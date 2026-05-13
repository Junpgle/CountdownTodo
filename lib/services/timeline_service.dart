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

    bool hasPomo = false;
    bool hasTodo = false;
    Map<String, dynamic>? pomoStats;

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
        'GROUP BY query ORDER BY freq DESC LIMIT 5',
        [startMs, endMs],
      );
      final topQuery = topSearch.isNotEmpty ? topSearch.first['query'] as String? : null;
      final topQueries = topSearch.map((r) => {'query': r['query'], 'freq': r['freq']}).toList();

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

      final pomoTop = await db.rawQuery(
        'SELECT uuid, todo_title, actual_duration, start_time FROM ('
        'SELECT uuid, todo_title, actual_duration, start_time FROM pomodoro_records '
        'WHERE is_deleted = 0 AND start_time >= ? AND start_time < ? AND '
        '(status = \'completed\' OR (status = \'interrupted\' AND actual_duration >= planned_duration * 0.9)) '
        'UNION ALL '
        'SELECT uuid, title as todo_title, (end_time - start_time) / 1000 as actual_duration, start_time FROM time_logs '
        'WHERE is_deleted = 0 AND start_time >= ? AND start_time < ?'
        ') ORDER BY actual_duration DESC LIMIT 5',
        [startMs, endMs, startMs, endMs],
      );
      hasPomo = pomoTop.isNotEmpty;
      pomoStats = hasPomo ? pomoTop.first : null;

      // 5. Highlights - Latest Wall-clock Completion (Handles over-midnight/all-nighters)
      final latestTodoStats = await db.rawQuery(
        'SELECT content, updated_at, strftime(\'%H:%M\', datetime(updated_at / 1000, \'unixepoch\', \'localtime\')) as wall_time '
        'FROM todos '
        'WHERE is_deleted = 0 AND is_completed = 1 AND updated_at >= ? AND updated_at < ? '
        'ORDER BY updated_at DESC LIMIT 5',
        [startMs, endMs],
      );
      hasTodo = latestTodoStats.isNotEmpty;
      final topCompleted = latestTodoStats.map((r) => {'title': r['content'], 'time': r['updated_at']}).toList();

      // 6. Highlights - Daily Trend for Sparkline
      final trendRows = await db.rawQuery(
        'SELECT day, SUM(dur) as total_dur FROM ('
        'SELECT strftime(\'%Y-%m-%d\', datetime(start_time / 1000, \'unixepoch\', \'localtime\')) as day, actual_duration as dur FROM pomodoro_records '
        'WHERE is_deleted = 0 AND start_time >= ? AND start_time < ? '
        'UNION ALL '
        'SELECT strftime(\'%Y-%m-%d\', datetime(start_time / 1000, \'unixepoch\', \'localtime\')) as day, (end_time - start_time) / 1000 as dur FROM time_logs '
        'WHERE is_deleted = 0 AND start_time >= ? AND start_time < ?'
        ') GROUP BY day ORDER BY day ASC',
        [startMs, endMs, startMs, endMs],
      );
      List<double> dailyTrend = trendRows.map((r) => (r['total_dur'] as num? ?? 0).toDouble() / 60).toList();

      // 6b. Top Productive Days
      DateTime? bestDay;
      int bestDayMinutes = 0;
      int bestDayCompleted = 0;
      List<Map<String, dynamic>> topDays = [];
      
      if (trendRows.isNotEmpty) {
        var sortedTrend = List.from(trendRows)..sort((a, b) => (b['total_dur'] as num? ?? 0).compareTo(a['total_dur'] as num? ?? 0));
        
        for (var i = 0; i < sortedTrend.length && i < 5; i++) {
          final row = sortedTrend[i];
          final dayStr = row['day'] as String;
          final d = DateFormat('yyyy-MM-dd').parse(dayStr);
          final mins = (row['total_dur'] as num? ?? 0).toInt() ~/ 60;
          
          if (i == 0) {
            bestDay = d;
            bestDayMinutes = mins;
          }
          topDays.add({'date': d, 'minutes': mins});
        }
        
        if (bestDay != null) {
          final dayStart = bestDay!.millisecondsSinceEpoch;
          final dayEnd = bestDay!.add(const Duration(days: 1)).millisecondsSinceEpoch;
          final dayCompletions = await db.rawQuery(
            'SELECT (SELECT COUNT(*) FROM todos WHERE is_deleted=0 AND is_completed=1 AND updated_at >= ? AND updated_at < ?) + '
            '(SELECT COUNT(*) FROM countdowns WHERE is_deleted=0 AND is_completed=1 AND updated_at >= ? AND updated_at < ?) as c',
            [dayStart, dayEnd, dayStart, dayEnd],
          );
          bestDayCompleted = dayCompletions.first['c'] as int? ?? 0;
        }
      }

      final hourData = await db.rawQuery(
        'SELECT strftime(\'%H\', datetime(ts / 1000, \'unixepoch\', \'localtime\')) as hr, COUNT(*) as c '
        'FROM ('
        'SELECT updated_at as ts FROM todos WHERE updated_at >= ? AND updated_at < ? AND is_completed = 1 '
        'UNION ALL SELECT start_time as ts FROM pomodoro_records WHERE start_time >= ? AND start_time < ? AND is_deleted = 0 '
        'UNION ALL SELECT start_time as ts FROM time_logs WHERE start_time >= ? AND start_time < ? AND is_deleted = 0'
        ') GROUP BY hr',
        [startMs, endMs, startMs, endMs, startMs, endMs],
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
        'SELECT dur FROM ('
        'SELECT actual_duration as dur FROM pomodoro_records WHERE is_deleted = 0 AND start_time >= ? AND start_time < ? '
        'UNION ALL '
        'SELECT (end_time - start_time) / 1000 as dur FROM time_logs WHERE is_deleted = 0 AND start_time >= ? AND start_time < ?'
        ')',
        [startMs, endMs, startMs, endMs],
      );
      int totalSecs = 0;
      int deepWork = 0;
      for (var row in pomoAll) {
        final dur = row['dur'] as int;
        totalSecs += dur;
        if (dur >= 45 * 60) deepWork++;
      }
      final avgPomo = pomoAll.isNotEmpty ? (totalSecs / pomoAll.length) / 60 : 0.0;

      // 9. Task & Subject Distribution (Combine Todos & Pomodoros for better signal)
      final List<String> allTitles = [];
      
      final todoRows = await db.query(
        'todos',
        columns: ['content'],
        where: 'is_deleted = 0 AND is_completed = 1 AND updated_at >= ? AND updated_at < ?',
        whereArgs: [startMs, endMs],
      );
      allTitles.addAll(todoRows.map((r) => (r['content'] as String? ?? '')));

      final pomoRows = await db.query(
        'pomodoro_records',
        columns: ['todo_title'],
        where: 'is_deleted = 0 AND start_time >= ? AND start_time < ?',
        whereArgs: [startMs, endMs],
      );
      allTitles.addAll(pomoRows.map((r) => (r['todo_title'] as String? ?? '')));

      final logRows = await db.query(
        'time_logs',
        columns: ['title'],
        where: 'is_deleted = 0 AND start_time >= ? AND start_time < ?',
        whereArgs: [startMs, endMs],
      );
      allTitles.addAll(logRows.map((r) => (r['title'] as String? ?? '')));
      
      final int totalItems = allTitles.length;
      int homework = 0;
      int exam = 0;
      Map<String, int> subjectCounts = {};
      Map<String, int> wordFrequency = {}; 

      final Map<String, List<String>> categories = {
        '系统/硬件': ['计组', 'cpu', 'vivada', 'verilog', 'fpga', '汇编', '操作系统', 'os', 'linux', '内核', '驱动', '硬件', '单片机', '嵌入式', 'arm', 'riscv'],
        '代码/算法': ['代码', 'coding', '算法', 'leetcode', 'c++', 'python', 'java', '软件', '开发', '调试', 'debug', '编程', '程序员', 'git', 'github'],
        '科研/论文': ['科研', '论文', 'paper', '实验', '项目', '调研', '开题', '结题', '报告', 'ppt', '研讨', '文献', '笔记', '组会', '学术', '发表'],
        '数学/计算': ['高数', '线代', '离散', '概率', '数学', '计算', '分析', '建模', '方程', '代数', '几何', '复变', '统计', '逻辑'],
        '物理/信号': ['物理', '大物', '信号', '系统', '电路', '电子', '电磁', '光学', '力学', '热学', '验收', '答辩'],
        '外语/考试': ['英语', '词汇', '单词', '阅读', '听力', '写作', '雅思', '托福', 'gre', '四级', '六级', '翻译', '口语', '考研', '考证'],
        '人文/社科': ['思政', '毛泽东', '文化', '戏剧', '哲学', '历史', '艺术', '社会', '心理', '法律', '经济', '管理'],
        '体育/健身': ['体育', '锻炼', '跑步', '健身', '篮球', '足球', '游泳', '散步', '拉伸', '训练', '有氧', '力量', '减脂'],
      };

      for (var title in allTitles) {
        final sub = title.toLowerCase();
        if (sub.trim().isEmpty) continue;

        // Homework/Exam tagging
        if (RegExp(r'作业|练习|刷题|homework|lab|实验|课后').hasMatch(sub)) homework++;
        if (RegExp(r'考试|测验|考证|期中|期末|exam|test|背诵|复习').hasMatch(sub)) exam++;
        
        // Word frequency (Split by common delimiters)
        final words = sub.split(RegExp(r'[\s、，,。（）()\[\]\-—_]'));
        for (var w in words) {
          if (w.length > 1 && !RegExp(r'的|了|和|是|就|都|而|及|与|着|或|个|项|次').hasMatch(w)) {
            wordFrequency[w] = (wordFrequency[w] ?? 0) + 1;
          }
        }

        bool matched = false;
        for (var entry in categories.entries) {
          if (entry.value.any((k) => sub.contains(k))) {
            subjectCounts[entry.key] = (subjectCounts[entry.key] ?? 0) + 1;
            matched = true;
            break;
          }
        }
        if (!matched) {
          // If not matched, we will try to use the top frequent word later
          subjectCounts['其他'] = (subjectCounts['其他'] ?? 0) + 1;
        }
      }

      final hwRatio = totalItems > 0 ? (homework / totalItems) : 0.0;
      final exRatio = totalItems > 0 ? (exam / totalItems) : 0.0;
      
      // Calculate Exam Subject Distribution
      Map<String, int> examSubjectDist = {};
      for (var title in allTitles) {
        final sub = title.toLowerCase();
        if (RegExp(r'考试|测验|考证|期中|期末|exam|test|背诵|复习').hasMatch(sub)) {
           bool matched = false;
           for (var entry in categories.entries) {
             if (entry.value.any((k) => sub.contains(k))) {
               examSubjectDist[entry.key] = (examSubjectDist[entry.key] ?? 0) + 1;
               matched = true;
               break;
             }
           }
           if (!matched) examSubjectDist['其他'] = (examSubjectDist['其他'] ?? 0) + 1;
        }
      }

      // Dynamic Category Elevation: If 'Other' has many items, extract common keywords
      final sortedWords = wordFrequency.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
      
      Map<String, double> subjectDist = {};
      int othersCount = subjectCounts['其他'] ?? 0;
      
      // Calculate known categories first
      subjectCounts.forEach((k, v) {
        if (k != '其他' && totalItems > 0) {
          subjectDist[k] = v / totalItems;
        }
      });

      // Distribute 'Other' into dynamic keywords if possible
      if (othersCount > 0 && totalItems > 0) {
        int distributed = 0;
        for (var wordEntry in sortedWords) {
          // If a word is frequent and NOT part of existing category keywords
          bool isExisting = false;
          for (var list in categories.values) {
            if (list.contains(wordEntry.key)) { isExisting = true; break; }
          }
          
          if (!isExisting && wordEntry.value > 1) {
            final dynamicLabel = wordEntry.key.toUpperCase();
            subjectDist[dynamicLabel] = (subjectDist[dynamicLabel] ?? 0) + (wordEntry.value / totalItems);
            distributed += wordEntry.value;
            if (subjectDist.length >= 8) break; // Limit categories for UI
          }
        }
        
        if (distributed < othersCount) {
          subjectDist['其他'] = (othersCount - distributed) / totalItems;
        }
      }

      // 10. Actual Data Coverage Range
      final rangeData = await db.rawQuery(
        'SELECT MIN(ts) as first_ts, MAX(ts) as last_ts FROM ('
        'SELECT created_at as ts FROM todos WHERE created_at >= ? AND created_at < ? AND is_deleted = 0 '
        'UNION ALL SELECT start_time as ts FROM pomodoro_records WHERE start_time >= ? AND start_time < ? AND is_deleted = 0 '
        'UNION ALL SELECT start_time as ts FROM time_logs WHERE start_time >= ? AND start_time < ? AND is_deleted = 0 '
        'UNION ALL SELECT timestamp as ts FROM search_history WHERE timestamp >= ? AND timestamp < ?'
        ')',
        [startMs, endMs, startMs, endMs, startMs, endMs, startMs, endMs],
      );
      
      DateTime? actualStart;
      DateTime? actualEnd;
      if (rangeData.isNotEmpty && rangeData.first['first_ts'] != null) {
        actualStart = DateTime.fromMillisecondsSinceEpoch(rangeData.first['first_ts'] as int);
        actualEnd = DateTime.fromMillisecondsSinceEpoch(rangeData.first['last_ts'] as int);
      }


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
        longestPomodoroMinutes: hasPomo ? (pomoStats!['actual_duration'] as int? ?? 0) ~/ 60 : 0,
        longestPomodoroTitle: hasPomo ? (pomoStats!['todo_title'] as String? ?? '无题') : null,
        longestPomodoroDate: hasPomo && pomoStats!['start_time'] != null 
            ? DateTime.fromMillisecondsSinceEpoch(pomoStats!['start_time'] as int) : null,
        latestTodoCompletionTime: hasTodo && latestTodoStats.first['updated_at'] != null 
            ? DateTime.fromMillisecondsSinceEpoch(latestTodoStats.first['updated_at'] as int) : null,
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
        actualStartTime: actualStart,
        actualEndTime: actualEnd,
        dailyTrend: dailyTrend,
        topFocusSessions: pomoTop,
        topProductiveDays: topDays,
        topSearchQueries: topQueries,
        topCompletedTodos: topCompleted,
        examSubjectDist: examSubjectDist,
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
  final Map<String, int> examSubjectDist;
  final List<Map<String, dynamic>> topCompletedTodos;
  final List<int> hourlyDistribution; // Counts for 0-23 hours
  final DateTime? actualStartTime;
  final DateTime? actualEndTime;
  final List<double> dailyTrend; // Duration per day (minutes), normalized or raw
  final List<Map<String, dynamic>> topFocusSessions;
  final List<Map<String, dynamic>> topProductiveDays;
  final List<Map<String, dynamic>> topSearchQueries;

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
    this.dailyTrend = const [],
    this.topFocusSessions = const [],
    this.topProductiveDays = const [],
    this.topSearchQueries = const [],
    this.topCompletedTodos = const [],
    this.examSubjectDist = const {},
  });

  final Map<String, double> subjectDistribution;
  final int examPrepCount;
}
