import '../models.dart';
import '../models/ai_todo_action.dart';
import 'pomodoro_service.dart';

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
      updatedPomodoroTags.isNotEmpty;
}

class AiTodoActionExecutor {
  static AiTodoActionExecutionResult execute({
    required List<AiTodoAction> actions,
    required List<Map<String, dynamic>> existingTodos,
    List<TimeLogItem> existingTimeLogs = const [],
    List<CountdownItem> existingCountdowns = const [],
    List<TodoGroup> existingTodoGroups = const [],
    List<PomodoroTag> existingPomodoroTags = const [],
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
    final selectedActions =
        actions.where((action) => action.isSelected && !action.isAdded);
    final createdAtFallback = now ?? DateTime.now();

    for (final action in selectedActions) {
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

      if (action.mutatesExistingTodo) {
        final updated = _buildUpdatedTodo(action, existingTodos);
        if (updated != null) {
          updatedTodos.add(updated);
          action.isAdded = true;
        }
        continue;
      }

      final created = _buildNewTodo(
        action,
        categoryReminderDefaults,
        createdAtFallback,
      );
      newTodos.add(created);
      action.isAdded = true;
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
    );
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

  static TodoItem? _buildUpdatedTodo(
    AiTodoAction action,
    List<Map<String, dynamic>> existingTodos,
  ) {
    final id = action.todoId;
    if (id == null) return null;

    final gId = action.groupId;
    final existingMatch = existingTodos.where((t) => t['id'] == id).toList();
    if (existingMatch.isEmpty) {
      final now = DateTime.now();
      final startTime = action.startTime != null
          ? DateTime.tryParse(action.startTime!)
          : null;
      final dueDate =
          action.dueDate != null ? DateTime.tryParse(action.dueDate!) : null;
      final recurrenceEndDate = action.recurrenceEndDate != null
          ? DateTime.tryParse(action.recurrenceEndDate!)
          : null;
      final recurrence = RecurrenceType.values.firstWhere(
        (e) => e.name == action.recurrence,
        orElse: () => RecurrenceType.none,
      );
      return TodoItem(
        id: id,
        title: action.title ?? '',
        groupId: (gId == null || gId.isEmpty) ? null : gId,
        isDone: action.type == AiTodoActionType.completeTodo,
        isDeleted: action.type == AiTodoActionType.deleteTodo,
        remark: action.remark,
        dueDate: dueDate,
        createdDate:
            startTime?.millisecondsSinceEpoch ?? now.millisecondsSinceEpoch,
        recurrence: recurrence,
        customIntervalDays: action.customIntervalDays,
        recurrenceEndDate: recurrenceEndDate,
        isAllDay: action.isAllDay,
        reminderMinutes: action.reminderMinutes,
        originalText: action.originalText,
      )..markAsChanged();
    }

    final existing = existingMatch.first;
    final existingGroupId = existing['groupId']?.toString();
    final nextGroupId = action.type == AiTodoActionType.categorizeTodo
        ? ((gId == null || gId.isEmpty) ? null : gId)
        : ((gId != null && gId.isNotEmpty) ? gId : existingGroupId);

    final existingStartTime = existing['startTime'] != null
        ? DateTime.tryParse(existing['startTime'].toString())
        : null;
    final existingDueDate = existing['endTime'] != null
        ? DateTime.tryParse(existing['endTime'].toString())
        : null;
    final nextStartTime = action.startTime != null
        ? DateTime.tryParse(action.startTime!)
        : existingStartTime;
    final nextDueDate = action.dueDate != null
        ? DateTime.tryParse(action.dueDate!)
        : existingDueDate;

    return TodoItem(
      id: id,
      title: action.title ?? existing['title'] ?? '',
      groupId: nextGroupId,
      isDone: action.type == AiTodoActionType.completeTodo
          ? true
          : existing['isDone'] ?? false,
      isDeleted: action.type == AiTodoActionType.deleteTodo
          ? true
          : existing['isDeleted'] ?? false,
      remark: action.remark ?? existing['remark'],
      dueDate: nextDueDate,
      createdDate: nextStartTime?.millisecondsSinceEpoch,
      recurrence: _parseRecurrence(action.recurrence, existing),
      customIntervalDays: action.customIntervalDays ??
          _parseNullableInt(
            existing['customIntervalDays'] ?? existing['custom_interval_days'],
          ),
      recurrenceEndDate: action.recurrenceEndDate != null
          ? DateTime.tryParse(action.recurrenceEndDate!)
          : _parseExistingDate(
              existing['recurrenceEndDate'] ?? existing['recurrence_end_date'],
            ),
      isAllDay: action.isAllDay || existing['isAllDay'] == true,
      reminderMinutes:
          action.reminderMinutes ?? existing['reminderMinutes'] as int?,
    )..markAsChanged();
  }

  static TodoItem _buildNewTodo(
    AiTodoAction action,
    Map<String, int> categoryReminderDefaults,
    DateTime now,
  ) {
    final startTime =
        action.startTime != null ? DateTime.tryParse(action.startTime!) : null;
    final dueDate =
        action.dueDate != null ? DateTime.tryParse(action.dueDate!) : null;
    final recurrenceEndDate = action.recurrenceEndDate != null
        ? DateTime.tryParse(action.recurrenceEndDate!)
        : null;
    final recurrence = RecurrenceType.values.firstWhere(
      (e) => e.name == action.recurrence,
      orElse: () => RecurrenceType.none,
    );
    final gId = action.groupId;

    return TodoItem(
      title: action.title ?? '未命名待办',
      remark: _buildRemark(action),
      dueDate: dueDate,
      createdDate:
          startTime?.millisecondsSinceEpoch ?? now.millisecondsSinceEpoch,
      recurrence: recurrence,
      customIntervalDays: action.customIntervalDays,
      recurrenceEndDate: recurrenceEndDate,
      originalText: action.originalText,
      groupId: (gId == null || gId.isEmpty) ? null : gId,
      isAllDay: action.isAllDay,
      reminderMinutes: action.reminderMinutes ??
          (gId != null ? categoryReminderDefaults[gId] : null),
    );
  }

  static String? _buildRemark(AiTodoAction action) {
    final sourcePrefix = action.sourceTodoIds.isEmpty
        ? null
        : '来源待办: ${action.sourceTodoIds.join(', ')}';
    if (sourcePrefix == null) return action.remark;
    if (action.remark == null || action.remark!.isEmpty) return sourcePrefix;
    return '${action.remark}\n$sourcePrefix';
  }

  static RecurrenceType _parseRecurrence(
    String recurrence,
    Map<String, dynamic> existing,
  ) {
    if (recurrence != 'none') {
      return RecurrenceType.values.firstWhere(
        (e) => e.name == recurrence,
        orElse: () => RecurrenceType.none,
      );
    }

    final existingRecurrence = existing['recurrence'];
    if (existingRecurrence is int &&
        existingRecurrence >= 0 &&
        existingRecurrence < RecurrenceType.values.length) {
      return RecurrenceType.values[existingRecurrence];
    }
    return RecurrenceType.values.firstWhere(
      (e) => e.name == existingRecurrence?.toString(),
      orElse: () => RecurrenceType.none,
    );
  }

  static int? _parseNullableInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString());
  }

  static DateTime? _parseExistingDate(dynamic value) {
    if (value == null) return null;
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
      title: update.title.isNotEmpty ? update.title : existing.title,
      isDone: update.isDone,
      isDeleted: update.isDeleted,
      version: existing.version,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
      createdAt: existing.createdAt,
      createdDate: update.createdDate ?? existing.createdDate,
      recurrence: update.recurrence,
      customIntervalDays: update.customIntervalDays,
      recurrenceEndDate: update.recurrenceEndDate,
      dueDate: update.dueDate,
      remark: update.remark ?? existing.remark,
      imagePath: existing.imagePath,
      originalText: update.originalText ?? existing.originalText,
      groupId: update.groupId,
      reminderMinutes: update.reminderMinutes,
      teamUuid: existing.teamUuid,
      creatorId: existing.creatorId,
      creatorName: existing.creatorName,
      teamName: existing.teamName,
      collabType: existing.collabType,
      hasConflict: existing.hasConflict,
      serverVersionData: existing.serverVersionData,
      isAllDay: update.isAllDay,
      categoryId: existing.categoryId,
    )..markAsChanged();
  }
}
