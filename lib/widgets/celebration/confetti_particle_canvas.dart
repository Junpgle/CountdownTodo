import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 默认庆祝彩带调色板（金黄、珊瑚橙、翡翠绿、亮蓝、霓虹粉、紫罗兰、青天蓝）。
const defaultConfettiPalette = <Color>[
  Color(0xFFFFD700), // 金黄
  Color(0xFFFF6D00), // 珊瑚橙
  Color(0xFF00E676), // 翡翠绿
  Color(0xFF2979FF), // 亮蓝
  Color(0xFFFF4081), // 霓虹粉
  Color(0xFF7C4DFF), // 紫罗兰
  Color(0xFF00E5FF), // 青天蓝
];

/// 庆祝微粒子模型。
class ConfettiParticle {
  double x;
  double y;
  double vx;
  double vy;
  double size;
  int paletteIndex;
  double rotation;
  double rotationSpeed;
  bool isCircle;

  ConfettiParticle({
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.size,
    required this.paletteIndex,
    required this.rotation,
    required this.rotationSpeed,
    required this.isCircle,
  });
}

/// 粒子画布绘制器。
class ConfettiPainter extends CustomPainter {
  final List<ConfettiParticle> particles;
  final Animation<double> animation;
  final List<Color> palette;
  final Paint _paint = Paint()..style = PaintingStyle.fill;
  final List<Color> _paintColors;

  ConfettiPainter({
    required this.particles,
    required this.animation,
    this.palette = defaultConfettiPalette,
  }) : _paintColors = List<Color>.filled(
         palette.length,
         Colors.transparent,
         growable: false,
       ),
       super(repaint: animation);

  @override
  void paint(Canvas canvas, Size size) {
    final progress = animation.value;
    final double alpha = (1.0 - progress).clamp(0.0, 1.0);
    if (alpha <= 0.0) return;

    final particleAlpha = (alpha * 1.2).clamp(0.0, 1.0);
    for (var i = 0; i < palette.length; i++) {
      _paintColors[i] = palette[i].withValues(alpha: particleAlpha);
    }

    for (final p in particles) {
      final colorIdx = p.paletteIndex % palette.length;
      _paint.color = _paintColors[colorIdx];

      canvas.save();
      canvas.translate(p.x, p.y);
      canvas.rotate(p.rotation);

      if (p.isCircle) {
        canvas.drawCircle(Offset.zero, p.size / 2, _paint);
      } else {
        canvas.drawRect(
          Rect.fromCenter(
            center: Offset.zero,
            width: p.size,
            height: p.size * 0.65,
          ),
          _paint,
        );
      }

      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant ConfettiPainter oldDelegate) =>
      oldDelegate.particles != particles || oldDelegate.animation != animation;
}

/// 可配置的全屏喷射彩带彩屑粒子层。
class ConfettiParticleCanvas extends StatefulWidget {
  final AnimationController? controller;
  final Duration duration;
  final int particleCount;
  final List<Color> palette;
  final double startYFraction;
  final VoidCallback? onCompleted;

  const ConfettiParticleCanvas({
    super.key,
    this.controller,
    this.duration = const Duration(milliseconds: 2400),
    this.particleCount = 50,
    this.palette = defaultConfettiPalette,
    this.startYFraction = 0.37,
    this.onCompleted,
  });

  @override
  State<ConfettiParticleCanvas> createState() => _ConfettiParticleCanvasState();
}

class _ConfettiParticleCanvasState extends State<ConfettiParticleCanvas>
    with SingleTickerProviderStateMixin {
  AnimationController? _internalController;
  AnimationController get _effectiveController =>
      widget.controller ?? _internalController!;

  final List<ConfettiParticle> _particles = [];
  final math.Random _random = math.Random();
  double _lastElapsedSeconds = 0.0;

  @override
  void initState() {
    super.initState();
    if (widget.controller == null) {
      _internalController = AnimationController(
        vsync: this,
        duration: widget.duration,
      );
      _internalController!.forward().then((_) {
        if (mounted) widget.onCompleted?.call();
      });
    }

    _effectiveController.addListener(_updatePhysics);
  }

  @override
  void didUpdateWidget(covariant ConfettiParticleCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller?.removeListener(_updatePhysics);
      _effectiveController.addListener(_updatePhysics);
    }
  }

  void _initParticles(Size size) {
    if (_particles.isNotEmpty) return;

    final centerX = size.width / 2;
    final startY = size.height * widget.startYFraction;

    for (int i = 0; i < widget.particleCount; i++) {
      final angle = (_random.nextDouble() * math.pi) + math.pi; // 向上弧形喷射
      final speed = 180 + _random.nextDouble() * 270;
      final vx = math.cos(angle) * speed * 1.12;
      final vy = math.sin(angle) * speed;

      _particles.add(
        ConfettiParticle(
          x: centerX + (_random.nextDouble() - 0.5) * 60,
          y: startY + (_random.nextDouble() - 0.5) * 40,
          vx: vx,
          vy: vy,
          size: 7 + _random.nextDouble() * 7,
          paletteIndex: _random.nextInt(widget.palette.length),
          rotation: _random.nextDouble() * math.pi * 2,
          rotationSpeed: (_random.nextDouble() - 0.5) * 12,
          isCircle: _random.nextBool(),
        ),
      );
    }
  }

  void _updatePhysics() {
    final totalSeconds = widget.duration.inMilliseconds / 1000.0;
    final currentSeconds = _effectiveController.value * totalSeconds;
    final dt = (currentSeconds - _lastElapsedSeconds).clamp(0.0, 0.05);
    _lastElapsedSeconds = currentSeconds;

    const gravity = 480.0;
    const airDrag = 0.985;

    for (final p in _particles) {
      p.vy += gravity * dt;
      p.vx *= airDrag;
      p.x += p.vx * dt;
      p.y += p.vy * dt;
      p.rotation += p.rotationSpeed * dt;
    }
  }

  @override
  void dispose() {
    _effectiveController.removeListener(_updatePhysics);
    _internalController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        _initParticles(size);

        return RepaintBoundary(
          child: CustomPaint(
            size: size,
            painter: ConfettiPainter(
              particles: _particles,
              animation: _effectiveController,
              palette: widget.palette,
            ),
          ),
        );
      },
    );
  }
}
