import 'package:home_widget/home_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';
import 'dart:async';
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

    // 并行读取所有必要的数据，极大提升性能
    final results = await Future.wait([
      StorageService.getTodos(username),
      CourseService.getAllCourses(username),
      StorageService.getCountdowns(username),
      StorageService.getTimeLogs(username),
      PomodoroService.getTodayRecords(),
      PomodoroService.getTags(), // 预加载标签
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

    final List<Future<void>> widgetWrites = [];

    // 1. 待办事项
    List<TodoItem> pendingTodos =
        allTodos.where((t) => !t.isDone && !t.isDeleted).toList();
    List<TodoItem> pastTodos = [];
    List<TodoItem> todayTodos = [];
    List<TodoItem> futureTodos = [];
    for (final t in pendingTodos) {
      if (t.dueDate != null) {
        DateTime d =
            DateTime(t.dueDate!.year, t.dueDate!.month, t.dueDate!.day);
        if (d.isBefore(today)) {
          pastTodos.add(t);
        } else if (d.isAfter(today))
          futureTodos.add(t);
        else
          todayTodos.add(t);
      } else {
        todayTodos.add(t);
      }
    }
    int startMs(TodoItem t) => t.createdDate ?? t.createdAt;
    int compareUrgency(TodoItem a, TodoItem b) {
      if (a.dueDate != null && b.dueDate != null) {
        return a.dueDate!.compareTo(b.dueDate!);
      }
      if (a.dueDate != null && b.dueDate == null) return -1;
      if (a.dueDate == null && b.dueDate != null) return 1;
      return startMs(a).compareTo(startMs(b));
    }

    pastTodos.sort(compareUrgency);
    todayTodos.sort(compareUrgency);
    futureTodos.sort(compareUrgency);
    final displayTodos = [...pastTodos, ...todayTodos, ...futureTodos]
        .take(maxWidgetItems)
        .toList();
    for (int i = 1; i <= maxWidgetItems; i++) {
      widgetWrites.add(HomeWidget.saveWidgetData('todo_$i', ''));
      widgetWrites.add(HomeWidget.saveWidgetData('todo_${i}_done', false));
      widgetWrites.add(HomeWidget.saveWidgetData('todo_${i}_id', ''));
      widgetWrites.add(HomeWidget.saveWidgetData('todo_${i}_due', ''));
    }
    for (int i = 0; i < displayTodos.length; i++) {
      final todo = displayTodos[i];
      String title = todo.title;
      if (todo.dueDate == null ||
          !DateTime(todo.dueDate!.year, todo.dueDate!.month, todo.dueDate!.day)
              .isAfter(today)) {
        title = "<b>$title</b>";
      }
      widgetWrites.add(HomeWidget.saveWidgetData('todo_${i + 1}', title));
      widgetWrites
          .add(HomeWidget.saveWidgetData('todo_${i + 1}_done', todo.isDone));
      widgetWrites.add(HomeWidget.saveWidgetData('todo_${i + 1}_id', todo.id));
      widgetWrites.add(HomeWidget.saveWidgetData(
          'todo_${i + 1}_due', _getDueDateLabel(todo.dueDate)));
    }

    // 2. 课程提醒 - 🚀 四行排版逻辑
    String urgentCourseId = '';
    for (int i = 1; i <= maxWidgetItems; i++) {
      widgetWrites.add(HomeWidget.saveWidgetData('course_date_$i', ''));
      widgetWrites.add(HomeWidget.saveWidgetData('course_name_$i', ''));
      widgetWrites.add(HomeWidget.saveWidgetData('course_time_$i', ''));
      widgetWrites.add(HomeWidget.saveWidgetData('course_room_$i', ''));
      widgetWrites.add(HomeWidget.saveWidgetData('course_id_$i', ''));
    }
    try {
      List<CourseItem> futureCourses = allCourses.where((c) {
        try {
          DateTime cDate = dateFormat.parse(c.date);
          DateTime cEnd = cDate
              .add(Duration(hours: c.endTime ~/ 100, minutes: c.endTime % 100));
          return cEnd.isAfter(now);
        } catch (_) {
          return false;
        }
      }).toList();
      futureCourses.sort((a, b) {
        int dateCmp = a.date.compareTo(b.date);
        if (dateCmp != 0) return dateCmp;
        return a.startTime.compareTo(b.startTime);
      });
      if (futureCourses.isNotEmpty) {
        final displayCourses = futureCourses.take(maxWidgetItems).toList();
        for (int i = 0; i < displayCourses.length; i++) {
          final course = displayCourses[i];
          DateTime courseDate = dateFormat.parse(course.date);
          int diffDays =
              DateTime(courseDate.year, courseDate.month, courseDate.day)
                  .difference(today)
                  .inDays;

          // 🚀 格式化日期头
          String dayLabel = diffDays == 0
              ? "今天"
              : (diffDays == 1 ? "明天" : (diffDays == 2 ? "后天" : "$diffDays天后"));
          String fullDateHeader =
              "$dayLabel | ${courseDate.month}月${courseDate.day}日";

          String cName = course.courseName;
          if (diffDays == 0) {
            fullDateHeader = "<b>$fullDateHeader</b>";
            cName = "<b>$cName</b>";
          }

          String courseId =
              '${course.courseName}_${course.date}_${course.startTime}';
          widgetWrites.add(HomeWidget.saveWidgetData(
              'course_date_${i + 1}', fullDateHeader));
          widgetWrites
              .add(HomeWidget.saveWidgetData('course_name_${i + 1}', cName));
          widgetWrites.add(HomeWidget.saveWidgetData('course_time_${i + 1}',
              '${course.formattedStartTime} - ${course.formattedEndTime}'));
          widgetWrites.add(HomeWidget.saveWidgetData(
              'course_room_${i + 1}', "@${course.roomName}"));
          widgetWrites
              .add(HomeWidget.saveWidgetData('course_id_${i + 1}', courseId));

          if (urgentCourseId.isEmpty) {
            DateTime cStart = courseDate.add(Duration(
                hours: course.startTime ~/ 100,
                minutes: course.startTime % 100));
            if (cStart.isAfter(now) && cStart.difference(now).inMinutes <= 30) {
              urgentCourseId = courseId;
            }
          }
        }
      }
    } catch (e) {
      print("Widget Course Error: $e");
    }
    widgetWrites
        .add(HomeWidget.saveWidgetData('urgent_course_id', urgentCourseId));

    // 3. 倒数日
    List<CountdownItem> countdowns = countdownsRaw
        .where(
            (c) => !c.isDeleted && c.targetDate.difference(today).inDays >= 0)
        .toList();
    countdowns.sort((a, b) => a.targetDate.compareTo(b.targetDate));
    for (int i = 1; i <= maxWidgetItems; i++) {
      widgetWrites.add(HomeWidget.saveWidgetData('cd_title_$i', ''));
      widgetWrites.add(HomeWidget.saveWidgetData('cd_days_$i', ''));
    }
    for (int i = 0; i < countdowns.length && i < maxWidgetItems; i++) {
      final cd = countdowns[i];
      final diff = cd.targetDate.difference(today).inDays;
      String cdTitle = diff == 0 ? "<b>${cd.title}</b>" : cd.title;
      widgetWrites.add(HomeWidget.saveWidgetData('cd_title_${i + 1}', cdTitle));
      widgetWrites.add(HomeWidget.saveWidgetData(
          'cd_days_${i + 1}', diff == 0 ? "就在今天" : "还有 $diff 天"));
    }

    // 4. 专注日志 —— 合并番茄钟记录与时间日志（优先本地数据）
    try {
      // 过滤出今日且未删除的 time logs
      final filteredTimeLogs = tlogsRaw.where((l) {
        if (l.isDeleted) return false;
        try {
          final d =
              DateTime.fromMillisecondsSinceEpoch(l.startTime, isUtc: true)
                  .toLocal();
          return d.year == today.year &&
              d.month == today.month &&
              d.day == today.day;
        } catch (_) {
          return false;
        }
      }).toList();

      // 过滤出今日且未删除的 pomodoro 记录
      final filteredPoms = pomsRaw.where((p) => !p.isDeleted).where((p) {
        try {
          final d =
              DateTime.fromMillisecondsSinceEpoch(p.startTime, isUtc: true)
                  .toLocal();
          return d.year == today.year &&
              d.month == today.month &&
              d.day == today.day;
        } catch (_) {
          return false;
        }
      }).toList();

      // 合并为统一结构
      final List<Map<String, dynamic>> merged = [];

      for (final l in filteredTimeLogs) {
        if (l.endTime <= l.startTime) continue; // 忽略无效
        merged.add({
          'kind': 'timelog',
          'title': (l.title.isNotEmpty
              ? l.title
              : (l.tagUuids.isNotEmpty ? '专注任务' : '补录')),
          'start': l.startTime,
          'end': l.endTime,
          'minutes': ((l.endTime - l.startTime) ~/ 60000),
        });
      }

      for (final p in filteredPoms) {
        int start = p.startTime;
        int end = p.endTime ??
            (p.startTime +
                (p.actualDuration != null
                    ? p.actualDuration! * 1000
                    : p.plannedDuration * 1000));
        if (end <= start) continue;
        final title = (p.todoTitle != null && p.todoTitle!.isNotEmpty)
            ? p.todoTitle!
            : '专注任务';
        merged.add({
          'kind': 'pomodoro',
          'title': title,
          'start': start,
          'end': end,
          'minutes': ((end - start) ~/ 60000),
        });
      }

      // 按开始时间降序（最近的在前）排序
      merged.sort((a, b) => b['start'].compareTo(a['start']));

      final totalMins =
          merged.fold<int>(0, (s, e) => s + (e['minutes'] as int));
      widgetWrites
          .add(HomeWidget.saveWidgetData('tl_total', '今日总专注: $totalMins 分钟'));

      // === 按标签统计分钟数（合并 Pomodoro 与 TimeLog） ===
      final Map<String, double> tagMinutes = {}; // 使用 double 以便均分
      const String untaggedKey = '未分类';

      // 遍历原始 filteredTimeLogs（timelog）和 filteredPoms（pomodoro）来统计标签分钟
      // 为此我们再利用 merged 中的信息，但需要原始记录的 tag uuid 列表
      // 先处理 time logs
      for (final l in filteredTimeLogs) {
        final mins = ((l.endTime - l.startTime) ~/ 60000).toDouble();
        final tags = l.tagUuids;
        if (tags.isEmpty) {
          tagMinutes[untaggedKey] = (tagMinutes[untaggedKey] ?? 0) + mins;
        } else {
          final per = mins / tags.length;
          for (final tu in tags) {
            final name = tagNameByUuid[tu] ?? tu;
            tagMinutes[name] = (tagMinutes[name] ?? 0) + per;
          }
        }
      }

      // 处理 pomodoro 记录
      for (final p in filteredPoms) {
        final start = p.startTime;
        final end = p.endTime ??
            (p.startTime +
                (p.actualDuration != null
                    ? p.actualDuration! * 1000
                    : p.plannedDuration * 1000));
        final mins = ((end - start) ~/ 60000).toDouble();
        final tags = p.tagUuids;
        if (tags.isEmpty) {
          tagMinutes[untaggedKey] = (tagMinutes[untaggedKey] ?? 0) + mins;
        } else {
          final per = mins / tags.length;
          for (final tu in tags) {
            final name = tagNameByUuid[tu] ?? tu;
            tagMinutes[name] = (tagMinutes[name] ?? 0) + per;
          }
        }
      }

      // 转换为列表并按分钟数降序排序
      final tagEntries = tagMinutes.entries
          .map((e) => MapEntry(e.key, e.value))
          .toList()
        ..sort((a, b) => b.value.compareTo(a.value));

      // 写入 widget：清空旧的 tag 键
      for (int i = 1; i <= maxWidgetItems; i++) {
        widgetWrites.add(HomeWidget.saveWidgetData('tl_tag_name_$i', ''));
        widgetWrites.add(HomeWidget.saveWidgetData('tl_tag_mins_$i', ''));
      }
      // 写入 tag 数量（字符串形式，widget 层解析即可）
      widgetWrites.add(
          HomeWidget.saveWidgetData('tl_tag_count', '${tagEntries.length}'));
      for (int i = 0; i < tagEntries.length && i < maxWidgetItems; i++) {
        final name = tagEntries[i].key;
        final mins = tagEntries[i].value.round();
        widgetWrites
            .add(HomeWidget.saveWidgetData('tl_tag_name_${i + 1}', name));
        widgetWrites
            .add(HomeWidget.saveWidgetData('tl_tag_mins_${i + 1}', '$mins分'));
      }

      // 清空条目
      for (int i = 1; i <= maxWidgetItems; i++) {
        widgetWrites.add(HomeWidget.saveWidgetData('tl_title_$i', ''));
        widgetWrites.add(HomeWidget.saveWidgetData('tl_time_$i', ''));
      }

      for (int i = 0; i < merged.length && i < maxWidgetItems; i++) {
        final it = merged[i];
        final displayTitle =
            (it['title'] as String).isNotEmpty ? it['title'] : '专注任务';
        final mins = it['minutes'] as int;
        widgetWrites
            .add(HomeWidget.saveWidgetData('tl_title_${i + 1}', displayTitle));
        widgetWrites
            .add(HomeWidget.saveWidgetData('tl_time_${i + 1}', '$mins分钟'));
      }
    } catch (e) {
      print('Widget focus merge error: $e');
      // 兜底：确保键存在
      widgetWrites.add(HomeWidget.saveWidgetData('tl_total', '今日总专注: 0 分钟'));
      for (int i = 1; i <= maxWidgetItems; i++) {
        widgetWrites.add(HomeWidget.saveWidgetData('tl_title_$i', ''));
        widgetWrites.add(HomeWidget.saveWidgetData('tl_time_$i', ''));
      }
    }

    // === 新增：根据课程/专注状态切换显示栏位（优先级：课程 -> 专注 -> 待办） ===
    String widgetMode = 'todo'; // todo | focus | course

    // 优先：课程提醒
    if (urgentCourseId.isNotEmpty) {
      widgetMode = 'course';
    } else {
      try {
        final run = await PomodoroService.loadRunState();
        if (run != null &&
            (run.phase == PomodoroPhase.focusing ||
                run.phase == PomodoroPhase.breaking ||
                run.phase == PomodoroPhase.remoteWatching)) {
          widgetMode = 'focus';

          // 展示专注信息：任务标题 / 剩余或已用时间 / 标签
          final title = (run.todoTitle != null && run.todoTitle!.isNotEmpty)
              ? run.todoTitle!
              : '专注中';
          widgetWrites.add(HomeWidget.saveWidgetData('focus_title', title));

          final nowMs = DateTime.now().millisecondsSinceEpoch;
          final isCountUp = run.mode == TimerMode.countUp;
          int seconds = isCountUp
              ? ((nowMs - run.sessionStartMs) / 1000).floor()
              : ((run.targetEndMs - nowMs) / 1000).ceil();
          if (seconds < 0) seconds = 0;

          final h = seconds ~/ 3600;
          final m = (seconds % 3600) ~/ 60;
          final timerStr = isCountUp
              ? (h > 0 ? '$h小时 $m分钟' : '$m 分钟')
              : (h > 0 ? '剩余 $h小时 $m分钟' : '剩余 $m 分钟');

          widgetWrites.add(HomeWidget.saveWidgetData('focus_seconds', seconds));
          widgetWrites.add(HomeWidget.saveWidgetData('focus_timer', timerStr));

          // 标签显示（优先本地 tag 名称）
          List<String> tagNames = [];
          for (final tu in run.tagUuids) {
            final n = tagNameByUuid[tu] ?? tu;
            tagNames.add(n);
          }

          // 写入 focus tag 键
          widgetWrites.add(HomeWidget.saveWidgetData(
              'focus_tag_count', '${tagNames.length}'));
          for (int i = 1; i <= maxWidgetItems; i++) {
            widgetWrites.add(HomeWidget.saveWidgetData(
                'focus_tag_$i', i <= tagNames.length ? tagNames[i - 1] : ''));
          }
        } else {
          // 清空 focus 键
          widgetWrites.add(HomeWidget.saveWidgetData('focus_title', ''));
          widgetWrites.add(HomeWidget.saveWidgetData('focus_seconds', 0));
          widgetWrites.add(HomeWidget.saveWidgetData('focus_timer', ''));
          widgetWrites.add(HomeWidget.saveWidgetData('focus_tag_count', '0'));
          for (int i = 1; i <= maxWidgetItems; i++) {
            widgetWrites.add(HomeWidget.saveWidgetData('focus_tag_$i', ''));
          }
        }
      } catch (e) {
        print('Widget focus state read error: $e');
      }
    }

    // 保存当前模式，供原生层决定展示哪一栏
    widgetWrites.add(HomeWidget.saveWidgetData('widget_mode', widgetMode));

    // 批量并行写入 widget 数据
    await Future.wait(widgetWrites);
    try {
      await HomeWidget.updateWidget(androidName: androidWidgetName);
    } catch (e) {
      // 🚀 调试版如果改了包名，这里会报找不到类的错误，静默处理不影响主程序
      print('⚠️ [WidgetService] Android Widget update suppressed: $e');
    }
  }

  static Future<void> updateTodoWidget(List<TodoItem> todos) async {
    final prefs = await SharedPreferences.getInstance();
    final username = prefs.getString(StorageService.KEY_CURRENT_USER) ?? '';
    await updateAllWidgetData(username, todos);
  }
}
