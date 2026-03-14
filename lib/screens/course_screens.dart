import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/course_service.dart';
import '../models.dart';
import '../storage_service.dart';
import 'time_log_screen.dart'; // 🚀 1. 引入时间日志页面

// --- 二级界面：按周查看课表 (全屏自适应压缩视图) ---
class WeeklyCourseScreen extends StatefulWidget {
  final String username;
  const WeeklyCourseScreen({Key? key, required this.username}) : super(key: key);

  @override
  State<WeeklyCourseScreen> createState() => _WeeklyCourseScreenState();
}

class _WeeklyCourseScreenState extends State<WeeklyCourseScreen> {
  int _currentWeek = 1;
  List<int> _availableWeeks = [];
  List<CourseItem> _weekCourses = [];

  List<TodoItem> _allTodos = [];

  // 拆分：全天/跨天待办 和 日内局部待办
  Map<int, List<TodoItem>> _allDayTodosPerDay = {};
  Map<int, List<TodoItem>> _intraDayTodosPerDay = {};

  bool _isLoading = true;
  DateTime? _semesterMonday;
  int _viewMode = 0; // 0: 混合查看, 1: 只看课表, 2: 只看待办

  // 时间轴参数配置
  final double timeColumnWidth = 45.0; // 稍微拓宽左侧，适应更大的时间字体
  final int startHour = 7;             // 轴起点：早上 7:00
  final int endHour = 23;              // 轴终点：晚上 23:00

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final weeks = await CourseService.getAvailableWeeks();
    final allTodosRaw = await StorageService.getTodos(widget.username);

    // 🚀 核心：全局列表中剔除回收站里逻辑删除的待办！
    _allTodos = allTodosRaw.where((t) => !t.isDeleted).toList();

    if (weeks.isNotEmpty) {
      _availableWeeks = weeks;

      // 解析出学期的第一周星期一的日期
      final allCourses = await CourseService.getAllCourses();
      if (allCourses.isNotEmpty) {
        allCourses.sort((a, b) => a.weekIndex.compareTo(b.weekIndex));
        final firstCourse = allCourses.first;
        if (firstCourse.date.isNotEmpty) {
          DateTime firstCourseDate = DateFormat('yyyy-MM-dd').parse(firstCourse.date);
          DateTime firstMonday = firstCourseDate.subtract(Duration(days: firstCourse.weekday - 1));
          _semesterMonday = firstMonday.subtract(Duration(days: (firstCourse.weekIndex - 1) * 7));
        } else {
          _semesterMonday = DateTime.now().subtract(Duration(days: DateTime.now().weekday - 1));
        }

        // 自动定位到当前自然周
        DateTime now = DateTime.now();
        int daysDiff = now.difference(_semesterMonday!).inDays;
        int currentRealWeek = (daysDiff ~/ 7) + 1;
        if (_availableWeeks.contains(currentRealWeek)) {
          _currentWeek = currentRealWeek;
        } else {
          _currentWeek = _availableWeeks.first;
        }
      }

      _weekCourses = await CourseService.getCoursesByWeek(_currentWeek);
      _updateWeekTodos();
    } else {
      // 兼容无课表情况
      DateTime? semStart = await StorageService.getSemesterStart();
      DateTime now = DateTime.now();
      if (semStart != null) {
        _semesterMonday = semStart.subtract(Duration(days: semStart.weekday - 1));
        int daysDiff = now.difference(_semesterMonday!).inDays;
        _currentWeek = (daysDiff ~/ 7) + 1;
        if (_currentWeek < 1) _currentWeek = 1;
      } else {
        _semesterMonday = now.subtract(Duration(days: now.weekday - 1));
        _currentWeek = 1;
      }
      _availableWeeks = List.generate(20, (index) => index + 1);
      _weekCourses = [];
      _updateWeekTodos();
    }

    setState(() => _isLoading = false);
  }

  void _updateWeekTodos() {
    _allDayTodosPerDay = {1: [], 2: [], 3: [], 4: [], 5: [], 6: [], 7: []};
    _intraDayTodosPerDay = {1: [], 2: [], 3: [], 4: [], 5: [], 6: [], 7: []};

    if (_semesterMonday == null) return;

    DateTime currentWeekMonday = _semesterMonday!.add(Duration(days: (_currentWeek - 1) * 7));
    DateTime currentWeekMondayStart = DateTime(currentWeekMonday.year, currentWeekMonday.month, currentWeekMonday.day);

    for (var todo in _allTodos) {
      // 🚀 修正：优先使用 createdDate，兼容旧数据 fallback 到 createdAt
      DateTime start = DateTime.fromMillisecondsSinceEpoch(todo.createdDate ?? todo.createdAt, isUtc: true).toLocal();
      DateTime end = todo.dueDate ?? start.add(const Duration(hours: 1));

      bool isAllDayFlag = todo.dueDate != null &&
          start.hour == 0 && start.minute == 0 &&
          todo.dueDate!.hour == 23 && todo.dueDate!.minute == 59;
      bool isCrossDay = !(start.year == end.year && start.month == end.month && start.day == end.day);
      bool treatAsAllDay = isAllDayFlag || isCrossDay;

      for (int i = 1; i <= 7; i++) {
        DateTime dayStart = currentWeekMondayStart.add(Duration(days: i - 1));
        DateTime dayEnd = dayStart.add(const Duration(hours: 23, minutes: 59, seconds: 59));

        if (start.isBefore(dayEnd) && end.isAfter(dayStart)) {
          if (treatAsAllDay) {
            _allDayTodosPerDay[i]!.add(todo);
          } else {
            _intraDayTodosPerDay[i]!.add(todo);
          }
        }
      }
    }
  }

  void _changeWeek(int delta) {
    int newWeek = _currentWeek + delta;
    setState(() {
      _currentWeek = newWeek;
      _isLoading = true;
    });
    CourseService.getCoursesByWeek(newWeek).then((courses) {
      setState(() {
        _weekCourses = courses;
        _updateWeekTodos();
        _isLoading = false;
      });
    });
  }

  // 周标签：学期内显示周数，学期外显示日期范围
  String _getWeekLabel() {
    if (_semesterMonday == null) return '第 $_currentWeek 周';
    DateTime monday = _semesterMonday!.add(Duration(days: (_currentWeek - 1) * 7));
    DateTime sunday = monday.add(const Duration(days: 6));

    int maxWeek = _availableWeeks.isNotEmpty ? _availableWeeks.last : 20;

    // 学期范围内显示周数，否则显示日期范围
    if (_currentWeek >= 1 && _currentWeek <= maxWeek) {
      return '第 $_currentWeek 周';
    } else {
      return '${DateFormat('M/d').format(monday)}-${DateFormat('M/d').format(sunday)}';
    }
  }

  // 跳转弹窗
  void _showWeekJumpDialog() {
    final TextEditingController controller = TextEditingController(text: '$_currentWeek');
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
            // 快捷跳转按钮
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
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
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

  void _jumpToWeek(int week) {
    setState(() {
      _currentWeek = week;
      _isLoading = true;
    });
    CourseService.getCoursesByWeek(week).then((courses) {
      setState(() {
        _weekCourses = courses;
        _updateWeekTodos();
        _isLoading = false;
      });
    });
  }

  void _jumpToCurrentWeek() {
    if (_semesterMonday == null) return;
    DateTime now = DateTime.now();
    int daysDiff = now.difference(_semesterMonday!).inDays;
    int week = (daysDiff ~/ 7) + 1;
    if (week < 1) week = 1;
    _jumpToWeek(week);
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

  void _showAllDayTodos(BuildContext context, List<TodoItem> todos, String dateStr) {
    showModalBottomSheet(
        context: context,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
        builder: (ctx) {
          return SafeArea(
            child: Container(
                padding: const EdgeInsets.all(16),
                constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.5),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Center(
                        child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2))),
                      ),
                      const SizedBox(height: 16),
                      Text("$dateStr 全天/跨天待办", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 16),
                      Expanded(
                          child: ListView.builder(
                              itemCount: todos.length,
                              itemBuilder: (context, index) {
                                final todo = todos[index];
                                return ListTile(
                                  leading: Icon(todo.isDone ? Icons.check_circle : Icons.task_alt, color: todo.isDone ? Colors.green : Colors.amber),
                                  title: Text(todo.title, style: TextStyle(decoration: todo.isDone ? TextDecoration.lineThrough : null)),
                                  // 🚀 修正：优先使用 createdDate，兼容旧数据 fallback 到 createdAt
                                  subtitle: Text("开始: ${DateFormat('MM-dd HH:mm').format(DateTime.fromMillisecondsSinceEpoch(todo.createdDate ?? todo.createdAt, isUtc: true).toLocal())}\n截止: ${todo.dueDate != null ? DateFormat('MM-dd HH:mm').format(todo.dueDate!) : '无'}"),
                                  onTap: () {
                                    Navigator.pop(ctx);
                                    Navigator.push(context, MaterialPageRoute(builder: (_) => TodoDetailScreen(todo: todo)));
                                  },
                                );
                              }
                          )
                      )
                    ]
                )
            ),
          );
        }
    );
  }

  Widget _buildAllDayHeaderRow(DateTime? monday) {
    if (monday == null || _viewMode == 1) return const SizedBox.shrink();

    bool hasAnyAllDay = _allDayTodosPerDay.values.any((list) => list.isNotEmpty);
    if (!hasAnyAllDay) return const SizedBox.shrink(); // 无待办直接消失，不占高度

    // 以下只在真正有全天待办时才渲染
    return Container(
      padding: EdgeInsets.only(left: timeColumnWidth, bottom: 2),
      color: Theme.of(context).colorScheme.surface,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: List.generate(7, (index) {
          int weekday = index + 1;
          List<TodoItem> dayTodos = _allDayTodosPerDay[weekday] ?? [];

          if (dayTodos.isEmpty) {
            return const Expanded(child: SizedBox(height: 22)); // 占位保持对齐
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
                    color: isToday ? Colors.blue : (isDark ? Colors.white70 : Colors.black87),
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

      children.add(
          Positioned(
            top: y,
            left: timeColumnWidth,
            right: 0,
            height: 1,
            child: Container(color: lineColor),
          )
      );

      if (hour < endHour) {
        children.add(
            Positioned(
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
                    style: TextStyle(fontSize: 12, color: textColor, fontWeight: FontWeight.w500),
                  ),
                ),
              ),
            )
        );
      }
    }

    for (int i = 0; i <= 7; i++) {
      children.add(
          Positioned(
            top: 0,
            bottom: 0,
            left: timeColumnWidth + i * cellWidth,
            width: 0.5,
            child: Container(color: lineColor),
          )
      );
    }

    if (_viewMode != 1) {
      Map<String, int> collisionMap = {};

      for (int weekday = 1; weekday <= 7; weekday++) {
        for (var todo in _intraDayTodosPerDay[weekday]!) {
          // 🚀 修正：优先使用 createdDate，兼容旧数据 fallback 到 createdAt
          DateTime start = DateTime.fromMillisecondsSinceEpoch(todo.createdDate ?? todo.createdAt, isUtc: true).toLocal();
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

          children.add(
              Positioned(
                top: top,
                left: finalLeft,
                width: finalWidth,
                height: height,
                child: GestureDetector(
                  onTap: () {
                    Navigator.push(context, MaterialPageRoute(builder: (_) => TodoDetailScreen(todo: todo)));
                  },
                  child: Container(
                    clipBehavior: Clip.hardEdge,
                    padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
                    decoration: BoxDecoration(
                        color: todo.isDone ? Colors.green.withOpacity(0.5) : Colors.amber.shade500.withOpacity(0.85),
                        borderRadius: BorderRadius.circular(4),
                        boxShadow: stackIndex > 0 ? [const BoxShadow(color: Colors.black12, blurRadius: 2, offset: Offset(-1, 1))] : null
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(top: 2.0),
                              child: Icon(todo.isDone ? Icons.check_circle : Icons.task_alt, size: 10, color: Colors.white),
                            ),
                            const SizedBox(width: 2),
                            Expanded(
                              child: Text(
                                todo.title,
                                style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    decoration: todo.isDone ? TextDecoration.lineThrough : null,
                                    height: 1.1
                                ),
                                maxLines: height < 25 ? 1 : 3,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              )
          );
        }
      }
    }

    if (_viewMode != 2) {
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

        children.add(
            Positioned(
              top: top + 1,
              left: left + 1,
              width: courseWidth,
              height: height - 2,
              child: GestureDetector(
                onTap: () {
                  Navigator.push(context, MaterialPageRoute(
                    builder: (_) => CourseDetailScreen(course: course),
                  ));
                },
                child: Container(
                  clipBehavior: Clip.hardEdge,
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                      color: bgColor.withOpacity(0.95),
                      borderRadius: BorderRadius.circular(4),
                      boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 1, offset: Offset(0, 1))]
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        course.courseName,
                        style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold, height: 1.15),
                        maxLines: height < 35 ? 1 : 4,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (height > 40) const Spacer(),
                      if (height > 40)
                        Text(
                          course.roomName,
                          style: const TextStyle(color: Colors.white, fontSize: 10, height: 1.1),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),
              ),
            )
        );
      }
    }

    DateTime now = DateTime.now();
    if (now.hour >= startHour && now.hour <= endHour) {
      if (_semesterMonday != null) {
        DateTime currentMonday = _semesterMonday!.add(Duration(days: (_currentWeek - 1) * 7));
        int diffDays = DateTime(now.year, now.month, now.day).difference(currentMonday).inDays;

        if (diffDays >= 0 && diffDays <= 6) {
          double nowY = _timeToY(now.hour, now.minute, minuteHeight);
          double lineLeft = timeColumnWidth + diffDays * cellWidth;

          children.add(
              Positioned(
                top: nowY,
                left: timeColumnWidth,
                width: cellWidth * 7,
                height: 1,
                child: Container(color: Colors.redAccent.withOpacity(0.5)),
              )
          );
          children.add(
              Positioned(
                top: nowY - 2.5,
                left: lineLeft - 2,
                width: 6,
                height: 6,
                child: Container(
                  decoration: const BoxDecoration(
                    color: Colors.redAccent,
                    shape: BoxShape.circle,
                  ),
                ),
              )
          );
        }
      }
    }

    return Stack(children: children);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('课表与待办', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        centerTitle: false,
        actions: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 2. AppBar 里的翻页按钮去掉 null 判断
              IconButton(
                icon: const Icon(Icons.arrow_back_ios, size: 16),
                onPressed: () => _changeWeek(-1), // 去掉 null 判断
              ),
              Text(
                // 学期内显示"第X周"，学期外显示日期范围
                _getWeekLabel(),
                style: const TextStyle(fontSize: 14),
              ),
              IconButton(
                icon: const Icon(Icons.arrow_forward_ios, size: 16),
                onPressed: () => _changeWeek(1),
              ),
            ],
          ),
          const SizedBox(width: 4),
          // 🚀 2. 新增：跳转至“时间日志”的快捷入口
          IconButton(
            icon: const Icon(Icons.edit_calendar, size: 20),
            tooltip: '记录时间日志',
            onPressed: () {
              Navigator.push(context, MaterialPageRoute(
                builder: (_) => TimeLogScreen(username: widget.username),
              ));
            },
          ),
          PopupMenuButton<int>(
            initialValue: _viewMode,
            onSelected: (val) {
              setState(() {
                _viewMode = val;
              });
            },
            itemBuilder: (context) => [
              const PopupMenuItem(value: 0, child: Text("混合查看")),
              const PopupMenuItem(value: 1, child: Text("只看课表")),
              const PopupMenuItem(value: 2, child: Text("只看待办")),
            ],
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                      _viewMode == 1 ? "只看课表" : (_viewMode == 2 ? "只看待办" : "混合查看"),
                      style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.bold)
                  ),
                  Icon(Icons.arrow_drop_down, size: 20, color: Theme.of(context).colorScheme.primary),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
        children: [
          _buildHeader(_getMondayOfCurrentWeek()),
          _buildAllDayHeaderRow(_getMondayOfCurrentWeek()),
          Divider(height: 1, thickness: 0.5, color: Theme.of(context).brightness == Brightness.dark ? Colors.white10 : Colors.black12),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                double cellWidth = (constraints.maxWidth - timeColumnWidth) / 7;
                double minuteHeight = constraints.maxHeight / ((endHour - startHour) * 60);

                return SizedBox(
                  width: constraints.maxWidth,
                  height: constraints.maxHeight,
                  child: _buildGrid(cellWidth, minuteHeight),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// --- 三级界面：课程详情 ---
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
          Text(course.courseName, textAlign: TextAlign.center, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
          const SizedBox(height: 32),
          _buildDetailRow(Icons.person, '授课教师', course.teacherName),
          const Divider(),
          _buildDetailRow(Icons.location_on, '上课地点', course.roomName),
          const Divider(),
          _buildDetailRow(Icons.calendar_today, '日期', '${course.date} (第${course.weekIndex}周 周${course.weekday})'),
          const Divider(),
          _buildDetailRow(Icons.access_time, '时间', '${course.formattedStartTime} - ${course.formattedEndTime}'),
          if (course.lessonType != null && course.lessonType!.isNotEmpty) ...[
            const Divider(),
            // 自动翻译内部可能存在的英文类型
            _buildDetailRow(Icons.category, '类型/备注', course.lessonType! == 'EXPERIMENT' ? '实验课' : (course.lessonType! == 'THEORY' ? '理论课' : course.lessonType!)),
          ]
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

// --- 三级界面：待办详情 ---
class TodoDetailScreen extends StatelessWidget {
  final TodoItem todo;
  const TodoDetailScreen({Key? key, required this.todo}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // 🚀 修正：优先使用 createdDate，兼容旧数据 fallback 到 createdAt
    DateTime createdAt = DateTime.fromMillisecondsSinceEpoch(todo.createdDate ?? todo.createdAt, isUtc: true).toLocal();
    bool isAllDay = todo.dueDate != null &&
        createdAt.hour == 0 && createdAt.minute == 0 &&
        todo.dueDate!.hour == 23 && todo.dueDate!.minute == 59;

    String startTimeStr = isAllDay
        ? DateFormat('yyyy-MM-dd (全天)').format(createdAt)
        : DateFormat('yyyy-MM-dd HH:mm').format(createdAt);

    String endTimeStr = todo.dueDate == null
        ? '无截止时间'
        : (isAllDay
        ? DateFormat('yyyy-MM-dd (全天)').format(todo.dueDate!)
        : DateFormat('yyyy-MM-dd HH:mm').format(todo.dueDate!));

    // 计算进度
    double progress = 0.0;
    DateTime now = DateTime.now();
    DateTime start = createdAt;
    DateTime end = todo.dueDate ?? DateTime(start.year, start.month, start.day, 23, 59, 59);

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
          Icon(todo.isDone ? Icons.check_circle : Icons.task_alt, size: 80, color: todo.isDone ? Colors.green : Colors.amber),
          const SizedBox(height: 16),
          Text(
              todo.title,
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  decoration: todo.isDone ? TextDecoration.lineThrough : null,
                  color: todo.isDone ? Colors.grey : null
              )
          ),
          const SizedBox(height: 32),

          // 进度条渲染
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text("时间进度", style: TextStyle(color: Colors.grey, fontSize: 14)),
                  Text("${(progress * 100).toInt()}%", style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.bold)),
                ],
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 10,
                  backgroundColor: Theme.of(context).colorScheme.onSurface.withOpacity(0.1),
                  valueColor: AlwaysStoppedAnimation<Color>(todo.isDone ? Colors.green : Theme.of(context).colorScheme.primary),
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
          _buildDetailRow(Icons.update, '最近更新', DateFormat('yyyy-MM-dd HH:mm').format(DateTime.fromMillisecondsSinceEpoch(todo.updatedAt, isUtc: true).toLocal())),
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