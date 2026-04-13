import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models.dart';

class TodoGroupWidget extends StatefulWidget {
  final TodoGroup group;
  final List<TodoItem> groupTodos;
  final bool isLight;
  final VoidCallback onToggle;
  final Function(TodoItem) onTodoToggle;
  final Function(String todoId) onTodoDropped;
  final Function(String todoId)? onTodoRemoved;
  final VoidCallback onDelete;
  final Function(TodoItem) onTodoTap;

  const TodoGroupWidget({
    super.key,
    required this.group,
    required this.groupTodos,
    required this.isLight,
    required this.onToggle,
    required this.onTodoToggle,
    required this.onTodoDropped,
    this.onTodoRemoved,
    required this.onDelete,
    required this.onTodoTap,
  });

  @override
  State<TodoGroupWidget> createState() => _TodoGroupWidgetState();
}

class _TodoGroupWidgetState extends State<TodoGroupWidget> with TickerProviderStateMixin {

  // Dynamic color based on group urgency (most urgent task wins)
  Color _getGroupUrgencyColor(List<TodoItem> todos) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    bool hasOverdue = false;
    double maxProgress = 0.0;

    for (final t in todos) {
      if (t.isDone) continue;
      final cDate = DateTime.fromMillisecondsSinceEpoch(
        t.createdDate ?? t.createdAt, isUtc: true,
      ).toLocal();
      final end = t.dueDate ?? DateTime(cDate.year, cDate.month, cDate.day, 23, 59, 59);
      final dueDay = DateTime(end.year, end.month, end.day);
      if (dueDay.isBefore(today)) {
        hasOverdue = true;
        break;
      }
      final totalMin = end.difference(cDate).inMinutes;
      if (totalMin > 0 && now.isAfter(cDate)) {
        final p = (now.difference(cDate).inMinutes / totalMin).clamp(0.0, 1.0);
        if (p > maxProgress) maxProgress = p;
      }
    }

    if (hasOverdue || maxProgress >= 1.0) {
      return const Color(0xFFE57373); // red
    } else if (maxProgress >= 0.5) {
      return const Color(0xFFFFB74D); // orange
    } else {
      return const Color(0xFF66BB6A); // green
    }
  }

  // Compute the overall group progress (max progress of any undone task)
  double _getGroupProgress(List<TodoItem> todos) {
    final now = DateTime.now();
    double maxProgress = 0.0;
    for (final t in todos) {
      if (t.isDone) continue;
      final cDate = DateTime.fromMillisecondsSinceEpoch(
        t.createdDate ?? t.createdAt, isUtc: true,
      ).toLocal();
      final end = t.dueDate ?? DateTime(cDate.year, cDate.month, cDate.day, 23, 59, 59);
      final totalMin = end.difference(cDate).inMinutes;
      if (totalMin > 0 && now.isAfter(cDate)) {
        final p = (now.difference(cDate).inMinutes / totalMin).clamp(0.0, 1.0);
        if (p > maxProgress) maxProgress = p;
      }
    }
    return maxProgress;
  }

  @override
  Widget build(BuildContext context) {
    final group = widget.group;
    final groupTodos = widget.groupTodos;
    final isLight = widget.isLight;
    final onToggle = widget.onToggle;
    final onTodoToggle = widget.onTodoToggle;
    final onTodoDropped = widget.onTodoDropped;
    final onDelete = widget.onDelete;
    final onTodoTap = widget.onTodoTap;
    // Sort by deadline
    final sortedTodos = List<TodoItem>.from(groupTodos)
      ..sort((a, b) {
        if (a.isDone != b.isDone) return a.isDone ? 1 : -1;
        if (a.dueDate == null && b.dueDate == null) return 0;
        if (a.dueDate == null) return 1;
        if (b.dueDate == null) return -1;
        return a.dueDate!.compareTo(b.dueDate!);
      });

    final doneCount = groupTodos.where((t) => t.isDone).length;
    final totalCount = groupTodos.length;
    final progress = totalCount == 0 ? 0.0 : doneCount / totalCount;
    final allDone = totalCount > 0 && doneCount == totalCount;

    // Nearest deadline
    DateTime? nearestDeadline;
    final upcomingTodos = groupTodos.where((t) => !t.isDone && t.dueDate != null).toList();
    if (upcomingTodos.isNotEmpty) {
      upcomingTodos.sort((a, b) => a.dueDate!.compareTo(b.dueDate!));
      nearestDeadline = upcomingTodos.first.dueDate;
    }

    // Urgency metrics for background fill
    final urgencyColor = allDone ? Colors.green : _getGroupUrgencyColor(groupTodos);
    final groupFillProgress = allDone ? 1.0 : _getGroupProgress(groupTodos);

    return DragTarget<String>(
      onWillAccept: (data) => data != null,
      onAccept: (todoId) => widget.onTodoDropped(todoId),
      builder: (context, candidateData, rejectedData) {
        final isHovering = candidateData.isNotEmpty;

        return AnimatedSize(
          duration: const Duration(milliseconds: 400),
          curve: Curves.fastOutSlowIn,
          alignment: Alignment.topCenter,
          child: Container(
            decoration: BoxDecoration(
              color: group.isExpanded 
                  ? (isLight ? Colors.white.withValues(alpha: 0.5) : Colors.grey[900]?.withValues(alpha: 0.5))
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(24),
            ),
            child: Column(
              children: [
                _buildGroupHeader(context, progress, doneCount, totalCount,
                    nearestDeadline, allDone, isHovering, urgencyColor, groupFillProgress),
                if (widget.group.isExpanded)
                  Container(
                    padding: const EdgeInsets.only(left: 12, right: 12, bottom: 20, top: 8),
                    decoration: BoxDecoration(
                      color: isLight ? Colors.white.withValues(alpha: 0.9) : Colors.grey[850]!.withValues(alpha: 0.95),
                      border: Border(
                        left: BorderSide(color: isLight ? Colors.grey.withValues(alpha: 0.15) : Colors.white.withValues(alpha: 0.08)),
                        right: BorderSide(color: isLight ? Colors.grey.withValues(alpha: 0.15) : Colors.white.withValues(alpha: 0.08)),
                        bottom: BorderSide(color: isLight ? Colors.grey.withValues(alpha: 0.15) : Colors.white.withValues(alpha: 0.08)),
                      ),
                      borderRadius: const BorderRadius.vertical(bottom: Radius.circular(24)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: isLight ? 0.03 : 0.15),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      children: sortedTodos.map((todo) => _buildTodoItem(context, todo)).toList(),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildGroupHeader(
    BuildContext context,
    double progress,
    int doneCount,
    int totalCount,
    DateTime? nearestDeadline,
    bool allDone,
    bool isHovering,
    Color urgencyColor,
    double groupFillProgress,
  ) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    // Icon and accent color syncs with urgency
    final statusColor = allDone ? Colors.green : urgencyColor;

    return Column(
      children: [
        // Stack layers for collapsed effect
        if (totalCount > 1 && !widget.group.isExpanded)
          AnimatedOpacity(
            duration: const Duration(milliseconds: 300),
            opacity: 1.0,
            child: Column(
              children: [
                _buildStackLayerInline(context, 0.94, 0.3),
                const SizedBox(height: 2),
                _buildStackLayerInline(context, 0.97, 0.6),
                const SizedBox(height: 2),
              ],
            ),
          ),

        // Main card with background fill
        GestureDetector(
          onTap: widget.onToggle,
          onLongPress: () => _showGroupMenu(context),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: isHovering
                  ? statusColor.withOpacity(0.08)
                  : (widget.isLight ? Colors.white : Colors.grey[900]),
              borderRadius: widget.group.isExpanded
                  ? const BorderRadius.vertical(top: Radius.circular(20))
                  : BorderRadius.circular(20),
              border: Border.all(
                  color: allDone
                      ? Colors.green.withOpacity(isDark ? 0.25 : 0.15)
                      : isHovering
                          ? statusColor
                          : (widget.isLight
                              ? Colors.grey.withOpacity(0.12)
                              : Colors.white.withOpacity(0.06)),
                  width: allDone || isHovering ? 1.2 : 1),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.03),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Stack(
              children: [
                // Background progress fill
                if (!allDone)
                  Positioned.fill(
                    child: FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: groupFillProgress.clamp(0.0, 1.0),
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              urgencyColor.withOpacity(widget.isLight ? 0.32 : 0.18),
                              urgencyColor.withOpacity(widget.isLight ? 0.15 : 0.07),
                            ],
                            begin: Alignment.centerLeft,
                            end: Alignment.centerRight,
                          ),
                        ),
                      ),
                    ),
                  ),
                // All-done gradient overlay
                if (allDone)
                  Positioned.fill(
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: isDark
                              ? [Colors.green.withOpacity(0.12), Colors.green.withOpacity(0.04)]
                              : [Colors.green.withOpacity(0.06), Colors.green.withOpacity(0.01)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                      ),
                    ),
                  ),
                // Actual content
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: statusColor.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          allDone
                            ? Icons.task_alt_rounded
                            : (widget.group.isExpanded ? Icons.folder_open_rounded : Icons.folder_rounded),
                          color: statusColor,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.group.name,
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.bold,
                                color: allDone
                                  ? (isDark ? Colors.green.shade200 : Colors.green.shade800)
                                  : (widget.isLight ? Colors.black87 : Colors.white),
                                letterSpacing: 0.2,
                              ),
                            ),
                            const SizedBox(height: 1),
                            Text(
                              allDone ? "全部任务已完成 ✨" : "$doneCount/$totalCount 已完成",
                              style: TextStyle(
                                fontSize: 11,
                                color: allDone
                                  ? (isDark ? Colors.green.withOpacity(0.5) : Colors.green.withOpacity(0.6))
                                  : Colors.grey[500],
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (nearestDeadline != null && !widget.group.isExpanded && !allDone) ...[
                        _buildDeadlineTag(context, nearestDeadline),
                        const SizedBox(width: 8),
                      ],
                      Icon(
                        widget.group.isExpanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                        color: Colors.grey.withOpacity(0.4),
                        size: 20,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStackLayerInline(BuildContext context, double scale, double opacity) {
    return Transform.scale(
      scale: scale,
      child: Container(
        height: 7,
        width: MediaQuery.of(context).size.width * 0.88,
        decoration: BoxDecoration(
          color: (widget.isLight ? Colors.white : Colors.grey[800])!.withValues(alpha: opacity),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
          border: Border.all(
            color: widget.isLight ? Colors.black.withValues(alpha: 0.08) : Colors.white.withValues(alpha: 0.08),
            width: 1,
          ),
        ),
      ),
    );
  }

  Widget _buildDeadlineTag(BuildContext context, DateTime deadline) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(deadline.year, deadline.month, deadline.day);
    final diff = target.difference(today).inDays;

    String label;
    Color color;
    if (diff == 0) {
      label = "今天";
      color = Colors.orange;
    } else if (diff == 1) {
      label = "明天";
      color = Colors.blue;
    } else if (diff < 0) {
      label = "逾期";
      color = Colors.red;
    } else {
      label = DateFormat('MM-dd').format(deadline);
      color = Colors.grey;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.5), width: 0.5),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _buildTodoItem(BuildContext context, TodoItem todo) {
    DateTime start = DateTime.fromMillisecondsSinceEpoch(todo.createdDate ?? todo.createdAt, isUtc: true).toLocal();
    final bool isAllDay = todo.dueDate != null &&
        start.hour == 0 && start.minute == 0 &&
        todo.dueDate!.hour == 23 && todo.dueDate!.minute == 59;

    // Build time string: "MM/dd HH:mm → MM/dd HH:mm" or "MM/dd → MM/dd" for all-day
    String timeStr = "";
    if (todo.dueDate != null) {
      if (isAllDay) {
        timeStr = "${DateFormat('MM/dd').format(start)} → ${DateFormat('MM/dd').format(todo.dueDate!)}";
      } else {
        timeStr = "${DateFormat('MM/dd HH:mm').format(start)} → ${DateFormat('MM/dd HH:mm').format(todo.dueDate!)}";
      }
    } else {
      timeStr = "开始 ${DateFormat('MM/dd HH:mm').format(start)}";
    }

    // Deadline urgency color
    Color? deadlineColor;
    if (todo.dueDate != null && !todo.isDone) {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final dueDay = DateTime(todo.dueDate!.year, todo.dueDate!.month, todo.dueDate!.day);
      if (dueDay.isBefore(today)) {
        deadlineColor = Colors.redAccent;
      } else if (dueDay.isAtSameMomentAs(today)) {
        deadlineColor = Colors.orange;
      }
    }

    return LongPressDraggable<String>(
      data: todo.id,
      onDragEnd: (details) {
        if (!details.wasAccepted) {
          widget.onTodoRemoved?.call(todo.id);
        }
      },
      feedback: Material(
        color: Colors.transparent,
        child: Container(
          width: MediaQuery.of(context).size.width * 0.8,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: widget.isLight ? Colors.white : Colors.grey[900],
            borderRadius: BorderRadius.circular(16),
            boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 10, spreadRadius: 1)],
          ),
          child: Text(todo.title, style: TextStyle(color: widget.isLight ? Colors.black : Colors.white)),
        ),
      ),
      child: InkWell(
        onTap: () => widget.onTodoTap(todo),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12.0, horizontal: 8.0),
          margin: const EdgeInsets.symmetric(vertical: 4.0),
          decoration: BoxDecoration(
            color: widget.isLight ? Colors.black.withOpacity(0.02) : Colors.white.withOpacity(0.03),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: GestureDetector(
                  onTap: () => widget.onTodoToggle(todo),
                  child: Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      color: todo.isDone ? Colors.green : Colors.transparent,
                      borderRadius: BorderRadius.circular(7),
                      border: Border.all(
                        color: todo.isDone ? Colors.green : Colors.grey.withOpacity(0.4),
                        width: 1.8,
                      ),
                    ),
                    child: todo.isDone
                        ? const Icon(Icons.check, size: 15, color: Colors.white)
                        : null,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      todo.title,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: widget.isLight ? Colors.black87 : Colors.white,
                        decoration: todo.isDone ? TextDecoration.lineThrough : null,
                        height: 1.25,
                      ),
                    ),
                    const SizedBox(height: 5),
                    // Time row
                    Row(
                      children: [
                        Icon(Icons.access_time_rounded, size: 12, color: deadlineColor ?? Colors.grey[500]),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            timeStr,
                            style: TextStyle(
                              fontSize: 12.5,
                              color: deadlineColor ?? Colors.grey[500],
                              fontWeight: deadlineColor != null ? FontWeight.w600 : FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                    // Remark
                    if (todo.remark != null && todo.remark!.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(top: 1),
                            child: Icon(Icons.notes_rounded, size: 12, color: Colors.grey[500]),
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              todo.remark!,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 12.5, color: Colors.grey[600], height: 1.4),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showGroupMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit, color: Colors.blue),
              title: const Text("修改组名"),
              onTap: () {
                Navigator.pop(ctx);
                _showRenameDialog(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete, color: Colors.red),
              title: const Text("解散分组"),
              subtitle: const Text("组内待办将恢复为独立状态"),
              onTap: () {
                Navigator.pop(ctx);
                widget.onDelete();
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showRenameDialog(BuildContext context) {
    final ctrl = TextEditingController(text: widget.group.name);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("重命名分组"),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(hintText: "输入新名称"),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("取消")),
          TextButton(
            onPressed: () {
              if (ctrl.text.trim().isNotEmpty) {
                widget.group.name = ctrl.text.trim();
                widget.group.markAsChanged();
                // 触发保存
                widget.onToggle(); 
                Navigator.pop(ctx);
              }
            },
            child: const Text("确定"),
          ),
        ],
      ),
    );
  }
}
