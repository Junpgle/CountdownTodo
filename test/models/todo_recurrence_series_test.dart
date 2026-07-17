import 'package:flutter_test/flutter_test.dart';
import 'package:CountDownTodo/models.dart';
import 'package:CountDownTodo/storage_service.dart';

void main() {
  test('TodoItem preserves recurrence series id through JSON', () {
    final todo = TodoItem(
      title: '每日复习',
      recurrence: RecurrenceType.daily,
      recurrenceSeriesId: 'series-123',
    );

    final restored = TodoItem.fromJson(todo.toJson());

    expect(restored.recurrenceSeriesId, 'series-123');
    expect(restored.recurrence, RecurrenceType.daily);
  });

  test('TodoItem accepts camelCase recurrence series id', () {
    final restored = TodoItem.fromJson({
      'uuid': '550e8400-e29b-41d4-a716-446655440000',
      'content': '每日复习',
      'recurrence': RecurrenceType.daily.index,
      'recurrenceSeriesId': 'series-camel-case',
    });

    expect(restored.recurrenceSeriesId, 'series-camel-case');
  });

  test('TodoItem treats an empty recurrence series id as missing', () {
    final restored = TodoItem.fromJson({
      'uuid': '550e8400-e29b-41d4-a716-446655440001',
      'content': '每日复习',
      'recurrence': RecurrenceType.daily.index,
      'recurrence_series_id': '',
    });

    expect(restored.recurrenceSeriesId, isNull);
  });

  test('old cloud instances recover one recurrence series from its timeline',
      () {
    TodoItem occurrence(
      int day, {
      RecurrenceType recurrence = RecurrenceType.none,
      bool isDone = false,
    }) {
      return TodoItem(
        id: 'occurrence-$day',
        title: '公考七日班',
        remark: '固定晚间课程',
        isDone: isDone,
        recurrence: recurrence,
        customIntervalDays: 0,
        recurrenceEndDate: DateTime(2026, 7, 19),
        createdDate: DateTime(2026, 7, day, 19).millisecondsSinceEpoch,
        dueDate: DateTime(2026, 7, day, 22),
      );
    }

    final incoming = [
      occurrence(13, isDone: true),
      occurrence(14, isDone: true),
      occurrence(15),
      occurrence(16),
      occurrence(17, recurrence: RecurrenceType.daily),
      occurrence(18),
      occurrence(19),
    ];

    final repaired =
        StorageService.repairMissingRemoteRecurrenceSeriesIdsForTest(
      incoming,
      const [],
    );

    expect(repaired, hasLength(7));
    expect(
      incoming.map((todo) => todo.recurrenceSeriesId).toSet(),
      {'occurrence-13'},
    );
    expect(incoming.where((todo) => todo.isDone), hasLength(2));
  });

  test('old cloud repair does not merge a same-title task at another time', () {
    final historical = TodoItem(
      id: 'historical',
      title: '每日复习',
      customIntervalDays: 0,
      createdDate: DateTime(2026, 7, 16, 19).millisecondsSinceEpoch,
      dueDate: DateTime(2026, 7, 16, 22),
    );
    final active = TodoItem(
      id: 'active',
      title: '每日复习',
      recurrence: RecurrenceType.daily,
      customIntervalDays: 0,
      createdDate: DateTime(2026, 7, 17, 19).millisecondsSinceEpoch,
      dueDate: DateTime(2026, 7, 17, 22),
    );
    final unrelated = TodoItem(
      id: 'unrelated',
      title: '每日复习',
      customIntervalDays: 0,
      createdDate: DateTime(2026, 7, 16, 8).millisecondsSinceEpoch,
      dueDate: DateTime(2026, 7, 16, 9),
    );

    StorageService.repairMissingRemoteRecurrenceSeriesIdsForTest(
      [historical, active, unrelated],
      const [],
    );

    expect(historical.recurrenceSeriesId, 'historical');
    expect(active.recurrenceSeriesId, 'historical');
    expect(unrelated.recurrenceSeriesId, isNull);
  });

  test('ambiguous identical active series are not guessed from old cloud data',
      () {
    TodoItem todo(String id, int day, {bool active = false}) => TodoItem(
          id: id,
          title: '同配置循环',
          recurrence: active ? RecurrenceType.daily : RecurrenceType.none,
          customIntervalDays: 0,
          createdDate: DateTime(2026, 7, day, 19).millisecondsSinceEpoch,
          dueDate: DateTime(2026, 7, day, 22),
        );
    final firstActive = todo('active-a', 17, active: true);
    final secondActive = todo('active-b', 17, active: true);
    final historical = todo('history', 16);

    StorageService.repairMissingRemoteRecurrenceSeriesIdsForTest(
      [historical, firstActive, secondActive],
      const [],
    );

    expect(firstActive.recurrenceSeriesId, 'active-a');
    expect(secondActive.recurrenceSeriesId, 'active-b');
    expect(historical.recurrenceSeriesId, isNull);
  });

  test('local series id is authoritative when old cloud response omits it', () {
    final incoming = TodoItem(
      id: 'same-uuid',
      title: '每日复习',
      recurrence: RecurrenceType.daily,
      createdDate: DateTime(2026, 7, 17, 19).millisecondsSinceEpoch,
      dueDate: DateTime(2026, 7, 17, 22),
    );
    final local = TodoItem(
      id: 'same-uuid',
      title: '每日复习',
      recurrence: RecurrenceType.daily,
      recurrenceSeriesId: 'original-series',
      createdDate: DateTime(2026, 7, 17, 19).millisecondsSinceEpoch,
      dueDate: DateTime(2026, 7, 17, 22),
    );

    final repaired =
        StorageService.repairMissingRemoteRecurrenceSeriesIdsForTest(
      [incoming],
      [local],
    );

    expect(repaired, {'same-uuid'});
    expect(incoming.recurrenceSeriesId, 'original-series');
  });

  test('incremental cloud anchor repairs instances already split locally', () {
    final localHistory = TodoItem(
      id: 'history-13',
      title: '每日复习',
      customIntervalDays: 0,
      createdDate: DateTime(2026, 7, 13, 19).millisecondsSinceEpoch,
      dueDate: DateTime(2026, 7, 13, 22),
    );
    final localActive = TodoItem(
      id: 'active-17',
      title: '每日复习',
      recurrence: RecurrenceType.daily,
      recurrenceSeriesId: 'active-17',
      customIntervalDays: 0,
      createdDate: DateTime(2026, 7, 17, 19).millisecondsSinceEpoch,
      dueDate: DateTime(2026, 7, 17, 22),
    );
    final incomingActive = TodoItem(
      id: 'active-17',
      title: '每日复习',
      recurrence: RecurrenceType.daily,
      customIntervalDays: 0,
      createdDate: DateTime(2026, 7, 17, 19).millisecondsSinceEpoch,
      dueDate: DateTime(2026, 7, 17, 22),
    );

    final repaired =
        StorageService.repairMissingRemoteRecurrenceSeriesIdsForTest(
      [incomingActive],
      [localHistory, localActive],
    );

    expect(repaired, containsAll({'history-13', 'active-17'}));
    expect(incomingActive.recurrenceSeriesId, 'active-17');
    expect(localHistory.recurrenceSeriesId, 'active-17');
  });

  test('stale child series id follows its anchor into the canonical series',
      () {
    final original = TodoItem(
      id: 'original-series',
      title: '每日复习',
      recurrenceSeriesId: 'original-series',
      createdDate: DateTime(2026, 7, 13, 19).millisecondsSinceEpoch,
      dueDate: DateTime(2026, 7, 13, 22),
    );
    final active = TodoItem(
      id: 'active-17',
      title: '每日复习',
      recurrence: RecurrenceType.daily,
      recurrenceSeriesId: 'original-series',
      createdDate: DateTime(2026, 7, 17, 19).millisecondsSinceEpoch,
      dueDate: DateTime(2026, 7, 17, 22),
    );
    final orphan = TodoItem(
      id: 'orphan-16',
      title: '每日复习',
      recurrenceSeriesId: 'active-17',
      createdDate: DateTime(2026, 7, 16, 19).millisecondsSinceEpoch,
      dueDate: DateTime(2026, 7, 16, 22, 30),
    );

    final repaired =
        StorageService.repairMissingRemoteRecurrenceSeriesIdsForTest(
      const [],
      [original, orphan, active],
    );

    expect(repaired, contains('orphan-16'));
    expect(orphan.recurrenceSeriesId, 'original-series');
  });

  test('identical migration snapshot is cleared as a stale version conflict',
      () {
    final todo = TodoItem(
      id: 'migration-conflict',
      title: '每日复习',
      isDone: true,
      recurrenceSeriesId: 'original-series',
      createdDate: DateTime(2026, 7, 13, 19).millisecondsSinceEpoch,
      dueDate: DateTime(2026, 7, 13, 22),
      reminderMinutes: 5,
    );
    final serverSnapshot = Map<String, dynamic>.from(todo.toJson())
      ..remove('recurrence_series_id')
      ..remove('recurrenceSeriesId');
    todo.hasConflict = true;
    todo.serverVersionData = serverSnapshot;
    final previousVersion = todo.version;

    final resolved =
        StorageService.clearResolvedRecurrenceMigrationConflictsForTest(
      [todo],
    );

    expect(resolved, [todo]);
    expect(todo.hasConflict, isFalse);
    expect(todo.serverVersionData, isNull);
    expect(todo.version, previousVersion + 1);
  });

  test('migration conflict with a real completion difference is preserved', () {
    final todo = TodoItem(
      id: 'real-completion-conflict',
      title: '每日复习',
      isDone: true,
      recurrenceSeriesId: 'original-series',
      createdDate: DateTime(2026, 7, 15, 19).millisecondsSinceEpoch,
      dueDate: DateTime(2026, 7, 15, 22),
    );
    final serverSnapshot = Map<String, dynamic>.from(todo.toJson())
      ..['is_completed'] = 0
      ..remove('recurrence_series_id')
      ..remove('recurrenceSeriesId');
    todo.hasConflict = true;
    todo.serverVersionData = serverSnapshot;

    final resolved =
        StorageService.clearResolvedRecurrenceMigrationConflictsForTest(
      [todo],
    );

    expect(resolved, isEmpty);
    expect(todo.hasConflict, isTrue);
    expect(todo.serverVersionData, isNotNull);
  });

  test('daily recurrence backfills every missing day', () {
    final todo = TodoItem(
      title: '每日循环',
      recurrence: RecurrenceType.daily,
    );

    final offsets = StorageService.recurrenceRollOffsetsForTest(
      todo,
      DateTime(2026, 7, 13),
      DateTime(2026, 7, 15),
    );

    expect(offsets, [1, 2]);
  });

  test('weekday recurrence skips weekend while backfilling', () {
    final todo = TodoItem(
      title: '工作日循环',
      recurrence: RecurrenceType.weekdays,
    );

    final offsets = StorageService.recurrenceRollOffsetsForTest(
      todo,
      DateTime(2026, 7, 10), // Friday
      DateTime(2026, 7, 13), // Monday
    );

    expect(offsets, [3]);
  });

  test('finite recurrence pre-generates every future occurrence to end date',
      () {
    final source = TodoItem(
      title: '每日循环',
      recurrence: RecurrenceType.daily,
      recurrenceSeriesId: 'series-future',
      createdDate: DateTime(2026, 7, 15, 19).millisecondsSinceEpoch,
      dueDate: DateTime(2026, 7, 15, 22),
      recurrenceEndDate: DateTime(2026, 7, 19),
    );

    final generated =
        StorageService.futureRecurrenceOccurrencesForTest(source, [source]);
    final days = generated.map((todo) {
      return DateTime.fromMillisecondsSinceEpoch(
        todo.createdDate!,
        isUtc: true,
      ).toLocal().day;
    }).toList();

    expect(days, [16, 17, 18, 19]);
    expect(generated.map((todo) => todo.id).toSet(), hasLength(4));
    expect(
      generated.every(
        (todo) =>
            todo.recurrenceSeriesId == 'series-future' &&
            todo.recurrence == RecurrenceType.none,
      ),
      isTrue,
    );

    final duplicatePass = StorageService.futureRecurrenceOccurrencesForTest(
      source,
      [source, ...generated],
    );
    expect(duplicatePass, isEmpty);
  });

  test('open-ended recurrence keeps two generated future occurrences', () {
    final source = TodoItem(
      title: '每周循环',
      recurrence: RecurrenceType.weekly,
      recurrenceSeriesId: 'series-open-ended',
      createdDate: DateTime(2026, 7, 15, 19).millisecondsSinceEpoch,
      dueDate: DateTime(2026, 7, 15, 22),
    );

    final generated =
        StorageService.futureRecurrenceOccurrencesForTest(source, [source]);
    final starts = generated
        .map((todo) => DateTime.fromMillisecondsSinceEpoch(
              todo.createdDate!,
              isUtc: true,
            ).toLocal())
        .toList();

    expect(generated, hasLength(2));
    expect(starts[0].day, 22);
    expect(starts[1].day, 29);
  });

  test('future generation deduplicates a series by local start day', () {
    final source = TodoItem(
      title: '每日循环',
      recurrence: RecurrenceType.daily,
      recurrenceSeriesId: 'series-day-dedupe',
      createdDate: DateTime(2026, 7, 15, 19).millisecondsSinceEpoch,
      dueDate: DateTime(2026, 7, 15, 22),
      recurrenceEndDate: DateTime(2026, 7, 17),
    );
    final editedFuture = TodoItem(
      title: '每日循环',
      recurrenceSeriesId: 'series-day-dedupe',
      createdDate: DateTime(2026, 7, 16, 20).millisecondsSinceEpoch,
      dueDate: DateTime(2026, 7, 16, 23),
    );

    final generated = StorageService.futureRecurrenceOccurrencesForTest(
      source,
      [source, editedFuture],
    );
    final days = generated.map((todo) {
      return DateTime.fromMillisecondsSinceEpoch(
        todo.createdDate!,
        isUtc: true,
      ).toLocal().day;
    }).toList();

    expect(days, [17]);
  });

  test('existing recurrence series repairs missing past occurrences', () {
    final previous = TodoItem(
      title: '每日循环',
      recurrenceSeriesId: 'series-history-gap',
      createdDate: DateTime(2026, 7, 13, 19).millisecondsSinceEpoch,
      dueDate: DateTime(2026, 7, 13, 22),
    );
    final active = TodoItem(
      title: '每日循环',
      recurrence: RecurrenceType.daily,
      recurrenceSeriesId: 'series-history-gap',
      createdDate: DateTime(2026, 7, 15, 19).millisecondsSinceEpoch,
      dueDate: DateTime(2026, 7, 15, 22),
    );

    final repaired =
        StorageService.repairMissingPastRecurrenceOccurrencesForTest(
      active,
      [previous, active],
    );
    final repairedStart = DateTime.fromMillisecondsSinceEpoch(
      repaired.single.createdDate!,
      isUtc: true,
    ).toLocal();

    expect(repairedStart, DateTime(2026, 7, 14, 19));
    expect(repaired.single.dueDate, DateTime(2026, 7, 14, 22));
    expect(repaired.single.id, isNot(anyOf(previous.id, active.id)));
    expect(repaired.single.recurrenceSeriesId, 'series-history-gap');
    expect(repaired.single.recurrence, RecurrenceType.none);

    final duplicatePass =
        StorageService.repairMissingPastRecurrenceOccurrencesForTest(
      active,
      [previous, ...repaired, active],
    );
    expect(duplicatePass, isEmpty);
  });

  test('past repair does not invent history without an earlier anchor', () {
    final active = TodoItem(
      title: '每日循环',
      recurrence: RecurrenceType.daily,
      recurrenceSeriesId: 'series-no-history',
      createdDate: DateTime(2026, 7, 15, 19).millisecondsSinceEpoch,
      dueDate: DateTime(2026, 7, 15, 22),
    );

    final repaired =
        StorageService.repairMissingPastRecurrenceOccurrencesForTest(
      active,
      [active],
    );

    expect(repaired, isEmpty);
  });

  test('persisted duplicate occurrences on one series day are cleaned up', () {
    TodoItem occurrence({
      required String id,
      RecurrenceType recurrence = RecurrenceType.none,
      bool isDone = false,
      int hour = 19,
    }) {
      return TodoItem(
        id: id,
        title: '每日循环',
        recurrence: recurrence,
        recurrenceSeriesId: 'series-persisted-dedupe',
        isDone: isDone,
        createdDate: DateTime(2026, 7, 15, hour).millisecondsSinceEpoch,
        dueDate: DateTime(2026, 7, 15, hour + 3),
      );
    }

    final completedDuplicate = occurrence(id: 'completed', isDone: true);
    final active = occurrence(
      id: 'active',
      recurrence: RecurrenceType.daily,
      hour: 20,
    );
    final extraDuplicate = occurrence(id: 'extra', hour: 21);
    final nextDay = TodoItem(
      id: 'next-day',
      title: '每日循环',
      recurrenceSeriesId: 'series-persisted-dedupe',
      createdDate: DateTime(2026, 7, 16, 19).millisecondsSinceEpoch,
    );

    final changed =
        StorageService.deduplicatePersistedRecurrenceOccurrencesForTest([
      completedDuplicate,
      active,
      extraDuplicate,
      nextDay,
    ]);

    expect(changed, isTrue);
    expect(active.isDeleted, isFalse);
    expect(active.isDone, isTrue);
    expect(active.recurrence, RecurrenceType.daily);
    expect(completedDuplicate.isDeleted, isTrue);
    expect(extraDuplicate.isDeleted, isTrue);
    expect(nextDay.isDeleted, isFalse);
  });

  test('dedupe keeps the more edited occurrence over a newer migrated copy',
      () {
    final edited = TodoItem(
      id: 'edited',
      title: '每日循环',
      version: 8,
      updatedAt: DateTime(2026, 7, 17, 13, 18).millisecondsSinceEpoch,
      recurrenceSeriesId: 'canonical-series',
      createdDate: DateTime(2026, 7, 16, 19).millisecondsSinceEpoch,
      dueDate: DateTime(2026, 7, 16, 22, 30),
    );
    final migratedCopy = TodoItem(
      id: 'migrated-copy',
      title: '每日循环',
      version: 2,
      updatedAt: DateTime(2026, 7, 17, 13, 21).millisecondsSinceEpoch,
      recurrenceSeriesId: 'canonical-series',
      createdDate: DateTime(2026, 7, 16, 19).millisecondsSinceEpoch,
      dueDate: DateTime(2026, 7, 16, 22),
    );

    final changed =
        StorageService.deduplicatePersistedRecurrenceOccurrencesForTest(
      [edited, migratedCopy],
    );

    expect(changed, isTrue);
    expect(edited.isDeleted, isFalse);
    expect(edited.dueDate, DateTime(2026, 7, 16, 22, 30));
    expect(migratedCopy.isDeleted, isTrue);
  });

  test('same recurrence series does not report schedule conflict', () {
    final first = TodoItem(
      title: '循环任务第一期',
      recurrenceSeriesId: 'series-conflict-test',
      createdDate: DateTime(2026, 7, 15, 9).millisecondsSinceEpoch,
      dueDate: DateTime(2026, 7, 15, 11),
    );
    final second = TodoItem(
      title: '循环任务第二期',
      recurrenceSeriesId: 'series-conflict-test',
      createdDate: DateTime(2026, 7, 15, 10).millisecondsSinceEpoch,
      dueDate: DateTime(2026, 7, 15, 12),
    );

    final changed = StorageService.recomputeLocalTodoScheduleConflictsForTest([
      first,
      second,
    ]);

    expect(changed, isFalse);
    expect(first.hasConflict, isFalse);
    expect(second.hasConflict, isFalse);
  });

  test('different recurrence series still report schedule conflict', () {
    final first = TodoItem(
      title: '任务 A',
      recurrenceSeriesId: 'series-a',
      createdDate: DateTime(2026, 7, 15, 9).millisecondsSinceEpoch,
      dueDate: DateTime(2026, 7, 15, 11),
    );
    final second = TodoItem(
      title: '任务 B',
      recurrenceSeriesId: 'series-b',
      createdDate: DateTime(2026, 7, 15, 10).millisecondsSinceEpoch,
      dueDate: DateTime(2026, 7, 15, 12),
    );

    final changed = StorageService.recomputeLocalTodoScheduleConflictsForTest([
      first,
      second,
    ]);

    expect(changed, isTrue);
    expect(first.hasConflict, isTrue);
    expect(second.hasConflict, isTrue);
  });
}
