import '../models.dart';
import 'pomodoro_service.dart';

enum TimeLogOverlapSource { manualLog, pomodoro }

class TimeLogOverlapInterval {
  const TimeLogOverlapInterval({
    required this.startTime,
    required this.endTime,
  });

  final int startTime;
  final int endTime;

  int get durationMilliseconds => endTime - startTime;
}

class TimeLogOverlap {
  const TimeLogOverlap({
    required this.source,
    required this.id,
    required this.title,
    required this.startTime,
    required this.endTime,
    required this.overlapIntervals,
    required this.overlapMilliseconds,
  });

  final TimeLogOverlapSource source;
  final String id;
  final String title;
  final int startTime;
  final int endTime;
  final List<TimeLogOverlapInterval> overlapIntervals;
  final int overlapMilliseconds;

  String get sourceLabel => switch (source) {
    TimeLogOverlapSource.manualLog => '时间日志',
    TimeLogOverlapSource.pomodoro => '番茄钟',
  };
}

/// Finds existing focus records that overlap a proposed manual time log.
/// Intervals use [start, end) semantics, so adjacent records do not conflict.
abstract final class TimeLogOverlapService {
  static List<TimeLogOverlap> find({
    required int startTime,
    required int endTime,
    required List<TimeLogItem> timeLogs,
    required List<PomodoroRecord> pomodoros,
    String? excludingTimeLogId,
    int? nowMilliseconds,
  }) {
    if (startTime <= 0 || endTime <= startTime) return const [];

    final overlaps = <TimeLogOverlap>[];
    for (final log in timeLogs) {
      if (log.isDeleted ||
          log.id == excludingTimeLogId ||
          log.startTime <= 0 ||
          log.endTime <= log.startTime) {
        continue;
      }
      final interval = _intersectionInterval(
        startTime,
        endTime,
        log.startTime,
        log.endTime,
      );
      if (interval == null) continue;
      overlaps.add(
        TimeLogOverlap(
          source: TimeLogOverlapSource.manualLog,
          id: log.id,
          title: log.title.trim().isEmpty ? '手动补录' : log.title.trim(),
          startTime: log.startTime,
          endTime: log.endTime,
          overlapIntervals: [interval],
          overlapMilliseconds: interval.durationMilliseconds,
        ),
      );
    }

    final now = nowMilliseconds ?? DateTime.now().millisecondsSinceEpoch;
    for (final record in pomodoros) {
      final recordEnd = record.endTime;
      if (record.isDeleted ||
          record.startTime <= 0 ||
          recordEnd == null ||
          recordEnd <= record.startTime ||
          recordEnd > now) {
        continue;
      }

      final overlapIntervals = <TimeLogOverlapInterval>[];
      for (final active in _activePomodoroIntervals(
        record.startTime,
        recordEnd,
        record.pauseIntervals,
      )) {
        final interval = _intersectionInterval(
          startTime,
          endTime,
          active.start,
          active.end,
        );
        if (interval == null) continue;
        if (overlapIntervals.isNotEmpty &&
            interval.startTime <= overlapIntervals.last.endTime) {
          final previous = overlapIntervals.removeLast();
          overlapIntervals.add(
            TimeLogOverlapInterval(
              startTime: previous.startTime,
              endTime: interval.endTime > previous.endTime
                  ? interval.endTime
                  : previous.endTime,
            ),
          );
        } else {
          overlapIntervals.add(interval);
        }
      }
      if (overlapIntervals.isEmpty) continue;
      final overlap = overlapIntervals.fold<int>(
        0,
        (total, interval) => total + interval.durationMilliseconds,
      );

      final title = record.todoTitle?.trim().isNotEmpty == true
          ? record.todoTitle!.trim()
          : record.note?.trim().isNotEmpty == true
          ? record.note!.trim()
          : '番茄专注';
      overlaps.add(
        TimeLogOverlap(
          source: TimeLogOverlapSource.pomodoro,
          id: record.uuid,
          title: title,
          startTime: record.startTime,
          endTime: recordEnd,
          overlapIntervals: overlapIntervals,
          overlapMilliseconds: overlap,
        ),
      );
    }

    overlaps.sort((left, right) {
      final byStart = left.startTime.compareTo(right.startTime);
      if (byStart != 0) return byStart;
      final bySource = left.source.index.compareTo(right.source.index);
      if (bySource != 0) return bySource;
      return left.id.compareTo(right.id);
    });
    return overlaps;
  }

  static TimeLogOverlapInterval? _intersectionInterval(
    int startA,
    int endA,
    int startB,
    int endB,
  ) {
    final start = startA > startB ? startA : startB;
    final end = endA < endB ? endA : endB;
    return end > start
        ? TimeLogOverlapInterval(startTime: start, endTime: end)
        : null;
  }

  static List<_FocusInterval> _activePomodoroIntervals(
    int sessionStart,
    int sessionEnd,
    List<PauseInterval>? pauses,
  ) {
    final fullSession = [_FocusInterval(sessionStart, sessionEnd)];
    if (pauses == null || pauses.isEmpty) return fullSession;

    final clippedPauses = <_FocusInterval>[];
    for (final pause in pauses) {
      final pauseEnd = pause.endMs ?? sessionEnd;
      final start = pause.startMs > sessionStart ? pause.startMs : sessionStart;
      final end = pauseEnd < sessionEnd ? pauseEnd : sessionEnd;
      if (end > start) clippedPauses.add(_FocusInterval(start, end));
    }
    if (clippedPauses.isEmpty) return fullSession;

    clippedPauses.sort((left, right) => left.start.compareTo(right.start));
    final mergedPauses = <_FocusInterval>[];
    for (final pause in clippedPauses) {
      if (mergedPauses.isEmpty || pause.start > mergedPauses.last.end) {
        mergedPauses.add(pause);
        continue;
      }
      final previous = mergedPauses.removeLast();
      mergedPauses.add(
        _FocusInterval(
          previous.start,
          pause.end > previous.end ? pause.end : previous.end,
        ),
      );
    }

    final active = <_FocusInterval>[];
    var cursor = sessionStart;
    for (final pause in mergedPauses) {
      if (pause.start > cursor) active.add(_FocusInterval(cursor, pause.start));
      if (pause.end > cursor) cursor = pause.end;
    }
    if (cursor < sessionEnd) active.add(_FocusInterval(cursor, sessionEnd));
    return active;
  }
}

class _FocusInterval {
  const _FocusInterval(this.start, this.end);

  final int start;
  final int end;
}
