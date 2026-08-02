import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 喝水目标的可视化选择器：瓶身显示水位，拖动刻度选择每日目标。
class HabitWaterTargetPicker extends StatelessWidget {
  final int value;
  final int min;
  final int max;
  final int step;
  final ValueChanged<int> onChanged;

  const HabitWaterTargetPicker({
    super.key,
    required this.value,
    required this.onChanged,
    this.min = 500,
    this.max = 4000,
    this.step = 100,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final safeValue = _snap(value);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(
                width: 144,
                height: 250,
                child: CustomPaint(
                  painter: _WaterBottlePainter(
                    value: safeValue,
                    min: min,
                    max: max,
                    colorScheme: colorScheme,
                  ),
                ),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '每日目标',
                      style: TextStyle(
                        fontSize: 13,
                        color: colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 180),
                      child: Text(
                        '$safeValue ml',
                        key: ValueKey(safeValue),
                        style: TextStyle(
                          fontSize: 32,
                          height: 1.1,
                          fontWeight: FontWeight.w900,
                          color: colorScheme.primary,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      '拖动下方标尺调整目标\n每格 100 ml',
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.5,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        color: colorScheme.tertiaryContainer,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.local_drink_outlined,
                              size: 17, color: colorScheme.onTertiaryContainer),
                          const SizedBox(width: 6),
                          Text(
                            '约 ${(safeValue / 200).round()} 杯 × 200 ml',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: colorScheme.onTertiaryContainer,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _WaterRuler(
            value: safeValue,
            min: min,
            max: max,
            step: step,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }

  int _snap(int raw) {
    final bounded = raw.clamp(min, max);
    final snapped = ((bounded - min) / step).round() * step + min;
    return snapped.clamp(min, max);
  }
}

class _WaterRuler extends StatelessWidget {
  final int value;
  final int min;
  final int max;
  final int step;
  final ValueChanged<int> onChanged;

  const _WaterRuler({
    required this.value,
    required this.min,
    required this.max,
    required this.step,
    required this.onChanged,
  });

  void _update(Offset position, double width) {
    final horizontalPadding = 18.0;
    final usableWidth = math.max(1, width - horizontalPadding * 2);
    final ratio =
        ((position.dx - horizontalPadding) / usableWidth).clamp(0.0, 1.0);
    final raw = min + ((max - min) * ratio).round();
    final next = ((raw - min) / step).round() * step + min;
    onChanged(next.clamp(min, max));
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        return Semantics(
          label: '每日饮水目标 $value 毫升，可拖动调整',
          slider: true,
          value: '$value 毫升',
          increasedValue: '${(value + step).clamp(min, max)} 毫升',
          decreasedValue: '${(value - step).clamp(min, max)} 毫升',
          onIncrease: () => onChanged((value + step).clamp(min, max)),
          onDecrease: () => onChanged((value - step).clamp(min, max)),
          child: MouseRegion(
            cursor: SystemMouseCursors.resizeLeftRight,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (details) =>
                  _update(details.localPosition, constraints.maxWidth),
              onHorizontalDragStart: (details) =>
                  _update(details.localPosition, constraints.maxWidth),
              onHorizontalDragUpdate: (details) =>
                  _update(details.localPosition, constraints.maxWidth),
              child: SizedBox(
                height: 78,
                width: double.infinity,
                child: CustomPaint(
                  painter: _WaterRulerPainter(
                    value: value,
                    min: min,
                    max: max,
                    step: step,
                    colorScheme: colorScheme,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _WaterBottlePainter extends CustomPainter {
  final int value;
  final int min;
  final int max;
  final ColorScheme colorScheme;

  _WaterBottlePainter({
    required this.value,
    required this.min,
    required this.max,
    required this.colorScheme,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final bottle = Rect.fromLTWH(25, 30, size.width - 50, size.height - 40);
    final body = RRect.fromRectAndRadius(bottle, const Radius.circular(28));
    final neck = RRect.fromRectAndRadius(
      Rect.fromLTWH(size.width / 2 - 20, 14, 40, 28),
      const Radius.circular(8),
    );
    final outline = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..color = colorScheme.primary.withValues(alpha: 0.55);
    final glass = Paint()..color = colorScheme.primary.withValues(alpha: 0.08);
    canvas.drawRRect(body, glass);
    canvas.drawRRect(body, outline);
    canvas.drawRRect(neck, glass);
    canvas.drawRRect(neck, outline);

    final ratio = ((value - min) / (max - min)).clamp(0.0, 1.0);
    final fillTop = bottle.bottom - bottle.height * ratio;
    canvas.save();
    canvas.clipRRect(body);
    final waterPaint = Paint()
      ..color = colorScheme.primary.withValues(alpha: 0.82);
    final wave = Path()
      ..moveTo(bottle.left, fillTop)
      ..cubicTo(
        bottle.left + bottle.width * 0.22,
        fillTop - 5,
        bottle.left + bottle.width * 0.45,
        fillTop + 5,
        bottle.left + bottle.width * 0.68,
        fillTop,
      )
      ..cubicTo(
        bottle.left + bottle.width * 0.82,
        fillTop - 3,
        bottle.right - bottle.width * 0.08,
        fillTop + 3,
        bottle.right,
        fillTop,
      )
      ..lineTo(bottle.right, bottle.bottom)
      ..lineTo(bottle.left, bottle.bottom)
      ..close();
    canvas.drawPath(wave, waterPaint);
    canvas.restore();

    final shine = Paint()
      ..color = colorScheme.onPrimary.withValues(alpha: 0.38)
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(const Offset(50, 75), const Offset(50, 125), shine);
  }

  @override
  bool shouldRepaint(covariant _WaterBottlePainter oldDelegate) {
    return oldDelegate.value != value ||
        oldDelegate.min != min ||
        oldDelegate.max != max ||
        oldDelegate.colorScheme != colorScheme;
  }
}

class _WaterRulerPainter extends CustomPainter {
  final int value;
  final int min;
  final int max;
  final int step;
  final ColorScheme colorScheme;

  _WaterRulerPainter({
    required this.value,
    required this.min,
    required this.max,
    required this.step,
    required this.colorScheme,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const left = 18.0;
    const right = 18.0;
    final lineY = 28.0;
    final usable = size.width - left - right;
    final range = max - min;
    final ratio = ((value - min) / range).clamp(0.0, 1.0);
    final thumbX = left + usable * ratio;

    final line = Paint()
      ..color = colorScheme.outlineVariant
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
        Offset(left, lineY), Offset(size.width - right, lineY), line);

    final totalSteps = (range / step).round();
    for (var i = 0; i <= totalSteps; i++) {
      final x = left + usable * i / totalSteps;
      final amount = min + i * step;
      final major = amount % 500 == 0;
      final tick = Paint()
        ..color = major ? colorScheme.onSurfaceVariant : colorScheme.outline
        ..strokeWidth = major ? 2 : 1;
      canvas.drawLine(
        Offset(x, lineY - (major ? 14 : 8)),
        Offset(x, lineY + (major ? 14 : 8)),
        tick,
      );
      if (major) {
        _drawLabel(canvas, '$amount', Offset(x, 53), colorScheme);
      }
    }

    final thumb = Paint()..color = colorScheme.primary;
    canvas.drawCircle(Offset(thumbX, lineY), 10, thumb);
    canvas.drawCircle(
      Offset(thumbX, lineY),
      4,
      Paint()..color = colorScheme.onPrimary,
    );
  }

  void _drawLabel(
    Canvas canvas,
    String text,
    Offset center,
    ColorScheme colors,
  ) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: colors.onSurfaceVariant,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(canvas, center - Offset(painter.width / 2, 0));
  }

  @override
  bool shouldRepaint(covariant _WaterRulerPainter oldDelegate) {
    return oldDelegate.value != value ||
        oldDelegate.min != min ||
        oldDelegate.max != max ||
        oldDelegate.step != step ||
        oldDelegate.colorScheme != colorScheme;
  }
}
