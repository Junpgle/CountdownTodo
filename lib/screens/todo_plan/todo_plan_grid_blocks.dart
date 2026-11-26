part of '../todo_plan_screen.dart';

extension _PlanGridBlocks on _PlanGridViewState {
  List<Widget> _buildBlockItems(
    TodoPlanBlock block,
    double width,
    double hourH,
    List<int> hourlyLaneCounts, {
    bool previewOnly = false,
  }) {
    final start = DateTime.fromMillisecondsSinceEpoch(block.startTime);
    final end = DateTime.fromMillisecondsSinceEpoch(block.endTime);
    final dayStart = CalendarDateMath.dateOnly(widget.date);
    final dayEnd = DateTime(dayStart.year, dayStart.month, dayStart.day + 1);
    if (!end.isAfter(dayStart) || !start.isBefore(dayEnd)) return const [];

    final clippedStart = start.isBefore(dayStart) ? dayStart : start;
    final clippedEnd = end.isAfter(dayEnd) ? dayEnd : end;
    final todo = _todoById[block.todoId];
    final isMappedBlock = widget.mappedBlockIds.contains(block.id);
    final canDrag =
        !previewOnly &&
        !isMappedBlock &&
        !widget.dragBusy &&
        PlanDragService.canAdjust(block, widget.dragService.now) &&
        widget.focusingPlanId != block.id &&
        todo != null &&
        !todo.isDone &&
        !todo.isDeleted &&
        !todo.isSkipped &&
        !ConflictVisibilityService.blocksTodoPlanning(todo);
    final hiddenAnchor = !previewOnly && _gesture?.block.id == block.id;
    final isMappedCourse = block.id.startsWith('mapped_course_');
    final isMappedHabit = HabitChallengePlanningService.isMappedHabitBlock(
      block,
    );
    final isMappedChallenge =
        HabitChallengePlanningService.isMappedChallengeBlock(block);
    final scheme = Theme.of(context).colorScheme;
    final color = isMappedCourse
        ? Colors.teal
        : isMappedHabit
        ? scheme.tertiary
        : isMappedChallenge
        ? scheme.secondary
        : (isMappedBlock ? Colors.amber.shade700 : scheme.primary);
    final icon = isMappedCourse
        ? Icons.school_rounded
        : isMappedHabit
        ? Icons.repeat_rounded
        : isMappedChallenge
        ? Icons.emoji_events_outlined
        : (isMappedBlock ? Icons.task_alt_rounded : Icons.event_note);
    final mappedBadgeLabel = isMappedCourse
        ? '课程'
        : isMappedHabit
        ? '习惯'
        : isMappedChallenge
        ? '挑战'
        : '待办';
    final widgets = <Widget>[];

    final endHour = clippedEnd.isAtSameMomentAs(dayEnd) ? 23 : clippedEnd.hour;
    for (int hour = clippedStart.hour; hour <= endHour; hour++) {
      final rowStart = DateTime(
        widget.date.year,
        widget.date.month,
        widget.date.day,
        hour,
      );
      final rowEnd = rowStart.add(const Duration(hours: 1));
      final segmentStart = clippedStart.isAfter(rowStart)
          ? clippedStart
          : rowStart;
      final segmentEnd = clippedEnd.isBefore(rowEnd) ? clippedEnd : rowEnd;
      if (!segmentEnd.isAfter(segmentStart) || hour >= 24) continue;
      final isStartSegment = segmentStart.isAtSameMomentAs(clippedStart);
      final isEndSegment = segmentEnd.isAtSameMomentAs(clippedEnd);
      final laneCount = hourlyLaneCounts[hour];
      final segmentHeight = max(1.0, hourH / laneCount - 2);
      final contentFontSize = min(11.0, max(6.0, segmentHeight * 0.72));

      final left = width * segmentStart.minute / 60;
      final segmentW = max(
        2.0,
        width * segmentEnd.difference(segmentStart).inMinutes / 60,
      );
      final segmentChild = IgnorePointer(
        ignoring:
            previewOnly || (_gesture != null && _gesture!.block.id != block.id),
        child: GestureDetector(
          key: !previewOnly && isStartSegment
              ? _sourceKeyFor(block)
              : ValueKey(
                  '${previewOnly ? 'plan-preview' : 'plan-drag-block'}-${block.id}-$hour',
                ),
          onTap: widget.dragBusy || _gesture != null
              ? null
              : isMappedBlock
              ? () => _openMappedBlockDetail(block)
              : () =>
                    _showEditBlockSheet(block, sourceKey: _sourceKeyFor(block)),
          onLongPressStart: canDrag
              ? (details) => _beginGesture(
                  block,
                  PlanDragKind.move,
                  details.globalPosition,
                )
              : null,
          onLongPressMoveUpdate: canDrag
              ? (details) =>
                    _updateGesture(details.globalPosition, width, hourH)
              : null,
          onLongPressEnd: canDrag ? (_) => unawaited(_finishGesture()) : null,
          onLongPressCancel: canDrag ? _cancelGesture : null,
          onPanStart: canDrag || previewOnly
              ? null
              : (_) => _clearRecordSelection(),
          onPanUpdate: canDrag || previewOnly ? null : (_) {},
          onPanEnd: canDrag || previewOnly ? null : (_) {},
          child: Stack(
            children: [
              Container(
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(5),
                  border: Border.all(color: color.withValues(alpha: 0.4)),
                ),
                padding: EdgeInsets.symmetric(
                  horizontal: 5,
                  vertical: laneCount > 1 ? 0 : 1,
                ),
                child: segmentW < 28
                    ? const SizedBox.shrink()
                    : Row(
                        children: [
                          Icon(
                            block.status == TodoPlanStatus.finished
                                ? Icons.check_circle
                                : icon,
                            size: min(10.0, contentFontSize),
                            color: color,
                          ),
                          const SizedBox(width: 3),
                          Expanded(
                            child: Text(
                              block.titleSnapshot ?? todo?.title ?? '未知待办',
                              style: TextStyle(
                                fontSize: contentFontSize,
                                fontWeight: FontWeight.bold,
                                color: color,
                              ),
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                            ),
                          ),
                          if (segmentW >
                                  100 *
                                      MediaQuery.textScalerOf(context)
                                          .scale(1) &&
                              isMappedBlock) ...[
                            const SizedBox(width: 4),
                            Text(
                              mappedBadgeLabel,
                              style: TextStyle(
                                fontSize: min(8.0, contentFontSize),
                                fontWeight: FontWeight.w700,
                                color: color.withValues(alpha: 0.72),
                              ),
                              maxLines: 1,
                            ),
                          ],
                          if (segmentW >
                              180 * MediaQuery.textScalerOf(context).scale(1))
                            Text(
                              '${AppTimeFormats.dateFormatter('HH:mm').format(start)}-${AppTimeFormats.dateFormatter('HH:mm').format(end)}',
                              style: TextStyle(
                                fontSize: min(8.0, contentFontSize),
                                color: color.withValues(alpha: 0.72),
                              ),
                              maxLines: 1,
                            ),
                        ],
                      ),
              ),
              if (isStartSegment && !isMappedBlock && (canDrag || previewOnly))
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  width: 12,
                  child: GestureDetector(
                    key: ValueKey(
                      '${previewOnly ? 'preview-' : ''}plan-resize-start-${block.id}',
                    ),
                    behavior: HitTestBehavior.translucent,
                    dragStartBehavior: DragStartBehavior.down,
                    onHorizontalDragStart: canDrag
                        ? (details) => _beginGesture(
                            block,
                            PlanDragKind.resizeStart,
                            details.globalPosition,
                          )
                        : null,
                    onHorizontalDragUpdate: canDrag
                        ? (details) => _updateGesture(
                            details.globalPosition,
                            width,
                            hourH,
                          )
                        : null,
                    onHorizontalDragEnd: canDrag
                        ? (_) => unawaited(_finishGesture())
                        : null,
                    onHorizontalDragCancel: canDrag ? _cancelGesture : null,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Container(width: 3, color: color),
                    ),
                  ),
                ),
              if (isEndSegment && !isMappedBlock && (canDrag || previewOnly))
                Positioned(
                  right: 0,
                  top: 0,
                  bottom: 0,
                  width: 12,
                  child: GestureDetector(
                    key: ValueKey(
                      '${previewOnly ? 'preview-' : ''}plan-resize-end-${block.id}',
                    ),
                    behavior: HitTestBehavior.translucent,
                    dragStartBehavior: DragStartBehavior.down,
                    onHorizontalDragStart: canDrag
                        ? (details) => _beginGesture(
                            block,
                            PlanDragKind.resizeEnd,
                            details.globalPosition,
                          )
                        : null,
                    onHorizontalDragUpdate: canDrag
                        ? (details) => _updateGesture(
                            details.globalPosition,
                            width,
                            hourH,
                          )
                        : null,
                    onHorizontalDragEnd: canDrag
                        ? (_) => unawaited(_finishGesture())
                        : null,
                    onHorizontalDragCancel: canDrag ? _cancelGesture : null,
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: Container(width: 3, color: color),
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
      widgets.add(
        Positioned(
          key: ValueKey(
            '${previewOnly ? 'preview' : 'anchor'}-${block.id}-$hour',
          ),
          top: hour * hourH + 1,
          left: left + 1,
          width: max(1.0, segmentW - 2),
          height: segmentHeight,
          child: hiddenAnchor
              ? Offstage(offstage: true, child: segmentChild)
              : segmentChild,
        ),
      );
    }
    return widgets;
  }

  List<Widget> _buildDraggingBlocks(double width, double hourH) {
    final s = min(_dragStartBlock!, _dragEndBlock!);
    final e = max(_dragStartBlock!, _dragEndBlock!);
    final color = Theme.of(context).colorScheme.primary;
    final widgets = <Widget>[];

    for (int i = s; i <= e; i++) {
      final hour = i ~/ _blocksPerHour;
      final col = i % _blocksPerHour;
      widgets.add(
        Positioned(
          top: hour * hourH + 1,
          left: width * col / _blocksPerHour + 1,
          width: width / _blocksPerHour - 2,
          height: max(1.0, hourH - 2),
          child: Container(
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        ),
      );
    }
    return widgets;
  }

  Widget _buildNowLine(double width, double hourH) {
    final now = DateTime.now();
    if (now.year != widget.date.year ||
        now.month != widget.date.month ||
        now.day != widget.date.day) {
      return const SizedBox.shrink();
    }

    final top = now.hour * hourH;
    final left = width * (now.minute + now.second / 60) / 60;
    return Positioned(
      top: top,
      left: left,
      height: hourH,
      child: Column(
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: const BoxDecoration(
              color: Colors.red,
              shape: BoxShape.circle,
            ),
          ),
          Expanded(child: Container(width: 1, color: Colors.red)),
        ],
      ),
    );
  }

  void _openMappedBlockDetail(TodoPlanBlock block) {
    if (block.id.startsWith('mapped_course_')) {
      final courseId = block.id.substring('mapped_course_'.length);
      final course = widget.courses.cast<CourseItem?>().firstWhere(
        (item) => item?.uuid == courseId,
        orElse: () => null,
      );
      if (course != null) {
        Navigator.of(context).push(
          PageTransitions.material(
            builder: (_) => CourseDetailScreen(course: course),
          ),
        );
      }
      return;
    }

    if (block.id.startsWith('mapped_todo_')) {
      final todoId = block.id.substring('mapped_todo_'.length);
      final todo = _todoById[todoId];
      if (todo != null) {
        Navigator.of(context).push(
          PageTransitions.material(
            builder: (_) => TodoDetailScreen(todo: todo),
          ),
        );
      }
      return;
    }

    if (HabitChallengePlanningService.isMappedHabitBlock(block)) {
      final habitUuid = HabitChallengePlanningService.habitUuidFromBlock(block);
      final goal = widget.habitChallenge.goals.cast<HabitGoal?>().firstWhere(
        (g) => g?.uuid == habitUuid,
        orElse: () => null,
      );
      if (goal == null) return;
      final rules =
          widget.habitChallenge.rulesByHabitUuid[goal.uuid] ?? const [];
      final rule = HabitRuleResolver.effectiveRule(rules, widget.date);
      final start = DateTime.fromMillisecondsSinceEpoch(block.startTime);
      final end = DateTime.fromMillisecondsSinceEpoch(block.endTime);
      showAppModalBottomSheet<void>(
        context: context,
        builder: (sheetCtx) {
          final cs = Theme.of(sheetCtx).colorScheme;
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(goal.icon, style: const TextStyle(fontSize: 28)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              goal.name,
                              style: Theme.of(sheetCtx).textTheme.titleMedium
                                  ?.copyWith(fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '习惯软预留 · ${AppTimeFormats.dateFormatter('HH:mm').format(start)}–${AppTimeFormats.dateFormatter('HH:mm').format(end)} (${block.plannedMinutes} 分钟)',
                              style: Theme.of(sheetCtx).textTheme.bodySmall
                                  ?.copyWith(color: cs.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.insights_outlined, size: 18),
                          label: const Text('习惯详情'),
                          onPressed: () async {
                            Navigator.pop(sheetCtx);
                            await Navigator.of(context).push(
                              PageTransitions.material(
                                builder: (_) => HabitDetailScreen(
                                  goal: goal,
                                  username: widget.username,
                                ),
                              ),
                            );
                            widget.onRefresh();
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton.icon(
                          icon: const Icon(Icons.timer_outlined, size: 18),
                          label: const Text('开始专注'),
                          onPressed: () {
                            Navigator.pop(sheetCtx);
                            HabitFocusLauncher.open(
                              context: context,
                              username: widget.username,
                              goal: goal,
                              rule: rule,
                              onReturned: widget.onRefresh,
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      );
      return;
    }

    if (HabitChallengePlanningService.isMappedChallengeBlock(block)) {
      final taskId = HabitChallengePlanningService.challengeTaskIdFromBlock(
        block,
      );
      final challenge = widget.habitChallenge.challengeState;
      if (challenge == null || taskId == null) return;
      final task = challenge.tasks.where((t) => t.id == taskId).firstOrNull;
      if (task == null) return;
      final start = DateTime.fromMillisecondsSinceEpoch(block.startTime);
      final end = DateTime.fromMillisecondsSinceEpoch(block.endTime);
      showAppModalBottomSheet<void>(
        context: context,
        builder: (sheetCtx) {
          final cs = Theme.of(sheetCtx).colorScheme;
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Text('🎯', style: TextStyle(fontSize: 28)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              task.title,
                              style: Theme.of(sheetCtx).textTheme.titleMedium
                                  ?.copyWith(fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${challenge.challengeTitle} · ${AppTimeFormats.dateFormatter('HH:mm').format(start)}–${AppTimeFormats.dateFormatter('HH:mm').format(end)} (${block.plannedMinutes} 分钟)',
                              style: Theme.of(sheetCtx).textTheme.bodySmall
                                  ?.copyWith(color: cs.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(
                            Icons.emoji_events_outlined,
                            size: 18,
                          ),
                          label: const Text('打开挑战'),
                          onPressed: () async {
                            Navigator.pop(sheetCtx);
                            await Navigator.of(context).push(
                              PageTransitions.material(
                                builder: (_) =>
                                    const ThirtyDayChallengeScreen(),
                              ),
                            );
                            widget.onRefresh();
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton.icon(
                          icon: const Icon(Icons.timer_outlined, size: 18),
                          label: const Text('开始专注'),
                          onPressed: () {
                            Navigator.pop(sheetCtx);
                            HabitFocusLauncher.openForChallenge(
                              context: context,
                              username: widget.username,
                              challengeState: challenge,
                              task: task,
                              onReturned: widget.onRefresh,
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      );
    }
  }

  void _showEditBlockSheet(
    TodoPlanBlock block, {
    required GlobalKey sourceKey,
  }) {
    showPlanBlockEditorSheet(
      context: context,
      builder: (context) => PlanBlockEditorSheet(
        block: block,
        onRecover: block.status != TodoPlanStatus.missed
            ? null
            : () {
                if (mounted) {
                  showMissedPlanRecovery(
                    context: this.context,
                    username: widget.username,
                    sourceId: block.id,
                    onSaved: widget.onRefresh,
                  );
                }
              },
        startTime: DateTime.fromMillisecondsSinceEpoch(block.startTime),
        endTime: DateTime.fromMillisecondsSinceEpoch(block.endTime),
        todos: widget.todos,
        todoGroups: widget.todoGroups,
        username: widget.username,
        initialTodoId: block.todoId,
        onSaved: widget.onRefresh,
        openPomodoro: (planBlock, todo) => PageTransitions.pushFromRect<void>(
          context: context,
          sourceKey: sourceKey,
          placeholderIcon: Icons.timer_outlined,
          page: PomodoroScreen(
            username: widget.username,
            initialEntry: PomodoroEntryIntent.forPlanBlock(
              boundTodo: todo,
              planBlock: planBlock,
            ),
          ),
        ),
        manualCompletionService: _manualCompletion,
        onManualCompleted: (receipt) =>
            _manualHostKey.currentState?.present(receipt),
      ),
    );
  }
}
