import '../../support/plan_availability_fixture.dart';

import 'package:countdown_todo/features/habits/models/habit_goal.dart';
import 'package:countdown_todo/features/habits/models/habit_goal_rule.dart';
import 'package:countdown_todo/features/habits/repositories/habit_repository.dart';
import 'package:countdown_todo/features/habits/screens/habit_calendar_tab.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('HabitCalendarTab 每一个习惯的打卡完成日历视图', () {
    late PlanAvailabilityFixture fixture;

    setUp(() async {
      fixture = PlanAvailabilityFixture();
      await fixture.initialize();
      debugDefaultTargetPlatformOverride = null;
    });

    tearDown(() => fixture.dispose());

    testWidgets('在习惯中心通过顶部筛选直接查看全部月历或切换每一个习惯专属打卡日历', (tester) async {
      tester.view.physicalSize = const Size(1200, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      // 创建两个习惯
      final rule1 = HabitGoalRuleRevision(
        habitUuid: 'h1',
        periodType: HabitPeriodType.daily,
        targetValue: 1,
        effectiveFromDate: '2026-11-01',
      );
      await HabitRepository.createGoal(
        name: '晨跑打卡',
        icon: '🏃',
        sourceType: HabitSourceType.quantityCheckIn,
        sourceIds: const [],
        rule: rule1,
        username: PlanAvailabilityFixture.username,
      );

      final rule2 = HabitGoalRuleRevision(
        habitUuid: 'h2',
        periodType: HabitPeriodType.daily,
        targetValue: 2000,
        unit: 'ml',
        effectiveFromDate: '2026-11-01',
      );
      await HabitRepository.createGoal(
        name: '每天喝水',
        icon: '💧',
        sourceType: HabitSourceType.quantityCheckIn,
        sourceIds: const [],
        rule: rule2,
        username: PlanAvailabilityFixture.username,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HabitCalendarTab(username: PlanAvailabilityFixture.username),
          ),
        ),
      );

      // 等待异步加载与计算
      await tester.pumpAndSettle();

      // 1. 验证筛选 Chip 存在
      expect(find.text('全部习惯'), findsOneWidget);
      expect(find.text('晨跑打卡'), findsWidgets);
      expect(find.text('每天喝水'), findsWidgets);

      // 2. 默认在「全部习惯」时是总览月历
      expect(find.text('全部完成'), findsOneWidget);
      expect(find.text('部分完成'), findsOneWidget);

      // 3. 点击顶部 Chip 切换到单习惯打卡日历（例如“每天喝水”）
      final waterChip = find.widgetWithText(FilterChip, '每天喝水');
      expect(waterChip, findsOneWidget);
      await tester.tap(waterChip);
      await tester.pumpAndSettle();

      // 验证单习惯大日历视图已呈现
      expect(find.text('每天喝水 · 本月打卡日历'), findsOneWidget);
      expect(find.text('已达标'), findsWidgets);
      expect(find.text('达成率'), findsOneWidget);
      expect(find.text('计划天数'), findsOneWidget);
      expect(find.text('免扣/跳过'), findsOneWidget);
      expect(find.text('查看全部'), findsOneWidget);

      // 4. 点击“查看全部”返回全部习惯日历视图
      await tester.tap(find.text('查看全部'));
      await tester.pumpAndSettle();

      expect(find.text('全部习惯'), findsOneWidget);
      expect(find.text('全部完成'), findsOneWidget);
    });
  });
}
