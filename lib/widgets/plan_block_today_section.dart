import 'dart:math';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models.dart';
import '../storage_service.dart';
import '../services/pomodoro_service.dart';
import '../screens/todo_plan_screen.dart';
import '../screens/plan_block_stats_screen.dart';
import '../utils/page_transitions.dart';

class PlanBlockTodaySection extends StatefulWidget {
  final String username;
  final bool isLight;
  final int refreshTrigger;
  final VoidCallback? onTap;
  final Key? chartKey;

  const PlanBlockTodaySection({
    super.key,
    required this.username,
    this.isLight = false,
    this.refreshTrigger = 0,
    this.onTap,
    this.chartKey,
  });

  @override
  State<PlanBlockTodaySection> createState() => _PlanBlockTodaySectionState();
}

class _PlanBlockTodaySectionState extends State<PlanBlockTodaySection> {
  List<TodoPlanBlock> _blocks = [];
  List<PomodoroRecord> _records = [];
  bool _loading = true;
  String? _expandedBlockId;

  bool _timeRangesOverlap(
      int startA, int endAExclusive, int startB, int endBExclusive) {
    return endAExclusive > startB && startA < endBExclusive;
  }

  String _normalizeTitle(String? s) {
    if (s == null) return '';
    return s.replaceAll(RegExp(r'\s+'), '').trim();
  }

  bool _isRecordAssociatedWithBlock(
      PomodoroRecord record, TodoPlanBlock block) {
    if (record.isDeleted || block.isDeleted) return false;

    if (record.planBlockId != null &&
        record.planBlockId!.isNotEmpty &&
        record.planBlockId == block.uuid) {
      return true;
    }

    if (block.pomodoroRecordIds.contains(record.uuid)) {
      return true;
    }

    if (record.planBlockId?.isNotEmpty == true) {
      return false;
    }

    if (record.todoUuid != null &&
        record.todoUuid!.isNotEmpty &&
        block.todoId.isNotEmpty &&
        record.todoUuid == block.todoId) {
      final recordEnd = record.endTime ??
          (record.startTime + record.effectiveDuration * 1000);
      return _timeRangesOverlap(
          record.startTime, recordEnd, block.startTime, block.endTime);
    }

    final recordTitle = _normalizeTitle(record.todoTitle);
    final blockTitle = _normalizeTitle(block.titleSnapshot);
    if (recordTitle.isNotEmpty && blockTitle.isNotEmpty) {
      final recordEnd = record.endTime ??
          (record.startTime + record.effectiveDuration * 1000);
      if (_timeRangesOverlap(
              record.startTime, recordEnd, block.startTime, block.endTime) &&
          recordTitle == blockTitle) {
        return true;
      }
    }

    return false;
  }

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
    final dayStart = DateTime(now.year, now.month, now.day);
    final dayEnd = dayStart.add(const Duration(days: 1));
    final results = await Future.wait([
      StorageService.getPlanBlocksByDay(widget.username, now),
      PomodoroService.getRecordsInRange(dayStart, dayEnd),
    ]);
    final blocks = results[0] as List<TodoPlanBlock>;
    final records = (results[1] as List<PomodoroRecord>)
        .where((record) =>
            !record.isDeleted &&
            record.startTime >= dayStart.millisecondsSinceEpoch &&
            record.startTime < dayEnd.millisecondsSinceEpoch)
        .toList();
    // 自动标记过期
    final missed = <TodoPlanBlock>[];
    for (final b in blocks) {
      if (!b.isDeleted &&
          b.status == TodoPlanStatus.planned &&
          _actualSecondsForBlock(b, records) <= 0 &&
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
        _records = records;
        _loading = false;
      });
    }
  }

  /// planBlockId → 关联记录列表
  Map<String, List<PomodoroRecord>> get _blockRecordsMap {
    final map = <String, List<PomodoroRecord>>{
      for (final b in _blocks) b.uuid: [],
    };
    for (final block in _blocks) {
      for (final record in _records) {
        if (_isRecordAssociatedWithBlock(record, block)) {
          map[block.uuid]!.add(record);
        }
      }
    }
    return map;
  }

  /// 不属于任何规划块的自由专注记录
  List<PomodoroRecord> _freeRecords(
      Map<String, List<PomodoroRecord>> blockRecordsMap) {
    final now = DateTime.now();
    final dayStart =
        DateTime(now.year, now.month, now.day).millisecondsSinceEpoch;
    final dayEnd = DateTime(now.year, now.month, now.day)
        .add(const Duration(days: 1))
        .millisecondsSinceEpoch;
    final associatedUuids = blockRecordsMap.values
        .expand((records) => records)
        .map((r) => r.uuid)
        .toSet();
    return _records.where((r) => !associatedUuids.contains(r.uuid)).where((r) {
      final recordEnd = r.endTime ?? (r.startTime + r.effectiveDuration * 1000);
      return _timeRangesOverlap(r.startTime, recordEnd, dayStart, dayEnd);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    if (_loading) {
      return _buildSkeleton(colorScheme);
    }

    final blockRecordsMap = _blockRecordsMap;
    final freeRecords = _freeRecords(blockRecordsMap);
    final planned = _blocks.fold<int>(0, (s, b) => s + b.plannedMinutes);
    final actual = _blocks.fold<int>(0, (s, b) {
      final fromRecords = (blockRecordsMap[b.uuid] ?? const <PomodoroRecord>[])
              .fold<int>(0, (sum, r) => sum + r.effectiveDuration) ~/
          60;
      final fromBlock = b.actualFocusSeconds ~/ 60;
      return s + max(fromRecords, fromBlock);
    });
    final rate = planned <= 0 ? 0.0 : (actual / planned).clamp(0.0, 999.0);

    return GestureDetector(
      onTap: widget.onTap ??
          () => Navigator.of(context).push(
                PageTransitions.material(
                  builder: (_) => TodoPlanScreen(username: widget.username),
                ),
              ),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: widget.isLight
                ? [
                    colorScheme.primaryContainer.withValues(alpha: 0.45),
                    colorScheme.surfaceContainerHighest.withValues(alpha: 0.25),
                  ]
                : [
                    colorScheme.primaryContainer.withValues(alpha: 0.22),
                    colorScheme.surfaceContainerHighest.withValues(alpha: 0.15),
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
            if (_blocks.isEmpty && freeRecords.isEmpty)
              _buildEmpty(theme)
            else ...[
              ..._buildBlockList(theme, blockRecordsMap),
              if (freeRecords.isNotEmpty) ...[
                const SizedBox(height: 8),
                _buildFreeRecordsSection(theme, freeRecords),
              ],
            ],
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
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
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
        SizedBox(
          key: widget.chartKey,
          child: IconButton(
            icon: Icon(Icons.bar_chart_rounded,
                size: 20, color: theme.colorScheme.onSurfaceVariant),
            tooltip: '规划统计',
            onPressed: () => Navigator.of(context).push(
              PageTransitions.material(
                builder: (_) => PlanBlockStatsScreen(username: widget.username),
              ),
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
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4)),
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

  List<Widget> _buildBlockList(
      ThemeData theme, Map<String, List<PomodoroRecord>> blockRecordsMap) {
    final sorted = List<TodoPlanBlock>.from(_blocks)
      ..sort((a, b) => a.startTime.compareTo(b.startTime));
    return sorted
        .take(5)
        .map((b) => _buildBlockRow(b, theme, blockRecordsMap))
        .toList();
  }

  Widget _buildBlockRow(
    TodoPlanBlock block,
    ThemeData theme,
    Map<String, List<PomodoroRecord>> blockRecordsMap,
  ) {
    final start = DateFormat('HH:mm')
        .format(DateTime.fromMillisecondsSinceEpoch(block.startTime));
    final end = DateFormat('HH:mm')
        .format(DateTime.fromMillisecondsSinceEpoch(block.endTime));
    final statusIcon = _statusIcon(block);
    final statusColor = _statusColor(block);
    final isExpanded = _expandedBlockId == block.uuid;
    final records = blockRecordsMap[block.uuid] ?? [];
    final hasRecords = records.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: hasRecords
              ? () => setState(() {
                    _expandedBlockId = isExpanded ? null : block.uuid;
                  })
              : null,
          child: Padding(
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
                if (hasRecords)
                  Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: Icon(
                      isExpanded
                          ? Icons.keyboard_arrow_up
                          : Icons.keyboard_arrow_down,
                      size: 16,
                      color: theme.colorScheme.onSurfaceVariant
                          .withValues(alpha: 0.5),
                    ),
                  ),
                Text('$start-$end',
                    style: TextStyle(
                        fontSize: 11,
                        color: theme.colorScheme.onSurfaceVariant)),
                const SizedBox(width: 4),
                Text(
                  _blockActualText(block, records),
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: statusColor),
                ),
              ],
            ),
          ),
        ),
        // 展开的专注记录列表
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          alignment: Alignment.topCenter,
          child: isExpanded
              ? _buildRecordList(records, theme)
              : const SizedBox.shrink(),
        ),
      ],
    );
  }

  /// 规划块右侧时长文本：实际/计划
  String _blockActualText(TodoPlanBlock block,
      [List<PomodoroRecord> records = const <PomodoroRecord>[]]) {
    final actualFromRecords =
        records.fold<int>(0, (sum, r) => sum + r.effectiveDuration) ~/ 60;
    final actualMin = max(actualFromRecords, block.actualFocusSeconds ~/ 60);
    if (actualMin <= 0) return '${block.plannedMinutes}m';
    return '$actualMin/${block.plannedMinutes}m';
  }

  int _actualSecondsForBlock(
    TodoPlanBlock block,
    List<PomodoroRecord> records,
  ) {
    final linkedRecordSeconds = records
        .where((record) => _isRecordAssociatedWithBlock(record, block))
        .fold<int>(0, (sum, record) => sum + record.effectiveDuration);
    return max(block.actualFocusSeconds, linkedRecordSeconds);
  }

  Widget _buildRecordList(List<PomodoroRecord> records, ThemeData theme) {
    final sorted = List<PomodoroRecord>.from(records)
      ..sort((a, b) => a.startTime.compareTo(b.startTime));
    return Padding(
      padding: const EdgeInsets.only(left: 23, top: 4, bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ...sorted.map((r) => _buildRecordRow(r, theme)),
        ],
      ),
    );
  }

  Widget _buildRecordRow(PomodoroRecord record, ThemeData theme) {
    final startTime = DateFormat('HH:mm').format(
        DateTime.fromMillisecondsSinceEpoch(record.startTime, isUtc: true)
            .toLocal());
    final duration = PomodoroService.formatDuration(record.effectiveDuration);
    final (icon, color) = _recordStatusIcon(record);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 6),
          Text(
            startTime,
            style: TextStyle(
                fontSize: 12,
                color:
                    theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7)),
          ),
          const SizedBox(width: 8),
          Text(
            duration,
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.onSurfaceVariant),
          ),
          if (record.todoTitle != null && record.todoTitle!.isNotEmpty) ...[
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                record.todoTitle!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 11,
                    color: theme.colorScheme.onSurfaceVariant
                        .withValues(alpha: 0.5)),
              ),
            ),
          ],
        ],
      ),
    );
  }

  (IconData, Color) _recordStatusIcon(PomodoroRecord record) {
    switch (record.status) {
      case PomodoroRecordStatus.completed:
        return (Icons.check_circle_rounded, Colors.green);
      case PomodoroRecordStatus.interrupted:
        return (Icons.warning_amber_rounded, Colors.orange);
      case PomodoroRecordStatus.switched:
        return (
          Icons.swap_horiz_rounded,
          Theme.of(context).colorScheme.primary
        );
    }
  }

  Widget _buildFreeRecordsSection(
      ThemeData theme, List<PomodoroRecord> freeRecords) {
    final sorted = List<PomodoroRecord>.from(freeRecords)
      ..sort((a, b) => a.startTime.compareTo(b.startTime));
    final totalSec = sorted.fold<int>(0, (s, r) => s + r.effectiveDuration);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.timer_outlined,
                size: 15,
                color:
                    theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6)),
            const SizedBox(width: 8),
            Text(
              '自由专注',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(width: 8),
            Text(
              '${sorted.length} 次 · ${PomodoroService.formatDuration(totalSec)}',
              style: TextStyle(
                  fontSize: 11,
                  color: theme.colorScheme.onSurfaceVariant
                      .withValues(alpha: 0.6)),
            ),
          ],
        ),
        const SizedBox(height: 4),
        ...sorted.map((r) => _buildRecordRow(r, theme)),
      ],
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
        return Theme.of(context).colorScheme.primary;
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
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.15),
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
