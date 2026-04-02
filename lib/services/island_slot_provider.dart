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
  final String specialType; // delivery/cafe/food/restaurant

  const IslandSlotData({
    required this.display,
    required this.type,
    this.detailTitle = '',
    this.detailSubtitle = '',
    this.detailLocation = '',
    this.detailTime = '',
    this.detailNote = '',
    this.specialType = '',
  });

  const IslandSlotData.empty()
      : display = '',
        type = '',
        detailTitle = '',
        detailSubtitle = '',
        detailLocation = '',
        detailTime = '',
        detailNote = '',
        specialType = '';

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
        if (specialType.isNotEmpty) 'specialType': specialType,
      };
}

/// Provider for island slot data (todo, course, countdown, record).
/// Centralizes data retrieval logic for the island display.
class IslandSlotProvider {
  IslandSlotProvider._();

  /// Detect special todo type from title keywords
  static String detectTodoType(String title) {
    final lower = title.toLowerCase();
    if (lower.contains('快递') ||
        lower.contains('取件') ||
        lower.contains('顺丰') ||
        lower.contains('京东') ||
        lower.contains('菜鸟') ||
        lower.contains('中通') ||
        lower.contains('圆通') ||
        lower.contains('韵达') ||
        lower.contains('申通') ||
        lower.contains('极兔') ||
        lower.contains('德邦')) {
      return 'delivery';
    } else if (lower.contains('奶茶') ||
        lower.contains('咖啡') ||
        lower.contains('古茗') ||
        lower.contains('茶百道') ||
        lower.contains('蜜雪冰城') ||
        lower.contains('瑞幸') ||
        lower.contains('星巴克') ||
        lower.contains('库迪') ||
        lower.contains('coco') ||
        lower.contains('一点点')) {
      return 'cafe';
    } else if (lower.contains('取餐') ||
        lower.contains('外卖') ||
        lower.contains('肯德基') ||
        lower.contains('麦当劳') ||
        lower.contains('kfc')) {
      return 'food';
    } else if (lower.contains('海底捞') ||
        lower.contains('太二') ||
        lower.contains('外婆家') ||
        lower.contains('西贝') ||
        lower.contains('必胜客') ||
        lower.contains('堂食') ||
        lower.contains('餐饮')) {
      return 'restaurant';
    }
    return 'default';
  }

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
        case 'date':
          return await _getDateSlot(isLeft);
        case 'weekday':
          return await _getWeekdaySlot(isLeft);
        default:
          return const IslandSlotData.empty();
      }
    } catch (e) {
      debugPrint('[IslandSlotProvider] Error getting slot $type: $e');
      return const IslandSlotData.empty();
    }
  }

  /// Get date slot data
  static Future<IslandSlotData> _getDateSlot(bool isLeft) async {
    final now = DateTime.now();
    final display = DateFormat('M月d日').format(now);
    return IslandSlotData(
      display: display,
      type: 'date',
      detailTitle: display,
    );
  }

  /// Get weekday slot data
  static Future<IslandSlotData> _getWeekdaySlot(bool isLeft) async {
    final now = DateTime.now();
    final weekdays = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
    final weekday = weekdays[now.weekday - 1];
    return IslandSlotData(
      display: weekday,
      type: 'weekday',
      detailTitle: weekday,
    );
  }

  /// Get todo slot data
  static Future<IslandSlotData> _getTodoSlot(bool isLeft) async {
    final username = await StorageService.getLoginSession() ?? 'default';
    final todos = await StorageService.getTodos(username);
    final active = todos.where((t) => !t.isDone && !t.isDeleted).toList();

    if (active.isEmpty) {
      return const IslandSlotData(display: '', type: 'todo');
    }

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    int urgencyScore(dynamic t) {
      if (t.dueDate == null) return 3;
      final dueDay =
          DateTime(t.dueDate!.year, t.dueDate!.month, t.dueDate!.day);
      if (dueDay.isBefore(today)) return 0; // 逾期
      if (dueDay.isAtSameMomentAs(today)) return 1; // 今天到期
      return 2; // 未来到期
    }

    active.sort((a, b) {
      final sa = urgencyScore(a);
      final sb = urgencyScore(b);
      if (sa != sb) return sa.compareTo(sb);
      // 同一紧迫级别内: 有 dueDate 的按时间排, 无 dueDate 的按创建时间倒序
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

    // 判断是否逾期
    final isOverdue = t.dueDate != null &&
        DateTime(t.dueDate!.year, t.dueDate!.month, t.dueDate!.day)
            .isBefore(today);

    // 检测特殊待办类型
    final specialType = detectTodoType(t.title);

    final overdueTag = isOverdue ? '逾期 ' : '';
    final display = isLeft
        ? (time.isNotEmpty ? '[$overdueTag$time] ${t.title}' : t.title)
        : (time.isNotEmpty ? '${t.title} [$overdueTag$time]' : t.title);

    final timeRange =
        t.dueDate != null ? DateFormat('HH:mm').format(t.dueDate!) : '';

    return IslandSlotData(
      display: display,
      type: 'todo',
      detailTitle: t.title,
      detailSubtitle: isOverdue ? '已逾期' : (t.remark ?? ''),
      detailTime: timeRange,
      detailNote: time.isNotEmpty ? time : '',
      specialType: specialType,
    );
  }

  /// Get course slot data
  static Future<IslandSlotData> _getCourseSlot(bool isLeft) async {
    try {
      final dashboard = await CourseService.getDashboardCourses();
      final courses = dashboard['courses'] as List?;

      if (courses != null && courses.isNotEmpty) {
        final now = DateTime.now();
        final isToday = dashboard['title'] == '今日课程';
        final valid = courses.where((c) {
          if (c is! CourseItem) return false;
          if (!isToday) return true; // 明日课程不会过期
          final endHour = c.endTime ~/ 100;
          final endMin = c.endTime % 100;
          final courseEnd =
              DateTime(now.year, now.month, now.day, endHour, endMin);
          return now.isBefore(courseEnd);
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
