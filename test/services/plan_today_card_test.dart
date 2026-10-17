@TestOn('vm')
library;

import 'dart:io';

import 'package:countdown_todo/models.dart';
import 'package:countdown_todo/services/plan_review_repository.dart';
import 'package:countdown_todo/services/plan_today_maintenance.dart';
import 'package:countdown_todo/services/api_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/plan_availability_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late PlanAvailabilityFixture f;
  late PlanReviewRepository repo;
  var now = DateTime(2026, 10, 8, 12);
  DateTime getDay() => DateTime(now.year, now.month, now.day);
  int at(int hour, [int minute = 0]) => DateTime(
    now.year,
    now.month,
    now.day,
    hour,
    minute,
  ).millisecondsSinceEpoch;
  Future<void> plan(
    String id,
    int hour, {
    TodoPlanStatus status = TodoPlanStatus.planned,
    int minutes = 60,
    int cache = 0,
    String todo = 'todo-target',
    List<String> links = const [],
  }) => f.block(
    TodoPlanBlock(
      id: id,
      todoId: todo,
      titleSnapshot: '规划$id',
      startTime: at(hour),
      endTime: at(hour) + minutes * 60000,
      plannedMinutes: minutes,
      status: status,
      actualFocusSeconds: cache,
      pomodoroRecordIds: links,
    ),
  );
  Future<void> focus(
    String id, {
    String? planId,
    String? todo = 'todo-target',
    int seconds = 40,
    int hour = 9,
    int? start,
    int? end,
  }) => f.db
      .insert('pomodoro_records', {
        'uuid': id,
        'todo_uuid': todo,
        'todo_title': '相同标题',
        'start_time': start ?? at(hour),
        'end_time': end ?? at(hour, 1),
        'actual_duration': seconds,
        'planned_duration': 3600,
        'status': 'completed',
        'plan_block_id': planId,
        'tag_uuids': '[]',
        'created_at': 1,
        'updated_at': 1,
      })
      .then((_) {});
  Future<PlanTodayCard> read() =>
      repo.readTodayCard(PlanAvailabilityFixture.username);
  setUp(() async {
    now = DateTime(2026, 10, 8, 12);
    f = PlanAvailabilityFixture();
    await f.initialize();
    repo = PlanReviewRepository(databaseOverride: f.db, clock: () => now);
    ApiService.setBaseUrlOverride('http://127.0.0.1:1');
  });
  tearDown(() async {
    ApiService.clearBaseUrlOverride();
    await f.dispose();
  });

  test('homepage aggregates equal overview and full review, not caches or cancellations', () async {
    await plan('old', 9, status: TodoPlanStatus.finished, cache: 99999);
    await plan('future', 14);
    await plan('cancelled', 16, status: TodoPlanStatus.cancelled);
    await plan('skipped', 17, status: TodoPlanStatus.skipped);
    await focus('40a', planId: 'old');
    await focus('40b', planId: 'old');
    final card = await read();
    final overview = await repo.readOverview(
      PlanAvailabilityFixture.username,
      getDay(),
      DateTime(2026, 10, 9),
    );
    final full = await repo.read(
      PlanAvailabilityFixture.username,
      getDay(),
      DateTime(2026, 10, 9),
    );
    expect(card.overview.plans, overview.plans);
    expect(card.overview.focus, full.focus);
    expect(card.total, 2);
    expect(card.overview.actual('seconds'), 80);
    expect(card.rows.singleWhere((r) => r.entry.id == 'old').focusSeconds, 80);
    expect(await f.db.query('op_logs'), isEmpty);
  });
  test('five completed morning plans cannot hide afternoon plans', () async {
    for (var i = 0; i < 5; i++) {
      await plan('finished$i', i + 5, status: TodoPlanStatus.finished);
    }
    await plan('next', 14);
    await plan('later', 16);
    final c = await read();
    expect(c.rows.map((r) => r.entry.id).take(2), ['next', 'later']);
    expect(c.rows.length, 5);
    expect(c.total, 7);
  });
  test(
    'ongoing first, reserve a need row, stable future ties, no duplicates',
    () async {
      await plan('ongoing', 11, minutes: 120);
      await plan('need', 8, status: TodoPlanStatus.missed);
      for (final id in ['e', 'd', 'c', 'b', 'a']) {
        await plan(id, 14);
      }
      await plan('already-finished', 18, status: TodoPlanStatus.finished);
      final c = await read();
      expect(c.rows.map((r) => r.entry.id), ['ongoing', 'a', 'b', 'c', 'need']);
      expect(c.rows.map((r) => r.entry.id).toSet().length, 5);
      expect(c.nextBoundary, DateTime(2026, 10, 8, 13));
    },
  );
  test(
    'attribution includes invisible candidates and does not borrow by title',
    () async {
      for (var i = 0; i < 6; i++) {
        await plan('competing$i', 9);
      }
      await focus('ambiguous');
      await focus('title-only', todo: null, seconds: 40);
      final c = await read();
      expect(c.rows.every((r) => r.focusSeconds == 0), isTrue);
      expect(c.overview.actual('seconds'), 80);
      expect(c.overview.actual('attribution'), 40);
      expect(c.overview.actual('unlinked'), 40);
      expect(c.overview.issues, greaterThan(0));
    },
  );
  test('zero-second unlinked records remain discoverable', () async {
    await focus('zero', todo: null, seconds: 0);
    final c = await read();
    expect(c.overview.actual('unlinkedN'), 1);
    expect(c.overview.actual('unlinked'), 0);
    expect(c.rows, isEmpty);
  });
  test('next start and midnight are one-shot boundaries', () async {
    await plan('next', 14);
    expect((await read()).nextBoundary, DateTime(2026, 10, 8, 14));
    now = DateTime(2026, 10, 8, 14);
    expect((await read()).nextBoundary, DateTime(2026, 10, 8, 15));
    now = DateTime(2026, 10, 8, 15);
    expect((await read()).nextBoundary, DateTime(2026, 10, 9));
  });
  test('bad planning data and all cancelled are not executable rows', () async {
    await plan('bad', 9, minutes: 0);
    await plan('cancel', 10, status: TodoPlanStatus.cancelled);
    await plan('skip', 11, status: TodoPlanStatus.skipped);
    final c = await read();
    expect(c.total, 0);
    expect(c.rows, isEmpty);
    expect(c.overview.issues, 1);
  });
  test('projection stays fixed with large day and unrelated history', () async {
    final observed = <int>[];
    repo = PlanReviewRepository(
      databaseOverride: f.db,
      clock: () => now,
      onQuery: (sql, count) {
        if (!sql.startsWith('PRAGMA')) observed.add(count);
      },
    );
    for (var i = 0; i < 100; i++) {
      await plan('p$i', 14);
    }
    for (var i = 0; i < 200; i++) {
      await f.block(
        TodoPlanBlock(
          id: 'history$i',
          todoId: 'todo-target',
          startTime: DateTime(2025, 1, 1).millisecondsSinceEpoch,
          endTime: DateTime(2025, 1, 1, 1).millisecondsSinceEpoch,
          plannedMinutes: 60,
        ),
      );
    }
    for (var i = 0; i < 100; i++) {
      await focus('bulk-focus$i');
    }
    final c = await read();
    expect(c.overview.actual('unlinked'), 4000);
    expect(c.total, 100);
    expect(c.rows.length, 5);
    expect(observed, [1, 1, 1, 1, 5]);
  });
  test(
    'cross-midnight ownership and deleted todo snapshots remain intact',
    () async {
      await plan('overnight', 23, minutes: 120);
      await focus(
        'prior',
        start: getDay()
            .subtract(const Duration(minutes: 20))
            .millisecondsSinceEpoch,
        end: getDay().add(const Duration(minutes: 20)).millisecondsSinceEpoch,
        seconds: 2400,
      );
      await f.db.update('todos', {'is_deleted': 1});
      final c = await read();
      expect(c.rows.single.entry.title, '规划overnight');
      expect(c.overview.actual('seconds'), 0);
      expect(c.total, 1);
      expect(c.rows.single.entry.end, at(23) + 120 * 60000);
    },
  );
  test('identity change rejects an old detail identity', () async {
    await plan('p', 14);
    final c = await read();
    await (await SharedPreferences.getInstance()).setInt('current_user_id', 9);
    await expectLater(
      repo.detail(c.overview.identity, 'plan', 'p'),
      throwsA(anything),
    );
  });
  test('legacy maintenance retains cache and same-title decisions, display reads write nothing', () async {
    await plan('cache', 8, cache: 1);
    await plan('title', 9, todo: 'different');
    await plan('missed', 10);
    await f.db.update(
      'todo_plan_blocks',
      {'title_snapshot': '相同标题'},
      where: 'uuid=?',
      whereArgs: ['title'],
    );
    await focus('legacy-title', todo: null, hour: 9);
    await const PlanTodayMaintenance().run(
      PlanAvailabilityFixture.username,
      now,
    );
    final rows = await f.db.query('todo_plan_blocks');
    expect(rows.singleWhere((r) => r['uuid'] == 'cache')['status'], 0);
    expect(rows.singleWhere((r) => r['uuid'] == 'title')['status'], 0);
    expect(
      rows.singleWhere((r) => r['uuid'] == 'missed')['status'],
      TodoPlanStatus.missed.index,
    );
    final before = await f.db.query('op_logs');
    await read();
    expect(await f.db.query('op_logs'), before);
  });
  for (final zone in ['America/New_York', 'Australia/Lord_Howe']) {
    test('local day boundaries respect DST in $zone', () async {
      if (Platform.environment['TZ'] != zone) return;
      now = zone == 'America/New_York'
          ? DateTime(2026, 11, 1, 12)
          : DateTime(2026, 10, 4, 12);
      await plan('local', 9);
      final c = await read();
      expect(c.overview.end, DateTime(now.year, now.month, now.day + 1));
      expect(
        c.overview.end.difference(c.overview.start).inMinutes,
        zone == 'America/New_York' ? 1500 : 1410,
      );
    });
  }
}
