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

  testWidgets('周视图在 06:50 存在日程时，保留 06:00 完整小时不压缩为过窄狭缝', (tester) async {
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

    await fixture.fixed(
      'fs_early',
      currentWeekMonday.add(const Duration(hours: 6, minutes: 50)),
      currentWeekMonday.add(const Duration(hours: 7, minutes: 40)),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: WeeklyCourseScreen(username: PlanAvailabilityFixture.username),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 600)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // 06:00 保留完整小时，06:00 与 07:00 均可见且具有正常的垂直间隔
    expect(find.text('06:00'), findsOneWidget);
    expect(find.text('07:00'), findsOneWidget);
    expect(find.text('08:00'), findsOneWidget);

    final pos06 = tester.getTopLeft(find.text('06:00'));
    final pos07 = tester.getTopLeft(find.text('07:00'));
    expect(pos07.dy - pos06.dy, greaterThan(25.0));
  });

  testWidgets('周视图在 07:00 存在最早日程时，整小时折叠 06:00，顶部清晰显示 07:00', (tester) async {
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

    await fixture.fixed(
      'fs_0700',
      currentWeekMonday.add(const Duration(hours: 7)),
      currentWeekMonday.add(const Duration(hours: 7, minutes: 40)),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: WeeklyCourseScreen(username: PlanAvailabilityFixture.username),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 600)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // 06:00~07:00 空闲折叠，06:00 隐藏，07:00 成为顶部刻度
    expect(find.text('06:00'), findsNothing);
    expect(find.text('07:00'), findsOneWidget);
    expect(find.text('08:00'), findsOneWidget);

    final pos07 = tester.getTopLeft(find.text('07:00'));
    final pos08 = tester.getTopLeft(find.text('08:00'));
    expect(pos08.dy - pos07.dy, greaterThan(25.0));
  });

  testWidgets('周视图在 08:00 之后才有日程时，整小时折叠 06:00 与 07:00', (tester) async {
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

    await fixture.course(
      'course_0800',
      currentWeekMonday,
      800,
      940,
      semester: 'test-semester',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: WeeklyCourseScreen(username: PlanAvailabilityFixture.username),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 600)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // 06:00 与 07:00 均被折叠，08:00 为顶部第一个可见小时刻度
    expect(find.text('06:00'), findsNothing);
    expect(find.text('07:00'), findsNothing);
    expect(find.text('08:00'), findsOneWidget);
  });
}
