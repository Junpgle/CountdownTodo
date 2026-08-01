import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/habit_goal.dart';
import '../models/habit_goal_rule.dart';
import '../repositories/habit_repository.dart';
import 'habit_format.dart';

/// 快捷打卡底部弹窗（设计文档第十五节 `habit_quick_checkin_sheet.dart`）。
///
/// 按习惯类型提供对应打卡入口：
/// - 数量型：快捷数值 + 自定义数量 + 备注；
/// - 时间点型：选择实际时间（默认当前时间）；
/// - 完成型：一键完成；
/// - 时长型：提示开始专注。
class HabitQuickCheckInSheet {
  /// 弹出快捷打卡弹窗。成功打卡后调用 [onChanged]。
  static Future<void> show({
    required BuildContext context,
    required HabitGoal goal,
    required HabitGoalRuleRevision rule,
    required VoidCallback onChanged,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => _QuickCheckInSheet(
        goal: goal,
        rule: rule,
        onChanged: onChanged,
      ),
    );
  }
}

class _QuickCheckInSheet extends StatefulWidget {
  final HabitGoal goal;
  final HabitGoalRuleRevision rule;
  final VoidCallback onChanged;

  const _QuickCheckInSheet({
    required this.goal,
    required this.rule,
    required this.onChanged,
  });

  @override
  State<_QuickCheckInSheet> createState() => _QuickCheckInSheetState();
}

class _QuickCheckInSheetState extends State<_QuickCheckInSheet> {
  final _controller = TextEditingController();
  final _noteController = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _controller.dispose();
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + bottomInset),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  widget.goal.icon.isNotEmpty ? widget.goal.icon : '🎯',
                  style: const TextStyle(fontSize: 20),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.goal.name,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            switch (widget.goal.sourceType) {
              HabitSourceType.quantityCheckIn => _buildQuantity(colorScheme),
              HabitSourceType.timeCheckIn => _buildTimePoint(colorScheme),
              HabitSourceType.recurringTodo => _buildCompletion(colorScheme),
              HabitSourceType.pomodoroTag => _buildFocusHint(colorScheme),
            },
          ],
        ),
      ),
    );
  }

  // ── 数量型 ──────────────────────────────────────────
  Widget _buildQuantity(ColorScheme colorScheme) {
    final quickValues = widget.rule.quickValues.isNotEmpty
        ? widget.rule.quickValues
        : const [1];
    final unit = widget.rule.unit;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: quickValues
              .map((v) => _valueChip(v.toDouble(), unit, colorScheme))
              .toList(),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[\d.]')),
          ],
          decoration: InputDecoration(
            labelText: unit.isNotEmpty ? '数量（$unit）' : '数量',
            suffixText: unit,
            border: const OutlineInputBorder(),
            isDense: true,
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _noteController,
          decoration: const InputDecoration(
            labelText: '备注（可选）',
            border: OutlineInputBorder(),
            isDense: true,
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: _busy ? null : () => _submitQuantity(),
            child: const Text('记录'),
          ),
        ),
      ],
    );
  }

  Widget _valueChip(double value, String unit, ColorScheme colorScheme) {
    final text = value == value.roundToDouble()
        ? value.round().toString()
        : value.toString();
    return FilledButton.tonal(
      onPressed: _busy ? null : () => _submit(value),
      style: FilledButton.styleFrom(
        backgroundColor: colorScheme.secondaryContainer,
        foregroundColor: colorScheme.onSecondaryContainer,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
      ),
      child: Text(unit.isNotEmpty ? '$text $unit' : text),
    );
  }

  Future<void> _submitQuantity() async {
    final v = double.tryParse(_controller.text.trim());
    if (v == null || v <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请填写有效的数量')),
      );
      return;
    }
    await _submit(v);
  }

  Future<void> _submit(double value) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final checkIn = await HabitRepository.addCheckIn(
        goal: widget.goal,
        rule: widget.rule,
        localOccurredAt: DateTime.now(),
        value: value,
        note: _noteController.text.trim().isEmpty
            ? null
            : _noteController.text.trim(),
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      widget.onChanged();
      final text = value == value.roundToDouble()
          ? value.round().toString()
          : value.toString();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              '已记录 $text${widget.rule.unit}${widget.rule.unit.isNotEmpty ? ' ' : ''}'
              '${widget.goal.name}'),
          action: SnackBarAction(
            label: '撤销',
            onPressed: () => HabitRepository.deleteCheckIn(checkIn),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ── 时间点型 ────────────────────────────────────────
  Widget _buildTimePoint(ColorScheme colorScheme) {
    final now = DateTime.now();
    var time = TimeOfDay(hour: now.hour, minute: now.minute);
    return StatefulBuilder(
      builder: (context, setSheetState) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '实际时间',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          InkWell(
            onTap: _busy
                ? null
                : () async {
                    final picked = await showTimePicker(
                      context: context,
                      initialTime: time,
                    );
                    if (picked != null) setSheetState(() => time = picked);
                  },
            borderRadius: BorderRadius.circular(12),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: colorScheme.outlineVariant),
              ),
              child: Row(
                children: [
                  Icon(Icons.schedule_rounded,
                      size: 18, color: colorScheme.primary),
                  const SizedBox(width: 10),
                  Text(
                    HabitText.timeOfDay(
                      DateTime(0)
                          .add(Duration(minutes: time.hour * 60 + time.minute)),
                    ),
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '目标 ${HabitText.targetTime(widget.rule.targetTimeMinute)}',
                    style: TextStyle(
                      fontSize: 12,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _busy
                  ? null
                  : () async {
                      if (_busy) return;
                      setState(() => _busy = true);
                      try {
                        final occurred = DateTime(now.year, now.month, now.day,
                            time.hour, time.minute);
                        final checkIn = await HabitRepository.addCheckIn(
                          goal: widget.goal,
                          rule: widget.rule,
                          localOccurredAt: occurred,
                          note: _noteController.text.trim().isEmpty
                              ? null
                              : _noteController.text.trim(),
                        );
                        if (!context.mounted) return;
                        Navigator.of(context).pop();
                        widget.onChanged();
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('已记录 ${widget.goal.name}'),
                            action: SnackBarAction(
                              label: '撤销',
                              onPressed: () =>
                                  HabitRepository.deleteCheckIn(checkIn),
                            ),
                          ),
                        );
                      } finally {
                        if (mounted) setState(() => _busy = false);
                      }
                    },
              child: const Text('打卡'),
            ),
          ),
        ],
      ),
    );
  }

  // ── 完成型 ──────────────────────────────────────────
  Widget _buildCompletion(ColorScheme colorScheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '在待办中完成一次即为达标，也可在此直接标记完成。',
          style: TextStyle(
            fontSize: 13,
            height: 1.5,
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: _busy
                ? null
                : () async {
                    if (_busy) return;
                    setState(() => _busy = true);
                    try {
                      await HabitRepository.setCompletion(
                        goal: widget.goal,
                        logicalDate: DateTime.now(),
                        done: true,
                      );
                      if (!mounted) return;
                      Navigator.of(context).pop();
                      widget.onChanged();
                    } finally {
                      if (mounted) setState(() => _busy = false);
                    }
                  },
            child: const Text('标记完成'),
          ),
        ),
      ],
    );
  }

  // ── 时长型 ──────────────────────────────────────────
  Widget _buildFocusHint(ColorScheme colorScheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '时长型习惯通过在专注中累计时长达标，回到卡片点击「开始专注」即可。',
          style: TextStyle(
            fontSize: 13,
            height: 1.5,
            color: colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
