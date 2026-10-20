import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:countdown_todo/models.dart';
import 'package:countdown_todo/services/database_helper.dart';
import 'package:countdown_todo/storage_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  test('rejects skipping a one-off todo before opening storage', () async {
    await expectLater(
      StorageService.saveTodos('default', [
        TodoItem(title: '一次性待办', isSkipped: true),
      ]),
      throwsArgumentError,
    );
  });

  test('persists skip state and pending sync per collaboration mode', () async {
    final username = 'skip_state_${DateTime.now().microsecondsSinceEpoch}';
    SharedPreferences.setMockInitialValues({
      'current_login_user': username,
      'current_user_id': 77,
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('current_login_user', username);
    await prefs.setInt('current_user_id', 77);

    final start = DateTime(2026, 10, 20, 9);
    final local = TodoItem(
      id: 'skip-personal',
      title: '个人重复任务',
      recurrence: RecurrenceType.weekly,
      recurrenceSeriesId: 'series-personal',
      createdDate: start.millisecondsSinceEpoch,
      dueDate: start.add(const Duration(hours: 2)),
      isSkipped: true,
    );
    final independent = TodoItem(
      id: 'skip-independent',
      title: '成员独立重复任务',
      recurrenceSeriesId: 'series-team',
      createdDate: start.millisecondsSinceEpoch,
      dueDate: start.add(const Duration(hours: 2)),
      collabType: 1,
      isSkipped: true,
    );

    await StorageService.saveTodos(
      username,
      [local, independent],
      sync: false,
      recomputeScheduleConflicts: false,
    );

    final todos = await StorageService.getTodos(username);
    final personal = todos.singleWhere((todo) => todo.id == local.id);
    final member = todos.singleWhere((todo) => todo.id == independent.id);
    expect(personal.isSkipped, isTrue);
    expect(personal.isSkippedSyncPending, isTrue);
    expect(member.isSkipped, isTrue);
    expect(member.isSkippedSyncPending, isTrue);

    final db = await DatabaseHelper.instance.databaseForUser(username);
    final personalRow = (await db.query(
      'todos',
      columns: const ['is_skipped', 'is_skipped_sync_pending'],
      where: 'uuid = ?',
      whereArgs: [local.id],
    )).single;
    final memberRow = (await db.query(
      'todo_completions',
      columns: const ['is_skipped', 'is_skipped_sync_pending'],
      where: 'todo_uuid = ? AND user_id = ?',
      whereArgs: [independent.id, 77],
    )).single;
    expect(personalRow['is_skipped'], 1);
    expect(personalRow['is_skipped_sync_pending'], 1);
    expect(memberRow['is_skipped'], 1);
    expect(memberRow['is_skipped_sync_pending'], 1);
  });
}
