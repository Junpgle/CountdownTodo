import 'package:flutter/foundation.dart';

import '../models/habit_goal.dart';
import '../models/habit_goal_rule.dart';
import '../models/habit_progress.dart';
import '../repositories/habit_repository.dart';
import 'habit_progress_calculator.dart';
import 'habit_rule_resolver.dart';

/// 某个日期（或所在周期）全部习惯的快照，供今日视图复用。
class HabitDaySnapshot {
  final List<HabitGoal> goals;
  final Map<String, HabitGoalRuleRevision> effectiveRules;
  final Map<String, HabitProgress> progressByHabit;
  final Map<String, List<HabitGoalRuleRevision>> allRulesByHabit;

  const HabitDaySnapshot({
    required this.goals,
    required this.effectiveRules,
    required this.progressByHabit,
    required this.allRulesByHabit,
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

  bool get isEmpty => goals.isEmpty;
}

/// 今日视图统一数据加载入口。
abstract final class HabitDayLoader {
  /// 加载 [date]（逻辑日期）当天全部未归档习惯的进度。
  static Future<HabitDaySnapshot> loadForDate(DateTime date) async {
    final goals = await HabitRepository.getActiveGoals();
    final allRules = await HabitRepository.getRules();
    final rulesByHabit = <String, List<HabitGoalRuleRevision>>{};
    final effective = <String, HabitGoalRuleRevision>{};
    final progress = <String, HabitProgress>{};

    for (final goal in goals) {
      final rules = allRules.where((r) => r.habitUuid == goal.uuid).toList()
        ..sort((a, b) =>
            (a.effectiveFromDate ?? '').compareTo(b.effectiveFromDate ?? ''));
      rulesByHabit[goal.uuid] = rules;
      final rule = HabitRuleResolver.effectiveRule(rules, date);
      if (rule == null) continue;
      effective[goal.uuid] = rule;
      try {
        progress[goal.uuid] = await HabitProgressCalculator.computePeriod(
          habit: goal,
          rules: rules,
          logicalDate: date,
        );
      } catch (e) {
        // 单个习惯计算失败不阻塞整个快照：降级为空进度，
        // 该习惯今天按无记录展示，其余习惯不受影响。
        debugPrint('⚠️ 习惯 ${goal.name} 进度计算失败: $e');
        progress[goal.uuid] = HabitProgress.empty(date);
      }
    }

    return HabitDaySnapshot(
      goals: goals,
      effectiveRules: effective,
      progressByHabit: progress,
      allRulesByHabit: rulesByHabit,
    );
  }
}
