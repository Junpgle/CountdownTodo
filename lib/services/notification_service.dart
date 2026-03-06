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

    // 适配 flutter_local_notifications 20.0.0+
    await flutterLocalNotificationsPlugin.initialize(settings: initializationSettings);
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

  // 1. 平常只展示未完成的”全天”待办
  static Future<void> updateTodoNotification(List<TodoItem> todos) async {
    final DateTime now = DateTime.now();

    final List<TodoItem> allDayTodos = todos.where((t) {
      if (t.dueDate == null) return false;

      // 🚀 修正：优先使用 createdDate，兼容旧数据 fallback 到 createdAt
      DateTime cDate = DateTime.fromMillisecondsSinceEpoch(t.createdDate ?? t.createdAt);
      bool isAllDayAttr = cDate.hour == 0 && cDate.minute == 0 &&
          t.dueDate!.hour == 23 && t.dueDate!.minute == 59;

      bool isDueToday = t.dueDate!.year == now.year &&
          t.dueDate!.month == now.month &&
          t.dueDate!.day == now.day;

      return isAllDayAttr && isDueToday;
    }).toList();

    final int totalCount = allDayTodos.length;

    if (totalCount == 0 || allDayTodos.every((t) => t.isDone)) {
      try {
        await _channel.invokeMethod('showOngoingNotification', {
          'totalCount': 0,
          'completedCount': 0,
          'pendingCount': 0,
          'pendingTitles': [],
        });
      } catch(e) {}
      return;
    }

    final int completedCount = allDayTodos.where((t) => t.isDone).length;
    final int pendingCount = totalCount - completedCount;

    final List<String> pendingTitles = allDayTodos
        .where((t) => !t.isDone)
        .take(5)
        .map((t) => t.title)
        .toList();

    try {
      await _channel.invokeMethod('showOngoingNotification', {
        'totalCount': totalCount,
        'completedCount': completedCount,
        'pendingCount': pendingCount,
        'pendingTitles': pendingTitles,
      });
    } catch (e) {
      print("更新全天待办通知失败: $e");
    }
  }

  // 2. 即将开始的特定时间待办通知 (类似课程提醒)
  static Future<void> showUpcomingTodoNotification(TodoItem todo) async {
    try {
      // 🚀 修正：优先使用 createdDate，兼容旧数据 fallback 到 createdAt
      String timeStr = DateFormat('HH:mm').format(DateTime.fromMillisecondsSinceEpoch(todo.createdDate ?? todo.createdAt));
      if (todo.dueDate != null) {
        timeStr += " - ${DateFormat('HH:mm').format(todo.dueDate!)}";
      }

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