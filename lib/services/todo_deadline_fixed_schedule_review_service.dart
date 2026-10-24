import 'dart:convert';

import '../models.dart';

class TodoDeadlineFixedScheduleReviewEntry {
  const TodoDeadlineFixedScheduleReviewEntry({
    required this.beforeTodo,
    required this.afterTodo,
    required this.schedule,
  });

  final TodoItem beforeTodo;
  final TodoItem afterTodo;
  final FixedScheduleItem schedule;
}

class TodoDeadlineFixedScheduleReviewGroup {
  const TodoDeadlineFixedScheduleReviewGroup({
    required this.key,
    required this.title,
    required this.entries,
    this.seriesId,
  });

  final String key;
  final String title;
  final String? seriesId;
  final List<TodoDeadlineFixedScheduleReviewEntry> entries;

  bool get isSeries => seriesId != null;

  DateTime? get firstStart => entries
      .map((entry) => _localStart(entry.schedule))
      .whereType<DateTime>()
      .reduce((a, b) => a.isBefore(b) ? a : b);

  DateTime? get lastStart => entries
      .map((entry) => _localStart(entry.schedule))
      .whereType<DateTime>()
      .reduce((a, b) => a.isAfter(b) ? a : b);

  static DateTime? _localStart(FixedScheduleItem item) => item.startTime == null
      ? null
      : DateTime.fromMillisecondsSinceEpoch(item.startTime!).toLocal();
}

class TodoDeadlineFixedScheduleReview {
  const TodoDeadlineFixedScheduleReview({required this.groups});

  final List<TodoDeadlineFixedScheduleReviewGroup> groups;

  bool get needsReview => groups.isNotEmpty;

  int get entryCount =>
      groups.fold<int>(0, (count, group) => count + group.entries.length);
}

/// Builds a read-only review when an edited todo deadline falls after a linked
/// upcoming fixed schedule. A deadline is not treated as occupied time.
class TodoDeadlineFixedScheduleReviewService {
  TodoDeadlineFixedScheduleReviewService._();

  static bool deadlineChanged(TodoItem before, TodoItem after) =>
      before.dueDate?.millisecondsSinceEpoch !=
          after.dueDate?.millisecondsSinceEpoch ||
      before.isDateOnly != after.isDateOnly;

  static bool sameScheduleSnapshot(
    Iterable<FixedScheduleItem> left,
    Iterable<FixedScheduleItem> right,
  ) {
    List<FixedScheduleItem> ordered(Iterable<FixedScheduleItem> values) =>
        values.toList()..sort((a, b) => a.id.compareTo(b.id));
    return jsonEncode(ordered(left).map((item) => item.toJson()).toList()) ==
        jsonEncode(ordered(right).map((item) => item.toJson()).toList());
  }

  static TodoDeadlineFixedScheduleReview build({
    required Iterable<TodoItem> changedTodos,
    required Map<String, TodoItem> baselines,
    required Iterable<FixedScheduleItem> schedules,
    required DateTime now,
  }) {
    final currentTime = now.toLocal();
    final schedulesByTodoId = <String, List<FixedScheduleItem>>{};
    for (final schedule in schedules) {
      if (schedule.isDeleted || schedule.startTime == null) continue;
      for (final id in schedule.relatedTodoIds) {
        final normalizedId = id.trim();
        if (normalizedId.isEmpty) continue;
        schedulesByTodoId
            .putIfAbsent(normalizedId, () => <FixedScheduleItem>[])
            .add(schedule);
      }
    }

    final entriesByKey = <String, List<TodoDeadlineFixedScheduleReviewEntry>>{};
    final titlesByKey = <String, String>{};
    final seriesByKey = <String, String?>{};
    for (final after in changedTodos) {
      final before = baselines[after.id];
      if (before == null ||
          !deadlineChanged(before, after) ||
          after.isDeleted ||
          after.isDone ||
          after.isSkipped ||
          after.dueDate == null) {
        continue;
      }

      for (final schedule in schedulesByTodoId[after.id] ?? const []) {
        if (_normalizeTeamUuid(schedule.teamUuid) !=
            _normalizeTeamUuid(before.teamUuid)) {
          continue;
        }
        if (schedule.phaseAt(currentTime) != FixedSchedulePhase.upcoming ||
            !_deadlineIsAfterScheduleStart(after, schedule)) {
          continue;
        }

        final seriesId = schedule.recurrenceSeriesId?.trim();
        final normalizedSeriesId = seriesId == null || seriesId.isEmpty
            ? null
            : seriesId;
        final title = schedule.title.trim();
        final key = normalizedSeriesId == null
            ? 'schedule:${schedule.id}'
            : 'series:${normalizedSeriesId.length}:$normalizedSeriesId:${title.length}:$title';
        entriesByKey
            .putIfAbsent(key, () => <TodoDeadlineFixedScheduleReviewEntry>[])
            .add(
              TodoDeadlineFixedScheduleReviewEntry(
                beforeTodo: before,
                afterTodo: after,
                schedule: schedule,
              ),
            );
        titlesByKey[key] = title;
        seriesByKey[key] = normalizedSeriesId;
      }
    }

    final groups = <TodoDeadlineFixedScheduleReviewGroup>[];
    for (final entry in entriesByKey.entries) {
      final items = entry.value
        ..sort((a, b) {
          final startA = a.schedule.startTime ?? 0;
          final startB = b.schedule.startTime ?? 0;
          final startCompare = startA.compareTo(startB);
          if (startCompare != 0) return startCompare;
          final todoCompare = a.afterTodo.title.compareTo(b.afterTodo.title);
          return todoCompare != 0
              ? todoCompare
              : a.schedule.id.compareTo(b.schedule.id);
        });
      groups.add(
        TodoDeadlineFixedScheduleReviewGroup(
          key: entry.key,
          title: titlesByKey[entry.key] ?? items.first.schedule.title,
          entries: List.unmodifiable(items),
          seriesId: seriesByKey[entry.key],
        ),
      );
    }
    groups.sort((a, b) {
      final firstA = a.firstStart;
      final firstB = b.firstStart;
      if (firstA != null && firstB != null) {
        final compare = firstA.compareTo(firstB);
        if (compare != 0) return compare;
      }
      final titleCompare = a.title.compareTo(b.title);
      return titleCompare != 0 ? titleCompare : a.key.compareTo(b.key);
    });
    return TodoDeadlineFixedScheduleReview(groups: List.unmodifiable(groups));
  }

  static bool _deadlineIsAfterScheduleStart(
    TodoItem todo,
    FixedScheduleItem schedule,
  ) {
    final due = todo.dueDate?.toLocal();
    final startTime = schedule.startTime;
    if (due == null || startTime == null) return false;
    final start = DateTime.fromMillisecondsSinceEpoch(startTime).toLocal();
    if (todo.isDateOnly) {
      return DateTime(
        due.year,
        due.month,
        due.day,
      ).isAfter(DateTime(start.year, start.month, start.day));
    }
    return due.isAfter(start);
  }

  static String? _normalizeTeamUuid(String? value) {
    final normalized = value?.trim();
    return normalized == null || normalized.isEmpty ? null : normalized;
  }
}
