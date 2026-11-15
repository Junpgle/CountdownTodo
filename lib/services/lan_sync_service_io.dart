import 'dart:async';
import 'dart:convert';
import 'dart:io';
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
import 'lan_sync_pairing.dart';
import 'lan_sync_private_data.dart';

class LanDevice {
  final String deviceId;
  final String userId;
  final String deviceName;
  final String ip;
  final int port;
  final int lastSeen;
  bool pendingApproval;

  LanDevice({
    required this.deviceId,
    required this.userId,
    required this.deviceName,
    required this.ip,
    required this.port,
    required this.lastSeen,
    this.pendingApproval = false,
  });

  Map<String, dynamic> toJson() => {
    'deviceId': deviceId,
    'userId': userId,
    'deviceName': deviceName,
    'ip': ip,
    'port': port,
    'lastSeen': lastSeen,
  };

  factory LanDevice.fromJson(Map<String, dynamic> j) => LanDevice(
    deviceId: j['deviceId'] ?? '',
    userId: j['userId'] ?? '',
    deviceName: j['deviceName'] ?? '',
    ip: j['ip'] ?? '',
    port: j['port'] ?? 0,
    lastSeen: j['lastSeen'] ?? 0,
  );

  LanDevice copyWith({bool? pendingApproval}) => LanDevice(
    deviceId: deviceId,
    userId: userId,
    deviceName: deviceName,
    ip: ip,
    port: port,
    lastSeen: lastSeen,
    pendingApproval: pendingApproval ?? this.pendingApproval,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LanDevice && deviceId == other.deviceId;

  @override
  int get hashCode => deviceId.hashCode;
}

class LanSyncResult {
  final bool success;
  final String message;
  final int todosSynced;
  final int countdownsSynced;
  final int timeLogsSynced;
  final int pomodoroTagsSynced;
  final int pomodoroRecordsSynced;
  final int coursesSynced;
  final double progress;

  LanSyncResult({
    this.success = false,
    this.message = '',
    this.todosSynced = 0,
    this.countdownsSynced = 0,
    this.timeLogsSynced = 0,
    this.pomodoroTagsSynced = 0,
    this.pomodoroRecordsSynced = 0,
    this.coursesSynced = 0,
    this.progress = 0,
  });
}

class LanSyncConfig {
  final bool syncTodos;
  final bool syncCountdowns;
  final bool syncTimeLogs;
  final bool syncPomodoroTags;
  final bool syncPomodoroRecords;
  final bool syncCourses;
  final bool syncSecrets;
  final bool syncSettings;

  LanSyncConfig({
    this.syncTodos = true,
    this.syncCountdowns = true,
    this.syncTimeLogs = true,
    this.syncPomodoroTags = true,
    this.syncPomodoroRecords = true,
    this.syncCourses = true,
    this.syncSecrets = true,
    this.syncSettings = false,
  });

  Map<String, dynamic> toJson() => {
    'todos': syncTodos,
    'countdowns': syncCountdowns,
    'timeLogs': syncTimeLogs,
    'pomodoroTags': syncPomodoroTags,
    'pomodoroRecords': syncPomodoroRecords,
    'courses': syncCourses,
    'secrets': syncSecrets,
    'settings': syncSettings,
  };

  int get totalCount =>
      (syncTodos ? 1 : 0) +
      (syncCountdowns ? 1 : 0) +
      (syncTimeLogs ? 1 : 0) +
      (syncPomodoroTags ? 1 : 0) +
      (syncPomodoroRecords ? 1 : 0) +
      (syncCourses ? 1 : 0) +
      (syncSecrets ? 1 : 0) +
      (syncSettings ? 1 : 0);
}

enum LanSyncState { idle, requesting, sending, receiving, completed }

class LanSyncService {
  static const int _discoveryPort = 54321;
  static const int _defaultHttpPort = 54322;
  static const String _multicastGroup = '239.255.0.1';
  static const String _prefDesktopDaemonEnabled =
      'lan_sync_desktop_daemon_enabled';
  static const String _prefAutoSyncEnabled = 'lan_sync_auto_sync_enabled';
  static const String _prefSyncSecretsEnabled = 'lan_sync_sync_secrets_enabled';
  static const String _prefSyncSettingsEnabled =
      'lan_sync_sync_settings_enabled';
  static const int _quickPairTtlMs = 5 * 60 * 1000;
  static const int _autoSyncCooldownMs = 5 * 60 * 1000;
  // Discovery sends once immediately. A 30-second keepalive avoids frequent
  // multicast radio wakeups while keeping nearby peers fresh; the refresh
  // action still broadcasts on demand.
  static const Duration _discoveryInterval = Duration(seconds: 30);
  static const int _deviceTimeoutMs = 90000;

  static final LanSyncService instance = LanSyncService._();
  factory LanSyncService() => instance;
  LanSyncService._();

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

  final Map<String, LanDevice> _pendingRequests = {};
  final Map<String, String> _pendingTokens = {};
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
  bool _autoSyncEnabled = true;
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

  void triggerDiscovery() {
    if (_isRunning) {
      _broadcastDiscovery();
      _startTimedScan(force: true);
      _emitStatus('正在重新扫描...');
    }
  }

  void _startTimedScan({bool force = false}) {
    _fallbackScanTimer?.cancel();
    if (force) {
      unawaited(_scanAllInterfaces());
    } else {
      // Multicast discovery is cheap and normally answers immediately. Only
      // fan out across the /24 subnet when multicast did not find any peer.
      _fallbackScanTimer = Timer(const Duration(seconds: 2), () {
        if (_isRunning && _devices.isEmpty) {
          unawaited(_scanAllInterfaces());
        }
      });
    }
    Future.delayed(const Duration(seconds: 10), () {
      if (_isRunning) {
        _emitStatus('已启动（AES加密），发现 ${_devices.length} 台设备');
      }
    });
  }

  bool _isSameUser(String? a, String? b) {
    if (a == null || b == null) return false;
    final na = a.trim().toLowerCase();
    final nb = b.trim().toLowerCase();
    return na.isNotEmpty && nb.isNotEmpty && na == nb;
  }

  bool _isVirtualInterfaceName(String name) {
    final lower = name.toLowerCase();
    const prefixes = [
      'utun',
      'tun',
      'tap',
      'ppp',
      'wg',
      'docker',
      'veth',
      'vmnet',
      'vboxnet',
      'bridge',
      'awdl',
      'llw',
      'ap',
    ];
    return prefixes.any((prefix) => lower.startsWith(prefix));
  }

  Future<List<({NetworkInterface interface, InternetAddress address})>>
  _getLanIpv4Interfaces() async {
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLoopback: false,
    );
    final preferred = <({NetworkInterface interface, InternetAddress address})>[];
    final secondary = <({NetworkInterface interface, InternetAddress address})>[];
    final virtualFallback =
        <({NetworkInterface interface, InternetAddress address})>[];
    for (final interface in interfaces) {
      final isVirtual = _isVirtualInterfaceName(interface.name);
      for (final addr in interface.addresses) {
        if (addr.isLoopback || addr.type != InternetAddressType.IPv4) continue;
        final ip = addr.address;
        if (ip.startsWith('169.254.') || ip.startsWith('198.18.')) continue;
        final entry = (interface: interface, address: addr);
        if (isVirtual) {
          virtualFallback.add(entry);
          continue;
        }
        if (ip.startsWith('192.168.') || ip.startsWith('10.')) {
          preferred.add(entry);
        } else {
          secondary.add(entry);
        }
      }
    }
    final physical = [...preferred, ...secondary];
    return physical.isNotEmpty ? physical : virtualFallback;
  }

  Future<void> _joinMulticastOnLanInterfaces(
    RawDatagramSocket socket,
    InternetAddress group,
  ) async {
    bool joinedAny = false;
    try {
      final lanInterfaces = await _getLanIpv4Interfaces();
      for (final entry in lanInterfaces) {
        try {
          socket.joinMulticast(group, entry.interface);
          joinedAny = true;
        } catch (_) {}
      }
    } catch (_) {}
    if (!joinedAny) {
      try {
        socket.joinMulticast(group);
      } catch (_) {}
    }
  }

  Future<void> _scanAllInterfaces({bool ignoreRunningState = false}) async {
    if (_scanInProgress || (!ignoreRunningState && !_isRunning)) return;
    _scanInProgress = true;
    try {
      final lanInterfaces = await _getLanIpv4Interfaces();
      for (final entry in lanInterfaces) {
        await _scanSubnet(
          entry.address.address,
          ignoreRunningState: ignoreRunningState,
        );
      }
    } catch (_) {
    } finally {
      _scanInProgress = false;
    }
  }

  Future<void> _scanSubnet(
    String localIp, {
    bool ignoreRunningState = false,
  }) async {
    final client = HttpClient();
    client.connectionTimeout = const Duration(milliseconds: 500);
    try {
      final parts = localIp.split('.');
      if (parts.length != 4) return;

      final subnet = '${parts[0]}.${parts[1]}.${parts[2]}';
      debugPrint(
        '[LanSync] Scanning HTTP subnet $subnet.1-254 (localIp=$localIp, user=$_currentUserId)',
      );
      const batchSize = 64;
      for (int firstHost = 1; firstHost < 255; firstHost += batchSize) {
        if (!ignoreRunningState && !_isRunning) break;
        final lastHost = (firstHost + batchSize).clamp(1, 255);
        final futures = <Future<void>>[];
        for (int host = firstHost; host < lastHost; host++) {
          final ip = '$subnet.$host';
          if (ip == localIp) continue;
          futures.add(
            _tryConnect(client, ip, ignoreRunningState: ignoreRunningState),
          );
        }
        await Future.wait(futures);
      }

      _emitDevices();
    } catch (e) {
      debugPrint('[LanSync] _scanSubnet error: $e');
    } finally {
      client.close(force: true);
    }
  }

  Future<void> _tryConnect(
    HttpClient client,
    String ip, {
    bool ignoreRunningState = false,
  }) async {
    if (!ignoreRunningState && !_isRunning) return;
    try {
      final request = await client
          .getUrl(Uri.parse('http://$ip:$_defaultHttpPort/discover'))
          .timeout(const Duration(milliseconds: 500));
      final response = await request.close().timeout(
        const Duration(milliseconds: 700),
      );
      final body = await response.transform(utf8.decoder).join();
      final data = jsonDecode(body) as Map<String, dynamic>;

      final remoteDeviceId = data['deviceId']?.toString();
      final remoteUserId = data['userId']?.toString();
      if (remoteDeviceId != null &&
          remoteDeviceId != _currentDeviceId &&
          (_discoverAllDevices || _isSameUser(remoteUserId, _currentUserId))) {
        final device = LanDevice(
          deviceId: remoteDeviceId,
          userId: remoteUserId ?? '',
          deviceName: data['deviceName']?.toString() ?? '未知设备',
          ip: ip,
          port: (data['port'] as num?)?.toInt() ?? _defaultHttpPort,
          lastSeen: DateTime.now().millisecondsSinceEpoch,
        );
        _devices[device.deviceId] = device;
        debugPrint(
          '[LanSync] HTTP discovered peer ${device.deviceName} ($ip:${device.port}, user=${device.userId})',
        );
      } else if (remoteDeviceId != null && remoteDeviceId != _currentDeviceId) {
        debugPrint(
          '[LanSync] HTTP peer $ip ignored due to userId mismatch: remote=$remoteUserId, local=$_currentUserId',
        );
      }
    } catch (_) {}
  }

  Future<String?> _getLocalIp() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );
      String? fallback;
      String? classB;
      String? classA;
      for (final interface in interfaces) {
        for (final addr in interface.addresses) {
          if (addr.isLoopback || addr.type != InternetAddressType.IPv4) {
            continue;
          }
          final ip = addr.address;
          if (ip.startsWith('169.254.')) continue;
          if (ip.startsWith('192.168.')) return ip;
          if (ip.startsWith('10.')) {
            classA ??= ip;
            continue;
          }
          final parts = ip.split('.');
          final second = parts.length == 4 ? int.tryParse(parts[1]) : null;
          if (parts[0] == '172' &&
              second != null &&
              second >= 16 &&
              second <= 31) {
            classB ??= ip;
            continue;
          }
          fallback ??= ip;
        }
      }
      return classA ?? classB ?? fallback;
    } catch (_) {}
    return null;
  }

  Future<void> _ensureIdentity() async {
    final rawUser = (await UserSessionStorage.getCurrentUsername())?.trim();
    _currentUserId = (rawUser != null && rawUser.isNotEmpty)
        ? rawUser
        : 'local';
    _currentDeviceId = await UserSessionStorage.getDeviceId();
    _currentDeviceName = await UserSessionStorage.getDeviceFriendlyName();
    _localIp = await _getLocalIp();
  }

  /// 从本地配置初始化桌面端常驻服务与自动无感同步状态。
  Future<void> initFromPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    _isDaemonMode = prefs.getBool(_prefDesktopDaemonEnabled) ?? true;
    _autoSyncEnabled = prefs.getBool(_prefAutoSyncEnabled) ?? true;
    _syncSecretsEnabled = prefs.getBool(_prefSyncSecretsEnabled) ?? true;
    _syncSettingsEnabled = prefs.getBool(_prefSyncSettingsEnabled) ?? false;
    final isDesktop =
        Platform.isWindows || Platform.isMacOS || Platform.isLinux;
    if (isDesktop && _isDaemonMode) {
      await start(daemonMode: true);
    } else if (_autoSyncEnabled) {
      await start(daemonMode: false);
    }
    daemonRunningNotifier.value = _isRunning && _isDaemonMode;
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
    if (_isRunning) {
      _broadcastDiscovery();
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
      _startDiscoveryBroadcast();
      _startTimedScan();
      daemonRunningNotifier.value = _isDaemonMode;
      _emitStatus(_isDaemonMode ? '常驻服务运行中（mDNS）' : '正在扫描设备...');
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
    final expiresAt =
        DateTime.now().millisecondsSinceEpoch + _quickPairTtlMs;
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

  void cancelQuickPairSession() {
    _activeQuickPairToken = null;
    _activeQuickPairExpiresAt = 0;
  }

  static const Duration _sessionTtl = Duration(minutes: 5);
  static const int _maxCryptoSessions = 64;

  void _pruneExpiredSessions() {
    final now = DateTime.now().millisecondsSinceEpoch;
    _cryptoSessions.removeWhere((_, session) => session.expiresAt < now);
  }

  ({String sessionId, String serverPublicKeyBase64}) _createCryptoSession(
    String clientPublicKeyBase64,
  ) {
    _pruneExpiredSessions();
    if (_cryptoSessions.length >= _maxCryptoSessions) {
      _cryptoSessions.remove(_cryptoSessions.keys.first);
    }

    final serverKeys = LanSyncCrypto.generateEphemeralKeyPair();
    final sharedKey = LanSyncCrypto.deriveSharedKey(
      serverKeys.privateKey,
      clientPublicKeyBase64,
    );

    final rng = Random.secure();
    final idBytes = List<int>.generate(16, (_) => rng.nextInt(256));
    final sessionId = idBytes
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();

    _cryptoSessions[sessionId] = (
      key: sharedKey,
      expiresAt: DateTime.now().add(_sessionTtl).millisecondsSinceEpoch,
    );
    return (
      sessionId: sessionId,
      serverPublicKeyBase64: serverKeys.publicKeyBase64,
    );
  }

  Uint8List? _getSessionKey(String? sessionId) {
    if (sessionId == null || sessionId.isEmpty) return null;
    _pruneExpiredSessions();
    return _cryptoSessions[sessionId]?.key;
  }

  Future<({String sessionId, Uint8List key})> _performHandshake(
    HttpClient client,
    String ip,
    int port,
  ) async {
    final clientKeys = LanSyncCrypto.generateEphemeralKeyPair();
    final req = await client.postUrl(Uri.parse('http://$ip:$port/handshake'));
    req.headers.contentType = ContentType.json;
    req.write(
      jsonEncode({
        'v': LanSyncCrypto.protocolVersion,
        'clientPublicKey': clientKeys.publicKeyBase64,
      }),
    );
    final resp = await req.close().timeout(const Duration(seconds: 8));
    final body = await resp.transform(utf8.decoder).join();
    if (resp.statusCode != HttpStatus.ok) {
      throw StateError('加密握手失败 (${resp.statusCode}): $body');
    }
    final data = jsonDecode(body) as Map<String, dynamic>;
    if (data['v'] != LanSyncCrypto.protocolVersion) {
      throw StateError('不支持的加密协议版本: ${data['v']}');
    }
    final sessionId = data['sessionId']?.toString() ?? '';
    final serverPub = data['serverPublicKey']?.toString() ?? '';
    if (sessionId.isEmpty || serverPub.isEmpty) {
      throw const FormatException('握手响应缺少会话参数');
    }
    final key = LanSyncCrypto.deriveSharedKey(clientKeys.privateKey, serverPub);
    return (sessionId: sessionId, key: key);
  }

  Future<Map<String, dynamic>> _postEncryptedSync(
    HttpClient client,
    String ip,
    int port,
    Map<String, dynamic> payload, {
    Duration timeout = const Duration(seconds: 20),
  }) async {
    final session = await _performHandshake(client, ip, port);
    final request = await client.postUrl(Uri.parse('http://$ip:$port/sync'));
    request.headers.contentType = ContentType.json;
    request.write(
      jsonEncode({
        'v': LanSyncCrypto.protocolVersion,
        'encrypted': true,
        'sessionId': session.sessionId,
        'payload': LanSyncCrypto.encryptString(
          session.key,
          jsonEncode(payload),
        ),
      }),
    );
    final response = await request.close().timeout(timeout);
    final encryptedBody = await response.transform(utf8.decoder).join();
    final encryptedResponseData =
        jsonDecode(encryptedBody) as Map<String, dynamic>;

    if (encryptedResponseData['encrypted'] != true ||
        encryptedResponseData['v'] != LanSyncCrypto.protocolVersion) {
      return {
        'success': false,
        'error':
            '响应未加密或版本不匹配 (${encryptedResponseData['error'] ?? 'unknown'})',
      };
    }

    final decryptedBody = LanSyncCrypto.decryptString(
      session.key,
      encryptedResponseData['payload'].toString(),
    );
    return jsonDecode(decryptedBody) as Map<String, dynamic>;
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
    _pendingRequests.clear();
    _pendingTokens.clear();
    cancelQuickPairSession();
    _emitDevices();
    _emitStatus('已停止');
  }

  Future<void> _startHttpServer() async {
    int port = _defaultHttpPort;
    for (int attempt = 0; attempt < 10; attempt++) {
      try {
        _server = await HttpServer.bind(InternetAddress.anyIPv4, port);
        _serverPort = port;
        // debugPrint('[LanSync] HTTP server started on port $port');
        break;
      } catch (e) {
        port = _defaultHttpPort + attempt + 1;
      }
    }
    if (_server == null) throw Exception('无法启动HTTP服务器');

    _server!.listen(_handleRequest);
  }

  Future<void> _handleRequest(HttpRequest req) async {
    try {
      final path = req.uri.path;
      if (path == '/handshake' && req.method == 'POST') {
        await _handleHandshakeRequest(req);
      } else if (path == '/sync' && req.method == 'POST') {
        await _handleSyncRequest(req);
      } else if (path == '/file' && req.method == 'POST') {
        await _handleFileRequest(req);
      } else if (path == '/discover' && req.method == 'GET') {
        await _handleDiscoverRequest(req);
      } else {
        req.response.statusCode = HttpStatus.notFound;
        req.response.write(jsonEncode({'error': 'not found'}));
        await req.response.close();
      }
    } catch (e) {
      // debugPrint('[LanSync] Handle request error: $e');
      try {
        req.response.statusCode = HttpStatus.internalServerError;
        req.response.headers.contentType = ContentType.json;
        req.response.write(jsonEncode({'error': e.toString()}));
        await req.response.close();
      } catch (_) {}
    }
  }

  Future<void> _handleHandshakeRequest(HttpRequest req) async {
    final body = await utf8.decoder.bind(req).join();
    final data = jsonDecode(body) as Map<String, dynamic>;
    if (data['v'] != LanSyncCrypto.protocolVersion) {
      req.response.statusCode = HttpStatus.badRequest;
      req.response.headers.contentType = ContentType.json;
      req.response.write(
        jsonEncode({'error': 'unsupported protocol version: ${data['v']}'}),
      );
      await req.response.close();
      return;
    }

    final clientPub = data['clientPublicKey']?.toString() ?? '';
    if (clientPub.isEmpty) {
      req.response.statusCode = HttpStatus.badRequest;
      req.response.headers.contentType = ContentType.json;
      req.response.write(jsonEncode({'error': 'missing clientPublicKey'}));
      await req.response.close();
      return;
    }

    final session = _createCryptoSession(clientPub);
    req.response.headers.contentType = ContentType.json;
    req.response.write(
      jsonEncode({
        'v': LanSyncCrypto.protocolVersion,
        'sessionId': session.sessionId,
        'serverPublicKey': session.serverPublicKeyBase64,
      }),
    );
    await req.response.close();
  }

  Future<void> _handleDiscoverRequest(HttpRequest req) async {
    if (_currentUserId == null || _currentUserId == 'local') {
      await _ensureIdentity();
    }
    final response = {
      'deviceId': _currentDeviceId,
      'userId': _currentUserId,
      'deviceName': _currentDeviceName,
      'port': _serverPort,
    };
    req.response.headers.contentType = ContentType.json;
    req.response.write(jsonEncode(response));
    await req.response.close();
  }

  Future<void> _handleSyncRequest(HttpRequest req) async {
    final encryptedBody = await utf8.decoder.bind(req).join();
    final encryptedData = jsonDecode(encryptedBody) as Map<String, dynamic>;

    if (encryptedData['encrypted'] != true ||
        encryptedData['v'] != LanSyncCrypto.protocolVersion) {
      req.response.statusCode = HttpStatus.badRequest;
      req.response.headers.contentType = ContentType.json;
      req.response.write(jsonEncode({'error': 'v2 encryption required'}));
      await req.response.close();
      return;
    }

    final sessionId = encryptedData['sessionId']?.toString();
    final sessionKey = _getSessionKey(sessionId);
    if (sessionKey == null) {
      req.response.statusCode = HttpStatus.unauthorized;
      req.response.headers.contentType = ContentType.json;
      req.response.write(
        jsonEncode({'error': 'invalid or expired crypto session'}),
      );
      await req.response.close();
      return;
    }

    final decryptedBody = LanSyncCrypto.decryptString(
      sessionKey,
      encryptedData['payload'].toString(),
    );
    final data = jsonDecode(decryptedBody) as Map<String, dynamic>;

    final remoteDeviceId = data['deviceId'] ?? '';
    final remoteUserId = data['userId'] ?? '';
    final remoteDeviceName = data['deviceName'] ?? '';
    final action = data['action'] ?? 'request';

    // quick_pair 使用一次性二维码令牌授权，允许跨账号或离线 local 账号直接互传。
    if (action != 'quick_pair' &&
        remoteUserId != _currentUserId &&
        !_discoverAllDevices) {
      await _writeEncryptedError(
        req,
        sessionKey,
        'account mismatch',
        statusCode: HttpStatus.forbidden,
      );
      return;
    }

    if (action == 'request') {
      final ip = req.connectionInfo?.remoteAddress.address ?? '';
      final port = data['port'] ?? 54322;

      final token = DateTime.now().millisecondsSinceEpoch.toString();
      final device = LanDevice(
        deviceId: remoteDeviceId,
        userId: remoteUserId,
        deviceName: remoteDeviceName,
        ip: ip,
        port: port,
        lastSeen: DateTime.now().millisecondsSinceEpoch,
      );

      _pendingRequests[remoteDeviceId] = device;
      _pendingTokens[remoteDeviceId] = token;

      _incomingRequestCtrl.add(device);

      await _writeEncryptedJson(req, sessionKey, {
        'pending': true,
        'token': token,
      });
      return;
    }

    if (action == 'confirm' ||
        action == 'quick_pair' ||
        action == 'auto_sync') {
      if (action == 'confirm') {
        final pendingDevice = _pendingRequests[remoteDeviceId];
        final pendingToken = _pendingTokens[remoteDeviceId];
        final receivedToken = data['token']?.toString();

        if (pendingDevice == null ||
            pendingToken == null ||
            receivedToken != pendingToken) {
          await _writeEncryptedError(req, sessionKey, 'no pending request');
          return;
        }
        _pendingRequests.remove(remoteDeviceId);
        _pendingTokens.remove(remoteDeviceId);
      } else if (action == 'quick_pair') {
        final receivedToken = data['token']?.toString() ?? '';
        final now = DateTime.now().millisecondsSinceEpoch;
        if (_activeQuickPairToken == null ||
            receivedToken.isEmpty ||
            receivedToken != _activeQuickPairToken ||
            now > _activeQuickPairExpiresAt) {
          await _writeEncryptedError(
            req,
            sessionKey,
            '配对二维码已过期或失效，请重新生成',
            statusCode: HttpStatus.unauthorized,
          );
          return;
        }
        // 一次性令牌用完即销毁，防止重放。
        cancelQuickPairSession();
      } else if (action == 'auto_sync') {
        if (!_autoSyncEnabled || remoteUserId != _currentUserId) {
          await _writeEncryptedError(
            req,
            sessionKey,
            'auto sync disabled',
            statusCode: HttpStatus.forbidden,
          );
          return;
        }
      }

      final isSilent = action == 'auto_sync';
      if (!isSilent) {
        _emitProgress('正在接收数据...');
        _emitProgressValue(0.1);
      }

      final syncConfig = _parseSyncConfig(data['config']);
      final username = _currentUserId ?? 'local';
      final mergeCounts = await _mergeSyncBundle(
        username: username,
        data: data,
        config: syncConfig,
        emitProgress: !isSilent,
      );

      final localData = await _gatherLocalData(username, syncConfig);
      await _writeEncryptedJson(req, sessionKey, {
        'success': true,
        'todos': syncConfig.syncTodos ? localData['todos'] : [],
        'countdowns': syncConfig.syncCountdowns ? localData['countdowns'] : [],
        'timeLogs': syncConfig.syncTimeLogs ? localData['timeLogs'] : [],
        'pomodoroTags': syncConfig.syncPomodoroTags
            ? localData['pomodoroTags']
            : [],
        'pomodoroRecords': syncConfig.syncPomodoroRecords
            ? localData['pomodoroRecords']
            : [],
        'courses': syncConfig.syncCourses ? localData['courses'] : [],
        if (syncConfig.syncSecrets && localData['secrets'] != null)
          'secrets': localData['secrets'],
        if (syncConfig.syncSettings && localData['settings'] != null)
          'settings': localData['settings'],
      });

      final result = LanSyncResult(
        success: true,
        message: action == 'quick_pair'
            ? '面对面同步成功（$remoteDeviceName）'
            : action == 'auto_sync'
            ? '局域网自动同步完成（$remoteDeviceName）'
            : '局域网同步完成（$remoteDeviceName）',
        todosSynced: mergeCounts.todos,
        countdownsSynced: mergeCounts.countdowns,
        timeLogsSynced: mergeCounts.timeLogs,
        pomodoroTagsSynced: mergeCounts.pomodoroTags,
        pomodoroRecordsSynced: mergeCounts.pomodoroRecords,
        coursesSynced: mergeCounts.courses,
        progress: 1.0,
      );
      if (action == 'quick_pair' && !_quickPairCompletedCtrl.isClosed) {
        _quickPairCompletedCtrl.add(result);
      }
      if (!_syncCompletedCtrl.isClosed) {
        _syncCompletedCtrl.add(result);
      }

      if (!isSilent) {
        _emitProgressValue(1.0);
        _emitProgress('同步完成');
      }
      return;
    }
  }

  Future<void> _writeEncryptedJson(
    HttpRequest req,
    Uint8List sessionKey,
    Map<String, dynamic> body, {
    int statusCode = HttpStatus.ok,
  }) async {
    req.response.statusCode = statusCode;
    req.response.headers.contentType = ContentType.json;
    req.response.write(
      jsonEncode({
        'v': LanSyncCrypto.protocolVersion,
        'encrypted': true,
        'payload': LanSyncCrypto.encryptString(sessionKey, jsonEncode(body)),
      }),
    );
    await req.response.close();
  }

  Future<void> _writeEncryptedError(
    HttpRequest req,
    Uint8List sessionKey,
    String message, {
    int statusCode = HttpStatus.ok,
  }) async {
    await _writeEncryptedJson(
      req,
      sessionKey,
      {'error': message},
      statusCode: statusCode,
    );
  }

  LanSyncConfig _parseSyncConfig(dynamic raw) {
    if (raw is! Map) return LanSyncConfig();
    return LanSyncConfig(
      syncTodos: raw['todos'] ?? true,
      syncCountdowns: raw['countdowns'] ?? true,
      syncTimeLogs: raw['timeLogs'] ?? true,
      syncPomodoroTags: raw['pomodoroTags'] ?? true,
      syncPomodoroRecords: raw['pomodoroRecords'] ?? true,
      syncCourses: raw['courses'] ?? true,
      syncSecrets: raw['secrets'] ?? true,
      syncSettings: raw['settings'] ?? false,
    );
  }

  List<Map<String, dynamic>> _extractList(dynamic raw) {
    if (raw is! List) return const [];
    return raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<void> _mergeLock = Future.value();

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
  }) {
    final prev = _mergeLock;
    final completer =
        Completer<
          ({
            int todos,
            int countdowns,
            int timeLogs,
            int pomodoroTags,
            int pomodoroRecords,
            int courses,
          })
        >();
    _mergeLock = completer.future.then((_) {}, onError: (_) {});

    () async {
      try {
        await prev;
        final result = await _mergeSyncBundleLocked(
          username: username,
          data: data,
          config: config,
          emitProgress: emitProgress,
        );
        completer.complete(result);
      } catch (e, st) {
        completer.completeError(e, st);
      }
    }();

    return completer.future;
  }

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
  _mergeSyncBundleLocked({
    required String username,
    required Map<String, dynamic> data,
    required LanSyncConfig config,
    bool emitProgress = true,
  }) async {
    int todosSynced = 0;
    int countdownsSynced = 0;
    int timeLogsSynced = 0;
    int pomodoroTagsSynced = 0;
    int pomodoroRecordsSynced = 0;
    int coursesSynced = 0;

    final step = config.totalCount > 0 ? 0.4 / config.totalCount : 0.1;
    double progress = 0.5;

    if (config.syncTodos) {
      await _mergeTodos(
        username,
        _extractList(data['todos']),
        (c) => todosSynced = c,
      );
      if (emitProgress) {
        progress += step;
        _emitProgressValue(progress);
        _emitProgress('合并待办完成...');
      }
    }

    if (config.syncCountdowns) {
      await _mergeCountdowns(
        username,
        _extractList(data['countdowns']),
        (c) => countdownsSynced = c,
      );
      if (emitProgress) {
        progress += step;
        _emitProgressValue(progress);
        _emitProgress('合并倒数日完成...');
      }
    }

    if (config.syncTimeLogs) {
      await _mergeTimeLogs(
        username,
        _extractList(data['timeLogs']),
        (c) => timeLogsSynced = c,
      );
      if (emitProgress) {
        progress += step;
        _emitProgressValue(progress);
        _emitProgress('合并时间日志完成...');
      }
    }

    if (config.syncPomodoroTags) {
      await _mergePomodoroTags(
        _extractList(data['pomodoroTags']),
        (c) => pomodoroTagsSynced = c,
      );
      if (emitProgress) {
        progress += step;
        _emitProgressValue(progress);
        _emitProgress('合并番茄标签完成...');
      }
    }

    if (config.syncPomodoroRecords) {
      await _mergePomodoroRecords(
        _extractList(data['pomodoroRecords']),
        (c) => pomodoroRecordsSynced = c,
      );
      if (emitProgress) {
        progress += step;
        _emitProgressValue(progress);
        _emitProgress('合并番茄记录完成...');
      }
    }

    if (config.syncCourses) {
      await _mergeCourses(
        username,
        _extractList(data['courses']),
        (c) => coursesSynced = c,
      );
      if (emitProgress) {
        progress += step;
        _emitProgressValue(progress);
        _emitProgress('合并课程完成...');
      }
    }

    if (config.syncSecrets && data['secrets'] is Map) {
      await LanSyncPrivateData.mergeSecrets(
        Map<String, dynamic>.from(data['secrets'] as Map),
      );
      if (emitProgress) {
        progress += step;
        _emitProgressValue(progress);
        _emitProgress('合并密钥与 AI 配置完成...');
      }
    }

    if (config.syncSettings && data['settings'] is Map) {
      await LanSyncPrivateData.mergePortableSettings(
        Map<String, dynamic>.from(data['settings'] as Map),
      );
      if (emitProgress) {
        progress += step;
        _emitProgressValue(progress);
        _emitProgress('合并偏好设置完成...');
      }
    }

    return (
      todos: todosSynced,
      countdowns: countdownsSynced,
      timeLogs: timeLogsSynced,
      pomodoroTags: pomodoroTagsSynced,
      pomodoroRecords: pomodoroRecordsSynced,
      courses: coursesSynced,
    );
  }

  Future<void> _mergeTodos(
    String username,
    List<Map<String, dynamic>> remote,
    Function(int) onChanged,
  ) async {
    if (remote.isEmpty) return;
    final local = await StorageService.getTodos(username);
    final Map<String, TodoItem> merged = {for (var t in local) t.id: t};
    bool changed = false;
    for (var r in remote) {
      final remoteItem = TodoItem.fromJson(r);
      final existing = merged[remoteItem.id];
      if (existing == null) {
        if (!remoteItem.isDeleted) {
          merged[remoteItem.id] = remoteItem;
          changed = true;
        }
      } else {
        if (_lwwWins(remoteItem, existing)) {
          merged[remoteItem.id] = remoteItem;
          changed = true;
        }
      }
    }
    if (changed) {
      await StorageService.saveTodos(
        username,
        merged.values.toList(),
        sync: false,
      );
      onChanged(merged.length);
    }
  }

  Future<void> _mergeCountdowns(
    String username,
    List<Map<String, dynamic>> remote,
    Function(int) onChanged,
  ) async {
    if (remote.isEmpty) return;
    final local = await StorageService.getCountdowns(username);
    final Map<String, CountdownItem> merged = {for (var c in local) c.id: c};
    bool changed = false;
    for (var r in remote) {
      final remoteItem = CountdownItem.fromJson(r);
      final existing = merged[remoteItem.id];
      if (existing == null) {
        if (!remoteItem.isDeleted) {
          merged[remoteItem.id] = remoteItem;
          changed = true;
        }
      } else {
        if (_lwwWinsCountdown(remoteItem, existing)) {
          merged[remoteItem.id] = remoteItem;
          changed = true;
        }
      }
    }
    if (changed) {
      await StorageService.saveCountdowns(
        username,
        merged.values.toList(),
        sync: false,
      );
      onChanged(merged.length);
    }
  }

  Future<void> _mergeTimeLogs(
    String username,
    List<Map<String, dynamic>> remote,
    Function(int) onChanged,
  ) async {
    if (remote.isEmpty) return;
    final local = await StorageService.getTimeLogs(username);
    final Map<String, TimeLogItem> merged = {for (var t in local) t.id: t};
    bool changed = false;
    for (var r in remote) {
      final remoteItem = TimeLogItem.fromJson(r);
      final existing = merged[remoteItem.id];
      if (existing == null) {
        if (!remoteItem.isDeleted) {
          merged[remoteItem.id] = remoteItem;
          changed = true;
        }
      } else {
        if (_lwwWinsTimeLog(remoteItem, existing)) {
          merged[remoteItem.id] = remoteItem;
          changed = true;
        }
      }
    }
    if (changed) {
      await StorageService.saveTimeLogs(
        username,
        merged.values.toList(),
        sync: false,
      );
      onChanged(merged.length);
    }
  }

  Future<void> _mergePomodoroTags(
    List<Map<String, dynamic>> remote,
    Function(int) onChanged,
  ) async {
    if (remote.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final s = prefs.getString('pomodoro_tags_v2');
    final List<PomodoroTag> localAll = s == null
        ? []
        : (jsonDecode(s) as List).map((e) => PomodoroTag.fromJson(e)).toList();
    final Map<String, PomodoroTag> merged = {for (var t in localAll) t.uuid: t};
    bool changed = false;
    for (var r in remote) {
      final remoteTag = PomodoroTag.fromJson(r);
      final existing = merged[remoteTag.uuid];
      if (existing == null) {
        if (!remoteTag.isDeleted) {
          merged[remoteTag.uuid] = remoteTag;
          changed = true;
        }
      } else {
        if (remoteTag.updatedAt > existing.updatedAt) {
          merged[remoteTag.uuid] = remoteTag;
          changed = true;
        }
      }
    }
    if (changed) {
      await PomodoroService.saveTags(merged.values.toList());
      onChanged(merged.length);
    }
  }

  Future<void> _mergePomodoroRecords(
    List<Map<String, dynamic>> remote,
    Function(int) onChanged,
  ) async {
    if (remote.isEmpty) return;
    final remoteRecords = remote.map(PomodoroRecord.fromJson).toList();
    final changed = await PomodoroService.mergeRecordsLww(remoteRecords);
    if (changed) {
      onChanged(remoteRecords.length);
    }
  }

  Future<void> _mergeCourses(
    String username,
    List<Map<String, dynamic>> remote,
    Function(int) onChanged,
  ) async {
    if (remote.isEmpty) return;
    final local = await CourseService.getAllCourses(
      username,
      applyCalendarAdjustments: false,
    );
    final remoteCourses = remote.map(CourseItem.fromJson).toList();
    final merged = CourseScheduleSemantics.mergeBySlot(local, remoteCourses);
    final localByUuid = {for (final course in local) course.uuid: course};

    bool sameCourse(CourseItem left, CourseItem right) =>
        left.courseName == right.courseName &&
        left.teacherName == right.teacherName &&
        left.date == right.date &&
        left.weekday == right.weekday &&
        left.startTime == right.startTime &&
        left.endTime == right.endTime &&
        left.weekIndex == right.weekIndex &&
        left.roomName == right.roomName &&
        left.lessonType == right.lessonType &&
        left.semesterId == right.semesterId &&
        left.teamUuid == right.teamUuid &&
        left.version == right.version &&
        left.updatedAt == right.updatedAt &&
        left.isDeleted == right.isDeleted;

    final changed =
        merged.length != local.length ||
        merged.any((course) {
          final old = localByUuid[course.uuid];
          return old == null || !sameCourse(old, course);
        });
    if (changed) {
      await CourseService.saveCourses(username, merged);
      onChanged(merged.length);
    }
  }

  bool _lwwWins(TodoItem remote, TodoItem local) =>
      LanSyncLww.isTodoWinner(remote, local);

  bool _lwwWinsCountdown(CountdownItem remote, CountdownItem local) =>
      LanSyncLww.isCountdownWinner(remote, local);

  bool _lwwWinsTimeLog(TimeLogItem remote, TimeLogItem local) =>
      LanSyncLww.isTimeLogWinner(remote, local);

  Future<Map<String, dynamic>> _gatherLocalData(
    String username, [
    LanSyncConfig? config,
  ]) async {
    config ??= LanSyncConfig();
    final todos = config.syncTodos
        ? await StorageService.getTodos(username)
        : [];
    final countdowns = config.syncCountdowns
        ? await StorageService.getCountdowns(username)
        : [];
    final timeLogs = config.syncTimeLogs
        ? await StorageService.getTimeLogs(username)
        : [];
    final pomodoroTags = config.syncPomodoroTags
        ? await PomodoroService.getTags()
        : [];
    final pomodoroRecords = config.syncPomodoroRecords
        ? await PomodoroService.getRecords()
        : [];
    final courses = config.syncCourses
        ? await CourseService.getAllCourses(username)
        : [];
    final secrets = config.syncSecrets
        ? await LanSyncPrivateData.gatherSecrets()
        : null;
    final settings = config.syncSettings
        ? await LanSyncPrivateData.gatherPortableSettings()
        : null;

    return {
      'todos': todos.map((t) => t.toJson()).toList(),
      'countdowns': countdowns.map((c) => c.toJson()).toList(),
      'timeLogs': timeLogs.map((t) => t.toJson()).toList(),
      'pomodoroTags': pomodoroTags.map((t) => t.toJson()).toList(),
      'pomodoroRecords': pomodoroRecords.map((r) => r.toJson()).toList(),
      'courses': courses.map((c) => c.toJson()).toList(),
      if (secrets != null && secrets.isNotEmpty) 'secrets': secrets,
      if (settings != null && settings.isNotEmpty) 'settings': settings,
    };
  }

  Future<void> _startUdpDiscovery() async {
    try {
      _udpSocket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        _discoveryPort,
        reuseAddress: true,
      );
      _udpSocket!.broadcastEnabled = true;
      await _joinMulticastOnLanInterfaces(
        _udpSocket!,
        InternetAddress(_multicastGroup),
      );

      _udpSubscription = _udpSocket!.listen((event) {
        if (event != RawSocketEvent.read) return;
        Datagram? datagram;
        while ((datagram = _udpSocket?.receive()) != null) {
          _processDiscoveryDatagram(datagram);
        }
      }, onError: (_) {});
    } catch (_) {}
  }

  void _processDiscoveryDatagram(Datagram? datagram) {
    if (datagram == null) return;
    try {
      final data =
          jsonDecode(utf8.decode(datagram.data)) as Map<String, dynamic>;
      final type = data['type']?.toString();
      if (type == 'discovery_probe') {
        if (data['deviceId'] != _currentDeviceId && _udpSocket != null) {
          final reply = jsonEncode({
            'type': 'discovery',
            'deviceId': _currentDeviceId,
            'userId': _currentUserId,
            'deviceName': _currentDeviceName,
            'port': _serverPort,
          });
          _udpSocket!.send(
            utf8.encode(reply),
            datagram.address,
            datagram.port,
          );
        }
        return;
      }
      if (type == 'discovery' &&
          data['deviceId'] != _currentDeviceId &&
          (_discoverAllDevices ||
              _isSameUser(data['userId']?.toString(), _currentUserId))) {
        final device = LanDevice(
          deviceId: data['deviceId'],
          userId: data['userId'],
          deviceName: data['deviceName'],
          ip: datagram.address.address,
          port: data['port'] ?? _defaultHttpPort,
          lastSeen: DateTime.now().millisecondsSinceEpoch,
        );
        final isNew = !_devices.containsKey(device.deviceId);
        _devices[device.deviceId] = device;
        _emitDevices();
        if (isNew && _udpSocket != null && _serverPort != null) {
          final reply = jsonEncode({
            'type': 'discovery',
            'deviceId': _currentDeviceId,
            'userId': _currentUserId,
            'deviceName': _currentDeviceName,
            'port': _serverPort,
          });
          _udpSocket!.send(
            utf8.encode(reply),
            datagram.address,
            _discoveryPort,
          );
        }
        _maybeAutoSync(device);
      }
    } catch (_) {}
  }

  Future<void> _startMdnsDiscovery() async {
    try {
      final useReusePort =
          Platform.isMacOS || Platform.isIOS || Platform.isLinux;
      try {
        _mdnsSocket = await RawDatagramSocket.bind(
          InternetAddress.anyIPv4,
          LanMdnsCodec.mdnsPort,
          reuseAddress: true,
          reusePort: useReusePort,
        );
      } catch (_) {
        _mdnsSocket = await RawDatagramSocket.bind(
          InternetAddress.anyIPv4,
          LanMdnsCodec.mdnsPort,
          reuseAddress: true,
        );
      }
      await _joinMulticastOnLanInterfaces(
        _mdnsSocket!,
        InternetAddress(LanMdnsCodec.multicastAddress),
      );
      _mdnsSubscription = _mdnsSocket!.listen((event) {
        if (event != RawSocketEvent.read) return;
        Datagram? datagram;
        while ((datagram = _mdnsSocket?.receive()) != null) {
          _processMdnsDatagram(datagram);
        }
      }, onError: (_) {});
      _mdnsSocket!.send(
        LanMdnsCodec.buildQuery(),
        InternetAddress(LanMdnsCodec.multicastAddress),
        LanMdnsCodec.mdnsPort,
      );
    } catch (_) {
      // 部分平台或受限网络可能禁止绑定 5353，保留已有 UDP 组播与子网扫描兜底。
    }
  }

  void _processMdnsDatagram(Datagram? datagram) {
    if (datagram == null || !_isRunning) return;
    final packet = datagram.data;
    if (LanMdnsCodec.isQueryForService(packet)) {
      _broadcastMdnsAnnouncement();
      return;
    }
    final peer = LanMdnsCodec.parseAnnouncement(
      packet,
      fallbackIp: datagram.address.address,
    );
    if (peer == null || peer.deviceId == _currentDeviceId) return;
    if (!_discoverAllDevices && !_isSameUser(peer.userId, _currentUserId)) {
      return;
    }

    final device = LanDevice(
      deviceId: peer.deviceId,
      userId: peer.userId,
      deviceName: peer.deviceName,
      ip: peer.ip,
      port: peer.port,
      lastSeen: DateTime.now().millisecondsSinceEpoch,
    );
    _devices[device.deviceId] = device;
    _emitDevices();

    if (peer.autoSync) {
      _maybeAutoSync(device);
    }
  }

  void _broadcastMdnsAnnouncement() {
    if (_mdnsSocket == null || !_isRunning || _serverPort == null) return;
    final ip = _localIp;
    if (ip == null || ip.isEmpty) return;
    try {
      final packet = LanMdnsCodec.buildAnnouncement(
        deviceId: _currentDeviceId ?? '',
        userId: _currentUserId ?? 'local',
        deviceName: _currentDeviceName ?? '未知设备',
        ip: ip,
        port: _serverPort!,
        autoSync: _autoSyncEnabled,
      );
      _mdnsSocket!.send(
        packet,
        InternetAddress(LanMdnsCodec.multicastAddress),
        LanMdnsCodec.mdnsPort,
      );
    } catch (_) {}
  }

  void _maybeAutoSync(LanDevice device) {
    if (!_autoSyncEnabled || _isSyncing) return;
    if (!_isSameUser(device.userId, _currentUserId)) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    final last = _lastAutoSyncAt[device.deviceId] ?? 0;
    if (now - last < _autoSyncCooldownMs) return;
    _lastAutoSyncAt[device.deviceId] = now;
    unawaited(_autoSyncWithDevice(device));
  }

  void _startDiscoveryBroadcast() {
    _discoveryTimer?.cancel();
    _broadcastDiscovery();
    _discoveryTimer = Timer.periodic(
      _discoveryInterval,
      (_) => _broadcastDiscovery(),
    );
  }

  void _broadcastDiscovery() {
    if (!_isRunning) return;
    if (_currentUserId == null || _currentUserId == 'local') {
      unawaited(_ensureIdentity());
    }
    if (_udpSocket != null) {
      try {
        final message = utf8.encode(
          jsonEncode({
            'type': 'discovery',
            'deviceId': _currentDeviceId,
            'userId': _currentUserId,
            'deviceName': _currentDeviceName,
            'port': _serverPort,
          }),
        );
        _udpSocket!.send(
          message,
          InternetAddress(_multicastGroup),
          _discoveryPort,
        );
        _udpSocket!.send(
          message,
          InternetAddress('255.255.255.255'),
          _discoveryPort,
        );
        unawaited(_sendSubnetBroadcasts(_udpSocket!, message));
      } catch (_) {}
    }
    _broadcastMdnsAnnouncement();
  }

  Future<void> _sendSubnetBroadcasts(
    RawDatagramSocket socket,
    List<int> payload,
  ) async {
    try {
      final lanInterfaces = await _getLanIpv4Interfaces();
      for (final entry in lanInterfaces) {
        final parts = entry.address.address.split('.');
        if (parts.length == 4) {
          final bcast = '${parts[0]}.${parts[1]}.${parts[2]}.255';
          try {
            socket.send(payload, InternetAddress(bcast), _discoveryPort);
          } catch (_) {}
        }
      }
    } catch (_) {}
  }

  bool _backgroundAutoSyncInProgress = false;

  /// 应用启动或切回前台时，按配置执行一次轻量局域网无感发现并双向合并。
  Future<void> triggerBackgroundAutoSync() async {
    if (_backgroundAutoSyncInProgress || _isSyncing) return;
    _backgroundAutoSyncInProgress = true;

    try {
      final prefs = await SharedPreferences.getInstance();
      final autoEnabled = prefs.getBool(_prefAutoSyncEnabled) ?? true;
      _autoSyncEnabled = autoEnabled;
      if (!autoEnabled) return;

      final loggedInUser = (await UserSessionStorage.getCurrentUsername())
          ?.trim();
      if (loggedInUser == null || loggedInUser.isEmpty) return;

      await _ensureIdentity();

      if (!_isRunning) {
        final isDesktop =
            Platform.isWindows || Platform.isMacOS || Platform.isLinux;
        final desktopDaemon =
            isDesktop && (prefs.getBool(_prefDesktopDaemonEnabled) ?? true);
        await start(daemonMode: desktopDaemon);
      } else {
        _broadcastDiscovery();
      }

      await Future.delayed(const Duration(milliseconds: 1200));
      if (!_devices.values.any((d) => _isSameUser(d.userId, _currentUserId))) {
        await _scanAllInterfaces(ignoreRunningState: true);
      }

      for (final device in _devices.values.toList()) {
        _maybeAutoSync(device);
      }
    } catch (e) {
      debugPrint('[LanSync] triggerBackgroundAutoSync error: $e');
    } finally {
      _backgroundAutoSyncInProgress = false;
    }
  }

  /// 触发一次轻量局域网设备扫描（供手动同步弹窗实时检测在线设备）。
  Future<void> scanForPeersOnce() async {
    await _ensureIdentity();
    if (!_isRunning) {
      final prefs = await SharedPreferences.getInstance();
      final isDesktop =
          Platform.isWindows || Platform.isMacOS || Platform.isLinux;
      final desktopDaemon =
          isDesktop && (prefs.getBool(_prefDesktopDaemonEnabled) ?? true);
      await start(daemonMode: desktopDaemon);
    } else {
      _broadcastDiscovery();
    }
    await Future.delayed(const Duration(milliseconds: 1000));
    if (!_devices.values.any((d) => _isSameUser(d.userId, _currentUserId))) {
      await _scanAllInterfaces(ignoreRunningState: true);
    }
    _emitDevices();
  }

  /// 首页手动触发局域网同步：向同账号在线局域网设备发起一次双向合并。
  Future<LanSyncResult> syncManualWithPeers({LanSyncConfig? config}) async {
    if (_isSyncing) return LanSyncResult(success: false, message: '同步进行中');
    await _ensureIdentity();

    final sameAccountPeers = _devices.values
        .where((d) => _isSameUser(d.userId, _currentUserId))
        .toList();

    if (sameAccountPeers.isEmpty) {
      await _discoverOnce(duration: const Duration(milliseconds: 2000));
    }

    final peers = _devices.values
        .where((d) => _isSameUser(d.userId, _currentUserId))
        .toList();
    if (peers.isEmpty) {
      return LanSyncResult(
        success: false,
        message: '未发现同账号在线局域网设备，请确认另一台设备已开启局域网服务并处于同一 Wi-Fi',
      );
    }

    LanSyncResult? lastSuccess;
    LanSyncResult? lastFailure;
    for (final peer in peers) {
      final res = await _performDirectSync(
        ip: peer.ip,
        port: peer.port,
        deviceName: peer.deviceName,
        action: 'auto_sync',
        config: config ?? LanSyncConfig(),
        silent: false,
      );
      if (res.success) {
        lastSuccess = res;
      } else {
        lastFailure = res;
      }
    }
    return lastSuccess ??
        lastFailure ??
        LanSyncResult(success: false, message: '局域网同步失败');
  }

  Future<void> _discoverOnce({
    Duration duration = const Duration(seconds: 3),
  }) async {
    RawDatagramSocket? tempMdnsSocket;
    RawDatagramSocket? tempUdpSocket;
    StreamSubscription<RawSocketEvent>? mdnsSub;
    StreamSubscription<RawSocketEvent>? udpSub;

    try {
      Future<void> bindTempMdns() async {
        try {
          final useReusePort =
              Platform.isMacOS || Platform.isIOS || Platform.isLinux;
          try {
            tempMdnsSocket = await RawDatagramSocket.bind(
              InternetAddress.anyIPv4,
              LanMdnsCodec.mdnsPort,
              reuseAddress: true,
              reusePort: useReusePort,
            );
          } catch (_) {
            tempMdnsSocket = await RawDatagramSocket.bind(
              InternetAddress.anyIPv4,
              LanMdnsCodec.mdnsPort,
              reuseAddress: true,
            );
          }
          await _joinMulticastOnLanInterfaces(
            tempMdnsSocket!,
            InternetAddress(LanMdnsCodec.multicastAddress),
          );
          mdnsSub = tempMdnsSocket!.listen((event) {
            if (event != RawSocketEvent.read) return;
            Datagram? datagram;
            while ((datagram = tempMdnsSocket?.receive()) != null) {
              final peer = LanMdnsCodec.parseAnnouncement(
                datagram!.data,
                fallbackIp: datagram.address.address,
              );
              if (peer == null ||
                  peer.deviceId == _currentDeviceId ||
                  !_isSameUser(peer.userId, _currentUserId)) {
                continue;
              }
              _devices[peer.deviceId] = LanDevice(
                deviceId: peer.deviceId,
                userId: peer.userId,
                deviceName: peer.deviceName,
                ip: peer.ip,
                port: peer.port,
                lastSeen: DateTime.now().millisecondsSinceEpoch,
              );
              _emitDevices();
            }
          }, onError: (_) {});
          tempMdnsSocket!.send(
            LanMdnsCodec.buildQuery(),
            InternetAddress(LanMdnsCodec.multicastAddress),
            LanMdnsCodec.mdnsPort,
          );
        } catch (_) {}
      }

      Future<void> bindTempUdp() async {
        try {
          tempUdpSocket = await RawDatagramSocket.bind(
            InternetAddress.anyIPv4,
            0,
          );
          tempUdpSocket!.broadcastEnabled = true;
          await _joinMulticastOnLanInterfaces(
            tempUdpSocket!,
            InternetAddress(_multicastGroup),
          );
          udpSub = tempUdpSocket!.listen((event) {
            if (event != RawSocketEvent.read) return;
            Datagram? datagram;
            while ((datagram = tempUdpSocket?.receive()) != null) {
              try {
                final data =
                    jsonDecode(utf8.decode(datagram!.data))
                        as Map<String, dynamic>;
                if (data['type'] == 'discovery' &&
                    data['deviceId'] != _currentDeviceId &&
                    _isSameUser(data['userId']?.toString(), _currentUserId)) {
                  final device = LanDevice(
                    deviceId: data['deviceId'],
                    userId: data['userId'],
                    deviceName: data['deviceName'],
                    ip: datagram.address.address,
                    port: data['port'] ?? _defaultHttpPort,
                    lastSeen: DateTime.now().millisecondsSinceEpoch,
                  );
                  _devices[device.deviceId] = device;
                  _emitDevices();
                }
              } catch (_) {}
            }
          }, onError: (_) {});

          final probe = utf8.encode(
            jsonEncode({
              'type': 'discovery_probe',
              'deviceId': _currentDeviceId,
              'userId': _currentUserId,
              'deviceName': _currentDeviceName,
            }),
          );
          tempUdpSocket!.send(
            probe,
            InternetAddress(_multicastGroup),
            _discoveryPort,
          );
          tempUdpSocket!.send(
            probe,
            InternetAddress('255.255.255.255'),
            _discoveryPort,
          );
          await _sendSubnetBroadcasts(tempUdpSocket!, probe);
        } catch (_) {}
      }

      await Future.wait([bindTempMdns(), bindTempUdp()]);
      await Future.delayed(duration);
      if (!_devices.values.any((d) => _isSameUser(d.userId, _currentUserId))) {
        await _scanAllInterfaces(ignoreRunningState: true);
      }
      _emitDevices();
    } finally {
      await mdnsSub?.cancel();
      await udpSub?.cancel();
      tempMdnsSocket?.close();
      tempUdpSocket?.close();
    }
  }

  /// 面对面扫码/配对码直连互同步（无需等待手动确认弹窗）。
  Future<LanSyncResult> syncWithPairingCode(
    String rawCode, {
    LanSyncConfig? config,
  }) async {
    if (_isSyncing) return LanSyncResult(success: false, message: '同步进行中');
    final pairing = LanPairingPayload.tryParse(rawCode);
    if (pairing == null) {
      return LanSyncResult(success: false, message: '无效的配对二维码或配对码');
    }
    if (pairing.isExpired()) {
      return LanSyncResult(success: false, message: '配对二维码已过期，请让对方重新生成');
    }

    await _ensureIdentity();
    if (pairing.deviceId.isNotEmpty && pairing.deviceId == _currentDeviceId) {
      return LanSyncResult(success: false, message: '不能与当前设备自身配对');
    }

    return _performDirectSync(
      ip: pairing.ip,
      port: pairing.port,
      deviceName: pairing.deviceName,
      action: 'quick_pair',
      token: pairing.token,
      config:
          config ??
          LanSyncConfig(
            syncSecrets: _syncSecretsEnabled,
            syncSettings: _syncSettingsEnabled,
          ),
      silent: false,
    );
  }

  Future<LanSyncResult> _autoSyncWithDevice(LanDevice device) async {
    if (_isSyncing) return LanSyncResult(success: false, message: '同步进行中');
    return _performDirectSync(
      ip: device.ip,
      port: device.port,
      deviceName: device.deviceName,
      action: 'auto_sync',
      config: LanSyncConfig(
        syncSecrets: _syncSecretsEnabled,
        syncSettings: _syncSettingsEnabled,
      ),
      silent: true,
    );
  }

  Future<LanSyncResult> _performDirectSync({
    required String ip,
    required int port,
    required String deviceName,
    required String action,
    String? token,
    required LanSyncConfig config,
    required bool silent,
  }) async {
    _isSyncing = true;
    if (!silent) _emitProgressValue(0.05);
    HttpClient? client;
    try {
      if (!silent) _emitProgress('正在连接 $deviceName...');
      final username = _currentUserId ?? 'local';
      final localData = await _gatherLocalData(username, config);

      final payload = <String, dynamic>{
        'deviceId': _currentDeviceId,
        'userId': username,
        'deviceName': _currentDeviceName,
        'port': _serverPort ?? 0,
        'action': action,
        'token': ?token,
        'config': config.toJson(),
        'todos': config.syncTodos ? localData['todos'] : [],
        'countdowns': config.syncCountdowns ? localData['countdowns'] : [],
        'timeLogs': config.syncTimeLogs ? localData['timeLogs'] : [],
        'pomodoroTags': config.syncPomodoroTags
            ? localData['pomodoroTags']
            : [],
        'pomodoroRecords': config.syncPomodoroRecords
            ? localData['pomodoroRecords']
            : [],
        'courses': config.syncCourses ? localData['courses'] : [],
        if (config.syncSecrets && localData['secrets'] != null)
          'secrets': localData['secrets'],
        if (config.syncSettings && localData['settings'] != null)
          'settings': localData['settings'],
      };

      if (!silent) {
        _emitProgress('正在交换加密数据...');
        _emitProgressValue(0.2);
      }

      client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
      final responseData = await _postEncryptedSync(client, ip, port, payload);
      if (responseData['success'] != true) {
        return LanSyncResult(
          success: false,
          message: responseData['error']?.toString() ?? '同步失败',
        );
      }

      if (!silent) {
        _emitProgress('正在按 LWW 规则合并数据...');
        _emitProgressValue(0.6);
      }

      final counts = await _mergeSyncBundle(
        username: username,
        data: responseData,
        config: config,
        emitProgress: !silent,
      );

      if (!silent) {
        _emitProgressValue(1.0);
        _emitProgress('同步完成');
      } else {
        _emitStatus('已与 $deviceName 自动同步');
      }

      final result = LanSyncResult(
        success: true,
        message: action == 'quick_pair'
            ? '面对面局域网同步成功（$deviceName）'
            : silent
            ? '局域网自动同步成功（$deviceName）'
            : '局域网同步成功（$deviceName）',
        todosSynced: counts.todos,
        countdownsSynced: counts.countdowns,
        timeLogsSynced: counts.timeLogs,
        pomodoroTagsSynced: counts.pomodoroTags,
        pomodoroRecordsSynced: counts.pomodoroRecords,
        coursesSynced: counts.courses,
        progress: 1.0,
      );
      if (!_syncCompletedCtrl.isClosed) {
        _syncCompletedCtrl.add(result);
      }
      return result;
    } catch (e) {
      return LanSyncResult(success: false, message: '连接失败: $e');
    } finally {
      client?.close(force: true);
      _isSyncing = false;
    }
  }

  Future<LanSyncResult> syncWithDevice(
    LanDevice device, {
    LanSyncConfig? config,
  }) async {
    if (_isSyncing) return LanSyncResult(success: false, message: '同步进行中');
    _isSyncing = true;
    _currentConfig = config ?? LanSyncConfig();
    // A retry must never inherit the previous request's confirmation token.
    _pendingRequests.remove(device.deviceId);
    _pendingTokens.remove(device.deviceId);
    _emitProgressValue(0);
    HttpClient? client;

    try {
      _emitProgress('正在请求连接 ${device.deviceName}...');

      client = HttpClient();

      final requestPayload = {
        'deviceId': _currentDeviceId,
        'userId': _currentUserId,
        'deviceName': _currentDeviceName,
        'port': _serverPort,
        'action': 'request',
      };

      final data = await _postEncryptedSync(
        client,
        device.ip,
        device.port,
        requestPayload,
      );

      String errorMsg = '连接被拒绝';
      if (data['pending'] == true) {
        final token = data['token']?.toString();
        if (token == null || token.isEmpty) {
          errorMsg = '连接失败: 对方返回的确认令牌无效';
        } else {
          // The receiver stores the incoming request under our device ID.
          // Mirror that pending state here so the receiver's later
          // `confirm` request can be accepted by this device's server.
          _pendingRequests[device.deviceId] = device.copyWith(
            pendingApproval: true,
          );
          _pendingTokens[device.deviceId] = token;
          _emitProgress('等待对方确认...');
          return LanSyncResult(success: false, message: '等待对方确认');
        }
      }
      if (data['error'] != null) {
        errorMsg = data['error'].toString();
      }

      return LanSyncResult(success: false, message: errorMsg);
    } catch (e) {
      return LanSyncResult(success: false, message: '连接失败: $e');
    } finally {
      client?.close(force: true);
      _isSyncing = false;
    }
  }

  LanSyncConfig _currentConfig = LanSyncConfig();
  String? _currentPendingToken;

  Future<LanSyncResult> confirmAndSync(
    LanDevice device, {
    LanSyncConfig? config,
  }) async {
    if (_isSyncing) return LanSyncResult(success: false, message: '同步进行中');
    if (_pendingTokens[device.deviceId] == null) {
      return LanSyncResult(success: false, message: '确认令牌已失效，请重新发起同步');
    }
    _isSyncing = true;
    _currentConfig = config ?? LanSyncConfig();
    _currentPendingToken = _pendingTokens[device.deviceId];
    _emitProgressValue(0);
    HttpClient? client;

    try {
      _emitProgress('正在连接 ${device.deviceName}...');
      _emitProgressValue(0.05);

      final username = _currentUserId!;
      final localData = await _gatherLocalData(username, _currentConfig);

      final payload = {
        'deviceId': _currentDeviceId,
        'userId': _currentUserId,
        'deviceName': _currentDeviceName,
        'port': _serverPort,
        'action': 'confirm',
        'token': _currentPendingToken,
        'config': _currentConfig.toJson(),
        'todos': _currentConfig.syncTodos ? localData['todos'] : [],
        'countdowns': _currentConfig.syncCountdowns
            ? localData['countdowns']
            : [],
        'timeLogs': _currentConfig.syncTimeLogs ? localData['timeLogs'] : [],
        'pomodoroTags': _currentConfig.syncPomodoroTags
            ? localData['pomodoroTags']
            : [],
        'pomodoroRecords': _currentConfig.syncPomodoroRecords
            ? localData['pomodoroRecords']
            : [],
        'courses': _currentConfig.syncCourses ? localData['courses'] : [],
        if (_currentConfig.syncSecrets && localData['secrets'] != null)
          'secrets': localData['secrets'],
        if (_currentConfig.syncSettings && localData['settings'] != null)
          'settings': localData['settings'],
      };

      _emitProgress('正在发送加密数据...');
      _emitProgressValue(0.1);

      client = HttpClient();

      final responseData = await _postEncryptedSync(
        client,
        device.ip,
        device.port,
        payload,
      );

      if (responseData['success'] != true) {
        return LanSyncResult(
          success: false,
          message: '同步失败: ${responseData['error']}',
        );
      }

      _emitProgress('正在合并远程数据...');
      _emitProgressValue(0.6);

      final remoteTodos =
          (responseData['todos'] as List?)
              ?.map((e) => Map<String, dynamic>.from(e))
              .toList() ??
          [];
      final remoteCountdowns =
          (responseData['countdowns'] as List?)
              ?.map((e) => Map<String, dynamic>.from(e))
              .toList() ??
          [];
      final remoteTimeLogs =
          (responseData['timeLogs'] as List?)
              ?.map((e) => Map<String, dynamic>.from(e))
              .toList() ??
          [];
      final remotePomodoroTags =
          (responseData['pomodoroTags'] as List?)
              ?.map((e) => Map<String, dynamic>.from(e))
              .toList() ??
          [];
      final remotePomodoroRecords =
          (responseData['pomodoroRecords'] as List?)
              ?.map((e) => Map<String, dynamic>.from(e))
              .toList() ??
          [];
      final remoteCourses =
          (responseData['courses'] as List?)
              ?.map((e) => Map<String, dynamic>.from(e))
              .toList() ??
          [];

      int todosSynced = 0,
          countdownsSynced = 0,
          timeLogsSynced = 0,
          pomodoroTagsSynced = 0,
          pomodoroRecordsSynced = 0,
          coursesSynced = 0;

      await _mergeTodos(username, remoteTodos, (count) => todosSynced = count);
      await _mergeCountdowns(
        username,
        remoteCountdowns,
        (count) => countdownsSynced = count,
      );
      await _mergeTimeLogs(
        username,
        remoteTimeLogs,
        (count) => timeLogsSynced = count,
      );
      await _mergePomodoroTags(
        remotePomodoroTags,
        (count) => pomodoroTagsSynced = count,
      );
      await _mergePomodoroRecords(
        remotePomodoroRecords,
        (count) => pomodoroRecordsSynced = count,
      );
      await _mergeCourses(
        username,
        remoteCourses,
        (count) => coursesSynced = count,
      );
      if (_currentConfig.syncSecrets && responseData['secrets'] is Map) {
        await LanSyncPrivateData.mergeSecrets(
          Map<String, dynamic>.from(responseData['secrets'] as Map),
        );
      }
      if (_currentConfig.syncSettings && responseData['settings'] is Map) {
        await LanSyncPrivateData.mergePortableSettings(
          Map<String, dynamic>.from(responseData['settings'] as Map),
        );
      }
      _emitProgressValue(1.0);
      _pendingRequests.remove(device.deviceId);
      _pendingTokens.remove(device.deviceId);

      return LanSyncResult(
        success: true,
        message: '同步成功（AES加密）',
        todosSynced: todosSynced,
        countdownsSynced: countdownsSynced,
        timeLogsSynced: timeLogsSynced,
        pomodoroTagsSynced: pomodoroTagsSynced,
        pomodoroRecordsSynced: pomodoroRecordsSynced,
        coursesSynced: coursesSynced,
        progress: 1.0,
      );
    } catch (e) {
      return LanSyncResult(success: false, message: '连接失败: $e');
    } finally {
      client?.close(force: true);
      _isSyncing = false;
    }
  }

  Future<void> _handleFileRequest(HttpRequest req) async {
    IOSink? sink;
    try {
      final version = req.headers.value('x-lan-encrypted');
      final sessionId = req.headers.value('x-lan-session');
      final sessionKey = _getSessionKey(sessionId);
      if (version != 'v2' || sessionKey == null) {
        req.response.statusCode = HttpStatus.unauthorized;
        req.response.headers.contentType = ContentType.json;
        req.response.write(jsonEncode({'error': 'v2 encrypted session required'}));
        await req.response.close();
        return;
      }

      String fileName = req.uri.queryParameters['name'] ?? 'unknown_file';
      // 移除可能导致路径遍历或非法的文件名字符
      fileName = fileName.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');

      final deviceName = req.uri.queryParameters['device'] ?? '未知设备';

      _emitProgress('正在接收来自 $deviceName 的加密文件: $fileName');
      _emitProgressValue(0.1);

      final tempDir = await getTemporaryDirectory();
      if (!await tempDir.exists()) {
        await tempDir.create(recursive: true);
      }
      final file = File(p.join(tempDir.path, fileName));
      sink = file.openWrite();

      int received = 0;
      final total = req.contentLength;
      final buffer = BytesBuilder(copy: false);
      var bufferBytes = Uint8List(0);
      int offset = 0;
      int chunkIndex = 0;
      const maxFrameSize =
          LanSyncCrypto.maxFileChunkSize + LanSyncCrypto.nonceLength + 16;

      await for (final chunk in req) {
        received += chunk.length;
        if (total > 0) {
          _emitProgressValue(0.1 + (received / total) * 0.9);
        }

        if (offset < bufferBytes.length) {
          buffer.add(Uint8List.sublistView(bufferBytes, offset));
        }
        buffer.add(chunk);
        bufferBytes = buffer.takeBytes();
        offset = 0;

        while (bufferBytes.length - offset >= 4) {
          final frameLen = ByteData.sublistView(
            bufferBytes,
            offset,
            offset + 4,
          ).getUint32(0, Endian.big);
          if (frameLen == 0 || frameLen > maxFrameSize) {
            throw const FormatException('Invalid encrypted file frame length');
          }
          if (bufferBytes.length - offset < 4 + frameLen) {
            break;
          }
          final sealedPayload = Uint8List.sublistView(
            bufferBytes,
            offset + 4,
            offset + 4 + frameLen,
          );
          final plainChunk = LanSyncCrypto.decodeFileFramePayload(
            sessionKey,
            chunkIndex++,
            sealedPayload,
          );
          sink.add(plainChunk);
          offset += 4 + frameLen;
        }
      }

      if (offset != bufferBytes.length) {
        throw const FormatException('Truncated encrypted file frame');
      }

      await sink.close();
      sink = null;

      _emitProgress('加密文件接收完成: $fileName');
      _emitProgressValue(1.0);

      _fileReceivedCtrl.add({
        'name': fileName,
        'path': file.path,
        'from': deviceName,
      });

      await _writeEncryptedJson(req, sessionKey, {'success': true});
    } catch (e) {
      await sink?.close();
      // debugPrint('[LanSync] File receive error: $e');
      req.response.statusCode = HttpStatus.internalServerError;
      req.response.headers.contentType = ContentType.json;
      req.response.write(jsonEncode({'error': e.toString()}));
      await req.response.close();
    }
  }

  Future<LanSyncResult> sendFilePath(LanDevice device, String path) {
    return sendFile(device, File(path));
  }

  Future<LanSyncResult> sendFile(LanDevice device, File file) async {
    if (_isSyncing) return LanSyncResult(success: false, message: '同步进行中');
    _isSyncing = true;
    _emitProgressValue(0);
    HttpClient? client;
    RandomAccessFile? raf;

    try {
      final fileName = p.basename(file.path);
      _emitProgress('正在建立加密通道并发送文件: $fileName');

      client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 10);

      final session = await _performHandshake(client, device.ip, device.port);

      final uri = Uri.parse('http://${device.ip}:${device.port}/file').replace(
        queryParameters: {
          'name': fileName,
          'device': _currentDeviceName ?? '未知设备',
        },
      );

      final request = await client.postUrl(uri);
      request.headers.set('X-Lan-Session', session.sessionId);
      request.headers.set('X-Lan-Encrypted', 'v2');

      final total = await file.length();
      raf = await file.open();
      int sent = 0;
      int chunkIndex = 0;

      while (true) {
        final plainChunk = await raf.read(LanSyncCrypto.maxFileChunkSize);
        if (plainChunk.isEmpty) break;
        final frame = LanSyncCrypto.encodeFileFrame(
          session.key,
          chunkIndex++,
          plainChunk,
        );
        request.add(frame);
        sent += plainChunk.length;
        if (total > 0) {
          _emitProgressValue((sent / total) * 0.95);
        }
      }
      await raf.close();
      raf = null;

      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();

      if (response.statusCode == HttpStatus.ok) {
        final respData = jsonDecode(body) as Map<String, dynamic>;
        if (respData['encrypted'] == true &&
            respData['v'] == LanSyncCrypto.protocolVersion) {
          final decrypted = jsonDecode(
            LanSyncCrypto.decryptString(
              session.key,
              respData['payload'].toString(),
            ),
          ) as Map<String, dynamic>;
          if (decrypted['success'] == true) {
            _emitProgressValue(1.0);
            _emitProgress('文件发送成功（AES-GCM 加密）');
            return LanSyncResult(success: true, message: '文件发送成功');
          }
        }
        return LanSyncResult(success: false, message: '文件传输加密校验失败');
      } else {
        return LanSyncResult(
          success: false,
          message: '服务器响应错误: ${response.statusCode}',
        );
      }
    } catch (e) {
      return LanSyncResult(success: false, message: '发送失败: $e');
    } finally {
      await raf?.close();
      client?.close(force: true);
      _isSyncing = false;
    }
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

  void dispose() {
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
