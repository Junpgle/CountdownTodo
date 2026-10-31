import 'package:flutter/widgets.dart';

/// Optionally keeps a visited homepage section mounted after it leaves the list
/// cache. Platforms that opt out can reuse their loaded data through the
/// dashboard section cache and let the list release the section subtree.
class HomeDashboardScrollSection extends StatefulWidget {
  const HomeDashboardScrollSection({
    super.key,
    required this.child,
    this.keepAlive = true,
  });

  final Widget child;
  final bool keepAlive;

  @override
  State<HomeDashboardScrollSection> createState() =>
      _HomeDashboardScrollSectionState();
}

class _HomeDashboardScrollSectionState extends State<HomeDashboardScrollSection>
    with AutomaticKeepAliveClientMixin<HomeDashboardScrollSection> {
  @override
  bool get wantKeepAlive => widget.keepAlive;

  @override
  void didUpdateWidget(covariant HomeDashboardScrollSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.keepAlive != widget.keepAlive) updateKeepAlive();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}
