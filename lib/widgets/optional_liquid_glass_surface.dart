import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import '../services/liquid_glass_effect_service.dart';

@visibleForTesting
GlassQuality liquidGlassPanelQualityFor(LiquidGlassEffectMode mode) {
  return mode == LiquidGlassEffectMode.enhanced
      ? GlassQuality.standard
      : GlassQuality.minimal;
}

@visibleForTesting
GlassQuality liquidGlassSurfaceQualityFor(LiquidGlassEffectMode mode) {
  return mode == LiquidGlassEffectMode.enhanced
      ? GlassQuality.premium
      : GlassQuality.standard;
}

@visibleForTesting
double liquidGlassPanelBackerOpacityFor(
  LiquidGlassEffectMode mode, {
  required bool isDark,
}) {
  final enhanced = mode == LiquidGlassEffectMode.enhanced;
  // White foreground content over photography needs a neutral dark dim rather
  // than an opaque light veil. Keep the light treatment stronger because dark
  // foreground content needs more separation from a busy backdrop.
  return isDark ? (enhanced ? 0.35 : 0.28) : (enhanced ? 0.58 : 0.52);
}

@visibleForTesting
double liquidGlassAdaptiveStaticOpacityFor({required bool isDark}) {
  return isDark ? 0.34 : 0.72;
}

@visibleForTesting
double liquidGlassSurfaceBackerOpacityFor(
  LiquidGlassEffectMode mode, {
  required bool isDark,
}) {
  final enhanced = mode == LiquidGlassEffectMode.enhanced;
  return isDark ? (enhanced ? 0.56 : 0.5) : (enhanced ? 0.64 : 0.58);
}

/// Rendering strategy for content-sized, potentially repeated glass panels.
enum OptionalLiquidGlassPanelMode {
  /// A single shader-free frosted layer with live backdrop blur.
  frosted,

  /// A card that follows the user's quality preference.
  ///
  /// Standard mode uses a non-sampling translucent material. Enhanced mode
  /// promotes the card to the package's standard real-time glass shader.
  adaptiveRepeated,

  /// A translucent material treatment without backdrop sampling.
  ///
  /// Use this for repeated cards in scroll views. Multiple backdrop filters
  /// compound quickly on Android GPUs even when each filter is inexpensive.
  staticMaterial,
}

/// A content-sized glass panel for shared cards, drawers, and compact controls.
///
/// Single prominent panels use the package's shader-free frosted tier. Repeated
/// cards can opt into [OptionalLiquidGlassPanelMode.adaptiveRepeated] to follow
/// the user-selected quality without forcing an expensive filter in standard
/// mode. Prominent static surfaces such as the bottom navigation bar use the
/// dedicated component below. The fallback is returned unchanged when the
/// global effect is disabled.
class OptionalLiquidGlassPanel extends StatelessWidget {
  const OptionalLiquidGlassPanel({
    super.key,
    required this.child,
    required this.fallback,
    this.width,
    this.height,
    this.padding,
    this.margin,
    this.borderRadius = 20,
    this.circular = false,
    this.tint,
    this.isDark,
    this.clipBehavior = Clip.antiAlias,
    this.mode = OptionalLiquidGlassPanelMode.frosted,
  });

  final Widget child;
  final Widget fallback;
  final double? width;
  final double? height;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final double borderRadius;
  final bool circular;
  final Color? tint;
  final bool? isDark;
  final Clip clipBehavior;
  final OptionalLiquidGlassPanelMode mode;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<LiquidGlassEffectConfiguration>(
      valueListenable: LiquidGlassEffectService.configurationListenable,
      builder: (context, configuration, _) {
        if (!configuration.enabled) return fallback;

        final colorScheme = Theme.of(context).colorScheme;
        final dark = isDark ?? colorScheme.brightness == Brightness.dark;
        final enhanced = configuration.mode == LiquidGlassEffectMode.enhanced;
        final tintSource = tint ?? colorScheme.primary;
        final neutralBase = dark ? colorScheme.scrim : colorScheme.surface;
        final resolvedTint = Color.alphaBlend(
          tintSource.withValues(
            alpha: tint == null ? 0.06 : (dark ? 0.12 : 0.1),
          ),
          neutralBase,
        ).withValues(alpha: dark ? 0.24 : 0.3);

        final useStaticMaterial =
            mode == OptionalLiquidGlassPanelMode.staticMaterial ||
                (mode == OptionalLiquidGlassPanelMode.adaptiveRepeated &&
                    !enhanced);
        if (useStaticMaterial) {
          final isAdaptiveCard =
              mode == OptionalLiquidGlassPanelMode.adaptiveRepeated;
          final materialOpacity = isAdaptiveCard
              ? liquidGlassAdaptiveStaticOpacityFor(isDark: dark)
              : (dark ? 0.86 : 0.9);
          final baseColor = Color.alphaBlend(
            resolvedTint.withValues(alpha: dark ? 0.18 : 0.12),
            neutralBase,
          ).withValues(alpha: materialOpacity);
          final highlightBase = dark
              ? colorScheme.surfaceBright
              : colorScheme.surfaceContainerHighest;
          final highlightColor = Color.alphaBlend(
            highlightBase.withValues(alpha: dark ? 0.1 : 0.16),
            baseColor.withValues(alpha: 1),
          ).withValues(
            alpha: (materialOpacity + (dark ? 0.05 : 0.04))
                .clamp(0.0, 1.0)
                .toDouble(),
          );
          final decoration = BoxDecoration(
            shape: circular ? BoxShape.circle : BoxShape.rectangle,
            borderRadius: circular ? null : BorderRadius.circular(borderRadius),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: <Color>[highlightColor, baseColor],
            ),
            border: Border.all(
              color: (dark
                      ? colorScheme.surfaceBright
                      : colorScheme.outlineVariant)
                  .withValues(alpha: dark ? 0.28 : 0.62),
              width: 0.8,
            ),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: colorScheme.shadow.withValues(alpha: dark ? 0.1 : 0.07),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          );

          return Container(
            key: const ValueKey<String>('optional-liquid-glass-static-panel'),
            width: width,
            height: height,
            padding: padding,
            margin: margin,
            clipBehavior: clipBehavior,
            decoration: decoration,
            child: child,
          );
        }

        return RepaintBoundary(
          child: GlassContainer(
            width: width,
            height: height,
            padding: padding,
            margin: margin,
            shape: circular
                ? const LiquidOval()
                : LiquidRoundedSuperellipse(borderRadius: borderRadius),
            settings: LiquidGlassSettings(
              glassColor: resolvedTint,
              thickness: enhanced ? 24 : 18,
              blur: enhanced ? 16 : 12,
              chromaticAberration: enhanced ? 0.008 : 0.004,
              lightIntensity:
                  enhanced ? (dark ? 0.72 : 0.6) : (dark ? 0.58 : 0.46),
              ambientStrength:
                  enhanced ? (dark ? 0.22 : 0.16) : (dark ? 0.16 : 0.1),
              fresnelStrength: enhanced ? 0.94 : 0.78,
              refractiveIndex: enhanced ? 1.2 : 1.12,
              saturation: enhanced ? 1.06 : 0.95,
              standardOpacityMultiplier: dark ? 0.62 : 0.5,
              shadowElevation: enhanced ? 1.4 : 0.8,
              backerColor: resolvedTint.withValues(
                alpha: liquidGlassPanelBackerOpacityFor(
                  configuration.mode,
                  isDark: dark,
                ),
              ),
            ),
            useOwnLayer: true,
            quality: liquidGlassPanelQualityFor(configuration.mode),
            clipBehavior: clipBehavior,
            child: child,
          ),
        );
      },
    );
  }
}

/// Uses the Liquid Glass renderer only when the user has enabled it, otherwise
/// returning the caller's existing platform-aware implementation unchanged.
class OptionalLiquidGlassSurface extends StatelessWidget {
  const OptionalLiquidGlassSurface({
    super.key,
    required this.child,
    required this.fallback,
    required this.height,
    required this.margin,
    required this.borderRadius,
    required this.tint,
    required this.isDark,
  });

  final Widget child;
  final Widget fallback;
  final double height;
  final EdgeInsetsGeometry margin;
  final double borderRadius;
  final Color tint;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<LiquidGlassEffectConfiguration>(
      valueListenable: LiquidGlassEffectService.configurationListenable,
      builder: (context, configuration, _) {
        if (!configuration.enabled) return fallback;
        final enhanced = configuration.mode == LiquidGlassEffectMode.enhanced;

        // GlassContainer's standard-quality path does not currently honor
        // useOwnLayer with an explicit RepaintBoundary. Isolate it here so an
        // ancestor route FadeTransition cannot distribute opacity into the
        // runtime shader, which trips Impeller's SetInheritedOpacity
        // validation and can render the transition with the wrong alpha.
        return RepaintBoundary(
          child: GlassContainer(
            height: height,
            margin: margin,
            shape: LiquidRoundedSuperellipse(borderRadius: borderRadius),
            settings: LiquidGlassSettings(
              glassColor: tint,
              thickness: enhanced ? 28 : 20,
              blur: enhanced ? 18 : 12,
              chromaticAberration: enhanced ? 0.012 : 0.006,
              lightIntensity:
                  enhanced ? (isDark ? 0.8 : 0.68) : (isDark ? 0.62 : 0.48),
              ambientStrength:
                  enhanced ? (isDark ? 0.26 : 0.18) : (isDark ? 0.18 : 0.1),
              fresnelStrength: enhanced ? 1.0 : 0.85,
              refractiveIndex: enhanced ? 1.24 : 1.14,
              saturation: enhanced ? 1.08 : 0.95,
              shadowElevation: enhanced ? 1.8 : 1.0,
              // Keep the refraction, but place a stronger neutral pad behind
              // it so busy wallpapers cannot compete with tab labels/icons.
              backerColor: tint.withValues(
                alpha: liquidGlassSurfaceBackerOpacityFor(
                  configuration.mode,
                  isDark: isDark,
                ),
              ),
            ),
            useOwnLayer: true,
            quality: liquidGlassSurfaceQualityFor(configuration.mode),
            clipBehavior: Clip.antiAlias,
            child: child,
          ),
        );
      },
    );
  }
}

/// Drop-in card shell that preserves the original decoration while the effect
/// is disabled, then follows the user's standard/enhanced glass preference.
class OptionalLiquidGlassCard extends StatelessWidget {
  const OptionalLiquidGlassCard({
    super.key,
    required this.child,
    required this.fallbackDecoration,
    this.width,
    this.height,
    this.padding,
    this.margin,
    this.alignment,
    this.constraints,
    this.borderRadius = 20,
    this.tint,
    this.isDark,
    this.clipBehavior = Clip.antiAlias,
  });

  final Widget child;
  final Decoration fallbackDecoration;
  final double? width;
  final double? height;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final AlignmentGeometry? alignment;
  final BoxConstraints? constraints;
  final double borderRadius;
  final Color? tint;
  final bool? isDark;
  final Clip clipBehavior;

  @override
  Widget build(BuildContext context) {
    final content = alignment == null
        ? child
        : Align(
            alignment: alignment!,
            child: child,
          );
    final fallback = Container(
      width: width,
      height: height,
      padding: padding,
      margin: margin,
      alignment: alignment,
      constraints: constraints,
      clipBehavior: clipBehavior,
      decoration: fallbackDecoration,
      child: child,
    );
    Widget result = OptionalLiquidGlassPanel(
      width: width,
      height: height,
      padding: padding,
      margin: margin,
      borderRadius: borderRadius,
      tint: tint,
      isDark: isDark,
      clipBehavior: clipBehavior,
      mode: OptionalLiquidGlassPanelMode.adaptiveRepeated,
      fallback: fallback,
      child: content,
    );
    if (constraints != null) {
      result = ConstrainedBox(constraints: constraints!, child: result);
    }
    return result;
  }
}
