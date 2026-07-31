import 'package:countdown_todo/models.dart';
import 'package:countdown_todo/utils/todo_widget_visibility.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TodoItem todo({
    required DateTime scheduled,
    RecurrenceType recurrence = RecurrenceType.none,
    String? seriesId,
    DateTime? dueDate,
    bool isDone = false,
    bool isDeleted = false,
  }) {
    return TodoItem(
      title: '待办',
      recurrence: recurrence,
      recurrenceSeriesId: seriesId,
      createdDate: scheduled.toUtc().millisecondsSinceEpoch,
      dueDate: dueDate,
      isDone: isDone,
      isDeleted: isDeleted,
    );
  }

  group('recurring todo widget visibility', () {
    test('one-off overdue todo never expires from the widget', () {
      final item = todo(
        scheduled: DateTime(2026, 7, 1, 9),
        dueDate: DateTime(2026, 7, 1, 18),
      );

      expect(
        isTodoEligibleForWidget(item, now: DateTime(2026, 7, 26, 12)),
        isTrue,
      );
      expect(recurringTodoWidgetVisibleUntil(item), isNull);
    });

    test('daily occurrence is visible on its day and the following day', () {
      final item = todo(
        scheduled: DateTime(2026, 7, 20, 9),
        dueDate: DateTime(2026, 7, 20, 18),
        recurrence: RecurrenceType.daily,
        seriesId: 'daily-series',
      );

      expect(
        recurringTodoWidgetVisibleUntil(item),
        DateTime(2026, 7, 22),
      );
      expect(
        isTodoEligibleForWidget(item, now: DateTime(2026, 7, 21, 23, 59)),
        isTrue,
      );
    });

    test('daily occurrence is hidden from the third calendar day', () {
      final item = todo(
        scheduled: DateTime(2026, 7, 20, 9),
        dueDate: DateTime(2026, 7, 20, 18),
        recurrence: RecurrenceType.daily,
        seriesId: 'daily-series',
      );

      expect(
        isTodoEligibleForWidget(item, now: DateTime(2026, 7, 22)),
        isFalse,
      );
    });

    test('historical series occurrence is recurring even without active rule',
        () {
      final item = todo(
        scheduled: DateTime(2026, 7, 20, 9),
        recurrence: RecurrenceType.none,
        seriesId: 'rolled-series',
      );

      expect(isRecurringTodoOccurrence(item), isTrue);
      expect(
        isTodoEligibleForWidget(item, now: DateTime(2026, 7, 22)),
        isFalse,
      );
    });

    test('occurrence without a due date expires from its start day', () {
      final item = todo(
        scheduled: DateTime(2026, 12, 31, 9),
        recurrence: RecurrenceType.daily,
        seriesId: 'year-boundary-series',
      );

      expect(
        recurringTodoWidgetVisibleUntil(item),
        DateTime(2027, 1, 2),
      );
    });

    test('completed and deleted todos are not eligible', () {
      final completed = todo(
        scheduled: DateTime(2026, 7, 26),
        isDone: true,
      );
      final deleted = todo(
        scheduled: DateTime(2026, 7, 26),
        isDeleted: true,
      );

      expect(isTodoEligibleForWidget(completed), isFalse);
      expect(isTodoEligibleForWidget(deleted), isFalse);
    });
  });

  group('widget recurrence selection', () {
    test('expired history is removed before the current occurrence is chosen',
        () {
      final expired = todo(
        scheduled: DateTime(2026, 7, 20, 9),
        dueDate: DateTime(2026, 7, 20, 18),
        seriesId: 'selection-series',
      );
      final current = todo(
        scheduled: DateTime(2026, 7, 26, 9),
        dueDate: DateTime(2026, 7, 26, 18),
        recurrence: RecurrenceType.daily,
        seriesId: 'selection-series',
      );

      final selected = selectTodosForWidget(
        [expired, current],
        now: DateTime(2026, 7, 26, 12),
      );

      expect(selected, hasLength(1));
      expect(selected.single.id, current.id);
    });

    test('future occurrence can replace an expired series history', () {
      final expired = todo(
        scheduled: DateTime(2026, 7, 20, 9),
        dueDate: DateTime(2026, 7, 20, 18),
        seriesId: 'future-series',
      );
      final future = todo(
        scheduled: DateTime(2026, 7, 27, 9),
        dueDate: DateTime(2026, 7, 27, 18),
        seriesId: 'future-series',
      );

      final selected = selectTodosForWidget(
        [expired, future],
        now: DateTime(2026, 7, 26, 12),
      );

      expect(selected, hasLength(1));
      expect(selected.single.id, future.id);
    });
  });
}
