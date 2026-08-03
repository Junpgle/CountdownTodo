import 'package:flutter/material.dart';

import '../../../services/feature_tip_service.dart';
import '../../../utils/page_transitions.dart';
import '../../../widgets/coach_mark_overlay.dart';
import 'habit_analysis_tab.dart';
import 'habit_archived_screen.dart';
import 'habit_calendar_tab.dart';
import 'habit_edit_screen.dart';
import 'habit_today_tab.dart';

/// 习惯中心：今日 / 日历 / 分析 三个标签页。
class HabitCenterScreen extends StatefulWidget {
  final String username;

  const HabitCenterScreen({super.key, required this.username});

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

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    // Listen to tab controller to update navigation rail selection
    _tabController.addListener(() {
      if (!mounted) return;
      setState(() {});
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkCoachMarks());
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
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
