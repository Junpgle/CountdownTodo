import 'package:flutter/material.dart';

import '../utils/page_transitions.dart';

/// Paints the panel's container transform without replacing the held pointer's
/// route. The panel keeps its final layout throughout the animation.
class QuickVoiceContainerTransition extends StatefulWidget {
  const QuickVoiceContainerTransition({
    super.key,
    required this.sourceRect,
    required this.child,
  });

  final Rect sourceRect;
  final Widget child;

  @override
  State<QuickVoiceContainerTransition> createState() =>
      QuickVoiceContainerTransitionState();
}

class QuickVoiceContainerTransitionState
    extends State<QuickVoiceContainerTransition>
    with SingleTickerProviderStateMixin {
  final _panelKey = GlobalKey();
  late final _controller = AnimationController(vsync: this);
  late final _animation = CurvedAnimation(
    parent: _controller,
    curve: PageTransitions.containerCurve,
    reverseCurve: PageTransitions.containerReverseCurve,
  );
  Rect? _panelRect;
  bool _closing = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduced = MediaQuery.disableAnimationsOf(context);
    _controller.duration = reduced
        ? Duration.zero
        : PageTransitions.containerDuration();
    _controller.reverseDuration = reduced
        ? Duration.zero
        : PageTransitions.containerDuration(reverse: true);
    _measureAfterLayout();
  }

  void _measureAfterLayout() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final panel = _panelKey.currentContext?.findRenderObject() as RenderBox?;
      final box = context.findRenderObject() as RenderBox?;
      if (panel == null || box == null || !panel.hasSize) return;
      final rect = Rect.fromLTWH(
        (box.size.width - panel.size.width) / 2,
        box.size.height - panel.size.height,
        panel.size.width,
        panel.size.height,
      );
      if (_panelRect == rect) return;
      final firstLayout = _panelRect == null;
      setState(() => _panelRect = rect);
      if (firstLayout && !_closing) _controller.forward();
    });
  }

  Future<void> close() async {
    _closing = true;
    // Recorder cancellation has already happened; only its visual container
    // remains alive while returning to the source button.
    try {
      await _controller.reverse().orCancel;
    } on TickerCanceled {
      // The owning page may disappear during the exit animation.
    }
  }

  @override
  void dispose() {
    _animation.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return AnimatedBuilder(
      animation: _animation,
      child: Align(
        alignment: Alignment.bottomCenter,
        child: NotificationListener<SizeChangedLayoutNotification>(
          onNotification: (_) {
            _measureAfterLayout();
            return false;
          },
          child: SizeChangedLayoutNotifier(
            child: SizedBox(key: _panelKey, child: widget.child),
          ),
        ),
      ),
      builder: (context, child) {
        final t = _animation.value;
        final target = _panelRect ?? widget.sourceRect;
        final rect = Rect.lerp(widget.sourceRect, target, t)!;
        final radius = BorderRadius.lerp(
          BorderRadius.circular(widget.sourceRect.shortestSide / 2),
          const BorderRadius.vertical(top: Radius.circular(32)),
          t,
        )!;
        final contentProgress = ((t - 0.28) / 0.72).clamp(0.0, 1.0);
        final scale = target.width == 0 ? 1.0 : rect.width / target.width;
        final transform = Matrix4.identity()
          ..translateByDouble(rect.left, rect.top, 0, 1)
          ..scaleByDouble(scale, scale, 1, 1)
          ..translateByDouble(-target.left, -target.top, 0, 1);
        return Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(color: colors.scrim.withValues(alpha: 0.4 * t)),
            ClipPath(
              key: const ValueKey('quick-voice-container-transform'),
              clipper: _VoiceContainerClipper(radius.toRRect(rect)),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ColoredBox(color: colors.surfaceContainerHigh),
                  Opacity(
                    opacity: contentProgress,
                    child: Transform(transform: transform, child: child),
                  ),
                  if (contentProgress < 1)
                    Positioned.fromRect(
                      rect: rect,
                      child: Opacity(
                        opacity: 1 - contentProgress,
                        child: Icon(Icons.mic_rounded, color: colors.primary),
                      ),
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _VoiceContainerClipper extends CustomClipper<Path> {
  const _VoiceContainerClipper(this.rect);
  final RRect rect;

  @override
  Path getClip(Size size) => Path()..addRRect(rect);

  @override
  bool shouldReclip(_VoiceContainerClipper oldClipper) =>
      oldClipper.rect != rect;
}
