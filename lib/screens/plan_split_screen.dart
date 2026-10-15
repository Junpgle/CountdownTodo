import '../models/plan_weekly_availability.dart';
import '../services/plan_weekly_availability_preferences.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models.dart';
import '../storage_service.dart';
import '../services/device_calendar_read_service.dart';
import '../services/plan_todo_guard.dart';
import '../models/plan_availability.dart';
import '../models/plan_split.dart';
import '../services/plan_availability_preferences.dart';
import '../services/plan_availability_repository.dart';
import '../services/plan_split_service.dart';
import '../widgets/plan_availability_panel.dart';

/// Restoring a draft never restores permission to relax calendar/avoidance checks.
Future<PlanSplitQuery> splitWithCurrentDefaults(
  PlanSplitQuery query, {
  bool refreshDefaults = false,
  bool useWeekly = true,
}) async {
  final b = query.base;
  final prefs = await PlanAvailabilityPreferences.load(b.username);
  if (prefs.bufferError != null) {
    throw PlanAvailabilityException(prefs.bufferError!);
  }
  final weekly = useWeekly ? await PlanWeeklyAvailabilityPreferences.load(b.username) : null;
  if(weekly?.error != null && !(b.weekly?.ignored ?? false)) {
    throw PlanAvailabilityException(weekly!.error!);
  }
  return query.configure(
    base: PlanAvailabilityQuery(
      weekly: useWeekly ? PlanWeeklyContext(weekly?.rules,ignored:b.weekly?.ignored ?? false) : null,
      username: b.username,
      todoId: b.todoId,
      date: b.date,
      minutes: b.minutes,
      windowStart: b.windowStart,
      windowEnd: b.windowEnd,
      appOnly: b.appOnly,
      avoidWindows:
          (!refreshDefaults && b.avoidanceDefaultsKey != null) ||
              b.avoidanceOverride
          ? b.avoidWindows
          : [for (final i in prefs.selectedIndices) prefs.options[i]],
      bufferBefore:
          (!refreshDefaults && b.bufferDefaultsKey != null) || b.bufferOverride
          ? b.bufferBefore
          : prefs.bufferBefore,
      bufferAfter:
          (!refreshDefaults && b.bufferDefaultsKey != null) || b.bufferOverride
          ? b.bufferAfter
          : prefs.bufferAfter,
      bufferOverride: b.bufferOverride,
      bufferDefaultsKey: refreshDefaults && !b.bufferOverride
          ? prefs.bufferKey
          : b.bufferDefaultsKey ?? prefs.bufferKey,
      avoidanceOverride: b.avoidanceOverride,
      avoidanceDefaultsKey: refreshDefaults && !b.avoidanceOverride
          ? prefs.avoidanceKey
          : b.avoidanceDefaultsKey ?? prefs.avoidanceKey,
    ),
  );
}

String splitTimeLabel(PlanTimeSlot s) {
  String offset(DateTime t) {
    final m = t.timeZoneOffset.inMinutes;
    return "UTC${m < 0 ? '-' : '+'}${(m.abs() ~/ 60).toString().padLeft(2, '0')}:${(m.abs() % 60).toString().padLeft(2, '0')}";
  }

  final endFormat = s.start.day == s.end.day ? 'HH:mm' : 'M/d HH:mm';
  final zones = s.start.timeZoneOffset == s.end.timeZoneOffset
      ? offset(s.start)
      : '${offset(s.start)} → ${offset(s.end)}';
  return '${DateFormat('M/d HH:mm').format(s.start)}–${DateFormat(endFormat).format(s.end)} · ${s.minutes}分钟 ($zones)';
}

class PlanSplitScreen extends StatefulWidget {
  const PlanSplitScreen({
    super.key,
    required this.todo,
    required this.initialQuery,
    this.repository,
    this.clock,
    this.requireDurationConfirmation = false,
  });
  final bool requireDurationConfirmation;
  final TodoItem todo;
  final PlanSplitQuery initialQuery;
  final PlanAvailabilityRepository? repository;
  final DateTime Function()? clock;
  @override
  State<PlanSplitScreen> createState() => _PlanSplitScreenState();
}

class _PlanSplitScreenState extends State<PlanSplitScreen>
    with WidgetsBindingObserver {
  late PlanSplitQuery _query;
  late Future<PlanTodoIdentity> _identity;
  PlanSplitSnapshot? _snapshot;
  PlanSplitResult? _result;
  Object? _error;
  bool _loading = false;
  int _sequence = 0;
  bool _durationConfirmed = false;
  DateTime get _now => widget.clock?.call() ?? DateTime.now();
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    StorageService.scopedDataRefreshNotifier.addListener(_invalidate);
    DeviceCalendarReadService.revision.addListener(_invalidate);
    PlanWeeklyAvailabilityPreferences.revision.addListener(_invalidate);
    _identity = PlanTodoIdentity.capture(widget.initialQuery.base.username);
    _identity.then<void>(
      (_) {},
      onError: (Object e, StackTrace trace) {
        if (mounted) setState(() => _error = e);
      },
    );
    _query = widget.initialQuery;
    if (widget.requireDurationConfirmation) {
      _error = const PlanAvailabilityException('未取得估时，请在修改条件中确认本次总时长');
    } else {
      _search();
    }
  }

  @override
  void dispose() {
    ++_sequence;
    WidgetsBinding.instance.removeObserver(this);
    StorageService.scopedDataRefreshNotifier.removeListener(_invalidate);
    DeviceCalendarReadService.revision.removeListener(_invalidate);
    PlanWeeklyAvailabilityPreferences.revision.removeListener(_invalidate);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _invalidate();
  }

  void _invalidate() {
    if (!mounted) return;
    ++_sequence;
    setState(() {
      _result = null;
      _loading = false;
      _error = const PlanAvailabilityException('安排或状态已变化，请重新查找');
    });
  }

  Future<void> _search() async {
    if (widget.requireDurationConfirmation && !_durationConfirmed) return;
    final sequence = ++_sequence;
    setState(() {
      _loading = true;
      _result = null;
      _error = null;
    });
    try {
      await (await _identity).check();
      final q = await splitWithCurrentDefaults(_query, refreshDefaults: true);
      final snapshot =
          await (widget.repository ??
                  PlanAvailabilityRepository(clock: widget.clock))
              .readSplit(q, forceRefresh: true);
      final result = PlanSplitService.find(q, snapshot, now: _now);
      if (mounted && sequence == _sequence) {
        setState(() {
          _query = q;
          _snapshot = snapshot;
          _result = result;
        });
      }
    } catch (e) {
      if (mounted && sequence == _sequence) setState(() => _error = e);
    } finally {
      if (mounted && sequence == _sequence) setState(() => _loading = false);
    }
  }

  Future<void> _adopt(int index) async {
    try {
      await (await _identity).check();
      if (!mounted || _result == null || _snapshot == null) return;
      final slots = _result!.groups[index];
      if (!PlanSplitService.accepts(_query, slots, _snapshot!, now: _now)) {
        throw const PlanAvailabilityException('时段已过期，请重新查找');
      }
      Navigator.pop(context, PlanSplitSelection(_query, slots, _snapshot!));
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _criteria() async {
    var base = _query.base, days = _query.days, maximum = _query.maximum;
    String? error;
    final maximumText = TextEditingController(text: '$maximum');
    ModalRoute<dynamic>? route;
    final updated = await showDialog<PlanSplitQuery>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, update) {
          route = ModalRoute.of(c);
          return AlertDialog(
            title: const Text('分段条件'),
            content: SizedBox(
              width: 540,
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text('日期范围'),
                    Wrap(
                      spacing: 8,
                      children: [
                        for (final n in {1, 3, 7, days})
                          ChoiceChip(
                            label: Text('$n天'),
                            selected: days == n,
                            onSelected: (_) => update(() => days = n),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    const Text('单段上限（15–120分钟）'),
                    Wrap(
                      spacing: 6,
                      children: [
                        for (final n in [25, 30, 45, 60, 90, 120])
                          ChoiceChip(
                            label: Text('$n'),
                            selected: maximum == n,
                            onSelected: (_) => update(() {
                              maximum = n;
                              maximumText.text = '$n';
                            }),
                          ),
                      ],
                    ),
                    TextField(
                      key: const ValueKey('split-maximum'),
                      controller: maximumText,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: '自定义单段上限'),
                      onChanged: (v) => maximum = int.tryParse(v) ?? 0,
                    ),
                    const SizedBox(height: 12),
                    PlanAvailabilityPanel(
                      configurationOnly: true,
                      username: base.username,
                      todo: widget.todo,
                      initialDate: base.date,
                      initialMinutes: base.minutes,
                      initialQuery: base,
                      clock: widget.clock,
                      onSelected: (_) {},
                      onInvalidated: () {},
                      onQueryChanged: (q) => base = q,
                    ),
                    if (error != null)
                      Text(
                        error!,
                        style: TextStyle(color: Theme.of(c).colorScheme.error),
                      ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(c),
                child: const Text('取消'),
              ),
              FilledButton(
                key: const ValueKey('split-search'),
                onPressed: () {
                  final q = PlanSplitQuery(base, days: days, maximum: maximum);
                  if (q.invalidReason != null) {
                    update(() => error = q.invalidReason);
                    return;
                  }
                  Navigator.pop(c, q);
                },
                child: const Text('查找完整方案'),
              ),
            ],
          );
        },
      ),
    );
    await route?.completed;
    // The dialog's text fields are gone before their controller is disposed.
    // Route completion may outlive the returned future during a reverse animation.
    if (mounted && updated != null) {
      _durationConfirmed = true;
      _query = updated;
      await _search();
    }
    // Keep controller until reverse transition has completed.
    maximumText.dispose();
  }

  void _withoutBuffers() {
    final b = _query.base;
    _query = _query.configure(
      base: PlanAvailabilityQuery(
        username: b.username,
        todoId: b.todoId,
        date: b.date,
        minutes: b.minutes,
        windowStart: b.windowStart,
        windowEnd: b.windowEnd,
        appOnly: b.appOnly,
        avoidWindows: b.avoidWindows,
        bufferOverride: true,
        avoidanceOverride: b.avoidanceOverride,
        avoidanceDefaultsKey: b.avoidanceDefaultsKey,
        weekly: b.weekly,
      ),
    );
    _search();
  }

  void _appOnly() {
    final b = _query.base;
    _query = _query.configure(
      base: PlanAvailabilityQuery(
        username: b.username,
        todoId: b.todoId,
        date: b.date,
        minutes: b.minutes,
        windowStart: b.windowStart,
        windowEnd: b.windowEnd,
        appOnly: true,
        avoidWindows: b.avoidWindows,
        bufferBefore: b.bufferBefore,
        bufferAfter: b.bufferAfter,
        bufferOverride: b.bufferOverride,
        bufferDefaultsKey: b.bufferDefaultsKey,
        avoidanceOverride: b.avoidanceOverride,
        avoidanceDefaultsKey: b.avoidanceDefaultsKey,
        weekly: b.weekly,
      ),
    );
    _search();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme, q = _query;
    return Scaffold(
      appBar: AppBar(title: const Text('分段安排')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                widget.todo.title,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text('共${q.total}分钟 · 每段15–${q.maximum}分钟 · 最多6段'),
                      Text(
                        '从${DateFormat('M月d日').format(q.base.date)}起${q.days}天 · 每天${q.base.windowStart ~/ 60}:${(q.base.windowStart % 60).toString().padLeft(2, '0')}–${q.base.windowEnd ~/ 60}:${(q.base.windowEnd % 60).toString().padLeft(2, '0')}',
                      ),
                      Text(
                        '${q.base.bufferSummary}；避让${q.base.avoidWindows.map((w) => w.label).join('、').isEmpty ? '无' : q.base.avoidWindows.map((w) => w.label).join('、')}',
                      ),
                      if(q.base.weekly?.active == true) const Text('按每周可安排时间推荐'),
                      if(q.base.weekly?.ignored == true) const Text('本次不使用每周规则'),
                      TextButton.icon(
                        key: const ValueKey('split-criteria'),
                        onPressed: _loading ? null : _criteria,
                        icon: const Icon(Icons.tune),
                        label: const Text('修改条件'),
                      ),
                    ],
                  ),
                ),
              ),
              if (_loading) const LinearProgressIndicator(),
              if (_error != null) ...[
                Text(
                  _error is PlanAvailabilityException
                      ? (_error as PlanAvailabilityException).message
                      : '读取失败，请重试',
                  style: TextStyle(color: colors.error),
                ),
                TextButton(
                  onPressed:
                      widget.requireDurationConfirmation && !_durationConfirmed
                      ? _criteria
                      : _search,
                  child: Text(
                    widget.requireDurationConfirmation && !_durationConfirmed
                        ? '确认本次时长'
                        : '重试',
                  ),
                ),
                if (_error is PlanAvailabilityException &&
                    (_error as PlanAvailabilityException).canUseAppOnly)
                  TextButton(
                    onPressed: _appOnly,
                    child: const Text('仅按应用内安排查找'),
                  ),
              ],
              if (_result?.message != null) Text(_result!.message!),
              if (_result != null &&
                  _result!.groups.isEmpty &&
                  _query.base.hasBuffers)
                TextButton(
                  onPressed: _withoutBuffers,
                  child: const Text('本次不留缓冲重试'),
                ),
              if (_result != null &&
                  (_result!.groups.isEmpty || _result!.incomplete))
                OutlinedButton.icon(
                  key: const ValueKey('split-return-single'),
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.arrow_back),
                  label: const Text('返回连续安排'),
                ),
              if (_result != null && !_result!.incomplete)
                for (var i = 0; i < _result!.groups.length; i++)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            '方案${i + 1} · ${_result!.groups[i].length}段 · 共${q.total}分钟',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          for (final s in _result!.groups[i])
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              child: Text(splitTimeLabel(s)),
                            ),
                          FilledButton(
                            key: ValueKey('split-adopt-$i'),
                            onPressed: () => _adopt(i),
                            child: const Text('采用整组'),
                          ),
                        ],
                      ),
                    ),
                  ),
              if (_snapshot != null)
                Text(
                  _snapshot!.coverage,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              const SizedBox(height: 12),
              const Text('保存前会重新检查全部时段；不会自动启动后续分段。'),
            ],
          ),
        ),
      ),
    );
  }
}
