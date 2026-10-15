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
import '../services/plan_editor_draft_repository.dart';
import '../services/plan_availability_preferences.dart';
import '../models/plan_availability.dart';
import '../models/plan_split.dart';
import '../services/plan_split_service.dart';
import '../screens/plan_split_screen.dart';
import '../storage_service.dart';
import '../screens/pomodoro_screen.dart';
import '../services/plan_availability_repository.dart';
import '../services/plan_availability_service.dart';
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
  });

  @override
  State<PlanBlockEditorSheet> createState() => _PlanBlockEditorSheetState();
}

class _PlanBlockEditorSheetState extends State<PlanBlockEditorSheet>
    with WidgetsBindingObserver {
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
      widget.fullPage && _supportsDraft && _selectedTodo != null;
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
  );
  bool get _dirty =>
      _reuseNeedsRetention ||
      (_userTouched && _fields.fingerprint != _baseline);
  void _touch() => _userTouched = true;
  void _automaticBaseline() {
    if (!_userTouched) _baseline = _fields.fingerprint;
  }

  Future<void> _readDraftOffer() async {
    if (!_supportsDraft ||
        (widget.saver != null && widget.draftRepository == null))
      return;
    final sequence = ++_draftReadSequence;
    final todoId = _selectedTodoId;
    if (_draftOffer != null || _draftLoadError != null) {
      setState(() {
        _draftOffer = null;
        _draftLoadError = null;
      });
    }
    if (todoId == null || _localDraft != null) return;
    try {
      await _identityReady;
      if (_identityError != null) throw _identityError!;
      final offers = await _drafts.list(_saveIdentity!, todoId: todoId);
      if (!mounted ||
          sequence != _draftReadSequence ||
          todoId != _selectedTodoId)
        return;
      setState(() {
        _draftOffer = offers.where((d) => d.id != _localDraft?.id).firstOrNull;
        _draftLoadError = null;
      });
    } catch (_) {
      if (mounted && sequence == _draftReadSequence) {
        setState(() => _draftLoadError = '草稿读取失败，可重试；当前表单仍可编辑');
      }
    }
  }

  Future<void> _restoreDraft(PlanEditorDraft draft) async {
    if (_busy) return;
    setState(() {
      _draftLoading = true;
      _draftRestoreFailed = false;
    });
    try {
      await _identityReady;
      if (_identityError != null) throw _identityError!;
      final prepared = await _drafts.prepare(
        _saveIdentity!,
        draft.id,
        draft.revision,
      );
      if (prepared.saved != null) {
        throw StateError('这份草稿已保存为规划，请从规划草稿查看已有规划');
      }
      if (!mounted) return;
      final f = prepared.draft.fields;
      PlanSplitSelection? restoredSplit;
      if (f.split != null) {
        final payload = PlanSplitDraft.fromJson(
          f.split!.toJson(),
          widget.username,
          f.todoId,
        );
        // Loading a draft must preserve times even when the current policy is
        // damaged. Defaults and the saved policy are checked at save/re-search.
        restoredSplit = PlanSplitSelection(
          payload.query,
          payload.slots,
          const PlanSplitSnapshot([]),
        );
      }
      if (!mounted) return;
      setState(() {
        _estimateSequence++;
        _draftRevision++;
        _draftReadSequence++;
        _localDraft = prepared.draft;
        _targetPlanId = prepared.draft.targetId;
        _restoredTodo = prepared.todo;
        _selectedTodoId = f.todoId;
        _restoredBacklog = prepared.backlog;
        _approvedArrangements = prepared.backlog == null ? null : '[]';
        _start = DateTime.fromMillisecondsSinceEpoch(f.start);
        _end = DateTime.fromMillisecondsSinceEpoch(f.end);
        _remarkCtrl.text = f.remark;
        _reminderMinutes = f.reminder;
        _pomodoroMinutes = f.pomodoro;
        _pomodoroRounds = f.rounds;
        _split = restoredSplit;
        _splitIds = f.split?.ids.toList() ?? [];
        _singleStart = null;
        _singleEnd = null;
        _singleQuery = null;
        _splitAdjusted = false;
        _restored = true;
        _restoredScheduleOrigin = f.scheduleOrigin;
        _restoredWeeklyKey = f.weeklyKey;
        _restoredWeeklyIgnored = f.weeklyIgnored;
        _offsetChanged =
            f.offsetMinutes != _start.timeZoneOffset.inMinutes ||
            (f.split?.timeZoneChanged ?? false);
        _recommendation = null;
        _manualQuery = null;
        _estimatedMinutes = null;
        _estimateResult = null;
        _allowAutoRecommendation = false;
        _autoRecommendationPending = false;
        _initialEstimatePending = false;
        _recommendationStale = false;
        _draftOffer = null;
        _draftLoadError = null;
        _operationError = null;
        _userTouched = false;
        _reuseNeedsRetention = false;
        _rebuildTodoEntries();
        _baseline = _fields.fingerprint;
      });
    } catch (error) {
      if (widget.restoredDraft != null && mounted) {
        setState(() => _draftRestoreFailed = true);
      }
      _reportError(error);
    } finally {
      if (mounted) setState(() => _draftLoading = false);
    }
  }

  Future<bool> _keepDraft() async {
    if (_busy ||
        _draftRestoreFailed ||
        !_supportsDraft ||
        _persistedBlock != null)
      return false;
    if (_offsetChanged) {
      _reportError(StateError('时区已变化，请先确认当前显示的日期与时间'));
      return false;
    }
    setState(() => _busy = true);
    try {
      await _identityReady;
      if (_identityError != null) throw _identityError!;
      final saved = await _drafts.keep(
        _saveIdentity!,
        _fields,
        previous: _localDraft,
        targetId: _targetPlanId,
      );
      if (!mounted) return false;
      setState(() {
        _localDraft = saved;
        _baseline = _fields.fingerprint;
        _userTouched = false;
        _reuseNeedsRetention = false;
        _operationError = null;
      });
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('已保留到本机规划草稿')));
      return true;
    } catch (error) {
      _reportError(error);
      return false;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _leave() async {
    if (_busy || _openingReuse || _draftLoading || _exitPrompt) return;
    if (!_dirty) {
      await _popEditor();
      return;
    }
    _exitPrompt = true;
    final action = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(_supportsDraft ? '保留这次规划？' : '放弃未保存的修改？'),
        content: Text(
          _localDraft != null
              ? '放弃修改也会删除这份本机草稿。保留后可稍后继续。'
              : '时段、备注、番茄和提醒设置还没有保存为规划。',
        ),
        actions: [
          TextButton(
            autofocus: true,
            onPressed: () => Navigator.pop(c),
            child: const Text('继续编辑'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, 'discard'),
            child: const Text('放弃修改'),
          ),
          if (_supportsDraft && _persistedBlock == null)
            FilledButton(
              onPressed: () => Navigator.pop(c, 'keep'),
              child: const Text('保留草稿并离开'),
            ),
        ],
      ),
    );
    _exitPrompt = false;
    if (!mounted || action == null) return;
    if (action == 'keep') {
      if (!await _keepDraft()) return;
    } else if (_localDraft != null) {
      setState(() => _busy = true);
      try {
        await _drafts.delete(
          _saveIdentity!,
          _localDraft!.id,
          _localDraft!.revision,
        );
        _localDraft = null;
      } catch (error) {
        _reportError(error);
        return;
      } finally {
        if (mounted) setState(() => _busy = false);
      }
    }
    await _popEditor();
  }

  Future<void> _popEditor() async {
    if (!mounted) return;
    setState(() => _allowExit = true);
    await WidgetsBinding.instance.endOfFrame;
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _pickDraftDate() async {
    final now = widget.clock?.call() ?? DateTime.now();
    final date = await showAppDatePicker(
      context: context,
      initialDate: _start.isBefore(now) ? now : _start,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: DateTime(now.year + 10),
    );
    if (date == null || !mounted) return;
    setState(() {
      _touch();
      _manualChange();
      final duration = _end.difference(_start);
      _start = DateTime(
        date.year,
        date.month,
        date.day,
        _start.hour,
        _start.minute,
      );
      _end = _start.add(duration);
    });
  }

  Future<void> _openDraftOffer() async {
    final offer = _draftOffer;
    if (offer == null || _busy || _draftLoading) return;
    if (_dirty) {
      final replace = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('继续上次草稿？'),
          content: const Text('这会替换当前尚未保留的输入。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c),
              child: const Text('继续当前编辑'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('继续上次草稿'),
            ),
          ],
        ),
      );
      if (replace != true || !mounted) return;
    }
    try {
      setState(() => _draftLoading = true);
      final draft = await _drafts.read(_saveIdentity!, offer.id);
      if (mounted) await _restoreDraft(draft);
    } catch (error) {
      _reportError(error);
    } finally {
      if (mounted) setState(() => _draftLoading = false);
    }
  }

  Widget _draftNotice() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (_draftLoading) const LinearProgressIndicator(),
      if (_draftRestoreFailed) ...[
        const Text('草稿未能恢复，当前不能保存。可重试或返回草稿列表查看保留内容。'),
        TextButton(
          onPressed: () => _restoreDraft(widget.restoredDraft!),
          child: const Text('重试恢复'),
        ),
      ],
      if (_draftLoadError != null)
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(_draftLoadError!),
            TextButton(onPressed: _readDraftOffer, child: const Text('重试读取草稿')),
          ],
        ),
      if (_draftOffer != null)
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.drafts_outlined),
          title: const Text('此待办有未完成的本机草稿'),
          subtitle: Text(
            DateFormat('M月d日 HH:mm').format(
              DateTime.fromMillisecondsSinceEpoch(_draftOffer!.updatedAt),
            ),
          ),
          onTap: _openDraftOffer,
          trailing: const Icon(Icons.chevron_right),
        ),
      if (_restored) ...[
        Text(
          _offsetChanged ? '时区已变化，请确认当前显示的日期与时间' : '草稿已恢复，请重新核对时段；保存前会检查最新安排。',
          key: const ValueKey('plan-draft-restored'),
        ),
        Wrap(
          spacing: 8,
          children: [
            TextButton.icon(
              key: const ValueKey('plan-draft-date'),
              onPressed: _busy
                  ? null
                  : _split == null
                  ? _pickDraftDate
                  : _chooseSplit,
              icon: const Icon(Icons.edit_calendar_outlined),
              label: Text(_split == null ? '修改日期' : '修改分段条件'),
            ),
            if (_offsetChanged)
              TextButton(
                onPressed: () => setState(() {
                  _touch();
                  _offsetChanged = false;
                }),
                child: const Text('确认当前时区时间'),
              ),
          ],
        ),
        const SizedBox(height: 12),
      ],
    ],
  );

  Future<PlanWeeklyContext?> _restoredWeeklyContext() async {
    if (!_restored || _restoredScheduleOrigin == 'manual') return null;
    if (_restoredWeeklyIgnored) {
      throw const PlanAvailabilityException(
        '草稿的本次不使用每周规则已失效，请重新查找并明确选择，或改为手动安排',
      );
    }
    final saved = await PlanWeeklyAvailabilityPreferences.load(widget.username);
    if (saved.error != null) throw PlanAvailabilityException(saved.error!);
    if (_restoredWeeklyKey != null && _restoredWeeklyKey != saved.key) {
      throw const PlanAvailabilityException('草稿的每周可安排时间已变化，请重新查找或改为手动安排');
    }
    return PlanWeeklyContext(saved.rules);
  }

  Future<void> _verifyRestoredTime() async {
    if (!_restored) return;
    if (_offsetChanged) throw StateError('时区已变化，请先确认当前显示的日期与时间');
    final weekly = await _restoredWeeklyContext();
    final preferences = await PlanAvailabilityPreferences.load(widget.username);
    if (preferences.bufferError != null &&
        !(_manualQuery?.bufferOverride ?? false)) {
      throw PlanAvailabilityException(preferences.bufferError!);
    }
    var appOnly =
        _manualQuery?.appOnly ?? _recommendation?.query.appOnly ?? false;
    while (true) {
      final query = PlanAvailabilityQuery(
        username: widget.username,
        weekly: weekly,
        todoId: _selectedTodoId!,
        date: _start,
        minutes: _end.difference(_start).inMinutes,
        windowStart: 0,
        windowEnd: 1440,
        appOnly: appOnly,
        bufferBefore: _manualQuery?.bufferBefore ?? preferences.bufferBefore,
        bufferAfter: _manualQuery?.bufferAfter ?? preferences.bufferAfter,
        bufferOverride: _manualQuery?.bufferOverride ?? false,
        bufferDefaultsKey:
            _manualQuery?.bufferDefaultsKey ?? preferences.bufferKey,
        avoidanceOverride: _manualQuery?.avoidanceOverride ?? false,
        avoidanceDefaultsKey:
            _manualQuery?.avoidanceDefaultsKey ?? preferences.avoidanceKey,
        avoidWindows:
            _manualQuery?.avoidWindows ??
            [
              for (final i in preferences.selectedIndices)
                preferences.options[i],
            ],
      );
      try {
        final latest =
            await (widget.availabilityLoader?.call(query) ??
                PlanAvailabilityRepository(clock: widget.clock)
                    .read(query, forceRefresh: true));
        final selection = PlanAvailabilitySelection(
          query,
          PlanTimeSlot(_start, _end),
          latest,
        );
        if (!PlanAvailabilityService.accepts(
          selection,
          latest,
          now: widget.clock?.call() ?? DateTime.now(),
        )) {
          throw const PlanAvailabilityException('草稿时段已过期、被占用或不符合避让，请重新选择时段');
        }
        _recommendation = selection;
        _recommendationStale = false;
        return;
      } on PlanAvailabilityException catch (error) {
        if (!error.canUseAppOnly || appOnly || !mounted) rethrow;
        final fallback = await showDialog<bool>(
          context: context,
          builder: (c) => AlertDialog(
            title: const Text('手机日历读取失败'),
            content: Text(error.message),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(c, false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(c, true),
                child: const Text('仅检查应用内日程'),
              ),
            ],
          ),
        );
        if (fallback != true) rethrow;
        appOnly = true;
      }
    }
  }

  Future<void> _captureSaveIdentity() async {
    try {
      _saveIdentity =
          widget.reuse?.identity ??
          _backlog?.identity ??
          await PlanTodoIdentity.capture(widget.username);
      await _saveIdentity!.check();
    } catch (error) {
      _identityError = error;
    }
  }

  Future<void> _checkLinkedTodo(
    DatabaseExecutor executor,
    TodoPlanBlock draft,
  ) async {
    await _identityReady;
    if (_identityError != null) throw _identityError!;
    final identity = _saveIdentity!;
    if (_localDraft != null) {
      await _drafts.validateRevision(executor, identity, _localDraft!);
    }
    await PlanTodoGuard.validate(executor, identity, draft.todoId);
    if (_backlog != null) {
      if (draft.todoId != _backlog!.todoId) {
        throw const PlanAvailabilityException('待办已变化，请重新打开清单');
      }
      await PlanTodoGuard.validateBacklog(
        executor,
        _backlog!,
        _approvedArrangements ?? _backlog!.arrangements,
        DateTime.fromMillisecondsSinceEpoch(draft.startTime),
        DateTime.fromMillisecondsSinceEpoch(draft.endTime),
        widget.clock?.call() ?? DateTime.now(),
      );
    }
    if (_isReuse && _backlog == null) {
      await PlanTodoGuard.validateBacklog(
        executor,
        PlanBacklogSaveContext(
          identity,
          draft.todoId,
          _approvedArrangements ?? '[]',
        ),
        _approvedArrangements ?? '[]',
        DateTime.fromMillisecondsSinceEpoch(draft.startTime),
        DateTime.fromMillisecondsSinceEpoch(draft.endTime),
        widget.clock?.call() ?? DateTime.now(),
      );
    }
    if (_split != null && _backlog == null && !_isReuse) {
      final latest = await PlanTodoGuard.arrangements(
        executor,
        draft.todoId,
        widget.clock?.call() ?? DateTime.now(),
      );
      if (latest != (_approvedArrangements ?? '[]')) {
        throw const PlanAvailabilityException('待办安排已变化，请重新确认追加整组');
      }
    }
    await identity.check();
  }

  Future<void> _confirmNewArrangements(String todoId) async {
    if ((_backlog == null && _split == null && !_isReuse) ||
        widget.saver != null)
      return;
    await _identityReady;
    if (_identityError != null) throw _identityError!;
    final db = await DatabaseHelper.instance.databaseForUser(widget.username);
    await PlanTodoGuard.validate(db, _saveIdentity!, todoId);
    final latest = await PlanTodoGuard.arrangements(
      db,
      todoId,
      widget.clock?.call() ?? DateTime.now(),
    );
    if (latest == (_approvedArrangements ?? _backlog?.arrangements ?? '[]')) {
      return;
    }
    if (latest == '[]') {
      _approvedArrangements = latest;
      return;
    }
    if (!mounted) throw const PlanAvailabilityException('页面已关闭');
    final append = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(_isReuse ? '此待办已有安排' : '此待办已有新的安排'),
        content: Text(
          _isReuse
              ? '本次会新增独立规划，原安排保留。可先查看已有安排，再决定是否追加。'
              : '编辑期间安排已变化。查看已有安排，或确认仍追加这次规划。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('查看已有安排'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('仍追加这次规划'),
          ),
        ],
      ),
    );
    if (append != true) {
      if (append == false) await widget.onViewExisting?.call();
      if (append == false &&
          _isReuse &&
          widget.onViewExisting == null &&
          mounted) {
        final rows = await db.query(
          'todo_plan_blocks',
          columns: ['start_time', 'end_time', 'status'],
          where: 'todo_uuid=? AND COALESCE(is_deleted,0)=0 AND status IN (0,2,4,5) AND end_time>?',
          whereArgs: [
            todoId,
            (widget.clock?.call() ?? DateTime.now()).millisecondsSinceEpoch,
          ],
          orderBy: 'start_time',
          limit: 20,
        );
        await _saveIdentity!.check();
        if (mounted) {
          await showDialog<void>(
            context: context,
            builder: (c) => AlertDialog(
              title: const Text('已有安排'),
              content: SingleChildScrollView(
                child: Text(
                  rows
                      .map(
                        (r) =>
                            '${DateFormat('MM-dd HH:mm').format(DateTime.fromMillisecondsSinceEpoch(r['start_time'] as int))}–${DateFormat('HH:mm').format(DateTime.fromMillisecondsSinceEpoch(r['end_time'] as int))}',
                      )
                      .join('\n'),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(c),
                  child: const Text('返回编辑'),
                ),
              ],
            ),
          );
        }
      }
      throw const PlanAvailabilityException('尚未追加，草稿已保留');
    }
    _approvedArrangements = latest;
  }

  void _manualChange() {
    _autoRecommendationPending = false;
    _draftRevision++;
    _estimateSequence++;
    _recommendation = null;
    _recommendationStale = false;
    _operationError = null;
    _restoredScheduleOrigin = 'manual';
    _restoredWeeklyKey = null;
    _restoredWeeklyIgnored = false;
  }

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
        ].where((todo) => !todo.isDone || todo.id == widget.block?.todoId),
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
        if (todo != null && !todo.isDone) {
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

  static List<_TodoPlanSelectEntry> _buildTodoEntries(
    List<TodoItem> todos,
    List<TodoGroup> groups,
  ) {
    final groupNameById = {for (final group in groups) group.id: group.name};
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
      final idx = groups.indexWhere((group) => group.id == groupId);
      return idx == -1 ? (1 << 30) - 1 : idx;
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

  String _todoGroupLabel(TodoItem todo) {
    final groupId = todo.groupId;
    if (groupId == null || groupId.isEmpty) return '未分类';
    return widget.todoGroups
            .cast<TodoGroup?>()
            .firstWhere((group) => group?.id == groupId, orElse: () => null)
            ?.name ??
        '未知分类';
  }

  String _todoUrgencyLabel(TodoItem todo) {
    final target = todo.dueDate;
    if (target == null) return '无时间';
    return DateFormat('MM-dd HH:mm').format(target);
  }

  Widget _buildTodoDropdownRow(TodoItem todo) {
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Container(
          constraints: const BoxConstraints(maxWidth: 86),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.8),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            _todoGroupLabel(todo),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            todo.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              decoration: todo.isDone ? TextDecoration.lineThrough : null,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          todo.isDone ? '已完成' : _todoUrgencyLabel(todo),
          style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }

  Future<TodoPlanBlock> _persist(
    TodoPlanBlock draft,
    PlanAvailabilitySelection? selection, {
    TodoPlanStatus? newStatus,
  }) async {
    final existing = _persistedBlock;
    if (_isReuse &&
        existing == null &&
        selection == null &&
        widget.saver == null) {
      selection = await _checkReuseTime();
    }
    if (widget.conflictEdit != null && widget.saver == null) {
      return (widget.conflictService ??
              PlanConflictReviewService(clock: widget.clock))
          .save(
            widget.conflictEdit!,
            draft,
            selection,
            expectedBlock: existing ?? widget.conflictEdit!.block,
            manualQuery: _manualQuery,
            newStatus: newStatus,
          );
    }
    if (widget.recovery != null && widget.saver == null) {
      return (widget.recoveryService ??
              MissedPlanRecoveryService(clock: widget.clock))
          .save(
            widget.recovery!,
            draft,
            selection,
            manualQuery: _manualQuery,
            expectedVersion: existing?.version,
            expectedUpdatedAt: existing?.updatedAt,
            newStatus: newStatus,
          );
    }
    if (widget.saver != null) {
      return widget.saver!(
        draft,
        selection,
        expectedVersion: existing?.version,
        expectedUpdatedAt: existing?.updatedAt,
        newStatus: newStatus,
      );
    }
    if (selection != null) {
      return PlanAvailabilityRepository(clock: widget.clock).save(
        selection,
        draft,
        expectedVersion: existing?.version,
        expectedUpdatedAt: existing?.updatedAt,
        beforeWrite: (executor) async {
          if (existing == null || existing.todoId != draft.todoId) {
            await _checkLinkedTodo(executor, draft);
          }
        },
      );
    }
    return StorageService.savePlanBlockEdited(
      widget.username,
      draft,
      expectedVersion: existing?.version,
      expectedUpdatedAt: existing?.updatedAt,
      newStatus: newStatus,
      beforeWrite: (executor) async {
        if ((await StorageService.getLoginSession() ?? 'default') !=
            widget.username) {
          throw const PlanAvailabilityException('账号已切换，请重新打开编辑器');
        }
        if (existing == null || existing.todoId != draft.todoId) {
          await _checkLinkedTodo(executor, draft);
        }
      },
    );
  }

  Future<PlanAvailabilitySelection> _checkReuseTime() async {
    final preferences = await PlanAvailabilityPreferences.load(widget.username);
    var appOnly = _manualQuery?.appOnly ?? false;
    while (true) {
      final query = PlanAvailabilityQuery(
        username: widget.username,
        todoId: _selectedTodoId!,
        date: _start,
        minutes: _end.difference(_start).inMinutes,
        windowStart: 0,
        windowEnd: 1440,
        appOnly: appOnly,
        bufferBefore: _manualQuery?.bufferBefore ?? preferences.bufferBefore,
        bufferAfter: _manualQuery?.bufferAfter ?? preferences.bufferAfter,
        bufferOverride: _manualQuery?.bufferOverride ?? false,
        bufferDefaultsKey:
            _manualQuery?.bufferDefaultsKey ?? preferences.bufferKey,
        avoidanceOverride: _manualQuery?.avoidanceOverride ?? false,
        avoidanceDefaultsKey:
            _manualQuery?.avoidanceDefaultsKey ?? preferences.avoidanceKey,
        avoidWindows:
            _manualQuery?.avoidWindows ??
            [
              for (final i in preferences.selectedIndices)
                preferences.options[i],
            ],
      );
      try {
        final repository = PlanAvailabilityRepository(clock: widget.clock);
        final fresh = await repository.read(query, forceRefresh: true);
        final candidate = PlanAvailabilitySelection(
          query,
          PlanTimeSlot(_start, _end),
          fresh,
        );
        if (!PlanAvailabilityService.accepts(
          candidate,
          fresh,
          now: widget.clock?.call() ?? DateTime.now(),
        )) {
          throw const PlanAvailabilityException('时段已过去、被占用或不符合避让，请重新选择');
        }
        return candidate;
      } on PlanAvailabilityException catch (error) {
        if (!error.canUseAppOnly || appOnly || !mounted) rethrow;
        final fallback = await showDialog<bool>(
          context: context,
          builder: (c) => AlertDialog(
            title: const Text('手机日历读取失败'),
            content: Text(error.message),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(c, false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(c, true),
                child: const Text('仅检查应用内日程'),
              ),
            ],
          ),
        );
        if (fallback != true) rethrow;
        appOnly = true;
      }
    }
  }

  Future<void> _chooseSplit({PlanAvailabilityQuery? query}) async {
    if (_busy || !_canSplit || _splitPersisted) return;
    final initial =
        _split?.query ??
        PlanSplitQuery(
          query ??
              PlanAvailabilityQuery(
                username: widget.username,
                todoId: _selectedTodoId!,
                date: _manualQuery?.date ?? _start,
                minutes: _end.difference(_start).inMinutes,
                windowStart: _manualQuery?.windowStart ?? 480,
                windowEnd: _manualQuery?.windowEnd ?? 1320,
                avoidWindows: _manualQuery?.avoidWindows ?? const [],
                appOnly: _manualQuery?.appOnly ?? false,
                bufferBefore: _manualQuery?.bufferBefore ?? 0,
                bufferAfter: _manualQuery?.bufferAfter ?? 0,
                bufferOverride: _manualQuery?.bufferOverride ?? false,
                bufferDefaultsKey: _manualQuery?.bufferDefaultsKey,
                avoidanceOverride: _manualQuery?.avoidanceOverride ?? false,
                avoidanceDefaultsKey: _manualQuery?.avoidanceDefaultsKey,
                weekly: _manualQuery?.weekly,
              ),
        );
    final result = await Navigator.of(context).push<PlanSplitSelection>(
      MaterialPageRoute(
        builder: (_) => PlanSplitScreen(
          todo: _selectedTodo!,
          initialQuery: initial,
          clock: widget.clock,
          requireDurationConfirmation:
              _split == null &&
              widget.autoRecommendTime &&
              _estimatedMinutes == null &&
              _recommendation == null,
        ),
      ),
    );
    if (!mounted || result == null) return;
    setState(() {
      if (_split == null) {
        _singleStart = _start;
        _singleEnd = _end;
        _singleQuery = _manualQuery;
      }
      _touch();
      _manualChange();
      _split = result;
      _restored = false;
      _splitAdjusted = false;
      _splitStale = false;
      _splitIds = [
        _targetPlanId,
        for (var i = 1; i < result.slots.length; i++) const Uuid().v4(),
      ];
      _start = result.slots.first.start;
      _end = result.slots.first.end;
    });
  }

  Future<void> _returnSingle() async {
    if (_busy || _splitPersisted) return;
    if (_splitAdjusted) {
      final yes = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('放弃已调整的分段？'),
          content: const Text('备注、提醒和番茄设置会保留。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('返回单段'),
            ),
          ],
        ),
      );
      if (yes != true || !mounted) return;
    }
    setState(() {
      _touch();
      _manualChange();
      _start = _singleStart ?? _start;
      _end = _singleEnd ?? _end;
      _manualQuery = _singleQuery;
      _split = null;
      _splitIds = [];
    });
  }

  Future<void> _adjustSplit(int index) async {
    if (_busy || _splitPersisted) return;
    final selection = _split!, old = selection.slots[index];
    final date = await showDatePicker(
      context: context,
      initialDate: old.start,
      firstDate: selection.query.base.dayStart,
      lastDate: CalendarDateMath.inclusiveEndDate(selection.query.endDate),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(old.start),
    );
    if (time == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final start = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
      final replacement = PlanTimeSlot(
        start,
        start.add(Duration(minutes: old.minutes)),
      );
      // Reserve stable group-position UUIDs until the first atomic commit.
      // Reordering times must not replace the original draft's target anchor.
      final slots = [
        for (var i = 0; i < selection.slots.length; i++)
          i == index ? replacement : selection.slots[i],
      ]..sort((a, b) => a.start.compareTo(b.start));
      final manualSplit = selection.query.configure(
        base: selection.query.base.withWeekly(null),
      );
      final fresh = await PlanAvailabilityRepository(clock: widget.clock)
          .readSplit(
            manualSplit,
            forceRefresh: true,
            requireCalendar: selection.snapshot.includesCalendar,
          );
      if (!PlanSplitService.accepts(
        manualSplit,
        slots,
        fresh,
        now: widget.clock?.call() ?? DateTime.now(),
      )) {
        throw const PlanAvailabilityException('调整后的整组时段不可用，请避开其他分段和日程');
      }
      if (mounted) {
        setState(() {
          _touch();
          _manualChange();
          _splitAdjusted = true;
          _splitStale = false;
          _split = PlanSplitSelection(manualSplit, slots, fresh);
          _start = slots.first.start;
          _end = slots.first.end;
        });
      }
    } catch (e) {
      _reportError(e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _splitPreview() => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        key: const ValueKey('plan-split-preview'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '${_split!.slots.length}段 · 共${_split!.query.total}分钟',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          if (_splitStale)
            const Text(
              '安排或状态已变化，保存前将重新核对整组；也可重新选择整组。',
              key: ValueKey('plan-split-stale'),
            ),
          if (_splitPersisted)
            const Text(
              '分段已保存；这里只能重试启动第1段或关闭此页面。',
              key: ValueKey('plan-split-persisted'),
            ),
          for (var i = 0; i < _split!.slots.length; i++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('第${i + 1}段 · ${splitTimeLabel(_split!.slots[i])}'),
                  if (_pomodoroRounds > 0)
                    Text(
                      '本段专注${_pomodoroRounds * _pomodoroMinutes}分钟；固定轮数可能超出时段',
                    ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: _busy || _splitPersisted
                          ? null
                          : () => _adjustSplit(i),
                      child: const Text('调整本段'),
                    ),
                  ),
                ],
              ),
            ),
          Wrap(
            spacing: 8,
            children: [
              TextButton(
                onPressed: _busy || _splitPersisted ? null : _chooseSplit,
                child: const Text('重新选择整组'),
              ),
              TextButton(
                onPressed: _busy || _splitPersisted ? null : _returnSingle,
                child: const Text('返回单段'),
              ),
            ],
          ),
        ],
      ),
    ),
  );

  Future<TodoPlanBlock> _saveDraft() async {
    if (_draftLoading) throw StateError('正在恢复草稿，请稍候');
    if (_draftRestoreFailed) throw StateError('草稿未能恢复，请先重试或返回列表');
    if (_selectedTodoId == null || !_end.isAfter(_start)) {
      throw const PlanAvailabilityException('请选择待办，并设置有效的开始和结束时间');
    }
    if (widget.block == null || widget.block!.todoId != _selectedTodoId) {
      final todo = _selectedTodo;
      if (todo == null || todo.isDone || todo.isDeleted) {
        throw const PlanAvailabilityException('待办已完成或失效，请选择未完成的待办');
      }
    }
    if (_persistedBlock != null && _savedDraftRevision == _draftRevision) {
      return _persistedBlock!;
    }
    if (_localDraft != null && _persistedBlock == null) {
      await _identityReady;
      if (_identityError != null) throw _identityError!;
      final latestDraft = await _drafts.read(_saveIdentity!, _localDraft!.id);
      if (latestDraft.revision != _localDraft!.revision) {
        throw StateError('草稿已更新，请重新读取后保存');
      }
      if (await _drafts.target(_saveIdentity!, _localDraft!) != null) {
        throw StateError('这份草稿已保存为规划，请从规划草稿查看，勿重复提交');
      }
    }
    final TodoPlanBlock saved;
    if (_split != null) {
      if (_restored) {
        final weekly = await _restoredWeeklyContext();
        final updated = await splitWithCurrentDefaults(
          _split!.query,
          useWeekly: _restoredScheduleOrigin != 'manual',
        );
        _split = PlanSplitSelection(
          updated.configure(base: updated.base.withWeekly(weekly)),
          _split!.slots,
          _split!.snapshot,
        );
      }
      if (_offsetChanged) throw StateError('时区已变化，请先确认当前显示的日期与时间');
      await _confirmNewArrangements(_selectedTodoId!);
      final blocks = [
        for (var i = 0; i < _split!.slots.length; i++)
          TodoPlanBlock(
              id: _splitIds[i],
              todoId: _selectedTodoId!,
              startTime: _split!.slots[i].start.millisecondsSinceEpoch,
              endTime: _split!.slots[i].end.millisecondsSinceEpoch,
            )
            ..titleSnapshot = _selectedTodo?.title
            ..plannedMinutes = _split!.slots[i].minutes
            ..remark = _remarkCtrl.text.isEmpty ? null : _remarkCtrl.text
            ..reminderMinutes = _reminderMinutes
            ..pomodoroMinutes = _pomodoroMinutes
            ..pomodoroRounds = _pomodoroRounds,
      ];
      final all = await PlanAvailabilityRepository(clock: widget.clock)
          .saveSplit(
            _split!,
            blocks,
            beforeWrite: (executor) => _checkLinkedTodo(executor, blocks.first),
          );
      _savedSplitBlocks = all;
      _splitStale = false;
      saved = all.first;
    } else {
      await _verifyRestoredTime();
      if (_recommendation != null && _recommendationStale) {
        throw const PlanAvailabilityException('推荐时段已失效，请重新查找或手动修改时间');
      }
      final draft = _persistedBlock == null
          ? TodoPlanBlock(
              id: _targetPlanId,
              todoId: _selectedTodoId!,
              startTime: _start.millisecondsSinceEpoch,
              endTime: _end.millisecondsSinceEpoch,
            )
          : TodoPlanBlock.fromJson(_persistedBlock!.toJson());
      draft
        ..todoId = _selectedTodoId!
        ..titleSnapshot = _selectedTodo?.title
        ..startTime = _start.millisecondsSinceEpoch
        ..endTime = _end.millisecondsSinceEpoch
        ..plannedMinutes = _end.difference(_start).inMinutes
        ..remark = _remarkCtrl.text.isEmpty ? null : _remarkCtrl.text
        ..reminderMinutes = _reminderMinutes
        ..pomodoroMinutes = _pomodoroMinutes
        ..pomodoroRounds = _pomodoroRounds;
      await _identityReady;
      if (_identityError != null && widget.saver == null) throw _identityError!;
      final committed =
          _isReuse && _persistedBlock == null && widget.saver == null
          ? await _reuseRepository.savedTarget(_saveIdentity!, draft)
          : null;
      if (committed != null) {
        saved = committed;
      } else {
        await _confirmNewArrangements(draft.todoId);
        saved = await _persist(draft, _recommendation);
      }
    }
    _persistedBlock = saved;
    _savedDraftRevision = _draftRevision;
    _baseline = _fields.fingerprint;
    _userTouched = false;
    _reuseNeedsRetention = false;
    if (_localDraft != null) {
      try {
        await _drafts.delete(
          _saveIdentity!,
          _localDraft!.id,
          _localDraft!.revision,
        );
        _localDraft = null;
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('规划已保存，但本机草稿清理失败；恢复时会识别已有规划')),
          );
        }
      }
    }
    widget.onSaved();
    if (widget.recovery != null && mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('已新建规划，原漏做记录已保留')));
    }
    return saved;
  }

  void _reportError(Object error, {bool focus = false}) {
    if (!mounted) return;
    final text = error is PlanAvailabilityException
        ? error.message
        : error is StateError
        ? error.message.toString()
        : '操作失败，请重试';
    setState(
      () => _operationError = _focusStarted
          ? '专注已启动，后续操作失败：$text；可重试更新状态'
          : focus &&
                _savedDraftRevision == _draftRevision &&
                _persistedBlock != null
          ? '规划已保存，专注未启动：$text'
          : text,
    );
  }

  Future<void> _save() async {
    if (_busy || _openingReuse) return;
    setState(() {
      _busy = true;
      _operationError = null;
    });
    try {
      if (!_focusStarted) await _saveDraft();
      await _popEditor();
    } catch (error) {
      _reportError(error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveAndStartFocus() async {
    if (_busy || _openingReuse) return;
    setState(() {
      _busy = true;
      _operationError = null;
    });
    try {
      final block = _focusStarted ? _persistedBlock! : await _saveDraft();
      var todo = _selectedTodo;
      if (todo == null) throw const PlanAvailabilityException('待办已失效，请重新打开编辑器');
      if (!_focusStarted && widget.saver == null) {
        if ((await StorageService.getLoginSession() ?? 'default') !=
            widget.username) {
          throw const PlanAvailabilityException('账号已切换，请重新打开编辑器');
        }
        final db = await DatabaseHelper.instance.databaseForUser(
          widget.username,
        );
        final blocks = await db.query(
          'todo_plan_blocks',
          where: 'uuid = ?',
          whereArgs: [block.id],
        );
        await _identityReady;
        if (_identityError != null) throw _identityError!;
        final freshTodo = await PlanTodoGuard.read(
          db,
          _saveIdentity!,
          block.todoId,
        );
        if (blocks.isEmpty ||
            blocks.single['version'] != block.version ||
            blocks.single['updated_at'] != block.updatedAt ||
            blocks.single['is_deleted'] == 1 ||
            freshTodo.isDone ||
            freshTodo.isDeleted) {
          throw const PlanAvailabilityException('规划或待办已变化，请读取最新记录');
        }
        todo = freshTodo;
      }
      if (!_focusStarted && _split != null) {
        final db = await DatabaseHelper.instance.databaseForUser(
          widget.username,
        );
        await PlanTodoGuard.validate(db, _saveIdentity!, block.todoId);
        for (final saved in _savedSplitBlocks) {
          final rows = await db.query(
            'todo_plan_blocks',
            where: 'uuid=?',
            whereArgs: [saved.id],
          );
          if (rows.isEmpty ||
              rows.single['version'] != saved.version ||
              rows.single['updated_at'] != saved.updatedAt ||
              rows.single['is_deleted'] == 1 ||
              rows.single['has_conflict'] == 1) {
            throw const PlanAvailabilityException('分段规划已变化，请核对已有安排');
          }
        }
        final fresh = await PlanAvailabilityRepository(clock: widget.clock)
            .readSplit(
              _split!.query,
              forceRefresh: true,
              requireCalendar: _split!.snapshot.includesCalendar,
            );
        final clean = PlanSplitSnapshot([
          for (final day in fresh.days)
            PlanAvailabilitySnapshot(
              todo: day.todo,
              coverage: day.coverage,
              busy: day.busy
                  .where(
                    (b) =>
                        b.source != PlanBusySource.planBlock ||
                        !_splitIds.contains(b.id),
                  )
                  .toList(),
            ),
        ]);
        if (!PlanSplitService.accepts(
          _split!.query,
          _split!.slots,
          clean,
          now: widget.clock?.call() ?? DateTime.now(),
        )) {
          throw const PlanAvailabilityException('分段时段已变化，规划已保存；专注未启动');
        }
      }
      if (!_focusStarted && widget.saver == null && _recommendation != null) {
        final repository = PlanAvailabilityRepository(clock: widget.clock);
        final snapshot = await repository.read(
          _recommendation!.query,
          forceRefresh: true,
          requireCalendar: _recommendation!.snapshot.deviceCalendarIncluded,
        );
        final check = PlanAvailabilitySnapshot(
          todo: snapshot.todo,
          busy: snapshot.busy.where((item) => item.id != block.id).toList(),
          coverage: snapshot.coverage,
        );
        final db = await DatabaseHelper.instance.databaseForUser(
          widget.username,
        );
        final rows = await db.query(
          'todo_plan_blocks',
          where: 'uuid = ?',
          whereArgs: [block.id],
        );
        if (rows.isEmpty ||
            rows.single['version'] != block.version ||
            rows.single['updated_at'] != block.updatedAt ||
            !PlanAvailabilityService.accepts(
              _recommendation!,
              check,
              now: widget.clock?.call() ?? DateTime.now(),
            )) {
          throw const PlanAvailabilityException('规划或时段已变化，请读取最新记录');
        }
      }
      if (!_focusStarted && widget.saver == null && widget.recovery != null) {
        final service =
            widget.recoveryService ??
            MissedPlanRecoveryService(clock: widget.clock);
        await service.validate(widget.recovery!, ignoreBlockId: block.id);
        final start = DateTime.fromMillisecondsSinceEpoch(block.startTime);
        final end = DateTime.fromMillisecondsSinceEpoch(block.endTime);
        final query = PlanAvailabilityQuery(
          username: widget.username,
          todoId: block.todoId,
          date: start,
          minutes: block.plannedMinutes,
          windowStart: 0,
          windowEnd: 1440,
          excludeBlockId: block.id,
          appOnly: _manualQuery?.appOnly ?? false,
          bufferBefore: _manualQuery?.bufferBefore ?? 0,
          bufferAfter: _manualQuery?.bufferAfter ?? 0,
          bufferOverride: _manualQuery?.bufferOverride ?? false,
          bufferDefaultsKey: _manualQuery?.bufferDefaultsKey,
          avoidanceOverride: _manualQuery?.avoidanceOverride ?? false,
          avoidanceDefaultsKey: _manualQuery?.avoidanceDefaultsKey,
          avoidWindows: _manualQuery?.avoidWindows ?? const [],
        );
        final latest = await service.availability.read(
          query,
          forceRefresh: true,
          requireCalendar:
              _recommendation?.snapshot.deviceCalendarIncluded ?? false,
        );
        if (!PlanAvailabilityService.accepts(
          PlanAvailabilitySelection(query, PlanTimeSlot(start, end), latest),
          latest,
          now: service.now,
        )) {
          throw const MissedPlanRecoveryException('规划时段已失效或被占用，请读取最新安排');
        }
      }
      if (!_focusStarted) {
        if (widget.startFocus != null) {
          await widget.startFocus!(block, todo);
        } else {
          final settings = await PomodoroService.getSettings();
          final previousRun = await PomodoroService.loadRunState();
          try {
            await PomodoroControlService.startFocus(
              settings: settings,
              boundTodo: todo,
              durationMinutes: max(
                1,
                block.pomodoroRounds > 0
                    ? block.pomodoroMinutes * block.pomodoroRounds
                    : block.plannedMinutes,
              ),
              planBlockId: block.uuid,
            );
          } catch (_) {
            // Native notification/DND initialization may fail after the run
            // marker was saved. Retrying must not create another session.
            final run = await PomodoroService.loadRunState();
            if (run != null &&
                run.planBlockId == block.id &&
                run.phase == PomodoroPhase.focusing &&
                run.sessionUuid != previousRun?.sessionUuid) {
              _focusStarted = true;
            }
            rethrow;
          }
        }
        _focusStarted = true;
      }
      try {
        _persistedBlock = await _persist(
          block,
          null,
          newStatus: TodoPlanStatus.focusing,
        );
      } catch (_) {
        if (mounted) {
          setState(() => _operationError = '专注已启动，但规划状态更新失败；可重试更新状态');
        }
        return;
      }
      widget.onSaved();
      if (!mounted) return;
      final navigator = Navigator.of(context);
      await _popEditor();
      if (widget.navigateOnFocus) {
        navigator.push(
          PageTransitions.material(
            builder: (_) => PomodoroScreen(username: widget.username),
          ),
        );
      }
    } catch (error) {
      _reportError(error, focus: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    if (widget.block == null || _busy || _openingReuse) return;
    await StorageService.deletePlanBlockGlobally(
      widget.username,
      widget.block!.id,
    );
    widget.onSaved();
    if (mounted) Navigator.pop(context);
  }

  Future<void> _reusePlan() async {
    if (_busy || _openingReuse || _draftLoading || !_canReuse) return;
    if (_dirty) {
      _reportError(StateError('请先保存修改，或放弃修改后重新打开'));
      return;
    }
    setState(() => _openingReuse = true);
    try {
      await _identityReady;
      if (_identityError != null) throw _identityError!;
      await _saveIdentity!.check();
      final seed = await _reuseRepository.read(
        widget.username,
        widget.block!.id,
      );
      if (!mounted) return;
      await seed.identity.check();
      await _saveIdentity!.check();
      if (!mounted) return;
      if (_dirty) throw StateError('请先保存修改，或放弃修改后重新打开');
      final todos = [
        for (final t in widget.todos)
          if (t.id != widget.block!.todoId) t,
        if (seed.todo != null) seed.todo!,
      ];
      await showPlanBlockEditorPage<void>(
        context: context,
        builder: (_) => PlanBlockEditorSheet(
          fullPage: true,
          username: widget.username,
          reuse: seed,
          reuseRepository: widget.reuseRepository,
          startTime: seed.start,
          endTime: seed.end,
          todos: todos,
          todoGroups: widget.todoGroups,
          autoFillEstimateOnTodoChange: true,
          availabilityLoader: widget.availabilityLoader,
          continuousRangeLoader: widget.continuousRangeLoader,
          saver: widget.saver,
          startFocus: widget.startFocus,
          estimate: widget.estimate,
          clock: widget.clock,
          navigateOnFocus: widget.navigateOnFocus,
          draftRepository: widget.draftRepository,
          onManageDrafts: widget.onManageDrafts,
          onSaved: widget.onSaved,
        ),
      );
    } catch (error) {
      if (mounted) _reportError(error);
    } finally {
      if (mounted) setState(() => _openingReuse = false);
    }
  }

  Future<void> _skip() async {
    if (widget.block == null || _busy || _openingReuse) return;
    final block = widget.block!;
    block.status = TodoPlanStatus.skipped;
    block.markAsChanged();
    await StorageService.savePlanBlocks(widget.username, [block]);
    widget.onSaved();
    if (mounted) Navigator.pop(context);
  }

  InputDecoration _fieldDecoration(String label) {
    final colors = Theme.of(context).colorScheme;
    return InputDecoration(
      labelText: label,
      filled: true,
      fillColor: colors.surface,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(
          color: colors.outlineVariant.withValues(alpha: 0.7),
        ),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(
          color: colors.outlineVariant.withValues(alpha: 0.7),
        ),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
    );
  }

  Future<void> _pickTime(bool start) async {
    final value = start ? _start : _end;
    final time = await showAppTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(value),
    );
    if (time == null || !mounted) return;
    setState(() {
      _touch();
      _manualChange();
      final changed = DateTime(
        value.year,
        value.month,
        value.day,
        time.hour,
        time.minute,
      );
      if (start) {
        _start = changed;
      } else {
        _end = changed;
      }
    });
  }

  Widget _timeField(bool start) {
    final theme = Theme.of(context);
    return TextButton(
      style: TextButton.styleFrom(
        foregroundColor: theme.colorScheme.onSurface,
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      onPressed: () => _pickTime(start),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            start ? '开始时间' : '结束时间',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            DateFormat('HH:mm').format(start ? _start : _end),
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _header(EdgeInsets padding, {required bool showIcon}) {
    final theme = Theme.of(context);
    return Padding(
      padding: padding,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (showIcon) ...[
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                Icons.edit_calendar_outlined,
                color: theme.colorScheme.onPrimaryContainer,
                size: 24,
              ),
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.recovery != null
                      ? '重新安排'
                      : widget.block == null
                      ? '添加规划块'
                      : '编辑规划块',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '为待办留出专属时间',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          if (widget.block != null)
            PopupMenuButton<String>(
              tooltip: '更多操作',
              onSelected: (value) {
                if (value == 'reuse') unawaited(_reusePlan());
                if (value == 'skip') _skip();
                if (value == 'delete') _delete();
              },
              itemBuilder: (_) => [
                if (_canReuse)
                  PopupMenuItem(
                    value: 'reuse',
                    enabled: !_busy && !_openingReuse && !_draftLoading,
                    child: Text(_openingReuse ? '正在读取设置…' : '照此新建'),
                  ),
                const PopupMenuItem(value: 'skip', child: Text('跳过规划')),
                PopupMenuItem(
                  value: 'delete',
                  child: Text(
                    '删除规划',
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                ),
              ],
            ),
          IconButton(
            tooltip: '关闭',
            onPressed: () => unawaited(_leave()),
            icon: const Icon(Icons.close, size: 22),
          ),
        ],
      ),
    );
  }

  Widget _formSection(IconData icon, String title) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(icon, size: 18, color: theme.colorScheme.primary),
        const SizedBox(width: 8),
        Text(
          title,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }

  Widget _form(double width, double scale, EdgeInsets padding) {
    if (_draftRestoreFailed)
      return Padding(padding: padding, child: _draftNotice());
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final horizontalTimes = width >= 360 && scale < 1.7;
    return Padding(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _draftNotice(),
          if (_isReuse)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                _recommendation == null &&
                        _split == null &&
                        _persistedBlock == null
                    ? '沿用已有规划设置 · ${_end.difference(_start).inMinutes}分钟\n时段尚未核实，请选择推荐或调整'
                    : '沿用已有规划设置 · ${_split?.query.total ?? _end.difference(_start).inMinutes}分钟',
                key: const ValueKey('plan-reuse-notice'),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
            ),
          if (widget.recovery != null) ...[
            Text(
              '原安排：${DateFormat('MM-dd HH:mm').format(DateTime.fromMillisecondsSinceEpoch(widget.recovery!.source.startTime))}–${DateFormat('MM-dd HH:mm').format(DateTime.fromMillisecondsSinceEpoch(widget.recovery!.source.endTime))} · 漏做',
              key: const ValueKey('plan-recovery-origin'),
            ),
            for (final notice in widget.recovery!.notices)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(notice),
              ),
            const SizedBox(height: 12),
          ],
          _formSection(Icons.checklist_outlined, '规划内容'),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            key: ValueKey('plan-todo-picker-$_selectedTodoId'),
            initialValue: _selectedTodoId,
            isExpanded: true,
            items: _todoEntries
                .map(
                  (entry) => DropdownMenuItem(
                    value: entry.value,
                    enabled: entry.todo != null && !entry.todo!.isDone,
                    child: entry.todo == null
                        ? Text(
                            entry.header!,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: colors.primary,
                            ),
                          )
                        : _buildTodoDropdownRow(entry.todo!),
                  ),
                )
                .toList(),
            selectedItemBuilder: (context) => _todoEntries
                .map(
                  (entry) => entry.todo == null
                      ? const SizedBox.shrink()
                      : Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            entry.todo!.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                )
                .toList(),
            onChanged:
                widget.recovery != null ||
                    widget.conflictEdit != null ||
                    !_hasSelectableTodos ||
                    _split != null
                ? null
                : (value) {
                    if (value == null || value.startsWith('__todo_header_')) {
                      return;
                    }
                    setState(() {
                      _touch();
                      _selectedTodoId = value;
                      _approvedArrangements = null;
                      _selectedTodoMetadata = _currentTodoMetadata;
                      _estimatedMinutes = null;
                      _estimateResult = null;
                      _manualChange();
                    });
                    if (widget.autoFillEstimateOnTodoChange) {
                      _prefillEstimate(value);
                    }
                    unawaited(_readDraftOffer());
                  },
            decoration: _fieldDecoration('待办项目'),
          ),
          if (_selectedTodoId == null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                _hasSelectableTodos ? '原待办已完成或失效，请重新选择未完成待办' : '暂无可规划的未完成待办',
                key: const ValueKey('plan-no-unfinished-todos'),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
            ),
          if (_estimateResult != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: TimeEstimationHint(result: _estimateResult!),
            ),
          const SizedBox(height: 20),
          if (_split != null)
            _splitPreview()
          else ...[
            _formSection(Icons.schedule_outlined, '安排时间'),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 4,
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  '${DateFormat('M月d日').format(_start)} 周${['一', '二', '三', '四', '五', '六', '日'][_start.weekday - 1]}',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  '${_end.difference(_start).inMinutes} 分钟',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: colors.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Container(
              decoration: BoxDecoration(
                color: colors.primaryContainer.withValues(alpha: 0.35),
                border: Border.all(
                  color: colors.primary.withValues(alpha: 0.15),
                ),
                borderRadius: BorderRadius.circular(18),
              ),
              child: horizontalTimes
                  ? Row(
                      children: [
                        Expanded(child: _timeField(true)),
                        Icon(
                          Icons.arrow_forward,
                          size: 18,
                          color: colors.onSurfaceVariant,
                        ),
                        Expanded(child: _timeField(false)),
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _timeField(true),
                        Divider(
                          height: 1,
                          indent: 16,
                          endIndent: 16,
                          color: colors.outlineVariant,
                        ),
                        _timeField(false),
                      ],
                    ),
            ),
          ],
          const SizedBox(height: 16),
          if (_split == null && _initialEstimatePending)
            const Padding(
              key: ValueKey('plan-initial-estimate'),
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Column(
                children: [
                  LinearProgressIndicator(),
                  SizedBox(height: 8),
                  Text('正在预测完成时间…'),
                ],
              ),
            )
          else if (_split == null)
            PlanAvailabilityPanel(
              username: widget.username,
              resultsOnly: widget.fullPage,
              autoLookupResults:
                  _isReuse ||
                  !widget.autoRecommendTime ||
                  _estimatedMinutes != null,
              todo: _selectedTodo,
              initialDate: _start,
              initialMinutes: _end.difference(_start).inMinutes,
              editingBlock: _persistedBlock,
              estimatedMinutes: _estimatedMinutes,
              loader: widget.availabilityLoader,
              rangeLoader: widget.continuousRangeLoader,
              onSplitRequested: _canSplit
                  ? (q) => _chooseSplit(query: q)
                  : null,
              clock: widget.clock,
              initialExpanded:
                  widget.recovery != null || widget.autoRecommendTime,
              autoLookupAndSelect: _allowAutoRecommendation,
              autoSelectionRevision: _draftRevision,
              onAutoLookupPendingChanged: (pending) {
                if (mounted && _autoRecommendationPending != pending) {
                  setState(() => _autoRecommendationPending = pending);
                }
              },
              dateShortcuts: widget.recovery != null,
              onQueryChanged: (query) => _manualQuery = query,
              onDateChanged: widget.recovery == null
                  ? null
                  : (date) => setState(() {
                      final duration = _end.difference(_start);
                      _manualChange();
                      _start = DateTime(
                        date.year,
                        date.month,
                        date.day,
                        _start.hour,
                        _start.minute,
                      );
                      _end = _start.add(duration);
                    }),
              onInvalidated: () {
                _estimateSequence++;
                if (_recommendation != null && mounted) {
                  setState(() => _recommendationStale = true);
                }
              },
              onSelected: (selection) => setState(() {
                final automatic = _autoRecommendationPending;
                if (!automatic) _touch();
                _estimateSequence++;
                _draftRevision++;
                _recommendation = selection;
                _restored = false;
                _recommendationStale = false;
                _start = selection.slot.start;
                _end = selection.slot.end;
                _operationError = null;
                _automaticBaseline();
              }),
            ),
          if (_canSplit && _split == null)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: const ValueKey('plan-open-split'),
                onPressed: _busy || _initialEstimatePending
                    ? null
                    : _chooseSplit,
                icon: const Icon(Icons.splitscreen_outlined),
                label: const Text('分段安排'),
              ),
            ),
          if (_restored && _restoredScheduleOrigin != 'manual')
            TextButton(
              key: const ValueKey('plan-draft-use-manual'),
              onPressed: _busy
                  ? null
                  : () => setState(() {
                      _touch();
                      _manualChange();
                      if (_split != null) {
                        _split = PlanSplitSelection(
                          _split!.query.configure(
                            base: _split!.query.base.withWeekly(null),
                          ),
                          _split!.slots,
                          _split!.snapshot,
                        );
                        _splitAdjusted = true;
                      }
                    }),
              child: const Text('保留此时间，改为手动安排'),
            ),
          if (_recommendation != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                _recommendationStale ? '推荐时段已失效，请重新查找' : '已填入推荐时段，保存前会再次检查。',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: _recommendationStale ? colors.error : colors.primary,
                ),
              ),
            ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: colors.surface,
              border: Border.all(
                color: colors.outlineVariant.withValues(alpha: 0.6),
              ),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _formSection(Icons.tune, '其他设置'),
                const SizedBox(height: 12),
                TextField(
                  key: const ValueKey('plan-remark'),
                  controller: _remarkCtrl,
                  readOnly: _splitPersisted,
                  onChanged: (_) => setState(() {
                    _touch();
                    _draftRevision++;
                    _autoRecommendationPending = false;
                  }),
                  decoration: _fieldDecoration('备注（可选）'),
                ),
                const SizedBox(height: 12),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final columns =
                        ((constraints.maxWidth >= 300 && scale <= 1.15) ||
                            (constraints.maxWidth >= 460 && scale < 1.6))
                        ? 3
                        : (constraints.maxWidth >= 240 && scale < 1.6 ? 2 : 1);
                    final fieldWidth =
                        (constraints.maxWidth - 12 * (columns - 1)) / columns;
                    Widget option(
                      String label,
                      int value,
                      List<int> values,
                      String Function(int) title,
                      ValueChanged<int?> changed,
                    ) => SizedBox(
                      width: fieldWidth,
                      child: DropdownButtonFormField<int>(
                        key: ValueKey('plan-option-$label'),
                        initialValue: value,
                        isExpanded: true,
                        decoration: _fieldDecoration(label).copyWith(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 14,
                          ),
                        ),
                        style: theme.textTheme.bodySmall,
                        iconSize: 20,
                        items: values
                            .map(
                              (item) => DropdownMenuItem(
                                value: item,
                                child: Text(
                                  title(item) == '按规划时长' && fieldWidth < 120
                                      ? '按时长'
                                      : title(item),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: _splitPersisted ? null : changed,
                      ),
                    );
                    return Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        option(
                          '单轮番茄',
                          _pomodoroMinutes,
                          [15, 20, 25, 30, 45, 60],
                          (m) => '$m 分钟',
                          (v) => setState(() {
                            _touch();
                            _draftRevision++;
                            _pomodoroMinutes = v ?? 25;
                          }),
                        ),
                        option(
                          _split == null ? '番茄轮数' : '每段番茄轮数',
                          _pomodoroRounds,
                          [0, 1, 2, 3, 4, 5, 6],
                          (m) => m == 0 ? '按规划时长' : '$m 轮',
                          (v) => setState(() {
                            _touch();
                            _draftRevision++;
                            _pomodoroRounds = v ?? 0;
                          }),
                        ),
                        option(
                          '提前提醒',
                          _reminderMinutes,
                          [0, 5, 10, 15, 30],
                          (m) => m == 0 ? '不提醒' : '$m 分钟前',
                          (v) => setState(() {
                            _touch();
                            _draftRevision++;
                            _reminderMinutes = v ?? 5;
                          }),
                        ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _footer(double width, double scale, EdgeInsets padding) {
    final colors = Theme.of(context).colorScheme;
    final save = FilledButton(
      key: const ValueKey('plan-save'),
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      onPressed:
          _busy ||
              _draftLoading ||
              _draftRestoreFailed ||
              _autoRecommendationPending ||
              (_selectedTodoId == null && !_focusStarted)
          ? null
          : _save,
      child: Text(
        _focusStarted
            ? '关闭'
            : _splitPersisted
            ? '完成'
            : _split != null
            ? '保存全部${_split!.slots.length}段'
            : '保存规划',
      ),
    );
    final focus = OutlinedButton.icon(
      key: const ValueKey('plan-save-focus'),
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      onPressed:
          _busy ||
              _draftLoading ||
              _draftRestoreFailed ||
              _autoRecommendationPending ||
              (_selectedTodoId == null && !_focusStarted)
          ? null
          : _saveAndStartFocus,
      icon: const Icon(Icons.play_arrow_rounded, size: 20),
      label: Text(
        _focusStarted
            ? '重试更新专注状态'
            : _splitPersisted
            ? '重试开始第1段'
            : _split != null
            ? '保存全部并开始第1段'
            : '保存并开始专注',
      ),
    );
    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(
          top: BorderSide(color: colors.outlineVariant.withValues(alpha: 0.6)),
        ),
      ),
      padding: padding,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.block?.status == TodoPlanStatus.missed &&
              widget.onRecover != null)
            TextButton.icon(
              key: const ValueKey('plan-recover-from-editor'),
              onPressed: _busy
                  ? null
                  : () async {
                      final route = ModalRoute.of(context);
                      final recover = widget.onRecover!;
                      await _leave();
                      if (!_allowExit) return;
                      await route?.completed;
                      recover();
                    },
              icon: const Icon(Icons.event_repeat),
              label: const Text('重新安排'),
            ),
          if (_busy)
            const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: LinearProgressIndicator(),
            ),
          if (_operationError != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                _operationError!,
                key: const ValueKey('plan-save-error'),
                style: TextStyle(color: colors.error),
              ),
            ),
          if (_operationError != null && widget.onManageDrafts != null)
            TextButton(
              onPressed: _busy ? null : widget.onManageDrafts,
              child: const Text('管理规划草稿'),
            ),
          if (_operationError != null &&
              widget.reviewRecovery != null &&
              !_focusStarted)
            TextButton(
              onPressed: _busy
                  ? null
                  : () async {
                      setState(() => _busy = true);
                      try {
                        await widget.reviewRecovery!(context);
                      } catch (error) {
                        _reportError(error);
                      } finally {
                        if (mounted) setState(() => _busy = false);
                      }
                    },
              child: const Text('查看最新安排'),
            ),
          if (width >= 440 && scale < 1.6)
            Row(
              children: [
                Expanded(child: focus),
                const SizedBox(width: 12),
                Expanded(child: save),
              ],
            )
          else ...[
            save,
            const SizedBox(height: 10),
            focus,
          ],
        ],
      ),
    );
  }

  Widget _page(double scale) => PopScope(
    canPop: _allowExit || (!_busy && !_draftLoading && !_dirty),
    onPopInvokedWithResult: (didPop, result) {
      if (!didPop) unawaited(_leave());
    },
    child: Scaffold(
      key: const ValueKey('plan-block-editor-page'),
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerLowest,
      appBar: AppBar(
        centerTitle: false,
        backgroundColor: Theme.of(context).colorScheme.surfaceContainerLowest,
        leading: BackButton(onPressed: () => unawaited(_leave())),
        actions: [
          if (_supportsDraft)
            PopupMenuButton<String>(
              tooltip: '更多操作',
              onSelected: (value) {
                if (value == 'keep') unawaited(_keepDraft());
                if (value == 'manage') widget.onManageDrafts?.call();
              },
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 'keep',
                  enabled:
                      !_busy &&
                      !_draftLoading &&
                      !_draftRestoreFailed &&
                      _persistedBlock == null,
                  child: const Text('保留草稿'),
                ),
                if (widget.onManageDrafts != null)
                  const PopupMenuItem(value: 'manage', child: Text('规划草稿')),
              ],
            ),
        ],
        title: Text(
          widget.conflictEdit != null
              ? '调整规划'
              : widget.recovery != null
              ? '重新安排'
              : '新建规划块',
        ),
      ),
      body: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth;
                final inset = width >= 500 ? 24.0 : 16.0;
                final form = _form(
                  width,
                  scale,
                  EdgeInsets.fromLTRB(inset, 12, inset, 16),
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
                          child: Column(children: [form, footer]),
                        )
                      : Column(
                          children: [
                            Expanded(child: SingleChildScrollView(child: form)),
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
  );

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final media = MediaQuery.of(context);
    final height = max(
      0.0,
      media.size.height - media.viewInsets.bottom - media.padding.vertical - 24,
    );
    final scale = media.textScaler.scale(14) / 14;
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
            padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
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
