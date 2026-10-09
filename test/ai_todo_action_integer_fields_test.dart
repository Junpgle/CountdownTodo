import 'package:countdown_todo/models/ai_todo_action.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('fractional values are not truncated into integer action fields', () {
    final action = AiTodoAction.fromJson({
      'action': 'start_pomodoro',
      'durationMinutes': 25.5,
      'customIntervalDays': 2.5,
      'reminderMinutes': 15.5,
      'targetTimeMinute': 480.5,
      'dayBoundaryMinute': 240.5,
    });

    expect(action.durationMinutes, isNull);
    expect(action.customIntervalDays, isNull);
    expect(action.reminderMinutes, isNull);
    expect(action.targetTimeMinute, isNull);
    expect(action.dayBoundaryMinute, isNull);
  });

  test('integral numeric values remain valid integer action fields', () {
    final action = AiTodoAction.fromJson({
      'action': 'start_pomodoro',
      'durationMinutes': 25.0,
      'customIntervalDays': 2.0,
      'reminderMinutes': 15.0,
      'targetTimeMinute': 480.0,
      'dayBoundaryMinute': 240.0,
    });

    expect(action.durationMinutes, 25);
    expect(action.customIntervalDays, 2);
    expect(action.reminderMinutes, 15);
    expect(action.targetTimeMinute, 480);
    expect(action.dayBoundaryMinute, 240);
  });
}
