import 'dart:math';

import '../features/habits/models/habit_goal.dart';
import '../features/habits/models/habit_goal_rule.dart';
import '../features/habits/repositories/habit_repository.dart';
import '../features/habits/services/habit_rule_resolver.dart';
import '../models.dart';
import '../models/ai_todo_action.dart';
import 'fixed_schedule_recurrence_service.dart';
import 'pomodoro_service.dart';
import '../utils/json_value_parser.dart';

class _HabitCreationDraft {
  const _HabitCreationDraft({
    required this.name,
    required this.icon,
    required this.sourceType,
    required this.sourceIds,
    required this.rule,
    required this.displayMode,
    required this.defaultFocusMinutes,
  });

  final String name;
  final String icon;
  final HabitSourceType sourceType;
  final List<String> sourceIds;
  final HabitGoalRuleRevision rule;
  final HabitDisplayMode displayMode;
  final int? defaultFocusMinutes;
}

class AiTodoActionExecutionResult {
  const AiTodoActionExecutionResult({
    required this.newTodos,
    required this.updatedTodos,
    this.newTimeLogs = const [],
    this.updatedTimeLogs = const [],
    this.pomodoroActions = const [],
    this.newCountdowns = const [],
    this.updatedCountdowns = const [],
    this.newTodoGroups = const [],
    this.updatedTodoGroups = const [],
    this.newPomodoroTags = const [],
    this.updatedPomodoroTags = const [],
    this.newPlanBlocks = const [],
    this.updatedPlanBlocks = const [],
    this.newFixedSchedules = const [],
    this.updatedFixedSchedules = const [],
    this.newHabitActions = const [],
  });

  final List<TodoItem> newTodos;
  final List<TodoItem> updatedTodos;
  final List<TimeLogItem> newTimeLogs;
  final List<TimeLogItem> updatedTimeLogs;
  final List<AiTodoAction> pomodoroActions;
  final List<CountdownItem> newCountdowns;
  final List<CountdownItem> updatedCountdowns;
  final List<TodoGroup> newTodoGroups;
  final List<TodoGroup> updatedTodoGroups;
  final List<PomodoroTag> newPomodoroTags;
  final List<PomodoroTag> updatedPomodoroTags;
  final List<TodoPlanBlock> newPlanBlocks;
  final List<TodoPlanBlock> updatedPlanBlocks;
  final List<FixedScheduleItem> newFixedSchedules;
  final List<FixedScheduleItem> updatedFixedSchedules;
  final List<AiTodoAction> newHabitActions;

  bool get hasChanges =>
      newTodos.isNotEmpty ||
      updatedTodos.isNotEmpty ||
      newTimeLogs.isNotEmpty ||
      updatedTimeLogs.isNotEmpty ||
      pomodoroActions.isNotEmpty ||
      newCountdowns.isNotEmpty ||
      updatedCountdowns.isNotEmpty ||
      newTodoGroups.isNotEmpty ||
      updatedTodoGroups.isNotEmpty ||
      newPomodoroTags.isNotEmpty ||
      updatedPomodoroTags.isNotEmpty ||
      newPlanBlocks.isNotEmpty ||
      updatedPlanBlocks.isNotEmpty ||
      newFixedSchedules.isNotEmpty ||
      updatedFixedSchedules.isNotEmpty ||
      newHabitActions.isNotEmpty;
}

class AiTodoActionExecutor {
  static AiTodoActionExecutionResult execute({
    required List<AiTodoAction> actions,
    required List<Map<String, dynamic>> existingTodos,
    List<TimeLogItem> existingTimeLogs = const [],
    List<CountdownItem> existingCountdowns = const [],
    List<TodoGroup> existingTodoGroups = const [],
    List<PomodoroTag> existingPomodoroTags = const [],
    List<TodoPlanBlock> existingPlanBlocks = const [],
    List<FixedScheduleItem> existingFixedSchedules = const [],
    Map<String, int> categoryReminderDefaults = const {},
    DateTime? now,
  }) {
    final newTodos = <TodoItem>[];
    final updatedTodos = <TodoItem>[];
    final newTimeLogs = <TimeLogItem>[];
    final updatedTimeLogs = <TimeLogItem>[];
    final pomodoroActions = <AiTodoAction>[];
    final newCountdowns = <CountdownItem>[];
    final updatedCountdowns = <CountdownItem>[];
    final newTodoGroups = <TodoGroup>[];
    final updatedTodoGroups = <TodoGroup>[];
    final newPomodoroTags = <PomodoroTag>[];
    final updatedPomodoroTags = <PomodoroTag>[];
    final newPlanBlocks = <TodoPlanBlock>[];
    final updatedPlanBlocks = <TodoPlanBlock>[];
    final newFixedSchedules = <FixedScheduleItem>[];
    final updatedFixedSchedules = <FixedScheduleItem>[];
    final newHabitActions = <AiTodoAction>[];
    final selectedActions = actions.where(
      (action) => action.isSelected && !action.isAdded && !action.isIgnored,
    );
    final createdAtFallback = now ?? DateTime.now();

    for (final action in selectedActions) {
      if (action.isFixedScheduleAction) {
        final schedules = _buildFixedSchedules(
          action,
          existingFixedSchedules: [
            ...existingFixedSchedules,
            ...newFixedSchedules,
            ...updatedFixedSchedules,
          ],
          now: createdAtFallback,
        );
        if (schedules.isNotEmpty) {
          final target = action.type == AiTodoActionType.createFixedSchedule
              ? newFixedSchedules
              : updatedFixedSchedules;
          for (final schedule in schedules) {
            final existingIndex =
                target.indexWhere((item) => item.id == schedule.id);
            if (existingIndex == -1) {
              target.add(schedule);
            } else {
              target[existingIndex] = schedule;
            }
          }
          action.isAdded = true;
        }
        continue;
      }

      if (action.isHabitAction) {
        if (_buildHabitCreationDraft(action) != null) {
          // 习惯需要异步写入 HabitRepository，先交给聊天确认卡保存，
          // 不在这个同步执行阶段提前标记 isAdded。
          newHabitActions.add(action);
        }
        continue;
      }

      if (action.isTimeLogAction) {
        final timeLog = _buildTimeLog(action, existingTimeLogs);
        if (timeLog != null) {
          if (action.type == AiTodoActionType.createTimeLog) {
            newTimeLogs.add(timeLog);
          } else {
            updatedTimeLogs.add(timeLog);
          }
          action.isAdded = true;
        }
        continue;
      }

      if (action.isPomodoroAction) {
        pomodoroActions.add(action);
        action.isAdded = true;
        continue;
      }

      if (action.isPlanBlockAction) {
        final block = _buildPlanBlock(
          action,
          existingTodos,
          existingPlanBlocks,
        );
        if (block != null) {
          if (action.type == AiTodoActionType.createPlanBlock) {
            newPlanBlocks.add(block);
          } else {
            updatedPlanBlocks.add(block);
          }
          action.isAdded = true;
        }
        continue;
      }

      if (action.isCountdownAction) {
        final countdown = _buildCountdown(action, existingCountdowns);
        if (countdown != null) {
          if (action.type == AiTodoActionType.createCountdown) {
            newCountdowns.add(countdown);
          } else {
            updatedCountdowns.add(countdown);
          }
          action.isAdded = true;
        }
        continue;
      }

      if (action.isTodoGroupAction) {
        final group = _buildTodoGroup(action, existingTodoGroups);
        if (group != null) {
          if (action.type == AiTodoActionType.createTodoGroup) {
            newTodoGroups.add(group);
          } else {
            updatedTodoGroups.add(group);
          }
          action.isAdded = true;
        }
        continue;
      }

      if (action.isPomodoroTagAction) {
        final tag = _buildPomodoroTag(action, existingPomodoroTags);
        if (tag != null) {
          if (action.type == AiTodoActionType.createPomodoroTag) {
            newPomodoroTags.add(tag);
          } else {
            updatedPomodoroTags.add(tag);
          }
          action.isAdded = true;
        }
        continue;
      }

      if (action.mutatesExistingItem) {
        final updates = _buildUpdatedTodos(action, existingTodos);
        if (updates.isNotEmpty) {
          for (final updated in updates) {
            final existingIndex =
                updatedTodos.indexWhere((todo) => todo.id == updated.id);
            if (existingIndex == -1) {
              updatedTodos.add(updated);
            } else {
              updatedTodos[existingIndex] = updated;
            }
          }
          action.isAdded = true;
        }
        continue;
      }

      final created = _buildNewTodo(
        action,
        categoryReminderDefaults,
        createdAtFallback,
      );
      if (created != null) {
        newTodos.add(created);
        action.isAdded = true;
      }
    }

    return AiTodoActionExecutionResult(
      newTodos: newTodos,
      updatedTodos: updatedTodos,
      newTimeLogs: newTimeLogs,
      updatedTimeLogs: updatedTimeLogs,
      pomodoroActions: pomodoroActions,
      newCountdowns: newCountdowns,
      updatedCountdowns: updatedCountdowns,
      newTodoGroups: newTodoGroups,
      updatedTodoGroups: updatedTodoGroups,
      newPomodoroTags: newPomodoroTags,
      updatedPomodoroTags: updatedPomodoroTags,
      newPlanBlocks: newPlanBlocks,
      updatedPlanBlocks: updatedPlanBlocks,
      newFixedSchedules: newFixedSchedules,
      updatedFixedSchedules: updatedFixedSchedules,
      newHabitActions: newHabitActions,
    );
  }

  /// 保存已经通过执行器校验的习惯创建动作。
  ///
  /// 习惯不是 TodoItem：这里写入真实的 HabitGoal 和首个规则版本；
  /// 完成一次型习惯在 HabitRepository 内按需创建并绑定循环待办系列。
  static Future<List<HabitGoal>> saveHabitActions({
    required String username,
    required List<AiTodoAction> actions,
  }) async {
    final created = <HabitGoal>[];
    for (final action in actions) {
      if (!action.isHabitAction ||
          !action.isSelected ||
          action.isAdded ||
          action.isIgnored) {
        continue;
      }
      final draft = _buildHabitCreationDraft(action);
      if (draft == null) continue;
      final goal = await HabitRepository.createGoal(
        name: draft.name,
        icon: draft.icon,
        sourceType: draft.sourceType,
        sourceIds: draft.sourceIds,
        rule: draft.rule,
        displayMode: draft.displayMode,
        defaultFocusMinutes: draft.defaultFocusMinutes,
        username: username,
      );
      action.isAdded = true;
      created.add(goal);
    }
    return created;
  }

  static _HabitCreationDraft? _buildHabitCreationDraft(
    AiTodoAction action,
  ) {
    final name = action.title?.trim();
    if (name == null || name.isEmpty) return null;

    final sourceType = _parseHabitSourceType(action);
    if (sourceType == null) return null;
    final periodType = _parseHabitPeriodType(action.habitPeriodType);
    if (periodType == null) return null;

    final weekdaysMask = action.weekdaysMask ??
        (periodType == HabitPeriodType.weekdays ? 31 : 127);
    if (weekdaysMask < 1 || weekdaysMask > 127) return null;
    final customIntervalDays = action.customIntervalDays;
    if (periodType == HabitPeriodType.custom &&
        (customIntervalDays == null || customIntervalDays < 1)) {
      return null;
    }

    final dayBoundaryMinute = action.dayBoundaryMinute ?? 0;
    if (dayBoundaryMinute < 0 || dayBoundaryMinute >= 1440) return null;

    var targetValue = 0.0;
    var unit = action.unit?.trim() ?? '';
    int? targetTimeMinute;
    var timeComparison = HabitTimeComparison.before;
    var defaultFocusMinutes = action.defaultFocusMinutes;
    final sourceIds = _cleanIds(
      sourceType == HabitSourceType.recurringTodo &&
              action.sourceIds.isEmpty &&
              action.recurrenceSeriesId?.trim().isNotEmpty == true
          ? [action.recurrenceSeriesId!]
          : action.sourceIds,
    );

    switch (sourceType) {
      case HabitSourceType.recurringTodo:
        targetValue = 1;
      case HabitSourceType.pomodoroTag:
        if (sourceIds.isEmpty) return null;
        final durationSeconds = _habitDurationSeconds(action);
        if (durationSeconds == null || durationSeconds < 1) return null;
        targetValue = durationSeconds.toDouble();
        unit = unit.isEmpty ? '分钟' : unit;
      case HabitSourceType.quantityCheckIn:
        final quantity = action.targetValue;
        if (quantity == null || !quantity.isFinite || quantity <= 0) {
          return null;
        }
        targetValue = quantity;
      case HabitSourceType.timeCheckIn:
        targetTimeMinute = action.targetTimeMinute;
        if (targetTimeMinute == null ||
            targetTimeMinute < 0 ||
            targetTimeMinute >= 1440) {
          return null;
        }
        timeComparison = _parseHabitTimeComparison(
              action.habitTimeComparison,
            ) ??
            HabitTimeComparison.before;
      case HabitSourceType.durationCheckIn:
        final durationSeconds = _habitDurationSeconds(action);
        if (durationSeconds == null || durationSeconds < 1) return null;
        targetValue = durationSeconds.toDouble();
        unit = unit.isEmpty ? '分钟' : unit;
    }

    if (sourceType != HabitSourceType.pomodoroTag &&
        sourceType != HabitSourceType.durationCheckIn) {
      defaultFocusMinutes = null;
    } else if (defaultFocusMinutes != null) {
      defaultFocusMinutes = defaultFocusMinutes.clamp(1, 240).toInt();
    }

    final tolerance = action.timeToleranceMinutes ?? 0;
    if (tolerance < 0) return null;
    final quickValues =
        action.quickValues.where((value) => value > 0).take(4).toList();
    final effectiveFromDate = _habitEffectiveFromDate(dayBoundaryMinute);
    final rule = HabitGoalRuleRevision(
      habitUuid: '',
      effectiveFromDate: effectiveFromDate,
      periodType: periodType,
      weekdaysMask: weekdaysMask,
      customIntervalDays: customIntervalDays,
      targetValue: targetValue,
      unit: unit,
      targetTimeMinute: targetTimeMinute,
      timeComparison: timeComparison,
      timeToleranceMinutes: tolerance,
      dayBoundaryMinute: dayBoundaryMinute,
      quickValues: quickValues,
      reminderPolicy: _parseHabitReminderPolicy(action),
    );

    return _HabitCreationDraft(
      name: name,
      icon: action.icon?.trim().isNotEmpty == true
          ? action.icon!.trim()
          : HabitRepository.defaultIconForName(name),
      sourceType: sourceType,
      sourceIds: sourceIds,
      rule: rule,
      displayMode: _parseHabitDisplayMode(action.habitDisplayMode) ??
          HabitDisplayMode.habitOnly,
      defaultFocusMinutes: defaultFocusMinutes,
    );
  }

  static HabitSourceType? _parseHabitSourceType(AiTodoAction action) {
    final raw = action.habitSourceType?.trim();
    if (raw != null && raw.isNotEmpty) {
      final index = int.tryParse(raw);
      if (index != null &&
          index >= 0 &&
          index < HabitSourceType.values.length) {
        return HabitSourceType.values[index];
      }
      switch (_normalizeHabitToken(raw)) {
        case 'recurringtodo':
        case 'completion':
        case 'completioncheckin':
        case '完成型':
        case '完成一次':
        case '循环待办':
          return HabitSourceType.recurringTodo;
        case 'pomodorotag':
        case '专注标签':
          return HabitSourceType.pomodoroTag;
        case 'quantitycheckin':
        case 'quantity':
        case 'amount':
        case '数量型':
        case '数量':
          return HabitSourceType.quantityCheckIn;
        case 'timecheckin':
        case 'timepoint':
        case '时间点型':
        case '时间点':
          return HabitSourceType.timeCheckIn;
        case 'durationcheckin':
        case 'duration':
        case '时长型':
        case '时长':
          return HabitSourceType.durationCheckIn;
        default:
          return null;
      }
    }
    if (action.targetTimeMinute != null) return HabitSourceType.timeCheckIn;
    if (action.durationMinutes != null) return HabitSourceType.durationCheckIn;
    if (action.targetValue != null) return HabitSourceType.quantityCheckIn;
    return HabitSourceType.recurringTodo;
  }

  static int? _habitDurationSeconds(AiTodoAction action) {
    final minutes = action.durationMinutes;
    if (minutes != null && minutes > 0) return minutes * 60;

    // 兼容模型把时长放进 targetValue 的写法，但只在单位明确时换算，
    // 避免把「30」误判成 30 秒还是 30 分钟。
    final value = action.targetValue;
    if (value == null || !value.isFinite || value <= 0) return null;
    final unit = action.unit?.trim().toLowerCase() ?? '';
    if (unit.contains('秒') || unit == 's' || unit.contains('sec')) {
      return value.round();
    }
    if (unit.contains('小时') || unit == 'h' || unit.contains('hour')) {
      return (value * 3600).round();
    }
    if (unit.contains('分钟') || unit == '分' || unit == 'min') {
      return (value * 60).round();
    }
    return null;
  }

  static HabitPeriodType? _parseHabitPeriodType(String? raw) {
    final value = raw?.trim();
    if (value == null || value.isEmpty) return HabitPeriodType.daily;
    final index = int.tryParse(value);
    if (index != null && index >= 0 && index < HabitPeriodType.values.length) {
      return HabitPeriodType.values[index];
    }
    switch (_normalizeHabitToken(value)) {
      case 'daily':
      case 'day':
      case '每天':
        return HabitPeriodType.daily;
      case 'weekly':
      case 'week':
      case '每周':
        return HabitPeriodType.weekly;
      case 'weekdays':
      case 'workdays':
      case '工作日':
      case '周一至周五':
        return HabitPeriodType.weekdays;
      case 'monthly':
      case 'month':
      case '每月':
        return HabitPeriodType.monthly;
      case 'custom':
      case 'customdays':
      case '自定义':
      case '每隔':
        return HabitPeriodType.custom;
      default:
        return null;
    }
  }

  static HabitTimeComparison? _parseHabitTimeComparison(String? raw) {
    final value = raw?.trim();
    if (value == null || value.isEmpty) return null;
    final index = int.tryParse(value);
    if (index != null &&
        index >= 0 &&
        index < HabitTimeComparison.values.length) {
      return HabitTimeComparison.values[index];
    }
    switch (_normalizeHabitToken(value)) {
      case 'before':
      case '早于':
      case '之前':
        return HabitTimeComparison.before;
      case 'after':
      case '晚于':
      case '之后':
        return HabitTimeComparison.after;
      default:
        return null;
    }
  }

  static HabitDisplayMode? _parseHabitDisplayMode(String? raw) {
    final value = raw?.trim();
    if (value == null || value.isEmpty) return null;
    final index = int.tryParse(value);
    if (index != null && index >= 0 && index < HabitDisplayMode.values.length) {
      return HabitDisplayMode.values[index];
    }
    switch (_normalizeHabitToken(value)) {
      case 'habitonly':
      case '仅习惯':
        return HabitDisplayMode.habitOnly;
      case 'todoonly':
      case '仅待办':
        return HabitDisplayMode.todoOnly;
      case 'both':
      case '两者':
        return HabitDisplayMode.both;
      default:
        return null;
    }
  }

  static HabitReminderPolicy _parseHabitReminderPolicy(
    AiTodoAction action,
  ) {
    final raw = action.habitReminderPolicy;
    final fixedTimes = _parseHabitMinuteList(
      raw?['fixedTimes'] ?? raw?['fixed_times'],
    );
    return HabitReminderPolicy(
      fixedTimes: fixedTimes,
      progressReminder: _parseHabitBool(
        raw?['progressReminder'] ?? raw?['progress_reminder'],
      ),
      nearEndReminder: _parseHabitBool(
        raw?['nearEndReminder'] ?? raw?['near_end_reminder'],
      ),
      dailySummaryReminder: _parseHabitBool(
        raw?['dailySummaryReminder'] ?? raw?['daily_summary_reminder'],
      ),
    );
  }

  static List<int> _parseHabitMinuteList(dynamic raw) {
    final values = raw is List
        ? raw
        : raw is String && raw.trim().isNotEmpty
            ? raw.split(RegExp(r'[,，\s]+'))
            : const <dynamic>[];
    return values
        .map(_parseHabitMinute)
        .whereType<int>()
        .where((value) => value >= 0 && value < 1440)
        .toSet()
        .toList()
      ..sort();
  }

  static int? _parseHabitMinute(dynamic raw) {
    final value = JsonValueParser.toNullableInt(raw);
    if (value != null) return value;
    final text = raw?.toString().trim();
    if (text == null) return null;
    final match = RegExp(r'^(\d{1,2}):(\d{1,2})$').firstMatch(text);
    if (match == null) return null;
    final hour = int.tryParse(match.group(1)!);
    final minute = int.tryParse(match.group(2)!);
    if (hour == null || minute == null || hour > 23 || minute > 59) {
      return null;
    }
    return hour * 60 + minute;
  }

  static bool _parseHabitBool(dynamic raw) {
    if (raw == true || raw == 1) return true;
    final value = raw?.toString().trim().toLowerCase();
    return value == 'true' || value == 'yes' || value == '1';
  }

  static List<String> _cleanIds(Iterable<String> ids) {
    return ids
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();
  }

  static String _normalizeHabitToken(String value) {
    return value.toLowerCase().replaceAll(RegExp(r'[\s_-]+'), '');
  }

  static String _habitEffectiveFromDate(int dayBoundaryMinute) {
    final logicalDate = HabitRuleResolver.logicalDateFor(
      DateTime.now(),
      dayBoundaryMinute,
    );
    return HabitRuleResolver.dayKey(logicalDate);
  }

  static List<FixedScheduleItem> _buildFixedSchedules(
    AiTodoAction action, {
    required List<FixedScheduleItem> existingFixedSchedules,
    required DateTime now,
  }) {
    if (action.type == AiTodoActionType.createFixedSchedule) {
      final template = _buildNewFixedSchedule(action, now);
      if (template == null) return const [];
      if (template.recurrence == RecurrenceType.none) return [template];

      final startDate = DateTime.tryParse(template.date);
      if (startDate == null) return const [];
      final recurrenceEnd = _parseExistingDate(action.recurrenceEndDate) ??
          FixedScheduleRecurrenceService.defaultEndDate(
            startDate: startDate,
            recurrence: template.recurrence,
            customIntervalDays: template.customIntervalDays ?? 1,
          );
      if (_day(recurrenceEnd).isBefore(_day(startDate))) return const [];
      try {
        return FixedScheduleRecurrenceService.rebuildSeries(
          template: template,
          existingSeries: const [],
          recurrence: template.recurrence,
          recurrenceEndDate: recurrenceEnd,
          customIntervalDays: template.customIntervalDays ?? 1,
        ).changes;
      } on FixedScheduleRecurrenceLimitException {
        return const [];
      }
    }

    final id = action.scheduleId;
    if (id == null || id.isEmpty) return const [];
    FixedScheduleItem? target;
    for (final candidate in existingFixedSchedules.reversed) {
      if (candidate.id == id) {
        target = candidate;
        break;
      }
    }
    if (target == null || target.isDeleted) return const [];
    final targetSeriesId = target.recurrenceSeriesId?.trim();
    if (action.recurrenceSeriesId?.trim().isNotEmpty == true &&
        action.recurrenceSeriesId!.trim() != targetSeriesId) {
      return const [];
    }

    // 重复规则描述的是从当前期开始的系列结构，不能在默认“仅本期”
    // 语义下静默重写整条日程系列。
    if (!action.appliesToFutureOccurrences &&
        (action.hasRecurrence ||
            action.hasCustomIntervalDays ||
            action.hasRecurrenceEndDate)) {
      return const [];
    }

    if (!action.appliesToFutureOccurrences ||
        targetSeriesId == null ||
        targetSeriesId.isEmpty) {
      final updated = _patchFixedSchedule(action, target);
      return updated == null ? const [] : [updated];
    }

    final targetDate = DateTime.tryParse(target.date);
    if (targetDate == null) return const [];
    final futureSeries = <FixedScheduleItem>[];
    final seenIds = <String>{};
    for (final candidate in existingFixedSchedules.reversed) {
      if (!seenIds.add(candidate.id) || candidate.isDeleted) continue;
      final candidateDate = DateTime.tryParse(candidate.date);
      if (candidate.recurrenceSeriesId == targetSeriesId &&
          candidateDate != null &&
          !candidateDate.isBefore(targetDate)) {
        futureSeries.add(candidate);
      }
    }
    futureSeries.sort((left, right) => left.date.compareTo(right.date));

    if (action.type == AiTodoActionType.cancelFixedSchedule ||
        action.type == AiTodoActionType.deleteFixedSchedule) {
      return futureSeries.map((item) {
        final copy = FixedScheduleItem.fromJson(item.toJson());
        if (action.type == AiTodoActionType.cancelFixedSchedule) {
          copy.status = FixedScheduleStatus.cancelled;
        } else {
          copy.isDeleted = true;
        }
        copy.markAsChanged();
        return copy;
      }).toList();
    }

    final patchedTarget = _patchFixedSchedule(action, target);
    if (patchedTarget == null) return const [];
    final rebuildsSeries = action.hasDate ||
        action.hasRecurrence ||
        action.hasCustomIntervalDays ||
        action.hasRecurrenceEndDate;
    if (rebuildsSeries) {
      final recurrence = patchedTarget.recurrence;
      final patchedDate = DateTime.tryParse(patchedTarget.date);
      if (patchedDate == null) return const [];
      final existingEnd = futureSeries
          .map((item) => DateTime.tryParse(item.date))
          .whereType<DateTime>()
          .fold<DateTime?>(
            null,
            (latest, date) =>
                latest == null || date.isAfter(latest) ? date : latest,
          );
      final recurrenceEnd = _parseExistingDate(action.recurrenceEndDate) ??
          existingEnd ??
          FixedScheduleRecurrenceService.defaultEndDate(
            startDate: patchedDate,
            recurrence: recurrence,
            customIntervalDays: patchedTarget.customIntervalDays ?? 1,
          );
      if (_day(recurrenceEnd).isBefore(_day(patchedDate))) return const [];
      try {
        return FixedScheduleRecurrenceService.rebuildSeries(
          template: patchedTarget,
          existingSeries: futureSeries,
          recurrence: recurrence,
          recurrenceEndDate: recurrenceEnd,
          customIntervalDays: patchedTarget.customIntervalDays ?? 1,
        ).changes;
      } on FixedScheduleRecurrenceLimitException {
        return const [];
      }
    }

    return futureSeries
        .map((item) {
          final propagated = AiTodoAction.fromJson(action.toJson())
            ..recurrenceScope = 'occurrence';
          final itemDate = DateTime.parse(item.date);
          if (action.hasStartTime && action.startTime != null) {
            propagated.startTime =
                _moveScheduleTimeToDate(action.startTime!, itemDate);
          }
          if (action.hasDueDate && action.dueDate != null) {
            propagated.dueDate = _moveScheduleTimeToDate(
              action.dueDate!,
              itemDate,
              anchorStart: action.startTime,
            );
          }
          return _patchFixedSchedule(propagated, item);
        })
        .whereType<FixedScheduleItem>()
        .toList();
  }

  static FixedScheduleItem? _buildNewFixedSchedule(
    AiTodoAction action,
    DateTime now,
  ) {
    final title = action.title?.trim();
    if (title == null || title.isEmpty) return null;
    final start = _parseExistingDate(action.startTime);
    final end = _parseExistingDate(action.dueDate) ??
        (start != null && action.durationMinutes != null
            ? start.add(Duration(minutes: action.durationMinutes!))
            : null);
    if (end != null && (start == null || !end.isAfter(start))) return null;
    final date =
        _parseScheduleDate(action.date) ?? (start == null ? null : _day(start));
    if (date == null) return null;
    final recurrence = _parseRecurrenceName(action.recurrence);
    if (recurrence == RecurrenceType.customDays &&
        (action.customIntervalDays == null || action.customIntervalDays! < 1)) {
      return null;
    }
    final reminders = action.hasReminderMinutesList
        ? action.reminderMinutesList
            .where((value) => value >= 0)
            .toSet()
            .toList()
        : action.hasReminderMinutes
            ? [if (action.reminderMinutes != null) action.reminderMinutes!]
            : const <int>[15];
    final item = FixedScheduleItem(
      title: title,
      date: _dateKey(date),
      startTime: start?.millisecondsSinceEpoch,
      endTime: end?.millisecondsSinceEpoch,
      status: _parseFixedScheduleStatus(action.status) ??
          FixedScheduleStatus.scheduled,
      source: FixedScheduleSource.ai,
      location: _nullableString(action.location),
      remark: _nullableString(action.remark),
      reminderMinutes: reminders,
      timezone: now.timeZoneName,
      recurrence: recurrence,
      customIntervalDays: recurrence == RecurrenceType.customDays
          ? action.customIntervalDays
          : null,
      relatedTodoIds: action.sourceTodoIds,
    );
    if (recurrence != RecurrenceType.none) {
      item.recurrenceSeriesId = item.id;
    }
    return item;
  }

  static FixedScheduleItem? _patchFixedSchedule(
    AiTodoAction action,
    FixedScheduleItem existing,
  ) {
    final updated = FixedScheduleItem.fromJson(existing.toJson());
    if (action.type == AiTodoActionType.deleteFixedSchedule) {
      updated.isDeleted = true;
      updated.markAsChanged();
      return updated;
    }
    if (action.type == AiTodoActionType.cancelFixedSchedule) {
      updated.status = FixedScheduleStatus.cancelled;
      updated.markAsChanged();
      return updated;
    }

    if (action.title?.trim().isNotEmpty == true) {
      updated.title = action.title!.trim();
    }
    if (action.hasRemark) updated.remark = _nullableString(action.remark);
    if (action.hasLocation) updated.location = _nullableString(action.location);
    if (action.hasReminderMinutesList) {
      updated.reminderMinutes = action.reminderMinutesList
          .where((value) => value >= 0)
          .toSet()
          .toList();
    } else if (action.hasReminderMinutes) {
      updated.reminderMinutes = [
        if (action.reminderMinutes != null) action.reminderMinutes!,
      ];
    }
    final parsedStatus = _parseFixedScheduleStatus(action.status);
    if (parsedStatus != null) updated.status = parsedStatus;

    final oldDate = DateTime.tryParse(existing.date);
    var nextDate = action.hasDate ? _parseScheduleDate(action.date) : oldDate;
    final suppliedStart =
        action.hasStartTime ? _parseExistingDate(action.startTime) : null;
    final suppliedEnd =
        action.hasDueDate ? _parseExistingDate(action.dueDate) : null;
    if (suppliedStart != null) nextDate = _day(suppliedStart);
    if (nextDate == null) return null;

    int? nextStart = existing.startTime;
    int? nextEnd = existing.endTime;
    if (action.hasStartTime) {
      nextStart = suppliedStart?.millisecondsSinceEpoch;
      if (suppliedStart == null) nextEnd = null;
    } else if (action.hasDate &&
        oldDate != null &&
        existing.startTime != null) {
      nextStart = _moveEpochToDate(existing.startTime!, nextDate);
    }
    if (action.hasDueDate) {
      nextEnd = suppliedEnd?.millisecondsSinceEpoch;
    } else if (action.durationMinutes != null && nextStart != null) {
      nextEnd = DateTime.fromMillisecondsSinceEpoch(nextStart)
          .add(Duration(minutes: action.durationMinutes!))
          .millisecondsSinceEpoch;
    } else if (action.hasDate && oldDate != null && existing.endTime != null) {
      nextEnd = _moveEpochToDate(existing.endTime!, nextDate);
    }
    if (nextEnd != null && (nextStart == null || nextEnd <= nextStart)) {
      return null;
    }
    updated
      ..date = _dateKey(nextDate)
      ..startTime = nextStart
      ..endTime = nextEnd;

    if (action.hasRecurrence) {
      updated.recurrence = _parseRecurrenceName(action.recurrence);
      updated.recurrenceSeriesId = updated.recurrence == RecurrenceType.none
          ? null
          : (updated.recurrenceSeriesId ?? updated.id);
    }
    if (updated.recurrence == RecurrenceType.customDays) {
      final interval = action.hasCustomIntervalDays
          ? action.customIntervalDays
          : updated.customIntervalDays;
      if (interval == null || interval < 1) return null;
      updated.customIntervalDays = interval;
    } else {
      updated.customIntervalDays = null;
    }
    updated.markAsChanged();
    return updated;
  }

  static FixedScheduleStatus? _parseFixedScheduleStatus(String? value) {
    return switch (value) {
      'scheduled' => FixedScheduleStatus.scheduled,
      'finished' => FixedScheduleStatus.finished,
      'cancelled' => FixedScheduleStatus.cancelled,
      _ => null,
    };
  }

  static DateTime? _parseScheduleDate(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final parsed = DateTime.tryParse(value.trim());
    return parsed == null ? null : _day(parsed);
  }

  static DateTime _day(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  static String _dateKey(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';

  static int _moveEpochToDate(int value, DateTime date) {
    final source = DateTime.fromMillisecondsSinceEpoch(value).toLocal();
    return DateTime(
      date.year,
      date.month,
      date.day,
      source.hour,
      source.minute,
      source.second,
      source.millisecond,
      source.microsecond,
    ).millisecondsSinceEpoch;
  }

  static String _moveScheduleTimeToDate(
    String value,
    DateTime date, {
    String? anchorStart,
  }) {
    final source = DateTime.parse(value).toLocal();
    var dayOffset = 0;
    if (anchorStart != null) {
      final anchor = DateTime.tryParse(anchorStart)?.toLocal();
      if (anchor != null) {
        dayOffset = _day(source).difference(_day(anchor)).inDays;
      }
    }
    return DateTime(
      date.year,
      date.month,
      date.day + dayOffset,
      source.hour,
      source.minute,
      source.second,
      source.millisecond,
      source.microsecond,
    ).toIso8601String();
  }

  static TodoPlanBlock? _buildPlanBlock(
    AiTodoAction action,
    List<Map<String, dynamic>> existingTodos,
    List<TodoPlanBlock> existingPlanBlocks,
  ) {
    if (action.type != AiTodoActionType.createPlanBlock) {
      final blockId = action.planBlockId;
      if (blockId == null || blockId.isEmpty) return null;
      TodoPlanBlock? existing;
      for (final block in existingPlanBlocks) {
        if (block.uuid == blockId) {
          existing = block;
          break;
        }
      }
      if (existing == null) return null;
      final updated = TodoPlanBlock.fromJson(existing.toJson());
      if (action.type == AiTodoActionType.deletePlanBlock) {
        updated.isDeleted = true;
      } else if (action.type == AiTodoActionType.skipPlanBlock) {
        updated.status = TodoPlanStatus.skipped;
      } else {
        if (action.todoId?.isNotEmpty == true) updated.todoId = action.todoId!;
        if (action.title?.trim().isNotEmpty == true) {
          updated.titleSnapshot = action.title!.trim();
        }
        final start = action.startTime != null
            ? DateTime.tryParse(action.startTime!)
            : null;
        final end = action.dueDate != null
            ? DateTime.tryParse(action.dueDate!)
            : (start != null && action.durationMinutes != null
                ? start.add(Duration(minutes: action.durationMinutes!))
                : null);
        if (start != null) updated.startTime = start.millisecondsSinceEpoch;
        if (end != null &&
            end.isAfter(
                DateTime.fromMillisecondsSinceEpoch(updated.startTime))) {
          updated.endTime = end.millisecondsSinceEpoch;
        }
        updated.plannedMinutes = max(
          1,
          DateTime.fromMillisecondsSinceEpoch(updated.endTime)
              .difference(
                  DateTime.fromMillisecondsSinceEpoch(updated.startTime))
              .inMinutes,
        );
        if (action.remark != null) updated.remark = action.remark;
        if (action.reminderMinutes != null) {
          updated.reminderMinutes = action.reminderMinutes!;
        }
      }
      updated.markAsChanged();
      return updated;
    }

    final todoId = action.todoId;
    if (todoId == null || todoId.isEmpty || action.startTime == null) {
      return null;
    }

    final start = DateTime.tryParse(action.startTime!);
    final end = action.dueDate != null
        ? DateTime.tryParse(action.dueDate!)
        : (start != null && action.durationMinutes != null
            ? start.add(Duration(minutes: action.durationMinutes!))
            : null);
    if (start == null || end == null || !end.isAfter(start)) return null;

    final match = existingTodos
        .where((todo) => todo['id']?.toString() == todoId)
        .toList();
    final title = action.title?.trim().isNotEmpty == true
        ? action.title!.trim()
        : (match.isNotEmpty ? match.first['title']?.toString() : null);
    final plannedMinutes =
        action.durationMinutes ?? end.difference(start).inMinutes;

    return TodoPlanBlock(
      todoId: todoId,
      titleSnapshot: title,
      startTime: start.millisecondsSinceEpoch,
      endTime: end.millisecondsSinceEpoch,
      plannedMinutes: plannedMinutes,
      source: TodoPlanSource.ai,
      remark: action.remark,
      reminderMinutes: action.reminderMinutes ?? 5,
    )..markAsChanged();
  }

  static TodoGroup? _buildTodoGroup(
    AiTodoAction action,
    List<TodoGroup> existingGroups,
  ) {
    TodoGroup? existing;
    if (action.todoId != null) {
      for (final group in existingGroups) {
        if (group.id == action.todoId) {
          existing = group;
          break;
        }
      }
    }
    if (action.type != AiTodoActionType.createTodoGroup && existing == null) {
      return null;
    }
    if (action.type == AiTodoActionType.deleteTodoGroup) {
      return TodoGroup(
        id: existing!.id,
        name: existing.name,
        isExpanded: existing.isExpanded,
        isDeleted: true,
        version: existing.version,
        updatedAt: existing.updatedAt,
        createdAt: existing.createdAt,
        teamUuid: existing.teamUuid,
        teamName: existing.teamName,
        creatorId: existing.creatorId,
        creatorName: existing.creatorName,
        hasConflict: existing.hasConflict,
        conflictData: existing.conflictData,
      )..markAsChanged();
    }

    final name = action.title ?? existing?.name;
    if (name == null || name.trim().isEmpty) return null;
    final group = TodoGroup(
      id: existing?.id,
      name: name.trim(),
      isExpanded: existing?.isExpanded ?? false,
      isDeleted: existing?.isDeleted ?? false,
      version: existing?.version ?? 1,
      updatedAt: existing?.updatedAt,
      createdAt: existing?.createdAt,
      teamUuid: existing?.teamUuid,
      teamName: existing?.teamName,
      creatorId: existing?.creatorId,
      creatorName: existing?.creatorName,
      hasConflict: existing?.hasConflict ?? false,
      conflictData: existing?.conflictData,
    );
    if (existing != null) group.markAsChanged();
    return group;
  }

  static CountdownItem? _buildCountdown(
    AiTodoAction action,
    List<CountdownItem> existingCountdowns,
  ) {
    CountdownItem? existing;
    if (action.todoId != null) {
      for (final countdown in existingCountdowns) {
        if (countdown.id == action.todoId) {
          existing = countdown;
          break;
        }
      }
    }
    if (action.type != AiTodoActionType.createCountdown && existing == null) {
      return null;
    }
    if (action.type == AiTodoActionType.deleteCountdown) {
      return CountdownItem(
        id: existing!.id,
        title: existing.title,
        targetDate: existing.targetDate,
        isDeleted: true,
        isCompleted: existing.isCompleted,
        version: existing.version,
        createdAt: existing.createdAt,
        teamUuid: existing.teamUuid,
        teamName: existing.teamName,
        creatorId: existing.creatorId,
        creatorName: existing.creatorName,
      )..markAsChanged();
    }

    final target = action.dueDate != null
        ? DateTime.tryParse(action.dueDate!)
        : action.startTime != null
            ? DateTime.tryParse(action.startTime!)
            : existing?.targetDate;
    if (target == null) return null;

    final countdown = CountdownItem(
      id: existing?.id,
      title: action.title ?? existing?.title ?? '倒计时',
      targetDate: target,
      isDeleted: existing?.isDeleted ?? false,
      isCompleted: action.type == AiTodoActionType.completeCountdown
          ? true
          : existing?.isCompleted ?? false,
      version: existing?.version ?? 1,
      createdAt: existing?.createdAt,
      teamUuid: existing?.teamUuid,
      teamName: existing?.teamName,
      creatorId: existing?.creatorId,
      creatorName: existing?.creatorName,
    );
    if (existing != null) countdown.markAsChanged();
    return countdown;
  }

  static PomodoroTag? _buildPomodoroTag(
    AiTodoAction action,
    List<PomodoroTag> existingTags,
  ) {
    PomodoroTag? existing;
    if (action.todoId != null) {
      for (final tag in existingTags) {
        if (tag.uuid == action.todoId) {
          existing = tag;
          break;
        }
      }
    }
    if (action.type != AiTodoActionType.createPomodoroTag && existing == null) {
      return null;
    }
    if (action.type == AiTodoActionType.deletePomodoroTag) {
      return PomodoroTag(
        uuid: existing!.uuid,
        name: existing.name,
        color: existing.color,
        isDeleted: true,
        version: existing.version,
        createdAt: existing.createdAt,
      )..updatedAt = DateTime.now().millisecondsSinceEpoch;
    }

    final name = action.title ?? existing?.name;
    if (name == null || name.trim().isEmpty) return null;
    final tag = PomodoroTag(
      uuid: existing?.uuid,
      name: name.trim(),
      color: action.color ?? existing?.color ?? '#607D8B',
      isDeleted: existing?.isDeleted ?? false,
      version: existing?.version ?? 1,
      createdAt: existing?.createdAt,
    );
    if (existing != null) {
      tag.version = existing.version + 1;
      tag.updatedAt = DateTime.now().millisecondsSinceEpoch;
    }
    return tag;
  }

  static TimeLogItem? _buildTimeLog(
    AiTodoAction action,
    List<TimeLogItem> existingTimeLogs,
  ) {
    TimeLogItem? existing;
    if (action.todoId != null) {
      for (final log in existingTimeLogs) {
        if (log.id == action.todoId) {
          existing = log;
          break;
        }
      }
    }

    if (action.type != AiTodoActionType.createTimeLog && existing == null) {
      return null;
    }

    if (action.type == AiTodoActionType.deleteTimeLog) {
      return TimeLogItem(
        id: existing!.id,
        title: existing.title,
        tagUuids: existing.tagUuids,
        startTime: existing.startTime,
        endTime: existing.endTime,
        remark: existing.remark,
        version: existing.version,
        createdAt: existing.createdAt,
        isDeleted: true,
        deviceId: existing.deviceId,
        teamUuid: existing.teamUuid,
      )..markAsChanged();
    }

    final start = action.startTime != null
        ? DateTime.tryParse(action.startTime!)
        : (existing != null
            ? DateTime.fromMillisecondsSinceEpoch(existing.startTime)
            : null);
    final end = action.dueDate != null
        ? DateTime.tryParse(action.dueDate!)
        : (start != null && action.durationMinutes != null
            ? start.add(Duration(minutes: action.durationMinutes!))
            : (existing != null
                ? DateTime.fromMillisecondsSinceEpoch(existing.endTime)
                : null));
    if (start == null || end == null || !end.isAfter(start)) return null;

    final log = TimeLogItem(
      id: existing?.id,
      title: action.title ?? existing?.title ?? '专注记录',
      tagUuids: action.tagUuids.isNotEmpty
          ? action.tagUuids
          : existing?.tagUuids ?? [],
      startTime: start.millisecondsSinceEpoch,
      endTime: end.millisecondsSinceEpoch,
      remark: action.remark ?? existing?.remark,
      version: existing?.version ?? 1,
      createdAt: existing?.createdAt,
      isDeleted: existing?.isDeleted ?? false,
      deviceId: existing?.deviceId,
      teamUuid: existing?.teamUuid,
    );
    if (existing != null) log.markAsChanged();
    return log;
  }

  static List<TodoItem> _buildUpdatedTodos(
    AiTodoAction action,
    List<Map<String, dynamic>> existingTodos,
  ) {
    final id = action.todoId;
    if (id == null || id.isEmpty) return const [];
    final target = existingTodos.where((todo) => todo['id'] == id).firstOrNull;
    if (target == null) return const [];

    final seriesId = _nullableString(
        target['recurrenceSeriesId'] ?? target['recurrence_series_id']);
    if (action.recurrenceSeriesId?.trim().isNotEmpty == true &&
        action.recurrenceSeriesId!.trim() != seriesId) {
      return const [];
    }

    final targetUpdate = _buildUpdatedTodo(action, target);
    if (targetUpdate == null) return const [];
    final updates = <TodoItem>[targetUpdate];

    // 完成只属于一个真实期次。即使模型误给 future，也不能把尚未发生的
    // 周期批量标记完成。
    if (!action.appliesToFutureOccurrences ||
        seriesId == null ||
        action.type == AiTodoActionType.completeTodo) {
      return updates;
    }

    final targetStart = _todoStart(target);
    final updatedStart = targetUpdate.createdDate == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(
            targetUpdate.createdDate!,
            isUtc: true,
          ).toLocal();
    final shift = targetStart == null || updatedStart == null
        ? Duration.zero
        : updatedStart.difference(targetStart);
    final updatedDuration = updatedStart == null || targetUpdate.dueDate == null
        ? null
        : targetUpdate.dueDate!.difference(updatedStart);
    final hasTimePatch = action.hasStartTime ||
        action.hasDueDate ||
        action.hasTimeMode ||
        action.hasIsAllDay;
    final recurrenceEnd = action.hasRecurrenceEndDate
        ? _parseExistingDate(action.recurrenceEndDate)
        : targetUpdate.recurrenceEndDate;

    final future = existingTodos.where((todo) {
      if (todo['id'] == id || _mapBool(todo, 'isDeleted')) return false;
      final candidateSeries = _nullableString(
          todo['recurrenceSeriesId'] ?? todo['recurrence_series_id']);
      final candidateStart = _todoStart(todo);
      return candidateSeries == seriesId &&
          candidateStart != null &&
          targetStart != null &&
          !candidateStart.isBefore(targetStart);
    }).toList()
      ..sort((a, b) => _todoStart(a)!.compareTo(_todoStart(b)!));

    for (final candidate in future) {
      final candidateAction = AiTodoAction.fromJson(action.toJson())
        ..todoId = candidate['id']?.toString()
        ..recurrenceScope = 'occurrence';
      final candidateStart = _todoStart(candidate)!;

      if (hasTimePatch) {
        if (targetUpdate.timeMode == TodoTimeMode.unscheduled) {
          candidateAction
            ..startTime = null
            ..dueDate = null
            ..timeMode = TodoTimeMode.unscheduled.name
            ..isAllDay = false
            ..hasStartTime = true
            ..hasDueDate = true
            ..hasTimeMode = true
            ..hasIsAllDay = true;
        } else {
          final shiftedStart = candidateStart.add(shift);
          candidateAction
            ..startTime = shiftedStart.toIso8601String()
            ..dueDate = updatedDuration == null
                ? shiftedStart.toIso8601String()
                : shiftedStart.add(updatedDuration).toIso8601String()
            ..timeMode = targetUpdate.timeMode.name
            ..isAllDay = targetUpdate.isDateOnly
            ..hasStartTime = true
            ..hasDueDate = true
            ..hasTimeMode = true
            ..hasIsAllDay = true;
        }
      }

      // 一个系列只能有一个规则锚点。新规则挂在目标期次上，之后已经生成
      // 的实例仍是 recurrence=none，但会同步其他规则元数据。
      if (action.hasRecurrence && action.recurrence != 'none') {
        candidateAction
          ..recurrence = 'none'
          ..hasRecurrence =
              _existingRecurrence(candidate) != RecurrenceType.none;
      }

      final shiftedCandidateDay = candidateStart.add(shift);
      final isPastRecurrenceEnd = recurrenceEnd != null &&
          DateTime(
            shiftedCandidateDay.year,
            shiftedCandidateDay.month,
            shiftedCandidateDay.day,
          ).isAfter(DateTime(
            recurrenceEnd.year,
            recurrenceEnd.month,
            recurrenceEnd.day,
          ));
      final shouldDelete = action.type == AiTodoActionType.deleteTodo ||
          (action.hasRecurrence && action.recurrence == 'none') ||
          isPastRecurrenceEnd;
      final updated = _buildUpdatedTodo(candidateAction, candidate);
      if (updated == null) continue;
      if (shouldDelete) {
        updated
          ..isDeleted = true
          ..recurrence = RecurrenceType.none;
      }
      updates.add(updated);
    }
    return updates;
  }

  static TodoItem? _buildUpdatedTodo(
    AiTodoAction action,
    Map<String, dynamic> existing,
  ) {
    final id = action.todoId;
    if (id == null || id.isEmpty) return null;

    final existingStart = _todoStart(existing);
    final existingDue = _todoDue(existing);
    final hasTimePatch = action.hasStartTime ||
        action.hasDueDate ||
        action.hasTimeMode ||
        action.hasIsAllDay;
    final normalizedTime = hasTimePatch
        ? _normalizeActionTime(
            action,
            existingStart: existingStart,
            existingDue: existingDue,
            existingMode: _existingTimeMode(existing),
          )
        : (
            start: existingStart,
            due: existingDue,
            isDateOnly: _existingTimeMode(existing) == TodoTimeMode.dateOnly,
          );

    final existingGroupId = _nullableString(existing['groupId']);
    final nextGroupId =
        action.type == AiTodoActionType.categorizeTodo || action.hasGroupId
            ? _nullableString(action.groupId)
            : existingGroupId;
    final existingRecurrence = _existingRecurrence(existing);
    final nextRecurrence = action.hasRecurrence
        ? _parseRecurrenceName(action.recurrence)
        : existingRecurrence;
    final existingCustomInterval = _parseNullableInt(
      existing['customIntervalDays'] ?? existing['custom_interval_days'],
    );
    final nextCustomInterval = action.hasCustomIntervalDays
        ? action.customIntervalDays
        : existingCustomInterval;
    final nextRecurrenceEnd = action.hasRecurrenceEndDate
        ? _parseExistingDate(action.recurrenceEndDate)
        : _parseExistingDate(
            existing['recurrenceEndDate'] ?? existing['recurrence_end_date'],
          );
    var recurrenceSeriesId = _nullableString(
        existing['recurrenceSeriesId'] ?? existing['recurrence_series_id']);
    if (nextRecurrence != RecurrenceType.none && recurrenceSeriesId == null) {
      recurrenceSeriesId = id;
    }

    final updated = TodoItem(
      id: id,
      title: action.title ?? existing['title']?.toString() ?? '',
      groupId: nextGroupId,
      isDone: action.type == AiTodoActionType.completeTodo
          ? true
          : _mapBool(existing, 'isDone'),
      isDeleted: action.type == AiTodoActionType.deleteTodo
          ? true
          : _mapBool(existing, 'isDeleted'),
      version: _parseNullableInt(existing['version']) ?? 1,
      updatedAt: _parseNullableInt(existing['updatedAt']),
      createdAt: _parseNullableInt(existing['createdAt']),
      remark: action.hasRemark ? action.remark : existing['remark']?.toString(),
      dueDate: normalizedTime.due,
      createdDate: normalizedTime.start?.toUtc().millisecondsSinceEpoch,
      recurrence: nextRecurrence,
      recurrenceSeriesId: recurrenceSeriesId,
      customIntervalDays: nextRecurrence == RecurrenceType.customDays
          ? nextCustomInterval
          : null,
      recurrenceEndDate: nextRecurrence == RecurrenceType.none &&
              action.hasRecurrence &&
              action.recurrence == 'none' &&
              !action.hasRecurrenceEndDate
          ? existingStart
          : nextRecurrenceEnd,
      isAllDay: normalizedTime.isDateOnly,
      reminderMinutes: action.hasReminderMinutes
          ? action.reminderMinutes
          : _parseNullableInt(existing['reminderMinutes']),
      imagePath: _nullableString(existing['imagePath']),
      originalText: _nullableString(existing['originalText']),
      teamUuid: _nullableString(existing['teamUuid']),
      creatorId: _nullableString(existing['creatorId']),
      creatorName: _nullableString(existing['creatorName']),
      teamName: _nullableString(existing['teamName']),
      collabType: _parseNullableInt(existing['collabType']) ?? 0,
      hasConflict: _mapBool(existing, 'hasConflict'),
      serverVersionData: existing['serverVersionData'] is Map
          ? Map<String, dynamic>.from(existing['serverVersionData'] as Map)
          : null,
      categoryId: _nullableString(existing['categoryId']),
    );
    updated.markAsChanged();
    return updated;
  }

  static TodoItem? _buildNewTodo(
    AiTodoAction action,
    Map<String, int> categoryReminderDefaults,
    DateTime now,
  ) {
    final normalizedTime = _normalizeActionTime(action);
    final recurrence = _parseRecurrenceName(action.recurrence);
    final recurrenceEndDate = _parseExistingDate(action.recurrenceEndDate);
    if (recurrence != RecurrenceType.none && normalizedTime.start == null) {
      return null;
    }
    if (recurrence == RecurrenceType.customDays &&
        (action.customIntervalDays == null ||
            action.customIntervalDays! <= 0)) {
      return null;
    }
    if (recurrenceEndDate != null &&
        normalizedTime.start != null &&
        DateTime(
          recurrenceEndDate.year,
          recurrenceEndDate.month,
          recurrenceEndDate.day,
        ).isBefore(DateTime(
          normalizedTime.start!.year,
          normalizedTime.start!.month,
          normalizedTime.start!.day,
        ))) {
      return null;
    }
    final gId = action.groupId;
    final todo = TodoItem(
      title: action.title ?? '未命名待办',
      remark: _buildRemark(action),
      dueDate: normalizedTime.due,
      createdDate: normalizedTime.start?.toUtc().millisecondsSinceEpoch,
      createdAt: now.millisecondsSinceEpoch,
      recurrence: recurrence,
      customIntervalDays: recurrence == RecurrenceType.customDays
          ? action.customIntervalDays
          : null,
      recurrenceEndDate: recurrenceEndDate,
      originalText: action.originalText,
      groupId: (gId == null || gId.isEmpty) ? null : gId,
      isAllDay: normalizedTime.isDateOnly,
      reminderMinutes: action.reminderMinutes ??
          (gId != null ? categoryReminderDefaults[gId] : null),
    );
    if (recurrence != RecurrenceType.none) {
      todo.recurrenceSeriesId = todo.id;
    }
    return todo;
  }

  static String? _buildRemark(AiTodoAction action) {
    final sourcePrefix = action.sourceTodoIds.isEmpty
        ? null
        : '来源待办: ${action.sourceTodoIds.join(', ')}';
    if (sourcePrefix == null) return action.remark;
    if (action.remark == null || action.remark!.isEmpty) return sourcePrefix;
    return '${action.remark}\n$sourcePrefix';
  }

  static ({DateTime? start, DateTime? due, bool isDateOnly})
      _normalizeActionTime(
    AiTodoAction action, {
    DateTime? existingStart,
    DateTime? existingDue,
    TodoTimeMode existingMode = TodoTimeMode.unscheduled,
  }) {
    final requestedMode = TodoTimeMode.values.firstWhere(
      (mode) => mode.name == action.timeMode,
      orElse: () {
        if (action.hasIsAllDay) {
          return action.isAllDay
              ? TodoTimeMode.dateOnly
              : (action.hasDueDate || action.hasStartTime
                  ? TodoTimeMode.deadline
                  : TodoTimeMode.unscheduled);
        }
        if (action.isAllDay) return TodoTimeMode.dateOnly;
        if (action.dueDate != null || action.startTime != null) {
          return TodoTimeMode.deadline;
        }
        return existingMode;
      },
    );
    if (requestedMode == TodoTimeMode.unscheduled) {
      return (start: null, due: null, isDateOnly: false);
    }

    final suppliedStart = action.hasStartTime
        ? _parseExistingDate(action.startTime)
        : existingStart;
    final suppliedDue =
        action.hasDueDate ? _parseExistingDate(action.dueDate) : existingDue;
    if (requestedMode == TodoTimeMode.dateOnly) {
      final normalized = TodoItem.normalizeTimeForWrite(
        selectedDate: suppliedStart ?? suppliedDue,
        dueDate: suppliedDue,
        isDateOnly: true,
      );
      return (
        start: normalized.start,
        due: normalized.due,
        isDateOnly: true,
      );
    }

    // 新版 TodoItem 不再写入执行时间段。即使兼容输入同时给了
    // startTime/endTime，待办本体也只保留 dueDate 截止点。
    final deadline = suppliedDue ?? suppliedStart;
    final normalized = TodoItem.normalizeTimeForWrite(
      dueDate: deadline,
      isDateOnly: false,
    );
    return (
      start: normalized.start,
      due: normalized.due,
      isDateOnly: false,
    );
  }

  static RecurrenceType _parseRecurrenceName(String recurrence) {
    return RecurrenceType.values.firstWhere(
      (value) => value.name == recurrence,
      orElse: () => RecurrenceType.none,
    );
  }

  static RecurrenceType _existingRecurrence(Map<String, dynamic> existing) {
    final value = existing['recurrence'];
    if (value is int && value >= 0 && value < RecurrenceType.values.length) {
      return RecurrenceType.values[value];
    }
    return _parseRecurrenceName(value?.toString() ?? 'none');
  }

  static TodoTimeMode _existingTimeMode(Map<String, dynamic> existing) {
    final value = existing['timeMode']?.toString();
    if (value != null) {
      return TodoTimeMode.values.firstWhere(
        (mode) => mode.name == value,
        orElse: () => TodoTimeMode.unscheduled,
      );
    }
    if (_mapBool(existing, 'isAllDay')) return TodoTimeMode.dateOnly;
    return _todoDue(existing) == null
        ? TodoTimeMode.unscheduled
        : TodoTimeMode.deadline;
  }

  static DateTime? _todoStart(Map<String, dynamic> todo) =>
      _parseExistingDate(todo['startTime'] ??
          todo['start_time'] ??
          todo['createdDate'] ??
          todo['created_date']);

  static DateTime? _todoDue(Map<String, dynamic> todo) => _parseExistingDate(
        todo['endTime'] ??
            todo['end_time'] ??
            todo['dueDate'] ??
            todo['due_date'],
      );

  static bool _mapBool(Map<String, dynamic> map, String key) {
    final value = map[key];
    return value == true || value == 1 || value?.toString() == '1';
  }

  static String? _nullableString(dynamic value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? null : text;
  }

  static int? _parseNullableInt(dynamic value) {
    return JsonValueParser.toNullableInt(value);
  }

  static DateTime? _parseExistingDate(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value.toLocal();
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
    if (value is num) return DateTime.fromMillisecondsSinceEpoch(value.toInt());
    return DateTime.tryParse(value.toString());
  }

  static List<TodoItem> mergeTodoUpdates(
    List<TodoItem> base,
    List<TodoItem> inserted,
    List<TodoItem> updated,
  ) {
    final result = List<TodoItem>.from(base)..addAll(inserted);
    for (final update in updated) {
      final idx = result.indexWhere((todo) => todo.id == update.id);
      if (idx == -1) {
        result.add(update);
      } else {
        result[idx] = _mergeTodo(result[idx], update);
      }
    }
    return result;
  }

  static List<TimeLogItem> mergeTimeLogUpdates(
    List<TimeLogItem> base,
    List<TimeLogItem> inserted,
    List<TimeLogItem> updated,
  ) {
    final result = List<TimeLogItem>.from(base)..addAll(inserted);
    for (final update in updated) {
      final idx = result.indexWhere((log) => log.id == update.id);
      if (idx == -1) {
        result.add(update);
      } else {
        result[idx] = update;
      }
    }
    return result;
  }

  static List<FixedScheduleItem> mergeFixedScheduleUpdates(
    List<FixedScheduleItem> base,
    List<FixedScheduleItem> inserted,
    List<FixedScheduleItem> updated,
  ) {
    final result = List<FixedScheduleItem>.from(base);
    for (final item in [...inserted, ...updated]) {
      final idx = result.indexWhere((existing) => existing.id == item.id);
      if (idx == -1) {
        result.add(item);
      } else {
        result[idx] = item;
      }
    }
    return result;
  }

  static List<CountdownItem> mergeCountdownUpdates(
    List<CountdownItem> base,
    List<CountdownItem> inserted,
    List<CountdownItem> updated,
  ) {
    final result = List<CountdownItem>.from(base)..addAll(inserted);
    for (final update in updated) {
      final idx = result.indexWhere((countdown) => countdown.id == update.id);
      if (idx == -1) {
        result.add(update);
      } else {
        result[idx] = update;
      }
    }
    return result;
  }

  static List<PomodoroTag> mergePomodoroTagUpdates(
    List<PomodoroTag> base,
    List<PomodoroTag> inserted,
    List<PomodoroTag> updated,
  ) {
    final result = List<PomodoroTag>.from(base)..addAll(inserted);
    for (final update in updated) {
      final idx = result.indexWhere((tag) => tag.uuid == update.uuid);
      if (idx == -1) {
        result.add(update);
      } else {
        result[idx] = update;
      }
    }
    return result;
  }

  static List<TodoGroup> mergeTodoGroupUpdates(
    List<TodoGroup> base,
    List<TodoGroup> inserted,
    List<TodoGroup> updated,
  ) {
    final result = List<TodoGroup>.from(base)..addAll(inserted);
    for (final update in updated) {
      final idx = result.indexWhere((group) => group.id == update.id);
      if (idx == -1) {
        result.add(update);
      } else {
        result[idx] = update;
      }
    }
    return result;
  }

  static TodoItem _mergeTodo(TodoItem existing, TodoItem update) {
    return TodoItem(
      id: existing.id,
      title: update.title,
      isDone: update.isDone,
      isDeleted: update.isDeleted,
      version: update.version,
      updatedAt: update.updatedAt,
      createdAt: existing.createdAt,
      createdDate: update.createdDate,
      recurrence: update.recurrence,
      recurrenceSeriesId:
          update.recurrenceSeriesId ?? existing.recurrenceSeriesId,
      customIntervalDays: update.customIntervalDays,
      recurrenceEndDate: update.recurrenceEndDate,
      dueDate: update.dueDate,
      remark: update.remark,
      imagePath: update.imagePath ?? existing.imagePath,
      originalText: update.originalText ?? existing.originalText,
      groupId: update.groupId,
      reminderMinutes: update.reminderMinutes,
      teamUuid: update.teamUuid ?? existing.teamUuid,
      creatorId: update.creatorId ?? existing.creatorId,
      creatorName: update.creatorName ?? existing.creatorName,
      teamName: update.teamName ?? existing.teamName,
      collabType: update.collabType,
      hasConflict: update.hasConflict,
      serverVersionData: update.serverVersionData,
      isAllDay: update.isAllDay,
      categoryId: update.categoryId ?? existing.categoryId,
    );
  }
}
