part of 'time_log_screen.dart';

ButtonStyle _timeLogPrimaryActionStyle({
  required Color backgroundColor,
  required Color foregroundColor,
  EdgeInsetsGeometry? padding,
  MaterialTapTargetSize? tapTargetSize,
}) => ButtonStyle(
  backgroundColor: WidgetStatePropertyAll(backgroundColor),
  backgroundBuilder: (context, states, child) =>
      child ?? const SizedBox.shrink(),
  foregroundColor: WidgetStatePropertyAll(foregroundColor),
  overlayColor: WidgetStatePropertyAll(foregroundColor.withValues(alpha: 0.12)),
  side: const WidgetStatePropertyAll(BorderSide.none),
  surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
  shadowColor: const WidgetStatePropertyAll(Colors.transparent),
  elevation: const WidgetStatePropertyAll(0),
  padding: padding == null ? null : WidgetStatePropertyAll(padding),
  tapTargetSize: tapTargetSize,
  shape: WidgetStatePropertyAll(
    RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
  ),
);

class _OutsideSheetTapRegion extends SingleChildRenderObjectWidget {
  const _OutsideSheetTapRegion({
    required this.sheetBounds,
    required this.onOutsideTap,
    super.child,
  });

  final Rect? Function() sheetBounds;
  final ValueChanged<PointerDownEvent> onOutsideTap;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _OutsideSheetTapRenderObject(sheetBounds, onOutsideTap);

  @override
  void updateRenderObject(
    BuildContext context,
    _OutsideSheetTapRenderObject renderObject,
  ) {
    renderObject
      ..sheetBounds = sheetBounds
      ..onOutsideTap = onOutsideTap;
  }
}

class _OutsideSheetTapRenderObject extends RenderProxyBox {
  _OutsideSheetTapRenderObject(this.sheetBounds, this.onOutsideTap);

  Rect? Function() sheetBounds;
  ValueChanged<PointerDownEvent> onOutsideTap;

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    final bounds = sheetBounds();
    if (bounds == null || bounds.contains(localToGlobal(position))) {
      return false;
    }
    return super.hitTest(result, position: position);
  }

  @override
  bool hitTestSelf(Offset position) => true;

  @override
  void handleEvent(PointerEvent event, BoxHitTestEntry entry) {
    if (event is PointerDownEvent) onOutsideTap(event);
  }
}

// ══════════════════════════════════════════════════════════
// 日视图 — 补录模式（网格拖拽选时间段）
// ══════════════════════════════════════════════════════════
class _DayView extends StatefulWidget {
  final DateTime date;
  final bool crossDay;
  final List<TimeLogItem> logs;
  final List<TodoPlanBlock> planBlocks;
  final List<TimeLogMappedSchedule> schedules;
  final List<PomodoroRecord> pomodoros;
  final List<PomodoroTag> tags;
  final List<TodoItem> todos;
  final List<TodoGroup> todoGroups;
  final String username;
  final _EntryMode entryMode;
  final VoidCallback onBack;
  final ValueChanged<_EntryMode> onEntryModeChanged;
  final ValueChanged<bool> onCrossDayChanged;
  final Future<TimeLogEditorSaveResult> Function(TimeLogItem) onSaveLog;
  final void Function(TodoPlanBlock) onSavePlanBlock;
  final void Function(PomodoroRecord) onPomodoroTap;
  final void Function(String) onDeleteLog;
  final void Function(String) onDeletePlanBlock;

  const _DayView({
    required this.date,
    required this.crossDay,
    required this.logs,
    required this.planBlocks,
    this.schedules = const [],
    required this.pomodoros,
    required this.tags,
    required this.todos,
    required this.todoGroups,
    required this.username,
    required this.entryMode,
    required this.onBack,
    required this.onEntryModeChanged,
    required this.onCrossDayChanged,
    required this.onSaveLog,
    required this.onSavePlanBlock,
    required this.onPomodoroTap,
    required this.onDeleteLog,
    required this.onDeletePlanBlock,
  });

  @override
  State<_DayView> createState() => _DayViewState();
}

class _DayViewState extends State<_DayView> {
  final GlobalKey _pomodoroEntrySourceKey = GlobalKey();
  int _minutesPerBlock = 15;
  int? _dragStart, _dragEnd;
  String? _selectedTagId;
  List<PomodoroTag>? _tagIndexSource;
  List<String>? _tagUuidSnapshot;
  Map<String, int> _tagIndicesByUuid = const {};
  List<TimeLogItem>? _dayLogsSource;
  List<TodoPlanBlock>? _dayPlanBlocksSource;
  List<TimeLogMappedSchedule>? _daySchedulesSource;
  List<PomodoroRecord>? _dayPomodorosSource;
  int? _dayRecordsStartMs;
  int? _dayRecordsEndMs;
  List<TimeLogItem> _dayLogs = const [];
  List<TodoPlanBlock> _dayPlanBlocks = const [];
  List<TimeLogMappedSchedule> _daySchedules = const [];
  List<PomodoroRecord> _dayPomodoros = const [];

  @override
  void initState() {
    super.initState();
    if (widget.tags.isNotEmpty) _selectedTagId = widget.tags.first.uuid;
  }

  int get _bpr => 60 ~/ _minutesPerBlock;
  int get _totalBlocks => 24 * _bpr;
  int get _ss =>
      _dragStart != null && _dragEnd != null ? min(_dragStart!, _dragEnd!) : 0;
  int get _se =>
      _dragStart != null && _dragEnd != null ? max(_dragStart!, _dragEnd!) : 0;
  int get _durMin =>
      _dragStart != null ? (_se - _ss + 1) * _minutesPerBlock : 0;

  DateTime get _gridStart => _dayStart(widget.date);

  void _ensureDayRecords() {
    final gridStartMs = _gridStart.millisecondsSinceEpoch;
    final gridEndMs = _dayEndMs(_gridStart);
    if (identical(_dayLogsSource, widget.logs) &&
        identical(_dayPlanBlocksSource, widget.planBlocks) &&
        identical(_daySchedulesSource, widget.schedules) &&
        identical(_dayPomodorosSource, widget.pomodoros) &&
        _dayRecordsStartMs == gridStartMs &&
        _dayRecordsEndMs == gridEndMs) {
      return;
    }

    _dayLogsSource = widget.logs;
    _dayPlanBlocksSource = widget.planBlocks;
    _daySchedulesSource = widget.schedules;
    _dayPomodorosSource = widget.pomodoros;
    _dayRecordsStartMs = gridStartMs;
    _dayRecordsEndMs = gridEndMs;
    _dayLogs = [
      for (final log in widget.logs)
        if (log.endTime > gridStartMs && log.startTime < gridEndMs) log,
    ];
    _dayPlanBlocks = [
      for (final block in widget.planBlocks)
        if (block.endTime > gridStartMs && block.startTime < gridEndMs) block,
    ];
    _daySchedules = [
      for (final schedule in widget.schedules)
        if (schedule.endTime > gridStartMs && schedule.startTime < gridEndMs)
          schedule,
    ];
    _dayPomodoros = [
      for (final pomodoro in widget.pomodoros)
        if ((pomodoro.endTime ??
                    (pomodoro.startTime + pomodoro.effectiveDuration * 1000)) >
                gridStartMs &&
            pomodoro.startTime < gridEndMs)
          pomodoro,
    ];
  }

  Map<String, int> _tagIndicesFor(List<PomodoroTag> tags) {
    final cachedUuids = _tagUuidSnapshot;
    if (identical(_tagIndexSource, tags) &&
        cachedUuids != null &&
        cachedUuids.length == tags.length) {
      var uuidsUnchanged = true;
      for (var index = 0; index < tags.length; index++) {
        if (cachedUuids[index] != tags[index].uuid) {
          uuidsUnchanged = false;
          break;
        }
      }
      if (uuidsUnchanged) return _tagIndicesByUuid;
    }

    _tagIndexSource = tags;
    _tagUuidSnapshot = tags.map((tag) => tag.uuid).toList(growable: false);
    return _tagIndicesByUuid = _DayGridPainter._buildTagIndices(tags);
  }

  PomodoroTag? _firstPomodoroTagForUuids(
    List<String> uuids,
    Map<String, int> tagIndicesByUuid,
  ) {
    int? firstIndex;
    for (final uuid in uuids) {
      final index = tagIndicesByUuid[uuid];
      if (index != null && (firstIndex == null || index < firstIndex)) {
        firstIndex = index;
      }
    }
    return firstIndex == null ? null : widget.tags[firstIndex];
  }

  int? _getIndex(Offset pos, double width, double hourH) {
    final bw = width / _bpr;
    if (pos.dy < 0 || pos.dy > 24 * hourH) return null;
    final hr = (pos.dy / hourH).floor().clamp(0, 23);
    final col = (pos.dx / bw).floor().clamp(0, _bpr - 1);
    return (hr * _bpr + col).clamp(0, _totalBlocks - 1);
  }

  void _openEntry() {
    if (_dragStart == null) return;
    final gs = _gridStart;
    final st = gs.add(Duration(minutes: _ss * _minutesPerBlock));
    final en = gs.add(Duration(minutes: (_se + 1) * _minutesPerBlock));
    if (widget.entryMode == _EntryMode.plan) {
      showAppModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => _PlanEntrySheet(
          initialStart: st,
          initialEnd: en,
          username: widget.username,
          todos: widget.todos,
          todoGroups: widget.todoGroups,
          onStartFocus: (block, todo) async {
            await StorageService.savePlanBlocks(widget.username, [block]);
            if (!mounted) return;
            Navigator.of(context).pop();
            await PageTransitions.pushFromRect<void>(
              context: context,
              sourceKey: _pomodoroEntrySourceKey,
              placeholderIcon: Icons.timer_outlined,
              page: PomodoroScreen(
                username: widget.username,
                initialEntry: PomodoroEntryIntent.forPlanBlock(
                  boundTodo: todo,
                  planBlock: block,
                ),
              ),
            );
          },
          onSave: (block) {
            Navigator.pop(context);
            widget.onSavePlanBlock(block);
          },
        ),
      );
      return;
    }
    showAppModalBottomSheet(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      builder: (_) => TimeLogEntrySheet(
        initialStart: st,
        initialEnd: en,
        initialTagId: _selectedTagId,
        tags: widget.tags,
        timeLogs: widget.logs,
        pomodoros: widget.pomodoros,
        onSave: widget.onSaveLog,
      ),
    );
  }

  void _showDayLogList() {
    final gsMs = _gridStart.millisecondsSinceEpoch;
    final geMs = _dayEndMs(_gridStart);
    final tagIndicesByUuid = _DayGridPainter._buildTagIndices(widget.tags);
    showAppModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setModal) {
          final colorScheme = Theme.of(ctx).colorScheme;
          final timeFormat = AppTimeFormats.dateFormatter('HH:mm');
          final dayLogs =
              widget.logs
                  .where((l) => l.endTime > gsMs && l.startTime < geMs)
                  .toList()
                ..sort((a, b) => b.startTime.compareTo(a.startTime));
          return ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(ctx).height * 0.75,
            ),
            child: OptionalLiquidGlassSheet(
              topRadius: 20,
              padding: EdgeInsets.only(
                bottom: MediaQuery.paddingOf(ctx).bottom + 16,
                left: 20,
                right: 20,
                top: 20,
              ),
              fallbackDecoration: BoxDecoration(
                color: _TC.card(ctx),
                border: Border(top: BorderSide(color: _TC.divider(ctx))),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(20),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        '当天补录',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: _TC.text(ctx),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: colorScheme.cdtInfo.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '${dayLogs.length}条',
                          style: TextStyle(
                            fontSize: 11,
                            color: colorScheme.cdtInfo,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: Icon(
                          Icons.close,
                          size: 20,
                          color: _TC.textHint(ctx),
                        ),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (dayLogs.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: Center(
                        child: Text(
                          '暂无补录记录',
                          style: TextStyle(color: _TC.textHint(ctx)),
                        ),
                      ),
                    )
                  else
                    Flexible(
                      child: ListView.separated(
                        shrinkWrap: true,
                        findItemIndexCallback: (Key key) {
                          if (key is ValueKey<String>) {
                            final id = key.value;
                            final idx = dayLogs.indexWhere((l) => l.id == id);
                            return idx != -1 ? idx : null;
                          }
                          return null;
                        },
                        itemCount: dayLogs.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (ctx2, i) {
                          final log = dayLogs[i];
                          PomodoroTag? tag;
                          var firstTagIndex = widget.tags.length;
                          for (final uuid in log.tagUuids) {
                            final index = tagIndicesByUuid[uuid];
                            if (index != null && index < firstTagIndex) {
                              firstTagIndex = index;
                            }
                          }
                          if (firstTagIndex < widget.tags.length) {
                            tag = widget.tags[firstTagIndex];
                          }
                          final c = tag != null
                              ? hexColor(tag.color)
                              : colorScheme.cdtInfo;
                          final dur = (log.endTime - log.startTime) ~/ 60000;
                          final s = DateTime.fromMillisecondsSinceEpoch(
                            log.startTime,
                          );
                          final e = DateTime.fromMillisecondsSinceEpoch(
                            log.endTime,
                          );
                          return RepaintBoundary(
                            key: ValueKey<String>(log.id),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 12,
                              ),
                              decoration: BoxDecoration(
                                color: _TC.inputFill(ctx2),
                                border: Border(
                                  left: BorderSide(color: c, width: 3),
                                ),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          log.title.isNotEmpty
                                              ? log.title
                                              : (tag?.name ?? '补录记录'),
                                          style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600,
                                            color: _TC.text(ctx2),
                                          ),
                                        ),
                                        const SizedBox(height: 3),
                                        Row(
                                          children: [
                                            if (tag != null) ...[
                                              Container(
                                                width: 6,
                                                height: 6,
                                                decoration: BoxDecoration(
                                                  color: c,
                                                  shape: BoxShape.circle,
                                                ),
                                              ),
                                              const SizedBox(width: 4),
                                              Text(
                                                tag.name,
                                                style: TextStyle(
                                                  fontSize: 10,
                                                  color: c,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                              const SizedBox(width: 6),
                                            ],
                                            Text(
                                              '${timeFormat.format(s)} → ${timeFormat.format(e)}',
                                              style: TextStyle(
                                                fontSize: 10,
                                                color: _TC.textHint(ctx2),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    '${dur}min',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                      color: c,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  IconButton(
                                    icon: Icon(
                                      Icons.delete_outline,
                                      size: 20,
                                      color: colorScheme.error.withValues(
                                        alpha: 0.6,
                                      ),
                                    ),
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(
                                      minWidth: 36,
                                      minHeight: 36,
                                    ),
                                    onPressed: () {
                                      showAppDialog(
                                        context: ctx,
                                        builder: (dCtx) => AlertDialog(
                                          backgroundColor: _TC.card(ctx),
                                          title: Text(
                                            '删除记录',
                                            style: TextStyle(
                                              color: _TC.text(ctx),
                                              fontSize: 16,
                                            ),
                                          ),
                                          content: Text(
                                            '确定删除「${log.title.isNotEmpty ? log.title : (tag?.name ?? '补录记录')}」吗？',
                                            style: TextStyle(
                                              color: _TC.textSub(ctx),
                                              fontSize: 13,
                                            ),
                                          ),
                                          actions: [
                                            TextButton(
                                              onPressed: () =>
                                                  Navigator.pop(dCtx),
                                              child: Text(
                                                '取消',
                                                style: TextStyle(
                                                  color: _TC.textSub(ctx),
                                                ),
                                              ),
                                            ),
                                            TextButton(
                                              onPressed: () {
                                                Navigator.pop(dCtx);
                                                widget.onDeleteLog(log.id);
                                                if (dayLogs.length <= 1) {
                                                  Navigator.pop(ctx);
                                                } else {
                                                  setModal(() {});
                                                }
                                              },
                                              child: Text(
                                                '删除',
                                                style: TextStyle(
                                                  color: colorScheme.error,
                                                  fontWeight: FontWeight.w700,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      );
                                    },
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    _ensureDayRecords();

    return Column(
      children: [
        _buildCrossDayBar(_dayLogs.length),
        Expanded(
          child: Row(
            children: [
              Expanded(
                child: LayoutBuilder(
                  builder: (ctx, c) {
                    final hourH = c.maxHeight / 24;
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: kTimeAxisW,
                          height: c.maxHeight,
                          child: Stack(
                            clipBehavior: Clip.none,
                            children: List.generate(
                              24,
                              (h) => Positioned(
                                top: h * hourH - 8,
                                right: 8,
                                child: Text(
                                  '${h.toString().padLeft(2, '0')}:00',
                                  style: TextStyle(
                                    fontSize: 9,
                                    color: _TC.timeLabel(
                                      ctx,
                                      major: h % 6 == 0,
                                    ),
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        Expanded(child: _buildGrid(hourH, c.maxHeight)),
                      ],
                    );
                  },
                ),
              ),
              if (widget.entryMode == _EntryMode.log)
                _buildTagSidebar()
              else
                const SizedBox(width: _timeLogTagSidebarWidth),
            ],
          ),
        ),
        if (_dragStart != null) _buildBottomBar(),
      ],
    );
  }

  Widget _buildCrossDayBar(int dLogN) {
    final colorScheme = Theme.of(context).colorScheme;
    final useFloating = floatingBottomBarShouldFloat(context);
    const actionControlHeight = 40.0;
    Widget actionControl(Widget child) =>
        SizedBox(height: actionControlHeight, child: child);
    final child = Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: useFloating
          ? null
          : BoxDecoration(color: _TC.topBar(context)),
      child: Row(
        children: [
          const SizedBox(width: 8),
          actionControl(
            _EntryModeToggle(
              mode: widget.entryMode,
              onChanged: widget.onEntryModeChanged,
            ),
          ),
          const SizedBox(width: 8),
          // 已补录数量
          if (widget.entryMode == _EntryMode.log && dLogN > 0)
            GestureDetector(
              onTap: _showDayLogList,
              child: Container(
                height: actionControlHeight,
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: colorScheme.cdtInfo.withValues(alpha: 0.1),
                  border: Border.all(
                    color: colorScheme.cdtInfo.withValues(alpha: 0.35),
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.list_alt_outlined,
                      size: 12,
                      color: colorScheme.cdtInfo,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '已补录 $dLogN',
                      style: TextStyle(
                        fontSize: 10,
                        color: colorScheme.cdtInfo,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          // 退出补录
          actionControl(
            GestureDetector(
              onTap: widget.onBack,
              child: Container(
                height: actionControlHeight,
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: colorScheme.error.withValues(alpha: 0.08),
                  border: Border.all(
                    color: colorScheme.error.withValues(alpha: 0.30),
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.close,
                      size: 12,
                      color: colorScheme.error.withValues(alpha: 0.8),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      widget.entryMode == _EntryMode.plan ? '退出规划' : '退出补录',
                      style: TextStyle(
                        fontSize: 11,
                        color: colorScheme.error.withValues(alpha: 0.8),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const Spacer(),
          // 分钟下拉选择器
          actionControl(
            _MinuteDropdown(
              value: _minutesPerBlock,
              onChanged: (m) => setState(() {
                _minutesPerBlock = m;
                _dragStart = null;
              }),
            ),
          ),
        ],
      ),
    );
    return FloatingGlassControl(
      height: useFloating ? 60 : 52,
      margin: useFloating
          ? const EdgeInsets.fromLTRB(8, 8, 8, 4)
          : EdgeInsets.zero,
      borderRadius: useFloating ? _timeLogActionBarRadius : 0,
      mobilePortraitOnly: true,
      child: child,
    );
  }

  Widget _buildGrid(double hourH, double totalH) {
    return LayoutBuilder(
      builder: (ctx, c) {
        final w = c.maxWidth;
        final colorScheme = Theme.of(ctx).colorScheme;
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        final accent = colorScheme.primary;
        final selTag = widget.tags.cast<PomodoroTag?>().firstWhere(
          (t) => t?.uuid == _selectedTagId,
          orElse: () => null,
        );

        return GestureDetector(
          key: _pomodoroEntrySourceKey,
          onPanStart: (d) {
            final i = _getIndex(d.localPosition, w, hourH);
            if (i != null) {
              setState(() {
                _dragStart = i;
                _dragEnd = i;
              });
            }
          },
          onPanUpdate: (d) {
            final i = _getIndex(d.localPosition, w, hourH);
            if (i != null) setState(() => _dragEnd = i);
          },
          onTapDown: (d) {
            final i = _getIndex(d.localPosition, w, hourH);
            if (i != null) {
              setState(() {
                _dragStart = i;
                _dragEnd = i;
              });
            }
          },
          child: Stack(
            children: [
              SizedBox(
                height: totalH,
                child: Stack(
                  children: [
                    RepaintBoundary(
                      child: CustomPaint(
                        size: Size(w, totalH),
                        painter: _DayGridPainter(
                          minutesPerBlock: _minutesPerBlock,
                          logs: _dayLogs,
                          planBlocks: _dayPlanBlocks,
                          schedules: _daySchedules,
                          showPlans: widget.entryMode == _EntryMode.plan,
                          tags: widget.tags,
                          tagIndicesByUuid: _tagIndicesFor(widget.tags),
                          gridStart: _gridStart,
                          gridMajorColor: colorScheme.outlineVariant,
                          gridMinorColor: colorScheme.outlineVariant.withValues(
                            alpha: isDark ? 0.28 : 0.48,
                          ),
                          successColor: colorScheme.cdtSuccess,
                          planColor: colorScheme.secondary,
                          isDark: isDark,
                          hourH: hourH,
                        ),
                      ),
                    ),
                    Positioned.fill(
                      child: IgnorePointer(
                        child: RepaintBoundary(
                          child: CustomPaint(
                            size: Size(w, totalH),
                            painter: _DayGridInteractionPainter(
                              minutesPerBlock: _minutesPerBlock,
                              dragStart: _dragStart,
                              dragEnd: _dragEnd,
                              gridStart: _gridStart,
                              selColor: selTag != null
                                  ? hexColor(selTag.color, opacity: 0.48)
                                  : accent.withValues(alpha: 0.45),
                              nowColor: colorScheme.cdtFocus,
                              hourH: hourH,
                            ),
                          ),
                        ),
                      ),
                    ),
                    ..._pomodoroTapTargets(w, hourH),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  List<Widget> _pomodoroTapTargets(double width, double hourH) {
    final gsMs = _gridStart.millisecondsSinceEpoch;
    final geMs = _dayEndMs(_gridStart);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final focusColor = colorScheme.cdtFocus;
    final tagIndicesByUuid = _tagIndicesFor(widget.tags);
    final List<Widget> targets = [];
    for (final pom in _dayPomodoros) {
      final pe = pom.endTime ?? (pom.startTime + pom.effectiveDuration * 1000);
      final rs = max(pom.startTime, gsMs);
      final re = min(pe, geMs);
      final startF = (rs - gsMs) / 3600000;
      final endF = (re - gsMs) / 3600000;
      int sH = startF.floor();
      int eH = endF.floor();
      if (eH > sH && endF == eH.toDouble()) eH--;
      PomodoroTag? tag;
      if (pom.tagUuids.isNotEmpty) {
        tag = _firstPomodoroTagForUuids(pom.tagUuids, tagIndicesByUuid);
      }
      final base = tag != null ? hexColor(tag.color) : focusColor;
      final fill = base.withValues(alpha: isDark ? 0.35 : 0.45);
      final mark = base.withValues(alpha: 0.85);
      for (int h = sH; h <= eH; h++) {
        final hS = max(h.toDouble(), startF);
        final hE = min((h + 1).toDouble(), endF);
        final left = (hS - h) * width;
        final right = (hE - h) * width;
        final bw = right - left;
        if (bw <= 0) continue;
        targets.add(
          Positioned(
            top: h * hourH + 1,
            left: left + 1,
            width: bw - 1,
            height: hourH - 2,
            child: GestureDetector(
              onTap: () => widget.onPomodoroTap(pom),
              behavior: HitTestBehavior.opaque,
              child: Container(
                decoration: BoxDecoration(
                  color: fill,
                  borderRadius: BorderRadius.circular(4),
                  border: Border(left: BorderSide(color: mark, width: 3)),
                ),
                child: bw > 20
                    ? Icon(Icons.timer_outlined, size: 12, color: mark)
                    : null,
              ),
            ),
          ),
        );
      }
    }
    return targets;
  }

  Widget _buildTagSidebar() => Container(
    width: _timeLogTagSidebarWidth,
    color: _TC.topBar(context),
    child: Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Text(
            'TAGS',
            style: TextStyle(
              fontSize: 8,
              color: _TC.textHint(context),
              letterSpacing: 2,
            ),
          ),
        ),
        Expanded(
          child: ListView.builder(
            findChildIndexCallback: (Key key) {
              if (key is ValueKey<String>) {
                final uuid = key.value;
                final index = widget.tags.indexWhere((t) => t.uuid == uuid);
                return index != -1 ? index : null;
              }
              return null;
            },
            itemCount: widget.tags.length,
            itemBuilder: (ctx, i) {
              final t = widget.tags[i];
              final c = hexColor(t.color);
              final sel = _selectedTagId == t.uuid;
              return GestureDetector(
                key: ValueKey<String>(t.uuid),
                onTap: () => setState(() => _selectedTagId = t.uuid),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  margin: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 4,
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 9),
                  decoration: BoxDecoration(
                    color: sel ? c.withValues(alpha: 0.2) : _TC.card(ctx),
                    border: Border.all(
                      color: sel ? c : c.withValues(alpha: 0.2),
                      width: sel ? 1.5 : 1,
                    ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    children: [
                      Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                          color: c,
                          shape: BoxShape.circle,
                          boxShadow: sel
                              ? [BoxShadow(color: c, blurRadius: 5)]
                              : [],
                        ),
                      ),
                      const SizedBox(height: 4),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Text(
                          t.name,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 9,
                            color: sel ? c : _TC.textSub(ctx),
                            fontWeight: sel ? FontWeight.w700 : FontWeight.w400,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    ),
  );

  Widget _buildBottomBar() {
    final gs = _gridStart;
    final st = gs.add(Duration(minutes: _ss * _minutesPerBlock));
    final en = gs.add(Duration(minutes: (_se + 1) * _minutesPerBlock));
    final timeFormat = AppTimeFormats.dateFormatter('HH:mm');
    final colorScheme = Theme.of(context).colorScheme;
    return OptionalLiquidGlassSheet(
      topRadius: 20,
      padding: EdgeInsets.fromLTRB(
        16,
        14,
        16,
        MediaQuery.paddingOf(context).bottom + 14,
      ),
      fallbackDecoration: BoxDecoration(
        color: _TC.card(context),
        border: Border(top: BorderSide(color: _TC.divider(context))),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '$_durMin 分钟',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: _TC.text(context),
                  ),
                ),
                Text(
                  '${timeFormat.format(st)} → ${timeFormat.format(en)}',
                  style: TextStyle(fontSize: 11, color: _TC.textSub(context)),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: () => setState(() {
              _dragStart = null;
              _dragEnd = null;
            }),
            child: Text('取消', style: TextStyle(color: _TC.textSub(context))),
          ),
          const SizedBox(width: 8),
          ElevatedButton(
            onPressed: _openEntry,
            style: _timeLogPrimaryActionStyle(
              backgroundColor: colorScheme.primary,
              foregroundColor: colorScheme.onPrimary,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(
              widget.entryMode == _EntryMode.plan ? '添加规划' : '详情录入',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}
