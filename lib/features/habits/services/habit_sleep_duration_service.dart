import '../../../services/storage/habit_storage.dart';
import '../models/habit_checkin.dart';
import '../models/habit_goal.dart';
import '../models/habit_goal_rule.dart';
import '../repositories/habit_repository.dart';
import 'habit_adaptation_service.dart';
import 'habit_rule_resolver.dart';

/// 早睡 / 早起打卡配对后生成睡眠时长打卡。
///
/// 睡眠时长属于独立时长型习惯，值以秒保存，规则目标也以秒保存。
/// 自动记录使用 [HabitCheckInSource.import]；用户编辑后会变成 manual，
/// 后续同步不会覆盖手动修正。
abstract final class HabitSleepDurationService {
  static const int minimumSleepMinutes = 3 * 60;
  static const int maximumSleepMinutes = 16 * 60;
  static bool _syncing = false;

  static bool isSleepDurationGoal(HabitGoal goal) {
    return goal.sourceType == HabitSourceType.durationCheckIn &&
        HabitAdaptationService.forHabit(goal)?.kind ==
            HabitAdaptationKind.sleepDuration;
  }

  /// 今日视图展示的睡眠日期：睡眠记录属于前一晚，而不是今天。
  static DateTime displayLogicalDateFor(HabitGoal goal, DateTime date) {
    final day = DateTime(date.year, date.month, date.day);
    return isSleepDurationGoal(goal)
        ? day.subtract(const Duration(days: 1))
        : day;
  }

  /// 刷新所有睡眠时长习惯，供今日页和详情页加载时调用。
  static Future<int> syncAll() async {
    if (_syncing) return 0;
    _syncing = true;
    try {
      final goals = await HabitRepository.getGoals();
      final durationGoals = goals
          .where((goal) =>
              !goal.isDeleted && !goal.isArchived && isSleepDurationGoal(goal))
          .toList(growable: false);
      if (durationGoals.isEmpty) return 0;

      final earlySleep = _firstGoal(goals, HabitAdaptationKind.earlySleep);
      final earlyWake = _firstGoal(goals, HabitAdaptationKind.earlyWake);
      if (earlySleep == null || earlyWake == null) return 0;

      final sleepCheckIns = await HabitRepository.getCheckIns(
        habitUuid: earlySleep.uuid,
      );
      final wakeCheckIns = await HabitRepository.getCheckIns(
        habitUuid: earlyWake.uuid,
      );
      final pairs = _pairCheckIns(sleepCheckIns, wakeCheckIns);
      var synced = 0;
      for (final goal in durationGoals) {
        synced += await _syncGoal(goal: goal, pairs: pairs);
      }
      return synced;
    } finally {
      _syncing = false;
    }
  }

  static Future<int> _syncGoal({
    required HabitGoal goal,
    required List<_SleepPair> pairs,
  }) async {
    final rules = await HabitRepository.getRules(habitUuid: goal.uuid);
    final activeRules = rules.where((rule) => !rule.isDeleted).toList();
    if (activeRules.isEmpty) return 0;
    final rule = _currentRule(goal, activeRules);
    if (rule == null) return 0;

    final allExisting = await HabitStorage.getCheckIns(
      habitUuid: goal.uuid,
      includeDeleted: true,
    );
    final byKey = <String, HabitCheckIn>{};
    final manualLogicalDates = <String>{};
    for (final checkIn in allExisting) {
      final key = checkIn.dedupeKey;
      if (key != null) byKey[key] = checkIn;
      if (!checkIn.isDeleted && checkIn.source == HabitCheckInSource.manual) {
        manualLogicalDates.add(checkIn.logicalDate);
      }
    }

    final activeKeys = <String>{};
    var synced = 0;
    for (final pair in pairs) {
      final localBedtime = pair.bedtime.localOccurredAt;
      final logicalDate = HabitRuleResolver.dayKey(
        HabitRuleResolver.logicalDateFor(
          localBedtime,
          rule.dayBoundaryMinute,
        ),
      );
      final dedupeKey = _dedupeKey(goal, logicalDate);
      activeKeys.add(dedupeKey);
      final seconds = pair.duration.inSeconds.toDouble();
      final note =
          '自动提取 · ${_formatTime(localBedtime)}–${_formatTime(pair.wake.localOccurredAt)} · '
          '${_formatDuration(pair.duration.inMinutes)}';
      final existing = byKey[dedupeKey];
      if (manualLogicalDates.contains(logicalDate) ||
          (existing != null &&
              !existing.isDeleted &&
              existing.source == HabitCheckInSource.manual)) {
        // 用户已经修正过这一晚，自动同步只保留用户的值。
        continue;
      }

      if (existing == null) {
        await HabitRepository.addCheckIn(
          goal: goal,
          rule: rule,
          localOccurredAt: localBedtime,
          value: seconds,
          note: note,
          source: HabitCheckInSource.import,
          dedupeKey: dedupeKey,
        );
        synced++;
        continue;
      }

      final occurredAt = localBedtime.toUtc().millisecondsSinceEpoch;
      final timezoneOffsetMinutes = localBedtime.timeZoneOffset.inMinutes;
      // syncAll() runs whenever the today-habits card is refreshed.  Avoid
      // rewriting an identical generated record: updateCheckIn() increments
      // its version and emits a habits refresh, which would otherwise cause
      // the card to reload itself indefinitely.
      if (!existing.isDeleted &&
          existing.ruleRevisionUuid == rule.uuid &&
          existing.occurredAt == occurredAt &&
          existing.logicalDate == logicalDate &&
          existing.timezoneOffsetMinutes == timezoneOffsetMinutes &&
          existing.value == seconds &&
          existing.note == note &&
          existing.source == HabitCheckInSource.import &&
          existing.dedupeKey == dedupeKey) {
        continue;
      }

      final updated = HabitCheckIn.fromJson(existing.toJson())
        ..isDeleted = false
        ..ruleRevisionUuid = rule.uuid
        ..occurredAt = occurredAt
        ..logicalDate = logicalDate
        ..timezoneOffsetMinutes = timezoneOffsetMinutes
        ..value = seconds
        ..note = note
        ..source = HabitCheckInSource.import
        ..dedupeKey = dedupeKey;
      await HabitRepository.updateCheckIn(updated);
      synced++;
    }

    // 如果原来的早睡或早起节点被删除，移除对应的自动时长记录；
    // 手动修正的记录始终保留。
    for (final checkIn in allExisting) {
      final key = checkIn.dedupeKey;
      if (checkIn.isDeleted ||
          checkIn.source == HabitCheckInSource.manual ||
          key == null ||
          !key.startsWith('habit-checkin/${goal.uuid}/sleep-pair/')) {
        continue;
      }
      if (!activeKeys.contains(key)) {
        await HabitRepository.deleteCheckIn(checkIn);
        synced++;
      }
    }
    return synced;
  }

  static List<_SleepPair> _pairCheckIns(
    List<HabitCheckIn> sleepCheckIns,
    List<HabitCheckIn> wakeCheckIns,
  ) {
    final bedtimes = sleepCheckIns
        .where((checkIn) =>
            !checkIn.isDeleted && checkIn.source != HabitCheckInSource.skip)
        .toList()
      ..sort((a, b) => a.occurredAt.compareTo(b.occurredAt));
    final wakeTimes = wakeCheckIns
        .where((checkIn) =>
            !checkIn.isDeleted && checkIn.source != HabitCheckInSource.skip)
        .toList()
      ..sort((a, b) => a.occurredAt.compareTo(b.occurredAt));
    final usedWakeUuids = <String>{};
    final pairs = <_SleepPair>[];

    for (final bedtime in bedtimes) {
      final bed = bedtime.localOccurredAt;
      HabitCheckIn? matchedWake;
      Duration? matchedDuration;
      for (final wake in wakeTimes) {
        if (usedWakeUuids.contains(wake.uuid)) continue;
        final duration = wake.localOccurredAt.difference(bed);
        if (duration.inMinutes < minimumSleepMinutes ||
            duration.inMinutes > maximumSleepMinutes) {
          continue;
        }
        if (matchedDuration == null ||
            duration.compareTo(matchedDuration) < 0) {
          matchedWake = wake;
          matchedDuration = duration;
        }
      }
      if (matchedWake != null && matchedDuration != null) {
        usedWakeUuids.add(matchedWake.uuid);
        pairs.add(
          _SleepPair(
            bedtime: bedtime,
            wake: matchedWake,
            duration: matchedDuration,
          ),
        );
      }
    }
    return pairs;
  }

  static HabitGoal? _firstGoal(
    Iterable<HabitGoal> goals,
    HabitAdaptationKind kind,
  ) {
    for (final goal in goals) {
      if (goal.isDeleted ||
          goal.isArchived ||
          goal.sourceType != HabitSourceType.timeCheckIn) {
        continue;
      }
      if (HabitAdaptationService.forHabit(goal)?.kind == kind) return goal;
    }
    return null;
  }

  static HabitGoalRuleRevision? _currentRule(
    HabitGoal goal,
    List<HabitGoalRuleRevision> rules,
  ) {
    for (final rule in rules) {
      if (rule.uuid == goal.currentRuleUuid) return rule;
    }
    return HabitRuleResolver.effectiveRule(rules, DateTime.now()) ?? rules.last;
  }

  static String _dedupeKey(HabitGoal goal, String logicalDate) {
    return HabitCheckIn.buildDedupeKey(
      goal.uuid,
      'sleep-pair/$logicalDate',
    )!;
  }

  static String _formatTime(DateTime value) =>
      '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';

  static String _formatDuration(int minutes) {
    final hours = minutes ~/ 60;
    final remainder = minutes % 60;
    if (remainder == 0) return '$hours 小时';
    return '$hours 小时 ${remainder.toString().padLeft(2, '0')} 分';
  }
}

class _SleepPair {
  final HabitCheckIn bedtime;
  final HabitCheckIn wake;
  final Duration duration;

  const _SleepPair({
    required this.bedtime,
    required this.wake,
    required this.duration,
  });
}
