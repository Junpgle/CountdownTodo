part of '../ai_todo_action_executor.dart';

AiTodoActionExecutionResult _executeAiTodoActions({
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
  final actionsByWriteGroup = <AiTodoActionWriteGroup, List<AiTodoAction>>{};
  Map<String, int>? newFixedScheduleIndexById;
  Map<String, int>? updatedFixedScheduleIndexById;
  Map<String, int>? updatedTodoIndexById;
  Set<String>? existingTodoGroupIds;
  void registerWrite(AiTodoActionWriteGroup group, AiTodoAction action) {
    (actionsByWriteGroup[group] ??= <AiTodoAction>[]).add(action);
  }

  final selectedActions = actions.where(
    (action) => action.isSelected && !action.isAdded && !action.isIgnored,
  );
  final createdAtFallback = now ?? DateTime.now();

  for (final action in selectedActions) {
    if (action.isFixedScheduleAction) {
      final isCreate = action.type == AiTodoActionType.createFixedSchedule;
      final schedules = _buildFixedSchedules(
        action,
        existingFixedSchedules: isCreate
            ? const <FixedScheduleItem>[]
            : [
                ...existingFixedSchedules,
                ...newFixedSchedules,
                ...updatedFixedSchedules,
              ],
        now: createdAtFallback,
      );
      if (schedules.isNotEmpty) {
        final target = isCreate ? newFixedSchedules : updatedFixedSchedules;
        final targetIndexById = isCreate
            ? (newFixedScheduleIndexById ??= <String, int>{})
            : (updatedFixedScheduleIndexById ??= <String, int>{});
        for (final schedule in schedules) {
          final existingIndex = targetIndexById[schedule.id];
          if (existingIndex == null) {
            targetIndexById[schedule.id] = target.length;
            target.add(schedule);
          } else {
            target[existingIndex] = schedule;
          }
        }
        registerWrite(AiTodoActionWriteGroup.fixedSchedules, action);
      }
      continue;
    }

    if (action.isHabitAction) {
      if (_isValidHabitAction(action)) {
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
        registerWrite(AiTodoActionWriteGroup.timeLogs, action);
      }
      continue;
    }

    if (action.isPomodoroAction) {
      pomodoroActions.add(action);
      continue;
    }

    if (action.isPlanBlockAction) {
      // New planning subjects stay drafts until this selected card executes.
      // Resolve titles again at confirmation to avoid duplicating a todo
      // created since generation, or referenced by another block in this batch.
      final planningTodos = [
        ...existingTodos,
        for (final todo in newTodos) {'id': todo.id, 'title': todo.title},
      ];
      TodoItem? pendingTodo;
      var planAction = action;
      final newTitle = action.newTodoTitle;
      if (action.type == AiTodoActionType.createPlanBlock &&
          newTitle != null &&
          action.todoId?.isNotEmpty != true) {
        final matches = planningTodos
            .where(
              (todo) =>
                  todo['title']?.toString().trim() == newTitle &&
                  todo['is_deleted'] != true &&
                  todo['isDeleted'] != true,
            )
            .toList();
        if (matches.length > 1) continue;
        if (matches.isEmpty) {
          pendingTodo = TodoItem(
            title: newTitle,
            createdAt: createdAtFallback.millisecondsSinceEpoch,
          );
          planningTodos.add({'id': pendingTodo.id, 'title': pendingTodo.title});
        }
        planAction = AiTodoAction.fromJson(action.toJson());
        planAction.todoId = pendingTodo?.id ?? matches.single['id']?.toString();
      }
      final block = _buildPlanBlock(
        planAction,
        planningTodos,
        existingPlanBlocks,
      );
      if (block != null) {
        if (pendingTodo != null) newTodos.add(pendingTodo);
        action.todoId = planAction.todoId;
        if (action.type == AiTodoActionType.createPlanBlock) {
          newPlanBlocks.add(block);
          registerWrite(AiTodoActionWriteGroup.newPlanBlocks, action);
        } else {
          updatedPlanBlocks.add(block);
          registerWrite(AiTodoActionWriteGroup.updatedPlanBlocks, action);
        }
      }
      continue;
    }

    // plan_todos is retained only as a parser compatibility alias. It has
    // no safe standalone creation semantics: the parser must first resolve
    // it to create_plan_block with a real existing todoId. Keep this guard
    // here as a second barrier for manually imported or persisted actions.
    if (action.type == AiTodoActionType.planTodos) {
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
        registerWrite(AiTodoActionWriteGroup.countdowns, action);
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
        registerWrite(AiTodoActionWriteGroup.todoGroups, action);
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
        registerWrite(AiTodoActionWriteGroup.pomodoroTags, action);
      }
      continue;
    }

    if (action.mutatesExistingItem) {
      if (action.type == AiTodoActionType.deleteTodo &&
          !_hasSuccessfulReplacementForDelete(action, actions)) {
        continue;
      }
      if (action.type == AiTodoActionType.categorizeTodo &&
          !action.hasGroupId) {
        continue;
      }
      final requestedGroupId = action.groupId?.trim();
      if (action.hasGroupId && requestedGroupId?.isNotEmpty == true) {
        final groupIds = existingTodoGroupIds ??= {
          for (final group in existingTodoGroups)
            if (!group.isDeleted) group.id,
        };
        if (!groupIds.contains(requestedGroupId)) continue;
      }
      final updates = _buildUpdatedTodos(action, existingTodos);
      if (updates.isNotEmpty) {
        final updateIndexById = updatedTodoIndexById ??= <String, int>{};
        for (final updated in updates) {
          final existingIndex = updateIndexById[updated.id];
          if (existingIndex == null) {
            updateIndexById[updated.id] = updatedTodos.length;
            updatedTodos.add(updated);
          } else {
            updatedTodos[existingIndex] = updated;
          }
        }
        registerWrite(AiTodoActionWriteGroup.updatedTodos, action);
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
      registerWrite(AiTodoActionWriteGroup.newTodos, action);
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
    actionsByWriteGroup: actionsByWriteGroup,
  );
}

List<T> _mergeById<T>(
  List<T> base, {
  List<T> appended = const [],
  List<T> updates = const [],
  required String Function(T) idOf,
  T Function(T existing, T update)? mergeExisting,
}) {
  final result = List<T>.of(base);
  final indexById = <String, int>{};
  for (var index = 0; index < result.length; index++) {
    final id = idOf(result[index]);
    indexById[id] ??= index;
  }

  for (final item in appended) {
    final index = result.length;
    result.add(item);
    final id = idOf(item);
    indexById[id] ??= index;
  }

  for (final update in updates) {
    final id = idOf(update);
    final index = indexById[id];
    if (index == null) {
      indexById[id] = result.length;
      result.add(update);
    } else {
      result[index] = mergeExisting?.call(result[index], update) ?? update;
    }
  }
  return result;
}

List<TodoItem> _mergeTodoUpdates(
  List<TodoItem> base,
  List<TodoItem> inserted,
  List<TodoItem> updated,
) {
  return _mergeById(
    base,
    appended: inserted,
    updates: updated,
    idOf: (todo) => todo.id,
    mergeExisting: _mergeTodo,
  );
}

List<TimeLogItem> _mergeTimeLogUpdates(
  List<TimeLogItem> base,
  List<TimeLogItem> inserted,
  List<TimeLogItem> updated,
) {
  return _mergeById(
    base,
    appended: inserted,
    updates: updated,
    idOf: (log) => log.id,
  );
}

List<FixedScheduleItem> _mergeFixedScheduleUpdates(
  List<FixedScheduleItem> base,
  List<FixedScheduleItem> inserted,
  List<FixedScheduleItem> updated,
) {
  return _mergeById(
    base,
    updates: [...inserted, ...updated],
    idOf: (item) => item.id,
  );
}

List<CountdownItem> _mergeCountdownUpdates(
  List<CountdownItem> base,
  List<CountdownItem> inserted,
  List<CountdownItem> updated,
) {
  return _mergeById(
    base,
    appended: inserted,
    updates: updated,
    idOf: (countdown) => countdown.id,
  );
}

List<PomodoroTag> _mergePomodoroTagUpdates(
  List<PomodoroTag> base,
  List<PomodoroTag> inserted,
  List<PomodoroTag> updated,
) {
  return _mergeById(
    base,
    appended: inserted,
    updates: updated,
    idOf: (tag) => tag.uuid,
  );
}

List<TodoGroup> _mergeTodoGroupUpdates(
  List<TodoGroup> base,
  List<TodoGroup> inserted,
  List<TodoGroup> updated,
) {
  return _mergeById(
    base,
    appended: inserted,
    updates: updated,
    idOf: (group) => group.id,
  );
}

TodoItem _mergeTodo(TodoItem existing, TodoItem update) {
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
