import '../models.dart';

/// Centralizes the time-window rules for live todo notifications.
class TodoNotificationPolicy {
  static const Duration defaultLiveLeadTime = Duration(minutes: 30);

  static bool isInsideLiveWindow(
    TodoItem todo,
    DateTime now, {
    Duration leadTime = defaultLiveLeadTime,
  }) {
    final due = todo.dueDate?.toLocal();
    if (due == null) return false;

    final start = DateTime.fromMillisecondsSinceEpoch(
      todo.createdDate ?? todo.createdAt,
      isUtc: true,
    ).toLocal();

    if (_isAllDay(todo, start, due)) return false;

    if (!_isSameDay(due, now)) return false;

    // A genuine overnight item should remain active across midnight. For a
    // longer multi-day item, however, treating the entire date span as an
    // active notification makes an evening task pop up throughout the day.
    // On its due day, use the displayed start/end clock times instead.
    final duration = due.difference(start);
    final effectiveStart = duration > const Duration(hours: 24)
        ? DateTime(
            due.year,
            due.month,
            due.day,
            start.hour,
            start.minute,
            start.second,
            start.millisecond,
            start.microsecond,
          )
        : start;

    if (!effectiveStart.isBefore(due)) return false;
    return !now.isBefore(effectiveStart.subtract(leadTime)) &&
        now.isBefore(due);
  }

  static bool _isSameDay(DateTime first, DateTime second) =>
      first.year == second.year &&
      first.month == second.month &&
      first.day == second.day;

  static bool _isAllDay(TodoItem todo, DateTime start, DateTime due) {
    if (todo.isAllDay) return true;
    if (start.hour != 0 || start.minute != 0) return false;
    return (due.hour == 23 && due.minute == 59) ||
        (due.hour == 0 && due.minute == 0 && due.isAfter(start));
  }
}
