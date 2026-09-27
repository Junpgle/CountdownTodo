import 'package:flutter_test/flutter_test.dart';

import 'package:countdown_todo/services/scheduled_reminder_registry.dart';

void main() {
  test('replaces only one source and de-duplicates notification ids', () {
    final merged = ScheduledReminderRegistry.merge(
      existing: [
        {
          'notifId': 1,
          'source': ScheduledReminderSources.reminderSchedule,
        },
        {
          'notifId': 2,
          'source': ScheduledReminderSources.habit,
        },
        {
          'notifId': 3,
          'source': ScheduledReminderSources.habit,
        },
      ],
      incoming: [
        {
          'notifId': 4,
          'source': ScheduledReminderSources.habit,
        },
        {
          'notifId': 2,
          'source': ScheduledReminderSources.habit,
        },
      ],
      replaceSource: ScheduledReminderSources.habit,
    );

    expect(merged.map((reminder) => reminder['notifId']), [1, 4, 2]);
    expect(
      merged.singleWhere((reminder) => reminder['notifId'] == 1)['source'],
      ScheduledReminderSources.reminderSchedule,
    );
  });

  test('infers legacy ownership and retains an event that has not started', () {
    final now = DateTime(2026, 9, 7, 12);
    final retained = ScheduledReminderRegistry.retainActive(
      [
        {
          'notifId': 40001,
          'triggerAtMs':
              now.subtract(const Duration(minutes: 5)).millisecondsSinceEpoch,
          'startAtMs':
              now.add(const Duration(minutes: 10)).millisecondsSinceEpoch,
        },
        {
          'notifId': 42001,
          'triggerAtMs':
              now.add(const Duration(minutes: 20)).millisecondsSinceEpoch,
        },
        {
          'notifId': 30001,
          'triggerAtMs':
              now.subtract(const Duration(minutes: 5)).millisecondsSinceEpoch,
        },
      ],
      now: now,
    );

    expect(retained.map((reminder) => reminder['notifId']), [40001, 42001]);
    expect(
      ScheduledReminderRegistry.sourceOf(retained.first),
      ScheduledReminderSources.pomodoro,
    );
    expect(
      ScheduledReminderRegistry.sourceOf(retained[1]),
      ScheduledReminderSources.habit,
    );
  });
}
