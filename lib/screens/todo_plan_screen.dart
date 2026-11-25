import '../widgets/plan_manual_completion_host.dart';
import '../services/plan_manual_completion_service.dart';
import 'plan_weekly_availability_screen.dart';

import 'dart:async';

import '../services/plan_review_repository.dart';
import '../widgets/plan_day_overview.dart';

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';

import '../models.dart';
import '../services/course_service.dart';
import '../storage_service.dart';
import '../utils/app_dialogs.dart';
import '../services/pomodoro_service.dart';
import 'pomodoro_screen.dart';
import 'pomodoro/pomodoro_entry_intent.dart';
import '../services/plan_execution_repository.dart';
import '../widgets/plan_execution_view.dart';
import 'course_screens.dart';
import 'plan_block_stats_screen.dart';
import 'plan_backlog_screen.dart';
import 'plan_editor_drafts_screen.dart';
import '../utils/page_transitions.dart';
import '../services/feature_tip_service.dart';
import '../widgets/coach_mark_overlay.dart';
import '../widgets/floating_glass_control.dart';
import '../widgets/plan_block_editor_sheet.dart';
import '../widgets/missed_plan_recovery_flow.dart';
import '../widgets/plan_conflict_review.dart';
import '../services/plan_drag_service.dart';
import '../services/conflict_visibility_service.dart';
import '../services/database_helper.dart';
import '../features/habits/models/habit_goal.dart';
import '../features/habits/screens/habit_detail_screen.dart';
import '../features/habits/services/habit_challenge_planning_service.dart';
import '../features/habits/services/habit_focus_launcher.dart';
import '../features/habits/services/habit_rule_resolver.dart';
import '../features/thirty_day_challenge/repositories/thirty_day_challenge_repository.dart';
import '../features/thirty_day_challenge/screens/thirty_day_challenge_screen.dart';

part 'todo_plan/todo_plan_grid_view.dart';
part 'todo_plan/todo_plan_grid_blocks.dart';

// 复用 TimeLog 的颜色和基础常量
const double kTimeAxisW = 46.0;

final GlobalKey planDragKey = GlobalKey();

class TodoPlanScreen extends StatefulWidget {
  final String username;
  final DateTime? initialDate;
  final String? initialTodoId;
  final PlanDragService? dragService;
  final PlanReviewRepository? overviewRepository;

  const TodoPlanScreen({
    super.key,
    required this.username,
    this.initialDate,
    this.initialTodoId,
    this.dragService,
    this.overviewRepository,
  });

  @override
  State<TodoPlanScreen> createState() => _TodoPlanScreenState();
}

class _TodoPlanScreenState extends State<TodoPlanScreen>
    with WidgetsBindingObserver {
  final GlobalKey _backlogActionKey = GlobalKey();
  late DateTime _focusedDate;
  bool _isLoading = true;
  List<TodoPlanBlock> _displayBlocks = [];
  List<TodoItem> _todos = [];
  List<TodoGroup> _todoGroups = [];
  List<CourseItem> _courses = [];
  List<PomodoroTag> _tags = [];
  List<PomodoroRecord> _pomodoroRecords = [];
  List<TimeLogItem> _timeLogs = [];
  HabitChallengePlanningSnapshot _habitChallenge =
      const HabitChallengePlanningSnapshot();
  String? _loadError;
  final Set<String> _mappedBlockIds = <String>{};
  int _loadGeneration = 0, _overviewRevision = 0;
  bool _overviewReady = false;
  late PlanDragService _dragService;
  PlanDragChange? _lastDrag;
  bool _dragBusy = false;
  bool _dragForeground = true;
  int _dragGeneration = 0, _undoCheck = 0;
  DateTime? _loadedDate;
  String? _runningPlanId;
  Timer? _undoExpiry;
  ScaffoldFeatureController<SnackBar, SnackBarClosedReason>? _dragNotice;
  Future<List<TodoItem>>? _planningTodosRead;
  Future<List<TodoGroup>>? _planningGroupsRead;
  Future<List<CourseItem>>? _planningCoursesRead;
  Future<List<PomodoroTag>>? _planningTagsRead;

  bool _showCoachMarks = false;

  @override
  void initState() {
    super.initState();
    _dragService = widget.dragService ?? PlanDragService();
    WidgetsBinding.instance.addObserver(this);
    final now = DateTime.now();
    final initial = widget.initialDate ?? now;
    _focusedDate = DateTime(initial.year, initial.month, initial.day);
    StorageService.scopedDataRefreshNotifier.addListener(_onScopedDataRefresh);
    ThirtyDayChallengeRepository.activityRevision.addListener(
      _onChallengeActivityChanged,
    );
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
    _clearDragHistory();
    WidgetsBinding.instance.removeObserver(this);
    StorageService.scopedDataRefreshNotifier.removeListener(
      _onScopedDataRefresh,
    );
    ThirtyDayChallengeRepository.activityRevision.removeListener(
      _onChallengeActivityChanged,
    );
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _dragForeground = state == AppLifecycleState.resumed;
    _undoExpiry?.cancel();
    if (state == AppLifecycleState.resumed) {
      _invalidatePlanningLookupReads();
      unawaited(_loadData());
      unawaited(_checkUndo());
    }
  }

  @override
  void didUpdateWidget(covariant TodoPlanScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.username != widget.username) {
      _invalidatePlanningLookupReads();
    }
    if (oldWidget.username != widget.username ||
        oldWidget.initialDate != widget.initialDate ||
        oldWidget.dragService != widget.dragService) {
      _clearDragHistory();
      _dragService = widget.dragService ?? PlanDragService();
      final date = widget.initialDate ?? _dragService.now;
      _focusedDate = DateTime(date.year, date.month, date.day);
      _loadedDate = null;
      unawaited(_loadData());
    }
  }

  void _clearDragHistory() {
    ++_dragGeneration;
    ++_undoCheck;
    _lastDrag = null;
    _undoExpiry?.cancel();
    _dragNotice?.close();
    _dragNotice = null;
  }

  void _notice(String text, {PlanDragChange? change}) {
    _dragNotice?.close();
    _dragNotice = ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 6),
        persist: false,
        behavior: SnackBarBehavior.floating,
        margin: EdgeInsets.fromLTRB(
          12,
          0,
          max(72, MediaQuery.sizeOf(context).width - 432),
          max(
            12,
            MediaQuery.sizeOf(context).height -
                floatingGlassTopBarHeight(context) -
                180,
          ),
        ),
        content: Text(text, maxLines: 3, overflow: TextOverflow.ellipsis),
        action: change == null
            ? null
            : SnackBarAction(
                label: '撤销',
                onPressed: () => unawaited(_undoDrag(change)),
              ),
      ),
    );
    final notice = _dragNotice;
    notice?.closed.then((_) {
      if (_dragNotice == notice) _dragNotice = null;
    });
  }

  String _dragTime(int value) =>
      AppTimeFormats.dateFormatter('HH:mm')
          .format(DateTime.fromMillisecondsSinceEpoch(value));

  Future<void> _checkUndo() async {
    final change = _lastDrag;
    if (change == null || _dragBusy || !_dragForeground) return;
    final check = ++_undoCheck;
    try {
      await _dragService.validateUndo(change);
      if (!mounted ||
          check != _undoCheck ||
          _lastDrag != change ||
          !_dragForeground) {
        return;
      }
      _undoExpiry?.cancel();
      final now = _dragService.now;
      final midnight = DateTime(now.year, now.month, now.day + 1);
      final ends = [
        midnight.millisecondsSinceEpoch,
        change.before.block.endTime,
        change.after.block.endTime,
      ]..sort();
      _undoExpiry = Timer(
        DateTime.fromMillisecondsSinceEpoch(ends.first).difference(now),
        () => unawaited(_checkUndo()),
      );
    } on PlanDragException catch (error) {
      if (mounted &&
          check == _undoCheck &&
          _lastDrag == change &&
          error.stale) {
        setState(_clearDragHistory);
      }
    }
  }

  Future<void> _saveDrag(PlanDragSnapshot original, PlanDragTimes times) async {
    if (_dragBusy) return;
    final generation = _dragGeneration;
    final service = _dragService;
    setState(() => _dragBusy = true);
    _undoExpiry?.cancel();
    try {
      final change = await service.save(original, times);
      if (!mounted || generation != _dragGeneration || change == null) return;
      setState(() => _lastDrag = change);
      final before = change.before.block;
      final after = change.after.block;
      _notice(
        '已调整「${after.titleSnapshot ?? '规划'}」\n'
        '${_dragTime(before.startTime)}–${_dragTime(before.endTime)} → '
        '${_dragTime(after.startTime)}–${_dragTime(after.endTime)}',
        change: change,
      );
    } catch (error) {
      if (mounted && generation == _dragGeneration) {
        _notice(error is PlanDragException ? error.message : '保存失败，请重试');
      }
    } finally {
      if (mounted) {
        setState(() => _dragBusy = false);
        await _loadData();
        unawaited(_checkUndo());
      }
    }
  }

  Future<void> _undoDrag(PlanDragChange change) async {
    if (_dragBusy || change != _lastDrag) return;
    final generation = _dragGeneration;
    final service = _dragService;
    setState(() => _dragBusy = true);
    _undoExpiry?.cancel();
    try {
      await service.undo(change);
      if (mounted && generation == _dragGeneration && change == _lastDrag) {
        setState(_clearDragHistory);
        _notice('已恢复原时段');
      }
    } catch (error) {
      if (mounted && generation == _dragGeneration) {
        if (error is PlanDragException && error.stale) {
          setState(_clearDragHistory);
        }
        _notice(error is PlanDragException ? error.message : '撤销失败，请重试');
      }
    } finally {
      if (mounted) {
        setState(() => _dragBusy = false);
        await _loadData();
        unawaited(_checkUndo());
      }
    }
  }

  void _onChallengeActivityChanged() {
    if (!mounted) return;
    unawaited(_loadData());
  }

  void _onScopedDataRefresh() {
    if (!mounted) return;
    final signal = StorageService.scopedDataRefreshNotifier.value;
    if (signal.affects(DataRefreshDomain.todos)) _planningTodosRead = null;
    if (signal.affects(DataRefreshDomain.todoGroups)) {
      _planningGroupsRead = null;
    }
    if (signal.affects(DataRefreshDomain.courses)) _planningCoursesRead = null;
    if (signal.affects(DataRefreshDomain.pomodoro)) _planningTagsRead = null;
    if (signal.affects(DataRefreshDomain.todos) ||
        signal.affects(DataRefreshDomain.todoGroups) ||
        signal.affects(DataRefreshDomain.courses) ||
        signal.affects(DataRefreshDomain.fixedSchedules) ||
        signal.affects(DataRefreshDomain.planBlocks) ||
        signal.affects(DataRefreshDomain.pomodoro) ||
        signal.affects(DataRefreshDomain.habits) ||
        signal.affects(DataRefreshDomain.timeLogs)) {
      unawaited(_loadData());
    }
  }

  void _invalidatePlanningLookupReads() {
    _planningTodosRead = null;
    _planningGroupsRead = null;
    _planningCoursesRead = null;
    _planningTagsRead = null;
  }

  Future<void> _loadData() async {
    if (!mounted) return;
    final loadGeneration = ++_loadGeneration;
    final focusedDate = _focusedDate;
    setState(() {
      _overviewReady = false;
      _isLoading = _loadedDate != focusedDate;
      _loadError = null;
    });
    late final List<dynamic> results;
    try {
      if ((await StorageService.getLoginSession() ?? 'default') !=
          widget.username) {
        throw const PlanDragException('账号已切换，请重新打开规划', stale: true);
      }
      results = await Future.wait([
        StorageService.getPlanBlocksByDay(widget.username, focusedDate),
        _planningTodosRead ??= StorageService.getTodos(widget.username),
        _planningGroupsRead ??= StorageService.getTodoGroups(widget.username),
        _planningCoursesRead ??= CourseService.getAllCourses(widget.username),
        _planningTagsRead ??= PomodoroService.getTags(),
        const PlanExecutionRepository().read(widget.username, focusedDate),
        PomodoroService.loadRunState(),
        _loadHabitChallengeSnapshot(),
      ]);
      if ((await StorageService.getLoginSession() ?? 'default') !=
          widget.username) {
        throw const PlanDragException('账号已切换，请重新打开规划', stale: true);
      }
    } catch (error) {
      _invalidatePlanningLookupReads();
      debugPrint('TodoPlan load failed: $error');
      if (mounted && loadGeneration == _loadGeneration) {
        setState(() {
          _isLoading = false;
          _loadError = error is PlanDragException
              ? error.message
              : '规划或实际记录读取失败，请重试';
          if (error is PlanDragException && error.stale) _clearDragHistory();
        });
      }
      return;
    }

    if (!mounted || loadGeneration != _loadGeneration) return;

    final blocks = (results[0] as List<TodoPlanBlock>)
        .where((b) => !b.isDeleted)
        .toList();
    final todos = (results[1] as List<TodoItem>)
        .where((t) => !t.isDeleted)
        .toList();
    final todoGroups = (results[2] as List<TodoGroup>)
        .where((g) => !g.isDeleted)
        .toList();
    final courses = (results[3] as List<CourseItem>)
        .where((c) => !c.isDeleted)
        .toList();
    final tags = results[4] as List<PomodoroTag>;
    final execution = results[5] as PlanExecutionData;
    final records = execution.records;
    _PlanActualRecordIndex? actualRecordIndex;

    // 自动标记过期未完成的规划块为 missed
    final now = _dragService.now.millisecondsSinceEpoch;
    final missedBlocks = <TodoPlanBlock>[];
    for (final b in blocks) {
      if (b.status != TodoPlanStatus.planned &&
          b.status != TodoPlanStatus.reminded) {
        continue;
      }
      final actualSeconds = records.isEmpty
          ? max(b.actualFocusSeconds, 0)
          : (actualRecordIndex ??= _PlanActualRecordIndex(
              blocks,
              records,
            )).secondsFor(b);
      if (actualSeconds <= 0 && b.endTime < now) {
        b.status = TodoPlanStatus.missed;
        b.markAsChanged();
        missedBlocks.add(b);
      }
    }
    if (missedBlocks.isNotEmpty) {
      await StorageService.savePlanBlocks(widget.username, missedBlocks);
    }

    if (!mounted || loadGeneration != _loadGeneration) return;

    final habitChallenge = results[7] as HabitChallengePlanningSnapshot;
    final mappedBlocks = _buildMappedBlocks(
      todos,
      courses,
      blocks,
      habitChallenge,
    );
    final mappedBlockIds = mappedBlocks.map((block) => block.id).toSet();
    final displayBlocks = [...blocks, ...mappedBlocks]
      ..sort((a, b) => a.startTime.compareTo(b.startTime));

    setState(() {
      _displayBlocks = displayBlocks;
      _todos = todos;
      _todoGroups = todoGroups;
      _courses = courses;
      _tags = tags;
      _pomodoroRecords = records;
      _timeLogs = execution.logs;
      _habitChallenge = habitChallenge;
      final run = results[6] as PomodoroRunState?;
      _runningPlanId = run?.phase == PomodoroPhase.focusing
          ? run?.planBlockId
          : null;
      _loadedDate = focusedDate;
      _mappedBlockIds
        ..clear()
        ..addAll(mappedBlockIds);
      _isLoading = false;
      _overviewReady = true;
      _overviewRevision++;
    });
    unawaited(_checkUndo());
  }

  Future<HabitChallengePlanningSnapshot> _loadHabitChallengeSnapshot() async {
    try {
      final db = await DatabaseHelper.instance.databaseForUser(widget.username);
      return await HabitChallengePlanningService.readFromDatabase(
        db,
        username: widget.username,
      );
    } catch (_) {
      return const HabitChallengePlanningSnapshot();
    }
  }

  List<TodoPlanBlock> _buildMappedBlocks(
    List<TodoItem> todos,
    List<CourseItem> courses,
    List<TodoPlanBlock> existingBlocks,
    HabitChallengePlanningSnapshot habitChallenge,
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
      mapped.add(
        TodoPlanBlock(
          id: 'mapped_course_${course.uuid}',
          todoId: 'mapped_course_${course.uuid}',
          titleSnapshot: '课程：${course.courseName}',
          startTime: start.millisecondsSinceEpoch,
          endTime: end.millisecondsSinceEpoch,
          plannedMinutes: minutes,
          status: TodoPlanStatus.planned,
          source: TodoPlanSource.calendar,
          remark: course.roomName,
        ),
      );
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

      mapped.add(
        TodoPlanBlock(
          id: 'mapped_todo_${todo.id}',
          todoId: todo.id,
          titleSnapshot: todo.title,
          startTime: start.millisecondsSinceEpoch,
          endTime: end.millisecondsSinceEpoch,
          plannedMinutes: minutes,
          status: todo.isDone
              ? TodoPlanStatus.finished
              : TodoPlanStatus.planned,
          source: TodoPlanSource.calendar,
          remark: todo.remark,
        ),
      );
    }

    mapped.addAll(
      HabitChallengePlanningService.buildMappedBlocksForDay(
        dayStart: _focusedDate,
        snapshot: habitChallenge,
        todos: todos,
      ),
    );

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
      _clearDragHistory();
      _focusedDate = DateTime(
        _focusedDate.year,
        _focusedDate.month,
        _focusedDate.day - 1,
      );
    });
    unawaited(_loadData());
  }

  void _nextDay() {
    setState(() {
      _clearDragHistory();
      _focusedDate = DateTime(
        _focusedDate.year,
        _focusedDate.month,
        _focusedDate.day + 1,
      );
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
        _clearDragHistory();
        _focusedDate = picked;
      });
      unawaited(_loadData());
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final displayBlocks = _displayBlocks;
    final topBarHeight = floatingGlassTopBarHeight(context);
    final compactDateNavigation =
        MediaQuery.sizeOf(context).width < 360 ||
        MediaQuery.textScalerOf(context).scale(18) > 24;
    final shortDate =
        MediaQuery.sizeOf(context).width < 400 || compactDateNavigation;
    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      extendBodyBehindAppBar: true,
      appBar: FloatingGlassAppBar(
        flexibleSpace: const FloatingGlassTopBarBackground(),
        leadingWidth: 56,
        titleSpacing: 0,
        actionsPadding: const EdgeInsets.only(right: 4),
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!compactDateNavigation)
              IconButton(
                tooltip: '前一天',
                icon: const Icon(Icons.chevron_left),
                onPressed: _prevDay,
              ),
            Flexible(
              child: Tooltip(
                message: AppTimeFormats.dateFormatter('yyyy年M月d日')
                    .format(_focusedDate),
                child: GestureDetector(
                  onTap: _pickDate,
                  child: Text(
                    AppTimeFormats.dateFormatter(shortDate ? 'M/d' : 'MM月dd日')
                        .format(_focusedDate),
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                ),
              ),
            ),
            if (!compactDateNavigation)
              IconButton(
                tooltip: '后一天',
                icon: const Icon(Icons.chevron_right),
                onPressed: _nextDay,
              ),
          ],
        ),
        centerTitle: true,
        actions: [
          // Composite controls own their width; an empty indicator must not
          // acquire the app bar's automatic 48 px glass action shell.
          SizedBox(
            child: PlanConflictIndicator(
              username: widget.username,
              date: _focusedDate,
              compact: true,
              onSaved: _loadData,
            ),
          ),
          IconButton(
            key: _backlogActionKey,
            icon: const Icon(Icons.playlist_add_check_rounded),
            tooltip: '待规划',
            onPressed: () => PageTransitions.pushFromRect<void>(
              context: context,
              page: PlanBacklogScreen(
                username: widget.username,
                date: _focusedDate,
              ),
              sourceKey: _backlogActionKey,
              sourceBorderRadius: BorderRadius.circular(24),
              placeholderIcon: Icons.playlist_add_check_rounded,
            ),
          ),
          PopupMenuButton<String>(
            tooltip: '更多',
            onSelected: (value) {
              if (value == 'previous') {
                _prevDay();
              } else if (value == 'next') {
                _nextDay();
              } else if (value == 'refresh') {
                _invalidatePlanningLookupReads();
                _loadData();
              } else if (value == 'weekly') {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) =>
                        PlanWeeklyAvailabilityScreen(username: widget.username),
                  ),
                );
              } else if (value == 'drafts') {
                openPlanEditorDrafts(
                  context,
                  widget.username,
                  onSaved: () => unawaited(_loadData()),
                );
              } else {
                Navigator.of(context).push(
                  PageTransitions.material(
                    builder: (_) => PlanBlockStatsScreen(
                      username: widget.username,
                      initialDate: _focusedDate,
                      repository: widget.overviewRepository,
                      clock: () => _dragService.now,
                    ),
                  ),
                );
              }
            },
            itemBuilder: (_) => [
              if (compactDateNavigation)
                const PopupMenuItem(value: 'previous', child: Text('前一天')),
              if (compactDateNavigation)
                const PopupMenuItem(value: 'next', child: Text('后一天')),
              const PopupMenuItem(value: 'stats', child: Text('规划统计')),
              const PopupMenuItem(value: 'drafts', child: Text('规划草稿')),
              const PopupMenuItem(value: 'weekly', child: Text('每周可安排时间')),
              const PopupMenuItem(value: 'refresh', child: Text('刷新')),
            ],
          ),
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
                    PlanDayOverview(
                      username: widget.username,
                      date: _focusedDate,
                      repository: widget.overviewRepository,
                      clock: () => _dragService.now,
                      revision: _overviewRevision,
                      enabled:
                          _overviewReady &&
                          _dragForeground &&
                          (ModalRoute.of(context)?.isCurrent ?? true),
                    ),
                    PlanExecutionSummary(
                      date: _focusedDate,
                      records: _pomodoroRecords,
                      logs: _timeLogs,
                      tags: _tags,
                    ),
                    Expanded(
                      child: _PlanGridView(
                        key: ValueKey(
                          'plan-grid-${widget.username}-$_focusedDate',
                        ),
                        date: _focusedDate,
                        blocks: displayBlocks,
                        mappedBlockIds: _mappedBlockIds,
                        todos: _todos,
                        todoGroups: _todoGroups,
                        courses: _courses,
                        tags: _tags,
                        pomodoroRecords: _pomodoroRecords,
                        timeLogs: _timeLogs,
                        habitChallenge: _habitChallenge,
                        username: widget.username,
                        initialTodoId: widget.initialTodoId,
                        onRefresh: _loadData,
                        dragService: _dragService,
                        dragBusy: _dragBusy,
                        focusingPlanId: _runningPlanId,
                        onSaveDrag: _saveDrag,
                        onUndoDrag: _lastDrag == null
                            ? null
                            : () => unawaited(_undoDrag(_lastDrag!)),
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}
