import 'package:countdown_todo/models.dart';
import 'package:countdown_todo/utils/todo_recurrence_calendar_index.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TodoItem occurrence(
    int day, {
    RecurrenceType recurrence = RecurrenceType.none,
    int hour = 19,
  }) {
    return TodoItem(
      title: '每日循环',
      recurrence: recurrence,
      recurrenceSeriesId: 'calendar-series',
      createdDate: DateTime(2026, 7, day, hour).millisecondsSinceEpoch,
      dueDate: DateTime(2026, 7, day, hour + 3),
    );
  }

  test(
    'persisted occurrence suppresses virtual projection for the same day',
    () {
      final current = occurrence(15, recurrence: RecurrenceType.daily);
      final future = occurrence(16);
      final index = TodoRecurrenceCalendarIndex([current, future]);

      expect(
        index.shouldProjectVirtual(current, DateTime(2026, 7, 15)),
        isTrue,
      );
      expect(
        index.shouldProjectVirtual(current, DateTime(2026, 7, 16)),
        isFalse,
      );
      expect(
        index.shouldProjectVirtual(current, DateTime(2026, 7, 17)),
        isTrue,
      );
    },
  );

  test('calendar keeps only one persisted occurrence per series and day', () {
    final duplicate = occurrence(16, hour: 18);
    final active = occurrence(16, recurrence: RecurrenceType.daily);
    final otherDay = occurrence(17);
    final index = TodoRecurrenceCalendarIndex([duplicate, active, otherDay]);

    expect(index.shouldDisplayPersisted(duplicate), isFalse);
    expect(index.shouldDisplayPersisted(active), isTrue);
    expect(index.shouldDisplayPersisted(otherDay), isTrue);
  });
}
