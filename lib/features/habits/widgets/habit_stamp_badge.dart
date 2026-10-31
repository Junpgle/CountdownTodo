import 'package:flutter/material.dart';

import '../services/habit_celebration_service.dart';

/// 具有物理冲击感、震颤与回弹的盖章动画组件。
class HabitStampBadge extends StatefulWidget {
  /// 是否触发播放盖章动画。
  final bool animate;

  /// 印章文案，默认“已达成”。
  final String text;

  /// 印章颜色，默认使用喜庆朱砂红或琥珀金。
  final Color? color;

  /// 印章尺寸（默认 120）。
  final double size;

  /// 水印不透明度（默认 0.28，作为半透明衬底）。
  final double opacity;

  /// 倾斜角度（弧度），默认约 -12°。
  final double angle;

  /// 动画完成回调。
  final VoidCallback? onAnimationComplete;

  const HabitStampBadge({
    super.key,
    this.animate = true,
    this.text = '已达成',
    this.color,
    this.size = 120.0,
    this.opacity = 0.28,
    this.angle = -0.22,
    this.onAnimationComplete,
  });

  @override
  State<HabitStampBadge> createState() => _HabitStampBadgeState();
}

class _HabitStampBadgeState extends State<HabitStampBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scaleAnimation;
  late final Animation<double> _opacityAnimation;
  late final Animation<double> _shockwaveAnimation;
  bool _hapticFired = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 580),
    );

    // 0.0 - 0.42: 蓄力悬空下砸 (2.4 -> 0.92)
    // 0.42 - 1.00: 触底回弹沉降 (0.92 -> 1.0)
    _scaleAnimation = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(
          begin: 2.4,
          end: 0.92,
        ).chain(CurveTween(curve: Curves.easeInCubic)),
        weight: 42,
      ),
      TweenSequenceItem(
        tween: Tween<double>(
          begin: 0.92,
          end: 1.0,
        ).chain(CurveTween(curve: Curves.easeOutBack)),
        weight: 58,
      ),
    ]).animate(_controller);

    _opacityAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.35, curve: Curves.easeIn),
      ),
    );

    // 落地瞬间向外扩散的印泥震波
    _shockwaveAnimation = Tween<double>(begin: 0.8, end: 1.6).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.40, 1.0, curve: Curves.easeOutCubic),
      ),
    );

    _controller.addListener(() {
      if (_controller.value >= 0.40 && !_hapticFired) {
        _hapticFired = true;
        HabitCelebrationService.playGoalMetImpact();
      }
    });

    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        widget.onAnimationComplete?.call();
      }
    });

    if (widget.animate) {
      _controller.forward(from: 0.0);
    } else {
      _controller.value = 1.0;
    }
  }

  @override
  void didUpdateWidget(HabitStampBadge oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.animate && !oldWidget.animate) {
      _hapticFired = false;
      _controller.forward(from: 0.0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final stampColor = widget.color ?? const Color(0xFFE53935); // 传统朱砂红印泥色

    final stampBody = Container(
      width: widget.size,
      height: widget.size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: stampColor,
          width: (widget.size * 0.035).clamp(2.0, 5.0),
        ),
        boxShadow: [
          BoxShadow(
            color: stampColor.withValues(alpha: 0.25),
            blurRadius: widget.size * 0.1,
            spreadRadius: 1,
          ),
        ],
      ),
      padding: EdgeInsets.all(widget.size * 0.045),
      child: Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: stampColor.withValues(alpha: 0.75),
            width: (widget.size * 0.015).clamp(1.0, 2.5),
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.star_rounded,
              size: widget.size * 0.18,
              color: stampColor,
            ),
            SizedBox(height: widget.size * 0.015),
            Text(
              widget.text,
              style: TextStyle(
                fontSize: widget.size * 0.16,
                fontWeight: FontWeight.w900,
                letterSpacing: widget.size * 0.015,
                color: stampColor,
                height: 1.1,
              ),
            ),
            SizedBox(height: widget.size * 0.015),
            Text(
              'COMPLETED',
              style: TextStyle(
                fontSize: widget.size * 0.075,
                fontWeight: FontWeight.w800,
                letterSpacing: widget.size * 0.01,
                color: stampColor.withValues(alpha: 0.85),
              ),
            ),
          ],
        ),
      ),
    );

    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _controller,
        child: stampBody,
        builder: (context, child) {
          final shockwaveProgress = (_controller.value - 0.45) / 0.55;
          final shockwaveAlpha =
              (1.0 - shockwaveProgress).clamp(0.0, 1.0) * 0.45 * widget.opacity;

          final badgeOpacity = (_opacityAnimation.value * widget.opacity).clamp(
            0.0,
            1.0,
          );

          return Transform.rotate(
            angle: widget.angle,
            child: Transform.scale(
              scale: _scaleAnimation.value,
              child: Opacity(
                opacity: badgeOpacity,
                child: Stack(
                  alignment: Alignment.center,
                  clipBehavior: Clip.none,
                  children: [
                    // 触地扩散冲击波
                    if (_controller.value >= 0.45 && shockwaveAlpha > 0.0)
                      Transform.scale(
                        scale: _shockwaveAnimation.value,
                        child: Container(
                          width: widget.size * 1.05,
                          height: widget.size * 1.05,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: stampColor.withValues(
                                alpha: shockwaveAlpha,
                              ),
                              width: (widget.size * 0.025).clamp(1.5, 4.0),
                            ),
                          ),
                        ),
                      ),

                    // 印章实体
                    child!,
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
