import 'package:flutter/material.dart';

class CoachMarkStep {
  final GlobalKey targetKey;
  final String title;
  final String description;
  final String? buttonLabel;
  final VoidCallback? onButtonTap;

  const CoachMarkStep({
    required this.targetKey,
    required this.title,
    required this.description,
    this.buttonLabel,
    this.onButtonTap,
  });
}

class CoachMarkOverlay {
  static void show({
    required BuildContext context,
    required List<CoachMarkStep> steps,
    required VoidCallback onFinish,
    required VoidCallback onSkip,
  }) {
    late OverlayEntry overlayEntry;

    overlayEntry = OverlayEntry(
      builder: (ctx) {
        return _CoachMarkOverlayWidget(
          steps: steps,
          onFinish: () {
            overlayEntry.remove();
            onFinish();
          },
          onSkip: () {
            overlayEntry.remove();
            onSkip();
          },
        );
      },
    );

    Overlay.of(context).insert(overlayEntry);
  }
}

class _CoachMarkOverlayWidget extends StatefulWidget {
  final List<CoachMarkStep> steps;
  final VoidCallback onFinish;
  final VoidCallback onSkip;

  const _CoachMarkOverlayWidget({
    super.key,
    required this.steps,
    required this.onFinish,
    required this.onSkip,
  });

  @override
  State<_CoachMarkOverlayWidget> createState() => _CoachMarkOverlayWidgetState();
}

class _CoachMarkOverlayWidgetState extends State<_CoachMarkOverlayWidget> {
  int _currentStep = 0;
  Rect? _targetRect;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _calculateTargetRect());
  }

  void _calculateTargetRect() {
    if (_currentStep >= widget.steps.length) {
      widget.onFinish();
      return;
    }
    final step = widget.steps[_currentStep];
    final context = step.targetKey.currentContext;
    if (context != null) {
      final RenderBox renderBox = context.findRenderObject() as RenderBox;
      final offset = renderBox.localToGlobal(Offset.zero);
      setState(() {
        _targetRect = offset & renderBox.size;
      });
    } else {
      // Key not found in widget tree, fallback or skip
      setState(() {
        _targetRect = null;
      });
    }
  }

  void _nextStep() {
    if (_currentStep < widget.steps.length - 1) {
      setState(() {
        _currentStep++;
        _targetRect = null; // Hide temporarily while calculating
      });
      WidgetsBinding.instance.addPostFrameCallback((_) => _calculateTargetRect());
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
              painter: _HolePainter(_targetRect),
              child: Container(),
            ),
          ),
          
          // 2. Skip Button
          Positioned(
            top: MediaQuery.of(context).padding.top + 16,
            right: 16,
            child: TextButton(
              onPressed: widget.onSkip,
              child: const Text('跳过教程', style: TextStyle(color: Colors.white70)),
            ),
          ),

          // 3. Tooltip Bubble
          if (_targetRect != null)
            _buildTooltip(step, _targetRect!),
        ],
      ),
    );
  }

  Widget _buildTooltip(CoachMarkStep step, Rect targetRect) {
    final screenSize = MediaQuery.of(context).size;
    final isBottomSpaceAvailable = (screenSize.height - targetRect.bottom) > 220;
    
    return Positioned(
      top: isBottomSpaceAvailable ? targetRect.bottom + 16 : null,
      bottom: !isBottomSpaceAvailable ? screenSize.height - targetRect.top + 16 : null,
      left: 16,
      right: 16,
      child: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 340),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
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
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                step.description,
                style: TextStyle(
                  fontSize: 14,
                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.75),
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
                      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.4),
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
                              _nextStep();
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
