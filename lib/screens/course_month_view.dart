import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models.dart';
import '../services/pomodoro_service.dart';

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
    super.key,
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
  });

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

    // 2. 预计算所有全局数据 (应用筛选逻辑)
    final Map<String, int> densityMap = {};
    void addDensity(String? dStr, int weight) {
      if (dStr != null && dStr.isNotEmpty) {
        densityMap[dStr] = (densityMap[dStr] ?? 0) + weight;
      }
    }

    if (activeDataViews.contains('courses')) {
      courseMap.forEach((date, list) => addDensity(date, 3 * list.length));
    }
    if (activeDataViews.contains('todos')) {
      todoMap.forEach((date, list) => addDensity(date, 1 * list.length));
      crossDayTodoMap.forEach((date, list) => addDensity(date, 1 * list.length));
    }
    if (activeDataViews.contains('timeLogs')) {
      logMap.forEach((date, list) => addDensity(date, 2 * list.length));
    }
    if (activeDataViews.contains('pomodoros')) {
      pomMap.forEach((date, list) => addDensity(date, 2 * list.length));
    }

    final List<TodoItem> ganttTodos = activeDataViews.contains('todos')
        ? allTodos.where((t) {
      if (t.isDeleted || t.dueDate == null) return false;
      final start = DateTime.fromMillisecondsSinceEpoch(t.createdDate ?? t.createdAt).toLocal();
      bool isCrossDay = t.dueDate != null && !DateUtils.isSameDay(start, t.dueDate!);
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
    final DateTime weekStart = weekDays.first;
    final DateTime weekEnd = weekDays.last.add(const Duration(hours: 23, minutes: 59, seconds: 59));

    // 1. 收集课程和单日待办 (按天遍历)
    for (int i = 0; i < weekDays.length; i++) {
      final day = weekDays[i];
      final dStr = DateFormat('yyyy-MM-dd').format(day);
      
      if (activeDataViews.contains('courses')) {
        for (var c in (courseMap[dStr] ?? [])) {
          weekBars.add({'course': c, 'start': i, 'end': i, 'title': c.courseName});
        }
      }
      
      if (activeDataViews.contains('todos')) {
        for (var t in (todoMap[dStr] ?? [])) {
          // 只添加非跨周任务，跨周任务统一在下面处理
          DateTime start = DateTime.fromMillisecondsSinceEpoch(t.createdDate ?? t.createdAt).toLocal();
          DateTime end = t.dueDate ?? start;
          if (DateUtils.isSameDay(start, end)) {
            weekBars.add({'todo': t, 'start': i, 'end': i, 'title': t.title});
          }
        }
      }

      if (activeDataViews.contains('timeLogs')) {
        for (var l in (logMap[dStr] ?? [])) {
          weekBars.add({
            'timeLog': l,
            'start': i,
            'end': i,
            'title': _timeLogTitle(l),
          });
        }
      }

      if (activeDataViews.contains('pomodoros')) {
        for (var p in (pomMap[dStr] ?? [])) {
          weekBars.add({
            'pomodoro': p,
            'start': i,
            'end': i,
            'title': _pomodoroTitle(p),
          });
        }
      }
    }

    // 2. 收集跨周/跨天待办 (区间判定)
    if (activeDataViews.contains('todos')) {
      for (var t in allGanttTodos) {
        DateTime tStart = DateTime.fromMillisecondsSinceEpoch(t.createdDate ?? t.createdAt).toLocal();
        DateTime tEnd = t.dueDate ?? tStart;
        
        // 如果是单日任务，上面已经处理过了
        if (DateUtils.isSameDay(tStart, tEnd)) continue;

        // 碰撞检测：任务是否与本周有交集
        if (tStart.isAfter(weekEnd) || tEnd.isBefore(weekStart)) continue;

        // 计算在本周内的显示范围 (0-6)
        int startIdx = tStart.isBefore(weekStart) ? 0 : tStart.difference(weekStart).inDays;
        int endIdx = tEnd.isAfter(weekEnd) ? 6 : tEnd.difference(weekStart).inDays;

        weekBars.add({
          'todo': t,
          'start': startIdx.clamp(0, 6),
          'end': endIdx.clamp(0, 6),
          'title': t.title,
        });
      }
    }

    // 3. 排序 (未完成待办优先，然后课程、时间日志、番茄钟、已完成待办)
    weekBars.sort((a, b) {
      final priorityA = _barPriority(a);
      final priorityB = _barPriority(b);
      if (priorityA != priorityB) return priorityA.compareTo(priorityB);

      int lenA = (a['end'] as int) - (a['start'] as int);
      int lenB = (b['end'] as int) - (b['start'] as int);
      if (lenA != lenB) return lenB.compareTo(lenA);

      return (a['start'] as int).compareTo(b['start'] as int);
    });

    return LayoutBuilder(builder: (context, constraints) {
      double cellWidth = constraints.maxWidth / 7;
      return Container(
        height: cellHeight,
        margin: const EdgeInsets.only(bottom: 2),
        child: Stack(
          children: [
            // 背景层：热力图
            Row(
              children: weekDays.map((day) {
                final dStr = DateFormat('yyyy-MM-dd').format(day);
                int count = densityMap[dStr] ?? 0;
                Color? heatColor;
                if (count > 0) {
                  double opacity = (count / 15).clamp(0.05, 0.4);
                  heatColor = Colors.blue.withValues(alpha: opacity);
                }

                final List<CourseItem> dayCourses = activeDataViews.contains('courses') ? (courseMap[dStr] ?? []) : [];
                final List<TodoItem> dayTodos = activeDataViews.contains('todos') ? (todoMap[dStr] ?? []) : [];
                final List<TimeLogItem> dayLogs = activeDataViews.contains('timeLogs') ? (logMap[dStr] ?? []) : [];
                final List<PomodoroRecord> dayPoms = activeDataViews.contains('pomodoros') ? (pomMap[dStr] ?? []) : [];

                return Expanded(
                  child: RepaintBoundary(
                    child: GestureDetector(
                      onTap: () => onDayTapped(day),
                      child: _buildDetailedDayBackground(context, day, heatColor, isDark, cellHeight, dayCourses, dayTodos, dayLogs, dayPoms),
                    ),
                  ),
                );
              }).toList(),
            ),

            // 甘特图层
            Positioned(
              left: 0,
              right: 0,
              top: 25,
              bottom: viewMode == 2 ? 12 : 4,
              child: LayoutBuilder(
                builder: (context, ganttConstraints) {
                  final clusteredRows = _clusterBars(weekBars);
                  if (clusteredRows.isEmpty) return const SizedBox.shrink();

                  final bool isHalfMonthView = viewMode != 2;
                  final double rowSpacing = isHalfMonthView ? 4.0 : 2.0;
                  final double minRowHeight = 18.0;

                  final double calculatedRowHeight =
                      (ganttConstraints.maxHeight - ((clusteredRows.length - 1) * rowSpacing)) / clusteredRows.length;
                  final double rowHeight =
                      calculatedRowHeight.clamp(minRowHeight, isHalfMonthView ? 40.0 : 24.0);
                  final double barHeight = (rowHeight - 4).clamp(14.0, 22.0);

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
                              final todo = bar['todo'] as TodoItem?;
                              final course = bar['course'] as CourseItem?;
                              final timeLog = bar['timeLog'] as TimeLogItem?;
                              final pomodoro = bar['pomodoro'] as PomodoroRecord?;
                              final int start = bar['start'];
                              final int end = bar['end'];

                              final Color barColor = _barColor(bar, isDark);
                              final Color textColor = _barTextColor(bar, isDark);

                              return Positioned(
                                left: start * cellWidth + 2,
                                width: (end - start + 1) * cellWidth - 4,
                                height: barHeight,
                                child: GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onTap: () {
                                    if (course != null) {
                                      onDayTapped(weekDays[start]);
                                    } else if (todo != null) {
                                      onGanttTodoTap?.call(todo);
                                    } else if (timeLog != null || pomodoro != null) {
                                      onDayTapped(weekDays[start]);
                                    }
                                  },
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: barColor,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    padding: const EdgeInsets.symmetric(horizontal: 4),
                                    alignment: Alignment.centerLeft,
                                    child: Text(
                                      bar['title'] ?? '',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: textColor,
                                        fontSize: (barHeight * 0.6).clamp(8.0, 11.0),
                                        fontWeight: FontWeight.w500,
                                        decoration: (todo?.isDone ?? false) ? TextDecoration.lineThrough : null,
                                      ),
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

  int _barPriority(Map<String, dynamic> bar) {
    final todo = bar['todo'] as TodoItem?;
    if (todo != null) return todo.isDone ? 4 : 0;
    if (bar['course'] != null) return 1;
    if (bar['timeLog'] != null) return 2;
    if (bar['pomodoro'] != null) return 3;
    return 5;
  }

  Color _barColor(Map<String, dynamic> bar, bool isDark) {
    final todo = bar['todo'] as TodoItem?;
    final log = bar['timeLog'] as TimeLogItem?;
    final pomodoro = bar['pomodoro'] as PomodoroRecord?;

    if (bar['course'] != null) {
      return Colors.blue.withValues(alpha: 0.85);
    }
    if (todo != null) {
      final isTeam = todo.teamUuid != null;
      return todo.isDone
          ? (isDark ? Colors.white24 : Colors.black12)
          : (isTeam
              ? Colors.green.withValues(alpha: 0.7)
              : Colors.orange.withValues(alpha: 0.7));
    }
    if (log != null) {
      final tagColor = _firstTagColor(log.tagUuids);
      return (tagColor ?? const Color(0xFF3B82F6)).withValues(alpha: 0.72);
    }
    if (pomodoro != null) {
      final tagColor = _firstTagColor(pomodoro.tagUuids);
      return (tagColor ?? Colors.redAccent).withValues(alpha: 0.68);
    }
    return isDark ? Colors.white24 : Colors.black12;
  }

  Color _barTextColor(Map<String, dynamic> bar, bool isDark) {
    final todo = bar['todo'] as TodoItem?;
    if (todo != null && todo.isDone) {
      return isDark ? Colors.white38 : Colors.black38;
    }
    return Colors.white;
  }

  String _timeLogTitle(TimeLogItem log) {
    if (log.title.isNotEmpty) return log.title;
    final tag = _firstTag(log.tagUuids);
    return tag?.name ?? '时间日志';
  }

  String _pomodoroTitle(PomodoroRecord record) {
    final tag = _firstTag(record.tagUuids);
    return tag?.name ?? '番茄钟';
  }

  PomodoroTag? _firstTag(List<String> tagUuids) {
    if (tagUuids.isEmpty) return null;
    for (final tag in pomodoroTags) {
      if (tagUuids.contains(tag.uuid)) return tag;
    }
    return null;
  }

  Color? _firstTagColor(List<String> tagUuids) {
    final tag = _firstTag(tagUuids);
    if (tag == null) return null;
    return _hexToColor(tag.color);
  }

  Color _hexToColor(String hex) {
    var value = hex.replaceAll('#', '').trim();
    if (value.length == 6) value = 'FF$value';
    return Color(int.tryParse(value, radix: 16) ?? 0xFF3B82F6);
  }

  Widget _buildDetailedDayBackground(BuildContext context, DateTime day, Color? heatColor, bool isDark, double height, List<CourseItem> courses, List<TodoItem> todos, List<TimeLogItem> logs, List<PomodoroRecord> poms) {
    bool isToday = DateUtils.isSameDay(day, DateTime.now());
    bool isCurrentMonth = day.month == selectedMonth.month;

    // 🚀 核心修复：小圆点和时间轴也要响应隐藏跨天设置
    List<TodoItem> filteredTodos = todos.where((t) {
      if (activeDataViews.contains('hideCrossDay')) {
        final start = DateTime.fromMillisecondsSinceEpoch(t.createdDate ?? t.createdAt).toLocal();
        bool isCrossDay = t.dueDate != null && !DateUtils.isSameDay(start, t.dueDate!);
        if (isCrossDay) return false;
      }
      return true;
    }).toList();

    return Container(
      decoration: BoxDecoration(
        color: heatColor ?? (isCurrentMonth ? (isDark ? Colors.white.withValues(alpha: 0.02) : Colors.white) : Colors.transparent),
        border: Border.all(color: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.03), width: 0.5),
      ),
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.all(4.0),
            child: Text('${day.day}', style: TextStyle(fontSize: 10.5, color: isToday ? Colors.redAccent : (isCurrentMonth ? (isDark ? Colors.white70 : Colors.black87) : Colors.grey.withValues(alpha: 0.3)), fontWeight: isToday ? FontWeight.bold : FontWeight.normal)),
          ),
          if (viewMode == 1 && height > 150)
            Positioned(
              top: 25, left: 4, right: 4, bottom: 4,
              child: Stack(
                children: [
                  Column(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: List.generate(4, (i) => Container(height: 0.5, width: double.infinity, color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.05)))),
                  ...courses.map((c) => _buildVerticalBar(c.startTime, c.endTime, Colors.blue.withValues(alpha: 0.6), height)),
                  ...filteredTodos.where((t)=>t.dueDate != null).map((t) => _buildTimeDot(t.dueDate!.hour * 100 + t.dueDate!.minute, Colors.amber, height)),
                  ...logs.map((l) {
                    DateTime s = DateTime.fromMillisecondsSinceEpoch(l.startTime).toLocal();
                    DateTime e = DateTime.fromMillisecondsSinceEpoch(l.endTime).toLocal();
                    return _buildVerticalBar(s.hour * 100 + s.minute, e.hour * 100 + e.minute, Colors.blueAccent.withValues(alpha: 0.4), height);
                  }),
                  ...poms.map((p) {
                    final DateTime s = DateTime.fromMillisecondsSinceEpoch(p.startTime).toLocal();
                    final int endMs = p.endTime ?? (p.startTime + p.effectiveDuration * 1000);
                    final DateTime e = DateTime.fromMillisecondsSinceEpoch(endMs).toLocal();
                    return _buildVerticalBar(s.hour * 100 + s.minute, e.hour * 100 + e.minute, Colors.redAccent.withValues(alpha: 0.4), height);
                  }),
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
    double startY = _calculateTimeY(start, 600, 2400);
    double endY = _calculateTimeY(end, 600, 2400);
    return Positioned(top: startY * (height - 30), height: (endY - startY).clamp(0.02, 1.0) * (height - 30), left: 0, width: 3, child: Container(decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(1))));
  }

  Widget _buildTimeDot(int time, Color color, double height) {
    double y = _calculateTimeY(time, 600, 2400);
    return Positioned(top: y * (height - 30), left: 4, width: 4, height: 4, child: Container(decoration: BoxDecoration(color: color, shape: BoxShape.circle)));
  }

  Widget _buildMiniDot(Color color) => Container(width: 4, height: 4, decoration: BoxDecoration(color: color.withValues(alpha: 0.6), shape: BoxShape.circle));

  double _calculateTimeY(int time, int start, int end) {
    int minutes = (time ~/ 100) * 60 + (time % 100);
    return ((minutes - (start ~/ 100 * 60)) / ((end ~/ 100 * 60) - (start ~/ 100 * 60))).clamp(0.0, 1.0);
  }

  Widget _buildWeekdayHeader(BuildContext context) {
    final weekdays = ['一', '二', '三', '四', '五', '六', '日'];
    return Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Row(children: weekdays.map((day) => Expanded(child: Center(child: Text(day, style: const TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.bold))))).toList()));
  }
}
