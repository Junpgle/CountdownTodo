import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../utils/android_energy_policy.dart';
import '../../../services/power_save_mode_service.dart';

/// 喝水详情页的今日进度卡：用杯内液面表达累计饮水量。
class HabitWaterProgressCard extends StatelessWidget {
  final double currentValue;
  final double targetValue;
  final String unit;
  final int recordCount;

  const HabitWaterProgressCard({
    super.key,
    required this.currentValue,
    required this.targetValue,
    this.unit = 'ml',
    this.recordCount = 0,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final double safeTarget = targetValue > 0 ? targetValue : 1.0;
    final double ratio = currentValue / safeTarget;
    final double visualRatio = ratio.clamp(0.0, 1.0).toDouble();
    final displayUnit = unit.trim().isEmpty ? 'ml' : unit.trim();
    final double remaining = math
        .max(safeTarget - currentValue, 0.0)
        .toDouble();
    final percent = (ratio * 100).round();
    final isComplete = currentValue >= safeTarget;

    return Semantics(
      container: true,
      label:
          '今日饮水 ${_formatAmount(currentValue)} $displayUnit，'
          '目标 ${_formatAmount(safeTarget)} $displayUnit，完成 $percent%',
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(14, 14, 18, 14),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: colorScheme.primary.withValues(alpha: 0.18),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(
              width: 126,
              height: 184,
              child: TweenAnimationBuilder<double>(
                tween: Tween<double>(end: visualRatio),
                duration: const Duration(milliseconds: 650),
                curve: Curves.easeOutCubic,
                builder: (context, animatedRatio, child) {
                  return _AnimatedWaterCup(
                    key: ValueKey('$currentValue:$targetValue'),
                    ratio: animatedRatio,
                    colorScheme: colorScheme,
                  );
                },
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.water_drop_rounded,
                        size: 18,
                        color: colorScheme.primary,
                      ),
                      const SizedBox(width: 7),
                      Text(
                        '今日饮水',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: colorScheme.onSurface,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${_formatAmount(currentValue)} $displayUnit',
                    style: TextStyle(
                      fontSize: 27,
                      height: 1.05,
                      fontWeight: FontWeight.w900,
                      color: colorScheme.primary,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    '目标 ${_formatAmount(safeTarget)} $displayUnit · $percent%',
                    style: TextStyle(
                      fontSize: 12,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 14),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: LinearProgressIndicator(
                      value: visualRatio,
                      minHeight: 8,
                      backgroundColor: colorScheme.primaryContainer,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        colorScheme.primary,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    isComplete
                        ? '今日目标已完成，继续少量多次即可。'
                        : '还差 ${_formatAmount(remaining)} $displayUnit 达标',
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.4,
                      fontWeight: FontWeight.w700,
                      color: isComplete
                          ? colorScheme.tertiary
                          : colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if (recordCount > 0) ...[
                    const SizedBox(height: 6),
                    Text(
                      '今天已记录 $recordCount 次 · 建议少量多次',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatAmount(double value) {
    return value == value.roundToDouble()
        ? value.round().toString()
        : value.toStringAsFixed(1);
  }
}

class _AnimatedWaterCup extends StatefulWidget {
  final double ratio;
  final ColorScheme colorScheme;

  const _AnimatedWaterCup({
    super.key,
    required this.ratio,
    required this.colorScheme,
  });

  @override
  State<_AnimatedWaterCup> createState() => _AnimatedWaterCupState();
}

class _AnimatedWaterCupState extends State<_AnimatedWaterCup>
    with SingleTickerProviderStateMixin {
  late final AnimationController _waveController;

  @override
  void initState() {
    super.initState();
    _waveController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2600),
    );
    PowerSaveModeService.enabledListenable.addListener(_syncAnimation);
    _syncAnimation();
  }

  void _syncAnimation() {
    if (AndroidEnergyPolicy.shouldRunDecorativeMotion) {
      if (!_waveController.isAnimating) {
        _waveController.repeat(
          count: AndroidEnergyPolicy.decorativeRepeatCount(androidCount: 3),
        );
      }
    } else {
      _waveController
        ..stop()
        ..reset();
    }
  }

  @override
  void dispose() {
    PowerSaveModeService.enabledListenable.removeListener(_syncAnimation);
    _waveController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(
        painter: _WaterProgressCupPainter(
          ratio: widget.ratio,
          animation: _waveController,
          colorScheme: widget.colorScheme,
        ),
      ),
    );
  }
}

class _WaterProgressCupPainter extends CustomPainter {
  static const _waveSampleCount = 28;
  // Cache each sample angle so animated frames only calculate phase sin/cos.
  static final List<(double, double, double, double, double)> _waveBasis =
      List.generate(_waveSampleCount, (index) {
        final progress = (index + 1) / _waveSampleCount;
        final primaryAngle = progress * math.pi * 2.2;
        final secondaryAngle = progress * math.pi * 4.4;
        return (
          progress,
          math.sin(primaryAngle),
          math.cos(primaryAngle),
          math.sin(secondaryAngle),
          math.cos(secondaryAngle),
        );
      }, growable: false);

  final double ratio;
  final Animation<double> animation;
  final ColorScheme colorScheme;
  late final Paint _shadowPaint = Paint()
    ..color = colorScheme.primary.withValues(alpha: 0.12)
    ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 9);
  final Paint _glassPaint = Paint();
  final Paint _waterPaint = Paint();
  late final Paint _surfacePaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.5
    ..color = colorScheme.onPrimary.withValues(alpha: 0.52);
  late final Paint _reflectionPaint = Paint()
    ..color = colorScheme.onPrimary.withValues(alpha: 0.26)
    ..strokeWidth = 3
    ..strokeCap = StrokeCap.round;
  late final Paint _bubblePaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.1
    ..color = colorScheme.onPrimary.withValues(alpha: 0.3);
  late final Paint _outlinePaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2.2
    ..color = colorScheme.primary.withValues(alpha: 0.52);
  late final Paint _highlightPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 3
    ..strokeCap = StrokeCap.round
    ..color = colorScheme.onPrimary.withValues(alpha: 0.38);
  late final Paint _rimPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.7
    ..color = colorScheme.primary.withValues(alpha: 0.45);
  late final Paint _graduationPaint = Paint()
    ..color = colorScheme.onPrimaryContainer.withValues(alpha: 0.34)
    ..strokeWidth = 1.2;
  late final LinearGradient _waterGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      colorScheme.primary.withValues(alpha: 0.68),
      colorScheme.primary.withValues(alpha: 0.96),
      colorScheme.tertiary.withValues(alpha: 0.82),
    ],
    stops: const [0, 0.45, 1],
  );

  static const List<(double, double, double, double)> _bubbles = [
    (0.28, 0.24, 2.4, 1.0),
    (0.66, 0.52, 1.8, 1.4),
    (0.47, 0.76, 1.3, 0.8),
  ];

  Size? _geometrySize;
  Path? _cupPathCache;
  Path? _highlightPathCache;
  final Path _waterPathCache = Path();
  final Path _surfacePathCache = Path();
  final List<double> _waveOffsets = List<double>.filled(
    _waveSampleCount,
    0,
    growable: false,
  );
  Rect? _glassShaderBounds;
  Shader? _glassShader;

  _WaterProgressCupPainter({
    required this.ratio,
    required this.animation,
    required this.colorScheme,
  }) : super(repaint: animation);

  @override
  void paint(Canvas canvas, Size size) {
    if (_geometrySize != size) {
      _geometrySize = size;
      _cupPathCache = _cupPath(size);
      _highlightPathCache = _highlightPath(size);
      _glassShaderBounds = null;
      _glassShader = null;
    }

    final phase = animation.value * math.pi * 2;
    final cup = _cupPathCache!;
    final top = 25.0;
    final bottom = size.height - 18;
    final fillTop = bottom - (bottom - top) * ratio.clamp(0.0, 1.0);

    _drawShadow(canvas, cup);
    _drawGlassBody(canvas, cup);

    canvas.save();
    canvas.clipPath(cup);
    if (ratio > 0.005) {
      _drawWater(canvas, size, fillTop, bottom, phase);
      _drawBubbles(canvas, size, fillTop, bottom, phase);
    }
    canvas.restore();

    _drawGlassEdges(canvas, size, cup);
    _drawRim(canvas, size);
    _drawGraduations(canvas, size);
  }

  Path _cupPath(Size size) {
    final topY = 25.0;
    final bottomY = size.height - 18;
    final topWidth = math.min(size.width * 0.84, 106.0);
    final bottomWidth = topWidth * 0.78;
    final leftTop = (size.width - topWidth) / 2;
    final rightTop = leftTop + topWidth;
    final leftBottom = (size.width - bottomWidth) / 2;
    final rightBottom = leftBottom + bottomWidth;

    return Path()
      ..moveTo(leftTop + 9, topY)
      ..quadraticBezierTo(leftTop, topY, leftTop + 2, topY + 10)
      ..lineTo(leftBottom + 5, bottomY - 9)
      ..quadraticBezierTo(leftBottom + 7, bottomY, leftBottom + 17, bottomY)
      ..lineTo(rightBottom - 17, bottomY)
      ..quadraticBezierTo(
        rightBottom - 7,
        bottomY,
        rightBottom - 5,
        bottomY - 9,
      )
      ..lineTo(rightTop - 2, topY + 10)
      ..quadraticBezierTo(rightTop, topY, rightTop - 9, topY)
      ..close();
  }

  void _drawShadow(Canvas canvas, Path cup) {
    canvas.save();
    canvas.translate(0, 5);
    canvas.drawPath(cup, _shadowPaint);
    canvas.restore();
  }

  void _drawGlassBody(Canvas canvas, Path cup) {
    final bounds = cup.getBounds();
    if (_glassShaderBounds != bounds) {
      _glassShaderBounds = bounds;
      _glassShader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          colorScheme.surface.withValues(alpha: 0.72),
          colorScheme.primaryContainer.withValues(alpha: 0.34),
        ],
      ).createShader(bounds);
    }
    _glassPaint.shader = _glassShader;
    canvas.drawPath(cup, _glassPaint);
  }

  void _drawWater(
    Canvas canvas,
    Size size,
    double fillTop,
    double bottom,
    double phase,
  ) {
    _updateWaveOffsets(phase);
    final waterPath = _waterPath(size, fillTop, bottom);
    final bounds = waterPath.getBounds();
    _waterPaint.shader = _waterGradient.createShader(bounds);
    canvas.drawPath(waterPath, _waterPaint);

    final surfacePath = _wavePath(
      size,
      fillTop,
      amplitude: 2.8,
      path: _surfacePathCache,
    );
    canvas.drawPath(surfacePath, _surfacePaint);

    canvas.drawLine(
      Offset(size.width * 0.31, size.height * 0.43),
      Offset(size.width * 0.31, size.height * 0.68),
      _reflectionPaint,
    );
  }

  void _updateWaveOffsets(double phase) {
    final phaseSin = math.sin(phase);
    final phaseCos = math.cos(phase);
    final secondaryPhase = phase * 0.7;
    final secondaryPhaseSin = math.sin(secondaryPhase);
    final secondaryPhaseCos = math.cos(secondaryPhase);

    for (var i = 0; i < _waveBasis.length; i++) {
      final basis = _waveBasis[i];
      final primary = basis.$2 * phaseCos + basis.$3 * phaseSin;
      final secondary =
          basis.$4 * secondaryPhaseCos - basis.$5 * secondaryPhaseSin;
      _waveOffsets[i] = primary + secondary * 0.28;
    }
  }

  Path _waterPath(Size size, double fillTop, double bottom) {
    final left = size.width * 0.16;
    final right = size.width * 0.84;
    final surface = _wavePath(
      size,
      fillTop,
      amplitude: 3.6,
      path: _waterPathCache,
    );
    return surface
      ..lineTo(right, bottom + 5)
      ..lineTo(left, bottom + 5)
      ..close();
  }

  Path _wavePath(
    Size size,
    double y, {
    required double amplitude,
    required Path path,
  }) {
    final left = size.width * 0.16;
    final width = size.width * 0.68;
    path
      ..reset()
      ..moveTo(left, y);
    for (var i = 0; i < _waveSampleCount; i++) {
      final x = left + width * _waveBasis[i].$1;
      path.lineTo(x, y + _waveOffsets[i] * amplitude);
    }
    return path;
  }

  void _drawBubbles(
    Canvas canvas,
    Size size,
    double fillTop,
    double bottom,
    double phase,
  ) {
    final waterHeight = bottom - fillTop;
    if (waterHeight < 24) return;
    final phaseCycles = phase / (math.pi * 2);
    for (final bubble in _bubbles) {
      final x = size.width * bubble.$1;
      final travel = (phaseCycles * bubble.$4 + bubble.$2) % 1;
      final y = bottom - waterHeight * travel;
      if (y <= fillTop + 8 || y >= bottom - 6) continue;
      canvas.drawCircle(Offset(x, y), bubble.$3, _bubblePaint);
    }
  }

  void _drawGlassEdges(Canvas canvas, Size size, Path cup) {
    canvas.drawPath(cup, _outlinePaint);

    canvas.drawPath(_highlightPathCache!, _highlightPaint);
  }

  void _drawRim(Canvas canvas, Size size) {
    final rimOuter = RRect.fromRectAndRadius(
      Rect.fromLTWH(size.width * 0.07, 17, size.width * 0.86, 17),
      const Radius.circular(9),
    );
    final rimInner = RRect.fromRectAndRadius(
      Rect.fromLTWH(size.width * 0.12, 21, size.width * 0.76, 9),
      const Radius.circular(5),
    );
    canvas.drawRRect(rimOuter, _rimPaint);
    canvas.drawRRect(rimInner, _rimPaint);
  }

  void _drawGraduations(Canvas canvas, Size size) {
    for (var i = 1; i <= 3; i++) {
      final y = size.height * (0.34 + i * 0.14);
      canvas.drawLine(
        Offset(size.width * 0.76, y),
        Offset(size.width * 0.84, y),
        _graduationPaint,
      );
    }
  }

  Path _highlightPath(Size size) => Path()
    ..moveTo(size.width * 0.22, size.height * 0.28)
    ..quadraticBezierTo(
      size.width * 0.18,
      size.height * 0.52,
      size.width * 0.28,
      size.height * 0.78,
    );

  @override
  bool shouldRepaint(covariant _WaterProgressCupPainter oldDelegate) {
    return oldDelegate.ratio != ratio ||
        oldDelegate.animation != animation ||
        oldDelegate.colorScheme != colorScheme;
  }
}
