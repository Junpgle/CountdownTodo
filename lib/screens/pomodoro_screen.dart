import 'package:flutter/material.dart';
import '../services/pomodoro_service.dart';
import 'pomodoro/widgets/fading_indexed_stack.dart';
import 'pomodoro/views/workbench_view.dart';
import 'pomodoro/views/stats_view.dart';

// ══════════════════════════════════════════════════════════════
// 番茄钟主页（TabBar: 专注工作台 + 统计看板）
// ══════════════════════════════════════════════════════════════
class PomodoroScreen extends StatefulWidget {
  final String username;
  /// 0 = 工作台（默认），1 = 统计看板
  final int initialTab;
  const PomodoroScreen({super.key, required this.username, this.initialTab = 0});

  @override
  State<PomodoroScreen> createState() => _PomodoroScreenState();
}

class _PomodoroScreenState extends State<PomodoroScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  PomodoroPhase _currentPhase = PomodoroPhase.idle;
  bool _workbenchReady = false;
  final _statsKey = GlobalKey<PomodoroStatsState>();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
        length: 2, vsync: this, initialIndex: widget.initialTab);
    _tabController.addListener(() {
      if (_tabController.index == 1 && !_tabController.indexIsChanging) {
        _statsKey.currentState?.reload();
      }
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isFocusingOrWatching = !_workbenchReady
        || _currentPhase == PomodoroPhase.focusing
        || _currentPhase == PomodoroPhase.remoteWatching;

    final int tabIndex = _tabController.index;
    final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;

    // Landscape: use a two-column layout (big timer/workbench left, stats/controls right)
    if (isLandscape) {
      return Scaffold(
        body: SafeArea(
          bottom: false,
          child: Row(
            children: [
              // Left: large workbench area
              Expanded(
                flex: 3,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  alignment: Alignment.center,
                  child: PomodoroWorkbench(
                    username: widget.username,
                    onPhaseChanged: (phase) {
                      if (mounted && _currentPhase != phase) {
                        setState(() => _currentPhase = phase);
                      }
                    },
                    onReady: () {
                      if (mounted && !_workbenchReady) {
                        setState(() => _workbenchReady = true);
                      }
                    },
                  ),
                ),
              ),

              // Right: fixed-width column with stats and compact controls
              Container(
                width: 360,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface.withOpacity(0.02),
                  border: Border(left: BorderSide(color: Theme.of(context).dividerColor, width: 0.5)),
                ),
                child: SafeArea(
                  top: false,
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // compact header with tab-like toggle
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('番茄统计', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                            ToggleButtons(
                              isSelected: [tabIndex == 0, tabIndex == 1],
                              onPressed: (i) {
                                _tabController.animateTo(i);
                                setState(() {});
                              },
                              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                              borderRadius: BorderRadius.circular(8),
                              children: const [Icon(Icons.timer_outlined), Icon(Icons.bar_chart_rounded)],
                            ),
                          ],
                        ),

                        const SizedBox(height: 12),

                        // Always show stats summary (same widget used in portrait tab)
                        Card(
                          elevation: 0,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: PomodoroStats(key: _statsKey, username: widget.username),
                          ),
                        ),

                        const SizedBox(height: 12),

                        // quick actions / next items placeholder
                        Text('待办与会话', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                        const SizedBox(height: 8),
                        // keep a compact list area so the right column isn't empty
                        Container(
                          height: 200,
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.02),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Center(child: Text('最近的待办 / 会话将在这里显示', style: Theme.of(context).textTheme.bodySmall)),
                        ),

                        const SizedBox(height: 16),

                        // some space for settings / controls
                        ElevatedButton.icon(
                          onPressed: () => _tabController.animateTo(0),
                          icon: const Icon(Icons.play_arrow),
                          label: const Text('开始/返回工作台'),
                        ),
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          onPressed: () => _tabController.animateTo(1),
                          icon: const Icon(Icons.bar_chart_rounded),
                          label: const Text('查看统计'),
                        ),
                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // ── 顶部导航栏：淡入淡出 ──
            _buildAppBar(isFocusingOrWatching),

            // ── 主内容区：IndexedStack 保持状态 + AnimatedOpacity 淡入淡出 ──
            Expanded(
              child: FadingIndexedStack(
                index: tabIndex,
                children: [
                  PomodoroWorkbench(
                    username: widget.username,
                    onPhaseChanged: (phase) {
                      if (mounted && _currentPhase != phase) {
                        setState(() => _currentPhase = phase);
                      }
                    },
                    onReady: () {
                      if (mounted && !_workbenchReady) {
                        setState(() => _workbenchReady = true);
                      }
                    },
                  ),
                  PomodoroStats(key: _statsKey, username: widget.username),
                ],
              ),
            ),

            // ── 底部 Tab 导航：淡入淡出 ──
            _buildBottomTabBar(isFocusingOrWatching),
          ],
        ),
      ),
    );
  }

  Widget _buildAppBar(bool isFocusingOrWatching) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      height: isFocusingOrWatching ? 0 : kToolbarHeight,
      clipBehavior: Clip.hardEdge,
      decoration: const BoxDecoration(),
      child: AnimatedOpacity(
        opacity: isFocusingOrWatching ? 0.0 : 1.0,
        duration: const Duration(milliseconds: 300),
        child: SizedBox(
          height: kToolbarHeight,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              children: [
                if (Navigator.canPop(context))
                  IconButton(
                    icon: const Icon(Icons.arrow_back),
                    onPressed: () => Navigator.pop(context),
                  ),
                const Expanded(
                  child: Center(
                    child: Text('🍅 番茄钟',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  ),
                ),
                if (Navigator.canPop(context))
                  const SizedBox(width: 48),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBottomTabBar(bool isFocusingOrWatching) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      height: isFocusingOrWatching ? 0 : null,
      clipBehavior: Clip.hardEdge,
      decoration: const BoxDecoration(),
      child: AnimatedOpacity(
        opacity: isFocusingOrWatching ? 0.0 : 1.0,
        duration: const Duration(milliseconds: 300),
        child: SafeArea(
          top: false,
          child: Container(
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(
                  color: Theme.of(context)
                      .colorScheme
                      .outlineVariant
                      .withValues(alpha: 0.5),
                  width: 1,
                ),
              ),
            ),
            child: TabBar(
              controller: _tabController,
              indicatorSize: TabBarIndicatorSize.label,
              dividerColor: Colors.transparent,
              tabs: const [
                Tab(
                  icon: Icon(Icons.timer_outlined),
                  text: '工作台',
                  iconMargin: EdgeInsets.only(bottom: 2),
                ),
                Tab(
                  icon: Icon(Icons.bar_chart_rounded),
                  text: '统计看板',
                  iconMargin: EdgeInsets.only(bottom: 2),
                ),
              ],
            ),
          ),
        ),
      );
  }
}

