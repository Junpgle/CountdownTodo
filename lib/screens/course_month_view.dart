import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models.dart';
import '../services/course_service.dart';
import '../services/pomodoro_service.dart';
import '../utils/page_transitions.dart';
import 'course_screens.dart';

class CourseMonthView extends StatelessWidget {
  final DateTime selectedMonth;
  final Map<String, List<CourseItem>> courseMap;
  final Map<String, List<TodoItem>> todoMap;
  final Map<String, List<TodoItem>> crossDayTodoMap;
  final Map<String, List<TimeLogItem>> logMap;
  final Map<String, List<PomodoroRecord>> pomMap;
  final List<PomodoroTag> pomodoroTags;
  final Set<String> activeDataViews;
  final Function(DateTime) onMonthChanged;
  final Function(DateTime) onDayTapped;
  final List<TodoItem> allTodos;
  final int viewMode; 
  final Function(TodoItem)? onGanttTodoTap;
  final DateTime? currentWeekMonday;

  const CourseMonthView({
    Key? key,
    required this.selectedMonth,
    required this.courseMap,
    required this.todoMap,
    required this.crossDayTodoMap,
    required this.logMap,
    required this.pomMap,
    required this.pomodoroTags,
    required this.activeDataViews,
    required this.onMonthChanged,
    required this.onDayTapped,
    this.allTodos = const [],
    this.viewMode = 2,
    this.onGanttTodoTap,
    this.currentWeekMonday,
  }) : super(key: key);

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  @override
  Widget build(BuildContext context) {
    bool isDark = Theme.of(context).brightness == Brightness.dark;
    
    // 🚀 动态计算起始日期
    final DateTime startDate;
    if (viewMode == 2) {
      final firstDayOfMonth = DateTime(selectedMonth.year, selectedMonth.month, 1);
      final daysBefore = firstDayOfMonth.weekday - 1;
      startDate = firstDayOfMonth.subtract(Duration(days: daysBefore));
    } else {
      startDate = currentWeekMonday ?? selectedMonth;
    }
    
    // 🚀 根据 viewMode 决定显示天数
    final int showDays = viewMode == 1 ? 14 : (selectedMonth.weekday - 1 + DateTime(selectedMonth.year, selectedMonth.month + 1, 0).day);
    final int rowCount = (showDays / 7).ceil();
    final int totalDays = rowCount * 7;
    final days = List.generate(totalDays, (index) => startDate.add(Duration(days: index)));

    // 🚀 热力密度预计算
    final Map<String, int> densityMap = {};
    for (var t in allTodos) {
       if (t.isDeleted) continue;
       final dt = t.dueDate ?? DateTime.fromMillisecondsSinceEpoch(t.updatedAt);
       final dStr = DateFormat('yyyy-MM-dd').format(dt);
       densityMap[dStr] = (densityMap[dStr] ?? 0) + 1;
    }

    // 🚀 甘特任务识别 (仅跨天)
    final List<TodoItem> spanningTodos = allTodos.where((t) {
      if (t.isDeleted || t.dueDate == null) return false;
      final start = DateTime.fromMillisecondsSinceEpoch(t.createdDate ?? t.createdAt).toLocal();
      return !DateUtils.isSameDay(start, t.dueDate!);
    }).toList();
    
    return RepaintBoundary(
      child: Column(
        children: [
          _buildWeekdayHeader(context),
          const SizedBox(height: 4),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final int rows = rowCount;
                const int cols = 7;
                const double spacing = 1.0; 
                
                final double cellWidth = (constraints.maxWidth - (cols - 1) * spacing) / cols;
                final double cellHeight = (constraints.maxHeight - (rows - 1) * spacing) / rows;
                final double aspectRatio = cellWidth / (cellHeight > 0 ? cellHeight : 80);
  
                return GridView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  physics: const ClampingScrollPhysics(),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: cols,
                    childAspectRatio: aspectRatio,
                    mainAxisSpacing: spacing,
                    crossAxisSpacing: spacing,
                  ),
                  itemCount: days.length,
                  itemBuilder: (context, index) {
                    final day = days[index];
                    final dStr = DateFormat('yyyy-MM-dd').format(day);
                    
                    int count = densityMap[dStr] ?? 0;
                    Color? heatColor;
                    if (count > 0) {
                       double opacity = (count / 8).clamp(0.05, 0.4);
                       heatColor = Colors.blue.withOpacity(opacity);
                    }

                    final List<TodoItem> currentSpanning = spanningTodos.where((t) {
                       final start = DateTime.fromMillisecondsSinceEpoch(t.createdDate ?? t.createdAt).toLocal();
                       final startDay = DateTime(start.year, start.month, start.day);
                       final endDay = DateTime(t.dueDate!.year, t.dueDate!.month, t.dueDate!.day);
                       return !day.isBefore(startDay) && !day.isAfter(endDay);
                    }).toList();

                    return _buildDayCell(
                      context, 
                      day, 
                      isDark, 
                      cellHeight,
                      heatColor,
                      currentSpanning,
                      activeDataViews.contains('courses') ? (courseMap[dStr] ?? []) : [],
                      activeDataViews.contains('todos') ? (todoMap[dStr] ?? []) : [],
                      (activeDataViews.contains('todos') && !activeDataViews.contains('hideCrossDay')) 
                          ? (crossDayTodoMap[dStr] ?? []) 
                          : [],
                      activeDataViews.contains('timeLogs') ? (logMap[dStr] ?? []) : [],
                      activeDataViews.contains('pomodoros') ? (pomMap[dStr] ?? []) : [],
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWeekdayHeader(BuildContext context) {
    final weekdays = ['一', '二', '三', '四', '五', '六', '日'];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: weekdays.map((day) => Expanded(
          child: Center(
            child: Text(
              day,
              style: TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.bold),
            ),
          ),
        )).toList(),
      ),
    );
  }

  Widget _buildDayCell(
    BuildContext context, 
    DateTime day, 
    bool isDark, 
    double cellHeight,
    Color? heatColor,
    List<TodoItem> spanningTodos,
    List<CourseItem> courses,
    List<TodoItem> todos,
    List<TodoItem> crossDayTodosInCell,
    List<TimeLogItem> logs,
    List<PomodoroRecord> pomodoros,
  ) {
    bool isCurrentMonth = day.month == selectedMonth.month;
    bool isToday = DateUtils.isSameDay(day, DateTime.now());

    List<dynamic> dayItems = [];
    dayItems.addAll(courses);
    dayItems.addAll(todos);
    dayItems.addAll(logs);
    dayItems.addAll(pomodoros);

    dayItems.sort((a, b) {
      int getPriority(dynamic item) {
        if (item is CourseItem) return 0;
        if (item is TodoItem) return 1;
        if (item is TimeLogItem) return 2;
        if (item is PomodoroRecord) return 3;
        return 4;
      }
      return getPriority(a).compareTo(getPriority(b));
    });

    int maxItems = ((cellHeight - 30) / 12).floor().clamp(1, 8);

    return GestureDetector(
      onTap: () => onDayTapped(day),
      child: Container(
        decoration: BoxDecoration(
          color: heatColor ?? (isCurrentMonth ? (isDark ? Colors.white.withOpacity(0.02) : Colors.white) : Colors.transparent),
          borderRadius: BorderRadius.circular(2),
          border: Border.all(
            color: isToday ? Theme.of(context).colorScheme.primary : (isDark ? Colors.white10 : Colors.black.withOpacity(0.03)),
            width: isToday ? 1.5 : 0.5,
          ),
        ),
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 2, 4, 0),
                  child: Text(
                    '${day.day}',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: isToday ? FontWeight.bold : FontWeight.normal,
                      color: isCurrentMonth ? (isDark ? Colors.white70 : Colors.black87) : Colors.grey.withOpacity(0.3),
                    ),
                  ),
                ),
                // 🚀 甘特融合层
                if (spanningTodos.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Column(
                      children: spanningTodos.take(3).map((t) {
                         final created = DateTime.fromMillisecondsSinceEpoch(t.createdDate ?? t.createdAt).toLocal();
                         final bool isStart = DateUtils.isSameDay(day, created);
                         final bool isEnd = DateUtils.isSameDay(day, t.dueDate!);
                         final color = (t.isDone ? Colors.green : Colors.blue).withOpacity(0.8);
                         
                         return GestureDetector(
                           onTap: () {
                             if (onGanttTodoTap != null) onGanttTodoTap!(t);
                           },
                           child: Container(
                             height: 16,
                             width: double.infinity,
                             margin: const EdgeInsets.only(bottom: 2),
                             padding: const EdgeInsets.symmetric(horizontal: 4),
                             alignment: Alignment.centerLeft,
                             decoration: BoxDecoration(
                               color: color,
                               borderRadius: BorderRadius.horizontal(
                                 left: isStart ? const Radius.circular(4) : Radius.zero,
                                 right: isEnd ? const Radius.circular(4) : Radius.zero,
                               ),
                             ),
                             child: isStart ? Text(
                               t.title,
                               style: const TextStyle(fontSize: 9, color: Colors.white, fontWeight: FontWeight.bold, overflow: TextOverflow.ellipsis),
                             ) : const SizedBox.shrink(),
                           ),
                         );
                      }).toList(),
                    ),
                  ),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: dayItems.length > maxItems ? maxItems : dayItems.length,
                    itemBuilder: (context, idx) => _buildCompactItem(context, dayItems[idx]),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCompactItem(BuildContext context, dynamic item) {
    if (item is CourseItem) return _buildMiniDot(_getCourseColor(item.courseName));
    if (item is TodoItem) return _buildMiniDot(item.isDone ? Colors.green : Colors.amber);
    return _buildMiniDot(Colors.blueGrey);
  }

  Widget _buildMiniDot(Color color) {
    return Container(
      width: double.infinity,
      height: 2,
      margin: const EdgeInsets.symmetric(vertical: 1, horizontal: 1),
      decoration: BoxDecoration(color: color.withOpacity(0.5), borderRadius: BorderRadius.circular(1)),
    );
  }

  Color _getCourseColor(String courseName) {
    final List<Color> colors = [Colors.blue, Colors.orange, Colors.purple, Colors.teal, Colors.pink];
    return colors[courseName.hashCode.abs() % colors.length];
  }
}
