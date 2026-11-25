import 'focus_do_not_disturb_service.dart';
import 'plan_reminder_guard.dart';
import 'scheduled_reminder_registry.dart';
import 'storage/app_settings_storage.dart';

/// 跨平台通知调度共享过滤逻辑（无平台 API 依赖）。
class NotificationServiceShared {
  const NotificationServiceShared._();

  static bool isPomodoroReminder(Map<String, dynamic> reminder) {
    final source = ScheduledReminderRegistry.sourceOf(reminder);
    final type = reminder['type']?.toString();
    return source == ScheduledReminderSources.pomodoro ||
        type == 'pomodoro' ||
        type == 'pomodoro_end';
  }

  static Future<List<Map<String, dynamic>>> filterScheduledReminders(
    Iterable<Map<String, dynamic>> reminders,
  ) async {
    final liveActivityEnabled =
        await AppSettingsStorage.isLiveActivityNotificationEnabled();
    final reminderEnabled =
        await AppSettingsStorage.isReminderNotificationEnabled();
    final courseEnabled =
        await AppSettingsStorage.isCourseNotificationEnabled();
    final todoLiveEnabled =
        await AppSettingsStorage.isTodoLiveNotificationEnabled();
    final specialTodoEnabled =
        await AppSettingsStorage.isSpecialTodoNotificationEnabled();
    final countdownEnabled =
        await AppSettingsStorage.isCountdownNotificationEnabled();
    final financeEnabled =
        await AppSettingsStorage.isFinanceRecurringReminderEnabled();
    final pomodoroEndEnabled =
        await AppSettingsStorage.isPomodoroEndNotificationEnabled();

    return PlanReminderGuard.filterSchedulablePlanReminders(
      reminders
          .where((reminder) {
            if (FocusDoNotDisturbService.isActive &&
                !isPomodoroReminder(reminder)) {
              return false;
            }
            if (isPomodoroReminder(reminder)) {
              return pomodoroEndEnabled;
            }
            if (!reminderEnabled) return false;
            final type = reminder['type']?.toString();
            switch (type) {
              case 'course':
                return liveActivityEnabled && courseEnabled;
              case 'upcoming_todo':
                return liveActivityEnabled && todoLiveEnabled;
              case 'special_todo':
                return liveActivityEnabled && specialTodoEnabled;
              case 'countdown':
                return liveActivityEnabled && countdownEnabled;
              case 'finance_recurring':
                return financeEnabled;
              default:
                return true;
            }
          })
          .map(Map<String, dynamic>.from)
          .toList(growable: false),
    );
  }
}
