import 'dart:convert';

import 'package:uuid/uuid.dart';

import '../../../utils/json_value_parser.dart';
import 'habit_goal.dart';

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

/// 提醒与规划策略（保存在 `reminder_policy_json` 中，兼容多端同步）。
class HabitReminderPolicy {
  /// 固定提醒时刻（一天内的分钟数，0..1439）。
  final List<int> fixedTimes;

  /// 进度提醒。
  final bool progressReminder;

  /// 临近结束提醒。
  final bool nearEndReminder;

  /// 当日汇总提醒。
  final bool dailySummaryReminder;

  /// 是否作为软日程预留接入「今日容量与规划块」。
  final bool includeInPlanning;

  /// 偏好执行开始时刻（一天内的分钟数，0..1439）。
  final int? preferredStartMinute;

  /// 预计执行耗时（分钟）。
  final int? plannedDurationMinutes;

  /// 绑定的番茄钟专注标签 UUID（供非专注时长型习惯一键启动专注使用）。
  final List<String> focusTagUuids;

  /// 番茄钟专注达标后是否自动完成今日习惯打卡。
  final bool autoCheckInOnFocus;

  const HabitReminderPolicy({
    this.fixedTimes = const [],
    this.progressReminder = false,
    this.nearEndReminder = false,
    this.dailySummaryReminder = false,
    this.includeInPlanning = false,
    this.preferredStartMinute,
    this.plannedDurationMinutes,
    this.focusTagUuids = const [],
    this.autoCheckInOnFocus = true,
  });

  HabitReminderPolicy copyWith({
    List<int>? fixedTimes,
    bool? progressReminder,
    bool? nearEndReminder,
    bool? dailySummaryReminder,
    bool? includeInPlanning,
    int? preferredStartMinute,
    bool clearPreferredStartMinute = false,
    int? plannedDurationMinutes,
    bool clearPlannedDurationMinutes = false,
    List<String>? focusTagUuids,
    bool? autoCheckInOnFocus,
  }) {
    return HabitReminderPolicy(
      fixedTimes: fixedTimes ?? this.fixedTimes,
      progressReminder: progressReminder ?? this.progressReminder,
      nearEndReminder: nearEndReminder ?? this.nearEndReminder,
      dailySummaryReminder: dailySummaryReminder ?? this.dailySummaryReminder,
      includeInPlanning: includeInPlanning ?? this.includeInPlanning,
      preferredStartMinute: clearPreferredStartMinute
          ? null
          : (preferredStartMinute ?? this.preferredStartMinute),
      plannedDurationMinutes: clearPlannedDurationMinutes
          ? null
          : (plannedDurationMinutes ?? this.plannedDurationMinutes),
      focusTagUuids: focusTagUuids ?? this.focusTagUuids,
      autoCheckInOnFocus: autoCheckInOnFocus ?? this.autoCheckInOnFocus,
    );
  }

  Map<String, dynamic> toJson() => {
    'fixed_times': fixedTimes,
    'progress_reminder': progressReminder ? 1 : 0,
    'near_end_reminder': nearEndReminder ? 1 : 0,
    'daily_summary_reminder': dailySummaryReminder ? 1 : 0,
    if (includeInPlanning) 'include_in_planning': 1,
    if (preferredStartMinute != null)
      'preferred_start_minute': preferredStartMinute,
    if (plannedDurationMinutes != null)
      'planned_duration_minutes': plannedDurationMinutes,
    if (focusTagUuids.isNotEmpty) 'focus_tag_uuids': focusTagUuids,
    if (!autoCheckInOnFocus) 'auto_checkin_on_focus': 0,
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
    List<String> focusTags = [];
    final rawTags = json['focus_tag_uuids'];
    if (rawTags is List) {
      focusTags = rawTags
          .map((e) => e.toString().trim())
          .where((e) => e.isNotEmpty)
          .toList();
    }
    final rawStart = int.tryParse(
      json['preferred_start_minute']?.toString() ?? '',
    );
    final rawDuration = int.tryParse(
      json['planned_duration_minutes']?.toString() ?? '',
    );
    final rawAutoCheckIn = json['auto_checkin_on_focus'];
    return HabitReminderPolicy(
      fixedTimes: times,
      progressReminder:
          json['progress_reminder'] == 1 || json['progress_reminder'] == true,
      nearEndReminder:
          json['near_end_reminder'] == 1 || json['near_end_reminder'] == true,
      dailySummaryReminder:
          json['daily_summary_reminder'] == 1 ||
          json['daily_summary_reminder'] == true,
      includeInPlanning:
          json['include_in_planning'] == 1 ||
          json['include_in_planning'] == true,
      preferredStartMinute: rawStart != null && rawStart >= 0 && rawStart < 1440
          ? rawStart
          : null,
      plannedDurationMinutes: rawDuration != null && rawDuration > 0
          ? rawDuration
          : null,
      focusTagUuids: focusTags,
      autoCheckInOnFocus: rawAutoCheckIn == null
          ? true
          : (rawAutoCheckIn == 1 || rawAutoCheckIn == true),
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
  }) : uuid = uuid ?? const Uuid().v4(),
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

  /// 解析习惯的预计耗时（分钟）。
  int effectivePlannedMinutes(HabitGoal goal) {
    final configured = reminderPolicy.plannedDurationMinutes;
    if (configured != null && configured > 0) {
      return configured.clamp(5, 720);
    }
    final defaultFocus = goal.defaultFocusMinutes;
    if (defaultFocus != null && defaultFocus > 0) {
      return defaultFocus.clamp(5, 720);
    }
    if (goal.sourceType == HabitSourceType.pomodoroTag ||
        goal.sourceType == HabitSourceType.durationCheckIn) {
      final mins = (targetValue / 60).round();
      if (mins > 0) return mins.clamp(5, 720);
    }
    return 25;
  }

  /// 解析习惯的偏好执行开始时刻（一天内的分钟数，0..1439）。
  int? effectivePreferredStartMinute() {
    final configured = reminderPolicy.preferredStartMinute;
    if (configured != null && configured >= 0 && configured < 1440) {
      return configured;
    }
    if (targetTimeMinute != null &&
        targetTimeMinute! >= 0 &&
        targetTimeMinute! < 1440) {
      return targetTimeMinute;
    }
    if (reminderPolicy.fixedTimes.isNotEmpty) {
      return reminderPolicy.fixedTimes.first;
    }
    return null;
  }

  /// 是否已启用且具备生成今日容量与规划软块的完整时间参数。
  bool hasPlanningBlock(HabitGoal goal) {
    return reminderPolicy.includeInPlanning &&
        effectivePreferredStartMinute() != null &&
        effectivePlannedMinutes(goal) > 0;
  }

  /// 解析习惯关联的番茄钟标签 UUID 列表。
  List<String> effectiveFocusTagUuids(HabitGoal goal) {
    if (goal.sourceType == HabitSourceType.pomodoroTag) {
      return goal.sourceIds;
    }
    return reminderPolicy.focusTagUuids;
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
      quickValues = rawQuick
          .map((e) => int.tryParse(e.toString()) ?? 0)
          .toList();
    } else if (rawQuick is String && rawQuick.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawQuick);
        if (decoded is List) {
          quickValues = decoded
              .map((e) => int.tryParse(e.toString()) ?? 0)
              .toList();
        }
      } catch (_) {}
    }

    HabitReminderPolicy reminderPolicy = const HabitReminderPolicy();
    final rawReminder = json['reminder_policy_json'];
    if (rawReminder is Map) {
      reminderPolicy = HabitReminderPolicy.fromJson(
        Map<String, dynamic>.from(rawReminder),
      );
    } else if (rawReminder is String && rawReminder.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawReminder);
        if (decoded is Map) {
          reminderPolicy = HabitReminderPolicy.fromJson(
            Map<String, dynamic>.from(decoded),
          );
        }
      } catch (_) {}
    }

    return HabitGoalRuleRevision(
      uuid: json['uuid']?.toString() ?? const Uuid().v4(),
      habitUuid: json['habit_uuid']?.toString() ?? '',
      effectiveFromDate: json['effective_from_date']?.toString(),
      effectiveToDate: json['effective_to_date']?.toString(),
      periodType: JsonValueParser.enumByIndex(
        HabitPeriodType.values,
        json['period_type'],
        fallback: HabitPeriodType.daily,
      ),
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
      timeComparison: JsonValueParser.enumByIndex(
        HabitTimeComparison.values,
        json['time_comparison'],
        fallback: HabitTimeComparison.before,
      ),
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
    return JsonValueParser.epochMillisOrNow(v);
  }
}
