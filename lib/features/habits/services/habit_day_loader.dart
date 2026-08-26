import 'package:flutter/foundation.dart';

import '../models/habit_goal.dart';
import '../models/habit_goal_rule.dart';
import '../models/habit_progress.dart';
import '../repositories/habit_repository.dart';
import 'habit_progress_calculator.dart';
import 'habit_adaptation_service.dart';
import 'habit_rule_resolver.dart';
import 'habit_sleep_coaching_service.dart';
import 'habit_sleep_duration_service.dart';
import 'habit_sleep_goal_resolver.dart';

/// 某个日期（或所在周期）全部习惯的快照，供今日视图复用。
class HabitDaySnapshot {
  final List<HabitGoal> goals;
  final Map<String, HabitGoalRuleRevision> effectiveRules;
  final Map<String, HabitProgress> progressByHabit;
  final Map<String, List<HabitGoalRuleRevision>> allRulesByHabit;
  final HabitSleepCoachingSnapshot? sleepCoachingSnapshot;

  const HabitDaySnapshot({
    required this.goals,
    required this.effectiveRules,
    required this.progressByHabit,
    required this.allRulesByHabit,
    this.sleepCoachingSnapshot,
  });

  HabitProgress progressOf(HabitGoal goal) =>
      progressByHabit[goal.uuid] ?? HabitProgress.empty(DateTime.now());

  HabitGoalRuleRevision ruleOf(HabitGoal goal) =>
      effectiveRules[goal.uuid] ??
      HabitGoalRuleRevision(
        habitUuid: goal.uuid,
        effectiveFromDate: '',
        periodType: HabitPeriodType.daily,
      );

  /// 返回睡眠训练对当前习惯的阶段目标。
  ///
  /// 快照只在训练开启时提供指标；暂停时仍保留暂停前检查点，关闭训练则
  /// 返回 null，让卡片继续展示规则中的最终目标。
  HabitSleepCoachingMetric? sleepCoachingMetricFor(HabitGoal goal) {
    final snapshot = sleepCoachingSnapshot;
    if (snapshot == null || !snapshot.plan.enabled) return null;
    final kind = HabitAdaptationService.forHabit(goal)?.kind;
    if (kind != HabitAdaptationKind.earlySleep &&
        kind != HabitAdaptationKind.earlyWake &&
        kind != HabitAdaptationKind.sleepDuration) {
      return null;
    }
    return snapshot.metricFor(kind!);
  }

  bool get isEmpty => goals.isEmpty;

  /// 首页展示顺序：未完成习惯优先，完成习惯放到后面。
  ///
  /// 使用原始索引作为次级排序，保证同一完成状态下仍保持用户原来的顺序。
  List<HabitGoal> get goalsForDisplay {
    final indexedGoals = goals.asMap().entries.toList();
    indexedGoals.sort((a, b) {
      final aCompleted = progressOf(a.value).goalMet ? 1 : 0;
      final bCompleted = progressOf(b.value).goalMet ? 1 : 0;
      final completionOrder = aCompleted.compareTo(bCompleted);
      return completionOrder != 0 ? completionOrder : a.key.compareTo(b.key);
    });
    return indexedGoals.map((entry) => entry.value).toList();
  }
}

/// 今日视图统一数据加载入口。
abstract final class HabitDayLoader {
  /// 加载 [date]（逻辑日期）当天全部未归档习惯的进度。
  static Future<HabitDaySnapshot> loadForDate(
    DateTime date, {
    String username = '',
  }) async {
    // 早睡/早起新增或修正后，睡眠时长在下一次刷新首页时自动重算。
    await HabitSleepDurationService.syncAll();
    HabitSleepCoachingSnapshot? sleepCoachingSnapshot;
    if (username.trim().isNotEmpty) {
      try {
        sleepCoachingSnapshot =
            await HabitSleepCoachingService.load(username.trim());
      } catch (e) {
        // 训练数据异常不阻塞首页习惯卡片，回退到规则中的最终目标。
        debugPrint('⚠️ 睡眠训练快照加载失败: $e');
      }
    }
    final goals = HabitSleepGoalResolver.forDisplay(
      await HabitRepository.getActiveGoals(),
    );
    final allRules = await HabitRepository.getRules();
    final rulesByHabit = <String, List<HabitGoalRuleRevision>>{};
    final effective = <String, HabitGoalRuleRevision>{};
    final progress = <String, HabitProgress>{};

    for (final goal in goals) {
      final progressDate =
          HabitSleepDurationService.displayLogicalDateFor(goal, date);
      final rules = allRules.where((r) => r.habitUuid == goal.uuid).toList()
        ..sort((a, b) =>
            (a.effectiveFromDate ?? '').compareTo(b.effectiveFromDate ?? ''));
      rulesByHabit[goal.uuid] = rules;
      final rule = HabitRuleResolver.effectiveRule(rules, progressDate);
      if (rule == null) continue;
      effective[goal.uuid] = rule;
      try {
        progress[goal.uuid] = await HabitProgressCalculator.computePeriod(
          habit: goal,
          rules: rules,
          logicalDate: progressDate,
        );
      } catch (e) {
        // 单个习惯计算失败不阻塞整个快照：降级为空进度，
        // 该习惯今天按无记录展示，其余习惯不受影响。
        debugPrint('⚠️ 习惯 ${goal.name} 进度计算失败: $e');
        progress[goal.uuid] = HabitProgress.empty(progressDate);
      }
    }

    return HabitDaySnapshot(
      goals: goals,
      effectiveRules: effective,
      progressByHabit: progress,
      allRulesByHabit: rulesByHabit,
      sleepCoachingSnapshot: sleepCoachingSnapshot,
    );
  }
}
