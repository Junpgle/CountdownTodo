import 'package:flutter/material.dart';

import '../services/liquid_glass_effect_service.dart';

/// Applies a restrained, readable glass material treatment to the stock
/// Material surfaces used throughout the app. Real refraction is supplied by
/// the opt-in glass widgets on prominent shared surfaces; this theme keeps all
/// remaining routes visually consistent without adding a shader per control.
ThemeData applyAppLiquidGlassTheme(
  ThemeData base, {
  required bool enabled,
  LiquidGlassEffectMode mode = LiquidGlassEffectMode.standard,
}) {
  if (!enabled) return base;

  final scheme = base.colorScheme;
  final isDark = scheme.brightness == Brightness.dark;
  final enhanced = mode == LiquidGlassEffectMode.enhanced;
  final surface = scheme.surface.withValues(
    alpha: isDark ? (enhanced ? 0.8 : 0.86) : (enhanced ? 0.84 : 0.9),
  );
  final elevatedSurface = Color.alphaBlend(
    scheme.primary.withValues(
      alpha: isDark ? (enhanced ? 0.13 : 0.08) : (enhanced ? 0.09 : 0.05),
    ),
    scheme.surface,
  ).withValues(
    alpha: isDark ? (enhanced ? 0.84 : 0.9) : (enhanced ? 0.88 : 0.93),
  );
  final quietSurface = Color.alphaBlend(
    scheme.primary.withValues(alpha: enhanced ? 0.1 : 0.05),
    scheme.surfaceContainerLow,
  ).withValues(
    alpha: isDark ? (enhanced ? 0.7 : 0.78) : (enhanced ? 0.76 : 0.84),
  );
  final outline = scheme.outlineVariant.withValues(
    alpha: isDark ? (enhanced ? 0.58 : 0.46) : (enhanced ? 0.68 : 0.58),
  );

  RoundedRectangleBorder rounded(double radius) => RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radius),
        side: BorderSide(color: outline, width: 0.75),
      );

  return base.copyWith(
    appBarTheme: base.appBarTheme.copyWith(
      backgroundColor: surface,
      foregroundColor: scheme.onSurface,
      surfaceTintColor: scheme.primary.withValues(alpha: 0.08),
      shadowColor: scheme.shadow.withValues(alpha: 0.12),
      elevation: 0,
      scrolledUnderElevation: 1,
    ),
    cardTheme: base.cardTheme.copyWith(
      color: quietSurface,
      surfaceTintColor: scheme.primary.withValues(alpha: 0.08),
      shadowColor: scheme.shadow.withValues(alpha: 0.1),
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      shape: rounded(20),
    ),
    dialogTheme: base.dialogTheme.copyWith(
      backgroundColor: elevatedSurface,
      surfaceTintColor: scheme.primary.withValues(alpha: 0.08),
      shadowColor: scheme.shadow.withValues(alpha: 0.22),
      barrierColor: scheme.scrim.withValues(alpha: 0.42),
      elevation: 8,
      clipBehavior: Clip.antiAlias,
      shape: rounded(28),
    ),
    bottomSheetTheme: base.bottomSheetTheme.copyWith(
      backgroundColor: elevatedSurface,
      modalBackgroundColor: elevatedSurface,
      surfaceTintColor: scheme.primary.withValues(alpha: 0.08),
      shadowColor: scheme.shadow.withValues(alpha: 0.2),
      elevation: 4,
      modalElevation: 8,
      clipBehavior: Clip.antiAlias,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
    ),
    drawerTheme: base.drawerTheme.copyWith(
      backgroundColor: elevatedSurface,
      surfaceTintColor: scheme.primary.withValues(alpha: 0.08),
      elevation: 4,
    ),
    navigationBarTheme: base.navigationBarTheme.copyWith(
      backgroundColor: surface,
      surfaceTintColor: scheme.primary.withValues(alpha: 0.08),
      indicatorColor: scheme.primaryContainer.withValues(alpha: 0.76),
      shadowColor: scheme.shadow.withValues(alpha: 0.12),
      elevation: 1,
    ),
    bottomNavigationBarTheme: base.bottomNavigationBarTheme.copyWith(
      backgroundColor: surface,
      elevation: 1,
    ),
    popupMenuTheme: base.popupMenuTheme.copyWith(
      color: elevatedSurface,
      surfaceTintColor: scheme.primary.withValues(alpha: 0.08),
      elevation: 4,
      shape: rounded(18),
    ),
    snackBarTheme: base.snackBarTheme.copyWith(
      backgroundColor: Color.alphaBlend(
        scheme.primary.withValues(alpha: 0.1),
        scheme.inverseSurface,
      ).withValues(alpha: 0.94),
      elevation: 4,
      behavior: SnackBarBehavior.floating,
      shape: rounded(18),
    ),
    floatingActionButtonTheme: base.floatingActionButtonTheme.copyWith(
      backgroundColor: scheme.primaryContainer.withValues(alpha: 0.88),
      foregroundColor: scheme.onPrimaryContainer,
      elevation: 2,
      focusElevation: 3,
      hoverElevation: 3,
      highlightElevation: 1,
      shape: rounded(20),
    ),
    inputDecorationTheme: base.inputDecorationTheme.copyWith(
      filled: true,
      fillColor: quietSurface,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide(color: outline),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide(color: outline),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide(color: scheme.primary, width: 1.5),
      ),
    ),
    chipTheme: base.chipTheme.copyWith(
      backgroundColor: quietSurface,
      selectedColor: scheme.secondaryContainer.withValues(alpha: 0.82),
      side: BorderSide(color: outline),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
  );
}
