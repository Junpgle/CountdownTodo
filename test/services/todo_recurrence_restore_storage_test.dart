import 'dart:io';

import 'package:countdown_todo/models.dart';
import 'package:countdown_todo/services/database_helper.dart';
import 'package:countdown_todo/services/todo_recurrence_delete_service.dart';
import 'package:countdown_todo/services/todo_recurrence_restore_service.dart';
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
    directory = await Directory.systemTemp.createTemp('recurrence-restore-');
    await databaseFactory.setDatabasesPath(directory.path);
  });

  setUp(() async {
    username = 'recurrence-restore-${sequence++}';
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

  test('整系列移入回收站后事务恢复全部期次、状态和唯一规则', () async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final start = today
        .subtract(const Duration(days: 2))
        .add(const Duration(hours: 9));
    const seriesId = '00000000-0000-4000-8000-000000000027';
    await seed([
      TodoItem(
        id: seriesId,
        title: '完整恢复的每日待办',
        recurrence: RecurrenceType.daily,
        recurrenceSeriesId: seriesId,
        recurrenceEndDate: today.add(const Duration(days: 4)),
        createdDate: start.millisecondsSinceEpoch,
        dueDate: start.add(const Duration(hours: 1)),
      ),
    ]);

    var members = (await StorageService.getTodos(
      username,
      includeDeleted: true,
    )).where((todo) => todo.recurrenceSeriesId == seriesId).toList();
    expect(members.length, greaterThanOrEqualTo(3));
    final completed = members.firstWhere((todo) {
      final date = DateTime.fromMillisecondsSinceEpoch(
        todo.createdDate ?? todo.createdAt,
        isUtc: true,
      ).toLocal();
      return DateTime(date.year, date.month, date.day).isBefore(today);
    });
    completed.isDone = true;
    await StorageService.updateSingleTodo(username, completed, sync: false);
    members = (await StorageService.getTodos(
      username,
      includeDeleted: true,
    )).where((todo) => todo.recurrenceSeriesId == seriesId).toList();
    final skipped = members.firstWhere(
      (todo) => !todo.isDone && todo.id != seriesId,
    );
    skipped.isSkipped = true;
    await StorageService.updateSingleTodo(username, skipped, sync: false);

    await StorageService.deleteRecurringTodoWithScope(
      username,
      seriesId,
      TodoRecurrenceDeleteScope.series,
      sync: false,
    );
    final beforeRestore = (await StorageService.getTodos(
      username,
      includeDeleted: true,
    )).where((todo) => todo.recurrenceSeriesId == seriesId).toList();
    expect(beforeRestore, isNotEmpty);
    expect(beforeRestore.every((todo) => todo.isDeleted), isTrue);
    expect(
      beforeRestore.where((todo) => todo.recurrence != RecurrenceType.none),
      hasLength(1),
    );

    final plan = await StorageService.restoreRecurringTodoSeries(
      username,
      seriesId,
      sync: false,
    );
    expect(plan.preview.recordCount, beforeRestore.length);
    expect(plan.preview.completedCount, 1);
    expect(plan.preview.skippedCount, 1);

    final restored = (await StorageService.getTodos(
      username,
      includeDeleted: true,
    )).where((todo) => todo.recurrenceSeriesId == seriesId).toList();
    final restoredById = {for (final todo in restored) todo.id: todo};
    expect(
      beforeRestore.every((todo) => restoredById[todo.id]?.isDeleted == false),
      isTrue,
    );
    expect(restoredById[completed.id]?.isDone, isTrue);
    expect(restoredById[skipped.id]?.isSkipped, isTrue);
    expect(
      restored.where(
        (todo) => !todo.isDeleted && todo.recurrence != RecurrenceType.none,
      ),
      hasLength(1),
    );
    final localDays = restored.where((todo) => !todo.isDeleted).map((todo) {
      final date = DateTime.fromMillisecondsSinceEpoch(
        todo.createdDate ?? todo.createdAt,
        isUtc: true,
      ).toLocal();
      return '${date.year}-${date.month}-${date.day}';
    }).toSet();
    expect(localDays.length, restored.where((todo) => !todo.isDeleted).length);
  });

  test('整组恢复事务拒绝预览后新增的已删除成员', () async {
    const seriesId = '00000000-0000-4000-8000-000000000037';
    final first = TodoItem(
      id: seriesId,
      title: '并发校验系列',
      recurrence: RecurrenceType.weekly,
      recurrenceSeriesId: seriesId,
      isDeleted: true,
      createdDate: DateTime.utc(2026, 10, 5, 9).millisecondsSinceEpoch,
    );
    final second = TodoItem(
      id: '00000000-0000-4000-8000-000000000038',
      title: first.title,
      recurrenceSeriesId: seriesId,
      isDeleted: true,
      createdDate: DateTime.utc(2026, 10, 12, 9).millisecondsSinceEpoch,
    );
    await seed([first, second]);

    final snapshot = await StorageService.getTodos(
      username,
      includeDeleted: true,
    );
    final plan = TodoRecurrenceRestoreService.tryPlan(
      todos: snapshot,
      seriesId: seriesId,
    );
    expect(plan, isNotNull);
    final third = TodoItem(
      id: '00000000-0000-4000-8000-000000000039',
      title: first.title,
      recurrenceSeriesId: seriesId,
      isDeleted: true,
      createdDate: DateTime.utc(2026, 10, 19, 9).millisecondsSinceEpoch,
    );
    await StorageService.saveTodos(
      username,
      [third],
      sync: false,
      isSyncSource: true,
      recomputeScheduleConflicts: false,
    );

    await expectLater(
      StorageService.saveTodos(
        username,
        plan!.restoredItems,
        sync: false,
        expectedTodoBaselines: plan.baselines,
        expectedSeriesMembership: {seriesId: plan.expectedMemberIds},
        expectedSeriesMembershipIncludesDeleted: true,
      ),
      throwsA(isA<StateError>()),
    );
    final afterFailure = await StorageService.getTodos(
      username,
      includeDeleted: true,
    );
    expect(
      afterFailure
          .where((todo) => todo.recurrenceSeriesId == seriesId)
          .every((todo) => todo.isDeleted),
      isTrue,
    );
  });

  test('分页回收站读取遇到已删除规则承载项时补齐完整系列', () async {
    const seriesId = '00000000-0000-4000-8000-000000000047';
    final rootUpdatedAt = DateTime.now().millisecondsSinceEpoch;
    final todos = <TodoItem>[
      TodoItem(
        id: seriesId,
        title: '分页回收站系列',
        recurrence: RecurrenceType.daily,
        recurrenceSeriesId: seriesId,
        isDeleted: true,
        updatedAt: rootUpdatedAt,
        createdDate: DateTime.utc(2026, 1, 1, 9).millisecondsSinceEpoch,
      ),
      for (var i = 1; i < 125; i++)
        TodoItem(
          id: '00000000-0000-4000-8000-${(100000000000 + i).toString()}',
          title: '分页回收站系列',
          recurrenceSeriesId: seriesId,
          isDeleted: true,
          updatedAt: DateTime.utc(2026, 1, 1).millisecondsSinceEpoch + i,
          createdDate: DateTime.utc(2026, 1, i + 1, 9).millisecondsSinceEpoch,
        ),
    ];
    await seed(todos);

    final firstPage = await StorageService.getTodos(
      username,
      includeDeleted: true,
      limit: 120,
    );

    expect(firstPage, hasLength(125));
    expect(
      firstPage.where((todo) => todo.recurrenceSeriesId == seriesId),
      hasLength(125),
    );
    expect(firstPage.every((todo) => todo.isDeleted), isTrue);
  });
}
