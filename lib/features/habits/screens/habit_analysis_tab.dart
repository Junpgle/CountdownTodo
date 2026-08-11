import 'package:flutter/material.dart';

import '../../../utils/page_transitions.dart';
import '../models/habit_goal.dart';
import '../models/habit_goal_rule.dart';
import '../models/habit_progress.dart';
import '../repositories/habit_repository.dart';
import '../services/habit_progress_calculator.dart';
import '../services/habit_rule_resolver.dart';
import '../services/habit_sleep_goal_resolver.dart';
import '../services/habit_streak_service.dart';
import '../widgets/habit_format.dart';
import 'habit_detail_screen.dart';

/// 习惯中心「分析」标签页：各习惯的连续与完成率统计。
class HabitAnalysisTab extends StatefulWidget {
  final String username;

  /// 数据变化后自增，触发重新加载。
  final int reloadTick;

  const HabitAnalysisTab({
    super.key,
    required this.username,
    this.reloadTick = 0,
  });

  @override
  State<HabitAnalysisTab> createState() => _HabitAnalysisTabState();
}

class _HabitAnalysisTabState extends State<HabitAnalysisTab> {
  List<HabitGoal> _goals = [];
  final Map<String, GlobalKey> _cardKeys = {};
  Map<String, List<HabitGoalRuleRevision>> _rulesByHabit = {};
  Map<String, HabitStreakSummary> _summaries = {};

  /// 本周（周一至今天）达标数 / 计划数。
  int _weekPlanned = 0;
  int _weekMet = 0;

  /// 近 30 天每日达标习惯数（index 0 = 29 天前）。
  List<int> _monthTrend = [];

  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void didUpdateWidget(HabitAnalysisTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.reloadTick != widget.reloadTick) {
      _loadData();
    }
  }

  Future<void> _loadData() async {
    if (!mounted) return;
    setState(() => _loading = true);
    final goals = HabitSleepGoalResolver.forDisplay(
      await HabitRepository.getActiveGoals(),
    );
    final allRules = await HabitRepository.getRules();
    final rulesByHabit = <String, List<HabitGoalRuleRevision>>{};
    final summaries = <String, HabitStreakSummary>{};

    for (final goal in goals) {
      final rules = allRules.where((r) => r.habitUuid == goal.uuid).toList()
        ..sort((a, b) =>
            (a.effectiveFromDate ?? '').compareTo(b.effectiveFromDate ?? ''));
      rulesByHabit[goal.uuid] = rules;
    }

    // 并行统计各习惯，避免串行拖慢分析页加载。
    final futures = <Future<void>>[];
    for (final goal in goals) {
      final rules = rulesByHabit[goal.uuid] ?? const [];
      if (rules.isEmpty) continue;
      futures.add(() async {
        summaries[goal.uuid] = await HabitStreakService.summarize(
          habit: goal,
          rules: rules,
        );
      }());
    }
    // 本周进度 + 近 30 天趋势（并行计算）。
    futures.add(() async {
      final result = await _computeWeekProgress(goals, rulesByHabit);
      _weekPlanned = result.$1;
      _weekMet = result.$2;
    }());
    futures.add(() async {
      _monthTrend = await _computeMonthTrend(goals, rulesByHabit);
    }());
    await Future.wait(futures);

    if (mounted) {
      setState(() {
        _goals = goals;
        _rulesByHabit = rulesByHabit;
        _summaries = summaries;
        _loading = false;
      });
    }
  }

  /// 本周进度：日粒度习惯按周一至今逐日统计；周粒度习惯整周达标计入一次；
  /// 月粒度习惯不计入本周。
  Future<(int, int)> _computeWeekProgress(
    List<HabitGoal> goals,
    Map<String, List<HabitGoalRuleRevision>> rulesByHabit,
  ) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final monday = today.subtract(Duration(days: today.weekday - 1));
    var planned = 0;
    var met = 0;

    for (final goal in goals) {
      final rules = rulesByHabit[goal.uuid] ?? const [];
      if (rules.isEmpty) continue;
      final rule = HabitRuleResolver.effectiveRule(rules, today);
      if (rule == null) continue;

      if (rule.periodType == HabitPeriodType.monthly) continue;

      if (rule.periodType == HabitPeriodType.weekly) {
        // 周周期：仅在本周结束时判定达标。
        if (today.weekday == DateTime.sunday) {
          final progress = await HabitProgressCalculator.computePeriod(
            habit: goal,
            rules: rules,
            logicalDate: today,
          );
          planned++;
          if (progress.goalMet) met++;
        }
        continue;
      }

      final range = await HabitProgressCalculator.computeRange(
        habit: goal,
        rules: rules,
        from: monday,
        to: today,
      );
      for (final day in range) {
        if (!day.progress.isPlanned) continue;
        planned++;
        if (day.progress.goalMet) met++;
      }
    }
    return (planned, met);
  }

  /// 近 30 天每日达标习惯数（从 29 天前到今天）。
  Future<List<int>> _computeMonthTrend(
    List<HabitGoal> goals,
    Map<String, List<HabitGoalRuleRevision>> rulesByHabit,
  ) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final from = today.subtract(const Duration(days: 29));
    final trend = List<int>.filled(30, 0);

    for (final goal in goals) {
      final rules = rulesByHabit[goal.uuid] ?? const [];
      if (rules.isEmpty) continue;
      final range = await HabitProgressCalculator.computeRange(
        habit: goal,
        rules: rules,
        from: from,
        to: today,
      );
      for (final day in range) {
        if (!day.progress.isPlanned || !day.progress.goalMet) continue;
        final index = day.logicalDate.difference(from).inDays;
        if (index >= 0 && index < 30) trend[index]++;
      }
    }
    return trend;
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_goals.isEmpty) {
      return Center(
        child: Text(
          '暂无统计数据',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _loadData,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 840),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            children: [
              LayoutBuilder(
                builder: (context, constraints) {
                  if (constraints.maxWidth > 600) {
                    return IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(child: _buildWeekProgressCard()),
                          const SizedBox(width: 12),
                          Expanded(flex: 2, child: _buildMonthTrendCard()),
                        ],
                      ),
                    );
                  }
                  return Column(
                    children: [
                      _buildWeekProgressCard(),
                      const SizedBox(height: 12),
                      _buildMonthTrendCard(),
                    ],
                  );
                },
              ),
              const SizedBox(height: 12),
              LayoutBuilder(
                builder: (context, constraints) {
                  if (constraints.maxWidth > 600) {
                    return Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: _goals
                          .map((g) => SizedBox(
                                width: (constraints.maxWidth - 12) / 2,
                                child: _buildStatCard(g),
                              ))
                          .toList(),
                    );
                  }
                  return Column(
                    children: _goals
                        .map((goal) => Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: _buildStatCard(goal),
                            ))
                        .toList(),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 本周进度卡（设计文档 9.x：本周进度）。
  Widget _buildWeekProgressCard() {
    final colorScheme = Theme.of(context).colorScheme;
    final ratio =
        _weekPlanned == 0 ? 0.0 : (_weekMet / _weekPlanned).clamp(0.0, 1.0);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            colorScheme.primaryContainer,
            colorScheme.secondaryContainer,
          ],
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '本周进度',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: colorScheme.onPrimaryContainer,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _weekPlanned == 0
                      ? '本周还没有计划'
                      : '$_weekMet / $_weekPlanned 习惯达标',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.3,
                    color: colorScheme.onSurface,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            width: 60,
            height: 60,
            child: Stack(
              fit: StackFit.expand,
              children: [
                CircularProgressIndicator(
                  value: ratio,
                  strokeWidth: 7,
                  strokeCap: StrokeCap.round,
                  backgroundColor: colorScheme.surface.withValues(alpha: 0.4),
                  valueColor: AlwaysStoppedAnimation(colorScheme.primary),
                ),
                Center(
                  child: Text(
                    '${(ratio * 100).round()}%',
                    style: TextStyle(
                      fontSize: 13,
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
    );
  }

  /// 近 30 天每日达标数热力图 (Heatmap)
  Widget _buildMonthTrendCard() {
    final colorScheme = Theme.of(context).colorScheme;
    final maxCount =
        _monthTrend.isEmpty ? 0 : _monthTrend.reduce((a, b) => a > b ? a : b);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final first = today.subtract(const Duration(days: 29));
    final firstWeekday = first.weekday; // 1 = Monday, 7 = Sunday

    // We arrange the 30 days into columns of 7 (Mon-Sun).
    // Pad empty spaces before the first day.
    final leadingEmpty = firstWeekday - 1;
    final totalCells = leadingEmpty + 30;
    final totalColumns = (totalCells / 7).ceil();

    final columns = <Widget>[];
    for (int col = 0; col < totalColumns; col++) {
      final cells = <Widget>[];
      for (int row = 0; row < 7; row++) {
        final cellIndex = col * 7 + row;
        final dayIndex = cellIndex - leadingEmpty;

        if (dayIndex < 0 || dayIndex >= 30) {
          // Empty placeholder
          cells.add(Container(
            width: 12,
            height: 12,
            margin: const EdgeInsets.all(2),
            color: Colors.transparent,
          ));
        } else {
          final value = _monthTrend[dayIndex];
          final isToday = dayIndex == 29;

          Color cellColor;
          if (value == 0) {
            cellColor =
                colorScheme.surfaceContainerHighest.withValues(alpha: 0.5);
          } else {
            // Calculate opacity based on intensity
            final intensity =
                maxCount == 0 ? 1.0 : (value / maxCount).clamp(0.2, 1.0);
            cellColor = colorScheme.primary.withValues(alpha: intensity);
          }
          if (isToday) {
            cellColor = colorScheme.tertiary; // Highlight today
          }

          cells.add(Container(
            width: 12,
            height: 12,
            margin: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              color: cellColor,
              borderRadius: BorderRadius.circular(3),
              border: isToday
                  ? Border.all(color: colorScheme.onTertiary, width: 1)
                  : null,
            ),
          ));
        }
      }
      columns.add(Column(
        mainAxisSize: MainAxisSize.min,
        children: cells,
      ));
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '打卡热力图 (近 30 天)',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Weekday labels
              Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  for (int i = 0; i < 7; i++)
                    Container(
                      height: 16,
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.only(right: 8),
                      child: Text(
                        i % 2 == 0
                            ? ['一', '二', '三', '四', '五', '六', '日'][i]
                            : '',
                        style: TextStyle(
                          fontSize: 9,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                ],
              ),
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  reverse: true, // Scroll to end (today)
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: columns,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${first.month}/${first.day}',
                style: TextStyle(
                  fontSize: 10.5,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              Text(
                '今天',
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(HabitGoal goal) {
    final colorScheme = Theme.of(context).colorScheme;
    final summary = _summaries[goal.uuid];
    final rules = _rulesByHabit[goal.uuid] ?? const [];
    final rule = rules.isNotEmpty
        ? HabitRuleResolver.effectiveRule(rules, DateTime.now())
        : null;
    final periodUnit = _periodUnit(rule);

    return Material(
      key: _cardKeys.putIfAbsent(goal.uuid, GlobalKey.new),
      color: colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () async {
          final changed = await PageTransitions.pushFromRect(
            context: context,
            page: HabitDetailScreen(
              goal: goal,
              username: widget.username,
            ),
            sourceKey: _cardKeys[goal.uuid]!,
            sourceBorderRadius: BorderRadius.circular(16),
          );
          if (changed == true && mounted) _loadData();
        },
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(goal.icon.isNotEmpty ? goal.icon : '🎯',
                      style: const TextStyle(fontSize: 20)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      goal.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: colorScheme.onSurface,
                      ),
                    ),
                  ),
                  if (summary != null)
                    _buildStreakBadge(
                      summary.currentStreak,
                      rule?.periodType ?? HabitPeriodType.daily,
                    ),
                ],
              ),
              const SizedBox(height: 12),
              if (summary == null)
                Text(
                  '暂无统计数据',
                  style: TextStyle(
                    fontSize: 12,
                    color: colorScheme.onSurfaceVariant,
                  ),
                )
              else ...[
                Row(
                  children: [
                    _statItem(
                      '当前连续',
                      '${summary.currentStreak} $periodUnit',
                    ),
                    _statItem('最长连续', '${summary.longestStreak} $periodUnit'),
                    _statItem('近 7 周期', _percent(summary.rate7)),
                    _statItem('近 30 周期', _percent(summary.rate30)),
                  ],
                ),
                if (_hasExtras(goal, summary)) ...[
                  const SizedBox(height: 10),
                  _buildExtrasRow(goal, summary),
                ],
                const SizedBox(height: 12),
                _buildInsightText(goal, summary),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStreakBadge(int streak, HabitPeriodType periodType) {
    final colorScheme = Theme.of(context).colorScheme;
    final unit = _periodUnit(
      HabitGoalRuleRevision(
        habitUuid: '',
        effectiveFromDate: '',
        periodType: periodType,
      ),
    );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: colorScheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.local_fire_department_rounded,
              size: 14, color: colorScheme.tertiary),
          const SizedBox(width: 4),
          Text(
            '连续 $streak $unit',
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: colorScheme.onTertiaryContainer,
            ),
          ),
        ],
      ),
    );
  }

  Widget _statItem(String label, String value) {
    final colorScheme = Theme.of(context).colorScheme;
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 10.5,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            value,
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
              color: colorScheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }

  String _periodUnit(HabitGoalRuleRevision? rule) {
    if (rule == null) return '天';
    switch (rule.periodType) {
      case HabitPeriodType.weekly:
        return '周';
      case HabitPeriodType.monthly:
        return '月';
      default:
        return '天';
    }
  }

  bool _hasExtras(HabitGoal goal, HabitStreakSummary summary) {
    switch (goal.sourceType) {
      case HabitSourceType.recurringTodo:
        return summary.weakestWeekday != null;
      case HabitSourceType.pomodoroTag:
        return summary.averageDuration != null ||
            summary.weakestWeekday != null;
      case HabitSourceType.durationCheckIn:
        return summary.averageDuration != null ||
            summary.weakestWeekday != null;
      case HabitSourceType.quantityCheckIn:
        return summary.averageValue != null || summary.weakestWeekday != null;
      case HabitSourceType.timeCheckIn:
        return summary.averageTimeMinute != null ||
            summary.onTimeRate != null ||
            summary.weakestWeekday != null;
    }
  }

  Widget _buildExtrasRow(HabitGoal goal, HabitStreakSummary summary) {
    final colorScheme = Theme.of(context).colorScheme;
    final extras = <String>[];

    switch (goal.sourceType) {
      case HabitSourceType.recurringTodo:
        break;
      case HabitSourceType.pomodoroTag:
        if (summary.averageDuration != null) {
          extras.add('日均 ${(summary.averageDuration! / 60).round()} 分钟');
        }
      case HabitSourceType.durationCheckIn:
        if (summary.averageDuration != null) {
          extras.add(
              '平均 ${(summary.averageDuration! / 3600).toStringAsFixed(1)} 小时');
        }
      case HabitSourceType.quantityCheckIn:
        if (summary.averageValue != null) {
          final unit = _unitOf(goal);
          final value = summary.averageValue!;
          final text = value == value.roundToDouble()
              ? value.round().toString()
              : value.toStringAsFixed(1);
          extras.add('日均 $text$unit');
        }
      case HabitSourceType.timeCheckIn:
        if (summary.averageTimeMinute != null) {
          final minute = summary.averageTimeMinute!.round();
          extras.add('平均 ${HabitText.targetTime(minute)}');
        }
        if (summary.onTimeRate != null) {
          extras.add('准时率 ${_percent(summary.onTimeRate!)}');
        }
    }
    if (summary.weakestWeekday != null) {
      extras.add('易中断：周${'一二三四五六日'[summary.weakestWeekday!]}');
    }

    return Wrap(
      spacing: 8,
      runSpacing: 6,
      children: extras
          .map(
            (text) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                text,
                style: TextStyle(
                  fontSize: 10.5,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          )
          .toList(),
    );
  }

  String _unitOf(HabitGoal goal) {
    final rules = _rulesByHabit[goal.uuid] ?? const [];
    final rule = rules.isNotEmpty
        ? HabitRuleResolver.effectiveRule(rules, DateTime.now())
        : null;
    return rule?.unit ?? '';
  }

  String _percent(double value) => '${(value * 100).round()}%';

  Widget _buildInsightText(HabitGoal goal, HabitStreakSummary summary) {
    final colorScheme = Theme.of(context).colorScheme;
    String insight = '';

    if (summary.currentStreak > 7) {
      insight = '太棒了！你已经连续坚持超过一周，继续保持！🔥';
    } else if (summary.weakestWeekday != null) {
      final weekday = '一二三四五六日'[summary.weakestWeekday!];
      insight = '小提示：周$weekday的达成率偏低，那天可以多给自己设点提醒哦。💡';
    } else if (summary.rate30 >= 0.8) {
      insight = '近 30 天表现极其优秀，习惯已经快要刻入你的 DNA 里啦！🧬';
    } else if (summary.rate7 == 0 && summary.rate30 > 0) {
      insight = '最近似乎有些懈怠，今天是重新开始的好日子，加油！💪';
    } else {
      insight = '保持节奏，每天的一小步，都是未来的一大步。✨';
    }

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(
            Icons.auto_awesome,
            size: 14,
            color: colorScheme.primary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              insight,
              style: TextStyle(
                fontSize: 11.5,
                color: colorScheme.onSurfaceVariant,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
