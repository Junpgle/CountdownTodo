import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'database_helper.dart';
import '../models.dart';

class TimelineService {
  static final TimelineService instance = TimelineService._();
  TimelineService._();

  Future<List<TimelineEvent>> getTodayEvents(String username) => getEventsForDay(username, DateTime.now());

  Future<List<TimelineEvent>> getYesterdayEvents(String username) => 
      getEventsForDay(username, DateTime.now().subtract(const Duration(days: 1)));

  Future<List<TimelineEvent>> getEventsForDay(String username, DateTime day) async {
    final List<TimelineEvent> events = [];
    final startOfDay = DateTime(day.year, day.month, day.day);
    final startOfDayMs = startOfDay.millisecondsSinceEpoch;
    final endOfDayMs = startOfDay.add(const Duration(days: 1)).millisecondsSinceEpoch;

    final db = await DatabaseHelper.instance.database;

    try {
      // 1. 番茄钟记录 (开始 & 结束)
      final pomoRecords = await db.query(
        'pomodoro_records',
        where: 'is_deleted = 0 AND ((start_time >= ? AND start_time < ?) OR (end_time >= ? AND end_time < ?))',
        whereArgs: [startOfDayMs, endOfDayMs, startOfDayMs, endOfDayMs],
      );

      for (var row in pomoRecords) {
        final startTime = row['start_time'] as int;
        final endTime = row['end_time'] as int?;
        final title = row['todo_title'] as String? ?? '无题任务';
        final status = row['status'] as String?;

        if (startTime >= startOfDayMs && startTime < endOfDayMs) {
          events.add(TimelineEvent(
            id: 'pomo_start_${row['uuid']}',
            timestamp: DateTime.fromMillisecondsSinceEpoch(startTime),
            type: TimelineEventType.pomodoroStart,
            title: '开启番茄钟',
            subtitle: title,
          ));
        }

        if (endTime != null && endTime >= startOfDayMs && endTime < endOfDayMs && status == 'completed') {
          events.add(TimelineEvent(
            id: 'pomo_end_${row['uuid']}',
            timestamp: DateTime.fromMillisecondsSinceEpoch(endTime),
            type: TimelineEventType.pomodoroEnd,
            title: '完成番茄专注',
            subtitle: '$title (${(row['actual_duration'] as int? ?? 0) ~/ 60}分钟)',
          ));
        }
      }

      // 2. 待办 (新增 & 完成)
      final todos = await db.query(
        'todos',
        where: 'is_deleted = 0 AND ((created_at >= ? AND created_at < ?) OR (is_completed = 1 AND updated_at >= ? AND updated_at < ?))',
        whereArgs: [startOfDayMs, endOfDayMs, startOfDayMs, endOfDayMs],
      );

      for (var row in todos) {
        final createdAt = row['created_at'] as int?;
        final updatedAt = row['updated_at'] as int?;
        final isCompleted = row['is_completed'] == 1;
        final title = row['content'] as String? ?? '';

        if (createdAt != null && createdAt >= startOfDayMs && createdAt < endOfDayMs) {
          events.add(TimelineEvent(
            id: 'todo_create_${row['uuid']}',
            timestamp: DateTime.fromMillisecondsSinceEpoch(createdAt),
            type: TimelineEventType.todoCreated,
            title: '新增待办',
            subtitle: title,
          ));
        }

        if (isCompleted && updatedAt != null && updatedAt >= startOfDayMs && updatedAt < endOfDayMs) {
          events.add(TimelineEvent(
            id: 'todo_complete_${row['uuid']}',
            timestamp: DateTime.fromMillisecondsSinceEpoch(updatedAt),
            type: TimelineEventType.todoCompleted,
            title: '完成待办',
            subtitle: title,
          ));
        }
      }

      // 3. 倒计时 (新增 & 完成)
      final countdowns = await db.query(
        'countdowns',
        where: 'is_deleted = 0 AND ((created_at >= ? AND created_at < ?) OR (is_completed = 1 AND updated_at >= ? AND updated_at < ?))',
        whereArgs: [startOfDayMs, endOfDayMs, startOfDayMs, endOfDayMs],
      );
      for (var row in countdowns) {
        final createdAt = row['created_at'] as int?;
        final updatedAt = row['updated_at'] as int?;
        final isCompleted = row['is_completed'] == 1;

        if (createdAt != null && createdAt >= startOfDayMs && createdAt < endOfDayMs) {
          events.add(TimelineEvent(
            id: 'cd_create_${row['uuid']}',
            timestamp: DateTime.fromMillisecondsSinceEpoch(createdAt),
            type: TimelineEventType.countdownCreated,
            title: '新增倒计时',
            subtitle: row['title'] as String? ?? '',
          ));
        }

        if (isCompleted && updatedAt != null && updatedAt >= startOfDayMs && updatedAt < endOfDayMs) {
          events.add(TimelineEvent(
            id: 'cd_complete_${row['uuid']}',
            timestamp: DateTime.fromMillisecondsSinceEpoch(updatedAt),
            type: TimelineEventType.countdownCompleted,
            title: '倒计时达成',
            subtitle: row['title'] as String? ?? '',
          ));
        }
      }

      // 4. 搜索历史
      final searchHistory = await db.query(
        'search_history',
        where: 'timestamp >= ? AND timestamp < ?',
        whereArgs: [startOfDayMs, endOfDayMs],
      );
      for (var row in searchHistory) {
        events.add(TimelineEvent(
          id: 'search_${row['id']}',
          timestamp: DateTime.fromMillisecondsSinceEpoch(row['timestamp'] as int),
          type: TimelineEventType.searchQuery,
          title: '搜索内容',
          subtitle: row['query'] as String? ?? '',
        ));
      }

      // 5. 课程 (开始 & 结束)
      final dayStr = DateFormat('yyyy-MM-dd').format(day);
      final courses = await db.query(
        'courses',
        where: 'date = ? OR weekday = ?',
        whereArgs: [dayStr, day.weekday],
      );

      final seenCourses = <String>{};
      for (var row in courses) {
        final courseName = row['course_name'] as String? ?? '未知课程';
        final startTimeInt = row['start_time'] as int;
        
        // 去重：同一天同一个名称和开始时间只显示一次
        final dedupKey = '${courseName}_$startTimeInt';
        if (seenCourses.contains(dedupKey)) continue;
        seenCourses.add(dedupKey);

        final roomName = row['room_name'] as String? ?? '';
        final endTimeInt = row['end_time'] as int;
        
        final startTime = DateTime(day.year, day.month, day.day, startTimeInt ~/ 100, startTimeInt % 100);
        final endTime = DateTime(day.year, day.month, day.day, endTimeInt ~/ 100, endTimeInt % 100);

        events.add(TimelineEvent(
          id: 'course_start_${row['uuid']}_$dayStr',
          timestamp: startTime,
          type: TimelineEventType.courseStart,
          title: '上课时间',
          subtitle: '$courseName${roomName.isNotEmpty ? ' @ $roomName' : ''}',
        ));

        events.add(TimelineEvent(
          id: 'course_end_${row['uuid']}_$dayStr',
          timestamp: endTime,
          type: TimelineEventType.courseEnd,
          title: '下课时间',
          subtitle: courseName,
        ));
      }

    } catch (e) {
      debugPrint('❌ TimelineService.getEventsForDay error: $e');
    }

    // 排序：按时间倒序
    events.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return events;
  }

  Future<TimelineSummary> getTodaySummary(String username) => getSummaryForDay(username, DateTime.now());

  Future<TimelineSummary> getSummaryForDay(String username, DateTime day) async {
    final startOfDay = DateTime(day.year, day.month, day.day);
    final startOfDayMs = startOfDay.millisecondsSinceEpoch;
    final endOfDayMs = startOfDay.add(const Duration(days: 1)).millisecondsSinceEpoch;
    
    final now = DateTime.now();
    final isToday = startOfDay.isAtSameMomentAs(DateTime(now.year, now.month, now.day));
    final currentHHMM = isToday ? now.hour * 100 + now.minute : 2359;
    final dayStr = DateFormat('yyyy-MM-dd').format(day);

    final db = await DatabaseHelper.instance.database;

    int searchCount = 0;
    DateTime? lastSearchTime;
    int todoCreated = 0;
    int todoCompleted = 0;
    int countdownCreated = 0;
    int countdownCompleted = 0;
    List<String> attendedCourses = [];
    int pomodoroCount = 0;

    try {
      // 1. 搜索
      final searches = await db.query(
        'search_history',
        where: 'timestamp >= ? AND timestamp < ?',
        whereArgs: [startOfDayMs, endOfDayMs],
        orderBy: 'timestamp DESC',
      );
      searchCount = searches.length;
      if (searches.isNotEmpty) {
        lastSearchTime = DateTime.fromMillisecondsSinceEpoch(searches.first['timestamp'] as int);
      }

      // 2. 待办
      final todos = await db.query(
        'todos',
        where: 'is_deleted = 0 AND ((created_at >= ? AND created_at < ?) OR (is_completed = 1 AND updated_at >= ? AND updated_at < ?))',
        whereArgs: [startOfDayMs, endOfDayMs, startOfDayMs, endOfDayMs],
      );
      for (var r in todos) {
        final c = r['created_at'] as int?;
        final u = r['updated_at'] as int?;
        if (c != null && c >= startOfDayMs && c < endOfDayMs) todoCreated++;
        if (r['is_completed'] == 1 && u != null && u >= startOfDayMs && u < endOfDayMs) todoCompleted++;
      }

      // 3. 倒计时
      final cds = await db.query(
        'countdowns',
        where: 'is_deleted = 0 AND ((created_at >= ? AND created_at < ?) OR (is_completed = 1 AND updated_at >= ? AND updated_at < ?))',
        whereArgs: [startOfDayMs, endOfDayMs, startOfDayMs, endOfDayMs],
      );
      for (var r in cds) {
        final c = r['created_at'] as int?;
        final u = r['updated_at'] as int?;
        if (c != null && c >= startOfDayMs && c < endOfDayMs) countdownCreated++;
        if (r['is_completed'] == 1 && u != null && u >= startOfDayMs && u < endOfDayMs) countdownCompleted++;
      }

      // 4. 课程 (已上的)
      final courses = await db.query(
        'courses',
        where: 'date = ? AND end_time < ?',
        whereArgs: [dayStr, currentHHMM],
      );
      // 使用 Set 去重
      attendedCourses = courses.map((e) => e['course_name'] as String).toSet().toList();

      // 5. 番茄钟 (完成次数)
      final poms = await db.query(
        'pomodoro_records',
        where: "is_deleted = 0 AND status = 'completed' AND end_time >= ? AND end_time < ?",
        whereArgs: [startOfDayMs, endOfDayMs],
      );
      pomodoroCount = poms.length;

    } catch (e) {
      debugPrint('❌ getSummaryForDay error: $e');
    }

    return TimelineSummary(
      searchCount: searchCount,
      lastSearchTime: lastSearchTime,
      todoCreatedCount: todoCreated,
      todoCompletedCount: todoCompleted,
      countdownCreatedCount: countdownCreated,
      countdownCompletedCount: countdownCompleted,
      attendedCourses: attendedCourses,
      pomodoroCount: pomodoroCount,
    );
  }
}

class TimelineSummary {
  final int searchCount;
  final DateTime? lastSearchTime;
  final int todoCreatedCount;
  final int todoCompletedCount;
  final int countdownCreatedCount;
  final int countdownCompletedCount;
  final List<String> attendedCourses;
  final int pomodoroCount;

  TimelineSummary({
    required this.searchCount,
    this.lastSearchTime,
    required this.todoCreatedCount,
    required this.todoCompletedCount,
    required this.countdownCreatedCount,
    required this.countdownCompletedCount,
    required this.attendedCourses,
    required this.pomodoroCount,
  });
}
