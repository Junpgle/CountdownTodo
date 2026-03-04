import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/course_service.dart';
import '../models.dart';
import '../storage_service.dart';

// --- 二级界面：按周查看课表 (网格视图) ---
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

  // 网格尺寸常量设置
  final double timeColumnWidth = 45.0; // 左侧时间栏宽度
  final double cellHeight = 65.0;      // 每个节次的高度
  final double breakHeight = 24.0;     // 午休/晚休分割线高度

  // 动态课间休息高度
  double get _shortBreakHeight => _viewMode == 1 ? 0.0 : 15.0;

  // 基础时间系设定：早上 8:00 作为原点(0)
  final int baseHour = 8;
  final int baseMinute = 0;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final weeks = await CourseService.getAvailableWeeks();
    _allTodos = await StorageService.getTodos(widget.username);

    if (weeks.isNotEmpty) {
      _availableWeeks = weeks;

      // 解析出学期的第一周星期一的日期，用于计算任何一周的日历日期
      final allCourses = await CourseService.getAllCourses();
      if (allCourses.isNotEmpty) {
        allCourses.sort((a, b) => a.weekIndex.compareTo(b.weekIndex));
        final firstCourse = allCourses.first;
        DateTime firstCourseDate = DateFormat('yyyy-MM-dd').parse(firstCourse.date);
        DateTime firstMonday = firstCourseDate.subtract(Duration(days: firstCourse.weekday - 1));
        _semesterMonday = firstMonday.subtract(Duration(days: (firstCourse.weekIndex - 1) * 7));

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
      // 兼容无课表情况：尝试获取学期设置或以当前周为第一周，以确保待办能够渲染
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
      _availableWeeks = List.generate(20, (index) => index + 1); // 虚拟生成20周
      _weekCourses = [];
      _updateWeekTodos();
    }

    setState(() => _isLoading = false);
  }

  // 刷新当前周对应的待办列表并分类
  void _updateWeekTodos() {
    _allDayTodosPerDay = {1: [], 2: [], 3: [], 4: [], 5: [], 6: [], 7: []};
    _intraDayTodosPerDay = {1: [], 2: [], 3: [], 4: [], 5: [], 6: [], 7: []};

    if (_semesterMonday == null) return;

    DateTime currentWeekMonday = _semesterMonday!.add(Duration(days: (_currentWeek - 1) * 7));
    DateTime currentWeekMondayStart = DateTime(currentWeekMonday.year, currentWeekMonday.month, currentWeekMonday.day);

    for (var todo in _allTodos) {
      DateTime start = todo.createdAt;
      // 如果没有截止日期，默认算作1小时的局部事件，防止在网格里拉得太长
      DateTime end = todo.dueDate ?? start.add(const Duration(hours: 1));

      // 判断是否是全天事件 或 跨天事件
      bool isAllDayFlag = todo.dueDate != null &&
          start.hour == 0 && start.minute == 0 &&
          todo.dueDate!.hour == 23 && todo.dueDate!.minute == 59;
      bool isCrossDay = !(start.year == end.year && start.month == end.month && start.day == end.day);
      bool treatAsAllDay = isAllDayFlag || isCrossDay;

      for (int i = 1; i <= 7; i++) {
        DateTime dayStart = currentWeekMondayStart.add(Duration(days: i - 1));
        DateTime dayEnd = dayStart.add(const Duration(hours: 23, minutes: 59, seconds: 59));

        // 检查重叠
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
    if (_availableWeeks.contains(newWeek)) {
      setState(() {
        _currentWeek = newWeek;
        _isLoading = true;
      });
      CourseService.getCoursesByWeek(_currentWeek).then((courses) {
        setState(() {
          _weekCourses = courses;
          _updateWeekTodos();
          _isLoading = false;
        });
      });
    }
  }

  DateTime? _getMondayOfCurrentWeek() {
    if (_semesterMonday != null) {
      return _semesterMonday!.add(Duration(days: (_currentWeek - 1) * 7));
    }
    return null;
  }

  String _getPeriodTime(int period) {
    switch (period) {
      case 1: return '08:00\n08:50';
      case 2: return '09:00\n09:50';
      case 3: return '10:10\n11:00';
      case 4: return '11:10\n12:00';
      case 5: return '14:00\n14:50';
      case 6: return '15:00\n15:50';
      case 7: return '16:00\n16:50';
      case 8: return '17:00\n17:50';
      case 9: return '19:00\n19:50';
      case 10: return '20:00\n20:50';
      case 11: return '21:00\n21:50';
      default: return '';
    }
  }

  // === 🚀 核心重构：精准的基于时间的 Y 轴偏移量计算，带动态课间间隙 ===

  double _getYOffsetByTime(int hour, int minute) {
    if (hour < 8) return 0.0;

    // 计算总高度
    double maxPossibleY = 11 * cellHeight + 2 * breakHeight + 8 * _shortBreakHeight;
    if (hour >= 22) return maxPossibleY;

    int totalMinutesFrom8AM = (hour - 8) * 60 + minute;
    double yOffset = 0.0;

    // --- 上午区域 (08:00 - 12:00) : 240 分钟 ---
    // 第1~4节，包含 3 个课间
    if (totalMinutesFrom8AM <= 240) {
      if (totalMinutesFrom8AM <= 50) { // 第1节
        return (totalMinutesFrom8AM / 50) * cellHeight;
      } else if (totalMinutesFrom8AM <= 60) { // 课间1
        return cellHeight + ((totalMinutesFrom8AM - 50) / 10) * _shortBreakHeight;
      } else if (totalMinutesFrom8AM <= 110) { // 第2节
        return cellHeight + _shortBreakHeight + ((totalMinutesFrom8AM - 60) / 50) * cellHeight;
      } else if (totalMinutesFrom8AM <= 130) { // 大课间2 (20分钟)
        return 2 * cellHeight + _shortBreakHeight + ((totalMinutesFrom8AM - 110) / 20) * _shortBreakHeight;
      } else if (totalMinutesFrom8AM <= 180) { // 第3节
        return 2 * cellHeight + 2 * _shortBreakHeight + ((totalMinutesFrom8AM - 130) / 50) * cellHeight;
      } else if (totalMinutesFrom8AM <= 190) { // 课间3
        return 3 * cellHeight + 2 * _shortBreakHeight + ((totalMinutesFrom8AM - 180) / 10) * _shortBreakHeight;
      } else { // 第4节 (190-240)
        return 3 * cellHeight + 3 * _shortBreakHeight + ((totalMinutesFrom8AM - 190) / 50) * cellHeight;
      }
    }

    yOffset = 4 * cellHeight + 3 * _shortBreakHeight;

    // --- 午休区域：12:00 - 14:00 (120分钟) ---
    int minutesAfterNoon = totalMinutesFrom8AM - 240;
    if (minutesAfterNoon <= 120) {
      return yOffset + (minutesAfterNoon / 120) * breakHeight;
    }

    yOffset += breakHeight;

    // --- 下午区域 (14:00 - 17:50) : 230 分钟 ---
    // 第5~8节，包含 3 个课间
    int minutesAfter2PM = totalMinutesFrom8AM - 360;
    if (minutesAfter2PM <= 230) {
      if (minutesAfter2PM <= 50) { // 第5节
        return yOffset + (minutesAfter2PM / 50) * cellHeight;
      } else if (minutesAfter2PM <= 60) { // 课间5
        return yOffset + cellHeight + ((minutesAfter2PM - 50) / 10) * _shortBreakHeight;
      } else if (minutesAfter2PM <= 110) { // 第6节
        return yOffset + cellHeight + _shortBreakHeight + ((minutesAfter2PM - 60) / 50) * cellHeight;
      } else if (minutesAfter2PM <= 120) { // 课间6
        return yOffset + 2 * cellHeight + _shortBreakHeight + ((minutesAfter2PM - 110) / 10) * _shortBreakHeight;
      } else if (minutesAfter2PM <= 170) { // 第7节
        return yOffset + 2 * cellHeight + 2 * _shortBreakHeight + ((minutesAfter2PM - 120) / 50) * cellHeight;
      } else if (minutesAfter2PM <= 180) { // 课间7
        return yOffset + 3 * cellHeight + 2 * _shortBreakHeight + ((minutesAfter2PM - 170) / 10) * _shortBreakHeight;
      } else { // 第8节 (180-230)
        return yOffset + 3 * cellHeight + 3 * _shortBreakHeight + ((minutesAfter2PM - 180) / 50) * cellHeight;
      }
    }

    yOffset += 4 * cellHeight + 3 * _shortBreakHeight;

    // --- 晚休区域：17:50 - 19:00 (70分钟) ---
    int minutesAfterAfternoon = totalMinutesFrom8AM - 590;
    if (minutesAfterAfternoon <= 70) {
      return yOffset + (minutesAfterAfternoon / 70) * breakHeight;
    }

    yOffset += breakHeight;

    // --- 晚上区域 (19:00 - 21:50) : 170 分钟 ---
    // 第9~11节，包含 2 个课间
    int minutesAfter7PM = totalMinutesFrom8AM - 660;
    if (minutesAfter7PM <= 170) {
      if (minutesAfter7PM <= 50) { // 第9节
        return yOffset + (minutesAfter7PM / 50) * cellHeight;
      } else if (minutesAfter7PM <= 60) { // 课间9
        return yOffset + cellHeight + ((minutesAfter7PM - 50) / 10) * _shortBreakHeight;
      } else if (minutesAfter7PM <= 110) { // 第10节
        return yOffset + cellHeight + _shortBreakHeight + ((minutesAfter7PM - 60) / 50) * cellHeight;
      } else if (minutesAfter7PM <= 120) { // 课间10
        return yOffset + 2 * cellHeight + _shortBreakHeight + ((minutesAfter7PM - 110) / 10) * _shortBreakHeight;
      } else { // 第11节 (120-170)
        return yOffset + 2 * cellHeight + 2 * _shortBreakHeight + ((minutesAfter7PM - 120) / 50) * cellHeight;
      }
    }

    return maxPossibleY;
  }

  // 获取课程基于节次的精确边界，引入动态课间高度
  double getTopOffset(int p) {
    if (p <= 4) {
      return (p - 1) * cellHeight + (p - 1) * _shortBreakHeight;
    } else if (p <= 8) {
      return 4 * cellHeight + 3 * _shortBreakHeight + breakHeight + (p - 5) * cellHeight + (p - 5) * _shortBreakHeight;
    } else {
      return 8 * cellHeight + 6 * _shortBreakHeight + 2 * breakHeight + (p - 9) * cellHeight + (p - 9) * _shortBreakHeight;
    }
  }

  double getBottomOffset(int p) {
    return getTopOffset(p) + cellHeight;
  }

  // 节次推算
  int getStartPeriod(int startTime) {
    if (startTime <= 850) return 1;
    if (startTime <= 950) return 2;
    if (startTime <= 1100) return 3;
    if (startTime <= 1200) return 4;
    if (startTime <= 1450) return 5;
    if (startTime <= 1550) return 6;
    if (startTime <= 1650) return 7;
    if (startTime <= 1750) return 8;
    if (startTime <= 1950) return 9;
    if (startTime <= 2050) return 10;
    return 11;
  }

  int getEndPeriod(int endTime) {
    if (endTime <= 850) return 1;
    if (endTime <= 950) return 2;
    if (endTime <= 1100) return 3;
    if (endTime <= 1200) return 4;
    if (endTime <= 1450) return 5;
    if (endTime <= 1550) return 6;
    if (endTime <= 1650) return 7;
    if (endTime <= 1750) return 8;
    if (endTime <= 1950) return 9;
    if (endTime <= 2050) return 10;
    return 11;
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
                                  subtitle: Text("开始: ${DateFormat('MM-dd HH:mm').format(todo.createdAt)}\n截止: ${todo.dueDate != null ? DateFormat('MM-dd HH:mm').format(todo.dueDate!) : '无'}"),
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

  // 渲染表头的全天事件横幅
  Widget _buildAllDayHeaderRow(DateTime? monday) {
    if (monday == null || _viewMode == 1) return const SizedBox.shrink();

    bool hasAnyAllDay = _allDayTodosPerDay.values.any((list) => list.isNotEmpty);
    if (!hasAnyAllDay) return const SizedBox.shrink();

    return Container(
      padding: EdgeInsets.only(left: timeColumnWidth, bottom: 4),
      color: Theme.of(context).colorScheme.surface,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: List.generate(7, (index) {
          int weekday = index + 1;
          List<TodoItem> dayTodos = _allDayTodosPerDay[weekday] ?? [];

          if (dayTodos.isEmpty) {
            return const Expanded(child: SizedBox(height: 22));
          }

          String text = dayTodos.length == 1 ? dayTodos.first.title : "${dayTodos.length}项全天待办";
          bool allDone = dayTodos.every((t) => t.isDone);

          return Expanded(
            child: GestureDetector(
              onTap: () {
                DateTime currentDay = monday.add(Duration(days: index));
                String dateStr = DateFormat('MM-dd').format(currentDay);
                _showAllDayTodos(context, dayTodos, dateStr);
              },
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
                padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 3),
                decoration: BoxDecoration(
                  color: allDone ? Colors.green.withOpacity(0.5) : Colors.amber.shade500.withOpacity(0.85),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  text,
                  style: TextStyle(
                    fontSize: 9,
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
      padding: EdgeInsets.only(left: timeColumnWidth, top: 8, bottom: 8),
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
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 2),
                if (dateStr.isNotEmpty)
                  Text(
                    dateStr,
                    style: TextStyle(
                      color: isToday ? Colors.blue : Colors.grey,
                      fontSize: 10,
                    ),
                  ),
              ],
            ),
          );
        }),
      ),
    );
  }

  Widget _buildGrid(double cellWidth) {
    List<Widget> children = [];
    bool isDark = Theme.of(context).brightness == Brightness.dark;
    Color lineColor = isDark ? Colors.white10 : Colors.black12;
    Color breakColor = isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.03);
    Color textColor = isDark ? Colors.white70 : Colors.black87;

    double currentY = 0;

    // 1. 绘制水平的网格线、左侧时间列以及休息分割带
    for (int i = 1; i <= 11; i++) {
      children.add(
          Positioned(
            top: currentY,
            left: 0,
            right: 0,
            height: cellHeight,
            child: Container(
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: lineColor, width: 0.5)),
              ),
            ),
          )
      );

      children.add(
          Positioned(
            top: currentY,
            left: 0,
            width: timeColumnWidth,
            height: cellHeight,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('$i', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: textColor)),
                const SizedBox(height: 2),
                Text(_getPeriodTime(i), style: const TextStyle(fontSize: 9, color: Colors.grey), textAlign: TextAlign.center),
              ],
            ),
          )
      );

      currentY += cellHeight;

      // 绘制课间/午休/晚休
      if (i == 4) {
        children.add(
            Positioned(
              top: currentY,
              left: 0,
              right: 0,
              height: breakHeight,
              child: Container(
                color: breakColor,
                alignment: Alignment.center,
                child: const Text('午休', style: TextStyle(fontSize: 11, color: Colors.grey)),
              ),
            )
        );
        currentY += breakHeight;
      } else if (i == 8) {
        children.add(
            Positioned(
              top: currentY,
              left: 0,
              right: 0,
              height: breakHeight,
              child: Container(
                color: breakColor,
                alignment: Alignment.center,
                child: const Text('晚休', style: TextStyle(fontSize: 11, color: Colors.grey)),
              ),
            )
        );
        currentY += breakHeight;
      } else if (i != 11 && _shortBreakHeight > 0) {
        // 短课间
        children.add(
            Positioned(
              top: currentY,
              left: 0,
              right: 0,
              height: _shortBreakHeight,
              child: Container(
                color: isDark ? Colors.white12 : Colors.grey.shade100,
              ),
            )
        );
        currentY += _shortBreakHeight;
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

    // 2. 将待办事项覆盖到网格上 (🚀 启用时间坐标系渲染)
    if (_viewMode != 1) {
      // 记录某天某时间段是否有堆叠，略微错开 X 轴防遮挡
      Map<String, int> collisionMap = {};

      for (int weekday = 1; weekday <= 7; weekday++) {
        for (var todo in _intraDayTodosPerDay[weekday]!) {
          DateTime start = todo.createdAt;
          DateTime end = todo.dueDate ?? start.add(const Duration(hours: 1));

          // 使用新的坐标系换算时间偏移量
          double top = _getYOffsetByTime(start.hour, start.minute);
          double bottom = _getYOffsetByTime(end.hour, end.minute);

          double height = bottom - top;
          // 防止待办时间太短，甚至不足一分钟，导致不可见，强制最低高度为半节课
          if (height < cellHeight / 2) height = cellHeight / 2;

          // 防重叠策略：如果一个待办的起始高度和其他待办相撞，就稍微往右偏移或者压缩宽度
          String collisionKey = "${weekday}_${(top / 10).floor()}";
          int stackIndex = collisionMap[collisionKey] ?? 0;
          collisionMap[collisionKey] = stackIndex + 1;

          double leftOffset = timeColumnWidth + (weekday - 1) * cellWidth;
          double finalWidth = cellWidth - 2;
          double finalLeft = leftOffset + 1;

          // 发生重叠时，层叠缩进展示
          if (stackIndex > 0) {
            finalLeft += 8.0 * stackIndex;
            finalWidth -= 8.0 * stackIndex;
          }

          children.add(
              Positioned(
                top: top + 1,
                left: finalLeft,
                width: finalWidth,
                height: height - 2,
                child: GestureDetector(
                  onTap: () {
                    Navigator.push(context, MaterialPageRoute(builder: (_) => TodoDetailScreen(todo: todo)));
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2), // 稍微减小垂直内边距
                    decoration: BoxDecoration(
                        color: todo.isDone ? Colors.green.withOpacity(0.5) : Colors.amber.shade500.withOpacity(0.85),
                        borderRadius: BorderRadius.circular(6),
                        // 给叠放的待办加点阴影更好辨认
                        boxShadow: stackIndex > 0 ? [const BoxShadow(color: Colors.black12, blurRadius: 2, offset: Offset(-1, 1))] : null
                    ),
                    // 🚀 核心修复：使用 ClipRRect 防止任何极端情况下的视觉溢出，并去除时间文本
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min, // 尽可能小
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Icon(todo.isDone ? Icons.check_circle : Icons.task_alt, size: 10, color: Colors.white),
                              const SizedBox(width: 4),
                              // 🚀 直接将标题放在第一行，并支持自动换行
                              Expanded(
                                child: Text(
                                  todo.title,
                                  style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      decoration: todo.isDone ? TextDecoration.lineThrough : null,
                                      height: 1.1
                                  ),
                                  maxLines: 3, // 允许最多显示3行标题
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
              )
          );
        }
      }
    }

    // 3. 将课程块覆盖到网格上
    if (_viewMode != 2) {
      for (var course in _weekCourses) {
        int startPeriod = getStartPeriod(course.startTime);
        int endPeriod = getEndPeriod(course.endTime);

        double top = getTopOffset(startPeriod);
        double height = getBottomOffset(endPeriod) - top;
        double left = timeColumnWidth + (course.weekday - 1) * cellWidth;

        Color bgColor = _getCourseColor(course.courseName);

        children.add(
            Positioned(
              top: top + 1,
              left: left + 1,
              width: cellWidth - 2,
              height: height - 2,
              child: GestureDetector(
                onTap: () {
                  Navigator.push(context, MaterialPageRoute(
                    builder: (_) => CourseDetailScreen(course: course),
                  ));
                },
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                      color: bgColor.withOpacity(0.95),
                      borderRadius: BorderRadius.circular(6),
                      boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 2, offset: Offset(0, 1))]
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        course.courseName,
                        style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold, height: 1.2),
                        maxLines: 4,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const Spacer(),
                      Text(
                        '@${course.roomName}',
                        style: const TextStyle(color: Colors.white, fontSize: 9, height: 1.1),
                        maxLines: 3,
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

    return Stack(
      children: children,
    );
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
              IconButton(
                icon: const Icon(Icons.arrow_back_ios, size: 16),
                onPressed: _availableWeeks.contains(_currentWeek - 1) ? () => _changeWeek(-1) : null,
              ),
              Text('第 $_currentWeek 周', style: const TextStyle(fontSize: 14)),
              IconButton(
                icon: const Icon(Icons.arrow_forward_ios, size: 16),
                onPressed: _availableWeeks.contains(_currentWeek + 1) ? () => _changeWeek(1) : null,
              ),
            ],
          ),
          const SizedBox(width: 4),

          // 切换查看模式
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
          // 全天/跨天事件横幅
          _buildAllDayHeaderRow(_getMondayOfCurrentWeek()),
          Divider(height: 1, thickness: 0.5, color: Theme.of(context).brightness == Brightness.dark ? Colors.white10 : Colors.black12),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                double cellWidth = (constraints.maxWidth - timeColumnWidth) / 7;
                return SingleChildScrollView(
                  child: SizedBox(
                    // 计算总高度以保证可以垂直滚动：11节课 + 2次长休息区 + 8次动态短课间
                    height: 11 * cellHeight + 2 * breakHeight + 8 * _shortBreakHeight,
                    child: _buildGrid(cellWidth),
                  ),
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
          if (course.lessonType != null) ...[
            const Divider(),
            _buildDetailRow(Icons.category, '课程类型', course.lessonType == 'EXPERIMENT' ? '实验课' : '理论/实践'),
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
    bool isAllDay = todo.dueDate != null &&
        todo.createdAt.hour == 0 && todo.createdAt.minute == 0 &&
        todo.dueDate!.hour == 23 && todo.dueDate!.minute == 59;

    String startTimeStr = isAllDay
        ? DateFormat('yyyy-MM-dd (全天)').format(todo.createdAt)
        : DateFormat('yyyy-MM-dd HH:mm').format(todo.createdAt);

    String endTimeStr = todo.dueDate == null
        ? '无截止时间'
        : (isAllDay
        ? DateFormat('yyyy-MM-dd (全天)').format(todo.dueDate!)
        : DateFormat('yyyy-MM-dd HH:mm').format(todo.dueDate!));

    // 计算进度
    double progress = 0.0;
    DateTime now = DateTime.now();
    DateTime start = todo.createdAt;
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
          _buildDetailRow(Icons.update, '最近更新', DateFormat('yyyy-MM-dd HH:mm').format(todo.lastUpdated)),
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