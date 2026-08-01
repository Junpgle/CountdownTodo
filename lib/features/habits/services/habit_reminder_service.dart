import '../../../services/notification_service.dart';
import '../../../services/storage/habit_storage.dart';
import '../models/habit_goal.dart';
import '../models/habit_goal_rule.dart';
import '../models/habit_progress.dart';
import '../widgets/habit_format.dart';
import 'habit_progress_calculator.dart';
import 'habit_rule_resolver.dart';

/// 习惯提醒调度服务（设计文档 §18，PR4）。
///
/// - 完成型：复用循环待办现有提醒，不重复注册；
/// - 数量型：固定提醒 + 进度提醒，达标后取消当天剩余提醒；
/// - 时间点型：目标前 30 分钟提醒 + 临近提醒（nearEnd）；
/// - 时长型：固定时刻目标提醒（含剩余时长）；
/// - 每日总结提醒（dailySummary）。
///
/// 通知 ID 使用设计文档 §18.5 预留的 42001～49999 区间，按
/// `habitUuid + reminderSlot + logicalDate` 生成稳定哈希。
abstract final class HabitReminderService {
  /// 通知 ID 区间（设计文档 §18.5：42001～49999 习惯目标提醒）。
  static const int baseId = 42001;
  static const int maxId = 49999;
  static const int _idSpan = maxId - baseId + 1;

  /// 时间点型：目标前多少分钟提醒。
  static const int timePointAdvanceMinutes = 30;

  /// 时间点型临近提醒：目标前多少分钟。
  static const int timePointNearEndMinutes = 5;

  /// 无固定时间时，进度提醒 / 每日总结的默认时刻。
  static const int progressReminderDefaultMinute = 20 * 60;
  static const int dailySummaryDefaultMinute = 21 * 60;

  /// 按稳定哈希生成区间内通知 ID。
  static int notifIdFor(String habitUuid, String slot, String logicalDate) {
    final input = '$habitUuid|$slot|$logicalDate';
    var hash = 0;
    for (final code in input.codeUnits) {
      hash = (hash * 31 + code) & 0x7fffffff;
    }
    return baseId + hash % _idSpan;
  }

  static bool isHabitNotificationId(int id) => id >= baseId && id <= maxId;

  /// 重新调度单个习惯今天剩余时间的提醒。
  ///
  /// 打卡 / 达标 / 删除等操作后调用，实现「达标后取消当天剩余提醒」。
  static Future<void> rescheduleFor(String habitUuid) async {
    final goals = await HabitStorage.getHabitGoals(includeArchived: false);
    final goal = goals.where((g) => g.uuid == habitUuid).firstOrNull;
    if (goal == null) return;
    final rules = await HabitStorage.getRuleRevisions(
      habitUuid: habitUuid,
      includeDeleted: false,
    );
    if (rules.isEmpty) return;
    await _reschedule([goal], {goal.uuid: rules});
  }

  /// 重新调度全部活跃习惯今天剩余时间的提醒。
  ///
  /// 应用启动 / 规则编辑后调用，覆盖跨天后的固定时刻提醒。
  static Future<void> rescheduleAll() async {
    final goals = await HabitStorage.getHabitGoals(includeArchived: false);
    if (goals.isEmpty) return;
    final rules = await HabitStorage.getRuleRevisions(includeDeleted: false);
    final rulesByHabit = <String, List<HabitGoalRuleRevision>>{};
    for (final goal in goals) {
      final list = rules.where((r) => r.habitUuid == goal.uuid).toList()
        ..sort((a, b) =>
            (a.effectiveFromDate ?? '').compareTo(b.effectiveFromDate ?? ''));
      if (list.isNotEmpty) rulesByHabit[goal.uuid] = list;
    }
    if (rulesByHabit.isEmpty) return;
    await _reschedule(goals, rulesByHabit);
  }

  /// 取消今日已注册但尚未触发的习惯提醒（达标后调用）。
  static Future<void> cancelHabitReminders() async {
    final scheduled = await NotificationService.getScheduledReminders();
    final habitIds = scheduled
        .map((r) => (r['notifId'] as num?)?.toInt())
        .whereType<int>()
        .where(isHabitNotificationId)
        .toSet();
    for (final id in habitIds) {
      await NotificationService.cancelReminder(id);
    }
  }

  // ── 内部 ─────────────────────────────────────────────

  static Future<void> _reschedule(
    List<HabitGoal> goals,
    Map<String, List<HabitGoalRuleRevision>> rulesByHabit,
  ) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final logicalKey = HabitRuleResolver.dayKey(today);
    final reminders = <Map<String, dynamic>>[];

    for (final goal in goals) {
      final rules = rulesByHabit[goal.uuid];
      if (rules == null || rules.isEmpty) continue;
      final rule = HabitRuleResolver.effectiveRule(rules, today);
      if (rule == null) continue;
      // 完成型：复用循环待办现有提醒（设计文档 18.1）。
      if (goal.sourceType == HabitSourceType.recurringTodo) continue;
      if (!HabitRuleResolver.isPlannedDay(rule, today)) continue;

      final progress = await HabitProgressCalculator.computePeriod(
        habit: goal,
        rules: rules,
        logicalDate: today,
      );
      // 跳过日与已达标日：当天不再注册提醒（达标取消，设计文档 18.3）。
      if (progress.isSkipped || progress.goalMet) continue;

      final title = '${goal.icon.isNotEmpty ? goal.icon : '🎯'} ${goal.name}';
      final unit = rule.unit;
      final policy = rule.reminderPolicy;

      switch (goal.sourceType) {
        case HabitSourceType.quantityCheckIn:
          _buildQuantityReminders(
            goal,
            rule,
            policy,
            progress,
            title,
            unit,
            today,
            now,
            logicalKey,
            reminders,
          );
        case HabitSourceType.pomodoroTag:
          _buildDurationReminders(
            goal,
            rule,
            policy,
            progress,
            title,
            today,
            now,
            logicalKey,
            reminders,
          );
        case HabitSourceType.timeCheckIn:
          _buildTimePointReminders(
            goal,
            rule,
            policy,
            title,
            today,
            now,
            logicalKey,
            reminders,
          );
        case HabitSourceType.recurringTodo:
          break;
      }
    }

    // 全量重排：先取消旧的区间内提醒，再增量注册新提醒，
    // 避免 clearFirst 清掉待办/课程等其他模块的提醒。
    await cancelHabitReminders();
    if (reminders.isEmpty) return;
    await NotificationService.scheduleReminders(reminders, clearFirst: false);
  }

  /// 数量型：固定提醒 + 进度提醒。
  static void _buildQuantityReminders(
    HabitGoal goal,
    HabitGoalRuleRevision rule,
    HabitReminderPolicy policy,
    HabitProgress progress,
    String title,
    String unit,
    DateTime today,
    DateTime now,
    String logicalKey,
    List<Map<String, dynamic>> reminders,
  ) {
    final current = _trim(progress.currentValue);
    final target = _trim(progress.targetValue);
    final unitText = unit.isNotEmpty ? ' $unit' : '';

    for (final minuteOfDay in _sortedFixedTimes(policy)) {
      _addReminder(
        reminders: reminders,
        goal: goal,
        slot: 'fixed-$minuteOfDay',
        triggerAt: today.add(Duration(minutes: minuteOfDay)),
        now: now,
        title: title,
        text: progress.currentValue > 0
            ? '今日已 $current/$target$unitText'
            : '记得打卡${unitText.isEmpty ? '' : '（$unit）'}',
      );
    }
    if (policy.progressReminder && progress.targetValue > 0) {
      final remaining = progress.targetValue - progress.currentValue;
      _addReminder(
        reminders: reminders,
        goal: goal,
        slot: 'progress',
        triggerAt: today.add(Duration(minutes: progressReminderDefaultMinute)),
        now: now,
        title: title,
        text: remaining > 0
            ? '今日 $current/$target$unitText，还差 ${_trim(remaining)}$unitText'
            : '今日已达标 $target$unitText',
      );
    }
    _addDailySummary(
      goal: goal,
      policy: policy,
      title: title,
      progress: progress,
      today: today,
      now: now,
      logicalKey: logicalKey,
      reminders: reminders,
    );
  }

  /// 时长型：固定时刻目标提醒（含剩余时长）+ 进度提醒。
  static void _buildDurationReminders(
    HabitGoal goal,
    HabitGoalRuleRevision rule,
    HabitReminderPolicy policy,
    HabitProgress progress,
    String title,
    DateTime today,
    DateTime now,
    String logicalKey,
    List<Map<String, dynamic>> reminders,
  ) {
    final currentMin = (progress.currentValue / 60).ceil();
    final targetMin = (progress.targetValue / 60).ceil();

    for (final minuteOfDay in _sortedFixedTimes(policy)) {
      final remaining = progress.targetValue - progress.currentValue;
      _addReminder(
        reminders: reminders,
        goal: goal,
        slot: 'fixed-$minuteOfDay',
        triggerAt: today.add(Duration(minutes: minuteOfDay)),
        now: now,
        title: title,
        text: remaining > 0
            ? '今天还需 ${(remaining / 60).ceil()} 分钟，点击开始专注'
            : '今日目标已完成',
      );
    }
    if (policy.progressReminder && progress.targetValue > 0) {
      _addReminder(
        reminders: reminders,
        goal: goal,
        slot: 'progress',
        triggerAt: today.add(Duration(minutes: progressReminderDefaultMinute)),
        now: now,
        title: title,
        text: '今日已专注 $currentMin/$targetMin 分钟',
      );
    }
    _addDailySummary(
      goal: goal,
      policy: policy,
      title: title,
      progress: progress,
      today: today,
      now: now,
      logicalKey: logicalKey,
      reminders: reminders,
    );
  }

  /// 时间点型：目标前 30 分钟 + 临近提醒。
  static void _buildTimePointReminders(
    HabitGoal goal,
    HabitGoalRuleRevision rule,
    HabitReminderPolicy policy,
    String title,
    DateTime today,
    DateTime now,
    String logicalKey,
    List<Map<String, dynamic>> reminders,
  ) {
    final targetMinute = rule.targetTimeMinute;
    if (targetMinute == null) return;
    final target = today.add(Duration(minutes: targetMinute));

    // 提前提醒：目标前 30 分钟。
    _addReminder(
      reminders: reminders,
      goal: goal,
      slot: 'advance',
      triggerAt: target.subtract(Duration(minutes: timePointAdvanceMinutes)),
      now: now,
      title: title,
      text: '距离目标 ${HabitText.targetTime(targetMinute)}'
          '还有 $timePointAdvanceMinutes 分钟',
    );
    // 临近提醒（nearEnd）。
    if (policy.nearEndReminder) {
      _addReminder(
        reminders: reminders,
        goal: goal,
        slot: 'near-end',
        triggerAt: target.subtract(Duration(minutes: timePointNearEndMinutes)),
        now: now,
        title: title,
        text: '目标即将到达（${HabitText.targetTime(targetMinute)}）',
      );
    }
    _addDailySummary(
      goal: goal,
      policy: policy,
      title: title,
      progress: null,
      today: today,
      now: now,
      logicalKey: logicalKey,
      reminders: reminders,
    );
  }

  static void _addDailySummary(
      {required HabitGoal goal,
      required HabitReminderPolicy policy,
      required String title,
      required HabitProgress? progress,
      required DateTime today,
      required DateTime now,
      required String logicalKey,
      required List<Map<String, dynamic>> reminders}) {
    if (!policy.dailySummaryReminder) return;
    _addReminder(
      reminders: reminders,
      goal: goal,
      slot: 'summary',
      triggerAt: today.add(Duration(minutes: dailySummaryDefaultMinute)),
      now: now,
      title: title,
      text: progress?.goalMet == true ? '今日目标已达成 🎉' : '今日还未达标',
    );
  }

  static void _addReminder({
    required List<Map<String, dynamic>> reminders,
    required HabitGoal goal,
    required String slot,
    required DateTime triggerAt,
    required DateTime now,
    required String title,
    required String text,
  }) {
    if (!triggerAt.isAfter(now)) return;
    reminders.add({
      'triggerAtMs': triggerAt.millisecondsSinceEpoch,
      'title': title,
      'text': text,
      'notifId': notifIdFor(
        goal.uuid,
        slot,
        HabitRuleResolver.dayKey(triggerAt),
      ),
      'type': 'habit',
      'habitGoalId': goal.uuid,
    });
  }

  static List<int> _sortedFixedTimes(HabitReminderPolicy policy) {
    final times = policy.fixedTimes.toSet().toList()..sort();
    return times;
  }

  static String _trim(double value) {
    if (value == value.roundToDouble()) return value.round().toString();
    return value.toStringAsFixed(1);
  }
}
