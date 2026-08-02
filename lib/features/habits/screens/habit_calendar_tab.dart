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
    // 日历是历史视图，归档习惯仍需参与计算；今日 / 分析页仍只加载未归档习惯。
    final goals = await HabitRepository.getGoals();
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
  ({_DayAggregate status, double ratio}) _aggregate(DateTime day) {
    // 未来日期不显示状态（设计文档 11.2）。
    final now = DateTime.now();
    if (day.isAfter(DateTime(now.year, now.month, now.day))) {
      return (status: _DayAggregate.future, ratio: 0.0);
    }
    final key = HabitRuleResolver.dayKey(day);
    int planned = 0;
    int met = 0;
    int skipped = 0;
    double totalRatio = 0.0;
    for (final goal in _goals) {
      final days = _daysByHabit[goal.uuid];
      if (days == null) continue;
      final match = days.where((d) {
        final k = HabitRuleResolver.dayKey(d.logicalDate);
        return k == key;
      });
      if (match.isEmpty) continue;
      final day = match.first;
      // 归档代表停止后续执行。归档后的空计划日不应继续污染日历，
      // 但归档前已经产生过记录的日期仍要保留。
      if (goal.isArchived && !_hasHistoricalRecord(day)) continue;
      final status = day.status;
      if (status == HabitDayStatus.notPlanned) continue;
      if (status == HabitDayStatus.skipped) {
        skipped++;
        continue;
      }
      planned++;
      totalRatio += day.progress.completionRatio.clamp(0.0, 1.0);
      if (status == HabitDayStatus.met) met++;
    }
    if (planned == 0) {
      // 全部习惯当天均被跳过：灰色标记（与非计划日的空白区分）。
      if (skipped > 0) return (status: _DayAggregate.skipped, ratio: 0.0);
      return (status: _DayAggregate.none, ratio: 0.0);
    }
    final overallRatio = totalRatio / planned;
    if (met == planned) return (status: _DayAggregate.allMet, ratio: 1.0);
    if (met == 0) return (status: _DayAggregate.noneMet, ratio: overallRatio);
    return (status: _DayAggregate.partial, ratio: overallRatio);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth > 600;

        if (isWide) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 5,
                child: RefreshIndicator(
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
                    ],
                  ),
                ),
              ),
              const VerticalDivider(
                  width: 1, thickness: 1, color: Colors.black12),
              Expanded(
                flex: 4,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                  children: [
                    _buildSelectedDayDetail(),
                  ],
                ),
              ),
            ],
          );
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
      },
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
      final aggData = _aggregate(date);
      final aggregate = aggData.status;
      final ratio = aggData.ratio;

      Color bg = Colors.transparent;
      Color dot = colorScheme.outlineVariant;
      switch (aggregate) {
        case _DayAggregate.allMet:
          bg = colorScheme.tertiaryContainer;
          dot = colorScheme.tertiary;
        case _DayAggregate.partial:
          bg = Colors.transparent;
          dot = colorScheme.tertiary;
        case _DayAggregate.noneMet:
        case _DayAggregate.none:
        case _DayAggregate.future:
          bg = Colors.transparent;
          dot = colorScheme.outlineVariant;
        case _DayAggregate.skipped:
          bg = colorScheme.surfaceContainerHighest.withValues(alpha: 0.45);
          dot = colorScheme.outline;
      }

      cells.add(
        GestureDetector(
          onTap: () => setState(() => _selectedDay = date),
          child: Container(
            margin: const EdgeInsets.all(2),
            decoration: BoxDecoration(
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
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8), // 略小于外框
              child: Stack(
                children: [
                  Container(color: bg),
                  // “水池灌水”式的进度填充
                  if (ratio > 0.0 && aggregate == _DayAggregate.partial)
                    Align(
                      alignment: Alignment.bottomCenter,
                      child: FractionallySizedBox(
                        heightFactor: ratio,
                        widthFactor: 1.0,
                        child: Container(
                          color: colorScheme.tertiaryContainer.withValues(alpha: 0.6),
                        ),
                      ),
                    ),
                  Center(
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
                ],
              ),
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
        item(colorScheme.outline, '已跳过'),
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
      final dayProgress = day.first;
      if (goal.isArchived && !_hasHistoricalRecord(dayProgress)) continue;
      rows.add(_buildDayRow(goal, dayProgress));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          dayLabel,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 16),
        if (rows.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 24),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(
              '这一天没有习惯计划',
              style: TextStyle(
                fontSize: 14,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          )
        else
          ...rows,
      ],
    );
  }

  bool _hasHistoricalRecord(HabitDayProgress day) {
    final progress = day.progress;
    return progress.hasRecord || progress.goalMet || progress.isSkipped;
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
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Text(goal.icon.isNotEmpty ? goal.icon : '🎯',
              style: const TextStyle(fontSize: 22)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        goal.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: colorScheme.onSurface,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        label,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: color,
                        ),
                      ),
                    ),
                  ],
                ),
                if (detail.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    detail,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12.5,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ]
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (goal.sourceType == HabitSourceType.recurringTodo)
            _buildMakeUpButton(goal, day)
          else
            _buildSkipButton(goal, day, colorScheme, label),
        ],
      ),
    );
  }

  /// 非完成型习惯：计划内且非未来日期支持「跳过 / 取消跳过」。
  Widget _buildSkipButton(
    HabitGoal goal,
    HabitDayProgress day,
    ColorScheme colorScheme,
    String label,
  ) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    if (day.logicalDate.isAfter(today) || !day.progress.isPlanned) {
      return const SizedBox.shrink();
    }
    final skipped = day.status == HabitDayStatus.skipped;
    return OutlinedButton(
      onPressed: () async {
        final rule = HabitRuleResolver.effectiveRule(
          _rulesByHabit[goal.uuid] ?? const [],
          day.logicalDate,
        );
        if (rule == null) return;
        await HabitRepository.toggleSkipped(
          goal: goal,
          rule: rule,
          localDate: day.logicalDate,
        );
        _loadData();
      },
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        minimumSize: const Size(0, 32),
        foregroundColor:
            skipped ? colorScheme.onSurfaceVariant : colorScheme.outline,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
      child: Text(skipped ? '取消跳过' : '跳过'),
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

enum _DayAggregate { none, allMet, partial, noneMet, skipped, future }
