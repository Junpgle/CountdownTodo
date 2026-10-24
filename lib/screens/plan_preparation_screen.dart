import 'dart:async';

import 'package:flutter/material.dart';

import '../models.dart';
import '../models/plan_availability.dart';
import '../models/plan_weekly_availability.dart';
import '../services/plan_availability_preferences.dart';
import '../services/plan_availability_repository.dart';
import '../services/plan_availability_service.dart';
import '../services/plan_weekly_availability_preferences.dart';
import '../services/time_estimation_service.dart';
import '../storage_service.dart';
import '../utils/page_transitions.dart';
import '../utils/time_utils.dart';
import '../widgets/plan_block_editor_sheet.dart';
import '../widgets/time_estimation_hint.dart';
import 'todo_plan_screen.dart';

typedef PlanPreparationScheduleLoader = Future<FixedScheduleItem?> Function(
  String username,
  String scheduleId,
);
typedef PlanPreparationTodoLoader = Future<TodoItem?> Function(
  String username,
  String todoId,
);
typedef PlanPreparationBlocksLoader = Future<List<TodoPlanBlock>> Function(
  String username,
  String todoId,
);
typedef PlanPreparationEstimate = Future<TimeEstimationResult> Function(
  TodoItem todo,
);
typedef PlanPreparationRangeLoader = Future<PlanContinuousRangeResult> Function(
  PlanAvailabilityQuery query,
);
typedef PlanPreparationSelectionValidator =
    Future<PlanAvailabilitySelection> Function(
      PlanAvailabilitySelection selection,
    );
typedef PlanPreparationEditorOpener = Future<void> Function({
  required BuildContext context,
  required String username,
  required TodoItem todo,
  required DateTime startTime,
  required DateTime endTime,
  required FixedSchedulePreparationContext preparationContext,
  required PlanAvailabilitySelection preparationSelection,
});

class PlanPreparationScreen extends StatefulWidget {
  const PlanPreparationScreen({
    super.key,
    required this.username,
    required this.schedule,
    required this.todo,
    this.clock,
    this.loadSchedule,
    this.loadTodo,
    this.loadBlocks,
    this.estimate,
    this.search,
    this.revalidate,
    this.openEditor,
  });

  final String username;
  final FixedScheduleItem schedule;
  final TodoItem todo;
  final DateTime Function()? clock;
  final PlanPreparationScheduleLoader? loadSchedule;
  final PlanPreparationTodoLoader? loadTodo;
  final PlanPreparationBlocksLoader? loadBlocks;
  final PlanPreparationEstimate? estimate;
  final PlanPreparationRangeLoader? search;
  final PlanPreparationSelectionValidator? revalidate;
  final PlanPreparationEditorOpener? openEditor;

  @override
  State<PlanPreparationScreen> createState() => _PlanPreparationScreenState();
}

class _PlanPreparationScreenState extends State<PlanPreparationScreen> {
  late final TextEditingController _durationController;
  late FixedScheduleItem _schedule;
  late TodoItem _todo;
  TimeEstimationResult? _estimate;
  PlanAvoidancePreferences? _availabilityPreferences;
  PlanWeeklyPreferencesSnapshot? _weeklyPreferences;
  PlanContinuousRangeResult? _result;
  List<TodoPlanBlock> _existingPlans = const [];
  String? _error, _calendarFailure;
  int _minutes = 0, _pageOffset = 0, _generation = 0;
  bool _loading = true, _searching = false, _opening = false, _appOnly = false;

  DateTime get _now => widget.clock?.call() ?? DateTime.now();
  DateTime get _pageStart {
    final now = _now;
    final today = DateTime(now.year, now.month, now.day);
    return today.add(Duration(days: _pageOffset));
  }

  DateTime get _preparationEnd =>
      DateTime.fromMillisecondsSinceEpoch(_schedule.startTime!).toLocal();

  @override
  void initState() {
    super.initState();
    _schedule = FixedScheduleItem.fromJson(widget.schedule.toJson());
    _todo = TodoItem.fromJson(widget.todo.toJson());
    _durationController = TextEditingController();
    unawaited(_load());
  }

  @override
  void dispose() {
    _generation++;
    _durationController.dispose();
    super.dispose();
  }

  Future<FixedScheduleItem?> _readSchedule() async {
    final load = widget.loadSchedule;
    if (load != null) return load(widget.username, widget.schedule.id);
    final schedules = await StorageService.getFixedSchedules(widget.username);
    for (final schedule in schedules) {
      if (schedule.id == widget.schedule.id) return schedule;
    }
    return null;
  }

  Future<TodoItem?> _readTodo() async {
    final load = widget.loadTodo;
    if (load != null) return load(widget.username, widget.todo.id);
    final todos = await StorageService.getTodosForFixedScheduleRelationIds(
      widget.username,
      {widget.todo.id},
    );
    for (final todo in todos) {
      if (todo.id == widget.todo.id) return todo;
    }
    return null;
  }

  Future<List<TodoPlanBlock>> _readBlocks() async {
    final load = widget.loadBlocks;
    return load == null
        ? StorageService.getPlanBlocksByTodo(widget.username, widget.todo.id)
        : load(widget.username, widget.todo.id);
  }

  bool _sameTeam(TodoItem todo, FixedScheduleItem schedule) =>
      (todo.teamUuid?.trim().isEmpty ?? true ? null : todo.teamUuid?.trim()) ==
      (schedule.teamUuid?.trim().isEmpty ?? true
          ? null
          : schedule.teamUuid?.trim());

  String? _invalidContext(FixedScheduleItem? schedule, TodoItem? todo) {
    if (schedule == null || schedule.isDeleted) return '固定日程已删除或无法读取，请返回详情页刷新';
    if (schedule.startTime == null ||
        schedule.startTime != widget.schedule.startTime ||
        schedule.status != FixedScheduleStatus.scheduled ||
        schedule.phaseAt(_now) != FixedSchedulePhase.upcoming) {
      return '固定日程已开始、结束或调整时间，不能继续使用这次推荐';
    }
    if (todo == null ||
        todo.isDeleted ||
        todo.isDone ||
        todo.isSkipped ||
        todo.hasConflict ||
        !schedule.relatedTodoIds.contains(widget.todo.id) ||
        !_sameTeam(todo, schedule)) {
      return '关联待办已完成、跳过、删除或失去关联，请返回详情页刷新';
    }
    if (!_preparationEnd.isAfter(_now)) return '固定日程已开始，无法安排准备时间';
    return null;
  }

  Future<void> _load() async {
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
      _calendarFailure = null;
      _result = null;
    });
    try {
      final schedule = await _readSchedule();
      final todo = await _readTodo();
      final invalid = _invalidContext(schedule, todo);
      if (invalid != null) throw StateError(invalid);
      final estimate =
          await (widget.estimate?.call(todo!) ??
              TimeEstimationService.estimate(
                todo!.title,
                groupId: todo.groupId,
                username: widget.username,
                clock: widget.clock,
              ));
      final availability = await PlanAvailabilityPreferences.load(
        widget.username,
      );
      if (availability.bufferError != null) {
        throw StateError(availability.bufferError!);
      }
      final weekly = await PlanWeeklyAvailabilityPreferences.load(
        widget.username,
      );
      if (weekly.error != null || weekly.rules == null) {
        throw StateError(weekly.error ?? '每周可安排时间无法读取，请修复规则后重试');
      }
      final blocks = await _readBlocks();
      if (!mounted || generation != _generation) return;
      setState(() {
        _schedule = schedule!;
        _todo = todo!;
        _estimate = estimate;
        _availabilityPreferences = availability;
        _weeklyPreferences = weekly;
        _existingPlans = blocks.where(PlanAvailabilityService.occupies).toList()
          ..sort((a, b) => a.startTime.compareTo(b.startTime));
        _minutes = estimate.estimatedMinutes.clamp(1, 1440);
        _durationController.text = '$_minutes';
        _loading = false;
      });
      await _search();
    } catch (error) {
      if (mounted && generation == _generation) {
        setState(() {
          _error = error is StateError ? error.message.toString() : '$error';
          _loading = false;
        });
      }
    }
  }

  PlanAvailabilityQuery _query() {
    final availability = _availabilityPreferences!;
    return PlanAvailabilityQuery(
      username: widget.username,
      todoId: _todo.id,
      date: _pageStart,
      minutes: _minutes,
      windowStart: 0,
      windowEnd: 1440,
      appOnly: _appOnly,
      resultLimit: 5,
      avoidWindows: [
        for (final index in availability.selectedIndices)
          availability.options[index],
      ],
      bufferBefore: availability.bufferBefore,
      bufferAfter: availability.bufferAfter,
      bufferDefaultsKey: availability.bufferKey,
      avoidanceDefaultsKey: availability.avoidanceKey,
      preparationEnd: _preparationEnd,
      weekly: PlanWeeklyContext(_weeklyPreferences!.rules),
    );
  }

  Future<void> _search() async {
    if (_loading ||
        _availabilityPreferences == null ||
        _weeklyPreferences == null) {
      return;
    }
    final generation = ++_generation;
    setState(() {
      _searching = true;
      _error = null;
      _calendarFailure = null;
      _result = null;
    });
    try {
      final schedule = await _readSchedule();
      final todo = await _readTodo();
      final invalid = _invalidContext(schedule, todo);
      if (invalid != null) throw StateError(invalid);
      final query = _query();
      final result =
          await (widget.search?.call(query) ??
              PlanAvailabilityRepository(clock: widget.clock)
                  .readPreparationWindow(query));
      if (!mounted || generation != _generation) return;
      setState(() {
        _schedule = schedule!;
        _todo = todo!;
        _result = result;
        _searching = false;
      });
    } on PlanAvailabilityException catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _calendarFailure = error.canUseAppOnly ? error.message : null;
        _error = error.canUseAppOnly ? null : error.message;
        _result = null;
        _searching = false;
      });
    } catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _error = error is StateError ? error.message.toString() : '$error';
        _result = null;
        _searching = false;
      });
    }
  }

  void _setDuration(int value) {
    final minutes = value.clamp(1, 1440);
    setState(() {
      _minutes = minutes;
      _durationController.text = '$minutes';
      _result = null;
    });
  }

  Future<void> _useAppOnly() async {
    final allowed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('仅检查应用内日程？'),
        content: Text(
          '${_calendarFailure ?? '手机日历读取失败'}\n\n继续后，推荐不会计入手机日历中的忙碌时段。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('继续查找'),
          ),
        ],
      ),
    );
    if (allowed != true || !mounted) return;
    setState(() => _appOnly = true);
    await _search();
  }

  bool get _canShowNextPage {
    final result = _result;
    if (result == null || !result.end.isAfter(_pageStart)) return false;
    return result.end.isBefore(_preparationEnd) ||
        DateTime(result.end.year, result.end.month, result.end.day).isBefore(
          DateTime(
            _preparationEnd.year,
            _preparationEnd.month,
            _preparationEnd.day,
          ),
        );
  }

  String _dateLabel(DateTime date) => AppTimeFormats.format(date, 'yyyy年M月d日');

  String _clockLabel(DateTime date) => AppTimeFormats.clock(date);

  Future<void> _adopt(PlanAvailabilitySelection selection) async {
    if (_opening) return;
    setState(() => _opening = true);
    try {
      final schedule = await _readSchedule();
      final todo = await _readTodo();
      final invalid = _invalidContext(schedule, todo);
      if (invalid != null) throw StateError(invalid);
      final currentTodo = todo!;
      final fresh =
          await (widget.revalidate?.call(selection) ??
              PlanAvailabilityRepository(clock: widget.clock)
                  .revalidateContinuous(selection));
      final preparationContext = FixedSchedulePreparationContext(
        scheduleId: schedule!.id,
        startTime: schedule.startTime!,
        appOnly: selection.query.appOnly,
      );
      if (!mounted) return;
      final openEditor = widget.openEditor;
      if (openEditor != null) {
        await openEditor(
          context: context,
          username: widget.username,
          todo: currentTodo,
          startTime: fresh.slot.start,
          endTime: fresh.slot.end,
          preparationContext: preparationContext,
          preparationSelection: fresh,
        );
      } else {
        await showPlanBlockEditorPage<void>(
          context: context,
          builder: (_) => PlanBlockEditorSheet(
            username: widget.username,
            fullPage: true,
            todos: [currentTodo],
            todoGroups: const [],
            initialTodoId: currentTodo.id,
            startTime: fresh.slot.start,
            endTime: fresh.slot.end,
            autoFillEstimateOnTodoChange: false,
            draftOrigin: 'recommended',
            preparationContext: preparationContext,
            preparationSelection: fresh,
            onSaved: () {},
          ),
        );
      }
      if (mounted) {
        await _refreshExistingPlans();
        await _search();
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              error is StateError ? error.message.toString() : '$error',
            ),
          ),
        );
        await _load();
      }
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  Future<void> _refreshExistingPlans() async {
    try {
      final plans = await _readBlocks();
      if (!mounted) return;
      setState(() {
        _existingPlans = plans.where(PlanAvailabilityService.occupies).toList()
          ..sort((a, b) => a.startTime.compareTo(b.startTime));
      });
    } catch (_) {
      // Availability search remains authoritative for whether a slot is free.
    }
  }

  Future<void> _openTimeline() async {
    if (_opening || _loading) return;
    setState(() => _opening = true);
    await Navigator.of(context).push<void>(
      PageTransitions.material(
        builder: (_) => TodoPlanScreen(
          username: widget.username,
          initialDate: _pageStart,
          initialTodoId: _todo.id,
        ),
      ),
    );
    if (!mounted) return;
    await _refreshExistingPlans();
    await _search();
    if (mounted) setState(() => _opening = false);
  }

  Widget _eventCard(ColorScheme colors, ThemeData theme) => Card(
    color: colors.secondaryContainer,
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.event_available_rounded,
            color: colors.onSecondaryContainer,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _schedule.title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: colors.onSecondaryContainer,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${_dateLabel(_preparationEnd)} · ${_clockLabel(_preparationEnd)} 开始',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colors.onSecondaryContainer,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '只用于本次时段推荐，不会修改待办期限。',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.onSecondaryContainer,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );

  Widget _durationCard(ColorScheme colors, ThemeData theme) => Card(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('准备待办', style: theme.textTheme.titleSmall),
          const SizedBox(height: 3),
          Text(
            _todo.title,
            style: theme.textTheme.titleMedium,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          if (_estimate != null) TimeEstimationHint(result: _estimate!),
          const Divider(height: 18),
          Row(
            children: [
              Expanded(child: Text('预计用时', style: theme.textTheme.titleSmall)),
              IconButton(
                tooltip: '减少15分钟',
                onPressed: _searching || _loading || _minutes <= 15
                    ? null
                    : () => _setDuration(_minutes - 15),
                icon: const Icon(Icons.remove_circle_outline_rounded),
              ),
              SizedBox(
                width: 76,
                child: TextField(
                  key: const ValueKey('preparation-duration'),
                  controller: _durationController,
                  enabled: !_loading && !_searching,
                  textAlign: TextAlign.center,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    suffixText: '分',
                    isDense: true,
                  ),
                  onChanged: (value) {
                    final minutes = int.tryParse(value);
                    setState(() {
                      _minutes = minutes != null && minutes > 0
                          ? minutes.clamp(1, 1440)
                          : 0;
                      _result = null;
                    });
                  },
                ),
              ),
              IconButton(
                tooltip: '增加15分钟',
                onPressed: _searching || _loading || _minutes >= 1440
                    ? null
                    : () => _setDuration(_minutes + 15),
                icon: const Icon(Icons.add_circle_outline_rounded),
              ),
            ],
          ),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.tonalIcon(
              key: const ValueKey('preparation-search'),
              onPressed: _minutes <= 0 || _searching || _loading
                  ? null
                  : _search,
              icon: _searching
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.search_rounded),
              label: Text(_searching ? '查找中' : '重新查找'),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _existingPlansCard(ColorScheme colors, ThemeData theme) {
    if (_existingPlans.isEmpty) return const SizedBox.shrink();
    final plans = _existingPlans.take(4).toList();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.event_note_rounded, color: colors.primary),
                const SizedBox(width: 8),
                Text('已有规划', style: theme.textTheme.titleSmall),
              ],
            ),
            const SizedBox(height: 8),
            for (final block in plans)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Text(
                  '${_dateLabel(DateTime.fromMillisecondsSinceEpoch(block.startTime).toLocal())} · '
                  '${AppTimeFormats.clock(DateTime.fromMillisecondsSinceEpoch(block.startTime).toLocal())}—'
                  '${AppTimeFormats.clock(DateTime.fromMillisecondsSinceEpoch(block.endTime).toLocal())}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ),
            if (_existingPlans.length > plans.length)
              Text(
                '还有 ${_existingPlans.length - plans.length} 条规划',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _weekNavigation(ThemeData theme) => Row(
    children: [
      IconButton.filledTonal(
        tooltip: '上一周',
        onPressed: _pageOffset == 0 || _searching
            ? null
            : () {
                setState(
                  () => _pageOffset = (_pageOffset - 7).clamp(0, 100000),
                );
                _search();
              },
        icon: const Icon(Icons.chevron_left_rounded),
      ),
      Expanded(
        child: Text(
          '${_dateLabel(_pageStart)} 起的 7 天',
          textAlign: TextAlign.center,
          style: theme.textTheme.titleSmall,
        ),
      ),
      IconButton.filledTonal(
        tooltip: '下一周',
        onPressed: !_canShowNextPage || _searching
            ? null
            : () {
                setState(() => _pageOffset += 7);
                _search();
              },
        icon: const Icon(Icons.chevron_right_rounded),
      ),
    ],
  );

  Widget _candidateCard(
    PlanAvailabilitySelection selection,
    int index,
    ColorScheme colors,
    ThemeData theme,
  ) {
    final start = selection.slot.start;
    final end = selection.slot.end;
    final sameDay =
        start.year == end.year &&
        start.month == end.month &&
        start.day == end.day;
    return Card(
      key: ValueKey('preparation-candidate-$index'),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 30,
                  height: 30,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: colors.primaryContainer,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${index + 1}',
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: colors.onPrimaryContainer,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _dateLabel(start),
                    style: theme.textTheme.titleSmall,
                  ),
                ),
                Text(
                  '${selection.slot.minutes} 分钟',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: colors.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '${_clockLabel(start)} — ${sameDay ? _clockLabel(end) : '${_dateLabel(end)} ${_clockLabel(end)}'}',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: _opening || _searching
                    ? null
                    : () => _adopt(selection),
                icon: const Icon(Icons.edit_calendar_rounded),
                label: const Text('检查并安排'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _resultSection(ColorScheme colors, ThemeData theme) {
    if (_searching) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 28),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    final result = _result;
    if (result == null) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _weekNavigation(theme),
        if (_appOnly)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              '仅检查应用内日程 · 未计入手机日历',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.tertiary,
              ),
            ),
          ),
        if (result.selections.isEmpty)
          Card(
            color: colors.surfaceContainerLow,
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                children: [
                  Icon(
                    Icons.event_busy_rounded,
                    color: colors.onSurfaceVariant,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '这段时间没有连续 $_minutes 分钟的可用时段',
                    style: theme.textTheme.titleSmall,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '可以调整预计用时、查看下一周，或到时间轴手动拖动安排。',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          )
        else ...[
          Text(
            '推荐时段 · ${result.selections.length} 个',
            style: theme.textTheme.titleSmall,
          ),
          const SizedBox(height: 4),
          Text(
            result.coverage,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          for (var i = 0; i < result.selections.length; i++)
            _candidateCard(result.selections[i], i, colors, theme),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
    return Scaffold(
      key: const ValueKey('fixed-schedule-preparation-screen'),
      appBar: AppBar(title: const Text('安排准备时间')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: _error != null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.sync_problem_rounded,
                              color: colors.error,
                            ),
                            const SizedBox(height: 12),
                            Text(_error!, textAlign: TextAlign.center),
                            const SizedBox(height: 12),
                            FilledButton.tonalIcon(
                              onPressed: _load,
                              icon: const Icon(Icons.refresh_rounded),
                              label: const Text('重新读取'),
                            ),
                          ],
                        ),
                      ),
                    )
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                      children: [
                        _eventCard(colors, theme),
                        _durationCard(colors, theme),
                        _existingPlansCard(colors, theme),
                        if (_calendarFailure != null)
                          Card(
                            color: colors.errorContainer,
                            child: Padding(
                              padding: const EdgeInsets.all(14),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '手机日历暂不可用',
                                    style: theme.textTheme.titleSmall?.copyWith(
                                      color: colors.onErrorContainer,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    _calendarFailure!,
                                    style: TextStyle(
                                      color: colors.onErrorContainer,
                                    ),
                                  ),
                                  Align(
                                    alignment: Alignment.centerRight,
                                    child: TextButton(
                                      onPressed: _useAppOnly,
                                      child: const Text('仅检查应用内日程'),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        if (_error != null)
                          Card(
                            color: colors.errorContainer,
                            child: Padding(
                              padding: const EdgeInsets.all(14),
                              child: Text(
                                _error!,
                                style: TextStyle(
                                  color: colors.onErrorContainer,
                                ),
                              ),
                            ),
                          ),
                        _resultSection(colors, theme),
                      ],
                    ),
            ),
      bottomNavigationBar: _loading || _error != null
          ? null
          : SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: OutlinedButton.icon(
                  key: const ValueKey('preparation-open-timeline'),
                  onPressed: _opening ? null : _openTimeline,
                  icon: const Icon(Icons.view_timeline_rounded),
                  label: const Text('到时间轴拖动安排'),
                ),
              ),
            ),
    );
  }
}
