import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../course_import/course_schedule_semantics.dart';
import '../models.dart';
import '../storage_service.dart';
import '../services/pomodoro_service.dart';
import '../services/course_service.dart';
import 'storage/user_session_storage.dart';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'lan_mdns_codec.dart';
import 'lan_sync_crypto.dart';
import 'lan_sync_models.dart';
import 'lan_sync_pairing.dart';
import 'lan_sync_private_data.dart';
import 'power_save_mode_service.dart';
import 'storage/app_settings_storage.dart';

export 'lan_sync_models.dart';

part 'lan_sync/lan_sync_discovery.dart';
part 'lan_sync/lan_sync_server.dart';
part 'lan_sync/lan_sync_merge.dart';
part 'lan_sync/lan_sync_transfer.dart';

const int _discoveryPort = 54321;
const int _defaultHttpPort = 54322;
const String _multicastGroup = '239.255.0.1';
const String _prefDesktopDaemonEnabled = 'lan_sync_desktop_daemon_enabled';
const String _prefAutoSyncEnabled = 'lan_sync_auto_sync_enabled';
const String _prefSyncSecretsEnabled = 'lan_sync_sync_secrets_enabled';
const String _prefSyncSettingsEnabled = 'lan_sync_sync_settings_enabled';
const String _prefTrustedPeerDeviceIds = 'lan_sync_trusted_peer_device_ids';
const int _quickPairTtlMs = 5 * 60 * 1000;
const int _pendingRequestTtlMs = 5 * 60 * 1000;
const int _autoSyncCooldownMs = 5 * 60 * 1000;
const int _maxReceiveFileBytes = 100 * 1024 * 1024;
// Discovery sends once immediately. A 30-second keepalive avoids frequent
// multicast radio wakeups while keeping nearby peers fresh; the refresh
// action still broadcasts on demand.
const Duration _discoveryInterval = Duration(seconds: 30);
const int _deviceTimeoutMs = 90000;

const Duration _sessionTtl = Duration(minutes: 5);
const int _maxCryptoSessions = 64;

abstract class _LanSyncServiceBase {
  @visibleForTesting
  bool? powerSaveModeOverrideForTesting;

  bool get _isPowerSaveMode =>
      powerSaveModeOverrideForTesting ?? PowerSaveModeService.isEnabled;

  bool _initialized = false;

  HttpServer? _server;
  RawDatagramSocket? _udpSocket;
  StreamSubscription<RawSocketEvent>? _udpSubscription;
  RawDatagramSocket? _mdnsSocket;
  StreamSubscription<RawSocketEvent>? _mdnsSubscription;
  Timer? _discoveryTimer;
  Timer? _fallbackScanTimer;
  int? _serverPort;
  bool _scanInProgress = false;

  final _devicesCtrl = StreamController<List<LanDevice>>.broadcast();
  final _statusCtrl = StreamController<String>.broadcast();
  final _syncProgressCtrl = StreamController<String>.broadcast();
  final _incomingRequestCtrl = StreamController<LanDevice>.broadcast();
  final _syncProgressValueCtrl = StreamController<double>.broadcast();
  final _fileReceivedCtrl = StreamController<Map<String, String>>.broadcast();
  final _quickPairCompletedCtrl = StreamController<LanSyncResult>.broadcast();
  final _syncCompletedCtrl = StreamController<LanSyncResult>.broadcast();

  final ValueNotifier<bool> daemonRunningNotifier = ValueNotifier<bool>(false);

  final Map<String, LanDevice> _incomingPendingRequests = {};
  final Map<String, ({String token, int expiresAt})> _incomingPendingTokens =
      {};
  final Map<String, LanDevice> _outgoingPendingRequests = {};
  final Map<String, ({String token, int expiresAt})> _outgoingPendingTokens =
      {};
  final Set<String> _trustedPeerDeviceIds = {};
  final Map<String, int> _lastAutoSyncAt = {};
  String? _activeQuickPairToken;
  int _activeQuickPairExpiresAt = 0;

  Stream<List<LanDevice>> get onDevicesChanged => _devicesCtrl.stream;
  Stream<String> get onStatusChanged => _statusCtrl.stream;
  Stream<String> get onSyncProgress => _syncProgressCtrl.stream;
  Stream<LanDevice> get onIncomingRequest => _incomingRequestCtrl.stream;
  Stream<double> get onProgressChanged => _syncProgressValueCtrl.stream;
  Stream<Map<String, String>> get onFileReceived => _fileReceivedCtrl.stream;
  Stream<LanSyncResult> get onQuickPairCompleted =>
      _quickPairCompletedCtrl.stream;
  Stream<LanSyncResult> get onSyncCompleted => _syncCompletedCtrl.stream;

  final Map<String, LanDevice> _devices = {};
  bool _isRunning = false;
  bool _isSyncing = false;
  bool _discoverAllDevices = false;
  bool _isDaemonMode = false;
  bool _autoSyncEnabled = false;
  bool _syncSecretsEnabled = true;
  bool _syncSettingsEnabled = false;

  bool get isRunning => _isRunning;
  bool get isSyncing => _isSyncing;
  bool get discoverAllDevices => _discoverAllDevices;
  bool get isDaemonMode => _isDaemonMode;
  bool get autoSyncEnabled => _autoSyncEnabled;
  bool get syncSecretsEnabled => _syncSecretsEnabled;
  bool get syncSettingsEnabled => _syncSettingsEnabled;
  int? get serverPort => _serverPort;

  set discoverAllDevices(bool value) {
    if (_discoverAllDevices != value) {
      _discoverAllDevices = value;
      _devices.clear();
      _emitDevices();
      triggerDiscovery();
    }
  }

  List<LanDevice> get devices => _devices.values.toList();

  String? _currentUserId;
  String? _currentDeviceId;
  String? _currentDeviceName;
  String? _localIp;
  final Map<String, ({Uint8List key, int expiresAt})> _cryptoSessions = {};

  String? get currentUserId => _currentUserId;
  String? get currentDeviceId => _currentDeviceId;
  String? get currentDeviceName => _currentDeviceName;
  String? get localIp => _localIp;

  Future<void> _mergeLock = Future.value();
  bool _backgroundAutoSyncInProgress = false;
  bool _hasRunStartupBackgroundSync = false;
  DateTime? _lastOfflineBackgroundSyncAt;
  int? _cachedOfflineSyncIntervalMinutes;
  LanSyncConfig _currentConfig = LanSyncConfig();
  String? _currentPendingToken;

  String get _hashedDiscoveryUserId =>
      LanDiscoveryIdentity.hashUserId(_currentUserId);

  bool _isSameUser(String? a, String? b) =>
      LanDiscoveryIdentity.isSameUser(a, b);

  Future<void> _ensureIdentity() async {
    final rawUser = (await UserSessionStorage.getCurrentUsername())?.trim();
    _currentUserId = (rawUser != null && rawUser.isNotEmpty)
        ? rawUser
        : 'local';
    _currentDeviceId = await UserSessionStorage.getDeviceId();
    _currentDeviceName = await UserSessionStorage.getDeviceFriendlyName();
    _localIp = await _getLocalIp();
  }

  String _localizePeerError(String? rawError, {String fallback = '同步失败'}) {
    final err = rawError?.trim() ?? '';
    if (err.isEmpty) return fallback;
    switch (err) {
      case 'auto sync disabled':
        return '对方设备未开启自动同步，请在对方“局域网同步”设置中开启“自动同步”';
      case 'account mismatch':
        return '对方设备账号不匹配，请确认双方登录同一账号或开启“所有设备”';
      case 'no pending request':
        return '对方没有待处理的同步请求，请重新发起';
      case 'v2 encryption required':
      case 'v2 encrypted session required':
        return '对方要求使用 v2 加密会话，请升级应用版本';
      case 'invalid or expired crypto session':
        return '加密会话无效或已过期，请重试';
      case 'missing clientPublicKey':
        return '握手请求缺少客户端公钥';
      case 'not found':
        return '请求路径不存在';
      case 'unknown':
        return '未知错误';
    }
    const unsupportedPrefix = 'unsupported protocol version:';
    if (err.startsWith(unsupportedPrefix)) {
      return '不支持的加密协议版本:${err.substring(unsupportedPrefix.length)}';
    }
    return err;
  }

  Future<void> _trustPeerDevice(String? deviceId) async {
    final normalized = deviceId?.trim() ?? '';
    if (normalized.isEmpty) return;
    if (!_trustedPeerDeviceIds.add(normalized)) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(
        _prefTrustedPeerDeviceIds,
        _trustedPeerDeviceIds.toList(growable: false),
      );
    } catch (_) {}
  }

  bool _constantTimeTokenEquals(String a, String b) {
    final aBytes = utf8.encode(a);
    final bBytes = utf8.encode(b);
    if (aBytes.length != bBytes.length) return false;
    var diff = 0;
    for (var i = 0; i < aBytes.length; i++) {
      diff |= aBytes[i] ^ bBytes[i];
    }
    return diff == 0;
  }

  void _emitDevices() {
    final now = DateTime.now().millisecondsSinceEpoch;
    _devices.removeWhere((_, d) => now - d.lastSeen > _deviceTimeoutMs);
    if (!_devicesCtrl.isClosed) _devicesCtrl.add(_devices.values.toList());
  }

  void _emitStatus(String msg) {
    if (!_statusCtrl.isClosed) _statusCtrl.add(msg);
  }

  void _emitProgress(String msg) {
    if (!_syncProgressCtrl.isClosed) _syncProgressCtrl.add(msg);
  }

  void _emitProgressValue(double value) {
    if (!_syncProgressValueCtrl.isClosed) _syncProgressValueCtrl.add(value);
  }

  Future<String?> _getLocalIp();
  Future<LanSyncResult> _autoSyncWithDevice(LanDevice device);
  Future<void> initFromPreferences();
  Future<void> start({bool daemonMode = false});
  void cancelQuickPairSession();
  Future<void> _handleFileRequest(HttpRequest req);
  Future<
    ({
      int todos,
      int countdowns,
      int timeLogs,
      int pomodoroTags,
      int pomodoroRecords,
      int courses,
    })
  >
  _mergeSyncBundle({
    required String username,
    required Map<String, dynamic> data,
    required LanSyncConfig config,
    bool emitProgress = true,
  });
  Future<Map<String, dynamic>> _gatherLocalData(
    String username, [
    LanSyncConfig? config,
  ]);
  Future<void> _discoverOnce({Duration duration = const Duration(seconds: 3)});
  Future<void> _mergeTodos(
    String username,
    List<Map<String, dynamic>> remote,
    Function(int) onChanged,
  );
  Future<void> _mergeCountdowns(
    String username,
    List<Map<String, dynamic>> remote,
    Function(int) onChanged,
  );
  Future<void> _mergeTimeLogs(
    String username,
    List<Map<String, dynamic>> remote,
    Function(int) onChanged,
  );
  Future<void> _mergePomodoroTags(
    List<Map<String, dynamic>> remote,
    Function(int) onChanged,
  );
  Future<void> _mergePomodoroRecords(
    List<Map<String, dynamic>> remote,
    Function(int) onChanged,
  );
  Future<void> _mergeCourses(
    String username,
    List<Map<String, dynamic>> remote,
    Function(int) onChanged,
  );
  Future<({String sessionId, Uint8List key})> _performHandshake(
    HttpClient client,
    String ip,
    int port,
  );
  Future<Map<String, dynamic>> _postEncryptedSync(
    HttpClient client,
    String ip,
    int port,
    Map<String, dynamic> payload,
  );
  Future<void> _writeEncryptedJson(
    HttpRequest req,
    Uint8List sessionKey,
    Map<String, dynamic> body,
  );
  Future<void> _writeEncryptedError(
    HttpRequest req,
    Uint8List sessionKey,
    String message, {
    int statusCode = HttpStatus.ok,
  });
  Uint8List? _getSessionKey(String? sessionId);
  void triggerDiscovery();
}

class LanSyncService extends _LanSyncServiceBase
    with
        _LanSyncDiscoveryMixin,
        _LanSyncServerMixin,
        _LanSyncMergeMixin,
        _LanSyncTransferMixin {
  static final LanSyncService instance = LanSyncService._();
  factory LanSyncService() => instance;
  LanSyncService._() {
    PowerSaveModeService.enabledListenable.addListener(
      _handlePowerSaveModeChanged,
    );
  }

  /// 从本地配置初始化桌面端常驻服务与自动无感同步状态。
  @override
  Future<void> initFromPreferences() async {
    _initialized = true;
    final prefs = await SharedPreferences.getInstance();
    final isOffline = await AppSettingsStorage.isOfflineModeEnabled();
    _isDaemonMode = prefs.getBool(_prefDesktopDaemonEnabled) ?? isOffline;
    _autoSyncEnabled = prefs.getBool(_prefAutoSyncEnabled) ?? isOffline;
    _syncSecretsEnabled = prefs.getBool(_prefSyncSecretsEnabled) ?? true;
    _syncSettingsEnabled = prefs.getBool(_prefSyncSettingsEnabled) ?? false;
    _trustedPeerDeviceIds
      ..clear()
      ..addAll(prefs.getStringList(_prefTrustedPeerDeviceIds) ?? const []);
    final isDesktop =
        Platform.isWindows || Platform.isMacOS || Platform.isLinux;
    if (isDesktop && _isDaemonMode) {
      await start(daemonMode: true);
    } else if (_autoSyncEnabled && !_isPowerSaveMode) {
      await start(daemonMode: false);
    }
    daemonRunningNotifier.value = _isRunning && _isDaemonMode;
  }

  /// 离线模式切换时联动局域网探测开关与服务状态：
  /// - 开启离线模式：默认打开局域网自动探测（桌面端同时开启常驻服务）。
  /// - 关闭离线模式：关闭局域网自动探测与常驻服务，并停止正在运行的探测。
  Future<void> onOfflineModeChanged(bool offlineEnabled) async {
    final isDesktop =
        Platform.isWindows || Platform.isMacOS || Platform.isLinux;
    if (offlineEnabled) {
      if (isDesktop) {
        await setDesktopDaemonEnabled(true);
      }
      await setAutoSyncEnabled(true);
    } else {
      await setAutoSyncEnabled(false);
      await setDesktopDaemonEnabled(false);
    }
  }

  /// 桌面端“局域网同步服务”常驻开关。
  Future<void> setDesktopDaemonEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefDesktopDaemonEnabled, enabled);
    _isDaemonMode = enabled;
    if (enabled) {
      if (!_isRunning) {
        await start(daemonMode: true);
      } else {
        daemonRunningNotifier.value = true;
      }
    } else {
      daemonRunningNotifier.value = false;
      if (_isRunning) {
        await stop();
      }
    }
  }

  /// 同账号局域网自动无感同步开关。
  Future<void> setAutoSyncEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefAutoSyncEnabled, enabled);
    _autoSyncEnabled = enabled;
    if (enabled && !_isPowerSaveMode) {
      if (!_isRunning) {
        await start(daemonMode: _isDaemonMode);
      } else {
        _broadcastDiscovery();
      }
    }
  }

  /// 是否通过局域网加密通道同步 API Key 与大模型配置。
  Future<void> setSyncSecretsEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefSyncSecretsEnabled, enabled);
    _syncSecretsEnabled = enabled;
  }

  /// 是否同步应用偏好设置（默认关闭）。
  Future<void> setSyncSettingsEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefSyncSettingsEnabled, enabled);
    _syncSettingsEnabled = enabled;
  }

  @override
  Future<void> start({bool daemonMode = false}) async {
    if (_isRunning) {
      if (daemonMode) {
        _isDaemonMode = true;
        daemonRunningNotifier.value = true;
      }
      return;
    }
    _isRunning = true;
    if (daemonMode) {
      _isDaemonMode = true;
    }

    await _ensureIdentity();

    try {
      await _startHttpServer();
      await _startUdpDiscovery();
      await _startMdnsDiscovery();
      if (!_isPowerSaveMode) {
        _startDiscoveryBroadcast();
        _startTimedScan();
      }
      daemonRunningNotifier.value = _isDaemonMode;
      _emitStatus(
        _isPowerSaveMode
            ? '省电模式已暂停自动探测'
            : (_isDaemonMode ? '常驻服务运行中（mDNS）' : '正在扫描设备...'),
      );
    } catch (e) {
      _emitStatus('启动失败: $e');
      _isRunning = false;
      daemonRunningNotifier.value = false;
    }
  }

  /// 开启面对面快传会话并生成带一次性 Token 的配对二维码载荷。
  Future<LanPairingPayload?> startQuickPairSession() async {
    if (!_isRunning) {
      await start(daemonMode: _isDaemonMode);
    } else {
      await _ensureIdentity();
    }
    if (!_isRunning || _serverPort == null) return null;

    final ip = _localIp ?? await _getLocalIp();
    if (ip == null || ip.isEmpty) return null;

    final token = LanPairingPayload.generateOneTimeToken();
    final expiresAt = DateTime.now().millisecondsSinceEpoch + _quickPairTtlMs;
    _activeQuickPairToken = token;
    _activeQuickPairExpiresAt = expiresAt;

    return LanPairingPayload(
      deviceId: _currentDeviceId ?? '',
      userId: _currentUserId ?? 'local',
      deviceName: _currentDeviceName ?? '未知设备',
      ip: ip,
      port: _serverPort!,
      token: token,
      expiresAt: expiresAt,
    );
  }

  @override
  void cancelQuickPairSession() {
    _activeQuickPairToken = null;
    _activeQuickPairExpiresAt = 0;
  }

  Future<void> stop() async {
    _isRunning = false;
    daemonRunningNotifier.value = false;
    _discoveryTimer?.cancel();
    _discoveryTimer = null;
    _fallbackScanTimer?.cancel();
    _fallbackScanTimer = null;
    await _udpSubscription?.cancel();
    _udpSubscription = null;
    _udpSocket?.close();
    _udpSocket = null;
    await _mdnsSubscription?.cancel();
    _mdnsSubscription = null;
    _mdnsSocket?.close();
    _mdnsSocket = null;
    await _server?.close(force: true);
    _server = null;
    _devices.clear();
    _incomingPendingRequests.clear();
    _incomingPendingTokens.clear();
    _outgoingPendingRequests.clear();
    _outgoingPendingTokens.clear();
    cancelQuickPairSession();
    _emitDevices();
    _emitStatus('已停止');
  }

  void rejectIncomingRequest(LanDevice device) {
    final id = device.deviceId.trim();
    if (id.isEmpty) return;
    _incomingPendingRequests.remove(id);
    _incomingPendingTokens.remove(id);
  }

  void dispose() {
    PowerSaveModeService.enabledListenable.removeListener(
      _handlePowerSaveModeChanged,
    );
    stop();
    _devicesCtrl.close();
    _statusCtrl.close();
    _syncProgressCtrl.close();
    _incomingRequestCtrl.close();
    _syncProgressValueCtrl.close();
    _fileReceivedCtrl.close();
    _quickPairCompletedCtrl.close();
    _syncCompletedCtrl.close();
    daemonRunningNotifier.dispose();
  }
}
