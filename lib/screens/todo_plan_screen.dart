import '../widgets/plan_manual_completion_host.dart';
import '../services/plan_manual_completion_service.dart';
import 'plan_weekly_availability_screen.dart';

import 'dart:async';

import '../services/plan_review_repository.dart';
import '../widgets/plan_day_overview.dart';

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:intl/intl.dart';

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

// 复用 TimeLog 的颜色和基础常量
const double kTimeAxisW = 46.0;

final GlobalKey planDragKey = GlobalKey();
final Map<(String?, String), DateFormat> _todoPlanDateFormatters = {};

DateFormat _todoPlanDateFormat(String pattern) {
  final locale = Intl.defaultLocale;
  return _todoPlanDateFormatters.putIfAbsent((
    locale,
    pattern,
  ), () => DateFormat(pattern, locale));
}

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
      _todoPlanDateFormat('HH:mm')
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
                message: _todoPlanDateFormat('yyyy年M月d日').format(_focusedDate),
                child: GestureDetector(
                  onTap: _pickDate,
                  child: Text(
                    _todoPlanDateFormat(shortDate ? 'M/d' : 'MM月dd日')
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

class _PlanActualRecordIndex {
  late final Map<String, int> _secondsByPlanBlockId;

  _PlanActualRecordIndex(
    List<TodoPlanBlock> blocks,
    Iterable<PomodoroRecord> records,
  ) {
    final actualSeconds = PomodoroPlanFocusAllocator.actualSecondsByBlock(
      blocks: blocks,
      records: records.toList(),
    );
    _secondsByPlanBlockId = {
      for (var index = 0; index < blocks.length; index++)
        blocks[index].uuid: actualSeconds[index],
    };
  }

  int secondsFor(TodoPlanBlock block) =>
      _secondsByPlanBlockId[block.uuid] ?? max(0, block.actualFocusSeconds);
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
  final HabitChallengePlanningSnapshot habitChallenge;
  final String username;
  final String? initialTodoId;
  final VoidCallback onRefresh;
  final PlanDragService dragService;
  final bool dragBusy;
  final String? focusingPlanId;
  final Future<void> Function(PlanDragSnapshot, PlanDragTimes) onSaveDrag;
  final VoidCallback? onUndoDrag;

  const _PlanGridView({
    super.key,
    required this.date,
    required this.blocks,
    required this.mappedBlockIds,
    required this.todos,
    required this.todoGroups,
    required this.courses,
    required this.tags,
    required this.pomodoroRecords,
    required this.timeLogs,
    this.habitChallenge = const HabitChallengePlanningSnapshot(),
    required this.username,
    this.initialTodoId,
    required this.onRefresh,
    required this.dragService,
    required this.dragBusy,
    required this.focusingPlanId,
    required this.onSaveDrag,
    required this.onUndoDrag,
  });

  @override
  State<_PlanGridView> createState() => _PlanGridViewState();
}

class _PlanGridViewState extends State<_PlanGridView>
    with WidgetsBindingObserver {
  final _manualHostKey = GlobalKey<PlanManualCompletionHostState>();
  final GlobalKey _planGridPomodoroSourceKey = GlobalKey();
  final Map<String, GlobalKey> _planBlockSourceKeys = {};
  late final _manualCompletion = PlanManualCompletionService(
    clock: () => widget.dragService.now,
  );
  late Map<String, TodoItem> _todoById;
  int? _dragStartBlock;
  int? _dragEndBlock;
  int _minutesPerBlock = 15;
  PlanDragSnapshot? _gesture;
  PlanDragTimes? _preview;
  PlanDragKind? _gestureKind;
  Offset? _pointerOrigin;
  bool _saving = false;
  List<Widget>? _gridLinesCache;
  double? _gridLinesWidth;
  double? _gridLinesHourHeight;
  int? _gridLinesBlocksPerHour;
  List<Widget>? _hourLabelsCache;
  double? _hourLabelsHourHeight;
  DateTime? _executionEntriesDate;
  List<PomodoroRecord>? _executionRecordsSource;
  List<TimeLogItem>? _executionLogsSource;
  List<PlanExecutionEntry>? _executionEntriesCache;
  List<int> _hourlyExecutionLaneCountsCache = List<int>.filled(24, 1);

  @override
  void initState() {
    super.initState();
    _rebuildItemIndexes();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed && !_saving) _cancelGesture();
  }

  @override
  void didUpdateWidget(covariant _PlanGridView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.todos, widget.todos)) {
      _rebuildItemIndexes();
    }
    final gesture = _gesture;
    if (gesture == null || _saving) return;
    final latest = widget.blocks
        .where((b) => b.id == gesture.block.id)
        .firstOrNull;
    if (latest == null ||
        !gesture.matches(latest) ||
        widget.focusingPlanId == latest.id ||
        widget.dragBusy) {
      _gesture = null;
      _preview = null;
      _gestureKind = null;
      _pointerOrigin = null;
    }
  }

  void _rebuildItemIndexes() {
    final todoById = <String, TodoItem>{};
    for (final todo in widget.todos) {
      todoById.putIfAbsent(todo.id, () => todo);
    }
    _todoById = todoById;
  }

  GlobalKey _sourceKeyFor(TodoPlanBlock block) =>
      _planBlockSourceKeys.putIfAbsent(block.id, GlobalKey.new);

  List<PlanExecutionEntry> _executionEntries() {
    final cachedEntries = _executionEntriesCache;
    final cachedDate = _executionEntriesDate;
    if (cachedEntries != null &&
        cachedDate != null &&
        DateUtils.isSameDay(cachedDate, widget.date) &&
        identical(_executionRecordsSource, widget.pomodoroRecords) &&
        identical(_executionLogsSource, widget.timeLogs)) {
      return cachedEntries;
    }

    final entries = PlanExecutionEntry.forDay(
      widget.date,
      widget.pomodoroRecords,
      widget.timeLogs,
    );
    _executionEntriesDate = widget.date;
    _executionRecordsSource = widget.pomodoroRecords;
    _executionLogsSource = widget.timeLogs;
    _executionEntriesCache = entries;
    _hourlyExecutionLaneCountsCache =
        PlanExecutionEntry.hourlyTimelineLaneCounts(widget.date, entries);
    return entries;
  }

  void _beginGesture(TodoPlanBlock block, PlanDragKind kind, Offset position) {
    if (widget.dragBusy || _saving || _gesture != null) return;
    try {
      final snapshot = widget.dragService.capture(
        widget.username,
        widget.date,
        block,
      );
      setState(() {
        _gesture = snapshot;
        _gestureKind = kind;
        _pointerOrigin = position;
        _preview = PlanDragTimes(
          DateTime.fromMillisecondsSinceEpoch(block.startTime),
          DateTime.fromMillisecondsSinceEpoch(block.endTime),
        );
        _dragStartBlock = null;
        _dragEndBlock = null;
      });
    } on PlanDragException catch (error) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  void _updateGesture(Offset position, double width, double hourH) {
    final original = _gesture;
    final origin = _pointerOrigin;
    final kind = _gestureKind;
    if (original == null || origin == null || kind == null || _saving) return;
    final delta = position - origin;
    final minutes =
        delta.dx / width * 60 +
        (kind == PlanDragKind.move ? delta.dy / hourH * 60 : 0);
    final block = original.block;
    final times = PlanDragGeometry.adjust(
      date: original.date,
      original: PlanDragTimes(
        DateTime.fromMillisecondsSinceEpoch(block.startTime),
        DateTime.fromMillisecondsSinceEpoch(block.endTime),
      ),
      deltaMinutes: minutes,
      step: _minutesPerBlock,
      kind: kind,
    );
    setState(() => _preview = times);
  }

  void _cancelGesture() {
    if (!mounted || _saving) return;
    setState(() {
      _gesture = null;
      _preview = null;
      _gestureKind = null;
      _pointerOrigin = null;
      _dragStartBlock = null;
      _dragEndBlock = null;
    });
  }

  Future<void> _finishGesture() async {
    final original = _gesture;
    final times = _preview;
    if (_saving || original == null || times == null) return;
    if (times.matches(original.block)) {
      _cancelGesture();
      return;
    }
    setState(() => _saving = true);
    try {
      await widget.onSaveDrag(original, times);
    } finally {
      if (mounted) {
        _saving = false;
        _cancelGesture();
      }
    }
  }

  int get _blocksPerHour => 60 ~/ _minutesPerBlock;

  int? _getIndex(Offset pos, double width, double hourH) {
    if (pos.dy < 0 || pos.dy > 24 * hourH) return null;
    final hour = (pos.dy / hourH).floor().clamp(0, 23);
    final blockInHour = ((pos.dx / width) * _blocksPerHour).floor().clamp(
      0,
      _blocksPerHour - 1,
    );
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
    if (widget.dragBusy || _gesture != null) return;
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

    final startTime = widget.date.add(
      Duration(minutes: startIdx * _minutesPerBlock),
    );
    final endTime = widget.date.add(
      Duration(minutes: (endIdx + 1) * _minutesPerBlock),
    );

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
    showPlanBlockEditorPage(
      context: context,
      builder: (context) => PlanBlockEditorSheet(
        fullPage: true,
        startTime: startTime,
        endTime: endTime,
        todos: widget.todos,
        todoGroups: widget.todoGroups,
        username: widget.username,
        initialTodoId: widget.initialTodoId,
        autoFillEstimateOnTodoChange: autoFillEstimateOnTodoChange,
        onSaved: widget.onRefresh,
        openPomodoro: (planBlock, todo) => PageTransitions.pushFromRect<void>(
          context: context,
          sourceKey: _planGridPomodoroSourceKey,
          placeholderIcon: Icons.timer_outlined,
          page: PomodoroScreen(
            username: widget.username,
            initialEntry: PomodoroEntryIntent.forPlanBlock(
              boundTodo: todo,
              planBlock: planBlock,
            ),
          ),
        ),
        onManageDrafts: () => openPlanEditorDrafts(
          context,
          widget.username,
          onSaved: widget.onRefresh,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final executionEntries = _executionEntries();
    final hourlyExecutionLaneCounts = _hourlyExecutionLaneCountsCache;

    return PlanManualCompletionHost(
      key: _manualHostKey,
      onRefresh: widget.onRefresh,
      child: Column(
        children: [
          _buildGranularityBar(),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
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
                      child: Stack(children: _buildHourLabels(hourH)),
                    ),
                    // 网格
                    Expanded(
                      child: GestureDetector(
                        key: _planGridPomodoroSourceKey,
                        onPanStart: (d) =>
                            _handleDragStart(d.localPosition, gridW, hourH),
                        onPanUpdate: (d) =>
                            _handleDragUpdate(d.localPosition, gridW, hourH),
                        onPanEnd: (d) =>
                            _handleDragEnd(autoFillEstimateOnTodoChange: false),
                        onPanCancel: _cancelGesture,
                        onTapDown: (d) =>
                            _handleDragStart(d.localPosition, gridW, hourH),
                        onTapUp: (d) =>
                            _handleDragEnd(autoFillEstimateOnTodoChange: true),
                        onTapCancel: _clearRecordSelection,
                        child: Container(
                          height: totalH,
                          decoration: BoxDecoration(
                            border: Border(
                              left: BorderSide(
                                color: Colors.grey.withValues(alpha: 0.1),
                              ),
                            ),
                          ),
                          child: Stack(
                            children: [
                              ..._buildGridLines(gridW, hourH),
                              ...widget.blocks.expand(
                                (block) => _buildBlockItems(
                                  block,
                                  gridW,
                                  hourH,
                                  hourlyExecutionLaneCounts,
                                ),
                              ),
                              if (_gesture != null && _preview != null)
                                ..._buildBlockItems(
                                  _gesture!.block
                                    ..startTime =
                                        _preview!.start.millisecondsSinceEpoch
                                    ..endTime =
                                        _preview!.end.millisecondsSinceEpoch
                                    ..plannedMinutes = _preview!.minutes,
                                  gridW,
                                  hourH,
                                  hourlyExecutionLaneCounts,
                                  previewOnly: true,
                                ),
                              if (executionEntries.isNotEmpty)
                                Positioned.fill(
                                  child: PlanExecutionTimelineLayer(
                                    date: widget.date,
                                    entries: executionEntries,
                                    tags: widget.tags,
                                    hourHeight: hourH,
                                    onRecordInteraction: _clearRecordSelection,
                                  ),
                                ),
                              if (_dragStartBlock != null &&
                                  _dragEndBlock != null)
                                ..._buildDraggingBlocks(gridW, hourH),
                              _buildNowLine(gridW, hourH),
                              if (_preview != null)
                                Positioned(
                                  left: 8,
                                  right: 8,
                                  top: _preview!.start.hour >= 12 ? 8 : null,
                                  bottom: _preview!.start.hour < 12 ? 8 : null,
                                  child: IgnorePointer(
                                    child: Material(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .secondaryContainer,
                                      borderRadius: BorderRadius.circular(12),
                                      child: Padding(
                                        padding: const EdgeInsets.all(8),
                                        child: Text(
                                          _saving
                                              ? '正在保存调整…'
                                              : '${_todoPlanDateFormat('HH:mm').format(_preview!.start)} → '
                                                    '${_todoPlanDateFormat('HH:mm').format(_preview!.end)} · ${_preview!.minutes}分钟',
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                            color: Theme.of(context)
                                                .colorScheme
                                                .onSecondaryContainer,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGranularityBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
      child: Row(
        children: [
          Expanded(
            child: Wrap(
              spacing: 6,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                const Text('粒度', style: TextStyle(fontSize: 12)),
                const SizedBox(width: 8),
                SegmentedButton<int>(
                  style: ButtonStyle(
                    backgroundBuilder: (context, states, child) =>
                        child ?? const SizedBox.shrink(),
                    backgroundColor: WidgetStateProperty.resolveWith((states) {
                      return states.contains(WidgetState.selected)
                          ? Theme.of(context).colorScheme.primaryContainer
                          : Theme.of(context).colorScheme.surfaceContainerLow;
                    }),
                    foregroundColor: WidgetStateProperty.resolveWith((states) {
                      return states.contains(WidgetState.selected)
                          ? Theme.of(context).colorScheme.onPrimaryContainer
                          : Theme.of(context).colorScheme.onSurfaceVariant;
                    }),
                    overlayColor: WidgetStatePropertyAll(
                      Theme.of(context).colorScheme.primary
                          .withValues(alpha: 0.12),
                    ),
                    shape: const WidgetStatePropertyAll(
                      RoundedRectangleBorder(
                        borderRadius: BorderRadius.all(Radius.circular(12)),
                      ),
                    ),
                    padding: const WidgetStatePropertyAll(
                      EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                  ),
                  segments: const [
                    ButtonSegment(value: 5, label: Text('5')),
                    ButtonSegment(value: 10, label: Text('10')),
                    ButtonSegment(value: 15, label: Text('15')),
                    ButtonSegment(value: 30, label: Text('30')),
                  ],
                  selected: {_minutesPerBlock},
                  showSelectedIcon: false,
                  onSelectionChanged: (value) {
                    if (widget.dragBusy || _gesture != null) return;
                    setState(() {
                      _minutesPerBlock = value.first;
                      _dragStartBlock = null;
                      _dragEndBlock = null;
                    });
                  },
                ),
                const SizedBox(width: 6),
                Text(
                  '分钟',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
              ],
            ),
          ),
          if (widget.dragBusy)
            const SizedBox(
              width: 36,
              height: 24,
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
          if (!widget.dragBusy && widget.onUndoDrag != null)
            IconButton(
              key: const ValueKey('plan-drag-undo'),
              tooltip: '撤销上次调整',
              onPressed: widget.onUndoDrag,
              icon: const Icon(Icons.undo_rounded),
            ),
        ],
      ),
    );
  }

  List<Widget> _buildGridLines(double width, double hourH) {
    final blocksPerHour = _blocksPerHour;
    final cachedLines = _gridLinesCache;
    if (cachedLines != null &&
        _gridLinesWidth == width &&
        _gridLinesHourHeight == hourH &&
        _gridLinesBlocksPerHour == blocksPerHour) {
      return cachedLines;
    }

    final lines = <Widget>[];
    for (int h = 0; h <= 24; h++) {
      lines.add(
        Positioned(
          top: h * hourH,
          left: 0,
          right: 0,
          height: 1,
          child: Container(color: Colors.grey.withValues(alpha: 0.06)),
        ),
      );
    }
    for (int c = 1; c < blocksPerHour; c++) {
      lines.add(
        Positioned(
          top: 0,
          bottom: 0,
          left: width * c / blocksPerHour,
          width: 0.5,
          child: Container(color: Colors.grey.withValues(alpha: 0.05)),
        ),
      );
    }

    // 隐藏的指引锚点 (9:00 - 10:00)
    lines.add(
      Positioned(
        top: 9 * hourH,
        left: width / 3,
        width: width / 3,
        height: hourH,
        child: SizedBox(key: planDragKey),
      ),
    );

    _gridLinesCache = lines;
    _gridLinesWidth = width;
    _gridLinesHourHeight = hourH;
    _gridLinesBlocksPerHour = blocksPerHour;
    return lines;
  }

  List<Widget> _buildHourLabels(double hourH) {
    final cachedLabels = _hourLabelsCache;
    if (cachedLabels != null && _hourLabelsHourHeight == hourH) {
      return cachedLabels;
    }
    final labels = List<Widget>.generate(
      24,
      (hour) => Positioned(
        top: hour * hourH + 1,
        right: 6,
        height: max(1.0, hourH - 1),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerRight,
          child: Text(
            '${hour.toString().padLeft(2, '0')}:00',
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w600,
              color: Colors.grey.withValues(alpha: 0.66),
            ),
          ),
        ),
      ),
    );
    _hourLabelsCache = labels;
    _hourLabelsHourHeight = hourH;
    return labels;
  }

  List<Widget> _buildBlockItems(
    TodoPlanBlock block,
    double width,
    double hourH,
    List<int> hourlyLaneCounts, {
    bool previewOnly = false,
  }) {
    final start = DateTime.fromMillisecondsSinceEpoch(block.startTime);
    final end = DateTime.fromMillisecondsSinceEpoch(block.endTime);
    final dayStart = DateTime(
      widget.date.year,
      widget.date.month,
      widget.date.day,
    );
    final dayEnd = DateTime(dayStart.year, dayStart.month, dayStart.day + 1);
    if (!end.isAfter(dayStart) || !start.isBefore(dayEnd)) return const [];

    final clippedStart = start.isBefore(dayStart) ? dayStart : start;
    final clippedEnd = end.isAfter(dayEnd) ? dayEnd : end;
    final todo = _todoById[block.todoId];
    final isMappedBlock = widget.mappedBlockIds.contains(block.id);
    final canDrag =
        !previewOnly &&
        !isMappedBlock &&
        !widget.dragBusy &&
        PlanDragService.canAdjust(block, widget.dragService.now) &&
        widget.focusingPlanId != block.id &&
        todo != null &&
        !todo.isDone &&
        !todo.isDeleted &&
        !todo.isSkipped &&
        !ConflictVisibilityService.blocksTodoPlanning(todo);
    final hiddenAnchor = !previewOnly && _gesture?.block.id == block.id;
    final isMappedCourse = block.id.startsWith('mapped_course_');
    final isMappedHabit = HabitChallengePlanningService.isMappedHabitBlock(
      block,
    );
    final isMappedChallenge =
        HabitChallengePlanningService.isMappedChallengeBlock(block);
    final scheme = Theme.of(context).colorScheme;
    final color = isMappedCourse
        ? Colors.teal
        : isMappedHabit
        ? scheme.tertiary
        : isMappedChallenge
        ? scheme.secondary
        : (isMappedBlock ? Colors.amber.shade700 : scheme.primary);
    final icon = isMappedCourse
        ? Icons.school_rounded
        : isMappedHabit
        ? Icons.repeat_rounded
        : isMappedChallenge
        ? Icons.emoji_events_outlined
        : (isMappedBlock ? Icons.task_alt_rounded : Icons.event_note);
    final mappedBadgeLabel = isMappedCourse
        ? '课程'
        : isMappedHabit
        ? '习惯'
        : isMappedChallenge
        ? '挑战'
        : '待办';
    final widgets = <Widget>[];

    final endHour = clippedEnd.isAtSameMomentAs(dayEnd) ? 23 : clippedEnd.hour;
    for (int hour = clippedStart.hour; hour <= endHour; hour++) {
      final rowStart = DateTime(
        widget.date.year,
        widget.date.month,
        widget.date.day,
        hour,
      );
      final rowEnd = rowStart.add(const Duration(hours: 1));
      final segmentStart = clippedStart.isAfter(rowStart)
          ? clippedStart
          : rowStart;
      final segmentEnd = clippedEnd.isBefore(rowEnd) ? clippedEnd : rowEnd;
      if (!segmentEnd.isAfter(segmentStart) || hour >= 24) continue;
      final isStartSegment = segmentStart.isAtSameMomentAs(clippedStart);
      final isEndSegment = segmentEnd.isAtSameMomentAs(clippedEnd);
      final laneCount = hourlyLaneCounts[hour];
      final segmentHeight = max(1.0, hourH / laneCount - 2);
      final contentFontSize = min(11.0, max(6.0, segmentHeight * 0.72));

      final left = width * segmentStart.minute / 60;
      final segmentW = max(
        2.0,
        width * segmentEnd.difference(segmentStart).inMinutes / 60,
      );
      widgets.add(
        Positioned(
          key: ValueKey(
            '${previewOnly ? 'preview' : 'anchor'}-${block.id}-$hour',
          ),
          top: hour * hourH + 1,
          left: left + 1,
          width: max(1.0, segmentW - 2),
          height: segmentHeight,
          child: Opacity(
            opacity: hiddenAnchor ? 0 : 1,
            child: IgnorePointer(
              ignoring:
                  previewOnly ||
                  (_gesture != null && _gesture!.block.id != block.id),
              child: GestureDetector(
                key: !previewOnly && isStartSegment
                    ? _sourceKeyFor(block)
                    : ValueKey(
                        '${previewOnly ? 'plan-preview' : 'plan-drag-block'}-${block.id}-$hour',
                      ),
                onTap: widget.dragBusy || _gesture != null
                    ? null
                    : isMappedBlock
                    ? () => _openMappedBlockDetail(block)
                    : () => _showEditBlockSheet(
                        block,
                        sourceKey: _sourceKeyFor(block),
                      ),
                onLongPressStart: canDrag
                    ? (details) => _beginGesture(
                        block,
                        PlanDragKind.move,
                        details.globalPosition,
                      )
                    : null,
                onLongPressMoveUpdate: canDrag
                    ? (details) =>
                          _updateGesture(details.globalPosition, width, hourH)
                    : null,
                onLongPressEnd: canDrag
                    ? (_) => unawaited(_finishGesture())
                    : null,
                onLongPressCancel: canDrag ? _cancelGesture : null,
                onPanStart: canDrag || previewOnly
                    ? null
                    : (_) => _clearRecordSelection(),
                onPanUpdate: canDrag || previewOnly ? null : (_) {},
                onPanEnd: canDrag || previewOnly ? null : (_) {},
                child: Stack(
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(5),
                        border: Border.all(color: color.withValues(alpha: 0.4)),
                      ),
                      padding: EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: laneCount > 1 ? 0 : 1,
                      ),
                      child: segmentW < 28
                          ? const SizedBox.shrink()
                          : Row(
                              children: [
                                Icon(
                                  block.status == TodoPlanStatus.finished
                                      ? Icons.check_circle
                                      : icon,
                                  size: min(10.0, contentFontSize),
                                  color: color,
                                ),
                                const SizedBox(width: 3),
                                Expanded(
                                  child: Text(
                                    block.titleSnapshot ??
                                        todo?.title ??
                                        '未知待办',
                                    style: TextStyle(
                                      fontSize: contentFontSize,
                                      fontWeight: FontWeight.bold,
                                      color: color,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                    maxLines: 1,
                                  ),
                                ),
                                if (segmentW >
                                        100 *
                                            MediaQuery.textScalerOf(context)
                                                .scale(1) &&
                                    isMappedBlock) ...[
                                  const SizedBox(width: 4),
                                  Text(
                                    mappedBadgeLabel,
                                    style: TextStyle(
                                      fontSize: min(8.0, contentFontSize),
                                      fontWeight: FontWeight.w700,
                                      color: color.withValues(alpha: 0.72),
                                    ),
                                    maxLines: 1,
                                  ),
                                ],
                                if (segmentW >
                                    180 *
                                        MediaQuery.textScalerOf(context)
                                            .scale(1))
                                  Text(
                                    '${_todoPlanDateFormat('HH:mm').format(start)}-${_todoPlanDateFormat('HH:mm').format(end)}',
                                    style: TextStyle(
                                      fontSize: min(8.0, contentFontSize),
                                      color: color.withValues(alpha: 0.72),
                                    ),
                                    maxLines: 1,
                                  ),
                              ],
                            ),
                    ),
                    if (isStartSegment &&
                        !isMappedBlock &&
                        (canDrag || previewOnly))
                      Positioned(
                        left: 0,
                        top: 0,
                        bottom: 0,
                        width: 12,
                        child: GestureDetector(
                          key: ValueKey(
                            '${previewOnly ? 'preview-' : ''}plan-resize-start-${block.id}',
                          ),
                          behavior: HitTestBehavior.translucent,
                          dragStartBehavior: DragStartBehavior.down,
                          onHorizontalDragStart: canDrag
                              ? (details) => _beginGesture(
                                  block,
                                  PlanDragKind.resizeStart,
                                  details.globalPosition,
                                )
                              : null,
                          onHorizontalDragUpdate: canDrag
                              ? (details) => _updateGesture(
                                  details.globalPosition,
                                  width,
                                  hourH,
                                )
                              : null,
                          onHorizontalDragEnd: canDrag
                              ? (_) => unawaited(_finishGesture())
                              : null,
                          onHorizontalDragCancel: canDrag
                              ? _cancelGesture
                              : null,
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Container(width: 3, color: color),
                          ),
                        ),
                      ),
                    if (isEndSegment &&
                        !isMappedBlock &&
                        (canDrag || previewOnly))
                      Positioned(
                        right: 0,
                        top: 0,
                        bottom: 0,
                        width: 12,
                        child: GestureDetector(
                          key: ValueKey(
                            '${previewOnly ? 'preview-' : ''}plan-resize-end-${block.id}',
                          ),
                          behavior: HitTestBehavior.translucent,
                          dragStartBehavior: DragStartBehavior.down,
                          onHorizontalDragStart: canDrag
                              ? (details) => _beginGesture(
                                  block,
                                  PlanDragKind.resizeEnd,
                                  details.globalPosition,
                                )
                              : null,
                          onHorizontalDragUpdate: canDrag
                              ? (details) => _updateGesture(
                                  details.globalPosition,
                                  width,
                                  hourH,
                                )
                              : null,
                          onHorizontalDragEnd: canDrag
                              ? (_) => unawaited(_finishGesture())
                              : null,
                          onHorizontalDragCancel: canDrag
                              ? _cancelGesture
                              : null,
                          child: Align(
                            alignment: Alignment.centerRight,
                            child: Container(width: 3, color: color),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
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
      widgets.add(
        Positioned(
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
        ),
      );
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
            decoration: const BoxDecoration(
              color: Colors.red,
              shape: BoxShape.circle,
            ),
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
            builder: (_) => CourseDetailScreen(course: course),
          ),
        );
      }
      return;
    }

    if (block.id.startsWith('mapped_todo_')) {
      final todoId = block.id.substring('mapped_todo_'.length);
      final todo = _todoById[todoId];
      if (todo != null) {
        Navigator.of(context).push(
          PageTransitions.material(
            builder: (_) => TodoDetailScreen(todo: todo),
          ),
        );
      }
      return;
    }

    if (HabitChallengePlanningService.isMappedHabitBlock(block)) {
      final habitUuid = HabitChallengePlanningService.habitUuidFromBlock(block);
      final goal = widget.habitChallenge.goals.cast<HabitGoal?>().firstWhere(
        (g) => g?.uuid == habitUuid,
        orElse: () => null,
      );
      if (goal == null) return;
      final rules =
          widget.habitChallenge.rulesByHabitUuid[goal.uuid] ?? const [];
      final rule = HabitRuleResolver.effectiveRule(rules, widget.date);
      final start = DateTime.fromMillisecondsSinceEpoch(block.startTime);
      final end = DateTime.fromMillisecondsSinceEpoch(block.endTime);
      showAppModalBottomSheet<void>(
        context: context,
        builder: (sheetCtx) {
          final cs = Theme.of(sheetCtx).colorScheme;
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(goal.icon, style: const TextStyle(fontSize: 28)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              goal.name,
                              style: Theme.of(sheetCtx).textTheme.titleMedium
                                  ?.copyWith(fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '习惯软预留 · ${_todoPlanDateFormat('HH:mm').format(start)}–${_todoPlanDateFormat('HH:mm').format(end)} (${block.plannedMinutes} 分钟)',
                              style: Theme.of(sheetCtx).textTheme.bodySmall
                                  ?.copyWith(color: cs.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.insights_outlined, size: 18),
                          label: const Text('习惯详情'),
                          onPressed: () async {
                            Navigator.pop(sheetCtx);
                            await Navigator.of(context).push(
                              PageTransitions.material(
                                builder: (_) => HabitDetailScreen(
                                  goal: goal,
                                  username: widget.username,
                                ),
                              ),
                            );
                            widget.onRefresh();
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton.icon(
                          icon: const Icon(Icons.timer_outlined, size: 18),
                          label: const Text('开始专注'),
                          onPressed: () {
                            Navigator.pop(sheetCtx);
                            HabitFocusLauncher.open(
                              context: context,
                              username: widget.username,
                              goal: goal,
                              rule: rule,
                              onReturned: widget.onRefresh,
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      );
      return;
    }

    if (HabitChallengePlanningService.isMappedChallengeBlock(block)) {
      final taskId = HabitChallengePlanningService.challengeTaskIdFromBlock(
        block,
      );
      final challenge = widget.habitChallenge.challengeState;
      if (challenge == null || taskId == null) return;
      final task = challenge.tasks.where((t) => t.id == taskId).firstOrNull;
      if (task == null) return;
      final start = DateTime.fromMillisecondsSinceEpoch(block.startTime);
      final end = DateTime.fromMillisecondsSinceEpoch(block.endTime);
      showAppModalBottomSheet<void>(
        context: context,
        builder: (sheetCtx) {
          final cs = Theme.of(sheetCtx).colorScheme;
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Text('🎯', style: TextStyle(fontSize: 28)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              task.title,
                              style: Theme.of(sheetCtx).textTheme.titleMedium
                                  ?.copyWith(fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${challenge.challengeTitle} · ${_todoPlanDateFormat('HH:mm').format(start)}–${_todoPlanDateFormat('HH:mm').format(end)} (${block.plannedMinutes} 分钟)',
                              style: Theme.of(sheetCtx).textTheme.bodySmall
                                  ?.copyWith(color: cs.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(
                            Icons.emoji_events_outlined,
                            size: 18,
                          ),
                          label: const Text('打开挑战'),
                          onPressed: () async {
                            Navigator.pop(sheetCtx);
                            await Navigator.of(context).push(
                              PageTransitions.material(
                                builder: (_) =>
                                    const ThirtyDayChallengeScreen(),
                              ),
                            );
                            widget.onRefresh();
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton.icon(
                          icon: const Icon(Icons.timer_outlined, size: 18),
                          label: const Text('开始专注'),
                          onPressed: () {
                            Navigator.pop(sheetCtx);
                            HabitFocusLauncher.openForChallenge(
                              context: context,
                              username: widget.username,
                              challengeState: challenge,
                              task: task,
                              onReturned: widget.onRefresh,
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      );
    }
  }

  void _showEditBlockSheet(
    TodoPlanBlock block, {
    required GlobalKey sourceKey,
  }) {
    showPlanBlockEditorSheet(
      context: context,
      builder: (context) => PlanBlockEditorSheet(
        block: block,
        onRecover: block.status != TodoPlanStatus.missed
            ? null
            : () {
                if (mounted) {
                  showMissedPlanRecovery(
                    context: this.context,
                    username: widget.username,
                    sourceId: block.id,
                    onSaved: widget.onRefresh,
                  );
                }
              },
        startTime: DateTime.fromMillisecondsSinceEpoch(block.startTime),
        endTime: DateTime.fromMillisecondsSinceEpoch(block.endTime),
        todos: widget.todos,
        todoGroups: widget.todoGroups,
        username: widget.username,
        initialTodoId: block.todoId,
        onSaved: widget.onRefresh,
        openPomodoro: (planBlock, todo) => PageTransitions.pushFromRect<void>(
          context: context,
          sourceKey: sourceKey,
          placeholderIcon: Icons.timer_outlined,
          page: PomodoroScreen(
            username: widget.username,
            initialEntry: PomodoroEntryIntent.forPlanBlock(
              boundTodo: todo,
              planBlock: planBlock,
            ),
          ),
        ),
        manualCompletionService: _manualCompletion,
        onManualCompleted: (receipt) =>
            _manualHostKey.currentState?.present(receipt),
      ),
    );
  }
}
