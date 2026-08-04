import 'dart:ui';
import 'package:flutter/material.dart';

import '../../../screens/pomodoro_screen.dart';
import '../../../services/pomodoro_control_service.dart';
import '../../../services/pomodoro_service.dart';
import '../../../utils/page_transitions.dart';
import '../models/habit_goal.dart';
import '../models/habit_goal_rule.dart';
import '../models/habit_progress.dart';
import '../services/habit_day_loader.dart';
import '../services/habit_sleep_duration_service.dart';
import '../widgets/habit_card.dart';
import 'habit_detail_screen.dart';
import 'habit_edit_screen.dart';

/// 习惯中心「今日」标签页：今日概览 + 全部习惯卡片。
class HabitTodayTab extends StatefulWidget {
  final String username;

  /// 教程要高亮的第一张习惯卡片。
  final GlobalKey? coachTargetKey;

  /// 数据变化后自增，触发重新加载。
  final int reloadTick;

  /// 今日板块顶部的推广 Banner。
  final Widget? topBanner;

  /// 内部数据变化回调（如快速打卡）。
  final VoidCallback? onChanged;

  const HabitTodayTab({
    super.key,
    required this.username,
    this.coachTargetKey,
    this.reloadTick = 0,
    this.topBanner,
    this.onChanged,
  });

  @override
  State<HabitTodayTab> createState() => _HabitTodayTabState();
}

class _HabitTodayTabState extends State<HabitTodayTab> {
  HabitDaySnapshot? _snapshot;
  final Map<String, GlobalKey> _cardKeys = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void didUpdateWidget(HabitTodayTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.reloadTick != widget.reloadTick) {
      _loadData();
    }
  }

  Future<void> _loadData() async {
    if (!mounted) return;
    setState(() => _loading = true);
    final snapshot = await HabitDayLoader.loadForDate(DateTime.now());
    if (mounted) {
      setState(() {
        _snapshot = snapshot;
        _loading = false;
      });
    }
  }

  void _handleChanged() {
    widget.onChanged?.call();
    _loadData();
  }

  GlobalKey _cardKeyFor(HabitGoal goal) {
    return _cardKeys.putIfAbsent(goal.uuid, GlobalKey.new);
  }

  Future<void> _openDetail(
    HabitGoal goal, {
    GlobalKey? sourceKey,
  }) async {
    final page = HabitDetailScreen(
      goal: goal,
      username: widget.username,
    );
    final changed = sourceKey == null
        ? await Navigator.of(context).push(
            PageTransitions.material(builder: (_) => page),
          )
        : await PageTransitions.pushFromRect(
            context: context,
            page: page,
            sourceKey: sourceKey,
            sourceBorderRadius: BorderRadius.circular(24),
          );
    if (changed == true && mounted) _handleChanged();
  }

  Future<void> _openCreate() async {
    final created = await Navigator.of(context).push(
      PageTransitions.material(
        builder: (_) => const HabitEditScreen(),
      ),
    );
    if (created == true && mounted) _handleChanged();
  }

  /// 时长型：启动专注并跳转番茄钟，默认时长为习惯设置的默认时长。
  Future<void> _startFocus(HabitGoal goal) async {
    final tagUuids = goal.sourceType == HabitSourceType.pomodoroTag
        ? goal.sourceIds
        : const <String>[];
    final running = await PomodoroService.loadRunState();
    if (running != null &&
        (running.phase == PomodoroPhase.focusing ||
            running.phase == PomodoroPhase.breaking)) {
      if (!mounted) return;
      await Navigator.of(context).push(
        PageTransitions.material(
          builder: (_) => PomodoroScreen(username: widget.username),
        ),
      );
      return;
    }
    try {
      final settings = await PomodoroService.getSettings();
      await PomodoroControlService.startFocus(
        settings: settings,
        tagUuids: tagUuids,
        durationMinutes: goal.defaultFocusMinutes,
      );
      if (!mounted) return;
      await Navigator.of(context).push(
        PageTransitions.material(
          builder: (_) => PomodoroScreen(username: widget.username),
        ),
      );
      if (mounted) _handleChanged();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('启动专注失败: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final Widget content;
    if (_loading) {
      content = const Center(child: CircularProgressIndicator());
    } else {
      final snapshot = _snapshot;
      if (snapshot == null) {
        content = const SizedBox.shrink();
      } else if (snapshot.isEmpty) {
        content = _buildEmpty();
      } else {
        content = RefreshIndicator(
          onRefresh: _loadData,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 840),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                children: [
                  _buildSummaryCard(snapshot),
                  const SizedBox(height: 16),
                  ..._buildGroupedCards(snapshot),
                ],
              ),
            ),
          ),
        );
      }
    }

    return Column(
      children: [
        if (widget.topBanner != null) widget.topBanner!,
        Expanded(child: content),
      ],
    );
  }

  /// 按设计文档 11.2 分组：清晨 / 白天 / 晚间 / 本周（本月）目标。
  List<Widget> _buildGroupedCards(HabitDaySnapshot snapshot) {
    final groups = <(String, IconData, List<HabitGoal>)>[
      ('清晨打卡', Icons.wb_twilight_rounded, []),
      ('白天打卡', Icons.wb_sunny_rounded, []),
      ('晚间打卡', Icons.nightlight_round, []),
      ('本周目标', Icons.event_repeat_rounded, []),
      ('本月目标', Icons.calendar_month_rounded, []),
    ];
    for (final goal in snapshot.goals) {
      final rule = snapshot.ruleOf(goal);
      final groupIndex = _groupIndex(goal, rule);
      groups[groupIndex].$3.add(goal);
    }

    final colorScheme = Theme.of(context).colorScheme;
    final firstGoalUuid =
        snapshot.goals.isEmpty ? null : snapshot.goals.first.uuid;
    final children = <Widget>[];
    for (final (label, icon, goals) in groups) {
      if (goals.isEmpty) continue;
      children.add(Padding(
        padding: const EdgeInsets.only(top: 16, bottom: 12),
        child: Row(
          children: [
            Icon(icon, size: 20, color: colorScheme.primary),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: colorScheme.onSurface,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '${goals.length}',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ));
      children.add(
        LayoutBuilder(
          builder: (context, constraints) {
            final crossAxisCount = constraints.maxWidth > 600 ? 2 : 1;
            const spacing = 12.0;
            final width =
                (constraints.maxWidth - spacing * (crossAxisCount - 1)) /
                    crossAxisCount;
            return Wrap(
              spacing: spacing,
              runSpacing: spacing,
              children: goals
                  .map((goal) => SizedBox(
                        key: goal.uuid == firstGoalUuid
                            ? widget.coachTargetKey ?? ValueKey(goal.uuid)
                            : ValueKey(goal.uuid),
                        width: width,
                        child: HabitCard(
                          goal: goal,
                          rule: snapshot.ruleOf(goal),
                          dayProgress: _dayProgress(snapshot, goal),
                          username: widget.username,
                          onChanged: _handleChanged,
                          onStartFocus: _startFocus,
                          animationKey: _cardKeyFor(goal),
                          onTap: () => _openDetail(
                            goal,
                            sourceKey: _cardKeyFor(goal),
                          ),
                        ),
                      ))
                  .toList(),
            );
          },
        ),
      );
      children.add(const SizedBox(height: 16));
    }
    return children;
  }

  /// 目标时间分组：清晨 05:00-10:00，晚间 >= 21:00 或 < 05:00（深夜），其余归白天；
  /// 时长型按统计周期归入本周/本月目标。
  int _groupIndex(HabitGoal goal, HabitGoalRuleRevision rule) {
    if (goal.sourceType == HabitSourceType.pomodoroTag ||
        goal.sourceType == HabitSourceType.durationCheckIn) {
      switch (rule.periodType) {
        case HabitPeriodType.weekly:
          return 3;
        case HabitPeriodType.monthly:
          return 4;
        case HabitPeriodType.daily:
        case HabitPeriodType.weekdays:
        case HabitPeriodType.custom:
          return 1;
      }
    }
    if (goal.sourceType == HabitSourceType.timeCheckIn) {
      final minute = rule.targetTimeMinute ?? 0;
      if (minute < 5 * 60 || minute >= 21 * 60) return 2; // 深夜或晚间归入晚间打卡
      if (minute >= 5 * 60 && minute < 10 * 60) return 0; // 05:00-10:00 归入清晨打卡
    }
    return 1;
  }

  HabitDayProgress _dayProgress(HabitDaySnapshot snapshot, HabitGoal goal) {
    final progress = snapshot.progressOf(goal);
    return HabitDayProgress(
      habit: goal,
      logicalDate: HabitSleepDurationService.displayLogicalDateFor(
        goal,
        DateTime.now(),
      ),
      status: progress.dayStatus,
      progress: progress,
    );
  }

  Widget _buildSummaryCard(HabitDaySnapshot snapshot) {
    final colorScheme = Theme.of(context).colorScheme;
    int planned = 0;
    int met = 0;
    for (final goal in snapshot.goals) {
      final progress = snapshot.progressOf(goal);
      if (!progress.isPlanned) continue;
      planned++;
      if (progress.goalMet) met++;
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(28),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                colorScheme.primaryContainer.withValues(alpha: 0.7),
                colorScheme.tertiaryContainer.withValues(alpha: 0.3),
              ],
            ),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(
              color: colorScheme.onSurface.withValues(alpha: 0.08),
              width: 1,
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '今日进度',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      planned == 0 ? '今天没有计划' : '$met / $planned 已完成',
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        color: colorScheme.onSurface,
                        letterSpacing: -0.5,
                      ),
                    ),
                  ],
                ),
              ),
              if (planned > 0)
                SizedBox(
                  width: 64,
                  height: 64,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      CircularProgressIndicator(
                        value: planned == 0 ? 0 : met / planned,
                        strokeWidth: 8,
                        strokeCap: StrokeCap.round,
                        backgroundColor:
                            colorScheme.onSurface.withValues(alpha: 0.1),
                        valueColor: AlwaysStoppedAnimation(colorScheme.primary),
                      ),
                      Center(
                        child: Text(
                          planned == 0
                              ? '0%'
                              : '${(met / planned * 100).round()}%',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: colorScheme.onSurface,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmpty() {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.auto_awesome_outlined,
            size: 56,
            color: colorScheme.outline.withValues(alpha: 0.6),
          ),
          const SizedBox(height: 16),
          Text(
            '还没有习惯\n创建第一个习惯，开始每日打卡吧',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              height: 1.6,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _openCreate,
            icon: const Icon(Icons.add_rounded),
            label: const Text('新建习惯'),
          ),
        ],
      ),
    );
  }
}
