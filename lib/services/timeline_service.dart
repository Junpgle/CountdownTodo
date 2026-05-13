import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'database_helper.dart';
import 'course_service.dart';
import '../models.dart';

class TimelineService {
  static final TimelineService instance = TimelineService._();
  TimelineService._();

  Future<List<TimelineEvent>> getTodayEvents(String username) => getEventsForDay(username, DateTime.now());

  Future<List<TimelineEvent>> getYesterdayEvents(String username) => 
      getEventsForDay(username, DateTime.now().subtract(const Duration(days: 1)));

  Future<List<TimelineEvent>> getEventsForDay(String username, DateTime day) async {
    final List<TimelineEvent> events = [];
    // 确保 day 是整日期（无时间部分）
    final startOfDay = DateTime(day.year, day.month, day.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));
    final startOfDayMs = startOfDay.millisecondsSinceEpoch;
    final endOfDayMs = endOfDay.millisecondsSinceEpoch;

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
            title: '开始专注',
            subtitle: title,
          ));
        }

        if (endTime != null && endTime >= startOfDayMs && endTime < endOfDayMs) {
          final isCompleted = status == 'completed';
          final isInterrupted = status == 'interrupted';
          final actualSecs = row['actual_duration'] as int? ?? 0;
          final plannedSecs = row['planned_duration'] as int? ?? 0;
          
          // 如果是由于任务未完成而中断（实际时长接近或超过计划时长，或者是正向计时）
          final isTaskUnfinished = isInterrupted && (plannedSecs == 0 || actualSecs >= plannedSecs * 0.9);

          events.add(TimelineEvent(
            id: 'pomo_end_${row['uuid']}',
            timestamp: DateTime.fromMillisecondsSinceEpoch(endTime),
            type: TimelineEventType.pomodoroEnd,
            title: (isCompleted || isTaskUnfinished) ? '完成专注' : '专注结束',
            subtitle: '$title (${actualSecs ~/ 60}分钟)${isInterrupted ? ' • 任务未完成' : ''}',
          ));
        }
      }

      // 2. 待办 (新增 & 编辑 & 完成) - 分开查询以避免混淆
      // 2a. 查询今天新增的待办
      final createdTodos = await db.query(
        'todos',
        where: 'is_deleted = 0 AND created_at >= ? AND created_at < ?',
        whereArgs: [startOfDayMs, endOfDayMs],
      );

      for (var row in createdTodos) {
        final title = row['content'] as String? ?? '';
        final createdAt = row['created_at'] as int;
        
        events.add(TimelineEvent(
          id: 'todo_create_${row['uuid']}',
          timestamp: DateTime.fromMillisecondsSinceEpoch(createdAt),
          type: TimelineEventType.todoCreated,
          title: '新增待办',
          subtitle: title,
        ));
      }

      // 2b. 查询今天编辑的待办（已编辑但未完成，排除无实质修改的）
      final editedTodos = await db.query(
        'todos',
        where: 'is_deleted = 0 AND is_completed = 0 AND updated_at >= ? AND updated_at < ? AND updated_at > created_at',
        whereArgs: [startOfDayMs, endOfDayMs],
      );

      for (var row in editedTodos) {
        final title = row['content'] as String? ?? '';
        final updatedAt = row['updated_at'] as int?;
        
        if (updatedAt != null) {
          events.add(TimelineEvent(
            id: 'todo_edit_${row['uuid']}',
            timestamp: DateTime.fromMillisecondsSinceEpoch(updatedAt),
            type: TimelineEventType.todoEdited,
            title: '编辑待办',
            subtitle: title,
          ));
        }
      }

      // 2c. 查询今天完成的待办
      final completedTodos = await db.query(
        'todos',
        where: 'is_deleted = 0 AND is_completed = 1 AND updated_at >= ? AND updated_at < ?',
        whereArgs: [startOfDayMs, endOfDayMs],
      );

      for (var row in completedTodos) {
        final title = row['content'] as String? ?? '';
        final updatedAt = row['updated_at'] as int?;
        
        if (updatedAt != null) {
          events.add(TimelineEvent(
            id: 'todo_complete_${row['uuid']}',
            timestamp: DateTime.fromMillisecondsSinceEpoch(updatedAt),
            type: TimelineEventType.todoCompleted,
            title: '完成待办',
            subtitle: title,
          ));
        }
      }

      // 3. 倒计时 (新增 & 编辑 & 完成) - 分开查询避免混淆
      // 3a. 查询今天新增的倒计时
      final createdCountdowns = await db.query(
        'countdowns',
        where: 'is_deleted = 0 AND created_at >= ? AND created_at < ?',
        whereArgs: [startOfDayMs, endOfDayMs],
      );

      for (var row in createdCountdowns) {
        final createdAt = row['created_at'] as int;
        events.add(TimelineEvent(
          id: 'cd_create_${row['uuid']}',
          timestamp: DateTime.fromMillisecondsSinceEpoch(createdAt),
          type: TimelineEventType.countdownCreated,
          title: '新增倒计时',
          subtitle: row['title'] as String? ?? '',
        ));
      }

      // 3b. 查询今天编辑的倒计时
      final editedCountdowns = await db.query(
        'countdowns',
        where: 'is_deleted = 0 AND is_completed = 0 AND updated_at >= ? AND updated_at < ? AND updated_at > created_at',
        whereArgs: [startOfDayMs, endOfDayMs],
      );

      for (var row in editedCountdowns) {
        final updatedAt = row['updated_at'] as int?;
        if (updatedAt != null) {
          events.add(TimelineEvent(
            id: 'cd_edit_${row['uuid']}',
            timestamp: DateTime.fromMillisecondsSinceEpoch(updatedAt),
            type: TimelineEventType.countdownEdited,
            title: '编辑倒计时',
            subtitle: row['title'] as String? ?? '',
          ));
        }
      }

      // 3c. 查询今天完成的倒计时
      final completedCountdowns = await db.query(
        'countdowns',
        where: 'is_deleted = 0 AND is_completed = 1 AND updated_at >= ? AND updated_at < ?',
        whereArgs: [startOfDayMs, endOfDayMs],
      );

      for (var row in completedCountdowns) {
        final updatedAt = row['updated_at'] as int?;
        if (updatedAt != null) {
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

      // 5. 课程 (开始 & 结束) - 使用 CourseService 以应用放假/调休规则
      final dayStr = DateFormat('yyyy-MM-dd').format(day);
      final courses = (await CourseService.getAllCourses(username))
          .where((course) => course.date == dayStr)
          .toList();

      final seenCourses = <String>{};
      for (var course in courses) {
        final courseName = course.courseName;
        final startTimeInt = course.startTime;
        
        // 去重：同一天同一个名称和开始时间只显示一次
        final dedupKey = '${courseName}_$startTimeInt';
        if (seenCourses.contains(dedupKey)) continue;
        seenCourses.add(dedupKey);

        final roomName = course.roomName;
        final endTimeInt = course.endTime;
        
        final startTime = DateTime(day.year, day.month, day.day, startTimeInt ~/ 100, startTimeInt % 100);
        final endTime = DateTime(day.year, day.month, day.day, endTimeInt ~/ 100, endTimeInt % 100);

        events.add(TimelineEvent(
          id: 'course_start_${course.uuid}_$dayStr',
          timestamp: startTime,
          type: TimelineEventType.courseStart,
          title: '上课时间',
          subtitle: '$courseName${roomName.isNotEmpty ? ' @ $roomName' : ''}',
        ));

        events.add(TimelineEvent(
          id: 'course_end_${course.uuid}_$dayStr',
          timestamp: endTime,
          type: TimelineEventType.courseEnd,
          title: '下课时间',
          subtitle: courseName,
        ));
      }
      
    } catch (e) {
      debugPrint('❌ TimelineService.getEventsForDay error: $e');
    }

    // 排序：按时间倒序（最新优先）
    events.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return events;
  }

  Future<TimelineSummary> getTodaySummary(String username) => getSummaryForDay(username, DateTime.now());

  Future<TimelineSummary> getSummaryForDay(String username, DateTime day) async {
    // 确保 day 是整日期（无时间部分）
    final startOfDay = DateTime(day.year, day.month, day.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));
    final startOfDayMs = startOfDay.millisecondsSinceEpoch;
    final endOfDayMs = endOfDay.millisecondsSinceEpoch;
    
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final isToday = startOfDay.isAtSameMomentAs(today);
    final currentHHMM = isToday ? now.hour * 100 + now.minute : 2359;
    final dayStr = DateFormat('yyyy-MM-dd').format(day);

    final db = await DatabaseHelper.instance.database;

    int searchCount = 0;
    DateTime? lastSearchTime;
    int todoCreated = 0;
    int todoEdited = 0;
    int todoCompleted = 0;
    int countdownCreated = 0;
    int countdownEdited = 0;
    int countdownCompleted = 0;
    List<String> attendedCourses = [];
    int pomodoroCount = 0;
    int longestPomoSecs = 0;

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

      // 2. 待办 - 分开统计新增/编辑/完成
      final createdTodos = await db.query(
        'todos',
        where: 'is_deleted = 0 AND created_at >= ? AND created_at < ?',
        whereArgs: [startOfDayMs, endOfDayMs],
      );
      todoCreated = createdTodos.length;

      final editedTodos = await db.query(
        'todos',
        where: 'is_deleted = 0 AND is_completed = 0 AND updated_at >= ? AND updated_at < ? AND updated_at > created_at',
        whereArgs: [startOfDayMs, endOfDayMs],
      );
      todoEdited = editedTodos.length;

      final completedTodos = await db.query(
        'todos',
        where: 'is_deleted = 0 AND is_completed = 1 AND updated_at >= ? AND updated_at < ?',
        whereArgs: [startOfDayMs, endOfDayMs],
      );
      todoCompleted = completedTodos.length;

      // 3. 倒计时 - 分开统计新增/编辑/完成
      final createdCds = await db.query(
        'countdowns',
        where: 'is_deleted = 0 AND created_at >= ? AND created_at < ?',
        whereArgs: [startOfDayMs, endOfDayMs],
      );
      countdownCreated = createdCds.length;

      final editedCds = await db.query(
        'countdowns',
        where: 'is_deleted = 0 AND is_completed = 0 AND updated_at >= ? AND updated_at < ? AND updated_at > created_at',
        whereArgs: [startOfDayMs, endOfDayMs],
      );
      countdownEdited = editedCds.length;

      final completedCds = await db.query(
        'countdowns',
        where: 'is_deleted = 0 AND is_completed = 1 AND updated_at >= ? AND updated_at < ?',
        whereArgs: [startOfDayMs, endOfDayMs],
      );
      countdownCompleted = completedCds.length;

      // 4. 课程 (已上的) - 使用调整后的课表
      final courses = (await CourseService.getAllCourses(username))
          .where((course) =>
              course.date == dayStr && course.endTime < currentHHMM)
          .toList();
      // 使用 Set 去重
      attendedCourses = courses.map((e) => e.courseName).toSet().toList();

      // 5. 番茄钟 (完成次数 - 包括正常完成和基本完成的中断)
      final poms = await db.query(
        'pomodoro_records',
        where: "is_deleted = 0 AND start_time >= ? AND start_time < ?",
        whereArgs: [startOfDayMs, endOfDayMs],
      );
      for (var row in poms) {
        final status = row['status'] as String?;
        final actualSecs = row['actual_duration'] as int? ?? 0;
        
        if (status == 'completed') {
          pomodoroCount++;
          if (actualSecs > longestPomoSecs) longestPomoSecs = actualSecs;
        } else if (status == 'interrupted') {
          final plannedSecs = row['planned_duration'] as int? ?? 0;
          if (plannedSecs == 0 || actualSecs >= plannedSecs * 0.9) {
            pomodoroCount++;
            if (actualSecs > longestPomoSecs) longestPomoSecs = actualSecs;
          }
        }
      }

    } catch (e) {
      debugPrint('❌ getSummaryForDay error: $e');
    }

    return TimelineSummary(
      searchCount: searchCount,
      lastSearchTime: lastSearchTime,
      todoCreatedCount: todoCreated,
      todoEditedCount: todoEdited,
      todoCompletedCount: todoCompleted,
      countdownCreatedCount: countdownCreated,
      countdownEditedCount: countdownEdited,
      countdownCompletedCount: countdownCompleted,
      attendedCourses: attendedCourses,
      pomodoroCount: pomodoroCount,
      longestPomodoroMinutes: longestPomoSecs ~/ 60,
      latestTodoCompletionTime: todoCompleted > 0 ? DateTime.fromMillisecondsSinceEpoch(
        (await db.rawQuery('SELECT MAX(updated_at) as m FROM todos WHERE is_deleted=0 AND is_completed=1 AND updated_at >= ? AND updated_at < ?', [startOfDayMs, endOfDayMs])).first['m'] as int? ?? 0
      ) : null,
    );
  }

  Future<TimelineSummary> getSummaryForRange(String username, DateTime start, DateTime end) async {
    final startMs = start.millisecondsSinceEpoch;
    final endMs = end.millisecondsSinceEpoch;
    
    final db = await DatabaseHelper.instance.database;

    try {
      // 1. Search
      final searches = await db.rawQuery(
        'SELECT COUNT(*) as count, MAX(timestamp) as last FROM search_history WHERE timestamp >= ? AND timestamp < ?',
        [startMs, endMs],
      );
      final searchCount = searches.first['count'] as int? ?? 0;
      final lastSearchTs = searches.first['last'] as int?;

      // 2. Todos
      final todoStats = await db.rawQuery(
        'SELECT '
        'COUNT(CASE WHEN created_at >= ? AND created_at < ? THEN 1 END) as created, '
        'COUNT(CASE WHEN is_completed = 1 AND updated_at >= ? AND updated_at < ? THEN 1 END) as completed '
        'FROM todos WHERE is_deleted = 0',
        [startMs, endMs, startMs, endMs],
      );
      
      // 3. Countdowns
      final cdStats = await db.rawQuery(
        'SELECT '
        'COUNT(CASE WHEN created_at >= ? AND created_at < ? THEN 1 END) as created, '
        'COUNT(CASE WHEN is_completed = 1 AND updated_at >= ? AND updated_at < ? THEN 1 END) as completed '
        'FROM countdowns WHERE is_deleted = 0',
        [startMs, endMs, startMs, endMs],
      );

      // 4. Pomodoro
      final pomoStats = await db.rawQuery(
        'SELECT uuid, todo_title, actual_duration, start_time FROM pomodoro_records '
        'WHERE is_deleted = 0 AND start_time >= ? AND start_time < ? AND '
        '(status = "completed" OR (status = "interrupted" AND actual_duration >= planned_duration * 0.9)) '
        'ORDER BY actual_duration DESC LIMIT 1',
        [startMs, endMs],
      );

      // 5. Highlights - Latest Completion
      final latestTodoStats = await db.rawQuery(
        'SELECT content, updated_at FROM todos '
        'WHERE is_deleted = 0 AND is_completed = 1 AND updated_at >= ? AND updated_at < ? '
        'ORDER BY updated_at DESC LIMIT 1',
        [startMs, endMs],
      );

      // 6. Highlights - Most Productive Day
      final productivity = await db.rawQuery(
        'SELECT strftime("%Y-%m-%d", datetime(start_time / 1000, "unixepoch", "localtime")) as day, '
        'SUM(actual_duration) as total_dur FROM pomodoro_records '
        'WHERE is_deleted = 0 AND start_time >= ? AND start_time < ? '
        'GROUP BY day ORDER BY total_dur DESC LIMIT 1',
        [startMs, endMs],
      );
      
      DateTime? bestDay;
      int bestDayMinutes = 0;
      int bestDayCompleted = 0;
      
      if (productivity.isNotEmpty && productivity.first['day'] != null) {
        final dayStr = productivity.first['day'] as String;
        bestDay = DateFormat('yyyy-MM-dd').parse(dayStr);
        bestDayMinutes = (productivity.first['total_dur'] as int? ?? 0) ~/ 60;
        
        // Find completions on that day
        final dayStart = bestDay.millisecondsSinceEpoch;
        final dayEnd = bestDay.add(const Duration(days: 1)).millisecondsSinceEpoch;
        
        final dayCompletions = await db.rawQuery(
          'SELECT (SELECT COUNT(*) FROM todos WHERE is_deleted=0 AND is_completed=1 AND updated_at >= ? AND updated_at < ?) + '
          '(SELECT COUNT(*) FROM countdowns WHERE is_deleted=0 AND is_completed=1 AND updated_at >= ? AND updated_at < ?) as c',
          [dayStart, dayEnd, dayStart, dayEnd],
        );
        bestDayCompleted = dayCompletions.first['c'] as int? ?? 0;
      }

      final hasPomo = pomoStats.isNotEmpty;
      final hasTodo = latestTodoStats.isNotEmpty;

      return TimelineSummary(
        searchCount: searchCount,
        lastSearchTime: lastSearchTs != null ? DateTime.fromMillisecondsSinceEpoch(lastSearchTs) : null,
        todoCreatedCount: todoStats.first['created'] as int? ?? 0,
        todoEditedCount: 0,
        todoCompletedCount: todoStats.first['completed'] as int? ?? 0,
        countdownCreatedCount: cdStats.first['created'] as int? ?? 0,
        countdownEditedCount: 0,
        countdownCompletedCount: cdStats.first['completed'] as int? ?? 0,
        attendedCourses: [],
        pomodoroCount: (await db.rawQuery('SELECT COUNT(*) as c FROM pomodoro_records WHERE is_deleted=0 AND start_time >= ? AND start_time < ?', [startMs, endMs])).first['c'] as int? ?? 0,
        longestPomodoroMinutes: hasPomo ? (pomoStats.first['actual_duration'] as int? ?? 0) ~/ 60 : 0,
        longestPomodoroTitle: hasPomo ? (pomoStats.first['todo_title'] as String? ?? '无题') : null,
        longestPomodoroDate: hasPomo ? DateTime.fromMillisecondsSinceEpoch(pomoStats.first['start_time'] as int) : null,
        latestTodoCompletionTime: hasTodo ? DateTime.fromMillisecondsSinceEpoch(latestTodoStats.first['updated_at'] as int) : null,
        latestTodoTitle: hasTodo ? (latestTodoStats.first['content'] as String? ?? '未命名任务') : null,
        mostProductiveDay: bestDay,
        mostProductiveDayDurationMinutes: bestDayMinutes,
        mostProductiveDayCompletedCount: bestDayCompleted,
      );
    } catch (e) {
      debugPrint('❌ getSummaryForRange error: $e');
      return TimelineSummary(
        searchCount: 0,
        todoCreatedCount: 0,
        todoEditedCount: 0,
        todoCompletedCount: 0,
        countdownCreatedCount: 0,
        countdownEditedCount: 0,
        countdownCompletedCount: 0,
        attendedCourses: [],
        pomodoroCount: 0,
      );
    }
  }
}

class TimelineSummary {
  final int searchCount;
  final DateTime? lastSearchTime;
  final int todoCreatedCount;
  final int todoEditedCount;
  final int todoCompletedCount;
  final int countdownCreatedCount;
  final int countdownEditedCount;
  final int countdownCompletedCount;
  final List<String> attendedCourses;
  final int pomodoroCount;
  
  // Highlights
  final int longestPomodoroMinutes;
  final String? longestPomodoroTitle;
  final DateTime? longestPomodoroDate;
  final DateTime? latestTodoCompletionTime;
  final String? latestTodoTitle;
  final DateTime? mostProductiveDay;
  final int mostProductiveDayDurationMinutes;
  final int mostProductiveDayCompletedCount;

  TimelineSummary({
    required this.searchCount,
    this.lastSearchTime,
    required this.todoCreatedCount,
    required this.todoEditedCount,
    required this.todoCompletedCount,
    required this.countdownCreatedCount,
    required this.countdownEditedCount,
    required this.countdownCompletedCount,
    required this.attendedCourses,
    required this.pomodoroCount,
    this.longestPomodoroMinutes = 0,
    this.longestPomodoroTitle,
    this.longestPomodoroDate,
    this.latestTodoCompletionTime,
    this.latestTodoTitle,
    this.mostProductiveDay,
    this.mostProductiveDayDurationMinutes = 0,
    this.mostProductiveDayCompletedCount = 0,
  });
}
