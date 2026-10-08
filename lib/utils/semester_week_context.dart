import 'package:flutter/material.dart';

import '../course_import/course_schedule_semantics.dart';
import '../models.dart';
import '../storage_service.dart';

/// Week numbering for dates inside the user's active semester.
///
/// Week boundaries follow the course calendar: each week starts on Monday,
/// and the week containing the semester start date is week 1.
class SemesterWeekContext {
  const SemesterWeekContext(this.semester);

  final SemesterInfo semester;

  /// Loads the selected semester calendar even during breaks between terms.
  /// Call [weekForDate] to determine whether a specific date is in that term.
  static Future<SemesterWeekContext?> loadForToday() async {
    try {
      final semesters = await StorageService.getSemesters();
      final activeId = _canonicalSemesterId(
        await StorageService.getActiveSemesterId(),
      );

      SemesterInfo? selected;
      for (final semester in semesters) {
        if (semester.isCurrent &&
            _canonicalSemesterId(semester.id) == activeId) {
          selected = semester;
          break;
        }
      }
      selected ??= _firstCurrentSemester(semesters);
      if (selected == null) {
        for (final semester in semesters) {
          if (_canonicalSemesterId(semester.id) == activeId) {
            selected = semester;
            break;
          }
        }
      }
      if (selected == null) return null;

      return SemesterWeekContext(selected);
    } catch (_) {
      return null;
    }
  }

  int? weekForDate(DateTime date) {
    final normalizedDate = _dateOnly(date);
    final startDate = _dateOnly(semester.startDate);
    final endDate = semester.endDate == null
        ? startDate.add(const Duration(days: 120))
        : _dateOnly(semester.endDate!);

    if (normalizedDate.isBefore(startDate) || normalizedDate.isAfter(endDate)) {
      return null;
    }

    return CourseScheduleSemantics.weekIndexForDate(startDate, normalizedDate);
  }

  String appendWeekLabel(DateTime date, String formattedDate) {
    final week = weekForDate(date);
    return week == null ? formattedDate : '$formattedDate · 第$week周';
  }

  static SemesterInfo? _firstCurrentSemester(List<SemesterInfo> semesters) {
    for (final semester in semesters) {
      if (semester.isCurrent) return semester;
    }
    return null;
  }

  static String _canonicalSemesterId(String id) {
    final normalized = id.trim();
    return normalized.isEmpty ? 'default' : normalized;
  }

  static DateTime _dateOnly(DateTime date) =>
      DateTime(date.year, date.month, date.day);
}

/// Adds the selected date's semester week to the Material date picker header.
/// The wrapped delegate keeps the app's existing calendar and locale behavior.
class SemesterWeekCalendarDelegate extends CalendarDelegate<DateTime> {
  const SemesterWeekCalendarDelegate({
    required this.semesterWeekContext,
    required this.base,
    required this.landscapeHeader,
  });

  final SemesterWeekContext semesterWeekContext;
  final CalendarDelegate<DateTime> base;
  final bool landscapeHeader;

  @override
  DateTime now() => base.now();

  @override
  DateTime dateOnly(DateTime date) => base.dateOnly(date);

  @override
  DateTimeRange<DateTime> datesOnly(DateTimeRange<DateTime> range) =>
      base.datesOnly(range);

  @override
  bool isSameDay(DateTime? dateA, DateTime? dateB) =>
      base.isSameDay(dateA, dateB);

  @override
  bool isSameMonth(DateTime? dateA, DateTime? dateB) =>
      base.isSameMonth(dateA, dateB);

  @override
  int monthDelta(DateTime startDate, DateTime endDate) =>
      base.monthDelta(startDate, endDate);

  @override
  DateTime addMonthsToMonthDate(DateTime monthDate, int monthsToAdd) =>
      base.addMonthsToMonthDate(monthDate, monthsToAdd);

  @override
  DateTime addDaysToDate(DateTime date, int days) =>
      base.addDaysToDate(date, days);

  @override
  int firstDayOffset(
    int year,
    int month,
    MaterialLocalizations localizations,
  ) => base.firstDayOffset(year, month, localizations);

  @override
  int getDaysInMonth(int year, int month) => base.getDaysInMonth(year, month);

  @override
  DateTime getMonth(int year, int month) => base.getMonth(year, month);

  @override
  DateTime getDay(int year, int month, int day) =>
      base.getDay(year, month, day);

  @override
  String formatMonthYear(DateTime date, MaterialLocalizations localizations) =>
      base.formatMonthYear(date, localizations);

  @override
  String formatYear(int year, MaterialLocalizations localizations) =>
      base.formatYear(year, localizations);

  @override
  String formatMediumDate(DateTime date, MaterialLocalizations localizations) {
    final week = semesterWeekContext.weekForDate(date);
    if (week == null) return base.formatMediumDate(date, localizations);
    final formattedDate = '${date.month}/${date.day}';
    return landscapeHeader
        ? '$formattedDate\n第$week周'
        : '$formattedDate · 第$week周';
  }

  @override
  String formatShortMonthDay(
    DateTime date,
    MaterialLocalizations localizations,
  ) => base.formatShortMonthDay(date, localizations);

  @override
  String formatShortDate(DateTime date, MaterialLocalizations localizations) =>
      base.formatShortDate(date, localizations);

  @override
  String formatFullDate(DateTime date, MaterialLocalizations localizations) {
    final formattedDate = base.formatFullDate(date, localizations);
    final week = semesterWeekContext.weekForDate(date);
    return week == null ? formattedDate : '$formattedDate，第$week周';
  }

  @override
  String formatCompactDate(
    DateTime date,
    MaterialLocalizations localizations,
  ) => base.formatCompactDate(date, localizations);

  @override
  DateTime? parseCompactDate(
    String? inputString,
    MaterialLocalizations localizations,
  ) => base.parseCompactDate(inputString, localizations);

  @override
  String dateHelpText(MaterialLocalizations localizations) =>
      base.dateHelpText(localizations);
}
