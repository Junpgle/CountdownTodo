import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../models.dart';

bool isAiGeneratedTodo(TodoItem todo) {
  final originalText = todo.originalText?.trim();
  final imagePath = todo.imagePath?.trim();
  return originalText != null &&
      originalText.isNotEmpty &&
      (imagePath == null || imagePath.isEmpty);
}

class AiGeneratedTodoWaterBorder extends StatefulWidget {
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
  State<AiGeneratedTodoWaterBorder> createState() =>
      _AiGeneratedTodoWaterBorderState();
}

class _AiGeneratedTodoWaterBorderState
    extends State<AiGeneratedTodoWaterBorder>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 5400),
    );
    if (widget.enabled) _controller.repeat();
  }

  @override
  void didUpdateWidget(covariant AiGeneratedTodoWaterBorder oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.enabled && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!widget.enabled && _controller.isAnimating) {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return CustomPaint(
            foregroundPainter: _AiWaterBorderPainter(
              progress: _controller.value,
              isLight: widget.isLight,
            ),
            child: Padding(
              padding: const EdgeInsets.all(2),
              child: child,
            ),
          );
        },
        child: widget.child,
      ),
    );
  }
}

class _AiWaterBorderPainter extends CustomPainter {
  const _AiWaterBorderPainter({
    required this.progress,
    required this.isLight,
  });

  final double progress;
  final bool isLight;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;

    final rect = Offset.zero & size;
    final borderRect = rect.deflate(2);
    final baseRRect = BorderRadius.circular(16).toRRect(borderRect);
    final colors = <Color>[
      const Color(0xFF36F1CD).withValues(alpha: isLight ? 0.72 : 0.86),
      const Color(0xFF4D7CFE).withValues(alpha: isLight ? 0.68 : 0.82),
      const Color(0xFFFF6FD8).withValues(alpha: isLight ? 0.72 : 0.88),
      const Color(0xFFFFF06A).withValues(alpha: isLight ? 0.62 : 0.78),
      const Color(0xFF77F36D).withValues(alpha: isLight ? 0.66 : 0.80),
      const Color(0xFF36F1CD).withValues(alpha: isLight ? 0.72 : 0.86),
    ];
    final shader = SweepGradient(
      colors: colors,
      stops: const [0, 0.17, 0.37, 0.58, 0.78, 1],
      transform: GradientRotation(progress * math.pi * 2),
    ).createShader(rect);

    final glowPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.4
      ..strokeCap = StrokeCap.round
      ..shader = shader
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
    canvas.drawRRect(baseRRect, glowPaint);

    for (var i = 0; i < 3; i++) {
      final phase = progress * math.pi * 2 + i * 1.9;
      final wave = math.sin(phase) * 0.9;
      final shiftedRect = Rect.fromCenter(
        center: rect.center +
            Offset(math.cos(phase) * 0.65, math.sin(phase * 0.8) * 0.65),
        width: borderRect.width - i + wave,
        height: borderRect.height - i - wave,
      );
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = i == 0 ? 1.8 : 0.9
        ..strokeCap = StrokeCap.round
        ..shader = shader;
      canvas.drawRRect(
        BorderRadius.circular(16 - i.toDouble()).toRRect(shiftedRect),
        paint,
      );
    }

    final sheen = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8
      ..color = Colors.white.withValues(alpha: isLight ? 0.44 : 0.28);
    canvas.drawRRect(
      BorderRadius.circular(14).toRRect(borderRect.deflate(1.4)),
      sheen,
    );
  }

  @override
  bool shouldRepaint(covariant _AiWaterBorderPainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.isLight != isLight;
  }
}
