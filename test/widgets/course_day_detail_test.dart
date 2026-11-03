import 'package:countdown_todo/models.dart';
import 'package:countdown_todo/screens/course_screens.dart';
import 'package:countdown_todo/storage_service.dart';
import 'package:countdown_todo/utils/page_transitions.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/plan_availability_fixture.dart';

void main() {
  late PlanAvailabilityFixture fixture;

  setUp(() async {
    fixture = PlanAvailabilityFixture();
    await fixture.initialize();
    debugDefaultTargetPlatformOverride = null;
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool('tip_shown_course_screen_guide', true);
  });

  tearDown(() => fixture.dispose());

  testWidgets('双周标题仍显示同一学期的周次范围', (tester) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final semesterStart = today.subtract(
      Duration(days: today.weekday - 1 + 28),
    );
    await StorageService.saveSemesters([
      SemesterInfo(
        id: 'biweek-label-test',
        name: '测试学期',
        startDate: semesterStart,
        isCurrent: true,
      ),
    ]);

    await tester.pumpWidget(
      MaterialApp(
        home: WeeklyCourseScreen(username: PlanAvailabilityFixture.username),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 500)),
    );
    await tester.pump();
    await tester.tap(find.byTooltip('切换视图模式'));
    await tester.pumpAndSettle();

    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Text &&
            RegExp(r'^测试学期 第\d+-\d+周$').hasMatch(widget.data ?? ''),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('周视图规划卡片通过共享容器动画打开详情', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final monday = today.subtract(Duration(days: today.weekday - 1));
    await StorageService.saveSemesters([
      SemesterInfo(
        id: 'week-plan-detail-test',
        name: '测试学期',
        startDate: monday,
        isCurrent: true,
      ),
    ]);
    final start = DateTime(now.year, now.month, now.day, 10);
    await fixture.block(
      TodoPlanBlock(
        id: 'week-plan-detail',
        todoId: 'todo-target',
        titleSnapshot: '周视图规划详情',
        startTime: start.millisecondsSinceEpoch,
        endTime: start.add(const Duration(minutes: 30)).millisecondsSinceEpoch,
        plannedMinutes: 30,
      ),
    );
    expect(
      await StorageService.getPlanBlocks(PlanAvailabilityFixture.username),
      hasLength(1),
    );

    final routeObserver = _RouteObserver();
    await tester.pumpWidget(
      MaterialApp(
        navigatorObservers: [routeObserver],
        home: WeeklyCourseScreen(username: PlanAvailabilityFixture.username),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(seconds: 1)),
    );
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(milliseconds: 700));

    final planCard = find.text('周视图规划详情');
    expect(planCard, findsOneWidget);
    await tester.tap(planCard);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));

    final route = routeObserver.pushedRoutes.last;
    expect(route, isA<ContainerTransformRoute>());
    final detailPage = (route as ContainerTransformRoute).page;
    expect(detailPage, isA<PlanBlockDetailScreen>());
    expect(
      (detailPage as PlanBlockDetailScreen).block.titleSnapshot,
      '周视图规划详情',
    );

    Navigator.of(tester.element(find.byType(WeeklyCourseScreen))).pop();
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('周视图规划详情'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('隐藏跨天待办时月详情仍展示单日全天待办', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final today = DateTime.now();
    final dayStart = DateTime(today.year, today.month, today.day);
    await fixture.todo(
      'single-day-all-day',
      '单日全天待办',
      legacyStart: dayStart,
      due: dayStart.add(const Duration(hours: 23, minutes: 59)),
      allDay: true,
    );
    await fixture.todo(
      'cross-day',
      '跨天待办',
      legacyStart: dayStart.add(const Duration(hours: 22)),
      due: dayStart.add(const Duration(days: 1, hours: 1)),
    );
    await fixture.db.insert('time_logs', {
      'uuid': 'ended-at-midnight',
      'title': '前一日午夜结束日志',
      'start_time': dayStart
          .subtract(const Duration(minutes: 30))
          .millisecondsSinceEpoch,
      'end_time': dayStart.millisecondsSinceEpoch,
      'device_id': 'fixture',
      'team_uuid': '',
      'created_at': 1,
      'updated_at': 1,
    });

    await tester.pumpWidget(
      MaterialApp(
        home: WeeklyCourseScreen(username: PlanAvailabilityFixture.username),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 500)),
    );
    await tester.pump();
    await tester.tap(find.byTooltip('切换视图模式'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('切换视图模式'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('筛选显示内容'));
    await tester.pumpAndSettle();
    final hideCrossDay = find.widgetWithText(MenuItemButton, '隐藏跨天待办');
    expect(hideCrossDay, findsOneWidget);
    await tester.tap(hideCrossDay);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('筛选显示内容'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('${today.day}').first, warnIfMissed: false);
    await tester.pumpAndSettle();

    final detailSheet = find.byType(BottomSheet);
    expect(detailSheet, findsOneWidget);
    expect(
      find.descendant(of: detailSheet, matching: find.text('单日全天待办')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: detailSheet, matching: find.text('跨天待办')),
      findsNothing,
    );
    expect(
      find.descendant(of: detailSheet, matching: find.text('前一日午夜结束日志')),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('周详情包含在当天最后一秒开始的待办', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final today = DateTime.now();
    final dayStart = DateTime(today.year, today.month, today.day);
    await fixture.todo(
      'day-detail-trigger',
      '当天详情入口',
      legacyStart: dayStart,
      due: dayStart.add(const Duration(hours: 23, minutes: 59)),
      allDay: true,
    );
    await fixture.todo(
      'late-cross-day',
      '最后一秒开始的跨天待办',
      legacyStart: DateTime(
        dayStart.year,
        dayStart.month,
        dayStart.day,
        23,
        59,
        59,
        500,
      ),
      due: DateTime(dayStart.year, dayStart.month, dayStart.day + 1, 1),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: WeeklyCourseScreen(username: PlanAvailabilityFixture.username),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 500)),
    );
    await tester.pump();
    for (var i = 0; i < 2; i++) {
      await tester.tap(find.byTooltip('切换视图模式'));
      await tester.pumpAndSettle();
    }
    await tester.tap(find.byTooltip('切换视图模式'));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.text('2项全天待办'));
    await tester.pump(const Duration(milliseconds: 500));

    final detailSheet = find.byType(BottomSheet);
    expect(
      find.descendant(of: detailSheet, matching: find.text('最后一秒开始的跨天待办')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('宽屏今日事项侧栏包含当天最后一秒的记录', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 844);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final today = DateTime.now();
    final dayStart = DateTime(today.year, today.month, today.day);
    await fixture.todo(
      'late-cross-day-sidebar',
      '侧栏最后一秒开始的待办',
      legacyStart: DateTime(
        dayStart.year,
        dayStart.month,
        dayStart.day,
        23,
        59,
        59,
        500,
      ),
      due: DateTime(dayStart.year, dayStart.month, dayStart.day + 1, 1),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: WeeklyCourseScreen(username: PlanAvailabilityFixture.username),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 500)),
    );
    await tester.pump();
    for (var i = 0; i < 2; i++) {
      await tester.tap(find.byTooltip('切换视图模式'));
      await tester.pumpAndSettle();
    }
    await tester.tap(find.byTooltip('切换视图模式'));
    await tester.pump(const Duration(milliseconds: 500));

    expect(
      find.ancestor(
        of: find.text('侧栏最后一秒开始的待办'),
        matching: find.byType(InkWell),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('周视图卡片采用左上对齐且精简时长与起止时间文案', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final monday = today.subtract(Duration(days: today.weekday - 1));
    await StorageService.saveSemesters([
      SemesterInfo(
        id: 'week-card-compact-test',
        name: '测试学期',
        startDate: monday,
        isCurrent: true,
      ),
    ]);

    final planStart = DateTime(today.year, today.month, today.day, 10);
    await fixture.block(
      TodoPlanBlock(
        id: 'compact-plan',
        todoId: 'todo-target',
        titleSnapshot: '精简规划块',
        startTime: planStart.millisecondsSinceEpoch,
        endTime: planStart
            .add(const Duration(minutes: 45))
            .millisecondsSinceEpoch,
        plannedMinutes: 45,
      ),
    );

    final logStart = DateTime(today.year, today.month, today.day, 14);
    await fixture.db.insert('time_logs', {
      'uuid': 'compact-log',
      'title': 'Coding',
      'start_time': logStart.millisecondsSinceEpoch,
      'end_time': logStart
          .add(const Duration(minutes: 45))
          .millisecondsSinceEpoch,
      'device_id': 'fixture',
      'team_uuid': '',
      'created_at': 1,
      'updated_at': 1,
    });

    await tester.pumpWidget(
      MaterialApp(
        home: WeeklyCourseScreen(username: PlanAvailabilityFixture.username),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 600)),
    );
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(milliseconds: 700));

    final planTitle = tester.widget<Text>(find.text('精简规划块'));
    expect(planTitle.textAlign, TextAlign.left);
    expect(find.text('45min'), findsNothing);

    final logTitle = tester.widget<Text>(find.text('Coding'));
    expect(logTitle.textAlign, TextAlign.left);
    expect(find.text('14:00-14:45'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('背景层课程与前景层待办重叠时不互相挤压列宽，且多条重叠碎待办在窄列下折叠为+N角标并可点击展开详情', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final monday = today.subtract(Duration(days: today.weekday - 1));
    await StorageService.saveSemesters([
      SemesterInfo(
        id: 'week-layer-agg-test',
        name: '测试学期',
        startDate: monday,
        isCurrent: true,
      ),
    ]);

    // 1. 在 10:00-11:40 放置一门课程（背景层）和一条顶部重叠短待办（前景层）
    await fixture.course(
      'bg-course-1',
      today,
      1000,
      1140,
      semester: 'week-layer-agg-test',
    );
    await fixture.todo(
      'fg-single-todo',
      '单条重叠待办',
      legacyStart: DateTime(today.year, today.month, today.day, 10, 0),
      due: DateTime(today.year, today.month, today.day, 10, 25),
    );

    // 2. 在 15:00-15:40 放置 3 条互相重叠的短待办（窄屏下 3 列宽度 < 24px，触发 +2 叠牌聚合）
    await fixture.todo(
      'fg-overlap-1',
      '碎片待办一',
      legacyStart: DateTime(today.year, today.month, today.day, 15, 0),
      due: DateTime(today.year, today.month, today.day, 15, 30),
    );
    await fixture.todo(
      'fg-overlap-2',
      '碎片待办二',
      legacyStart: DateTime(today.year, today.month, today.day, 15, 5),
      due: DateTime(today.year, today.month, today.day, 15, 35),
    );
    await fixture.todo(
      'fg-overlap-3',
      '碎片待办三',
      legacyStart: DateTime(today.year, today.month, today.day, 15, 10),
      due: DateTime(today.year, today.month, today.day, 15, 40),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: WeeklyCourseScreen(username: PlanAvailabilityFixture.username),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 600)),
    );
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(milliseconds: 700));

    // 背景层课程与前景层单条待办均保持完整单日列宽，未因重叠被对半切碎
    final courseRect = tester.getRect(
      find.ancestor(
        of: find.text('合成课程'),
        matching: find.byType(Positioned),
      ).first,
    );
    final singleTodoRect = tester.getRect(
      find.ancestor(
        of: find.text('单条重叠待办'),
        matching: find.byType(Positioned),
      ).first,
    );
    expect(courseRect.width, closeTo(singleTodoRect.width, 0.5));
    expect(courseRect.width, greaterThan(40.0));
    expect(singleTodoRect.width, greaterThan(40.0));

    // 背景层课程标题自动下移避让顶部重叠的前景短待办，避免标题叠字
    final courseTitleRect = tester.getRect(find.text('合成课程'));
    final todoTitleRect = tester.getRect(find.text('单条重叠待办'));
    expect(courseTitleRect.top, greaterThanOrEqualTo(todoTitleRect.bottom));

    // 15:00 的 3 条重叠待办被聚合为叠牌卡片，仅显示首条标题与 +2 角标
    expect(find.text('碎片待办一'), findsOneWidget);
    expect(find.text('碎片待办二'), findsNothing);
    expect(find.text('碎片待办三'), findsNothing);
    expect(find.text('+2'), findsOneWidget);

    // 点击 +2 叠牌卡片弹出底部详情面板，展示全部 3 条待办
    await tester.tap(find.text('+2'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    final detailSheet = find.byType(BottomSheet);
    expect(detailSheet, findsOneWidget);
    expect(
      find.descendant(of: detailSheet, matching: find.text('碎片待办一')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: detailSheet, matching: find.text('碎片待办二')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: detailSheet, matching: find.text('碎片待办三')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('周视图支持日程视角与复盘视角切换，并对已完成事项降噪', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final monday = today.subtract(Duration(days: today.weekday - 1));
    await StorageService.saveSemesters([
      SemesterInfo(
        id: 'perspective-test',
        name: '视角学期',
        startDate: monday,
        isCurrent: true,
      ),
    ]);

    await fixture.course(
      'course-review-map',
      today,
      800,
      935,
      semester: 'perspective-test',
    );

    final planStart = DateTime(today.year, today.month, today.day, 10, 0);
    await fixture.block(
      TodoPlanBlock(
        id: 'plan-done',
        todoId: 'todo-for-plan',
        titleSnapshot: '行测已完成规划',
        startTime: planStart.millisecondsSinceEpoch,
        endTime: planStart
            .add(const Duration(minutes: 90))
            .millisecondsSinceEpoch,
        plannedMinutes: 90,
        status: TodoPlanStatus.finished,
      ),
    );

    await fixture.todo(
      'todo-done-1',
      '已完成日内待办',
      done: true,
      legacyStart: DateTime(today.year, today.month, today.day, 14, 0),
      due: DateTime(today.year, today.month, today.day, 15, 0),
    );
    await fixture.todo(
      'todo-pending-1',
      '待处理日内待办',
      done: false,
      legacyStart: DateTime(today.year, today.month, today.day, 16, 0),
      due: DateTime(today.year, today.month, today.day, 17, 0),
    );

    final logStart = DateTime(today.year, today.month, today.day, 19, 0);
    await fixture.db.insert('time_logs', {
      'uuid': 'log-review-1',
      'title': '申论复盘记录',
      'start_time': logStart.millisecondsSinceEpoch,
      'end_time': logStart
          .add(const Duration(minutes: 90))
          .millisecondsSinceEpoch,
      'device_id': 'fixture',
      'team_uuid': '',
      'created_at': 1,
      'updated_at': 1,
    });

    await tester.pumpWidget(
      MaterialApp(
        home: WeeklyCourseScreen(username: PlanAvailabilityFixture.username),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 600)),
    );
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(milliseconds: 700));

    Container cardContainerForText(String label) {
      return tester.widget<Container>(
        find
            .ancestor(of: find.text(label), matching: find.byType(Container))
            .first,
      );
    }

    // 1. 验证已完成事项降噪：已完成待办与 100% 完成规划块透明度显著低于未完成待办
    final doneTodoBox =
        cardContainerForText('已完成日内待办').decoration! as BoxDecoration;
    final pendingTodoBox =
        cardContainerForText('待处理日内待办').decoration! as BoxDecoration;
    final finishedPlanBox =
        cardContainerForText('行测已完成规划').decoration! as BoxDecoration;
    expect(doneTodoBox.color!.a, lessThanOrEqualTo(0.30));
    expect(finishedPlanBox.color!.a, lessThanOrEqualTo(0.30));
    expect(pendingTodoBox.color!.a, greaterThan(0.75));

    final normalCourseColor =
        (cardContainerForText('合成课程').decoration! as BoxDecoration).color!;

    // 2. 打开筛选菜单，切换到「日程视角」
    await tester.tap(find.byTooltip('筛选显示内容'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('日程视角'), findsOneWidget);
    expect(find.text('复盘视角'), findsOneWidget);
    expect(find.text('全部视角'), findsOneWidget);

    await tester.tap(find.text('日程视角'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // 日程视角：课程和规划块可见，时间日志和待办隐藏
    expect(find.text('合成课程'), findsOneWidget);
    expect(find.text('行测已完成规划'), findsOneWidget);
    expect(find.text('申论复盘记录'), findsNothing);
    expect(find.text('待处理日内待办'), findsNothing);

    // 3. 切换到「复盘视角」：时间日志可见，规划块隐藏，课程退化为浅灰底图
    await tester.tap(find.text('复盘视角'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('申论复盘记录'), findsOneWidget);
    expect(find.text('行测已完成规划'), findsNothing);
    expect(find.text('合成课程'), findsOneWidget);

    final reviewCourseColor =
        (cardContainerForText('合成课程').decoration! as BoxDecoration).color!;
    expect(reviewCourseColor, isNot(equals(normalCourseColor)));
    expect(tester.takeException(), isNull);
  });

  testWidgets('滑动切换有全天事项与无全天事项的周次时不触发重复 GlobalKey，且新周数据立即渲染', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final monday = today.subtract(Duration(days: today.weekday - 1));
    final nextWeekDay = today.add(const Duration(days: 7));
    await StorageService.saveSemesters([
      SemesterInfo(
        id: 'swipe-globalkey-test',
        name: '滑动学期',
        startDate: monday,
        isCurrent: true,
      ),
    ]);

    // 第 1 周：含全天待办（显示顶部全天栏）+ 日内待办 + 规划块
    await fixture.todo(
      'w1-allday',
      '首周全天待办',
      allDay: true,
      legacyStart: DateTime(today.year, today.month, today.day, 0, 0),
      due: DateTime(today.year, today.month, today.day, 23, 59),
    );
    await fixture.todo(
      'w1-intraday',
      '首周日内待办',
      legacyStart: DateTime(today.year, today.month, today.day, 10, 0),
      due: DateTime(today.year, today.month, today.day, 11, 0),
    );

    // 第 2 周：无全天待办（顶部全天栏收起，触发网格高度约束变化）+ 规划块 + 日内待办
    final w2PlanStart = DateTime(
      nextWeekDay.year,
      nextWeekDay.month,
      nextWeekDay.day,
      14,
      0,
    );
    await fixture.block(
      TodoPlanBlock(
        id: 'w2-plan',
        todoId: 'w2-todo-ref',
        titleSnapshot: '下周规划块',
        startTime: w2PlanStart.millisecondsSinceEpoch,
        endTime: w2PlanStart
            .add(const Duration(minutes: 90))
            .millisecondsSinceEpoch,
        plannedMinutes: 90,
      ),
    );
    await fixture.todo(
      'w2-intraday',
      '下周日内待办',
      legacyStart: DateTime(
        nextWeekDay.year,
        nextWeekDay.month,
        nextWeekDay.day,
        16,
        0,
      ),
      due: DateTime(
        nextWeekDay.year,
        nextWeekDay.month,
        nextWeekDay.day,
        17,
        0,
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: WeeklyCourseScreen(username: PlanAvailabilityFixture.username),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 600)),
    );
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(milliseconds: 700));

    expect(find.text('首周全天待办'), findsOneWidget);
    expect(find.text('首周日内待办'), findsOneWidget);

    // 向左滑动切换到第 2 周（此时 AnimatedSwitcher 同时持有第 1 周与第 2 周子树，且顶部全天栏高度变化）
    await tester.fling(
      find.byType(WeeklyCourseScreen),
      const Offset(-280, 0),
      1200,
    );
    await tester.pump();
    expect(tester.takeException(), isNull);

    await tester.pump(const Duration(milliseconds: 200));
    expect(tester.takeException(), isNull);

    // 动画完成后无需额外点击屏幕，第 2 周数据已完整显示
    await tester.pump(const Duration(milliseconds: 500));
    expect(tester.takeException(), isNull);
    expect(find.text('下周规划块'), findsOneWidget);
    expect(find.text('下周日内待办'), findsOneWidget);
  });

  testWidgets('周视图长课程与长固定日程卡片根据可用高度动态扩展标题与地点最大行数', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final monday = today.subtract(Duration(days: today.weekday - 1));
    await StorageService.saveSemesters([
      SemesterInfo(
        id: 'card-maxlines-test',
        name: '测试学期',
        startDate: monday,
        isCurrent: true,
      ),
    ]);
    final wednesday = monday.add(const Duration(days: 2));
    final wedStr =
        '${wednesday.year}-${wednesday.month.toString().padLeft(2, '0')}-${wednesday.day.toString().padLeft(2, '0')}';
    final monStr =
        '${monday.year}-${monday.month.toString().padLeft(2, '0')}-${monday.day.toString().padLeft(2, '0')}';
    await fixture.db.insert('courses', {
      'uuid': 'course-long-title',
      'course_name': '习近平新时代中国特色社会主义思想概论',
      'teacher_name': '张老师',
      'room_name': '敬亭学堂 402',
      'date': wedStr,
      'weekday': 3,
      'start_time': 800,
      'end_time': 935,
      'week_index': 1,
      'semester_id': 'card-maxlines-test',
      'created_at': 1,
      'updated_at': 1,
    });
    final fixedStart = DateTime(monday.year, monday.month, monday.day, 14, 0);
    final fixedEnd = DateTime(monday.year, monday.month, monday.day, 17, 20);
    await fixture.db.insert(
      'fixed_schedules',
      FixedScheduleItem(
        id: 'tall-fixed-schedule',
        title: '算法设计与分析实验',
        date: monStr,
        location: '计算中心 B302 实验室',
        remark: '携带实验报告',
        startTime: fixedStart.millisecondsSinceEpoch,
        endTime: fixedEnd.millisecondsSinceEpoch,
      ).toJson(),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: WeeklyCourseScreen(username: PlanAvailabilityFixture.username),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 600)),
    );
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(milliseconds: 700));

    final courseTitleText = tester.widget<Text>(
      find.text('习近平新时代中国特色社会主义思想概论'),
    );
    expect(courseTitleText.maxLines, greaterThanOrEqualTo(3));
    expect(find.text('敬亭学堂 402'), findsOneWidget);

    final fixedTitleText = tester.widget<Text>(find.text('算法设计与分析实验'));
    final fixedLocationText = tester.widget<Text>(
      find.text('计算中心 B302 实验室 · 携带实验报告'),
    );
    expect(fixedTitleText.maxLines, greaterThanOrEqualTo(3));
    expect(fixedLocationText.maxLines, greaterThanOrEqualTo(3));
    expect(find.byIcon(Icons.location_on_rounded), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('周视图番茄钟与时间日志卡片展示持续时间，固定日程展示地点与图标', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final monday = today.subtract(Duration(days: today.weekday - 1));
    await StorageService.saveSemesters([
      SemesterInfo(
        id: 'duration-location-test',
        name: '测试学期',
        startDate: monday,
        isCurrent: true,
      ),
    ]);
    final monStr =
        '${monday.year}-${monday.month.toString().padLeft(2, '0')}-${monday.day.toString().padLeft(2, '0')}';

    // 1. 固定日程（包含地点）
    final fixedStart = DateTime(monday.year, monday.month, monday.day, 10, 0);
    final fixedEnd = DateTime(monday.year, monday.month, monday.day, 11, 0);
    await fixture.db.insert(
      'fixed_schedules',
      FixedScheduleItem(
        id: 'fixed-loc-item',
        title: '教研组会',
        date: monStr,
        location: '新安学堂 317',
        startTime: fixedStart.millisecondsSinceEpoch,
        endTime: fixedEnd.millisecondsSinceEpoch,
      ).toJson(),
    );

    // 2. 番茄钟（持续 25 分钟）
    final pomStart = DateTime(monday.year, monday.month, monday.day, 14, 0);
    await fixture.db.insert('pomodoro_records', {
      'uuid': 'pom-25min',
      'todo_title': '高数刷题',
      'start_time': pomStart.millisecondsSinceEpoch,
      'end_time': pomStart.add(const Duration(minutes: 25)).millisecondsSinceEpoch,
      'planned_duration': 1500,
      'actual_duration': 1500,
      'status': 'completed',
      'tag_uuids': '[]',
      'created_at': 1,
      'updated_at': 1,
    });

    // 3. 时间日志（持续 1 小时 30 分钟）
    final logStart = DateTime(monday.year, monday.month, monday.day, 16, 0);
    await fixture.db.insert('time_logs', {
      'uuid': 'log-90min',
      'title': '毕业设计开发',
      'start_time': logStart.millisecondsSinceEpoch,
      'end_time': logStart.add(const Duration(minutes: 90)).millisecondsSinceEpoch,
      'device_id': 'fixture',
      'team_uuid': '',
      'created_at': 1,
      'updated_at': 1,
    });

    await tester.pumpWidget(
      MaterialApp(
        home: WeeklyCourseScreen(username: PlanAvailabilityFixture.username),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 600)),
    );
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(milliseconds: 700));

    // 验证固定日程展示了地点和图标
    expect(find.text('教研组会'), findsOneWidget);
    expect(find.text('新安学堂 317'), findsOneWidget);
    expect(find.byIcon(Icons.location_on_rounded), findsWidgets);

    // 验证番茄钟展示了 25分钟
    expect(find.text('高数刷题'), findsOneWidget);
    expect(find.text('25分钟'), findsOneWidget);

    // 验证时间日志展示了 1小时30分
    expect(find.text('毕业设计开发'), findsOneWidget);
    expect(find.text('1小时30分'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

class _RouteObserver extends NavigatorObserver {
  final List<Route<dynamic>> pushedRoutes = [];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushedRoutes.add(route);
  }
}
