import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models.dart';

/// 分享页只读待办组件（支持折叠，与手机端布局一致）
class ShareTodoSection extends StatefulWidget {
  final List<TodoItem> todos;
  final List<TodoGroup> todoGroups;
  final bool isLight;

  const ShareTodoSection({
    super.key,
    required this.todos,
    required this.todoGroups,
    required this.isLight,
  });

  @override
  State<ShareTodoSection> createState() => _ShareTodoSectionState();
}

class _ShareTodoDisplayItem {
  final TodoItem? todo;
  final TodoGroup? group;
  final List<TodoItem> groupTodos;
  final DateTime? date;
  final bool isDone;
  final double progress;

  const _ShareTodoDisplayItem({
    this.todo,
    this.group,
    this.groupTodos = const [],
    this.date,
    required this.isDone,
    this.progress = 0,
  });
}

class _ShareTodoSectionState extends State<ShareTodoSection> {
  bool _isWholeListExpanded = true;
  bool _isPastTodosExpanded = false;
  bool _isTodayExpanded = true;
  bool _isTodayManuallyExpanded = false;
  bool _isFutureExpanded = true;
  final Map<String, bool> _expandedFolders = {};

  @override
  Widget build(BuildContext context) {
    final bool isDarkTheme = Theme.of(context).brightness == Brightness.dark;
    final bool useDarkUI = isDarkTheme;
    final colorScheme = Theme.of(context).colorScheme;

    final DateTime now = DateTime.now();
    final DateTime today = DateTime(now.year, now.month, now.day);

    final displayItems = _buildSortedDisplayItems(now, today);
    final pastItems = displayItems
        .where((item) => _isBeforeDay(item.date, today))
        .toList();
    final todayItems = displayItems
        .where((item) => !_isBeforeDay(item.date, today) &&
            !_isAfterDay(item.date, today))
        .toList();
    final futureItems = displayItems
        .where((item) => _isAfterDay(item.date, today))
        .toList();

    final int undoneCount = widget.todos
        .where((todo) => !todo.isDeleted && !todo.isDone)
        .length;

    if (displayItems.isEmpty) return const SizedBox.shrink();

    // 标题栏
    final header = Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child:
              _buildSectionHeader(context, "待办清单", Icons.check_circle_outline),
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              visualDensity: VisualDensity.compact,
              icon: Icon(
                _isWholeListExpanded ? Icons.expand_less : Icons.expand_more,
                size: 20,
                color: useDarkUI ? Colors.white70 : Colors.grey,
              ),
              onPressed: () =>
                  setState(() => _isWholeListExpanded = !_isWholeListExpanded),
            ),
          ],
        ),
      ],
    );

    // 展开时的内容
    final List<Widget> sections = [];

    // 逾期
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
            children: pastItems
                .map((item) => _buildDisplayItem(context, item, today))
                .toList(),
          ),
        ),
      );
    }

    // 今日
    final bool allTodayDone =
        todayItems.isNotEmpty && todayItems.every((item) => item.isDone);
    final bool showTodayItems =
        _isTodayManuallyExpanded || (!allTodayDone && _isTodayExpanded);

    sections.add(
      AnimatedSwitcher(
        duration: const Duration(milliseconds: 400),
        transitionBuilder: (child, animation) {
          return FadeTransition(
            opacity: animation,
            child: SizeTransition(
                sizeFactor: animation,
                alignment: Alignment.topCenter,
                child: child),
          );
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
                                : colorScheme.primary.withValues(alpha: 0.04))),
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
                                  : colorScheme.primary
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
                                : colorScheme.primary.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            allTodayDone
                                ? Icons.celebration_rounded
                                : Icons.today_rounded,
                            size: 20,
                            color: allTodayDone
                                ? Colors.green
                                : colorScheme.primary,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                allTodayDone
                                    ? "今日任务已完成 🎉"
                                    : "今日还有 ${todayItems.where((item) => !item.isDone).length} 个待办",
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                  color: widget.isLight
                                      ? (isDarkTheme
                                          ? Colors.white
                                          : Colors.black)
                                      : (useDarkUI ? Colors.white : null),
                                  letterSpacing: 0.2,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                "点击展开查看详情",
                                style: TextStyle(
                                  fontSize: 12,
                                  color: widget.isLight
                                      ? (isDarkTheme
                                          ? Colors.white.withValues(alpha: 0.6)
                                          : Colors.black
                                              .withValues(alpha: 0.55))
                                      : (useDarkUI
                                              ? Colors.white
                                              : Colors.black)
                                          .withValues(alpha: 0.5),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Icon(Icons.unfold_more_rounded,
                            size: 18,
                            color: (useDarkUI ? Colors.white : Colors.grey)
                                .withValues(alpha: 0.4)),
                      ],
                    ),
                  ),
                ),
              )
            : Column(
                key: const ValueKey('expanded_list'),
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (todayItems.isNotEmpty) ...[
                    _buildGroupLabel(
                      text: "今日 · ${todayItems.length}",
                      expanded: true,
                      color: colorScheme.primary,
                      onTap: () {
                        setState(() {
                          _isTodayManuallyExpanded = false;
                          _isTodayExpanded = false;
                        });
                      },
                    ),
                    ...todayItems.map(
                        (item) => _buildDisplayItem(context, item, today)),
                  ],
                ],
              ),
      ),
    );

    // 未来
    if (futureItems.isNotEmpty) {
      sections.add(
        _buildGroupLabel(
          text: "未来 · ${futureItems.length}",
          expanded: _isFutureExpanded,
          color: colorScheme.secondary,
          onTap: () => setState(() => _isFutureExpanded = !_isFutureExpanded),
        ),
      );
      sections.add(
        _buildAnimatedSection(
          expanded: _isFutureExpanded,
          child: Column(
            children: futureItems
                .map((item) => _buildDisplayItem(context, item, today))
                .toList(),
          ),
        ),
      );
    }

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 500),
      transitionBuilder: (Widget child, Animation<double> animation) {
        return FadeTransition(
          opacity: animation,
          child: SizeTransition(
              sizeFactor: animation,
              alignment: Alignment.topCenter,
              child: child),
        );
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
                                  colorScheme.primary.withValues(alpha: 0.06),
                                  colorScheme.primary.withValues(alpha: 0.01)
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
                            : colorScheme.primary.withValues(alpha: 0.08)),
                    width: 1,
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: colorScheme.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(Icons.checklist_rtl_rounded,
                          size: 20, color: colorScheme.primary),
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
              children: [header, ...sections],
            ),
    );
  }

  Widget _buildSectionHeader(
      BuildContext context, String title, IconData icon) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: colorScheme.primary.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 20, color: colorScheme.primary),
          ),
          const SizedBox(width: 10),
          Text(
            title,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildGroupLabel({
    required String text,
    required bool expanded,
    required VoidCallback onTap,
    Color? color,
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

  Widget _buildAnimatedSection(
      {required bool expanded, required Widget child}) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      transitionBuilder: (Widget child, Animation<double> animation) {
        return FadeTransition(
          opacity: animation,
          child: SizeTransition(
            sizeFactor: animation,
            alignment: Alignment.topCenter,
            child: child,
          ),
        );
      },
      child: expanded
          ? Container(key: const ValueKey('expanded_content'), child: child)
          : const SizedBox.shrink(key: ValueKey('collapsed_empty')),
    );
  }

  List<_ShareTodoDisplayItem> _buildSortedDisplayItems(
    DateTime now,
    DateTime today,
  ) {
    final groupById = <String, TodoGroup>{
      for (final group in widget.todoGroups)
        if (!group.isDeleted) group.id: group,
    };
    final todosByGroup = <String, List<TodoItem>>{};
    final standaloneTodos = <TodoItem>[];
    final visibleTodos = widget.todos
        .where((todo) => !todo.isDeleted && !_isHistoricalTodo(todo, today))
        .toList();

    for (final todo in visibleTodos) {
      final groupId = todo.groupId;
      if (groupId != null &&
          groupId.isNotEmpty &&
          groupById.containsKey(groupId)) {
        todosByGroup.putIfAbsent(groupId, () => []).add(todo);
      } else {
        standaloneTodos.add(todo);
      }
    }

    final items = <_ShareTodoDisplayItem>[];
    for (final group in groupById.values) {
      final groupTodos = todosByGroup[group.id];
      if (groupTodos == null || groupTodos.isEmpty) continue;
      _sortFolderTodos(groupTodos);

      DateTime? groupDate;
      for (final todo in groupTodos) {
        if (todo.isDone || todo.dueDate == null) continue;
        if (groupDate == null || todo.dueDate!.isBefore(groupDate)) {
          groupDate = todo.dueDate;
        }
      }
      if (groupDate == null) {
        for (final todo in groupTodos) {
          if (todo.dueDate != null &&
              (groupDate == null || todo.dueDate!.isBefore(groupDate))) {
            groupDate = todo.dueDate;
          }
        }
      }

      var groupProgress = 0.0;
      for (final todo in groupTodos) {
        if (!todo.isDone) {
          final todoProgress = _todoProgress(todo, now);
          if (todoProgress > groupProgress) groupProgress = todoProgress;
        }
      }

      items.add(_ShareTodoDisplayItem(
        group: group,
        groupTodos: groupTodos,
        date: groupDate,
        isDone: groupTodos.every((todo) => todo.isDone),
        progress: groupProgress,
      ));
    }

    for (final todo in standaloneTodos) {
      items.add(_ShareTodoDisplayItem(
        todo: todo,
        date: todo.dueDate,
        isDone: todo.isDone,
        progress: _todoProgress(todo, now),
      ));
    }

    // Keep the same urgency order as TodoSectionWidget: unfinished first,
    // then progress descending, then the nearest deadline.
    int compareItems(_ShareTodoDisplayItem a, _ShareTodoDisplayItem b) {
      if (a.isDone != b.isDone) return a.isDone ? 1 : -1;
      final progressOrder = b.progress.compareTo(a.progress);
      if (progressOrder != 0) return progressOrder;
      if (a.date != null && b.date != null) return a.date!.compareTo(b.date!);
      if (a.date != null) return -1;
      if (b.date != null) return 1;
      return 0;
    }

    items.sort(compareItems);
    return items;
  }

  void _sortFolderTodos(List<TodoItem> todos) {
    todos.sort((a, b) {
      if (a.isDone != b.isDone) return a.isDone ? 1 : -1;
      if (a.dueDate == null && b.dueDate == null) return 0;
      if (a.dueDate == null) return 1;
      if (b.dueDate == null) return -1;
      return a.dueDate!.compareTo(b.dueDate!);
    });
  }

  double _todoProgress(TodoItem todo, DateTime now) {
    final createdAt = DateTime.fromMillisecondsSinceEpoch(
      todo.createdDate ?? todo.createdAt,
      isUtc: true,
    ).toLocal();
    final end = todo.dueDate ??
        DateTime(createdAt.year, createdAt.month, createdAt.day, 23, 59, 59);
    final totalMinutes = end.difference(createdAt).inMinutes;
    if (totalMinutes <= 0 || !now.isAfter(createdAt)) return 0;
    return (now.difference(createdAt).inMinutes / totalMinutes)
        .clamp(0.0, 1.0)
        .toDouble();
  }

  bool _isHistoricalTodo(TodoItem todo, DateTime today) {
    if (!todo.isDone) return false;
    if (todo.dueDate != null) return _isBeforeDay(todo.dueDate, today);
    final createdAt = DateTime.fromMillisecondsSinceEpoch(
      todo.createdDate ?? todo.createdAt,
      isUtc: true,
    ).toLocal();
    return _isBeforeDay(createdAt, today);
  }

  bool _isBeforeDay(DateTime? date, DateTime today) {
    if (date == null) return false;
    return DateTime(date.year, date.month, date.day).isBefore(today);
  }

  bool _isAfterDay(DateTime? date, DateTime today) {
    if (date == null) return false;
    return DateTime(date.year, date.month, date.day).isAfter(today);
  }

  Widget _buildDisplayItem(
    BuildContext context,
    _ShareTodoDisplayItem item,
    DateTime today,
  ) {
    final todo = item.todo;
    if (todo != null) {
      return _buildTodoCard(
        context,
        todo,
        isOverdue: _isBeforeDay(todo.dueDate, today),
        isFuture: _isAfterDay(todo.dueDate, today),
      );
    }
    return _buildFolderCard(context, item, today);
  }

  Widget _buildFolderCard(
    BuildContext context,
    _ShareTodoDisplayItem item,
    DateTime today,
  ) {
    final group = item.group!;
    final colorScheme = Theme.of(context).colorScheme;
    final expanded = _expandedFolders[group.id] ?? group.isExpanded;
    final doneCount = item.groupTodos.where((todo) => todo.isDone).length;
    final totalCount = item.groupTodos.length;
    final nearestDeadline = item.groupTodos
        .where((todo) => !todo.isDone && todo.dueDate != null)
        .map((todo) => todo.dueDate!)
        .fold<DateTime?>(
          null,
          (nearest, date) =>
              nearest == null || date.isBefore(nearest) ? date : nearest,
        );

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.65),
        ),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: () => setState(() {
              _expandedFolders[group.id] = !expanded;
            }),
            borderRadius: BorderRadius.circular(18),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
              child: Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color:
                          colorScheme.primaryContainer.withValues(alpha: 0.7),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      expanded
                          ? Icons.folder_open_rounded
                          : Icons.folder_rounded,
                      size: 19,
                      color: colorScheme.primary,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          group.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          item.isDone
                              ? '全部任务已完成 ✨'
                              : '$doneCount/$totalCount 已完成',
                          style: TextStyle(
                            fontSize: 11,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (nearestDeadline != null && !expanded) ...[
                    const SizedBox(width: 8),
                    Text(
                      DateFormat('MM/dd').format(nearestDeadline),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: colorScheme.secondary,
                      ),
                    ),
                  ],
                  const SizedBox(width: 6),
                  Icon(
                    expanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    size: 20,
                    color: colorScheme.onSurfaceVariant.withValues(alpha: 0.65),
                  ),
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 240),
            curve: Curves.easeInOut,
            alignment: Alignment.topCenter,
            child: expanded
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                    child: Column(
                      children: item.groupTodos.map((todo) {
                        return _buildTodoCard(
                          context,
                          todo,
                          isOverdue: _isBeforeDay(todo.dueDate, today),
                          isFuture: _isAfterDay(todo.dueDate, today),
                        );
                      }).toList(),
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  Widget _buildTodoCard(BuildContext context, TodoItem todo,
      {bool isOverdue = false, bool isFuture = false}) {
    final colorScheme = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final DateTime today = DateTime(now.year, now.month, now.day);

    // 进度
    final cDate = DateTime.fromMillisecondsSinceEpoch(
      todo.createdDate ?? todo.createdAt,
      isUtc: true,
    ).toLocal();
    final end = todo.dueDate ??
        DateTime(cDate.year, cDate.month, cDate.day, 23, 59, 59);
    final totalMin = end.difference(cDate).inMinutes;
    double progress = 0.0;
    if (totalMin > 0 && now.isAfter(cDate)) {
      progress = (now.difference(cDate).inMinutes / totalMin).clamp(0.0, 1.0);
    }

    // 颜色
    final Color cardBg = todo.isDone
        ? colorScheme.surfaceContainerHighest
            .withValues(alpha: widget.isLight ? 0.25 : 0.08)
        : colorScheme.surface.withValues(
            alpha: _isPastDue(todo, today)
                ? (widget.isLight ? 0.9 : 0.45)
                : isFuture
                    ? (widget.isLight ? 0.85 : 0.35)
                    : (widget.isLight ? 0.97 : 0.75),
          );

    final Color titleColor = todo.isDone
        ? colorScheme.onSurface.withValues(alpha: 0.35)
        : (isOverdue || isFuture
            ? colorScheme.onSurface.withValues(alpha: 0.65)
            : colorScheme.onSurface);

    // 时间标签
    String badge = "";
    Color badgeColor = colorScheme.primary;
    Color badgeBg = colorScheme.primaryContainer.withValues(alpha: 0.6);

    if (todo.dueDate != null) {
      final d =
          DateTime(todo.dueDate!.year, todo.dueDate!.month, todo.dueDate!.day);
      final todayDate = DateTime(now.year, now.month, now.day);
      if (isOverdue) {
        badge = "已逾期";
        badgeColor = Colors.redAccent.shade200;
        badgeBg = Colors.redAccent.withValues(alpha: 0.12);
      } else if (isFuture) {
        final days = d.difference(todayDate).inDays;
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

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: widget.isLight ? 0.15 : 0.08),
            blurRadius: 12,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  todo.title,
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w500,
                    color: titleColor,
                  ),
                ),
              ),
              if (todo.isDone)
                Icon(Icons.check_circle_rounded, size: 18, color: Colors.green)
              else if (isOverdue)
                Icon(Icons.warning_rounded, size: 18, color: Colors.redAccent)
              else
                Icon(Icons.radio_button_unchecked,
                    size: 18, color: Colors.grey.shade400),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: badgeBg,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  badge,
                  style: TextStyle(
                      fontSize: 11,
                      color: badgeColor,
                      fontWeight: FontWeight.w600),
                ),
              ),
              if (todo.collabType == 1 && todo.teamName != null) ...[
                const SizedBox(width: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.group, size: 10, color: colorScheme.primary),
                      const SizedBox(width: 3),
                      Text(
                        todo.teamName!,
                        style: TextStyle(
                            fontSize: 10,
                            color: colorScheme.primary,
                            fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
          if (_buildTimeLabel(todo) case final timeLabel?) ...[
            const SizedBox(height: 7),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  todo.isDateOnly
                      ? Icons.calendar_today_rounded
                      : Icons.schedule_rounded,
                  size: 15,
                  color: colorScheme.onSurfaceVariant.withValues(alpha: 0.85),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    timeLabel,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ],
          if (!todo.isDone && progress > 0) ...[
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 4,
                backgroundColor:
                    colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                color: isOverdue ? Colors.redAccent : colorScheme.primary,
              ),
            ),
          ],
        ],
      ),
    );
  }

  bool _isPastDue(TodoItem t, DateTime today) {
    if (t.dueDate != null) {
      final d = DateTime(t.dueDate!.year, t.dueDate!.month, t.dueDate!.day);
      return d.isBefore(today);
    }
    return false;
  }

  String? _buildTimeLabel(TodoItem todo) {
    final start = todo.createdDate == null ? null : todo.effectiveStartTime;
    final end = todo.dueDate?.toLocal();

    if (start == null && end == null) return null;
    if (todo.isDateOnly) {
      final date = end ?? start;
      return date == null ? null : '${DateFormat('MM/dd').format(date)} 内完成';
    }
    if (start != null && end != null && todo.hasLegacyTimeRange) {
      return '${DateFormat('MM/dd HH:mm').format(start)} → '
          '${DateFormat('MM/dd HH:mm').format(end)}';
    }
    if (end != null) {
      return '${DateFormat('MM/dd HH:mm').format(end)} 前完成';
    }
    if (start != null) {
      return '开始 ${DateFormat('MM/dd HH:mm').format(start)}';
    }
    return null;
  }
}

/// 分享页只读日程组件。
///
/// 日程与待办是两种不同的数据类型：日程使用固定的起止时间，不能用
/// 待办的完成勾选或截止时间来代替。因此这里单独渲染 `fixed_schedules`。
class ShareScheduleSection extends StatelessWidget {
  final List<FixedScheduleItem> schedules;
  final bool isLight;

  const ShareScheduleSection({
    super.key,
    required this.schedules,
    required this.isLight,
  });

  @override
  Widget build(BuildContext context) {
    if (schedules.isEmpty) return const SizedBox.shrink();

    final colorScheme = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final sorted = schedules.where((item) => !item.isDeleted).toList()
      ..sort(_compareSchedules);
    final endedSchedules = sorted
        .where((item) => item.phaseAt(now) == FixedSchedulePhase.ended)
        .toList();
    final notEndedSchedules = sorted
        .where((item) => item.phaseAt(now) != FixedSchedulePhase.ended)
        .toList();

    if (sorted.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildHeader(context, colorScheme),
        const SizedBox(height: 14),
        ...notEndedSchedules.map((item) => _buildScheduleCard(context, item)),
        if (endedSchedules.isNotEmpty) ...[
          _buildEndedGroupHeader(context, colorScheme, endedSchedules.length),
          ...endedSchedules.map((item) => _buildScheduleCard(context, item)),
        ],
      ],
    );
  }

  Widget _buildHeader(BuildContext context, ColorScheme colorScheme) {
    return Row(
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: colorScheme.secondary.withValues(alpha: 0.13),
            borderRadius: BorderRadius.circular(13),
          ),
          child: Icon(Icons.event_available_rounded,
              size: 20, color: colorScheme.secondary),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '日程',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 2),
              Text(
                '固定安排与活动时间',
                style: TextStyle(
                  fontSize: 12,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        _buildCountChip(colorScheme),
      ],
    );
  }

  Widget _buildEndedGroupHeader(
    BuildContext context,
    ColorScheme colorScheme,
    int count,
  ) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 10, left: 4, right: 4),
      child: Row(
        children: [
          Icon(Icons.history_rounded,
              size: 17, color: colorScheme.onSurfaceVariant),
          const SizedBox(width: 7),
          Text(
            '已结束',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                ),
          ),
          const Spacer(),
          Text(
            '$count 项',
            style: TextStyle(
              fontSize: 12,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCountChip(ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: colorScheme.secondaryContainer.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        '${schedules.where((item) => !item.isDeleted).length} 项',
        style: TextStyle(
          color: colorScheme.onSecondaryContainer,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _buildScheduleCard(BuildContext context, FixedScheduleItem item) {
    final colorScheme = Theme.of(context).colorScheme;
    final phase = item.phaseAt(DateTime.now());
    final phaseColor = _phaseColor(colorScheme, phase);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest
            .withValues(alpha: isLight ? 0.62 : 0.42),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: phaseColor.withValues(alpha: 0.24)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: phaseColor.withValues(alpha: 0.13),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.event_rounded, size: 19, color: phaseColor),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 6),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.schedule_rounded,
                        size: 15, color: colorScheme.onSurfaceVariant),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Text(
                        _formatScheduleTime(item),
                        style: TextStyle(
                          fontSize: 12,
                          color: colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
                if (item.location?.isNotEmpty == true) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(Icons.location_on_outlined,
                          size: 15, color: colorScheme.onSurfaceVariant),
                      const SizedBox(width: 5),
                      Expanded(
                        child: Text(
                          item.location!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            decoration: BoxDecoration(
              color: phaseColor.withValues(alpha: 0.13),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              _phaseLabel(phase),
              style: TextStyle(
                fontSize: 11,
                color: phaseColor,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  int _compareSchedules(FixedScheduleItem a, FixedScheduleItem b) {
    final aStart = a.startTime ?? _dateStart(a.date);
    final bStart = b.startTime ?? _dateStart(b.date);
    return aStart.compareTo(bStart);
  }

  int _dateStart(String value) {
    final date = DateTime.tryParse(value)?.toLocal();
    return date?.millisecondsSinceEpoch ?? 0;
  }

  String _formatScheduleTime(FixedScheduleItem item) {
    final start = item.startTime == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(item.startTime!, isUtc: true)
            .toLocal();
    final end = item.endTime == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(item.endTime!, isUtc: true)
            .toLocal();
    final date = DateTime.tryParse(item.date)?.toLocal();

    if (start == null && end == null) {
      return date == null
          ? '时间待定'
          : '${DateFormat('MM/dd').format(date)} · 时间待定';
    }
    if (start != null && end != null) {
      final sameDay = start.year == end.year &&
          start.month == end.month &&
          start.day == end.day;
      return sameDay
          ? '${DateFormat('MM/dd').format(start)} '
              '${DateFormat('HH:mm').format(start)} → '
              '${DateFormat('HH:mm').format(end)}'
          : '${DateFormat('MM/dd HH:mm').format(start)} → '
              '${DateFormat('MM/dd HH:mm').format(end)}';
    }
    if (start != null) {
      return '${DateFormat('MM/dd HH:mm').format(start)} · 结束待定';
    }
    return '${DateFormat('MM/dd HH:mm').format(end!)} · 开始待定';
  }

  Color _phaseColor(ColorScheme colorScheme, FixedSchedulePhase phase) {
    return switch (phase) {
      FixedSchedulePhase.cancelled => colorScheme.error,
      FixedSchedulePhase.ended => colorScheme.onSurfaceVariant,
      FixedSchedulePhase.ongoing => colorScheme.tertiary,
      FixedSchedulePhase.timeTbd => colorScheme.secondary,
      FixedSchedulePhase.upcoming => colorScheme.primary,
    };
  }

  String _phaseLabel(FixedSchedulePhase phase) {
    return switch (phase) {
      FixedSchedulePhase.cancelled => '已取消',
      FixedSchedulePhase.ended => '已结束',
      FixedSchedulePhase.ongoing => '进行中',
      FixedSchedulePhase.timeTbd => '待定',
      FixedSchedulePhase.upcoming => '即将开始',
    };
  }
}

/// 分享页只读倒计时组件
class ShareCountdownSection extends StatelessWidget {
  final List<CountdownItem> countdowns;
  final bool isLight;

  const ShareCountdownSection({
    super.key,
    required this.countdowns,
    required this.isLight,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final bool isDarkTheme = Theme.of(context).brightness == Brightness.dark;
    final bool useDarkUI = isDarkTheme;

    // 过滤：只显示未完成且未过期的倒计时
    final activeCountdowns = countdowns.where((item) {
      return !item.isCompleted && item.targetDate.difference(today).inDays >= 0;
    }).toList()
      ..sort((a, b) => a.targetDate.compareTo(b.targetDate));

    if (activeCountdowns.isEmpty) return const SizedBox.shrink();

    // 提取团队列表
    final teams = <String>{};
    for (final c in activeCountdowns) {
      if (c.teamUuid != null) teams.add(c.teamUuid!);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(context, "重要日", Icons.timer),
        if (teams.isNotEmpty) ...[
          const SizedBox(height: 8),
          // 团队筛选标签（只读，不显示）
        ],
        const SizedBox(height: 8),
        SizedBox(
          height: 130,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.only(right: 12),
            itemCount: activeCountdowns.length,
            itemBuilder: (context, index) {
              final item = activeCountdowns[index];
              final diff = item.targetDate.difference(today).inDays;
              final bool isUrgent = diff <= 3;
              final bool isHoliday = _isHolidayKeyword(item.title);

              // 颜色
              final Color bgColor = useDarkUI
                  ? (isUrgent && isHoliday
                      ? Colors.greenAccent.withValues(alpha: 0.18)
                      : isUrgent
                          ? Colors.redAccent.withValues(alpha: 0.25)
                          : isLight
                              ? Colors.white.withValues(alpha: 0.1)
                              : colorScheme.surfaceContainerHighest
                                  .withValues(alpha: 0.5))
                  : (isUrgent && isHoliday
                      ? Colors.green.shade50
                      : isUrgent
                          ? Colors.red.shade50
                          : colorScheme.surface);

              final borderColor = useDarkUI
                  ? (isUrgent && isHoliday
                      ? Colors.greenAccent.withValues(alpha: 0.5)
                      : isUrgent
                          ? Colors.redAccent.withValues(alpha: 0.5)
                          : Colors.white.withValues(alpha: 0.15))
                  : (isUrgent && isHoliday
                      ? Colors.green.withValues(alpha: 0.3)
                      : isUrgent
                          ? Colors.redAccent.withValues(alpha: 0.3)
                          : Colors.black.withValues(alpha: 0.05));

              final textColor =
                  useDarkUI ? Colors.white : colorScheme.onSurface;
              final subTextColor =
                  useDarkUI ? Colors.white70 : colorScheme.onSurfaceVariant;
              final accentColor = useDarkUI
                  ? (isUrgent && isHoliday
                      ? Colors.greenAccent.shade100
                      : isUrgent
                          ? Colors.redAccent.shade100
                          : Colors.white)
                  : (isUrgent && isHoliday
                      ? Colors.green
                      : isUrgent
                          ? Colors.redAccent
                          : colorScheme.primary);

              return Container(
                width: 130,
                margin: const EdgeInsets.only(right: 12, bottom: 8),
                decoration: BoxDecoration(
                  color: bgColor,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: borderColor),
                  boxShadow: useDarkUI
                      ? []
                      : [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.04),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          )
                        ],
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 标题行
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              item.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: textColor,
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                                height: 1.2,
                              ),
                            ),
                          ),
                        ],
                      ),
                      // 团队信息
                      if (item.teamUuid != null) ...[
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Icon(Icons.groups_rounded,
                                size: 10,
                                color: accentColor.withValues(alpha: 0.6)),
                            const SizedBox(width: 3),
                            Expanded(
                              child: Text(
                                "${item.teamName ?? '团队'} · ${item.creatorName ?? '成员'}",
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 8,
                                  color: subTextColor.withValues(alpha: 0.8),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ] else ...[
                        const SizedBox(height: 12),
                      ],
                      const Spacer(),
                      // 天数
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            "$diff",
                            style: TextStyle(
                              fontSize: 28,
                              height: 1.0,
                              fontWeight: FontWeight.bold,
                              color: accentColor,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Padding(
                            padding: const EdgeInsets.only(bottom: 4.0),
                            child: Text(
                              "天",
                              style: TextStyle(
                                fontSize: 11,
                                color: subTextColor,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      // 目标日
                      Text(
                        "目标日: ${DateFormat('yyyy-MM-dd').format(item.targetDate)}",
                        style: TextStyle(
                          fontSize: 9,
                          color: subTextColor,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  bool _isHolidayKeyword(String title) {
    final lower = title.toLowerCase();
    const keywords = [
      '假期',
      '放假',
      '休假',
      '春节',
      '国庆',
      '五一',
      '端午',
      '中秋',
      '元旦',
      '清明',
      '新年',
      '圣诞',
      'holiday',
      'vacation',
      'break',
    ];
    return keywords.any((kw) => lower.contains(kw));
  }

  Widget _buildSectionHeader(
      BuildContext context, String title, IconData icon) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: colorScheme.primary.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 20, color: colorScheme.primary),
          ),
          const SizedBox(width: 10),
          Text(
            title,
            style: Theme.of(context)
                .textTheme
                .titleLarge
                ?.copyWith(fontWeight: FontWeight.bold, letterSpacing: 0.5),
          ),
        ],
      ),
    );
  }
}
