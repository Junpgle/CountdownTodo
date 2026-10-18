import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models.dart';
import '../storage_service.dart';
import '../services/database_helper.dart';
import '../services/plan_review_repository.dart';
import '../services/plan_today_maintenance.dart';
import '../services/plan_todo_guard.dart';
import '../services/pomodoro_service.dart';
import '../services/missed_plan_recovery_service.dart';
import '../screens/todo_plan_screen.dart';
import '../screens/plan_block_stats_screen.dart';
import '../utils/page_transitions.dart';
import 'optional_liquid_glass_surface.dart';
import 'missed_plan_recovery_flow.dart';
import 'plan_conflict_review.dart';
import 'plan_block_editor_sheet.dart';
import 'plan_manual_completion_host.dart';
import '../services/plan_manual_completion_service.dart';
import 'plan_day_overview.dart' show planOverviewDuration;
import '../services/home_agenda_repository.dart';
import '../services/device_calendar_read_service.dart';
import '../screens/course_screens.dart';
import '../screens/fixed_schedule_detail_screen.dart';
import '../screens/add_todo_screen.dart';
import '../utils/app_dialogs.dart';
import 'floating_glass_control.dart';
import 'home_agenda_card.dart';

final Map<(String?, String), DateFormat> _planTodayDateFormats = {};

DateFormat _planTodayDateFormat(String pattern) {
  final locale = Intl.defaultLocale;
  return _planTodayDateFormats.putIfAbsent(
    (locale, pattern),
    () => DateFormat(pattern, locale),
  );
}

/// Display reloads never trigger the legacy missed-state maintenance.
class PlanBlockTodaySection extends StatefulWidget {
  const PlanBlockTodaySection({
    super.key,
    required this.username,
    this.isLight = false,
    this.refreshTrigger = 0,
    this.onTap,
    this.chartKey,
    this.enabled = true,
    this.repository,
    this.clock,
    this.maintain,
    this.unifiedAgenda = false,
    this.includeSchedules = true,
    this.includePlans = true,
    this.todos = const [],
    this.agendaRepository,
    this.onTodoAdded,
  });
  final String username;
  final bool isLight, enabled;
  final int refreshTrigger;
  final Function? onTap;
  final Key? chartKey;
  final PlanReviewRepository? repository;
  final DateTime Function()? clock;
  final Future<void> Function()? maintain;
  final bool unifiedAgenda, includeSchedules, includePlans;
  final List<TodoItem> todos;
  final HomeAgendaRepository? agendaRepository;
  final Future<void> Function(TodoItem)? onTodoAdded;
  @override
  State<PlanBlockTodaySection> createState() => _PlanBlockTodaySectionState();
}

class _PlanBlockTodaySectionState extends State<PlanBlockTodaySection>
    with WidgetsBindingObserver {
  final _manualHostKey = GlobalKey<PlanManualCompletionHostState>();
  late PlanReviewRepository _repository;
  late HomeAgendaRepository _agendaRepository;
  HomeAgendaSnapshot? _agenda;
  Duration _agendaDuration = const Duration(milliseconds: 500);
  PlanTodayCard? _data;
  PlanTodoIdentity? _identity;
  Timer? _wake;
  StreamSubscription<PomodoroRunState?>? _focus;
  String? _expandedBlockId, _error;
  bool _loading = false, _opening = false, _foreground = true;
  bool _visible = false, _ticker = true, _maintenancePending = true;
  bool _maintenanceRunning = false;
  bool _collapsed = false;
  int _collapseRevision = 0;
  int _sequence = 0;
  final _issuesKey = GlobalKey(debugLabel: 'agenda_issues_button');
  final _unlinkedKey = GlobalKey(debugLabel: 'agenda_unlinked_button');
  DateTime? _expiredBoundary;
  DateTime get _now => widget.clock?.call() ?? DateTime.now();
  DateTime get _today => DateUtils.dateOnly(_now);
  bool get _active => _foreground && _visible && _ticker && widget.enabled;
  bool get _canOpen =>
      _active && !_loading && !_opening && _data != null && _error == null;

  @override
  void initState() {
    super.initState();
    _repository =
        widget.repository ??
        widget.agendaRepository?.plans ??
        PlanReviewRepository(clock: widget.clock);
    _agendaRepository =
        widget.agendaRepository ?? HomeAgendaRepository(plans: _repository);
    unawaited(_readCollapsed());
    WidgetsBinding.instance.addObserver(this);
    StorageService.scopedDataRefreshNotifier.addListener(_onSignal);
    if (widget.unifiedAgenda) {
      DeviceCalendarReadService.revision.addListener(_onCalendarRevision);
    }
    _focus = PomodoroService.onRunStateChanged.listen((_) {
      if (_active && !_opening && !_maintenanceRunning) {
        unawaited(
          _load(
            onlySources: widget.unifiedAgenda
                ? const <HomeAgendaSource>{HomeAgendaSource.plans}
                : null,
          ),
        );
      }
    });
  }

  Future<void> _readCollapsed() async {
    final revision = ++_collapseRevision;
    final username = widget.username;
    final prefs = await SharedPreferences.getInstance();
    if (!mounted ||
        revision != _collapseRevision ||
        username != widget.username) {
      return;
    }
    setState(() {
      _collapsed =
          (widget.unifiedAgenda
              ? prefs.getBool('home_agenda_collapsed_$username')
              : null) ??
          prefs.getBool('plan_today_collapsed_$username') ??
          false;
      _agendaDuration = (prefs.getBool('enable_animations') ?? true)
          ? Duration(
              milliseconds: (prefs.getInt('animation_duration') ?? 500).clamp(
                0,
                1 << 31,
              ),
            )
          : Duration.zero;
    });
  }

  Future<void> _toggleCollapsed() async {
    ++_collapseRevision;
    final username = widget.username;
    final collapsed = !_collapsed;
    setState(() => _collapsed = collapsed);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(
      '${widget.unifiedAgenda ? 'home_agenda' : 'plan_today'}_collapsed_$username',
      collapsed,
    );
  }

  void _invalidate({bool clear = false}) {
    ++_sequence;
    _wake?.cancel();
    _loading = false;
    if (clear) {
      _data = null;
      _identity = null;
      _expandedBlockId = null;
      _error = null;
      _agenda = null;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final visible = ModalRoute.of(context)?.isCurrent ?? true;
    final ticker = TickerMode.valuesOf(context).enabled;
    if (_visible != visible || _ticker != ticker) {
      _visible = visible;
      _ticker = ticker;
      _invalidate();
      if (_active && !_opening) unawaited(_load());
    }
  }

  @override
  void didUpdateWidget(covariant PlanBlockTodaySection old) {
    super.didUpdateWidget(old);
    if (old.username != widget.username) {
      _collapsed = false;
      unawaited(_readCollapsed());
    }
    final todosChanged = widget.unifiedAgenda && old.todos != widget.todos;
    final changed =
        old.username != widget.username ||
        old.repository != widget.repository ||
        old.agendaRepository != widget.agendaRepository ||
        old.includePlans != widget.includePlans ||
        old.includeSchedules != widget.includeSchedules;
    if (changed ||
        old.refreshTrigger != widget.refreshTrigger ||
        old.enabled != widget.enabled ||
        old.clock != widget.clock ||
        todosChanged) {
      _invalidate(clear: changed);
      if (changed) {
        _repository =
            widget.repository ??
            widget.agendaRepository?.plans ??
            PlanReviewRepository(clock: widget.clock);
        _agendaRepository =
            widget.agendaRepository ?? HomeAgendaRepository(plans: _repository);
      }
      if (changed || old.refreshTrigger != widget.refreshTrigger) {
        _maintenancePending = true;
      }
      if (_active && !_opening) {
        final refreshTriggerChanged =
            old.refreshTrigger != widget.refreshTrigger;
        final onlySources =
            widget.unifiedAgenda &&
                !changed &&
                old.enabled == widget.enabled &&
                old.clock == widget.clock
            ? <HomeAgendaSource>{
                if (todosChanged || refreshTriggerChanged)
                  HomeAgendaSource.plans,
                if (refreshTriggerChanged) HomeAgendaSource.courses,
                if (refreshTriggerChanged) HomeAgendaSource.fixed,
              }
            : null;
        unawaited(_load(onlySources: onlySources));
      }
    }
  }

  void _onSignal() {
    final signal = StorageService.scopedDataRefreshNotifier.value;
    if (signal.affects(DataRefreshDomain.pomodoro)) {
      _maintenancePending = true;
    }
    final refreshesPlans =
        signal.affects(DataRefreshDomain.todos) ||
        signal.affects(DataRefreshDomain.planBlocks) ||
        signal.affects(DataRefreshDomain.pomodoro) ||
        signal.affects(DataRefreshDomain.timeLogs);
    final refreshesCourses =
        widget.unifiedAgenda && signal.affects(DataRefreshDomain.courses);
    final refreshesFixed =
        widget.unifiedAgenda &&
        signal.affects(DataRefreshDomain.fixedSchedules);
    if (!(signal.affects(DataRefreshDomain.all) ||
        refreshesPlans ||
        refreshesCourses ||
        refreshesFixed)) {
      return;
    }
    if (_maintenanceRunning &&
        !signal.domains.contains(DataRefreshDomain.all)) {
      return;
    }
    final fullRefresh = signal.domains.contains(DataRefreshDomain.all);
    final onlySources = widget.unifiedAgenda && !fullRefresh
        ? <HomeAgendaSource>{
            if (refreshesPlans) HomeAgendaSource.plans,
            if (refreshesCourses) HomeAgendaSource.courses,
            if (refreshesFixed) HomeAgendaSource.fixed,
          }
        : null;
    _invalidate(clear: fullRefresh);
    if (mounted) setState(() {});
    if (_active && !_opening) {
      unawaited(_load(onlySources: onlySources));
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    // Keep the last readable snapshot while the window is inactive. Resume
    // with a refresh, but do not replace the visible card with an empty glass
    // shell while the app is unfocused or waiting for data.
    _invalidate();
    if (mounted) setState(() {});
    if (_active && !_opening) unawaited(_load());
  }

  @override
  void dispose() {
    _invalidate();
    _focus?.cancel();
    StorageService.scopedDataRefreshNotifier.removeListener(_onSignal);
    if (widget.unifiedAgenda) {
      DeviceCalendarReadService.revision.removeListener(_onCalendarRevision);
    }
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _onCalendarRevision() {
    if (_active && !_opening && widget.includeSchedules) {
      unawaited(_load(onlySources: {HomeAgendaSource.calendar}));
    }
  }

  Future<void> _load({Set<HomeAgendaSource>? onlySources}) async {
    if (!_active || _opening || _maintenanceRunning) return;
    final request = ++_sequence, day = _today;
    final username = widget.username;
    _wake?.cancel();
    setState(() {
      if (_data?.overview.start != day) {
        _data = null;
        _expandedBlockId = null;
        if (_agenda?.day != day) _agenda = null;
      }
      _loading = true;
      _error = null;
    });
    try {
      await _identity?.check();
      String? maintenanceError;
      if (_maintenancePending &&
          (!widget.unifiedAgenda || widget.includePlans)) {
        _maintenancePending = false;
        _maintenanceRunning = true;
        try {
          await (widget.maintain?.call() ??
              const PlanTodayMaintenance().run(username, _now));
        } catch (error) {
          if (!widget.unifiedAgenda) rethrow;
          maintenanceError = '$error';
        } finally {
          _maintenanceRunning = false;
        }
      }
      if (!mounted || !_active) return;
      if (request != _sequence || _today != day) {
        unawaited(_load());
        return;
      }
      if (widget.unifiedAgenda) {
        final agenda = await _agendaRepository.read(
          username,
          now: _now,
          todos: widget.todos,
          includeSchedules: widget.includeSchedules,
          includePlans: widget.includePlans,
          previous: _agenda,
          only: onlySources,
          planningError: maintenanceError,
        );
        await agenda.identity.check();
        await _identity?.check();
        if (!mounted || request != _sequence || !_active) return;
        if (agenda.day != _today) {
          _invalidate(clear: true);
          unawaited(_load());
          return;
        }
        setState(() {
          _agenda = agenda;
          _identity = agenda.identity;
          _data = agenda.plans?.card;
          _loading = false;
          if (!agenda.items.any((i) => i.plan?.entry.id == _expandedBlockId)) {
            _expandedBlockId = null;
          }
        });
        _schedule(agenda.nextBoundary);
        return;
      }
      final data = await _repository.readTodayCard(username);
      await data.overview.identity.check();
      await _identity?.check();
      if (!mounted || request != _sequence || !_active) return;
      if (data.overview.start != day ||
          _today != day ||
          data.overview.identity.username != username) {
        _invalidate(clear: true);
        unawaited(_load());
        return;
      }
      setState(() {
        _identity = data.overview.identity;
        _data = data;
        _loading = false;
        if (!data.rows.any((r) => r.entry.id == _expandedBlockId)) {
          _expandedBlockId = null;
        }
      });
      _schedule(data.nextBoundary);
    } catch (error) {
      if (mounted && request == _sequence && _active) {
        setState(() {
          _loading = false;
          _data = null;
          _identity = null;
          _expandedBlockId = null;
          _error = '$error';
          _agenda = null;
        });
      }
    } finally {
      if (mounted &&
          request != _sequence &&
          _active &&
          !_loading &&
          !_opening &&
          !_maintenanceRunning &&
          _error == null &&
          (widget.unifiedAgenda
              ? (_agenda == null || _agenda!.day != _today)
              : (_data == null || _data!.overview.start != _today))) {
        scheduleMicrotask(_load);
      }
    }
  }

  void _schedule(DateTime boundary) {
    if (!_active || _opening) return;
    final delay = boundary.difference(_now), expired = !boundary.isAfter(_now);
    if (expired && _expiredBoundary == boundary) return;
    _expiredBoundary = expired ? boundary : null;
    _wake = Timer(expired ? Duration.zero : delay, () {
      if (_active && (ModalRoute.of(context)?.isCurrent ?? true)) {
        unawaited(
          _load(
            onlySources: widget.unifiedAgenda
                ? const <HomeAgendaSource>{HomeAgendaSource.plans}
                : null,
          ),
        );
      }
    });
  }

  Future<void> _navigate(
    Future<void> Function(PlanTodayCard data) action, {
    bool preserveOnError = false,
  }) async {
    if (!_canOpen) return;
    final data = _data!, request = ++_sequence;
    var failed = false;
    _wake?.cancel();
    setState(() => _opening = true);
    try {
      await data.overview.identity.check();
      if (!mounted ||
          request != _sequence ||
          !_active ||
          _today != data.overview.start) {
        return;
      }
      await action(data);
    } catch (error) {
      failed = true;
      if (mounted) {
        if (preserveOnError) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('$error')),
          );
        } else {
          setState(() {
            _data = null;
            _identity = null;
            _error = '$error';
          });
        }
      }
    } finally {
      if (mounted) {
        setState(() => _opening = false);
        if (_active && (!failed || preserveOnError)) unawaited(_load());
      }
    }
  }

  Future<void> _review([
    PlanReviewFilter? filter,
    String? planId,
    GlobalKey? sourceKey,
  ]) => _navigate((data) async {
    final page = filter == null
        ? PlanBlockStatsScreen(
            username: widget.username,
            repository: _repository,
            initialDate: data.overview.start,
            clock: widget.clock,
          )
        : PlanReviewDetailScreen(
            username: widget.username,
            repository: _repository,
            identity: data.overview.identity,
            start: data.overview.start,
            end: data.overview.end,
            filter: filter,
            planId: planId,
            title: planId == null ? null : '今日记录投入',
            clock: widget.clock,
          );
    if (sourceKey != null) {
      await PageTransitions.pushFromRect(
        context: context,
        page: page,
        sourceKey: sourceKey,
        placeholderIcon: filter == null
            ? Icons.insights_outlined
            : Icons.timer_outlined,
      );
    } else {
      await Navigator.of(context)
          .push<void>(PageTransitions.material(builder: (_) => page));
    }
  });
  Future<void> _invokeOnTap([GlobalKey? sourceKey]) async {
    final callback = widget.onTap;
    if (callback == null) return;
    if (callback is FutureOr<void> Function(GlobalKey?)) {
      await callback(sourceKey);
    } else if (callback is FutureOr<void> Function()) {
      await callback();
    } else {
      try {
        await (callback as dynamic)(sourceKey);
      } catch (_) {
        await (callback as dynamic)();
      }
    }
  }

  void _calendar([GlobalKey? sourceKey]) {
    if (!_canOpen) return;
    unawaited(
      _navigate((data) async {
        if (widget.onTap != null) {
          await _invokeOnTap(sourceKey);
        } else {
          final page = TodoPlanScreen(
            username: widget.username,
            initialDate: data.overview.start,
          );
          if (sourceKey != null) {
            await PageTransitions.pushFromRect(
              context: context,
              page: page,
              sourceKey: sourceKey,
              placeholderIcon: Icons.calendar_month_rounded,
            );
          } else {
            await Navigator.of(context)
                .push(PageTransitions.material(builder: (_) => page));
          }
        }
      }),
    );
  }

  Future<void> _edit(PlanTodayRow item) => _navigate((data) async {
    final raw = await _repository.detail(
      data.overview.identity,
      'plan',
      item.entry.id,
    );
    if (raw['review_valid'] != true ||
        raw['status'] is! int ||
        (raw['status'] as int) < 0 ||
        (raw['status'] as int) >= TodoPlanStatus.values.length ||
        ![0, 5, 10, 15, 30].contains(raw['reminder_minutes']) ||
        ![15, 20, 25, 30, 45, 60].contains(raw['pomodoro_minutes']) ||
        raw['pomodoro_rounds'] is! int ||
        (raw['pomodoro_rounds'] as int) < 0 ||
        (raw['pomodoro_rounds'] as int) > 6) {
      throw StateError('规划已变化或需核对，请刷新后查看');
    }
    final block = TodoPlanBlock.fromJson(raw);
    final db = await DatabaseHelper.instance.databaseForUser(widget.username);
    final rows = await PlanTodoGuard.projectedRows(
      db,
      data.overview.identity,
      block.todoId,
    );
    if (rows.isEmpty) throw StateError('关联待办已不存在，请在投入明细查看历史');
    final todo = TodoItem.fromSql({
      ...rows.single,
      'is_completed': rows.single['member_completed'],
    })..id = block.todoId;
    final todos = await StorageService.getTodos(widget.username);
    final groups = await StorageService.getTodoGroups(widget.username);
    await data.overview.identity.check();
    if (!mounted || !_active || _today != data.overview.start) return;
    await showPlanBlockEditorSheet<void>(
      context: context,
      builder: (_) => PlanBlockEditorSheet(
        block: block,
        username: widget.username,
        todos: [
          for (final t in todos)
            if (t.id != todo.id) t,
          todo,
        ],
        todoGroups: groups,
        startTime: DateTime.fromMillisecondsSinceEpoch(block.startTime),
        endTime: DateTime.fromMillisecondsSinceEpoch(block.endTime),
        clock: widget.clock,
        onSaved: () => _maintenancePending = true,
        manualCompletionService: PlanManualCompletionService(
          clock: widget.clock,
        ),
        onManualCompleted: (receipt) =>
            _manualHostKey.currentState?.present(receipt),
      ),
    );
  });
  Future<void> _recover(PlanTodayRow row) => _navigate(
    (_) => showMissedPlanRecovery(
      context: context,
      username: widget.username,
      sourceId: row.entry.id,
      service: MissedPlanRecoveryService(clock: widget.clock),
      onSaved: () => _maintenancePending = true,
    ),
  );

  bool get _canAgendaOpen =>
      _active && !_loading && !_opening && _agenda != null && _error == null;

  Future<void> _agendaNavigate(Future<void> Function() action) async {
    if (!_canAgendaOpen) return;
    final snapshot = _agenda!, request = ++_sequence;
    _wake?.cancel();
    setState(() => _opening = true);
    try {
      await snapshot.identity.check();
      if (!mounted ||
          request != _sequence ||
          !_active ||
          snapshot.day != _today) {
        return;
      }
      await action();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$error')));
      }
    } finally {
      if (mounted) {
        setState(() => _opening = false);
        if (_active) unawaited(_load());
      }
    }
  }

  void _agendaCalendar({bool tomorrow = false, GlobalKey? sourceKey}) {
    final day = _today;
    unawaited(
      _agendaNavigate(() async {
        if (!tomorrow && widget.onTap != null) {
          await _invokeOnTap(sourceKey);
          return;
        }
        final page = TodoPlanScreen(
          username: widget.username,
          initialDate: tomorrow
              ? DateTime(day.year, day.month, day.day + 1)
              : day,
        );
        if (sourceKey != null) {
          await PageTransitions.pushFromRect(
            context: context,
            page: page,
            sourceKey: sourceKey,
            placeholderIcon: Icons.calendar_month_rounded,
          );
        } else {
          await Navigator.of(context)
              .push(PageTransitions.material(builder: (_) => page));
        }
      }),
    );
  }

  void _agendaItem(HomeAgendaItem item, [GlobalKey? cardKey]) {
    if (!_canAgendaOpen) return;
    if (item.plan != null) {
      setState(
        () => _expandedBlockId = _expandedBlockId == item.plan!.entry.id
            ? null
            : item.plan!.entry.id,
      );
      return;
    }
    unawaited(
      _agendaNavigate(() async {
        final Widget page;
        IconData placeholder = Icons.event_note_rounded;
        if (item.course != null) {
          page = CourseDetailScreen(course: item.course!);
          placeholder = Icons.school_rounded;
        } else if (item.fixed != null) {
          page = FixedScheduleDetailScreen(
            username: widget.username,
            item: item.fixed!,
          );
          placeholder = Icons.event_available_rounded;
        } else if (item.calendar != null) {
          page = DeviceCalendarEventDetailScreen(event: item.calendar!);
          placeholder = Icons.event_note_rounded;
        } else {
          page = TodoDetailScreen(todo: item.todo!);
          placeholder = Icons.check_circle_outline_rounded;
        }
        if (cardKey != null) {
          await PageTransitions.pushFromRect(
            context: context,
            page: page,
            sourceKey: cardKey,
            sourceBorderRadius: const BorderRadius.all(Radius.circular(14)),
            placeholderIcon: placeholder,
          );
        } else {
          await Navigator.of(context)
              .push(PageTransitions.material(builder: (_) => page));
        }
      }),
    );
  }

  void _agendaAdd([GlobalKey? sourceKey]) {
    final snapshot = _agenda!;
    unawaited(
      _agendaNavigate(() async {
        final action = await showAppModalBottomSheet<String>(
          context: context,
          showDragHandle: true,
          builder: (context) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.event_available_outlined),
                  title: const Text('新增固定日程'),
                  subtitle: const Text('考试、会议、预约等事项'),
                  onTap: () => Navigator.pop(context, 'fixed'),
                ),
                ListTile(
                  leading: const Icon(Icons.view_week_outlined),
                  title: const Text('安排待办时间'),
                  onTap: () => Navigator.pop(context, 'plan'),
                ),
              ],
            ),
          ),
        );
        if (!mounted || action == null) return;
        // The menu temporarily makes this route non-current; check the captured
        // account directly before acting on the selection.
        await snapshot.identity.check();
        if (!mounted || snapshot.day != _today) return;
        if (action == 'plan') {
          final page = TodoPlanScreen(
            username: widget.username,
            initialDate: _today,
          );
          if (sourceKey != null) {
            await PageTransitions.pushFromRect(
              context: context,
              page: page,
              sourceKey: sourceKey,
              placeholderIcon: Icons.calendar_month_rounded,
            );
          } else {
            await Navigator.of(context)
                .push(PageTransitions.material(builder: (_) => page));
          }
        } else if (action == 'fixed') {
          final page = AddTodoScreen(
            initialMode: AddTodoInitialMode.fixedSchedule,
            onTodoAdded: widget.onTodoAdded ?? (_) async {},
            onFixedScheduleAdded: (item) =>
                StorageService.saveFixedSchedules(widget.username, [item]),
          );
          if (sourceKey != null) {
            await PageTransitions.pushFromRect(
              context: context,
              page: page,
              sourceKey: sourceKey,
              placeholderIcon: Icons.add_task_rounded,
            );
          } else {
            await Navigator.of(context)
                .push(PageTransitions.material(builder: (_) => page));
          }
        }
        _maintenancePending = true;
      }),
    );
  }

  bool _canMarkAgendaPlanCompleted(PlanTodayRow row) {
    if (row.entry.end <= 0 ||
        row.entry.end > _now.millisecondsSinceEpoch ||
        row.entry.id.startsWith('mapped_') ||
        row.status < 0 ||
        row.status >= TodoPlanStatus.values.length) {
      return false;
    }
    return const {
      TodoPlanStatus.planned,
      TodoPlanStatus.reminded,
      TodoPlanStatus.delayed,
      TodoPlanStatus.missed,
    }.contains(TodoPlanStatus.values[row.status]);
  }

  Future<void> _confirmAgendaPlanCompleted(PlanTodayRow row) => _navigate((
    data,
  ) async {
    final route = ModalRoute.of(context);
    final service = PlanManualCompletionService(clock: widget.clock);
    final request = await service.prepare(widget.username, row.entry.id);
    if (!mounted || !_active || route?.isCurrent == false) return;

    final block = request.block;
    final format = _planTodayDateFormat('M月d日 HH:mm');
    var saving = false;
    String? saveError;
    final confirmedReceipt = await showAppDialog<PlanManualCompletionReceipt>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('确认这次规划已完成？'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  block.titleSnapshot?.trim().isNotEmpty == true
                      ? block.titleSnapshot!
                      : '这次规划',
                ),
                const SizedBox(height: 8),
                Text(
                  '${format.format(DateTime.fromMillisecondsSinceEpoch(block.startTime))} — ${format.format(DateTime.fromMillisecondsSinceEpoch(block.endTime))}',
                ),
                const SizedBox(height: 16),
                const Text(
                  '仅将这次规划标为已完成。不会改变待办完成状态、停止专注计时或新增专注记录。',
                ),
                if (saveError != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    '标记未成功：$saveError',
                    style: TextStyle(
                      color: Theme.of(dialogContext).colorScheme.error,
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: saving ? null : () => Navigator.pop(dialogContext),
              child: const Text('返回核对'),
            ),
            FilledButton(
              key: ValueKey('plan-manual-confirm-agenda-${row.entry.id}'),
              onPressed: saving
                  ? null
                  : () async {
                      setDialogState(() {
                        saving = true;
                        saveError = null;
                      });
                      PlanManualCompletionReceipt? receipt;
                      try {
                        await data.overview.identity.check();
                        receipt = await service.confirm(request);
                        await receipt.identity.check();
                        await service.ensureCompleted(receipt);
                        if (!dialogContext.mounted) {
                          receipt.invalidate();
                          return;
                        }
                        Navigator.pop(dialogContext, receipt);
                      } catch (error) {
                        receipt?.invalidate();
                        if (dialogContext.mounted) {
                          setDialogState(() {
                            saving = false;
                            saveError = '$error';
                          });
                        }
                      }
                    },
              child: saving
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('确认完成'),
            ),
          ],
        ),
      ),
      barrierDismissible: false,
    );
    if (confirmedReceipt == null ||
        !mounted ||
        !_active ||
        route?.isCurrent == false) {
      confirmedReceipt?.invalidate();
      return;
    }
    _maintenancePending = true;
    _manualHostKey.currentState?.present(confirmedReceipt);
  }, preserveOnError: true);

  Widget _agendaPlanActions(PlanTodayRow row, [GlobalKey? cardKey]) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        '今日已核实投入 ${planOverviewDuration(row.focusSeconds)}',
        style: Theme.of(context).textTheme.bodySmall,
      ),
      Wrap(
        spacing: 4,
        children: [
          TextButton(
            key: ValueKey('plan-today-edit-${row.entry.id}'),
            onPressed: _canOpen ? () => _edit(row) : null,
            child: const Text('查看规划'),
          ),
          TextButton(
            key: ValueKey('plan-today-focus-${row.entry.id}'),
            onPressed: _canOpen
                ? () => _review(PlanReviewFilter.focus, row.entry.id, cardKey)
                : null,
            child: const Text('投入明细'),
          ),
          if (_canMarkAgendaPlanCompleted(row))
            FilledButton.tonalIcon(
              key: ValueKey('plan-today-complete-${row.entry.id}'),
              onPressed: _active
                  ? () => _openAgendaPlanCompletion(row)
                  : null,
              icon: const Icon(Icons.check_circle_outline),
              label: const Text('标记为已完成'),
            ),
          if (row.status == TodoPlanStatus.missed.index)
            TextButton.icon(
              key: ValueKey('plan-today-recover-${row.entry.id}'),
              onPressed: _canOpen ? () => _recover(row) : null,
              icon: const Icon(Icons.event_repeat),
              label: const Text('重新安排'),
            ),
        ],
      ),
    ],
  );

  void _openAgendaPlanCompletion(PlanTodayRow row) {
    if (!_active) return;
    if (!_canOpen) {
      final message = _loading
          ? '今日规划正在更新，请稍后再试'
          : _opening
          ? '今日安排正在处理其他操作，请稍后再试'
          : _error != null
          ? '今日规划读取失败：$_error'
          : '今日规划尚未就绪，正在重新读取';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
      if (!_loading && !_opening) unawaited(_load());
      return;
    }
    unawaited(_confirmAgendaPlanCompleted(row));
  }

  Widget _buildAgenda() {
    final overview = _data?.overview;
    return PlanManualCompletionHost(
      key: _manualHostKey,
      enabled: _active,
      onRefresh: () => unawaited(_load()),
      child: HomeAgendaCard(
        isLight: widget.isLight,
        isForeground: _foreground,
        snapshot: _agenda,
        collapsed: _collapsed,
        loading: _loading,
        enabled: _canAgendaOpen,
        retryEnabled: _active && !_loading && !_opening,
        showPlans: widget.includePlans,
        duration: _agendaDuration,
        onCollapse: _toggleCollapsed,
        onStats: _canOpen
            ? ([sourceKey]) => _review(null, null, sourceKey)
            : null,
        onAll: ([sourceKey]) => _agendaCalendar(sourceKey: sourceKey),
        onTomorrow: ([sourceKey]) =>
            _agendaCalendar(tomorrow: true, sourceKey: sourceKey),
        onAdd: ([sourceKey]) => _agendaAdd(sourceKey),
        onItem: (item, [cardKey]) => _agendaItem(item, cardKey),
        onRetry: (source) =>
            unawaited(_load(onlySources: source == null ? null : {source})),
        planActions: _agendaPlanActions,
        expandedPlanId: _expandedBlockId,
        chartKey: widget.chartKey,
        error: _error,
        extra: overview == null
            ? null
            : IgnorePointer(
                ignoring: !_canOpen,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    PlanConflictIndicator(
                      enabled: _active && !_opening && widget.includePlans,
                      retainResultOnRefresh: true,
                      username: widget.username,
                      date: overview.start,
                      refreshTrigger: widget.refreshTrigger,
                      onSaved: () {
                        _maintenancePending = true;
                        unawaited(_load());
                      },
                    ),
                    if (overview.issues > 0)
                      SizedBox(
                        key: _issuesKey,
                        child: TextButton(
                          onPressed: _canOpen
                              ? () => _review(
                                  PlanReviewFilter.issues,
                                  null,
                                  _issuesKey,
                                )
                              : null,
                          child: const Text('记录待核对'),
                        ),
                      ),
                    if (overview.actual('unlinkedN') > 0)
                      SizedBox(
                        key: _unlinkedKey,
                        child: TextButton(
                          onPressed: _canOpen
                              ? () => _review(
                                  PlanReviewFilter.unlinked,
                                  null,
                                  _unlinkedKey,
                                )
                              : null,
                          child: Text(
                            '未关联规划的专注 · ${planOverviewDuration(overview.actual('unlinked'))}',
                          ),
                        ),
                      ),
                  ],
                ),
              ),
      ),
    );
  }

  String _status(PlanTodayRow row) {
    if (row.status == TodoPlanStatus.finished.index) return '已完成';
    if (row.status == TodoPlanStatus.focusing.index) return '正在专注';
    if (row.status == TodoPlanStatus.missed.index) {
      return row.entry.end <= _now.millisecondsSinceEpoch ? '漏做' : '状态待核对';
    }
    if (row.entry.end <= _now.millisecondsSinceEpoch) return '已结束待确认';
    if (row.entry.start <= _now.millisecondsSinceEpoch) return '时段进行中';
    return '未开始';
  }

  String _range(PlanReviewEntry entry) {
    final a = DateTime.fromMillisecondsSinceEpoch(entry.start);
    final b = DateTime.fromMillisecondsSinceEpoch(entry.end);
    final pattern = DateUtils.isSameDay(a, b) ? 'HH:mm' : 'MM-dd HH:mm';
    final dateFormat = _planTodayDateFormat(pattern);
    return '${dateFormat.format(a)}–${dateFormat.format(b)}';
  }

  Widget _metrics(double width, PlanReviewOverview data) {
    final theme = Theme.of(context), labels = ['计划', '已结束完成', '有效专注'];
    final done = data.plan('done'), ended = data.plan('ended');
    final values = [
      planOverviewDuration(data.plan('seconds')),
      ended == 0 ? '暂无' : '$done/$ended',
      planOverviewDuration(data.actual('seconds')),
    ];
    final filters = [
      PlanReviewFilter.plans,
      PlanReviewFilter.ended,
      PlanReviewFilter.focus,
    ];
    final valueStyle = theme.textTheme.titleMedium!.copyWith(
      fontWeight: FontWeight.w600,
      color: theme.colorScheme.onSurface,
    );
    final labelStyle = theme.textTheme.labelSmall!.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    double measure(String text, TextStyle style) {
      final painter = TextPainter(
        text: TextSpan(text: text, style: style),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
      )..layout();
      return painter.width;
    }

    final fits = List.generate(
      3,
      (i) =>
          measure(values[i], valueStyle) + 16 <= width / 3 &&
          measure(labels[i], labelStyle) + 16 <= width / 3,
    ).every((v) => v);
    if (!fits) {
      return TextButton.icon(
        onPressed: _canOpen ? () => _review() : null,
        icon: const Icon(Icons.insights_outlined),
        label: const Text('查看今日概览'),
      );
    }
    return Container(
      margin: const EdgeInsets.only(top: 4, bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: List.generate(
          3,
          (i) => Expanded(
            child: Semantics(
              label: '${labels[i]}，${values[i]}',
              button: true,
              excludeSemantics: true,
              onTap: _canOpen ? () => _review(filters[i]) : null,
              child: InkWell(
                onTap: _canOpen ? () => _review(filters[i]) : null,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(values[i], style: valueStyle),
                      Text(labels[i], style: labelStyle),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _row(PlanTodayRow row) {
    final e = row.entry, colors = Theme.of(context).colorScheme;
    final expanded = _expandedBlockId == e.id;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          key: ValueKey('plan-today-row-${e.id}'),
          onTap: _canOpen
              ? () => setState(() => _expandedBlockId = expanded ? null : e.id)
              : null,
          borderRadius: BorderRadius.circular(10),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 4),
              child: Row(
                children: [
                  Container(
                    width: 3,
                    height: 28,
                    margin: const EdgeInsets.only(right: 10),
                    decoration: BoxDecoration(
                      color: row.status == TodoPlanStatus.missed.index
                          ? colors.error.withValues(alpha: 0.7)
                          : row.status == TodoPlanStatus.finished.index
                          ? colors.outlineVariant
                          : colors.primary.withValues(alpha: 0.7),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          e.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                        Wrap(
                          spacing: 10,
                          children: [
                            Text(
                              _range(e),
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            Text(
                              _status(row),
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color:
                                        row.status ==
                                            TodoPlanStatus.missed.index
                                        ? colors.error
                                        : colors.primary,
                                  ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    expanded
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                    size: 18,
                    color: colors.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          alignment: Alignment.topCenter,
          child: expanded
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '今日已核实投入 ${planOverviewDuration(row.focusSeconds)}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    Wrap(
                      spacing: 4,
                      children: [
                        TextButton(
                          key: ValueKey('plan-today-edit-${e.id}'),
                          onPressed: _canOpen ? () => _edit(row) : null,
                          child: const Text('查看规划'),
                        ),
                        TextButton(
                          key: ValueKey('plan-today-focus-${e.id}'),
                          onPressed: _canOpen
                              ? () => _review(PlanReviewFilter.focus, e.id)
                              : null,
                          child: const Text('投入明细'),
                        ),
                        if (row.status == TodoPlanStatus.missed.index)
                          TextButton.icon(
                            key: ValueKey('plan-today-recover-${e.id}'),
                            onPressed: _canOpen ? () => _recover(row) : null,
                            icon: const Icon(Icons.event_repeat),
                            label: const Text('重新安排'),
                          ),
                      ],
                    ),
                  ],
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.unifiedAgenda) return _buildAgenda();
    final theme = Theme.of(context), colors = theme.colorScheme, data = _data;
    return PlanManualCompletionHost(
      key: _manualHostKey,
      enabled: _active,
      onRefresh: () => unawaited(_load()),
      child: GestureDetector(
        onTap: _canOpen ? _calendar : null,
        child: OptionalLiquidGlassCard(
          borderRadius: 18,
          highContrast: true,
          tint: colors.surface.withValues(alpha: 0.2),
          fallbackDecoration: BoxDecoration(
            color: widget.isLight
                ? colors.surfaceContainerLow.withValues(alpha: 0.98)
                : colors.surfaceContainerLow,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: colors.outlineVariant.withValues(alpha: 0.5),
            ),
          ),
          padding: EdgeInsets.fromLTRB(
            12,
            _collapsed ? 6 : 10,
            12,
            _collapsed ? 6 : 8,
          ),
          child: LayoutBuilder(
            builder: (context, constraints) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: colors.primaryContainer.withValues(alpha: 0.7),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        Icons.event_note_outlined,
                        size: 19,
                        color: colors.onPrimaryContainer,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: InkWell(
                        onTap: _toggleCollapsed,
                        borderRadius: BorderRadius.circular(8),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Text(
                            '今日规划',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (_loading)
                      const SizedBox(
                        key: ValueKey('plan-today-updating'),
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    SizedBox(
                      key: widget.chartKey,
                      child: IconButton(
                        constraints: const BoxConstraints.tightFor(
                          width: floatingGlassStandardControlSize,
                          height: floatingGlassStandardControlSize,
                        ),
                        visualDensity: VisualDensity.standard,
                        style: floatingGlassPlainIconButtonStyle(),
                        tooltip: '规划统计',
                        onPressed: _canOpen ? () => _review() : null,
                        icon: const Icon(Icons.insights_outlined, size: 20),
                      ),
                    ),
                    IconButton(
                      key: const ValueKey('plan-today-collapse'),
                      constraints: const BoxConstraints.tightFor(
                        width: floatingGlassStandardControlSize,
                        height: floatingGlassStandardControlSize,
                      ),
                      visualDensity: VisualDensity.standard,
                      style: floatingGlassPlainIconButtonStyle(),
                      tooltip: _collapsed ? '展开今日规划' : '收起今日规划',
                      onPressed: _toggleCollapsed,
                      icon: Icon(
                        _collapsed
                            ? Icons.expand_more_rounded
                            : Icons.expand_less_rounded,
                        size: 20,
                      ),
                    ),
                  ],
                ),
                AnimatedSize(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeInOutCubic,
                  alignment: Alignment.topCenter,
                  child: _collapsed
                      ? const SizedBox.shrink()
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (_error != null) ...[
                              Text(
                                '今日规划读取失败：$_error',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: colors.error,
                                ),
                              ),
                              Align(
                                alignment: Alignment.centerLeft,
                                child: TextButton(
                                  key: const ValueKey('plan-today-retry'),
                                  onPressed: _active ? () => _load() : null,
                                  child: const Text('重试'),
                                ),
                              ),
                            ] else if (data == null)
                              const SizedBox(
                                height: 70,
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: Text('正在读取今日规划…'),
                                ),
                              )
                            else ...[
                              _metrics(constraints.maxWidth, data.overview),
                              IgnorePointer(
                                ignoring: !_canOpen,
                                child: PlanConflictIndicator(
                                  enabled: _active && !_opening,
                                  retainResultOnRefresh: true,
                                  username: widget.username,
                                  date: data.overview.start,
                                  refreshTrigger: widget.refreshTrigger,
                                  onSaved: () {
                                    _maintenancePending = true;
                                    unawaited(_load());
                                  },
                                ),
                              ),
                              if (data.overview.issues > 0)
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: TextButton(
                                    onPressed: _canOpen
                                        ? () => _review(PlanReviewFilter.issues)
                                        : null,
                                    child: const Text('记录待核对'),
                                  ),
                                ),
                              if (data.rows.isEmpty)
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 12,
                                  ),
                                  child: Text(
                                    '今日暂无可展示的执行规划，点击查看或添加',
                                    style: theme.textTheme.bodySmall,
                                  ),
                                ),
                              ...data.rows.map(_row),
                              const SizedBox(height: 4),
                              Divider(
                                height: 1,
                                color: colors.outlineVariant.withValues(
                                  alpha: 0.5,
                                ),
                              ),
                              Align(
                                alignment: Alignment.centerLeft,
                                child: TextButton.icon(
                                  key: const ValueKey('plan-today-all'),
                                  onPressed: _canOpen ? _calendar : null,
                                  icon: const Icon(
                                    Icons.arrow_forward_rounded,
                                    size: 16,
                                  ),
                                  label: Text(
                                    data.total > data.rows.length
                                        ? '查看全部规划'
                                        : '全部规划',
                                  ),
                                ),
                              ),
                              if (data.overview.actual('unlinkedN') > 0)
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: TextButton(
                                    onPressed: _canOpen
                                        ? () =>
                                              _review(PlanReviewFilter.unlinked)
                                        : null,
                                    child: Text(
                                      '未关联规划的专注 · ${planOverviewDuration(data.overview.actual('unlinked'))}',
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(
                                            color: colors.onSurfaceVariant,
                                          ),
                                    ),
                                  ),
                                ),
                            ],
                          ],
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
