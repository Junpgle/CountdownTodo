import '../models/habit_goal_rule.dart';

/// 习惯规则解析：逻辑日期、生效规则、计划日与周期计算。
///
/// 纯函数实现，便于单元测试。
abstract final class HabitRuleResolver {
  /// 计算逻辑日期：实际本地时间减去日期分界时长后的日期。
  ///
  /// 早睡习惯日期分界为 04:00 时：
  /// 7 月 31 日 23:30 → 7 月 31 日；8 月 1 日 00:40 → 7 月 31 日；
  /// 8 月 1 日 04:20 → 8 月 1 日。
  static DateTime logicalDateFor(DateTime localTime, int dayBoundaryMinute) {
    final shifted = localTime.subtract(Duration(minutes: dayBoundaryMinute));
    return DateTime(shifted.year, shifted.month, shifted.day);
  }

  /// 逻辑日期键（'yyyy-MM-dd'），用于数据库存储与比较。
  static String dayKey(DateTime logicalDate) {
    final d = DateTime(logicalDate.year, logicalDate.month, logicalDate.day);
    return '${d.year.toString().padLeft(4, '0')}-'
        '${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';
  }

  /// 解析 'yyyy-MM-dd' 为本地日期。
  static DateTime? parseDayKey(String key) {
    final parts = key.split('-');
    if (parts.length != 3) return null;
    final year = int.tryParse(parts[0]);
    final month = int.tryParse(parts[1]);
    final day = int.tryParse(parts[2]);
    if (year == null || month == null || day == null) return null;
    return DateTime(year, month, day);
  }

  /// 获取给定日期（逻辑日期）生效的规则版本：
  /// 从最近一次生效日期不晚于该日期的未删除版本中选择。
  static HabitGoalRuleRevision? effectiveRule(
    List<HabitGoalRuleRevision> rules,
    DateTime logicalDate,
  ) {
    final dateKey = dayKey(logicalDate);
    HabitGoalRuleRevision? best;
    for (final rule in rules) {
      if (rule.isDeleted) continue;
      if (rule.effectiveFromDate != null &&
          rule.effectiveFromDate!.compareTo(dateKey) > 0) {
        continue;
      }
      if (rule.effectiveToDate != null &&
          rule.effectiveToDate!.compareTo(dateKey) < 0) {
        continue;
      }
      if (best == null ||
          (rule.effectiveFromDate ?? '').compareTo(
                best.effectiveFromDate ?? '',
              ) >
              0) {
        best = rule;
      }
    }
    return best;
  }

  /// 当前生效规则（今天），供今日卡片使用。
  static HabitGoalRuleRevision? currentRule(
    List<HabitGoalRuleRevision> rules,
    int dayBoundaryMinute,
    DateTime? now,
  ) {
    final current = now ?? DateTime.now();
    return effectiveRule(rules, logicalDateFor(current, dayBoundaryMinute));
  }

  /// 该逻辑日期是否为计划日。
  static bool isPlannedDay(HabitGoalRuleRevision rule, DateTime logicalDate) {
    switch (rule.periodType) {
      case HabitPeriodType.daily:
        return true;
      case HabitPeriodType.weekly:
      case HabitPeriodType.monthly:
        // 周期累计目标：周期内的每一天都可能是执行日，但达标按整个周期判断。
        return true;
      case HabitPeriodType.weekdays:
        final weekdayIndex = logicalDate.weekday - 1; // 0 = 周一
        return (rule.weekdaysMask & (1 << weekdayIndex)) != 0;
      case HabitPeriodType.custom:
        final interval = rule.customIntervalDays ?? 1;
        if (interval <= 0) return true;
        final anchor = _customAnchor(rule);
        if (anchor == null) return true;
        final diffDays = logicalDate
            .difference(DateTime(anchor.year, anchor.month, anchor.day))
            .inDays;
        return diffDays % interval == 0;
    }
  }

  /// 自定义周期的锚点日期：规则生效起始日。
  static DateTime? _customAnchor(HabitGoalRuleRevision rule) {
    final from = rule.effectiveFromDate;
    if (from == null) return null;
    return parseDayKey(from);
  }

  /// 周期起始（本地 00:00）：
  /// - daily / weekdays / custom：当天；
  /// - weekly：本周周一；
  /// - monthly：本月 1 号。
  static DateTime periodStart(
    HabitGoalRuleRevision rule,
    DateTime logicalDate,
  ) {
    final day = DateTime(logicalDate.year, logicalDate.month, logicalDate.day);
    switch (rule.periodType) {
      case HabitPeriodType.daily:
      case HabitPeriodType.weekdays:
      case HabitPeriodType.custom:
        return day;
      case HabitPeriodType.weekly:
        return day.subtract(Duration(days: day.weekday - 1));
      case HabitPeriodType.monthly:
        return DateTime(day.year, day.month, 1);
    }
  }

  /// 周期结束（不含当天，用于时间范围查询）。
  static DateTime periodEndExclusive(
    HabitGoalRuleRevision rule,
    DateTime logicalDate,
  ) {
    final start = periodStart(rule, logicalDate);
    switch (rule.periodType) {
      case HabitPeriodType.daily:
      case HabitPeriodType.weekdays:
      case HabitPeriodType.custom:
        return start.add(const Duration(days: 1));
      case HabitPeriodType.weekly:
        return start.add(const Duration(days: 7));
      case HabitPeriodType.monthly:
        return DateTime(start.year, start.month + 1, 1);
    }
  }

  /// 周期是否已经结束。
  static bool isPeriodFinished(
    HabitGoalRuleRevision rule,
    DateTime logicalDate,
    DateTime now,
  ) {
    final end = periodEndExclusive(rule, logicalDate);
    return now.isAfter(end);
  }

  /// 下一个周期起始日期。
  static DateTime nextPeriodStart(
    HabitGoalRuleRevision rule,
    DateTime logicalDate,
  ) {
    switch (rule.periodType) {
      case HabitPeriodType.daily:
      case HabitPeriodType.weekdays:
      case HabitPeriodType.custom:
        return periodStart(rule, logicalDate).add(const Duration(days: 1));
      case HabitPeriodType.weekly:
        return periodStart(rule, logicalDate).add(const Duration(days: 7));
      case HabitPeriodType.monthly:
        final start = periodStart(rule, logicalDate);
        return DateTime(start.year, start.month + 1, 1);
    }
  }

  /// 周期键：每天习惯按天、每周按 ISO 周、每月按年月。
  static String periodKey(
    HabitGoalRuleRevision rule,
    DateTime logicalDate,
  ) {
    switch (rule.periodType) {
      case HabitPeriodType.daily:
      case HabitPeriodType.weekdays:
      case HabitPeriodType.custom:
        return dayKey(logicalDate);
      case HabitPeriodType.weekly:
        final start = periodStart(rule, logicalDate);
        return 'w-${start.year}-${start.month.toString().padLeft(2, '0')}-${start.day.toString().padLeft(2, '0')}';
      case HabitPeriodType.monthly:
        final start = periodStart(rule, logicalDate);
        return 'm-${start.year}-${start.month.toString().padLeft(2, '0')}';
    }
  }

  /// 判断时间点型习惯的实际时间是否达标。
  static bool isTimePointMet(
    HabitGoalRuleRevision rule,
    DateTime localActualTime,
  ) {
    final target = rule.targetTimeMinute;
    if (target == null) return false;
    final actualMinute = localActualTime.hour * 60 + localActualTime.minute;
    final tolerance = rule.timeToleranceMinutes;
    switch (rule.timeComparison) {
      case HabitTimeComparison.before:
        return actualMinute <= target + tolerance;
      case HabitTimeComparison.after:
        return actualMinute >= target - tolerance;
    }
  }
}
