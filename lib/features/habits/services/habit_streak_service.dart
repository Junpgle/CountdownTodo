import '../models/habit_goal.dart';
import '../models/habit_goal_rule.dart';
import '../models/habit_progress.dart';
import 'habit_progress_calculator.dart';
import 'habit_rule_resolver.dart';

/// 连续达标与完成率统计。
///
/// 规则（设计文档第十七节）：
/// - 计划日达标：连续加一；计划日未达标：连续中断；
/// - 非计划日：不增加也不中断；未来日期不参与；
/// - 当天尚未结束：不提前判定失败，连续不中断也不增加；
/// - 每周/每月习惯按周期（周/月）而不是按天计算连续。
abstract final class HabitStreakService {
  /// 统计一个习惯的连续达标与完成率。
  ///
  /// [lookbackDays] 控制回看窗口，防止历史过长拖慢统计；
  /// 为 null 时按周期类型自适应（天/自定义约 1 年，周约 104 周，月约 60 月）。
  static Future<HabitStreakSummary> summarize({
    required HabitGoal habit,
    required List<HabitGoalRuleRevision> rules,
    DateTime? now,
    int? lookbackDays,
  }) async {
    final nowValue = now ?? DateTime.now();
    if (rules.isEmpty) {
      return const HabitStreakSummary();
    }
    final rule = HabitRuleResolver.effectiveRule(rules, nowValue) ??
        rules.firstWhere((r) => !r.isDeleted, orElse: () => rules.first);
    final today = HabitRuleResolver.logicalDateFor(
      nowValue,
      rule.dayBoundaryMinute,
    );
    final lookback = lookbackDays ?? _defaultLookbackDays(rule.periodType);
    final from = today.subtract(Duration(days: lookback));

    final days = await HabitProgressCalculator.computeRange(
      habit: habit,
      rules: rules,
      from: from,
      to: today,
      now: nowValue,
      // 每周/每月习惯只需周期级进度：跳过周期内重复条目，
      // 避免 60 个月回看窗口生成约 1860 个 day-level 条目。
      periodLevel: true,
    );

    return summarizeFromDays(
      habit: habit,
      days: days,
      rule: rule,
      now: nowValue,
    );
  }

  /// 从逐日进度直接统计（复用已计算的数据）。
  static HabitStreakSummary summarizeFromDays({
    required HabitGoal habit,
    required List<HabitDayProgress> days,
    required HabitGoalRuleRevision rule,
    required DateTime now,
  }) {
    // 聚合为周期级进度。
    final periodMap = <String, _PeriodEntry>{};
    for (final day in days) {
      final key = HabitRuleResolver.periodKey(rule, day.logicalDate);
      final entry = periodMap.putIfAbsent(
        key,
        () => _PeriodEntry(
          start: HabitRuleResolver.periodStart(rule, day.logicalDate),
          planned: day.progress.isPlanned,
        ),
      );
      entry.planned = entry.planned || day.progress.isPlanned;
      entry.met = entry.met || day.progress.goalMet;
      entry.finished = entry.finished || day.progress.isFinished;
    }

    final periods = periodMap.values.toList()
      ..sort((a, b) => a.start.compareTo(b.start));

    // 连续达标。
    int currentStreak = 0;
    for (int i = periods.length - 1; i >= 0; i--) {
      final period = periods[i];
      if (!period.planned) continue;
      if (!period.finished) {
        // 当前周期尚未结束：达标则计入，未达标不中断也不增加。
        if (period.met) currentStreak++;
        continue;
      }
      if (period.met) {
        currentStreak++;
      } else {
        break;
      }
    }

    int longestStreak = 0;
    int running = 0;
    for (final period in periods) {
      if (!period.planned) continue;
      if (!period.finished) {
        // 当前周期尚未结束：达标计入、未达标不中断，与 currentStreak 口径一致，
        // 保证 longestStreak >= currentStreak 恒成立。
        if (period.met) {
          running++;
          if (running > longestStreak) longestStreak = running;
        }
        continue;
      }
      if (period.met) {
        running++;
        if (running > longestStreak) longestStreak = running;
      } else {
        running = 0;
      }
    }

    // 完成率：近 7 / 30 个周期。
    final rateWindow = (List<_PeriodEntry>.from(periods.reversed))
        .where((p) => p.finished)
        .toList();

    int totalPlanned30 = 0;
    int totalCompleted30 = 0;
    int totalOverdue30 = 0;
    for (int i = 0; i < 30 && i < rateWindow.length; i++) {
      final p = rateWindow[i];
      if (!p.planned) continue;
      totalPlanned30++;
      if (p.met) {
        totalCompleted30++;
      } else {
        totalOverdue30++;
      }
    }
    final rate30 =
        totalPlanned30 == 0 ? 0.0 : totalCompleted30 / totalPlanned30;

    int planned7 = 0;
    int completed7 = 0;
    for (int i = 0; i < 7 && i < rateWindow.length; i++) {
      final p = rateWindow[i];
      if (!p.planned) continue;
      planned7++;
      if (p.met) completed7++;
    }
    final rate7 = planned7 == 0 ? 0.0 : completed7 / planned7;

    final isDailyLike = rule.periodType == HabitPeriodType.daily ||
        rule.periodType == HabitPeriodType.weekdays ||
        rule.periodType == HabitPeriodType.custom;

    int? weakestWeekday;
    double? averageValue;
    double? averageDuration;
    double? averageTimeMinute;
    double? onTimeRate;

    if (isDailyLike) {
      // 最容易中断的星期：按星期统计未达标率（仅已结束计划日）。
      final missByWeekday = <int, List<bool>>{};
      for (final day in days) {
        if (!day.progress.isPlanned || !day.progress.isFinished) continue;
        final weekday = day.logicalDate.weekday - 1;
        missByWeekday.putIfAbsent(weekday, () => []).add(day.progress.goalMet);
      }
      double? weakestRate;
      missByWeekday.forEach((weekday, results) {
        if (results.length < 2) return;
        final missRate = results.where((met) => !met).length / results.length;
        if (weakestRate == null || missRate > weakestRate!) {
          weakestRate = missRate;
          weakestWeekday = weekday;
        }
      });
      if (weakestRate != null && weakestRate! <= 0) weakestWeekday = null;

      // 平均值与准时率（仅已结束且当日有记录的计划日）。
      final recordedDays = days
          .where((d) =>
              d.progress.isPlanned &&
              d.progress.isFinished &&
              d.progress.hasRecord)
          .toList();
      if (recordedDays.isNotEmpty) {
        switch (habit.sourceType) {
          case HabitSourceType.recurringTodo:
            break;
          case HabitSourceType.quantityCheckIn:
            averageValue = recordedDays
                    .map((d) => d.progress.currentValue)
                    .reduce((a, b) => a + b) /
                recordedDays.length;
          case HabitSourceType.pomodoroTag:
            averageDuration = recordedDays
                    .map((d) => d.progress.currentValue)
                    .reduce((a, b) => a + b) /
                recordedDays.length;
          case HabitSourceType.timeCheckIn:
            final times = recordedDays
                .where((d) => d.progress.firstRecordAt != null)
                .map((d) =>
                    d.progress.firstRecordAt!.hour * 60 +
                    d.progress.firstRecordAt!.minute)
                .toList();
            if (times.isNotEmpty) {
              averageTimeMinute = times.reduce((a, b) => a + b) / times.length;
              final onTimeCount =
                  recordedDays.where((d) => d.progress.goalMet).length;
              onTimeRate = onTimeCount / recordedDays.length;
            }
        }
      }
    }

    return HabitStreakSummary(
      currentStreak: currentStreak,
      longestStreak: longestStreak,
      rate7: rate7,
      rate30: rate30,
      plannedCount: totalPlanned30,
      completedCount: totalCompleted30,
      overdueCount: totalOverdue30,
      weakestWeekday: weakestWeekday,
      averageValue: averageValue,
      averageDuration: averageDuration,
      averageTimeMinute: averageTimeMinute,
      onTimeRate: onTimeRate,
    );
  }

  /// 按周期类型估算足够的回看窗口（覆盖 rate30 与常见连续长度）。
  static int _defaultLookbackDays(HabitPeriodType periodType) {
    switch (periodType) {
      case HabitPeriodType.weekly:
        return 104 * 7; // 104 周
      case HabitPeriodType.monthly:
        return 60 * 31; // 60 个月
      case HabitPeriodType.daily:
      case HabitPeriodType.weekdays:
      case HabitPeriodType.custom:
        return 400;
    }
  }
}

class _PeriodEntry {
  final DateTime start;
  bool planned;
  bool met = false;
  bool finished = false;

  _PeriodEntry({
    required this.start,
    required this.planned,
  });
}
