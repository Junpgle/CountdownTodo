part of '../time_log_screen.dart';

class _EntryModeToggle extends StatelessWidget {
  final _EntryMode mode;
  final ValueChanged<_EntryMode> onChanged;

  const _EntryModeToggle({required this.mode, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact =
            constraints.maxWidth.isFinite && constraints.maxWidth < 118;

        Widget item(_EntryMode value, String label, IconData icon) {
          final selected = mode == value;
          final color = value == _EntryMode.plan
              ? Theme.of(context).colorScheme.secondary
              : Theme.of(context).colorScheme.primary;
          return GestureDetector(
            onTap: () => onChanged(value),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: EdgeInsets.symmetric(
                horizontal: compact ? 1 : 9,
                vertical: 5,
              ),
              decoration: BoxDecoration(
                color: selected
                    ? color.withValues(alpha: 0.14)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    icon,
                    size: compact ? 10 : 12,
                    color: selected ? color : _TC.textHint(context),
                  ),
                  SizedBox(width: compact ? 2 : 4),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: compact ? 10 : 11,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                      color: selected ? color : _TC.textSub(context),
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        return Container(
          alignment: Alignment.center,
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            color: _TC.inputFill(context),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _TC.divider(context)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              item(_EntryMode.log, '补录', Icons.edit_calendar),
              item(_EntryMode.plan, '规划', Icons.event_note),
            ],
          ),
        );
      },
    );
  }
}

class _PlanEntrySheet extends StatefulWidget {
  final DateTime initialStart;
  final DateTime initialEnd;
  final String username;
  final List<TodoItem> todos;
  final List<TodoGroup> todoGroups;
  final void Function(TodoPlanBlock) onSave;
  final Future<void> Function(TodoPlanBlock block, TodoItem todo) onStartFocus;

  const _PlanEntrySheet({
    required this.initialStart,
    required this.initialEnd,
    required this.username,
    required this.todos,
    required this.todoGroups,
    required this.onSave,
    required this.onStartFocus,
  });

  @override
  State<_PlanEntrySheet> createState() => _PlanEntrySheetState();
}

class _PlanEntrySheetState extends State<_PlanEntrySheet> {
  late DateTime _start;
  late DateTime _end;
  late TextEditingController _remarkCtrl;
  String? _todoId;
  int _reminderMinutes = 5;
  late List<TodoItem> _sortedTodos;

  @override
  void initState() {
    super.initState();
    _start = widget.initialStart;
    _end = widget.initialEnd;
    _remarkCtrl = TextEditingController();
    _sortedTodos = _sortTodos(
      collapseRecurrenceSeriesForTodoPicker(widget.todos, now: _start),
      widget.todoGroups,
    );
    if (_sortedTodos.isNotEmpty) _todoId = _sortedTodos.first.id;
  }

  static List<TodoItem> _sortTodos(
    List<TodoItem> todos,
    List<TodoGroup> groups,
  ) {
    final groupIndices = <String, int>{};
    for (var index = 0; index < groups.length; index++) {
      final groupId = groups[index].id;
      if (!groupIndices.containsKey(groupId)) {
        groupIndices[groupId] = index;
      }
    }

    int groupRank(TodoItem todo) {
      final groupId = todo.groupId;
      if (groupId == null || groupId.isEmpty) return 1 << 30;
      return groupIndices[groupId] ?? (1 << 30) - 1;
    }

    int urgencyMs(TodoItem todo) {
      if (todo.dueDate != null) return todo.dueDate!.millisecondsSinceEpoch;
      if (todo.createdDate != null && todo.createdDate! > 0) {
        return todo.createdDate!;
      }
      return 1 << 62;
    }

    return List<TodoItem>.from(todos)..sort((a, b) {
      if (a.isDone != b.isDone) return a.isDone ? 1 : -1;
      final groupCompare = groupRank(a).compareTo(groupRank(b));
      if (groupCompare != 0) return groupCompare;
      final urgencyCompare = urgencyMs(a).compareTo(urgencyMs(b));
      if (urgencyCompare != 0) return urgencyCompare;
      return a.title.compareTo(b.title);
    });
  }

  @override
  void dispose() {
    _remarkCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickTime(bool start) async {
    final value = await showAppTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(start ? _start : _end),
    );
    if (value == null || !mounted) return;
    setState(() {
      if (start) {
        _start = DateTime(
          _start.year,
          _start.month,
          _start.day,
          value.hour,
          value.minute,
        );
      } else {
        _end = DateTime(
          _end.year,
          _end.month,
          _end.day,
          value.hour,
          value.minute,
        );
      }
    });
  }

  void _save() {
    final block = _buildBlock();
    if (block == null) return;
    widget.onSave(block);
  }

  TodoPlanBlock? _buildBlock() {
    if (_todoId == null) {
      AppSnackBars.showSnackBar(
        context,
        const SnackBar(content: Text('请先选择待办')),
      );
      return null;
    }
    if (!_end.isAfter(_start)) {
      AppSnackBars.showSnackBar(
        context,
        const SnackBar(content: Text('结束时间必须晚于开始时间')),
      );
      return null;
    }
    final todo = widget.todos.cast<TodoItem?>().firstWhere(
      (t) => t?.id == _todoId,
      orElse: () => null,
    );
    return TodoPlanBlock(
      todoId: _todoId!,
      titleSnapshot: todo?.title,
      startTime: _start.millisecondsSinceEpoch,
      endTime: _end.millisecondsSinceEpoch,
      plannedMinutes: _end.difference(_start).inMinutes,
      remark: _remarkCtrl.text.trim().isEmpty ? null : _remarkCtrl.text.trim(),
      reminderMinutes: _reminderMinutes,
    );
  }

  Future<void> _saveAndStartFocus() async {
    final block = _buildBlock();
    if (block == null) return;
    final todo = widget.todos.cast<TodoItem?>().firstWhere(
      (t) => t?.id == block.todoId,
      orElse: () => null,
    );
    if (todo == null) return;
    await widget.onStartFocus(block, todo);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final accent = colorScheme.secondary;
    final duration = _end.difference(_start).inMinutes;
    return OptionalLiquidGlassSheet(
      topRadius: 20,
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(context).bottom + 16,
        left: 20,
        right: 20,
        top: 20,
      ),
      fallbackDecoration: BoxDecoration(
        color: _TC.card(context),
        border: Border(top: BorderSide(color: _TC.divider(context))),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '添加规划',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: _TC.text(context),
                ),
              ),
              const Spacer(),
              Text(
                '$duration 分钟',
                style: TextStyle(
                  color: accent,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            '关联待办',
            style: TextStyle(
              fontSize: 9,
              color: _TC.textHint(context),
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            initialValue: _todoId,
            isExpanded: true,
            items: _sortedTodos
                .map(
                  (todo) => DropdownMenuItem(
                    value: todo.id,
                    child: Text(
                      todo.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                )
                .toList(),
            onChanged: (value) => setState(() => _todoId = value),
            decoration: InputDecoration(
              filled: true,
              fillColor: _TC.inputFill(context),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _TimePickerCard(
                  label: '开始时间',
                  dt: _start,
                  onTapTime: () => _pickTime(true),
                  onTapDate: () {},
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _TimePickerCard(
                  label: '结束时间',
                  dt: _end,
                  onTapTime: () => _pickTime(false),
                  onTapDate: () {},
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _remarkCtrl,
            style: TextStyle(color: _TC.text(context), fontSize: 13),
            decoration: InputDecoration(
              hintText: '规划备注（可选）',
              hintStyle: TextStyle(color: _TC.textHint(context)),
              filled: true,
              fillColor: _TC.inputFill(context),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Text(
                '提前提醒',
                style: TextStyle(fontSize: 13, color: _TC.textSub(context)),
              ),
              const Spacer(),
              DropdownButton<int>(
                value: _reminderMinutes,
                items: [0, 5, 10, 15, 30]
                    .map(
                      (m) => DropdownMenuItem(
                        value: m,
                        child: Text(m == 0 ? '不提醒' : '$m 分钟前'),
                      ),
                    )
                    .toList(),
                onChanged: (value) =>
                    setState(() => _reminderMinutes = value ?? 5),
              ),
            ],
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            height: 46,
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _saveAndStartFocus,
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('进入番茄钟'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _save,
                    style: _timeLogPrimaryActionStyle(
                      backgroundColor: accent,
                      foregroundColor: colorScheme.onSecondary,
                    ),
                    child: const Text(
                      '保存规划',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════
// 补录详情面板 (兼容新增和编辑模式)
// ══════════════════════════════════════════════════════════
class TimeLogEntrySheet extends StatefulWidget {
  final DateTime initialStart, initialEnd;
  final String? initialTagId;
  final List<PomodoroTag> tags;
  final List<TimeLogItem> timeLogs;
  final List<PomodoroRecord> pomodoros;
  final Future<TimeLogEditorSaveResult> Function(TimeLogItem) onSave;
  final TimeLogItem? existingLog;

  const TimeLogEntrySheet({
    super.key,
    required this.initialStart,
    required this.initialEnd,
    this.initialTagId,
    required this.tags,
    required this.timeLogs,
    required this.pomodoros,
    required this.onSave,
    this.existingLog,
  });
  @override
  State<TimeLogEntrySheet> createState() => _TimeLogEntrySheetState();
}

enum _TimeLogExitChoice { keepEditing, discard, save }

class _TimeLogEntrySheetState extends State<TimeLogEntrySheet> {
  late DateTime _start, _end;
  late String? _tagId;
  late TextEditingController _tc;
  late DateTime _baselineStart, _baselineEnd;
  late String? _baselineTagId;
  late String _baselineTitle;
  String _lastObservedTitle = '';
  bool? _lastCanPop;
  late String _draftId;
  late int _draftCreatedAt;
  TimeLogItem? _pendingSaveLog;
  String? _saveError;
  bool _isSaving = false;
  bool _isExitDialogOpen = false;
  bool _allowExit = false;
  double _handleDragDistance = 0;
  final GlobalKey _sheetKey = GlobalKey();
  OverlayEntry? _outsideTapEntry;

  bool get _hasUnsavedChanges =>
      _start.millisecondsSinceEpoch != _baselineStart.millisecondsSinceEpoch ||
      _end.millisecondsSinceEpoch != _baselineEnd.millisecondsSinceEpoch ||
      _tagId != _baselineTagId ||
      _tc.text != _baselineTitle;

  void _invalidatePendingSave() {
    _pendingSaveLog = null;
    _saveError = null;
  }

  void _onTitleChanged() {
    if (!mounted) return;
    final title = _tc.text;
    if (title == _lastObservedTitle) return;
    _lastObservedTitle = title;
    final hadSaveError = _saveError != null;
    _invalidatePendingSave();
    final canPop = _allowExit || (!_isSaving && !_hasUnsavedChanges);
    if (hadSaveError || canPop != _lastCanPop) {
      setState(() {});
    }
  }

  @override
  void initState() {
    super.initState();
    if (widget.existingLog != null) {
      final log = widget.existingLog!;
      _start = DateTime.fromMillisecondsSinceEpoch(log.startTime);
      _end = DateTime.fromMillisecondsSinceEpoch(log.endTime);
      _tagId = log.tagUuids.isNotEmpty ? log.tagUuids.first : null;
      _tc = TextEditingController(text: log.title);
    } else {
      _start = widget.initialStart;
      _end = widget.initialEnd;
      _tagId = widget.initialTagId;
      final tag = widget.tags.cast<PomodoroTag?>().firstWhere(
        (t) => t?.uuid == _tagId,
        orElse: () => null,
      );
      _tc = TextEditingController(text: tag?.name ?? '');
    }
    _baselineStart = _start;
    _baselineEnd = _end;
    _baselineTagId = _tagId;
    _baselineTitle = _tc.text;
    _lastObservedTitle = _tc.text;
    _draftId = widget.existingLog?.id ?? const Uuid().v4();
    _draftCreatedAt =
        widget.existingLog?.createdAt ?? DateTime.now().millisecondsSinceEpoch;
    _tc.addListener(_onTitleChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final entry = OverlayEntry(
        builder: (_) => Positioned.fill(
          child: _OutsideSheetTapRegion(
            sheetBounds: _sheetBounds,
            onOutsideTap: _onOutsideTap,
            child: const SizedBox.expand(),
          ),
        ),
      );
      _outsideTapEntry = entry;
      Overlay.of(context, rootOverlay: true).insert(entry);
    });
  }

  @override
  void dispose() {
    _outsideTapEntry?.remove();
    _tc.removeListener(_onTitleChanged);
    _tc.dispose();
    super.dispose();
  }

  Rect? _sheetBounds() {
    if (!mounted || ModalRoute.of(context)?.isCurrent != true) return null;
    final renderObject = _sheetKey.currentContext?.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) return null;
    return renderObject.localToGlobal(Offset.zero) & renderObject.size;
  }

  void _onOutsideTap(PointerDownEvent event) {
    if (!mounted || ModalRoute.of(context)?.isCurrent != true) return;
    final bounds = _sheetBounds();
    if (bounds == null || bounds.contains(event.position)) return;
    unawaited(_requestExit());
  }

  String _durLabel() {
    final m = _end.difference(_start).inMinutes;
    if (m <= 0) return '--';
    return m >= 60 ? '${m ~/ 60}h ${m % 60}m' : '${m}m';
  }

  Future<void> _pickTime(bool isStart) async {
    final t = await showAppTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(isStart ? _start : _end),
    );
    if (t == null || !mounted) return;
    _invalidatePendingSave();
    setState(() {
      if (isStart) {
        _start = DateTime(
          _start.year,
          _start.month,
          _start.day,
          t.hour,
          t.minute,
        );
      } else {
        _end = DateTime(_end.year, _end.month, _end.day, t.hour, t.minute);
      }
    });
  }

  Future<void> _pickDate(bool isStart) async {
    final now = DateTime.now();
    final firstDate = DateTime(2020);
    final lastDate = DateTime(now.year, now.month, now.day);
    final selectedDate = isStart ? _start : _end;
    final initialDate = selectedDate.isBefore(firstDate)
        ? firstDate
        : selectedDate.isAfter(lastDate)
        ? lastDate
        : selectedDate;
    final d = await showAppDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: firstDate,
      lastDate: lastDate,
    );
    if (d == null || !mounted) return;
    _invalidatePendingSave();
    setState(() {
      if (isStart) {
        _start = DateTime(d.year, d.month, d.day, _start.hour, _start.minute);
      } else {
        _end = DateTime(d.year, d.month, d.day, _end.hour, _end.minute);
      }
    });
  }

  TimeLogItem _buildPendingLog() {
    final pending = _pendingSaveLog;
    if (pending != null) return pending;

    final existing = widget.existingLog;
    final tagUuids = existing != null && _tagId == _baselineTagId
        ? List<String>.of(existing.tagUuids)
        : _tagId == null
        ? <String>[]
        : <String>[_tagId!];
    final tag = widget.tags.cast<PomodoroTag?>().firstWhere(
      (t) => t?.uuid == _tagId,
      orElse: () => null,
    );
    final log = TimeLogItem(
      id: _draftId,
      title: _tc.text.isNotEmpty ? _tc.text : (tag?.name ?? '未命名补录'),
      tagUuids: tagUuids,
      startTime: _start.millisecondsSinceEpoch,
      endTime: _end.millisecondsSinceEpoch,
      remark: existing?.remark,
      version: existing?.version ?? 1,
      createdAt: existing?.createdAt ?? _draftCreatedAt,
      isDeleted: existing?.isDeleted ?? false,
      deviceId: existing?.deviceId,
      teamUuid: existing?.teamUuid,
    );
    if (existing != null) log.markAsChanged();
    _pendingSaveLog = log;
    return log;
  }

  Future<void> _closeSheet() async {
    if (!_allowExit && mounted) setState(() => _allowExit = true);
    await WidgetsBinding.instance.endOfFrame;
    if (mounted) await Navigator.of(context).maybePop();
  }

  Future<void> _requestExit() async {
    if (!mounted || _isSaving || _isExitDialogOpen) return;
    if (!_hasUnsavedChanges) {
      await _closeSheet();
      return;
    }

    _isExitDialogOpen = true;
    final choice = await showDialog<_TimeLogExitChoice>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) => AlertDialog(
        title: const Text('保留这条时间日志？'),
        content: const Text('当前补录有尚未保存的修改。'),
        actions: [
          TextButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(_TimeLogExitChoice.keepEditing),
            child: const Text('继续编辑'),
          ),
          TextButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(_TimeLogExitChoice.discard),
            child: const Text('放弃修改'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(_TimeLogExitChoice.save),
            child: const Text('保存并退出'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    _isExitDialogOpen = false;

    switch (choice) {
      case _TimeLogExitChoice.discard:
        await _closeSheet();
      case _TimeLogExitChoice.save:
        await _save();
      case _TimeLogExitChoice.keepEditing:
      case null:
        break;
    }
  }

  Future<void> _save() async {
    if (_isSaving) return;
    if (!_end.isAfter(_start)) {
      AppSnackBars.showSnackBar(
        context,
        const SnackBar(content: Text('结束时间必须晚于开始时间')),
      );
      return;
    }
    if (widget.existingLog != null && !_hasUnsavedChanges) {
      await _closeSheet();
      return;
    }

    setState(() {
      _isSaving = true;
      _saveError = null;
    });
    try {
      final overlaps = TimeLogOverlapService.find(
        startTime: _start.millisecondsSinceEpoch,
        endTime: _end.millisecondsSinceEpoch,
        timeLogs: widget.timeLogs,
        pomodoros: widget.pomodoros,
        excludingTimeLogId: widget.existingLog?.id,
      );
      final isFuture = _end.isAfter(DateTime.now());
      if (overlaps.isNotEmpty || isFuture) {
        final confirmed = await showTimeLogSaveConfirmation(
          context: context,
          start: _start,
          end: _end,
          overlaps: overlaps,
          isFuture: isFuture,
          isEditing: widget.existingLog != null,
        );
        if (confirmed != true || !mounted) return;
      }

      final result = await widget.onSave(_buildPendingLog());
      if (!mounted) return;
      if (!result.isSaved) {
        setState(() {
          _saveError =
              result.disposition == TimeLogEditorSaveDisposition.unknown
              ? '保存结果暂时无法核实。输入已保留，再次保存会继续使用同一条记录。'
              : '保存失败，输入已保留。请检查后重试。';
        });
        return;
      }
      await _closeSheet();
    } catch (error) {
      if (mounted) {
        setState(() => _saveError = '保存失败，输入已保留。请检查后重试。');
        debugPrint('Time log editor save failed: $error');
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Widget _buildDragHandle(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return GestureDetector(
      key: const ValueKey('time-log-dismiss-handle'),
      behavior: HitTestBehavior.opaque,
      onVerticalDragStart: (_) => _handleDragDistance = 0,
      onVerticalDragUpdate: (details) {
        _handleDragDistance += details.delta.dy;
      },
      onVerticalDragEnd: (details) {
        final shouldClose =
            _handleDragDistance > 40 || (details.primaryVelocity ?? 0) > 500;
        _handleDragDistance = 0;
        if (shouldClose) unawaited(_requestExit());
      },
      child: SizedBox(
        height: 24,
        child: Center(
          child: Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final accent = colorScheme.primary;
    final canPop = _allowExit || (!_isSaving && !_hasUnsavedChanges);
    _lastCanPop = canPop;
    return PopScope<Object?>(
      canPop: canPop,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) unawaited(_requestExit());
      },
      child: OptionalLiquidGlassSheet(
        key: _sheetKey,
        topRadius: 20,
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom + 16,
          left: 20,
          right: 20,
          top: 20,
        ),
        fallbackDecoration: BoxDecoration(
          color: _TC.card(context),
          border: Border(top: BorderSide(color: _TC.divider(context))),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildDragHandle(context),
              Row(
                children: [
                  Text(
                    widget.existingLog != null ? '编辑记录' : '补录事件',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: _TC.text(context),
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: '关闭补录',
                    onPressed: _isSaving ? null : _requestExit,
                    icon: const Icon(Icons.close_rounded, size: 20),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.cdtSuccess
                          .withValues(alpha: 0.12),
                      border: Border.all(
                        color: Theme.of(context).colorScheme.cdtSuccess
                            .withValues(alpha: 0.35),
                      ),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      _durLabel(),
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.cdtSuccess,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                'CATEGORY',
                style: TextStyle(
                  fontSize: 9,
                  color: _TC.textHint(context),
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: widget.tags.map((t) {
                  final c = hexColor(t.color);
                  final sel = _tagId == t.uuid;
                  return GestureDetector(
                    onTap: _isSaving
                        ? null
                        : () {
                            _invalidatePendingSave();
                            setState(() => _tagId = t.uuid);
                            _tc.text = t.name;
                          },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 7,
                      ),
                      decoration: BoxDecoration(
                        color: sel
                            ? c.withValues(alpha: 0.2)
                            : c.withValues(alpha: 0.06),
                        border: Border.all(
                          color: sel ? c : c.withValues(alpha: 0.3),
                        ),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        t.name,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: sel ? c : c.withValues(alpha: 0.7),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),
              Text(
                'TITLE',
                style: TextStyle(
                  fontSize: 9,
                  color: _TC.textHint(context),
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 6),
              TextField(
                key: const ValueKey('time-log-title'),
                enabled: !_isSaving,
                controller: _tc,
                style: TextStyle(color: _TC.text(context), fontSize: 13),
                decoration: InputDecoration(
                  hintText: '事件名称（留空使用标签名）',
                  hintStyle: TextStyle(
                    color: _TC.textHint(context),
                    fontSize: 13,
                  ),
                  filled: true,
                  fillColor: _TC.inputFill(context),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: _TC.divider(context)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: _TC.divider(context)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: accent),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _TimePickerCard(
                      label: '开始时间',
                      dt: _start,
                      onTapTime: _isSaving ? () {} : () => _pickTime(true),
                      onTapDate: _isSaving ? () {} : () => _pickDate(true),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _TimePickerCard(
                      label: '结束时间',
                      dt: _end,
                      onTapTime: _isSaving ? () {} : () => _pickTime(false),
                      onTapDate: _isSaving ? () {} : () => _pickDate(false),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              if (_saveError != null) ...[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.error_outline_rounded,
                      size: 18,
                      color: colorScheme.error,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _saveError!,
                        style: TextStyle(
                          color: colorScheme.error,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
              ],
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: _isSaving ? null : _save,
                  style: _timeLogPrimaryActionStyle(
                    backgroundColor: accent,
                    foregroundColor: colorScheme.onPrimary,
                  ),
                  child: _isSaving
                      ? const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                            SizedBox(width: 10),
                            Text('保存中…'),
                          ],
                        )
                      : const Text(
                          '保存记录',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TimePickerCard extends StatelessWidget {
  final String label;
  final DateTime dt;
  final VoidCallback onTapTime, onTapDate;
  const _TimePickerCard({
    required this.label,
    required this.dt,
    required this.onTapTime,
    required this.onTapDate,
  });
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTapTime,
    child: Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _TC.inputFill(context),
        border: Border.all(color: _TC.divider(context)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 9,
              color: _TC.textHint(context),
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 4),
          GestureDetector(
            onTap: onTapDate,
            child: Text(
              _timeLogComponentDateFormat('MM月dd日').format(dt),
              style: TextStyle(fontSize: 11, color: _TC.textSub(context)),
            ),
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 6,
            runSpacing: 0,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                _timeLogComponentDateFormat('HH:mm').format(dt),
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: _TC.text(context),
                ),
              ),
              Icon(Icons.access_time, size: 14, color: _TC.textHint(context)),
            ],
          ),
        ],
      ),
    ),
  );
}
