import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import '../storage_service.dart';
import '../services/course_service.dart';
import 'island_config.dart';

/// Service for checking and managing reminders for the island window.
class IslandReminderService {
  IslandReminderService._();

  /// Check for upcoming reminders within the configured window.
  /// Returns the most urgent reminder or null if none found.
  static Future<Map<String, dynamic>?> checkUpcomingReminder() async {
    final now = DateTime.now();
    final allReminders = <Map<String, dynamic>>[];

    debugPrint('[IslandReminder] Checking reminders: now=$now');

    // Check todos
    final todoReminders = await _checkTodos(now);
    allReminders.addAll(todoReminders);

    // Check courses
    final courseReminders = await _checkCourses(now);
    allReminders.addAll(courseReminders);

    debugPrint('[IslandReminder] Found ${allReminders.length} reminders');
    if (allReminders.isEmpty) return null;

    // Sort by time, most urgent first
    allReminders.sort((a, b) =>
        (a['minutesUntil'] as int).compareTo(b['minutesUntil'] as int));
    debugPrint('[IslandReminder] Returning most urgent: ${allReminders.first}');
    return allReminders.first;
  }

  /// Check for upcoming todo reminders
  static Future<List<Map<String, dynamic>>> _checkTodos(DateTime now) async {
    final reminders = <Map<String, dynamic>>[];

    try {
      // Try reading from shared file first
      List<Map<String, dynamic>> todoMaps = [];
      try {
        final dir = await getApplicationSupportDirectory();
        final file = File('${dir.path}/${IslandConfig.todoFileName}');
        if (await file.exists()) {
          final content = await file.readAsString();
          final List<dynamic> decoded = jsonDecode(content);
          todoMaps = decoded.cast<Map<String, dynamic>>();
          debugPrint(
              '[IslandReminder] Got ${todoMaps.length} todos from shared file');
        }
      } catch (e) {
        debugPrint('[IslandReminder] Failed to read shared file: $e');
      }

      // Fallback to StorageService
      if (todoMaps.isEmpty) {
        final username = await StorageService.getLoginSession() ?? 'default';
        final todos = await StorageService.getTodos(username);
        debugPrint(
            '[IslandReminder] Got ${todos.length} todos from StorageService');
        todoMaps = todos
            .map((t) => {
                  'id': t.id,
                  'title': t.title,
                  'remark': t.remark,
                  'dueDate': t.dueDate?.millisecondsSinceEpoch,
                  'createdDate': t.createdDate,
                  'createdAt': t.createdAt,
                  'isDone': t.isDone,
                  'isDeleted': t.isDeleted,
                })
            .toList();
      }

      // Filter active todos
      final activeTodos = todoMaps
          .where((t) =>
              !(t['isDone'] as bool? ?? false) &&
              !(t['isDeleted'] as bool? ?? false) &&
              t['dueDate'] != null)
          .toList();

      for (final t in activeTodos) {
        final reminder = _processTodoReminder(t, now);
        if (reminder != null) {
          reminders.add(reminder);
        }
      }
    } catch (e) {
      debugPrint('[IslandReminder] Check todos failed: $e');
    }

    return reminders;
  }

  /// Process a single todo and return a reminder if within window
  static Map<String, dynamic>? _processTodoReminder(
      Map<String, dynamic> t, DateTime now) {
    final createdDate = t['createdDate'] as int?;
    final dueDateMs = t['dueDate'] as int?;
    final title = t['title']?.toString() ?? '';
    final remark = t['remark']?.toString() ?? '';
    final id = t['id']?.toString() ?? '';

    if (dueDateMs == null) return null;

    DateTime? startTime;
    bool hasExplicitStartTime = false;

    if (createdDate != null) {
      startTime = DateTime.fromMillisecondsSinceEpoch(createdDate, isUtc: true)
          .toLocal();
      hasExplicitStartTime = startTime.hour != 0 || startTime.minute != 0;
    }

    final dueDate =
        DateTime.fromMillisecondsSinceEpoch(dueDateMs, isUtc: true).toLocal();

    // Check start time reminder
    if (hasExplicitStartTime && startTime != null) {
      final startDiff = startTime.difference(now).inMinutes;
      if (startDiff >= 0 && startDiff <= 20) {
        return {
          'type': 'todo',
          'title': title,
          'subtitle': remark,
          'startTime':
              '${startTime.hour.toString().padLeft(2, '0')}:${startTime.minute.toString().padLeft(2, '0')}',
          'endTime':
              '${dueDate.hour.toString().padLeft(2, '0')}:${dueDate.minute.toString().padLeft(2, '0')}',
          'minutesUntil': startDiff,
          'isEnding': false,
          'itemId': id,
        };
      }
    }

    // Check end time reminder
    final endDiff = dueDate.difference(now).inMinutes;
    if (endDiff >= 0 && endDiff <= 20) {
      return {
        'type': 'todo',
        'title': title,
        'subtitle': remark,
        'startTime': hasExplicitStartTime && startTime != null
            ? '${startTime.hour.toString().padLeft(2, '0')}:${startTime.minute.toString().padLeft(2, '0')}'
            : '',
        'endTime':
            '${dueDate.hour.toString().padLeft(2, '0')}:${dueDate.minute.toString().padLeft(2, '0')}',
        'minutesUntil': endDiff,
        'isEnding': true,
        'itemId': id,
      };
    }

    return null;
  }

  /// Check for upcoming course reminders
  static Future<List<Map<String, dynamic>>> _checkCourses(DateTime now) async {
    final reminders = <Map<String, dynamic>>[];

    try {
      final courses = await CourseService.getAllCourses();
      debugPrint('[IslandReminder] Got ${courses.length} courses');

      final todayStr =
          '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

      for (final c in courses.where((c) => c.date == todayStr)) {
        final startHour = c.startTime ~/ 100;
        final startMin = c.startTime % 100;
        final courseStart =
            DateTime(now.year, now.month, now.day, startHour, startMin);
        final diff = courseStart.difference(now).inMinutes;

        if (diff >= 0 && diff <= 20) {
          reminders.add({
            'type': 'course',
            'title': c.courseName,
            'subtitle': c.roomName,
            'startTime': c.formattedStartTime,
            'endTime': c.formattedEndTime,
            'minutesUntil': diff,
            'isEnding': false,
            'itemId': '${c.date}_${c.startTime}',
          });
        }
      }
    } catch (e) {
      debugPrint('[IslandReminder] Check courses failed: $e');
    }

    return reminders;
  }

  /// Set up a timer to expire a reminder after the specified minutes
  static Timer setupExpireTimer(
    Map<String, dynamic> reminder,
    void Function(Map<String, dynamic> currentState) onExpire,
    Map<String, dynamic> Function() getCurrentState,
  ) {
    final minutesUntil = reminder['minutesUntil'] as int? ?? 0;
    final itemId = reminder['itemId']?.toString();

    if (minutesUntil < 0) {
      debugPrint('[IslandReminder] Reminder already expired: $itemId');
      onExpire(getCurrentState());
      return Timer(Duration.zero, () {});
    }

    final expireDuration = Duration(minutes: minutesUntil);
    debugPrint(
        '[IslandReminder] Setting expire timer: $itemId, ${minutesUntil}min');

    return Timer(expireDuration, () {
      debugPrint('[IslandReminder] Reminder expired: $itemId');
      final currentState = getCurrentState();
      final currentReminderData =
          currentState['reminderPopupData'] as Map<String, dynamic>?;
      final currentItemId = currentReminderData?['itemId']?.toString();

      if (currentItemId == itemId) {
        onExpire(currentState);
      }
    });
  }
}
