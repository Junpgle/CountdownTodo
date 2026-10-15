import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../services/todo_completion_celebration_service.dart';
import 'optional_liquid_glass_surface.dart';

/// 待办全清微粒子粒子模型
class _ConfettiParticle {
  double x;
  double y;
  double vx;
  double vy;
  double size;
  Color color;
  double rotation;
  double rotationSpeed;
  bool isCircle;

  _ConfettiParticle({
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.size,
    required this.color,
    required this.rotation,
    required this.rotationSpeed,
    required this.isCircle,
  });
}

/// 粒子画布绘制器
class _ConfettiPainter extends CustomPainter {
  final List<_ConfettiParticle> particles;
  final double progress;

  _ConfettiPainter({required this.particles, required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final double alpha = (1.0 - progress).clamp(0.0, 1.0);
    if (alpha <= 0.0) return;

    final paint = Paint()..style = PaintingStyle.fill;

    for (final p in particles) {
      final particleAlpha = (alpha * 1.2).clamp(0.0, 1.0);
      paint.color = p.color.withValues(alpha: particleAlpha);

      canvas.save();
      canvas.translate(p.x, p.y);
      canvas.rotate(p.rotation);

      if (p.isCircle) {
        canvas.drawCircle(Offset.zero, p.size / 2, paint);
      } else {
        canvas.drawRect(
          Rect.fromCenter(
            center: Offset.zero,
            width: p.size,
            height: p.size * 0.65,
          ),
          paint,
        );
      }

      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _ConfettiPainter oldDelegate) => true;
}

/// 今日待办全部达成庆祝弹层
class TodoCelebrationOverlay extends StatefulWidget {
  final int completedTodayCount;
  final VoidCallback? onDismiss;

  const TodoCelebrationOverlay({
    super.key,
    required this.completedTodayCount,
    this.onDismiss,
  });

  @override
  State<TodoCelebrationOverlay> createState() => _TodoCelebrationOverlayState();
}

class _TodoCelebrationOverlayState extends State<TodoCelebrationOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  final List<_ConfettiParticle> _particles = [];
  final math.Random _random = math.Random();
  double _lastElapsedSeconds = 0.0;

  static const List<Color> _palette = [
    Color(0xFFFFD700), // 金黄
    Color(0xFFFF6D00), // 珊瑚橙
    Color(0xFF00E676), // 翡翠绿
    Color(0xFF2979FF), // 亮蓝
    Color(0xFFFF4081), // 霓虹粉
    Color(0xFF7C4DFF), // 紫罗兰
    Color(0xFF00B0FF), // 浅天蓝
  ];

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    );

    _controller.addListener(_updatePhysics);
    _controller.forward().then((_) {
      if (mounted) {
        widget.onDismiss?.call();
      }
    });
  }

  void _initParticles(Size size) {
    if (_particles.isNotEmpty) return;

    final centerX = size.width / 2;
    final startY = size.height * 0.38;

    for (int i = 0; i < 48; i++) {
      final angle = (_random.nextDouble() * math.pi) + math.pi; // 向上弧形喷射
      final speed = 180 + _random.nextDouble() * 260;
      final vx = math.cos(angle) * speed * 1.1;
      final vy = math.sin(angle) * speed;

      _particles.add(
        _ConfettiParticle(
          x: centerX + (_random.nextDouble() - 0.5) * 60,
          y: startY + (_random.nextDouble() - 0.5) * 40,
          vx: vx,
          vy: vy,
          size: 7 + _random.nextDouble() * 7,
          color: _palette[_random.nextInt(_palette.length)],
          rotation: _random.nextDouble() * math.pi * 2,
          rotationSpeed: (_random.nextDouble() - 0.5) * 12,
          isCircle: _random.nextBool(),
        ),
      );
    }
  }

  void _updatePhysics() {
    final currentSeconds = _controller.value * 2.4;
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
    _controller.removeListener(_updatePhysics);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        _initParticles(size);

        return Material(
          type: MaterialType.transparency,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // 粒子层
              RepaintBoundary(
                child: AnimatedBuilder(
                  animation: _controller,
                  builder: (context, _) {
                    return CustomPaint(
                      size: size,
                      painter: _ConfettiPainter(
                        particles: _particles,
                        progress: _controller.value,
                      ),
                    );
                  },
                ),
              ),

              // 居中庆祝卡片
              Center(
                child: TweenAnimationBuilder<double>(
                  tween: Tween<double>(begin: 0.8, end: 1.0),
                  duration: const Duration(milliseconds: 450),
                  curve: Curves.elasticOut,
                  builder: (context, scale, child) {
                    return Transform.scale(scale: scale, child: child);
                  },
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 32),
                    constraints: const BoxConstraints(maxWidth: 380),
                    child: OptionalLiquidGlassCard(
                      borderRadius: 24,
                      tint: colorScheme.primary.withValues(alpha: 0.12),
                      fallbackDecoration: BoxDecoration(
                        color: isDark
                            ? colorScheme.surfaceContainerHighest.withValues(
                                alpha: 0.92,
                              )
                            : colorScheme.surface.withValues(alpha: 0.96),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                          color: const Color(0xFFFFD700).withValues(alpha: 0.5),
                          width: 1.5,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.16),
                            blurRadius: 24,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 24,
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: LinearGradient(
                                  colors: [
                                    const Color(0xFFFFD700)
                                        .withValues(alpha: 0.28),
                                    const Color(0xFFFF6D00)
                                        .withValues(alpha: 0.15),
                                  ],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                              ),
                              child: const Icon(
                                Icons.celebration_rounded,
                                size: 44,
                                color: Color(0xFFFFB300),
                              ),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              '今日待办全部达成！',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: colorScheme.onSurface,
                                letterSpacing: 0.3,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              widget.completedTodayCount > 0
                                  ? '今日已完成 ${widget.completedTodayCount} 项任务\n今日事今日毕，尽情享受闲暇时光 ✨'
                                  : '今日任务已全部清空，放松一下吧 ✨',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 13.5,
                                color: colorScheme.onSurface.withValues(
                                  alpha: 0.75,
                                ),
                                height: 1.45,
                              ),
                            ),
                            const SizedBox(height: 20),
                            FilledButton.tonal(
                              key: const ValueKey('celebration_dismiss_btn'),
                              onPressed: () {
                                widget.onDismiss?.call();
                              },
                              style: FilledButton.styleFrom(
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 24,
                                  vertical: 10,
                                ),
                              ),
                              child: const Text(
                                '太棒了',
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// 弹出今日待办全部达成庆祝弹窗
Future<void> showTodoAllDoneCelebration(
  BuildContext context, {
  required int completedTodayCount,
}) async {
  await TodoCompletionCelebrationService.ensureInitialized();
  if (!TodoCompletionCelebrationService.isCelebrationEnabled) return;

  if (!context.mounted) return;

  await showDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierColor: Colors.black.withValues(alpha: 0.35),
    builder: (dialogCtx) => TodoCelebrationOverlay(
      completedTodayCount: completedTodayCount,
      onDismiss: () {
        if (dialogCtx.mounted) {
          Navigator.of(dialogCtx).pop();
        }
      },
    ),
  );
}
