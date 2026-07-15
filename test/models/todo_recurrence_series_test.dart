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
