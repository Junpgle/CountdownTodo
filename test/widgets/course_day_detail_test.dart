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
    await tester.tap(find.text('${today.day}'), warnIfMissed: false);
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
}

class _RouteObserver extends NavigatorObserver {
  final List<Route<dynamic>> pushedRoutes = [];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushedRoutes.add(route);
  }
}
