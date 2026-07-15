import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

enum TodoRecurrenceNodeState {
  completed,
  overdue,
  current,
  pending,
  future,
  neutral,
}

class TodoRecurrenceProgressNode {
  const TodoRecurrenceProgressNode({
    required this.date,
    required this.state,
    this.occurrenceId,
    this.isCurrent = false,
    this.label,
  });

  final DateTime date;
  final TodoRecurrenceNodeState state;
  final String? occurrenceId;
  final bool isCurrent;
  final String? label;

  String get key =>
      occurrenceId ??
      '${date.millisecondsSinceEpoch}_${state.name}_${isCurrent ? 1 : 0}';
}

class TodoRecurrenceProgress extends StatefulWidget {
  const TodoRecurrenceProgress({
    super.key,
    required this.nodes,
    required this.completedCount,
    this.totalCount,
    this.overdueCount = 0,
    this.initiallyExpanded = true,
    this.onNodeTap,
    this.onManage,
  });

  final List<TodoRecurrenceProgressNode> nodes;
  final int completedCount;

  /// 有限循环的总期数。无限循环传 null，仅显示累计完成期数。
  final int? totalCount;
  final int overdueCount;
  final bool initiallyExpanded;
  final ValueChanged<TodoRecurrenceProgressNode>? onNodeTap;
  final VoidCallback? onManage;

  @override
  State<TodoRecurrenceProgress> createState() => _TodoRecurrenceProgressState();
}

class _TodoRecurrenceProgressState extends State<TodoRecurrenceProgress> {
  late bool _expanded;

  @override
  void initState() {
    super.initState();
    _expanded = widget.initiallyExpanded;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final completionSummary = widget.totalCount == null
        ? '已完成 ${widget.completedCount} 期'
        : '已完成 ${widget.completedCount}/${widget.totalCount} 期';
    final summary = completionSummary +
        (widget.overdueCount > 0 ? ' · ${widget.overdueCount} 逾期' : '');

    return Semantics(
      label: '循环进度，$summary',
      child: GestureDetector(
        key: const ValueKey('todo_recurrence_progress'),
        behavior: HitTestBehavior.opaque,
        onLongPress: widget.onManage,
        child: Container(
          padding: const EdgeInsets.fromLTRB(9, 7, 9, 6),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(9),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              InkWell(
                key: const ValueKey('recurrence_progress_toggle'),
                borderRadius: BorderRadius.circular(7),
                onTap: () => setState(() => _expanded = !_expanded),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 1),
                  child: Row(
                    children: [
                      Icon(
                        Icons.repeat_rounded,
                        size: 12,
                        color: colorScheme.primary,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          _expanded ? '循环进度 · $summary' : summary,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                      Icon(
                        _expanded
                            ? Icons.expand_less_rounded
                            : Icons.expand_more_rounded,
                        size: 15,
                        color: colorScheme.onSurfaceVariant
                            .withValues(alpha: 0.65),
                      ),
                    ],
                  ),
                ),
              ),
              AnimatedSize(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                alignment: Alignment.topCenter,
                child: _expanded
                    ? Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: _buildTimeline(colorScheme),
                      )
                    : const SizedBox(width: double.infinity),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTimeline(ColorScheme colorScheme) {
    if (widget.nodes.length <= 7) {
      return Row(
        children: [
          for (var i = 0; i < widget.nodes.length; i++) ...[
            if (i > 0) Expanded(child: _buildDottedConnector(colorScheme)),
            _buildNode(widget.nodes[i], colorScheme),
          ],
        ],
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (var i = 0; i < widget.nodes.length; i++) ...[
            if (i > 0)
              SizedBox(
                width: 22,
                child: _buildDottedConnector(colorScheme),
              ),
            _buildNode(widget.nodes[i], colorScheme),
          ],
        ],
      ),
    );
  }

  Widget _buildDottedConnector(ColorScheme colorScheme) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: List.generate(
        4,
        (_) => Container(
          width: 2.5,
          height: 1.2,
          decoration: BoxDecoration(
            color: colorScheme.outlineVariant,
            borderRadius: BorderRadius.circular(1),
          ),
        ),
      ),
    );
  }

  Widget _buildNode(
    TodoRecurrenceProgressNode node,
    ColorScheme colorScheme,
  ) {
    final (Color background, Color foreground, IconData? icon, bool outlined) =
        switch (node.state) {
      TodoRecurrenceNodeState.completed => (
          colorScheme.primary,
          colorScheme.onPrimary,
          Icons.check_rounded,
          false,
        ),
      TodoRecurrenceNodeState.overdue => (
          colorScheme.error,
          colorScheme.onError,
          Icons.priority_high_rounded,
          false,
        ),
      TodoRecurrenceNodeState.current => (
          colorScheme.secondary,
          colorScheme.onSecondary,
          Icons.circle,
          false,
        ),
      TodoRecurrenceNodeState.pending => (
          colorScheme.tertiaryContainer,
          colorScheme.onTertiaryContainer,
          Icons.more_horiz_rounded,
          false,
        ),
      TodoRecurrenceNodeState.future => (
          colorScheme.surfaceContainerHighest,
          colorScheme.outline,
          null,
          true,
        ),
      TodoRecurrenceNodeState.neutral => (
          colorScheme.surfaceContainer,
          colorScheme.onSurfaceVariant,
          Icons.remove_rounded,
          true,
        ),
    };
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final nodeDay = DateTime(node.date.year, node.date.month, node.date.day);
    final label = node.label ??
        (nodeDay == today ? '今天' : DateFormat('M/d').format(node.date));

    return Semantics(
      button: widget.onNodeTap != null,
      label: '$label，${_stateLabel(node.state)}'
          '${node.occurrenceId != null && !node.isCurrent ? '，点击管理本期' : ''}',
      child: InkWell(
        key: ValueKey('recurrence_node_${node.key}'),
        borderRadius: BorderRadius.circular(8),
        onTap: widget.onNodeTap == null ? null : () => widget.onNodeTap!(node),
        child: SizedBox(
          width: 31,
          child: Column(
            children: [
              Container(
                width: 18,
                height: 18,
                decoration: BoxDecoration(
                  color: background,
                  shape: BoxShape.circle,
                  border: outlined
                      ? Border.all(color: colorScheme.outlineVariant)
                      : null,
                  boxShadow: node.state == TodoRecurrenceNodeState.current
                      ? [
                          BoxShadow(
                            color:
                                colorScheme.secondary.withValues(alpha: 0.28),
                            blurRadius: 5,
                            spreadRadius: 1,
                          ),
                        ]
                      : null,
                ),
                alignment: Alignment.center,
                child: icon == null
                    ? null
                    : Icon(
                        icon,
                        size: node.state == TodoRecurrenceNodeState.current
                            ? 6
                            : 11,
                        color: foreground,
                      ),
              ),
              const SizedBox(height: 2),
              Text(
                label,
                maxLines: 1,
                style: TextStyle(
                  fontSize: 8.5,
                  fontWeight:
                      node.isCurrent ? FontWeight.bold : FontWeight.w500,
                  color: node.isCurrent
                      ? colorScheme.secondary
                      : colorScheme.onSurfaceVariant.withValues(alpha: 0.72),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _stateLabel(TodoRecurrenceNodeState state) => switch (state) {
        TodoRecurrenceNodeState.completed => '已完成',
        TodoRecurrenceNodeState.overdue => '已逾期',
        TodoRecurrenceNodeState.current => '当前周期',
        TodoRecurrenceNodeState.pending => '待完成',
        TodoRecurrenceNodeState.future => '未来周期',
        TodoRecurrenceNodeState.neutral => '已跳过或循环结束',
      };
}
