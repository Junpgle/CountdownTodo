import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models.dart';
import '../models/plan_availability.dart';
import '../services/todo_overdue_triage_service.dart';
import '../utils/app_dialogs.dart';
import 'optional_liquid_glass_surface.dart';

class TodoOverdueTriageSheet extends StatefulWidget {
  final String username;
  final List<TodoItem> initialOverdueTodos;
  final List<TodoItem> allTodos;
  final Function(List<TodoItem>) onTodosChanged;
  final VoidCallback onRefreshRequested;
  final TodoOverdueTriageService service;

  const TodoOverdueTriageSheet({
    super.key,
    required this.username,
    required this.initialOverdueTodos,
    required this.allTodos,
    required this.onTodosChanged,
    required this.onRefreshRequested,
    this.service = const TodoOverdueTriageService(),
  });

  @override
  State<TodoOverdueTriageSheet> createState() => _TodoOverdueTriageSheetState();
}

class _TodoOverdueTriageSheetState extends State<TodoOverdueTriageSheet> {
  late List<TodoItem> _overdueTodos;
  late Set<String> _selectedIds;
  bool _isProcessing = false;

  // 记录正在查找可用时段的 todo ID，以及查找到的候选时段
  final Map<String, List<PlanTimeSlot>> _foundSlots = {};
  final Set<String> _searchingSlotIds = {};

  @override
  void initState() {
    super.initState();
    _overdueTodos = List.from(widget.initialOverdueTodos);
    _selectedIds = _overdueTodos.map((t) => t.id).toSet();
  }

  void _toggleSelectAll() {
    setState(() {
      if (_selectedIds.length == _overdueTodos.length) {
        _selectedIds.clear();
      } else {
        _selectedIds = _overdueTodos.map((t) => t.id).toSet();
      }
    });
  }

  void _toggleItem(String id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
      } else {
        _selectedIds.add(id);
      }
    });
  }

  Future<void> _handleBatchReschedule(OverdueRescheduleTarget target) async {
    final toProcess = _overdueTodos
        .where((item) => _selectedIds.contains(item.id))
        .toList();
    if (toProcess.isEmpty) return;

    setState(() => _isProcessing = true);
    try {
      final result = await widget.service.applyBatchReschedule(
        username: widget.username,
        todosToReschedule: toProcess,
        target: target,
        allTodos: widget.allTodos,
      );

      if (!mounted) return;

      widget.onTodosChanged(result.updatedTodos);
      widget.onRefreshRequested();

      final label = switch (target) {
        OverdueRescheduleTarget.today => '已顺延至今天',
        OverdueRescheduleTarget.tomorrow => '已顺延至明天',
        OverdueRescheduleTarget.clear => '已清除截止时间',
      };

      Navigator.of(context).pop();

      AppSnackBars.showSnackBar(
        context,
        SnackBar(
          content: Text('${result.modifiedCount} 项待办$label'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isProcessing = false);
      AppSnackBars.showSnackBar(context, SnackBar(content: Text('处理失败: $e')));
    }
  }

  Future<void> _findSlotsForTodo(TodoItem todo) async {
    setState(() => _searchingSlotIds.add(todo.id));
    try {
      final slots = await widget.service.findSmartSlots(
        username: widget.username,
        todo: todo,
      );
      if (!mounted) return;
      setState(() {
        _searchingSlotIds.remove(todo.id);
        _foundSlots[todo.id] = slots;
      });
      if (slots.isEmpty) {
        AppSnackBars.showSnackBar(
          context,
          const SnackBar(
            content: Text('今天和明天暂未找到足够连续的空闲时段，可手动到规划中心调整'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _searchingSlotIds.remove(todo.id));
      AppSnackBars.showSnackBar(context, SnackBar(content: Text('查找时段失败: $e')));
    }
  }

  Future<void> _applySlotSchedule(TodoItem todo, PlanTimeSlot slot) async {
    setState(() => _isProcessing = true);
    try {
      await widget.service.schedulePlanBlock(
        username: widget.username,
        todo: todo,
        slot: slot,
        allTodos: widget.allTodos,
      );

      if (!mounted) return;

      widget.onTodosChanged(widget.allTodos);
      widget.onRefreshRequested();

      setState(() {
        _isProcessing = false;
        _overdueTodos.removeWhere((t) => t.id == todo.id);
        _selectedIds.remove(todo.id);
        _foundSlots.remove(todo.id);
      });

      AppSnackBars.showSnackBar(
        context,
        SnackBar(
          content: Text(
            '已为 "${todo.title}" 安排规划：${DateFormat('HH:mm').format(slot.start)}–${DateFormat('HH:mm').format(slot.end)}',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );

      if (_overdueTodos.isEmpty) {
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isProcessing = false);
      AppSnackBars.showSnackBar(context, SnackBar(content: Text('安排规划失败: $e')));
    }
  }

  String _formatOverdueTime(DateTime due) {
    final now = widget.service.clock();
    final today = DateTime(now.year, now.month, now.day);
    final dueDate = DateTime(due.year, due.month, due.day);
    final daysDiff = today.difference(dueDate).inDays;

    final timeStr = DateFormat('HH:mm').format(due);
    if (daysDiff == 0) {
      return '今天 $timeStr 已过期';
    } else if (daysDiff == 1) {
      return '昨天 $timeStr 逾期';
    } else if (daysDiff == 2) {
      return '前天 $timeStr 逾期';
    } else {
      return '$daysDiff 天前逾期 (${DateFormat('MM-dd').format(due)})';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    final isAllSelected =
        _selectedIds.length == _overdueTodos.length && _overdueTodos.isNotEmpty;

    final screenHeight = MediaQuery.sizeOf(context).height;
    final maxDialogHeight = math.min(screenHeight * 0.78, 560.0);

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 520, maxHeight: maxDialogHeight),
        child: OptionalLiquidGlassCard(
          borderRadius: 24,
          tint: colorScheme.primary.withValues(alpha: isDark ? 0.16 : 0.08),
          fallbackDecoration: BoxDecoration(
            color:
                (isDark
                        ? colorScheme.surfaceContainerHighest
                        : colorScheme.surface)
                    .withValues(alpha: 0.92),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.12)
                  : colorScheme.outline.withValues(alpha: 0.18),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.2),
                blurRadius: 28,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── 顶部拖拽指示条与标题 ──
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.redAccent.withValues(alpha: 0.12),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.history_toggle_off_rounded,
                          size: 20,
                          color: isDark
                              ? Colors.redAccent.shade100
                              : Colors.redAccent.shade700,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              '逾期待办整理',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              '可一键批量顺延，或利用空闲时间块智能排期',
                              style: TextStyle(
                                fontSize: 12,
                                color: colorScheme.onSurface.withValues(
                                  alpha: 0.6,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () => Navigator.of(context).pop(),
                        tooltip: '关闭',
                      ),
                    ],
                  ),
                ),

                const Divider(height: 1),

                // ── 全选与统计栏 ──
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: Row(
                    children: [
                      InkWell(
                        onTap: _toggleSelectAll,
                        borderRadius: BorderRadius.circular(8),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 4,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Checkbox(
                                value: isAllSelected,
                                tristate:
                                    _selectedIds.isNotEmpty &&
                                    _selectedIds.length < _overdueTodos.length,
                                onChanged: (_) => _toggleSelectAll(),
                                materialTapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap,
                                visualDensity: VisualDensity.compact,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                isAllSelected ? '取消全选' : '全选',
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const Spacer(),
                      Text(
                        '已选 ${_selectedIds.length} / ${_overdueTodos.length} 项',
                        style: TextStyle(
                          fontSize: 12,
                          color: colorScheme.onSurface.withValues(alpha: 0.6),
                        ),
                      ),
                    ],
                  ),
                ),

                // ── 任务列表 ──
                Flexible(
                  child: _overdueTodos.isEmpty
                      ? const Padding(
                          padding: EdgeInsets.all(32.0),
                          child: Center(child: Text('🎉 当前没有逾期待办')),
                        )
                      : ListView.separated(
                          shrinkWrap: true,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 4,
                          ),
                          itemCount: _overdueTodos.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 8),
                          itemBuilder: (context, index) {
                            final todo = _overdueTodos[index];
                            final isSelected = _selectedIds.contains(todo.id);
                            final slots = _foundSlots[todo.id];
                            final isSearching = _searchingSlotIds.contains(
                              todo.id,
                            );

                            return OptionalLiquidGlassCard(
                              key: ValueKey('overdue_todo_${todo.id}'),
                              borderRadius: 14,
                              fallbackDecoration: BoxDecoration(
                                color: colorScheme.surfaceContainerLow,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: isSelected
                                      ? colorScheme.primary.withValues(
                                          alpha: 0.3,
                                        )
                                      : colorScheme.outlineVariant.withValues(
                                          alpha: 0.4,
                                        ),
                                ),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  8,
                                  10,
                                  12,
                                  10,
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.center,
                                      children: [
                                        Checkbox(
                                          value: isSelected,
                                          onChanged: (_) =>
                                              _toggleItem(todo.id),
                                          visualDensity: VisualDensity.compact,
                                        ),
                                        const SizedBox(width: 4),
                                        Expanded(
                                          child: InkWell(
                                            onTap: () => _toggleItem(todo.id),
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
                                            child: Padding(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    vertical: 4,
                                                  ),
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    todo.title,
                                                    style: TextStyle(
                                                      fontSize: 14,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                      decoration: isSelected
                                                          ? null
                                                          : TextDecoration
                                                                .lineThrough,
                                                      color: isSelected
                                                          ? colorScheme
                                                                .onSurface
                                                          : colorScheme
                                                                .onSurface
                                                                .withValues(
                                                                  alpha: 0.4,
                                                                ),
                                                    ),
                                                    maxLines: 2,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                  ),
                                                  if (todo.dueDate != null)
                                                    Text(
                                                      _formatOverdueTime(
                                                        todo.dueDate!,
                                                      ),
                                                      style: TextStyle(
                                                        fontSize: 11,
                                                        color: Colors
                                                            .redAccent
                                                            .shade200,
                                                        fontWeight:
                                                            FontWeight.w500,
                                                      ),
                                                    ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        // ── 单项智能排期按钮 ──
                                        if (isSearching)
                                          const SizedBox(
                                            width: 24,
                                            height: 24,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                            ),
                                          )
                                        else
                                          OutlinedButton.icon(
                                            onPressed: () =>
                                                _findSlotsForTodo(todo),
                                            icon: const Icon(
                                              Icons.calendar_today_rounded,
                                              size: 13,
                                            ),
                                            label: const Text(
                                              '智能排期',
                                              style: TextStyle(fontSize: 12),
                                            ),
                                            style: OutlinedButton.styleFrom(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 10,
                                                    vertical: 4,
                                                  ),
                                              visualDensity:
                                                  VisualDensity.compact,
                                              shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(10),
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),

                                    // ── 展示智能查找出的可用时段推荐 ──
                                    if (slots != null && slots.isNotEmpty) ...[
                                      const SizedBox(height: 8),
                                      Padding(
                                        padding: const EdgeInsets.only(
                                          left: 42,
                                          bottom: 4,
                                        ),
                                        child: Wrap(
                                          spacing: 8,
                                          runSpacing: 6,
                                          children: slots.map((slot) {
                                            final isToday =
                                                slot.start.day ==
                                                widget.service.clock().day;
                                            final prefix = isToday
                                                ? '今天'
                                                : '明天';
                                            final timeStr =
                                                '$prefix ${DateFormat('HH:mm').format(slot.start)}–${DateFormat('HH:mm').format(slot.end)} (${slot.minutes}分)';
                                            return ActionChip(
                                              avatar: const Icon(
                                                Icons.add_task_rounded,
                                                size: 14,
                                              ),
                                              label: Text(
                                                timeStr,
                                                style: const TextStyle(
                                                  fontSize: 11,
                                                ),
                                              ),
                                              backgroundColor: colorScheme
                                                  .primaryContainer
                                                  .withValues(alpha: 0.5),
                                              onPressed: () =>
                                                  _applySlotSchedule(
                                                    todo,
                                                    slot,
                                                  ),
                                            );
                                          }).toList(),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),

                const Divider(height: 1),

                // ── 底部批量操作栏 ──
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _selectedIds.isEmpty || _isProcessing
                              ? null
                              : () => _handleBatchReschedule(
                                  OverdueRescheduleTarget.clear,
                                ),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Text(
                            '清除截止日',
                            style: TextStyle(fontSize: 13),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: FilledButton.tonal(
                          onPressed: _selectedIds.isEmpty || _isProcessing
                              ? null
                              : () => _handleBatchReschedule(
                                  OverdueRescheduleTarget.tomorrow,
                                ),
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Text(
                            '顺延至明日',
                            style: TextStyle(fontSize: 13),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: FilledButton(
                          onPressed: _selectedIds.isEmpty || _isProcessing
                              ? null
                              : () => _handleBatchReschedule(
                                  OverdueRescheduleTarget.today,
                                ),
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Text(
                            '顺延至今日',
                            style: TextStyle(fontSize: 13),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 快捷弹出逾期待办整理面板
Future<void> showTodoOverdueTriageSheet({
  required BuildContext context,
  required String username,
  required List<TodoItem> overdueTodos,
  required List<TodoItem> allTodos,
  required Function(List<TodoItem>) onTodosChanged,
  required VoidCallback onRefreshRequested,
  TodoOverdueTriageService service = const TodoOverdueTriageService(),
}) {
  return showAppDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierColor: Colors.black.withValues(alpha: 0.35),
    builder: (ctx) => TodoOverdueTriageSheet(
      username: username,
      initialOverdueTodos: overdueTodos,
      allTodos: allTodos,
      onTodosChanged: onTodosChanged,
      onRefreshRequested: onRefreshRequested,
      service: service,
    ),
  );
}
