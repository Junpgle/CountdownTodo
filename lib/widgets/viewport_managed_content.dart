import 'package:flutter/widgets.dart';
import 'package:visibility_detector/visibility_detector.dart';

/// Pauses offscreen animations while preserving section state and loaded data.
/// Disposing dashboard sections during scrolling restarts their async loaders
/// and can increase transient allocations instead of reducing memory usage.
class ViewportManagedContent extends StatefulWidget {
  const ViewportManagedContent({super.key, required this.child});

  final Widget child;

  @override
  State<ViewportManagedContent> createState() => _ViewportManagedContentState();
}

class _ViewportManagedContentState extends State<ViewportManagedContent> {
  final Key _visibilityKey = UniqueKey();
  bool _isVisible = true;

  void _handleVisibilityChanged(VisibilityInfo info) {
    if (!mounted) return;
    final isVisible = info.visibleFraction > 0;
    if (isVisible == _isVisible) return;
    setState(() => _isVisible = isVisible);
  }

  @override
  Widget build(BuildContext context) {
    return VisibilityDetector(
      key: _visibilityKey,
      onVisibilityChanged: _handleVisibilityChanged,
      child: TickerMode(enabled: _isVisible, child: widget.child),
    );
  }
}
