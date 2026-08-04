import 'package:countdown_todo/features/habits/models/habit_goal.dart';
import 'package:countdown_todo/features/habits/models/habit_progress.dart';
import 'package:countdown_todo/features/habits/services/habit_day_loader.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  HabitProgress progress({required bool goalMet}) => HabitProgress(
        period: DateTime(2026, 8, 4),
        currentValue: goalMet ? 1 : 0,
        targetValue: 1,
        completionRatio: goalMet ? 1 : 0,
        hasRecord: goalMet,
        goalMet: goalMet,
        isPlanned: true,
        isFinished: false,
      );

  test('homepage display order puts unfinished habits before completed ones',
      () {
    final completed = HabitGoal(uuid: 'completed', name: '已完成');
    final unfinished = HabitGoal(uuid: 'unfinished', name: '未完成');
    final anotherCompleted = HabitGoal(
      uuid: 'another-completed',
      name: '另一个已完成',
    );
    final snapshot = HabitDaySnapshot(
      goals: [completed, unfinished, anotherCompleted],
      effectiveRules: const {},
      progressByHabit: {
        completed.uuid: progress(goalMet: true),
        unfinished.uuid: progress(goalMet: false),
        anotherCompleted.uuid: progress(goalMet: true),
      },
      allRulesByHabit: const {},
    );

    expect(
      snapshot.goalsForDisplay.map((goal) => goal.uuid),
      ['unfinished', 'completed', 'another-completed'],
    );
    expect(snapshot.goalsForDisplay.take(1).single.uuid, 'unfinished');
  });
}
