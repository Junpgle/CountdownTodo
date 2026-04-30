import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models.dart';
import '../storage_service.dart';
import '../services/course_service.dart';

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

class _AppBoardScreenState extends State<AppBoardScreen> with TickerProviderStateMixin {
  List<TodoItem> _todos = [];
  List<CountdownItem> _countdowns = [];
  List<CourseItem> _courses = [];
  DateTime? _semesterStart;
  bool _isLoading = true;
  String _mobileTab = 'stream'; // stream, roadmap, mission
  String _missionTab = 'active'; // active, completed
  double _dayWidth = 60.0;
  TodoItem? _detailTask;
  DateTime _now = DateTime.now();
  late Timer _timer;
  final ScrollController _cdScrollController = ScrollController();
  final ScrollController _marqueeController = ScrollController();
  Timer? _marqueeTimer;

  @override
  void initState() {
    super.initState();
    _loadData();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          _now = DateTime.now();
        });
      }
    });
    _startMarquee();
  }

  @override
  void dispose() {
    _timer.cancel();
    _marqueeTimer?.cancel();
    _cdScrollController.dispose();
    _marqueeController.dispose();
    super.dispose();
  }

  void _startMarquee() {
    _marqueeTimer = Timer.periodic(const Duration(milliseconds: 30), (timer) {
      if (_marqueeController.hasClients) {
        double maxScroll = _marqueeController.position.maxScrollExtent;
        double currentScroll = _marqueeController.offset;
        if (currentScroll >= maxScroll - 1) {
          _marqueeController.jumpTo(0);
        } else {
          _marqueeController.animateTo(
            currentScroll + 10,
            duration: const Duration(milliseconds: 300),
            curve: Curves.linear,
          );
        }
      }
    });
  }

  int _calculateCurrentWeek() {
    if (_semesterStart == null) return 1;
    final start = DateTime(_semesterStart!.year, _semesterStart!.month, _semesterStart!.day);
    // Adjust to previous Monday
    final startMonday = start.subtract(Duration(days: start.weekday - 1));
    final today = DateTime(_now.year, _now.month, _now.day);
    final diffDays = today.difference(startMonday).inDays;
    if (diffDays < 0) return 1;
    return (diffDays ~/ 7) + 1;
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
          final key = '${c.courseName}-${c.startTime}-${c.weekday}-${c.weekIndex}';
          if (!seenCourses.contains(key)) {
            seenCourses.add(key);
            uniqueCourses.add(c);
          }
        }

        setState(() {
          _todos = todos.where((t) => !t.isDeleted).toList();
          _countdowns = countdowns.where((c) => !c.isDeleted && c.targetDate.isAfter(_now)).toList();
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
      debugPrint('Error loading board data: $e');
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
    final isDesktop = MediaQuery.of(context).size.width >= 1024;

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
                    ? const Center(child: CircularProgressIndicator(color: Colors.blue))
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

  Widget _buildHeader(bool isDesktop) {
    return Container(
      height: isDesktop ? 100 : 70,
      padding: EdgeInsets.symmetric(horizontal: isDesktop ? 40 : 16),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.05))),
        color: Colors.black.withValues(alpha: 0.2),
      ),
      child: Row(
        children: [
          // Back Button
          IconButton(
            onPressed: widget.onBack ?? () => Navigator.of(context).pop(),
            icon: const Icon(Icons.arrow_back, color: Colors.white70),
            style: IconButton.styleFrom(
              backgroundColor: Colors.white.withValues(alpha: 0.05),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              side: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
            ),
          ),
          const SizedBox(width: 16),
          // Title
          if (isDesktop)
            ShaderMask(
              shaderCallback: (bounds) => const LinearGradient(
                colors: [Colors.white, Colors.white38],
              ).createShader(bounds),
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
                  shaderCallback: (bounds) => const LinearGradient(
                    colors: [Colors.white, Colors.white38],
                  ).createShader(bounds),
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
                    itemCount: _countdowns.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 16),
                    itemBuilder: (context, index) {
                      final cd = _countdowns[index];
                      final diff = cd.targetDate.difference(_now).inDays;
                      final isUrgent = diff < 3;
                      return Container(
                        width: 140,
                        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                        decoration: BoxDecoration(
                          color: (isUrgent ? Colors.red : Colors.blue).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: (isUrgent ? Colors.red : Colors.blue).withValues(alpha: 0.2),
                          ),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              cd.title,
                              style: TextStyle(
                                color: isUrgent ? Colors.redAccent : Colors.blueAccent,
                                fontSize: 10,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 1,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              '${math.max(0, diff)} 天',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                                fontFeatures: [FontFeature.tabularFigures()],
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          if (isDesktop)
            Text(
              DateFormat('HH:mm').format(_now),
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.8),
                fontSize: 48,
                fontWeight: FontWeight.w900,
                letterSpacing: -2,
                fontFeatures: [const FontFeature.tabularFigures()],
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
                    itemHeight: availableHeight / 26, // Fit 24 hours + some padding
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
                        icon: const Icon(Icons.zoom_out, color: Colors.white30, size: 18),
                        onPressed: () => setState(() => _dayWidth = math.max(10, _dayWidth - 5)),
                      ),
                      IconButton(
                        icon: const Icon(Icons.zoom_in, color: Colors.white30, size: 18),
                        onPressed: () => setState(() => _dayWidth = math.min(150, _dayWidth + 5)),
                      ),
                    ],
                  ),
                  child: GanttChart(
                    todos: _todos.where((t) => t.dueDate != null).toList(),
                    dayWidth: _dayWidth == 60.0 ? (availableWidth * 0.5 / 37) : _dayWidth, // Default fit
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
                      const Text('完成率', style: TextStyle(color: Colors.white30, fontSize: 8, fontWeight: FontWeight.w900)),
                      Text(
                        '${_calculateCompletionRate()}%',
                        style: const TextStyle(color: emeraldAccent, fontSize: 12, fontWeight: FontWeight.w900),
                      ),
                    ],
                  ),
                  child: MissionControl(
                    todos: _todos,
                    activeTab: _missionTab,
                    onTabChanged: (tab) => setState(() => _missionTab = tab),
                    onTaskClick: (task) => setState(() => _detailTask = task),
                  ),
                ),
              ),
            ],
          );
        }
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
                  todos: _todos.where((t) => t.dueDate != null).toList(),
                  dayWidth: _dayWidth,
                  onTaskClick: (task) => setState(() => _detailTask = task),
                ),
              ),
            'mission' => GlassCard(
                title: '作战指挥中心',
                child: MissionControl(
                  todos: _todos,
                  activeTab: _missionTab,
                  onTabChanged: (tab) => setState(() => _missionTab = tab),
                  onTaskClick: (task) => setState(() => _detailTask = task),
                ),
              ),
            _ => const SizedBox.shrink(),
          };
        }
      ),
    );
  }

  Widget _buildMobileNav() {
    return Container(
      height: 64,
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.1))),
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
            Icon(icon, color: isSelected ? Colors.blue : Colors.white24, size: 20),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.blue : Colors.white24,
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
      color: Colors.blue.withValues(alpha: 0.05),
      child: Center(
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
    );
  }

  int _calculateCompletionRate() {
    if (_todos.isEmpty) return 0;
    int completed = _todos.where((t) => t.isDone).length;
    return (completed * 100 ~/ _todos.length);
  }
}

// --- Sub-Widgets ---

class GlassCard extends StatelessWidget {
  final String title;
  final Widget child;
  final Widget? headerExtra;
  final String? className;

  const GlassCard({
    super.key,
    required this.title,
    required this.child,
    this.headerExtra,
    this.className,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(40),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.5,
                  ),
                ),
                if (headerExtra != null) headerExtra!,
              ],
            ),
          ),
          Expanded(child: child),
        ],
      ),
    );
  }
}

class AnimatedBackground extends StatefulWidget {
  const AnimatedBackground({super.key});

  @override
  State<AnimatedBackground> createState() => _AnimatedBackgroundState();
}

class _AnimatedBackgroundState extends State<AnimatedBackground> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 10),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Stack(
          children: [
            Positioned(
              top: -100 + (50 * _controller.value),
              left: -100 + (30 * _controller.value),
              child: Container(
                width: 400,
                height: 400,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.blue.withValues(alpha: 0.05 + (0.05 * _controller.value)),
                ),
              ),
            ),
            Positioned(
              bottom: -50 - (40 * _controller.value),
              right: -50 - (20 * _controller.value),
              child: Container(
                width: 350,
                height: 350,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.indigo.withValues(alpha: 0.05 + (0.03 * _controller.value)),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class TodayHourlyTimeline extends StatelessWidget {
  final List<TodoItem> todos;
  final List<CourseItem> courses;
  final DateTime? semesterStart;
  final int currentWeek;
  final double? itemHeight;
  final Function(TodoItem) onTaskClick;

  const TodayHourlyTimeline({
    super.key,
    required this.todos,
    required this.courses,
    this.semesterStart,
    required this.currentWeek,
    this.itemHeight,
    required this.onTaskClick,
  });

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final todayEnd = todayStart.add(const Duration(days: 1));

    // Filter today's items
    final todayCourses = courses.where((c) {
      // Check weekday and weekIndex (if available)
      return c.weekday == now.weekday && (c.weekIndex == 0 || c.weekIndex == currentWeek);
    }).toList();

    final todayTasks = todos.where((t) {
      if (t.dueDate == null) return false;
      return t.dueDate!.isAfter(todayStart) && t.dueDate!.isBefore(todayEnd);
    }).toList();

    return ListView.builder(
      physics: itemHeight != null ? const NeverScrollableScrollPhysics() : const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: 24,
      itemBuilder: (context, hour) {
        final isCurrent = now.hour == hour;
        final hCourses = todayCourses.where((c) => c.startTime ~/ 100 == hour).toList();
        final hTasks = todayTasks.where((t) => t.dueDate!.hour == hour).toList();

        return Container(
          height: itemHeight ?? 60,
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.02))),
            color: isCurrent ? Colors.blue.withValues(alpha: 0.05) : null,
          ),
          child: Row(
            children: [
              SizedBox(
                width: 30,
                child: Text(
                  hour.toString().padLeft(2, '0'),
                  style: TextStyle(
                    color: isCurrent ? Colors.blueAccent : Colors.white.withValues(alpha: 0.1),
                    fontSize: 9,
                    fontWeight: FontWeight.w900,
                    fontFeatures: [const FontFeature.tabularFigures()],
                  ),
                  textAlign: TextAlign.right,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      ...hCourses.map((c) => Container(
                            margin: const EdgeInsets.only(right: 4),
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                            decoration: BoxDecoration(
                              color: Colors.indigo.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: Colors.indigo.withValues(alpha: 0.1)),
                            ),
                            child: Text(
                              c.courseName,
                              style: const TextStyle(color: Colors.white70, fontSize: 8, fontWeight: FontWeight.bold),
                            ),
                          )),
                      ...hTasks.map((t) => GestureDetector(
                            onTap: () => onTaskClick(t),
                            child: Container(
                              margin: const EdgeInsets.only(right: 4),
                              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                              decoration: BoxDecoration(
                                color: (t.isDone ? emerald : Colors.blue).withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(color: (t.isDone ? emerald : Colors.blue).withValues(alpha: 0.1)),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    width: 3,
                                    height: 3,
                                    decoration: BoxDecoration(
                                      color: t.isDone ? emeraldAccent : Colors.blueAccent,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 2),
                                  Text(
                                    t.title,
                                    style: TextStyle(
                                      color: t.isDone ? Colors.white30 : Colors.white,
                                      fontSize: 8,
                                      fontWeight: FontWeight.bold,
                                      decoration: t.isDone ? TextDecoration.lineThrough : null,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          )),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class GanttChart extends StatefulWidget {
  final List<TodoItem> todos;
  final double dayWidth;
  final Function(TodoItem) onTaskClick;

  const GanttChart({
    super.key,
    required this.todos,
    required this.dayWidth,
    required this.onTaskClick,
  });

  @override
  State<GanttChart> createState() => _GanttChartState();
}

class _GanttChartState extends State<GanttChart> {
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToToday();
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToToday() {
    if (_scrollController.hasClients) {
      final now = DateTime.now();
      final minDate = now.subtract(const Duration(days: 7));
      final todayOffset = now.difference(minDate).inHours / 24 * widget.dayWidth;
      final viewportWidth = _scrollController.position.viewportDimension;
      _scrollController.jumpTo(math.max(0, todayOffset - (viewportWidth / 2)));
    }
  }

  List<List<TodoItem>> _packTasks(List<TodoItem> tasks, DateTime minDate, DateTime maxDate) {
    if (tasks.isEmpty) return [];

    // Split into active and completed
    final activeTasks = tasks.where((t) => !t.isDone).toList();
    final completedTasks = tasks.where((t) => t.isDone).toList();

    List<List<TodoItem>> packGroup(List<TodoItem> group) {
      if (group.isEmpty) return [];
      
      // Sort by start date
      final sorted = List<TodoItem>.from(group)
        ..sort((a, b) {
          final startA = a.createdAt != 0 ? DateTime.fromMillisecondsSinceEpoch(a.createdAt) : a.dueDate!.subtract(const Duration(days: 3));
          final startB = b.createdAt != 0 ? DateTime.fromMillisecondsSinceEpoch(b.createdAt) : b.dueDate!.subtract(const Duration(days: 3));
          return startA.compareTo(startB);
        });

      final List<List<TodoItem>> rows = [];
      for (final task in sorted) {
        final start = task.createdAt != 0 ? DateTime.fromMillisecondsSinceEpoch(task.createdAt) : task.dueDate!.subtract(const Duration(days: 3));
        final end = task.dueDate!;
        if (end.isBefore(minDate) || start.isAfter(maxDate)) continue;

        bool placed = false;
        for (final row in rows) {
          bool overlaps = false;
          for (final existingTask in row) {
            final eStart = existingTask.createdAt != 0 ? DateTime.fromMillisecondsSinceEpoch(existingTask.createdAt) : existingTask.dueDate!.subtract(const Duration(days: 3));
            final eEnd = existingTask.dueDate!;
            if (end.isAfter(eStart.subtract(const Duration(hours: 2))) && start.isBefore(eEnd.add(const Duration(hours: 2)))) {
              overlaps = true;
              break;
            }
          }
          if (!overlaps) {
            row.add(task);
            placed = true;
            break;
          }
        }
        if (!placed) rows.add([task]);
      }
      return rows;
    }

    // Pack active tasks (top) then completed tasks (bottom)
    return [...packGroup(activeTasks), ...packGroup(completedTasks)];
  }

  @override
  Widget build(BuildContext context) {
    if (widget.todos.isEmpty) {
      return const Center(child: Text('暂无带日期的任务', style: TextStyle(color: Colors.white24)));
    }

    final now = DateTime.now();
    
    // Calculate dynamic range based on tasks
    DateTime minDate = now.subtract(const Duration(days: 7));
    DateTime maxDate = now.add(const Duration(days: 30));

    for (var t in widget.todos) {
      final start = t.createdAt != 0 ? DateTime.fromMillisecondsSinceEpoch(t.createdAt) : t.dueDate!.subtract(const Duration(days: 3));
      final end = t.dueDate!;
      if (start.isBefore(minDate)) minDate = start;
      if (end.isAfter(maxDate)) maxDate = end;
    }

    // Add buffers
    minDate = DateTime(minDate.year, minDate.month, minDate.day).subtract(const Duration(days: 7));
    maxDate = DateTime(maxDate.year, maxDate.month, maxDate.day).add(const Duration(days: 7));
    
    final totalDays = maxDate.difference(minDate).inDays;
    final packedRows = _packTasks(widget.todos, minDate, maxDate);

    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth;
        final effectiveDayWidth = widget.dayWidth <= 0 || widget.dayWidth == 60.0 
            ? availableWidth / totalDays 
            : widget.dayWidth;
        
        final totalWidth = totalDays * effectiveDayWidth;

        return SingleChildScrollView(
          controller: _scrollController,
          scrollDirection: Axis.horizontal,
          physics: totalWidth <= availableWidth + 1 ? const NeverScrollableScrollPhysics() : const BouncingScrollPhysics(),
          child: SizedBox(
            width: totalWidth,
            child: Stack(
              children: [
                // Grid Lines & Header
                Column(
                  children: [
                    Row(
                      children: List.generate(totalDays, (index) {
                        final date = minDate.add(Duration(days: index));
                        final isToday = date.day == now.day && date.month == now.month && date.year == now.year;
                        return Container(
                          width: effectiveDayWidth,
                          height: 40,
                          decoration: BoxDecoration(
                            border: Border(right: BorderSide(color: Colors.white.withValues(alpha: 0.05))),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                DateFormat('E').format(date).toUpperCase(),
                                style: TextStyle(
                                  color: isToday ? Colors.blue : Colors.white12, 
                                  fontSize: math.max(6.0, effectiveDayWidth / 5), 
                                  fontWeight: FontWeight.w900
                                ),
                              ),
                              Text(
                                date.day.toString(),
                                style: TextStyle(
                                  color: isToday ? Colors.white : Colors.white30, 
                                  fontSize: math.max(8.0, effectiveDayWidth / 4), 
                                  fontWeight: FontWeight.bold
                                ),
                              ),
                            ],
                          ),
                        );
                      }),
                    ),
                    Expanded(
                      child: Row(
                        children: List.generate(totalDays, (index) {
                          return Container(
                            width: effectiveDayWidth,
                            decoration: BoxDecoration(
                              border: Border(right: BorderSide(color: Colors.white.withValues(alpha: 0.02))),
                            ),
                          );
                        }),
                      ),
                    ),
                  ],
                ),
                // Today Line
                Positioned(
                  left: now.difference(minDate).inHours / 24 * effectiveDayWidth,
                  top: 0,
                  bottom: 0,
                  child: Container(
                    width: 1,
                    color: Colors.blue.withValues(alpha: 0.5),
                  ),
                ),
                // Task Rows
                Padding(
                  padding: const EdgeInsets.only(top: 50),
                  child: ListView.builder(
                    itemCount: packedRows.length,
                    itemBuilder: (context, rowIndex) {
                      final rowTasks = packedRows[rowIndex];
                      return Container(
                        height: 28,
                        margin: const EdgeInsets.symmetric(vertical: 2),
                        child: Stack(
                          children: rowTasks.map((task) {
                            final start = task.createdAt != 0 ? DateTime.fromMillisecondsSinceEpoch(task.createdAt) : task.dueDate!.subtract(const Duration(days: 3));
                            final end = task.dueDate!;
                            
                            final left = math.max(0.0, start.difference(minDate).inHours / 24 * effectiveDayWidth);
                            final width = math.max(effectiveDayWidth * 0.5, end.difference(start).inHours / 24 * effectiveDayWidth);

                            return Positioned(
                              left: left,
                              width: width,
                              top: 0,
                              bottom: 0,
                              child: GestureDetector(
                                onTap: () => widget.onTaskClick(task),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 4),
                                  decoration: BoxDecoration(
                                    color: (task.teamUuid != null ? Colors.blue : emerald).withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(color: (task.teamUuid != null ? Colors.blue : emerald).withValues(alpha: 0.3)),
                                  ),
                                  alignment: Alignment.centerLeft,
                                  child: Text(
                                    task.title,
                                    style: TextStyle(
                                      color: task.isDone ? Colors.white24 : Colors.white,
                                      fontSize: 8,
                                      fontWeight: FontWeight.w900,
                                      decoration: task.isDone ? TextDecoration.lineThrough : null,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      }
    );
  }
}

class MissionControl extends StatelessWidget {
  final List<TodoItem> todos;
  final String activeTab;
  final Function(String) onTabChanged;
  final Function(TodoItem) onTaskClick;

  const MissionControl({
    super.key,
    required this.todos,
    required this.activeTab,
    required this.onTabChanged,
    required this.onTaskClick,
  });

  @override
  Widget build(BuildContext context) {
    final activeTasks = todos.where((t) => !t.isDone).toList();
    final completedTasks = todos.where((t) => t.isDone).toList();
    final displayTasks = activeTab == 'active' ? activeTasks : completedTasks;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                _buildTab('active', '活跃任务', Colors.blue),
                _buildTab('completed', '历史记录', emerald),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            itemCount: displayTasks.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final task = displayTasks[index];
              final isOverdue = task.dueDate != null && task.dueDate!.isBefore(DateTime.now()) && !task.isDone;
              
              return InkWell(
                onTap: () => onTaskClick(task),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isOverdue ? Colors.red.withValues(alpha: 0.05) : Colors.white.withValues(alpha: 0.02),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: isOverdue ? Colors.red.withValues(alpha: 0.2) : Colors.white.withValues(alpha: 0.05)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: activeTab == 'active' ? Colors.blueAccent : emeraldAccent,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              task.title,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.9),
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                decoration: task.isDone ? TextDecoration.lineThrough : null,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              '${task.creatorName ?? "用户"} · ${task.dueDate != null ? DateFormat('HH:mm').format(task.dueDate!) : "无时间"}',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.2),
                                fontSize: 8,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildTab(String tab, String label, Color activeColor) {
    bool isSelected = activeTab == tab;
    return Expanded(
      child: GestureDetector(
        onTap: () => onTabChanged(tab),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? activeColor : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            boxShadow: isSelected ? [BoxShadow(color: activeColor.withValues(alpha: 0.3), blurRadius: 8)] : null,
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              color: isSelected ? Colors.white : Colors.white24,
              fontSize: 10,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ),
    );
  }
}

class TaskDetailModal extends StatelessWidget {
  final TodoItem task;
  final VoidCallback onClose;

  const TaskDetailModal({super.key, required this.task, required this.onClose});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onClose,
      child: Container(
        color: Colors.black.withValues(alpha: 0.8),
        child: Center(
          child: GestureDetector(
            onTap: () {}, // Prevent closing when clicking modal
            child: Container(
              width: math.min(600, MediaQuery.of(context).size.width * 0.9),
              constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.8),
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A),
                borderRadius: BorderRadius.circular(32),
                border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
              ),
              clipBehavior: Clip.antiAlias,
              child: Stack(
                children: [
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    height: 6,
                    child: Container(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(colors: [Colors.blue, Colors.indigo]),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(32),
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                decoration: BoxDecoration(
                                  color: (task.teamUuid != null ? Colors.blue : emerald).withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(color: (task.teamUuid != null ? Colors.blue : emerald).withValues(alpha: 0.3)),
                                ),
                                child: Text(
                                  task.teamName ?? '个人空间',
                                  style: TextStyle(
                                    color: task.teamUuid != null ? Colors.blueAccent : emeraldAccent,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.close, color: Colors.white24),
                                onPressed: onClose,
                              ),
                            ],
                          ),
                          const SizedBox(height: 24),
                          Text(
                            task.title,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 32,
                              fontWeight: FontWeight.w900,
                              height: 1.1,
                            ),
                          ),
                          const SizedBox(height: 32),
                          _buildInfoRow(Icons.access_time, '开始时间', DateFormat('yyyy-MM-dd HH:mm').format(DateTime.fromMillisecondsSinceEpoch(task.createdAt))),
                          _buildInfoRow(Icons.calendar_today, '截止时间', task.dueDate != null ? DateFormat('yyyy-MM-dd HH:mm').format(task.dueDate!) : '无截止日期'),
                          _buildInfoRow(Icons.person_outline, '创建者', task.creatorName ?? '我'),
                          const SizedBox(height: 24),
                          const Text('备注与详情', style: TextStyle(color: Colors.white24, fontSize: 10, fontWeight: FontWeight.w900)),
                          const SizedBox(height: 12),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.03),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
                            ),
                            child: Text(
                              task.remark ?? '暂无详细备注说明。',
                              style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 14, height: 1.6),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          Icon(icon, color: Colors.white24, size: 16),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(color: Colors.white24, fontSize: 8, fontWeight: FontWeight.w900)),
              Text(value, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
            ],
          ),
        ],
      ),
    );
  }
}
