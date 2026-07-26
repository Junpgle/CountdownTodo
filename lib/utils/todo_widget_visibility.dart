import '../models.dart';
import 'todo_recurrence_picker.dart';

/// A recurring occurrence remains eligible for a home-screen widget through
/// the calendar day after its scheduled day.
const int recurringTodoWidgetGraceDays = 1;

bool isRecurringTodoOccurrence(TodoItem todo) {
  final seriesId = todo.recurrenceSeriesId;
  return todo.recurrence != RecurrenceType.none ||
      (seriesId != null && seriesId.isNotEmpty);
}

/// The first local instant at which a recurring occurrence must be hidden.
///
/// A Monday occurrence is visible on Monday and Tuesday, then expires at local
/// midnight on Wednesday. One-off todos do not expire from the widget.
DateTime? recurringTodoWidgetVisibleUntil(TodoItem todo) {
  if (!isRecurringTodoOccurrence(todo)) return null;

  final scheduled = todo.dueDate?.toLocal() ?? todo.effectiveStartTime;
  return DateTime(
    scheduled.year,
    scheduled.month,
    scheduled.day + recurringTodoWidgetGraceDays + 1,
  );
}

bool isTodoEligibleForWidget(TodoItem todo, {DateTime? now}) {
  if (todo.isDone || todo.isDeleted) return false;

  final visibleUntil = recurringTodoWidgetVisibleUntil(todo);
  if (visibleUntil == null) return true;
  return (now ?? DateTime.now()).toLocal().isBefore(visibleUntil);
}

/// Builds the widget's actionable todo list without changing picker behavior
/// elsewhere in the app.
///
/// Expired recurring occurrences are removed before a series is collapsed so
/// a current or future occurrence from the same series can take their place.
List<TodoItem> selectTodosForWidget(
  Iterable<TodoItem> todos, {
  DateTime? now,
}) {
  final current = (now ?? DateTime.now()).toLocal();
  return collapseRecurrenceSeriesForTodoPicker(
    todos.where((todo) => isTodoEligibleForWidget(todo, now: current)),
    now: current,
  );
}
