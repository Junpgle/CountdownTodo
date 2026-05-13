import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:sqflite/sqflite.dart';
import 'database_helper.dart';
import 'course_service.dart';
import 'pomodoro_service.dart';
import '../models.dart';

class TimelineService {
  static final TimelineService instance = TimelineService._();
  TimelineService._();

  Future<List<TimelineEvent>> getEventsForDay(String username, DateTime date) async {
    final db = await DatabaseHelper.instance.database;
    final startOfDay = DateTime(date.year, date.month, date.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));
    final startOfDayMs = startOfDay.millisecondsSinceEpoch;
    final endOfDayMs = endOfDay.millisecondsSinceEpoch;
    final dayStr = DateFormat('yyyy-MM-dd').format(date);

    List<TimelineEvent> events = [];

    try {
      // 1. 搜索历史
      final searches = await db.query(
        'search_history',
        where: 'timestamp >= ? AND timestamp < ?',
        whereArgs: [startOfDayMs, endOfDayMs],
      );
      for (var row in searches) {
        events.add(TimelineEvent(
          id: 'search_${row['id']}',
          timestamp: DateTime.fromMillisecondsSinceEpoch(row['timestamp'] as int),
          type: TimelineEventType.searchQuery,
          title: '知识检索',
          subtitle: row['query'] as String? ?? '',
        ));
      }

      // 2. 待办事项
      final createdTodos = await db.query(
        'todos',
        where: 'is_deleted = 0 AND created_at >= ? AND created_at < ?',
        whereArgs: [startOfDayMs, endOfDayMs],
      );
      for (var row in createdTodos) {
        final title = row['content'] as String? ?? '';
        events.add(TimelineEvent(
          id: 'todo_create_${row['uuid']}',
          timestamp: DateTime.fromMillisecondsSinceEpoch(row['created_at'] as int),
          type: TimelineEventType.todoCreated,
          title: '新增待办',
          subtitle: title,
        ));
      }

      final completedTodos = await db.query(
        'todos',
        where: 'is_deleted = 0 AND is_completed = 1 AND updated_at >= ? AND updated_at < ?',
        whereArgs: [startOfDayMs, endOfDayMs],
      );
      for (var row in completedTodos) {
        final title = row['content'] as String? ?? '';
        final updatedAt = row['updated_at'] as int;
        events.add(TimelineEvent(
          id: 'todo_complete_${row['uuid']}',
          timestamp: DateTime.fromMillisecondsSinceEpoch(updatedAt),
          type: TimelineEventType.todoCompleted,
          title: '完成待办',
          subtitle: title,
        ));
      }

      // 3. 课程
      final courses = await CourseService.getAllCourses(username);
      for (var course in courses) {
        if (course.date == dayStr) {
          // startTime is int (HHMM)
          final hour = course.startTime ~/ 100;
          final minute = course.startTime % 100;
          final courseStart = DateTime(date.year, date.month, date.day, hour, minute);
          
          if (courseStart.millisecondsSinceEpoch >= startOfDayMs && 
              courseStart.millisecondsSinceEpoch < endOfDayMs) {
            events.add(TimelineEvent(
              id: 'course_${course.uuid}_${course.startTime}',
              timestamp: courseStart,
              type: TimelineEventType.courseStart,
              title: '步入课堂',
              subtitle: course.courseName,
            ));
          }
        }
      }

      // 4. 番茄钟
      final poms = await db.query(
        'pomodoro_records',
        where: 'is_deleted = 0 AND start_time >= ? AND start_time < ?',
        whereArgs: [startOfDayMs, endOfDayMs],
      );
      for (var row in poms) {
        final startTime = row['start_time'] as int;
        final actualDur = row['actual_duration'] as int? ?? 0;
        final status = row['status'] as String?;
        final title = row['todo_title'] as String? ?? '无题专注';

        events.add(TimelineEvent(
          id: 'pomo_start_${row['uuid']}',
          timestamp: DateTime.fromMillisecondsSinceEpoch(startTime),
          type: TimelineEventType.pomodoroStart,
          title: '开始专注',
          subtitle: title,
        ));

        if (status == 'completed' || (status == 'interrupted' && actualDur > 0)) {
          events.add(TimelineEvent(
            id: 'pomo_end_${row['uuid']}',
            timestamp: DateTime.fromMillisecondsSinceEpoch(startTime + actualDur * 1000),
            type: TimelineEventType.pomodoroEnd,
            title: status == 'completed' ? '收获专注果实' : '专注中断',
            subtitle: '$title (${actualDur ~/ 60}分钟)',
          ));
        }
      }

    } catch (e) {
      debugPrint('❌ getEventsForDay error: $e');
    }

    events.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    return events;
  }

  Future<TimelineSummary> getTodaySummary(String username) async {
    return getSummaryForDay(username, DateTime.now());
  }

  Future<TimelineSummary> getSummaryForDay(String username, DateTime date) async {
    final startOfDay = DateTime(date.year, date.month, date.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));
    return getSummaryForRange(username, startOfDay, endOfDay);
  }

  Future<TimelineSummary> getSummaryForRange(String username, DateTime start, DateTime end) async {
    final db = await DatabaseHelper.instance.database;
    final startMs = start.millisecondsSinceEpoch;
    final endMs = end.millisecondsSinceEpoch;

    try {
      // 1. Search
      final searchStats = await db.rawQuery(
        'SELECT COUNT(*) as count, MAX(timestamp) as last_ts FROM search_history '
        'WHERE timestamp >= ? AND timestamp < ?',
        [startMs, endMs],
      );
      final searchCount = searchStats.first['count'] as int? ?? 0;
      final lastSearchTs = searchStats.first['last_ts'] as int?;
      
      final topSearch = await db.rawQuery(
        'SELECT query, COUNT(*) as freq FROM search_history '
        'WHERE timestamp >= ? AND timestamp < ? '
        'GROUP BY query ORDER BY freq DESC LIMIT 1',
        [startMs, endMs],
      );
      final topQuery = topSearch.isNotEmpty ? topSearch.first['query'] as String? : null;

      // 2. Todos
      final todoStats = await db.rawQuery(
        'SELECT COUNT(*) as created, SUM(CASE WHEN is_completed = 1 THEN 1 ELSE 0 END) as completed FROM todos '
        'WHERE is_deleted = 0 AND created_at >= ? AND created_at < ?',
        [startMs, endMs],
      );

      // 3. Countdowns
      final cdStats = await db.rawQuery(
        'SELECT COUNT(*) as created, SUM(CASE WHEN is_completed = 1 THEN 1 ELSE 0 END) as completed FROM countdowns '
        'WHERE is_deleted = 0 AND created_at >= ? AND created_at < ?',
        [startMs, endMs],
      );

      // 4. Pomodoro
      final pomoStats = await db.rawQuery(
        'SELECT uuid, todo_title, actual_duration, start_time FROM pomodoro_records '
        'WHERE is_deleted = 0 AND start_time >= ? AND start_time < ? AND '
        '(status = \'completed\' OR (status = \'interrupted\' AND actual_duration >= planned_duration * 0.9)) '
        'ORDER BY actual_duration DESC LIMIT 1',
        [startMs, endMs],
      );

      // 5. Highlights - Latest Wall-clock Completion (Handles over-midnight/all-nighters)
      final latestTodoStats = await db.rawQuery(
        'SELECT content, updated_at, strftime(\'%H:%M\', datetime(updated_at / 1000, \'unixepoch\', \'localtime\')) as wall_time '
        'FROM todos '
        'WHERE is_deleted = 0 AND is_completed = 1 AND updated_at >= ? AND updated_at < ? '
        'ORDER BY CASE WHEN strftime(\'%H\', datetime(updated_at / 1000, \'unixepoch\', \'localtime\')) < \'05\' THEN 1 ELSE 0 END DESC, wall_time DESC LIMIT 1',
        [startMs, endMs],
      );

      // 6. Highlights - Most Productive Day
      final productivity = await db.rawQuery(
        'SELECT strftime(\'%Y-%m-%d\', datetime(start_time / 1000, \'unixepoch\', \'localtime\')) as day, '
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
        
        final dayStart = bestDay.millisecondsSinceEpoch;
        final dayEnd = bestDay.add(const Duration(days: 1)).millisecondsSinceEpoch;
        final dayCompletions = await db.rawQuery(
          'SELECT (SELECT COUNT(*) FROM todos WHERE is_deleted=0 AND is_completed=1 AND updated_at >= ? AND updated_at < ?) + '
          '(SELECT COUNT(*) FROM countdowns WHERE is_deleted=0 AND is_completed=1 AND updated_at >= ? AND updated_at < ?) as c',
          [dayStart, dayEnd, dayStart, dayEnd],
        );
        bestDayCompleted = dayCompletions.first['c'] as int? ?? 0;
      }

      final hourData = await db.rawQuery(
        'SELECT strftime(\'%H\', datetime(ts / 1000, \'unixepoch\', \'localtime\')) as hr, COUNT(*) as c '
        'FROM (SELECT updated_at as ts FROM todos WHERE updated_at >= ? AND updated_at < ? AND is_completed = 1 '
        'UNION ALL SELECT start_time as ts FROM pomodoro_records WHERE start_time >= ? AND start_time < ?) '
        'GROUP BY hr',
        [startMs, endMs, startMs, endMs],
      );
      
      List<int> hourlyDist = List.filled(24, 0);
      int peakHr = 0;
      int maxC = 0;
      for (var row in hourData) {
        final hr = int.parse(row['hr'] as String);
        final count = row['c'] as int;
        hourlyDist[hr] = count;
        if (count > maxC) {
          maxC = count;
          peakHr = hr;
        }
      }

      // 8. Focus Depth & Avg
      final pomoAll = await db.rawQuery(
        'SELECT actual_duration FROM pomodoro_records '
        'WHERE is_deleted = 0 AND start_time >= ? AND start_time < ? AND '
        '(status = \'completed\' OR (status = \'interrupted\' AND actual_duration >= planned_duration * 0.9))',
        [startMs, endMs],
      );
      int totalSecs = 0;
      int deepWork = 0;
      for (var row in pomoAll) {
        final dur = row['actual_duration'] as int;
        totalSecs += dur;
        if (dur >= 45 * 60) deepWork++;
      }
      final avgPomo = pomoAll.isNotEmpty ? (totalSecs / pomoAll.length) / 60 : 0.0;

      // 9. Task & Subject Distribution (Combine Todos & Pomodoros for better signal)
      final List<String> allTitles = [];
      
      // Add Todo contents
      final todoRows = await db.query(
        'todos',
        columns: ['content'],
        where: 'is_deleted = 0 AND is_completed = 1 AND updated_at >= ? AND updated_at < ?',
        whereArgs: [startMs, endMs],
      );
      allTitles.addAll(todoRows.map((r) => (r['content'] as String? ?? '')));

      // Add Pomodoro titles (often more descriptive for 'work')
      final pomoRows = await db.query(
        'pomodoro_records',
        columns: ['todo_title'],
        where: 'is_deleted = 0 AND start_time >= ? AND start_time < ?',
        whereArgs: [startMs, endMs],
      );
      allTitles.addAll(pomoRows.map((r) => (r['todo_title'] as String? ?? '')));

      int homework = 0;
      int exam = 0;
      Map<String, int> subjectCounts = {};
      
      final Map<String, List<String>> categories = {
        '计算机/底层': ['计组', 'cpu', '代码', 'vivada', 'verilog', 'fpga', '汇编', '操作系统', 'os', 'linux', 'coding', '算法', 'leetcode', 'c++', 'python', 'java', '智能', '嵌入式', '内核', '驱动', '编译器', '调试', 'debug', '环境'],
        '物理/科研': ['物理', '大物', '实验', '科研', '论文', 'paper', '训练', '验收', '答辩', '项目', '调研', '开题', '结题', '报告', 'ppt', '研讨', '文献', '笔记', '组会'],
        '数学/基础': ['高数', '线代', '离散', '概率', '数学', '计算', '分析', '建模', '方程', '代数', '几何', '复变'],
        '人文/外语': ['英语', '词汇', '单词', '阅读', '听力', '学术', '思政', '毛泽东', '文化', '戏剧', '哲学', '历史', '写作', '雅思', '托福', 'gre'],
        '体育/素质': ['体育', '风雨', '锻炼', '跑步', '健身', '篮球', '足球', '游泳', '散步', '拉伸'],
      };

      for (var title in allTitles) {
        final sub = title.toLowerCase();
        if (sub.isEmpty) continue;

        if (sub.contains('作业') || sub.contains('练习') || sub.contains('刷题') || sub.contains('homework') || sub.contains('lab')) homework++;
        if (sub.contains('考试') || sub.contains('测验') || sub.contains('考证') || sub.contains('期中') || sub.contains('期末') || sub.contains('exam') || sub.contains('test')) exam++;
        
        bool matched = false;
        for (var entry in categories.entries) {
          if (entry.value.any((k) => sub.contains(k))) {
            subjectCounts[entry.key] = (subjectCounts[entry.key] ?? 0) + 1;
            matched = true;
            break;
          }
        }
        if (!matched) subjectCounts['其他'] = (subjectCounts['其他'] ?? 0) + 1;
      }

      final totalItems = allTitles.length;
      final hwRatio = totalItems > 0 ? (homework / totalItems) : 0.0;
      final exRatio = totalItems > 0 ? (exam / totalItems) : 0.0;
      
      Map<String, double> subjectDist = {};
      if (totalItems > 0) {
        subjectCounts.forEach((k, v) => subjectDist[k] = v / totalItems);
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
        pomodoroCount: pomoAll.length,
        longestPomodoroMinutes: hasPomo ? (pomoStats.first['actual_duration'] as int? ?? 0) ~/ 60 : 0,
        longestPomodoroTitle: hasPomo ? (pomoStats.first['todo_title'] as String? ?? '无题') : null,
        longestPomodoroDate: hasPomo ? DateTime.fromMillisecondsSinceEpoch(pomoStats.first['start_time'] as int) : null,
        latestTodoCompletionTime: hasTodo ? DateTime.fromMillisecondsSinceEpoch(latestTodoStats.first['updated_at'] as int) : null,
        latestTodoTitle: hasTodo ? (latestTodoStats.first['content'] as String? ?? '未命名任务') : null,
        mostProductiveDay: bestDay,
        mostProductiveDayDurationMinutes: bestDayMinutes,
        mostProductiveDayCompletedCount: bestDayCompleted,
        topSearchQuery: topQuery,
        peakHour: peakHr,
        avgPomodoroMinutes: avgPomo,
        deepWorkCount: deepWork,
        homeworkRatio: hwRatio,
        examRatio: exRatio,
        subjectDistribution: subjectDist,
        examPrepCount: exam,
        hourlyDistribution: hourlyDist,
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
  
  final int longestPomodoroMinutes;
  final String? longestPomodoroTitle;
  final DateTime? longestPomodoroDate;
  final DateTime? latestTodoCompletionTime;
  final String? latestTodoTitle;
  final DateTime? mostProductiveDay;
  final int mostProductiveDayDurationMinutes;
  final int mostProductiveDayCompletedCount;
  final String? topSearchQuery;
  final int peakHour; // Most active hour (0-23)
  final double avgPomodoroMinutes;
  final int deepWorkCount; // Sessions > 45 mins
  final double homeworkRatio; // % of homework tasks
  final double examRatio; // % of exam tasks
  final List<int> hourlyDistribution; // Counts for 0-23 hours
  final DateTime? actualStartTime;
  final DateTime? actualEndTime;

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
    this.topSearchQuery,
    this.peakHour = 0,
    this.avgPomodoroMinutes = 0,
    this.deepWorkCount = 0,
    this.homeworkRatio = 0,
    this.examRatio = 0,
    this.subjectDistribution = const {},
    this.examPrepCount = 0,
    this.hourlyDistribution = const [],
    this.actualStartTime,
    this.actualEndTime,
  });

  final Map<String, double> subjectDistribution;
  final int examPrepCount;
}
