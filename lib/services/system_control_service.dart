import 'dart:async';
import 'dart:ffi';
import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:win32/win32.dart';

// ══════════════════════════════════════════════════════════════════════════
// COM GUIDs
// ══════════════════════════════════════════════════════════════════════════

final _clsidMMDeviceEnumerator = calloc<GUID>()
  ..ref.setGUID('{BCDE0395-E52F-467C-8E3D-C4579291692E}');
final _iidMMDeviceEnumerator = calloc<GUID>()
  ..ref.setGUID('{A95664D2-9614-4F35-A746-DE8DB63617E6}');
final _iidAudioEndpointVolume = calloc<GUID>()
  ..ref.setGUID('{5CDF2C82-841E-4546-9722-0CF74078229A}');

// ══════════════════════════════════════════════════════════════════════════
// IAudioEndpointVolume vtable 原生签名
// ══════════════════════════════════════════════════════════════════════════
// IUnknown: QueryInterface(0), AddRef(1), Release(2)
// IAudioEndpointVolume:
//   7 = SetMasterVolumeLevelScalar
//   9 = GetMasterVolumeLevelScalar
//  14 = SetMute
//  15 = GetMute

typedef _SetVolScalarNative = Int32 Function(
    Pointer<COMObject> self, Float fLevel, Pointer<GUID> pguid);
typedef _SetVolScalar = int Function(
    Pointer<COMObject> self, double fLevel, Pointer<GUID> pguid);

typedef _GetVolScalarNative = Int32 Function(
    Pointer<COMObject> self, Pointer<Float> pfLevel);
typedef _GetVolScalar = int Function(
    Pointer<COMObject> self, Pointer<Float> pfLevel);

typedef _SetMuteNative = Int32 Function(
    Pointer<COMObject> self, Int32 bMute, Pointer<GUID> pguid);
typedef _SetMute = int Function(
    Pointer<COMObject> self, int bMute, Pointer<GUID> pguid);

typedef _GetMuteNative = Int32 Function(
    Pointer<COMObject> self, Pointer<Int32> pbMute);
typedef _GetMute = int Function(Pointer<COMObject> self, Pointer<Int32> pbMute);

// ══════════════════════════════════════════════════════════════════════════
// WinRT SMTC 类型定义
// ══════════════════════════════════════════════════════════════════════════

// WinRT 函数签名
typedef _RoInitializeNative = Int32 Function(Int32 aptType);
typedef _RoInitialize = int Function(int aptType);

typedef _RoGetActivationFactoryNative = Int32 Function(
    IntPtr activatableClassId, Pointer<GUID> iid, Pointer<Pointer> factory);
typedef _RoGetActivationFactory = int Function(
    int activatableClassId, Pointer<GUID> iid, Pointer<Pointer> factory);

typedef _WindowsCreateStringNative = Int32 Function(
    Pointer<Utf16> sourceString, Uint32 length, Pointer<IntPtr> string);
typedef _WindowsCreateString = int Function(
    Pointer<Utf16> sourceString, int length, Pointer<IntPtr> string);

typedef _WindowsDeleteStringNative = Int32 Function(IntPtr string);
typedef _WindowsDeleteString = int Function(int string);

typedef _WindowsGetStringRawBufferNative = Pointer<Utf16> Function(
    IntPtr string, Pointer<Uint32> length);
typedef _WindowsGetStringRawBuffer = Pointer<Utf16> Function(
    int string, Pointer<Uint32> length);

// ══════════════════════════════════════════════════════════════════════════
// 数据类
// ══════════════════════════════════════════════════════════════════════════

enum PlaybackStatus { playing, paused, stopped, unknown }

class MediaInfo {
  final String title;
  final String artist;
  final String album;
  final String albumArtist;
  final PlaybackStatus status;

  const MediaInfo({
    this.title = '',
    this.artist = '',
    this.album = '',
    this.albumArtist = '',
    this.status = PlaybackStatus.unknown,
  });

  bool get isEmpty => title.isEmpty && artist.isEmpty;

  @override
  String toString() => 'MediaInfo(title: $title, artist: $artist, '
      'album: $album, status: $status)';
}

// ══════════════════════════════════════════════════════════════════════════
// 系统控制服务
// ══════════════════════════════════════════════════════════════════════════

class SystemControlService {
  SystemControlService._();

  // ───────────── 音量 (Core Audio API) ─────────────────────────────

  static Pointer<COMObject>? _epVolume;
  static double _cachedVolume = 0.5;
  static bool _cachedMute = false;
  static bool _comInit = false;

  static void initVolume() {
    try {
      if (!_comInit) {
        CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
        _comInit = true;
      }

      using((arena) {
        final enumPtr = arena<Pointer<COMObject>>();
        var hr = CoCreateInstance(
          _clsidMMDeviceEnumerator,
          nullptr,
          CLSCTX_ALL,
          _iidMMDeviceEnumerator,
          enumPtr.cast(),
        );
        if (hr != S_OK) return;
        final enumerator = IMMDeviceEnumerator(enumPtr.value);

        final devPtr = arena<Pointer<COMObject>>();
        hr = enumerator.getDefaultAudioEndpoint(
            eRender, eConsole, devPtr.cast());
        if (hr != S_OK) {
          enumerator.release();
          return;
        }
        final device = IMMDevice(devPtr.value);

        final volPtr = arena<Pointer<COMObject>>();
        hr = device.activate(
          _iidAudioEndpointVolume,
          CLSCTX_ALL,
          nullptr,
          volPtr.cast(),
        );
        device.release();
        enumerator.release();
        if (hr != S_OK) return;

        _epVolume = volPtr.value;
        IUnknown(_epVolume!).addRef();
        _cachedVolume = _readVolScalar();
        _cachedMute = _readMute();
      });
    } catch (e) {
      debugPrint('[SCS] initVolume error: $e');
    }
  }

  static Pointer<IntPtr> get _volVtbl => _epVolume!.ref.vtable;

  static _GetVolScalar _fnGetVolScalar() =>
      Pointer<NativeFunction<_GetVolScalarNative>>.fromAddress(_volVtbl[9])
          .asFunction<_GetVolScalar>();

  static _SetVolScalar _fnSetVolScalar() =>
      Pointer<NativeFunction<_SetVolScalarNative>>.fromAddress(_volVtbl[7])
          .asFunction<_SetVolScalar>();

  static _GetMute _fnGetMute() =>
      Pointer<NativeFunction<_GetMuteNative>>.fromAddress(_volVtbl[15])
          .asFunction<_GetMute>();

  static _SetMute _fnSetMute() =>
      Pointer<NativeFunction<_SetMuteNative>>.fromAddress(_volVtbl[14])
          .asFunction<_SetMute>();

  static double _readVolScalar() {
    if (_epVolume == null) return _cachedVolume;
    try {
      final p = calloc<Float>();
      if (_fnGetVolScalar()(_epVolume!, p) == S_OK) {
        final v = p.value.clamp(0.0, 1.0);
        calloc.free(p);
        return v;
      }
      calloc.free(p);
    } catch (_) {}
    return _cachedVolume;
  }

  static bool _readMute() {
    if (_epVolume == null) return _cachedMute;
    try {
      final p = calloc<Int32>();
      if (_fnGetMute()(_epVolume!, p) == S_OK) {
        final v = p.value != 0;
        calloc.free(p);
        return v;
      }
      calloc.free(p);
    } catch (_) {}
    return _cachedMute;
  }

  static double getVolumeSync() => _cachedVolume;
  static bool isMuted() => _cachedMute;

  static void setVolume(double target) {
    _cachedVolume = target.clamp(0.0, 1.0);
    _writeVolScalar(_cachedVolume);
  }

  static void commitVolume(double target) => setVolume(target);

  static void _writeVolScalar(double level) {
    if (_epVolume == null) return;
    try {
      _fnSetVolScalar()(_epVolume!, level, nullptr);
    } catch (e) {
      debugPrint('[SCS] setVolume error: $e');
    }
  }

  static void toggleMute() {
    _cachedMute = !_cachedMute;
    _writeMute(_cachedMute);
  }

  static void _writeMute(bool mute) {
    if (_epVolume == null) return;
    try {
      _fnSetMute()(_epVolume!, mute ? 1 : 0, nullptr);
    } catch (e) {
      debugPrint('[SCS] setMute error: $e');
    }
  }

  // ───────────── 亮度 (Monitor Configuration API) ─────────────────

  static int _physHandle = 0;
  static int _minBri = 0;
  static int _maxBri = 100;
  static double _cachedBrightness = 0.7;
  static bool _briSupported = false;

  static void initBrightness() {
    try {
      final hMon =
          MonitorFromWindow(GetDesktopWindow(), MONITOR_DEFAULTTOPRIMARY);

      final cnt = calloc<Uint32>();
      if (GetNumberOfPhysicalMonitorsFromHMONITOR(hMon, cnt) == 0) {
        calloc.free(cnt);
        return;
      }
      final n = cnt.value;
      calloc.free(cnt);
      if (n == 0) return;

      final arr = calloc<PHYSICAL_MONITOR>(n);
      if (GetPhysicalMonitorsFromHMONITOR(hMon, n, arr) == 0) {
        calloc.free(arr);
        return;
      }
      _physHandle = arr.cast<IntPtr>().value;

      final mn = calloc<Uint32>();
      final cr = calloc<Uint32>();
      final mx = calloc<Uint32>();
      if (GetMonitorBrightness(_physHandle, mn, cr, mx) != 0) {
        _minBri = mn.value;
        _maxBri = mx.value;
        _briSupported = true;
        final range = _maxBri - _minBri;
        if (range > 0) _cachedBrightness = (cr.value - _minBri) / range;
      } else {
        debugPrint('[SCS] Monitor does not support DDC/CI brightness');
      }
      calloc.free(mn);
      calloc.free(cr);
      calloc.free(mx);
      calloc.free(arr);
    } catch (e) {
      debugPrint('[SCS] initBrightness error: $e');
    }
  }

  static double getBrightness() => _cachedBrightness;

  static void setBrightness(double value) {
    _cachedBrightness = value.clamp(0.0, 1.0);
    if (!_briSupported || _physHandle == 0) return;
    try {
      final range = _maxBri - _minBri;
      SetMonitorBrightness(
          _physHandle, (_minBri + _cachedBrightness * range).round());
    } catch (e) {
      debugPrint('[SCS] setBrightness error: $e');
    }
  }

  static void disposeBrightness() {
    _physHandle = 0;
    _briSupported = false;
  }

  static void disposeGamma() => disposeBrightness();

  // ════════════════════════════════════════════════════════════════════════
  // 媒体播放器状态 — WinRT SMTC
  // ════════════════════════════════════════════════════════════════════════

  static MediaInfo _mediaInfo = const MediaInfo();
  static Timer? _mediaTimer;
  static bool _winrtInit = false;

  // WinRT 函数指针
  static late final _RoInitialize _roInit;
  static late final _RoGetActivationFactory _roGetFactory;
  static late final _WindowsCreateString _winCreateStr;
  static late final _WindowsDeleteString _winDeleteStr;
  static late final _WindowsGetStringRawBuffer _winGetStrBuf;

  // SMTC Manager 静态接口 IID: {3E4A4642-560D-5270-ADF8-2C8C8E1E9E8E}
  static final _iidSMTCManagerStatics = calloc<GUID>()
    ..ref.setGUID('{3E4A4642-560D-5270-ADF8-2C8C8E1E9E8E}');

  // RuntimeClass HSTRING
  static int _hstrSMTCClass = 0;

  /// 初始化 WinRT 并加载所需函数
  static void _initWinRT() {
    if (_winrtInit) return;

    final combase = DynamicLibrary.open('combase.dll');
    _roInit = combase
        .lookupFunction<_RoInitializeNative, _RoInitialize>('RoInitialize');
    _roGetFactory = combase.lookupFunction<_RoGetActivationFactoryNative,
        _RoGetActivationFactory>('RoGetActivationFactory');
    _winCreateStr = combase.lookupFunction<_WindowsCreateStringNative,
        _WindowsCreateString>('WindowsCreateString');
    _winDeleteStr = combase.lookupFunction<_WindowsDeleteStringNative,
        _WindowsDeleteString>('WindowsDeleteString');
    _winGetStrBuf = combase.lookupFunction<_WindowsGetStringRawBufferNative,
        _WindowsGetStringRawBuffer>('WindowsGetStringRawBuffer');

    // RoInitialize(RO_INIT_MULTITHREADED = 0)
    _roInit(0);

    // 创建 RuntimeClass 名称的 HSTRING
    final className =
        'Windows.Media.Control.GlobalSystemMediaTransportControlsSessionManager'
            .toNativeUtf16();
    final hstrPtr = calloc<IntPtr>();
    _winCreateStr(className, 138, hstrPtr); // 138 = char count
    _hstrSMTCClass = hstrPtr.value;
    calloc.free(hstrPtr);
    calloc.free(className);

    _winrtInit = true;
  }

  /// 从 HSTRING 读取 Dart 字符串
  static String _hstringToDart(int hstring) {
    if (hstring == 0) return '';
    final lenPtr = calloc<Uint32>();
    final buf = _winGetStrBuf(hstring, lenPtr);
    final result = buf.toDartString();
    calloc.free(lenPtr);
    return result;
  }

  static MediaInfo getMediaInfo() => _mediaInfo;

  static void startMediaPolling({int intervalMs = 2000}) {
    _mediaTimer?.cancel();
    _mediaTimer =
        Timer.periodic(Duration(milliseconds: intervalMs), (_) => _pollSMTC());
    _pollSMTC();
  }

  static void stopMediaPolling() {
    _mediaTimer?.cancel();
    _mediaTimer = null;
  }

  /// 通过 WinRT SMTC 获取媒体信息
  static void _pollSMTC() {
    try {
      _initWinRT();

      // 获取 IActivationFactory
      final factoryPtr = calloc<Pointer<COMObject>>();
      final hr = _roGetFactory(
          _hstrSMTCClass, _iidSMTCManagerStatics, factoryPtr.cast());
      if (hr != S_OK) {
        calloc.free(factoryPtr);
        _fallbackMediaInfo();
        return;
      }

      final factory = factoryPtr.value;
      calloc.free(factoryPtr);

      // IGlobalSystemMediaTransportControlsSessionManagerStatics vtable:
      // IUnknown(0-2), IInspectable(3-5), RequestAsync(6)
      // RequestAsync 返回 IAsyncOperation<SessionManager>
      final asyncOpPtr = calloc<Pointer<COMObject>>();
      final requestAsyncAddr = factory.ref.vtable[6];
      final requestAsyncFn = Pointer<
                  NativeFunction<
                      Int32 Function(Pointer<COMObject> self,
                          Pointer<Pointer<COMObject>> result)>>.fromAddress(
              requestAsyncAddr)
          .asFunction<
              int Function(Pointer<COMObject> self,
                  Pointer<Pointer<COMObject>> result)>();

      final hr2 = requestAsyncFn(factory, asyncOpPtr);
      IUnknown(factory).release();
      if (hr2 != S_OK) {
        calloc.free(asyncOpPtr);
        _fallbackMediaInfo();
        return;
      }

      // 等待异步操作完成
      final sessionManager = _waitForAsyncOperation(asyncOpPtr.value);
      calloc.free(asyncOpPtr);
      if (sessionManager == null) {
        _fallbackMediaInfo();
        return;
      }

      // GetCurrentSession()
      final sessionPtr = calloc<Pointer<COMObject>>();
      // vtable[6] = GetCurrentSession (IUnknown 0-2, IInspectable 3-5, GetCurrentSession 6)
      final getCurSessionAddr = sessionManager.ref.vtable[6];
      final getCurSessionFn = Pointer<
                  NativeFunction<
                      Int32 Function(Pointer<COMObject> self,
                          Pointer<Pointer<COMObject>> result)>>.fromAddress(
              getCurSessionAddr)
          .asFunction<
              int Function(Pointer<COMObject> self,
                  Pointer<Pointer<COMObject>> result)>();

      final hr3 = getCurSessionFn(sessionManager, sessionPtr);
      IUnknown(sessionManager).release();
      if (hr3 != S_OK) {
        calloc.free(sessionPtr);
        _mediaInfo = const MediaInfo(status: PlaybackStatus.unknown);
        return;
      }

      final session = sessionPtr.value;
      calloc.free(sessionPtr);

      // GetPlaybackInfo() - vtable[8]
      final playbackInfoPtr = calloc<Pointer<COMObject>>();
      final getPlaybackInfoAddr = session.ref.vtable[8];
      final getPlaybackInfoFn = Pointer<
                  NativeFunction<
                      Int32 Function(Pointer<COMObject> self,
                          Pointer<Pointer<COMObject>> result)>>.fromAddress(
              getPlaybackInfoAddr)
          .asFunction<
              int Function(Pointer<COMObject> self,
                  Pointer<Pointer<COMObject>> result)>();

      final hr4 = getPlaybackInfoFn(session, playbackInfoPtr);
      PlaybackStatus status = PlaybackStatus.unknown;
      if (hr4 == S_OK) {
        final playbackInfo = playbackInfoPtr.value;
        // PlaybackStatus: vtable[6] = get_PlaybackStatus
        // 返回枚举值: 0=Closed, 1=Opened, 2=Changing, 3=Stopped, 4=Paused, 5=Playing
        final getStatusAddr = playbackInfo.ref.vtable[6];
        final getStatusFn = Pointer<
                NativeFunction<
                    Int32 Function(Pointer<COMObject> self,
                        Pointer<Int32> result)>>.fromAddress(getStatusAddr)
            .asFunction<
                int Function(Pointer<COMObject> self, Pointer<Int32> result)>();

        final statusPtr = calloc<Int32>();
        if (getStatusFn(playbackInfo, statusPtr) == S_OK) {
          switch (statusPtr.value) {
            case 5:
              status = PlaybackStatus.playing;
              break;
            case 4:
              status = PlaybackStatus.paused;
              break;
            case 3:
              status = PlaybackStatus.stopped;
              break;
            default:
              status = PlaybackStatus.unknown;
          }
        }
        calloc.free(statusPtr);
        IUnknown(playbackInfo).release();
      }
      calloc.free(playbackInfoPtr);

      // TryGetMediaPropertiesAsync() - vtable[9]
      final mediaPropsAsyncPtr = calloc<Pointer<COMObject>>();
      final tryGetMediaAddr = session.ref.vtable[9];
      final tryGetMediaFn = Pointer<
                  NativeFunction<
                      Int32 Function(Pointer<COMObject> self,
                          Pointer<Pointer<COMObject>> result)>>.fromAddress(
              tryGetMediaAddr)
          .asFunction<
              int Function(Pointer<COMObject> self,
                  Pointer<Pointer<COMObject>> result)>();

      final hr5 = tryGetMediaFn(session, mediaPropsAsyncPtr);
      IUnknown(session).release();

      String title = '';
      String artist = '';
      String album = '';
      String albumArtist = '';

      if (hr5 == S_OK) {
        final mediaProps = _waitForAsyncOperation(mediaPropsAsyncPtr.value);
        calloc.free(mediaPropsAsyncPtr);

        if (mediaProps != null) {
          // 读取 Title - vtable[6] = get_Title
          title = _readHstringProperty(mediaProps, 6);
          // 读取 Artist - vtable[7] = get_Artist
          artist = _readHstringProperty(mediaProps, 7);
          // 读取 AlbumTitle - vtable[8] = get_AlbumTitle
          album = _readHstringProperty(mediaProps, 8);
          // 读取 AlbumArtist - vtable[9] = get_AlbumArtist
          albumArtist = _readHstringProperty(mediaProps, 9);

          IUnknown(mediaProps).release();
        }
      } else {
        calloc.free(mediaPropsAsyncPtr);
      }

      _mediaInfo = MediaInfo(
        title: title,
        artist: artist.isNotEmpty ? artist : albumArtist,
        album: album,
        albumArtist: albumArtist,
        status: status,
      );
    } catch (e) {
      debugPrint('[SCS] pollSMTC error: $e');
      _fallbackMediaInfo();
    }
  }

  /// 读取 WinRT 对象的 HSTRING 属性
  static String _readHstringProperty(Pointer<COMObject> obj, int vtableIndex) {
    try {
      final getPropAddr = obj.ref.vtable[vtableIndex];
      final getPropFn = Pointer<
              NativeFunction<
                  Int32 Function(Pointer<COMObject> self,
                      Pointer<IntPtr> result)>>.fromAddress(getPropAddr)
          .asFunction<
              int Function(Pointer<COMObject> self, Pointer<IntPtr> result)>();

      final hstrPtr = calloc<IntPtr>();
      if (getPropFn(obj, hstrPtr) == S_OK) {
        final dartStr = _hstringToDart(hstrPtr.value);
        if (hstrPtr.value != 0) _winDeleteStr(hstrPtr.value);
        calloc.free(hstrPtr);
        return dartStr;
      }
      calloc.free(hstrPtr);
    } catch (_) {}
    return '';
  }

  /// 等待 IAsyncOperation 完成并获取结果
  /// IAsyncOperation vtable:
  ///   IUnknown: 0-2
  ///   IAsyncInfo: 3=get_Id, 4=get_Status, 5=get_ErrorCode, 6=Cancel, 7=Close
  ///   IAsyncOperation: 8=put_Completed, 9=get_Completed, 10=GetResults
  static Pointer<COMObject>? _waitForAsyncOperation(
      Pointer<COMObject> asyncOp) {
    try {
      // 使用轮询方式等待完成
      // get_Status - vtable[4]
      final getStatusAddr = asyncOp.ref.vtable[4];
      final getStatusFn = Pointer<
              NativeFunction<
                  Int32 Function(Pointer<COMObject> self,
                      Pointer<Int32> result)>>.fromAddress(getStatusAddr)
          .asFunction<
              int Function(Pointer<COMObject> self, Pointer<Int32> result)>();

      // AsyncStatus: 0=Started, 1=Completed, 2=Cancelled, 3=Error
      final statusPtr = calloc<Int32>();
      final startTime = DateTime.now();

      while (true) {
        if (getStatusFn(asyncOp, statusPtr) != S_OK) {
          calloc.free(statusPtr);
          IUnknown(asyncOp).release();
          return null;
        }

        if (statusPtr.value == 1) break; // Completed
        if (statusPtr.value >= 2) {
          // Cancelled or Error
          calloc.free(statusPtr);
          IUnknown(asyncOp).release();
          return null;
        }

        // 超时 5 秒
        if (DateTime.now().difference(startTime).inMilliseconds > 5000) {
          calloc.free(statusPtr);
          IUnknown(asyncOp).release();
          return null;
        }

        Sleep(10);
      }
      calloc.free(statusPtr);

      // GetResults - vtable[10]
      final getResultsAddr = asyncOp.ref.vtable[10];
      final getResultsFn = Pointer<
                  NativeFunction<
                      Int32 Function(Pointer<COMObject> self,
                          Pointer<Pointer<COMObject>> result)>>.fromAddress(
              getResultsAddr)
          .asFunction<
              int Function(Pointer<COMObject> self,
                  Pointer<Pointer<COMObject>> result)>();

      final resultPtr = calloc<Pointer<COMObject>>();
      final hr = getResultsFn(asyncOp, resultPtr);
      IUnknown(asyncOp).release();

      if (hr == S_OK) {
        final result = resultPtr.value;
        calloc.free(resultPtr);
        return result;
      }
      calloc.free(resultPtr);
    } catch (e) {
      debugPrint('[SCS] async operation error: $e');
      try {
        IUnknown(asyncOp).release();
      } catch (_) {}
    }
    return null;
  }

  /// 降级方案：通过窗口标题识别媒体播放器
  static void _fallbackMediaInfo() {
    try {
      final hwnd = GetForegroundWindow();
      if (hwnd == 0) return;
      final len = GetWindowTextLength(hwnd);
      if (len == 0) return;
      final buf = wsalloc(len + 1);
      GetWindowText(hwnd, buf, len + 1);
      final title = buf.toDartString();
      free(buf);

      const players = [
        'Spotify',
        '网易云音乐',
        'NetEase',
        'QQ音乐',
        'QQ Music',
        '酷狗',
        'KuGou',
        '酷我',
        'KuWo',
        'foobar',
        'VLC',
        'AIMP',
        'MusicBee',
        'iTunes',
        'Media Player',
      ];
      if (players.any((p) => title.contains(p))) {
        final parts = title.split(' - ');
        if (parts.length >= 2) {
          _mediaInfo = MediaInfo(
            title: parts.sublist(1).join(' - ').trim(),
            artist: parts[0].trim(),
            status: PlaybackStatus.playing,
          );
          return;
        }
      }
      _mediaInfo = const MediaInfo(status: PlaybackStatus.unknown);
    } catch (_) {}
  }

  // ───────────── 全局清理 ──────────────────────────────────────────

  static void dispose() {
    stopMediaPolling();
    disposeBrightness();

    if (_epVolume != null) {
      try {
        IUnknown(_epVolume!).release();
      } catch (_) {}
      _epVolume = null;
    }

    if (_hstrSMTCClass != 0) {
      try {
        _winDeleteStr(_hstrSMTCClass);
      } catch (_) {}
      _hstrSMTCClass = 0;
    }
  }
}
