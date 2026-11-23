import 'package:countdown_todo/features/habits/models/habit_checkin.dart';
import 'package:countdown_todo/features/habits/models/habit_goal.dart';
import 'package:countdown_todo/features/habits/models/habit_goal_rule.dart';
import 'package:countdown_todo/features/habits/repositories/habit_repository.dart';
import 'package:countdown_todo/features/habits/services/habit_challenge_planning_service.dart';
import 'package:countdown_todo/features/habits/services/habit_focus_completion_service.dart';
import 'package:countdown_todo/features/thirty_day_challenge/repositories/thirty_day_challenge_repository.dart';
import 'package:countdown_todo/models/plan_availability.dart';
import 'package:countdown_todo/services/plan_availability_repository.dart';
import 'package:countdown_todo/services/pomodoro_service.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/plan_availability_fixture.dart';

DateTime _at(int hour, [int minute = 0]) => DateTime(2026, 10, 8, hour, minute);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late PlanAvailabilityFixture fixture;
  late PlanAvailabilityRepository repository;

  setUp(() async {
    fixture = PlanAvailabilityFixture();
    await fixture.initialize();
    repository = PlanAvailabilityRepository(
      databaseOverride: fixture.db,
      clock: () => PlanAvailabilityFixture.now,
    );
  });

  tearDown(() => fixture.dispose());

  test('习惯与 30 天挑战配置容量预留后，未完成时占用今日容量并生成软规划块，完成后自动释放容量', () async {
    // 1. 创建一个配置了 19:00 预留 30 分钟的习惯
    final habit = HabitGoal(
      uuid: 'habit-read',
      name: '深度阅读',
      icon: '📖',
      sourceType: HabitSourceType.quantityCheckIn,
      currentRuleUuid: 'rule-read-1',
      defaultFocusMinutes: 30,
    );
    final rule = HabitGoalRuleRevision(
      uuid: 'rule-read-1',
      habitUuid: habit.uuid,
      periodType: HabitPeriodType.daily,
      targetValue: 30,
      unit: '页',
      reminderPolicy: const HabitReminderPolicy(
        includeInPlanning: true,
        preferredStartMinute: 19 * 60,
        plannedDurationMinutes: 30,
        focusTagUuids: ['tag-read'],
        autoCheckInOnFocus: true,
      ),
    );
    await fixture.db.insert('habit_goals', habit.toJson());
    await fixture.db.insert('habit_goal_rule_revisions', rule.toJson());

    // 2. 开启 30 天挑战并配置 20:00 预留 45 分钟
    final challengeState =
        await ThirtyDayChallengeRepository.startBuiltInChallenge();
    await ThirtyDayChallengeRepository.updatePlanningConfig(
      challengeState,
      includeInPlanning: true,
      preferredStartMinute: 20 * 60,
      plannedDurationMinutes: 45,
      focusTagUuids: const ['tag-life'],
      autoCompleteOnFocus: true,
    );

    final query = PlanAvailabilityQuery(
      username: PlanAvailabilityFixture.username,
      todoId: 'todo-target',
      date: PlanAvailabilityFixture.day,
      minutes: 30,
    );

    // 3. 验证未完成时占用今日容量（PlanBusySource.habit 与 PlanBusySource.challenge）
    final snapshot = await repository.read(query);
    final habitBusy = snapshot.busy
        .where((i) => i.source == PlanBusySource.habit)
        .toList();
    final challengeBusy = snapshot.busy
        .where((i) => i.source == PlanBusySource.challenge)
        .toList();

    expect(habitBusy, hasLength(1));
    expect(habitBusy.first.start, _at(19, 0));
    expect(habitBusy.first.end, _at(19, 30));
    expect(habitBusy.first.title, contains('深度阅读'));

    expect(challengeBusy, hasLength(1));
    expect(challengeBusy.first.start, _at(20, 0));
    expect(challengeBusy.first.end, _at(20, 45));
    expect(challengeBusy.first.title, contains('去一间从来没去过的餐厅'));

    // 4. 验证生成日程规划时间轴软时间块
    final planningSnapshot =
        await HabitChallengePlanningService.readFromDatabase(
          fixture.db,
          username: PlanAvailabilityFixture.username,
        );
    final mappedBlocks = HabitChallengePlanningService.buildMappedBlocksForDay(
      dayStart: PlanAvailabilityFixture.day,
      snapshot: planningSnapshot,
      todos: const [],
    );
    expect(mappedBlocks.map((b) => b.id).toSet(), {
      'mapped_habit_habit-read',
      'mapped_challenge_1',
    });

    // 5. 完成习惯打卡与今日挑战后，今日容量占用自动释放
    final checkIn = HabitCheckIn(
      habitUuid: habit.uuid,
      ruleRevisionUuid: rule.uuid,
      occurredAt: _at(19, 10).millisecondsSinceEpoch,
      logicalDate: '2026-10-08',
      value: 30,
      source: HabitCheckInSource.manual,
    );
    await fixture.db.insert('habit_checkins', checkIn.toJson());

    await ThirtyDayChallengeRepository.setCompleted(
      challengeState,
      1,
      true,
      completedAt: _at(20, 20),
    );

    final afterSnapshot = await repository.read(query);
    expect(
      afterSnapshot.busy.where(
        (i) =>
            i.source == PlanBusySource.habit ||
            i.source == PlanBusySource.challenge,
      ),
      isEmpty,
    );
  });

  test('专注达标后自动完成习惯打卡与 30 天挑战任务', () async {
    final rule = HabitGoalRuleRevision(
      uuid: 'rule-vocab-1',
      habitUuid: 'habit-vocab',
      periodType: HabitPeriodType.daily,
      targetValue: 30,
      unit: '个',
      quickValues: const [30],
      reminderPolicy: const HabitReminderPolicy(
        includeInPlanning: true,
        preferredStartMinute: 8 * 60,
        plannedDurationMinutes: 25,
        autoCheckInOnFocus: true,
      ),
    );
    final habit = await HabitRepository.createGoal(
      name: '背单词',
      icon: '🔤',
      sourceType: HabitSourceType.quantityCheckIn,
      sourceIds: const [],
      rule: rule,
      defaultFocusMinutes: 25,
      username: PlanAvailabilityFixture.username,
    );

    final challengeState =
        await ThirtyDayChallengeRepository.startBuiltInChallenge();
    await ThirtyDayChallengeRepository.updatePlanningConfig(
      challengeState,
      includeInPlanning: true,
      preferredStartMinute: 21 * 60,
      plannedDurationMinutes: 25,
      autoCompleteOnFocus: true,
    );

    final now = DateTime.now();
    final record = PomodoroRecord(
      startTime: now
          .subtract(const Duration(minutes: 25))
          .millisecondsSinceEpoch,
      endTime: now.millisecondsSinceEpoch,
      plannedDuration: 25 * 60,
      actualDuration: 25 * 60,
      status: PomodoroRecordStatus.completed,
    );

    final messages = await HabitFocusCompletionService.onFocusRecorded(
      username: PlanAvailabilityFixture.username,
      record: record,
      explicitHabitUuid: habit.uuid,
      explicitChallengeTaskId: 1,
      userConfirmedCompleted: true,
    );

    expect(messages, isNotEmpty);
    expect(messages.join(' '), contains('背单词'));

    final checkIns = await HabitRepository.getCheckIns(habitUuid: habit.uuid);
    expect(checkIns.where((c) => !c.isDeleted), hasLength(1));
    expect(checkIns.first.value, 30);

    final updatedChallenge = await ThirtyDayChallengeRepository.load(
      username: PlanAvailabilityFixture.username,
    );
    expect(updatedChallenge.tasks.first.isCompleted, isTrue);
  });
}
