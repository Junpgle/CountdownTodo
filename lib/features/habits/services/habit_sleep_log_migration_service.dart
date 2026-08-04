import '../../../models.dart';
import '../models/habit_goal.dart';
import '../models/habit_goal_rule.dart';
import '../repositories/habit_repository.dart';
import '../services/habit_adaptation_service.dart';
import '../services/habit_rule_resolver.dart';

/// 从旧时间日志迁移到早睡 / 早起习惯时使用的建议。
///
/// 建议只基于最近的有效夜间睡眠记录生成，不会修改 [matchedLogs]，
/// 也不会把历史日志伪造成过去的习惯打卡。
class HabitSleepLogMigrationProposal {
  final List<TimeLogItem> matchedLogs;
  final int observedNights;
  final int bedtimeMinute;
  final int wakeMinute;
  final int medianSleepMinutes;
  final bool hasEarlySleep;
  final bool hasEarlyWake;

  const HabitSleepLogMigrationProposal({
    required this.matchedLogs,
    required this.observedNights,
    required this.bedtimeMinute,
    required this.wakeMinute,
    required this.medianSleepMinutes,
    required this.hasEarlySleep,
    required this.hasEarlyWake,
  });

  bool get createsEarlySleep => !hasEarlySleep;
  bool get createsEarlyWake => !hasEarlyWake;
  bool get canMigrate => createsEarlySleep || createsEarlyWake;

  String get sleepDurationLabel {
    final hours = medianSleepMinutes ~/ 60;
    final minutes = medianSleepMinutes % 60;
    if (minutes == 0) return '$hours 小时';
    return '$hours 小时 $minutes 分钟';
  }
}

/// 识别旧时间日志中的夜间睡眠，并生成早睡 / 早起习惯的可确认迁移方案。
abstract final class HabitSleepLogMigrationService {
  static const int defaultLookbackDays = 60;
  static const int minimumNights = 2;

  static const _sleepKeywords = [
    '睡眠',
    '睡觉',
    '睡了',
    '作息',
    '入睡',
    '上床',
    '就寝',
    '早睡',
    '起床',
    '早起',
    '早醒',
    '醒来',
    '唤醒',
    'sleep',
    'sleeping',
    'bedtime',
    'wake',
    'wakeup',
    'getup',
  ];

  /// [tagNames] 的 key 是时间日志中的 tag UUID，value 是标签名称。
  static HabitSleepLogMigrationProposal? buildProposal({
    required Iterable<TimeLogItem> logs,
    Map<String, String> tagNames = const {},
    Iterable<HabitGoal> existingGoals = const [],
    DateTime? now,
    int lookbackDays = defaultLookbackDays,
  }) {
    final current = now ?? DateTime.now();
    final cutoff = DateTime(
      current.year,
      current.month,
      current.day,
    ).subtract(Duration(days: lookbackDays));

    // 同一晚可能存在多段重复日志，只保留持续时间最长的一段，避免一次睡眠
    // 被重复计入统计。午休等白天记录也不用于推导早睡早起目标。
    final byNight = <String, _SleepSample>{};
    for (final log in logs) {
      if (log.isDeleted) continue;
      final start = DateTime.fromMillisecondsSinceEpoch(log.startTime);
      final end = DateTime.fromMillisecondsSinceEpoch(log.endTime);
      if (start.isBefore(cutoff) ||
          start.isAfter(current) ||
          !end.isAfter(start)) {
        continue;
      }
      final durationMinutes = end.difference(start).inMinutes;
      if (durationMinutes < 3 * 60 || durationMinutes > 16 * 60) continue;
      if (start.hour >= 6 && start.hour < 18) continue;

      final tagText = log.tagUuids
          .map((uuid) => tagNames[uuid] ?? '')
          .where((name) => name.isNotEmpty)
          .join(' ');
      final searchable = _normalize([
        log.title,
        log.remark ?? '',
        tagText,
      ].join(' '));
      if (!_sleepKeywords.any(searchable.contains)) continue;

      final night =
          start.hour < 12 ? start.subtract(const Duration(days: 1)) : start;
      final nightKey = _dateKey(night);
      final sample = _SleepSample(
        log: log,
        durationMinutes: durationMinutes,
        bedtimeMinute: start.hour < 12
            ? start.hour * 60 + start.minute + 1440
            : start.hour * 60 + start.minute,
        wakeMinute: end.hour * 60 + end.minute,
      );
      final previous = byNight[nightKey];
      if (previous == null ||
          sample.durationMinutes > previous.durationMinutes) {
        byNight[nightKey] = sample;
      }
    }

    if (byNight.length < minimumNights) return null;
    final samples = byNight.values.toList()
      ..sort((a, b) => a.log.startTime.compareTo(b.log.startTime));
    final existing = existingGoals.where((goal) => !goal.isDeleted);
    final hasEarlySleep = existing.any(_isEarlySleepGoal);
    final hasEarlyWake = existing.any(_isEarlyWakeGoal);

    final bedtime = _normalizeMinute(
      _median(samples.map((sample) => sample.bedtimeMinute).toList()),
    );
    final wake = _normalizeMinute(
      _median(samples.map((sample) => sample.wakeMinute).toList()),
    );

    final proposal = HabitSleepLogMigrationProposal(
      matchedLogs: samples.map((sample) => sample.log).toList(growable: false),
      observedNights: samples.length,
      bedtimeMinute: bedtime,
      wakeMinute: wake,
      medianSleepMinutes: _median(
        samples.map((sample) => sample.durationMinutes).toList(),
      ),
      hasEarlySleep: hasEarlySleep,
      hasEarlyWake: hasEarlyWake,
    );
    return proposal.canMigrate ? proposal : null;
  }

  /// 按当前用户的习惯状态再次检查后创建缺少的习惯，避免预览期间重复创建。
  /// 旧时间日志和历史习惯打卡都保持不变。
  static Future<List<HabitGoal>> createHabits({
    required HabitSleepLogMigrationProposal proposal,
    String username = '',
  }) async {
    final allGoals = await HabitRepository.getGoals();
    final activeGoals = allGoals.where((goal) => !goal.isDeleted);
    final hasEarlySleep = activeGoals.any(_isEarlySleepGoal);
    final hasEarlyWake = activeGoals.any(_isEarlyWakeGoal);

    final created = <HabitGoal>[];
    if (!hasEarlySleep) {
      created.add(
        await HabitRepository.createGoal(
          name: '早睡',
          icon: '🌙',
          sourceType: HabitSourceType.timeCheckIn,
          rule: _timeRule(
            targetMinute: proposal.bedtimeMinute,
            dayBoundaryMinute: HabitRuleResolver.defaultDayBoundaryMinute,
          ),
          username: username,
        ),
      );
    }
    if (!hasEarlyWake) {
      created.add(
        await HabitRepository.createGoal(
          name: '早起',
          icon: '🌅',
          sourceType: HabitSourceType.timeCheckIn,
          rule: _timeRule(targetMinute: proposal.wakeMinute),
          username: username,
        ),
      );
    }
    return created;
  }

  static HabitGoalRuleRevision _timeRule({
    required int targetMinute,
    int dayBoundaryMinute = 0,
  }) {
    final today = HabitRuleResolver.dayKey(
      HabitRuleResolver.logicalDateFor(DateTime.now(), dayBoundaryMinute),
    );
    return HabitGoalRuleRevision(
      habitUuid: '',
      effectiveFromDate: today,
      periodType: HabitPeriodType.daily,
      targetTimeMinute: targetMinute,
      timeComparison: HabitTimeComparison.before,
      timeToleranceMinutes: 15,
      dayBoundaryMinute: dayBoundaryMinute,
      // 迁移不直接开启提醒，避免用户确认迁移后突然收到新通知；
      // 习惯详情页仍可继续开启已有的提醒设置。
      reminderPolicy: const HabitReminderPolicy(),
    );
  }

  static String formatMinute(int minute) {
    final normalized = _normalizeMinute(minute);
    final hour = normalized ~/ 60;
    final value = normalized % 60;
    return '${hour.toString().padLeft(2, '0')}:${value.toString().padLeft(2, '0')}';
  }

  static String _normalize(String value) =>
      value.toLowerCase().replaceAll(RegExp(r'\s+'), '');

  static String _dateKey(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  static int _normalizeMinute(int minute) {
    final normalized = minute % 1440;
    return normalized < 0 ? normalized + 1440 : normalized;
  }

  static int _median(List<int> values) {
    final sorted = List<int>.from(values)..sort();
    final middle = sorted.length ~/ 2;
    if (sorted.length.isOdd) return sorted[middle];
    return ((sorted[middle - 1] + sorted[middle]) / 2).round();
  }

  static bool _isEarlySleepGoal(HabitGoal goal) {
    if (goal.sourceType != HabitSourceType.timeCheckIn) return false;
    final adaptation = HabitAdaptationService.forHabit(goal);
    if (adaptation?.kind == HabitAdaptationKind.earlySleep) return true;
    final normalized = goal.name.trim().toLowerCase().replaceAll(' ', '');
    return normalized.contains('早睡') || normalized.contains('入睡');
  }

  static bool _isEarlyWakeGoal(HabitGoal goal) {
    if (goal.sourceType != HabitSourceType.timeCheckIn) return false;
    final adaptation = HabitAdaptationService.forHabit(goal);
    if (adaptation?.kind == HabitAdaptationKind.earlyWake) return true;
    final normalized = goal.name.trim().toLowerCase().replaceAll(' ', '');
    return normalized.contains('早起') ||
        normalized.contains('起床') ||
        normalized.contains('醒来');
  }
}

class _SleepSample {
  final TimeLogItem log;
  final int durationMinutes;
  final int bedtimeMinute;
  final int wakeMinute;

  const _SleepSample({
    required this.log,
    required this.durationMinutes,
    required this.bedtimeMinute,
    required this.wakeMinute,
  });
}
