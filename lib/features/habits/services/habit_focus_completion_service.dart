import 'dart:math' show max, min;

import '../../../services/pomodoro_service.dart';
import '../../thirty_day_challenge/repositories/thirty_day_challenge_repository.dart';
import '../models/habit_checkin.dart';
import '../models/habit_goal.dart';
import '../models/habit_goal_rule.dart';
import '../repositories/habit_repository.dart';
import 'habit_rule_resolver.dart';
import 'habit_source_resolver.dart';
import 'habit_stamp_animation_queue.dart';

/// 番茄钟专注结束时的习惯打卡与 30 天挑战任务自动完成服务。
abstract final class HabitFocusCompletionService {
  /// 当一条专注记录保存完成时触发，返回可供 UI 展示的完成提示文案列表。
  static Future<List<String>> onFocusRecorded({
    required String username,
    required PomodoroRecord record,
    String? explicitHabitUuid,
    int? explicitChallengeTaskId,
    bool userConfirmedCompleted = false,
  }) async {
    final messages = <String>[];
    final effectiveSeconds = max(0, record.effectiveDuration);
    if (effectiveSeconds <= 0 && !userConfirmedCompleted) {
      return messages;
    }

    try {
      final habitMessages = await _processHabits(
        username: username,
        record: record,
        explicitHabitUuid: explicitHabitUuid,
        userConfirmedCompleted: userConfirmedCompleted,
      );
      messages.addAll(habitMessages);
    } catch (_) {}

    if (explicitChallengeTaskId != null) {
      try {
        final challengeMsg = await _processChallengeTask(
          username: username,
          record: record,
          taskId: explicitChallengeTaskId,
          userConfirmedCompleted: userConfirmedCompleted,
        );
        if (challengeMsg != null) {
          messages.add(challengeMsg);
        }
      } catch (_) {}
    }

    return messages;
  }

  static Future<List<String>> _processHabits({
    required String username,
    required PomodoroRecord record,
    String? explicitHabitUuid,
    required bool userConfirmedCompleted,
  }) async {
    final messages = <String>[];
    final goals = await HabitRepository.getActiveGoals();
    if (goals.isEmpty) return messages;

    final rules = await HabitRepository.getRulesForHabits(
      goals.map((g) => g.uuid),
    );
    final rulesByHabit = <String, List<HabitGoalRuleRevision>>{};
    for (final r in rules) {
      if (!r.isDeleted) {
        (rulesByHabit[r.habitUuid] ??= []).add(r);
      }
    }

    final recordTagSet = record.tagUuids.toSet();
    final now = record.endTime != null
        ? DateTime.fromMillisecondsSinceEpoch(record.endTime!).toLocal()
        : DateTime.now();

    for (final goal in goals) {
      if (goal.isDeleted || goal.isArchived) continue;
      final habitRules = rulesByHabit[goal.uuid] ?? const [];
      final latestBoundary = habitRules.isNotEmpty
          ? habitRules.last.dayBoundaryMinute
          : 0;
      final logicalDate = HabitRuleResolver.logicalDateFor(now, latestBoundary);
      final rule = HabitRuleResolver.effectiveRule(habitRules, logicalDate);
      if (rule == null) continue;

      final isExplicit = explicitHabitUuid == goal.uuid;
      final focusTags = rule.effectiveFocusTagUuids(goal).toSet();
      final matchesTags =
          focusTags.isNotEmpty && recordTagSet.any(focusTags.contains);

      if (!isExplicit && !matchesTags) continue;

      if (goal.sourceType == HabitSourceType.pomodoroTag) {
        final msg = await _checkPomodoroTagHabitGoalMet(
          goal: goal,
          rule: rule,
          logicalDate: logicalDate,
          record: record,
        );
        if (msg != null) messages.add(msg);
        continue;
      }

      if (!rule.reminderPolicy.autoCheckInOnFocus && !isExplicit) {
        continue;
      }

      // 判断本次专注时长是否达到该习惯单次专注目标（或用户已确认完成）
      final targetFocusSeconds = min(
        rule.effectivePlannedMinutes(goal) * 60,
        record.plannedDuration > 0 ? record.plannedDuration : 25 * 60,
      );
      final reachedFocusTarget =
          userConfirmedCompleted ||
          record.effectiveDuration >= targetFocusSeconds;
      if (!reachedFocusTarget) continue;

      final autoCheckedMsg = await _autoCheckInHabit(
        username: username,
        goal: goal,
        rule: rule,
        logicalDate: logicalDate,
        now: now,
        record: record,
      );
      if (autoCheckedMsg != null) {
        messages.add(autoCheckedMsg);
      }
    }

    return messages;
  }

  static Future<String?> _checkPomodoroTagHabitGoalMet({
    required HabitGoal goal,
    required HabitGoalRuleRevision rule,
    required DateTime logicalDate,
    required PomodoroRecord record,
  }) async {
    if (rule.targetValue <= 0 || goal.sourceIds.isEmpty) return null;
    final periodStart = HabitRuleResolver.periodStart(rule, logicalDate);
    final periodEnd = HabitRuleResolver.periodEndExclusive(rule, logicalDate);
    final records = await HabitSourceResolver.recordsForTags(
      tagUuids: goal.sourceIds,
      from: HabitRuleResolver.addCalendarDays(periodStart, -1),
      to: HabitRuleResolver.addCalendarDays(periodEnd, 1),
    );
    final startKey = HabitRuleResolver.dayKey(periodStart);
    final endKey = HabitRuleResolver.dayKey(periodEnd);
    var totalSeconds = 0;
    for (final item in records) {
      final localStart = DateTime.fromMillisecondsSinceEpoch(item.startTime)
          .toLocal();
      final itemLogical = HabitRuleResolver.logicalDateFor(
        localStart,
        rule.dayBoundaryMinute,
      );
      final key = HabitRuleResolver.dayKey(itemLogical);
      if (key.compareTo(startKey) >= 0 && key.compareTo(endKey) < 0) {
        totalSeconds += item.effectiveDuration;
      }
    }
    final previousSeconds = totalSeconds - record.effectiveDuration;
    if (totalSeconds >= rule.targetValue &&
        previousSeconds < rule.targetValue) {
      HabitStampAnimationQueue.request(
        habitUuid: goal.uuid,
        logicalDate: logicalDate,
      );
      return '🎉 专注达标！习惯「${goal.name}」已完成目标';
    }
    return null;
  }

  static Future<String?> _autoCheckInHabit({
    required String username,
    required HabitGoal goal,
    required HabitGoalRuleRevision rule,
    required DateTime logicalDate,
    required DateTime now,
    required PomodoroRecord record,
  }) async {
    final dayKey = HabitRuleResolver.dayKey(logicalDate);

    switch (goal.sourceType) {
      case HabitSourceType.recurringTodo:
        final existing = await HabitRepository.getCheckIns(
          habitUuid: goal.uuid,
          fromDate: dayKey,
          toDate: dayKey,
        );
        final alreadyDone = existing.any(
          (c) => !c.isDeleted && c.source != HabitCheckInSource.skip,
        );
        if (alreadyDone) return null;
        await HabitRepository.setCompletion(
          goal: goal,
          logicalDate: logicalDate,
          done: true,
          username: username,
        );
        HabitStampAnimationQueue.request(
          habitUuid: goal.uuid,
          logicalDate: logicalDate,
        );
        return '✅ 专注达标，已自动完成习惯「${goal.name}」打卡';

      case HabitSourceType.durationCheckIn:
        final existing = await HabitRepository.getCheckIns(
          habitUuid: goal.uuid,
          fromDate: dayKey,
          toDate: dayKey,
        );
        final dedupeKey = HabitCheckIn.buildDedupeKey(
          goal.uuid,
          'pomodoro/${record.uuid}',
        );
        if (existing.any((c) => !c.isDeleted && c.dedupeKey == dedupeKey)) {
          return null;
        }
        final beforeSeconds = existing
            .where((c) => !c.isDeleted && c.source != HabitCheckInSource.skip)
            .fold<double>(0, (sum, c) => sum + c.value);
        await HabitRepository.addCheckIn(
          goal: goal,
          rule: rule,
          localOccurredAt: now,
          value: record.effectiveDuration.toDouble(),
          note: '番茄钟专注自动打卡',
          dedupeKey: dedupeKey,
        );
        final afterSeconds = beforeSeconds + record.effectiveDuration;
        if (rule.targetValue <= 0 || afterSeconds >= rule.targetValue) {
          HabitStampAnimationQueue.request(
            habitUuid: goal.uuid,
            logicalDate: logicalDate,
          );
        }
        return '✅ 已将专注时长计入习惯「${goal.name}」';

      case HabitSourceType.quantityCheckIn:
        final existing = await HabitRepository.getCheckIns(
          habitUuid: goal.uuid,
          fromDate: dayKey,
          toDate: dayKey,
        );
        final dedupeKey = HabitCheckIn.buildDedupeKey(
          goal.uuid,
          'pomodoro/${record.uuid}',
        );
        if (existing.any((c) => !c.isDeleted && c.dedupeKey == dedupeKey)) {
          return null;
        }
        final currentSum = existing
            .where((c) => !c.isDeleted && c.source != HabitCheckInSource.skip)
            .fold<double>(0, (sum, c) => sum + c.value);
        final target = rule.targetValue > 0 ? rule.targetValue : 1.0;
        if (currentSum >= target) return null;
        final increment = rule.quickValues.isNotEmpty
            ? rule.quickValues.first.toDouble()
            : max(1.0, target - currentSum);
        await HabitRepository.addCheckIn(
          goal: goal,
          rule: rule,
          localOccurredAt: now,
          value: increment,
          note: '番茄钟专注自动打卡',
          dedupeKey: dedupeKey,
        );
        if (currentSum + increment >= target) {
          HabitStampAnimationQueue.request(
            habitUuid: goal.uuid,
            logicalDate: logicalDate,
          );
        }
        return '✅ 专注达标，已自动完成习惯「${goal.name}」打卡';

      case HabitSourceType.timeCheckIn:
        final existing = await HabitRepository.getCheckIns(
          habitUuid: goal.uuid,
          fromDate: dayKey,
          toDate: dayKey,
        );
        if (existing.any(
          (c) => !c.isDeleted && c.source != HabitCheckInSource.skip,
        )) {
          return null;
        }
        await HabitRepository.addCheckIn(
          goal: goal,
          rule: rule,
          localOccurredAt: now,
          value: 0,
          note: '番茄钟专注自动打卡',
          dedupeKey: HabitCheckIn.buildDedupeKey(
            goal.uuid,
            'pomodoro/${record.uuid}',
          ),
        );
        HabitStampAnimationQueue.request(
          habitUuid: goal.uuid,
          logicalDate: logicalDate,
        );
        return '✅ 专注达标，已自动记录习惯「${goal.name}」打卡';

      case HabitSourceType.pomodoroTag:
        return null;
    }
  }

  static Future<String?> _processChallengeTask({
    required String username,
    required PomodoroRecord record,
    required int taskId,
    required bool userConfirmedCompleted,
  }) async {
    final state = await ThirtyDayChallengeRepository.load(
      username: username.isEmpty ? null : username,
    );
    if (!state.autoCompleteOnFocus && !userConfirmedCompleted) return null;

    final targetSeconds = min(
      state.effectivePlannedMinutes * 60,
      record.plannedDuration > 0 ? record.plannedDuration : 25 * 60,
    );
    if (!userConfirmedCompleted && record.effectiveDuration < targetSeconds) {
      return null;
    }

    final task = state.tasks.where((t) => t.id == taskId).firstOrNull;
    if (task == null || task.isCompleted) return null;

    await ThirtyDayChallengeRepository.setCompleted(state, taskId, true);
    return '🎯 专注完成，已自动打卡 30 天挑战「${task.title}」';
  }
}
