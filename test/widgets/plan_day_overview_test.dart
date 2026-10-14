@TestOn('vm')
library;

import 'dart:async';

import 'package:countdown_todo/models.dart';
import 'package:countdown_todo/screens/plan_block_stats_screen.dart';
import 'package:countdown_todo/screens/todo_plan_screen.dart';
import 'package:countdown_todo/services/plan_drag_service.dart';
import 'package:countdown_todo/services/plan_review_repository.dart';
import 'package:countdown_todo/services/plan_todo_guard.dart';
import 'package:countdown_todo/widgets/plan_day_overview.dart';
import 'package:countdown_todo/widgets/plan_block_editor_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/plan_availability_fixture.dart';

final day = DateTime(2026, 10, 8), now = DateTime(2026, 10, 8, 13);

class _Clock extends PlanDragService {
  @override
  DateTime get now => DateTime(2026, 10, 8, 13);
}

class _Controlled extends PlanReviewRepository {
  final requests = <(DateTime, DateTime, Completer<PlanReviewOverview>)>[];
  @override
  Future<PlanReviewOverview> readOverview(
    String username,
    DateTime start,
    DateTime end,
  ) {
    final response = Completer<PlanReviewOverview>();
    requests.add((start, end, response));
    return response.future;
  }
}

class _Retry extends PlanReviewRepository {
  _Retry() : super(clock: () => now);
  int calls = 0;
  @override
  Future<PlanReviewOverview> readOverview(
    String username,
    DateTime start,
    DateTime end,
  ) {
    if (++calls == 1) return Future.error(StateError('合成概览失败'));
    return super.readOverview(username, start, end);
  }
}

Finder k(String name) => find.byKey(ValueKey(name));
Future<void> drain(WidgetTester t) async {
  for (var i = 0; i < 4; i++) {
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 40)),
    );
    await t.pump(const Duration(milliseconds: 300));
  }
}

void main() {
  late PlanAvailabilityFixture f;
  late PlanReviewRepository repo;
  late PlanTodoIdentity identity;
  PlanReviewOverview data(
    DateTime date, {
    int seconds = 80,
    DateTime? boundary,
  }) => PlanReviewOverview(
    identity: identity,
    start: date,
    end: DateTime(date.year, date.month, date.day + 1),
    plans: const {'seconds': 7200, 'ended': 2, 'done': 1},
    focus: {'seconds': seconds},
    logs: const {'seconds': 1200},
    issues: 0,
    nextBoundary: boundary ?? DateTime(2026, 10, 9),
  );
  setUp(() async {
    f = PlanAvailabilityFixture();
    await f.initialize();
    debugDefaultTargetPlatformOverride = null;
    await initializeDateFormatting();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('tip_shown_todo_plan_guide', true);
    await prefs.setBool(
      'migration_marker_${PlanAvailabilityFixture.username}_v4',
      true,
    );
    identity = await PlanTodoIdentity.capture(PlanAvailabilityFixture.username);
    repo = PlanReviewRepository(clock: () => now);
    await f.block(
      TodoPlanBlock(
        id: 'past',
        todoId: 'todo-target',
        titleSnapshot: '已完成规划',
        startTime: day.add(const Duration(hours: 8)).millisecondsSinceEpoch,
        endTime: day.add(const Duration(hours: 9)).millisecondsSinceEpoch,
        plannedMinutes: 60,
        status: TodoPlanStatus.finished,
      ),
    );
    await f.block(
      TodoPlanBlock(
        id: 'future',
        todoId: 'todo-target',
        titleSnapshot: '未来规划',
        startTime: day.add(const Duration(hours: 14)).millisecondsSinceEpoch,
        endTime: day.add(const Duration(hours: 15)).millisecondsSinceEpoch,
        plannedMinutes: 60,
      ),
    );
    for (var i = 0; i < 2; i++) {
      final start = day.add(Duration(hours: 6 + i)).millisecondsSinceEpoch;
      await f.db.insert('pomodoro_records', {
        'uuid': 'focus-$i',
        'todo_title': '自由专注$i',
        'start_time': start,
        'end_time': start + 60000,
        'actual_duration': 40,
        'planned_duration': 1500,
        'status': 'completed',
        'created_at': 1,
        'updated_at': 1,
      });
    }
  });
  tearDown(() async {
    await f.dispose();
    debugDefaultTargetPlatformOverride = null;
  });
  Future<void> host(
    WidgetTester t, {
    PlanReviewRepository? repository,
    Size size = const Size(390, 844),
    double scale = 1,
    bool full = false,
    ValueNotifier<DateTime>? date,
    ValueNotifier<(int, bool)>? revision,
  }) async {
    t.view.devicePixelRatio = 1;
    t.view.physicalSize = size;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    addTearDown(() async => t.pumpWidget(const SizedBox()));
    Widget overview(DateTime selected, (int, bool) state) => PlanDayOverview(
      username: PlanAvailabilityFixture.username,
      date: selected,
      clock: () => now,
      repository: repository ?? repo,
      revision: state.$1,
      enabled: state.$2,
    );
    await t.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        ),
        builder: (c, child) => MediaQuery(
          data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: full
            ? TodoPlanScreen(
                username: PlanAvailabilityFixture.username,
                initialDate: day,
                dragService: _Clock(),
                overviewRepository: repository ?? repo,
              )
            : Scaffold(
                body: Column(
                  children: [
                    if (date != null)
                      ValueListenableBuilder<DateTime>(
                        valueListenable: date,
                        builder: (_, value, _) => overview(value, (0, true)),
                      )
                    else if (revision != null)
                      ValueListenableBuilder<(int, bool)>(
                        valueListenable: revision,
                        builder: (_, value, _) => overview(day, value),
                      )
                    else
                      overview(day, (0, true)),
                    const Expanded(
                      child: ColoredBox(
                        key: ValueKey('grid-placeholder'),
                        color: Colors.transparent,
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
    await drain(t);
  }

  test('compact durations preserve seconds and zero', () {
    expect(planOverviewDuration(0), '0分');
    expect(planOverviewDuration(40), '40秒');
    expect(planOverviewDuration(80), '1分20秒');
    expect(planOverviewDuration(3600), '1时');
    expect(planOverviewDuration(3661), '1时1分1秒');
  });
  testWidgets(
    'four metrics use verified total and direct same-day focus details',
    (t) async {
      await host(t);
      expect(k('plan-overview-focus'), findsOneWidget);
      expect(find.text('1分20秒'), findsOneWidget);
      expect(find.text('1/1'), findsOneWidget);
      expect(t.getSize(k('plan-day-overview')).height, lessThanOrEqualTo(70));
      await t.tap(k('plan-overview-focus'));
      await drain(t);
      final detail = t.widget<PlanReviewDetailScreen>(
        find.byType(PlanReviewDetailScreen),
      );
      expect(detail.start, day);
      expect(detail.filter, PlanReviewFilter.focus);
      expect(find.textContaining('自由专注0'), findsWidgets);
      await t.pageBack();
      await drain(t);
      expect(find.byType(PlanDayOverview), findsOneWidget);
    },
  );
  for (final geometry in [
    (const Size(320, 700), 1.8),
    (const Size(720, 360), 2.0),
    (const Size(1280, 900), 1.0),
  ]) {
    testWidgets('responsive overview ${geometry.$1} scale ${geometry.$2}', (
      t,
    ) async {
      await host(t, size: geometry.$1, scale: geometry.$2);
      if (geometry.$2 > 1) {
        expect(k('plan-overview-open'), findsOneWidget);
        await t.tap(k('plan-overview-open'));
        await drain(t);
        expect(
          t
              .widget<PlanBlockStatsScreen>(find.byType(PlanBlockStatsScreen))
              .initialDate,
          day,
        );
        await t.pageBack();
        await drain(t);
      } else {
        expect(k('plan-overview-plans'), findsOneWidget);
      }
      expect(t.takeException(), isNull);
      expect(t.getSize(k('grid-placeholder')).height, greaterThan(0));
    });
  }
  testWidgets('huge numbers simplify rather than truncate', (t) async {
    final controlled = _Controlled();
    await host(t, repository: controlled);
    controlled.requests.single.$3.complete(data(day, seconds: 999999999));
    await drain(t);
    expect(k('plan-overview-open'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
  testWidgets('late response cannot overwrite another date', (t) async {
    final controlled = _Controlled(), date = ValueNotifier(day);
    addTearDown(date.dispose);
    await host(t, repository: controlled, date: date);
    final next = DateTime(2026, 10, 9);
    date.value = next;
    await drain(t);
    controlled.requests[1].$3.complete(data(next, seconds: 120));
    await drain(t);
    controlled.requests[0].$3.complete(data(day, seconds: 300));
    await drain(t);
    expect(find.text('2分'), findsOneWidget);
    expect(find.text('5分'), findsNothing);
  });
  testWidgets('source refresh disables old clicks until new overview arrives', (
    t,
  ) async {
    final controlled = _Controlled(), revision = ValueNotifier((0, true));
    addTearDown(revision.dispose);
    await host(t, repository: controlled, revision: revision);
    controlled.requests[0].$3.complete(data(day));
    await drain(t);
    revision.value = (0, false);
    await t.pump();
    await t.tap(k('plan-overview-focus'));
    await t.pump();
    expect(find.byType(PlanReviewDetailScreen), findsNothing);
    revision.value = (1, true);
    await drain(t);
    controlled.requests[1].$3.complete(data(day, seconds: 180));
    await drain(t);
    expect(find.text('3分'), findsOneWidget);
  });
  testWidgets(
    'account switched during a request does not leak previous numbers',
    (t) async {
      final controlled = _Controlled();
      await host(t, repository: controlled);
      await t.runAsync(
        () async => (await SharedPreferences.getInstance()).setString(
          'current_login_user',
          'other',
        ),
      );
      controlled.requests.single.$3.complete(data(day));
      await drain(t);
      expect(k('plan-overview-error'), findsOneWidget);
      expect(k('plan-overview-focus'), findsNothing);
    },
  );
  testWidgets(
    'expired boundary retries at most once and hidden route stops reads',
    (t) async {
      final controlled = _Controlled();
      await host(t, repository: controlled);
      controlled.requests[0].$3.complete(data(day, boundary: now));
      await drain(t);
      expect(controlled.requests.length, 2);
      controlled.requests[1].$3.complete(data(day, boundary: now));
      await drain(t);
      await t.pump(const Duration(seconds: 10));
      expect(controlled.requests.length, 2);
      final context = t.element(find.byType(PlanDayOverview));
      unawaited(
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: Text('covered')),
          ),
        ),
      );
      await t.pumpAndSettle();
      await t.pump(const Duration(days: 2));
      expect(controlled.requests.length, 2);
      Navigator.of(context).pop();
      await drain(t);
      expect(controlled.requests.length, 3);
      controlled.requests.last.$3.complete(data(day));
      await drain(t);
    },
  );
  testWidgets(
    'formal calendar remains usable when overview fails; retry is read-only',
    (t) async {
      final retry = _Retry();
      await host(t, repository: retry, full: true);
      expect(k('plan-overview-error'), findsOneWidget);
      expect(find.text('23:00'), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is GestureDetector &&
              w.onPanStart != null &&
              w.onTapDown != null,
        ),
        findsOneWidget,
      );
      final changes = await t.runAsync(
        () async =>
            (await f.db.rawQuery('SELECT total_changes() n')).single['n'],
      );
      await t.tap(k('plan-overview-retry'));
      await drain(t);
      expect(k('plan-overview-focus'), findsOneWidget);
      expect(retry.calls, 2);
      final after = await t.runAsync(
        () async =>
            (await f.db.rawQuery('SELECT total_changes() n')).single['n'],
      );
      expect(after, changes);
    },
  );
  testWidgets('formal calendar menu opens statistics on selected date', (
    t,
  ) async {
    await host(t, full: true);
    await t.tap(find.byTooltip('更多'));
    await t.pumpAndSettle();
    await t.tap(find.text('规划统计'));
    await drain(t);
    final stats = t.widget<PlanBlockStatsScreen>(
      find.byType(PlanBlockStatsScreen),
    );
    expect(stats.initialDate, day);
    expect(stats.repository, same(repo));
    expect(stats.clock!(), now);
  });
  testWidgets(
    'member switched before navigation clears numbers and blocks old details',
    (t) async {
      await host(t);
      await t.runAsync(
        () async => (await SharedPreferences.getInstance()).setInt(
          'current_user_id',
          9,
        ),
      );
      await t.tap(k('plan-overview-focus'));
      await drain(t);
      expect(find.byType(PlanReviewDetailScreen), findsNothing);
      expect(k('plan-overview-error'), findsOneWidget);
      expect(k('plan-overview-focus'), findsNothing);
      expect(find.text('身份已变化，请重新打开'), findsOneWidget);
    },
  );
  testWidgets('background invalidates requests and resume refreshes once', (
    t,
  ) async {
    final controlled = _Controlled();
    await host(t, repository: controlled);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await t.pump();
    controlled.requests[0].$3.complete(data(day, seconds: 600));
    await drain(t);
    await t.pump(const Duration(days: 1));
    expect(controlled.requests.length, 1);
    expect(k('plan-overview-focus'), findsNothing);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await drain(t);
    expect(controlled.requests.length, 2);
    controlled.requests[1].$3.complete(data(day, seconds: 120));
    await drain(t);
    expect(find.text('2分'), findsOneWidget);
  });
  testWidgets(
    'late response after leaving has no visible or framework effect',
    (t) async {
      final controlled = _Controlled();
      await host(t, repository: controlled);
      await t.pumpWidget(const MaterialApp(home: Text('已离开')));
      controlled.requests.single.$3.complete(data(day));
      await drain(t);
      expect(find.text('已离开'), findsOneWidget);
      expect(k('plan-overview-focus'), findsNothing);
      expect(t.takeException(), isNull);
    },
  );
  for (final item in [
    ('plans', PlanReviewFilter.plans),
    ('ended', PlanReviewFilter.ended),
    ('logs', PlanReviewFilter.logs),
  ]) {
    testWidgets('${item.$1} opens matching detail filter', (t) async {
      await host(t);
      await t.tap(k('plan-overview-${item.$1}'));
      await drain(t);
      final detail = t.widget<PlanReviewDetailScreen>(
        find.byType(PlanReviewDetailScreen),
      );
      expect(detail.filter, item.$2);
      expect(detail.start, day);
    });
  }
  testWidgets('issues badge opens the existing review issues', (t) async {
    await t.runAsync(
      () => f.db.update(
        'todo_plan_blocks',
        {'status': TodoPlanStatus.missed.index},
        where: 'uuid=?',
        whereArgs: ['future'],
      ),
    );
    await host(t);
    expect(k('plan-overview-issues'), findsOneWidget);
    await t.tap(k('plan-overview-issues'));
    await drain(t);
    expect(
      t
          .widget<PlanReviewDetailScreen>(find.byType(PlanReviewDetailScreen))
          .filter,
      PlanReviewFilter.issues,
    );
  });
  testWidgets(
    'overview failure does not prevent drag creation and cancel writes nothing',
    (t) async {
      final controlled = _Controlled();
      await host(t, repository: controlled, full: true);
      controlled.requests.single.$3.completeError(StateError('合成概览失败'));
      await drain(t);
      final grid = find.byWidgetPredicate(
        (w) =>
            w is GestureDetector && w.onPanStart != null && w.onTapDown != null,
      );
      final rect = t.getRect(grid);
      await t.dragFrom(
        Offset(rect.left + rect.width * .3, rect.top + rect.height * .7),
        const Offset(60, 35),
      );
      await drain(t);
      expect(find.byType(PlanBlockEditorSheet), findsOneWidget);
      Navigator.of(t.element(find.byType(PlanBlockEditorSheet))).pop();
      await drain(t);
      if (controlled.requests.length > 1) {
        controlled.requests.last.$3.completeError(StateError('合成概览失败'));
      }
      await drain(t);
      final counts = await t.runAsync(
        () async => [
          (await f.db.query('todo_plan_blocks')).length,
          (await f.db.query('op_logs')).length,
        ],
      );
      expect(counts, [2, 0]);
      expect(t.takeException(), isNull);
    },
  );
}
