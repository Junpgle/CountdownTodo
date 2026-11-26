part of 'todo_section_widget.dart';

// ignore_for_file: unused_element, unused_element_parameter, annotate_overrides

mixin _TodoSectionViewCardMixin on _TodoSectionStateBase {
  Widget _buildTodoItemCard(
    TodoItem todo, {
    required bool isPast,
    required bool isFuture,
    required DateTime now,
    Key? key,
    Widget? dragHandle,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final bool isLight = widget.isLight;

    // ── 颜色层 ──
    final Color cardBg = todo.isDone
        ? colorScheme.surfaceContainerHighest.withValues(
            alpha: isLight ? 0.25 : 0.08,
          )
        : colorScheme.surface.withValues(
            alpha: isPast
                ? (isLight ? 0.9 : 0.45)
                : isFuture
                ? (isLight ? 0.85 : 0.35)
                : (isLight ? 0.97 : 0.75),
          );

    final Color titleColor = todo.isDone
        ? colorScheme.onSurface.withValues(alpha: 0.35)
        : (isPast || isFuture
              ? colorScheme.onSurface.withValues(alpha: 0.65)
              : colorScheme.onSurface);
    final bool isRecentlyUpdatedByOthers = widget.highlightedTodoIds.contains(
      todo.id,
    );

    // ── 进度计算 ──
    DateTime cDate = AppTimeFormats.localFromServerTimestamp(
      todo.createdDate ?? todo.createdAt,
    );
    double progress = 0.0;
    if (todo.dueDate != null) {
      final startMicros = cDate.microsecondsSinceEpoch;
      final nowMicros = now.microsecondsSinceEpoch;
      final timeMode = todo.timeModeForStartTime(cDate);
      final end = timeMode == TodoTimeMode.dateOnly
          ? todo.effectiveDueAtForTimeMode(timeMode)!
          : DateTime(
              todo.dueDate!.year,
              todo.dueDate!.month,
              todo.dueDate!.day,
              todo.dueDate!.hour,
              todo.dueDate!.minute,
              59,
            );
      var totalMinutes =
          (end.microsecondsSinceEpoch - startMicros) ~/
          Duration.microsecondsPerMinute;
      if (totalMinutes <= 0) totalMinutes = 1;
      if (nowMicros > startMicros) {
        final elapsedMinutes =
            (nowMicros - startMicros) ~/ Duration.microsecondsPerMinute;
        progress = (elapsedMinutes / totalMinutes).clamp(0.0, 1.0);
      }
    }
    final Color? progressFillColor = todo.isDone
        ? null
        : _getProgressFillColor(progress, isPast);

    // ── 时间徽章文本 ──
    String badge = "";
    Color badgeColor = colorScheme.primary;
    Color badgeBg = colorScheme.primaryContainer.withValues(alpha: 0.6);

    if (todo.dueDate != null) {
      final DateTime d = DateTime(
        todo.dueDate!.year,
        todo.dueDate!.month,
        todo.dueDate!.day,
      );
      final DateTime today = DateTime(now.year, now.month, now.day);
      if (isPast) {
        badge = "已逾期";
        badgeColor = Colors.redAccent.shade200;
        badgeBg = Colors.redAccent.withValues(alpha: 0.12);
      } else if (isFuture) {
        int days = CalendarDateMath.daysBetween(today, d);
        badge = "$days天后";
        badgeColor = colorScheme.secondary;
        badgeBg = colorScheme.secondaryContainer.withValues(alpha: 0.5);
      } else {
        badge = "今天截止";
        badgeColor = Colors.orange.shade700;
        badgeBg = Colors.orange.withValues(alpha: 0.12);
      }
    } else {
      badge = AppTimeFormats.dateFormatter('MM/dd').format(cDate);
      badgeColor = colorScheme.onSurface.withValues(alpha: 0.45);
      badgeBg = colorScheme.onSurface.withValues(alpha: 0.06);
    }

    // ── 循环图标 ──
    Widget? recurrenceIcon;
    if (todo.recurrence != RecurrenceType.none) {
      recurrenceIcon = Icon(
        Icons.repeat_rounded,
        size: 11,
        color: colorScheme.primary.withValues(alpha: 0.6),
      );
    }

    return KeyedSubtree(
      key: Key('todo_item_${todo.id}'),
      child: Dismissible(
        key: key ?? _getTodoDismissKey('dismiss', todo.id),
        direction: DismissDirection.endToStart,
        background: Container(
          margin: const EdgeInsets.only(bottom: 6),
          decoration: BoxDecoration(
            color: Colors.redAccent.shade400,
            borderRadius: BorderRadius.circular(14),
          ),
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.only(right: 20),
          child: const Icon(
            Icons.delete_outline_rounded,
            color: Colors.white,
            size: 22,
          ),
        ),
        confirmDismiss: (_) async {
          if (TodoRecurrenceDeleteService.isRecurring(todo)) {
            await _deleteRecurringTodoWithScope(todo);
            return false;
          }
          return AppDialogs.confirm(
            context,
            title: '确认删除',
            message: '确定要删除「${todo.title}」吗？',
            confirmLabel: '删除',
            destructive: true,
          );
        },
        onDismissed: (_) async {
          _todoDismissKeys.remove('drag_${todo.id}');
          _todoDismissKeys.remove('dismiss_${todo.id}');
          try {
            await StorageService.deleteTodoGlobally(widget.username, todo.id);
            List<TodoItem> updatedList = List.from(widget.todos)
              ..removeWhere((t) => t.id == todo.id);
            widget.onTodosChanged(updatedList);

            final prefs = await SharedPreferences.getInstance();
            final String cacheKey = 'deleted_todos_${widget.username}';
            List<TodoItem> deleted = [];
            String? str = prefs.getString(cacheKey);
            if (str != null) {
              deleted = (jsonDecode(str) as Iterable)
                  .map((e) => TodoItem.fromJson(e))
                  .toList();
            }
            deleted.insert(0, todo);
            if (deleted.length > 100) {
              deleted = deleted.sublist(0, 100);
            }
            await prefs.setString(
              cacheKey,
              jsonEncode(deleted.map((e) => e.toJson()).toList()),
            );
          } catch (e) {
            debugPrint("删除失败: $e");
          }
        },
        child: Builder(
          builder: (cardCtx) => AnimatedBuilder(
            animation:
                _completingAnimations[todo.id] ??
                _TodoSectionStateBase._kIdleAnimation,
            builder: (context, child) {
              final anim = _completingAnimations[todo.id];
              final isAnimating = anim != null && anim.isAnimating;
              if (!isAnimating) return child!;
              final value = anim.value;
              final scale = 1.0 - (value * 0.08);
              final opacity = 1.0 - (value * 0.7);

              return Transform.scale(
                scale: scale,
                child: Opacity(opacity: opacity, child: child),
              );
            },
            child: KeyedSubtree(
              key: _getTodoCardKey(todo.id),
              child: Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: AiGeneratedTodoWaterBorder(
                  enabled: _isAiGeneratedTodo(todo),
                  isLight: isLight,
                  child: OptionalLiquidGlassCard(
                    clipBehavior: Clip.antiAlias,
                    borderRadius: 14,
                    tint:
                        (todo.teamUuid != null
                                ? colorScheme.primary
                                : (isPast && !todo.isDone
                                      ? colorScheme.error
                                      : colorScheme.primary))
                            .withValues(alpha: 0.16),
                    fallbackDecoration: BoxDecoration(
                      color: todo.teamUuid != null
                          ? (isLight
                                ? colorScheme.surface.withValues(alpha: 0.92)
                                : colorScheme.surfaceContainerHighest
                                      .withValues(alpha: 0.4))
                          : cardBg,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: todo.teamUuid != null
                            ? colorScheme.primary.withValues(alpha: 0.2)
                            : (isPast && !todo.isDone
                                  ? Colors.redAccent.withValues(alpha: 0.25)
                                  : colorScheme.outline.withValues(
                                      alpha: isLight ? 0.06 : 0.12,
                                    )),
                        width: todo.teamUuid != null ? 1.2 : 1,
                      ),
                      boxShadow: (!todo.isDone && isLight)
                          ? [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.03),
                                blurRadius: 6,
                                offset: const Offset(0, 2),
                              ),
                            ]
                          : [],
                    ),
                    child: Stack(
                      children: [
                        if (isRecentlyUpdatedByOthers)
                          Positioned.fill(
                            child: IgnorePointer(
                              child: TweenAnimationBuilder<double>(
                                key: ValueKey(
                                  'remote_update_flash_${todo.id}_${widget.remoteUpdateHighlightSignal}',
                                ),
                                tween: Tween<double>(begin: 1, end: 0),
                                duration: const Duration(milliseconds: 1100),
                                curve: Curves.easeOutCubic,
                                builder: (context, value, _) {
                                  if (value <= 0.001) {
                                    return const SizedBox.shrink();
                                  }
                                  return Container(
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(14),
                                      gradient: LinearGradient(
                                        colors: [
                                          Colors.amberAccent.withValues(
                                            alpha: 0.35 * value,
                                          ),
                                          Colors.amberAccent.withValues(
                                            alpha: 0.12 * value,
                                          ),
                                          Colors.transparent,
                                        ],
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                        if (isRecentlyUpdatedByOthers)
                          Positioned.fill(
                            child: IgnorePointer(
                              child: TweenAnimationBuilder<double>(
                                key: ValueKey(
                                  'remote_update_sweep_${todo.id}_${widget.remoteUpdateHighlightSignal}',
                                ),
                                tween: Tween<double>(begin: 0, end: 1),
                                duration: const Duration(milliseconds: 900),
                                curve: Curves.easeOutCubic,
                                builder: (context, value, _) {
                                  if (value >= 0.999) {
                                    return const SizedBox.shrink();
                                  }
                                  return Align(
                                    alignment: Alignment(-1.4 + 2.8 * value, 0),
                                    child: FractionallySizedBox(
                                      widthFactor: 0.3,
                                      heightFactor: 1,
                                      child: Container(
                                        decoration: BoxDecoration(
                                          gradient: LinearGradient(
                                            colors: [
                                              Colors.transparent,
                                              Colors.amberAccent.withValues(
                                                alpha: 0.22,
                                              ),
                                              Colors.transparent,
                                            ],
                                            begin: Alignment.centerLeft,
                                            end: Alignment.centerRight,
                                          ),
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                        if (!todo.isDone)
                          Positioned.fill(
                            child: TweenAnimationBuilder<double>(
                              duration: const Duration(milliseconds: 600),
                              curve: Curves.easeOutQuart,
                              tween: Tween<double>(
                                begin: progress < 0.08
                                    ? 0.08
                                    : progress.clamp(0.0, 1.0),
                                end: progress < 0.08
                                    ? 0.08
                                    : progress.clamp(0.0, 1.0),
                              ),
                              builder: (context, value, child) {
                                return FractionallySizedBox(
                                  alignment: Alignment.centerLeft,
                                  widthFactor: value,
                                  child: child!,
                                );
                              },
                              child: Container(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [
                                      progressFillColor!.withValues(
                                        alpha: isLight ? 0.32 : 0.18,
                                      ),
                                      progressFillColor.withValues(
                                        alpha: isLight ? 0.15 : 0.08,
                                      ),
                                    ],
                                    begin: Alignment.centerLeft,
                                    end: Alignment.centerRight,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(14),
                            onTap: () => _editTodo(todo, cardCtx),
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(minHeight: 52),
                              child: Row(
                                // Stack 中的任务行只有松垂直约束；使用 stretch
                                // 会让行高退化为 0，显式高度可避免额外 intrinsic pass。
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  if (todo.teamUuid != null)
                                    Container(
                                      width: 4,
                                      height: 36,
                                      margin: const EdgeInsets.symmetric(
                                        vertical: 8,
                                      ),
                                      decoration: BoxDecoration(
                                        color: colorScheme.primary,
                                        borderRadius:
                                            const BorderRadius.horizontal(
                                              right: Radius.circular(3),
                                            ),
                                      ),
                                    ),
                                  Expanded(
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 9,
                                      ),
                                      child: Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.center,
                                        children: [
                                          SizedBox(
                                            width: 24,
                                            height: 24,
                                            child: Checkbox(
                                              materialTapTargetSize:
                                                  MaterialTapTargetSize
                                                      .shrinkWrap,
                                              visualDensity:
                                                  VisualDensity.compact,
                                              shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(6),
                                              ),
                                              activeColor: colorScheme.primary,
                                              value: todo.isDone,
                                              onChanged: (val) {
                                                if (val == null) return;

                                                // 🚀 乐观 UI 更新：立即修改状态并通知父组件
                                                final bool wasDone =
                                                    todo.isDone;
                                                _invalidateTodoViewModel();
                                                setState(() {
                                                  todo.isDone = val;
                                                  if (val && todo.isSkipped) {
                                                    todo.isSkipped = false;
                                                    todo.isSkippedSyncPending =
                                                        true;
                                                  }
                                                  if (val) {
                                                    _isCompleting[todo.id] =
                                                        true;
                                                  } else {
                                                    _isCompleting.remove(
                                                      todo.id,
                                                    );
                                                    _completingAnimations[todo
                                                            .id]
                                                        ?.dispose();
                                                    _completingAnimations
                                                        .remove(todo.id);
                                                  }
                                                });

                                                if (val) {
                                                  PomodoroSyncService()
                                                      .sendStopSignal(
                                                        todoUuid: todo.id,
                                                      );
                                                }
                                                todo.markAsChanged();
                                                List<TodoItem> updatedList =
                                                    List.from(widget.todos);
                                                // 排序以将已完成移到底部
                                                updatedList.sort(
                                                  (a, b) => a.isDone == b.isDone
                                                      ? 0
                                                      : (a.isDone ? 1 : -1),
                                                );
                                                widget.onTodosChanged(
                                                  updatedList,
                                                );

                                                if (val && !wasDone) {
                                                  TodoCompletionCelebrationService.playCompletionImpact();
                                                  _checkAndTriggerTodayAllDoneCelebration(
                                                    todo,
                                                  );
                                                  // 播放动画后清理
                                                  _completingAnimations[todo.id]
                                                      ?.dispose();
                                                  final controller =
                                                      AnimationController(
                                                        duration:
                                                            const Duration(
                                                              milliseconds: 400,
                                                            ),
                                                        vsync: this,
                                                      );
                                                  _completingAnimations[todo
                                                          .id] =
                                                      controller;
                                                  controller.forward().then((
                                                    _,
                                                  ) {
                                                    if (mounted) {
                                                      setState(() {
                                                        _isCompleting[todo.id] =
                                                            false;
                                                        _completingAnimations[todo
                                                                .id]
                                                            ?.dispose();
                                                        _completingAnimations
                                                            .remove(todo.id);
                                                      });
                                                    }
                                                  });
                                                }
                                              },
                                            ),
                                          ),
                                          const SizedBox(width: 4),
                                          dragHandle ??
                                              _buildTodoDragHandle(
                                                todo,
                                                colorScheme.onSurfaceVariant,
                                              ),
                                          const SizedBox(width: 6),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Row(
                                                  children: [
                                                    Expanded(
                                                      child: Text(
                                                        todo.title,
                                                        maxLines: 1,
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                        style: TextStyle(
                                                          decoration:
                                                              todo.isDone
                                                              ? TextDecoration
                                                                    .lineThrough
                                                              : null,
                                                          decorationColor:
                                                              colorScheme
                                                                  .onSurface
                                                                  .withValues(
                                                                    alpha: 0.3,
                                                                  ),
                                                          color: titleColor
                                                              .withValues(
                                                                alpha: 0.95,
                                                              ),
                                                          fontSize: 14.5,
                                                          fontWeight:
                                                              todo.isDone ||
                                                                  isPast ||
                                                                  isFuture
                                                              ? FontWeight.w500
                                                              : FontWeight.w600,
                                                          height: 1.2,
                                                        ),
                                                      ),
                                                    ),
                                                    if (recurrenceIcon !=
                                                        null) ...[
                                                      const SizedBox(width: 4),
                                                      recurrenceIcon,
                                                    ],
                                                    if (ConflictVisibilityService.isVisibleTodoConflict(
                                                      todo,
                                                    )) ...[
                                                      const SizedBox(width: 4),
                                                      Icon(
                                                        Icons
                                                            .warning_amber_rounded,
                                                        size: 14,
                                                        color: Colors
                                                            .orange
                                                            .shade400,
                                                      ),
                                                    ],
                                                    const SizedBox(width: 6),
                                                    Container(
                                                      padding:
                                                          const EdgeInsets.symmetric(
                                                            horizontal: 7,
                                                            vertical: 2,
                                                          ),
                                                      decoration: BoxDecoration(
                                                        color: todo.isDone
                                                            ? colorScheme
                                                                  .onSurface
                                                                  .withValues(
                                                                    alpha: 0.06,
                                                                  )
                                                            : badgeBg,
                                                        borderRadius:
                                                            BorderRadius.circular(
                                                              6,
                                                            ),
                                                      ),
                                                      child: Text(
                                                        badge,
                                                        style: TextStyle(
                                                          fontSize: 10.5,
                                                          fontWeight:
                                                              FontWeight.w600,
                                                          color: todo.isDone
                                                              ? colorScheme
                                                                    .onSurface
                                                                    .withValues(
                                                                      alpha:
                                                                          0.3,
                                                                    )
                                                              : badgeColor,
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                                if (todo.teamUuid != null) ...[
                                                  const SizedBox(height: 5),
                                                  Row(
                                                    children: [
                                                      Container(
                                                        padding:
                                                            const EdgeInsets.symmetric(
                                                              horizontal: 6,
                                                              vertical: 2,
                                                            ),
                                                        decoration: BoxDecoration(
                                                          color: colorScheme
                                                              .primary
                                                              .withValues(
                                                                alpha: 0.18,
                                                              ),
                                                          borderRadius:
                                                              BorderRadius.circular(
                                                                4,
                                                              ),
                                                          border: Border.all(
                                                            color: colorScheme
                                                                .primary
                                                                .withValues(
                                                                  alpha: 0.4,
                                                                ),
                                                            width: 0.8,
                                                          ),
                                                        ),
                                                        child: Row(
                                                          mainAxisSize:
                                                              MainAxisSize.min,
                                                          children: [
                                                            Icon(
                                                              _selectedSubTeamUuid ==
                                                                      null
                                                                  ? Icons
                                                                        .groups_rounded
                                                                  : Icons
                                                                        .person_outline_rounded,
                                                              size: 10,
                                                              color: colorScheme
                                                                  .primary,
                                                            ),
                                                            const SizedBox(
                                                              width: 3,
                                                            ),
                                                            Text(
                                                              _selectedSubTeamUuid ==
                                                                      null
                                                                  ? "${todo.teamName ?? '团队'} · ${todo.creatorName ?? '成员'}"
                                                                  : "创建者：${todo.creatorName ?? '成员'}",
                                                              style: TextStyle(
                                                                fontSize: 10,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .bold,
                                                                color:
                                                                    colorScheme
                                                                        .primary,
                                                              ),
                                                            ),
                                                          ],
                                                        ),
                                                      ),
                                                      if (todo.collabType ==
                                                              1 &&
                                                          _teamRoles[todo
                                                                  .teamUuid] ==
                                                              'admin') ...[
                                                        const SizedBox(
                                                          width: 6,
                                                        ),
                                                        GestureDetector(
                                                          onTap: () =>
                                                              _showIndependentTodoStatus(
                                                                todo,
                                                              ),
                                                          child: Container(
                                                            padding:
                                                                const EdgeInsets.symmetric(
                                                                  horizontal: 6,
                                                                  vertical: 2,
                                                                ),
                                                            decoration: BoxDecoration(
                                                              color: Colors
                                                                  .green
                                                                  .withValues(
                                                                    alpha: 0.15,
                                                                  ),
                                                              borderRadius:
                                                                  BorderRadius.circular(
                                                                    4,
                                                                  ),
                                                              border: Border.all(
                                                                color: Colors
                                                                    .green
                                                                    .withValues(
                                                                      alpha:
                                                                          0.4,
                                                                    ),
                                                                width: 0.8,
                                                              ),
                                                            ),
                                                            child: Row(
                                                              children: [
                                                                const Icon(
                                                                  Icons
                                                                      .assignment_turned_in_outlined,
                                                                  size: 10,
                                                                  color: Colors
                                                                      .green,
                                                                ),
                                                                const SizedBox(
                                                                  width: 3,
                                                                ),
                                                                const Text(
                                                                  "独立任务进度",
                                                                  style: TextStyle(
                                                                    fontSize:
                                                                        10,
                                                                    fontWeight:
                                                                        FontWeight
                                                                            .bold,
                                                                    color: Colors
                                                                        .green,
                                                                  ),
                                                                ),
                                                              ],
                                                            ),
                                                          ),
                                                        ),
                                                      ],
                                                    ],
                                                  ),
                                                ],
                                                const SizedBox(height: 3),
                                                Row(
                                                  children: [
                                                    Icon(
                                                      Icons.schedule_rounded,
                                                      size: 11,
                                                      color: colorScheme
                                                          .onSurface
                                                          .withValues(
                                                            alpha: todo.isDone
                                                                ? 0.65
                                                                : (isPast
                                                                      ? 0.75
                                                                      : 0.65),
                                                          ),
                                                    ),
                                                    const SizedBox(width: 3),
                                                    Expanded(
                                                      child: Text(
                                                        _buildTimeLabel(
                                                          todo,
                                                          cDate,
                                                          isPast,
                                                          isFuture,
                                                          now,
                                                        ),
                                                        maxLines: 1,
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                        style: TextStyle(
                                                          fontSize: 11,
                                                          color: colorScheme
                                                              .onSurface
                                                              .withValues(
                                                                alpha:
                                                                    todo.isDone
                                                                    ? 0.4
                                                                    : isPast
                                                                    ? 0.75
                                                                    : 0.65,
                                                              ),
                                                          height: 1.2,
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                                if (todo.remark != null &&
                                                    todo
                                                        .remark!
                                                        .isNotEmpty) ...[
                                                  const SizedBox(height: 2),
                                                  Text(
                                                    todo.remark!,
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: TextStyle(
                                                      fontSize: 11,
                                                      color: colorScheme
                                                          .onSurface
                                                          .withValues(
                                                            alpha: todo.isDone
                                                                ? 0.22
                                                                : 0.4,
                                                          ),
                                                      height: 1.2,
                                                    ),
                                                  ),
                                                ],
                                                if (todo.recurrence !=
                                                        RecurrenceType.none ||
                                                    todo.recurrenceSeriesId !=
                                                        null) ...[
                                                  const SizedBox(height: 6),
                                                  _buildRecurrenceProgress(
                                                    todo,
                                                    now,
                                                  ),
                                                ],
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        if (isRecentlyUpdatedByOthers)
                          Positioned(
                            bottom: 8,
                            right: 10,
                            child: TweenAnimationBuilder<double>(
                              key: ValueKey(
                                'remote_update_badge_${todo.id}_${widget.remoteUpdateHighlightSignal}',
                              ),
                              tween: Tween<double>(begin: 0.8, end: 1.0),
                              duration: const Duration(milliseconds: 650),
                              curve: Curves.easeOutCubic,
                              builder: (context, scale, child) {
                                if (scale >= 0.999) return child!;
                                return Transform.scale(
                                  scale: scale,
                                  child: child,
                                );
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.amberAccent.withValues(
                                    alpha: 0.24,
                                  ),
                                  borderRadius: BorderRadius.circular(999),
                                  border: Border.all(
                                    color: Colors.amberAccent.withValues(
                                      alpha: 0.9,
                                    ),
                                    width: 1,
                                  ),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.bolt_rounded,
                                      size: 12,
                                      color: Colors.amberAccent,
                                    ),
                                    SizedBox(width: 4),
                                    Text(
                                      '远端更新',
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w800,
                                        color: Colors.amberAccent,
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
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// A card-wide long press wins the gesture arena before a slow vertical
  /// scroll. Keep task moving available on a dedicated handle instead.
  Widget _buildTodoDragHandle(TodoItem todo, Color color) {
    return LongPressDraggable<String>(
      data: todo.id,
      feedback: Material(
        color: Colors.transparent,
        child: Container(
          width: MediaQuery.sizeOf(context).width * 0.8,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(14),
            boxShadow: const [
              BoxShadow(color: Colors.black26, blurRadius: 12, spreadRadius: 1),
            ],
          ),
          child: Text(
            todo.title,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurface,
              fontSize: 14,
            ),
          ),
        ),
      ),
      child: _buildTodoDragHandleIcon(todo, color),
    );
  }

  Widget _buildTodoDragHandleIcon(TodoItem todo, Color color) {
    return Semantics(
      label: '长按拖动 ${todo.title}',
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
        child: Icon(Icons.drag_indicator_rounded, size: 16, color: color),
      ),
    );
  }

  Widget _buildExpandTransition(Widget child, Animation<double> animation) {
    return AnimatedBuilder(
      animation: animation,
      child: child,
      builder: (context, child) {
        if (animation.value <= 0.001) {
          return const SizedBox.shrink();
        }
        if (animation.value >= 0.999) {
          return child!;
        }
        return FadeTransition(
          opacity: animation,
          child: SizeTransition(
            sizeFactor: animation,
            alignment: AlignmentDirectional.topStart,
            child: child,
          ),
        );
      },
    );
  }

  Widget _buildAnimatedSection({
    required bool expanded,
    required Widget child,
  }) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      transitionBuilder: _buildExpandTransition,
      child: expanded
          ? Container(key: const ValueKey('expanded_content'), child: child)
          : const SizedBox.shrink(key: ValueKey('collapsed_empty')),
    );
  }

  Widget _buildGroupLabel({
    required String text,
    required bool expanded,
    required VoidCallback onTap,
    Color? color,
    IconData? icon,
    Widget? trailing,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
        child: Row(
          children: [
            Icon(
              expanded
                  ? Icons.keyboard_arrow_down_rounded
                  : Icons.keyboard_arrow_right_rounded,
              size: 20,
              color: (color ?? Theme.of(context).colorScheme.onSurface)
                  .withValues(alpha: 0.5),
            ),
            const SizedBox(width: 8),
            if (icon != null) ...[
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 6),
            ],
            Text(
              text,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: (color ?? Theme.of(context).colorScheme.onSurface)
                    .withValues(alpha: 0.8),
                letterSpacing: 0.5,
              ),
            ),
            if (trailing != null) ...[const Spacer(), trailing],
          ],
        ),
      ),
    );
  }
}
