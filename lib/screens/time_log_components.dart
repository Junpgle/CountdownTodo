part of 'time_log_screen.dart';

String? _timeLogComponentDateLocale;
final _timeLogComponentDateFormatters = <String, DateFormat>{};

DateFormat _timeLogComponentDateFormat(String pattern) {
  final locale = Intl.defaultLocale;
  if (_timeLogComponentDateLocale != locale) {
    _timeLogComponentDateLocale = locale;
    _timeLogComponentDateFormatters.clear();
  }
  return _timeLogComponentDateFormatters.putIfAbsent(
    pattern,
    () => DateFormat(pattern, locale),
  );
}

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
  List<PomodoroRecord>? _dayPomodorosSource;
  int? _dayRecordsStartMs;
  int? _dayRecordsEndMs;
  List<TimeLogItem> _dayLogs = const [];
  List<TodoPlanBlock> _dayPlanBlocks = const [];
  List<PomodoroRecord> _dayPomodoros = const [];
  final Paint _selectionPaint = Paint();
  final Paint _currentTimeLinePaint = Paint();
  final Paint _currentTimeDotPaint = Paint();

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
        identical(_dayPomodorosSource, widget.pomodoros) &&
        _dayRecordsStartMs == gridStartMs &&
        _dayRecordsEndMs == gridEndMs) {
      return;
    }

    _dayLogsSource = widget.logs;
    _dayPlanBlocksSource = widget.planBlocks;
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
          final timeFormat = _timeLogComponentDateFormat('HH:mm');
          final dayLogs =
              widget.logs
                  .where((l) => l.endTime > gsMs && l.startTime < geMs)
                  .toList()
                ..sort((a, b) => b.startTime.compareTo(a.startTime));
          return ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(ctx).size.height * 0.75,
            ),
            child: OptionalLiquidGlassSheet(
              topRadius: 20,
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(ctx).padding.bottom + 16,
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
                          return Container(
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
                            selectionPaint: _selectionPaint,
                            currentTimeLinePaint: _currentTimeLinePaint,
                            currentTimeDotPaint: _currentTimeDotPaint,
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
            itemCount: widget.tags.length,
            itemBuilder: (ctx, i) {
              final t = widget.tags[i];
              final c = hexColor(t.color);
              final sel = _selectedTagId == t.uuid;
              return GestureDetector(
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
    final timeFormat = _timeLogComponentDateFormat('HH:mm');
    final colorScheme = Theme.of(context).colorScheme;
    return OptionalLiquidGlassSheet(
      topRadius: 20,
      padding: EdgeInsets.fromLTRB(
        16,
        14,
        16,
        MediaQuery.of(context).padding.bottom + 14,
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

// ══════════════════════════════════════════════════════════
// 补录模式网格 Painter
// ══════════════════════════════════════════════════════════
class _DayGridPainter extends CustomPainter {
  final int minutesPerBlock;
  final List<TimeLogItem> logs;
  final List<TodoPlanBlock> planBlocks;
  final bool showPlans;
  final List<PomodoroTag> tags;
  final DateTime gridStart;
  final Color gridMajorColor;
  final Color gridMinorColor;
  final Color successColor;
  final Color planColor;
  final bool isDark;
  final double hourH;
  final Map<String, int> tagIndicesByUuid;

  _DayGridPainter({
    required this.minutesPerBlock,
    required this.logs,
    required this.planBlocks,
    required this.showPlans,
    required this.tags,
    required this.tagIndicesByUuid,
    required this.gridStart,
    required this.gridMajorColor,
    required this.gridMinorColor,
    required this.successColor,
    required this.planColor,
    required this.isDark,
    required this.hourH,
  });

  static Map<String, int> _buildTagIndices(List<PomodoroTag> tags) {
    final indices = <String, int>{};
    for (var index = 0; index < tags.length; index++) {
      final uuid = tags[index].uuid;
      if (!indices.containsKey(uuid)) indices[uuid] = index;
    }
    return indices;
  }

  PomodoroTag? _firstTagForUuids(List<String> uuids) {
    int? firstIndex;
    for (final uuid in uuids) {
      final index = tagIndicesByUuid[uuid];
      if (index != null && (firstIndex == null || index < firstIndex)) {
        firstIndex = index;
      }
    }
    return firstIndex == null ? null : tags[firstIndex];
  }

  @override
  void paint(Canvas canvas, Size size) {
    final bpr = 60 ~/ minutesPerBlock;
    final bw = size.width / bpr;
    final gsMs = gridStart.millisecondsSinceEpoch;
    final geMs = _dayEndMs(gridStart);

    final mj = Paint()
      ..color = gridMajorColor
      ..strokeWidth = 0.5;
    final mn = Paint()
      ..color = gridMinorColor
      ..strokeWidth = 0.5;
    final eventFillPaint = Paint();
    final eventBarPaint = Paint();

    for (int h = 0; h <= 24; h++) {
      canvas.drawLine(
        Offset(0, h * hourH),
        Offset(size.width, h * hourH),
        h % 6 == 0 ? mj : mn,
      );
    }
    for (int c = 0; c <= bpr; c++) {
      canvas.drawLine(
        Offset(c * bw, 0),
        Offset(c * bw, size.height),
        c % 4 == 0 ? mj : mn,
      );
    }

    for (final log in logs) {
      if (log.endTime <= gsMs || log.startTime >= geMs) continue;
      final sMs = max(log.startTime, gsMs);
      final eMs = min(log.endTime, geMs);
      final sIdx = (sMs - gsMs) ~/ (60000 * minutesPerBlock);
      final eIdx = ((eMs - gsMs - 1) ~/ (60000 * minutesPerBlock)).clamp(
        0,
        24 * bpr - 1,
      );
      PomodoroTag? tag;
      if (log.tagUuids.isNotEmpty) {
        tag = _firstTagForUuids(log.tagUuids);
      }
      final fill = tag != null
          ? hexColor(tag.color, opacity: isDark ? 0.14 : 0.10)
          : (isDark ? const Color(0x18888888) : const Color(0x0F000000));
      final bar = tag != null
          ? hexColor(tag.color, opacity: 0.5)
          : (isDark ? const Color(0x44888888) : const Color(0x44000000));
      eventFillPaint.color = fill;
      eventBarPaint.color = bar;
      for (int i = sIdx; i <= eIdx; i++) {
        final rowStartMs = gsMs + i * 60 * minutesPerBlock * 1000;
        final rowEndMs = rowStartMs + 60 * minutesPerBlock * 1000;
        final segStart = max(sMs, rowStartMs);
        final segEnd = min(eMs, rowEndMs);
        final startOffset =
            (segStart - rowStartMs) / (60 * minutesPerBlock * 1000);
        final endOffset = (segEnd - rowStartMs) / (60 * minutesPerBlock * 1000);
        final left = i % bpr * bw + startOffset * bw;
        final width = ((endOffset - startOffset) * bw).clamp(1.0, bw);
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(left, i ~/ bpr * hourH + 1, width, hourH - 2),
            const Radius.circular(3),
          ),
          eventFillPaint,
        );
        canvas.drawRect(
          Rect.fromLTWH(left, i ~/ bpr * hourH + 1, 3, hourH - 2),
          eventBarPaint,
        );
      }
    }

    if (showPlans) {
      for (final plan in planBlocks) {
        if (plan.endTime <= gsMs || plan.startTime >= geMs) continue;
        final sMs = max(plan.startTime, gsMs);
        final eMs = min(plan.endTime, geMs);
        final sIdx = (sMs - gsMs) ~/ (60000 * minutesPerBlock);
        final eIdx = ((eMs - gsMs - 1) ~/ (60000 * minutesPerBlock)).clamp(
          0,
          24 * bpr - 1,
        );
        final base = plan.status == TodoPlanStatus.finished
            ? successColor
            : planColor;
        final fill = base.withValues(alpha: isDark ? 0.18 : 0.12);
        final bar = base.withValues(alpha: 0.58);
        eventFillPaint.color = fill;
        eventBarPaint.color = bar;
        for (int i = sIdx; i <= eIdx; i++) {
          final rowStartMs = gsMs + i * 60 * minutesPerBlock * 1000;
          final rowEndMs = rowStartMs + 60 * minutesPerBlock * 1000;
          final segStart = max(sMs, rowStartMs);
          final segEnd = min(eMs, rowEndMs);
          final startOffset =
              (segStart - rowStartMs) / (60 * minutesPerBlock * 1000);
          final endOffset =
              (segEnd - rowStartMs) / (60 * minutesPerBlock * 1000);
          final left = i % bpr * bw + startOffset * bw;
          final width = ((endOffset - startOffset) * bw).clamp(1.0, bw);
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              Rect.fromLTWH(left, i ~/ bpr * hourH + 1, width, hourH - 2),
              const Radius.circular(3),
            ),
            eventFillPaint,
          );
          canvas.drawRect(
            Rect.fromLTWH(left, i ~/ bpr * hourH + 1, 3, hourH - 2),
            eventBarPaint,
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DayGridPainter o) =>
      o.minutesPerBlock != minutesPerBlock ||
      !identical(o.logs, logs) ||
      !identical(o.planBlocks, planBlocks) ||
      o.showPlans != showPlans ||
      !identical(o.tags, tags) ||
      o.gridStart != gridStart ||
      o.gridMajorColor != gridMajorColor ||
      o.gridMinorColor != gridMinorColor ||
      o.successColor != successColor ||
      o.planColor != planColor ||
      o.isDark != isDark ||
      o.hourH != hourH;
}

class _DayGridInteractionPainter extends CustomPainter {
  final int minutesPerBlock;
  final int? dragStart;
  final int? dragEnd;
  final DateTime gridStart;
  final Color selColor;
  final Color nowColor;
  final double hourH;
  final Paint selectionPaint;
  final Paint currentTimeLinePaint;
  final Paint currentTimeDotPaint;

  _DayGridInteractionPainter({
    required this.minutesPerBlock,
    required this.dragStart,
    required this.dragEnd,
    required this.gridStart,
    required this.selColor,
    required this.nowColor,
    required this.hourH,
    required this.selectionPaint,
    required this.currentTimeLinePaint,
    required this.currentTimeDotPaint,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final bpr = 60 ~/ minutesPerBlock;
    final blockWidth = size.width / bpr;
    final gridStartMs = gridStart.millisecondsSinceEpoch;
    final gridEndMs = _dayEndMs(gridStart);

    if (dragStart != null && dragEnd != null) {
      final firstBlock = min(dragStart!, dragEnd!);
      final lastBlock = max(dragStart!, dragEnd!);
      selectionPaint.color = selColor;
      for (var index = firstBlock; index <= lastBlock; index++) {
        final rowStartMs = gridStartMs + index * 60 * minutesPerBlock * 1000;
        final rowEndMs = rowStartMs + 60 * minutesPerBlock * 1000;
        final segmentEnd = min(rowEndMs, gridEndMs);
        final endOffset =
            (segmentEnd - rowStartMs) / (60 * minutesPerBlock * 1000);
        final left = index % bpr * blockWidth;
        final width = (endOffset * blockWidth).clamp(1.0, blockWidth);
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(left, index ~/ bpr * hourH + 1, width, hourH - 2),
            const Radius.circular(3),
          ),
          selectionPaint,
        );
      }
    }

    final now = DateTime.now();
    if (!DateUtils.isSameDay(now, gridStart)) return;
    final hour = now.hour;
    final x = (now.minute + now.second / 60) / 60 * size.width;
    currentTimeLinePaint
      ..color = nowColor.withValues(alpha: 0.7)
      ..strokeWidth = 1.5;
    currentTimeDotPaint.color = nowColor;
    canvas.drawLine(
      Offset(x, hour * hourH),
      Offset(x, (hour + 1) * hourH),
      currentTimeLinePaint,
    );
    canvas.drawCircle(Offset(x, hour * hourH), 3, currentTimeDotPaint);
  }

  @override
  bool shouldRepaint(covariant _DayGridInteractionPainter oldDelegate) =>
      oldDelegate.minutesPerBlock != minutesPerBlock ||
      oldDelegate.dragStart != dragStart ||
      oldDelegate.dragEnd != dragEnd ||
      oldDelegate.gridStart != gridStart ||
      oldDelegate.selColor != selColor ||
      oldDelegate.nowColor != nowColor ||
      oldDelegate.hourH != hourH;
}

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
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
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
    _invalidatePendingSave();
    setState(() {});
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
    return PopScope<Object?>(
      canPop: _allowExit || (!_isSaving && !_hasUnsavedChanges),
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) unawaited(_requestExit());
      },
      child: OptionalLiquidGlassSheet(
        key: _sheetKey,
        topRadius: 20,
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom + 16,
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

// ══════════════════════════════════════════════════════════
// 标签详情面板相关 (模型、图表容器、图表画笔)
// ══════════════════════════════════════════════════════════

class _TagRecord {
  final bool isPomodoro;
  final String title, id, timeRangeLabel;
  final int startTime, endTime, durationMin;
  final bool isCompleted;
  const _TagRecord({
    required this.isPomodoro,
    required this.title,
    required this.startTime,
    required this.endTime,
    required this.durationMin,
    required this.id,
    required this.timeRangeLabel,
    this.isCompleted = false,
  });
}

String _tagMonthDay(DateTime date) =>
    '${date.month.toString().padLeft(2, '0')}/${date.day.toString().padLeft(2, '0')}';

String _tagClockTime(DateTime date) =>
    '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';

String _tagDateTimeRange(DateTime start, DateTime end) =>
    '${_tagMonthDay(start)} ${_tagClockTime(start)} → ${_tagClockTime(end)}';

String _tagChartMonth(DateTime date) =>
    '${(date.year % 100).toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}';

class _TagDetailSheet extends StatefulWidget {
  final PomodoroTag tag;
  final List<TimeLogItem> logs;
  final List<PomodoroRecord> pomodoros;
  final void Function(String) onDelete;
  const _TagDetailSheet({
    required this.tag,
    required this.logs,
    this.pomodoros = const [],
    required this.onDelete,
  });

  @override
  State<_TagDetailSheet> createState() => _TagDetailSheetState();
}

enum _ChartScale { session, day, week, month }

class _TagDetailSheetState extends State<_TagDetailSheet> {
  int _chartType = 0; // 0: 时长, 1: 开始时间, 2: 结束时间
  _ChartScale _scale = _ChartScale.session;
  List<_TagRecord> _allRecs = const [];
  List<_TagRecord> _recentRecs = const [];
  List<int> _chartData = const [];
  List<String> _xLabels = const [];
  String Function(int) _formatLabel = _formatChartDuration;
  int _totalMin = 0;
  int _avgMin = 0;
  int _maxMin = 0;
  late Color _tagColor;

  @override
  void initState() {
    super.initState();
    _tagColor = hexColor(widget.tag.color);
    _rebuildRecordCache();
    _rebuildChartCache();
  }

  @override
  void didUpdateWidget(covariant _TagDetailSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    final tagChanged =
        oldWidget.tag.uuid != widget.tag.uuid ||
        oldWidget.tag.name != widget.tag.name ||
        oldWidget.tag.color != widget.tag.color;
    if (tagChanged ||
        !identical(oldWidget.logs, widget.logs) ||
        !identical(oldWidget.pomodoros, widget.pomodoros)) {
      _tagColor = hexColor(widget.tag.color);
      _rebuildRecordCache();
      _rebuildChartCache();
    }
  }

  void _rebuildRecordCache() {
    final records = <_TagRecord>[];
    for (final log in widget.logs) {
      if (!log.tagUuids.contains(widget.tag.uuid)) continue;
      final start = DateTime.fromMillisecondsSinceEpoch(log.startTime);
      final end = DateTime.fromMillisecondsSinceEpoch(log.endTime);
      records.add(
        _TagRecord(
          isPomodoro: false,
          title: log.title.isNotEmpty ? log.title : widget.tag.name,
          startTime: log.startTime,
          endTime: log.endTime,
          durationMin: (log.endTime - log.startTime) ~/ 60000,
          id: log.id,
          timeRangeLabel: _tagDateTimeRange(start, end),
        ),
      );
    }
    for (final pomodoro in widget.pomodoros) {
      if (!pomodoro.tagUuids.contains(widget.tag.uuid)) continue;
      final endTime =
          pomodoro.endTime ??
          (pomodoro.startTime + pomodoro.effectiveDuration * 1000);
      final start = DateTime.fromMillisecondsSinceEpoch(pomodoro.startTime);
      final end = DateTime.fromMillisecondsSinceEpoch(endTime);
      records.add(
        _TagRecord(
          isPomodoro: true,
          title: (pomodoro.todoTitle?.isNotEmpty ?? false)
              ? pomodoro.todoTitle!
              : widget.tag.name,
          startTime: pomodoro.startTime,
          endTime: endTime,
          durationMin: (endTime - pomodoro.startTime) ~/ 60000,
          id: pomodoro.uuid,
          timeRangeLabel: _tagDateTimeRange(start, end),
          isCompleted: pomodoro.isCompleted,
        ),
      );
    }
    records.sort((a, b) => a.startTime.compareTo(b.startTime));
    _allRecs = List<_TagRecord>.unmodifiable(records);
    _recentRecs = List<_TagRecord>.unmodifiable(records.reversed);

    var total = 0;
    var longest = records.isEmpty ? 0 : records.first.durationMin;
    for (final record in records) {
      total += record.durationMin;
      if (record.durationMin > longest) longest = record.durationMin;
    }
    _totalMin = total;
    _avgMin = records.isEmpty ? 0 : total ~/ records.length;
    _maxMin = longest;
  }

  void _rebuildChartCache() {
    if (_scale == _ChartScale.session) {
      final firstIndex = max(0, _allRecs.length - 30);
      final chartRecords = _allRecs.skip(firstIndex);
      if (_chartType == 0) {
        _chartData = List<int>.unmodifiable(
          chartRecords.map((record) => record.durationMin),
        );
        _formatLabel = _formatChartDuration;
      } else {
        _chartData = List<int>.unmodifiable(
          chartRecords.map((record) {
            final timestamp = _chartType == 1
                ? record.startTime
                : record.endTime;
            final date = DateTime.fromMillisecondsSinceEpoch(timestamp);
            return date.hour * 60 + date.minute;
          }),
        );
        _formatLabel = _formatChartClockTime;
      }
      _xLabels = List<String>.unmodifiable(
        chartRecords.map(
          (record) => _tagMonthDay(
            DateTime.fromMillisecondsSinceEpoch(record.startTime),
          ),
        ),
      );
      return;
    }

    // Numeric keys preserve chronological ordering without allocating and
    // formatting a date string for every record on each chart interaction.
    final grouped = <int, int>{};
    for (final record in _allRecs) {
      final date = DateTime.fromMillisecondsSinceEpoch(record.startTime);
      final key = switch (_scale) {
        _ChartScale.day => DateTime(
          date.year,
          date.month,
          date.day,
        ).millisecondsSinceEpoch,
        _ChartScale.week => DateTime(
          date.year,
          date.month,
          date.day - date.weekday + 1,
        ).millisecondsSinceEpoch,
        _ChartScale.month => date.year * 12 + date.month - 1,
        _ChartScale.session => throw StateError('session chart handled above'),
      };
      grouped.update(
        key,
        (value) => value + record.durationMin,
        ifAbsent: () => record.durationMin,
      );
    }
    final keys = grouped.keys.toList()..sort();
    if (keys.length > 20) keys.removeRange(0, keys.length - 20);
    _chartData = List<int>.unmodifiable(keys.map((key) => grouped[key]!));
    _xLabels = List<String>.unmodifiable(
      keys.map((key) {
        if (_scale == _ChartScale.month) {
          return _tagChartMonth(DateTime(key ~/ 12, key % 12 + 1));
        }
        final date = DateTime.fromMillisecondsSinceEpoch(key);
        final label = _tagMonthDay(date);
        return _scale == _ChartScale.week ? 'W$label' : label;
      }),
    );
    _formatLabel = _formatChartDuration;
  }

  void _selectChartType(int index) {
    if (_chartType == index) return;
    setState(() {
      _chartType = index;
      _rebuildChartCache();
    });
  }

  void _selectChartScale(_ChartScale scale) {
    if (_scale == scale) return;
    setState(() {
      _scale = scale;
      if (scale != _ChartScale.session) _chartType = 0;
      _rebuildChartCache();
    });
  }

  static String _formatChartDuration(int value) => '${value}m';

  static String _formatChartClockTime(int value) =>
      '${(value ~/ 60).toString().padLeft(2, '0')}:${(value % 60).toString().padLeft(2, '0')}';

  Widget _buildChartTab(String title, int index, Color color) {
    final isSel = _chartType == index;
    return GestureDetector(
      onTap: () => _selectChartType(index),
      child: Container(
        margin: const EdgeInsets.only(left: 6),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: isSel ? color.withValues(alpha: 0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          title,
          style: TextStyle(
            fontSize: 11,
            color: isSel ? color : _TC.textSub(context),
            fontWeight: isSel ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }

  Widget _buildScaleTab(String title, _ChartScale scale, Color color) {
    final isSel = _scale == scale;
    return GestureDetector(
      onTap: () => _selectChartScale(scale),
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: isSel ? color : _TC.inputFill(context),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSel ? color : _TC.divider(context),
            width: 1,
          ),
        ),
        child: Text(
          title,
          style: TextStyle(
            fontSize: 10,
            color: isSel ? Colors.white : _TC.textSub(context),
            fontWeight: isSel ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = _tagColor;

    return OptionalLiquidGlassSheet(
      topRadius: 24,
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      fallbackDecoration: BoxDecoration(
        color: _TC.card(context),
        border: Border(
          top: BorderSide(color: c.withValues(alpha: 0.35), width: 1.5),
        ),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: c,
                  shape: BoxShape.circle,
                  boxShadow: [BoxShadow(color: c, blurRadius: 8)],
                ),
              ),
              const SizedBox(width: 10),
              Text(
                widget.tag.name,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: _TC.text(context),
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: c.withValues(alpha: 0.12),
                  border: Border.all(color: c.withValues(alpha: 0.3)),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '${(_totalMin / 60).toStringAsFixed(1)}h 累计',
                  style: TextStyle(
                    fontSize: 11,
                    color: c,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              IconButton(
                icon: Icon(Icons.close, color: _TC.textHint(context), size: 20),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _StatCard(label: '记录次数', value: '${_allRecs.length}次', color: c),
              const SizedBox(width: 10),
              _StatCard(label: '平均时长', value: '${_avgMin}min', color: c),
              const SizedBox(width: 10),
              _StatCard(label: '最长一次', value: '${_maxMin}min', color: c),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Text(
                'DIMENSIONS',
                style: TextStyle(
                  fontSize: 9,
                  color: _TC.textHint(context),
                  letterSpacing: 2,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              _buildScaleTab('按次', _ChartScale.session, c),
              _buildScaleTab('日', _ChartScale.day, c),
              _buildScaleTab('周', _ChartScale.week, c),
              _buildScaleTab('月', _ChartScale.month, c),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Text(
                'TRENDS',
                style: TextStyle(
                  fontSize: 9,
                  color: _TC.textHint(context),
                  letterSpacing: 2,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              _buildChartTab('时长', 0, c),
              if (_scale == _ChartScale.session) ...[
                _buildChartTab('开始', 1, c),
                _buildChartTab('结束', 2, c),
              ],
            ],
          ),
          const SizedBox(height: 10),
          if (_chartData.length >= 2)
            RepaintBoundary(
              child: _MiniLineChart(
                data: _chartData,
                xLabels: _xLabels,
                color: c,
                height: 130,
                formatLabel: _formatLabel,
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text(
                  '数据采集中...',
                  style: TextStyle(fontSize: 11, color: _TC.textHint(context)),
                ),
              ),
            ),
          const SizedBox(height: 16),
          Text(
            'RECENT RECORDS',
            style: TextStyle(
              fontSize: 9,
              color: _TC.textHint(context),
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 220),
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: _recentRecs.length,
              primary: false,
              separatorBuilder: (_, _) => const SizedBox(height: 6),
              itemBuilder: (ctx, i) {
                final r = _recentRecs[i];
                final colorScheme = Theme.of(ctx).colorScheme;
                return Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: _TC.inputFill(ctx),
                    border: Border(
                      left: BorderSide(
                        color: r.isPomodoro ? colorScheme.cdtFocus : c,
                        width: 3,
                      ),
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      if (r.isPomodoro) ...[
                        Icon(
                          Icons.timer_outlined,
                          size: 12,
                          color: colorScheme.cdtFocus.withValues(alpha: 0.6),
                        ),
                        const SizedBox(width: 4),
                      ],
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              r.title,
                              style: TextStyle(
                                fontSize: 12,
                                color: _TC.text(ctx),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              r.timeRangeLabel,
                              style: TextStyle(
                                fontSize: 10,
                                color: _TC.textHint(ctx),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        '${r.durationMin}min',
                        style: TextStyle(
                          fontSize: 13,
                          color: r.isPomodoro ? colorScheme.cdtFocus : c,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (!r.isPomodoro)
                        IconButton(
                          icon: Icon(
                            Icons.delete_outline,
                            color: colorScheme.error.withValues(alpha: 0.55),
                            size: 18,
                          ),
                          onPressed: () => widget.onDelete(r.id),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        )
                      else
                        const SizedBox(width: 40),
                    ],
                  ),
                );
              },
            ),
          ),
          SizedBox(height: MediaQuery.of(context).padding.bottom + 16),
        ],
      ),
    );
  }
}

class _LineChartGeometry {
  final List<int> data;
  final List<int> dataSnapshot;
  final double width;
  final double height;
  final double itemW;
  final Color color;
  final String Function(int) formatLabel;
  final List<Offset> points;
  final List<TextPainter?> tooltipPainters;
  final Path fillPath;
  final Path linePath;
  final Paint fillPaint;
  final Paint linePaint;
  final Paint pointPaint;
  final Paint hoverGlowPaint;
  final Paint hoverLinePaint;
  final Paint bubblePaint;

  _LineChartGeometry._({
    required this.data,
    required this.dataSnapshot,
    required this.width,
    required this.height,
    required this.itemW,
    required this.color,
    required this.formatLabel,
    required this.points,
    required this.tooltipPainters,
    required this.fillPath,
    required this.linePath,
    required this.fillPaint,
    required this.linePaint,
    required this.pointPaint,
    required this.hoverGlowPaint,
    required this.hoverLinePaint,
    required this.bubblePaint,
  });

  factory _LineChartGeometry.create({
    required List<int> data,
    required double width,
    required double height,
    required double itemW,
    required Color color,
    required String Function(int) formatLabel,
  }) {
    var minValue = data.isEmpty ? 0 : data.first;
    var maxValue = minValue;
    for (var i = 1; i < data.length; i++) {
      final value = data[i];
      if (value < minValue) minValue = value;
      if (value > maxValue) maxValue = value;
    }
    final minV = minValue.toDouble();
    final maxV = maxValue.toDouble();
    final valueRange = maxV - minV;
    final range = valueRange < 1 ? 10.0 : valueRange;
    final totalPointsW = (data.length - 1) * itemW;
    final startX = max(20.0, width - 20 - totalPointsW);
    final points = <Offset>[];
    for (var i = 0; i < data.length; i++) {
      final y = height - 30 - ((data[i] - minV) / range) * (height - 60);
      points.add(Offset(startX + i * itemW, y));
    }

    final fillPath = Path();
    final linePath = Path();
    final fillPaint = Paint();
    final linePaint = Paint()
      ..color = color
      ..strokeWidth = 3.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    if (points.length >= 2) {
      fillPath
        ..moveTo(points.first.dx, height - 30)
        ..lineTo(points.first.dx, points.first.dy);
      linePath.moveTo(points.first.dx, points.first.dy);
      for (var i = 0; i < points.length - 1; i++) {
        final p1 = points[i];
        final p2 = points[i + 1];
        final midpointX = p1.dx + (p2.dx - p1.dx) / 2;
        fillPath.cubicTo(midpointX, p1.dy, midpointX, p2.dy, p2.dx, p2.dy);
        linePath.cubicTo(midpointX, p1.dy, midpointX, p2.dy, p2.dx, p2.dy);
      }
      fillPath
        ..lineTo(points.last.dx, height - 30)
        ..close();
      fillPaint.shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [color.withValues(alpha: 0.3), color.withValues(alpha: 0.0)],
      ).createShader(Rect.fromLTWH(0, 0, width, height));
    }

    final tooltipPainters = List<TextPainter?>.filled(
      data.length >= 2 ? data.length : 0,
      null,
    );

    return _LineChartGeometry._(
      data: data,
      dataSnapshot: List<int>.unmodifiable(data),
      width: width,
      height: height,
      itemW: itemW,
      color: color,
      formatLabel: formatLabel,
      points: points,
      tooltipPainters: tooltipPainters,
      fillPath: fillPath,
      linePath: linePath,
      fillPaint: fillPaint,
      linePaint: linePaint,
      pointPaint: Paint()..color = color,
      hoverGlowPaint: Paint()..color = color.withValues(alpha: 0.2),
      hoverLinePaint: Paint()
        ..color = color.withValues(alpha: 0.5)
        ..strokeWidth = 1.0,
      bubblePaint: Paint()..color = color,
    );
  }

  void dispose() {
    for (final painter in tooltipPainters) {
      painter?.dispose();
    }
  }

  TextPainter tooltipPainterAt(int index) {
    final cached = tooltipPainters[index];
    if (cached != null) return cached;
    final painter = TextPainter(
      text: TextSpan(
        text: formatLabel(data[index]),
        style: const TextStyle(
          fontSize: 11,
          color: Colors.white,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: ui.TextDirection.ltr,
    )..layout();
    tooltipPainters[index] = painter;
    return painter;
  }
}

class _MiniLineChart extends StatefulWidget {
  final List<int> data;
  final List<String> xLabels;
  final Color color;
  final double height;
  final String Function(int) formatLabel;

  const _MiniLineChart({
    required this.data,
    required this.xLabels,
    required this.color,
    this.height = 130,
    required this.formatLabel,
  });

  @override
  State<_MiniLineChart> createState() => _MiniLineChartState();
}

class _MiniLineChartState extends State<_MiniLineChart> {
  late ScrollController _sc;
  Offset? _touchPos;
  _LineChartGeometry? _lineChartGeometry;
  List<TextPainter?> _xLabelPainters = [];
  List<String> _cachedXLabels = [];
  Color? _cachedLabelColor;
  int _cachedLabelStride = 0;

  bool _xLabelPaintersNeedUpdate() {
    final stride = widget.data.length > 10 ? 2 : 1;
    if (_cachedLabelColor != widget.color ||
        _cachedLabelStride != stride ||
        _cachedXLabels.length != widget.xLabels.length) {
      return true;
    }
    for (var i = 0; i < widget.xLabels.length; i++) {
      if (_cachedXLabels[i] != widget.xLabels[i]) return true;
    }
    return false;
  }

  void _rebuildXLabelPainters() {
    final stride = widget.data.length > 10 ? 2 : 1;
    final painters = List<TextPainter?>.filled(widget.xLabels.length, null);
    final labelCount = widget.xLabels.length < widget.data.length
        ? widget.xLabels.length
        : widget.data.length;
    for (var i = 0; i < labelCount; i += stride) {
      final painter = TextPainter(
        text: TextSpan(
          text: widget.xLabels[i],
          style: TextStyle(
            fontSize: 9,
            color: widget.color.withValues(alpha: 0.6),
            fontWeight: FontWeight.w500,
          ),
        ),
        textDirection: ui.TextDirection.ltr,
      )..layout();
      painters[i] = painter;
    }

    for (final painter in _xLabelPainters) {
      painter?.dispose();
    }
    _xLabelPainters = painters;
    _cachedXLabels = List<String>.of(widget.xLabels);
    _cachedLabelColor = widget.color;
    _cachedLabelStride = stride;
  }

  _LineChartGeometry _geometryFor(Size size, double itemW) {
    final cached = _lineChartGeometry;
    if (cached != null &&
        cached.width == size.width &&
        cached.height == size.height &&
        cached.itemW == itemW &&
        cached.color == widget.color &&
        cached.formatLabel == widget.formatLabel &&
        identical(cached.data, widget.data)) {
      return cached;
    }

    cached?.dispose();
    return _lineChartGeometry = _LineChartGeometry.create(
      data: widget.data,
      width: size.width,
      height: size.height,
      itemW: itemW,
      color: widget.color,
      formatLabel: widget.formatLabel,
    );
  }

  void _invalidateLineChartGeometry() {
    _lineChartGeometry?.dispose();
    _lineChartGeometry = null;
  }

  void _updateTouch(Offset? position) {
    if (_touchPos == position) return;
    setState(() => _touchPos = position);
  }

  @override
  void initState() {
    super.initState();
    _sc = ScrollController();
    _rebuildXLabelPainters();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_sc.hasClients) {
        _sc.jumpTo(_sc.position.maxScrollExtent);
      }
    });
  }

  @override
  void didUpdateWidget(_MiniLineChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    final geometry = _lineChartGeometry;
    if (geometry != null) {
      var dataChanged =
          !identical(geometry.data, widget.data) ||
          geometry.dataSnapshot.length != widget.data.length;
      if (!dataChanged) {
        for (var i = 0; i < widget.data.length; i++) {
          if (geometry.dataSnapshot[i] != widget.data[i]) {
            dataChanged = true;
            break;
          }
        }
      }
      if (dataChanged ||
          oldWidget.color != widget.color ||
          oldWidget.height != widget.height ||
          oldWidget.formatLabel != widget.formatLabel) {
        _invalidateLineChartGeometry();
      }
    }
    if (_xLabelPaintersNeedUpdate()) _rebuildXLabelPainters();
    if (oldWidget.data.length != widget.data.length) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_sc.hasClients) {
          _sc.animateTo(
            _sc.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      });
    }
  }

  @override
  void dispose() {
    _invalidateLineChartGeometry();
    for (final painter in _xLabelPainters) {
      painter?.dispose();
    }
    _sc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width - 40;
    const double itemW = 55.0; // 固定间距
    final double chartContentW = (widget.data.length - 1) * itemW + 40;
    final double scrollWidth = max(screenWidth, chartContentW);
    final size = Size(scrollWidth, widget.height);
    final geometry = _geometryFor(size, itemW);

    return SizedBox(
      height: widget.height,
      width: double.infinity,
      child: GestureDetector(
        onPanUpdate: (d) =>
            _updateTouch(d.localPosition.translate(_sc.offset, 0)),
        onPanEnd: (_) => _updateTouch(null),
        onTapDown: (d) =>
            _updateTouch(d.localPosition.translate(_sc.offset, 0)),
        onTapUp: (_) => _updateTouch(null),
        child: SingleChildScrollView(
          controller: _sc,
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          child: SizedBox(
            width: scrollWidth,
            height: widget.height,
            child: Stack(
              fit: StackFit.expand,
              children: [
                RepaintBoundary(
                  child: CustomPaint(
                    painter: _LineChartPathPainter(geometry: geometry),
                  ),
                ),
                CustomPaint(
                  painter: _LineChartPainter(
                    geometry: geometry,
                    xLabels: widget.xLabels,
                    xLabelPainters: _xLabelPainters,
                    touchPos: _touchPos,
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

class _LineChartPainter extends CustomPainter {
  final _LineChartGeometry geometry;
  final List<String> xLabels;
  final List<TextPainter?> xLabelPainters;
  final Offset? touchPos;

  _LineChartPainter({
    required this.geometry,
    required this.xLabels,
    required this.xLabelPainters,
    this.touchPos,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final data = geometry.data;
    if (data.isEmpty) return;
    final pts = geometry.points;

    if (data.length < 2) {
      // 只有一个点的情况
      final p = pts[0];
      canvas.drawCircle(p, 6, geometry.pointPaint);
      return;
    }

    int? activeIdx;
    if (touchPos != null) {
      if (geometry.itemW > 0) {
        final relativeIndex = (touchPos!.dx - pts.first.dx) / geometry.itemW;
        final lowerIndex = relativeIndex.floor();
        final fraction = relativeIndex - lowerIndex;
        final nearestIndex = fraction <= 0.5 ? lowerIndex : lowerIndex + 1;
        activeIdx = nearestIndex.clamp(0, pts.length - 1).toInt();
      } else {
        activeIdx = 0;
      }
    }

    for (int i = 0; i < pts.length; i++) {
      final p = pts[i];
      final isHover = i == activeIdx;

      // 节点点
      canvas.drawCircle(p, isHover ? 6 : 4, geometry.pointPaint);
      if (isHover) {
        canvas.drawCircle(p, 10, geometry.hoverGlowPaint);
      }

      // X轴标签
      if (i % (data.length > 10 ? 2 : 1) == 0) {
        final dateTp = xLabelPainters[i]!;
        dateTp.paint(canvas, Offset(p.dx - dateTp.width / 2, size.height - 18));
      }

      // 活跃点的指示线和数值
      if (isHover) {
        canvas.drawLine(
          Offset(p.dx, 0),
          Offset(p.dx, size.height - 30),
          geometry.hoverLinePaint,
        );

        final valTp = geometry.tooltipPainterAt(i);

        // 绘制气泡背景
        final bgR = Rect.fromCenter(
          center: Offset(p.dx, p.dy - 25),
          width: valTp.width + 16,
          height: valTp.height + 8,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(bgR, const Radius.circular(8)),
          geometry.bubblePaint,
        );
        valTp.paint(
          canvas,
          Offset(p.dx - valTp.width / 2, p.dy - 25 - valTp.height / 2),
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _LineChartPainter o) =>
      !identical(o.geometry, geometry) ||
      !identical(o.xLabels, xLabels) ||
      !identical(o.xLabelPainters, xLabelPainters) ||
      o.touchPos != touchPos;
}

class _LineChartPathPainter extends CustomPainter {
  final _LineChartGeometry geometry;

  const _LineChartPathPainter({required this.geometry});

  @override
  void paint(Canvas canvas, Size size) {
    if (geometry.data.length < 2) return;
    canvas.drawPath(geometry.fillPath, geometry.fillPaint);
    canvas.drawPath(geometry.linePath, geometry.linePaint);
  }

  @override
  bool shouldRepaint(covariant _LineChartPathPainter oldDelegate) =>
      !identical(oldDelegate.geometry, geometry);
}

// ══════════════════════════════════════════════════════════
// 信息展示小组件
// ══════════════════════════════════════════════════════════
class _StatCard extends StatelessWidget {
  final String label, value;
  final Color color;
  const _StatCard({
    required this.label,
    required this.value,
    required this.color,
  });
  @override
  Widget build(BuildContext context) => Expanded(
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: _TC.inputFill(context),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(fontSize: 10, color: _TC.textHint(context)),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    ),
  );
}

class _InfoCard extends StatelessWidget {
  final String label, value, sub;
  const _InfoCard({
    required this.label,
    required this.value,
    required this.sub,
  });
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    decoration: BoxDecoration(
      color: _TC.inputFill(context),
      borderRadius: BorderRadius.circular(10),
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
        Text(
          value,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: _TC.text(context),
          ),
        ),
        Text(sub, style: TextStyle(fontSize: 10, color: _TC.textSub(context))),
      ],
    ),
  );
}

// ── 小按钮 ────────────────────────────────────────────────
class _TopBarChip extends StatelessWidget {
  final String label;
  final IconData? icon;
  final Color color;
  final BuildContext ctx;
  final VoidCallback? onTap;
  final bool filled;

  const _TopBarChip({
    required this.label,
    required this.color,
    required this.ctx,
    this.icon,
    this.onTap,
    this.filled = false,
  });

  @override
  Widget build(BuildContext context) {
    final bg = filled ? color : color.withValues(alpha: 0.10);
    final border = filled ? Colors.transparent : color.withValues(alpha: 0.30);
    final fg = filled ? Colors.white : color;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: bg,
          border: Border.all(color: border),
          borderRadius: BorderRadius.circular(_timeLogActionChipRadius),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 12, color: fg),
              const SizedBox(width: 4),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: fg,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MinuteDropdown extends StatelessWidget {
  final int value;
  final ValueChanged<int> onChanged;

  const _MinuteDropdown({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;

    return Container(
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.10),
        border: Border.all(color: accent.withValues(alpha: 0.35)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int>(
          value: value,
          isDense: true,
          icon: Icon(Icons.expand_more, size: 14, color: accent),
          dropdownColor: Theme.of(context).colorScheme.surfaceContainerHighest,
          style: TextStyle(
            fontSize: 11,
            color: accent,
            fontWeight: FontWeight.w600,
          ),
          items: const [5, 10, 15, 30]
              .map((m) => DropdownMenuItem(value: m, child: Text('$m 分/格')))
              .toList(),
          onChanged: (m) {
            if (m != null) onChanged(m);
          },
        ),
      ),
    );
  }
}
