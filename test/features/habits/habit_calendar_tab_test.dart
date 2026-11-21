import '../../support/plan_availability_fixture.dart';

import 'package:countdown_todo/features/habits/models/habit_goal.dart';
import 'package:countdown_todo/features/habits/models/habit_goal_rule.dart';
import 'package:countdown_todo/features/habits/repositories/habit_repository.dart';
import 'package:countdown_todo/features/habits/screens/habit_analysis_tab.dart';
import 'package:countdown_todo/features/habits/screens/habit_calendar_tab.dart';
import 'package:countdown_todo/features/habits/screens/habit_center_screen.dart';
import 'package:countdown_todo/features/habits/screens/habit_today_tab.dart';
import 'package:countdown_todo/features/habits/services/habit_rule_resolver.dart';
import 'package:countdown_todo/features/habits/widgets/habit_calendar_light_up_sheet.dart';
import 'package:countdown_todo/features/habits/widgets/habit_drink_picker_sheet.dart';
import 'package:countdown_todo/services/database_helper.dart';
import 'package:countdown_todo/services/feature_tip_service.dart';
import 'package:countdown_todo/services/sync_capability_service.dart';
import 'package:countdown_todo/services/sync_oplog_policy.dart';
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

    testWidgets('点击日期弹出快捷点亮面板，可连续点亮奶茶与饮料图标并在格子并排显示及取消', (tester) async {
      tester.view.physicalSize = const Size(420, 860);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final todayKey = HabitRuleResolver.dayKey(today);
      final monthStartKey = HabitRuleResolver.dayKey(
        DateTime(now.year, now.month, 1),
      );

      await HabitRepository.createGoal(
        name: '喝奶茶',
        icon: '🧋',
        sourceType: HabitSourceType.recurringTodo,
        rule: HabitGoalRuleRevision(
          habitUuid: 'milk_tea',
          periodType: HabitPeriodType.daily,
          targetValue: 1,
          effectiveFromDate: monthStartKey,
        ),
        username: PlanAvailabilityFixture.username,
      );
      await HabitRepository.createGoal(
        name: '喝饮料',
        icon: '🥤',
        sourceType: HabitSourceType.quantityCheckIn,
        rule: HabitGoalRuleRevision(
          habitUuid: 'drink',
          periodType: HabitPeriodType.daily,
          targetValue: 1,
          unit: '杯',
          effectiveFromDate: monthStartKey,
        ),
        username: PlanAvailabilityFixture.username,
      );
      await HabitRepository.createGoal(
        name: '喝咖啡',
        icon: '☕',
        sourceType: HabitSourceType.recurringTodo,
        rule: HabitGoalRuleRevision(
          habitUuid: 'coffee',
          periodType: HabitPeriodType.daily,
          targetValue: 1,
          effectiveFromDate: monthStartKey,
        ),
        username: PlanAvailabilityFixture.username,
      );

      var onChangedCalls = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HabitCalendarTab(
              username: PlanAvailabilityFixture.username,
              onChanged: () => onChangedCalls++,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final dayCell = find.byKey(ValueKey('habit_calendar_day_$todayKey'));
      expect(dayCell, findsOneWidget);

      // 1. 点击今天格子弹出快捷点亮面板
      await tester.tap(dayCell);
      await tester.pumpAndSettle();
      expect(find.byType(HabitCalendarLightUpSheet), findsOneWidget);

      // 2. 连续点亮「喝奶茶 🧋」和「喝饮料 🥤」
      await tester.tap(
        find.descendant(
          of: find.byType(HabitCalendarLightUpSheet),
          matching: find.text('喝奶茶'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(HabitCalendarLightUpSheet),
          matching: find.text('喝饮料'),
        ),
      );
      await tester.pumpAndSettle();

      // 关闭面板
      await tester.tap(find.text('完成'));
      await tester.pumpAndSettle();
      expect(onChangedCalls, 1);

      // 验证格子直接并排显示 🧋 和 🥤
      expect(
        find.descendant(of: dayCell, matching: find.text('🧋')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: dayCell, matching: find.text('🥤')),
        findsOneWidget,
      );

      // 3. 再点亮第 3 个图标「喝咖啡 ☕」，验证 3 个图标完整展示而不提前折叠为 '+1'
      await tester.tap(dayCell);
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(HabitCalendarLightUpSheet),
          matching: find.text('喝咖啡'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('完成'));
      await tester.pumpAndSettle();

      expect(
        find.descendant(of: dayCell, matching: find.text('☕')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: dayCell, matching: find.text('+1')),
        findsNothing,
      );

      // 4. 取消点亮「喝奶茶」和「喝咖啡」，只保留「喝饮料 🥤」
      await tester.tap(dayCell);
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(HabitCalendarLightUpSheet),
          matching: find.text('喝奶茶'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(HabitCalendarLightUpSheet),
          matching: find.text('喝咖啡'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('完成'));
      await tester.pumpAndSettle();

      expect(
        find.descendant(of: dayCell, matching: find.text('🧋')),
        findsNothing,
      );
      expect(
        find.descendant(of: dayCell, matching: find.text('🥤')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: dayCell, matching: find.text('+1')),
        findsNothing,
      );
    });

    testWidgets('单习惯日历视图点亮后直接显示对应图标，且支持补点规则生效日之前的日期', (tester) async {
      tester.view.physicalSize = const Size(420, 860);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final now = DateTime.now();
      final todayKey = HabitRuleResolver.dayKey(
        DateTime(now.year, now.month, now.day),
      );
      final firstOfMonthKey = HabitRuleResolver.dayKey(
        DateTime(now.year, now.month, 1),
      );

      // 习惯从今天才生效，验证仍可补点本月 1 号
      await HabitRepository.createGoal(
        name: '喝奶茶',
        icon: '🧋',
        sourceType: HabitSourceType.quantityCheckIn,
        rule: HabitGoalRuleRevision(
          habitUuid: 'milk_tea_single',
          periodType: HabitPeriodType.daily,
          targetValue: 1,
          effectiveFromDate: todayKey,
        ),
        username: PlanAvailabilityFixture.username,
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: HabitCalendarTab(username: PlanAvailabilityFixture.username),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 切换到单习惯视图
      await tester.tap(find.widgetWithText(FilterChip, '喝奶茶'));
      await tester.pumpAndSettle();

      final firstDayCell = find.byKey(
        ValueKey('habit_calendar_single_day_$firstOfMonthKey'),
      );
      expect(firstDayCell, findsOneWidget);

      await tester.tap(firstDayCell);
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(HabitCalendarLightUpSheet),
          matching: find.text('喝奶茶'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('完成'));
      await tester.pumpAndSettle();

      expect(
        find.descendant(of: firstDayCell, matching: find.text('🧋')),
        findsOneWidget,
      );
    });

    testWidgets('戒掉饮料习惯可在今日卡片与日历中手动选择喝了什么，并直接把饮品图标展示在日历上', (tester) async {
      tester.view.physicalSize = const Size(420, 860);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await FeatureTipService.markTipShown('coach_habit_center');

      final now = DateTime.now();
      final todayKey = HabitRuleResolver.dayKey(
        DateTime(now.year, now.month, now.day),
      );
      final monthStartKey = HabitRuleResolver.dayKey(
        DateTime(now.year, now.month, 1),
      );

      await HabitRepository.createGoal(
        name: '戒掉饮料',
        icon: '🚫',
        sourceType: HabitSourceType.recurringTodo,
        rule: HabitGoalRuleRevision(
          habitUuid: 'quit_drinks',
          periodType: HabitPeriodType.daily,
          targetValue: 1,
          effectiveFromDate: monthStartKey,
        ),
        username: PlanAvailabilityFixture.username,
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: HabitCenterScreen(username: PlanAvailabilityFixture.username),
        ),
      );
      await tester.pumpAndSettle();

      // 1. 在今日页的「戒掉饮料」卡片上点击「选饮品」
      expect(find.text('选饮品'), findsOneWidget);
      await tester.tap(find.text('选饮品'));
      await tester.pumpAndSettle();
      expect(find.byType(HabitDrinkPickerSheet), findsOneWidget);

      // 选择「奶茶 🧋」并完成
      await tester.tap(
        find.descendant(
          of: find.byType(HabitDrinkPickerSheet),
          matching: find.text('奶茶'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(HabitDrinkPickerSheet),
          matching: find.text('完成'),
        ),
      );
      await tester.pumpAndSettle();

      // 2. 切到「日历」标签页，验证今天格子直接展示 🧋 而不是通用 🚫
      await tester.tap(find.text('日历').first);
      await tester.pumpAndSettle();

      final overviewDayCell = find.byKey(
        ValueKey('habit_calendar_day_$todayKey'),
      );
      expect(
        find.descendant(of: overviewDayCell, matching: find.text('🧋')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: overviewDayCell, matching: find.text('🚫')),
        findsNothing,
      );

      // 3. 切到「戒掉饮料」单习惯日历，点今天格子直接弹出饮品选择面板并再选「饮料 🥤」
      await tester.tap(find.widgetWithText(FilterChip, '戒掉饮料'));
      await tester.pumpAndSettle();

      final singleDayCell = find.byKey(
        ValueKey('habit_calendar_single_day_$todayKey'),
      );
      await tester.tap(singleDayCell);
      await tester.pumpAndSettle();
      expect(find.byType(HabitDrinkPickerSheet), findsOneWidget);

      await tester.tap(
        find.descendant(
          of: find.byType(HabitDrinkPickerSheet),
          matching: find.text('饮料'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('完成'));
      await tester.pumpAndSettle();

      // 验证单习惯日历格子并排展示 🧋 和 🥤，下方明细显示可读摘要
      expect(
        find.descendant(of: singleDayCell, matching: find.text('🧋')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: singleDayCell, matching: find.text('🥤')),
        findsOneWidget,
      );
      final calendarList = find.descendant(
        of: find.byType(HabitCalendarTab),
        matching: find.byType(ListView),
      );
      await tester.drag(calendarList, const Offset(0, -400));
      await tester.pumpAndSettle();
      // 选到饮料记为破戒（打卡失败 -> 未完成）
      expect(find.text('破戒：🧋 奶茶 · 🥤 饮料'), findsOneWidget);
      expect(find.text('未完成'), findsWidgets);

      // 4. 改选「今日没喝（打卡成功）」，验证清除破戒记录并转为已完成
      await tester.drag(calendarList, const Offset(0, 400));
      await tester.pumpAndSettle();
      await tester.tap(singleDayCell);
      await tester.pumpAndSettle();
      await tester.tap(find.text('今日没喝（打卡成功）'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('完成'));
      await tester.pumpAndSettle();

      expect(
        find.descendant(of: singleDayCell, matching: find.text('🚫')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: singleDayCell, matching: find.text('🧋')),
        findsNothing,
      );
      await tester.drag(calendarList, const Offset(0, -400));
      await tester.pumpAndSettle();
      expect(find.text('没喝饮料 · 打卡成功'), findsOneWidget);
      expect(find.text('已完成'), findsWidgets);
    });

    testWidgets('支持自定义常用饮品图标、写入云同步 oplog 并在日历格子直接展示自定义图标', (tester) async {
      tester.view.physicalSize = const Size(420, 860);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final now = DateTime.now();
      final todayKey = HabitRuleResolver.dayKey(
        DateTime(now.year, now.month, now.day),
      );
      final monthStartKey = HabitRuleResolver.dayKey(
        DateTime(now.year, now.month, 1),
      );

      await HabitRepository.createGoal(
        name: '戒掉饮料',
        icon: '🚫',
        sourceType: HabitSourceType.recurringTodo,
        rule: HabitGoalRuleRevision(
          habitUuid: 'quit_drinks_custom',
          periodType: HabitPeriodType.daily,
          targetValue: 1,
          effectiveFromDate: monthStartKey,
        ),
        username: PlanAvailabilityFixture.username,
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: HabitCalendarTab(username: PlanAvailabilityFixture.username),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 切到「戒掉饮料」单习惯视图，点今天格子弹出饮品面板
      await tester.tap(find.widgetWithText(FilterChip, '戒掉饮料'));
      await tester.pumpAndSettle();
      final singleDayCell = find.byKey(
        ValueKey('habit_calendar_single_day_$todayKey'),
      );
      await tester.tap(singleDayCell);
      await tester.pumpAndSettle();

      // 点击「自定义」新增 🍋 柠檬茶
      await tester.tap(find.text('自定义'));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, '饮品名称'), '柠檬茶');
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();

      // 验证「柠檬茶」已出现在面板中，且 op_logs 已记录 habit_drink_options 待云同步
      expect(find.text('柠檬茶'), findsOneWidget);
      final db = await DatabaseHelper.instance.database;
      final oplogs = await db.query(
        'op_logs',
        where: 'target_table = ? AND is_synced = 0',
        whereArgs: ['habit_drink_options'],
      );
      expect(oplogs, isNotEmpty);

      // 验证旧服务端不支持 habit_drink_options 时不误确认 oplog，支持时正常确认
      final entry = SyncOplogEntry(
        id: 1,
        table: 'habit_drink_options',
        uuid: 'custom-1',
      );
      final legacyResolution = SyncOplogPolicy.resolveRequestSnapshot(
        requestSnapshot: [entry],
        blockingConflictUuids: const {},
        acknowledgeFixedScheduleOps: true,
        acknowledgeHabitOps: true,
        acknowledgeSleepCoachingOps: true,
        acknowledgeHabitDrinkOptionOps:
            SyncCapabilityService.supportsHabitDrinkOptions({'habits': 1}),
      );
      expect(legacyResolution.acknowledgedIds, isEmpty);
      final modernResolution = SyncOplogPolicy.resolveRequestSnapshot(
        requestSnapshot: [entry],
        blockingConflictUuids: const {},
        acknowledgeFixedScheduleOps: true,
        acknowledgeHabitOps: true,
        acknowledgeSleepCoachingOps: true,
        acknowledgeHabitDrinkOptionOps:
            SyncCapabilityService.supportsHabitDrinkOptions({
              'habits': 1,
              'habit_drink_options': 1,
            }),
      );
      expect(modernResolution.acknowledgedIds, contains(1));

      // 点选自定义饮品「柠檬茶 🍋」并完成，验证日历格子直接显示 🍋
      await tester.tap(find.text('柠檬茶'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('完成'));
      await tester.pumpAndSettle();

      expect(
        find.descendant(of: singleDayCell, matching: find.text('🍋')),
        findsOneWidget,
      );
    });

    testWidgets('宽屏桌面端打开快捷点亮面板与饮品选择面板时保持紧凑宽度与卡片尺寸，不溢出', (tester) async {
      tester.view.physicalSize = const Size(1200, 760);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final now = DateTime.now();
      final todayKey = HabitRuleResolver.dayKey(
        DateTime(now.year, now.month, now.day),
      );
      final monthStartKey = HabitRuleResolver.dayKey(
        DateTime(now.year, now.month, 1),
      );

      await HabitRepository.createGoal(
        name: '戒掉饮料',
        icon: '💧',
        sourceType: HabitSourceType.recurringTodo,
        rule: HabitGoalRuleRevision(
          habitUuid: 'quit_drinks_wide',
          periodType: HabitPeriodType.daily,
          targetValue: 1,
          effectiveFromDate: monthStartKey,
        ),
        username: PlanAvailabilityFixture.username,
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: HabitCalendarTab(username: PlanAvailabilityFixture.username),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 1. 总览日历点击今天，验证快捷点亮面板宽度 <= 520
      await tester.tap(find.byKey(ValueKey('habit_calendar_day_$todayKey')));
      await tester.pumpAndSettle();
      final lightUpSize = tester.getSize(
        find.byType(HabitCalendarLightUpSheet),
      );
      expect(lightUpSize.width, lessThanOrEqualTo(520.0));

      // 2. 点击「戒掉饮料」打开饮品选择面板，验证宽度 <= 520 且不溢出
      await tester.tap(
        find.descendant(
          of: find.byType(HabitCalendarLightUpSheet),
          matching: find.text('戒掉饮料'),
        ),
      );
      await tester.pumpAndSettle();
      final drinkSheetSize = tester.getSize(find.byType(HabitDrinkPickerSheet));
      expect(drinkSheetSize.width, lessThanOrEqualTo(520.0));
      expect(drinkSheetSize.height, lessThanOrEqualTo(760.0 * 0.85));
    });
  });
}
