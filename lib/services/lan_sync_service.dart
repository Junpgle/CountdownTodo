import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart' as enc;
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models.dart';
import '../storage_service.dart';
import '../services/pomodoro_service.dart';
import '../services/course_service.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

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

  LanSyncConfig({
    this.syncTodos = true,
    this.syncCountdowns = true,
    this.syncTimeLogs = true,
    this.syncPomodoroTags = true,
    this.syncPomodoroRecords = true,
    this.syncCourses = true,
  });

  Map<String, dynamic> toJson() => {
        'todos': syncTodos,
        'countdowns': syncCountdowns,
        'timeLogs': syncTimeLogs,
        'pomodoroTags': syncPomodoroTags,
        'pomodoroRecords': syncPomodoroRecords,
        'courses': syncCourses,
      };

  int get totalCount =>
      (syncTodos ? 1 : 0) +
      (syncCountdowns ? 1 : 0) +
      (syncTimeLogs ? 1 : 0) +
      (syncPomodoroTags ? 1 : 0) +
      (syncPomodoroRecords ? 1 : 0) +
      (syncCourses ? 1 : 0);
}

enum LanSyncState { idle, requesting, sending, receiving, completed }

class LanSyncService {
  static const int _discoveryPort = 54321;
  static const int _defaultHttpPort = 54322;
  static const String _multicastGroup = '239.255.0.1';
  static const Duration _discoveryInterval = Duration(seconds: 5);
  static const int _deviceTimeoutMs = 15000;

  static final LanSyncService instance = LanSyncService._();
  factory LanSyncService() => instance;
  LanSyncService._();

  HttpServer? _server;
  RawDatagramSocket? _udpSocket;
  Timer? _discoveryTimer;
  Timer? _udpListenTimer;
  int? _serverPort;

  final _devicesCtrl = StreamController<List<LanDevice>>.broadcast();
  final _statusCtrl = StreamController<String>.broadcast();
  final _syncProgressCtrl = StreamController<String>.broadcast();
  final _incomingRequestCtrl = StreamController<LanDevice>.broadcast();
  final _syncProgressValueCtrl = StreamController<double>.broadcast();
  final _fileReceivedCtrl = StreamController<Map<String, String>>.broadcast();

  final Map<String, LanDevice> _pendingRequests = {};
  final Map<String, String> _pendingTokens = {};
  String? _currentRequestDeviceId;

  Stream<List<LanDevice>> get onDevicesChanged => _devicesCtrl.stream;
  Stream<String> get onStatusChanged => _statusCtrl.stream;
  Stream<String> get onSyncProgress => _syncProgressCtrl.stream;
  Stream<LanDevice> get onIncomingRequest => _incomingRequestCtrl.stream;
  Stream<double> get onProgressChanged => _syncProgressValueCtrl.stream;
  Stream<Map<String, String>> get onFileReceived => _fileReceivedCtrl.stream;

  final Map<String, LanDevice> _devices = {};
  bool _isRunning = false;
  bool _isSyncing = false;
  bool _discoverAllDevices = false;

  bool get isRunning => _isRunning;
  bool get isSyncing => _isSyncing;
  bool get discoverAllDevices => _discoverAllDevices;

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
  enc.Encrypter? _encrypter;
  enc.IV? _iv;

  String? get currentUserId => _currentUserId;
  String? get currentDeviceId => _currentDeviceId;
  String? get currentDeviceName => _currentDeviceName;
  String? get localIp => _localIp;

  void triggerDiscovery() {
    if (_isRunning) {
      _broadcastDiscovery();
      _startTimedScan();
      _emitStatus('正在重新扫描...');
    }
  }

  void _startTimedScan() {
    _scanAllInterfaces();
    Future.delayed(const Duration(seconds: 10), () {
      if (_isRunning) {
        _emitStatus('已启动（AES加密），发现 ${_devices.length} 台设备');
      }
    });
  }

  Future<void> _scanAllInterfaces() async {
    try {
      final interfaces = await NetworkInterface.list(
          type: InternetAddressType.IPv4, includeLoopback: false);

      for (var interface in interfaces) {
        for (var addr in interface.addresses) {
          if (addr.isLoopback) continue;
          if (addr.type != InternetAddressType.IPv4) continue;

          debugPrint('[LanSync] Scanning interface: ${addr.address}');
          await _scanSubnet(addr.address);
        }
      }
    } catch (e) {
      debugPrint('[LanSync] Interface scan failed: $e');
    }
  }

  Future<void> _scanSubnet(String localIp) async {
    try {
      final parts = localIp.split('.');
      if (parts.length != 4) return;

      final subnet = '${parts[0]}.${parts[1]}.${parts[2]}';
      final client = HttpClient();
      client.badCertificateCallback = (cert, host, port) => true;

      final futures = <Future>[];
      for (int i = 1; i < 255; i++) {
        final ip = '$subnet.$i';
        if (ip == localIp) continue;

        futures.add(_tryConnect(client, ip));
      }

      await Future.wait(futures).timeout(const Duration(seconds: 10));
      client.close();
      _emitDevices();
    } catch (e) {
      debugPrint('[LanSync] Subnet scan failed: $e');
    }
  }

  Future<void> _tryConnect(HttpClient client, String ip) async {
    try {
      final request = await client
          .getUrl(Uri.parse('http://$ip:54322/discover'))
          .timeout(const Duration(milliseconds: 300));
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      final data = jsonDecode(body) as Map<String, dynamic>;

      if (data['deviceId'] != _currentDeviceId &&
          (_discoverAllDevices || data['userId'] == _currentUserId)) {
        final device = LanDevice(
          deviceId: data['deviceId'],
          userId: data['userId'],
          deviceName: data['deviceName'],
          ip: ip,
          port: data['port'] ?? 54322,
          lastSeen: DateTime.now().millisecondsSinceEpoch,
        );
        _devices[device.deviceId] = device;
        debugPrint(
            '[LanSync] Found device via TCP: $ip (${data['deviceName']})');
      }
    } catch (_) {}
  }

  Future<String?> _getLocalIp() async {
    try {
      final interfaces =
          await NetworkInterface.list(type: InternetAddressType.IPv4);
      for (var interface in interfaces) {
        for (var addr in interface.addresses) {
          if (!addr.isLoopback && addr.type == InternetAddressType.IPv4) {
            return addr.address;
          }
        }
      }
    } catch (e) {
      debugPrint('[LanSync] Failed to get local IP: $e');
    }
    return null;
  }

  Future<void> start() async {
    if (_isRunning) return;
    _isRunning = true;

    final prefs = await SharedPreferences.getInstance();
    _currentUserId = prefs.getString(StorageService.KEY_CURRENT_USER) ?? '';
    _currentDeviceId = await StorageService.getDeviceId();
    _currentDeviceName = await StorageService.getDeviceFriendlyName();
    _localIp = await _getLocalIp();

    if (_currentUserId!.isEmpty) {
      _emitStatus('未登录，无法使用局域网同步');
      _isRunning = false;
      return;
    }

    _initEncryption();

    try {
      await _startHttpServer();
      await _startUdpDiscovery();
      _startDiscoveryBroadcast();
      _startTimedScan();
      _emitStatus('正在扫描设备...');
    } catch (e) {
      _emitStatus('启动失败: $e');
      _isRunning = false;
    }
  }

  void _initEncryption() {
    final keyBytes =
        sha256.convert(utf8.encode('lan_sync_${_currentUserId}')).bytes;
    final ivBytes = sha256
        .convert(utf8.encode('lan_sync_iv_${_currentUserId}'))
        .bytes
        .sublist(0, 16);
    _encrypter = enc.Encrypter(enc.AES(enc.Key(Uint8List.fromList(keyBytes))));
    _iv = enc.IV(Uint8List.fromList(ivBytes));
  }

  String _encrypt(String plainText) {
    return _encrypter!.encrypt(plainText, iv: _iv!).base64;
  }

  String _decrypt(String encryptedText) {
    return _encrypter!.decrypt64(encryptedText, iv: _iv!);
  }

  Future<void> stop() async {
    _isRunning = false;
    _discoveryTimer?.cancel();
    _udpListenTimer?.cancel();
    _udpSocket?.close();
    await _server?.close(force: true);
    _devices.clear();
    _emitDevices();
    _emitStatus('已停止');
  }

  Future<void> _startHttpServer() async {
    int port = _defaultHttpPort;
    for (int attempt = 0; attempt < 10; attempt++) {
      try {
        _server = await HttpServer.bind(InternetAddress.anyIPv4, port);
        _serverPort = port;
        debugPrint('[LanSync] HTTP server started on port $port');
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
      if (path == '/sync' && req.method == 'POST') {
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
      debugPrint('[LanSync] Handle request error: $e');
      try {
        req.response.statusCode = HttpStatus.internalServerError;
        req.response.write(jsonEncode({'error': e.toString()}));
        await req.response.close();
      } catch (_) {}
    }
  }

  Future<void> _handleDiscoverRequest(HttpRequest req) async {
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

    if (encryptedData['encrypted'] != true) {
      req.response.statusCode = HttpStatus.badRequest;
      req.response.write(jsonEncode({'error': 'encryption required'}));
      await req.response.close();
      return;
    }

    final decryptedBody = _decrypt(encryptedData['payload']);
    final data = jsonDecode(decryptedBody) as Map<String, dynamic>;

    final remoteDeviceId = data['deviceId'] ?? '';
    final remoteUserId = data['userId'] ?? '';
    final remoteDeviceName = data['deviceName'] ?? '';
    final action = data['action'] ?? 'request';

    if (remoteUserId != _currentUserId && !_discoverAllDevices) {
      req.response.statusCode = HttpStatus.forbidden;
      final errResp = _encrypt(jsonEncode({'error': 'account mismatch'}));
      req.response.write(jsonEncode({'encrypted': true, 'payload': errResp}));
      await req.response.close();
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
      _currentRequestDeviceId = remoteDeviceId;

      _incomingRequestCtrl.add(device);

      final response = jsonEncode({'pending': true, 'token': token});
      req.response.headers.contentType = ContentType.json;
      req.response.write(jsonEncode({
        'encrypted': true,
        'payload': _encrypt(response),
      }));
      await req.response.close();
      return;
    }

    if (action == 'confirm') {
      final requestToken = data['token'];
      final pendingDevice = _pendingRequests[remoteDeviceId];

      if (pendingDevice == null) {
        req.response.headers.contentType = ContentType.json;
        req.response.write(jsonEncode({'error': 'no pending request'}));
        await req.response.close();
        return;
      }

      _pendingRequests.remove(remoteDeviceId);
      _currentRequestDeviceId = null;

      _emitProgress('正在接收数据...');
      _emitProgressValue(0.1);

      final remoteTodos = (data['todos'] as List?)
              ?.map((e) => Map<String, dynamic>.from(e))
              .toList() ??
          [];
      final remoteCountdowns = (data['countdowns'] as List?)
              ?.map((e) => Map<String, dynamic>.from(e))
              .toList() ??
          [];
      final remoteTimeLogs = (data['timeLogs'] as List?)
              ?.map((e) => Map<String, dynamic>.from(e))
              .toList() ??
          [];
      final remotePomodoroTags = (data['pomodoroTags'] as List?)
              ?.map((e) => Map<String, dynamic>.from(e))
              .toList() ??
          [];
      final remotePomodoroRecords = (data['pomodoroRecords'] as List?)
              ?.map((e) => Map<String, dynamic>.from(e))
              .toList() ??
          [];
      final remoteCourses = (data['courses'] as List?)
              ?.map((e) => Map<String, dynamic>.from(e))
              .toList() ??
          [];

      final configData = data['config'] as Map<String, dynamic>?;
      final syncConfig = configData != null
          ? LanSyncConfig(
              syncTodos: configData['todos'] ?? true,
              syncCountdowns: configData['countdowns'] ?? true,
              syncTimeLogs: configData['timeLogs'] ?? true,
              syncPomodoroTags: configData['pomodoroTags'] ?? true,
              syncPomodoroRecords: configData['pomodoroRecords'] ?? true,
              syncCourses: configData['courses'] ?? true,
            )
          : LanSyncConfig();

      int todosSynced = 0,
          countdownsSynced = 0,
          timeLogsSynced = 0,
          pomodoroTagsSynced = 0,
          pomodoroRecordsSynced = 0,
          coursesSynced = 0;

      final username = _currentUserId!;
      final step =
          syncConfig.totalCount > 0 ? 0.4 / syncConfig.totalCount : 0.1;
      double progress = 0.5;

      if (syncConfig.syncTodos) {
        await _mergeTodos(
            username, remoteTodos, (count) => todosSynced = count);
        progress += step;
        _emitProgressValue(progress);
        _emitProgress('合并待办完成...');
      }

      if (syncConfig.syncCountdowns) {
        await _mergeCountdowns(
            username, remoteCountdowns, (count) => countdownsSynced = count);
        progress += step;
        _emitProgressValue(progress);
        _emitProgress('合并倒数日完成...');
      }

      if (syncConfig.syncTimeLogs) {
        await _mergeTimeLogs(
            username, remoteTimeLogs, (count) => timeLogsSynced = count);
        progress += step;
        _emitProgressValue(progress);
        _emitProgress('合并时间日志完成...');
      }

      if (syncConfig.syncPomodoroTags) {
        await _mergePomodoroTags(
            remotePomodoroTags, (count) => pomodoroTagsSynced = count);
        progress += step;
        _emitProgressValue(progress);
        _emitProgress('合并番茄标签完成...');
      }

      if (syncConfig.syncPomodoroRecords) {
        await _mergePomodoroRecords(
            remotePomodoroRecords, (count) => pomodoroRecordsSynced = count);
        progress += step;
        _emitProgressValue(progress);
        _emitProgress('合并番茄记录完成...');
      }

      if (syncConfig.syncCourses) {
        await _mergeCourses(username, remoteCourses, (count) => coursesSynced = count);
        progress += step;
        _emitProgressValue(progress);
        _emitProgress('合并课程完成...');
      }

      final localData = await _gatherLocalData(username, syncConfig);

      final responsePayload = jsonEncode({
        'success': true,
        'todos': syncConfig.syncTodos ? localData['todos'] : [],
        'countdowns': syncConfig.syncCountdowns ? localData['countdowns'] : [],
        'timeLogs': syncConfig.syncTimeLogs ? localData['timeLogs'] : [],
        'pomodoroTags':
            syncConfig.syncPomodoroTags ? localData['pomodoroTags'] : [],
        'pomodoroRecords':
            syncConfig.syncPomodoroRecords ? localData['pomodoroRecords'] : [],
        'courses': syncConfig.syncCourses ? localData['courses'] : [],
      });

      req.response.headers.contentType = ContentType.json;
      req.response.write(jsonEncode({
        'encrypted': true,
        'payload': _encrypt(responsePayload),
      }));
      await req.response.close();

      _emitProgressValue(1.0);
      _emitProgress('同步完成');

      debugPrint(
          '[LanSync] Sync from $remoteDeviceId: todos=$todosSynced, countdowns=$countdownsSynced, timeLogs=$timeLogsSynced, pomTags=$pomodoroTagsSynced, pomRecords=$pomodoroRecordsSynced, courses=$coursesSynced');
    }
  }

  Future<void> _mergeTodos(String username, List<Map<String, dynamic>> remote,
      Function(int) onChanged) async {
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
      await StorageService.saveTodos(username, merged.values.toList(),
          sync: false);
      onChanged(merged.length);
    }
  }

  Future<void> _mergeCountdowns(String username,
      List<Map<String, dynamic>> remote, Function(int) onChanged) async {
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
      await StorageService.saveCountdowns(username, merged.values.toList(),
          sync: false);
      onChanged(merged.length);
    }
  }

  Future<void> _mergeTimeLogs(String username,
      List<Map<String, dynamic>> remote, Function(int) onChanged) async {
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
      await StorageService.saveTimeLogs(username, merged.values.toList(),
          sync: false);
      onChanged(merged.length);
    }
  }

  Future<void> _mergePomodoroTags(
      List<Map<String, dynamic>> remote, Function(int) onChanged) async {
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
      List<Map<String, dynamic>> remote, Function(int) onChanged) async {
    if (remote.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final s = prefs.getString('pomodoro_records');
    final List<PomodoroRecord> localAll = s == null
        ? []
        : (jsonDecode(s) as List)
            .map((e) => PomodoroRecord.fromJson(e))
            .toList();
    final Map<String, PomodoroRecord> merged = {
      for (var r in localAll) r.uuid: r
    };
    bool changed = false;
    for (var r in remote) {
      final remoteRecord = PomodoroRecord.fromJson(r);
      final existing = merged[remoteRecord.uuid];
      if (existing == null) {
        if (!remoteRecord.isDeleted) {
          merged[remoteRecord.uuid] = remoteRecord;
          changed = true;
        }
      } else {
        if (remoteRecord.updatedAt > existing.updatedAt) {
          merged[remoteRecord.uuid] = remoteRecord;
          changed = true;
        }
      }
    }
    if (changed) {
      await prefs.setString('pomodoro_records',
          jsonEncode(merged.values.map((r) => r.toJson()).toList()));
      onChanged(merged.length);
    }
  }

  Future<void> _mergeCourses(String username,
      List<Map<String, dynamic>> remote, Function(int) onChanged) async {
    if (remote.isEmpty) return;
    final local = await CourseService.getAllCourses(username);
    final Map<String, CourseItem> merged = {};
    for (var c in local) {
      final key = '${c.courseName}_${c.date}_${c.startTime}';
      merged[key] = c;
    }
    bool changed = false;
    for (var r in remote) {
      final remoteCourse = CourseItem.fromJson(r);
      final key =
          '${remoteCourse.courseName}_${remoteCourse.date}_${remoteCourse.startTime}';
      if (!merged.containsKey(key)) {
        merged[key] = remoteCourse;
        changed = true;
      }
    }
    if (changed) {
      await CourseService.saveCourses(username, merged.values.toList());
      onChanged(merged.length);
    }
  }

  bool _lwwWins(TodoItem remote, TodoItem local) {
    if (remote.version > local.version) return true;
    if (remote.version == local.version && remote.updatedAt > local.updatedAt)
      return true;
    return false;
  }

  bool _lwwWinsCountdown(CountdownItem remote, CountdownItem local) {
    if (remote.version > local.version) return true;
    if (remote.version == local.version && remote.updatedAt > local.updatedAt)
      return true;
    return false;
  }

  bool _lwwWinsTimeLog(TimeLogItem remote, TimeLogItem local) {
    if (remote.version > local.version) return true;
    if (remote.version == local.version && remote.updatedAt > local.updatedAt)
      return true;
    return false;
  }

  Future<Map<String, dynamic>> _gatherLocalData(String username,
      [LanSyncConfig? config]) async {
    config ??= LanSyncConfig();
    final todos =
        config.syncTodos ? await StorageService.getTodos(username) : [];
    final countdowns = config.syncCountdowns
        ? await StorageService.getCountdowns(username)
        : [];
    final timeLogs =
        config.syncTimeLogs ? await StorageService.getTimeLogs(username) : [];
    final pomodoroTags =
        config.syncPomodoroTags ? await PomodoroService.getTags() : [];
    final pomodoroRecords =
        config.syncPomodoroRecords ? await PomodoroService.getRecords() : [];
    final courses =
        config.syncCourses ? await CourseService.getAllCourses(username) : [];

    return {
      'todos': todos.map((t) => t.toJson()).toList(),
      'countdowns': countdowns.map((c) => c.toJson()).toList(),
      'timeLogs': timeLogs.map((t) => t.toJson()).toList(),
      'pomodoroTags': pomodoroTags.map((t) => t.toJson()).toList(),
      'pomodoroRecords': pomodoroRecords.map((r) => r.toJson()).toList(),
      'courses': courses.map((c) => c.toJson()).toList(),
    };
  }

  Future<void> _startUdpDiscovery() async {
    try {
      _udpSocket =
          await RawDatagramSocket.bind(InternetAddress.anyIPv4, _discoveryPort);
      _udpSocket!.joinMulticast(InternetAddress(_multicastGroup));

      _udpListenTimer = Timer.periodic(const Duration(milliseconds: 200), (_) {
        Datagram? d;
        while ((d = _udpSocket!.receive()) != null) {
          _processDiscoveryDatagram(d);
        }
      });
    } catch (e) {
      debugPrint('[LanSync] UDP discovery failed: $e');
    }
  }

  void _processDiscoveryDatagram(Datagram? datagram) {
    if (datagram == null) return;
    try {
      final data =
          jsonDecode(utf8.decode(datagram.data)) as Map<String, dynamic>;
      if (data['type'] == 'discovery' &&
          data['deviceId'] != _currentDeviceId &&
          (_discoverAllDevices || data['userId'] == _currentUserId)) {
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

  void _startDiscoveryBroadcast() {
    _discoveryTimer?.cancel();
    _broadcastDiscovery();
    _discoveryTimer =
        Timer.periodic(_discoveryInterval, (_) => _broadcastDiscovery());
  }

  void _broadcastDiscovery() {
    if (_udpSocket == null || !_isRunning) return;
    try {
      final message = jsonEncode({
        'type': 'discovery',
        'deviceId': _currentDeviceId,
        'userId': _currentUserId,
        'deviceName': _currentDeviceName,
        'port': _serverPort,
      });
      _udpSocket!.send(
        utf8.encode(message),
        InternetAddress(_multicastGroup),
        _discoveryPort,
      );
    } catch (e) {
      debugPrint('[LanSync] Broadcast error: $e');
    }
  }

  Future<LanSyncResult> syncWithDevice(LanDevice device,
      {LanSyncConfig? config}) async {
    if (_isSyncing) return LanSyncResult(success: false, message: '同步进行中');
    _isSyncing = true;
    _currentConfig = config ?? LanSyncConfig();
    _emitProgressValue(0);

    try {
      _emitProgress('正在请求连接 ${device.deviceName}...');

      final client = HttpClient();
      client.badCertificateCallback = (cert, host, port) => true;

      final requestPayload = {
        'deviceId': _currentDeviceId,
        'userId': _currentUserId,
        'deviceName': _currentDeviceName,
        'port': _serverPort,
        'action': 'request',
      };

      final encryptedPayload = _encrypt(jsonEncode(requestPayload));

      final request = await client
          .postUrl(Uri.parse('http://${device.ip}:${device.port}/sync'));
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode({
        'encrypted': true,
        'payload': encryptedPayload,
      }));
      final response = await request.close();

      final body = await response.transform(utf8.decoder).join();
      final responseData = jsonDecode(body) as Map<String, dynamic>;

      if (responseData['pending'] == true) {
        _emitProgress('等待对方确认...');
        return LanSyncResult(success: false, message: '等待对方确认');
      }

      client.close();
      _isSyncing = false;
      return LanSyncResult(success: false, message: '连接被拒绝');
    } catch (e) {
      _isSyncing = false;
      return LanSyncResult(success: false, message: '连接失败: $e');
    }
  }

  LanSyncConfig _currentConfig = LanSyncConfig();
  String? _currentPendingToken;

  Future<LanSyncResult> confirmAndSync(LanDevice device,
      {LanSyncConfig? config}) async {
    if (_isSyncing) return LanSyncResult(success: false, message: '同步进行中');
    _isSyncing = true;
    _currentConfig = config ?? LanSyncConfig();
    _currentPendingToken = _pendingTokens[device.deviceId];
    _emitProgressValue(0);

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
        'countdowns':
            _currentConfig.syncCountdowns ? localData['countdowns'] : [],
        'timeLogs': _currentConfig.syncTimeLogs ? localData['timeLogs'] : [],
        'pomodoroTags':
            _currentConfig.syncPomodoroTags ? localData['pomodoroTags'] : [],
        'pomodoroRecords': _currentConfig.syncPomodoroRecords
            ? localData['pomodoroRecords']
            : [],
        'courses': _currentConfig.syncCourses ? localData['courses'] : [],
      };

      _emitProgress('正在发送加密数据...');
      _emitProgressValue(0.1);

      final client = HttpClient();
      client.badCertificateCallback = (cert, host, port) => true;

      final encryptedPayload = _encrypt(jsonEncode(payload));

      final request = await client
          .postUrl(Uri.parse('http://${device.ip}:${device.port}/sync'));
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode({
        'encrypted': true,
        'payload': encryptedPayload,
      }));
      final response = await request.close();

      final encryptedBody = await response.transform(utf8.decoder).join();
      debugPrint('[LanSync] Response body: $encryptedBody');
      final encryptedResponseData =
          jsonDecode(encryptedBody) as Map<String, dynamic>;

      if (encryptedResponseData['encrypted'] != true) {
        _isSyncing = false;
        return LanSyncResult(
            success: false,
            message:
                '同步失败: 响应未加密 (${encryptedResponseData['error'] ?? 'unknown'})');
      }

      final decryptedBody = _decrypt(encryptedResponseData['payload']);
      final responseData = jsonDecode(decryptedBody) as Map<String, dynamic>;

      if (responseData['success'] != true) {
        _isSyncing = false;
        return LanSyncResult(
            success: false, message: '同步失败: ${responseData['error']}');
      }

      _emitProgress('正在合并远程数据...');
      _emitProgressValue(0.6);

      final remoteTodos = (responseData['todos'] as List?)
              ?.map((e) => Map<String, dynamic>.from(e))
              .toList() ??
          [];
      final remoteCountdowns = (responseData['countdowns'] as List?)
              ?.map((e) => Map<String, dynamic>.from(e))
              .toList() ??
          [];
      final remoteTimeLogs = (responseData['timeLogs'] as List?)
              ?.map((e) => Map<String, dynamic>.from(e))
              .toList() ??
          [];
      final remotePomodoroTags = (responseData['pomodoroTags'] as List?)
              ?.map((e) => Map<String, dynamic>.from(e))
              .toList() ??
          [];
      final remotePomodoroRecords = (responseData['pomodoroRecords'] as List?)
              ?.map((e) => Map<String, dynamic>.from(e))
              .toList() ??
          [];
      final remoteCourses = (responseData['courses'] as List?)
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
          username, remoteCountdowns, (count) => countdownsSynced = count);
      await _mergeTimeLogs(
          username, remoteTimeLogs, (count) => timeLogsSynced = count);
      await _mergePomodoroTags(
          remotePomodoroTags, (count) => pomodoroTagsSynced = count);
      await _mergePomodoroRecords(
          remotePomodoroRecords, (count) => pomodoroRecordsSynced = count);
      await _mergeCourses(username, remoteCourses, (count) => coursesSynced = count);
      _emitProgressValue(1.0);

      client.close();

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
      _isSyncing = false;
      return LanSyncResult(success: false, message: '连接失败: $e');
    } finally {
      _isSyncing = false;
    }
  }

  Future<void> _handleFileRequest(HttpRequest req) async {
    try {
      String fileName = req.uri.queryParameters['name'] ?? 'unknown_file';
      // 移除可能导致路径遍历或非法的文件名字符
      fileName = fileName.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
      
      final deviceName = req.uri.queryParameters['device'] ?? '未知设备';

      _emitProgress('正在接收来自 $deviceName 的文件: $fileName');
      _emitProgressValue(0.1);

      final tempDir = await getTemporaryDirectory();
      if (!await tempDir.exists()) {
        await tempDir.create(recursive: true);
      }
      final file = File(p.join(tempDir.path, fileName));
      final sink = file.openWrite();

      int received = 0;
      final total = req.contentLength;

      await for (var chunk in req) {
        sink.add(chunk);
        received += chunk.length;
        if (total > 0) {
          _emitProgressValue(0.1 + (received / total) * 0.9);
        }
      }
      await sink.close();

      _emitProgress('文件接收完成: $fileName');
      _emitProgressValue(1.0);

      _fileReceivedCtrl.add({
        'name': fileName,
        'path': file.path,
        'from': deviceName,
      });

      req.response.statusCode = HttpStatus.ok;
      req.response.write(jsonEncode({'success': true}));
      await req.response.close();
    } catch (e) {
      debugPrint('[LanSync] File receive error: $e');
      req.response.statusCode = HttpStatus.internalServerError;
      await req.response.close();
    }
  }

  Future<LanSyncResult> sendFile(LanDevice device, File file) async {
    if (_isSyncing) return LanSyncResult(success: false, message: '同步进行中');
    _isSyncing = true;
    _emitProgressValue(0);

    try {
      final fileName = p.basename(file.path);
      _emitProgress('正在发送文件到 ${device.deviceName}: $fileName');

      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 10);

      final uri = Uri.parse('http://${device.ip}:${device.port}/file').replace(
        queryParameters: {
          'name': fileName,
          'device': _currentDeviceName ?? '未知设备',
        },
      );

      final request = await client.postUrl(uri);
      final fileStream = file.openRead();
      final total = await file.length();
      int sent = 0;

      await request.addStream(fileStream.map((chunk) {
        sent += chunk.length;
        _emitProgressValue((sent / total) * 0.95);
        return chunk;
      }));

      final response = await request.close();
      _isSyncing = false;

      if (response.statusCode == HttpStatus.ok) {
        _emitProgressValue(1.0);
        _emitProgress('文件发送成功');
        return LanSyncResult(success: true, message: '文件发送成功');
      } else {
        return LanSyncResult(success: false, message: '服务器响应错误: ${response.statusCode}');
      }
    } catch (e) {
      _isSyncing = false;
      return LanSyncResult(success: false, message: '发送失败: $e');
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
  }
}
