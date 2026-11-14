import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:countdown_todo/models.dart';
import 'package:countdown_todo/screens/course_screens.dart';
import 'package:countdown_todo/storage_service.dart';

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

  testWidgets('周视图表头中今天显示高亮容器与“今”徽章', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final currentWeekMonday = today.subtract(Duration(days: today.weekday - 1));

    await StorageService.saveSemesters([
      SemesterInfo(
        id: 'test-semester',
        name: '当前学期',
        startDate: currentWeekMonday,
        isCurrent: true,
      ),
    ]);

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        ),
        home: WeeklyCourseScreen(username: PlanAvailabilityFixture.username),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 600)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // 表头应包含今天专属的“今”药丸徽章
    expect(find.text('今'), findsOneWidget);

    // 检查表头的无障碍 Semantics 中包含“今天”
    final semanticsFinder = find.byWidgetPredicate(
      (widget) =>
          widget is Semantics &&
          widget.properties.label != null &&
          widget.properties.label!.contains('今天'),
    );
    expect(semanticsFinder, findsOneWidget);
  });

  testWidgets('周视图网格中包含贯穿当天的纵向高光背景列', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final currentWeekMonday = today.subtract(Duration(days: today.weekday - 1));

    await StorageService.saveSemesters([
      SemesterInfo(
        id: 'test-semester',
        name: '当前学期',
        startDate: currentWeekMonday,
        isCurrent: true,
      ),
    ]);

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        ),
        home: WeeklyCourseScreen(username: PlanAvailabilityFixture.username),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 600)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // 网格中存在 IgnorePointer 包裹的纵向今天高光列
    final highlightColumns = find.byWidgetPredicate((widget) {
      if (widget is Positioned && widget.top == 0 && widget.bottom == 0) {
        final child = widget.child;
        if (child is IgnorePointer && child.child is Container) {
          final container = child.child as Container;
          final decoration = container.decoration;
          return decoration is BoxDecoration && decoration.color != null;
        }
      }
      return false;
    });

    expect(highlightColumns, findsAtLeastNWidgets(1));
  });
}
