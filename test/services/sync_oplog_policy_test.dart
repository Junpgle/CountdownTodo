import 'package:countdown_todo/services/sync_oplog_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SyncOplogPolicy', () {
    test('only operations present in the request snapshot are acknowledged',
        () {
      const requestSnapshot = [
        SyncOplogEntry(id: 1, table: 'todos', uuid: 'yesterday'),
        SyncOplogEntry(id: 2, table: 'todo_groups', uuid: 'group-1'),
      ];

      final resolution = SyncOplogPolicy.resolveRequestSnapshot(
        requestSnapshot: requestSnapshot,
        blockingConflictUuids: const {},
        acknowledgeFixedScheduleOps: true,
        acknowledgeHabitOps: true,
      );

      expect(resolution.acknowledgedIds, {1, 2});
      expect(resolution.acknowledgedIds, isNot(contains(3)));
    });

    test('an operation created during sync remains pending and protected', () {
      const requestSnapshot = [
        // 请求携带的是 today 在勾选前的旧操作。
        SyncOplogEntry(id: 10, table: 'todos', uuid: 'today'),
      ];
      const currentPending = [
        // 请求期间用户勾选完成，同一 UUID 产生了新 oplog。
        SyncOplogEntry(id: 11, table: 'todos', uuid: 'today'),
      ];

      final inFlightUuids = SyncOplogPolicy.todoUuidsCreatedAfterSnapshot(
        requestSnapshot: requestSnapshot,
        currentPending: currentPending,
      );

      expect(inFlightUuids, {'today'});
      expect(
        SyncOplogPolicy.shouldProtectTodoMerge(
          'today',
          forceFlushUuids: const {},
          inFlightMutationUuids: inFlightUuids,
        ),
        isTrue,
      );
    });

    test('blocking conflicts and unsupported tables are not acknowledged', () {
      const requestSnapshot = [
        SyncOplogEntry(id: 20, table: 'todos', uuid: 'conflicted'),
        SyncOplogEntry(id: 21, table: 'fixed_schedules', uuid: 'schedule'),
        SyncOplogEntry(id: 22, table: 'pomodoro_records', uuid: 'pomodoro'),
        SyncOplogEntry(id: 23, table: 'habit_goals', uuid: 'habit-goal'),
      ];

      final resolution = SyncOplogPolicy.resolveRequestSnapshot(
        requestSnapshot: requestSnapshot,
        blockingConflictUuids: const {'conflicted'},
        acknowledgeFixedScheduleOps: false,
        acknowledgeHabitOps: false,
      );

      expect(resolution.acknowledgedIds, isEmpty);
      expect(resolution.blockedIds, {20});
    });

    test('habit ops are acknowledged only when the server declares habits v1',
        () {
      const requestSnapshot = [
        SyncOplogEntry(id: 30, table: 'habit_goals', uuid: 'goal-1'),
        SyncOplogEntry(
            id: 31, table: 'habit_goal_rule_revisions', uuid: 'rule-1'),
        SyncOplogEntry(id: 32, table: 'habit_checkins', uuid: 'checkin-1'),
      ];

      final resolution = SyncOplogPolicy.resolveRequestSnapshot(
        requestSnapshot: requestSnapshot,
        blockingConflictUuids: const {},
        acknowledgeFixedScheduleOps: true,
        acknowledgeHabitOps: true,
      );

      expect(resolution.acknowledgedIds, {30, 31, 32});

      final oldServer = SyncOplogPolicy.resolveRequestSnapshot(
        requestSnapshot: requestSnapshot,
        blockingConflictUuids: const {},
        acknowledgeFixedScheduleOps: true,
        acknowledgeHabitOps: false,
      );

      expect(oldServer.acknowledgedIds, isEmpty);
    });

    test('sleep coaching ops stay pending without explicit server support', () {
      const requestSnapshot = [
        SyncOplogEntry(
          id: 40,
          table: 'habit_sleep_coaching_plans',
          uuid: 'plan-1',
        ),
      ];

      final oldServer = SyncOplogPolicy.resolveRequestSnapshot(
        requestSnapshot: requestSnapshot,
        blockingConflictUuids: const {},
        acknowledgeFixedScheduleOps: true,
        acknowledgeHabitOps: true,
      );
      expect(oldServer.acknowledgedIds, isEmpty);

      final newServer = SyncOplogPolicy.resolveRequestSnapshot(
        requestSnapshot: requestSnapshot,
        blockingConflictUuids: const {},
        acknowledgeFixedScheduleOps: true,
        acknowledgeHabitOps: true,
        acknowledgeSleepCoachingOps: true,
      );
      expect(newServer.acknowledgedIds, {40});
    });
  });
}
