import 'package:flutter/material.dart';

import 'floating_glass_control.dart';

/// A home-screen quick action backed by the shared draggable Liquid Glass FAB.
/// Callers can opt out with [useLiquidGlass] when a native FAB is required.
class HomeQuickActionButton extends StatelessWidget {
  const HomeQuickActionButton.compact({
    super.key,
    required this.heroTag,
    required this.onPressed,
    required this.tooltip,
    required this.tint,
    required this.foregroundColor,
    required this.isDark,
    this.useLiquidGlass = true,
    required Widget child,
  })  : _extended = false,
        _compactChild = child,
        icon = null,
        label = null;

  const HomeQuickActionButton.extended({
    super.key,
    required this.heroTag,
    required this.onPressed,
    required this.tooltip,
    required this.tint,
    required this.foregroundColor,
    required this.isDark,
    this.useLiquidGlass = true,
    required this.icon,
    required this.label,
  })  : _extended = true,
        _compactChild = null;

  final Object heroTag;
  final VoidCallback onPressed;
  final String tooltip;
  final Color tint;
  final Color foregroundColor;
  final bool isDark;
  final bool useLiquidGlass;
  final bool _extended;
  final Widget? _compactChild;
  final Widget? icon;
  final Widget? label;

  @override
  Widget build(BuildContext context) {
    final fallback = _extended
        ? FloatingActionButton.extended(
            heroTag: heroTag,
            onPressed: onPressed,
            tooltip: tooltip,
            icon: icon!,
            label: label!,
          )
        : FloatingActionButton.small(
            heroTag: heroTag,
            onPressed: onPressed,
            tooltip: tooltip,
            child: _compactChild,
          );

    if (!useLiquidGlass) return fallback;

    return _extended
        ? FloatingGlassActionButton.extended(
            heroTag: heroTag,
            onPressed: onPressed,
            tooltip: tooltip,
            backgroundColor: tint,
            foregroundColor: foregroundColor,
            icon: icon!,
            label: label!,
          )
        : FloatingGlassActionButton.small(
            heroTag: heroTag,
            onPressed: onPressed,
            tooltip: tooltip,
            backgroundColor: tint,
            foregroundColor: foregroundColor,
            child: _compactChild,
          );
  }
}
