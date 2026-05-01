import 'dart:io';

import 'package:flutter/services.dart';

import '../models.dart';
import '../storage_service.dart';
import 'course_service.dart';

enum CalendarSyncEntryType { todo, course, countdown }

class CalendarSyncEntry {
  CalendarSyncEntry({
    required this.id,
    required this.type,
    required this.title,
    required this.start,
    required this.end,
    required this.allDay,
    this.location,
    this.description,
  });

  final String id;
  final CalendarSyncEntryType type;
  final String title;
  final DateTime start;
  final DateTime end;
  final bool allDay;
  final String? location;
  final String? description;

  String get typeLabel {
    switch (type) {
      case CalendarSyncEntryType.todo:
        return '待办';
      case CalendarSyncEntryType.course:
        return '课程';
      case CalendarSyncEntryType.countdown:
        return '倒数日';
    }
  }

  Map<String, dynamic> toPlatformJson() => {
        'sourceType': type.name,
        'title': title,
        'startMs': _platformMillis(start),
        'endMs': _platformMillis(end),
        'allDay': allDay,
        'location': location,
        'description': description,
      };

  int _platformMillis(DateTime value) {
    if (!allDay) return value.toUtc().millisecondsSinceEpoch;
    return DateTime.utc(value.year, value.month, value.day)
        .millisecondsSinceEpoch;
  }
}

class CalendarSyncResult {
  CalendarSyncResult({
    required this.inserted,
    required this.cleared,
    required this.failed,
  });

  final int inserted;
  final int cleared;
  final int failed;

  factory CalendarSyncResult.fromMap(Map<dynamic, dynamic>? map) {
    return CalendarSyncResult(
      inserted: (map?['inserted'] as num?)?.toInt() ?? 0,
      cleared: (map?['cleared'] as num?)?.toInt() ?? 0,
      failed: (map?['failed'] as num?)?.toInt() ?? 0,
    );
  }
}

class CalendarSyncService {
  static const MethodChannel _channel =
      MethodChannel('com.math_quiz.junpgle.com.math_quiz_app/notifications');

  static bool get isSupported => Platform.isAndroid;

  static Future<bool> checkPermission() async {
    if (!isSupported) return false;
    return await _channel.invokeMethod<bool>('checkCalendarPermission') ??
        false;
  }

  static Future<bool> requestPermission() async {
    if (!isSupported) return false;
    return await _channel.invokeMethod<bool>('requestCalendarPermission') ??
        false;
  }

  static Future<List<Map<String, dynamic>>> getWritableCalendars() async {
    if (!isSupported) return const [];
    final raw = await _channel.invokeMethod<List<dynamic>>(
          'getWritableCalendars',
        ) ??
        const [];
    return raw
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  static Future<CalendarSyncResult> writeEntries({
    required List<CalendarSyncEntry> entries,
    int? calendarId,
    bool clearFirst = true,
  }) async {
    if (!isSupported) {
      return CalendarSyncResult(
          inserted: 0, cleared: 0, failed: entries.length);
    }
    final result = await _channel.invokeMethod<Map<dynamic, dynamic>>(
      'syncCalendarEvents',
      {
        'calendarId': calendarId,
        'clearFirst': clearFirst,
        'events': entries.map((entry) => entry.toPlatformJson()).toList(),
      },
    );
    return CalendarSyncResult.fromMap(result);
  }

  static Future<int> clearAppEvents({int? calendarId}) async {
    if (!isSupported) return 0;
    final cleared = await _channel.invokeMethod<int>(
      'clearCalendarEvents',
      {'calendarId': calendarId},
    );
    return cleared ?? 0;
  }

  static Future<List<CalendarSyncEntry>> loadEntries(String username) async {
    final results = await Future.wait([
      StorageService.getTodos(username),
      CourseService.getAllCourses(username),
      StorageService.getCountdowns(username),
    ]);

    final todos = results[0] as List<TodoItem>;
    final courses = results[1] as List<CourseItem>;
    final countdowns = results[2] as List<CountdownItem>;
    final entries = <CalendarSyncEntry>[];

    for (final todo in todos) {
      if (todo.isDeleted || todo.isDone) continue;
      final entry = _todoToEntry(todo);
      if (entry != null) entries.add(entry);
    }

    for (final course in courses) {
      if (course.isDeleted) continue;
      final entry = _courseToEntry(course);
      if (entry != null) entries.add(entry);
    }

    for (final countdown in countdowns) {
      if (countdown.isDeleted || countdown.isCompleted) continue;
      entries.add(_countdownToEntry(countdown));
    }

    entries.sort((a, b) => a.start.compareTo(b.start));
    return entries;
  }

  static CalendarSyncEntry? _todoToEntry(TodoItem todo) {
    final start = todo.createdDate != null && todo.createdDate! > 0
        ? DateTime.fromMillisecondsSinceEpoch(todo.createdDate!).toLocal()
        : todo.dueDate?.toLocal();
    if (start == null) return null;

    DateTime end =
        todo.dueDate?.toLocal() ?? start.add(const Duration(minutes: 30));
    if (!end.isAfter(start)) {
      end = start.add(todo.isAllDayTask
          ? const Duration(days: 1)
          : const Duration(minutes: 30));
    }

    final details = <String>[
      if (todo.teamName?.trim().isNotEmpty == true)
        '团队：${todo.teamName!.trim()}',
      if (todo.creatorName?.trim().isNotEmpty == true)
        '创建人：${todo.creatorName!.trim()}',
      if (todo.remark?.trim().isNotEmpty == true) todo.remark!.trim(),
    ];
    final shouldWriteAsAllDay = _shouldWriteAsAllDayTodo(todo, start, end);

    return CalendarSyncEntry(
      id: todo.id,
      type: CalendarSyncEntryType.todo,
      title: todo.title,
      start: shouldWriteAsAllDay ? _dateOnly(start) : start,
      end: shouldWriteAsAllDay
          ? _dateOnly(start).add(const Duration(days: 1))
          : end,
      allDay: shouldWriteAsAllDay,
      description: details.isEmpty ? null : details.join('\n'),
    );
  }

  static CalendarSyncEntry? _courseToEntry(CourseItem course) {
    final parts = course.date.split('-');
    if (parts.length != 3) return null;
    final year = int.tryParse(parts[0]);
    final month = int.tryParse(parts[1]);
    final day = int.tryParse(parts[2]);
    if (year == null || month == null || day == null) return null;

    final start = DateTime(
      year,
      month,
      day,
      course.startTime ~/ 100,
      course.startTime % 100,
    );
    var end = DateTime(
      year,
      month,
      day,
      course.endTime ~/ 100,
      course.endTime % 100,
    );
    if (!end.isAfter(start)) end = start.add(const Duration(minutes: 45));

    final desc = [
      if (course.teacherName.isNotEmpty && course.teacherName != '未知教师')
        '教师：${course.teacherName}',
      if (course.lessonType?.isNotEmpty == true) '类型：${course.lessonType}',
    ].join('\n');

    return CalendarSyncEntry(
      id: course.uuid,
      type: CalendarSyncEntryType.course,
      title: course.courseName,
      start: start,
      end: end,
      allDay: false,
      location: course.roomName == '未知地点' ? null : course.roomName,
      description: desc.isEmpty ? null : desc,
    );
  }

  static CalendarSyncEntry _countdownToEntry(CountdownItem countdown) {
    final start = _dateOnly(countdown.targetDate.toLocal());
    return CalendarSyncEntry(
      id: countdown.id,
      type: CalendarSyncEntryType.countdown,
      title: countdown.title,
      start: start,
      end: start.add(const Duration(days: 1)),
      allDay: true,
    );
  }

  static DateTime _dateOnly(DateTime date) =>
      DateTime(date.year, date.month, date.day);

  static bool _shouldWriteAsAllDayTodo(
    TodoItem todo,
    DateTime start,
    DateTime end,
  ) {
    if (todo.isAllDay) return true;
    final sameDay = start.year == end.year &&
        start.month == end.month &&
        start.day == end.day;
    if (!sameDay) {
      final looksLikeWholeDay = start.hour == 0 &&
          start.minute == 0 &&
          (end.hour == 23 && end.minute == 59 ||
              (end.hour == 0 && end.minute == 0 && end.isAfter(start)));
      return looksLikeWholeDay;
    }
    return false;
  }
}
