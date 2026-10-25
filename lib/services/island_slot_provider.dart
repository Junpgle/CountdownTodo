import 'package:intl/intl.dart';

import '../storage_service.dart';
import '../models.dart';
import '../utils/calendar_date_math.dart';
import 'course_service.dart';
import 'item_semantics_service.dart';
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

  static final Map<(String?, String), DateFormat> _dateFormatters = {};

  static DateFormat _dateFormat(String pattern) {
    final locale = Intl.defaultLocale;
    return _dateFormatters.putIfAbsent((
      locale,
      pattern,
    ), () => DateFormat(pattern, locale));
  }

  /// Detect special todo type from title keywords
  static String detectTodoType(String title) =>
      ItemSemanticsService.specialTodoTypeForTitle(title);

  static int completedFocusSecondsInRange(
    Iterable<PomodoroRecord> records,
    DateTime start,
    DateTime endExclusive,
  ) {
    final startMs = start.millisecondsSinceEpoch;
    final endMs = endExclusive.millisecondsSinceEpoch;
    return records
        .where(
          (record) =>
              !record.isDeleted &&
              record.status == PomodoroRecordStatus.completed &&
              record.startTime >= startMs &&
              record.startTime < endMs,
        )
        .fold(0, (seconds, record) => seconds + (record.actualDuration ?? 0));
  }

  /// Get slot data for a specific type
  static Future<IslandSlotData> getSlotData(
    String type, {
    required bool isLeft,
  }) async {
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
      // debugPrint('[IslandSlotProvider] Error getting slot $type: $e');
      return const IslandSlotData.empty();
    }
  }

  /// Get date slot data
  static Future<IslandSlotData> _getDateSlot(bool isLeft) async {
    final now = DateTime.now();
    final display = _dateFormat('M月d日').format(now);
    return IslandSlotData(display: display, type: 'date', detailTitle: display);
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
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    TodoItem? selectedTodo;
    DateTime? selectedDueDay;
    var selectedUrgency = 4;
    for (final todo in todos) {
      if (todo.isDone || todo.isDeleted || todo.isSkipped) continue;

      final dueDate = todo.dueDate;
      final dueDay = dueDate == null
          ? null
          : DateTime(dueDate.year, dueDate.month, dueDate.day);
      final urgency = dueDay == null
          ? 3
          : dueDay.isBefore(today)
          ? 0
          : dueDay.isAtSameMomentAs(today)
          ? 1
          : 2;

      var isPreferred = selectedTodo == null || urgency < selectedUrgency;
      final current = selectedTodo;
      if (!isPreferred && current != null && urgency == selectedUrgency) {
        final currentDueDate = current.dueDate;
        if (dueDate == null && currentDueDate == null) {
          isPreferred = todo.createdAt > current.createdAt;
        } else if (dueDate != null && currentDueDate == null) {
          isPreferred = true;
        } else if (dueDate != null && currentDueDate != null) {
          isPreferred = dueDate.isBefore(currentDueDate);
        }
      }

      if (isPreferred) {
        selectedTodo = todo;
        selectedDueDay = dueDay;
        selectedUrgency = urgency;
      }
    }

    final t = selectedTodo;
    if (t == null) {
      return const IslandSlotData(display: '', type: 'todo');
    }
    final time = t.dueDate != null
        ? _dateFormat('MM-dd').format(t.dueDate!)
        : '';

    // 判断是否逾期
    final isOverdue = selectedDueDay != null && selectedDueDay.isBefore(today);

    // 检测特殊待办类型
    final specialType = detectTodoType(t.title);

    final overdueTag = isOverdue ? '逾期 ' : '';
    final display = isLeft
        ? (time.isNotEmpty ? '[$overdueTag$time] ${t.title}' : t.title)
        : (time.isNotEmpty ? '${t.title} [$overdueTag$time]' : t.title);

    final timeRange = t.dueDate != null
        ? _dateFormat('HH:mm').format(t.dueDate!)
        : '';

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
      final username = await StorageService.getLoginSession() ?? 'default';
      final dashboard = await CourseService.getDashboardCourses(username);
      final courses = dashboard['courses'] as List?;

      if (courses != null && courses.isNotEmpty) {
        final now = DateTime.now();
        final isToday = dashboard['title'] == '今日课程';
        CourseItem? c;
        for (final item in courses) {
          if (item is! CourseItem) continue;
          if (isToday) {
            final endHour = item.endTime ~/ 100;
            final endMin = item.endTime % 100;
            final courseEnd = DateTime(
              now.year,
              now.month,
              now.day,
              endHour,
              endMin,
            );
            if (!now.isBefore(courseEnd)) continue;
          }
          c = item;
          break;
        }

        if (c != null) {
          final startHour = c.startTime ~/ 100;
          final startMin = c.startTime % 100;
          final courseStart = DateTime(
            now.year,
            now.month,
            now.day,
            startHour,
            startMin,
          );
          final isOngoing = now.isAfter(courseStart);

          final time = isOngoing ? c.formattedEndTime : c.formattedStartTime;
          final timeLabel = isOngoing ? '结束' : '开始';
          final dateLabel = _courseDateLabel(
            course: c,
            fallbackTomorrow: !isToday,
            now: now,
          );
          final leadLabel = isToday ? time : dateLabel;
          final detailTime = isToday ? '$time$timeLabel' : dateLabel;
          final display = isLeft
              ? '[$leadLabel] ${c.courseName}'
              : '${c.courseName} [$leadLabel]';

          return IslandSlotData(
            display: display,
            type: 'course',
            detailTitle: c.courseName,
            detailSubtitle: c.teacherName,
            detailLocation: c.roomName,
            detailTime: detailTime,
          );
        }
      }
    } catch (_) {}
    return const IslandSlotData(display: '', type: 'course');
  }

  static String _courseDateLabel({
    required CourseItem course,
    required bool fallbackTomorrow,
    required DateTime now,
  }) {
    DateTime? courseDate;
    if (course.date.isNotEmpty) {
      try {
        courseDate = _dateFormat('yyyy-MM-dd').parseStrict(course.date);
      } catch (_) {
        courseDate = null;
      }
    }

    final today = DateTime(now.year, now.month, now.day);
    if (courseDate == null) {
      return fallbackTomorrow ? '明天' : '今天';
    }

    final day = DateTime(courseDate.year, courseDate.month, courseDate.day);
    final diff = CalendarDateMath.daysBetween(today, day);
    if (diff <= 0) return '今天';
    if (diff == 1) return '明天';
    if (diff == 2) return '后天';
    return '$diff天后';
  }

  /// Get pomodoro record slot data
  static Future<IslandSlotData> _getRecordSlot(bool isLeft) async {
    try {
      final record = await PomodoroService.getLatestRecord();
      if (record != null) {
        final time = _dateFormat('HH:mm').format(
          DateTime.fromMillisecondsSinceEpoch(
            record.endTime ?? record.startTime,
          ),
        );
        final title = record.todoTitle ?? '专注';
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
      // debugPrint('[IslandSlotProvider] getCountdowns: ${cds.length} items');
      final now = DateTime.now();
      final today = CalendarDateMath.dateOnly(now);
      CountdownItem? nearest;
      var nearestDays = 0;
      for (final countdown in cds) {
        if (countdown.isDeleted) continue;
        final days = CalendarDateMath.daysBetween(today, countdown.targetDate);
        if (days < 0) continue;
        if (nearest == null ||
            countdown.targetDate.isBefore(nearest.targetDate)) {
          nearest = countdown;
          nearestDays = days;
        }
      }

      if (nearest != null) {
        final c = nearest;
        final days = nearestDays;
        final info = '$days天';
        final display = isLeft ? '[$info] ${c.title}' : '${c.title} [$info]';
        // debugPrint('[IslandSlotProvider] countdown display: $display');
        return IslandSlotData(
          display: display,
          type: 'countdown',
          detailTitle: c.title,
          detailTime: _dateFormat('yyyy-MM-dd').format(c.targetDate),
          detailNote: '还有$days天',
        );
      }
    } catch (e) {
      // debugPrint('[IslandSlotProvider] countdown error: $e');
    }
    return const IslandSlotData(display: '', type: 'countdown');
  }

  /// Get focus time slot data (today's total focus, or yesterday if none)
  static Future<IslandSlotData> _getFocusSlot(bool isLeft) async {
    try {
      final now = DateTime.now();
      final todayRange = CalendarDateMath.dayRange(now);
      final yesterdayStart = CalendarDateMath.addDays(todayRange.start, -1);
      final yesterdayRange = CalendarDateMath.dayRange(yesterdayStart);
      final records = await PomodoroService.getRecordsInRange(
        yesterdayRange.start,
        todayRange.endExclusive,
      );
      final todayStartMs = todayRange.start.millisecondsSinceEpoch;
      final todayEndMs = todayRange.endExclusive.millisecondsSinceEpoch;
      final yesterdayStartMs = yesterdayRange.start.millisecondsSinceEpoch;
      var todayFocusSeconds = 0;
      var yesterdayFocusSeconds = 0;
      for (final record in records) {
        if (record.isDeleted ||
            record.status != PomodoroRecordStatus.completed) {
          continue;
        }
        final startTime = record.startTime;
        final actualDuration = record.actualDuration ?? 0;
        if (startTime >= todayStartMs && startTime < todayEndMs) {
          todayFocusSeconds += actualDuration;
        } else if (startTime >= yesterdayStartMs && startTime < todayStartMs) {
          yesterdayFocusSeconds += actualDuration;
        }
      }

      // If no focus today, calculate yesterday's
      final useYesterday = todayFocusSeconds == 0;
      final displaySeconds = useYesterday
          ? yesterdayFocusSeconds
          : todayFocusSeconds;
      final label = useYesterday ? '昨日' : '今日';

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
          .where(
            (t) =>
                !t.isDone && !t.isDeleted && !t.isSkipped && t.dueDate != null,
          )
          .toList();

      for (var t in active) {
        if (t.dueDate!.year == now.year &&
            t.dueDate!.month == now.month &&
            t.dueDate!.day == now.day) {
          queue.add({
            'text': t.title,
            'type': 'todo',
            'timeLabel': _dateFormat('HH:mm').format(t.dueDate!),
          });
        }
      }
    } catch (_) {}
    return queue;
  }
}
