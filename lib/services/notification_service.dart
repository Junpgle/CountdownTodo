import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:intl/intl.dart';
import '../models.dart';

class NotificationService {
  // 定义与原生通信的通道名称
  static const MethodChannel _channel =
  MethodChannel('com.math_quiz.junpgle.com.math_quiz_app/notifications');

  // 初始化方法
  static Future<void> init() async {
    final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();
    const AndroidInitializationSettings initializationSettingsAndroid =
    AndroidInitializationSettings('@mipmap/ic_launcher');
    const InitializationSettings initializationSettings =
    InitializationSettings(android: initializationSettingsAndroid);

    // 修复：在 flutter_local_notifications 17.0.0 及更高版本中，
    // initialize 方法的首个参数是名为 'settings' 的命名参数。
    await flutterLocalNotificationsPlugin.initialize(settings: initializationSettings);
  }

  // --- 辅助方法：判断是否为同一天 ---
  static bool _isSameDay(DateTime date1, DateTime date2) {
    return date1.year == date2.year &&
        date1.month == date2.month &&
        date1.day == date2.day;
  }

  // --- 课程 (Course) 实时通知逻辑 ---
  static Future<void> showCourseLiveActivity({
    required String courseName,
    required String room,
    required String timeStr,
    required String teacher,
  }) async {
    try {
      await _channel.invokeMethod('showOngoingNotification', {
        'type': 'course',
        'courseName': courseName,
        'room': room,
        'timeStr': timeStr,
        'teacher': teacher,
      });
    } catch (e) {
      print("更新课程通知失败: $e");
    }
  }

  // --- 测验 (Quiz) 通知逻辑 ---
  static Future<void> updateQuizNotification({
    required int currentIndex,
    required int totalCount,
    required String questionText,
    required bool isOver,
    int score = 0,
  }) async {
    if (isOver) {
      await cancelNotification();
      return;
    }

    try {
      await _channel.invokeMethod('showOngoingNotification', {
        'type': 'quiz',
        'currentIndex': currentIndex,
        'totalCount': totalCount,
        'questionText': questionText,
        'isOver': false,
        'score': score,
      });
    } catch (e) {
      print("更新测验通知失败: $e");
    }
  }

  // --- 待办事项 (Todo) 通知逻辑 ---

  // 1. 更新今日待办概览通知
  static Future<void> updateTodoNotification(List<TodoItem> todos) async {
    final DateTime now = DateTime.now();

    // 过滤出：1. 今天的任务 2. 全天任务
    final List<TodoItem> todayAllDayTodos = todos.where((t) {
      if (t.dueDate == null) return false;

      // 转换为本地时间进行日期比较
      DateTime localDueDate = t.dueDate!.toLocal();

      // 检查是否是今天
      bool isDueToday = _isSameDay(localDueDate, now);
      if (!isDueToday) return false;

      // 检查是否为全天属性 (00:00 - 23:59)
      DateTime startDate = DateTime.fromMillisecondsSinceEpoch(
          t.createdDate ?? t.createdAt,
          isUtc: true
      ).toLocal();

      bool isAllDayAttr = startDate.hour == 0 && startDate.minute == 0 &&
          localDueDate.hour == 23 && localDueDate.minute == 59;

      return isAllDayAttr;
    }).toList();

    final int totalCount = todayAllDayTodos.length;

    // 如果今天没有全天待办，或者全部已完成，则尝试清除/隐藏通知
    if (totalCount == 0 || todayAllDayTodos.every((t) => t.isDone)) {
      try {
        await _channel.invokeMethod('showOngoingNotification', {
          'type': 'todo_summary',
          'totalCount': 0,
          'completedCount': 0,
          'pendingCount': 0,
          'pendingTitles': [],
        });
      } catch(e) {}
      return;
    }

    final int completedCount = todayAllDayTodos.where((t) => t.isDone).length;
    final int pendingCount = totalCount - completedCount;

    // 获取前5个未完成的任务标题展示
    final List<String> pendingTitles = todayAllDayTodos
        .where((t) => !t.isDone)
        .take(5)
        .map((t) => t.title)
        .toList();

    try {
      await _channel.invokeMethod('showOngoingNotification', {
        'type': 'todo_summary',
        'totalCount': totalCount,
        'completedCount': completedCount,
        'pendingCount': pendingCount,
        'pendingTitles': pendingTitles,
      });
    } catch (e) {
      print("更新今日待办通知失败: $e");
    }
  }

  // 2. 即将开始的特定时间待办通知 (单条提醒)
  static Future<void> showUpcomingTodoNotification(TodoItem todo) async {
    if (todo.dueDate == null) return;

    // 检查是否为今天的任务，非今天的任务不触发实时提醒
    if (!_isSameDay(todo.dueDate!.toLocal(), DateTime.now())) {
      return;
    }

    try {
      DateTime startDate = DateTime.fromMillisecondsSinceEpoch(
          todo.createdDate ?? todo.createdAt,
          isUtc: true
      ).toLocal();

      String timeStr = DateFormat('HH:mm').format(startDate);
      timeStr += " - ${DateFormat('HH:mm').format(todo.dueDate!.toLocal())}";

      await _channel.invokeMethod('showOngoingNotification', {
        'type': 'upcoming_todo',
        'todoTitle': todo.title,
        'timeStr': timeStr,
      });
    } catch (e) {
      print("更新即将开始的待办通知失败: $e");
    }
  }

  // --- 通用方法 ---

  static Future<void> cancelNotification() async {
    try {
      await _channel.invokeMethod('cancelNotification');
    } catch (e) {
      print("取消通知失败: $e");
    }
  }
}