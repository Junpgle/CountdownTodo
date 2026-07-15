enum MacPomodoroAction { togglePause, stopFocus }

enum MacIslandReminderActionType { acknowledged, snoozed }

class MacIslandReminderAction {
  const MacIslandReminderAction({
    required this.type,
    required this.reminder,
    this.snoozeMinutes = 10,
  });

  final MacIslandReminderActionType type;
  final Map<String, dynamic> reminder;
  final int snoozeMinutes;
}

class MacPomodoroStatusBarService {
  static Stream<MacPomodoroAction> get onAction => const Stream.empty();
  static Stream<MacIslandReminderAction> get onReminderAction =>
      const Stream.empty();

  static Future<void> init() async {}

  static void clearNative() {}

  static Future<void> syncCurrentStatus() async {}

  static Future<void> scheduleIslandReminders(
    List<Map<String, dynamic>> reminders, {
    bool clearFirst = true,
    bool restoring = false,
  }) async {}

  static void clearIslandReminders() {}

  static Future<void> showTestReminder() async {}

  static void dispose() {}
}
