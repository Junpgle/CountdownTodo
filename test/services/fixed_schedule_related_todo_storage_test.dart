import 'dart:io';

import 'package:countdown_todo/models.dart';
import 'package:countdown_todo/services/database_helper.dart';
import 'package:countdown_todo/storage_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late String username;
  var sequence = 0;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    directory = await Directory.systemTemp.createTemp(
      'fixed-schedule-todo-relations-',
    );
    await databaseFactory.setDatabasesPath(directory.path);
  });

  setUp(() async {
    username = 'fixed-schedule-related-${sequence++}';
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    await prefs.setString('current_login_user', username);
    await prefs.setInt('current_user_id', 0);
    await prefs.setBool('migration_marker_${username}_v4', true);
    await prefs.setBool('cleanup_done_${username}_v4_repair', true);
    await prefs.setBool('conflict_detection_enabled', false);
  });

  tearDown(() async {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await DatabaseHelper.instance.closeDatabase();
  });

  tearDownAll(() async {
    await directory.delete(recursive: true);
  });

  test(
    'loads exact, non-deleted related schedules and excludes substring IDs',
    () async {
      await StorageService.saveFixedSchedules(
        username,
        [
          FixedScheduleItem(
            id: 'related',
            title: '高等数学考试',
            date: '2026-11-10',
            relatedTodoIds: const ['todo-a'],
          ),
          FixedScheduleItem(
            id: 'substring',
            title: '其他考试',
            date: '2026-11-11',
            relatedTodoIds: const ['todo-ab'],
          ),
          FixedScheduleItem(
            id: 'deleted',
            title: '已删除考试',
            date: '2026-11-12',
            relatedTodoIds: const ['todo-a'],
            isDeleted: true,
          ),
        ],
        sync: false,
        isSyncSource: true,
      );

      final result = await StorageService.getFixedSchedulesByRelatedTodo(
        username,
        'todo-a',
      );

      expect(result.map((item) => item.id), ['related']);
    },
  );

  test('propagates account and database read failures', () async {
    await expectLater(
      StorageService.getFixedSchedulesByRelatedTodo('other-account', 'todo-a'),
      throwsStateError,
    );
  });
}
