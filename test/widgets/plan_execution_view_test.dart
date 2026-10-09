import 'dart:convert';

import 'package:countdown_todo/models.dart';
import 'package:countdown_todo/screens/course_screens.dart';
import 'package:countdown_todo/screens/todo_plan_screen.dart';
import 'package:countdown_todo/services/liquid_glass_effect_service.dart';
import 'package:countdown_todo/services/pomodoro_service.dart';
import 'package:countdown_todo/storage_service.dart';
import 'package:countdown_todo/widgets/plan_block_editor_sheet.dart';
import 'package:countdown_todo/widgets/plan_execution_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/plan_availability_fixture.dart';

void main() {
  final day = DateTime(2026, 10, 8);
  int at(int hour, [int minute = 0]) => DateTime(
    day.year,
    day.month,
    day.day,
    hour,
    minute,
  ).millisecondsSinceEpoch;
  final focus = PomodoroRecord(
    uuid: 'focus',
    todoTitle: '阅读专注',
    startTime: at(1),
    endTime: at(2),
    plannedDuration: 3600,
    actualDuration: 2400,
  );
  final log = TimeLogItem(
    id: 'log',
    title: '阅读日志',
    startTime: at(-1, 30),
    endTime: at(0, 30),
  );
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await LiquidGlassEffectService.setEnabled(false);
  });
  tearDown(() async {
    await LiquidGlassEffectService.setEnabled(false);
    GlassPerformanceMonitor.stop();
  });

  Widget summary() => PlanExecutionSummary(
    date: day,
    records: [focus],
    logs: [log],
    tags: const [],
  );

  testWidgets('当天未关联规划的专注和跨天日志可见，列表进入原生详情', (tester) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: summary())));
    expect(find.text('专注 1 条'), findsOneWidget);
    expect(find.text('时间日志 1 条'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('plan-execution-list')));
    await tester.pumpAndSettle();
    expect(find.text('专注 · 阅读专注'), findsOneWidget);
    expect(find.textContaining('有效专注 40 分钟'), findsOneWidget);
    expect(find.text('时间日志 · 阅读日志'), findsOneWidget);
    expect(find.textContaining('10-07 23:30–10-08 00:30'), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey('plan-execution-list-专注-focus')),
    );
    await tester.pumpAndSettle();
    expect(find.byType(PomodoroDetailScreen), findsOneWidget);
    Navigator.of(tester.element(find.byType(PomodoroDetailScreen))).pop();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('plan-execution-list')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('plan-execution-list-时间日志-log')),
    );
    await tester.pumpAndSettle();
    expect(find.byType(TimeLogDetailScreen), findsOneWidget);
  });

  testWidgets('时间轴截断跨午夜记录且点击只查看详情', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            height: 864,
            child: PlanExecutionTimelineLayer(
              date: day,
              entries: PlanExecutionEntry.forDay(day, [focus], [log]),
              tags: const [],
              hourHeight: 36,
            ),
          ),
        ),
      ),
    );
    final segment = find.byKey(const ValueKey('plan-execution-时间日志-log-0'));
    expect(segment, findsOneWidget);
    expect(
      find.byKey(const ValueKey('plan-execution-时间日志-log-23')),
      findsNothing,
    );
    expect(tester.getSize(segment).width, closeTo(198, 1));
    await tester.tap(segment);
    await tester.pumpAndSettle();
    expect(find.byType(TimeLogDetailScreen), findsOneWidget);
    expect(find.byType(PlanBlockEditorSheet), findsNothing);
  });

  testWidgets('真实规划页加载实际记录，取消与查看零写入，新增日志即时刷新', (tester) async {
    final now = DateTime.now();
    final entryDay = DateTime(now.year, now.month, now.day + 1);
    int hour(int h) => entryDay.add(Duration(hours: h)).millisecondsSinceEpoch;
    final fixture = PlanAvailabilityFixture();
    await tester.runAsync(() => fixture.initialize());
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('tip_shown_todo_plan_guide', true);
    await tester.runAsync(() async {
      final record = PomodoroRecord(
        uuid: 'real-focus',
        todoTitle: '真实入口专注',
        startTime: hour(1),
        endTime: hour(2),
        plannedDuration: 3600,
        actualDuration: 1200,
      );
      await fixture.db.insert('pomodoro_records', {
        ...record.toJson(),
        'tag_uuids': jsonEncode(record.tagUuids),
      });
      await StorageService.saveTimeLogs(PlanAvailabilityFixture.username, [
        TimeLogItem(
          id: 'real-log',
          title: '真实入口日志',
          startTime: hour(2),
          endTime: hour(3),
        ),
      ], sync: false);
    });
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    try {
      await tester.pumpWidget(
        MaterialApp(
          home: TodoPlanScreen(
            username: PlanAvailabilityFixture.username,
            initialDate: entryDay,
          ),
        ),
      );
      await tester.runAsync(
        () async => Future<void>.delayed(const Duration(milliseconds: 250)),
      );
      await tester.pumpAndSettle();
      expect(find.text('专注 1 条'), findsOneWidget);
      expect(find.text('时间日志 1 条'), findsOneWidget);
      final timeline = find.byType(PlanExecutionTimelineLayer);
      expect(
        find.ancestor(of: timeline, matching: find.byType(Scrollable)),
        findsNothing,
      );
      expect(
        tester.getBottomRight(find.text('23:00')).dy,
        lessThanOrEqualTo(844),
      );
      final dragGrid = find.byWidgetPredicate(
        (widget) =>
            widget is GestureDetector &&
            widget.onPanStart != null &&
            widget.onPanUpdate != null &&
            widget.onTapDown != null,
      );
      final gridRect = tester.getRect(dragGrid);
      await tester.dragFrom(
        Offset(
          gridRect.left + gridRect.width * 0.4,
          gridRect.top + gridRect.height * 0.7,
        ),
        const Offset(60, 30),
      );
      await tester.pumpAndSettle();
      expect(find.byType(PlanBlockEditorSheet), findsOneWidget);
      expect(
        tester
            .widget<PlanBlockEditorSheet>(find.byType(PlanBlockEditorSheet))
            .autoFillEstimateOnTodoChange,
        isFalse,
      );
      Navigator.of(tester.element(find.byType(PlanBlockEditorSheet))).pop();
      await tester.pumpAndSettle();
      final focusSegment = find.byKey(
        const ValueKey('plan-execution-专注-real-focus-1'),
      );
      await tester.drag(focusSegment, const Offset(40, 20));
      await tester.pumpAndSettle();
      expect(find.byType(PlanBlockEditorSheet), findsNothing);
      expect(find.byType(PomodoroDetailScreen), findsNothing);
      await tester.tap(
        find.byKey(const ValueKey('plan-execution-专注-real-focus-1')),
      );
      await tester.pumpAndSettle();
      expect(find.byType(PomodoroDetailScreen), findsOneWidget);
      expect(find.byType(PlanBlockEditorSheet), findsNothing);
      Navigator.of(tester.element(find.byType(PomodoroDetailScreen))).pop();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('plan-execution-list')));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('关闭'));
      await tester.pumpAndSettle();
      await tester.runAsync(
        () => StorageService.saveTimeLogs(PlanAvailabilityFixture.username, [
          TimeLogItem(
            id: 'new-log',
            title: '刚补录',
            startTime: hour(3),
            endTime: hour(4),
          ),
        ], sync: false),
      );
      await tester.runAsync(
        () async => Future<void>.delayed(const Duration(milliseconds: 250)),
      );
      await tester.pumpAndSettle();
      expect(find.text('时间日志 2 条'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.runAsync(() async {
        expect(await fixture.db.query('todo_plan_blocks'), isEmpty);
        expect(await fixture.db.query('op_logs'), isEmpty);
      });
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(() => fixture.dispose());
    }
  });

  for (final glass in [false, true]) {
    for (final viewport in [
      const Size(320, 640),
      const Size(720, 360),
      const Size(1280, 900),
    ]) {
      testWidgets('记录列表适配 $viewport 大字体 glass=$glass', (tester) async {
        await LiquidGlassEffectService.setEnabled(glass);
        tester.view.physicalSize = viewport;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(brightness: Brightness.dark),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(2)),
              child: child!,
            ),
            home: Scaffold(body: summary()),
          ),
        );
        await tester.tap(find.byKey(const ValueKey('plan-execution-list')));
        await tester.pumpAndSettle();
        expect(find.text('时间日志 · 阅读日志'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.tap(find.byTooltip('关闭'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  }
}
