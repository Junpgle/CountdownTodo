import 'package:flutter/material.dart';

import '../../../utils/app_dialogs.dart';
import '../../../utils/page_transitions.dart';
import '../../../widgets/floating_bottom_bar.dart';
import '../models/habit_checkin.dart';
import '../models/habit_goal.dart';
import '../models/habit_goal_rule.dart';
import '../models/habit_progress.dart';
import '../repositories/habit_repository.dart';
import '../services/habit_calendar_light_up_service.dart';
import '../services/habit_drink_log_service.dart';
import '../services/habit_freeze_service.dart';
import '../services/habit_sleep_duration_service.dart';
import '../services/habit_progress_calculator.dart';
import '../services/habit_rule_resolver.dart';
import '../services/habit_source_resolver.dart';
import '../services/habit_sleep_goal_resolver.dart';
import '../widgets/habit_calendar_light_up_sheet.dart';
import '../widgets/habit_drink_picker_sheet.dart';
import '../widgets/habit_format.dart';
import 'habit_detail_screen.dart';
import 'habit_edit_screen.dart';

/// 习惯中心「日历」标签页：
///
/// 顶部支持按习惯筛选：
/// - 选中「全部习惯」时显示聚合月历；
/// - 选中具体习惯时显示该习惯专属的打卡完成日历视图。
class HabitCalendarTab extends StatefulWidget {
  final double topPadding;
  final double extraBottomPadding;
  final String username;

  /// 数据变化后自增，触发重新加载。
  final int reloadTick;

  /// 初始选中的习惯 UUID（为空表示默认查看全部习惯）。
  final String? initialHabitUuid;

  /// 日历内快速点亮/修改打卡后通知父级刷新其他标签页。
  final VoidCallback? onChanged;

  const HabitCalendarTab({
    super.key,
    this.topPadding = 0,
    this.extraBottomPadding = 0,
    required this.username,
    this.reloadTick = 0,
    this.initialHabitUuid,
    this.onChanged,
  });

  @override
  State<HabitCalendarTab> createState() => _HabitCalendarTabState();
}

class _HabitCalendarTabState extends State<HabitCalendarTab> {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  DateTime _selectedDay = DateTime.now();
  List<HabitGoal> _goals = [];
  Map<String, List<HabitGoalRuleRevision>> _rulesByHabit = {};
  Map<String, Map<String, HabitDayProgress>> _dayByHabitAndLogicalDate = {};
  Map<String, Map<String, List<HabitCheckIn>>> _checkInsByHabitAndLogicalDate =
      {};
  final Map<String, ({_DayAggregate status, double ratio})> _aggregateCache =
      {};
  String? _aggregateCacheTodayKey;
  bool _loading = true;
  int _loadGeneration = 0;

  /// 当前选中的习惯 UUID（null 表示全部习惯）。
  String? _selectedHabitUuid;

  @override
  void initState() {
    super.initState();
    _selectedHabitUuid = widget.initialHabitUuid;
    _loadData();
  }

  @override
  void didUpdateWidget(HabitCalendarTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.reloadTick != widget.reloadTick) {
      _loadData();
    }
    if (oldWidget.initialHabitUuid != widget.initialHabitUuid &&
        widget.initialHabitUuid != null) {
      setState(() => _selectedHabitUuid = widget.initialHabitUuid);
    }
  }

  HabitGoal? get _selectedGoal {
    if (_selectedHabitUuid == null) return null;
    return _goals.where((goal) => goal.uuid == _selectedHabitUuid).firstOrNull;
  }

  Future<void> _loadData() async {
    if (!mounted) return;
    final loadGen = ++_loadGeneration;
    _aggregateCache.clear();
    _aggregateCacheTodayKey = null;
    setState(() => _loading = true);
    try {
      await HabitSleepDurationService.syncAll();
      // 日历是历史视图，归档习惯仍需参与计算；今日 / 分析页仍只加载未归档习惯。
      final goals = HabitSleepGoalResolver.forDisplay(
        await HabitRepository.getGoals(),
      );
      final goalUuids = goals.map((goal) => goal.uuid).toSet();
      final allRules = goalUuids.isEmpty
          ? const <HabitGoalRuleRevision>[]
          : await HabitRepository.getRulesForHabits(goalUuids);
      final rulesByHabit = <String, List<HabitGoalRuleRevision>>{};
      final daysByHabit = <String, List<HabitDayProgress>>{};
      final calculationGoals = <HabitGoal>[];

      final monthStart = DateTime(_month.year, _month.month, 1);
      final monthEnd = DateTime(_month.year, _month.month + 1, 0);

      if (goalUuids.isNotEmpty) {
        for (final rule in allRules) {
          if (!goalUuids.contains(rule.habitUuid)) continue;
          rulesByHabit.putIfAbsent(rule.habitUuid, () => []).add(rule);
        }
      }
      for (final goal in goals) {
        final rules = rulesByHabit.putIfAbsent(
          goal.uuid,
          () => <HabitGoalRuleRevision>[],
        );
        rules.sort(
          (a, b) =>
              (a.effectiveFromDate ?? '').compareTo(b.effectiveFromDate ?? ''),
        );
        if (rules.isNotEmpty) calculationGoals.add(goal);
      }

      final checkIns = calculationGoals.isEmpty
          ? const <HabitCheckIn>[]
          : await HabitRepository.getCheckInsForHabits(
              calculationGoals.map((goal) => goal.uuid),
              fromDate: HabitRuleResolver.dayKey(monthStart),
              toDate: HabitRuleResolver.dayKey(monthEnd),
            );
      final checkInsByHabit = <String, List<HabitCheckIn>>{};
      final checkInsByHabitAndLogicalDate =
          <String, Map<String, List<HabitCheckIn>>>{};
      for (final checkIn in checkIns) {
        (checkInsByHabit[checkIn.habitUuid] ??= <HabitCheckIn>[]).add(checkIn);
        ((checkInsByHabitAndLogicalDate[checkIn.habitUuid] ??=
                    <String, List<HabitCheckIn>>{})[checkIn.logicalDate] ??=
                <HabitCheckIn>[])
            .add(checkIn);
      }
      final recordsByHabit = await HabitSourceResolver.recordsForRange(
        calculationGoals
            .where((goal) => goal.sourceType == HabitSourceType.pomodoroTag)
            .map((goal) => (habitUuid: goal.uuid, tagUuids: goal.sourceIds)),
        from: monthStart,
        to: monthEnd,
      );
      final todosByHabit = await HabitSourceResolver.todosForHabitSources(
        calculationGoals
            .where((goal) => goal.sourceType == HabitSourceType.recurringTodo)
            .map((goal) => (habitUuid: goal.uuid, seriesIds: goal.sourceIds)),
      );

      // 并行计算各习惯的月进度，避免 N 个习惯串行读库拖慢月视图。
      final futures = <Future<void>>[];
      for (final goal in calculationGoals) {
        final rules = rulesByHabit[goal.uuid] ?? const [];
        futures.add(() async {
          final todos = todosByHabit?[goal.uuid];
          daysByHabit[goal.uuid] = await HabitProgressCalculator.computeRange(
            habit: goal,
            rules: rules,
            from: monthStart,
            to: monthEnd,
            todos: goal.sourceType == HabitSourceType.recurringTodo
                ? todos
                : const [],
            records: goal.sourceType == HabitSourceType.pomodoroTag
                ? recordsByHabit[goal.uuid] ?? const []
                : const [],
            checkIns: checkInsByHabit[goal.uuid] ?? const [],
          );
        }());
      }
      await Future.wait(futures);

      final dayByHabitAndLogicalDate =
          <String, Map<String, HabitDayProgress>>{};
      for (final entry in daysByHabit.entries) {
        final dayByLogicalDate = <String, HabitDayProgress>{};
        for (final day in entry.value) {
          dayByLogicalDate.putIfAbsent(
            HabitRuleResolver.dayKey(day.logicalDate),
            () => day,
          );
        }
        dayByHabitAndLogicalDate[entry.key] = dayByLogicalDate;
      }

      if (mounted && loadGen == _loadGeneration) {
        setState(() {
          _goals = goals;
          _rulesByHabit = rulesByHabit;
          _dayByHabitAndLogicalDate = dayByHabitAndLogicalDate;
          _checkInsByHabitAndLogicalDate = checkInsByHabitAndLogicalDate;
          if (_selectedHabitUuid != null &&
              !goals.any((g) => g.uuid == _selectedHabitUuid)) {
            _selectedHabitUuid = null;
          }
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('习惯日历加载失败: $e');
      if (mounted && loadGen == _loadGeneration) {
        setState(() => _loading = false);
      }
    }
  }

  void _changeMonth(int delta) {
    setState(() {
      _month = DateTime(_month.year, _month.month + delta, 1);
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

  void _goToCurrentMonth() {
    final now = DateTime.now();
    setState(() {
      _month = DateTime(now.year, now.month, 1);
      _selectedDay = now;
    });
    _loadData();
  }

  bool _isFutureDate(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return DateTime(date.year, date.month, date.day).isAfter(today);
  }

  bool _isHabitLitOnDay(HabitGoal goal, DateTime date) {
    if (_isFutureDate(date)) return false;
    final key = HabitRuleResolver.dayKey(date);
    final dayProgress = _dayByHabitAndLogicalDate[goal.uuid]?[key];
    final dayCheckIns =
        _checkInsByHabitAndLogicalDate[goal.uuid]?[key] ??
        const <HabitCheckIn>[];
    if (goal.isArchived &&
        (dayProgress == null || !_hasHistoricalRecord(dayProgress)) &&
        dayCheckIns.isEmpty) {
      return false;
    }
    return HabitCalendarLightUpService.isHabitLitOnDay(
      goal: goal,
      dayProgress: dayProgress,
      dayCheckIns: dayCheckIns,
    );
  }

  List<String> _litIconsForHabitOnDay(HabitGoal goal, DateTime date) {
    if (!_isHabitLitOnDay(goal, date)) return const <String>[];
    final key = HabitRuleResolver.dayKey(date);
    final dayCheckIns =
        _checkInsByHabitAndLogicalDate[goal.uuid]?[key] ??
        const <HabitCheckIn>[];
    return HabitDrinkLogService.displayIconsForHabitOnDay(
      goal: goal,
      dayCheckIns: dayCheckIns,
    );
  }

  List<String> _litIconsForDay(DateTime date) {
    if (_isFutureDate(date)) return const <String>[];
    final icons = <String>[];
    for (final goal in _goals) {
      icons.addAll(_litIconsForHabitOnDay(goal, date));
    }
    return icons;
  }

  Future<void> _handleDayTap(DateTime date, {HabitGoal? focusedGoal}) async {
    setState(() => _selectedDay = date);
    if (_isFutureDate(date)) return;
    if (focusedGoal != null &&
        HabitDrinkLogService.isDrinkChoiceHabit(focusedGoal)) {
      await _openDrinkPickerForDate(focusedGoal, date);
      return;
    }
    await _openLightUpSheet(date, focusedGoal: focusedGoal);
  }

  Future<List<String>?> _openDrinkPickerForDate(
    HabitGoal goal,
    DateTime date,
  ) async {
    final key = HabitRuleResolver.dayKey(date);
    final dayCheckIns =
        _checkInsByHabitAndLogicalDate[goal.uuid]?[key] ??
        const <HabitCheckIn>[];
    var changed = false;
    final picked = await HabitDrinkPickerSheet.show(
      context: context,
      goal: goal,
      rules: _rulesByHabit[goal.uuid] ?? const [],
      logicalDate: date,
      username: widget.username,
      initialSelectedIcons: HabitDrinkLogService.extractDrinkIcons(dayCheckIns),
      onChanged: () {
        changed = true;
        _loadData();
      },
    );
    if (changed && mounted) {
      await _loadData();
      widget.onChanged?.call();
    }
    return picked;
  }

  Future<void> _openLightUpSheet(
    DateTime date, {
    HabitGoal? focusedGoal,
  }) async {
    final key = HabitRuleResolver.dayKey(date);
    final sheetGoals = <HabitGoal>[];
    final addedUuids = <String>{};

    void addIfEligible(HabitGoal goal) {
      if (addedUuids.contains(goal.uuid)) return;
      final isLit = _isHabitLitOnDay(goal, date);
      if (goal.isArchived && !isLit) return;
      addedUuids.add(goal.uuid);
      sheetGoals.add(goal);
    }

    if (focusedGoal != null) {
      addIfEligible(focusedGoal);
    }
    for (final goal in _goals) {
      addIfEligible(goal);
    }

    final initialLitStates = <String, bool>{
      for (final goal in sheetGoals) goal.uuid: _isHabitLitOnDay(goal, date),
    };
    final initialDisplayIconsByHabit = <String, List<String>>{
      for (final goal in sheetGoals)
        if (_isHabitLitOnDay(goal, date))
          goal.uuid: _litIconsForHabitOnDay(goal, date),
    };
    final subtitleByHabit = <String, String>{};
    for (final goal in sheetGoals) {
      final dayProgress = _dayByHabitAndLogicalDate[goal.uuid]?[key];
      if (dayProgress != null &&
          dayProgress.status == HabitDayStatus.inProgress) {
        final compact = _dayValueText(goal, dayProgress);
        if (compact.isNotEmpty) {
          subtitleByHabit[goal.uuid] = compact;
        }
      }
    }

    var changedAny = false;
    final screenSize = MediaQuery.sizeOf(context);
    await showAppModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      constraints: BoxConstraints(
        maxWidth: 520,
        maxHeight: screenSize.height * 0.82,
      ),
      builder: (_) => HabitCalendarLightUpSheet(
        date: date,
        goals: sheetGoals,
        initialLitStates: initialLitStates,
        initialDisplayIconsByHabit: initialDisplayIconsByHabit,
        subtitleByHabit: subtitleByHabit,
        focusedHabitUuid: focusedGoal?.uuid,
        onToggleHabit: (goal, currentlyLit) async {
          final result = await HabitCalendarLightUpService.toggleHabitLitForDay(
            goal: goal,
            rules: _rulesByHabit[goal.uuid] ?? const [],
            logicalDate: date,
            currentlyLit: currentlyLit,
            dayProgress: _dayByHabitAndLogicalDate[goal.uuid]?[key],
            username: widget.username,
          );
          if (result.changed) {
            changedAny = true;
            await _loadData();
          }
          return result;
        },
        onPickDrinks: (goal) async {
          final picked = await _openDrinkPickerForDate(goal, date);
          if (picked != null) {
            changedAny = true;
          }
          return picked;
        },
        onCreateHabit: () async {
          final created = await Navigator.of(context).push<bool>(
            PageTransitions.material(builder: (_) => const HabitEditScreen()),
          );
          if (created == true && mounted) {
            await _loadData();
            widget.onChanged?.call();
          }
        },
      ),
    );

    if (changedAny && mounted) {
      widget.onChanged?.call();
    }
  }

  /// 在日历格子中渲染当天点亮的习惯图标：
  /// - 1 个图标：大号居中清晰展示（如 🧋 或 🥤）；
  /// - 2 个图标：并排展示（如 🧋🥤）；
  /// - 3~4 个（宽格子最多 6 个）图标：多行紧凑排列完整展示，不提前折叠为 +1；
  /// - 超出容量时再在末尾展示 `+N` 徽标，防止窄屏溢出。
  Widget _buildDayLitIcons(List<String> icons, ColorScheme colorScheme) {
    if (icons.isEmpty) return const SizedBox.shrink();

    if (icons.length == 1) {
      return FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          icons.first,
          style: const TextStyle(fontSize: 18, height: 1.05),
        ),
      );
    }

    if (icons.length == 2) {
      return FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(icons[0], style: const TextStyle(fontSize: 14, height: 1.05)),
            const SizedBox(width: 2),
            Text(icons[1], style: const TextStyle(fontSize: 14, height: 1.05)),
          ],
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final isRoomyCell = constraints.maxWidth >= 54;
        final maxVisible = isRoomyCell ? 6 : 4;
        final hasOverflow = icons.length > maxVisible;
        final shownCount = hasOverflow ? maxVisible - 1 : icons.length;
        final visibleIcons = icons.take(shownCount).toList(growable: false);
        final extraCount = icons.length - shownCount;
        final iconSize = icons.length <= 3
            ? (isRoomyCell ? 13.0 : 11.5)
            : (isRoomyCell ? 11.5 : 10.0);

        return FittedBox(
          fit: BoxFit.scaleDown,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: constraints.maxWidth.isFinite
                  ? constraints.maxWidth
                  : 56,
            ),
            child: Wrap(
              alignment: WrapAlignment.center,
              runAlignment: WrapAlignment.center,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 1.5,
              runSpacing: 1,
              children: [
                for (final icon in visibleIcons)
                  Text(
                    icon,
                    style: TextStyle(fontSize: iconSize, height: 1.05),
                  ),
                if (hasOverflow)
                  Text(
                    '+$extraCount',
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      color: colorScheme.primary,
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ── 每日聚合状态（全部习惯） ─────────────────────────
  ({_DayAggregate status, double ratio}) _aggregate(DateTime day) {
    final now = DateTime.now();
    final todayKey = HabitRuleResolver.dayKey(now);
    if (_aggregateCacheTodayKey != todayKey) {
      _aggregateCache.clear();
      _aggregateCacheTodayKey = todayKey;
    }
    final cacheKey = '$todayKey|${HabitRuleResolver.dayKey(day)}';
    return _aggregateCache.putIfAbsent(
      cacheKey,
      () => _calculateAggregate(day, now),
    );
  }

  ({_DayAggregate status, double ratio}) _calculateAggregate(
    DateTime day,
    DateTime now,
  ) {
    if (day.isAfter(DateTime(now.year, now.month, now.day))) {
      return (status: _DayAggregate.future, ratio: 0.0);
    }
    final key = HabitRuleResolver.dayKey(day);
    int planned = 0;
    int met = 0;
    int skipped = 0;
    double totalRatio = 0.0;
    for (final goal in _goals) {
      final day = _dayByHabitAndLogicalDate[goal.uuid]?[key];
      if (day == null) continue;
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
      if (skipped > 0) return (status: _DayAggregate.skipped, ratio: 0.0);
      return (status: _DayAggregate.none, ratio: 0.0);
    }
    final overallRatio = totalRatio / planned;
    if (met == planned) return (status: _DayAggregate.allMet, ratio: 1.0);
    if (met == 0) return (status: _DayAggregate.noneMet, ratio: overallRatio);
    return (status: _DayAggregate.partial, ratio: overallRatio);
  }

  // ── 单习惯当月打卡统计 ────────────────────────────────
  ({
    int plannedDays,
    int metDays,
    int frozenDays,
    int skippedDays,
    int missedDays,
    double rate,
  })
  _computeGoalMonthSummary(HabitGoal goal) {
    final daysInMonth = DateTime(_month.year, _month.month + 1, 0).day;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    int planned = 0;
    int met = 0;
    int frozen = 0;
    int skipped = 0;
    int missed = 0;

    final daysMap = _dayByHabitAndLogicalDate[goal.uuid];
    if (daysMap != null) {
      for (int d = 1; d <= daysInMonth; d++) {
        final date = DateTime(_month.year, _month.month, d);
        if (date.isAfter(today)) continue;
        final key = HabitRuleResolver.dayKey(date);
        final dayProgress = daysMap[key];
        if (dayProgress == null) continue;
        if (goal.isArchived && !_hasHistoricalRecord(dayProgress)) continue;

        final status = dayProgress.status;
        if (status == HabitDayStatus.notPlanned) continue;

        planned++;
        switch (status) {
          case HabitDayStatus.met:
            met++;
          case HabitDayStatus.frozen:
            frozen++;
          case HabitDayStatus.skipped:
            skipped++;
          case HabitDayStatus.missed:
            missed++;
          case HabitDayStatus.inProgress:
          case HabitDayStatus.notPlanned:
            break;
        }
      }
    }

    final rate = planned > 0 ? (met / planned) : 0.0;
    return (
      plannedDays: planned,
      metDays: met,
      frozenDays: frozen,
      skippedDays: skipped,
      missedDays: missed,
      rate: rate,
    );
  }

  String _compactDayValue(HabitGoal goal, HabitDayProgress day) {
    final progress = day.progress;
    if (day.status == HabitDayStatus.met) {
      switch (goal.sourceType) {
        case HabitSourceType.recurringTodo:
          return '✓';
        case HabitSourceType.pomodoroTag:
        case HabitSourceType.durationCheckIn:
          final m = (progress.currentValue / 60).round();
          return m > 0 ? '${m}m' : '✓';
        case HabitSourceType.quantityCheckIn:
          final v = progress.currentValue;
          final unit = _unitOf(goal);
          final vStr = v == v.roundToDouble()
              ? '${v.toInt()}'
              : v.toStringAsFixed(1);
          return '$vStr$unit';
        case HabitSourceType.timeCheckIn:
          final actual = progress.firstRecordAt;
          if (actual != null) {
            return HabitText.timeOfDay(actual);
          }
          return '✓';
      }
    }
    return '';
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _goals.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth > 600;
        final bottomPadding =
            floatingBottomNavigationContentPaddingFor(context) +
            widget.extraBottomPadding;
        final selectedGoal = _selectedGoal;

        // 1. 选中具体习惯：单习惯打卡大日历视图
        if (selectedGoal != null) {
          return _buildSingleHabitView(
            context,
            goal: selectedGoal,
            isWide: isWide,
            bottomPadding: bottomPadding,
          );
        }

        // 2. 选中全部习惯：总览月历视图
        return _buildOverviewCalendarView(
          context,
          isWide: isWide,
          bottomPadding: bottomPadding,
        );
      },
    );
  }

  // ── 顶部月份切换栏 ─────────────────────────────────────
  Widget _buildMonthHeader() {
    final colorScheme = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final isCurrentMonth = _month.year == now.year && _month.month == now.month;

    return Row(
      children: [
        IconButton(
          tooltip: '上一月',
          onPressed: () => _changeMonth(-1),
          icon: const Icon(Icons.chevron_left_rounded),
        ),
        Expanded(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${_month.year} 年 ${_month.month} 月',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16.5,
                  fontWeight: FontWeight.w700,
                  color: colorScheme.onSurface,
                ),
              ),
              if (_loading && _goals.isNotEmpty) ...[
                const SizedBox(width: 8),
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: colorScheme.primary,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (!isCurrentMonth)
          TextButton(
            onPressed: _goToCurrentMonth,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: const Size(0, 32),
            ),
            child: const Text('今月', style: TextStyle(fontSize: 12.5)),
          ),
        IconButton(
          tooltip: '下一月',
          onPressed: () => _changeMonth(1),
          icon: const Icon(Icons.chevron_right_rounded),
        ),
      ],
    );
  }

  // ── 习惯筛选 Chip 列表 ──────────────────────────────────
  Widget _buildHabitFilterBar() {
    final colorScheme = Theme.of(context).colorScheme;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          FilterChip(
            showCheckmark: false,
            avatar: Icon(
              Icons.grid_view_rounded,
              size: 15,
              color: _selectedHabitUuid == null
                  ? colorScheme.onPrimary
                  : colorScheme.onSurfaceVariant,
            ),
            label: const Text('全部习惯'),
            selected: _selectedHabitUuid == null,
            selectedColor: colorScheme.primary,
            labelStyle: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: _selectedHabitUuid == null
                  ? colorScheme.onPrimary
                  : colorScheme.onSurface,
            ),
            onSelected: (_) {
              if (_selectedHabitUuid != null) {
                setState(() => _selectedHabitUuid = null);
              }
            },
          ),
          const SizedBox(width: 8),
          for (final goal in _goals) ...[
            FilterChip(
              showCheckmark: false,
              avatar: Text(
                goal.icon.isNotEmpty ? goal.icon : '🎯',
                style: const TextStyle(fontSize: 14),
              ),
              label: Text(
                goal.name + (goal.isArchived ? ' (已归档)' : ''),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              selected: _selectedHabitUuid == goal.uuid,
              selectedColor: colorScheme.primary,
              labelStyle: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: _selectedHabitUuid == goal.uuid
                    ? colorScheme.onPrimary
                    : colorScheme.onSurface,
              ),
              onSelected: (_) {
                setState(() => _selectedHabitUuid = goal.uuid);
              },
            ),
            const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }

  // ── 单习惯打卡日历大视图 ──────────────────────────────────
  Widget _buildSingleHabitView(
    BuildContext context, {
    required HabitGoal goal,
    required bool isWide,
    required double bottomPadding,
  }) {
    if (isWide) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 5,
            child: RefreshIndicator(
              edgeOffset: widget.topPadding,
              onRefresh: _loadData,
              child: ListView(
                padding: EdgeInsets.fromLTRB(
                  16,
                  widget.topPadding + 12,
                  16,
                  bottomPadding,
                ),
                children: [
                  _buildMonthHeader(),
                  const SizedBox(height: 10),
                  _buildHabitFilterBar(),
                  const SizedBox(height: 14),
                  _buildSingleHabitSummaryCard(goal),
                  const SizedBox(height: 14),
                  _buildWeekdayHeader(),
                  const SizedBox(height: 4),
                  _buildSingleHabitDayGrid(goal),
                  const SizedBox(height: 14),
                  _buildSingleHabitLegend(),
                ],
              ),
            ),
          ),
          const VerticalDivider(width: 1, thickness: 1, color: Colors.black12),
          Expanded(
            flex: 4,
            child: ListView(
              padding: EdgeInsets.fromLTRB(
                16,
                widget.topPadding + 12,
                16,
                bottomPadding,
              ),
              children: [_buildSingleHabitDayDetail(goal)],
            ),
          ),
        ],
      );
    }

    return RefreshIndicator(
      edgeOffset: widget.topPadding,
      onRefresh: _loadData,
      child: ListView(
        padding: EdgeInsets.fromLTRB(
          16,
          widget.topPadding + 12,
          16,
          bottomPadding,
        ),
        children: [
          _buildMonthHeader(),
          const SizedBox(height: 10),
          _buildHabitFilterBar(),
          const SizedBox(height: 14),
          _buildSingleHabitSummaryCard(goal),
          const SizedBox(height: 14),
          _buildWeekdayHeader(),
          const SizedBox(height: 4),
          _buildSingleHabitDayGrid(goal),
          const SizedBox(height: 14),
          _buildSingleHabitLegend(),
          const SizedBox(height: 14),
          _buildSingleHabitDayDetail(goal),
        ],
      ),
    );
  }

  // ── 单习惯本月打卡统计小卡片 ─────────────────────────────
  Widget _buildSingleHabitSummaryCard(HabitGoal goal) {
    final colorScheme = Theme.of(context).colorScheme;
    final summary = _computeGoalMonthSummary(goal);
    final ratePercent = (summary.rate * 100).round();

    Widget statItem({
      required String label,
      required String value,
      Color? valueColor,
    }) {
      return Expanded(
        child: Column(
          children: [
            Text(
              value,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: valueColor ?? colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 11.5,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Text(
                goal.icon.isNotEmpty ? goal.icon : '🎯',
                style: const TextStyle(fontSize: 20),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${goal.name} · 本月打卡日历',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                    color: colorScheme.onSurface,
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: () async {
                  final changed = await Navigator.of(context).push<bool>(
                    PageTransitions.material(
                      builder: (_) => HabitDetailScreen(
                        goal: goal,
                        username: widget.username,
                      ),
                    ),
                  );
                  if (changed == true && mounted) {
                    _loadData();
                  }
                },
                icon: const Icon(Icons.arrow_forward_ios_rounded, size: 12),
                label: const Text('详情', style: TextStyle(fontSize: 12.5)),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: const Size(0, 30),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Divider(height: 1, thickness: 0.5),
          const SizedBox(height: 10),
          Row(
            children: [
              statItem(
                label: '已达标',
                value: '${summary.metDays}天',
                valueColor: colorScheme.tertiary,
              ),
              statItem(
                label: '达成率',
                value: '$ratePercent%',
                valueColor: colorScheme.primary,
              ),
              statItem(label: '计划天数', value: '${summary.plannedDays}天'),
              statItem(
                label: '免扣/跳过',
                value: '${summary.frozenDays}/${summary.skippedDays}天',
                valueColor: summary.frozenDays > 0
                    ? colorScheme.secondary
                    : null,
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── 单习惯大日历网格 ──────────────────────────────────
  Widget _buildSingleHabitDayGrid(HabitGoal goal) {
    final colorScheme = Theme.of(context).colorScheme;
    final firstDay = DateTime(_month.year, _month.month, 1);
    final daysInMonth = DateTime(_month.year, _month.month + 1, 0).day;
    final leadingBlanks = firstDay.weekday - 1;

    final cells = <Widget>[];
    for (int i = 0; i < leadingBlanks; i++) {
      cells.add(const SizedBox.shrink());
    }

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    for (int day = 1; day <= daysInMonth; day++) {
      final date = DateTime(_month.year, _month.month, day);
      final isToday =
          date.year == today.year &&
          date.month == today.month &&
          date.day == today.day;
      final isSelected =
          date.year == _selectedDay.year &&
          date.month == _selectedDay.month &&
          date.day == _selectedDay.day;
      final isFuture = date.isAfter(today);

      final key = HabitRuleResolver.dayKey(date);
      final dayProgress = _dayByHabitAndLogicalDate[goal.uuid]?[key];
      final dayCheckIns =
          _checkInsByHabitAndLogicalDate[goal.uuid]?[key] ??
          const <HabitCheckIn>[];
      final isLit = _isHabitLitOnDay(goal, date);
      final hasDrinkFailure =
          !isFuture &&
          HabitDrinkLogService.isDrinkChoiceHabit(goal) &&
          HabitDrinkLogService.extractDrinkIcons(dayCheckIns).isNotEmpty;

      HabitDayStatus? status;
      if (!isFuture && dayProgress != null) {
        if (!goal.isArchived || _hasHistoricalRecord(dayProgress)) {
          status = dayProgress.status;
        }
      }

      Color cellBg = Colors.transparent;
      Color textColor = colorScheme.onSurface;
      Color dotColor = Colors.transparent;
      String subText = '';

      if (isFuture) {
        textColor = colorScheme.onSurfaceVariant.withValues(alpha: 0.35);
      } else if (hasDrinkFailure) {
        cellBg = colorScheme.errorContainer.withValues(alpha: 0.45);
        textColor = colorScheme.onErrorContainer;
        dotColor = colorScheme.error;
      } else if (isLit) {
        cellBg = colorScheme.tertiaryContainer.withValues(alpha: 0.82);
        textColor = colorScheme.onTertiaryContainer;
        dotColor = colorScheme.tertiary;
        if (dayProgress != null) {
          final compact = _compactDayValue(goal, dayProgress);
          if (compact.isNotEmpty && compact != '✓') {
            subText = compact;
          }
        }
      } else {
        switch (status) {
          case HabitDayStatus.met:
            cellBg = colorScheme.tertiaryContainer;
            textColor = colorScheme.onTertiaryContainer;
            dotColor = colorScheme.tertiary;
          case HabitDayStatus.frozen:
            cellBg = colorScheme.secondaryContainer.withValues(alpha: 0.55);
            textColor = colorScheme.onSecondaryContainer;
            dotColor = colorScheme.secondary;
          case HabitDayStatus.skipped:
            cellBg = colorScheme.surfaceContainerHighest.withValues(
              alpha: 0.45,
            );
            textColor = colorScheme.outline;
            dotColor = colorScheme.outline;
          case HabitDayStatus.inProgress:
            cellBg = Colors.transparent;
            dotColor = colorScheme.secondary;
          case HabitDayStatus.missed:
            cellBg = colorScheme.errorContainer.withValues(alpha: 0.15);
            dotColor = colorScheme.error;
          case HabitDayStatus.notPlanned:
          case null:
            textColor = colorScheme.onSurfaceVariant.withValues(alpha: 0.4);
        }
      }

      final litIcons = _litIconsForHabitOnDay(goal, date);
      final hasDrinkSelection =
          isLit &&
          HabitDrinkLogService.extractDrinkIcons(
            _checkInsByHabitAndLogicalDate[goal.uuid]?[key] ??
                const <HabitCheckIn>[],
          ).isNotEmpty;

      cells.add(
        GestureDetector(
          key: ValueKey('habit_calendar_single_day_$key'),
          onTap: () => _handleDayTap(date, focusedGoal: goal),
          child: Container(
            margin: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: isSelected
                    ? colorScheme.primary
                    : isToday
                    ? colorScheme.primary.withValues(alpha: 0.45)
                    : isLit
                    ? colorScheme.tertiary.withValues(alpha: 0.25)
                    : Colors.transparent,
                width: isSelected ? 2 : 1,
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Stack(
                children: [
                  Container(color: cellBg),
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 2,
                        vertical: 2,
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            '$day',
                            style: TextStyle(
                              fontSize: isLit ? 11.5 : 13,
                              fontWeight: isToday || isSelected
                                  ? FontWeight.w800
                                  : FontWeight.w500,
                              color: isSelected
                                  ? colorScheme.primary
                                  : textColor,
                            ),
                          ),
                          if (isLit) ...[
                            const SizedBox(height: 1),
                            Flexible(
                              child: _buildDayLitIcons(litIcons, colorScheme),
                            ),
                            if (!hasDrinkSelection && subText.isNotEmpty)
                              FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  subText,
                                  maxLines: 1,
                                  style: TextStyle(
                                    fontSize: 8.5,
                                    fontWeight: FontWeight.w700,
                                    color: colorScheme.tertiary,
                                  ),
                                ),
                              ),
                          ] else if (status == HabitDayStatus.frozen) ...[
                            const SizedBox(height: 2),
                            Icon(
                              Icons.shield_rounded,
                              size: 8.5,
                              color: colorScheme.secondary,
                            ),
                          ] else ...[
                            const SizedBox(height: 2),
                            Container(
                              width: 5.5,
                              height: 5.5,
                              decoration: BoxDecoration(
                                color: dotColor,
                                shape: BoxShape.circle,
                              ),
                            ),
                          ],
                        ],
                      ),
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
      padding: EdgeInsets.zero,
      primary: false,
      crossAxisCount: 7,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: 0.84,
      children: cells,
    );
  }

  // ── 单习惯图例 ─────────────────────────────────────
  Widget _buildSingleHabitLegend() {
    final colorScheme = Theme.of(context).colorScheme;
    Widget item(Color color, String label, {Widget? icon}) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null)
            icon
          else
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
          ),
        ],
      );
    }

    return Wrap(
      spacing: 14,
      runSpacing: 8,
      children: [
        item(colorScheme.tertiary, '已达标'),
        item(colorScheme.error, '未完成'),
        item(colorScheme.secondary, '进行中'),
        item(
          colorScheme.secondary,
          '免扣保护',
          icon: Icon(
            Icons.shield_rounded,
            size: 12,
            color: colorScheme.secondary,
          ),
        ),
        item(colorScheme.outline, '已跳过'),
      ],
    );
  }

  // ── 单习惯选中日明细 ──────────────────────────────────
  Widget _buildSingleHabitDayDetail(HabitGoal goal) {
    final colorScheme = Theme.of(context).colorScheme;
    final dayLabel =
        '${_selectedDay.month} 月 ${_selectedDay.day} 日'
        ' · 周${'一二三四五六日'[_selectedDay.weekday - 1]}';
    final key = HabitRuleResolver.dayKey(_selectedDay);
    final dayProgress = _dayByHabitAndLogicalDate[goal.uuid]?[key];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              dayLabel,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: colorScheme.onSurface,
              ),
            ),
            TextButton.icon(
              onPressed: () => setState(() => _selectedHabitUuid = null),
              icon: const Icon(Icons.arrow_back_rounded, size: 14),
              label: const Text('查看全部', style: TextStyle(fontSize: 12.5)),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (dayProgress == null)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 24),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(
              '这一天没有打卡计划',
              style: TextStyle(
                fontSize: 14,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          )
        else
          _buildDayRow(goal, dayProgress),
      ],
    );
  }

  // ── 总览聚合月历视图 ───────────────────────────────────
  Widget _buildOverviewCalendarView(
    BuildContext context, {
    required bool isWide,
    required double bottomPadding,
  }) {
    if (isWide) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 5,
            child: RefreshIndicator(
              edgeOffset: widget.topPadding,
              onRefresh: _loadData,
              child: ListView(
                padding: EdgeInsets.fromLTRB(
                  16,
                  widget.topPadding + 12,
                  16,
                  bottomPadding,
                ),
                children: [
                  _buildMonthHeader(),
                  const SizedBox(height: 10),
                  _buildHabitFilterBar(),
                  const SizedBox(height: 14),
                  _buildWeekdayHeader(),
                  const SizedBox(height: 4),
                  _buildDayGrid(),
                  const SizedBox(height: 16),
                  _buildLegend(),
                ],
              ),
            ),
          ),
          const VerticalDivider(width: 1, thickness: 1, color: Colors.black12),
          Expanded(
            flex: 4,
            child: ListView(
              padding: EdgeInsets.fromLTRB(
                16,
                widget.topPadding + 12,
                16,
                bottomPadding,
              ),
              children: [_buildSelectedDayDetail()],
            ),
          ),
        ],
      );
    }

    return RefreshIndicator(
      edgeOffset: widget.topPadding,
      onRefresh: _loadData,
      child: ListView(
        padding: EdgeInsets.fromLTRB(
          16,
          widget.topPadding + 12,
          16,
          bottomPadding,
        ),
        children: [
          _buildMonthHeader(),
          const SizedBox(height: 10),
          _buildHabitFilterBar(),
          const SizedBox(height: 14),
          _buildWeekdayHeader(),
          const SizedBox(height: 4),
          _buildDayGrid(),
          const SizedBox(height: 16),
          _buildLegend(),
          const SizedBox(height: 16),
          _buildSelectedDayDetail(),
        ],
      ),
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
    final leadingBlanks = firstDay.weekday - 1;

    final cells = <Widget>[];
    for (int i = 0; i < leadingBlanks; i++) {
      cells.add(const SizedBox.shrink());
    }

    final today = DateTime.now();
    for (int day = 1; day <= daysInMonth; day++) {
      final date = DateTime(_month.year, _month.month, day);
      final isToday =
          date.year == today.year &&
          date.month == today.month &&
          date.day == today.day;
      final isSelected =
          date.year == _selectedDay.year &&
          date.month == _selectedDay.month &&
          date.day == _selectedDay.day;
      final isFuture = _isFutureDate(date);
      final aggData = _aggregate(date);
      final aggregate = aggData.status;
      final ratio = aggData.ratio;
      final litIcons = _litIconsForDay(date);
      final hasLit = litIcons.isNotEmpty;
      final key = HabitRuleResolver.dayKey(date);

      Color bg = Colors.transparent;
      Color dot = colorScheme.outlineVariant;
      if (hasLit) {
        if (aggregate == _DayAggregate.allMet) {
          bg = colorScheme.tertiaryContainer.withValues(alpha: 0.8);
          dot = colorScheme.tertiary;
        } else if (aggregate == _DayAggregate.noneMet) {
          bg = colorScheme.errorContainer.withValues(alpha: 0.42);
          dot = colorScheme.error;
        } else {
          bg = colorScheme.primaryContainer.withValues(alpha: 0.55);
          dot = colorScheme.primary;
        }
      } else {
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
      }

      cells.add(
        GestureDetector(
          key: ValueKey('habit_calendar_day_$key'),
          onTap: () => _handleDayTap(date),
          child: Container(
            margin: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: isSelected
                    ? colorScheme.primary
                    : isToday
                    ? colorScheme.primary.withValues(alpha: 0.45)
                    : hasLit
                    ? colorScheme.primary.withValues(alpha: 0.22)
                    : Colors.transparent,
                width: isSelected ? 2 : 1,
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Stack(
                children: [
                  Container(color: bg),
                  if (!hasLit &&
                      ratio > 0.0 &&
                      aggregate == _DayAggregate.partial)
                    Align(
                      alignment: Alignment.bottomCenter,
                      child: FractionallySizedBox(
                        heightFactor: ratio,
                        widthFactor: 1.0,
                        child: Container(
                          color: colorScheme.tertiaryContainer.withValues(
                            alpha: 0.6,
                          ),
                        ),
                      ),
                    ),
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 2,
                        vertical: 2,
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            '$day',
                            style: TextStyle(
                              fontSize: hasLit ? 11.5 : 13,
                              fontWeight: isToday || isSelected
                                  ? FontWeight.w800
                                  : FontWeight.w500,
                              color: isFuture
                                  ? colorScheme.onSurfaceVariant.withValues(
                                      alpha: 0.38,
                                    )
                                  : isSelected
                                  ? colorScheme.primary
                                  : colorScheme.onSurface,
                            ),
                          ),
                          if (hasLit) ...[
                            const SizedBox(height: 1),
                            Flexible(
                              child: _buildDayLitIcons(litIcons, colorScheme),
                            ),
                          ] else ...[
                            const SizedBox(height: 2),
                            Container(
                              width: 6,
                              height: 6,
                              decoration: BoxDecoration(
                                color:
                                    aggregate == _DayAggregate.none ||
                                        aggregate == _DayAggregate.future
                                    ? Colors.transparent
                                    : dot,
                                shape: BoxShape.circle,
                              ),
                            ),
                          ],
                        ],
                      ),
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
      padding: EdgeInsets.zero,
      primary: false,
      crossAxisCount: 7,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: 0.84,
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
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
          ),
        ],
      );
    }

    return Wrap(
      spacing: 16,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        item(colorScheme.tertiary, '全部完成'),
        item(colorScheme.tertiary.withValues(alpha: 0.5), '部分完成'),
        item(colorScheme.outline, '已跳过'),
        Text(
          '点击日期可点亮习惯图标',
          style: TextStyle(
            fontSize: 11,
            color: colorScheme.primary,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  // ── 选中日明细（全部习惯列表） ──────────────────────────
  Widget _buildSelectedDayDetail() {
    final colorScheme = Theme.of(context).colorScheme;
    final dayLabel =
        '${_selectedDay.month} 月 ${_selectedDay.day} 日'
        ' · 周${'一二三四五六日'[_selectedDay.weekday - 1]}';
    final rows = <Widget>[];
    final key = HabitRuleResolver.dayKey(_selectedDay);

    for (final goal in _goals) {
      final dayProgress = _dayByHabitAndLogicalDate[goal.uuid]?[key];
      if (dayProgress == null) continue;
      if (goal.isArchived && !_hasHistoricalRecord(dayProgress)) continue;
      rows.add(_buildDayRow(goal, dayProgress));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                dayLabel,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: colorScheme.onSurface,
                ),
              ),
            ),
            if (!_isFutureDate(_selectedDay))
              FilledButton.tonalIcon(
                onPressed: () => _openLightUpSheet(_selectedDay),
                icon: const Icon(Icons.auto_awesome_rounded, size: 15),
                label: const Text('点亮图标', style: TextStyle(fontSize: 12.5)),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  minimumSize: const Size(0, 32),
                ),
              ),
          ],
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
    return progress.hasRecord ||
        progress.goalMet ||
        progress.isSkipped ||
        progress.isFrozen;
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
      HabitDayStatus.frozen => (colorScheme.primary, '免扣保护'),
    };

    final dayKey = HabitRuleResolver.dayKey(day.logicalDate);
    final dayCheckIns =
        _checkInsByHabitAndLogicalDate[goal.uuid]?[dayKey] ??
        const <HabitCheckIn>[];
    final drinkSummary = HabitDrinkLogService.formatDrinkSummary(dayCheckIns);
    final isDrinkChoice = HabitDrinkLogService.isDrinkChoiceHabit(goal);
    final rawDetail = _dayValueText(goal, day);
    final detail = drinkSummary.isNotEmpty
        ? (isDrinkChoice ? '破戒：$drinkSummary' : drinkSummary)
        : (isDrinkChoice && status == HabitDayStatus.met
              ? '没喝饮料 · 打卡成功'
              : rawDetail);
    final rowIcon = drinkSummary.isNotEmpty
        ? HabitDrinkLogService.extractDrinkIcons(dayCheckIns).first
        : (goal.icon.isNotEmpty ? goal.icon : '🎯');

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          InkWell(
            onTap: () {
              setState(() => _selectedHabitUuid = goal.uuid);
            },
            borderRadius: BorderRadius.circular(8),
            child: Text(rowIcon, style: const TextStyle(fontSize: 22)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: InkWell(
              onTap: () {
                setState(() => _selectedHabitUuid = goal.uuid);
              },
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
                          horizontal: 6,
                          vertical: 2,
                        ),
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
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          if (!isDrinkChoice) ...[
            _buildFreezeButton(goal, day, colorScheme),
            const SizedBox(width: 8),
            if (goal.sourceType == HabitSourceType.recurringTodo) ...[
              _buildMakeUpButton(goal, day),
              const SizedBox(width: 8),
              _buildSkipButton(goal, day, colorScheme, label),
            ] else
              _buildSkipButton(goal, day, colorScheme, label),
          ] else if (!_isFutureDate(day.logicalDate)) ...[
            OutlinedButton(
              onPressed: () => _openDrinkPickerForDate(goal, day.logicalDate),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                minimumSize: const Size(0, 32),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text('记录饮品'),
            ),
            const SizedBox(width: 6),
            _buildSkipButton(goal, day, colorScheme, label),
          ],
        ],
      ),
    );
  }

  /// 计划内且非未来日期支持「使用免扣卡 / 取消免扣守护」。
  Widget _buildFreezeButton(
    HabitGoal goal,
    HabitDayProgress day,
    ColorScheme colorScheme,
  ) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    if (day.logicalDate.isAfter(today) || !day.progress.isPlanned) {
      return const SizedBox.shrink();
    }
    final isFrozen = day.status == HabitDayStatus.frozen;
    final isMissed = day.status == HabitDayStatus.missed;
    if (!isFrozen && !isMissed) return const SizedBox.shrink();

    return OutlinedButton.icon(
      onPressed: () async {
        final rule = HabitRuleResolver.effectiveRule(
          _rulesByHabit[goal.uuid] ?? const [],
          day.logicalDate,
        );
        if (rule == null) return;
        if (isFrozen) {
          final checkIns = await HabitRepository.getCheckIns(
            habitUuid: goal.uuid,
          );
          final dateKey = HabitRuleResolver.dayKey(day.logicalDate);
          final freezeCheckIn = checkIns
              .where(
                (c) =>
                    !c.isDeleted &&
                    c.logicalDate == dateKey &&
                    c.source == HabitCheckInSource.freeze,
              )
              .firstOrNull;
          if (freezeCheckIn != null) {
            await HabitFreezeService.revokeFreeze(
              goal: goal,
              freezeCheckIn: freezeCheckIn,
            );
            _loadData();
          }
        } else {
          final checkIns = await HabitRepository.getCheckIns(
            habitUuid: goal.uuid,
          );
          final validation = await HabitFreezeService.canApplyFreeze(
            goal: goal,
            rule: rule,
            logicalDate: day.logicalDate,
            checkIns: checkIns,
            rules: _rulesByHabit[goal.uuid],
          );
          if (!validation.canApply) {
            if (mounted) {
              AppSnackBars.showSnackBar(
                context,
                SnackBar(content: Text(validation.reason ?? '当前条件不满足')),
              );
            }
            return;
          }
          await HabitFreezeService.applyFreeze(
            goal: goal,
            rule: rule,
            logicalDate: day.logicalDate,
            username: widget.username,
            rules: _rulesByHabit[goal.uuid],
          );
          _loadData();
        }
      },
      icon: Icon(
        Icons.shield_outlined,
        size: 13,
        color: isFrozen ? colorScheme.secondary : colorScheme.primary,
      ),
      label: Text(isFrozen ? '取消免扣' : '用免扣卡'),
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        minimumSize: const Size(0, 32),
        foregroundColor: isFrozen ? colorScheme.secondary : colorScheme.primary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
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
        foregroundColor: skipped
            ? colorScheme.onSurfaceVariant
            : colorScheme.outline,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
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
      case HabitSourceType.durationCheckIn:
        return HabitText.durationProgressForGoal(goal, progress);
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
        foregroundColor: met
            ? colorScheme.onSurfaceVariant
            : colorScheme.primary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      child: Text(met ? '撤销' : '补卡'),
    );
  }
}

enum _DayAggregate { none, allMet, partial, noneMet, skipped, future }
