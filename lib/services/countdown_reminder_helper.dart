import 'package:shared_preferences/shared_preferences.dart';

import '../models.dart';
import '../utils/time_utils.dart';

/// Shared ID matching, notification lookup, and per-day dismissal persistence
/// for countdown special-date reminders.
abstract final class CountdownReminderHelper {
  static const int scheduledAlarmBaseId = 70001;
  static const int scheduledAlarmMaxId = 70999;
  static const int liveNotificationBaseId = 71001;
  static const int liveNotificationRange = 999;
  static const int liveNotificationMaxId = 71999;
  static const int maxRetainedDismissedKeys = 200;

  static int liveNotificationId(String countdownId) =>
      liveNotificationBaseId +
      (countdownId.hashCode.abs() % liveNotificationRange);

  static bool isCountdownNotificationId(int? notifId) =>
      notifId != null &&
      notifId >= scheduledAlarmBaseId &&
      notifId <= liveNotificationMaxId;

  static bool isScheduledAlarmId(int? notifId) =>
      notifId != null &&
      notifId >= scheduledAlarmBaseId &&
      notifId <= scheduledAlarmMaxId;

  static bool isLiveNotificationId(int? notifId) =>
      notifId != null &&
      notifId >= liveNotificationBaseId &&
      notifId <= liveNotificationMaxId;

  static String dismissedStorageKey(String countdownId, String dateStr) =>
      '${countdownId.trim()}@${dateStr.trim()}';

  static List<String> pruneDismissedKeys(
    Iterable<String> keys, {
    int maxEntries = maxRetainedDismissedKeys,
  }) {
    final unique = keys.where((k) => k.isNotEmpty).toSet().toList();
    if (unique.length <= maxEntries) return unique;
    unique.sort((left, right) {
      final leftDate = left.split('@').last;
      final rightDate = right.split('@').last;
      final byDate = rightDate.compareTo(leftDate);
      return byDate != 0 ? byDate : left.compareTo(right);
    });
    return unique.sublist(0, maxEntries);
  }

  /// Resolves the target [CountdownItem] for a notification "完成" action.
  ///
  /// Matching prefers explicit [countdownId], then live-activity hash IDs
  /// (`71001..71999`, prioritizing items due today), then scheduled alarm IDs
  /// (`70001..70999`) mapped through [scheduledReminders].
  static CountdownItem? findCountdownToComplete({
    required List<CountdownItem> countdowns,
    String? countdownId,
    int? notifId,
    List<Map<String, dynamic>> scheduledReminders =
        const <Map<String, dynamic>>[],
    DateTime? now,
    bool includeCompleted = false,
  }) {
    final referenceNow = now ?? DateTime.now();
    bool isEligible(CountdownItem c) =>
        !c.isDeleted && (includeCompleted || !c.isCompleted);

    final trimmedId = countdownId?.trim();
    if (trimmedId != null && trimmedId.isNotEmpty) {
      for (final item in countdowns) {
        if (item.id == trimmedId && isEligible(item)) return item;
      }
      return null;
    }

    if (isLiveNotificationId(notifId)) {
      CountdownItem? fallbackMatch;
      for (final item in countdowns) {
        if (!isEligible(item)) continue;
        if (liveNotificationId(item.id) != notifId) continue;
        if (AppTimeFormats.isSameDay(item.targetDate.toLocal(), referenceNow)) {
          return item;
        }
        fallbackMatch ??= item;
      }
      return fallbackMatch;
    }

    if (isScheduledAlarmId(notifId)) {
      String? scheduledCountdownId;
      for (final reminder in scheduledReminders) {
        final rId = (reminder['notifId'] as num?)?.toInt();
        if (rId == notifId && reminder['type'] == 'countdown') {
          scheduledCountdownId = reminder['countdownId']?.toString().trim();
          if (scheduledCountdownId != null && scheduledCountdownId.isNotEmpty) {
            break;
          }
        }
      }
      if (scheduledCountdownId != null && scheduledCountdownId.isNotEmpty) {
        for (final item in countdowns) {
          if (item.id == scheduledCountdownId && isEligible(item)) return item;
        }
      }

      final index = notifId! - scheduledAlarmBaseId;
      if (index >= 0 && index < countdowns.length) {
        final indexed = countdowns[index];
        if (isEligible(indexed) &&
            AppTimeFormats.isSameDay(
              indexed.targetDate.toLocal(),
              referenceNow,
            )) {
          return indexed;
        }
      }

      final todayMatches = <CountdownItem>[
        for (final item in countdowns)
          if (isEligible(item) &&
              AppTimeFormats.isSameDay(item.targetDate.toLocal(), referenceNow))
            item,
      ];
      if (todayMatches.length == 1) return todayMatches.single;
    }

    return null;
  }

  static List<int> scheduledNotifIdsForCountdown(
    String countdownId,
    List<Map<String, dynamic>> scheduledReminders,
  ) {
    final trimmed = countdownId.trim();
    if (trimmed.isEmpty) return const <int>[];
    final ids = <int>[];
    for (final reminder in scheduledReminders) {
      if (reminder['type'] != 'countdown') continue;
      if (reminder['countdownId']?.toString().trim() != trimmed) continue;
      final notifId = (reminder['notifId'] as num?)?.toInt();
      if (notifId != null) ids.add(notifId);
    }
    return ids;
  }
}

/// Persists dismissed countdown special-date reminders in SharedPreferences so
/// manual dismissals and completions hold across app restarts on all platforms.
abstract final class CountdownReminderPrefs {
  static const String prefsKey = 'countdown_reminder_dismissed_v1';

  static Future<Set<String>> getDismissedKeys() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList(prefsKey) ?? const <String>[]).toSet();
  }

  static Future<bool> isDismissed(String countdownId, String dateStr) async {
    final key = CountdownReminderHelper.dismissedStorageKey(
      countdownId,
      dateStr,
    );
    final keys = await getDismissedKeys();
    return keys.contains(key);
  }

  static Future<void> markDismissed(String countdownId, String dateStr) async {
    final cleanId = countdownId.trim();
    final cleanDate = dateStr.trim();
    if (cleanId.isEmpty || cleanDate.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final keys = (prefs.getStringList(prefsKey) ?? const <String>[]).toSet();
    final key = CountdownReminderHelper.dismissedStorageKey(cleanId, cleanDate);
    if (!keys.add(key)) return;
    await prefs.setStringList(
      prefsKey,
      CountdownReminderHelper.pruneDismissedKeys(keys),
    );
  }

  static Future<void> clearForCountdown(String countdownId) async {
    final cleanId = countdownId.trim();
    if (cleanId.isEmpty) return;
    final prefix = '$cleanId@';
    final prefs = await SharedPreferences.getInstance();
    final current = prefs.getStringList(prefsKey) ?? const <String>[];
    final updated = current
        .where((entry) => !entry.startsWith(prefix))
        .toList();
    if (updated.length == current.length) return;
    await prefs.setStringList(prefsKey, updated);
  }
}
