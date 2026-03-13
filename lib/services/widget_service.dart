import 'package:home_widget/home_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';
import 'package:intl/intl.dart';
import '../models.dart';
import '../storage_service.dart';
import 'course_service.dart';

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

  static Future<void> init() async {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    if (_initialized) return;
    try {
      await HomeWidget.registerBackgroundCallback(widgetBackgroundCallback);
      _initialized = true;
    } catch (e) {
      print('WidgetBackground 注册失败: $e');
    }
  }

  static String _getDueDateLabel(DateTime? dueDate) {
    if (dueDate == null) return '';
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final dueDay = DateTime(dueDate.year, dueDate.month, dueDate.day);
    final diffDays = dueDay.difference(today).inDays;
    if (diffDays < 0) return '已逾期';
    else if (diffDays == 0) return '今天 ${dueDate.hour.toString().padLeft(2, '0')}:${dueDate.minute.toString().padLeft(2, '0')}';
    else if (diffDays == 1) return '明天';
    else return '$diffDays天后';
  }

  static Future<void> updateAllWidgetData(String username, List<TodoItem> todos) async {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    DateTime now = DateTime.now();
    DateTime today = DateTime(now.year, now.month, now.day);
    DateFormat dateFormat = DateFormat('yyyy-MM-dd');

    // 1. 待办事项
    List<TodoItem> pendingTodos = todos.where((t) => !t.isDone && !t.isDeleted).toList();
    List<TodoItem> pastTodos = [];
    List<TodoItem> todayTodos = [];
    List<TodoItem> futureTodos = [];
    for (final t in pendingTodos) {
      if (t.dueDate != null) {
        DateTime d = DateTime(t.dueDate!.year, t.dueDate!.month, t.dueDate!.day);
        if (d.isBefore(today)) pastTodos.add(t);
        else if (d.isAfter(today)) futureTodos.add(t);
        else todayTodos.add(t);
      } else { todayTodos.add(t); }
    }
    int startMs(TodoItem t) => t.createdDate ?? t.createdAt;
    int compareUrgency(TodoItem a, TodoItem b) {
      if (a.dueDate != null && b.dueDate != null) return a.dueDate!.compareTo(b.dueDate!);
      if (a.dueDate != null && b.dueDate == null) return -1;
      if (a.dueDate == null && b.dueDate != null) return 1;
      return startMs(a).compareTo(startMs(b));
    }
    pastTodos.sort(compareUrgency); todayTodos.sort(compareUrgency); futureTodos.sort(compareUrgency);
    final displayTodos = [...pastTodos, ...todayTodos, ...futureTodos].take(maxWidgetItems).toList();
    for (int i = 1; i <= maxWidgetItems; i++) {
      await HomeWidget.saveWidgetData('todo_$i', '');
      await HomeWidget.saveWidgetData('todo_${i}_done', false);
      await HomeWidget.saveWidgetData('todo_${i}_id', '');
      await HomeWidget.saveWidgetData('todo_${i}_due', '');
    }
    for (int i = 0; i < displayTodos.length; i++) {
      final todo = displayTodos[i];
      String title = todo.title;
      if (todo.dueDate == null || !DateTime(todo.dueDate!.year, todo.dueDate!.month, todo.dueDate!.day).isAfter(today)) {
        title = "<b>$title</b>";
      }
      await HomeWidget.saveWidgetData('todo_${i + 1}', title);
      await HomeWidget.saveWidgetData('todo_${i + 1}_done', todo.isDone);
      await HomeWidget.saveWidgetData('todo_${i + 1}_id', todo.id);
      await HomeWidget.saveWidgetData('todo_${i + 1}_due', _getDueDateLabel(todo.dueDate));
    }

    // 2. 课程提醒 - 🚀 四行排版逻辑
    String urgentCourseId = '';
    for (int i = 1; i <= maxWidgetItems; i++) {
      await HomeWidget.saveWidgetData('course_date_$i', '');
      await HomeWidget.saveWidgetData('course_name_$i', '');
      await HomeWidget.saveWidgetData('course_time_$i', '');
      await HomeWidget.saveWidgetData('course_room_$i', '');
      await HomeWidget.saveWidgetData('course_id_$i', '');
    }
    try {
      List<CourseItem> allCourses = await CourseService.getAllCourses();
      List<CourseItem> futureCourses = allCourses.where((c) {
        try {
          DateTime cDate = dateFormat.parse(c.date);
          DateTime cEnd = cDate.add(Duration(hours: c.endTime ~/ 100, minutes: c.endTime % 100));
          return cEnd.isAfter(now);
        } catch (_) { return false; }
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
          int diffDays = DateTime(courseDate.year, courseDate.month, courseDate.day).difference(today).inDays;

          // 🚀 格式化日期头
          String dayLabel = diffDays == 0 ? "今天" : (diffDays == 1 ? "明天" : (diffDays == 2 ? "后天" : "$diffDays天后"));
          String fullDateHeader = "$dayLabel | ${courseDate.month}月${courseDate.day}日";

          String cName = course.courseName;
          if (diffDays == 0) {
            fullDateHeader = "<b>$fullDateHeader</b>";
            cName = "<b>$cName</b>";
          }

          String courseId = '${course.courseName}_${course.date}_${course.startTime}';
          await HomeWidget.saveWidgetData('course_date_${i + 1}', fullDateHeader);
          await HomeWidget.saveWidgetData('course_name_${i + 1}', cName);
          await HomeWidget.saveWidgetData('course_time_${i + 1}', '${course.formattedStartTime} - ${course.formattedEndTime}');
          await HomeWidget.saveWidgetData('course_room_${i + 1}', "@${course.roomName}");
          await HomeWidget.saveWidgetData('course_id_${i + 1}', courseId);

          if (urgentCourseId.isEmpty) {
            DateTime cStart = courseDate.add(Duration(hours: course.startTime ~/ 100, minutes: course.startTime % 100));
            if (cStart.isAfter(now) && cStart.difference(now).inMinutes <= 30) urgentCourseId = courseId;
          }
        }
      }
    } catch (e) { print("Widget Course Error: $e"); }
    await HomeWidget.saveWidgetData('urgent_course_id', urgentCourseId);

    // 3. 倒数日
    List<CountdownItem> countdowns = await StorageService.getCountdowns(username);
    countdowns = countdowns.where((c) => !c.isDeleted && c.targetDate.difference(today).inDays >= 0).toList();
    countdowns.sort((a, b) => a.targetDate.compareTo(b.targetDate));
    for (int i = 1; i <= maxWidgetItems; i++) {
      await HomeWidget.saveWidgetData('cd_title_$i', '');
      await HomeWidget.saveWidgetData('cd_days_$i', '');
    }
    for (int i = 0; i < countdowns.length && i < maxWidgetItems; i++) {
      final cd = countdowns[i];
      final diff = cd.targetDate.difference(today).inDays;
      String cdTitle = diff == 0 ? "<b>${cd.title}</b>" : cd.title;
      await HomeWidget.saveWidgetData('cd_title_${i + 1}', cdTitle);
      await HomeWidget.saveWidgetData('cd_days_${i + 1}', diff == 0 ? "就在今天" : "还有 $diff 天");
    }

    // 4. 专注日志
    List<TimeLogItem> logs = await StorageService.getTimeLogs(username);
    logs = logs.where((l) {
      if (l.isDeleted) return false;
      final d = DateTime.fromMillisecondsSinceEpoch(l.startTime, isUtc: true).toLocal();
      return d.year == today.year && d.month == today.month && d.day == today.day;
    }).toList();
    int totalMins = logs.fold(0, (sum, l) => sum + (l.endTime - l.startTime) ~/ 60000);
    await HomeWidget.saveWidgetData('tl_total', '今日总专注: $totalMins 分钟');
    logs.sort((a, b) => b.startTime.compareTo(a.startTime));
    for (int i = 1; i <= maxWidgetItems; i++) {
      await HomeWidget.saveWidgetData('tl_title_$i', '');
      await HomeWidget.saveWidgetData('tl_time_$i', '');
    }
    for (int i = 0; i < logs.length && i < maxWidgetItems; i++) {
      final log = logs[i];
      await HomeWidget.saveWidgetData('tl_title_${i + 1}', log.title.isNotEmpty ? log.title : '专注任务');
      await HomeWidget.saveWidgetData('tl_time_${i + 1}', '${(log.endTime - log.startTime) ~/ 60000}分钟');
    }
    await HomeWidget.updateWidget(androidName: androidWidgetName);
  }

  static Future<void> updateTodoWidget(List<TodoItem> todos) async {
    final prefs = await SharedPreferences.getInstance();
    final username = prefs.getString(StorageService.KEY_CURRENT_USER) ?? '';
    await updateAllWidgetData(username, todos);
  }
}