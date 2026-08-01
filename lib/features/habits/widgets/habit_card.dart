import 'package:flutter/material.dart';

import '../models/habit_checkin.dart';
import '../models/habit_goal.dart';
import '../models/habit_goal_rule.dart';
import '../models/habit_progress.dart';
import '../repositories/habit_repository.dart';
import '../../../utils/theme_color_tokens.dart';
import 'habit_format.dart';
import 'habit_quick_checkin_sheet.dart';

/// 单个习惯卡片：进度条 + 类型化操作按钮。
///
/// 操作完成后通过 [onChanged] 通知父级重新加载数据。
class HabitCard extends StatefulWidget {
  final HabitGoal goal;
  final HabitGoalRuleRevision rule;
  final HabitDayProgress dayProgress;

  /// 首页浅色背景模式。
  final bool isLight;

  /// 数据变化后通知父级刷新。
  final VoidCallback onChanged;

  /// 时长型习惯「开始专注」回调（由父级负责启动并跳转番茄钟）。
  final Future<void> Function(HabitGoal goal)? onStartFocus;

  /// 时长型习惯「查看记录」回调（默认由父级跳转详情页）。
  final VoidCallback? onViewRecords;

  /// 点击卡片主体（跳转详情）。
  final VoidCallback? onTap;

  final String username;

  const HabitCard({
    super.key,
    required this.goal,
    required this.rule,
    required this.dayProgress,
    this.isLight = false,
    required this.onChanged,
    this.onStartFocus,
    this.onViewRecords,
    this.onTap,
    this.username = '',
  });

  @override
  State<HabitCard> createState() => _HabitCardState();
}

class _HabitCardState extends State<HabitCard> {
  bool _busy = false;

  ColorScheme get _colors => Theme.of(context).colorScheme;

  @override
  Widget build(BuildContext context) {
    final progress = widget.dayProgress.progress;
    final status = widget.dayProgress.status;
    final isDarkCard = !widget.isLight;

    final Color borderColor = widget.isLight
        ? Colors.white.withValues(alpha: 0.2)
        : _colors.outlineVariant.withValues(alpha: 0.5);

    return Container(
      decoration: BoxDecoration(
        color: isDarkCard
            ? _colors.surfaceContainerLow
            : Colors.white.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: borderColor),
        boxShadow: [
          if (widget.isLight)
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 10,
              offset: const Offset(0, 4),
            )
          else
            BoxShadow(
              color: _colors.shadow.withValues(alpha: 0.03),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: widget.onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeader(progress, status),
                if (widget.goal.sourceType != HabitSourceType.timeCheckIn &&
                    widget.goal.sourceType !=
                        HabitSourceType.recurringTodo) ...[
                  const SizedBox(height: 10),
                  _buildProgressBar(progress),
                ],
                const SizedBox(height: 10),
                _buildActions(progress, status),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── 头部：图标 + 名称 + 状态 ────────────────────────
  Widget _buildHeader(HabitProgress progress, HabitDayStatus status) {
    final textColor = widget.isLight ? Colors.white : _colors.onSurface;
    final subColor = widget.isLight
        ? Colors.white.withValues(alpha: 0.7)
        : _colors.onSurfaceVariant;

    return Row(
      children: [
        Container(
          width: 38,
          height: 38,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: _statusColor(status).withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(widget.goal.icon.isNotEmpty ? widget.goal.icon : '🎯',
              style: const TextStyle(fontSize: 20)),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.goal.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: textColor,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                _subtitle(status, progress),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11.5, color: subColor),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        _buildStatusBadge(status),
      ],
    );
  }

  String _subtitle(HabitDayStatus status, HabitProgress progress) {
    switch (widget.goal.sourceType) {
      case HabitSourceType.recurringTodo:
        return HabitText.periodLabel(widget.rule);
      case HabitSourceType.pomodoroTag:
        return '${HabitText.periodLabel(widget.rule)} · '
            '${HabitText.durationProgress(progress)}';
      case HabitSourceType.quantityCheckIn:
        final unit = widget.rule.unit;
        return '${HabitText.periodLabel(widget.rule)} · '
            '${HabitText.amountProgress(progress, unit)}';
      case HabitSourceType.timeCheckIn:
        return '${HabitText.periodLabel(widget.rule)} · '
            '目标 ${HabitText.targetTime(widget.rule.targetTimeMinute)}';
    }
  }

  Color _statusColor(HabitDayStatus status) {
    if (widget.isLight) {
      switch (status) {
        case HabitDayStatus.met:
          return Colors.greenAccent;
        case HabitDayStatus.missed:
          return Colors.redAccent;
        case HabitDayStatus.inProgress:
          return Colors.amber;
        default:
          return Colors.white70;
      }
    }
    switch (status) {
      case HabitDayStatus.met:
        return _colors.cdtSuccess;
      case HabitDayStatus.missed:
        return _colors.error;
      case HabitDayStatus.inProgress:
        return _colors.cdtWarning;
      default:
        return _colors.outline;
    }
  }

  Widget _buildStatusBadge(HabitDayStatus status) {
    final color = _statusColor(status);
    final String text;
    switch (status) {
      case HabitDayStatus.met:
        text = '已完成';
      case HabitDayStatus.missed:
        text = '未完成';
      case HabitDayStatus.inProgress:
        text = '进行中';
      case HabitDayStatus.notPlanned:
        text = '今日无计划';
      case HabitDayStatus.skipped:
        text = '已跳过';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: widget.isLight ? 0.2 : 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w600,
          color: widget.isLight ? Colors.white : color,
        ),
      ),
    );
  }

  // ── 进度条 ──────────────────────────────────────────
  Widget _buildProgressBar(HabitProgress progress) {
    final status = widget.dayProgress.status;
    final barColor = _statusColor(status);
    final ratio = progress.completionRatio.clamp(0.0, 1.0);

    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: LinearProgressIndicator(
        value: ratio,
        minHeight: 6,
        backgroundColor: widget.isLight
            ? Colors.white.withValues(alpha: 0.2)
            : _colors.surfaceContainerHighest,
        valueColor: AlwaysStoppedAnimation(barColor),
      ),
    );
  }

  // ── 操作区 ──────────────────────────────────────────
  Widget _buildActions(HabitProgress progress, HabitDayStatus status) {
    switch (widget.goal.sourceType) {
      case HabitSourceType.recurringTodo:
        return _buildCompletionAction(progress);
      case HabitSourceType.pomodoroTag:
        return _buildDurationAction();
      case HabitSourceType.quantityCheckIn:
        return _buildQuantityAction(status);
      case HabitSourceType.timeCheckIn:
        return _buildTimeAction(progress);
    }
  }

  Widget _buildCompletionAction(HabitProgress progress) {
    final done = progress.goalMet;
    return Row(
      children: [
        Expanded(
          child: FilledButton(
            onPressed: done || _busy ? null : () => _toggleDone(progress),
            style: FilledButton.styleFrom(
              backgroundColor: done
                  ? (widget.isLight
                      ? Colors.white.withValues(alpha: 0.15)
                      : _colors.surfaceContainerHighest)
                  : (widget.isLight ? Colors.white.withValues(alpha: 0.2) : null),
              foregroundColor: done
                  ? (widget.isLight ? Colors.white70 : _colors.onSurfaceVariant)
                  : (widget.isLight ? Colors.white : null),
              padding: const EdgeInsets.symmetric(vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(done ? Icons.check_circle_rounded : Icons.check_rounded,
                    size: 17),
                const SizedBox(width: 6),
                Text(done ? '已完成' : '完成'),
              ],
            ),
          ),
        ),
        if (done) ...[
          const SizedBox(width: 8),
          OutlinedButton(
            onPressed: _busy ? null : () => _toggleDone(progress),
            style: OutlinedButton.styleFrom(
              foregroundColor: widget.isLight ? Colors.white : null,
              side: widget.isLight ? const BorderSide(color: Colors.white70) : null,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text('撤销'),
          ),
        ],
      ],
    );
  }

  Future<void> _toggleDone(HabitProgress progress) async {
    setState(() => _busy = true);
    try {
      await HabitRepository.setCompletion(
        goal: widget.goal,
        logicalDate: DateTime.now(),
        done: !progress.goalMet,
        username: widget.username,
      );
      widget.onChanged();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _buildDurationAction() {
    return Row(
      children: [
        Expanded(
          child: FilledButton.tonal(
            onPressed: _busy || widget.onStartFocus == null
                ? null
                : () async {
                    setState(() => _busy = true);
                    try {
                      await widget.onStartFocus?.call(widget.goal);
                    } finally {
                      if (mounted) setState(() => _busy = false);
                    }
                  },
            style: FilledButton.styleFrom(
              backgroundColor: widget.isLight ? Colors.white.withValues(alpha: 0.2) : null,
              foregroundColor: widget.isLight ? Colors.white : null,
              padding: const EdgeInsets.symmetric(vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.play_arrow_rounded, size: 18),
                SizedBox(width: 6),
                Text('开始专注'),
              ],
            ),
          ),
        ),
        if (widget.onViewRecords != null) ...[
          const SizedBox(width: 8),
          OutlinedButton(
            onPressed: widget.onViewRecords,
            style: OutlinedButton.styleFrom(
              foregroundColor: widget.isLight ? Colors.white : null,
              side: widget.isLight ? const BorderSide(color: Colors.white70) : null,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text('查看记录'),
          ),
        ],
      ],
    );
  }

  Widget _buildQuantityAction(HabitDayStatus status) {
    final quickValues = widget.rule.quickValues.isNotEmpty
        ? widget.rule.quickValues
        : const [1];
    final unit = widget.rule.unit;

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        ...quickValues.take(3).map((v) => _quickValueChip(v.toDouble(), unit)),
        TextButton(
          onPressed: _busy ? null : () => _openQuantityCustomDialog(),
          style: TextButton.styleFrom(
            foregroundColor: widget.isLight ? Colors.white : null,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            minimumSize: const Size(0, 36),
          ),
          child: const Text('自定义'),
        ),
      ],
    );
  }

  Widget _quickValueChip(double value, String unit) {
    final text = value == value.roundToDouble()
        ? value.round().toString()
        : value.toString();
    return FilledButton.tonal(
      onPressed: _busy ? null : () => _quickCheckIn(value, text),
      style: FilledButton.styleFrom(
        backgroundColor: widget.isLight ? Colors.white.withValues(alpha: 0.2) : _colors.secondaryContainer,
        foregroundColor: widget.isLight ? Colors.white : _colors.onSecondaryContainer,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        minimumSize: const Size(0, 36),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
      ),
      child: Text(unit.isNotEmpty ? '$text $unit' : text),
    );
  }

  Future<void> _quickCheckIn(double value, String label) async {
    setState(() => _busy = true);
    try {
      final checkIn = await HabitRepository.addCheckIn(
        goal: widget.goal,
        rule: widget.rule,
        localOccurredAt: DateTime.now(),
        value: value,
      );
      widget.onChanged();
      _showUndoSnackBar('已记录 $label${widget.rule.unit}', checkIn);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openQuantityCustomDialog() async {
    await HabitQuickCheckInSheet.show(
      context: context,
      goal: widget.goal,
      rule: widget.rule,
      onChanged: widget.onChanged,
    );
  }

  Widget _buildTimeAction(HabitProgress progress) {
    final actual = progress.firstRecordAt;

    return Row(
      children: [
        if (actual != null) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: _colors.cdtSuccess.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '${HabitText.timeOfDay(actual)} · '
              '${HabitText.timePointStatus(widget.rule, progress)}',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: _colors.cdtSuccess,
              ),
            ),
          ),
          const SizedBox(width: 8),
        ],
        Expanded(
          child: FilledButton.tonal(
            onPressed: _busy ? null : () => _openTimePicker(actual),
            style: FilledButton.styleFrom(
              backgroundColor: widget.isLight ? Colors.white.withValues(alpha: 0.2) : null,
              foregroundColor: widget.isLight ? Colors.white : null,
              padding: const EdgeInsets.symmetric(vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: Text(actual == null ? '打卡' : '重新打卡'),
          ),
        ),
      ],
    );
  }

  Future<void> _openTimePicker(DateTime? existing) async {
    final now = DateTime.now();
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(existing ?? now),
      helpText: '记录「${widget.goal.name}」的时间',
    );
    if (picked == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final occurred =
          DateTime(now.year, now.month, now.day, picked.hour, picked.minute);
      final checkIn = await HabitRepository.addCheckIn(
        goal: widget.goal,
        rule: widget.rule,
        localOccurredAt: occurred,
        source: HabitCheckInSource.manual,
      );
      widget.onChanged();
      _showUndoSnackBar(
        '已记录 ${HabitText.timeOfDay(occurred)}',
        checkIn,
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showUndoSnackBar(String message, HabitCheckIn checkIn) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          duration: const Duration(seconds: 4),
          action: SnackBarAction(
            label: '撤销',
            onPressed: () async {
              await HabitRepository.deleteCheckIn(checkIn);
              widget.onChanged();
            },
          ),
        ),
      );
  }
}
