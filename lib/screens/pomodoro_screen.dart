import 'dart:async';
import 'package:CountDownTodo/screens/pomodoro/widgets/fading_indexed_stack.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/notification_service.dart';
import '../services/pomodoro_service.dart';
import 'pomodoro/views/workbench_view.dart';
import 'pomodoro/views/stats_view.dart';
import '../widgets/coach_mark_overlay.dart';
import '../services/feature_tip_service.dart';

// ══════════════════════════════════════════════════════════════
// 番茄钟主页（TabBar: 专注工作台 + 统计看板）
// ══════════════════════════════════════════════════════════════
class PomodoroScreen extends StatefulWidget {
  final String username;

  /// 0 = 工作台（默认），1 = 统计看板
  final int initialTab;

  /// 0 = 日，1 = 周，2 = 月，3 = 年
  final int initialDimension;

  const PomodoroScreen({
    super.key,
    required this.username,
    this.initialTab = 0,
    this.initialDimension = 0,
  });

  @override
  State<PomodoroScreen> createState() => _PomodoroScreenState();
}

class _PomodoroScreenState extends State<PomodoroScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  PomodoroPhase _currentPhase = PomodoroPhase.idle;
  bool _workbenchReady = false;
  final _statsKey = GlobalKey<PomodoroStatsState>();
  final GlobalKey<PomodoroWorkbenchState> _workbenchKeyPortrait =
      GlobalKey<PomodoroWorkbenchState>();
  final GlobalKey<PomodoroWorkbenchState> _workbenchKeyLandscape =
      GlobalKey<PomodoroWorkbenchState>();
  final GlobalKey _statsTabKey = GlobalKey();
  final List<StreamSubscription<MethodCall>> _notifSubs = [];
  bool _disposed = false;

  /// 统一访问当前活跃的 workbench state（portrait 或 landscape）
  PomodoroWorkbenchState? get _workbenchState =>
      _workbenchKeyPortrait.currentState ?? _workbenchKeyLandscape.currentState;

  @override
  void initState() {
    super.initState();
    debugPrint(
        '[PomodoroScreen] initState start; initialTab=${widget.initialTab} username=${widget.username}');
    _tabController =
        TabController(length: 2, vsync: this, initialIndex: widget.initialTab);
    _tabController.addListener(() {
      if (_disposed || !mounted) return;
      // 🚀 性能优化：只有在确实需要刷新 UI 时才 setState
      if (!_tabController.indexIsChanging) {
        if (_tabController.index == 1) {
          try {
            _statsKey.currentState?.reload();
          } catch (_) {}
        } else {
          try {
            _workbenchState?.reload();
          } catch (_) {}
        }
        if (mounted && !_disposed) setState(() {});
      }
    });

    // If initial tab is workbench, trigger a reload after first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_disposed || !mounted) return;
      debugPrint(
          '[PomodoroScreen] postFrameCallback firing; initialTab=${widget.initialTab}');
      if (widget.initialTab == 0) {
        try {
          _workbenchState?.reload();
        } catch (_) {}
        debugPrint(
            '[PomodoroScreen] requested workbench reload from postFrameCallback');
      }
    });

    // 监听通知栏按钮事件（listen 会自动 replay 冷启动 pending 事件）
    _setupMethodChannelListener();
  }

  bool _showCoachMarks = false;

  Future<void> _checkCoachMarks() async {
    if (_showCoachMarks || !mounted || !_workbenchReady) return;
    final hasSeenCoachMarks =
        await FeatureTipService.hasTipBeenShown('coach_pomodoro_intro');
    if (hasSeenCoachMarks) return;

    // 等待 AppBar 的 AnimatedContainer 动画（300ms）完成，否则目标会因为布局展开而向下偏移
    await Future.delayed(const Duration(milliseconds: 400));
    if (!mounted) return;

    final workbench = _workbenchState;
    if (workbench == null) return;

    setState(() {
      _showCoachMarks = true;
    });

    CoachMarkOverlay.show(
      context: context,
      steps: [
        CoachMarkStep(
          targetKey: workbench.settingsKey,
          title: '设置',
          description: '点击这里可以配置番茄钟的时长、休息时间、循环次数等详细设置。',
        ),
        CoachMarkStep(
          targetKey: workbench.tagsManagerKey,
          title: '标签管理',
          description: '在这里管理你的所有专注标签，方便你对不同的专注内容进行分类。',
        ),
        CoachMarkStep(
          targetKey: workbench.serverConnKey,
          title: '连接状态',
          description: '显示当前与服务器的跨端同步状态，绿灯表示一切正常。',
        ),
        CoachMarkStep(
          targetKey: workbench.modeSwitchKey,
          title: '计时模式',
          description: '你可以随时在正计时与倒计时之间切换，满足不同场景的专注需求。',
        ),
        CoachMarkStep(
          targetKey: workbench.focusTagsKey,
          title: '选择专注标签',
          description: '快速为当前的专注选择一个或多个标签。专注结束后也可以随时修改它们！',
        ),
        CoachMarkStep(
          targetKey: workbench.bindTodoKey,
          title: '绑定专注事件',
          description: '点击可以绑定具体的待办事项或课程，让每一次专注都有的放矢。专注结束后同样可以重新绑定！',
        ),
        CoachMarkStep(
          targetKey: _statsTabKey,
          title: '统计看板',
          description: '专注完成后，可以在这里查看你的专注统计数据，洞悉你的专注趋势。',
        ),
      ],
      onFinish: () {
        if (mounted) {
          _showCoachMarks = false;
        }
        FeatureTipService.markTipShown('coach_pomodoro_intro');
      },
      onSkip: () {
        if (mounted) {
          _showCoachMarks = false;
        }
        FeatureTipService.markTipShown('coach_pomodoro_intro');
      },
    );
  }

  void _setupMethodChannelListener() {
    _notifSubs.add(NotificationService.listen('pomodoroFinishEarly', (call) {
      debugPrint('[PomodoroScreen] Triggering finishEarly from notification');
      if (!mounted || _disposed) return;
      _workbenchState?.handleFinishEarly();
    }));
    _notifSubs.add(NotificationService.listen('pomodoroAbandon', (call) {
      debugPrint('[PomodoroScreen] Triggering abandonFocus from notification');
      if (!mounted || _disposed) return;
      _workbenchState?.handleAbandonFocus();
    }));
  }

  @override
  void dispose() {
    _disposed = true;
    for (final sub in _notifSubs) {
      sub.cancel();
    }
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // isFocusingOrWatching controls AppBar / bottom tab visibility (when focusing/remote watching)
    // Keep existing logic for those UI parts but compute more explicit helpers for landscape stats.
    final bool isTimerRunning = _currentPhase == PomodoroPhase.focusing ||
        _currentPhase == PomodoroPhase.breaking ||
        _currentPhase == PomodoroPhase.remoteWatching;

    // Keep previous readiness gating for AppBar/tab hiding behavior
    final isFocusingOrWatching = !_workbenchReady || isTimerRunning;

    // Show the compact landscape stats column only when timer is idle or finished
    final bool showLandscapeStats = _currentPhase == PomodoroPhase.idle ||
        _currentPhase == PomodoroPhase.finished;

    final int tabIndex = _tabController.index;
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;

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
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  alignment: Alignment.center,
                  child: PomodoroWorkbench(
                    key: _workbenchKeyLandscape,
                    username: widget.username,
                    onPhaseChanged: (phase) {
                      if (!_disposed && mounted && _currentPhase != phase) {
                        setState(() => _currentPhase = phase);
                      }
                    },
                    onReady: () {
                      if (!_disposed && mounted && !_workbenchReady) {
                        setState(() => _workbenchReady = true);
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (mounted) _checkCoachMarks();
                        });
                      }
                    },
                    onRecordAdded: () {
                      if (!_disposed && mounted) {
                        try {
                          _statsKey.currentState?.reload();
                        } catch (_) {}
                      }
                    },
                  ),
                ),
              ),

              // Right: fixed-width column with stats and compact controls
              // Only show the right column when the timer is idle/finished to avoid distraction
              if (showLandscapeStats)
                Container(
                  width:
                      420, // Increased width for better visibility on wide screens
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: Theme.of(context)
                        .colorScheme
                        .surface
                        .withValues(alpha: 0.02),
                    border: Border(
                        left: BorderSide(
                            color: Theme.of(context).dividerColor, width: 0.5)),
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
                              Text('番茄统计',
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleSmall
                                      ?.copyWith(fontWeight: FontWeight.bold)),
                              ToggleButtons(
                                isSelected: [tabIndex == 0, tabIndex == 1],
                                onPressed: (i) {
                                  _tabController.animateTo(i);
                                  setState(() {});
                                },
                                constraints: const BoxConstraints(
                                    minWidth: 32, minHeight: 32),
                                borderRadius: BorderRadius.circular(8),
                                children: const [
                                  Icon(Icons.timer_outlined, size: 18),
                                  Icon(Icons.bar_chart_rounded, size: 18)
                                ],
                              ),
                            ],
                          ),

                          const SizedBox(height: 12),

                          // Always show stats summary (same widget used in portrait tab)
                          Card(
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                            child: Padding(
                              padding: const EdgeInsets.all(4),
                              child: PomodoroStats(
                                  key: _statsKey,
                                  username: widget.username,
                                  initialDimension: widget.initialDimension,
                                  isCompact: true),
                            ),
                          ),
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
                  // portrait workbench
                  PomodoroWorkbench(
                    key: _workbenchKeyPortrait,
                    username: widget.username,
                    onPhaseChanged: (phase) {
                      if (!_disposed && mounted && _currentPhase != phase) {
                        setState(() => _currentPhase = phase);
                      }
                    },
                    onReady: () {
                      if (!_disposed && mounted && !_workbenchReady) {
                        setState(() => _workbenchReady = true);
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (mounted) _checkCoachMarks();
                        });
                      }
                    },
                    onRecordAdded: () {
                      if (!_disposed && mounted) {
                        try {
                          _statsKey.currentState?.reload();
                        } catch (_) {}
                      }
                    },
                  ),
                  PomodoroStats(
                    key: _statsKey,
                    username: widget.username,
                    initialDimension: widget.initialDimension,
                  ),
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
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold)),
                  ),
                ),
                if (Navigator.canPop(context)) const SizedBox(width: 48),
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
              tabs: [
                const Tab(
                  icon: Icon(Icons.timer_outlined),
                  text: '工作台',
                  iconMargin: EdgeInsets.only(bottom: 2),
                ),
                Tab(
                  key: _statsTabKey,
                  icon: const Icon(Icons.bar_chart_rounded),
                  text: '统计看板',
                  iconMargin: const EdgeInsets.only(bottom: 2),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
