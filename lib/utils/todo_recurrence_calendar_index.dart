import '../models.dart';

/// Indexes persisted recurrence occurrences for calendar projection.
///
/// A recurrence series can have only one occurrence starting on a given local
/// calendar day. Persisted occurrences take precedence over the calendar's
/// virtual projections.
class TodoRecurrenceCalendarIndex {
  TodoRecurrenceCalendarIndex(Iterable<TodoItem> todos) {
    for (final todo in todos) {
      final key = _keyForTodo(todo);
      if (todo.isDeleted || key == null) continue;
      final existing = _occurrenceBySeriesDay[key];
      if (existing == null || _prefer(todo, existing)) {
        _occurrenceBySeriesDay[key] = todo;
      }
    }
  }

  final Map<String, TodoItem> _occurrenceBySeriesDay = {};

  bool shouldDisplayPersisted(TodoItem todo) {
    final key = _keyForTodo(todo);
    if (key == null) return !todo.isDeleted;
    return !todo.isDeleted && _occurrenceBySeriesDay[key]?.id == todo.id;
  }

  bool shouldProjectVirtual(TodoItem source, DateTime targetDay) {
    final seriesId = source.recurrenceSeriesId;
    if (seriesId == null || seriesId.isEmpty) return true;
    final persisted = _occurrenceBySeriesDay[_key(seriesId, targetDay)];
    return persisted == null || persisted.id == source.id;
  }

  static bool _prefer(TodoItem candidate, TodoItem existing) {
    final candidateActive = candidate.recurrence != RecurrenceType.none;
    final existingActive = existing.recurrence != RecurrenceType.none;
    if (candidateActive != existingActive) return candidateActive;
    if (candidate.updatedAt != existing.updatedAt) {
      return candidate.updatedAt > existing.updatedAt;
    }
    return candidate.id.compareTo(existing.id) > 0;
  }

  static String? _keyForTodo(TodoItem todo) {
    final seriesId = todo.recurrenceSeriesId;
    if (seriesId == null || seriesId.isEmpty) return null;
    final start = DateTime.fromMillisecondsSinceEpoch(
      todo.createdDate ?? todo.createdAt,
      isUtc: true,
    ).toLocal();
    return _key(seriesId, start);
  }

  static String _key(String seriesId, DateTime day) =>
      '$seriesId|${day.year}-${day.month}-${day.day}';
}
