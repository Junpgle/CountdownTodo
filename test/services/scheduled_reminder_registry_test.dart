import 'package:flutter_test/flutter_test.dart';

import 'package:countdown_todo/services/scheduled_reminder_registry.dart';

void main() {
  test('plan cleanup removes exact plan alarms and preserves other sources and inputs', () {
    final reminders = <Map<String, dynamic>>[
      {'notifId': 33001, 'type': 'plan_block', 'planBlockId': 'cancel'},
      {'notifId': 33002, 'type': 'plan_block', 'planBlockId': 'keep'},
      {'notifId': 40001, 'type': 'pomodoro', 'planBlockId': 'cancel'},
      {'notifId': 42001, 'source': 'habit', 'type': 'habit', 'planBlockId': 'cancel'},
      {'notifId': 30001, 'type': 'todo'},
      {'notifId': 31001, 'type': 'course'},
    ];
    final remaining = ScheduledReminderRegistry.withoutPlanBlocks(reminders, {'cancel'});
    expect(remaining.map((r) => r['notifId']), [33002, 40001, 42001, 30001, 31001]);
    expect(reminders.length, 6);
    remaining.first['text'] = 'copy';
    expect(reminders[1].containsKey('text'), isFalse);
  });
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

  test('drops out-of-range timestamps without blocking other reminders', () {
    final now = DateTime(2026, 9, 7, 12);
    final retained = ScheduledReminderRegistry.retainActive(
      [
        {'notifId': 1, 'triggerAtMs': 9223372036854775807},
        {
          'notifId': 2,
          'triggerAtMs': now.add(const Duration(minutes: 10)).millisecondsSinceEpoch,
        },
        {'notifId': 3},
      ],
      now: now,
    );

    expect(retained.map((reminder) => reminder['notifId']), [2, 3]);
  });
  test('drops malformed timestamps while keeping valid and legacy reminders', () {
    final now = DateTime(2026, 9, 7, 12);
    final retained = ScheduledReminderRegistry.retainActive(
      [
        {'notifId': 1, 'triggerAtMs': 'not-a-time'},
        {
          'notifId': 2,
          'triggerAtMs': now.add(const Duration(minutes: 10)).millisecondsSinceEpoch,
        },
        {
          'notifId': 3,
          'triggerAtMs': now.add(const Duration(minutes: 10)).millisecondsSinceEpoch,
          'startAtMs': <String, Object?>{'bad': 'value'},
        },
        {'notifId': 4},
      ],
      now: now,
    );

    expect(retained.map((reminder) => reminder['notifId']), [2, 4]);
  });
}
