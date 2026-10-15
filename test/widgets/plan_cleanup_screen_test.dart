import 'package:countdown_todo/models.dart';
import 'package:countdown_todo/models/plan_cleanup.dart';
import 'package:countdown_todo/screens/plan_cleanup_screen.dart';
import 'package:countdown_todo/services/plan_cleanup_repository.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/plan_availability_fixture.dart';

class _NoSyncCleanupRepository extends PlanCleanupRepository {
  _NoSyncCleanupRepository(PlanAvailabilityFixture fixture)
    : super(
        databaseOverride: fixture.db,
        clock: () => PlanAvailabilityFixture.now,
      );

  @override
  Future<List<TodoPlanBlock>> cancel(
    PlanCleanupRequest request, {
    bool sync = true,
  }) => super.cancel(request, sync: false);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late PlanAvailabilityFixture fixture;

  setUp(() async {
    fixture = PlanAvailabilityFixture();
    await fixture.initialize();
    debugDefaultTargetPlatformOverride = null;
    await fixture.db.update('todos', {'is_completed': 1});
    await fixture.block(
      TodoPlanBlock(
        id: 'cleanup-ui-plan',
        todoId: 'todo-target',
        startTime: PlanAvailabilityFixture.day
            .add(const Duration(hours: 10))
            .millisecondsSinceEpoch,
        endTime: PlanAvailabilityFixture.day
            .add(const Duration(hours: 10, minutes: 45))
            .millisecondsSinceEpoch,
        plannedMinutes: 45,
        calendarEventId: 'phone-event',
        reminderMinutes: 15,
      ),
    );
  });

  tearDown(() async => fixture.dispose());

  testWidgets(
    'confirms the reviewed item, reports calendar limits and retries reminders',
    (tester) async {
      var reminderAttempts = 0;
      Future<void> updateReminders() async {
        reminderAttempts++;
        if (reminderAttempts == 1) throw StateError('notification fault');
      }

      await tester.pumpWidget(
        MaterialApp(
          home: PlanCleanupScreen(
            username: PlanAvailabilityFixture.username,
            todoId: 'todo-target',
            repository: _NoSyncCleanupRepository(fixture),
            clock: () => PlanAvailabilityFixture.now,
            updateReminders: updateReminders,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('已选1段 · 45分钟'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('cleanup-cancel')));
      await tester.pumpAndSettle();
      expect(find.textContaining('手机日历副本不会随本次操作删除'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('cleanup-confirm')));
      await tester.pumpAndSettle();

      expect(find.text('已取消1段'), findsOneWidget);
      expect(find.textContaining('应用内释放45分钟规划时段'), findsOneWidget);
      expect(find.textContaining('规划已取消，提醒更新失败'), findsOneWidget);
      expect((await fixture.db.query('todo_plan_blocks')).single['status'], 3);
      expect((await fixture.db.query('op_logs')).length, 1);

      await tester.tap(find.byKey(const ValueKey('cleanup-retry-reminders')));
      await tester.pumpAndSettle();
      expect(reminderAttempts, 2);
      expect(find.text('应用提醒已更新'), findsOneWidget);
      expect((await fixture.db.query('op_logs')).length, 1);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
