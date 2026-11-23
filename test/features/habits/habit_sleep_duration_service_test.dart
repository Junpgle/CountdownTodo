import 'package:countdown_todo/features/habits/models/habit_goal.dart';
import 'package:countdown_todo/features/habits/services/habit_sleep_duration_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('睡眠时长在今日视图展示前一晚', () {
    final goal = HabitGoal(
      uuid: 'sleep-duration',
      name: '睡眠时长',
      sourceType: HabitSourceType.durationCheckIn,
    );

    expect(
      HabitSleepDurationService.displayLogicalDateFor(
        goal,
        DateTime(2026, 8, 5, 14),
      ),
      DateTime(2026, 8, 4),
    );
  });

  test('其他习惯仍展示当天', () {
    final goal = HabitGoal(
      uuid: 'water',
      name: '喝水',
      sourceType: HabitSourceType.quantityCheckIn,
    );
    final date = DateTime(2026, 8, 5, 14);

    expect(
      HabitSleepDurationService.displayLogicalDateFor(goal, date),
      DateTime(2026, 8, 5),
    );
  });
}
