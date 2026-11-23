import 'package:countdown_todo/features/habits/models/habit_goal_rule.dart';
import 'package:countdown_todo/features/habits/models/habit_progress.dart';
import 'package:countdown_todo/features/habits/widgets/habit_format.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  HabitProgress progressAt(DateTime actual) => HabitProgress(
    period: DateTime(2026, 8, 1),
    currentValue: 0,
    targetValue: 1,
    completionRatio: 1,
    hasRecord: true,
    goalMet: true,
    isPlanned: true,
    isFinished: false,
    firstRecordAt: actual,
  );

  test('凌晨目标与凌晨打卡使用同一条扩展时间轴', () {
    final rule = HabitGoalRuleRevision(
      habitUuid: 'habit-1',
      targetTimeMinute: 30,
      timeComparison: HabitTimeComparison.before,
      dayBoundaryMinute: 4 * 60,
    );

    expect(
      HabitText.timePointStatus(rule, progressAt(DateTime(2026, 8, 2, 0, 6))),
      '比目标早 24 分钟',
    );
  });

  test('晚间目标的次日凌晨打卡仍按前夜计算', () {
    final rule = HabitGoalRuleRevision(
      habitUuid: 'habit-1',
      targetTimeMinute: 23 * 60 + 30,
      timeComparison: HabitTimeComparison.before,
      dayBoundaryMinute: 4 * 60,
    );

    expect(
      HabitText.timePointStatus(rule, progressAt(DateTime(2026, 8, 2, 0, 6))),
      '比目标晚 36 分钟',
    );
  });
}
