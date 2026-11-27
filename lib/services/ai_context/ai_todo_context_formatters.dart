part of '../ai_todo_context_builder.dart';

String _formatTodos(
  List<Map<String, dynamic>> todos,
  List<TodoGroup> todoGroups, {
  String? userMessage,
  DateTime? now,
}) {
  if (todos.isEmpty) return '暂无待办';
  final scoped = _scopeTodosByTime(todos, userMessage: userMessage, now: now);
  if (scoped.isEmpty) return '待办列表: 暂无匹配时间范围的待办';
  final displayed = scoped.take(80).toList();
  final groupNameById = <String, String>{};
  for (final group in todoGroups) {
    groupNameById.putIfAbsent(group.id, () => group.name);
  }
  return '待办列表（按时间范围筛选，展示 ${displayed.length}/${scoped.length} 条）:\n${displayed.map((t) {
    final id = t['id'] ?? 'unknown';
    final title = t['title'] ?? '';
    final remark = t['remark'] ?? '';
    final dueDateValue = t['dueDate'] ?? t['due_date'] ?? t['endTime'] ?? t['end_time'];
    final dueDate = _parseFlexibleDateTime(dueDateValue);
    final timeMode = switch (t['timeMode']?.toString()) {
      'dateOnly' => '日期内完成',
      'deadline' => '定时截止',
      _ => '未安排',
    };
    final recurrence = t['recurrence'] ?? 'none';
    final recurrenceRule = t['recurrenceRule'] ?? recurrence;
    final recurrenceSeriesId = t['recurrenceSeriesId']?.toString().trim() ?? '';
    final recurrenceRole = t['recurrenceRole']?.toString() ?? 'standalone';
    final customIntervalDays = t['customIntervalDays'];
    final recurrenceEndDate = t['recurrenceEndDate']?.toString().trim() ?? '';
    final status = t['isSkipped'] == true
        ? '已跳过本期'
        : t['isDone'] == true
        ? '已完成'
        : '未完成';
    final reminderMinutes = t['reminderMinutes'] ?? 5;
    final gid = t['groupId'] ?? '';
    var folderName = '';
    if (gid is String && gid.isNotEmpty) {
      folderName = groupNameById[gid] ?? '';
    }

    final recurrenceText = recurrenceSeriesId.isEmpty ? ' | 循环: none' : ' | 系列ID: $recurrenceSeriesId | 期次角色: $recurrenceRole | 系列规则: $recurrenceRule${recurrenceRule == 'customDays' ? '(${customIntervalDays ?? 1}天)' : ''}${recurrenceEndDate.isNotEmpty ? ' | 系列结束: $recurrenceEndDate' : ''}${recurrence != recurrenceRule ? ' | 本期存储规则: $recurrence' : ''}';
    final timeText = switch (t['timeMode']?.toString()) {
      'dateOnly' when dueDate != null => ' | 目标日期: ${_formatDate(dueDate)}',
      'deadline' when dueDate != null => ' | 截止: ${_formatDateTime(dueDate)}',
      _ => '',
    };
    final skippedNote = t['isSkipped'] == true ? ' | 只跳过该期，后续期次继续' : '';
    return '- [期次todoId: $id] 标题: $title | 状态: $status$skippedNote${remark.toString().isNotEmpty ? ' | 备注: $remark' : ''}${folderName.isNotEmpty ? ' | 分类: $folderName' : ''}$timeText | 时间语义: $timeMode$recurrenceText | 提醒: 提前$reminderMinutes分钟';
  }).join('\n')}';
}

String _formatGroups(List<TodoGroup> todoGroups) {
  if (todoGroups.isEmpty) return '暂无分类';
  return todoGroups.map((g) => '- 名称: ${g.name} | ID: ${g.id}').join('\n');
}

String _formatCountdowns(
  List<CountdownItem> countdowns, {
  String? userMessage,
  DateTime? now,
}) {
  final active = _scopeCountdownsByTime(
    countdowns,
    userMessage: userMessage,
    now: now,
  );
  if (active.isEmpty) return '倒计时: 暂无匹配时间范围的记录';
  final ordered = active.toList()
    ..sort((left, right) => left.targetDate.compareTo(right.targetDate));
  final displayed = ordered.take(40).toList();
  return '倒计时（按目标时间升序，展示 ${displayed.length}/${ordered.length} 条）:\n${displayed.map((c) {
    final target = AppTimeFormats.fullDateTime(c.targetDate);
    final status = c.isCompleted ? '已达成' : '进行中';
    return '- [ID: ${c.id}] 标题: ${c.title} | 目标: $target | 状态: $status';
  }).join('\n')}';
}

String _formatPomodoroTags(List<PomodoroTag> tags) {
  final allActive = tags.where((tag) => !tag.isDeleted).toList();
  final active = allActive.take(40).toList();
  if (active.isEmpty) return '暂无番茄标签';
  return '番茄标签（展示 ${active.length}/${allActive.length} 个）:\n${active.map((t) => '- [ID: ${t.uuid}] 名称: ${t.name} | 颜色: ${t.color}').join('\n')}';
}

String _formatPlanBlocks(
  List<TodoPlanBlock> blocks,
  List<Map<String, dynamic>> todos, {
  String? userMessage,
  DateTime? now,
  AiContextDateRange? priorityRange,
}) {
  final active = _scopePlanBlocksByTime(
    blocks,
    userMessage: userMessage,
    now: now,
  )..sort((a, b) => a.startTime.compareTo(b.startTime));
  if (active.isEmpty) return '待办规划: 暂无匹配时间范围的规划块';
  final blocksToFormat = _limitPlanBlocks(
    active,
    limit: 60,
    priorityRange: priorityRange,
  );

  final todoTitleById = <String, String>{};
  for (final todo in todos) {
    final id = todo['id']?.toString();
    if (id == null) continue;
    todoTitleById.putIfAbsent(id, () => todo['title']?.toString() ?? '');
  }

  String todoTitle(String id) {
    final title = todoTitleById[id];
    return title == null || title.isEmpty ? id : title;
  }

  final selectedRangeNotice = priorityRange == null ? '' : '，优先用户所选范围';
  return '待办规划（按时间范围筛选，展示 ${blocksToFormat.length}/${active.length} 条$selectedRangeNotice）:\n${blocksToFormat.map((b) {
    final start = AppTimeFormats.fullDateTime(DateTime.fromMillisecondsSinceEpoch(b.startTime));
    final end = AppTimeFormats.fullDateTime(DateTime.fromMillisecondsSinceEpoch(b.endTime));
    final actualMinutes = b.actualFocusSeconds ~/ 60;
    return '- [ID: ${b.id}] 待办ID: ${b.todoId} | 标题: ${b.titleSnapshot ?? todoTitle(b.todoId)} | 时间: $start-$end | 计划: ${b.plannedMinutes}分钟 | 实际专注: $actualMinutes分钟 | 状态: ${b.status.name} | 提醒: 提前${b.reminderMinutes}分钟';
  }).join('\n')}';
}

List<TodoPlanBlock> _limitPlanBlocks(
  List<TodoPlanBlock> blocks, {
  required int limit,
  AiContextDateRange? priorityRange,
}) {
  if (blocks.length <= limit || priorityRange == null) {
    return blocks.take(limit).toList();
  }

  bool isInPriorityRange(TodoPlanBlock block) {
    final start = DateTime.fromMillisecondsSinceEpoch(block.startTime);
    final end = DateTime.fromMillisecondsSinceEpoch(block.endTime);
    return _dateRangeOverlaps(
      priorityRange.start,
      priorityRange.endExclusive,
      start,
      end,
    );
  }

  final selected = blocks.where(isInPriorityRange).take(limit).toList();
  final remainingLimit = limit - selected.length;
  if (remainingLimit > 0) {
    selected.addAll(
      blocks.where((block) => !isInPriorityRange(block)).take(remainingLimit),
    );
  }
  selected.sort((left, right) => left.startTime.compareTo(right.startTime));
  return selected;
}

String _formatFixedSchedules(
  List<FixedScheduleItem> schedules,
  String userMessage,
  DateTime now,
) {
  final scoped = _scopeFixedSchedulesByTime(
    schedules,
    userMessage: userMessage,
    now: now,
  );
  if (scoped.isEmpty) return '固定日程: 暂无';
  final lines = scoped
      .take(50)
      .map((item) {
        final time = item.startTime == null
            ? '时间待定'
            : item.endTime == null
            ? '${AppTimeFormats.clock(DateTime.fromMillisecondsSinceEpoch(item.startTime!).toLocal())}（结束待定）'
            : '${AppTimeFormats.clock(DateTime.fromMillisecondsSinceEpoch(item.startTime!).toLocal())}-${AppTimeFormats.clock(DateTime.fromMillisecondsSinceEpoch(item.endTime!).toLocal())}';
        final series = item.recurrenceSeriesId?.trim().isNotEmpty == true
            ? ' | 系列ID: ${item.recurrenceSeriesId} | 重复: ${item.recurrence.name}'
            : '';
        final location = item.location?.trim().isNotEmpty == true
            ? ' | 地点: ${item.location}'
            : '';
        final remark = item.remark?.trim().isNotEmpty == true
            ? ' | 备注: ${item.remark}'
            : '';
        return '- [日程ID: ${item.id}] ${item.date} $time ${item.title} | 状态: ${item.status.name}$location$remark$series';
      })
      .join('\n');
  final displayedCount = scoped.length < 50 ? scoped.length : 50;
  return '固定日程（外部时间硬约束；展示 $displayedCount/${scoped.length} 条；每条使用自己的日程ID）:\n$lines';
}

String _formatCourses(
  List<CourseItem> courses,
  String userMessage,
  DateTime now,
) {
  if (courses.isEmpty) return '课程表: 暂无';
  final activeCourses = courses.where((c) => !c.isDeleted).toList()
    ..sort((a, b) {
      final dateCompare = a.date.compareTo(b.date);
      if (dateCompare != 0) return dateCompare;
      return a.startTime.compareTo(b.startTime);
    });
  if (activeCourses.isEmpty) return '课程表: 暂无';

  final allDates = activeCourses
      .map((c) => DateTime.tryParse(c.date))
      .whereType<DateTime>()
      .toList();
  final availableRange = allDates.isEmpty
      ? null
      : _DateRange(
          label: '全部可用课程日期',
          start: allDates.first,
          end: AppTimeFormats.localDayStartOffset(allDates.last, 1),
        );
  final period = _resolveCoursePeriod(userMessage, now);
  final scopedCourses = _selectCoursesForPeriod(activeCourses, period, now);
  final selectedCourses = period == null
      ? scopedCourses.take(30).toList()
      : scopedCourses;
  final lines = selectedCourses
      .map(
        (c) =>
            '- ${c.date} ${c.formattedStartTime}-${c.formattedEndTime} ${c.courseName} | ${c.roomName} | ${c.teacherName}',
      )
      .join('\n');
  final header = period == null
      ? '课程表（当前时间: ${_formatDateTime(now)}，今日起展示 ${selectedCourses.length}/${scopedCourses.length} 节）'
      : '课程表（当前时间: ${_formatDateTime(now)}，${period.label}范围: ${_formatDate(period.start)} 至 ${_formatDate(AppTimeFormats.localDayStartOffset(period.end, -1))}，共${selectedCourses.length}节）';
  final rangeLine = availableRange == null
      ? ''
      : '\n${availableRange.label}: ${_formatDate(availableRange.start)} 至 ${_formatDate(AppTimeFormats.localDayStartOffset(availableRange.end, -1))}';
  return '$header$rangeLine\n${lines.isEmpty ? '暂无匹配课程' : lines}';
}

String _formatFocusRecords(
  List<TimeLogItem> timeLogs,
  List<PomodoroRecord> pomodoroRecords,
  String userMessage,
  DateTime now, {
  int recordLimit = 30,
  AiContextDateRange? priorityRange,
}) {
  final records = _activeFocusRecords(timeLogs, pomodoroRecords);
  if (records.isEmpty) return '专注记录: 暂无';
  final period = _resolveTimeLogPeriod(userMessage, now);
  final scopedRecords = _scopeFocusRecords(records, period);
  final recordsToFormat = _limitFocusRecords(
    scopedRecords,
    limit: recordLimit,
    priorityRange: priorityRange,
  );

  if (period != null) {
    int totalFocusSeconds(Iterable<_FocusRecord> records) => records
        .map((record) => _focusOverlapSeconds(record, period))
        .fold<int>(0, (sum, seconds) => sum + seconds);
    final totalMinutes = (totalFocusSeconds(scopedRecords) / 60).round();
    final timeLogMinutes =
        (totalFocusSeconds(scopedRecords.where((r) => r.source == '补录')) / 60)
            .round();
    final pomodoroMinutes =
        (totalFocusSeconds(scopedRecords.where((r) => r.source == '番茄钟')) / 60)
            .round();
    final lines = recordsToFormat
        .map((r) {
          final start = _formatEpochMillis(r.startMs);
          final end = _formatEpochMillis(r.endMs);
          final seconds = _focusOverlapSeconds(r, period);
          return '- [${r.source} ID: ${r.id}] $start-$end ${r.title} | 本时段计入${formatDurationChinese(seconds)}${r.status != null ? ' | 状态: ${r.status}' : ''}';
        })
        .join('\n');
    return '''专注记录:
${period.label}范围: ${_formatDateTime(period.start)} 至 ${_formatDateTime(period.end)}
${period.label}合计: ${formatMinutesChinese(totalMinutes)}
其中补录: ${formatMinutesChinese(timeLogMinutes)}，番茄钟: ${formatMinutesChinese(pomodoroMinutes)}
记录明细展示 ${recordsToFormat.length}/${scopedRecords.length} 条，按开始时间倒序；合计基于全部记录。
${period.label}记录:
${lines.isEmpty ? '暂无' : lines}''';
  }

  final lines = recordsToFormat
      .map((r) {
        final start = _formatEpochMillis(r.startMs);
        final end = _formatEpochMillis(r.endMs);
        return '- [${r.source} ID: ${r.id}] $start-$end ${r.title} | ${formatMinutesChinese(r.minutes)}${r.status != null ? ' | 状态: ${r.status}' : ''}';
      })
      .join('\n');
  return '专注记录（展示 ${recordsToFormat.length}/${records.length} 条，按开始时间倒序）:\n$lines';
}

List<_FocusRecord> _activeFocusRecords(
  List<TimeLogItem> timeLogs,
  List<PomodoroRecord> pomodoroRecords,
) => [
  ...timeLogs
      .where((record) => !record.isDeleted)
      .map(_FocusRecord.fromTimeLog),
  ...pomodoroRecords
      .where((record) => !record.isDeleted)
      .map(_FocusRecord.fromPomodoro),
]..sort((left, right) => right.startMs.compareTo(left.startMs));

List<_FocusRecord> _scopeFocusRecords(
  List<_FocusRecord> records,
  _TimeLogPeriod? period,
) => period == null
    ? records
    : records.where((record) => _focusOverlapsPeriod(record, period)).toList();

int _countFocusRecords(
  List<TimeLogItem> timeLogs,
  List<PomodoroRecord> pomodoroRecords,
  _TimeLogPeriod? period,
) {
  var count = 0;
  for (final log in timeLogs) {
    if (log.isDeleted) continue;
    final record = _FocusRecord.fromTimeLog(log);
    if (period == null || _focusOverlapsPeriod(record, period)) count++;
  }
  for (final pomodoro in pomodoroRecords) {
    if (pomodoro.isDeleted) continue;
    final record = _FocusRecord.fromPomodoro(pomodoro);
    if (period == null || _focusOverlapsPeriod(record, period)) count++;
  }
  return count;
}

List<_FocusRecord> _limitFocusRecords(
  List<_FocusRecord> records, {
  required int limit,
  AiContextDateRange? priorityRange,
}) {
  if (records.length <= limit) return records;
  if (priorityRange == null) return records.take(limit).toList();

  final selectedPeriod = _TimeLogPeriod(
    label: '用户选择范围',
    start: priorityRange.start,
    end: priorityRange.endExclusive,
  );
  final selectedRecords = records
      .where((record) => _focusOverlapsPeriod(record, selectedPeriod))
      .take(limit)
      .toList();
  final remainingLimit = limit - selectedRecords.length;
  if (remainingLimit > 0) {
    selectedRecords.addAll(
      records
          .where((record) => !_focusOverlapsPeriod(record, selectedPeriod))
          .take(remainingLimit),
    );
  }
  selectedRecords.sort((left, right) => right.startMs.compareTo(left.startMs));
  return selectedRecords;
}

String _formatConflicts(List<ConflictInfo> conflicts) {
  if (conflicts.isEmpty) return '冲突信息: 暂无';
  final displayed = conflicts.take(20).toList();
  final lines = displayed
      .map((c) {
        final title =
            c.item['title'] ?? c.item['content'] ?? c.item['id'] ?? '';
        final other =
            c.conflictWith['title'] ??
            c.conflictWith['content'] ??
            c.conflictWith['id'] ??
            '';
        return '- ${c.type}: $title <-> $other';
      })
      .join('\n');
  return '冲突信息（展示 ${displayed.length}/${conflicts.length} 条）:\n$lines';
}

String _formatTeams(List<Team> teams) {
  if (teams.isEmpty) return '团队协作: 暂无';
  final displayed = teams.take(20).toList();
  final lines = displayed
      .map((t) => '- ${t.name} | ID: ${t.uuid} | 成员: ${t.memberCount}')
      .join('\n');
  return '团队协作（展示 ${displayed.length}/${teams.length} 个）:\n$lines';
}

String _formatTimeZone(DateTime value) {
  final offset = value.timeZoneOffset;
  final sign = offset.isNegative ? '-' : '+';
  final absOffset = offset.abs();
  final hours = absOffset.inHours.toString().padLeft(2, '0');
  final minutes = (absOffset.inMinutes % 60).toString().padLeft(2, '0');
  return 'UTC$sign$hours:$minutes ${value.timeZoneName}';
}

String _formatEpochMillis(int value) {
  return _formatDateTime(DateTime.fromMillisecondsSinceEpoch(value));
}

String _formatDateTime(DateTime value) {
  return AppTimeFormats.fullDateTime(value.toLocal());
}

String _formatDate(DateTime value) {
  return AppTimeFormats.date(value.toLocal());
}

String _formatCompactDate(DateTime value) {
  return AppTimeFormats.dayKey(value.toLocal());
}
