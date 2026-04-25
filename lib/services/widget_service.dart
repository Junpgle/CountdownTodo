import 'package:home_widget/home_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import '../models.dart';
import '../storage_service.dart';
import 'course_service.dart';
import 'pomodoro_service.dart';

@pragma('vm:entry-point')
Future<void> widgetBackgroundCallback(Uri? uri) async {
  if (!Platform.isAndroid && !Platform.isIOS) return;
  if (uri != null && uri.scheme == 'todowidget' && uri.host == 'markdone') {
    final id = uri.pathSegments.isNotEmpty ? uri.pathSegments.first : null;
    if (id != null) {
      final prefs = await SharedPreferences.getInstance();
      final username = prefs.getString(StorageService.KEY_CURRENT_USER) ?? '';
      if (username.isNotEmpty) {
        List<TodoItem> todos = await StorageService.getTodos(username);
        bool changed = false;
        for (var t in todos) {
          if (t.id == id) {
            t.isDone = !t.isDone;
            t.markAsChanged();
            changed = true;
            break;
          }
        }
        if (changed) {
          todos.sort((a, b) => a.isDone == b.isDone ? 0 : (a.isDone ? 1 : -1));
          await StorageService.saveTodos(username, todos);
          await WidgetService.updateAllWidgetData(username, todos);
        }
      }
    }
  }
}

class WidgetService {
  static const String androidWidgetName = 'TodoWidgetProvider';
  static bool _initialized = false;
  static const int maxWidgetItems = 8;
  static Timer? _periodicTimer;

  static Future<void> dispose() async {
    _periodicTimer?.cancel();
    _periodicTimer = null;
  }

  static Future<void> init() async {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    if (_initialized) return;
    try {
      await HomeWidget.registerInteractivityCallback(widgetBackgroundCallback);
      _initialized = true;
    } catch (e) {
      print('WidgetBackground 注册失败: $e');
    }

    // 启动 15 分钟一次的周期刷新（确保在应用运行期间定期更新 widget，减少能耗）
    _periodicTimer?.cancel();
    _periodicTimer = Timer.periodic(const Duration(minutes: 15), (timer) async {
      try {
        final prefs = await SharedPreferences.getInstance();
        final username = prefs.getString(StorageService.KEY_CURRENT_USER) ?? '';
        if (username.isEmpty) return;
        final todos = await StorageService.getTodos(username);
        await WidgetService.updateAllWidgetData(username, todos);
      } catch (e) {
        print('Widget periodic refresh error: $e');
      }
    });

    // 立即触发一次更新
    try {
      final prefs = await SharedPreferences.getInstance();
      final username = prefs.getString(StorageService.KEY_CURRENT_USER) ?? '';
      if (username.isNotEmpty) {
        final todos = await StorageService.getTodos(username);
        await updateAllWidgetData(username, todos);
      }
    } catch (e) {
      print('Widget initial update error: $e');
    }
  }

  static String _getDueDateLabel(DateTime? dueDate) {
    if (dueDate == null) return '';
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final dueDay = DateTime(dueDate.year, dueDate.month, dueDate.day);
    final diffDays = dueDay.difference(today).inDays;
    if (diffDays < 0) {
      return '已逾期';
    } else if (diffDays == 0)
      return '今天 ${dueDate.hour.toString().padLeft(2, '0')}:${dueDate.minute.toString().padLeft(2, '0')}';
    else if (diffDays == 1)
      return '明天';
    else
      return '$diffDays天后';
  }

  static Future<void> updateAllWidgetData(
      String username, List<TodoItem> todos) async {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    DateTime now = DateTime.now();
    DateTime today = DateTime(now.year, now.month, now.day);
    DateFormat dateFormat = DateFormat('yyyy-MM-dd');

    // 🚀 性能优化：如果提供了 preloadedTodos，则跳过部分读取（虽然 Widget 需要的数据比 HomeDashboard 更多）
    // 但为了彻底解决启动卡顿，我们尽量减少同步调用。
    final results = await Future.wait([
      todos != null ? Future.value(todos) : StorageService.getTodos(username),
      CourseService.getAllCourses(username),
      StorageService.getCountdowns(username),
      StorageService.getTimeLogs(username),
      PomodoroService.getTodayRecords(),
      PomodoroService.getTags(),
    ]);

    final List<TodoItem> allTodos = results[0] as List<TodoItem>;
    final List<CourseItem> allCourses = results[1] as List<CourseItem>;
    final List<CountdownItem> countdownsRaw = results[2] as List<CountdownItem>;
    final List<TimeLogItem> tlogsRaw = results[3] as List<TimeLogItem>;
    final List<PomodoroRecord> pomsRaw = results[4] as List<PomodoroRecord>;
    final List<PomodoroTag> allTags = results[5] as List<PomodoroTag>;

    final Map<String, String> tagNameByUuid = {
      for (var t in allTags) t.uuid: t.name
    };

    // 🚀 核心优化：将所有复杂的逻辑处理（排序、过滤、格式化、HTML 标签插入）全部移至后台 Isolate
    final Map<String, dynamic> rawInput = {
      'now': now.millisecondsSinceEpoch,
      'todos': results[0],
      'courses': results[1],
      'countdowns': results[2],
      'timelogs': results[3],
      'poms': results[4],
      'tags': results[5],
    };

    final Map<String, dynamic> widgetData = await compute(_prepareWidgetDataIsolate, rawInput);

    // 批量写入结果
    final List<Future<void>> widgetWrites = [];
    widgetData.forEach((key, value) {
      widgetWrites.add(HomeWidget.saveWidgetData(key, value));
    });

    await Future.wait(widgetWrites);
    try {
      await HomeWidget.updateWidget(androidName: androidWidgetName);
    } catch (e) {
      debugPrint('⚠️ [WidgetService] Android Widget update suppressed: $e');
    }
  }

  /// 🚀 Isolate 内部逻辑：处理所有 Widget 展现逻辑
  static Map<String, dynamic> _prepareWidgetDataIsolate(Map<String, dynamic> input) {
    final now = DateTime.fromMillisecondsSinceEpoch(input['now']);
    final today = DateTime(now.year, now.month, now.day);
    final List<TodoItem> allTodos = input['todos'] as List<TodoItem>;
    final List<CourseItem> allCourses = input['courses'] as List<CourseItem>;
    final List<CountdownItem> countdownsRaw = input['countdowns'] as List<CountdownItem>;
    final List<TimeLogItem> tlogsRaw = input['timelogs'] as List<TimeLogItem>;
    final List<PomodoroRecord> pomsRaw = input['poms'] as List<PomodoroRecord>;
    final List<PomodoroTag> allTags = input['tags'] as List<PomodoroTag>;

    final Map<String, String> tagNameByUuid = {for (var t in allTags) t.uuid: t.name};
    final Map<String, dynamic> resultData = {};

    // 1. 待办事项处理
    List<TodoItem> pendingTodos = allTodos.where((t) => !t.isDone && !t.isDeleted).toList();
    List<TodoItem> pastTodos = [];
    List<TodoItem> todayTodos = [];
    List<TodoItem> futureTodos = [];
    for (final t in pendingTodos) {
      if (t.dueDate != null) {
        DateTime d = DateTime(t.dueDate!.year, t.dueDate!.month, t.dueDate!.day);
        if (d.isBefore(today)) pastTodos.add(t);
        else if (d.isAfter(today)) futureTodos.add(t);
        else todayTodos.add(t);
      } else {
        todayTodos.add(t);
      }
    }
    int startMs(TodoItem t) => t.createdDate ?? t.createdAt;
    int compareUrgency(TodoItem a, TodoItem b) {
      if (a.dueDate != null && b.dueDate != null) return a.dueDate!.compareTo(b.dueDate!);
      if (a.dueDate != null && b.dueDate == null) return -1;
      if (a.dueDate == null && b.dueDate != null) return 1;
      return startMs(a).compareTo(startMs(b));
    }
    pastTodos.sort(compareUrgency);
    todayTodos.sort(compareUrgency);
    futureTodos.sort(compareUrgency);
    final displayTodos = [...pastTodos, ...todayTodos, ...futureTodos].take(maxWidgetItems).toList();

    for (int i = 1; i <= maxWidgetItems; i++) {
      resultData['todo_$i'] = '';
      resultData['todo_${i}_done'] = false;
      resultData['todo_${i}_id'] = '';
      resultData['todo_${i}_due'] = '';
    }
    for (int i = 0; i < displayTodos.length; i++) {
      final todo = displayTodos[i];
      String title = todo.title;
      if (todo.dueDate == null || !DateTime(todo.dueDate!.year, todo.dueDate!.month, todo.dueDate!.day).isAfter(today)) {
        title = "<b>$title</b>";
      }
      resultData['todo_${i + 1}'] = title;
      resultData['todo_${i + 1}_done'] = todo.isDone;
      resultData['todo_${i + 1}_id'] = todo.id;
      resultData['todo_${i + 1}_due'] = _getDueDateLabel(todo.dueDate);
    }

    // 2. 课程处理
    String urgentCourseId = '';
    for (int i = 1; i <= maxWidgetItems; i++) {
      resultData['course_date_$i'] = '';
      resultData['course_name_$i'] = '';
      resultData['course_time_$i'] = '';
      resultData['course_room_$i'] = '';
      resultData['course_id_$i'] = '';
    }
    try {
      final df = DateFormat('yyyy-MM-dd');
      List<CourseItem> futureCourses = allCourses.where((c) {
        try {
          DateTime cDate = df.parse(c.date);
          DateTime cEnd = cDate.add(Duration(hours: c.endTime ~/ 100, minutes: c.endTime % 100));
          return cEnd.isAfter(now);
        } catch (_) { return false; }
      }).toList();
      futureCourses.sort((a, b) {
        int dateCmp = a.date.compareTo(b.date);
        if (dateCmp != 0) return dateCmp;
        return a.startTime.compareTo(b.startTime);
      });
      final displayCourses = futureCourses.take(maxWidgetItems).toList();
      for (int i = 0; i < displayCourses.length; i++) {
        final course = displayCourses[i];
        DateTime courseDate = df.parse(course.date);
        int diffDays = DateTime(courseDate.year, courseDate.month, courseDate.day).difference(today).inDays;
        String dayLabel = diffDays == 0 ? "今天" : (diffDays == 1 ? "明天" : (diffDays == 2 ? "后天" : "$diffDays天后"));
        String fullDateHeader = "$dayLabel | ${courseDate.month}月${courseDate.day}日";
        String cName = course.courseName;
        if (diffDays == 0) {
          fullDateHeader = "<b>$fullDateHeader</b>";
          cName = "<b>$cName</b>";
        }
        String cId = '${course.courseName}_${course.date}_${course.startTime}';
        resultData['course_date_${i + 1}'] = fullDateHeader;
        resultData['course_name_${i + 1}'] = cName;
        resultData['course_time_${i + 1}'] = '${course.formattedStartTime} - ${course.formattedEndTime}';
        resultData['course_room_${i + 1}'] = "@${course.roomName}";
        resultData['course_id_${i + 1}'] = cId;
        if (urgentCourseId.isEmpty) {
          DateTime cStart = courseDate.add(Duration(hours: course.startTime ~/ 100, minutes: course.startTime % 100));
          if (cStart.isAfter(now) && cStart.difference(now).inMinutes <= 30) urgentCourseId = cId;
        }
      }
    } catch (_) {}
    resultData['urgent_course_id'] = urgentCourseId;

    // 3. 倒数日
    List<CountdownItem> countdowns = countdownsRaw.where((c) => !c.isDeleted && c.targetDate.difference(today).inDays >= 0).toList();
    countdowns.sort((a, b) => a.targetDate.compareTo(b.targetDate));
    for (int i = 1; i <= maxWidgetItems; i++) {
      resultData['cd_title_$i'] = '';
      resultData['cd_days_$i'] = '';
    }
    for (int i = 0; i < countdowns.length && i < maxWidgetItems; i++) {
      final cd = countdowns[i];
      final diff = cd.targetDate.difference(today).inDays;
      resultData['cd_title_${i + 1}'] = diff == 0 ? "<b>${cd.title}</b>" : cd.title;
      resultData['cd_days_${i + 1}'] = diff == 0 ? "就在今天" : "还有 $diff 天";
    }

    // 4. 专注日志统计
    try {
      final filteredTimeLogs = tlogsRaw.where((l) => !l.isDeleted).where((l) {
        final d = DateTime.fromMillisecondsSinceEpoch(l.startTime, isUtc: true).toLocal();
        return d.year == today.year && d.month == today.month && d.day == today.day;
      }).toList();
      final filteredPoms = pomsRaw.where((p) => !p.isDeleted).where((p) {
        final d = DateTime.fromMillisecondsSinceEpoch(p.startTime, isUtc: true).toLocal();
        return d.year == today.year && d.month == today.month && d.day == today.day;
      }).toList();

      final List<Map<String, dynamic>> merged = [];
      for (final l in filteredTimeLogs) {
        if (l.endTime <= l.startTime) continue;
        merged.add({'title': (l.title.isNotEmpty ? l.title : '专注任务'), 'start': l.startTime, 'minutes': ((l.endTime - l.startTime) ~/ 60000)});
      }
      for (final p in filteredPoms) {
        int start = p.startTime;
        int end = p.endTime ?? (p.startTime + (p.actualDuration ?? p.plannedDuration) * 1000);
        if (end <= start) continue;
        merged.add({'title': (p.todoTitle ?? '专注任务'), 'start': start, 'minutes': ((end - start) ~/ 60000)});
      }
      merged.sort((a, b) => b['start'].compareTo(a['start']));
      final totalMins = merged.fold<int>(0, (s, e) => s + (e['minutes'] as int));
      resultData['tl_total'] = '今日总专注: $totalMins 分钟';

      final Map<String, double> tagMinutes = {};
      for (final l in filteredTimeLogs) {
        final mins = ((l.endTime - l.startTime) ~/ 60000).toDouble();
        if (l.tagUuids.isEmpty) tagMinutes['未分类'] = (tagMinutes['未分类'] ?? 0) + mins;
        else {
          final per = mins / l.tagUuids.length;
          for (final tu in l.tagUuids) {
            final name = tagNameByUuid[tu] ?? tu;
            tagMinutes[name] = (tagMinutes[name] ?? 0) + per;
          }
        }
      }
      for (final p in filteredPoms) {
        final start = p.startTime;
        final end = p.endTime ?? (p.startTime + (p.actualDuration ?? p.plannedDuration) * 1000);
        final mins = ((end - start) ~/ 60000).toDouble();
        if (p.tagUuids.isEmpty) tagMinutes['未分类'] = (tagMinutes['未分类'] ?? 0) + mins;
        else {
          final per = mins / p.tagUuids.length;
          for (final tu in p.tagUuids) {
            final name = tagNameByUuid[tu] ?? tu;
            tagMinutes[name] = (tagMinutes[name] ?? 0) + per;
          }
        }
      }
      final tagEntries = tagMinutes.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
      for (int i = 1; i <= maxWidgetItems; i++) {
        resultData['tl_tag_name_$i'] = '';
        resultData['tl_tag_mins_$i'] = '';
        resultData['tl_title_$i'] = '';
        resultData['tl_time_$i'] = '';
      }
      resultData['tl_tag_count'] = '${tagEntries.length}';
      for (int i = 0; i < tagEntries.length && i < maxWidgetItems; i++) {
        resultData['tl_tag_name_${i + 1}'] = tagEntries[i].key;
        resultData['tl_tag_mins_${i + 1}'] = '${tagEntries[i].value.round()}分';
      }
      for (int i = 0; i < merged.length && i < maxWidgetItems; i++) {
        resultData['tl_title_${i + 1}'] = merged[i]['title'];
        resultData['tl_time_${i + 1}'] = '${merged[i]['minutes']}分钟';
      }
    } catch (_) {}

    // 5. 专注状态判断
    resultData['widget_mode'] = urgentCourseId.isNotEmpty ? 'course' : 'todo';
    return resultData;
  }

  static String _hm(DateTime dt) => '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';

  static Future<void> updateTodoWidget(List<TodoItem> todos) async {
    final prefs = await SharedPreferences.getInstance();
    final username = prefs.getString(StorageService.KEY_CURRENT_USER) ?? '';
    await updateAllWidgetData(username, todos);
  }
}
