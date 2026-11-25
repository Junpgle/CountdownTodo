part of 'todo_section_widget.dart';

// ignore_for_file: annotate_overrides

mixin _TodoSectionViewMixin on _TodoSectionStateBase {
  Widget _buildTodoList() {
    final DateTime now = widget.clock();
    final DateTime today = DateTime(now.year, now.month, now.day);
    if (_cachedVmSignatureDate != today ||
        (_cachedVm != null && _cachedVm!.today != today)) {
      _invalidateTodoViewModel();
    }
    _cachedVmSignature ??= _computeViewModelSignature(today);
    _cachedVmSignatureDate ??= today;
    _cachedVm ??= _computeViewModel();
    final vm = _cachedVm!;

    final bool isDarkTheme = Theme.of(context).brightness == Brightness.dark;
    final bool useDarkUI = isDarkTheme || widget.isLight;

    final bool hideFolders =
        _folderDisplayMode == _TodoFolderDisplayMode.hidden;
    final bool separateFolders =
        _folderDisplayMode == _TodoFolderDisplayMode.separate;

    if (vm.activeTodoCount == 0 && vm.activeGroups.isEmpty) {
      return EmptyState(text: "暂无待办，去添加一个吧", isLight: widget.isLight);
    }

    final int undoneCount = vm.undoneCount;
    final List<_SortedDisplayItem> pastItems = vm.pastItems;
    final List<_SortedDisplayItem> todayItems = vm.todayItems;
    final List<_SortedDisplayItem> futureItems = vm.futureItems;
    final List<_GroupDisplayData> separateGroupData = vm.separateGroupData;

    final List<Widget> sections = [];
    final bool allTodayDone = vm.allTodayDone;

    if (_isWholeListExpanded &&
        separateFolders &&
        separateGroupData.isNotEmpty) {
      sections.add(
        _buildGroupLabel(
          text: "📂 文件夹",
          expanded: true,
          color: Theme.of(context).colorScheme.primary,
          onTap: () {},
        ),
      );
      sections.add(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: separateGroupData
              .map((data) => _buildGroupWidget(data.group, data.todos))
              .toList(),
        ),
      );
    }

    if (_isWholeListExpanded && pastItems.isNotEmpty) {
      final List<TodoItem> overdueTodos = vm.overdueTodos;

      if (overdueTodos.isNotEmpty) {
        sections.add(
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 8),
            child: TodoOverdueTriageBanner(
              count: overdueTodos.length,
              isLight: widget.isLight,
              onTap: () => _openOverdueTriage(overdueTodos),
            ),
          ),
        );
      }

      sections.add(
        _buildGroupLabel(
          text: "逾期 · ${pastItems.length}",
          expanded: _isPastTodosExpanded,
          color: Colors.redAccent.shade200,
          onTap: () =>
              setState(() => _isPastTodosExpanded = !_isPastTodosExpanded),
          trailing: overdueTodos.isNotEmpty
              ? TextButton.icon(
                  key: const ValueKey('todo_overdue_triage_header_button'),
                  onPressed: () => _openOverdueTriage(overdueTodos),
                  icon: const Icon(Icons.auto_fix_high_rounded, size: 14),
                  label: const Text('快速整理', style: TextStyle(fontSize: 12)),
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    foregroundColor: Colors.redAccent.shade200,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                  ),
                )
              : null,
        ),
      );
      sections.add(
        _buildAnimatedSection(
          expanded: _isPastTodosExpanded,
          child: _isPastTodosExpanded
              ? Column(
                  children: pastItems
                      .map((item) {
                        final todo = item.todo;
                        if (todo != null) {
                          return _buildTodoItemCard(
                            todo,
                            isPast: true,
                            isFuture: false,
                            now: now,
                            key: _getTodoDismissKey('dismiss', todo.id),
                          );
                        }
                        return _buildGroupWidget(item.group!, item.groupTodos!);
                      })
                      .toList(growable: false),
                )
              : const SizedBox.shrink(),
        ),
      );
    }

    final bool showTodayItems =
        _isTodayManuallyExpanded || (!allTodayDone && _isTodayExpanded);

    // ── 今日板块动画封装 ──
    if (_isWholeListExpanded) {
      sections.add(
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 400),
          transitionBuilder: _buildExpandTransition,
          child: (!showTodayItems && todayItems.isNotEmpty)
              ? GestureDetector(
                  key: const ValueKey('today_summary_card'),
                  onTap: () => setState(() {
                    _isTodayManuallyExpanded = true;
                    _isTodayExpanded = true;
                  }),
                  child: OptionalLiquidGlassCard(
                    margin: const EdgeInsets.symmetric(vertical: 10),
                    borderRadius: 20,
                    tint: allTodayDone
                        ? Colors.green.withValues(alpha: 0.16)
                        : Theme.of(context).colorScheme.primary
                              .withValues(alpha: 0.14),
                    isDark: isDarkTheme,
                    fallbackDecoration: BoxDecoration(
                      color: isDarkTheme
                          ? Colors.grey[850]!.withValues(alpha: 0.95)
                          : Colors.white.withValues(alpha: 0.95),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: allTodayDone
                            ? Colors.green.withValues(alpha: 0.4)
                            : (isDarkTheme
                                  ? Colors.white.withValues(alpha: 0.15)
                                  : Colors.black.withValues(alpha: 0.1)),
                        width: 1.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(
                            alpha: isDarkTheme ? 0.25 : 0.08,
                          ),
                          blurRadius: 12,
                          offset: const Offset(0, 5),
                        ),
                      ],
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 16,
                      ),
                      child: Row(
                        children: [
                          GestureDetector(
                            onTap: allTodayDone
                                ? () {
                                    TodoCompletionCelebrationService.playCelebrationImpact();
                                    showTodoAllDoneCelebration(
                                      context,
                                      completedTodayCount: todayItems.length,
                                    );
                                  }
                                : null,
                            child: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: allTodayDone
                                    ? Colors.green.withValues(alpha: 0.1)
                                    : Theme.of(context).colorScheme.primary
                                          .withValues(alpha: 0.1),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                allTodayDone
                                    ? Icons.celebration_rounded
                                    : Icons.task_alt_rounded,
                                size: 20,
                                color: allTodayDone
                                    ? Colors.green
                                    : Theme.of(context).colorScheme.primary,
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  allTodayDone ? "任务已全部达成！" : "今日事今日毕",
                                  style: TextStyle(
                                    color: allTodayDone
                                        ? (isDarkTheme
                                              ? Colors.green.shade200
                                              : Colors.green.shade900)
                                        : (isDarkTheme
                                              ? Colors.white
                                              : Colors.black.withValues(
                                                  alpha: 0.85,
                                                )),
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                    letterSpacing: 0.2,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  allTodayDone
                                      ? "今天也很努力呢，休息一下吧 ✨"
                                      : "今日还有 ${vm.todayUndoneCount} 个待办等待完成",
                                  style: TextStyle(
                                    color: (allTodayDone
                                        ? (isDarkTheme
                                              ? Colors.green[200]
                                              : Colors.green[800])
                                        : (isDarkTheme
                                              ? Colors.white.withValues(
                                                  alpha: 0.7,
                                                )
                                              : Colors.black.withValues(
                                                  alpha: 0.6,
                                                ))),
                                    fontSize: 12.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Icon(
                            Icons.arrow_forward_ios_rounded,
                            size: 14,
                            color: (allTodayDone ? Colors.green : Colors.grey)
                                .withValues(alpha: 0.5),
                          ),
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
                          "今日 · ${vm.todayDoneCount}/${todayItems.length} 已完成",
                      expanded: true,
                      onTap: () => setState(() {
                        _isTodayExpanded = false;
                        _isTodayManuallyExpanded = false;
                      }),
                    ),
                    _buildAnimatedSection(
                      expanded: _isTodayExpanded,
                      child: ReorderableListView.builder(
                        itemCount: todayItems.length,
                        itemBuilder: (context, index) {
                          final item = todayItems[index];
                          if (item.todo != null) {
                            return _buildTodoItemCard(
                              item.todo!,
                              isPast: false,
                              isFuture: false,
                              now: now,
                              key: _getTodoDismissKey('dismiss', item.todo!.id),
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
                              item.group!,
                              item.groupTodos!,
                            ),
                          );
                        },
                        padding: EdgeInsets.zero,
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        buildDefaultDragHandles: false,
                        onReorderItem: (oldIndex, newIndex) {
                          final List<int> todayIndices = [];
                          for (int i = 0; i < widget.todos.length; i++) {
                            final t = widget.todos[i];
                            if (_isHistoricalTodoAt(t, today) ||
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
                          final reordered = List<_SortedDisplayItem>.from(
                            todayItems,
                          );
                          final item = reordered.removeAt(oldIndex);
                          reordered.insert(newIndex, item);
                          final updatedList = List<TodoItem>.from(widget.todos);
                          final reorderedTodos = reordered
                              .where((e) => e.todo != null)
                              .map((e) => e.todo!)
                              .toList();
                          for (
                            int i = 0;
                            i < todayIndices.length &&
                                i < reorderedTodos.length;
                            i++
                          ) {
                            updatedList[todayIndices[i]] = reorderedTodos[i];
                          }
                          widget.onTodosChanged(updatedList);
                        },
                      ),
                    ),
                  ],
                )
              : const SizedBox.shrink(key: ValueKey('today_empty')),
        ),
      );
    }

    if (_isWholeListExpanded && futureItems.isNotEmpty) {
      sections.add(
        _buildGroupLabel(
          text: "将来 · ${vm.futureUndoneCount} 未完成",
          expanded: _isFutureExpanded,
          icon: Icons.calendar_month_rounded,
          onTap: () => setState(() => _isFutureExpanded = !_isFutureExpanded),
        ),
      );
      sections.add(
        _buildAnimatedSection(
          expanded: _isFutureExpanded,
          child: _isFutureExpanded
              ? Column(
                  children: futureItems
                      .map((item) {
                        final todo = item.todo;
                        if (todo != null) {
                          return _buildTodoItemCard(
                            todo,
                            isPast: false,
                            isFuture: true,
                            now: now,
                            key: _getTodoDismissKey('dismiss', todo.id),
                          );
                        }
                        return _buildGroupWidget(item.group!, item.groupTodos!);
                      })
                      .toList(growable: false),
                )
              : const SizedBox.shrink(),
        ),
      );
    }

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 500),
      transitionBuilder: _buildExpandTransition,
      child: !_isWholeListExpanded
          ? GestureDetector(
              key: const ValueKey('collapsed_card'),
              onTap: () => setState(() => _isWholeListExpanded = true),
              child: Container(
                margin: const EdgeInsets.symmetric(vertical: 8),
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 14,
                ),
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
                                  Colors.white.withValues(alpha: 0.04),
                                ]
                              : [
                                  Theme.of(context).colorScheme.primary
                                      .withValues(alpha: 0.06),
                                  Theme.of(context).colorScheme.primary
                                      .withValues(alpha: 0.01),
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
                              : Theme.of(context).colorScheme.primary
                                    .withValues(alpha: 0.08)),
                    width: 1,
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primary
                            .withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        Icons.checklist_rtl_rounded,
                        size: 20,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
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
                                  ? (isDarkTheme ? Colors.white : Colors.black)
                                  : (useDarkUI ? Colors.white : null),
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                              letterSpacing: 0.2,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            undoneCount == 0
                                ? "今天做的不错！点击展开回顾"
                                : "点击这里展开清单，继续加油吧 ✨",
                            style: TextStyle(
                              color: widget.isLight
                                  ? (isDarkTheme
                                        ? Colors.white.withValues(alpha: 0.6)
                                        : Colors.black.withValues(alpha: 0.55))
                                  : (useDarkUI ? Colors.white : Colors.black)
                                        .withValues(alpha: 0.5),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      Icons.unfold_more_rounded,
                      size: 18,
                      color: (useDarkUI ? Colors.white : Colors.grey)
                          .withValues(alpha: 0.4),
                    ),
                  ],
                ),
              ),
            )
          : Column(
              key: const ValueKey('expanded_list'),
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildTeamFilterTabs(), // 🚀 注入团队分类切换
                ...sections,
              ],
            ),
    );
  }

  Widget _buildGroupWidget(TodoGroup g, List<TodoItem> gTodos) {
    final bool urgentFirstFolders =
        _folderDisplayMode == _TodoFolderDisplayMode.urgentFirst;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: RepaintBoundary(
        child: TodoGroupWidget(
          group: g,
          groupTodos: gTodos,
          isLight: widget.isLight,
          onlyShowMostUrgentTodo: urgentFirstFolders,
          teamRoles: _teamRoles,
          recurrenceProgressBuilder: (todo) =>
              _buildRecurrenceProgress(todo, widget.clock()),
          onToggle: () {
            _invalidateTodoViewModel();
            setState(() {
              g.isExpanded = !g.isExpanded;
              g.markAsChanged();
            });
            widget.onGroupsChanged(widget.todoGroups);
          },
          onTodoToggle: (todo) {
            final bool wasDone = todo.isDone;
            _invalidateTodoViewModel();
            if (!todo.isDone) {
              PomodoroSyncService().sendStopSignal(todoUuid: todo.id);
            }
            todo.isDone = !todo.isDone;
            if (todo.isDone && todo.isSkipped) {
              todo.isSkipped = false;
              todo.isSkippedSyncPending = true;
            }
            todo.markAsChanged();
            if (todo.isDone && !wasDone) {
              TodoCompletionCelebrationService.playCompletionImpact();
              _checkAndTriggerTodayAllDoneCelebration(todo);
            }
            widget.onTodosChanged(widget.todos);
          },
          onTodoDropped: (todoId) {
            final idx = widget.todos.indexWhere((t) => t.id == todoId);
            if (idx != -1) {
              _invalidateTodoViewModel();
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
              _invalidateTodoViewModel();
              setState(() {
                widget.todos[idx].groupId = null;
                widget.todos[idx].version += 10;
                widget.todos[idx].updatedAt =
                    DateTime.now().millisecondsSinceEpoch;
              });
              widget.onTodosChanged(widget.todos);
              AppSnackBars.showSnackBar(
                context,
                const SnackBar(content: Text('自由了！已移出文件夹')),
              );
            }
          },
          onShowIndependentTodoStatus: _showIndependentTodoStatus,
          onDelete: () async {
            final idx = widget.todoGroups.indexWhere((x) => x.id == g.id);
            if (idx != -1) {
              _invalidateTodoViewModel();
              widget.todoGroups[idx].isDeleted = true;
              widget.todoGroups[idx].markAsChanged();
            }
            await StorageService.deleteTodoGroupGlobally(widget.username, g.id);
            widget.onGroupsChanged(widget.todoGroups);
            widget.onRefreshRequested();
          },
          onTodoTapWithContext: _editTodo,
          onTodoDelete: (todo) async {
            if (TodoRecurrenceDeleteService.isRecurring(todo)) {
              await _deleteRecurringTodoWithScope(todo);
              return;
            }
            _invalidateTodoViewModel();
            setState(() {
              PomodoroSyncService().sendStopSignal(todoUuid: todo.id);
              todo.isDeleted = true;
              todo.markAsChanged();
            });
            widget.onTodosChanged(List<TodoItem>.from(widget.todos));
            await StorageService.deleteTodoGlobally(widget.username, todo.id);
          },
        ),
      ),
    );
  }

  /// 🚀 Uni-Sync 4.0: 首页动态团队切换 Tab
  Widget _buildTeamFilterTabs() {
    final signature = _cachedVmSignature!;
    var teamMap = _cachedTeamFilterMap;
    if (teamMap == null || _cachedTeamFilterSignature != signature) {
      // Extract all associated teams from todos and folders on cache misses.
      teamMap = {};
      for (final todo in widget.todos) {
        if (todo.teamUuid != null && todo.teamName != null) {
          teamMap[todo.teamUuid!] = todo.teamName!;
        }
      }
      for (final group in widget.todoGroups) {
        if (group.teamUuid != null && group.teamName != null) {
          teamMap[group.teamUuid!] = group.teamName!;
        }
      }
      _cachedTeamFilterMap = teamMap;
      _cachedTeamFilterSignature = signature;
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
                  _invalidateTodoViewModel();
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
                      _invalidateTodoViewModel();
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
                  ),
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
                actionKey: widget.folderKey ?? _folderManagementButtonKey,
                actionTooltip: "管理文件夹",
                isLight: widget.isLight,
                onAction: () async {
                  await PageTransitions.pushFromRect(
                    context: context,
                    page: FolderManageScreen(
                      username: widget.username,
                      todoGroups: widget.todoGroups,
                      onGroupsChanged: widget.onGroupsChanged,
                      allTodos: widget.todos,
                      onTodosChanged: widget.onTodosChanged,
                      onManualTodoSaved: widget.onManualTodoSaved,
                    ),
                    sourceKey: widget.folderKey ?? _folderManagementButtonKey,
                    placeholderIcon: Icons.folder_copy_outlined,
                  );
                  _loadSettings();
                },
              ),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  key: widget.historyKey ?? _historicalTodosButtonKey,
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
                      await PageTransitions.pushFromRect(
                        context: context,
                        page: HistoricalTodosScreen(username: widget.username),
                        sourceKey:
                            widget.historyKey ?? _historicalTodosButtonKey,
                        placeholderIcon: Icons.history_rounded,
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

  void _showIndependentTodoStatus(TodoItem todo) async {
    // 🚀 不再使用全局阻塞 Dialog，改为弹窗内局部加载
    showAppDialog(
      context: context,
      builder: (ctx) => _IndependentStatusDialog(todo: todo),
    );
  }

  void _openOverdueTriage(List<TodoItem> overdueTodos) {
    showTodoOverdueTriageSheet(
      context: context,
      username: widget.username,
      overdueTodos: overdueTodos,
      allTodos: widget.todos,
      onTodosChanged: widget.onTodosChanged,
      onRefreshRequested: widget.onRefreshRequested,
    );
  }

  void _checkAndTriggerTodayAllDoneCelebration(TodoItem justCompletedTodo) {
    final vm = _cachedVm;
    if (vm == null || vm.todayItems.isEmpty) return;

    bool wasAllDoneBefore = true;
    bool isAllDoneNow = true;
    int totalTodayCount = 0;

    for (final item in vm.todayItems) {
      if (item.todo != null) {
        totalTodayCount++;
        final bool isCurrent = item.todo!.id == justCompletedTodo.id;
        final bool wasDone = isCurrent ? false : item.todo!.isDone;
        final bool isDone = isCurrent ? true : item.todo!.isDone;
        if (!wasDone) wasAllDoneBefore = false;
        if (!isDone) isAllDoneNow = false;
      } else if (item.groupTodos != null) {
        totalTodayCount += item.groupTodos!.length;
        for (final t in item.groupTodos!) {
          final bool isCurrent = t.id == justCompletedTodo.id;
          final bool wasDone = isCurrent ? false : t.isDone;
          final bool isDone = isCurrent ? true : t.isDone;
          if (!wasDone) wasAllDoneBefore = false;
          if (!isDone) isAllDoneNow = false;
        }
      } else {
        totalTodayCount++;
        if (!item.isDone) {
          wasAllDoneBefore = false;
          isAllDoneNow = false;
        }
      }
    }

    if (!wasAllDoneBefore && isAllDoneNow && totalTodayCount > 0) {
      TodoCompletionCelebrationService.playCelebrationImpact();
      showTodoAllDoneCelebration(context, completedTodayCount: totalTodayCount);
    }
  }
}
