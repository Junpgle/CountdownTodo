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

class _ShareTodoSectionState extends State<ShareTodoSection> {
  bool _isWholeListExpanded = true;
  bool _isPastTodosExpanded = false;
  bool _isTodayExpanded = true;
  bool _isTodayManuallyExpanded = false;
  bool _isFutureExpanded = true;

  @override
  Widget build(BuildContext context) {
    final bool isDarkTheme = Theme.of(context).brightness == Brightness.dark;
    final bool useDarkUI = isDarkTheme || widget.isLight;
    final colorScheme = Theme.of(context).colorScheme;

    final DateTime now = DateTime.now();
    final DateTime today = DateTime(now.year, now.month, now.day);

    // 分类
    final pastItems = <TodoItem>[];
    final todayItems = <TodoItem>[];
    final futureItems = <TodoItem>[];

    for (final t in widget.todos) {
      if (t.isDone) continue;
      if (t.dueDate != null) {
        final d = DateTime(t.dueDate!.year, t.dueDate!.month, t.dueDate!.day);
        if (d.isBefore(today)) {
          pastItems.add(t);
        } else if (d.isAfter(today)) {
          futureItems.add(t);
        } else {
          todayItems.add(t);
        }
      } else {
        todayItems.add(t);
      }
    }

    final int undoneCount = pastItems.length + todayItems.length + futureItems.length;

    if (undoneCount == 0 && widget.todos.isEmpty) {
      return const SizedBox.shrink();
    }

    // 标题栏
    final header = Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: _buildSectionHeader(context, "待办清单", Icons.check_circle_outline),
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
              onPressed: () => setState(() => _isWholeListExpanded = !_isWholeListExpanded),
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
          onTap: () => setState(() => _isPastTodosExpanded = !_isPastTodosExpanded),
        ),
      );
      sections.add(
        _buildAnimatedSection(
          expanded: _isPastTodosExpanded,
          child: Column(
            children: pastItems.map((t) => _buildTodoCard(context, t, isOverdue: true)).toList(),
          ),
        ),
      );
    }

    // 今日
    final bool allTodayDone = todayItems.isNotEmpty && todayItems.every((t) => t.isDone);
    final bool showTodayItems = _isTodayManuallyExpanded || (!allTodayDone && _isTodayExpanded);

    sections.add(
      AnimatedSwitcher(
        duration: const Duration(milliseconds: 400),
        transitionBuilder: (child, animation) {
          return FadeTransition(
            opacity: animation,
            child: SizeTransition(sizeFactor: animation, alignment: Alignment.topCenter, child: child),
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
                        ? (isDarkTheme ? Colors.grey[850]!.withValues(alpha: 0.95) : Colors.white.withValues(alpha: 0.95))
                        : (allTodayDone
                            ? (isDarkTheme ? Colors.green.withValues(alpha: 0.15) : Colors.green.withValues(alpha: 0.08))
                            : (isDarkTheme ? Colors.white.withValues(alpha: 0.08) : colorScheme.primary.withValues(alpha: 0.04))),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: allTodayDone
                          ? Colors.green.withValues(alpha: 0.4)
                          : (widget.isLight
                              ? (isDarkTheme ? Colors.white.withValues(alpha: 0.15) : Colors.black.withValues(alpha: 0.1))
                              : (isDarkTheme ? Colors.white.withValues(alpha: 0.22) : colorScheme.primary.withValues(alpha: 0.25))),
                      width: 1.5,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: widget.isLight ? 0.15 : 0.08),
                        blurRadius: 12,
                        offset: const Offset(0, 5),
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
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
                            allTodayDone ? Icons.celebration_rounded : Icons.today_rounded,
                            size: 20,
                            color: allTodayDone ? Colors.green : colorScheme.primary,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                allTodayDone ? "今日任务已完成 🎉" : "今日还有 ${todayItems.where((t) => !t.isDone).length} 个待办",
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                  color: widget.isLight
                                      ? (isDarkTheme ? Colors.white : Colors.black)
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
                                      ? (isDarkTheme ? Colors.white.withValues(alpha: 0.6) : Colors.black.withValues(alpha: 0.55))
                                      : (useDarkUI ? Colors.white : Colors.black).withValues(alpha: 0.5),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Icon(Icons.unfold_more_rounded,
                            size: 18, color: (useDarkUI ? Colors.white : Colors.grey).withValues(alpha: 0.4)),
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
                    ...todayItems.map((t) => _buildTodoCard(context, t)),
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
            children: futureItems.map((t) => _buildTodoCard(context, t, isFuture: true)).toList(),
          ),
        ),
      );
    }

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 500),
      transitionBuilder: (Widget child, Animation<double> animation) {
        return FadeTransition(
          opacity: animation,
          child: SizeTransition(sizeFactor: animation, alignment: Alignment.topCenter, child: child),
        );
      },
      child: !_isWholeListExpanded
          ? GestureDetector(
              key: const ValueKey('collapsed_card'),
              onTap: () => setState(() => _isWholeListExpanded = true),
              child: Container(
                margin: const EdgeInsets.symmetric(vertical: 8),
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                decoration: BoxDecoration(
                  color: widget.isLight
                      ? (isDarkTheme ? Colors.grey[850]!.withValues(alpha: 0.95) : Colors.white.withValues(alpha: 0.95))
                      : null,
                  gradient: widget.isLight
                      ? null
                      : LinearGradient(
                          colors: useDarkUI
                              ? [Colors.white.withValues(alpha: 0.12), Colors.white.withValues(alpha: 0.04)]
                              : [colorScheme.primary.withValues(alpha: 0.06), colorScheme.primary.withValues(alpha: 0.01)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: widget.isLight
                        ? (isDarkTheme ? Colors.white.withValues(alpha: 0.15) : Colors.black.withValues(alpha: 0.1))
                        : (useDarkUI ? Colors.white.withValues(alpha: 0.1) : colorScheme.primary.withValues(alpha: 0.08)),
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
                      child: Icon(Icons.checklist_rtl_rounded, size: 20, color: colorScheme.primary),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            undoneCount == 0 ? "全部任务已完成" : "目前还有 $undoneCount 个待办",
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
                            undoneCount == 0 ? "今天做的不错！点击展开回顾" : "点击这里展开清单，继续加油吧 ✨",
                            style: TextStyle(
                              color: widget.isLight
                                  ? (isDarkTheme ? Colors.white.withValues(alpha: 0.6) : Colors.black.withValues(alpha: 0.55))
                                  : (useDarkUI ? Colors.white : Colors.black).withValues(alpha: 0.5),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(Icons.unfold_more_rounded, size: 18, color: (useDarkUI ? Colors.white : Colors.grey).withValues(alpha: 0.4)),
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

  Widget _buildSectionHeader(BuildContext context, String title, IconData icon) {
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
              expanded ? Icons.keyboard_arrow_down_rounded : Icons.keyboard_arrow_right_rounded,
              size: 20,
              color: (color ?? Theme.of(context).colorScheme.onSurface).withValues(alpha: 0.5),
            ),
            const SizedBox(width: 8),
            Text(
              text,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: (color ?? Theme.of(context).colorScheme.onSurface).withValues(alpha: 0.8),
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAnimatedSection({required bool expanded, required Widget child}) {
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

  Widget _buildTodoCard(BuildContext context, TodoItem todo, {bool isOverdue = false, bool isFuture = false}) {
    final colorScheme = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final DateTime today = DateTime(now.year, now.month, now.day);

    // 进度
    final cDate = DateTime.fromMillisecondsSinceEpoch(
      todo.createdDate ?? todo.createdAt,
      isUtc: true,
    ).toLocal();
    final end = todo.dueDate ?? DateTime(cDate.year, cDate.month, cDate.day, 23, 59, 59);
    final totalMin = end.difference(cDate).inMinutes;
    double progress = 0.0;
    if (totalMin > 0 && now.isAfter(cDate)) {
      progress = (now.difference(cDate).inMinutes / totalMin).clamp(0.0, 1.0);
    }

    // 颜色
    final Color cardBg = todo.isDone
        ? colorScheme.surfaceContainerHighest.withValues(alpha: widget.isLight ? 0.25 : 0.08)
        : colorScheme.surface.withValues(
            alpha: _isPastDue(todo, today) ? (widget.isLight ? 0.9 : 0.45) : isFuture ? (widget.isLight ? 0.85 : 0.35) : (widget.isLight ? 0.97 : 0.75),
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
      final d = DateTime(todo.dueDate!.year, todo.dueDate!.month, todo.dueDate!.day);
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
                Icon(Icons.radio_button_unchecked, size: 18, color: Colors.grey.shade400),
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
                  style: TextStyle(fontSize: 11, color: badgeColor, fontWeight: FontWeight.w600),
                ),
              ),
              if (todo.collabType == 1 && todo.teamName != null) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
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
                        style: TextStyle(fontSize: 10, color: colorScheme.primary, fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
          if (!todo.isDone && progress > 0) ...[
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 4,
                backgroundColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
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
    final bool useDarkUI = isDarkTheme || isLight;

    // 过滤：只显示未完成且未过期的倒计时
    final activeCountdowns = countdowns.where((item) {
      return !item.isCompleted && item.targetDate.difference(today).inDays >= 0;
    }).toList()..sort((a, b) => a.targetDate.compareTo(b.targetDate));

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
                              : colorScheme.surfaceContainerHighest.withValues(alpha: 0.5))
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

              final textColor = useDarkUI ? Colors.white : colorScheme.onSurface;
              final subTextColor = useDarkUI ? Colors.white70 : colorScheme.onSurfaceVariant;
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
      '假期', '放假', '休假', '春节', '国庆', '五一', '端午', '中秋',
      '元旦', '清明', '新年', '圣诞', 'holiday', 'vacation', 'break',
    ];
    return keywords.any((kw) => lower.contains(kw));
  }

  Widget _buildSectionHeader(BuildContext context, String title, IconData icon) {
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
            style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold, letterSpacing: 0.5),
          ),
        ],
      ),
    );
  }
}
