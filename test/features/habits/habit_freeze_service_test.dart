import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:countdown_todo/features/habits/models/habit_checkin.dart';
import 'package:countdown_todo/features/habits/models/habit_goal.dart';
import 'package:countdown_todo/features/habits/models/habit_goal_rule.dart';
import 'package:countdown_todo/features/habits/services/habit_freeze_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('HabitFreezeService', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('首次查询新习惯自动赠送 1 张启程保底免扣卡', () async {
      const habitUuid = 'habit-test-1';
      final cards = await HabitFreezeService.getAvailableCards(habitUuid);
      expect(cards, HabitFreezeService.kInitialGiftCards);
      expect(cards, 1);
    });

    test('设置免扣卡库存受最大持有上限 2 张约束', () async {
      const habitUuid = 'habit-test-2';
      await HabitFreezeService.setAvailableCards(habitUuid, 5);
      final cards = await HabitFreezeService.getAvailableCards(habitUuid);
      expect(cards, HabitFreezeService.kMaxFreezeCards);
      expect(cards, 2);

      await HabitFreezeService.setAvailableCards(habitUuid, -1);
      final cardsZero = await HabitFreezeService.getAvailableCards(habitUuid);
      expect(cardsZero, 0);
    });

    test('连续打卡未满 7 天不奖励免扣卡', () async {
      final goal = HabitGoal(uuid: 'habit-test-3', name: '晨跑');
      // 预置已有 0 张卡
      await HabitFreezeService.setAvailableCards(goal.uuid, 0);

      final awarded = await HabitFreezeService.checkAndAwardCards(
        habit: goal,
        currentStreak: 5,
      );
      expect(awarded, 0);

      final cards = await HabitFreezeService.getAvailableCards(goal.uuid);
      expect(cards, 0);
    });

    test('连续打卡满 7 天奖励 1 张免扣卡', () async {
      final goal = HabitGoal(uuid: 'habit-test-4', name: '背单词');
      // 预置已有 0 张卡
      await HabitFreezeService.setAvailableCards(goal.uuid, 0);

      final awarded = await HabitFreezeService.checkAndAwardCards(
        habit: goal,
        currentStreak: 7,
      );
      expect(awarded, 1);

      final cards = await HabitFreezeService.getAvailableCards(goal.uuid);
      expect(cards, 1);

      // 同一个 7 天里程碑再次调用不重复发放
      final awardedAgain = await HabitFreezeService.checkAndAwardCards(
        habit: goal,
        currentStreak: 7,
      );
      expect(awardedAgain, 0);
    });

    test('满仓 2 张卡后达到 14 天里程碑不会溢出增加', () async {
      final goal = HabitGoal(uuid: 'habit-test-5', name: '阅读');
      // 初始赠送 1 张，再设为 2 张
      await HabitFreezeService.setAvailableCards(goal.uuid, 2);

      final awarded = await HabitFreezeService.checkAndAwardCards(
        habit: goal,
        currentStreak: 14,
      );
      expect(awarded, 0);

      final cards = await HabitFreezeService.getAvailableCards(goal.uuid);
      expect(cards, 2);
    });

    test('绝不连续错过两次：前一天已免扣时，今天不可再次使用免扣卡', () async {
      final goal = HabitGoal(uuid: 'habit-test-6', name: '冥想');
      final rule = HabitGoalRuleRevision(
        uuid: 'rule-test-6',
        habitUuid: goal.uuid,
        effectiveFromDate: '2026-08-01',
        periodType: HabitPeriodType.daily,
      );

      // 拥有 2 张免扣卡
      await HabitFreezeService.setAvailableCards(goal.uuid, 2);

      final yesterday = DateTime(2026, 8, 4);
      final today = DateTime(2026, 8, 5);

      // 昨天已经有免扣打卡记录
      final checkIns = [
        HabitCheckIn(
          habitUuid: goal.uuid,
          ruleRevisionUuid: rule.uuid,
          occurredAt: yesterday.millisecondsSinceEpoch,
          logicalDate: '2026-08-04',
          source: HabitCheckInSource.freeze,
        ),
      ];

      final validation = await HabitFreezeService.canApplyFreeze(
        goal: goal,
        rule: rule,
        logicalDate: today,
        checkIns: checkIns,
      );

      expect(validation.canApply, isFalse);
      expect(validation.reason, contains('绝不连续错过两次'));
    });

    test('非计划日不可使用免扣卡', () async {
      final goal = HabitGoal(uuid: 'habit-test-7', name: '工作总结');
      final rule = HabitGoalRuleRevision(
        uuid: 'rule-test-7',
        habitUuid: goal.uuid,
        effectiveFromDate: '2026-08-01',
        periodType: HabitPeriodType.weekdays,
        weekdaysMask: 31, // 仅周一至周五 (bit 0..4)
      );

      await HabitFreezeService.setAvailableCards(goal.uuid, 1);

      // 2026-08-08 是周六（非计划日）
      final saturday = DateTime(2026, 8, 8);

      final validation = await HabitFreezeService.canApplyFreeze(
        goal: goal,
        rule: rule,
        logicalDate: saturday,
        checkIns: const [],
      );

      expect(validation.canApply, isFalse);
      expect(validation.reason, contains('不是计划打卡日'));
    });

    test('无可用免扣卡时不可使用', () async {
      final goal = HabitGoal(uuid: 'habit-test-8', name: '喝水');
      final rule = HabitGoalRuleRevision(
        uuid: 'rule-test-8',
        habitUuid: goal.uuid,
        effectiveFromDate: '2026-08-01',
        periodType: HabitPeriodType.daily,
      );

      // 消耗至 0 张
      await HabitFreezeService.setAvailableCards(goal.uuid, 0);

      final validation = await HabitFreezeService.canApplyFreeze(
        goal: goal,
        rule: rule,
        logicalDate: DateTime(2026, 8, 5),
        checkIns: const [],
      );

      expect(validation.canApply, isFalse);
      expect(validation.reason, contains('没有可用的免扣卡'));
    });
  });
}
