import '../models.dart';
import '../utils/time_utils.dart';

/// Centralizes the time-window rules for live todo notifications.
class TodoNotificationPolicy {
  static const Duration defaultLiveLeadTime = Duration(minutes: 30);

  static bool isInsideLiveWindow(
    TodoItem todo,
    DateTime now, {
    Duration leadTime = defaultLiveLeadTime,
  }) {
    return isInsideLiveWindowForLocalDueDate(
      localDueDate: todo.dueDate?.toLocal(),
      isDateOnly: todo.isDateOnly,
      now: now,
      leadTime: leadTime,
    );
  }

  static bool isInsideLiveWindowForLocalDueDate({
    required DateTime? localDueDate,
    required bool isDateOnly,
    required DateTime now,
    Duration leadTime = defaultLiveLeadTime,
  }) {
    final due = localDueDate;
    if (due == null) return false;

    if (isDateOnly) return false;

    if (!AppTimeFormats.isSameDay(due, now)) return false;
    return !now.isBefore(due.subtract(leadTime)) && now.isBefore(due);
  }
}
