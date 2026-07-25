import 'package:countdown_todo/models.dart';
import 'package:flutter_test/flutter_test.dart';

TodoItem todoWithRange({
  required DateTime start,
  DateTime? due,
  bool isAllDay = false,
}) =>
    TodoItem(
      title: '测试待办',
      createdDate: start.toUtc().millisecondsSinceEpoch,
      dueDate: due,
      isAllDay: isAllDay,
    );

void main() {
  group('TodoItem time semantics', () {
    test('a todo without a due date is unscheduled', () {
      final todo = todoWithRange(start: DateTime(2026, 7, 20, 9));

      expect(todo.timeMode, TodoTimeMode.unscheduled);
      expect(todo.isDateOnly, isFalse);
    });

    test('an explicit date-only todo keeps date-only semantics', () {
      final todo = todoWithRange(
        start: DateTime(2026, 7, 20),
        due: DateTime(2026, 7, 20, 23, 59),
        isAllDay: true,
      );

      expect(todo.timeMode, TodoTimeMode.dateOnly);
      expect(todo.isAllDayTask, isTrue);
    });

    test('legacy midnight-to-end-of-day data is repaired on read', () {
      final todo = todoWithRange(
        start: DateTime(2026, 7, 20),
        due: DateTime(2026, 7, 20, 23, 59),
      );

      expect(todo.timeMode, TodoTimeMode.dateOnly);
    });

    test('legacy midnight-to-later-midnight data is date-only', () {
      final todo = todoWithRange(
        start: DateTime(2026, 7, 20),
        due: DateTime(2026, 7, 21),
      );

      expect(todo.timeMode, TodoTimeMode.dateOnly);
    });

    test('a long cross-day deadline is not inferred as date-only', () {
      final todo = todoWithRange(
        start: DateTime(2026, 7, 19, 19),
        due: DateTime(2026, 7, 21, 22),
      );

      expect(todo.timeMode, TodoTimeMode.deadline);
      expect(todo.isDateOnly, isFalse);
    });

    test('an old explicit start and end is recognized as a legacy range', () {
      final todo = todoWithRange(
        start: DateTime(2026, 7, 20, 9),
        due: DateTime(2026, 7, 20, 11),
      );

      expect(todo.hasLegacyTimeRange, isTrue);
    });

    test('a deadline anchor is not recognized as a legacy range', () {
      final due = DateTime(2026, 7, 20, 18);
      final todo = todoWithRange(start: due, due: due);

      expect(todo.hasLegacyTimeRange, isFalse);
    });

    test('an old start-only todo is recognized as legacy timing', () {
      final todo = todoWithRange(start: DateTime(2026, 7, 20, 9));

      expect(todo.hasLegacyTiming, isTrue);
      expect(todo.hasLegacyTimeRange, isFalse);
    });

    test('explicit date-only state survives JSON round trip', () {
      final source = todoWithRange(
        start: DateTime(2026, 7, 20),
        due: DateTime(2026, 7, 20, 23, 59),
        isAllDay: true,
      );

      final restored = TodoItem.fromJson(source.toJson());

      expect(restored.isAllDay, isTrue);
      expect(restored.timeMode, TodoTimeMode.dateOnly);
    });

    test('new unscheduled todos do not write a business time range', () {
      final normalized = TodoItem.normalizeTimeForWrite(
        selectedDate: DateTime(2026, 7, 20, 9),
        isDateOnly: false,
      );

      expect(normalized.start, isNull);
      expect(normalized.due, isNull);
    });

    test('new deadlines use the deadline as their storage anchor', () {
      final due = DateTime(2026, 7, 20, 18);
      final normalized = TodoItem.normalizeTimeForWrite(
        selectedDate: DateTime(2026, 7, 20),
        dueDate: due,
        isDateOnly: false,
      );

      expect(normalized.start, due);
      expect(normalized.due, due);
    });

    test('date-only writes keep the legacy-compatible day boundaries', () {
      final normalized = TodoItem.normalizeTimeForWrite(
        selectedDate: DateTime(2026, 7, 20, 16, 30),
        isDateOnly: true,
      );

      expect(normalized.start, DateTime(2026, 7, 20));
      expect(normalized.due, DateTime(2026, 7, 20, 23, 59));
    });

    test('editing a legacy range preserves its start and end', () {
      final start = DateTime(2026, 7, 20, 9);
      final end = DateTime(2026, 7, 20, 11);

      final normalized = TodoItem.normalizeTimeForEdit(
        selectedDate: start,
        dueDate: end,
        isDateOnly: false,
        preserveExistingTiming: true,
      );

      expect(normalized.start, start);
      expect(normalized.due, end);
    });

    test('editing old start-only timing does not clear its start', () {
      final start = DateTime(2026, 7, 20, 9);

      final normalized = TodoItem.normalizeTimeForEdit(
        selectedDate: start,
        isDateOnly: false,
        preserveExistingTiming: true,
      );

      expect(normalized.start, start);
      expect(normalized.due, isNull);
    });

    test('editing a normal deadline still uses the deadline anchor', () {
      final due = DateTime(2026, 7, 20, 18);

      final normalized = TodoItem.normalizeTimeForEdit(
        selectedDate: DateTime(2026, 7, 20, 9),
        dueDate: due,
        isDateOnly: false,
        preserveExistingTiming: false,
      );

      expect(normalized.start, due);
      expect(normalized.due, due);
    });
  });
}
