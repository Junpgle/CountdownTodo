import '../models.dart';

/// Shared membership and date helpers for recurring todo edits.
class TodoRecurrenceSeriesEditService {
  const TodoRecurrenceSeriesEditService._();

  static String? seriesIdFor(TodoItem todo) {
    final seriesId = todo.recurrenceSeriesId?.trim();
    if (seriesId?.isNotEmpty == true) return seriesId;
    return todo.recurrence == RecurrenceType.none ? null : todo.id;
  }

  static bool belongsToSeries(TodoItem todo, String seriesId) {
    if (todo.recurrenceSeriesId == seriesId) return true;
    return todo.id == seriesId &&
        (todo.recurrenceSeriesId == null ||
            todo.recurrenceSeriesId!.trim().isEmpty);
  }

  static List<TodoItem> activeMembers(
    Iterable<TodoItem> todos,
    String seriesId,
  ) =>
      todos
          .where((todo) => !todo.isDeleted && belongsToSeries(todo, seriesId))
          .toList()
        ..sort(
          (a, b) => (a.createdDate ?? a.createdAt).compareTo(
            b.createdDate ?? b.createdAt,
          ),
        );

  static Set<String> activeMemberIds(
    Iterable<TodoItem> todos,
    String seriesId,
  ) => activeMembers(todos, seriesId).map((todo) => todo.id).toSet();

  static TodoRecurrenceEditCounts countMembers(
    Iterable<TodoItem> todos,
    String seriesId, {
    required DateTime now,
  }) {
    final members = activeMembers(todos, seriesId);
    final today = DateTime(now.year, now.month, now.day);
    var historical = 0;
    var current = 0;
    var future = 0;
    var completed = 0;
    var skipped = 0;
    for (final member in members) {
      final start = DateTime.fromMillisecondsSinceEpoch(
        member.createdDate ?? member.createdAt,
        isUtc: true,
      ).toLocal();
      final startDay = DateTime(start.year, start.month, start.day);
      if (startDay.isBefore(today)) {
        historical++;
      } else if (startDay.isAfter(today)) {
        future++;
      } else {
        current++;
      }
      if (member.isDone) completed++;
      if (member.isSkipped) skipped++;
    }
    return TodoRecurrenceEditCounts(
      total: members.length,
      historical: historical,
      current: current,
      future: future,
      completed: completed,
      skipped: skipped,
    );
  }

  /// Shifts a series rule date by local calendar days without changing its
  /// wall-clock components across daylight-saving boundaries.
  static DateTime shiftCalendarDate(DateTime value, int dayDelta) {
    final local = value.toLocal();
    return DateTime(
      local.year,
      local.month,
      local.day + dayDelta,
      local.hour,
      local.minute,
      local.second,
      local.millisecond,
      local.microsecond,
    );
  }

  static int calendarDayDelta(DateTime from, DateTime to) {
    final localFrom = from.toLocal();
    final localTo = to.toLocal();
    final first = DateTime.utc(localFrom.year, localFrom.month, localFrom.day);
    final last = DateTime.utc(localTo.year, localTo.month, localTo.day);
    return last.difference(first).inDays;
  }
}

class TodoRecurrenceEditCounts {
  const TodoRecurrenceEditCounts({
    required this.total,
    required this.historical,
    required this.current,
    required this.future,
    required this.completed,
    required this.skipped,
  });

  final int total;
  final int historical;
  final int current;
  final int future;
  final int completed;
  final int skipped;
}
