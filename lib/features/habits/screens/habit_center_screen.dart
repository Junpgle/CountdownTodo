import 'package:flutter/material.dart';

import '../../../utils/page_transitions.dart';
import 'habit_analysis_tab.dart';
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

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _openCreateHabit() async {
    final created = await Navigator.of(context).push(
      PageTransitions.material(
        builder: (_) => const HabitEditScreen(),
      ),
    );
    if (created == true && mounted) {
      setState(() => _reloadTick++);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('习惯中心'),
          centerTitle: false,
          actions: [
            IconButton(
              tooltip: '新建习惯',
              onPressed: _openCreateHabit,
              icon: const Icon(Icons.add_rounded),
            ),
            const SizedBox(width: 4),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(48),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 600),
                child: Container(
                  height: 40,
                  margin:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest
                        .withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: TabBar(
                    controller: _tabController,
                    indicatorSize: TabBarIndicatorSize.tab,
                    dividerColor: Colors.transparent,
                    indicator: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      color: colorScheme.primaryContainer,
                      boxShadow: [
                        BoxShadow(
                          color: colorScheme.shadow.withValues(alpha: 0.05),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    labelColor: colorScheme.onPrimaryContainer,
                    labelStyle: const TextStyle(fontWeight: FontWeight.w700),
                    unselectedLabelColor: colorScheme.onSurfaceVariant,
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
        ),
        body: TabBarView(
          controller: _tabController,
          children: [
            HabitTodayTab(
              username: widget.username,
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
          ],
        ),
      ),
    );
  }
}
