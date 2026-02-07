import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'models.dart';

class NotificationService {
  // 定义与原生通信的通道名称
  static const MethodChannel _channel =
  MethodChannel('com.math_quiz.junpgle.com.math_quiz_app/notifications');

  // 初始化方法
  static Future<void> init() async {
    // 依然保留 flutter_local_notifications 的初始化，防止与其他功能冲突
    final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();
    const AndroidInitializationSettings initializationSettingsAndroid =
    AndroidInitializationSettings('@mipmap/ic_launcher');
    const InitializationSettings initializationSettings =
    InitializationSettings(android: initializationSettingsAndroid);

    // 修复：适配 flutter_local_notifications 20.0.0+，必须使用命名参数 'settings'
    await flutterLocalNotificationsPlugin.initialize(settings: initializationSettings);
  }

  static Future<void> updateTodoNotification(List<TodoItem> todos) async {
    final int totalCount = todos.length;

    // 如果没有任务，调用原生方法取消通知
    if (totalCount == 0) {
      try {
        await _channel.invokeMethod('cancelNotification');
      } catch (e) {
        print("原生取消通知失败: $e");
      }
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
      // 调用原生 Kotlin 方法
      await _channel.invokeMethod('showOngoingNotification', {
        'totalCount': totalCount,
        'completedCount': completedCount,
        'pendingCount': pendingCount,
        'pendingTitles': pendingTitles,
      });
    } catch (e) {
      print("调用原生通知失败: $e");
    }
  }
}