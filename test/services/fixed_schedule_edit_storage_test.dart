import 'dart:io';

import 'package:countdown_todo/models.dart';
import 'package:countdown_todo/services/database_helper.dart';
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
    directory = await Directory.systemTemp.createTemp('fixed-schedule-edit-');
    await databaseFactory.setDatabasesPath(directory.path);
  });

  setUp(() async {
    username = 'fixed-schedule-edit-${sequence++}';
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

  List<FixedScheduleItem> seedSeries() => [
    FixedScheduleItem(
      id: 'series-root',
      title: '周会',
      date: '2026-10-19',
      recurrence: RecurrenceType.weekly,
      recurrenceSeriesId: 'series-root',
    ),
    FixedScheduleItem(
      id: 'series-next',
      title: '周会',
      date: '2026-10-26',
      recurrence: RecurrenceType.weekly,
      recurrenceSeriesId: 'series-root',
    ),
  ];

  Future<List<FixedScheduleItem>> loadSeries() async =>
      (await StorageService.getFixedSchedules(
        username,
        includeDeleted: true,
      )).where((item) => item.recurrenceSeriesId == 'series-root').toList();

  Future<List<Map<String, Object?>>> operationRows() async {
    final db = await DatabaseHelper.instance.databaseForUser(username);
    return db.query(
      'op_logs',
      columns: const ['target_uuid'],
      where: "target_table = 'fixed_schedules'",
    );
  }

  test(
    'rejects stale row snapshots without partially writing the edit',
    () async {
      await StorageService.saveFixedSchedules(
        username,
        seedSeries(),
        sync: false,
        isSyncSource: true,
      );
      final baseline = await loadSeries();

      final concurrentUpdate = FixedScheduleItem.fromJson(
        baseline.first.toJson(),
      )..title = '另一窗口的修改';
      concurrentUpdate.markAsChanged();
      await StorageService.saveFixedSchedules(username, [
        concurrentUpdate,
      ], sync: false);

      final proposedRoot = FixedScheduleItem.fromJson(baseline.first.toJson())
        ..title = '编辑器中的修改';
      final proposedNext = FixedScheduleItem.fromJson(baseline.last.toJson())
        ..title = '编辑器中的修改';
      proposedRoot.markAsChanged();
      proposedNext.markAsChanged();

      final saved = await StorageService.saveFixedSchedulesIfUnchanged(
        username,
        baseline: baseline,
        items: [proposedRoot, proposedNext],
        sync: false,
      );

      expect(saved, isFalse);
      final current = await loadSeries();
      expect(current.first.title, '另一窗口的修改');
      expect(current.last.title, '周会');
      expect((await operationRows()).map((row) => row['target_uuid']), [
        'series-root',
      ]);
    },
  );

  test('rejects a new series member added after the editor loaded', () async {
    await StorageService.saveFixedSchedules(
      username,
      seedSeries(),
      sync: false,
      isSyncSource: true,
    );
    final baseline = await loadSeries();
    await StorageService.saveFixedSchedules(username, [
      FixedScheduleItem(
        id: 'series-third',
        title: '周会',
        date: '2026-11-02',
        recurrence: RecurrenceType.weekly,
        recurrenceSeriesId: 'series-root',
      ),
    ], sync: false);
    final proposed = FixedScheduleItem.fromJson(baseline.first.toJson())
      ..title = '编辑器中的修改';
    proposed.markAsChanged();

    final saved = await StorageService.saveFixedSchedulesIfUnchanged(
      username,
      baseline: baseline,
      items: [proposed],
      sync: false,
    );

    expect(saved, isFalse);
    expect((await loadSeries()).map((item) => item.id), [
      'series-root',
      'series-next',
      'series-third',
    ]);
    expect((await loadSeries()).first.title, '周会');
    expect((await operationRows()).map((row) => row['target_uuid']), [
      'series-third',
    ]);
  });

  test(
    'writes every accepted change and its oplog in one local batch',
    () async {
      await StorageService.saveFixedSchedules(
        username,
        seedSeries(),
        sync: false,
        isSyncSource: true,
      );
      final baseline = await loadSeries();
      final proposed = baseline.map((item) {
        final copy = FixedScheduleItem.fromJson(item.toJson())..title = '新周会';
        copy.markAsChanged();
        return copy;
      }).toList();

      final saved = await StorageService.saveFixedSchedulesIfUnchanged(
        username,
        baseline: baseline,
        items: proposed,
        sync: false,
      );

      expect(saved, isTrue);
      expect((await loadSeries()).map((item) => item.title), ['新周会', '新周会']);
      expect((await operationRows()).map((row) => row['target_uuid']), [
        'series-root',
        'series-next',
      ]);
    },
  );

  test(
    'persists association ID edits with each affected fixed-schedule op log',
    () async {
      final schedules = seedSeries()
        ..[0].relatedTodoIds = ['root-task']
        ..[1].relatedTodoIds = ['next-task'];
      await StorageService.saveFixedSchedules(
        username,
        schedules,
        sync: false,
        isSyncSource: true,
      );
      final baseline = await loadSeries();
      final proposed = baseline.map((item) {
        final copy = FixedScheduleItem.fromJson(item.toJson())
          ..relatedTodoIds = ['shared-preparation'];
        copy.markAsChanged();
        return copy;
      }).toList();

      final saved = await StorageService.saveFixedSchedulesIfUnchanged(
        username,
        baseline: baseline,
        items: proposed,
        sync: false,
      );

      expect(saved, isTrue);
      expect(
        (await loadSeries()).map((item) => item.relatedTodoIds),
        everyElement(['shared-preparation']),
      );
      expect((await operationRows()).map((row) => row['target_uuid']), [
        'series-root',
        'series-next',
      ]);
    },
  );

  test(
    'does not replace an unrelated row when a new UUID already exists',
    () async {
      await StorageService.saveFixedSchedules(
        username,
        seedSeries(),
        sync: false,
        isSyncSource: true,
      );
      final baseline = await loadSeries();
      final existingStandalone = FixedScheduleItem(
        id: 'new-row-collision',
        title: '其他已有日程',
        date: '2026-11-03',
      );
      await StorageService.saveFixedSchedules(
        username,
        [existingStandalone],
        sync: false,
        isSyncSource: true,
      );
      final proposedStandalone = FixedScheduleItem(
        id: existingStandalone.id,
        title: '编辑器的新日程',
        date: '2026-11-04',
      );

      final saved = await StorageService.saveFixedSchedulesIfUnchanged(
        username,
        baseline: baseline,
        items: [proposedStandalone],
        sync: false,
      );

      expect(saved, isFalse);
      final db = await DatabaseHelper.instance.databaseForUser(username);
      final collision = FixedScheduleItem.fromJson(
        (await db.query(
          'fixed_schedules',
          where: 'uuid = ?',
          whereArgs: [existingStandalone.id],
        )).single,
      );
      expect(collision.title, '其他已有日程');
    },
  );

  test('rejects a reviewed reschedule when its linked todo changes', () async {
    const todoId = '1c516f9c-55ba-4db6-bc63-09a020f80001';
    final original = FixedScheduleItem(
      id: 'reviewed-schedule',
      title: '考试',
      date: '2026-11-10',
      startTime: DateTime(2026, 11, 10, 9).millisecondsSinceEpoch,
      endTime: DateTime(2026, 11, 10, 10).millisecondsSinceEpoch,
      relatedTodoIds: const [todoId],
      reminderMinutes: const [15],
    );
    await StorageService.saveFixedSchedules(
      username,
      [original],
      sync: false,
      isSyncSource: true,
    );
    final baseline = await StorageService.getFixedSchedules(username);
    final todo = TodoItem(id: todoId, title: '复习资料');
    await StorageService.saveTodos(
      username,
      [todo],
      sync: false,
      isSyncSource: true,
    );
    final reviewedTodos =
        await StorageService.getTodosForFixedScheduleRelations(username);
    final candidate = FixedScheduleItem.fromJson(original.toJson())
      ..date = '2026-11-11'
      ..startTime = DateTime(2026, 11, 11, 11).millisecondsSinceEpoch
      ..endTime = DateTime(2026, 11, 11, 12).millisecondsSinceEpoch;
    candidate.markAsChanged();
    final noPlans = await StorageService.getPlanBlocksOverlappingFixedSchedules(
      username,
      [candidate],
    );

    final concurrentTodo = TodoItem.fromJson(reviewedTodos.single.toJson())
      ..title = '另一处更新的复习资料';
    concurrentTodo.markAsChanged();
    await StorageService.saveTodos(username, [concurrentTodo], sync: false);
    final saved = await StorageService.saveFixedSchedulesIfUnchanged(
      username,
      baseline: baseline,
      items: [candidate],
      reviewedTodoIds: [todoId],
      reviewedTodos: reviewedTodos.where((item) => item.id == todoId).toList(),
      reviewedPlanBlocks: noPlans,
      sync: false,
    );

    expect(saved, isFalse);
    final stored = (await StorageService.getFixedSchedules(username)).single;
    expect(stored.startTime, original.startTime);
    expect(stored.date, original.date);
  });

  test(
    'accepts an unchanged linked todo with the SQL default reminder sentinel',
    () async {
      const todoId = '1c516f9c-55ba-4db6-bc63-09a020f80004';
      final original = FixedScheduleItem(
        id: 'reviewed-default-reminder-schedule',
        title: '面试',
        date: '2026-11-10',
        startTime: DateTime(2026, 11, 10, 9).millisecondsSinceEpoch,
        endTime: DateTime(2026, 11, 10, 10).millisecondsSinceEpoch,
        relatedTodoIds: const [todoId],
        reminderMinutes: const [15],
      );
      await StorageService.saveFixedSchedules(
        username,
        [original],
        sync: false,
        isSyncSource: true,
      );
      final baseline = await StorageService.getFixedSchedules(username);
      await StorageService.saveTodos(
        username,
        [TodoItem(id: todoId, title: '准备材料')],
        sync: false,
        isSyncSource: true,
      );
      final reviewedTodos =
          await StorageService.getTodosForFixedScheduleRelations(username);
      final candidate = FixedScheduleItem.fromJson(original.toJson())
        ..date = '2026-11-11'
        ..startTime = DateTime(2026, 11, 11, 11).millisecondsSinceEpoch
        ..endTime = DateTime(2026, 11, 11, 12).millisecondsSinceEpoch;
      candidate.markAsChanged();
      final noPlans =
          await StorageService.getPlanBlocksOverlappingFixedSchedules(
            username,
            [candidate],
          );

      final saved = await StorageService.saveFixedSchedulesIfUnchanged(
        username,
        baseline: baseline,
        items: [candidate],
        reviewedTodoIds: [todoId],
        reviewedTodos: reviewedTodos
            .where((item) => item.id == todoId)
            .toList(),
        reviewedPlanBlocks: noPlans,
        sync: false,
      );

      expect(saved, isTrue);
      expect(
        (await StorageService.getFixedSchedules(username)).single.date,
        '2026-11-11',
      );
    },
  );

  test(
    'rejects a reviewed reschedule when a new overlapping plan is added',
    () async {
      final original = FixedScheduleItem(
        id: 'reviewed-plan-schedule',
        title: '面试',
        date: '2026-11-10',
        startTime: DateTime(2026, 11, 10, 9).millisecondsSinceEpoch,
        endTime: DateTime(2026, 11, 10, 10).millisecondsSinceEpoch,
      );
      await StorageService.saveFixedSchedules(
        username,
        [original],
        sync: false,
        isSyncSource: true,
      );
      final baseline = await StorageService.getFixedSchedules(username);
      final candidate = FixedScheduleItem.fromJson(original.toJson())
        ..startTime = DateTime(2026, 11, 10, 11).millisecondsSinceEpoch
        ..endTime = DateTime(2026, 11, 10, 12).millisecondsSinceEpoch;
      candidate.markAsChanged();
      final reviewedPlans =
          await StorageService.getPlanBlocksOverlappingFixedSchedules(
            username,
            [candidate],
          );
      await StorageService.savePlanBlocks(
        username,
        [
          TodoPlanBlock(
            id: '1c516f9c-55ba-4db6-bc63-09a020f80002',
            todoId: '1c516f9c-55ba-4db6-bc63-09a020f80003',
            titleSnapshot: '临时新规划',
            startTime: DateTime(2026, 11, 10, 11, 30).millisecondsSinceEpoch,
            endTime: DateTime(2026, 11, 10, 12, 30).millisecondsSinceEpoch,
          ),
        ],
        sync: false,
        isSyncSource: true,
      );

      final saved = await StorageService.saveFixedSchedulesIfUnchanged(
        username,
        baseline: baseline,
        items: [candidate],
        reviewedPlanBlocks: reviewedPlans,
        sync: false,
      );

      expect(saved, isFalse);
      final stored = (await StorageService.getFixedSchedules(username)).single;
      expect(stored.startTime, original.startTime);
    },
  );
}
