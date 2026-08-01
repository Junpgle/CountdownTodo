import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../models.dart';
import '../../../services/storage/habit_storage.dart';
import '../../../services/storage/user_session_storage.dart';
import '../../../storage_service.dart';
import '../models/habit_checkin.dart';
import '../models/habit_goal.dart';
import '../models/habit_goal_rule.dart';
import '../services/habit_rule_resolver.dart';
import '../services/habit_source_resolver.dart';

/// 习惯业务门面：目标、规则版本与打卡的统一入口。
///
/// 云同步尚未接入（PR5），本地保存走 [HabitStorage]。
abstract final class HabitRepository {
  // ── 目标 ─────────────────────────────────────────────

  static Future<List<HabitGoal>> getGoals() async =>
      HabitStorage.getHabitGoals();

  static Future<List<HabitGoal>> getActiveGoals() async =>
      HabitStorage.getHabitGoals(includeArchived: false);

  static Future<List<HabitGoalRuleRevision>> getRules({String? habitUuid}) =>
      HabitStorage.getRuleRevisions(habitUuid: habitUuid);

  static Future<List<HabitCheckIn>> getCheckIns({
    String? habitUuid,
    String? fromDate,
    String? toDate,
  }) =>
      HabitStorage.getCheckIns(
        habitUuid: habitUuid,
        fromDate: fromDate,
        toDate: toDate,
      );

  /// 创建习惯（含首个规则版本）。
  ///
  /// 完成型习惯会同时创建一条循环待办系列（除非指定已有待办系列）。
  /// 返回创建后的 [HabitGoal]。
  static Future<HabitGoal> createGoal({
    required String name,
    String icon = '🎯',
    required HabitSourceType sourceType,
    List<String> sourceIds = const [],
    required HabitGoalRuleRevision rule,
    HabitDisplayMode displayMode = HabitDisplayMode.habitOnly,
    int? defaultFocusMinutes,
    String username = '',
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final deviceId = await UserSessionStorage.getDeviceId();

    if (sourceType == HabitSourceType.recurringTodo && sourceIds.isEmpty) {
      final seriesTodo = await _createRecurringTodoFromRule(
        username: username,
        name: name,
        rule: rule,
      );
      sourceIds = [seriesTodo.recurrenceSeriesId ?? seriesTodo.id];
      rule.effectiveFromDate ??= HabitRuleResolver.dayKey(
        HabitRuleResolver.logicalDateFor(
          DateTime.now(),
          rule.dayBoundaryMinute,
        ),
      );
    }

    final goal = HabitGoal(
      name: name,
      icon: icon,
      sourceType: sourceType,
      sourceIds: sourceIds,
      currentRuleUuid: rule.uuid,
      displayMode: displayMode,
      defaultFocusMinutes: defaultFocusMinutes,
      deviceId: deviceId,
    );

    final ruleForGoal = HabitGoalRuleRevision(
      uuid: rule.uuid,
      habitUuid: goal.uuid,
      effectiveFromDate: rule.effectiveFromDate,
      effectiveToDate: rule.effectiveToDate,
      periodType: rule.periodType,
      weekdaysMask: rule.weekdaysMask,
      customIntervalDays: rule.customIntervalDays,
      targetValue: rule.targetValue,
      unit: rule.unit,
      targetTimeMinute: rule.targetTimeMinute,
      timeComparison: rule.timeComparison,
      timeToleranceMinutes: rule.timeToleranceMinutes,
      dayBoundaryMinute: rule.dayBoundaryMinute,
      quickValues: rule.quickValues,
      reminderPolicy: rule.reminderPolicy,
      createdAt: now,
      updatedAt: now,
    );
    goal.currentRuleUuid = ruleForGoal.uuid;

    await HabitStorage.saveRuleRevisions([ruleForGoal]);
    await HabitStorage.saveHabitGoals([goal]);
    StorageService.triggerRefresh();
    return goal;
  }

  /// 设计文档 4.3：已有循环待办加入习惯追踪。
  ///
  /// 不复制待办数据，仅创建绑定关系（sourceId = 待办系列 ID）；
  /// 默认保留原有显示方式（仅显示在待办模块）。
  /// 该系列已绑定习惯时返回 null。
  static Future<HabitGoal?> createGoalFromSeries({
    required TodoItem todo,
    String username = '',
  }) async {
    final seriesId = todo.recurrenceSeriesId ?? todo.id;
    final existing = await HabitStorage.getHabitGoals();
    if (existing.any((g) => !g.isDeleted && g.sourceIds.contains(seriesId))) {
      return null;
    }

    final now = DateTime.now();
    final rule = HabitGoalRuleRevision(
      habitUuid: '',
      effectiveFromDate: HabitRuleResolver.dayKey(
        HabitRuleResolver.logicalDateFor(now, 0),
      ),
      periodType: _periodFromRecurrence(todo),
      weekdaysMask: todo.recurrence == RecurrenceType.weekdays ? 31 : 127,
      customIntervalDays: todo.recurrence == RecurrenceType.customDays
          ? (todo.customIntervalDays ?? 0)
          : null,
    );
    return createGoal(
      name: todo.title,
      icon: '🎯',
      sourceType: HabitSourceType.recurringTodo,
      sourceIds: [seriesId],
      rule: rule,
      displayMode: HabitDisplayMode.todoOnly,
      username: username,
    );
  }

  static HabitPeriodType _periodFromRecurrence(TodoItem todo) {
    switch (todo.recurrence) {
      case RecurrenceType.weekly:
        return HabitPeriodType.weekly;
      case RecurrenceType.monthly:
        return HabitPeriodType.monthly;
      case RecurrenceType.weekdays:
        return HabitPeriodType.weekdays;
      case RecurrenceType.customDays:
        return HabitPeriodType.custom;
      case RecurrenceType.daily:
      case RecurrenceType.yearly:
      case RecurrenceType.none:
        return HabitPeriodType.daily;
    }
  }

  /// 完成型固定提醒的待办开始时刻：把 [minuteOfDay]（0..1439）映射到
  /// [day] 对应的本地时刻，配合提前量 0 由现有待办提醒调度触发。
  @visibleForTesting
  static DateTime reminderStartFor(DateTime day, int minuteOfDay) {
    final m = minuteOfDay.clamp(0, 1439);
    return DateTime(
      day.year,
      day.month,
      day.day,
      m ~/ 60,
      m % 60,
    );
  }

  static Future<TodoItem> _createRecurringTodoFromRule({
    required String username,
    required String name,
    required HabitGoalRuleRevision rule,
  }) async {
    final now = DateTime.now();
    final todo = TodoItem(
      title: name,
      isAllDay: true,
      createdDate:
          DateTime(now.year, now.month, now.day).millisecondsSinceEpoch,
    );
    todo.recurrence = _recurrenceFromRule(rule);
    todo.customIntervalDays = rule.customIntervalDays;
    todo.recurrenceSeriesId = todo.id;
    todo.isDone = false;
    // 设计文档 18.1：完成型提醒直接复用循环待办现有提醒。
    // 把待办开始时刻设为目标固定时间、提前量 0，即由现有提醒调度在
    // 目标时刻触发（循环实例会继承该时刻）。
    final fixedTimes = rule.reminderPolicy.fixedTimes;
    if (fixedTimes.isNotEmpty) {
      todo.createdDate =
          reminderStartFor(now, fixedTimes.first).millisecondsSinceEpoch;
      todo.reminderMinutes = 0;
    }
    await StorageService.updateSingleTodo(username, todo);
    return todo;
  }

  static RecurrenceType _recurrenceFromRule(HabitGoalRuleRevision rule) {
    switch (rule.periodType) {
      case HabitPeriodType.daily:
        return RecurrenceType.daily;
      case HabitPeriodType.weekly:
        return RecurrenceType.weekly;
      case HabitPeriodType.weekdays:
        if (rule.weekdaysMask == 31) return RecurrenceType.weekdays;
        return RecurrenceType.weekly;
      case HabitPeriodType.monthly:
        return RecurrenceType.monthly;
      case HabitPeriodType.custom:
        return RecurrenceType.customDays;
    }
  }

  /// 更新习惯展示信息（名称、图标、排序、显示位置）。
  static Future<void> updateGoal(HabitGoal goal, {String username = ''}) async {
    goal.markAsChanged();
    await HabitStorage.saveHabitGoals([goal]);
    StorageService.triggerRefresh();
  }

  /// 修改目标规则。
  ///
  /// [effectiveFromOption]：
  /// - 'today'：从今天开始（默认），关闭旧版本、新规则从今天生效；
  /// - 'nextPeriod'：从下一个周期开始（如每周从下周一、每月从下月 1 号）；
  /// - 'all'：修改全部历史目标（覆盖所有版本的目标值）。
  static Future<void> updateRule({
    required HabitGoal goal,
    required HabitGoalRuleRevision updatedRule,
    String effectiveFromOption = 'today',
    required List<HabitGoalRuleRevision> allRules,
  }) async {
    final todayKey = HabitRuleResolver.dayKey(
      HabitRuleResolver.logicalDateFor(
          DateTime.now(), updatedRule.dayBoundaryMinute),
    );

    if (effectiveFromOption == 'all') {
      for (final rule in allRules) {
        if (rule.isDeleted) continue;
        rule
          ..targetValue = updatedRule.targetValue
          ..unit = updatedRule.unit
          ..targetTimeMinute = updatedRule.targetTimeMinute
          ..timeComparison = updatedRule.timeComparison
          ..timeToleranceMinutes = updatedRule.timeToleranceMinutes
          ..periodType = updatedRule.periodType
          ..weekdaysMask = updatedRule.weekdaysMask
          ..customIntervalDays = updatedRule.customIntervalDays
          ..dayBoundaryMinute = updatedRule.dayBoundaryMinute
          ..quickValues = updatedRule.quickValues
          ..reminderPolicy = updatedRule.reminderPolicy
          ..markAsChanged();
      }
      final current = HabitRuleResolver.effectiveRule(allRules, DateTime.now());
      if (current != null) goal.currentRuleUuid = current.uuid;
      await HabitStorage.saveRuleRevisions(allRules);
      await HabitStorage.saveHabitGoals([goal]);
      StorageService.triggerRefresh();
      return;
    }

    final sorted = allRules.where((r) => !r.isDeleted).toList()
      ..sort((a, b) =>
          (a.effectiveFromDate ?? '').compareTo(b.effectiveFromDate ?? ''));
    final current = sorted.isNotEmpty ? sorted.last : null;

    if (effectiveFromOption != 'nextPeriod' &&
        current != null &&
        current.effectiveFromDate == todayKey) {
      // 当前版本今天开始生效：直接修改，不新增版本。
      current
        ..targetValue = updatedRule.targetValue
        ..unit = updatedRule.unit
        ..targetTimeMinute = updatedRule.targetTimeMinute
        ..timeComparison = updatedRule.timeComparison
        ..timeToleranceMinutes = updatedRule.timeToleranceMinutes
        ..periodType = updatedRule.periodType
        ..weekdaysMask = updatedRule.weekdaysMask
        ..customIntervalDays = updatedRule.customIntervalDays
        ..dayBoundaryMinute = updatedRule.dayBoundaryMinute
        ..quickValues = updatedRule.quickValues
        ..reminderPolicy = updatedRule.reminderPolicy
        ..markAsChanged();
      await HabitStorage.saveRuleRevisions([current]);
      await HabitStorage.saveHabitGoals([goal]);
      StorageService.triggerRefresh();
      return;
    }

    final startKey = effectiveFromOption == 'nextPeriod' && current != null
        ? HabitRuleResolver.dayKey(
            HabitRuleResolver.nextPeriodStart(
              current,
              HabitRuleResolver.logicalDateFor(
                  DateTime.now(), current.dayBoundaryMinute),
            ),
          )
        : todayKey;

    final newRule = HabitGoalRuleRevision(
      habitUuid: goal.uuid,
      effectiveFromDate: startKey,
      periodType: updatedRule.periodType,
      weekdaysMask: updatedRule.weekdaysMask,
      customIntervalDays: updatedRule.customIntervalDays,
      targetValue: updatedRule.targetValue,
      unit: updatedRule.unit,
      targetTimeMinute: updatedRule.targetTimeMinute,
      timeComparison: updatedRule.timeComparison,
      timeToleranceMinutes: updatedRule.timeToleranceMinutes,
      dayBoundaryMinute: updatedRule.dayBoundaryMinute,
      quickValues: updatedRule.quickValues,
      reminderPolicy: updatedRule.reminderPolicy,
    );
    goal.currentRuleUuid = newRule.uuid;
    goal.markAsChanged();

    final changes = <HabitGoalRuleRevision>[];
    if (current != null &&
        current.effectiveToDate == null &&
        current.effectiveFromDate != startKey) {
      current
        ..effectiveToDate = _previousDay(startKey)
        ..markAsChanged();
      changes.add(current);
    }
    changes.add(newRule);
    await HabitStorage.saveRuleRevisions(changes);
    await HabitStorage.saveHabitGoals([goal]);
    StorageService.triggerRefresh();
  }

  /// 归档 / 取消归档习惯。
  static Future<void> setArchived(HabitGoal goal, bool archived) async {
    if (goal.isArchived == archived) return;
    goal.isArchived = archived;
    goal.markAsChanged();
    await HabitStorage.saveHabitGoals([goal]);
    StorageService.triggerRefresh();
  }

  /// 逻辑删除习惯。
  static Future<void> deleteGoal(HabitGoal goal) async {
    goal.isDeleted = true;
    goal.isArchived = false;
    goal.markAsChanged();
    final rules = await getRules(habitUuid: goal.uuid);
    final changes = <HabitGoalRuleRevision>[];
    for (final rule in rules) {
      if (rule.isDeleted) continue;
      rule.isDeleted = true;
      rule.markAsChanged();
      changes.add(rule);
    }
    await HabitStorage.saveRuleRevisions(changes);
    await HabitStorage.saveHabitGoals([goal]);
    StorageService.triggerRefresh();
  }

  // ── 打卡 ─────────────────────────────────────────────

  /// 新增一条打卡。返回创建的 [HabitCheckIn]。
  static Future<HabitCheckIn> addCheckIn({
    required HabitGoal goal,
    required HabitGoalRuleRevision rule,
    required DateTime localOccurredAt,
    double value = 0,
    String? note,
    HabitCheckInSource source = HabitCheckInSource.manual,
    String? dedupeKey,
  }) async {
    final deviceId = await UserSessionStorage.getDeviceId();
    final checkIn = HabitCheckIn(
      habitUuid: goal.uuid,
      ruleRevisionUuid: rule.uuid,
      occurredAt: localOccurredAt.toUtc().millisecondsSinceEpoch,
      logicalDate: HabitRuleResolver.dayKey(
        HabitRuleResolver.logicalDateFor(
          localOccurredAt,
          rule.dayBoundaryMinute,
        ),
      ),
      timezoneOffsetMinutes: localOccurredAt.timeZoneOffset.inMinutes,
      value: value,
      note: note,
      source: source,
      dedupeKey: dedupeKey,
      deviceId: deviceId,
    );
    await HabitStorage.saveCheckIns([checkIn]);
    StorageService.triggerRefresh();
    return checkIn;
  }

  static Future<void> updateCheckIn(HabitCheckIn checkIn) async {
    checkIn.markAsChanged();
    await HabitStorage.saveCheckIns([checkIn]);
    StorageService.triggerRefresh();
  }

  /// 逻辑删除打卡。
  static Future<void> deleteCheckIn(HabitCheckIn checkIn) async {
    if (checkIn.isDeleted) return;
    checkIn.isDeleted = true;
    checkIn.markAsChanged();
    await HabitStorage.saveCheckIns([checkIn]);
    StorageService.triggerRefresh();
  }

  // ── 完成型习惯操作 ───────────────────────────────────

  /// 获取完成型习惯今天对应的循环待办实例。
  static Future<TodoItem?> todoOccurrenceForDate(
    HabitGoal goal,
    DateTime logicalDate,
  ) async {
    final todos = await HabitSourceResolver.todosForSeries(
      goal.sourceIds,
    );
    return HabitSourceResolver.todoForDate(todos, logicalDate);
  }

  /// 切换完成型习惯当天实例的完成状态。
  static Future<bool> toggleCompletion({
    required HabitGoal goal,
    required DateTime logicalDate,
    String username = '',
  }) async {
    if (goal.sourceType != HabitSourceType.recurringTodo) return false;
    final todo = await todoOccurrenceForDate(goal, logicalDate);
    if (todo == null) return false;
    if (username.isEmpty) {
      final prefs = await SharedPreferences.getInstance();
      username = prefs.getString(StorageService.keyCurrentUser) ?? '';
    }
    todo.isDone = !todo.isDone;
    todo.markAsChanged();
    await StorageService.updateSingleTodo(username, todo);
    StorageService.triggerRefresh();
    return true;
  }

  static Future<void> setCompletion({
    required HabitGoal goal,
    required DateTime logicalDate,
    required bool done,
    String username = '',
  }) async {
    if (goal.sourceType != HabitSourceType.recurringTodo) return;
    final todo = await todoOccurrenceForDate(goal, logicalDate);
    if (todo == null) return;
    if (todo.isDone == done) return;
    if (username.isEmpty) {
      final prefs = await SharedPreferences.getInstance();
      username = prefs.getString(StorageService.keyCurrentUser) ?? '';
    }
    todo.isDone = done;
    todo.markAsChanged();
    await StorageService.updateSingleTodo(username, todo);
    StorageService.triggerRefresh();
  }

  // ── 工具 ─────────────────────────────────────────────

  static String _previousDay(String dayKey) {
    final date = HabitRuleResolver.parseDayKey(dayKey);
    if (date == null) return dayKey;
    final prev = date.subtract(const Duration(days: 1));
    return HabitRuleResolver.dayKey(prev);
  }

  /// 为习惯名称生成模板默认图标。
  static String defaultIconForName(String name) {
    const iconMap = {
      '喝水': '💧',
      '早起': '🌅',
      '早睡': '🌙',
      '俯卧撑': '💪',
      '阅读': '📖',
      '运动': '🏃',
      '学习': '📚',
      '冥想': '🧘',
      '维生素': '💊',
      '整理': '🧹',
      '单词': '🔤',
      '跑步': '🏃',
    };
    for (final entry in iconMap.entries) {
      if (name.contains(entry.key)) return entry.value;
    }
    return '🎯';
  }
}
