import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'models.dart';

class NotificationService {
  static final FlutterLocalNotificationsPlugin _notificationsPlugin =
  FlutterLocalNotificationsPlugin();

  // 通道 ID
  static const String _channelId = 'todo_live_activity';
  static const String _channelName = '待办实时活动';
  static const String _channelDesc = '显示未完成的待办事项';

  // 通知的唯一 ID，保持不变以实现"更新"而不是"新增"
  static const int _notificationId = 888;

  static Future<void> init() async {
    // Android 初始化设置
    const AndroidInitializationSettings initializationSettingsAndroid =
    AndroidInitializationSettings('@mipmap/ic_launcher');

    // 综合初始化设置
    const InitializationSettings initializationSettings =
    InitializationSettings(android: initializationSettingsAndroid);

    await _notificationsPlugin.initialize(initializationSettings);
  }

  // 更新待办通知
  static Future<void> updateTodoNotification(List<TodoItem> todos) async {
    // 筛选未完成的任务
    final pendingTodos = todos.where((t) => !t.isDone).toList();
    final count = pendingTodos.length;

    // 如果没有待办，取消通知
    if (count == 0) {
      await _notificationsPlugin.cancel(_notificationId);
      return;
    }

    // 构建大文本样式 (展开后显示的内容)
    // 类似于 iOS 实时活动的展开效果
    StringBuffer bodyBuffer = StringBuffer();
    for (int i = 0; i < pendingTodos.length; i++) {
      bodyBuffer.writeln("${i + 1}. ${pendingTodos[i].title}");
    }
    String bigText = bodyBuffer.toString().trim();

    // Android 通知详情
    AndroidNotificationDetails androidPlatformChannelSpecifics =
    AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDesc,
      importance: Importance.low, // 设置为低，避免每次更新都发出声音/震动
      priority: Priority.low,
      ongoing: true, // 设置为常驻，用户无法划掉 (类似实时活动/前台服务)
      autoCancel: false,
      styleInformation: BigTextStyleInformation(
        bigText,
        contentTitle: '当前有 $count 个待办未完成',
        htmlFormatBigText: true,
        htmlFormatContentTitle: true,
      ),
    );

    NotificationDetails platformChannelSpecifics =
    NotificationDetails(android: androidPlatformChannelSpecifics);

    await _notificationsPlugin.show(
      _notificationId,
      '待办清单', // 标题
      '还有 $count 个任务待处理 (下拉查看详情)', // 收起时的简略内容
      platformChannelSpecifics,
    );
  }
}