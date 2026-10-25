import 'dart:io';

import 'package:countdown_todo/models.dart';
import 'package:countdown_todo/services/database_helper.dart';
import 'package:countdown_todo/services/todo_trash_multi_restore_service.dart';
import 'package:countdown_todo/storage_service.dart';
import 'package:flutter/foundation.dart';
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
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    directory = await Directory.systemTemp.createTemp('trash-multi-restore-');
    await databaseFactory.setDatabasesPath(directory.path);
  });

  setUp(() async {
    username = 'trash-multi-restore-${sequence++}';
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
    debugDefaultTargetPlatformOverride = null;
    await directory.delete(recursive: true);
  });

  Future<void> seed(List<TodoItem> todos) => StorageService.saveTodos(
    username,
    todos,
    sync: false,
    isSyncSource: true,
    recomputeScheduleConflicts: false,
  );

  test('批量恢复只更新所选待办并为每条写本地 oplog', () async {
    final ordinary = TodoItem(
      id: '00000000-0000-4000-8000-000000000111',
      title: '普通已完成待办',
      isDeleted: true,
      isDone: true,
      createdDate: DateTime.utc(2026, 10, 18, 9).millisecondsSinceEpoch,
    );
    const firstSeries = '00000000-0000-4000-8000-000000000101';
    final firstRule = TodoItem(
      id: firstSeries,
      title: '每日复习',
      recurrence: RecurrenceType.daily,
      recurrenceSeriesId: firstSeries,
      isDeleted: true,
      createdDate: DateTime.utc(2026, 10, 19, 9).millisecondsSinceEpoch,
    );
    final selectedOccurrence = TodoItem(
      id: '00000000-0000-4000-8000-000000000102',
      title: firstRule.title,
      recurrenceSeriesId: firstSeries,
      isDeleted: true,
      isSkipped: true,
      createdDate: DateTime.utc(2026, 10, 20, 9).millisecondsSinceEpoch,
    );
    const secondSeries = '00000000-0000-4000-8000-000000000103';
    final secondRule = TodoItem(
      id: secondSeries,
      title: '每周整理',
      recurrence: RecurrenceType.weekly,
      recurrenceSeriesId: secondSeries,
      isDeleted: true,
      createdDate: DateTime.utc(2026, 10, 21, 9).millisecondsSinceEpoch,
    );
    final untouched = TodoItem(
      id: '00000000-0000-4000-8000-000000000104',
      title: '不恢复的期次',
      recurrenceSeriesId: firstSeries,
      isDeleted: true,
      createdDate: DateTime.utc(2026, 10, 22, 9).millisecondsSinceEpoch,
    );
    await seed([
      ordinary,
      firstRule,
      selectedOccurrence,
      secondRule,
      untouched,
    ]);

    final snapshot = await StorageService.getTodos(
      username,
      includeDeleted: true,
    );
    final plan = TodoTrashMultiRestoreService.tryPlan(
      todos: snapshot,
      selectedTodoIds: [ordinary.id, selectedOccurrence.id, secondRule.id],
    );
    expect(plan, isNotNull);
    expect(plan!.preview.recordCount, 3);
    expect(plan.preview.seriesCount, 2);
    await StorageService.restoreTodoTrashSelection(username, plan, sync: false);

    final saved = await StorageService.getTodos(username, includeDeleted: true);
    final byId = {for (final todo in saved) todo.id: todo};
    expect(byId[ordinary.id]!.isDeleted, isFalse);
    expect(byId[ordinary.id]!.isDone, isTrue);
    expect(byId[selectedOccurrence.id]!.isDeleted, isFalse);
    expect(byId[selectedOccurrence.id]!.isSkipped, isTrue);
    expect(byId[firstRule.id]!.isDeleted, isTrue);
    expect(byId[untouched.id]!.isDeleted, isTrue);
    expect(byId[secondRule.id]!.isDeleted, isFalse);
    expect(byId[secondRule.id]!.recurrence, RecurrenceType.weekly);

    final db = await DatabaseHelper.instance.databaseForUser(username);
    final ops = await db.query(
      'op_logs',
      columns: const ['target_uuid'],
      where: "target_table = 'todos' AND is_synced = 0",
    );
    final opIds = ops.map((row) => row['target_uuid'].toString()).toSet();
    expect(opIds, containsAll(plan.selectedTodoIds));
  });

  test('任一所选项目基线变化时整批拒绝且其它选中项不被恢复', () async {
    final first = TodoItem(
      id: '00000000-0000-4000-8000-000000000121',
      title: '保持在回收站',
      isDeleted: true,
      createdDate: DateTime.utc(2026, 10, 18, 9).millisecondsSinceEpoch,
    );
    final second = TodoItem(
      id: '00000000-0000-4000-8000-000000000122',
      title: '确认期间被修改',
      isDeleted: true,
      createdDate: DateTime.utc(2026, 10, 19, 9).millisecondsSinceEpoch,
    );
    await seed([first, second]);
    final snapshot = await StorageService.getTodos(
      username,
      includeDeleted: true,
    );
    final plan = TodoTrashMultiRestoreService.tryPlan(
      todos: snapshot,
      selectedTodoIds: [first.id, second.id],
    );
    expect(plan, isNotNull);

    final changed = TodoItem.fromJson(second.toJson())
      ..title = '已被另一处修改'
      ..markAsChanged();
    await StorageService.saveTodos(
      username,
      [changed],
      sync: false,
      isSyncSource: true,
      recomputeScheduleConflicts: false,
    );

    await expectLater(
      StorageService.restoreTodoTrashSelection(username, plan!, sync: false),
      throwsA(isA<StateError>()),
    );
    final afterFailure = await StorageService.getTodos(
      username,
      includeDeleted: true,
    );
    final byId = {for (final todo in afterFailure) todo.id: todo};
    expect(byId[first.id]!.isDeleted, isTrue);
    expect(byId[second.id]!.isDeleted, isTrue);
    expect(byId[second.id]!.title, '已被另一处修改');
  });
}
