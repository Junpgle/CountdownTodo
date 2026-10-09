import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models.dart';
import '../models/plan_availability.dart';
import '../screens/course_screens.dart';
import '../screens/fixed_schedule_detail_screen.dart';
import '../screens/pomodoro_screen.dart';
import '../services/device_calendar_read_service.dart';
import '../services/plan_conflict_review_service.dart';
import '../storage_service.dart';
import '../utils/page_transitions.dart';
import 'optional_liquid_glass_surface.dart';
import 'plan_block_editor_sheet.dart';

typedef PlanConflictReviewLoader = Future<PlanConflictReviewResult> Function(
  String username,
  DateTime date, {
  int days,
  bool appOnly,
});

String _time(DateTime value) => DateFormat('MM-dd HH:mm').format(value);
DateTime _day(DateTime value) => DateTime(value.year, value.month, value.day);
String _sourceName(PlanBusySource source) => switch (source) {
  PlanBusySource.course => '课程',
  PlanBusySource.fixedSchedule => '固定日程',
  PlanBusySource.planBlock => '另一规划',
  PlanBusySource.legacyTodo => '待办执行区间',
  PlanBusySource.deviceCalendar => '手机日历',
};

/// A compact foreground indicator. A failure or unknown source is never shown
/// as a clean result. Range changes and old responses are guarded separately.
class PlanConflictIndicator extends StatefulWidget {
  const PlanConflictIndicator({
    super.key,
    required this.username,
    this.date,
    this.refreshTrigger = 0,
    this.compact = false,
    this.onSaved,
    this.service = const PlanConflictReviewService(),
    this.loader,
  });
  final String username;
  final DateTime? date;
  final int refreshTrigger;
  final bool compact;
  final VoidCallback? onSaved;
  final PlanConflictReviewService service;
  final PlanConflictReviewLoader? loader;
  @override
  State<PlanConflictIndicator> createState() => _PlanConflictIndicatorState();
}

class _PlanConflictIndicatorState extends State<PlanConflictIndicator>
    with WidgetsBindingObserver {
  PlanConflictReviewResult? _result;
  PlanAvailabilityException? _error;
  int _sequence = 0;
  bool _opening = false;
  Timer? _wake;
  bool _foreground = true;
  DateTime get _date => _day(widget.date ?? widget.service.now);
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    StorageService.scopedDataRefreshNotifier.addListener(_onRefresh);
    DeviceCalendarReadService.revision.addListener(_reload);
    unawaited(_reload());
  }

  @override
  void didUpdateWidget(covariant PlanConflictIndicator old) {
    super.didUpdateWidget(old);
    if (old.username != widget.username ||
        old.date != widget.date ||
        old.refreshTrigger != widget.refreshTrigger ||
        old.loader != widget.loader ||
        old.service != widget.service) {
      unawaited(_reload());
    }
  }

  void _onRefresh() {
    final signal = StorageService.scopedDataRefreshNotifier.value;
    if ([
      DataRefreshDomain.todos,
      DataRefreshDomain.courses,
      DataRefreshDomain.fixedSchedules,
      DataRefreshDomain.planBlocks,
      DataRefreshDomain.pomodoro,
    ].any(signal.affects)) {
      unawaited(_reload());
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _wake?.cancel();
    if (_foreground) unawaited(_reload());
  }

  Future<void> _reload() async {
    if (!mounted || !_foreground) return;
    final sequence = ++_sequence;
    final date = _date;
    final username = widget.username;
    _wake?.cancel();
    setState(() {
      _result = null;
      _error = null;
    });
    try {
      final result = await (widget.loader ?? widget.service.read)(
        username,
        date,
        days: 1,
        appOnly: false,
      );
      if (!mounted || sequence != _sequence || username != widget.username) {
        return;
      }
      if (date != _date) {
        unawaited(_reload());
        return;
      }
      setState(() => _result = result);
      final now = widget.service.now;
      var next = DateTime(now.year, now.month, now.day + 1);
      for (final entry in result.entries) {
        final end = DateTime.fromMillisecondsSinceEpoch(entry.block.endTime);
        if (end.isAfter(now) && end.isBefore(next)) next = end;
      }
      if (_foreground) {
        _wake = Timer(next.difference(now), () => unawaited(_reload()));
      }
    } catch (error) {
      if (!mounted || sequence != _sequence) return;
      setState(
        () => _error = error is PlanAvailabilityException
            ? error
            : const PlanAvailabilityException('安排读取失败，请重试'),
      );
    }
  }

  Future<void> _open() async {
    if (_opening) return;
    setState(() => _opening = true);
    try {
      await showPlanConflictReview(
        context: context,
        username: widget.username,
        date: _date,
        initial: _result,
        service: widget.service,
        loader: widget.loader,
        onSaved: widget.onSaved,
        onResult: (result) {
          if (mounted &&
              result.username == widget.username &&
              result.start == _date &&
              result.end == DateTime(_date.year, _date.month, _date.day + 1)) {
            setState(() {
              _result = result;
              _error = null;
            });
          }
        },
      );
    } finally {
      if (mounted) {
        setState(() => _opening = false);
        unawaited(_reload());
      }
    }
  }

  @override
  void dispose() {
    ++_sequence;
    _wake?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    StorageService.scopedDataRefreshNotifier.removeListener(_onRefresh);
    DeviceCalendarReadService.revision.removeListener(_reload);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;
    final incomplete = _error != null || result?.complete == false;
    final count = result?.entries.length ?? 0;
    if (!incomplete && count == 0) return const SizedBox.shrink();
    final label = incomplete ? '冲突检查未完成' : '$count条规划时间重叠';
    final color = incomplete
        ? Theme.of(context).colorScheme.onSurfaceVariant
        : Theme.of(context).colorScheme.error;
    if (widget.compact) {
      return IconButton(
        key: const ValueKey('plan-conflict-indicator'),
        tooltip: label,
        onPressed: _opening ? null : _open,
        icon: Badge(
          label: Text(incomplete ? '!' : '$count'),
          child: Icon(Icons.event_busy_outlined, color: color),
        ),
      );
    }
    return TextButton.icon(
      key: const ValueKey('plan-conflict-indicator'),
      onPressed: _opening ? null : _open,
      icon: Icon(Icons.event_busy_outlined, size: 18, color: color),
      label: Text(label, style: TextStyle(color: color)),
    );
  }
}

enum _ActionKind { adjust, focus, source }

class _ReviewAction {
  const _ReviewAction(this.kind, this.entry, [this.source]);
  final _ActionKind kind;
  final PlanConflictEntry entry;
  final PlanBusyInterval? source;
}

Future<void> showPlanConflictReview({
  required BuildContext context,
  required String username,
  required DateTime date,
  PlanConflictReviewResult? initial,
  PlanConflictReviewService service = const PlanConflictReviewService(),
  PlanConflictReviewLoader? loader,
  VoidCallback? onSaved,
  ValueChanged<PlanConflictReviewResult>? onResult,
}) async {
  ModalRoute<dynamic>? route;
  final action = await showPlanBlockEditorSheet<_ReviewAction>(
    context: context,
    builder: (sheetContext) {
      route = ModalRoute.of(sheetContext);
      return PlanConflictReviewSheet(
        username: username,
        date: date,
        initial: initial,
        service: service,
        loader: loader,
        onResult: onResult,
      );
    },
  );
  await route?.completed;
  if (!context.mounted || action == null) return;
  try {
    if ((await StorageService.getLoginSession() ?? 'default') != username) {
      throw const PlanAvailabilityException('账号已切换，请重新打开冲突列表');
    }
    if (!context.mounted) return;
    if (action.kind == _ActionKind.focus) {
      await Navigator.of(context).push(
        PageTransitions.material(
          builder: (_) => PomodoroScreen(username: username),
        ),
      );
    } else if (action.kind == _ActionKind.adjust) {
      final edit = await service.prepareEdit(username, action.entry.block.id);
      if (!context.mounted) return;
      await showPlanBlockEditorPage<void>(
        context: context,
        builder: (_) => PlanBlockEditorSheet(
          fullPage: true,
          conflictEdit: edit,
          conflictService: service,
          block: edit.block,
          username: username,
          todos: [edit.todo],
          todoGroups: const [],
          initialTodoId: edit.todo.id,
          autoFillEstimateOnTodoChange: false,
          startTime: DateTime.fromMillisecondsSinceEpoch(edit.block.startTime),
          endTime: DateTime.fromMillisecondsSinceEpoch(edit.block.endTime),
          clock: service.clock,
          availabilityLoader: (query, {bool forceRefresh = false}) =>
              service.availability.read(query, forceRefresh: forceRefresh),
          onSaved: onSaved ?? () {},
        ),
      );
    } else {
      final record = action.source?.record;
      final Widget page;
      if (record is CourseItem) {
        page = CourseDetailScreen(course: record);
      } else if (record is FixedScheduleItem) {
        page = FixedScheduleDetailScreen(username: username, item: record);
      } else if (record is DeviceCalendarEvent) {
        page = DeviceCalendarEventDetailScreen(event: record);
      } else if (record is TodoItem) {
        page = TodoDetailScreen(todo: record);
      } else if (record is TodoPlanBlock) {
        page = PlanConflictPlanDetailScreen(block: record);
      } else {
        throw const PlanAvailabilityException('来源已变化，请刷新列表');
      }
      await Navigator.of(context)
          .push(PageTransitions.material(builder: (_) => page));
    }
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error is PlanAvailabilityException ? error.message : '读取安排失败，请重试',
          ),
        ),
      );
    }
  }
}

class PlanConflictReviewSheet extends StatefulWidget {
  const PlanConflictReviewSheet({
    super.key,
    required this.username,
    required this.date,
    this.initial,
    this.service = const PlanConflictReviewService(),
    this.loader,
    this.onResult,
  });
  final ValueChanged<PlanConflictReviewResult>? onResult;
  final String username;
  final DateTime date;
  final PlanConflictReviewResult? initial;
  final PlanConflictReviewService service;
  final PlanConflictReviewLoader? loader;
  @override
  State<PlanConflictReviewSheet> createState() =>
      _PlanConflictReviewSheetState();
}

class _PlanConflictReviewSheetState extends State<PlanConflictReviewSheet>
    with WidgetsBindingObserver {
  PlanConflictReviewResult? _result;
  PlanAvailabilityException? _error;
  bool _loading = false, _appOnly = false;
  int _range = 0, _sequence = 0;
  Timer? _wake;
  bool _foreground = true;
  DateTime get _today => _day(widget.service.now);
  DateTime get _date => _range == 0 ? _day(widget.date) : _today;
  int get _days => _range == 2 ? 7 : 1;
  @override
  void initState() {
    super.initState();
    _result = widget.initial;
    _range = _day(widget.date) == _today ? 1 : 0;
    WidgetsBinding.instance.addObserver(this);
    StorageService.scopedDataRefreshNotifier.addListener(_onRefresh);
    DeviceCalendarReadService.revision.addListener(_reload);
    unawaited(_reload());
  }

  void _onRefresh() {
    final signal = StorageService.scopedDataRefreshNotifier.value;
    if ([
      DataRefreshDomain.todos,
      DataRefreshDomain.courses,
      DataRefreshDomain.fixedSchedules,
      DataRefreshDomain.planBlocks,
      DataRefreshDomain.pomodoro,
    ].any(signal.affects)) {
      unawaited(_reload());
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _wake?.cancel();
    if (_foreground) unawaited(_reload());
  }

  Future<void> _reload() async {
    if (!mounted || !_foreground) return;
    final sequence = ++_sequence;
    final date = _date;
    _wake?.cancel();
    setState(() {
      _loading = true;
      _error = null;
      _result = null;
    });
    try {
      final result = await (widget.loader ?? widget.service.read)(
        widget.username,
        date,
        days: _days,
        appOnly: _appOnly,
      );
      if (mounted && sequence == _sequence) {
        if (date != _date) {
          unawaited(_reload());
          return;
        }
        setState(() => _result = result);
        widget.onResult?.call(result);
        final now = widget.service.now;
        var next = DateTime(now.year, now.month, now.day + 1);
        for (final entry in result.entries) {
          final end = DateTime.fromMillisecondsSinceEpoch(entry.block.endTime);
          if (end.isAfter(now) && end.isBefore(next)) next = end;
        }
        if (_foreground) {
          _wake = Timer(next.difference(now), () => unawaited(_reload()));
        }
      }
    } catch (error) {
      if (mounted && sequence == _sequence) {
        setState(
          () => _error = error is PlanAvailabilityException
              ? error
              : const PlanAvailabilityException('安排读取失败，请重试'),
        );
      }
    } finally {
      if (mounted && sequence == _sequence) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    ++_sequence;
    _wake?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    StorageService.scopedDataRefreshNotifier.removeListener(_onRefresh);
    DeviceCalendarReadService.revision.removeListener(_reload);
    super.dispose();
  }

  Widget _entry(PlanConflictEntry entry) {
    final block = entry.block;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ExpansionTile(
            key: ValueKey('plan-conflict-${block.id}'),
            title: Text(
              entry.todo?.title ?? block.titleSnapshot ?? '未命名规划',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${_time(DateTime.fromMillisecondsSinceEpoch(block.startTime))}–${_time(DateTime.fromMillisecondsSinceEpoch(block.endTime))}',
                ),
                Text('${entry.overlaps.length}项时间重叠'),
              ],
            ),
            childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            children: [
              Text(entry.todo?.title ?? block.titleSnapshot ?? '未命名规划'),
              for (var i = 0; i < entry.overlaps.length; i++)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        '${_sourceName(entry.overlaps[i].source.source)} · ${entry.overlaps[i].source.title ?? '安排'}',
                      ),
                      Text(
                        '重叠 ${_time(entry.overlaps[i].start)}–${_time(entry.overlaps[i].end)}',
                      ),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton(
                          key: ValueKey('plan-conflict-source-${block.id}-$i'),
                          onPressed: () => Navigator.pop(
                            context,
                            _ReviewAction(
                              _ActionKind.source,
                              entry,
                              entry.overlaps[i].source,
                            ),
                          ),
                          child: Text(
                            '查看${_sourceName(entry.overlaps[i].source.source)}',
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Wrap(
              spacing: 8,
              children: [
                if (entry.canAdjust)
                  TextButton.icon(
                    key: ValueKey('plan-conflict-adjust-${block.id}'),
                    onPressed: () => Navigator.pop(
                      context,
                      _ReviewAction(_ActionKind.adjust, entry),
                    ),
                    icon: const Icon(Icons.event_repeat, size: 18),
                    label: const Text('调整安排'),
                  )
                else if (block.status == TodoPlanStatus.focusing)
                  TextButton(
                    key: ValueKey('plan-conflict-focus-${block.id}'),
                    onPressed: () => Navigator.pop(
                      context,
                      _ReviewAction(_ActionKind.focus, entry),
                    ),
                    child: const Text('查看当前专注'),
                  )
                else
                  const Text('关联待办失效，暂不能改期'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final colors = Theme.of(context).colorScheme;
    final result = _result;
    final rows = <Object>[];
    DateTime? group;
    for (final entry in result?.entries ?? const <PlanConflictEntry>[]) {
      var date = _day(
        DateTime.fromMillisecondsSinceEpoch(entry.block.startTime),
      );
      if (result != null && date.isBefore(result.start)) date = result.start;
      if (date != group) {
        rows.add(date);
        group = date;
      }
      rows.add(entry);
    }
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 680,
            maxHeight:
                (media.size.height -
                        media.viewInsets.bottom -
                        media.padding.vertical -
                        24)
                    .clamp(0.0, double.infinity),
          ),
          child: OptionalLiquidGlassSheet(
            topRadius: 28,
            fallbackDecoration: BoxDecoration(
              color: colors.surface,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(28),
              ),
            ),
            child: Material(
              color: Colors.transparent,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 8, 0),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            '规划时间重叠',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                        ),
                        IconButton(
                          tooltip: '关闭冲突列表',
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                  ),
                  Flexible(
                    child: ListView.builder(
                      shrinkWrap: true,
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                      itemCount: rows.length + 1,
                      itemBuilder: (context, index) {
                        if (index > 0) {
                          final row = rows[index - 1];
                          return row is DateTime
                              ? Padding(
                                  padding: const EdgeInsets.only(top: 12),
                                  child: Text(
                                    DateFormat('M月d日').format(row),
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleSmall,
                                  ),
                                )
                              : _entry(row as PlanConflictEntry);
                        }
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Wrap(
                              spacing: 8,
                              children: [
                                if (_day(widget.date) != _today)
                                  ChoiceChip(
                                    key: const ValueKey(
                                      'plan-conflict-range-selected',
                                    ),
                                    label: Text(
                                      DateFormat('M月d日').format(widget.date),
                                    ),
                                    selected: _range == 0,
                                    onSelected: (_) {
                                      _range = 0;
                                      unawaited(_reload());
                                    },
                                  ),
                                ChoiceChip(
                                  key: const ValueKey(
                                    'plan-conflict-range-today',
                                  ),
                                  label: const Text('今天'),
                                  selected: _range != 2 && _date == _today,
                                  onSelected: (_) {
                                    _range = 1;
                                    unawaited(_reload());
                                  },
                                ),
                                ChoiceChip(
                                  key: const ValueKey(
                                    'plan-conflict-range-week',
                                  ),
                                  label: const Text('未来7天'),
                                  selected: _range == 2,
                                  onSelected: (_) {
                                    _range = 2;
                                    unawaited(_reload());
                                  },
                                ),
                              ],
                            ),
                            if (_loading)
                              const Padding(
                                padding: EdgeInsets.all(16),
                                child: LinearProgressIndicator(),
                              ),
                            if (_error != null) ...[
                              Text(
                                '冲突检查未完成',
                                style: TextStyle(color: colors.error),
                              ),
                              Text(_error!.message),
                              TextButton(
                                onPressed: _reload,
                                child: const Text('重试'),
                              ),
                              if (_error!.canUseAppOnly)
                                TextButton(
                                  key: const ValueKey('plan-conflict-app-only'),
                                  onPressed: () {
                                    _appOnly = true;
                                    unawaited(_reload());
                                  },
                                  child: const Text('仅按应用内安排检查'),
                                ),
                            ],
                            if (result != null) ...[
                              Text(
                                '${DateFormat('M月d日').format(result.start)}–${DateFormat('M月d日').format(result.end.subtract(const Duration(days: 1)))} · ${result.entries.length}条规划时间重叠',
                              ),
                              const SizedBox(height: 8),
                              Text(
                                result.coverage,
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                              if (result.appOnly)
                                const Text('仅按应用内安排检查；未计入手机日历'),
                              if (!result.complete)
                                ExpansionTile(
                                  title: const Text('冲突检查未完成：部分安排时间待定'),
                                  children: [
                                    for (final text in result.unknownTimes)
                                      Text(text),
                                  ],
                                ),
                              if (result.entries.isEmpty)
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 20,
                                  ),
                                  child: Text(
                                    result.complete
                                        ? '已检查范围内没有发现重叠'
                                        : '已知时段未发现重叠，时间待定事项仍需确认',
                                  ),
                                ),
                            ],
                          ],
                        );
                      },
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
}

/// Viewing a source must not invoke the day screen's automatic missed-plan
/// maintenance, or expose a second unvalidated editing path.
class PlanConflictPlanDetailScreen extends StatelessWidget {
  const PlanConflictPlanDetailScreen({super.key, required this.block});
  final TodoPlanBlock block;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = switch (block.status) {
      TodoPlanStatus.planned => '待执行',
      TodoPlanStatus.reminded => '已提醒',
      TodoPlanStatus.delayed => '已延后',
      TodoPlanStatus.focusing => '专注中',
      TodoPlanStatus.finished => '已完成',
      TodoPlanStatus.missed => '已漏做',
      TodoPlanStatus.skipped => '已跳过',
      TodoPlanStatus.cancelled => '已取消',
    };
    return Scaffold(
      appBar: AppBar(title: const Text('规划详情')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                block.titleSnapshot ?? '未命名规划',
                style: theme.textTheme.headlineSmall,
              ),
              const SizedBox(height: 16),
              Text(
                '${_time(DateTime.fromMillisecondsSinceEpoch(block.startTime))}–${_time(DateTime.fromMillisecondsSinceEpoch(block.endTime))}',
              ),
              const SizedBox(height: 12),
              Text('状态 · $status'),
              Text(
                '计划 ${block.plannedMinutes} 分钟 · 实际专注 ${block.actualFocusSeconds ~/ 60} 分钟',
              ),
              const Divider(height: 32),
              Text('备注', style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              Text(block.remark?.isNotEmpty == true ? block.remark! : '未填写'),
            ],
          ),
        ),
      ),
    );
  }
}
