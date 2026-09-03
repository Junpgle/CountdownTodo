part of 'todo_section_widget.dart';

// ignore_for_file: annotate_overrides

mixin _TodoSectionViewMixin on _TodoSectionStateBase {
  Widget _buildTodoItemCard(
    TodoItem todo, {
    required bool isPast,
    required bool isFuture,
    Key? key,
    Widget? dragHandle,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final bool isLight = widget.isLight;

    // ── 颜色层 ──
    final Color cardBg = todo.isDone
        ? colorScheme.surfaceContainerHighest
            .withValues(alpha: isLight ? 0.25 : 0.08)
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
    final bool isRecentlyUpdatedByOthers =
        widget.highlightedTodoIds.contains(todo.id);

    // ── 进度计算 ──
    DateTime cDate = DateTime.fromMillisecondsSinceEpoch(
      todo.createdDate ?? todo.createdAt,
      isUtc: true,
    ).toLocal();
    final DateTime now = DateTime.now();
    double progress = 0.0;
    {
      DateTime start = cDate;
      DateTime end = todo.dueDate != null
          ? DateTime(
              todo.dueDate!.year,
              todo.dueDate!.month,
              todo.dueDate!.day,
              todo.dueDate!.hour,
              todo.dueDate!.minute,
              59,
            )
          : DateTime(cDate.year, cDate.month, cDate.day, 23, 59, 59);
      int totalMinutes = end.difference(start).inMinutes;
      if (totalMinutes <= 0) totalMinutes = 1;
      if (now.isAfter(start)) {
        progress = (now.difference(start).inMinutes / totalMinutes).clamp(
          0.0,
          1.0,
        );
      }
    }

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
        int days = d.difference(today).inDays;
        badge = "$days天后";
        badgeColor = colorScheme.secondary;
        badgeBg = colorScheme.secondaryContainer.withValues(alpha: 0.5);
      } else {
        badge = "今天截止";
        badgeColor = Colors.orange.shade700;
        badgeBg = Colors.orange.withValues(alpha: 0.12);
      }
    } else {
      badge = DateFormat('MM/dd').format(cDate);
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
              return await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('确认删除'),
                  content: Text('确定要删除「${todo.title}」吗？'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('取消'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      style: TextButton.styleFrom(
                          foregroundColor: Colors.redAccent),
                      child: const Text('删除'),
                    ),
                  ],
                ),
              );
            },
            onDismissed: (_) async {
              _todoDismissKeys.remove('drag_${todo.id}');
              _todoDismissKeys.remove('dismiss_${todo.id}');
              try {
                await StorageService.deleteTodoGlobally(
                    widget.username, todo.id);
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
                animation: _completingAnimations[todo.id] ??
                    _TodoSectionStateBase._kIdleAnimation,
                builder: (context, child) {
                  final anim = _completingAnimations[todo.id];
                  final isAnimating = anim != null && anim.isAnimating;
                  final value = isAnimating ? anim.value : 0.0;
                  final scale = 1.0 - (value * 0.08);
                  final opacity = 1.0 - (value * 0.7);

                  return Transform.scale(
                    scale: scale,
                    child: Opacity(
                      opacity: opacity,
                      child: child,
                    ),
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
                        tint: (todo.teamUuid != null
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
                                        alpha: isLight ? 0.06 : 0.12)),
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
                                        'remote_update_flash_${todo.id}_${widget.remoteUpdateHighlightSignal}'),
                                    tween: Tween<double>(begin: 1, end: 0),
                                    duration:
                                        const Duration(milliseconds: 1100),
                                    curve: Curves.easeOutCubic,
                                    builder: (context, value, _) {
                                      return Container(
                                        decoration: BoxDecoration(
                                          borderRadius:
                                              BorderRadius.circular(14),
                                          gradient: LinearGradient(
                                            colors: [
                                              Colors.amberAccent.withValues(
                                                  alpha: 0.35 * value),
                                              Colors.amberAccent.withValues(
                                                  alpha: 0.12 * value),
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
                                        'remote_update_sweep_${todo.id}_${widget.remoteUpdateHighlightSignal}'),
                                    tween: Tween<double>(begin: 0, end: 1),
                                    duration: const Duration(milliseconds: 900),
                                    curve: Curves.easeOutCubic,
                                    builder: (context, value, _) {
                                      return Align(
                                        alignment:
                                            Alignment(-1.4 + 2.8 * value, 0),
                                        child: FractionallySizedBox(
                                          widthFactor: 0.3,
                                          heightFactor: 1,
                                          child: Container(
                                            decoration: BoxDecoration(
                                              gradient: LinearGradient(
                                                colors: [
                                                  Colors.transparent,
                                                  Colors.amberAccent
                                                      .withValues(alpha: 0.22),
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
                                  duration: const Duration(milliseconds: 1200),
                                  curve: Curves.easeOutQuart,
                                  tween: Tween<double>(
                                      begin: 0.0,
                                      end: progress < 0.08
                                          ? 0.08
                                          : progress.clamp(0.0, 1.0)),
                                  builder: (context, value, child) {
                                    final fillColor =
                                        _getProgressFillColor(progress, isPast);
                                    return FractionallySizedBox(
                                      alignment: Alignment.centerLeft,
                                      widthFactor: value,
                                      child: Container(
                                        decoration: BoxDecoration(
                                          gradient: LinearGradient(
                                            colors: [
                                              fillColor.withValues(
                                                  alpha: isLight ? 0.32 : 0.18),
                                              fillColor.withValues(
                                                  alpha: isLight ? 0.15 : 0.08),
                                            ],
                                            begin: Alignment.centerLeft,
                                            end: Alignment.centerRight,
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                            Material(
                              color: Colors.transparent,
                              child: InkWell(
                                borderRadius: BorderRadius.circular(14),
                                onTap: () => _editTodo(todo, cardCtx),
                                child: ConstrainedBox(
                                  constraints: const BoxConstraints(
                                    minHeight: 52,
                                  ),
                                  child: Row(
                                    // Stack 中的任务行只有松垂直约束；使用 stretch
                                    // 会让行高退化为 0，显式高度可避免额外 intrinsic pass。
                                    crossAxisAlignment:
                                        CrossAxisAlignment.center,
                                    children: [
                                      if (todo.teamUuid != null)
                                        Container(
                                          width: 4,
                                          height: 36,
                                          margin: const EdgeInsets.symmetric(
                                              vertical: 8),
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
                                              horizontal: 12, vertical: 9),
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
                                                          BorderRadius.circular(
                                                              6)),
                                                  activeColor:
                                                      colorScheme.primary,
                                                  value: todo.isDone,
                                                  onChanged: (val) {
                                                    if (val == null) return;

                                                    // 🚀 乐观 UI 更新：立即修改状态并通知父组件
                                                    final bool wasDone =
                                                        todo.isDone;
                                                    setState(() {
                                                      todo.isDone = val;
                                                      if (val) {
                                                        _isCompleting[todo.id] =
                                                            true;
                                                      } else {
                                                        _isCompleting
                                                            .remove(todo.id);
                                                        _completingAnimations[
                                                                todo.id]
                                                            ?.dispose();
                                                        _completingAnimations
                                                            .remove(todo.id);
                                                      }
                                                    });

                                                    if (val) {
                                                      PomodoroSyncService()
                                                          .sendStopSignal(
                                                              todoUuid:
                                                                  todo.id);
                                                    }
                                                    todo.markAsChanged();
                                                    List<TodoItem> updatedList =
                                                        List.from(widget.todos);
                                                    // 排序以将已完成移到底部
                                                    updatedList.sort((a, b) =>
                                                        a.isDone == b.isDone
                                                            ? 0
                                                            : (a.isDone
                                                                ? 1
                                                                : -1));
                                                    widget.onTodosChanged(
                                                        updatedList);

                                                    if (val && !wasDone) {
                                                      // 播放动画后清理
                                                      _completingAnimations[
                                                              todo.id]
                                                          ?.dispose();
                                                      final controller =
                                                          AnimationController(
                                                              duration:
                                                                  const Duration(
                                                                      milliseconds:
                                                                          400),
                                                              vsync: this);
                                                      _completingAnimations[
                                                          todo.id] = controller;
                                                      controller
                                                          .forward()
                                                          .then((_) {
                                                        if (mounted) {
                                                          setState(() {
                                                            _isCompleting[todo
                                                                .id] = false;
                                                            _completingAnimations[
                                                                    todo.id]
                                                                ?.dispose();
                                                            _completingAnimations
                                                                .remove(
                                                                    todo.id);
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
                                                            overflow:
                                                                TextOverflow
                                                                    .ellipsis,
                                                            style: TextStyle(
                                                              decoration: todo
                                                                      .isDone
                                                                  ? TextDecoration
                                                                      .lineThrough
                                                                  : null,
                                                              decorationColor:
                                                                  colorScheme
                                                                      .onSurface
                                                                      .withValues(
                                                                          alpha:
                                                                              0.3),
                                                              color: titleColor
                                                                  .withValues(
                                                                      alpha:
                                                                          0.95),
                                                              fontSize: 14.5,
                                                              fontWeight: todo
                                                                          .isDone ||
                                                                      isPast ||
                                                                      isFuture
                                                                  ? FontWeight
                                                                      .w500
                                                                  : FontWeight
                                                                      .w600,
                                                              height: 1.2,
                                                            ),
                                                          ),
                                                        ),
                                                        if (recurrenceIcon !=
                                                            null) ...[
                                                          const SizedBox(
                                                              width: 4),
                                                          recurrenceIcon,
                                                        ],
                                                        if (todo
                                                            .hasConflict) ...[
                                                          const SizedBox(
                                                              width: 4),
                                                          Icon(
                                                            Icons
                                                                .warning_amber_rounded,
                                                            size: 14,
                                                            color: Colors.orange
                                                                .shade400,
                                                          ),
                                                        ],
                                                        const SizedBox(
                                                            width: 6),
                                                        Container(
                                                          padding:
                                                              const EdgeInsets
                                                                  .symmetric(
                                                                  horizontal: 7,
                                                                  vertical: 2),
                                                          decoration:
                                                              BoxDecoration(
                                                            color: todo.isDone
                                                                ? colorScheme
                                                                    .onSurface
                                                                    .withValues(
                                                                        alpha:
                                                                            0.06)
                                                                : badgeBg,
                                                            borderRadius:
                                                                BorderRadius
                                                                    .circular(
                                                                        6),
                                                          ),
                                                          child: Text(
                                                            badge,
                                                            style: TextStyle(
                                                                fontSize: 10.5,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w600,
                                                                color: todo
                                                                        .isDone
                                                                    ? colorScheme
                                                                        .onSurface
                                                                        .withValues(
                                                                            alpha:
                                                                                0.3)
                                                                    : badgeColor),
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                    if (todo.teamUuid !=
                                                        null) ...[
                                                      const SizedBox(height: 5),
                                                      Row(
                                                        children: [
                                                          Container(
                                                            padding:
                                                                const EdgeInsets
                                                                    .symmetric(
                                                                    horizontal:
                                                                        6,
                                                                    vertical:
                                                                        2),
                                                            decoration:
                                                                BoxDecoration(
                                                              color: colorScheme
                                                                  .primary
                                                                  .withValues(
                                                                      alpha:
                                                                          0.18),
                                                              borderRadius:
                                                                  BorderRadius
                                                                      .circular(
                                                                          4),
                                                              border: Border.all(
                                                                  color: colorScheme
                                                                      .primary
                                                                      .withValues(
                                                                          alpha:
                                                                              0.4),
                                                                  width: 0.8),
                                                            ),
                                                            child: Row(
                                                              mainAxisSize:
                                                                  MainAxisSize
                                                                      .min,
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
                                                                        .primary),
                                                                const SizedBox(
                                                                    width: 3),
                                                                Text(
                                                                    _selectedSubTeamUuid ==
                                                                            null
                                                                        ? "${todo.teamName ?? '团队'} · ${todo.creatorName ?? '成员'}"
                                                                        : "创建者：${todo.creatorName ?? '成员'}",
                                                                    style: TextStyle(
                                                                        fontSize:
                                                                            10,
                                                                        fontWeight:
                                                                            FontWeight
                                                                                .bold,
                                                                        color: colorScheme
                                                                            .primary)),
                                                              ],
                                                            ),
                                                          ),
                                                          if (todo.collabType ==
                                                                  1 &&
                                                              _teamRoles[todo
                                                                      .teamUuid] ==
                                                                  'admin') ...[
                                                            const SizedBox(
                                                                width: 6),
                                                            GestureDetector(
                                                              onTap: () =>
                                                                  _showIndependentTodoStatus(
                                                                      todo),
                                                              child: Container(
                                                                padding: const EdgeInsets
                                                                    .symmetric(
                                                                    horizontal:
                                                                        6,
                                                                    vertical:
                                                                        2),
                                                                decoration:
                                                                    BoxDecoration(
                                                                  color: Colors
                                                                      .green
                                                                      .withValues(
                                                                          alpha:
                                                                              0.15),
                                                                  borderRadius:
                                                                      BorderRadius
                                                                          .circular(
                                                                              4),
                                                                  border: Border.all(
                                                                      color: Colors
                                                                          .green
                                                                          .withValues(
                                                                              alpha:
                                                                                  0.4),
                                                                      width:
                                                                          0.8),
                                                                ),
                                                                child: Row(
                                                                  children: [
                                                                    const Icon(
                                                                        Icons
                                                                            .assignment_turned_in_outlined,
                                                                        size:
                                                                            10,
                                                                        color: Colors
                                                                            .green),
                                                                    const SizedBox(
                                                                        width:
                                                                            3),
                                                                    const Text(
                                                                        "独立任务进度",
                                                                        style: TextStyle(
                                                                            fontSize:
                                                                                10,
                                                                            fontWeight:
                                                                                FontWeight.bold,
                                                                            color: Colors.green)),
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
                                                            Icons
                                                                .schedule_rounded,
                                                            size: 11,
                                                            color: colorScheme
                                                                .onSurface
                                                                .withValues(
                                                                    alpha: todo
                                                                            .isDone
                                                                        ? 0.65
                                                                        : (isPast
                                                                            ? 0.75
                                                                            : 0.65))),
                                                        const SizedBox(
                                                            width: 3),
                                                        Expanded(
                                                            child: Text(
                                                                _buildTimeLabel(
                                                                    todo,
                                                                    cDate,
                                                                    isPast,
                                                                    isFuture,
                                                                    now),
                                                                maxLines: 1,
                                                                overflow:
                                                                    TextOverflow
                                                                        .ellipsis,
                                                                style: TextStyle(
                                                                    fontSize: 11,
                                                                    color: colorScheme.onSurface.withValues(
                                                                        alpha: todo.isDone
                                                                            ? 0.4
                                                                            : isPast
                                                                                ? 0.75
                                                                                : 0.65),
                                                                    height: 1.2))),
                                                      ],
                                                    ),
                                                    if (todo.remark != null &&
                                                        todo.remark!
                                                            .isNotEmpty) ...[
                                                      const SizedBox(height: 2),
                                                      Text(todo.remark!,
                                                          maxLines: 1,
                                                          overflow: TextOverflow
                                                              .ellipsis,
                                                          style: TextStyle(
                                                              fontSize: 11,
                                                              color: colorScheme
                                                                  .onSurface
                                                                  .withValues(
                                                                      alpha: todo
                                                                              .isDone
                                                                          ? 0.22
                                                                          : 0.4),
                                                              height: 1.2)),
                                                    ],
                                                    if (todo.recurrence !=
                                                            RecurrenceType
                                                                .none ||
                                                        todo.recurrenceSeriesId !=
                                                            null) ...[
                                                      const SizedBox(height: 6),
                                                      _buildRecurrenceProgress(
                                                          todo, now),
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
                                      'remote_update_badge_${todo.id}_${widget.remoteUpdateHighlightSignal}'),
                                  tween: Tween<double>(begin: 0.8, end: 1.0),
                                  duration: const Duration(milliseconds: 650),
                                  curve: Curves.easeOutCubic,
                                  builder: (context, scale, child) {
                                    return Transform.scale(
                                      scale: scale,
                                      child: child,
                                    );
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: Colors.amberAccent
                                          .withValues(alpha: 0.24),
                                      borderRadius: BorderRadius.circular(999),
                                      border: Border.all(
                                        color: Colors.amberAccent
                                            .withValues(alpha: 0.9),
                                        width: 1,
                                      ),
                                    ),
                                    child: const Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.bolt_rounded,
                                            size: 12,
                                            color: Colors.amberAccent),
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
          width: MediaQuery.of(context).size.width * 0.8,
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

  Widget _buildAnimatedSection(
      {required bool expanded, required Widget child}) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      transitionBuilder: (Widget child, Animation<double> animation) {
        return FadeTransition(
          opacity: animation,
          child: SizeTransition(
            sizeFactor: animation,
            alignment: AlignmentDirectional.topStart,
            child: child,
          ),
        );
      },
      child: expanded
          ? Container(
              key: const ValueKey('expanded_content'),
              child: child,
            )
          : const SizedBox.shrink(key: ValueKey('collapsed_empty')),
    );
  }

  Widget _buildGroupLabel({
    required String text,
    required bool expanded,
    required VoidCallback onTap,
    Color? color,
    IconData? icon,
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
          ],
        ),
      ),
    );
  }

  Widget _buildTodoList() {
    final DateTime now = DateTime.now();
    final DateTime today = DateTime(now.year, now.month, now.day);
    final viewModelSignature = _computeViewModelSignature(today);
    if ((_cachedVm != null && _cachedVm!.today != today) ||
        _cachedVmSignature != viewModelSignature) {
      _cachedVm = null;
      _cachedVmSignature = viewModelSignature;
    }
    _cachedVm ??= _computeViewModel();
    final vm = _cachedVm!;

    final bool isDarkTheme = Theme.of(context).brightness == Brightness.dark;
    final bool useDarkUI = isDarkTheme || widget.isLight;

    final bool hideFolders =
        _folderDisplayMode == _TodoFolderDisplayMode.hidden;
    final bool separateFolders =
        _folderDisplayMode == _TodoFolderDisplayMode.separate;

    if (vm.activeTodos.isEmpty && vm.activeGroups.isEmpty) {
      return EmptyState(text: "暂无待办，去添加一个吧", isLight: widget.isLight);
    }

    final int undoneCount = vm.undoneCount;
    final List<_SortedDisplayItem> pastItems = vm.pastItems;
    final List<_SortedDisplayItem> todayItems = vm.todayItems;
    final List<_SortedDisplayItem> futureItems = vm.futureItems;
    final List<_GroupDisplayData> separateGroupData = vm.separateGroupData;

    final List<Widget> sections = [];

    if (separateFolders && separateGroupData.isNotEmpty) {
      sections.add(
        _buildGroupLabel(
          text: "📂 文件夹",
          expanded: true,
          color: Theme.of(context).colorScheme.primary,
          onTap: () {},
        ),
      );
      sections.add(Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: separateGroupData
            .map((data) => _buildGroupWidget(data.group, data.todos))
            .toList(),
      ));
    }

    if (pastItems.isNotEmpty) {
      sections.add(
        _buildGroupLabel(
          text: "逾期 · ${pastItems.length}",
          expanded: _isPastTodosExpanded,
          color: Colors.redAccent.shade200,
          onTap: () =>
              setState(() => _isPastTodosExpanded = !_isPastTodosExpanded),
        ),
      );
      sections.add(
        _buildAnimatedSection(
          expanded: _isPastTodosExpanded,
          child: Column(
            children: pastItems.map((item) {
              final todo = item.todo;
              if (todo != null) {
                return _buildTodoItemCard(todo,
                    isPast: true,
                    isFuture: false,
                    key: _getTodoDismissKey('dismiss', todo.id));
              }
              return _buildGroupWidget(item.group!, item.groupTodos!);
            }).toList(),
          ),
        ),
      );
    }

    final bool allTodayDone =
        todayItems.isNotEmpty && todayItems.every((t) => t.isDone);
    final bool showTodayItems =
        _isTodayManuallyExpanded || (!allTodayDone && _isTodayExpanded);

    // ── 今日板块动画封装 ──
    sections.add(
      AnimatedSwitcher(
        duration: const Duration(milliseconds: 400),
        transitionBuilder: (child, animation) {
          return FadeTransition(
              opacity: animation,
              child: SizeTransition(
                  sizeFactor: animation,
                  alignment: AlignmentDirectional.topStart,
                  child: child));
        },
        child: (!showTodayItems && todayItems.isNotEmpty)
            ? GestureDetector(
                key: const ValueKey('today_summary_card'),
                onTap: () => setState(() {
                  _isTodayManuallyExpanded = true;
                  _isTodayExpanded = true;
                }),
                child: Container(
                  margin: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: widget.isLight
                        ? (isDarkTheme
                            ? Colors.grey[850]!.withValues(alpha: 0.95)
                            : Colors.white.withValues(alpha: 0.95))
                        : (allTodayDone
                            ? (isDarkTheme
                                ? Colors.green.withValues(alpha: 0.15)
                                : Colors.green.withValues(alpha: 0.08))
                            : (isDarkTheme
                                ? Colors.white.withValues(alpha: 0.08)
                                : Theme.of(context)
                                    .colorScheme
                                    .primary
                                    .withValues(alpha: 0.04))),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: allTodayDone
                          ? Colors.green.withValues(alpha: 0.4)
                          : (widget.isLight
                              ? (isDarkTheme
                                  ? Colors.white.withValues(alpha: 0.15)
                                  : Colors.black.withValues(alpha: 0.1))
                              : (isDarkTheme
                                  ? Colors.white.withValues(alpha: 0.22)
                                  : Theme.of(context)
                                      .colorScheme
                                      .primary
                                      .withValues(alpha: 0.25))),
                      width: 1.5,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black
                            .withValues(alpha: widget.isLight ? 0.15 : 0.08),
                        blurRadius: 12,
                        offset: const Offset(0, 5),
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 16),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                              color: allTodayDone
                                  ? Colors.green.withValues(alpha: 0.1)
                                  : Theme.of(context)
                                      .colorScheme
                                      .primary
                                      .withValues(alpha: 0.1),
                              shape: BoxShape.circle),
                          child: Icon(
                              allTodayDone
                                  ? Icons.celebration_rounded
                                  : Icons.task_alt_rounded,
                              size: 20,
                              color: allTodayDone
                                  ? Colors.green
                                  : Theme.of(context).colorScheme.primary),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(allTodayDone ? "任务已全部达成！" : "今日事今日毕",
                                  style: TextStyle(
                                      color: allTodayDone
                                          ? (isDarkTheme
                                              ? Colors.green.shade200
                                              : Colors.green.shade900)
                                          : (widget.isLight
                                              ? (isDarkTheme
                                                  ? Colors.white
                                                  : Colors.black)
                                              : (isDarkTheme
                                                  ? Colors.white
                                                      .withValues(alpha: 0.9)
                                                  : Colors.black.withValues(
                                                      alpha: 0.85))),
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                      letterSpacing: 0.2)),
                              const SizedBox(height: 2),
                              Text(
                                  allTodayDone
                                      ? "今天也很努力呢，休息一下吧 ✨"
                                      : "今日还有 ${todayItems.where((t) => !t.isDone).length} 个待办等待完成",
                                  style: TextStyle(
                                      color: (allTodayDone
                                          ? (isDarkTheme
                                              ? Colors.green[200]
                                              : Colors.green[800])
                                          : (widget.isLight
                                              ? (isDarkTheme
                                                  ? Colors.white
                                                      .withValues(alpha: 0.7)
                                                  : Colors.black
                                                      .withValues(alpha: 0.6))
                                              : (isDarkTheme
                                                  ? Colors.white
                                                  : Colors.black))),
                                      fontSize: 12.5)),
                            ],
                          ),
                        ),
                        Icon(Icons.arrow_forward_ios_rounded,
                            size: 14,
                            color: (allTodayDone ? Colors.green : Colors.grey)
                                .withValues(alpha: 0.5)),
                      ],
                    ),
                  ),
                ),
              )
            : (showTodayItems && todayItems.isNotEmpty)
                ? Column(
                    key: const ValueKey('today_expanded_items'),
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildGroupLabel(
                        text:
                            "今日 · ${todayItems.where((t) => t.isDone).length}/${todayItems.length} 已完成",
                        expanded: true,
                        onTap: () => setState(() {
                          _isTodayExpanded = false;
                          _isTodayManuallyExpanded = false;
                        }),
                      ),
                      _buildAnimatedSection(
                        expanded: _isTodayExpanded,
                        child: ReorderableListView(
                          padding: EdgeInsets.zero,
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          buildDefaultDragHandles: false,
                          onReorderItem: (oldIndex, newIndex) {
                            final List<int> todayIndices = [];
                            for (int i = 0; i < widget.todos.length; i++) {
                              final t = widget.todos[i];
                              if (_isHistoricalTodo(t) ||
                                  t.isDeleted ||
                                  (!hideFolders && t.groupId != null)) {
                                continue;
                              }
                              if (t.dueDate == null ||
                                  (t.dueDate!.year == today.year &&
                                      t.dueDate!.month == today.month &&
                                      t.dueDate!.day == today.day)) {
                                todayIndices.add(i);
                              }
                            }
                            final reordered =
                                List<_SortedDisplayItem>.from(todayItems);
                            final item = reordered.removeAt(oldIndex);
                            reordered.insert(newIndex, item);
                            final updatedList =
                                List<TodoItem>.from(widget.todos);
                            final reorderedTodos = reordered
                                .where((e) => e.todo != null)
                                .map((e) => e.todo!)
                                .toList();
                            for (int i = 0;
                                i < todayIndices.length &&
                                    i < reorderedTodos.length;
                                i++) {
                              updatedList[todayIndices[i]] = reorderedTodos[i];
                            }
                            widget.onTodosChanged(updatedList);
                          },
                          children: todayItems.asMap().entries.map((entry) {
                            final int index = entry.key;
                            final item = entry.value;
                            if (item.todo != null) {
                              return _buildTodoItemCard(
                                item.todo!,
                                isPast: false,
                                isFuture: false,
                                key: _getTodoDismissKey(
                                    'dismiss', item.todo!.id),
                                dragHandle: ReorderableDelayedDragStartListener(
                                  index: index,
                                  child: _buildTodoDragHandleIcon(
                                    item.todo!,
                                    Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                  ),
                                ),
                              );
                            }
                            return Container(
                                key: ValueKey('group_${item.group!.id}'),
                                child: _buildGroupWidget(
                                    item.group!, item.groupTodos!));
                          }).toList(),
                        ),
                      )
                    ],
                  )
                : const SizedBox.shrink(key: ValueKey('today_empty')),
      ),
    );

    if (futureItems.isNotEmpty) {
      sections.add(_buildGroupLabel(
          text: "将来 · ${futureItems.where((t) => !t.isDone).length} 未完成",
          expanded: _isFutureExpanded,
          icon: Icons.calendar_month_rounded,
          onTap: () => setState(() => _isFutureExpanded = !_isFutureExpanded)));
      sections.add(_buildAnimatedSection(
          expanded: _isFutureExpanded,
          child: Column(
              children: futureItems.map((item) {
            final todo = item.todo;
            if (todo != null) {
              return _buildTodoItemCard(todo,
                  isPast: false,
                  isFuture: true,
                  key: _getTodoDismissKey('dismiss', todo.id));
            }
            return _buildGroupWidget(item.group!, item.groupTodos!);
          }).toList())));
    }

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 500),
      transitionBuilder: (Widget child, Animation<double> animation) {
        return FadeTransition(
            opacity: animation,
            child: SizeTransition(
                sizeFactor: animation,
                alignment: AlignmentDirectional.topStart,
                child: child));
      },
      child: !_isWholeListExpanded
          ? GestureDetector(
              key: const ValueKey('collapsed_card'),
              onTap: () => setState(() => _isWholeListExpanded = true),
              child: Container(
                margin: const EdgeInsets.symmetric(vertical: 8),
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                decoration: BoxDecoration(
                  color: widget.isLight
                      ? (isDarkTheme
                          ? Colors.grey[850]!.withValues(alpha: 0.95)
                          : Colors.white.withValues(alpha: 0.95))
                      : null,
                  gradient: widget.isLight
                      ? null
                      : LinearGradient(
                          colors: useDarkUI
                              ? [
                                  Colors.white.withValues(alpha: 0.12),
                                  Colors.white.withValues(alpha: 0.04)
                                ]
                              : [
                                  Theme.of(context)
                                      .colorScheme
                                      .primary
                                      .withValues(alpha: 0.06),
                                  Theme.of(context)
                                      .colorScheme
                                      .primary
                                      .withValues(alpha: 0.01)
                                ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                      color: widget.isLight
                          ? (isDarkTheme
                              ? Colors.white.withValues(alpha: 0.15)
                              : Colors.black.withValues(alpha: 0.1))
                          : (useDarkUI
                              ? Colors.white.withValues(alpha: 0.1)
                              : Theme.of(context)
                                  .colorScheme
                                  .primary
                                  .withValues(alpha: 0.08)),
                      width: 1),
                ),
                child: Row(
                  children: [
                    Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                            color: Theme.of(context)
                                .colorScheme
                                .primary
                                .withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(10)),
                        child: Icon(Icons.checklist_rtl_rounded,
                            size: 20,
                            color: Theme.of(context).colorScheme.primary)),
                    const SizedBox(width: 16),
                    Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                          Text(
                              undoneCount == 0
                                  ? "全部任务已完成"
                                  : "目前还有 $undoneCount 个待办",
                              style: TextStyle(
                                  color: widget.isLight
                                      ? (isDarkTheme
                                          ? Colors.white
                                          : Colors.black)
                                      : (useDarkUI ? Colors.white : null),
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                  letterSpacing: 0.2)),
                          const SizedBox(height: 2),
                          Text(
                              undoneCount == 0
                                  ? "今天做的不错！点击展开回顾"
                                  : "点击这里展开清单，继续加油吧 ✨",
                              style: TextStyle(
                                  color: widget.isLight
                                      ? (isDarkTheme
                                          ? Colors.white.withValues(alpha: 0.6)
                                          : Colors.black
                                              .withValues(alpha: 0.55))
                                      : (useDarkUI
                                              ? Colors.white
                                              : Colors.black)
                                          .withValues(alpha: 0.5),
                                  fontSize: 12)),
                        ])),
                    Icon(Icons.unfold_more_rounded,
                        size: 18,
                        color: (useDarkUI ? Colors.white : Colors.grey)
                            .withValues(alpha: 0.4)),
                  ],
                ),
              ),
            )
          : Column(
              key: const ValueKey('expanded_list'),
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildTeamFilterTabs(), // 🚀 注入团队分类切换
                ...sections
              ],
            ),
    );
  }

  _TodoSectionViewModel _computeViewModel() {
    final bool hideFolders =
        _folderDisplayMode == _TodoFolderDisplayMode.hidden;
    final bool separateFolders =
        _folderDisplayMode == _TodoFolderDisplayMode.separate;

    final DateTime now = DateTime.now();
    final DateTime today = DateTime(now.year, now.month, now.day);

    final seriesOccurrences = <String, List<TodoItem>>{};
    for (final todo in widget.todos) {
      final seriesId = todo.recurrenceSeriesId;
      if (todo.isDeleted || seriesId == null || seriesId.isEmpty) continue;
      if (_habitOnlyRecurringSeriesIds.contains(seriesId)) continue;
      if (_selectedSubTeamUuid != null &&
          todo.teamUuid != _selectedSubTeamUuid) {
        continue;
      }
      seriesOccurrences.putIfAbsent(seriesId, () => []).add(todo);
    }
    for (final occurrences in seriesOccurrences.values) {
      occurrences.sort((a, b) => (a.createdDate ?? a.createdAt)
          .compareTo(b.createdDate ?? b.createdAt));
    }
    _recurrenceSeriesOccurrences = seriesOccurrences;

    final seriesRepresentativeIds =
        _buildRecurrenceSeriesRepresentativeIds(seriesOccurrences);

    // Build groupById map for O(1) lookup - avoid todoGroups.any() per todo
    final groupById = <String, TodoGroup>{};
    for (final g in widget.todoGroups) {
      if (g.isDeleted) continue;
      if (_selectedSubTeamUuid != null && g.teamUuid != _selectedSubTeamUuid) {
        continue;
      }
      groupById[g.id] = g;
    }

    // Build todosByGroup map and orphaned list in one pass
    final todosByGroup = <String, List<TodoItem>>{};
    final orphanedTodos = <TodoItem>[];
    final displayTodos = _filterHabitOnlyRecurringTodos(
      widget.todos,
      _habitOnlyRecurringSeriesIds,
    );
    for (final t in displayTodos) {
      if (t.isDeleted || _isHistoricalTodo(t)) continue;
      if (_selectedSubTeamUuid != null && t.teamUuid != _selectedSubTeamUuid) {
        continue;
      }
      if (!_shouldDisplayRecurrenceTodo(t, seriesRepresentativeIds)) {
        continue;
      }

      final tid = t.groupId;
      if (!hideFolders &&
          tid != null &&
          tid.isNotEmpty &&
          groupById.containsKey(tid)) {
        todosByGroup.putIfAbsent(tid, () => []).add(t);
      } else {
        orphanedTodos.add(t);
      }
    }

    final Iterable<TodoGroup> activeGroups =
        hideFolders ? const <TodoGroup>[] : groupById.values;

    final List<TodoItem> activeTodos = [
      ...todosByGroup.values.expand((list) => list),
      ...orphanedTodos,
    ];

    final int undoneCount = activeTodos.where((t) => !t.isDone).length;

    List<_SortedDisplayItem> pastItems = [];
    List<_SortedDisplayItem> todayItems = [];
    List<_SortedDisplayItem> futureItems = [];
    List<_GroupDisplayData> separateGroupData = [];

    void placeItem(_SortedDisplayItem item) {
      if (item.date == null) {
        todayItems.add(item);
      } else {
        final d = DateTime(item.date!.year, item.date!.month, item.date!.day);
        if (d.isBefore(today)) {
          pastItems.add(item);
        } else if (d.isAfter(today)) {
          futureItems.add(item);
        } else {
          todayItems.add(item);
        }
      }
    }

    // 1. Process Folders - iterate over active groups (already filtered)
    for (final g in activeGroups) {
      final allGTodos = todosByGroup[g.id] ?? [];
      final gTodos = _selectedSubTeamUuid == null
          ? allGTodos
          : allGTodos.where((t) => t.teamUuid == _selectedSubTeamUuid).toList();

      if (gTodos.isEmpty) continue;

      bool isAllDone = gTodos.isNotEmpty && gTodos.every((t) => t.isDone);
      DateTime? minDate;
      for (var t in gTodos) {
        if (!t.isDone && t.dueDate != null) {
          if (minDate == null || t.dueDate!.isBefore(minDate)) {
            minDate = t.dueDate;
          }
        }
      }
      if (minDate == null) {
        for (var t in gTodos) {
          if (t.dueDate != null) {
            if (minDate == null || t.dueDate!.isBefore(minDate)) {
              minDate = t.dueDate;
            }
          }
        }
      }

      // Calculate folder progress
      double groupProgress = 0.0;
      for (var t in gTodos) {
        if (t.isDone) continue;
        final cDate = DateTime.fromMillisecondsSinceEpoch(
                t.createdDate ?? t.createdAt,
                isUtc: true)
            .toLocal();
        final end = t.dueDate ??
            DateTime(cDate.year, cDate.month, cDate.day, 23, 59, 59);
        final totalMin = end.difference(cDate).inMinutes;
        if (totalMin > 0 && now.isAfter(cDate)) {
          final p =
              (now.difference(cDate).inMinutes / totalMin).clamp(0.0, 1.0);
          if (p > groupProgress) groupProgress = p;
        }
      }

      final groupData = _GroupDisplayData(
        group: g,
        todos: gTodos,
        isAllDone: isAllDone,
        minDate: minDate,
        progress: groupProgress,
      );

      if (!separateFolders) {
        placeItem(_SortedDisplayItem(
          todo: null,
          group: g,
          date: minDate,
          isDone: isAllDone,
          startMs: 0,
          progress: groupProgress,
          groupTodos: gTodos,
        ));
      } else {
        separateGroupData.add(groupData);
      }
    }

    // 2. Process Standalone/Orphaned Todos
    for (final t in orphanedTodos) {
      double todoProgress = 0.0;
      {
        final cDate = DateTime.fromMillisecondsSinceEpoch(
                t.createdDate ?? t.createdAt,
                isUtc: true)
            .toLocal();
        final end = t.dueDate ??
            DateTime(cDate.year, cDate.month, cDate.day, 23, 59, 59);
        final totalMin = end.difference(cDate).inMinutes;
        if (totalMin > 0 && now.isAfter(cDate)) {
          todoProgress =
              (now.difference(cDate).inMinutes / totalMin).clamp(0.0, 1.0);
        }
      }

      placeItem(_SortedDisplayItem(
        todo: t,
        group: null,
        date: t.dueDate,
        isDone: t.isDone,
        startMs: t.createdDate ?? t.createdAt,
        progress: todoProgress,
      ));
    }

    void sortItems(List<_SortedDisplayItem> list) {
      list.sort((a, b) {
        if (a.isDone != b.isDone) return a.isDone ? 1 : -1;
        final progressCmp = b.progress.compareTo(a.progress);
        if (progressCmp != 0) return progressCmp;
        if (a.date != null && b.date != null) return a.date!.compareTo(b.date!);
        if (a.date != null) return -1;
        if (b.date != null) return 1;
        return 0;
      });
    }

    sortItems(pastItems);
    sortItems(todayItems);
    sortItems(futureItems);

    return _TodoSectionViewModel(
      today: today,
      activeTodos: activeTodos,
      activeGroups: activeGroups,
      undoneCount: undoneCount,
      pastItems: pastItems,
      todayItems: todayItems,
      futureItems: futureItems,
      separateGroupData: separateGroupData,
    );
  }

  int _computeViewModelSignature(DateTime today) {
    return Object.hash(
      today.millisecondsSinceEpoch,
      _selectedSubTeamUuid,
      _folderDisplayMode.index,
      Object.hashAll(widget.todos.map((todo) => Object.hash(
            todo.id,
            todo.isDeleted,
            todo.isDone,
            todo.version,
            todo.createdDate,
            todo.createdAt,
            todo.dueDate?.millisecondsSinceEpoch,
            todo.recurrence.index,
            todo.recurrenceSeriesId,
            todo.groupId,
            todo.teamUuid,
          ))),
      Object.hashAll(widget.todoGroups.map((group) => Object.hash(
            group.id,
            group.isDeleted,
            group.isExpanded,
            group.version,
            group.teamUuid,
          ))),
    );
  }

  Widget _buildGroupWidget(TodoGroup g, List<TodoItem> gTodos) {
    final bool urgentFirstFolders =
        _folderDisplayMode == _TodoFolderDisplayMode.urgentFirst;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: TodoGroupWidget(
        group: g,
        groupTodos: gTodos,
        isLight: widget.isLight,
        onlyShowMostUrgentTodo: urgentFirstFolders,
        teamRoles: _teamRoles,
        recurrenceProgressBuilder: (todo) =>
            _buildRecurrenceProgress(todo, DateTime.now()),
        onToggle: () {
          setState(() {
            g.isExpanded = !g.isExpanded;
            g.markAsChanged();
          });
          widget.onGroupsChanged(widget.todoGroups);
        },
        onTodoToggle: (todo) {
          if (!todo.isDone) {
            PomodoroSyncService().sendStopSignal(todoUuid: todo.id);
          }
          todo.isDone = !todo.isDone;
          todo.markAsChanged();
          widget.onTodosChanged(widget.todos);
        },
        onTodoDropped: (todoId) {
          final idx = widget.todos.indexWhere((t) => t.id == todoId);
          if (idx != -1) {
            setState(() {
              widget.todos[idx].groupId = g.id;
              widget.todos[idx].version += 10;
              widget.todos[idx].updatedAt =
                  DateTime.now().millisecondsSinceEpoch;
            });
            widget.onTodosChanged(widget.todos);
          }
        },
        onTodoRemoved: (todoId) {
          final idx = widget.todos.indexWhere((t) => t.id == todoId);
          if (idx != -1 && widget.todos[idx].groupId != null) {
            setState(() {
              widget.todos[idx].groupId = null;
              widget.todos[idx].version += 10;
              widget.todos[idx].updatedAt =
                  DateTime.now().millisecondsSinceEpoch;
            });
            widget.onTodosChanged(widget.todos);
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('自由了！已移出文件夹')),
            );
          }
        },
        onShowIndependentTodoStatus: _showIndependentTodoStatus,
        onDelete: () async {
          final idx = widget.todoGroups.indexWhere((x) => x.id == g.id);
          if (idx != -1) {
            widget.todoGroups[idx].isDeleted = true;
            widget.todoGroups[idx].markAsChanged();
          }
          await StorageService.deleteTodoGroupGlobally(widget.username, g.id);
          widget.onGroupsChanged(widget.todoGroups);
          widget.onRefreshRequested();
        },
        onTodoTap: (todo) => _editTodo(todo, context),
        onTodoDelete: (todo) async {
          setState(() {
            PomodoroSyncService().sendStopSignal(todoUuid: todo.id);
            todo.isDeleted = true;
            todo.markAsChanged();
          });
          widget.onTodosChanged(List<TodoItem>.from(widget.todos));
          await StorageService.deleteTodoGlobally(widget.username, todo.id);
        },
      ),
    );
  }

  /// 🚀 Uni-Sync 4.0: 首页动态团队切换 Tab
  Widget _buildTeamFilterTabs() {
    // 1. 提取所有关联的团队信息 (同时扫描任务和文件夹)
    final Map<String, String> teamMap = {};
    for (var t in widget.todos) {
      if (t.teamUuid != null && t.teamName != null) {
        teamMap[t.teamUuid!] = t.teamName!;
      }
    }
    for (var g in widget.todoGroups) {
      if (g.teamUuid != null && g.teamName != null) {
        teamMap[g.teamUuid!] = g.teamName!;
      }
    }

    if (teamMap.isEmpty) return const SizedBox.shrink();

    final bool isDarkTheme = Theme.of(context).brightness == Brightness.dark;
    final bool useDarkUI = isDarkTheme || widget.isLight;

    return Container(
      height: 40,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            // "全部" 按钮
            _buildFilterChip(
              label: "全部",
              isSelected: _selectedSubTeamUuid == null,
              onTap: () {
                setState(() {
                  _selectedSubTeamUuid = null;
                  _cachedVm = null;
                });
                widget.onTeamChanged?.call(null, null);
              },
              useDarkUI: useDarkUI,
            ),
            const SizedBox(width: 8),
            // 各个团队按钮
            ...teamMap.entries.map((entry) {
              return Padding(
                padding: const EdgeInsets.only(right: 8.0),
                child: _buildFilterChip(
                  label: entry.value,
                  isSelected: _selectedSubTeamUuid == entry.key,
                  onTap: () {
                    setState(() {
                      _selectedSubTeamUuid = entry.key;
                      _cachedVm = null;
                    });
                    widget.onTeamChanged?.call(entry.key, entry.value);
                  },
                  useDarkUI: useDarkUI,
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChip({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
    required bool useDarkUI,
  }) {
    final theme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? theme.primary
              : (useDarkUI ? Colors.white10 : Colors.grey.shade100),
          borderRadius: BorderRadius.circular(20),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: theme.primary.withValues(alpha: 0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  )
                ]
              : [],
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            color: isSelected
                ? Colors.white
                : (useDarkUI ? Colors.white70 : Colors.black87),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isDarkTheme = Theme.of(context).brightness == Brightness.dark;
    final bool useDarkUI = isDarkTheme || widget.isLight;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: SectionHeader(
                title: "待办清单",
                icon: Icons.check_circle_outline,
                actionIcon: Icons.create_new_folder_outlined,
                actionKey: widget.folderKey,
                actionTooltip: "管理文件夹",
                isLight: widget.isLight,
                onAction: () async {
                  await Navigator.of(context).push(
                    PageTransitions.material(
                      builder: (_) => FolderManageScreen(
                        username: widget.username,
                        todoGroups: widget.todoGroups,
                        onGroupsChanged: widget.onGroupsChanged,
                        allTodos: widget.todos,
                        onTodosChanged: widget.onTodosChanged,
                      ),
                    ),
                  );
                  _loadSettings();
                },
              ),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  key: widget.historyKey,
                  child: IconButton(
                    constraints: const BoxConstraints.tightFor(
                      width: floatingGlassStandardControlSize,
                      height: floatingGlassStandardControlSize,
                    ),
                    visualDensity: VisualDensity.standard,
                    style: floatingGlassPlainIconButtonStyle(),
                    icon: Icon(
                      Icons.history,
                      size: 20,
                      color: useDarkUI ? Colors.white70 : Colors.grey,
                    ),
                    onPressed: () async {
                      await Navigator.push(
                        context,
                        PageTransitions.material(
                          builder: (_) =>
                              HistoricalTodosScreen(username: widget.username),
                        ),
                      );
                      widget.onRefreshRequested();
                    },
                  ),
                ),
                IconButton(
                  constraints: const BoxConstraints.tightFor(
                    width: floatingGlassStandardControlSize,
                    height: floatingGlassStandardControlSize,
                  ),
                  visualDensity: VisualDensity.standard,
                  style: floatingGlassPlainIconButtonStyle(),
                  icon: Icon(
                    _isWholeListExpanded
                        ? Icons.expand_less
                        : Icons.expand_more,
                    size: 20,
                    color: useDarkUI ? Colors.white70 : Colors.grey,
                  ),
                  onPressed: () => setState(
                    () => _isWholeListExpanded = !_isWholeListExpanded,
                  ),
                ),
              ],
            ),
          ],
        ),
        _buildTodoList(),
      ],
    );
  }

  Future<_AiAssistantContext> _loadAiAssistantContext() async {
    try {
      final results = await Future.wait<dynamic>([
        CourseService.getAllCourses(widget.username),
        StorageService.getTimeLogs(widget.username),
        PomodoroService.getRecords(),
      ]);
      final courses = (results[0] as List<CourseItem>)
          .where((course) => !course.isDeleted)
          .toList();
      final timeLogs = (results[1] as List<TimeLogItem>)
          .where((log) => !log.isDeleted)
          .toList();
      final pomodoroRecords = (results[2] as List<PomodoroRecord>)
          .where((record) => !record.isDeleted)
          .toList();
      return _AiAssistantContext(
        courses: courses,
        timeLogs: timeLogs,
        pomodoroRecords: pomodoroRecords,
        teams: _teams,
      );
    } catch (e) {
      debugPrint('加载 AI 助手上下文失败: $e');
      return _AiAssistantContext(teams: _teams);
    }
  }

  void _showIndependentTodoStatus(TodoItem todo) async {
    // 🚀 不再使用全局阻塞 Dialog，改为弹窗内局部加载
    showDialog(
      context: context,
      builder: (ctx) => _IndependentStatusDialog(todo: todo),
    );
  }
}
