part of 'time_log_screen.dart';

// ══════════════════════════════════════════════════════════
// 日视图 — 补录模式（网格拖拽选时间段）
// ══════════════════════════════════════════════════════════
class _DayView extends StatefulWidget {
  final DateTime date;
  final bool crossDay;
  final List<TimeLogItem> logs;
  final List<PomodoroRecord> pomodoros;
  final List<PomodoroTag> tags;
  final VoidCallback onBack;
  final ValueChanged<bool> onCrossDayChanged;
  final void Function(TimeLogItem) onSaveLog;
  final void Function(PomodoroRecord) onPomodoroTap;
  final void Function(String) onDeleteLog;

  const _DayView(
      {required this.date,
      required this.crossDay,
      required this.logs,
      required this.pomodoros,
      required this.tags,
      required this.onBack,
      required this.onCrossDayChanged,
      required this.onSaveLog,
      required this.onPomodoroTap,
      required this.onDeleteLog});

  @override
  State<_DayView> createState() => _DayViewState();
}

class _DayViewState extends State<_DayView> {
  int _minutesPerBlock = 15;
  int? _dragStart, _dragEnd;
  String? _selectedTagId;

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
    showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => _LogEntrySheet(
            initialStart: st,
            initialEnd: en,
            initialTagId: _selectedTagId,
            tags: widget.tags,
            onSave: (log) {
              Navigator.pop(context);
              widget.onSaveLog(log);
            }));
  }

  void _showDayLogList() {
    final gsMs = _gridStart.millisecondsSinceEpoch;
    final geMs = gsMs + 86400000;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => StatefulBuilder(builder: (ctx, setModal) {
        final dayLogs = widget.logs
            .where((l) => l.endTime > gsMs && l.startTime < geMs)
            .toList()
          ..sort((a, b) => b.startTime.compareTo(a.startTime));
        return Container(
          padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx).padding.bottom + 16,
              left: 20,
              right: 20,
              top: 20),
          constraints:
              BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.75),
          decoration: BoxDecoration(
              color: _TC.card(ctx),
              border: Border(top: BorderSide(color: _TC.divider(ctx))),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(20))),
          child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Text('当天补录',
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: _TC.text(ctx))),
                  const SizedBox(width: 8),
                  Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 3),
                      decoration: BoxDecoration(
                          color: const Color(0xFF3B82F6).withOpacity(0.12),
                          borderRadius: BorderRadius.circular(20)),
                      child: Text('${dayLogs.length}条',
                          style: const TextStyle(
                              fontSize: 11,
                              color: Color(0xFF60A5FA),
                              fontWeight: FontWeight.w600))),
                  const Spacer(),
                  IconButton(
                      icon:
                          Icon(Icons.close, size: 20, color: _TC.textHint(ctx)),
                      onPressed: () => Navigator.pop(ctx)),
                ]),
                const SizedBox(height: 12),
                if (dayLogs.isEmpty)
                  Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: Center(
                          child: Text('暂无补录记录',
                              style: TextStyle(color: _TC.textHint(ctx)))))
                else
                  Flexible(
                      child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: dayLogs.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (ctx2, i) {
                      final log = dayLogs[i];
                      final tag = log.tagUuids.isNotEmpty
                          ? widget.tags.cast<PomodoroTag?>().firstWhere(
                              (t) => log.tagUuids.contains(t?.uuid),
                              orElse: () => null)
                          : null;
                      final c = tag != null
                          ? hexColor(tag.color)
                          : const Color(0xFF3B82F6);
                      final dur = (log.endTime - log.startTime) ~/ 60000;
                      final s =
                          DateTime.fromMillisecondsSinceEpoch(log.startTime);
                      final e =
                          DateTime.fromMillisecondsSinceEpoch(log.endTime);
                      return Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(
                            color: _TC.inputFill(ctx2),
                            border:
                                Border(left: BorderSide(color: c, width: 3)),
                            borderRadius: BorderRadius.circular(10)),
                        child: Row(children: [
                          Expanded(
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                Text(
                                    log.title.isNotEmpty
                                        ? log.title
                                        : (tag?.name ?? '补录记录'),
                                    style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: _TC.text(ctx2))),
                                const SizedBox(height: 3),
                                Row(children: [
                                  if (tag != null) ...[
                                    Container(
                                        width: 6,
                                        height: 6,
                                        decoration: BoxDecoration(
                                            color: c, shape: BoxShape.circle)),
                                    const SizedBox(width: 4),
                                    Text(tag.name,
                                        style: TextStyle(
                                            fontSize: 10,
                                            color: c,
                                            fontWeight: FontWeight.w600)),
                                    const SizedBox(width: 6),
                                  ],
                                  Text(
                                      '${DateFormat('HH:mm').format(s)} → ${DateFormat('HH:mm').format(e)}',
                                      style: TextStyle(
                                          fontSize: 10,
                                          color: _TC.textHint(ctx2))),
                                ]),
                              ])),
                          const SizedBox(width: 8),
                          Text('${dur}min',
                              style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: c)),
                          const SizedBox(width: 4),
                          IconButton(
                            icon: Icon(Icons.delete_outline,
                                size: 20, color: Colors.red.withOpacity(0.6)),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(
                                minWidth: 36, minHeight: 36),
                            onPressed: () {
                              showDialog(
                                  context: ctx,
                                  builder: (dCtx) => AlertDialog(
                                        backgroundColor: _TC.card(ctx),
                                        title: Text('删除记录',
                                            style: TextStyle(
                                                color: _TC.text(ctx),
                                                fontSize: 16)),
                                        content: Text(
                                            '确定删除「${log.title.isNotEmpty ? log.title : (tag?.name ?? '补录记录')}」吗？',
                                            style: TextStyle(
                                                color: _TC.textSub(ctx),
                                                fontSize: 13)),
                                        actions: [
                                          TextButton(
                                              onPressed: () =>
                                                  Navigator.pop(dCtx),
                                              child: Text('取消',
                                                  style: TextStyle(
                                                      color:
                                                          _TC.textSub(ctx)))),
                                          TextButton(
                                              onPressed: () {
                                                Navigator.pop(dCtx);
                                                widget.onDeleteLog(log.id);
                                                if (dayLogs.length <= 1)
                                                  Navigator.pop(ctx);
                                                else
                                                  setModal(() {});
                                              },
                                              child: const Text('删除',
                                                  style: TextStyle(
                                                      color: Colors.red,
                                                      fontWeight:
                                                          FontWeight.w700))),
                                        ],
                                      ));
                            },
                          ),
                        ]),
                      );
                    },
                  )),
              ]),
        );
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final gsMs = _gridStart.millisecondsSinceEpoch;
    final geMs = gsMs + 86400000;
    final dLogN =
        widget.logs.where((l) => l.endTime > gsMs && l.startTime < geMs).length;

    return Column(children: [
      _buildCrossDayBar(dLogN),
      Expanded(
          child: Row(children: [
        Expanded(child: LayoutBuilder(builder: (ctx, c) {
          final hourH = c.maxHeight / 24;
          return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
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
                            child: Text('${h.toString().padLeft(2, '0')}:00',
                                style: TextStyle(
                                    fontSize: 9,
                                    color:
                                        _TC.timeLabel(ctx, major: h % 6 == 0),
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.5)))))),
            Expanded(child: _buildGrid(hourH, c.maxHeight)),
          ]);
        })),
        _buildTagSidebar(),
      ])),
      if (_dragStart != null) _buildBottomBar(),
    ]);
  }

  Widget _buildCrossDayBar(int dLogN) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        color: _TC.topBar(context),
        child: Row(children: [
          const SizedBox(width: 8),
          // 已补录数量
          if (dLogN > 0)
            GestureDetector(
                onTap: _showDayLogList,
                child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                        color: const Color(0xFF3B82F6).withOpacity(0.1),
                        border: Border.all(
                            color: const Color(0xFF3B82F6).withOpacity(0.35)),
                        borderRadius: BorderRadius.circular(8)),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.list_alt_outlined,
                          size: 12, color: Color(0xFF60A5FA)),
                      const SizedBox(width: 4),
                      Text('已补录 $dLogN',
                          style: const TextStyle(
                              fontSize: 10,
                              color: Color(0xFF60A5FA),
                              fontWeight: FontWeight.w600)),
                    ]))),
          // 退出补录
          GestureDetector(
            onTap: widget.onBack,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.08),
                border: Border.all(color: Colors.red.withOpacity(0.30)),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.close, size: 12, color: Colors.red.withOpacity(0.8)),
                const SizedBox(width: 4),
                Text('退出补录',
                    style: TextStyle(
                        fontSize: 11,
                        color: Colors.red.withOpacity(0.8),
                        fontWeight: FontWeight.w600)),
              ]),
            ),
          ),
          const Spacer(),
          // 分钟下拉选择器
          _MinuteDropdown(
            value: _minutesPerBlock,
            onChanged: (m) => setState(() {
              _minutesPerBlock = m;
              _dragStart = null;
            }),
          ),
        ]),
      );

  Widget _buildGrid(double hourH, double totalH) {
    return LayoutBuilder(builder: (ctx, c) {
      final w = c.maxWidth;
      final isDark = Theme.of(ctx).brightness == Brightness.dark;
      final accent = Theme.of(ctx).colorScheme.primary;
      final selTag = widget.tags
          .cast<PomodoroTag?>()
          .firstWhere((t) => t?.uuid == _selectedTagId, orElse: () => null);

      return GestureDetector(
        onPanStart: (d) {
          final i = _getIndex(d.localPosition, w, hourH);
          if (i != null)
            setState(() {
              _dragStart = i;
              _dragEnd = i;
            });
        },
        onPanUpdate: (d) {
          final i = _getIndex(d.localPosition, w, hourH);
          if (i != null) setState(() => _dragEnd = i);
        },
        onTapDown: (d) {
          final i = _getIndex(d.localPosition, w, hourH);
          if (i != null)
            setState(() {
              _dragStart = i;
              _dragEnd = i;
            });
        },
        child: Stack(children: [
          SizedBox(
              height: totalH,
              child: CustomPaint(
                  size: Size(w, totalH),
                  painter: _DayGridPainter(
                      minutesPerBlock: _minutesPerBlock,
                      dragStart: _dragStart,
                      dragEnd: _dragEnd,
                      logs: widget.logs,
                      tags: widget.tags,
                      gridStart: _gridStart,
                      selColor: selTag != null
                          ? hexColor(selTag.color, opacity: 0.48)
                          : accent.withOpacity(0.45),
                      isDark: isDark,
                      hourH: hourH))),
          ..._pomodoroTapTargets(w, hourH),
        ]),
      );
    });
  }

  List<Widget> _pomodoroTapTargets(double width, double hourH) {
    final gsMs = _gridStart.millisecondsSinceEpoch;
    final geMs = gsMs + 86400000;
    final List<Widget> targets = [];
    for (final pom in widget.pomodoros) {
      final pe = pom.endTime ?? (pom.startTime + pom.effectiveDuration * 1000);
      if (pe <= gsMs || pom.startTime >= geMs) continue;
      final rs = max(pom.startTime, gsMs);
      final re = min(pe, geMs);
      final startF = (rs - gsMs) / 3600000;
      final endF = (re - gsMs) / 3600000;
      int sH = startF.floor();
      int eH = endF.floor();
      if (eH > sH && endF == eH.toDouble()) eH--;
      PomodoroTag? tag;
      if (pom.tagUuids.isNotEmpty)
        tag = widget.tags.cast<PomodoroTag?>().firstWhere(
            (t) => pom.tagUuids.contains(t?.uuid),
            orElse: () => null);
      final isDark = Theme.of(context).brightness == Brightness.dark;
      final base = tag != null ? hexColor(tag.color) : Colors.redAccent;
      final fill = base.withOpacity(isDark ? 0.35 : 0.45);
      final mark = base.withOpacity(0.85);
      for (int h = sH; h <= eH; h++) {
        final hS = max(h.toDouble(), startF);
        final hE = min((h + 1).toDouble(), endF);
        final left = (hS - h) * width;
        final right = (hE - h) * width;
        final bw = right - left;
        if (bw <= 0) continue;
        targets.add(Positioned(
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
                        border:
                            Border(left: BorderSide(color: mark, width: 3))),
                    child: bw > 20
                        ? Icon(Icons.timer_outlined, size: 12, color: mark)
                        : null))));
      }
    }
    return targets;
  }

  Widget _buildTagSidebar() => Container(
      width: 78,
      color: _TC.topBar(context),
      child: Column(children: [
        Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Text('TAGS',
                style: TextStyle(
                    fontSize: 8,
                    color: _TC.textHint(context),
                    letterSpacing: 2))),
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
                              horizontal: 5, vertical: 4),
                          padding: const EdgeInsets.symmetric(vertical: 9),
                          decoration: BoxDecoration(
                              color: sel ? c.withOpacity(0.2) : _TC.card(ctx),
                              border: Border.all(
                                  color: sel ? c : c.withOpacity(0.2),
                                  width: sel ? 1.5 : 1),
                              borderRadius: BorderRadius.circular(10)),
                          child: Column(children: [
                            Container(
                                width: 7,
                                height: 7,
                                decoration: BoxDecoration(
                                    color: c,
                                    shape: BoxShape.circle,
                                    boxShadow: sel
                                        ? [BoxShadow(color: c, blurRadius: 5)]
                                        : [])),
                            const SizedBox(height: 4),
                            Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 4),
                                child: Text(t.name,
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                        fontSize: 9,
                                        color: sel ? c : _TC.textSub(ctx),
                                        fontWeight: sel
                                            ? FontWeight.w700
                                            : FontWeight.w400),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis)),
                          ])));
                })),
      ]));

  Widget _buildBottomBar() {
    final gs = _gridStart;
    final st = gs.add(Duration(minutes: _ss * _minutesPerBlock));
    final en = gs.add(Duration(minutes: (_se + 1) * _minutesPerBlock));
    return Container(
      padding: EdgeInsets.fromLTRB(
          16, 14, 16, MediaQuery.of(context).padding.bottom + 14),
      decoration: BoxDecoration(
          color: _TC.card(context),
          border: Border(top: BorderSide(color: _TC.divider(context))),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(0.06),
                blurRadius: 12,
                offset: const Offset(0, -4))
          ]),
      child: Row(children: [
        Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
              Text('$_durMin 分钟',
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: _TC.text(context))),
              Text(
                  '${DateFormat('HH:mm').format(st)} → ${DateFormat('HH:mm').format(en)}',
                  style: TextStyle(fontSize: 11, color: _TC.textSub(context))),
            ])),
        TextButton(
            onPressed: () => setState(() {
                  _dragStart = null;
                  _dragEnd = null;
                }),
            child: Text('取消', style: TextStyle(color: _TC.textSub(context)))),
        const SizedBox(width: 8),
        ElevatedButton(
            onPressed: _openEntry,
            style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                elevation: 0),
            child: const Text('详情录入',
                style: TextStyle(fontWeight: FontWeight.w700))),
      ]),
    );
  }
}

// ══════════════════════════════════════════════════════════
// 补录模式网格 Painter
// ══════════════════════════════════════════════════════════
class _DayGridPainter extends CustomPainter {
  final int minutesPerBlock;
  final int? dragStart, dragEnd;
  final List<TimeLogItem> logs;
  final List<PomodoroTag> tags;
  final DateTime gridStart;
  final Color selColor;
  final bool isDark;
  final double hourH;

  _DayGridPainter(
      {required this.minutesPerBlock,
      this.dragStart,
      this.dragEnd,
      required this.logs,
      required this.tags,
      required this.gridStart,
      required this.selColor,
      required this.isDark,
      required this.hourH});

  @override
  void paint(Canvas canvas, Size size) {
    final bpr = 60 ~/ minutesPerBlock;
    final bw = size.width / bpr;
    final gsMs = gridStart.millisecondsSinceEpoch;
    final geMs = gsMs + 86400000;

    final mj = Paint()
      ..color = isDark ? const Color(0xFF1E1E1E) : const Color(0xFFDDDDDD)
      ..strokeWidth = 0.5;
    final mn = Paint()
      ..color = isDark ? const Color(0xFF0E0E0E) : const Color(0xFFF2F2F2)
      ..strokeWidth = 0.5;

    for (int h = 0; h <= 24; h++) {
      canvas.drawLine(Offset(0, h * hourH), Offset(size.width, h * hourH),
          h % 6 == 0 ? mj : mn);
    }
    for (int c = 0; c <= bpr; c++) {
      canvas.drawLine(
          Offset(c * bw, 0), Offset(c * bw, size.height), c % 4 == 0 ? mj : mn);
    }

    for (final log in logs) {
      if (log.endTime <= gsMs || log.startTime >= geMs) continue;
      final sMs = max(log.startTime, gsMs);
      final eMs = min(log.endTime, geMs);
      final sIdx = (sMs - gsMs) ~/ (60000 * minutesPerBlock);
      final eIdx = ((eMs - gsMs - 1) ~/ (60000 * minutesPerBlock))
          .clamp(0, 24 * bpr - 1);
      PomodoroTag? tag;
      if (log.tagUuids.isNotEmpty)
        tag = tags.cast<PomodoroTag?>().firstWhere(
            (t) => log.tagUuids.contains(t?.uuid),
            orElse: () => null);
      final fill = tag != null
          ? hexColor(tag.color, opacity: isDark ? 0.14 : 0.10)
          : (isDark ? const Color(0x18888888) : const Color(0x0F000000));
      final bar = tag != null
          ? hexColor(tag.color, opacity: 0.5)
          : (isDark ? const Color(0x44888888) : const Color(0x44000000));
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
                const Radius.circular(3)),
            Paint()..color = fill);
        canvas.drawRect(Rect.fromLTWH(left, i ~/ bpr * hourH + 1, 3, hourH - 2),
            Paint()..color = bar);
      }
    }

    if (dragStart != null && dragEnd != null) {
      final s = min(dragStart!, dragEnd!);
      final e = max(dragStart!, dragEnd!);
      for (int i = s; i <= e; i++) {
        final rowStartMs = gsMs + i * 60 * minutesPerBlock * 1000;
        final rowEndMs = rowStartMs + 60 * minutesPerBlock * 1000;
        final segStart = rowStartMs;
        final segEnd = min(rowEndMs, geMs);
        final startOffset = 0.0;
        final endOffset = (segEnd - rowStartMs) / (60 * minutesPerBlock * 1000);
        final left = i % bpr * bw + startOffset * bw;
        final width = ((endOffset - startOffset) * bw).clamp(1.0, bw);
        canvas.drawRRect(
            RRect.fromRectAndRadius(
                Rect.fromLTWH(left, i ~/ bpr * hourH + 1, width, hourH - 2),
                const Radius.circular(3)),
            Paint()..color = selColor);
      }
    }

    final now = DateTime.now();
    if (now.isAfter(gridStart) &&
        now.isBefore(gridStart.add(const Duration(days: 1)))) {
      final h = now.hour;
      final x = (now.minute + now.second / 60) / 60 * size.width;

      canvas.drawLine(
          Offset(x, h * hourH),
          Offset(x, (h + 1) * hourH),
          Paint()
            ..color = Colors.redAccent.withOpacity(0.7)
            ..strokeWidth = 1.5);
      canvas.drawCircle(
          Offset(x, h * hourH), 3, Paint()..color = Colors.redAccent);
    }
  }

  @override
  bool shouldRepaint(covariant _DayGridPainter o) => true;
}

// ══════════════════════════════════════════════════════════
// 补录详情面板 (兼容新增和编辑模式)
// ══════════════════════════════════════════════════════════
class _LogEntrySheet extends StatefulWidget {
  final DateTime initialStart, initialEnd;
  final String? initialTagId;
  final List<PomodoroTag> tags;
  final void Function(TimeLogItem) onSave;
  final TimeLogItem? existingLog;

  const _LogEntrySheet(
      {required this.initialStart,
      required this.initialEnd,
      this.initialTagId,
      required this.tags,
      required this.onSave,
      this.existingLog});
  @override
  State<_LogEntrySheet> createState() => _LogEntrySheetState();
}

class _LogEntrySheetState extends State<_LogEntrySheet> {
  late DateTime _start, _end;
  late String? _tagId;
  late TextEditingController _tc;

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
      final tag = widget.tags
          .cast<PomodoroTag?>()
          .firstWhere((t) => t?.uuid == _tagId, orElse: () => null);
      _tc = TextEditingController(text: tag?.name ?? '');
    }
  }

  @override
  void dispose() {
    _tc.dispose();
    super.dispose();
  }

  String _durLabel() {
    final m = _end.difference(_start).inMinutes;
    if (m <= 0) return '--';
    return m >= 60 ? '${m ~/ 60}h ${m % 60}m' : '${m}m';
  }

  Future<void> _pickTime(bool isStart) async {
    final t = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.fromDateTime(isStart ? _start : _end));
    if (t == null) return;
    setState(() {
      if (isStart)
        _start =
            DateTime(_start.year, _start.month, _start.day, t.hour, t.minute);
      else
        _end = DateTime(_end.year, _end.month, _end.day, t.hour, t.minute);
    });
  }

  Future<void> _pickDate(bool isStart) async {
    final d = await showDatePicker(
        context: context,
        initialDate: isStart ? _start : _end,
        firstDate: DateTime(2020),
        lastDate: DateTime.now().add(const Duration(days: 1)));
    if (d == null) return;
    setState(() {
      if (isStart)
        _start = DateTime(d.year, d.month, d.day, _start.hour, _start.minute);
      else
        _end = DateTime(d.year, d.month, d.day, _end.hour, _end.minute);
    });
  }

  void _save() {
    if (!_end.isAfter(_start)) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('结束时间必须晚于开始时间')));
      return;
    }

    final tag = widget.tags
        .cast<PomodoroTag?>()
        .firstWhere((t) => t?.uuid == _tagId, orElse: () => null);

    final log = TimeLogItem(
      id: widget.existingLog?.id,
      title: _tc.text.isNotEmpty ? _tc.text : (tag?.name ?? '未命名补录'),
      tagUuids: _tagId != null ? [_tagId!] : [],
      startTime: _start.millisecondsSinceEpoch,
      endTime: _end.millisecondsSinceEpoch,
      remark: widget.existingLog?.remark,
      version: widget.existingLog?.version ?? 1,
      createdAt: widget.existingLog?.createdAt,
      deviceId: widget.existingLog?.deviceId,
    );

    if (widget.existingLog != null) {
      log.markAsChanged();
    }

    widget.onSave(log);
  }

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return Container(
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom + 16,
          left: 20,
          right: 20,
          top: 20),
      decoration: BoxDecoration(
          color: _TC.card(context),
          border: Border(top: BorderSide(color: _TC.divider(context))),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20))),
      child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Text(widget.existingLog != null ? '编辑记录' : '补录事件',
                  style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: _TC.text(context))),
              const Spacer(),
              Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                      color: const Color(0xFF22C55E).withOpacity(0.12),
                      border: Border.all(
                          color: const Color(0xFF22C55E).withOpacity(0.35)),
                      borderRadius: BorderRadius.circular(20)),
                  child: Text(_durLabel(),
                      style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF4ADE80),
                          fontWeight: FontWeight.w600))),
            ]),
            const SizedBox(height: 16),
            Text('CATEGORY',
                style: TextStyle(
                    fontSize: 9,
                    color: _TC.textHint(context),
                    letterSpacing: 2)),
            const SizedBox(height: 8),
            Wrap(
                spacing: 8,
                runSpacing: 6,
                children: widget.tags.map((t) {
                  final c = hexColor(t.color);
                  final sel = _tagId == t.uuid;
                  return GestureDetector(
                      onTap: () => setState(() {
                            _tagId = t.uuid;
                            _tc.text = t.name;
                          }),
                      child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 7),
                          decoration: BoxDecoration(
                              color: sel
                                  ? c.withOpacity(0.2)
                                  : c.withOpacity(0.06),
                              border: Border.all(
                                  color: sel ? c : c.withOpacity(0.3)),
                              borderRadius: BorderRadius.circular(20)),
                          child: Text(t.name,
                              style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: sel ? c : c.withOpacity(0.7)))));
                }).toList()),
            const SizedBox(height: 16),
            Text('TITLE',
                style: TextStyle(
                    fontSize: 9,
                    color: _TC.textHint(context),
                    letterSpacing: 2)),
            const SizedBox(height: 6),
            TextField(
                controller: _tc,
                style: TextStyle(color: _TC.text(context), fontSize: 13),
                decoration: InputDecoration(
                    hintText: '事件名称（留空使用标签名）',
                    hintStyle:
                        TextStyle(color: _TC.textHint(context), fontSize: 13),
                    filled: true,
                    fillColor: _TC.inputFill(context),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: _TC.divider(context))),
                    enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: _TC.divider(context))),
                    focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: accent)),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10))),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(
                  child: _TimePickerCard(
                      label: '开始时间',
                      dt: _start,
                      onTapTime: () => _pickTime(true),
                      onTapDate: () => _pickDate(true))),
              const SizedBox(width: 10),
              Expanded(
                  child: _TimePickerCard(
                      label: '结束时间',
                      dt: _end,
                      onTapTime: () => _pickTime(false),
                      onTapDate: () => _pickDate(false))),
            ]),
            const SizedBox(height: 20),
            SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                    onPressed: _save,
                    style: ElevatedButton.styleFrom(
                        backgroundColor: accent,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        elevation: 0),
                    child: const Text('保存记录',
                        style: TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w700)))),
          ]),
    );
  }
}

class _TimePickerCard extends StatelessWidget {
  final String label;
  final DateTime dt;
  final VoidCallback onTapTime, onTapDate;
  const _TimePickerCard(
      {required this.label,
      required this.dt,
      required this.onTapTime,
      required this.onTapDate});
  @override
  Widget build(BuildContext context) => GestureDetector(
      onTap: onTapTime,
      child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
              color: _TC.inputFill(context),
              border: Border.all(color: _TC.divider(context)),
              borderRadius: BorderRadius.circular(12)),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label,
                style: TextStyle(
                    fontSize: 9,
                    color: _TC.textHint(context),
                    letterSpacing: 1)),
            const SizedBox(height: 4),
            GestureDetector(
                onTap: onTapDate,
                child: Text(DateFormat('MM月dd日').format(dt),
                    style:
                        TextStyle(fontSize: 11, color: _TC.textSub(context)))),
            const SizedBox(height: 4),
            Row(children: [
              Text(DateFormat('HH:mm').format(dt),
                  style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: _TC.text(context))),
              const SizedBox(width: 6),
              Icon(Icons.access_time, size: 14, color: _TC.textHint(context)),
            ]),
          ])));
}

// ══════════════════════════════════════════════════════════
// 标签详情面板相关 (模型、图表容器、图表画笔)
// ══════════════════════════════════════════════════════════

class _TagRecord {
  final bool isPomodoro;
  final String title, id;
  final int startTime, endTime, durationMin;
  final bool isCompleted;
  const _TagRecord(
      {required this.isPomodoro,
      required this.title,
      required this.startTime,
      required this.endTime,
      required this.durationMin,
      required this.id,
      this.isCompleted = false});
}

class _TagDetailSheet extends StatefulWidget {
  final PomodoroTag tag;
  final List<TimeLogItem> logs;
  final List<PomodoroRecord> pomodoros;
  final void Function(String) onDelete;
  const _TagDetailSheet(
      {required this.tag,
      required this.logs,
      this.pomodoros = const [],
      required this.onDelete});

  @override
  State<_TagDetailSheet> createState() => _TagDetailSheetState();
}

enum _ChartScale { session, day, week, month }

class _TagDetailSheetState extends State<_TagDetailSheet> {
  int _chartType = 0; // 0: 时长, 1: 开始时间, 2: 结束时间
  _ChartScale _scale = _ChartScale.session;
  Offset? _touchPos;

  Widget _buildChartTab(String title, int index, Color color) {
    final isSel = _chartType == index;
    return GestureDetector(
      onTap: () => setState(() => _chartType = index),
      child: Container(
        margin: const EdgeInsets.only(left: 6),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: isSel ? color.withOpacity(0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(title,
            style: TextStyle(
              fontSize: 11,
              color: isSel ? color : _TC.textSub(context),
              fontWeight: isSel ? FontWeight.w700 : FontWeight.w500,
            )),
      ),
    );
  }

  Widget _buildScaleTab(String title, _ChartScale scale, Color color) {
    final isSel = _scale == scale;
    return GestureDetector(
      onTap: () => setState(() {
        _scale = scale;
        if (scale != _ChartScale.session) _chartType = 0; // 聚合模式仅限时长
      }),
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: isSel ? color : _TC.inputFill(context),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: isSel ? color : _TC.divider(context), width: 1),
        ),
        child: Text(title,
            style: TextStyle(
              fontSize: 10,
              color: isSel ? Colors.white : _TC.textSub(context),
              fontWeight: isSel ? FontWeight.w700 : FontWeight.w500,
            )),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tagLogs =
        widget.logs.where((l) => l.tagUuids.contains(widget.tag.uuid)).toList();
    final tagPoms = widget.pomodoros
        .where((p) => p.tagUuids.contains(widget.tag.uuid))
        .toList();

    final allRecs = <_TagRecord>[
      ...tagLogs.map((l) => _TagRecord(
          isPomodoro: false,
          title: l.title.isNotEmpty ? l.title : widget.tag.name,
          startTime: l.startTime,
          endTime: l.endTime,
          durationMin: (l.endTime - l.startTime) ~/ 60000,
          id: l.id)),
      ...tagPoms.map((p) {
        final end = p.endTime ?? (p.startTime + p.effectiveDuration * 1000);
        return _TagRecord(
            isPomodoro: true,
            title: (p.todoTitle?.isNotEmpty ?? false)
                ? p.todoTitle!
                : widget.tag.name,
            startTime: p.startTime,
            endTime: end,
            durationMin: (end - p.startTime) ~/ 60000,
            id: p.uuid,
            isCompleted: p.isCompleted ?? false);
      }),
    ]..sort((a, b) => a.startTime.compareTo(b.startTime)); // 改为升序，方便聚合处理

    final totalMin = allRecs.fold(0, (s, r) => s + r.durationMin);
    final avgMin = allRecs.isEmpty ? 0 : totalMin ~/ allRecs.length;
    final maxMin =
        allRecs.isEmpty ? 0 : allRecs.map((r) => r.durationMin).reduce(max);
    final c = hexColor(widget.tag.color);

    // ── 数据聚合处理逻辑 ─────────────────────────────────────
    List<int> chartData = [];
    List<String> xLabels = [];
    String Function(int) formatLabel = (v) => '${v}m';

    if (_scale == _ChartScale.session) {
      final chartRecs = allRecs.length > 30 ? allRecs.sublist(allRecs.length - 30) : allRecs;
      if (_chartType == 0) {
        chartData = chartRecs.map((r) => r.durationMin).toList();
        formatLabel = (v) => '${v}m';
      } else {
        chartData = chartRecs.map((r) {
          final dt = DateTime.fromMillisecondsSinceEpoch(
              _chartType == 1 ? r.startTime : r.endTime);
          return dt.hour * 60 + dt.minute;
        }).toList();
        formatLabel = (v) =>
            '${(v ~/ 60).toString().padLeft(2, '0')}:${(v % 60).toString().padLeft(2, '0')}';
      }
      xLabels = chartRecs.map((r) {
        final dt = DateTime.fromMillisecondsSinceEpoch(r.startTime);
        return DateFormat('MM/dd').format(dt);
      }).toList();
    } else {
      // 按天/周/月聚合
      final Map<String, int> grouped = {};
      for (final r in allRecs) {
        final dt = DateTime.fromMillisecondsSinceEpoch(r.startTime);
        String key;
        if (_scale == _ChartScale.day) {
          key = DateFormat('MM/dd').format(dt);
        } else if (_scale == _ChartScale.week) {
          final weekStart = dt.subtract(Duration(days: dt.weekday - 1));
          key = 'W${DateFormat('MM/dd').format(weekStart)}';
        } else {
          key = DateFormat('yy/MM').format(dt);
        }
        grouped[key] = (grouped[key] ?? 0) + r.durationMin;
      }
      final sortedKeys = grouped.keys.toList(); // 已经按时间顺序
      xLabels = sortedKeys.length > 20 ? sortedKeys.sublist(sortedKeys.length - 20) : sortedKeys;
      chartData = xLabels.map((k) => grouped[k]!).toList();
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      decoration: BoxDecoration(
          color: _TC.card(context),
          border:
              Border(top: BorderSide(color: c.withOpacity(0.35), width: 1.5)),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24))),
      child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                      color: c,
                      shape: BoxShape.circle,
                      boxShadow: [BoxShadow(color: c, blurRadius: 8)])),
              const SizedBox(width: 10),
              Text(widget.tag.name,
                  style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: _TC.text(context))),
              const Spacer(),
              Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                      color: c.withOpacity(0.12),
                      border: Border.all(color: c.withOpacity(0.3)),
                      borderRadius: BorderRadius.circular(20)),
                  child: Text('${(totalMin / 60).toStringAsFixed(1)}h 累计',
                      style: TextStyle(
                          fontSize: 11,
                          color: c,
                          fontWeight: FontWeight.w600))),
              IconButton(
                  icon:
                      Icon(Icons.close, color: _TC.textHint(context), size: 20),
                  onPressed: () => Navigator.pop(context)),
            ]),
            const SizedBox(height: 16),
            Row(children: [
              _StatCard(label: '记录次数', value: '${allRecs.length}次', color: c),
              const SizedBox(width: 10),
              _StatCard(label: '平均时长', value: '${avgMin}min', color: c),
              const SizedBox(width: 10),
              _StatCard(label: '最长一次', value: '${maxMin}min', color: c),
            ]),
            const SizedBox(height: 16),
            Row(children: [
              Text('DIMENSIONS',
                  style: TextStyle(
                      fontSize: 9,
                      color: _TC.textHint(context),
                      letterSpacing: 2,
                      fontWeight: FontWeight.w700)),
              const Spacer(),
              _buildScaleTab('按次', _ChartScale.session, c),
              _buildScaleTab('日', _ChartScale.day, c),
              _buildScaleTab('周', _ChartScale.week, c),
              _buildScaleTab('月', _ChartScale.month, c),
            ]),
            const SizedBox(height: 12),
            Row(children: [
              Text('TRENDS',
                  style: TextStyle(
                      fontSize: 9,
                      color: _TC.textHint(context),
                      letterSpacing: 2,
                      fontWeight: FontWeight.w700)),
              const Spacer(),
              _buildChartTab('时长', 0, c),
              if (_scale == _ChartScale.session) ...[
                _buildChartTab('开始', 1, c),
                _buildChartTab('结束', 2, c),
              ],
            ]),
            const SizedBox(height: 10),
            if (chartData.length >= 2)
              _MiniLineChart(
                  data: chartData,
                  xLabels: xLabels,
                  color: c,
                  height: 130,
                  formatLabel: formatLabel,
                  touchPos: _touchPos,
                  onTouch: (p) => setState(() => _touchPos = p))
            else
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Center(
                    child: Text('数据采集中...',
                        style: TextStyle(
                            fontSize: 11, color: _TC.textHint(context)))),
              ),
            const SizedBox(height: 16),
            Text('RECENT RECORDS',
                style: TextStyle(
                    fontSize: 9,
                    color: _TC.textHint(context),
                    letterSpacing: 2)),
            const SizedBox(height: 8),
            ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 220),
                child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: allRecs.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 6),
                    itemBuilder: (ctx, i) {
                      final r = allRecs.reversed.elementAt(i);
                      final s =
                          DateTime.fromMillisecondsSinceEpoch(r.startTime);
                      final e = DateTime.fromMillisecondsSinceEpoch(r.endTime);
                      return Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                            color: _TC.inputFill(ctx),
                            border: Border(
                                left: BorderSide(
                                    color: r.isPomodoro ? Colors.redAccent : c,
                                    width: 3)),
                            borderRadius: BorderRadius.circular(8)),
                        child: Row(children: [
                          if (r.isPomodoro) ...[
                            Icon(Icons.timer_outlined,
                                size: 12,
                                color: Colors.redAccent.withOpacity(0.6)),
                            const SizedBox(width: 4),
                          ],
                          Expanded(
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                Text(r.title,
                                    style: TextStyle(
                                        fontSize: 12,
                                        color: _TC.text(ctx),
                                        fontWeight: FontWeight.w600)),
                                const SizedBox(height: 2),
                                Text(
                                    '${DateFormat('MM/dd').format(s)} ${DateFormat('HH:mm').format(s)} → ${DateFormat('HH:mm').format(e)}',
                                    style: TextStyle(
                                        fontSize: 10,
                                        color: _TC.textHint(ctx))),
                              ])),
                          Text('${r.durationMin}min',
                              style: TextStyle(
                                  fontSize: 13,
                                  color: r.isPomodoro ? Colors.redAccent : c,
                                  fontWeight: FontWeight.w700)),
                          if (!r.isPomodoro)
                            IconButton(
                                icon: Icon(Icons.delete_outline,
                                    color: Colors.red.withOpacity(0.55),
                                    size: 18),
                                onPressed: () => widget.onDelete(r.id),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints())
                          else
                            const SizedBox(width: 40),
                        ]),
                      );
                    })),
            SizedBox(height: MediaQuery.of(context).padding.bottom + 16),
          ]),
    );
  }
}

class _MiniLineChart extends StatefulWidget {
  final List<int> data;
  final List<String> xLabels;
  final Color color;
  final double height;
  final String Function(int) formatLabel;
  final Offset? touchPos;
  final ValueChanged<Offset?> onTouch;

  const _MiniLineChart(
      {required this.data,
      required this.xLabels,
      required this.color,
      this.height = 130,
      required this.formatLabel,
      this.touchPos,
      required this.onTouch});

  @override
  State<_MiniLineChart> createState() => _MiniLineChartState();
}

class _MiniLineChartState extends State<_MiniLineChart> {
  late ScrollController _sc;

  @override
  void initState() {
    super.initState();
    _sc = ScrollController();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_sc.hasClients) {
        _sc.jumpTo(_sc.position.maxScrollExtent);
      }
    });
  }

  @override
  void didUpdateWidget(_MiniLineChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.data.length != widget.data.length) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_sc.hasClients) {
          _sc.animateTo(_sc.position.maxScrollExtent,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOut);
        }
      });
    }
  }

  @override
  void dispose() {
    _sc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width - 40;
    const double itemW = 55.0; // 固定间距
    final double chartContentW = (widget.data.length - 1) * itemW + 40;
    final double scrollWidth = max(screenWidth, chartContentW);

    return SizedBox(
      height: widget.height,
      width: double.infinity,
      child: GestureDetector(
        onPanUpdate: (d) => widget.onTouch(d.localPosition.translate(_sc.offset, 0)),
        onPanEnd: (_) => widget.onTouch(null),
        onTapDown: (d) => widget.onTouch(d.localPosition.translate(_sc.offset, 0)),
        onTapUp: (_) => widget.onTouch(null),
        child: SingleChildScrollView(
          controller: _sc,
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          child: SizedBox(
            width: scrollWidth,
            height: widget.height,
            child: CustomPaint(
                painter: _LineChartPainter(
                    data: widget.data,
                    xLabels: widget.xLabels,
                    color: widget.color,
                    formatLabel: widget.formatLabel,
                    touchPos: widget.touchPos,
                    itemW: itemW)),
          ),
        ),
      ),
    );
  }
}

class _LineChartPainter extends CustomPainter {
  final List<int> data;
  final List<String> xLabels;
  final Color color;
  final String Function(int) formatLabel;
  final Offset? touchPos;
  final double itemW;

  _LineChartPainter(
      {required this.data,
      required this.xLabels,
      required this.color,
      required this.formatLabel,
      this.touchPos,
      required this.itemW});

  @override
  void paint(Canvas canvas, Size size) {
    if (data.length < 1) return;
    final minV = data.reduce(min).toDouble();
    final maxV = data.reduce(max).toDouble();
    final range = (maxV - minV) < 1 ? 10.0 : maxV - minV;

    double calcY(double v) {
      return size.height - 30 - ((v - minV) / range) * (size.height - 60);
    }

    // 计算起始位置，如果数据点较少，则靠右排列，保持固定间距
    final double totalPointsW = (data.length - 1) * itemW;
    final double startX = max(20.0, size.width - 20 - totalPointsW);
    
    final pts = List.generate(
        data.length, (i) => Offset(startX + i * itemW, calcY(data[i].toDouble())));

    if (data.length < 2) {
      // 只有一个点的情况
      final p = pts[0];
      canvas.drawCircle(p, 6, Paint()..color = color);
      return;
    }

    // 1. 绘制面积渐变
    final fillPath = Path();
    fillPath.moveTo(pts[0].dx, size.height - 30);
    fillPath.lineTo(pts[0].dx, pts[0].dy);
    for (int i = 0; i < pts.length - 1; i++) {
      final p1 = pts[i];
      final p2 = pts[i + 1];
      final control1 = Offset(p1.dx + (p2.dx - p1.dx) / 2, p1.dy);
      final control2 = Offset(p1.dx + (p2.dx - p1.dx) / 2, p2.dy);
      fillPath.cubicTo(
          control1.dx, control1.dy, control2.dx, control2.dy, p2.dx, p2.dy);
    }
    fillPath.lineTo(pts.last.dx, size.height - 30);
    fillPath.close();

    final gradient = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [color.withOpacity(0.3), color.withOpacity(0.0)],
    );
    canvas.drawPath(fillPath,
        Paint()..shader = gradient.createShader(Rect.fromLTWH(0, 0, size.width, size.height)));

    // 2. 绘制平滑曲线
    final path = Path();
    path.moveTo(pts[0].dx, pts[0].dy);
    for (int i = 0; i < pts.length - 1; i++) {
      final p1 = pts[i];
      final p2 = pts[i + 1];
      final control1 = Offset(p1.dx + (p2.dx - p1.dx) / 2, p1.dy);
      final control2 = Offset(p1.dx + (p2.dx - p1.dx) / 2, p2.dy);
      path.cubicTo(
          control1.dx, control1.dy, control2.dx, control2.dy, p2.dx, p2.dy);
    }
    canvas.drawPath(
        path,
        Paint()
          ..color = color
          ..strokeWidth = 3.0
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round);

    // 3. 绘制坐标轴与点
    int? activeIdx;
    if (touchPos != null) {
      double minD = 9999;
      for (int i = 0; i < pts.length; i++) {
        final d = (pts[i].dx - touchPos!.dx).abs();
        if (d < minD) {
          minD = d;
          activeIdx = i;
        }
      }
    }

    for (int i = 0; i < pts.length; i++) {
      final p = pts[i];
      final isHover = i == activeIdx;
      
      // 节点点
      canvas.drawCircle(p, isHover ? 6 : 4, Paint()..color = color);
      if (isHover) {
        canvas.drawCircle(p, 10, Paint()..color = color.withOpacity(0.2));
      }

      // X轴标签
      if (i % (data.length > 10 ? 2 : 1) == 0) {
        final dateTp = TextPainter(
          text: TextSpan(
            text: xLabels[i],
            style: TextStyle(fontSize: 9, color: color.withOpacity(0.6), fontWeight: FontWeight.w500),
          ),
          textDirection: ui.TextDirection.ltr,
        )..layout();
        dateTp.paint(canvas, Offset(p.dx - dateTp.width / 2, size.height - 18));
      }

      // 活跃点的指示线和数值
      if (isHover) {
        final lineP = Paint()..color = color.withOpacity(0.5)..strokeWidth = 1.0;
        canvas.drawLine(Offset(p.dx, 0), Offset(p.dx, size.height - 30), lineP);
        
        final valText = formatLabel(data[i]);
        final valTp = TextPainter(
          text: TextSpan(
            text: valText,
            style: const TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.bold),
          ),
          textDirection: ui.TextDirection.ltr,
        )..layout();
        
        // 绘制气泡背景
        final bgR = Rect.fromCenter(center: Offset(p.dx, p.dy - 25), width: valTp.width + 16, height: valTp.height + 8);
        canvas.drawRRect(RRect.fromRectAndRadius(bgR, const Radius.circular(8)), Paint()..color = color);
        valTp.paint(canvas, Offset(p.dx - valTp.width / 2, p.dy - 25 - valTp.height / 2));
      }
    }
  }

  @override
  bool shouldRepaint(covariant _LineChartPainter o) => true;
}

// ══════════════════════════════════════════════════════════
// 信息展示小组件
// ══════════════════════════════════════════════════════════
class _StatCard extends StatelessWidget {
  final String label, value;
  final Color color;
  const _StatCard(
      {required this.label, required this.value, required this.color});
  @override
  Widget build(BuildContext context) => Expanded(
      child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
              color: _TC.inputFill(context),
              borderRadius: BorderRadius.circular(10)),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label,
                style: TextStyle(fontSize: 10, color: _TC.textHint(context))),
            const SizedBox(height: 4),
            Text(value,
                style: TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w700, color: color)),
          ])));
}

class _InfoCard extends StatelessWidget {
  final String label, value, sub;
  const _InfoCard(
      {required this.label, required this.value, required this.sub});
  @override
  Widget build(BuildContext context) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
          color: _TC.inputFill(context),
          borderRadius: BorderRadius.circular(10)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label,
            style: TextStyle(
                fontSize: 9, color: _TC.textHint(context), letterSpacing: 1)),
        const SizedBox(height: 4),
        Text(value,
            style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: _TC.text(context))),
        Text(sub, style: TextStyle(fontSize: 10, color: _TC.textSub(context))),
      ]));
}

// ══════════════════════════════════════════════════════════
// 标签管理面板
// ══════════════════════════════════════════════════════════
class _TagManagerSheet extends StatefulWidget {
  final List<PomodoroTag> tags;
  const _TagManagerSheet({required this.tags});
  @override
  State<_TagManagerSheet> createState() => _TagManagerSheetState();
}

class _TagManagerSheetState extends State<_TagManagerSheet> {
  late List<PomodoroTag> _list;
  final _nc = TextEditingController();
  String _newColor = kPalette[0];

  @override
  void initState() {
    super.initState();
    _list = widget.tags
        .map((t) => PomodoroTag(uuid: t.uuid, name: t.name, color: t.color))
        .toList();
  }

  @override
  void dispose() {
    _nc.dispose();
    super.dispose();
  }

  void _add() {
    if (_nc.text.trim().isEmpty) return;
    setState(() {
      _list.add(PomodoroTag(
          uuid: 'tag_${DateTime.now().millisecondsSinceEpoch}',
          name: _nc.text.trim(),
          color: _newColor));
      _nc.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return Container(
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom + 16,
          left: 20,
          right: 20,
          top: 20),
      decoration: BoxDecoration(
          color: _TC.card(context),
          border: Border(top: BorderSide(color: _TC.divider(context))),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20))),
      child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Text('标签管理',
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: _TC.text(context))),
              const Spacer(),
              IconButton(
                  icon:
                      Icon(Icons.close, color: _TC.textHint(context), size: 20),
                  onPressed: () => Navigator.pop(context)),
            ]),
            const SizedBox(height: 12),
            ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 260),
                child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: _list.length,
                    itemBuilder: (ctx, i) {
                      final t = _list[i];
                      final c = hexColor(t.color);
                      return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(children: [
                            Container(
                                width: 10,
                                height: 10,
                                decoration: BoxDecoration(
                                    color: c, shape: BoxShape.circle)),
                            const SizedBox(width: 8),
                            Expanded(
                                child: TextField(
                                    controller: TextEditingController(text: t.name)
                                      ..selection = TextSelection.collapsed(
                                          offset: t.name.length),
                                    onChanged: (v) => _list[i] = PomodoroTag(
                                        uuid: t.uuid, name: v, color: t.color),
                                    style: TextStyle(
                                        fontSize: 12, color: _TC.text(ctx)),
                                    decoration: InputDecoration(
                                        isDense: true,
                                        filled: true,
                                        fillColor: _TC.inputFill(ctx),
                                        border: OutlineInputBorder(
                                            borderRadius:
                                                BorderRadius.circular(8),
                                            borderSide: BorderSide(
                                                color: _TC.divider(ctx))),
                                        enabledBorder: OutlineInputBorder(
                                            borderRadius:
                                                BorderRadius.circular(8),
                                            borderSide: BorderSide(
                                                color: _TC.divider(ctx))),
                                        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8)))),
                            const SizedBox(width: 6),
                            Wrap(
                                spacing: 3,
                                children: kPalette
                                    .map((pc) => GestureDetector(
                                        onTap: () => setState(() => _list[i] =
                                            PomodoroTag(
                                                uuid: t.uuid,
                                                name: t.name,
                                                color: pc)),
                                        child: Container(
                                            width: 14,
                                            height: 14,
                                            decoration: BoxDecoration(
                                                color: hexColor(pc),
                                                shape: BoxShape.circle,
                                                border: Border.all(
                                                    color: t.color == pc
                                                        ? Colors.white
                                                        : Colors.transparent,
                                                    width: 1.5)))))
                                    .toList()),
                            const SizedBox(width: 6),
                            GestureDetector(
                                onTap: () => setState(() => _list.removeAt(i)),
                                child: Icon(Icons.delete_outline,
                                    color: Colors.red.withOpacity(0.55),
                                    size: 18)),
                          ]));
                    })),
            Divider(color: _TC.divider(context), height: 24),
            Text('NEW TAG',
                style: TextStyle(
                    fontSize: 9,
                    color: _TC.textHint(context),
                    letterSpacing: 2)),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                  child: TextField(
                      controller: _nc,
                      onSubmitted: (_) => _add(),
                      style: TextStyle(fontSize: 13, color: _TC.text(context)),
                      decoration: InputDecoration(
                          hintText: '标签名称',
                          hintStyle: TextStyle(color: _TC.textHint(context)),
                          isDense: true,
                          filled: true,
                          fillColor: _TC.inputFill(context),
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide:
                                  BorderSide(color: _TC.divider(context))),
                          enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide:
                                  BorderSide(color: _TC.divider(context))),
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 10)))),
              const SizedBox(width: 8),
              ElevatedButton(
                  onPressed: _add,
                  style: ElevatedButton.styleFrom(
                      backgroundColor: accent.withOpacity(0.15),
                      foregroundColor: accent,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8))),
                  child: const Text('+ 添加',
                      style: TextStyle(fontWeight: FontWeight.w600))),
            ]),
            const SizedBox(height: 8),
            Wrap(
                spacing: 6,
                children: kPalette.map((pc) {
                  final cc = hexColor(pc);
                  return GestureDetector(
                      onTap: () => setState(() => _newColor = pc),
                      child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          width: 24,
                          height: 24,
                          decoration: BoxDecoration(
                              color: cc,
                              shape: BoxShape.circle,
                              border: Border.all(
                                  color: _newColor == pc
                                      ? Colors.white
                                      : Colors.transparent,
                                  width: 2),
                              boxShadow: _newColor == pc
                                  ? [BoxShadow(color: cc, blurRadius: 6)]
                                  : [])));
                }).toList()),
            const SizedBox(height: 16),
            SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                    onPressed: () => Navigator.pop(context, _list),
                    style: ElevatedButton.styleFrom(
                        backgroundColor: accent,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        elevation: 0),
                    child: const Text('保存',
                        style: TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w700)))),
            SizedBox(height: MediaQuery.of(context).padding.bottom + 4),
          ]),
    );
  }
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
    final bg = filled ? color : color.withOpacity(0.10);
    final border = filled ? Colors.transparent : color.withOpacity(0.30);
    final fg = filled ? Colors.white : color;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: bg,
          border: Border.all(color: border),
          borderRadius: BorderRadius.circular(8),
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
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: accent.withOpacity(0.10),
        border: Border.all(color: accent.withOpacity(0.35)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int>(
          value: value,
          isDense: true,
          icon: Icon(Icons.expand_more, size: 14, color: accent),
          dropdownColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
          style: TextStyle(
            fontSize: 11,
            color: accent,
            fontWeight: FontWeight.w600,
          ),
          items: const [5, 10, 15, 30]
              .map((m) => DropdownMenuItem(
                    value: m,
                    child: Text('$m 分/格'),
                  ))
              .toList(),
          onChanged: (m) {
            if (m != null) onChanged(m);
          },
        ),
      ),
    );
  }
}

class _TinyButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final bool primary;
  const _TinyButton(
      {required this.label, required this.onTap, this.primary = false});
  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return GestureDetector(
        onTap: onTap,
        child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
                color: primary ? accent : _TC.btnBg(context),
                border: Border.all(
                    color:
                        primary ? Colors.transparent : _TC.btnBorder(context)),
                borderRadius: BorderRadius.circular(8)),
            child: Text(label,
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: primary ? FontWeight.w700 : FontWeight.w400,
                    color: primary ? Colors.white : _TC.textSub(context)))));
  }
}
