import 'dart:math';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models.dart';
import '../services/course_service.dart';
import '../services/pomodoro_service.dart';
import '../storage_service.dart';

class PlanBlockStatsScreen extends StatefulWidget {
  final String username;

  const PlanBlockStatsScreen({super.key, required this.username});

  @override
  State<PlanBlockStatsScreen> createState() => _PlanBlockStatsScreenState();
}

class _PlanBlockStatsScreenState extends State<PlanBlockStatsScreen> {
  int _dimension = 0; // 0=day, 1=week, 2=month
  late DateTime _current;
  List<TodoPlanBlock> _allBlocks = [];
  List<TodoItem> _todos = [];
  List<PomodoroRecord> _pomodoroRecords = [];
  final Set<String> _mappedBlockIds = <String>{};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _current = DateTime.now();
    _loadData();
  }

  DateTimeRange get _range {
    switch (_dimension) {
      case 0:
        final start = DateTime(_current.year, _current.month, _current.day);
        return DateTimeRange(
            start: start, end: start.add(const Duration(days: 1)));
      case 1:
        final start = _current.subtract(Duration(days: _current.weekday - 1));
        final weekStart = DateTime(start.year, start.month, start.day);
        return DateTimeRange(
            start: weekStart, end: weekStart.add(const Duration(days: 7)));
      default:
        final start = DateTime(_current.year, _current.month, 1);
        final end = DateTime(_current.year, _current.month + 1, 1);
        return DateTimeRange(start: start, end: end);
    }
  }

  String get _rangeLabel {
    switch (_dimension) {
      case 0:
        return DateFormat('yyyy年MM月dd日').format(_current);
      case 1:
        final start = _current.subtract(Duration(days: _current.weekday - 1));
        final end = start.add(const Duration(days: 6));
        return '${DateFormat('MM.dd').format(start)} - ${DateFormat('MM.dd').format(end)}';
      default:
        return DateFormat('yyyy年MM月').format(_current);
    }
  }

  void _prev() {
    setState(() {
      switch (_dimension) {
        case 0:
          _current = _current.subtract(const Duration(days: 1));
          break;
        case 1:
          _current = _current.subtract(const Duration(days: 7));
          break;
        default:
          _current = DateTime(_current.year, _current.month - 1, 1);
      }
    });
    _loadData();
  }

  void _next() {
    setState(() {
      switch (_dimension) {
        case 0:
          _current = _current.add(const Duration(days: 1));
          break;
        case 1:
          _current = _current.add(const Duration(days: 7));
          break;
        default:
          _current = DateTime(_current.year, _current.month + 1, 1);
      }
    });
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    final r = _range;
    final results = await Future.wait([
      StorageService.getPlanBlocks(widget.username),
      StorageService.getTodos(widget.username),
      CourseService.getAllCourses(widget.username),
      PomodoroService.getRecordsInRange(r.start, r.end),
    ]);
    if (!mounted) return;
    final allBlocks =
        (results[0] as List<TodoPlanBlock>).where((b) => !b.isDeleted).toList();
    final todos =
        (results[1] as List<TodoItem>).where((t) => !t.isDeleted).toList();
    final courses =
        (results[2] as List<CourseItem>).where((c) => !c.isDeleted).toList();
    final records = (results[3] as List<PomodoroRecord>)
        .where((record) =>
            !record.isDeleted &&
            record.startTime >= r.start.millisecondsSinceEpoch &&
            record.startTime < r.end.millisecondsSinceEpoch)
        .toList();
    final rangeBlocks = allBlocks.where((b) {
      final start = DateTime.fromMillisecondsSinceEpoch(b.startTime);
      return !start.isBefore(r.start) && start.isBefore(r.end);
    }).toList();
    final mappedBlocks = _buildMappedBlocks(todos, courses, rangeBlocks, r);
    final mappedIds = mappedBlocks.map((block) => block.id).toSet();

    setState(() {
      _allBlocks = [
        ...rangeBlocks,
        ...mappedBlocks,
      ];
      _todos = todos;
      _pomodoroRecords = records;
      _mappedBlockIds
        ..clear()
        ..addAll(mappedIds);
      _loading = false;
    });
  }

  List<TodoPlanBlock> _buildMappedBlocks(
    List<TodoItem> todos,
    List<CourseItem> courses,
    List<TodoPlanBlock> existingBlocks,
    DateTimeRange range,
  ) {
    final blocks = <TodoPlanBlock>[];
    final plannedTodoIds = existingBlocks.map((block) => block.todoId).toSet();

    for (final course in courses) {
      final start = _courseDateTime(course.date, course.startTime);
      final end = _courseDateTime(course.date, course.endTime);
      if (start == null || end == null || !end.isAfter(start)) continue;
      if (!_startsInRange(start, range)) continue;
      final minutes = end.difference(start).inMinutes;
      if (minutes <= 0) continue;
      blocks.add(TodoPlanBlock(
        id: 'mapped_course_${course.uuid}',
        todoId: 'mapped_course_${course.uuid}',
        titleSnapshot: '课程：${course.courseName}',
        startTime: start.millisecondsSinceEpoch,
        endTime: end.millisecondsSinceEpoch,
        plannedMinutes: minutes,
        status: TodoPlanStatus.planned,
        source: TodoPlanSource.calendar,
        remark: course.roomName,
      ));
    }

    for (final todo in todos) {
      if (plannedTodoIds.contains(todo.id)) continue;
      final startMs = todo.createdDate;
      final dueDate = todo.dueDate;
      if (startMs == null || dueDate == null) continue;
      if (todo.isAllDayTask) continue;

      final start = DateTime.fromMillisecondsSinceEpoch(startMs);
      final end = dueDate;
      if (!end.isAfter(start)) continue;
      if (!_isSameLocalDay(start, end)) continue;
      if (!_startsInRange(start, range)) continue;

      final minutes = end.difference(start).inMinutes;
      if (minutes <= 0) continue;
      blocks.add(TodoPlanBlock(
        id: 'mapped_todo_${todo.id}',
        todoId: todo.id,
        titleSnapshot: todo.title,
        startTime: start.millisecondsSinceEpoch,
        endTime: end.millisecondsSinceEpoch,
        plannedMinutes: minutes,
        status: todo.isDone ? TodoPlanStatus.finished : TodoPlanStatus.planned,
        source: TodoPlanSource.calendar,
        remark: todo.remark,
      ));
    }

    return blocks;
  }

  DateTime? _courseDateTime(String date, int hhmm) {
    final parsed = DateTime.tryParse(date);
    if (parsed == null || hhmm <= 0) return null;
    final hour = hhmm ~/ 100;
    final minute = hhmm % 100;
    if (hour < 0 || hour > 23 || minute < 0 || minute > 59) return null;
    return DateTime(parsed.year, parsed.month, parsed.day, hour, minute);
  }

  bool _startsInRange(DateTime start, DateTimeRange range) =>
      !start.isBefore(range.start) && start.isBefore(range.end);

  bool _isSameLocalDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  bool _isMappedBlock(TodoPlanBlock block) =>
      _mappedBlockIds.contains(block.id);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        title:
            const Text('规划统计', style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadData,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _buildDimensionSelector(theme),
                  const SizedBox(height: 12),
                  _buildNavRow(theme),
                  const SizedBox(height: 16),
                  _buildOverviewCard(theme),
                  const SizedBox(height: 20),
                  _buildTrendChart(theme),
                  const SizedBox(height: 20),
                  _buildTodoRanking(theme),
                  const SizedBox(height: 20),
                  _buildMissedList(theme),
                  const SizedBox(height: 20),
                  _buildAiSuggestionCard(theme),
                  const SizedBox(height: 80),
                ],
              ),
            ),
    );
  }

  Widget _buildDimensionSelector(ThemeData theme) {
    return SegmentedButton<int>(
      segments: const [
        ButtonSegment(value: 0, label: Text('日')),
        ButtonSegment(value: 1, label: Text('周')),
        ButtonSegment(value: 2, label: Text('月')),
      ],
      selected: {_dimension},
      onSelectionChanged: (s) {
        setState(() => _dimension = s.first);
        _loadData();
      },
    );
  }

  Widget _buildNavRow(ThemeData theme) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(icon: const Icon(Icons.chevron_left), onPressed: _prev),
        Text(_rangeLabel,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        IconButton(icon: const Icon(Icons.chevron_right), onPressed: _next),
      ],
    );
  }

  Widget _buildOverviewCard(ThemeData theme) {
    final planned = _allBlocks.fold<int>(0, (s, b) => s + b.plannedMinutes);
    final actual =
        _allBlocks.fold<int>(0, (s, b) => s + _actualMinutesForBlock(b));
    final done = _allBlocks
        .where((b) =>
            b.status == TodoPlanStatus.finished ||
            (b.plannedMinutes > 0 &&
                _actualSecondsForBlock(b) >= b.plannedMinutes * 60 * 0.8))
        .length;
    final missed =
        _allBlocks.where((b) => b.status == TodoPlanStatus.missed).length;
    final skipped =
        _allBlocks.where((b) => b.status == TodoPlanStatus.skipped).length;
    final rate = planned <= 0 ? 0.0 : (actual / planned).clamp(0.0, 999.0);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            theme.colorScheme.primaryContainer.withValues(alpha: 0.5),
            theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Text(
            '${(rate * 100).round()}%',
            style: TextStyle(
              fontSize: 48,
              fontWeight: FontWeight.w900,
              color: _rateColor(rate),
            ),
          ),
          Text('达成率',
              style: TextStyle(
                  fontSize: 14, color: theme.colorScheme.onSurfaceVariant)),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _overviewChip('计划', _fmtMin(planned), Colors.deepPurple),
              _overviewChip('实际', _fmtMin(actual), Colors.green),
              _overviewChip(
                  '完成', '$done', Theme.of(context).colorScheme.primary, Icons.check_circle_outline),
              _overviewChip(
                  '漏做', '$missed', Colors.redAccent, Icons.cancel_outlined),
              _overviewChip('跳过', '$skipped', Colors.orange, Icons.skip_next),
            ],
          ),
        ],
      ),
    );
  }

  Widget _overviewChip(String label, String value, Color color,
      [IconData? icon]) {
    return Column(
      children: [
        if (icon != null)
          Icon(icon, size: 18, color: color)
        else
          const SizedBox(height: 18),
        const SizedBox(height: 4),
        Text(value,
            style: TextStyle(
                fontSize: 16, fontWeight: FontWeight.bold, color: color)),
        Text(label,
            style:
                TextStyle(fontSize: 11, color: color.withValues(alpha: 0.7))),
      ],
    );
  }

  Widget _buildTrendChart(ThemeData theme) {
    // 构建 7 个数据点
    final chartData = <_ChartPoint>[];
    for (int i = 0; i < 7; i++) {
      DateTime day;
      switch (_dimension) {
        case 0:
          // 日维度只显示一天
          day = DateTime(_current.year, _current.month, _current.day);
          break;
        case 1:
          final weekStart =
              _current.subtract(Duration(days: _current.weekday - 1));
          day = DateTime(weekStart.year, weekStart.month, weekStart.day)
              .add(Duration(days: i));
          break;
        default:
          day = DateTime(_current.year, _current.month, 1 + i * 4);
      }
      final dayBlocks = _allBlocks.where((b) {
        final s = DateTime.fromMillisecondsSinceEpoch(b.startTime);
        return s.year == day.year && s.month == day.month && s.day == day.day;
      }).toList();
      final planned = dayBlocks.fold<int>(0, (s, b) => s + b.plannedMinutes);
      final actual =
          dayBlocks.fold<int>(0, (s, b) => s + _actualMinutesForBlock(b));
      chartData.add(_ChartPoint(
        label: DateFormat(_dimension == 2 ? 'dd' : 'E', 'zh_CN').format(day),
        planned: planned,
        actual: actual,
      ));
    }

    final maxVal =
        chartData.map((d) => max(d.planned, d.actual)).fold<int>(0, max);
    if (maxVal <= 0) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color:
            theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('趋势',
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.onSurface)),
          const SizedBox(height: 4),
          Row(children: [
            Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                    color: Colors.deepPurple.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(2))),
            const SizedBox(width: 4),
            Text('计划',
                style: TextStyle(
                    fontSize: 11, color: theme.colorScheme.onSurfaceVariant)),
            const SizedBox(width: 12),
            Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(2))),
            const SizedBox(width: 4),
            Text('实际',
                style: TextStyle(
                    fontSize: 11, color: theme.colorScheme.onSurfaceVariant)),
          ]),
          const SizedBox(height: 12),
          SizedBox(
            height: 140,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: chartData.map((d) {
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Container(
                              width: 10,
                              height: max(2, 110 * d.planned / maxVal),
                              decoration: BoxDecoration(
                                color: Colors.deepPurple.withValues(alpha: 0.4),
                                borderRadius: BorderRadius.circular(3),
                              ),
                            ),
                            const SizedBox(width: 2),
                            Container(
                              width: 10,
                              height: max(2, 110 * d.actual / maxVal),
                              decoration: BoxDecoration(
                                color: Colors.green.withValues(alpha: 0.6),
                                borderRadius: BorderRadius.circular(3),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(d.label,
                            style: TextStyle(
                                fontSize: 9,
                                color: theme.colorScheme.onSurfaceVariant)),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTodoRanking(ThemeData theme) {
    // 按待办聚合
    final Map<String, int> todoActualMap = {};
    final Map<String, int> todoPlannedMap = {};
    for (final b in _allBlocks) {
      todoPlannedMap[b.todoId] =
          (todoPlannedMap[b.todoId] ?? 0) + b.plannedMinutes;
      todoActualMap[b.todoId] =
          (todoActualMap[b.todoId] ?? 0) + _actualMinutesForBlock(b);
    }
    if (todoActualMap.isEmpty) return const SizedBox.shrink();

    final sorted = todoActualMap.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final maxVal = sorted.first.value;
    if (maxVal <= 0) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color:
            theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('待办专注排行',
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.onSurface)),
          const SizedBox(height: 12),
          ...sorted.take(8).map((e) {
            final todo = _todos
                .cast<TodoItem?>()
                .firstWhere((t) => t?.id == e.key, orElse: () => null);
            final title = todo?.title ?? e.key;
            final planned = todoPlannedMap[e.key] ?? 0;
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 13,
                                color: theme.colorScheme.onSurface)),
                      ),
                      Text('${e.value}m / ${planned}m',
                          style: TextStyle(
                              fontSize: 12,
                              color: theme.colorScheme.onSurfaceVariant)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: maxVal > 0 ? e.value / maxVal : 0,
                      minHeight: 6,
                      backgroundColor:
                          theme.colorScheme.surfaceContainerHighest,
                      valueColor:
                          AlwaysStoppedAnimation(theme.colorScheme.primary),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildMissedList(ThemeData theme) {
    final missed = _allBlocks
        .where((b) => b.status == TodoPlanStatus.missed)
        .toList()
      ..sort((a, b) => b.startTime.compareTo(a.startTime));
    if (missed.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color:
            theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.warning_amber_rounded,
                  size: 18, color: Colors.redAccent),
              const SizedBox(width: 6),
              Text('漏做规划 (${missed.length})',
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.onSurface)),
            ],
          ),
          const SizedBox(height: 12),
          ...missed.take(10).map((b) {
            final start = DateFormat('MM/dd HH:mm')
                .format(DateTime.fromMillisecondsSinceEpoch(b.startTime));
            final end = DateFormat('HH:mm')
                .format(DateTime.fromMillisecondsSinceEpoch(b.endTime));
            final todo = _todos
                .cast<TodoItem?>()
                .firstWhere((t) => t?.id == b.todoId, orElse: () => null);
            return Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  Icon(Icons.cancel_outlined,
                      size: 15, color: Colors.redAccent),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                        '${b.titleSnapshot ?? todo?.title ?? '未命名'}  $start-$end',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 13, color: theme.colorScheme.onSurface)),
                  ),
                  Text('${b.plannedMinutes}m',
                      style: TextStyle(
                          fontSize: 12,
                          color: theme.colorScheme.onSurfaceVariant)),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  String _fmtMin(int minutes) {
    if (minutes < 60) return '${minutes}m';
    final h = minutes ~/ 60;
    final m = minutes % 60;
    return m > 0 ? '${h}h${m}m' : '${h}h';
  }

  Color _rateColor(double rate) {
    if (rate >= 0.8) return Colors.green;
    if (rate >= 0.5) return Colors.orange;
    return Colors.redAccent;
  }

  int _actualMinutesForBlock(TodoPlanBlock block) {
    return _actualSecondsForBlock(block) ~/ 60;
  }

  int _actualSecondsForBlock(TodoPlanBlock block) {
    final linkedRecordSeconds = _pomodoroRecords
        .where((record) => _recordBelongsToBlock(record, block))
        .fold<int>(0, (sum, record) => sum + record.effectiveDuration);
    return max(block.actualFocusSeconds, linkedRecordSeconds);
  }

  bool _recordBelongsToBlock(PomodoroRecord record, TodoPlanBlock block) {
    if (record.planBlockId == block.uuid ||
        block.pomodoroRecordIds.contains(record.uuid)) {
      return true;
    }
    if (record.planBlockId?.isNotEmpty == true ||
        record.todoUuid == null ||
        record.todoUuid != block.todoId) {
      return false;
    }
    final recordEnd =
        record.endTime ?? record.startTime + record.effectiveDuration * 1000;
    return record.startTime < block.endTime && recordEnd > block.startTime;
  }

  Widget _buildAiSuggestionCard(ThemeData theme) {
    if (_allBlocks.isEmpty) return const SizedBox.shrink();
    final missedOrEmpty = _allBlocks
        .where((b) =>
            !_isMappedBlock(b) &&
            (b.status == TodoPlanStatus.missed ||
                (b.plannedMinutes > 0 && _actualSecondsForBlock(b) <= 0)))
        .length;
    final lowCompletion = _allBlocks.where((b) {
      if (_isMappedBlock(b)) return false;
      final actualSeconds = _actualSecondsForBlock(b);
      if (b.plannedMinutes <= 0 || actualSeconds <= 0) return false;
      final ratio = actualSeconds / (b.plannedMinutes * 60);
      return ratio < 0.8;
    }).length;
    final totalPlanned =
        _allBlocks.fold<int>(0, (sum, block) => sum + block.plannedMinutes);
    final suggestions = <String>[
      if (missedOrEmpty >= 3) '漏做块较多，建议顺延未开始的规划，并减少同一天的连续安排。',
      if (lowCompletion >= 2) '多个规划未达到 80%，下次可把长规划拆成 25min x N 的番茄块。',
      if (totalPlanned >= 480) '计划总量偏满，建议保留课程和休息缓冲，避免把空闲时间排满。',
      if (missedOrEmpty < 3 && lowCompletion < 2 && totalPlanned < 480)
        '当前规划达成情况稳定，可以继续按这个节奏排期。',
    ];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer.withValues(alpha: 0.28),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.auto_awesome,
                size: 18, color: theme.colorScheme.secondary),
            const SizedBox(width: 6),
            Text('AI 建议',
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.onSurface)),
          ]),
          const SizedBox(height: 10),
          ...suggestions.map((text) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(text,
                    style: TextStyle(
                        fontSize: 13,
                        color: theme.colorScheme.onSurfaceVariant)),
              )),
        ],
      ),
    );
  }
}

class _ChartPoint {
  final String label;
  final int planned;
  final int actual;
  _ChartPoint(
      {required this.label, required this.planned, required this.actual});
}
