part of 'todo_section_widget.dart';

List<TodoItem> _relatedRecurrenceOccurrences(
  TodoItem current,
  List<TodoItem> todos,
) {
  final seriesId = current.recurrenceSeriesId;
  if (seriesId == null || seriesId.isEmpty) return <TodoItem>[current];
  return todos
      .where((todo) => !todo.isDeleted && todo.recurrenceSeriesId == seriesId)
      .toList()
    ..sort(
      (a, b) => (a.createdDate ?? a.createdAt).compareTo(
        b.createdDate ?? b.createdAt,
      ),
    );
}

Set<String> _focusRecordTodoIds(TodoItem current, List<TodoItem> todos) {
  final seriesId = current.recurrenceSeriesId;
  if (seriesId == null || seriesId.isEmpty) return <String>{current.id};
  return <String>{
    current.id,
    ...todos
        .where((todo) => todo.recurrenceSeriesId == seriesId)
        .map((todo) => todo.id),
  };
}

int _focusedRecurrencePeriodCount(
  TodoItem current,
  List<TodoItem> todos,
  List<PomodoroRecord> records,
) {
  final seriesId = current.recurrenceSeriesId;
  if (seriesId == null || seriesId.isEmpty) {
    return records.isEmpty ? 0 : 1;
  }

  final occurrences = <TodoItem>[
    current,
    ...todos.where(
      (todo) => todo.id != current.id && todo.recurrenceSeriesId == seriesId,
    ),
  ];
  final occurrenceById = <String, TodoItem>{
    for (final occurrence in occurrences) occurrence.id: occurrence,
  };
  final occurrenceByStartDay = <String, TodoItem>{};
  for (final occurrence in occurrences) {
    final dayKey = _localDayKey(occurrence.createdDate ?? occurrence.createdAt);
    final existing = occurrenceByStartDay[dayKey];
    if (existing == null ||
        (occurrence.recurrence != RecurrenceType.none &&
            existing.recurrence == RecurrenceType.none)) {
      occurrenceByStartDay[dayKey] = occurrence;
    }
  }

  final periodKeys = <String>{};
  for (final record in records) {
    final boundOccurrence = occurrenceById[record.todoUuid];
    if (boundOccurrence != null &&
        _recordStartsInsideOccurrence(record, boundOccurrence)) {
      periodKeys.add(boundOccurrence.id);
      continue;
    }

    final datedOccurrence =
        occurrenceByStartDay[_localDayKey(record.startTime)];
    if (datedOccurrence != null) {
      periodKeys.add(datedOccurrence.id);
      continue;
    }

    periodKeys.add(
      boundOccurrence?.id ?? 'date:${_localDayKey(record.startTime)}',
    );
  }
  return periodKeys.length;
}

bool _recordStartsInsideOccurrence(PomodoroRecord record, TodoItem occurrence) {
  final occurrenceStart = occurrence.createdDate ?? occurrence.createdAt;
  final occurrenceEnd = occurrence.dueDate?.millisecondsSinceEpoch;
  if (occurrenceEnd == null) {
    return _localDayKey(record.startTime) == _localDayKey(occurrenceStart);
  }
  return record.startTime >= occurrenceStart &&
      record.startTime <= occurrenceEnd;
}

String _localDayKey(int millisecondsSinceEpoch) {
  final local = DateTime.fromMillisecondsSinceEpoch(
    millisecondsSinceEpoch,
    isUtc: true,
  ).toLocal();
  return '${local.year}-${local.month}-${local.day}';
}

extension _TodoEditScreenActions on TodoEditScreenState {
  Future<bool> _persistCurrentTodo({required bool closeAfterSave}) async {
    if (_saving) return false;
    if (_titleCtrl.text.trim().isEmpty) {
      AppSnackBars.showSnackBar(
        context,
        const SnackBar(content: Text('请输入待办内容')),
      );
      return false;
    }
    if (_recurrence == RecurrenceType.customDays &&
        (_customDays == null || _customDays! < 1)) {
      AppSnackBars.showSnackBar(
        context,
        const SnackBar(content: Text('自定义重复间隔至少为 1 天')),
      );
      return false;
    }
    if (!_hasUnsavedChanges) {
      if (mounted && closeAfterSave) Navigator.pop(context, false);
      return true;
    }
    if (_preserveLegacyTiming &&
        _dueDate != null &&
        !_dueDate!.isAfter(_createdDate)) {
      AppSnackBars.showSnackBar(
        context,
        const SnackBar(content: Text('结束时间必须晚于开始时间')),
      );
      return false;
    }
    final normalizedTime = TodoItem.normalizeTimeForEdit(
      selectedDate: _createdDate,
      dueDate: _dueDate,
      isDateOnly: _isAllDay,
      preserveExistingTiming: _preserveLegacyTiming,
    );
    if (_recurrence != RecurrenceType.none && normalizedTime.start == null) {
      AppSnackBars.showSnackBar(
        context,
        const SnackBar(content: Text('重复待办需要先设置首次完成日期')),
      );
      return false;
    }
    final normalizedStart = normalizedTime.start;
    final normalizedDue = normalizedTime.due;
    final seriesId = TodoRecurrenceSeriesEditService.seriesIdFor(_editingTodo);
    if (_isWholeSeriesEdit) {
      if (seriesId == null || widget.onEditorSave == null) {
        AppSnackBars.showSnackBar(
          context,
          const SnackBar(content: Text('当前入口无法安全保存整个系列，请从待办列表重新打开')),
        );
        return false;
      }
      final confirmed = await _confirmWholeSeriesEdit(
        seriesId: seriesId,
        normalizedStart: normalizedStart,
        normalizedDue: normalizedDue,
      );
      if (!confirmed || !mounted) return false;
    }
    final baselinesById = {
      for (final item in _editorTodos) item.id: _copyTodo(item),
    };
    final stagedTodos = _editorTodos.map(_copyTodo).toList();
    final todoIndex = stagedTodos.indexWhere(
      (item) => item.id == _editingTodo.id,
    );
    if (todoIndex < 0) return false;
    final todo = stagedTodos[todoIndex];
    final startShift = normalizedStart == null
        ? Duration.zero
        : normalizedStart.difference(_originalCreatedDate);
    final calendarDayDelta = normalizedStart == null
        ? 0
        : TodoRecurrenceSeriesEditService.calendarDayDelta(
            _originalCreatedDate,
            normalizedStart,
          );
    final editedDuration = normalizedStart == null || normalizedDue == null
        ? null
        : normalizedDue.difference(normalizedStart);
    final recurrenceEndDateChanged =
        _recurrenceEndDate?.millisecondsSinceEpoch !=
        todo.recurrenceEndDate?.millisecondsSinceEpoch;

    if (seriesId != null && seriesId.isNotEmpty) {
      final originalStartMs = _originalCreatedDate.millisecondsSinceEpoch;
      for (final occurrence in stagedTodos) {
        if (occurrence.id == todo.id ||
            occurrence.isDeleted ||
            !TodoRecurrenceSeriesEditService.belongsToSeries(
              occurrence,
              seriesId,
            ) ||
            (!_isWholeSeriesEdit &&
                (occurrence.createdDate ?? occurrence.createdAt) <
                    originalStartMs)) {
          continue;
        }

        final occurrenceStart = DateTime.fromMillisecondsSinceEpoch(
          occurrence.createdDate ?? occurrence.createdAt,
          isUtc: true,
        ).toLocal();
        final shiftedStart = occurrenceStart.add(startShift);
        final recurrenceEndDay = _recurrenceEndDate == null
            ? null
            : DateTime(
                _recurrenceEndDate!.year,
                _recurrenceEndDate!.month,
                _recurrenceEndDate!.day,
              );
        final shiftedDay = DateTime(
          shiftedStart.year,
          shiftedStart.month,
          shiftedStart.day,
        );
        // 循环结束日期是系列规则的一部分，即使用户选择“只修改本期”，
        // 结束日期之后的已物化实例也必须删除；否则存储层下次滚动时仍
        // 会把它们视为系列成员。其它字段仍遵循“修改后续周期”开关。
        if (!_isWholeSeriesEdit &&
            recurrenceEndDateChanged &&
            recurrenceEndDay != null &&
            shiftedDay.isAfter(recurrenceEndDay)) {
          occurrence.isDeleted = true;
          occurrence.recurrence = RecurrenceType.none;
          occurrence.markAsChanged();
          continue;
        }
        if (!_appliesToFutureOccurrences && !_isWholeSeriesEdit) continue;
        if (!_isWholeSeriesEdit && _recurrence == RecurrenceType.none) {
          occurrence.isDeleted = true;
          occurrence.recurrence = RecurrenceType.none;
          occurrence.markAsChanged();
          continue;
        }
        occurrence.title = _titleCtrl.text;
        occurrence.createdDate = normalizedStart == null
            ? null
            : shiftedStart.millisecondsSinceEpoch;
        occurrence.dueDate = editedDuration == null
            ? null
            : _isAllDay
            ? DateTime(
                shiftedStart.year,
                shiftedStart.month,
                shiftedStart.day,
                23,
                59,
              )
            : shiftedStart.add(editedDuration);
        if (!_isWholeSeriesEdit) {
          if (occurrence.recurrence != RecurrenceType.none) {
            occurrence.recurrence = _recurrence;
          }
          occurrence.customIntervalDays = _customDays;
          occurrence.recurrenceEndDate = _recurrenceEndDate;
        } else if (calendarDayDelta != 0 &&
            occurrence.recurrenceEndDate != null) {
          occurrence.recurrenceEndDate =
              TodoRecurrenceSeriesEditService.shiftCalendarDate(
                occurrence.recurrenceEndDate!,
                calendarDayDelta,
              );
        }
        occurrence.remark = _remarkCtrl.text.trim().isEmpty
            ? null
            : _remarkCtrl.text.trim();
        occurrence.groupId = _selectedGroupId;
        occurrence.reminderMinutes = _reminderMinutes;
        occurrence.teamUuid = _selectedTeamUuid;
        occurrence.collabType = _collabType;
        occurrence.isAllDay = _isAllDay;
        occurrence.markAsChanged();
      }
    }

    todo.title = _titleCtrl.text;
    final wasDone = todo.isDone;
    if (!_isWholeSeriesEdit) todo.isDone = _isDone;
    todo.createdDate = normalizedStart?.millisecondsSinceEpoch;
    todo.dueDate = normalizedDue;
    if (!_isWholeSeriesEdit) {
      todo.recurrence = _recurrence;
      if (_recurrence != RecurrenceType.none &&
          (todo.recurrenceSeriesId == null ||
              todo.recurrenceSeriesId!.isEmpty)) {
        todo.recurrenceSeriesId = todo.id;
      }
      todo.customIntervalDays = _customDays;
      todo.recurrenceEndDate = _recurrenceEndDate;
    } else {
      todo.recurrenceSeriesId ??= seriesId;
      if (calendarDayDelta != 0 && todo.recurrenceEndDate != null) {
        todo.recurrenceEndDate =
            TodoRecurrenceSeriesEditService.shiftCalendarDate(
              todo.recurrenceEndDate!,
              calendarDayDelta,
            );
      }
    }
    todo.remark = _remarkCtrl.text.trim().isEmpty
        ? null
        : _remarkCtrl.text.trim();
    todo.groupId = _selectedGroupId;
    todo.reminderMinutes = _reminderMinutes;
    todo.teamUuid = _selectedTeamUuid;
    todo.collabType = _collabType;
    todo.isAllDay = _isAllDay;
    todo.markAsChanged();

    final changedTodos = stagedTodos
        .where(
          (item) =>
              item.version !=
              _editorTodos
                  .firstWhere((previous) => previous.id == item.id)
                  .version,
        )
        .toList(growable: false);
    final saveBaselines = <String, TodoItem>{
      for (final item in changedTodos) item.id: baselinesById[item.id]!,
    };
    final expectedSeriesMembership = <String, Set<String>>{};
    if (_isWholeSeriesEdit && seriesId != null) {
      final members = TodoRecurrenceSeriesEditService.activeMembers(
        _editorTodos,
        seriesId,
      );
      saveBaselines.addEntries(
        members.map((member) => MapEntry(member.id, baselinesById[member.id]!)),
      );
      expectedSeriesMembership[seriesId] = members
          .map((member) => member.id)
          .toSet();
    }

    var folderSyncCommitted = false;
    _mutateState(() => _saving = true);
    try {
      final reviewGuard = await _reviewFixedScheduleDeadlines(
        changedTodos: changedTodos,
        baselines: baselinesById,
      );
      if (!mounted ||
          (changedTodos.any((after) {
                final before = baselinesById[after.id];
                return before != null &&
                    TodoDeadlineFixedScheduleReviewService.deadlineChanged(
                      before,
                      after,
                    ) &&
                    !after.isDeleted &&
                    !after.isDone &&
                    !after.isSkipped;
              }) &&
              reviewGuard == null)) {
        return false;
      }
      if (reviewGuard != null && widget.onEditorSave == null) {
        throw StateError('当前入口无法安全校验关联固定日程，请从待办列表重新打开后保存。');
      }

      if (_syncFolderToTeam &&
          _selectedGroupId != null &&
          _selectedTeamUuid != null) {
        final groups = _editorGroups.map(_copyGroup).toList();
        final idx = groups.indexWhere((g) => g.id == _selectedGroupId);
        if (idx != -1) {
          final groupBaseline = _copyGroup(groups[idx]);
          groups[idx].teamUuid = _selectedTeamUuid;
          final team = _teams
              .where((t) => t.uuid == _selectedTeamUuid)
              .firstOrNull;
          if (team != null) groups[idx].teamName = team.name;
          groups[idx].markAsChanged();
          if (widget.onEditorGroupsSave == null) {
            await widget.onGroupsChanged(groups);
          } else {
            await widget.onEditorGroupsSave!(
              [groups[idx]],
              {groupBaseline.id: groupBaseline},
            );
          }
          _editorGroups = groups;
          _rebuildAvailableGroupIndex();
          folderSyncCommitted = true;
          _syncFolderToTeam = false;
        }
      }
      final TodoEditorSaveResult result;
      if (widget.onEditorSave == null) {
        if (_isWholeSeriesEdit) {
          throw StateError('当前入口无法安全保存整个系列');
        }
        await widget.onTodosChanged(stagedTodos);
        result = const TodoEditorSaveResult();
      } else {
        result = await widget.onEditorSave!(
          changedTodos,
          saveBaselines,
          expectedSeriesMembership: expectedSeriesMembership.isEmpty
              ? null
              : expectedSeriesMembership,
          expectedFixedScheduleTodoIds: reviewGuard?.todoIds,
          expectedFixedScheduleBaselines: reviewGuard?.schedules,
        );
      }
      if (!mounted) return false;
      _editorTodos = stagedTodos;
      _editingTodo = todo;
      _loadEditorFields(todo);
      if (!wasDone && _isDone) {
        final completionCallback = widget.onTodoCompletionCommitted;
        if (completionCallback == null) {
          PomodoroSyncService().sendStopSignal(todoUuid: todo.id);
        } else {
          completionCallback(todo.id);
        }
      }
      if (result.warnings.isNotEmpty) {
        AppSnackBars.showSnackBar(
          context,
          SnackBar(content: Text('待办已保存；${result.warnings.join('；')}')),
        );
      }
      if (closeAfterSave && result.warnings.isEmpty) {
        Navigator.pop(context, true);
      }
      return true;
    } catch (error) {
      if (mounted) {
        final details = error is StateError ? error.message : error;
        final message = folderSyncCommitted
            ? '文件夹已更新；待办保存失败，修改仍保留：$details'
            : _syncFolderToTeam &&
                  _selectedGroupId != null &&
                  _selectedTeamUuid != null
            ? '文件夹同步失败；待办尚未保存，修改仍保留：$details'
            : '待办保存失败，修改仍保留：$details';
        AppSnackBars.showSnackBar(context, SnackBar(content: Text(message)));
      }
      return false;
    } finally {
      if (mounted) _mutateState(() => _saving = false);
    }
  }

  Future<bool> _ensureEditorAccountCurrent() async {
    final username = widget.username.trim();
    final currentUsername = (await StorageService.getCurrentUsername())?.trim();
    final switched = username == 'default'
        ? currentUsername != null &&
              currentUsername.isNotEmpty &&
              currentUsername != 'default'
        : currentUsername != username;
    if (username.isEmpty || switched) {
      throw StateError('账户已切换，无法复核关联固定日程；请重新打开待办。');
    }
    return true;
  }

  Future<_TodoFixedScheduleReviewGuard?> _reviewFixedScheduleDeadlines({
    required List<TodoItem> changedTodos,
    required Map<String, TodoItem> baselines,
  }) async {
    final changedIds = changedTodos
        .where((after) {
          final before = baselines[after.id];
          return before != null &&
              TodoDeadlineFixedScheduleReviewService.deadlineChanged(
                before,
                after,
              ) &&
              !after.isDeleted &&
              !after.isDone &&
              !after.isSkipped;
        })
        .map((todo) => todo.id)
        .toSet();
    if (changedIds.isEmpty) return null;

    for (var attempt = 0; attempt < 3; attempt++) {
      await _ensureEditorAccountCurrent();
      final schedules = await StorageService.getFixedSchedulesByRelatedTodos(
        widget.username.trim(),
        changedIds,
      );
      await _ensureEditorAccountCurrent();
      final review = TodoDeadlineFixedScheduleReviewService.build(
        changedTodos: changedTodos,
        baselines: baselines,
        schedules: schedules,
        now: _now,
      );
      if (review.needsReview) {
        if (!mounted) return null;
        final confirmed = await showTodoDeadlineFixedScheduleReviewDialog(
          context,
          review,
        );
        if (!mounted || confirmed != true) return null;
      }

      await _ensureEditorAccountCurrent();
      final freshSchedules =
          await StorageService.getFixedSchedulesByRelatedTodos(
            widget.username.trim(),
            changedIds,
          );
      await _ensureEditorAccountCurrent();
      if (TodoDeadlineFixedScheduleReviewService.sameScheduleSnapshot(
        schedules,
        freshSchedules,
      )) {
        return _TodoFixedScheduleReviewGuard(
          todoIds: changedIds,
          schedules: freshSchedules,
        );
      }
    }

    throw StateError('关联固定日程连续发生变化，暂未保存；请重试复核。');
  }

  /// 设计文档 4.3：将当前循环待办加入习惯追踪。
  Future<void> _addToHabitTracking() async {
    final seriesId = _editingTodo.recurrenceSeriesId ?? _editingTodo.id;
    final already = await HabitRepository.getActiveGoals();
    if (!mounted) return;
    if (already.any((g) => g.sourceIds.contains(seriesId))) {
      AppSnackBars.showSnackBar(
        context,
        const SnackBar(content: Text('该循环待办已加入习惯追踪')),
      );
      return;
    }

    final confirmed = await showAppDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('转为独立习惯追踪'),
        content: Text(
          '确定将循环待办「${_editingTodo.title}」转为习惯吗？\n\n'
          '• 将导入其周期规则和历史完成记录为习惯打卡；\n'
          '• 原循环待办系列将移入回收站，今后打卡独立在习惯模块中进行，漏打卡不会在待办中显示逾期。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('转为习惯'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final goal = await HabitRepository.createGoalFromSeries(
      todo: _editingTodo,
      username: widget.username,
    );
    if (!mounted) return;
    if (goal == null) {
      AppSnackBars.showSnackBar(
        context,
        const SnackBar(content: Text('转为习惯失败，请稍后重试')),
      );
      return;
    }
    AppSnackBars.showSnackBar(
      context,
      SnackBar(content: Text('已转为独立习惯：${goal.name}')),
    );
    Navigator.of(context).pop(true);
  }

  Future<void> _save() async {
    await _persistCurrentTodo(closeAfterSave: true);
  }

  Future<bool> _confirmWholeSeriesEdit({
    required String seriesId,
    required DateTime? normalizedStart,
    required DateTime? normalizedDue,
  }) async {
    final occurrences = TodoRecurrenceSeriesEditService.activeMembers(
      _editorTodos,
      seriesId,
    );
    final counts = TodoRecurrenceSeriesEditService.countMembers(
      _editorTodos,
      seriesId,
      now: _now,
    );
    if (counts.total == 0) return false;
    final dateOrTimeChanged =
        normalizedStart?.millisecondsSinceEpoch !=
            _originalCreatedDate.millisecondsSinceEpoch ||
        normalizedDue?.millisecondsSinceEpoch !=
            _editingTodo.dueDate?.millisecondsSinceEpoch ||
        _isAllDay != _editingTodo.isDateOnly ||
        _preserveLegacyTiming != _editingTodo.hasLegacyTiming;
    final startShift = normalizedStart == null
        ? Duration.zero
        : normalizedStart.difference(_originalCreatedDate);
    final editedDuration = normalizedStart == null || normalizedDue == null
        ? null
        : normalizedDue.difference(normalizedStart);
    final datePattern = _isAllDay ? 'M月d日' : 'M月d日 HH:mm';
    String previewRange(TodoItem occurrence) {
      final start = DateTime.fromMillisecondsSinceEpoch(
        occurrence.createdDate ?? occurrence.createdAt,
        isUtc: true,
      ).toLocal();
      final newStart = start.add(startShift);
      final oldEnd = occurrence.dueDate?.toLocal();
      final newEnd = editedDuration == null
          ? null
          : _isAllDay
          ? DateTime(newStart.year, newStart.month, newStart.day, 23, 59)
          : newStart.add(editedDuration);
      final oldLabel = _dateFormat(datePattern).format(start);
      final newLabel = _dateFormat(datePattern).format(newStart);
      if (_isAllDay) return '$oldLabel → $newLabel';
      final oldRange = oldEnd == null
          ? oldLabel
          : '$oldLabel–${_dateFormat(datePattern).format(oldEnd)}';
      final newRange = newEnd == null
          ? newLabel
          : '$newLabel–${_dateFormat(datePattern).format(newEnd)}';
      return '$oldRange → $newRange';
    }

    final result = await showAppDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('确认应用到整个系列'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('本次修改会应用到 ${counts.total} 期。'),
                const SizedBox(height: 10),
                Text(
                  '历史 ${counts.historical} · 今天 ${counts.current} · 未来 ${counts.future}',
                ),
                const SizedBox(height: 4),
                Text('已完成 ${counts.completed} · 已跳过 ${counts.skipped}，状态保持不变'),
                if (dateOrTimeChanged && occurrences.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Text(
                    '日期变化基准：${_dateFormat(datePattern).format(_originalCreatedDate)} 这期',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  const SizedBox(height: 6),
                  _buildSeriesDatePreviewRow(
                    '首期',
                    previewRange(occurrences.first),
                  ),
                  if (occurrences.length > 1)
                    _buildSeriesDatePreviewRow(
                      '末期',
                      previewRange(occurrences.last),
                    ),
                ],
                const SizedBox(height: 14),
                Text(
                  '重复规则保持不变。已有规划块、时间日志和专注记录保留原时间。',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text('应用到 ${counts.total} 期'),
          ),
        ],
      ),
    );
    return result == true;
  }

  Widget _buildSeriesDatePreviewRow(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 42,
          child: Text(
            label,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(child: Text(value)),
      ],
    ),
  );

  Future<void> _deleteCurrentTodo() async {
    final confirmed = await showAppDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('删除待办'),
        content: const Text('确定要删除这条待办吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('删除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final stagedTodos = _editorTodos.map(_copyTodo).toList();
    final index = stagedTodos.indexWhere((todo) => todo.id == _editingTodo.id);
    if (index < 0) return;
    final baseline = _copyTodo(_editingTodo);
    stagedTodos[index].isDeleted = true;
    stagedTodos[index].hasConflict = false;
    stagedTodos[index].serverVersionData = null;
    stagedTodos[index].markAsChanged();
    _mutateState(() => _saving = true);
    try {
      final TodoEditorSaveResult result;
      if (widget.onEditorSave == null) {
        await widget.onTodosChanged(stagedTodos);
        result = const TodoEditorSaveResult();
      } else {
        result = await widget.onEditorSave!(
          [stagedTodos[index]],
          {baseline.id: baseline},
        );
      }
      if (result.warnings.isNotEmpty && mounted) {
        AppSnackBars.showSnackBar(
          context,
          SnackBar(content: Text('待办已删除；${result.warnings.join('；')}')),
        );
      }
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) {
        final details = error is StateError ? error.message : error;
        AppSnackBars.showSnackBar(
          context,
          SnackBar(content: Text('删除失败，待办仍保留：$details')),
        );
      }
    } finally {
      if (mounted) _mutateState(() => _saving = false);
    }
  }

  Future<void> _requestExit() async {
    if (_saving || _allowExit || _exitPromptOpen || !_hasUnsavedChanges) {
      return;
    }
    _exitPromptOpen = true;
    FocusScope.of(context).unfocus();
    try {
      final action = await showAppDialog<_OccurrenceSwitchAction>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('保留这次修改？'),
          content: Text('“${_editingTodo.title}”有尚未保存的内容。'),
          actions: [
            TextButton(
              onPressed: () =>
                  Navigator.pop(dialogContext, _OccurrenceSwitchAction.cancel),
              child: const Text('继续编辑'),
            ),
            TextButton(
              onPressed: () =>
                  Navigator.pop(dialogContext, _OccurrenceSwitchAction.discard),
              child: const Text('放弃修改'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.pop(dialogContext, _OccurrenceSwitchAction.save),
              child: const Text('保存并退出'),
            ),
          ],
        ),
      );
      if (!mounted ||
          action == null ||
          action == _OccurrenceSwitchAction.cancel) {
        return;
      }
      if (action == _OccurrenceSwitchAction.save) {
        await _persistCurrentTodo(closeAfterSave: true);
        return;
      }
      _mutateState(() => _allowExit = true);
      await WidgetsBinding.instance.endOfFrame;
      if (mounted) await Navigator.of(context).maybePop();
    } finally {
      _exitPromptOpen = false;
    }
  }

  Future<void> _switchToRelatedOccurrence(TodoItem occurrence) async {
    if (_saving) return;
    if (occurrence.id == _editingTodo.id) return;
    FocusScope.of(context).unfocus();
    if (_hasUnsavedChanges) {
      final action = await showAppDialog<_OccurrenceSwitchAction>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('切换循环期次'),
          content: const Text('当前期有尚未保存的修改，要先保存再切换吗？'),
          actions: [
            TextButton(
              onPressed: () =>
                  Navigator.pop(dialogContext, _OccurrenceSwitchAction.cancel),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () =>
                  Navigator.pop(dialogContext, _OccurrenceSwitchAction.discard),
              child: const Text('放弃修改'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.pop(dialogContext, _OccurrenceSwitchAction.save),
              child: const Text('保存并切换'),
            ),
          ],
        ),
      );
      if (!mounted ||
          action == null ||
          action == _OccurrenceSwitchAction.cancel) {
        return;
      }
      if (action == _OccurrenceSwitchAction.save) {
        final saved = await _persistCurrentTodo(closeAfterSave: false);
        if (!mounted || !saved) return;
      }
    }

    _mutateState(() {
      final next = _editorTodos.firstWhere(
        (todo) => todo.id == occurrence.id,
        orElse: () => occurrence,
      );
      _editingTodo = next;
      _loadEditorFields(next);
      _syncFolderToTeam = false;
      _relatedPlanBlocks = [];
      _focusRecords = [];
      _totalFocusSeconds = 0;
      _focusedPeriodCount = 0;
      _isLoadingPlans = true;
      _isLoadingRecords = true;
    });
    _loadRelatedPlans();
    _loadFocusRecords();
  }

  void _loadEditorFields(TodoItem todo) {
    _loadingEditorFields = true;
    try {
      _titleCtrl.text = todo.title;
      _remarkCtrl.text = todo.remark ?? '';
      _isDone = todo.isDone;
      _createdDate = DateTime.fromMillisecondsSinceEpoch(
        todo.createdDate ?? todo.createdAt,
        isUtc: true,
      ).toLocal();
      _originalCreatedDate = _createdDate;
      _dueDate = todo.dueDate;
      _recurrence = todo.recurrence;
      _customDays = todo.customIntervalDays;
      _customDaysCtrl.text = _customDays?.toString() ?? '';
      _lastObservedTitle = _titleCtrl.text;
      _lastObservedRemark = _remarkCtrl.text;
      _lastObservedCustomDays = _customDaysCtrl.text;
      _recurrenceEndDate = todo.recurrenceEndDate;
      _isAllDay = todo.isDateOnly;
      _preserveLegacyTiming = todo.hasLegacyTiming;
      _selectedGroupId = todo.groupId;
      _reminderMinutes = todo.reminderMinutes ?? 5;
      _selectedTeamUuid = todo.teamUuid;
      _collabType = todo.collabType;
    } finally {
      _loadingEditorFields = false;
    }
  }

  bool get _hasUnsavedChanges {
    final normalizedTime = TodoItem.normalizeTimeForEdit(
      selectedDate: _createdDate,
      dueDate: _dueDate,
      isDateOnly: _isAllDay,
      preserveExistingTiming: _preserveLegacyTiming,
    );
    final todo = _editingTodo;
    final editedRemark = _remarkCtrl.text.trim().isEmpty
        ? null
        : _remarkCtrl.text.trim();
    final savedRemark = todo.remark?.trim().isEmpty ?? true
        ? null
        : todo.remark!.trim();
    return _titleCtrl.text != todo.title ||
        (!_isWholeSeriesEdit && _isDone != todo.isDone) ||
        normalizedTime.start?.millisecondsSinceEpoch != todo.createdDate ||
        normalizedTime.due?.millisecondsSinceEpoch !=
            todo.dueDate?.millisecondsSinceEpoch ||
        (!_isWholeSeriesEdit &&
            (_recurrence != todo.recurrence ||
                _customDays != todo.customIntervalDays ||
                (_recurrence == RecurrenceType.customDays &&
                    _customDaysCtrl.text.trim() !=
                        (todo.customIntervalDays?.toString() ?? '')) ||
                _recurrenceEndDate?.millisecondsSinceEpoch !=
                    todo.recurrenceEndDate?.millisecondsSinceEpoch)) ||
        editedRemark != savedRemark ||
        _selectedGroupId != todo.groupId ||
        _reminderMinutes != (todo.reminderMinutes ?? 5) ||
        _selectedTeamUuid != todo.teamUuid ||
        _collabType != todo.collabType ||
        _syncFolderToTeam ||
        _isAllDay != todo.isDateOnly;
  }
}
