import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../models.dart';
import '../storage_service.dart';
import '../services/pomodoro_service.dart';
import '../services/course_service.dart';
import '../services/ai_todo_chat_launcher.dart';
import '../services/ai_todo_action_executor.dart';
import '../utils/app_color_utils.dart';
import '../utils/app_dialogs.dart';
import '../utils/calendar_date_math.dart';
import '../utils/page_transitions.dart';
import '../utils/todo_recurrence_picker.dart';
import '../utils/theme_color_tokens.dart';
import '../utils/time_log_range_math.dart';
import '../widgets/app_detail_widgets.dart';

import 'dart:ui' as ui;

import 'pomodoro_screen.dart';
import 'pomodoro/pomodoro_entry_intent.dart';
import '../services/feature_tip_service.dart';
import '../services/time_log_overlap_service.dart';
import '../services/time_log_editor_save_service.dart';
import '../widgets/coach_mark_overlay.dart';
import '../widgets/floating_glass_control.dart';
import '../widgets/optional_liquid_glass_surface.dart';
import 'pomodoro/unified_tag_manager_screen.dart';
import 'time_log_save_confirmation.dart';

part 'time_log_components.dart';

/// 时间日志中展示的课程与固定日程只读占位模型
class TimeLogMappedSchedule {
  final String id;
  final String title;
  final String? subtitle;
  final int startTime; // ms
  final int endTime; // ms
  final bool isCourse;

  const TimeLogMappedSchedule({
    required this.id,
    required this.title,
    this.subtitle,
    required this.startTime,
    required this.endTime,
    required this.isCourse,
  });
}

// ══════════════════════════════════════════════════════════
// 常量
// ══════════════════════════════════════════════════════════
final GlobalKey timeLogDragKey = GlobalKey();
final GlobalKey timeLogTagKey = GlobalKey();
final GlobalKey timeLogAddKey = GlobalKey();
const double kTimeAxisW = 46.0; // 左侧时间标签列宽（固定）
const double kRowH = 52.0; // 每行（1小时）高度
const int kColsPerH = 10; // 每小时几列（60/6=10）→ 24×10=240格
const int kMinsPerCol = 6; // 每列代表多少分钟（60/10=6）
const int kTotalRows = 24; // 总行数（24小时）
const int kTotalCols = 24 * kColsPerH; // 总列数 = 240

// 周视图常量
const double kWeekTimeW = 44.0;
const double kWeekDayW = 100.0;

// 时间日志的浮动操作区采用同一套柔和圆角，避免外层胶囊和内层方形按钮
// 叠在一起后产生割裂感。
const double _timeLogActionBarRadius = 20.0;
const double _timeLogActionChipRadius = 12.0;
const double _timeLogSummaryChipHeight = 30.0;
const double _timeLogTagSidebarWidth = 78.0;

const List<String> kPalette = [
  '#EF4444',
  '#F97316',
  '#EAB308',
  '#22C55E',
  '#10B981',
  '#06B6D4',
  '#3B82F6',
  '#8B5CF6',
  '#EC4899',
  '#F43F5E',
];

Color hexColor(String hex, {double opacity = 1.0}) {
  return AppColorUtils.hexToColor(
    hex,
    fallback: const Color(0xFF607D8B),
    opacity: opacity,
  );
}

DateTime _dayStart(DateTime d) => CalendarDateMath.dateOnly(d);
int _dayEndMs(DateTime d) =>
    CalendarDateMath.dayRange(d).endExclusive.millisecondsSinceEpoch;

// ══════════════════════════════════════════════════════════
// 主题色助手
// ══════════════════════════════════════════════════════════
class _TC {
  static Color surface(BuildContext c) => Theme.of(c).colorScheme.surface;

  static Color card(BuildContext c) => Theme.of(c).brightness == Brightness.dark
      ? Theme.of(c).colorScheme.surfaceContainerLow
      : Theme.of(c).colorScheme.surfaceContainerHighest;

  static Color topBar(BuildContext c) => Theme.of(c).colorScheme.surface;

  static Color inputFill(BuildContext c) =>
      Theme.of(c).colorScheme.surfaceContainerHighest;

  static Color text(BuildContext c) => Theme.of(c).colorScheme.onSurface;

  static Color textSub(BuildContext c) =>
      Theme.of(c).colorScheme.onSurface.withValues(alpha: 0.55);

  static Color textHint(BuildContext c) =>
      Theme.of(c).colorScheme.onSurface.withValues(alpha: 0.28);

  static Color divider(BuildContext c) => Theme.of(c).dividerColor;

  static Color timeLabel(BuildContext c, {bool major = false}) => major
      ? Theme.of(c).colorScheme.onSurfaceVariant
      : Theme.of(c).colorScheme.onSurfaceVariant.withValues(alpha: 0.55);
}

// ══════════════════════════════════════════════════════════
// 视图枚举
// ══════════════════════════════════════════════════════════
enum _ViewMode { week, day }

enum _DayMode { view, edit }

enum _EntryMode { log, plan }

// ══════════════════════════════════════════════════════════
// 主屏幕
// ══════════════════════════════════════════════════════════
class TimeLogScreen extends StatefulWidget {
  final String username;
  final String? initialTagUuid; // 🚀 从搜索跳转时，自动打开对应标签的统计面板

  const TimeLogScreen({super.key, required this.username, this.initialTagUuid});

  @override
  State<TimeLogScreen> createState() => _TimeLogScreenState();
}

class _TimeLogScreenState extends State<TimeLogScreen> {
  final GlobalKey _aiAssistantActionKey = GlobalKey();
  bool _isLoading = true;
  _ViewMode _view = _ViewMode.week;
  _DayMode _dayMode = _DayMode.view;
  DateTime _focusedDate = DateTime.now();
  late DateTime _weekStart;
  bool _crossDay = false;

  List<TimeLogItem> _allLogs = [];
  List<PomodoroTag> _allTags = []; // 所有标签（包括归档）
  List<PomodoroTag> _tags = []; // 未归档标签（用于显示）
  List<PomodoroRecord> _allPomodoros = [];
  List<TodoItem> _allTodos = [];
  List<TodoGroup> _allTodoGroups = [];
  List<TodoPlanBlock> _allPlanBlocks = [];
  List<TimeLogMappedSchedule> _allMappedSchedules = [];
  _EntryMode _entryMode = _EntryMode.log;
  bool _showCoachMarks = false;
  int _loadGeneration = 0;
  bool _didOpenInitialTag = false;

  void _checkCoachMarks() async {
    if (!mounted || _showCoachMarks) return;

    final hasShown = await FeatureTipService.hasTipBeenShown('time_log_guide');
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
          targetKey: timeLogTagKey,
          title: '标签管理',
          description:
              '时间日志的标签与番茄钟的标签是**通用的**！\n你可以点击这里统一创建或管理所有标签，方便后续按类别进行专注或日志统计。',
        ),
        CoachMarkStep(
          targetKey: timeLogAddKey,
          title: '手动补录',
          description: '除了滑动创建，你也可以直接点击上方的「补录」按钮，通过精确填写时间来手动记录遗漏的专注。',
        ),
        CoachMarkStep(
          targetKey: timeLogDragKey,
          title: '滑动添加日志',
          description: '点击补录按钮后，在日历网格内的空白区域，上下滑动手指即可快速创建一条时间日志！',
        ),
      ],
      onFinish: () {
        if (mounted) {
          setState(() {
            _showCoachMarks = false;
          });
        }
        FeatureTipService.markTipShown('time_log_guide');
      },
      onSkip: () {
        if (mounted) {
          setState(() {
            _showCoachMarks = false;
          });
        }
        FeatureTipService.markTipShown('time_log_guide');
      },
    );
  }

  // 打开编辑面板
  void _editTimeLog(TimeLogItem log) {
    showAppModalBottomSheet(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      builder: (_) => TimeLogEntrySheet(
        initialStart: DateTime.fromMillisecondsSinceEpoch(log.startTime),
        initialEnd: DateTime.fromMillisecondsSinceEpoch(log.endTime),
        tags: _tags,
        timeLogs: _allLogs,
        pomodoros: _allPomodoros,
        existingLog: log,
        onSave: _saveTimeLog,
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _weekStart = CalendarDateMath.weekRange(DateTime.now()).start;
    StorageService.scopedDataRefreshNotifier.addListener(_onScopedDataRefresh);
    _loadData();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkCoachMarks();
    });
  }

  void _onScopedDataRefresh() {
    if (!mounted) return;
    final signal = StorageService.scopedDataRefreshNotifier.value;
    if (signal.affects(DataRefreshDomain.timeLogs) ||
        signal.affects(DataRefreshDomain.pomodoro) ||
        signal.affects(DataRefreshDomain.todos) ||
        signal.affects(DataRefreshDomain.todoGroups) ||
        signal.affects(DataRefreshDomain.planBlocks) ||
        signal.affects(DataRefreshDomain.courses) ||
        signal.affects(DataRefreshDomain.fixedSchedules)) {
      unawaited(_loadData());
    }
  }

  static DateTime? _courseDateTime(String date, int hhmm) {
    final parsed = DateTime.tryParse(date);
    if (parsed == null || hhmm < 0) return null;
    final hour = hhmm ~/ 100;
    final minute = hhmm % 100;
    if (hour < 0 || hour > 23 || minute < 0 || minute > 59) return null;
    return DateTime(parsed.year, parsed.month, parsed.day, hour, minute);
  }

  static List<TimeLogMappedSchedule> _buildMappedSchedules({
    required List<CourseItem> courses,
    required List<FixedScheduleItem> fixedSchedules,
  }) {
    final mapped = <TimeLogMappedSchedule>[];

    for (final course in courses) {
      if (course.isDeleted) continue;
      final start = _courseDateTime(course.date, course.startTime);
      final end = _courseDateTime(course.date, course.endTime);
      if (start == null || end == null || !end.isAfter(start)) continue;

      final room = course.roomName.trim();
      final teacher = course.teacherName.trim();
      final subtitle = room.isNotEmpty
          ? (teacher.isNotEmpty ? '$room · $teacher' : room)
          : (teacher.isNotEmpty ? teacher : null);

      mapped.add(
        TimeLogMappedSchedule(
          id: 'course_${course.uuid}',
          title: course.courseName,
          subtitle: subtitle,
          startTime: start.millisecondsSinceEpoch,
          endTime: end.millisecondsSinceEpoch,
          isCourse: true,
        ),
      );
    }

    for (final item in fixedSchedules) {
      if (item.isDeleted || item.status == FixedScheduleStatus.cancelled) {
        continue;
      }
      final startMs = item.startTime;
      if (startMs == null) continue;
      final endMs = item.endTime ?? (startMs + 60 * 60 * 1000);
      if (endMs <= startMs) continue;

      final loc = item.location?.trim();
      mapped.add(
        TimeLogMappedSchedule(
          id: 'fixed_${item.id}',
          title: item.title,
          subtitle: (loc != null && loc.isNotEmpty) ? loc : null,
          startTime: startMs,
          endTime: endMs,
          isCourse: false,
        ),
      );
    }

    mapped.sort((a, b) => a.startTime.compareTo(b.startTime));
    return mapped;
  }

  @override
  void dispose() {
    StorageService.scopedDataRefreshNotifier.removeListener(
      _onScopedDataRefresh,
    );
    super.dispose();
  }

  Future<void> _loadData({bool forceSync = false}) async {
    if (!mounted) return;
    final loadGeneration = ++_loadGeneration;
    setState(() => _isLoading = true);

    if (forceSync) {
      try {
        await StorageService.syncData(
          widget.username,
          syncTimeLogs: true,
          syncScreenTime: false,
          syncTodos: false,
          syncCountdowns: false,
          syncPomodoro: false,
          syncPlanBlocks: false,
          syncFixedSchedules: false,
          syncHabits: false,
          syncFinance: false,
        );
      } catch (e) {
        if (mounted) {
          AppSnackBars.error(context, '同步失败: $e');
        }
      }
    }

    // 🚀 核心优化：并行加载所有统计所需数据
    late final List<dynamic> results;
    try {
      results = await Future.wait([
        PomodoroService.getTags(),
        StorageService.getTimeLogs(widget.username),
        PomodoroService.getRecords(),
        StorageService.getTodos(widget.username),
        StorageService.getPlanBlocks(widget.username),
        StorageService.getTodoGroups(widget.username),
        CourseService.getAllCourses(widget.username),
        StorageService.getFixedSchedules(widget.username),
      ]);
    } catch (error) {
      debugPrint('TimeLog load failed: $error');
      if (mounted && loadGeneration == _loadGeneration) {
        setState(() => _isLoading = false);
      }
      return;
    }

    if (!mounted || loadGeneration != _loadGeneration) return;

    final courses = (results[6] as List<CourseItem>)
        .where((c) => !c.isDeleted)
        .toList();
    final fixedSchedules = (results[7] as List<FixedScheduleItem>)
        .where((f) => !f.isDeleted)
        .toList();
    final mappedSchedules = _buildMappedSchedules(
      courses: courses,
      fixedSchedules: fixedSchedules,
    );

    setState(() {
      _allTags = results[0] as List<PomodoroTag>;
      _tags = _allTags.where((t) => !t.isArchived).toList();
      _allLogs = (results[1] as List<TimeLogItem>)
          .where((l) => !l.isDeleted)
          .toList();
      _allPomodoros = results[2] as List<PomodoroRecord>;
      _allTodos = (results[3] as List<TodoItem>)
          .where((t) => !t.isDeleted)
          .toList();
      _allPlanBlocks = (results[4] as List<TodoPlanBlock>)
          .where((p) => !p.isDeleted)
          .toList();
      _allTodoGroups = (results[5] as List<TodoGroup>)
          .where((g) => !g.isDeleted)
          .toList();
      _allMappedSchedules = mappedSchedules;
      _isLoading = false;
    });

    // 🚀 如果从搜索跳转并指定了标签，数据加载完成后自动弹出统计面板
    if (widget.initialTagUuid != null && !_didOpenInitialTag) {
      _didOpenInitialTag = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final tag = _tags
            .where((t) => t.uuid == widget.initialTagUuid)
            .firstOrNull;
        if (tag != null && mounted) _showTagDetail(tag);
      });
    }
  }

  late final TimeLogEditorSaveService _timeLogEditorSaveService =
      TimeLogEditorSaveService(
        (username, logs) =>
            StorageService.saveTimeLogs(username, logs, sync: true),
        (username) => StorageService.getTimeLogs(username),
      );

  Future<TimeLogEditorSaveResult> _saveTimeLog(TimeLogItem log) async {
    final result = await _timeLogEditorSaveService.save(widget.username, log);
    if (!result.isSaved || !mounted) return result;

    setState(() {
      _allLogs = [
        for (final existing in _allLogs)
          if (existing.id != log.id) existing,
        log,
      ]..sort((a, b) => b.startTime.compareTo(a.startTime));
    });

    if (result.disposition == TimeLogEditorSaveDisposition.savedAfterReadBack) {
      StorageService.triggerRefresh(const {DataRefreshDomain.timeLogs});
      unawaited(_syncRecoveredTimeLog());
      AppSnackBars.showSnackBar(
        context,
        const SnackBar(content: Text('已确认保存在本机，云端同步状态尚未确认。')),
      );
    }
    return result;
  }

  Future<void> _syncRecoveredTimeLog() async {
    try {
      await StorageService.syncData(
        widget.username,
        syncTimeLogs: true,
        syncScreenTime: false,
        syncTodos: false,
        syncCountdowns: false,
        syncPomodoro: false,
        syncPlanBlocks: false,
        syncFixedSchedules: false,
        syncHabits: false,
        syncFinance: false,
      );
    } catch (error) {
      debugPrint('Recovered time log sync failed: $error');
    }
  }

  void _deleteLog(String id) async {
    await StorageService.deleteTimeLogGlobally(widget.username, id);
    _loadData();
  }

  Future<void> _addPlanBlock(TodoPlanBlock block) async {
    await StorageService.savePlanBlocks(widget.username, [block]);
    await _loadData();
  }

  void _deletePlanBlock(String id) async {
    await StorageService.deletePlanBlockGlobally(widget.username, id);
    _loadData();
  }

  void _goDay(DateTime d, {_DayMode mode = _DayMode.view}) => setState(() {
    _focusedDate = d;
    _view = _ViewMode.day;
    _dayMode = mode;
  });

  void _goWeek() => setState(() => _view = _ViewMode.week);

  Widget _buildTitleChevron(IconData icon, VoidCallback onPressed) {
    return IconButton(
      icon: Icon(icon, size: 20),
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: 24, height: 32),
      visualDensity: VisualDensity.compact,
      splashRadius: 16,
      onPressed: onPressed,
    );
  }

  Widget _buildTitle() {
    if (_view == _ViewMode.week) {
      final we = CalendarDateMath.addDays(_weekStart, 6);
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildTitleChevron(
            Icons.chevron_left,
            () => setState(
              () => _weekStart = CalendarDateMath.addDays(_weekStart, -7),
            ),
          ),
          const SizedBox(width: 4),
          Flexible(
            child: GestureDetector(
              onTap: () => setState(
                () =>
                    _weekStart = CalendarDateMath.weekRange(DateTime.now())
                        .start,
              ),
              child: Text(
                '${AppTimeFormats.monthDaySlash(_weekStart)} - ${AppTimeFormats.monthDaySlash(we)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          const SizedBox(width: 4),
          _buildTitleChevron(
            Icons.chevron_right,
            () => setState(
              () => _weekStart = CalendarDateMath.addDays(_weekStart, 7),
            ),
          ),
        ],
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildTitleChevron(
          Icons.chevron_left,
          () => setState(
            () => _focusedDate = CalendarDateMath.addDays(
              CalendarDateMath.dateOnly(_focusedDate),
              -1,
            ),
          ),
        ),
        Flexible(
          child: GestureDetector(
            onTap: () async {
              final p = await showAppDatePicker(
                context: context,
                initialDate: _focusedDate,
                firstDate: DateTime(2020),
                lastDate: CalendarDateMath.addDays(
                  CalendarDateMath.dateOnly(DateTime.now()),
                  1,
                ),
              );
              if (p != null) setState(() => _focusedDate = p);
            },
            child: Text(
              AppTimeFormats.monthDayCn(_focusedDate),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
          ),
        ),
        _buildTitleChevron(
          Icons.chevron_right,
          () => setState(
            () => _focusedDate = CalendarDateMath.addDays(
              CalendarDateMath.dateOnly(_focusedDate),
              1,
            ),
          ),
        ),
      ],
    );
  }

  List<Widget> _buildActions() {
    final acts = <Widget>[];
    // 保证窄屏优先保留必要操作（标签管理、刷新）。AI 助手是低优先级
    // 入口，避免它占用顶栏空间后把其它按钮挤出可见区域。
    final showAiAssistant = MediaQuery.sizeOf(context).width >= 480;
    if (_view == _ViewMode.day) {
      // 只保留标签管理，不再有切换图标
      if (_dayMode == _DayMode.edit) {
        acts.add(
          IconButton(
            key: timeLogTagKey,
            icon: const Icon(Icons.label_outline, size: 20),
            onPressed: _showTagManager,
            tooltip: '标签管理',
          ),
        );
      }
    }
    if (showAiAssistant) {
      acts.add(
        IconButton(
          key: _aiAssistantActionKey,
          icon: const Icon(Icons.smart_toy_outlined, size: 20),
          tooltip: 'AI专注助手',
          onPressed: _openAiAssistant,
        ),
      );
    }
    acts.add(
      IconButton(
        icon: const Icon(Icons.refresh, size: 20),
        onPressed: () => _loadData(forceSync: true),
      ),
    );
    return acts;
  }

  Future<void> _openAiAssistant() async {
    try {
      final results = await Future.wait<dynamic>([
        StorageService.getTodos(widget.username),
        StorageService.getTodoGroups(widget.username),
        CourseService.getAllCourses(widget.username),
        StorageService.getCountdowns(widget.username),
      ]);
      if (!mounted) return;
      await AiTodoChatLauncher.open(
        context,
        username: widget.username,
        todos: (results[0] as List<TodoItem>)
            .where((t) => !t.isDeleted)
            .toList(),
        todoGroups: (results[1] as List<TodoGroup>)
            .where((g) => !g.isDeleted)
            .toList(),
        courses: (results[2] as List<CourseItem>)
            .where((c) => !c.isDeleted)
            .toList(),
        countdowns: (results[3] as List<CountdownItem>)
            .where((c) => !c.isDeleted)
            .toList(),
        pomodoroTags: _tags,
        timeLogs: _allLogs,
        pomodoroRecords: _allPomodoros,
        sourceKey: _aiAssistantActionKey,
        onTodosBatchAction:
            (
              inserted,
              updated, {
              expectedTodoBaselines,
              expectedSeriesMembership,
            }) async {
              final allTodos = await StorageService.getTodos(widget.username);
              final merged = AiTodoActionExecutor.mergeTodoUpdates(
                allTodos,
                inserted,
                updated,
              );
              await StorageService.saveTodos(
                widget.username,
                merged,
                expectedTodoBaselines: expectedTodoBaselines,
                expectedSeriesMembership: expectedSeriesMembership,
              );
            },
      );
    } catch (e) {
      if (mounted) {
        AppSnackBars.error(context, '打开AI助手失败: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final contentTopInset = floatingGlassTopBarHeight(context) + 34;
    return PopScope(
      canPop: _view == _ViewMode.week,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _view != _ViewMode.week) {
          _goWeek();
        }
      },
      child: Scaffold(
        backgroundColor: _TC.surface(context),
        extendBodyBehindAppBar: true,
        appBar: FloatingGlassAppBar(
          flexibleSpace: const FloatingGlassTopBarBackground(),
          leading: _view == _ViewMode.day
              ? IconButton(
                  icon: const Icon(Icons.arrow_back_ios_new, size: 18),
                  onPressed: _goWeek,
                )
              : null,
          title: _buildTitle(),
          centerTitle: true,
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(34),
            child: Container(
              height: 34,
              color: _TC.topBar(context),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _ViewTab(
                    label: '周',
                    selected: _view == _ViewMode.week,
                    onTap: () {
                      if (_view != _ViewMode.week) _goWeek();
                    },
                  ),
                  const SizedBox(width: 6),
                  _ViewTab(
                    label: '日',
                    selected: _view == _ViewMode.day,
                    onTap: () {
                      if (_view != _ViewMode.day) {
                        _goDay(DateTime.now(), mode: _DayMode.view);
                      }
                    },
                  ),
                ],
              ),
            ),
          ),
          actions: _buildActions(),
          backgroundColor: _TC.topBar(context),
          elevation: 0,
          surfaceTintColor: Colors.transparent,
        ),
        body: Padding(
          padding: EdgeInsets.only(top: contentTopInset),
          child: _isLoading
              ? _buildSkeleton()
              : _view == _ViewMode.week
              ? _WeekView(
                  weekStart: _weekStart,
                  logs: _allLogs,
                  pomodoros: _allPomodoros,
                  schedules: _allMappedSchedules,
                  tags: _tags,
                  onDayTap: (d) => _goDay(d),
                  onTagTap: _showTagDetail,
                  onManageTags: _showTagManager,
                  onAddLog: () => _goDay(DateTime.now(), mode: _DayMode.edit),
                  onPomodoroTap: _showPomodoroDetail,
                  onTimeLogTap: _showTimeLogDetail,
                  onScheduleTap: _showScheduleDetail,
                  username: widget.username,
                )
              : _dayMode == _DayMode.view
              ? _DayGridView(
                  date: _focusedDate,
                  logs: _allLogs,
                  pomodoros: _allPomodoros,
                  schedules: _allMappedSchedules,
                  tags: _tags,
                  onPomodoroTap: _showPomodoroDetail,
                  onTimeLogTap: _showTimeLogDetail,
                  onScheduleTap: _showScheduleDetail,
                  onSwitchEdit: () => setState(() => _dayMode = _DayMode.edit),
                )
              : _DayView(
                  date: _focusedDate,
                  crossDay: _crossDay,
                  logs: _allLogs,
                  planBlocks: _allPlanBlocks,
                  schedules: _allMappedSchedules,
                  pomodoros: _allPomodoros,
                  tags: _tags,
                  todos: _allTodos,
                  todoGroups: _allTodoGroups,
                  username: widget.username,
                  entryMode: _entryMode,
                  onEntryModeChanged: (mode) =>
                      setState(() => _entryMode = mode),
                  onBack: _goWeek,
                  onCrossDayChanged: (v) => setState(() => _crossDay = v),
                  onSaveLog: (log) async {
                    final result = await _saveTimeLog(log);
                    if (result.isSaved && mounted) {
                      setState(() => _dayMode = _DayMode.view);
                    }
                    return result;
                  },
                  onSavePlanBlock: (block) {
                    _addPlanBlock(block);
                    setState(() => _dayMode = _DayMode.view);
                  },
                  onPomodoroTap: _showPomodoroDetail,
                  onDeleteLog: _deleteLog,
                  onDeletePlanBlock: _deletePlanBlock,
                ),
        ),
      ),
    );
  }

  // ── 共用弹窗容器 ─────────────────────────────────────
  Widget _sheet(Color borderColor, Widget child) => OptionalLiquidGlassSheet(
    topRadius: 20,
    padding: EdgeInsets.fromLTRB(
      20,
      20,
      20,
      MediaQuery.of(context).padding.bottom + 20,
    ),
    fallbackDecoration: BoxDecoration(
      color: _TC.card(context),
      border: Border(top: BorderSide(color: borderColor, width: 1.5)),
      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
    ),
    child: child,
  );

  void _showPomodoroDetail(PomodoroRecord pom) {
    final colorScheme = Theme.of(context).colorScheme;
    final tag = pom.tagUuids.isNotEmpty
        ? _tags.cast<PomodoroTag?>().firstWhere(
            (t) => t?.uuid == pom.tagUuids.first,
            orElse: () => null,
          )
        : null;
    final tc = tag != null ? hexColor(tag.color) : colorScheme.cdtFocus;
    final endMs = pom.endTime ?? (pom.startTime + pom.effectiveDuration * 1000);
    final dur = pom.effectiveDuration ~/ 60;
    final s = DateTime.fromMillisecondsSinceEpoch(pom.startTime);
    final e = DateTime.fromMillisecondsSinceEpoch(endMs);
    showAppModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _sheet(
        tc.withValues(alpha: 0.4),
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _glow(tc),
                const SizedBox(width: 10),
                Text(
                  '专注记录',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: _TC.text(context),
                  ),
                ),
                const Spacer(),
                _pill('${dur}min', tc),
                IconButton(
                  icon: Icon(
                    Icons.close,
                    size: 18,
                    color: _TC.textHint(context),
                  ),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            if (tag != null) ...[
              const SizedBox(height: 10),
              _tagRow(tag.name, tc),
            ],
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _InfoCard(
                    label: '开始',
                    value: AppTimeFormats.clock(s),
                    sub: AppTimeFormats.monthDaySlash(s),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _InfoCard(
                    label: '结束',
                    value: AppTimeFormats.clock(e),
                    sub: AppTimeFormats.monthDaySlash(e),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _InfoCard(
                    label: '时长',
                    value: '${dur}min',
                    sub: (pom.isCompleted == true) ? '✓ 完成' : '手动停止',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showTimeLogDetail(TimeLogItem log) {
    final tag = log.tagUuids.isNotEmpty
        ? _tags.cast<PomodoroTag?>().firstWhere(
            (t) => t?.uuid == log.tagUuids.first,
            orElse: () => null,
          )
        : null;
    final c = tag != null
        ? hexColor(tag.color)
        : Theme.of(context).colorScheme.cdtInfo;
    final dur = (log.endTime - log.startTime) ~/ 60000;
    final s = DateTime.fromMillisecondsSinceEpoch(log.startTime);
    final e = DateTime.fromMillisecondsSinceEpoch(log.endTime);
    showAppModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _sheet(
        c.withValues(alpha: 0.4),
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _glow(c),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    log.title.isNotEmpty ? log.title : (tag?.name ?? '补录记录'),
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: _TC.text(context),
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                _pill('${dur}min', c),
                IconButton(
                  icon: Icon(
                    Icons.close,
                    size: 18,
                    color: _TC.textHint(context),
                  ),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            if (tag != null) ...[
              const SizedBox(height: 10),
              _tagRow(tag.name, c),
            ],
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _InfoCard(
                    label: '开始',
                    value: AppTimeFormats.clock(s),
                    sub: AppTimeFormats.monthDaySlash(s),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _InfoCard(
                    label: '结束',
                    value: AppTimeFormats.clock(e),
                    sub: AppTimeFormats.monthDaySlash(e),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _InfoCard(
                    label: '时长',
                    value: '${dur}min',
                    sub: '手动补录',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      _editTimeLog(log);
                    },
                    icon: const Icon(Icons.edit_note, size: 18),
                    label: const Text(
                      '编辑记录',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _TC.text(context),
                      side: BorderSide(color: _TC.divider(context)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      _deleteLog(log.id);
                    },
                    icon: const Icon(Icons.delete_outline, size: 18),
                    label: const Text(
                      '删除记录',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Theme.of(context).colorScheme.error,
                      side: BorderSide(
                        color: Theme.of(context).colorScheme.error
                            .withValues(alpha: 0.4),
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showScheduleDetail(TimeLogMappedSchedule schedule) {
    final isCourse = schedule.isCourse;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final c = isCourse
        ? (isDark ? const Color(0xFF64B5F6) : const Color(0xFF1E88E5))
        : (isDark ? const Color(0xFFFFB74D) : const Color(0xFFFB8C00));
    final dur = (schedule.endTime - schedule.startTime) ~/ 60000;
    final s = DateTime.fromMillisecondsSinceEpoch(schedule.startTime);
    final e = DateTime.fromMillisecondsSinceEpoch(schedule.endTime);

    showAppModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _sheet(
        c.withValues(alpha: 0.4),
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _glow(c),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    schedule.title,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: _TC.text(context),
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                _pill(isCourse ? '课程' : '日程', c),
                const SizedBox(width: 6),
                _pill('${dur}min', c),
                IconButton(
                  icon: Icon(
                    Icons.close,
                    size: 18,
                    color: _TC.textHint(context),
                  ),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            if (schedule.subtitle != null && schedule.subtitle!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(
                    isCourse ? Icons.place_outlined : Icons.info_outline,
                    size: 14,
                    color: _TC.textSub(context),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      schedule.subtitle!,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: _TC.textSub(context),
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _InfoCard(
                    label: '开始',
                    value: AppTimeFormats.clock(s),
                    sub: AppTimeFormats.monthDaySlash(s),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _InfoCard(
                    label: '结束',
                    value: AppTimeFormats.clock(e),
                    sub: AppTimeFormats.monthDaySlash(e),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _InfoCard(label: '时长', value: '$dur', sub: '分钟'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _glow(Color c) => Container(
    width: 10,
    height: 10,
    decoration: BoxDecoration(
      color: c,
      shape: BoxShape.circle,
      boxShadow: [BoxShadow(color: c, blurRadius: 6)],
    ),
  );

  Widget _pill(String t, Color c) => AppMetricChip(label: t, color: c);

  Widget _tagRow(String name, Color c) => Row(
    children: [
      Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(color: c, shape: BoxShape.circle),
      ),
      const SizedBox(width: 8),
      Text(
        name,
        style: TextStyle(fontSize: 13, color: c, fontWeight: FontWeight.w600),
      ),
    ],
  );

  void _showTagDetail(PomodoroTag tag) {
    showAppModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _TagDetailSheet(
        tag: tag,
        logs: _allLogs,
        pomodoros: _allPomodoros,
        onDelete: (id) {
          Navigator.pop(context);
          _deleteLog(id);
        },
      ),
    );
  }

  void _showTagManager() async {
    final updated = await PageTransitions.pushFromRect<List<PomodoroTag>>(
      context: context,
      page: UnifiedTagManagerScreen(
        allTags: _allTags,
        showSelection: false,
        showArchive: true,
        onChanged: (tags, selected) async {
          await PomodoroService.saveTags(tags);
          setState(() {
            _allTags = tags;
            _tags = tags.where((t) => !t.isArchived).toList();
          });
        },
      ),
      sourceKey: timeLogTagKey,
      sourceBorderRadius: BorderRadius.circular(_timeLogActionChipRadius),
      placeholderIcon: Icons.label_outline,
    );
    if (updated != null) {
      await PomodoroService.saveTags(updated);
      setState(() {
        _allTags = updated;
        _tags = updated.where((t) => !t.isArchived).toList();
      });
    }
  }

  // 🚀 时间日志骨架屏
  Widget _buildSkeleton() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseColor = isDark
        ? Colors.white10
        : Colors.black.withValues(alpha: 0.05);

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: 8,
      itemBuilder: (context, index) => Container(
        height: 60,
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: baseColor,
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════
// 视图切换 Tab
// ══════════════════════════════════════════════════════════
class _ViewTab extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _ViewTab({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 5),
        decoration: BoxDecoration(
          color: selected ? accent.withValues(alpha: 0.12) : Colors.transparent,
          border: Border.all(
            color: selected
                ? accent.withValues(alpha: 0.4)
                : Colors.transparent,
          ),
          borderRadius: BorderRadius.circular(_timeLogActionChipRadius),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
            color: selected ? accent : _TC.textSub(context),
          ),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════
// 周视图
// ══════════════════════════════════════════════════════════
class _WeekView extends StatefulWidget {
  final DateTime weekStart;
  final List<TimeLogItem> logs;
  final List<PomodoroRecord> pomodoros;
  final List<TimeLogMappedSchedule> schedules;
  final List<PomodoroTag> tags;
  final void Function(DateTime) onDayTap;
  final void Function(PomodoroTag) onTagTap;
  final VoidCallback onManageTags, onAddLog;
  final void Function(PomodoroRecord) onPomodoroTap;
  final void Function(TimeLogItem) onTimeLogTap;
  final void Function(TimeLogMappedSchedule) onScheduleTap;
  final String username;

  const _WeekView({
    required this.weekStart,
    required this.logs,
    required this.pomodoros,
    this.schedules = const [],
    required this.tags,
    required this.onDayTap,
    required this.onTagTap,
    required this.onManageTags,
    required this.onAddLog,
    required this.onPomodoroTap,
    required this.onTimeLogTap,
    required this.onScheduleTap,
    required this.username,
  });

  @override
  State<_WeekView> createState() => _WeekViewState();
}

class _WeekViewData {
  const _WeekViewData({
    required this.days,
    required this.todayMinutes,
    required this.dayStartMs,
    required this.dayEndMs,
    required this.logsByDay,
    required this.pomodorosByDay,
    required this.schedulesByDay,
    required this.minutesByDay,
    required this.minutesByTag,
  });

  final List<DateTime> days;
  final int todayMinutes;
  final List<int> dayStartMs;
  final List<int> dayEndMs;
  final List<List<TimeLogItem>> logsByDay;
  final List<List<PomodoroRecord>> pomodorosByDay;
  final List<List<TimeLogMappedSchedule>> schedulesByDay;
  final List<int> minutesByDay;
  final Map<String, int> minutesByTag;
}

class _WeekViewState extends State<_WeekView>
    with SingleTickerProviderStateMixin {
  late AnimationController _heatAnimCtrl;
  late Animation<double> _heatAnim;
  List<TimeLogItem>? _cachedLogs;
  List<PomodoroRecord>? _cachedPomodoros;
  List<TimeLogMappedSchedule>? _cachedSchedules;
  List<PomodoroTag>? _cachedTags;
  DateTime? _cachedWeekStart;
  int? _cachedTodayStartMs;
  int? _cachedTodayEndMs;
  _WeekViewData? _cachedWeekData;

  @override
  void initState() {
    super.initState();
    _heatAnimCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _heatAnim = CurvedAnimation(
      parent: _heatAnimCtrl,
      curve: Curves.easeOutCubic,
    );
    _heatAnimCtrl.forward();
  }

  @override
  void didUpdateWidget(_WeekView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.weekStart != widget.weekStart ||
        oldWidget.logs.length != widget.logs.length ||
        oldWidget.pomodoros.length != widget.pomodoros.length ||
        oldWidget.schedules.length != widget.schedules.length) {
      _heatAnimCtrl.reset();
      _heatAnimCtrl.forward();
    }
  }

  @override
  void dispose() {
    _heatAnimCtrl.dispose();
    super.dispose();
  }

  _WeekViewData _buildWeekViewData(
    List<DateTime> days,
    DateTime todayStart,
    DateTime todayEnd,
  ) {
    final dayStartMs = <int>[];
    final dayEndMs = <int>[];
    for (final day in days) {
      final range = CalendarDateMath.dayRange(day);
      dayStartMs.add(range.start.millisecondsSinceEpoch);
      dayEndMs.add(range.endExclusive.millisecondsSinceEpoch);
    }
    final logsByDay = List.generate(days.length, (_) => <TimeLogItem>[]);
    final pomodorosByDay = List.generate(
      days.length,
      (_) => <PomodoroRecord>[],
    );
    final schedulesByDay = List.generate(
      days.length,
      (_) => <TimeLogMappedSchedule>[],
    );
    final minutesByDay = List<int>.filled(days.length, 0);
    final visibleTagUuids = widget.tags.map((tag) => tag.uuid).toSet();
    final minutesByTag = <String, int>{};
    final seenTagUuids = <String>{};
    final weekStartMs = dayStartMs.first;
    final weekEndMs = dayEndMs.last;
    final todayStartMs = todayStart.millisecondsSinceEpoch;
    final todayEndMs = todayEnd.millisecondsSinceEpoch;
    var todayMinutes = 0;

    int firstDayEndingAfter(int instantMs) {
      var low = 0;
      var high = dayEndMs.length;
      while (low < high) {
        final middle = (low + high) ~/ 2;
        if (dayEndMs[middle] <= instantMs) {
          low = middle + 1;
        } else {
          high = middle;
        }
      }
      return low;
    }

    for (final log in widget.logs) {
      if (log.endTime > weekStartMs && log.startTime < weekEndMs) {
        final overlapMinutes = TimeLogRangeMath.overlapMinutes(
          intervalStartMs: log.startTime,
          intervalEndMs: log.endTime,
          rangeStartMs: weekStartMs,
          rangeEndMs: weekEndMs,
        );
        seenTagUuids.clear();
        for (final uuid in log.tagUuids) {
          if (!visibleTagUuids.contains(uuid) || !seenTagUuids.add(uuid)) {
            continue;
          }
          minutesByTag[uuid] = (minutesByTag[uuid] ?? 0) + overlapMinutes;
        }
      }
      if (log.endTime > todayStartMs && log.startTime < todayEndMs) {
        todayMinutes += TimeLogRangeMath.overlapMinutes(
          intervalStartMs: log.startTime,
          intervalEndMs: log.endTime,
          rangeStartMs: todayStartMs,
          rangeEndMs: todayEndMs,
        );
      }
      for (
        var dayIndex = firstDayEndingAfter(log.startTime);
        dayIndex < days.length && dayStartMs[dayIndex] < log.endTime;
        dayIndex++
      ) {
        logsByDay[dayIndex].add(log);
        minutesByDay[dayIndex] += TimeLogRangeMath.overlapMinutes(
          intervalStartMs: log.startTime,
          intervalEndMs: log.endTime,
          rangeStartMs: dayStartMs[dayIndex],
          rangeEndMs: dayEndMs[dayIndex],
        );
      }
    }
    for (final pomodoro in widget.pomodoros) {
      final endMs =
          pomodoro.endTime ??
          (pomodoro.startTime + pomodoro.effectiveDuration * 1000);
      if (pomodoro.startTime < weekEndMs && endMs > weekStartMs) {
        final durationMinutes = pomodoro.effectiveDuration ~/ 60;
        seenTagUuids.clear();
        for (final uuid in pomodoro.tagUuids) {
          if (!visibleTagUuids.contains(uuid) || !seenTagUuids.add(uuid)) {
            continue;
          }
          minutesByTag[uuid] = (minutesByTag[uuid] ?? 0) + durationMinutes;
        }
      }
      if (pomodoro.startTime < todayEndMs && endMs > todayStartMs) {
        todayMinutes += pomodoro.effectiveDuration ~/ 60;
      }
      for (
        var dayIndex = firstDayEndingAfter(pomodoro.startTime);
        dayIndex < days.length && dayStartMs[dayIndex] < endMs;
        dayIndex++
      ) {
        pomodorosByDay[dayIndex].add(pomodoro);
        minutesByDay[dayIndex] += pomodoro.effectiveDuration ~/ 60;
      }
    }

    for (final schedule in widget.schedules) {
      for (
        var dayIndex = firstDayEndingAfter(schedule.startTime);
        dayIndex < days.length && dayStartMs[dayIndex] < schedule.endTime;
        dayIndex++
      ) {
        schedulesByDay[dayIndex].add(schedule);
      }
    }

    return _WeekViewData(
      days: days,
      todayMinutes: todayMinutes,
      dayStartMs: dayStartMs,
      dayEndMs: dayEndMs,
      logsByDay: logsByDay,
      pomodorosByDay: pomodorosByDay,
      schedulesByDay: schedulesByDay,
      minutesByDay: minutesByDay,
      minutesByTag: minutesByTag,
    );
  }

  _WeekViewData _weekViewDataFor(
    DateTime weekStart,
    DateTime todayStart,
    DateTime todayEnd,
  ) {
    final normalizedWeekStart = CalendarDateMath.weekRange(weekStart).start;
    final todayStartMs = todayStart.millisecondsSinceEpoch;
    final todayEndMs = todayEnd.millisecondsSinceEpoch;
    final cached = _cachedWeekData;
    if (cached != null &&
        identical(_cachedLogs, widget.logs) &&
        identical(_cachedPomodoros, widget.pomodoros) &&
        identical(_cachedSchedules, widget.schedules) &&
        identical(_cachedTags, widget.tags) &&
        _cachedWeekStart == normalizedWeekStart &&
        _cachedTodayStartMs == todayStartMs &&
        _cachedTodayEndMs == todayEndMs) {
      return cached;
    }

    final days = List<DateTime>.generate(
      7,
      (index) => CalendarDateMath.addDays(normalizedWeekStart, index),
      growable: false,
    );
    final data = _buildWeekViewData(days, todayStart, todayEnd);
    _cachedLogs = widget.logs;
    _cachedPomodoros = widget.pomodoros;
    _cachedSchedules = widget.schedules;
    _cachedTags = widget.tags;
    _cachedWeekStart = normalizedWeekStart;
    _cachedTodayStartMs = todayStartMs;
    _cachedTodayEndMs = todayEndMs;
    return _cachedWeekData = data;
  }

  @override
  Widget build(BuildContext context) {
    final todayRange = CalendarDateMath.dayRange(DateTime.now());
    final weekData = _weekViewDataFor(
      widget.weekStart,
      todayRange.start,
      todayRange.endExclusive,
    );
    final days = weekData.days;

    return LayoutBuilder(
      builder: (ctx, outer) {
        final isWide = outer.maxWidth >= 720;
        return Column(
          children: [
            _buildTopBar(ctx, weekData.todayMinutes),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _buildGrid(
                      ctx,
                      days,
                      outer.maxWidth - (isWide ? 160.0 : 0),
                      weekData,
                    ),
                  ),
                  if (isWide) _buildTagSidebar(ctx, weekData.minutesByTag),
                ],
              ),
            ),
            if (!isWide) _buildTagChips(ctx, weekData.minutesByTag),
          ],
        );
      },
    );
  }

  Widget _buildTopBar(BuildContext ctx, int todayMin) {
    final useFloating = floatingBottomBarShouldFloat(ctx);
    final child = Container(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
      decoration: useFloating ? null : BoxDecoration(color: _TC.topBar(ctx)),
      child: Row(
        children: [
          // 今日统计
          _TopBarChip(
            label: '今日 ${todayMin}min',
            color: Theme.of(ctx).colorScheme.cdtSuccess,
            ctx: ctx,
          ),
          const Spacer(),
          SizedBox(
            key: timeLogTagKey,
            child: _TopBarChip(
              label: '标签',
              icon: Icons.label_outline,
              color: _TC.textSub(ctx).withValues(alpha: 0.8),
              ctx: ctx,
              onTap: widget.onManageTags,
            ),
          ),
          const SizedBox(width: 6),
          SizedBox(
            key: timeLogAddKey,
            child: _TopBarChip(
              label: '补录',
              icon: Icons.edit_calendar_outlined,
              color: Theme.of(ctx).colorScheme.primary,
              ctx: ctx,
              onTap: widget.onAddLog,
              filled: true,
            ),
          ),
          const SizedBox(width: 6),
          Builder(
            builder: (bCtx) => _TopBarChip(
              label: '恢复',
              icon: Icons.cloud_download_outlined,
              color: Theme.of(ctx).colorScheme.cdtSuccess,
              ctx: ctx,
              onTap: () async {
                await StorageService.resetSyncTime(widget.username);
                await StorageService.syncData(
                  widget.username,
                  forceFullSync: true,
                  syncTodos: true,
                  syncCountdowns: true,
                  syncTimeLogs: true,
                );
                if (bCtx.mounted) {
                  AppSnackBars.success(
                    bCtx,
                    '🎉 数据强拉成功！请点击右上角的【刷新图标 ↻】查看界面',
                    duration: const Duration(seconds: 4),
                  );
                }
              },
            ),
          ),
        ],
      ),
    );
    if (useFloating) {
      // The weekly calendar header sits directly below this action row. Keep
      // both on the same page surface so a floating glass capsule does not
      // read as a detached card pasted onto the grid.
      return Container(
        height: 52,
        margin: const EdgeInsets.only(top: 8),
        alignment: Alignment.center,
        color: _TC.topBar(ctx),
        child: child,
      );
    }

    return FloatingGlassControl(
      height: 52,
      borderRadius: 0,
      mobilePortraitOnly: true,
      child: child,
    );
  }

  Widget _buildGrid(
    BuildContext ctx,
    List<DateTime> days,
    double availW,
    _WeekViewData weekData,
  ) {
    const totalW = kWeekTimeW + kWeekDayW * 7;
    final scale = availW / totalW;
    final tW = kWeekTimeW * scale;
    final dW = kWeekDayW * scale;
    final colorScheme = Theme.of(ctx).colorScheme;
    final accent = colorScheme.primary;
    final isDark = Theme.of(ctx).brightness == Brightness.dark;

    return Column(
      children: [
        Container(
          height: 52,
          color: _TC.topBar(ctx),
          child: Row(
            children: [
              SizedBox(width: tW),
              ...List.generate(7, (i) {
                final d = days[i];
                final isToday = AppTimeFormats.isSameDay(d, DateTime.now());
                final dm = weekData.minutesByDay[i];
                return GestureDetector(
                  onTap: () => widget.onDayTap(d),
                  child: Container(
                    width: dW,
                    height: 52,
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    decoration: BoxDecoration(
                      color: isToday ? accent.withValues(alpha: 0.07) : null,
                      border: Border(
                        right: BorderSide(
                          color: _TC.divider(ctx).withValues(alpha: 0.2),
                        ),
                      ),
                    ),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '周${['一', '二', '三', '四', '五', '六', '日'][i]}',
                            style: TextStyle(
                              fontSize: 9,
                              color: isToday ? accent : _TC.textHint(ctx),
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.5,
                            ),
                          ),
                          Text(
                            '${d.day}',
                            style: TextStyle(
                              fontSize: 15,
                              color: isToday ? _TC.text(ctx) : _TC.textSub(ctx),
                              fontWeight: isToday
                                  ? FontWeight.w700
                                  : FontWeight.w400,
                            ),
                          ),
                          if (dm > 0)
                            Text(
                              '${dm}m',
                              style: TextStyle(
                                fontSize: 8,
                                color: accent.withValues(alpha: 0.5),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                );
              }),
            ],
          ),
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (ctx2, gc) {
              final hourH = gc.maxHeight / 24;
              final totalH = hourH * 24;
              return SizedBox(
                height: totalH,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: tW,
                      height: totalH,
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: List.generate(
                          24,
                          (h) => Positioned(
                            top: h * hourH - 8,
                            right: 4,
                            child: Text(
                              h.toString().padLeft(2, '0'),
                              style: TextStyle(
                                fontSize: (tW * 0.16).clamp(7.0, 11.0),
                                color: _TC.timeLabel(ctx2, major: h % 6 == 0),
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    ...List.generate(days.length, (dayIndex) {
                      final ds = weekData.dayStartMs[dayIndex];
                      final de = weekData.dayEndMs[dayIndex];
                      final dLogs = weekData.logsByDay[dayIndex];
                      final dPoms = weekData.pomodorosByDay[dayIndex];
                      final dSchedules = weekData.schedulesByDay[dayIndex];
                      return SizedBox(
                        width: dW,
                        height: totalH,
                        child: Stack(
                          children: [
                            RepaintBoundary(
                              child: CustomPaint(
                                size: Size(dW, totalH),
                                painter: _WeekGridPainter(
                                  hourH: hourH,
                                  majorLineColor: colorScheme.outlineVariant,
                                  minorLineColor: colorScheme.outlineVariant
                                      .withValues(alpha: isDark ? 0.28 : 0.45),
                                ),
                              ),
                            ),
                            CustomPaint(
                              size: Size(dW, totalH),
                              painter: _WeekColPainter(
                                dayLogs: dLogs,
                                dayPoms: dPoms,
                                daySchedules: dSchedules,
                                tags: widget.tags,
                                dayStartMs: ds,
                                dayEndMs: de,
                                isDark: isDark,
                                hourH: hourH,
                                animation: _heatAnim,
                                focusColor: colorScheme.cdtFocus,
                                logColor: colorScheme.cdtInfo,
                              ),
                            ),
                            ...dSchedules.map((schedule) {
                              final rs = max(schedule.startTime, ds);
                              final re = min(schedule.endTime, de);
                              final top = (rs - ds) / 3600000 * hourH;
                              final h = ((re - rs) / 3600000 * hourH).clamp(
                                3.0,
                                9999.0,
                              );
                              return Positioned(
                                top: top,
                                left: 0,
                                right: 0,
                                height: h,
                                child: GestureDetector(
                                  onTap: () => widget.onScheduleTap(schedule),
                                  behavior: HitTestBehavior.opaque,
                                  child: const SizedBox.expand(),
                                ),
                              );
                            }),
                            ...dPoms.map((pom) {
                              final pe =
                                  pom.endTime ??
                                  (pom.startTime +
                                      pom.effectiveDuration * 1000);
                              final rs = max(pom.startTime, ds);
                              final re = min(pe, de);
                              final top = (rs - ds) / 3600000 * hourH;
                              final h = ((re - rs) / 3600000 * hourH).clamp(
                                3.0,
                                9999.0,
                              );
                              return Positioned(
                                top: top,
                                left: 0,
                                right: 0,
                                height: h,
                                child: GestureDetector(
                                  onTap: () => widget.onPomodoroTap(pom),
                                  behavior: HitTestBehavior.opaque,
                                  child: const SizedBox.expand(),
                                ),
                              );
                            }),
                            ...dLogs.map((log) {
                              final rs = max(log.startTime, ds);
                              final re = min(log.endTime, de);
                              final top = (rs - ds) / 3600000 * hourH;
                              final h = ((re - rs) / 3600000 * hourH).clamp(
                                3.0,
                                9999.0,
                              );
                              return Positioned(
                                top: top,
                                left: 0,
                                right: 0,
                                height: h,
                                child: GestureDetector(
                                  onTap: () => widget.onTimeLogTap(log),
                                  behavior: HitTestBehavior.opaque,
                                  child: const SizedBox.expand(),
                                ),
                              );
                            }),
                          ],
                        ),
                      );
                    }),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildTagSidebar(BuildContext ctx, Map<String, int> minutesByTag) =>
      SizedBox(
        width: 160,
        child: OptionalLiquidGlassSheet(
          fallbackDecoration: BoxDecoration(
            color: _TC.card(ctx),
            border: Border(left: BorderSide(color: _TC.divider(ctx))),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 14, 12, 8),
                child: Text(
                  '本周标签',
                  style: TextStyle(
                    fontSize: 10,
                    color: _TC.textHint(ctx),
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.5,
                  ),
                ),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: widget.tags.length,
                  itemBuilder: (context, index) {
                    final t = widget.tags[index];
                    final tw = minutesByTag[t.uuid] ?? 0;
                    final c = hexColor(t.color);
                    return GestureDetector(
                      onTap: () => widget.onTagTap(t),
                      child: Container(
                        margin: const EdgeInsets.fromLTRB(8, 0, 8, 6),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: c.withValues(alpha: 0.07),
                          border: Border.all(color: c.withValues(alpha: 0.25)),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: c,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    t.name,
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: c,
                                      fontWeight: FontWeight.w700,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  Text(
                                    '${(tw / 60).toStringAsFixed(1)}h',
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: _TC.text(ctx),
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                  padding: const EdgeInsets.only(bottom: 8),
                ),
              ),
            ],
          ),
        ),
      );

  Widget _buildTagChips(BuildContext ctx, Map<String, int> minutesByTag) =>
      Container(
        height: 56,
        color: _TC.topBar(ctx),
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          itemCount: widget.tags.length,
          itemBuilder: (context, index) {
            final t = widget.tags[index];
            final tw = minutesByTag[t.uuid] ?? 0;
            final c = hexColor(t.color);
            return GestureDetector(
              onTap: () => widget.onTagTap(t),
              child: Container(
                margin: const EdgeInsets.only(right: 8),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: c.withValues(alpha: 0.08),
                  border: Border.all(color: c.withValues(alpha: 0.3)),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      t.name,
                      style: TextStyle(
                        fontSize: 9,
                        color: c,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.8,
                      ),
                    ),
                    Text(
                      '${(tw / 60).toStringAsFixed(1)}h',
                      style: TextStyle(
                        fontSize: 11,
                        color: _TC.text(ctx),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      );
}

// ══════════════════════════════════════════════════════════
// 周视图静态网格 Painter
// ══════════════════════════════════════════════════════════
class _WeekGridPainter extends CustomPainter {
  final double hourH;
  final Color majorLineColor;
  final Color minorLineColor;
  final Paint _gridPaint = Paint()..strokeWidth = 0.5;

  _WeekGridPainter({
    required this.hourH,
    required this.majorLineColor,
    required this.minorLineColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    for (int hour = 0; hour <= 24; hour++) {
      final y = hour * hourH;
      canvas.drawLine(
        Offset(0, y),
        Offset(size.width, y),
        _gridPaint..color = hour % 6 == 0 ? majorLineColor : minorLineColor,
      );
    }
    canvas.drawLine(
      Offset(size.width - 0.5, 0),
      Offset(size.width - 0.5, size.height),
      _gridPaint..color = majorLineColor,
    );
  }

  @override
  bool shouldRepaint(covariant _WeekGridPainter oldDelegate) =>
      oldDelegate.hourH != hourH ||
      oldDelegate.majorLineColor != majorLineColor ||
      oldDelegate.minorLineColor != minorLineColor;
}

// ══════════════════════════════════════════════════════════
// 周视图区块 Painter
// ══════════════════════════════════════════════════════════
class _WeekColBlockVisual {
  final Color color;
  final String title;
  final double top;
  final double bottom;
  final double staggerDelay;
  final double staggerProgressScale;

  const _WeekColBlockVisual({
    required this.color,
    required this.title,
    required this.top,
    required this.bottom,
    required this.staggerDelay,
    required this.staggerProgressScale,
  });
}

class _WeekColPainter extends CustomPainter {
  final List<TimeLogItem> dayLogs;
  final List<PomodoroRecord> dayPoms;
  final List<TimeLogMappedSchedule> daySchedules;
  final List<PomodoroTag> tags;
  final int dayStartMs;
  final int dayEndMs;
  final bool isDark;
  final double hourH;
  final Animation<double> animation;
  final Color focusColor;
  final Color logColor;
  final Paint _blockPaint = Paint();
  late final Map<String, int> _tagIndicesByUuid =
      _DayGridPainter._buildTagIndices(tags);
  TextPainter? _titlePainter;
  int _staggerBlockIndex = 0;
  late final int _totalBlockCount =
      dayPoms.length + dayLogs.length + daySchedules.length;

  double _staggerDelayFor(double top, double bottom) {
    if (bottom <= top + 1) return 0.0;
    final delay = _totalBlockCount > 0
        ? _staggerBlockIndex / _totalBlockCount
        : 0.0;
    _staggerBlockIndex++;
    return delay;
  }

  TextPainter get _reusableTitlePainter => _titlePainter ??= TextPainter(
    textDirection: ui.TextDirection.ltr,
    maxLines: 1,
    ellipsis: '…',
  );
  late final List<_WeekColBlockVisual> _scheduleVisuals = daySchedules
      .map((schedule) {
        final isCourse = schedule.isCourse;
        final base = isCourse
            ? (isDark ? const Color(0xFF64B5F6) : const Color(0xFF1E88E5))
            : (isDark ? const Color(0xFFFFB74D) : const Color(0xFFFB8C00));
        final rangeStart = max(schedule.startTime, dayStartMs);
        final rangeEnd = min(schedule.endTime, dayEndMs);
        final top = (rangeStart - dayStartMs) / 3600000 * hourH;
        final bottom = (rangeEnd - dayStartMs) / 3600000 * hourH;
        final staggerDelay = _staggerDelayFor(top, bottom);
        return _WeekColBlockVisual(
          color: base.withValues(alpha: isDark ? 0.35 : 0.30),
          title: '${isCourse ? "课程" : "日程"}: ${schedule.title}',
          top: top,
          bottom: bottom,
          staggerDelay: staggerDelay,
          staggerProgressScale: 1.0 / (1.0 - staggerDelay),
        );
      })
      .toList(growable: false);
  late final List<_WeekColBlockVisual> _pomodoroVisuals = dayPoms
      .map((pomodoro) {
        final tag = _matchingTag(pomodoro.tagUuids);
        final end =
            pomodoro.endTime ??
            (pomodoro.startTime + pomodoro.effectiveDuration * 1000);
        final rangeStart = max(pomodoro.startTime, dayStartMs);
        final rangeEnd = min(end, dayEndMs);
        final top = (rangeStart - dayStartMs) / 3600000 * hourH;
        final bottom = (rangeEnd - dayStartMs) / 3600000 * hourH;
        final staggerDelay = _staggerDelayFor(top, bottom);
        return _WeekColBlockVisual(
          color: tag == null
              ? focusColor.withValues(alpha: 0.45)
              : hexColor(tag.color, opacity: 0.45),
          title: tag?.name ?? '专注',
          top: top,
          bottom: bottom,
          staggerDelay: staggerDelay,
          staggerProgressScale: 1.0 / (1.0 - staggerDelay),
        );
      })
      .toList(growable: false);
  late final List<_WeekColBlockVisual> _logVisuals = dayLogs
      .map((log) {
        final tag = _matchingTag(log.tagUuids);
        final title = log.title.isNotEmpty ? log.title : '补录';
        final rangeStart = max(log.startTime, dayStartMs);
        final rangeEnd = min(log.endTime, dayEndMs);
        final top = (rangeStart - dayStartMs) / 3600000 * hourH;
        final bottom = (rangeEnd - dayStartMs) / 3600000 * hourH;
        final staggerDelay = _staggerDelayFor(top, bottom);
        return _WeekColBlockVisual(
          color: tag == null
              ? logColor.withValues(alpha: 0.45)
              : hexColor(tag.color, opacity: 0.45),
          title: tag != null && title == '补录' ? tag.name : title,
          top: top,
          bottom: bottom,
          staggerDelay: staggerDelay,
          staggerProgressScale: 1.0 / (1.0 - staggerDelay),
        );
      })
      .toList(growable: false);

  _WeekColPainter({
    required this.dayLogs,
    this.dayPoms = const [],
    this.daySchedules = const [],
    required this.tags,
    required this.dayStartMs,
    required this.dayEndMs,
    required this.isDark,
    required this.hourH,
    required this.animation,
    required this.focusColor,
    required this.logColor,
  }) : super(repaint: animation);

  PomodoroTag? _matchingTag(List<String> tagUuids) {
    if (tagUuids.isEmpty) return null;
    int? firstIndex;
    for (final uuid in tagUuids) {
      final index = _tagIndicesByUuid[uuid];
      if (index != null && (firstIndex == null || index < firstIndex)) {
        firstIndex = index;
      }
    }
    return firstIndex == null ? null : tags[firstIndex];
  }

  @override
  void paint(Canvas canvas, Size size) {
    final animationProgress = animation.value;

    void block(
      _WeekColBlockVisual visual,
      bool isPom, {
      bool isSchedule = false,
    }) {
      final top = visual.top;
      final bot = visual.bottom;
      if (bot <= top + 1) return;

      final blockProgress =
          ((animationProgress - visual.staggerDelay) *
                  visual.staggerProgressScale)
              .clamp(0.0, 1.0);
      if (blockProgress <= 0.0) return;

      final animatedBot = top + (bot - top) * blockProgress;

      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTRB(0, top + 0.5, 3, animatedBot - 0.5),
          const Radius.circular(2),
        ),
        _blockPaint
          ..color = visual.color.withValues(
            alpha: (isSchedule ? 0.75 : 0.9) * blockProgress,
          ),
      );

      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTRB(3, top + 0.5, size.width - 1, animatedBot - 0.5),
          const Radius.circular(3),
        ),
        _blockPaint
          ..color = visual.color.withValues(
            alpha: (isSchedule ? 0.16 : (isPom ? 0.22 : 0.35)) * blockProgress,
          ),
      );

      final blockH = animatedBot - top;
      final blockW = size.width - 6;

      if (blockH >= 10 && blockW >= 8 && blockProgress > 0.5) {
        if (blockH >= 18) {
          final tp = _reusableTitlePainter
            ..text = TextSpan(
              text: visual.title,
              style: TextStyle(
                fontSize: (blockH * 0.28).clamp(7.0, 10.0),
                color: visual.color.withValues(alpha: 0.95 * blockProgress),
                fontWeight: FontWeight.w700,
              ),
            )
            ..layout(maxWidth: blockW - 4);
          tp.paint(canvas, Offset(5, top + (blockH - tp.height) / 2));
        } else {
          final tp = _reusableTitlePainter
            ..text = TextSpan(
              text: visual.title,
              style: TextStyle(
                fontSize: 7.0,
                color: visual.color.withValues(alpha: 0.85 * blockProgress),
                fontWeight: FontWeight.w700,
              ),
            )
            ..layout(maxWidth: blockH - 2);

          canvas.save();
          canvas.translate(5 + tp.height, top + 1);
          canvas.rotate(pi / 2);
          tp.paint(canvas, Offset.zero);
          canvas.restore();
        }
      }
    }

    // 先画排程（课程 / 日程）
    for (var i = 0; i < daySchedules.length; i++) {
      final visual = _scheduleVisuals[i];
      block(visual, false, isSchedule: true);
    }

    // 画番茄钟（★ 传入 title）
    for (var i = 0; i < dayPoms.length; i++) {
      final visual = _pomodoroVisuals[i];
      block(visual, true);
    }

    // 画补录日志（★ 传入 title）
    for (var i = 0; i < dayLogs.length; i++) {
      final visual = _logVisuals[i];
      block(visual, false);
    }
  }

  @override
  bool shouldRepaint(covariant _WeekColPainter o) =>
      o.isDark != isDark ||
      o.hourH != hourH ||
      o.dayLogs != dayLogs ||
      o.dayPoms != dayPoms ||
      o.daySchedules != daySchedules ||
      o.tags != tags ||
      o.dayStartMs != dayStartMs ||
      o.dayEndMs != dayEndMs ||
      o.animation != animation ||
      o.focusColor != focusColor ||
      o.logColor != logColor;
}

// ══════════════════════════════════════════════════════════
// 日视图 — 网格（24行×5分钟格）
// ══════════════════════════════════════════════════════════
class _DayGridView extends StatefulWidget {
  final DateTime date;
  final List<TimeLogItem> logs;
  final List<PomodoroRecord> pomodoros;
  final List<TimeLogMappedSchedule> schedules;
  final List<PomodoroTag> tags;
  final void Function(PomodoroRecord) onPomodoroTap;
  final void Function(TimeLogItem) onTimeLogTap;
  final void Function(TimeLogMappedSchedule) onScheduleTap;
  final VoidCallback onSwitchEdit;

  const _DayGridView({
    required this.date,
    required this.logs,
    required this.pomodoros,
    this.schedules = const [],
    required this.tags,
    required this.onPomodoroTap,
    required this.onTimeLogTap,
    required this.onScheduleTap,
    required this.onSwitchEdit,
  });

  @override
  State<_DayGridView> createState() => _DayGridViewState();
}

class _DayGridViewState extends State<_DayGridView> {
  List<TimeLogItem>? _dayLogsSource;
  List<PomodoroRecord>? _dayPomodorosSource;
  List<TimeLogMappedSchedule>? _daySchedulesSource;
  int? _dayDataStartMs;
  int? _dayDataEndMs;
  List<TimeLogItem> _dayLogs = const [];
  List<PomodoroRecord> _dayPomodoros = const [];
  List<TimeLogMappedSchedule> _daySchedules = const [];
  List<MapEntry<String, int>> _sortedTagMinutes = const [];
  List<PomodoroTag>? _tagIndexSource;
  List<PomodoroTag>? _tagIndexSnapshot;
  Map<String, PomodoroTag> _tagsByUuid = const {};
  Map<String, int> _tagIndicesByUuid = const {};
  int _dayLogMinutes = 0;
  int _dayPomodoroMinutes = 0;
  int _dayScheduleMinutes = 0;

  void _ensureTagIndex() {
    final cachedTags = _tagIndexSnapshot;
    if (identical(_tagIndexSource, widget.tags) &&
        cachedTags != null &&
        cachedTags.length == widget.tags.length) {
      var tagsUnchanged = true;
      for (var index = 0; index < widget.tags.length; index++) {
        if (!identical(cachedTags[index], widget.tags[index])) {
          tagsUnchanged = false;
          break;
        }
      }
      if (tagsUnchanged) return;
    }

    final tagsByUuid = <String, PomodoroTag>{};
    final tagIndicesByUuid = <String, int>{};
    for (var index = 0; index < widget.tags.length; index++) {
      final tag = widget.tags[index];
      tagsByUuid.putIfAbsent(tag.uuid, () => tag);
      tagIndicesByUuid.putIfAbsent(tag.uuid, () => index);
    }
    _tagIndexSource = widget.tags;
    _tagIndexSnapshot = List<PomodoroTag>.of(widget.tags, growable: false);
    _tagsByUuid = tagsByUuid;
    _tagIndicesByUuid = tagIndicesByUuid;
  }

  void _ensureDayData(int dayStartMs, int dayEndMs) {
    if (identical(_dayLogsSource, widget.logs) &&
        identical(_dayPomodorosSource, widget.pomodoros) &&
        identical(_daySchedulesSource, widget.schedules) &&
        _dayDataStartMs == dayStartMs &&
        _dayDataEndMs == dayEndMs) {
      return;
    }

    final dayLogs = <TimeLogItem>[];
    final dayPomodoros = <PomodoroRecord>[];
    final daySchedules = <TimeLogMappedSchedule>[];
    final tagMinutesByUuid = <String, int>{};
    var logMinutes = 0;
    for (final log in widget.logs) {
      if (log.endTime <= dayStartMs || log.startTime >= dayEndMs) continue;
      dayLogs.add(log);
      final overlapMinutes = TimeLogRangeMath.overlapMinutes(
        intervalStartMs: log.startTime,
        intervalEndMs: log.endTime,
        rangeStartMs: dayStartMs,
        rangeEndMs: dayEndMs,
      );
      logMinutes += overlapMinutes;
      for (final uuid in log.tagUuids) {
        tagMinutesByUuid[uuid] = (tagMinutesByUuid[uuid] ?? 0) + overlapMinutes;
      }
    }

    var pomodoroMinutes = 0;
    for (final pomodoro in widget.pomodoros) {
      final endMs =
          pomodoro.endTime ??
          (pomodoro.startTime + pomodoro.effectiveDuration * 1000);
      if (endMs <= dayStartMs || pomodoro.startTime >= dayEndMs) continue;
      dayPomodoros.add(pomodoro);
      final durationMinutes = pomodoro.effectiveDuration ~/ 60;
      pomodoroMinutes += durationMinutes;
      for (final uuid in pomodoro.tagUuids) {
        tagMinutesByUuid[uuid] =
            (tagMinutesByUuid[uuid] ?? 0) + durationMinutes;
      }
    }

    var scheduleMinutes = 0;
    for (final schedule in widget.schedules) {
      if (schedule.endTime <= dayStartMs || schedule.startTime >= dayEndMs) {
        continue;
      }
      daySchedules.add(schedule);
      final overlapMinutes = TimeLogRangeMath.overlapMinutes(
        intervalStartMs: schedule.startTime,
        intervalEndMs: schedule.endTime,
        rangeStartMs: dayStartMs,
        rangeEndMs: dayEndMs,
      );
      scheduleMinutes += overlapMinutes;
    }

    _dayLogsSource = widget.logs;
    _dayPomodorosSource = widget.pomodoros;
    _daySchedulesSource = widget.schedules;
    _dayDataStartMs = dayStartMs;
    _dayDataEndMs = dayEndMs;
    _dayLogs = dayLogs;
    _dayPomodoros = dayPomodoros;
    _daySchedules = daySchedules;
    _sortedTagMinutes = tagMinutesByUuid.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    _dayLogMinutes = logMinutes;
    _dayPomodoroMinutes = pomodoroMinutes;
    _dayScheduleMinutes = scheduleMinutes;
  }

  @override
  Widget build(BuildContext context) {
    final dayRange = CalendarDateMath.dayRange(widget.date);
    final ds = dayRange.start.millisecondsSinceEpoch;
    final de = dayRange.endExclusive.millisecondsSinceEpoch;
    _ensureDayData(ds, de);
    _ensureTagIndex();
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final colorScheme = theme.colorScheme;
    final totalMin = _dayLogMinutes + _dayPomodoroMinutes;

    return Column(
      children: [
        _buildSummary(
          context,
          totalMin,
          _dayLogMinutes,
          _dayPomodoroMinutes,
          _dayScheduleMinutes,
          _sortedTagMinutes,
          _tagsByUuid,
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (ctx, constraints) {
              final gridAreaW = constraints.maxWidth - kTimeAxisW;
              final colW = gridAreaW / kColsPerH;
              final rowH = constraints.maxHeight / kTotalRows;

              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: kTimeAxisW,
                    height: constraints.maxHeight,
                    child: _TimeLabels(isDark: isDark, rowH: rowH),
                  ),
                  Expanded(
                    child: SizedBox(
                      width: gridAreaW,
                      height: constraints.maxHeight,
                      child: _GridCanvas(
                        colW: colW,
                        rowW: gridAreaW,
                        rowH: rowH,
                        dayStartMs: ds,
                        dLogs: _dayLogs,
                        dPoms: _dayPomodoros,
                        dSchedules: _daySchedules,
                        tags: widget.tags,
                        tagIndicesByUuid: _tagIndicesByUuid,
                        isDark: isDark,
                        focusColor: colorScheme.cdtFocus,
                        logColor: colorScheme.cdtInfo,
                        onPomodoroTap: widget.onPomodoroTap,
                        onTimeLogTap: widget.onTimeLogTap,
                        onScheduleTap: widget.onScheduleTap,
                        date: widget.date,
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildSummary(
    BuildContext ctx,
    int total,
    int logMin,
    int pomMin,
    int scheduleMin,
    List<MapEntry<String, int>> sortedTagMinutes,
    Map<String, PomodoroTag> tagsByUuid,
  ) {
    final accent = Theme.of(ctx).colorScheme.primary;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
      color: _TC.topBar(ctx),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                height: _timeLogSummaryChipHeight,
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.1),
                  border: Border.all(color: accent.withValues(alpha: 0.3)),
                  borderRadius: BorderRadius.circular(_timeLogActionChipRadius),
                ),
                child: Text(
                  '${(total / 60).toStringAsFixed(1)}h  今日合计',
                  style: TextStyle(
                    fontSize: 11,
                    color: accent,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              if (pomMin > 0)
                _miniPill(
                  ctx,
                  '专注 ${pomMin}m',
                  Theme.of(ctx).colorScheme.cdtFocus,
                ),
              if (logMin > 0) ...[
                const SizedBox(width: 6),
                _miniPill(
                  ctx,
                  '补录 ${logMin}m',
                  Theme.of(ctx).colorScheme.cdtInfo,
                ),
              ],
              if (scheduleMin > 0) ...[
                const SizedBox(width: 6),
                _miniPill(
                  ctx,
                  '排程 ${scheduleMin}m',
                  Theme.of(ctx).colorScheme.tertiary,
                ),
              ],
              const Spacer(),
              GestureDetector(
                onTap: widget.onSwitchEdit,
                child: Container(
                  height: _timeLogSummaryChipHeight,
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.1),
                    border: Border.all(color: accent.withValues(alpha: 0.3)),
                    borderRadius: BorderRadius.circular(
                      _timeLogActionChipRadius,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.edit_note, size: 14, color: accent),
                      const SizedBox(width: 4),
                      Text(
                        '补录',
                        style: TextStyle(
                          fontSize: 11,
                          color: accent,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          if (sortedTagMinutes.isNotEmpty && total > 0) ...[
            const SizedBox(height: 8),
            _TagProgressBar(
              sortedTagMinutes: sortedTagMinutes,
              totalMin: total,
              tagsByUuid: tagsByUuid,
            ),
          ],
        ],
      ),
    );
  }

  Widget _miniPill(BuildContext ctx, String text, Color c) => Container(
    height: _timeLogSummaryChipHeight,
    alignment: Alignment.center,
    padding: const EdgeInsets.symmetric(horizontal: 12),
    decoration: BoxDecoration(
      color: c.withValues(alpha: 0.08),
      border: Border.all(color: c.withValues(alpha: 0.3)),
      borderRadius: BorderRadius.circular(_timeLogActionChipRadius),
    ),
    child: Text(
      text,
      style: TextStyle(fontSize: 11, color: c, fontWeight: FontWeight.w600),
    ),
  );
}

// ══════════════════════════════════════════════════════════
// 左侧时间标签列
// ══════════════════════════════════════════════════════════
class _TimeLabels extends StatelessWidget {
  final bool isDark;
  final double rowH;

  const _TimeLabels({required this.isDark, required this.rowH});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: kTimeAxisW,
      height: rowH * kTotalRows,
      child: Stack(
        children: List.generate(kTotalRows, (h) {
          return Positioned(
            top: h * rowH,
            left: 0,
            right: 0,
            child: SizedBox(
              height: rowH,
              child: Align(
                alignment: Alignment.topRight,
                child: Padding(
                  padding: const EdgeInsets.only(right: 8, top: 3),
                  child: Text(
                    '${h.toString().padLeft(2, '0')}:00',
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: h % 6 == 0
                          ? FontWeight.w700
                          : FontWeight.w400,
                      color: _TC.timeLabel(context, major: h % 6 == 0),
                    ),
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════
// 网格 Canvas
// ══════════════════════════════════════════════════════════
class _GridCanvas extends StatelessWidget {
  final double colW, rowW, rowH;
  final int dayStartMs;
  final List<TimeLogItem> dLogs;
  final List<PomodoroRecord> dPoms;
  final List<TimeLogMappedSchedule> dSchedules;
  final List<PomodoroTag> tags;
  final Map<String, int> tagIndicesByUuid;
  final bool isDark;
  final Color focusColor;
  final Color logColor;
  final DateTime date;
  final void Function(PomodoroRecord) onPomodoroTap;
  final void Function(TimeLogItem) onTimeLogTap;
  final void Function(TimeLogMappedSchedule) onScheduleTap;

  const _GridCanvas({
    required this.colW,
    required this.rowW,
    required this.rowH,
    required this.dayStartMs,
    required this.dLogs,
    required this.dPoms,
    this.dSchedules = const [],
    required this.tags,
    required this.tagIndicesByUuid,
    required this.isDark,
    required this.focusColor,
    required this.logColor,
    required this.date,
    required this.onPomodoroTap,
    required this.onTimeLogTap,
    required this.onScheduleTap,
  });

  PomodoroTag? _firstTagForUuids(List<String> uuids) {
    int? firstIndex;
    for (final uuid in uuids) {
      final index = tagIndicesByUuid[uuid];
      if (index != null && (firstIndex == null || index < firstIndex)) {
        firstIndex = index;
      }
    }
    return firstIndex == null ? null : tags[firstIndex];
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final dayEndMs = _dayEndMs(DateTime.fromMillisecondsSinceEpoch(dayStartMs));
    final colorScheme = Theme.of(context).colorScheme;
    final isToday = AppTimeFormats.isSameDay(now, date);
    final nowTotalMin = isToday ? now.hour * 60 + now.minute : -1;

    return Stack(
      children: [
        CustomPaint(
          size: Size(rowW, rowH * kTotalRows),
          painter: _GridBgPainter(
            colW: colW,
            rowH: rowH,
            rowMajorColor: colorScheme.outlineVariant,
            rowNormalColor: colorScheme.outlineVariant.withValues(
              alpha: isDark ? 0.38 : 0.58,
            ),
            colHourColor: colorScheme.outline,
            colHalfColor: colorScheme.outlineVariant,
            colCellColor: colorScheme.outlineVariant.withValues(
              alpha: isDark ? 0.26 : 0.42,
            ),
            labelMajorColor: colorScheme.onSurfaceVariant.withValues(
              alpha: 0.48,
            ),
            labelMinorColor: colorScheme.onSurfaceVariant.withValues(
              alpha: 0.34,
            ),
          ),
        ),
        if (nowTotalMin >= 0) _buildNowLine(nowTotalMin),
        // 排程（课程 / 固定日程，发生冲突时上下两行紧凑排列）
        ..._buildScheduleBlocks(
          schedules: dSchedules,
          dayStartMs: dayStartMs,
          colW: colW,
          rowW: rowW,
          rowH: rowH,
          isDark: isDark,
          onScheduleTap: onScheduleTap,
        ),
        // 番茄钟
        ...dPoms.expand((pom) {
          final pe =
              pom.endTime ?? (pom.startTime + pom.effectiveDuration * 1000);
          PomodoroTag? tag;
          if (pom.tagUuids.isNotEmpty) {
            tag = _firstTagForUuids(pom.tagUuids);
          }
          final base = tag != null ? hexColor(tag.color) : focusColor;
          final title = tag?.name ?? '专注';
          return _buildEventBlocks(
            startMs: max(pom.startTime, dayStartMs),
            endMs: min(pe, dayEndMs),
            dayStartMs: dayStartMs,
            colW: colW,
            rowW: rowW,
            rowH: rowH,
            fillColor: base.withValues(alpha: isDark ? 0.30 : 0.22),
            barColor: base,
            title: title,
            onTap: () => onPomodoroTap(pom),
          );
        }),

        // 补录日志
        ...dLogs.expand((log) {
          PomodoroTag? tag;
          if (log.tagUuids.isNotEmpty) {
            tag = _firstTagForUuids(log.tagUuids);
          }
          final base = tag != null ? hexColor(tag.color) : logColor;
          final title = log.title.isNotEmpty ? log.title : (tag?.name ?? '补录');
          return _buildEventBlocks(
            startMs: max(log.startTime, dayStartMs),
            endMs: min(log.endTime, dayEndMs),
            dayStartMs: dayStartMs,
            colW: colW,
            rowW: rowW,
            rowH: rowH,
            fillColor: base.withValues(alpha: isDark ? 0.26 : 0.18),
            barColor: base,
            title: title,
            onTap: () => onTimeLogTap(log),
          );
        }),

        Positioned(
          top: 9 * rowH,
          left: rowW / 3,
          width: rowW / 3,
          height: rowH,
          child: SizedBox(key: timeLogDragKey),
        ),
      ],
    );
  }

  Widget _buildNowLine(int nowTotalMin) {
    final nowHour = nowTotalMin ~/ 60;
    final minInHour = nowTotalMin % 60;
    final x = (minInHour / kMinsPerCol) * colW;
    final y = nowHour * rowH;

    return Stack(
      children: [
        Positioned(
          top: y,
          left: 0,
          right: 0,
          height: 1.0,
          child: Container(color: focusColor.withValues(alpha: 0.20)),
        ),
        Positioned(
          top: y,
          left: x,
          width: 1.5,
          height: rowH,
          child: Container(color: focusColor.withValues(alpha: 0.80)),
        ),
        Positioned(
          top: y + rowH / 2 - 3,
          left: x - 3,
          child: Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: focusColor,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: focusColor.withValues(alpha: 0.5),
                  blurRadius: 4,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  List<Widget> _buildEventBlocks({
    required int startMs,
    required int endMs,
    required int dayStartMs,
    required double colW,
    required double rowW,
    required double rowH,
    required Color fillColor,
    required Color barColor,
    required String title,
    required VoidCallback onTap,
  }) {
    if (endMs <= startMs) return [];

    final startMinF = (startMs - dayStartMs) / 60000.0;
    final endMinF = (endMs - dayStartMs) / 60000.0;
    final List<Widget> result = [];

    int row = startMinF ~/ 60;
    bool isFirst = true;

    while (row < kTotalRows) {
      final rowStartMin = row * 60.0;
      final rowEndMin = rowStartMin + 60.0;
      final segStartMin = startMinF.clamp(rowStartMin, rowEndMin);
      final segEndMin = endMinF.clamp(rowStartMin, rowEndMin);

      if (segEndMin <= segStartMin) {
        if (endMinF <= rowStartMin) break;
        row++;
        continue;
      }

      final colStart = (segStartMin - rowStartMin) / kMinsPerCol;
      final colEnd = (segEndMin - rowStartMin) / kMinsPerCol;
      final left = colStart * colW;
      final width = ((colEnd - colStart) * colW).clamp(1.0, double.infinity);
      final isLast = endMinF <= rowEndMin;

      // ── 色块背景（每一行都画）──────────────────────────
      result.add(
        Positioned(
          top: row * rowH + 1,
          left: left + 1,
          width: width - 2,
          height: rowH - 2,
          child: GestureDetector(
            onTap: onTap,
            behavior: HitTestBehavior.opaque,
            child: ClipRRect(
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(isFirst ? 3 : 0),
                bottomLeft: Radius.circular(isLast ? 3 : 0),
                topRight: Radius.circular(isFirst && isLast ? 3 : 0),
                bottomRight: Radius.circular(isFirst && isLast ? 3 : 0),
              ),
              child: Container(
                decoration: BoxDecoration(
                  color: fillColor,
                  border: Border(
                    left: BorderSide(color: barColor, width: 2.5),
                    top: isFirst
                        ? BorderSide(
                            color: barColor.withValues(alpha: 0.45),
                            width: 1.0,
                          )
                        : BorderSide.none,
                    bottom: isLast
                        ? BorderSide(
                            color: barColor.withValues(alpha: 0.45),
                            width: 1.0,
                          )
                        : BorderSide.none,
                    right: isLast && colEnd < kColsPerH
                        ? BorderSide(
                            color: barColor.withValues(alpha: 0.25),
                            width: 1.0,
                          )
                        : BorderSide.none,
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      // ── 文字：只在第一行，横跨整行宽度（从 left+3 到行末）──
      if (isFirst) {
        result.add(
          Positioned(
            top: row * rowH + 1,
            left: left + 3, // 紧贴左边彩条右侧
            right: 2, // 贴到行右边，让文字尽量展开
            height: rowH - 2,
            child: GestureDetector(
              onTap: onTap,
              behavior: HitTestBehavior.translucent,
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 10,
                    color: barColor,
                    fontWeight: FontWeight.w700,
                    height: 1.2,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ),
            ),
          ),
        );
      }

      if (isLast) break;
      isFirst = false;
      row++;
    }

    return result;
  }

  List<Widget> _buildScheduleBlocks({
    required List<TimeLogMappedSchedule> schedules,
    required int dayStartMs,
    required double colW,
    required double rowW,
    required double rowH,
    required bool isDark,
    required void Function(TimeLogMappedSchedule) onScheduleTap,
  }) {
    if (schedules.isEmpty) return const [];

    final List<List<_ScheduleRowSegment>> segmentsByRow = List.generate(
      kTotalRows,
      (_) => <_ScheduleRowSegment>[],
    );

    for (final schedule in schedules) {
      final sMs = max(schedule.startTime, dayStartMs);
      final eMs = min(schedule.endTime, dayStartMs + 24 * 3600 * 1000);
      if (eMs <= sMs) continue;

      final startMinF = (sMs - dayStartMs) / 60000.0;
      final endMinF = (eMs - dayStartMs) / 60000.0;
      final isCourse = schedule.isCourse;
      final base = isCourse
          ? (isDark ? const Color(0xFF64B5F6) : const Color(0xFF1E88E5))
          : (isDark ? const Color(0xFFFFB74D) : const Color(0xFFFB8C00));
      final title =
          '${isCourse ? "课程" : "日程"}: ${schedule.title}${schedule.subtitle != null && schedule.subtitle!.isNotEmpty ? " · ${schedule.subtitle}" : ""}';
      final fillColor = base.withValues(alpha: isDark ? 0.16 : 0.10);
      final barColor = base.withValues(alpha: 0.75);
      final borderColor = base.withValues(alpha: isDark ? 0.40 : 0.30);
      final onTap = () => onScheduleTap(schedule);

      int row = startMinF ~/ 60;
      bool isFirst = true;

      while (row < kTotalRows) {
        final rowStartMin = row * 60.0;
        final rowEndMin = rowStartMin + 60.0;
        final segStartMin = startMinF.clamp(rowStartMin, rowEndMin);
        final segEndMin = endMinF.clamp(rowStartMin, rowEndMin);

        if (segEndMin <= segStartMin) {
          if (endMinF <= rowStartMin) break;
          row++;
          continue;
        }

        final isLast = endMinF <= rowEndMin;
        segmentsByRow[row].add(
          _ScheduleRowSegment(
            schedule: schedule,
            row: row,
            segStartMin: segStartMin,
            segEndMin: segEndMin,
            isFirst: isFirst,
            isLast: isLast,
            fillColor: fillColor,
            barColor: barColor,
            borderColor: borderColor,
            title: title,
            onTap: onTap,
          ),
        );

        if (isLast) break;
        isFirst = false;
        row++;
      }
    }

    final List<Widget> result = [];

    for (int row = 0; row < kTotalRows; row++) {
      final rowSegments = segmentsByRow[row];
      if (rowSegments.isEmpty) continue;

      // 稳定排序：课程优先排在上半行（lane 0），日程排在下半行（lane 1）
      rowSegments.sort((a, b) {
        if (a.schedule.isCourse != b.schedule.isCourse) {
          return a.schedule.isCourse ? -1 : 1;
        }
        final cmpStart = a.schedule.startTime.compareTo(b.schedule.startTime);
        if (cmpStart != 0) return cmpStart;
        return a.schedule.id.compareTo(b.schedule.id);
      });

      // 检查当前行中的片段是否存在时间水平重叠
      final laneAssignment = <_ScheduleRowSegment, int>{};
      final laneTotalCount = <_ScheduleRowSegment, int>{};

      for (int i = 0; i < rowSegments.length; i++) {
        final current = rowSegments[i];
        final overlapping = <_ScheduleRowSegment>[];
        for (int j = 0; j < rowSegments.length; j++) {
          final other = rowSegments[j];
          if (current.segStartMin < other.segEndMin &&
              other.segStartMin < current.segEndMin) {
            overlapping.add(other);
          }
        }

        if (overlapping.length <= 1) {
          laneAssignment[current] = 0;
          laneTotalCount[current] = 1;
        } else {
          final indexInOverlap = overlapping.indexOf(current);
          laneAssignment[current] = indexInOverlap.clamp(0, 1);
          laneTotalCount[current] = min(overlapping.length, 2);
        }
      }

      for (final seg in rowSegments) {
        final lane = laneAssignment[seg] ?? 0;
        final totalLanes = laneTotalCount[seg] ?? 1;

        final rowStartMin = row * 60.0;
        final colStart = (seg.segStartMin - rowStartMin) / kMinsPerCol;
        final colEnd = (seg.segEndMin - rowStartMin) / kMinsPerCol;
        final left = colStart * colW;
        final width = ((colEnd - colStart) * colW).clamp(1.0, double.infinity);

        final double topOffset;
        final double blockHeight;
        final double fontSize;

        if (totalLanes >= 2) {
          // 冲突时间段：一行分两行用，上下紧凑排列
          final laneH = (rowH - 3.0) / 2.0;
          blockHeight = laneH;
          topOffset = row * rowH + 1.0 + lane * (laneH + 1.0);
          fontSize = (laneH * 0.72).clamp(7.5, 9.5);
        } else {
          blockHeight = rowH - 2.0;
          topOffset = row * rowH + 1.0;
          fontSize = (blockHeight * 0.40).clamp(9.0, 10.5);
        }

        result.add(
          Positioned(
            top: topOffset,
            left: left + 1,
            width: width - 2,
            height: blockHeight,
            child: GestureDetector(
              onTap: seg.onTap,
              behavior: HitTestBehavior.opaque,
              child: ClipRRect(
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(seg.isFirst ? 3 : 0),
                  bottomLeft: Radius.circular(seg.isLast ? 3 : 0),
                  topRight: Radius.circular(seg.isFirst && seg.isLast ? 3 : 0),
                  bottomRight: Radius.circular(
                    seg.isFirst && seg.isLast ? 3 : 0,
                  ),
                ),
                child: Container(
                  decoration: BoxDecoration(
                    color: seg.fillColor,
                    border: Border(
                      left: BorderSide(
                        color: seg.barColor,
                        width: totalLanes >= 2 ? 2.0 : 2.5,
                      ),
                      top: BorderSide(color: seg.borderColor, width: 0.8),
                      bottom: BorderSide(color: seg.borderColor, width: 0.8),
                      right: seg.isLast && colEnd < kColsPerH
                          ? BorderSide(color: seg.borderColor, width: 0.8)
                          : BorderSide.none,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );

        if (seg.isFirst) {
          result.add(
            Positioned(
              top: topOffset,
              left: left + 4,
              right: 2,
              height: blockHeight,
              child: IgnorePointer(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    seg.title,
                    style: TextStyle(
                      fontSize: fontSize,
                      color: seg.barColor,
                      fontWeight: FontWeight.w700,
                      height: 1.1,
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                ),
              ),
            ),
          );
        }
      }
    }

    return result;
  }
}

class _ScheduleRowSegment {
  final TimeLogMappedSchedule schedule;
  final int row;
  final double segStartMin;
  final double segEndMin;
  final bool isFirst;
  final bool isLast;
  final Color fillColor;
  final Color barColor;
  final Color borderColor;
  final String title;
  final VoidCallback onTap;

  _ScheduleRowSegment({
    required this.schedule,
    required this.row,
    required this.segStartMin,
    required this.segEndMin,
    required this.isFirst,
    required this.isLast,
    required this.fillColor,
    required this.barColor,
    required this.borderColor,
    required this.title,
    required this.onTap,
  });
}

// ══════════════════════════════════════════════════════════
// 网格背景 Painter
// ══════════════════════════════════════════════════════════
class _GridBgPainter extends CustomPainter {
  final double colW;
  final double rowH;
  final Color rowMajorColor;
  final Color rowNormalColor;
  final Color colHourColor;
  final Color colHalfColor;
  final Color colCellColor;
  final Color labelMajorColor;
  final Color labelMinorColor;

  const _GridBgPainter({
    required this.colW,
    required this.rowH,
    required this.rowMajorColor,
    required this.rowNormalColor,
    required this.colHourColor,
    required this.colHalfColor,
    required this.colCellColor,
    required this.labelMajorColor,
    required this.labelMinorColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rowMajor = Paint()
      ..color = rowMajorColor
      ..strokeWidth = 0.9;
    final rowNormal = Paint()
      ..color = rowNormalColor
      ..strokeWidth = 0.5;

    for (int r = 0; r <= kTotalRows; r++) {
      final y = r * rowH;
      canvas.drawLine(
        Offset(0, y),
        Offset(size.width, y),
        r % 6 == 0 ? rowMajor : rowNormal,
      );
    }

    final colHour = Paint()
      ..color = colHourColor
      ..strokeWidth = 0.9;
    final colHalf = Paint()
      ..color = colHalfColor
      ..strokeWidth = 0.5;
    final colCell = Paint()
      ..color = colCellColor
      ..strokeWidth = 0.3;

    for (int c = 0; c <= kTotalCols; c++) {
      final x = c * colW;
      final Paint p;
      if (c % kColsPerH == 0) {
        p = colHour;
      } else if (c % 5 == 0) {
        p = colHalf;
      } else {
        p = colCell;
      }
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), p);
    }

    for (int h = 0; h < kTotalRows; h++) {
      final rowTop = h * rowH;

      _drawLabel(
        canvas,
        '${h.toString().padLeft(2, '0')}:00',
        Offset(h * kColsPerH * colW + 3, rowTop + 2),
        fontSize: 8.0,
        color: labelMajorColor,
        bold: true,
      );

      if (colW >= 14) {
        _drawLabel(
          canvas,
          '${h.toString().padLeft(2, '0')}:30',
          Offset((h * kColsPerH + 5) * colW + 3, rowTop + 2),
          fontSize: 7.0,
          color: labelMinorColor,
          bold: false,
        );
      }
    }
  }

  void _drawLabel(
    Canvas canvas,
    String text,
    Offset offset, {
    required double fontSize,
    required Color color,
    required bool bold,
  }) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontSize: fontSize,
          color: color,
          fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
        ),
      ),
      textDirection: ui.TextDirection.ltr,
    )..layout();
    tp.paint(canvas, offset);
  }

  @override
  bool shouldRepaint(covariant _GridBgPainter o) =>
      o.colW != colW ||
      o.rowH != rowH ||
      o.rowMajorColor != rowMajorColor ||
      o.rowNormalColor != rowNormalColor ||
      o.colHourColor != colHourColor ||
      o.colHalfColor != colHalfColor ||
      o.colCellColor != colCellColor ||
      o.labelMajorColor != labelMajorColor ||
      o.labelMinorColor != labelMinorColor;
}

// ══════════════════════════════════════════════════════════
// 标签色条
// ══════════════════════════════════════════════════════════
class _TagProgressBar extends StatelessWidget {
  final List<MapEntry<String, int>> sortedTagMinutes;
  final int totalMin;
  final Map<String, PomodoroTag> tagsByUuid;

  const _TagProgressBar({
    required this.sortedTagMinutes,
    required this.totalMin,
    required this.tagsByUuid,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: SizedBox(
            height: 5,
            width: double.infinity,
            child: Row(
              children: sortedTagMinutes.map((e) {
                final t = tagsByUuid[e.key];
                final c = t != null
                    ? hexColor(t.color)
                    : Theme.of(context).colorScheme.cdtInfo;
                return Expanded(
                  flex: e.value,
                  child: Container(color: c),
                );
              }).toList(),
            ),
          ),
        ),
        const SizedBox(height: 5),
        Wrap(
          spacing: 10,
          runSpacing: 3,
          children: sortedTagMinutes.map((e) {
            final t = tagsByUuid[e.key];
            if (t == null) return const SizedBox.shrink();
            final c = hexColor(t.color);
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(color: c, shape: BoxShape.circle),
                ),
                const SizedBox(width: 4),
                Text(
                  t.name,
                  style: TextStyle(
                    fontSize: 10,
                    color: c,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 3),
                Text(
                  '${e.value}m',
                  style: TextStyle(fontSize: 10, color: _TC.textSub(context)),
                ),
              ],
            );
          }).toList(),
        ),
      ],
    );
  }
}
