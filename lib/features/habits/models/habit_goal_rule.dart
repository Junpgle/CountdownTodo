import 'dart:convert';

import 'package:uuid/uuid.dart';

/// 目标周期类型。
enum HabitPeriodType {
  /// 每天。
  daily,

  /// 每周累计。
  weekly,

  /// 指定星期（配合 [HabitGoalRuleRevision.weekdaysMask]）。
  weekdays,

  /// 每月累计。
  monthly,

  /// 自定义间隔天数（配合 [HabitGoalRuleRevision.customIntervalDays]）。
  custom,
}

/// 时间点型习惯的目标比较方式。
enum HabitTimeComparison {
  /// 实际时间早于或等于目标时间（如早起、早睡）。
  before,

  /// 实际时间晚于或等于目标时间（如 18:00 后不喝咖啡）。
  after,
}

/// 提醒策略（第一版仅保存配置，调度由提醒服务负责）。
class HabitReminderPolicy {
  /// 固定提醒时刻（一天内的分钟数，0..1439）。
  final List<int> fixedTimes;

  /// 进度提醒。
  final bool progressReminder;

  /// 临近结束提醒。
  final bool nearEndReminder;

  /// 当日汇总提醒。
  final bool dailySummaryReminder;

  const HabitReminderPolicy({
    this.fixedTimes = const [],
    this.progressReminder = false,
    this.nearEndReminder = false,
    this.dailySummaryReminder = false,
  });

  Map<String, dynamic> toJson() => {
        'fixed_times': fixedTimes,
        'progress_reminder': progressReminder ? 1 : 0,
        'near_end_reminder': nearEndReminder ? 1 : 0,
        'daily_summary_reminder': dailySummaryReminder ? 1 : 0,
      };

  factory HabitReminderPolicy.fromJson(Map<String, dynamic> json) {
    List<int> times = [];
    final rawTimes = json['fixed_times'];
    if (rawTimes is List) {
      times = rawTimes
          .map((e) => int.tryParse(e.toString()) ?? 0)
          .where((e) => e >= 0 && e < 1440)
          .toList();
    }
    return HabitReminderPolicy(
      fixedTimes: times,
      progressReminder:
          json['progress_reminder'] == 1 || json['progress_reminder'] == true,
      nearEndReminder:
          json['near_end_reminder'] == 1 || json['near_end_reminder'] == true,
      dailySummaryReminder: json['daily_summary_reminder'] == 1 ||
          json['daily_summary_reminder'] == true,
    );
  }
}

/// 目标规则版本：表示某个时间段内有效的目标规则。
///
/// 历史数据始终按照当时生效的目标判断，修改目标时新增版本而不是覆盖。
class HabitGoalRuleRevision {
  String uuid;
  String habitUuid;

  /// 生效起始逻辑日期（'yyyy-MM-dd'，含当天）。
  String? effectiveFromDate;

  /// 生效结束逻辑日期（'yyyy-MM-dd'，含当天；null 表示仍生效）。
  String? effectiveToDate;

  HabitPeriodType periodType;

  /// 指定星期时的掩码：bit 0 = 周一 … bit 6 = 周日。
  int weekdaysMask;

  /// 自定义周期天数（periodType == custom 时生效）。
  int? customIntervalDays;

  /// 目标值：
  /// - 完成型：1；
  /// - 时长型：目标时长（秒）；
  /// - 数量型：目标数量；
  /// - 时间点型：0（不使用）。
  /// 默认 0，与 fromJson / 数据库 DEFAULT 保持一致。
  double targetValue;

  /// 单位（数量型，如 ml、个、次；时长型为空或“分钟”）。
  String unit;

  /// 目标时间（一天内的分钟数），仅时间点型。
  int? targetTimeMinute;

  /// 目标比较方式，仅时间点型。
  HabitTimeComparison timeComparison;

  /// 允许范围（分钟）。before 型允许晚于目标 N 分钟，after 型允许早于 N 分钟。
  int timeToleranceMinutes;

  /// 日期分界时间（一天内的分钟数），早睡等跨午夜习惯默认 04:00。
  int dayBoundaryMinute;

  /// 快捷增加值（数量型，最多 4 个）。
  List<int> quickValues;

  HabitReminderPolicy reminderPolicy;

  bool isDeleted;
  int version;
  String? deviceId;
  int createdAt;
  int updatedAt;
  bool hasConflict;
  Map<String, dynamic>? conflictData;

  HabitGoalRuleRevision({
    String? uuid,
    required this.habitUuid,
    this.effectiveFromDate,
    this.effectiveToDate,
    this.periodType = HabitPeriodType.daily,
    this.weekdaysMask = 127,
    this.customIntervalDays,
    this.targetValue = 0,
    this.unit = '',
    this.targetTimeMinute,
    this.timeComparison = HabitTimeComparison.before,
    this.timeToleranceMinutes = 0,
    this.dayBoundaryMinute = 0,
    List<int>? quickValues,
    HabitReminderPolicy? reminderPolicy,
    this.isDeleted = false,
    this.version = 1,
    this.deviceId,
    int? createdAt,
    int? updatedAt,
    this.hasConflict = false,
    this.conflictData,
  })  : uuid = uuid ?? const Uuid().v4(),
        quickValues = quickValues ?? [],
        reminderPolicy = reminderPolicy ?? const HabitReminderPolicy(),
        createdAt = createdAt ?? DateTime.now().millisecondsSinceEpoch,
        updatedAt = updatedAt ?? DateTime.now().millisecondsSinceEpoch;

  void markAsChanged() {
    version++;
    final now = DateTime.now().millisecondsSinceEpoch;
    updatedAt = now > updatedAt ? now : updatedAt + 1;
  }

  /// 该规则是否覆盖给定逻辑日期（'yyyy-MM-dd'）。
  bool coversDate(String dateKey) {
    if (isDeleted) return false;
    if (effectiveFromDate != null &&
        dateKey.compareTo(effectiveFromDate!) < 0) {
      return false;
    }
    if (effectiveToDate != null && dateKey.compareTo(effectiveToDate!) > 0) {
      return false;
    }
    return true;
  }

  Map<String, dynamic> toJson() => {
        'uuid': uuid,
        'habit_uuid': habitUuid,
        'effective_from_date': effectiveFromDate,
        'effective_to_date': effectiveToDate,
        'period_type': periodType.index,
        'weekdays_mask': weekdaysMask,
        'custom_interval_days': customIntervalDays,
        'target_value': targetValue,
        'unit': unit,
        'target_time_minute': targetTimeMinute,
        'time_comparison': timeComparison.index,
        'time_tolerance_minutes': timeToleranceMinutes,
        'day_boundary_minute': dayBoundaryMinute,
        'quick_values_json': jsonEncode(quickValues),
        'reminder_policy_json': jsonEncode(reminderPolicy.toJson()),
        'is_deleted': isDeleted ? 1 : 0,
        'version': version,
        'device_id': deviceId,
        'created_at': createdAt,
        'updated_at': updatedAt,
        'has_conflict': hasConflict ? 1 : 0,
        'conflict_data': conflictData != null ? jsonEncode(conflictData) : null,
      };

  factory HabitGoalRuleRevision.fromJson(Map<String, dynamic> json) {
    List<int> quickValues = [];
    final rawQuick = json['quick_values_json'];
    if (rawQuick is List) {
      quickValues =
          rawQuick.map((e) => int.tryParse(e.toString()) ?? 0).toList();
    } else if (rawQuick is String && rawQuick.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawQuick);
        if (decoded is List) {
          quickValues =
              decoded.map((e) => int.tryParse(e.toString()) ?? 0).toList();
        }
      } catch (_) {}
    }

    HabitReminderPolicy reminderPolicy = const HabitReminderPolicy();
    final rawReminder = json['reminder_policy_json'];
    if (rawReminder is Map) {
      reminderPolicy =
          HabitReminderPolicy.fromJson(Map<String, dynamic>.from(rawReminder));
    } else if (rawReminder is String && rawReminder.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawReminder);
        if (decoded is Map) {
          reminderPolicy =
              HabitReminderPolicy.fromJson(Map<String, dynamic>.from(decoded));
        }
      } catch (_) {}
    }

    return HabitGoalRuleRevision(
      uuid: json['uuid']?.toString() ?? const Uuid().v4(),
      habitUuid: json['habit_uuid']?.toString() ?? '',
      effectiveFromDate: json['effective_from_date']?.toString(),
      effectiveToDate: json['effective_to_date']?.toString(),
      periodType: HabitPeriodType
          .values[int.tryParse(json['period_type']?.toString() ?? '') ?? 0],
      weekdaysMask:
          int.tryParse(json['weekdays_mask']?.toString() ?? '') ?? 127,
      customIntervalDays: json['custom_interval_days'] != null
          ? int.tryParse(json['custom_interval_days'].toString())
          : null,
      targetValue: double.tryParse(json['target_value']?.toString() ?? '') ?? 0,
      unit: json['unit']?.toString() ?? '',
      targetTimeMinute: json['target_time_minute'] != null
          ? int.tryParse(json['target_time_minute'].toString())
          : null,
      timeComparison: HabitTimeComparison
          .values[int.tryParse(json['time_comparison']?.toString() ?? '') ?? 0],
      timeToleranceMinutes:
          int.tryParse(json['time_tolerance_minutes']?.toString() ?? '') ?? 0,
      dayBoundaryMinute:
          int.tryParse(json['day_boundary_minute']?.toString() ?? '') ?? 0,
      quickValues: quickValues,
      reminderPolicy: reminderPolicy,
      isDeleted: json['is_deleted'] == 1 || json['is_deleted'] == true,
      version: int.tryParse(json['version']?.toString() ?? '') ?? 1,
      deviceId: json['device_id']?.toString(),
      createdAt: _parseMs(json['created_at']),
      updatedAt: _parseMs(json['updated_at']),
      hasConflict: json['has_conflict'] == 1 || json['has_conflict'] == true,
      conflictData: _mapOrNull(json['conflict_data']),
    );
  }

  static Map<String, dynamic>? _mapOrNull(dynamic raw) {
    if (raw == null) return null;
    if (raw is Map) return Map<String, dynamic>.from(raw);
    if (raw is String && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) return Map<String, dynamic>.from(decoded);
      } catch (_) {}
    }
    return null;
  }

  static int _parseMs(dynamic v) {
    if (v == null) return DateTime.now().millisecondsSinceEpoch;
    final n = int.tryParse(v.toString());
    return n ?? DateTime.now().millisecondsSinceEpoch;
  }
}
