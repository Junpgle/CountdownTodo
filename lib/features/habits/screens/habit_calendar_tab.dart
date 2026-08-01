import 'package:flutter/material.dart';

import '../models/habit_goal.dart';
import '../models/habit_goal_rule.dart';
import '../models/habit_progress.dart';
import '../repositories/habit_repository.dart';
import '../services/habit_progress_calculator.dart';
import '../services/habit_rule_resolver.dart';
import '../widgets/habit_format.dart';

/// 习惯中心「日历」标签页：月历 + 选中日习惯明细。
class HabitCalendarTab extends StatefulWidget {
  final String username;

  /// 数据变化后自增，触发重新加载。
  final int reloadTick;

  const HabitCalendarTab({
    super.key,
    required this.username,
    this.reloadTick = 0,
  });

  @override
  State<HabitCalendarTab> createState() => _HabitCalendarTabState();
}

class _HabitCalendarTabState extends State<HabitCalendarTab> {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  DateTime _selectedDay = DateTime.now();
  List<HabitGoal> _goals = [];
  Map<String, List<HabitGoalRuleRevision>> _rulesByHabit = {};
  Map<String, List<HabitDayProgress>> _daysByHabit = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void didUpdateWidget(HabitCalendarTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.reloadTick != widget.reloadTick) {
      _loadData();
    }
  }

  Future<void> _loadData() async {
    if (!mounted) return;
    setState(() => _loading = true);
    final goals = await HabitRepository.getActiveGoals();
    final allRules = await HabitRepository.getRules();
    final rulesByHabit = <String, List<HabitGoalRuleRevision>>{};
    final daysByHabit = <String, List<HabitDayProgress>>{};

    final monthStart = DateTime(_month.year, _month.month, 1);
    final monthEnd = DateTime(_month.year, _month.month + 1, 0);

    for (final goal in goals) {
      final rules = allRules.where((r) => r.habitUuid == goal.uuid).toList()
        ..sort((a, b) =>
            (a.effectiveFromDate ?? '').compareTo(b.effectiveFromDate ?? ''));
      rulesByHabit[goal.uuid] = rules;
    }

    // 并行计算各习惯的月进度，避免 N 个习惯串行读库拖慢月视图。
    final futures = <Future<void>>[];
    for (final goal in goals) {
      final rules = rulesByHabit[goal.uuid] ?? const [];
      if (rules.isEmpty) continue;
      futures.add(() async {
        daysByHabit[goal.uuid] = await HabitProgressCalculator.computeRange(
          habit: goal,
          rules: rules,
          from: monthStart,
          to: monthEnd,
        );
      }());
    }
    await Future.wait(futures);

    if (mounted) {
      setState(() {
        _goals = goals;
        _rulesByHabit = rulesByHabit;
        _daysByHabit = daysByHabit;
        _loading = false;
      });
    }
  }

  void _changeMonth(int delta) {
    setState(() {
      _month = DateTime(_month.year, _month.month + delta, 1);
      // 选中日期超出新月份（如 1 月 31 日切到 2 月）时回落到当月最后一天。
      final daysInMonth = DateTime(_month.year, _month.month + 1, 0).day;
      if (_selectedDay.year != _month.year ||
          _selectedDay.month != _month.month) {
        _selectedDay = DateTime(
          _month.year,
          _month.month,
          _selectedDay.day.clamp(1, daysInMonth).toInt(),
        );
      }
    });
    _loadData();
  }

  // ── 每日聚合状态 ────────────────────────────────────
  _DayAggregate _aggregate(DateTime day) {
    // 未来日期不显示状态（设计文档 11.2）。
    final now = DateTime.now();
    if (day.isAfter(DateTime(now.year, now.month, now.day))) {
      return _DayAggregate.future;
    }
    final key = HabitRuleResolver.dayKey(day);
    int planned = 0;
    int met = 0;
    for (final goal in _goals) {
      final days = _daysByHabit[goal.uuid];
      if (days == null) continue;
      final match = days.where((d) {
        final k = HabitRuleResolver.dayKey(d.logicalDate);
        return k == key;
      });
      if (match.isEmpty) continue;
      final status = match.first.status;
      if (status == HabitDayStatus.notPlanned ||
          status == HabitDayStatus.skipped) {
        continue;
      }
      planned++;
      if (status == HabitDayStatus.met) met++;
    }
    if (planned == 0) return _DayAggregate.none;
    if (met == planned) return _DayAggregate.allMet;
    if (met == 0) return _DayAggregate.noneMet;
    return _DayAggregate.partial;
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          _buildMonthHeader(),
          const SizedBox(height: 12),
          _buildWeekdayHeader(),
          const SizedBox(height: 4),
          _buildDayGrid(),
          const SizedBox(height: 16),
          _buildLegend(),
          const SizedBox(height: 12),
          _buildSelectedDayDetail(),
        ],
      ),
    );
  }

  Widget _buildMonthHeader() {
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        IconButton(
          onPressed: () => _changeMonth(-1),
          icon: const Icon(Icons.chevron_left_rounded),
        ),
        Expanded(
          child: Text(
            '${_month.year} 年 ${_month.month} 月',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: colorScheme.onSurface,
            ),
          ),
        ),
        IconButton(
          onPressed: () => _changeMonth(1),
          icon: const Icon(Icons.chevron_right_rounded),
        ),
      ],
    );
  }

  Widget _buildWeekdayHeader() {
    const labels = ['一', '二', '三', '四', '五', '六', '日'];
    return Row(
      children: labels
          .map(
            (label) => Expanded(
              child: Center(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          )
          .toList(),
    );
  }

  Widget _buildDayGrid() {
    final colorScheme = Theme.of(context).colorScheme;
    final firstDay = DateTime(_month.year, _month.month, 1);
    final daysInMonth = DateTime(_month.year, _month.month + 1, 0).day;
    final leadingBlanks = firstDay.weekday - 1; // 周一开头

    final cells = <Widget>[];
    for (int i = 0; i < leadingBlanks; i++) {
      cells.add(const SizedBox.shrink());
    }

    final today = DateTime.now();
    for (int day = 1; day <= daysInMonth; day++) {
      final date = DateTime(_month.year, _month.month, day);
      final isToday = date.year == today.year &&
          date.month == today.month &&
          date.day == today.day;
      final isSelected = date.year == _selectedDay.year &&
          date.month == _selectedDay.month &&
          date.day == _selectedDay.day;
      final aggregate = _aggregate(date);

      Color bg = Colors.transparent;
      Color dot = colorScheme.outlineVariant;
      switch (aggregate) {
        case _DayAggregate.allMet:
          bg = colorScheme.tertiaryContainer;
          dot = colorScheme.tertiary;
        case _DayAggregate.partial:
          bg = colorScheme.tertiaryContainer.withValues(alpha: 0.5);
          dot = colorScheme.tertiary;
        case _DayAggregate.noneMet:
          bg = colorScheme.errorContainer.withValues(alpha: 0.45);
          dot = colorScheme.error;
        case _DayAggregate.none:
        case _DayAggregate.future:
          bg = Colors.transparent;
          dot = colorScheme.outlineVariant;
      }

      cells.add(
        GestureDetector(
          onTap: () => setState(() => _selectedDay = date),
          child: Container(
            margin: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: isSelected
                    ? colorScheme.primary
                    : isToday
                        ? colorScheme.primary.withValues(alpha: 0.4)
                        : Colors.transparent,
                width: isSelected ? 2 : 1,
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '$day',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: isToday ? FontWeight.w800 : FontWeight.w500,
                    color: isSelected
                        ? colorScheme.primary
                        : colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 2),
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: aggregate == _DayAggregate.none
                        ? Colors.transparent
                        : dot,
                    shape: BoxShape.circle,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return GridView.count(
      crossAxisCount: 7,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: 0.95,
      children: cells,
    );
  }

  Widget _buildLegend() {
    final colorScheme = Theme.of(context).colorScheme;
    Widget item(Color color, String label) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      );
    }

    return Wrap(
      spacing: 16,
      runSpacing: 8,
      children: [
        item(colorScheme.tertiary, '全部完成'),
        item(colorScheme.tertiary.withValues(alpha: 0.5), '部分完成'),
        item(colorScheme.error, '未完成'),
      ],
    );
  }

  // ── 选中日明细 ──────────────────────────────────────
  Widget _buildSelectedDayDetail() {
    final colorScheme = Theme.of(context).colorScheme;
    final dayLabel = '${_selectedDay.month} 月 ${_selectedDay.day} 日'
        ' · 周${'一二三四五六日'[_selectedDay.weekday - 1]}';
    final rows = <Widget>[];

    for (final goal in _goals) {
      final days = _daysByHabit[goal.uuid];
      if (days == null) continue;
      final key = HabitRuleResolver.dayKey(_selectedDay);
      final day = days.where(
        (d) => HabitRuleResolver.dayKey(d.logicalDate) == key,
      );
      if (day.isEmpty) continue;
      rows.add(_buildDayRow(goal, day.first));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          dayLabel,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 10),
        if (rows.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 20),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text(
              '这一天没有习惯计划',
              style: TextStyle(
                fontSize: 13,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          )
        else
          ...rows,
      ],
    );
  }

  Widget _buildDayRow(HabitGoal goal, HabitDayProgress day) {
    final colorScheme = Theme.of(context).colorScheme;
    final status = day.status;
    final (Color color, String label) = switch (status) {
      HabitDayStatus.met => (colorScheme.tertiary, '已完成'),
      HabitDayStatus.missed => (colorScheme.error, '未完成'),
      HabitDayStatus.inProgress => (colorScheme.secondary, '进行中'),
      HabitDayStatus.notPlanned => (colorScheme.outline, '无计划'),
      HabitDayStatus.skipped => (colorScheme.outline, '已跳过'),
    };

    final detail = _dayValueText(goal, day);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Text(goal.icon.isNotEmpty ? goal.icon : '🎯',
              style: const TextStyle(fontSize: 18)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  goal.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurface,
                  ),
                ),
                if (detail.isNotEmpty)
                  Text(
                    detail,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (goal.sourceType == HabitSourceType.recurringTodo)
            _buildMakeUpButton(goal, day)
          else
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _dayValueText(HabitGoal goal, HabitDayProgress day) {
    final progress = day.progress;
    switch (goal.sourceType) {
      case HabitSourceType.recurringTodo:
        return '';
      case HabitSourceType.pomodoroTag:
        return HabitText.durationProgress(progress);
      case HabitSourceType.quantityCheckIn:
        return HabitText.amountProgress(progress, _unitOf(goal));
      case HabitSourceType.timeCheckIn:
        final actual = progress.firstRecordAt;
        if (actual == null) return '未打卡';
        return '${HabitText.timeOfDay(actual)} · '
            '${HabitText.timePointStatus(_ruleOf(goal), progress)}';
    }
  }

  String _unitOf(HabitGoal goal) {
    final rules = _rulesByHabit[goal.uuid];
    if (rules == null || rules.isEmpty) return '';
    final rule = HabitRuleResolver.effectiveRule(rules, _selectedDay);
    return rule?.unit ?? '';
  }

  HabitGoalRuleRevision _ruleOf(HabitGoal goal) {
    final rules = _rulesByHabit[goal.uuid] ?? const [];
    return HabitRuleResolver.effectiveRule(rules, _selectedDay) ??
        HabitGoalRuleRevision(
          habitUuid: goal.uuid,
          effectiveFromDate: '',
          periodType: HabitPeriodType.daily,
        );
  }

  /// 完成型习惯：历史日期补卡 / 撤销。
  Widget _buildMakeUpButton(HabitGoal goal, HabitDayProgress day) {
    final colorScheme = Theme.of(context).colorScheme;
    final met = day.status == HabitDayStatus.met;
    return OutlinedButton(
      onPressed: () async {
        await HabitRepository.toggleCompletion(
          goal: goal,
          logicalDate: day.logicalDate,
          username: widget.username,
        );
        _loadData();
      },
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        minimumSize: const Size(0, 32),
        foregroundColor:
            met ? colorScheme.onSurfaceVariant : colorScheme.primary,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
      child: Text(met ? '撤销' : '补卡'),
    );
  }
}

enum _DayAggregate { none, allMet, partial, noneMet, future }
