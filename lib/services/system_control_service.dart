import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';

/// Windows 系统控制服务（音量 / 亮度）
class SystemControlService {
  SystemControlService._();

  // ══════════════════════════════════════════════════════════════════════════
  // 音量控制 — PowerShell Core Audio
  // waveOut 只控制进程音量，不控制系统主音量
  // 用 PowerShell 直接操作 SndVol 的主音量
  // ══════════════════════════════════════════════════════════════════════════

  static double _cachedVolume = 0.75;
  static bool _volumeInited = false;

  /// 获取系统主音量 (0.0 ~ 1.0)
  static Future<double> getVolume() async {
    if (!_volumeInited) {
      _volumeInited = true;
      await _syncVolumeFromSystem();
    }
    return _cachedVolume;
  }

  /// 获取同步版本（UI 用）
  static double getVolumeSync() {
    if (!_volumeInited) {
      _volumeInited = true;
      _syncVolumeFromSystem();
    }
    return _cachedVolume;
  }

  /// 设置系统主音量 (0.0 ~ 1.0)
  static Future<void> setVolume(double volume) async {
    final v = volume.clamp(0.0, 1.0);
    _cachedVolume = v;
    final intVal = (v * 100).round();
    try {
      await Process.run('powershell', [
        '-NoProfile',
        '-Command',
        '''
\$wsh = New-Object -ComObject WScript.Shell
1..50 | ForEach-Object { \$wsh.SendKeys([char]174) }
1..$intVal | ForEach-Object { \$wsh.SendKeys([char]175) }
'''
      ]);
    } catch (e) {
      debugPrint('[SystemControl] setVolume error: $e');
    }
  }

  /// 从系统读取当前音量
  static Future<void> _syncVolumeFromSystem() async {
    try {
      final result = await Process.run('powershell', [
        '-NoProfile',
        '-Command',
        '''
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public class Audio {
  [DllImport("ole32.dll")]
  public static extern int CoInitialize(IntPtr pvReserved);
  [ComImport, Guid("5CDF2C82-841E-4546-9722-0CF74078229A"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
  interface IAudioEndpointVolume {
    int RegisterControlChangeNotify(IntPtr pNotify);
    int UnregisterControlChangeNotify(IntPtr pNotify);
    int GetChannelCount(out uint pnChannelCount);
    int SetMasterVolumeLevel(float fLevelDB, Guid pguidEventContext);
    int SetMasterVolumeLevelScalar(float fLevel, Guid pguidEventContext);
    int GetMasterVolumeLevel(out float pfLevelDB);
    int GetMasterVolumeLevelScalar(out float pfLevel);
    int SetChannelVolumeLevel(uint nChannel, float fLevelDB, Guid pguidEventContext);
    int SetChannelVolumeLevelScalar(uint nChannel, float fLevel, Guid pguidEventContext);
    int GetChannelVolumeLevel(uint nChannel, out float pfLevelDB);
    int GetChannelVolumeLevelScalar(uint nChannel, out float pfLevel);
    int SetMute([MarshalAs(UnmanagedType.Bool)] bool bMute, Guid pguidEventContext);
    int GetMute([MarshalAs(UnmanagedType.Bool)] out bool pbMute);
    int GetVolumeStepInfo(out uint pnStep, out uint pnStepCount);
    int VolumeStepUp(Guid pguidEventContext);
    int VolumeStepDown(Guid pguidEventContext);
    int QueryHardwareSupport(out uint pdwHardwareSupportMask);
    int GetVolumeRange(out float pflVolumeMindB, out float pflVolumeMaxdB, out float pflVolumeIncrementdB);
  }
  [ComImport, Guid("A95664D2-9614-4F35-A746-DE8DB63617E6"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
  interface IMMDeviceEnumerator {
    int EnumAudioEndpoints(int dataFlow, uint dwStateMask, out IntPtr ppDevices);
    int GetDefaultAudioEndpoint(int dataFlow, int role, out IntPtr ppEndpoint);
    int GetDevice(IntPtr pwstrId, out IntPtr ppDevice);
    int RegisterEndpointNotificationCallback(IntPtr pClient);
    int UnregisterEndpointNotificationCallback(IntPtr pClient);
  }
  [ComImport, Guid("D666063F-1587-4E43-81F1-B948E807363F"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
  interface IMMDevice {
    int Activate(ref Guid iid, uint dwClsCtx, IntPtr pActivationParams, [MarshalAs(UnmanagedType.IUnknown)] out object ppInterface);
  }
}
"@
[Audio]::CoInitialize([IntPtr]::Zero) | Out-Null
\$enumerator = New-Object -ComObject MMDeviceEnumerator
\$device = \$enumerator.GetDefaultAudioEndpoint(0, 0)
\$iid = [Guid]"5CDF2C82-841E-4546-9722-0CF74078229A"
\$volume = \$null
\$device.Activate([ref]\$iid, 23, [IntPtr]::Zero, [ref]\$volume) | Out-Null
\$vol = 0.0
\$volume.GetMasterVolumeLevelScalar([ref]\$vol)
Write-Output \$vol
'''
      ]);
      if (result.exitCode == 0) {
        final parsed = double.tryParse(result.stdout.toString().trim());
        if (parsed != null) {
          _cachedVolume = parsed.clamp(0.0, 1.0);
          debugPrint(
              '[SystemControl] 读取系统音量: ${(_cachedVolume * 100).round()}%');
        }
      } else {
        debugPrint('[SystemControl] 读取音量失败: ${result.stderr}');
      }
    } catch (e) {
      debugPrint('[SystemControl] _syncVolumeFromSystem error: $e');
    }
  }

  /// 静音/取消静音
  static double? _savedVolume;

  static Future<void> toggleMute() async {
    final current = getVolumeSync();
    if (current > 0) {
      _savedVolume = current;
      await setVolume(0);
    } else {
      await setVolume(_savedVolume ?? 0.75);
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // 亮度控制 — Gamma Ramp (gdi32.dll)
  // 通过修改显卡 gamma 曲线实现亮度调节，兼容性好，无需 DDC/CI
  // ══════════════════════════════════════════════════════════════════════════

  static final _gdi32 = DynamicLibrary.open('gdi32.dll');
  static final _user32 = DynamicLibrary.open('user32.dll');

  // HDC GetDC(HWND hWnd)
  static final _getDC = _user32.lookupFunction<IntPtr Function(IntPtr hWnd),
      int Function(int hWnd)>('GetDC');

  // BOOL ReleaseDC(HWND hWnd, HDC hDC)
  static final _releaseDC = _user32.lookupFunction<
      Int32 Function(IntPtr hWnd, IntPtr hDC),
      int Function(int hWnd, int hDC)>('ReleaseDC');

  // BOOL SetDeviceGammaRamp(HDC hDC, LPVOID lpRamp)
  static final _setGammaRamp = _gdi32.lookupFunction<
      Int32 Function(IntPtr hDC, Pointer<Uint16> lpRamp),
      int Function(int hDC, Pointer<Uint16> lpRamp)>('SetDeviceGammaRamp');

  // BOOL GetDeviceGammaRamp(HDC hDC, LPVOID lpRamp)
  static final _getGammaRamp = _gdi32.lookupFunction<
      Int32 Function(IntPtr hDC, Pointer<Uint16> lpRamp),
      int Function(int hDC, Pointer<Uint16> lpRamp)>('GetDeviceGammaRamp');

  static double _cachedBrightness = 0.7;
  static int? _hdc;

  /// 获取 HDC（仅获取一次）
  static int _getOrCreateDC() {
    if (_hdc != null) return _hdc!;
    _hdc = _getDC(0); // 0 = NULL HWND → 整个屏幕
    debugPrint('[SystemControl] Gamma Ramp HDC: ${_hdc}');
    return _hdc!;
  }

  /// 获取亮度缓存值
  static double getBrightness() => _cachedBrightness;

  /// 设置亮度 (0.0 ~ 1.0)
  static void setBrightness(double value) {
    final v = value.clamp(0.0, 1.0);
    _cachedBrightness = v;
    _applyGammaRamp(v);
  }

  /// 通过 Gamma Ramp 设置屏幕亮度
  /// ramp 有 3×256 个 uint16（R/G/B 各 256 项）
  static void _applyGammaRamp(double brightness) {
    try {
      final hdc = _getOrCreateDC();
      if (hdc == 0) {
        debugPrint('[SystemControl] 无法获取 DC');
        return;
      }

      final ramp = calloc<Uint16>(256 * 3);
      final b = brightness.clamp(0.01, 1.0); // 避免全黑

      for (int i = 0; i < 256; i++) {
        final val = (i * b * 257).round().clamp(0, 65535);
        ramp[i] = val; // R
        ramp[256 + i] = val; // G
        ramp[512 + i] = val; // B
      }

      final result = _setGammaRamp(hdc, ramp);
      calloc.free(ramp);

      if (result == 0) {
        debugPrint(
            '[SystemControl] SetDeviceGammaRamp 失败, brightness=$brightness');
      } else {
        debugPrint(
            '[SystemControl] Gamma Ramp 已设置: ${(brightness * 100).round()}%');
      }
    } catch (e) {
      debugPrint('[SystemControl] _applyGammaRamp error: $e');
    }
  }

  /// 释放资源
  static void disposeGamma() {
    if (_hdc != null && _hdc != 0) {
      _releaseDC(0, _hdc!);
      _hdc = null;
    }
  }
}
