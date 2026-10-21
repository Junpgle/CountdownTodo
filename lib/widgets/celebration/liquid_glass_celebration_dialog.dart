import 'package:flutter/material.dart';

import '../optional_liquid_glass_surface.dart';
import 'confetti_particle_canvas.dart';

/// 居中 Liquid Glass 庆祝弹层公共组件。
///
/// 集成全屏彩带微粒子喷射动画、弹性缩放入场、Material 3 动态色彩与 Liquid Glass 质感卡片。
/// 广泛应用于待办清空庆祝、习惯达成庆祝等场景。
class LiquidGlassCelebrationDialog extends StatefulWidget {
  final VoidCallback? onDismiss;
  final bool autoDismiss;
  final Duration duration;
  final Widget? headerBadge;
  final String? title;
  final Widget? titleWidget;
  final Widget? content;
  final String? description;
  final Widget? descriptionWidget;
  final String actionLabel;
  final Key? actionKey;
  final Widget? action;
  final Color? tint;
  final int particleCount;
  final List<Color> palette;

  const LiquidGlassCelebrationDialog({
    super.key,
    this.onDismiss,
    this.autoDismiss = true,
    this.duration = const Duration(milliseconds: 2400),
    this.headerBadge,
    this.title,
    this.titleWidget,
    this.content,
    this.description,
    this.descriptionWidget,
    this.actionLabel = '太棒了',
    this.actionKey,
    this.action,
    this.tint,
    this.particleCount = 50,
    this.palette = defaultConfettiPalette,
  });

  /// 快捷构造带金光环形渐变底座的图标/徽章。
  static Widget buildGradientBadge({
    Widget? child,
    IconData? icon,
    Color iconColor = const Color(0xFFFFB300),
    double size = 72,
    double iconSize = 42,
    List<Color>? gradientColors,
  }) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: gradientColors ?? [
            const Color(0xFFFFD700).withValues(alpha: 0.3),
            const Color(0xFFFF6D00).withValues(alpha: 0.16),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: child ?? (icon != null ? Icon(icon, size: iconSize, color: iconColor) : null),
    );
  }

  /// 弹出居中庆祝弹窗。
  static Future<void> show({
    required BuildContext context,
    required WidgetBuilder builder,
    bool barrierDismissible = true,
    Color? barrierColor,
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: barrierDismissible,
      barrierColor: barrierColor ?? Colors.black.withValues(alpha: 0.35),
      builder: builder,
    );
  }

  @override
  State<LiquidGlassCelebrationDialog> createState() =>
      _LiquidGlassCelebrationDialogState();
}

class _LiquidGlassCelebrationDialogState
    extends State<LiquidGlassCelebrationDialog>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.duration,
    );

    _controller.forward().then((_) {
      if (mounted && widget.autoDismiss) {
        widget.onDismiss?.call();
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Material(
      type: MaterialType.transparency,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // 1. 全屏彩带彩屑粒子层
          ConfettiParticleCanvas(
            controller: _controller,
            duration: widget.duration,
            particleCount: widget.particleCount,
            palette: widget.palette,
          ),

          // 2. 居中弹性弹出庆祝卡片
          Center(
            child: TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: 0.78, end: 1.0),
              duration: const Duration(milliseconds: 480),
              curve: Curves.elasticOut,
              builder: (context, scale, child) {
                return Transform.scale(scale: scale, child: child);
              },
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 28),
                constraints: const BoxConstraints(maxWidth: 380),
                child: OptionalLiquidGlassCard(
                  borderRadius: 24,
                  tint: widget.tint ??
                      const Color(0xFFFFD700).withValues(alpha: 0.12),
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
                        color: Colors.black.withValues(alpha: 0.16),
                        blurRadius: 28,
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
                        // 徽章/图标底座
                        if (widget.headerBadge != null) ...[
                          widget.headerBadge!,
                          const SizedBox(height: 16),
                        ],

                        // 标题
                        if (widget.titleWidget != null)
                          widget.titleWidget!
                        else if (widget.title != null)
                          Text(
                            widget.title!,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: colorScheme.onSurface,
                              letterSpacing: 0.3,
                            ),
                          ),

                        // 自定义业务内容区（如 Streak 天数徽章、任务数统计）
                        if (widget.content != null) widget.content!,

                        // 描述/名言/小贴士
                        if (widget.descriptionWidget != null) ...[
                          const SizedBox(height: 12),
                          widget.descriptionWidget!,
                        ] else if (widget.description != null) ...[
                          const SizedBox(height: 12),
                          Text(
                            widget.description!,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 13.2,
                              color: colorScheme.onSurface.withValues(
                                alpha: 0.75,
                              ),
                              height: 1.45,
                            ),
                          ),
                        ],

                        const SizedBox(height: 20),

                        // 确认关闭按钮
                        if (widget.action != null)
                          widget.action!
                        else
                          FilledButton.tonal(
                            key: widget.actionKey,
                            onPressed: () {
                              widget.onDismiss?.call();
                            },
                            style: FilledButton.styleFrom(
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 26,
                                vertical: 10,
                              ),
                            ),
                            child: Text(
                              widget.actionLabel,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
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
  }
}
