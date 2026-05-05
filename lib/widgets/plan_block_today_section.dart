import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models.dart';
import '../storage_service.dart';
import '../screens/todo_plan_screen.dart';
import '../screens/plan_block_stats_screen.dart';

class PlanBlockTodaySection extends StatefulWidget {
  final String username;
  final bool isLight;
  final int refreshTrigger;
  final VoidCallback? onTap;

  const PlanBlockTodaySection({
    super.key,
    required this.username,
    this.isLight = false,
    this.refreshTrigger = 0,
    this.onTap,
  });

  @override
  State<PlanBlockTodaySection> createState() => _PlanBlockTodaySectionState();
}

class _PlanBlockTodaySectionState extends State<PlanBlockTodaySection> {
  List<TodoPlanBlock> _blocks = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void didUpdateWidget(PlanBlockTodaySection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshTrigger != widget.refreshTrigger) _loadData();
  }

  Future<void> _loadData() async {
    if (!mounted) return;
    setState(() => _loading = true);
    final now = DateTime.now();
    final blocks =
        await StorageService.getPlanBlocksByDay(widget.username, now);
    // 自动标记过期
    final missed = <TodoPlanBlock>[];
    for (final b in blocks) {
      if (!b.isDeleted &&
          b.status == TodoPlanStatus.planned &&
          b.actualFocusSeconds <= 0 &&
          b.endTime < now.millisecondsSinceEpoch) {
        b.status = TodoPlanStatus.missed;
        b.markAsChanged();
        missed.add(b);
      }
    }
    if (missed.isNotEmpty) {
      await StorageService.savePlanBlocks(widget.username, missed);
    }
    if (mounted) {
      setState(() {
        _blocks = blocks.where((b) => !b.isDeleted).toList();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    if (_loading) {
      return _buildSkeleton(colorScheme);
    }

    final planned =
        _blocks.fold<int>(0, (s, b) => s + b.plannedMinutes);
    final actual =
        _blocks.fold<int>(0, (s, b) => s + b.actualFocusSeconds ~/ 60);
    final rate =
        planned <= 0 ? 0.0 : (actual / planned).clamp(0.0, 999.0);

    return GestureDetector(
      onTap: widget.onTap ??
          () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) =>
                      TodoPlanScreen(username: widget.username),
                ),
              ),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: widget.isLight
                ? [
                    colorScheme.primaryContainer.withValues(alpha: 0.45),
                    colorScheme.surfaceContainerHighest
                        .withValues(alpha: 0.25),
                  ]
                : [
                    colorScheme.primaryContainer.withValues(alpha: 0.22),
                    colorScheme.surfaceContainerHighest
                        .withValues(alpha: 0.15),
                  ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(theme, planned, rate),
            const SizedBox(height: 12),
            if (_blocks.isEmpty)
              _buildEmpty(theme)
            else
              ..._buildBlockList(theme),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(ThemeData theme, int planned, double rate) {
    return Row(
      children: [
        Icon(Icons.event_note_rounded,
            size: 20, color: theme.colorScheme.primary),
        const SizedBox(width: 8),
        Text('今日规划',
            style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.onSurface)),
        const Spacer(),
        if (_blocks.isNotEmpty) ...[
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: _rateColor(rate).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '${planned}m 计划 · ${(rate * 100).round()}% 达成',
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: _rateColor(rate)),
            ),
          ),
          const SizedBox(width: 4),
        ],
        IconButton(
          icon: Icon(Icons.bar_chart_rounded,
              size: 20, color: theme.colorScheme.onSurfaceVariant),
          tooltip: '规划统计',
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) =>
                  PlanBlockStatsScreen(username: widget.username),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEmpty(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(Icons.event_busy_outlined,
              size: 18,
              color: theme.colorScheme.onSurfaceVariant
                  .withValues(alpha: 0.4)),
          const SizedBox(width: 8),
          Text('暂无规划，点击添加',
              style: TextStyle(
                  fontSize: 13,
                  color: theme.colorScheme.onSurfaceVariant
                      .withValues(alpha: 0.5))),
        ],
      ),
    );
  }

  List<Widget> _buildBlockList(ThemeData theme) {
    final sorted = List<TodoPlanBlock>.from(_blocks)
      ..sort((a, b) => a.startTime.compareTo(b.startTime));
    return sorted.take(5).map((b) => _buildBlockRow(b, theme)).toList();
  }

  Widget _buildBlockRow(TodoPlanBlock block, ThemeData theme) {
    final start =
        DateFormat('HH:mm').format(
            DateTime.fromMillisecondsSinceEpoch(block.startTime));
    final end =
        DateFormat('HH:mm').format(
            DateTime.fromMillisecondsSinceEpoch(block.endTime));
    final statusIcon = _statusIcon(block);
    final statusColor = _statusColor(block);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Icon(statusIcon, size: 15, color: statusColor),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              block.titleSnapshot ?? '未命名',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: theme.colorScheme.onSurface),
            ),
          ),
          Text('$start-$end',
              style: TextStyle(
                  fontSize: 11,
                  color: theme.colorScheme.onSurfaceVariant)),
          const SizedBox(width: 4),
          Text('${block.plannedMinutes}m',
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: statusColor)),
        ],
      ),
    );
  }

  IconData _statusIcon(TodoPlanBlock block) {
    switch (block.status) {
      case TodoPlanStatus.finished:
        return Icons.check_circle_rounded;
      case TodoPlanStatus.focusing:
        return Icons.play_circle_fill_rounded;
      case TodoPlanStatus.missed:
        return Icons.cancel_rounded;
      case TodoPlanStatus.skipped:
        return Icons.skip_next_rounded;
      case TodoPlanStatus.cancelled:
        return Icons.remove_circle_outline;
      default:
        return Icons.radio_button_unchecked;
    }
  }

  Color _statusColor(TodoPlanBlock block) {
    switch (block.status) {
      case TodoPlanStatus.finished:
        return Colors.green;
      case TodoPlanStatus.focusing:
        return Colors.blue;
      case TodoPlanStatus.missed:
        return Colors.redAccent;
      case TodoPlanStatus.skipped:
        return Colors.orange;
      case TodoPlanStatus.cancelled:
        return Colors.grey;
      default:
        return Colors.deepPurple;
    }
  }

  Color _rateColor(double rate) {
    if (rate >= 0.8) return Colors.green;
    if (rate >= 0.5) return Colors.orange;
    return Colors.redAccent;
  }

  Widget _buildSkeleton(ColorScheme colorScheme) {
    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest
            .withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
      ),
      padding: const EdgeInsets.all(16),
      height: 120,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
              width: 100,
              height: 16,
              decoration: BoxDecoration(
                  color: colorScheme.onSurface.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(4))),
          const SizedBox(height: 16),
          Container(
              width: double.infinity,
              height: 12,
              decoration: BoxDecoration(
                  color: colorScheme.onSurface.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(4))),
          const SizedBox(height: 8),
          Container(
              width: 200,
              height: 12,
              decoration: BoxDecoration(
                  color: colorScheme.onSurface.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(4))),
        ],
      ),
    );
  }
}
