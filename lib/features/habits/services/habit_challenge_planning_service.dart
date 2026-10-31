import 'dart:convert';
import 'dart:math' show max;

import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import '../../../models.dart';
import '../../../models/plan_availability.dart';
import '../../../services/pomodoro_service.dart';
import '../../../services/storage/storage_key_scope.dart';
import '../../thirty_day_challenge/models/thirty_day_challenge.dart';
import '../models/habit_checkin.dart';
import '../models/habit_goal.dart';
import '../models/habit_goal_rule.dart';
import 'habit_rule_resolver.dart';
import 'habit_source_resolver.dart';

/// 习惯与 30 天挑战接入「今日容量与规划块」的统一投影服务。
///
/// 负责：
/// 1. 从数据库 / 本地偏好中零副作用读取已启用规划预留的习惯与 30 天挑战；
/// 2. 计算某日尚未完成/跳过的软日程占用区间（[PlanBusyInterval]），供容量与可用时段引擎扣减；
/// 3. 生成日视图时间轴上的软规划块（`mapped_habit_*` / `mapped_challenge_*`）。
class HabitChallengePlanningSnapshot {
  final List<HabitGoal> goals;
  final Map<String, List<HabitGoalRuleRevision>> rulesByHabitUuid;
  final Map<String, List<HabitCheckIn>> checkInsByHabitUuid;
  final List<PomodoroRecord> pomodoroRecords;
  final ThirtyDayChallengeState? challengeState;

  const HabitChallengePlanningSnapshot({
    this.goals = const [],
    this.rulesByHabitUuid = const {},
    this.checkInsByHabitUuid = const {},
    this.pomodoroRecords = const [],
    this.challengeState,
  });
}

abstract final class HabitChallengePlanningService {
  static const String mappedHabitPrefix = 'mapped_habit_';
  static const String mappedChallengePrefix = 'mapped_challenge_';
  static const String _challengeStorageKey = 'thirty_day_self_challenge_v1';

  static bool isMappedHabitBlock(TodoPlanBlock block) =>
      block.id.startsWith(mappedHabitPrefix);

  static bool isMappedChallengeBlock(TodoPlanBlock block) =>
      block.id.startsWith(mappedChallengePrefix);

  static String? habitUuidFromBlock(TodoPlanBlock block) {
    if (!isMappedHabitBlock(block)) return null;
    return block.id.substring(mappedHabitPrefix.length);
  }

  static int? challengeTaskIdFromBlock(TodoPlanBlock block) {
    if (!isMappedChallengeBlock(block)) return null;
    return int.tryParse(block.id.substring(mappedChallengePrefix.length));
  }

  /// 返回需要纳入 `PlanAvailabilityRepository._settingsFingerprint` 的偏好键前缀。
  static bool isPlanningPreferenceKey(String key, String username) {
    final base = StorageKeyScope.scoped(_challengeStorageKey, username);
    return key == base ||
        key == '${base}_started' ||
        key == '${base}_intro_seen' ||
        key == '${base}_paused';
  }

  /// 从给定的 [DatabaseExecutor] 与 `SharedPreferences` 只读加载习惯与 30 天挑战数据。
  ///
  /// 注意：绝不向 `SharedPreferences` 写入初始值，保持只读与幂等。
  static Future<HabitChallengePlanningSnapshot> readFromDatabase(
    DatabaseExecutor db, {
    required String username,
  }) async {
    final goals = <HabitGoal>[];
    final rulesByHabitUuid = <String, List<HabitGoalRuleRevision>>{};
    final checkInsByHabitUuid = <String, List<HabitCheckIn>>{};
    final pomodoroRecords = <PomodoroRecord>[];

    try {
      final goalRows = await db.query(
        'habit_goals',
        where: 'is_deleted = 0 AND is_archived = 0',
        orderBy: 'sort_order ASC, created_at ASC',
      );
      for (final row in goalRows) {
        final goal = HabitGoal.fromJson(Map<String, dynamic>.from(row));
        if (!goal.isDeleted && !goal.isArchived) {
          goals.add(goal);
        }
      }
    } catch (_) {
      // 表不存在或精简测试库时安全降级为空。
    }

    if (goals.isNotEmpty) {
      try {
        final ruleRows = await db.query(
          'habit_goal_rule_revisions',
          where: 'is_deleted = 0',
        );
        for (final row in ruleRows) {
          final rule = HabitGoalRuleRevision.fromJson(
            Map<String, dynamic>.from(row),
          );
          if (!rule.isDeleted) {
            (rulesByHabitUuid[rule.habitUuid] ??= []).add(rule);
          }
        }
      } catch (_) {}

      try {
        final checkInRows = await db.query(
          'habit_checkins',
          where: 'is_deleted = 0',
        );
        for (final row in checkInRows) {
          final checkIn = HabitCheckIn.fromJson(Map<String, dynamic>.from(row));
          if (!checkIn.isDeleted) {
            (checkInsByHabitUuid[checkIn.habitUuid] ??= []).add(checkIn);
          }
        }
      } catch (_) {}

      try {
        final recordRows = await db.query(
          'pomodoro_records',
          where: 'is_deleted = 0',
        );
        for (final row in recordRows) {
          final record = PomodoroRecord.fromJson(
            Map<String, dynamic>.from(row),
          );
          if (!record.isDeleted && record.isCompleted && !record.hasConflict) {
            pomodoroRecords.add(record);
          }
        }
      } catch (_) {}
    }

    final challengeState = await _readActiveChallengeReadOnly(username);

    return HabitChallengePlanningSnapshot(
      goals: goals,
      rulesByHabitUuid: rulesByHabitUuid,
      checkInsByHabitUuid: checkInsByHabitUuid,
      pomodoroRecords: pomodoroRecords,
      challengeState: challengeState,
    );
  }

  static Future<ThirtyDayChallengeState?> _readActiveChallengeReadOnly(
    String username,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final scopedBase = StorageKeyScope.scoped(_challengeStorageKey, username);
      final started =
          prefs.getBool('${scopedBase}_started') ??
          prefs.getBool('${scopedBase}_intro_seen') ??
          false;
      final paused = prefs.getBool('${scopedBase}_paused') ?? false;
      if (!started || paused) return null;
      final raw = prefs.getString(scopedBase);
      if (raw == null || raw.isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      return ThirtyDayChallengeState.fromJson(
        Map<String, dynamic>.from(decoded),
      );
    } catch (_) {
      return null;
    }
  }

  /// 生成某一天（[dayStart] 本地 00:00）的软占用区间（用于 [PlanAvailabilityRepository]）。
  static List<PlanBusyInterval> buildBusyIntervalsForDay({
    required DateTime dayStart,
    required HabitChallengePlanningSnapshot snapshot,
    required List<TodoItem> todos,
  }) {
    final date = DateTime(dayStart.year, dayStart.month, dayStart.day);
    final dayKey = HabitRuleResolver.dayKey(date);
    final intervals = <PlanBusyInterval>[];

    for (final goal in snapshot.goals) {
      if (goal.isDeleted || goal.isArchived) continue;
      final rules = snapshot.rulesByHabitUuid[goal.uuid] ?? const [];
      final rule = HabitRuleResolver.effectiveRule(rules, date);
      if (rule == null || !rule.hasPlanningBlock(goal)) continue;
      if (!HabitRuleResolver.isPlannedDay(rule, date)) continue;

      final remainingMinutes = _remainingHabitMinutesForDate(
        goal: goal,
        rule: rule,
        date: date,
        snapshot: snapshot,
        todos: todos,
      );
      if (remainingMinutes <= 0) continue;

      final startMinute = rule.effectivePreferredStartMinute()!;
      final start = DateTime(
        date.year,
        date.month,
        date.day,
        startMinute ~/ 60,
        startMinute % 60,
      );
      final end = start.add(Duration(minutes: remainingMinutes));
      intervals.add(
        PlanBusyInterval(
          start,
          end,
          source: PlanBusySource.habit,
          id: 'habit:${goal.uuid}:$dayKey',
          title: '${goal.icon} ${goal.name}',
          record: goal,
        ),
      );
    }

    final challenge = snapshot.challengeState;
    if (challenge != null &&
        challenge.hasPlanningBlock &&
        !challenge.isCompleted &&
        !challenge.hasCompletedTaskOnDate(date)) {
      final nextTask = challenge.nextUnfinishedTask;
      if (nextTask != null) {
        final startMinute = challenge.effectivePreferredStartMinute!;
        final plannedMinutes = challenge.effectivePlannedMinutes;
        final start = DateTime(
          date.year,
          date.month,
          date.day,
          startMinute ~/ 60,
          startMinute % 60,
        );
        final end = start.add(Duration(minutes: plannedMinutes));
        intervals.add(
          PlanBusyInterval(
            start,
            end,
            source: PlanBusySource.challenge,
            id: 'challenge:${nextTask.id}:$dayKey',
            title: '🎯 ${nextTask.title}',
            record: nextTask,
          ),
        );
      }
    }

    return intervals;
  }

  /// 生成某一天在待办规划网格中的软规划块（包含已完成与待完成状态，方便在时间轴可视化）。
  static List<TodoPlanBlock> buildMappedBlocksForDay({
    required DateTime dayStart,
    required HabitChallengePlanningSnapshot snapshot,
    required List<TodoItem> todos,
  }) {
    final date = DateTime(dayStart.year, dayStart.month, dayStart.day);
    final blocks = <TodoPlanBlock>[];

    for (final goal in snapshot.goals) {
      if (goal.isDeleted || goal.isArchived) continue;
      final rules = snapshot.rulesByHabitUuid[goal.uuid] ?? const [];
      final rule = HabitRuleResolver.effectiveRule(rules, date);
      if (rule == null || !rule.hasPlanningBlock(goal)) continue;
      if (!HabitRuleResolver.isPlannedDay(rule, date)) continue;

      final isSkipped = _isHabitSkippedOnDate(
        goal: goal,
        date: date,
        snapshot: snapshot,
      );
      if (isSkipped) continue;

      final remainingMinutes = _remainingHabitMinutesForDate(
        goal: goal,
        rule: rule,
        date: date,
        snapshot: snapshot,
        todos: todos,
      );
      final isDone = remainingMinutes <= 0;
      final plannedMinutes = rule.effectivePlannedMinutes(goal);
      final startMinute = rule.effectivePreferredStartMinute()!;
      final start = DateTime(
        date.year,
        date.month,
        date.day,
        startMinute ~/ 60,
        startMinute % 60,
      );
      final durationMinutes = isDone ? plannedMinutes : remainingMinutes;
      final end = start.add(Duration(minutes: durationMinutes));
      final focusedSeconds = _focusedSecondsForHabitOnDate(
        goal: goal,
        date: date,
        snapshot: snapshot,
      );

      blocks.add(
        TodoPlanBlock(
          id: '$mappedHabitPrefix${goal.uuid}',
          todoId: 'habit_${goal.uuid}',
          titleSnapshot: '${goal.icon} ${goal.name}',
          startTime: start.millisecondsSinceEpoch,
          endTime: end.millisecondsSinceEpoch,
          plannedMinutes: durationMinutes,
          actualFocusSeconds: focusedSeconds,
          status: isDone ? TodoPlanStatus.finished : TodoPlanStatus.planned,
          source: TodoPlanSource.manual,
          remark: '习惯预留时段',
        ),
      );
    }

    final challenge = snapshot.challengeState;
    if (challenge != null && challenge.hasPlanningBlock) {
      final completedTodayTask = _completedChallengeTaskOnDate(challenge, date);
      final targetTask = completedTodayTask ?? challenge.nextUnfinishedTask;
      if (targetTask != null) {
        final startMinute = challenge.effectivePreferredStartMinute!;
        final plannedMinutes = challenge.effectivePlannedMinutes;
        final start = DateTime(
          date.year,
          date.month,
          date.day,
          startMinute ~/ 60,
          startMinute % 60,
        );
        final end = start.add(Duration(minutes: plannedMinutes));
        blocks.add(
          TodoPlanBlock(
            id: '$mappedChallengePrefix${targetTask.id}',
            todoId: 'challenge_${targetTask.id}',
            titleSnapshot: '🎯 30天挑战：${targetTask.title}',
            startTime: start.millisecondsSinceEpoch,
            endTime: end.millisecondsSinceEpoch,
            plannedMinutes: plannedMinutes,
            status: completedTodayTask != null
                ? TodoPlanStatus.finished
                : TodoPlanStatus.planned,
            source: TodoPlanSource.manual,
            remark: challenge.challengeTitle,
          ),
        );
      }
    }

    return blocks;
  }

  static ThirtyDayChallengeTask? _completedChallengeTaskOnDate(
    ThirtyDayChallengeState challenge,
    DateTime date,
  ) {
    final targetDay = DateTime(date.year, date.month, date.day);
    for (final task in challenge.tasks) {
      if (!task.isCompleted || task.completedAt == null) continue;
      final local = task.completedAt!.toLocal();
      if (DateTime(local.year, local.month, local.day) == targetDay) {
        return task;
      }
    }
    return null;
  }

  static bool _isHabitSkippedOnDate({
    required HabitGoal goal,
    required DateTime date,
    required HabitChallengePlanningSnapshot snapshot,
  }) {
    final dayKey = HabitRuleResolver.dayKey(date);
    final checkIns = snapshot.checkInsByHabitUuid[goal.uuid] ?? const [];
    return checkIns.any(
      (c) =>
          !c.isDeleted &&
          c.logicalDate == dayKey &&
          c.source == HabitCheckInSource.skip,
    );
  }

  /// 计算指定日期该习惯还需预留的分钟数；若今日已达标或已跳过则返回 0。
  static int _remainingHabitMinutesForDate({
    required HabitGoal goal,
    required HabitGoalRuleRevision rule,
    required DateTime date,
    required HabitChallengePlanningSnapshot snapshot,
    required List<TodoItem> todos,
  }) {
    if (_isHabitSkippedOnDate(goal: goal, date: date, snapshot: snapshot)) {
      return 0;
    }

    final plannedMinutes = rule.effectivePlannedMinutes(goal);
    final dayKey = HabitRuleResolver.dayKey(date);
    final periodStart = HabitRuleResolver.periodStart(rule, date);
    final periodEnd = HabitRuleResolver.periodEndExclusive(rule, date);
    final periodStartKey = HabitRuleResolver.dayKey(periodStart);
    final periodEndKey = HabitRuleResolver.dayKey(periodEnd);

    switch (goal.sourceType) {
      case HabitSourceType.recurringTodo:
        final checkIns = snapshot.checkInsByHabitUuid[goal.uuid] ?? const [];
        final hasTodayCheckIn = checkIns.any(
          (c) => !c.isDeleted && c.logicalDate == dayKey,
        );
        if (hasTodayCheckIn) return 0;

        final seriesIds = goal.sourceIds.toSet();
        final seriesTodos = seriesIds.isEmpty
            ? const <TodoItem>[]
            : todos
                  .where(
                    (t) =>
                        !t.isDeleted &&
                        t.recurrenceSeriesId != null &&
                        seriesIds.contains(t.recurrenceSeriesId),
                  )
                  .toList(growable: false);
        final todayTodo = HabitSourceResolver.todoForDate(seriesTodos, date);
        if (todayTodo != null && (todayTodo.isDone || todayTodo.isSkipped)) {
          return 0;
        }
        if (rule.periodType == HabitPeriodType.weekly ||
            rule.periodType == HabitPeriodType.monthly) {
          final periodDoneCount = checkIns
              .where(
                (c) =>
                    !c.isDeleted &&
                    c.source != HabitCheckInSource.skip &&
                    c.logicalDate.compareTo(periodStartKey) >= 0 &&
                    c.logicalDate.compareTo(periodEndKey) < 0,
              )
              .map((c) => c.logicalDate)
              .toSet()
              .length;
          final index = HabitSourceResolver.indexTodos(seriesTodos);
          final todoCount = index.completedCountInRange(periodStart, periodEnd);
          final target = rule.targetValue > 0 ? rule.targetValue : 1;
          if ((periodDoneCount + todoCount) >= target) return 0;
        }
        return plannedMinutes;

      case HabitSourceType.timeCheckIn:
        final checkIns = snapshot.checkInsByHabitUuid[goal.uuid] ?? const [];
        final hasTodayCheckIn = checkIns.any(
          (c) =>
              !c.isDeleted &&
              c.source != HabitCheckInSource.skip &&
              c.logicalDate == dayKey,
        );
        return hasTodayCheckIn ? 0 : plannedMinutes;

      case HabitSourceType.quantityCheckIn:
        final checkIns = snapshot.checkInsByHabitUuid[goal.uuid] ?? const [];
        final todaySum = checkIns
            .where(
              (c) =>
                  !c.isDeleted &&
                  c.source != HabitCheckInSource.skip &&
                  c.logicalDate == dayKey,
            )
            .fold<double>(0, (sum, c) => sum + c.value);
        final periodSum = checkIns
            .where(
              (c) =>
                  !c.isDeleted &&
                  c.source != HabitCheckInSource.skip &&
                  c.logicalDate.compareTo(periodStartKey) >= 0 &&
                  c.logicalDate.compareTo(periodEndKey) < 0,
            )
            .fold<double>(0, (sum, c) => sum + c.value);
        final target = rule.targetValue > 0 ? rule.targetValue : 1;
        if (periodSum >= target) return 0;
        if ((rule.periodType == HabitPeriodType.weekly ||
                rule.periodType == HabitPeriodType.monthly) &&
            todaySum > 0) {
          return 0;
        }
        return plannedMinutes;

      case HabitSourceType.durationCheckIn:
        final checkIns = snapshot.checkInsByHabitUuid[goal.uuid] ?? const [];
        final todaySeconds = checkIns
            .where(
              (c) =>
                  !c.isDeleted &&
                  c.source != HabitCheckInSource.skip &&
                  c.logicalDate == dayKey,
            )
            .fold<double>(0, (sum, c) => sum + c.value);
        final periodSeconds = checkIns
            .where(
              (c) =>
                  !c.isDeleted &&
                  c.source != HabitCheckInSource.skip &&
                  c.logicalDate.compareTo(periodStartKey) >= 0 &&
                  c.logicalDate.compareTo(periodEndKey) < 0,
            )
            .fold<double>(0, (sum, c) => sum + c.value);
        if (rule.targetValue > 0 && periodSeconds >= rule.targetValue) {
          return 0;
        }
        final doneMinutes = (todaySeconds / 60).floor();
        return max(0, plannedMinutes - doneMinutes);

      case HabitSourceType.pomodoroTag:
        final tagIds = goal.sourceIds.toSet();
        if (tagIds.isEmpty) return plannedMinutes;
        var todaySeconds = 0;
        var periodSeconds = 0;
        for (final record in snapshot.pomodoroRecords) {
          if (record.isDeleted || !record.isCompleted || record.hasConflict) {
            continue;
          }
          if (!record.tagUuids.any(tagIds.contains)) continue;
          final localStart = DateTime.fromMillisecondsSinceEpoch(
            record.startTime,
          ).toLocal();
          final logical = HabitRuleResolver.logicalDateFor(
            localStart,
            rule.dayBoundaryMinute,
          );
          final recordKey = HabitRuleResolver.dayKey(logical);
          if (recordKey == dayKey) {
            todaySeconds += record.effectiveDuration;
          }
          if (recordKey.compareTo(periodStartKey) >= 0 &&
              recordKey.compareTo(periodEndKey) < 0) {
            periodSeconds += record.effectiveDuration;
          }
        }
        if (rule.targetValue > 0 && periodSeconds >= rule.targetValue) {
          return 0;
        }
        final doneMinutes = (todaySeconds / 60).floor();
        return max(0, plannedMinutes - doneMinutes);
    }
  }

  static int _focusedSecondsForHabitOnDate({
    required HabitGoal goal,
    required DateTime date,
    required HabitChallengePlanningSnapshot snapshot,
  }) {
    final rules = snapshot.rulesByHabitUuid[goal.uuid] ?? const [];
    final rule = HabitRuleResolver.effectiveRule(rules, date);
    final dayBoundary = rule?.dayBoundaryMinute ?? 0;
    final dayKey = HabitRuleResolver.dayKey(date);
    final tagIds = (rule?.effectiveFocusTagUuids(goal) ?? goal.sourceIds)
        .toSet();
    if (tagIds.isEmpty) return 0;
    var seconds = 0;
    for (final record in snapshot.pomodoroRecords) {
      if (record.isDeleted || !record.isCompleted || record.hasConflict) {
        continue;
      }
      if (!record.tagUuids.any(tagIds.contains)) continue;
      final localStart = DateTime.fromMillisecondsSinceEpoch(record.startTime)
          .toLocal();
      final logical = HabitRuleResolver.logicalDateFor(localStart, dayBoundary);
      if (HabitRuleResolver.dayKey(logical) == dayKey) {
        seconds += record.effectiveDuration;
      }
    }
    return seconds;
  }
}
