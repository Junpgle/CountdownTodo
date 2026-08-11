import 'package:countdown_todo/models.dart';
import 'package:countdown_todo/services/pomodoro_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('TodoItem accepts string numbers and camelCase date fields', () {
    final due = DateTime.utc(2026, 1, 2, 9, 30);
    final item = TodoItem.fromJson({
      'uuid': '12345678-1234-1234-1234-123456789012',
      'content': '兼容数据',
      'recurrence': 'invalid',
      'dueDate': due.toIso8601String(),
      'customIntervalDays': '7',
      'reminderMinutes': '15',
      'version': '3',
    });

    expect(item.recurrence, RecurrenceType.none);
    expect(item.dueDate, due.toLocal());
    expect(item.customIntervalDays, 7);
    expect(item.reminderMinutes, 15);
    expect(item.version, 3);
  });

  test('timeline and fixed schedule parsers do not throw on malformed values',
      () {
    final event = TimelineEvent.fromMap({
      'type': 'invalid',
      'timestamp': 'invalid',
      'title': 123,
    });
    final schedule = FixedScheduleItem.fromJson({
      'title': '课程',
      'date': '2026-01-02',
      'status': 'invalid',
      'source': 'invalid',
      'custom_interval_days': '14',
      'owner_user_id': '9',
    });

    expect(event.type, TimelineEventType.pomodoroStart);
    expect(event.title, '123');
    expect(schedule.status, FixedScheduleStatus.scheduled);
    expect(schedule.source, FixedScheduleSource.manual);
    expect(schedule.customIntervalDays, 14);
    expect(schedule.ownerUserId, 9);
  });

  test('pomodoro state clamps malformed enum values and parses strings', () {
    final state = PomodoroRunState.fromJson({
      'phase': '999',
      'focusSeconds': '1500',
      'mode': '1',
      'targetEndMs': '123',
    });

    expect(state.phase, PomodoroPhase.remoteWatching);
    expect(state.focusSeconds, 1500);
    expect(state.mode, TimerMode.countUp);
    expect(state.targetEndMs, 123);
  });
}
