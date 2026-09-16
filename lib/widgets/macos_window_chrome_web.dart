import 'package:flutter/widgets.dart';

/// No-op implementation for web builds.
class MacosWindowChrome extends StatelessWidget {
  const MacosWindowChrome({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}
