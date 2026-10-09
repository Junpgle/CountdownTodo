import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models.dart';
import '../models/plan_availability.dart';
import '../services/device_calendar_read_service.dart';
import '../services/plan_availability_preferences.dart';
import '../services/plan_availability_repository.dart';
import '../services/plan_availability_service.dart';
import '../storage_service.dart';
import '../utils/app_dialogs.dart';

class PlanAvailabilityPanel extends StatefulWidget {
  const PlanAvailabilityPanel({
    super.key,
    required this.username,
    required this.todo,
    required this.initialDate,
    required this.initialMinutes,
    required this.onSelected,
    required this.onInvalidated,
    this.editingBlock,
    this.loader,
    this.clock,
    this.estimatedMinutes,
    this.initialExpanded = false,
    this.dateShortcuts = false,
    this.onQueryChanged,
    this.onDateChanged,
  });
  final String username;
  final TodoItem? todo;
  final DateTime initialDate;
  final int initialMinutes;
  final TodoPlanBlock? editingBlock;
  final int? estimatedMinutes;
  final PlanAvailabilityLoader? loader;
  final DateTime Function()? clock;
  final ValueChanged<PlanAvailabilitySelection> onSelected;
  final VoidCallback onInvalidated;
  final bool initialExpanded;
  final bool dateShortcuts;
  final ValueChanged<PlanAvailabilityQuery>? onQueryChanged;
  final ValueChanged<DateTime>? onDateChanged;
  @override
  State<PlanAvailabilityPanel> createState() => _PlanAvailabilityPanelState();
}

class _PlanAvailabilityPanelState extends State<PlanAvailabilityPanel>
    with WidgetsBindingObserver {
  late DateTime _date;
  late int _minutes;
  late final TextEditingController _duration;
  int _start = 480, _end = 1320, _sequence = 0;
  bool _expanded = false, _loading = false, _appOnly = false;
  PlanAvailabilitySnapshot? _snapshot;
  PlanAvailabilityResult? _result;
  PlanAvailabilityException? _error;
  DateTime? _selectedStart;
  int _resultLimit = 5;
  final List<PlanDailyTimeWindow> _avoidOptions = List.of(
    PlanAvailabilityPreferences.defaultWindows,
  );
  final Set<PlanDailyTimeWindow> _enabledAvoid = {};
  int _avoidPreferencesSequence = 0;
  bool _avoidPreferencesLoaded = false;
  DateTime get _now => widget.clock?.call() ?? DateTime.now();
  PlanAvailabilityQuery get _query => PlanAvailabilityQuery(
    username: widget.username,
    todoId: widget.todo?.id ?? '',
    date: _date,
    minutes: _minutes,
    windowStart: _start,
    windowEnd: _end,
    excludeBlockId: widget.editingBlock?.id,
    appOnly: _appOnly,
    resultLimit: _resultLimit,
    avoidWindows: List.unmodifiable(_enabledAvoid),
  );

  @override
  void initState() {
    super.initState();
    _date = _day(widget.initialDate);
    _expanded = widget.initialExpanded;
    _minutes = widget.initialMinutes > 0 ? widget.initialMinutes : 30;
    _duration = TextEditingController(text: '$_minutes');
    unawaited(_loadAvoidPreferences());
    WidgetsBinding.instance.addObserver(this);
    StorageService.scopedDataRefreshNotifier.addListener(_onRefresh);
    DeviceCalendarReadService.revision.addListener(_invalidate);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onQueryChanged?.call(_query);
    });
  }

  DateTime _day(DateTime value) => DateTime(value.year, value.month, value.day);

  Future<void> _loadAvoidPreferences() async {
    final sequence = ++_avoidPreferencesSequence;
    final username = widget.username;
    _avoidPreferencesLoaded = false;
    _avoidOptions
      ..clear()
      ..addAll(PlanAvailabilityPreferences.defaultWindows);
    _enabledAvoid.clear();
    PlanAvoidancePreferences saved;
    try {
      saved = await PlanAvailabilityPreferences.load(username);
    } catch (error) {
      debugPrint('Unable to load availability preferences: $error');
      saved = PlanAvoidancePreferences(
        PlanAvailabilityPreferences.defaultWindows,
        const {},
      );
    }
    if (!mounted ||
        sequence != _avoidPreferencesSequence ||
        username != widget.username) {
      return;
    }
    _avoidOptions
      ..clear()
      ..addAll(saved.options);
    _enabledAvoid.addAll(saved.selectedIndices.map((i) => _avoidOptions[i]));
    _avoidPreferencesLoaded = true;
    _invalidate();
  }

  void _avoidChanged() {
    _invalidate();
    final username = widget.username;
    unawaited(
      PlanAvailabilityPreferences.save(
        username,
        _avoidOptions,
        _enabledAvoid,
      ).catchError((Object error) {
        debugPrint('Unable to save availability preferences: $error');
        if (!mounted || username != widget.username) return;
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('避让设置未能保存，请重试')));
      }),
    );
  }

  @override
  void didUpdateWidget(covariant PlanAvailabilityPanel old) {
    super.didUpdateWidget(old);
    if (old.username != widget.username) {
      unawaited(_loadAvoidPreferences());
    }
    final changed =
        old.username != widget.username ||
        old.todo?.id != widget.todo?.id ||
        old.editingBlock?.id != widget.editingBlock?.id ||
        old.todo?.version != widget.todo?.version ||
        old.todo?.updatedAt != widget.todo?.updatedAt;
    final dateChanged =
        _day(widget.initialDate) != _day(old.initialDate) &&
        _date != _day(widget.initialDate);
    final minutesChanged =
        old.initialMinutes != widget.initialMinutes &&
        _minutes != widget.initialMinutes;
    if (dateChanged) _date = _day(widget.initialDate);
    if (minutesChanged && widget.initialMinutes > 0) {
      _minutes = widget.initialMinutes;
      _duration.text = '$_minutes';
    }
    if (changed || dateChanged || minutesChanged) {
      _sequence++;
      _selectedStart = null;
      _snapshot = null;
      _result = null;
      _loading = false;
      _error = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onInvalidated();
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    StorageService.scopedDataRefreshNotifier.removeListener(_onRefresh);
    DeviceCalendarReadService.revision.removeListener(_invalidate);
    _duration.dispose();
    super.dispose();
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

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _invalidate();
  }

  void _invalidate() {
    if (!mounted) return;
    ++_sequence;
    setState(() {
      _selectedStart = null;
      _snapshot = null;
      _result = null;
      _error = null;
      _loading = false;
    });
    widget.onInvalidated();
    widget.onQueryChanged?.call(_query);
  }

  void _changeMinutes(int value) {
    _minutes = value;
    _duration.text = '$value';
    _invalidate();
  }

  Future<void> _editAvoid(PlanDailyTimeWindow? existing) async {
    final sequence = _avoidPreferencesSequence;
    var start = existing?.startMinutes ?? 900;
    var end = existing?.endMinutes ?? 960;
    String? error;
    final chosen = await showAppDialog<PlanDailyTimeWindow>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, update) {
          Future<void> pick(bool first) async {
            final value = first ? start : end;
            final time = await showAppTimePicker(
              context: context,
              initialTime: TimeOfDay(
                hour: value == 1440 ? 0 : value ~/ 60,
                minute: value % 60,
              ),
            );
            if (time == null || !context.mounted) return;
            update(() {
              final minutes = time.hour * 60 + time.minute;
              if (first) {
                start = minutes;
              } else {
                // The picker represents 24:00 as 00:00. Preserve the
                // end-of-day meaning when editing an avoidance window.
                end = minutes == 0 ? 1440 : minutes;
              }
              error = null;
            });
          }

          return AlertDialog(
            scrollable: true,
            title: Text(existing == null ? '自定义避让时段' : '调整${existing.label}时间'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextButton(
                  key: const ValueKey('plan-avoid-start'),
                  onPressed: () => pick(true),
                  child: Text('开始 ${_hhmm(start)}'),
                ),
                TextButton(
                  key: const ValueKey('plan-avoid-end'),
                  onPressed: () => pick(false),
                  child: Text('结束 ${_hhmm(end)}'),
                ),
                if (error != null)
                  Text(
                    error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('取消'),
              ),
              FilledButton(
                key: const ValueKey('plan-avoid-confirm'),
                onPressed: () {
                  if (end <= start) {
                    update(() => error = '结束时间须晚于开始时间');
                    return;
                  }
                  Navigator.pop(
                    dialogContext,
                    PlanDailyTimeWindow(existing?.label ?? '自定义', start, end),
                  );
                },
                child: const Text('应用'),
              ),
            ],
          );
        },
      ),
    );
    if (chosen == null || !mounted || sequence != _avoidPreferencesSequence) {
      return;
    }
    if (existing != null) {
      final index = _avoidOptions.indexOf(existing);
      _avoidOptions[index] = chosen;
      _enabledAvoid.remove(existing);
    } else {
      _avoidOptions.add(chosen);
    }
    _enabledAvoid.add(chosen);
    _avoidChanged();
  }

  Widget _avoidControls() => ExpansionTile(
    key: const ValueKey('plan-avoid-options'),
    tilePadding: EdgeInsets.zero,
    childrenPadding: EdgeInsets.zero,
    title: Text(
      _enabledAvoid.isEmpty
          ? '避让休息、用餐时间（可选）'
          : '已避开 ${_enabledAvoid.length} 个时段',
      style: Theme.of(context).textTheme.labelLarge,
    ),
    children: [
      for (var index = 0; index < _avoidOptions.length; index++)
        Wrap(
          spacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            FilterChip(
              key: ValueKey('plan-avoid-toggle-$index'),
              label: Text(_avoidOptions[index].label),
              selected: _enabledAvoid.contains(_avoidOptions[index]),
              onSelected: !_avoidPreferencesLoaded
                  ? null
                  : (enabled) {
                      if (enabled) {
                        _enabledAvoid.add(_avoidOptions[index]);
                      } else {
                        _enabledAvoid.remove(_avoidOptions[index]);
                      }
                      _avoidChanged();
                    },
            ),
            TextButton(
              key: ValueKey('plan-avoid-edit-$index'),
              onPressed: !_avoidPreferencesLoaded
                  ? null
                  : () => _editAvoid(_avoidOptions[index]),
              child: Text(
                '${_hhmm(_avoidOptions[index].startMinutes)}–${_hhmm(_avoidOptions[index].endMinutes)}',
              ),
            ),
            if (index >= 3)
              IconButton(
                tooltip: '移除此避让时段',
                key: ValueKey('plan-avoid-remove-$index'),
                icon: const Icon(Icons.close, size: 18),
                onPressed: !_avoidPreferencesLoaded
                    ? null
                    : () {
                        _enabledAvoid.remove(_avoidOptions[index]);
                        _avoidOptions.removeAt(index);
                        _avoidChanged();
                      },
              ),
          ],
        ),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          key: const ValueKey('plan-avoid-add'),
          onPressed: !_avoidPreferencesLoaded ? null : () => _editAvoid(null),
          icon: const Icon(Icons.add, size: 18),
          label: const Text('添加自定义时段'),
        ),
      ),
    ],
  );

  Future<void> _lookup() async {
    final query = _query;
    final invalid = PlanAvailabilityService.invalidReason(
      query,
      widget.todo,
      _now,
    );
    if (invalid != null) {
      setState(() => _error = PlanAvailabilityException(invalid));
      return;
    }
    final sequence = ++_sequence;
    setState(() {
      _loading = true;
      _selectedStart = null;
      _snapshot = null;
      _result = null;
      _error = null;
    });
    widget.onInvalidated();
    try {
      final snapshot =
          await (widget.loader?.call(query, forceRefresh: true) ??
              const PlanAvailabilityRepository().read(
                query,
                forceRefresh: true,
              ));
      if (!mounted || sequence != _sequence) return;
      setState(() {
        _snapshot = snapshot;
        _result = PlanAvailabilityService.find(query, snapshot, now: _now);
      });
    } catch (error) {
      if (!mounted || sequence != _sequence) return;
      setState(
        () => _error = error is PlanAvailabilityException
            ? error
            : const PlanAvailabilityException('安排读取失败，请重试'),
      );
    } finally {
      if (mounted && sequence == _sequence) setState(() => _loading = false);
    }
  }

  Future<void> _pickDate() async {
    final date = await showAppDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(_now.year - 100),
      lastDate: DateTime(_now.year + 100),
      currentDate: _now,
    );
    if (date != null && mounted) {
      _date = _day(date);
      _invalidate();
      widget.onDateChanged?.call(_date);
    }
  }

  Future<void> _pickWindow(bool start) async {
    final value = start ? _start : _end;
    final time = await showAppTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: (value ~/ 60) % 24, minute: value % 60),
    );
    if (time == null || !mounted) return;
    final minutes = time.hour * 60 + time.minute;
    if (start) {
      _start = minutes;
    } else {
      _end = minutes == 0 ? 1440 : minutes;
    }
    _invalidate();
  }

  String _hhmm(int minutes) =>
      '${(minutes ~/ 60).toString().padLeft(2, '0')}:${(minutes % 60).toString().padLeft(2, '0')}';

  String _sourceLabel(PlanBusySource source) => switch (source) {
    PlanBusySource.course => '课程',
    PlanBusySource.fixedSchedule => '固定日程',
    PlanBusySource.planBlock => '规划块',
    PlanBusySource.legacyTodo => '旧执行区间',
    PlanBusySource.deviceCalendar => '手机日历',
  };

  void _select(PlanTimeSlot slot) {
    final selection = PlanAvailabilitySelection(_query, slot, _snapshot!);
    if (!PlanAvailabilityService.accepts(selection, _snapshot!, now: _now)) {
      _invalidate();
      setState(() => _error = const PlanAvailabilityException('该时段已过去，请重新查找'));
      return;
    }
    setState(() => _selectedStart = slot.start);
    widget.onSelected(selection);
  }

  Widget _expansion({
    required bool open,
    required Duration duration,
    required Widget collapsed,
    required Widget expanded,
  }) => KeyedSubtree(
    key: const ValueKey('plan-availability-expansion'),
    child: duration == Duration.zero
        ? (open ? expanded : collapsed)
        : AnimatedCrossFade(
            duration: duration,
            firstCurve: Curves.easeInOut,
            secondCurve: Curves.easeInOut,
            sizeCurve: Curves.easeInOutCubic,
            alignment: Alignment.topCenter,
            crossFadeState: open
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            firstChild: collapsed,
            secondChild: expanded,
          ),
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final editable =
        widget.editingBlock == null ||
        PlanAvailabilityService.canReschedule(widget.editingBlock!);
    final open = _expanded && editable;
    final transitionDuration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 260);
    return Container(
      decoration: BoxDecoration(
        color: colors.primary.withValues(alpha: 0.045),
        border: Border.all(color: colors.primary.withValues(alpha: 0.18)),
        borderRadius: BorderRadius.circular(20),
      ),
      padding: const EdgeInsets.all(16),
      child: Material(
        color: Colors.transparent,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            OutlinedButton.icon(
              key: const ValueKey('plan-find-time'),
              style: OutlinedButton.styleFrom(
                side: BorderSide.none,
                padding: EdgeInsets.zero,
                alignment: Alignment.centerLeft,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              onPressed: editable
                  ? () => setState(() => _expanded = !_expanded)
                  : null,
              icon: const Icon(Icons.event_available_outlined),
              label: Row(
                children: [
                  const Expanded(
                    child: Text(
                      '找可用时间',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  AnimatedRotation(
                    turns: open ? 0.5 : 0,
                    duration: transitionDuration,
                    curve: Curves.easeInOutCubic,
                    child: const Icon(Icons.expand_more),
                  ),
                ],
              ),
            ),
            _expansion(
              open: open,
              duration: transitionDuration,
              collapsed: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  editable ? '避开已有安排，选择一个连续空闲时段' : '该规划状态不支持推荐改期',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ),
              expanded: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 8),
                  if (widget.dateShortcuts)
                    Wrap(
                      spacing: 8,
                      children: [
                        for (final offset in [0, 1])
                          TextButton(
                            key: ValueKey('plan-date-shortcut-$offset'),
                            onPressed: () {
                              final today = _day(_now);
                              _date = DateTime(
                                today.year,
                                today.month,
                                today.day + offset,
                              );
                              _invalidate();
                              widget.onDateChanged?.call(_date);
                            },
                            child: Text(offset == 0 ? '今天' : '明天'),
                          ),
                        TextButton(
                          onPressed: _pickDate,
                          child: const Text('其他日期'),
                        ),
                      ],
                    ),
                  Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      TextButton.icon(
                        key: const ValueKey('plan-availability-date'),
                        onPressed: _pickDate,
                        icon: const Icon(
                          Icons.calendar_today_outlined,
                          size: 18,
                        ),
                        label: Text(DateFormat('yyyy-MM-dd').format(_date)),
                      ),
                      TextButton(
                        key: const ValueKey('plan-window-start'),
                        onPressed: () => _pickWindow(true),
                        child: Text('从 ${_hhmm(_start)}'),
                      ),
                      TextButton(
                        key: const ValueKey('plan-window-end'),
                        onPressed: () => _pickWindow(false),
                        child: Text('到 ${_hhmm(_end)}'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text('需要多长时间？', style: theme.textTheme.labelLarge),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      for (final value in [15, 30, 45, 60])
                        ChoiceChip(
                          key: ValueKey('plan-duration-$value'),
                          label: Text('$value 分钟'),
                          selected: _minutes == value,
                          showCheckmark: false,
                          side: BorderSide.none,
                          backgroundColor: colors.surfaceContainerLow,
                          selectedColor: colors.primaryContainer,
                          onSelected: (_) => _changeMinutes(value),
                        ),
                      SizedBox(
                        width: 140,
                        child: TextField(
                          key: const ValueKey('plan-custom-duration'),
                          controller: _duration,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            labelText: '自定义',
                            suffixText: '分钟',
                            isDense: true,
                            filled: true,
                            fillColor: colors.surfaceContainerLow,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none,
                            ),
                          ),
                          onChanged: (value) {
                            _minutes = int.tryParse(value) ?? 0;
                            _invalidate();
                          },
                        ),
                      ),
                    ],
                  ),
                  if (widget.estimatedMinutes != null)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton(
                        onPressed: () =>
                            _changeMinutes(widget.estimatedMinutes!),
                        child: Text('采用历史估时 ${widget.estimatedMinutes} 分钟'),
                      ),
                    ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      const Text('推荐数量'),
                      for (final limit in [3, 5, 8])
                        ChoiceChip(
                          key: ValueKey('plan-result-limit-$limit'),
                          label: Text('$limit 个'),
                          selected: _resultLimit == limit,
                          showCheckmark: false,
                          onSelected: (_) {
                            _resultLimit = limit;
                            _invalidate();
                          },
                        ),
                    ],
                  ),
                  _avoidControls(),
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    key: const ValueKey('plan-lookup-slots'),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: _loading || !_avoidPreferencesLoaded
                        ? null
                        : _lookup,
                    icon: _loading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.search, size: 20),
                    label: Text(
                      _loading ? '正在查找' : (_error == null ? '查找时段' : '重新查找'),
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _error!.message,
                      style: TextStyle(color: colors.error),
                    ),
                    if (_error!.canUseAppOnly)
                      TextButton(
                        key: const ValueKey('plan-app-only'),
                        onPressed: () {
                          _appOnly = true;
                          _invalidate();
                          _lookup();
                        },
                        child: const Text('仅按应用内安排查找'),
                      ),
                  ],
                  if (_result?.message != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Text(_result!.message!),
                    ),
                  if (_result != null &&
                      _snapshot != null &&
                      _result!.slots.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    Text(
                      '可用时段 · ${_result!.slots.length} 个建议',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 10),
                    for (final slot in _result!.slots)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: OutlinedButton(
                          key: ValueKey(
                            'plan-slot-${slot.start.millisecondsSinceEpoch}',
                          ),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: _selectedStart == slot.start
                                ? colors.onPrimaryContainer
                                : colors.onSurface,
                            backgroundColor: _selectedStart == slot.start
                                ? colors.primaryContainer
                                : colors.surface,
                            side: BorderSide(
                              color: _selectedStart == slot.start
                                  ? colors.primary
                                  : colors.outlineVariant,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            padding: const EdgeInsets.all(14),
                          ),
                          onPressed: () => _select(slot),
                          child: Row(
                            children: [
                              Icon(
                                _selectedStart == slot.start
                                    ? Icons.check_circle_outline
                                    : Icons.schedule_outlined,
                                size: 22,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '${DateFormat('HH:mm').format(slot.start)}–${DateFormat('HH:mm').format(slot.end)}',
                                      style: theme.textTheme.titleMedium
                                          ?.copyWith(
                                            fontWeight: FontWeight.w600,
                                          ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      '${DateFormat('MM-dd').format(slot.start)} · ${slot.minutes} 分钟${_selectedStart == slot.start ? ' · 已选用' : ''}',
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(
                                            color: colors.onSurfaceVariant,
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              Icon(
                                _selectedStart == slot.start
                                    ? Icons.done
                                    : Icons.arrow_forward,
                                size: 18,
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                  const SizedBox(height: 12),
                  Text(
                    _snapshot?.coverage ??
                        (_appOnly
                            ? '仅按应用内安排查找；未计入手机日历'
                            : '检查应用内安排；手机日历仅在已开启且已授权时计入'),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                  if (_snapshot != null) ...[
                    if (_snapshot!.todo.dueDate != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          _snapshot!.todo.isDateOnly
                              ? '须在 ${DateFormat('MM-dd').format(_snapshot!.todo.dueDate!)} 当天结束前完成'
                              : '须在 ${DateFormat('MM-dd HH:mm').format(_snapshot!.todo.dueDate!)} 截止前完成',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ),
                    Theme(
                      data: theme.copyWith(dividerColor: Colors.transparent),
                      child: ExpansionTile(
                        key: const ValueKey('plan-busy-details'),
                        tilePadding: EdgeInsets.zero,
                        title: Text(
                          '已计入 ${_snapshot!.busy.length} 项占用',
                          style: theme.textTheme.bodySmall,
                        ),
                        children: [
                          for (final item
                              in (_snapshot!.busy.toList()..sort(
                                    (a, b) => a.start.compareTo(b.start),
                                  ))
                                  .take(50))
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  '${_sourceLabel(item.source)} · ${DateFormat('MM-dd HH:mm').format(item.start)}–${DateFormat('MM-dd HH:mm').format(item.end)}',
                                  style: theme.textTheme.bodySmall,
                                ),
                              ),
                            ),
                          if (_snapshot!.busy.isEmpty) const Text('已检查来源中没有占用'),
                          if (_snapshot!.busy.length > 50)
                            Text(
                              '另有 ${_snapshot!.busy.length - 50} 项占用，均已计入计算',
                            ),
                        ],
                      ),
                    ),
                  ],
                  if (_snapshot?.unknownTimes.isNotEmpty == true)
                    ExpansionTile(
                      tilePadding: EdgeInsets.zero,
                      title: Text(
                        '另有 ${_snapshot!.unknownTimes.length} 项安排时间未确定',
                        style: theme.textTheme.bodySmall,
                      ),
                      children: [
                        for (final text in _snapshot!.unknownTimes)
                          Padding(
                            padding: const EdgeInsets.all(8),
                            child: Text(text),
                          ),
                      ],
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
