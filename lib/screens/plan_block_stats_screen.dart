import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models.dart';
import '../services/plan_review_repository.dart';
import '../services/plan_todo_guard.dart';
import '../services/pomodoro_service.dart';
import '../storage_service.dart';
import '../utils/app_dialogs.dart';
import '../utils/page_transitions.dart';
import '../widgets/floating_glass_control.dart';
import '../widgets/missed_plan_recovery_flow.dart';
import 'course_screens.dart';

String reviewDuration(int seconds) {
  if (seconds == 0) return '0分钟';
  final hours = seconds ~/ 3600, minutes = seconds % 3600 ~/ 60;
  final remainder = seconds % 60;
  return [
    if (hours > 0) '$hours小时',
    if (minutes > 0) '$minutes分钟',
    if (remainder > 0) '$remainder秒',
  ].join(' ');
}

String _date(int ms) {
  if (ms <= 0 || ms > 8640000000000000) return '时间待核对';
  return DateFormat('M/d HH:mm')
      .format(DateTime.fromMillisecondsSinceEpoch(ms));
}

String _period(PlanReviewEntry e) => '${_date(e.start)} — ${_date(e.end)}';
String _message(Object e) =>
    e is StateError ? e.message.toString() : e.toString();
String _label(PlanReviewFilter f) => switch (f) {
  PlanReviewFilter.plans => '真实规划',
  PlanReviewFilter.ended => '已结束规划',
  PlanReviewFilter.missed => '漏做规划',
  PlanReviewFilter.focus => '有效专注',
  PlanReviewFilter.linked => '已关联规划',
  PlanReviewFilter.unlinked => '未关联规划',
  PlanReviewFilter.attribution => '归属待核对',
  PlanReviewFilter.logs => '时间日志',
  PlanReviewFilter.issues => '需要核对',
};

const _scopeText =
    '规划与专注按开始的本地日期归属，跨午夜仅计一次。专注使用已结束记录的实际秒数，包含中断与切换，零秒保留为零。旧记录缺失实际时长时列为待核对，因此可能与番茄统计的旧记录兼容值不同。\n\n完成比例只看已结束的真实规划状态，不代表待办完成度。课程、日历和旧式待办区间不计入真实规划；取消、跳过单列。\n\n时间日志按范围裁剪，记录之间可能重叠，不能与专注相加为总工作量。规划原累计缓存仅作参考，不补入实际。';

/// Only visible routes refresh. Each screen owns at most one boundary timer.
abstract class _ReviewLiveState<T extends StatefulWidget> extends State<T>
    with WidgetsBindingObserver {
  PlanTodoIdentity? identity;
  int sequence = 0;
  bool foreground = true, opening = false;
  Timer? boundary;
  StreamSubscription<PomodoroRunState?>? _focus;
  Future<void> load();
  void refresh() {
    if (mounted &&
        foreground &&
        !opening &&
        (ModalRoute.of(context)?.isCurrent ?? true)) {
      unawaited(load());
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    StorageService.scopedDataRefreshNotifier.addListener(refresh);
    _focus = PomodoroService.onRunStateChanged.listen((_) => refresh());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    foreground = state == AppLifecycleState.resumed;
    if (foreground) {
      refresh();
    } else {
      boundary?.cancel();
      sequence++;
    }
  }

  Future<bool> accept(PlanTodoIdentity current, int request) async {
    await identity?.check();
    await current.check();
    if (!mounted || request != sequence || !foreground) return false;
    identity ??= current;
    return true;
  }

  void schedule(DateTime next, DateTime now) {
    boundary?.cancel();
    final delay = next.difference(now);
    if (!opening && foreground) {
      boundary = Timer(
        delay.isNegative ? const Duration(milliseconds: 1) : delay,
        refresh,
      );
    }
  }

  @override
  void dispose() {
    sequence++;
    boundary?.cancel();
    _focus?.cancel();
    StorageService.scopedDataRefreshNotifier.removeListener(refresh);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}

class PlanBlockStatsScreen extends StatefulWidget {
  const PlanBlockStatsScreen({
    super.key,
    required this.username,
    this.repository,
    this.clock,
    this.initialDate,
  });
  final String username;
  final PlanReviewRepository? repository;
  final DateTime Function()? clock;
  final DateTime? initialDate;
  @override
  State<PlanBlockStatsScreen> createState() => _PlanBlockStatsScreenState();
}

class _PlanBlockStatsScreenState
    extends _ReviewLiveState<PlanBlockStatsScreen> {
  late DateTime _current;
  late final PlanReviewRepository _repository;
  int _dimension = 0;
  bool _loading = true;
  String? _error;
  PlanReviewSummary? _data;
  DateTime get _now => widget.clock?.call() ?? DateTime.now();
  DateTimeRange get _range {
    final start = switch (_dimension) {
      1 => DateTime(
        _current.year,
        _current.month,
        _current.day - _current.weekday + 1,
      ),
      2 => DateTime(_current.year, _current.month, 1),
      _ => DateTime(_current.year, _current.month, _current.day),
    };
    return DateTimeRange(
      start: start,
      end: _dimension == 2
          ? DateTime(start.year, start.month + 1, 1)
          : DateTime(
              start.year,
              start.month,
              start.day + (_dimension == 1 ? 7 : 1),
            ),
    );
  }

  String get _rangeLabel => _dimension == 2
      ? DateFormat('yyyy年M月').format(_current)
      : _dimension == 0
      ? DateFormat('yyyy年M月d日').format(_current)
      : '${DateFormat('M/d').format(_range.start)} — ${DateFormat('M/d').format(DateTime(_range.end.year, _range.end.month, _range.end.day - 1))}';
  @override
  void initState() {
    _current = widget.initialDate ?? _now;
    _repository =
        widget.repository ?? PlanReviewRepository(clock: widget.clock);
    super.initState();
    unawaited(load());
  }

  @override
  Future<void> load() async {
    final request = ++sequence;
    boundary?.cancel();
    setState(() {
      _loading = true;
      _error = null;
      if (_data?.start != _range.start || _data?.end != _range.end) {
        _data = null;
      }
    });
    try {
      await identity?.check();
      final range = _range;
      final data = await _repository.read(
        widget.username,
        range.start,
        range.end,
      );
      if (!await accept(data.identity, request)) return;
      setState(() {
        _data = data;
        _loading = false;
      });
      schedule(data.nextBoundary, _now);
    } catch (e) {
      if (mounted && request == sequence) {
        setState(() {
          _error = _message(e);
          _loading = false;
          _data = null;
        });
      }
    }
  }

  void _navigate(int delta) {
    setState(() {
      _current = _dimension == 2
          ? DateTime(_current.year, _current.month + delta, 1)
          : DateTime(
              _current.year,
              _current.month,
              _current.day + delta * (_dimension == 1 ? 7 : 1),
            );
    });
    unawaited(load());
  }

  Future<void> _open(
    PlanReviewFilter filter, {
    String? todoId,
    String? title,
    DateTime? start,
    DateTime? end,
  }) async {
    if (opening || identity == null) return;
    opening = true;
    boundary?.cancel();
    try {
      await identity!.check();
      if (!mounted) return;
      final range = _range;
      await Navigator.of(context).push(
        PageTransitions.material(
          builder: (_) => PlanReviewDetailScreen(
            username: widget.username,
            repository: _repository,
            identity: identity!,
            start: start ?? range.start,
            end: end ?? range.end,
            filter: filter,
            todoId: todoId,
            title: title,
            clock: widget.clock,
          ),
        ),
      );
    } catch (e) {
      if (mounted) _notice(context, _message(e));
    } finally {
      opening = false;
      if (mounted && foreground) await load();
    }
  }

  Future<void> _recover(String id) async {
    if (opening) return;
    opening = true;
    boundary?.cancel();
    try {
      await identity?.check();
      if (!mounted) return;
      await showMissedPlanRecovery(
        context: context,
        username: widget.username,
        sourceId: id,
        onSaved: () async {},
      );
    } catch (e) {
      if (mounted) _notice(context, _message(e));
    } finally {
      opening = false;
      if (mounted && foreground) await load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context), colors = theme.colorScheme;
    final compactDate =
        MediaQuery.sizeOf(context).width < 400 &&
        MediaQuery.textScalerOf(context).scale(16) > 20;
    final top = floatingGlassTopBarHeight(context);
    return Scaffold(
      backgroundColor: colors.surface,
      extendBodyBehindAppBar: true,
      appBar: FloatingGlassAppBar(
        flexibleSpace: const FloatingGlassTopBarBackground(),
        title: const Text('规划统计'),
        actions: [
          IconButton(
            tooltip: '统计口径',
            icon: const Icon(Icons.info_outline),
            onPressed: () => _scope(context),
          ),
        ],
      ),
      body: FloatingGlassTopBarContentFade(
        topBarHeight: top,
        child: RefreshIndicator(
          onRefresh: load,
          child: ListView(
            key: const PageStorageKey('plan-review-overview'),
            padding: EdgeInsets.fromLTRB(16, top + 12, 16, 32),
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 900),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SegmentedButton<int>(
                        segments: const [
                          ButtonSegment(value: 0, label: Text('日')),
                          ButtonSegment(value: 1, label: Text('周')),
                          ButtonSegment(value: 2, label: Text('月')),
                        ],
                        selected: {_dimension},
                        onSelectionChanged: (v) {
                          setState(() => _dimension = v.first);
                          unawaited(load());
                        },
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          IconButton(
                            tooltip: '上一时段',
                            onPressed: () => _navigate(-1),
                            icon: const Icon(Icons.chevron_left),
                          ),
                          Expanded(
                            child: Tooltip(
                              message: _rangeLabel,
                              child: Text(
                                compactDate && _dimension == 0
                                    ? DateFormat('M月d日').format(_current)
                                    : _rangeLabel,
                                textAlign: TextAlign.center,
                                style: theme.textTheme.titleMedium,
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: '下一时段',
                            onPressed: () => _navigate(1),
                            icon: const Icon(Icons.chevron_right),
                          ),
                        ],
                      ),
                      if (_loading && _data == null)
                        const Padding(
                          padding: EdgeInsets.all(40),
                          child: Center(child: CircularProgressIndicator()),
                        )
                      else if (_error != null)
                        _ReviewError(error: _error!, retry: load)
                      else if (_data != null)
                        ..._content(_data!),
                      if (_loading && _data != null)
                        const LinearProgressIndicator(),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _content(PlanReviewSummary s) {
    final theme = Theme.of(context), colors = theme.colorScheme;
    final ended = s.plan('ended'), done = s.plan('done');
    return [
      Text(
        '本期概览',
        style: theme.textTheme.headlineSmall?.copyWith(
          fontWeight: FontWeight.w700,
        ),
      ),
      const SizedBox(height: 6),
      Text(
        '按开始日统计 · 时间日志单独查看',
        style: theme.textTheme.bodySmall?.copyWith(
          color: colors.onSurfaceVariant,
        ),
      ),
      const SizedBox(height: 16),
      LayoutBuilder(
        builder: (context, c) {
          final minimum = 136 * MediaQuery.textScalerOf(context).scale(14) / 14;
          final columns = c.maxWidth >= 720 && c.maxWidth >= minimum * 4 + 30
              ? 4
              : c.maxWidth >= minimum * 2 + 10
              ? 2
              : 1;
          final width = (c.maxWidth - (columns - 1) * 10) / columns;
          return Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _metric(
                width,
                '真实规划',
                reviewDuration(s.plan('seconds')),
                '${s.plan('n')}项 · 未结束${s.plan('upcoming')}项',
                Icons.calendar_today_outlined,
                colors.primary,
                () => _open(PlanReviewFilter.plans),
                'review-plans',
              ),
              _metric(
                width,
                '已结束规划',
                ended == 0 ? '暂无' : '$done / $ended',
                ended == 0
                    ? '暂无已结束规划'
                    : '完成比例 ${(done * 100 / ended).round()}%',
                Icons.task_alt,
                colors.primary,
                () => _open(PlanReviewFilter.ended),
                'review-ended',
              ),
              _metric(
                width,
                '有效专注',
                reviewDuration(s.actual('seconds')),
                '${s.actual('n')}条已核实记录',
                Icons.timer_outlined,
                colors.tertiary,
                () => _open(PlanReviewFilter.focus),
                'review-focus',
              ),
              _metric(
                width,
                '时间日志',
                reviewDuration(s.log('seconds')),
                '${s.log('n')}条 · 可能重叠',
                Icons.edit_calendar_outlined,
                colors.secondary,
                () => _open(PlanReviewFilter.logs),
                'review-logs',
              ),
            ],
          );
        },
      ),
      const SizedBox(height: 8),
      Text(
        '取消 ${s.plan('cancelled')}项 · 跳过 ${s.plan('skipped')}项 · 不计入执行预算',
        style: theme.textTheme.bodySmall,
      ),
      if (s.plan('n') == 0 &&
          s.actual('n') == 0 &&
          s.log('n') == 0 &&
          s.issues == 0)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 24),
          child: Text('这个时段暂无真实规划或实际记录。课程和日历安排可在规划时间轴查看。'),
        ),
      const SizedBox(height: 24),
      _trend(s),
      if (s.ranking.isNotEmpty) ...[
        const SizedBox(height: 24),
        Text('待办投入排行', style: theme.textTheme.titleMedium),
        const SizedBox(height: 4),
        const Text('按具体待办区分 · 展示前10项'),
        ...s.ranking.indexed.map((pair) {
          final (i, row) = pair;
          return ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Text(
              '${i + 1}'.padLeft(2, '0'),
              style: theme.textTheme.titleLarge?.copyWith(
                color: colors.primary,
              ),
            ),
            title: Text(
              row['title']?.toString() ?? '历史待办',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              '${reviewDuration((row['seconds'] as num).toInt())} · ${row['n']}条记录',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _open(
              PlanReviewFilter.focus,
              todoId: row['id'] as String,
              title: row['title'] as String?,
            ),
          );
        }),
      ],
      if (s.issues > 0 || s.missed.isNotEmpty) ...[
        const SizedBox(height: 24),
        Text('需要处理', style: theme.textTheme.titleMedium),
        if (s.issues > 0)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.fact_check_outlined, color: colors.error),
            title: Text('${s.issues}项需要核对'),
            subtitle: const Text('缺失时长、归属或状态待核对，点开查看依据'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _open(PlanReviewFilter.issues),
          ),
        if (s.missed.isNotEmpty)
          Text('漏做规划 (${s.plan('missed')})', style: theme.textTheme.titleSmall),
        ...s.missed.map(
          (e) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              children: [
                Text('${e.title}  ${_period(e)}'),
                TextButton(
                  key: ValueKey('plan-stats-recover-${e.id}'),
                  onPressed: () => _recover(e.id),
                  child: const Text('重新安排'),
                ),
              ],
            ),
          ),
        ),
        if (s.plan('missed') > 10)
          TextButton(
            key: const ValueKey('plan-stats-all-missed'),
            onPressed: () => _open(PlanReviewFilter.missed),
            child: const Text('查看全部漏做'),
          ),
      ],
      const SizedBox(height: 24),
      _section('复盘提示', [
        if (s.plan('ended') == 0)
          const Text('暂无已结束规划，积累实际记录后再复盘。')
        else if (s.plan('missed') >= 3)
          Text('本期有${s.plan('missed')}项漏做规划，可先核对已有安排，再决定是否重新安排。')
        else
          Text(
            '本期${s.plan('ended')}项已结束规划中，${s.plan('done')}项标记完成。完成状态不代表待办完成度。',
          ),
        if (s.plan('ended') > 0)
          TextButton(
            onPressed: () => _open(
              s.plan('missed') >= 3
                  ? PlanReviewFilter.missed
                  : PlanReviewFilter.ended,
            ),
            child: const Text('查看触发依据'),
          ),
        if (s.plan('seconds') >= 28800 * s.days.length) ...[
          const Text('平均每天规划达到8小时，可核对是否留足课程、用餐与休息时间。'),
          TextButton(
            onPressed: () => _open(PlanReviewFilter.plans),
            child: const Text('查看规划预算'),
          ),
        ],
        const Text('依据本地记录生成，不会自动改动安排。'),
      ]),
    ];
  }

  Widget _metric(
    double width,
    String title,
    String value,
    String hint,
    IconData icon,
    Color color,
    VoidCallback tap,
    String key,
  ) {
    final theme = Theme.of(context);
    return SizedBox(
      width: width,
      child: Card(
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        color: theme.colorScheme.surfaceContainerLow,
        child: InkWell(
          key: ValueKey(key),
          onTap: tap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, color: color, size: 21),
                const SizedBox(height: 14),
                Text(title, style: theme.textTheme.labelLarge),
                const SizedBox(height: 5),
                Text(
                  value,
                  style: theme.textTheme.titleLarge?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(hint, style: theme.textTheme.bodySmall),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _section(String title, List<Widget> children) => Card(
    margin: EdgeInsets.zero,
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 10),
          ...children,
        ],
      ),
    ),
  );
  Widget _trend(PlanReviewSummary s) {
    final colors = Theme.of(context).colorScheme;
    final maxSeconds = s.days.fold<int>(
      1,
      (m, d) => math.max(
        m,
        math.max((d['planned'] as num).toInt(), (d['actual'] as num).toInt()),
      ),
    );
    return _section('投入趋势', [
      Wrap(
        spacing: 16,
        children: [
          Text('● 真实规划', style: TextStyle(color: colors.primary)),
          Text('● 有效专注', style: TextStyle(color: colors.tertiary)),
        ],
      ),
      const SizedBox(height: 20),
      SizedBox(
        height: 112,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: s.days.indexed.map((pair) {
            final (i, d) = pair;
            final date = DateTime.fromMillisecondsSinceEpoch(d['start'] as int);
            final planned = (d['planned'] as num).toInt(),
                actual = (d['actual'] as num).toInt();
            return Expanded(
              child: Tooltip(
                message:
                    '${DateFormat('M/d').format(date)}\n规划 ${reviewDuration(planned)}\n专注 ${reviewDuration(actual)}',
                child: InkWell(
                  onTap: () => _open(
                    PlanReviewFilter.focus,
                    start: date,
                    end: DateTime(date.year, date.month, date.day + 1),
                    title: '${DateFormat('M/d').format(date)}专注明细',
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      SizedBox(
                        height: 82,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Flexible(
                              child: Container(
                                width: 24,
                                height: math.max(2, 82 * planned / maxSeconds),
                                margin: const EdgeInsets.symmetric(
                                  horizontal: 1,
                                ),
                                decoration: BoxDecoration(
                                  color: colors.primary,
                                  borderRadius: BorderRadius.circular(3),
                                ),
                              ),
                            ),
                            Flexible(
                              child: Container(
                                width: 24,
                                height: math.max(2, 82 * actual / maxSeconds),
                                margin: const EdgeInsets.symmetric(
                                  horizontal: 1,
                                ),
                                decoration: BoxDecoration(
                                  color: colors.tertiary,
                                  borderRadius: BorderRadius.circular(3),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        s.days.length <= 7 || i % 5 == 0 ? '${date.day}' : '',
                        textScaler: TextScaler.noScaling,
                        style: const TextStyle(fontSize: 11),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
      const SizedBox(height: 6),
      const Text('点按查看当天专注 · 两组数字不用于计算任务完成度'),
    ]);
  }
}

class PlanReviewDetailScreen extends StatefulWidget {
  const PlanReviewDetailScreen({
    super.key,
    required this.username,
    required this.repository,
    required this.identity,
    required this.start,
    required this.end,
    required this.filter,
    this.todoId,
    this.planId,
    this.title,
    this.clock,
    this.cumulative = false,
  });
  final String username;
  final PlanReviewRepository repository;
  final PlanTodoIdentity identity;
  final DateTime start, end;
  final PlanReviewFilter filter;
  final String? todoId, planId, title;
  final DateTime Function()? clock;
  final bool cumulative;
  @override
  State<PlanReviewDetailScreen> createState() => _PlanReviewDetailScreenState();
}

class _PlanReviewDetailScreenState
    extends _ReviewLiveState<PlanReviewDetailScreen> {
  late PlanReviewFilter _filter;
  PlanReviewPage? _page;
  List<PlanReviewEntry> _rows = [];
  PlanReviewFilter? _loadedFilter;
  bool _loading = true;
  String? _error;
  DateTime get _now => widget.clock?.call() ?? DateTime.now();
  @override
  void initState() {
    _filter = widget.filter;
    identity = widget.identity;
    super.initState();
    unawaited(load());
  }

  @override
  Future<void> load({bool more = false}) async {
    final request = ++sequence;
    boundary?.cancel();
    setState(() {
      _loading = true;
      _error = null;
      if (!more && _loadedFilter != _filter) {
        _rows = [];
        _page = null;
      }
    });
    try {
      await identity!.check();
      final page = await widget.repository.page(
        widget.username,
        widget.start,
        widget.end,
        _filter,
        todoId: widget.todoId,
        planId: widget.planId,
        cumulative: widget.cumulative,
        cursor: more ? _page?.next : null,
      );
      if (!await accept(page.identity, request)) return;
      setState(() {
        final keepLoaded =
            !more &&
            _loadedFilter == _filter &&
            _rows.length > 50 &&
            _page?.fingerprint == page.fingerprint;
        if (!keepLoaded) {
          _rows = more && !page.restarted
              ? [..._rows, ...page.rows]
              : page.rows;
          _page = page;
        }
        _loadedFilter = _filter;
        _loading = false;
      });
      schedule(page.nextBoundary, _now);
    } catch (e) {
      if (mounted && request == sequence) {
        setState(() {
          _error = _message(e);
          _loading = false;
          if (!more) {
            _rows = [];
            _page = null;
          }
        });
      }
    }
  }

  Future<void> _recover(PlanReviewEntry e) async {
    if (opening) return;
    opening = true;
    boundary?.cancel();
    try {
      await identity!.check();
      if (!mounted) return;
      await showMissedPlanRecovery(
        context: context,
        username: widget.username,
        sourceId: e.id,
        onSaved: () async {},
      );
    } catch (e) {
      if (mounted) _notice(context, _message(e));
    } finally {
      opening = false;
      if (mounted && foreground) await load();
    }
  }

  Future<void> _openEntry(PlanReviewEntry e) async {
    if (opening) return;
    opening = true;
    boundary?.cancel();
    try {
      final row = await widget.repository.detail(identity!, e.kind, e.id);
      if (!mounted) return;
      if (e.kind == 'plan') {
        final period = await widget.repository.page(
          widget.username,
          widget.start,
          widget.end,
          PlanReviewFilter.focus,
          planId: e.id,
        );
        final lifetime = await widget.repository.page(
          widget.username,
          widget.start,
          widget.end,
          PlanReviewFilter.focus,
          planId: e.id,
          cumulative: true,
        );
        await identity!.check();
        if (!mounted) return;
        final target = await showAppDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            scrollable: true,
            title: Text(e.title),
            content: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_period(e)),
                Text(
                  '原计划 ${row['planned_minutes']}分钟 · 状态 ${_status(row['status'])}',
                ),
                const SizedBox(height: 12),
                Text('本期记录投入 ${reviewDuration(period.seconds)}'),
                Text('累计记录投入 ${reviewDuration(lifetime.seconds)}'),
                Text('原累计参考 ${row['actual_focus_seconds'] ?? 0}秒（不计入实际）'),
                if (e.reason.isNotEmpty) Text(e.reason),
                const SizedBox(height: 8),
                const Text('本期与累计投入分开统计，原累计仅作历史参考。'),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('关闭'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('本期记录'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('累计记录'),
              ),
            ],
          ),
        );
        if (target != null && mounted) {
          await Navigator.of(context).push(
            PageTransitions.material(
              builder: (_) => PlanReviewDetailScreen(
                username: widget.username,
                repository: widget.repository,
                identity: identity!,
                start: widget.start,
                end: widget.end,
                filter: PlanReviewFilter.focus,
                planId: e.id,
                title: target ? '累计记录投入' : '本期记录投入',
                cumulative: target,
                clock: widget.clock,
              ),
            ),
          );
        }
      } else if (_filter == PlanReviewFilter.issues ||
          row['review_valid'] != true) {
        await showAppDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            scrollable: true,
            title: Text(e.title),
            content: Text(
              '${e.reason}\n${_period(e)}\n原实际秒数：${row['actual_duration'] ?? '缺失'}\n原计划秒数：${row['planned_duration'] ?? '无'}\n原状态：${row['status'] ?? '无'}\n记录ID：${e.id}',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('关闭'),
              ),
            ],
          ),
        );
      } else {
        await identity!.check();
        if (!mounted) return;
        Widget screen;
        final recordTags = (row['review_tags'] as List)
            .map(
              (t) => PomodoroTag.fromJson(Map<String, dynamic>.from(t as Map)),
            )
            .toList();
        if (e.kind == 'focus') {
          screen = PomodoroDetailScreen(
            record: PomodoroRecord.fromJson(Map<String, dynamic>.from(row)),
            tags: recordTags,
          );
        } else {
          final raw = row['tag_uuids'];
          List<dynamic> tags = [];
          if (raw is String) {
            try {
              final decoded = jsonDecode(raw);
              if (decoded is List) tags = decoded;
            } catch (_) {}
          }
          screen = TimeLogDetailScreen(
            log: TimeLogItem.fromJson({
              ...row,
              'id': row['uuid'],
              'tag_uuids': tags,
            }),
            tags: recordTags,
          );
        }
        await Navigator.of(context)
            .push(PageTransitions.material(builder: (_) => screen));
      }
    } catch (e) {
      if (mounted) _notice(context, _message(e));
    } finally {
      opening = false;
      if (mounted && foreground) await load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final focusFilters = [
      PlanReviewFilter.focus,
      PlanReviewFilter.linked,
      PlanReviewFilter.unlinked,
      PlanReviewFilter.attribution,
    ];
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title ?? _label(widget.filter)),
        actions: [
          IconButton(
            tooltip: '统计口径',
            onPressed: () => _scope(context),
            icon: const Icon(Icons.info_outline),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: load,
        child: ListView(
          key: PageStorageKey('review-detail-${widget.filter.name}'),
          padding: const EdgeInsets.all(16),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 900),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      widget.cumulative
                          ? '累计有效记录 · 按唯一规划关联'
                          : '${DateFormat('yyyy/M/d').format(widget.start)} — ${DateFormat('yyyy/M/d').format(DateTime(widget.end.year, widget.end.month, widget.end.day - 1))}',
                    ),
                    if (focusFilters.contains(widget.filter))
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          children: focusFilters
                              .map(
                                (f) => ChoiceChip(
                                  label: Text(_label(f)),
                                  selected: _filter == f,
                                  onSelected: (_) {
                                    setState(() => _filter = f);
                                    unawaited(load());
                                  },
                                ),
                              )
                              .toList(),
                        ),
                      ),
                    if (_page != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Text(
                          _filter == PlanReviewFilter.issues
                              ? '${_page!.total}项需要核对'
                              : '${_page!.total}项 · ${reviewDuration(_page!.seconds)}',
                          style: theme.textTheme.titleLarge,
                        ),
                      ),
                    if (widget.filter == PlanReviewFilter.logs)
                      const Text('日志记录时长可能重叠，未与专注相加。'),
                    if (focusFilters.contains(widget.filter))
                      const Text('按记录开始日统计 · 跨午夜仅计一次'),
                    if (_error != null)
                      _ReviewError(error: _error!, retry: load),
                    if (!_loading && _error == null && _rows.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(32),
                        child: Text('当前筛选没有记录'),
                      ),
                    ..._rows.map(
                      (e) => Card(
                        margin: const EdgeInsets.symmetric(vertical: 5),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              InkWell(
                                key: ValueKey('review-entry-${e.kind}-${e.id}'),
                                onTap: () => _openEntry(e),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 4,
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        e.title,
                                        style: theme.textTheme.titleMedium,
                                      ),
                                      const SizedBox(height: 4),
                                      Text(_period(e)),
                                      Text(
                                        '${e.kind == 'plan'
                                            ? '计划'
                                            : e.kind == 'log'
                                            ? '日志'
                                            : '专注'} ${reviewDuration(e.seconds)}${e.reason.isEmpty ? '' : ' · ${e.reason}'}',
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              if (e.kind == 'plan' && e.values['status'] == 6)
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: TextButton(
                                    key: ValueKey(
                                      'plan-stats-all-recover-${e.id}',
                                    ),
                                    onPressed: () => _recover(e),
                                    child: const Text('重新安排'),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    if (_loading)
                      const Padding(
                        padding: EdgeInsets.all(24),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    else if (_error == null && _page?.next != null)
                      TextButton(
                        key: const ValueKey('review-load-more'),
                        onPressed: () => load(more: true),
                        child: const Text('加载更多'),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _status(Object? value) => switch (value) {
  0 => '待执行',
  1 => '已完成',
  2 => '已延后',
  3 => '已取消',
  4 => '已提醒',
  5 => '专注中',
  6 => '漏做',
  7 => '已跳过',
  _ => '待核对',
};
void _notice(BuildContext context, String message) =>
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
Future<void> _scope(BuildContext context) => showAppDialog<void>(
  context: context,
  builder: (context) => AlertDialog(
    scrollable: true,
    title: const Text('统计口径'),
    content: const Text(_scopeText),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('知道了'),
      ),
    ],
  ),
);

class _ReviewError extends StatelessWidget {
  const _ReviewError({required this.error, required this.retry});
  final String error;
  final Future<void> Function() retry;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 24),
    child: Column(
      children: [
        Icon(
          Icons.cloud_off_outlined,
          color: Theme.of(context).colorScheme.error,
        ),
        const SizedBox(height: 12),
        const Text('统计未能完成'),
        Text(error, textAlign: TextAlign.center),
        TextButton(onPressed: retry, child: const Text('重试')),
      ],
    ),
  );
}
