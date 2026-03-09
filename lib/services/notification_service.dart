import 'package:flutter/foundation.dart';
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
      debugPrint("更新课程通知失败: $e");
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
      debugPrint("更新测验通知失败: $e");
    }
  }

  // --- 待办事项 ---

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
      } catch (e) {
        debugPrint("清除待办通知失败: $e");
      }
      return;
    }

    final int completedCount = todayAllDayTodos.where((t) => t.isDone).length;
    final int pendingCount = totalCount - completedCount;

    // 获取前5个未完成的任务（标题 + 备注）
    final List<TodoItem> pendingItems = todayAllDayTodos
        .where((t) => !t.isDone)
        .take(5)
        .toList();
    final List<String> pendingTitles = pendingItems.map((t) => t.title).toList();
    final List<String> pendingRemarks = pendingItems
        .map((t) => t.remark?.trim() ?? '')
        .toList();

    try {
      await _channel.invokeMethod('showOngoingNotification', {
        'type': 'todo_summary',
        'totalCount': totalCount,
        'completedCount': completedCount,
        'pendingCount': pendingCount,
        'pendingTitles': pendingTitles,
        'pendingRemarks': pendingRemarks,
      });
    } catch (e) {
      debugPrint("更新今日待办通知失败: $e");
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
        'todoRemark': todo.remark ?? '',   // 📝 备注作为副标题
        'timeStr': timeStr,
      });
    } catch (e) {
      debugPrint("更新即将开始的待办通知失败: $e");
    }
  }

  // 3. 番茄钟实时通知
  /// [remainingSeconds] 剩余秒数
  /// [phase] 'focusing' | 'breaking'
  /// [todoTitle] 当前绑定的任务标题（可选）
  /// [currentCycle] 当前第几轮
  /// [totalCycles] 总轮数
  /// [tagNames] 已选标签名称列表
  /// [alertKey] 非空时触发一次性普通提醒（仅开始事件传入，如 "pomo_start_<targetEndMs>"）
  static Future<void> updatePomodoroNotification({
    required int remainingSeconds,
    required String phase,
    String? todoTitle,
    int currentCycle = 1,
    int totalCycles = 4,
    List<String> tagNames = const [],
    String alertKey = '',
  }) async {
    // >60s 只显示分钟，最后60s 才显示 MM:SS（降低通知刷新频率的配套格式）
    final String countdownStr;
    if (remainingSeconds > 60) {
      final mins = (remainingSeconds / 60).ceil();
      countdownStr = '$mins 分钟';
    } else {
      final mins = remainingSeconds ~/ 60;
      final secs = remainingSeconds % 60;
      countdownStr =
          '${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
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
        'alertKey': alertKey, // 空字符串 = 不触发普通提醒
      });
    } catch (e) {
      debugPrint('更新番茄钟通知失败: $e');
    }
  }

  // 4. 番茄钟结束一次性提醒（专注完成 / 休息结束）
  /// [alertKey] 去重 key，如 "pomo_end_<targetEndMs>"
  /// [todoTitle] 绑定的任务标题（可选）
  /// [isBreak] true = 休息结束，false = 专注完成
  static Future<void> sendPomodoroEndAlert({
    required String alertKey,
    String? todoTitle,
    bool isBreak = false,
  }) async {
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

  // --- 通用方法 ---

  static Future<void> cancelNotification() async {
    try {
      await _channel.invokeMethod('cancelNotification');
    } catch (e) {
      debugPrint("取消通知失败: $e");
    }
  }

  // ── 保活：精确 Alarm 调度 ──────────────────────────────────────

  /// 向原生注册一批提醒 Alarm（会覆盖上次的列表）。
  /// [reminders] 每项包含：
  ///   - triggerAtMs : int   触发时间（UTC 毫秒时间戳）
  ///   - title       : String 通知标题
  ///   - text        : String 通知正文
  ///   - notifId     : int   通知 ID（唯一，用于去重 / 取消）
  static Future<void> scheduleReminders(
      List<Map<String, dynamic>> reminders) async {
    if (reminders.isEmpty) return;
    try {
      final json = reminders
          .map((r) =>
              '{"triggerAtMs":${r['triggerAtMs']},'
              '"title":${_jsonStr(r['title'])},'
              '"text":${_jsonStr(r['text'])},'
              '"notifId":${r['notifId']}}')
          .join(',');
      await _channel.invokeMethod('scheduleReminders', {
        'remindersJson': '[$json]',
      });
    } catch (e) {
      debugPrint('scheduleReminders 失败: $e');
    }
  }

  /// 取消某个 Alarm（通过 notifId 定定位）
  static Future<void> cancelReminder(int notifId) async {
    try {
      await _channel.invokeMethod('cancelReminder', {'notifId': notifId});
    } catch (e) {
      debugPrint('cancelReminder 失败: $e');
    }
  }

  /// 检查 Android 12+ 精确闹钟权限（true = 已授权，false = 需要引导用户设置）
  static Future<bool> checkExactAlarmPermission() async {
    try {
      return await _channel.invokeMethod<bool>('checkExactAlarmPermission') ?? true;
    } catch (_) {
      return true;
    }
  }

  /// 跳转到系统精确闹钟权限设置页（Android 12+）
  static Future<void> openExactAlarmSettings() async {
    try {
      await _channel.invokeMethod('openExactAlarmSettings');
    } catch (e) {
      debugPrint('openExactAlarmSettings 失败: $e');
    }
  }

  static String _jsonStr(dynamic v) {
    final s = (v ?? '').toString()
        .replaceAll('\\', '\\\\')
        .replaceAll('"', '\\"');
    return '"$s"';
  }
}

