import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../models.dart';
import '../../../storage_service.dart';
import '../../../services/pomodoro_service.dart';
import '../../../screens/course_screens.dart';
import '../../../utils/app_color_utils.dart';
import '../../../utils/app_dialogs.dart';
import '../../../utils/calendar_date_math.dart';
import '../../../utils/page_transitions.dart';
import '../../../utils/todo_recurrence_picker.dart';
import '../../../widgets/optional_liquid_glass_surface.dart';

part 'parts/stats_view_sections.dart';
part 'parts/stats_view_editor.dart';
part 'parts/stats_view_widgets.dart';

class _MonthlyPomodoroSummary {
  final int month;
  int focusSeconds = 0;
  int sessionCount = 0;
  int completedCount = 0;

  _MonthlyPomodoroSummary(this.month);

  void add(PomodoroSessionSummary session) {
    focusSeconds += session.effectiveDuration;
    sessionCount++;
    if (session.isCompleted) completedCount++;
  }
}

class PomodoroStats extends StatefulWidget {
  final String username;
  final bool isCompact;
  final int initialDimension;
  const PomodoroStats({
    super.key,
    required this.username,
    this.isCompact = false,
    this.initialDimension = 0,
  });

  @override
  State<PomodoroStats> createState() => PomodoroStatsState();
}

class PomodoroStatsState extends State<PomodoroStats> {
  int _dimension = 0; // 0: Day, 1: Week, 2: Month, 3: Year
  DateTime _selected = DateTime.now();
  List<PomodoroSession> _sessions = [];
  List<PomodoroTag> _tags = [];
  Map<String, PomodoroTag> _tagsByUuid = {};
  int _sessionTotalSeconds = 0;
  Map<String, int> _sessionFocusByTag = {};
  int _completedSessionCount = 0;
  List<TodoItem> _todos = [];
  List<TodoGroup> _todoGroups = [];
  Map<String, String> _todoGroupNamesById = {};
  List<_MonthlyPomodoroSummary> _yearlyMonthlySummaries = [];
  Map<int, int> _yearlyFocusSeconds = {};
  Map<String, int> _yearlyTagSeconds = {};
  int _yearlyTotalSeconds = 0;
  int _yearlyCompletedCount = 0;
  bool _loading = true;
  bool _syncing = false;
  List<PomodoroSession> _chartSessions = [];
  PomodoroCommunityStats? _communityStats;
  int _loadGeneration = 0;

  void _mutateState(VoidCallback fn) => setState(fn);

  @override
  void initState() {
    super.initState();
    _dimension = widget.initialDimension; // 🚀 使用初始维度
    _loadLocal().then((_) => _syncIfDue());
    _loadCommunityStats();
  }

  void reload() {
    _loadLocal().then((_) => _syncAndRefresh());
    _loadCommunityStats(forceRefresh: true);
  }

  Future<void> _loadCommunityStats({bool forceRefresh = false}) async {
    final stats = await PomodoroService.getTodayCommunityStats(
      forceRefresh: forceRefresh,
    );
    if (!mounted) return;
    if (stats?.avgSeconds != _communityStats?.avgSeconds) {
      setState(() => _communityStats = stats);
    }
  }

  Future<void> _syncIfDue() async {
    final interval = await StorageService.getSyncInterval();
    if (interval == 0) return;
    final lastSync = await StorageService.getLastAutoSyncTime(widget.username);
    final now = DateTime.now();
    bool due = false;
    if (lastSync == null) {
      due = true;
    } else {
      switch (interval) {
        case 1:
          due = true;
          break;
        case 2:
          due = now.difference(lastSync).inMinutes >= 30;
          break;
        case 3:
          due = now.difference(lastSync).inHours >= 1;
          break;
        case 4:
          due = now.difference(lastSync).inHours >= 24;
          break;
        default:
          due = false;
      }
    }
    if (due) _syncAndRefresh();
  }

  Future<void> _syncAndRefresh() async {
    if (!mounted) return;
    setState(() => _syncing = true);
    try {
      await PomodoroService.syncTagsFromCloud();
      await PomodoroService.syncRecordsFromCloud();
    } catch (e) {
      // debugPrint('[PomodoroStats] _syncAndRefresh error: $e');
    }
    if (!mounted) return;
    setState(() => _syncing = false);
    await _loadLocal();
  }

  Future<void> _fullPull() async {
    if (!mounted) return;
    setState(() => _loading = true);
    try {
      await PomodoroService.syncTagsFromCloud();
      await PomodoroService.syncRecordsFromCloud(fromMs: 0);
    } catch (_) {}
    await _loadLocal();
  }

  Future<void> _loadLocal() async {
    if (!mounted) return;
    final loadGeneration = ++_loadGeneration;
    final dimension = _dimension;
    final selected = _selected;
    final detailRange = _getRange();
    final chartRange = _getChartRange();
    final isYearly = dimension == 3;
    setState(() => _loading = true);

    final results = await Future.wait([
      PomodoroService.getTags(),
      StorageService.getTodos(widget.username),
      StorageService.getTodoGroups(widget.username),
      isYearly
          ? PomodoroService.getSessionSummariesInRange(
              chartRange.start,
              chartRange.end,
              tagsFrom: detailRange.start,
              tagsTo: detailRange.end,
            )
          : PomodoroService.getSessionsInRange(
              chartRange.start,
              chartRange.end,
            ),
    ]);

    // 🚀 核心优化：等待 300ms 让进入页面的过渡动画彻底完成
    // 避免在此期间进行大量 CPU 计算导致掉帧
    await Future.delayed(const Duration(milliseconds: 300));

    if (!mounted || loadGeneration != _loadGeneration) return;

    final tags = results[0] as List<PomodoroTag>;
    final allTodos = results[1] as List<TodoItem>;
    final groups = results[2] as List<TodoGroup>;
    List<PomodoroSession> chartSessions = [];
    List<PomodoroSession> sessions = [];
    List<_MonthlyPomodoroSummary> monthlySummaries = [];
    Map<int, int> yearlyFocusSeconds = {};
    Map<String, int> yearlyTagSeconds = {};
    var yearlyTotalSeconds = 0;
    var yearlyCompletedCount = 0;

    if (isYearly) {
      monthlySummaries = List.generate(
        12,
        (index) => _MonthlyPomodoroSummary(index + 1),
      );
      final summaries = results[3] as List<PomodoroSessionSummary>;
      final detailStartMs = detailRange.start.millisecondsSinceEpoch;
      final detailEndMs = detailRange.end.millisecondsSinceEpoch;

      for (final summary in summaries) {
        final localStart = AppTimeFormats.localFromServerTimestamp(
          summary.startTime,
        );
        yearlyFocusSeconds.update(
          localStart.year,
          (seconds) => seconds + summary.effectiveDuration,
          ifAbsent: () => summary.effectiveDuration,
        );

        if (summary.startTime < detailStartMs ||
            summary.startTime >= detailEndMs ||
            localStart.year != selected.year) {
          continue;
        }

        yearlyTotalSeconds += summary.effectiveDuration;
        if (summary.isCompleted) yearlyCompletedCount++;
        monthlySummaries[localStart.month - 1].add(summary);

        final tagUuids = summary.tagUuids.isEmpty
            ? const ['__none__']
            : summary.tagUuids;
        for (final uuid in tagUuids) {
          yearlyTagSeconds.update(
            uuid,
            (seconds) => seconds + summary.effectiveDuration,
            ifAbsent: () => summary.effectiveDuration,
          );
        }
      }
    } else {
      final allSessions = results[3] as List<PomodoroSession>;
      chartSessions = allSessions;
      sessions = allSessions.where((session) {
        return session.startTime >= detailRange.start.millisecondsSinceEpoch &&
            session.startTime < detailRange.end.millisecondsSinceEpoch;
      }).toList();
    }
    sessions.sort((a, b) => b.startTime.compareTo(a.startTime));

    final tagsByUuid = <String, PomodoroTag>{};
    for (final tag in tags) {
      tagsByUuid.putIfAbsent(tag.uuid, () => tag);
    }
    var sessionTotalSeconds = 0;
    var completedSessionCount = 0;
    final sessionFocusByTag = <String, int>{};
    for (final session in sessions) {
      final duration = session.effectiveDuration;
      sessionTotalSeconds += duration;
      if (session.isCompleted) completedSessionCount++;
      if (session.tagUuids.isEmpty) {
        sessionFocusByTag.update(
          '__none__',
          (seconds) => seconds + duration,
          ifAbsent: () => duration,
        );
      } else {
        for (final uuid in session.tagUuids) {
          sessionFocusByTag.update(
            uuid,
            (seconds) => seconds + duration,
            ifAbsent: () => duration,
          );
        }
      }
    }

    final todoGroups = groups.where((g) => !g.isDeleted).toList();
    final todoGroupNamesById = <String, String>{};
    for (final group in todoGroups) {
      if (!todoGroupNamesById.containsKey(group.id)) {
        todoGroupNamesById[group.id] = group.name;
      }
    }

    setState(() {
      _tags = tags;
      _tagsByUuid = tagsByUuid;
      _sessionTotalSeconds = sessionTotalSeconds;
      _sessionFocusByTag = sessionFocusByTag;
      _completedSessionCount = completedSessionCount;
      _todos = allTodos.where((t) => !t.isDeleted).toList();
      _todoGroups = todoGroups;
      _todoGroupNamesById = todoGroupNamesById;
      _chartSessions = chartSessions;
      _sessions = sessions;
      _yearlyMonthlySummaries = monthlySummaries;
      _yearlyFocusSeconds = yearlyFocusSeconds;
      _yearlyTagSeconds = yearlyTagSeconds;
      _yearlyTotalSeconds = yearlyTotalSeconds;
      _yearlyCompletedCount = yearlyCompletedCount;
      _loading = false;
    });
  }

  DateTimeRange _getRange() {
    if (_dimension == 0) {
      final range = CalendarDateMath.dayRange(_selected);
      return DateTimeRange(start: range.start, end: range.endExclusive);
    } else if (_dimension == 1) {
      final range = CalendarDateMath.weekRange(_selected);
      return DateTimeRange(start: range.start, end: range.endExclusive);
    } else if (_dimension == 2) {
      final start = DateTime(_selected.year, _selected.month, 1);
      final end = DateTime(_selected.year, _selected.month + 1, 1);
      return DateTimeRange(start: start, end: end);
    } else {
      final start = DateTime(_selected.year, 1, 1);
      final end = DateTime(_selected.year + 1, 1, 1);
      return DateTimeRange(start: start, end: end);
    }
  }

  DateTimeRange _getChartRange() {
    if (_dimension == 0) {
      final base = CalendarDateMath.dateOnly(_selected);
      final start = CalendarDateMath.addDays(base, -5);
      final end = CalendarDateMath.addDays(base, 2);
      return DateTimeRange(start: start, end: end);
    } else if (_dimension == 1) {
      final range = _getRange();
      final start = CalendarDateMath.addDays(range.start, -5 * 7);
      final end = CalendarDateMath.addDays(range.start, 2 * 7);
      return DateTimeRange(start: start, end: end);
    } else if (_dimension == 2) {
      final start = DateTime(_selected.year, _selected.month - 5, 1);
      final end = DateTime(_selected.year, _selected.month + 2, 1);
      return DateTimeRange(start: start, end: end);
    } else {
      final start = DateTime(_selected.year - 5, 1, 1);
      final end = DateTime(_selected.year + 2, 1, 1);
      return DateTimeRange(start: start, end: end);
    }
  }

  String _rangeLabel() {
    if (_dimension == 0) {
      return AppTimeFormats.dateFormatter('yyyy年MM月dd日').format(_selected);
    }
    if (_dimension == 1) {
      final range = _getRange();
      final startStr = AppTimeFormats.dateFormatter('MM/dd')
          .format(range.start);
      final endStr = AppTimeFormats.dateFormatter('MM/dd')
          .format(range.end.subtract(const Duration(seconds: 1)));
      return '$startStr - $endStr';
    }
    if (_dimension == 2) {
      return AppTimeFormats.dateFormatter('yyyy年MM月').format(_selected);
    }
    return '${_selected.year}年';
  }

  void _prev() {
    setState(() {
      if (_dimension == 0) {
        _selected = CalendarDateMath.addDays(_selected, -1);
      } else if (_dimension == 1) {
        _selected = CalendarDateMath.addDays(_selected, -7);
      } else if (_dimension == 2) {
        _selected = DateTime(_selected.year, _selected.month - 1, 1);
      } else {
        _selected = DateTime(_selected.year - 1, 1, 1);
      }
    });
    _loadLocal();
  }

  void _next() {
    setState(() {
      if (_dimension == 0) {
        _selected = CalendarDateMath.addDays(_selected, 1);
      } else if (_dimension == 1) {
        _selected = CalendarDateMath.addDays(_selected, 7);
      } else if (_dimension == 2) {
        _selected = DateTime(_selected.year, _selected.month + 1, 1);
      } else {
        _selected = DateTime(_selected.year + 1, 1, 1);
      }
    });
    _loadLocal();
  }

  Future<void> _pickDay() async {
    final now = DateTime.now();
    final picked = await showAppDatePicker(
      context: context,
      initialDate: _selected.isAfter(now) ? now : _selected,
      firstDate: DateTime(1970),
      lastDate: DateTime(now.year + 1, 12, 31),
      helpText: '选择日期',
      cancelText: '取消',
      confirmText: '确定',
    );
    if (!mounted || picked == null) return;
    final pickedDate = CalendarDateMath.dateOnly(picked);
    if (AppTimeFormats.isSameDay(pickedDate, _selected)) {
      return;
    }
    setState(() => _selected = pickedDate);
    _loadLocal();
  }

  Future<void> _pickWeek() async {
    final now = DateTime.now();
    final picked = await showAppDatePicker(
      context: context,
      initialDate: _selected.isAfter(now) ? now : _selected,
      firstDate: DateTime(1970),
      lastDate: DateTime(now.year + 1, 12, 31),
      helpText: '选择周内任意日期以跳转到该周',
      cancelText: '取消',
      confirmText: '确定',
    );
    if (!mounted || picked == null) return;
    final pickedDate = CalendarDateMath.dateOnly(picked);
    final currentWeekRange = _getRange();
    if (pickedDate.isAfter(
          currentWeekRange.start.subtract(const Duration(seconds: 1)),
        ) &&
        pickedDate.isBefore(currentWeekRange.end)) {
      return;
    }
    setState(() => _selected = pickedDate);
    _loadLocal();
  }

  Future<void> _pickMonth() async {
    final now = DateTime.now();
    final picked = await showAppDialog<DateTime>(
      context: context,
      builder: (dialogContext) => _MonthPickerDialog(
        initialDate: _selected,
        firstDate: DateTime(1970),
        lastDate: DateTime(now.year),
      ),
    );
    if (!mounted || picked == null) return;
    if (picked.year == _selected.year && picked.month == _selected.month) {
      return;
    }
    setState(() => _selected = DateTime(picked.year, picked.month, 1));
    _loadLocal();
  }

  Future<void> _pickYear() async {
    final now = DateTime.now();
    final pickerYear = _selected.year.clamp(1970, now.year);
    final year = await showAppDialog<int>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('选择年份'),
        content: SizedBox(
          width: 320,
          height: 360,
          child: YearPicker(
            firstDate: DateTime(1970),
            lastDate: DateTime(now.year),
            currentDate: now,
            selectedDate: DateTime(pickerYear),
            onChanged: (date) => Navigator.of(dialogContext).pop(date.year),
          ),
        ),
      ),
    );
    if (!mounted || year == null || year == _selected.year) return;
    setState(() => _selected = DateTime(year, 1, 1));
    _loadLocal();
  }

  Future<void> _handleTitleTap() async {
    switch (_dimension) {
      case 0:
        await _pickDay();
        break;
      case 1:
        await _pickWeek();
        break;
      case 2:
        await _pickMonth();
        break;
      case 3:
        await _pickYear();
        break;
    }
  }

  void _openDay(DateTime day) {
    setState(() {
      _dimension = 0;
      _selected = CalendarDateMath.dateOnly(day);
    });
    _loadLocal();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return _buildSkeleton();
    final bool isDesktop =
        !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.windows ||
            defaultTargetPlatform == TargetPlatform.linux ||
            defaultTargetPlatform == TargetPlatform.macOS);
    final bool showDesktopActions = isDesktop || !widget.isCompact;

    final totalSecs = _dimension == 3
        ? _yearlyTotalSeconds
        : _sessionTotalSeconds;
    final byTag = _dimension == 3 ? _yearlyTagSeconds : _sessionFocusByTag;
    final completedCount = _dimension == 3
        ? _yearlyCompletedCount
        : _completedSessionCount;

    return MediaQuery.removePadding(
      context: context,
      removeTop: true,
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          widget.isCompact ? 16 : 20,
          widget.isCompact ? 4 : 12,
          widget.isCompact ? 16 : 20,
          24,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!widget.isCompact &&
                (Theme.of(context).platform == TargetPlatform.windows ||
                    Theme.of(context).platform == TargetPlatform.linux ||
                    Theme.of(context).platform == TargetPlatform.macOS))
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back),
                      onPressed: () => Navigator.maybePop(context),
                    ),
                    const Text(
                      '专注统计',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),

            // Navigation Row
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton.filledTonal(
                  visualDensity: widget.isCompact
                      ? VisualDensity.compact
                      : null,
                  icon: Icon(
                    Icons.chevron_left,
                    size: widget.isCompact ? 18 : 24,
                  ),
                  onPressed: _prev,
                ),
                InkWell(
                  onTap: _handleTitleTap,
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _rangeLabel(),
                          style: TextStyle(
                            fontSize: widget.isCompact ? 14 : 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(
                          Icons.arrow_drop_down_rounded,
                          size: widget.isCompact ? 18 : 22,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ],
                    ),
                  ),
                ),
                IconButton.filledTonal(
                  visualDensity: widget.isCompact
                      ? VisualDensity.compact
                      : null,
                  icon: Icon(
                    Icons.chevron_right,
                    size: widget.isCompact ? 18 : 24,
                  ),
                  onPressed: _next,
                ),
              ],
            ),

            const SizedBox(height: 12),
            Center(
              child: SegmentedButton<int>(
                segments: [
                  ButtonSegment(
                    value: 0,
                    label: Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: widget.isCompact ? 4 : 12,
                      ),
                      child: const Text('日'),
                    ),
                  ),
                  ButtonSegment(
                    value: 1,
                    label: Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: widget.isCompact ? 4 : 8,
                      ),
                      child: const Text('周'),
                    ),
                  ),
                  ButtonSegment(
                    value: 2,
                    label: Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: widget.isCompact ? 4 : 12,
                      ),
                      child: const Text('月'),
                    ),
                  ),
                  ButtonSegment(
                    value: 3,
                    label: Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: widget.isCompact ? 4 : 12,
                      ),
                      child: const Text('年'),
                    ),
                  ),
                ],
                selected: {_dimension},
                onSelectionChanged: (s) {
                  setState(() {
                    _dimension = s.first;
                  });
                  _loadLocal();
                },
              ),
            ),

            const SizedBox(height: 20),

            // --- Trend Chart ---
            RepaintBoundary(child: _buildTrendChart()),

            const SizedBox(height: 20),

            RepaintBoundary(
              child: _buildSummaryCard(totalSecs, completedCount),
            ),

            const SizedBox(height: 20),
            const Text(
              '标签分布',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            RepaintBoundary(child: _buildTagDistribution(byTag, totalSecs)),

            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _dimension == 3 ? '逐月概览' : '详细记录',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (_syncing)
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else if (showDesktopActions)
                  TextButton.icon(
                    onPressed: _syncAndRefresh,
                    icon: const Icon(Icons.sync, size: 16),
                    label: const Text('同步'),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if (_dimension == 3)
              ..._buildYearlyOverview()
            else
              ..._buildSessionList(),

            if (showDesktopActions) ...[
              const SizedBox(height: 40),
              Center(
                child: TextButton(
                  onPressed: _fullPull,
                  child: const Text('拉取全部历史记录'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
