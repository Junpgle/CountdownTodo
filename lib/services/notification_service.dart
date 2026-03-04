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
    // 需求：全部答题结束后消失
    // 如果 isOver 为 true，直接取消通知
    if (isOver) {
      await cancelNotification();
      return;
    }

    try {
      // 调用原生方法更新进度
      await _channel.invokeMethod('showOngoingNotification', {
        'type': 'quiz', // 标记为测验类型
        'currentIndex': currentIndex,
        'totalCount': totalCount,
        'questionText': questionText,
        'isOver': false, // 因为结束后我们直接 cancel 了，所以这里传 false 即可
        'score': score,
      });
    } catch (e) {
      print("更新测验通知失败: $e");
    }
  }

  // --- 待办事项 (Todo) 通知逻辑 ---

  // 1. 平常只展示未完成的”全天”待办
  static Future<void> updateTodoNotification(List<TodoItem> todos) async {
    // 过滤出“今天截止”的“全天待办”（包括跨天但今天截止的全天待办）
    final DateTime now = DateTime.now();

    final List<TodoItem> allDayTodos = todos.where((t) {
      if (t.dueDate == null) return false;

      // 1. 判断是否是全天属性 (00:00 开始, 23:59 结束)
      bool isAllDayAttr = t.createdAt.hour == 0 && t.createdAt.minute == 0 &&
          t.dueDate!.hour == 23 && t.dueDate!.minute == 59;

      // 2. 判断截止日期是否是今天
      bool isDueToday = t.dueDate!.year == now.year &&
          t.dueDate!.month == now.month &&
          t.dueDate!.day == now.day;

      return isAllDayAttr && isDueToday;
    }).toList();

    final int totalCount = allDayTodos.length;

    // 如果没有未完成的全天任务，取消（待办类的）通知
    // 注意：这里可能和即将开始的具体时间待办通知冲突，需要在调用端妥善处理优先级
    if (totalCount == 0 || allDayTodos.every((t) => t.isDone)) {
      // 这里的取消策略需要谨慎，如果当前正在展示“即将开始的待办”或“课程”，
      // 贸然 cancel 可能会把它们也取消掉。
      // 最好的做法是让原生代码知道当前通知的类型，只有在当前是"普通待办汇总"时才取消。
      // 但为了简单起见，如果我们要严格区分，可能需要在原生端也增加一个 `type` 参数。
      // 目前，如果我们假设原生代码中的 else 分支（默认分支）是用来显示这个汇总的，
      // 我们可以在原生端加一个检查。
      // 这里暂时只发一个空的通知去“抹除”之前的待办汇总。
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

    // 筛选未完成的任务标题
    final List<String> pendingTitles = allDayTodos
        .where((t) => !t.isDone)
        .take(5)
        .map((t) => t.title)
        .toList();

    try {
      await _channel.invokeMethod('showOngoingNotification', {
        // 不传 type，默认走原生代码里的 else (待办事项汇总逻辑)
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
      String timeStr = DateFormat('HH:mm').format(todo.createdAt);
      if (todo.dueDate != null) {
        timeStr += " - ${DateFormat('HH:mm').format(todo.dueDate!)}";
      }

      await _channel.invokeMethod('showOngoingNotification', {
        'type': 'upcoming_todo', // 新增一种类型，需要在原生 Android 代码中处理
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