import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models.dart';
import '../storage_service.dart';

class CourseDayTransfer {
  final String fromDate;
  final String toDate;
  final String label;

  const CourseDayTransfer({
    required this.fromDate,
    required this.toDate,
    this.label = '',
  });

  Map<String, dynamic> toJson() => {
        'from_date': fromDate,
        'to_date': toDate,
        'label': label,
      };

  factory CourseDayTransfer.fromJson(Map<String, dynamic> json) =>
      CourseDayTransfer(
        fromDate: json['from_date']?.toString() ?? '',
        toDate: json['to_date']?.toString() ?? '',
        label: json['label']?.toString() ?? '',
      );
}

class CourseCalendarAdjustment {
  final Set<String> holidayDates;
  final Map<String, String> holidayLabels;
  final List<CourseDayTransfer> transfers;
  final bool officialHolidayPromptEnabled;
  final Set<String> handledOfficialHolidayKeys;

  const CourseCalendarAdjustment({
    required this.holidayDates,
    this.holidayLabels = const {},
    required this.transfers,
    this.officialHolidayPromptEnabled = true,
    this.handledOfficialHolidayKeys = const {},
  });

  factory CourseCalendarAdjustment.empty() => const CourseCalendarAdjustment(
        holidayDates: <String>{},
        holidayLabels: <String, String>{},
        transfers: [],
        handledOfficialHolidayKeys: <String>{},
      );

  Map<String, dynamic> toJson() => {
        'holiday_dates': holidayDates.toList()..sort(),
        'holiday_labels': holidayLabels,
        'transfers': transfers.map((t) => t.toJson()).toList(),
        'official_holiday_prompt_enabled': officialHolidayPromptEnabled,
        'handled_official_holiday_keys': handledOfficialHolidayKeys.toList()
          ..sort(),
      };

  factory CourseCalendarAdjustment.fromJson(Map<String, dynamic> json) {
    final holidays = (json['holiday_dates'] as List? ?? const [])
        .map((e) => e.toString())
        .where((e) => e.isNotEmpty)
        .toSet();
    final labels = (json['holiday_labels'] as Map? ?? const {})
        .map((key, value) => MapEntry(key.toString(), value.toString()));
    final transfers = (json['transfers'] as List? ?? const [])
        .whereType<Map>()
        .map((e) => CourseDayTransfer.fromJson(Map<String, dynamic>.from(e)))
        .where((e) => e.fromDate.isNotEmpty && e.toDate.isNotEmpty)
        .toList();
    final handledOfficialHolidayKeys =
        (json['handled_official_holiday_keys'] as List? ?? const [])
            .map((e) => e.toString())
            .where((e) => e.isNotEmpty)
            .toSet();
    return CourseCalendarAdjustment(
      holidayDates: holidays,
      holidayLabels: labels,
      transfers: transfers,
      officialHolidayPromptEnabled:
          json['official_holiday_prompt_enabled'] != false,
      handledOfficialHolidayKeys: handledOfficialHolidayKeys,
    );
  }

  CourseCalendarAdjustment copyWith({
    Set<String>? holidayDates,
    Map<String, String>? holidayLabels,
    List<CourseDayTransfer>? transfers,
    bool? officialHolidayPromptEnabled,
    Set<String>? handledOfficialHolidayKeys,
  }) =>
      CourseCalendarAdjustment(
        holidayDates: holidayDates ?? this.holidayDates,
        holidayLabels: holidayLabels ?? this.holidayLabels,
        transfers: transfers ?? this.transfers,
        officialHolidayPromptEnabled:
            officialHolidayPromptEnabled ?? this.officialHolidayPromptEnabled,
        handledOfficialHolidayKeys:
            handledOfficialHolidayKeys ?? this.handledOfficialHolidayKeys,
      );
}

class OfficialHolidayWindow {
  final int year;
  final String key;
  final String name;
  final List<String> holidayDates;
  final List<CourseDayTransfer> transfers;

  const OfficialHolidayWindow({
    required this.year,
    required this.key,
    required this.name,
    required this.holidayDates,
    required this.transfers,
  });
}

class CourseCalendarAdjustmentService {
  static const String _prefsKey = 'course_calendar_adjustments_v1';
  static final DateFormat _df = DateFormat('yyyy-MM-dd');
  static const String official2026SourceName = '国务院办公厅关于2026年部分节假日安排的通知';
  static const String official2026SourceUrl =
      'https://www.gov.cn/gongbao/2025/issue_12406/202511/content_7048922.html';

  static const List<OfficialHolidayWindow> official2026Windows = [
    OfficialHolidayWindow(
      year: 2026,
      key: '2026_new_year',
      name: '元旦',
      holidayDates: ['2026-01-01', '2026-01-02', '2026-01-03'],
      transfers: [
        CourseDayTransfer(
          fromDate: '2026-01-02',
          toDate: '2026-01-04',
          label: '元旦',
        ),
      ],
    ),
    OfficialHolidayWindow(
      year: 2026,
      key: '2026_spring_festival',
      name: '春节',
      holidayDates: [
        '2026-02-15',
        '2026-02-16',
        '2026-02-17',
        '2026-02-18',
        '2026-02-19',
        '2026-02-20',
        '2026-02-21',
        '2026-02-22',
        '2026-02-23',
      ],
      transfers: [
        CourseDayTransfer(
          fromDate: '2026-02-16',
          toDate: '2026-02-14',
          label: '春节',
        ),
        CourseDayTransfer(
          fromDate: '2026-02-23',
          toDate: '2026-02-28',
          label: '春节',
        ),
      ],
    ),
    OfficialHolidayWindow(
      year: 2026,
      key: '2026_qingming',
      name: '清明节',
      holidayDates: ['2026-04-04', '2026-04-05', '2026-04-06'],
      transfers: [],
    ),
    OfficialHolidayWindow(
      year: 2026,
      key: '2026_labor_day',
      name: '劳动节',
      holidayDates: [
        '2026-05-01',
        '2026-05-02',
        '2026-05-03',
        '2026-05-04',
        '2026-05-05',
      ],
      transfers: [
        CourseDayTransfer(
          fromDate: '2026-05-04',
          toDate: '2026-05-09',
          label: '劳动节',
        ),
      ],
    ),
    OfficialHolidayWindow(
      year: 2026,
      key: '2026_dragon_boat',
      name: '端午节',
      holidayDates: ['2026-06-19', '2026-06-20', '2026-06-21'],
      transfers: [],
    ),
    OfficialHolidayWindow(
      year: 2026,
      key: '2026_mid_autumn',
      name: '中秋节',
      holidayDates: ['2026-09-25', '2026-09-26', '2026-09-27'],
      transfers: [],
    ),
    OfficialHolidayWindow(
      year: 2026,
      key: '2026_national_day',
      name: '国庆节',
      holidayDates: [
        '2026-10-01',
        '2026-10-02',
        '2026-10-03',
        '2026-10-04',
        '2026-10-05',
        '2026-10-06',
        '2026-10-07',
      ],
      transfers: [
        CourseDayTransfer(
          fromDate: '2026-10-05',
          toDate: '2026-09-20',
          label: '国庆节',
        ),
        CourseDayTransfer(
          fromDate: '2026-10-06',
          toDate: '2026-10-10',
          label: '国庆节',
        ),
      ],
    ),
  ];

  static List<OfficialHolidayWindow> get officialWindows => official2026Windows;

  static Future<CourseCalendarAdjustment> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null || raw.isEmpty) return CourseCalendarAdjustment.empty();

    try {
      return CourseCalendarAdjustment.fromJson(
        Map<String, dynamic>.from(jsonDecode(raw) as Map),
      );
    } catch (e) {
      debugPrint('[CourseCalendar] 读取课表调休设置失败: $e');
      return CourseCalendarAdjustment.empty();
    }
  }

  static Future<void> save(CourseCalendarAdjustment adjustment) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, jsonEncode(adjustment.toJson()));
    StorageService.triggerRefresh();
  }

  static Future<void> markOfficialHolidayHandled(String key) async {
    if (key.isEmpty) return;
    final adjustment = await load();
    if (adjustment.handledOfficialHolidayKeys.contains(key)) return;
    await save(adjustment.copyWith(
      handledOfficialHolidayKeys: {
        ...adjustment.handledOfficialHolidayKeys,
        key,
      },
    ));
  }

  static Future<OfficialHolidayWindow?> pendingOfficialHolidayWindow() async {
    final adjustment = await load();
    if (!adjustment.officialHolidayPromptEnabled) return null;

    final now = DateTime.now();
    for (final window in officialWindows) {
      if (adjustment.handledOfficialHolidayKeys.contains(window.key) ||
          _isWindowConfigured(adjustment, window)) {
        continue;
      }
      final dates = window.holidayDates
          .map((date) => _df.parseStrict(date))
          .toList()
        ..sort();
      final first = dates.first.subtract(const Duration(days: 30));
      final last = dates.last.add(const Duration(days: 7));
      if (!now.isBefore(first) && !now.isAfter(last)) return window;
    }
    return null;
  }

  static bool _isWindowConfigured(
    CourseCalendarAdjustment adjustment,
    OfficialHolidayWindow window,
  ) {
    final windowHolidays = window.holidayDates.toSet();
    if (adjustment.holidayDates.any(windowHolidays.contains)) return true;

    final windowTransferKeys =
        window.transfers.map((t) => '${t.fromDate}>${t.toDate}').toSet();
    if (windowTransferKeys.isEmpty) return false;
    return adjustment.transfers
        .map((t) => '${t.fromDate}>${t.toDate}')
        .any(windowTransferKeys.contains);
  }

  static Future<List<CourseItem>> applyToCourses(
    List<CourseItem> rawCourses,
  ) async {
    final adjustment = await load();
    if (adjustment.holidayDates.isEmpty && adjustment.transfers.isEmpty) {
      return rawCourses;
    }

    final semesterMonday = await _resolveSemesterMonday(rawCourses);
    final byDate = <String, List<CourseItem>>{};
    for (final course in rawCourses) {
      final date = course.date.trim();
      if (date.isEmpty) continue;
      byDate.putIfAbsent(date, () => []).add(course);
    }

    final adjusted = rawCourses
        .where((course) => !adjustment.holidayDates.contains(course.date))
        .map((course) => course)
        .toList();

    for (final transfer in adjustment.transfers) {
      final sourceCourses = byDate[transfer.fromDate] ?? const <CourseItem>[];
      if (sourceCourses.isEmpty) continue;
      final targetDate = _df.parseStrict(transfer.toDate);
      final targetWeekday = targetDate.weekday;
      final targetWeekIndex = semesterMonday == null
          ? sourceCourses.first.weekIndex
          : targetDate.difference(semesterMonday).inDays ~/ 7 + 1;

      for (final course in sourceCourses) {
        adjusted.add(_copyCourseForDate(
          course,
          date: transfer.toDate,
          weekday: targetWeekday,
          weekIndex: targetWeekIndex,
        ));
      }
    }

    adjusted.sort((a, b) {
      final dateCompare = a.date.compareTo(b.date);
      if (dateCompare != 0) return dateCompare;
      return a.startTime.compareTo(b.startTime);
    });
    return _dedupe(adjusted);
  }

  static Future<DateTime?> _resolveSemesterMonday(
      List<CourseItem> courses) async {
    final semStart = await StorageService.getSemesterStart();
    if (semStart != null) {
      final normalized = DateTime(semStart.year, semStart.month, semStart.day);
      return normalized.subtract(Duration(days: normalized.weekday - 1));
    }

    final dated = courses.where((c) => c.date.isNotEmpty).toList()
      ..sort((a, b) => a.weekIndex.compareTo(b.weekIndex));
    if (dated.isEmpty) return null;
    try {
      final first = dated.first;
      final firstDate = _df.parseStrict(first.date);
      return DateTime(firstDate.year, firstDate.month, firstDate.day)
          .subtract(Duration(days: first.weekday - 1))
          .subtract(Duration(days: (first.weekIndex - 1) * 7));
    } catch (_) {
      return null;
    }
  }

  static CourseItem _copyCourseForDate(
    CourseItem course, {
    required String date,
    required int weekday,
    required int weekIndex,
  }) {
    return CourseItem(
      uuid: '${course.uuid}@$date',
      courseName: course.courseName,
      teacherName: course.teacherName,
      date: date,
      weekday: weekday,
      startTime: course.startTime,
      endTime: course.endTime,
      weekIndex: weekIndex,
      roomName: course.roomName,
      lessonType: course.lessonType,
      teamUuid: course.teamUuid,
      version: course.version,
      updatedAt: course.updatedAt,
      createdAt: course.createdAt,
      isDeleted: course.isDeleted,
    );
  }

  static List<CourseItem> _dedupe(List<CourseItem> courses) {
    final seen = <String>{};
    final result = <CourseItem>[];
    for (final course in courses) {
      final key =
          '${course.date}|${course.courseName}|${course.roomName}|${course.startTime}|${course.endTime}';
      if (seen.add(key)) result.add(course);
    }
    return result;
  }
}
