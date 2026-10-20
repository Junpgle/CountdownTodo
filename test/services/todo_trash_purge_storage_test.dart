import 'dart:io';

import 'package:countdown_todo/models.dart';
import 'package:countdown_todo/services/database_helper.dart';
import 'package:countdown_todo/services/todo_recurrence_delete_service.dart';
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
    directory = await Directory.systemTemp.createTemp('todo-trash-purge-');
    await databaseFactory.setDatabasesPath(directory.path);
  });

  setUp(() async {
    username = 'todo-trash-purge-${sequence++}';
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

  Future<void> seed(List<TodoItem> todos) {
    for (final todo in todos) {
      todo.createdDate ??= todo.createdAt;
    }
    return StorageService.saveTodos(
      username,
      todos,
      sync: false,
      isSyncSource: true,
      recomputeScheduleConflicts: false,
    );
  }

  Future<List<Map<String, Object?>>> deleteLogs() async {
    final db = await DatabaseHelper.instance.databaseForUser(username);
    return db.query(
      'op_logs',
      columns: const ['target_uuid'],
      where: "op_type = 'DELETE' AND target_table = 'todos'",
    );
  }

  test('清空预览精确覆盖回收站全部记录并逐条写入删除日志', () async {
    final todos = [
      TodoItem(
        id: 'trash-clear-1',
        title: '已完成旧期',
        isDeleted: true,
        isDone: true,
        createdDate: DateTime.utc(2026, 10, 17, 9).millisecondsSinceEpoch,
      ),
      TodoItem(
        id: 'trash-clear-2',
        title: '已跳过旧期',
        isDeleted: true,
        isSkipped: true,
        recurrenceSeriesId: 'trash-clear-skipped-series',
        createdDate: DateTime.utc(2026, 10, 18, 9).millisecondsSinceEpoch,
      ),
      TodoItem(
        id: 'trash-clear-3',
        title: '普通待办',
        isDeleted: true,
        createdDate: DateTime.utc(2026, 10, 19, 9).millisecondsSinceEpoch,
      ),
      TodoItem(id: 'trash-clear-active', title: '仍在清单'),
    ];
    await seed(todos);

    final plan = await StorageService.previewClearTodoRecycleBin(username);
    expect(plan.preview.recordCount, 3);
    expect(plan.preview.occurrenceCount, 3);
    expect(plan.preview.completedCount, 1);
    expect(plan.preview.skippedCount, 1);

    final result = await StorageService.purgeTodoTrash(username, plan);
    final remaining = await StorageService.getTodos(
      username,
      includeDeleted: true,
    );
    expect(result.deletedCount, 3);
    expect(remaining.map((todo) => todo.id), ['trash-clear-active']);
    expect(
      (await deleteLogs()).map((row) => row['target_uuid']),
      unorderedEquals(['trash-clear-1', 'trash-clear-2', 'trash-clear-3']),
    );
  });

  test('部分删除系列只清理墓碑，活动期次与规则保留', () async {
    const seriesId = 'trash-partial-series';
    await seed([
      TodoItem(
        id: seriesId,
        title: '仍在进行的重复待办',
        recurrence: RecurrenceType.daily,
        recurrenceSeriesId: seriesId,
        recurrenceEndDate: DateTime(2026, 10, 25),
        isDeleted: false,
        createdDate: DateTime.utc(2026, 10, 20, 9).millisecondsSinceEpoch,
      ),
      TodoItem(
        id: 'trash-partial-old-1',
        title: '仍在进行的重复待办',
        recurrenceSeriesId: seriesId,
        isDeleted: true,
        isDone: true,
        createdDate: DateTime.utc(2026, 10, 18, 9).millisecondsSinceEpoch,
      ),
      TodoItem(
        id: 'trash-partial-old-2',
        title: '仍在进行的重复待办',
        recurrenceSeriesId: seriesId,
        isDeleted: true,
        isSkipped: true,
        createdDate: DateTime.utc(2026, 10, 19, 9).millisecondsSinceEpoch,
      ),
    ]);

    final plan = await StorageService.previewPermanentTodoSeriesDelete(
      username,
      seriesId,
    );
    expect(plan.preview.recordCount, 2);
    expect(plan.preview.hasActiveSeriesMembers, isTrue);
    expect(plan.guardEntries, hasLength(3));

    final result = await StorageService.purgeTodoTrash(username, plan);
    final remaining = await StorageService.getTodos(
      username,
      includeDeleted: true,
    );
    final active = remaining.singleWhere((todo) => todo.id == seriesId);
    expect(result.deletedCount, 2);
    expect(active.isDeleted, isFalse);
    expect(active.recurrence, RecurrenceType.daily);
    expect(
      remaining
          .where((todo) => todo.recurrenceSeriesId == seriesId)
          .where((todo) => todo.isDeleted),
      isEmpty,
    );
    expect(
      remaining
          .where((todo) => todo.recurrenceSeriesId == seriesId)
          .where((todo) => todo.recurrence != RecurrenceType.none)
          .where((todo) => !todo.isDeleted),
      hasLength(1),
    );
    expect(
      (await deleteLogs()).map((row) => row['target_uuid']),
      unorderedEquals(['trash-partial-old-1', 'trash-partial-old-2']),
    );
  });

  test('完整删除系列只清理确认快照中的所有期次', () async {
    const seriesId = 'trash-full-series';
    await seed([
      TodoItem(
        id: 'trash-full-series-a',
        title: '已停止的重复待办',
        recurrenceSeriesId: seriesId,
        isDeleted: true,
        isDone: true,
        createdDate: DateTime.utc(2026, 10, 18, 9).millisecondsSinceEpoch,
      ),
      TodoItem(
        id: 'trash-full-series-b',
        title: '已停止的重复待办',
        recurrenceSeriesId: seriesId,
        isDeleted: true,
        isSkipped: true,
        createdDate: DateTime.utc(2026, 10, 19, 9).millisecondsSinceEpoch,
      ),
    ]);
    final plan = await StorageService.previewPermanentTodoSeriesDelete(
      username,
      seriesId,
    );
    expect(plan.preview.recordCount, 2);
    expect(plan.preview.hasActiveSeriesMembers, isFalse);

    final result = await StorageService.purgeTodoTrash(username, plan);
    final remaining = await StorageService.getTodos(
      username,
      includeDeleted: true,
    );
    expect(result.deletedCount, 2);
    expect(
      remaining.where((todo) => todo.recurrenceSeriesId == seriesId),
      isEmpty,
    );
    expect(
      (await deleteLogs()).map((row) => row['target_uuid']),
      unorderedEquals(['trash-full-series-a', 'trash-full-series-b']),
    );
  });

  test('单条预览后已恢复的待办不会被过期确认物理删除', () async {
    final todo = TodoItem(
      id: 'trash-stale-single',
      title: '确认期间被恢复',
      isDeleted: true,
    );
    await seed([todo]);
    final plan = await StorageService.previewPermanentTodoDelete(
      username,
      todo.id,
    );
    final current = (await StorageService.getTodoByUuid(username, todo.id))!;
    current.isDeleted = false;
    current.markAsChanged();
    await StorageService.updateSingleTodo(username, current, sync: false);

    await expectLater(
      StorageService.purgeTodoTrash(username, plan),
      throwsA(isA<StateError>()),
    );
    final remaining = await StorageService.getTodoByUuid(username, todo.id);
    expect(remaining, isNotNull);
    expect(remaining!.isDeleted, isFalse);
    expect(await deleteLogs(), isEmpty);
  });

  test('清空预览后新增回收站记录会使整批操作中止', () async {
    await seed([
      TodoItem(id: 'trash-stale-clear-a', title: '原有待删除', isDeleted: true),
    ]);
    final plan = await StorageService.previewClearTodoRecycleBin(username);
    await StorageService.saveTodos(
      username,
      [
        TodoItem(
          id: 'trash-stale-clear-b',
          title: '新加入回收站',
          isDeleted: true,
          createdDate: DateTime.now().millisecondsSinceEpoch,
        ),
      ],
      sync: false,
      isSyncSource: true,
      recomputeScheduleConflicts: false,
    );

    await expectLater(
      StorageService.purgeTodoTrash(username, plan),
      throwsA(isA<StateError>()),
    );
    final remaining = await StorageService.getTodos(
      username,
      includeDeleted: true,
    );
    expect(remaining.where((todo) => todo.isDeleted), hasLength(2));
    expect(await deleteLogs(), isEmpty);
  });

  test('系列预览后新增期次会阻止对旧范围进行批量清理', () async {
    const seriesId = 'trash-stale-series';
    await seed([
      TodoItem(
        id: 'trash-stale-series-active',
        title: '仍在清单中的期次',
        recurrenceSeriesId: seriesId,
        createdDate: DateTime.now().millisecondsSinceEpoch,
      ),
      TodoItem(
        id: 'trash-stale-series-old',
        title: '回收站中的期次',
        recurrenceSeriesId: seriesId,
        isDeleted: true,
        createdDate: DateTime.now().millisecondsSinceEpoch,
      ),
    ]);
    final plan = await StorageService.previewPermanentTodoSeriesDelete(
      username,
      seriesId,
    );
    await StorageService.saveTodos(
      username,
      [
        TodoItem(
          id: 'trash-stale-series-new',
          title: '确认期间新加入的期次',
          recurrenceSeriesId: seriesId,
          isDeleted: true,
          createdDate: DateTime.now().millisecondsSinceEpoch,
        ),
      ],
      sync: false,
      isSyncSource: true,
      recomputeScheduleConflicts: false,
    );

    await expectLater(
      StorageService.purgeTodoTrash(username, plan),
      throwsA(isA<StateError>()),
    );
    final remaining = await StorageService.getTodos(
      username,
      includeDeleted: true,
    );
    expect(
      remaining.where((todo) => todo.recurrenceSeriesId == seriesId),
      hasLength(3),
    );
    expect(await deleteLogs(), isEmpty);
  });

  test('物理删除的循环期次由 DELETE 日志阻止重复维护重新生成', () async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final start = DateTime(today.year, today.month, today.day, 9);
    final targetDay = today.add(const Duration(days: 1));
    const seriesId = 'trash-purged-future-occurrence-series';
    await seed([
      TodoItem(
        id: seriesId,
        title: '物理删除期次测试',
        recurrence: RecurrenceType.daily,
        recurrenceSeriesId: seriesId,
        recurrenceEndDate: today.add(const Duration(days: 6)),
        createdDate: start.millisecondsSinceEpoch,
        dueDate: start.add(const Duration(hours: 1)),
      ),
    ]);

    DateTime localDay(TodoItem todo) {
      final local = DateTime.fromMillisecondsSinceEpoch(
        todo.createdDate ?? todo.createdAt,
        isUtc: true,
      ).toLocal();
      return DateTime(local.year, local.month, local.day);
    }

    final before = await StorageService.getTodos(
      username,
      includeDeleted: true,
    );
    final occurrence = before.singleWhere(
      (todo) =>
          todo.recurrenceSeriesId == seriesId &&
          !todo.isDeleted &&
          localDay(todo) == targetDay,
    );
    await StorageService.deleteRecurringTodoWithScope(
      username,
      occurrence.id,
      TodoRecurrenceDeleteScope.occurrence,
      sync: false,
    );

    final plan = await StorageService.previewPermanentTodoDelete(
      username,
      occurrence.id,
    );
    await StorageService.purgeTodoTrash(username, plan);
    final after = await StorageService.getTodos(username, includeDeleted: true);

    expect(
      after.where(
        (todo) =>
            todo.recurrenceSeriesId == seriesId && localDay(todo) == targetDay,
      ),
      isEmpty,
    );
    expect(
      after.any(
        (todo) =>
            todo.recurrenceSeriesId == seriesId &&
            todo.recurrence != RecurrenceType.none &&
            !todo.isDeleted,
      ),
      isTrue,
    );
    expect(
      (await deleteLogs()).map((row) => row['target_uuid']),
      contains(occurrence.id),
    );
  });

  test('oplog 写入失败时系列行和删除日志一起回滚', () async {
    const seriesId = 'trash-rollback-series';
    await seed([
      TodoItem(
        id: 'trash-rollback-a',
        title: '回滚组',
        recurrenceSeriesId: seriesId,
        isDeleted: true,
      ),
      TodoItem(
        id: 'trash-rollback-b',
        title: '回滚组',
        recurrenceSeriesId: seriesId,
        isDeleted: true,
      ),
    ]);
    final plan = await StorageService.previewPermanentTodoSeriesDelete(
      username,
      seriesId,
    );
    final db = await DatabaseHelper.instance.databaseForUser(username);
    await db.execute('''
      CREATE TRIGGER fail_todo_trash_purge_oplog
      BEFORE INSERT ON op_logs
      BEGIN
        SELECT RAISE(ABORT, 'forced oplog failure');
      END
    ''');

    await expectLater(
      StorageService.purgeTodoTrash(username, plan),
      throwsA(isA<Exception>()),
    );
    final remaining = await StorageService.getTodos(
      username,
      includeDeleted: true,
    );
    expect(
      remaining.where((todo) => todo.recurrenceSeriesId == seriesId),
      hasLength(2),
    );
    expect(await deleteLogs(), isEmpty);
  });
}
