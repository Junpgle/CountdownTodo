import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'models.dart'; // 确保这个路径与你的项目结构一致

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

  static Future<void> updateTodoNotification(List<TodoItem> todos) async {
    final int totalCount = todos.length;

    // 如果没有任务，取消通知
    if (totalCount == 0) {
      await cancelNotification();
      return;
    }

    final int completedCount = todos.where((t) => t.isDone).length;
    final int pendingCount = totalCount - completedCount;

    // 筛选未完成的任务标题
    final List<String> pendingTitles = todos
        .where((t) => !t.isDone)
        .take(5)
        .map((t) => t.title)
        .toList();

    try {
      await _channel.invokeMethod('showOngoingNotification', {
        // 不传 type，默认走原生代码里的 else (待办事项逻辑)
        'totalCount': totalCount,
        'completedCount': completedCount,
        'pendingCount': pendingCount,
        'pendingTitles': pendingTitles,
      });
    } catch (e) {
      print("更新待办通知失败: $e");
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