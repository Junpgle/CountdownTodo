import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../services/course_service.dart';
import '../services/pomodoro_service.dart';
import '../models.dart';
import '../storage_service.dart';
import '../utils/page_transitions.dart';
import 'time_log_screen.dart';
import 'course_month_view.dart';

// --- 二级界面：按周查看课表 (全屏自适应压缩视图) ---
class WeeklyCourseScreen extends StatefulWidget {
  final String username;
  const WeeklyCourseScreen({Key? key, required this.username})
      : super(key: key);

  @override
  State<WeeklyCourseScreen> createState() => _WeeklyCourseScreenState();
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
  Map<int, List<TimeLogItem>> _timeLogsPerDay = {};
  Map<int, List<PomodoroRecord>> _pomodorosPerDay = {};
  Set<String> _activeDataViews = {'courses', 'todos', 'timeLogs', 'pomodoros'};

  // --- 🚀 月视图相关 ---
  bool _isMonthView = false;
  DateTime _selectedMonth = DateTime.now();
  List<CourseItem> _allCourses = [];
  double _baseScale = 1.0;
  double _currentScale = 1.0;
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
    final keyStr = '${courseName}_${weekday}_${startTime}';
    return _courseCardKeys.putIfAbsent(keyStr, () => GlobalKey());
  }

  GlobalKey _getTodoCardKey(String id) {
    return _todoCardKeys.putIfAbsent(id, () => GlobalKey());
  }

  GlobalKey _getTimeLogCardKey(String id) {
    return _timeLogCardKeys.putIfAbsent(id, () => GlobalKey());
  }

  GlobalKey _getPomodoroCardKey(String id) {
    return _pomodoroCardKeys.putIfAbsent(id, () => GlobalKey());
  }

  // 时间轴参数配置
  final double timeColumnWidth = 45.0; 
  final int startHour = 7; 
  final int endHour = 23; 

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

  @override
  void dispose() {
    _pulseController.dispose();
    _courseExpandCtrl.dispose();
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final weeks = await CourseService.getAvailableWeeks();
    final allTodosRaw = await StorageService.getTodos(widget.username);

    _allTodos = allTodosRaw.where((t) => !t.isDeleted).toList();

    final allLogsRaw = await StorageService.getTimeLogs(widget.username);
    _allTimeLogs = allLogsRaw.where((l) => !l.isDeleted).toList();
    _allPomodoroRecords = await PomodoroService.getRecords();
    _pomodoroTags = await PomodoroService.getTags();

    // 加载所有课程供月视图使用
    _allCourses = await CourseService.getAllCourses();

    // 🚀 核心改进：优先从设置中读取开学日期，不要通过课程反推（课程周次索引在不同解析器间可能有 0/1 差异）
    DateTime? semStart = await StorageService.getSemesterStart();
    if (semStart != null) {
      _semesterMonday = semStart.subtract(Duration(days: semStart.weekday - 1));
    } else {
      // 没有任何设置时，尝试回退：
      final allCourses = await CourseService.getAllCourses();
      if (allCourses.isNotEmpty) {
        allCourses.sort((a, b) => a.weekIndex.compareTo(b.weekIndex));
        final firstCourse = allCourses.first;
        if (firstCourse.date.isNotEmpty) {
          DateTime firstCourseDate = DateFormat('yyyy-MM-dd').parse(firstCourse.date);
          _semesterMonday = firstCourseDate.subtract(Duration(days: firstCourse.weekday - 1))
              .subtract(Duration(days: (firstCourse.weekIndex > 0 ? firstCourse.weekIndex : 0) * 7));
        }
      }
    }

    if (_semesterMonday == null) {
      DateTime now = DateTime.now();
      _semesterMonday = now.subtract(Duration(days: now.weekday - 1));
    }

    // 计算当前周
    DateTime now = DateTime.now();
    int daysOffset = now.difference(_semesterMonday!).inDays;
    _currentWeek = (daysOffset ~/ 7) + 1;
    if (_currentWeek < 1) _currentWeek = 1;

    if (weeks.isNotEmpty) {
      _availableWeeks = weeks;
      _weekCourses = await CourseService.getCoursesByWeek(_currentWeek);
    } else {
      _availableWeeks = List.generate(20, (index) => index + 1);
      _weekCourses = [];
    }

    _updateWeekTodos();
    _updateWeekTimeLogsAndPomodoros();
    
    // 🚀 性能优化：优先渲染周视图，将耗时的月视图全量分组逻辑推迟到下一帧
    setState(() => _isLoading = false);
    
    Future.microtask(() {
      if (mounted) {
        _groupDataForMonthView();
        setState(() {}); // 更新月视图数据
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _courseExpandCtrl.forward();
    });
  }

  // --- 🚀 性能优化: 预先按日期分组数据 (避免在动画期间重复计算) ---
  Map<String, List<CourseItem>> _monthCourseMap = {};
  Map<String, List<TodoItem>> _monthTodoMap = {};
  Map<String, List<TodoItem>> _monthCrossDayTodoMap = {};
  Map<String, List<TimeLogItem>> _monthLogMap = {};
  Map<String, List<PomodoroRecord>> _monthPomMap = {};

  void _groupDataForMonthView() {
    _monthCourseMap = {};
    for (var c in _allCourses) {
      _monthCourseMap.putIfAbsent(c.date, () => []).add(c);
    }

    _monthTodoMap = {};
    _monthCrossDayTodoMap = {};
    for (var t in _allTodos) {
      DateTime tStart = DateTime.fromMillisecondsSinceEpoch(t.createdDate ?? t.createdAt, isUtc: true).toLocal();
      DateTime tEnd = t.dueDate ?? tStart.add(const Duration(hours: 1));
      bool isAllDay = t.dueDate != null && tStart.hour == 0 && tStart.minute == 0 && t.dueDate!.hour == 23 && t.dueDate!.minute == 59;
      bool isAcross = !(tStart.year == tEnd.year && tStart.month == tEnd.month && tStart.day == tEnd.day);
      DateTime cursor = DateTime(tStart.year, tStart.month, tStart.day);
      DateTime endCursor = DateTime(tEnd.year, tEnd.month, tEnd.day);
      while (!cursor.isAfter(endCursor)) {
        String dStr = DateFormat('yyyy-MM-dd').format(cursor);
        if (isAllDay || isAcross) {
          _monthCrossDayTodoMap.putIfAbsent(dStr, () => []).add(t);
        } else {
          _monthTodoMap.putIfAbsent(dStr, () => []).add(t);
        }
        cursor = cursor.add(const Duration(days: 1));
      }
    }

    _monthLogMap = {};
    for (var l in _allTimeLogs) {
      DateTime lStart = DateTime.fromMillisecondsSinceEpoch(l.startTime, isUtc: true).toLocal();
      DateTime lEnd = DateTime.fromMillisecondsSinceEpoch(l.endTime, isUtc: true).toLocal();
      DateTime cursor = DateTime(lStart.year, lStart.month, lStart.day);
      DateTime endCursor = DateTime(lEnd.year, lEnd.month, lEnd.day);
      while (!cursor.isAfter(endCursor)) {
        String dStr = DateFormat('yyyy-MM-dd').format(cursor);
        _monthLogMap.putIfAbsent(dStr, () => []).add(l);
        cursor = cursor.add(const Duration(days: 1));
      }
    }

    _monthPomMap = {};
    for (var p in _allPomodoroRecords) {
      if (p.startTime == 0) continue;
      DateTime pStart = DateTime.fromMillisecondsSinceEpoch(p.startTime, isUtc: true).toLocal();
      int pEndMs = p.endTime ?? (p.startTime + p.effectiveDuration * 1000);
      DateTime pEnd = DateTime.fromMillisecondsSinceEpoch(pEndMs, isUtc: true).toLocal();
      DateTime cursor = DateTime(pStart.year, pStart.month, pStart.day);
      DateTime endCursor = DateTime(pEnd.year, pEnd.month, pEnd.day);
      while (!cursor.isAfter(endCursor)) {
        String dStr = DateFormat('yyyy-MM-dd').format(cursor);
        _monthPomMap.putIfAbsent(dStr, () => []).add(p);
        cursor = cursor.add(const Duration(days: 1));
      }
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

  void _updateWeekTimeLogsAndPomodoros() {
    _timeLogsPerDay = {1: [], 2: [], 3: [], 4: [], 5: [], 6: [], 7: []};
    _pomodorosPerDay = {1: [], 2: [], 3: [], 4: [], 5: [], 6: [], 7: []};

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
          _pomodorosPerDay[i]!.add(record);
        }
      }
    }
  }


  void _changeWeek(int delta) {
    if (_currentWeek + delta >= 1) {
      _isNextSlide = delta > 0;
      _jumpToWeek(_currentWeek + delta);
    }
  }

  void _jumpToWeek(int newWeek) {
    setState(() {
      _currentWeek = newWeek;
      _isLoading = true;
    });
    CourseService.getCoursesByWeek(newWeek).then((courses) {
      setState(() {
        _weekCourses = courses;
        _updateWeekTodos();
        _updateWeekTimeLogsAndPomodoros();
        _isLoading = false;
      });
    });
  }

  void _toggleView(bool isMonth) {
    if (_isMonthView == isMonth) return;
    setState(() {
      _isMonthView = isMonth;
      _updateWeekTodos();
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
    if (_isMonthView) {
      return DateFormat('yyyy年M月').format(_selectedMonth);
    }
    if (_semesterMonday == null) return '第 $_currentWeek 周';
    DateTime monday =
        _semesterMonday!.add(Duration(days: (_currentWeek - 1) * 7));
    DateTime sunday = monday.add(const Duration(days: 6));

    int maxWeek = _availableWeeks.isNotEmpty ? _availableWeeks.last : 20;

    if (_currentWeek >= 1 && _currentWeek <= maxWeek) {
      return '第 $_currentWeek 周';
    } else {
      return '${DateFormat('M/d').format(monday)}-${DateFormat('M/d').format(sunday)}';
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
    final String weekdayStr = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'][day.weekday - 1];
    
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
    
    if (_activeDataViews.contains('pomodoros')) {
      items.addAll(_monthPomMap[dStr] ?? []);
    }

    items.sort((a, b) {
      int getPriority(dynamic item) {
        if (item is CourseItem) return 0;
        if (item is TodoItem) return 1;
        if (item is TimeLogItem) return 2;
        if (item is PomodoroRecord) return 3;
        return 4;
      }
      return getPriority(a).compareTo(getPriority(b));
    });

    return Container(
      width: double.infinity,
      color: isDark ? Colors.black.withOpacity(0.1) : Colors.grey[50],
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
                            size: 64, color: isDark ? Colors.white10 : Colors.black12),
                        const SizedBox(height: 16),
                        Text('该日无安排',
                            style: TextStyle(
                                color: isDark ? Colors.white24 : Colors.black26)),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                    itemCount: items.length,
                    itemBuilder: (context, index) => _buildDetailSidebarItem(context, items[index]),
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
          decoration: BoxDecoration(color: color.withOpacity(0.1), shape: BoxShape.circle),
          child: Icon(Icons.class_, color: color, size: 20),
        ),
        title: Text(item.courseName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
        subtitle: Text('${item.formattedStartTime}-${item.formattedEndTime} @ ${item.roomName}', style: const TextStyle(fontSize: 12)),
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => CourseDetailScreen(course: item))),
      );
    } else if (item is TodoItem) {
      return ListTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: (item.isDone ? Colors.green : Colors.amber).withOpacity(0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(item.isDone ? Icons.check_circle : Icons.task_alt,
              color: item.isDone ? Colors.green : Colors.amber, size: 20),
        ),
        title: Text(item.title, style: TextStyle(
          fontSize: 15,
          decoration: item.isDone ? TextDecoration.lineThrough : null,
          color: item.isDone ? Colors.grey : null,
        )),
        subtitle: Text(item.dueDate != null ? '截止: ${DateFormat('HH:mm').format(item.dueDate!)}' : '无截止时间', style: const TextStyle(fontSize: 12)),
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => TodoDetailScreen(todo: item))),
      );
    } else if (item is TimeLogItem) {
      const color = Colors.blue;
      return ListTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(color: color.withOpacity(0.1), shape: BoxShape.circle),
          child: const Icon(Icons.edit_calendar, color: color, size: 20),
        ),
        title: Text(item.title.isNotEmpty ? item.title : '时间日志', style: const TextStyle(fontSize: 15)),
        subtitle: Text('${DateFormat('HH:mm').format(DateTime.fromMillisecondsSinceEpoch(item.startTime, isUtc: true).toLocal())} - ${DateFormat('HH:mm').format(DateTime.fromMillisecondsSinceEpoch(item.endTime, isUtc: true).toLocal())}', style: const TextStyle(fontSize: 12)),
      );
    } else if (item is PomodoroRecord) {
      const color = Colors.redAccent;
      return ListTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(color: color.withOpacity(0.1), shape: BoxShape.circle),
          child: const Icon(Icons.timer, color: color, size: 20),
        ),
        title: const Text('番茄专注', style: TextStyle(fontSize: 15)),
        subtitle: Text('时长: ${item.effectiveDuration ~/ 60} 分钟', style: const TextStyle(fontSize: 12)),
      );
    }
    return const SizedBox.shrink();
  }

  Widget _buildCheckableMenuItem(String key, String label) {
    bool isSelected = _activeDataViews.contains(key);
    return MenuItemButton(
      closeOnActivate: false,
      onPressed: () {
        setState(() {
          if (isSelected) {
            if (_activeDataViews.length > 1) {
              _activeDataViews.remove(key);
            }
          } else {
            _activeDataViews.add(key);
          }
        });
      },
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isSelected ? Icons.check_box : Icons.check_box_outline_blank,
            size: 20,
            color: isSelected
                ? Theme.of(context).colorScheme.primary
                : Colors.grey,
          ),
          const SizedBox(width: 8),
          Text(label),
        ],
      ),
    );
  }

  DateTime? _getMondayOfCurrentWeek() {
    if (_semesterMonday != null) {
      return _semesterMonday!.add(Duration(days: (_currentWeek - 1) * 7));
    }
    return null;
  }

  double _timeToY(int hour, int minute, double minuteHeight) {
    if (hour < startHour) return 0;
    if (hour > endHour) return (endHour - startHour) * 60 * minuteHeight;
    return ((hour - startHour) * 60 + minute) * minuteHeight;
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
                                  subtitle: Text(
                                      "开始: ${DateFormat('MM-dd HH:mm').format(DateTime.fromMillisecondsSinceEpoch(todo.createdDate ?? todo.createdAt, isUtc: true).toLocal())}\n截止: ${todo.dueDate != null ? DateFormat('MM-dd HH:mm').format(todo.dueDate!) : '无'}"),
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
    if (monday == null || !_activeDataViews.contains('todos'))
      return const SizedBox.shrink();

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
                      ? Colors.green.withOpacity(0.5)
                      : Colors.amber.shade500.withOpacity(0.85),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  text,
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.white,
                    decoration: allDone ? TextDecoration.lineThrough : null,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          );
        }),
      ),
    );
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

  Widget _buildGrid(double cellWidth, double minuteHeight) {
    List<Widget> children = [];
    bool isDark = Theme.of(context).brightness == Brightness.dark;
    Color lineColor = isDark ? Colors.white10 : Colors.black12;
    Color textColor = isDark ? Colors.white70 : Colors.black87;

    for (int hour = startHour; hour <= endHour; hour++) {
      double y = _timeToY(hour, 0, minuteHeight);

      children.add(Positioned(
        top: y,
        left: timeColumnWidth,
        right: 0,
        height: 1,
        child: Container(color: lineColor),
      ));

      if (hour < endHour) {
        children.add(Positioned(
          top: y,
          left: 0,
          width: timeColumnWidth,
          height: 60 * minuteHeight,
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
        for (var todo in _intraDayTodosPerDay[weekday]!) {
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
              ? Colors.green.withOpacity(0.5)
              : Colors.amber.shade500.withOpacity(0.85);
          final todoCardKey = _getTodoCardKey(todo.id);
          final todoIndex = _intraDayTodosPerDay.values
              .expand((e) => e)
              .toList()
              .indexOf(todo);

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
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
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
                                    maxLines: height < 30 ? 1 : 2,
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

          Color logColor = const Color(0xFF3B82F6).withOpacity(0.7);
          String logTitle = log.title.isNotEmpty ? log.title : '时间日志';
          if (log.tagUuids.isNotEmpty) {
            final tag = _pomodoroTags.cast<PomodoroTag?>().firstWhere(
                (t) => log.tagUuids.contains(t?.uuid),
                orElse: () => null);
            if (tag != null) {
              logColor = _hexToColor(tag.color).withOpacity(0.7);
              if (logTitle == '时间日志') logTitle = tag.name;
            }
          }

          final logCardKey = _getTimeLogCardKey(log.id);
          final logIndex =
              _timeLogsPerDay.values.expand((e) => e).toList().indexOf(log);

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
                          color: logColor.withOpacity(1.0), width: 0.5)),
                  child: height < 18
                      ? const Icon(Icons.edit_calendar,
                          size: 8, color: Colors.white)
                      : Column(
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
                                    maxLines: height < 25 ? 1 : 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                            if (height > 22)
                              Text(
                                '${start.hour.toString().padLeft(2, '0')}:${start.minute.toString().padLeft(2, '0')}-${end.hour.toString().padLeft(2, '0')}:${end.minute.toString().padLeft(2, '0')}',
                                style: TextStyle(
                                    color: Colors.white.withOpacity(0.8),
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

          Color pomColor = Colors.redAccent.withOpacity(0.6);
          String pomTitle = '专注';
          if (record.tagUuids.isNotEmpty) {
            final tag = _pomodoroTags.cast<PomodoroTag?>().firstWhere(
                (t) => record.tagUuids.contains(t?.uuid),
                orElse: () => null);
            if (tag != null) {
              pomColor = _hexToColor(tag.color).withOpacity(0.6);
              pomTitle = tag.name;
            }
          }

          final pomCardKey = _getPomodoroCardKey(record.uuid);
          final pomIndex =
              _pomodorosPerDay.values.expand((e) => e).toList().indexOf(record);

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
                          color: pomColor.withOpacity(1.0), width: 0.5)),
                  child: height < 18
                      ? const Icon(Icons.local_fire_department,
                          size: 8, color: Colors.white)
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Padding(
                                  padding: const EdgeInsets.only(top: 1.0),
                                  child: const Icon(Icons.local_fire_department,
                                      size: 8, color: Colors.white),
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
                                    maxLines: height < 25 ? 1 : 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                            if (height > 22)
                              Text(
                                '${record.effectiveDuration ~/ 60}min',
                                style: TextStyle(
                                    color: Colors.white.withOpacity(0.85),
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
                      sourceColor: bgColor.withOpacity(0.95),
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
                    color: bgColor.withOpacity(0.95),
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
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (height > 30) ...[
                      const SizedBox(height: 2),
                      Text(
                        course.roomName,
                        style: TextStyle(
                            color: Colors.white.withOpacity(0.85),
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
                      .withOpacity(0.3 + 0.2 * _pulseAnimation.value),
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
                    color: Colors.redAccent.withOpacity(_pulseAnimation.value),
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

    List<TodoItem> todayAllDay = _allTodos.where((todo) {
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

      DateTime todayStart = DateTime(now.year, now.month, now.day);
      DateTime todayEnd =
          todayStart.add(const Duration(hours: 23, minutes: 59, seconds: 59));

      return start.isBefore(todayEnd) && end.isAfter(todayStart);
    }).toList();

    // 排序：未完成优先
    todayAllDay.sort((a, b) {
      if (a.isDone == b.isDone) return 0;
      return a.isDone ? 1 : -1;
    });

    // 🚀 平板适配：如果是在月视图且选中了日期，展示该日的详情
    if (_isMonthView && _selectedMonthDay != null) {
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
                                      ? Colors.green.withOpacity(0.1)
                                      : Colors.green.withOpacity(0.05))
                                  : (isDark
                                      ? Colors.amber.withOpacity(0.1)
                                      : Colors.amber.withOpacity(0.05)),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: todo.isDone
                                    ? Colors.green.withOpacity(0.3)
                                    : Colors.amber.withOpacity(0.3),
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
                                  child: Text(
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
    double timeColumnWidth = 50.0;
    int startHour = 8;
    int endHour = 22;

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
              onPressed: () => _isMonthView ? _changeMonth(-1) : _changeWeek(-1),
            ),
            const SizedBox(width: 4),
            GestureDetector(
              onTap: _isMonthView ? null : _showWeekJumpDialog,
              child: Text(
                _getWeekLabel(),
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(width: 4),
            IconButton(
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              icon: const Icon(Icons.arrow_forward_ios, size: 13),
              onPressed: () => _isMonthView ? _changeMonth(1) : _changeWeek(1),
            ),
          ],
        ),
        centerTitle: false,
        titleSpacing: 0,
        actions: [
          IconButton(
            visualDensity: const VisualDensity(horizontal: -2),
            icon: Icon(_isMonthView ? Icons.view_week : Icons.calendar_month, size: 20),
            tooltip: _isMonthView ? '切换到周视图' : '切换到月视图',
            onPressed: () => _toggleView(!_isMonthView),
          ),
          IconButton(
            visualDensity: const VisualDensity(horizontal: -2),
            icon: const Icon(Icons.edit_calendar, size: 20),
            tooltip: '记录时间日志',
            onPressed: () async {
              final result = await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => TimeLogScreen(username: widget.username),
                ),
              );
              if (result == true) {
                _loadData();
              }
            },
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.filter_list, size: 20),
            tooltip: '筛选显示内容',
            onSelected: (value) {
              setState(() {
                if (_activeDataViews.contains(value)) {
                  _activeDataViews.remove(value);
                } else {
                  _activeDataViews.add(value);
                }
                if (value == 'todos' || value == 'hideCrossDay') {
                  _updateWeekTodos();
                }
              });
            },
            itemBuilder: (context) {
              return [
                PopupMenuItem(
                  value: 'courses',
                  child: Row(
                    children: [
                      Icon(Icons.check,
                          size: 16,
                          color: _activeDataViews.contains('courses')
                              ? Colors.blue
                              : Colors.transparent),
                      const SizedBox(width: 8),
                      const Text('课表'),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'todos',
                  child: Row(
                    children: [
                      Icon(Icons.check,
                          size: 16,
                          color: _activeDataViews.contains('todos')
                              ? Colors.blue
                              : Colors.transparent),
                      const SizedBox(width: 8),
                      const Text('待办'),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'timeLogs',
                  child: Row(
                    children: [
                      Icon(Icons.check,
                          size: 16,
                          color: _activeDataViews.contains('timeLogs')
                              ? Colors.blue
                              : Colors.transparent),
                      const SizedBox(width: 8),
                      const Text('时间日志'),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'pomodoros',
                  child: Row(
                    children: [
                      Icon(Icons.check,
                          size: 16,
                          color: _activeDataViews.contains('pomodoros')
                              ? Colors.blue
                              : Colors.transparent),
                      const SizedBox(width: 8),
                      const Text('番茄钟'),
                    ],
                  ),
                ),
                const PopupMenuDivider(),
                PopupMenuItem(
                  value: 'hideCrossDay',
                  child: Row(
                    children: [
                      Icon(Icons.check,
                          size: 16,
                          color: _activeDataViews.contains('hideCrossDay')
                              ? Colors.blue
                              : Colors.transparent),
                      const SizedBox(width: 8),
                      const Text('隐藏跨天待办'),
                    ],
                  ),
                ),
              ];
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
                        onScaleStart: (details) {
                          _baseScale = _currentScale;
                        },
                        onScaleUpdate: (details) {
                           if (details.scale < 0.8 && !_isMonthView) {
                            _toggleView(true);
                            HapticFeedback.mediumImpact();
                          } else if (details.scale > 1.2 && _isMonthView) {
                            _toggleView(false);
                            HapticFeedback.mediumImpact();
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
                          
                          if (_dragOffset.abs() > threshold || details.primaryVelocity!.abs() > 300) {
                            if (_dragOffset > 0 || (details.primaryVelocity ?? 0) > 300) {
                              // 向右滑动 -> 上一个
                              if (_isMonthView) _changeMonth(-1); else _changeWeek(-1);
                            } else {
                              // 向左滑动 -> 下一个
                              if (_isMonthView) _changeMonth(1); else _changeWeek(1);
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
                            if (!_isMonthView) ...[
                              _buildHeader(_getMondayOfCurrentWeek()),
                              _buildAllDayHeaderRow(_getMondayOfCurrentWeek()),
                              Divider(
                                  height: 1,
                                  thickness: 0.5,
                                  color: isDark ? Colors.white10 : Colors.black12),
                            ],
                            Expanded(
                              child: TweenAnimationBuilder<double>(
                                duration: const Duration(milliseconds: 600),
                                curve: Curves.easeInOutQuart,
                                tween: Tween<double>(
                                  begin: _isMonthView ? 1.0 : 0.0,
                                  end: _isMonthView ? 1.0 : 0.0,
                                ),
                                builder: (context, t, child) {
                                  return ClipRect(
                                    child: Stack(
                                      children: [
                                      // --- 月视图 ---
                                      IgnorePointer(
                                        ignoring: t < 0.5,
                                        child: Opacity(
                                          opacity: t.clamp(0.0, 1.0),
                                          child: Transform.scale(
                                            scale: 0.8 + (t * 0.2),
                                            child: AnimatedSwitcher(
                                              duration: const Duration(milliseconds: 400),
                                              transitionBuilder: (child, animation) {
                                                // 结合跟手位移和动画效果
                                                return Transform.translate(
                                                  offset: Offset(_dragOffset * (1.0 - animation.value), 0),
                                                  child: SlideTransition(
                                                    position: Tween<Offset>(
                                                      begin: Offset(_isNextSlide ? 1.0 : -1.0, 0.0),
                                                      end: Offset.zero,
                                                    ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
                                                    child: FadeTransition(opacity: animation, child: child),
                                                  ),
                                                );
                                              },
                                              child: CourseMonthView(
                                                key: ValueKey('MonthView_${_selectedMonth.year}_${_selectedMonth.month}'),
                                                selectedMonth: _selectedMonth,
                                                courseMap: _monthCourseMap,
                                                todoMap: _monthTodoMap,
                                                crossDayTodoMap: _monthCrossDayTodoMap,
                                                logMap: _monthLogMap,
                                                pomMap: _monthPomMap,
                                                pomodoroTags: _pomodoroTags,
                                                activeDataViews: _activeDataViews,
                                                onMonthChanged: (m) {
                                                  setState(() => _selectedMonth = m);
                                                  _groupDataForMonthView(); 
                                                },
                                                onDayTapped: (d) {
                                                  setState(() => _selectedMonthDay = d);
                                                },
                                              ),
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
                                      offset: Offset(_dragOffset * (1.0 - animation.value), 0),
                                      child: SlideTransition(
                                        position: Tween<Offset>(
                                          begin: Offset(_isNextSlide ? 1.0 : -1.0, 0.0),
                                          end: Offset.zero,
                                        ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
                                        child: FadeTransition(opacity: animation, child: child),
                                      ),
                                    );
                                  },
                                  child: RepaintBoundary(
                                    key: ValueKey('WeekView_$_currentWeek'),
                                    child: LayoutBuilder(
                                      builder: (context, innerConstraints) {
                                        double cellWidth = (innerConstraints.maxWidth - timeColumnWidth) / 7;
                                        double minuteHeight = innerConstraints.maxHeight / ((endHour - startHour) * 60);
                                        return _buildGrid(cellWidth, minuteHeight);
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
                        child: _buildTodaySidebar(),
                      ),
                  ],
                );
              },
            ),
    );
  }

  Widget _buildSkeleton() {
    bool isDark = Theme.of(context).brightness == Brightness.dark;
    Color baseColor = isDark ? Colors.white10 : Colors.black.withOpacity(0.05);

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

  Widget _buildSkeletonBox(double cellWidth, double top, double height, int dayIndex, Color color) {
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
}

// --- Detail Screens ---

class CourseDetailScreen extends StatelessWidget {
  final CourseItem course;
  const CourseDetailScreen({Key? key, required this.course}) : super(key: key);

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
                    : (course.lessonType == 'THEORY' ? '理论课' : course.lessonType!)),
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

class TodoDetailScreen extends StatelessWidget {
  final TodoItem todo;
  const TodoDetailScreen({Key? key, required this.todo}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    DateTime createdAt = DateTime.fromMillisecondsSinceEpoch(
            todo.createdDate ?? todo.createdAt,
            isUtc: true)
        .toLocal();
    bool isAllDay = todo.dueDate != null &&
        createdAt.hour == 0 &&
        createdAt.minute == 0 &&
        todo.dueDate!.hour == 23 &&
        todo.dueDate!.minute == 59;

    String startTimeStr = isAllDay
        ? DateFormat('yyyy-MM-dd (全天)').format(createdAt)
        : DateFormat('yyyy-MM-dd HH:mm').format(createdAt);

    String endTimeStr = todo.dueDate == null
        ? '无截止时间'
        : (isAllDay
            ? DateFormat('yyyy-MM-dd (全天)').format(todo.dueDate!)
            : DateFormat('yyyy-MM-dd HH:mm').format(todo.dueDate!));

    double progress = 0.0;
    DateTime now = DateTime.now();
    DateTime start = createdAt;
    DateTime end = todo.dueDate ??
        DateTime(start.year, start.month, start.day, 23, 59, 59);

    if (todo.isDone) {
      progress = 1.0;
    } else {
      int totalMinutes = end.difference(start).inMinutes;
      if (totalMinutes <= 0) totalMinutes = 1;

      if (now.isBefore(start)) {
        progress = 0.0;
      } else {
        int passedMinutes = now.difference(start).inMinutes;
        progress = (passedMinutes / totalMinutes).clamp(0.0, 1.0);
      }
    }

    return Scaffold(
      appBar: AppBar(title: const Text('待办详情')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Icon(todo.isDone ? Icons.check_circle : Icons.task_alt,
              size: 80, color: todo.isDone ? Colors.green : Colors.amber),
          const SizedBox(height: 16),
          Text(todo.title,
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  decoration: todo.isDone ? TextDecoration.lineThrough : null,
                  color: todo.isDone ? Colors.grey : null)),
          const SizedBox(height: 32),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text("时间进度",
                      style: TextStyle(color: Colors.grey, fontSize: 14)),
                  Text("${(progress * 100).toInt()}%",
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.primary,
                          fontWeight: FontWeight.bold)),
                ],
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 10,
                  backgroundColor:
                      Theme.of(context).colorScheme.onSurface.withOpacity(0.1),
                  valueColor: AlwaysStoppedAnimation<Color>(todo.isDone
                      ? Colors.green
                      : Theme.of(context).colorScheme.primary),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          _buildDetailRow(Icons.flag, '状态', todo.isDone ? '已完成' : '进行中'),
          const Divider(),
          _buildDetailRow(Icons.play_circle_outline, '开始时间', startTimeStr),
          const Divider(),
          _buildDetailRow(Icons.stop_circle_outlined, '截止时间', endTimeStr),
          const Divider(),
          _buildDetailRow(
              Icons.update,
              '最近更新',
              DateFormat('yyyy-MM-dd HH:mm').format(
                  DateTime.fromMillisecondsSinceEpoch(todo.updatedAt,
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

class TimeLogDetailScreen extends StatelessWidget {
  final TimeLogItem log;
  final List<PomodoroTag> tags;
  const TimeLogDetailScreen({Key? key, required this.log, required this.tags})
      : super(key: key);

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
      {Key? key, required this.record, required this.tags})
      : super(key: key);

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
