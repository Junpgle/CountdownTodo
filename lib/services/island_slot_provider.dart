import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import '../storage_service.dart';
import 'course_service.dart';
import 'pomodoro_service.dart';

/// Data structure for island slot content
class IslandSlotData {
  final String display;
  final String type;
  final String detailTitle;
  final String detailSubtitle;
  final String detailLocation;
  final String detailTime;
  final String detailNote;

  const IslandSlotData({
    required this.display,
    required this.type,
    this.detailTitle = '',
    this.detailSubtitle = '',
    this.detailLocation = '',
    this.detailTime = '',
    this.detailNote = '',
  });

  const IslandSlotData.empty()
      : display = '',
        type = '',
        detailTitle = '',
        detailSubtitle = '',
        detailLocation = '',
        detailTime = '',
        detailNote = '';

  bool get isEmpty => display.isEmpty;
  bool get isNotEmpty => display.isNotEmpty;

  Map<String, String> toMap() => {
        'display': display,
        'type': type,
        'detail_title': detailTitle,
        'detail_subtitle': detailSubtitle,
        'detail_location': detailLocation,
        'detail_time': detailTime,
        'detail_note': detailNote,
      };
}

/// Provider for island slot data (todo, course, countdown, record).
/// Centralizes data retrieval logic for the island display.
class IslandSlotProvider {
  IslandSlotProvider._();

  /// Get slot data for a specific type
  static Future<IslandSlotData> getSlotData(String type,
      {required bool isLeft}) async {
    try {
      switch (type) {
        case 'todo':
          return await _getTodoSlot(isLeft);
        case 'course':
          return await _getCourseSlot(isLeft);
        case 'record':
          return await _getRecordSlot(isLeft);
        case 'countdown':
          return await _getCountdownSlot(isLeft);
        case 'focus':
          return await _getFocusSlot(isLeft);
        default:
          return const IslandSlotData.empty();
      }
    } catch (e) {
      debugPrint('[IslandSlotProvider] Error getting slot $type: $e');
      return const IslandSlotData.empty();
    }
  }

  /// Get todo slot data
  static Future<IslandSlotData> _getTodoSlot(bool isLeft) async {
    final username = await StorageService.getLoginSession() ?? 'default';
    final todos = await StorageService.getTodos(username);
    final active = todos.where((t) => !t.isDone && !t.isDeleted).toList();

    if (active.isEmpty) {
      return const IslandSlotData(display: '', type: 'todo');
    }

    active.sort((a, b) {
      if (a.dueDate == null && b.dueDate == null) {
        return b.createdAt.compareTo(a.createdAt);
      }
      if (a.dueDate == null) return 1;
      if (b.dueDate == null) return -1;
      return a.dueDate!.compareTo(b.dueDate!);
    });

    final t = active.first;
    final time =
        t.dueDate != null ? DateFormat('MM-dd').format(t.dueDate!) : '';
    final display = isLeft
        ? (time.isNotEmpty ? '[$time] ${t.title}' : t.title)
        : (time.isNotEmpty ? '${t.title} [$time]' : t.title);

    final timeRange =
        t.dueDate != null ? DateFormat('HH:mm').format(t.dueDate!) : '';

    return IslandSlotData(
      display: display,
      type: 'todo',
      detailTitle: t.title,
      detailSubtitle: t.remark ?? '',
      detailTime: timeRange,
      detailNote: time.isNotEmpty ? time : '',
    );
  }

  /// Get course slot data
  static Future<IslandSlotData> _getCourseSlot(bool isLeft) async {
    try {
      final dashboard = await CourseService.getDashboardCourses();
      final courses = dashboard['courses'] as List?;

      if (courses != null && courses.isNotEmpty) {
        final now = DateTime.now();
        final valid = courses.where((c) {
          if (c is! CourseItem) return false;
          if (dashboard['title'] == '今日课程') {
            final endHour = c.endTime ~/ 100;
            final endMin = c.endTime % 100;
            final courseEnd =
                DateTime(now.year, now.month, now.day, endHour, endMin);
            return now.isBefore(courseEnd);
          }
          return true;
        }).toList();

        if (valid.isNotEmpty) {
          final c = valid.first as CourseItem;
          final startHour = c.startTime ~/ 100;
          final startMin = c.startTime % 100;
          final courseStart =
              DateTime(now.year, now.month, now.day, startHour, startMin);
          final isOngoing = now.isAfter(courseStart);

          final time = isOngoing ? c.formattedEndTime : c.formattedStartTime;
          final timeLabel = isOngoing ? '结束' : '开始';
          final display =
              isLeft ? '[$time] ${c.courseName}' : '${c.courseName} [$time]';

          return IslandSlotData(
            display: display,
            type: 'course',
            detailTitle: c.courseName,
            detailSubtitle: c.teacherName,
            detailLocation: c.roomName,
            detailTime: '$time$timeLabel',
          );
        }
      }
    } catch (_) {}
    return const IslandSlotData(display: '', type: 'course');
  }

  /// Get pomodoro record slot data
  static Future<IslandSlotData> _getRecordSlot(bool isLeft) async {
    try {
      final records = await PomodoroService.getRecords();
      if (records.isNotEmpty) {
        final r = records.first;
        final time = DateFormat('HH:mm').format(
            DateTime.fromMillisecondsSinceEpoch(r.endTime ?? r.startTime));
        final title = r.todoTitle ?? '专注';
        return IslandSlotData(
          display: isLeft ? '[$time] $title' : '$title [$time]',
          type: 'record',
          detailTitle: title,
          detailTime: time,
        );
      }
    } catch (_) {}
    return const IslandSlotData(display: '无记录', type: 'record');
  }

  /// Get countdown slot data
  static Future<IslandSlotData> _getCountdownSlot(bool isLeft) async {
    try {
      final username = await StorageService.getLoginSession() ?? 'default';
      final cds = await StorageService.getCountdowns(username);
      debugPrint('[IslandSlotProvider] getCountdowns: ${cds.length} items');
      final now = DateTime.now();
      final active =
          cds.where((c) => !c.isDeleted && c.targetDate.isAfter(now)).toList();
      debugPrint('[IslandSlotProvider] active countdowns: ${active.length}');
      active.sort((a, b) => a.targetDate.compareTo(b.targetDate));

      if (active.isNotEmpty) {
        final c = active.first;
        final days = c.targetDate.difference(now).inDays;
        final info = '${days}天';
        final display = isLeft ? '[$info] ${c.title}' : '${c.title} [$info]';
        debugPrint('[IslandSlotProvider] countdown display: $display');
        return IslandSlotData(
          display: display,
          type: 'countdown',
          detailTitle: c.title,
          detailTime: DateFormat('yyyy-MM-dd').format(c.targetDate),
          detailNote: '还有${days}天',
        );
      }
    } catch (e) {
      debugPrint('[IslandSlotProvider] countdown error: $e');
    }
    return const IslandSlotData(display: '', type: 'countdown');
  }

  /// Get focus time slot data (today's total focus, or yesterday if none)
  static Future<IslandSlotData> _getFocusSlot(bool isLeft) async {
    try {
      final records = await PomodoroService.getRecords();
      final now = DateTime.now();
      final todayStart =
          DateTime(now.year, now.month, now.day).millisecondsSinceEpoch;
      final yesterdayStart = todayStart - 86400000; // 24 hours in ms

      // Calculate today's focus time
      int todayFocusSeconds = 0;
      for (final r in records) {
        if (r.startTime >= todayStart &&
            r.status == PomodoroRecordStatus.completed) {
          todayFocusSeconds += r.actualDuration ?? 0;
        }
      }

      // If no focus today, calculate yesterday's
      int displaySeconds = todayFocusSeconds;
      String label = '今日';
      if (todayFocusSeconds == 0) {
        for (final r in records) {
          if (r.startTime >= yesterdayStart &&
              r.startTime < todayStart &&
              r.status == PomodoroRecordStatus.completed) {
            displaySeconds += r.actualDuration ?? 0;
          }
        }
        label = '昨日';
      }

      if (displaySeconds > 0) {
        final hours = displaySeconds ~/ 3600;
        final minutes = (displaySeconds % 3600) ~/ 60;
        final timeStr = hours > 0 ? '${hours}h${minutes}m' : '${minutes}m';
        final display = isLeft ? '[$label] $timeStr' : '$timeStr [$label]';

        return IslandSlotData(
          display: display,
          type: 'focus',
          detailTitle: '$label专注',
          detailTime: timeStr,
          detailNote: '共$displaySeconds秒',
        );
      }
    } catch (_) {}
    return const IslandSlotData(display: '', type: 'focus');
  }

  /// Get reminder queue for todos due today
  static Future<List<Map<String, String>>> getReminderQueue() async {
    final queue = <Map<String, String>>[];
    try {
      final username = await StorageService.getLoginSession() ?? 'default';
      final todos = await StorageService.getTodos(username);
      final now = DateTime.now();
      final active = todos
          .where((t) => !t.isDone && !t.isDeleted && t.dueDate != null)
          .toList();

      for (var t in active) {
        if (t.dueDate!.year == now.year &&
            t.dueDate!.month == now.month &&
            t.dueDate!.day == now.day) {
          queue.add({
            'text': t.title,
            'type': 'todo',
            'timeLabel': DateFormat('HH:mm').format(t.dueDate!),
          });
        }
      }
    } catch (_) {}
    return queue;
  }
}
