import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/plan_availability.dart';
import '../models/plan_weekly_availability.dart';
import '../services/device_calendar_read_service.dart';
import '../services/plan_availability_preferences.dart';
import '../services/plan_availability_repository.dart';
import '../services/plan_availability_service.dart';
import '../services/plan_continuous_range_service.dart';
import '../services/conflict_visibility_service.dart';
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

class _PlanExplanationDerivedData {
  const _PlanExplanationDerivedData({
    required this.diagnostic,
    required this.fragments,
  });

  final PlanAvailabilityDiagnostics diagnostic;
  final List<PlanTimeSlot> fragments;
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
  String? _dateFormatLocale;
  DateFormat? _dateFormatter;
  DateFormat? _timeFormatter;
  PlanAvailabilityQuery? _derivedQuery;
  PlanAvailabilitySnapshot? _derivedSnapshot;
  DateTime? _derivedToday;
  DateTime? _derivedCurrentMinute;
  _PlanExplanationDerivedData? _cachedDerivedData;
  DateTime get _now => widget.clock?.call() ?? DateTime.now();
  PlanAvailabilityQuery get _query => widget.query;

  void _ensureDateFormatters() {
    final locale = Intl.defaultLocale;
    if (_dateFormatLocale == locale &&
        _dateFormatter != null &&
        _timeFormatter != null) {
      return;
    }
    _dateFormatLocale = locale;
    _dateFormatter = DateFormat('MM月dd日', locale);
    _timeFormatter = DateFormat('HH:mm', locale);
  }

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
      _cachedDerivedData = null;
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
      if (ConflictVisibilityService.blocksTodoPlanning(fresh.todo) ||
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

  String _date(DateTime d) {
    _ensureDateFormatters();
    return _dateFormatter!.format(d);
  }

  String _time(DateTime d) {
    _ensureDateFormatters();
    return _timeFormatter!.format(d);
  }

  _PlanExplanationDerivedData _derivedDataFor(DateTime now) {
    final query = _query;
    final snapshot = _snapshot;
    final today = DateTime(now.year, now.month, now.day);
    final currentMinute = PlanAvailabilityService.minuteCeiling(now);
    final cachedData = _cachedDerivedData;
    if (cachedData != null &&
        identical(_derivedQuery, query) &&
        identical(_derivedSnapshot, snapshot) &&
        _derivedToday == today &&
        _derivedCurrentMinute == currentMinute) {
      return cachedData;
    }

    final diagnostic = PlanAvailabilityService.diagnose(
      query,
      snapshot,
      now: now,
    );
    final fragments = diagnostic.fragments.where((s) => s.minutes > 0).toList()
      ..sort((a, b) {
        final comparison = b.minutes.compareTo(a.minutes);
        return comparison != 0 ? comparison : a.start.compareTo(b.start);
      });
    final derivedData = _PlanExplanationDerivedData(
      diagnostic: diagnostic,
      fragments: fragments,
    );
    _derivedQuery = query;
    _derivedSnapshot = snapshot;
    _derivedToday = today;
    _derivedCurrentMinute = currentMinute;
    _cachedDerivedData = derivedData;
    return derivedData;
  }

  String _minute(int m) =>
      '${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';
  @override
  Widget build(BuildContext context) {
    final derivedData = _derivedDataFor(_now);
    final diagnostic = derivedData.diagnostic;
    final due = PlanAvailabilityService.deadline(_snapshot.todo);
    final next = DateTime(
      _query.date.year,
      _query.date.month,
      _query.date.day + 1,
    );
    final canFollow = diagnostic.valid && (due == null || due.isAfter(next));
    final fragments = derivedData.fragments;
    final colors = Theme.of(context).colorScheme;
    final range = _range;
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: colors.surfaceContainerLowest,
      appBar: AppBar(
        title: const Text('查找说明'),
        centerTitle: false,
        backgroundColor: colors.surfaceContainerLowest,
        actions: [
          IconButton(
            key: const ValueKey('plan-explanation-refresh'),
            tooltip: '刷新检查',
            onPressed: _busy ? null : () => _search(following: range != null),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '${_date(_query.date)} · 需要连续${_query.minutes}分钟',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),
                if (_busy) const LinearProgressIndicator(),
                if (_error != null)
                  Container(
                    key: _errorKey,
                    margin: const EdgeInsets.only(bottom: 16),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: colors.errorContainer,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      _error!,
                      key: const ValueKey('plan-explanation-error'),
                      style: TextStyle(color: colors.onErrorContainer),
                    ),
                  ),
                if (!_stale) ...[
                  _surface(
                    tint: true,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          diagnostic.reason == PlanAvailabilityReason.available
                              ? Icons.event_available_outlined
                              : Icons.calendar_month_outlined,
                          color: colors.primary,
                          size: 28,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          switch (diagnostic.reason) {
                            PlanAvailabilityReason.fragmented => '当天空闲较零散',
                            PlanAvailabilityReason.noTime => '当天暂无可用时间',
                            _ => diagnostic.message ?? '当前条件已找到完整连续时段',
                          },
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (diagnostic.valid) ...[
                          const SizedBox(height: 8),
                          Text(
                            diagnostic.summary,
                            key: const ValueKey('plan-fragment-summary'),
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (fragments.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    _sectionTitle('当天空闲片段', '仅供参考，不会缩短规划时长'),
                    const SizedBox(height: 12),
                    for (final s in fragments.take(3))
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _surface(
                          padding: 14,
                          child: Row(
                            children: [
                              Container(
                                width: 3,
                                height: 42,
                                decoration: BoxDecoration(
                                  color: colors.outlineVariant,
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '${_time(s.start)}–${_time(s.end)} · ${s.minutes}分钟',
                                      style: theme.textTheme.titleMedium
                                          ?.copyWith(
                                            fontWeight: FontWeight.w600,
                                          ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      s.minutes < _query.minutes
                                          ? '不足${_query.minutes}分钟，仅供参考'
                                          : '片段参考，请通过查找结果采用',
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(
                                            color: colors.onSurfaceVariant,
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ],
                const SizedBox(height: 16),
                _surface(
                  padding: 0,
                  child: ExpansionTile(
                    title: const Text('查找条件与计算明细'),
                    subtitle: Text(
                      '${_minute(_query.windowStart)}–${_minute(_query.windowEnd)} · ${_query.minutes}分钟',
                    ),
                    leading: Icon(Icons.tune, color: colors.primary),
                    shape: const Border(),
                    collapsedShape: const Border(),
                    childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          _tag(_query.bufferSummary),
                          _tag(
                            _query.weekly?.ignored == true
                                ? '本次不使用每周规则'
                                : _query.weekly?.active == true
                                ? '沿用每周可安排时间'
                                : '每周规则未开启',
                          ),
                          _tag(
                            _query.avoidWindows.isEmpty
                                ? '未选择避让时段'
                                : '避让：${_query.avoidWindows.map((w) => w.label).join('、')}',
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        _snapshot.coverage,
                        style: theme.textTheme.bodySmall,
                      ),
                      if (_snapshot.unknownTimes.isNotEmpty)
                        Text(
                          '另有${_snapshot.unknownTimes.length}项安排时间未确定；不编造占用区间',
                          style: TextStyle(color: colors.error),
                        ),
                      if (!_stale) ...[
                        const Divider(height: 24),
                        const Text('按以下顺序计算剩余时间；重叠只扣一次，不代表各项是唯一原因。'),
                        for (final stage in diagnostic.stages)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Row(
                              children: [
                                Expanded(child: Text(stage.label)),
                                const SizedBox(width: 12),
                                Text(
                                  '${stage.minutes}分钟',
                                  style: theme.textTheme.labelLarge,
                                ),
                              ],
                            ),
                          ),
                        const Divider(),
                        Text('已计入${_snapshot.busy.length}项占用（含重叠项，不按项数累加分钟）'),
                        for (final b in _snapshot.busy.take(50))
                          Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(
                              '${_date(b.start)} ${_time(b.start)}–${_time(b.end)} · ${switch (b.source) {
                                PlanBusySource.course => '课程',
                                PlanBusySource.fixedSchedule => '固定日程',
                                PlanBusySource.planBlock => '规划',
                                PlanBusySource.legacyTodo => '旧执行区间',
                                PlanBusySource.deviceCalendar => '手机日历',
                                PlanBusySource.habit => '习惯预留',
                                PlanBusySource.challenge => '30天挑战',
                              }}',
                              style: theme.textTheme.bodySmall,
                            ),
                          ),
                        if (_snapshot.busy.length > 50)
                          const Text('其余占用均已计入计算'),
                        for (final unknown in _snapshot.unknownTimes)
                          Text(unknown),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  _snapshot.coverage,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 20),
                if (canFollow)
                  FilledButton.icon(
                    key: const ValueKey('plan-following-days'),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        vertical: 16,
                        horizontal: 20,
                      ),
                    ),
                    onPressed: _busy ? null : () => _search(following: true),
                    icon: const Icon(Icons.travel_explore_outlined, size: 20),
                    label: const Text('查找后续7天'),
                  )
                else
                  const Text('截止前已无后续日期，或需先修正查找条件'),
                const SizedBox(height: 8),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 12,
                  runSpacing: 4,
                  children: [
                    TextButton(
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
                  const SizedBox(height: 24),
                  Text(
                    range.end.isAfter(range.start)
                        ? '后续日期 · ${_date(range.start)}—${_date(DateTime(range.end.year, range.end.month, range.end.day - 1))}'
                        : '截止前已无后续日期',
                    key: _rangeKey,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '找到${range.selections.length}个候选 · 每次${_query.minutes}分钟 · 择一采用',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 16),
                  for (final selected in range.selections) _candidate(selected),
                  if (range.selections.isEmpty &&
                      range.end.isAfter(range.start))
                    _surface(child: const Text('上述完整范围内未找到符合当前条件的连续时段')),
                  const SizedBox(height: 8),
                  Text(
                    range.coverage,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                  for (final unknown in range.unknownTimes) Text(unknown),
                ],
                if (_snapshot.unknownTimes.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    '另有${_snapshot.unknownTimes.length}项安排时间未确定，请在采用前核对',
                    style: TextStyle(color: colors.error),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _surface({
    required Widget child,
    double padding = 20,
    bool tint = false,
  }) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: EdgeInsets.all(padding),
      decoration: BoxDecoration(
        color: tint
            ? colors.primaryContainer.withValues(alpha: 0.45)
            : colors.surface,
        border: Border.all(
          color: tint
              ? colors.primary.withValues(alpha: 0.15)
              : colors.outlineVariant.withValues(alpha: 0.6),
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: child,
    );
  }

  Widget _tag(String label) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(label, style: theme.textTheme.bodySmall),
    );
  }

  Widget _sectionTitle(String title, String subtitle) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        title,
        style: Theme.of(context).textTheme.titleSmall
            ?.copyWith(fontWeight: FontWeight.w700),
      ),
      const SizedBox(height: 4),
      Text(
        subtitle,
        style: Theme.of(context).textTheme.bodySmall
            ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
      ),
    ],
  );

  Widget _candidate(PlanAvailabilitySelection selected) {
    final theme = Theme.of(context), slot = selected.slot;
    final colors = theme.colorScheme;
    final button = FilledButton.tonal(
      key: ValueKey(
        'plan-following-adopt-${slot.start.millisecondsSinceEpoch}',
      ),
      onPressed: _busy || _stale ? null : () => _adopt(selected),
      child: const Text('采用'),
    );
    final time = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${_date(slot.start)} ${PlanWeeklyRules.weekdays[slot.start.weekday - 1]}',
          style: theme.textTheme.labelMedium?.copyWith(color: colors.primary),
        ),
        const SizedBox(height: 6),
        Text(
          '${_time(slot.start)}–${_time(slot.end)}',
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '连续${slot.minutes}分钟',
          style: theme.textTheme.bodySmall?.copyWith(
            color: colors.onSurfaceVariant,
          ),
        ),
      ],
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: _surface(
        padding: 16,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final stack =
                constraints.maxWidth < 250 ||
                MediaQuery.textScalerOf(context).scale(14) > 20;
            return stack
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      time,
                      const SizedBox(height: 12),
                      Align(alignment: Alignment.centerRight, child: button),
                    ],
                  )
                : Row(
                    children: [
                      Expanded(child: time),
                      const SizedBox(width: 12),
                      button,
                    ],
                  );
          },
        ),
      ),
    );
  }
}
