import '../../../services/storage/habit_storage.dart';
import '../../../services/storage/user_session_storage.dart';
import '../../../storage_service.dart';
import '../models/habit_checkin.dart';
import '../models/habit_goal.dart';
import '../models/habit_goal_rule.dart';
import '../models/habit_sleep_coaching_plan.dart';
import '../repositories/habit_repository.dart';
import 'habit_adaptation_service.dart';
import 'habit_rule_resolver.dart';
import 'habit_sleep_goal_resolver.dart';

/// 睡眠训练中一个维度的当前值、最终目标和本阶段建议值。
class HabitSleepCoachingMetric {
  final HabitAdaptationKind kind;
  final int? currentValue;
  final int? baselineValue;
  final int? targetValue;
  final int stageTarget;
  final int maxStage;

  const HabitSleepCoachingMetric({
    required this.kind,
    required this.currentValue,
    required this.baselineValue,
    required this.targetValue,
    required this.stageTarget,
    required this.maxStage,
  });

  bool get isAvailable => targetValue != null;
}

/// 三个睡眠详情页共享的训练状态快照。
class HabitSleepCoachingSnapshot {
  final HabitSleepCoachingPlan plan;
  final int stageIndex;
  final int stageProgressDays;
  final List<HabitSleepCoachingMetric> metrics;

  const HabitSleepCoachingSnapshot({
    required this.plan,
    required this.stageIndex,
    required this.stageProgressDays,
    required this.metrics,
  });

  HabitSleepCoachingMetric? metricFor(HabitAdaptationKind kind) {
    for (final metric in metrics) {
      if (metric.kind == kind) return metric;
    }
    return null;
  }

  int get maxStage => metrics.fold<int>(
        0,
        (value, metric) => value > metric.maxStage ? value : metric.maxStage,
      );
}

/// 睡眠训练计划的读写与阶段推导。
///
/// 正常阶段由同一账号下已经同步的打卡事件推导；暂停时额外保存一个
/// 跨端同步的检查点，恢复后从检查点之后继续，避免暂停期间的记录偷推进度。
abstract final class HabitSleepCoachingService {
  static const int defaultStepMinutes = 15;
  static const int defaultStageDays = 4;

  static Future<HabitSleepCoachingPlan?> getPlan(String username) async {
    if (username.trim().isEmpty) return null;
    final plans = await HabitStorage.getSleepCoachingPlans();
    final stableUuid = HabitSleepCoachingPlan.stableUuidFor(username);
    for (final plan in plans) {
      if (plan.uuid == stableUuid &&
          plan.kind == HabitSleepCoachingPlan.planKind) {
        return plan;
      }
    }
    return null;
  }

  static Future<HabitSleepCoachingSnapshot?> load(String username) async {
    if (username.trim().isEmpty) return null;
    final plan = await getPlan(username);
    if (plan == null) return null;
    final goals = await HabitRepository.getGoals();
    final rules = await HabitRepository.getRules();
    final checkIns = await HabitRepository.getCheckIns();
    if (plan.timezoneOffsetMinutes == null) {
      // 兼容首个版本创建的计划：优先从已经同步的睡眠打卡推断原始偏移，
      // 这样两台设备首次打开旧计划时不会各自写入本机时区。
      plan.timezoneOffsetMinutes = _inferredTimezoneOffset(goals, checkIns) ??
          DateTime.now().timeZoneOffset.inMinutes;
      plan.markAsChanged();
      await HabitStorage.saveSleepCoachingPlans([plan]);
      StorageService.requestSync(username);
    }
    return _buildSnapshot(
      plan: plan,
      goals: goals,
      rules: rules,
      checkIns: checkIns,
    );
  }

  /// 将当前时刻转换为计划固定时区下的逻辑日期。
  static DateTime logicalTodayForPlan(
    HabitSleepCoachingPlan plan, {
    DateTime? now,
  }) {
    final nowInPlanTimezone = (now ?? DateTime.now())
        .toUtc()
        .add(Duration(minutes: plan.timezoneOffsetMinutes ?? 0));
    return DateTime(
      nowInPlanTimezone.year,
      nowInPlanTimezone.month,
      nowInPlanTimezone.day,
    );
  }

  static DateTime _nowInPlanTimezone(
    HabitSleepCoachingPlan plan, {
    DateTime? now,
  }) {
    return (now ?? DateTime.now())
        .toUtc()
        .add(Duration(minutes: plan.timezoneOffsetMinutes ?? 0));
  }

  static int? _inferredTimezoneOffset(
    List<HabitGoal> goals,
    List<HabitCheckIn> checkIns,
  ) {
    final sleepGoalUuids = goals
        .where((goal) {
          final kind = HabitAdaptationService.forHabit(goal)?.kind;
          return !goal.isDeleted &&
              (kind == HabitAdaptationKind.earlySleep ||
                  kind == HabitAdaptationKind.earlyWake ||
                  kind == HabitAdaptationKind.sleepDuration);
        })
        .map((goal) => goal.uuid)
        .toSet();
    if (sleepGoalUuids.isEmpty) return null;
    final counts = <int, int>{};
    for (final checkIn in checkIns) {
      if (checkIn.isDeleted || !sleepGoalUuids.contains(checkIn.habitUuid)) {
        continue;
      }
      final offset =
          checkIn.timezoneOffsetMinutes.clamp(-14 * 60, 14 * 60).toInt();
      counts[offset] = (counts[offset] ?? 0) + 1;
    }
    if (counts.isEmpty) return null;
    final sorted = counts.entries.toList()
      ..sort((a, b) => b.value != a.value
          ? b.value.compareTo(a.value)
          : a.key.compareTo(b.key));
    return sorted.first.key;
  }

  /// 开启新计划时一次性记录当前作息基线。基线随计划同步，后续设备不会
  /// 因为本地最近几天数据变化而重新起算。
  static Future<HabitSleepCoachingSnapshot> enable({
    required String username,
    int stepMinutes = defaultStepMinutes,
    int stageDays = defaultStageDays,
  }) async {
    if (username.trim().isEmpty) {
      throw ArgumentError('睡眠训练需要登录账号');
    }
    final goals = await HabitRepository.getGoals();
    final rules = await HabitRepository.getRules();
    final checkIns = await HabitRepository.getCheckIns();
    final deviceId = await UserSessionStorage.getDeviceId();
    final now = DateTime.now();
    final existing = await getPlan(username);
    final plan = existing ??
        HabitSleepCoachingPlan(
          uuid: HabitSleepCoachingPlan.stableUuidFor(username),
          deviceId: deviceId,
        );
    plan.enabled = true;
    plan.paused = false;
    plan.stepMinutes = stepMinutes.clamp(5, 60).toInt();
    plan.stageDays = stageDays.clamp(1, 14).toInt();
    plan.timezoneOffsetMinutes = now.timeZoneOffset.inMinutes;
    plan.pausedStageIndex = null;
    plan.pausedProgressDays = null;
    plan.pausedLogicalDate = null;
    plan.startedLogicalDate = HabitRuleResolver.dayKey(
      logicalTodayForPlan(plan, now: now),
    );
    final metrics = _metricInputs(goals, rules, checkIns, plan: plan);
    plan.baselineBedtimeMinute =
        metrics[HabitAdaptationKind.earlySleep]?.baseline;
    plan.baselineWakeMinute = metrics[HabitAdaptationKind.earlyWake]?.baseline;
    plan.baselineSleepMinutes =
        metrics[HabitAdaptationKind.sleepDuration]?.baseline;
    plan.isDeleted = false;
    plan.deviceId = deviceId;
    if (existing != null) plan.markAsChanged();
    await HabitStorage.saveSleepCoachingPlans([plan]);
    StorageService.requestSync(username);
    return _buildSnapshot(
      plan: plan,
      goals: goals,
      rules: rules,
      checkIns: checkIns,
    );
  }

  static Future<HabitSleepCoachingPlan> setEnabled({
    required String username,
    required HabitSleepCoachingPlan plan,
    required bool enabled,
  }) async {
    if (username.trim().isEmpty) {
      throw ArgumentError('睡眠训练需要登录账号');
    }
    plan.enabled = enabled;
    if (!enabled) {
      plan.paused = false;
      plan.pausedStageIndex = null;
      plan.pausedProgressDays = null;
      plan.pausedLogicalDate = null;
    }
    plan.markAsChanged();
    await HabitStorage.saveSleepCoachingPlans([plan]);
    StorageService.requestSync(username);
    return plan;
  }

  static Future<HabitSleepCoachingPlan> setPaused({
    required String username,
    required HabitSleepCoachingPlan plan,
    required bool paused,
  }) async {
    if (username.trim().isEmpty) {
      throw ArgumentError('睡眠训练需要登录账号');
    }
    if (paused) {
      final goals = await HabitRepository.getGoals();
      final rules = await HabitRepository.getRules();
      final checkIns = await HabitRepository.getCheckIns();
      final wasPaused = plan.paused;
      plan.paused = false;
      final current = _buildSnapshot(
        plan: plan,
        goals: goals,
        rules: rules,
        checkIns: checkIns,
      );
      plan.paused = wasPaused;
      plan.pausedStageIndex = current.stageIndex;
      plan.pausedProgressDays = current.stageProgressDays;
      plan.pausedLogicalDate = HabitRuleResolver.dayKey(
        logicalTodayForPlan(plan),
      );
    }
    plan.paused = paused;
    plan.markAsChanged();
    await HabitStorage.saveSleepCoachingPlans([plan]);
    StorageService.requestSync(username);
    return plan;
  }

  static Future<HabitSleepCoachingPlan> updateSettings({
    required String username,
    required HabitSleepCoachingPlan plan,
    required int stepMinutes,
    required int stageDays,
  }) async {
    if (username.trim().isEmpty) {
      throw ArgumentError('睡眠训练需要登录账号');
    }
    plan.stepMinutes = stepMinutes.clamp(5, 60).toInt();
    plan.stageDays = stageDays.clamp(1, 14).toInt();
    final wasPaused = plan.paused;
    plan.pausedStageIndex = null;
    plan.pausedProgressDays = null;
    plan.pausedLogicalDate = null;
    if (wasPaused) {
      final goals = await HabitRepository.getGoals();
      final rules = await HabitRepository.getRules();
      final checkIns = await HabitRepository.getCheckIns();
      plan.paused = false;
      final current = _buildSnapshot(
        plan: plan,
        goals: goals,
        rules: rules,
        checkIns: checkIns,
      );
      plan.pausedStageIndex = current.stageIndex;
      plan.pausedProgressDays = current.stageProgressDays;
      plan.pausedLogicalDate = HabitRuleResolver.dayKey(
        logicalTodayForPlan(plan),
      );
      plan.paused = true;
    }
    plan.markAsChanged();
    await HabitStorage.saveSleepCoachingPlans([plan]);
    StorageService.requestSync(username);
    return plan;
  }

  static Map<HabitAdaptationKind, _MetricInput> _metricInputs(
      List<HabitGoal> goals,
      List<HabitGoalRuleRevision> rules,
      List<HabitCheckIn> checkIns,
      {HabitSleepCoachingPlan? plan}) {
    final result = <HabitAdaptationKind, _MetricInput>{};
    for (final kind in const [
      HabitAdaptationKind.earlySleep,
      HabitAdaptationKind.earlyWake,
      HabitAdaptationKind.sleepDuration,
    ]) {
      final goal = HabitSleepGoalResolver.canonical(goals, kind);
      if (goal == null) continue;
      final goalRules =
          rules.where((rule) => rule.habitUuid == goal.uuid).toList();
      final referenceNow =
          plan == null ? DateTime.now() : _nowInPlanTimezone(plan);
      final finalRule = HabitRuleResolver.currentRule(
        goalRules,
        goalRules.isEmpty
            ? HabitRuleResolver.defaultDayBoundaryMinute
            : _effectiveBoundary(goalRules.first.dayBoundaryMinute),
        referenceNow,
      );
      final dayBoundaryMinute = finalRule?.dayBoundaryMinute ??
          HabitRuleResolver.defaultDayBoundaryMinute;
      final target = kind == HabitAdaptationKind.sleepDuration
          ? finalRule == null
              ? null
              : (finalRule.targetValue / 60).round()
          : finalRule?.targetTimeMinute == null
              ? null
              : _minuteFor(kind, finalRule!.targetTimeMinute!);
      final records = checkIns
          .where((checkIn) =>
              checkIn.habitUuid == goal.uuid &&
              !checkIn.isDeleted &&
              checkIn.source != HabitCheckInSource.skip)
          .toList()
        ..sort((a, b) => a.occurredAt.compareTo(b.occurredAt));
      final recentCutoff = DateTime.now()
          .subtract(const Duration(days: 14))
          .millisecondsSinceEpoch;
      final baselineRecords =
          records.where((record) => record.occurredAt >= recentCutoff).toList();
      final baseline = records.isEmpty
          ? target
          : _median((baselineRecords.isEmpty ? records : baselineRecords)
              .map((record) => _recordValue(kind, record))
              .toList());
      result[kind] = _MetricInput(
        kind: kind,
        goalUuid: goal.uuid,
        target: target,
        baseline: baseline,
        records: records,
        dayBoundaryMinute: dayBoundaryMinute,
      );
    }
    return result;
  }

  static HabitSleepCoachingSnapshot _buildSnapshot({
    required HabitSleepCoachingPlan plan,
    required List<HabitGoal> goals,
    required List<HabitGoalRuleRevision> rules,
    required List<HabitCheckIn> checkIns,
  }) {
    final inputs = _metricInputs(goals, rules, checkIns, plan: plan);
    final normalizedInputs = <HabitAdaptationKind, _MetricInput>{};
    for (final entry in inputs.entries) {
      final storedBaseline = switch (entry.key) {
        HabitAdaptationKind.earlySleep => plan.baselineBedtimeMinute,
        HabitAdaptationKind.earlyWake => plan.baselineWakeMinute,
        HabitAdaptationKind.sleepDuration => plan.baselineSleepMinutes,
        _ => null,
      };
      normalizedInputs[entry.key] = entry.value.copyWith(
        baseline: storedBaseline ?? entry.value.baseline,
      );
    }

    final maxStage = normalizedInputs.values.fold<int>(0, (value, input) {
      final distance = _distance(input.kind, input.baseline, input.target);
      final count = distance <= 0 ? 0 : (distance / plan.stepMinutes).ceil();
      return value > count ? value : count;
    });
    final progression = _progression(
      plan: plan,
      inputs: normalizedInputs,
      maxStage: maxStage,
    );
    final metrics = normalizedInputs.values.map((input) {
      final stageTarget = _stageTarget(
        input.kind,
        input.baseline,
        input.target,
        progression.stageIndex,
        plan.stepMinutes,
      );
      final current = input.records.isEmpty
          ? null
          : _recordValue(input.kind, input.records.last);
      final metricMaxStage =
          _distance(input.kind, input.baseline, input.target) <= 0
              ? 0
              : (_distance(input.kind, input.baseline, input.target) /
                      plan.stepMinutes)
                  .ceil();
      return HabitSleepCoachingMetric(
        kind: input.kind,
        currentValue: current,
        baselineValue: input.baseline,
        targetValue: input.target,
        stageTarget: stageTarget ?? input.target ?? 0,
        maxStage: metricMaxStage,
      );
    }).toList();
    return HabitSleepCoachingSnapshot(
      plan: plan,
      stageIndex: progression.stageIndex,
      stageProgressDays: progression.progressDays,
      metrics: metrics,
    );
  }

  static _Progression _progression({
    required HabitSleepCoachingPlan plan,
    required Map<HabitAdaptationKind, _MetricInput> inputs,
    required int maxStage,
  }) {
    if (!plan.enabled || maxStage <= 0) {
      return const _Progression(stageIndex: 0, progressDays: 0);
    }
    if (plan.paused) {
      return _Progression(
        stageIndex: (plan.pausedStageIndex ?? 0).clamp(0, maxStage).toInt(),
        progressDays:
            (plan.pausedProgressDays ?? 0).clamp(0, plan.stageDays).toInt(),
      );
    }
    final start = HabitRuleResolver.parseDayKey(plan.startedLogicalDate ?? '');
    if (start == null) {
      return const _Progression(stageIndex: 0, progressDays: 0);
    }
    final today = logicalTodayForPlan(plan);
    var stage = plan.pausedStageIndex ?? 0;
    var progressDays = plan.pausedProgressDays ?? 0;
    final checkpoint = HabitRuleResolver.parseDayKey(
      plan.pausedLogicalDate ?? '',
    );
    final firstDay = checkpoint == null
        ? DateTime(start.year, start.month, start.day)
        : checkpoint.add(const Duration(days: 1));
    if (firstDay.isAfter(today)) {
      return _Progression(
        stageIndex: stage.clamp(0, maxStage).toInt(),
        progressDays: progressDays.clamp(0, plan.stageDays).toInt(),
      );
    }
    for (var day = firstDay;
        !day.isAfter(today);
        day = day.add(const Duration(days: 1))) {
      if (stage >= maxStage) break;
      final actuals = <HabitAdaptationKind, int>{};
      for (final input in inputs.values) {
        final record = input.records
            .where((candidate) =>
                _recordLogicalDateForPlan(candidate, input, plan) ==
                HabitRuleResolver.dayKey(day))
            .lastOrNull;
        if (record != null) {
          actuals[input.kind] = _recordValue(input.kind, record);
        }
      }
      if (actuals.isEmpty) continue;
      if (actuals.length != inputs.length) {
        continue;
      }
      final passed = inputs.values.every((input) {
        final actual = actuals[input.kind];
        final expected = _stageTarget(
          input.kind,
          input.baseline,
          input.target,
          stage,
          plan.stepMinutes,
        );
        return actual != null &&
            expected != null &&
            _isMet(input.kind, actual, expected);
      });
      if (passed) {
        progressDays++;
        if (progressDays >= plan.stageDays) {
          stage++;
          progressDays = 0;
        }
      } else {
        progressDays = 0;
      }
    }
    return _Progression(
      stageIndex: stage.clamp(0, maxStage).toInt(),
      progressDays: progressDays,
    );
  }

  static bool _isMet(HabitAdaptationKind kind, int actual, int expected) {
    const toleranceMinutes = 15;
    switch (kind) {
      case HabitAdaptationKind.earlySleep:
      case HabitAdaptationKind.earlyWake:
        return actual >= expected - toleranceMinutes &&
            actual <= expected + toleranceMinutes;
      case HabitAdaptationKind.sleepDuration:
        return actual >= expected - toleranceMinutes &&
            actual <= expected + toleranceMinutes;
      default:
        return false;
    }
  }

  static int? _stageTarget(
    HabitAdaptationKind kind,
    int? baseline,
    int? target,
    int stage,
    int stepMinutes,
  ) {
    if (baseline == null || target == null) return target;
    final distance = _distance(kind, baseline, target);
    final movement = (stage * stepMinutes).clamp(0, distance).toInt();
    switch (kind) {
      case HabitAdaptationKind.earlySleep:
      case HabitAdaptationKind.earlyWake:
        return baseline - movement;
      case HabitAdaptationKind.sleepDuration:
        return baseline + movement;
      default:
        return target;
    }
  }

  static int _distance(
    HabitAdaptationKind kind,
    int? baseline,
    int? target,
  ) {
    if (baseline == null || target == null) return 0;
    switch (kind) {
      case HabitAdaptationKind.earlySleep:
      case HabitAdaptationKind.earlyWake:
        return (baseline - target).clamp(0, 24 * 60).toInt();
      case HabitAdaptationKind.sleepDuration:
        return (target - baseline).clamp(0, 24 * 60).toInt();
      default:
        return 0;
    }
  }

  static int _recordValue(HabitAdaptationKind kind, HabitCheckIn record) {
    if (kind == HabitAdaptationKind.sleepDuration) {
      return (record.value / 60).round();
    }
    return _minuteFor(
        kind, record.localOccurredAt.hour * 60 + record.localOccurredAt.minute);
  }

  static String _recordLogicalDateForPlan(
    HabitCheckIn record,
    _MetricInput input,
    HabitSleepCoachingPlan plan,
  ) {
    final occurredInOriginalTimezone = DateTime.fromMillisecondsSinceEpoch(
      record.occurredAt,
      isUtc: true,
    ).add(Duration(minutes: record.timezoneOffsetMinutes));
    final date = switch (input.kind) {
      // 凌晨入睡属于前一晚；dayBoundary=0 是旧规则的“未配置”写法。
      HabitAdaptationKind.earlySleep => HabitRuleResolver.logicalDateFor(
          occurredInOriginalTimezone,
          _effectiveBoundary(input.dayBoundaryMinute),
        ),
      // 起床打卡属于前一晚。只对中午前的起床做回退，避免凌晨起床被
      // 04:00 分界再额外回退一天。
      HabitAdaptationKind.earlyWake => DateTime(
          occurredInOriginalTimezone.year,
          occurredInOriginalTimezone.month,
          occurredInOriginalTimezone.day,
        ).subtract(
            Duration(days: occurredInOriginalTimezone.hour < 12 ? 1 : 0)),
      // 自动生成的睡眠时长记录发生时刻沿用入睡时刻，因此与早睡使用
      // 同一夜间日期；手动记录也保持其保存时的本地日期语义。
      HabitAdaptationKind.sleepDuration => HabitRuleResolver.logicalDateFor(
          occurredInOriginalTimezone,
          _effectiveBoundary(input.dayBoundaryMinute),
        ),
      _ => occurredInOriginalTimezone,
    };
    return HabitRuleResolver.dayKey(
      date,
    );
  }

  static int _effectiveBoundary(int boundaryMinute) {
    return boundaryMinute == 0
        ? HabitRuleResolver.defaultDayBoundaryMinute
        : boundaryMinute;
  }

  static int _minuteFor(HabitAdaptationKind kind, int minute) {
    if (kind == HabitAdaptationKind.earlySleep && minute < 12 * 60) {
      return minute + 24 * 60;
    }
    return minute;
  }

  static int _median(List<int> values) {
    if (values.isEmpty) return 0;
    final sorted = [...values]..sort();
    return sorted[sorted.length ~/ 2];
  }
}

class _MetricInput {
  final HabitAdaptationKind kind;
  final String goalUuid;
  final int? target;
  final int? baseline;
  final List<HabitCheckIn> records;
  final int dayBoundaryMinute;

  const _MetricInput({
    required this.kind,
    required this.goalUuid,
    required this.target,
    required this.baseline,
    required this.records,
    required this.dayBoundaryMinute,
  });

  _MetricInput copyWith({int? baseline}) => _MetricInput(
        kind: kind,
        goalUuid: goalUuid,
        target: target,
        baseline: baseline ?? this.baseline,
        records: records,
        dayBoundaryMinute: dayBoundaryMinute,
      );
}

class _Progression {
  final int stageIndex;
  final int progressDays;

  const _Progression({required this.stageIndex, required this.progressDays});
}

extension<T> on Iterable<T> {
  T? get lastOrNull => isEmpty ? null : last;
}
