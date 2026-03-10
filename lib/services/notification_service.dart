import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:intl/intl.dart';
import '../models.dart';

class NotificationService {
  // ── Android/iOS 专属的原生通道 (处理常驻通知、Live Activity等) ──
  static const MethodChannel _channel =
  MethodChannel('com.math_quiz.junpgle.com.math_quiz_app/notifications');

  // ── Windows 等桌面端使用的跨平台通知插件 ──
  static final FlutterLocalNotificationsPlugin _plugin =
  FlutterLocalNotificationsPlugin();

  // ===========================================================================
  // 初始化
  // ===========================================================================
  static Future<void> init() async {
    // 仅在支持的平台上初始化
    if (!Platform.isAndroid && !Platform.isIOS && !Platform.isWindows) return;

    // Android 初始化配置
    const AndroidInitializationSettings initializationSettingsAndroid =
    AndroidInitializationSettings('@mipmap/ic_launcher');

    // 🚀 修复点：Windows 初始化配置，新版要求传入 appName, appUserModelId, guid
    const WindowsInitializationSettings initializationSettingsWindows =
    WindowsInitializationSettings(
      appName: 'MathQuizApp',
      appUserModelId: 'com.math_quiz.junpgle.com.math_quiz_app',
      guid: 'a1b2c3d4-e5f6-7a8b-9c0d-e1f2a3b4c5d6', // 需填入一个合法的 UUID
    );

    const InitializationSettings initializationSettings = InitializationSettings(
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

  // ===========================================================================
  // 1. 课程提醒 (事件型：Windows 弹窗，移动端走原生通道)
  // ===========================================================================
  static Future<void> showCourseLiveActivity({
    required String courseName,
    required String room,
    required String timeStr,
    required String teacher,
  }) async {
    if (!Platform.isAndroid && !Platform.isIOS && !Platform.isWindows) return;

    // 🚀 Windows 端逻辑：发出右下角 Toast 弹窗
    if (Platform.isWindows) {
      // 🚀 修复点：新版 show 方法强制使用命名参数
      await _plugin.show(
        id: courseName.hashCode, // 简单的去重ID
        title: '📚 上课提醒: $courseName',
        body: '$timeStr | 教室: $room | $teacher',
        notificationDetails: const NotificationDetails(windows: WindowsNotificationDetails()),
      );
      return; // Windows 处理完毕，直接返回
    }

    // 📱 Android / iOS 端逻辑：调用你写好的原生通道
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

  // ===========================================================================
  // 2. 测验通知 (常驻型：仅移动端支持，Windows 直接拦截不处理)
  // ===========================================================================
  static Future<void> updateQuizNotification({
    required int currentIndex,
    required int totalCount,
    required String questionText,
    required bool isOver,
    int score = 0,
  }) async {
    // 拦截 Windows，不让它打扰用户
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

  // ===========================================================================
  // 3. 今日待办概览 (常驻型：仅移动端支持，Windows PC端有自己的悬浮窗)
  // ===========================================================================
  static Future<void> updateTodoNotification(List<TodoItem> todos) async {
    // 拦截 Windows
    if (!Platform.isAndroid && !Platform.isIOS) return;

    final DateTime now = DateTime.now();
    final List<TodoItem> todayAllDayTodos = todos.where((t) {
      if (t.dueDate == null) return false;
      DateTime localDueDate = t.dueDate!.toLocal();
      if (!_isSameDay(localDueDate, now)) return false;
      DateTime startDate = DateTime.fromMillisecondsSinceEpoch(
          t.createdDate ?? t.createdAt,
          isUtc: true).toLocal();
      return startDate.hour == 0 && startDate.minute == 0 &&
          localDueDate.hour == 23 && localDueDate.minute == 59;
    }).toList();

    final int totalCount = todayAllDayTodos.length;
    if (totalCount == 0 || todayAllDayTodos.every((t) => t.isDone)) {
      try {
        await _channel.invokeMethod('showOngoingNotification', {
          'type': 'todo_summary', 'totalCount': 0, 'completedCount': 0, 'pendingCount': 0, 'pendingTitles': [],
        });
      } catch (e) {}
      return;
    }

    final int completedCount = todayAllDayTodos.where((t) => t.isDone).length;
    final int pendingCount = totalCount - completedCount;
    final List<TodoItem> pendingItems = todayAllDayTodos.where((t) => !t.isDone).take(5).toList();

    try {
      await _channel.invokeMethod('showOngoingNotification', {
        'type': 'todo_summary',
        'totalCount': totalCount,
        'completedCount': completedCount,
        'pendingCount': pendingCount,
        'pendingTitles': pendingItems.map((t) => t.title).toList(),
        'pendingRemarks': pendingItems.map((t) => t.remark?.trim() ?? '').toList(),
      });
    } catch (e) {
      debugPrint("更新今日待办通知失败: $e");
    }
  }

  // ===========================================================================
  // 4. 特定时间待办提醒 (事件型：Windows 弹窗，移动端走原生通道)
  // ===========================================================================
  static Future<void> showUpcomingTodoNotification(TodoItem todo) async {
    if (!Platform.isAndroid && !Platform.isIOS && !Platform.isWindows) return;
    if (todo.dueDate == null) return;
    if (!_isSameDay(todo.dueDate!.toLocal(), DateTime.now())) return;

    DateTime startDate = DateTime.fromMillisecondsSinceEpoch(
        todo.createdDate ?? todo.createdAt, isUtc: true).toLocal();
    String timeStr = "${DateFormat('HH:mm').format(startDate)} - ${DateFormat('HH:mm').format(todo.dueDate!.toLocal())}";

    // 🚀 Windows 端逻辑：发出右下角 Toast 弹窗
    if (Platform.isWindows) {
      // 🚀 修复点：使用新版命名参数
      await _plugin.show(
        id: todo.id.hashCode,
        title: '🔔 待办提醒: ${todo.title}',
        body: '$timeStr\n${todo.remark ?? ''}',
        notificationDetails: const NotificationDetails(windows: WindowsNotificationDetails()),
      );
      return; // 结束，不执行下方的 Android 逻辑
    }

    // 📱 Android / iOS 端逻辑
    try {
      await _channel.invokeMethod('showOngoingNotification', {
        'type': 'upcoming_todo',
        'todoTitle': todo.title,
        'todoRemark': todo.remark ?? '',
        'timeStr': timeStr,
      });
    } catch (e) {
      debugPrint("更新即将开始的待办通知失败: $e");
    }
  }

  // ===========================================================================
  // 5. 番茄钟实时倒计时 (常驻型：仅移动端支持，拦截 Windows 以免疯狂弹窗)
  // ===========================================================================
  static Future<void> updatePomodoroNotification({
    required int remainingSeconds,
    required String phase,
    String? todoTitle,
    int currentCycle = 1,
    int totalCycles = 4,
    List<String> tagNames = const [],
    String alertKey = '',
  }) async {
    // 拦截 Windows！防止桌面右下角每秒叮叮响。PC端倒计时由 C++ Overlay 负责显示。
    if (!Platform.isAndroid && !Platform.isIOS) return;

    final String countdownStr;
    if (remainingSeconds > 60) {
      countdownStr = '${(remainingSeconds / 60).ceil()} 分钟';
    } else {
      countdownStr = '${(remainingSeconds ~/ 60).toString().padLeft(2, '0')}:${(remainingSeconds % 60).toString().padLeft(2, '0')}';
    }

    try {
      await _channel.invokeMethod('showOngoingNotification', {
        'type': 'pomodoro', 'phase': phase, 'countdown': countdownStr,
        'todoTitle': todoTitle ?? '', 'currentCycle': currentCycle, 'totalCycles': totalCycles, 'tagNames': tagNames, 'alertKey': alertKey,
      });
    } catch (e) {}
  }

  // ===========================================================================
  // 6. 番茄钟结束提醒 (事件型：Windows 弹窗，移动端走原生通道)
  // ===========================================================================
  static Future<void> sendPomodoroEndAlert({
    required String alertKey,
    String? todoTitle,
    bool isBreak = false,
  }) async {
    if (!Platform.isAndroid && !Platform.isIOS && !Platform.isWindows) return;

    // 🚀 Windows 端逻辑：发出右下角 Toast 弹窗
    if (Platform.isWindows) {
      final title = isBreak ? '☕ 休息结束' : '🍅 专注完成';
      final body = todoTitle?.isNotEmpty == true
          ? '任务 "$todoTitle" 阶段已结束'
          : (isBreak ? '准备开始下一轮专注' : '请休息一下吧');

      // 🚀 修复点：使用新版命名参数
      await _plugin.show(
        id: alertKey.hashCode,
        title: title,
        body: body,
        notificationDetails: const NotificationDetails(windows: WindowsNotificationDetails()),
      );
      return; // 结束，不执行下方的 Android 逻辑
    }

    // 📱 Android / iOS 端逻辑
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

  // ===========================================================================
  // 通用方法与 Alarm (仅支持移动端)
  // ===========================================================================
  static Future<void> cancelNotification() async {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    try {
      await _channel.invokeMethod('cancelNotification');
    } catch (e) {}
  }

  static Future<void> scheduleReminders(List<Map<String, dynamic>> reminders) async {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    if (reminders.isEmpty) return;
    try {
      final json = reminders.map((r) => '{"triggerAtMs":${r['triggerAtMs']},'
          '"title":${_jsonStr(r['title'])},"text":${_jsonStr(r['text'])},"notifId":${r['notifId']}}').join(',');
      await _channel.invokeMethod('scheduleReminders', {'remindersJson': '[$json]'});
    } catch (e) {}
  }

  static Future<void> cancelReminder(int notifId) async {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    try { await _channel.invokeMethod('cancelReminder', {'notifId': notifId}); } catch (e) {}
  }

  static Future<bool> checkExactAlarmPermission() async {
    if (!Platform.isAndroid && !Platform.isIOS) return true;
    try { return await _channel.invokeMethod<bool>('checkExactAlarmPermission') ?? true; } catch (_) { return true; }
  }

  static Future<void> openExactAlarmSettings() async {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    try { await _channel.invokeMethod('openExactAlarmSettings'); } catch (e) {}
  }

  static String _jsonStr(dynamic v) {
    return '"${(v ?? '').toString().replaceAll('\\', '\\\\').replaceAll('"', '\\"')}"';
  }
}