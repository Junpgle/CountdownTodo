import 'package:flutter/material.dart';

/// Applies the app-wide dark surface palette for OLED black mode.
///
/// The generated scheme's accent colors remain intact while Material surfaces
/// move between pure black and softened charcoal tones.
ColorScheme withOledBlackSurfacePalette(
  ColorScheme scheme, {
  required bool enabled,
}) {
  if (scheme.brightness != Brightness.dark) return scheme;

  return scheme.copyWith(
    surface: enabled ? const Color(0xFF000000) : const Color(0xFF121212),
    surfaceDim: enabled ? const Color(0xFF000000) : const Color(0xFF101010),
    surfaceBright: enabled ? const Color(0xFF242424) : const Color(0xFF323232),
    surfaceContainerLowest: enabled
        ? const Color(0xFF000000)
        : const Color(0xFF0D0D0D),
    surfaceContainerLow: enabled
        ? const Color(0xFF0A0A0A)
        : const Color(0xFF171717),
    surfaceContainer: enabled
        ? const Color(0xFF101010)
        : const Color(0xFF1D1D1D),
    surfaceContainerHigh: enabled
        ? const Color(0xFF171717)
        : const Color(0xFF242424),
    surfaceContainerHighest: enabled
        ? const Color(0xFF1E1E1E)
        : const Color(0xFF2B2B2B),
  );
}
