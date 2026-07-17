import '../models.dart';

/// 将任务选择器中的同系列循环实例折叠为一个真实实例。
///
/// 优先选择目标日期上的真实期次；没有同日期实例时再选择当前循环锚点，
/// 最后回退到最近的过去期次或最早的未来期次。
List<TodoItem> collapseRecurrenceSeriesForTodoPicker(
  Iterable<TodoItem> todos, {
  DateTime? now,
  String? preferredTodoId,
}) {
  final visibleTodos = todos.where((todo) => !todo.isDeleted).toList();
  final occurrencesBySeries = <String, List<TodoItem>>{};
  for (final todo in visibleTodos) {
    final seriesId = todo.recurrenceSeriesId;
    if (seriesId == null || seriesId.isEmpty) continue;
    occurrencesBySeries.putIfAbsent(seriesId, () => []).add(todo);
  }

  final todaySource = (now ?? DateTime.now()).toLocal();
  final today = DateTime(
    todaySource.year,
    todaySource.month,
    todaySource.day,
  );
  final representativeIds = <String, String>{};
  for (final entry in occurrencesBySeries.entries) {
    final preferred = entry.value.cast<TodoItem?>().firstWhere(
          (todo) => todo?.id == preferredTodoId,
          orElse: () => null,
        );
    representativeIds[entry.key] =
        preferred?.id ?? _selectPickerOccurrence(entry.value, today).id;
  }

  return visibleTodos.where((todo) {
    final seriesId = todo.recurrenceSeriesId;
    if (seriesId == null || seriesId.isEmpty) return true;
    return representativeIds[seriesId] == todo.id;
  }).toList();
}

bool areSameTodoOrRecurrenceSeries(TodoItem? first, TodoItem? second) {
  if (first == null || second == null) return first == null && second == null;
  if (first.id == second.id) return true;
  final firstSeriesId = first.recurrenceSeriesId;
  final secondSeriesId = second.recurrenceSeriesId;
  return firstSeriesId != null &&
      firstSeriesId.isNotEmpty &&
      firstSeriesId == secondSeriesId;
}

TodoItem _selectPickerOccurrence(
  List<TodoItem> occurrences,
  DateTime today,
) {
  final todayOccurrences = occurrences
      .where((todo) => _startDay(todo).isAtSameMomentAs(today))
      .toList();
  if (todayOccurrences.isNotEmpty) {
    final activeToday = todayOccurrences
        .where((todo) => todo.recurrence != RecurrenceType.none)
        .toList();
    return _preferIncomplete(
      activeToday.isNotEmpty ? activeToday : todayOccurrences,
    );
  }

  final active = occurrences
      .where((todo) => todo.recurrence != RecurrenceType.none)
      .toList();
  if (active.isNotEmpty) {
    return _preferIncomplete(active);
  }

  final pastOccurrences = occurrences
      .where((todo) => _startDay(todo).isBefore(today))
      .toList()
    ..sort((a, b) => _todoStartMs(b).compareTo(_todoStartMs(a)));
  if (pastOccurrences.isNotEmpty) {
    return _preferIncompleteWithSameStart(pastOccurrences);
  }

  final futureOccurrences = List<TodoItem>.from(occurrences)
    ..sort((a, b) => _todoStartMs(a).compareTo(_todoStartMs(b)));
  return _preferIncompleteWithSameStart(futureOccurrences);
}

TodoItem _preferIncomplete(List<TodoItem> occurrences) {
  return occurrences.cast<TodoItem?>().firstWhere(
        (todo) => todo?.isDone == false,
        orElse: () => occurrences.first,
      )!;
}

TodoItem _preferIncompleteWithSameStart(List<TodoItem> occurrences) {
  final firstStart = _todoStartMs(occurrences.first);
  final sameStart = occurrences
      .takeWhile((todo) => _todoStartMs(todo) == firstStart)
      .toList();
  return _preferIncomplete(sameStart);
}

int _todoStartMs(TodoItem todo) => todo.createdDate ?? todo.createdAt;

DateTime _startDay(TodoItem todo) {
  final start = DateTime.fromMillisecondsSinceEpoch(
    _todoStartMs(todo),
    isUtc: true,
  ).toLocal();
  return DateTime(start.year, start.month, start.day);
}
