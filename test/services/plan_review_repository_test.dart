import 'package:countdown_todo/models.dart';
import 'package:countdown_todo/services/plan_review_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/plan_availability_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late PlanAvailabilityFixture f;
  late PlanReviewRepository repo;
  final day = DateTime(2026, 10, 8), end = DateTime(2026, 10, 9);
  final now = DateTime(2026, 10, 9, 12);
  int at(int hour, [int minute = 0]) =>
      DateTime(2026, 10, 8, hour, minute).millisecondsSinceEpoch;
  Future<void> plan(
    String id, {
    int hour = 10,
    int minute = 0,
    int minutes = 60,
    TodoPlanStatus status = TodoPlanStatus.planned,
    List<String> links = const [],
    int cache = 0,
    String todo = 'todo-target',
  }) => f.block(
    TodoPlanBlock(
      id: id,
      todoId: todo,
      titleSnapshot: '规划$id',
      startTime: at(hour, minute),
      endTime: at(hour, minute) + minutes * 60000,
      plannedMinutes: minutes,
      status: status,
      pomodoroRecordIds: links,
      actualFocusSeconds: cache,
    ),
  );
  Future<void> focus(
    String id, {
    int hour = 10,
    int minute = 0,
    int? seconds = 1500,
    String? planId,
    String? todo = 'todo-target',
    String status = 'completed',
    int? start,
    int? finish,
    bool deleted = false,
    int conflict = 0,
  }) => f.db
      .insert('pomodoro_records', {
        'uuid': id,
        'todo_uuid': todo,
        'todo_title': '记录$id',
        'start_time': start ?? at(hour, minute),
        'end_time': finish ?? ((start ?? at(hour, minute)) + 1800000),
        'actual_duration': seconds,
        'planned_duration': 1500,
        'status': status,
        'plan_block_id': planId,
        'is_deleted': deleted ? 1 : 0,
        'has_conflict': conflict,
        'created_at': at(0),
        'updated_at': at(0),
      })
      .then((_) {});
  Future<PlanReviewSummary> read() =>
      repo.read(PlanAvailabilityFixture.username, day, end);
  Future<void> legacyNullableFocusTable() async {
    // Historical imports may have nullable fields, unlike today's schema.
    await f.db.execute('ALTER TABLE pomodoro_records RENAME TO old_focus');
    await f.db.execute(
      'CREATE TABLE pomodoro_records AS SELECT * FROM old_focus',
    );
    await f.db.execute('DROP TABLE old_focus');
  }

  Future<PlanReviewPage> page(
    PlanReviewFilter filter, {
    PlanReviewCursor? cursor,
    String? planId,
    bool cumulative = false,
  }) => repo.page(
    PlanAvailabilityFixture.username,
    day,
    end,
    filter,
    cursor: cursor,
    planId: planId,
    cumulative: cumulative,
  );
  setUp(() async {
    f = PlanAvailabilityFixture();
    await f.initialize();
    repo = PlanReviewRepository(clock: () => now);
  });
  tearDown(() async => f.dispose());

  test('real plan budget excludes course and legacy mapped tasks', () async {
    await f.course('course', day, 800, 1000);
    await f.todo(
      'legacy',
      '旧式',
      legacyStart: DateTime(2026, 10, 8, 14),
      due: DateTime(2026, 10, 8, 15),
    );
    await plan('real', status: TodoPlanStatus.finished);
    await focus('r', seconds: 2400, planId: 'real');
    final s = await read();
    expect(s.plan('seconds'), 3600);
    expect(s.actual('seconds'), 2400);
    expect(s.plan('done'), 1);
    expect(s.plan('ended'), 1);
    expect((await page(PlanReviewFilter.plans)).total, 1);
  });
  test(
    'one record overlapping two plans counts once and needs attribution',
    () async {
      await plan('a');
      await plan('b', minute: 5);
      await focus('r', minute: 10);
      final s = await read();
      expect(s.actual('seconds'), 1500);
      expect(s.actual('attribution'), 1500);
      expect(s.actual('linked'), 0);
      expect(
        (await page(PlanReviewFilter.attribution)).rows.single.reason,
        '归属待核对',
      );
    },
  );
  test(
    'explicit plan and list agreeing is one claim, cache never inflates actual',
    () async {
      await plan('a', links: ['r'], cache: 5400);
      await plan('b');
      await focus('r', planId: 'a', seconds: 1200);
      final s = await read();
      expect(s.actual('linked'), 1200);
      expect(s.actual('seconds'), 1200);
      expect((await page(PlanReviewFilter.linked)).rows.single.planId, 'a');
    },
  );
  test(
    'contradictory ids and todo identity are never guessed from titles',
    () async {
      await f.todo('other', '复习高数');
      await plan('a', links: ['r']);
      await plan('b', todo: 'other');
      await focus('r', planId: 'b');
      expect((await read()).actual('attribution'), 1500);
      expect((await read()).ranking, isEmpty);
    },
  );
  test('dangling explicit plan does not fall back to overlap', () async {
    await plan('a');
    await focus('r', planId: 'missing');
    expect((await read()).actual('attribution'), 1500);
  });
  test(
    'missing duration is review, zero stays zero, interrupted is real work',
    () async {
      await legacyNullableFocusTable();
      await focus('legacy', seconds: null);
      await focus('zero', seconds: 0);
      await focus('interrupted', seconds: 61, status: 'interrupted');
      await focus('switched', seconds: 62, status: 'switched');
      final s = await read();
      expect(s.actual('seconds'), 123);
      expect(s.actual('n'), 3);
      final issues = await page(PlanReviewFilter.issues);
      expect(issues.rows.single.id, 'legacy');
      expect(issues.rows.single.reason, '旧记录时长待核对');
    },
  );
  test(
    'bad or conflicted records are excluded without planned fallback',
    () async {
      await legacyNullableFocusTable();
      await focus('negative', seconds: -10);
      await focus('conflict', conflict: 1);
      await focus('deleted', deleted: true);
      await focus('status', status: 'unknown');
      await focus('no-end');
      await f.db.update(
        'pomodoro_records',
        {'end_time': null},
        where: 'uuid=?',
        whereArgs: ['no-end'],
      );
      expect((await read()).actual('seconds'), 0);
      expect((await page(PlanReviewFilter.issues)).total, 4);
    },
  );
  test(
    'cancelled and skipped excluded from denominator but work remains',
    () async {
      await plan('done', status: TodoPlanStatus.finished);
      await plan('cancelled', status: TodoPlanStatus.cancelled);
      await plan('skipped', status: TodoPlanStatus.skipped);
      await focus('r', planId: 'cancelled');
      final s = await read();
      expect(s.plan('seconds'), 3600);
      expect(s.plan('ended'), 1);
      expect(s.plan('done'), 1);
      expect(s.plan('cancelled'), 1);
      expect(s.plan('skipped'), 1);
      expect(s.actual('linked'), 1500);
    },
  );
  test('future has no completion denominator, ended planned is not inferred missed', () async {
    repo = PlanReviewRepository(clock: () => DateTime(2026, 10, 8, 9));
    await plan('future');
    var s = await read();
    expect(s.plan('ended'), 0);
    expect(s.plan('upcoming'), 1);
    expect(s.issues, 0);
    repo = PlanReviewRepository(clock: () => now);
    s = await read();
    expect(s.plan('ended'), 1);
    expect(s.plan('done'), 0);
    expect(s.plan('missed'), 0);
    expect(s.issues, 1);
  });
  test(
    'cross-midnight records bucket by start but can bind previous-day plan',
    () async {
      await f.block(
        TodoPlanBlock(
          id: 'night',
          todoId: 'todo-target',
          startTime: DateTime(2026, 10, 7, 23).millisecondsSinceEpoch,
          endTime: at(1),
          plannedMinutes: 120,
        ),
      );
      await focus('early', hour: 0, seconds: 1200);
      await focus(
        'late',
        hour: 23,
        minute: 30,
        seconds: 2400,
        finish: DateTime(2026, 10, 9, 0, 30).millisecondsSinceEpoch,
      );
      final s = await read();
      expect(s.actual('seconds'), 3600);
      expect(s.actual('linked'), 1200);
      expect(s.plan('seconds'), 0);
      expect(
        (await repo.read(
          PlanAvailabilityFixture.username,
          end,
          DateTime(2026, 10, 10),
        )).actual('seconds'),
        0,
      );
    },
  );
  test('period and lifetime detail cannot mix outside-range focus', () async {
    await plan('a');
    await focus('current', planId: 'a', seconds: 1200);
    await focus(
      'past',
      planId: 'a',
      seconds: 600,
      start: DateTime(2026, 10, 7, 10).millisecondsSinceEpoch,
    );
    expect((await page(PlanReviewFilter.focus, planId: 'a')).seconds, 1200);
    expect(
      (await page(
        PlanReviewFilter.focus,
        planId: 'a',
        cumulative: true,
      )).seconds,
      1800,
    );
    expect((await read()).actual('seconds'), 1200);
  });
  test('logs clipped to period, not combined with focus, aggregate seconds before display', () async {
    await focus('r', seconds: 40);
    await f.db.insert('time_logs', {
      'uuid': 'l',
      'title': '跨日',
      'start_time': DateTime(2026, 10, 7, 23, 59, 30).millisecondsSinceEpoch,
      'end_time': at(0) + 30000,
      'created_at': at(0),
      'updated_at': at(0),
      'device_id': 'fixture',
      'team_uuid': '',
    });
    await f.db.insert('time_logs', {
      'uuid': 'l2',
      'title': '重叠',
      'start_time': at(0),
      'end_time': at(0) + 40000,
      'created_at': at(0),
      'updated_at': at(0),
      'device_id': 'fixture',
      'team_uuid': '',
    });
    final s = await read();
    expect(s.log('seconds'), 70);
    expect(s.actual('seconds'), 40);
    expect((await page(PlanReviewFilter.logs)).seconds, 70);
  });
  test(
    'invalid real planning data goes to review instead of denominator',
    () async {
      await plan('bad');
      await f.db.update('todo_plan_blocks', {'planned_minutes': 0});
      expect((await read()).plan('seconds'), 0);
      expect((await read()).plan('ended'), 0);
      expect((await page(PlanReviewFilter.issues)).rows.single.kind, 'plan');
    },
  );
  test('exact uuid rankings preserve same title, completion and recurrence instances', () async {
    await f.todo('other', '复习高数', done: true);
    await focus('one', todo: 'todo-target', seconds: 61);
    await focus('two', todo: 'other', seconds: 62);
    final s = await read();
    expect(s.ranking.length, 2);
    expect(s.ranking.map((r) => r['id']).toSet(), {'todo-target', 'other'});
  });
  test(
    '50 item stable cursor, writes invalidate even same aggregate totals',
    () async {
      await f.db.transaction((t) async {
        for (var i = 0; i < 105; i++) {
          await t.insert('pomodoro_records', {
            'uuid': 'r${i.toString().padLeft(3, '0')}',
            'start_time': at(10),
            'end_time': at(11),
            'actual_duration': 60,
            'planned_duration': 60,
            'status': 'completed',
            'created_at': at(0),
            'updated_at': at(0),
          });
        }
      });
      final p1 = await page(PlanReviewFilter.focus);
      expect(p1.rows.length, 50);
      expect(p1.total, 105);
      final p2 = await page(PlanReviewFilter.focus, cursor: p1.next);
      expect(p2.restarted, false);
      expect(
        {...p1.rows.map((r) => r.id), ...p2.rows.map((r) => r.id)}.length,
        100,
      );
      await f.db.update(
        'pomodoro_records',
        {'todo_title': '标题更改'},
        where: 'uuid=?',
        whereArgs: ['r104'],
      );
      final refreshed = await page(PlanReviewFilter.focus, cursor: p2.next);
      expect(refreshed.restarted, true);
      expect(refreshed.rows.first.id, p1.rows.first.id);
    },
  );
  test(
    'large unrelated history is not decoded and query count is bounded',
    () async {
      await f.db.transaction((t) async {
        for (var i = 0; i < 1001; i++) {
          await t.insert('pomodoro_records', {
            'uuid': 'old$i',
            'start_time': 1,
            'end_time': 1000,
            'actual_duration': 1,
            'planned_duration': 1,
            'status': 'completed',
            'note': '私密长备注' * 100,
            'created_at': at(0),
            'updated_at': at(0),
          });
          await t.insert('todo_plan_blocks', {
            ...TodoPlanBlock(id: 'old-plan-$i', todoId: 'todo-target',
              titleSnapshot: '无关历史规划', startTime: 1, endTime: 1000,
              plannedMinutes: 1, status: TodoPlanStatus.finished,
              remark: '历史私密备注' * 100).toDbJson(),
            'calendar_event_id': '',
            'created_at': at(0),
            'updated_at': at(0),
          });
        }
      });
      await focus('r');
      final calls = <int>[];
      repo = PlanReviewRepository(
        clock: () => now,
        onQuery: (sql, n) => calls.add(n),
      );
      final s = await read();
      expect(s.actual('n'), 1);
      expect(s.plan('seconds'), 0);
      expect(calls.length, 10);
      expect(calls.every((n) => n < 60), true);
    },
  );
  test(
    'reads are zero-write and account/member switch rejects old identity',
    () async {
      await focus('r');
      final before = (await f.db.rawQuery('SELECT total_changes() n'))
          .single['n'];
      final s = await read();
      await page(PlanReviewFilter.focus);
      expect(
        (await f.db.rawQuery('SELECT total_changes() n')).single['n'],
        before,
      );
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('current_user_id', 9);
      await expectLater(
        repo.detail(s.identity, 'focus', 'r'),
        throwsA(anything),
      );
      await prefs.setString('current_login_user', 'other');
      await expectLater(read(), throwsA(anything));
    },
  );
  test(
    'a missing explicit id cannot be rescued by another plan list',
    () async {
      await plan('a', links: ['r']);
      await focus('r', planId: 'missing');
      final s = await read();
      expect(s.actual('attribution'), 1500);
      expect(s.actual('linked'), 0);
    },
  );
  test(
    'multiple claims without direct todo cannot guess a ranking owner',
    () async {
      await f.todo('other', '另一待办');
      await plan('a', links: ['r']);
      await plan('b', links: ['r'], todo: 'other');
      await focus('r', todo: null);
      final s = await read();
      expect(s.actual('seconds'), 1500);
      expect(s.actual('attribution'), 1500);
      expect(s.ranking, isEmpty);
    },
  );
  test(
    'three mutually exclusive actual categories reconcile to total',
    () async {
      await plan('a');
      await focus('linked', planId: 'a', seconds: 61);
      await focus('free', todo: null, seconds: 62);
      await focus('review', planId: 'missing', seconds: 63);
      final s = await read();
      expect(s.actual('seconds'), 186);
      final parts = await Future.wait([
        page(PlanReviewFilter.linked),
        page(PlanReviewFilter.unlinked),
        page(PlanReviewFilter.attribution),
      ]);
      expect(parts.map((p) => p.seconds), [61, 62, 63]);
      expect(parts.expand((p) => p.rows).map((r) => r.id).toSet().length, 3);
    },
  );
  test(
    'deleted todo preserves historical title snapshot and actual work',
    () async {
      await focus('r');
      await f.db.update('todos', {'is_deleted': 1});
      final p = await page(PlanReviewFilter.focus);
      expect(p.rows.single.title, '记录r');
      expect(p.rows.single.reason, contains('历史待办已删除或不存在'));
      expect((await read()).actual('seconds'), 1500);
    },
  );
  test(
    'fractional log intervals sum milliseconds before formatting seconds',
    () async {
      for (var i = 0; i < 2; i++) {
        await f.db.insert('time_logs', {
          'uuid': 'log$i',
          'title': '短日志',
          'start_time': at(10),
          'end_time': at(10) + 30500,
          'created_at': 1,
          'updated_at': 1,
          'device_id': '',
          'team_uuid': '',
        });
      }
      expect((await read()).log('seconds'), 61);
      expect((await page(PlanReviewFilter.logs)).seconds, 61);
    },
  );
  test(
    'month overview has calendar days and adjacent month boundary is exclusive',
    () async {
      await focus('r');
      await focus(
        'outside',
        start: DateTime(2026, 11, 1).millisecondsSinceEpoch,
      );
      final s = await repo.read(
        PlanAvailabilityFixture.username,
        DateTime(2026, 10, 1),
        DateTime(2026, 11, 1),
      );
      expect(s.days.length, 31);
      expect(
        s.days.fold<int>(0, (sum, d) => sum + (d['actual'] as num).toInt()),
        1500,
      );
      expect(s.actual('n'), 1);
    },
  );
  test('details retain tag names and reject deleted record', () async {
    await focus('r');
    await f.db.insert('pomodoro_tags', {
      'uuid': 'tag',
      'name': '学习',
      'color': '#123456',
      'created_at': 1,
      'updated_at': 1,
    });
    await f.db.update('pomodoro_records', {'tag_uuids': '["tag"]'});
    final s = await read();
    final row = await repo.detail(s.identity, 'focus', 'r');
    expect((row['review_tags'] as List).single['name'], '学习');
    expect(row['review_valid'], true);
    await f.db.update('pomodoro_records', {'is_deleted': 1});
    await expectLater(repo.detail(s.identity, 'focus', 'r'), throwsStateError);
  });
  test('ended details wake at next end even if no rows yet', () async {
    repo = PlanReviewRepository(clock: () => DateTime(2026, 10, 8, 9));
    await plan('future');
    final p = await page(PlanReviewFilter.ended);
    expect(p.rows, isEmpty);
    expect(p.nextBoundary, DateTime(2026, 10, 8, 11));
  });
  test(
    'future missed marker is reviewed without a premature recovery prompt',
    () async {
      repo = PlanReviewRepository(clock: () => DateTime(2026, 10, 8, 9));
      await plan('future', status: TodoPlanStatus.missed);
      final s = await read();
      expect(s.plan('missed'), 0);
      expect(s.missed, isEmpty);
      expect(s.issues, 1);
    },
  );
  test('unmigrated legacy data gives explicit initialization error without writing', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      'user_todos_${PlanAvailabilityFixture.username}',
      ['legacy'],
    );
    await expectLater(read(), throwsStateError);
    expect(
      prefs.getStringList('user_todos_${PlanAvailabilityFixture.username}'),
      ['legacy'],
    );
  });
}
