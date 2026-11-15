import '../../support/plan_availability_fixture.dart';

import 'package:countdown_todo/features/habits/models/habit_goal.dart';
import 'package:countdown_todo/features/habits/models/habit_goal_rule.dart';
import 'package:countdown_todo/features/habits/repositories/habit_repository.dart';
import 'package:countdown_todo/features/habits/screens/habit_analysis_tab.dart';
import 'package:countdown_todo/features/habits/screens/habit_calendar_tab.dart';
import 'package:countdown_todo/features/habits/screens/habit_center_screen.dart';
import 'package:countdown_todo/features/habits/screens/habit_today_tab.dart';
import 'package:countdown_todo/services/feature_tip_service.dart';
import 'package:countdown_todo/widgets/floating_bottom_bar.dart';
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

    testWidgets('习惯中心日历视图滚动到底部时不会被新建习惯悬浮按钮遮挡', (tester) async {
      tester.view.physicalSize = const Size(400, 760);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await FeatureTipService.markTipShown('coach_habit_center');

      for (var i = 1; i <= 5; i++) {
        await HabitRepository.createGoal(
          name: '测试习惯$i',
          icon: '✅',
          sourceType: HabitSourceType.quantityCheckIn,
          sourceIds: const [],
          rule: HabitGoalRuleRevision(
            habitUuid: 'h$i',
            periodType: HabitPeriodType.daily,
            targetValue: 1,
            effectiveFromDate: '2026-11-01',
          ),
          username: PlanAvailabilityFixture.username,
        );
      }

      await tester.pumpWidget(
        const MaterialApp(
          home: HabitCenterScreen(username: PlanAvailabilityFixture.username),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('日历').first);
      await tester.pumpAndSettle();

      final calendarList = find.descendant(
        of: find.byType(HabitCalendarTab),
        matching: find.byType(ListView),
      );
      expect(calendarList, findsOneWidget);

      await tester.drag(calendarList, const Offset(0, -1200));
      await tester.pumpAndSettle();

      final fabRect = tester.getRect(find.text('新建习惯'));
      final lastHabitRect = tester.getRect(find.text('测试习惯5').last);
      expect(lastHabitRect.bottom, lessThan(fabRect.top));
    });

    testWidgets('习惯中心今日/分析视图滚动到底部不被遮挡，且顶部具备渐隐区域', (tester) async {
      tester.view.physicalSize = const Size(400, 760);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await FeatureTipService.markTipShown('coach_habit_center');

      for (var i = 1; i <= 6; i++) {
        await HabitRepository.createGoal(
          name: '习惯条目$i',
          icon: '✅',
          sourceType: HabitSourceType.quantityCheckIn,
          sourceIds: const [],
          rule: HabitGoalRuleRevision(
            habitUuid: 't$i',
            periodType: HabitPeriodType.daily,
            targetValue: 1,
            effectiveFromDate: '2026-11-01',
          ),
          username: PlanAvailabilityFixture.username,
        );
      }

      await tester.pumpWidget(
        const MaterialApp(
          home: HabitCenterScreen(username: PlanAvailabilityFixture.username),
        ),
      );
      await tester.pumpAndSettle();

      // 1. 顶部渐隐组件启用了默认 tailExtent，且 TabBarView 从顶部 0 起点延伸以进入渐隐带。
      final fadeWidget = tester.widget<FloatingGlassTopBarContentFade>(
        find.byType(FloatingGlassTopBarContentFade),
      );
      expect(fadeWidget.tailExtent, floatingGlassTopBarDefaultFadeTail);
      expect(tester.getTopLeft(find.byType(TabBarView)).dy, 0.0);

      // 2. 今日视图滚动到底部不被「新建习惯」悬浮按钮遮挡。
      final todayScroll = find.descendant(
        of: find.byType(HabitTodayTab),
        matching: find.byType(CustomScrollView),
      );
      await tester.drag(todayScroll, const Offset(0, -1600));
      await tester.pumpAndSettle();

      final fabRectToday = tester.getRect(find.text('新建习惯'));
      final lastTodayRect = tester.getRect(find.text('习惯条目6').last);
      expect(lastTodayRect.bottom, lessThan(fabRectToday.top));

      // 3. 分析视图滚动到底部不被「新建习惯」悬浮按钮遮挡。
      await tester.tap(find.text('分析').first);
      await tester.pumpAndSettle();

      final analysisList = find.descendant(
        of: find.byType(HabitAnalysisTab),
        matching: find.byType(ListView),
      );
      await tester.drag(analysisList, const Offset(0, -2000));
      await tester.pumpAndSettle();

      final fabRectAnalysis = tester.getRect(find.text('新建习惯'));
      final lastAnalysisRect = tester.getRect(find.text('习惯条目6').last);
      expect(lastAnalysisRect.bottom, lessThan(fabRectAnalysis.top));
    });
  });
}
