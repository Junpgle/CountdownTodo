import 'package:countdown_todo/features/habits/models/habit_goal_rule.dart';
import 'package:countdown_todo/features/habits/services/habit_rule_resolver.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('HabitRuleResolver.logicalDateFor', () {
    test('日期分界 00:00 时当天内时间不变', () {
      final date = DateTime(2026, 7, 31, 23, 30);
      final logical = HabitRuleResolver.logicalDateFor(date, 0);
      expect(logical, DateTime(2026, 7, 31));
    });

    test('早睡习惯日期分界 04:00 的三种情况', () {
      final boundary = 4 * 60;
      expect(
        HabitRuleResolver.logicalDateFor(DateTime(2026, 7, 31, 23, 30), boundary),
        DateTime(2026, 7, 31),
      );
      expect(
        HabitRuleResolver.logicalDateFor(DateTime(2026, 8, 1, 0, 40), boundary),
        DateTime(2026, 7, 31),
      );
      expect(
        HabitRuleResolver.logicalDateFor(DateTime(2026, 8, 1, 4, 20), boundary),
        DateTime(2026, 8, 1),
      );
    });

    test('dayKey 与 parseDayKey 互逆', () {
      final date = DateTime(2026, 8, 1);
      final key = HabitRuleResolver.dayKey(date);
      expect(key, '2026-08-01');
      expect(HabitRuleResolver.parseDayKey(key), date);
      expect(HabitRuleResolver.parseDayKey('bad'), isNull);
    });
  });

  group('HabitRuleResolver.effectiveRule', () {
    HabitGoalRuleRevision rule(String uuid, String from, [String? to]) =>
        HabitGoalRuleRevision(
          uuid: uuid,
          habitUuid: 'h1',
          effectiveFromDate: from,
          effectiveToDate: to,
        );

    test('选择生效且最近的规则', () {
      final rules = [
        rule('a', '2026-07-01', '2026-07-31'),
        rule('b', '2026-08-01'),
      ];
      expect(
        HabitRuleResolver.effectiveRule(rules, DateTime(2026, 7, 15))!.uuid,
        'a',
      );
      expect(
        HabitRuleResolver.effectiveRule(rules, DateTime(2026, 8, 15))!.uuid,
        'b',
      );
    });

    test('已删除规则不参与选择', () {
      final rules = [
        rule('a', '2026-07-01')..isDeleted = true,
        rule('b', '2026-07-10'),
      ];
      expect(
        HabitRuleResolver.effectiveRule(rules, DateTime(2026, 7, 15))!.uuid,
        'b',
      );
    });

    test('无规则时返回 null', () {
      expect(HabitRuleResolver.effectiveRule([], DateTime(2026, 7, 15)), isNull);
    });
  });

  group('HabitRuleResolver.isPlannedDay', () {
    final habitUuid = 'h1';

    test('每天类型每天都是计划日', () {
      final rule = HabitGoalRuleRevision(
        habitUuid: habitUuid,
        periodType: HabitPeriodType.daily,
      );
      expect(HabitRuleResolver.isPlannedDay(rule, DateTime(2026, 7, 31)), true);
      expect(HabitRuleResolver.isPlannedDay(rule, DateTime(2026, 8, 1)), true);
    });

    test('指定星期（周一、周三、周五）', () {
      final rule = HabitGoalRuleRevision(
        habitUuid: habitUuid,
        periodType: HabitPeriodType.weekdays,
        weekdaysMask: (1 << 0) | (1 << 2) | (1 << 4), // 周一三五
      );
      // 2026-07-31 是周五
      expect(HabitRuleResolver.isPlannedDay(rule, DateTime(2026, 7, 31)), true);
      // 2026-08-01 是周六
      expect(HabitRuleResolver.isPlannedDay(rule, DateTime(2026, 8, 1)), false);
      // 2026-08-03 是周一
      expect(HabitRuleResolver.isPlannedDay(rule, DateTime(2026, 8, 3)), true);
    });

    test('自定义周期：每 2 天', () {
      final rule = HabitGoalRuleRevision(
        habitUuid: habitUuid,
        periodType: HabitPeriodType.custom,
        customIntervalDays: 2,
        effectiveFromDate: '2026-08-01',
      );
      expect(HabitRuleResolver.isPlannedDay(rule, DateTime(2026, 8, 1)), true);
      expect(HabitRuleResolver.isPlannedDay(rule, DateTime(2026, 8, 2)), false);
      expect(HabitRuleResolver.isPlannedDay(rule, DateTime(2026, 8, 3)), true);
      expect(HabitRuleResolver.isPlannedDay(rule, DateTime(2026, 8, 4)), false);
    });

    test('自定义周期：锚点为空时视为每天', () {
      final rule = HabitGoalRuleRevision(
        habitUuid: habitUuid,
        periodType: HabitPeriodType.custom,
        customIntervalDays: 3,
      );
      expect(HabitRuleResolver.isPlannedDay(rule, DateTime(2026, 8, 1)), true);
    });
  });

  group('HabitRuleResolver 周期计算', () {
    HabitGoalRuleRevision rule(HabitPeriodType type) =>
        HabitGoalRuleRevision(
          habitUuid: 'h1',
          periodType: type,
        );

    test('每日周期', () {
      expect(
        HabitRuleResolver.periodStart(rule(HabitPeriodType.daily), DateTime(2026, 8, 5, 12)),
        DateTime(2026, 8, 5),
      );
      expect(
        HabitRuleResolver.periodEndExclusive(
            rule(HabitPeriodType.daily), DateTime(2026, 8, 5)),
        DateTime(2026, 8, 6),
      );
    });

    test('每周周期从周一开始', () {
      // 2026-08-05 是周三
      expect(
        HabitRuleResolver.periodStart(rule(HabitPeriodType.weekly), DateTime(2026, 8, 5)),
        DateTime(2026, 8, 3),
      );
      expect(
        HabitRuleResolver.periodEndExclusive(
            rule(HabitPeriodType.weekly), DateTime(2026, 8, 5)),
        DateTime(2026, 8, 10),
      );
      expect(
        HabitRuleResolver.nextPeriodStart(
            rule(HabitPeriodType.weekly), DateTime(2026, 8, 5)),
        DateTime(2026, 8, 10),
      );
    });

    test('每月周期从 1 号开始', () {
      expect(
        HabitRuleResolver.periodStart(rule(HabitPeriodType.monthly), DateTime(2026, 8, 20)),
        DateTime(2026, 8, 1),
      );
      expect(
        HabitRuleResolver.periodEndExclusive(
            rule(HabitPeriodType.monthly), DateTime(2026, 8, 20)),
        DateTime(2026, 9, 1),
      );
    });

    test('周期结束判断', () {
      final daily = rule(HabitPeriodType.daily);
      expect(
        HabitRuleResolver.isPeriodFinished(
            daily, DateTime(2026, 8, 5), DateTime(2026, 8, 5, 23, 59)),
        false,
      );
      expect(
        HabitRuleResolver.isPeriodFinished(
            daily, DateTime(2026, 8, 5), DateTime(2026, 8, 6, 0, 0, 1)),
        true,
      );

      final weekly = rule(HabitPeriodType.weekly);
      expect(
        HabitRuleResolver.isPeriodFinished(
            weekly, DateTime(2026, 8, 5), DateTime(2026, 8, 9, 23, 59)),
        false,
      );
      expect(
        HabitRuleResolver.isPeriodFinished(
            weekly, DateTime(2026, 8, 5), DateTime(2026, 8, 10, 0, 0, 1)),
        true,
      );
    });
  });

  group('HabitRuleResolver.isTimePointMet', () {
    test('before 型：早于目标达标', () {
      final rule = HabitGoalRuleRevision(
        habitUuid: 'h1',
        targetTimeMinute: 7 * 60 + 30,
        timeComparison: HabitTimeComparison.before,
      );
      expect(
        HabitRuleResolver.isTimePointMet(rule, DateTime(2026, 8, 1, 7, 18)),
        true,
      );
      expect(
        HabitRuleResolver.isTimePointMet(rule, DateTime(2026, 8, 1, 8, 5)),
        false,
      );
      expect(
        HabitRuleResolver.isTimePointMet(rule, DateTime(2026, 8, 1, 7, 30)),
        true,
      );
    });

    test('before 型：允许范围 15 分钟', () {
      final rule = HabitGoalRuleRevision(
        habitUuid: 'h1',
        targetTimeMinute: 23 * 60 + 30,
        timeComparison: HabitTimeComparison.before,
        timeToleranceMinutes: 15,
      );
      expect(
        HabitRuleResolver.isTimePointMet(rule, DateTime(2026, 8, 1, 23, 40)),
        true,
      );
      expect(
        HabitRuleResolver.isTimePointMet(rule, DateTime(2026, 8, 1, 23, 50)),
        false,
      );
    });

    test('after 型：晚于目标达标，允许范围提前', () {
      final rule = HabitGoalRuleRevision(
        habitUuid: 'h1',
        targetTimeMinute: 18 * 60,
        timeComparison: HabitTimeComparison.after,
        timeToleranceMinutes: 10,
      );
      expect(
        HabitRuleResolver.isTimePointMet(rule, DateTime(2026, 8, 1, 17, 55)),
        true,
      );
      expect(
        HabitRuleResolver.isTimePointMet(rule, DateTime(2026, 8, 1, 17, 40)),
        false,
      );
      expect(
        HabitRuleResolver.isTimePointMet(rule, DateTime(2026, 8, 1, 19, 0)),
        true,
      );
    });
  });
}
