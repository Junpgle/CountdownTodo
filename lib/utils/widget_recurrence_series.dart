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
  final byStartMs = <int, WidgetRecurrenceOccurrenceItem>{};
  for (final occurrence in actualOccurrences) {
    final start = _startOf(occurrence);
    byStartMs[start.millisecondsSinceEpoch] = WidgetRecurrenceOccurrenceItem(
      occurrenceId: occurrence.id,
      startAtMs: start.millisecondsSinceEpoch,
      dueAtMs: occurrence.dueDate?.toLocal().millisecondsSinceEpoch,
      isDone: occurrence.isDone,
      isDateOnly: occurrence.isDateOnly,
    );
  }

  if (ruleAnchor.recurrence != RecurrenceType.none) {
    var projectedStart = _startOf(ruleAnchor);
    final anchorDue = ruleAnchor.dueDate?.toLocal();
    final dueOffset = anchorDue?.difference(projectedStart);
    for (var i = 0; i < _futureOccurrenceLimit; i++) {
      if (recurrenceEnd != null && projectedStart.isAfter(recurrenceEnd)) break;
      final key = projectedStart.millisecondsSinceEpoch;
      byStartMs.putIfAbsent(
        key,
        () => WidgetRecurrenceOccurrenceItem(
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

  final sorted = byStartMs.values.toList()
    ..sort((a, b) => a.startAtMs.compareTo(b.startAtMs));
  final nowMs = now.millisecondsSinceEpoch;
  var low = 0;
  var high = sorted.length;
  while (low < high) {
    final middle = (low + high) >> 1;
    if (sorted[middle].startAtMs < nowMs) {
      low = middle + 1;
    } else {
      high = middle;
    }
  }

  final firstPast = low > _pastOccurrenceLimit ? low - _pastOccurrenceLimit : 0;
  final afterFuture = low + _futureOccurrenceLimit < sorted.length
      ? low + _futureOccurrenceLimit
      : sorted.length;
  return sorted.sublist(firstPast, afterFuture);
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
