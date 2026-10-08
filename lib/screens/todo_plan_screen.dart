import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models.dart';
import '../services/course_service.dart';
import '../storage_service.dart';
import '../utils/app_dialogs.dart';
import '../services/pomodoro_service.dart';
import '../services/plan_execution_repository.dart';
import '../widgets/plan_execution_view.dart';
import 'course_screens.dart';
import 'plan_block_stats_screen.dart';
import '../utils/page_transitions.dart';
import '../services/feature_tip_service.dart';
import '../widgets/coach_mark_overlay.dart';
import '../widgets/floating_glass_control.dart';
import '../widgets/plan_block_editor_sheet.dart';

// 复用 TimeLog 的颜色和基础常量
const double kTimeAxisW = 46.0;

final GlobalKey planDragKey = GlobalKey();

class TodoPlanScreen extends StatefulWidget {
  final String username;
  final DateTime? initialDate;
  final String? initialTodoId;

  const TodoPlanScreen({
    super.key,
    required this.username,
    this.initialDate,
    this.initialTodoId,
  });

  @override
  State<TodoPlanScreen> createState() => _TodoPlanScreenState();
}

class _TodoPlanScreenState extends State<TodoPlanScreen>
    with WidgetsBindingObserver {
  late DateTime _focusedDate;
  bool _isLoading = true;
  List<TodoPlanBlock> _planBlocks = [];
  List<TodoItem> _todos = [];
  List<TodoGroup> _todoGroups = [];
  List<CourseItem> _courses = [];
  List<PomodoroTag> _tags = [];
  List<PomodoroRecord> _pomodoroRecords = [];
  List<TimeLogItem> _timeLogs = [];
  String? _loadError;
  final Set<String> _mappedBlockIds = <String>{};
  int _loadGeneration = 0;

  bool _showCoachMarks = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final now = DateTime.now();
    final initial = widget.initialDate ?? now;
    _focusedDate = DateTime(initial.year, initial.month, initial.day);
    StorageService.scopedDataRefreshNotifier.addListener(_onScopedDataRefresh);
    _loadData();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkCoachMarks();
    });
  }

  void _checkCoachMarks() async {
    if (!mounted || _showCoachMarks) return;

    final hasShown = await FeatureTipService.hasTipBeenShown('todo_plan_guide');
    if (hasShown || !mounted) return;

    await Future.delayed(const Duration(milliseconds: 600));
    if (!mounted) return;

    setState(() {
      _showCoachMarks = true;
    });

    CoachMarkOverlay.show(
      context: context,
      steps: [
        CoachMarkStep(
          targetKey: planDragKey,
          title: '滑动创建规划',
          description: '在日历网格内的空白区域，上下滑动手指即可快速规划一整块时间！\n你还可以长按已有的规划块进行拖拽移动。',
        ),
      ],
      onFinish: () {
        if (mounted) {
          setState(() {
            _showCoachMarks = false;
          });
        }
        FeatureTipService.markTipShown('todo_plan_guide');
      },
      onSkip: () {
        if (mounted) {
          setState(() {
            _showCoachMarks = false;
          });
        }
        FeatureTipService.markTipShown('todo_plan_guide');
      },
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    StorageService.scopedDataRefreshNotifier
        .removeListener(_onScopedDataRefresh);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _loadData();
  }

  void _onScopedDataRefresh() {
    if (!mounted) return;
    final signal = StorageService.scopedDataRefreshNotifier.value;
    if (signal.affects(DataRefreshDomain.todos) ||
        signal.affects(DataRefreshDomain.todoGroups) ||
        signal.affects(DataRefreshDomain.courses) ||
        signal.affects(DataRefreshDomain.planBlocks) ||
        signal.affects(DataRefreshDomain.pomodoro) ||
        signal.affects(DataRefreshDomain.timeLogs)) {
      unawaited(_loadData());
    }
  }

  Future<void> _loadData() async {
    if (!mounted) return;
    final loadGeneration = ++_loadGeneration;
    final focusedDate = _focusedDate;
    setState(() {
      _isLoading = true;
      _loadError = null;
    });
    late final List<dynamic> results;
    try {
      results = await Future.wait([
        StorageService.getPlanBlocksByDay(widget.username, focusedDate),
        StorageService.getTodos(widget.username),
        StorageService.getTodoGroups(widget.username),
        CourseService.getAllCourses(widget.username),
        PomodoroService.getTags(),
        const PlanExecutionRepository().read(widget.username, focusedDate),
      ]);
    } catch (error) {
      debugPrint('TodoPlan load failed: $error');
      if (mounted && loadGeneration == _loadGeneration) {
        setState(() {
          _isLoading = false;
          _loadError = '规划或实际记录读取失败，请重试';
        });
      }
      return;
    }

    if (!mounted || loadGeneration != _loadGeneration) return;

    final blocks =
        (results[0] as List<TodoPlanBlock>).where((b) => !b.isDeleted).toList();
    final todos =
        (results[1] as List<TodoItem>).where((t) => !t.isDeleted).toList();
    final todoGroups =
        (results[2] as List<TodoGroup>).where((g) => !g.isDeleted).toList();
    final courses =
        (results[3] as List<CourseItem>).where((c) => !c.isDeleted).toList();
    final tags = results[4] as List<PomodoroTag>;
    final execution = results[5] as PlanExecutionData;
    final records = execution.records;

    // 自动标记过期未完成的规划块为 missed
    final now = DateTime.now().millisecondsSinceEpoch;
    final missedBlocks = <TodoPlanBlock>[];
    for (final b in blocks) {
      if ((b.status == TodoPlanStatus.planned ||
              b.status == TodoPlanStatus.reminded) &&
          _actualSecondsForPlanBlock(b, records) <= 0 &&
          b.endTime < now) {
        b.status = TodoPlanStatus.missed;
        b.markAsChanged();
        missedBlocks.add(b);
      }
    }
    if (missedBlocks.isNotEmpty) {
      await StorageService.savePlanBlocks(widget.username, missedBlocks);
    }

    if (!mounted || loadGeneration != _loadGeneration) return;

    setState(() {
      _planBlocks = blocks;
      _todos = todos;
      _todoGroups = todoGroups;
      _courses = courses;
      _tags = tags;
      _pomodoroRecords = records;
      _timeLogs = execution.logs;
      _mappedBlockIds
        ..clear()
        ..addAll(_buildMappedBlocks(todos, courses, blocks)
            .map((block) => block.id));
      _isLoading = false;
    });
  }

  List<TodoPlanBlock> _buildMappedBlocks(
    List<TodoItem> todos,
    List<CourseItem> courses,
    List<TodoPlanBlock> existingBlocks,
  ) {
    final mapped = <TodoPlanBlock>[];
    final plannedTodoIds = existingBlocks
        .where((block) => !block.isDeleted && block.todoId.isNotEmpty)
        .map((block) => block.todoId)
        .toSet();

    for (final course in courses) {
      final start = _courseDateTime(course.date, course.startTime);
      final end = _courseDateTime(course.date, course.endTime);
      if (start == null || end == null || !end.isAfter(start)) continue;
      if (!_isSameLocalDay(start, _focusedDate)) continue;
      final minutes = end.difference(start).inMinutes;
      if (minutes <= 0) continue;
      mapped.add(TodoPlanBlock(
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

      final start = DateTime.fromMillisecondsSinceEpoch(startMs).toLocal();
      final end = dueDate.toLocal();
      if (!end.isAfter(start)) continue;
      if (!_isSameLocalDay(start, end)) continue;
      if (!_isSameLocalDay(start, _focusedDate)) continue;
      final minutes = end.difference(start).inMinutes;
      if (minutes <= 0) continue;

      mapped.add(TodoPlanBlock(
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

    return mapped;
  }

  DateTime? _courseDateTime(String date, int hhmm) {
    final parsed = DateTime.tryParse(date);
    if (parsed == null || hhmm < 0) return null;
    final hour = hhmm ~/ 100;
    final minute = hhmm % 100;
    if (hour < 0 || hour > 23 || minute < 0 || minute > 59) return null;
    return DateTime(parsed.year, parsed.month, parsed.day, hour, minute);
  }

  bool _isSameLocalDay(DateTime a, DateTime b) {
    final left = a.toLocal();
    final right = b.toLocal();
    return left.year == right.year &&
        left.month == right.month &&
        left.day == right.day;
  }

  void _prevDay() {
    setState(() {
      final date = _focusedDate.subtract(const Duration(days: 1));
      _focusedDate = DateTime(date.year, date.month, date.day);
    });
    unawaited(_loadData());
  }

  void _nextDay() {
    setState(() {
      final date = _focusedDate.add(const Duration(days: 1));
      _focusedDate = DateTime(date.year, date.month, date.day);
    });
    unawaited(_loadData());
  }

  void _pickDate() async {
    final picked = await showAppDatePicker(
      context: context,
      initialDate: _focusedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() {
        _focusedDate = picked;
      });
      unawaited(_loadData());
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mappedBlocks = _buildMappedBlocks(_todos, _courses, _planBlocks);
    final displayBlocks = [..._planBlocks, ...mappedBlocks]
      ..sort((a, b) => a.startTime.compareTo(b.startTime));
    final topBarHeight = floatingGlassTopBarHeight(context);
    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      extendBodyBehindAppBar: true,
      appBar: FloatingGlassAppBar(
        flexibleSpace: const FloatingGlassTopBarBackground(),
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.chevron_left),
              onPressed: _prevDay,
            ),
            GestureDetector(
              onTap: _pickDate,
              child: Text(
                DateFormat('MM月dd日').format(_focusedDate),
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.chevron_right),
              onPressed: _nextDay,
            ),
          ],
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.bar_chart_rounded),
            tooltip: '规划统计',
            onPressed: () => Navigator.of(context).push(
              PageTransitions.material(
                builder: (_) => PlanBlockStatsScreen(username: widget.username),
              ),
            ),
          ),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadData),
        ],
      ),
      body: FloatingGlassTopBarContentFade(
        topBarHeight: topBarHeight,
        tailExtent: 0,
        child: Padding(
          // The transparent app bar paints over the body. Keep the plan
          // summary and grid below it instead of hiding their first row.
          padding: EdgeInsets.only(top: topBarHeight),
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _loadError != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_loadError!),
                      TextButton(onPressed: _loadData, child: const Text('重试')),
                    ],
                  ),
                )
              : Column(
                  children: [
                    _PlanDaySummary(
                      blocks: _planBlocks,
                      pomodoroRecords: _pomodoroRecords,
                    ),
                    PlanExecutionSummary(
                      date: _focusedDate,
                      records: _pomodoroRecords,
                      logs: _timeLogs,
                      tags: _tags,
                    ),
                    Expanded(
                      child: _PlanGridView(
                        date: _focusedDate,
                        blocks: displayBlocks,
                        mappedBlockIds: _mappedBlockIds,
                        todos: _todos,
                        todoGroups: _todoGroups,
                        courses: _courses,
                        tags: _tags,
                        pomodoroRecords: _pomodoroRecords,
                        timeLogs: _timeLogs,
                        username: widget.username,
                        initialTodoId: widget.initialTodoId,
                        onRefresh: _loadData,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

int _actualMinutesForPlanBlock(
  TodoPlanBlock block,
  List<PomodoroRecord> records,
) {
  return _actualSecondsForPlanBlock(block, records) ~/ 60;
}

int _actualSecondsForPlanBlock(
  TodoPlanBlock block,
  List<PomodoroRecord> records,
) {
  final linkedRecordSeconds = records
      .where((record) => _pomodoroRecordBelongsToPlanBlock(record, block))
      .fold<int>(0, (sum, record) => sum + record.effectiveDuration);
  return max(block.actualFocusSeconds, linkedRecordSeconds);
}

bool _pomodoroRecordBelongsToPlanBlock(
  PomodoroRecord record,
  TodoPlanBlock block,
) {
  if (record.isDeleted || block.isDeleted) return false;
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

class _PlanDaySummary extends StatelessWidget {
  final List<TodoPlanBlock> blocks;
  final List<PomodoroRecord> pomodoroRecords;

  const _PlanDaySummary({
    required this.blocks,
    required this.pomodoroRecords,
  });

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final planned = blocks.fold<int>(0, (sum, b) => sum + b.plannedMinutes);
    final actual = blocks.fold<int>(
        0, (sum, b) => sum + _actualMinutesForPlanBlock(b, pomodoroRecords));
    final done = blocks
        .where((b) =>
            b.status == TodoPlanStatus.finished ||
            (b.plannedMinutes > 0 &&
                _actualSecondsForPlanBlock(b, pomodoroRecords) >=
                    b.plannedMinutes * 60 * 0.8))
        .length;
    final missed = blocks
        .where((b) =>
            (b.status == TodoPlanStatus.planned ||
                b.status == TodoPlanStatus.reminded) &&
            _actualSecondsForPlanBlock(b, pomodoroRecords) <= 0 &&
            b.endTime < now)
        .length;
    final rate = planned <= 0 ? 0 : ((actual / planned) * 100).clamp(0, 999);
    final theme = Theme.of(context);

    Widget chip(String label, String value, Color color, IconData icon) {
      return Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: color.withValues(alpha: 0.24)),
          ),
          child: Row(children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: color,
                          fontWeight: FontWeight.w800,
                          fontSize: 13)),
                  Text(label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: 0.55),
                          fontSize: 10)),
                ],
              ),
            ),
          ]),
        ),
      );
    }

    return Container(
      color: theme.colorScheme.surface,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      child: Row(children: [
        chip('计划', '${planned}m', Colors.deepPurple, Icons.event_note),
        const SizedBox(width: 8),
        chip('实际', '${actual}m', Colors.green, Icons.timer),
        const SizedBox(width: 8),
        chip('达成', '${rate.round()}%', Colors.blue, Icons.bar_chart),
        const SizedBox(width: 8),
        chip('完成/漏做', '$done/$missed', Colors.orange, Icons.task_alt),
      ]),
    );
  }
}

class _PlanGridView extends StatefulWidget {
  final DateTime date;
  final List<TodoPlanBlock> blocks;
  final Set<String> mappedBlockIds;
  final List<TodoItem> todos;
  final List<TodoGroup> todoGroups;
  final List<CourseItem> courses;
  final List<PomodoroTag> tags;
  final List<PomodoroRecord> pomodoroRecords;
  final List<TimeLogItem> timeLogs;
  final String username;
  final String? initialTodoId;
  final VoidCallback onRefresh;

  const _PlanGridView({
    required this.date,
    required this.blocks,
    required this.mappedBlockIds,
    required this.todos,
    required this.todoGroups,
    required this.courses,
    required this.tags,
    required this.pomodoroRecords,
    required this.timeLogs,
    required this.username,
    this.initialTodoId,
    required this.onRefresh,
  });

  @override
  State<_PlanGridView> createState() => _PlanGridViewState();
}

class _PlanGridViewState extends State<_PlanGridView> {
  int? _dragStartBlock;
  int? _dragEndBlock;
  int _minutesPerBlock = 15;
  TodoPlanBlock? _movingBlock;
  DateTime? _movingStart;
  DateTime? _movingEnd;
  int _lastMoveDelta = 0;

  int get _blocksPerHour => 60 ~/ _minutesPerBlock;
  bool get _hasExecutionRecords =>
      widget.pomodoroRecords.isNotEmpty || widget.timeLogs.isNotEmpty;

  int? _getIndex(Offset pos, double width, double hourH) {
    if (pos.dy < 0 || pos.dy > 24 * hourH) return null;
    final hour = (pos.dy / hourH).floor().clamp(0, 23);
    final blockInHour = ((pos.dx / width) * _blocksPerHour)
        .floor()
        .clamp(0, _blocksPerHour - 1);
    return hour * _blocksPerHour + blockInHour;
  }

  void _clearRecordSelection() {
    if (_dragStartBlock == null && _dragEndBlock == null) return;
    setState(() {
      _dragStartBlock = null;
      _dragEndBlock = null;
    });
  }

  void _handleDragStart(Offset pos, double width, double hourH) {
    final idx = _getIndex(pos, width, hourH);
    if (idx != null) {
      setState(() {
        _dragStartBlock = idx;
        _dragEndBlock = idx;
      });
    }
  }

  void _handleDragUpdate(Offset pos, double width, double hourH) {
    final idx = _getIndex(pos, width, hourH);
    if (idx != null) {
      setState(() {
        _dragEndBlock = idx;
      });
    }
  }

  void _handleDragEnd({required bool autoFillEstimateOnTodoChange}) async {
    if (_dragStartBlock == null || _dragEndBlock == null) return;

    final startIdx = min(_dragStartBlock!, _dragEndBlock!);
    final endIdx = max(_dragStartBlock!, _dragEndBlock!);

    final startTime =
        widget.date.add(Duration(minutes: startIdx * _minutesPerBlock));
    final endTime =
        widget.date.add(Duration(minutes: (endIdx + 1) * _minutesPerBlock));

    setState(() {
      _dragStartBlock = null;
      _dragEndBlock = null;
    });

    _showAddBlockSheet(
      startTime,
      endTime,
      autoFillEstimateOnTodoChange: autoFillEstimateOnTodoChange,
    );
  }

  void _showAddBlockSheet(
    DateTime startTime,
    DateTime endTime, {
    required bool autoFillEstimateOnTodoChange,
  }) {
    showPlanBlockEditorSheet(
      context: context,
      builder: (context) => PlanBlockEditorSheet(
        startTime: startTime,
        endTime: endTime,
        todos: widget.todos,
        todoGroups: widget.todoGroups,
        username: widget.username,
        initialTodoId: widget.initialTodoId,
        autoFillEstimateOnTodoChange: autoFillEstimateOnTodoChange,
        onSaved: widget.onRefresh,
      ),
    );
  }

  Future<void> _updateBlockTime(
    TodoPlanBlock block,
    DateTime start,
    DateTime end,
  ) async {
    if (!end.isAfter(start)) return;
    block.startTime = start.millisecondsSinceEpoch;
    block.endTime = end.millisecondsSinceEpoch;
    block.plannedMinutes = end.difference(start).inMinutes;
    block.markAsChanged();
    await StorageService.savePlanBlocks(widget.username, [block]);
    widget.onRefresh();
  }

  int _snapMinutes(double minutes) =>
      (minutes / _minutesPerBlock).round() * _minutesPerBlock;

  DateTime _dayStart() =>
      DateTime(widget.date.year, widget.date.month, widget.date.day);

  DateTime _clampToDay(DateTime value) {
    final start = _dayStart();
    final end = start.add(const Duration(days: 1));
    if (value.isBefore(start)) return start;
    if (value.isAfter(end)) return end;
    return value;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildGranularityBar(),
        Expanded(child: LayoutBuilder(builder: (context, constraints) {
          final totalH = constraints.maxHeight;
          final hourH = totalH / 24;
          final gridW = constraints.maxWidth - kTimeAxisW;

          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 时间轴
              SizedBox(
                width: kTimeAxisW,
                height: totalH,
                child: Stack(
                  children: List.generate(
                      24,
                      (h) => Positioned(
                            top: h * hourH + 1,
                            right: 6,
                            child: Text('${h.toString().padLeft(2, '0')}:00',
                                style: TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.w600,
                                    color:
                                        Colors.grey.withValues(alpha: 0.66))),
                          )),
                ),
              ),
              // 网格
              Expanded(
                child: GestureDetector(
                  onPanStart: (d) =>
                      _handleDragStart(d.localPosition, gridW, hourH),
                  onPanUpdate: (d) =>
                      _handleDragUpdate(d.localPosition, gridW, hourH),
                  onPanEnd: (d) =>
                      _handleDragEnd(autoFillEstimateOnTodoChange: false),
                  onTapDown: (d) =>
                      _handleDragStart(d.localPosition, gridW, hourH),
                  onTapUp: (d) =>
                      _handleDragEnd(autoFillEstimateOnTodoChange: true),
                  child: Container(
                    height: totalH,
                    decoration: BoxDecoration(
                      border: Border(
                          left: BorderSide(
                              color: Colors.grey.withValues(alpha: 0.1))),
                    ),
                    child: Stack(
                      children: [
                        ..._buildGridLines(gridW, hourH),
                        ...widget.blocks.expand(
                            (block) => _buildBlockItems(block, gridW, hourH)),
                        if (_hasExecutionRecords)
                          Positioned.fill(child: PlanExecutionTimelineLayer(
                            date: widget.date,
                            entries: PlanExecutionEntry.forDay(widget.date,
                                widget.pomodoroRecords, widget.timeLogs),
                            tags: widget.tags,
                            hourHeight: hourH,
                            onRecordInteraction: _clearRecordSelection,
                          )),
                        if (_dragStartBlock != null && _dragEndBlock != null)
                          ..._buildDraggingBlocks(gridW, hourH),
                        _buildNowLine(gridW, hourH),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          );
        })),
      ],
    );
  }

  Widget _buildGranularityBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
      child: Wrap(
        spacing: 6,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          const Text('粒度', style: TextStyle(fontSize: 12)),
          const SizedBox(width: 8),
          SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 5, label: Text('5')),
              ButtonSegment(value: 10, label: Text('10')),
              ButtonSegment(value: 15, label: Text('15')),
              ButtonSegment(value: 30, label: Text('30')),
            ],
            selected: {_minutesPerBlock},
            showSelectedIcon: false,
            onSelectionChanged: (value) {
              setState(() {
                _minutesPerBlock = value.first;
                _dragStartBlock = null;
                _dragEndBlock = null;
              });
            },
          ),
          const SizedBox(width: 6),
          Text('分钟', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
        ],
      ),
    );
  }

  List<Widget> _buildGridLines(double width, double hourH) {
    final lines = <Widget>[];
    for (int h = 0; h <= 24; h++) {
      lines.add(Positioned(
        top: h * hourH,
        left: 0,
        right: 0,
        height: 1,
        child: Container(color: Colors.grey.withValues(alpha: 0.06)),
      ));
    }
    for (int c = 1; c < _blocksPerHour; c++) {
      lines.add(Positioned(
        top: 0,
        bottom: 0,
        left: width * c / _blocksPerHour,
        width: 0.5,
        child: Container(color: Colors.grey.withValues(alpha: 0.05)),
      ));
    }

    // 隐藏的指引锚点 (9:00 - 10:00)
    lines.add(Positioned(
      top: 9 * hourH,
      left: width / 3,
      width: width / 3,
      height: hourH,
      child: SizedBox(key: planDragKey),
    ));

    return lines;
  }

  List<Widget> _buildBlockItems(
      TodoPlanBlock block, double width, double hourH) {
    final start = DateTime.fromMillisecondsSinceEpoch(block.startTime);
    final end = DateTime.fromMillisecondsSinceEpoch(block.endTime);
    final dayStart =
        DateTime(widget.date.year, widget.date.month, widget.date.day);
    final dayEnd = dayStart.add(const Duration(days: 1));
    if (!end.isAfter(dayStart) || !start.isBefore(dayEnd)) return const [];

    final clippedStart = start.isBefore(dayStart) ? dayStart : start;
    final clippedEnd = end.isAfter(dayEnd) ? dayEnd : end;
    final todo = widget.todos
        .cast<TodoItem?>()
        .firstWhere((t) => t?.id == block.todoId, orElse: () => null);
    final isMappedBlock = widget.mappedBlockIds.contains(block.id);
    final isMappedCourse = block.id.startsWith('mapped_course_');
    final color = isMappedCourse
        ? Colors.teal
        : (isMappedBlock
            ? Colors.amber.shade700
            : Theme.of(context).colorScheme.primary);
    final icon = isMappedCourse
        ? Icons.school_rounded
        : (isMappedBlock ? Icons.task_alt_rounded : Icons.event_note);
    final actualMinutes =
        _actualMinutesForPlanBlock(block, widget.pomodoroRecords);
    final widgets = <Widget>[];

    final endHour = clippedEnd.isAtSameMomentAs(dayEnd) ? 23 : clippedEnd.hour;
    for (int hour = clippedStart.hour; hour <= endHour; hour++) {
      final rowStart =
          DateTime(widget.date.year, widget.date.month, widget.date.day, hour);
      final rowEnd = rowStart.add(const Duration(hours: 1));
      final segmentStart =
          clippedStart.isAfter(rowStart) ? clippedStart : rowStart;
      final segmentEnd = clippedEnd.isBefore(rowEnd) ? clippedEnd : rowEnd;
      if (!segmentEnd.isAfter(segmentStart) || hour >= 24) continue;
      final isStartSegment = segmentStart.isAtSameMomentAs(clippedStart);
      final isEndSegment = segmentEnd.isAtSameMomentAs(clippedEnd);

      final left = width * segmentStart.minute / 60;
      final segmentW =
          max(2.0, width * segmentEnd.difference(segmentStart).inMinutes / 60);
      widgets.add(Positioned(
        top: hour * hourH + 1,
        left: left + 1,
        width: max(1.0, segmentW - 2),
        height: max(1.0, hourH * (_hasExecutionRecords ? 0.5 : 1.0) - 2),
        child: GestureDetector(
          onTap: isMappedBlock
              ? () => _openMappedBlockDetail(block)
              : () => _showEditBlockSheet(block),
          onLongPressStart: isMappedBlock
              ? null
              : (_) {
                  _movingBlock = block;
                  _movingStart = start;
                  _movingEnd = end;
                  _lastMoveDelta = 0;
                },
          onLongPressMoveUpdate: isMappedBlock
              ? null
              : (details) {
                  if (_movingBlock?.uuid != block.uuid ||
                      _movingStart == null ||
                      _movingEnd == null) {
                    return;
                  }
                  final deltaMinutes = _snapMinutes(
                    details.offsetFromOrigin.dy / hourH * 60 +
                        details.offsetFromOrigin.dx / width * 60,
                  );
                  if (deltaMinutes == _lastMoveDelta) return;
                  _lastMoveDelta = deltaMinutes;
                  final nextStart = _clampToDay(
                      _movingStart!.add(Duration(minutes: deltaMinutes)));
                  final duration = _movingEnd!.difference(_movingStart!);
                  var nextEnd = nextStart.add(duration);
                  final dayEnd = _dayStart().add(const Duration(days: 1));
                  if (nextEnd.isAfter(dayEnd)) {
                    nextEnd = dayEnd;
                  }
                  setState(() {
                    block.startTime = nextStart.millisecondsSinceEpoch;
                    block.endTime = nextEnd.millisecondsSinceEpoch;
                    block.plannedMinutes =
                        nextEnd.difference(nextStart).inMinutes;
                  });
                },
          onLongPressEnd: isMappedBlock
              ? null
              : (_) async {
                  _movingBlock = null;
                  _movingStart = null;
                  _movingEnd = null;
                  _lastMoveDelta = 0;
                  block.markAsChanged();
                  await StorageService.savePlanBlocks(widget.username, [block]);
                  widget.onRefresh();
                },
          child: Stack(
            children: [
              Container(
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(5),
                  border: Border.all(color: color.withValues(alpha: 0.4)),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                child: Row(
                  children: [
                    Icon(
                        block.status == TodoPlanStatus.finished
                            ? Icons.check_circle
                            : icon,
                        size: 10,
                        color: color),
                    const SizedBox(width: 3),
                    Expanded(
                      child: Text(
                        block.titleSnapshot ?? todo?.title ?? '未知待办',
                        style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: color),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                    ),
                    if (segmentW > 60 && isMappedBlock) ...[
                      const SizedBox(width: 4),
                      Text(
                        isMappedCourse ? '课程' : '待办',
                        style: TextStyle(
                            fontSize: 8,
                            fontWeight: FontWeight.w700,
                            color: color.withValues(alpha: 0.72)),
                        maxLines: 1,
                      ),
                    ],
                    if (segmentW > 68)
                      Text(
                        '${DateFormat('HH:mm').format(start)}-${DateFormat('HH:mm').format(end)}',
                        style: TextStyle(
                            fontSize: 8, color: color.withValues(alpha: 0.72)),
                        maxLines: 1,
                      ),
                    if (segmentW > 92 && actualMinutes > 0) ...[
                      const SizedBox(width: 4),
                      Text(
                        '$actualMinutes/${block.plannedMinutes}m',
                        style: TextStyle(
                            fontSize: 8,
                            fontWeight: FontWeight.w700,
                            color: Colors.green.shade700),
                        maxLines: 1,
                      ),
                    ],
                  ],
                ),
              ),
              if (isStartSegment && !isMappedBlock)
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  width: 12,
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onHorizontalDragUpdate: (details) {
                      final delta = _snapMinutes(details.delta.dx / width * 60);
                      if (delta == 0) return;
                      final nextStart = _clampToDay(
                        DateTime.fromMillisecondsSinceEpoch(block.startTime)
                            .add(Duration(minutes: delta)),
                      );
                      final endTime =
                          DateTime.fromMillisecondsSinceEpoch(block.endTime);
                      if (!endTime.isAfter(nextStart
                          .add(Duration(minutes: _minutesPerBlock - 1)))) {
                        return;
                      }
                      setState(() {
                        block.startTime = nextStart.millisecondsSinceEpoch;
                        block.plannedMinutes =
                            endTime.difference(nextStart).inMinutes;
                      });
                    },
                    onHorizontalDragEnd: (_) => _updateBlockTime(
                      block,
                      DateTime.fromMillisecondsSinceEpoch(block.startTime),
                      DateTime.fromMillisecondsSinceEpoch(block.endTime),
                    ),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Container(width: 3, color: color),
                    ),
                  ),
                ),
              if (isEndSegment && !isMappedBlock)
                Positioned(
                  right: 0,
                  top: 0,
                  bottom: 0,
                  width: 12,
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onHorizontalDragUpdate: (details) {
                      final delta = _snapMinutes(details.delta.dx / width * 60);
                      if (delta == 0) return;
                      final nextEnd = _clampToDay(
                        DateTime.fromMillisecondsSinceEpoch(block.endTime)
                            .add(Duration(minutes: delta)),
                      );
                      final startTime =
                          DateTime.fromMillisecondsSinceEpoch(block.startTime);
                      if (!nextEnd.isAfter(startTime
                          .add(Duration(minutes: _minutesPerBlock - 1)))) {
                        return;
                      }
                      setState(() {
                        block.endTime = nextEnd.millisecondsSinceEpoch;
                        block.plannedMinutes =
                            nextEnd.difference(startTime).inMinutes;
                      });
                    },
                    onHorizontalDragEnd: (_) => _updateBlockTime(
                      block,
                      DateTime.fromMillisecondsSinceEpoch(block.startTime),
                      DateTime.fromMillisecondsSinceEpoch(block.endTime),
                    ),
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: Container(width: 3, color: color),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ));
    }
    return widgets;
  }

  List<Widget> _buildDraggingBlocks(double width, double hourH) {
    final s = min(_dragStartBlock!, _dragEndBlock!);
    final e = max(_dragStartBlock!, _dragEndBlock!);
    final color = Theme.of(context).colorScheme.primary;
    final widgets = <Widget>[];

    for (int i = s; i <= e; i++) {
      final hour = i ~/ _blocksPerHour;
      final col = i % _blocksPerHour;
      widgets.add(Positioned(
        top: hour * hourH + 1,
        left: width * col / _blocksPerHour + 1,
        width: width / _blocksPerHour - 2,
        height: max(1.0, hourH - 2),
        child: Container(
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(4),
          ),
        ),
      ));
    }
    return widgets;
  }

  Widget _buildNowLine(double width, double hourH) {
    final now = DateTime.now();
    if (now.year != widget.date.year ||
        now.month != widget.date.month ||
        now.day != widget.date.day) {
      return const SizedBox.shrink();
    }

    final top = now.hour * hourH;
    final left = width * (now.minute + now.second / 60) / 60;
    return Positioned(
      top: top,
      left: left,
      height: hourH,
      child: Column(
        children: [
          Container(
            width: 6,
            height: 6,
            decoration:
                const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
          ),
          Expanded(child: Container(width: 1, color: Colors.red)),
        ],
      ),
    );
  }

  void _openMappedBlockDetail(TodoPlanBlock block) {
    if (block.id.startsWith('mapped_course_')) {
      final courseId = block.id.substring('mapped_course_'.length);
      final course = widget.courses.cast<CourseItem?>().firstWhere(
            (item) => item?.uuid == courseId,
            orElse: () => null,
          );
      if (course != null) {
        Navigator.of(context).push(
          PageTransitions.material(
              builder: (_) => CourseDetailScreen(course: course)),
        );
      }
      return;
    }

    if (block.id.startsWith('mapped_todo_')) {
      final todoId = block.id.substring('mapped_todo_'.length);
      final todo = widget.todos.cast<TodoItem?>().firstWhere(
            (item) => item?.id == todoId,
            orElse: () => null,
          );
      if (todo != null) {
        Navigator.of(context).push(
          PageTransitions.material(
              builder: (_) => TodoDetailScreen(todo: todo)),
        );
      }
    }
  }

  void _showEditBlockSheet(TodoPlanBlock block) {
    showPlanBlockEditorSheet(
      context: context,
      builder: (context) => PlanBlockEditorSheet(
        block: block,
        startTime: DateTime.fromMillisecondsSinceEpoch(block.startTime),
        endTime: DateTime.fromMillisecondsSinceEpoch(block.endTime),
        todos: widget.todos,
        todoGroups: widget.todoGroups,
        username: widget.username,
        initialTodoId: block.todoId,
        onSaved: widget.onRefresh,
      ),
    );
  }
}
