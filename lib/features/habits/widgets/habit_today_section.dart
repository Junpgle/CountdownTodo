import 'package:flutter/material.dart';

import '../../../screens/pomodoro_screen.dart';
import '../../../services/pomodoro_control_service.dart';
import '../../../services/pomodoro_service.dart';
import '../../../utils/page_transitions.dart';
import '../models/habit_goal.dart';
import '../models/habit_progress.dart';
import '../screens/habit_detail_screen.dart';
import '../services/habit_day_loader.dart';
import 'habit_card.dart';

/// 首页「今日习惯」卡片。
///
/// 展示当天各习惯进度与快捷操作；[refreshTrigger] 自增时重新加载。
class HabitTodaySection extends StatefulWidget {
  final String username;
  final bool isLight;

  /// 每次自增时触发重新加载（由首页 resumed 回调驱动）。
  final int refreshTrigger;

  /// 点击标题区域（跳转习惯中心）。
  final VoidCallback? onTap;

  /// 时长型习惯「开始专注」回调；为空时使用内置实现。
  final Future<void> Function(HabitGoal goal)? onStartFocus;

  /// 时长型习惯「查看记录」回调；为空时使用内置实现（跳转详情页）。
  final VoidCallback? onViewRecords;

  const HabitTodaySection({
    super.key,
    required this.username,
    this.isLight = false,
    this.refreshTrigger = 0,
    this.onTap,
    this.onStartFocus,
    this.onViewRecords,
  });

  @override
  State<HabitTodaySection> createState() => _HabitTodaySectionState();
}

class _HabitTodaySectionState extends State<HabitTodaySection> {
  HabitDaySnapshot? _snapshot;
  final Map<String, GlobalKey> _cardKeys = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void didUpdateWidget(HabitTodaySection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshTrigger != widget.refreshTrigger) {
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

  Future<void> _startFocus(HabitGoal goal) async {
    // 防御：仅时长型习惯绑定专注标签，其他类型或空标签直接打开专注页。
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
      if (mounted) _loadData();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('启动专注失败: $e')),
      );
    }
  }

  GlobalKey _cardKeyFor(HabitGoal goal) {
    return _cardKeys.putIfAbsent(goal.uuid, GlobalKey.new);
  }

  Future<void> _viewRecords(HabitGoal goal) async {
    await PageTransitions.pushFromRect(
      context: context,
      page: HabitDetailScreen(
        username: widget.username,
        goal: goal,
      ),
      sourceKey: _cardKeyFor(goal),
      sourceBorderRadius: BorderRadius.circular(24),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textColor = widget.isLight ? Colors.white : null;
    final subColor = widget.isLight
        ? Colors.white.withValues(alpha: 0.7)
        : colorScheme.onSurfaceVariant;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── 标题行 ──
        InkWell(
          onTap: widget.onTap,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: widget.isLight
                        ? Colors.white.withValues(alpha: 0.15)
                        : colorScheme.tertiary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.repeat_rounded,
                      size: 20,
                      color:
                          widget.isLight ? Colors.white : colorScheme.tertiary),
                ),
                const SizedBox(width: 10),
                Text(
                  '今日习惯',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                    color: textColor,
                  ),
                ),
                if (!_loading &&
                    _snapshot != null &&
                    _snapshot!.goals.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  _buildSummaryBadge(colorScheme),
                ],
                const Spacer(),
                if (widget.onTap != null)
                  Icon(Icons.chevron_right, size: 20, color: subColor),
              ],
            ),
          ),
        ),
        const SizedBox(height: 4),

        // ── 内容 ──
        if (_loading)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: CircularProgressIndicator(),
            ),
          )
        else if (_snapshot == null || _snapshot!.isEmpty)
          _buildEmpty(subColor)
        else ...[
          // 首页仅展示前 5 个，超出通过「查看全部」进入习惯中心。
          ..._snapshot!.goals.take(5).map((goal) => _buildCard(goal)),
          if (_snapshot!.goals.length > 5)
            Center(
              child: TextButton.icon(
                onPressed: widget.onTap,
                icon: Icon(Icons.apps_rounded, size: 16, color: subColor),
                label: Text(
                  '查看全部习惯（共 ${_snapshot!.goals.length} 个）',
                  style: TextStyle(fontSize: 12.5, color: subColor),
                ),
              ),
            ),
        ],
      ],
    );
  }

  /// 今日达标汇总徽章（如「2/3 达标」）。
  Widget _buildSummaryBadge(ColorScheme colorScheme) {
    final progressList =
        _snapshot!.progressByHabit.values.where((p) => p.isPlanned);
    final planned = progressList.length;
    final met = progressList.where((p) => p.goalMet).length;
    if (planned == 0) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: widget.isLight
              ? Colors.white.withValues(alpha: 0.2)
              : colorScheme.tertiaryContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          '${_snapshot!.goals.length} 个',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color:
                widget.isLight ? Colors.white : colorScheme.onTertiaryContainer,
          ),
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: widget.isLight
            ? Colors.white.withValues(alpha: 0.2)
            : met == planned
                ? colorScheme.tertiaryContainer
                : colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        '$met/$planned 达标',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: widget.isLight
              ? Colors.white
              : met == planned
                  ? colorScheme.onTertiaryContainer
                  : colorScheme.onSecondaryContainer,
        ),
      ),
    );
  }

  Widget _buildEmpty(Color subColor) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
      decoration: BoxDecoration(
        color: widget.isLight
            ? Colors.white.withValues(alpha: 0.15)
            : Theme.of(context)
                .colorScheme
                .surfaceContainerLow
                .withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: widget.isLight
              ? Colors.white.withValues(alpha: 0.2)
              : Theme.of(context).dividerColor.withValues(alpha: 0.4),
        ),
      ),
      child: Column(
        children: [
          Icon(Icons.auto_awesome_outlined,
              size: 30, color: subColor.withValues(alpha: 0.5)),
          const SizedBox(height: 8),
          Text(
            '还没有习惯，去创建第一个吧',
            style: TextStyle(color: subColor, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildCard(HabitGoal goal) {
    final progress = _snapshot!.progressOf(goal);
    final rule = _snapshot!.ruleOf(goal);
    final dayProgress = HabitDayProgress(
      habit: goal,
      logicalDate: DateTime.now(),
      status: progress.dayStatus,
      progress: progress,
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: HabitCard(
        animationKey: _cardKeyFor(goal),
        goal: goal,
        rule: rule,
        dayProgress: dayProgress,
        username: widget.username,
        onChanged: _loadData,
        onStartFocus: widget.onStartFocus ?? _startFocus,
        onViewRecords: widget.onViewRecords ?? () => _viewRecords(goal),
        onTap: () => _viewRecords(goal),
      ),
    );
  }
}
