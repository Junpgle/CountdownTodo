import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:visibility_detector/visibility_detector.dart';

import '../models.dart';
import '../utils/android_energy_policy.dart';
import '../services/power_save_mode_service.dart';

bool isAiGeneratedTodo(TodoItem todo) {
  final originalText = todo.originalText?.trim();
  final imagePath = todo.imagePath?.trim();
  return originalText != null &&
      originalText.isNotEmpty &&
      (imagePath == null || imagePath.isEmpty);
}

class AiGeneratedTodoWaterBorder extends StatelessWidget {
  const AiGeneratedTodoWaterBorder({
    super.key,
    required this.child,
    required this.enabled,
    required this.isLight,
  });

  final Widget child;
  final bool enabled;
  final bool isLight;

  @override
  Widget build(BuildContext context) {
    return AiWaterRippleBorder(
      enabled: enabled,
      isLight: isLight,
      visibleOnlyWhenInViewport: true,
      child: child,
    );
  }
}

class AiWaterRippleBorder extends StatelessWidget {
  const AiWaterRippleBorder({
    super.key,
    required this.child,
    required this.isLight,
    this.enabled = true,
    this.visibleOnlyWhenInViewport = false,
    this.borderRadius = const BorderRadius.all(Radius.circular(16)),
  });

  final Widget child;
  final bool enabled;
  final bool isLight;
  final bool visibleOnlyWhenInViewport;
  final BorderRadius borderRadius;

  @override
  Widget build(BuildContext context) {
    if (!enabled) return child;
    return _AnimatedAiWaterRippleBorder(
      isLight: isLight,
      borderRadius: borderRadius,
      visibleOnlyWhenInViewport: visibleOnlyWhenInViewport,
      child: child,
    );
  }
}

class _AnimatedAiWaterRippleBorder extends StatefulWidget {
  const _AnimatedAiWaterRippleBorder({
    required this.isLight,
    required this.borderRadius,
    required this.visibleOnlyWhenInViewport,
    required this.child,
  });

  final Widget child;
  final bool isLight;
  final BorderRadius borderRadius;
  final bool visibleOnlyWhenInViewport;

  @override
  State<_AnimatedAiWaterRippleBorder> createState() =>
      _AnimatedAiWaterRippleBorderState();
}

class _AnimatedAiWaterRippleBorderState
    extends State<_AnimatedAiWaterRippleBorder>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool _isVisible = true;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 5400),
    );
    PowerSaveModeService.enabledListenable.addListener(_syncAnimation);
    _syncAnimation();
  }

  void _syncAnimation() {
    if ((!widget.visibleOnlyWhenInViewport || _isVisible) &&
        AndroidEnergyPolicy.shouldRunDecorativeMotion) {
      _startAnimation();
    } else {
      _controller
        ..stop()
        ..reset();
    }
  }

  void _onVisibilityChanged(VisibilityInfo info) {
    final isVisible = info.visibleFraction > 0;
    if (!mounted || _isVisible == isVisible) return;
    _isVisible = isVisible;
    _syncAnimation();
  }

  @override
  void didUpdateWidget(covariant _AnimatedAiWaterRippleBorder oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.visibleOnlyWhenInViewport !=
        widget.visibleOnlyWhenInViewport) {
      _syncAnimation();
    }
  }

  void _startAnimation() {
    _controller
      ..reset()
      ..repeat(
        count: AndroidEnergyPolicy.decorativeRepeatCount(androidCount: 2),
      );
  }

  @override
  void dispose() {
    PowerSaveModeService.enabledListenable.removeListener(_syncAnimation);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final paintedChild = RepaintBoundary(
      child: CustomPaint(
        foregroundPainter: _AiWaterBorderPainter(
          animation: _controller,
          isLight: widget.isLight,
          borderRadius: widget.borderRadius,
        ),
        // The foreground painter repaints on every animation tick. Keep the
        // card subtree in its own layer so those ticks do not repaint its
        // static text, icons, and glass surface along with the ripple.
        child: RepaintBoundary(
          child: Padding(padding: const EdgeInsets.all(2), child: widget.child),
        ),
      ),
    );
    if (!widget.visibleOnlyWhenInViewport) return paintedChild;
    return VisibilityDetector(
      key: ObjectKey(this),
      onVisibilityChanged: _onVisibilityChanged,
      child: paintedChild,
    );
  }
}

class _AiWaterBorderGradientTransform extends GradientTransform {
  const _AiWaterBorderGradientTransform(this.animation);

  final Animation<double> animation;

  @override
  Matrix4 transform(Rect bounds, {TextDirection? textDirection}) {
    final radians = animation.value * math.pi * 2;
    final sinRadians = math.sin(radians);
    final oneMinusCosRadians = 1 - math.cos(radians);
    final center = bounds.center;
    final originX = sinRadians * center.dy + oneMinusCosRadians * center.dx;
    final originY = -sinRadians * center.dx + oneMinusCosRadians * center.dy;

    return Matrix4.identity()
      ..translateByDouble(originX, originY, 0, 1)
      ..rotateZ(radians);
  }
}

class _AiWaterBorderPainter extends CustomPainter {
  _AiWaterBorderPainter({
    required this.animation,
    required this.isLight,
    required this.borderRadius,
  }) : super(repaint: animation);

  final Animation<double> animation;
  final bool isLight;
  final BorderRadius borderRadius;
  Size? _cachedSize;
  BorderRadius? _cachedBorderRadius;
  Rect? _cachedRect;
  Rect? _cachedBorderRect;
  RRect? _cachedBaseRRect;
  RRect? _cachedSheenRRect;
  List<BorderRadius>? _cachedWaveBorderRadii;
  late final SweepGradient _gradient = SweepGradient(
    colors: _gradientColors,
    stops: const [0, 0.17, 0.37, 0.58, 0.78, 1],
    transform: _AiWaterBorderGradientTransform(animation),
  );
  late final List<Color> _gradientColors = [
    const Color(0xFF36F1CD).withValues(alpha: isLight ? 0.72 : 0.86),
    const Color(0xFF4D7CFE).withValues(alpha: isLight ? 0.68 : 0.82),
    const Color(0xFFFF6FD8).withValues(alpha: isLight ? 0.72 : 0.88),
    const Color(0xFFFFF06A).withValues(alpha: isLight ? 0.62 : 0.78),
    const Color(0xFF77F36D).withValues(alpha: isLight ? 0.66 : 0.80),
    const Color(0xFF36F1CD).withValues(alpha: isLight ? 0.72 : 0.86),
  ];
  late final Paint _glowPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 4.4
    ..strokeCap = StrokeCap.round
    ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
  late final List<Paint> _wavePaints = List<Paint>.generate(
    3,
    (index) => Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = index == 0 ? 1.8 : 0.9
      ..strokeCap = StrokeCap.round,
    growable: false,
  );
  late final Paint _sheenPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 0.8
    ..color = Colors.white.withValues(alpha: isLight ? 0.44 : 0.28);

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;

    final progress = animation.value;
    _cacheStaticGeometry(size);
    final rect = _cachedRect!;
    final borderRect = _cachedBorderRect!;
    final shader = _gradient.createShader(rect);

    _glowPaint.shader = shader;
    canvas.drawRRect(_cachedBaseRRect!, _glowPaint);

    for (var i = 0; i < 3; i++) {
      final phase = progress * math.pi * 2 + i * 1.9;
      final wave = math.sin(phase) * 0.9;
      final shiftedRect = Rect.fromCenter(
        center:
            rect.center +
            Offset(math.cos(phase) * 0.65, math.sin(phase * 0.8) * 0.65),
        width: borderRect.width - i + wave,
        height: borderRect.height - i - wave,
      );
      final paint = _wavePaints[i]..shader = shader;
      canvas.drawRRect(_cachedWaveBorderRadii![i].toRRect(shiftedRect), paint);
    }

    canvas.drawRRect(_cachedSheenRRect!, _sheenPaint);
  }

  void _cacheStaticGeometry(Size size) {
    if (_cachedSize == size && _cachedBorderRadius == borderRadius) return;

    final rect = Offset.zero & size;
    final borderRect = rect.deflate(2);
    _cachedSize = size;
    _cachedBorderRadius = borderRadius;
    _cachedRect = rect;
    _cachedBorderRect = borderRect;
    _cachedBaseRRect = borderRadius.toRRect(borderRect);
    _cachedSheenRRect = _insetBorderRadius(
      borderRadius,
      2,
    ).toRRect(borderRect.deflate(1.4));
    _cachedWaveBorderRadii = List<BorderRadius>.generate(
      3,
      (index) => _insetBorderRadius(borderRadius, index.toDouble()),
      growable: false,
    );
  }

  static BorderRadius _insetBorderRadius(BorderRadius radius, double inset) {
    Radius insetRadius(Radius value) => Radius.elliptical(
      math.max(0, value.x - inset).toDouble(),
      math.max(0, value.y - inset).toDouble(),
    );

    return BorderRadius.only(
      topLeft: insetRadius(radius.topLeft),
      topRight: insetRadius(radius.topRight),
      bottomLeft: insetRadius(radius.bottomLeft),
      bottomRight: insetRadius(radius.bottomRight),
    );
  }

  @override
  bool shouldRepaint(covariant _AiWaterBorderPainter oldDelegate) {
    return oldDelegate.animation != animation ||
        oldDelegate.isLight != isLight ||
        oldDelegate.borderRadius != borderRadius;
  }
}
