import 'package:uuid/uuid.dart';

import '../../../utils/json_value_parser.dart';

/// 账号级睡眠训练计划。
///
/// 计划保存用户选择、训练起点，以及暂停时的阶段检查点；正常阶段由
/// 本地/云端一致的睡眠打卡记录推导，避免不同设备分别维护进度造成分叉。
class HabitSleepCoachingPlan {
  static const String planKind = 'sleep_routine';

  String uuid;
  String kind;
  bool enabled;
  bool paused;
  int stepMinutes;
  int stageDays;
  String? startedLogicalDate;
  int? baselineBedtimeMinute;
  int? baselineWakeMinute;
  int? baselineSleepMinutes;

  /// 暂停时冻结的阶段检查点。恢复后从 pausedLogicalDate 的下一天继续推导。
  int? pausedStageIndex;
  int? pausedProgressDays;
  String? pausedLogicalDate;

  /// 训练开始时采用的逻辑日期时区偏移（分钟）。
  ///
  /// 计划在不同设备上展示时，统一以这个偏移计算“今天”，避免用户
  /// 切换设备或旅行后阶段进度相差一天。旧计划会在首次读取时迁移填充。
  int? timezoneOffsetMinutes;
  bool isDeleted;
  int version;
  String? deviceId;
  int createdAt;
  int updatedAt;

  HabitSleepCoachingPlan({
    String? uuid,
    this.kind = planKind,
    this.enabled = false,
    this.paused = false,
    this.stepMinutes = 15,
    this.stageDays = 4,
    this.startedLogicalDate,
    this.baselineBedtimeMinute,
    this.baselineWakeMinute,
    this.baselineSleepMinutes,
    this.pausedStageIndex,
    this.pausedProgressDays,
    this.pausedLogicalDate,
    this.timezoneOffsetMinutes,
    this.isDeleted = false,
    this.version = 1,
    this.deviceId,
    int? createdAt,
    int? updatedAt,
  })  : uuid = uuid ?? const Uuid().v4(),
        createdAt = createdAt ?? DateTime.now().millisecondsSinceEpoch,
        updatedAt = updatedAt ?? DateTime.now().millisecondsSinceEpoch;

  /// 账号名是当前客户端跨设备可获得的稳定标识；服务端仍以 user_id 隔离数据。
  static String stableUuidFor(String username) {
    final normalized = username.trim().toLowerCase();
    return const Uuid().v5(
      Namespace.url.value,
      'countdown-todo/sleep-coaching/$normalized',
    );
  }

  void markAsChanged() {
    version++;
    final now = DateTime.now().millisecondsSinceEpoch;
    updatedAt = now > updatedAt ? now : updatedAt + 1;
  }

  Map<String, dynamic> toJson() => {
        'uuid': uuid,
        'kind': kind,
        'enabled': enabled ? 1 : 0,
        'paused': paused ? 1 : 0,
        'step_minutes': stepMinutes,
        'stage_days': stageDays,
        'started_logical_date': startedLogicalDate,
        'baseline_bedtime_minute': baselineBedtimeMinute,
        'baseline_wake_minute': baselineWakeMinute,
        'baseline_sleep_minutes': baselineSleepMinutes,
        'paused_stage_index': pausedStageIndex,
        'paused_progress_days': pausedProgressDays,
        'paused_logical_date': pausedLogicalDate,
        'timezone_offset_minutes': timezoneOffsetMinutes,
        'is_deleted': isDeleted ? 1 : 0,
        'version': version,
        'device_id': deviceId,
        'created_at': createdAt,
        'updated_at': updatedAt,
      };

  factory HabitSleepCoachingPlan.fromJson(Map<String, dynamic> json) {
    return HabitSleepCoachingPlan(
      uuid: json['uuid']?.toString() ?? const Uuid().v4(),
      kind: json['kind']?.toString() ?? planKind,
      enabled: _isTrue(json['enabled']),
      paused: _isTrue(json['paused']),
      stepMinutes:
          _clampInt(json['step_minutes'] ?? json['stepMinutes'], 15, 5, 60),
      stageDays: _clampInt(json['stage_days'] ?? json['stageDays'], 4, 1, 14),
      startedLogicalDate: json['started_logical_date']?.toString() ??
          json['startedLogicalDate']?.toString(),
      baselineBedtimeMinute: _intOrNull(
        json['baseline_bedtime_minute'] ?? json['baselineBedtimeMinute'],
      ),
      baselineWakeMinute: _intOrNull(
        json['baseline_wake_minute'] ?? json['baselineWakeMinute'],
      ),
      baselineSleepMinutes: _intOrNull(
        json['baseline_sleep_minutes'] ?? json['baselineSleepMinutes'],
      ),
      pausedStageIndex: _intOrNull(
        json['paused_stage_index'] ?? json['pausedStageIndex'],
      ),
      pausedProgressDays: _intOrNull(
        json['paused_progress_days'] ?? json['pausedProgressDays'],
      ),
      pausedLogicalDate: json['paused_logical_date']?.toString() ??
          json['pausedLogicalDate']?.toString(),
      timezoneOffsetMinutes: _clampNullableInt(
        json['timezone_offset_minutes'] ?? json['timezoneOffsetMinutes'],
        -14 * 60,
        14 * 60,
      ),
      isDeleted: _isTrue(json['is_deleted']),
      version: _intOrDefault(json['version'], 1),
      deviceId: json['device_id']?.toString(),
      createdAt: JsonValueParser.epochMillisOrNow(json['created_at']),
      updatedAt: JsonValueParser.epochMillisOrNow(json['updated_at']),
    );
  }

  static bool _isTrue(dynamic value) =>
      value == true || value == 1 || value == '1';

  static int _intOrDefault(dynamic value, int fallback) =>
      int.tryParse(value?.toString() ?? '') ?? fallback;

  static int? _intOrNull(dynamic value) =>
      value == null ? null : int.tryParse(value.toString());

  static int? _clampNullableInt(dynamic value, int min, int max) {
    final parsed = _intOrNull(value);
    return parsed?.clamp(min, max).toInt();
  }

  static int _clampInt(dynamic value, int fallback, int min, int max) =>
      (_intOrDefault(value, fallback)).clamp(min, max).toInt();
}
