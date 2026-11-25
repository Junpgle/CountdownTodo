part of 'todo_chat_screen.dart';

final RegExp _actionFeedbackLatinTokenPattern = RegExp(r'[a-z0-9]+');
final RegExp _actionFeedbackCjkTokenPattern = RegExp(r'[一-鿿]+');
final RegExp _habitReminderCamelCasePattern = RegExp(r'[A-Z]');
final RegExp _financeOptionLeadingPunctuationPattern = RegExp(
  r'^[^\u4e00-\u9fffA-Za-z0-9]+',
);

// ignore_for_file: annotate_overrides, unused_element, unused_element_parameter

mixin _TodoChatActions on _TodoChatScreenStateBase {
  String _formatTodoTimeRange(
    String? startTime,
    String? dueDate,
    bool isAllDay,
  ) {
    DateTime? start;
    DateTime? end;

    if (startTime != null && startTime.isNotEmpty) {
      start = DateTime.tryParse(startTime);
    }
    if (dueDate != null && dueDate.isNotEmpty) {
      end = DateTime.tryParse(dueDate);
    }

    if (start == null && end == null) return '未设置时间';

    String formatDateTime(DateTime dt, bool showDate, bool showTime) {
      if (showDate && showTime) {
        return AppTimeFormats.dateFormatter('MM/dd HH:mm').format(dt);
      } else if (showDate) {
        return AppTimeFormats.dateFormatter('MM/dd').format(dt);
      } else {
        return AppTimeFormats.dateFormatter('HH:mm').format(dt);
      }
    }

    bool sameDay(DateTime a, DateTime b) {
      return a.year == b.year && a.month == b.month && a.day == b.day;
    }

    if (isAllDay) {
      if (start != null && end != null && sameDay(start, end)) {
        return '全天 ${AppTimeFormats.dateFormatter('MM/dd').format(start)}';
      } else if (start != null && end != null) {
        final dateFormat = AppTimeFormats.dateFormatter('MM/dd');
        return '全天 ${dateFormat.format(start)} ~ ${dateFormat.format(end)}';
      } else if (start != null) {
        return '全天 ${AppTimeFormats.dateFormatter('MM/dd').format(start)}';
      } else if (end != null) {
        return '全天 ${AppTimeFormats.dateFormatter('MM/dd').format(end)}';
      }
    }

    if (start != null && end != null) {
      if (sameDay(start, end)) {
        final dateText = AppTimeFormats.dateFormatter('MM/dd').format(start);
        final timeFormat = AppTimeFormats.dateFormatter('HH:mm');
        final startText = timeFormat.format(start);
        final endText = timeFormat.format(end);
        return '$dateText $startText ~ $endText';
      } else {
        final dateTimeFormat = AppTimeFormats.dateFormatter('MM/dd HH:mm');
        return '${dateTimeFormat.format(start)} ~ ${dateTimeFormat.format(end)}';
      }
    } else if (start != null) {
      final showTime = start.hour != 0 || start.minute != 0;
      return '开始: ${formatDateTime(start, true, showTime)}';
    } else if (end != null) {
      final showTime = end.hour != 0 || end.minute != 0;
      return '截止: ${formatDateTime(end, true, showTime)}';
    }

    return '未设置时间';
  }

  String _formatScheduleActionTime(AiTodoAction action) {
    final existing = _fixedSchedules
        .where((item) => item.id == action.scheduleId)
        .firstOrNull;
    final dateValue = action.hasDate
        ? action.date
        : action.date ?? existing?.date;
    final startValue = action.hasStartTime
        ? action.startTime
        : action.startTime ??
              (existing?.startTime == null
                  ? null
                  : DateTime.fromMillisecondsSinceEpoch(existing!.startTime!)
                        .toIso8601String());
    final endValue = action.hasDueDate
        ? action.dueDate
        : action.dueDate ??
              (existing?.endTime == null
                  ? null
                  : DateTime.fromMillisecondsSinceEpoch(existing!.endTime!)
                        .toIso8601String());
    final date = dateValue?.trim();
    final start = DateTime.tryParse(startValue ?? '');
    final end = DateTime.tryParse(endValue ?? '');
    final day = date?.isNotEmpty == true
        ? date!
        : start == null
        ? '日期待定'
        : AppTimeFormats.dateFormatter('yyyy-MM-dd').format(start);
    if (start == null) return '$day 时间待定';
    final startText = AppTimeFormats.dateFormatter('HH:mm').format(start);
    if (end == null) return '$day $startText（结束待定）';
    return '$day $startText-${AppTimeFormats.dateFormatter('HH:mm').format(end)}';
  }

  String _formatHabitActionSummary(AiTodoAction action) {
    if (action.type == AiTodoActionType.deleteHabit) {
      return '软删除习惯目标及其规则';
    }
    if (action.type == AiTodoActionType.updateHabit) {
      final rawFields = action.metadata['habitUpdateFields'];
      if (rawFields is! Map || rawFields.isEmpty) return '修改习惯目标';
      final fields = Map<String, dynamic>.from(rawFields);
      final changes = <String>[];
      if (fields.containsKey('name')) changes.add('名称：${fields['name']}');
      if (fields.containsKey('icon')) changes.add('图标：${fields['icon']}');
      if (fields.containsKey('displayMode')) {
        changes.add('展示：${_habitDisplayModeLabel(fields['displayMode'])}');
      }
      if (fields.containsKey('defaultFocusMinutes')) {
        changes.add('默认专注：${fields['defaultFocusMinutes']} 分钟');
      }
      if (fields.containsKey('targetValue')) {
        final unit = fields['unit']?.toString().trim();
        changes.add(
          '目标：${fields['targetValue']}${unit?.isNotEmpty == true ? ' $unit' : ''}',
        );
      } else if (fields.containsKey('unit')) {
        changes.add('单位：${fields['unit']}');
      }
      if (fields.containsKey('durationMinutes')) {
        changes.add('时长：${fields['durationMinutes']} 分钟');
      }
      if (fields.containsKey('targetTimeMinute')) {
        final minute = int.tryParse(fields['targetTimeMinute'].toString());
        final time = minute == null
            ? fields['targetTimeMinute'].toString()
            : '${(minute ~/ 60).toString().padLeft(2, '0')}:${(minute % 60).toString().padLeft(2, '0')}';
        final comparison = fields['timeComparison'] == 'after'
            ? '之后'
            : fields['timeComparison'] == 'before'
            ? '之前'
            : '';
        changes.add('目标时间：$time$comparison');
      }
      if (fields.containsKey('timeComparison') &&
          !fields.containsKey('targetTimeMinute')) {
        changes.add(
          '比较规则：${fields['timeComparison'] == 'after' ? '之后' : '之前'}',
        );
      }
      if (fields.containsKey('timeToleranceMinutes')) {
        changes.add('容差：${fields['timeToleranceMinutes']} 分钟');
      }
      if (fields.containsKey('periodType')) {
        changes.add('周期：${_habitPeriodLabel(fields['periodType'])}');
      }
      if (fields.containsKey('weekdaysMask')) {
        final mask = int.tryParse(fields['weekdaysMask'].toString()) ?? 0;
        const weekdays = ['一', '二', '三', '四', '五', '六', '日'];
        final selectedDays = [
          for (var index = 0; index < weekdays.length; index++)
            if ((mask & (1 << index)) != 0) '周${weekdays[index]}',
        ];
        changes.add(
          '星期：${selectedDays.isEmpty ? '未指定' : selectedDays.join('、')}',
        );
      }
      if (fields.containsKey('customIntervalDays')) {
        changes.add('间隔：每${fields['customIntervalDays']}天');
      }
      if (fields.containsKey('dayBoundaryMinute')) {
        changes.add('日界：${fields['dayBoundaryMinute']} 分钟');
      }
      if (fields.containsKey('quickValues')) {
        final values = fields['quickValues'];
        changes.add('快捷值：${values is List ? values.join('、') : values}');
      }
      if (fields.containsKey('reminderPolicy')) {
        final policy = fields['reminderPolicy'];
        if (policy is Map) {
          final details = <String>[];
          final fixedTimes = policy['fixedTimes'] ?? policy['fixed_times'];
          if (fixedTimes is List) {
            final times = fixedTimes
                .map((value) {
                  final minute = int.tryParse(value.toString());
                  if (minute == null) return value.toString();
                  return '${(minute ~/ 60).toString().padLeft(2, '0')}:${(minute % 60).toString().padLeft(2, '0')}';
                })
                .join('、');
            details.add('时间 ${times.isEmpty ? '清空' : times}');
          }
          for (final entry in const {
            'progressReminder': '进度提醒',
            'nearEndReminder': '临近结束提醒',
            'dailySummaryReminder': '每日汇总提醒',
          }.entries) {
            final snakeKey = entry.key.replaceAllMapped(
              _habitReminderCamelCasePattern,
              (match) => '_${match.group(0)!.toLowerCase()}',
            );
            final value = policy.containsKey(entry.key)
                ? policy[entry.key]
                : policy[snakeKey];
            if (value != null) {
              details.add('${entry.value}${value == true ? '开' : '关'}');
            }
          }
          changes.add(details.isEmpty ? '更新提醒规则' : '提醒：${details.join('、')}');
        } else {
          changes.add('更新提醒规则');
        }
      }
      if (fields.containsKey('effectiveFromOption')) {
        changes.add(
          '生效范围：${_habitEffectiveFromLabel(fields['effectiveFromOption'])}',
        );
      } else if (const {
        'targetValue',
        'unit',
        'durationMinutes',
        'targetTimeMinute',
        'timeComparison',
        'timeToleranceMinutes',
        'periodType',
        'weekdaysMask',
        'customIntervalDays',
        'dayBoundaryMinute',
        'quickValues',
        'reminderPolicy',
      }.any(fields.containsKey)) {
        changes.add('生效范围：今天（默认）');
      }
      return changes.isEmpty ? '修改习惯目标' : changes.join(' · ');
    }

    final period = switch (action.habitPeriodType?.toLowerCase()) {
      'weekly' => '每周',
      'weekdays' => '工作日',
      'monthly' => '每月',
      'custom' || 'customdays' => '每${action.customIntervalDays ?? 1}天',
      _ => '每天',
    };
    final sourceType = action.habitSourceType?.toLowerCase();
    String target;
    switch (sourceType) {
      case 'quantitycheckin':
      case 'quantity':
        final value = action.targetValue;
        final valueText = value == null
            ? '数量目标'
            : value == value.roundToDouble()
            ? value.round().toString()
            : value.toStringAsFixed(1);
        target = action.unit?.trim().isNotEmpty == true
            ? '$valueText ${action.unit!.trim()}'
            : valueText;
      case 'durationcheckin':
      case 'pomodorotag':
        target = action.durationMinutes == null
            ? '时长目标'
            : '${action.durationMinutes} 分钟';
      case 'timecheckin':
        final minute = action.targetTimeMinute;
        final time = minute == null
            ? '时间点目标'
            : '${(minute ~/ 60).toString().padLeft(2, '0')}:${(minute % 60).toString().padLeft(2, '0')}';
        target = action.habitTimeComparison?.toLowerCase() == 'after'
            ? '$time 后'
            : '$time 前';
      case 'recurringtodo':
        target = '完成 1 次';
      default:
        target = '习惯目标';
    }
    return '$period · $target';
  }

  String _actionCardTitle(AiTodoAction action) {
    if (action.type == AiTodoActionType.updateHabit ||
        action.type == AiTodoActionType.deleteHabit) {
      final habitUuid = action.habitUuid?.trim();
      if (habitUuid == null || habitUuid.isEmpty) {
        return '习惯目标缺少ID';
      }
      for (final goal in _habitGoals) {
        if (goal.uuid == habitUuid && !goal.isDeleted) return goal.name;
      }
      return '无法核对的习惯目标';
    }
    final title = action.title?.trim();
    if (title?.isNotEmpty == true) return title!;
    if (action.isHabitAction) {
      return switch (action.type) {
        AiTodoActionType.deleteHabit => '删除习惯',
        AiTodoActionType.updateHabit => '修改习惯',
        _ => '未命名习惯',
      };
    }
    if (action.isFixedScheduleAction) return '未命名日程';
    return '未命名待办';
  }

  String _habitDisplayModeLabel(Object? value) => switch (value?.toString()) {
    'habitOnly' => '仅习惯',
    'todoOnly' => '仅待办',
    'both' => '习惯与待办',
    _ => value?.toString() ?? '未指定',
  };

  String _habitPeriodLabel(Object? value) => switch (value?.toString()) {
    'daily' => '每天',
    'weekly' => '每周',
    'weekdays' => '工作日',
    'monthly' => '每月',
    'custom' => '自定义周期',
    _ => value?.toString() ?? '未指定',
  };

  String _habitEffectiveFromLabel(Object? value) => switch (value?.toString()) {
    'today' => '今天',
    'nextPeriod' => '下个周期',
    'all' => '全部历史规则',
    _ => value?.toString() ?? '未指定',
  };

  String _getTodoCurrentFolderName(String? todoId) {
    if (todoId == null) return '未知';
    final matches = widget.todos.where((t) => t['id'] == todoId);
    if (matches.isEmpty) return '默认分类';
    final existing = matches.first;
    final gid = existing['groupId'] as String?;
    if (gid == null || gid.isEmpty) return '默认分类';
    return widget.todoGroups
        .firstWhere((g) => g.id == gid, orElse: () => TodoGroup(name: '未知'))
        .name;
  }

  String _getRecurrenceText(String recurrence) {
    switch (recurrence.toLowerCase()) {
      case 'daily':
        return '每天';
      case 'weekly':
        return '每周';
      case 'monthly':
        return '每月';
      case 'weekdays':
        return '工作日';
      default:
        return recurrence;
    }
  }

  Widget _buildMessageTodoActions(ChatMessage msg, bool isDark) {
    final activeActions = msg.todoActions!
        .where((action) => !action.isAdded && !action.isIgnored)
        .toList();
    if (activeActions.isEmpty) return const SizedBox.shrink();
    final hasExistingMutations = activeActions.any(
      (t) => t.mutatesExistingItem,
    );
    final hasPomodoroActions = activeActions.any((t) => t.isPomodoroAction);
    final hasTimeLogActions = activeActions.any((t) => t.isTimeLogAction);
    final hasCountdownActions = activeActions.any((t) => t.isCountdownAction);
    final hasTagActions = activeActions.any((t) => t.isPomodoroTagAction);
    final hasScheduleActions = activeActions.any(
      (t) => t.isFixedScheduleAction,
    );
    final hasHabitActions = activeActions.any((t) => t.isHabitAction);
    final onlyCreatingHabits = activeActions
        .where((t) => t.isHabitAction)
        .every((t) => t.type == AiTodoActionType.createHabit);
    final hasPlanActions = activeActions.any((t) => t.isPlanBlockAction);

    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      key: _todoActionPanelKeyFor(msg),
      padding: const EdgeInsets.only(top: 8),
      child: _IridescentActionPanel(
        isDark: isDark,
        child: Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: isDark
                ? colorScheme.surfaceContainerHighest.withValues(alpha: 0.24)
                : colorScheme.primaryContainer.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.02),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Row(
                  children: [
                    Icon(
                      Icons.add_task_outlined,
                      color: Theme.of(context).colorScheme.primary,
                      size: 16,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      hasPlanActions
                          ? '待确认规划操作'
                          : hasHabitActions
                          ? onlyCreatingHabits
                                ? '建议创建习惯'
                                : '建议管理习惯'
                          : hasPomodoroActions
                          ? '建议操作番茄钟'
                          : hasScheduleActions
                          ? '建议管理日程'
                          : hasTimeLogActions
                          ? '建议整理专注记录'
                          : hasCountdownActions
                          ? '建议整理倒计时'
                          : hasTagActions
                          ? '建议整理番茄标签'
                          : hasExistingMutations
                          ? '建议整理待办'
                          : '建议添加待办',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ],
                ),
              ),
              ...activeActions.asMap().entries.map((entry) {
                final todo = entry.value;

                final isSelected = todo.isSelected;
                final currentGroupId = todo.groupId;
                final startTime = todo.startTime;
                final dueDate = todo.dueDate;
                final isAllDay = todo.isAllDay;
                final recurrence = todo.recurrence;
                final timeStr = todo.isHabitAction
                    ? _formatHabitActionSummary(todo)
                    : todo.isFixedScheduleAction
                    ? _formatScheduleActionTime(todo)
                    : _formatTodoTimeRange(startTime, dueDate, isAllDay);

                return Container(
                  margin: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.05)
                        : Colors.white.withValues(alpha: 0.8),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          SizedBox(
                            width: 24,
                            height: 24,
                            child: Checkbox(
                              value: isSelected,
                              onChanged: (val) async {
                                try {
                                  await _updateTodoActionDraft(
                                    todo,
                                    (draft) => draft.isSelected = val == true,
                                  );
                                } catch (error) {
                                  if (mounted) {
                                    AppSnackBars.showSnackBar(
                                      context,
                                      SnackBar(content: Text('保存失败：$error')),
                                    );
                                  }
                                }
                              },
                            ),
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    _buildActionBadge(todo),
                                    Expanded(
                                      child: Text(
                                        _actionCardTitle(todo),
                                        style: const TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                                if (todo.mutatesExistingItem)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 2),
                                    child: Text(
                                      _getMutationHint(todo),
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: Colors.grey.withValues(
                                          alpha: 0.8,
                                        ),
                                        fontStyle: FontStyle.italic,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.edit_outlined, size: 18),
                            tooltip: '编辑执行内容',
                            onPressed: () => _editAction(todo),
                            visualDensity: VisualDensity.compact,
                          ),
                          IconButton(
                            icon: const Icon(Icons.close_rounded, size: 18),
                            tooltip: '忽略此操作',
                            onPressed: () => _ignoreAction(todo),
                            visualDensity: VisualDensity.compact,
                          ),
                        ],
                      ),
                      // 时间和循环信息
                      Padding(
                        padding: const EdgeInsets.only(left: 28, top: 4),
                        child: Row(
                          children: [
                            Icon(
                              todo.isHabitAction
                                  ? Icons.repeat_rounded
                                  : Icons.access_time,
                              size: 13,
                              color: Theme.of(context).colorScheme.onSurface
                                  .withValues(alpha: 0.5),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              timeStr,
                              style: TextStyle(
                                fontSize: 11,
                                color: Theme.of(context).colorScheme.onSurface
                                    .withValues(alpha: 0.5),
                              ),
                            ),
                            if (!todo.isHabitAction &&
                                recurrence != 'none') ...[
                              const SizedBox(width: 12),
                              Icon(
                                Icons.repeat,
                                size: 13,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                _getRecurrenceText(recurrence),
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Theme.of(context).colorScheme.primary,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      if (todo.type == AiTodoActionType.createCountdown)
                        Padding(
                          padding: const EdgeInsets.only(left: 28, top: 4),
                          child: Row(
                            children: [
                              Icon(
                                Icons.groups_outlined,
                                size: 13,
                                color: Theme.of(context).colorScheme.onSurface
                                    .withValues(alpha: 0.45),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '团队：${_countdownTeamLabel(todo)}',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Theme.of(context).colorScheme.onSurface
                                      .withValues(alpha: 0.6),
                                ),
                              ),
                            ],
                          ),
                        ),
                      if (todo.remark != null && todo.remark!.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(left: 28, top: 4),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                Icons.notes,
                                size: 13,
                                color: Theme.of(context).colorScheme.onSurface
                                    .withValues(alpha: 0.4),
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  todo.remark!,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurface
                                        .withValues(alpha: 0.6),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      if (todo.isFixedScheduleAction &&
                          todo.location?.isNotEmpty == true)
                        Padding(
                          padding: const EdgeInsets.only(left: 28, top: 4),
                          child: Row(
                            children: [
                              Icon(
                                Icons.location_on_outlined,
                                size: 13,
                                color: Theme.of(context).colorScheme.onSurface
                                    .withValues(alpha: 0.4),
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  todo.location!,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurface
                                        .withValues(alpha: 0.6),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      _buildClassificationMetadata(todo),
                      _buildChangeSummary(todo),
                      if (_isDangerousAction(todo))
                        Padding(
                          padding: const EdgeInsets.only(left: 28, top: 6),
                          child: Row(
                            children: [
                              Icon(
                                Icons.warning_amber_rounded,
                                size: 13,
                                color: Theme.of(context).colorScheme.error,
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  _getDangerHint(todo),
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Theme.of(context).colorScheme.error,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      if (todo.isTodoAction)
                        Padding(
                          padding: const EdgeInsets.only(left: 28, top: 6),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.primary
                                  .withValues(alpha: 0.05),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.folder_outlined,
                                  size: 13,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: DropdownButtonHideUnderline(
                                    child: DropdownButton<String?>(
                                      value:
                                          widget.todoGroups.any(
                                            (g) => g.id == currentGroupId,
                                          )
                                          ? currentGroupId
                                          : null,
                                      isDense: true,
                                      icon: const Icon(
                                        Icons.arrow_drop_down,
                                        size: 16,
                                      ),
                                      hint: const Text(
                                        '选择分类',
                                        style: TextStyle(fontSize: 11),
                                      ),
                                      items: [
                                        const DropdownMenuItem<String?>(
                                          value: null,
                                          child: Text(
                                            '默认分类',
                                            style: TextStyle(fontSize: 11),
                                          ),
                                        ),
                                        ...widget.todoGroups.map(
                                          (g) => DropdownMenuItem<String?>(
                                            value: g.id,
                                            child: Text(
                                              g.name,
                                              style: const TextStyle(
                                                fontSize: 11,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                      onChanged: (val) async {
                                        try {
                                          await _updateTodoActionDraft(todo, (
                                            draft,
                                          ) {
                                            draft.groupId = val;
                                            draft.hasGroupId = true;
                                          });
                                        } catch (error) {
                                          if (mounted) {
                                            AppSnackBars.showSnackBar(
                                              context,
                                              SnackBar(
                                                content: Text('保存失败：$error'),
                                              ),
                                            );
                                          }
                                        }
                                      },
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                );
              }),
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed:
                        msg.todoActions!.any(
                          (t) => t.isSelected && !t.isAdded && !t.isIgnored,
                        )
                        ? () => _addTodosForMessage(msg)
                        : null,
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 0),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.add_task, size: 16),
                        const SizedBox(width: 8),
                        Text(
                          '执行所选操作 (${activeActions.where((t) => t.isSelected).length})',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildClassificationMetadata(AiTodoAction action) {
    final priority = action.metadata['priorityLabel']?.toString();
    final rawTags = action.metadata['tags'];
    final tags = rawTags is List
        ? rawTags.map((e) => e.toString()).where((e) => e.isNotEmpty).toList()
        : const <String>[];
    if ((priority == null || priority.isEmpty) && tags.isEmpty) {
      return const SizedBox.shrink();
    }
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(left: 28, top: 6),
      child: Wrap(
        spacing: 6,
        runSpacing: 4,
        children: [
          if (priority != null && priority.isNotEmpty)
            _buildMiniMetaChip(Icons.flag_rounded, priority, Colors.orange),
          ...tags.map(
            (tag) => _buildMiniMetaChip(
              Icons.sell_outlined,
              tag,
              colorScheme.primary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMiniMetaChip(IconData icon, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionBadge(AiTodoAction action) {
    Color color;
    String label;
    switch (action.type) {
      case AiTodoActionType.createTodo:
        color = Colors.green;
        label = '新增';
        break;
      case AiTodoActionType.createHabit:
        color = Colors.deepPurple;
        label = '习惯';
        break;
      case AiTodoActionType.updateHabit:
        color = Colors.deepPurple;
        label = '改习惯';
        break;
      case AiTodoActionType.deleteHabit:
        color = Colors.red;
        label = '删习惯';
        break;
      case AiTodoActionType.completeTodo:
        color = Theme.of(context).colorScheme.primary;
        label = '完成';
        break;
      case AiTodoActionType.skipTodo:
        color = Theme.of(context).colorScheme.tertiary;
        label = '跳过本期';
        break;
      case AiTodoActionType.deleteTodo:
        color = Colors.red;
        label = '删除';
        break;
      case AiTodoActionType.createFixedSchedule:
        color = Colors.blue;
        label = '新日程';
        break;
      case AiTodoActionType.updateFixedSchedule:
        color = Colors.orange;
        label = '改日程';
        break;
      case AiTodoActionType.cancelFixedSchedule:
        color = Colors.orange;
        label = '取消日程';
        break;
      case AiTodoActionType.deleteFixedSchedule:
        color = Colors.red;
        label = '删日程';
        break;
      case AiTodoActionType.rescheduleTodo:
        color = Colors.purple;
        label = '改期';
        break;
      case AiTodoActionType.bulkRescheduleTodo:
        color = Colors.purple;
        label = '批改';
        break;
      case AiTodoActionType.updateTodo:
        color = action.recurrenceScope == 'series'
            ? Theme.of(context).colorScheme.tertiary
            : Colors.orange;
        label = action.recurrenceScope == 'series' ? '改系列' : '修改';
        break;
      case AiTodoActionType.categorizeTodo:
        color = Colors.orange;
        label = '整理';
        break;
      case AiTodoActionType.planTodos:
        color = Colors.teal;
        label = '规划';
        break;
      case AiTodoActionType.createPlanBlock:
        color = Colors.teal;
        label = '时间块';
        break;
      case AiTodoActionType.updatePlanBlock:
      case AiTodoActionType.reschedulePlanBlocks:
        color = Colors.teal;
        label = '改规划';
        break;
      case AiTodoActionType.deletePlanBlock:
        color = Colors.red;
        label = '删规划';
        break;
      case AiTodoActionType.skipPlanBlock:
        color = Colors.orange;
        label = '跳过';
        break;
      case AiTodoActionType.startPlanBlockPomodoro:
        color = Colors.redAccent;
        label = '准备专注';
        break;
      case AiTodoActionType.splitTodo:
        color = Colors.indigo;
        label = '拆分';
        break;
      case AiTodoActionType.mergeTodos:
        color = Colors.indigo;
        label = '合并';
        break;
      case AiTodoActionType.createTimeLog:
        color = Colors.cyan;
        label = '记录';
        break;
      case AiTodoActionType.updateTimeLog:
        color = Colors.orange;
        label = '改记录';
        break;
      case AiTodoActionType.deleteTimeLog:
        color = Colors.red;
        label = '删记录';
        break;
      case AiTodoActionType.startPomodoro:
        color = Colors.redAccent;
        label = '开始';
        break;
      case AiTodoActionType.stopPomodoro:
        color = Colors.grey;
        label = '停止';
        break;
      case AiTodoActionType.createCountdown:
        color = Colors.deepOrange;
        label = '倒计时';
        break;
      case AiTodoActionType.updateCountdown:
        color = Colors.orange;
        label = '改倒计时';
        break;
      case AiTodoActionType.completeCountdown:
        color = Colors.green;
        label = '达成';
        break;
      case AiTodoActionType.deleteCountdown:
        color = Colors.red;
        label = '删倒计时';
        break;
      case AiTodoActionType.createTodoGroup:
        color = Colors.green;
        label = '分类';
        break;
      case AiTodoActionType.updateTodoGroup:
        color = Colors.orange;
        label = '改分类';
        break;
      case AiTodoActionType.deleteTodoGroup:
        color = Colors.red;
        label = '删分类';
        break;
      case AiTodoActionType.createPomodoroTag:
        color = Colors.cyan;
        label = '标签';
        break;
      case AiTodoActionType.updatePomodoroTag:
        color = Colors.orange;
        label = '改标签';
        break;
      case AiTodoActionType.deletePomodoroTag:
        color = Colors.red;
        label = '删标签';
        break;
      case AiTodoActionType.unknown:
        color = Colors.grey;
        label = '操作';
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      margin: const EdgeInsets.only(right: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 9,
          color: color,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Future<void> _ignoreAction(AiTodoAction action) async {
    try {
      await _updateTodoActionDraft(action, (draft) {
        draft.isIgnored = true;
        draft.isSelected = false;
      });
      _recordIgnoreFeedback(action);
    } catch (error) {
      if (mounted) {
        AppSnackBars.showSnackBar(
          context,
          SnackBar(content: Text('保存失败：$error')),
        );
      }
    }
  }

  void _recordIgnoreFeedback(AiTodoAction action) {
    if (action.type != AiTodoActionType.categorizeTodo) return;
    final title = action.title ?? '';
    if (title.isEmpty) return;
    final kws = _extractActionKeywords(title);
    if (kws.isEmpty) return;
    if (action.groupId != null) {
      SuggestionFeedbackService.record(
        keywords: kws,
        suggestionType: 'group',
        suggestedValue: action.groupId!,
        accepted: false,
      );
    }
    final priority = action.metadata['priority'];
    if (priority != null) {
      SuggestionFeedbackService.record(
        keywords: kws,
        suggestionType: 'priority',
        suggestedValue: '$priority',
        accepted: false,
      );
    }
    final tags = action.metadata['tags'];
    if (tags is List) {
      for (final tag in tags) {
        SuggestionFeedbackService.record(
          keywords: kws,
          suggestionType: 'tag',
          suggestedValue: tag.toString(),
          accepted: false,
        );
      }
    }
  }

  List<String> _extractActionKeywords(String text) {
    final lower = text.toLowerCase();
    final tokens = <String>[];
    for (final m in _actionFeedbackLatinTokenPattern.allMatches(lower)) {
      if (m.group(0)!.length >= 2) tokens.add(m.group(0)!);
    }
    for (final m in _actionFeedbackCjkTokenPattern.allMatches(lower)) {
      final seg = m.group(0)!;
      for (int i = 0; i < seg.length; i++) {
        tokens.add(seg[i]);
      }
      for (int i = 0; i < seg.length - 1; i++) {
        tokens.add(seg.substring(i, i + 2));
      }
    }
    return tokens;
  }
}
