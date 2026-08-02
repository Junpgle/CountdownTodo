import 'package:countdown_todo/features/habits/models/habit_checkin.dart';
import 'package:countdown_todo/features/habits/models/habit_goal.dart';
import 'package:countdown_todo/features/habits/models/habit_goal_rule.dart';
import 'package:countdown_todo/features/habits/models/habit_progress.dart';
import 'package:countdown_todo/features/habits/services/habit_progress_calculator.dart';
import 'package:countdown_todo/models.dart';
import 'package:countdown_todo/services/pomodoro_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026, 8, 5, 14, 0); // 周三 14:00

  HabitGoal goal(HabitSourceType type, List<String> sourceIds) => HabitGoal(
        uuid: 'goal-1',
        name: '测试习惯',
        sourceType: type,
        sourceIds: sourceIds,
      );

  HabitGoalRuleRevision dailyRule({double target = 1}) => HabitGoalRuleRevision(
        uuid: 'rule-1',
        habitUuid: 'goal-1',
        effectiveFromDate: '2026-07-01',
        periodType: HabitPeriodType.daily,
        targetValue: target,
      );

  String dayKey(DateTime d) => '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  HabitCheckIn checkIn(
    DateTime localTime,
    double value, {
    String habitUuid = 'goal-1',
  }) {
    final logicalDay = DateTime(localTime.year, localTime.month, localTime.day);
    return HabitCheckIn(
      habitUuid: habitUuid,
      ruleRevisionUuid: 'rule-1',
      occurredAt: localTime.toUtc().millisecondsSinceEpoch,
      logicalDate: dayKey(logicalDay),
      timezoneOffsetMinutes: DateTime.now().timeZoneOffset.inMinutes,
      value: value,
    );
  }

  group('数量型习惯', () {
    test('当日多次打卡正确求和，达标后 goalMet 为 true', () async {
      final habit = goal(HabitSourceType.quantityCheckIn, []);
      final rule = dailyRule(target: 2000);
      final results = await HabitProgressCalculator.computeRange(
        habit: habit,
        rules: [rule],
        from: DateTime(2026, 8, 5),
        to: DateTime(2026, 8, 5),
        now: now,
        checkIns: [
          checkIn(DateTime(2026, 8, 5, 8, 30), 250),
          checkIn(DateTime(2026, 8, 5, 10, 45), 300),
          checkIn(DateTime(2026, 8, 5, 13, 20), 500),
        ],
      );
      final progress = results.first.progress;
      expect(progress.currentValue, 1050);
      expect(progress.hasRecord, true);
      expect(progress.goalMet, false);
      expect(progress.isFinished, false);
      expect(progress.dayStatus, HabitDayStatus.inProgress);
      expect(progress.recordCount, 3);
      expect(progress.checkIns!.length, 3);
    });

    test('当天结束仍未达标为 missed', () async {
      final habit = goal(HabitSourceType.quantityCheckIn, []);
      final rule = dailyRule(target: 2000);
      final results = await HabitProgressCalculator.computeRange(
        habit: habit,
        rules: [rule],
        from: DateTime(2026, 8, 4),
        to: DateTime(2026, 8, 4),
        now: now,
        checkIns: [checkIn(DateTime(2026, 8, 4, 9, 0), 1000)],
      );
      expect(results.first.progress.dayStatus, HabitDayStatus.missed);
      expect(results.first.progress.goalMet, false);
    });

    test('已达标的历史日期为 met', () async {
      final habit = goal(HabitSourceType.quantityCheckIn, []);
      final rule = dailyRule(target: 2000);
      final results = await HabitProgressCalculator.computeRange(
        habit: habit,
        rules: [rule],
        from: DateTime(2026, 8, 3),
        to: DateTime(2026, 8, 3),
        now: now,
        checkIns: [
          checkIn(DateTime(2026, 8, 3, 9, 0), 2000),
        ],
      );
      expect(results.first.progress.goalMet, true);
      expect(results.first.progress.dayStatus, HabitDayStatus.met);
    });
  });

  group('时间点型习惯', () {
    test('最早一次打卡决定达标与否', () async {
      final habit = goal(HabitSourceType.timeCheckIn, []);
      final rule = HabitGoalRuleRevision(
        uuid: 'rule-1',
        habitUuid: 'goal-1',
        effectiveFromDate: '2026-07-01',
        periodType: HabitPeriodType.daily,
        targetValue: 1,
        targetTimeMinute: 7 * 60 + 30,
        timeComparison: HabitTimeComparison.before,
      );
      final results = await HabitProgressCalculator.computeRange(
        habit: habit,
        rules: [rule],
        from: DateTime(2026, 8, 5),
        to: DateTime(2026, 8, 5),
        now: now,
        checkIns: [
          checkIn(DateTime(2026, 8, 5, 7, 18), 0),
          checkIn(DateTime(2026, 8, 5, 9, 0), 0),
        ],
      );
      final progress = results.first.progress;
      expect(progress.goalMet, true);
      expect(progress.onTime, true);
      expect(progress.firstRecordAt!.hour, 7);
      expect(progress.dayStatus, HabitDayStatus.met);
    });

    test('打卡但未准时不会达标', () async {
      final habit = goal(HabitSourceType.timeCheckIn, []);
      final rule = HabitGoalRuleRevision(
        uuid: 'rule-1',
        habitUuid: 'goal-1',
        effectiveFromDate: '2026-07-01',
        periodType: HabitPeriodType.daily,
        targetValue: 1,
        targetTimeMinute: 7 * 60 + 30,
        timeComparison: HabitTimeComparison.before,
      );
      final results = await HabitProgressCalculator.computeRange(
        habit: habit,
        rules: [rule],
        from: DateTime(2026, 8, 5),
        to: DateTime(2026, 8, 5),
        now: now,
        checkIns: [checkIn(DateTime(2026, 8, 5, 8, 5), 0)],
      );
      final progress = results.first.progress;
      expect(progress.goalMet, false);
      expect(progress.onTime, false);
      expect(progress.hasRecord, true);
      expect(progress.dayStatus, HabitDayStatus.inProgress);
    });
  });

  group('完成型习惯', () {
    TodoItem todo(
            {required String id, required DateTime day, bool done = false}) =>
        TodoItem(
          id: id,
          title: '每天整理桌面',
          createdDate:
              DateTime(day.year, day.month, day.day).millisecondsSinceEpoch,
          isDone: done,
          recurrenceSeriesId: 'series-1',
        );

    test('对应日期实例完成则达标', () async {
      final habit = goal(HabitSourceType.recurringTodo, ['series-1']);
      final rule = dailyRule();
      final results = await HabitProgressCalculator.computeRange(
        habit: habit,
        rules: [rule],
        from: DateTime(2026, 8, 5),
        to: DateTime(2026, 8, 5),
        now: now,
        todos: [
          todo(id: 't1', day: DateTime(2026, 8, 5), done: true),
        ],
      );
      expect(results.first.progress.goalMet, true);
      expect(results.first.progress.dayStatus, HabitDayStatus.met);
    });

    test('未完成且已过期为 missed，今天为 inProgress', () async {
      final habit = goal(HabitSourceType.recurringTodo, ['series-1']);
      final rule = dailyRule();
      final results = await HabitProgressCalculator.computeRange(
        habit: habit,
        rules: [rule],
        from: DateTime(2026, 8, 4),
        to: DateTime(2026, 8, 5),
        now: now,
        todos: [
          todo(id: 't4', day: DateTime(2026, 8, 4)),
          todo(id: 't5', day: DateTime(2026, 8, 5)),
        ],
      );
      expect(results[0].progress.dayStatus, HabitDayStatus.missed);
      expect(results[1].progress.dayStatus, HabitDayStatus.inProgress);
    });

    test('非计划日（周末除外）不影响状态', () async {
      final habit = goal(HabitSourceType.recurringTodo, ['series-1']);
      final rule = HabitGoalRuleRevision(
        uuid: 'rule-1',
        habitUuid: 'goal-1',
        effectiveFromDate: '2026-07-01',
        periodType: HabitPeriodType.weekdays,
        weekdaysMask: 31, // 周一至周五
      );
      // 2026-08-01 是周六
      final results = await HabitProgressCalculator.computeRange(
        habit: habit,
        rules: [rule],
        from: DateTime(2026, 8, 1),
        to: DateTime(2026, 8, 1),
        now: now,
        todos: const [],
      );
      expect(results.first.progress.dayStatus, HabitDayStatus.notPlanned);
    });
  });

  group('时长型习惯', () {
    PomodoroRecord record({
      required String uuid,
      required DateTime start,
      int effective = 30 * 60,
    }) =>
        PomodoroRecord(
          uuid: uuid,
          startTime: start.millisecondsSinceEpoch,
          plannedDuration: effective,
          actualDuration: effective,
          status: PomodoroRecordStatus.completed,
          tagUuids: const ['tag-1'],
        );

    test('每天累计有效时长，暂停时间不计入', () async {
      final habit = goal(HabitSourceType.pomodoroTag, ['tag-1']);
      final rule = HabitGoalRuleRevision(
        uuid: 'rule-1',
        habitUuid: 'goal-1',
        effectiveFromDate: '2026-07-01',
        periodType: HabitPeriodType.daily,
        targetValue: 30 * 60,
      );
      final results = await HabitProgressCalculator.computeRange(
        habit: habit,
        rules: [rule],
        from: DateTime(2026, 8, 5),
        to: DateTime(2026, 8, 5),
        now: now,
        records: [
          record(
              uuid: 'r1',
              start: DateTime(2026, 8, 5, 9, 0),
              effective: 20 * 60),
          record(
              uuid: 'r2',
              start: DateTime(2026, 8, 5, 10, 0),
              effective: 10 * 60),
        ],
      );
      final progress = results.first.progress;
      expect(progress.currentValue, 30 * 60);
      expect(progress.goalMet, true);
    });

    test('被中断的专注不计入', () async {
      final habit = goal(HabitSourceType.pomodoroTag, ['tag-1']);
      final rule = HabitGoalRuleRevision(
        uuid: 'rule-1',
        habitUuid: 'goal-1',
        effectiveFromDate: '2026-07-01',
        periodType: HabitPeriodType.daily,
        targetValue: 30 * 60,
      );
      final results = await HabitProgressCalculator.computeRange(
        habit: habit,
        rules: [rule],
        from: DateTime(2026, 8, 5),
        to: DateTime(2026, 8, 5),
        now: now,
        records: [
          PomodoroRecord(
            uuid: 'r1',
            startTime: DateTime(2026, 8, 5, 9, 0).millisecondsSinceEpoch,
            plannedDuration: 20 * 60,
            actualDuration: 5 * 60,
            status: PomodoroRecordStatus.interrupted,
            tagUuids: const ['tag-1'],
          ),
        ],
      );
      expect(results.first.progress.currentValue, 0);
      expect(results.first.progress.goalMet, false);
    });

    test('每周累计目标按周聚合', () async {
      final habit = goal(HabitSourceType.pomodoroTag, ['tag-1']);
      final rule = HabitGoalRuleRevision(
        uuid: 'rule-1',
        habitUuid: 'goal-1',
        effectiveFromDate: '2026-07-01',
        periodType: HabitPeriodType.weekly,
        targetValue: 150 * 60,
      );
      // 2026-08-05 所在周：周一 2026-08-03 至周日 2026-08-09
      final results = await HabitProgressCalculator.computeRange(
        habit: habit,
        rules: [rule],
        from: DateTime(2026, 8, 3),
        to: DateTime(2026, 8, 9),
        now: now,
        records: [
          record(
              uuid: 'r1',
              start: DateTime(2026, 8, 3, 9, 0),
              effective: 80 * 60),
          record(
              uuid: 'r2',
              start: DateTime(2026, 8, 5, 10, 0),
              effective: 70 * 60),
          record(
              uuid: 'r3',
              start: DateTime(2026, 8, 10, 9, 0),
              effective: 60 * 60),
        ],
      );
      for (final day in results) {
        expect(day.progress.currentValue, 150 * 60);
        expect(day.progress.goalMet, true);
        expect(day.progress.dayStatus, HabitDayStatus.met);
      }
    });

    test('periodLevel：每月习惯只返回周期起始日条目', () async {
      final habit = goal(HabitSourceType.quantityCheckIn, []);
      final rule = HabitGoalRuleRevision(
        uuid: 'rule-1',
        habitUuid: 'goal-1',
        effectiveFromDate: '2021-01-01',
        periodType: HabitPeriodType.monthly,
        targetValue: 30,
      );
      final from = DateTime(2021, 1, 1);
      final to = DateTime(2026, 8, 5);
      final dayCount = to.difference(from).inDays + 1;

      final dayLevel = await HabitProgressCalculator.computeRange(
        habit: habit,
        rules: [rule],
        from: from,
        to: to,
        now: now,
        checkIns: [checkIn(DateTime(2026, 7, 15, 9, 0), 30)],
      );
      expect(dayLevel.length, dayCount);

      final periodLevel = await HabitProgressCalculator.computeRange(
        habit: habit,
        rules: [rule],
        from: from,
        to: to,
        now: now,
        checkIns: [checkIn(DateTime(2026, 7, 15, 9, 0), 30)],
        periodLevel: true,
      );
      // 仅每个月 1 号一个条目：2021-01 ~ 2026-08 共 68 个月。
      expect(periodLevel.length, 68);
      // 周期级条目仍携带周期进度（8 月当期未结束不计达标）。
      expect(periodLevel.first.logicalDate, DateTime(2021, 1, 1));
      expect(
        periodLevel
            .lastWhere(
                (d) => d.logicalDate.year == 2026 && d.logicalDate.month == 7)
            .progress
            .goalMet,
        true,
      );
      final aug = periodLevel.lastWhere(
          (d) => d.logicalDate.year == 2026 && d.logicalDate.month == 8);
      expect(aug.progress.isFinished, false);
      expect(aug.progress.goalMet, false);
    });

    test('多标签绑定累计正确', () async {
      final habit = goal(HabitSourceType.pomodoroTag, ['tag-1', 'tag-2']);
      final rule = HabitGoalRuleRevision(
        uuid: 'rule-1',
        habitUuid: 'goal-1',
        effectiveFromDate: '2026-07-01',
        periodType: HabitPeriodType.daily,
        targetValue: 60 * 60,
      );
      final results = await HabitProgressCalculator.computeRange(
        habit: habit,
        rules: [rule],
        from: DateTime(2026, 8, 5),
        to: DateTime(2026, 8, 5),
        now: now,
        records: [
          PomodoroRecord(
            uuid: 'r1',
            startTime: DateTime(2026, 8, 5, 9, 0).millisecondsSinceEpoch,
            plannedDuration: 30 * 60,
            actualDuration: 30 * 60,
            status: PomodoroRecordStatus.completed,
            tagUuids: const ['tag-1'],
          ),
          PomodoroRecord(
            uuid: 'r2',
            startTime: DateTime(2026, 8, 5, 10, 0).millisecondsSinceEpoch,
            plannedDuration: 30 * 60,
            actualDuration: 30 * 60,
            status: PomodoroRecordStatus.completed,
            tagUuids: const ['tag-2'],
          ),
        ],
      );
      expect(results.first.progress.currentValue, 60 * 60);
      expect(results.first.progress.goalMet, true);
    });
  });
}
