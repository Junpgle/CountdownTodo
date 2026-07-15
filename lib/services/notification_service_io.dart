import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:intl/intl.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import '../models.dart';
import '../storage_service.dart';
import 'storage/app_settings_storage.dart';
import 'macos_pomodoro_status_bar_service.dart';
import 'todo_notification_policy.dart';

class NotificationService {
  static const MethodChannel _channel =
      MethodChannel('com.math_quiz.junpgle.com.math_quiz_app/notifications');

  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static Future<void>? _initializationFuture;
  static bool _initialized = false;

  static final Map<String, DateTime> _recentGenericNotifications = {};
  static final Set<String> _sentPomodoroEndAlertKeys = {};
  static final Set<String> _shownUpdateNotificationKeys = {};
  static StreamSubscription<MacIslandReminderAction>?
      _macReminderActionSubscription;

  // 集中式事件分发：所有原生 MethodChannel 调用统一由此广播
  static final StreamController<MethodCall> _eventCtrl =
      StreamController<MethodCall>.broadcast();
  static bool _channelBound = false;

  // 通用 pending 队列：仅在某 method 无 listener 时入队。
  static final Map<String, List<MethodCall>> _pendingEvents = {};
  // method 级 listener 计数
  static final Map<String, int> _listenerCounts = {};

  /// 尽早绑定原生 MethodChannel handler，应在 main() 中调用。
  /// 绑定完成后通知 native 侧可以开始发送 pending 事件。
  static Future<void> bindNativeChannel() async {
    _ensureChannelBound();
    try {
      await _channel.invokeMethod('notificationDartReady');
    } catch (_) {
      // Native notification calls are best-effort.
    }
  }

  /// 订阅指定 method 的通知事件。返回 StreamSubscription，dispose 时 cancel 即可。
  /// 注册时自动 replay 该 method 的 pending 事件。
  /// cancel 时自动递减 listener 计数，无需手动调用 unlisten。
  static StreamSubscription<MethodCall> listen(
    String method,
    void Function(MethodCall call) handler,
  ) {
    _ensureChannelBound();
    _listenerCounts[method] = (_listenerCounts[method] ?? 0) + 1;
    // replay 该 method 的 pending 事件
    final pending = _pendingEvents.remove(method);
    if (pending != null) {
      for (final call in pending) {
        handler(call);
      }
    }
    final inner = _eventCtrl.stream
        .where((call) => call.method == method)
        .listen(handler);
    return _TrackedSubscription(inner, method);
  }

  static void _ensureChannelBound() {
    if (_channelBound) return;
    _channelBound = true;
    _channel.setMethodCallHandler((call) async {
      // 仅在无 listener 时入队，避免已处理事件被重复 replay
      if ((_listenerCounts[call.method] ?? 0) == 0) {
        _pendingEvents.putIfAbsent(call.method, () => []).add(call);
      }
      _eventCtrl.add(call);
    });
  }

  // Dedupe keys for Windows all-day todo notifications: "todoId@yyyy-MM-dd"
  static final Set<String> _windowsAllDayTodoNotifiedKeys = <String>{};

  static const NotificationDetails _desktopNotificationDetails =
      NotificationDetails(
    windows: WindowsNotificationDetails(),
    macOS: DarwinNotificationDetails(),
  );

  static bool get _isDesktopSupported => Platform.isWindows || Platform.isMacOS;

  static Future<void> init() async {
    await ensureInitialized();
  }

  static Future<void> ensureInitialized() async {
    if (!Platform.isAndroid &&
        !Platform.isIOS &&
        !Platform.isWindows &&
        !Platform.isMacOS) {
      return;
    }
    if (_initialized) return;
    final existing = _initializationFuture;
    if (existing != null) return existing;

    final future = _initialize();
    _initializationFuture = future;
    return future;
  }

  static Future<String> getBrowserNotificationPermission() async => 'granted';

  static Future<bool> requestBrowserNotificationPermission() async => true;

  static Future<void> _initialize() async {
    tz.initializeTimeZones();

    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const WindowsInitializationSettings initializationSettingsWindows =
        WindowsInitializationSettings(
      appName: 'MathQuizApp',
      appUserModelId: 'com.math_quiz.junpgle.com.math_quiz_app',
      guid: 'a1b2c3d4-e5f6-7a8b-9c0d-e1f2a3b4c5d6',
    );

    const DarwinInitializationSettings initializationSettingsDarwin =
        DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const InitializationSettings initializationSettings =
        InitializationSettings(
      android: initializationSettingsAndroid,
      windows: initializationSettingsWindows,
      macOS: initializationSettingsDarwin,
    );

    try {
      await _plugin.initialize(settings: initializationSettings);
      _initialized = true;
      if (Platform.isMacOS) {
        await MacPomodoroStatusBarService.init();
        _macReminderActionSubscription ??=
            MacPomodoroStatusBarService.onReminderAction.listen(
          _handleMacIslandReminderAction,
        );
        final stored = await StorageService.getWindowsScheduledReminders();
        await MacPomodoroStatusBarService.scheduleIslandReminders(
          stored,
          clearFirst: true,
          restoring: true,
        );
      }
    } finally {
      if (!_initialized) {
        _initializationFuture = null;
      }
    }
  }

  static Future<void> _handleMacIslandReminderAction(
      MacIslandReminderAction event) async {
    final notifId = (event.reminder['notifId'] as num?)?.toInt();
    if (notifId == null) return;

    await cancelReminder(notifId);
    if (event.type == MacIslandReminderActionType.snoozed) {
      final snoozed = Map<String, dynamic>.from(event.reminder)
        ..['triggerAtMs'] = DateTime.now()
            .add(Duration(minutes: event.snoozeMinutes))
            .millisecondsSinceEpoch;
      await scheduleReminders([snoozed], clearFirst: false);
    }
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
    if (!await AppSettingsStorage.isCourseNotificationEnabled()) return;
    if (!Platform.isAndroid && !Platform.isIOS && !_isDesktopSupported) return;
    await ensureInitialized();

    if (_isDesktopSupported) {
      await _plugin.show(
        id: 12347,
        title: '📚 上课提醒: $courseName',
        body: '$timeStr | 教室: $room | $teacher',
        notificationDetails: _desktopNotificationDetails,
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
    } catch (_) {
      // Native notification calls are best-effort.
    }
  }

  static Future<void> updateQuizNotification({
    required int currentIndex,
    required int totalCount,
    required String questionText,
    required bool isOver,
    int score = 0,
  }) async {
    if (!await AppSettingsStorage.isQuizNotificationEnabled()) return;
    if (!Platform.isAndroid && !Platform.isIOS) return;

    if (isOver) {
      await cancelQuizNotification();
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
    } catch (_) {
      // Native notification calls are best-effort.
    }
  }

  /// 🚀 Uni-Sync: 显示通用系统通知 (用于团队变动等重要事件)
  static Future<void> showGenericNotification({
    required String title,
    required String body,
  }) async {
    final now = DateTime.now();
    final dedupeKey = '$title\u0000$body';
    final lastShown = _recentGenericNotifications[dedupeKey];
    if (lastShown != null &&
        now.difference(lastShown) < const Duration(minutes: 1)) {
      return;
    }
    _recentGenericNotifications.removeWhere(
      (_, shownAt) => now.difference(shownAt) > const Duration(minutes: 10),
    );
    _recentGenericNotifications[dedupeKey] = now;

    await ensureInitialized();
    const androidDetails = AndroidNotificationDetails(
      'system_channel',
      '系统通知',
      channelDescription: '显示团队变动、状态提醒等重要信息',
      importance: Importance.max,
      priority: Priority.high,
      showWhen: true,
    );
    const notificationDetails = NotificationDetails(android: androidDetails);
    // 🚀 修复编译错误：恢复为具名参数形式，并确保 ID 唯一性
    final int notifId = DateTime.now().millisecondsSinceEpoch.hashCode;
    await _plugin.show(
      id: notifId,
      title: title,
      body: body,
      notificationDetails: notificationDetails,
    );
  }

  static Future<void> updateTodoNotification(List<TodoItem> todos) async {
    if (!await AppSettingsStorage.isTodoSummaryNotificationEnabled()) return;
    if (!Platform.isAndroid && !Platform.isIOS) return;
    await ensureInitialized();

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
      await cancelSpecialTodoNotification(12345);
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
//       debugPrint("更新今日待办通知失败: $e");
    }
  }

  static String _detectTodoType(String title) {
    final lowerTitle = title.toLowerCase();
    if (lowerTitle.contains('快递') ||
        lowerTitle.contains('取件') ||
        lowerTitle.contains('顺丰') ||
        lowerTitle.contains('京东') ||
        lowerTitle.contains('菜鸟') ||
        lowerTitle.contains('中通') ||
        lowerTitle.contains('圆通') ||
        lowerTitle.contains('韵达') ||
        lowerTitle.contains('申通')) {
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
      return 'cafe';
    } else if (lowerTitle.contains('海底捞') ||
        lowerTitle.contains('太二') ||
        lowerTitle.contains('外婆家') ||
        lowerTitle.contains('西贝') ||
        lowerTitle.contains('必胜客') ||
        lowerTitle.contains('堂食') ||
        lowerTitle.contains('餐饮')) {
      return 'restaurant';
    } else if (lowerTitle.contains('取餐') ||
        lowerTitle.contains('外卖') ||
        lowerTitle.contains('肯德基') ||
        lowerTitle.contains('麦当劳') ||
        lowerTitle.contains('KFC')) {
      return 'food';
    }
    return 'default';
  }

  static bool _isAllDayTodo(TodoItem todo) {
    if (todo.dueDate == null) return false;

    final DateTime startDate = DateTime.fromMillisecondsSinceEpoch(
            todo.createdDate ?? todo.createdAt,
            isUtc: true)
        .toLocal();
    final DateTime dueDate = todo.dueDate!.toLocal();

    return _isAllDayRange(startDate, dueDate);
  }

  static bool _isAllDayRange(DateTime startDate, DateTime dueDate) {
    if (!_isSameDay(startDate, dueDate)) {
      final endsAtNextMidnight = startDate.hour == 0 &&
          startDate.minute == 0 &&
          dueDate.hour == 0 &&
          dueDate.minute == 0 &&
          dueDate.isAfter(startDate);
      return endsAtNextMidnight;
    }

    return startDate.hour == 0 &&
        startDate.minute == 0 &&
        ((dueDate.hour == 23 && dueDate.minute == 59) ||
            (dueDate.hour == 0 &&
                dueDate.minute == 0 &&
                dueDate.isAfter(startDate)));
  }

  static String _windowsAllDayTodoKey(TodoItem todo) {
    final dayStr = DateFormat('yyyy-MM-dd').format(todo.dueDate!.toLocal());
    return '${todo.id}@$dayStr';
  }

  static Future<void> showUpcomingTodoNotification(TodoItem todo) async {
    if (!Platform.isAndroid && !Platform.isIOS && !_isDesktopSupported) return;
    if (todo.dueDate == null) return;
    if (!_isSameDay(todo.dueDate!.toLocal(), DateTime.now())) return;

    final todoType = _detectTodoType(todo.title);
    final isSpecialTodo = todoType != 'default';
    final isAllDayTodo = _isAllDayTodo(todo);

    // Keep the safety check at the notification boundary as well as in the
    // dashboard. This prevents future callers from showing an evening task
    // hours early merely because its due date is today.
    if (!isSpecialTodo &&
        !isAllDayTodo &&
        !TodoNotificationPolicy.isInsideLiveWindow(todo, DateTime.now())) {
      return;
    }

    if (isSpecialTodo) {
      if (!await AppSettingsStorage.isSpecialTodoNotificationEnabled()) return;
    } else {
      if (!await AppSettingsStorage.isTodoSummaryNotificationEnabled()) return;
    }

    DateTime startDate = DateTime.fromMillisecondsSinceEpoch(
            todo.createdDate ?? todo.createdAt,
            isUtc: true)
        .toLocal();
    final dueDate = todo.dueDate!.toLocal();
    String timeStr = isAllDayTodo
        ? '全天'
        : "${DateFormat('HH:mm').format(startDate)} - ${DateFormat('HH:mm').format(dueDate)}";
    final notifId = todo.id.hashCode;

//     debugPrint(
//         "🔔 showUpcomingTodoNotification: title=${todo.title}, todoId=${todo.id}, hashCode=${todo.id.hashCode}, todoType=$todoType, isSpecialTodo=$isSpecialTodo, notifId=$notifId");

    if (_isDesktopSupported) {
      if (isAllDayTodo) {
        final todaySuffix =
            '@${DateFormat('yyyy-MM-dd').format(DateTime.now())}';
        _windowsAllDayTodoNotifiedKeys
            .removeWhere((key) => !key.endsWith(todaySuffix));

        final dedupeKey = _windowsAllDayTodoKey(todo);
        if (_windowsAllDayTodoNotifiedKeys.contains(dedupeKey)) {
//           debugPrint('⏭️ 跳过重复的桌面端全天待办通知: $dedupeKey');
          return;
        }
        _windowsAllDayTodoNotifiedKeys.add(dedupeKey);
      }

      await _plugin.show(
        id: todo.id.hashCode,
        title: '🔔 待办提醒: ${todo.title}',
        body: '$timeStr\n${todo.remark ?? ''}',
        notificationDetails: _desktopNotificationDetails,
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
        'imagePath': todo.imagePath,
        'originalText': todo.originalText, // 📄 原始分析文本
      });
//       debugPrint(
//           "✅ 通知发送成功: type=${isSpecialTodo ? 'special_todo' : 'upcoming_todo'}, title=${todo.title}, notifId=$notifId");
    } catch (e) {
//       debugPrint("更新即将开始的待办通知失败: $e");
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
    if (!await AppSettingsStorage.isPomodoroNotificationEnabled()) return;
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
    } catch (_) {
      // Native notification calls are best-effort.
    }
  }

  static Future<void> sendPomodoroEndAlert({
    required String alertKey,
    String? todoTitle,
    bool isBreak = false,
  }) async {
    if (!await AppSettingsStorage.isPomodoroEndNotificationEnabled()) return;
    if (!Platform.isAndroid && !Platform.isIOS && !_isDesktopSupported) return;
    if (!_sentPomodoroEndAlertKeys.add(alertKey)) return;
    if (_sentPomodoroEndAlertKeys.length > 100) {
      _sentPomodoroEndAlertKeys.remove(_sentPomodoroEndAlertKeys.first);
    }
    await ensureInitialized();

    if (_isDesktopSupported) {
      final title = isBreak ? '☕ 休息结束' : '🍅 专注完成';
      final body = todoTitle?.isNotEmpty == true
          ? '任务 "$todoTitle" 阶段已结束'
          : (isBreak ? '准备开始下一轮专注' : '请休息一下吧');

      await _plugin.show(
        id: alertKey.hashCode,
        title: title,
        body: body,
        notificationDetails: _desktopNotificationDetails,
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
//       debugPrint('番茄钟结束提醒失败: $e');
    }
  }

  static Future<void> cancelNotification() async {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    try {
      await _channel.invokeMethod('cancelNotification');
    } catch (_) {
      // Native notification calls are best-effort.
    }
  }

  /// 取消特定 ID 的特殊待办通知
  /// [notifId] 是通知的 ID
  static Future<void> cancelSpecialTodoNotification(int notifId) async {
    if (!Platform.isAndroid && !Platform.isIOS && !_isDesktopSupported) return;
    if (_isDesktopSupported) {
      await ensureInitialized();
      await _plugin.cancel(id: notifId);
      return;
    }
    try {
      await _channel.invokeMethod(
          'cancelSpecialTodoNotification', {'notificationId': notifId});
    } catch (_) {
      // Native notification calls are best-effort.
    }
  }

  static Future<void> scheduleReminders(List<Map<String, dynamic>> reminders,
      {bool clearFirst = true}) async {
    if (!await AppSettingsStorage.isReminderNotificationEnabled() &&
        !(clearFirst && reminders.isEmpty)) {
      return;
    }
    if (!Platform.isAndroid && !Platform.isIOS && !_isDesktopSupported) return;
    if (reminders.isEmpty && !clearFirst) return;
    await ensureInitialized();

    if (_isDesktopSupported) {
      final existing = clearFirst
          ? <Map<String, dynamic>>[]
          : await StorageService.getWindowsScheduledReminders();
      if (clearFirst) {
        await _plugin.cancelAll();
        await StorageService.saveWindowsScheduledReminders([]);
      }

      final List<Map<String, dynamic>> scheduledOnDesktop = [];

      for (final r in reminders) {
        final triggerAtMs = r['triggerAtMs'];
        final triggerAt = DateTime.fromMillisecondsSinceEpoch(triggerAtMs);
        if (triggerAt.isBefore(DateTime.now())) continue;

        try {
          await _plugin.zonedSchedule(
            id: r['notifId'],
            scheduledDate: tz.TZDateTime.from(triggerAt, tz.local),
            notificationDetails: _desktopNotificationDetails,
            androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
            title: r['title'] ?? '',
            body: r['text'] ?? '',
          );
          scheduledOnDesktop.add(r);
        } catch (e) {
//           debugPrint('桌面端预约提醒失败: $e');
        }
      }

      if (scheduledOnDesktop.isNotEmpty || clearFirst) {
        final scheduledIds =
            scheduledOnDesktop.map((reminder) => reminder['notifId']).toSet();
        existing.removeWhere(
            (reminder) => scheduledIds.contains(reminder['notifId']));
        existing.addAll(scheduledOnDesktop);
        await StorageService.saveWindowsScheduledReminders(existing);
      }
      if (Platform.isMacOS) {
        await MacPomodoroStatusBarService.scheduleIslandReminders(
          scheduledOnDesktop,
          clearFirst: clearFirst,
        );
      }
      return;
    }

    try {
      final payload = reminders.map((r) {
        final imagePath = r['analysisImagePath']?.toString();
        return {
          'triggerAtMs': r['triggerAtMs'],
          'title': r['title'] ?? '',
          'text': r['text'] ?? '',
          'notifId': r['notifId'],
          if (r['type'] != null) 'type': r['type'],
          if (r['todoType'] != null) 'todoType': r['todoType'],
          if (r['courseName'] != null) 'courseName': r['courseName'],
          if (r['courseStartMs'] != null) 'courseStartMs': r['courseStartMs'],
          if (r['courseEndMs'] != null) 'courseEndMs': r['courseEndMs'],
          if (r['room'] != null) 'room': r['room'],
          if (r['timeStr'] != null) 'timeStr': r['timeStr'],
          if (r['teacher'] != null) 'teacher': r['teacher'],
          if (r['originalText'] != null) 'originalText': r['originalText'],
          if (r['planBlockId'] != null) 'planBlockId': r['planBlockId'],
          if (r['todoId'] != null) 'todoId': r['todoId'],
          if (imagePath != null && imagePath.isNotEmpty)
            'analysisImagePath': imagePath,
        };
      }).toList();

      await _channel.invokeMethod('scheduleReminders', {
        'remindersJson': jsonEncode(payload),
        'clearFirst': clearFirst,
      });
    } catch (_) {
      // Native notification calls are best-effort.
    }
  }

  static Future<List<Map<String, dynamic>>> getScheduledReminders() async {
    if (!Platform.isAndroid && !Platform.isIOS && !_isDesktopSupported) {
      return [];
    }

    if (_isDesktopSupported) {
      return await StorageService.getWindowsScheduledReminders();
    }

    try {
      final jsonStr =
          await _channel.invokeMethod<String>('getScheduledReminders');
      if (jsonStr == null || jsonStr.isEmpty) return [];

      final List<dynamic> list = jsonDecode(jsonStr);
      return list.map((item) => Map<String, dynamic>.from(item)).toList();
    } catch (e) {
//       debugPrint('Error getting scheduled reminders: $e');
      return [];
    }
  }

  static Future<void> cancelReminder(int notifId) async {
    if (!Platform.isAndroid && !Platform.isIOS && !_isDesktopSupported) return;

    if (_isDesktopSupported) {
      await ensureInitialized();
      await _plugin.cancel(id: notifId);
      final current = await StorageService.getWindowsScheduledReminders();
      current.removeWhere((r) => r['notifId'] == notifId);
      await StorageService.saveWindowsScheduledReminders(current);
      return;
    }

    try {
      await _channel.invokeMethod('cancelReminder', {'notifId': notifId});
    } catch (_) {
      // Native notification calls are best-effort.
    }
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
    } catch (_) {
      // Native notification calls are best-effort.
    }
  }

  // ==========================================
  // 📸 图片识别待办通知
  // ==========================================

  // ignore: constant_identifier_names
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
    if (!await AppSettingsStorage.isTodoRecognizeNotificationEnabled()) return;
    if (!Platform.isAndroid && !Platform.isIOS && !_isDesktopSupported) return;
    await ensureInitialized();

    final title = '🔍 图片识别待办中...';
    final body = '第$currentAttempt/$maxAttempts次尝试 | $status';

    if (_isDesktopSupported) {
      await _plugin.show(
        id: NOTIF_ID_TODO_RECOGNIZE,
        title: title,
        body: body,
        notificationDetails: _desktopNotificationDetails,
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
//       debugPrint("更新图片识别进度通知失败: $e");
    }
  }

  /// 显示图片识别成功通知（实时通知，点击进入确认页面）
  /// [todoCount] 识别到的待办数量
  static Future<void> showTodoRecognizeSuccess({
    required int todoCount,
  }) async {
    if (!await AppSettingsStorage.isTodoRecognizeNotificationEnabled()) return;
    if (!Platform.isAndroid && !Platform.isIOS && !_isDesktopSupported) return;
    await ensureInitialized();

    final title = '✅ 图片识别完成';
    final body = '发现$todoCount个待办事项，点击查看详情';

    if (_isDesktopSupported) {
      await _plugin.show(
        id: NOTIF_ID_TODO_RECOGNIZE,
        title: title,
        body: body,
        notificationDetails: _desktopNotificationDetails,
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
//       debugPrint("发送图片识别成功通知失败: $e");
    }
  }

  /// 显示图片识别失败通知（实时通知）
  /// [errorMsg] 错误信息
  static Future<void> showTodoRecognizeFailed({
    required String errorMsg,
  }) async {
    if (!await AppSettingsStorage.isTodoRecognizeNotificationEnabled()) return;
    if (!Platform.isAndroid && !Platform.isIOS && !_isDesktopSupported) return;
    await ensureInitialized();

    final title = '❌ 图片识别失败';
    final body =
        errorMsg.length > 50 ? '${errorMsg.substring(0, 50)}...' : errorMsg;

    if (_isDesktopSupported) {
      await _plugin.show(
        id: NOTIF_ID_TODO_RECOGNIZE,
        title: title,
        body: body,
        notificationDetails: _desktopNotificationDetails,
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
//       debugPrint("发送图片识别失败通知失败: $e");
    }
  }

  /// 取消图片识别相关通知
  static Future<void> cancelTodoRecognizeNotification() async {
    if (!Platform.isAndroid && !Platform.isIOS && !_isDesktopSupported) return;

    if (_isDesktopSupported) {
      await ensureInitialized();
      await _plugin.cancel(id: NOTIF_ID_TODO_RECOGNIZE);
      return;
    }

    try {
      await _channel.invokeMethod('cancelTodoRecognizeNotification');
    } catch (_) {
      // Native notification calls are best-effort.
    }
  }

  /// 🚀 显示版本更新实时通知
  static Future<void> showUpdateNotification({
    required String versionName,
    required String updateTitle,
    required String updateContent,
  }) async {
    if (!Platform.isAndroid && !Platform.isIOS && !_isDesktopSupported) return;
    final notificationKey =
        '$versionName\u0000$updateTitle\u0000$updateContent';
    if (!_shownUpdateNotificationKeys.add(notificationKey)) return;
    await ensureInitialized();

    if (_isDesktopSupported) {
      await _plugin.show(
        id: 12354,
        title: '🚀 $updateTitle',
        body: '$versionName: $updateContent',
        notificationDetails: _desktopNotificationDetails,
      );
      return;
    }

    try {
      await _channel.invokeMethod('showOngoingNotification', {
        'type': 'update_found',
        'versionName': versionName,
        'title': updateTitle,
        'content': updateContent,
      });
    } catch (e) {
//       debugPrint("发送版本更新通知失败: $e");
    }
  }

  /// 取消版本更新通知
  static Future<void> cancelUpdateNotification() async {
    if (!Platform.isAndroid && !Platform.isIOS && !_isDesktopSupported) return;

    if (_isDesktopSupported) {
      await ensureInitialized();
      await _plugin.cancel(id: 12354);
      return;
    }

    try {
      await _channel.invokeMethod(
          'cancelNotification'); // cancelNotification 会清除 UPDATE_NOTIFICATION_ID
    } catch (_) {
      // Native notification calls are best-effort.
    }
  }

  /// 取消测验进度通知
  static Future<void> cancelQuizNotification() async {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    try {
      await cancelSpecialTodoNotification(12355);
    } catch (_) {
      // Native notification calls are best-effort.
    }
  }
}

/// 包装 StreamSubscription，cancel 时自动递减 NotificationService 的 listener 计数。
class _TrackedSubscription<T> implements StreamSubscription<T> {
  final StreamSubscription<T> _inner;
  final String _method;

  _TrackedSubscription(this._inner, this._method);

  @override
  Future<void> cancel() {
    NotificationService._listenerCounts[_method] =
        (NotificationService._listenerCounts[_method] ?? 1) - 1;
    if ((NotificationService._listenerCounts[_method] ?? 0) <= 0) {
      NotificationService._listenerCounts.remove(_method);
    }
    return _inner.cancel();
  }

  @override
  bool get isPaused => _inner.isPaused;

  @override
  void pause([Future<void>? resumeSignal]) => _inner.pause(resumeSignal);

  @override
  void resume() => _inner.resume();

  @override
  Future<E> asFuture<E>([E? futureValue]) => _inner.asFuture(futureValue);

  @override
  void onDone(void Function()? handleDone) => _inner.onDone(handleDone);

  @override
  void onError(Function? handleError) => _inner.onError(handleError);

  @override
  void onData(void Function(T data)? handleData) => _inner.onData(handleData);
}
