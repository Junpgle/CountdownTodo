import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import '../services/liquid_glass_effect_service.dart';

double _clampOpacity(double value) => value.clamp(0.0, 1.0).toDouble();

WidgetStateProperty<Color?> _glassButtonForeground(
  Color base, {
  Color? disabled,
}) {
  return WidgetStateProperty.resolveWith((states) {
    if (states.contains(WidgetState.disabled)) {
      return disabled ?? base.withValues(alpha: 0.38);
    }
    return base;
  });
}

WidgetStateProperty<BorderSide?> _glassButtonSide(
  Color color, {
  required double opacity,
}) {
  return WidgetStateProperty.resolveWith((states) {
    final resolvedOpacity = states.contains(WidgetState.disabled)
        ? opacity * 0.5
        : states.contains(WidgetState.pressed)
            ? opacity + 0.12
            : opacity;
    return BorderSide(
      color: color.withValues(alpha: _clampOpacity(resolvedOpacity)),
      width: 0.8,
    );
  });
}

WidgetStateProperty<Color?> _glassButtonOverlay(Color color) {
  return WidgetStateProperty.resolveWith((states) {
    if (states.contains(WidgetState.pressed)) {
      return color.withValues(alpha: 0.16);
    }
    if (states.contains(WidgetState.hovered) ||
        states.contains(WidgetState.focused)) {
      return color.withValues(alpha: 0.08);
    }
    return Colors.transparent;
  });
}

ButtonLayerBuilder _glassButtonBackgroundBuilder({
  required Color Function(Set<WidgetState> states) tintForStates,
  required double Function(Set<WidgetState> states) opacityForStates,
  required bool isDark,
  required double borderRadius,
  bool circular = false,
}) {
  return (context, states, child) {
    final configuration = LiquidGlassEffectService.configuration;
    final colorScheme = Theme.of(context).colorScheme;
    final tint = tintForStates(states);
    final base = Color.alphaBlend(
      tint.withValues(alpha: isDark ? 0.16 : 0.12),
      isDark ? colorScheme.scrim : colorScheme.surface,
    );
    final opacity = _clampOpacity(opacityForStates(states));
    final backer = base.withValues(alpha: opacity);
    final highlight = (isDark
            ? colorScheme.surfaceBright
            : colorScheme.surfaceContainerHighest)
        .withValues(alpha: isDark ? 0.1 : 0.16);

    return GlassContainer(
      shape: circular
          ? const LiquidOval()
          : LiquidRoundedSuperellipse(borderRadius: borderRadius),
      settings: LiquidGlassSettings(
        glassColor: tint.withValues(alpha: isDark ? 0.12 : 0.1),
        thickness:
            configuration.mode == LiquidGlassEffectMode.enhanced ? 20 : 16,
        blur: configuration.mode == LiquidGlassEffectMode.enhanced ? 12 : 9,
        chromaticAberration: 0.0015,
        lightIntensity: isDark ? 0.48 : 0.58,
        ambientStrength: isDark ? 0.08 : 0.1,
        fresnelStrength: 0.5,
        refractiveIndex: 1.08,
        saturation: 1.0,
        standardOpacityMultiplier: 1.0,
        shadowElevation: 0.35,
        backerColor: backer,
      ),
      useOwnLayer: true,
      quality: GlassQuality.standard,
      clipBehavior: Clip.antiAlias,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: <Color>[
              highlight,
              tint.withValues(alpha: isDark ? 0.04 : 0.06),
            ],
          ),
        ),
        child: child ?? const SizedBox.shrink(),
      ),
    );
  };
}

/// Applies the shared liquid-glass treatment to stock Material surfaces used
/// throughout the app. Standard buttons render their own lightweight glass
/// layer through [ButtonStyle.backgroundBuilder], while prominent shared
/// surfaces continue to use the dedicated glass widgets.
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

  final buttonRadius = BorderRadius.circular(18);
  final glassSurface = scheme.surfaceContainerHighest;
  final glassOutline = scheme.outlineVariant;
  final filledGlassStyle = ButtonStyle(
    backgroundColor: const WidgetStatePropertyAll(Colors.transparent),
    backgroundBuilder: _glassButtonBackgroundBuilder(
      tintForStates: (_) => scheme.primaryContainer,
      opacityForStates: (_) =>
          isDark ? (enhanced ? 0.74 : 0.68) : (enhanced ? 0.84 : 0.78),
      isDark: isDark,
      borderRadius: 18,
    ),
    foregroundColor: _glassButtonForeground(scheme.onPrimaryContainer),
    overlayColor: _glassButtonOverlay(scheme.onPrimaryContainer),
    surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
    shadowColor: const WidgetStatePropertyAll(Colors.transparent),
    elevation: const WidgetStatePropertyAll(0),
    side: _glassButtonSide(
      scheme.onPrimaryContainer,
      opacity: isDark ? 0.26 : 0.34,
    ),
    shape: WidgetStatePropertyAll(
      RoundedRectangleBorder(borderRadius: buttonRadius),
    ),
  );
  final elevatedGlassStyle = ButtonStyle(
    backgroundColor: const WidgetStatePropertyAll(Colors.transparent),
    backgroundBuilder: _glassButtonBackgroundBuilder(
      tintForStates: (_) => glassSurface,
      opacityForStates: (_) =>
          isDark ? (enhanced ? 0.62 : 0.56) : (enhanced ? 0.72 : 0.66),
      isDark: isDark,
      borderRadius: 18,
    ),
    foregroundColor: _glassButtonForeground(scheme.onSurface),
    overlayColor: _glassButtonOverlay(scheme.primary),
    surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
    shadowColor: const WidgetStatePropertyAll(Colors.transparent),
    elevation: const WidgetStatePropertyAll(0),
    side: _glassButtonSide(
      glassOutline,
      opacity: isDark ? 0.4 : 0.52,
    ),
    shape: WidgetStatePropertyAll(
      RoundedRectangleBorder(borderRadius: buttonRadius),
    ),
  );
  final outlinedGlassStyle = ButtonStyle(
    backgroundColor: const WidgetStatePropertyAll(Colors.transparent),
    backgroundBuilder: _glassButtonBackgroundBuilder(
      tintForStates: (_) => glassSurface,
      opacityForStates: (_) => isDark ? 0.24 : 0.2,
      isDark: isDark,
      borderRadius: 18,
    ),
    foregroundColor: _glassButtonForeground(scheme.primary),
    overlayColor: _glassButtonOverlay(scheme.primary),
    surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
    shadowColor: const WidgetStatePropertyAll(Colors.transparent),
    elevation: const WidgetStatePropertyAll(0),
    side: _glassButtonSide(
      scheme.primary,
      opacity: isDark ? 0.42 : 0.5,
    ),
    shape: WidgetStatePropertyAll(
      RoundedRectangleBorder(borderRadius: buttonRadius),
    ),
  );
  final textGlassStyle = ButtonStyle(
    backgroundColor: const WidgetStatePropertyAll(Colors.transparent),
    backgroundBuilder: _glassButtonBackgroundBuilder(
      tintForStates: (_) => glassSurface,
      opacityForStates: (_) => isDark ? 0.18 : 0.14,
      isDark: isDark,
      borderRadius: 16,
    ),
    foregroundColor: _glassButtonForeground(scheme.primary),
    overlayColor: _glassButtonOverlay(scheme.primary),
    surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
    shadowColor: const WidgetStatePropertyAll(Colors.transparent),
    elevation: const WidgetStatePropertyAll(0),
    side: _glassButtonSide(
      glassOutline,
      opacity: isDark ? 0.26 : 0.34,
    ),
    shape: WidgetStatePropertyAll(
      RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
  );
  final iconGlassStyle = ButtonStyle(
    backgroundColor: const WidgetStatePropertyAll(Colors.transparent),
    backgroundBuilder: _glassButtonBackgroundBuilder(
      tintForStates: (_) => glassSurface,
      opacityForStates: (_) =>
          isDark ? (enhanced ? 0.4 : 0.34) : (enhanced ? 0.46 : 0.4),
      isDark: isDark,
      borderRadius: 22,
      circular: true,
    ),
    foregroundColor: _glassButtonForeground(scheme.onSurface),
    overlayColor: _glassButtonOverlay(scheme.primary),
    surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
    shadowColor: const WidgetStatePropertyAll(Colors.transparent),
    elevation: const WidgetStatePropertyAll(0),
    side: _glassButtonSide(
      glassOutline,
      opacity: isDark ? 0.34 : 0.46,
    ),
    shape: const WidgetStatePropertyAll(CircleBorder()),
  );
  final segmentedGlassStyle = ButtonStyle(
    backgroundColor: const WidgetStatePropertyAll(Colors.transparent),
    backgroundBuilder: _glassButtonBackgroundBuilder(
      tintForStates: (states) {
        final selected = states.contains(WidgetState.selected);
        return selected ? scheme.secondaryContainer : glassSurface;
      },
      opacityForStates: (states) {
        final selected = states.contains(WidgetState.selected);
        return selected
            ? (isDark ? (enhanced ? 0.72 : 0.66) : (enhanced ? 0.82 : 0.76))
            : (isDark ? 0.3 : 0.24);
      },
      isDark: isDark,
      borderRadius: 16,
    ),
    foregroundColor: WidgetStateProperty.resolveWith((states) {
      return states.contains(WidgetState.selected)
          ? scheme.onSecondaryContainer
          : scheme.onSurfaceVariant;
    }),
    overlayColor: _glassButtonOverlay(scheme.primary),
    surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
    shadowColor: const WidgetStatePropertyAll(Colors.transparent),
    elevation: const WidgetStatePropertyAll(0),
    side: _glassButtonSide(
      glassOutline,
      opacity: isDark ? 0.38 : 0.5,
    ),
    shape: WidgetStatePropertyAll(
      RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
  );

  RoundedRectangleBorder rounded(double radius) => RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radius),
        side: BorderSide(color: outline, width: 0.75),
      );

  return base.copyWith(
    appBarTheme: base.appBarTheme.copyWith(
      // Keep stock AppBars transparent and elevation-free. The shared
      // FloatingGlassTopBarBackground is supplied at each AppBar callsite
      // because AppBarTheme does not expose a flexibleSpace slot.
      backgroundColor: Colors.transparent,
      foregroundColor: scheme.onSurface,
      surfaceTintColor: Colors.transparent,
      shadowColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(24)),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: elevatedGlassStyle.merge(base.elevatedButtonTheme.style),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: filledGlassStyle.merge(base.filledButtonTheme.style),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: outlinedGlassStyle.merge(base.outlinedButtonTheme.style),
    ),
    textButtonTheme: TextButtonThemeData(
      style: textGlassStyle.merge(base.textButtonTheme.style),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: iconGlassStyle.merge(base.iconButtonTheme.style),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: segmentedGlassStyle.merge(base.segmentedButtonTheme.style),
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
