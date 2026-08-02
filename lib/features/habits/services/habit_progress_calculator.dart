import '../../../models.dart';
import '../../../services/pomodoro_service.dart';
import '../../../services/storage/habit_storage.dart';
import '../models/habit_checkin.dart';
import '../models/habit_goal.dart';
import '../models/habit_goal_rule.dart';
import '../models/habit_progress.dart';
import 'habit_rule_resolver.dart';
import 'habit_source_resolver.dart';

/// 统一进度计算：根据 sourceType 分派到不同数据源。
///
/// 入口：`computeRange`（一个习惯在一个日期范围内的逐日进度）与
/// `computePeriod`（单周期进度）。为避免日历月视图重复读库，
/// 内部按需加载一次数据后批量计算。
abstract final class HabitProgressCalculator {
  /// 时长型习惯计入统计的最短有效时长（秒）。
  ///
  /// 设计文档 5.4：被取消且持续时间过短的专注不计入。
  static const int kMinEffectiveDurationSeconds = 60;

  /// 计算一个习惯在 [from]（含）到 [to]（含）逻辑日期范围内的逐日进度。
  ///
  /// 数据可预先传入避免重复加载；未传入时内部加载。
  /// [periodLevel] 为 true 时，每周/每月习惯只返回每个周期起始日的条目
  /// （周期内每天的进度本就相同），供连续统计等只关心周期粒度的场景使用。
  static Future<List<HabitDayProgress>> computeRange({
    required HabitGoal habit,
    required List<HabitGoalRuleRevision> rules,
    required DateTime from,
    required DateTime to,
    DateTime? now,
    List<TodoItem>? todos,
    List<PomodoroRecord>? records,
    List<HabitCheckIn>? checkIns,
    bool periodLevel = false,
  }) async {
    final nowValue = now ?? DateTime.now();
    final fromDay = DateTime(from.year, from.month, from.day);
    final toDay = DateTime(to.year, to.month, to.day);
    final dayCount = toDay.difference(fromDay).inDays;
    // 上限覆盖 60 个月（60*31≈1860 天）的统计回看窗口。
    if (dayCount < 0 || dayCount > 2400) return const [];

    final todosValue = todos ?? await _loadTodos(habit);
    final recordsValue =
        records ?? await _loadRecords(habit, rules, fromDay, toDay);
    final checkInsValue = checkIns ??
        await HabitStorage.getCheckIns(
          habitUuid: habit.uuid,
          fromDate: HabitRuleResolver.dayKey(fromDay),
          toDate: HabitRuleResolver.dayKey(toDay),
        );

    final results = <HabitDayProgress>[];
    // 周期累计型（每周/每月）按周期只计算一次，周期内每天复用同一结果，
    // 避免长回看窗口下逐日重复扫描打卡数据。
    final periodCache = <String, HabitProgress>{};
    // periodLevel 下记录上一个条目所属「规则 + 周期」，周期变更时保留新条目，
    // 避免规则在周期中途变更（如 3 月 15 日生效新规则）时丢失部分周期进度。
    String? lastPeriodId;
    for (int i = 0; i <= dayCount; i++) {
      final date = fromDay.add(Duration(days: i));
      if (periodLevel) {
        final rule = HabitRuleResolver.effectiveRule(rules, date);
        if (rule != null &&
            (rule.periodType == HabitPeriodType.weekly ||
                rule.periodType == HabitPeriodType.monthly)) {
          final periodId =
              '${rule.uuid}|${HabitRuleResolver.periodKey(rule, date)}';
          if (periodId == lastPeriodId) {
            // 同规则同周期内：进度与周期起始日相同，跳过避免生成重复条目。
            continue;
          }
          lastPeriodId = periodId;
        } else {
          lastPeriodId = null;
        }
      }
      final progress = _computeDay(
        habit: habit,
        rules: rules,
        logicalDate: date,
        now: nowValue,
        todos: todosValue,
        records: recordsValue,
        checkIns: checkInsValue,
        periodCache: periodCache,
      );
      results.add(HabitDayProgress(
        habit: habit,
        logicalDate: date,
        status: progress.dayStatus,
        progress: progress,
      ));
    }
    return results;
  }

  /// 计算单个逻辑日期（或所在周期）的进度。
  static Future<HabitProgress> computePeriod({
    required HabitGoal habit,
    required List<HabitGoalRuleRevision> rules,
    required DateTime logicalDate,
    DateTime? now,
  }) async {
    final nowValue = now ?? DateTime.now();
    final day = DateTime(logicalDate.year, logicalDate.month, logicalDate.day);
    final results = await computeRange(
      habit: habit,
      rules: rules,
      from: day,
      to: day,
      now: nowValue,
    );
    return results.isNotEmpty
        ? results.first.progress
        : HabitProgress.empty(day);
  }

  static Future<List<TodoItem>> _loadTodos(HabitGoal habit) async {
    if (habit.sourceType != HabitSourceType.recurringTodo) return const [];
    return HabitSourceResolver.todosForSeries(habit.sourceIds);
  }

  static Future<List<PomodoroRecord>> _loadRecords(
    HabitGoal habit,
    List<HabitGoalRuleRevision> rules,
    DateTime fromDay,
    DateTime toDay,
  ) async {
    if (habit.sourceType != HabitSourceType.pomodoroTag) return const [];
    final rule = HabitRuleResolver.effectiveRule(rules, fromDay) ??
        (rules.isNotEmpty ? rules.last : null);
    if (rule == null) return const [];
    // 查询窗口前后各放宽一天，覆盖跨午夜的日期分界。
    final from = fromDay.subtract(const Duration(days: 1));
    final to = toDay.add(const Duration(days: 1));
    return HabitSourceResolver.recordsForTags(
      tagUuids: habit.sourceIds,
      from: from,
      to: to,
    );
  }

  static HabitProgress _computeDay({
    required HabitGoal habit,
    required List<HabitGoalRuleRevision> rules,
    required DateTime logicalDate,
    required DateTime now,
    required List<TodoItem> todos,
    required List<PomodoroRecord> records,
    required List<HabitCheckIn> checkIns,
    Map<String, HabitProgress>? periodCache,
  }) {
    final rule = HabitRuleResolver.effectiveRule(rules, logicalDate);
    if (rule == null) {
      return HabitProgress(
        period: logicalDate,
        currentValue: 0,
        targetValue: 0,
        completionRatio: 0,
        hasRecord: false,
        goalMet: false,
        isPlanned: false,
        isFinished: true,
      );
    }

    final isAggregated = rule.periodType == HabitPeriodType.weekly ||
        rule.periodType == HabitPeriodType.monthly;
    if (!isAggregated) {
      // 手动跳过：该日不执行也不中断连续（仅每日类周期适用）。
      final hasSkip = checkIns.any((c) =>
          !c.isDeleted &&
          c.source == HabitCheckInSource.skip &&
          c.logicalDate == HabitRuleResolver.dayKey(logicalDate));
      if (hasSkip) {
        return HabitProgress(
          period: HabitRuleResolver.periodStart(rule, logicalDate),
          currentValue: 0,
          targetValue: rule.targetValue <= 0 ? 1.0 : rule.targetValue,
          completionRatio: 0,
          hasRecord: true,
          goalMet: false,
          isPlanned: HabitRuleResolver.isPlannedDay(rule, logicalDate),
          isSkipped: true,
          isFinished: true,
        );
      }
    }
    if (isAggregated && periodCache != null) {
      final key = '${rule.uuid}|'
          '${HabitRuleResolver.periodKey(rule, logicalDate)}';
      final cached = periodCache[key];
      if (cached != null) return cached;
      final computed = switch (habit.sourceType) {
        HabitSourceType.recurringTodo => _computeCompletion(
            habit: habit,
            rule: rule,
            logicalDate: logicalDate,
            now: now,
            todos: todos,
          ),
        HabitSourceType.pomodoroTag => _computeDuration(
            habit: habit,
            rule: rule,
            logicalDate: logicalDate,
            now: now,
            records: records,
          ),
        HabitSourceType.quantityCheckIn => _computeQuantity(
            habit: habit,
            rule: rule,
            logicalDate: logicalDate,
            now: now,
            checkIns: checkIns,
          ),
        HabitSourceType.timeCheckIn => _computeTimePoint(
            habit: habit,
            rule: rule,
            logicalDate: logicalDate,
            now: now,
            checkIns: checkIns,
          ),
      };
      periodCache[key] = computed;
      return computed;
    }

    switch (habit.sourceType) {
      case HabitSourceType.recurringTodo:
        return _computeCompletion(
          habit: habit,
          rule: rule,
          logicalDate: logicalDate,
          now: now,
          todos: todos,
        );
      case HabitSourceType.pomodoroTag:
        return _computeDuration(
          habit: habit,
          rule: rule,
          logicalDate: logicalDate,
          now: now,
          records: records,
        );
      case HabitSourceType.quantityCheckIn:
        return _computeQuantity(
          habit: habit,
          rule: rule,
          logicalDate: logicalDate,
          now: now,
          checkIns: checkIns,
        );
      case HabitSourceType.timeCheckIn:
        return _computeTimePoint(
          habit: habit,
          rule: rule,
          logicalDate: logicalDate,
          now: now,
          checkIns: checkIns,
        );
    }
  }

  // ── 完成型：循环待办实例 ─────────────────────────────

  static HabitProgress _computeCompletion({
    required HabitGoal habit,
    required HabitGoalRuleRevision rule,
    required DateTime logicalDate,
    required DateTime now,
    required List<TodoItem> todos,
  }) {
    final isAggregated = rule.periodType == HabitPeriodType.weekly ||
        rule.periodType == HabitPeriodType.monthly;
    final planned = HabitRuleResolver.isPlannedDay(rule, logicalDate);
    final finished = HabitRuleResolver.isPeriodFinished(rule, logicalDate, now);

    if (isAggregated) {
      // 周期累计：统计周期内所有已完成实例数量。
      final start = HabitRuleResolver.periodStart(rule, logicalDate);
      final end = HabitRuleResolver.periodEndExclusive(rule, logicalDate);
      final doneCount = todos.where((t) {
        if (t.isDeleted || !t.isDone) return false;
        final day = _todoLocalDay(t);
        if (day == null) return false;
        return !day.isBefore(start) && day.isBefore(end);
      }).length;
      final target = rule.targetValue <= 0 ? 1.0 : rule.targetValue;
      final met = doneCount >= target;
      return HabitProgress(
        period: start,
        currentValue: doneCount.toDouble(),
        targetValue: target,
        completionRatio: target <= 0 ? 0 : doneCount / target,
        hasRecord: doneCount > 0,
        goalMet: met,
        isPlanned: planned,
        isFinished: finished,
        recordCount: doneCount,
      );
    }

    final done = HabitSourceResolver.isTodoDoneOn(todos, logicalDate);
    final target = rule.targetValue <= 0 ? 1.0 : rule.targetValue;
    return HabitProgress(
      period: HabitRuleResolver.periodStart(rule, logicalDate),
      currentValue: done ? 1.0 : 0.0,
      targetValue: target,
      completionRatio: done ? 1.0 : 0.0,
      hasRecord: done,
      goalMet: done,
      isPlanned: planned,
      isFinished: finished,
      recordCount: done ? 1 : 0,
    );
  }

  // ── 时长型：专注记录累计 ─────────────────────────────

  static HabitProgress _computeDuration({
    required HabitGoal habit,
    required HabitGoalRuleRevision rule,
    required DateTime logicalDate,
    required DateTime now,
    required List<PomodoroRecord> records,
  }) {
    final planned = HabitRuleResolver.isPlannedDay(rule, logicalDate);
    final finished = HabitRuleResolver.isPeriodFinished(rule, logicalDate, now);
    final start = HabitRuleResolver.periodStart(rule, logicalDate);
    final end = HabitRuleResolver.periodEndExclusive(rule, logicalDate);

    int totalSeconds = 0;
    DateTime? firstRecordAt;
    DateTime? lastRecordAt;
    for (final record in records) {
      if (record.isDeleted || !record.isCompleted || record.hasConflict) {
        continue;
      }
      // 设计文档 5.4：被取消且持续时间过短的专注不计入。
      if (record.effectiveDuration < kMinEffectiveDurationSeconds) {
        continue;
      }
      final localStart =
          DateTime.fromMillisecondsSinceEpoch(record.startTime).toLocal();
      if (localStart.isBefore(start) || !localStart.isBefore(end)) continue;
      totalSeconds += record.effectiveDuration;
      final first = firstRecordAt;
      final last = lastRecordAt;
      if (first == null || localStart.isBefore(first)) {
        firstRecordAt = localStart;
      }
      if (last == null || localStart.isAfter(last)) lastRecordAt = localStart;
    }

    final target = rule.targetValue <= 0 ? 0.0 : rule.targetValue;
    final met = target > 0 && totalSeconds >= target;
    return HabitProgress(
      period: start,
      currentValue: totalSeconds.toDouble(),
      targetValue: target,
      completionRatio: target <= 0 ? 0 : totalSeconds / target,
      hasRecord: totalSeconds > 0,
      goalMet: met,
      isPlanned: planned,
      isFinished: finished,
      recordCount: totalSeconds > 0 ? 1 : 0,
      firstRecordAt: firstRecordAt,
      lastRecordAt: lastRecordAt,
    );
  }

  // ── 数量型：打卡事件累计 ─────────────────────────────

  static HabitProgress _computeQuantity({
    required HabitGoal habit,
    required HabitGoalRuleRevision rule,
    required DateTime logicalDate,
    required DateTime now,
    required List<HabitCheckIn> checkIns,
  }) {
    final planned = HabitRuleResolver.isPlannedDay(rule, logicalDate);
    final finished = HabitRuleResolver.isPeriodFinished(rule, logicalDate, now);
    final start = HabitRuleResolver.periodStart(rule, logicalDate);
    final end = HabitRuleResolver.periodEndExclusive(rule, logicalDate);
    final startKey = HabitRuleResolver.dayKey(start);
    final endKey =
        HabitRuleResolver.dayKey(end.subtract(const Duration(days: 1)));

    final dayCheckIns = checkIns.where((c) {
      if (c.isDeleted) return false;
      if (c.source == HabitCheckInSource.skip) return false;
      if (c.logicalDate.compareTo(startKey) < 0) return false;
      return c.logicalDate.compareTo(endKey) <= 0;
    }).toList();

    double total = 0;
    DateTime? firstRecordAt;
    DateTime? lastRecordAt;
    for (final c in dayCheckIns) {
      total += c.value;
      final local = c.localOccurredAt;
      final first = firstRecordAt;
      final last = lastRecordAt;
      if (first == null || local.isBefore(first)) firstRecordAt = local;
      if (last == null || local.isAfter(last)) lastRecordAt = local;
    }

    final target = rule.targetValue <= 0 ? 0.0 : rule.targetValue;
    final met = target > 0 && total >= target;
    return HabitProgress(
      period: start,
      currentValue: total,
      targetValue: target,
      completionRatio: target <= 0 ? 0 : total / target,
      hasRecord: dayCheckIns.isNotEmpty,
      goalMet: met,
      isPlanned: planned,
      isFinished: finished,
      recordCount: dayCheckIns.length,
      firstRecordAt: firstRecordAt,
      lastRecordAt: lastRecordAt,
      checkIns: dayCheckIns,
    );
  }

  // ── 时间点型：实际发生时间判断 ───────────────────────

  static HabitProgress _computeTimePoint({
    required HabitGoal habit,
    required HabitGoalRuleRevision rule,
    required DateTime logicalDate,
    required DateTime now,
    required List<HabitCheckIn> checkIns,
  }) {
    final planned = HabitRuleResolver.isPlannedDay(rule, logicalDate);
    final finished = HabitRuleResolver.isPeriodFinished(rule, logicalDate, now);
    final start = HabitRuleResolver.periodStart(rule, logicalDate);
    final end = HabitRuleResolver.periodEndExclusive(rule, logicalDate);
    final startKey = HabitRuleResolver.dayKey(start);
    final endKey =
        HabitRuleResolver.dayKey(end.subtract(const Duration(days: 1)));

    final dayCheckIns = checkIns.where((c) {
      if (c.isDeleted) return false;
      if (c.source == HabitCheckInSource.skip) return false;
      if (c.logicalDate.compareTo(startKey) < 0) return false;
      return c.logicalDate.compareTo(endKey) <= 0;
    }).toList();

    HabitCheckIn? earliest;
    for (final c in dayCheckIns) {
      final current = earliest;
      if (current == null || c.occurredAt < current.occurredAt) {
        earliest = c;
      }
    }

    final onTime = earliest != null &&
        HabitRuleResolver.isTimePointMet(rule, earliest.localOccurredAt);
    final target = rule.targetValue <= 0 ? 1.0 : rule.targetValue;
    return HabitProgress(
      period: start,
      currentValue: 0,
      targetValue: target,
      completionRatio: onTime ? 1.0 : 0.0,
      hasRecord: earliest != null,
      goalMet: onTime,
      isPlanned: planned,
      isFinished: finished,
      onTime: onTime,
      recordCount: dayCheckIns.length,
      firstRecordAt: earliest?.localOccurredAt,
      lastRecordAt: dayCheckIns.isNotEmpty
          ? dayCheckIns
              .reduce((a, b) => a.occurredAt > b.occurredAt ? a : b)
              .localOccurredAt
          : null,
      checkIns: dayCheckIns,
    );
  }

  static DateTime? _todoLocalDay(TodoItem todo) {
    final ms = todo.createdDate ?? todo.createdAt;
    if (ms <= 0) return null;
    return DateTime.fromMillisecondsSinceEpoch(ms).toLocal();
  }
}
