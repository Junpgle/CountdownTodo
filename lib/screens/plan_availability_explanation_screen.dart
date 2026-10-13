import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/plan_availability.dart';
import '../models/plan_weekly_availability.dart';
import '../services/device_calendar_read_service.dart';
import '../services/plan_availability_preferences.dart';
import '../services/plan_availability_repository.dart';
import '../services/plan_availability_service.dart';
import '../services/plan_continuous_range_service.dart';
import '../services/plan_todo_guard.dart';
import '../services/plan_weekly_availability_preferences.dart';
import '../storage_service.dart';

enum PlanExplanationAction { modify, split }

class PlanExplanationResult {
  const PlanExplanationResult.selection(this.selection) : action = null;
  const PlanExplanationResult.action(this.action) : selection = null;
  final PlanAvailabilitySelection? selection;
  final PlanExplanationAction? action;
}

class PlanAvailabilityExplanationScreen extends StatefulWidget {
  const PlanAvailabilityExplanationScreen({
    super.key,
    required this.query,
    required this.snapshot,
    this.loader,
    this.rangeLoader,
    this.clock,
    this.canSplit = false,
  });
  final PlanAvailabilityQuery query;
  final PlanAvailabilitySnapshot snapshot;
  final PlanAvailabilityLoader? loader;
  final PlanContinuousRangeLoader? rangeLoader;
  final DateTime Function()? clock;
  final bool canSplit;
  @override
  State<PlanAvailabilityExplanationScreen> createState() =>
      _PlanAvailabilityExplanationScreenState();
}

class _PlanAvailabilityExplanationScreenState
    extends State<PlanAvailabilityExplanationScreen>
    with WidgetsBindingObserver {
  late PlanAvailabilitySnapshot _snapshot;
  late final Future<PlanTodoIdentity?> _openedIdentity;
  Object? _identityError;
  PlanContinuousRangeResult? _range;
  final _rangeKey = GlobalKey(), _errorKey = GlobalKey();
  bool _busy = false, _stale = false;
  int _sequence = 0;
  String? _error;
  DateTime get _now => widget.clock?.call() ?? DateTime.now();
  PlanAvailabilityQuery get _query => widget.query;
  @override
  void initState() {
    super.initState();
    _snapshot = widget.snapshot;
    _openedIdentity = PlanTodoIdentity.capture(_query.username)
        .then<PlanTodoIdentity?>(
          (identity) => identity,
          onError: (Object e) {
            _identityError = e;
            return null;
          },
        );
    WidgetsBinding.instance.addObserver(this);
    PlanWeeklyAvailabilityPreferences.revision.addListener(_invalidate);
    DeviceCalendarReadService.revision.addListener(_invalidate);
    StorageService.scopedDataRefreshNotifier.addListener(_onRefresh);
  }

  void _onRefresh() {
    final signal = StorageService.scopedDataRefreshNotifier.value;
    if ([
      DataRefreshDomain.todos,
      DataRefreshDomain.courses,
      DataRefreshDomain.fixedSchedules,
      DataRefreshDomain.planBlocks,
    ].any(signal.affects)) {
      _invalidate();
    }
  }

  void _invalidate() {
    if (!mounted) return;
    ++_sequence;
    setState(() {
      _stale = true;
      _busy = false;
      _range = null;
      _error = '安排或条件可能已变化，请刷新检查；修改规则请返回查找条件';
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _invalidate();
  }

  @override
  void dispose() {
    ++_sequence;
    WidgetsBinding.instance.removeObserver(this);
    PlanWeeklyAvailabilityPreferences.revision.removeListener(_invalidate);
    DeviceCalendarReadService.revision.removeListener(_invalidate);
    StorageService.scopedDataRefreshNotifier.removeListener(_onRefresh);
    super.dispose();
  }

  Future<PlanTodoIdentity> _identity() async {
    final identity = await _openedIdentity;
    if (identity == null) {
      throw _identityError ?? const PlanAvailabilityException('身份无法读取，请重新打开');
    }
    await identity.check();
    return identity;
  }

  Future<PlanAvailabilitySnapshot> _read(
    PlanAvailabilityQuery q, {
    bool requireCalendar = false,
  }) async {
    final s =
        await (widget.loader?.call(q, forceRefresh: true) ??
            PlanAvailabilityRepository(clock: widget.clock)
                .read(q, forceRefresh: true, requireCalendar: requireCalendar));
    if (requireCalendar && !s.deviceCalendarIncluded) {
      throw const PlanAvailabilityException('手机日历读取范围已变化，请重新查找');
    }
    return s;
  }

  void _reveal(GlobalKey key, int sequence) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final target = key.currentContext;
      if (mounted && sequence == _sequence && target != null) {
        Scrollable.ensureVisible(
          target,
          duration: const Duration(milliseconds: 260),
        );
      }
    });
  }

  Future<void> _search({bool following = false}) async {
    if (_busy) return;
    final sequence = ++_sequence;
    setState(() {
      _busy = true;
      _error = null;
      _range = null;
    });
    try {
      final identity = await _identity();
      await PlanAvailabilityPreferences.validateQueryDefaults(_query);
      var current = _snapshot;
      PlanContinuousRangeResult? result;
      if (following) {
        result =
            await (widget.rangeLoader?.call(_query, forceRefresh: true) ??
                PlanAvailabilityRepository(clock: widget.clock)
                    .readFollowingDays(_query));
        current =
            result.currentSnapshot ??
            (!result.end.isAfter(result.start)
                ? await _read(
                    _query,
                    requireCalendar: _snapshot.deviceCalendarIncluded,
                  )
                : current);
      } else {
        current = await _read(
          _query,
          requireCalendar: _snapshot.deviceCalendarIncluded,
        );
      }
      if (_snapshot.deviceCalendarIncluded &&
          (!current.deviceCalendarIncluded ||
              result?.selections.any(
                    (s) => !s.snapshot.deviceCalendarIncluded,
                  ) ==
                  true)) {
        throw const PlanAvailabilityException('手机日历读取范围已变化，请返回条件明确选择应用内模式');
      }
      final invalid = PlanAvailabilityService.invalidReason(
        _query,
        current.todo,
        _now,
      );
      if (invalid != null) throw PlanAvailabilityException(invalid);
      if (!mounted || sequence != _sequence) return;
      await identity.check();
      await PlanAvailabilityPreferences.validateQueryDefaults(_query);
      if (!mounted || sequence != _sequence) return;
      setState(() {
        _snapshot = current;
        _range = result;
        _stale = false;
      });
      if (result != null) _reveal(_rangeKey, sequence);
    } catch (e) {
      if (mounted && sequence == _sequence) {
        setState(() {
          _stale = true;
          _error = e is PlanAvailabilityException ? e.message : '安排读取失败，请重试';
        });
        _reveal(_errorKey, sequence);
      }
    } finally {
      if (mounted && sequence == _sequence) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _adopt(PlanAvailabilitySelection selected) async {
    if (_busy || _stale) return;
    final sequence = ++_sequence;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final identity = await _identity();
      await PlanAvailabilityPreferences.validateQueryDefaults(selected.query);
      final verified = widget.loader == null
          ? await PlanAvailabilityRepository(clock: widget.clock)
                .revalidateContinuous(selected)
          : null;
      final fresh =
          verified?.snapshot ??
          await _read(
            selected.query,
            requireCalendar: selected.snapshot.deviceCalendarIncluded,
          );
      if (fresh.todo.hasConflict ||
          !PlanAvailabilityService.accepts(selected, fresh, now: _now)) {
        throw const PlanAvailabilityException('该时段已变化，请重新查找后采用');
      }
      await PlanAvailabilityPreferences.validateQueryDefaults(selected.query);
      await identity.check();
      if (mounted && sequence == _sequence) {
        Navigator.pop(
          context,
          PlanExplanationResult.selection(
            PlanAvailabilitySelection(selected.query, selected.slot, fresh),
          ),
        );
      }
    } catch (e) {
      if (mounted && sequence == _sequence) {
        setState(() {
          _stale = true;
          _range = null;
          _error = e is PlanAvailabilityException ? e.message : '时段复核失败，请重试';
        });
        _reveal(_errorKey, sequence);
      }
    } finally {
      if (mounted && sequence == _sequence) {
        setState(() => _busy = false);
      }
    }
  }

  String _date(DateTime d) => DateFormat('MM月dd日').format(d);
  String _time(DateTime d) => DateFormat('HH:mm').format(d);
  String _minute(int m) =>
      '${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';
  @override
  Widget build(BuildContext context) {
    final diagnostic = PlanAvailabilityService.diagnose(
      _query,
      _snapshot,
      now: _now,
    );
    final due = PlanAvailabilityService.deadline(_snapshot.todo);
    final next = DateTime(
      _query.date.year,
      _query.date.month,
      _query.date.day + 1,
    );
    final canFollow = diagnostic.valid && (due == null || due.isAfter(next));
    final fragments = diagnostic.fragments.where((s) => s.minutes > 0).toList()
      ..sort((a, b) {
        final c = b.minutes.compareTo(a.minutes);
        return c != 0 ? c : a.start.compareTo(b.start);
      });
    final colors = Theme.of(context).colorScheme;
    final range = _range;
    return Scaffold(
      appBar: AppBar(
        title: const Text('查找说明'),
        actions: [
          IconButton(
            key: const ValueKey('plan-explanation-refresh'),
            tooltip: '刷新检查',
            onPressed: _busy ? null : () => _search(following: range != null),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '${_date(_query.date)} · 需要连续${_query.minutes}分钟',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  '${_minute(_query.windowStart)}–${_minute(_query.windowEnd)} · ${_query.bufferSummary}',
                ),
                Text(
                  _query.weekly?.ignored == true
                      ? '本次不使用每周规则'
                      : _query.weekly?.active == true
                      ? '沿用每周可安排时间'
                      : '每周规则未开启',
                ),
                Text(
                  _query.avoidWindows.isEmpty
                      ? '未选择避让时段'
                      : '避让：${_query.avoidWindows.map((w) => w.label).join('、')}',
                ),
                const SizedBox(height: 8),
                Text(_snapshot.coverage),
                if (_snapshot.unknownTimes.isNotEmpty)
                  Text(
                    '另有${_snapshot.unknownTimes.length}项安排时间未确定；不编造占用区间',
                    style: TextStyle(color: colors.error),
                  ),
                if (_busy) const LinearProgressIndicator(),
                if (_error != null)
                  Padding(
                    key: _errorKey,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      _error!,
                      key: const ValueKey('plan-explanation-error'),
                      style: TextStyle(color: colors.error),
                    ),
                  ),
                if (!_stale) ...[
                  const SizedBox(height: 16),
                  Text(diagnostic.message ?? '当前条件已找到完整连续时段'),
                  if (diagnostic.valid)
                    Text(
                      diagnostic.summary,
                      key: const ValueKey('plan-fragment-summary'),
                    ),
                  for (final s in fragments.take(3))
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.timelapse),
                      title: Text(
                        '${_time(s.start)}–${_time(s.end)} · ${s.minutes}分钟',
                      ),
                      subtitle: Text(
                        s.minutes < _query.minutes
                            ? '不足${_query.minutes}分钟，仅供参考'
                            : '片段参考，请通过查找结果采用',
                      ),
                    ),
                  ExpansionTile(
                    title: const Text('查看计算明细'),
                    tilePadding: EdgeInsets.zero,
                    children: [
                      const Text('按以下顺序计算剩余时间；重叠只扣一次，不代表各项是唯一原因。'),
                      for (final stage in diagnostic.stages)
                        ListTile(
                          title: Text(stage.label),
                          trailing: Text('${stage.minutes}分钟'),
                        ),
                      Text('已计入${_snapshot.busy.length}项占用（含重叠项，不按项数累加分钟）'),
                      for (final b in _snapshot.busy.take(50))
                        Text(
                          '${_date(b.start)} ${_time(b.start)}–${_time(b.end)} · ${switch (b.source) {
                            PlanBusySource.course => '课程',
                            PlanBusySource.fixedSchedule => '固定日程',
                            PlanBusySource.planBlock => '规划',
                            PlanBusySource.legacyTodo => '旧执行区间',
                            PlanBusySource.deviceCalendar => '手机日历',
                          }}',
                        ),
                      if (_snapshot.busy.length > 50) const Text('其余占用均已计入计算'),
                      for (final unknown in _snapshot.unknownTimes)
                        Text(unknown),
                    ],
                  ),
                ],
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton(
                      key: const ValueKey('plan-explanation-modify'),
                      onPressed: _busy
                          ? null
                          : () => Navigator.pop(
                              context,
                              const PlanExplanationResult.action(
                                PlanExplanationAction.modify,
                              ),
                            ),
                      child: const Text('修改查找条件'),
                    ),
                    if (canFollow)
                      FilledButton(
                        key: const ValueKey('plan-following-days'),
                        onPressed: _busy
                            ? null
                            : () => _search(following: true),
                        child: const Text('查找后续7天'),
                      )
                    else
                      const Text('截止前已无后续日期，或需先修正查找条件'),
                    if (widget.canSplit &&
                        diagnostic.valid &&
                        diagnostic.reason != PlanAvailabilityReason.deadline &&
                        _query.minutes >= 30 &&
                        _query.minutes <= 720)
                      TextButton(
                        key: const ValueKey('plan-explanation-split'),
                        onPressed: _busy || _stale
                            ? null
                            : () => Navigator.pop(
                                context,
                                const PlanExplanationResult.action(
                                  PlanExplanationAction.split,
                                ),
                              ),
                        child: const Text('分段安排'),
                      ),
                  ],
                ),
                if (range != null) ...[
                  const SizedBox(height: 20),
                  Text(
                    range.end.isAfter(range.start)
                        ? '后续日期 · ${_date(range.start)}—${_date(DateTime(range.end.year, range.end.month, range.end.day - 1))}'
                        : '截止前已无后续日期',
                    key: _rangeKey,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  Text(
                    '找到${range.selections.length}个候选 · 每次${_query.minutes}分钟 · 择一采用',
                  ),
                  Text(range.coverage),
                  for (final unknown in range.unknownTimes) Text(unknown),
                  if (range.selections.isEmpty &&
                      range.end.isAfter(range.start))
                    const Text('上述完整范围内未找到符合当前条件的连续时段'),
                  for (final selected in range.selections)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              '${_date(selected.slot.start)} ${PlanWeeklyRules.weekdays[selected.slot.start.weekday - 1]}',
                            ),
                            Text(
                              '${_time(selected.slot.start)}–${_time(selected.slot.end)} · ${selected.slot.minutes}分钟',
                            ),
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton(
                                key: ValueKey(
                                  'plan-following-adopt-${selected.slot.start.millisecondsSinceEpoch}',
                                ),
                                onPressed: _busy || _stale
                                    ? null
                                    : () => _adopt(selected),
                                child: const Text('采用'),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
