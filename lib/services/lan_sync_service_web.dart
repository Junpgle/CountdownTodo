import 'dart:async';

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
  static final LanSyncService instance = LanSyncService._();
  factory LanSyncService() => instance;
  LanSyncService._();

  final _statusCtrl = StreamController<String>.broadcast();

  Stream<List<LanDevice>> get onDevicesChanged => const Stream.empty();
  Stream<String> get onStatusChanged => _statusCtrl.stream;
  Stream<String> get onSyncProgress => const Stream.empty();
  Stream<LanDevice> get onIncomingRequest => const Stream.empty();
  Stream<double> get onProgressChanged => const Stream.empty();
  Stream<Map<String, String>> get onFileReceived => const Stream.empty();

  bool get isRunning => false;
  bool get isSyncing => false;
  bool _discoverAllDevices = false;
  bool get discoverAllDevices => _discoverAllDevices;
  set discoverAllDevices(bool value) => _discoverAllDevices = value;

  List<LanDevice> get devices => const [];
  String? get currentUserId => null;
  String? get currentDeviceId => null;
  String? get currentDeviceName => null;
  String? get localIp => null;

  void triggerDiscovery() {
    _statusCtrl.add('浏览器不支持局域网发现');
  }

  Future<void> start() async {
    _statusCtrl.add('浏览器不支持局域网同步');
  }

  Future<void> stop() async {}

  Future<LanSyncResult> syncWithDevice(
    LanDevice device, {
    LanSyncConfig? config,
  }) async =>
      LanSyncResult(message: '浏览器不支持局域网同步');

  Future<LanSyncResult> confirmAndSync(
    LanDevice device, {
    LanSyncConfig? config,
  }) async =>
      LanSyncResult(message: '浏览器不支持局域网同步');

  Future<LanSyncResult> sendFilePath(LanDevice device, String path) async =>
      LanSyncResult(message: '浏览器不支持局域网文件发送');

  void dispose() {
    _statusCtrl.close();
  }
}
