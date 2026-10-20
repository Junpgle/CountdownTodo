part of 'todo_section_widget.dart';

// ignore_for_file: annotate_overrides

class _TodoRecurrenceDateSlot {
  const _TodoRecurrenceDateSlot({required this.date, this.occurrenceIndex});

  final DateTime date;
  final int? occurrenceIndex;
}

class _TodoRecurrenceDateStructure {
  _TodoRecurrenceDateStructure._({
    required this.seriesId,
    required this.occurrences,
    required this.occurrenceStartEpochs,
    required this.occurrenceSlotIndexById,
    required this.recurrence,
    required this.customIntervalDays,
    required this.recurrenceEndDayEpoch,
    required this.slots,
    required this._projectedStart,
  });

  final String? seriesId;
  final List<TodoItem> occurrences;
  final List<int> occurrenceStartEpochs;
  final Map<String, int> occurrenceSlotIndexById;
  final RecurrenceType recurrence;
  final int? customIntervalDays;
  final int? recurrenceEndDayEpoch;
  final List<_TodoRecurrenceDateSlot> slots;
  DateTime _projectedStart;
  final List<DateTime> _projectedDates = <DateTime>[];
  bool _projectionExhausted = false;

  static _TodoRecurrenceDateStructure build({
    required String? seriesId,
    required List<TodoItem> occurrences,
    required TodoItem todo,
  }) {
    final slots = <_TodoRecurrenceDateSlot>[];
    final occurrenceStartEpochs = <int>[];
    final occurrenceSlotIndexById = <String, int>{};
    final currentStart = _startFor(todo);
    DateTime? previousStart;

    for (var index = 0; index < occurrences.length; index++) {
      final item = occurrences[index];
      final startEpoch = item.createdDate ?? item.createdAt;
      occurrenceStartEpochs.add(startEpoch);
      final start = DateTime.fromMillisecondsSinceEpoch(
        startEpoch,
        isUtc: true,
      ).toLocal();

      if (previousStart != null && todo.recurrence != RecurrenceType.none) {
        var missingStart = TodoRecurrenceDateService.nextDate(
          previousStart,
          todo,
        );
        var guard = 0;
        while (missingStart != null &&
            missingStart.isBefore(start) &&
            guard < 90) {
          slots.add(_TodoRecurrenceDateSlot(date: missingStart));
          missingStart = TodoRecurrenceDateService.nextDate(missingStart, todo);
          guard++;
        }
      }

      occurrenceSlotIndexById.putIfAbsent(item.id, () => slots.length);
      slots.add(_TodoRecurrenceDateSlot(date: start, occurrenceIndex: index));
      previousStart = start;
    }

    final recurrenceEnd = todo.recurrenceEndDate;
    final recurrenceEndDay = recurrenceEnd == null
        ? null
        : DateTime(recurrenceEnd.year, recurrenceEnd.month, recurrenceEnd.day);

    return _TodoRecurrenceDateStructure._(
      seriesId: seriesId,
      occurrences: occurrences,
      occurrenceStartEpochs: occurrenceStartEpochs,
      occurrenceSlotIndexById: Map<String, int>.unmodifiable(
        occurrenceSlotIndexById,
      ),
      recurrence: todo.recurrence,
      customIntervalDays: todo.customIntervalDays,
      recurrenceEndDayEpoch: recurrenceEndDay?.millisecondsSinceEpoch,
      slots: List<_TodoRecurrenceDateSlot>.unmodifiable(slots),
      projectedStart: slots.isEmpty ? currentStart : slots.last.date,
    );
  }

  bool matches({
    required String? seriesId,
    required List<TodoItem> occurrences,
    required TodoItem todo,
  }) {
    if (this.seriesId != seriesId ||
        recurrence != todo.recurrence ||
        customIntervalDays != todo.customIntervalDays ||
        recurrenceEndDayEpoch != _recurrenceEndDayEpoch(todo) ||
        occurrences.length != this.occurrences.length) {
      return false;
    }
    if (identical(this.occurrences, occurrences)) return true;

    for (var index = 0; index < occurrences.length; index++) {
      if (!identical(this.occurrences[index], occurrences[index]) ||
          occurrenceStartEpochs[index] !=
              (occurrences[index].createdDate ??
                  occurrences[index].createdAt)) {
        return false;
      }
    }
    return true;
  }

  int ensureProjectedDates(TodoItem todo, int requestedCount) {
    final targetCount = requestedCount.clamp(0, 90).toInt();
    while (_projectedDates.length < targetCount && !_projectionExhausted) {
      final nextStart = TodoRecurrenceDateService.nextDate(
        _projectedStart,
        todo,
      );
      if (nextStart == null) {
        _projectionExhausted = true;
        break;
      }
      _projectedStart = nextStart;
      final recurrenceEnd = recurrenceEndDayEpoch;
      final projectedDay = DateTime(
        nextStart.year,
        nextStart.month,
        nextStart.day,
      );
      if (recurrenceEnd != null &&
          projectedDay.millisecondsSinceEpoch > recurrenceEnd) {
        _projectionExhausted = true;
        break;
      }
      _projectedDates.add(nextStart);
    }
    return _projectedDates.length < targetCount
        ? _projectedDates.length
        : targetCount;
  }

  static DateTime _startFor(TodoItem todo) =>
      DateTime.fromMillisecondsSinceEpoch(
        todo.createdDate ?? todo.createdAt,
        isUtc: true,
      ).toLocal();

  static int? _recurrenceEndDayEpoch(TodoItem todo) {
    final recurrenceEnd = todo.recurrenceEndDate;
    if (recurrenceEnd == null) return null;
    return DateTime(
      recurrenceEnd.year,
      recurrenceEnd.month,
      recurrenceEnd.day,
    ).millisecondsSinceEpoch;
  }
}

mixin _TodoSectionRecurrenceMixin on _TodoSectionStateBase {
  void _editTodo(TodoItem todo, BuildContext cardCtx) {
    final renderBox = cardCtx.findRenderObject() as RenderBox?;
    if (renderBox == null) return;
    final rect = renderBox.localToGlobal(Offset.zero) & renderBox.size;
    final color = Theme.of(context).colorScheme.surface;

    Navigator.push(
      context,
      ContainerTransformRoute(
        page: TodoEditScreen(
          todo: todo,
          todos: widget.todos,
          onTodosChanged: widget.onTodosChanged,
          onEditorSave: widget.onEditorSave,
          onEditorGroupsSave: widget.onEditorGroupsSave,
          todoGroups: widget.todoGroups,
          onGroupsChanged: widget.onGroupsChanged,
          username: widget.username,
        ),
        sourceRect: rect,
        sourceColor: color,
        sourceBorderRadius: const BorderRadius.all(Radius.circular(14)),
      ),
    );
  }

  void _openTodoEditor(
    TodoItem todo, {
    TodoRecurrenceEditScope scope = TodoRecurrenceEditScope.occurrence,
  }) {
    Navigator.push(
      context,
      PageTransitions.material(
        builder: (_) => TodoEditScreen(
          todo: todo,
          todos: widget.todos,
          onTodosChanged: widget.onTodosChanged,
          onEditorSave: widget.onEditorSave,
          onEditorGroupsSave: widget.onEditorGroupsSave,
          todoGroups: widget.todoGroups,
          onGroupsChanged: widget.onGroupsChanged,
          username: widget.username,
          recurrenceEditScope: scope,
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────
  // 时间标签构建（单行，信息完整）
  // ─────────────────────────────────────────────
  String _buildTimeLabel(
    TodoItem todo,
    DateTime cDate,
    bool isPast,
    bool isFuture,
    DateTime now,
  ) {
    final isDateOnly = todo.isDateOnly;

    if (todo.dueDate != null) {
      if (isDateOnly) {
        return '${_cachedDateFormat('MM/dd').format(todo.dueDate!)}内完成';
      }
      if (todo.hasLegacyTimeRange) {
        final dateTimeFormat = _cachedDateFormat('MM/dd HH:mm');
        final startStr = dateTimeFormat.format(cDate);
        final dueStr = dateTimeFormat.format(todo.dueDate!);
        return '$startStr → $dueStr';
      }
      final dueStr = _cachedDateFormat('MM/dd HH:mm').format(todo.dueDate!);
      return '$dueStr前完成';
    } else {
      if (todo.hasLegacyTiming) {
        return '开始 ${_cachedDateFormat('MM/dd HH:mm').format(cDate)}';
      }
      return '未安排';
    }
  }

  // ─────────────────────────────────────────────
  // Dynamic progress fill color system
  // ─────────────────────────────────────────────
  Color _getProgressFillColor(double progress, bool isPast) {
    if (isPast || progress >= 1.0) {
      // Overdue / at deadline: light red
      return const Color(0xFFE57373); // red 300
    } else if (progress >= 0.5) {
      // Mid stage: orange-yellow
      return const Color(0xFFFFB74D); // orange 300
    } else {
      // Early stage: emerald green
      return const Color(0xFF66BB6A); // green 400
    }
  }

  Widget _buildRecurrenceProgress(TodoItem todo, DateTime now) {
    final seriesId = todo.recurrenceSeriesId;
    final actualOccurrences = seriesId == null
        ? <TodoItem>[todo]
        : (_recurrenceSeriesOccurrences[seriesId] ?? <TodoItem>[todo]);

    if (todo.recurrence == RecurrenceType.none &&
        actualOccurrences.length <= 1) {
      return const SizedBox.shrink();
    }

    final structureKey = seriesId == null
        ? 'todo:${todo.id}'
        : 'series:$seriesId';
    var dateStructure = _recurrenceDateStructures[structureKey];
    if (dateStructure == null ||
        !dateStructure.matches(
          seriesId: seriesId,
          occurrences: actualOccurrences,
          todo: todo,
        )) {
      dateStructure = _TodoRecurrenceDateStructure.build(
        seriesId: seriesId,
        occurrences: actualOccurrences,
        todo: todo,
      );
      _recurrenceDateStructures[structureKey] = dateStructure;
    }

    var currentIndex = dateStructure.occurrenceSlotIndexById[todo.id] ?? -1;
    if (currentIndex < 0) {
      for (var index = 0; index < dateStructure.slots.length; index++) {
        final occurrenceIndex = dateStructure.slots[index].occurrenceIndex;
        if (occurrenceIndex != null &&
            actualOccurrences[occurrenceIndex].id == todo.id) {
          currentIndex = index;
          break;
        }
      }
    }
    final fixedEnd = todo.recurrenceEndDate != null;
    final historyEnd = currentIndex >= 0
        ? currentIndex + 1
        : dateStructure.slots.length;
    final summaryEnd = fixedEnd ? dateStructure.slots.length : historyEnd;
    final displayStart = currentIndex >= 0
        ? (currentIndex - 2).clamp(0, dateStructure.slots.length).toInt()
        : (dateStructure.slots.length - 3)
              .clamp(0, dateStructure.slots.length)
              .toInt();
    final nodes = <TodoRecurrenceProgressNode>[];
    var completedCount = 0;
    var overdueCount = 0;
    var skippedCount = 0;
    final currentStart = DateTime.fromMillisecondsSinceEpoch(
      todo.createdDate ?? todo.createdAt,
      isUtc: true,
    ).toLocal();
    final occurrenceDuration =
        todo.dueDate?.difference(currentStart) ?? const Duration(hours: 24);
    for (var index = 0; index < dateStructure.slots.length; index++) {
      final slot = dateStructure.slots[index];
      final occurrenceIndex = slot.occurrenceIndex;
      final DateTime date;
      final TodoRecurrenceNodeState state;
      final String? occurrenceId;
      final bool isCurrent;
      if (occurrenceIndex == null) {
        final missingStart = slot.date;
        date = missingStart;
        state = missingStart.isAfter(now)
            ? TodoRecurrenceNodeState.future
            : missingStart.add(occurrenceDuration).isBefore(now)
            ? TodoRecurrenceNodeState.overdue
            : TodoRecurrenceNodeState.pending;
        occurrenceId = null;
        isCurrent = false;
      } else {
        final item = actualOccurrences[occurrenceIndex];
        final start = slot.date;
        final end = item.dueDate ?? start;
        isCurrent = item.id == todo.id;
        date = start;
        occurrenceId = item.id;
        state = item.isSkipped
            ? TodoRecurrenceNodeState.skipped
            : item.isDone
            ? TodoRecurrenceNodeState.completed
            : isCurrent
            ? todo.recurrence == RecurrenceType.none
                  ? TodoRecurrenceNodeState.neutral
                  : TodoRecurrenceNodeState.current
            : start.isAfter(now)
            ? TodoRecurrenceNodeState.future
            : end.isBefore(now)
            ? TodoRecurrenceNodeState.overdue
            : TodoRecurrenceNodeState.pending;
      }

      if (index < summaryEnd) {
        if (state == TodoRecurrenceNodeState.completed) completedCount++;
        if (state == TodoRecurrenceNodeState.overdue) overdueCount++;
        if (state == TodoRecurrenceNodeState.skipped) skippedCount++;
      }
      if (index < displayStart) continue;
      nodes.add(
        TodoRecurrenceProgressNode(
          date: date,
          state: state,
          occurrenceId: occurrenceId,
          isCurrent: isCurrent,
        ),
      );
    }

    var projectedCount = 0;
    if (todo.recurrence != RecurrenceType.none) {
      const openEndedFuturePreviewCount = 14;
      var futureCount = 0;
      for (final node in nodes) {
        if (node.state == TodoRecurrenceNodeState.future) futureCount++;
      }
      final requestedProjectionCount = todo.recurrenceEndDate == null
          ? openEndedFuturePreviewCount - futureCount
          : 90;
      projectedCount = dateStructure.ensureProjectedDates(
        todo,
        requestedProjectionCount,
      );
      for (var index = 0; index < projectedCount; index++) {
        final projectedNode = TodoRecurrenceProgressNode(
          date: dateStructure._projectedDates[index],
          state: TodoRecurrenceNodeState.future,
        );
        nodes.add(projectedNode);
      }
    }

    // 有结束日期的有限循环展示整个系列的完成进度；开放式循环没有固定
    // 总期数，因此仍以已经发生的历史和当前期作为统计范围。
    final summary = (
      completedCount: completedCount,
      totalCount: fixedEnd
          ? dateStructure.slots.length + projectedCount
          : summaryEnd,
      overdueCount: overdueCount,
    );
    return TodoRecurrenceProgress(
      key: ValueKey('recurrence_progress_${seriesId ?? todo.id}'),
      nodes: nodes,
      completedCount: summary.completedCount,
      totalCount: todo.recurrenceEndDate == null ? null : summary.totalCount,
      overdueCount: summary.overdueCount,
      skippedCount: skippedCount,
      onNodeTap: (node) => _handleRecurrenceNodeTap(todo, node, dateStructure!),
      onManage: () => _showRecurrenceManagement(todo),
    );
  }

  Future<void> _handleRecurrenceNodeTap(
    TodoItem current,
    TodoRecurrenceProgressNode node,
    _TodoRecurrenceDateStructure dateStructure,
  ) async {
    if (node.isCurrent) {
      if (current.recurrenceSeriesId?.isNotEmpty == true ||
          current.recurrence != RecurrenceType.none) {
        await _showRecurrenceOccurrenceActions(current, node.date);
      } else {
        _setTodoCompletion(current, !current.isDone);
      }
      return;
    }

    final occurrenceId = node.occurrenceId;
    if (occurrenceId != null) {
      final slotIndex = dateStructure.occurrenceSlotIndexById[occurrenceId];
      if (slotIndex != null && slotIndex < dateStructure.slots.length) {
        final occurrenceIndex = dateStructure.slots[slotIndex].occurrenceIndex;
        if (occurrenceIndex != null &&
            occurrenceIndex < dateStructure.occurrences.length) {
          final occurrence = dateStructure.occurrences[occurrenceIndex];
          if (occurrence.id == occurrenceId) {
            await _showRecurrenceOccurrenceActions(occurrence, node.date);
            return;
          }
        }
      }
    }

    AppSnackBars.showSnackBar(
      context,
      SnackBar(
        content: Text(
          '${_cachedDateFormat('M月d日').format(node.date)}的待办实例尚未生成',
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _showRecurrenceOccurrenceActions(
    TodoItem occurrence,
    DateTime occurrenceDate,
  ) async {
    final colorScheme = Theme.of(context).colorScheme;
    final action = await showAppModalBottomSheet<_RecurrenceOccurrenceAction>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(
                Icons.event_repeat_rounded,
                color: colorScheme.primary,
              ),
              title: Text(
                _cachedDateFormat('yyyy年M月d日').format(occurrenceDate),
              ),
              subtitle: Text(occurrence.title),
            ),
            const Divider(height: 1),
            ListTile(
              key: const ValueKey('recurrence_occurrence_toggle_completion'),
              leading: Icon(
                occurrence.isDone
                    ? Icons.radio_button_unchecked_rounded
                    : Icons.check_circle_outline_rounded,
                color: colorScheme.primary,
              ),
              title: Text(occurrence.isDone ? '取消完成' : '标记为完成'),
              subtitle: const Text('只修改这一期的完成状态'),
              onTap: () => Navigator.pop(
                sheetContext,
                _RecurrenceOccurrenceAction.toggleCompletion,
              ),
            ),
            if (occurrence.recurrenceSeriesId?.isNotEmpty == true ||
                occurrence.recurrence != RecurrenceType.none)
              ListTile(
                key: const ValueKey('recurrence_occurrence_skip'),
                leading: Icon(
                  occurrence.isSkipped
                      ? Icons.restore_rounded
                      : Icons.skip_next_rounded,
                  color: colorScheme.tertiary,
                ),
                title: Text(occurrence.isSkipped ? '恢复本期' : '跳过本期'),
                subtitle: Text(
                  occurrence.isSkipped ? '恢复后重新进入待办与提醒' : '只跳过这一期，后续期次仍会继续',
                ),
                onTap: () => Navigator.pop(
                  sheetContext,
                  _RecurrenceOccurrenceAction.skip,
                ),
              ),
            ListTile(
              key: const ValueKey('recurrence_occurrence_edit'),
              leading: Icon(
                Icons.edit_calendar_rounded,
                color: colorScheme.secondary,
              ),
              title: const Text('编辑本期'),
              subtitle: const Text('修改这一期的标题、时间或备注'),
              onTap: () =>
                  Navigator.pop(sheetContext, _RecurrenceOccurrenceAction.edit),
            ),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;
    switch (action) {
      case _RecurrenceOccurrenceAction.toggleCompletion:
        _setTodoCompletion(occurrence, !occurrence.isDone);
      case _RecurrenceOccurrenceAction.skip:
        await _toggleSkippedOccurrence(occurrence, occurrenceDate);
      case _RecurrenceOccurrenceAction.edit:
        _openTodoEditor(occurrence);
    }
  }

  Future<void> _toggleSkippedOccurrence(
    TodoItem occurrence,
    DateTime occurrenceDate,
  ) async {
    if (occurrence.isSkipped) {
      await _saveSkippedOccurrence(occurrence, skipped: false);
      if (mounted) {
        AppSnackBars.showSnackBar(
          context,
          const SnackBar(content: Text('已恢复本期待办')),
        );
      }
      return;
    }
    if (occurrence.isDone ||
        occurrence.isDeleted ||
        (occurrence.recurrenceSeriesId?.trim().isNotEmpty != true &&
            occurrence.recurrence == RecurrenceType.none)) {
      AppSnackBars.showSnackBar(
        context,
        const SnackBar(content: Text('只有未完成的重复待办本期可以跳过')),
      );
      return;
    }

    List<TodoPlanBlock> linkedPlans;
    PomodoroRunState? run;
    try {
      linkedPlans = await StorageService.getPlanBlocksByTodo(
        widget.username,
        occurrence.id,
      );
      run = await PomodoroService.loadRunState();
    } catch (_) {
      if (!mounted) return;
      AppSnackBars.showSnackBar(
        context,
        const SnackBar(content: Text('无法核对当前规划和专注状态，请重试')),
      );
      return;
    }
    if (!mounted) return;
    if (_runFocusesOccurrence(run, occurrence.id, linkedPlans)) {
      AppSnackBars.showSnackBar(
        context,
        const SnackBar(content: Text('这期待办正在专注，请先结束当前专注再跳过')),
      );
      return;
    }
    final notStartedPlanCount = linkedPlans
        .where(
          (block) =>
              !block.isDeleted &&
              block.actualFocusSeconds == 0 &&
              (block.status == TodoPlanStatus.planned ||
                  block.status == TodoPlanStatus.reminded),
        )
        .length;
    final dateLabel = _cachedDateFormat('yyyy年M月d日').format(occurrenceDate);
    if (!mounted) return;
    final confirmed = await showAppDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('跳过这一期？'),
        content: Text(
          '将「${occurrence.title}」($dateLabel) 标记为已跳过。它不会算作完成或逾期，后续期次仍会继续。'
          '${notStartedPlanCount > 0 ? '\n\n关联的 $notStartedPlanCount 个未开始规划会保留，不会删除。' : ''}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton.tonal(
            key: const ValueKey('confirm_skip_occurrence'),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('跳过本期'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;

    // Re-read the persisted instance before applying the confirmation so an
    // old sheet cannot skip a completed, deleted, or newly focused period.
    final latest = await StorageService.getTodoByUuid(
      widget.username,
      occurrence.id,
    );
    if (latest == null ||
        latest.isDeleted ||
        latest.isDone ||
        latest.isSkipped) {
      if (mounted) {
        AppSnackBars.showSnackBar(
          context,
          const SnackBar(content: Text('这期待办状态已变化，请重新打开后操作')),
        );
      }
      return;
    }
    List<TodoPlanBlock> latestPlans;
    PomodoroRunState? latestRun;
    try {
      latestPlans = await StorageService.getPlanBlocksByTodo(
        widget.username,
        latest.id,
      );
      latestRun = await PomodoroService.loadRunState();
    } catch (_) {
      if (!mounted) return;
      AppSnackBars.showSnackBar(
        context,
        const SnackBar(content: Text('无法核对当前规划和专注状态，请重试')),
      );
      return;
    }
    if (latest.recurrenceSeriesId?.isNotEmpty != true &&
        latest.recurrence == RecurrenceType.none) {
      if (mounted) {
        AppSnackBars.showSnackBar(
          context,
          const SnackBar(content: Text('这期待办已不再重复，无法跳过')),
        );
      }
      return;
    }
    if (_runFocusesOccurrence(latestRun, latest.id, latestPlans)) {
      if (mounted) {
        AppSnackBars.showSnackBar(
          context,
          const SnackBar(content: Text('这期待办已开始专注，暂不能跳过')),
        );
      }
      return;
    }
    final saved = await _saveSkippedOccurrence(latest, skipped: true);
    if (!saved) return;
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: const Text('已跳过本期，后续期次仍会继续'),
          action: SnackBarAction(
            label: '撤销',
            onPressed: () => _restoreSkippedOccurrence(latest),
          ),
        ),
      );
  }

  bool _runFocusesOccurrence(
    PomodoroRunState? run,
    String todoId,
    List<TodoPlanBlock> plans,
  ) {
    if (run == null ||
        !{
          PomodoroPhase.focusing,
          PomodoroPhase.breaking,
          PomodoroPhase.remoteWatching,
        }.contains(run.phase)) {
      return false;
    }
    if (run.todoUuid == todoId) return true;
    final blockId = run.planBlockId;
    return blockId != null && plans.any((block) => block.id == blockId);
  }

  Future<void> _restoreSkippedOccurrence(TodoItem occurrence) async {
    final latest = await StorageService.getTodoByUuid(
      widget.username,
      occurrence.id,
    );
    if (latest == null || latest.isDeleted || !latest.isSkipped) return;
    final saved = await _saveSkippedOccurrence(latest, skipped: false);
    if (!saved) return;
    if (mounted) {
      AppSnackBars.showSnackBar(
        context,
        const SnackBar(content: Text('已撤销跳过')),
      );
    }
  }

  Future<bool> _saveSkippedOccurrence(
    TodoItem occurrence, {
    required bool skipped,
  }) async {
    final index = widget.todos.indexWhere((todo) => todo.id == occurrence.id);
    if (index < 0) return false;
    final updated = List<TodoItem>.from(widget.todos);
    final current = occurrence.detachedCopy();
    current.isDone = false;
    current.isSkipped = skipped;
    current.isSkippedSyncPending = true;
    current.markAsChanged();
    updated[index] = current;
    _invalidateTodoViewModel();
    setState(() {});
    try {
      await widget.onTodosChanged(updated);
      return true;
    } catch (_) {
      if (mounted) {
        AppSnackBars.showSnackBar(
          context,
          const SnackBar(content: Text('保存跳过状态失败，请重试')),
        );
      }
      widget.onRefreshRequested();
      return false;
    }
  }

  void _setTodoCompletion(TodoItem todo, bool isDone) {
    if (todo.isDone == isDone) return;
    _invalidateTodoViewModel();
    setState(() {
      todo.isDone = isDone;
      if (isDone && todo.isSkipped) {
        todo.isSkipped = false;
        todo.isSkippedSyncPending = true;
      }
    });
    if (isDone) {
      PomodoroSyncService().sendStopSignal(todoUuid: todo.id);
    }
    todo.markAsChanged();
    widget.onTodosChanged(List<TodoItem>.from(widget.todos));
  }

  Future<void> _showRecurrenceManagement(TodoItem todo) async {
    final colorScheme = Theme.of(context).colorScheme;
    final seriesId = TodoRecurrenceSeriesEditService.seriesIdFor(todo);
    final seriesCount = seriesId == null
        ? 0
        : TodoRecurrenceSeriesEditService.activeMembers(
            widget.todos,
            seriesId,
          ).length;
    await showAppModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.8,
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.only(bottom: 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
                  child: Text(
                    '编辑范围',
                    style: Theme.of(sheetContext).textTheme.titleSmall
                        ?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ),
                ListTile(
                  leading: Icon(
                    Icons.edit_calendar_rounded,
                    color: colorScheme.primary,
                  ),
                  title: const Text('仅本期'),
                  subtitle: const Text('只编辑当前这一期待办'),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _openTodoEditor(todo);
                  },
                ),
                ListTile(
                  leading: Icon(
                    Icons.event_repeat_rounded,
                    color: colorScheme.secondary,
                  ),
                  title: const Text('本期及以后'),
                  subtitle: const Text('当前和后续已生成期次采用新内容'),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _openTodoEditor(
                      todo,
                      scope: TodoRecurrenceEditScope.future,
                    );
                  },
                ),
                if (seriesId != null)
                  ListTile(
                    leading: Icon(
                      Icons.all_inclusive_rounded,
                      color: colorScheme.tertiary,
                    ),
                    title: const Text('整个系列'),
                    subtitle: Text('$seriesCount 期都会修改；完成和跳过状态保留'),
                    onTap: () {
                      Navigator.pop(sheetContext);
                      _openTodoEditor(
                        todo,
                        scope: TodoRecurrenceEditScope.series,
                      );
                    },
                  ),
                if (todo.recurrence != RecurrenceType.none) ...[
                  const Divider(height: 12),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
                    child: Text(
                      '系列操作',
                      style: Theme.of(sheetContext).textTheme.titleSmall
                          ?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ),
                  ListTile(
                    leading: Icon(
                      Icons.stop_circle_outlined,
                      color: colorScheme.error,
                    ),
                    title: const Text('在本期结束重复'),
                    subtitle: const Text('停止后续生成；本期之后已生成的关联期次移入回收站'),
                    onTap: () {
                      Navigator.pop(sheetContext);
                      final start = DateTime.fromMillisecondsSinceEpoch(
                        todo.createdDate ?? todo.createdAt,
                        isUtc: true,
                      ).toLocal();
                      _invalidateTodoViewModel();
                      setState(() {
                        final currentStart = todo.createdDate ?? todo.createdAt;
                        final currentSeriesId = todo.recurrenceSeriesId;
                        if (currentSeriesId != null &&
                            currentSeriesId.isNotEmpty) {
                          for (final occurrence in widget.todos) {
                            if (occurrence.id == todo.id ||
                                occurrence.isDeleted ||
                                occurrence.recurrenceSeriesId !=
                                    currentSeriesId ||
                                (occurrence.createdDate ??
                                        occurrence.createdAt) <=
                                    currentStart) {
                              continue;
                            }
                            occurrence.isDeleted = true;
                            occurrence.recurrence = RecurrenceType.none;
                            occurrence.markAsChanged();
                          }
                        }
                        todo.recurrence = RecurrenceType.none;
                        todo.recurrenceEndDate = DateTime(
                          start.year,
                          start.month,
                          start.day,
                        );
                        todo.markAsChanged();
                      });
                      widget.onTodosChanged(List<TodoItem>.from(widget.todos));
                    },
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────
  // Compact card: redesigned
  // ─────────────────────────────────────────────
}
