part of '../ai_todo_action_executor.dart';

List<FixedScheduleItem> _buildFixedSchedules(
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
    final recurrenceEnd =
        _parseExistingDate(action.recurrenceEndDate) ??
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
  final rebuildsSeries =
      action.hasDate ||
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
    final recurrenceEnd =
        _parseExistingDate(action.recurrenceEndDate) ??
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
          propagated.startTime = _moveScheduleTimeToDate(
            action.startTime!,
            itemDate,
          );
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

FixedScheduleItem? _buildNewFixedSchedule(AiTodoAction action, DateTime now) {
  final title = action.title?.trim();
  if (title == null || title.isEmpty) return null;
  final start = _parseExistingDate(action.startTime);
  final end =
      _parseExistingDate(action.dueDate) ??
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
      ? action.reminderMinutesList.where((value) => value >= 0).toSet().toList()
      : action.hasReminderMinutes
      ? [if (action.reminderMinutes != null) action.reminderMinutes!]
      : const <int>[15];
  final item = FixedScheduleItem(
    title: title,
    date: _dateKey(date),
    startTime: start?.millisecondsSinceEpoch,
    endTime: end?.millisecondsSinceEpoch,
    status:
        _parseFixedScheduleStatus(action.status) ??
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

FixedScheduleItem? _patchFixedSchedule(
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
  final suppliedStart = action.hasStartTime
      ? _parseExistingDate(action.startTime)
      : null;
  final suppliedEnd = action.hasDueDate
      ? _parseExistingDate(action.dueDate)
      : null;
  if (suppliedStart != null) nextDate = _day(suppliedStart);
  if (nextDate == null) return null;

  int? nextStart = existing.startTime;
  int? nextEnd = existing.endTime;
  if (action.hasStartTime) {
    nextStart = suppliedStart?.millisecondsSinceEpoch;
    if (suppliedStart == null) nextEnd = null;
  } else if (action.hasDate && oldDate != null && existing.startTime != null) {
    nextStart = _moveEpochToDate(existing.startTime!, nextDate);
  }
  if (action.hasDueDate) {
    nextEnd = suppliedEnd?.millisecondsSinceEpoch;
  } else if (action.durationMinutes != null && nextStart != null) {
    nextEnd = DateTime.fromMillisecondsSinceEpoch(nextStart)
        .add(Duration(minutes: action.durationMinutes!))
        .millisecondsSinceEpoch;
  } else if (action.hasStartTime) {
    if (suppliedStart != null &&
        existing.startTime != null &&
        existing.endTime != null) {
      nextEnd = suppliedStart
          .add(Duration(milliseconds: existing.endTime! - existing.startTime!))
          .millisecondsSinceEpoch;
    }
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

FixedScheduleStatus? _parseFixedScheduleStatus(String? value) {
  return switch (value) {
    'scheduled' => FixedScheduleStatus.scheduled,
    'finished' => FixedScheduleStatus.finished,
    'cancelled' => FixedScheduleStatus.cancelled,
    _ => null,
  };
}

DateTime? _parseScheduleDate(String? value) {
  if (value == null || value.trim().isEmpty) return null;
  final parsed = DateTime.tryParse(value.trim());
  return parsed == null ? null : _day(parsed);
}

DateTime _day(DateTime value) => DateTime(value.year, value.month, value.day);

String _dateKey(DateTime value) => AppTimeFormats.date(value);

int _moveEpochToDate(int value, DateTime date) {
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

String _moveScheduleTimeToDate(
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

TodoPlanBlock? _buildPlanBlock(
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
      final originalStart = DateTime.fromMillisecondsSinceEpoch(
        updated.startTime,
      );
      final originalEnd = DateTime.fromMillisecondsSinceEpoch(updated.endTime);
      final start = action.startTime != null
          ? DateTime.tryParse(action.startTime!)
          : null;
      if (action.startTime != null && start == null) return null;
      final nextStart = start ?? originalStart;
      final suppliedEnd = action.dueDate != null
          ? DateTime.tryParse(action.dueDate!)
          : null;
      if (action.dueDate != null && suppliedEnd == null) return null;
      final end =
          suppliedEnd ??
          (action.durationMinutes != null
              ? nextStart.add(Duration(minutes: action.durationMinutes!))
              : start != null
              ? nextStart.add(originalEnd.difference(originalStart))
              : null);
      if (end != null && !end.isAfter(nextStart)) return null;
      if (start != null) updated.startTime = start.millisecondsSinceEpoch;
      if (end != null) updated.endTime = end.millisecondsSinceEpoch;
      updated.plannedMinutes = max(
        1,
        DateTime.fromMillisecondsSinceEpoch(updated.endTime)
            .difference(DateTime.fromMillisecondsSinceEpoch(updated.startTime))
            .inMinutes,
      );
      if (action.hasRemark) updated.remark = action.remark;
      if (action.hasReminderMinutes) {
        updated.reminderMinutes = action.reminderMinutes ?? 0;
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
      .firstOrNull;
  if (match == null) return null;
  final title = action.title?.trim().isNotEmpty == true
      ? action.title!.trim()
      : match['title']?.toString();
  final plannedMinutes = max(1, end.difference(start).inMinutes);

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

TodoGroup? _buildTodoGroup(
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

CountdownItem? _buildCountdown(
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
    teamUuid: action.hasTeamUuid ? action.teamUuid : existing?.teamUuid,
    teamName: action.hasTeamUuid ? action.teamName : existing?.teamName,
    creatorId: existing?.creatorId,
    creatorName: existing?.creatorName,
  );
  if (existing != null) countdown.markAsChanged();
  return countdown;
}

PomodoroTag? _buildPomodoroTag(
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

TimeLogItem? _buildTimeLog(
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
                  ? action.startTime != null && start != null
                        ? start.add(
                            Duration(
                              milliseconds:
                                  existing.endTime - existing.startTime,
                            ),
                          )
                        : DateTime.fromMillisecondsSinceEpoch(existing.endTime)
                  : null));
  if (start == null || end == null || !end.isAfter(start)) return null;

  final log = TimeLogItem(
    id: existing?.id,
    title: action.title ?? existing?.title ?? '专注记录',
    tagUuids: action.hasTagUuids ? action.tagUuids : existing?.tagUuids ?? [],
    startTime: start.millisecondsSinceEpoch,
    endTime: end.millisecondsSinceEpoch,
    remark: action.hasRemark ? action.remark : existing?.remark,
    version: existing?.version ?? 1,
    createdAt: existing?.createdAt,
    isDeleted: existing?.isDeleted ?? false,
    deviceId: existing?.deviceId,
    teamUuid: existing?.teamUuid,
  );
  if (existing != null) log.markAsChanged();
  return log;
}
