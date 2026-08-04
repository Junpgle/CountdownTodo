import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 时间点型习惯在某一天的图表数据。
class HabitTimePointChartData {
  final DateTime date;
  final DateTime? actualTime;
  final bool onTime;
  final int? targetTimeMinute;
  final int dayBoundaryMinute;

  const HabitTimePointChartData({
    required this.date,
    required this.actualTime,
    required this.onTime,
    required this.targetTimeMinute,
    this.dayBoundaryMinute = 4 * 60,
  });

  int? get actualTimeMinute {
    final time = actualTime;
    if (time == null) return null;
    return time.hour * 60 + time.minute;
  }

  /// 将跨午夜的实际时间放到目标时间之后的连续时间轴上。
  int? get displayActualTimeMinute {
    final actual = actualTimeMinute;
    if (actual == null) return null;
    return _displayMinute(actual, targetTimeMinute, dayBoundaryMinute);
  }

  int? get displayTargetTimeMinute {
    final target = targetTimeMinute;
    if (target == null) return null;
    return _displayMinute(target, target, dayBoundaryMinute);
  }

  static int _displayMinute(
    int minute,
    int? target,
    int dayBoundaryMinute,
  ) {
    final boundary = dayBoundaryMinute.clamp(0, 24 * 60);
    if (target != null && target >= boundary && minute < boundary) {
      return minute + 24 * 60;
    }
    return minute;
  }
}

/// 时间点型习惯的时间折线图。
///
/// 图表不依赖第三方库，纵轴会围绕目标和实际记录自动缩放，
/// 未打卡日期不会跨越连线。
class HabitTimePointChart extends StatelessWidget {
  final List<HabitTimePointChartData> data;
  final int rangeDays;

  const HabitTimePointChart({
    super.key,
    required this.data,
    this.rangeDays = 30,
  });

  static const _chartHeight = 172.0;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final scale = _HabitTimePointChartScale.fromData(data);
    final recordedCount =
        data.where((point) => point.actualTime != null).length;
    final firstDate = data.isEmpty ? null : data.first.date;
    final middleDate = data.length < 3 ? null : data[data.length ~/ 2].date;
    final lastDate = data.length < 2 ? null : data.last.date;

    return Semantics(
      label: '近 $rangeDays 天时间点折线图，已记录 $recordedCount 天',
      child: SizedBox(
        height: _chartHeight + 30,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 52,
              height: _chartHeight,
              child: _buildYAxis(colorScheme, scale),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                children: [
                  SizedBox(
                    height: _chartHeight,
                    child: CustomPaint(
                      key: const ValueKey('habit-time-point-chart-canvas'),
                      painter: _HabitTimePointChartPainter(
                        data: data,
                        colorScheme: colorScheme,
                        scale: scale,
                      ),
                      child: const SizedBox.expand(),
                    ),
                  ),
                  const SizedBox(height: 6),
                  SizedBox(
                    height: 22,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        if (firstDate != null)
                          _dateLabel(firstDate, colorScheme),
                        if (middleDate != null)
                          _dateLabel(middleDate, colorScheme),
                        if (lastDate != null) _dateLabel(lastDate, colorScheme),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildYAxis(
    ColorScheme colorScheme,
    _HabitTimePointChartScale scale,
  ) {
    return Stack(
      children: [
        for (final minute in scale.tickMinutes)
          Positioned(
            top: _tickTop(minute, scale),
            left: 0,
            right: 0,
            child: Text(
              _formatMinute(minute),
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 10,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
      ],
    );
  }

  double _tickTop(int minute, _HabitTimePointChartScale scale) {
    final center = _chartHeight - scale.ratioFor(minute) * _chartHeight;
    return (center - 7).clamp(0.0, _chartHeight - 14).toDouble();
  }

  Widget _dateLabel(DateTime date, ColorScheme colorScheme) {
    return Text(
      '${date.month}/${date.day}',
      style: TextStyle(
        fontSize: 10.5,
        color: colorScheme.onSurfaceVariant,
      ),
    );
  }

  static String _formatMinute(int minute) {
    if (minute == 24 * 60) return '24:00';
    final normalizedMinute = minute % (24 * 60);
    final hour = normalizedMinute ~/ 60;
    final minutePart = normalizedMinute % 60;
    final prefix = minute >= 24 * 60 ? '次日 ' : '';
    return '$prefix${hour.toString().padLeft(2, '0')}:${minutePart.toString().padLeft(2, '0')}';
  }
}

class _HabitTimePointChartScale {
  final int minMinute;
  final int maxMinute;

  const _HabitTimePointChartScale({
    required this.minMinute,
    required this.maxMinute,
  });

  factory _HabitTimePointChartScale.fromData(
    List<HabitTimePointChartData> data,
  ) {
    final values = <int>[];
    for (final point in data) {
      final actual = point.displayActualTimeMinute;
      final target = point.displayTargetTimeMinute;
      if (actual != null) values.add(actual);
      if (target != null) values.add(target);
    }
    if (values.isEmpty) {
      return const _HabitTimePointChartScale(minMinute: 0, maxMinute: 1440);
    }

    final minValue = values.reduce(math.min);
    final maxValue = values.reduce(math.max);
    final valueRange = maxValue - minValue;
    final padding = math.max(60, (valueRange * 0.25).ceil());
    var minMinute = ((minValue - padding).clamp(0, 2880) ~/ 60) * 60;
    var maxMinute = (((maxValue + padding).clamp(0, 2880) + 59) ~/ 60) * 60;
    if (maxMinute <= minMinute) maxMinute = minMinute + 60;
    if (maxMinute > 2880) {
      maxMinute = 2880;
      minMinute = math.max(0, maxMinute - 240);
    }
    return _HabitTimePointChartScale(
      minMinute: minMinute,
      maxMinute: maxMinute,
    );
  }

  List<int> get tickMinutes => List<int>.generate(
        5,
        (index) => (minMinute + (maxMinute - minMinute) * index / 4).round(),
      );

  bool contains(int minute) => minute >= minMinute && minute <= maxMinute;

  double ratioFor(int minute) {
    if (maxMinute == minMinute) return 0.5;
    return ((minute - minMinute) / (maxMinute - minMinute)).clamp(0.0, 1.0);
  }
}

class _HabitTimePointChartPainter extends CustomPainter {
  final List<HabitTimePointChartData> data;
  final ColorScheme colorScheme;
  final _HabitTimePointChartScale scale;

  const _HabitTimePointChartPainter({
    required this.data,
    required this.colorScheme,
    required this.scale,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0 || data.isEmpty) return;

    final gridPaint = Paint()
      ..color = colorScheme.outlineVariant.withValues(alpha: 0.55)
      ..strokeWidth = 1;
    for (final minute in scale.tickMinutes) {
      if (!scale.contains(minute)) continue;
      final y = _yFor(minute, size.height);
      _drawDashedLine(
        canvas,
        Offset(0, y),
        Offset(size.width, y),
        gridPaint,
      );
    }

    _drawTargetLines(canvas, size);
    _drawActualLines(canvas, size);
  }

  void _drawTargetLines(Canvas canvas, Size size) {
    final targetPaint = Paint()
      ..color = colorScheme.primary.withValues(alpha: 0.7)
      ..strokeWidth = 1.5;

    Offset? previousPoint;
    for (var index = 0; index < data.length; index++) {
      final target = data[index].displayTargetTimeMinute;
      if (target == null || !scale.contains(target)) {
        previousPoint = null;
        continue;
      }
      final point =
          Offset(_xFor(index, size.width), _yFor(target, size.height));
      if (previousPoint != null) {
        _drawDashedLine(canvas, previousPoint, point, targetPaint);
      }
      previousPoint = point;
    }
  }

  void _drawActualLines(Canvas canvas, Size size) {
    final linePaint = Paint()
      ..color = colorScheme.primary
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final dotOutlinePaint = Paint()
      ..color = colorScheme.surface
      ..style = PaintingStyle.fill;

    Offset? previousPoint;
    var previousIndex = -2;
    for (var index = 0; index < data.length; index++) {
      final minute = data[index].displayActualTimeMinute;
      if (minute == null || !scale.contains(minute)) {
        previousPoint = null;
        previousIndex = -2;
        continue;
      }

      final point =
          Offset(_xFor(index, size.width), _yFor(minute, size.height));
      if (previousPoint != null && previousIndex == index - 1) {
        canvas.drawLine(previousPoint, point, linePaint);
      }

      canvas.drawCircle(point, 5, dotOutlinePaint);
      canvas.drawCircle(
        point,
        3.5,
        Paint()
          ..color =
              data[index].onTime ? colorScheme.tertiary : colorScheme.error
          ..style = PaintingStyle.fill,
      );
      previousPoint = point;
      previousIndex = index;
    }
  }

  double _xFor(int index, double width) {
    if (data.length <= 1) return width / 2;
    return index / (data.length - 1) * width;
  }

  double _yFor(int minute, double height) {
    return height - scale.ratioFor(minute) * height;
  }

  void _drawDashedLine(
    Canvas canvas,
    Offset start,
    Offset end,
    Paint paint,
  ) {
    final distance = (end - start).distance;
    if (distance <= 0) return;
    final direction = (end - start) / distance;
    var offset = 0.0;
    const dashLength = 5.0;
    const gapLength = 4.0;
    while (offset < distance) {
      final dashEnd = math.min(offset + dashLength, distance);
      canvas.drawLine(
        start + direction * offset,
        start + direction * dashEnd,
        paint,
      );
      offset += dashLength + gapLength;
    }
  }

  @override
  bool shouldRepaint(covariant _HabitTimePointChartPainter oldDelegate) {
    return !identical(oldDelegate.data, data) ||
        oldDelegate.colorScheme != colorScheme ||
        oldDelegate.scale.minMinute != scale.minMinute ||
        oldDelegate.scale.maxMinute != scale.maxMinute;
  }
}
