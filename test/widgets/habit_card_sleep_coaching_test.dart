import 'package:countdown_todo/features/habits/models/habit_goal.dart';
import 'package:countdown_todo/features/habits/models/habit_goal_rule.dart';
import 'package:countdown_todo/features/habits/models/habit_progress.dart';
import 'package:countdown_todo/features/habits/services/habit_adaptation_service.dart';
import 'package:countdown_todo/features/habits/services/habit_sleep_coaching_service.dart';
import 'package:countdown_todo/features/habits/widgets/habit_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('睡眠时长卡片展示当前阶段目标', (tester) async {
    final goal = HabitGoal(
      uuid: 'sleep-duration',
      name: '睡眠时长',
      sourceType: HabitSourceType.durationCheckIn,
    );
    final rule = HabitGoalRuleRevision(
      habitUuid: goal.uuid,
      targetValue: 8 * 60 * 60,
      unit: '秒',
    );
    final progress = HabitProgress(
      period: DateTime(2026, 8, 12),
      currentValue: 6 * 60 * 60,
      targetValue: rule.targetValue,
      completionRatio: 0.75,
      hasRecord: true,
      goalMet: false,
      isPlanned: true,
      isFinished: false,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HabitCard(
            goal: goal,
            rule: rule,
            dayProgress: HabitDayProgress(
              habit: goal,
              logicalDate: DateTime(2026, 8, 12),
              status: progress.dayStatus,
              progress: progress,
            ),
            sleepCoachingMetric: const HabitSleepCoachingMetric(
              kind: HabitAdaptationKind.sleepDuration,
              currentValue: 360,
              baselineValue: 360,
              targetValue: 480,
              stageTarget: 450,
              maxStage: 8,
            ),
            onChanged: _noop,
          ),
        ),
      ),
    );

    expect(find.textContaining('本期目标 7 小时 30 分'), findsOneWidget);
    expect(find.textContaining('本期目标 8 小时'), findsNothing);
  });
}

void _noop() {}
