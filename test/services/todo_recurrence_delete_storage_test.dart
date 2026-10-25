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
    directory = await Directory.systemTemp.createTemp('recurrence-delete-');
    await databaseFactory.setDatabasesPath(directory.path);
  });

  setUp(() async {
    username = 'recurrence-delete-${sequence++}';
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

  test('删除当前规则期后重载不会复活墓碑，后续规则仍继续', () async {
    final today = DateTime.now();
    final start = DateTime(
      today.year,
      today.month,
      today.day,
      9,
    ).subtract(const Duration(days: 1));
    final seriesId = '00000000-0000-4000-8000-000000000026';
    final anchor = TodoItem(
      id: seriesId,
      title: '持续有效的重复待办',
      recurrence: RecurrenceType.daily,
      recurrenceSeriesId: seriesId,
      recurrenceEndDate: DateTime(today.year, today.month, today.day + 4),
      createdDate: start.millisecondsSinceEpoch,
      dueDate: start.add(const Duration(hours: 1)),
    );
    await seed([anchor]);

    final before = await StorageService.getTodos(
      username,
      includeDeleted: true,
    );
    final selected = before.singleWhere((todo) {
      final local = DateTime.fromMillisecondsSinceEpoch(
        todo.createdDate ?? todo.createdAt,
        isUtc: true,
      ).toLocal();
      return todo.recurrenceSeriesId == seriesId &&
          local.year == today.year &&
          local.month == today.month &&
          local.day == today.day &&
          !todo.isDeleted;
    });
    selected.isDone = true;
    await StorageService.updateSingleTodo(username, selected, sync: false);

    final plan = await StorageService.deleteRecurringTodoWithScope(
      username,
      selected.id,
      TodoRecurrenceDeleteScope.occurrence,
      sync: false,
    );
    expect(plan.preview.completedCount, 1);

    final after = await StorageService.getTodos(username, includeDeleted: true);
    final samePeriod = after.where((todo) {
      final local = DateTime.fromMillisecondsSinceEpoch(
        todo.createdDate ?? todo.createdAt,
        isUtc: true,
      ).toLocal();
      return todo.recurrenceSeriesId == seriesId &&
          local.year == today.year &&
          local.month == today.month &&
          local.day == today.day;
    }).toList();
    expect(samePeriod, hasLength(1));
    expect(samePeriod.single.id, selected.id);
    expect(samePeriod.single.isDeleted, isTrue);
    expect(samePeriod.single.isDone, isTrue);
    expect(
      after.where(
        (todo) =>
            todo.recurrenceSeriesId == seriesId &&
            !todo.isDeleted &&
            todo.recurrence != RecurrenceType.none,
      ),
      hasLength(1),
    );
    expect(
      after.any(
        (todo) =>
            todo.recurrenceSeriesId == seriesId &&
            !todo.isDeleted &&
            (todo.createdDate ?? todo.createdAt) == selected.createdDate,
      ),
      isFalse,
    );
  });

  test('本期及以后删除保留此前期次并收口规则边界', () async {
    final today = DateTime.now();
    final todayStart = DateTime(today.year, today.month, today.day, 9);
    final targetDay = DateTime(today.year, today.month, today.day);
    final start = todayStart.subtract(const Duration(days: 1));
    final seriesId = '00000000-0000-4000-8000-000000000027';
    await seed([
      TodoItem(
        id: seriesId,
        title: '按范围停止的重复待办',
        recurrence: RecurrenceType.daily,
        recurrenceSeriesId: seriesId,
        recurrenceEndDate: todayStart.add(const Duration(days: 5)),
        createdDate: start.millisecondsSinceEpoch,
        dueDate: start.add(const Duration(hours: 1)),
      ),
    ]);

    final before = await StorageService.getTodos(
      username,
      includeDeleted: true,
    );
    final selected = before.singleWhere((todo) {
      final local = DateTime.fromMillisecondsSinceEpoch(
        todo.createdDate ?? todo.createdAt,
        isUtc: true,
      ).toLocal();
      return todo.recurrenceSeriesId == seriesId &&
          local.year == today.year &&
          local.month == today.month &&
          local.day == today.day &&
          !todo.isDeleted;
    });

    await StorageService.deleteRecurringTodoWithScope(
      username,
      selected.id,
      TodoRecurrenceDeleteScope.future,
      sync: false,
    );
    final after = await StorageService.getTodos(username, includeDeleted: true);
    DateTime dayFor(TodoItem todo) {
      final local = DateTime.fromMillisecondsSinceEpoch(
        todo.createdDate ?? todo.createdAt,
        isUtc: true,
      ).toLocal();
      return DateTime(local.year, local.month, local.day);
    }

    final members = after
        .where((todo) => todo.recurrenceSeriesId == seriesId)
        .toList();
    final retained = members
        .where((todo) => dayFor(todo).isBefore(targetDay))
        .where((todo) => !todo.isDeleted)
        .toList();
    expect(retained, isNotEmpty);
    expect(
      members
          .where((todo) => !dayFor(todo).isBefore(targetDay))
          .every((todo) => todo.isDeleted),
      isTrue,
    );
    final retainedLastDay = retained
        .map(dayFor)
        .reduce((left, right) => left.isAfter(right) ? left : right);
    final activeRules = members
        .where((todo) => !todo.isDeleted)
        .where((todo) => todo.recurrence != RecurrenceType.none)
        .toList();
    expect(activeRules.length, lessThanOrEqualTo(1));
    if (activeRules.isNotEmpty) {
      expect(
        activeRules.single.recurrenceEndDate == null
            ? null
            : DateTime(
                activeRules.single.recurrenceEndDate!.year,
                activeRules.single.recurrenceEndDate!.month,
                activeRules.single.recurrenceEndDate!.day,
              ),
        retainedLastDay,
      );
    }
    expect(
      members.any((todo) {
        final end = todo.recurrenceEndDate;
        return !todo.isDeleted &&
            end != null &&
            DateTime(end.year, end.month, end.day) == retainedLastDay;
      }),
      isTrue,
    );
  });

  test('整个系列进入回收站后不再保留活动生成规则', () async {
    final today = DateTime.now();
    final start = DateTime(today.year, today.month, today.day, 9);
    final seriesId = '00000000-0000-4000-8000-000000000028';
    await seed([
      TodoItem(
        id: seriesId,
        title: '整组删除的重复待办',
        recurrence: RecurrenceType.daily,
        recurrenceSeriesId: seriesId,
        recurrenceEndDate: start.add(const Duration(days: 5)),
        createdDate: start.millisecondsSinceEpoch,
        dueDate: start.add(const Duration(hours: 1)),
      ),
    ]);
    final before = await StorageService.getTodos(
      username,
      includeDeleted: true,
    );
    final anchor = before.firstWhere((todo) => todo.id == seriesId);

    final plan = await StorageService.deleteRecurringTodoWithScope(
      username,
      anchor.id,
      TodoRecurrenceDeleteScope.series,
      sync: false,
    );
    final after = await StorageService.getTodos(username, includeDeleted: true);
    final series = after
        .where((todo) => todo.recurrenceSeriesId == seriesId)
        .toList();

    expect(plan.preview.occurrenceCount, greaterThanOrEqualTo(1));
    expect(series, isNotEmpty);
    expect(series.every((todo) => todo.isDeleted), isTrue);
    expect(
      series.where((todo) => todo.recurrence != RecurrenceType.none),
      hasLength(1),
    );
  });
}
