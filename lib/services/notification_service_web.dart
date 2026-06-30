import 'dart:async';

import 'package:flutter/services.dart';

import '../models.dart';

class NotificationService {
  static final StreamController<MethodCall> _eventCtrl =
      StreamController<MethodCall>.broadcast();

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

  static Future<void> showCourseLiveActivity({
    required String courseName,
    required String room,
    required String timeStr,
    required String teacher,
  }) async {}

  static Future<void> updateQuizNotification({
    required int currentIndex,
    required int totalCount,
    required String questionText,
    required bool isOver,
    int score = 0,
  }) async {}

  static Future<void> showGenericNotification({
    required String title,
    required String body,
  }) async {}

  static Future<void> updateTodoNotification(List<TodoItem> todos) async {}

  static Future<void> showUpcomingTodoNotification(TodoItem todo) async {}

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
  }) async {}

  static Future<void> cancelNotification() async {}

  static Future<void> cancelSpecialTodoNotification(int notifId) async {}

  static Future<void> scheduleReminders(List<Map<String, dynamic>> reminders,
      {bool clearFirst = true}) async {}

  static Future<List<Map<String, dynamic>>> getScheduledReminders() async {
    return [];
  }

  static Future<void> cancelReminder(int notifId) async {}

  static Future<bool> checkExactAlarmPermission() async => true;

  static Future<void> openExactAlarmSettings() async {}

  static Future<void> showTodoRecognizeProgress({
    required int currentAttempt,
    required int maxAttempts,
    required String status,
  }) async {}

  static Future<void> showTodoRecognizeSuccess({
    required int todoCount,
  }) async {}

  static Future<void> showTodoRecognizeFailed({
    required String errorMsg,
  }) async {}

  static Future<void> cancelTodoRecognizeNotification() async {}

  static Future<void> showUpdateNotification({
    required String versionName,
    required String updateTitle,
    required String updateContent,
  }) async {}

  static Future<void> cancelUpdateNotification() async {}

  static Future<void> cancelQuizNotification() async {}
}
