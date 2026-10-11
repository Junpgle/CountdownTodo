import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:countdown_todo/models.dart';
import 'package:countdown_todo/services/plan_todo_guard.dart';
import 'package:countdown_todo/services/pomodoro_service.dart';
import 'package:countdown_todo/storage_service.dart';

import '../support/plan_availability_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late PlanAvailabilityFixture f;
  late PlanTodoIdentity identity;
  setUp(() async {
    f = PlanAvailabilityFixture();
    await f.initialize();
    identity = await PlanTodoIdentity.capture(PlanAvailabilityFixture.username);
  });
  tearDown(() async => f.dispose());
  final now = PlanAvailabilityFixture.now;
  final start = PlanAvailabilityFixture.day.add(const Duration(hours: 10));
  TodoPlanBlock draft(String id) => TodoPlanBlock(
    id: id,
    todoId: 'todo-target',
    startTime: start.millisecondsSinceEpoch,
    endTime: start.add(const Duration(hours: 1)).millisecondsSinceEpoch,
  );
  test('new arrangements after confirmation reject atomically, explicit fingerprint permits append', () async {
    final context = PlanBacklogSaveContext(
      identity,
      'todo-target',
      await PlanTodoGuard.arrangements(f.db, 'todo-target', now),
    );
    await f.block(draft('other-device'));
    final before = await f.db.query('op_logs');
    await expectLater(
      StorageService.savePlanBlockEdited(
        PlanAvailabilityFixture.username,
        draft('local-draft'),
        sync: false,
        beforeWrite: (txn) => PlanTodoGuard.validateBacklog(
          txn,
          context,
          context.arrangements,
          start,
          now,
        ),
      ),
      throwsA(anything),
    );
    expect((await f.db.query('todo_plan_blocks')).length, 1);
    expect(await f.db.query('op_logs'), before);
    final allowed = await PlanTodoGuard.arrangements(f.db, 'todo-target', now);
    await StorageService.savePlanBlockEdited(
      PlanAvailabilityFixture.username,
      draft('local-draft'),
      sync: false,
      beforeWrite: (txn) =>
          PlanTodoGuard.validateBacklog(txn, context, allowed, start, now),
    );
    expect((await f.db.query('todo_plan_blocks')).length, 2);
    expect((await f.db.query('op_logs')).length, before.length + 1);
    await f.db.update(
      'todo_plan_blocks',
      {'end_time': start.add(const Duration(hours: 2)).millisecondsSinceEpoch},
      where: 'uuid=?',
      whereArgs: ['other-device'],
    );
    await expectLater(
      PlanTodoGuard.validateBacklog(f.db, context, allowed, start, now),
      throwsA(anything),
    );
  });
  for (final field in ['is_completed', 'is_deleted', 'has_conflict']) {
    test('$field cannot be bypassed by append', () async {
      final context = PlanBacklogSaveContext(identity, 'todo-target', '[]');
      await f.db.update('todos', {field: 1});
      await expectLater(
        PlanTodoGuard.validateBacklog(f.db, context, '[]', start, now),
        throwsA(anything),
      );
    });
  }
  test(
    'paused focus blocks new manual plans even after original period ended',
    () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'pomodoro_run_state_${identity.username}',
        jsonEncode(
          PomodoroRunState(
            phase: PomodoroPhase.focusing,
            isPaused: true,
            todoUuid: 'todo-target',
          ).toJson(),
        ),
      );
      await expectLater(
        PlanTodoGuard.validate(f.db, identity, 'todo-target'),
        throwsA(anything),
      );
    },
  );
  test('member switch invalidates captured identity and independent override is consistent', () async {
    await f.db.update('todos', {'collab_type': 1, 'is_completed': 1});
    await f.db.insert('todo_completions', {
      'todo_uuid': 'todo-target',
      'user_id': 0,
      'is_completed': 0,
    });
    expect(
      (await PlanTodoGuard.read(f.db, identity, 'todo-target')).isDone,
      false,
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('current_user_id', 1);
    await expectLater(
      PlanTodoGuard.validate(f.db, identity, 'todo-target'),
      throwsA(anything),
    );
  });
  test('failed op-log insertion rolls back plan with guard in the same transaction', () async {
    await f.db.execute(
      "CREATE TRIGGER fail_log BEFORE INSERT ON op_logs BEGIN SELECT RAISE(ABORT,'synthetic'); END",
    );
    await expectLater(
      StorageService.savePlanBlockEdited(
        identity.username,
        draft('rollback'),
        sync: false,
        beforeWrite: (txn) =>
            PlanTodoGuard.validate(txn, identity, 'todo-target'),
      ),
      throwsA(anything),
    );
    expect(await f.db.query('todo_plan_blocks'), isEmpty);
    expect(await f.db.query('op_logs'), isEmpty);
  });
}
