import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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
import '../widgets/app_sheet_widgets.dart';
import 'time_log_save_confirmation.dart';

part 'time_log_components.dart';
part 'time_log/time_log_entry_sheets.dart';
part 'time_log/time_log_tag_detail_sheet.dart';
part 'time_log/time_log_charts_and_widgets.dart';
part 'time_log/time_log_detail_sheets.dart';
part 'time_log/time_log_week_view.dart';
part 'time_log/time_log_week_painters.dart';
part 'time_log/time_log_day_grid_view.dart';

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
                  onAggregatedSchedulesTap: _showAggregatedScheduleSheet,
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

  void _mutateState(VoidCallback fn) => setState(fn);
}
