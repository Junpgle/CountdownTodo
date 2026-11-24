import '../services/plan_continuous_range_service.dart';
import '../models/plan_weekly_availability.dart';
import '../services/plan_weekly_availability_preferences.dart';

import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../models.dart';
import '../services/database_helper.dart';
import '../services/plan_todo_guard.dart';
import '../services/plan_reuse_repository.dart';
import '../services/plan_manual_completion_service.dart';
import '../services/plan_editor_draft_repository.dart';
import '../services/plan_availability_preferences.dart';
import '../models/plan_availability.dart';
import '../models/plan_split.dart';
import '../services/plan_split_service.dart';
import '../screens/plan_split_screen.dart';
import '../storage_service.dart';
import '../screens/pomodoro_screen.dart';
import '../screens/pomodoro/pomodoro_entry_intent.dart';
import '../services/plan_availability_repository.dart';
import '../services/plan_availability_service.dart';
import '../services/fixed_schedule_preparation_guard.dart';
import '../services/plan_conflict_review_service.dart';
import '../services/missed_plan_recovery_service.dart';
import '../services/time_estimation_service.dart';
import '../services/time_estimation_repository.dart';
import '../services/pomodoro_service.dart';
import '../services/pomodoro_control_service.dart';
import '../utils/app_dialogs.dart';
import '../utils/calendar_date_math.dart';
import '../utils/page_transitions.dart';
import '../utils/todo_recurrence_picker.dart';
import 'plan_availability_panel.dart';
import 'optional_liquid_glass_surface.dart';
import 'time_estimation_hint.dart';

part 'plan_block_editor/plan_block_editor_drafts.dart';
part 'plan_block_editor/plan_block_editor_actions.dart';
part 'plan_block_editor/plan_block_editor_ui.dart';

final Map<(String?, String), DateFormat> _planBlockEditorDateFormats = {};

DateFormat _planBlockEditorDateFormat(String pattern) {
  final locale = Intl.defaultLocale;
  return _planBlockEditorDateFormats.putIfAbsent((
    locale,
    pattern,
  ), () => DateFormat(pattern, locale));
}

Future<T?> showPlanBlockEditorPage<T>({
  required BuildContext context,
  required WidgetBuilder builder,
}) =>
    Navigator.of(context)
        .push<T>(PageTransitions.material<T>(builder: builder));

/// Existing plan editing retains the bounded sheet shell.
Future<T?> showPlanBlockEditorSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
}) => showAppModalBottomSheet<T>(
  context: context,
  isScrollControlled: true,
  enableDrag: false,
  backgroundColor: Colors.transparent,
  constraints: const BoxConstraints(maxWidth: 680),
  useGlassSheet: false,
  builder: builder,
);

class _TodoPlanSelectEntry {
  const _TodoPlanSelectEntry._({required this.value, this.header, this.todo});

  factory _TodoPlanSelectEntry.header(String header, int index) =>
      _TodoPlanSelectEntry._(value: '__todo_header_$index', header: header);

  factory _TodoPlanSelectEntry.todo(TodoItem todo) =>
      _TodoPlanSelectEntry._(value: todo.id, todo: todo);

  final String value;
  final String? header;
  final TodoItem? todo;
}

typedef PlanEditorSaver = Future<TodoPlanBlock> Function(
  TodoPlanBlock draft,
  PlanAvailabilitySelection? selection, {
  int? expectedVersion,
  int? expectedUpdatedAt,
  TodoPlanStatus? newStatus,
});

class PlanBlockEditorSheet extends StatefulWidget {
  final TodoPlanBlock? block;
  final DateTime startTime;
  final DateTime endTime;
  final List<TodoItem> todos;
  final List<TodoGroup> todoGroups;
  final String username;
  final String? initialTodoId;
  final bool autoFillEstimateOnTodoChange;
  final VoidCallback onSaved;
  final PlanAvailabilityLoader? availabilityLoader;
  final PlanContinuousRangeLoader? continuousRangeLoader;
  final PlanEditorSaver? saver;
  final Future<void> Function(TodoPlanBlock block, TodoItem todo)? startFocus;
  final Future<void> Function(TodoPlanBlock block, TodoItem todo)? openPomodoro;
  final Future<TimeEstimationResult> Function(TodoItem todo)? estimate;
  final DateTime Function()? clock;
  final bool navigateOnFocus;
  final MissedPlanRecoveryContext? recovery;
  final MissedPlanRecoveryService? recoveryService;
  final VoidCallback? onRecover;
  final Future<void> Function(BuildContext)? reviewRecovery;
  final bool autoRecommendTime;
  final bool fullPage;
  final PlanConflictEditContext? conflictEdit;
  final PlanConflictReviewService? conflictService;
  final PlanBacklogSaveContext? backlogContext;
  final Future<void> Function()? onViewExisting;
  final PlanEditorDraft? restoredDraft;
  final PlanEditorDraftRepository? draftRepository;
  final String draftOrigin;
  final VoidCallback? onManageDrafts;
  final PlanReuseSeed? reuse;
  final PlanReuseRepository? reuseRepository;
  final PlanManualCompletionService? manualCompletionService;
  final ValueChanged<PlanManualCompletionReceipt>? onManualCompleted;
  final FixedSchedulePreparationContext? preparationContext;
  final PlanAvailabilitySelection? preparationSelection;

  const PlanBlockEditorSheet({
    super.key,
    this.block,
    required this.startTime,
    required this.endTime,
    required this.todos,
    required this.todoGroups,
    required this.username,
    this.initialTodoId,
    this.autoFillEstimateOnTodoChange = true,
    required this.onSaved,
    this.availabilityLoader,
    this.continuousRangeLoader,
    this.saver,
    this.startFocus,
    this.openPomodoro,
    this.estimate,
    this.clock,
    this.navigateOnFocus = true,
    this.recovery,
    this.recoveryService,
    this.onRecover,
    this.reviewRecovery,
    this.autoRecommendTime = false,
    this.fullPage = false,
    this.conflictEdit,
    this.conflictService,
    this.backlogContext,
    this.onViewExisting,
    this.restoredDraft,
    this.draftRepository,
    this.draftOrigin = 'timeline',
    this.onManageDrafts,
    this.reuse,
    this.reuseRepository,
    this.manualCompletionService,
    this.onManualCompleted,
    this.preparationContext,
    this.preparationSelection,
  });

  @override
  State<PlanBlockEditorSheet> createState() => _PlanBlockEditorSheetState();
}

List<_TodoPlanSelectEntry> _buildTodoEntries(
  List<TodoItem> todos,
  List<TodoGroup> groups,
) {
  final groupNameById = <String, String>{};
  final groupIndices = <String, int>{};
  for (var index = 0; index < groups.length; index++) {
    final group = groups[index];
    groupNameById[group.id] = group.name;
    if (!groupIndices.containsKey(group.id)) {
      groupIndices[group.id] = index;
    }
  }
  int urgencyMs(TodoItem todo) {
    return todo.effectiveDueAt?.millisecondsSinceEpoch ?? (1 << 62);
  }

  String groupName(TodoItem todo) {
    final groupId = todo.groupId;
    if (groupId == null || groupId.isEmpty) return '未分类';
    return groupNameById[groupId] ?? '未知分类';
  }

  int groupRank(TodoItem todo) {
    final groupId = todo.groupId;
    if (groupId == null || groupId.isEmpty) return 1 << 30;
    return groupIndices[groupId] ?? (1 << 30) - 1;
  }

  final sorted = List<TodoItem>.from(todos)
    ..sort((a, b) {
      if (a.isDone != b.isDone) return a.isDone ? 1 : -1;
      final groupRankCompare = groupRank(a).compareTo(groupRank(b));
      if (groupRankCompare != 0) return groupRankCompare;
      final groupCompare = groupName(a).compareTo(groupName(b));
      if (groupCompare != 0) return groupCompare;
      final urgencyCompare = urgencyMs(a).compareTo(urgencyMs(b));
      if (urgencyCompare != 0) return urgencyCompare;
      return a.title.compareTo(b.title);
    });

  final entries = <_TodoPlanSelectEntry>[];
  String? currentHeader;
  var headerIndex = 0;
  for (final todo in sorted) {
    final header = '${todo.isDone ? "已完成" : "未完成"} · ${groupName(todo)}';
    if (header != currentHeader) {
      currentHeader = header;
      entries.add(_TodoPlanSelectEntry.header(header, headerIndex++));
    }
    entries.add(_TodoPlanSelectEntry.todo(todo));
  }
  return entries;
}

class _PlanBlockEditorSheetState extends State<PlanBlockEditorSheet>
    with WidgetsBindingObserver {
  final GlobalKey _focusActionSourceKey = GlobalKey();
  String? _selectedTodoId;
  late DateTime _start, _end;
  late TextEditingController _remarkCtrl;
  int _reminderMinutes = 5;
  int _pomodoroMinutes = 25;
  int _pomodoroRounds = 0;
  late List<_TodoPlanSelectEntry> _todoEntries;
  int? _estimatedMinutes;
  TimeEstimationResult? _estimateResult;
  (String?, String?) _selectedTodoMetadata = (null, null);
  int _estimateSequence = 0, _draftRevision = 0, _savedDraftRevision = -1;
  late final PlanManualCompletionService _manualCompletion =
      widget.manualCompletionService ??
      PlanManualCompletionService(clock: widget.clock);
  bool _busy = false, _recommendationStale = false, _focusStarted = false;
  PlanAvailabilitySelection? _recommendation;
  TodoPlanBlock? _persistedBlock;
  String? _operationError;
  PlanAvailabilityQuery? _manualQuery;
  PlanSplitSelection? _split;
  List<String> _splitIds = [];
  List<TodoPlanBlock> _savedSplitBlocks = [];
  DateTime? _singleStart, _singleEnd;
  PlanAvailabilityQuery? _singleQuery;
  bool _splitAdjusted = false, _splitStale = false;
  bool get _canSplit =>
      widget.fullPage &&
      _supportsDraft &&
      _selectedTodo != null &&
      _preparationContext == null;
  bool get _splitPersisted => _split != null && _savedSplitBlocks.isNotEmpty;

  bool _autoRecommendationPending = false;
  bool _initialEstimatePending = false;
  bool _allowAutoRecommendation = false;
  PlanTodoIdentity? _saveIdentity;
  late Future<void> _identityReady;
  Object? _identityError;
  String? _approvedArrangements;
  late final PlanEditorDraftRepository _drafts;
  PlanEditorDraft? _localDraft;
  PlanDraftSummary? _draftOffer;
  PlanBacklogSaveContext? _restoredBacklog;
  FixedSchedulePreparationContext? _preparationContext;
  TodoItem? _restoredTodo;
  late String _targetPlanId, _baseline;
  bool _userTouched = false, _allowExit = false, _exitPrompt = false;
  bool _reuseNeedsRetention = false, _openingReuse = false;
  bool _draftLoading = false, _restored = false, _offsetChanged = false;
  String _restoredScheduleOrigin = 'legacy';
  String? _restoredWeeklyKey;
  bool _restoredWeeklyIgnored = false;
  bool _draftRestoreFailed = false;
  String? _draftLoadError;
  int _draftReadSequence = 0;
  PlanBacklogSaveContext? get _backlog =>
      _restoredBacklog ?? widget.backlogContext;
  bool get _canReuse =>
      widget.block != null &&
      !widget.block!.id.startsWith('mapped_') &&
      widget.block!.source != TodoPlanSource.calendar;
  bool get _isReuse =>
      (_localDraft?.fields.origin ??
          widget.restoredDraft?.fields.origin ??
          (widget.reuse == null ? null : 'reuse')) ==
      'reuse';
  List<String> get _reuseSettingsAdjustments =>
      _localDraft?.fields.settingsAdjustments ??
      widget.restoredDraft?.fields.settingsAdjustments ??
      widget.reuse?.settings.corrections
          .map((correction) => correction.summary)
          .toList() ??
      const [];
  PlanReuseRepository get _reuseRepository =>
      widget.reuseRepository ?? PlanReuseRepository(clock: widget.clock);
  bool get _supportsDraft =>
      widget.block == null &&
      widget.recovery == null &&
      widget.conflictEdit == null;
  PlanDraftFields get _fields => PlanDraftFields(
    todoId: _selectedTodoId ?? '',
    title: _selectedTodo?.title ?? '',
    start: _start.millisecondsSinceEpoch,
    end: _end.millisecondsSinceEpoch,
    remark: _remarkCtrl.text,
    reminder: _reminderMinutes,
    pomodoro: _pomodoroMinutes,
    rounds: _pomodoroRounds,
    origin:
        _localDraft?.fields.origin ??
        (_isReuse
            ? 'reuse'
            : _backlog != null
            ? 'backlog'
            : widget.draftOrigin),
    settingsAdjustments: _reuseSettingsAdjustments,
    offsetMinutes: _start.timeZoneOffset.inMinutes,
    split: _split == null
        ? null
        : PlanSplitDraft(_split!.query, _split!.slots, _splitIds),
    scheduleOrigin: _restored
        ? _restoredScheduleOrigin
        : (_recommendation != null || (_split != null && !_splitAdjusted)
              ? 'recommended'
              : 'manual'),
    weeklyKey: _restored
        ? _restoredWeeklyKey
        : (_split?.query.base.weekly ?? _recommendation?.query.weekly)
              ?.fingerprint,
    weeklyIgnored: _restored
        ? _restoredWeeklyIgnored
        : (_split?.query.base.weekly ?? _recommendation?.query.weekly)
                  ?.ignored ??
              false,
    preparationContext: _preparationContext ?? widget.preparationContext,
  );

  void _mutateState(VoidCallback fn) => setState(fn);

  @override
  void initState() {
    super.initState();
    _drafts =
        widget.draftRepository ??
        PlanEditorDraftRepository(clock: widget.clock);
    _targetPlanId = const Uuid().v4();
    _identityReady = _captureSaveIdentity();
    WidgetsBinding.instance.addObserver(this);
    StorageService.scopedDataRefreshNotifier.addListener(
      _validateEstimateAccount,
    );
    _start = widget.startTime;
    _end = widget.endTime;
    _preparationContext = widget.preparationContext;
    _recommendation = widget.preparationSelection;
    _persistedBlock = widget.block == null
        ? null
        : TodoPlanBlock.fromJson(widget.block!.toJson());
    _autoRecommendationPending =
        (widget.autoRecommendTime || widget.reuse != null) &&
        widget.block == null;
    _initialEstimatePending =
        _autoRecommendationPending && widget.reuse == null;
    _allowAutoRecommendation = _autoRecommendationPending;
    _selectedTodoId =
        widget.block?.todoId ?? widget.reuse?.todo?.id ?? widget.initialTodoId;
    _restoredTodo = widget.reuse?.todo;
    final defaults = widget.recovery?.draft(_start) ?? widget.block;
    _remarkCtrl = TextEditingController(
      text: widget.reuse?.settings.remark ?? defaults?.remark,
    );
    _reminderMinutes =
        widget.reuse?.settings.reminder ?? defaults?.reminderMinutes ?? 5;
    _pomodoroMinutes =
        widget.reuse?.settings.pomodoro ?? defaults?.pomodoroMinutes ?? 25;
    _pomodoroRounds =
        widget.reuse?.settings.rounds ?? defaults?.pomodoroRounds ?? 0;
    _rebuildTodoEntries(chooseDefault: true);
    _baseline = _fields.fingerprint;
    _reuseNeedsRetention = widget.reuse != null;
    if (_selectedTodoId == null && _isReuse) _autoRecommendationPending = false;
    _draftLoading = widget.restoredDraft != null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (widget.restoredDraft != null) {
        unawaited(_restoreDraft(widget.restoredDraft!));
      } else {
        unawaited(_readDraftOffer());
      }
    });
    if (_initialEstimatePending) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_prepareInitialEstimate());
      });
    }
  }

  Future<void> _prepareInitialEstimate() async {
    final revision = _draftRevision;
    final todoId = _selectedTodoId;
    if (todoId != null) await _prefillEstimate(todoId);
    if (!mounted) return;
    setState(() {
      _initialEstimatePending = false;
      _allowAutoRecommendation =
          revision == _draftRevision &&
          todoId == _selectedTodoId &&
          _estimatedMinutes != null;
      if (!_allowAutoRecommendation) {
        _autoRecommendationPending = false;
        if (todoId != null && revision == _draftRevision) {
          _operationError = '完成时间预测失败，请手动设置时长后查找';
        }
      }
    });
  }

  void _rebuildTodoEntries({bool chooseDefault = false}) {
    _todoEntries = _buildTodoEntries(
      collapseRecurrenceSeriesForTodoPicker(
        [
          for (final todo in widget.todos)
            if (_restoredTodo?.id == todo.id) _restoredTodo! else todo,
        ].where(
          (todo) =>
              (!todo.isDone && !todo.isSkipped) ||
              todo.id == widget.block?.todoId,
        ),
        now: _start,
        preferredTodoId: _selectedTodoId,
      ),
      widget.todoGroups,
    );
    final selectedExists = _todoEntries.any(
      (entry) => entry.todo?.id == _selectedTodoId,
    );
    if (!selectedExists) {
      _selectedTodoId = null;
    }
    if (chooseDefault &&
        _selectedTodoId == null &&
        widget.block == null &&
        widget.recovery == null &&
        !_isReuse) {
      for (final entry in _todoEntries) {
        final todo = entry.todo;
        if (todo != null && !todo.isDone && !todo.isSkipped) {
          _selectedTodoId = todo.id;
          break;
        }
      }
    }
    _selectedTodoMetadata = _currentTodoMetadata;
  }

  (String?, String?) get _currentTodoMetadata =>
      (_selectedTodo?.title, _selectedTodo?.groupId);

  @override
  void didUpdateWidget(covariant PlanBlockEditorSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    final previous = _selectedTodoId;
    final priorMetadata = _selectedTodoMetadata;
    _rebuildTodoEntries();
    if (_selectedTodoId != previous ||
        oldWidget.username != widget.username ||
        priorMetadata != _selectedTodoMetadata) {
      _manualChange();
      _estimatedMinutes = null;
      _estimateResult = null;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _validateEstimateAccount();
  }

  void _validateEstimateAccount() {
    unawaited(_checkEstimateAccount());
    if (mounted && _split != null && _persistedBlock == null) {
      setState(() => _splitStale = true);
    }
  }

  Future<void> _checkEstimateAccount() async {
    try {
      await TimeEstimationRepository.checkAccount(widget.username);
    } on TimeEstimationAccountChanged {
      if (mounted) {
        setState(() {
          _manualChange();
          _estimatedMinutes = null;
          _estimateResult = null;
          _initialEstimatePending = false;
        });
      }
    }
  }

  @override
  void dispose() {
    ++_estimateSequence;
    WidgetsBinding.instance.removeObserver(this);
    StorageService.scopedDataRefreshNotifier.removeListener(
      _validateEstimateAccount,
    );
    _remarkCtrl.dispose();
    super.dispose();
  }

  Future<void> _prefillEstimate(String todoId) async {
    final todo = widget.todos.cast<TodoItem?>().firstWhere(
      (t) => t?.id == todoId,
      orElse: () => null,
    );
    if (todo == null || todo.title.isEmpty) return;

    final sequence = ++_estimateSequence;
    final revision = _draftRevision;
    final username = widget.username;
    final title = todo.title;
    final group = todo.groupId;
    TimeEstimationResult result;
    try {
      await TimeEstimationRepository.checkAccount(username);
      result =
          await (widget.estimate?.call(todo) ??
              TimeEstimationService.estimate(
                todo.title,
                groupId: todo.groupId,
                username: username,
                clock: widget.clock,
              ));
      await TimeEstimationRepository.checkAccount(username);
    } catch (_) {
      return; // A suggestion failure must not discard or block the draft.
    }
    if (!mounted ||
        sequence != _estimateSequence ||
        revision != _draftRevision ||
        widget.username != username ||
        _selectedTodoId != todoId ||
        _selectedTodo?.title != title ||
        _selectedTodo?.groupId != group ||
        _recommendation != null) {
      return;
    }

    final estMin = result.estimatedMinutes;
    if (estMin <= 0) return;
    final newEnd = _start.add(Duration(minutes: estMin));

    setState(() {
      _estimatedMinutes = estMin;
      _estimateResult = result;
      // Auto-fill end time
      if (newEnd.isAfter(_start)) {
        if (!_restored && !_isReuse) _end = newEnd;
      }
      _automaticBaseline();
      // Estimated focus time does not change the user's Pomodoro configuration.
    });
  }

  TodoItem? get _selectedTodo => _restoredTodo?.id == _selectedTodoId
      ? _restoredTodo
      : widget.todos.cast<TodoItem?>().firstWhere(
          (t) => t?.id == _selectedTodoId,
          orElse: () => null,
        );

  bool get _hasSelectableTodos =>
      _todoEntries.any((entry) => entry.todo != null && !entry.todo!.isDone);

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final size = MediaQuery.sizeOf(context);
    final viewInsets = MediaQuery.viewInsetsOf(context);
    final padding = MediaQuery.paddingOf(context);
    final textScaler = MediaQuery.textScalerOf(context);
    final height = max(
      0.0,
      size.height - viewInsets.bottom - padding.vertical - 24,
    );
    final scale = textScaler.scale(14) / 14;
    if (widget.fullPage) return _page(scale);
    return Semantics(
      namesRoute: true,
      label: widget.recovery != null
          ? '重新安排'
          : widget.block == null
          ? '添加规划块'
          : '编辑规划块',
      child: PopScope(
        canPop: _allowExit || (!_busy && !_draftLoading && !_dirty),
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop) unawaited(_leave());
        },
        child: SafeArea(
          child: Padding(
            padding: EdgeInsets.only(bottom: viewInsets.bottom),
            child: Align(
              alignment: Alignment.bottomCenter,
              heightFactor: 1,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: 680, maxHeight: height),
                child: OptionalLiquidGlassSheet(
                  topRadius: 28,
                  fallbackDecoration: BoxDecoration(
                    color: colors.surface,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(28),
                    ),
                  ),
                  child: ColoredBox(
                    // Dense form content needs a quiet surface over glass.
                    color: colors.surface.withValues(alpha: 0.85),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final width = constraints.maxWidth;
                        final inset = width >= 500 ? 24.0 : 16.0;
                        final header = _header(
                          EdgeInsets.fromLTRB(inset, 24, inset - 8, 20),
                          showIcon: width >= 430,
                        );
                        final form = _form(
                          width,
                          scale,
                          EdgeInsets.fromLTRB(inset, 8, inset, 16),
                        );
                        final footer = _footer(
                          width,
                          scale,
                          EdgeInsets.fromLTRB(inset, 16, inset, 16),
                        );
                        final compact =
                            constraints.maxHeight < 320 ||
                            (constraints.maxHeight < 480 && scale > 1.3);
                        return IgnorePointer(
                          ignoring: _busy || _draftLoading,
                          child: compact
                              ? SingleChildScrollView(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [header, form, footer],
                                  ),
                                )
                              : Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    header,
                                    Flexible(
                                      child: SingleChildScrollView(child: form),
                                    ),
                                    footer,
                                  ],
                                ),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
