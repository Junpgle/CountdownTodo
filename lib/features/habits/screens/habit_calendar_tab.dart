import 'package:flutter/material.dart';

import '../../../utils/app_dialogs.dart';
import '../../../utils/page_transitions.dart';
import '../../../utils/time_utils.dart';
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
import '../widgets/habit_emoji_text.dart';
import '../widgets/habit_format.dart';
import 'habit_detail_screen.dart';
import 'habit_edit_screen.dart';

part 'habit_calendar/habit_calendar_shared.dart';
part 'habit_calendar/habit_calendar_single_view.dart';
part 'habit_calendar/habit_calendar_overview.dart';

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

  void _mutateState(VoidCallback fn) => setState(fn);

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
}

enum _DayAggregate { none, allMet, partial, noneMet, skipped, future }
