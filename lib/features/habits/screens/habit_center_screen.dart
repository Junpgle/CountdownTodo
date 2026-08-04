import 'package:flutter/material.dart';

import '../../../features/thirty_day_challenge/repositories/thirty_day_challenge_repository.dart';
import '../../../features/thirty_day_challenge/screens/thirty_day_challenge_screen.dart';
import '../../../models.dart';
import '../../../services/pomodoro_service.dart';
import '../../../services/feature_tip_service.dart';
import '../../../storage_service.dart';
import '../../../utils/page_transitions.dart';
import '../../../widgets/coach_mark_overlay.dart';
import '../models/habit_checkin.dart';
import '../models/habit_goal.dart';
import '../repositories/habit_repository.dart';
import '../services/habit_sleep_log_migration_service.dart';
import '../widgets/habit_sleep_log_migration_card.dart';
import 'habit_analysis_tab.dart';
import 'habit_archived_screen.dart';
import 'habit_calendar_tab.dart';
import 'habit_edit_screen.dart';
import 'habit_today_tab.dart';

/// 习惯中心：今日 / 日历 / 分析 三个标签页。
class HabitCenterScreen extends StatefulWidget {
  final String username;
  final bool openSleepMigration;

  const HabitCenterScreen({
    super.key,
    required this.username,
    this.openSleepMigration = false,
  });

  @override
  State<HabitCenterScreen> createState() => _HabitCenterScreenState();
}

class _HabitCenterScreenState extends State<HabitCenterScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  /// 习惯数据变化后自增，通知各标签页重新加载。
  int _reloadTick = 0;
  final GlobalKey _archiveActionKey = GlobalKey();
  final GlobalKey _createActionKey = GlobalKey();
  final GlobalKey _navigationKey = GlobalKey();
  final GlobalKey _todayContentKey = GlobalKey();
  bool _showCoachMarks = false;
  bool _showChallengePromotion = false;
  HabitSleepLogMigrationProposal? _sleepLogMigration;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    // Listen to tab controller to update navigation rail selection
    _tabController.addListener(() {
      if (!mounted) return;
      setState(() {});
    });
    _loadChallengePromotion();
    _loadSleepLogMigration();
    if (widget.openSleepMigration) {
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _openSleepLogMigrationEntry());
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) => _checkCoachMarks());
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadChallengePromotion() async {
    final dismissed =
        await ThirtyDayChallengeRepository.isHabitCenterPromotionDismissed();
    if (!mounted) return;
    setState(() => _showChallengePromotion = !dismissed);
  }

  Future<void> _openChallengePromotion() async {
    await Navigator.of(context).push(
      PageTransitions.material(
        builder: (_) => const ThirtyDayChallengeScreen(),
      ),
    );
    if (mounted) _loadChallengePromotion();
  }

  Future<void> _dismissChallengePromotion() async {
    if (!mounted) return;
    setState(() => _showChallengePromotion = false);
    await ThirtyDayChallengeRepository.dismissHabitCenterPromotion();
  }

  String get _sleepMigrationTipId =>
      'habit_sleep_log_migration_${widget.username}';

  Future<void> _loadSleepLogMigration() async {
    await _loadSleepLogMigrationData();
  }

  Future<void> _loadSleepLogMigrationData({bool bypassTip = false}) async {
    try {
      if (!bypassTip &&
          await FeatureTipService.hasTipBeenShown(_sleepMigrationTipId)) {
        return;
      }
      final results = await Future.wait<dynamic>([
        StorageService.getTimeLogs(widget.username),
        HabitRepository.getGoals(),
        PomodoroService.getTags(),
        HabitRepository.getCheckIns(),
      ]);
      final tags = results[2] as List<PomodoroTag>;
      final proposal = HabitSleepLogMigrationService.buildProposal(
        logs: results[0] as List<TimeLogItem>,
        existingGoals: results[1] as List<HabitGoal>,
        existingCheckIns: results[3] as List<HabitCheckIn>,
        tagNames: {for (final tag in tags) tag.uuid: tag.name},
      );
      if (!mounted) return;
      setState(() => _sleepLogMigration = proposal);
    } catch (_) {
      // 迁移提示是增强体验，读取失败不影响习惯中心的正常使用。
    }
  }

  Future<void> _openSleepLogMigrationEntry() async {
    await _loadSleepLogMigrationData(bypassTip: true);
    if (!mounted) return;
    if (_sleepLogMigration != null) {
      await _openSleepLogMigration();
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Row(
          children: [
            Text('🌙'),
            SizedBox(width: 8),
            Expanded(child: Text('从时间日志迁移')),
          ],
        ),
        content: const Text(
          '暂时没有找到足够的夜间睡眠记录。请在时间日志中使用“睡眠、睡觉、作息、入睡、起床”等标题或标签，连续记录至少两晚完整睡眠时段；回到习惯中心后即可生成早睡和早起建议。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
  }

  Future<void> _openSleepLogMigration() async {
    final proposal = _sleepLogMigration;
    if (proposal == null) return;
    var timeSelection = HabitSleepLogTimeSelection.startTime;
    var sleepKind = HabitSleepLogKind.fullSleep;
    final options = await showDialog<HabitSleepLogMigrationOptions>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final selectedOptions = HabitSleepLogMigrationOptions(
            timeSelection: timeSelection,
            kind: sleepKind,
          );
          final selectedProposal = proposal.forOptions(selectedOptions);
          final displayProposal = selectedProposal ?? proposal;
          final canImport = selectedProposal?.canMigrate == true;
          return AlertDialog(
            title: const Row(
              children: [
                Text('🌙'),
                SizedBox(width: 8),
                Expanded(child: Text('迁移到早睡早起')),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '根据近 ${displayProposal.observedNights} 晚睡眠日志，系统建议把规律作息变成每天可打卡的时间点：',
                  ),
                  const SizedBox(height: 14),
                  _buildMigrationSuggestionRow(
                    context,
                    icon: Icons.nightlight_round,
                    title: '早睡',
                    value: HabitSleepLogMigrationService.formatMinute(
                      displayProposal.bedtimeMinute,
                    ),
                    enabled: displayProposal.createsEarlySleep,
                    existingText: displayProposal.hasEarlySleep ? '已有习惯' : null,
                  ),
                  const SizedBox(height: 8),
                  _buildMigrationSuggestionRow(
                    context,
                    icon: Icons.wb_twilight_rounded,
                    title: '早起',
                    value: displayProposal.hasReliableWakeTime
                        ? HabitSleepLogMigrationService.formatMinute(
                            displayProposal.wakeMinute,
                          )
                        : '暂无可靠结束时间',
                    enabled: displayProposal.createsEarlyWake,
                    existingText: displayProposal.hasEarlyWake
                        ? '已有习惯'
                        : displayProposal.hasReliableWakeTime
                            ? null
                            : '需手动补录',
                  ),
                  const SizedBox(height: 14),
                  Text(
                    proposal.hasGridOnlyLogs
                        ? '检测到 15 / 30 分钟的时间格记录。请确认这些记录是整段睡眠的入睡标记，还是小睡；整段睡眠才会进入早睡迁移。'
                        : '请确认这些记录代表整段夜间睡眠，而不是小睡。',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '记录类型',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  Wrap(
                    spacing: 8,
                    children: [
                      ChoiceChip(
                        label: const Text('整段睡眠'),
                        selected: sleepKind == HabitSleepLogKind.fullSleep,
                        onSelected: (_) => setDialogState(
                          () => sleepKind = HabitSleepLogKind.fullSleep,
                        ),
                      ),
                      ChoiceChip(
                        label: const Text('小睡'),
                        selected: sleepKind == HabitSleepLogKind.nap,
                        onSelected: (_) => setDialogState(
                          () => sleepKind = HabitSleepLogKind.nap,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    sleepKind == HabitSleepLogKind.fullSleep
                        ? '短时间格仅作为入睡时间标记。'
                        : '短时间格会被视为小睡，不导入早睡早起。',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '时间点取法（仅影响短时间格）',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  Wrap(
                    spacing: 8,
                    children: [
                      ChoiceChip(
                        label: const Text('取开始时间'),
                        selected: timeSelection ==
                            HabitSleepLogTimeSelection.startTime,
                        onSelected: (_) => setDialogState(
                          () => timeSelection =
                              HabitSleepLogTimeSelection.startTime,
                        ),
                      ),
                      ChoiceChip(
                        label: const Text('取平均时间'),
                        selected: timeSelection ==
                            HabitSleepLogTimeSelection.midpoint,
                        onSelected: (_) => setDialogState(
                          () => timeSelection =
                              HabitSleepLogTimeSelection.midpoint,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    timeSelection == HabitSleepLogTimeSelection.startTime
                        ? '例如 23:00–23:30 取 23:00。'
                        : '例如 23:00–23:30 取 23:15。',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '日志中位睡眠时长约 ${displayProposal.sleepDurationLabel}。完整睡眠会把结束时间导入早起并自动生成睡眠时长；只有入睡时间格时不会伪造早起时间。',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 13,
                    ),
                  ),
                  if (!canImport) ...[
                    const SizedBox(height: 8),
                    Text(
                      '当前选择下没有可迁移的整段睡眠记录。',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('稍后'),
              ),
              FilledButton.icon(
                onPressed: canImport
                    ? () => Navigator.of(dialogContext).pop(selectedOptions)
                    : null,
                icon: const Icon(Icons.add_task_rounded),
                label: Text(
                  displayProposal.createsEarlySleep ||
                          displayProposal.createsEarlyWake
                      ? '创建并导入'
                      : '导入历史打卡',
                ),
              ),
            ],
          );
        },
      ),
    );
    if (options == null || !mounted) return;

    try {
      final result = await HabitSleepLogMigrationService.migrateProposal(
        proposal: proposal,
        username: widget.username,
        options: options,
      );
      if (!mounted) return;
      await FeatureTipService.markTipShown(_sleepMigrationTipId);
      if (!mounted) return;
      setState(() {
        _sleepLogMigration = null;
        _reloadTick++;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '已创建 ${result.createdGoals.length} 个习惯，导入 ${result.totalImported} 条节点，生成 ${result.generatedSleepDurationCount} 条睡眠时长',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('迁移失败：$e')),
      );
    }
  }

  Future<void> _dismissSleepLogMigration() async {
    if (!mounted) return;
    setState(() => _sleepLogMigration = null);
    await FeatureTipService.markTipShown(_sleepMigrationTipId);
  }

  Widget _buildMigrationSuggestionRow(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String value,
    required bool enabled,
    String? existingText,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, color: colorScheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              color: colorScheme.primary,
            ),
          ),
          if (existingText != null) ...[
            const SizedBox(width: 8),
            Text(
              existingText,
              style: TextStyle(
                color: colorScheme.onSurfaceVariant,
                fontSize: 12,
              ),
            ),
          ] else if (enabled) ...[
            const SizedBox(width: 8),
            Icon(
              Icons.add_circle_outline_rounded,
              size: 18,
              color: colorScheme.primary,
            ),
          ],
        ],
      ),
    );
  }

  Widget? _buildTopBanners(ColorScheme colorScheme) {
    final banners = <Widget>[];
    final migration = _sleepLogMigration;
    if (migration != null) {
      banners.add(
        HabitSleepLogMigrationCard(
          proposal: migration,
          onTap: _openSleepLogMigration,
          onDismiss: _dismissSleepLogMigration,
        ),
      );
    }
    if (_showChallengePromotion) {
      banners.add(_buildChallengePromotionBanner(colorScheme));
    }
    if (banners.isEmpty) return null;
    return Column(children: banners);
  }

  Widget _buildChallengePromotionBanner(ColorScheme colorScheme) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 840),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Material(
            color: colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(20),
            child: InkWell(
              onTap: _openChallengePromotion,
              borderRadius: BorderRadius.circular(20),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: colorScheme.primary,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(
                        Icons.auto_awesome_rounded,
                        color: colorScheme.onPrimary,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '30天找到全新自我',
                            style: TextStyle(
                              color: colorScheme.onPrimaryContainer,
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '给平淡生活加一点新鲜感，开启一次小小的自我挑战',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: colorScheme.onPrimaryContainer
                                  .withValues(alpha: 0.78),
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      Icons.chevron_right_rounded,
                      color: colorScheme.onPrimaryContainer,
                    ),
                    IconButton(
                      tooltip: '关闭推广',
                      onPressed: _dismissChallengePromotion,
                      icon: Icon(
                        Icons.close_rounded,
                        color: colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openCreateHabit() async {
    final created = await PageTransitions.pushFromRect(
      context: context,
      page: const HabitEditScreen(),
      sourceKey: _createActionKey,
      sourceBorderRadius: BorderRadius.circular(20),
    );
    if (created == true && mounted) {
      setState(() => _reloadTick++);
    }
  }

  Future<void> _openArchived() async {
    final changed = await PageTransitions.pushFromRect(
      context: context,
      page: const HabitArchivedScreen(),
      sourceKey: _archiveActionKey,
      sourceBorderRadius: BorderRadius.circular(20),
    );
    if (changed == true && mounted) {
      setState(() => _reloadTick++);
    }
  }

  Future<void> _checkCoachMarks() async {
    if (_showCoachMarks || !mounted) return;
    final hasSeenCoachMarks =
        await FeatureTipService.hasTipBeenShown('coach_habit_center');
    if (hasSeenCoachMarks || !mounted) return;

    _showCoachMarks = true;
    await CoachMarkOverlay.show(
      context: context,
      steps: [
        CoachMarkStep(
          targetKey: _createActionKey,
          title: '新建习惯',
          description: '从这里创建一个想长期坚持的目标，可以设置打卡方式、周期和提醒。',
        ),
        CoachMarkStep(
          targetKey: _navigationKey,
          title: '切换视图',
          description: '在“今日”“日历”和“分析”之间切换，分别查看今天的执行情况、历史记录和趋势。',
        ),
        CoachMarkStep(
          targetKey: _todayContentKey,
          title: '今日习惯',
          description: '这里会按时间段展示今天的习惯，完成后可以直接打卡，也可以点进详情记录更多信息。',
        ),
        CoachMarkStep(
          targetKey: _archiveActionKey,
          title: '归档习惯',
          description: '暂时不想继续的习惯可以归档，历史记录仍会保留，之后也能恢复。',
        ),
      ],
      onFinish: _dismissCoachMarks,
      onSkip: _dismissCoachMarks,
    );
  }

  Future<void> _dismissCoachMarks() async {
    _showCoachMarks = false;
    await FeatureTipService.markTipShown('coach_habit_center');
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth > 600;

        final actions = [
          IconButton(
            tooltip: '从时间日志迁移早睡早起',
            onPressed: _openSleepLogMigrationEntry,
            icon: const Icon(Icons.bedtime_outlined),
          ),
          IconButton(
            key: _archiveActionKey,
            tooltip: '已归档习惯',
            onPressed: _openArchived,
            icon: const Icon(Icons.inventory_2_outlined),
          ),
          const SizedBox(width: 4),
        ];

        final bodyTabs = [
          HabitTodayTab(
            username: widget.username,
            coachTargetKey: _todayContentKey,
            reloadTick: _reloadTick,
            topBanner: _buildTopBanners(colorScheme),
            onChanged: () => setState(() => _reloadTick++),
          ),
          HabitCalendarTab(
            username: widget.username,
            reloadTick: _reloadTick,
          ),
          HabitAnalysisTab(
            username: widget.username,
            reloadTick: _reloadTick,
          ),
        ];

        if (isWide) {
          return Scaffold(
            appBar: AppBar(
              title: const Text('习惯中心'),
              centerTitle: false,
              actions: actions,
            ),
            floatingActionButton: Padding(
              padding: const EdgeInsets.only(bottom: 32.0, right: 32.0),
              child: FloatingActionButton.extended(
                key: _createActionKey,
                onPressed: _openCreateHabit,
                tooltip: '新建习惯',
                icon: const Icon(Icons.add_rounded),
                label: const Text('新建习惯'),
              ),
            ),
            body: Row(
              children: [
                NavigationRail(
                  key: _navigationKey,
                  selectedIndex: _tabController.index,
                  onDestinationSelected: (index) {
                    _tabController.animateTo(index);
                  },
                  labelType: NavigationRailLabelType.all,
                  destinations: const [
                    NavigationRailDestination(
                      icon: Icon(Icons.today_outlined),
                      selectedIcon: Icon(Icons.today),
                      label: Text('今日'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.calendar_month_outlined),
                      selectedIcon: Icon(Icons.calendar_month),
                      label: Text('日历'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.analytics_outlined),
                      selectedIcon: Icon(Icons.analytics),
                      label: Text('分析'),
                    ),
                  ],
                ),
                VerticalDivider(
                    thickness: 1,
                    width: 1,
                    color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: bodyTabs,
                  ),
                ),
              ],
            ),
          );
        }

        // Narrow screen (mobile)
        return Scaffold(
          appBar: AppBar(
            title: const Text('习惯中心'),
            centerTitle: false,
            actions: actions,
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(48),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 600),
                  child: TabBar(
                    key: _navigationKey,
                    controller: _tabController,
                    indicatorSize: TabBarIndicatorSize.tab,
                    dividerColor:
                        colorScheme.outlineVariant.withValues(alpha: 0.5),
                    labelStyle: const TextStyle(fontWeight: FontWeight.w700),
                    tabs: const [
                      Tab(text: '今日'),
                      Tab(text: '日历'),
                      Tab(text: '分析'),
                    ],
                  ),
                ),
              ),
            ),
          ),
          floatingActionButton: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              FloatingActionButton.extended(
                key: _createActionKey,
                onPressed: _openCreateHabit,
                tooltip: '新建习惯',
                icon: const Icon(Icons.add_rounded),
                label: const Text('新建习惯'),
              ),
              const SizedBox(height: 100),
            ],
          ),
          body: TabBarView(
            controller: _tabController,
            children: bodyTabs,
          ),
        );
      },
    );
  }
}
