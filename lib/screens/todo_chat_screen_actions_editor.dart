part of 'todo_chat_screen.dart';

// ignore_for_file: annotate_overrides, unused_element, unused_element_parameter

mixin _TodoChatActionEditor on _TodoChatScreenStateBase {
  Future<void> _editAction(AiTodoAction action) async {
    final sourceAction = action;
    action = action.copy();
    final titleCtrl = TextEditingController(text: action.title ?? '');
    final remarkCtrl = TextEditingController(text: action.remark ?? '');
    final startCtrl = TextEditingController(text: action.startTime ?? '');
    final dueCtrl = TextEditingController(text: action.dueDate ?? '');
    final dateCtrl = TextEditingController(text: action.date ?? '');
    final locationCtrl = TextEditingController(text: action.location ?? '');
    final durationCtrl = TextEditingController(
      text: action.durationMinutes?.toString() ?? '',
    );
    final reminderCtrl = TextEditingController(
      text: action.isFixedScheduleAction
          ? action.reminderMinutesList.join(',')
          : action.reminderMinutes?.toString() ?? '',
    );
    final colorCtrl = TextEditingController(text: action.color ?? '');
    final statusCtrl = TextEditingController(text: action.status ?? '');
    final initialTagUuids = List<String>.from(action.tagUuids);
    var selectedTagUuids = List<String>.from(action.tagUuids);
    final sourceTags = widget.pomodoroTags.isNotEmpty
        ? widget.pomodoroTags
        : await PomodoroService.getTags();
    if (!mounted) return;
    final availableTags = sourceTags
        .where((tag) => !tag.isDeleted && !tag.isArchived)
        .toList();
    const personalTeamChoice = '__personal__';
    const unselectedTeamChoice = '__select_team__';
    final hasTeamReference =
        action.teamUuid?.trim().isNotEmpty == true ||
        action.teamName?.trim().isNotEmpty == true;
    final resolvedTeam = AiTeamBindingResolver.resolveReference(
      name: action.teamName,
      uuid: action.teamUuid,
      teams: _teams,
    );
    var teamChoice =
        resolvedTeam?.uuid ??
        (hasTeamReference ? unselectedTeamChoice : personalTeamChoice);
    var recurrence = action.recurrence;
    var isAllDay = action.isAllDay;
    var timeMode =
        action.timeMode ??
        (isAllDay
            ? TodoTimeMode.dateOnly.name
            : action.dueDate == null
            ? TodoTimeMode.unscheduled.name
            : TodoTimeMode.deadline.name);
    var recurrenceScope = action.recurrenceScope;
    final scopeTarget = _findExistingTodo(action.todoId);
    final rawTargetRecurrence = scopeTarget?['recurrence'];
    final targetHasRecurrence = switch (rawTargetRecurrence) {
      num value => value.toInt() != RecurrenceType.none.index,
      String value =>
        value.trim().isNotEmpty &&
            value.trim() != 'none' &&
            value.trim() != '0',
      _ => false,
    };
    final targetSeriesId = scopeTarget?['recurrenceSeriesId']
        ?.toString()
        .trim();
    final canChooseWholeSeriesScope =
        action.type == AiTodoActionType.updateTodo &&
        (targetSeriesId?.isNotEmpty == true || targetHasRecurrence);
    if (!canChooseWholeSeriesScope && recurrenceScope == 'series') {
      recurrenceScope = 'occurrence';
    }
    final initialRecurrence = recurrence;
    final initialIsAllDay = isAllDay;
    final initialTimeMode = timeMode;
    final initialRemarkText = remarkCtrl.text;
    final initialDateText = dateCtrl.text;
    final initialLocationText = locationCtrl.text;
    final initialStartText = startCtrl.text;
    final initialDueText = dueCtrl.text;
    final initialReminderText = reminderCtrl.text;
    final initialTitleText = titleCtrl.text;

    await showAppDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Row(
            children: [
              _buildActionBadge(action),
              const SizedBox(width: 8),
              const Text('编辑执行内容'),
            ],
          ),
          content: SizedBox(
            width: MediaQuery.sizeOf(context).width * 0.86,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_usesTitle(action))
                    _editField(titleCtrl, _titleLabel(action)),
                  if (action.type == AiTodoActionType.createCountdown)
                    DropdownButtonFormField<String>(
                      initialValue: teamChoice,
                      decoration: const InputDecoration(labelText: '绑定团队'),
                      items: [
                        const DropdownMenuItem(
                          value: personalTeamChoice,
                          child: Text('仅自己可见'),
                        ),
                        if (teamChoice == unselectedTeamChoice)
                          const DropdownMenuItem(
                            value: unselectedTeamChoice,
                            enabled: false,
                            child: Text('请选择本地团队'),
                          ),
                        for (final team in _teams)
                          DropdownMenuItem(
                            value: team.uuid,
                            child: Text(team.name),
                          ),
                      ],
                      onChanged: (value) => setDialogState(() {
                        teamChoice = value ?? personalTeamChoice;
                      }),
                    ),
                  if (_usesRemark(action)) _editField(remarkCtrl, '备注'),
                  if (action.isFixedScheduleAction)
                    _editField(dateCtrl, '日程日期', hint: 'YYYY-MM-DD'),
                  if (action.isFixedScheduleAction)
                    _editField(locationCtrl, '地点'),
                  if (_usesStartTime(action))
                    _editField(
                      startCtrl,
                      _startTimeLabel(action),
                      hint: 'YYYY-MM-DD HH:mm',
                    ),
                  if (_usesDueTime(action))
                    _editField(
                      dueCtrl,
                      _dueTimeLabel(action),
                      hint: 'YYYY-MM-DD HH:mm',
                    ),
                  if (_usesDuration(action))
                    _editField(
                      durationCtrl,
                      '时长（分钟）',
                      keyboardType: TextInputType.number,
                    ),
                  if (_usesReminder(action))
                    _editField(
                      reminderCtrl,
                      '提前提醒（分钟）',
                      keyboardType: TextInputType.number,
                    ),
                  if (_usesColor(action))
                    _editField(colorCtrl, '颜色', hint: '#3B82F6'),
                  if (_usesStatus(action))
                    _editField(
                      statusCtrl,
                      '状态',
                      hint: 'completed 或 interrupted',
                    ),
                  if (_usesTags(action)) ...[
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        '番茄标签',
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                    ),
                    const SizedBox(height: 6),
                    if (availableTags.isEmpty)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          selectedTagUuids.isEmpty
                              ? '暂无可选标签'
                              : '已有 ${selectedTagUuids.length} 个不可选标签，保存时会保留',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      )
                    else
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        children: [
                          for (final tag in availableTags)
                            FilterChip(
                              label: Text(tag.name),
                              selected: selectedTagUuids.contains(tag.uuid),
                              onSelected: (selected) => setDialogState(() {
                                if (selected) {
                                  if (!selectedTagUuids.contains(tag.uuid)) {
                                    selectedTagUuids.add(tag.uuid);
                                  }
                                } else {
                                  selectedTagUuids.remove(tag.uuid);
                                }
                              }),
                            ),
                        ],
                      ),
                    if (selectedTagUuids.any(
                      (uuid) => !availableTags.any((tag) => tag.uuid == uuid),
                    ))
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          '存在不可选标签，保存时会保留',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    const SizedBox(height: 8),
                  ],
                  if (action.isTodoAction || action.isFixedScheduleAction) ...[
                    const SizedBox(height: 8),
                    if (action.isTodoAction)
                      DropdownButtonFormField<String>(
                        initialValue: timeMode,
                        decoration: const InputDecoration(labelText: '待办时间语义'),
                        items: const [
                          DropdownMenuItem(
                            value: 'unscheduled',
                            child: Text('未安排'),
                          ),
                          DropdownMenuItem(
                            value: 'dateOnly',
                            child: Text('日期内完成'),
                          ),
                          DropdownMenuItem(
                            value: 'deadline',
                            child: Text('截止时刻'),
                          ),
                        ],
                        onChanged: (value) => setDialogState(() {
                          timeMode = value ?? TodoTimeMode.unscheduled.name;
                          isAllDay = timeMode == TodoTimeMode.dateOnly.name;
                        }),
                      ),
                    if (action.type == AiTodoActionType.updateTodo &&
                        recurrenceScope == 'series')
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Text(
                            '整个系列编辑会保留当前重复规则；需要修改频率时请切换到“本期及以后”。',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                      )
                    else
                      DropdownButtonFormField<String>(
                        initialValue: recurrence,
                        decoration: const InputDecoration(labelText: '循环'),
                        items: const [
                          DropdownMenuItem(value: 'none', child: Text('不循环')),
                          DropdownMenuItem(value: 'daily', child: Text('每天')),
                          DropdownMenuItem(value: 'weekly', child: Text('每周')),
                          DropdownMenuItem(value: 'monthly', child: Text('每月')),
                          DropdownMenuItem(value: 'yearly', child: Text('每年')),
                          DropdownMenuItem(
                            value: 'weekdays',
                            child: Text('工作日'),
                          ),
                        ],
                        onChanged: (value) =>
                            setDialogState(() => recurrence = value ?? 'none'),
                      ),
                    if (action.mutatesExistingItem ||
                        (action.isFixedScheduleAction &&
                            action.type !=
                                AiTodoActionType.createFixedSchedule))
                      DropdownButtonFormField<String>(
                        initialValue: recurrenceScope,
                        decoration: const InputDecoration(labelText: '循环作用范围'),
                        items: [
                          DropdownMenuItem(
                            value: 'occurrence',
                            child: Text('仅本期'),
                          ),
                          DropdownMenuItem(
                            value: 'future',
                            child: Text('本期及以后'),
                          ),
                          if (canChooseWholeSeriesScope)
                            const DropdownMenuItem(
                              value: 'series',
                              child: Text('整个系列'),
                            ),
                        ],
                        onChanged: (value) => setDialogState(
                          () => recurrenceScope = value ?? 'occurrence',
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () async {
                if (action.type == AiTodoActionType.createCountdown &&
                    teamChoice == unselectedTeamChoice) {
                  AppSnackBars.showSnackBar(
                    context,
                    const SnackBar(content: Text('请先选择本地团队或仅自己可见')),
                  );
                  return;
                }
                setState(() {
                  if (_usesTitle(action)) {
                    action.title = _nullIfBlank(titleCtrl.text);
                  }
                  if (action.type == AiTodoActionType.createCountdown) {
                    if (teamChoice == personalTeamChoice) {
                      action.teamUuid = null;
                      action.teamName = null;
                    } else {
                      for (final team in _teams) {
                        if (team.uuid == teamChoice) {
                          action.teamUuid = team.uuid;
                          action.teamName = team.name;
                          break;
                        }
                      }
                    }
                    action.hasTeamUuid = true;
                  }
                  if (action.type == AiTodoActionType.updateHabit) {
                    final fields = Map<String, dynamic>.from(
                      action.metadata['habitUpdateFields'] is Map
                          ? action.metadata['habitUpdateFields'] as Map
                          : const <String, dynamic>{},
                    );
                    if (fields.containsKey('name') ||
                        titleCtrl.text != initialTitleText) {
                      final name = _nullIfBlank(titleCtrl.text);
                      if (name == null) {
                        fields.remove('name');
                      } else {
                        fields['name'] = name;
                      }
                    }
                    action.metadata['habitUpdateFields'] = fields;
                  }
                  action.remark = _nullIfBlank(remarkCtrl.text);
                  action.date = _nullIfBlank(dateCtrl.text);
                  action.location = _nullIfBlank(locationCtrl.text);
                  action.startTime = _nullIfBlank(startCtrl.text);
                  action.dueDate = _nullIfBlank(dueCtrl.text);
                  action.durationMinutes = int.tryParse(durationCtrl.text);
                  if (action.isFixedScheduleAction) {
                    action.reminderMinutesList = reminderCtrl.text
                        .split(',')
                        .map((value) => int.tryParse(value.trim()))
                        .whereType<int>()
                        .toList();
                  } else {
                    action.reminderMinutes = int.tryParse(reminderCtrl.text);
                  }
                  action.color = _nullIfBlank(colorCtrl.text);
                  action.status = _nullIfBlank(statusCtrl.text);
                  action.tagUuids = List<String>.from(selectedTagUuids);
                  action.hasTagUuids =
                      action.hasTagUuids ||
                      selectedTagUuids.length != initialTagUuids.length ||
                      selectedTagUuids.any(
                        (uuid) => !initialTagUuids.contains(uuid),
                      );
                  action.recurrence = recurrence;
                  action.isAllDay = isAllDay;
                  action.timeMode = timeMode;
                  action.recurrenceScope = recurrenceScope;
                  action.hasRemark =
                      action.hasRemark || remarkCtrl.text != initialRemarkText;
                  action.hasDate =
                      action.hasDate || dateCtrl.text != initialDateText;
                  action.hasLocation =
                      action.hasLocation ||
                      locationCtrl.text != initialLocationText;
                  action.hasStartTime =
                      action.hasStartTime || startCtrl.text != initialStartText;
                  action.hasDueDate =
                      action.hasDueDate || dueCtrl.text != initialDueText;
                  if (action.isFixedScheduleAction) {
                    action.hasReminderMinutesList =
                        action.hasReminderMinutesList ||
                        reminderCtrl.text != initialReminderText;
                  } else {
                    action.hasReminderMinutes =
                        action.hasReminderMinutes ||
                        reminderCtrl.text != initialReminderText;
                  }
                  action.hasTimeMode =
                      action.hasTimeMode ||
                      timeMode != initialTimeMode ||
                      isAllDay != initialIsAllDay;
                  action.hasIsAllDay =
                      action.hasIsAllDay ||
                      isAllDay != initialIsAllDay ||
                      timeMode != initialTimeMode;
                  action.hasRecurrence =
                      action.hasRecurrence || recurrence != initialRecurrence;
                  if (action.type == AiTodoActionType.updateTodo &&
                      recurrenceScope == 'series') {
                    action
                      ..hasRecurrence = false
                      ..hasCustomIntervalDays = false
                      ..hasRecurrenceEndDate = false;
                  }
                });
                try {
                  await _commitTodoActionDraft(sourceAction, action);
                  if (ctx.mounted) Navigator.pop(ctx);
                } catch (error) {
                  if (context.mounted) {
                    AppSnackBars.showSnackBar(
                      context,
                      SnackBar(content: Text('保存失败，草稿仍保留：$error')),
                    );
                  }
                }
              },
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _editField(
    TextEditingController controller,
    String label, {
    String? hint,
    TextInputType? keyboardType,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          border: const OutlineInputBorder(),
          isDense: true,
        ),
      ),
    );
  }

  String? _nullIfBlank(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  String _countdownTeamLabel(AiTodoAction action) {
    final team = AiTeamBindingResolver.resolveReference(
      name: action.teamName,
      uuid: action.teamUuid,
      teams: _teams,
    );
    if (team != null) return team.name;
    if (action.teamName?.trim().isNotEmpty == true ||
        action.teamUuid?.trim().isNotEmpty == true) {
      return '需重新选择团队';
    }
    return '仅自己可见';
  }

  bool _usesTitle(AiTodoAction action) =>
      action.type != AiTodoActionType.completeTodo &&
      action.type != AiTodoActionType.skipTodo &&
      action.type != AiTodoActionType.deleteTodo &&
      action.type != AiTodoActionType.cancelFixedSchedule &&
      action.type != AiTodoActionType.deleteFixedSchedule &&
      action.type != AiTodoActionType.deleteTimeLog &&
      action.type != AiTodoActionType.stopPomodoro &&
      action.type != AiTodoActionType.completeCountdown &&
      action.type != AiTodoActionType.deleteCountdown &&
      action.type != AiTodoActionType.deleteTodoGroup &&
      action.type != AiTodoActionType.deletePomodoroTag &&
      action.type != AiTodoActionType.deleteHabit;

  bool _usesRemark(AiTodoAction action) =>
      (action.isTodoAction && action.type != AiTodoActionType.skipTodo) ||
      action.isFixedScheduleAction ||
      action.isTimeLogAction ||
      action.isPlanBlockAction;

  bool _usesStartTime(AiTodoAction action) =>
      (action.isTodoAction && action.type != AiTodoActionType.skipTodo) ||
      action.isFixedScheduleAction ||
      action.isTimeLogAction ||
      action.isPlanBlockAction;

  bool _usesDueTime(AiTodoAction action) =>
      (action.isTodoAction && action.type != AiTodoActionType.skipTodo) ||
      action.isFixedScheduleAction ||
      action.isTimeLogAction ||
      action.isCountdownAction ||
      action.isPlanBlockAction;

  bool _usesDuration(AiTodoAction action) =>
      action.isTimeLogAction ||
      action.isPlanBlockAction ||
      action.type == AiTodoActionType.startPomodoro;

  bool _usesReminder(AiTodoAction action) =>
      (action.isTodoAction && action.type != AiTodoActionType.skipTodo) ||
      action.isFixedScheduleAction ||
      action.isPlanBlockAction;

  bool _usesColor(AiTodoAction action) => action.isPomodoroTagAction;

  bool _usesStatus(AiTodoAction action) =>
      action.type == AiTodoActionType.stopPomodoro;

  bool _usesTags(AiTodoAction action) =>
      action.isTimeLogAction || action.isPomodoroAction;

  String _titleLabel(AiTodoAction action) {
    if (action.isHabitAction) return '习惯名称';
    if (action.isFixedScheduleAction) return '日程标题';
    if (action.isTodoGroupAction) return '分类名称';
    if (action.isPomodoroTagAction) return '标签名称';
    if (action.isCountdownAction) return '倒计时标题';
    if (action.isTimeLogAction) return '专注记录标题';
    return '标题';
  }

  String _startTimeLabel(AiTodoAction action) {
    if (action.isTimeLogAction) return '开始时间';
    return '开始时间';
  }

  String _dueTimeLabel(AiTodoAction action) {
    if (action.isFixedScheduleAction) return '结束时间';
    if (action.isCountdownAction) return '目标时间';
    if (action.isTimeLogAction) return '结束时间';
    return '截止时间';
  }

  String _getMutationHint(AiTodoAction action) {
    switch (action.type) {
      case AiTodoActionType.completeTodo:
        return '标记为已完成';
      case AiTodoActionType.skipTodo:
        return '仅跳过这一期，后续期次继续';
      case AiTodoActionType.deleteTodo:
        return '移动到已删除';
      case AiTodoActionType.createFixedSchedule:
        return '新增固定日程';
      case AiTodoActionType.updateFixedSchedule:
        return '更新固定日程';
      case AiTodoActionType.cancelFixedSchedule:
        return '取消固定日程';
      case AiTodoActionType.deleteFixedSchedule:
        return '删除固定日程';
      case AiTodoActionType.rescheduleTodo:
        return '调整时间安排';
      case AiTodoActionType.bulkRescheduleTodo:
        return '批量调整时间安排';
      case AiTodoActionType.updateTodo:
        return '更新待办内容';
      case AiTodoActionType.categorizeTodo:
        return '从 [${_getTodoCurrentFolderName(action.todoId)}] 移动';
      case AiTodoActionType.planTodos:
        return '生成计划待办';
      case AiTodoActionType.createPlanBlock:
        return action.newTodoTitle != null
            ? '新建待办“${action.newTodoTitle}”并安排时间块'
            : '安排到具体时间块';
      case AiTodoActionType.updatePlanBlock:
        return '修改规划块';
      case AiTodoActionType.deletePlanBlock:
        return '删除规划块';
      case AiTodoActionType.reschedulePlanBlocks:
        return '重排规划块';
      case AiTodoActionType.skipPlanBlock:
        return '跳过规划块';
      case AiTodoActionType.startPlanBlockPomodoro:
        return '准备规划番茄钟';
      case AiTodoActionType.splitTodo:
        return action.sourceTodoIds.isEmpty
            ? '拆分为子任务'
            : '从 [${action.sourceTodoIds.join(', ')}] 拆分';
      case AiTodoActionType.mergeTodos:
        return action.sourceTodoIds.isEmpty
            ? '合并为新待办'
            : '合并 [${action.sourceTodoIds.join(', ')}]';
      case AiTodoActionType.createTimeLog:
        return '新增专注记录';
      case AiTodoActionType.updateTimeLog:
        return '修改专注记录';
      case AiTodoActionType.deleteTimeLog:
        return '删除专注记录';
      case AiTodoActionType.startPomodoro:
        return '开始番茄钟';
      case AiTodoActionType.stopPomodoro:
        return '停止当前番茄钟';
      case AiTodoActionType.createCountdown:
        return '新增倒计时';
      case AiTodoActionType.updateCountdown:
        return '修改倒计时';
      case AiTodoActionType.completeCountdown:
        return '标记倒计时达成';
      case AiTodoActionType.deleteCountdown:
        return '删除倒计时';
      case AiTodoActionType.createTodoGroup:
        return '新增待办分类';
      case AiTodoActionType.updateTodoGroup:
        return '修改待办分类';
      case AiTodoActionType.deleteTodoGroup:
        return '删除待办分类';
      case AiTodoActionType.createPomodoroTag:
        return '新增番茄标签';
      case AiTodoActionType.updatePomodoroTag:
        return '修改番茄标签';
      case AiTodoActionType.deletePomodoroTag:
        return '删除番茄标签';
      case AiTodoActionType.createHabit:
        return '新增习惯目标';
      case AiTodoActionType.updateHabit:
        return '更新习惯目标';
      case AiTodoActionType.deleteHabit:
        return '软删除习惯目标';
      case AiTodoActionType.createTodo:
      case AiTodoActionType.unknown:
        return '';
    }
  }

  Widget _buildChangeSummary(AiTodoAction action) {
    if (action.isFixedScheduleAction) {
      return _buildFixedScheduleChangeSummary(action);
    }
    if (action.type == AiTodoActionType.updateHabit) {
      final rawFields = action.metadata['habitUpdateFields'];
      if (rawFields is! Map || rawFields.isEmpty) {
        return const SizedBox.shrink();
      }
      final rows = _formatHabitActionSummary(action).split(' · ');
      return _buildMutationRowsSummary(rows);
    }
    if (!action.mutatesExistingItem || !action.isTodoAction) {
      return const SizedBox.shrink();
    }
    final existing = _findExistingTodo(action.todoId);
    if (existing == null) return const SizedBox.shrink();

    final rows = <String>[];
    void addRow(String label, String before, String after) {
      if (before == after || after.isEmpty) return;
      rows.add('$label: $before -> $after');
    }

    addRow('标题', '${existing['title'] ?? ''}', action.title ?? '');
    addRow('备注', '${existing['remark'] ?? ''}', action.remark ?? '');
    if (action.hasStartTime ||
        action.hasDueDate ||
        action.hasTimeMode ||
        action.hasIsAllDay) {
      final beforeTime = _formatTodoTimeRange(
        existing['startTime']?.toString(),
        existing['endTime']?.toString(),
        existing['isAllDay'] == true,
      );
      final afterTime = _formatTodoTimeRange(
        action.startTime ?? existing['startTime']?.toString(),
        action.dueDate ?? existing['endTime']?.toString(),
        action.timeMode == TodoTimeMode.dateOnly.name ||
            (action.timeMode == null &&
                (action.hasIsAllDay
                    ? action.isAllDay
                    : existing['isAllDay'] == true)),
      );
      addRow('时间', beforeTime, afterTime);
    }
    if (action.groupId != null ||
        action.type == AiTodoActionType.categorizeTodo) {
      addRow(
        '分类',
        _getGroupName(existing['groupId']?.toString()),
        _getGroupName(action.groupId),
      );
    }
    if (action.reminderMinutes != null) {
      addRow(
        '提醒',
        '提前${existing['reminderMinutes'] ?? 5}分钟',
        '提前${action.reminderMinutes}分钟',
      );
    }
    if (action.type == AiTodoActionType.completeTodo) {
      addRow('状态', existing['isDone'] == true ? '已完成' : '未完成', '已完成');
    }
    if (action.type == AiTodoActionType.skipTodo) {
      addRow('状态', '待处理', '已跳过本期');
    }
    if (action.type == AiTodoActionType.deleteTodo) {
      addRow('删除', existing['isDeleted'] == true ? '已删除' : '未删除', '已删除');
    }
    final rawRecurrence = existing['recurrence'];
    final isRecurringTodo = rawRecurrence is num
        ? rawRecurrence.toInt() != RecurrenceType.none.index
        : rawRecurrence?.toString().trim().isNotEmpty == true &&
              rawRecurrence?.toString().trim() != 'none' &&
              rawRecurrence?.toString().trim() != '0';
    if (existing['recurrenceSeriesId']?.toString().isNotEmpty == true ||
        isRecurringTodo) {
      rows.add(
        action.recurrenceScope == 'series'
            ? '范围: 整个系列（执行前会再次确认期次数量）'
            : action.appliesToFutureOccurrences
            ? '范围: 本期及以后'
            : '范围: 仅本期',
      );
    }
    if (action.metadata['wholeSeriesScopeDowngraded'] == true) {
      rows.add('范围提示: 用户请求未明确整个系列，已先限制为仅本期');
    }

    if (rows.isEmpty) return const SizedBox.shrink();
    return _buildMutationRowsSummary(rows);
  }

  Widget _buildMutationRowsSummary(List<String> rows) {
    if (rows.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(left: 28, top: 6),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest
              .withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: rows
              .map(
                (row) => Text(
                  row,
                  style: TextStyle(
                    fontSize: 11,
                    color: Theme.of(context).colorScheme.onSurface
                        .withValues(alpha: 0.65),
                  ),
                ),
              )
              .toList(),
        ),
      ),
    );
  }

  Widget _buildFixedScheduleChangeSummary(AiTodoAction action) {
    if (action.type == AiTodoActionType.createFixedSchedule) {
      return const SizedBox.shrink();
    }
    final existing = _fixedSchedules
        .where((item) => item.id == action.scheduleId)
        .firstOrNull;
    if (existing == null) return const SizedBox.shrink();
    final rows = <String>[];
    if (action.title?.trim().isNotEmpty == true &&
        action.title!.trim() != existing.title) {
      rows.add('标题: ${existing.title} -> ${action.title!.trim()}');
    }
    if (action.hasDate && action.date != existing.date) {
      rows.add('日期: ${existing.date} -> ${action.date ?? '待确认'}');
    }
    if (action.hasStartTime || action.hasDueDate) {
      final existingAction = AiTodoAction(
        type: AiTodoActionType.updateFixedSchedule,
        date: existing.date,
        startTime: existing.startTime == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(existing.startTime!)
                  .toIso8601String(),
        dueDate: existing.endTime == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(existing.endTime!)
                  .toIso8601String(),
      );
      final nextAction = AiTodoAction(
        type: AiTodoActionType.updateFixedSchedule,
        date: action.hasDate ? action.date : existing.date,
        startTime: action.hasStartTime
            ? action.startTime
            : existingAction.startTime,
        dueDate: action.hasDueDate ? action.dueDate : existingAction.dueDate,
      );
      rows.add(
        '时间: ${_formatScheduleActionTime(existingAction)} -> ${_formatScheduleActionTime(nextAction)}',
      );
    }
    if (action.hasLocation) {
      rows.add('地点: ${existing.location ?? '无'} -> ${action.location ?? '无'}');
    }
    if (action.type == AiTodoActionType.cancelFixedSchedule) {
      rows.add('状态: ${existing.status.name} -> cancelled');
    }
    if (action.type == AiTodoActionType.deleteFixedSchedule) {
      rows.add('删除: 未删除 -> 已删除');
    }
    if (existing.recurrenceSeriesId?.isNotEmpty == true) {
      rows.add(action.appliesToFutureOccurrences ? '范围: 本期及以后' : '范围: 仅本期');
    }
    if (rows.isEmpty) return const SizedBox.shrink();
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(left: 28, top: 6),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: rows
              .map(
                (row) => Text(
                  row,
                  style: TextStyle(
                    fontSize: 11,
                    color: colorScheme.onSurface.withValues(alpha: 0.65),
                  ),
                ),
              )
              .toList(),
        ),
      ),
    );
  }

  Map<String, dynamic>? _findExistingTodo(String? todoId) {
    if (todoId == null) return null;
    for (final todo in widget.todos) {
      if (todo['id'] == todoId) return todo;
    }
    return null;
  }

  String _getGroupName(String? groupId) {
    if (groupId == null || groupId.isEmpty) return '默认分类';
    return widget.todoGroups
        .firstWhere((g) => g.id == groupId, orElse: () => TodoGroup(name: '未知'))
        .name;
  }

  bool _isDangerousAction(AiTodoAction action) {
    return action.type == AiTodoActionType.deleteTodo ||
        action.type == AiTodoActionType.skipTodo ||
        action.type == AiTodoActionType.deleteTimeLog ||
        action.type == AiTodoActionType.cancelFixedSchedule ||
        action.type == AiTodoActionType.deleteFixedSchedule ||
        (action.type == AiTodoActionType.updateFixedSchedule &&
            action.status == 'cancelled') ||
        action.type == AiTodoActionType.stopPomodoro ||
        action.type == AiTodoActionType.deleteCountdown ||
        action.type == AiTodoActionType.completeCountdown ||
        action.type == AiTodoActionType.deleteTodoGroup ||
        action.type == AiTodoActionType.deletePomodoroTag ||
        action.type == AiTodoActionType.deleteHabit ||
        action.type == AiTodoActionType.deletePlanBlock ||
        action.type == AiTodoActionType.skipPlanBlock ||
        (action.type == AiTodoActionType.splitTodo &&
            action.deleteSourceTodos) ||
        (action.type == AiTodoActionType.mergeTodos &&
            action.deleteSourceTodos);
  }

  String _getDangerHint(AiTodoAction action) {
    switch (action.type) {
      case AiTodoActionType.deleteTodo:
        return '将删除已有待办，执行前请确认';
      case AiTodoActionType.skipTodo:
        return '只跳过此重复待办期次，不会完成或删除，也不会影响后续期次';
      case AiTodoActionType.cancelFixedSchedule:
        return '将取消已有日程，执行前请确认';
      case AiTodoActionType.deleteFixedSchedule:
        return '将删除已有日程，执行前请确认';
      case AiTodoActionType.updateFixedSchedule:
        return action.status == 'cancelled' ? '将取消已有日程，执行前请确认' : '';
      case AiTodoActionType.splitTodo:
        return '拆分后会删除原待办，执行前请确认';
      case AiTodoActionType.mergeTodos:
        return '合并后会删除源待办，执行前请确认';
      case AiTodoActionType.deleteTimeLog:
        return '将删除已有专注记录，执行前请确认';
      case AiTodoActionType.stopPomodoro:
        return '将停止当前番茄钟，执行前请确认';
      case AiTodoActionType.deleteCountdown:
        return '将删除已有倒计时，执行前请确认';
      case AiTodoActionType.completeCountdown:
        return '将标记倒计时达成，执行前请确认';
      case AiTodoActionType.deleteTodoGroup:
        return '将删除待办分类，执行前请确认';
      case AiTodoActionType.deletePomodoroTag:
        return '将删除番茄标签，执行前请确认';
      case AiTodoActionType.deleteHabit:
        return '将软删除此习惯及其规则版本，执行前请确认';
      case AiTodoActionType.deletePlanBlock:
        return '将删除规划块，执行前请确认';
      case AiTodoActionType.skipPlanBlock:
        return '将跳过规划块，执行前请确认';
      case AiTodoActionType.createTodo:
      case AiTodoActionType.updateTodo:
      case AiTodoActionType.completeTodo:
      case AiTodoActionType.createFixedSchedule:
      case AiTodoActionType.rescheduleTodo:
      case AiTodoActionType.bulkRescheduleTodo:
      case AiTodoActionType.categorizeTodo:
      case AiTodoActionType.planTodos:
      case AiTodoActionType.createPlanBlock:
      case AiTodoActionType.updatePlanBlock:
      case AiTodoActionType.reschedulePlanBlocks:
      case AiTodoActionType.startPlanBlockPomodoro:
      case AiTodoActionType.createHabit:
      case AiTodoActionType.updateHabit:
      case AiTodoActionType.unknown:
      case AiTodoActionType.createTimeLog:
      case AiTodoActionType.updateTimeLog:
      case AiTodoActionType.startPomodoro:
      case AiTodoActionType.createCountdown:
      case AiTodoActionType.updateCountdown:
      case AiTodoActionType.createTodoGroup:
      case AiTodoActionType.updateTodoGroup:
      case AiTodoActionType.createPomodoroTag:
      case AiTodoActionType.updatePomodoroTag:
        return '';
    }
  }
}
