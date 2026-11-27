import 'dart:convert';

import 'package:countdown_todo/services/database_helper.dart';
import 'package:countdown_todo/storage_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  tearDown(() async {
    await DatabaseHelper.instance.closeDatabase();
  });

  test('clearTeamItems soft-deletes team records and queues op_logs in one transaction', () async {
    final username = 'clear_team_${DateTime.now().microsecondsSinceEpoch}';
    SharedPreferences.setMockInitialValues({'current_login_user': username});
    final db = await DatabaseHelper.instance.database;
    final dbPath = db.path;
    addTearDown(() async {
      await DatabaseHelper.instance.closeDatabase();
      await databaseFactory.deleteDatabase(dbPath);
    });

    const teamUuid = 'team-alpha';
    const now = 1700000000000;

    await db.insert('todos', {
      'uuid': 'todo-team',
      'team_uuid': teamUuid,
      'content': 'Team Todo',
      'is_deleted': 0,
      'version': 1,
      'created_at': now,
      'updated_at': now,
    });
    await db.insert('todos', {
      'uuid': 'todo-personal',
      'team_uuid': null,
      'content': 'Personal Todo',
      'is_deleted': 0,
      'version': 1,
      'created_at': now,
      'updated_at': now,
    });
    await db.insert('todo_groups', {
      'uuid': 'group-team',
      'team_uuid': teamUuid,
      'name': 'Team Group',
      'is_deleted': 0,
      'version': 1,
      'created_at': now,
      'updated_at': now,
    });
    await db.insert('countdowns', {
      'uuid': 'cd-team',
      'team_uuid': teamUuid,
      'title': 'Team Countdown',
      'target_time': now + 100000,
      'is_deleted': 0,
      'version': 1,
      'created_at': now,
      'updated_at': now,
    });
    await db.insert('time_logs', {
      'uuid': 'log-team',
      'team_uuid': teamUuid,
      'title': 'Team TimeLog',
      'device_id': 'test-device',
      'start_time': now,
      'end_time': now + 60000,
      'is_deleted': 0,
      'version': 1,
      'created_at': now,
      'updated_at': now,
    });
    await db.insert('courses', {
      'uuid': 'course-team',
      'team_uuid': teamUuid,
      'course_name': 'Team Course',
      'date': '2026-11-26',
      'weekday': 4,
      'start_time': now,
      'end_time': now + 3600000,
      'week_index': 1,
      'is_deleted': 0,
      'version': 1,
      'created_at': now,
      'updated_at': now,
    });
    await db.insert('fixed_schedules', {
      'uuid': 'fs-team',
      'team_uuid': teamUuid,
      'title': 'Team Schedule',
      'date': '2026-11-26',
      'is_deleted': 0,
      'version': 1,
      'created_at': now,
      'updated_at': now,
    });
    await db.insert('todo_plan_blocks', {
      'uuid': 'plan-team',
      'todo_uuid': 'todo-team',
      'title_snapshot': 'Team Plan',
      'start_time': now,
      'end_time': now + 60000,
      'planned_minutes': 1,
      'calendar_event_id': '',
      'is_deleted': 0,
      'version': 1,
      'created_at': now,
      'updated_at': now,
    });
    await db.insert('todo_completions', {
      'todo_uuid': 'todo-team',
      'user_id': 7,
      'is_completed': 1,
      'updated_at': now,
    });
    await db.insert('todo_completions', {
      'todo_uuid': 'todo-personal',
      'user_id': 7,
      'is_completed': 0,
      'updated_at': now,
    });

    await StorageService.clearTeamItems(teamUuid);

    Future<int> isDeletedFor(String table, String uuid) async {
      final rows = await db.query(
        table,
        columns: ['is_deleted', 'version'],
        where: 'uuid = ?',
        whereArgs: [uuid],
      );
      return rows.single['is_deleted'] as int;
    }

    expect(await isDeletedFor('todos', 'todo-team'), 1);
    expect(await isDeletedFor('todos', 'todo-personal'), 0);
    expect(await isDeletedFor('todo_groups', 'group-team'), 1);
    expect(await isDeletedFor('countdowns', 'cd-team'), 1);
    expect(await isDeletedFor('time_logs', 'log-team'), 1);
    expect(await isDeletedFor('courses', 'course-team'), 1);
    expect(await isDeletedFor('fixed_schedules', 'fs-team'), 1);
    expect(await isDeletedFor('todo_plan_blocks', 'plan-team'), 1);

    final completions = await db.query('todo_completions');
    expect(completions.map((r) => r['todo_uuid']), equals(['todo-personal']));

    final opLogs = await db.query('op_logs');
    final byTable = <String, String>{
      for (final row in opLogs)
        row['target_table'] as String: row['target_uuid'] as String,
    };
    expect(byTable, {
      'todos': 'todo-team',
      'todo_groups': 'group-team',
      'countdowns': 'cd-team',
      'time_logs': 'log-team',
      'todo_plan_blocks': 'plan-team',
    });
    for (final row in opLogs) {
      final payload =
          jsonDecode(row['data_json'] as String) as Map<String, dynamic>;
      expect(payload['is_deleted'], isTrue);
      expect(payload['version'], 2);
    }
  });
}
