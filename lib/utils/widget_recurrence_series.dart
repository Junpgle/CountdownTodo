import '../models.dart';
import '../models/widget_snapshot.dart';
import '../services/todo_recurrence_date_service.dart';

const int _pastOccurrenceLimit = 8;
const int _futureOccurrenceLimit = 40;

/// Builds a compact, series-oriented catalog for the configurable macOS
/// recurrence widget.
///
/// A widget binds to [TodoItem.recurrenceSeriesId], while the concrete
/// occurrence IDs are allowed to roll forward. A small projected window keeps
/// the widget useful across date boundaries even when the Flutter app is not
/// currently running.
List<WidgetRecurrenceSeriesItem> buildWidgetRecurrenceSeries(
  Iterable<TodoItem> todos, {
  DateTime? now,
}) {
  final current = (now ?? DateTime.now()).toLocal();
  final occurrencesBySeries = <String, List<TodoItem>>{};

  for (final todo in todos) {
    final seriesId = todo.recurrenceSeriesId;
    if (todo.isDeleted || seriesId == null || seriesId.isEmpty) continue;
    occurrencesBySeries.putIfAbsent(seriesId, () => []).add(todo);
  }

  final result = <WidgetRecurrenceSeriesItem>[];
  for (final entry in occurrencesBySeries.entries) {
    final occurrences = entry.value
      ..sort((a, b) => _startOf(a).compareTo(_startOf(b)));
    final analysis = _analyzeSeriesOccurrences(occurrences, current);
    final ruleAnchor = analysis.ruleAnchor ?? analysis.representative;
    final representative = analysis.representative;
    final recurrenceEnd = ruleAnchor.recurrenceEndDate?.toLocal();
    final recurrenceEndDay = recurrenceEnd == null
        ? null
        : DateTime(
            recurrenceEnd.year,
            recurrenceEnd.month,
            recurrenceEnd.day,
            23,
            59,
            59,
            999,
          );
    final isActive =
        TodoRecurrenceDateService.nextDate(_startOf(ruleAnchor), ruleAnchor) !=
            null &&
        (recurrenceEndDay == null || !recurrenceEndDay.isBefore(current));

    result.add(
      WidgetRecurrenceSeriesItem(
        seriesId: entry.key,
        title: representative.title,
        recurrenceType: ruleAnchor.recurrence.name,
        recurrenceText: _recurrenceText(ruleAnchor),
        customIntervalDays: ruleAnchor.customIntervalDays,
        anchorStartMs: _startOf(ruleAnchor).millisecondsSinceEpoch,
        anchorDueMs: ruleAnchor.dueDate?.toLocal().millisecondsSinceEpoch,
        recurrenceEndMs: recurrenceEnd?.millisecondsSinceEpoch,
        isActive: isActive,
        contextText: _contextText(representative),
        completedCount: analysis.completedCount,
        overdueCount: analysis.overdueCount,
        elapsedCount: analysis.elapsedCount,
        totalCount: recurrenceEnd == null ? null : occurrences.length,
        occurrences: _buildOccurrenceWindow(
          occurrences,
          ruleAnchor: ruleAnchor,
          now: current,
          recurrenceEnd: recurrenceEndDay,
        ),
      ),
    );
  }

  result.sort((a, b) {
    if (a.isActive != b.isActive) return a.isActive ? -1 : 1;
    final aNext = _nextOccurrenceMs(a, current);
    final bNext = _nextOccurrenceMs(b, current);
    if (aNext != bNext) return aNext.compareTo(bNext);
    return a.title.compareTo(b.title);
  });
  return result;
}

_WidgetRecurrenceSeriesAnalysis _analyzeSeriesOccurrences(
  List<TodoItem> occurrences,
  DateTime now,
) {
  final today = DateTime(now.year, now.month, now.day);
  TodoItem? firstToday;
  TodoItem? firstUndoneToday;
  TodoItem? firstRule;
  TodoItem? lastStartedRule;
  TodoItem? lastPast;
  var completedCount = 0;
  var overdueCount = 0;
  var elapsedCount = 0;

  for (final todo in occurrences) {
    final start = _startOf(todo);
    if (start.year == today.year &&
        start.month == today.month &&
        start.day == today.day) {
      firstToday ??= todo;
      if (!todo.isDone) firstUndoneToday ??= todo;
    }
    if (todo.recurrence != RecurrenceType.none) {
      firstRule ??= todo;
      if (!start.isAfter(now)) lastStartedRule = todo;
    }
    if (!start.isAfter(now)) lastPast = todo;

    if (todo.isDone) {
      completedCount++;
      elapsedCount++;
      continue;
    }
    if (start.isAfter(now)) continue;
    elapsedCount++;
    final effectiveEnd =
        todo.dueDate?.toLocal() ??
        DateTime(start.year, start.month, start.day + 1);
    if (effectiveEnd.isBefore(now)) overdueCount++;
  }

  return _WidgetRecurrenceSeriesAnalysis(
    ruleAnchor: lastStartedRule ?? firstRule,
    representative:
        firstUndoneToday ??
        firstToday ??
        lastStartedRule ??
        firstRule ??
        lastPast ??
        occurrences.first,
    completedCount: completedCount,
    overdueCount: overdueCount,
    elapsedCount: elapsedCount,
  );
}

List<WidgetRecurrenceOccurrenceItem> _buildOccurrenceWindow(
  List<TodoItem> actualOccurrences, {
  required TodoItem ruleAnchor,
  required DateTime now,
  required DateTime? recurrenceEnd,
}) {
  final projectedItems = <WidgetRecurrenceOccurrenceItem>[];
  if (ruleAnchor.recurrence != RecurrenceType.none) {
    var projectedStart = _startOf(ruleAnchor);
    final anchorDue = ruleAnchor.dueDate?.toLocal();
    final dueOffset = anchorDue?.difference(projectedStart);
    for (var i = 0; i < _futureOccurrenceLimit; i++) {
      if (recurrenceEnd != null && projectedStart.isAfter(recurrenceEnd)) break;
      final key = projectedStart.millisecondsSinceEpoch;
      projectedItems.add(
        WidgetRecurrenceOccurrenceItem(
          occurrenceId: '',
          startAtMs: key,
          dueAtMs: dueOffset == null
              ? null
              : projectedStart.add(dueOffset).millisecondsSinceEpoch,
          isDateOnly: ruleAnchor.isDateOnly,
          isProjected: true,
        ),
      );
      final nextStart = TodoRecurrenceDateService.nextDate(
        projectedStart,
        ruleAnchor,
      );
      if (nextStart == null) break;
      projectedStart = nextStart;
    }
  }

  final nowMs = now.millisecondsSinceEpoch;
  int actualStartAt(int index) =>
      _startOf(actualOccurrences[index]).millisecondsSinceEpoch;

  WidgetRecurrenceOccurrenceItem actualItem(
    TodoItem occurrence,
    int startAtMs,
  ) => WidgetRecurrenceOccurrenceItem(
    occurrenceId: occurrence.id,
    startAtMs: startAtMs,
    dueAtMs: occurrence.dueDate?.toLocal().millisecondsSinceEpoch,
    isDone: occurrence.isDone,
    isDateOnly: occurrence.isDateOnly,
  );

  int lowerBoundActual(int target) {
    var low = 0;
    var high = actualOccurrences.length;
    while (low < high) {
      final middle = (low + high) >> 1;
      if (actualStartAt(middle) < target) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    return low;
  }

  int lowerBoundProjected(int target) {
    var low = 0;
    var high = projectedItems.length;
    while (low < high) {
      final middle = (low + high) >> 1;
      if (projectedItems[middle].startAtMs < target) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    return low;
  }

  // Actual occurrences are already sorted by the caller, and projections are
  // chronological. Merge only the visible window instead of materializing all
  // historical instances. Actual items keep the former duplicate-date winner.
  final firstFutureActualIndex = lowerBoundActual(nowMs);
  final firstFutureProjectedIndex = lowerBoundProjected(nowMs);
  var actualPastIndex = firstFutureActualIndex - 1;
  var projectedPastIndex = firstFutureProjectedIndex - 1;
  final pastDescending = <WidgetRecurrenceOccurrenceItem>[];
  while (pastDescending.length < _pastOccurrenceLimit &&
      (actualPastIndex >= 0 || projectedPastIndex >= 0)) {
    final actualStart = actualPastIndex < 0
        ? null
        : actualStartAt(actualPastIndex);
    final projectedStart = projectedPastIndex < 0
        ? null
        : projectedItems[projectedPastIndex].startAtMs;
    if (projectedStart == null ||
        (actualStart != null && actualStart >= projectedStart)) {
      final startAtMs = actualStart!;
      pastDescending.add(
        actualItem(actualOccurrences[actualPastIndex], startAtMs),
      );
      var beforeSameStart = actualPastIndex - 1;
      while (beforeSameStart >= 0 &&
          actualStartAt(beforeSameStart) == startAtMs) {
        beforeSameStart--;
      }
      actualPastIndex = beforeSameStart;
      if (projectedStart == startAtMs) projectedPastIndex--;
    } else {
      pastDescending.add(projectedItems[projectedPastIndex]);
      projectedPastIndex--;
    }
  }

  var actualFutureIndex = firstFutureActualIndex;
  var projectedFutureIndex = firstFutureProjectedIndex;
  final futureItems = <WidgetRecurrenceOccurrenceItem>[];
  while (futureItems.length < _futureOccurrenceLimit &&
      (actualFutureIndex < actualOccurrences.length ||
          projectedFutureIndex < projectedItems.length)) {
    final actualStart = actualFutureIndex >= actualOccurrences.length
        ? null
        : actualStartAt(actualFutureIndex);
    final projectedStart = projectedFutureIndex >= projectedItems.length
        ? null
        : projectedItems[projectedFutureIndex].startAtMs;
    if (projectedStart == null ||
        (actualStart != null && actualStart <= projectedStart)) {
      final startAtMs = actualStart!;
      var afterSameStart = actualFutureIndex + 1;
      while (afterSameStart < actualOccurrences.length &&
          actualStartAt(afterSameStart) == startAtMs) {
        afterSameStart++;
      }
      futureItems.add(
        actualItem(actualOccurrences[afterSameStart - 1], startAtMs),
      );
      actualFutureIndex = afterSameStart;
      if (projectedStart == startAtMs) projectedFutureIndex++;
    } else {
      futureItems.add(projectedItems[projectedFutureIndex]);
      projectedFutureIndex++;
    }
  }

  final result = <WidgetRecurrenceOccurrenceItem>[
    for (var index = pastDescending.length - 1; index >= 0; index--)
      pastDescending[index],
    ...futureItems,
  ];
  return result;
}

DateTime _startOf(TodoItem todo) => todo.effectiveStartTime;

String _recurrenceText(TodoItem todo) {
  if (todo.recurrence == RecurrenceType.customDays) {
    final interval = todo.customIntervalDays ?? 0;
    return interval > 0 ? '每 $interval 天' : '循环间隔无效';
  }
  return switch (todo.recurrence) {
    RecurrenceType.none => '循环已结束',
    RecurrenceType.daily => '每天',
    RecurrenceType.customDays => '循环间隔无效',
    RecurrenceType.weekly => '每周',
    RecurrenceType.monthly => '每月',
    RecurrenceType.yearly => '每年',
    RecurrenceType.weekdays => '工作日',
  };
}

String? _contextText(TodoItem todo) {
  final teamName = todo.teamName?.trim();
  if (teamName != null && teamName.isNotEmpty) return teamName;
  return null;
}

int _nextOccurrenceMs(WidgetRecurrenceSeriesItem series, DateTime now) {
  final nowMs = now.millisecondsSinceEpoch;
  for (final occurrence in series.occurrences) {
    if (occurrence.startAtMs >= nowMs) return occurrence.startAtMs;
  }
  return 1 << 62;
}

class _WidgetRecurrenceSeriesAnalysis {
  final TodoItem? ruleAnchor;
  final TodoItem representative;
  final int completedCount;
  final int overdueCount;
  final int elapsedCount;

  const _WidgetRecurrenceSeriesAnalysis({
    required this.ruleAnchor,
    required this.representative,
    required this.completedCount,
    required this.overdueCount,
    required this.elapsedCount,
  });
}
