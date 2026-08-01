import '../../../services/storage/habit_storage.dart';
import '../models/habit_checkin.dart';
import '../models/habit_goal.dart';
import '../repositories/habit_repository.dart';
import 'habit_rule_resolver.dart';

/// 小组件快捷打卡结果。
sealed class HabitWidgetCheckInResult {
  const HabitWidgetCheckInResult();
}

/// 已打卡成功。
class HabitWidgetCheckInDone extends HabitWidgetCheckInResult {
  const HabitWidgetCheckInDone({required this.succeeded});

  final bool succeeded;
}

/// 无法在后台打卡（时长型习惯），需要引导用户打开应用。
class HabitWidgetCheckInOpenApp extends HabitWidgetCheckInResult {
  const HabitWidgetCheckInOpenApp();
}

/// 小组件 / 深链接共享的快捷打卡逻辑。
///
/// - 数量型：增加一个快捷值（默认取规则第一个快捷值，[value] 可覆盖）。
/// - 时间点型：记录「现在」一次。
/// - 完成型：将今天标记为已完成。
/// - 时长型：后台无法可靠启动专注，返回 [HabitWidgetCheckInOpenApp]。
abstract final class HabitWidgetCheckIn {
  static Future<HabitWidgetCheckInResult> quickCheckIn({
    required String habitId,
    double? value,
    String username = '',
  }) async {
    final goals = await HabitStorage.getHabitGoals(includeArchived: false);
    final goal = goals.where((g) => g.uuid == habitId).firstOrNull;
    if (goal == null) return const HabitWidgetCheckInDone(succeeded: false);

    final rules = await HabitStorage.getRuleRevisions(
      habitUuid: goal.uuid,
      includeDeleted: false,
    );
    final now = DateTime.now();
    final rule = HabitRuleResolver.effectiveRule(rules, now);
    if (rule == null) return const HabitWidgetCheckInDone(succeeded: false);
    final logicalDate = HabitRuleResolver.logicalDateFor(
      now,
      rule.dayBoundaryMinute,
    );
    if (!HabitRuleResolver.isPlannedDay(rule, logicalDate)) {
      return const HabitWidgetCheckInDone(succeeded: false);
    }

    switch (goal.sourceType) {
      case HabitSourceType.quantityCheckIn:
        final v = value ??
            (rule.quickValues.isNotEmpty
                ? rule.quickValues.first.toDouble()
                : 1.0);
        await HabitRepository.addCheckIn(
          goal: goal,
          rule: rule,
          localOccurredAt: now,
          value: v,
          source: HabitCheckInSource.widget,
        );
        return const HabitWidgetCheckInDone(succeeded: true);

      case HabitSourceType.timeCheckIn:
        await HabitRepository.addCheckIn(
          goal: goal,
          rule: rule,
          localOccurredAt: now,
          source: HabitCheckInSource.widget,
        );
        return const HabitWidgetCheckInDone(succeeded: true);

      case HabitSourceType.recurringTodo:
        await HabitRepository.setCompletion(
          goal: goal,
          logicalDate: logicalDate,
          done: true,
          username: username,
        );
        return const HabitWidgetCheckInDone(succeeded: true);

      case HabitSourceType.pomodoroTag:
        return const HabitWidgetCheckInOpenApp();
    }
  }
}
