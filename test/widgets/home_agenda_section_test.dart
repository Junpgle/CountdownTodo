@TestOn('vm')
library;

import 'dart:async';

import 'package:countdown_todo/models.dart';
import 'package:countdown_todo/services/api_service.dart';
import 'package:countdown_todo/services/device_calendar_read_service.dart';
import 'package:countdown_todo/services/home_agenda_repository.dart';
import 'package:countdown_todo/services/plan_review_repository.dart';
import 'package:countdown_todo/screens/course_screens.dart';
import 'package:countdown_todo/screens/plan_block_stats_screen.dart';
import 'package:countdown_todo/widgets/plan_block_today_section.dart';
import 'package:countdown_todo/screens/todo_plan_screen.dart';
import 'package:countdown_todo/widgets/plan_block_editor_sheet.dart';
import 'package:countdown_todo/storage_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/plan_availability_fixture.dart';

void main() {
  late PlanAvailabilityFixture f;
  late PlanReviewRepository plans;
  late HomeAgendaRepository repo;
  late DateTime now;
  late ValueNotifier<int> revision;
  late ValueNotifier<bool> enabled;
  var maintenance = 0, courseReads = 0, calendarReads = 0, allTaps = 0;
  bool calendarFails = false;
  Completer<List<CourseItem>>? pending;
  DateTime at(int h, [int m = 0]) => DateTime(2026, 10, 8, h, m);
  Future<void> plan(
    String id,
    int hour, {
    TodoPlanStatus status = TodoPlanStatus.planned,
  }) => f.block(
    TodoPlanBlock(
      id: id,
      todoId: 'todo-target',
      titleSnapshot: '规划$id',
      startTime: at(hour).millisecondsSinceEpoch,
      endTime: at(hour + 1).millisecondsSinceEpoch,
      plannedMinutes: 60,
      status: status,
    ),
  );
  Future<void> settle(WidgetTester t) async {
    for (var i = 0; i < 3; i++) {
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 40)),
      );
      await t.pump(const Duration(milliseconds: 500));
    }
  }

  Future<void> tap(WidgetTester t, Finder finder) async {
    await t.ensureVisible(finder);
    await t.tap(finder);
    await settle(t);
  }

  Future<void> open(
    WidgetTester t, {
    Size size = const Size(390, 844),
    double scale = 1,
    Brightness brightness = Brightness.light,
    bool provideOnTap = true,
  }) async {
    t.view.devicePixelRatio = 1;
    t.view.physicalSize = size;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    addTearDown(() async {
      await t.pumpWidget(const SizedBox.shrink());
      await t.pump();
    });
    await t.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.teal,
            brightness: brightness,
          ),
        ),
        builder: (c, child) => MediaQuery(
          data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: Scaffold(
          body: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: ListenableBuilder(
                listenable: Listenable.merge([revision, enabled]),
                builder: (c, _) => PlanBlockTodaySection(
                  username: PlanAvailabilityFixture.username,
                  unifiedAgenda: true,
                  agendaRepository: repo,
                  clock: () => now,
                  refreshTrigger: revision.value,
                  enabled: enabled.value,
                  maintain: () async {
                    maintenance++;
                  },
                  onTap: provideOnTap
                      ? () {
                          allTaps++;
                        }
                      : null,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await settle(t);
  }

  Finder key(String s) => find.byKey(ValueKey(s));
  Finder editAction(String id) => find.text('查看规划');
  setUp(() async {
    f = PlanAvailabilityFixture();
    await f.initialize();
    debugDefaultTargetPlatformOverride = null;
    await initializeDateFormatting();
    now = at(12);
    revision = ValueNotifier(0);
    enabled = ValueNotifier(true);
    maintenance = courseReads = calendarReads = allTaps = 0;
    calendarFails = false;
    pending = null;
    plans = PlanReviewRepository(databaseOverride: f.db, clock: () => now);
    repo = HomeAgendaRepository(
      plans: plans,
      courseLoader: (_) async {
        courseReads++;
        return pending?.future ?? [];
      },
      fixedLoader: (_, _) async => [],
      calendarLoader: (_) async {
        calendarReads++;
        if (calendarFails) throw StateError('故障');
        return [
          DeviceCalendarEvent(
            id: 'e',
            calendarId: 'c',
            title: '手机讲座',
            start: at(15),
            end: at(16),
            allDay: false,
            location: '会议室',
          ),
        ];
      },
    );
    ApiService.setBaseUrlOverride('http://127.0.0.1:1');
  });
  tearDown(() async {
    ApiService.clearBaseUrlOverride();
    revision.dispose();
    enabled.dispose();
    await f.dispose();
  });

  testWidgets(
    'one agenda, expandable plan and history, real editor and device detail',
    (t) async {
      await plan('current', 11);
      now = at(11, 30);
      await plan('done', 8, status: TodoPlanStatus.finished);
      await open(t);
      expect(find.text('今日安排'), findsOneWidget);
      expect(find.text('今日规划'), findsNothing);
      expect(find.text('今日日程'), findsNothing);
      expect(find.text('规划current'), findsOneWidget);
      expect(find.text('规划done'), findsNothing);
      await tap(t, key('agenda-ended'));
      expect(find.text('规划done'), findsOneWidget);
      await tap(t, key('plan-today-row-current'));
      await tap(t, editAction('current'));
      expect(
        t
            .widget<PlanBlockEditorSheet>(find.byType(PlanBlockEditorSheet))
            .block!
            .id,
        'current',
      );
      await tap(t, find.byTooltip('关闭'));
      await tap(t, find.text('手机讲座'));
      expect(find.byType(DeviceCalendarEventDetailScreen), findsOneWidget);
      expect(find.text('手机日历 · 只读'), findsOneWidget);
      expect(find.text('2026年10月8日'), findsOneWidget);
      expect(find.text('15:00'), findsOneWidget);
      expect(find.text('16:00'), findsOneWidget);
      await t.pageBack();
      await settle(t);
      expect(allTaps, 0);
      expect(await f.db.query('op_logs'), isEmpty);
    },
  );
  testWidgets(
    'collapse migrates preference, retains stats and preserves account memory',
    (t) async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(
        'plan_today_collapsed_${PlanAvailabilityFixture.username}',
        true,
      );
      await plan('next', 14);
      await open(t);
      expect(key('plan-today-row-next'), findsNothing);
      expect(find.textContaining('接下来 14:00'), findsOneWidget);
      await tap(t, find.byTooltip('规划统计'));
      expect(find.byType(PlanBlockStatsScreen), findsOneWidget);
      await t.pageBack();
      await settle(t);
      await tap(t, key('plan-today-collapse'));
      expect(key('plan-today-row-next'), findsOneWidget);
      expect(
        prefs.getBool(
          'home_agenda_collapsed_${PlanAvailabilityFixture.username}',
        ),
        isFalse,
      );
      expect(allTaps, 0);
    },
  );

  testWidgets(
    'agenda editor manual completion and undo preserve source-page flow',
    (t) async {
      await plan('missed', 9, status: TodoPlanStatus.missed);
      await open(t);
      await tap(t, key('agenda-attention'));
      await tap(t, key('plan-today-row-missed'));
      await tap(t, editAction('missed'));
      await tap(t, find.byTooltip('更多操作'));
      await tap(t, find.text('确认规划已完成'));
      await tap(t, key('plan-manual-confirm'));
      expect(find.byType(PlanBlockEditorSheet), findsNothing);
      expect(key('plan-manual-undo'), findsOneWidget);
      expect((await f.db.query('todo_plan_blocks')).single['status'], 1);
      await tap(t, key('plan-manual-undo'));
      expect((await f.db.query('todo_plan_blocks')).single['status'], 6);
      expect((await f.db.query('op_logs')).length, 2);
      expect(await f.db.query('pomodoro_records'), isEmpty);
    },
  );

  testWidgets('plan focus details retain exact plan and local date', (t) async {
    await plan('next', 14);
    await open(t);
    await tap(t, key('plan-today-row-next'));
    await tap(t, key('plan-today-focus-next'));
    final screen = t.widget<PlanReviewDetailScreen>(
      find.byType(PlanReviewDetailScreen),
    );
    expect(screen.planId, 'next');
    expect(screen.start, DateTime(2026, 10, 8));
    expect(screen.cumulative, isFalse);
    expect(allTaps, 0);
    await t.pageBack();
    await settle(t);
    expect(await f.db.query('op_logs'), isEmpty);
  });
  testWidgets('calendar failure retry is local and never repeats maintenance', (
    t,
  ) async {
    calendarFails = true;
    await plan('next', 14);
    await open(t);
    expect(find.text('手机日历读取失败'), findsOneWidget);
    expect(find.text('规划next'), findsOneWidget);
    calendarFails = false;
    final oldReads = courseReads;
    await tap(t, key('agenda-retry-calendar'));
    expect(find.text('手机讲座'), findsOneWidget);
    expect(courseReads, oldReads);
    expect(calendarReads, 2);
    expect(maintenance, 1);
    expect(await f.db.query('op_logs'), isEmpty);
  });
  testWidgets('same-day refresh retains rows without allowing old operations', (
    t,
  ) async {
    await plan('next', 14);
    await open(t);
    pending = Completer<List<CourseItem>>();
    revision.value++;
    await t.pump();
    expect(key('plan-today-row-next'), findsOneWidget);
    expect(t.widget<InkWell>(key('plan-today-row-next')).onTap, isNull);
    pending!.complete([]);
    pending = null;
    await settle(t);
    expect(t.widget<InkWell>(key('plan-today-row-next')).onTap, isNotNull);
  });
  testWidgets(
    'disabled module performs no reads or maintenance, midnight clears yesterday',
    (t) async {
      enabled.value = false;
      await plan('next', 14);
      await open(t);
      expect(courseReads, 0);
      expect(maintenance, 0);
      enabled.value = true;
      await settle(t);
      expect(courseReads, 1);
      now = DateTime(2026, 10, 9);
      await t.pump(const Duration(days: 1));
      await settle(t);
      expect(find.text('规划next'), findsNothing);
      expect(find.text('今日安排'), findsOneWidget);
    },
  );
  testWidgets('identity reset discards old rows before late read completes', (
    t,
  ) async {
    await plan('next', 14);
    await open(t);
    pending = Completer<List<CourseItem>>();
    revision.value++;
    await t.pump();
    await (await SharedPreferences.getInstance()).setInt('current_user_id', 8);
    StorageService.triggerRefresh({DataRefreshDomain.all});
    await t.pump(const Duration(milliseconds: 101));
    expect(key('plan-today-row-next'), findsNothing);
    pending!.complete([]);
    pending = null;
    await settle(t);
    expect(allTaps, 0);
  });
  for (final config in [
    (const Size(320, 700), 1.8, Brightness.dark),
    (const Size(390, 844), 1.0, Brightness.light),
    (const Size(720, 360), 1.0, Brightness.light),
    (const Size(1280, 900), 1.8, Brightness.dark),
  ]) {
    testWidgets('timeline and expanded actions fit $config', (t) async {
      await plan('next', 14);
      await plan('missed', 9, status: TodoPlanStatus.missed);
      await open(t, size: config.$1, scale: config.$2, brightness: config.$3);
      await tap(t, key('plan-today-row-next'));
      await tap(t, key('agenda-attention'));
      expect(find.text('规划missed'), findsOneWidget);
      expect(t.takeException(), isNull);
      expect(await f.db.query('op_logs'), isEmpty);
    });
  }

  testWidgets(
    'agenda-all without external onTap opens TodoPlanScreen with container transition',
    (t) async {
      await plan('next', 14);
      await open(t, provideOnTap: false);
      await tap(t, key('agenda-all'));
      expect(find.byType(TodoPlanScreen), findsOneWidget);
      await t.pageBack();
      await settle(t);
      expect(allTaps, 0);
    },
  );

  testWidgets(
    'agenda-all with external onTap forwards sourceKey for container transition',
    (t) async {
      GlobalKey? receivedKey;
      await plan('next', 14);
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PlanBlockTodaySection(
              username: PlanAvailabilityFixture.username,
              unifiedAgenda: true,
              agendaRepository: repo,
              clock: () => now,
              onTap: ([sourceKey]) {
                receivedKey = sourceKey;
                allTaps++;
              },
            ),
          ),
        ),
      );
      await settle(t);
      await tap(t, key('agenda-all'));
      expect(allTaps, 1);
      expect(receivedKey, isNotNull);
      expect(receivedKey!.currentContext, isNotNull);
    },
  );
}
