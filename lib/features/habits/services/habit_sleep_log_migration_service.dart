import 'package:uuid/uuid.dart';

import '../../../models.dart';
import '../models/habit_checkin.dart';
import '../models/habit_goal.dart';
import '../models/habit_goal_rule.dart';
import '../repositories/habit_repository.dart';
import '../services/habit_adaptation_service.dart';
import '../services/habit_rule_resolver.dart';
import 'habit_sleep_duration_service.dart';
import 'habit_sleep_goal_resolver.dart';

/// 只有时间格占位（例如 15 / 30 分钟）时，早睡节点采用的时间。
enum HabitSleepLogTimeSelection {
  startTime,
  midpoint,
}

/// 短时间格记录的语义。
enum HabitSleepLogKind {
  fullSleep,
  nap,
}

/// 睡眠日志迁移时的用户确认口径。
class HabitSleepLogMigrationOptions {
  final HabitSleepLogTimeSelection timeSelection;
  final HabitSleepLogKind kind;

  const HabitSleepLogMigrationOptions({
    this.timeSelection = HabitSleepLogTimeSelection.startTime,
    this.kind = HabitSleepLogKind.fullSleep,
  });
}

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
  final List<String> gridOnlyLogIds;
  final bool hasReliableWakeTime;

  const HabitSleepLogMigrationProposal({
    required this.matchedLogs,
    required this.observedNights,
    required this.bedtimeMinute,
    required this.wakeMinute,
    required this.medianSleepMinutes,
    required this.hasEarlySleep,
    required this.hasEarlyWake,
    this.gridOnlyLogIds = const [],
    this.hasReliableWakeTime = true,
  });

  bool get createsEarlySleep => !hasEarlySleep;
  bool get createsEarlyWake => !hasEarlyWake && hasReliableWakeTime;

  bool get hasGridOnlyLogs => gridOnlyLogIds.isNotEmpty;

  bool isGridOnlyLog(TimeLogItem log) => gridOnlyLogIds.contains(log.id);

  /// 应用迁移口径后返回新的建议。选择“小睡”时，短时间格记录不会导入。
  HabitSleepLogMigrationProposal? forOptions(
    HabitSleepLogMigrationOptions options,
  ) {
    return HabitSleepLogMigrationService.applyOptions(this, options);
  }

  /// 即使两个目标都已经存在，也允许继续迁移历史打卡。
  bool get canMigrate => matchedLogs.isNotEmpty;

  String get sleepDurationLabel {
    if (!hasReliableWakeTime || medianSleepMinutes <= 0) {
      return '无法从时间格估算';
    }
    final hours = medianSleepMinutes ~/ 60;
    final minutes = medianSleepMinutes % 60;
    if (minutes == 0) return '$hours 小时';
    return '$hours 小时 $minutes 分钟';
  }
}

/// 已有早睡习惯导入时间日志时的预览结果。
class HabitTimeLogImportPreview {
  final List<TimeLogItem> candidateLogs;
  final List<TimeLogItem> pendingLogs;
  final int alreadyImportedCount;
  final List<String> gridOnlyLogIds;

  const HabitTimeLogImportPreview({
    required this.candidateLogs,
    required this.pendingLogs,
    required this.alreadyImportedCount,
    this.gridOnlyLogIds = const [],
  });

  bool get hasPendingLogs => pendingLogs.isNotEmpty;
}

/// 一条睡眠时间日志要导入到哪个时间点习惯。
enum HabitTimeLogImportPart {
  bedtime,
  wakeTime,
}

/// 一次“迁移到早睡早起”的执行结果。
class HabitSleepLogMigrationResult {
  final List<HabitGoal> createdGoals;
  final int importedBedtimeCount;
  final int importedWakeTimeCount;
  final int generatedSleepDurationCount;

  const HabitSleepLogMigrationResult({
    required this.createdGoals,
    required this.importedBedtimeCount,
    required this.importedWakeTimeCount,
    required this.generatedSleepDurationCount,
  });

  int get totalImported => importedBedtimeCount + importedWakeTimeCount;
}

/// 识别旧时间日志中的夜间睡眠，并生成早睡 / 早起习惯的可确认迁移方案。
abstract final class HabitSleepLogMigrationService {
  /// 迁移面向历史时间日志，不能只看最近几周；一年范围可以覆盖大多数
  /// 用户从旧功能迁移到习惯的场景，同时避免无限期使用过时作息推导目标。
  static const int defaultLookbackDays = 365;
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
    Iterable<HabitCheckIn> existingCheckIns = const [],
    DateTime? now,
    int lookbackDays = defaultLookbackDays,
    HabitSleepLogMigrationOptions options =
        const HabitSleepLogMigrationOptions(),
  }) {
    // 迁移完成状态必须来自可同步的习惯打卡，不能只依赖本机的
    // SharedPreferences，否则同一账号在另一台设备上还会再次出现入口。
    if (hasImportedTimeLogCheckIns(existingCheckIns)) return null;

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
      if (start.hour >= 6 && start.hour < 18) continue;
      final gridOnly = _isGridOnlyDuration(durationMinutes);
      if (gridOnly && options.kind == HabitSleepLogKind.nap) continue;
      if (!gridOnly &&
          (durationMinutes < 3 * 60 || durationMinutes > 16 * 60)) {
        continue;
      }

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
        bedtimeMinute: _bedtimeMinute(
          start,
          end: end,
          gridOnly: gridOnly,
          selection: options.timeSelection,
        ),
        wakeMinute: end.hour * 60 + end.minute,
        gridOnly: gridOnly,
      );
      final previous = byNight[nightKey];
      if (_shouldReplaceSample(sample, previous)) {
        byNight[nightKey] = sample;
      }
    }

    if (byNight.length < minimumNights) return null;
    final samples = byNight.values.toList()
      ..sort((a, b) => a.log.startTime.compareTo(b.log.startTime));
    final existing = existingGoals.where(
      (goal) => !goal.isDeleted && !goal.isArchived,
    );
    final hasEarlySleep = existing.any(_isEarlySleepGoal);
    final hasEarlyWake = existing.any(_isEarlyWakeGoal);

    final bedtime = _normalizeMinute(
      _median(samples.map((sample) => sample.bedtimeMinute).toList()),
    );
    final reliableSamples =
        samples.where((sample) => !sample.gridOnly).toList();
    final wake = _normalizeMinute(
      reliableSamples.isEmpty
          ? 7 * 60
          : _median(
              reliableSamples.map((sample) => sample.wakeMinute).toList()),
    );

    final proposal = HabitSleepLogMigrationProposal(
      matchedLogs: samples.map((sample) => sample.log).toList(growable: false),
      observedNights: samples.length,
      bedtimeMinute: bedtime,
      wakeMinute: wake,
      medianSleepMinutes: reliableSamples.isEmpty
          ? 0
          : _median(
              reliableSamples.map((sample) => sample.durationMinutes).toList(),
            ),
      hasEarlySleep: hasEarlySleep,
      hasEarlyWake: hasEarlyWake,
      gridOnlyLogIds: samples
          .where((sample) => sample.gridOnly)
          .map((sample) => sample.log.id)
          .toList(growable: false),
      hasReliableWakeTime: reliableSamples.isNotEmpty,
    );
    return proposal.canMigrate ? proposal : null;
  }

  /// 检查旧时间日志中哪些记录还没有导入指定的早睡习惯。
  ///
  /// 这里不要求目标习惯是新建的，适用于用户已经有早睡习惯的场景。
  static Future<HabitTimeLogImportPreview> buildImportPreview({
    required HabitGoal goal,
    required Iterable<TimeLogItem> logs,
    Map<String, String> tagNames = const {},
    HabitTimeLogImportPart part = HabitTimeLogImportPart.bedtime,
    DateTime? now,
    int lookbackDays = defaultLookbackDays,
  }) async {
    final proposal = buildProposal(
      logs: logs,
      tagNames: tagNames,
      now: now,
      lookbackDays: lookbackDays,
    );
    final candidates = proposal?.matchedLogs ?? const <TimeLogItem>[];
    final importCandidates =
        part == HabitTimeLogImportPart.wakeTime && proposal != null
            ? candidates.where((log) => !proposal.isGridOnlyLog(log)).toList()
            : candidates;
    final goals = await HabitRepository.getGoals();
    final canonicalGoal = HabitSleepGoalResolver.canonical(
          goals,
          part == HabitTimeLogImportPart.bedtime
              ? HabitAdaptationKind.earlySleep
              : HabitAdaptationKind.earlyWake,
        ) ??
        goal;
    // 重复睡眠目标之间也共享导入去重状态，避免从不同详情页重复导入同一条日志。
    final checkIns = await HabitRepository.getCheckIns();
    final importedKeys = _checkInDedupeKeys(checkIns);
    final pending = importCandidates
        .where(
          (log) => !_containsTimeLogDedupeKey(
            importedKeys,
            canonicalGoal,
            log,
            part: part,
          ),
        )
        .toList(growable: false);
    return HabitTimeLogImportPreview(
      candidateLogs: candidates,
      pendingLogs: pending,
      alreadyImportedCount: importCandidates.length - pending.length,
      gridOnlyLogIds: proposal?.gridOnlyLogIds ?? const [],
    );
  }

  /// 将预览中的历史时间日志导入到已有早睡习惯。
  ///
  /// 每条日志使用稳定的 [timeLogDedupeKey]，因此重复执行只会导入新增记录。
  /// 原时间日志不会被修改或删除。
  static Future<int> importTimeLogs({
    required HabitGoal goal,
    required HabitGoalRuleRevision rule,
    required HabitTimeLogImportPreview preview,
    HabitTimeLogImportPart part = HabitTimeLogImportPart.bedtime,
    HabitSleepLogMigrationOptions options =
        const HabitSleepLogMigrationOptions(),
  }) async {
    final goals = await HabitRepository.getGoals();
    final kind = part == HabitTimeLogImportPart.bedtime
        ? HabitAdaptationKind.earlySleep
        : HabitAdaptationKind.earlyWake;
    final importGoal = HabitSleepGoalResolver.canonical(goals, kind) ?? goal;
    final importRule = importGoal.uuid == goal.uuid
        ? rule
        : await _currentRuleFor(importGoal) ?? rule;
    final existing = await HabitRepository.getCheckIns();
    final importedKeys = _checkInDedupeKeys(existing);
    var importedCount = 0;
    for (final log in preview.pendingLogs) {
      final dedupeKey = timeLogDedupeKey(importGoal, log, part: part);
      if (_containsTimeLogDedupeKey(
        importedKeys,
        importGoal,
        log,
        part: part,
      )) {
        continue;
      }
      final localStart =
          DateTime.fromMillisecondsSinceEpoch(log.startTime).toLocal();
      final localEnd =
          DateTime.fromMillisecondsSinceEpoch(log.endTime).toLocal();
      final isGridOnly = preview.gridOnlyLogIds.contains(log.id);
      if (part == HabitTimeLogImportPart.wakeTime && isGridOnly) continue;
      final localOccurredAt = part == HabitTimeLogImportPart.bedtime
          ? _bedtimeDateTime(
              localStart,
              localEnd,
              gridOnly: isGridOnly,
              selection: options.timeSelection,
            )
          : localEnd;
      final durationMinutes = localEnd.difference(localStart).inMinutes;
      final hours = durationMinutes ~/ 60;
      final minutes = durationMinutes % 60;
      final durationLabel =
          minutes == 0 ? '$hours 小时' : '$hours 小时 $minutes 分钟';
      final timeRange =
          '${formatMinute(localStart.hour * 60 + localStart.minute)}–'
          '${formatMinute(localEnd.hour * 60 + localEnd.minute)}';
      final selectionLabel = isGridOnly &&
              options.timeSelection == HabitSleepLogTimeSelection.midpoint
          ? '取时间格中点'
          : isGridOnly
              ? '取时间格开始'
              : null;
      await HabitRepository.addCheckIn(
        goal: importGoal,
        rule: importRule,
        localOccurredAt: localOccurredAt,
        source: HabitCheckInSource.import,
        note: '从时间日志导入 · $timeRange · $durationLabel'
            '${selectionLabel == null ? '' : ' · $selectionLabel'}',
        dedupeKey: dedupeKey,
      );
      importedKeys.add(dedupeKey);
      importedCount++;
    }
    return importedCount;
  }

  static String timeLogDedupeKey(
    HabitGoal goal,
    TimeLogItem log, {
    HabitTimeLogImportPart part = HabitTimeLogImportPart.bedtime,
  }) {
    final suffix = part == HabitTimeLogImportPart.bedtime ? '' : '/end';
    return HabitCheckIn.buildDedupeKey(
      goal.uuid,
      'time-log/v2/${log.startTime}-${log.endTime}$suffix',
    )!;
  }

  /// 判断某账号是否已经完成过睡眠时间日志迁移。
  ///
  /// 迁移打卡会随习惯数据同步，因此这个判断可以跨设备生效；普通手动
  /// 打卡不会误触发，即使用户已经手动创建了“早睡”或“早起”习惯也不影响
  /// 首次迁移入口。
  static bool hasImportedTimeLogCheckIns(
    Iterable<HabitCheckIn> checkIns,
  ) {
    return checkIns.any(
      (checkIn) =>
          !checkIn.isDeleted &&
          checkIn.source == HabitCheckInSource.import &&
          checkIn.dedupeKey?.contains('/time-log/') == true,
    );
  }

  static Set<String> _checkInDedupeKeys(Iterable<HabitCheckIn> checkIns) {
    return checkIns
        .where((checkIn) => !checkIn.isDeleted)
        .map((checkIn) => checkIn.dedupeKey)
        .whereType<String>()
        .toSet();
  }

  static bool _containsTimeLogDedupeKey(
    Set<String> importedKeys,
    HabitGoal goal,
    TimeLogItem log, {
    required HabitTimeLogImportPart part,
  }) {
    if (importedKeys.contains(timeLogDedupeKey(goal, log, part: part))) {
      return true;
    }
    // 兼容 v5.7 及更早版本按时间日志 UUID 生成的去重键，升级后不能
    // 因为键格式变化而把已经导入的记录再写一遍。
    final suffix = part == HabitTimeLogImportPart.bedtime ? '' : '/end';
    final v2Suffix = '/time-log/v2/${log.startTime}-${log.endTime}$suffix';
    final legacySuffix = '/time-log/${log.id}$suffix';
    return importedKeys.any(
      (key) => key.endsWith(v2Suffix) || key.endsWith(legacySuffix),
    );
  }

  static bool _shouldReplaceSample(
      _SleepSample sample, _SleepSample? previous) {
    if (previous == null) return true;
    if (sample.durationMinutes != previous.durationMinutes) {
      return sample.durationMinutes > previous.durationMinutes;
    }
    // 同一晚同样长的跨设备副本按时间确定性选择，避免不同设备因列表
    // 顺序不同而各自挑出不同的 UUID。
    return sample.log.startTime < previous.log.startTime ||
        (sample.log.startTime == previous.log.startTime &&
            sample.log.endTime < previous.log.endTime);
  }

  /// 按当前用户的习惯状态再次检查后创建缺少的习惯，避免预览期间重复创建。
  /// 旧时间日志和历史习惯打卡都保持不变。
  static Future<List<HabitGoal>> createHabits({
    required HabitSleepLogMigrationProposal proposal,
    String username = '',
  }) async {
    final allGoals = await HabitRepository.getGoals();
    final activeGoals = allGoals.where(
      (goal) => !goal.isDeleted && !goal.isArchived,
    );
    final hasEarlySleep = activeGoals.any(_isEarlySleepGoal);
    final hasEarlyWake = activeGoals.any(_isEarlyWakeGoal);

    final created = <HabitGoal>[];
    if (!hasEarlySleep) {
      final goalUuid = _migrationGoalUuid(username, 'early-sleep');
      created.add(
        await HabitRepository.createGoal(
          goalUuid: goalUuid,
          name: '早睡',
          icon: '🌙',
          sourceType: HabitSourceType.timeCheckIn,
          rule: _timeRule(
            uuid: _migrationRuleUuid(goalUuid),
            targetMinute: proposal.bedtimeMinute,
            dayBoundaryMinute: HabitRuleResolver.defaultDayBoundaryMinute,
          ),
          username: username,
        ),
      );
    }
    if (proposal.hasReliableWakeTime && !hasEarlyWake) {
      final goalUuid = _migrationGoalUuid(username, 'early-wake');
      created.add(
        await HabitRepository.createGoal(
          goalUuid: goalUuid,
          name: '早起',
          icon: '🌅',
          sourceType: HabitSourceType.timeCheckIn,
          rule: _timeRule(
            uuid: _migrationRuleUuid(goalUuid),
            targetMinute: proposal.wakeMinute,
          ),
          username: username,
        ),
      );
    }
    final hasSleepDuration = activeGoals.any(_isSleepDurationGoal);
    if (proposal.hasReliableWakeTime && !hasSleepDuration) {
      final goalUuid = _migrationGoalUuid(username, 'sleep-duration');
      created.add(
        await HabitRepository.createGoal(
          goalUuid: goalUuid,
          name: '睡眠时长',
          icon: '🛌',
          sourceType: HabitSourceType.durationCheckIn,
          rule: _durationRule(
            uuid: _migrationRuleUuid(goalUuid),
            effectiveFromDate: _earliestSleepLogicalDate(proposal),
          ),
          username: username,
        ),
      );
    }
    return created;
  }

  /// 创建缺少的目标，并把匹配到的旧日志分别导入早睡和早起。
  ///
  /// 睡眠开始时间对应早睡，睡眠结束时间对应早起。旧时间日志不会被修改，
  /// 重复执行会通过稳定去重键跳过已经导入的记录。
  static Future<HabitSleepLogMigrationResult> migrateProposal({
    required HabitSleepLogMigrationProposal proposal,
    String username = '',
    HabitSleepLogMigrationOptions options =
        const HabitSleepLogMigrationOptions(),
  }) async {
    final selectedProposal = proposal.forOptions(options);
    if (selectedProposal == null || selectedProposal.matchedLogs.isEmpty) {
      return const HabitSleepLogMigrationResult(
        createdGoals: [],
        importedBedtimeCount: 0,
        importedWakeTimeCount: 0,
        generatedSleepDurationCount: 0,
      );
    }
    final createdGoals = await createHabits(
      proposal: selectedProposal,
      username: username,
    );
    final activeGoals = (await HabitRepository.getGoals())
        .where((goal) => !goal.isDeleted && !goal.isArchived)
        .toList(growable: false);
    final earlySleep = HabitSleepGoalResolver.canonical(
      activeGoals,
      HabitAdaptationKind.earlySleep,
    );
    final earlyWake = HabitSleepGoalResolver.canonical(
      activeGoals,
      HabitAdaptationKind.earlyWake,
    );
    final preview = HabitTimeLogImportPreview(
      candidateLogs: selectedProposal.matchedLogs,
      pendingLogs: selectedProposal.matchedLogs,
      alreadyImportedCount: 0,
      gridOnlyLogIds: selectedProposal.gridOnlyLogIds,
    );

    var importedBedtimeCount = 0;
    var importedWakeTimeCount = 0;
    if (earlySleep != null) {
      final rule = await _currentRuleFor(earlySleep);
      if (rule != null) {
        importedBedtimeCount = await importTimeLogs(
          goal: earlySleep,
          rule: rule,
          preview: preview,
          part: HabitTimeLogImportPart.bedtime,
          options: options,
        );
      }
    }
    if (earlyWake != null) {
      final rule = await _currentRuleFor(earlyWake);
      if (rule != null) {
        importedWakeTimeCount = await importTimeLogs(
          goal: earlyWake,
          rule: rule,
          preview: preview,
          part: HabitTimeLogImportPart.wakeTime,
          options: options,
        );
      }
    }
    final generatedSleepDurationCount =
        await HabitSleepDurationService.syncAll();

    return HabitSleepLogMigrationResult(
      createdGoals: createdGoals,
      importedBedtimeCount: importedBedtimeCount,
      importedWakeTimeCount: importedWakeTimeCount,
      generatedSleepDurationCount: generatedSleepDurationCount,
    );
  }

  static bool _isSleepDurationGoal(HabitGoal goal) {
    return goal.sourceType == HabitSourceType.durationCheckIn &&
        HabitAdaptationService.forHabit(goal)?.kind ==
            HabitAdaptationKind.sleepDuration;
  }

  static Future<HabitGoalRuleRevision?> _currentRuleFor(
    HabitGoal goal,
  ) async {
    final rules = await HabitRepository.getRules(habitUuid: goal.uuid);
    final activeRules = rules.where((rule) => !rule.isDeleted).toList();
    if (activeRules.isEmpty) return null;
    for (final rule in activeRules) {
      if (rule.uuid == goal.currentRuleUuid) return rule;
    }
    return HabitRuleResolver.effectiveRule(activeRules, DateTime.now()) ??
        activeRules.last;
  }

  static HabitGoalRuleRevision _timeRule({
    String? uuid,
    required int targetMinute,
    int dayBoundaryMinute = 0,
  }) {
    final today = HabitRuleResolver.dayKey(
      HabitRuleResolver.logicalDateFor(DateTime.now(), dayBoundaryMinute),
    );
    return HabitGoalRuleRevision(
      uuid: uuid,
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

  static HabitGoalRuleRevision _durationRule({
    String? uuid,
    String? effectiveFromDate,
  }) {
    final today = HabitRuleResolver.dayKey(
      HabitRuleResolver.logicalDateFor(
        DateTime.now(),
        HabitRuleResolver.defaultDayBoundaryMinute,
      ),
    );
    return HabitGoalRuleRevision(
      uuid: uuid,
      habitUuid: '',
      effectiveFromDate: effectiveFromDate ?? today,
      periodType: HabitPeriodType.daily,
      targetValue: 8 * 60 * 60,
      unit: '小时',
      dayBoundaryMinute: HabitRuleResolver.defaultDayBoundaryMinute,
      reminderPolicy: const HabitReminderPolicy(),
    );
  }

  static String _migrationGoalUuid(String username, String kind) {
    final account = username.trim().toLowerCase();
    return const Uuid().v5(
      Namespace.url.value,
      'countdown-todo/sleep-log-migration/$account/$kind',
    );
  }

  static String _migrationRuleUuid(String goalUuid) {
    return const Uuid().v5(goalUuid, 'current-rule');
  }

  static String? _earliestSleepLogicalDate(
    HabitSleepLogMigrationProposal proposal,
  ) {
    if (proposal.matchedLogs.isEmpty) return null;
    final first = proposal.matchedLogs
        .map((log) =>
            DateTime.fromMillisecondsSinceEpoch(log.startTime).toLocal())
        .reduce((a, b) => a.isBefore(b) ? a : b);
    return HabitRuleResolver.dayKey(
      HabitRuleResolver.logicalDateFor(
        first,
        HabitRuleResolver.defaultDayBoundaryMinute,
      ),
    );
  }

  /// 用用户选择的口径重新计算迁移目标。
  static HabitSleepLogMigrationProposal? applyOptions(
    HabitSleepLogMigrationProposal proposal,
    HabitSleepLogMigrationOptions options,
  ) {
    final logs = proposal.matchedLogs
        .where(
          (log) =>
              options.kind == HabitSleepLogKind.fullSleep ||
              !proposal.isGridOnlyLog(log),
        )
        .toList(growable: false);
    if (logs.isEmpty) return null;

    final gridOnlyIds = proposal.gridOnlyLogIds
        .where((id) => logs.any((log) => log.id == id))
        .toList(growable: false);
    final reliableLogs = logs.where((log) => !gridOnlyIds.contains(log.id));
    final bedtime = _median(
      logs.map((log) {
        final start =
            DateTime.fromMillisecondsSinceEpoch(log.startTime).toLocal();
        return _bedtimeMinute(
          start,
          end: DateTime.fromMillisecondsSinceEpoch(log.endTime).toLocal(),
          gridOnly: gridOnlyIds.contains(log.id),
          selection: options.timeSelection,
        );
      }).toList(),
    );
    final reliableList = reliableLogs.toList(growable: false);
    final wake = reliableList.isEmpty
        ? 7 * 60
        : _median(
            reliableList.map((log) {
              final end =
                  DateTime.fromMillisecondsSinceEpoch(log.endTime).toLocal();
              return end.hour * 60 + end.minute;
            }).toList(),
          );
    return HabitSleepLogMigrationProposal(
      matchedLogs: logs,
      observedNights: logs.length,
      bedtimeMinute: _normalizeMinute(bedtime),
      wakeMinute: _normalizeMinute(wake),
      medianSleepMinutes: reliableList.isEmpty
          ? 0
          : _median(
              reliableList.map((log) {
                final start =
                    DateTime.fromMillisecondsSinceEpoch(log.startTime);
                final end = DateTime.fromMillisecondsSinceEpoch(log.endTime);
                return end.difference(start).inMinutes;
              }).toList(),
            ),
      hasEarlySleep: proposal.hasEarlySleep,
      hasEarlyWake: proposal.hasEarlyWake,
      gridOnlyLogIds: gridOnlyIds,
      hasReliableWakeTime: reliableList.isNotEmpty,
    );
  }

  static bool _isGridOnlyDuration(int durationMinutes) {
    return durationMinutes == 15 || durationMinutes == 30;
  }

  static int _bedtimeMinute(
    DateTime start, {
    DateTime? end,
    required bool gridOnly,
    required HabitSleepLogTimeSelection selection,
  }) {
    var minute = start.hour * 60 + start.minute;
    if (gridOnly && selection == HabitSleepLogTimeSelection.midpoint) {
      final midpoint = end == null
          ? start.add(const Duration(minutes: 15))
          : start.add(end.difference(start) ~/ 2);
      minute = midpoint.hour * 60 + midpoint.minute;
    }
    if (minute < 12 * 60) minute += 1440;
    return minute;
  }

  static DateTime _bedtimeDateTime(
    DateTime start,
    DateTime end, {
    required bool gridOnly,
    required HabitSleepLogTimeSelection selection,
  }) {
    if (!gridOnly || selection == HabitSleepLogTimeSelection.startTime) {
      return start;
    }
    return start.add(end.difference(start) ~/ 2);
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
  final bool gridOnly;

  const _SleepSample({
    required this.log,
    required this.durationMinutes,
    required this.bedtimeMinute,
    required this.wakeMinute,
    required this.gridOnly,
  });
}
