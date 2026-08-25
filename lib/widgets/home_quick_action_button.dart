import 'package:flutter/material.dart';

import 'optional_liquid_glass_surface.dart';

/// A home-screen quick action that preserves the stock FAB while Liquid Glass
/// is disabled and swaps only its visual shell when the effect is enabled.
class HomeQuickActionButton extends StatelessWidget {
  const HomeQuickActionButton.compact({
    super.key,
    required this.heroTag,
    required this.onPressed,
    required this.tooltip,
    required this.tint,
    required this.foregroundColor,
    required this.isDark,
    required Widget child,
  })  : _extended = false,
        _compactChild = child,
        _icon = null,
        _label = null;

  const HomeQuickActionButton.extended({
    super.key,
    required this.heroTag,
    required this.onPressed,
    required this.tooltip,
    required this.tint,
    required this.foregroundColor,
    required this.isDark,
    required Widget icon,
    required Widget label,
  })  : _extended = true,
        _compactChild = null,
        _icon = icon,
        _label = label;

  final Object heroTag;
  final VoidCallback onPressed;
  final String tooltip;
  final Color tint;
  final Color foregroundColor;
  final bool isDark;
  final bool _extended;
  final Widget? _compactChild;
  final Widget? _icon;
  final Widget? _label;

  @override
  Widget build(BuildContext context) {
    final fallback = _extended
        ? FloatingActionButton.extended(
            heroTag: heroTag,
            onPressed: onPressed,
            tooltip: tooltip,
            icon: _icon!,
            label: _label!,
          )
        : FloatingActionButton.small(
            heroTag: heroTag,
            onPressed: onPressed,
            tooltip: tooltip,
            child: _compactChild,
          );

    final borderRadius = _extended ? 16.0 : 20.0;
    final glassContent = Tooltip(
      message: tooltip,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(borderRadius),
          child: _extended
              ? SizedBox(
                  height: 56,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        IconTheme(
                          data: IconThemeData(
                            color: foregroundColor,
                            size: 24,
                          ),
                          child: _icon!,
                        ),
                        const SizedBox(width: 8),
                        DefaultTextStyle(
                          style:
                              Theme.of(context).textTheme.labelLarge!.copyWith(
                                    color: foregroundColor,
                                    fontWeight: FontWeight.w600,
                                  ),
                          child: _label!,
                        ),
                      ],
                    ),
                  ),
                )
              : SizedBox(
                  width: 40,
                  height: 40,
                  child: Center(child: _compactChild),
                ),
        ),
      ),
    );

    return OptionalLiquidGlassPanel(
      borderRadius: borderRadius,
      circular: !_extended,
      tint: tint.withValues(alpha: 0.18),
      isDark: isDark,
      fallback: fallback,
      child: glassContent,
    );
  }
}
