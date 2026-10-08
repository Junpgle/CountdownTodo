import '../models.dart';

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
  });
  final DateTime start;
  final DateTime end;
  final PlanBusySource source;
  final String id;
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
  });
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
  const PlanAvailabilityResult(this.slots, {this.message});
  final List<PlanTimeSlot> slots;
  final String? message;
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
