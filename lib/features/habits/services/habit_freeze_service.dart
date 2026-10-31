import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../models.dart';
import '../../../services/pomodoro_service.dart';
import '../models/habit_checkin.dart';
import '../models/habit_goal.dart';
import '../models/habit_goal_rule.dart';
import '../repositories/habit_repository.dart';
import 'habit_progress_calculator.dart';
import 'habit_rule_resolver.dart';

/// 习惯免扣卡守护服务（Streak Freeze）。
///
/// 核心人文关怀设计：
/// 1. 启程礼遇：每个习惯默认赠送 1 张保底免扣卡，保护新手最容易阵亡的前几天；
/// 2. 7天律动奖励：连续打卡满 7 天（即完整一周），自动奖励 1 张免扣卡；
/// 3. 持有上限：最多存储 2 张免扣卡，既有安全感又防止过度懈怠；
/// 4. 绝不连续错过两次（Never Miss Twice）：不可连续两天使用免扣卡；
/// 5. 守护效果：免扣卡生效日保持连续天数不中断，并在日历和统计中以专属蓝冰盾牌展示；
/// 6. 贴心自动守护：开启自动守护时，若昨日意外遗漏且符合条件，次日自动触发守护并附带温暖提示。
abstract final class HabitFreezeService {
  /// 单个习惯最大免扣卡持有上限。
  static const int kMaxFreezeCards = 2;

  /// 获得一张免扣卡所需的连续达标天数。
  static const int kStreakIntervalForReward = 7;

  /// 新习惯初始赠送的保底免扣卡数量。
  static const int kInitialGiftCards = 1;

  static const String _prefixBalance = 'habit_freeze_balance_';
  static const String _prefixMilestone = 'habit_freeze_milestone_';
  static const String _prefixInit = 'habit_freeze_initialized_';
  static const String _prefixReconciledSpent = 'habit_freeze_reconciled_spent_';
  static const String _keyPendingNotice = 'habit_freeze_pending_notice';
  static const String _keyAutoProtectEnabled =
      'habit_freeze_auto_protect_enabled';

  /// 获取指定习惯当前可用的免扣卡数量（0..kMaxFreezeCards）。
  ///
  /// 若为首次读取，自动赠送新手保底卡并持久化；
  /// 同时自动对比本地与云同步写入的有效免扣打卡记录（`HabitCheckInSource.freeze`），
  /// 确保跨设备使用或撤销后，剩余卡片数量实现跨端自动对账同步。
  static Future<int> getAvailableCards(String habitUuid) async {
    final prefs = await SharedPreferences.getInstance();
    final initKey = '$_prefixInit$habitUuid';
    final balanceKey = '$_prefixBalance$habitUuid';
    final reconciledSpentKey = '$_prefixReconciledSpent$habitUuid';

    int localBalance = prefs.getInt(balanceKey) ?? kInitialGiftCards;
    if (!prefs.containsKey(initKey)) {
      // 首次初始化：赠送 1 张启程护航卡
      await prefs.setBool(initKey, true);
      await prefs.setInt(balanceKey, kInitialGiftCards);
      localBalance = kInitialGiftCards;
    }

    // 跨平台自动对账：结合同步下来的有效免扣打卡记录核算
    try {
      final checkIns = await HabitRepository.getCheckIns(habitUuid: habitUuid);
      final currentSpent = checkIns
          .where((c) => !c.isDeleted && c.source == HabitCheckInSource.freeze)
          .length;
      final lastReconciledSpent =
          prefs.getInt(reconciledSpentKey) ?? currentSpent;

      if (currentSpent != lastReconciledSpent) {
        final spentDiff = currentSpent - lastReconciledSpent;
        localBalance = (localBalance - spentDiff).clamp(0, kMaxFreezeCards);
        await prefs.setInt(balanceKey, localBalance);
        await prefs.setInt(reconciledSpentKey, currentSpent);
      } else if (!prefs.containsKey(reconciledSpentKey)) {
        await prefs.setInt(reconciledSpentKey, currentSpent);
      }
    } catch (_) {
      // 离线或数据加载异常时安全降级使用本地存储值
    }

    return localBalance.clamp(0, kMaxFreezeCards);
  }

  /// 更新免扣卡库存（安全限制在 0..kMaxFreezeCards 之间）。
  static Future<void> setAvailableCards(String habitUuid, int cards) async {
    final prefs = await SharedPreferences.getInstance();
    final clamped = cards.clamp(0, kMaxFreezeCards);
    await prefs.setInt('$_prefixBalance$habitUuid', clamped);
    await prefs.setBool('$_prefixInit$habitUuid', true);
  }

  /// 检查连续天数，若达到新的 7 天倍数里程碑且未达上限，则发放免扣卡。
  /// 返回本次新获得的免扣卡数量。
  static Future<int> checkAndAwardCards({
    required HabitGoal habit,
    required int currentStreak,
  }) async {
    if (currentStreak < kStreakIntervalForReward) return 0;

    final prefs = await SharedPreferences.getInstance();
    final milestoneKey = '$_prefixMilestone${habit.uuid}';
    final lastMilestone = prefs.getInt(milestoneKey) ?? 0;

    // 若当前连续天数退回了（例如此前中断后重新累计），重置里程碑基准
    if (currentStreak < lastMilestone) {
      final adjusted =
          (currentStreak ~/ kStreakIntervalForReward) *
          kStreakIntervalForReward;
      await prefs.setInt(milestoneKey, adjusted);
      return 0;
    }

    final currentTargetMilestones = currentStreak ~/ kStreakIntervalForReward;
    final lastTargetMilestones = lastMilestone ~/ kStreakIntervalForReward;
    final newMilestonesCount = currentTargetMilestones - lastTargetMilestones;

    if (newMilestonesCount <= 0) return 0;

    // 记录新的里程碑进度
    await prefs.setInt(
      milestoneKey,
      currentTargetMilestones * kStreakIntervalForReward,
    );

    final currentBalance = await getAvailableCards(habit.uuid);
    final room = kMaxFreezeCards - currentBalance;
    if (room <= 0) return 0;

    final awarded = newMilestonesCount > room ? room : newMilestonesCount;
    await setAvailableCards(habit.uuid, currentBalance + awarded);
    return awarded;
  }

  /// 检查某一天是否可以应用免扣卡。
  ///
  /// 校验规则：
  /// 1. 当前习惯还有可用免扣卡；
  /// 2. 该日期属于计划打卡日；
  /// 3. 该日期非未来日期；
  /// 4. 该日期未达标（若当天已完成打卡达标则无需且不可使用免扣卡）；
  /// 5. 该日期尚未被跳过或已被免扣保护；
  /// 6. 绝不连续错过两次：前一个计划日不能也处于免扣状态，后一个计划日亦然。
  static Future<({bool canApply, String? reason})> canApplyFreeze({
    required HabitGoal goal,
    required HabitGoalRuleRevision rule,
    required DateTime logicalDate,
    required List<HabitCheckIn> checkIns,
    List<HabitGoalRuleRevision>? rules,
    List<TodoItem>? todos,
    List<PomodoroRecord>? records,
    DateTime? now,
  }) async {
    final balance = await getAvailableCards(goal.uuid);
    if (balance <= 0) {
      return (canApply: false, reason: '当前没有可用的免扣卡（连续打卡满 7 天可获得 1 张）');
    }

    final isPlanned = HabitRuleResolver.isPlannedDay(rule, logicalDate);
    if (!isPlanned) {
      return (canApply: false, reason: '该日期不是计划打卡日，无需使用免扣卡');
    }

    final nowVal = now ?? DateTime.now();
    final today = DateTime(nowVal.year, nowVal.month, nowVal.day);
    final targetDay = DateTime(
      logicalDate.year,
      logicalDate.month,
      logicalDate.day,
    );
    if (targetDay.isAfter(today)) {
      return (canApply: false, reason: '未来日期不可使用免扣卡');
    }

    final dateKey = HabitRuleResolver.dayKey(logicalDate);
    final existingForDay = checkIns
        .where((c) => !c.isDeleted && c.logicalDate == dateKey)
        .toList(growable: false);

    final isAlreadyFrozen = existingForDay.any(
      (c) => c.source == HabitCheckInSource.freeze,
    );
    if (isAlreadyFrozen) {
      return (canApply: false, reason: '该日已经处于免扣卡守护中');
    }

    // 核心规则：当天已经完成打卡达标，则不可以使用免扣卡
    final effectiveRules = rules != null && rules.isNotEmpty ? rules : [rule];
    final progress = await HabitProgressCalculator.computePeriod(
      habit: goal,
      rules: effectiveRules,
      logicalDate: logicalDate,
      now: nowVal,
      todos: todos,
      records: records,
      checkIns: checkIns,
    );

    if (progress.goalMet) {
      return (canApply: false, reason: '当天已完成打卡达标，无需使用免扣卡');
    }

    if (progress.isSkipped) {
      return (canApply: false, reason: '该日期已标记为跳过，无需使用免扣卡');
    }

    // 检查“绝不连续错过两次”原则：查找前一个计划日和后一个计划日
    final prevPlannedDate = _findAdjacentPlannedDay(
      rule: rule,
      from: logicalDate,
      stepDays: -1,
    );
    if (prevPlannedDate != null) {
      final prevKey = HabitRuleResolver.dayKey(prevPlannedDate);
      final prevWasFrozen = checkIns.any(
        (c) =>
            !c.isDeleted &&
            c.logicalDate == prevKey &&
            c.source == HabitCheckInSource.freeze,
      );
      if (prevWasFrozen) {
        return (canApply: false, reason: '绝不连续错过两次：前一天已经使用了免扣卡，今天需要你的坚持哦！');
      }
    }

    final nextPlannedDate = _findAdjacentPlannedDay(
      rule: rule,
      from: logicalDate,
      stepDays: 1,
    );
    if (nextPlannedDate != null) {
      final nextKey = HabitRuleResolver.dayKey(nextPlannedDate);
      final nextWasFrozen = checkIns.any(
        (c) =>
            !c.isDeleted &&
            c.logicalDate == nextKey &&
            c.source == HabitCheckInSource.freeze,
      );
      if (nextWasFrozen) {
        return (canApply: false, reason: '不能连续两天使用免扣卡');
      }
    }

    return (canApply: true, reason: null);
  }

  /// 对指定逻辑日使用一张免扣卡。
  ///
  /// 写入一条 `HabitCheckInSource.freeze` 的打卡记录，并扣除一张免扣卡。
  static Future<bool> applyFreeze({
    required HabitGoal goal,
    required HabitGoalRuleRevision rule,
    required DateTime logicalDate,
    String? note,
    String? deviceId,
    String username = '',
    List<HabitGoalRuleRevision>? rules,
    List<TodoItem>? todos,
    List<PomodoroRecord>? records,
    DateTime? now,
  }) async {
    final allCheckIns = await HabitRepository.getCheckIns(habitUuid: goal.uuid);

    final validation = await canApplyFreeze(
      goal: goal,
      rule: rule,
      logicalDate: logicalDate,
      checkIns: allCheckIns,
      rules: rules,
      todos: todos,
      records: records,
      now: now,
    );

    if (!validation.canApply) {
      debugPrint('⚠️ 无法使用免扣卡: ${validation.reason}');
      return false;
    }

    final dateKey = HabitRuleResolver.dayKey(logicalDate);
    await HabitRepository.addCheckIn(
      goal: goal,
      rule: rule,
      localOccurredAt: logicalDate,
      value: 0,
      note: note ?? '🛡️ 免扣卡守护',
      source: HabitCheckInSource.freeze,
      dedupeKey: HabitCheckIn.buildDedupeKey(goal.uuid, 'freeze/$dateKey'),
    );

    final balance = await getAvailableCards(goal.uuid);
    await setAvailableCards(goal.uuid, balance - 1);
    final prefs = await SharedPreferences.getInstance();
    final checkInsAfter = await HabitRepository.getCheckIns(
      habitUuid: goal.uuid,
    );
    final currentSpent = checkInsAfter
        .where((c) => !c.isDeleted && c.source == HabitCheckInSource.freeze)
        .length;
    await prefs.setInt('$_prefixReconciledSpent${goal.uuid}', currentSpent);
    return true;
  }

  /// 撤销指定逻辑日的免扣卡守护，并退还 1 张卡片。
  static Future<bool> revokeFreeze({
    required HabitGoal goal,
    required HabitCheckIn freezeCheckIn,
  }) async {
    if (freezeCheckIn.source != HabitCheckInSource.freeze) return false;

    await HabitRepository.deleteCheckIn(freezeCheckIn);
    final balance = await getAvailableCards(goal.uuid);
    await setAvailableCards(goal.uuid, balance + 1);
    final prefs = await SharedPreferences.getInstance();
    final checkInsAfter = await HabitRepository.getCheckIns(
      habitUuid: goal.uuid,
    );
    final currentSpent = checkInsAfter
        .where((c) => !c.isDeleted && c.source == HabitCheckInSource.freeze)
        .length;
    await prefs.setInt('$_prefixReconciledSpent${goal.uuid}', currentSpent);
    return true;
  }

  /// 是否启用了自动守护（默认开启）。
  static Future<bool> isAutoProtectEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyAutoProtectEnabled) ?? true;
  }

  /// 设置是否开启自动守护。
  static Future<void> setAutoProtectEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyAutoProtectEnabled, enabled);
  }

  /// 智能自动守护昨日遗漏打卡的习惯。
  ///
  /// 在用户启动 App 或加载习惯首页时被调用。
  /// 返回被守护的习惯名称列表，并在 SharedPreferences 中暂存提示文本。
  static Future<List<String>> autoProtectMissedDays({
    required List<HabitGoal> goals,
    String username = '',
  }) async {
    final enabled = await isAutoProtectEnabled();
    if (!enabled || goals.isEmpty) return const [];

    final now = DateTime.now();
    final yesterday = HabitRuleResolver.addCalendarDays(now, -1);
    final yesterdayKey = HabitRuleResolver.dayKey(yesterday);

    final protectedHabitNames = <String>[];

    for (final goal in goals) {
      if (goal.isArchived || goal.isDeleted) continue;

      // 仅适用于每日类习惯（每日、工作日、自定义天数）
      final rules = await HabitRepository.getRules(habitUuid: goal.uuid);
      final rule = HabitRuleResolver.effectiveRule(rules, yesterday);
      if (rule == null) continue;

      final isAggregated =
          rule.periodType == HabitPeriodType.weekly ||
          rule.periodType == HabitPeriodType.monthly;
      if (isAggregated) continue;

      // 必须是昨天的计划日
      if (!HabitRuleResolver.isPlannedDay(rule, yesterday)) continue;

      final checkIns = await HabitRepository.getCheckIns(habitUuid: goal.uuid);

      // 计算昨天是否达标
      final progress = await HabitProgressCalculator.computePeriod(
        habit: goal,
        rules: [rule],
        logicalDate: yesterday,
        now: now,
        checkIns: checkIns,
      );

      // 若已经达标、已跳过或已被守护，则无需处理
      if (progress.goalMet || progress.isSkipped || progress.isFrozen) {
        continue;
      }

      // 检查是否有可用卡且符合规则
      final validation = await canApplyFreeze(
        goal: goal,
        rule: rule,
        logicalDate: yesterday,
        checkIns: checkIns,
        rules: [rule],
        now: now,
      );

      if (validation.canApply) {
        final applied = await applyFreeze(
          goal: goal,
          rule: rule,
          logicalDate: yesterday,
          note: '🛡️ 自动免扣卡守护 ($yesterdayKey)',
          username: username,
          rules: [rule],
          now: now,
        );
        if (applied) {
          protectedHabitNames.add(goal.name);
        }
      }
    }

    if (protectedHabitNames.isNotEmpty) {
      final namesText = protectedHabitNames
          .take(2)
          .map((n) => '「$n」')
          .join('、');
      final moreText = protectedHabitNames.length > 2
          ? ' 等 ${protectedHabitNames.length} 个习惯'
          : '';
      final msg = '🛡️ 昨天辛苦啦！免扣卡已为你守住 $namesText$moreText 的连续记录。今天继续从容出发！';
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyPendingNotice, msg);
    }

    return protectedHabitNames;
  }

  /// 获取并清除暂存的自动守护温馨提示文本（若有）。
  static Future<String?> popPendingAutoProtectNotice() async {
    final prefs = await SharedPreferences.getInstance();
    final msg = prefs.getString(_keyPendingNotice);
    if (msg != null && msg.isNotEmpty) {
      await prefs.remove(_keyPendingNotice);
      return msg;
    }
    return null;
  }

  /// 寻找向前/向后最近的一个计划日（最多回溯 14 天）。
  static DateTime? _findAdjacentPlannedDay({
    required HabitGoalRuleRevision rule,
    required DateTime from,
    required int stepDays,
  }) {
    var cur = from;
    for (int i = 0; i < 14; i++) {
      cur = HabitRuleResolver.addCalendarDays(cur, stepDays);
      if (HabitRuleResolver.isPlannedDay(rule, cur)) {
        return cur;
      }
    }
    return null;
  }
}
