import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models.dart';
import '../services/database_helper.dart';
import '../models/plan_availability.dart';
import '../storage_service.dart';
import '../screens/pomodoro_screen.dart';
import '../services/plan_availability_repository.dart';
import '../services/plan_availability_service.dart';
import '../services/missed_plan_recovery_service.dart';
import '../services/time_estimation_service.dart';
import '../services/pomodoro_service.dart';
import '../services/pomodoro_control_service.dart';
import '../utils/app_dialogs.dart';
import '../utils/page_transitions.dart';
import '../utils/todo_recurrence_picker.dart';
import 'plan_availability_panel.dart';
import 'optional_liquid_glass_surface.dart';

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
  });

  @override
  State<PlanBlockEditorSheet> createState() => _PlanBlockEditorSheetState();
}

class _PlanBlockEditorSheetState extends State<PlanBlockEditorSheet> {
  String? _selectedTodoId;
  late DateTime _start, _end;
  late TextEditingController _remarkCtrl;
  int _reminderMinutes = 5;
  int _pomodoroMinutes = 25;
  int _pomodoroRounds = 0;
  late List<_TodoPlanSelectEntry> _todoEntries;
  int? _estimatedMinutes;
  int _estimateSequence = 0, _draftRevision = 0, _savedDraftRevision = -1;
  bool _busy = false, _recommendationStale = false, _focusStarted = false;
  PlanAvailabilitySelection? _recommendation;
  TodoPlanBlock? _persistedBlock;
  String? _operationError;
  PlanAvailabilityQuery? _manualQuery;
  bool _autoRecommendationPending = false;
  bool _initialEstimatePending = false;
  bool _allowAutoRecommendation = false;

  void _manualChange() {
    _autoRecommendationPending = false;
    _draftRevision++;
    _estimateSequence++;
    _recommendation = null;
    _recommendationStale = false;
    _operationError = null;
  }

  @override
  void initState() {
    super.initState();
    _start = widget.startTime;
    _end = widget.endTime;
    _persistedBlock = widget.block == null
        ? null
        : TodoPlanBlock.fromJson(widget.block!.toJson());
    _autoRecommendationPending =
        widget.autoRecommendTime && widget.block == null;
    _initialEstimatePending = _autoRecommendationPending;
    _allowAutoRecommendation = _autoRecommendationPending;
    _selectedTodoId = widget.block?.todoId ?? widget.initialTodoId;
    final defaults = widget.recovery?.draft(_start) ?? widget.block;
    _remarkCtrl = TextEditingController(text: defaults?.remark);
    _reminderMinutes = defaults?.reminderMinutes ?? 5;
    _pomodoroMinutes = defaults?.pomodoroMinutes ?? 25;
    _pomodoroRounds = defaults?.pomodoroRounds ?? 0;
    _rebuildTodoEntries(chooseDefault: true);
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
        widget.todos.where(
          (todo) => !todo.isDone || todo.id == widget.block?.todoId,
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
        widget.recovery == null) {
      for (final entry in _todoEntries) {
        final todo = entry.todo;
        if (todo != null && !todo.isDone) {
          _selectedTodoId = todo.id;
          break;
        }
      }
    }
  }

  @override
  void didUpdateWidget(covariant PlanBlockEditorSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    final previous = _selectedTodoId;
    _rebuildTodoEntries();
    if (_selectedTodoId != previous) _manualChange();
  }

  @override
  void dispose() {
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
    TimeEstimationResult result;
    try {
      result =
          await (widget.estimate?.call(todo) ??
              TimeEstimationService.estimate(
                todo.title,
                groupId: todo.groupId,
              ));
    } catch (_) {
      return; // A suggestion failure must not discard or block the draft.
    }
    if (!mounted ||
        sequence != _estimateSequence ||
        revision != _draftRevision ||
        _selectedTodoId != todoId ||
        _recommendation != null) {
      return;
    }

    final estMin = result.estimatedMinutes;
    if (estMin <= 0) return;
    final newEnd = _start.add(Duration(minutes: estMin));

    setState(() {
      _estimatedMinutes = estMin;
      // Auto-fill end time
      if (newEnd.isAfter(_start)) {
        _end = newEnd;
      }
      // Suggest pomodoro rounds based on estimated duration
      if (estMin >= _pomodoroMinutes) {
        _pomodoroRounds = (estMin / _pomodoroMinutes).round().clamp(1, 6);
      }
    });
  }

  TodoItem? get _selectedTodo => widget.todos.cast<TodoItem?>().firstWhere(
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
      if (todo.dueDate != null) return todo.dueDate!.millisecondsSinceEpoch;
      if (todo.createdDate != null && todo.createdDate! > 0) {
        return todo.createdDate!;
      }
      return 1 << 62;
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
    final target =
        todo.dueDate ??
        (todo.createdDate != null && todo.createdDate! > 0
            ? DateTime.fromMillisecondsSinceEpoch(todo.createdDate!)
            : null);
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
          final rows = await executor.query(
            'todos',
            columns: ['is_completed', 'is_deleted'],
            where: 'uuid = ?',
            whereArgs: [draft.todoId],
            limit: 1,
          );
          if (rows.isEmpty ||
              rows.single['is_completed'] == 1 ||
              rows.single['is_deleted'] == 1) {
            throw const PlanAvailabilityException('待办已完成或失效，请选择未完成的待办');
          }
        }
      },
    );
  }

  Future<TodoPlanBlock> _saveDraft() async {
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
    if (_recommendation != null && _recommendationStale) {
      throw const PlanAvailabilityException('推荐时段已失效，请重新查找或手动修改时间');
    }
    final draft = _persistedBlock == null
        ? TodoPlanBlock(
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
    final saved = await _persist(draft, _recommendation);
    _persistedBlock = saved;
    _savedDraftRevision = _draftRevision;
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
    if (_busy) return;
    setState(() {
      _busy = true;
      _operationError = null;
    });
    try {
      if (!_focusStarted) await _saveDraft();
      if (mounted) Navigator.pop(context);
    } catch (error) {
      _reportError(error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveAndStartFocus() async {
    if (_busy) return;
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
        final todos = await db.query(
          'todos',
          where: 'uuid = ?',
          whereArgs: [block.todoId],
        );
        if (blocks.isEmpty ||
            blocks.single['version'] != block.version ||
            blocks.single['updated_at'] != block.updatedAt ||
            blocks.single['is_deleted'] == 1 ||
            todos.isEmpty ||
            todos.single['is_completed'] == 1 ||
            todos.single['is_deleted'] == 1) {
          throw const PlanAvailabilityException('规划或待办已变化，请读取最新记录');
        }
        todo = TodoItem.fromSql(todos.single)..id = block.todoId;
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
      navigator.pop();
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
    if (widget.block == null) return;
    await StorageService.deletePlanBlockGlobally(
      widget.username,
      widget.block!.id,
    );
    widget.onSaved();
    if (mounted) Navigator.pop(context);
  }

  Future<void> _skip() async {
    if (widget.block == null) return;
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
      fillColor: colors.surfaceContainerLow,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
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
                if (value == 'skip') _skip();
                if (value == 'delete') _delete();
              },
              itemBuilder: (_) => [
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
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.close, size: 22),
          ),
        ],
      ),
    );
  }

  Widget _form(double width, double scale, EdgeInsets padding) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final horizontalTimes = width >= 360 && scale < 1.7;
    return Padding(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
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
            onChanged: widget.recovery != null || !_hasSelectableTodos
                ? null
                : (value) {
                    if (value == null || value.startsWith('__todo_header_')) {
                      return;
                    }
                    setState(() {
                      _selectedTodoId = value;
                      _manualChange();
                    });
                    if (widget.autoFillEstimateOnTodoChange) {
                      _prefillEstimate(value);
                    }
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
          if (_estimatedMinutes != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                '${widget.autoRecommendTime ? '预计用时' : '历史估时'} ${formatMinutesChinese(_estimatedMinutes!)}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.primary,
                ),
              ),
            ),
          const SizedBox(height: 20),
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
              color: colors.surfaceContainerLow,
              borderRadius: BorderRadius.circular(16),
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
          const SizedBox(height: 16),
          if (_initialEstimatePending)
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
          else
            PlanAvailabilityPanel(
              username: widget.username,
              resultsOnly: widget.fullPage,
              autoLookupResults:
                  !widget.autoRecommendTime || _estimatedMinutes != null,
              todo: _selectedTodo,
              initialDate: _start,
              initialMinutes: _end.difference(_start).inMinutes,
              editingBlock: _persistedBlock,
              estimatedMinutes: _estimatedMinutes,
              loader: widget.availabilityLoader,
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
                _estimateSequence++;
                _draftRevision++;
                _recommendation = selection;
                _recommendationStale = false;
                _start = selection.slot.start;
                _end = selection.slot.end;
                _operationError = null;
              }),
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
          const SizedBox(height: 24),
          Text(
            '其他设置',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _remarkCtrl,
            onChanged: (_) => setState(() {
              _draftRevision++;
              _autoRecommendationPending = false;
            }),
            decoration: _fieldDecoration('备注（可选）'),
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 460 && scale < 1.6
                  ? 3
                  : (constraints.maxWidth >= 240 ? 2 : 1);
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
                  decoration: _fieldDecoration(label),
                  items: values
                      .map(
                        (item) => DropdownMenuItem(
                          value: item,
                          child: Text(
                            title(item),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: changed,
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
                      _draftRevision++;
                      _pomodoroMinutes = v ?? 25;
                    }),
                  ),
                  option(
                    '番茄轮数',
                    _pomodoroRounds,
                    [0, 1, 2, 3, 4, 5, 6],
                    (m) => m == 0 ? '按规划时长' : '$m 轮',
                    (v) => setState(() {
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
              _autoRecommendationPending ||
              (_selectedTodoId == null && !_focusStarted)
          ? null
          : _save,
      child: Text(_focusStarted ? '关闭' : '保存规划'),
    );
    final focus = OutlinedButton.icon(
      key: const ValueKey('plan-save-focus'),
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      onPressed:
          _busy ||
              _autoRecommendationPending ||
              (_selectedTodoId == null && !_focusStarted)
          ? null
          : _saveAndStartFocus,
      icon: const Icon(Icons.play_arrow_rounded, size: 20),
      label: Text(_focusStarted ? '重试更新专注状态' : '保存并开始专注'),
    );
    return Container(
      decoration: BoxDecoration(
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
                      Navigator.of(context).pop();
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
    canPop: !_busy,
    child: Scaffold(
      key: const ValueKey('plan-block-editor-page'),
      appBar: AppBar(title: Text(widget.recovery != null ? '重新安排' : '新建规划块')),
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
                  ignoring: _busy,
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
        canPop: !_busy,
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
                          ignoring: _busy,
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
