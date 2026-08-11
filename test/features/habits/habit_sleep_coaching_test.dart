import 'package:countdown_todo/features/habits/models/habit_sleep_coaching_plan.dart';
import 'package:countdown_todo/features/habits/services/habit_adaptation_service.dart';
import 'package:countdown_todo/features/habits/services/habit_sleep_coaching_service.dart';
import 'package:countdown_todo/features/habits/services/habit_sleep_goal_resolver.dart';
import 'package:countdown_todo/features/habits/models/habit_goal.dart';
import 'package:countdown_todo/features/habits/widgets/habit_sleep_coaching_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('HabitSleepCoachingPlan', () {
    test('timezone and sync fields survive JSON round trip', () {
      final plan = HabitSleepCoachingPlan(
        uuid: 'plan-1',
        enabled: true,
        paused: true,
        startedLogicalDate: '2026-08-11',
        baselineBedtimeMinute: 1410,
        baselineWakeMinute: 450,
        baselineSleepMinutes: 420,
        pausedStageIndex: 2,
        pausedProgressDays: 3,
        pausedLogicalDate: '2026-08-10',
        timezoneOffsetMinutes: 480,
        version: 3,
        deviceId: 'device-a',
        createdAt: 1000,
        updatedAt: 2000,
      );

      final restored = HabitSleepCoachingPlan.fromJson(plan.toJson());

      expect(restored.uuid, plan.uuid);
      expect(restored.enabled, isTrue);
      expect(restored.paused, isTrue);
      expect(restored.pausedStageIndex, 2);
      expect(restored.pausedProgressDays, 3);
      expect(restored.pausedLogicalDate, '2026-08-10');
      expect(restored.timezoneOffsetMinutes, 480);
      expect(restored.version, 3);
      expect(restored.updatedAt, 2000);
    });

    test('stable UUID ignores username casing and surrounding spaces', () {
      expect(
        HabitSleepCoachingPlan.stableUuidFor(' User@example.com '),
        HabitSleepCoachingPlan.stableUuidFor('user@example.com'),
      );
    });
  });

  test('canonical sleep goal is deterministic when old devices created copies',
      () {
    final copy = HabitGoal(
      name: '我的早睡',
      sourceType: HabitSourceType.timeCheckIn,
      createdAt: 100,
    );
    final canonical = HabitGoal(
      name: '早睡',
      sourceType: HabitSourceType.timeCheckIn,
      createdAt: 200,
    );

    expect(
      HabitSleepGoalResolver.canonical(
        [copy, canonical],
        HabitAdaptationKind.earlySleep,
      )?.uuid,
      canonical.uuid,
    );

    final displayGoals = HabitSleepGoalResolver.forDisplay([
      canonical,
      copy,
      HabitGoal(
        name: '普通习惯',
        sourceType: HabitSourceType.quantityCheckIn,
      ),
    ]);
    expect(
      displayGoals.map((goal) => goal.name).toList(),
      ['早睡', '普通习惯'],
    );
  });

  test('logical today uses the plan timezone rather than device timezone', () {
    final plan = HabitSleepCoachingPlan(timezoneOffsetMinutes: 480);

    final today = HabitSleepCoachingService.logicalTodayForPlan(
      plan,
      now: DateTime.utc(2026, 8, 11, 16, 30),
    );

    expect(today, DateTime(2026, 8, 12));
  });

  testWidgets('switching off disables the plan instead of pausing it',
      (tester) async {
    var enabledValue = true;
    bool? pausedValue;
    final plan = HabitSleepCoachingPlan(enabled: true);
    final snapshot = HabitSleepCoachingSnapshot(
      plan: plan,
      stageIndex: 0,
      stageProgressDays: 0,
      metrics: const <HabitSleepCoachingMetric>[],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HabitSleepCoachingCard(
            kind: HabitAdaptationKind.earlySleep,
            snapshot: snapshot,
            onEnable: () {},
            onPauseChanged: (value) => pausedValue = value,
            onEnabledChanged: (value) => enabledValue = value,
          ),
        ),
      ),
    );

    await tester.tap(find.byType(Switch));
    await tester.pump();

    expect(enabledValue, isFalse);
    expect(pausedValue, isNull);
  });
}
