import 'dart:math';

import '../features/habits/models/habit_goal.dart';
import '../features/habits/models/habit_goal_rule.dart';
import '../features/habits/repositories/habit_repository.dart';
import '../features/habits/services/habit_rule_resolver.dart';
import '../models.dart';
import '../models/ai_todo_action.dart';
import 'todo_recurrence_series_edit_service.dart';
import 'fixed_schedule_recurrence_service.dart';
import 'pomodoro_service.dart';
import '../utils/json_value_parser.dart';
import '../utils/calendar_date_math.dart';
import '../utils/text_utils.dart';

part 'ai_action_executor/ai_todo_action_executor_main.dart';
part 'ai_action_executor/ai_todo_action_executor_habits.dart';
part 'ai_action_executor/ai_todo_action_executor_schedules_and_entities.dart';
part 'ai_action_executor/ai_todo_action_executor_todos.dart';

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

enum AiTodoActionWriteGroup {
  newTodos,
  updatedTodos,
  timeLogs,
  countdowns,
  todoGroups,
  pomodoroTags,
  newPlanBlocks,
  updatedPlanBlocks,
  fixedSchedules,
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
    this.actionsByWriteGroup = const {},
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
  final Map<AiTodoActionWriteGroup, List<AiTodoAction>> actionsByWriteGroup;

  List<AiTodoAction> actionsForWriteGroup(AiTodoActionWriteGroup group) =>
      actionsByWriteGroup[group] ?? const [];

  void markWriteGroupAdded(AiTodoActionWriteGroup group) {
    for (final action in actionsForWriteGroup(group)) {
      action.isAdded = true;
    }
  }

  bool get hasNonPomodoroChanges =>
      newTodos.isNotEmpty ||
      updatedTodos.isNotEmpty ||
      newTimeLogs.isNotEmpty ||
      updatedTimeLogs.isNotEmpty ||
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

  bool get hasChanges => hasNonPomodoroChanges || pomodoroActions.isNotEmpty;
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
  }) => _executeAiTodoActions(
    actions: actions,
    existingTodos: existingTodos,
    existingTimeLogs: existingTimeLogs,
    existingCountdowns: existingCountdowns,
    existingTodoGroups: existingTodoGroups,
    existingPomodoroTags: existingPomodoroTags,
    existingPlanBlocks: existingPlanBlocks,
    existingFixedSchedules: existingFixedSchedules,
    categoryReminderDefaults: categoryReminderDefaults,
    now: now,
  );

  /// 执行已经通过校验并由用户确认的习惯操作。
  ///
  /// 习惯不是 TodoItem：这里通过 HabitRepository 创建、更新或软删除目标，
  /// 规则更新保留历史版本；完成一次型习惯在仓库内按需绑定循环待办系列。
  static Future<List<HabitGoal>> saveHabitActions({
    required String username,
    required List<AiTodoAction> actions,
    Future<void> Function()? onActionSaved,
  }) => _saveHabitActions(
    username: username,
    actions: actions,
    onActionSaved: onActionSaved,
  );

  static List<TodoItem> mergeTodoUpdates(
    List<TodoItem> base,
    List<TodoItem> inserted,
    List<TodoItem> updated,
  ) => _mergeTodoUpdates(base, inserted, updated);

  static List<TimeLogItem> mergeTimeLogUpdates(
    List<TimeLogItem> base,
    List<TimeLogItem> inserted,
    List<TimeLogItem> updated,
  ) => _mergeTimeLogUpdates(base, inserted, updated);

  static List<FixedScheduleItem> mergeFixedScheduleUpdates(
    List<FixedScheduleItem> base,
    List<FixedScheduleItem> inserted,
    List<FixedScheduleItem> updated,
  ) => _mergeFixedScheduleUpdates(base, inserted, updated);

  static List<CountdownItem> mergeCountdownUpdates(
    List<CountdownItem> base,
    List<CountdownItem> inserted,
    List<CountdownItem> updated,
  ) => _mergeCountdownUpdates(base, inserted, updated);

  static List<PomodoroTag> mergePomodoroTagUpdates(
    List<PomodoroTag> base,
    List<PomodoroTag> inserted,
    List<PomodoroTag> updated,
  ) => _mergePomodoroTagUpdates(base, inserted, updated);

  static List<TodoGroup> mergeTodoGroupUpdates(
    List<TodoGroup> base,
    List<TodoGroup> inserted,
    List<TodoGroup> updated,
  ) => _mergeTodoGroupUpdates(base, inserted, updated);
}
