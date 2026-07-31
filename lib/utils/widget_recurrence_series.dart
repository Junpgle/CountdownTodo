import '../models.dart';
import '../models/widget_snapshot.dart';

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
    final activeRules = occurrences
        .where((todo) => todo.recurrence != RecurrenceType.none)
        .toList();
    final ruleAnchor = _selectRuleAnchor(activeRules, current) ??
        _selectRepresentative(occurrences, current);
    final representative = _selectRepresentative(occurrences, current);
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
    final isActive = ruleAnchor.recurrence != RecurrenceType.none &&
        (recurrenceEndDay == null || !recurrenceEndDay.isBefore(current));

    var completedCount = 0;
    var overdueCount = 0;
    var elapsedCount = 0;
    for (final occurrence in occurrences) {
      final start = _startOf(occurrence);
      if (occurrence.isDone) {
        completedCount++;
        elapsedCount++;
        continue;
      }
      if (start.isAfter(current)) continue;
      elapsedCount++;
      final effectiveEnd = occurrence.dueDate?.toLocal() ??
          DateTime(start.year, start.month, start.day + 1);
      if (effectiveEnd.isBefore(current)) overdueCount++;
    }

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
        completedCount: completedCount,
        overdueCount: overdueCount,
        elapsedCount: elapsedCount,
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

TodoItem? _selectRuleAnchor(List<TodoItem> activeRules, DateTime now) {
  if (activeRules.isEmpty) return null;
  final pastOrCurrent =
      activeRules.where((todo) => !_startOf(todo).isAfter(now)).toList();
  if (pastOrCurrent.isNotEmpty) return pastOrCurrent.last;
  return activeRules.first;
}

TodoItem _selectRepresentative(List<TodoItem> occurrences, DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  final todayOccurrences = occurrences.where((todo) {
    final start = _startOf(todo);
    return DateTime(start.year, start.month, start.day) == today;
  }).toList();
  if (todayOccurrences.isNotEmpty) {
    return todayOccurrences.firstWhere(
      (todo) => !todo.isDone,
      orElse: () => todayOccurrences.first,
    );
  }

  final active = occurrences
      .where((todo) => todo.recurrence != RecurrenceType.none)
      .toList();
  if (active.isNotEmpty) return _selectRuleAnchor(active, now)!;

  final past =
      occurrences.where((todo) => !_startOf(todo).isAfter(now)).toList();
  if (past.isNotEmpty) return past.last;
  return occurrences.first;
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
      projectedStart = _nextRecurrenceStart(projectedStart, ruleAnchor);
    }
  }

  final sorted = byStartMs.values.toList()
    ..sort((a, b) => a.startAtMs.compareTo(b.startAtMs));
  final nowMs = now.millisecondsSinceEpoch;
  final past = sorted.where((item) => item.startAtMs < nowMs).toList();
  final future = sorted.where((item) => item.startAtMs >= nowMs).toList();
  return [
    ...past.skip((past.length - _pastOccurrenceLimit).clamp(0, past.length)),
    ...future.take(_futureOccurrenceLimit),
  ];
}

DateTime _nextRecurrenceStart(DateTime current, TodoItem todo) {
  switch (todo.recurrence) {
    case RecurrenceType.daily:
      return DateTime(
        current.year,
        current.month,
        current.day + 1,
        current.hour,
        current.minute,
        current.second,
        current.millisecond,
      );
    case RecurrenceType.customDays:
      return DateTime(
        current.year,
        current.month,
        current.day + (todo.customIntervalDays ?? 1).clamp(1, 3650),
        current.hour,
        current.minute,
        current.second,
        current.millisecond,
      );
    case RecurrenceType.weekly:
      return DateTime(
        current.year,
        current.month,
        current.day + 7,
        current.hour,
        current.minute,
        current.second,
        current.millisecond,
      );
    case RecurrenceType.weekdays:
      var next = DateTime(
        current.year,
        current.month,
        current.day + 1,
        current.hour,
        current.minute,
        current.second,
        current.millisecond,
      );
      while (next.weekday == DateTime.saturday ||
          next.weekday == DateTime.sunday) {
        next = DateTime(
          next.year,
          next.month,
          next.day + 1,
          next.hour,
          next.minute,
          next.second,
          next.millisecond,
        );
      }
      return next;
    case RecurrenceType.monthly:
      final targetMonth = DateTime(current.year, current.month + 1);
      final lastDay = DateTime(targetMonth.year, targetMonth.month + 1, 0).day;
      return DateTime(
        targetMonth.year,
        targetMonth.month,
        current.day.clamp(1, lastDay),
        current.hour,
        current.minute,
        current.second,
        current.millisecond,
      );
    case RecurrenceType.yearly:
      final lastDay = DateTime(current.year + 1, current.month + 1, 0).day;
      return DateTime(
        current.year + 1,
        current.month,
        current.day.clamp(1, lastDay),
        current.hour,
        current.minute,
        current.second,
        current.millisecond,
      );
    case RecurrenceType.none:
      return current;
  }
}

DateTime _startOf(TodoItem todo) => todo.effectiveStartTime;

String _recurrenceText(TodoItem todo) {
  return switch (todo.recurrence) {
    RecurrenceType.none => '循环已结束',
    RecurrenceType.daily => '每天',
    RecurrenceType.customDays => '每 ${todo.customIntervalDays ?? 1} 天',
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
