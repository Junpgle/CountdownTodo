@TestOn('vm')
library;

import 'dart:convert';

import 'package:countdown_todo/models.dart';
import 'package:countdown_todo/models/plan_cleanup.dart';
import 'package:countdown_todo/services/plan_cleanup_repository.dart';
import 'package:countdown_todo/services/plan_reminder_guard.dart';
import 'package:countdown_todo/services/pomodoro_service.dart';
import 'package:countdown_todo/storage_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/plan_availability_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late PlanAvailabilityFixture f;
  late PlanCleanupRepository repo;
  late DateTime clock;
  const user = PlanAvailabilityFixture.username, todoId = 'todo-target';
  final day = PlanAvailabilityFixture.day;
  Future<void> block(
    String id, {
    String todo = todoId,
    DateTime? start,
    TodoPlanStatus status = TodoPlanStatus.planned,
    int minutes = 45,
    String? calendar,
  }) => f.block(
    TodoPlanBlock(
      id: id,
      todoId: todo,
      startTime:
          (start ?? day.add(const Duration(hours: 10))).millisecondsSinceEpoch,
      endTime: (start ?? day.add(const Duration(hours: 10)))
          .add(Duration(minutes: minutes))
          .millisecondsSinceEpoch,
      plannedMinutes: minutes,
      status: status,
      calendarEventId: calendar,
      remark: '保留备注',
      reminderMinutes: 15,
      pomodoroMinutes: 20,
      pomodoroRounds: 2,
    ),
  );
  Future<PlanCleanupRequest> request([Set<String>? ids]) async {
    final snapshot = await repo.detail(user, todoId);
    return snapshot.select(
      ids ?? snapshot.rows.where((r) => r.eligible).map((r) => r.id).toSet(),
      clock,
    );
  }

  Future<void> record(
    String id, {
    String? plan,
    String? todo = todoId,
    int actual = 0,
    int? start,
    int? end,
  }) async => f.db
      .insert('pomodoro_records', {
        'uuid': id,
        'todo_uuid': todo,
        'plan_block_id': plan,
        'start_time':
            start ?? day.add(const Duration(hours: 10)).millisecondsSinceEpoch,
        'end_time':
            end ??
            day
                .add(const Duration(hours: 10, minutes: 20))
                .millisecondsSinceEpoch,
        'planned_duration': 1200,
        'actual_duration': actual,
        'status': 'completed',
        'created_at': 1,
        'updated_at': 1,
      })
      .then((_) {});
  Future<void> unchanged(List<Map<String, Object?>> before) async {
    expect(await f.db.query('todo_plan_blocks', orderBy: 'uuid'), before);
    expect(await f.db.query('op_logs'), isEmpty);
  }

  setUp(() async {
    f = PlanAvailabilityFixture();
    await f.initialize();
    clock = PlanAvailabilityFixture.now;
    repo = PlanCleanupRepository(databaseOverride: f.db, clock: () => clock);
    await f.db.update(
      'todos',
      {'is_completed': 1},
      where: 'uuid=?',
      whereArgs: [todoId],
    );
  });
  tearDown(() async => f.dispose());

  test('preview is read-only; selected cancellation preserves all fields; exact retry writes nothing', () async {
    await block('a', calendar: 'phone-1');
    await block('b', start: day.add(const Duration(hours: 11)));
    await block('c', start: day.add(const Duration(hours: 12)));
    final before = await f.db.query('todo_plan_blocks', orderBy: 'uuid');
    final page = await repo.read(user);
    expect(page.rows.single.count, 3);
    expect(page.rows.single.eligible, 3);
    final req = await request({'a', 'b'});
    expect(req.hasCalendarCopy, isTrue);
    expect(req.unionMinutes, 90);
    await unchanged(before);
    var refresh = 0;
    void listener() => refresh++;
    StorageService.scopedDataRefreshNotifier.addListener(listener);
    try {
      final saved = await repo.cancel(req, sync: false);
      expect(
        saved.map((r) => r.status),
        everyElement(TodoPlanStatus.cancelled),
      );
      await Future<void>.delayed(const Duration(milliseconds: 250));
      expect(refresh, 1);
      final after = await f.db.query('todo_plan_blocks', orderBy: 'uuid');
      for (var i = 0; i < after.length; i++) {
        expect(after[i], i < 2 ? req.cancelledRow(before[i]) : before[i]);
      }
      expect((await f.db.query('op_logs')).length, 2);
      await repo.cancel(req, sync: false);
      await Future<void>.delayed(const Duration(milliseconds: 250));
      expect(await f.db.query('todo_plan_blocks', orderBy: 'uuid'), after);
      expect((await f.db.query('op_logs')).length, 2);
      expect(refresh, 1);
    } finally {
      StorageService.scopedDataRefreshNotifier.removeListener(listener);
    }
  });
  test('overlapping intervals are counted as a union', () async {
    await block('a');
    await block('b', start: day.add(const Duration(hours: 10, minutes: 15)));
    expect((await request()).unionMinutes, 60);
  });
  test('maxed plan counters are not offered for cancellation', () async {
    const maximum = 9223372036854775807;
    await block('max-version');
    await block('max-updated', start: day.add(const Duration(hours: 11)));
    await f.db.update(
      'todo_plan_blocks',
      {'version': maximum},
      where: 'uuid=?',
      whereArgs: ['max-version'],
    );
    await f.db.update(
      'todo_plan_blocks',
      {'updated_at': maximum},
      where: 'uuid=?',
      whereArgs: ['max-updated'],
    );

    final snapshot = await repo.detail(user, todoId);

    for (final id in ['max-version', 'max-updated']) {
      final item = snapshot.rows.singleWhere((row) => row.id == id);
      expect(item.eligible, isFalse);
      expect(item.reason, '规划时间或版本需核对');
    }
  });
  test('near-limit plan counters still allow an exact retry', () async {
    const maximum = 9223372036854775807;
    await block('near-limit');
    await f.db.update(
      'todo_plan_blocks',
      {'version': maximum - 1, 'updated_at': maximum - 1},
      where: 'uuid=?',
      whereArgs: ['near-limit'],
    );
    final req = await request();

    await repo.cancel(req, sync: false);
    await repo.cancel(req, sync: false);

    final row = (await f.db.query(
      'todo_plan_blocks',
      where: 'uuid=?',
      whereArgs: ['near-limit'],
    )).single;
    expect(row['status'], TodoPlanStatus.cancelled.index);
    expect(row['version'], maximum);
    expect(row['updated_at'], maximum);
    expect((await f.db.query('op_logs')).length, 1);
  });
  test(
    'stale reminder maintenance cannot revive cancellation or other sources',
    () async {
      await block('a');
      await block('b', start: day.add(const Duration(hours: 12)));
      final stale = TodoPlanBlock.fromJson(
        (await f.db.query(
          'todo_plan_blocks',
          where: 'uuid=?',
          whereArgs: ['a'],
        )).single,
      );
      await repo.cancel(await request({'a'}), sync: false);
      stale.status = TodoPlanStatus.reminded;
      stale.markAsChanged();
      await StorageService.savePlanBlocks(user, [stale], sync: false);
      expect(
        (await f.db.query(
          'todo_plan_blocks',
          where: 'uuid=?',
          whereArgs: ['a'],
        )).single['status'],
        3,
      );
      expect((await f.db.query('op_logs')).length, 1);
      final reminders = await PlanReminderGuard.filterSchedulablePlanReminders([
        {'type': 'plan_block', 'planBlockId': 'a', 'notifId': 33001},
        {'type': 'plan_block', 'planBlockId': 'b', 'notifId': 33002},
        {'type': 'pomodoro', 'planBlockId': 'a', 'notifId': 40001},
        {'type': 'habit', 'planBlockId': 'a', 'notifId': 42001},
      ], databaseOverride: f.db);
      expect(reminders.map((r) => r['notifId']), [33002, 40001, 42001]);
    },
  );
  test(
    'queued plan alarms remain only for planned, delayed and reminded blocks',
    () async {
      for (final status in TodoPlanStatus.values) {
        await block(status.name, status: status);
      }
      final reminders = await PlanReminderGuard.filterSchedulablePlanReminders([
        for (var i = 0; i < TodoPlanStatus.values.length; i++)
          {
            'type': 'plan_block',
            'planBlockId': TodoPlanStatus.values[i].name,
            'notifId': 33001 + i,
          },
      ], databaseOverride: f.db);
      expect(reminders.map((r) => r['planBlockId']), [
        'planned',
        'delayed',
        'reminded',
      ]);
    },
  );
  test('malformed and unknown plan reminder ids are dropped without affecting other sources', () async {
    final reminders = await PlanReminderGuard.filterSchedulablePlanReminders([
      {'type': 'plan_block', 'notifId': 33001},
      {'type': 'plan_block', 'planBlockId': '   ', 'notifId': 33002},
      {'type': 'plan_block', 'planBlockId': 'missing', 'notifId': 33003},
      {'type': 'pomodoro', 'planBlockId': 'missing', 'notifId': 40001},
      {'type': 'habit', 'planBlockId': 'missing', 'notifId': 42001},
    ], databaseOverride: f.db);
    expect(reminders.map((r) => r['notifId']), [40001, 42001]);
  });
  test(
    'reminder state updates still work for an active plan and write one oplog',
    () async {
      await block('a');
      final plan = TodoPlanBlock.fromJson(
        (await f.db.query('todo_plan_blocks')).single,
      );
      plan.status = TodoPlanStatus.reminded;
      plan.markAsChanged();
      await StorageService.savePlanBlocks(user, [plan], sync: false);
      expect((await f.db.query('todo_plan_blocks')).single['status'], 4);
      expect((await f.db.query('op_logs')).length, 1);
    },
  );
  test(
    'an exact retry remains idempotent after the cancelled plan start passes',
    () async {
      await block('a');
      final req = await request();
      await repo.cancel(req, sync: false);

      clock = day.add(const Duration(hours: 10, minutes: 1));
      final retried = await repo.cancel(req, sync: false);

      expect(retried.single.status, TodoPlanStatus.cancelled);
      expect((await f.db.query('op_logs')).length, 1);
      expect(
        (await f.db.query('todo_plan_blocks')).single['version'],
        (req.rows.single['version'] as int) + 1,
      );
    },
  );
  for (final table in ['todo_plan_blocks', 'op_logs']) {
    test('second $table failure rolls back the whole cancellation', () async {
      await block('a');
      await block('b');
      final req = await request(),
          before = await f.db.query('todo_plan_blocks', orderBy: 'uuid');
      await f.db.execute(
        table == 'op_logs'
            ? "CREATE TRIGGER fault BEFORE INSERT ON op_logs WHEN NEW.target_uuid='b' BEGIN SELECT RAISE(ABORT,'fault'); END"
            : "CREATE TRIGGER fault BEFORE UPDATE ON todo_plan_blocks WHEN NEW.uuid='b' BEGIN SELECT RAISE(ABORT,'fault'); END",
      );
      await expectLater(repo.cancel(req, sync: false), throwsA(anything));
      await unchanged(before);
    });
  }
  for (final change in [
    'new-plan',
    'plan-time',
    'plan-delete',
    'plan-note',
    'record',
    'todo-undone',
    'todo-delete',
    'todo-conflict',
    'team',
    'member',
    'account',
    'clock',
  ]) {
    test('late $change rejects the entire reviewed set', () async {
      await block('a');
      await block('b');
      final req = await request();
      switch (change) {
        case 'new-plan':
          await block('c');
        case 'plan-time':
          await f.db.update(
            'todo_plan_blocks',
            {'start_time': day.millisecondsSinceEpoch},
            where: 'uuid=?',
            whereArgs: ['b'],
          );
        case 'plan-delete':
          await f.db.update(
            'todo_plan_blocks',
            {'is_deleted': 1},
            where: 'uuid=?',
            whereArgs: ['b'],
          );
        case 'plan-note':
          await f.db.update(
            'todo_plan_blocks',
            {'remark': '他端修改'},
            where: 'uuid=?',
            whereArgs: ['b'],
          );
        case 'record':
          await record('new-record', plan: 'b');
        case 'todo-undone':
          await f.db.update('todos', {'is_completed': 0});
        case 'todo-delete':
          await f.db.update('todos', {'is_deleted': 1});
        case 'todo-conflict':
          await f.db.update('todos', {'has_conflict': 1});
        case 'team':
          await f.db.update('todos', {'team_uuid': 'team-1'});
        case 'member':
          await (await SharedPreferences.getInstance()).setInt(
            'current_user_id',
            3,
          );
        case 'account':
          await (await SharedPreferences.getInstance()).setString(
            'current_login_user',
            'other',
          );
        case 'clock':
          clock = day.add(const Duration(hours: 10));
      }
      final before = await f.db.query('todo_plan_blocks', orderBy: 'uuid');
      await expectLater(repo.cancel(req, sync: false), throwsA(anything));
      await unchanged(before);
    });
  }
  test('partial cancellation and changed committed result are not accepted as retry', () async {
    await block('a');
    await block('b');
    final req = await request();
    await f.db.update(
      'todo_plan_blocks',
      {'status': 3},
      where: 'uuid=?',
      whereArgs: ['a'],
    );
    await expectLater(repo.cancel(req, sync: false), throwsA(anything));
    expect(await f.db.query('op_logs'), isEmpty);
    await f.db.update(
      'todo_plan_blocks',
      {'status': 0},
      where: 'uuid=?',
      whereArgs: ['a'],
    );
    await repo.cancel(req, sync: false);
    await f.db.update(
      'todo_plan_blocks',
      {'remark': '取消后他端又编辑'},
      where: 'uuid=?',
      whereArgs: ['a'],
    );
    final before = await f.db.query('todo_plan_blocks');
    await expectLater(repo.cancel(req, sync: false), throwsA(anything));
    expect(await f.db.query('todo_plan_blocks'), before);
    expect((await f.db.query('op_logs')).length, 2);
  });
  test('zero-second, deleted, mismatched and unbound overlapping records all block cancellation', () async {
    for (final id in ['direct', 'mismatch', 'overlap', 'deleted', 'dangling']) {
      await block(id);
    }
    await record('r0', plan: 'direct');
    await record('r1', plan: 'mismatch', todo: 'different-todo');
    await record('r2', plan: null);
    await record('r3', plan: 'deleted', todo: null);
    await f.db.update(
      'pomodoro_records',
      {'is_deleted': 1},
      where: 'uuid=?',
      whereArgs: ['r3'],
    );
    await f.db.update(
      'todo_plan_blocks',
      {'pomodoro_record_ids': 'missing-record'},
      where: 'uuid=?',
      whereArgs: ['dangling'],
    );
    final snapshot = await repo.detail(user, todoId);
    expect(snapshot.eligible, 0);
    expect(snapshot.rows.every((r) => !r.eligible), isTrue);
    expect(() => snapshot.select({'direct'}, clock), throwsA(anything));
  });
  test(
    'invalid recorded times and orphan plan ownership are conservative errors',
    () async {
      await block('a');
      await record('broken', plan: null, start: 0, end: 0);
      expect((await repo.detail(user, todoId)).eligible, 0);
      await f.db.delete('pomodoro_records');
      await record('orphan', plan: 'not-a-real-plan');
      expect((await repo.detail(user, todoId)).eligible, 0);
    },
  );
  test('only future eligible statuses; started, cache evidence and corrupt plans disabled', () async {
    for (final status in TodoPlanStatus.values) {
      await block(status.name, status: status);
    }
    await block('begun', start: clock.subtract(const Duration(minutes: 10)));
    await block('cache');
    await f.db.update(
      'todo_plan_blocks',
      {'actual_focus_seconds': 1},
      where: 'uuid=?',
      whereArgs: ['cache'],
    );
    await block('invalid');
    await f.db.update(
      'todo_plan_blocks',
      {'planned_minutes': 10},
      where: 'uuid=?',
      whereArgs: ['invalid'],
    );
    final snapshot = await repo.detail(user, todoId);
    expect(snapshot.rows.where((r) => r.eligible).map((r) => r.id).toSet(), {
      'planned',
      'reminded',
      'delayed',
    });
    expect(snapshot.rows.any((r) => r.id == 'finished'), isFalse);
  });
  test(
    'paused focus blocks the whole task; corrupt run state is a visible error',
    () async {
      await block('a');
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'pomodoro_run_state_$user',
        jsonEncode(
          PomodoroRunState(
            phase: PomodoroPhase.focusing,
            isPaused: true,
            todoUuid: todoId,
          ).toJson(),
        ),
      );
      final snapshot = await repo.detail(user, todoId);
      expect(snapshot.eligible, 0);
      expect(snapshot.blockedReason, contains('专注'));
      await prefs.setString('pomodoro_run_state_$user', 'broken');
      await expectLater(repo.detail(user, todoId), throwsA(anything));
    },
  );
  test('team and independent member completions are read-only; no series/title merge', () async {
    await block('a');
    await f.todo('same-title', '复习高数', done: true);
    await block('same-title-plan', todo: 'same-title');
    await f.todo('team', '团队', done: false);
    await f.db.update(
      'todos',
      {'team_uuid': 'team-uuid', 'collab_type': 1},
      where: 'uuid=?',
      whereArgs: ['team'],
    );
    await f.db.insert('todo_completions', {
      'todo_uuid': 'team',
      'user_id': 0,
      'is_completed': 1,
    });
    await block('team-plan', todo: 'team');
    final page = await repo.read(user);
    expect(page.rows.length, 3);
    expect(page.rows.firstWhere((r) => r.id == 'team').eligible, 0);
    final snapshot = await repo.detail(user, 'team');
    expect(snapshot.blockedReason, contains('团队'));
    await repo.cancel(await request({'a'}), sync: false);
    expect(
      (await f.db.query(
        'todo_plan_blocks',
        where: 'uuid=?',
        whereArgs: ['same-title-plan'],
      )).single['status'],
      0,
    );
  });
  test('pagination is bounded, literal search and orphan folders are normalized; writes restart cursors', () async {
    await f.db.transaction((tx) async {
      for (var i = 0; i < 110; i++) {
        final id = 'bulk-${i.toString().padLeft(3, '0')}';
        await tx.insert('todos', {
          'uuid': id,
          'content': i == 0 ? '100%_完成' : '任务$i',
          'is_completed': 1,
          'group_id': 'removed',
          'created_date': 0,
          'created_at': 1,
          'updated_at': 1,
        });
        final start = day.add(Duration(minutes: i));
        await tx.insert(
          'todo_plan_blocks',
          TodoPlanBlock(
            id: 'plan-$id',
            todoId: id,
            titleSnapshot: '',
            startTime: start.millisecondsSinceEpoch,
            endTime: start
                .add(const Duration(minutes: 15))
                .millisecondsSinceEpoch,
            plannedMinutes: 15,
          ).toDbJson(),
        );
      }
    });
    expect((await repo.read(user, search: '%_')).rows.single.id, 'bulk-000');
    var page = await repo.read(user, folder: '');
    expect(page.total, 110);
    final ids = <String>{};
    while (true) {
      expect(page.rows.length, lessThanOrEqualTo(50));
      ids.addAll(page.rows.map((r) => r.id));
      if (page.next == null) break;
      page = await repo.read(user, folder: '', cursor: page.next);
      expect(page.restarted, isFalse);
    }
    expect(ids.length, 110);
    final first = await repo.read(user);
    await f.db.update(
      'todos',
      {'content': 'changed'},
      where: 'uuid=?',
      whereArgs: ['bulk-000'],
    );
    expect((await repo.read(user, cursor: first.next)).restarted, isTrue);
  });
  test('detail paging restarts after source changes or time crossing; cannot select unseen rows', () async {
    for (var i = 0; i < 52; i++) {
      await block(
        'p-${i.toString().padLeft(2, '0')}',
        start: day.add(Duration(minutes: i)),
      );
    }
    final first = await repo.detail(user, todoId);
    expect(first.rows.length, 50);
    expect(() => first.select({'p-51'}, clock), throwsA(anything));
    final next = await repo.detail(user, todoId, cursor: first.next);
    expect(next.rows.length, 2);
    expect(next.restarted, isFalse);
    clock = day;
    expect(
      (await repo.detail(user, todoId, cursor: first.next)).restarted,
      isTrue,
    );
  });
  test(
    'pending legacy data and source failure never become empty or eligible',
    () async {
      await block('a');
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList('user_todos_$user', ['legacy']);
      await expectLater(repo.read(user), throwsA(anything));
      await prefs.remove('user_todos_$user');
      await prefs.setString('pomodoro_records_$user', '[{"uuid":"legacy"}]');
      await expectLater(repo.detail(user, todoId), throwsA(anything));
      await prefs.remove('pomodoro_records_$user');
      await f.db.execute('DROP TABLE pomodoro_records');
      await expectLater(repo.detail(user, todoId), throwsA(anything));
    },
  );
}
