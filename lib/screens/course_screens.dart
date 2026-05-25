import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../services/course_service.dart';
import '../services/pomodoro_service.dart';
import '../services/ai_todo_chat_launcher.dart';
import '../services/ai_todo_action_executor.dart';
import '../models.dart';
import '../storage_service.dart';
import '../utils/page_transitions.dart';
import 'time_log_screen.dart';
import 'course_month_view.dart';
import '../widgets/team_heatmap_widget.dart';
import '../widgets/team_gantt_widget.dart';
import '../utils/timezone_utils.dart';

// --- 二级界面：按周查看课表 (全屏自适应压缩视图) ---
class WeeklyCourseScreen extends StatefulWidget {
  final String username;
  const WeeklyCourseScreen({super.key, required this.username});

  @override
  State<WeeklyCourseScreen> createState() => _WeeklyCourseScreenState();
}

class _HiddenTimeRange {
  const _HiddenTimeRange(this.startMinute, this.endMinute);

  final double startMinute;
  final double endMinute;

  double get duration => endMinute - startMinute;

  bool contains(double minute) => minute > startMinute && minute < endMinute;

  double hiddenBefore(double minute) {
    if (minute <= startMinute) return 0.0;
    if (minute >= endMinute) return duration;
    return minute - startMinute;
  }
}

class _WeeklyCourseScreenState extends State<WeeklyCourseScreen>
    with TickerProviderStateMixin {
  int _currentWeek = 1;
  List<int> _availableWeeks = [];
  List<CourseItem> _weekCourses = [];

  List<TodoItem> _allTodos = [];

  // 拆分：全天/跨天待办 和 日内局部待办
  Map<int, List<TodoItem>> _allDayTodosPerDay = {};
  Map<int, List<TodoItem>> _intraDayTodosPerDay = {};

  bool _isLoading = true;
  DateTime? _semesterMonday;

  List<TimeLogItem> _allTimeLogs = [];
  List<PomodoroRecord> _allPomodoroRecords = [];
  List<PomodoroTag> _pomodoroTags = [];
  List<TodoPlanBlock> _allPlanBlocks = [];
  Map<int, List<TimeLogItem>> _timeLogsPerDay = {};
  Map<int, List<PomodoroRecord>> _pomodorosPerDay = {};
  Map<int, List<TodoPlanBlock>> _planBlocksPerDay = {};
  final Set<String> _activeDataViews = {
    'courses',
    'todos',
    'plans',
    'timeLogs',
    'pomodoros'
  };
  bool _collapseFreeTime = true;

  // --- 🚀 视图模式分级 (1周, 2周, 1个月) ---
  int _viewMode = 0; // 0: 1周, 1: 2周, 2: 1个月
  DateTime _selectedMonth = DateTime.now();
  List<CourseItem> _allCourses = [];
  final double _baseScale = 1.0;
  final double _currentScale = 1.0;
  bool _isNextSlide = true;
  double _dragOffset = 0.0; // 实时跟踪滑动位移
  DateTime? _selectedMonthDay; // 平板模式下月视图选中的日期

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  late AnimationController _courseExpandCtrl;
  late Animation<double> _courseExpandAnim;

  late PageController _pageController;
  final Map<String, GlobalKey> _courseCardKeys = {};
  final Map<String, GlobalKey> _todoCardKeys = {};
  final Map<String, GlobalKey> _timeLogCardKeys = {};
  final Map<String, GlobalKey> _pomodoroCardKeys = {};

  GlobalKey _getCourseCardKey(String courseName, int weekday, int startTime) {
    // Include current week to avoid key collisions while AnimatedSwitcher keeps
    // both previous and next week grids in the tree during transition.
    final keyStr = 'w${_currentWeek}_${courseName}_${weekday}_$startTime';
    return _courseCardKeys.putIfAbsent(keyStr, () => GlobalKey());
  }

  GlobalKey _getTodoCardKey(String id) {
    final keyStr = 'w${_currentWeek}_$id';
    return _todoCardKeys.putIfAbsent(keyStr, () => GlobalKey());
  }

  GlobalKey _getTimeLogCardKey(String id) {
    final keyStr = 'w${_currentWeek}_$id';
    return _timeLogCardKeys.putIfAbsent(keyStr, () => GlobalKey());
  }

  GlobalKey _getPomodoroCardKey(String id) {
    final keyStr = 'w${_currentWeek}_$id';
    return _pomodoroCardKeys.putIfAbsent(keyStr, () => GlobalKey());
  }

  // 时间轴参数配置
  final double timeColumnWidth = 45.0;
  final int startHour = 6;
  final int endHour = 24;

  // 自适应空闲时间压缩：统一记录所有被扣除的绝对时间区间。
  List<_HiddenTimeRange> _hiddenTimeRanges = const [];
  double? _lunchCardStartMinute;
  double _lunchCardDuration = 0.0;
  String _lunchCollapseText = '';
  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.3, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _courseExpandCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _courseExpandAnim = CurvedAnimation(
      parent: _courseExpandCtrl,
      curve: Curves.easeOutCubic,
    );
    _pageController = PageController(initialPage: 0);
    _loadData();
  }

  DateTime? _lastModeSwitch;
  final double _lastScale = 1.0;

  @override
  void dispose() {
    _pulseController.dispose();
    _courseExpandCtrl.dispose();
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    // 🚀 核心优化：并行加载所有基础数据，消除重复调用
    final results = await Future.wait([
      CourseService.getAllCourses(widget.username),
      StorageService.getTodos(widget.username),
      StorageService.getTimeLogs(widget.username),
      PomodoroService.getRecords(),
      PomodoroService.getTags(),
      StorageService.getPlanBlocks(widget.username),
      StorageService.getSemesterStart(),
    ]);

    // 🚀 核心优化：等待 300ms 让进入页面的过渡动画彻底完成
    // 避免在动画期间进行大量 CPU 计算导致界面掉帧
    await Future.delayed(const Duration(milliseconds: 300));

    if (!mounted) return;

    _allCourses = results[0] as List<CourseItem>;
    final List<TodoItem> allTodosRaw = results[1] as List<TodoItem>;
    final List<TimeLogItem> allLogsRaw = results[2] as List<TimeLogItem>;
    _allPomodoroRecords = results[3] as List<PomodoroRecord>;
    _pomodoroTags = results[4] as List<PomodoroTag>;
    DateTime? semStart = results[6] as DateTime?;

    // 1. 处理课程相关数据
    if (_allCourses.isNotEmpty) {
      _availableWeeks = _allCourses.map((c) => c.weekIndex).toSet().toList();
      _availableWeeks.sort();
    } else {
      _availableWeeks = List.generate(20, (index) => index + 1);
    }

    // 2. 处理待办
    _allTodos = allTodosRaw.where((t) => !t.isDeleted).toList();

    // 3. 处理日志
    _allTimeLogs = allLogsRaw.where((l) => !l.isDeleted).toList();

    // 4. 计算学期起始周
    _allPlanBlocks =
        (results[5] as List<TodoPlanBlock>).where((p) => !p.isDeleted).toList();

    if (semStart != null) {
      _semesterMonday = semStart.subtract(Duration(days: semStart.weekday - 1));
    } else if (_allCourses.isNotEmpty) {
      final sortedCourses = List<CourseItem>.from(_allCourses)
        ..sort((a, b) => a.weekIndex.compareTo(b.weekIndex));
      final firstCourse = sortedCourses.first;
      if (firstCourse.date.isNotEmpty) {
        DateTime firstCourseDate =
            DateFormat('yyyy-MM-dd').parse(firstCourse.date);
        _semesterMonday = firstCourseDate
            .subtract(Duration(days: firstCourse.weekday - 1))
            .subtract(Duration(
                days: (firstCourse.weekIndex > 0 ? firstCourse.weekIndex : 0) *
                    7));
      }
    }

    if (_semesterMonday == null) {
      DateTime now = DateTime.now();
      _semesterMonday = now.subtract(Duration(days: now.weekday - 1));
    }

    // 5. 计算当前周
    DateTime now = DateTime.now();
    int daysOffset = now.difference(_semesterMonday!).inDays;
    _currentWeek = (daysOffset ~/ 7) + 1;

    // 6. 获取当前周课程
    _weekCourses =
        _allCourses.where((c) => c.weekIndex == _currentWeek).toList();

    // 7. 月视图数据按需构建，避免首次进入课程页就做全量逐日展开
    _monthDataPrepared = false;
    if (_viewMode == 2) {
      _groupDataForMonthView();
    }
    _updateWeekTodos();
    _updateWeekTimeLogsPomodorosAndPlans();
    _checkCollapsedSlots();

    if (mounted) {
      setState(() => _isLoading = false);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _courseExpandCtrl.forward();
      });
    }
  }

  // --- 🚀 性能优化: 预先按日期分组数据 (避免在动画期间重复计算) ---
  Map<String, List<CourseItem>> _monthCourseMap = {};
  Map<String, List<TodoItem>> _monthTodoMap = {};
  Map<String, List<TodoItem>> _monthCrossDayTodoMap = {};
  Map<String, List<TimeLogItem>> _monthLogMap = {};
  Map<String, List<PomodoroRecord>> _monthPomMap = {};
  Map<String, List<TodoPlanBlock>> _monthPlanMap = {};
  bool _monthDataPrepared = false;
  static const int _maxExpandedSpanDays = 366;

  void _groupDataForMonthView() {
    _monthDataPrepared = true;
    _monthCourseMap = {};
    _monthTodoMap = {};
    _monthCrossDayTodoMap = {};
    _monthLogMap = {};
    _monthPomMap = {};
    _monthPlanMap = {};

    final df = DateFormat('yyyy-MM-dd');

    // 1. 课程分组
    for (var c in _allCourses) {
      if (c.date.isNotEmpty) {
        _monthCourseMap.putIfAbsent(c.date, () => []).add(c);
      } else if (_semesterMonday != null && c.weekIndex > 0) {
        final date = _semesterMonday!
            .add(Duration(days: (c.weekIndex - 1) * 7 + (c.weekday - 1)));
        _monthCourseMap.putIfAbsent(df.format(date), () => []).add(c);
      }
    }

    // 2. 待办分组 (优化：减少 DateFormat 调用)
    for (var t in _allTodos) {
      DateTime tStart =
          DateTime.fromMillisecondsSinceEpoch(t.createdDate ?? t.createdAt)
              .toLocal();
      DateTime tEnd = t.dueDate ?? tStart.add(const Duration(hours: 1));

      bool isAllDay = t.dueDate != null &&
          tStart.hour == 0 &&
          tStart.minute == 0 &&
          t.dueDate!.hour == 23 &&
          t.dueDate!.minute == 59;
      bool isAcross = !(tStart.year == tEnd.year &&
          tStart.month == tEnd.month &&
          tStart.day == tEnd.day);

      _forEachExpandedDay(
        start: tStart,
        end: tEnd,
        debugLabel: 'todo:${t.id}',
        onDay: (cursor) {
          final dStr = df.format(cursor);
          if (isAllDay || isAcross) {
            _monthCrossDayTodoMap.putIfAbsent(dStr, () => []).add(t);
          } else {
            _monthTodoMap.putIfAbsent(dStr, () => []).add(t);
          }
        },
      );
    }

    // 3. 日志与番茄钟
    for (var l in _allTimeLogs) {
      DateTime lStart =
          DateTime.fromMillisecondsSinceEpoch(l.startTime).toLocal();
      DateTime lEnd = DateTime.fromMillisecondsSinceEpoch(l.endTime).toLocal();
      _forEachExpandedDay(
        start: lStart,
        end: lEnd,
        debugLabel: 'timeLog:${l.id}',
        onDay: (cursor) {
          _monthLogMap.putIfAbsent(df.format(cursor), () => []).add(l);
        },
      );
    }

    for (var p in _allPomodoroRecords) {
      if (p.startTime <= 0) continue;
      DateTime pStart =
          DateTime.fromMillisecondsSinceEpoch(p.startTime).toLocal();
      int pEndMs = p.endTime ?? (p.startTime + p.effectiveDuration * 1000);
      DateTime pEnd = DateTime.fromMillisecondsSinceEpoch(pEndMs).toLocal();
      _forEachExpandedDay(
        start: pStart,
        end: pEnd,
        debugLabel: 'pomodoro:${p.uuid}',
        onDay: (cursor) {
          _monthPomMap.putIfAbsent(df.format(cursor), () => []).add(p);
        },
      );
    }

    for (var plan in _allPlanBlocks) {
      if (plan.startTime <= 0 || plan.endTime <= plan.startTime) continue;
      final start =
          DateTime.fromMillisecondsSinceEpoch(plan.startTime).toLocal();
      final end = DateTime.fromMillisecondsSinceEpoch(plan.endTime).toLocal();
      _forEachExpandedDay(
        start: start,
        end: end,
        debugLabel: 'plan:${plan.uuid}',
        onDay: (cursor) {
          _monthPlanMap.putIfAbsent(df.format(cursor), () => []).add(plan);
        },
      );
    }
  }

  void _forEachExpandedDay({
    required DateTime start,
    required DateTime end,
    required String debugLabel,
    required void Function(DateTime day) onDay,
  }) {
    final dayStart = DateTime(start.year, start.month, start.day);
    final dayEnd = DateTime(end.year, end.month, end.day);
    final spanDays = dayEnd.difference(dayStart).inDays;

    if (spanDays < 0) {
      debugPrint(
          '[CourseScreen] Skip invalid span for $debugLabel: start=$start end=$end');
      return;
    }
    if (spanDays > _maxExpandedSpanDays) {
      debugPrint(
          '[CourseScreen] Skip oversized span for $debugLabel: ${spanDays + 1} days');
      return;
    }

    var cursor = dayStart;
    while (!cursor.isAfter(dayEnd)) {
      onDay(cursor);
      cursor = cursor.add(const Duration(days: 1));
    }
  }

  void _updateWeekTodos() {
    _allDayTodosPerDay = {1: [], 2: [], 3: [], 4: [], 5: [], 6: [], 7: []};
    _intraDayTodosPerDay = {1: [], 2: [], 3: [], 4: [], 5: [], 6: [], 7: []};

    if (_semesterMonday == null) return;

    DateTime currentWeekMonday =
        _semesterMonday!.add(Duration(days: (_currentWeek - 1) * 7));
    DateTime currentWeekMondayStart = DateTime(
        currentWeekMonday.year, currentWeekMonday.month, currentWeekMonday.day);

    for (var todo in _allTodos) {
      DateTime start = DateTime.fromMillisecondsSinceEpoch(
              todo.createdDate ?? todo.createdAt,
              isUtc: true)
          .toLocal();
      DateTime end = todo.dueDate ?? start.add(const Duration(hours: 1));

      bool isAllDayFlag = todo.dueDate != null &&
          start.hour == 0 &&
          start.minute == 0 &&
          todo.dueDate!.hour == 23 &&
          todo.dueDate!.minute == 59;
      bool isCrossDay = !(start.year == end.year &&
          start.month == end.month &&
          start.day == end.day);
      bool treatAsAllDay = isAllDayFlag || isCrossDay;

      if (_activeDataViews.contains('hideCrossDay') && isCrossDay) {
        continue;
      }

      for (int i = 1; i <= 7; i++) {
        DateTime dayStart = currentWeekMondayStart.add(Duration(days: i - 1));
        DateTime dayEnd =
            dayStart.add(const Duration(hours: 23, minutes: 59, seconds: 59));

        if (start.isBefore(dayEnd) && end.isAfter(dayStart)) {
          if (treatAsAllDay) {
            _allDayTodosPerDay[i]!.add(todo);
          } else {
            _intraDayTodosPerDay[i]!.add(todo);
          }
        }
      }
    }

    // 排序：未完成优先
    for (int i = 1; i <= 7; i++) {
      _allDayTodosPerDay[i]!.sort((a, b) {
        if (a.isDone == b.isDone) return 0;
        return a.isDone ? 1 : -1;
      });
      _intraDayTodosPerDay[i]!.sort((a, b) {
        if (a.isDone == b.isDone) return 0;
        return a.isDone ? 1 : -1;
      });
    }
  }

  void _updateWeekTimeLogsPomodorosAndPlans() {
    _timeLogsPerDay = {1: [], 2: [], 3: [], 4: [], 5: [], 6: [], 7: []};
    _pomodorosPerDay = {1: [], 2: [], 3: [], 4: [], 5: [], 6: [], 7: []};
    _planBlocksPerDay = {1: [], 2: [], 3: [], 4: [], 5: [], 6: [], 7: []};

    if (_semesterMonday == null) return;

    DateTime currentWeekMonday =
        _semesterMonday!.add(Duration(days: (_currentWeek - 1) * 7));

    for (int i = 1; i <= 7; i++) {
      DateTime dayStart = currentWeekMonday.add(Duration(days: i - 1));
      DateTime dayStartMs =
          DateTime(dayStart.year, dayStart.month, dayStart.day);
      DateTime dayEndMs = dayStartMs.add(const Duration(days: 1));

      int dayStartMsEpoch = dayStartMs.millisecondsSinceEpoch;
      int dayEndMsEpoch = dayEndMs.millisecondsSinceEpoch;

      for (var log in _allTimeLogs) {
        if (log.endTime > dayStartMsEpoch && log.startTime < dayEndMsEpoch) {
          _timeLogsPerDay[i]!.add(log);
        }
      }

      for (var record in _allPomodoroRecords) {
        int recordEnd = record.endTime ??
            (record.startTime + record.effectiveDuration * 1000);
        if (recordEnd > dayStartMsEpoch && record.startTime < dayEndMsEpoch) {
          // 🚀 跳过与计划块关联的番茄钟，避免重复显示
          if (!_isPomodoroAssociatedWithPlan(record)) {
            _pomodorosPerDay[i]!.add(record);
          }
        }
      }

      for (var plan in _allPlanBlocks) {
        if (plan.endTime > dayStartMsEpoch && plan.startTime < dayEndMsEpoch) {
          _planBlocksPerDay[i]!.add(plan);
        }
      }
    }
  }

  void _changeWeek(int delta) {
    _isNextSlide = delta > 0;
    _jumpToWeek(_currentWeek + delta);
  }

  void _jumpToWeek(int newWeek) {
    if (!mounted) return;
    setState(() {
      _currentWeek = newWeek;
      _isLoading = true;
    });

    // 🚀 核心优化：直接使用已加载的 _allCourses 进行过滤，不再触发数据库/Isolate 开销
    _weekCourses = _allCourses.where((c) => c.weekIndex == newWeek).toList();
    _updateWeekTodos();
    _updateWeekTimeLogsPomodorosAndPlans();
    _checkCollapsedSlots();

    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  void _toggleViewMode(int mode) {
    if (_viewMode == mode) return;
    setState(() {
      _viewMode = mode;
      if (mode == 0) {
        _updateWeekTodos();
      } else if (mode == 2 && !_monthDataPrepared) {
        _groupDataForMonthView();
      }
    });
  }

  void _changeMonth(int delta) {
    setState(() {
      _isNextSlide = delta > 0;
      _selectedMonth =
          DateTime(_selectedMonth.year, _selectedMonth.month + delta, 1);
    });
  }

  String _getWeekLabel() {
    if (_viewMode == 2) {
      return DateFormat('yyyy年M月').format(_selectedMonth);
    }
    if (_semesterMonday == null) return '第 $_currentWeek 周';
    DateTime monday =
        _semesterMonday!.add(Duration(days: (_currentWeek - 1) * 7));
    DateTime sunday = monday.add(const Duration(days: 6));

    int maxWeek = _availableWeeks.isNotEmpty ? _availableWeeks.last : 20;

    if (_currentWeek >= 1 && _currentWeek <= maxWeek) {
      return '第 $_currentWeek 周';
    } else if (_currentWeek < 1) {
      return '学期前 ${1 - _currentWeek} 周';
    } else {
      return '${DateFormat('M/d').format(monday)}-${DateFormat('M/d').format(sunday)}';
    }
  }

  String _getBiWeekLabel() {
    if (_semesterMonday == null) return "第$_currentWeek-${_currentWeek + 1}周";

    DateTime w1Monday =
        _semesterMonday!.add(Duration(days: (_currentWeek - 1) * 7));
    DateTime w2Monday = w1Monday.add(const Duration(days: 7));

    String m1 = DateFormat('M月').format(w1Monday);
    String m2 = DateFormat('M月').format(w2Monday);

    // 计算每月第几周 (简易： (day-1)/7 + 1)
    int wk1 = ((w1Monday.day - 1) / 7).floor() + 1;
    int wk2 = ((w2Monday.day - 1) / 7).floor() + 1;

    if (m1 == m2) {
      return "$m1 第$wk1-$wk2周";
    } else {
      return "$m1第$wk1周-$m2第$wk2周";
    }
  }

  void _showWeekJumpDialog() {
    final TextEditingController controller =
        TextEditingController(text: '$_currentWeek');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('跳转到指定周'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: '周次',
                border: OutlineInputBorder(),
                suffixText: '周',
              ),
              autofocus: true,
            ),
            if (_availableWeeks.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                '有课周次：${_availableWeeks.first}-${_availableWeeks.last}周',
                style: const TextStyle(color: Colors.grey, fontSize: 12),
              ),
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [
                ActionChip(
                  label: const Text('本周'),
                  onPressed: () {
                    Navigator.pop(ctx);
                    _jumpToCurrentWeek();
                  },
                ),
                if (_availableWeeks.isNotEmpty)
                  ActionChip(
                    label: Text('第${_availableWeeks.first}周'),
                    onPressed: () {
                      Navigator.pop(ctx);
                      _jumpToWeek(_availableWeeks.first);
                    },
                  ),
                if (_availableWeeks.isNotEmpty)
                  ActionChip(
                    label: Text('第${_availableWeeks.last}周'),
                    onPressed: () {
                      Navigator.pop(ctx);
                      _jumpToWeek(_availableWeeks.last);
                    },
                  ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
            onPressed: () {
              int? week = int.tryParse(controller.text.trim());
              if (week != null && week >= 1) {
                Navigator.pop(ctx);
                _jumpToWeek(week);
              }
            },
            child: const Text('跳转'),
          ),
        ],
      ),
    );
  }

  void _jumpToCurrentWeek() {
    if (_semesterMonday == null) return;
    DateTime now = DateTime.now();
    int daysDiff = now.difference(_semesterMonday!).inDays;
    int week = (daysDiff ~/ 7) + 1;
    if (week < 1) week = 1;
    _jumpToWeek(week);
  }

  Widget _buildMonthDaySidebar(DateTime day) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final String dateStr = DateFormat('yyyy年M月d日').format(day);
    final String weekdayStr =
        ['周一', '周二', '周三', '周四', '周五', '周六', '周日'][day.weekday - 1];

    final dStr = DateFormat('yyyy-MM-dd').format(day);
    final List<dynamic> items = [];

    // 根据筛选条件收集数据
    if (_activeDataViews.contains('courses')) {
      items.addAll(_monthCourseMap[dStr] ?? []);
    }

    if (_activeDataViews.contains('todos')) {
      items.addAll(_monthTodoMap[dStr] ?? []);
      if (!_activeDataViews.contains('hideCrossDay')) {
        items.addAll(_monthCrossDayTodoMap[dStr] ?? []);
      }
    }

    if (_activeDataViews.contains('timeLogs')) {
      items.addAll(_monthLogMap[dStr] ?? []);
    }

    if (_activeDataViews.contains('plans')) {
      items.addAll(_monthPlanMap[dStr] ?? []);
    }

    if (_activeDataViews.contains('pomodoros')) {
      items.addAll(_monthPomMap[dStr] ?? []);
    }

    items.sort((a, b) {
      int getStartTime(dynamic item) {
        if (item is CourseItem) {
          // 课程：转换为当天的分钟数进行比较
          return item.startTime;
        }
        if (item is TodoItem) {
          // 待办：如果是全天/跨天，取创建时间或 0 点；如果是日内，取 dueDate 的时间
          if (item.dueDate == null) return 0;
          return item.dueDate!.hour * 100 + item.dueDate!.minute;
        }
        if (item is TimeLogItem) {
          final dt =
              DateTime.fromMillisecondsSinceEpoch(item.startTime, isUtc: true)
                  .toLocal();
          return dt.hour * 100 + dt.minute;
        }
        if (item is TodoPlanBlock) {
          final dt =
              DateTime.fromMillisecondsSinceEpoch(item.startTime).toLocal();
          return dt.hour * 100 + dt.minute;
        }
        if (item is PomodoroRecord) {
          final dt =
              DateTime.fromMillisecondsSinceEpoch(item.startTime, isUtc: true)
                  .toLocal();
          return dt.hour * 100 + dt.minute;
        }
        return 9999;
      }

      final int timeA = getStartTime(a);
      final int timeB = getStartTime(b);

      if (timeA != timeB) return timeA.compareTo(timeB);

      // 如果时间相同，再按类型排优先级
      int getPriority(dynamic item) {
        if (item is CourseItem) return 0;
        if (item is TodoItem) return 1;
        if (item is TimeLogItem) return 2;
        if (item is TodoPlanBlock) return 3;
        if (item is PomodoroRecord) return 4;
        return 5;
      }

      return getPriority(a).compareTo(getPriority(b));
    });

    return Container(
      width: double.infinity,
      color: isDark ? Colors.black.withValues(alpha: 0.1) : Colors.grey[50],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        weekdayStr,
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        dateStr,
                        style: TextStyle(
                          fontSize: 14,
                          color: isDark ? Colors.white54 : Colors.black54,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => setState(() => _selectedMonthDay = null),
                  tooltip: '关闭详情',
                ),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20),
            child: Divider(),
          ),
          Expanded(
            child: items.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.event_available,
                            size: 64,
                            color: isDark ? Colors.white10 : Colors.black12),
                        const SizedBox(height: 16),
                        Text('该日无安排',
                            style: TextStyle(
                                color:
                                    isDark ? Colors.white24 : Colors.black26)),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                    itemCount: items.length,
                    itemBuilder: (context, index) =>
                        _buildDetailSidebarItem(context, items[index]),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailSidebarItem(BuildContext context, dynamic item) {
    if (item is CourseItem) {
      final color = _getCourseColor(item.courseName);
      return ListTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1), shape: BoxShape.circle),
          child: Icon(Icons.class_, color: color, size: 20),
        ),
        title: Text(item.courseName,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
        subtitle: Text(
            '${item.formattedStartTime}-${item.formattedEndTime} @ ${item.roomName}',
            style: const TextStyle(fontSize: 12)),
        onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) => CourseDetailScreen(course: item))),
      );
    } else if (item is TodoItem) {
      return ListTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: (item.isDone ? Colors.green : Colors.amber)
                .withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(item.isDone ? Icons.check_circle : Icons.task_alt,
              color: item.isDone ? Colors.green : Colors.amber, size: 20),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(item.title,
                  style: TextStyle(
                    fontSize: 15,
                    decoration: item.isDone ? TextDecoration.lineThrough : null,
                    color: item.isDone ? Colors.grey : null,
                  )),
            ),
            if (item.teamUuid != null)
              Container(
                margin: const EdgeInsets.only(left: 4),
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: Colors.blue.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Colors.blue.withValues(alpha: 0.3)),
                ),
                child: const Icon(Icons.group, size: 12, color: Colors.blue),
              ),
          ],
        ),
        subtitle: Text(
            (item.teamUuid != null ? '${item.teamName ?? '团队'} · ' : '') +
                (item.dueDate != null
                    ? '截止: ${DateFormat('HH:mm').format(item.dueDate!)}'
                    : '无截止时间'),
            style: const TextStyle(fontSize: 12)),
        onTap: () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => TodoDetailScreen(todo: item))),
      );
    } else if (item is TimeLogItem) {
      const color = Colors.blue;
      return ListTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1), shape: BoxShape.circle),
          child: const Icon(Icons.edit_calendar, color: color, size: 20),
        ),
        title: Text(item.title.isNotEmpty ? item.title : '时间日志',
            style: const TextStyle(fontSize: 15)),
        subtitle: Text(
            '${DateFormat('HH:mm').format(DateTime.fromMillisecondsSinceEpoch(item.startTime, isUtc: true).toLocal())} - ${DateFormat('HH:mm').format(DateTime.fromMillisecondsSinceEpoch(item.endTime, isUtc: true).toLocal())}',
            style: const TextStyle(fontSize: 12)),
      );
    } else if (item is TodoPlanBlock) {
      const color = Colors.deepPurple;
      final start =
          DateTime.fromMillisecondsSinceEpoch(item.startTime).toLocal();
      final end = DateTime.fromMillisecondsSinceEpoch(item.endTime).toLocal();
      return ListTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1), shape: BoxShape.circle),
          child: Icon(
              item.status == TodoPlanStatus.finished
                  ? Icons.event_available
                  : Icons.event_note,
              color: color,
              size: 20),
        ),
        title: Text(item.titleSnapshot ?? '规划任务',
            style: const TextStyle(fontSize: 15)),
        subtitle: Text(
            '${DateFormat('HH:mm').format(start)} - ${DateFormat('HH:mm').format(end)} · 计划 ${item.plannedMinutes} 分钟',
            style: const TextStyle(fontSize: 12)),
      );
    } else if (item is PomodoroRecord) {
      const color = Colors.redAccent;
      return ListTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1), shape: BoxShape.circle),
          child: const Icon(Icons.timer, color: color, size: 20),
        ),
        title: const Text('番茄专注', style: TextStyle(fontSize: 15)),
        subtitle: Text('时长: ${item.effectiveDuration ~/ 60} 分钟',
            style: const TextStyle(fontSize: 12)),
      );
    }
    return const SizedBox.shrink();
  }

  void _handleFilterSelection(String value) {
    setState(() {
      if (value == 'clearAll') {
        _activeDataViews.clear();
        _updateWeekTodos();
      } else if (value == 'selectAll') {
        _activeDataViews
            .addAll({'courses', 'todos', 'plans', 'timeLogs', 'pomodoros'});
        _updateWeekTodos();
      } else if (value == 'disableFreeTimeCollapse') {
        _collapseFreeTime = !_collapseFreeTime;
      } else {
        if (_activeDataViews.contains(value)) {
          _activeDataViews.remove(value);
        } else {
          _activeDataViews.add(value);
        }
        if (value == 'todos' || value == 'hideCrossDay') {
          _updateWeekTodos();
        }
      }
    });
    _checkCollapsedSlots();
  }

  Widget _buildCheckableMenuItem(String key, String label) {
    final bool isSelected = key == 'disableFreeTimeCollapse'
        ? !_collapseFreeTime
        : _activeDataViews.contains(key);
    return MenuItemButton(
      closeOnActivate: false,
      onPressed: () => _handleFilterSelection(key),
      child: SizedBox(
        width: 150,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isSelected ? Icons.check : null,
              size: 16,
              color: isSelected
                  ? Theme.of(context).colorScheme.primary
                  : Colors.transparent,
            ),
            const SizedBox(width: 8),
            Text(label),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterActionItem(
      String value, String label, IconData icon, Color color) {
    return MenuItemButton(
      closeOnActivate: false,
      onPressed: () => _handleFilterSelection(value),
      child: SizedBox(
        width: 150,
        child: Row(
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 8),
            Text(label, style: TextStyle(color: color)),
          ],
        ),
      ),
    );
  }

  DateTime? _getMondayOfCurrentWeek() {
    if (_semesterMonday != null) {
      return _semesterMonday!.add(Duration(days: (_currentWeek - 1) * 7));
    }
    return null;
  }

  void _checkCollapsedSlots() {
    if (!_collapseFreeTime) {
      setState(() {
        _hiddenTimeRanges = const [];
        _lunchCardStartMinute = null;
        _lunchCardDuration = 0.0;
        _lunchCollapseText = '';
      });
      return;
    }

    const earlyStart = 360.0;
    const earlyEnd = 480.0;
    const lunchStart = 720.0;
    const lunchEnd = 840.0;
    const lateStart = 1260.0;
    const lateEnd = 1440.0;
    const lunchReserve = 20.0;

    // 初始值：min >= max 表示该敏感区间完全空闲。
    double minEarly = earlyEnd, maxEarly = earlyStart;
    double minLunch = lunchEnd, maxLunch = lunchStart;
    double minLate = lateEnd, maxLate = lateStart;

    void updateBounds(double s, double e) {
      // 时段 A [06:00, 08:00]
      double sA = s.clamp(earlyStart, earlyEnd);
      double eA = e.clamp(earlyStart, earlyEnd);
      if (sA < eA) {
        if (sA < minEarly) minEarly = sA;
        if (eA > maxEarly) maxEarly = eA;
      }

      // 时段 B [720, 840]
      double sB = s.clamp(lunchStart, lunchEnd);
      double eB = e.clamp(lunchStart, lunchEnd);
      if (sB < eB) {
        if (sB < minLunch) minLunch = sB;
        if (eB > maxLunch) maxLunch = eB;
      }

      // 时段 C [21:00, 24:00]
      double sC = s.clamp(lateStart, lateEnd);
      double eC = e.clamp(lateStart, lateEnd);
      if (sC < eC) {
        if (sC < minLate) minLate = sC;
        if (eC > maxLate) maxLate = eC;
      }
    }

    // 1. 扫描当前可见课程数据
    if (_activeDataViews.contains('courses')) {
      for (var course in _weekCourses) {
        double cs = (course.startTime ~/ 100) * 60.0 + (course.startTime % 100);
        double ce = (course.endTime ~/ 100) * 60.0 + (course.endTime % 100);
        updateBounds(cs, ce);
      }
    }

    final weekMonday = _getMondayOfCurrentWeek();

    void updateBoundsFromEpochRange(int startMs, int endMs) {
      if (weekMonday == null || endMs <= startMs) return;

      final weekStart =
          DateTime(weekMonday.year, weekMonday.month, weekMonday.day);
      final weekEnd = weekStart.add(const Duration(days: 7));
      DateTime start =
          DateTime.fromMillisecondsSinceEpoch(startMs, isUtc: true).toLocal();
      DateTime end =
          DateTime.fromMillisecondsSinceEpoch(endMs, isUtc: true).toLocal();

      if (!end.isAfter(weekStart) || !start.isBefore(weekEnd)) return;
      if (start.isBefore(weekStart)) start = weekStart;
      if (end.isAfter(weekEnd)) end = weekEnd;

      DateTime dayStart = DateTime(start.year, start.month, start.day);
      while (dayStart.isBefore(end)) {
        final dayEnd = dayStart.add(const Duration(days: 1));
        final sliceStart = start.isAfter(dayStart) ? start : dayStart;
        final sliceEnd = end.isBefore(dayEnd) ? end : dayEnd;
        if (sliceEnd.isAfter(sliceStart)) {
          final double sliceStartMinute =
              sliceStart.hour * 60.0 + sliceStart.minute;
          final double sliceEndMinute = sliceEnd == dayEnd
              ? 1440.0
              : sliceEnd.hour * 60.0 + sliceEnd.minute;
          updateBounds(
            sliceStartMinute,
            sliceEndMinute,
          );
        }
        dayStart = dayEnd;
      }
    }

    // 2. 扫描当前可见日内待办
    if (_activeDataViews.contains('todos')) {
      for (int weekday = 1; weekday <= 7; weekday++) {
        for (var todo in _intraDayTodosPerDay[weekday] ?? []) {
          if (todo.dueDate == null) continue;
          DateTime dt = todo.dueDate!;
          double m = dt.hour * 60.0 + dt.minute;
          updateBounds(m, m + 1); // 截止时间点算作 1 分钟区间
        }
      }
    }

    // 3. 扫描当前可见时间日志
    if (_activeDataViews.contains('timeLogs')) {
      for (var log in _allTimeLogs) {
        updateBoundsFromEpochRange(log.startTime, log.endTime);
      }
    }

    // 4. 扫描当前可见计划块
    if (_activeDataViews.contains('plans')) {
      for (var plan in _allPlanBlocks) {
        updateBoundsFromEpochRange(plan.startTime, plan.endTime);
      }
    }

    // 5. 扫描当前可见专注记录。这里不能复用 _pomodorosPerDay，因为它会为避免
    // 界面重复显示而跳过已关联计划块的专注记录。
    if (_activeDataViews.contains('pomodoros')) {
      for (var record in _allPomodoroRecords) {
        final int endMs = record.endTime ??
            (record.startTime + record.effectiveDuration * 1000);
        updateBoundsFromEpochRange(record.startTime, endMs);
      }
    }

    ({double pre, double post}) buildHideLengths(
        double rangeStart, double rangeEnd, double minStart, double maxEnd) {
      if (minStart >= maxEnd) {
        return (pre: rangeEnd - rangeStart, post: 0.0);
      }
      return (
        pre: (minStart - rangeStart).clamp(0.0, rangeEnd - rangeStart),
        post: (rangeEnd - maxEnd).clamp(0.0, rangeEnd - rangeStart),
      );
    }

    void addRange(List<_HiddenTimeRange> ranges, double start, double end) {
      if (end - start > 0.01) {
        ranges.add(_HiddenTimeRange(start, end));
      }
    }

    void addTwoSidedRanges(
      List<_HiddenTimeRange> ranges,
      double rangeStart,
      double rangeEnd,
      double pre,
      double post,
    ) {
      addRange(ranges, rangeStart, rangeStart + pre);
      addRange(ranges, rangeEnd - post, rangeEnd);
    }

    final early = buildHideLengths(earlyStart, earlyEnd, minEarly, maxEarly);
    final lunch = buildHideLengths(lunchStart, lunchEnd, minLunch, maxLunch);
    final late = buildHideLengths(lateStart, lateEnd, minLate, maxLate);
    final String lunchCollapseText =
        _buildLunchCollapseText(lunchStart, lunchEnd, lunch.pre, lunch.post);

    double lunchPre = lunch.pre;
    double lunchPost = lunch.post;
    double? lunchCardStartMinute;
    double lunchCardDuration = 0.0;

    final double totalLunchHide = lunchPre + lunchPost;
    if (totalLunchHide > 0.0) {
      lunchCardDuration =
          totalLunchHide > lunchReserve ? lunchReserve : totalLunchHide;

      if (lunchPre > 0.0) {
        lunchCardStartMinute = lunchStart;
        final double reserveFromPre =
            lunchPre >= lunchCardDuration ? lunchCardDuration : lunchPre;
        lunchPre -= reserveFromPre;
        final double reserveRemain = lunchCardDuration - reserveFromPre;
        if (reserveRemain > 0.0) {
          lunchPost =
              (lunchPost - reserveRemain).clamp(0.0, lunchEnd - lunchStart);
        }
      } else {
        lunchCardStartMinute = lunchEnd - lunchPost;
        lunchPost =
            (lunchPost - lunchCardDuration).clamp(0.0, lunchEnd - lunchStart);
      }
    }

    final hiddenRanges = <_HiddenTimeRange>[];
    addTwoSidedRanges(
        hiddenRanges, earlyStart, earlyEnd, early.pre, early.post);
    addTwoSidedRanges(hiddenRanges, lunchStart, lunchEnd, lunchPre, lunchPost);
    addTwoSidedRanges(hiddenRanges, lateStart, lateEnd, late.pre, late.post);
    hiddenRanges.sort((a, b) => a.startMinute.compareTo(b.startMinute));

    setState(() {
      _hiddenTimeRanges = hiddenRanges;
      _lunchCardStartMinute = lunchCardStartMinute;
      _lunchCardDuration = lunchCardDuration;
      _lunchCollapseText = lunchCollapseText;
    });
  }

  double get _totalHiddenMinutes =>
      _hiddenTimeRanges.fold(0.0, (sum, range) => sum + range.duration);

  double _mapTimeToVirtualMinutes(int hour, int minute) {
    double m = (hour * 60 + minute).toDouble();
    final startMinute = startHour * 60.0;
    if (m < startMinute) return 0;

    final hiddenBefore = _hiddenTimeRanges.fold(
        0.0, (sum, range) => sum + range.hiddenBefore(m));
    double virtualM = m - startMinute - hiddenBefore;
    return virtualM < 0 ? 0 : virtualM;
  }

  double _timeToY(int hour, int minute, double minuteHeight) {
    double virtualMinutes = _mapTimeToVirtualMinutes(hour, minute);
    return virtualMinutes * minuteHeight;
  }

  Color _getCourseColor(String courseName) {
    final List<Color> colors = [
      Colors.blueAccent.shade200,
      Colors.orangeAccent.shade200,
      Colors.purpleAccent.shade200,
      Colors.teal.shade300,
      Colors.pinkAccent.shade200,
      Colors.indigoAccent.shade200,
      Colors.green.shade400,
      Colors.deepOrange.shade300,
    ];
    int hash = courseName.hashCode;
    return colors[hash % colors.length];
  }

  Color _hexToColor(String hex) {
    String clean = hex.replaceAll('#', '');
    if (clean.length == 6) clean = 'FF$clean';
    return Color(int.parse(clean, radix: 16));
  }

  void _showAllDayTodos(
      BuildContext context, List<TodoItem> todos, String dateStr) {
    showModalBottomSheet(
        context: context,
        shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
        builder: (ctx) {
          return SafeArea(
            child: Container(
                padding: const EdgeInsets.all(16),
                constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(context).size.height * 0.5),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Center(
                        child: Container(
                            width: 40,
                            height: 4,
                            decoration: BoxDecoration(
                                color: Colors.grey.shade300,
                                borderRadius: BorderRadius.circular(2))),
                      ),
                      const SizedBox(height: 16),
                      Text("$dateStr 全天/跨天待办",
                          style: const TextStyle(
                              fontSize: 18, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 16),
                      Expanded(
                          child: ListView.builder(
                              itemCount: todos.length,
                              itemBuilder: (context, index) {
                                final todo = todos[index];
                                return ListTile(
                                  leading: Icon(
                                      todo.isDone
                                          ? Icons.check_circle
                                          : Icons.task_alt,
                                      color: todo.isDone
                                          ? Colors.green
                                          : Colors.amber),
                                  title: Text(todo.title,
                                      style: TextStyle(
                                          decoration: todo.isDone
                                              ? TextDecoration.lineThrough
                                              : null)),
                                  subtitle: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      if (todo.teamUuid != null)
                                        Padding(
                                          padding:
                                              const EdgeInsets.only(bottom: 2),
                                          child: Row(
                                            children: [
                                              const Icon(Icons.group,
                                                  size: 12, color: Colors.blue),
                                              const SizedBox(width: 4),
                                              Text(
                                                  "${todo.teamName ?? '团队'} · ${todo.creatorName ?? '成员'}",
                                                  style: const TextStyle(
                                                      fontSize: 11,
                                                      color: Colors.blue,
                                                      fontWeight:
                                                          FontWeight.bold)),
                                            ],
                                          ),
                                        ),
                                      Text(
                                          "开始: ${DateFormat('MM-dd HH:mm').format(DateTime.fromMillisecondsSinceEpoch(todo.createdDate ?? todo.createdAt, isUtc: true).toLocal())}\n截止: ${todo.dueDate != null ? DateFormat('MM-dd HH:mm').format(todo.dueDate!) : '无'}"),
                                    ],
                                  ),
                                  onTap: () {
                                    Navigator.pop(ctx);
                                    Navigator.push(
                                        context,
                                        PageTransitions.slideHorizontal(
                                            TodoDetailScreen(todo: todo)));
                                  },
                                );
                              }))
                    ])),
          );
        });
  }

  Widget _buildAllDayHeaderRow(DateTime? monday) {
    if (monday == null || !_activeDataViews.contains('todos')) {
      return const SizedBox.shrink();
    }

    bool hasAnyAllDay =
        _allDayTodosPerDay.values.any((list) => list.isNotEmpty);
    if (!hasAnyAllDay) return const SizedBox.shrink();

    return Container(
      padding: EdgeInsets.only(left: timeColumnWidth, bottom: 2),
      color: Theme.of(context).colorScheme.surface,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: List.generate(7, (index) {
          int weekday = index + 1;
          List<TodoItem> dayTodos = _allDayTodosPerDay[weekday] ?? [];

          if (dayTodos.isEmpty) {
            return const Expanded(child: SizedBox(height: 22));
          }

          String text = dayTodos.length == 1
              ? dayTodos.first.title
              : "${dayTodos.length}项全天待办";
          bool allDone = dayTodos.every((t) => t.isDone);

          return Expanded(
            child: GestureDetector(
              onTap: () {
                DateTime currentDay = monday.add(Duration(days: index));
                String dateStr = DateFormat('MM-dd').format(currentDay);
                _showAllDayTodos(context, dayTodos, dateStr);
              },
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 1, vertical: 1),
                padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
                decoration: BoxDecoration(
                  color: allDone
                      ? Colors.green.withValues(alpha: 0.5)
                      : Colors.amber.shade500.withValues(alpha: 0.85),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (dayTodos.any((t) => t.teamUuid != null))
                      const Padding(
                        padding: EdgeInsets.only(right: 2),
                        child: Icon(Icons.group, size: 10, color: Colors.white),
                      ),
                    Flexible(
                      child: Text(
                        text,
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.white,
                          decoration:
                              allDone ? TextDecoration.lineThrough : null,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  bool _timeRangesOverlap(
      int startA, int endAExclusive, int startB, int endBExclusive) {
    return endAExclusive > startB && startA < endBExclusive;
  }

  bool _isRecordAssociatedWithPlan(PomodoroRecord record, TodoPlanBlock plan) {
    if (record.isDeleted || plan.isDeleted) return false;

    if (plan.pomodoroRecordIds.contains(record.uuid)) {
      return true;
    }

    if (record.planBlockId != null &&
        record.planBlockId!.isNotEmpty &&
        record.planBlockId == plan.id) {
      return true;
    }

    if (plan.todoId.isNotEmpty &&
        record.todoUuid != null &&
        record.todoUuid!.isNotEmpty &&
        record.todoUuid == plan.todoId) {
      final int recordEnd = record.endTime ??
          (record.startTime + record.effectiveDuration * 1000);
      return _timeRangesOverlap(
          record.startTime, recordEnd, plan.startTime, plan.endTime);
    }

    return false;
  }

  // --- 辅助方法：计算规划块关联的番茄钟完成情况 ---
  Map<String, dynamic> _calculatePlanPomodoroProgress(TodoPlanBlock plan) {
    final associatedRecords = _allPomodoroRecords
        .where((record) => _isRecordAssociatedWithPlan(record, plan))
        .toList();

    if (associatedRecords.isEmpty) {
      return {'completed': 0, 'total': 0, 'progress': 0.0};
    }

    // 计算实际专注进度（秒）
    int totalSeconds = 0;
    int completedSeconds = 0;

    for (var record in associatedRecords) {
      final int effective =
          record.effectiveDuration > 0 ? record.effectiveDuration : 0;
      final int planned =
          record.plannedDuration > 0 ? record.plannedDuration : effective;
      final int base = planned > 0 ? planned : 1;
      totalSeconds += base;
      completedSeconds += effective.clamp(0, base);
    }

    final progress = totalSeconds > 0 ? completedSeconds / totalSeconds : 0.0;

    return {
      'completed': completedSeconds,
      'total': totalSeconds,
      'progress': progress.clamp(0.0, 1.0),
      'recordCount': associatedRecords.length,
    };
  }

  // --- 辅助方法：检查番茄钟是否被某个计划块关联 ---
  bool _isPomodoroAssociatedWithPlan(PomodoroRecord record) {
    return _allPlanBlocks
        .any((plan) => _isRecordAssociatedWithPlan(record, plan));
  }

  Widget _buildHeader(DateTime? monday) {
    DateTime now = DateTime.now();
    String todayStr = DateFormat('yyyy-MM-dd').format(now);
    bool isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      color: Theme.of(context).colorScheme.surface,
      padding: EdgeInsets.only(left: timeColumnWidth, top: 4, bottom: 4),
      child: Row(
        children: List.generate(7, (index) {
          DateTime? currentDate;
          String dateStr = '';
          bool isToday = false;

          if (monday != null) {
            currentDate = monday.add(Duration(days: index));
            dateStr = DateFormat('M/dd').format(currentDate);
            isToday = DateFormat('yyyy-MM-dd').format(currentDate) == todayStr;
          }

          List<String> weekdays = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];

          return Expanded(
            child: Column(
              children: [
                Text(
                  weekdays[index],
                  style: TextStyle(
                    color: isToday
                        ? Colors.blue
                        : (isDark ? Colors.white70 : Colors.black87),
                    fontWeight: isToday ? FontWeight.bold : FontWeight.normal,
                    fontSize: 13,
                  ),
                ),
                if (dateStr.isNotEmpty)
                  Text(
                    dateStr,
                    style: TextStyle(
                      color: isToday ? Colors.blue : Colors.grey,
                      fontSize: 11,
                    ),
                  ),
              ],
            ),
          );
        }),
      ),
    );
  }

  bool _isHourCollapsed(int hour) {
    double m = hour * 60.0;
    return _hiddenTimeRanges.any((range) => range.contains(m));
  }

  String _formatMinute(double minute) {
    final int value = minute.round();
    final int h = value ~/ 60;
    final int m = value % 60;
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
  }

  String _buildLunchCollapseText(
      double rangeStart, double rangeEnd, double pre, double post) {
    final ranges = <String>[];
    if (pre > 0.0) {
      ranges.add(
          '${_formatMinute(rangeStart)}-${_formatMinute(rangeStart + pre)}');
    }
    if (post > 0.0) {
      ranges
          .add('${_formatMinute(rangeEnd - post)}-${_formatMinute(rangeEnd)}');
    }
    return ranges.join(' & ');
  }

  Widget _buildGrid(double cellWidth, double minuteHeight) {
    List<Widget> children = [];
    bool isDark = Theme.of(context).brightness == Brightness.dark;
    Color lineColor = isDark ? Colors.white10 : Colors.black12;
    Color textColor = isDark ? Colors.white70 : Colors.black87;

    for (int hour = startHour; hour <= endHour; hour++) {
      // 🚀 自适应时间隐藏：如果该小时正点落于本周的合并收窄区间中，跳过不绘制
      if (_isHourCollapsed(hour)) continue;

      double y = _timeToY(hour, 0, minuteHeight);

      children.add(Positioned(
        top: y,
        left: timeColumnWidth,
        right: 0,
        height: 1,
        child: Container(color: lineColor),
      ));

      if (hour < endHour) {
        // 🚀 动态自适应刻度容器高：寻找下一个可见的刻度小时并求高差，避免刻度重叠挤压
        int nextHour = hour + 1;
        while (nextHour <= endHour) {
          if (_isHourCollapsed(nextHour)) {
            nextHour++;
            continue;
          }
          break;
        }
        double slotHeight = _timeToY(nextHour, 0, minuteHeight) - y;

        children.add(Positioned(
          top: y,
          left: 0,
          width: timeColumnWidth,
          height: slotHeight,
          child: Align(
            alignment: Alignment.topCenter,
            child: Padding(
              padding: const EdgeInsets.only(top: 2.0),
              child: Text(
                '${hour.toString().padLeft(2, '0')}:00',
                style: TextStyle(
                    fontSize: 12,
                    color: textColor,
                    fontWeight: FontWeight.w500),
              ),
            ),
          ),
        ));
      }
    }

    final lunchCardStart = _lunchCardStartMinute;
    if (lunchCardStart != null && _lunchCardDuration > 0.0) {
      final int lunchCardHour = lunchCardStart ~/ 60;
      final int lunchCardMinute = lunchCardStart.round() % 60;
      final double y1 = _timeToY(lunchCardHour, lunchCardMinute, minuteHeight);
      double collapseHeight = _lunchCardDuration * minuteHeight;

      children.add(Positioned(
        top: y1 + 1,
        left: timeColumnWidth + 1,
        right: 1,
        height: (collapseHeight - 2).clamp(2.0, double.infinity).toDouble(),
        child: Container(
          decoration: BoxDecoration(
            color: isDark
                ? Colors.white.withValues(alpha: 0.06)
                : Colors.black.withValues(alpha: 0.035),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: isDark ? Colors.white10 : Colors.black12,
              width: 0.5,
            ),
          ),
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: isDark
                    ? [
                        Colors.white.withValues(alpha: 0.012),
                        Colors.white.withValues(alpha: 0.012),
                        Colors.white.withValues(alpha: 0.04),
                        Colors.white.withValues(alpha: 0.04),
                        Colors.white.withValues(alpha: 0.012),
                        Colors.white.withValues(alpha: 0.012),
                      ]
                    : [
                        Colors.black.withValues(alpha: 0.008),
                        Colors.black.withValues(alpha: 0.008),
                        Colors.black.withValues(alpha: 0.028),
                        Colors.black.withValues(alpha: 0.028),
                        Colors.black.withValues(alpha: 0.008),
                        Colors.black.withValues(alpha: 0.008),
                      ],
                stops: const [0.0, 0.18, 0.18, 0.32, 0.32, 1.0],
              ),
            ),
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    '☕ 午休区间已折叠 ($_lunchCollapseText)',
                    style: TextStyle(
                      fontSize: 10,
                      color: isDark ? Colors.white54 : Colors.black54,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ));
    }

    for (int i = 0; i <= 7; i++) {
      children.add(Positioned(
        top: 0,
        bottom: 0,
        left: timeColumnWidth + i * cellWidth,
        width: 0.5,
        child: Container(color: lineColor),
      ));
    }

    if (_activeDataViews.contains('todos')) {
      Map<String, int> collisionMap = {};

      for (int weekday = 1; weekday <= 7; weekday++) {
        final dayTodos = _intraDayTodosPerDay[weekday] ?? [];
        for (var todo in dayTodos) {
          DateTime start = DateTime.fromMillisecondsSinceEpoch(
                  todo.createdDate ?? todo.createdAt,
                  isUtc: true)
              .toLocal();
          DateTime end = todo.dueDate ?? start.add(const Duration(hours: 1));

          double top = _timeToY(start.hour, start.minute, minuteHeight);
          double bottom = _timeToY(end.hour, end.minute, minuteHeight);
          double height = bottom - top;

          if (height < 20.0) height = 20.0;

          String collisionKey = "${weekday}_${(top / 15).floor()}";
          int stackIndex = collisionMap[collisionKey] ?? 0;
          collisionMap[collisionKey] = stackIndex + 1;

          double leftOffset = timeColumnWidth + (weekday - 1) * cellWidth;
          double finalWidth = cellWidth - 2;
          double finalLeft = leftOffset + 1;

          if (stackIndex > 0) {
            finalLeft += 4.0 * stackIndex;
            finalWidth -= 4.0 * stackIndex;
          }

          Color todoColor = todo.isDone
              ? Colors.green.withValues(alpha: 0.5)
              : Colors.amber.shade500.withValues(alpha: 0.85);
          final todoCardKey = _getTodoCardKey(todo.id);
          final todoIndex = _intraDayTodosPerDay.values
              .expand((e) => e)
              .toList()
              .indexOf(todo);

          // 🚀 根据物理高度动态计算 Todo 标题最大行数
          final double availableForTodo =
              (todo.teamUuid != null && height >= 32)
                  ? height - 14.0
                  : height - 2.0;
          int todoMaxLines = (availableForTodo / 10.0).round();
          if (todoMaxLines < 1) todoMaxLines = 1;

          children.add(Positioned(
            top: top,
            left: finalLeft,
            width: finalWidth,
            height: height,
            child: AnimatedBuilder(
              animation: _courseExpandAnim,
              builder: (ctx, child) {
                final delay = (todoIndex * 0.06).clamp(0.0, 0.5);
                final t = ((_courseExpandAnim.value - delay) / (1.0 - delay))
                    .clamp(0.0, 1.0);
                final scale = 0.7 + 0.3 * t;
                final opacity = t;
                return Transform.scale(
                  scale: scale,
                  child: Opacity(
                    opacity: opacity,
                    child: child,
                  ),
                );
              },
              child: GestureDetector(
                onTap: () {
                  final renderBox = todoCardKey.currentContext
                      ?.findRenderObject() as RenderBox?;
                  if (renderBox != null) {
                    final rect =
                        renderBox.localToGlobal(Offset.zero) & renderBox.size;
                    Navigator.push(
                      context,
                      ContainerTransformRoute(
                        page: TodoDetailScreen(todo: todo),
                        sourceRect: rect,
                        sourceColor: todoColor,
                        sourceBorderRadius:
                            const BorderRadius.all(Radius.circular(4)),
                      ),
                    );
                  } else {
                    Navigator.push(
                        context,
                        PageTransitions.slideHorizontal(
                            TodoDetailScreen(todo: todo)));
                  }
                },
                child: Container(
                  key: todoCardKey,
                  clipBehavior: Clip.hardEdge,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
                  decoration: BoxDecoration(
                      color: todoColor,
                      borderRadius: BorderRadius.circular(4),
                      boxShadow: stackIndex > 0
                          ? [
                              const BoxShadow(
                                  color: Colors.black12,
                                  blurRadius: 2,
                                  offset: Offset(-1, 1))
                            ]
                          : null),
                  child: height < 20
                      ? Icon(todo.isDone ? Icons.check_circle : Icons.task_alt,
                          size: 10, color: Colors.white)
                      : SingleChildScrollView(
                          physics: const NeverScrollableScrollPhysics(),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (todo.teamUuid != null && height >= 32)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 2.0),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 2, vertical: 0.5),
                                    decoration: BoxDecoration(
                                      color:
                                          Colors.white.withValues(alpha: 0.3),
                                      borderRadius: BorderRadius.circular(2),
                                    ),
                                    child: Row(
                                      children: [
                                        const Icon(Icons.group,
                                            size: 8, color: Colors.white),
                                        const SizedBox(width: 1),
                                        Expanded(
                                          // 🚀 强制填满剩余空间并截断
                                          child: Text(
                                            todo.teamName ?? '团队',
                                            style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 7,
                                                fontWeight: FontWeight.bold),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.only(top: 2.0),
                                    child: Icon(
                                        todo.isDone
                                            ? Icons.check_circle
                                            : Icons.task_alt,
                                        size: 10,
                                        color: Colors.white),
                                  ),
                                  const SizedBox(width: 2),
                                  Expanded(
                                    child: Text(
                                      todo.title,
                                      style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          decoration: todo.isDone
                                              ? TextDecoration.lineThrough
                                              : null,
                                          height: 1.0),
                                      maxLines: todoMaxLines,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                ),
              ),
            ),
          ));
        }
      }
    }

    if (_activeDataViews.contains('timeLogs')) {
      for (int weekday = 1; weekday <= 7; weekday++) {
        for (var log in _timeLogsPerDay[weekday]!) {
          DateTime start =
              DateTime.fromMillisecondsSinceEpoch(log.startTime, isUtc: true)
                  .toLocal();
          DateTime end =
              DateTime.fromMillisecondsSinceEpoch(log.endTime, isUtc: true)
                  .toLocal();

          double top = _timeToY(start.hour, start.minute, minuteHeight);
          double bottom = _timeToY(end.hour, end.minute, minuteHeight);
          double height = bottom - top;

          if (height < 18.0) height = 18.0;

          double leftOffset = timeColumnWidth + (weekday - 1) * cellWidth;
          double finalWidth = cellWidth - 2;
          double finalLeft = leftOffset + 1;

          Color logColor = const Color(0xFF3B82F6).withValues(alpha: 0.7);
          String logTitle = log.title.isNotEmpty ? log.title : '时间日志';
          if (log.tagUuids.isNotEmpty) {
            final tag = _pomodoroTags.cast<PomodoroTag?>().firstWhere(
                (t) => log.tagUuids.contains(t?.uuid),
                orElse: () => null);
            if (tag != null) {
              logColor = _hexToColor(tag.color).withValues(alpha: 0.7);
              if (logTitle == '时间日志') logTitle = tag.name;
            }
          }

          final logCardKey = _getTimeLogCardKey(log.id);
          final logIndex =
              _timeLogsPerDay.values.expand((e) => e).toList().indexOf(log);

          // 🚀 根据物理高度动态计算 TimeLog 标题最大行数
          final double availableForLog =
              height > 22 ? height - 9.0 : height - 2.0;
          int logMaxLines = (availableForLog / 9.0).round();
          if (logMaxLines < 1) logMaxLines = 1;

          children.add(Positioned(
            top: top,
            left: finalLeft,
            width: finalWidth,
            height: height,
            child: AnimatedBuilder(
              animation: _courseExpandAnim,
              builder: (ctx, child) {
                final delay = (logIndex * 0.06).clamp(0.0, 0.5);
                final t = ((_courseExpandAnim.value - delay) / (1.0 - delay))
                    .clamp(0.0, 1.0);
                final scale = 0.7 + 0.3 * t;
                final opacity = t;
                return Transform.scale(
                  scale: scale,
                  child: Opacity(
                    opacity: opacity,
                    child: child,
                  ),
                );
              },
              child: GestureDetector(
                onTap: () {
                  final renderBox = logCardKey.currentContext
                      ?.findRenderObject() as RenderBox?;
                  if (renderBox != null) {
                    final rect =
                        renderBox.localToGlobal(Offset.zero) & renderBox.size;
                    Navigator.push(
                      context,
                      ContainerTransformRoute(
                        page:
                            TimeLogDetailScreen(log: log, tags: _pomodoroTags),
                        sourceRect: rect,
                        sourceColor: logColor,
                        sourceBorderRadius:
                            const BorderRadius.all(Radius.circular(4)),
                      ),
                    );
                  } else {
                    Navigator.push(
                        context,
                        PageTransitions.slideHorizontal(TimeLogDetailScreen(
                            log: log, tags: _pomodoroTags)));
                  }
                },
                child: Container(
                  key: logCardKey,
                  clipBehavior: Clip.hardEdge,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
                  decoration: BoxDecoration(
                      color: logColor,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                          color: logColor.withValues(alpha: 1.0), width: 0.5)),
                  child: height < 18
                      ? const Icon(Icons.edit_calendar,
                          size: 8, color: Colors.white)
                      : SingleChildScrollView(
                          physics: const NeverScrollableScrollPhysics(),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.only(top: 1.0),
                                    child: const Icon(Icons.edit_calendar,
                                        size: 8, color: Colors.white),
                                  ),
                                  const SizedBox(width: 2),
                                  Expanded(
                                    child: Text(
                                      logTitle,
                                      style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 9,
                                          fontWeight: FontWeight.bold,
                                          height: 1.0),
                                      maxLines: logMaxLines,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                              if (height > 22)
                                Text(
                                  '${start.hour.toString().padLeft(2, '0')}:${start.minute.toString().padLeft(2, '0')}-${end.hour.toString().padLeft(2, '0')}:${end.minute.toString().padLeft(2, '0')}',
                                  style: TextStyle(
                                      color:
                                          Colors.white.withValues(alpha: 0.8),
                                      fontSize: 7,
                                      height: 1.0),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                            ],
                          ),
                        ),
                ),
              ),
            ),
          ));
        }
      }
    }

    if (_activeDataViews.contains('plans')) {
      for (int weekday = 1; weekday <= 7; weekday++) {
        for (var plan in _planBlocksPerDay[weekday] ?? <TodoPlanBlock>[]) {
          final start =
              DateTime.fromMillisecondsSinceEpoch(plan.startTime).toLocal();
          final end =
              DateTime.fromMillisecondsSinceEpoch(plan.endTime).toLocal();

          double top = _timeToY(start.hour, start.minute, minuteHeight);
          double bottom = _timeToY(end.hour, end.minute, minuteHeight);
          double height = bottom - top;
          if (height < 18.0) height = 18.0;

          final leftOffset = timeColumnWidth + (weekday - 1) * cellWidth;
          final planColor = plan.status == TodoPlanStatus.finished
              ? Colors.green.withValues(alpha: 0.58)
              : Colors.deepPurple.withValues(alpha: 0.58);
          final title = plan.titleSnapshot ?? '规划任务';
          final planIndex =
              _planBlocksPerDay.values.expand((e) => e).toList().indexOf(plan);

          // 计算关联的番茄钟完成进度
          final pomProgress = _calculatePlanPomodoroProgress(plan);
          final recordCount = (pomProgress['recordCount'] as int?) ?? 0;
          final hasAssociatedPomodoro = recordCount > 0;

          // 🚀 根据物理高度动态计算 Plan 标题最大行数
          int planMaxLines = 2;
          if (hasAssociatedPomodoro) {
            double availableForPlan = height > 32
                ? height - 19.0
                : (height > 24 ? height - 11.0 : height - 4.0);
            planMaxLines = (availableForPlan / 9.0).round();
            if (planMaxLines < 1) planMaxLines = 1;
          } else {
            double availableForPlan =
                height > 24 ? height - 11.0 : height - 4.0;
            planMaxLines = (availableForPlan / 9.0).round();
            if (planMaxLines < 1) planMaxLines = 1;
          }

          children.add(Positioned(
            top: top,
            left: leftOffset + 4,
            width: cellWidth - 8,
            height: height,
            child: AnimatedBuilder(
              animation: _courseExpandAnim,
              builder: (ctx, child) {
                final delay = (planIndex * 0.04).clamp(0.0, 0.45);
                final t = ((_courseExpandAnim.value - delay) / (1.0 - delay))
                    .clamp(0.0, 1.0);
                return Transform.scale(
                  scale: 0.8 + 0.2 * t,
                  child: Opacity(opacity: t, child: child),
                );
              },
              child: Container(
                clipBehavior: Clip.hardEdge,
                padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 2),
                decoration: BoxDecoration(
                  color: planColor,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                      color: Colors.white.withValues(alpha: 0.35), width: 0.5),
                ),
                // 如果有关联的番茄钟，用背景填充表示完成进度
                child: hasAssociatedPomodoro
                    ? Stack(
                        fit: StackFit.expand,
                        children: [
                          // 背景进度条（从下往上）
                          Align(
                            alignment: Alignment.bottomCenter,
                            child: FractionallySizedBox(
                              heightFactor:
                                  ((pomProgress['progress'] as double?) ?? 0.0)
                                      .clamp(0.0, 1.0),
                              widthFactor: 1.0,
                              child: Container(
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.25),
                                ),
                              ),
                            ),
                          ),
                          // 内容层
                          SingleChildScrollView(
                            physics: const NeverScrollableScrollPhysics(),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Icon(
                                        plan.status == TodoPlanStatus.finished
                                            ? Icons.event_available
                                            : Icons.event_note,
                                        size: 9,
                                        color: Colors.white),
                                    const SizedBox(width: 2),
                                    Expanded(
                                      child: Text(
                                        title,
                                        style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 9,
                                            fontWeight: FontWeight.bold,
                                            height: 1.0),
                                        maxLines: height < 28 ? 1 : 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                                if (height > 24)
                                  Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        '${plan.plannedMinutes}min',
                                        style: TextStyle(
                                            color: Colors.white
                                                .withValues(alpha: 0.85),
                                            fontSize: 7,
                                            height: 1.0),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      // 显示番茄钟完成情况
                                      if (height > 32)
                                        Text(
                                          '${(((pomProgress['progress'] as double?) ?? 0.0) * 100).toStringAsFixed(0)}%',
                                          style: TextStyle(
                                              color: Colors.white
                                                  .withValues(alpha: 0.7),
                                              fontSize: 6,
                                              height: 1.0,
                                              fontWeight: FontWeight.bold),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                    ],
                                  ),
                              ],
                            ),
                          ),
                        ],
                      )
                    : (height < 18
                        ? const Icon(Icons.event_note,
                            size: 8, color: Colors.white)
                        : SingleChildScrollView(
                            physics: const NeverScrollableScrollPhysics(),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Icon(
                                        plan.status == TodoPlanStatus.finished
                                            ? Icons.event_available
                                            : Icons.event_note,
                                        size: 9,
                                        color: Colors.white),
                                    const SizedBox(width: 2),
                                    Expanded(
                                      child: Text(
                                        title,
                                        style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 9,
                                            fontWeight: FontWeight.bold,
                                            height: 1.0),
                                        maxLines: height < 28 ? 1 : 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                                if (height > 24)
                                  Text(
                                    '${plan.plannedMinutes}min',
                                    style: TextStyle(
                                        color: Colors.white
                                            .withValues(alpha: 0.85),
                                        fontSize: 7,
                                        height: 1.0),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                              ],
                            ))),
              ),
            ),
          ));
        }
      }
    }

    if (_activeDataViews.contains('pomodoros')) {
      for (int weekday = 1; weekday <= 7; weekday++) {
        for (var record in _pomodorosPerDay[weekday]!) {
          DateTime start =
              DateTime.fromMillisecondsSinceEpoch(record.startTime, isUtc: true)
                  .toLocal();
          int endMs = record.endTime ??
              (record.startTime + record.effectiveDuration * 1000);
          DateTime end =
              DateTime.fromMillisecondsSinceEpoch(endMs, isUtc: true).toLocal();

          double top = _timeToY(start.hour, start.minute, minuteHeight);
          double bottom = _timeToY(end.hour, end.minute, minuteHeight);
          double height = bottom - top;

          if (height < 18.0) height = 18.0;

          double leftOffset = timeColumnWidth + (weekday - 1) * cellWidth;
          double finalWidth = cellWidth - 2;
          double finalLeft = leftOffset + 1;

          Color pomColor = Colors.redAccent.withValues(alpha: 0.6);
          String pomTitle = '专注';

          // 优先显示任务名，其次显示标签名
          if (record.todoTitle != null && record.todoTitle!.isNotEmpty) {
            pomTitle = record.todoTitle!;
          } else if (record.tagUuids.isNotEmpty) {
            final tag = _pomodoroTags.cast<PomodoroTag?>().firstWhere(
                (t) => record.tagUuids.contains(t?.uuid),
                orElse: () => null);
            if (tag != null) {
              pomColor = _hexToColor(tag.color).withValues(alpha: 0.6);
              pomTitle = tag.name;
            }
          }

          final pomCardKey = _getPomodoroCardKey(record.uuid);
          final pomIndex =
              _pomodorosPerDay.values.expand((e) => e).toList().indexOf(record);

          // 🚀 根据物理高度动态计算 Pomodoro 标题最大行数
          final double availableForPom =
              height > 22 ? height - 9.0 : height - 2.0;
          int pomMaxLines = (availableForPom / 9.0).round();
          if (pomMaxLines < 1) pomMaxLines = 1;

          children.add(Positioned(
            top: top,
            left: finalLeft,
            width: finalWidth,
            height: height,
            child: AnimatedBuilder(
              animation: _courseExpandAnim,
              builder: (ctx, child) {
                final delay = (pomIndex * 0.06).clamp(0.0, 0.5);
                final t = ((_courseExpandAnim.value - delay) / (1.0 - delay))
                    .clamp(0.0, 1.0);
                final scale = 0.7 + 0.3 * t;
                final opacity = t;
                return Transform.scale(
                  scale: scale,
                  child: Opacity(
                    opacity: opacity,
                    child: child,
                  ),
                );
              },
              child: GestureDetector(
                onTap: () {
                  final renderBox = pomCardKey.currentContext
                      ?.findRenderObject() as RenderBox?;
                  if (renderBox != null) {
                    final rect =
                        renderBox.localToGlobal(Offset.zero) & renderBox.size;
                    Navigator.push(
                      context,
                      ContainerTransformRoute(
                        page: PomodoroDetailScreen(
                            record: record, tags: _pomodoroTags),
                        sourceRect: rect,
                        sourceColor: pomColor,
                        sourceBorderRadius:
                            const BorderRadius.all(Radius.circular(4)),
                      ),
                    );
                  } else {
                    Navigator.push(
                        context,
                        PageTransitions.slideHorizontal(PomodoroDetailScreen(
                            record: record, tags: _pomodoroTags)));
                  }
                },
                child: Container(
                  key: pomCardKey,
                  clipBehavior: Clip.hardEdge,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
                  decoration: BoxDecoration(
                      color: pomColor,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                          color: pomColor.withValues(alpha: 1.0), width: 0.5)),
                  child: height < 18
                      ? const Icon(Icons.local_fire_department,
                          size: 8, color: Colors.white)
                      : SingleChildScrollView(
                          physics: const NeverScrollableScrollPhysics(),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.only(top: 1.0),
                                    child: const Icon(
                                        Icons.local_fire_department,
                                        size: 8,
                                        color: Colors.white),
                                  ),
                                  const SizedBox(width: 2),
                                  Expanded(
                                    child: Text(
                                      pomTitle,
                                      style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 9,
                                          fontWeight: FontWeight.bold,
                                          height: 1.0),
                                      maxLines: pomMaxLines,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                              if (height > 22)
                                Text(
                                  '${record.effectiveDuration ~/ 60}min',
                                  style: TextStyle(
                                      color:
                                          Colors.white.withValues(alpha: 0.85),
                                      fontSize: 7,
                                      height: 1.0),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                            ],
                          ),
                        ),
                ),
              ),
            ),
          ));
        }
      }
    }

    if (_activeDataViews.contains('courses')) {
      for (var course in _weekCourses) {
        int sh = course.startTime ~/ 100;
        int sm = course.startTime % 100;
        int eh = course.endTime ~/ 100;
        int em = course.endTime % 100;

        double top = _timeToY(sh, sm, minuteHeight);
        double height = _timeToY(eh, em, minuteHeight) - top;
        double left = timeColumnWidth + (course.weekday - 1) * cellWidth;
        double courseWidth = cellWidth - 2;

        Color bgColor = _getCourseColor(course.courseName);
        final cardKey = _getCourseCardKey(
            course.courseName, course.weekday, course.startTime);
        final courseIndex = _weekCourses.indexOf(course);

        // 🚀 根据课程卡片的物理高度动态计算课程名称的最大行数限制，四舍五入并收紧估算，让文本尽量多地展开
        int courseMaxLines = 2;
        if (course.roomName.isNotEmpty && height > 30) {
          double availableForCourse = (height - 2) - 14.5;
          courseMaxLines = (availableForCourse / 12.0).round();
          if (courseMaxLines < 1) courseMaxLines = 1;
        } else {
          double availableForCourse = (height - 2) - 5.0;
          courseMaxLines = (availableForCourse / 12.0).round();
          if (courseMaxLines < 1) courseMaxLines = 1;
        }

        children.add(Positioned(
          top: top + 1,
          left: left + 1,
          width: courseWidth,
          height: height - 2,
          child: AnimatedBuilder(
            animation: _courseExpandAnim,
            builder: (ctx, child) {
              final delay = (courseIndex * 0.06).clamp(0.0, 0.5);
              final t = ((_courseExpandAnim.value - delay) / (1.0 - delay))
                  .clamp(0.0, 1.0);
              final scale = 0.7 + 0.3 * t;
              final opacity = t;
              return Transform.scale(
                scale: scale,
                child: Opacity(
                  opacity: opacity,
                  child: child,
                ),
              );
            },
            child: GestureDetector(
              onTap: () {
                final renderBox =
                    cardKey.currentContext?.findRenderObject() as RenderBox?;
                if (renderBox != null) {
                  final rect =
                      renderBox.localToGlobal(Offset.zero) & renderBox.size;
                  Navigator.push(
                    context,
                    ContainerTransformRoute(
                      page: CourseDetailScreen(course: course),
                      sourceRect: rect,
                      sourceColor: bgColor.withValues(alpha: 0.95),
                      sourceBorderRadius:
                          const BorderRadius.all(Radius.circular(4)),
                    ),
                  );
                } else {
                  Navigator.push(
                      context,
                      PageTransitions.slideHorizontal(
                        CourseDetailScreen(course: course),
                      ));
                }
              },
              child: Container(
                key: cardKey,
                clipBehavior: Clip.hardEdge,
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                    color: bgColor.withValues(alpha: 0.95),
                    borderRadius: BorderRadius.circular(4),
                    boxShadow: const [
                      BoxShadow(
                          color: Colors.black12,
                          blurRadius: 1,
                          offset: Offset(0, 1))
                    ]),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      course.courseName,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          height: 1.15),
                      maxLines: courseMaxLines,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (height > 30) ...[
                      const SizedBox(height: 2),
                      Text(
                        course.roomName,
                        style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.85),
                            fontSize: 9,
                            height: 1.1),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ));
      }
    }

    DateTime now = DateTime.now();
    if (now.hour >= startHour && now.hour <= endHour) {
      if (_semesterMonday != null) {
        DateTime currentMonday =
            _semesterMonday!.add(Duration(days: (_currentWeek - 1) * 7));
        int diffDays = DateTime(now.year, now.month, now.day)
            .difference(currentMonday)
            .inDays;

        if (diffDays >= 0 && diffDays <= 6) {
          double nowY = _timeToY(now.hour, now.minute, minuteHeight);
          double lineLeft = timeColumnWidth + diffDays * cellWidth;

          children.add(Positioned(
            top: nowY,
            left: timeColumnWidth,
            width: cellWidth * 7,
            height: 1,
            child: AnimatedBuilder(
              animation: _pulseAnimation,
              builder: (context, child) {
                return Container(
                  color: Colors.redAccent
                      .withValues(alpha: 0.3 + 0.2 * _pulseAnimation.value),
                );
              },
            ),
          ));
          children.add(Positioned(
            top: nowY - 2.5,
            left: lineLeft - 2,
            width: 6,
            height: 6,
            child: AnimatedBuilder(
              animation: _pulseAnimation,
              builder: (context, child) {
                return Container(
                  decoration: BoxDecoration(
                    color: Colors.redAccent
                        .withValues(alpha: _pulseAnimation.value),
                    shape: BoxShape.circle,
                  ),
                );
              },
            ),
          ));
        }
      }
    }

    return Stack(children: children);
  }

  Widget _buildTodaySidebar() {
    DateTime now = DateTime.now();
    String dateStr = DateFormat('M月d日').format(now);
    String weekdayStr =
        ['周一', '周二', '周三', '周四', '周五', '周六', '周日'][now.weekday - 1];
    bool isDark = Theme.of(context).brightness == Brightness.dark;

    List<TodoItem> todayAllDay = !_activeDataViews.contains('todos')
        ? []
        : _allTodos.where((todo) {
            DateTime start = DateTime.fromMillisecondsSinceEpoch(
                    todo.createdDate ?? todo.createdAt,
                    isUtc: true)
                .toLocal();
            DateTime end = todo.dueDate ?? start.add(const Duration(hours: 1));

            bool isAllDayFlag = todo.dueDate != null &&
                start.hour == 0 &&
                start.minute == 0 &&
                todo.dueDate!.hour == 23 &&
                todo.dueDate!.minute == 59;
            bool isCrossDay = !(start.year == end.year &&
                start.month == end.month &&
                start.day == end.day);
            bool treatAsAllDay = isAllDayFlag || isCrossDay;

            if (!treatAsAllDay) return false;

            // 如果开启了隐藏跨天，且该任务是跨天任务，则过滤掉
            if (_activeDataViews.contains('hideCrossDay') && isCrossDay)
              return false;

            DateTime todayStart = DateTime(now.year, now.month, now.day);
            DateTime todayEnd = todayStart
                .add(const Duration(hours: 23, minutes: 59, seconds: 59));

            return start.isBefore(todayEnd) && end.isAfter(todayStart);
          }).toList();

    // 排序：未完成优先
    todayAllDay.sort((a, b) {
      if (a.isDone == b.isDone) return 0;
      return a.isDone ? 1 : -1;
    });

    // 🚀 平板适配：如果是在月视图且选中了日期，展示该日的详情
    if (_viewMode == 2 && _selectedMonthDay != null) {
      return _buildMonthDaySidebar(_selectedMonthDay!);
    }

    return Container(
      width: double.infinity,
      color: isDark ? Colors.grey[900] : Colors.grey[50],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "今日全天事项",
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  "$dateStr · $weekdayStr",
                  style: TextStyle(
                    fontSize: 14,
                    color: isDark ? Colors.white54 : Colors.black54,
                  ),
                ),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20),
            child: Divider(),
          ),
          Expanded(
            child: todayAllDay.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.event_available,
                            size: 48,
                            color: isDark ? Colors.white12 : Colors.black12),
                        const SizedBox(height: 16),
                        Text(
                          "今天没有全天待办",
                          style: TextStyle(
                            color: isDark ? Colors.white24 : Colors.black26,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: todayAllDay.length,
                    itemBuilder: (context, index) {
                      final todo = todayAllDay[index];
                      return Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 4),
                        child: InkWell(
                          onTap: () {
                            Navigator.push(
                                context,
                                PageTransitions.slideHorizontal(
                                    TodoDetailScreen(todo: todo)));
                          },
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: todo.isDone
                                  ? (isDark
                                      ? Colors.green.withValues(alpha: 0.1)
                                      : Colors.green.withValues(alpha: 0.05))
                                  : (isDark
                                      ? Colors.amber.withValues(alpha: 0.1)
                                      : Colors.amber.withValues(alpha: 0.05)),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: todo.isDone
                                    ? Colors.green.withValues(alpha: 0.3)
                                    : Colors.amber.withValues(alpha: 0.3),
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  todo.isDone
                                      ? Icons.check_circle
                                      : Icons.task_alt,
                                  size: 20,
                                  color:
                                      todo.isDone ? Colors.green : Colors.amber,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      if (todo.teamUuid != null)
                                        Padding(
                                          padding:
                                              const EdgeInsets.only(bottom: 2),
                                          child: Row(
                                            children: [
                                              const Icon(Icons.group,
                                                  size: 10, color: Colors.blue),
                                              const SizedBox(width: 4),
                                              Text(todo.teamName ?? '团队',
                                                  style: const TextStyle(
                                                      fontSize: 10,
                                                      color: Colors.blue,
                                                      fontWeight:
                                                          FontWeight.bold)),
                                            ],
                                          ),
                                        ),
                                      Text(
                                        todo.title,
                                        style: TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w500,
                                          decoration: todo.isDone
                                              ? TextDecoration.lineThrough
                                              : null,
                                          color: todo.isDone
                                              ? (isDark
                                                  ? Colors.white38
                                                  : Colors.black38)
                                              : (isDark
                                                  ? Colors.white
                                                  : Colors.black87),
                                        ),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
          Padding(
            padding: const EdgeInsets.all(20.0),
            child: Text(
              "共 ${todayAllDay.length} 项全天事项",
              style: TextStyle(
                  fontSize: 12,
                  color: isDark ? Colors.white24 : Colors.black26),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    bool isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            IconButton(
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              icon: const Icon(Icons.arrow_back_ios, size: 13),
              onPressed: () {
                if (_viewMode == 2) {
                  _changeMonth(-1);
                } else if (_viewMode == 1) {
                  _changeWeek(-2);
                } else {
                  _changeWeek(-1);
                }
              },
            ),
            const SizedBox(width: 4),
            GestureDetector(
              onTap: _viewMode == 0 ? _showWeekJumpDialog : null,
              child: Text(
                _viewMode == 2
                    ? DateFormat('yyyy年M月').format(_selectedMonth)
                    : (_viewMode == 1 ? _getBiWeekLabel() : _getWeekLabel()),
                style:
                    const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(width: 4),
            IconButton(
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              icon: const Icon(Icons.arrow_forward_ios, size: 13),
              onPressed: () {
                if (_viewMode == 2) {
                  _changeMonth(1);
                } else if (_viewMode == 1) {
                  _changeWeek(2);
                } else {
                  _changeWeek(1);
                }
              },
            ),
          ],
        ),
        centerTitle: false,
        titleSpacing: 0,
        actions: [
          IconButton(
            visualDensity: const VisualDensity(horizontal: -2),
            icon: const Icon(Icons.smart_toy_outlined, size: 20),
            tooltip: 'AI日程助手',
            onPressed: _openAiAssistant,
          ),
          IconButton(
            visualDensity: const VisualDensity(horizontal: -2),
            icon: Icon(
                _viewMode == 2
                    ? Icons.view_week
                    : (_viewMode == 1
                        ? Icons.calendar_month
                        : Icons.calendar_view_week),
                size: 20),
            tooltip: '切换试图模式',
            onPressed: () => _toggleViewMode((_viewMode + 1) % 3),
          ),
          IconButton(
            visualDensity: const VisualDensity(horizontal: -2),
            icon: const Icon(Icons.edit_calendar, size: 20),
            tooltip: '记录时间日志',
            onPressed: () async {
              final result = await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) =>
                      TimeLogScreen(username: widget.username),
                ),
              );
              if (result == true) {
                _loadData();
              }
            },
          ),
          MenuAnchor(
            menuChildren: [
              _buildCheckableMenuItem('courses', '课表'),
              _buildCheckableMenuItem('todos', '待办'),
              _buildCheckableMenuItem('timeLogs', '时间日志'),
              _buildCheckableMenuItem('plans', '今日规划'),
              _buildCheckableMenuItem('pomodoros', '番茄钟'),
              const Divider(height: 1),
              _buildCheckableMenuItem('hideCrossDay', '隐藏跨天待办'),
              _buildCheckableMenuItem('disableFreeTimeCollapse', '不折叠空余时间'),
              const Divider(height: 1),
              _buildFilterActionItem(
                'selectAll',
                '一键全选',
                Icons.select_all,
                Theme.of(context).colorScheme.primary,
              ),
              _buildFilterActionItem(
                'clearAll',
                '一键清除',
                Icons.clear_all,
                Colors.redAccent,
              ),
            ],
            builder: (context, controller, child) {
              return IconButton(
                visualDensity: const VisualDensity(horizontal: -2),
                icon: const Icon(Icons.filter_list, size: 20),
                tooltip: '筛选显示内容',
                onPressed: () {
                  if (controller.isOpen) {
                    controller.close();
                  } else {
                    controller.open();
                  }
                },
              );
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _isLoading
          ? _buildSkeleton()
          : LayoutBuilder(
              builder: (context, constraints) {
                final bool isWide = constraints.maxWidth > 900;

                return Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onScaleUpdate: (details) {
                          final now = DateTime.now();
                          if (_lastModeSwitch != null &&
                              now.difference(_lastModeSwitch!).inMilliseconds <
                                  800) return;

                          if (details.scale < 0.7) {
                            if (_viewMode < 2) {
                              _toggleViewMode(_viewMode + 1);
                              _lastModeSwitch = now;
                              HapticFeedback.lightImpact();
                            }
                          } else if (details.scale > 1.5) {
                            if (_viewMode > 0) {
                              _toggleViewMode(_viewMode - 1);
                              _lastModeSwitch = now;
                              HapticFeedback.lightImpact();
                            }
                          }
                        },
                        onHorizontalDragUpdate: (details) {
                          // 让视图跟手移动
                          setState(() {
                            _dragOffset += details.delta.dx;
                          });
                        },
                        onHorizontalDragEnd: (details) {
                          final screenWidth = MediaQuery.of(context).size.width;
                          final threshold = screenWidth * 0.2; // 20% 宽度触发切换

                          if (_dragOffset.abs() > threshold ||
                              details.primaryVelocity!.abs() > 300) {
                            if (_dragOffset > 0 ||
                                (details.primaryVelocity ?? 0) > 300) {
                              // 向右滑动 -> 上一个
                              if (_viewMode == 2) {
                                _changeMonth(-1);
                              } else {
                                _changeWeek(-1);
                              }
                            } else {
                              // 向左滑动 -> 下一个
                              if (_viewMode == 2) {
                                _changeMonth(1);
                              } else {
                                _changeWeek(1);
                              }
                            }
                            HapticFeedback.lightImpact();
                          }

                          // 重置位移（AnimatedSwitcher 会处理新旧视图的平滑切换）
                          setState(() {
                            _dragOffset = 0;
                          });
                        },
                        child: Column(
                          children: [
                            if (_viewMode == 0) ...[
                              _buildHeader(_getMondayOfCurrentWeek()),
                              _buildAllDayHeaderRow(_getMondayOfCurrentWeek()),
                              Divider(
                                  height: 1,
                                  thickness: 0.5,
                                  color:
                                      isDark ? Colors.white10 : Colors.black12),
                            ],
                            Expanded(
                              child: TweenAnimationBuilder<double>(
                                duration: const Duration(milliseconds: 600),
                                curve: Curves.easeInOutQuart,
                                tween: Tween<double>(
                                  begin: _viewMode > 0 ? 1.0 : 0.0,
                                  end: _viewMode > 0 ? 1.0 : 0.0,
                                ),
                                builder: (context, t, child) {
                                  return ClipRect(
                                    child: Stack(
                                      children: [
                                        // --- 🚀 二周/月视图 & 甘特图 ---
                                        IgnorePointer(
                                          ignoring: _viewMode == 0,
                                          child: AnimatedOpacity(
                                            duration: const Duration(
                                                milliseconds: 400),
                                            opacity: _viewMode > 0 ? 1.0 : 0.0,
                                            child: Transform.scale(
                                              scale: _viewMode > 0 ? 1.0 : 0.8,
                                              child: CourseMonthView(
                                                key: ValueKey(
                                                    'MonthView_${_selectedMonth.year}_${_selectedMonth.month}_mode$_viewMode'),
                                                selectedMonth: _selectedMonth,
                                                courseMap: _monthCourseMap,
                                                todoMap: _monthTodoMap,
                                                crossDayTodoMap:
                                                    _monthCrossDayTodoMap,
                                                logMap: _monthLogMap,
                                                pomMap: _monthPomMap,
                                                pomodoroTags: _pomodoroTags,
                                                activeDataViews:
                                                    _activeDataViews,
                                                allTodos: _allTodos,
                                                viewMode: _viewMode,
                                                currentWeekMonday:
                                                    _getMondayOfCurrentWeek(), // 🚀 动态透传起点
                                                onMonthChanged: (m) => setState(
                                                    () => _selectedMonth = m),
                                                onDayTapped: (d) {
                                                  setState(() =>
                                                      _selectedMonthDay = d);
                                                  if (constraints.maxWidth <=
                                                      900) {
                                                    _showDayDetailSheet(d);
                                                  }
                                                },
                                                onGanttTodoTap: (todo) {
                                                  if (todo.dueDate != null) {
                                                    setState(() =>
                                                        _selectedMonthDay =
                                                            todo.dueDate);
                                                    if (constraints.maxWidth <=
                                                        900) {
                                                      _showDayDetailSheet(
                                                          todo.dueDate!);
                                                    }
                                                  }
                                                },
                                              ),
                                            ),
                                          ),
                                        ),
                                        // --- 周视图 (使用 child 避免重复 build) ---
                                        IgnorePointer(
                                          ignoring: t > 0.5,
                                          child: Opacity(
                                            opacity: (1.0 - t).clamp(0.0, 1.0),
                                            child: Transform.scale(
                                              scale: 1.0 + (t * 0.2),
                                              child: child,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                                // 提取为 child, 确保在 TweenAnimationBuilder 动画时周视图不会触发 build
                                child: AnimatedSwitcher(
                                  duration: const Duration(milliseconds: 400),
                                  transitionBuilder: (child, animation) {
                                    return Transform.translate(
                                      offset: Offset(
                                          _dragOffset * (1.0 - animation.value),
                                          0),
                                      child: SlideTransition(
                                        position: Tween<Offset>(
                                          begin: Offset(
                                              _isNextSlide ? 1.0 : -1.0, 0.0),
                                          end: Offset.zero,
                                        ).animate(CurvedAnimation(
                                            parent: animation,
                                            curve: Curves.easeOutCubic)),
                                        child: FadeTransition(
                                            opacity: animation, child: child),
                                      ),
                                    );
                                  },
                                  child: RepaintBoundary(
                                    key: ValueKey('WeekView_$_currentWeek'),
                                    child: LayoutBuilder(
                                      builder: (context, innerConstraints) {
                                        double cellWidth =
                                            (innerConstraints.maxWidth -
                                                    timeColumnWidth) /
                                                7;
                                        // 🚀 恢复自适应：将全天时间轴按比例缩放到当前屏幕可用高度，无需滑动
                                        double totalMinutes =
                                            (endHour - startHour) * 60.0 -
                                                _totalHiddenMinutes;
                                        double minuteHeight =
                                            innerConstraints.maxHeight /
                                                totalMinutes;

                                        return _buildGrid(
                                            cellWidth, minuteHeight);
                                      },
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (isWide)
                      Container(
                        width: 350,
                        decoration: BoxDecoration(
                          border: Border(
                            left: BorderSide(
                              color: isDark ? Colors.white10 : Colors.black12,
                              width: 1,
                            ),
                          ),
                        ),
                        child: _selectedMonthDay != null
                            ? _buildMonthDaySidebar(_selectedMonthDay!)
                            : _buildTodaySidebar(),
                      ),
                  ],
                );
              },
            ),
    );
  }

  Future<void> _openAiAssistant() async {
    try {
      final groups = await StorageService.getTodoGroups(widget.username);
      if (!mounted) return;
      await AiTodoChatLauncher.open(
        context,
        username: widget.username,
        todos: _allTodos,
        todoGroups: groups.where((g) => !g.isDeleted).toList(),
        courses: _allCourses,
        timeLogs: _allTimeLogs,
        pomodoroRecords: _allPomodoroRecords,
        pomodoroTags: _pomodoroTags,
        onTodosBatchAction: (inserted, updated) async {
          final allTodos = await StorageService.getTodos(widget.username);
          final merged = AiTodoActionExecutor.mergeTodoUpdates(
              allTodos, inserted, updated);
          await StorageService.saveTodos(widget.username, merged);
          await _loadData();
        },
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('打开AI助手失败: $e')),
        );
      }
    }
  }

  Widget _buildSkeleton() {
    bool isDark = Theme.of(context).brightness == Brightness.dark;
    Color baseColor =
        isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.05);

    return FadeTransition(
      opacity: _pulseAnimation,
      child: Column(
        children: [
          // 头部骨架 (日期)
          Container(
            height: 60,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Container(width: timeColumnWidth),
                for (int i = 0; i < 7; i++)
                  Expanded(
                    child: Center(
                      child: Container(
                        width: 30,
                        height: 12,
                        decoration: BoxDecoration(
                          color: baseColor,
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          // 网格骨架
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                double cellWidth = (constraints.maxWidth - timeColumnWidth) / 7;
                return Row(
                  children: [
                    Container(width: timeColumnWidth),
                    Expanded(
                      child: Stack(
                        children: [
                          // 纵向分割线
                          for (int i = 0; i <= 7; i++)
                            Positioned(
                              left: i * cellWidth,
                              top: 0,
                              bottom: 0,
                              child: Container(width: 0.5, color: baseColor),
                            ),
                          // 几个占位框，模拟课表布局
                          _buildSkeletonBox(cellWidth, 120, 80, 1, baseColor),
                          _buildSkeletonBox(cellWidth, 250, 60, 2, baseColor),
                          _buildSkeletonBox(cellWidth, 150, 100, 4, baseColor),
                          _buildSkeletonBox(cellWidth, 400, 90, 5, baseColor),
                          _buildSkeletonBox(cellWidth, 200, 70, 0, baseColor),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSkeletonBox(
      double cellWidth, double top, double height, int dayIndex, Color color) {
    return Positioned(
      left: dayIndex * cellWidth + 4,
      top: top,
      width: cellWidth - 8,
      height: height,
      child: Container(
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );
  }

  String _safeStr(String? s) {
    if (s == null) return '';
    return s.replaceAll(
        RegExp(
            r'[\uD800-\uDBFF](?![\uDC00-\uDFFF])|(^|[^\uD800-\uDBFF])[\uDC00-\uDFFF]'),
        '');
  }

  void _showDayDetailSheet(DateTime day) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.75,
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
        ),
        child: ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
          child: _buildMonthDaySidebar(day),
        ),
      ),
    );
  }

  void _showTodoDetails(TodoItem todo) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    DateTime startTime = DateTime.fromMillisecondsSinceEpoch(
            todo.createdDate ?? todo.createdAt,
            isUtc: true)
        .toLocal();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.85),
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.1),
                blurRadius: 20,
                offset: const Offset(0, -5))
          ],
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white10 : Colors.black12,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Row(
                children: [
                  Container(
                      width: 4,
                      height: 24,
                      decoration: BoxDecoration(
                          color: todo.isDone ? Colors.green : Colors.amber,
                          borderRadius: BorderRadius.circular(2))),
                  const SizedBox(width: 12),
                  const Text("任务详情",
                      style:
                          TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.open_in_new_rounded, size: 20),
                    onPressed: () {
                      Navigator.pop(context);
                      Navigator.push(
                          context,
                          PageTransitions.slideHorizontal(
                              TodoDetailScreen(todo: todo)));
                    },
                    tooltip: '详情页',
                  ),
                  IconButton(
                      icon: const Icon(Icons.close_rounded, size: 20),
                      onPressed: () => Navigator.pop(context)),
                ],
              ),
              const SizedBox(height: 24),
              Text(_safeStr(todo.title),
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    decoration: todo.isDone ? TextDecoration.lineThrough : null,
                    color: todo.isDone ? Colors.grey : null,
                  )),
              const SizedBox(height: 16),
              if (todo.remark != null && todo.remark!.isNotEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  margin: const EdgeInsets.only(bottom: 24),
                  decoration: BoxDecoration(
                    color: (isDark ? Colors.white : Colors.black)
                        .withValues(alpha: 0.03),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                        color: (isDark ? Colors.white : Colors.black)
                            .withValues(alpha: 0.05)),
                  ),
                  child: Text(_safeStr(todo.remark!),
                      style: TextStyle(
                          fontSize: 15,
                          color: isDark ? Colors.white70 : Colors.black87,
                          height: 1.5)),
                ),
              Wrap(
                spacing: 16,
                runSpacing: 20,
                children: [
                  _buildDetailItem(
                      Icons.flag_rounded, "任务状态", todo.isDone ? "已完成" : "进行中",
                      color: todo.isDone ? Colors.green : Colors.amber),
                  _buildDetailItem(
                      Icons.calendar_today_rounded,
                      "截止日期",
                      todo.dueDate != null
                          ? TimezoneUtils.getRelativeTime(
                              todo.dueDate!.millisecondsSinceEpoch)
                          : "未设置",
                      color: (todo.dueDate != null &&
                              !todo.isDone &&
                              todo.dueDate!.isBefore(DateTime.now()))
                          ? Colors.red
                          : null),
                  _buildDetailItem(Icons.schedule_rounded, "开始时间",
                      DateFormat('MM-dd HH:mm').format(startTime)),
                  if (todo.recurrence != RecurrenceType.none)
                    _buildDetailItem(Icons.repeat_rounded, "重复模式",
                        _getRecurrenceLabel(todo.recurrence)),
                  _buildDetailItem(
                      Icons.group_rounded, "所属团队", todo.teamName ?? "个人任务",
                      color: todo.teamUuid != null ? Colors.blue : null),
                  if (todo.creatorName != null)
                    _buildDetailItem(
                        Icons.person_outline_rounded, "创建人", todo.creatorName!),
                  if (todo.reminderMinutes != null && todo.reminderMinutes! > 0)
                    _buildDetailItem(Icons.notifications_active_rounded, "提醒设置",
                        "提前 ${todo.reminderMinutes} 分钟"),
                ],
              ),
              if (todo.imagePath != null && todo.imagePath!.isNotEmpty) ...[
                const SizedBox(height: 24),
                const Text("附件图片",
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey)),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Image.file(
                    File(todo.imagePath!),
                    width: double.infinity,
                    fit: BoxFit.cover,
                    errorBuilder: (ctx, err, stack) => const SizedBox.shrink(),
                  ),
                ),
              ],
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  String _getRecurrenceLabel(RecurrenceType type) {
    switch (type) {
      case RecurrenceType.daily:
        return "每天";
      case RecurrenceType.weekly:
        return "每周";
      case RecurrenceType.monthly:
        return "每月";
      case RecurrenceType.yearly:
        return "每年";
      case RecurrenceType.weekdays:
        return "工作日";
      case RecurrenceType.customDays:
        return "自定义天数";
      default:
        return "不重复";
    }
  }

  Widget _buildDetailItem(IconData icon, String label, String value,
      {Color? color}) {
    return SizedBox(
      width: 140,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: Colors.grey),
              const SizedBox(width: 6),
              Text(label,
                  style: const TextStyle(fontSize: 11, color: Colors.grey)),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: color,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildPanoramaContent() {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      color: isDark ? const Color(0xFF0F0F0F) : const Color(0xFFF2F4F7),
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 8),
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                borderRadius: BorderRadius.circular(28),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 20,
                      offset: const Offset(0, 10))
                ],
              ),
              child: Column(
                children: [
                  TeamHeatmapWidget(todos: _allTodos, viewDays: 35),
                  const Padding(
                      padding: EdgeInsets.symmetric(vertical: 20),
                      child: Divider(indent: 16, endIndent: 16)),
                  TeamGanttWidget(
                    todos: _allTodos,
                    viewDays: 30,
                    onTodoTap: _showTodoDetails,
                  ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  _buildPanoStatStat(
                      "全量待办", "${_allTodos.length}", Colors.blue),
                  const SizedBox(width: 12),
                  _buildPanoStatStat(
                      "团队协作",
                      "${_allTodos.where((t) => t.teamUuid != null).length}",
                      Colors.purple),
                ],
              ),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 100)),
        ],
      ),
    );
  }

  Widget _buildPanoStatStat(String label, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: TextStyle(
                    fontSize: 11, color: color, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Text(value,
                style: TextStyle(
                    fontSize: 24, fontWeight: FontWeight.bold, color: color)),
          ],
        ),
      ),
    );
  }
}

// --- Detail Screens ---

class CourseDetailScreen extends StatelessWidget {
  final CourseItem course;
  const CourseDetailScreen({super.key, required this.course});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('课程详情')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const Icon(Icons.class_, size: 80, color: Colors.blueAccent),
          const SizedBox(height: 16),
          Text(course.courseName,
              textAlign: TextAlign.center,
              style:
                  const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
          const SizedBox(height: 32),
          _buildDetailRow(Icons.person, '授课教师', course.teacherName),
          const Divider(),
          _buildDetailRow(Icons.location_on, '上课地点', course.roomName),
          const Divider(),
          _buildDetailRow(Icons.calendar_today, '日期',
              '${course.date} (第${course.weekIndex}周 周${course.weekday})'),
          const Divider(),
          _buildDetailRow(Icons.access_time, '时间',
              '${course.formattedStartTime} - ${course.formattedEndTime}'),
          if (course.lessonType != null && course.lessonType!.isNotEmpty) ...[
            const Divider(),
            _buildDetailRow(
                Icons.category,
                '类型/备注',
                course.lessonType == 'EXPERIMENT'
                    ? '实验课'
                    : (course.lessonType == 'THEORY'
                        ? '理论课'
                        : course.lessonType!)),
          ],
        ],
      ),
    );
  }

  Widget _buildDetailRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Icon(icon, color: Colors.grey),
          const SizedBox(width: 16),
          Text(label, style: const TextStyle(color: Colors.grey, fontSize: 16)),
          const Spacer(),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }
}

class TodoDetailScreen extends StatefulWidget {
  final TodoItem todo;
  const TodoDetailScreen({super.key, required this.todo});

  @override
  State<TodoDetailScreen> createState() => _TodoDetailScreenState();
}

class _TodoDetailScreenState extends State<TodoDetailScreen> {
  List<PomodoroRecord> _focusRecords = [];
  bool _loadingRecords = true;

  @override
  void initState() {
    super.initState();
    _loadFocusRecords();
  }

  Future<void> _loadFocusRecords() async {
    final records = await PomodoroService.getRecordsByTodoUuid(widget.todo.id);
    if (mounted) {
      setState(() {
        _focusRecords = records;
        _loadingRecords = false;
      });
    }
  }

  String _getRecurrenceText() {
    final todo = widget.todo;
    switch (todo.recurrence) {
      case RecurrenceType.none:
        return '不重复';
      case RecurrenceType.daily:
        return '每天';
      case RecurrenceType.weekly:
        return '每周';
      case RecurrenceType.monthly:
        return '每月';
      case RecurrenceType.yearly:
        return '每年';
      case RecurrenceType.weekdays:
        return '工作日';
      case RecurrenceType.customDays:
        return '每 ${todo.customIntervalDays} 天';
      default:
        return '未知';
    }
  }

  @override
  Widget build(BuildContext context) {
    final todo = widget.todo;
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;

    DateTime startTime = DateTime.fromMillisecondsSinceEpoch(
            todo.createdDate ?? todo.createdAt,
            isUtc: true)
        .toLocal();

    DateTime? endTime = todo.dueDate;

    String startTimeStr = todo.isAllDay
        ? DateFormat('yyyy-MM-dd (全天)').format(startTime)
        : DateFormat('yyyy-MM-dd HH:mm').format(startTime);

    String endTimeStr = endTime == null
        ? '无截止时间'
        : (todo.isAllDay
            ? DateFormat('yyyy-MM-dd (全天)').format(endTime)
            : DateFormat('yyyy-MM-dd HH:mm').format(endTime));

    double progress = 0.0;
    if (todo.isDone) {
      progress = 1.0;
    } else if (endTime != null) {
      final now = DateTime.now();
      final total = endTime.difference(startTime).inSeconds;
      if (total > 0) {
        final passed = now.difference(startTime).inSeconds;
        progress = (passed / total).clamp(0.0, 1.0);
      }
    }

    return Scaffold(
      backgroundColor:
          isDark ? const Color(0xFF121212) : const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: const Text('任务详情'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        child: Column(
          children: [
            // Header Card
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: isDark ? Colors.grey[900] : Colors.white,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  )
                ],
              ),
              child: Column(
                children: [
                  Icon(
                    todo.isDone
                        ? Icons.check_circle_rounded
                        : Icons.pending_rounded,
                    size: 64,
                    color: todo.isDone ? Colors.green : Colors.amber,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    todo.title,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      decoration:
                          todo.isDone ? TextDecoration.lineThrough : null,
                      color: todo.isDone ? Colors.grey : null,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: LinearProgressIndicator(
                            value: progress,
                            minHeight: 8,
                            backgroundColor:
                                colorScheme.primary.withValues(alpha: 0.1),
                            valueColor: AlwaysStoppedAnimation<Color>(
                                todo.isDone
                                    ? Colors.green
                                    : colorScheme.primary),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        "${(progress * 100).toInt()}%",
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color:
                              todo.isDone ? Colors.green : colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            _buildSection(context, "基本信息", [
              _buildModernRow(
                  Icons.flag_rounded, "当前状态", todo.isDone ? "已完成" : "进行中",
                  valueColor: todo.isDone ? Colors.green : Colors.amber),
              _buildModernRow(Icons.schedule_rounded, "开始时间", startTimeStr),
              _buildModernRow(Icons.event_busy_rounded, "截止时间", endTimeStr,
                  valueColor: (endTime != null &&
                          !todo.isDone &&
                          endTime.isBefore(DateTime.now()))
                      ? Colors.red
                      : null),
              if (todo.recurrence != RecurrenceType.none)
                _buildModernRow(
                    Icons.repeat_rounded, "重复周期", _getRecurrenceText()),
              if (todo.reminderMinutes != null && todo.reminderMinutes! > 0)
                _buildModernRow(Icons.notifications_active_rounded, "提醒设置",
                    "提前 ${todo.reminderMinutes} 分钟"),
            ]),

            if (todo.teamUuid != null)
              _buildSection(context, "协作信息", [
                _buildModernRow(
                    Icons.group_rounded, "所属团队", todo.teamName ?? "未知团队"),
                _buildModernRow(
                    Icons.person_rounded, "创建者", todo.creatorName ?? "未知用户"),
                _buildModernRow(Icons.handshake_rounded, "协作模式",
                    todo.collabType == 1 ? "每个人独立完成" : "所有人共同协作"),
              ]),

            if (todo.remark != null && todo.remark!.isNotEmpty)
              _buildSection(context, "备注详情", [
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    todo.remark!,
                    style: TextStyle(
                      fontSize: 14,
                      color: isDark ? Colors.white70 : Colors.black87,
                      height: 1.5,
                    ),
                  ),
                ),
              ]),

            if (todo.originalText != null && todo.originalText!.isNotEmpty)
              _buildSection(context, "原始识别文本", [
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    todo.originalText!,
                    style: TextStyle(
                      fontSize: 12,
                      fontStyle: FontStyle.italic,
                      color: Colors.grey,
                    ),
                  ),
                ),
              ]),

            if (todo.imagePath != null && todo.imagePath!.isNotEmpty)
              _buildSection(context, "附件图片", [
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.file(
                      File(todo.imagePath!),
                      errorBuilder: (ctx, err, stack) => const Text("无法加载本地图片",
                          style: TextStyle(color: Colors.grey, fontSize: 12)),
                    ),
                  ),
                ),
              ]),

            _buildSection(context, "系统信息", [
              _buildModernRow(
                  Icons.update_rounded,
                  "最近更新",
                  DateFormat('yyyy-MM-dd HH:mm:ss').format(
                      DateTime.fromMillisecondsSinceEpoch(todo.updatedAt,
                              isUtc: true)
                          .toLocal())),
              _buildModernRow(
                  Icons.fingerprint_rounded,
                  "任务 ID",
                  todo.id.length > 8
                      ? "${todo.id.substring(0, 8)}..."
                      : todo.id, onTap: () {
                Clipboard.setData(ClipboardData(text: todo.id));
                ScaffoldMessenger.of(context)
                    .showSnackBar(const SnackBar(content: Text("ID 已复制到剪贴板")));
              }),
            ]),

            if (!_loadingRecords && _focusRecords.isNotEmpty)
              _buildSection(context, "专注记录 (${_focusRecords.length})", [
                ..._focusRecords.take(20).map((r) => _buildFocusRecordRow(r)),
                if (_focusRecords.length > 20)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      '仅显示最近 20 条',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[500],
                      ),
                    ),
                  ),
              ]),

            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildFocusRecordRow(PomodoroRecord r) {
    final startLocal =
        DateTime.fromMillisecondsSinceEpoch(r.startTime, isUtc: true).toLocal();
    final durationMin = r.effectiveDuration ~/ 60;
    final statusIcon =
        r.isCompleted ? Icons.check_circle_rounded : Icons.timer_off_rounded;
    final statusColor = r.isCompleted ? Colors.green : Colors.orange;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => PomodoroDetailScreen(
                record: r,
                tags: [],
              ),
            ),
          );
        },
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(statusIcon, size: 20, color: statusColor),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${DateFormat('MM-dd HH:mm').format(startLocal)} · $durationMin 分钟',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (r.note != null && r.note!.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      r.note!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSection(
      BuildContext context, String title, List<Widget> children) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? Colors.grey[900] : Colors.white,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey,
                  letterSpacing: 1.2)),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }

  Widget _buildModernRow(IconData icon, String label, String value,
      {Color? valueColor, VoidCallback? onTap}) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Icon(icon, size: 18, color: Colors.grey),
            const SizedBox(width: 12),
            Text(label,
                style: const TextStyle(fontSize: 14, color: Colors.grey)),
            const Spacer(),
            Text(value,
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: valueColor)),
          ],
        ),
      ),
    );
  }
}

class TimeLogDetailScreen extends StatelessWidget {
  final TimeLogItem log;
  final List<PomodoroTag> tags;
  const TimeLogDetailScreen({super.key, required this.log, required this.tags});

  Color _hexToColor(String hex) {
    String clean = hex.replaceAll('#', '');
    if (clean.length == 6) clean = 'FF$clean';
    return Color(int.parse(clean, radix: 16));
  }

  @override
  Widget build(BuildContext context) {
    DateTime start =
        DateTime.fromMillisecondsSinceEpoch(log.startTime, isUtc: true)
            .toLocal();
    DateTime end =
        DateTime.fromMillisecondsSinceEpoch(log.endTime, isUtc: true).toLocal();
    int durationMin = (log.endTime - log.startTime) ~/ 60000;

    Color logColor = const Color(0xFF3B82F6);
    String tagInfo = '无标签';
    if (log.tagUuids.isNotEmpty) {
      final tag = tags.cast<PomodoroTag?>().firstWhere(
          (t) => log.tagUuids.contains(t?.uuid),
          orElse: () => null);
      if (tag != null) {
        logColor = _hexToColor(tag.color);
        tagInfo = tag.name;
      }
    }

    return Scaffold(
      appBar: AppBar(title: const Text('时间日志详情')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Icon(Icons.edit_calendar, size: 80, color: logColor),
          const SizedBox(height: 16),
          Text(log.title.isNotEmpty ? log.title : '时间日志',
              textAlign: TextAlign.center,
              style:
                  const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
          const SizedBox(height: 32),
          _buildDetailRow(Icons.label, '标签', tagInfo),
          const Divider(),
          _buildDetailRow(Icons.access_time, '时长', '$durationMin 分钟'),
          const Divider(),
          _buildDetailRow(Icons.play_arrow, '开始时间',
              DateFormat('yyyy-MM-dd HH:mm').format(start)),
          const Divider(),
          _buildDetailRow(
              Icons.stop, '结束时间', DateFormat('yyyy-MM-dd HH:mm').format(end)),
          if (log.remark != null && log.remark!.isNotEmpty) ...[
            const Divider(),
            _buildDetailRow(Icons.note, '备注', log.remark!),
          ],
          const Divider(),
          _buildDetailRow(
              Icons.update,
              '最近更新',
              DateFormat('yyyy-MM-dd HH:mm').format(
                  DateTime.fromMillisecondsSinceEpoch(log.updatedAt,
                          isUtc: true)
                      .toLocal())),
        ],
      ),
    );
  }

  Widget _buildDetailRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Icon(icon, color: Colors.grey),
          const SizedBox(width: 16),
          Text(label, style: const TextStyle(color: Colors.grey, fontSize: 16)),
          const Spacer(),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }
}

class PomodoroDetailScreen extends StatelessWidget {
  final PomodoroRecord record;
  final List<PomodoroTag> tags;
  const PomodoroDetailScreen(
      {super.key, required this.record, required this.tags});

  Color _hexToColor(String hex) {
    String clean = hex.replaceAll('#', '');
    if (clean.length == 6) clean = 'FF$clean';
    return Color(int.parse(clean, radix: 16));
  }

  @override
  Widget build(BuildContext context) {
    DateTime start =
        DateTime.fromMillisecondsSinceEpoch(record.startTime, isUtc: true)
            .toLocal();
    int endMs =
        record.endTime ?? (record.startTime + record.effectiveDuration * 1000);
    DateTime end =
        DateTime.fromMillisecondsSinceEpoch(endMs, isUtc: true).toLocal();
    int durationMin = record.effectiveDuration ~/ 60;

    Color pomColor = Colors.redAccent;
    String tagInfo = '无标签';
    if (record.tagUuids.isNotEmpty) {
      final tag = tags.cast<PomodoroTag?>().firstWhere(
          (t) => record.tagUuids.contains(t?.uuid),
          orElse: () => null);
      if (tag != null) {
        pomColor = _hexToColor(tag.color);
        tagInfo = tag.name;
      }
    }

    String statusText = record.isCompleted ? '已完成' : '已中断';

    return Scaffold(
      appBar: AppBar(title: const Text('番茄钟详情')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Icon(Icons.local_fire_department, size: 80, color: pomColor),
          const SizedBox(height: 16),
          const Text('专注记录',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
          const SizedBox(height: 32),
          _buildDetailRow(Icons.label, '标签', tagInfo),
          const Divider(),
          _buildDetailRow(Icons.access_time, '时长', '$durationMin 分钟'),
          const Divider(),
          _buildDetailRow(Icons.play_arrow, '开始时间',
              DateFormat('yyyy-MM-dd HH:mm').format(start)),
          const Divider(),
          _buildDetailRow(
              Icons.stop, '结束时间', DateFormat('yyyy-MM-dd HH:mm').format(end)),
          const Divider(),
          _buildDetailRow(Icons.info_outline, '状态', statusText),
          if (record.todoTitle != null && record.todoTitle!.isNotEmpty) ...[
            const Divider(),
            _buildDetailRow(Icons.task_alt, '关联待办', record.todoTitle!),
          ],
          if (record.note != null && record.note!.isNotEmpty) ...[
            const Divider(),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.note_rounded, color: Colors.grey),
                  const SizedBox(width: 16),
                  const Text('备注',
                      style: TextStyle(color: Colors.grey, fontSize: 16)),
                  const Spacer(),
                  Flexible(
                    child: Text(
                      record.note!,
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w500),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const Divider(),
          _buildDetailRow(
              Icons.update,
              '最近更新',
              DateFormat('yyyy-MM-dd HH:mm').format(
                  DateTime.fromMillisecondsSinceEpoch(record.updatedAt,
                          isUtc: true)
                      .toLocal())),
        ],
      ),
    );
  }

  Widget _buildDetailRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Icon(icon, color: Colors.grey),
          const SizedBox(width: 16),
          Text(label, style: const TextStyle(color: Colors.grey, fontSize: 16)),
          const Spacer(),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }
}
