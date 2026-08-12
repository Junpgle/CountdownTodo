import 'package:flutter/material.dart';

import '../models/habit_checkin.dart';
import '../models/habit_goal.dart';
import '../models/habit_goal_rule.dart';
import '../models/habit_progress.dart';
import '../repositories/habit_repository.dart';
import '../services/habit_adaptation_service.dart';
import '../services/habit_sleep_coaching_service.dart';
import '../../../utils/theme_color_tokens.dart';
import '../../../utils/app_platform.dart';
import 'habit_format.dart';
import 'habit_quick_checkin_sheet.dart';

/// 单个习惯卡片：进度条 + 类型化操作按钮。
///
/// 操作完成后通过 [onChanged] 通知父级重新加载数据。
class HabitCard extends StatefulWidget {
  final HabitGoal goal;
  final HabitGoalRuleRevision rule;
  final HabitDayProgress dayProgress;

  /// 数据变化后通知父级刷新。
  final VoidCallback onChanged;

  /// 时长型习惯「开始专注」回调（由父级负责启动并跳转番茄钟）。
  final Future<void> Function(HabitGoal goal)? onStartFocus;

  /// 时长型习惯「查看记录」回调（默认由父级跳转详情页）。
  final VoidCallback? onViewRecords;

  /// 点击卡片主体（跳转详情）。
  final VoidCallback? onTap;

  /// 容器变换动画的起点。为空时保持普通卡片渲染。
  final GlobalKey? animationKey;

  /// 首页卡片使用更紧凑的间距；详情页默认保留完整尺寸。
  final bool compact;

  final String username;

  /// 睡眠作息渐进训练当前阶段的目标；为空时使用规则最终目标。
  final HabitSleepCoachingMetric? sleepCoachingMetric;

  const HabitCard({
    super.key,
    required this.goal,
    required this.rule,
    required this.dayProgress,
    required this.onChanged,
    this.onStartFocus,
    this.onViewRecords,
    this.onTap,
    this.animationKey,
    this.compact = false,
    this.username = '',
    this.sleepCoachingMetric,
  });

  @override
  State<HabitCard> createState() => _HabitCardState();
}

class _HabitCardState extends State<HabitCard> {
  bool _busy = false;
  bool _isPressed = false;

  ColorScheme get _colors => Theme.of(context).colorScheme;

  @override
  Widget build(BuildContext context) {
    final progress = widget.dayProgress.progress;
    final status = widget.dayProgress.status;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return GestureDetector(
      onTapDown: (_) {
        if (widget.onTap != null) setState(() => _isPressed = true);
      },
      onTapUp: (_) {
        if (widget.onTap != null) {
          setState(() => _isPressed = false);
          widget.onTap!();
        }
      },
      onTapCancel: () {
        if (widget.onTap != null) setState(() => _isPressed = false);
      },
      child: AnimatedScale(
        scale: _isPressed ? 0.96 : 1.0,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        child: Container(
          key: widget.animationKey,
          margin: EdgeInsets.symmetric(vertical: widget.compact ? 2 : 6),
          decoration: BoxDecoration(
            color: _colors.surfaceContainerLow,
            borderRadius: BorderRadius.circular(widget.compact ? 18 : 24),
            border: Border.all(
              color: _colors.onSurface.withValues(alpha: isDark ? 0.1 : 0.05),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: _colors.shadow.withValues(alpha: 0.04),
                blurRadius: AppPlatform.isAndroid
                    ? (widget.compact ? 8 : 12)
                    : (widget.compact ? 16 : 24),
                offset: AppPlatform.isAndroid
                    ? const Offset(0, 4)
                    : (widget.compact
                        ? const Offset(0, 4)
                        : const Offset(0, 8)),
              ),
            ],
          ),
          child: Padding(
            padding: widget.compact
                ? const EdgeInsets.fromLTRB(12, 12, 12, 10)
                : const EdgeInsets.fromLTRB(16, 18, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeader(progress, status),
                if (widget.goal.sourceType != HabitSourceType.timeCheckIn &&
                    widget.goal.sourceType !=
                        HabitSourceType.recurringTodo) ...[
                  SizedBox(height: widget.compact ? 8 : 14),
                  _buildProgressBar(progress, status),
                ],
                SizedBox(height: widget.compact ? 8 : 12),
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
    final textColor = _colors.onSurface;
    final subColor = _colors.onSurfaceVariant;
    final statusColor = _statusColor(status);

    return Row(
      children: [
        Container(
          width: widget.compact ? 32 : 40,
          height: widget.compact ? 32 : 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: statusColor.withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child: Text(
            widget.goal.icon.isNotEmpty ? widget.goal.icon : '🎯',
            style: TextStyle(fontSize: widget.compact ? 18 : 22),
          ),
        ),
        SizedBox(width: widget.compact ? 8 : 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.goal.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: widget.compact ? 14 : 16,
                  fontWeight: FontWeight.w700,
                  color: textColor,
                ),
              ),
              const SizedBox(height: 1),
              Text(
                _subtitle(status, progress),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: widget.compact ? 11 : 12,
                  color: subColor,
                ),
              ),
            ],
          ),
        ),
        SizedBox(width: widget.compact ? 6 : 8),
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
      case HabitSourceType.durationCheckIn:
        final coachingTarget = _sleepCoachingTargetLabel;
        return '${HabitText.periodLabel(widget.rule)} · '
            '${coachingTarget == null ? HabitText.durationProgressForGoal(widget.goal, progress) : '${HabitText.formatDuration(progress.currentValue.round())} · '
                '本期目标 $coachingTarget'}';
      case HabitSourceType.quantityCheckIn:
        final unit = widget.rule.unit;
        return '${HabitText.periodLabel(widget.rule)} · '
            '${HabitText.amountProgress(progress, unit)}';
      case HabitSourceType.timeCheckIn:
        final coachingTarget = _sleepCoachingTargetLabel;
        return '${HabitText.periodLabel(widget.rule)} · '
            '目标 ${coachingTarget ?? HabitText.targetTime(widget.rule.targetTimeMinute)}';
    }
  }

  String? get _sleepCoachingTargetLabel {
    final metric = widget.sleepCoachingMetric;
    if (metric == null || !metric.isAvailable) return null;
    switch (metric.kind) {
      case HabitAdaptationKind.earlySleep:
      case HabitAdaptationKind.earlyWake:
        return HabitText.targetTime(metric.stageTarget);
      case HabitAdaptationKind.sleepDuration:
        return HabitText.formatDuration(metric.stageTarget * 60);
      default:
        return null;
    }
  }

  Color _statusColor(HabitDayStatus status) {
    switch (status) {
      case HabitDayStatus.met:
        return _colors.cdtSuccess;
      case HabitDayStatus.missed:
        return _colors.error;
      case HabitDayStatus.inProgress:
        return _colors.primary;
      default:
        return _colors.outlineVariant;
    }
  }

  Widget _buildStatusBadge(HabitDayStatus status) {
    final color = _statusColor(status);
    final String text;
    switch (status) {
      case HabitDayStatus.met:
        text = '已完成';
        break;
      case HabitDayStatus.missed:
        text = '未完成';
        break;
      case HabitDayStatus.inProgress:
        text = '进行中';
        break;
      case HabitDayStatus.notPlanned:
        text = '今日无计划';
        break;
      case HabitDayStatus.skipped:
        text = '已跳过';
        break;
    }
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: widget.compact ? 6 : 8,
        vertical: widget.compact ? 3 : 4,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: widget.compact ? 10 : 11,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }

  // ── 进度条 ──────────────────────────────────────────
  Widget _buildProgressBar(HabitProgress progress, HabitDayStatus status) {
    final barColor = _statusColor(status);
    final coaching = widget.sleepCoachingMetric;
    final ratio = coaching?.kind == HabitAdaptationKind.sleepDuration &&
            coaching!.stageTarget > 0
        ? (progress.currentValue / (coaching.stageTarget * 60)).clamp(0.0, 1.0)
        : progress.completionRatio.clamp(0.0, 1.0);

    return ClipRRect(
      borderRadius: BorderRadius.circular(2),
      child: LinearProgressIndicator(
        value: ratio,
        minHeight: 4,
        backgroundColor: _colors.surfaceContainerHighest,
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
      case HabitSourceType.durationCheckIn:
        return _buildSleepDurationAction();
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
          child: FilledButton.tonal(
            onPressed: done || _busy ? null : () => _toggleDone(progress),
            style: FilledButton.styleFrom(
              padding: EdgeInsets.symmetric(
                vertical: widget.compact ? 8 : 12,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(widget.compact ? 10 : 12),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(done ? Icons.check_circle_rounded : Icons.check_rounded,
                    size: widget.compact ? 16 : 18),
                SizedBox(width: widget.compact ? 4 : 6),
                Text(done ? '已完成' : '完成'),
              ],
            ),
          ),
        ),
        if (done) ...[
          const SizedBox(width: 8),
          TextButton(
            onPressed: _busy ? null : () => _toggleDone(progress),
            style: TextButton.styleFrom(
              padding: EdgeInsets.symmetric(
                horizontal: widget.compact ? 10 : 16,
                vertical: widget.compact ? 8 : 12,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(widget.compact ? 10 : 12),
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
              padding: EdgeInsets.symmetric(
                vertical: widget.compact ? 8 : 12,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(widget.compact ? 10 : 12),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.play_arrow_rounded, size: widget.compact ? 16 : 18),
                SizedBox(width: widget.compact ? 4 : 6),
                Text('开始专注'),
              ],
            ),
          ),
        ),
        if (widget.onViewRecords != null) ...[
          const SizedBox(width: 8),
          TextButton(
            onPressed: widget.onViewRecords,
            style: TextButton.styleFrom(
              padding: EdgeInsets.symmetric(
                horizontal: widget.compact ? 10 : 16,
                vertical: widget.compact ? 8 : 12,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(widget.compact ? 10 : 12),
              ),
            ),
            child: const Text('查看记录'),
          ),
        ],
      ],
    );
  }

  Widget _buildSleepDurationAction() {
    return Row(
      children: [
        Expanded(
          child: FilledButton.tonal(
            onPressed: _busy
                ? null
                : () async {
                    await HabitQuickCheckInSheet.show(
                      context: context,
                      goal: widget.goal,
                      rule: widget.rule,
                      logicalDate: widget.dayProgress.logicalDate,
                      onChanged: widget.onChanged,
                    );
                  },
            style: FilledButton.styleFrom(
              padding: EdgeInsets.symmetric(
                vertical: widget.compact ? 8 : 12,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(widget.compact ? 10 : 12),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.edit_calendar_rounded,
                    size: widget.compact ? 16 : 18),
                SizedBox(width: widget.compact ? 4 : 6),
                Text('手动修正睡眠时长'),
              ],
            ),
          ),
        ),
        if (widget.onViewRecords != null) ...[
          const SizedBox(width: 8),
          TextButton(
            onPressed: widget.onViewRecords,
            style: TextButton.styleFrom(
              minimumSize: Size(0, widget.compact ? 36 : 40),
              padding: EdgeInsets.symmetric(
                horizontal: widget.compact ? 8 : 12,
              ),
            ),
            child: const Text('历史'),
          ),
        ],
      ],
    );
  }

  Widget _buildQuantityAction(HabitDayStatus status) {
    final adaptation = HabitAdaptationService.forHabit(
      widget.goal,
    );
    final quickValues = widget.rule.quickValues.isNotEmpty
        ? widget.rule.quickValues
        : adaptation?.suggestedQuickValues ?? const [1];
    final unit = widget.rule.unit;

    return Wrap(
      spacing: widget.compact ? 6 : 8,
      runSpacing: widget.compact ? 4 : 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        ...quickValues.take(3).map(
              (v) => _quickValueChip(
                v.toDouble(),
                unit,
                label: adaptation?.quickLabel(v, unit: unit),
              ),
            ),
        TextButton(
          onPressed: _busy ? null : () => _openQuantityCustomDialog(),
          style: TextButton.styleFrom(
            padding: EdgeInsets.symmetric(
              horizontal: widget.compact ? 10 : 12,
              vertical: widget.compact ? 6 : 8,
            ),
            minimumSize: Size(0, widget.compact ? 32 : 36),
          ),
          child: const Text('自定义'),
        ),
      ],
    );
  }

  Widget _quickValueChip(double value, String unit, {String? label}) {
    final text = value == value.roundToDouble()
        ? value.round().toString()
        : value.toString();
    return FilledButton.tonal(
      onPressed: _busy ? null : () => _quickCheckIn(value, text),
      style: FilledButton.styleFrom(
        padding: EdgeInsets.symmetric(
          horizontal: widget.compact ? 12 : 16,
          vertical: widget.compact ? 6 : 8,
        ),
        minimumSize: Size(0, widget.compact ? 32 : 36),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(widget.compact ? 10 : 12),
        ),
      ),
      child: Text(label ?? (unit.isNotEmpty ? '$text $unit' : text)),
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
            padding: EdgeInsets.symmetric(
              horizontal: widget.compact ? 8 : 10,
              vertical: widget.compact ? 4 : 6,
            ),
            decoration: BoxDecoration(
              color: _colors.cdtSuccess.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '${HabitText.timeOfDay(actual)} · '
              '${HabitText.timePointStatus(widget.rule, progress)}',
              style: TextStyle(
                fontSize: widget.compact ? 11 : 12,
                fontWeight: FontWeight.w600,
                color: _colors.cdtSuccess,
              ),
            ),
          ),
          SizedBox(width: widget.compact ? 6 : 8),
        ],
        Expanded(
          child: FilledButton.tonal(
            onPressed: _busy ? null : () => _openTimePicker(actual),
            style: FilledButton.styleFrom(
              padding: EdgeInsets.symmetric(
                vertical: widget.compact ? 8 : 12,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(widget.compact ? 10 : 12),
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
    final wasReplacement = checkIn.replacedPrevious;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            wasReplacement ? '$message（已覆盖上一条记录）' : message,
          ),
          duration: const Duration(seconds: 4),
          action: wasReplacement
              ? null
              : SnackBarAction(
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
