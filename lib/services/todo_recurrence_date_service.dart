import '../models.dart';

/// Shared recurrence date arithmetic used by storage and projected UI views.
abstract final class TodoRecurrenceDateService {
  /// Returns the next occurrence start, or `null` when the rule is inactive or
  /// has an invalid interval.
  static DateTime? nextDate(DateTime current, TodoItem todo) {
    switch (todo.recurrence) {
      case RecurrenceType.daily:
        return DateTime(
          current.year,
          current.month,
          current.day + 1,
          current.hour,
          current.minute,
          current.second,
          current.millisecond,
        );
      case RecurrenceType.customDays:
        final days = todo.customIntervalDays ?? 0;
        if (days <= 0) return null;
        return DateTime(
          current.year,
          current.month,
          current.day + days,
          current.hour,
          current.minute,
          current.second,
          current.millisecond,
        );
      case RecurrenceType.weekly:
        return DateTime(
          current.year,
          current.month,
          current.day + 7,
          current.hour,
          current.minute,
          current.second,
          current.millisecond,
        );
      case RecurrenceType.weekdays:
        var next = DateTime(
          current.year,
          current.month,
          current.day + 1,
          current.hour,
          current.minute,
          current.second,
          current.millisecond,
        );
        while (next.weekday == DateTime.saturday ||
            next.weekday == DateTime.sunday) {
          next = DateTime(
            next.year,
            next.month,
            next.day + 1,
            next.hour,
            next.minute,
            next.second,
            next.millisecond,
          );
        }
        return next;
      case RecurrenceType.monthly:
        final targetMonth = DateTime(current.year, current.month + 1);
        final lastDay =
            DateTime(targetMonth.year, targetMonth.month + 1, 0).day;
        return DateTime(
          targetMonth.year,
          targetMonth.month,
          current.day.clamp(1, lastDay),
          current.hour,
          current.minute,
          current.second,
          current.millisecond,
        );
      case RecurrenceType.yearly:
        final lastDay = DateTime(current.year + 1, current.month + 1, 0).day;
        return DateTime(
          current.year + 1,
          current.month,
          current.day.clamp(1, lastDay),
          current.hour,
          current.minute,
          current.second,
          current.millisecond,
        );
      case RecurrenceType.none:
        return null;
    }
  }
}
