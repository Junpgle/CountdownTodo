import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models.dart';
import '../storage_service.dart';
import '../services/course_service.dart';
import '../services/power_save_mode_service.dart';
import '../course_import/course_schedule_semantics.dart';
import '../utils/android_energy_policy.dart';
import '../utils/calendar_date_math.dart';
import '../widgets/app_skeleton.dart';
import '../widgets/floating_glass_control.dart';
import '../widgets/optional_liquid_glass_surface.dart';
import '../utils/time_utils.dart';

part 'app_board/app_board_gantt.dart';
part 'app_board/app_board_widgets.dart';

// Custom Colors to match Tailwind Emerald
const Color emerald = Color(0xFF10B981);
const Color emeraldAccent = Color(0xFF34D399);

class AppBoardScreen extends StatefulWidget {
  final String username;
  final VoidCallback? onBack;

  const AppBoardScreen({super.key, required this.username, this.onBack});

  @override
  State<AppBoardScreen> createState() => _AppBoardScreenState();
}

class _AppBoardScreenState extends State<AppBoardScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  List<TodoItem> _todos = [];
  List<TodoItem> _ganttTodos = [];
  int _completedTodoCount = 0;
  List<CountdownItem> _countdowns = [];
  List<CourseItem> _courses = [];
  DateTime? _semesterStart;
  bool _isLoading = true;
  String _mobileTab = 'stream'; // stream, roadmap, mission
  String _missionTab = 'active'; // active, completed
  double _dayWidth = 60.0;
  TodoItem? _detailTask;
  DateTime _now = DateTime.now();
  final ValueNotifier<DateTime> _nowNotifier = ValueNotifier(DateTime.now());
  Timer? _timer;
  final ScrollController _cdScrollController = ScrollController();
  final ScrollController _marqueeController = ScrollController();
  Timer? _marqueeTimer;
  bool _appInForeground = true;
  bool _tickerModeEnabled = false;

  bool get _shouldRunTimers =>
      mounted && _appInForeground && _tickerModeEnabled;
  bool get _shouldRunMarquee =>
      _shouldRunTimers && AndroidEnergyPolicy.shouldRunDecorativeMotion;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    PowerSaveModeService.enabledListenable.addListener(_onPowerSaveModeChanged);
    final lifecycleState = WidgetsBinding.instance.lifecycleState;
    _appInForeground =
        lifecycleState == null || lifecycleState == AppLifecycleState.resumed;
    _loadData();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final tickerModeEnabled = TickerMode.valuesOf(context).enabled;
    if (_tickerModeEnabled == tickerModeEnabled) return;
    _tickerModeEnabled = tickerModeEnabled;
    _syncTimersWithVisibility();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appInForeground = state == AppLifecycleState.resumed;
    _syncTimersWithVisibility();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    PowerSaveModeService.enabledListenable.removeListener(
      _onPowerSaveModeChanged,
    );
    _stopTimers();
    _nowNotifier.dispose();
    _cdScrollController.dispose();
    _marqueeController.dispose();
    super.dispose();
  }

  void _syncTimersWithVisibility() {
    if (_shouldRunTimers) {
      _startTimers();
    } else {
      _stopTimers();
    }
  }

  void _startTimers() {
    if (_timer == null) {
      _refreshCurrentTime();
      _scheduleClockRefresh();
    }
    if (_shouldRunMarquee) _scheduleMarqueeTick(Duration.zero);
  }

  void _scheduleClockRefresh() {
    if (!_shouldRunTimers) return;

    final now = DateTime.now();
    final nextMinute = DateTime(
      now.year,
      now.month,
      now.day,
      now.hour,
      now.minute,
    ).add(const Duration(minutes: 1));
    final delay = nextMinute.difference(now);
    _timer = Timer(delay, () {
      _timer = null;
      if (!_shouldRunTimers) {
        _stopTimers();
        return;
      }
      _refreshCurrentTime();
      _scheduleClockRefresh();
    });
  }

  void _stopTimers() {
    _timer?.cancel();
    _timer = null;
    _marqueeTimer?.cancel();
    _marqueeTimer = null;
  }

  void _scheduleMarqueeTick(Duration delay) {
    if (!_shouldRunMarquee || _marqueeTimer != null) return;
    _marqueeTimer = Timer(delay, _handleMarqueeTick);
  }

  void _handleMarqueeTick() {
    _marqueeTimer = null;
    if (!_shouldRunMarquee) return;

    var nextDelay = const Duration(seconds: 1);
    if (_marqueeController.hasClients) {
      final maxScroll = _marqueeController.position.maxScrollExtent;
      if (maxScroll > 1) {
        final scrollInterval = AndroidEnergyPolicy.decorativeScrollInterval(
          const Duration(milliseconds: 100),
        );
        final scrollDistance =
            30 * scrollInterval.inMicroseconds / Duration.microsecondsPerSecond;
        final currentScroll = _marqueeController.offset;
        _marqueeController.jumpTo(
          currentScroll >= maxScroll - 1 ? 0 : currentScroll + scrollDistance,
        );
        // Keep the original ~30px/s speed while Android batches the decorative
        // movement into half as many timer wakeups.
        nextDelay = scrollInterval;
      }
    }
    _scheduleMarqueeTick(nextDelay);
  }

  void _onPowerSaveModeChanged() {
    _stopTimers();
    _refreshCurrentTime();
    _syncTimersWithVisibility();
  }

  void _refreshCurrentTime() {
    final now = DateTime.now();
    _now = now;

    final displayedTime = _nowNotifier.value;
    if (displayedTime.year != now.year ||
        displayedTime.month != now.month ||
        displayedTime.day != now.day ||
        displayedTime.hour != now.hour ||
        displayedTime.minute != now.minute) {
      _nowNotifier.value = now;
    }
  }

  int _calculateCurrentWeek() {
    if (_semesterStart == null) return 1;
    final week = CourseScheduleSemantics.weekIndexForDate(
      _semesterStart!,
      _now,
    );
    return week < 1 ? 1 : week;
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final todos = await StorageService.getTodos(widget.username, limit: 500);
      final countdowns = await StorageService.getCountdowns(widget.username);
      final courses = await CourseService.getAllCourses(widget.username);
      final semesterStart = await StorageService.getSemesterStart();

      if (mounted) {
        // De-duplicate courses to prevent multi-week loading issues
        final seenCourses = <String>{};
        final uniqueCourses = <CourseItem>[];
        for (var c in courses) {
          final key =
              '${c.courseName}-${c.startTime}-${c.weekday}-${c.weekIndex}';
          if (!seenCourses.contains(key)) {
            seenCourses.add(key);
            uniqueCourses.add(c);
          }
        }

        final activeTodos = <TodoItem>[];
        final ganttTodos = <TodoItem>[];
        var completedTodoCount = 0;
        for (final todo in todos) {
          if (todo.isDeleted || todo.isSkipped) continue;
          activeTodos.add(todo);
          if (todo.isDone) completedTodoCount++;
          if (todo.dueDate != null) ganttTodos.add(todo);
        }

        setState(() {
          _todos = activeTodos;
          _ganttTodos = ganttTodos;
          _completedTodoCount = completedTodoCount;
          _countdowns = countdowns
              .where((c) => !c.isDeleted && c.targetDate.isAfter(_now))
              .toList();
          _countdowns.sort((a, b) => a.targetDate.compareTo(b.targetDate));
          _courses = uniqueCourses;
          _semesterStart = semesterStart;
          _isLoading = false;
        });

        // Auto-scroll Gantt to Today after a short delay to allow layout
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _scrollToToday();
        });
      }
    } catch (e) {
      // debugPrint('Error loading board data: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _scrollToToday() {
    // This is a placeholder since the scroll controllers for the sub-widgets
    // are not directly accessible here. In a real scenario, we might use a
    // shared ScrollController or a global key.
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.sizeOf(context).width >= 1024;

    return Scaffold(
      backgroundColor: const Color(0xFF020617),
      body: Stack(
        children: [
          const AnimatedBackground(),
          Column(
            children: [
              _buildHeader(isDesktop),
              Expanded(
                child: _isLoading
                    ? const AppSkeletonDashboardPage(
                        isLightSurface: true,
                        showMetricGrid: true,
                        showChart: true,
                        listCount: 4,
                        wideLayout: AppSkeletonDashboardWideLayout.splitColumns,
                        wideBreakpoint: 1024,
                        leftFlex: 3,
                        rightFlex: 6,
                        wideHorizontalPadding: 24,
                      )
                    : isDesktop
                    ? _buildDesktopLayout()
                    : _buildMobileLayout(),
              ),
              if (isDesktop) _buildFooter(),
              if (!isDesktop) _buildMobileNav(),
            ],
          ),
          if (_detailTask != null)
            TaskDetailModal(
              task: _detailTask!,
              onClose: () => setState(() => _detailTask = null),
            ),
        ],
      ),
    );
  }

  static const LinearGradient _titleGradient = LinearGradient(
    colors: [Colors.white, Colors.white38],
  );
  static Rect? _cachedDesktopTitleBounds;
  static Shader? _cachedDesktopTitleShader;
  static Rect? _cachedMobileTitleBounds;
  static Shader? _cachedMobileTitleShader;

  static Shader _resolveDesktopTitleShader(Rect bounds) {
    if (_cachedDesktopTitleBounds == bounds &&
        _cachedDesktopTitleShader != null) {
      return _cachedDesktopTitleShader!;
    }
    _cachedDesktopTitleBounds = bounds;
    return _cachedDesktopTitleShader = _titleGradient.createShader(bounds);
  }

  static Shader _resolveMobileTitleShader(Rect bounds) {
    if (_cachedMobileTitleBounds == bounds &&
        _cachedMobileTitleShader != null) {
      return _cachedMobileTitleShader!;
    }
    _cachedMobileTitleBounds = bounds;
    return _cachedMobileTitleShader = _titleGradient.createShader(bounds);
  }

  Widget _buildHeader(bool isDesktop) {
    final onBack = widget.onBack ?? () => Navigator.of(context).pop();
    return Container(
      height: isDesktop ? 100 : 70,
      padding: EdgeInsets.symmetric(horizontal: isDesktop ? 40 : 16),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Colors.white.withValues(alpha: 0.05)),
        ),
        color: Colors.black.withValues(alpha: 0.2),
      ),
      child: Row(
        children: [
          // Back Button
          SizedBox.square(
            dimension: 48,
            child: FloatingGlassControl(
              height: 48,
              borderRadius: 16,
              tint: Theme.of(context).colorScheme.surfaceContainerHighest
                  .withValues(alpha: 0.08),
              isDark: true,
              useTopBarGlass: true,
              fallback: IconButton(
                onPressed: onBack,
                icon: const Icon(Icons.arrow_back, color: Colors.white70),
                style: IconButton.styleFrom(
                  backgroundColor: Colors.white.withValues(alpha: 0.05),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  side: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
                ),
              ),
              child: IconButton(
                onPressed: onBack,
                icon: const Icon(Icons.arrow_back, color: Colors.white70),
                style: IconButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  side: BorderSide.none,
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          // Title
          if (isDesktop)
            ShaderMask(
              shaderCallback: _resolveDesktopTitleShader,
              child: const Text(
                '看板',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 32,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -1.5,
                ),
              ),
            ),
          if (!isDesktop)
            Expanded(
              child: Center(
                child: ShaderMask(
                  shaderCallback: _resolveMobileTitleShader,
                  child: const Text(
                    '看板',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.5,
                    ),
                  ),
                ),
              ),
            ),
          if (isDesktop)
            Expanded(
              child: Center(
                child: SizedBox(
                  height: 60,
                  child: ListView.separated(
                    controller: _cdScrollController,
                    scrollDirection: Axis.horizontal,
                    shrinkWrap: true,
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    findItemIndexCallback: (Key key) {
                      if (key is ValueKey<String>) {
                        final id = key.value;
                        final idx = _countdowns.indexWhere((c) => c.id == id);
                        return idx != -1 ? idx : null;
                      }
                      return null;
                    },
                    itemCount: _countdowns.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 16),
                    itemBuilder: (context, index) {
                      final cd = _countdowns[index];
                      final diff = CalendarDateMath.daysBetween(
                        _now,
                        cd.targetDate,
                      );
                      final isUrgent = diff < 3;
                      return RepaintBoundary(
                        key: ValueKey<String>(cd.id),
                        child: Container(
                          width: 140,
                          padding: const EdgeInsets.symmetric(
                            vertical: 6,
                            horizontal: 12,
                          ),
                          decoration: BoxDecoration(
                            color:
                                (isUrgent
                                        ? Colors.red
                                        : Theme.of(context).colorScheme.primary)
                                    .withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color:
                                  (isUrgent
                                          ? Colors.red
                                          : Theme.of(context)
                                                .colorScheme
                                                .primary)
                                      .withValues(alpha: 0.2),
                            ),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                cd.title,
                                style: TextStyle(
                                  color: isUrgent
                                      ? Colors.redAccent
                                      : Theme.of(context).colorScheme.secondary,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 1,
                                  height: 1.0,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${math.max(0, diff)} 天',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w900,
                                  height: 1.0,
                                  fontFeatures: [FontFeature.tabularFigures()],
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          if (isDesktop)
            ValueListenableBuilder<DateTime>(
              valueListenable: _nowNotifier,
              builder: (context, now, _) => Text(
                AppTimeFormats.dateFormatter('HH:mm').format(now),
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.8),
                  fontSize: 48,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -2,
                  fontFeatures: [const FontFeature.tabularFigures()],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildDesktopLayout() {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final availableHeight = constraints.maxHeight;
          final availableWidth = constraints.maxWidth;

          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                flex: 3,
                child: GlassCard(
                  title: '今日执行流',
                  child: TodayHourlyTimeline(
                    todos: _todos,
                    courses: _courses,
                    semesterStart: _semesterStart,
                    currentWeek: _calculateCurrentWeek(),
                    itemHeight:
                        availableHeight / 26, // Fit 24 hours + some padding
                    onTaskClick: (task) => setState(() => _detailTask = task),
                  ),
                ),
              ),
              const SizedBox(width: 24),
              Expanded(
                flex: 6,
                child: GlassCard(
                  title: '战略路线图',
                  headerExtra: Row(
                    children: [
                      IconButton(
                        icon: const Icon(
                          Icons.zoom_out,
                          color: Colors.white30,
                          size: 18,
                        ),
                        onPressed: () => setState(
                          () => _dayWidth = math.max(10, _dayWidth - 5),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(
                          Icons.zoom_in,
                          color: Colors.white30,
                          size: 18,
                        ),
                        onPressed: () => setState(
                          () => _dayWidth = math.min(150, _dayWidth + 5),
                        ),
                      ),
                    ],
                  ),
                  child: GanttChart(
                    todos: _ganttTodos,
                    dayWidth: _dayWidth == 60.0
                        ? (availableWidth * 0.5 / 37)
                        : _dayWidth, // Default fit
                    onTaskClick: (task) => setState(() => _detailTask = task),
                  ),
                ),
              ),
              const SizedBox(width: 24),
              Expanded(
                flex: 3,
                child: GlassCard(
                  title: '作战指挥中心',
                  headerExtra: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      const Text(
                        '完成率',
                        style: TextStyle(
                          color: Colors.white30,
                          fontSize: 8,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(
                        '${_calculateCompletionRate()}%',
                        style: const TextStyle(
                          color: emeraldAccent,
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                  child: MissionControl(
                    todos: _todos,
                    activeTab: _missionTab,
                    clock: () => _now,
                    onTabChanged: (tab) => setState(() => _missionTab = tab),
                    onTaskClick: (task) => setState(() => _detailTask = task),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildMobileLayout() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final availableHeight = constraints.maxHeight;
          return switch (_mobileTab) {
            'stream' => GlassCard(
              title: '今日执行流',
              child: TodayHourlyTimeline(
                todos: _todos,
                courses: _courses,
                semesterStart: _semesterStart,
                currentWeek: _calculateCurrentWeek(),
                itemHeight: availableHeight / 26,
                onTaskClick: (task) => setState(() => _detailTask = task),
              ),
            ),
            'roadmap' => GlassCard(
              title: '战略路线图',
              child: GanttChart(
                todos: _ganttTodos,
                dayWidth: _dayWidth,
                onTaskClick: (task) => setState(() => _detailTask = task),
              ),
            ),
            'mission' => GlassCard(
              title: '作战指挥中心',
              child: MissionControl(
                todos: _todos,
                activeTab: _missionTab,
                clock: () => _now,
                onTabChanged: (tab) => setState(() => _missionTab = tab),
                onTaskClick: (task) => setState(() => _detailTask = task),
              ),
            ),
            _ => const SizedBox.shrink(),
          };
        },
      ),
    );
  }

  Widget _buildMobileNav() {
    return Container(
      height: 64,
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        border: Border(
          top: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
        ),
      ),
      child: Row(
        children: [
          _buildNavButton('stream', Icons.access_time, '今日'),
          _buildNavButton('roadmap', Icons.layers, '路线图'),
          _buildNavButton('mission', Icons.check_circle_outline, '任务'),
        ],
      ),
    );
  }

  Widget _buildNavButton(String tab, IconData icon, String label) {
    bool isSelected = _mobileTab == tab;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _mobileTab = tab),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              color: isSelected
                  ? Theme.of(context).colorScheme.primary
                  : Colors.white24,
              size: 20,
            ),
            Text(
              label,
              style: TextStyle(
                color: isSelected
                    ? Theme.of(context).colorScheme.primary
                    : Colors.white24,
                fontSize: 8,
                fontWeight: FontWeight.w900,
                letterSpacing: 1,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFooter() {
    return Container(
      height: 40,
      width: double.infinity,
      color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.05),
      child: Center(
        child: RepaintBoundary(
          child: SingleChildScrollView(
            controller: _marqueeController,
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                const SizedBox(width: 1000), // Start from outside
                Text(
                  '【公告】 实时执行流同步中... 祝您今日工作愉快！',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.6),
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(width: 1000), // Gap
              ],
            ),
          ),
        ),
      ),
    );
  }

  int _calculateCompletionRate() {
    if (_todos.isEmpty) return 0;
    return (_completedTodoCount * 100 ~/ _todos.length);
  }
}

// --- Sub-Widgets ---
