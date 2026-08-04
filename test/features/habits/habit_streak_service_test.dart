import 'package:countdown_todo/features/habits/models/habit_goal.dart';
import 'package:countdown_todo/features/habits/models/habit_goal_rule.dart';
import 'package:countdown_todo/features/habits/models/habit_progress.dart';
import 'package:countdown_todo/features/habits/services/habit_streak_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('HabitStreakService', () {
    test('连续达标：昨天达标今天达标', () async {
      final habit = HabitGoal(
        uuid: 'h1',
        name: 't',
        sourceType: HabitSourceType.quantityCheckIn,
      );
      final rule = HabitGoalRuleRevision(
        uuid: 'r1',
        habitUuid: 'h1',
        effectiveFromDate: '2026-07-01',
        periodType: HabitPeriodType.daily,
        targetValue: 100,
      );
      final now = DateTime(2026, 8, 5, 14, 0);
      final days = _days([
        _day(DateTime(2026, 8, 1), met: true),
        _day(DateTime(2026, 8, 2), met: true),
        _day(DateTime(2026, 8, 3), met: false),
        _day(DateTime(2026, 8, 4), met: true),
        _day(DateTime(2026, 8, 5), met: true),
      ]);

      final summary = HabitStreakService.summarizeFromDays(
        habit: habit,
        days: days,
        rule: rule,
        now: now,
      );
      expect(summary.currentStreak, 2);
      expect(summary.longestStreak, 2);
    });

    test('今天进行中未达标不中断连续', () async {
      final habit = HabitGoal(
        uuid: 'h1',
        name: 't',
        sourceType: HabitSourceType.quantityCheckIn,
      );
      final rule = HabitGoalRuleRevision(
        uuid: 'r1',
        habitUuid: 'h1',
        effectiveFromDate: '2026-07-01',
        periodType: HabitPeriodType.daily,
        targetValue: 100,
      );
      final now = DateTime(2026, 8, 5, 14, 0);
      final days = [
        // 8/1-8/4 全部达标，今天只有一半进度（进行中）。
        _day(DateTime(2026, 8, 1), met: true),
        _day(DateTime(2026, 8, 2), met: true),
        _day(DateTime(2026, 8, 3), met: true),
        _day(DateTime(2026, 8, 4), met: true),
        _day(DateTime(2026, 8, 5), met: false, finished: false),
      ];

      final summary = HabitStreakService.summarizeFromDays(
        habit: habit,
        days: days,
        rule: rule,
        now: now,
      );
      // 不提前判定失败：连续保持昨天的 4 天。
      expect(summary.currentStreak, 4);
      expect(summary.longestStreak, 4);
    });

    test('今天达标后连续加一', () async {
      final habit = HabitGoal(
        uuid: 'h1',
        name: 't',
        sourceType: HabitSourceType.quantityCheckIn,
      );
      final rule = HabitGoalRuleRevision(
        uuid: 'r1',
        habitUuid: 'h1',
        effectiveFromDate: '2026-07-01',
        periodType: HabitPeriodType.daily,
        targetValue: 100,
      );
      final now = DateTime(2026, 8, 5, 14, 0);
      final days = [
        _day(DateTime(2026, 8, 3), met: true),
        _day(DateTime(2026, 8, 4), met: true),
        _day(DateTime(2026, 8, 5), met: true, finished: false),
      ];

      final summary = HabitStreakService.summarizeFromDays(
        habit: habit,
        days: days,
        rule: rule,
        now: now,
      );
      expect(summary.currentStreak, 3);
    });

    test('非计划日不增加也不中断', () async {
      final habit = HabitGoal(
        uuid: 'h1',
        name: 't',
        sourceType: HabitSourceType.recurringTodo,
      );
      final rule = HabitGoalRuleRevision(
        uuid: 'r1',
        habitUuid: 'h1',
        effectiveFromDate: '2026-07-01',
        periodType: HabitPeriodType.weekdays,
        weekdaysMask: 31, // 周一至周五
      );
      final now = DateTime(2026, 8, 5, 14, 0); // 周三
      final days = [
        // 8/1（周六）非计划、8/2（周日）非计划
        _day(DateTime(2026, 8, 1), planned: false),
        _day(DateTime(2026, 8, 2), planned: false),
        // 8/3（周一）达标、8/4（周二）达标
        _day(DateTime(2026, 8, 3), met: true),
        _day(DateTime(2026, 8, 4), met: true),
        // 8/5（周三）进行中
        _day(DateTime(2026, 8, 5), met: false, finished: false),
      ];

      final summary = HabitStreakService.summarizeFromDays(
        habit: habit,
        days: days,
        rule: rule,
        now: now,
      );
      expect(summary.currentStreak, 2);
      expect(summary.longestStreak, 2);
    });

    test('计划日未达标中断连续', () async {
      final habit = HabitGoal(
        uuid: 'h1',
        name: 't',
        sourceType: HabitSourceType.quantityCheckIn,
      );
      final rule = HabitGoalRuleRevision(
        uuid: 'r1',
        habitUuid: 'h1',
        effectiveFromDate: '2026-07-01',
        periodType: HabitPeriodType.daily,
        targetValue: 100,
      );
      final now = DateTime(2026, 8, 5, 14, 0);
      final days = [
        _day(DateTime(2026, 8, 1), met: true),
        _day(DateTime(2026, 8, 2), met: true),
        _day(DateTime(2026, 8, 3), met: false),
        _day(DateTime(2026, 8, 4), met: true),
        _day(DateTime(2026, 8, 5), met: true),
      ];

      final summary = HabitStreakService.summarizeFromDays(
        habit: habit,
        days: days,
        rule: rule,
        now: now,
      );
      expect(summary.currentStreak, 2);
      // 最长：8/4-8/5 两连 + 8/1-8/2 两连
      expect(summary.longestStreak, 2);
    });

    test('近 7 / 30 天完成率', () async {
      final habit = HabitGoal(
        uuid: 'h1',
        name: 't',
        sourceType: HabitSourceType.quantityCheckIn,
      );
      final rule = HabitGoalRuleRevision(
        uuid: 'r1',
        habitUuid: 'h1',
        effectiveFromDate: '2026-07-01',
        periodType: HabitPeriodType.daily,
        targetValue: 100,
      );
      final now = DateTime(2026, 8, 5, 14, 0);
      final days = [
        for (int i = 0; i < 10; i++)
          _day(DateTime(2026, 8, 5).subtract(Duration(days: 10 - i)),
              met: i.isEven),
      ];

      final summary = HabitStreakService.summarizeFromDays(
        habit: habit,
        days: days,
        rule: rule,
        now: now,
      );
      // 已结束天数：10 天（不含今天进行中），其中偶数下标达标 5 天。
      expect(summary.rate30, closeTo(5 / 10, 1e-9));
      expect(summary.plannedCount, 10);
      expect(summary.completedCount, 5);
      expect(summary.overdueCount, 5);
    });

    test('每周习惯按周计算连续', () async {
      final habit = HabitGoal(
        uuid: 'h1',
        name: 't',
        sourceType: HabitSourceType.pomodoroTag,
        sourceIds: const ['tag-1'],
      );
      final rule = HabitGoalRuleRevision(
        uuid: 'r1',
        habitUuid: 'h1',
        effectiveFromDate: '2026-07-01',
        periodType: HabitPeriodType.weekly,
        targetValue: 150 * 60,
      );
      final now = DateTime(2026, 8, 12, 14, 0); // 周三
      final days = [
        // 第 32 周（8/3-8/9）达标
        _day(DateTime(2026, 8, 3), met: true),
        _day(DateTime(2026, 8, 4), met: true),
        // 第 33 周（8/10-8/16）进行中
        _day(DateTime(2026, 8, 10), met: false, finished: false),
        _day(DateTime(2026, 8, 11), met: false, finished: false),
        _day(DateTime(2026, 8, 12), met: false, finished: false),
      ];

      final summary = HabitStreakService.summarizeFromDays(
        habit: habit,
        days: days,
        rule: rule,
        now: now,
      );
      expect(summary.currentStreak, 1);
    });

    test('每周时长型习惯统计平均周期时长', () async {
      final habit = HabitGoal(
        uuid: 'h1',
        name: 't',
        sourceType: HabitSourceType.pomodoroTag,
        sourceIds: const ['tag-1'],
      );
      final rule = HabitGoalRuleRevision(
        uuid: 'r1',
        habitUuid: 'h1',
        effectiveFromDate: '2026-07-01',
        periodType: HabitPeriodType.weekly,
        targetValue: 150 * 60,
      );
      final summary = HabitStreakService.summarizeFromDays(
        habit: habit,
        days: [
          _day(
            DateTime(2026, 8, 3),
            met: true,
            hasRecord: true,
            currentValue: 120 * 60,
          ),
          _day(
            DateTime(2026, 8, 10),
            met: true,
            hasRecord: true,
            currentValue: 180 * 60,
          ),
        ],
        rule: rule,
        now: DateTime(2026, 8, 20, 14, 0),
      );

      expect(summary.averageDuration, 150 * 60);
    });

    test('时间点型平均起床时间与准时率', () async {
      final habit = HabitGoal(
        uuid: 'h1',
        name: 't',
        sourceType: HabitSourceType.timeCheckIn,
      );
      final rule = HabitGoalRuleRevision(
        uuid: 'r1',
        habitUuid: 'h1',
        effectiveFromDate: '2026-07-01',
        periodType: HabitPeriodType.daily,
        targetValue: 1,
        targetTimeMinute: 7 * 60 + 30,
        timeComparison: HabitTimeComparison.before,
      );
      final now = DateTime(2026, 8, 5, 14, 0);
      final days = [
        _day(DateTime(2026, 8, 3),
            met: true, hasRecord: true, firstAt: DateTime(2026, 8, 3, 7, 10)),
        _day(DateTime(2026, 8, 4),
            met: false, hasRecord: true, firstAt: DateTime(2026, 8, 4, 8, 5)),
      ];

      final summary = HabitStreakService.summarizeFromDays(
        habit: habit,
        days: days,
        rule: rule,
        now: now,
      );
      expect(summary.averageTimeMinute,
          closeTo((7 * 60 + 10 + 8 * 60 + 5) / 2, 1e-9));
      expect(summary.onTimeRate, 0.5);
    });

    test('早睡跨午夜平均时间保持在凌晨附近', () async {
      final habit = HabitGoal(
        uuid: 'sleep',
        name: '早睡',
        sourceType: HabitSourceType.timeCheckIn,
      );
      final rule = HabitGoalRuleRevision(
        uuid: 'sleep-rule',
        habitUuid: 'sleep',
        effectiveFromDate: '2026-07-01',
        periodType: HabitPeriodType.daily,
        targetTimeMinute: 30,
        timeComparison: HabitTimeComparison.before,
        dayBoundaryMinute: 240,
      );
      final days = [
        _day(
          DateTime(2026, 8, 3),
          met: true,
          hasRecord: true,
          firstAt: DateTime(2026, 8, 3, 23, 50),
        ),
        _day(
          DateTime(2026, 8, 4),
          met: true,
          hasRecord: true,
          firstAt: DateTime(2026, 8, 4, 0, 10),
        ),
      ];

      final summary = HabitStreakService.summarizeFromDays(
        habit: habit,
        days: days,
        rule: rule,
        now: DateTime(2026, 8, 5, 14, 0),
      );

      expect(summary.averageTimeMinute, closeTo(0, 1e-9));
    });
  });
}

HabitDayProgress _day(
  DateTime date, {
  bool planned = true,
  bool met = false,
  bool finished = true,
  bool hasRecord = false,
  DateTime? firstAt,
  double? currentValue,
}) {
  final progress = HabitProgress(
    period: date,
    currentValue: currentValue ?? (met ? 100 : (hasRecord ? 50 : 0)),
    targetValue: 100,
    completionRatio: met ? 1 : 0,
    hasRecord: hasRecord,
    goalMet: met,
    isPlanned: planned,
    isFinished: finished,
    firstRecordAt: firstAt,
    lastRecordAt: firstAt,
  );
  return HabitDayProgress(
    habit: HabitGoal(uuid: 'h1', name: 't'),
    logicalDate: date,
    status: progress.dayStatus,
    progress: progress,
  );
}

List<HabitDayProgress> _days(List<HabitDayProgress> days) => days;
