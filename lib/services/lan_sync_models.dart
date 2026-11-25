/// 局域网同步设备信息。
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

/// 局域网同步执行结果。
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

/// 局域网同步数据类型配置。
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
