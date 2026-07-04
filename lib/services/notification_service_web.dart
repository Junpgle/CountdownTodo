import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter/services.dart';

import '../models.dart';
import 'storage/app_settings_storage.dart';

class NotificationService {
  static final StreamController<MethodCall> _eventCtrl =
      StreamController<MethodCall>.broadcast();
  static final Map<int, Timer> _reminderTimers = {};
  static final Map<int, Map<String, dynamic>> _scheduledReminders = {};

  // ignore: constant_identifier_names
  static const int NOTIF_ID_TODO_RECOGNIZE = 9001;

  static Future<void> bindNativeChannel() async {}

  static StreamSubscription<MethodCall> listen(
    String method,
    void Function(MethodCall call) handler,
  ) {
    return _eventCtrl.stream
        .where((call) => call.method == method)
        .listen(handler);
  }

  static Future<void> init() async {}

  static Future<void> ensureInitialized() async {}

  static bool get _hasBrowserBridge => globalContext.has('cdtNotifications');

  static JSObject? get _browserBridge =>
      _hasBrowserBridge ? globalContext['cdtNotifications'] as JSObject? : null;

  static String _jsString(JSAny? value, {String fallback = 'unsupported'}) {
    return value?.dartify()?.toString() ?? fallback;
  }

  static Future<String> getBrowserNotificationPermission() async {
    try {
      final bridge = _browserBridge;
      if (bridge == null) return 'unsupported';
      final result =
          bridge.callMethodVarArgs<JSAny?>('permission'.toJS, <JSAny?>[]);
      return _jsString(result);
    } catch (_) {
      return 'unsupported';
    }
  }

  static Future<bool> requestBrowserNotificationPermission() async {
    try {
      final bridge = _browserBridge;
      if (bridge == null) return false;
      final promise = bridge.callMethodVarArgs<JSPromise<JSString>>(
        'requestPermission'.toJS,
        <JSAny?>[],
      );
      final permission = await promise.toDart;
      return permission.toDart == 'granted';
    } catch (_) {
      return false;
    }
  }

  static Future<bool> _showBrowserNotification(
    String title,
    String body, {
    String? tag,
  }) async {
    if (title.trim().isEmpty) return false;
    if (await getBrowserNotificationPermission() != 'granted') return false;

    try {
      final bridge = _browserBridge;
      if (bridge == null) return false;
      final result = bridge.callMethodVarArgs<JSAny?>(
        'show'.toJS,
        <JSAny?>[
          title.toJS,
          body.toJS,
          (tag ?? '').toJS,
        ],
      );
      return result?.dartify() == true;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> _showNormalNotification(
    String title,
    String body, {
    String? tag,
  }) async {
    if (!await AppSettingsStorage.isNormalNotificationEnabled()) return false;
    return _showBrowserNotification(title, body, tag: tag);
  }

  static Future<void> showCourseLiveActivity({
    required String courseName,
    required String room,
    required String timeStr,
    required String teacher,
  }) async {
    if (!await AppSettingsStorage.isCourseNotificationEnabled()) return;
    await _showNormalNotification(
      '上课提醒: $courseName',
      [
        if (timeStr.isNotEmpty) timeStr,
        if (room.isNotEmpty) '教室: $room',
        if (teacher.isNotEmpty) teacher,
      ].join(' | '),
      tag: 'course-$courseName-$timeStr',
    );
  }

  static Future<void> updateQuizNotification({
    required int currentIndex,
    required int totalCount,
    required String questionText,
    required bool isOver,
    int score = 0,
  }) async {
    if (!isOver) return;
    if (!await AppSettingsStorage.isQuizNotificationEnabled()) return;
    await _showNormalNotification(
      '测验完成',
      totalCount > 0 ? '得分 $score / $totalCount' : '本次测验已结束',
      tag: 'quiz-finished',
    );
  }

  static Future<void> showGenericNotification({
    required String title,
    required String body,
  }) async {
    await _showNormalNotification(title, body);
  }

  static Future<void> updateTodoNotification(List<TodoItem> todos) async {}

  static Future<void> showUpcomingTodoNotification(TodoItem todo) async {
    if (!await AppSettingsStorage.isReminderNotificationEnabled()) return;
    final due = todo.dueDate?.toLocal();
    final timeText = due == null
        ? '即将开始'
        : '${due.month}/${due.day} ${due.hour.toString().padLeft(2, '0')}:${due.minute.toString().padLeft(2, '0')}';
    final remark = todo.remark?.trim();
    await _showNormalNotification(
      todo.title,
      remark?.isNotEmpty == true ? '$timeText · $remark' : timeText,
      tag: 'todo-${todo.id}',
    );
  }

  static Future<void> updatePomodoroNotification({
    required int remainingSeconds,
    required String phase,
    String? todoTitle,
    int currentCycle = 1,
    int totalCycles = 4,
    List<String> tagNames = const [],
    String alertKey = '',
  }) async {}

  static Future<void> sendPomodoroEndAlert({
    required String alertKey,
    String? todoTitle,
    bool isBreak = false,
  }) async {
    if (!await AppSettingsStorage.isPomodoroEndNotificationEnabled()) return;
    final title = isBreak ? '休息结束' : '专注完成';
    final body = todoTitle?.isNotEmpty == true
        ? '"$todoTitle" 阶段已结束'
        : (isBreak ? '准备开始下一轮专注' : '请休息一下吧');
    await _showNormalNotification(title, body, tag: alertKey);
  }

  static Future<void> cancelNotification() async {}

  static Future<void> cancelSpecialTodoNotification(int notifId) async {
    await cancelReminder(notifId);
  }

  static Future<void> scheduleReminders(List<Map<String, dynamic>> reminders,
      {bool clearFirst = true}) async {
    if (clearFirst) {
      _clearScheduledReminders();
    }

    if (reminders.isEmpty) return;
    if (!await AppSettingsStorage.isNormalNotificationEnabled()) return;
    if (!await AppSettingsStorage.isReminderNotificationEnabled()) return;

    for (final reminder in reminders) {
      _scheduleReminder(reminder);
    }
  }

  static Future<List<Map<String, dynamic>>> getScheduledReminders() async {
    final reminders = _scheduledReminders.values
        .map((reminder) => Map<String, dynamic>.from(reminder))
        .toList();
    reminders.sort((a, b) {
      final aMs = _readInt(a['triggerAtMs']) ?? 0;
      final bMs = _readInt(b['triggerAtMs']) ?? 0;
      return aMs.compareTo(bMs);
    });
    return reminders;
  }

  static Future<void> cancelReminder(int notifId) async {
    _reminderTimers.remove(notifId)?.cancel();
    _scheduledReminders.remove(notifId);
  }

  static Future<bool> checkExactAlarmPermission() async => true;

  static Future<void> openExactAlarmSettings() async {}

  static Future<void> showTodoRecognizeProgress({
    required int currentAttempt,
    required int maxAttempts,
    required String status,
  }) async {
    if (!await AppSettingsStorage.isTodoRecognizeNotificationEnabled()) return;
    await _showNormalNotification(
      '图片识别待办中',
      '第$currentAttempt/$maxAttempts次尝试 | $status',
      tag: 'todo-recognize',
    );
  }

  static Future<void> showTodoRecognizeSuccess({
    required int todoCount,
  }) async {
    if (!await AppSettingsStorage.isTodoRecognizeNotificationEnabled()) return;
    await _showNormalNotification(
      '图片识别完成',
      '发现$todoCount个待办事项',
      tag: 'todo-recognize',
    );
  }

  static Future<void> showTodoRecognizeFailed({
    required String errorMsg,
  }) async {
    if (!await AppSettingsStorage.isTodoRecognizeNotificationEnabled()) return;
    final body =
        errorMsg.length > 80 ? '${errorMsg.substring(0, 80)}...' : errorMsg;
    await _showNormalNotification(
      '图片识别失败',
      body,
      tag: 'todo-recognize',
    );
  }

  static Future<void> cancelTodoRecognizeNotification() async {
    await cancelReminder(NOTIF_ID_TODO_RECOGNIZE);
  }

  static Future<void> showUpdateNotification({
    required String versionName,
    required String updateTitle,
    required String updateContent,
  }) async {
    final title = updateTitle.isNotEmpty ? updateTitle : '发现新版本 $versionName';
    final body = updateContent.isNotEmpty ? updateContent : '刷新网页即可加载最新版本';
    await _showNormalNotification(title, body, tag: 'app-update');
  }

  static Future<void> cancelUpdateNotification() async {}

  static Future<void> cancelQuizNotification() async {}

  static void _clearScheduledReminders() {
    for (final timer in _reminderTimers.values) {
      timer.cancel();
    }
    _reminderTimers.clear();
    _scheduledReminders.clear();
  }

  static void _scheduleReminder(Map<String, dynamic> source) {
    final triggerAtMs = _readInt(source['triggerAtMs']);
    if (triggerAtMs == null) return;

    final triggerAt = DateTime.fromMillisecondsSinceEpoch(triggerAtMs);
    final delay = triggerAt.difference(DateTime.now());
    if (delay <= Duration.zero) return;

    final notifId = _readInt(source['notifId']) ?? triggerAtMs.hashCode;
    final reminder = Map<String, dynamic>.from(source)
      ..['triggerAtMs'] = triggerAtMs
      ..['notifId'] = notifId
      ..['title'] = source['title']?.toString() ?? 'CountDownTodo 提醒'
      ..['text'] = source['text']?.toString() ?? '';

    _reminderTimers.remove(notifId)?.cancel();
    _scheduledReminders[notifId] = reminder;
    _reminderTimers[notifId] = Timer(delay, () async {
      _reminderTimers.remove(notifId);
      final current = _scheduledReminders.remove(notifId);
      if (current == null) return;
      if (!await _shouldShowScheduledReminder(current)) return;
      await _showBrowserNotification(
        current['title']?.toString() ?? 'CountDownTodo 提醒',
        current['text']?.toString() ?? '',
        tag: 'reminder-$notifId',
      );
    });
  }

  static Future<bool> _shouldShowScheduledReminder(
    Map<String, dynamic> reminder,
  ) async {
    if (!await AppSettingsStorage.isNormalNotificationEnabled()) return false;
    if (!await AppSettingsStorage.isReminderNotificationEnabled()) {
      return false;
    }

    switch (reminder['type']?.toString()) {
      case 'course':
        return AppSettingsStorage.isCourseNotificationEnabled();
      case 'special_todo':
        return AppSettingsStorage.isSpecialTodoNotificationEnabled();
      default:
        return true;
    }
  }

  static int? _readInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }
}
