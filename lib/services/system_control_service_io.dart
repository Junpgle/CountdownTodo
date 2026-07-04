import 'dart:async';
import 'dart:ffi';
import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:win32/win32.dart';

// ══════════════════════════════════════════════════════════════════════════
// WinRT 类型
// ══════════════════════════════════════════════════════════════════════════

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
  String toString() => 'MediaInfo(title: "$title", artist: "$artist", '
      'album: "$album", albumArtist: "$albumArtist", status: $status)';
}

// ══════════════════════════════════════════════════════════════════════════
// 系统控制服务
// ══════════════════════════════════════════════════════════════════════════

class SystemControlService {
  SystemControlService._();

  // ───────────── 音量 ─────────────────────────────────────────────
  // 使用 keybd_event 虚拟按键方式（稳定可靠）

  static final _user32 = DynamicLibrary.open('user32.dll');

  static final _keybdEvent = _user32.lookupFunction<
      Void Function(Uint8 bVk, Uint8 bScan, Uint32 dwFlags, IntPtr dwExtraInfo),
      void Function(
          int bVk, int bScan, int dwFlags, int dwExtraInfo)>('keybd_event');

  static const _KEYEVENTF_KEYUP = 0x0002;
  static const _KEYEVENTF_SILENT = 0x0004;
  static const _VK_VOLUME_UP = 0xAF;
  static const _VK_VOLUME_DOWN = 0xAE;
  static const _VK_VOLUME_MUTE = 0xAD;

  static final _winmm = DynamicLibrary.open('winmm.dll');
  static final _waveOutGetVolume = _winmm.lookupFunction<
      Uint32 Function(Uint32, Pointer<Uint32>),
      int Function(int, Pointer<Uint32>)>('waveOutGetVolume');

  static double _cachedVolume = 0.5;
  static double? _savedVolume;
  static int _lastSentVolSteps = -1;

  static void _sendKey(int vk) {
    _keybdEvent(vk, 0, _KEYEVENTF_SILENT, 0);
    _keybdEvent(vk, 0, _KEYEVENTF_SILENT | _KEYEVENTF_KEYUP, 0);
  }

  static double _readSystemVolume() {
    try {
      final ptr = calloc<Uint32>();
      _waveOutGetVolume(0, ptr);
      final val = ptr.value;
      calloc.free(ptr);
      final left = val & 0xFFFF;
      final right = (val >> 16) & 0xFFFF;
      return ((left + right) / 2) / 0xFFFF;
    } catch (_) {
      return 0.5;
    }
  }

  static double getVolumeSync() => _cachedVolume;

  static void initVolume() {
    debugPrint('[SCS] initVolume start');
    _cachedVolume = _readSystemVolume();
    _lastSentVolSteps = (_cachedVolume * 50).round();
    debugPrint(
        '[SCS] initVolume done: vol=$_cachedVolume, steps=$_lastSentVolSteps');
  }

  static void setVolume(double target) {
    final t = target.clamp(0.0, 1.0);
    debugPrint('[SCS] setVolume($t)');
    _cachedVolume = t;
    final newSteps = (t * 50).round();

    if (_lastSentVolSteps < 0) _lastSentVolSteps = newSteps;
    final diff = newSteps - _lastSentVolSteps;
    if (diff.abs() < 2) return;

    _lastSentVolSteps = newSteps;
    if (diff > 0) {
      for (var i = 0; i < diff; i++) {
        _sendKey(_VK_VOLUME_UP);
      }
    } else {
      for (var i = 0; i < -diff; i++) {
        _sendKey(_VK_VOLUME_DOWN);
      }
    }
  }

  static void commitVolume(double target) {
    final t = target.clamp(0.0, 1.0);
    debugPrint('[SCS] commitVolume($t)');
    _cachedVolume = t;
    final newSteps = (t * 50).round();
    if (_lastSentVolSteps < 0) _lastSentVolSteps = newSteps;
    final diff = newSteps - _lastSentVolSteps;
    if (diff == 0) return;
    _lastSentVolSteps = newSteps;
    if (diff > 0) {
      for (var i = 0; i < diff; i++) {
        _sendKey(_VK_VOLUME_UP);
      }
    } else {
      for (var i = 0; i < -diff; i++) {
        _sendKey(_VK_VOLUME_DOWN);
      }
    }
  }

  static bool isMuted() => _cachedVolume <= 0.01;

  static void toggleMute() {
    debugPrint('[SCS] toggleMute, current vol=$_cachedVolume');
    if (_cachedVolume > 0) {
      _savedVolume = _cachedVolume;
      _sendKey(_VK_VOLUME_MUTE);
      _cachedVolume = 0;
    } else {
      _sendKey(_VK_VOLUME_MUTE);
      _cachedVolume = _savedVolume ?? 0.5;
    }
  }

  // ───────────── 亮度 (Monitor Configuration API) ─────────────────

  static int _physHandle = 0;
  static int _minBri = 0;
  static int _maxBri = 100;
  static double _cachedBrightness = 0.7;
  static bool _briSupported = false;

  static void initBrightness() {
    debugPrint('[SCS] initBrightness start');
    try {
      final hMon =
          MonitorFromWindow(GetDesktopWindow(), MONITOR_DEFAULTTOPRIMARY);
      debugPrint('[SCS] hMonitor: $hMon');

      final cnt = calloc<Uint32>();
      if (GetNumberOfPhysicalMonitorsFromHMONITOR(hMon, cnt) == 0) {
        debugPrint('[SCS] GetNumberOfPhysicalMonitors failed');
        calloc.free(cnt);
        return;
      }
      final n = cnt.value;
      calloc.free(cnt);
      debugPrint('[SCS] physical monitor count: $n');
      if (n == 0) return;

      final arr = calloc<PHYSICAL_MONITOR>(n);
      if (GetPhysicalMonitorsFromHMONITOR(hMon, n, arr) == 0) {
        debugPrint('[SCS] GetPhysicalMonitors failed');
        calloc.free(arr);
        return;
      }
      _physHandle = arr.cast<IntPtr>().value;
      debugPrint('[SCS] physHandle: $_physHandle');

      final mn = calloc<Uint32>();
      final cr = calloc<Uint32>();
      final mx = calloc<Uint32>();
      if (GetMonitorBrightness(_physHandle, mn, cr, mx) != 0) {
        _minBri = mn.value;
        _maxBri = mx.value;
        _briSupported = true;
        final range = _maxBri - _minBri;
        if (range > 0) _cachedBrightness = (cr.value - _minBri) / range;
        debugPrint(
            '[SCS] brightness range: $_minBri~$_maxBri, current: ${cr.value}');
      } else {
        debugPrint('[SCS] Monitor does not support DDC/CI brightness');
      }
      calloc.free(mn);
      calloc.free(cr);
      calloc.free(mx);
      calloc.free(arr);
    } catch (e, st) {
      debugPrint('[SCS] initBrightness error: $e\n$st');
    }
  }

  static double getBrightness() => _cachedBrightness;

  static void setBrightness(double value) {
    _cachedBrightness = value.clamp(0.0, 1.0);
    debugPrint(
        '[SCS] setBrightness($_cachedBrightness) supported=$_briSupported');
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

  static late final _RoInitialize _roInit;
  static late final _RoGetActivationFactory _roGetFactory;
  static late final _WindowsCreateString _winCreateStr;
  static late final _WindowsDeleteString _winDeleteStr;
  static late final _WindowsGetStringRawBuffer _winGetStrBuf;

  static final _iidSMTCManagerStatics = calloc<GUID>()
    ..ref.setGUID('{3E4A4642-560D-5270-ADF8-2C8C8E1E9E8E}');
  static int _hstrSMTCClass = 0;

  static void _initWinRT() {
    if (_winrtInit) return;
    debugPrint('[SCS] _initWinRT start');
    try {
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

      final hr = _roInit(0);
      debugPrint('[SCS] RoInitialize: 0x${hr.toRadixString(16)}');

      final className =
          'Windows.Media.Control.GlobalSystemMediaTransportControlsSessionManager'
              .toNativeUtf16();
      final hstrPtr = calloc<IntPtr>();
      final hr2 = _winCreateStr(className, 138, hstrPtr);
      debugPrint('[SCS] WindowsCreateString: 0x${hr2.toRadixString(16)}');
      _hstrSMTCClass = hstrPtr.value;
      calloc.free(hstrPtr);
      calloc.free(className);

      _winrtInit = true;
      debugPrint('[SCS] _initWinRT done, hstr=$_hstrSMTCClass');
    } catch (e, st) {
      debugPrint('[SCS] _initWinRT error: $e\n$st');
    }
  }

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
    debugPrint('[SCS] startMediaPolling interval=$intervalMs');
    _mediaTimer?.cancel();
    _mediaTimer =
        Timer.periodic(Duration(milliseconds: intervalMs), (_) => _pollSMTC());
    _pollSMTC();
  }

  static void stopMediaPolling() {
    _mediaTimer?.cancel();
    _mediaTimer = null;
  }

  static void _pollSMTC() {
    debugPrint('[SCS] === _pollSMTC >>> ===');
    try {
      _initWinRT();

      if (!_winrtInit || _hstrSMTCClass == 0) {
        debugPrint('[SCS] WinRT not ready, fallback');
        _fallbackMediaInfo();
        return;
      }

      // ── Step 1: RoGetActivationFactory ──
      debugPrint('[SCS] [1] RoGetActivationFactory...');
      final factoryPtr = calloc<Pointer<COMObject>>();
      final hr = _roGetFactory(
          _hstrSMTCClass, _iidSMTCManagerStatics, factoryPtr.cast());
      debugPrint('[SCS] [1] result: 0x${hr.toRadixString(16)}');
      if (hr != S_OK) {
        calloc.free(factoryPtr);
        debugPrint('[SCS] factory failed, fallback');
        _fallbackMediaInfo();
        return;
      }
      final factory = factoryPtr.value;
      calloc.free(factoryPtr);
      debugPrint('[SCS] [1] factory OK: $factory');

      // ── Step 2: RequestAsync ──
      // IGlobalSystemMediaTransportControlsSessionManagerStatics vtable:
      // IUnknown(0-2), IInspectable(3-5), RequestAsync(6)
      debugPrint('[SCS] [2] RequestAsync...');
      final asyncOpPtr = calloc<Pointer<COMObject>>();
      final requestAddr = factory.ref.vtable[6];
      debugPrint('[SCS] [2] vtable[6] addr: $requestAddr');

      final requestFn = Pointer<
                  NativeFunction<
                      Int32 Function(Pointer<COMObject> self,
                          Pointer<Pointer<COMObject>> result)>>.fromAddress(
              requestAddr)
          .asFunction<
              int Function(Pointer<COMObject> self,
                  Pointer<Pointer<COMObject>> result)>();

      final hr2 = requestFn(factory, asyncOpPtr);
      debugPrint('[SCS] [2] RequestAsync result: 0x${hr2.toRadixString(16)}');
      IUnknown(factory).release();

      if (hr2 != S_OK) {
        calloc.free(asyncOpPtr);
        debugPrint('[SCS] RequestAsync failed, fallback');
        _fallbackMediaInfo();
        return;
      }

      // ── Step 3: 等待异步完成 ──
      debugPrint('[SCS] [3] waiting async op...');
      final sessionManager = _waitForAsync(asyncOpPtr.value);
      calloc.free(asyncOpPtr);
      debugPrint('[SCS] [3] sessionManager: $sessionManager');
      if (sessionManager == null) {
        debugPrint('[SCS] sessionManager null, fallback');
        _fallbackMediaInfo();
        return;
      }

      // ── Step 4: GetCurrentSession ──
      // IGlobalSystemMediaTransportControlsSessionManager vtable:
      // IUnknown(0-2), IInspectable(3-5), GetCurrentSession(6)
      debugPrint('[SCS] [4] GetCurrentSession...');
      final sessionPtr = calloc<Pointer<COMObject>>();
      final getSessionAddr = sessionManager.ref.vtable[6];
      debugPrint('[SCS] [4] vtable[6] addr: $getSessionAddr');
      final getSessionFn = Pointer<
                  NativeFunction<
                      Int32 Function(Pointer<COMObject> self,
                          Pointer<Pointer<COMObject>> result)>>.fromAddress(
              getSessionAddr)
          .asFunction<
              int Function(Pointer<COMObject> self,
                  Pointer<Pointer<COMObject>> result)>();

      final hr3 = getSessionFn(sessionManager, sessionPtr);
      debugPrint('[SCS] [4] GetCurrentSession: 0x${hr3.toRadixString(16)}');
      IUnknown(sessionManager).release();

      if (hr3 != S_OK) {
        calloc.free(sessionPtr);
        debugPrint('[SCS] no current session');
        _mediaInfo = const MediaInfo(status: PlaybackStatus.unknown);
        return;
      }

      final session = sessionPtr.value;
      calloc.free(sessionPtr);
      debugPrint('[SCS] [4] session OK: $session');

      // ── Step 5: GetPlaybackInfo ──
      // IGlobalSystemMediaTransportControlsSession vtable:
      // IUnknown(0-2), IInspectable(3-5)
      // 6: get_SourceAppUserModelId
      // 7: get_DiscSession
      // 8: GetPlaybackInfo
      // 9: GetTimelineProperties
      // 10: TrySkipAsync / TryChangePlaybackModeAsync (varies)
      // ...
      debugPrint('[SCS] [5] GetPlaybackInfo...');
      PlaybackStatus status = PlaybackStatus.unknown;
      final playbackInfoPtr = calloc<Pointer<COMObject>>();
      final getPlaybackAddr = session.ref.vtable[8];
      debugPrint('[SCS] [5] vtable[8] addr: $getPlaybackAddr');
      final getPlaybackFn = Pointer<
                  NativeFunction<
                      Int32 Function(Pointer<COMObject> self,
                          Pointer<Pointer<COMObject>> result)>>.fromAddress(
              getPlaybackAddr)
          .asFunction<
              int Function(Pointer<COMObject> self,
                  Pointer<Pointer<COMObject>> result)>();

      final hr4 = getPlaybackFn(session, playbackInfoPtr);
      debugPrint('[SCS] [5] GetPlaybackInfo: 0x${hr4.toRadixString(16)}');
      if (hr4 == S_OK) {
        final playbackInfo = playbackInfoPtr.value;
        // IGlobalSystemMediaTransportControlsSessionPlaybackInfo vtable:
        // IUnknown(0-2), IInspectable(3-5), get_Controls(6), get_PlaybackStatus(7),
        // get_PlaybackType(8), get_AutoRepeatMode(9), get_ShuffleEnabled(10), get_PlaybackRate(11)
        final getStatusAddr = playbackInfo.ref.vtable[7];
        debugPrint(
            '[SCS] [5] get_PlaybackStatus vtable[7] addr: $getStatusAddr');
        final getStatusFn = Pointer<
                NativeFunction<
                    Int32 Function(Pointer<COMObject> self,
                        Pointer<Int32> result)>>.fromAddress(getStatusAddr)
            .asFunction<
                int Function(Pointer<COMObject> self, Pointer<Int32> result)>();

        final statusPtr = calloc<Int32>();
        final hrS = getStatusFn(playbackInfo, statusPtr);
        debugPrint(
            '[SCS] [5] playback status: 0x${hrS.toRadixString(16)} val=${statusPtr.value}');
        if (hrS == S_OK) {
          switch (statusPtr.value) {
            case 4:
              status = PlaybackStatus.playing;
              break;
            case 5:
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

      // ── Step 6: TryGetMediaPropertiesAsync ──
      debugPrint('[SCS] [6] TryGetMediaPropertiesAsync...');
      final mediaPropsAsyncPtr = calloc<Pointer<COMObject>>();
      // vtable index for TryGetMediaPropertiesAsync depends on the interface version
      // Try common indices: 10, 11
      int tryGetMediaIndex = 10;
      final tryGetMediaAddr = session.ref.vtable[tryGetMediaIndex];
      debugPrint('[SCS] [6] vtable[$tryGetMediaIndex] addr: $tryGetMediaAddr');
      final tryGetMediaFn = Pointer<
                  NativeFunction<
                      Int32 Function(Pointer<COMObject> self,
                          Pointer<Pointer<COMObject>> result)>>.fromAddress(
              tryGetMediaAddr)
          .asFunction<
              int Function(Pointer<COMObject> self,
                  Pointer<Pointer<COMObject>> result)>();

      final hr5 = tryGetMediaFn(session, mediaPropsAsyncPtr);
      debugPrint(
          '[SCS] [6] TryGetMediaPropertiesAsync: 0x${hr5.toRadixString(16)}');
      IUnknown(session).release();

      String title = '';
      String artist = '';
      String album = '';
      String albumArtist = '';

      if (hr5 == S_OK) {
        debugPrint('[SCS] [6] waiting media props async...');
        final mediaProps = _waitForAsync(mediaPropsAsyncPtr.value);
        calloc.free(mediaPropsAsyncPtr);
        debugPrint('[SCS] [6] mediaProps: $mediaProps');

        if (mediaProps != null) {
          // IGlobalSystemMediaTransportControlsSessionMediaProperties vtable:
          // IUnknown(0-2), IInspectable(3-5), get_Title(6), get_AlbumArtist(7),
          // get_Artist(8), get_AlbumTitle(9), ...
          title = _readHstr(mediaProps, 6);
          albumArtist = _readHstr(mediaProps, 7);
          artist = _readHstr(mediaProps, 8);
          album = _readHstr(mediaProps, 9);
          debugPrint('[SCS] [6] title="$title", artist="$artist", '
              'album="$album", albumArtist="$albumArtist"');
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
      debugPrint('[SCS] === _pollSMTC result: $_mediaInfo ===');
    } catch (e, st) {
      debugPrint('[SCS] _pollSMTC error: $e\n$st');
      _fallbackMediaInfo();
    }
  }

  static String _readHstr(Pointer<COMObject> obj, int idx) {
    try {
      final addr = obj.ref.vtable[idx];
      final fn = Pointer<
              NativeFunction<
                  Int32 Function(Pointer<COMObject> self,
                      Pointer<IntPtr> result)>>.fromAddress(addr)
          .asFunction<
              int Function(Pointer<COMObject> self, Pointer<IntPtr> result)>();
      final p = calloc<IntPtr>();
      if (fn(obj, p) == S_OK) {
        final s = _hstringToDart(p.value);
        if (p.value != 0) _winDeleteStr(p.value);
        calloc.free(p);
        return s;
      }
      calloc.free(p);
    } catch (e) {
      debugPrint('[SCS] _readHstr($idx) error: $e');
    }
    return '';
  }

  /// 等待 IAsyncOperation 完成并返回结果
  static Pointer<COMObject>? _waitForAsync(Pointer<COMObject> asyncOp) {
    debugPrint('[SCS] _waitForAsync start');
    try {
      // IAsyncInfo vtable: 3=get_Id, 4=get_Status, ...
      final getStatusAddr = asyncOp.ref.vtable[4];
      debugPrint('[SCS] get_Status vtable[4] addr: $getStatusAddr');
      final getStatusFn = Pointer<
              NativeFunction<
                  Int32 Function(Pointer<COMObject> self,
                      Pointer<Int32> result)>>.fromAddress(getStatusAddr)
          .asFunction<
              int Function(Pointer<COMObject> self, Pointer<Int32> result)>();

      final statusPtr = calloc<Int32>();
      final start = DateTime.now();
      int polls = 0;

      while (true) {
        final hr = getStatusFn(asyncOp, statusPtr);
        if (hr != S_OK) {
          debugPrint('[SCS] getStatus failed: 0x${hr.toRadixString(16)}');
          calloc.free(statusPtr);
          IUnknown(asyncOp).release();
          return null;
        }

        // AsyncStatus: 0=Started, 1=Completed, 2=Cancelled, 3=Error
        if (statusPtr.value == 1) break;
        if (statusPtr.value >= 2) {
          debugPrint('[SCS] async status=${statusPtr.value}');
          calloc.free(statusPtr);
          IUnknown(asyncOp).release();
          return null;
        }

        if (DateTime.now().difference(start).inMilliseconds > 5000) {
          debugPrint('[SCS] async timeout after 5s, $polls polls');
          calloc.free(statusPtr);
          IUnknown(asyncOp).release();
          return null;
        }

        polls++;
        Sleep(10);
      }
      debugPrint('[SCS] async completed, $polls polls');
      calloc.free(statusPtr);

      // IAsyncOperation vtable: IUnknown(0-2), IAsyncInfo(3-7), GetResults(10)
      final getResultsAddr = asyncOp.ref.vtable[10];
      debugPrint('[SCS] GetResults vtable[10] addr: $getResultsAddr');
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
      debugPrint('[SCS] GetResults: 0x${hr.toRadixString(16)}');
      IUnknown(asyncOp).release();

      if (hr == S_OK) {
        final result = resultPtr.value;
        calloc.free(resultPtr);
        debugPrint('[SCS] async result: $result');
        return result;
      }
      calloc.free(resultPtr);
    } catch (e, st) {
      debugPrint('[SCS] _waitForAsync error: $e\n$st');
      try {
        IUnknown(asyncOp).release();
      } catch (_) {}
    }
    return null;
  }

  static void _fallbackMediaInfo() {
    debugPrint('[SCS] _fallbackMediaInfo');
    try {
      final hwnd = GetForegroundWindow();
      if (hwnd == 0) return;
      final len = GetWindowTextLength(hwnd);
      if (len == 0) return;
      final buf = wsalloc(len + 1);
      GetWindowText(hwnd, buf, len + 1);
      final title = buf.toDartString();
      free(buf);
      debugPrint('[SCS] foreground: "$title"');

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
    } catch (e) {
      debugPrint('[SCS] _fallbackMediaInfo error: $e');
    }
  }

  // ───────────── 全局清理 ──────────────────────────────────────────

  static void dispose() {
    debugPrint('[SCS] dispose');
    stopMediaPolling();
    disposeBrightness();
    if (_hstrSMTCClass != 0) {
      try {
        _winDeleteStr(_hstrSMTCClass);
      } catch (_) {}
      _hstrSMTCClass = 0;
    }
  }
}
