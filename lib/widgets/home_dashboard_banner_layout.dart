import 'package:flutter/material.dart';

class HomeDashboardBannerLayout extends StatelessWidget {
  const HomeDashboardBannerLayout({
    super.key,
    required this.bannerKey,
    required this.pomodoroRevision,
    required this.pomodoroBuilder,
    this.pomodoroChild,
    required this.showPomodoro,
    required this.banners,
  });

  final Key bannerKey;
  final Listenable pomodoroRevision;
  final WidgetBuilder pomodoroBuilder;
  final Widget? pomodoroChild;
  final bool showPomodoro;
  final List<Widget> banners;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: bannerKey,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showPomodoro)
          pomodoroChild ??
              AnimatedBuilder(
                animation: pomodoroRevision,
                builder: (context, _) => pomodoroBuilder(context),
              ),
        ...banners,
      ],
    );
  }
}
