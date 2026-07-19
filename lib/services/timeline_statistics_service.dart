import 'dart:math' as math;

import '../models.dart';
import 'pomodoro_service.dart';

class TimelineRecurrenceSeriesStatistics {
  const TimelineRecurrenceSeriesStatistics({
    required this.seriesId,
    required this.title,
    required this.scheduledCount,
    required this.completedCount,
    required this.missedCount,
    required this.pendingCount,
    required this.longestStreak,
    required this.endingStreak,
  });

  final String seriesId;
  final String title;
  final int scheduledCount;
  final int completedCount;
  final int missedCount;
  final int pendingCount;
  final int longestStreak;
  final int endingStreak;

  int get resolvedCount => completedCount + missedCount;

  double get completionRate =>
      resolvedCount > 0 ? completedCount / resolvedCount : 0;
}

/// Aggregates the newer productivity data sources used by the personal report.
///
/// Keeping these calculations outside the widget makes the report, the poster,
/// and future entry points share the same range and de-duplication rules.
class TimelineRangeStatistics {
  const TimelineRangeStatistics({
    required this.pomodoroFocusSeconds,
    required this.timeLogSeconds,
    required this.pomodoroCount,
    required this.timeLogCount,
    required this.pauseSeconds,
    required this.pauseCount,
    required this.plannedMinutes,
    required this.planActualSeconds,
    required this.planBlockCount,
    required this.planCompletedCount,
    required this.planMissedCount,
    required this.planSkippedCount,
    required this.recurringCompletedCount,
    required this.recurringScheduledCount,
    required this.recurringMissedCount,
    required this.recurringPendingCount,
    required this.recurrenceSeries,
    required this.topFocusTags,
  });

  final int pomodoroFocusSeconds;
  final int timeLogSeconds;
  final int pomodoroCount;
  final int timeLogCount;
  final int pauseSeconds;
  final int pauseCount;
  final int plannedMinutes;
  final int planActualSeconds;
  final int planBlockCount;
  final int planCompletedCount;
  final int planMissedCount;
  final int planSkippedCount;
  final int recurringCompletedCount;
  final int recurringScheduledCount;
  final int recurringMissedCount;
  final int recurringPendingCount;
  final List<TimelineRecurrenceSeriesStatistics> recurrenceSeries;
  final List<MapEntry<String, int>> topFocusTags;

  int get totalFocusSeconds => pomodoroFocusSeconds + timeLogSeconds;

  int get focusSessionCount => pomodoroCount + timeLogCount;

  double get planAchievementRate =>
      plannedMinutes > 0 ? planActualSeconds / (plannedMinutes * 60) : 0;

  int get recurringResolvedCount =>
      recurringCompletedCount + recurringMissedCount;

  double get recurringCompletionRate => recurringResolvedCount > 0
      ? recurringCompletedCount / recurringResolvedCount
      : 0;

  int get recurrenceSeriesCount => recurrenceSeries.length;

  int get recurringLongestStreak => recurrenceSeries.fold<int>(
        0,
        (longest, series) => math.max(longest, series.longestStreak),
      );

  TimelineRecurrenceSeriesStatistics? get bestRecurrenceSeries {
    final resolved =
        recurrenceSeries.where((series) => series.resolvedCount > 0).toList();
    if (resolved.isEmpty) return null;
    resolved.sort((a, b) {
      final rate = b.completionRate.compareTo(a.completionRate);
      if (rate != 0) return rate;
      final completed = b.completedCount.compareTo(a.completedCount);
      if (completed != 0) return completed;
      return b.longestStreak.compareTo(a.longestStreak);
    });
    return resolved.first;
  }
}

class TimelineStatisticsService {
  const TimelineStatisticsService._();

  static TimelineRangeStatistics calculate({
    required DateTime start,
    required DateTime end,
    required List<PomodoroRecord> pomodoroRecords,
    required List<TimeLogItem> timeLogs,
    required List<TodoPlanBlock> planBlocks,
    required List<TodoItem> todos,
    required List<PomodoroTag> tags,
    DateTime? now,
  }) {
    final effectiveNow = now ?? DateTime.now();
    final startMs = start.millisecondsSinceEpoch;
    final endMs = end.millisecondsSinceEpoch;
    final records = pomodoroRecords
        .where((record) =>
            !record.isDeleted &&
            record.startTime >= startMs &&
            record.startTime < endMs)
        .toList();
    final logs = timeLogs
        .where((log) =>
            !log.isDeleted &&
            log.startTime >= startMs &&
            log.startTime < endMs &&
            log.endTime > log.startTime)
        .toList();
    final blocks = planBlocks
        .where((block) =>
            !block.isDeleted &&
            block.startTime >= startMs &&
            block.startTime < endMs)
        .toList();

    final pomodoroSeconds = records.fold<int>(
      0,
      (sum, record) => sum + math.max(0, record.effectiveDuration),
    );
    final timeLogSeconds = logs.fold<int>(
      0,
      (sum, log) => sum + math.max(0, (log.endTime - log.startTime) ~/ 1000),
    );
    final pauseSeconds = records.fold<int>(
      0,
      (sum, record) => sum + math.max(0, record.totalPauseSeconds ?? 0),
    );
    final pauseCount = records.fold<int>(0, (sum, record) {
      final intervals = record.pauseIntervals?.length ?? 0;
      return sum +
          (intervals > 0
              ? intervals
              : ((record.totalPauseSeconds ?? 0) > 0 ? 1 : 0));
    });

    var planActualSeconds = 0;
    var planCompletedCount = 0;
    var planMissedCount = 0;
    var planSkippedCount = 0;
    for (final block in blocks) {
      final actualSeconds = _actualSecondsForBlock(block, records);
      planActualSeconds += actualSeconds;
      final reachedTarget = block.plannedMinutes > 0 &&
          actualSeconds >= block.plannedMinutes * 60 * 0.8;
      if (block.status == TodoPlanStatus.finished || reachedTarget) {
        planCompletedCount++;
      } else if (block.status == TodoPlanStatus.missed) {
        planMissedCount++;
      } else if (block.status == TodoPlanStatus.skipped ||
          block.status == TodoPlanStatus.cancelled) {
        planSkippedCount++;
      }
    }

    final tagNames = <String, String>{
      for (final tag in tags) tag.uuid: tag.name,
    };
    final focusByTag = <String, int>{};
    void addTaggedDuration(List<String> tagUuids, int seconds) {
      if (seconds <= 0) return;
      if (tagUuids.isEmpty) {
        focusByTag['未分类'] = (focusByTag['未分类'] ?? 0) + seconds;
        return;
      }
      for (final uuid in tagUuids.toSet()) {
        final name = tagNames[uuid]?.trim();
        final displayName = name == null || name.isEmpty ? '已删除标签' : name;
        focusByTag[displayName] = (focusByTag[displayName] ?? 0) + seconds;
      }
    }

    for (final record in records) {
      addTaggedDuration(record.tagUuids, record.effectiveDuration);
    }
    for (final log in logs) {
      addTaggedDuration(
        log.tagUuids,
        math.max(0, (log.endTime - log.startTime) ~/ 1000),
      );
    }
    final topFocusTags = focusByTag.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final recurrenceSeries = _calculateRecurrenceSeries(
      todos: todos,
      start: start,
      end: end,
      now: effectiveNow,
    );
    final recurringCompletedCount = recurrenceSeries.fold<int>(
      0,
      (sum, series) => sum + series.completedCount,
    );
    final recurringMissedCount = recurrenceSeries.fold<int>(
      0,
      (sum, series) => sum + series.missedCount,
    );
    final recurringPendingCount = recurrenceSeries.fold<int>(
      0,
      (sum, series) => sum + series.pendingCount,
    );

    final result = TimelineRangeStatistics(
      pomodoroFocusSeconds: pomodoroSeconds,
      timeLogSeconds: timeLogSeconds,
      pomodoroCount: records.length,
      timeLogCount: logs.length,
      pauseSeconds: pauseSeconds,
      pauseCount: pauseCount,
      plannedMinutes:
          blocks.fold<int>(0, (sum, block) => sum + block.plannedMinutes),
      planActualSeconds: planActualSeconds,
      planBlockCount: blocks.length,
      planCompletedCount: planCompletedCount,
      planMissedCount: planMissedCount,
      planSkippedCount: planSkippedCount,
      recurringCompletedCount: recurringCompletedCount,
      recurringScheduledCount: recurrenceSeries.fold<int>(
        0,
        (sum, series) => sum + series.scheduledCount,
      ),
      recurringMissedCount: recurringMissedCount,
      recurringPendingCount: recurringPendingCount,
      recurrenceSeries: recurrenceSeries,
      topFocusTags: topFocusTags.take(5).toList(),
    );
    return result;
  }

  static int _actualSecondsForBlock(
    TodoPlanBlock block,
    List<PomodoroRecord> records,
  ) {
    final linkedRecordSeconds = records
        .where((record) => _recordBelongsToBlock(record, block))
        .fold<int>(0, (sum, record) => sum + record.effectiveDuration);
    return math.max(block.actualFocusSeconds, linkedRecordSeconds);
  }

  static bool _recordBelongsToBlock(
    PomodoroRecord record,
    TodoPlanBlock block,
  ) {
    if (record.planBlockId == block.uuid ||
        block.pomodoroRecordIds.contains(record.uuid)) {
      return true;
    }
    if (record.planBlockId?.isNotEmpty == true ||
        record.todoUuid == null ||
        record.todoUuid != block.todoId) {
      return false;
    }
    final recordEnd =
        record.endTime ?? record.startTime + record.effectiveDuration * 1000;
    return record.startTime < block.endTime && recordEnd > block.startTime;
  }

  static List<TimelineRecurrenceSeriesStatistics> _calculateRecurrenceSeries({
    required List<TodoItem> todos,
    required DateTime start,
    required DateTime end,
    required DateTime now,
  }) {
    final occurrencesBySeriesDay = <String, List<TodoItem>>{};
    for (final todo in todos) {
      final seriesId = todo.recurrenceSeriesId?.trim();
      if (todo.isDeleted || seriesId == null || seriesId.isEmpty) continue;
      final occurrenceStart = _todoStart(todo);
      if (occurrenceStart.isBefore(start) || !occurrenceStart.isBefore(end)) {
        continue;
      }
      if (occurrenceStart.isAfter(now)) continue;
      final dayKey =
          '$seriesId|${occurrenceStart.year}-${occurrenceStart.month}-${occurrenceStart.day}';
      occurrencesBySeriesDay.putIfAbsent(dayKey, () => []).add(todo);
    }

    final occurrencesBySeries = <String, List<_RecurrenceOccurrence>>{};
    for (final entry in occurrencesBySeriesDay.entries) {
      final todosOnDay = entry.value;
      var representative = todosOnDay.first;
      for (final candidate in todosOnDay.skip(1)) {
        if (_preferRecurrenceOccurrence(candidate, representative)) {
          representative = candidate;
        }
      }
      final seriesId = representative.recurrenceSeriesId!.trim();
      final occurrenceStart = _todoStart(representative);
      final isCompleted = todosOnDay.any((todo) => todo.isDone);
      final due = todosOnDay
          .map(_todoDueEnd)
          .whereType<DateTime>()
          .fold<DateTime?>(null, (latest, value) {
        if (latest == null || value.isAfter(latest)) return value;
        return latest;
      });
      final effectiveDue = due ??
          DateTime(
            occurrenceStart.year,
            occurrenceStart.month,
            occurrenceStart.day,
            23,
            59,
            59,
            999,
          );
      occurrencesBySeries.putIfAbsent(seriesId, () => []).add(
            _RecurrenceOccurrence(
              start: occurrenceStart,
              title: representative.title,
              isCompleted: isCompleted,
              isMissed: !isCompleted && effectiveDue.isBefore(now),
            ),
          );
    }

    final result = <TimelineRecurrenceSeriesStatistics>[];
    for (final entry in occurrencesBySeries.entries) {
      final occurrences = entry.value
        ..sort((a, b) => a.start.compareTo(b.start));
      var completed = 0;
      var missed = 0;
      var pending = 0;
      var runningStreak = 0;
      var longestStreak = 0;
      for (final occurrence in occurrences) {
        if (occurrence.isCompleted) {
          completed++;
          runningStreak++;
          longestStreak = math.max(longestStreak, runningStreak);
        } else if (occurrence.isMissed) {
          missed++;
          runningStreak = 0;
        } else {
          pending++;
        }
      }

      var endingStreak = 0;
      for (final occurrence in occurrences.reversed) {
        if (!occurrence.isCompleted && !occurrence.isMissed) continue;
        if (!occurrence.isCompleted) break;
        endingStreak++;
      }
      result.add(TimelineRecurrenceSeriesStatistics(
        seriesId: entry.key,
        title: occurrences.last.title,
        scheduledCount: occurrences.length,
        completedCount: completed,
        missedCount: missed,
        pendingCount: pending,
        longestStreak: longestStreak,
        endingStreak: endingStreak,
      ));
    }
    result.sort((a, b) {
      final completed = b.completedCount.compareTo(a.completedCount);
      if (completed != 0) return completed;
      final rate = b.completionRate.compareTo(a.completionRate);
      if (rate != 0) return rate;
      return b.longestStreak.compareTo(a.longestStreak);
    });
    return result;
  }

  static bool _preferRecurrenceOccurrence(
    TodoItem candidate,
    TodoItem existing,
  ) {
    if (candidate.isDone != existing.isDone) return candidate.isDone;
    final candidateActive = candidate.recurrence != RecurrenceType.none;
    final existingActive = existing.recurrence != RecurrenceType.none;
    if (candidateActive != existingActive) return candidateActive;
    if (candidate.version != existing.version) {
      return candidate.version > existing.version;
    }
    return candidate.updatedAt > existing.updatedAt;
  }

  static DateTime _todoStart(TodoItem todo) =>
      DateTime.fromMillisecondsSinceEpoch(
        todo.createdDate ?? todo.createdAt,
        isUtc: true,
      ).toLocal();

  static DateTime? _todoDueEnd(TodoItem todo) {
    final due = todo.dueDate?.toLocal();
    if (due == null) return null;
    final looksDateOnly = due.hour == 0 &&
        due.minute == 0 &&
        due.second == 0 &&
        due.millisecond == 0;
    if (!todo.isAllDayTask && !looksDateOnly) return due;
    return DateTime(due.year, due.month, due.day, 23, 59, 59, 999);
  }
}

class _RecurrenceOccurrence {
  const _RecurrenceOccurrence({
    required this.start,
    required this.title,
    required this.isCompleted,
    required this.isMissed,
  });

  final DateTime start;
  final String title;
  final bool isCompleted;
  final bool isMissed;
}
