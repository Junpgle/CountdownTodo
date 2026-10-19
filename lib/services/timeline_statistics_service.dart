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
    TimelineRecurrenceSeriesStatistics? best;
    for (final series in recurrenceSeries) {
      if (series.resolvedCount <= 0) continue;
      final currentBest = best;
      if (currentBest == null) {
        best = series;
        continue;
      }
      final rate = currentBest.completionRate.compareTo(series.completionRate);
      if (rate != 0) {
        if (rate < 0) best = series;
        continue;
      }
      final completed = currentBest.completedCount.compareTo(
        series.completedCount,
      );
      if (completed != 0) {
        if (completed < 0) best = series;
        continue;
      }
      if (currentBest.longestStreak < series.longestStreak) best = series;
    }
    return best;
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
    Set<String> excludedRecurrenceSeriesIds = const <String>{},
  }) {
    final effectiveNow = now ?? DateTime.now();
    final startMs = start.millisecondsSinceEpoch;
    final endMs = end.millisecondsSinceEpoch;
    final records = pomodoroRecords
        .where(
          (record) =>
              !record.isDeleted &&
              record.startTime >= startMs &&
              record.startTime < endMs,
        )
        .toList();
    final blocks = planBlocks
        .where(
          (block) =>
              !block.isDeleted &&
              block.startTime >= startMs &&
              block.startTime < endMs,
        )
        .toList();

    final tagNames = <String, String>{
      for (final tag in tags) tag.uuid: tag.name,
    };
    final focusByTag = <String, int>{};
    final seenTagUuids = <String>{};
    void addTaggedDuration(List<String> tagUuids, int seconds) {
      if (seconds <= 0) return;
      if (tagUuids.isEmpty) {
        focusByTag['未分类'] = (focusByTag['未分类'] ?? 0) + seconds;
        return;
      }
      seenTagUuids.clear();
      for (final uuid in tagUuids) {
        if (!seenTagUuids.add(uuid)) continue;
        final name = tagNames[uuid]?.trim();
        final displayName = name == null || name.isEmpty ? '已删除标签' : name;
        focusByTag[displayName] = (focusByTag[displayName] ?? 0) + seconds;
      }
    }

    var pomodoroSeconds = 0;
    var timeLogSeconds = 0;
    var timeLogCount = 0;
    var pauseSeconds = 0;
    var pauseCount = 0;
    for (final record in records) {
      final duration = record.effectiveDuration;
      pomodoroSeconds += math.max(0, duration);
      pauseSeconds += math.max(0, record.totalPauseSeconds ?? 0);
      final intervals = record.pauseIntervals?.length ?? 0;
      pauseCount += intervals > 0
          ? intervals
          : ((record.totalPauseSeconds ?? 0) > 0 ? 1 : 0);
      addTaggedDuration(record.tagUuids, duration);
    }
    for (final log in timeLogs) {
      if (log.isDeleted ||
          log.startTime < startMs ||
          log.startTime >= endMs ||
          log.endTime <= log.startTime) {
        continue;
      }
      timeLogCount++;
      final seconds = math.max(0, (log.endTime - log.startTime) ~/ 1000);
      timeLogSeconds += seconds;
      addTaggedDuration(log.tagUuids, seconds);
    }

    var planActualSeconds = 0;
    var planCompletedCount = 0;
    var planMissedCount = 0;
    var planSkippedCount = 0;
    final actualSecondsByBlock = _actualSecondsByBlock(blocks, records);
    for (var blockIndex = 0; blockIndex < blocks.length; blockIndex++) {
      final block = blocks[blockIndex];
      final actualSeconds = actualSecondsByBlock[blockIndex];
      planActualSeconds += actualSeconds;
      final reachedTarget =
          block.plannedMinutes > 0 &&
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

    final topFocusTags = focusByTag.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final recurrenceSeries = _calculateRecurrenceSeries(
      todos: todos,
      start: start,
      end: end,
      now: effectiveNow,
      excludedSeriesIds: excludedRecurrenceSeriesIds,
    );
    var recurringCompletedCount = 0;
    var recurringMissedCount = 0;
    var recurringPendingCount = 0;
    var recurringScheduledCount = 0;
    for (final series in recurrenceSeries) {
      recurringCompletedCount += series.completedCount;
      recurringMissedCount += series.missedCount;
      recurringPendingCount += series.pendingCount;
      recurringScheduledCount += series.scheduledCount;
    }

    final result = TimelineRangeStatistics(
      pomodoroFocusSeconds: pomodoroSeconds,
      timeLogSeconds: timeLogSeconds,
      pomodoroCount: records.length,
      timeLogCount: timeLogCount,
      pauseSeconds: pauseSeconds,
      pauseCount: pauseCount,
      plannedMinutes: blocks.fold<int>(
        0,
        (sum, block) => sum + block.plannedMinutes,
      ),
      planActualSeconds: planActualSeconds,
      planBlockCount: blocks.length,
      planCompletedCount: planCompletedCount,
      planMissedCount: planMissedCount,
      planSkippedCount: planSkippedCount,
      recurringCompletedCount: recurringCompletedCount,
      recurringScheduledCount: recurringScheduledCount,
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

  static List<int> _actualSecondsByBlock(
    List<TodoPlanBlock> blocks,
    List<PomodoroRecord> records,
  ) {
    if (blocks.isEmpty) return const <int>[];
    if (blocks.length * records.length <= 64) {
      return [
        for (final block in blocks) _actualSecondsForBlock(block, records),
      ];
    }

    final blocksById = <String, List<int>>{};
    final blocksByTodoId = <String, List<int>>{};
    final explicitBlocksByRecordId = <String, Set<int>>{};
    for (var blockIndex = 0; blockIndex < blocks.length; blockIndex++) {
      final block = blocks[blockIndex];
      blocksById.putIfAbsent(block.uuid, () => []).add(blockIndex);
      blocksByTodoId.putIfAbsent(block.todoId, () => []).add(blockIndex);
      for (final recordId in block.pomodoroRecordIds) {
        explicitBlocksByRecordId
            .putIfAbsent(recordId, () => <int>{})
            .add(blockIndex);
      }
    }

    final linkedSecondsByBlock = List<int>.filled(blocks.length, 0);
    for (final record in records) {
      final explicitlyLinked = explicitBlocksByRecordId[record.uuid];
      if (explicitlyLinked != null) {
        for (final blockIndex in explicitlyLinked) {
          linkedSecondsByBlock[blockIndex] += record.effectiveDuration;
        }
      }

      final planBlockId = record.planBlockId;
      final directlyLinked = planBlockId == null
          ? null
          : blocksById[planBlockId];
      if (directlyLinked != null) {
        for (final blockIndex in directlyLinked) {
          if (explicitlyLinked?.contains(blockIndex) == true) continue;
          linkedSecondsByBlock[blockIndex] += record.effectiveDuration;
        }
      }

      final todoUuid = record.todoUuid;
      if (planBlockId?.isNotEmpty == true || todoUuid == null) continue;
      final candidateBlocks = blocksByTodoId[todoUuid];
      if (candidateBlocks == null) continue;

      final recordEnd =
          record.endTime ?? record.startTime + record.effectiveDuration * 1000;
      for (final blockIndex in candidateBlocks) {
        final block = blocks[blockIndex];
        if (planBlockId == block.uuid ||
            explicitlyLinked?.contains(blockIndex) == true) {
          continue;
        }
        if (record.startTime < block.endTime && recordEnd > block.startTime) {
          linkedSecondsByBlock[blockIndex] += record.effectiveDuration;
        }
      }
    }
    return [
      for (var i = 0; i < blocks.length; i++)
        math.max(blocks[i].actualFocusSeconds, linkedSecondsByBlock[i]),
    ];
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
    required Set<String> excludedSeriesIds,
  }) {
    final occurrencesBySeriesDay = <String, List<TodoItem>>{};
    for (final todo in todos) {
      final seriesId = todo.recurrenceSeriesId?.trim();
      if (todo.isDeleted ||
          seriesId == null ||
          seriesId.isEmpty ||
          excludedSeriesIds.contains(seriesId)) {
        continue;
      }
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
      var isCompleted = representative.isDone;
      var due = _todoDueEnd(representative);
      for (final candidate in todosOnDay.skip(1)) {
        if (_preferRecurrenceOccurrence(candidate, representative)) {
          representative = candidate;
        }
        isCompleted = isCompleted || candidate.isDone;
        final candidateDue = _todoDueEnd(candidate);
        if (candidateDue != null &&
            (due == null || candidateDue.isAfter(due))) {
          due = candidateDue;
        }
      }
      final seriesId = representative.recurrenceSeriesId!.trim();
      final occurrenceStart = _todoStart(representative);
      final effectiveDue =
          due ??
          DateTime(
            occurrenceStart.year,
            occurrenceStart.month,
            occurrenceStart.day,
            23,
            59,
            59,
            999,
          );
      occurrencesBySeries
          .putIfAbsent(seriesId, () => [])
          .add(
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
      result.add(
        TimelineRecurrenceSeriesStatistics(
          seriesId: entry.key,
          title: occurrences.last.title,
          scheduledCount: occurrences.length,
          completedCount: completed,
          missedCount: missed,
          pendingCount: pending,
          longestStreak: longestStreak,
          endingStreak: endingStreak,
        ),
      );
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
    final looksDateOnly =
        due.hour == 0 &&
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
