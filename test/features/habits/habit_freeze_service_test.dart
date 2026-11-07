import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:countdown_todo/features/habits/models/habit_checkin.dart';
import 'package:countdown_todo/features/habits/models/habit_goal.dart';
import 'package:countdown_todo/features/habits/models/habit_goal_rule.dart';
import 'package:countdown_todo/features/habits/repositories/habit_repository.dart';
import 'package:countdown_todo/features/habits/services/habit_freeze_service.dart';

import '../../support/plan_availability_fixture.dart';

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

    test('当天已完成打卡达标时不可使用免扣卡', () async {
      final goal = HabitGoal(
        uuid: 'habit-test-9',
        name: '喝水',
        sourceType: HabitSourceType.quantityCheckIn,
      );
      final rule = HabitGoalRuleRevision(
        uuid: 'rule-test-9',
        habitUuid: goal.uuid,
        effectiveFromDate: '2026-08-01',
        periodType: HabitPeriodType.daily,
        targetValue: 2000,
      );

      await HabitFreezeService.setAvailableCards(goal.uuid, 1);

      final testDate = DateTime(2026, 8, 5);
      final checkIns = [
        HabitCheckIn(
          habitUuid: goal.uuid,
          ruleRevisionUuid: rule.uuid,
          occurredAt: testDate.millisecondsSinceEpoch,
          logicalDate: '2026-08-05',
          value: 2000,
          source: HabitCheckInSource.manual,
        ),
      ];

      final validation = await HabitFreezeService.canApplyFreeze(
        goal: goal,
        rule: rule,
        logicalDate: testDate,
        checkIns: checkIns,
        now: DateTime(2026, 8, 5, 20, 0),
      );

      expect(validation.canApply, isFalse);
      expect(validation.reason, contains('已完成打卡达标'));
    });

    test('未来日期不可使用免扣卡', () async {
      final goal = HabitGoal(
        uuid: 'habit-test-10',
        name: '早起',
        sourceType: HabitSourceType.quantityCheckIn,
      );
      final rule = HabitGoalRuleRevision(
        uuid: 'rule-test-10',
        habitUuid: goal.uuid,
        effectiveFromDate: '2026-08-01',
        periodType: HabitPeriodType.daily,
        targetValue: 1,
      );

      await HabitFreezeService.setAvailableCards(goal.uuid, 1);

      final now = DateTime(2026, 8, 5, 10, 0);
      final tomorrow = DateTime(2026, 8, 6);

      final validation = await HabitFreezeService.canApplyFreeze(
        goal: goal,
        rule: rule,
        logicalDate: tomorrow,
        checkIns: const [],
        now: now,
      );

      expect(validation.canApply, isFalse);
      expect(validation.reason, contains('未来日期'));
    });

    test('记录、读取与清除免扣卡撤销标记', () async {
      const habitUuid = 'habit-test-revoked-1';
      const dayKey = '2026-11-06';
      const otherDayKey = '2026-11-05';
      const otherHabitUuid = 'habit-test-revoked-2';

      expect(
        await HabitFreezeService.isFreezeRevoked(habitUuid, dayKey),
        isFalse,
      );

      await HabitFreezeService.markFreezeRevoked(habitUuid, dayKey);

      expect(
        await HabitFreezeService.isFreezeRevoked(habitUuid, dayKey),
        isTrue,
      );
      // 其他日期或习惯不受影响
      expect(
        await HabitFreezeService.isFreezeRevoked(habitUuid, otherDayKey),
        isFalse,
      );
      expect(
        await HabitFreezeService.isFreezeRevoked(otherHabitUuid, dayKey),
        isFalse,
      );

      await HabitFreezeService.clearFreezeRevoked(habitUuid, dayKey);
      expect(
        await HabitFreezeService.isFreezeRevoked(habitUuid, dayKey),
        isFalse,
      );
    });
  });

  group('HabitFreezeService 自动守护与手动撤销防循环守护集成测试', () {
    late PlanAvailabilityFixture fixture;

    setUp(() async {
      fixture = PlanAvailabilityFixture();
      await fixture.initialize();
    });

    tearDown(() => fixture.dispose());

    test('手动撤销免扣卡后，autoProtectMissedDays 不会再次自动免扣该日期', () async {
      final now = DateTime(2026, 11, 7, 10, 0);
      final yesterday = DateTime(2026, 11, 6);
      const yesterdayKey = '2026-11-06';

      final rule = HabitGoalRuleRevision(
        habitUuid: 'habit-auto-test-1',
        periodType: HabitPeriodType.daily,
        targetValue: 1,
        effectiveFromDate: '2026-11-01',
      );
      final goal = await HabitRepository.createGoal(
        name: '阅读英语',
        icon: '📖',
        sourceType: HabitSourceType.quantityCheckIn,
        sourceIds: const [],
        rule: rule,
        username: PlanAvailabilityFixture.username,
      );

      // 确保持有 1 张免扣卡
      await HabitFreezeService.setAvailableCards(goal.uuid, 1);
      expect(await HabitFreezeService.getAvailableCards(goal.uuid), 1);

      // 1. 模拟初次进入今日界面：昨天未打卡，触发自动免扣
      final protected1 = await HabitFreezeService.autoProtectMissedDays(
        goals: [goal],
        username: PlanAvailabilityFixture.username,
        now: now,
      );
      expect(protected1, contains('阅读英语'));

      // 扣除 1 张卡，余 0 张
      expect(await HabitFreezeService.getAvailableCards(goal.uuid), 0);

      // 检查昨天已有 freeze check-in
      final checkIns = await HabitRepository.getCheckIns(habitUuid: goal.uuid);
      final freezeCheckIn = checkIns.firstWhere(
        (c) =>
            !c.isDeleted &&
            c.logicalDate == yesterdayKey &&
            c.source == HabitCheckInSource.freeze,
      );
      expect(freezeCheckIn, isNotNull);

      // 2. 模拟用户去日历里手动取消免扣卡
      final revoked = await HabitFreezeService.revokeFreeze(
        goal: goal,
        freezeCheckIn: freezeCheckIn,
      );
      expect(revoked, isTrue);

      // 免扣卡退还，恢复为 1 张
      expect(await HabitFreezeService.getAvailableCards(goal.uuid), 1);
      // 撤销标记已写入
      expect(
        await HabitFreezeService.isFreezeRevoked(goal.uuid, yesterdayKey),
        isTrue,
      );

      // 3. 模拟用户回到今日界面，触发 autoProtectMissedDays
      final protected2 = await HabitFreezeService.autoProtectMissedDays(
        goals: [goal],
        username: PlanAvailabilityFixture.username,
        now: now,
      );

      // 关键断言：不再重复免扣！
      expect(protected2, isEmpty);
      // 免扣卡依然保留在手中，没有被偷偷扣掉
      expect(await HabitFreezeService.getAvailableCards(goal.uuid), 1);

      // 4. 若用户后续主动在日历或详情手动补用免扣卡，撤销标记自动解除
      final manuallyApplied = await HabitFreezeService.applyFreeze(
        goal: goal,
        rule: rule,
        logicalDate: yesterday,
        now: now,
      );
      expect(manuallyApplied, isTrue);
      expect(
        await HabitFreezeService.isFreezeRevoked(goal.uuid, yesterdayKey),
        isFalse,
      );
    });
  });
}
