import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../utils/app_platform.dart';
import 'home_bottom_navigation_content.dart';
import 'optional_liquid_glass_surface.dart';

export 'home_bottom_navigation_content.dart' show FloatingBottomNavigationItem;

/// Whether a bottom bar should use the floating treatment on this device.
///
/// The floating capsule is intentionally limited to phone-sized portrait
/// layouts. Tablets, desktop windows, and landscape layouts keep their
/// existing bottom-bar geometry so a wide navigation surface is not squeezed
/// into a phone-shaped capsule.
@visibleForTesting
bool floatingBottomBarShouldFloatFor({
  required bool isMobile,
  required double width,
  required double height,
  double maxPhoneShortestSide = 600,
}) {
  final shortestSide = math.min(width, height);
  return isMobile && height > width && shortestSide < maxPhoneShortestSide;
}

/// The runtime device/layout check used by [FloatingBottomBar].
bool floatingBottomBarShouldFloat(BuildContext context) {
  final size = MediaQuery.sizeOf(context);
  return floatingBottomBarShouldFloatFor(
    isMobile: AppPlatform.isMobile,
    width: size.width,
    height: size.height,
  );
}

/// Resolves the compact homepage height for the shared phone navigation bar.
double floatingBottomBarHeightFor(BuildContext context) {
  final bottomInset = MediaQuery.viewPaddingOf(context).bottom;
  return 60.0 + (bottomInset > 0 ? bottomInset * 0.5 : 6.0);
}

/// Resolves the homepage's phone margins for the shared navigation bar.
EdgeInsets floatingBottomBarMarginFor(BuildContext context) {
  final horizontal =
      homeBottomBarHorizontalMarginFor(MediaQuery.sizeOf(context).width);
  return EdgeInsets.fromLTRB(horizontal, 0, horizontal, 24);
}

/// Resolves a compact width for a shared navigation bar.
///
/// Two-item bars otherwise inherit the homepage's three-slot width and leave
/// unusually large empty space on either side of each destination. Keep the
/// homepage margins as the lower bound, while capping the common two-item
/// treatment at the same compact visual width used by the reference bar.
EdgeInsets floatingBottomNavigationMarginFor(
  BuildContext context, {
  required int itemCount,
}) {
  final width = MediaQuery.sizeOf(context).width;
  final homepageMargin = homeBottomBarHorizontalMarginFor(width);
  final maxWidth = itemCount == 2 ? 320.0 : null;
  final widthMargin = maxWidth == null ? 0.0 : (width - maxWidth) / 2;
  final horizontal = math.max(homepageMargin, widthMargin);
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
    if (mobilePortraitOnly && !floatingBottomBarShouldFloat(context)) {
      return child;
    }

    final colorScheme = Theme.of(context).colorScheme;
    final dark = isDark ?? colorScheme.brightness == Brightness.dark;
    final resolvedTint = tint ??
        Color.alphaBlend(
          colorScheme.primary.withValues(alpha: 0.08),
          colorScheme.surface,
        ).withValues(alpha: dark ? 0.24 : 0.32);
    final resolvedHalo = haloColor ?? colorScheme.primary;

    return OptionalLiquidGlassSurface(
      height: height,
      margin: margin,
      borderRadius: borderRadius,
      tint: resolvedTint,
      haloColor: resolvedHalo,
      isDark: dark,
      allowChildOverflow: allowChildOverflow,
      fallback: _FloatingBottomBarFallback(
        height: height,
        margin: margin,
        borderRadius: borderRadius,
        haloColor: resolvedHalo,
        isDark: dark,
        allowChildOverflow: allowChildOverflow,
        child: child,
      ),
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

class _FloatingBottomBarFallback extends StatelessWidget {
  const _FloatingBottomBarFallback({
    required this.height,
    required this.margin,
    required this.borderRadius,
    required this.haloColor,
    required this.isDark,
    required this.allowChildOverflow,
    required this.child,
  });

  final double height;
  final EdgeInsetsGeometry margin;
  final double borderRadius;
  final Color haloColor;
  final bool isDark;
  final bool allowChildOverflow;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final decoration = BoxDecoration(
      color: isDark
          ? colorScheme.surfaceContainerHighest.withValues(alpha: 0.82)
          : colorScheme.surface.withValues(alpha: 0.9),
      borderRadius: BorderRadius.circular(borderRadius),
      border: Border.all(
        color:
            colorScheme.outlineVariant.withValues(alpha: isDark ? 0.42 : 0.54),
        width: 0.8,
      ),
      boxShadow: <BoxShadow>[
        BoxShadow(
          color: haloColor.withValues(alpha: isDark ? 0.12 : 0.2),
          blurRadius: 26,
          spreadRadius: 1,
          offset: const Offset(0, 4),
        ),
        BoxShadow(
          color: colorScheme.shadow.withValues(alpha: 0.12),
          blurRadius: 15,
          offset: const Offset(0, 5),
        ),
      ],
    );

    final content = Stack(
      fit: StackFit.expand,
      clipBehavior: allowChildOverflow ? Clip.none : Clip.hardEdge,
      children: <Widget>[
        // Backdrop blur is deliberately skipped on Android, where a full
        // capsule blur can cause raster jank over a scrolling dashboard.
        if (!AppPlatform.isAndroid)
          ClipRRect(
            borderRadius: BorderRadius.circular(borderRadius),
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 16, sigmaY: 16),
              child: const SizedBox.expand(),
            ),
          ),
        child,
      ],
    );

    return Container(
      height: height,
      margin: margin,
      decoration: decoration,
      child: content,
    );
  }
}
