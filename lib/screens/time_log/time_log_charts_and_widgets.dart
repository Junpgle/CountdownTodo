part of '../time_log_screen.dart';

// ══════════════════════════════════════════════════════════
// 补录模式网格 Painter
// ══════════════════════════════════════════════════════════
class _DayGridPainter extends CustomPainter {
  final int minutesPerBlock;
  final List<TimeLogItem> logs;
  final List<TodoPlanBlock> planBlocks;
  final List<TimeLogMappedSchedule> schedules;
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
    this.schedules = const [],
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

  static final Paint _majorGridPaint = Paint()..strokeWidth = 0.5;
  static final Paint _minorGridPaint = Paint()..strokeWidth = 0.5;
  static final Paint _eventFillPaint = Paint();
  static final Paint _eventBarPaint = Paint();

  @override
  void paint(Canvas canvas, Size size) {
    final bpr = 60 ~/ minutesPerBlock;
    final bw = size.width / bpr;
    final gsMs = gridStart.millisecondsSinceEpoch;
    final geMs = _dayEndMs(gridStart);

    final mj = _majorGridPaint..color = gridMajorColor;
    final mn = _minorGridPaint..color = gridMinorColor;
    final eventFillPaint = _eventFillPaint;
    final eventBarPaint = _eventBarPaint;

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

    for (final schedule in schedules) {
      if (schedule.endTime <= gsMs || schedule.startTime >= geMs) continue;
      final sMs = max(schedule.startTime, gsMs);
      final eMs = min(schedule.endTime, geMs);
      final sIdx = (sMs - gsMs) ~/ (60000 * minutesPerBlock);
      final eIdx = ((eMs - gsMs - 1) ~/ (60000 * minutesPerBlock)).clamp(
        0,
        24 * bpr - 1,
      );
      final base = schedule.isCourse
          ? (isDark ? const Color(0xFF64B5F6) : const Color(0xFF1E88E5))
          : (isDark ? const Color(0xFFFFB74D) : const Color(0xFFFB8C00));
      final fill = base.withValues(alpha: isDark ? 0.16 : 0.10);
      final bar = base.withValues(alpha: 0.65);
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
          Rect.fromLTWH(left, i ~/ bpr * hourH + 1, 2.5, hourH - 2),
          eventBarPaint,
        );
      }
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
      !identical(o.schedules, schedules) ||
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
  static final Paint _selectionPaint = Paint();
  static final Paint _currentTimeLinePaint = Paint();
  static final Paint _currentTimeDotPaint = Paint();

  _DayGridInteractionPainter({
    required this.minutesPerBlock,
    required this.dragStart,
    required this.dragEnd,
    required this.gridStart,
    required this.selColor,
    required this.nowColor,
    required this.hourH,
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
      _selectionPaint.color = selColor;
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
          _selectionPaint,
        );
      }
    }

    final now = DateTime.now();
    if (!DateUtils.isSameDay(now, gridStart)) return;
    final hour = now.hour;
    final x = (now.minute + now.second / 60) / 60 * size.width;
    _currentTimeLinePaint
      ..color = nowColor.withValues(alpha: 0.7)
      ..strokeWidth = 1.5;
    _currentTimeDotPaint.color = nowColor;
    canvas.drawLine(
      Offset(x, hour * hourH),
      Offset(x, (hour + 1) * hourH),
      _currentTimeLinePaint,
    );
    canvas.drawCircle(Offset(x, hour * hourH), 3, _currentTimeDotPaint);
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
    final screenWidth = MediaQuery.sizeOf(context).width - 40;
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
                RepaintBoundary(
                  child: CustomPaint(
                    painter: _LineChartPainter(
                      geometry: geometry,
                      xLabels: widget.xLabels,
                      xLabelPainters: _xLabelPainters,
                      touchPos: _touchPos,
                    ),
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

  static final Paint _pointPaint = Paint();
  static final Paint _hoverGlowPaint = Paint();
  static final Paint _hoverLinePaint = Paint()..strokeWidth = 1.0;
  static final Paint _bubblePaint = Paint();

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

    _pointPaint.color = geometry.color;
    _hoverGlowPaint.color = geometry.color.withValues(alpha: 0.2);
    _hoverLinePaint.color = geometry.color.withValues(alpha: 0.5);
    _bubblePaint.color = geometry.color;

    if (data.length < 2) {
      // 只有一个点的情况
      final p = pts[0];
      canvas.drawCircle(p, 6, _pointPaint);
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
      canvas.drawCircle(p, isHover ? 6 : 4, _pointPaint);
      if (isHover) {
        canvas.drawCircle(p, 10, _hoverGlowPaint);
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
          _hoverLinePaint,
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
          _bubblePaint,
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
