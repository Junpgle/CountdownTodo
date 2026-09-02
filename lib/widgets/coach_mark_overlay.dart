import 'dart:async';

import 'package:flutter/material.dart';

class CoachMarkStep {
  final GlobalKey targetKey;
  final String title;
  final String description;
  final String? buttonLabel;
  final VoidCallback? onButtonTap;
  final bool finishOnButtonTap;

  const CoachMarkStep({
    required this.targetKey,
    required this.title,
    required this.description,
    this.buttonLabel,
    this.onButtonTap,
    this.finishOnButtonTap = false,
  });
}

class CoachMarkOverlay {
  static Future<bool> show({
    required BuildContext context,
    required List<CoachMarkStep> steps,
    required VoidCallback onFinish,
    required VoidCallback onSkip,
  }) {
    final completed = Completer<bool>();
    late OverlayEntry overlayEntry;

    overlayEntry = OverlayEntry(
      builder: (ctx) {
        return _CoachMarkOverlayWidget(
          steps: steps,
          onFinish: () {
            overlayEntry.remove();
            onFinish();
            if (!completed.isCompleted) completed.complete(true);
          },
          onSkip: () {
            overlayEntry.remove();
            onSkip();
            if (!completed.isCompleted) completed.complete(false);
          },
        );
      },
    );

    Overlay.of(context, rootOverlay: true).insert(overlayEntry);
    return completed.future;
  }
}

class _CoachMarkOverlayWidget extends StatefulWidget {
  final List<CoachMarkStep> steps;
  final VoidCallback onFinish;
  final VoidCallback onSkip;

  const _CoachMarkOverlayWidget({
    required this.steps,
    required this.onFinish,
    required this.onSkip,
  });

  @override
  State<_CoachMarkOverlayWidget> createState() =>
      _CoachMarkOverlayWidgetState();
}

class _CoachMarkOverlayWidgetState extends State<_CoachMarkOverlayWidget> {
  int _currentStep = 0;
  Rect? _targetRect;
  bool _isCalculating = true; // 🚀 新增：标记是否正在计算坐标（比如正在滚动）

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _calculateTargetRect());
  }

  Future<void> _calculateTargetRect() async {
    if (!mounted) return;
    if (_currentStep >= widget.steps.length) {
      widget.onFinish();
      return;
    }
    final step = widget.steps[_currentStep];
    final context = step.targetKey.currentContext;
    if (context != null) {
      // 🚀 先滚动到可见区域并居中，以免元素在屏幕外导致错位
      await Scrollable.ensureVisible(
        context,
        alignment: 0.5,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
      if (!mounted || !context.mounted) return;

      // 某些页面使用容器变换动画进入。目标控件在动画期间会跟着整页
      // 从来源位置移动到最终位置，必须等路由动画完成后再读取坐标。
      await _waitForRouteAnimation(context);
      if (!mounted || !context.mounted) return;
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted || !context.mounted) return;

      final RenderBox renderBox = context.findRenderObject() as RenderBox;

      // 教程遮罩铺满根 Overlay，而目标控件可能位于嵌套路由、侧边栏或
      // 带 Transform 的页面中，因此直接使用相对 Flutter 视图的全局坐标。
      // 不要再减去 Overlay RenderBox 的 origin：桌面端 Overlay 的布局原点
      // 可能已经是窗口原点，但其 RenderBox 的 global origin 会带有页面内边距。
      final targetTopLeft = renderBox.localToGlobal(Offset.zero);
      final targetBottomRight = renderBox.localToGlobal(
        renderBox.size.bottomRight(Offset.zero),
      );
      final targetRect = Rect.fromPoints(
        targetTopLeft,
        targetBottomRight,
      );

      setState(() {
        _targetRect = targetRect;
        _isCalculating = false;
      });
    } else {
      // Key not found in widget tree, display the tooltip at the center without a hole
      setState(() {
        _targetRect = null;
        _isCalculating = false;
      });
    }
  }

  Future<void> _waitForRouteAnimation(BuildContext targetContext) async {
    final animation = ModalRoute.of(targetContext)?.animation;
    if (animation == null || animation.status == AnimationStatus.completed) {
      return;
    }

    final settled = Completer<void>();
    late final AnimationStatusListener listener;
    listener = (status) {
      if (status == AnimationStatus.completed ||
          status == AnimationStatus.dismissed) {
        animation.removeStatusListener(listener);
        if (!settled.isCompleted) settled.complete();
      }
    };
    animation.addStatusListener(listener);
    if (animation.status == AnimationStatus.completed ||
        animation.status == AnimationStatus.dismissed) {
      animation.removeStatusListener(listener);
      if (!settled.isCompleted) settled.complete();
    }
    await settled.future;
  }

  void _nextStep() {
    if (_currentStep < widget.steps.length - 1) {
      setState(() {
        _currentStep++;
        _isCalculating = true; // 🚀 标记为正在计算
        // _targetRect = null; // 不再清空，避免中间态闪烁
      });
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _calculateTargetRect());
    } else {
      widget.onFinish();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_currentStep >= widget.steps.length) return const SizedBox.shrink();

    final step = widget.steps[_currentStep];
    return Material(
      color: Colors.transparent,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // 1. Cutout Mask
          GestureDetector(
            onTap: _nextStep,
            child: CustomPaint(
              painter: _HolePainter(_isCalculating ? null : _targetRect),
              child: Container(),
            ),
          ),

          // 2. Skip Button
          Positioned(
            top: MediaQuery.of(context).padding.top + 16,
            right: 16,
            child: TextButton(
              onPressed: widget.onSkip,
              child:
                  const Text('跳过教程', style: TextStyle(color: Colors.white70)),
            ),
          ),

          // 3. Tooltip Bubble
          if (!_isCalculating) _buildTooltip(step, _targetRect),
        ],
      ),
    );
  }

  Widget _buildTooltip(CoachMarkStep step, Rect? targetRect) {
    final scheme = Theme.of(context).colorScheme;
    return Positioned.fill(
      child: CustomSingleChildLayout(
        delegate: _CoachMarkTooltipLayoutDelegate(targetRect: targetRect),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 340),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: scheme.surface,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.15),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                step.title,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: scheme.onSurface,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                step.description,
                style: TextStyle(
                  fontSize: 14,
                  color: scheme.onSurface.withValues(alpha: 0.75),
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${_currentStep + 1} / ${widget.steps.length}',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: scheme.onSurface.withValues(alpha: 0.4),
                    ),
                  ),
                  Row(
                    children: [
                      if (step.buttonLabel != null)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: TextButton(
                            onPressed: () {
                              step.onButtonTap?.call();
                              if (step.finishOnButtonTap) {
                                widget.onFinish();
                              } else {
                                _nextStep();
                              }
                            },
                            child: Text(step.buttonLabel!),
                          ),
                        ),
                      FilledButton(
                        onPressed: _nextStep,
                        style: FilledButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                        ),
                        child: Text(
                          _currentStep == widget.steps.length - 1
                              ? '完成'
                              : '下一步',
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CoachMarkTooltipLayoutDelegate extends SingleChildLayoutDelegate {
  final Rect? targetRect;
  static const double _margin = 16;
  static const double _gap = 16;

  const _CoachMarkTooltipLayoutDelegate({required this.targetRect});

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    return BoxConstraints(
      minWidth: 0,
      maxWidth: constraints.maxWidth - _margin * 2,
      minHeight: 0,
      maxHeight: constraints.maxHeight - _margin * 2,
    );
  }

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final maxLeft = size.width - childSize.width - _margin;
    final centeredLeft = (size.width - childSize.width) / 2;
    final left = centeredLeft.clamp(_margin, maxLeft).toDouble();

    if (targetRect == null) {
      final centeredTop = (size.height - childSize.height) / 2;
      return Offset(left, centeredTop.clamp(_margin, _maxTop(size, childSize)));
    }

    final topSpace = targetRect!.top - _gap - childSize.height;
    final bottomSpace = targetRect!.bottom + _gap;
    final maxTop = _maxTop(size, childSize);

    final top = bottomSpace + childSize.height <= size.height - _margin
        ? bottomSpace
        : topSpace >= _margin
            ? topSpace
            : (targetRect!.center.dy - childSize.height / 2)
                .clamp(_margin, maxTop)
                .toDouble();
    return Offset(left, top.clamp(_margin, maxTop).toDouble());
  }

  double _maxTop(Size size, Size childSize) =>
      (size.height - childSize.height - _margin).clamp(_margin, size.height);

  @override
  bool shouldRelayout(covariant _CoachMarkTooltipLayoutDelegate oldDelegate) {
    return oldDelegate.targetRect != targetRect;
  }
}

class _HolePainter extends CustomPainter {
  final Rect? targetRect;

  _HolePainter(this.targetRect);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.black.withValues(alpha: 0.65);
    if (targetRect == null) {
      canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), paint);
      return;
    }

    final holeRect = targetRect!.inflate(8); // Give breathing room
    final path = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..addRRect(RRect.fromRectAndRadius(holeRect, const Radius.circular(16)))
      ..fillType = PathFillType.evenOdd;

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _HolePainter oldDelegate) {
    return oldDelegate.targetRect != targetRect;
  }
}
