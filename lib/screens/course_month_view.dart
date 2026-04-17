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
  }) : super(key: key);

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  @override
  Widget build(BuildContext context) {
    bool isDark = Theme.of(context).brightness == Brightness.dark;
    
    // 计算月份数据
    final firstDayOfMonth = DateTime(selectedMonth.year, selectedMonth.month, 1);
    final daysBefore = firstDayOfMonth.weekday - 1;
    final startDate = firstDayOfMonth.subtract(Duration(days: daysBefore));
    final lastDayOfMonth = DateTime(selectedMonth.year, selectedMonth.month + 1, 0);
    final totalNeededDays = daysBefore + lastDayOfMonth.day;
    final int rowCount = (totalNeededDays / 7).ceil();
    final totalDays = rowCount * 7;
    final days = List.generate(totalDays, (index) => startDate.add(Duration(days: index)));
    
    return RepaintBoundary(
      child: Column(
        children: [
          const SizedBox(height: 8), // 增加一点顶部间距，避免遮挡
          // 星期表头
          _buildWeekdayHeader(context),
          const SizedBox(height: 4),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final int rows = rowCount;
                const int cols = 7;
                const double spacing = 4.0;
                
                final double gridWidth = constraints.maxWidth;
                final double gridHeight = constraints.maxHeight;
                
                final double cellWidth = (gridWidth - (cols - 1) * spacing) / cols;
                final double cellHeight = (gridHeight - (rows - 1) * spacing) / rows;
                final double aspectRatio = cellWidth / cellHeight;
  
                return GridView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: cols,
                    childAspectRatio: aspectRatio > 0 ? aspectRatio : 0.65,
                    mainAxisSpacing: spacing,
                    crossAxisSpacing: spacing,
                  ),
                  itemCount: days.length,
                  itemBuilder: (context, index) {
                    final day = days[index];
                    final dStr = DateFormat('yyyy-MM-dd').format(day);
                    return _buildDayCell(
                      context, 
                      day, 
                      isDark, 
                      cellHeight,
                      courseMap[dStr] ?? [],
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
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey,
                fontWeight: FontWeight.bold,
              ),
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
    List<CourseItem> courses,
    List<TodoItem> todos,
    List<TodoItem> crossDayTodosInCell,
    List<TimeLogItem> logs,
    List<PomodoroRecord> pomodoros,
  ) {
    bool isCurrentMonth = day.month == selectedMonth.month;
    bool isToday = DateFormat('yyyy-MM-dd').format(day) ==
        DateFormat('yyyy-MM-dd').format(DateTime.now());

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

    // 如果有跨天待办，将其总结为一个块并放在最前面
    if (crossDayTodosInCell.isNotEmpty) {
      dayItems.insert(0, {
        'type': 'crossDaySummary',
        'count': crossDayTodosInCell.length,
        'todos': crossDayTodosInCell
      });
    }

    // 动态计算能显示的条目数量
    int maxItems = ((cellHeight - 40) / 14).floor().clamp(1, 10);

    return GestureDetector(
      onTap: () => _showDayDetails(context, day, dayItems),
      child: Container(
        decoration: BoxDecoration(
          color: isToday 
              ? Theme.of(context).colorScheme.primary.withOpacity(0.08) 
              : (isCurrentMonth ? (isDark ? Colors.white.withOpacity(0.02) : Colors.white) : Colors.transparent),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: isToday 
                ? Theme.of(context).colorScheme.primary.withOpacity(0.3) 
                : (isDark ? Colors.white10 : Colors.black.withOpacity(0.04)),
            width: 0.5,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 4, 4, 2),
              child: Text(
                '${day.day}',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: isToday ? FontWeight.bold : FontWeight.normal,
                  color: isCurrentMonth 
                      ? (isToday ? Theme.of(context).colorScheme.primary : (isDark ? Colors.white70 : Colors.black87))
                      : (isDark ? Colors.white24 : Colors.black26),
                ),
              ),
            ),
            Expanded(
              child: ListView.builder(
                padding: EdgeInsets.zero,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: dayItems.length > maxItems ? maxItems : dayItems.length,
                itemBuilder: (context, idx) {
                  final item = dayItems[idx];
                  return _buildCompactItem(context, item);
                },
              ),
            ),
            if (dayItems.length > maxItems)
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 2, right: 2),
                child: Text(
                  '+${dayItems.length - maxItems}',
                  style: TextStyle(fontSize: 8, color: isDark ? Colors.white38 : Colors.black38),
                  textAlign: TextAlign.right,
                ),
              ),
          ],
        ),
      ),
    );
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
    return colors[hash.abs() % colors.length];
  }

  Color _hexToColor(String hex) {
    String clean = hex.replaceAll('#', '');
    if (clean.length == 6) clean = 'FF$clean';
    return Color(int.parse(clean, radix: 16));
  }

  Widget _buildEventDot(Color color, String label) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: color.withOpacity(0.2),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withOpacity(0.5), width: 0.5),
      ),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 4,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 2),
          Expanded(
            child: Text(
              label,
              style: TextStyle(fontSize: 8, color: color, fontWeight: FontWeight.bold),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompactItem(BuildContext context, dynamic item) {
    if (item is Map && item['type'] == 'crossDaySummary') {
      return _buildEventDot(Colors.purple, '${item['count']}个跨天待办');
    }
    if (item is CourseItem) {
      return _buildEventDot(_getCourseColor(item.courseName), item.courseName);
    } else if (item is TodoItem) {
      return _buildEventDot(item.isDone ? Colors.green : Colors.amber, item.title);
    } else if (item is TimeLogItem) {
      Color color = const Color(0xFF3B82F6);
      if (item.tagUuids.isNotEmpty) {
        final tag = pomodoroTags.cast<PomodoroTag?>().firstWhere(
            (t) => item.tagUuids.contains(t?.uuid),
            orElse: () => null);
        if (tag != null) color = _hexToColor(tag.color);
      }
      return _buildEventDot(color, item.title.isNotEmpty ? item.title : '日志');
    } else if (item is PomodoroRecord) {
      Color pomColor = Colors.redAccent;
      String pomTitle = '专注';
      if (item.tagUuids.isNotEmpty) {
        final tag = pomodoroTags.cast<PomodoroTag?>().firstWhere(
            (t) => item.tagUuids.contains(t?.uuid),
            orElse: () => null);
        if (tag != null) {
          pomColor = _hexToColor(tag.color);
          pomTitle = tag.name;
        }
      }
      return _buildEventDot(pomColor, pomTitle);
    }
    return const SizedBox.shrink();
  }

  void _showDayDetails(BuildContext context, DateTime day, List<dynamic> items) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _DayDetailsBottomSheet(
        day: day,
        items: items,
        pomodoroTags: pomodoroTags,
      ),
    );
  }
}

class _DayDetailsBottomSheet extends StatelessWidget {
  final DateTime day;
  final List<dynamic> items;
  final List<PomodoroTag> pomodoroTags;

  const _DayDetailsBottomSheet({
    Key? key,
    required this.day,
    required this.items,
    required this.pomodoroTags,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final dateStr = DateFormat('yyyy年M月d日').format(day);
    final weekdayStr = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'][day.weekday - 1];

    return Container(
      height: MediaQuery.of(context).size.height * 0.7,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.withOpacity(0.3),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        dateStr,
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        weekdayStr,
                        style: TextStyle(color: Colors.grey),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '共 ${items.length} 个事项',
                  style: TextStyle(color: Theme.of(context).colorScheme.primary, fontSize: 13),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: items.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.event_busy, size: 64, color: Colors.grey.withOpacity(0.2)),
                        const SizedBox(height: 16),
                        Text('今日无安排', style: TextStyle(color: Colors.grey)),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: items.length,
                    itemBuilder: (context, index) {
                      final item = items[index];
                      return _buildDetailItem(context, item);
                    },
                  ),
          ),
        ],
      ),
    );
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
    return colors[hash.abs() % colors.length];
  }

  Color _hexToColor(String hex) {
    String clean = hex.replaceAll('#', '');
    if (clean.length == 6) clean = 'FF$clean';
    return Color(int.parse(clean, radix: 16));
  }

  Widget _buildDetailItem(BuildContext context, dynamic item) {
    if (item is Map && item['type'] == 'crossDaySummary') {
      final List<TodoItem> todos = item['todos'];
      return ExpansionTile(
        title: Text('${item['count']}个跨天/全天待办', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.purple)),
        leading: const Icon(Icons.layers, color: Colors.purple),
        children: todos.map((t) => ListTile(
          title: Text(t.title, style: TextStyle(decoration: t.isDone ? TextDecoration.lineThrough : null)),
          subtitle: Text(t.dueDate != null ? '截止: ${DateFormat('MM-dd HH:mm').format(t.dueDate!)}' : '无截止时间'),
          dense: true,
        )).toList(),
      );
    }
    if (item is CourseItem) {
      final color = _getCourseColor(item.courseName);
      return ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(Icons.class_, color: color),
        ),
        title: Text(item.courseName,
            style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(
            '${item.formattedStartTime} - ${item.formattedEndTime} @ ${item.roomName}'),
        onTap: () {
          Navigator.pop(context);
          Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => CourseDetailScreen(course: item)));
        },
      );
    } else if (item is TodoItem) {
      return ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: (item.isDone ? Colors.green : Colors.amber).withOpacity(0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(item.isDone ? Icons.check_circle : Icons.task_alt,
              color: item.isDone ? Colors.green : Colors.amber),
        ),
        title: Text(item.title,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              decoration: item.isDone ? TextDecoration.lineThrough : null,
              color: item.isDone ? Colors.grey : null,
            )),
        subtitle: Text(item.dueDate != null
            ? '截止: ${DateFormat('HH:mm').format(item.dueDate!)}'
            : '无截止时间'),
        onTap: () {
          Navigator.pop(context);
          Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => TodoDetailScreen(todo: item)));
        },
      );
    } else if (item is TimeLogItem) {
      final color = const Color(0xFF3B82F6);
      return ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(Icons.edit_calendar, color: color),
        ),
        title: Text(item.title.isNotEmpty ? item.title : '时间日志',
            style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(
            '${DateFormat('HH:mm').format(DateTime.fromMillisecondsSinceEpoch(item.startTime, isUtc: true).toLocal())} - ${DateFormat('HH:mm').format(DateTime.fromMillisecondsSinceEpoch(item.endTime, isUtc: true).toLocal())}'),
        onTap: () {
          Navigator.pop(context);
          Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) =>
                      TimeLogDetailScreen(log: item, tags: pomodoroTags)));
        },
      );
    } else if (item is PomodoroRecord) {
      const color = Colors.redAccent;
      return ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.timer, color: color),
        ),
        title: const Text('番茄专注', style: TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text('时长: ${item.effectiveDuration ~/ 60} 分钟'),
        onTap: () {
          Navigator.pop(context);
          Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) =>
                      PomodoroDetailScreen(record: item, tags: pomodoroTags)));
        },
      );
    }
    return const SizedBox.shrink();
  }
}
