import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../models.dart';
import '../../../services/storage/habit_storage.dart';
import '../../../services/storage/user_session_storage.dart';
import '../../../storage_service.dart';
import '../models/habit_checkin.dart';
import '../models/habit_goal.dart';
import '../models/habit_goal_rule.dart';
import '../services/habit_adaptation_service.dart';
import '../services/habit_reminder_service.dart';
import '../services/habit_rule_resolver.dart';
import '../services/habit_source_resolver.dart';

/// 习惯业务门面：目标、规则版本与打卡的统一入口。
///
/// 本地保存走 [HabitStorage]；写入成功后由统一同步队列自动上行。
abstract final class HabitRepository {
  /// 习惯存储层负责写入 oplog，这里负责把变更交给自动同步队列。
  ///
  /// 部分旧调用方没有显式传入账号，回退到当前登录账号；未登录时仍
  /// 保持本地可用，后续登录或手动同步会消费 oplog。
  static Future<void> _requestSync([String username = '']) async {
    final explicitUsername = username.trim();
    final resolvedUsername = explicitUsername.isNotEmpty
        ? explicitUsername
        : ((await StorageService.getCurrentUsername())?.trim() ?? '');
    if (resolvedUsername.isNotEmpty) {
      StorageService.requestSync(resolvedUsername);
    }
  }

  // ── 目标 ─────────────────────────────────────────────

  static Future<List<HabitGoal>> getGoals() async =>
      HabitStorage.getHabitGoals();

  static Future<List<HabitGoal>> getActiveGoals() async =>
      HabitStorage.getHabitGoals(includeArchived: false);

  /// 循环待办来源且仅在习惯模块展示的活动习惯系列。
  ///
  /// 首页待办列表会隐藏这些系列；逾期待办统计也应遵循相同展示口径。
  static Future<Set<String>> getHabitOnlyRecurringTodoSeriesIds() async {
    final goals = await getActiveGoals();
    return goals
        .where(
          (goal) =>
              goal.sourceType == HabitSourceType.recurringTodo &&
              goal.displayMode == HabitDisplayMode.habitOnly,
        )
        .expand((goal) => goal.sourceIds)
        .where((seriesId) => seriesId.isNotEmpty)
        .toSet();
  }

  static Future<List<HabitGoalRuleRevision>> getRules({String? habitUuid}) =>
      HabitStorage.getRuleRevisions(habitUuid: habitUuid);

  static Future<List<HabitGoalRuleRevision>> getRulesForHabits(
    Iterable<String> habitUuids,
  ) => HabitStorage.getRuleRevisionsForHabits(habitUuids);

  static Future<List<HabitCheckIn>> getCheckIns({
    String? habitUuid,
    String? fromDate,
    String? toDate,
  }) => HabitStorage.getCheckIns(
    habitUuid: habitUuid,
    fromDate: fromDate,
    toDate: toDate,
  );

  static Future<List<HabitCheckIn>> getCheckInsForHabits(
    Iterable<String> habitUuids, {
    String? fromDate,
    String? toDate,
    bool includeDeleted = false,
  }) => HabitStorage.getCheckInsForHabits(
    habitUuids,
    fromDate: fromDate,
    toDate: toDate,
    includeDeleted: includeDeleted,
  );

  /// 创建习惯（含首个规则版本）。
  ///
  /// 完成型习惯直接在习惯模块内通过 [HabitCheckIn] 记录打卡，不再自动新建循环待办；
  /// 若传入已有循环待办系列 [sourceIds]，则会导入其历史完成/跳过记录并将原循环待办移入回收站。
  /// 返回创建后的 [HabitGoal]。
  static Future<HabitGoal> createGoal({
    required String name,
    String icon = '🎯',
    required HabitSourceType sourceType,
    List<String> sourceIds = const [],
    required HabitGoalRuleRevision rule,
    String? goalUuid,
    String? ruleUuid,
    HabitDisplayMode displayMode = HabitDisplayMode.habitOnly,
    int? defaultFocusMinutes,
    String username = '',
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final deviceId = await UserSessionStorage.getDeviceId();
    final pendingImportSeriesIds = sourceType == HabitSourceType.recurringTodo
        ? sourceIds
              .map((id) => id.trim())
              .where((id) => id.isNotEmpty)
              .toList(growable: false)
        : const <String>[];

    if (sourceType == HabitSourceType.recurringTodo) {
      rule.effectiveFromDate ??= HabitRuleResolver.dayKey(
        HabitRuleResolver.logicalDateFor(
          DateTime.now(),
          rule.dayBoundaryMinute,
        ),
      );
      if (rule.targetValue <= 0) {
        rule.targetValue = 1;
      }
      sourceIds = const [];
      displayMode = HabitDisplayMode.habitOnly;
    }

    final goal = HabitGoal(
      uuid: goalUuid,
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
      uuid: ruleUuid ?? rule.uuid,
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
    if (pendingImportSeriesIds.isNotEmpty) {
      await _importAndRetireRecurringTodoSeries(
        goal: goal,
        rule: ruleForGoal,
        seriesIds: pendingImportSeriesIds,
        username: username,
      );
    }
    await _requestSync(username);
    StorageService.triggerRefresh(const {DataRefreshDomain.habits});
    unawaited(HabitReminderService.rescheduleAll().catchError((_) {}));
    return goal;
  }

  /// 将已有循环待办系列转为独立完成型习惯：
  /// 导入周期规则与历史已完成/已跳过期次，并将原循环待办整组移入回收站。
  static Future<HabitGoal?> createGoalFromSeries({
    required TodoItem todo,
    String username = '',
  }) async {
    final seriesId = (todo.recurrenceSeriesId ?? todo.id).trim();
    if (seriesId.isEmpty) return null;

    final seriesTodos = await _loadSeriesTodosForImport(
      [seriesId],
      username: username,
      fallbackTodos: [todo],
    );
    final now = DateTime.now();
    var earliestLogicalDate = HabitRuleResolver.logicalDateFor(now, 0);
    for (final item in seriesTodos) {
      if (item.isDeleted) continue;
      final day = _todoLocalDay(item);
      if (day != null && day.isBefore(earliestLogicalDate)) {
        earliestLogicalDate = day;
      }
    }

    var reminderPolicy = const HabitReminderPolicy();
    if (!todo.isAllDay &&
        todo.reminderMinutes != null &&
        todo.reminderMinutes! >= 0 &&
        todo.createdDate != null) {
      final triggerLocal = DateTime.fromMillisecondsSinceEpoch(
        todo.createdDate!,
      ).toLocal().subtract(Duration(minutes: todo.reminderMinutes!));
      final minuteOfDay = (triggerLocal.hour * 60 + triggerLocal.minute).clamp(
        0,
        1439,
      );
      reminderPolicy = HabitReminderPolicy(fixedTimes: [minuteOfDay]);
    }

    final rule = HabitGoalRuleRevision(
      habitUuid: '',
      effectiveFromDate: HabitRuleResolver.dayKey(earliestLogicalDate),
      periodType: _periodFromRecurrence(todo),
      weekdaysMask: todo.recurrence == RecurrenceType.weekdays ? 31 : 127,
      customIntervalDays: todo.recurrence == RecurrenceType.customDays
          ? (todo.customIntervalDays ?? 0)
          : null,
      targetValue: 1,
      reminderPolicy: reminderPolicy,
    );
    return createGoal(
      name: todo.title,
      icon: defaultIconForName(todo.title),
      sourceType: HabitSourceType.recurringTodo,
      sourceIds: [seriesId],
      rule: rule,
      displayMode: HabitDisplayMode.habitOnly,
      username: username,
    );
  }

  /// 自动迁移旧版绑定了循环待办系列的完成型习惯：
  /// 将已完成/已跳过的待办期次转为独立 [HabitCheckIn]，软删除原循环待办系列，
  /// 并清空习惯上的 [HabitGoal.sourceIds]。
  static Future<void> migrateLegacyRecurringTodoHabits({
    String username = '',
  }) async {
    final goals = await HabitStorage.getHabitGoals();
    final legacyGoals = goals
        .where(
          (goal) =>
              !goal.isDeleted &&
              goal.sourceType == HabitSourceType.recurringTodo &&
              goal.sourceIds.any((id) => id.trim().isNotEmpty),
        )
        .toList(growable: false);
    if (legacyGoals.isEmpty) return;

    final rulesByHabit = <String, List<HabitGoalRuleRevision>>{};
    final allRules = await HabitStorage.getRuleRevisionsForHabits(
      legacyGoals.map((goal) => goal.uuid),
    );
    for (final rule in allRules) {
      if (rule.isDeleted) continue;
      (rulesByHabit[rule.habitUuid] ??= <HabitGoalRuleRevision>[]).add(rule);
    }

    final updatedGoals = <HabitGoal>[];
    for (final goal in legacyGoals) {
      final rules = rulesByHabit[goal.uuid] ?? const <HabitGoalRuleRevision>[];
      HabitGoalRuleRevision rule;
      if (rules.isNotEmpty) {
        rules.sort(
          (a, b) =>
              (a.effectiveFromDate ?? '').compareTo(b.effectiveFromDate ?? ''),
        );
        rule = rules.first;
      } else {
        rule = HabitGoalRuleRevision(
          habitUuid: goal.uuid,
          effectiveFromDate: HabitRuleResolver.dayKey(DateTime.now()),
          periodType: HabitPeriodType.daily,
          targetValue: 1,
        );
        goal.currentRuleUuid = rule.uuid;
        await HabitStorage.saveRuleRevisions([rule]);
      }

      await _importAndRetireRecurringTodoSeries(
        goal: goal,
        rule: rule,
        seriesIds: List<String>.of(goal.sourceIds),
        username: username,
      );
      goal
        ..sourceIds = const []
        ..displayMode = HabitDisplayMode.habitOnly
        ..markAsChanged();
      updatedGoals.add(goal);
    }

    if (updatedGoals.isNotEmpty) {
      await HabitStorage.saveHabitGoals(updatedGoals);
      await _requestSync(username);
      StorageService.triggerRefresh(const {
        DataRefreshDomain.habits,
        DataRefreshDomain.todos,
      });
    }
  }

  static Future<void> _importAndRetireRecurringTodoSeries({
    required HabitGoal goal,
    required HabitGoalRuleRevision rule,
    required List<String> seriesIds,
    String username = '',
  }) async {
    final cleanSeriesIds = seriesIds
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList(growable: false);
    if (cleanSeriesIds.isEmpty) return;

    final resolvedUsername = await _resolveUsername(username);
    final seriesTodos = await _loadSeriesTodosForImport(
      cleanSeriesIds,
      username: resolvedUsername,
    );
    if (seriesTodos.isEmpty) return;

    final deviceId = await UserSessionStorage.getDeviceId();
    final existingCheckIns = await HabitStorage.getCheckIns(
      habitUuid: goal.uuid,
    );
    final existingDoneDates = <String>{};
    final existingSkipDates = <String>{};
    for (final checkIn in existingCheckIns) {
      if (checkIn.isDeleted) continue;
      if (checkIn.source == HabitCheckInSource.skip) {
        existingSkipDates.add(checkIn.logicalDate);
      } else {
        existingDoneDates.add(checkIn.logicalDate);
      }
    }

    final newCheckIns = <HabitCheckIn>[];
    String? earliestDateKey = rule.effectiveFromDate;
    for (final todo in seriesTodos) {
      if (todo.isDeleted) continue;
      final localDay = _todoLocalDay(todo);
      if (localDay == null) continue;
      final dayKey = HabitRuleResolver.dayKey(localDay);
      if (earliestDateKey == null ||
          earliestDateKey.isEmpty ||
          dayKey.compareTo(earliestDateKey) < 0) {
        earliestDateKey = dayKey;
      }

      final occurredMs = todo.createdDate ?? todo.createdAt;
      final localOccurred = DateTime.fromMillisecondsSinceEpoch(occurredMs)
          .toLocal();
      if (todo.isDone && existingDoneDates.add(dayKey)) {
        newCheckIns.add(
          HabitCheckIn(
            habitUuid: goal.uuid,
            ruleRevisionUuid: rule.uuid,
            occurredAt: localOccurred.toUtc().millisecondsSinceEpoch,
            logicalDate: dayKey,
            timezoneOffsetMinutes: localOccurred.timeZoneOffset.inMinutes,
            value: 1,
            note: todo.remark?.trim().isNotEmpty == true
                ? todo.remark!.trim()
                : null,
            source: HabitCheckInSource.manual,
            dedupeKey: HabitCheckIn.buildDedupeKey(
              goal.uuid,
              'completion/$dayKey',
            ),
            deviceId: deviceId,
          ),
        );
      } else if (todo.isSkipped &&
          !existingDoneDates.contains(dayKey) &&
          existingSkipDates.add(dayKey)) {
        newCheckIns.add(
          HabitCheckIn(
            habitUuid: goal.uuid,
            ruleRevisionUuid: rule.uuid,
            occurredAt: localOccurred.toUtc().millisecondsSinceEpoch,
            logicalDate: dayKey,
            timezoneOffsetMinutes: localOccurred.timeZoneOffset.inMinutes,
            value: 0,
            source: HabitCheckInSource.skip,
            dedupeKey: HabitCheckIn.buildDedupeKey(goal.uuid, 'skip/$dayKey'),
            deviceId: deviceId,
          ),
        );
      }
    }

    if (earliestDateKey != null &&
        earliestDateKey.isNotEmpty &&
        earliestDateKey != rule.effectiveFromDate) {
      rule
        ..effectiveFromDate = earliestDateKey
        ..markAsChanged();
      await HabitStorage.saveRuleRevisions([rule]);
    }
    if (newCheckIns.isNotEmpty) {
      await HabitStorage.saveCheckIns(newCheckIns);
    }

    final activeTodos = seriesTodos
        .where((todo) => !todo.isDeleted)
        .toList(growable: false);
    if (activeTodos.isNotEmpty) {
      final deletedItems = <TodoItem>[];
      for (final todo in activeTodos) {
        final copy = todo.detachedCopy()
          ..isDeleted = true
          ..markAsChanged();
        deletedItems.add(copy);
      }
      try {
        await StorageService.saveTodos(resolvedUsername, deletedItems);
      } catch (e) {
        debugPrint('⚠️ 迁移循环待办至回收站失败: $e');
      }
    }
  }

  static Future<List<TodoItem>> _loadSeriesTodosForImport(
    List<String> seriesIds, {
    String username = '',
    List<TodoItem> fallbackTodos = const [],
  }) async {
    final cleanIds = seriesIds
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toSet();
    if (cleanIds.isEmpty) return fallbackTodos;

    final byId = <String, TodoItem>{};
    for (final todo in fallbackTodos) {
      final seriesId = (todo.recurrenceSeriesId ?? todo.id).trim();
      if (cleanIds.contains(seriesId) || cleanIds.contains(todo.id)) {
        byId[todo.id] = todo;
      }
    }
    final fromDb = await HabitSourceResolver.todosForSeries(
      cleanIds.toList(growable: false),
    );
    for (final todo in fromDb) {
      byId[todo.id] = todo;
    }
    return byId.values.toList(growable: false);
  }

  static DateTime? _todoLocalDay(TodoItem todo) {
    final ms = todo.createdDate ?? todo.createdAt;
    if (ms <= 0) return null;
    final local = DateTime.fromMillisecondsSinceEpoch(ms).toLocal();
    return DateTime(local.year, local.month, local.day);
  }

  static Future<String> _resolveUsername([String username = '']) async {
    final explicitUsername = username.trim();
    if (explicitUsername.isNotEmpty) return explicitUsername;
    final current = (await StorageService.getCurrentUsername())?.trim() ?? '';
    return current.isNotEmpty ? current : 'default';
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

  /// 完成型固定提醒的时刻：把 [minuteOfDay]（0..1439）映射到
  /// [day] 对应的本地时刻。
  @visibleForTesting
  static DateTime reminderStartFor(DateTime day, int minuteOfDay) {
    final m = minuteOfDay.clamp(0, 1439);
    return DateTime(day.year, day.month, day.day, m ~/ 60, m % 60);
  }

  /// 更新习惯展示信息（名称、图标、排序、显示位置）。
  static Future<void> updateGoal(HabitGoal goal, {String username = ''}) async {
    goal.markAsChanged();
    await HabitStorage.saveHabitGoals([goal]);
    await _requestSync(username);
    StorageService.triggerRefresh(const {DataRefreshDomain.habits});
    unawaited(HabitReminderService.rescheduleAll().catchError((_) {}));
  }

  /// 修改目标规则。
  ///
  /// [effectiveFromOption]：
  /// - 'today'：从今天开始（默认），关闭旧版本、新规则从今天生效；
  /// - 'nextPeriod'：从下一个周期开始（如每周从下周一、每月从下月 1 号）；
  /// - 'all'：修改全部历史目标；可指定仅覆盖部分规则字段。
  /// [fieldsToUpdate] 仅用于选择性覆盖全部历史时保留未指定的历史规则字段；
  /// 留空时保持旧调用方的整条规则覆盖语义。
  static Future<void> updateRule({
    required HabitGoal goal,
    required HabitGoalRuleRevision updatedRule,
    String effectiveFromOption = 'today',
    required List<HabitGoalRuleRevision> allRules,
    Set<String>? fieldsToUpdate,
    String username = '',
  }) async {
    final todayKey = HabitRuleResolver.dayKey(
      HabitRuleResolver.logicalDateFor(
        DateTime.now(),
        updatedRule.dayBoundaryMinute,
      ),
    );

    if (effectiveFromOption == 'all') {
      for (final rule in allRules) {
        if (rule.isDeleted) continue;
        if (fieldsToUpdate == null || fieldsToUpdate.contains('targetValue')) {
          rule.targetValue = updatedRule.targetValue;
        }
        if (fieldsToUpdate == null || fieldsToUpdate.contains('unit')) {
          rule.unit = updatedRule.unit;
        }
        if (fieldsToUpdate == null ||
            fieldsToUpdate.contains('targetTimeMinute')) {
          rule.targetTimeMinute = updatedRule.targetTimeMinute;
        }
        if (fieldsToUpdate == null ||
            fieldsToUpdate.contains('timeComparison')) {
          rule.timeComparison = updatedRule.timeComparison;
        }
        if (fieldsToUpdate == null ||
            fieldsToUpdate.contains('timeToleranceMinutes')) {
          rule.timeToleranceMinutes = updatedRule.timeToleranceMinutes;
        }
        if (fieldsToUpdate == null || fieldsToUpdate.contains('periodType')) {
          rule.periodType = updatedRule.periodType;
        }
        if (fieldsToUpdate == null || fieldsToUpdate.contains('weekdaysMask')) {
          rule.weekdaysMask = updatedRule.weekdaysMask;
        }
        if (fieldsToUpdate == null ||
            fieldsToUpdate.contains('customIntervalDays')) {
          rule.customIntervalDays = updatedRule.customIntervalDays;
        }
        if (fieldsToUpdate == null ||
            fieldsToUpdate.contains('dayBoundaryMinute')) {
          rule.dayBoundaryMinute = updatedRule.dayBoundaryMinute;
        }
        if (fieldsToUpdate == null || fieldsToUpdate.contains('quickValues')) {
          rule.quickValues = updatedRule.quickValues;
        }
        if (fieldsToUpdate == null ||
            fieldsToUpdate.contains('reminderPolicy')) {
          rule.reminderPolicy = updatedRule.reminderPolicy;
        }
        rule.markAsChanged();
      }
      final current = HabitRuleResolver.effectiveRule(allRules, DateTime.now());
      if (current != null) goal.currentRuleUuid = current.uuid;
      await HabitStorage.saveRuleRevisions(allRules);
      await HabitStorage.saveHabitGoals([goal]);
      await _requestSync(username);
      StorageService.triggerRefresh(const {DataRefreshDomain.habits});
      unawaited(HabitReminderService.rescheduleAll().catchError((_) {}));
      return;
    }

    final sorted = allRules.where((r) => !r.isDeleted).toList()
      ..sort(
        (a, b) =>
            (a.effectiveFromDate ?? '').compareTo(b.effectiveFromDate ?? ''),
      );
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
      await _requestSync(username);
      StorageService.triggerRefresh(const {DataRefreshDomain.habits});
      unawaited(HabitReminderService.rescheduleAll().catchError((_) {}));
      return;
    }

    final startKey = effectiveFromOption == 'nextPeriod' && current != null
        ? HabitRuleResolver.dayKey(
            HabitRuleResolver.nextPeriodStart(
              current,
              HabitRuleResolver.logicalDateFor(
                DateTime.now(),
                current.dayBoundaryMinute,
              ),
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
    await _requestSync(username);
    StorageService.triggerRefresh(const {DataRefreshDomain.habits});
    unawaited(HabitReminderService.rescheduleAll().catchError((_) {}));
  }

  /// 归档 / 取消归档习惯。
  static Future<void> setArchived(HabitGoal goal, bool archived) async {
    if (goal.isArchived == archived) return;
    goal.isArchived = archived;
    goal.markAsChanged();
    await HabitStorage.saveHabitGoals([goal]);
    await _requestSync();
    StorageService.triggerRefresh(const {DataRefreshDomain.habits});
    unawaited(HabitReminderService.rescheduleAll().catchError((_) {}));
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
    await _requestSync();
    StorageService.triggerRefresh(const {DataRefreshDomain.habits});
    unawaited(HabitReminderService.rescheduleAll().catchError((_) {}));
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
    final replacedCount = _shouldReplaceSleepTimePoint(goal, source)
        ? await _replaceSleepTimePointCheckIns(
            goal: goal,
            logicalDate: checkIn.logicalDate,
          )
        : 0;
    checkIn.replacedPrevious = replacedCount > 0;
    await HabitStorage.saveCheckIns([checkIn]);
    await _requestSync();
    StorageService.triggerRefresh(const {DataRefreshDomain.habits});
    _rescheduleReminders(goal.uuid);
    return checkIn;
  }

  static Future<void> updateCheckIn(HabitCheckIn checkIn) async {
    checkIn.markAsChanged();
    await HabitStorage.saveCheckIns([checkIn]);
    await _requestSync();
    StorageService.triggerRefresh(const {DataRefreshDomain.habits});
    _rescheduleReminders(checkIn.habitUuid);
  }

  /// Persist already-versioned check-in changes together, then publish one
  /// sync request, refresh signal, and reminder reschedule per affected habit.
  static Future<void> saveCheckInsBatch(List<HabitCheckIn> checkIns) async {
    if (checkIns.isEmpty) return;
    await HabitStorage.saveCheckIns(checkIns);
    await _requestSync();
    StorageService.triggerRefresh(const {DataRefreshDomain.habits});
    for (final habitUuid in checkIns.map((item) => item.habitUuid).toSet()) {
      _rescheduleReminders(habitUuid);
    }
  }

  /// 早睡 / 早起是一个「节点结果」，同一晚重复打卡时以后一次为准。
  ///
  /// 只对用户主动产生的记录生效。历史迁移、健康设备等来源保留原始
  /// 事件，避免导入过程因为同一天存在多条日志而相互覆盖。
  static bool _shouldReplaceSleepTimePoint(
    HabitGoal goal,
    HabitCheckInSource source,
  ) {
    if (goal.sourceType != HabitSourceType.timeCheckIn) return false;
    if (source != HabitCheckInSource.manual &&
        source != HabitCheckInSource.notification &&
        source != HabitCheckInSource.widget) {
      return false;
    }
    final kind = HabitAdaptationService.forHabit(goal)?.kind;
    return kind == HabitAdaptationKind.earlySleep ||
        kind == HabitAdaptationKind.earlyWake;
  }

  static Future<int> _replaceSleepTimePointCheckIns({
    required HabitGoal goal,
    required String logicalDate,
  }) async {
    final existing = await HabitStorage.getCheckIns(
      habitUuid: goal.uuid,
      fromDate: logicalDate,
      toDate: logicalDate,
    );
    final replaced = existing
        .where(
          (checkIn) =>
              !checkIn.isDeleted && checkIn.source != HabitCheckInSource.skip,
        )
        .toList(growable: false);
    if (replaced.isEmpty) return 0;

    for (final checkIn in replaced) {
      checkIn
        ..isDeleted = true
        ..markAsChanged();
    }
    await HabitStorage.saveCheckIns(replaced);
    await _requestSync();
    StorageService.triggerRefresh(const {DataRefreshDomain.habits});
    _rescheduleReminders(goal.uuid);
    return replaced.length;
  }

  /// 逻辑删除打卡。
  static Future<void> deleteCheckIn(HabitCheckIn checkIn) async {
    if (checkIn.isDeleted) return;
    checkIn.isDeleted = true;
    checkIn.markAsChanged();
    await HabitStorage.saveCheckIns([checkIn]);
    await _requestSync();
    StorageService.triggerRefresh(const {DataRefreshDomain.habits});
    _rescheduleReminders(checkIn.habitUuid);
  }

  /// 切换某逻辑日的「跳过」标记：有则移除，无则添加。
  ///
  /// 跳过日不执行、不达标，也不中断连续天数（仅每日类周期适用）。
  static Future<void> toggleSkipped({
    required HabitGoal goal,
    required HabitGoalRuleRevision rule,
    required DateTime localDate,
  }) async {
    final logicalDate = HabitRuleResolver.dayKey(
      HabitRuleResolver.logicalDateFor(localDate, rule.dayBoundaryMinute),
    );
    final existing = await HabitStorage.getCheckIns(
      habitUuid: goal.uuid,
      fromDate: logicalDate,
      toDate: logicalDate,
    );
    final skip = existing
        .where((c) => !c.isDeleted && c.source == HabitCheckInSource.skip)
        .firstOrNull;
    if (skip != null) {
      await deleteCheckIn(skip);
      return;
    }
    await addCheckIn(
      goal: goal,
      rule: rule,
      localOccurredAt: localDate,
      source: HabitCheckInSource.skip,
      dedupeKey: HabitCheckIn.buildDedupeKey(goal.uuid, 'skip/$logicalDate'),
    );
  }

  // ── 完成型习惯操作 ───────────────────────────────────

  /// 切换完成型习惯指定逻辑日的完成状态。
  static Future<bool> toggleCompletion({
    required HabitGoal goal,
    required DateTime logicalDate,
    String username = '',
  }) async {
    if (goal.sourceType != HabitSourceType.recurringTodo) return false;
    if (goal.sourceIds.isNotEmpty) {
      await migrateLegacyRecurringTodoHabits(username: username);
    }
    final dayKey = HabitRuleResolver.dayKey(logicalDate);
    final existing = await HabitStorage.getCheckIns(
      habitUuid: goal.uuid,
      fromDate: dayKey,
      toDate: dayKey,
    );
    final isDone = existing.any(
      (checkIn) =>
          !checkIn.isDeleted && checkIn.source != HabitCheckInSource.skip,
    );
    await setCompletion(
      goal: goal,
      logicalDate: logicalDate,
      done: !isDone,
      username: username,
    );
    return true;
  }

  static Future<void> setCompletion({
    required HabitGoal goal,
    required DateTime logicalDate,
    required bool done,
    String username = '',
  }) async {
    if (goal.sourceType != HabitSourceType.recurringTodo) return;
    if (goal.sourceIds.isNotEmpty) {
      await migrateLegacyRecurringTodoHabits(username: username);
    }
    final dayKey = HabitRuleResolver.dayKey(logicalDate);
    final existing = await HabitStorage.getCheckIns(
      habitUuid: goal.uuid,
      fromDate: dayKey,
      toDate: dayKey,
    );
    final activeCompletions = existing
        .where(
          (checkIn) =>
              !checkIn.isDeleted && checkIn.source != HabitCheckInSource.skip,
        )
        .toList(growable: false);
    final activeSkips = existing
        .where(
          (checkIn) =>
              !checkIn.isDeleted && checkIn.source == HabitCheckInSource.skip,
        )
        .toList(growable: false);

    if (done) {
      for (final skip in activeSkips) {
        await deleteCheckIn(skip);
      }
      if (activeCompletions.isNotEmpty) return;

      final rules = await getRules(habitUuid: goal.uuid);
      final rule =
          HabitRuleResolver.effectiveRule(rules, logicalDate) ??
          (rules.isNotEmpty
              ? rules.last
              : HabitGoalRuleRevision(
                  habitUuid: goal.uuid,
                  effectiveFromDate: dayKey,
                  periodType: HabitPeriodType.daily,
                  targetValue: 1,
                ));
      final now = DateTime.now();
      final isToday =
          now.year == logicalDate.year &&
          now.month == logicalDate.month &&
          now.day == logicalDate.day;
      final occurredAt = isToday
          ? now
          : DateTime(logicalDate.year, logicalDate.month, logicalDate.day, 12);
      await addCheckIn(
        goal: goal,
        rule: rule,
        localOccurredAt: occurredAt,
        value: 1,
        dedupeKey: HabitCheckIn.buildDedupeKey(goal.uuid, 'completion/$dayKey'),
      );
      return;
    }

    for (final checkIn in activeCompletions) {
      await deleteCheckIn(checkIn);
    }
  }

  // ── 工具 ─────────────────────────────────────────────

  /// 打卡 / 达标 / 删除后异步重排该习惯今天的提醒，
  /// 实现「达标后取消当天剩余提醒」（设计文档 18.3）。
  static void _rescheduleReminders(String habitUuid) {
    unawaited(HabitReminderService.rescheduleFor(habitUuid).catchError((_) {}));
  }

  static String _previousDay(String dayKey) {
    final date = HabitRuleResolver.parseDayKey(dayKey);
    if (date == null) return dayKey;
    final prev = HabitRuleResolver.addCalendarDays(date, -1);
    return HabitRuleResolver.dayKey(prev);
  }

  /// 为习惯名称生成模板默认图标。
  static String defaultIconForName(String name) {
    const iconMap = {
      '喝水': '💧',
      '早起': '🌅',
      '早睡': '🌙',
      '睡眠时长': '🛌',
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
