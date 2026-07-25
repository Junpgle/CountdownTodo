class SyncCapabilityService {
  SyncCapabilityService._();

  static const String fixedSchedules = 'fixed_schedules';
  static const int fixedSchedulesVersion = 1;

  static bool supportsFixedSchedules(dynamic rawCapabilities) =>
      capabilityVersion(rawCapabilities, fixedSchedules) >=
      fixedSchedulesVersion;

  /// 只有本轮实际同步固定日程，并且服务端明确声明协议版本时，
  /// 才能确认对应 oplog。未知能力必须按旧服务端处理并保留本地操作。
  static bool shouldAcknowledgeFixedScheduleOps({
    required bool syncEnabled,
    required dynamic rawCapabilities,
  }) =>
      syncEnabled && supportsFixedSchedules(rawCapabilities);

  static int capabilityVersion(dynamic rawCapabilities, String name) {
    if (rawCapabilities is Map) {
      final raw = rawCapabilities[name];
      if (raw == true) return 1;
      if (raw is num) return raw.toInt();
      return int.tryParse(raw?.toString() ?? '') ?? 0;
    }
    if (rawCapabilities is List) {
      return rawCapabilities.map((item) => item.toString()).contains(name)
          ? 1
          : 0;
    }
    return 0;
  }
}
