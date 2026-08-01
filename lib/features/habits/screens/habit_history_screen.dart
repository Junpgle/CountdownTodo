import 'package:flutter/material.dart';

import '../models/habit_checkin.dart';
import '../models/habit_goal.dart';
import '../models/habit_goal_rule.dart';
import '../repositories/habit_repository.dart';
import '../widgets/habit_format.dart';

/// 习惯历史：打卡记录 + 目标修改历史。
///
/// 对应设计文档第十五节独立的 `habit_history_screen.dart`，
/// 具体记录保留在详情页之外的历史页，避免主时间轴信息过多。
class HabitHistoryScreen extends StatefulWidget {
  final HabitGoal goal;
  final String username;

  const HabitHistoryScreen({
    super.key,
    required this.goal,
    this.username = '',
  });

  @override
  State<HabitHistoryScreen> createState() => _HabitHistoryScreenState();
}

class _HabitHistoryScreenState extends State<HabitHistoryScreen> {
  bool _loading = true;
  List<HabitCheckIn> _checkIns = [];
  List<HabitGoalRuleRevision> _rules = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final checkIns = await HabitRepository.getCheckIns(
      habitUuid: widget.goal.uuid,
    );
    final rules = await HabitRepository.getRules(habitUuid: widget.goal.uuid);
    if (!mounted) return;
    setState(() {
      _checkIns = checkIns.where((c) => !c.isDeleted).toList()
        ..sort((a, b) => b.logicalDate.compareTo(a.logicalDate));
      _rules = rules.where((r) => !r.isDeleted).toList()
        ..sort((a, b) =>
            (b.effectiveFromDate ?? '').compareTo(a.effectiveFromDate ?? ''));
      _loading = false;
    });
  }

  Future<void> _deleteCheckIn(HabitCheckIn checkIn) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除打卡'),
        content: const Text('确定删除这条打卡记录吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await HabitRepository.deleteCheckIn(checkIn);
    _loadData();
  }

  HabitGoalRuleRevision? _ruleFor(String? uuid) {
    if (uuid == null) return null;
    for (final rule in _rules) {
      if (rule.uuid == uuid) return rule;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.goal.name} · 历史'),
        centerTitle: false,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 840),
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                  children: [
                    _buildCheckInSection(colorScheme),
                    const SizedBox(height: 24),
                    _buildRuleHistorySection(colorScheme),
                  ],
                ),
              ),
            ),
    );
  }

  // ── 打卡记录 ────────────────────────────────────────
  Widget _buildCheckInSection(ColorScheme colorScheme) {
    final grouped = <String, List<HabitCheckIn>>{};
    for (final checkIn in _checkIns) {
      grouped.putIfAbsent(checkIn.logicalDate, () => []).add(checkIn);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              '打卡记录',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: colorScheme.onSurface,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '共 ${_checkIns.length} 条',
              style: TextStyle(
                fontSize: 12,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (_checkIns.isEmpty) _emptyBox(colorScheme, '暂无打卡记录'),
        ...grouped.entries.map((entry) => _dayGroup(colorScheme, entry)),
      ],
    );
  }

  Widget _dayGroup(
    ColorScheme colorScheme,
    MapEntry<String, List<HabitCheckIn>> entry,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 4),
          child: Text(
            _dateLabel(entry.key),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: colorScheme.primary,
            ),
          ),
        ),
        ...entry.value.map((c) => _checkInRow(colorScheme, c)),
      ],
    );
  }

  Widget _checkInRow(ColorScheme colorScheme, HabitCheckIn checkIn) {
    final local = checkIn.localOccurredAt;
    final rule = _ruleFor(checkIn.ruleRevisionUuid);
    final unit = rule?.unit ?? '';
    final valueText = switch (widget.goal.sourceType) {
      HabitSourceType.quantityCheckIn =>
        '+${_trimNumber(checkIn.value)}${unit.isNotEmpty ? ' $unit' : ''}',
      HabitSourceType.timeCheckIn => '打卡 ${HabitText.timeOfDay(local)}',
      HabitSourceType.recurringTodo ||
      HabitSourceType.pomodoroTag =>
        HabitText.timeOfDay(local),
    };

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(
            HabitSourceType.timeCheckIn == widget.goal.sourceType
                ? Icons.schedule_rounded
                : Icons.add_circle_outline_rounded,
            size: 18,
            color: colorScheme.primary,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  valueText,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurface,
                  ),
                ),
                if (checkIn.note != null && checkIn.note!.isNotEmpty)
                  Text(
                    checkIn.note!,
                    style: TextStyle(
                      fontSize: 12,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
          Text(
            HabitText.timeOfDay(local),
            style: TextStyle(
              fontSize: 12,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          IconButton(
            tooltip: '删除',
            onPressed: () => _deleteCheckIn(checkIn),
            icon: Icon(
              Icons.delete_outline_rounded,
              size: 18,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  // ── 目标修改历史 ────────────────────────────────────
  Widget _buildRuleHistorySection(ColorScheme colorScheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '目标修改历史',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 10),
        if (_rules.isEmpty) _emptyBox(colorScheme, '暂无目标修改记录'),
        ..._rules.map((r) => _ruleRow(colorScheme, r)),
      ],
    );
  }

  Widget _ruleRow(
    ColorScheme colorScheme,
    HabitGoalRuleRevision rule,
  ) {
    final from = rule.effectiveFromDate ?? '';
    final to = rule.effectiveToDate ?? '至今';
    final targetText = switch (widget.goal.sourceType) {
      HabitSourceType.quantityCheckIn => '${_trimNumber(rule.targetValue)}'
          '${rule.unit.isNotEmpty ? ' ${rule.unit}' : ''}',
      HabitSourceType.pomodoroTag =>
        HabitText.formatDuration(rule.targetValue.round()),
      HabitSourceType.timeCheckIn =>
        HabitText.targetTime(rule.targetTimeMinute),
      HabitSourceType.recurringTodo => '完成一次',
    };

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(
            Icons.history_rounded,
            size: 18,
            color: colorScheme.primary,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  targetText,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurface,
                  ),
                ),
                Text(
                  '${HabitText.periodLabel(rule)} · $from 至 $to',
                  style: TextStyle(
                    fontSize: 12,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyBox(ColorScheme colorScheme, String text) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 20),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant),
      ),
    );
  }

  String _dateLabel(String key) {
    final parts = key.split('-');
    if (parts.length != 3) return key;
    final date = DateTime(
      int.parse(parts[0]),
      int.parse(parts[1]),
      int.parse(parts[2]),
    );
    const weekdays = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
    return '${date.month}月${date.day}日 ${weekdays[date.weekday - 1]}';
  }

  static String _trimNumber(double value) {
    if (value == value.roundToDouble()) return value.round().toString();
    return value.toStringAsFixed(1);
  }
}
