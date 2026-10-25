import 'package:countdown_todo/services/plan_settings_compatibility.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('retains supported values without corrections', () {
    final result = PlanSettingsCompatibility.normalize(
      reminderMinutes: 10,
      pomodoroMinutes: 45,
      pomodoroRounds: 2,
    );

    expect(
      [result.reminderMinutes, result.pomodoroMinutes, result.pomodoroRounds],
      [10, 45, 2],
    );
    expect(result.corrections, isEmpty);
  });

  test('replaces only unsupported settings and gives field-level labels', () {
    final result = PlanSettingsCompatibility.normalize(
      reminderMinutes: 7,
      pomodoroMinutes: 45,
      pomodoroRounds: 7,
    );

    expect(
      [result.reminderMinutes, result.pomodoroMinutes, result.pomodoroRounds],
      [5, 45, 0],
    );
    expect(result.corrections.map((item) => item.summary).toList(), [
      '提前提醒：7 分钟前 → 5 分钟前',
      '番茄轮数：7 轮 → 按规划时长',
    ]);
  });

  test('does not display malformed stored values', () {
    final result = PlanSettingsCompatibility.normalize(
      reminderMinutes: 'corrupt-data',
      pomodoroMinutes: null,
      pomodoroRounds: 1,
    );

    expect(
      [result.reminderMinutes, result.pomodoroMinutes, result.pomodoroRounds],
      [5, 25, 1],
    );
    expect(result.corrections.map((item) => item.summary).toList(), [
      '提前提醒：无法识别 → 5 分钟前',
      '单轮番茄：无法识别 → 25 分钟',
    ]);
  });
}
