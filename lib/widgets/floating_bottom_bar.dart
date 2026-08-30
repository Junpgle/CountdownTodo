import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'floating_glass_control.dart';
import 'home_bottom_navigation_content.dart';

export 'floating_glass_control.dart'
    show
        FloatingGlassAppBar,
        FloatingGlassAppBarAction,
        FloatingGlassActionButton,
        FloatingGlassControl,
        LiquidGlassSwitch,
        LiquidGlassSwitchListTile,
        liquidGlassSwitchActiveColorFor,
        FloatingGlassLargeFlexibleSpace,
        FloatingGlassPinnedHeaderLayout,
        FloatingGlassScrollAware,
        FloatingGlassSliverAppBar,
        FloatingGlassSliverContentFade,
        FloatingGlassSliverContentFadeGroup,
        FloatingGlassTopBarBackground,
        FloatingGlassTopBarContentFade,
        FloatingGlassTopBarOverlay,
        floatingGlassTopBarContentFadeShader,
        floatingGlassTopBarDefaultFadeTail,
        floatingGlassSettingsBody,
        floatingGlassSettingsContentTopInset,
        floatingGlassTopBarHeight,
        floatingGlassTopBarSystemOverlayStyle,
        floatingGlassTopBarTitleProgress,
        floatingGlassStandardControlSize,
        floatingBottomBarShouldFloat,
        floatingBottomBarShouldFloatFor;

export 'home_bottom_navigation_content.dart' show FloatingBottomNavigationItem;

/// Resolves the compact homepage height for the shared phone navigation bar.
double floatingBottomBarHeightFor(BuildContext context) {
  final bottomInset = MediaQuery.viewPaddingOf(context).bottom;
  return 60.0 + (bottomInset > 0 ? bottomInset * 0.5 : 6.0);
}

/// Resolves the homepage's phone margins for the shared navigation bar.
EdgeInsets floatingBottomBarMarginFor(BuildContext context) {
  return floatingBottomNavigationMarginFor(context, itemCount: 3);
}

/// Resolves the capsule width for a shared navigation bar.
///
/// The homepage's three destinations are the reference: preserve that exact
/// width, then scale it by the number of destinations so each slot keeps the
/// same visual rhythm. A small screen-edge inset remains as a safety cap for
/// four- and five-item bars.
@visibleForTesting
double floatingBottomNavigationWidthFor(
  double screenWidth, {
  required int itemCount,
}) {
  final referenceMargin = homeBottomBarHorizontalMarginFor(screenWidth);
  final referenceWidth = math.max(0.0, screenWidth - referenceMargin * 2.0);
  final proportionalWidth =
      referenceWidth * math.max(1, itemCount).toDouble() / 3.0;
  final availableWidth = math.max(0.0, screenWidth - 32.0);
  return math.min(proportionalWidth, availableWidth);
}

/// Resolves margins for the shared navigation bar from its item count.
EdgeInsets floatingBottomNavigationMarginFor(
  BuildContext context, {
  required int itemCount,
}) {
  final width = MediaQuery.sizeOf(context).width;
  final navigationWidth = floatingBottomNavigationWidthFor(
    width,
    itemCount: itemCount,
  );
  final horizontal = math.max(16.0, (width - navigationWidth) / 2.0);
  return EdgeInsets.fromLTRB(horizontal, 0, horizontal, 24);
}

/// Shared floating glass shell for bottom navigation and bottom actions.
///
/// The child remains responsible for its own semantics and interaction. This
/// widget only supplies the capsule geometry, live Liquid Glass treatment (if
/// enabled), and a matching neutral fallback. Set [mobilePortraitOnly] to
/// false for a bar that is already known to be rendered exclusively on a
/// phone, such as the home dashboard's custom bar.
class FloatingBottomBar extends StatelessWidget {
  const FloatingBottomBar({
    super.key,
    required this.child,
    this.height = 88,
    this.margin = const EdgeInsets.fromLTRB(16, 8, 16, 12),
    this.borderRadius = 34,
    this.tint,
    this.haloColor,
    this.isDark,
    this.mobilePortraitOnly = true,
    this.allowChildOverflow = true,
  });

  final Widget child;
  final double height;
  final EdgeInsetsGeometry margin;
  final double borderRadius;
  final Color? tint;
  final Color? haloColor;
  final bool? isDark;
  final bool mobilePortraitOnly;
  final bool allowChildOverflow;

  @override
  Widget build(BuildContext context) {
    return FloatingGlassControl(
      height: height,
      margin: margin,
      borderRadius: borderRadius,
      tint: tint,
      haloColor: haloColor,
      isDark: isDark,
      mobilePortraitOnly: mobilePortraitOnly,
      allowChildOverflow: allowChildOverflow,
      child: child,
    );
  }
}

/// Complete shared navigation bar with the homepage's spring lens and liquid
/// glass interaction. Use this for phone portrait tab navigation; use
/// [FloatingBottomBar] directly for a non-tab action strip.
class FloatingBottomNavigationBar extends StatefulWidget {
  const FloatingBottomNavigationBar({
    super.key,
    required this.items,
    required this.selectedIndex,
    required this.onTabSelected,
    this.primaryColor,
    this.inactiveColor,
    this.selectedBackgroundColor,
    this.height,
    this.margin,
    this.tint,
    this.haloColor,
    this.isDark,
    this.mobilePortraitOnly = true,
    this.keyPrefix = 'floating-bottom',
  });

  final List<FloatingBottomNavigationItem> items;
  final int selectedIndex;
  final ValueChanged<int> onTabSelected;
  final Color? primaryColor;
  final Color? inactiveColor;
  final Color? selectedBackgroundColor;
  final double? height;
  final EdgeInsetsGeometry? margin;
  final Color? tint;
  final Color? haloColor;
  final bool? isDark;
  final bool mobilePortraitOnly;
  final String keyPrefix;

  @override
  State<FloatingBottomNavigationBar> createState() =>
      _FloatingBottomNavigationBarState();
}

class _FloatingBottomNavigationBarState
    extends State<FloatingBottomNavigationBar> {
  final ValueNotifier<double> _stretchNotifier = ValueNotifier<double>(0.0);

  @override
  void dispose() {
    _stretchNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final dark = widget.isDark ?? colorScheme.brightness == Brightness.dark;
    final primaryColor = widget.primaryColor ?? colorScheme.primary;
    final inactiveColor = widget.inactiveColor ?? colorScheme.onSurfaceVariant;
    final selectedBackgroundColor = widget.selectedBackgroundColor ??
        homeBottomBarSelectedBackgroundColor(
          colorScheme: colorScheme,
          primaryColor: primaryColor,
          isDark: dark,
        );
    final tint = widget.tint ??
        Color.alphaBlend(
          primaryColor.withValues(alpha: 0.08),
          colorScheme.surface,
        ).withValues(alpha: dark ? 0.24 : 0.32);
    final height = widget.height ?? floatingBottomBarHeightFor(context);
    final margin = widget.margin ??
        floatingBottomNavigationMarginFor(
          context,
          itemCount: widget.items.length,
        );

    final content = FloatingBottomNavigationContent(
      items: widget.items,
      selectedIndex: widget.selectedIndex,
      primaryColor: primaryColor,
      inactiveColor: inactiveColor,
      selectedBackgroundColor: selectedBackgroundColor,
      onTabSelected: widget.onTabSelected,
      onDragStretchChanged: (stretch) => _stretchNotifier.value = stretch,
      keyPrefix: widget.keyPrefix,
    );
    final surface = FloatingBottomBar(
      height: height,
      margin: margin,
      borderRadius: 34,
      tint: tint,
      haloColor: widget.haloColor ?? primaryColor,
      isDark: dark,
      mobilePortraitOnly: widget.mobilePortraitOnly,
      allowChildOverflow: true,
      child: content,
    );

    return ValueListenableBuilder<double>(
      valueListenable: _stretchNotifier,
      builder: (context, stretch, child) {
        final scaleX = 1.0 + stretch * 0.045;
        return Transform(
          alignment: Alignment.bottomCenter,
          transform: Matrix4.diagonal3Values(scaleX, 1.0, 1.0),
          child: child,
        );
      },
      child: surface,
    );
  }
}
