import 'package:flutter/widgets.dart';

/// Keeps a visited homepage section's loaded content and height when it leaves
/// the list cache. Recreating an async section with its loading placeholder can
/// otherwise make the sliver correct the scroll offset during a gentle drag.
class HomeDashboardScrollSection extends StatefulWidget {
  const HomeDashboardScrollSection({super.key, required this.child});

  final Widget child;

  @override
  State<HomeDashboardScrollSection> createState() =>
      _HomeDashboardScrollSectionState();
}

class _HomeDashboardScrollSectionState extends State<HomeDashboardScrollSection>
    with AutomaticKeepAliveClientMixin<HomeDashboardScrollSection> {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}
