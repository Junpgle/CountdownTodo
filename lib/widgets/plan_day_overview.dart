import 'dart:async';

import 'package:flutter/material.dart';

import '../models/plan_availability.dart';
import '../screens/plan_block_stats_screen.dart';
import '../services/plan_review_repository.dart';
import '../services/plan_todo_guard.dart';
import '../services/pomodoro_service.dart';
import '../utils/page_transitions.dart';

String planOverviewDuration(int seconds) {
  if (seconds == 0) return '0分';
  if (seconds < 60) return '$seconds秒';
  final hours = seconds ~/ 3600, minutes = seconds % 3600 ~/ 60;
  return '${hours > 0 ? '$hours时' : ''}${minutes > 0 ? '$minutes分' : ''}'
      '${seconds % 60 > 0 ? '${seconds % 60}秒' : ''}';
}

/// A bounded summary above the day grid. Loading and failures never replace it.
class PlanDayOverview extends StatefulWidget {
  const PlanDayOverview({
    super.key,
    required this.username,
    required this.date,
    this.repository,
    this.clock,
    this.revision = 0,
    this.enabled = true,
  });
  final String username;
  final DateTime date;
  final PlanReviewRepository? repository;
  final DateTime Function()? clock;
  final int revision;
  final bool enabled;
  @override
  State<PlanDayOverview> createState() => _PlanDayOverviewState();
}

class _PlanDayOverviewState extends State<PlanDayOverview>
    with WidgetsBindingObserver {
  late PlanReviewRepository _repository;
  PlanTodoIdentity? _identity;
  PlanReviewOverview? _data;
  Timer? _boundary;
  DateTime? _expiredBoundary;
  StreamSubscription<PomodoroRunState?>? _focus;
  int _sequence = 0;
  bool _foreground = true, _visible = false, _loading = false, _opening = false;
  String? _error;
  DateTime get _now => widget.clock?.call() ?? DateTime.now();
  DateTime get _start => DateUtils.dateOnly(widget.date);
  DateTime get _end => DateTime(_start.year, _start.month, _start.day + 1);
  bool get _active => _visible && widget.enabled && _foreground;
  bool get _canOpen =>
      _active && !_loading && !_opening && _data != null && _error == null;

  PlanReviewRepository _makeRepository() =>
      widget.repository ?? PlanReviewRepository(clock: () => _now);

  @override
  void initState() {
    super.initState();
    _repository = _makeRepository();
    WidgetsBinding.instance.addObserver(this);
    _focus = PomodoroService.onRunStateChanged.listen((_) {
      if (_active && !_opening) unawaited(_load());
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final visible = ModalRoute.of(context)?.isCurrent ?? true;
    if (visible != _visible) {
      _visible = visible;
      _invalidate();
      if (_active && !_opening) unawaited(_load());
    }
  }

  void _invalidate({bool clear = false}) {
    ++_sequence;
    _boundary?.cancel();
    _loading = false;
    if (clear) {
      _data = null;
      _error = null;
    }
  }

  @override
  void didUpdateWidget(covariant PlanDayOverview oldWidget) {
    super.didUpdateWidget(oldWidget);
    final identityChanged =
        oldWidget.username != widget.username ||
        oldWidget.repository != widget.repository;
    final dateChanged = !DateUtils.isSameDay(oldWidget.date, widget.date);
    if (identityChanged) {
      _identity = null;
      _repository = _makeRepository();
    }
    if (identityChanged ||
        dateChanged ||
        oldWidget.revision != widget.revision ||
        oldWidget.enabled != widget.enabled) {
      _invalidate(clear: identityChanged || dateChanged);
      if (_active && !_opening) unawaited(_load());
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _invalidate();
    if (mounted) setState(() {});
    if (_active && !_opening) unawaited(_load());
  }

  @override
  void dispose() {
    _invalidate();
    _focus?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _load() async {
    if (!_active || _opening) return;
    final request = ++_sequence;
    final username = widget.username, start = _start, end = _end;
    _boundary?.cancel();
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await _identity?.check();
      final data = await _repository.readOverview(username, start, end);
      await data.identity.check();
      await _identity?.check();
      if (!mounted || request != _sequence || !_active) return;
      if (data.identity.username != username ||
          data.start != start ||
          data.end != end) {
        throw StateError('概览范围已变化，请重试');
      }
      setState(() {
        _identity ??= data.identity;
        _data = data;
        _loading = false;
      });
      _schedule(data.nextBoundary);
    } catch (error) {
      if (mounted && request == _sequence && _active) {
        setState(() {
          _loading = false;
          _data = null;
          _error = error is PlanAvailabilityException
              ? error.message
              : error is StateError
              ? error.message.toString()
              : '概览读取失败，请重试';
        });
      }
    }
  }

  void _schedule(DateTime boundary) {
    _boundary?.cancel();
    if (!_active || _opening) return;
    final delay = boundary.difference(_now);
    final expired = delay <= Duration.zero;
    if (expired && _expiredBoundary == boundary) return;
    _expiredBoundary = expired ? boundary : null;
    _boundary = Timer(expired ? Duration.zero : delay, () {
      if (_active && (ModalRoute.of(context)?.isCurrent ?? true)) {
        unawaited(_load());
      }
    });
  }

  Future<void> _open([PlanReviewFilter? filter]) async {
    if (!_canOpen) return;
    final data = _data!, request = ++_sequence;
    final username = widget.username;
    _boundary?.cancel();
    setState(() => _opening = true);
    try {
      await data.identity.check();
      if (!mounted || request != _sequence || !_active) return;
      await Navigator.of(context).push(
        PageTransitions.material(
          builder: (_) => filter == null
              ? PlanBlockStatsScreen(
                  username: username,
                  repository: _repository,
                  initialDate: data.start,
                  clock: widget.clock,
                )
              : PlanReviewDetailScreen(
                  username: username,
                  repository: _repository,
                  identity: data.identity,
                  start: data.start,
                  end: data.end,
                  filter: filter,
                  clock: widget.clock,
                ),
        ),
      );
    } catch (error) {
      if (mounted && request == _sequence) {
        setState(() {
          _data = null;
          _error = error is PlanAvailabilityException
              ? error.message
              : error is StateError
              ? error.message.toString()
              : '明细打开失败，请重试';
        });
      }
    } finally {
      if (mounted) {
        setState(() => _opening = false);
        if (_active) unawaited(_load());
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context), colors = theme.colorScheme;
    final data = _data;
    Widget content;
    if (_error != null) {
      content = Tooltip(
        message: _error!,
        child: Row(
          children: [
            Icon(Icons.info_outline, size: 18, color: colors.error),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _error!.contains('账号或成员') ? '身份已变化，请重新打开' : '概览加载失败',
                key: const ValueKey('plan-overview-error'),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colors.error,
                ),
              ),
            ),
            IconButton(
              key: const ValueKey('plan-overview-retry'),
              tooltip: '重试概览',
              onPressed: _active ? _load : null,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
      );
    } else if (data == null) {
      content = SizedBox(
        height: 48,
        child: Row(
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: _active
                  ? const CircularProgressIndicator(strokeWidth: 2)
                  : const Icon(Icons.schedule, size: 16),
            ),
            SizedBox(width: 10),
            Expanded(child: Text('正在读取当日概览…')),
          ],
        ),
      );
    } else {
      final ended = data.plan('ended'), done = data.plan('done');
      final metrics = <(String, String, String, PlanReviewFilter, String)>[
        (
          '真实规划',
          planOverviewDuration(data.plan('seconds')),
          reviewDuration(data.plan('seconds')),
          PlanReviewFilter.plans,
          'plans',
        ),
        (
          '有效专注',
          planOverviewDuration(data.actual('seconds')),
          reviewDuration(data.actual('seconds')),
          PlanReviewFilter.focus,
          'focus',
        ),
        (
          '已结束完成',
          ended == 0 ? '暂无' : '$done/$ended',
          ended == 0 ? '暂无已结束规划' : '完成$done项，共$ended项已结束规划',
          PlanReviewFilter.ended,
          'ended',
        ),
        (
          '时间日志',
          planOverviewDuration(data.log('seconds')),
          reviewDuration(data.log('seconds')),
          PlanReviewFilter.logs,
          'logs',
        ),
      ];
      final labelStyle = theme.textTheme.labelSmall!;
      final valueStyle = theme.textTheme.titleSmall!.copyWith(
        fontWeight: FontWeight.w700,
        color: colors.primary,
      );
      double measure(String value, TextStyle style) => (TextPainter(
        text: TextSpan(text: value, style: style),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
        maxLines: 1,
      )..layout()).width;
      final issues = data.issues > 0
          ? IconButton(
              key: const ValueKey('plan-overview-issues'),
              tooltip: '有记录待核对（${data.issues}项）',
              onPressed: _canOpen ? () => _open(PlanReviewFilter.issues) : null,
              icon: Badge(
                label: Text('${data.issues}'),
                child: Icon(
                  Icons.info_outline,
                  size: 18,
                  color: colors.tertiary,
                ),
              ),
            )
          : null;
      content = LayoutBuilder(
        builder: (context, constraints) {
          final cell =
              (constraints.maxWidth - (issues == null ? 0 : 48) - 18) / 4;
          final fits =
              MediaQuery.textScalerOf(context).scale(14) <= 20 &&
              metrics.every(
                (m) =>
                    measure(m.$1, labelStyle) + 12 <= cell &&
                    measure(m.$2, valueStyle) + 12 <= cell,
              );
          return Row(
            children: [
              Expanded(
                child: fits
                    ? Row(
                        children: [
                          for (var i = 0; i < metrics.length; i++) ...[
                            if (i > 0) const SizedBox(width: 6),
                            Expanded(
                              child: Semantics(
                                label: '${metrics[i].$1}，${metrics[i].$3}',
                                button: true,
                                enabled: _canOpen,
                                onTap: _canOpen
                                    ? () => _open(metrics[i].$4)
                                    : null,
                                excludeSemantics: true,
                                child: InkWell(
                                  key: ValueKey(
                                    'plan-overview-${metrics[i].$5}',
                                  ),
                                  borderRadius: BorderRadius.circular(10),
                                  onTap: _canOpen
                                      ? () => _open(metrics[i].$4)
                                      : null,
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 8,
                                      horizontal: 6,
                                    ),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(metrics[i].$2, style: valueStyle),
                                        const SizedBox(height: 3),
                                        Text(metrics[i].$1, style: labelStyle),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ],
                      )
                    : TextButton(
                        key: const ValueKey('plan-overview-open'),
                        style: TextButton.styleFrom(
                          alignment: Alignment.centerLeft,
                          padding: const EdgeInsets.symmetric(vertical: 10),
                        ),
                        onPressed: _canOpen ? () => _open() : null,
                        child: Row(
                          children: [
                            const Expanded(child: Text('当日概览')),
                            const Text('查看'),
                            const SizedBox(width: 4),
                            const Icon(Icons.chevron_right, size: 18),
                          ],
                        ),
                      ),
              ),
              ?issues,
            ],
          );
        },
      );
    }
    return Material(
      color: colors.surface,
      child: Padding(
        key: const ValueKey('plan-day-overview'),
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            content,
            SizedBox(
              height: 2,
              child:
                  _visible &&
                      _foreground &&
                      (_loading || !widget.enabled) &&
                      data != null
                  ? const LinearProgressIndicator()
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}
