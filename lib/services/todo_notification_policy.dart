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

    if (todo.isDateOnly) return false;

    if (!_isSameDay(due, now)) return false;
    return !now.isBefore(due.subtract(leadTime)) && now.isBefore(due);
  }

  static bool _isSameDay(DateTime first, DateTime second) =>
      first.year == second.year &&
      first.month == second.month &&
      first.day == second.day;
}
