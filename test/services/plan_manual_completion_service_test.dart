@TestOn('vm')
library;

import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import 'package:countdown_todo/models.dart';
import 'package:countdown_todo/models/plan_availability.dart';
import 'package:countdown_todo/services/plan_manual_completion_service.dart';
import 'package:countdown_todo/services/plan_review_repository.dart';
import 'package:countdown_todo/services/pomodoro_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/plan_availability_fixture.dart';

class _LostReplyDatabase implements Database {
  _LostReplyDatabase(this.inner);
  final Database inner;
  bool loseReply = false;
  @override
  Future<T> transaction<T>(
    Future<T> Function(Transaction txn) action, {
    bool? exclusive,
  }) async {
    final result = await inner.transaction(action, exclusive: exclusive);
    if (loseReply) {
      loseReply = false;
      throw StateError('synthetic committed response lost');
    }
    return result;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const user = PlanAvailabilityFixture.username;
  late PlanAvailabilityFixture f;
  late PlanManualCompletionService service;
  late DateTime now;
  late TodoPlanBlock original;
  Future<Map<String, Object?>> row() async => (await f.db.query(
    'todo_plan_blocks',
    where: 'uuid=?',
    whereArgs: ['manual'],
  )).single;
  Future<int> logs() async => (await f.db.query('op_logs')).length;
  Future<PlanManualCompletionRequest> prepare() =>
      service.prepare(user, 'manual');
  Future<PlanManualCompletionReceipt> finish() async =>
      service.confirm(await prepare(), sync: false);
  Future<void> focus(
    String id, {
    String? plan = 'manual',
    String todo = 'todo-target',
    int? start,
  }) async {
    final a = start ?? DateTime(2026, 10, 8, 9, 10).millisecondsSinceEpoch;
    await f.db.insert('pomodoro_records', {
      'uuid': id,
      'todo_uuid': todo,
      'todo_title': '相同标题',
      'plan_block_id': plan,
      'start_time': a,
      'end_time': a + 60000,
      'actual_duration': 40,
      'planned_duration': 1500,
      'status': 'completed',
      'version': 1,
      'updated_at': 1,
      'created_at': 1,
      'tag_uuids': '[]',
    });
  }

  Map<String, Object?> business(Map<String, Object?> r) => {...r}
    ..remove('status')
    ..remove('version')
    ..remove('updated_at');
  setUp(() async {
    f = PlanAvailabilityFixture();
    await f.initialize();
    now = DateTime(2026, 10, 8, 12);
    service = PlanManualCompletionService(
      databaseOverride: f.db,
      clock: () => now,
    );
    original = TodoPlanBlock(
      id: 'manual',
      todoId: 'todo-target',
      titleSnapshot: '整理材料',
      startTime: DateTime(2026, 10, 8, 9).millisecondsSinceEpoch,
      endTime: DateTime(2026, 10, 8, 10).millisecondsSinceEpoch,
      plannedMinutes: 60,
      status: TodoPlanStatus.missed,
      actualFocusSeconds: 99999,
      remark: '保留备注',
      reminderMinutes: 10,
      pomodoroRounds: 2,
      calendarEventId: 'keep-calendar',
      pomodoroRecordIds: ['legacy'],
    );
    await f.block(original);
  });
  tearDown(() => f.dispose());

  test('prepare is read only; confirm and undo only change status and version metadata', () async {
    final before = await row();
    final request = await prepare();
    expect(await row(), before);
    expect(await logs(), 0);
    final receipt = await service.confirm(request, sync: false);
    final completed = await row();
    expect(completed['status'], TodoPlanStatus.finished.index);
    expect(completed['version'], original.version + 1);
    expect(business(completed), business(before));
    expect(await logs(), 1);
    expect((await f.db.query('todos')).single['is_completed'], 0);
    expect(await f.db.query('pomodoro_records'), isEmpty);
    expect(await f.db.query('time_logs'), isEmpty);
    final afterUndo = await service.undo(receipt, sync: false);
    expect(afterUndo.status, TodoPlanStatus.missed);
    expect((await row())['version'], original.version + 2);
    expect(business(await row()), business(before));
    expect(await logs(), 2);
    await expectLater(
      service.undo(receipt, sync: false),
      throwsA(isA<PlanAvailabilityException>()),
    );
    expect(await logs(), 2);
  });
  test('finished count changes but verified focus and budget do not', () async {
    await focus('a');
    await focus('b');
    final review = PlanReviewRepository(
      databaseOverride: f.db,
      clock: () => now,
    );
    final before = await review.readTodayCard(user);
    await finish();
    final after = await review.readTodayCard(user);
    expect(before.overview.actual('seconds'), 80);
    expect(after.overview.actual('seconds'), 80);
    expect(after.overview.plan('seconds'), before.overview.plan('seconds'));
    expect(after.overview.plan('done'), before.overview.plan('done') + 1);
  });
  test(
    'a plan linked to a team todo can be confirmed without changing the todo',
    () async {
      await f.db.update('todos', {
        'is_completed': 1,
        'team_uuid': 'team',
        'collab_type': 1,
      });
      await service.confirm(await prepare(), sync: false);
      expect((await row())['status'], TodoPlanStatus.finished.index);
      expect((await f.db.query('todos')).single['is_completed'], 1);
    },
  );
  for (final state in [
    TodoPlanStatus.planned,
    TodoPlanStatus.reminded,
    TodoPlanStatus.delayed,
    TodoPlanStatus.missed,
  ]) {
    test('ended ${state.name} can be confirmed', () async {
      await f.db.update('todo_plan_blocks', {'status': state.index});
      await finish();
      expect((await row())['status'], 1);
    });
  }
  for (final status in [1, 3, 5, 7, 99]) {
    test('status $status cannot be manually completed', () async {
      await f.db.update('todo_plan_blocks', {'status': status});
      await expectLater(prepare(), throwsA(anything));
      expect(await logs(), 0);
    });
  }
  for (final change in <Map<String, Object?>>[
    {'end_time': DateTime(2026, 10, 8, 13).millisecondsSinceEpoch},
    {'start_time': 0},
    {'end_time': 1},
    {'start_time': 'broken'},
    {'is_deleted': 1},
    {'version': -1},
  ]) {
    test('invalid or unfinished interval $change is rejected', () async {
      await f.db.update('todo_plan_blocks', change);
      await expectLater(prepare(), throwsA(anything));
      expect(await logs(), 0);
    });
  }
  for (final change in <Map<String, Object?>>[
    {'is_deleted': 1},
    {'has_conflict': 1},
  ]) {
    test('deleted or conflicting todo $change is rejected', () async {
      await f.db.update('todos', change);
      await expectLater(prepare(), throwsA(anything));
      expect(await logs(), 0);
    });
  }
  test(
    'mapped and stale editor identities cannot masquerade as a stored block',
    () async {
      await expectLater(
        service.prepare(user, 'mapped_todo_todo-target'),
        throwsA(anything),
      );
      final changed = TodoPlanBlock.fromJson(original.toJson())
        ..remark = 'unsaved';
      await expectLater(
        service.prepare(user, 'manual', expected: changed),
        throwsA(anything),
      );
      expect(await logs(), 0);
    },
  );
  for (final mutation in [
    'block',
    'todo',
    'linked',
    'overlap',
    'legacy',
    'identity',
    'focus',
    'broken-run',
  ]) {
    test('confirmation rejects $mutation changes after preview', () async {
      final request = await prepare();
      final prefs = await SharedPreferences.getInstance();
      switch (mutation) {
        case 'block':
          await f.db.update('todo_plan_blocks', {'remark': 'changed'});
        case 'todo':
          await f.db.update('todos', {'is_completed': 1});
        case 'linked':
          await focus('new');
        case 'overlap':
          await focus('new', plan: null);
        case 'legacy':
          await focus('legacy', plan: null, todo: 'other');
        case 'identity':
          await prefs.setInt('current_user_id', 123);
        case 'focus':
          await prefs.setString(
            'pomodoro_run_state_$user',
            jsonEncode(
              PomodoroRunState(
                phase: PomodoroPhase.focusing,
                isPaused: true,
                todoUuid: original.todoId,
              ).toJson(),
            ),
          );
        case 'broken-run':
          await prefs.setString('pomodoro_run_state_$user', 'broken');
      }
      await expectLater(
        service.confirm(request, sync: false),
        throwsA(anything),
      );
      expect((await row())['status'], 6);
      expect(await logs(), 0);
    });
  }
  test('concurrent same request writes exactly once; a different stale request is rejected', () async {
    final a = await prepare(), b = await prepare();
    final receipts = await Future.wait([
      service.confirm(a, sync: false),
      service.confirm(a, sync: false),
    ]);
    expect(identical(receipts[0], receipts[1]), isTrue);
    expect(await logs(), 1);
    await expectLater(service.confirm(b, sync: false), throwsA(anything));
    expect(await logs(), 1);
  });
  test(
    'oplog abort rolls back the status, and an explicit retry can succeed',
    () async {
      final request = await prepare();
      final before = await row();
      await f.db.execute(
        "CREATE TRIGGER reject_manual BEFORE INSERT ON op_logs BEGIN SELECT RAISE(ABORT, 'synthetic'); END",
      );
      await expectLater(
        service.confirm(request, sync: false),
        throwsA(anything),
      );
      expect(await row(), before);
      expect(await logs(), 0);
      await f.db.execute('DROP TRIGGER reject_manual');
      await service.confirm(request, sync: false);
      expect(await logs(), 1);
    },
  );
  test(
    'undo failure also rolls back, preserves receipt, and retry is atomic',
    () async {
      final receipt = await finish();
      final before = await row();
      await f.db.execute(
        "CREATE TRIGGER reject_manual BEFORE INSERT ON op_logs BEGIN SELECT RAISE(ABORT, 'synthetic'); END",
      );
      await expectLater(service.undo(receipt, sync: false), throwsA(anything));
      expect(await row(), before);
      expect(await logs(), 1);
      await f.db.execute('DROP TRIGGER reject_manual');
      await Future.wait([
        service.undo(receipt, sync: false),
        service.undo(receipt, sync: false),
      ]);
      expect(await logs(), 2);
    },
  );
  for (final mutation in [
    'block',
    'linked',
    'todo',
    'expiry',
    'invalidate',
    'clock-back',
  ]) {
    test('undo rejects $mutation instead of restoring stale data', () async {
      final receipt = await finish();
      switch (mutation) {
        case 'block':
          await f.db.update('todo_plan_blocks', {'remark': 'new remark'});
        case 'linked':
          await focus('after');
        case 'todo':
          await f.db.update('todos', {'is_completed': 1});
        case 'expiry':
          now = now.add(const Duration(seconds: 10));
        case 'invalidate':
          receipt.invalidate();
        case 'clock-back':
          now = now.subtract(const Duration(seconds: 1));
      }
      await expectLater(service.undo(receipt, sync: false), throwsA(anything));
      expect((await row())['status'], 1);
      expect(await logs(), 1);
    });
  }
  test('same-title unrelated and same-task distant history do not contaminate the snapshot', () async {
    final request = await prepare();
    await focus('other', plan: null, todo: 'different');
    await focus(
      'distant',
      plan: null,
      start: DateTime(2025, 1, 1).millisecondsSinceEpoch,
    );
    await service.confirm(request, sync: false);
    expect(await logs(), 1);
  });
  test(
    'lost commit response is not retried as a second write or granted undo',
    () async {
      final proxy = _LostReplyDatabase(f.db);
      service = PlanManualCompletionService(
        databaseOverride: proxy,
        clock: () => now,
      );
      final request = await prepare();
      proxy.loseReply = true;
      await expectLater(
        service.confirm(request, sync: false),
        throwsA(anything),
      );
      expect((await row())['status'], 1);
      expect(await logs(), 1);
      await expectLater(
        service.confirm(request, sync: false),
        throwsA(anything),
      );
      await expectLater(prepare(), throwsA(anything));
      expect(await logs(), 1);
    },
  );

  test('large explicit linkage is streamed in batches, unrelated history not decoded', () async {
    await f.db.transaction((tx) async {
      for (var i = 0; i < 420; i++) {
        await tx.insert('pomodoro_records', {
          'uuid': 'linked$i',
          'todo_uuid': 'todo-target',
          'plan_block_id': 'manual',
          'start_time': 1,
          'end_time': 2,
          'version': 1,
          'planned_duration': 1500,
          'actual_duration': 0,
          'status': 'completed',
          'tag_uuids': '[]',
          'created_at': 1,
          'updated_at': 1,
        });
      }
      for (var i = 0; i < 500; i++) {
        await tx.insert('pomodoro_records', {
          'uuid': 'other$i',
          'todo_uuid': 'other',
          'start_time': 1,
          'end_time': 2,
          'planned_duration': 1500,
          'actual_duration': 0,
          'status': 'completed',
          'tag_uuids': '[]',
          'created_at': 1,
          'updated_at': 1,
        });
      }
    });
    final counts = <int>[];
    service = PlanManualCompletionService(
      databaseOverride: f.db,
      clock: () => now,
      onQuery: (_, n) => counts.add(n),
    );
    await prepare();
    expect(counts, [200, 200, 20]);
    expect(await logs(), 0);
  });
}
