/// Scheduled reminder ownership and merge helpers.
///
/// Every producer owns a source. Rebuilding one producer must replace only
/// that source; otherwise a pomodoro transition or a habit check-in can erase
/// course and todo alarms that were registered by another producer.
abstract final class ScheduledReminderSources {
  static const reminderSchedule = 'reminder_schedule';
  static const pomodoro = 'pomodoro';
  static const habit = 'habit';
}

abstract final class ScheduledReminderRegistry {
  static Map<String, dynamic> withSource(
    Map<String, dynamic> reminder,
    String source,
  ) {
    return Map<String, dynamic>.from(reminder)..['source'] = source;
  }

  static String sourceOf(Map<String, dynamic> reminder) {
    final explicitSource = reminder['source']?.toString().trim();
    if (explicitSource != null && explicitSource.isNotEmpty) {
      return explicitSource;
    }

    final type = reminder['type']?.toString();
    if (type == 'habit') return ScheduledReminderSources.habit;
    if (type == 'pomodoro' || type == 'pomodoro_end') {
      return ScheduledReminderSources.pomodoro;
    }

    final id = notifIdOf(reminder);
    if (id == 40001 || id == 40002) {
      return ScheduledReminderSources.pomodoro;
    }
    if (id != null && id >= 42001 && id <= 49999) {
      return ScheduledReminderSources.habit;
    }
    return ScheduledReminderSources.reminderSchedule;
  }

  static int? notifIdOf(Map<String, dynamic> reminder) {
    final value = reminder['notifId'];
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }

  /// Keep alarms which can still fire or whose associated event has not
  /// started yet. The latter is needed for reminders whose trigger time has
  /// already passed but which still need an immediate desktop/island display.
  static List<Map<String, dynamic>> retainActive(
    Iterable<Map<String, dynamic>> reminders, {
    DateTime? now,
  }) {
    final current = now ?? DateTime.now();
    return reminders
        .where((reminder) {
          final triggerAt = _dateTimeOf(reminder['triggerAtMs']);
          final startAt = _dateTimeOf(
            reminder['startAtMs'] ?? reminder['courseStartMs'],
          );
          if (triggerAt == null) return true;
          return triggerAt.isAfter(current) ||
              (startAt != null && startAt.isAfter(current));
        })
        .map(Map<String, dynamic>.from)
        .toList(growable: false);
  }

  static List<Map<String, dynamic>> merge({
    required Iterable<Map<String, dynamic>> existing,
    required Iterable<Map<String, dynamic>> incoming,
    String? replaceSource,
    bool replaceAll = false,
  }) {
    final merged = <Map<String, dynamic>>[];
    final existingById = <int, Map<String, dynamic>>{};

    for (final reminder in existing) {
      final copy = Map<String, dynamic>.from(reminder);
      if (replaceAll ||
          (replaceSource != null && sourceOf(copy) == replaceSource)) {
        continue;
      }
      final id = notifIdOf(copy);
      if (id != null) {
        if (existingById.containsKey(id)) {
          final old = existingById[id]!;
          final oldIndex = merged.indexOf(old);
          if (oldIndex >= 0) merged.removeAt(oldIndex);
        }
        existingById[id] = copy;
      }
      merged.add(copy);
    }

    for (final reminder in incoming) {
      final copy = Map<String, dynamic>.from(reminder);
      final id = notifIdOf(copy);
      if (id != null) {
        final old = existingById.remove(id);
        if (old != null) {
          final oldIndex = merged.indexOf(old);
          if (oldIndex >= 0) merged.removeAt(oldIndex);
        }
      }
      merged.add(copy);
      if (id != null) existingById[id] = copy;
    }

    return merged;
  }

  static DateTime? _dateTimeOf(dynamic value) {
    int? milliseconds;
    if (value is int) {
      milliseconds = value;
    } else if (value is num) {
      milliseconds = value.toInt();
    } else if (value is String) {
      milliseconds = int.tryParse(value);
    }
    return milliseconds == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(milliseconds);
  }
}
