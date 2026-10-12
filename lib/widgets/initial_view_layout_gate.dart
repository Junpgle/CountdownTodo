import 'package:flutter/widgets.dart';

/// Mounts the application after the first Flutter view frame has completed.
///
/// A newly focused web view can ask Flutter to find its first focus target
/// before the initial widget tree has completed layout. Reading-order focus
/// traversal reads render bounds, so mounting the app after one empty frame
/// keeps that request from measuring unlaid controls.
class InitialViewLayoutGate extends StatefulWidget {
  const InitialViewLayoutGate({super.key, required this.child});

  final Widget child;

  @override
  State<InitialViewLayoutGate> createState() => _InitialViewLayoutGateState();
}

class _InitialViewLayoutGateState extends State<InitialViewLayoutGate> {
  var _layoutFrameCompleted = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        setState(() => _layoutFrameCompleted = true);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return _layoutFrameCompleted ? widget.child : const SizedBox.shrink();
  }
}
