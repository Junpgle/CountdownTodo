import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models.dart';
import 'home_sections.dart';

import '../screens/course_screens.dart';
import '../screens/todo_plan_screen.dart';
import '../services/course_service.dart';
import '../storage_service.dart';
import '../utils/page_transitions.dart';
import 'version_history_sheet.dart';

// ─────────────────────────────────────────────
// HHMM 整数 → 时间字符串  例: 800→"8:00"  950→"9:50"
// ─────────────────────────────────────────────
String _periodToTime(int hhmm) {
  final int h = hhmm ~/ 100;
  final int m = hhmm % 100;
  return '$h:${m.toString().padLeft(2, '0')}';
}

const List<String> _weekdayNames = [
  '',
  '周一',
  '周二',
  '周三',
  '周四',
  '周五',
  '周六',
  '周日'
];

String _weekdayLabel(int weekday) =>
    (weekday >= 1 && weekday <= 7) ? _weekdayNames[weekday] : '';

String _lessonTypeLabel(String? type) {
  if (type == 'EXPERIMENT') return '实验';
  if (type == 'THEORY') return '理论';
  return type?.trim() ?? '';
}

// ─────────────────────────────────────────────
// 主组件
// ─────────────────────────────────────────────
class CourseSectionWidget extends StatelessWidget {
  final Map<String, dynamic> dashboardCourseData;
  final List<TodoItem> todos;
  final bool isLight;
  final String? username;
  final int refreshTrigger;
  final Key? actionKey;

  const CourseSectionWidget({
    super.key,
    required this.dashboardCourseData,
    this.todos = const [],
    required this.isLight,
    this.username,
    this.refreshTrigger = 0,
    this.actionKey,
  });

  void _showCourseDetail(
      BuildContext context, CourseItem course, GlobalKey cardKey) {
    final renderBox = cardKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) {
      _showCourseDetailFallback(context, course);
      return;
    }
    final rect = renderBox.localToGlobal(Offset.zero) & renderBox.size;
    final color = Theme.of(context).colorScheme.surface;

    Navigator.push(
      context,
      ContainerTransformRoute(
        page: _CourseDetailPage(course: course),
        sourceRect: rect,
        sourceColor: color,
        sourceBorderRadius: const BorderRadius.all(Radius.circular(14)),
      ),
    );
  }

  void _showCourseDetailFallback(BuildContext context, CourseItem course) {
    final String typeLabel = _lessonTypeLabel(course.lessonType);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final colorScheme = Theme.of(ctx).colorScheme;
        return Container(
          margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          decoration: BoxDecoration(
            color: colorScheme.surface,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(
                child: Container(
                  margin: const EdgeInsets.only(top: 12, bottom: 8),
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: colorScheme.onSurface.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Container(
                margin: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer.withValues(alpha: 0.45),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(children: [
                  Container(
                      width: 4,
                      height: 44,
                      decoration: BoxDecoration(
                          color: colorScheme.primary,
                          borderRadius: BorderRadius.circular(2))),
                  const SizedBox(width: 12),
                  Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        Row(children: [
                          Expanded(
                              child: Text(course.courseName,
                                  style: TextStyle(
                                      fontSize: 17,
                                      fontWeight: FontWeight.bold,
                                      color: colorScheme.onSurface,
                                      height: 1.2))),
                          if (typeLabel.isNotEmpty)
                            Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                    color: colorScheme.secondaryContainer,
                                    borderRadius: BorderRadius.circular(8)),
                                child: Text(typeLabel,
                                    style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color:
                                            colorScheme.onSecondaryContainer))),
                        ]),
                        const SizedBox(height: 4),
                        Text(
                            '${_periodToTime(course.startTime)} – ${_periodToTime(course.endTime)}',
                            style: TextStyle(
                                fontSize: 13,
                                color: colorScheme.primary,
                                fontWeight: FontWeight.w600)),
                      ])),
                ]),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Column(children: [
                  _DetailRow(
                      icon: Icons.location_on_outlined,
                      label: "教室",
                      value: course.roomName,
                      colorScheme: colorScheme),
                  _DetailRow(
                      icon: Icons.person_outline_rounded,
                      label: "教师",
                      value: course.teacherName,
                      colorScheme: colorScheme),
                  _DetailRow(
                      icon: Icons.calendar_today_outlined,
                      label: "日期",
                      value: '${course.date}  ${_weekdayLabel(course.weekday)}',
                      colorScheme: colorScheme),
                  _DetailRow(
                      icon: Icons.view_week_outlined,
                      label: "周次",
                      value: '第 ${course.weekIndex} 周',
                      colorScheme: colorScheme),
                ]),
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(
                    16, 4, 16, MediaQuery.of(ctx).padding.bottom + 16),
                child: Row(children: [
                  Expanded(
                      child: FilledButton.tonal(
                          style: FilledButton.styleFrom(
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14)),
                              minimumSize: const Size.fromHeight(44)),
                          onPressed: () => Navigator.pop(ctx),
                          child: const Text("关闭"))),
                  const SizedBox(width: 10),
                  Expanded(
                      child: FilledButton(
                          style: FilledButton.styleFrom(
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14)),
                              minimumSize: const Size.fromHeight(44)),
                          onPressed: () {
                            Navigator.pop(ctx);
                            Navigator.push(
                                context,
                                PageTransitions.slideHorizontal(
                                    CourseDetailScreen(course: course)));
                          },
                          child: const Text("查看详情"))),
                ]),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    List<CourseItem> courses = [];
    try {
      if (dashboardCourseData['courses'] != null &&
          dashboardCourseData['courses'] is List) {
        for (var item in dashboardCourseData['courses']) {
          if (item is CourseItem) courses.add(item);
        }
      }
    } catch (e) {
      debugPrint('解析主页课程数据失败: $e');
    }

    if (username != null) {
      return _TodayScheduleList(
        username: username!,
        courses: courses,
        todos: todos,
        isLight: isLight,
        refreshTrigger: refreshTrigger,
        actionKey: actionKey,
        onCourseTap: (course, cardKey) =>
            _showCourseDetail(context, course, cardKey),
      );
    }

    final title = dashboardCourseData['title']?.toString() ?? '课程提醒';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: title,
          icon: Icons.class_outlined,
          onAction: null,
          actionIcon: null,
          actionTooltip: null,
          isLight: isLight,
        ),
        if (courses.isEmpty)
          EmptyState(
              text: dashboardCourseData['title'] == '暂无课表'
                  ? "尚未导入课表，点击上方图标开始"
                  : "近期暂无课程（今天与明天）",
              isLight: isLight)
        else
          ListView.builder(
            padding: EdgeInsets.zero,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: courses.length,
            itemBuilder: (context, index) {
              final course = courses[index];
              return _CourseCompactCard(
                course: course,
                isLight: isLight,
                onTap: (cardKey) => _showCourseDetail(context, course, cardKey),
              );
            },
          ),
      ],
    );
  }
}

enum _TodayScheduleItemType { course, plan, todo }

class _TodayScheduleItem {
  const _TodayScheduleItem.course(this.course)
      : block = null,
        todo = null,
        type = _TodayScheduleItemType.course;

  const _TodayScheduleItem.plan(this.block)
      : course = null,
        todo = null,
        type = _TodayScheduleItemType.plan;

  const _TodayScheduleItem.todo(this.todo)
      : course = null,
        block = null,
        type = _TodayScheduleItemType.todo;

  final _TodayScheduleItemType type;
  final CourseItem? course;
  final TodoPlanBlock? block;
  final TodoItem? todo;

  int get startMs {
    final plan = block;
    if (plan != null) return plan.startTime;
    final todoValue = todo;
    if (todoValue != null) return _todoStartMs(todoValue);
    final courseValue = course!;
    return _courseTimeMs(courseValue, courseValue.startTime);
  }

  int get endMs {
    final plan = block;
    if (plan != null) return plan.endTime;
    final todoValue = todo;
    if (todoValue != null) {
      return todoValue.dueDate?.millisecondsSinceEpoch ?? 0;
    }
    final courseValue = course!;
    return _courseTimeMs(courseValue, courseValue.endTime);
  }

  static int _todoStartMs(TodoItem todo) => todo.createdDate ?? todo.createdAt;

  static int _courseTimeMs(CourseItem course, int hhmm) {
    final date = DateTime.tryParse(course.date);
    if (date == null) return 0;
    final hour = hhmm ~/ 100;
    final minute = hhmm % 100;
    return DateTime(date.year, date.month, date.day, hour, minute)
        .millisecondsSinceEpoch;
  }
}

class _TodayScheduleList extends StatefulWidget {
  const _TodayScheduleList({
    required this.username,
    required this.courses,
    required this.todos,
    required this.isLight,
    required this.refreshTrigger,
    required this.onCourseTap,
    this.actionKey,
  });

  final String username;
  final List<CourseItem> courses;
  final List<TodoItem> todos;
  final bool isLight;
  final int refreshTrigger;
  final void Function(CourseItem course, GlobalKey cardKey) onCourseTap;
  final Key? actionKey;

  @override
  State<_TodayScheduleList> createState() => _TodayScheduleListState();
}

class _TodayScheduleListState extends State<_TodayScheduleList> {
  List<TodoPlanBlock> _blocks = [];
  List<TodoPlanBlock> _tomorrowBlocks = [];
  List<CourseItem> _todayCourses = [];
  List<CourseItem> _tomorrowCourses = [];
  bool _loading = true;
  bool _showEnded = false;

  @override
  void initState() {
    super.initState();
    _loadBlocks();
  }

  @override
  void didUpdateWidget(covariant _TodayScheduleList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.username != widget.username ||
        oldWidget.refreshTrigger != widget.refreshTrigger) {
      _loadBlocks();
    }
  }

  Future<void> _loadBlocks() async {
    setState(() => _loading = true);
    final now = DateTime.now();
    final results = await Future.wait([
      StorageService.getPlanBlocksByDay(widget.username, now),
      StorageService.getPlanBlocksByDay(
        widget.username,
        now.add(const Duration(days: 1)),
      ),
      CourseService.getAllCourses(widget.username),
    ]);
    final blocks = results[0] as List<TodoPlanBlock>;
    final tomorrowBlocks = results[1] as List<TodoPlanBlock>;
    final allCourses = results[2] as List<CourseItem>;
    final today = DateFormat('yyyy-MM-dd').format(now);
    final tomorrow =
        DateFormat('yyyy-MM-dd').format(now.add(const Duration(days: 1)));

    final missed = <TodoPlanBlock>[];
    for (final block in blocks) {
      if (!block.isDeleted &&
          block.status == TodoPlanStatus.planned &&
          block.actualFocusSeconds <= 0 &&
          block.endTime < now.millisecondsSinceEpoch) {
        block.status = TodoPlanStatus.missed;
        block.markAsChanged();
        missed.add(block);
      }
    }
    if (missed.isNotEmpty) {
      await StorageService.savePlanBlocks(widget.username, missed);
    }

    if (!mounted) return;
    setState(() {
      _blocks = blocks.where((b) => !b.isDeleted).toList();
      _tomorrowBlocks = tomorrowBlocks.where((b) => !b.isDeleted).toList();
      _todayCourses = allCourses
          .where((course) => !course.isDeleted && course.date == today)
          .toList()
        ..sort((a, b) => a.startTime.compareTo(b.startTime));
      _tomorrowCourses = allCourses
          .where((course) => !course.isDeleted && course.date == tomorrow)
          .toList()
        ..sort((a, b) => a.startTime.compareTo(b.startTime));
      _loading = false;
    });
  }

  void _openTodoPlanScreen() {
    Navigator.push(
      context,
      PageTransitions.material(
        builder: (_) => TodoPlanScreen(username: widget.username),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final fallbackToday = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final fallbackCourses =
        widget.courses.where((course) => course.date == fallbackToday).toList();
    final todayCourses = _todayCourses.isNotEmpty
        ? _todayCourses
        : (_loading ? fallbackCourses : <CourseItem>[]);
    final plannedTodoIds = _blocks
        .where((block) => !block.isDeleted && block.todoId.isNotEmpty)
        .map((block) => block.todoId)
        .toSet();
    final todayTimedTodos = _todayTimedTodos(
      widget.todos,
      DateTime.now(),
      excludeTodoIds: plannedTodoIds,
    );
    final todayItems = <_TodayScheduleItem>[
      ...todayCourses.map(_TodayScheduleItem.course),
      ..._blocks.map(_TodayScheduleItem.plan),
      ...todayTimedTodos.map(_TodayScheduleItem.todo),
    ]..sort((a, b) => a.startMs.compareTo(b.startMs));
    final endedItems = todayItems
        .where((item) => item.endMs > 0 && item.endMs < nowMs)
        .toList();
    final activeItems = todayItems
        .where((item) => item.endMs <= 0 || item.endMs >= nowMs)
        .toList();
    final tomorrowItems = <_TodayScheduleItem>[
      ..._tomorrowCourses.map(_TodayScheduleItem.course),
      ..._tomorrowBlocks.map(_TodayScheduleItem.plan),
    ]..sort((a, b) => a.startMs.compareTo(b.startMs));

    final showingTomorrow = activeItems.isEmpty &&
        (todayItems.isNotEmpty || tomorrowItems.isNotEmpty);
    final items = showingTomorrow ? tomorrowItems : activeItems;

    final scheduleTitle = showingTomorrow ? '明日日程' : '今日日程';
    final Widget content;
    if (_loading && todayItems.isEmpty && tomorrowItems.isEmpty) {
      content = const _TodayScheduleSkeleton();
    } else if (items.isEmpty && endedItems.isEmpty) {
      content = EmptyState(
        text: '今日和明日暂无课程、待办与规划',
        isLight: widget.isLight,
      );
    } else {
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (endedItems.isNotEmpty && !showingTomorrow) ...[
            _EndedScheduleSummary(
              count: endedItems.length,
              expanded: _showEnded,
              isLight: widget.isLight,
              onTap: () => setState(() => _showEnded = !_showEnded),
            ),
            if (_showEnded)
              ...endedItems.map((item) => Opacity(
                    opacity: 0.58,
                    child: _buildItemCard(item),
                  )),
          ],
          if (showingTomorrow)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                todayItems.isEmpty ? '明日安排' : '今日已全部结束，显示明日安排',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ...items.map(_buildItemCard),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: scheduleTitle,
          icon: Icons.class_outlined,
          onAction: _openTodoPlanScreen,
          actionIcon: Icons.event_note_outlined,
          actionTooltip: '打开规划界面',
          actionKey: widget.actionKey,
          isLight: widget.isLight,
        ),
        content,
      ],
    );
  }

  Widget _buildItemCard(_TodayScheduleItem item) {
    final course = item.course;
    if (course != null) {
      return _CourseCompactCard(
        course: course,
        isLight: widget.isLight,
        onTap: (cardKey) => widget.onCourseTap(course, cardKey),
      );
    }
    final todo = item.todo;
    if (todo != null) {
      return _TodoCompactCard(
        todo: todo,
        isLight: widget.isLight,
        onTap: () => Navigator.of(context).push(
          PageTransitions.material(
            builder: (_) => TodoDetailScreen(todo: todo),
          ),
        ),
      );
    }
    return _PlanCompactCard(
      block: item.block!,
      isLight: widget.isLight,
      onTap: () => Navigator.of(context).push(
        PageTransitions.material(
          builder: (_) => TodoPlanScreen(username: widget.username),
        ),
      ),
    );
  }

  List<TodoItem> _todayTimedTodos(
    List<TodoItem> todos,
    DateTime day, {
    required Set<String> excludeTodoIds,
  }) {
    return todos.where((todo) {
      if (todo.isDeleted || todo.dueDate == null) return false;
      if (excludeTodoIds.contains(todo.id)) return false;
      if (todo.isAllDayTask) return false;

      final startMs = todo.createdDate ?? todo.createdAt;
      if (startMs <= 0) return false;

      final start = DateTime.fromMillisecondsSinceEpoch(startMs).toLocal();
      final end = todo.dueDate!.toLocal();
      if (!end.isAfter(start)) return false;
      if (!_isSameLocalDay(start, end)) return false;
      return _isSameLocalDay(start, day);
    }).toList()
      ..sort((a, b) => _TodayScheduleItem._todoStartMs(a)
          .compareTo(_TodayScheduleItem._todoStartMs(b)));
  }

  bool _isSameLocalDay(DateTime a, DateTime b) {
    final left = a.toLocal();
    final right = b.toLocal();
    return left.year == right.year &&
        left.month == right.month &&
        left.day == right.day;
  }
}

class _EndedScheduleSummary extends StatelessWidget {
  const _EndedScheduleSummary({
    required this.count,
    required this.expanded,
    required this.isLight,
    required this.onTap,
  });

  final int count;
  final bool expanded;
  final bool isLight;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: colorScheme.surface.withValues(alpha: isLight ? 0.78 : 0.48),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: colorScheme.outline.withValues(alpha: 0.10),
        ),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                Icon(
                  expanded
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.keyboard_arrow_down_rounded,
                  size: 17,
                  color: colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '已结束 $count 项',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                Text(
                  expanded ? '收起' : '展开',
                  style: TextStyle(
                    fontSize: 11,
                    color: colorScheme.onSurfaceVariant.withValues(alpha: 0.72),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TodayScheduleSkeleton extends StatelessWidget {
  const _TodayScheduleSkeleton();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      children: List.generate(
        2,
        (index) => Container(
          margin: const EdgeInsets.only(bottom: 6),
          height: 58,
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
    );
  }
}

class _CourseDetailPage extends StatefulWidget {
  final CourseItem course;
  const _CourseDetailPage({required this.course});
  @override
  State<_CourseDetailPage> createState() => _CourseDetailPageState();
}

class _CourseDetailPageState extends State<_CourseDetailPage> {
  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final String typeLabel = _lessonTypeLabel(widget.course.lessonType);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.course.courseName),
        centerTitle: true,
        actions: [
          FilledButton.icon(
            onPressed: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                PageTransitions.slideHorizontal(
                    CourseDetailScreen(course: widget.course)),
              );
            },
            icon: const Icon(Icons.visibility_outlined, size: 18),
            label: const Text('详情'),
            style: FilledButton.styleFrom(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: colorScheme.primaryContainer.withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                Container(
                  width: 4,
                  height: 44,
                  decoration: BoxDecoration(
                    color: colorScheme.primary,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Expanded(
                              child: Text(widget.course.courseName,
                                  style: TextStyle(
                                      fontSize: 17,
                                      fontWeight: FontWeight.bold,
                                      color: colorScheme.onSurface,
                                      height: 1.2))),
                          if (typeLabel.isNotEmpty)
                            Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                    color: colorScheme.secondaryContainer,
                                    borderRadius: BorderRadius.circular(8)),
                                child: Text(typeLabel,
                                    style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color:
                                            colorScheme.onSecondaryContainer))),
                        ]),
                        const SizedBox(height: 4),
                        Text(
                            '${_periodToTime(widget.course.startTime)} – ${_periodToTime(widget.course.endTime)}',
                            style: TextStyle(
                                fontSize: 13,
                                color: colorScheme.primary,
                                fontWeight: FontWeight.w600)),
                      ]),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _DetailRow(
              icon: Icons.location_on_outlined,
              label: "教室",
              value: widget.course.roomName,
              colorScheme: colorScheme),
          _DetailRow(
              icon: Icons.person_outline_rounded,
              label: "教师",
              value: widget.course.teacherName,
              colorScheme: colorScheme),
          _DetailRow(
              icon: Icons.calendar_today_outlined,
              label: "日期",
              value:
                  '${widget.course.date}  ${_weekdayLabel(widget.course.weekday)}',
              colorScheme: colorScheme),
          _DetailRow(
              icon: Icons.view_week_outlined,
              label: "周次",
              value: '第 ${widget.course.weekIndex} 周',
              colorScheme: colorScheme),
        ]),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// 紧凑卡片（与待办风格对齐）
// ─────────────────────────────────────────────
class _CourseCompactCard extends StatefulWidget {
  final CourseItem course;
  final bool isLight;
  final Function(GlobalKey cardKey) onTap;

  const _CourseCompactCard({
    required this.course,
    required this.isLight,
    required this.onTap,
  });

  @override
  State<_CourseCompactCard> createState() => _CourseCompactCardState();
}

class _CourseCompactCardState extends State<_CourseCompactCard> {
  late final GlobalKey _cardKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final String typeLabel = _lessonTypeLabel(widget.course.lessonType);

    return Container(
      key: _cardKey,
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color:
            colorScheme.surface.withValues(alpha: widget.isLight ? 0.97 : 0.75),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: colorScheme.outline
              .withValues(alpha: widget.isLight ? 0.06 : 0.12),
          width: 1,
        ),
        boxShadow: widget.isLight
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.03),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                )
              ]
            : [],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => widget.onTap(_cardKey),
          onLongPress: () => VersionHistorySheet.show(
              context, widget.course.uuid, 'courses', widget.course.courseName),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            child: Row(
              children: [
                // 左侧竖条
                Container(
                  width: 3,
                  height: 36,
                  margin: const EdgeInsets.only(right: 10),
                  decoration: BoxDecoration(
                    color: colorScheme.primary.withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                // 时间列
                SizedBox(
                  width: 50,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _periodToTime(widget.course.startTime),
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: colorScheme.primary,
                          height: 1.2,
                        ),
                      ),
                      Text(
                        _periodToTime(widget.course.endTime),
                        style: TextStyle(
                          fontSize: 10.5,
                          color: colorScheme.primary.withValues(alpha: 0.55),
                          height: 1.2,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                // 课程名 + 地点教师
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              widget.course.courseName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 14.5,
                                fontWeight: FontWeight.w600,
                                color: colorScheme.onSurface,
                                height: 1.2,
                              ),
                            ),
                          ),
                          if (typeLabel.isNotEmpty) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: colorScheme.secondaryContainer
                                    .withValues(alpha: 0.8),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                typeLabel,
                                style: TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w600,
                                  color: colorScheme.onSecondaryContainer,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          Icon(Icons.location_on_rounded,
                              size: 11,
                              color:
                                  colorScheme.onSurface.withValues(alpha: 0.4)),
                          const SizedBox(width: 3),
                          Expanded(
                            child: Text(
                              '${widget.course.roomName}  ·  ${widget.course.teacherName}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11,
                                color: colorScheme.onSurface
                                    .withValues(alpha: 0.45),
                                height: 1.2,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 4),
                Icon(Icons.chevron_right_rounded,
                    size: 16,
                    color: colorScheme.onSurface.withValues(alpha: 0.25)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PlanCompactCard extends StatelessWidget {
  const _PlanCompactCard({
    required this.block,
    required this.isLight,
    required this.onTap,
  });

  final TodoPlanBlock block;
  final bool isLight;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final start = DateFormat('HH:mm')
        .format(DateTime.fromMillisecondsSinceEpoch(block.startTime));
    final end = DateFormat('HH:mm')
        .format(DateTime.fromMillisecondsSinceEpoch(block.endTime));
    final statusColor = _statusColor(block.status);

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: colorScheme.surface.withValues(alpha: isLight ? 0.97 : 0.75),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: statusColor.withValues(alpha: isLight ? 0.16 : 0.24),
          width: 1,
        ),
        boxShadow: isLight
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.03),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                )
              ]
            : [],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            child: Row(
              children: [
                Container(
                  width: 3,
                  height: 36,
                  margin: const EdgeInsets.only(right: 10),
                  decoration: BoxDecoration(
                    color: statusColor,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                SizedBox(
                  width: 50,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        start,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: statusColor,
                          height: 1.2,
                        ),
                      ),
                      Text(
                        end,
                        style: TextStyle(
                          fontSize: 10.5,
                          color: statusColor.withValues(alpha: 0.58),
                          height: 1.2,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Icon(
                            _statusIcon(block.status),
                            size: 14,
                            color: statusColor,
                          ),
                          const SizedBox(width: 5),
                          Expanded(
                            child: Text(
                              block.titleSnapshot ?? '未命名规划',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 14.5,
                                fontWeight: FontWeight.w600,
                                color: colorScheme.onSurface,
                                height: 1.2,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          Icon(Icons.event_note_rounded,
                              size: 11,
                              color:
                                  colorScheme.onSurface.withValues(alpha: 0.4)),
                          const SizedBox(width: 3),
                          Expanded(
                            child: Text(
                              '${block.plannedMinutes} 分钟规划${block.remark?.isNotEmpty == true ? ' · ${block.remark}' : ''}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11,
                                color: colorScheme.onSurface
                                    .withValues(alpha: 0.45),
                                height: 1.2,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 4),
                Icon(Icons.chevron_right_rounded,
                    size: 16,
                    color: colorScheme.onSurface.withValues(alpha: 0.25)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static IconData _statusIcon(TodoPlanStatus status) {
    switch (status) {
      case TodoPlanStatus.finished:
        return Icons.check_circle_rounded;
      case TodoPlanStatus.focusing:
        return Icons.play_circle_fill_rounded;
      case TodoPlanStatus.missed:
        return Icons.cancel_rounded;
      case TodoPlanStatus.skipped:
        return Icons.skip_next_rounded;
      case TodoPlanStatus.cancelled:
        return Icons.remove_circle_outline;
      default:
        return Icons.radio_button_unchecked;
    }
  }

  static Color _statusColor(TodoPlanStatus status) {
    switch (status) {
      case TodoPlanStatus.finished:
        return Colors.green;
      case TodoPlanStatus.focusing:
        return Colors.blue;
      case TodoPlanStatus.missed:
        return Colors.redAccent;
      case TodoPlanStatus.skipped:
        return Colors.orange;
      case TodoPlanStatus.cancelled:
        return Colors.grey;
      default:
        return Colors.deepPurple;
    }
  }
}

class _TodoCompactCard extends StatelessWidget {
  const _TodoCompactCard({
    required this.todo,
    required this.isLight,
    required this.onTap,
  });

  final TodoItem todo;
  final bool isLight;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final start = DateTime.fromMillisecondsSinceEpoch(
      todo.createdDate ?? todo.createdAt,
    ).toLocal();
    final end = todo.dueDate!.toLocal();
    final now = DateTime.now();
    final statusColor = todo.isDone
        ? Colors.green
        : (end.isBefore(now) ? Colors.redAccent : Colors.amber.shade700);
    final minutes = end.difference(start).inMinutes;

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: colorScheme.surface.withValues(alpha: isLight ? 0.97 : 0.75),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: statusColor.withValues(alpha: isLight ? 0.16 : 0.24),
          width: 1,
        ),
        boxShadow: isLight
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.03),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                )
              ]
            : [],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          onLongPress: () =>
              VersionHistorySheet.show(context, todo.id, 'todos', todo.title),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            child: Row(
              children: [
                Container(
                  width: 3,
                  height: 36,
                  margin: const EdgeInsets.only(right: 10),
                  decoration: BoxDecoration(
                    color: statusColor,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                SizedBox(
                  width: 50,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        DateFormat('HH:mm').format(start),
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: statusColor,
                          height: 1.2,
                        ),
                      ),
                      Text(
                        DateFormat('HH:mm').format(end),
                        style: TextStyle(
                          fontSize: 10.5,
                          color: statusColor.withValues(alpha: 0.58),
                          height: 1.2,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Icon(
                            todo.isDone
                                ? Icons.check_circle_rounded
                                : Icons.task_alt_rounded,
                            size: 14,
                            color: statusColor,
                          ),
                          const SizedBox(width: 5),
                          Expanded(
                            child: Text(
                              todo.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 14.5,
                                fontWeight: FontWeight.w600,
                                color: colorScheme.onSurface,
                                decoration: todo.isDone
                                    ? TextDecoration.lineThrough
                                    : null,
                                height: 1.2,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          Icon(Icons.schedule_rounded,
                              size: 11,
                              color:
                                  colorScheme.onSurface.withValues(alpha: 0.4)),
                          const SizedBox(width: 3),
                          Expanded(
                            child: Text(
                              '${minutes > 0 ? '$minutes 分钟' : '定时待办'}${todo.remark?.isNotEmpty == true ? ' · ${todo.remark}' : ''}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11,
                                color: colorScheme.onSurface
                                    .withValues(alpha: 0.45),
                                height: 1.2,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 4),
                Icon(Icons.chevron_right_rounded,
                    size: 16,
                    color: colorScheme.onSurface.withValues(alpha: 0.25)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// 详情行
// ─────────────────────────────────────────────
class _DetailRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final ColorScheme colorScheme;

  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.colorScheme,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon,
              size: 16, color: colorScheme.onSurface.withValues(alpha: 0.45)),
          const SizedBox(width: 10),
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: colorScheme.onSurface.withValues(alpha: 0.5),
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 13,
                color: colorScheme.onSurface.withValues(alpha: 0.85),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
