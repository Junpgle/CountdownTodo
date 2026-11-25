part of '../todo_plan_screen.dart';

class _PlanActualRecordIndex {
  late final Map<String, int> _secondsByPlanBlockId;

  _PlanActualRecordIndex(
    List<TodoPlanBlock> blocks,
    Iterable<PomodoroRecord> records,
  ) {
    final actualSeconds = PomodoroPlanFocusAllocator.actualSecondsByBlock(
      blocks: blocks,
      records: records.toList(),
    );
    _secondsByPlanBlockId = {
      for (var index = 0; index < blocks.length; index++)
        blocks[index].uuid: actualSeconds[index],
    };
  }

  int secondsFor(TodoPlanBlock block) =>
      _secondsByPlanBlockId[block.uuid] ?? max(0, block.actualFocusSeconds);
}

class _PlanGridView extends StatefulWidget {
  final DateTime date;
  final List<TodoPlanBlock> blocks;
  final Set<String> mappedBlockIds;
  final List<TodoItem> todos;
  final List<TodoGroup> todoGroups;
  final List<CourseItem> courses;
  final List<PomodoroTag> tags;
  final List<PomodoroRecord> pomodoroRecords;
  final List<TimeLogItem> timeLogs;
  final HabitChallengePlanningSnapshot habitChallenge;
  final String username;
  final String? initialTodoId;
  final VoidCallback onRefresh;
  final PlanDragService dragService;
  final bool dragBusy;
  final String? focusingPlanId;
  final Future<void> Function(PlanDragSnapshot, PlanDragTimes) onSaveDrag;
  final VoidCallback? onUndoDrag;

  const _PlanGridView({
    super.key,
    required this.date,
    required this.blocks,
    required this.mappedBlockIds,
    required this.todos,
    required this.todoGroups,
    required this.courses,
    required this.tags,
    required this.pomodoroRecords,
    required this.timeLogs,
    this.habitChallenge = const HabitChallengePlanningSnapshot(),
    required this.username,
    this.initialTodoId,
    required this.onRefresh,
    required this.dragService,
    required this.dragBusy,
    required this.focusingPlanId,
    required this.onSaveDrag,
    required this.onUndoDrag,
  });

  @override
  State<_PlanGridView> createState() => _PlanGridViewState();
}

class _PlanGridViewState extends State<_PlanGridView>
    with WidgetsBindingObserver {
  final _manualHostKey = GlobalKey<PlanManualCompletionHostState>();
  final GlobalKey _planGridPomodoroSourceKey = GlobalKey();
  final Map<String, GlobalKey> _planBlockSourceKeys = {};
  late final _manualCompletion = PlanManualCompletionService(
    clock: () => widget.dragService.now,
  );
  late Map<String, TodoItem> _todoById;
  int? _dragStartBlock;
  int? _dragEndBlock;
  int _minutesPerBlock = 15;
  PlanDragSnapshot? _gesture;
  PlanDragTimes? _preview;
  PlanDragKind? _gestureKind;
  Offset? _pointerOrigin;
  bool _saving = false;
  List<Widget>? _gridLinesCache;
  double? _gridLinesWidth;
  double? _gridLinesHourHeight;
  int? _gridLinesBlocksPerHour;
  List<Widget>? _hourLabelsCache;
  double? _hourLabelsHourHeight;
  DateTime? _executionEntriesDate;
  List<PomodoroRecord>? _executionRecordsSource;
  List<TimeLogItem>? _executionLogsSource;
  List<PlanExecutionEntry>? _executionEntriesCache;
  List<int> _hourlyExecutionLaneCountsCache = List<int>.filled(24, 1);

  @override
  void initState() {
    super.initState();
    _rebuildItemIndexes();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed && !_saving) _cancelGesture();
  }

  @override
  void didUpdateWidget(covariant _PlanGridView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.todos, widget.todos)) {
      _rebuildItemIndexes();
    }
    final gesture = _gesture;
    if (gesture == null || _saving) return;
    final latest = widget.blocks
        .where((b) => b.id == gesture.block.id)
        .firstOrNull;
    if (latest == null ||
        !gesture.matches(latest) ||
        widget.focusingPlanId == latest.id ||
        widget.dragBusy) {
      _gesture = null;
      _preview = null;
      _gestureKind = null;
      _pointerOrigin = null;
    }
  }

  void _rebuildItemIndexes() {
    final todoById = <String, TodoItem>{};
    for (final todo in widget.todos) {
      todoById.putIfAbsent(todo.id, () => todo);
    }
    _todoById = todoById;
  }

  GlobalKey _sourceKeyFor(TodoPlanBlock block) =>
      _planBlockSourceKeys.putIfAbsent(block.id, GlobalKey.new);

  List<PlanExecutionEntry> _executionEntries() {
    final cachedEntries = _executionEntriesCache;
    final cachedDate = _executionEntriesDate;
    if (cachedEntries != null &&
        cachedDate != null &&
        DateUtils.isSameDay(cachedDate, widget.date) &&
        identical(_executionRecordsSource, widget.pomodoroRecords) &&
        identical(_executionLogsSource, widget.timeLogs)) {
      return cachedEntries;
    }

    final entries = PlanExecutionEntry.forDay(
      widget.date,
      widget.pomodoroRecords,
      widget.timeLogs,
    );
    _executionEntriesDate = widget.date;
    _executionRecordsSource = widget.pomodoroRecords;
    _executionLogsSource = widget.timeLogs;
    _executionEntriesCache = entries;
    _hourlyExecutionLaneCountsCache =
        PlanExecutionEntry.hourlyTimelineLaneCounts(widget.date, entries);
    return entries;
  }

  void _beginGesture(TodoPlanBlock block, PlanDragKind kind, Offset position) {
    if (widget.dragBusy || _saving || _gesture != null) return;
    try {
      final snapshot = widget.dragService.capture(
        widget.username,
        widget.date,
        block,
      );
      setState(() {
        _gesture = snapshot;
        _gestureKind = kind;
        _pointerOrigin = position;
        _preview = PlanDragTimes(
          DateTime.fromMillisecondsSinceEpoch(block.startTime),
          DateTime.fromMillisecondsSinceEpoch(block.endTime),
        );
        _dragStartBlock = null;
        _dragEndBlock = null;
      });
    } on PlanDragException catch (error) {
      AppSnackBars.showSnackBar(
        context,
        SnackBar(content: Text(error.message)),
      );
    }
  }

  void _updateGesture(Offset position, double width, double hourH) {
    final original = _gesture;
    final origin = _pointerOrigin;
    final kind = _gestureKind;
    if (original == null || origin == null || kind == null || _saving) return;
    final delta = position - origin;
    final minutes =
        delta.dx / width * 60 +
        (kind == PlanDragKind.move ? delta.dy / hourH * 60 : 0);
    final block = original.block;
    final times = PlanDragGeometry.adjust(
      date: original.date,
      original: PlanDragTimes(
        DateTime.fromMillisecondsSinceEpoch(block.startTime),
        DateTime.fromMillisecondsSinceEpoch(block.endTime),
      ),
      deltaMinutes: minutes,
      step: _minutesPerBlock,
      kind: kind,
    );
    setState(() => _preview = times);
  }

  void _cancelGesture() {
    if (!mounted || _saving) return;
    setState(() {
      _gesture = null;
      _preview = null;
      _gestureKind = null;
      _pointerOrigin = null;
      _dragStartBlock = null;
      _dragEndBlock = null;
    });
  }

  Future<void> _finishGesture() async {
    final original = _gesture;
    final times = _preview;
    if (_saving || original == null || times == null) return;
    if (times.matches(original.block)) {
      _cancelGesture();
      return;
    }
    setState(() => _saving = true);
    try {
      await widget.onSaveDrag(original, times);
    } finally {
      if (mounted) {
        _saving = false;
        _cancelGesture();
      }
    }
  }

  int get _blocksPerHour => 60 ~/ _minutesPerBlock;

  int? _getIndex(Offset pos, double width, double hourH) {
    if (pos.dy < 0 || pos.dy > 24 * hourH) return null;
    final hour = (pos.dy / hourH).floor().clamp(0, 23);
    final blockInHour = ((pos.dx / width) * _blocksPerHour).floor().clamp(
      0,
      _blocksPerHour - 1,
    );
    return hour * _blocksPerHour + blockInHour;
  }

  void _clearRecordSelection() {
    if (_dragStartBlock == null && _dragEndBlock == null) return;
    setState(() {
      _dragStartBlock = null;
      _dragEndBlock = null;
    });
  }

  void _handleDragStart(Offset pos, double width, double hourH) {
    if (widget.dragBusy || _gesture != null) return;
    final idx = _getIndex(pos, width, hourH);
    if (idx != null) {
      setState(() {
        _dragStartBlock = idx;
        _dragEndBlock = idx;
      });
    }
  }

  void _handleDragUpdate(Offset pos, double width, double hourH) {
    final idx = _getIndex(pos, width, hourH);
    if (idx != null) {
      setState(() {
        _dragEndBlock = idx;
      });
    }
  }

  void _handleDragEnd({required bool autoFillEstimateOnTodoChange}) async {
    if (_dragStartBlock == null || _dragEndBlock == null) return;

    final startIdx = min(_dragStartBlock!, _dragEndBlock!);
    final endIdx = max(_dragStartBlock!, _dragEndBlock!);

    final startTime = widget.date.add(
      Duration(minutes: startIdx * _minutesPerBlock),
    );
    final endTime = widget.date.add(
      Duration(minutes: (endIdx + 1) * _minutesPerBlock),
    );

    setState(() {
      _dragStartBlock = null;
      _dragEndBlock = null;
    });

    _showAddBlockSheet(
      startTime,
      endTime,
      autoFillEstimateOnTodoChange: autoFillEstimateOnTodoChange,
    );
  }

  void _showAddBlockSheet(
    DateTime startTime,
    DateTime endTime, {
    required bool autoFillEstimateOnTodoChange,
  }) {
    showPlanBlockEditorPage(
      context: context,
      builder: (context) => PlanBlockEditorSheet(
        fullPage: true,
        startTime: startTime,
        endTime: endTime,
        todos: widget.todos,
        todoGroups: widget.todoGroups,
        username: widget.username,
        initialTodoId: widget.initialTodoId,
        autoFillEstimateOnTodoChange: autoFillEstimateOnTodoChange,
        onSaved: widget.onRefresh,
        openPomodoro: (planBlock, todo) => PageTransitions.pushFromRect<void>(
          context: context,
          sourceKey: _planGridPomodoroSourceKey,
          placeholderIcon: Icons.timer_outlined,
          page: PomodoroScreen(
            username: widget.username,
            initialEntry: PomodoroEntryIntent.forPlanBlock(
              boundTodo: todo,
              planBlock: planBlock,
            ),
          ),
        ),
        onManageDrafts: () => openPlanEditorDrafts(
          context,
          widget.username,
          onSaved: widget.onRefresh,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final executionEntries = _executionEntries();
    final hourlyExecutionLaneCounts = _hourlyExecutionLaneCountsCache;

    return PlanManualCompletionHost(
      key: _manualHostKey,
      onRefresh: widget.onRefresh,
      child: Column(
        children: [
          _buildGranularityBar(),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final totalH = constraints.maxHeight;
                final hourH = totalH / 24;
                final gridW = constraints.maxWidth - kTimeAxisW;

                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 时间轴
                    SizedBox(
                      width: kTimeAxisW,
                      height: totalH,
                      child: Stack(children: _buildHourLabels(hourH)),
                    ),
                    // 网格
                    Expanded(
                      child: GestureDetector(
                        key: _planGridPomodoroSourceKey,
                        onPanStart: (d) =>
                            _handleDragStart(d.localPosition, gridW, hourH),
                        onPanUpdate: (d) =>
                            _handleDragUpdate(d.localPosition, gridW, hourH),
                        onPanEnd: (d) =>
                            _handleDragEnd(autoFillEstimateOnTodoChange: false),
                        onPanCancel: _cancelGesture,
                        onTapDown: (d) =>
                            _handleDragStart(d.localPosition, gridW, hourH),
                        onTapUp: (d) =>
                            _handleDragEnd(autoFillEstimateOnTodoChange: true),
                        onTapCancel: _clearRecordSelection,
                        child: Container(
                          height: totalH,
                          decoration: BoxDecoration(
                            border: Border(
                              left: BorderSide(
                                color: Colors.grey.withValues(alpha: 0.1),
                              ),
                            ),
                          ),
                          child: Stack(
                            children: [
                              ..._buildGridLines(gridW, hourH),
                              ...widget.blocks.expand(
                                (block) => _buildBlockItems(
                                  block,
                                  gridW,
                                  hourH,
                                  hourlyExecutionLaneCounts,
                                ),
                              ),
                              if (_gesture != null && _preview != null)
                                ..._buildBlockItems(
                                  _gesture!.block
                                    ..startTime =
                                        _preview!.start.millisecondsSinceEpoch
                                    ..endTime =
                                        _preview!.end.millisecondsSinceEpoch
                                    ..plannedMinutes = _preview!.minutes,
                                  gridW,
                                  hourH,
                                  hourlyExecutionLaneCounts,
                                  previewOnly: true,
                                ),
                              if (executionEntries.isNotEmpty)
                                Positioned.fill(
                                  child: PlanExecutionTimelineLayer(
                                    date: widget.date,
                                    entries: executionEntries,
                                    tags: widget.tags,
                                    hourHeight: hourH,
                                    onRecordInteraction: _clearRecordSelection,
                                  ),
                                ),
                              if (_dragStartBlock != null &&
                                  _dragEndBlock != null)
                                ..._buildDraggingBlocks(gridW, hourH),
                              _buildNowLine(gridW, hourH),
                              if (_preview != null)
                                Positioned(
                                  left: 8,
                                  right: 8,
                                  top: _preview!.start.hour >= 12 ? 8 : null,
                                  bottom: _preview!.start.hour < 12 ? 8 : null,
                                  child: IgnorePointer(
                                    child: Material(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .secondaryContainer,
                                      borderRadius: BorderRadius.circular(12),
                                      child: Padding(
                                        padding: const EdgeInsets.all(8),
                                        child: Text(
                                          _saving
                                              ? '正在保存调整…'
                                              : '${AppTimeFormats.dateFormatter('HH:mm').format(_preview!.start)} → '
                                                    '${AppTimeFormats.dateFormatter('HH:mm').format(_preview!.end)} · ${_preview!.minutes}分钟',
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                            color: Theme.of(context)
                                                .colorScheme
                                                .onSecondaryContainer,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGranularityBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
      child: Row(
        children: [
          Expanded(
            child: Wrap(
              spacing: 6,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                const Text('粒度', style: TextStyle(fontSize: 12)),
                const SizedBox(width: 8),
                SegmentedButton<int>(
                  style: ButtonStyle(
                    backgroundBuilder: (context, states, child) =>
                        child ?? const SizedBox.shrink(),
                    backgroundColor: WidgetStateProperty.resolveWith((states) {
                      return states.contains(WidgetState.selected)
                          ? Theme.of(context).colorScheme.primaryContainer
                          : Theme.of(context).colorScheme.surfaceContainerLow;
                    }),
                    foregroundColor: WidgetStateProperty.resolveWith((states) {
                      return states.contains(WidgetState.selected)
                          ? Theme.of(context).colorScheme.onPrimaryContainer
                          : Theme.of(context).colorScheme.onSurfaceVariant;
                    }),
                    overlayColor: WidgetStatePropertyAll(
                      Theme.of(context).colorScheme.primary
                          .withValues(alpha: 0.12),
                    ),
                    shape: const WidgetStatePropertyAll(
                      RoundedRectangleBorder(
                        borderRadius: BorderRadius.all(Radius.circular(12)),
                      ),
                    ),
                    padding: const WidgetStatePropertyAll(
                      EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                  ),
                  segments: const [
                    ButtonSegment(value: 5, label: Text('5')),
                    ButtonSegment(value: 10, label: Text('10')),
                    ButtonSegment(value: 15, label: Text('15')),
                    ButtonSegment(value: 30, label: Text('30')),
                  ],
                  selected: {_minutesPerBlock},
                  showSelectedIcon: false,
                  onSelectionChanged: (value) {
                    if (widget.dragBusy || _gesture != null) return;
                    setState(() {
                      _minutesPerBlock = value.first;
                      _dragStartBlock = null;
                      _dragEndBlock = null;
                    });
                  },
                ),
                const SizedBox(width: 6),
                Text(
                  '分钟',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
              ],
            ),
          ),
          if (widget.dragBusy)
            const SizedBox(
              width: 36,
              height: 24,
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
          if (!widget.dragBusy && widget.onUndoDrag != null)
            IconButton(
              key: const ValueKey('plan-drag-undo'),
              tooltip: '撤销上次调整',
              onPressed: widget.onUndoDrag,
              icon: const Icon(Icons.undo_rounded),
            ),
        ],
      ),
    );
  }

  List<Widget> _buildGridLines(double width, double hourH) {
    final blocksPerHour = _blocksPerHour;
    final cachedLines = _gridLinesCache;
    if (cachedLines != null &&
        _gridLinesWidth == width &&
        _gridLinesHourHeight == hourH &&
        _gridLinesBlocksPerHour == blocksPerHour) {
      return cachedLines;
    }

    final lines = <Widget>[];
    for (int h = 0; h <= 24; h++) {
      lines.add(
        Positioned(
          top: h * hourH,
          left: 0,
          right: 0,
          height: 1,
          child: Container(color: Colors.grey.withValues(alpha: 0.06)),
        ),
      );
    }
    for (int c = 1; c < blocksPerHour; c++) {
      lines.add(
        Positioned(
          top: 0,
          bottom: 0,
          left: width * c / blocksPerHour,
          width: 0.5,
          child: Container(color: Colors.grey.withValues(alpha: 0.05)),
        ),
      );
    }

    // 隐藏的指引锚点 (9:00 - 10:00)
    lines.add(
      Positioned(
        top: 9 * hourH,
        left: width / 3,
        width: width / 3,
        height: hourH,
        child: SizedBox(key: planDragKey),
      ),
    );

    _gridLinesCache = lines;
    _gridLinesWidth = width;
    _gridLinesHourHeight = hourH;
    _gridLinesBlocksPerHour = blocksPerHour;
    return lines;
  }

  List<Widget> _buildHourLabels(double hourH) {
    final cachedLabels = _hourLabelsCache;
    if (cachedLabels != null && _hourLabelsHourHeight == hourH) {
      return cachedLabels;
    }
    final labels = List<Widget>.generate(
      24,
      (hour) => Positioned(
        top: hour * hourH + 1,
        right: 6,
        height: max(1.0, hourH - 1),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerRight,
          child: Text(
            '${hour.toString().padLeft(2, '0')}:00',
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w600,
              color: Colors.grey.withValues(alpha: 0.66),
            ),
          ),
        ),
      ),
    );
    _hourLabelsCache = labels;
    _hourLabelsHourHeight = hourH;
    return labels;
  }
}
