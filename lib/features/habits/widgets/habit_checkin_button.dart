import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/habit_celebration_service.dart';

/// 习惯打卡粒子模型。
class _BurstParticle {
  final double angle;
  final double distance;
  final double size;
  final Color color;
  final bool isStar;

  _BurstParticle({
    required this.angle,
    required this.distance,
    required this.size,
    required this.color,
    required this.isStar,
  });
}

/// 粒子画布绘制器。
class _BurstPainter extends CustomPainter {
  final List<_BurstParticle> particles;
  final double progress;

  _BurstPainter({required this.particles, required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0.0 || progress >= 1.0) return;

    final center = Offset(size.width / 2, size.height / 2);
    final paint = Paint()..style = PaintingStyle.fill;
    final curvedProgress = Curves.easeOutCubic.transform(progress);
    final alpha = (1.0 - progress).clamp(0.0, 1.0);

    for (final p in particles) {
      final currentDist = p.distance * curvedProgress;
      final x = center.dx + math.cos(p.angle) * currentDist;
      final y = center.dy + math.sin(p.angle) * currentDist;
      paint.color = p.color.withValues(alpha: alpha);

      if (p.isStar) {
        final currentSize = p.size * (1.0 - progress * 0.4);
        _drawFourPointStar(canvas, Offset(x, y), currentSize, paint);
      } else {
        canvas.drawCircle(Offset(x, y), p.size * (1.0 - progress * 0.3), paint);
      }
    }
  }

  void _drawFourPointStar(
    Canvas canvas,
    Offset center,
    double radius,
    Paint paint,
  ) {
    final path = Path();
    final innerRadius = radius * 0.35;
    for (int i = 0; i < 4; i++) {
      final outerAngle = (i * math.pi / 2) - (math.pi / 2);
      final innerAngle = outerAngle + (math.pi / 4);
      final ox = center.dx + math.cos(outerAngle) * radius;
      final oy = center.dy + math.sin(outerAngle) * radius;
      final ix = center.dx + math.cos(innerAngle) * innerRadius;
      final iy = center.dy + math.sin(innerAngle) * innerRadius;

      if (i == 0) {
        path.moveTo(ox, oy);
      } else {
        path.lineTo(ox, oy);
      }
      path.lineTo(ix, iy);
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _BurstPainter oldDelegate) =>
      oldDelegate.progress != progress;
}

/// 具有弹性缩放、长按蓄力与粒子爆发动效的打卡触发器包装组件。
class HabitCelebrationTrigger extends StatefulWidget {
  final Widget child;
  final Future<void> Function()? onCheckIn;
  final bool enabled;

  /// 为空时跟随 [HabitCelebrationService.isHoldToCheckinEnabled]。
  final bool? enableHoldToCheckin;

  /// 爆发微粒子主色调。为空时取主题 primary。
  final Color? burstColor;

  /// 圆角大小，用于绘制长按蓄力边框。
  final BorderRadius? borderRadius;

  /// 长按模式下短按时的提示信息。
  final String holdHint;

  /// 无障碍按钮名称；为空时使用 [holdHint]。
  final String? semanticLabel;

  const HabitCelebrationTrigger({
    super.key,
    required this.child,
    required this.onCheckIn,
    this.enabled = true,
    this.enableHoldToCheckin,
    this.burstColor,
    this.borderRadius,
    this.holdHint = '长按以打卡',
    this.semanticLabel,
  });

  @override
  State<HabitCelebrationTrigger> createState() =>
      _HabitCelebrationTriggerState();
}

class _HabitCelebrationTriggerState extends State<HabitCelebrationTrigger>
    with TickerProviderStateMixin {
  late final AnimationController _scaleController;
  late final AnimationController _holdController;
  late final AnimationController _burstController;

  final math.Random _random = math.Random();
  List<_BurstParticle> _particles = const [];
  int _lastFeedbackStep = -1;
  bool _isHolding = false;

  bool _completedInThisHold = false;

  bool get _isHoldMode =>
      widget.enableHoldToCheckin ??
      HabitCelebrationService.isHoldToCheckinEnabled;

  @override
  void initState() {
    super.initState();
    _scaleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 140),
      lowerBound: 0.93,
      upperBound: 1.0,
      value: 1.0,
    );

    _holdController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 560),
    );

    _burstController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 480),
    );

    _holdController.addListener(_onHoldProgress);
    _holdController.addStatusListener((status) {
      if (status == AnimationStatus.completed && _isHolding) {
        _isHolding = false;
        _completedInThisHold = true;
        final primary =
            widget.burstColor ?? Theme.of(context).colorScheme.primary;
        _triggerSuccess(primary);
      }
    });
  }

  @override
  void dispose() {
    _holdController.removeListener(_onHoldProgress);
    _scaleController.dispose();
    _holdController.dispose();
    _burstController.dispose();
    super.dispose();
  }

  void _onHoldProgress() {
    if (!_isHoldMode || !_isHolding) return;
    final step = (_holdController.value * 4).floor();
    if (step > _lastFeedbackStep && step > 0 && step < 4) {
      _lastFeedbackStep = step;
      HabitCelebrationService.playHoldStepImpact();
    }
  }

  void _generateParticles(Color primaryColor) {
    final colors = [
      primaryColor,
      const Color(0xFFFFD700), // 金色
      const Color(0xFFFF9100), // 暖橙
      const Color(0xFF00E676), // 翡翠绿
      primaryColor.withValues(alpha: 0.9),
    ];

    final list = <_BurstParticle>[];
    const count = 16;
    for (int i = 0; i < count; i++) {
      final baseAngle = (i * (2 * math.pi / count));
      final jitterAngle = (_random.nextDouble() - 0.5) * 0.35;
      final angle = baseAngle + jitterAngle;
      final distance = 36.0 + _random.nextDouble() * 32.0;
      final size = 3.5 + _random.nextDouble() * 3.5;
      final color = colors[_random.nextInt(colors.length)];
      final isStar = _random.nextBool();

      list.add(
        _BurstParticle(
          angle: angle,
          distance: distance,
          size: size,
          color: color,
          isStar: isStar,
        ),
      );
    }
    _particles = list;
  }

  Future<void> _triggerSuccess(Color primaryColor) async {
    _generateParticles(primaryColor);
    HabitCelebrationService.playCheckinImpact();

    _burstController.forward(from: 0.0);
    _scaleController.animateTo(1.0, curve: Curves.easeOutBack);

    await widget.onCheckIn?.call();
  }

  bool get _canActivate => widget.enabled && widget.onCheckIn != null;

  void _activateWithoutPointerHold() {
    if (!_canActivate) return;
    final primary = widget.burstColor ?? Theme.of(context).colorScheme.primary;
    unawaited(_triggerSuccess(primary));
  }

  void _handlePointerDown(PointerDownEvent event) {
    if (!widget.enabled || widget.onCheckIn == null) return;
    _scaleController.animateTo(0.93, curve: Curves.easeInOut);

    if (_isHoldMode) {
      _isHolding = true;
      _completedInThisHold = false;
      _lastFeedbackStep = -1;
      _holdController.forward(from: 0.0);
    }
  }

  void _handlePointerMove(PointerMoveEvent event) {
    if (!_isHolding) return;
    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox != null) {
      final localPos = renderBox.globalToLocal(event.position);
      if (!renderBox.size.contains(localPos)) {
        // 移出手势范围，平滑取消蓄力打卡
        _isHolding = false;
        _completedInThisHold = true; // 阻止后续 pointerUp 触发打卡
        _holdController.reverse();
        _scaleController.animateTo(1.0, curve: Curves.easeOutCubic);
      }
    }
  }

  void _handlePointerUp(PointerUpEvent event) {
    if (!widget.enabled || widget.onCheckIn == null) return;

    if (_isHoldMode) {
      if (_completedInThisHold) {
        _completedInThisHold = false;
        _holdController.reset();
        return;
      }
      _isHolding = false;
      _holdController.reverse();
      _scaleController.animateTo(1.0, curve: Curves.easeOutBack);
      // 长按模式下，未满蓄力就松手只取消操作；即时辅助激活由语义／键盘
      // 动作单独处理，避免把防误触设置重新变成轻触打卡。
    } else {
      final primary =
          widget.burstColor ?? Theme.of(context).colorScheme.primary;
      _triggerSuccess(primary);
    }
  }

  void _handlePointerCancel(PointerCancelEvent event) {
    if (!widget.enabled) return;
    _isHolding = false;
    _completedInThisHold = false;
    if (_isHoldMode) {
      _holdController.reverse();
    }
    _scaleController.animateTo(1.0, curve: Curves.easeOutCubic);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primaryColor = widget.burstColor ?? theme.colorScheme.primary;
    final effectiveRadius = widget.borderRadius ?? BorderRadius.circular(12);

    return FocusableActionDetector(
      enabled: _canActivate,
      shortcuts: const <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
      },
      actions: <Type, Action<Intent>>{
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            _activateWithoutPointerHold();
            return null;
          },
        ),
      },
      child: Semantics(
        button: true,
        enabled: _canActivate,
        label: widget.semanticLabel ?? widget.holdHint,
        hint: _isHoldMode ? '${widget.holdHint}；轻触会取消蓄力，辅助操作可直接打卡。' : '轻触以打卡。',
        onTap: _canActivate ? _activateWithoutPointerHold : null,
        child: ExcludeSemantics(
          child: Stack(
            fit: StackFit.passthrough,
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                excludeFromSemantics: true,
                onTap: () {
                  // 吸收点击手势，阻止向上冒泡至卡片全局的跳转详情 onTap
                },
                onTapDown: (_) {},
                onTapUp: (_) {},
                onTapCancel: () {},
                child: Listener(
                  behavior: HitTestBehavior.opaque,
                  onPointerDown: _handlePointerDown,
                  onPointerMove: _handlePointerMove,
                  onPointerUp: _handlePointerUp,
                  onPointerCancel: _handlePointerCancel,
                  child: AnimatedBuilder(
                    animation: Listenable.merge([
                      _scaleController,
                      _holdController,
                    ]),
                    builder: (context, child) {
                      final scale = _scaleController.value;
                      final holdProgress = _holdController.value;

                      return Transform.scale(
                        scale: scale,
                        child: CustomPaint(
                          foregroundPainter: _isHoldMode && holdProgress > 0.0
                              ? _HoldProgressBorderPainter(
                                  progress: holdProgress,
                                  color: primaryColor,
                                  borderRadius: effectiveRadius,
                                )
                              : null,
                          child: widget.child,
                        ),
                      );
                    },
                  ),
                ),
              ),

              // 粒子爆发层
              Positioned.fill(
                child: IgnorePointer(
                  child: RepaintBoundary(
                    child: AnimatedBuilder(
                      animation: _burstController,
                      builder: (context, child) {
                        if (!_burstController.isAnimating) {
                          return const SizedBox.shrink();
                        }
                        return CustomPaint(
                          painter: _BurstPainter(
                            particles: _particles,
                            progress: _burstController.value,
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 长按蓄力边框光流绘制器。
class _HoldProgressBorderPainter extends CustomPainter {
  final double progress;
  final Color color;
  final BorderRadius borderRadius;

  static final Paint _fillPaint = Paint()..style = PaintingStyle.fill;
  static final Paint _borderPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round;

  _HoldProgressBorderPainter({
    required this.progress,
    required this.color,
    required this.borderRadius,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0.0) return;

    final rect = Rect.fromLTWH(0, 0, size.width, size.height);
    final rrect = borderRadius.toRRect(rect);

    // 绘制内部轻微蓄力填充背景
    _fillPaint.color = color.withValues(
      alpha: (progress * 0.18).clamp(0.0, 0.25),
    );
    canvas.drawRRect(rrect, _fillPaint);

    // 绘制蓄力流光边框
    _borderPaint
      ..strokeWidth = 2.0 + (progress * 1.5)
      ..color = color.withValues(alpha: (0.4 + progress * 0.6).clamp(0.0, 1.0));

    final path = Path()..addRRect(rrect);
    final pathMetrics = path.computeMetrics().toList();
    if (pathMetrics.isEmpty) return;

    final metric = pathMetrics.first;
    final extractLength = metric.length * progress;
    final extractPath = metric.extractPath(0.0, extractLength);

    canvas.drawPath(extractPath, _borderPaint);
  }

  @override
  bool shouldRepaint(covariant _HoldProgressBorderPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.color != color;
}
