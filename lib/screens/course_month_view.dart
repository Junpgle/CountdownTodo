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

  @override
  Widget build(BuildContext context) {
    bool isDark = Theme.of(context).brightness == Brightness.dark;

    // 1. 确定起始日期与天数
    final DateTime startDate;
    int showDays;
    if (viewMode == 2) {
      final firstDayOfMonth = DateTime(selectedMonth.year, selectedMonth.month, 1);
      final daysBefore = firstDayOfMonth.weekday - 1;
      startDate = firstDayOfMonth.subtract(Duration(days: daysBefore));
      showDays = daysBefore + DateTime(selectedMonth.year, selectedMonth.month + 1, 0).day;
    } else {
      startDate = currentWeekMonday ?? selectedMonth;
      showDays = 14;
    }
    final int rowCount = (showDays / 7).ceil();
    final List<List<DateTime>> weeks = List.generate(rowCount, (w) =>
        List.generate(7, (d) => startDate.add(Duration(days: w * 7 + d)))
    );

    // 2. 预计算所有全局数据 (应用筛选逻辑，包含隐藏跨天)
    final Map<String, int> densityMap = {};
    if (activeDataViews.contains('todos')) {
      for (var t in allTodos) {
        if (t.isDeleted || t.dueDate == null) continue;

        // 🚀 核心修复：检查是否跨天并响应隐藏设置
        final start = DateTime.fromMillisecondsSinceEpoch(t.createdDate ?? t.createdAt).toLocal();
        bool isCrossDay = !DateUtils.isSameDay(start, t.dueDate!);
        if (isCrossDay && activeDataViews.contains('hideCrossDay')) continue;

        final dStr = DateFormat('yyyy-MM-dd').format(t.dueDate!);
        densityMap[dStr] = (densityMap[dStr] ?? 0) + 1;
      }
    }

    final List<TodoItem> ganttTodos = activeDataViews.contains('todos')
        ? allTodos.where((t) {
      if (t.isDeleted || t.dueDate == null) return false;
      // 🚀 核心修复：看板色条也必须响应隐藏跨天设置
      final start = DateTime.fromMillisecondsSinceEpoch(t.createdDate ?? t.createdAt).toLocal();
      bool isCrossDay = !DateUtils.isSameDay(start, t.dueDate!);
      if (isCrossDay && activeDataViews.contains('hideCrossDay')) return false;
      return true;
    }).toList()
        : [];

    return Column(
      children: [
        _buildWeekdayHeader(context),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              double availableHeight = constraints.maxHeight;
              double rowHeight = (availableHeight / weeks.length).clamp(110.0, 1000.0);
              return ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                physics: const NeverScrollableScrollPhysics(),
                itemCount: weeks.length,
                itemBuilder: (context, weekIdx) {
                  return _buildWeekRow(context, weeks[weekIdx], ganttTodos, densityMap, isDark, rowHeight);
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildWeekRow(BuildContext context, List<DateTime> weekDays, List<TodoItem> allGanttTodos, Map<String, int> densityMap, bool isDark, double cellHeight) {
    final List<Map<String, dynamic>> weekBars = [];
    final weekStart = weekDays.first;
    final weekEnd = weekDays.last.add(const Duration(hours: 23, minutes: 59, seconds: 59));

    for (var t in allGanttTodos) {
      final taskStart = DateTime.fromMillisecondsSinceEpoch(t.createdDate ?? t.createdAt).toLocal();
      final taskEnd = t.dueDate!;
      if (taskStart.isAfter(weekEnd) || taskEnd.isBefore(weekStart)) continue;

      int startIdx = taskStart.isBefore(weekStart) ? 0 : taskStart.weekday - 1;
      int endIdx = taskEnd.isAfter(weekEnd) ? 6 : taskEnd.weekday - 1;

      weekBars.add({
        'todo': t,
        'start': startIdx,
        'end': endIdx,
        'isRealStart': taskStart.isAfter(weekStart.subtract(const Duration(seconds: 1))),
        'isRealEnd': taskEnd.isBefore(weekEnd.add(const Duration(seconds: 1))),
      });
    }

    // Sort bars by timeline so personal and team todos are mixed by time.
    weekBars.sort((a, b) {
      final TodoItem aTodo = a['todo'] as TodoItem;
      final TodoItem bTodo = b['todo'] as TodoItem;

      // Keep unfinished tasks on top, then preserve chronological order.
      if (aTodo.isDone != bTodo.isDone) return aTodo.isDone ? 1 : -1;

      final DateTime aStart = DateTime.fromMillisecondsSinceEpoch(
        aTodo.createdDate ?? aTodo.createdAt,
      ).toLocal();
      final DateTime bStart = DateTime.fromMillisecondsSinceEpoch(
        bTodo.createdDate ?? bTodo.createdAt,
      ).toLocal();
      final int byStart = aStart.compareTo(bStart);
      if (byStart != 0) return byStart;

      final DateTime aEnd = (aTodo.dueDate ?? aStart).toLocal();
      final DateTime bEnd = (bTodo.dueDate ?? bStart).toLocal();
      final int byEnd = aEnd.compareTo(bEnd);
      if (byEnd != 0) return byEnd;

      return aTodo.id.compareTo(bTodo.id);
    });

    return LayoutBuilder(builder: (context, constraints) {
      double cellWidth = constraints.maxWidth / 7;
      return Container(
        height: cellHeight,
        margin: const EdgeInsets.only(bottom: 2),
        child: Stack(
          children: [
            Row(
              children: weekDays.map((day) {
                final dStr = DateFormat('yyyy-MM-dd').format(day);
                int count = densityMap[dStr] ?? 0;
                Color? heatColor;
                if (count > 0) {
                  double opacity = (count / 10).clamp(0.05, 0.4);
                  heatColor = Colors.blue.withOpacity(opacity);
                }

                final List<CourseItem> dayCourses = activeDataViews.contains('courses') ? (courseMap[dStr] ?? []) : [];
                final List<TodoItem> dayTodos = activeDataViews.contains('todos') ? (todoMap[dStr] ?? []) : [];
                final List<TimeLogItem> dayLogs = activeDataViews.contains('timeLogs') ? (logMap[dStr] ?? []) : [];
                final List<PomodoroRecord> dayPoms = activeDataViews.contains('pomodoros') ? (pomMap[dStr] ?? []) : [];

                return Expanded(
                    child: GestureDetector(
                        onTap: () => onDayTapped(day),
                        child: _buildDetailedDayBackground(context, day, heatColor, isDark, cellHeight, dayCourses, dayTodos, dayLogs, dayPoms)
                    )
                );
              }).toList(),
            ),

            if (activeDataViews.contains('todos'))
              Positioned(
                left: 0,
                right: 0,
                top: 25,
                bottom: viewMode == 2 ? 0 : 4,
                child: LayoutBuilder(
                  builder: (context, ganttConstraints) {
                    final clusteredRows = _clusterBars(weekBars);
                    if (clusteredRows.isEmpty) return const SizedBox.shrink();

                    final bool isHalfMonthView = viewMode != 2;
                    final double rowSpacing = isHalfMonthView ? 4.0 : 2.0;
                    final double minRowHeight = 18.0;

                    // 1. 动态计算理想行高 (不限制最大截取行数)
                    final double calculatedRowHeight =
                        (ganttConstraints.maxHeight - ((clusteredRows.length - 1) * rowSpacing)) / clusteredRows.length;

                    // 2. 限制最大和最小高度，当高度被压缩到 minRowHeight 时，超出部分自然触发可滚动
                    final double rowHeight =
                    calculatedRowHeight.clamp(minRowHeight, isHalfMonthView ? 40.0 : 24.0);
                    final double barHeight = (rowHeight - 4).clamp(14.0, 22.0);

                    // 3. 使用 SingleChildScrollView 使内容支持滑动查看
                    return SingleChildScrollView(
                      physics: const BouncingScrollPhysics(),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.start,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: clusteredRows.map((rowGroup) {
                          return Container(
                            height: rowHeight,
                            margin: EdgeInsets.only(
                              bottom: rowGroup == clusteredRows.last ? 0 : rowSpacing,
                            ),
                            child: Stack(
                              clipBehavior: Clip.none,
                              children: rowGroup.map((bar) {
                                final t = bar['todo'] as TodoItem;
                                final int start = bar['start'];
                                final int end = bar['end'];
                                return Positioned(
                                  left: start * cellWidth + 2,
                                  width: (end - start + 1) * cellWidth - 4,
                                  height: barHeight,
                                  child: GestureDetector(
                                    behavior: HitTestBehavior.opaque,
                                    onTap: () => onGanttTodoTap?.call(t),
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color: (t.isDone
                                            ? Colors.green
                                            : (t.teamUuid != null ? Colors.blue : Colors.deepPurpleAccent))
                                            .withOpacity(0.9),
                                        borderRadius: BorderRadius.circular(6),
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.black.withOpacity(0.1),
                                            blurRadius: 2,
                                            offset: const Offset(0, 1),
                                          )
                                        ],
                                      ),
                                      padding: const EdgeInsets.symmetric(horizontal: 4),
                                      alignment: Alignment.centerLeft,
                                      child: Text(
                                        t.title,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 9.5,
                                          fontWeight: FontWeight.bold,
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
                        }).toList(),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      );
    });
  }

  List<List<Map<String, dynamic>>> _clusterBars(List<Map<String, dynamic>> bars) {
    List<List<Map<String, dynamic>>> rows = [];
    for (var bar in bars) {
      bool placed = false;
      for (var row in rows) {
        bool overlap = row.any((existing) => !(bar['end'] < existing['start'] || bar['start'] > existing['end']));
        if (!overlap) { row.add(bar); placed = true; break; }
      }
      if (!placed) rows.add([bar]);
    }
    return rows;
  }

  Widget _buildDetailedDayBackground(BuildContext context, DateTime day, Color? heatColor, bool isDark, double height, List<CourseItem> courses, List<TodoItem> todos, List<TimeLogItem> logs, List<PomodoroRecord> poms) {
    bool isToday = DateUtils.isSameDay(day, DateTime.now());
    bool isCurrentMonth = day.month == selectedMonth.month;

    // 🚀 核心修复：小圆点和时间轴也要响应隐藏跨天设置
    List<TodoItem> filteredTodos = todos.where((t) {
      if (activeDataViews.contains('hideCrossDay')) {
        final start = DateTime.fromMillisecondsSinceEpoch(t.createdDate ?? t.createdAt).toLocal();
        if (!DateUtils.isSameDay(start, t.dueDate!)) return false;
      }
      return true;
    }).toList();

    return Container(
      decoration: BoxDecoration(
        color: heatColor ?? (isCurrentMonth ? (isDark ? Colors.white.withOpacity(0.02) : Colors.white) : Colors.transparent),
        border: Border.all(color: isDark ? Colors.white10 : Colors.black.withOpacity(0.03), width: 0.5),
      ),
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.all(4.0),
            child: Text('${day.day}', style: TextStyle(fontSize: 10.5, color: isToday ? Colors.redAccent : (isCurrentMonth ? (isDark ? Colors.white70 : Colors.black87) : Colors.grey.withOpacity(0.3)), fontWeight: isToday ? FontWeight.bold : FontWeight.normal)),
          ),
          if (viewMode == 1 && height > 150)
            Positioned(
              top: 25, left: 4, right: 4, bottom: 4,
              child: Stack(
                children: [
                  Column(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: List.generate(4, (i) => Container(height: 0.5, width: double.infinity, color: isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.05)))),
                  ...courses.map((c) => _buildVerticalBar(c.startTime, c.endTime, Colors.blue.withOpacity(0.6), height)),
                  ...filteredTodos.where((t)=>t.dueDate != null).map((t) => _buildTimeDot(t.dueDate!.hour * 100 + t.dueDate!.minute, Colors.amber, height)),
                  ...logs.map((l) {
                    DateTime s = DateTime.fromMillisecondsSinceEpoch(l.startTime, isUtc: true).toLocal();
                    DateTime e = DateTime.fromMillisecondsSinceEpoch(l.endTime, isUtc: true).toLocal();
                    return _buildVerticalBar(s.hour * 100 + s.minute, e.hour * 100 + e.minute, Colors.blueAccent.withOpacity(0.4), height);
                  }),
                  ...poms.map((p) => _buildTimeDot(DateTime.fromMillisecondsSinceEpoch(p.startTime, isUtc: true).toLocal().hour * 100, Colors.redAccent, height)),
                ],
              ),
            ),
          if (viewMode == 2)
            Positioned(
              bottom: 4, left: 4, right: 4,
              child: Wrap(spacing: 2, children: [
                if (courses.isNotEmpty) _buildMiniDot(Colors.blue),
                if (filteredTodos.isNotEmpty) _buildMiniDot(Colors.amber),
                if (logs.isNotEmpty) _buildMiniDot(Colors.blueAccent),
                if (poms.isNotEmpty) _buildMiniDot(Colors.redAccent),
              ]),
            ),
        ],
      ),
    );
  }

  Widget _buildVerticalBar(int start, int end, Color color, double height) {
    double startY = _calculateTimeY(start, 800, 2200);
    double endY = _calculateTimeY(end, 800, 2200);
    return Positioned(top: startY * (height - 30), height: (endY - startY).clamp(0.02, 1.0) * (height - 30), left: 0, width: 3, child: Container(decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(1))));
  }

  Widget _buildTimeDot(int time, Color color, double height) {
    double y = _calculateTimeY(time, 800, 2200);
    return Positioned(top: y * (height - 30), left: 4, width: 4, height: 4, child: Container(decoration: BoxDecoration(color: color, shape: BoxShape.circle)));
  }

  Widget _buildMiniDot(Color color) => Container(width: 4, height: 4, decoration: BoxDecoration(color: color.withOpacity(0.6), shape: BoxShape.circle));

  double _calculateTimeY(int time, int start, int end) {
    int minutes = (time ~/ 100) * 60 + (time % 100);
    return ((minutes - (start ~/ 100 * 60)) / ((end ~/ 100 * 60) - (start ~/ 100 * 60))).clamp(0.0, 1.0);
  }

  Widget _buildWeekdayHeader(BuildContext context) {
    final weekdays = ['一', '二', '三', '四', '五', '六', '日'];
    return Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Row(children: weekdays.map((day) => Expanded(child: Center(child: Text(day, style: const TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.bold))))).toList()));
  }
}