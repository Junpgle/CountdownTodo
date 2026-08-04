import '../models/habit_goal.dart';
import '../models/habit_goal_rule.dart';
import '../models/habit_progress.dart';
import '../services/habit_adaptation_service.dart';
import '../services/habit_rule_resolver.dart';

/// 习惯文案格式化工具。
abstract final class HabitText {
  /// 周期类型文案。
  static String periodLabel(HabitGoalRuleRevision rule) {
    switch (rule.periodType) {
      case HabitPeriodType.daily:
        return '每天';
      case HabitPeriodType.weekly:
        return '每周';
      case HabitPeriodType.monthly:
        return '每月';
      case HabitPeriodType.weekdays:
        final names = <String>['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
        final selected = <String>[];
        for (int i = 0; i < 7; i++) {
          if ((rule.weekdaysMask & (1 << i)) != 0) {
            selected.add(names[i]);
          }
        }
        if (selected.isEmpty) return '每周';
        if (selected.length == 5 && selected.join() == '周一,周二,周三,周四,周五') {
          return '工作日';
        }
        if (selected.length == 7) return '每天';
        return selected.join('、');
      case HabitPeriodType.custom:
        return '每 ${rule.customIntervalDays ?? 1} 天';
    }
  }

  /// 数量/时长文本：`1250 / 2000 ml`。
  static String amountProgress(HabitProgress progress, String unit) {
    final current = _trimNumber(progress.currentValue);
    final target = _trimNumber(progress.targetValue);
    final unitText = unit.isNotEmpty ? ' $unit' : '';
    return '$current / $target$unitText';
  }

  /// 时长文本（秒 → 分钟）。
  static String durationProgress(HabitProgress progress) {
    final currentMin = (progress.currentValue / 60).ceil();
    final targetMin = (progress.targetValue / 60).ceil();
    return '$currentMin / $targetMin 分钟';
  }

  /// 根据深度适配的习惯类型显示时长进度。
  ///
  /// 睡眠时长的底层值同样是秒，但用户更适合看到「7 小时 30 分 / 8 小时」；
  /// 普通时长习惯继续使用分钟口径。
  static String durationProgressForGoal(
    HabitGoal goal,
    HabitProgress progress,
  ) {
    if (HabitAdaptationService.forHabit(goal)?.kind ==
        HabitAdaptationKind.sleepDuration) {
      return '${formatDuration(progress.currentValue.round())} / '
          '${formatDuration(progress.targetValue.round())}';
    }
    return durationProgress(progress);
  }

  /// 时间点型：实际时间。
  static String timeOfDay(DateTime time) =>
      '${time.hour.toString().padLeft(2, '0')}:'
      '${time.minute.toString().padLeft(2, '0')}';

  /// 秒数 → 人类可读时长，如「2 小时 05 分」/「45 分钟」。
  static String formatDuration(int seconds) {
    final totalMinutes = (seconds / 60).round();
    final h = totalMinutes ~/ 60;
    final m = totalMinutes % 60;
    if (h > 0 && m > 0) return '$h 小时 ${m.toString().padLeft(2, '0')} 分';
    if (h > 0) return '$h 小时';
    return '$m 分钟';
  }

  /// 目标时间文案（分钟 → HH:mm）。
  static String targetTime(int? minuteOfDay) {
    if (minuteOfDay == null) return '';
    final h = (minuteOfDay ~/ 60) % 24;
    final m = minuteOfDay % 60;
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
  }

  /// 时间点型习惯的状态说明，如「比目标早 12 分钟」。
  static String timePointStatus(
    HabitGoalRuleRevision rule,
    HabitProgress progress,
  ) {
    final actual = progress.firstRecordAt;
    if (actual == null) return '未打卡';
    final targetMinute = rule.targetTimeMinute ?? 0;
    final actualMinute = actual.hour * 60 + actual.minute;
    if (!progress.goalMet) {
      final diff = rule.timeComparison == HabitTimeComparison.before
          ? actualMinute - targetMinute
          : targetMinute - actualMinute;
      if (diff > 0) {
        return '比目标晚 $diff 分钟';
      }
      return '未达标';
    }
    // 凌晨打卡归属前夜，按扩展分钟与目标比较，与 isTimePointMet 口径一致，
    // 避免跨午夜宽限内达标却显示「比目标早 1390 分钟」。
    final dayBoundary = rule.dayBoundaryMinute > 0
        ? rule.dayBoundaryMinute
        : HabitRuleResolver.defaultDayBoundaryMinute;
    final effectiveActual =
        actualMinute < dayBoundary ? actualMinute + 24 * 60 : actualMinute;
    // 目标本身也可能落在日期分界之前（如 00:30）。实际时间和目标
    // 必须位于同一条扩展时间轴，否则 00:06 会被拿去和前一天的
    // 00:30 比较，错误显示为晚了 1416 分钟。
    final effectiveTarget =
        targetMinute < dayBoundary ? targetMinute + 24 * 60 : targetMinute;
    final diff = rule.timeComparison == HabitTimeComparison.before
        ? effectiveTarget - effectiveActual
        : effectiveActual - effectiveTarget;
    if (rule.timeToleranceMinutes > 0 &&
        diff.abs() <= rule.timeToleranceMinutes) {
      return '已达标';
    }
    if (diff > 0) return '比目标早 $diff 分钟';
    if (diff < 0) return '比目标晚 ${-diff} 分钟';
    return '准时达标';
  }

  static String _trimNumber(double value) {
    if (value == value.roundToDouble()) return value.round().toString();
    return value.toStringAsFixed(1);
  }

  /// 习惯类型标签。
  static String sourceTypeLabel(HabitSourceType type) {
    switch (type) {
      case HabitSourceType.recurringTodo:
        return '完成一次';
      case HabitSourceType.pomodoroTag:
        return '累计时长';
      case HabitSourceType.durationCheckIn:
        return '时长打卡';
      case HabitSourceType.quantityCheckIn:
        return '累计数量';
      case HabitSourceType.timeCheckIn:
        return '记录时间';
    }
  }

  /// 日期分界文案。
  static String dayBoundaryLabel(int minuteOfDay) {
    if (minuteOfDay == 0) return '00:00';
    return targetTime(minuteOfDay);
  }
}
