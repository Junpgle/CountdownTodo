part of '../ai_todo_action_executor.dart';

List<TodoItem> _buildUpdatedTodos(
  AiTodoAction action,
  List<Map<String, dynamic>> existingTodos,
) {
  final id = action.todoId;
  if (id == null || id.isEmpty) return const [];
  if (action.recurrenceScope == 'series' &&
      action.type != AiTodoActionType.updateTodo) {
    return const [];
  }
  final target = existingTodos.where((todo) => todo['id'] == id).firstOrNull;
  if (target == null) return const [];

  final storedSeriesId = _nullableString(
    target['recurrenceSeriesId'] ?? target['recurrence_series_id'],
  );
  final seriesId =
      storedSeriesId ??
      (_existingRecurrence(target) == RecurrenceType.none ? null : id);
  final isWholeSeriesEdit =
      action.type == AiTodoActionType.updateTodo &&
      action.recurrenceScope == 'series';
  if (action.type == AiTodoActionType.skipTodo) {
    final isRecurring =
        seriesId != null || _existingRecurrence(target) != RecurrenceType.none;
    if (!isRecurring ||
        action.appliesToFutureOccurrences ||
        _mapBool(target, 'isDone') ||
        _mapBool(target, 'isDeleted') ||
        _mapBool(target, 'isSkipped')) {
      return const [];
    }
  }
  if (action.recurrenceSeriesId?.trim().isNotEmpty == true &&
      action.recurrenceSeriesId!.trim() != seriesId) {
    return const [];
  }

  if (isWholeSeriesEdit && seriesId == null) return const [];
  final effectiveAction = action.copy();
  if (isWholeSeriesEdit) {
    // Whole-series edits change shared todo content and timing only. The
    // recurrence rule remains anchored to the selected occurrence.
    effectiveAction
      ..hasRecurrence = false
      ..hasCustomIntervalDays = false
      ..hasRecurrenceEndDate = false;
  }
  final targetUpdate = _buildUpdatedTodo(effectiveAction, target);
  if (targetUpdate == null) return const [];
  final updates = <TodoItem>[targetUpdate];

  // 完成只属于一个真实期次。即使模型误给 future，也不能把尚未发生的
  // 周期批量标记完成。
  if ((!action.appliesToFutureOccurrences && !isWholeSeriesEdit) ||
      seriesId == null ||
      action.type == AiTodoActionType.completeTodo ||
      action.type == AiTodoActionType.skipTodo) {
    return updates;
  }

  final targetStart = _todoStart(target);
  final updatedStart = targetUpdate.createdDate == null
      ? null
      : AppTimeFormats.localFromServerTimestamp(targetUpdate.createdDate!);
  final shift = targetStart == null || updatedStart == null
      ? Duration.zero
      : updatedStart.difference(targetStart);
  final updatedDuration = updatedStart == null || targetUpdate.dueDate == null
      ? null
      : targetUpdate.dueDate!.difference(updatedStart);
  final hasTimePatch =
      effectiveAction.hasStartTime ||
      effectiveAction.hasDueDate ||
      effectiveAction.hasTimeMode ||
      effectiveAction.hasIsAllDay;
  final recurrenceEnd = effectiveAction.hasRecurrenceEndDate
      ? _parseExistingDate(effectiveAction.recurrenceEndDate)
      : targetUpdate.recurrenceEndDate;
  final calendarDayDelta = targetStart == null || updatedStart == null
      ? 0
      : TodoRecurrenceSeriesEditService.calendarDayDelta(
          targetStart,
          updatedStart,
        );
  if (isWholeSeriesEdit &&
      calendarDayDelta != 0 &&
      targetUpdate.recurrenceEndDate != null) {
    targetUpdate.recurrenceEndDate =
        TodoRecurrenceSeriesEditService.shiftCalendarDate(
          targetUpdate.recurrenceEndDate!,
          calendarDayDelta,
        );
  }

  final future =
      existingTodos.where((todo) {
        if (todo['id'] == id || _mapBool(todo, 'isDeleted')) return false;
        final candidateSeries = _nullableString(
          todo['recurrenceSeriesId'] ?? todo['recurrence_series_id'],
        );
        final candidateStart = _todoStart(todo);
        final candidateId = todo['id']?.toString();
        final sameSeries =
            candidateSeries == seriesId ||
            (candidateId == seriesId && candidateSeries == null);
        if (!sameSeries) return false;
        if (isWholeSeriesEdit) return true;
        return candidateStart != null &&
            targetStart != null &&
            !candidateStart.isBefore(targetStart);
      }).toList()..sort(
        (a, b) => (_todoStart(a)?.millisecondsSinceEpoch ?? 0).compareTo(
          _todoStart(b)?.millisecondsSinceEpoch ?? 0,
        ),
      );

  for (final candidate in future) {
    final candidateAction = effectiveAction.copy()
      ..todoId = candidate['id']?.toString()
      ..recurrenceScope = 'occurrence';
    final candidateStart = _todoStart(candidate);

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
      } else if (candidateStart != null &&
          targetStart != null &&
          updatedStart != null) {
        final shiftedStart = candidateStart.add(shift);
        candidateAction
          ..startTime = shiftedStart.toIso8601String()
          ..dueDate = updatedDuration == null
              ? shiftedStart.toIso8601String()
              : targetUpdate.isDateOnly
              ? DateTime(
                  shiftedStart.year,
                  shiftedStart.month,
                  shiftedStart.day,
                  23,
                  59,
                ).toIso8601String()
              : shiftedStart.add(updatedDuration).toIso8601String()
          ..timeMode = targetUpdate.timeMode.name
          ..isAllDay = targetUpdate.isDateOnly
          ..hasStartTime = true
          ..hasDueDate = true
          ..hasTimeMode = true
          ..hasIsAllDay = true;
      } else if (isWholeSeriesEdit) {
        candidateAction
          ..hasStartTime = false
          ..hasDueDate = false
          ..hasTimeMode = false
          ..hasIsAllDay = false;
      }
    }

    // 一个系列只能有一个规则锚点。新规则挂在目标期次上，之后已经生成
    // 的实例仍是 recurrence=none，但会同步其他规则元数据。
    if (!isWholeSeriesEdit &&
        effectiveAction.hasRecurrence &&
        effectiveAction.recurrence != 'none') {
      candidateAction
        ..recurrence = 'none'
        ..hasRecurrence = _existingRecurrence(candidate) != RecurrenceType.none;
    }

    final shiftedCandidateDay = candidateStart?.add(shift);
    final isPastRecurrenceEnd =
        recurrenceEnd != null &&
        shiftedCandidateDay != null &&
        DateTime(
          shiftedCandidateDay.year,
          shiftedCandidateDay.month,
          shiftedCandidateDay.day,
        ).isAfter(
          DateTime(recurrenceEnd.year, recurrenceEnd.month, recurrenceEnd.day),
        );
    final shouldDelete =
        !isWholeSeriesEdit &&
        (action.type == AiTodoActionType.deleteTodo ||
            (effectiveAction.hasRecurrence &&
                effectiveAction.recurrence == 'none') ||
            isPastRecurrenceEnd);
    final updated = _buildUpdatedTodo(candidateAction, candidate);
    if (updated == null) continue;
    if (isWholeSeriesEdit &&
        calendarDayDelta != 0 &&
        updated.recurrenceEndDate != null) {
      updated.recurrenceEndDate =
          TodoRecurrenceSeriesEditService.shiftCalendarDate(
            updated.recurrenceEndDate!,
            calendarDayDelta,
          );
    }
    if (shouldDelete) {
      updated
        ..isDeleted = true
        ..recurrence = RecurrenceType.none;
    }
    updates.add(updated);
  }
  return updates;
}

bool _hasSuccessfulReplacementForDelete(
  AiTodoAction deletion,
  List<AiTodoAction> actions,
) {
  final generatedBy = deletion.metadata['generatedBy'];
  if (generatedBy != 'split_todo' && generatedBy != 'merge_todos') {
    return true;
  }

  final sourceId = deletion.todoId?.trim();
  if (sourceId == null || sourceId.isEmpty) return false;
  final replacements = actions.where((action) {
    if (!action.sourceTodoIds.contains(sourceId)) return false;
    return generatedBy == 'split_todo'
        ? action.type == AiTodoActionType.splitTodo
        : action.type == AiTodoActionType.mergeTodos;
  }).toList();
  return replacements.isNotEmpty &&
      replacements.every(
        (action) => action.isSelected && !action.isIgnored && action.isAdded,
      );
}

TodoItem? _buildUpdatedTodo(
  AiTodoAction action,
  Map<String, dynamic> existing,
) {
  final id = action.todoId;
  if (id == null || id.isEmpty) return null;

  final existingStart = _todoStart(existing);
  final existingDue = _todoDue(existing);
  final hasTimePatch =
      action.hasStartTime ||
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
  if ((action.hasRecurrence || action.hasCustomIntervalDays) &&
      nextRecurrence == RecurrenceType.customDays &&
      (nextCustomInterval == null || nextCustomInterval <= 0)) {
    return null;
  }
  final nextRecurrenceEnd = action.hasRecurrenceEndDate
      ? _parseExistingDate(action.recurrenceEndDate)
      : _parseExistingDate(
          existing['recurrenceEndDate'] ?? existing['recurrence_end_date'],
        );
  if (action.hasRecurrence &&
      nextRecurrence != RecurrenceType.none &&
      normalizedTime.start == null) {
    return null;
  }
  if ((action.hasRecurrence || action.hasRecurrenceEndDate || hasTimePatch) &&
      nextRecurrence != RecurrenceType.none &&
      nextRecurrenceEnd != null &&
      normalizedTime.start != null &&
      _day(nextRecurrenceEnd).isBefore(_day(normalizedTime.start!))) {
    return null;
  }
  var recurrenceSeriesId = _nullableString(
    existing['recurrenceSeriesId'] ?? existing['recurrence_series_id'],
  );
  if (nextRecurrence != RecurrenceType.none && recurrenceSeriesId == null) {
    recurrenceSeriesId = id;
  }

  final updated = TodoItem(
    id: id,
    title: action.title ?? existing['title']?.toString() ?? '',
    groupId: nextGroupId,
    isDone: action.type == AiTodoActionType.completeTodo
        ? true
        : action.type == AiTodoActionType.skipTodo
        ? false
        : _mapBool(existing, 'isDone'),
    isSkipped: action.type == AiTodoActionType.skipTodo
        ? true
        : action.type == AiTodoActionType.completeTodo
        ? false
        : _mapBool(existing, 'isSkipped'),
    isSkippedSyncPending:
        action.type == AiTodoActionType.skipTodo ||
            (action.type == AiTodoActionType.completeTodo &&
                _mapBool(existing, 'isSkipped'))
        ? true
        : _mapBool(existing, 'isSkippedSyncPending'),
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
    recurrenceEndDate:
        nextRecurrence == RecurrenceType.none &&
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

TodoItem? _buildNewTodo(
  AiTodoAction action,
  Map<String, int> categoryReminderDefaults,
  DateTime now,
) {
  final title = action.title?.trim();
  if (title == null || title.isEmpty) return null;

  final normalizedTime = _normalizeActionTime(action);
  final recurrence = _parseRecurrenceName(action.recurrence);
  final recurrenceEndDate = _parseExistingDate(action.recurrenceEndDate);
  if (recurrence != RecurrenceType.none && normalizedTime.start == null) {
    return null;
  }
  if (recurrence == RecurrenceType.customDays &&
      (action.customIntervalDays == null || action.customIntervalDays! <= 0)) {
    return null;
  }
  if (recurrenceEndDate != null &&
      normalizedTime.start != null &&
      DateTime(
        recurrenceEndDate.year,
        recurrenceEndDate.month,
        recurrenceEndDate.day,
      ).isBefore(
        DateTime(
          normalizedTime.start!.year,
          normalizedTime.start!.month,
          normalizedTime.start!.day,
        ),
      )) {
    return null;
  }
  final gId = action.groupId;
  final todo = TodoItem(
    title: title,
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
    reminderMinutes:
        action.reminderMinutes ??
        (gId != null ? categoryReminderDefaults[gId] : null),
  );
  if (recurrence != RecurrenceType.none) {
    todo.recurrenceSeriesId = todo.id;
  }
  return todo;
}

String? _buildRemark(AiTodoAction action) {
  final sourcePrefix = action.sourceTodoIds.isEmpty
      ? null
      : '来源待办: ${action.sourceTodoIds.join(', ')}';
  if (sourcePrefix == null) return action.remark;
  if (action.remark == null || action.remark!.isEmpty) return sourcePrefix;
  return '${action.remark}\n$sourcePrefix';
}

({DateTime? start, DateTime? due, bool isDateOnly}) _normalizeActionTime(
  AiTodoAction action, {
  DateTime? existingStart,
  DateTime? existingDue,
  TodoTimeMode existingMode = TodoTimeMode.unscheduled,
}) {
  if (action.hasDueDate && action.dueDate == null) {
    return (start: null, due: null, isDateOnly: false);
  }

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
  final suppliedDue = action.hasDueDate
      ? _parseExistingDate(action.dueDate)
      : existingDue;
  if (requestedMode == TodoTimeMode.dateOnly) {
    final normalized = TodoItem.normalizeTimeForWrite(
      selectedDate: suppliedStart ?? suppliedDue,
      dueDate: suppliedDue,
      isDateOnly: true,
    );
    return (start: normalized.start, due: normalized.due, isDateOnly: true);
  }

  // 新版 TodoItem 不再写入执行时间段。即使兼容输入同时给了
  // startTime/endTime，待办本体也只保留 dueDate 截止点。
  final deadline = suppliedDue ?? suppliedStart;
  final normalized = TodoItem.normalizeTimeForWrite(
    dueDate: deadline,
    isDateOnly: false,
  );
  return (start: normalized.start, due: normalized.due, isDateOnly: false);
}

RecurrenceType _parseRecurrenceName(String recurrence) {
  return RecurrenceType.values.firstWhere(
    (value) => value.name == recurrence,
    orElse: () => RecurrenceType.none,
  );
}

RecurrenceType _existingRecurrence(Map<String, dynamic> existing) {
  final value = existing['recurrence'];
  if (value is int && value >= 0 && value < RecurrenceType.values.length) {
    return RecurrenceType.values[value];
  }
  return _parseRecurrenceName(value?.toString() ?? 'none');
}

TodoTimeMode _existingTimeMode(Map<String, dynamic> existing) {
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

DateTime? _todoStart(Map<String, dynamic> todo) => _parseExistingDate(
  todo['startTime'] ??
      todo['start_time'] ??
      todo['createdDate'] ??
      todo['created_date'],
);

DateTime? _todoDue(Map<String, dynamic> todo) => _parseExistingDate(
  todo['endTime'] ?? todo['end_time'] ?? todo['dueDate'] ?? todo['due_date'],
);

bool _mapBool(Map<String, dynamic> map, String key) {
  final snakeKey = key.replaceAllMapped(
    RegExp(r'[A-Z]'),
    (match) => '_${match.group(0)!.toLowerCase()}',
  );
  final aliases = switch (key) {
    'isDone' => const ['is_completed', 'isCompleted'],
    'isSkipped' => const ['is_skipped'],
    'isSkippedSyncPending' => const ['is_skipped_sync_pending'],
    _ => const <String>[],
  };
  final value =
      map[key] ??
      map[snakeKey] ??
      aliases.map((alias) => map[alias]).whereType<Object>().firstOrNull;
  return value == true || value == 1 || value?.toString() == '1';
}

String? _nullableString(dynamic value) =>
    AppTextUtils.trimToNull(value?.toString());

int? _parseNullableInt(dynamic value) {
  return JsonValueParser.toNullableInt(value);
}

DateTime? _parseExistingDate(dynamic value) {
  if (value == null) return null;
  if (value is DateTime) return value.toLocal();
  if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
  if (value is num) return DateTime.fromMillisecondsSinceEpoch(value.toInt());
  return DateTime.tryParse(value.toString());
}
