import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:intl/intl.dart';
import '../models.dart';

class NotificationService {
  static const MethodChannel _channel =
      MethodChannel('com.math_quiz.junpgle.com.math_quiz_app/notifications');

  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static Future<void> init() async {
    if (!Platform.isAndroid && !Platform.isIOS && !Platform.isWindows) return;

    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const WindowsInitializationSettings initializationSettingsWindows =
        WindowsInitializationSettings(
      appName: 'MathQuizApp',
      appUserModelId: 'com.math_quiz.junpgle.com.math_quiz_app',
      guid: 'a1b2c3d4-e5f6-7a8b-9c0d-e1f2a3b4c5d6',
    );

    const InitializationSettings initializationSettings =
        InitializationSettings(
      android: initializationSettingsAndroid,
      windows: initializationSettingsWindows,
    );

    await _plugin.initialize(settings: initializationSettings);
  }

  static bool _isSameDay(DateTime date1, DateTime date2) {
    return date1.year == date2.year &&
        date1.month == date2.month &&
        date1.day == date2.day;
  }

  static Future<void> showCourseLiveActivity({
    required String courseName,
    required String room,
    required String timeStr,
    required String teacher,
  }) async {
    if (!Platform.isAndroid && !Platform.isIOS && !Platform.isWindows) return;

    if (Platform.isWindows) {
      await _plugin.show(
        id: courseName.hashCode,
        title: '📚 上课提醒: $courseName',
        body: '$timeStr | 教室: $room | $teacher',
        notificationDetails:
            const NotificationDetails(windows: WindowsNotificationDetails()),
      );
      return;
    }

    try {
      await _channel.invokeMethod('showOngoingNotification', {
        'type': 'course',
        'courseName': courseName,
        'room': room,
        'timeStr': timeStr,
        'teacher': teacher,
      });
    } catch (e) {
      debugPrint("更新课程通知失败: $e");
    }
  }

  static Future<void> updateQuizNotification({
    required int currentIndex,
    required int totalCount,
    required String questionText,
    required bool isOver,
    int score = 0,
  }) async {
    if (!Platform.isAndroid && !Platform.isIOS) return;

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
      debugPrint("更新测验通知失败: $e");
    }
  }

  static Future<void> updateTodoNotification(List<TodoItem> todos) async {
    if (!Platform.isAndroid && !Platform.isIOS) return;

    final DateTime now = DateTime.now();
    final List<TodoItem> todayAllDayTodos = todos.where((t) {
      if (t.dueDate == null) return false;
      final todoType = _detectTodoType(t.title);
      if (todoType != 'default') return false;
      DateTime localDueDate = t.dueDate!.toLocal();
      if (!_isSameDay(localDueDate, now)) return false;
      DateTime startDate = DateTime.fromMillisecondsSinceEpoch(
              t.createdDate ?? t.createdAt,
              isUtc: true)
          .toLocal();
      return startDate.hour == 0 &&
          startDate.minute == 0 &&
          localDueDate.hour == 23 &&
          localDueDate.minute == 59;
    }).toList();

    final int totalCount = todayAllDayTodos.length;
    if (totalCount == 0 || todayAllDayTodos.every((t) => t.isDone)) {
      try {
        await _channel.invokeMethod('showOngoingNotification', {
          'type': 'todo_summary',
          'totalCount': 0,
          'completedCount': 0,
          'pendingCount': 0,
          'pendingTitles': [],
        });
      } catch (e) {}
      return;
    }

    final int completedCount = todayAllDayTodos.where((t) => t.isDone).length;
    final int pendingCount = totalCount - completedCount;
    final List<TodoItem> pendingItems =
        todayAllDayTodos.where((t) => !t.isDone).take(5).toList();

    try {
      await _channel.invokeMethod('showOngoingNotification', {
        'type': 'todo_summary',
        'totalCount': totalCount,
        'completedCount': completedCount,
        'pendingCount': pendingCount,
        'pendingTitles': pendingItems.map((t) => t.title).toList(),
        'pendingRemarks':
            pendingItems.map((t) => t.remark?.trim() ?? '').toList(),
      });
    } catch (e) {
      debugPrint("更新今日待办通知失败: $e");
    }
  }

  static String _detectTodoType(String title) {
    final lowerTitle = title.toLowerCase();
    debugPrint("🔍 _detectTodoType 检测: title=$title, lowerTitle=$lowerTitle");
    if (lowerTitle.contains('快递') ||
        lowerTitle.contains('取件') ||
        lowerTitle.contains('顺丰') ||
        lowerTitle.contains('京东') ||
        lowerTitle.contains('菜鸟') ||
        lowerTitle.contains('中通') ||
        lowerTitle.contains('圆通') ||
        lowerTitle.contains('韵达') ||
        lowerTitle.contains('申通')) {
      debugPrint("🔍 匹配到: delivery");
      return 'delivery';
    } else if (lowerTitle.contains('奶茶') ||
        lowerTitle.contains('咖啡') ||
        lowerTitle.contains('古茗') ||
        lowerTitle.contains('茶百道') ||
        lowerTitle.contains('蜜雪冰城') ||
        lowerTitle.contains('瑞幸') ||
        lowerTitle.contains('星巴克') ||
        lowerTitle.contains('库迪') ||
        lowerTitle.contains('coco') ||
        lowerTitle.contains('一点点')) {
      debugPrint("🔍 匹配到: cafe");
      return 'cafe';
    } else if (lowerTitle.contains('海底捞') ||
        lowerTitle.contains('太二') ||
        lowerTitle.contains('外婆家') ||
        lowerTitle.contains('西贝') ||
        lowerTitle.contains('必胜客') ||
        lowerTitle.contains('堂食') ||
        lowerTitle.contains('餐饮')) {
      debugPrint("🔍 匹配到: restaurant");
      return 'restaurant';
    } else if (lowerTitle.contains('取餐') ||
        lowerTitle.contains('外卖') ||
        lowerTitle.contains('肯德基') ||
        lowerTitle.contains('麦当劳') ||
        lowerTitle.contains('KFC')) {
      debugPrint("🔍 匹配到: food");
      return 'food';
    }
    debugPrint("🔍 匹配到: default");
    return 'default';
  }

  static Future<void> showUpcomingTodoNotification(TodoItem todo) async {
    if (!Platform.isAndroid && !Platform.isIOS && !Platform.isWindows) return;
    if (todo.dueDate == null) return;
    if (!_isSameDay(todo.dueDate!.toLocal(), DateTime.now())) return;

    DateTime startDate = DateTime.fromMillisecondsSinceEpoch(
            todo.createdDate ?? todo.createdAt,
            isUtc: true)
        .toLocal();
    String timeStr =
        "${DateFormat('HH:mm').format(startDate)} - ${DateFormat('HH:mm').format(todo.dueDate!.toLocal())}";
    final todoType = _detectTodoType(todo.title);
    final isSpecialTodo = todoType != 'default';
    final notifId = isSpecialTodo ? todo.id.hashCode : null;

    debugPrint(
        "🔔 showUpcomingTodoNotification: title=${todo.title}, todoId=${todo.id}, hashCode=${todo.id.hashCode}, todoType=$todoType, isSpecialTodo=$isSpecialTodo, notifId=$notifId");

    if (Platform.isWindows) {
      await _plugin.show(
        id: todo.id.hashCode,
        title: '🔔 待办提醒: ${todo.title}',
        body: '$timeStr\n${todo.remark ?? ''}',
        notificationDetails:
            const NotificationDetails(windows: WindowsNotificationDetails()),
      );
      return;
    }

    try {
      await _channel.invokeMethod('showOngoingNotification', {
        'type': isSpecialTodo ? 'special_todo' : 'upcoming_todo',
        'todoTitle': todo.title,
        'todoRemark': todo.remark ?? '',
        'timeStr': timeStr,
        'todoType': todoType,
        'notificationId': notifId,
      });
      debugPrint(
          "✅ 通知发送成功: type=${isSpecialTodo ? 'special_todo' : 'upcoming_todo'}, title=${todo.title}, notifId=$notifId");
    } catch (e) {
      debugPrint("更新即将开始的待办通知失败: $e");
    }
  }

  static Future<void> updatePomodoroNotification({
    required int remainingSeconds,
    required String phase,
    String? todoTitle,
    int currentCycle = 1,
    int totalCycles = 4,
    List<String> tagNames = const [],
    String alertKey = '',
  }) async {
    if (!Platform.isAndroid && !Platform.isIOS) return;

    final String countdownStr;
    if (remainingSeconds > 60) {
      countdownStr = '${(remainingSeconds / 60).ceil()} 分钟';
    } else {
      countdownStr =
          '${(remainingSeconds ~/ 60).toString().padLeft(2, '0')}:${(remainingSeconds % 60).toString().padLeft(2, '0')}';
    }

    try {
      await _channel.invokeMethod('showOngoingNotification', {
        'type': 'pomodoro',
        'phase': phase,
        'countdown': countdownStr,
        'todoTitle': todoTitle ?? '',
        'currentCycle': currentCycle,
        'totalCycles': totalCycles,
        'tagNames': tagNames,
        'alertKey': alertKey,
      });
    } catch (e) {}
  }

  static Future<void> sendPomodoroEndAlert({
    required String alertKey,
    String? todoTitle,
    bool isBreak = false,
  }) async {
    if (!Platform.isAndroid && !Platform.isIOS && !Platform.isWindows) return;

    if (Platform.isWindows) {
      final title = isBreak ? '☕ 休息结束' : '🍅 专注完成';
      final body = todoTitle?.isNotEmpty == true
          ? '任务 "$todoTitle" 阶段已结束'
          : (isBreak ? '准备开始下一轮专注' : '请休息一下吧');

      await _plugin.show(
        id: alertKey.hashCode,
        title: title,
        body: body,
        notificationDetails:
            const NotificationDetails(windows: WindowsNotificationDetails()),
      );
      return;
    }

    try {
      await _channel.invokeMethod('showOngoingNotification', {
        'type': 'pomodoro_end',
        'alertKey': alertKey,
        'todoTitle': todoTitle ?? '',
        'isBreak': isBreak,
      });
    } catch (e) {
      debugPrint('番茄钟结束提醒失败: $e');
    }
  }

  static Future<void> cancelNotification() async {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    try {
      await _channel.invokeMethod('cancelNotification');
    } catch (e) {}
  }

  /// 取消特定 ID 的特殊待办通知
  /// [notifId] 是通知的 ID
  static Future<void> cancelSpecialTodoNotification(int notifId) async {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    try {
      await _channel.invokeMethod(
          'cancelSpecialTodoNotification', {'notificationId': notifId});
    } catch (e) {}
  }

  static Future<void> scheduleReminders(
      List<Map<String, dynamic>> reminders) async {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    if (reminders.isEmpty) return;
    try {
      final json = reminders
          .map((r) => '{"triggerAtMs":${r['triggerAtMs']},'
              '"title":${_jsonStr(r['title'])},"text":${_jsonStr(r['text'])},"notifId":${r['notifId']}}')
          .join(',');
      await _channel
          .invokeMethod('scheduleReminders', {'remindersJson': '[$json]'});
    } catch (e) {}
  }

  static Future<void> cancelReminder(int notifId) async {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    try {
      await _channel.invokeMethod('cancelReminder', {'notifId': notifId});
    } catch (e) {}
  }

  static Future<bool> checkExactAlarmPermission() async {
    if (!Platform.isAndroid && !Platform.isIOS) return true;
    try {
      return await _channel.invokeMethod<bool>('checkExactAlarmPermission') ??
          true;
    } catch (_) {
      return true;
    }
  }

  static Future<void> openExactAlarmSettings() async {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    try {
      await _channel.invokeMethod('openExactAlarmSettings');
    } catch (e) {}
  }

  static String _jsonStr(dynamic v) {
    return '"${(v ?? '').toString().replaceAll('\\', '\\\\').replaceAll('"', '\\"')}"';
  }

  // ==========================================
  // 📸 图片识别待办通知
  // ==========================================

  static const int NOTIF_ID_TODO_RECOGNIZE = 9001;

  /// 显示图片识别进度通知（实时通知）
  /// [currentAttempt] 当前尝试次数（从1开始）
  /// [maxAttempts] 最大尝试次数
  /// [status] 当前状态描述
  static Future<void> showTodoRecognizeProgress({
    required int currentAttempt,
    required int maxAttempts,
    required String status,
  }) async {
    if (!Platform.isAndroid && !Platform.isIOS && !Platform.isWindows) return;

    final title = '🔍 图片识别待办中...';
    final body = '第$currentAttempt/$maxAttempts次尝试 | $status';

    if (Platform.isWindows) {
      await _plugin.show(
        id: NOTIF_ID_TODO_RECOGNIZE,
        title: title,
        body: body,
        notificationDetails:
            const NotificationDetails(windows: WindowsNotificationDetails()),
      );
      return;
    }

    try {
      final progress =
          maxAttempts > 0 ? (currentAttempt * 100) ~/ maxAttempts : 0;
      await _channel.invokeMethod('showOngoingNotification', {
        'type': 'todo_recognize_progress',
        'currentAttempt': currentAttempt,
        'maxAttempts': maxAttempts,
        'status': status,
        'notificationId': NOTIF_ID_TODO_RECOGNIZE,
        'progress': progress,
      });
    } catch (e) {
      debugPrint("更新图片识别进度通知失败: $e");
    }
  }

  /// 显示图片识别成功通知（实时通知，点击进入确认页面）
  /// [todoCount] 识别到的待办数量
  static Future<void> showTodoRecognizeSuccess({
    required int todoCount,
  }) async {
    if (!Platform.isAndroid && !Platform.isIOS && !Platform.isWindows) return;

    final title = '✅ 图片识别完成';
    final body = '发现$todoCount个待办事项，点击查看详情';

    if (Platform.isWindows) {
      await _plugin.show(
        id: NOTIF_ID_TODO_RECOGNIZE,
        title: title,
        body: body,
        notificationDetails:
            const NotificationDetails(windows: WindowsNotificationDetails()),
      );
      return;
    }

    try {
      await _channel.invokeMethod('showOngoingNotification', {
        'type': 'todo_recognize_success',
        'todoCount': todoCount,
        'notificationId': NOTIF_ID_TODO_RECOGNIZE,
      });
    } catch (e) {
      debugPrint("发送图片识别成功通知失败: $e");
    }
  }

  /// 显示图片识别失败通知（实时通知）
  /// [errorMsg] 错误信息
  static Future<void> showTodoRecognizeFailed({
    required String errorMsg,
  }) async {
    if (!Platform.isAndroid && !Platform.isIOS && !Platform.isWindows) return;

    final title = '❌ 图片识别失败';
    final body =
        errorMsg.length > 50 ? '${errorMsg.substring(0, 50)}...' : errorMsg;

    if (Platform.isWindows) {
      await _plugin.show(
        id: NOTIF_ID_TODO_RECOGNIZE,
        title: title,
        body: body,
        notificationDetails:
            const NotificationDetails(windows: WindowsNotificationDetails()),
      );
      return;
    }

    try {
      await _channel.invokeMethod('showOngoingNotification', {
        'type': 'todo_recognize_failed',
        'errorMsg': errorMsg,
        'notificationId': NOTIF_ID_TODO_RECOGNIZE,
      });
    } catch (e) {
      debugPrint("发送图片识别失败通知失败: $e");
    }
  }

  /// 取消图片识别相关通知
  static Future<void> cancelTodoRecognizeNotification() async {
    if (!Platform.isAndroid && !Platform.isIOS && !Platform.isWindows) return;

    if (Platform.isWindows) {
      await _plugin.cancel(id: NOTIF_ID_TODO_RECOGNIZE);
      return;
    }

    try {
      await _channel.invokeMethod('cancelTodoRecognizeNotification');
    } catch (e) {}
  }
}
