import '../../../utils/time_utils.dart';
import '../models/habit_checkin.dart';
import '../models/habit_goal.dart';
import '../models/habit_goal_rule.dart';
import '../models/habit_progress.dart';
import '../repositories/habit_repository.dart';
import 'habit_drink_log_service.dart';
import 'habit_rule_resolver.dart';
import '../../../utils/calendar_date_math.dart';

/// 日历快捷点亮操作的结果。
class HabitCalendarToggleResult {
  final bool changed;
  final bool isLit;
  final String? message;

  const HabitCalendarToggleResult({
    required this.changed,
    required this.isLit,
    this.message,
  });
}

/// 习惯日历「图标点亮 / 取消点亮」业务逻辑。
///
/// 复用现有 [HabitRepository] 与 [HabitCheckIn] 数据模型，
/// 保持本地存储、统计分析和云端同步完全兼容。
abstract final class HabitCalendarLightUpService {
  /// 判断某个习惯在指定逻辑日是否处于「已点亮」状态。
  ///
  /// - 计划内已达标（[HabitDayStatus.met]）视为点亮；
  /// - 在规则生效日前或非计划日补录了有效打卡记录（非跳过、非免扣）也视为点亮，
  ///   方便用户在日历上自由补点历史日期而不破坏既有达成率统计。
  static bool isHabitLitOnDay({
    required HabitGoal goal,
    required HabitDayProgress? dayProgress,
    required List<HabitCheckIn> dayCheckIns,
  }) {
    if (HabitDrinkLogService.extractDrinkIcons(dayCheckIns).isNotEmpty) {
      return true;
    }
    if (dayProgress != null) {
      if (dayProgress.status == HabitDayStatus.met) {
        return true;
      }
      if (dayProgress.status != HabitDayStatus.notPlanned) {
        return false;
      }
    }
    return dayCheckIns.any(
      (checkIn) =>
          !checkIn.isDeleted &&
          checkIn.source != HabitCheckInSource.skip &&
          checkIn.source != HabitCheckInSource.freeze,
    );
  }

  /// 一键点亮或取消点亮指定日期的某个习惯。
  static Future<HabitCalendarToggleResult> toggleHabitLitForDay({
    required HabitGoal goal,
    required List<HabitGoalRuleRevision> rules,
    required DateTime logicalDate,
    required bool currentlyLit,
    required HabitDayProgress? dayProgress,
    required String username,
  }) async {
    if (goal.sourceType == HabitSourceType.pomodoroTag) {
      return HabitCalendarToggleResult(
        changed: false,
        isLit: currentlyLit,
        message: '专注型习惯会随专注记录自动点亮',
      );
    }

    final normalizedDate = CalendarDateMath.dateOnly(logicalDate);

    if (goal.sourceType == HabitSourceType.recurringTodo) {
      await HabitRepository.setCompletion(
        goal: goal,
        logicalDate: normalizedDate,
        done: !currentlyLit,
        username: username,
      );
      return HabitCalendarToggleResult(changed: true, isLit: !currentlyLit);
    }

    final dayKey = HabitRuleResolver.dayKey(normalizedDate);
    final existing = await HabitRepository.getCheckIns(
      habitUuid: goal.uuid,
      fromDate: dayKey,
      toDate: dayKey,
    );

    if (currentlyLit) {
      final toDelete = existing
          .where(
            (checkIn) =>
                !checkIn.isDeleted &&
                checkIn.source != HabitCheckInSource.skip &&
                checkIn.source != HabitCheckInSource.freeze,
          )
          .toList(growable: false);
      if (toDelete.isEmpty) {
        return const HabitCalendarToggleResult(changed: false, isLit: false);
      }
      for (final checkIn in toDelete) {
        checkIn
          ..isDeleted = true
          ..markAsChanged();
      }
      await HabitRepository.saveCheckInsBatch(toDelete);
      return const HabitCalendarToggleResult(changed: true, isLit: false);
    }

    // 点亮前若当天存在跳过标记，先清除跳过标记，避免状态冲突。
    final activeSkips = existing
        .where(
          (checkIn) =>
              !checkIn.isDeleted && checkIn.source == HabitCheckInSource.skip,
        )
        .toList(growable: false);
    if (activeSkips.isNotEmpty) {
      for (final skip in activeSkips) {
        skip
          ..isDeleted = true
          ..markAsChanged();
      }
      await HabitRepository.saveCheckInsBatch(activeSkips);
    }

    final rule = _resolveRuleForLightUp(goal, rules, normalizedDate);
    final occurredAt = _resolveOccurredAt(
      goal: goal,
      rule: rule,
      logicalDate: normalizedDate,
    );

    switch (goal.sourceType) {
      case HabitSourceType.quantityCheckIn:
        final target = rule.targetValue > 0 ? rule.targetValue : 1.0;
        final current = dayProgress?.progress.currentValue ?? 0.0;
        final delta = target - current;
        final valueToAdd = delta > 0 ? delta : target;
        await HabitRepository.addCheckIn(
          goal: goal,
          rule: rule,
          localOccurredAt: occurredAt,
          value: valueToAdd,
        );
        return const HabitCalendarToggleResult(changed: true, isLit: true);

      case HabitSourceType.durationCheckIn:
        final target = rule.targetValue > 0 ? rule.targetValue : 3600.0;
        final current = dayProgress?.progress.currentValue ?? 0.0;
        final delta = target - current;
        final valueToAdd = delta > 0 ? delta : target;
        await HabitRepository.addCheckIn(
          goal: goal,
          rule: rule,
          localOccurredAt: occurredAt,
          value: valueToAdd,
        );
        return const HabitCalendarToggleResult(changed: true, isLit: true);

      case HabitSourceType.timeCheckIn:
        await HabitRepository.addCheckIn(
          goal: goal,
          rule: rule,
          localOccurredAt: occurredAt,
          value: 0,
        );
        return const HabitCalendarToggleResult(changed: true, isLit: true);

      case HabitSourceType.recurringTodo:
      case HabitSourceType.pomodoroTag:
        return HabitCalendarToggleResult(changed: false, isLit: currentlyLit);
    }
  }

  static HabitGoalRuleRevision _resolveRuleForLightUp(
    HabitGoal goal,
    List<HabitGoalRuleRevision> rules,
    DateTime logicalDate,
  ) {
    final effective = HabitRuleResolver.effectiveRule(rules, logicalDate);
    if (effective != null) return effective;
    if (rules.isNotEmpty) return rules.first;
    return HabitGoalRuleRevision(
      habitUuid: goal.uuid,
      effectiveFromDate: HabitRuleResolver.dayKey(logicalDate),
      periodType: HabitPeriodType.daily,
      targetValue: 1,
    );
  }

  /// 构造必然落在该 [logicalDate] 逻辑日内的本地时间。
  static DateTime _resolveOccurredAt({
    required HabitGoal goal,
    required HabitGoalRuleRevision rule,
    required DateTime logicalDate,
  }) {
    if (goal.sourceType == HabitSourceType.timeCheckIn &&
        rule.targetTimeMinute != null) {
      final targetMinute = rule.targetTimeMinute!.clamp(0, 1439);
      final base = DateTime(
        logicalDate.year,
        logicalDate.month,
        logicalDate.day,
        targetMinute ~/ 60,
        targetMinute % 60,
      );
      if (targetMinute < rule.dayBoundaryMinute) {
        return base.add(const Duration(days: 1));
      }
      return base;
    }

    final now = DateTime.now();
    final todayLogical = HabitRuleResolver.logicalDateFor(
      now,
      rule.dayBoundaryMinute,
    );
    if (AppTimeFormats.isSameDay(todayLogical, logicalDate)) {
      return now;
    }

    // 历史日期取中午 12:00，确保大于任意合法日界线（00:00~06:00），严格落在同一逻辑日。
    final safeMinute = rule.dayBoundaryMinute >= 720
        ? (rule.dayBoundaryMinute + 30).clamp(0, 1439)
        : 720;
    return DateTime(
      logicalDate.year,
      logicalDate.month,
      logicalDate.day,
      safeMinute ~/ 60,
      safeMinute % 60,
    );
  }
}
