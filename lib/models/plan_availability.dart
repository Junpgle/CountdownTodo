import '../models.dart';
import 'plan_weekly_availability.dart';

enum PlanBusySource {
  course,
  fixedSchedule,
  planBlock,
  legacyTodo,
  deviceCalendar,
}

class PlanBusyInterval {
  const PlanBusyInterval(
    this.start,
    this.end, {
    required this.source,
    this.id = '',
    this.title,
    this.record,
  });
  final DateTime start;
  final DateTime end;
  final PlanBusySource source;
  final String id;
  final String? title;
  final Object? record;
}

class PlanAvailabilityQuery {
  const PlanAvailabilityQuery({
    required this.username,
    required this.todoId,
    required this.date,
    required this.minutes,
    this.windowStart = 480,
    this.windowEnd = 1320,
    this.excludeBlockId,
    this.appOnly = false,
    this.resultLimit = 5,
    this.avoidWindows = const [],
    this.bufferBefore = 0,
    this.bufferAfter = 0,
    this.bufferOverride = false,
    this.bufferDefaultsKey,
    this.avoidanceOverride = false,
    this.avoidanceDefaultsKey,
    this.weekly,
  });
  final PlanWeeklyContext? weekly;
  final String username;
  final String todoId;
  final DateTime date;
  final int minutes;
  final int windowStart;
  final int windowEnd;
  final String? excludeBlockId;
  final bool appOnly;
  final int resultLimit;
  final List<PlanDailyTimeWindow> avoidWindows;
  final int bufferBefore, bufferAfter;

  /// Explicit one-query choice (including a failed preference write).
  final bool bufferOverride;
  final String? bufferDefaultsKey;
  final bool avoidanceOverride;
  final String? avoidanceDefaultsKey;
  PlanAvailabilityQuery withWeekly(PlanWeeklyContext? value) =>
      PlanAvailabilityQuery(
        username: username,
        todoId: todoId,
        date: date,
        minutes: minutes,
        windowStart: windowStart,
        windowEnd: windowEnd,
        excludeBlockId: excludeBlockId,
        appOnly: appOnly,
        resultLimit: resultLimit,
        avoidWindows: avoidWindows,
        bufferBefore: bufferBefore,
        bufferAfter: bufferAfter,
        bufferOverride: bufferOverride,
        bufferDefaultsKey: bufferDefaultsKey,
        avoidanceOverride: avoidanceOverride,
        avoidanceDefaultsKey: avoidanceDefaultsKey,
        weekly: value,
      );
  PlanAvailabilityQuery onDate(DateTime value, {int? limit, bool? onlyApp}) =>
      PlanAvailabilityQuery(
        username: username,
        todoId: todoId,
        date: value,
        minutes: minutes,
        windowStart: windowStart,
        windowEnd: windowEnd,
        excludeBlockId: excludeBlockId,
        appOnly: onlyApp ?? appOnly,
        resultLimit: limit ?? resultLimit,
        avoidWindows: avoidWindows,
        bufferBefore: bufferBefore,
        bufferAfter: bufferAfter,
        bufferOverride: bufferOverride,
        bufferDefaultsKey: bufferDefaultsKey,
        avoidanceOverride: avoidanceOverride,
        avoidanceDefaultsKey: avoidanceDefaultsKey,
        weekly: weekly,
      );
  bool get hasBuffers => bufferBefore != 0 || bufferAfter != 0;
  String get bufferSummary => bufferOverride && !hasBuffers
      ? '本次未留缓冲'
      : '已按开始前$bufferBefore分钟、结束后$bufferAfter分钟查找';
  DateTime get sourceStart =>
      dayStart.subtract(Duration(minutes: bufferBefore));
  DateTime get sourceEnd => dayEnd.add(Duration(minutes: bufferAfter));
  PlanTimeSlot buffered(PlanBusyInterval busy) => PlanTimeSlot(
    busy.start.subtract(Duration(minutes: bufferAfter)),
    busy.end.add(Duration(minutes: bufferBefore)),
  );
  DateTime get dayStart => DateTime(date.year, date.month, date.day);
  DateTime get dayEnd => DateTime(date.year, date.month, date.day + 1);
}

/// Optional daily preferences, separate from persisted scheduling records.
class PlanDailyTimeWindow {
  const PlanDailyTimeWindow(this.label, this.startMinutes, this.endMinutes);
  final String label;
  final int startMinutes;
  final int endMinutes;

  PlanTimeSlot onDate(DateTime date) => PlanTimeSlot(
    DateTime(
      date.year,
      date.month,
      date.day,
      startMinutes ~/ 60,
      startMinutes % 60,
    ),
    DateTime(
      date.year,
      date.month,
      date.day,
      endMinutes ~/ 60,
      endMinutes % 60,
    ),
  );
}

class PlanTimeSlot {
  const PlanTimeSlot(this.start, this.end);
  final DateTime start;
  final DateTime end;
  int get minutes => end.difference(start).inMinutes;
}

class PlanAvailabilitySnapshot {
  const PlanAvailabilitySnapshot({
    required this.todo,
    required this.busy,
    required this.coverage,
    this.unknownTimes = const [],
    this.deviceCalendarIncluded = false,
    this.courseFingerprint = '',
    this.settingsFingerprint = '',
    this.calendarRevision = 0,
  });
  final TodoItem todo;
  final List<PlanBusyInterval> busy;
  final String coverage;
  final List<String> unknownTimes;
  final bool deviceCalendarIncluded;
  final String courseFingerprint;
  final String settingsFingerprint;
  final int calendarRevision;
}

class PlanAvailabilityResult {
  const PlanAvailabilityResult(this.slots, {this.message, this.diagnostics});
  final List<PlanTimeSlot> slots;
  final String? message;
  final PlanAvailabilityDiagnostics? diagnostics;
}

class PlanAvailabilitySelection {
  const PlanAvailabilitySelection(this.query, this.slot, this.snapshot);
  final PlanAvailabilityQuery query;
  final PlanTimeSlot slot;
  final PlanAvailabilitySnapshot snapshot;
}

class PlanAvailabilityException implements Exception {
  const PlanAvailabilityException(this.message, {this.canUseAppOnly = false});
  final String message;
  final bool canUseAppOnly;
  @override
  String toString() => message;
}

/// Shared read-only occupancy for a local date, independent of any target todo.
class PlanAvailabilityDaySources {
  const PlanAvailabilityDaySources({
    required this.date,
    required this.busy,
    required this.unknownTimes,
  });
  final DateTime date;
  final List<PlanBusyInterval> busy;
  final List<String> unknownTimes;
}

/// One account-scoped read of all sources, including one device-calendar range.
class PlanAvailabilityRangeSnapshot {
  const PlanAvailabilityRangeSnapshot({
    required this.username,
    required this.start,
    required this.end,
    required this.blocks,
    required this.todos,
    required this.days,
    required this.coverage,
    required this.deviceCalendarIncluded,
  });
  final String username;
  final DateTime start, end;
  final List<TodoPlanBlock> blocks;
  final List<TodoItem> todos;
  final List<PlanAvailabilityDaySources> days;
  final String coverage;
  final bool deviceCalendarIncluded;
}

/// Reasons describe a successful calculation, never a failed source read.
enum PlanAvailabilityReason {
  available,
  invalid,
  rangeEnded,
  deadline,
  weeklyNone,
  weeklyOutside,
  noTime,
  fragmented,
}

class PlanAvailabilityStage {
  const PlanAvailabilityStage(this.label, this.minutes);
  final String label;
  final int minutes;
}

class PlanAvailabilityDiagnostics {
  PlanAvailabilityDiagnostics(
    this.reason,
    this.message, {
    Iterable<PlanTimeSlot> fragments = const [],
    Iterable<PlanAvailabilityStage> stages = const [],
  }) : fragments = List.unmodifiable(fragments),
       stages = List.unmodifiable(stages);
  final PlanAvailabilityReason reason;
  final String? message;
  final List<PlanTimeSlot> fragments;
  final List<PlanAvailabilityStage> stages;
  bool get valid => reason != PlanAvailabilityReason.invalid;
  int get totalMinutes => fragments.fold(0, (n, s) => n + s.minutes);
  int get longestMinutes =>
      fragments.fold(0, (n, s) => s.minutes > n ? s.minutes : n);
  String get summary => '当前条件下最长$longestMinutes分钟，共$totalMinutes分钟碎片';
}

class PlanContinuousRangeResult {
  PlanContinuousRangeResult(
    this.start,
    this.end,
    this.coverage,
    Iterable<PlanAvailabilitySelection> selections,
    Iterable<String> unknownTimes, {
    this.currentSnapshot,
  }) : selections = List.unmodifiable(selections),
       unknownTimes = List.unmodifiable(unknownTimes.toSet());

  /// Inclusive start and exclusive end, both local calendar midnights.
  final DateTime start, end;
  final String coverage;
  final List<PlanAvailabilitySelection> selections;
  final List<String> unknownTimes;
  final PlanAvailabilitySnapshot? currentSnapshot;
}
