import '../models/habit_goal.dart';
import 'habit_adaptation_service.dart';

/// 为睡眠相关的跨设备流程选择唯一的业务目标。
///
/// 旧版本允许用户在多个设备上创建多个同名睡眠目标。数据不能在没有
/// 用户确认的情况下直接删除，因此这里先用稳定、可重复的规则选择一个
/// canonical goal，训练、自动生成睡眠时长和历史导入都写入同一个目标。
abstract final class HabitSleepGoalResolver {
  static const _sleepKinds = [
    HabitAdaptationKind.earlySleep,
    HabitAdaptationKind.earlyWake,
    HabitAdaptationKind.sleepDuration,
  ];

  static HabitGoal? canonical(
    Iterable<HabitGoal> goals,
    HabitAdaptationKind kind,
  ) {
    final candidates = goals.where((goal) {
      if (goal.isDeleted || goal.isArchived) return false;
      return HabitAdaptationService.forHabit(goal)?.kind == kind;
    }).toList(growable: false);
    if (candidates.isEmpty) return null;

    final sorted = [...candidates]..sort((a, b) {
        final nameRank = _canonicalNameRank(kind, a.name).compareTo(
          _canonicalNameRank(kind, b.name),
        );
        if (nameRank != 0) return nameRank;
        final createdRank = a.createdAt.compareTo(b.createdAt);
        if (createdRank != 0) return createdRank;
        return a.uuid.compareTo(b.uuid);
      });
    return sorted.first;
  }

  /// 隐藏未归档的重复睡眠目标，但保留它们的数据和归档历史。
  ///
  /// 这是展示层的非破坏性去重：同步仍保留所有目标，归档页和历史记录
  /// 仍可访问旧目标；今日、分析和日历只展示每种睡眠目标的 canonical 项。
  static List<HabitGoal> forDisplay(Iterable<HabitGoal> goals) {
    final list = goals.toList(growable: false);
    final canonicalUuids = <String>{};
    for (final kind in _sleepKinds) {
      final goal = canonical(list, kind);
      if (goal != null) canonicalUuids.add(goal.uuid);
    }
    return list.where((goal) {
      if (goal.isArchived) return true;
      final kind = HabitAdaptationService.forHabit(goal)?.kind;
      if (kind == null || !_sleepKinds.contains(kind)) return true;
      return canonicalUuids.contains(goal.uuid);
    }).toList(growable: false);
  }

  static int _canonicalNameRank(HabitAdaptationKind kind, String name) {
    final normalized = name.trim().toLowerCase().replaceAll(' ', '');
    final canonicalNames = switch (kind) {
      HabitAdaptationKind.earlySleep => const {'早睡', '早点睡', 'bedtime'},
      HabitAdaptationKind.earlyWake => const {'早起', '起床', 'wakeup'},
      HabitAdaptationKind.sleepDuration => const {
          '睡眠时长',
          '睡眠时间',
          'sleepduration'
        },
      _ => const <String>{},
    };
    return canonicalNames.contains(normalized) ? 0 : 1;
  }
}
