import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../widgets/optional_liquid_glass_surface.dart';
import '../models/habit_goal.dart';
import '../services/habit_celebration_service.dart';

const _habitConfettiPalette = <Color>[
  Color(0xFFFFD700), // 金黄
  Color(0xFFFF6D00), // 珊瑚橙
  Color(0xFF00E676), // 翡翠绿
  Color(0xFF2979FF), // 亮蓝
  Color(0xFFFF4081), // 霓虹粉
  Color(0xFF7C4DFF), // 紫罗兰
  Color(0xFF00E5FF), // 青天蓝
];

const _inspirationalQuotes = <String>[
  '滴水穿石，每一天微小的坚持都在发生质变 ✨',
  '自律是送给未来自己最好的礼物 🌟',
  '干得漂亮！离理想中的自己又近了一步 💫',
  '日拱一卒，功不唐捐，今天的你非常棒 🌱',
  '点滴积累，终成江海。享受每一次坚持的成就感 🚀',
];

/// 习惯达标粒子模型。
class _ConfettiParticle {
  double x;
  double y;
  double vx;
  double vy;
  double size;
  int paletteIndex;
  double rotation;
  double rotationSpeed;
  bool isCircle;

  _ConfettiParticle({
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

class _ConfettiPainter extends CustomPainter {
  final List<_ConfettiParticle> particles;
  final Animation<double> animation;
  final Paint _paint = Paint()..style = PaintingStyle.fill;
  final List<Color> _paintColors = List<Color>.filled(
    _habitConfettiPalette.length,
    Colors.transparent,
    growable: false,
  );

  _ConfettiPainter({required this.particles, required this.animation})
    : super(repaint: animation);

  @override
  void paint(Canvas canvas, Size size) {
    final progress = animation.value;
    final double alpha = (1.0 - progress).clamp(0.0, 1.0);
    if (alpha <= 0.0) return;

    final particleAlpha = (alpha * 1.2).clamp(0.0, 1.0);
    for (var i = 0; i < _habitConfettiPalette.length; i++) {
      _paintColors[i] = _habitConfettiPalette[i].withValues(
        alpha: particleAlpha,
      );
    }

    for (final p in particles) {
      _paint.color = _paintColors[p.paletteIndex];

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
  bool shouldRepaint(covariant _ConfettiPainter oldDelegate) =>
      oldDelegate.particles != particles || oldDelegate.animation != animation;
}

/// 习惯达成全屏庆祝弹层。
class HabitGoalMetOverlay extends StatefulWidget {
  final HabitGoal goal;
  final int streakDays;
  final VoidCallback? onDismiss;

  const HabitGoalMetOverlay({
    super.key,
    required this.goal,
    this.streakDays = 0,
    this.onDismiss,
  });

  @override
  State<HabitGoalMetOverlay> createState() => _HabitGoalMetOverlayState();
}

class _HabitGoalMetOverlayState extends State<HabitGoalMetOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  final List<_ConfettiParticle> _particles = [];
  final math.Random _random = math.Random();
  double _lastElapsedSeconds = 0.0;
  late final String _quote;

  @override
  void initState() {
    super.initState();
    _quote = _inspirationalQuotes[_random.nextInt(_inspirationalQuotes.length)];
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

    HabitCelebrationService.playGoalMetImpact();
  }

  void _initParticles(Size size) {
    if (_particles.isNotEmpty) return;

    final centerX = size.width / 2;
    final startY = size.height * 0.36;

    for (int i = 0; i < 52; i++) {
      final angle = (_random.nextDouble() * math.pi) + math.pi; // 向上弧形喷射
      final speed = 190 + _random.nextDouble() * 280;
      final vx = math.cos(angle) * speed * 1.15;
      final vy = math.sin(angle) * speed;

      _particles.add(
        _ConfettiParticle(
          x: centerX + (_random.nextDouble() - 0.5) * 60,
          y: startY + (_random.nextDouble() - 0.5) * 40,
          vx: vx,
          vy: vy,
          size: 7 + _random.nextDouble() * 7,
          paletteIndex: _random.nextInt(_habitConfettiPalette.length),
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

    const gravity = 460.0;
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
                child: CustomPaint(
                  size: size,
                  painter: _ConfettiPainter(
                    particles: _particles,
                    animation: _controller,
                  ),
                ),
              ),

              // 居中庆祝卡片
              Center(
                child: TweenAnimationBuilder<double>(
                  tween: Tween<double>(begin: 0.75, end: 1.0),
                  duration: const Duration(milliseconds: 500),
                  curve: Curves.elasticOut,
                  builder: (context, scale, child) {
                    return Transform.scale(scale: scale, child: child);
                  },
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 28),
                    constraints: const BoxConstraints(maxWidth: 360),
                    child: OptionalLiquidGlassCard(
                      borderRadius: 24,
                      tint: const Color(0xFFFFD700).withValues(alpha: 0.12),
                      fallbackDecoration: BoxDecoration(
                        color: isDark
                            ? colorScheme.surfaceContainerHighest.withValues(
                                alpha: 0.94,
                              )
                            : colorScheme.surface.withValues(alpha: 0.96),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                          color: const Color(0xFFFFD700).withValues(alpha: 0.5),
                          width: 1.5,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.18),
                            blurRadius: 28,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 26,
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // 习惯图标与光环
                            Container(
                              width: 72,
                              height: 72,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: LinearGradient(
                                  colors: [
                                    const Color(0xFFFFD700)
                                        .withValues(alpha: 0.32),
                                    const Color(0xFFFF6D00)
                                        .withValues(alpha: 0.18),
                                  ],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                              ),
                              child: Text(
                                widget.goal.icon.isNotEmpty
                                    ? widget.goal.icon
                                    : '🎯',
                                style: const TextStyle(fontSize: 38),
                              ),
                            ),
                            const SizedBox(height: 16),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(
                                  Icons.verified_rounded,
                                  color: Color(0xFFFFB300),
                                  size: 20,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  '今日习惯达成！',
                                  style: TextStyle(
                                    fontSize: 19,
                                    fontWeight: FontWeight.w800,
                                    color: colorScheme.onSurface,
                                    letterSpacing: 0.3,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(
                              '「${widget.goal.name}」',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: colorScheme.primary,
                              ),
                            ),
                            if (widget.streakDays > 0) ...[
                              const SizedBox(height: 10),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFF9100)
                                      .withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  '🔥 已连续坚持 ${widget.streakDays} 天',
                                  style: const TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFFFF6D00),
                                  ),
                                ),
                              ),
                            ],
                            const SizedBox(height: 14),
                            Text(
                              _quote,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 13,
                                color: colorScheme.onSurface.withValues(
                                  alpha: 0.75,
                                ),
                                height: 1.45,
                              ),
                            ),
                            const SizedBox(height: 20),
                            FilledButton.tonal(
                              onPressed: () {
                                widget.onDismiss?.call();
                              },
                              style: FilledButton.styleFrom(
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 28,
                                  vertical: 10,
                                ),
                              ),
                              child: const Text(
                                '收到 ✨',
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

/// 弹出习惯达成庆祝弹窗。
Future<void> showHabitGoalMetCelebration(
  BuildContext context, {
  required HabitGoal goal,
  int streakDays = 0,
}) async {
  await HabitCelebrationService.ensureInitialized();
  if (!HabitCelebrationService.isCelebrationEnabled) return;

  if (!context.mounted) return;

  await showDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierColor: Colors.black.withValues(alpha: 0.35),
    builder: (dialogCtx) => HabitGoalMetOverlay(
      goal: goal,
      streakDays: streakDays,
      onDismiss: () {
        if (dialogCtx.mounted) {
          Navigator.of(dialogCtx).pop();
        }
      },
    ),
  );
}
