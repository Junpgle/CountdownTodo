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

class CoachMarkOverlay extends StatefulWidget {
  final List<CoachMarkStep> steps;
  final VoidCallback onFinish;
  final VoidCallback onSkip;

  const CoachMarkOverlay({
    super.key,
    required this.steps,
    required this.onFinish,
    required this.onSkip,
  });

  @override
  State<CoachMarkOverlay> createState() => _CoachMarkOverlayState();
}

class _CoachMarkOverlayState extends State<CoachMarkOverlay> {
  int _currentStep = 0;
  OverlayEntry? _overlayEntry;
  final LayerLink _layerLink = LayerLink();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _showStep(0));
  }

  void _showStep(int index) {
    if (index >= widget.steps.length) {
      widget.onFinish();
      return;
    }
    setState(() => _currentStep = index);
  }

  void _nextStep() {
    _showStep(_currentStep + 1);
  }

  void _skip() {
    widget.onSkip();
  }

  @override
  Widget build(BuildContext context) {
    if (_currentStep >= widget.steps.length) return const SizedBox.shrink();

    final step = widget.steps[_currentStep];
    return Material(
      color: Colors.black54,
      child: Stack(
        children: [
          GestureDetector(
            onTap: _nextStep,
            child: Container(color: Colors.transparent),
          ),
          CompositedTransformFollower(
            link: _layerLink,
            targetAnchor: Alignment.bottomCenter,
            followerAnchor: Alignment.topCenter,
            offset: const Offset(0, 16),
            child: _buildTooltip(step),
          ),
          if (_currentStep < widget.steps.length - 1)
            Positioned(
              top: 16,
              right: 16,
              child: TextButton(
                onPressed: _skip,
                child: const Text('跳过教程',
                    style: TextStyle(color: Colors.white70)),
              ),
            ),
          if (_currentStep == widget.steps.length - 1)
            Positioned(
              bottom: 32,
              left: 0,
              right: 0,
              child: Center(
                child: FilledButton(
                  onPressed: _nextStep,
                  child: const Text('完成引导'),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTooltip(CoachMarkStep step) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 16,
            offset: const Offset(0, 4),
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
              color: scheme.onSurface.withValues(alpha: 0.7),
              height: 1.4,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${_currentStep + 1} / ${widget.steps.length}',
                style: TextStyle(
                  fontSize: 12,
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
                          _nextStep();
                        },
                        child: Text(step.buttonLabel!),
                      ),
                    ),
                  FilledButton(
                    onPressed: _nextStep,
                    style: FilledButton.styleFrom(
                      visualDensity: VisualDensity.compact,
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
    );
  }

  @override
  void dispose() {
    _overlayEntry?.remove();
    super.dispose();
  }
}
