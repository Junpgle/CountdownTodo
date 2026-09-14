import 'package:intl/intl.dart';

import '../models.dart';

/// Aggregated schedule information for all occurrences of one course series.
class CourseSeriesSummary {
  const CourseSeriesSummary({
    required this.startWeek,
    required this.endWeek,
    required this.totalLessons,
    required this.completedLessons,
  });

  final int startWeek;
  final int endWeek;
  final int totalLessons;
  final int completedLessons;
}

/// Shared schedule rules used by every course-import and merge entry point.
///
/// A [CourseItem] stores both its relative position (week/day) and a concrete
/// date for fast display.  The semester start is the source of truth when an
/// imported course is assigned to a semester, so the concrete date is always
/// rebuilt from the relative position here.
abstract final class CourseScheduleSemantics {
  static final DateFormat _dateFormat = DateFormat('yyyy-MM-dd');

  static DateTime mondayOf(DateTime startDate) {
    final normalized = DateTime(startDate.year, startDate.month, startDate.day);
    return normalized.subtract(Duration(days: normalized.weekday - 1));
  }

  static String dateFor({
    required DateTime semesterStart,
    required int weekIndex,
    required int weekday,
  }) {
    final safeWeek = weekIndex < 1 ? 1 : weekIndex;
    final safeWeekday = weekday.clamp(DateTime.monday, DateTime.sunday).toInt();
    final date = mondayOf(semesterStart).add(Duration(
      days: (safeWeek - 1) * 7 + (safeWeekday - 1),
    ));
    return _dateFormat.format(date);
  }

  /// Course times are stored as HHMM integers.  Zero, malformed minutes, and
  /// reversed ranges mean that the parser did not produce a usable slot.
  static bool hasUsableTime(CourseItem course) {
    return _isClockTime(course.startTime) &&
        _isClockTime(course.endTime) &&
        course.startTime > 0 &&
        course.endTime > course.startTime;
  }

  /// Summarizes every scheduled occurrence belonging to [course].
  ///
  /// A course item represents one occurrence of a class.  Semester and subject
  /// identify the series; teacher, lesson type, room, weekday, and time are
  /// occurrence attributes and may change between weeks.
  static CourseSeriesSummary summarizeCourseSeries(
    CourseItem course,
    Iterable<CourseItem> courses, {
    DateTime? asOf,
  }) {
    final related = <String, CourseItem>{};
    for (final candidate in courses) {
      if (!_belongsToCourseSeries(course, candidate)) continue;
      related[candidate.uuid] = candidate;
    }
    // Keep the detail subject visible even when the caller has not loaded the
    // full schedule yet or the source list does not contain this occurrence.
    related[course.uuid] = course;

    final occurrences = related.values.toList();
    final weeks = occurrences
        .map((item) => item.weekIndex)
        .where((week) => week > 0)
        .toList();
    final fallbackWeek = course.weekIndex > 0 ? course.weekIndex : 1;
    final startWeek = weeks.isEmpty ? fallbackWeek : weeks.reduce(_min);
    final endWeek = weeks.isEmpty ? fallbackWeek : weeks.reduce(_max);
    final referenceTime = asOf ?? DateTime.now();
    final completedLessons = occurrences.where((item) {
      final start = _scheduledStart(item);
      return start != null && !start.isAfter(referenceTime);
    }).length;

    return CourseSeriesSummary(
      startWeek: startWeek,
      endWeek: endWeek,
      totalLessons: occurrences.length,
      completedLessons: completedLessons,
    );
  }

  /// Returns a copy with a repaired time range and a UUID derived from the
  /// repaired identity rather than the parser's placeholder time.
  static CourseItem withTimeRange(
    CourseItem course, {
    required int startTime,
    required int endTime,
  }) {
    return CourseItem(
      courseName: course.courseName,
      teacherName: course.teacherName,
      date: course.date,
      weekday: course.weekday,
      startTime: startTime,
      endTime: endTime,
      weekIndex: course.weekIndex,
      roomName: course.roomName,
      lessonType: course.lessonType,
      semesterId: course.semesterId,
      teamUuid: course.teamUuid,
      version: course.version,
      updatedAt: course.updatedAt,
      createdAt: course.createdAt,
      isDeleted: course.isDeleted,
    );
  }

  /// Assigns parsed courses to a semester and rebuilds their concrete dates.
  ///
  /// The UUID is intentionally regenerated because the semester is part of a
  /// course's deterministic identity.  Import metadata is retained so this
  /// method can also be used by non-UI import adapters.
  static List<CourseItem> assignToSemester(
    Iterable<CourseItem> courses, {
    required String semesterId,
    required DateTime semesterStart,
  }) {
    final canonicalSemester = canonicalSemesterId(semesterId);
    return courses.map((course) {
      final weekday =
          course.weekday.clamp(DateTime.monday, DateTime.sunday).toInt();
      final weekIndex = course.weekIndex < 1 ? 1 : course.weekIndex;
      return CourseItem(
        courseName: course.courseName,
        teacherName: course.teacherName,
        date: dateFor(
          semesterStart: semesterStart,
          weekIndex: weekIndex,
          weekday: weekday,
        ),
        weekday: weekday,
        startTime: course.startTime,
        endTime: course.endTime,
        weekIndex: weekIndex,
        roomName: course.roomName,
        lessonType: course.lessonType,
        semesterId: canonicalSemester,
        teamUuid: course.teamUuid,
        version: course.version,
        updatedAt: course.updatedAt,
        createdAt: course.createdAt,
        isDeleted: course.isDeleted,
      );
    }).toList();
  }

  /// Assigns a semester while retaining a source date when no semester start
  /// is available (for legacy exports that already contain concrete dates).
  static List<CourseItem> assignIdOnly(
    Iterable<CourseItem> courses, {
    required String semesterId,
  }) {
    final canonicalSemester = canonicalSemesterId(semesterId);
    return courses
        .map((course) => CourseItem(
              courseName: course.courseName,
              teacherName: course.teacherName,
              date: course.date,
              weekday: course.weekday,
              startTime: course.startTime,
              endTime: course.endTime,
              weekIndex: course.weekIndex,
              roomName: course.roomName,
              lessonType: course.lessonType,
              semesterId: canonicalSemester,
              teamUuid: course.teamUuid,
              version: course.version,
              updatedAt: course.updatedAt,
              createdAt: course.createdAt,
              isDeleted: course.isDeleted,
            ))
        .toList();
  }

  /// Returns whether two courses occupy an overlapping slot in the same
  /// semester.  Relative week/day is used as a fallback for legacy rows that
  /// do not have a concrete date.
  static bool overlaps(CourseItem left, CourseItem right) {
    if (canonicalSemesterId(left.semesterId) !=
        canonicalSemesterId(right.semesterId)) {
      return false;
    }

    final leftDate = left.date.trim();
    final rightDate = right.date.trim();
    final sameDay = leftDate.isNotEmpty && rightDate.isNotEmpty
        ? leftDate == rightDate
        : left.weekIndex == right.weekIndex && left.weekday == right.weekday;
    if (!sameDay) return false;

    return left.startTime < right.endTime && left.endTime > right.startTime;
  }

  /// Merges incoming courses by replacing all existing courses that occupy
  /// the same slot in the same semester.  UUID-only merging is insufficient
  /// because a changed room or course name creates a new deterministic UUID.
  static List<CourseItem> mergeBySlot(
    Iterable<CourseItem> existing,
    Iterable<CourseItem> incoming,
  ) {
    final merged = <String, CourseItem>{};
    for (final course in existing) {
      merged[course.uuid] = course;
    }

    for (final course in incoming) {
      final conflictingUuids = merged.values
          .where((oldCourse) => overlaps(oldCourse, course))
          .map((oldCourse) => oldCourse.uuid)
          .toList();
      for (final uuid in conflictingUuids) {
        merged.remove(uuid);
      }
      merged[course.uuid] = course;
    }

    return merged.values.toList();
  }

  /// Replaces only one semester and preserves every other semester.
  static List<CourseItem> replaceSemester(
    Iterable<CourseItem> existing,
    Iterable<CourseItem> incoming, {
    required String semesterId,
  }) {
    final targetSemesterId = canonicalSemesterId(semesterId);
    final merged = <String, CourseItem>{};
    for (final course in existing) {
      if (canonicalSemesterId(course.semesterId) != targetSemesterId) {
        merged[course.uuid] = course;
      }
    }
    for (final course in incoming) {
      final normalizedCourse =
          canonicalSemesterId(course.semesterId) == course.semesterId
              ? course
              : assignIdOnly([course], semesterId: targetSemesterId).single;
      merged[normalizedCourse.uuid] = normalizedCourse;
    }
    return merged.values.toList();
  }

  static String canonicalSemesterId(String? semesterId) {
    final normalized = semesterId?.trim() ?? '';
    return normalized.isEmpty ? 'default' : normalized;
  }

  static bool _belongsToCourseSeries(CourseItem course, CourseItem candidate) {
    return canonicalSemesterId(course.semesterId) ==
            canonicalSemesterId(candidate.semesterId) &&
        course.courseName.trim() == candidate.courseName.trim();
  }

  static DateTime? _scheduledStart(CourseItem course) {
    final date = DateTime.tryParse(course.date.trim());
    if (date == null) return null;

    if (!hasUsableTime(course) || !_isClockTime(course.startTime)) return null;
    final hour = course.startTime ~/ 100;
    final minute = course.startTime % 100;
    return DateTime(date.year, date.month, date.day, hour, minute);
  }

  static int _min(int left, int right) => left < right ? left : right;

  static int _max(int left, int right) => left > right ? left : right;

  static bool _isClockTime(int value) {
    if (value < 0) return false;
    final hour = value ~/ 100;
    final minute = value % 100;
    return hour <= 23 && minute < 60;
  }
}
