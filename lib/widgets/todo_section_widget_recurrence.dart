part of 'todo_section_widget.dart';

// ignore_for_file: annotate_overrides

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
    bool applyToFutureOccurrences = false,
  }) {
    Navigator.push(
      context,
      PageTransitions.material(
        builder: (_) => TodoEditScreen(
          todo: todo,
          todos: widget.todos,
          onTodosChanged: widget.onTodosChanged,
          todoGroups: widget.todoGroups,
          onGroupsChanged: widget.onGroupsChanged,
          username: widget.username,
          applyToFutureOccurrences: applyToFutureOccurrences,
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
        return '${DateFormat('MM/dd').format(todo.dueDate!)}内完成';
      }
      if (todo.hasLegacyTimeRange) {
        final startStr = DateFormat('MM/dd HH:mm').format(cDate);
        final dueStr = DateFormat('MM/dd HH:mm').format(todo.dueDate!);
        return '$startStr → $dueStr';
      }
      final dueStr = DateFormat('MM/dd HH:mm').format(todo.dueDate!);
      return '$dueStr前完成';
    } else {
      if (todo.hasLegacyTiming) {
        return '开始 ${DateFormat('MM/dd HH:mm').format(cDate)}';
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
    final actualOccurrences = List<TodoItem>.from(
      seriesId == null
          ? <TodoItem>[todo]
          : (_recurrenceSeriesOccurrences[seriesId] ?? <TodoItem>[todo]),
    )..sort((a, b) =>
        (a.createdDate ?? a.createdAt).compareTo(b.createdDate ?? b.createdAt));

    if (todo.recurrence == RecurrenceType.none &&
        actualOccurrences.length <= 1) {
      return const SizedBox.shrink();
    }

    final allNodes = <TodoRecurrenceProgressNode>[];
    final currentStart = DateTime.fromMillisecondsSinceEpoch(
      todo.createdDate ?? todo.createdAt,
      isUtc: true,
    ).toLocal();
    final occurrenceDuration =
        todo.dueDate?.difference(currentStart) ?? const Duration(hours: 24);
    DateTime? previousStart;
    for (final item in actualOccurrences) {
      final start = DateTime.fromMillisecondsSinceEpoch(
        item.createdDate ?? item.createdAt,
        isUtc: true,
      ).toLocal();
      if (previousStart != null && todo.recurrence != RecurrenceType.none) {
        var missingStart = _nextRecurrenceStart(previousStart, todo);
        var guard = 0;
        while (missingStart.isBefore(start) && guard < 90) {
          allNodes.add(TodoRecurrenceProgressNode(
            date: missingStart,
            state: missingStart.isAfter(now)
                ? TodoRecurrenceNodeState.future
                : missingStart.add(occurrenceDuration).isBefore(now)
                    ? TodoRecurrenceNodeState.overdue
                    : TodoRecurrenceNodeState.pending,
          ));
          missingStart = _nextRecurrenceStart(missingStart, todo);
          guard++;
        }
      }
      final end = item.dueDate ?? start;
      final isCurrent = item.id == todo.id;
      final state = item.isDone
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
      allNodes.add(TodoRecurrenceProgressNode(
        date: start,
        state: state,
        occurrenceId: item.id,
        isCurrent: isCurrent,
      ));
      previousStart = start;
    }
    final currentIndex = allNodes.indexWhere((node) => node.isCurrent);
    final historyEnd = currentIndex >= 0 ? currentIndex + 1 : allNodes.length;
    final historyNodes = allNodes.take(historyEnd).toList();
    final nodes = historyNodes
        .skip((historyNodes.length - 3).clamp(0, historyNodes.length))
        .followedBy(allNodes.skip(historyEnd))
        .toList();

    if (todo.recurrence != RecurrenceType.none) {
      var projectedStart = nodes.isNotEmpty ? nodes.last.date : currentStart;
      final recurrenceEnd = todo.recurrenceEndDate;
      final recurrenceEndDay = recurrenceEnd == null
          ? null
          : DateTime(
              recurrenceEnd.year,
              recurrenceEnd.month,
              recurrenceEnd.day,
            );
      const openEndedFuturePreviewCount = 14;
      var projectedCount = 0;
      var futureCount = nodes
          .where((node) => node.state == TodoRecurrenceNodeState.future)
          .length;
      while (projectedCount < 90) {
        if (recurrenceEndDay == null &&
            futureCount >= openEndedFuturePreviewCount) {
          break;
        }
        projectedStart = _nextRecurrenceStart(projectedStart, todo);
        final projectedDay = DateTime(
          projectedStart.year,
          projectedStart.month,
          projectedStart.day,
        );
        if (recurrenceEndDay != null &&
            projectedDay.isAfter(recurrenceEndDay)) {
          break;
        }
        final projectedNode = TodoRecurrenceProgressNode(
          date: projectedStart,
          state: TodoRecurrenceNodeState.future,
        );
        nodes.add(projectedNode);
        allNodes.add(projectedNode);
        projectedCount++;
        futureCount++;
      }
    }

    // 有结束日期的有限循环展示整个系列的完成进度；开放式循环没有固定
    // 总期数，因此仍以已经发生的历史和当前期作为统计范围。
    final summary = _calculateRecurrenceSummary(
      allNodes: allNodes,
      historyNodes: historyNodes,
      hasFixedEnd: todo.recurrenceEndDate != null,
    );
    return TodoRecurrenceProgress(
      key: ValueKey('recurrence_progress_${seriesId ?? todo.id}'),
      nodes: nodes,
      completedCount: summary.completedCount,
      totalCount: todo.recurrenceEndDate == null ? null : summary.totalCount,
      overdueCount: summary.overdueCount,
      onNodeTap: (node) => _handleRecurrenceNodeTap(todo, node),
      onManage: () => _showRecurrenceManagement(todo),
    );
  }

  Future<void> _handleRecurrenceNodeTap(
    TodoItem current,
    TodoRecurrenceProgressNode node,
  ) async {
    if (node.isCurrent) {
      _setTodoCompletion(current, !current.isDone);
      return;
    }

    final occurrenceId = node.occurrenceId;
    if (occurrenceId != null) {
      final occurrence = widget.todos.cast<TodoItem?>().firstWhere(
            (item) => item?.id == occurrenceId,
            orElse: () => null,
          );
      if (occurrence != null) {
        await _showRecurrenceOccurrenceActions(occurrence, node.date);
        return;
      }
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '${DateFormat('M月d日').format(node.date)}的待办实例尚未生成',
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
              title: Text(DateFormat('yyyy年M月d日').format(occurrenceDate)),
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
            ListTile(
              key: const ValueKey('recurrence_occurrence_edit'),
              leading: Icon(
                Icons.edit_calendar_rounded,
                color: colorScheme.secondary,
              ),
              title: const Text('编辑本期'),
              subtitle: const Text('修改这一期的标题、时间或备注'),
              onTap: () => Navigator.pop(
                sheetContext,
                _RecurrenceOccurrenceAction.edit,
              ),
            ),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;
    switch (action) {
      case _RecurrenceOccurrenceAction.toggleCompletion:
        _setTodoCompletion(occurrence, !occurrence.isDone);
      case _RecurrenceOccurrenceAction.edit:
        _openTodoEditor(occurrence);
    }
  }

  void _setTodoCompletion(TodoItem todo, bool isDone) {
    if (todo.isDone == isDone) return;
    setState(() => todo.isDone = isDone);
    if (isDone) {
      PomodoroSyncService().sendStopSignal(todoUuid: todo.id);
    }
    todo.markAsChanged();
    widget.onTodosChanged(List<TodoItem>.from(widget.todos));
  }

  Future<void> _showRecurrenceManagement(TodoItem todo) async {
    final colorScheme = Theme.of(context).colorScheme;
    await showAppModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading:
                  Icon(Icons.edit_calendar_rounded, color: colorScheme.primary),
              title: const Text('只修改本期'),
              subtitle: const Text('仅编辑当前显示的这一期待办'),
              onTap: () {
                Navigator.pop(sheetContext);
                _openTodoEditor(todo);
              },
            ),
            ListTile(
              leading: Icon(Icons.event_repeat_rounded,
                  color: colorScheme.secondary),
              title: const Text('修改后续所有周期'),
              subtitle: const Text('本期及之后的实例同步采用修改内容'),
              onTap: () {
                Navigator.pop(sheetContext);
                _openTodoEditor(todo, applyToFutureOccurrences: true);
              },
            ),
            if (todo.recurrence != RecurrenceType.none)
              ListTile(
                leading:
                    Icon(Icons.stop_circle_outlined, color: colorScheme.error),
                title: const Text('在本期结束循环'),
                subtitle: const Text('保留已有记录，不再产生新的周期'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  final start = DateTime.fromMillisecondsSinceEpoch(
                    todo.createdDate ?? todo.createdAt,
                    isUtc: true,
                  ).toLocal();
                  setState(() {
                    final currentStart = todo.createdDate ?? todo.createdAt;
                    final seriesId = todo.recurrenceSeriesId;
                    if (seriesId != null && seriesId.isNotEmpty) {
                      for (final occurrence in widget.todos) {
                        if (occurrence.id == todo.id ||
                            occurrence.isDeleted ||
                            occurrence.recurrenceSeriesId != seriesId ||
                            (occurrence.createdDate ?? occurrence.createdAt) <=
                                currentStart) {
                          continue;
                        }
                        occurrence.isDeleted = true;
                        occurrence.recurrence = RecurrenceType.none;
                        occurrence.markAsChanged();
                      }
                    }
                    todo.recurrence = RecurrenceType.none;
                    todo.recurrenceEndDate =
                        DateTime(start.year, start.month, start.day);
                    todo.markAsChanged();
                  });
                  widget.onTodosChanged(List<TodoItem>.from(widget.todos));
                },
              ),
          ],
        ),
      ),
    );
  }

  DateTime _nextRecurrenceStart(DateTime current, TodoItem todo) {
    switch (todo.recurrence) {
      case RecurrenceType.daily:
        return DateTime(current.year, current.month, current.day + 1,
            current.hour, current.minute, current.second, current.millisecond);
      case RecurrenceType.customDays:
        final days = todo.customIntervalDays ?? 1;
        return DateTime(current.year, current.month, current.day + days,
            current.hour, current.minute, current.second, current.millisecond);
      case RecurrenceType.weekly:
        return DateTime(current.year, current.month, current.day + 7,
            current.hour, current.minute, current.second, current.millisecond);
      case RecurrenceType.weekdays:
        var next = DateTime(current.year, current.month, current.day + 1,
            current.hour, current.minute, current.second, current.millisecond);
        while (next.weekday == DateTime.saturday ||
            next.weekday == DateTime.sunday) {
          next = DateTime(next.year, next.month, next.day + 1, next.hour,
              next.minute, next.second, next.millisecond);
        }
        return next;
      case RecurrenceType.monthly:
        final targetMonth = DateTime(current.year, current.month + 1);
        final lastDay =
            DateTime(targetMonth.year, targetMonth.month + 1, 0).day;
        return DateTime(
          targetMonth.year,
          targetMonth.month,
          current.day.clamp(1, lastDay),
          current.hour,
          current.minute,
          current.second,
          current.millisecond,
        );
      case RecurrenceType.yearly:
        final lastDay = DateTime(current.year + 1, current.month + 1, 0).day;
        return DateTime(
          current.year + 1,
          current.month,
          current.day.clamp(1, lastDay),
          current.hour,
          current.minute,
          current.second,
          current.millisecond,
        );
      case RecurrenceType.none:
        return current;
    }
  }

  // ─────────────────────────────────────────────
  // Compact card: redesigned
  // ─────────────────────────────────────────────
}
