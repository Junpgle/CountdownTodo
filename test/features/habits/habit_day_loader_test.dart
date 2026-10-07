import 'package:countdown_todo/features/habits/models/habit_goal.dart';
import 'package:countdown_todo/features/habits/models/habit_goal_rule.dart';
import 'package:countdown_todo/features/habits/services/habit_day_loader.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('凌晨日期分界前使用前一逻辑日的有效规则', () {
    final goal = HabitGoal(
      uuid: 'goal-1',
      name: '早睡',
      sourceType: HabitSourceType.timeCheckIn,
    );
    final rule = HabitGoalRuleRevision(
      uuid: 'rule-1',
      habitUuid: goal.uuid,
      effectiveFromDate: '2026-07-01',
      effectiveToDate: '2026-08-05',
      dayBoundaryMinute: 4 * 60,
    );

    expect(
      HabitDayLoader.progressLogicalDateFor(
        goal: goal,
        rules: [rule],
        date: DateTime(2026, 8, 6, 1, 59),
      ),
      DateTime(2026, 8, 5),
    );
    expect(
      HabitDayLoader.progressLogicalDateFor(
        goal: goal,
        rules: [rule],
        date: DateTime(2026, 8, 6, 4),
      ),
      DateTime(2026, 8, 6),
    );
  });
}
