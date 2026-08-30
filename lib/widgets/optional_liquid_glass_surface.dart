import 'dart:ui' as ui;

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
double liquidGlassHighContrastStaticOpacityFor({required bool isDark}) {
  // Dense-content surfaces (folders, lists) need a stronger fill than chip-like
  // adaptive cards, while still staying translucent enough to read as glass.
  return isDark ? 0.8 : 0.88;
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

@visibleForTesting
bool liquidGlassUsesGroupedBackdropFor(
  LiquidGlassEffectMode effectMode,
  OptionalLiquidGlassPanelMode panelMode,
) {
  return effectMode == LiquidGlassEffectMode.enhanced &&
      panelMode == OptionalLiquidGlassPanelMode.adaptiveRepeated;
}

/// Whether every corner of [radius] shares the same circular value, which is
/// the only per-corner-free shape the superellipse clip renders faithfully.
bool _hasUniformRadius(BorderRadiusGeometry radius) {
  if (radius is! BorderRadius) return false;
  final value = radius.topLeft.x;
  return radius.topLeft.y == value &&
      radius.topRight.x == value &&
      radius.topRight.y == value &&
      radius.bottomLeft.x == value &&
      radius.bottomLeft.y == value &&
      radius.bottomRight.x == value &&
      radius.bottomRight.y == value;
}

/// Isolates a glass-heavy scrollable and provides one shared backdrop group.
///
/// Descendant cards and panels keep their live glass treatment at all times;
/// any grouped backdrop filters in the subtree share the engine's single
/// backdrop input instead of creating independent captures.
class OptionalLiquidGlassScrollOptimizer extends StatelessWidget {
  const OptionalLiquidGlassScrollOptimizer({
    super.key,
    required this.child,
  });

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return BackdropGroup(child: child);
  }
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
    this.borderRadiusGeometry,
    this.circular = false,
    this.highContrast = false,
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

  /// Per-corner override for shapes the uniform [borderRadius] cannot express
  /// (e.g. a card whose top corners are rounded but bottom corners square so
  /// it merges flush into an attached sheet). Supported by the static
  /// material and grouped backdrop tiers; the frosted GlassContainer tier
  /// falls back to the uniform radius.
  final BorderRadiusGeometry? borderRadiusGeometry;
  final bool circular;

  /// Boosts the fill opacity so dense text stays legible over busy backdrops
  /// while the blur and tint still read as glass. Use for content-bearing
  /// surfaces (folders, lists), not for chips or decorative panels.
  final bool highContrast;
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
        // Per-corner radii are only expressible by the tiers that clip with
        // BorderRadius; the superellipse shader shape needs a uniform radius.
        final resolvedRadius =
            borderRadiusGeometry ?? BorderRadius.circular(borderRadius);
        final hasUniformRadius = !circular && _hasUniformRadius(resolvedRadius);
        if (useStaticMaterial) {
          final isAdaptiveCard =
              mode == OptionalLiquidGlassPanelMode.adaptiveRepeated;
          final materialOpacity = isAdaptiveCard
              ? (highContrast
                  ? liquidGlassHighContrastStaticOpacityFor(isDark: dark)
                  : liquidGlassAdaptiveStaticOpacityFor(isDark: dark))
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
            borderRadius: circular ? null : resolvedRadius,
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

        if (liquidGlassUsesGroupedBackdropFor(configuration.mode, mode)) {
          // Flutter can batch sibling backdrop filters carrying the same
          // BackdropKey into one blur operation. This keeps a real, live
          // frosted background throughout a 120 Hz scroll gesture without
          // paying one offscreen blur + fragment shader pass per visible card.
          final baseColor = Color.alphaBlend(
            resolvedTint.withValues(alpha: dark ? 0.2 : 0.14),
            neutralBase,
          ).withValues(
            alpha: highContrast ? (dark ? 0.5 : 0.6) : (dark ? 0.32 : 0.44),
          );
          final highlightBase = dark
              ? colorScheme.surfaceBright
              : colorScheme.surfaceContainerHighest;
          final highlightColor = Color.alphaBlend(
            highlightBase.withValues(alpha: dark ? 0.12 : 0.18),
            baseColor.withValues(alpha: 1),
          ).withValues(
            alpha: highContrast ? (dark ? 0.56 : 0.68) : (dark ? 0.38 : 0.5),
          );
          final decoration = BoxDecoration(
            shape: circular ? BoxShape.circle : BoxShape.rectangle,
            borderRadius: circular ? null : resolvedRadius,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: <Color>[highlightColor, baseColor],
            ),
            border: Border.all(
              color: (dark
                      ? colorScheme.surfaceBright
                      : colorScheme.outlineVariant)
                  .withValues(alpha: dark ? 0.42 : 0.58),
              width: 0.8,
            ),
          );
          final filtered = BackdropFilter.grouped(
            filter: ui.ImageFilter.blur(
              sigmaX: 9,
              sigmaY: 9,
              tileMode: TileMode.clamp,
            ),
            child: Container(
              key: const ValueKey<String>(
                'optional-liquid-glass-grouped-panel',
              ),
              width: width,
              height: height,
              padding: padding,
              decoration: decoration,
              child: child,
            ),
          );
          // ClipRSuperellipse only renders uniform radii faithfully; per-corner
          // shapes fall back to an anti-aliased rounded rect.
          final clipped = circular
              ? ClipOval(clipBehavior: clipBehavior, child: filtered)
              : hasUniformRadius
                  ? ClipRSuperellipse(
                      borderRadius: resolvedRadius as BorderRadius,
                      clipBehavior: clipBehavior,
                      child: filtered,
                    )
                  : ClipRRect(
                      borderRadius: resolvedRadius,
                      clipBehavior: clipBehavior,
                      child: filtered,
                    );
          return Container(margin: margin, child: clipped);
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
///
/// Enhanced mode pins the prominent surface (floating bottom bar) to a single,
/// consistent live frosted-glass rendering: one real-time backdrop blur with a
/// specular white rim. This avoids the premium pipeline's per-frame backdrop
/// texture recapture while content scrolls beneath the bar — the dominant
/// raster cost of a scrolling glass dashboard, and prone to desync that made
/// the glass appear to vanish mid-fling — while keeping the same glassy read
/// in every frame. Standard mode keeps the lightweight shader container.
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
    this.haloColor,
    this.haloOpacity,
    this.backerOpacity,
    this.useTopBarGlass = false,
    this.allowChildOverflow = false,
  });

  final Widget child;
  final Widget fallback;
  final double height;
  final EdgeInsetsGeometry margin;
  final double borderRadius;
  final Color tint;
  final bool isDark;
  final Color? haloColor;

  /// Scales the outer colored halo without changing the glass fill. Top-bar
  /// controls use a restrained value so their material follows the page
  /// surface instead of leaving a detached shadow stain behind.
  final double? haloOpacity;

  /// Optional opacity for the neutral pad behind the glass. Small controls
  /// can use a lighter pad so the backdrop remains visible through the lens.
  final double? backerOpacity;

  /// Uses the low-distortion, page-derived liquid-glass recipe reserved for
  /// small top-bar controls. It still renders through [GlassContainer]; this
  /// only changes the shader settings so a small lens does not become a gray
  /// disk over dark text.
  final bool useTopBarGlass;

  /// Paints [child] above the clipped glass shell so elevated controls can
  /// extend beyond the surface without losing their shadow or refraction rim.
  final bool allowChildOverflow;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<LiquidGlassEffectConfiguration>(
      valueListenable: LiquidGlassEffectService.configurationListenable,
      builder: (context, configuration, _) {
        if (!configuration.enabled) return fallback;
        final enhanced = configuration.mode == LiquidGlassEffectMode.enhanced;

        if (useTopBarGlass) {
          return _TopBarLiquidGlassSurface(
            height: height,
            margin: margin,
            borderRadius: borderRadius,
            tint: tint,
            haloColor: haloColor,
            haloOpacity: haloOpacity,
            isDark: isDark,
            backerOpacity: backerOpacity,
            allowChildOverflow: allowChildOverflow,
            child: child,
          );
        }

        // One consistent frosted-glass treatment: a single live backdrop blur
        // samples the moving backdrop every frame without the premium
        // pipeline's texture capture, so scrolling stays smooth and the glass
        // never flickers away.
        if (enhanced) {
          return _FrostedGlassSurface(
            height: height,
            margin: margin,
            borderRadius: borderRadius,
            tint: tint,
            haloColor: haloColor,
            haloOpacity: haloOpacity,
            isDark: isDark,
            backerOpacity: backerOpacity,
            allowChildOverflow: allowChildOverflow,
            child: child,
          );
        }

        // GlassContainer's standard-quality path does not currently honor
        // useOwnLayer with an explicit RepaintBoundary. Isolate it here so an
        // ancestor route FadeTransition cannot distribute opacity into the
        // runtime shader, which trips Impeller's SetInheritedOpacity
        // validation and can render the transition with the wrong alpha.
        final glassShell = GlassContainer(
          height: height,
          shape: LiquidRoundedSuperellipse(borderRadius: borderRadius),
          settings: LiquidGlassSettings(
            glassColor: tint,
            thickness: 20,
            blur: 12,
            chromaticAberration: 0.006,
            lightIntensity: isDark ? 0.62 : 0.48,
            ambientStrength: isDark ? 0.18 : 0.1,
            fresnelStrength: 0.85,
            refractiveIndex: 1.14,
            saturation: 0.95,
            shadowElevation: 1.0,
            // Keep the refraction, but place a stronger neutral pad behind it
            // so busy wallpapers cannot compete with tab labels/icons.
            backerColor: tint.withValues(
              alpha: (backerOpacity ??
                      liquidGlassSurfaceBackerOpacityFor(
                        configuration.mode,
                        isDark: isDark,
                      ))
                  .clamp(0.0, 1.0)
                  .toDouble(),
            ),
          ),
          useOwnLayer: true,
          quality: liquidGlassSurfaceQualityFor(configuration.mode),
          clipBehavior: Clip.antiAlias,
          child: allowChildOverflow ? const SizedBox.expand() : child,
        );

        return RepaintBoundary(
          child: Container(
            height: height,
            margin: margin,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(borderRadius),
              boxShadow: _surfaceHaloShadows(
                haloColor: haloColor ?? tint,
                shadowColor: Theme.of(context).colorScheme.shadow,
                isDark: isDark,
                haloOpacity: haloOpacity,
              ),
            ),
            child: allowChildOverflow
                ? Stack(
                    fit: StackFit.expand,
                    clipBehavior: Clip.none,
                    children: <Widget>[glassShell, child],
                  )
                : glassShell,
          ),
        );
      },
    );
  }
}

/// A small, page-derived liquid-glass lens for top-bar controls.
///
/// Top-bar controls remain inside a scrolling route, so they intentionally use
/// the package's standard real-time shader instead of the premium texture
/// capture. This is still the actual Liquid Glass renderer; the recipe simply
/// uses a lighter tint, lower refraction, and a restrained backer so the lens
/// inherits the page rather than becoming a detached gray circle.
class _TopBarLiquidGlassSurface extends StatelessWidget {
  const _TopBarLiquidGlassSurface({
    required this.height,
    required this.margin,
    required this.borderRadius,
    required this.tint,
    required this.haloColor,
    required this.haloOpacity,
    required this.isDark,
    required this.backerOpacity,
    required this.allowChildOverflow,
    required this.child,
  });

  final double height;
  final EdgeInsetsGeometry margin;
  final double borderRadius;
  final Color tint;
  final Color? haloColor;
  final double? haloOpacity;
  final bool isDark;
  final double? backerOpacity;
  final bool allowChildOverflow;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final pageBase = isDark
        ? colorScheme.surfaceContainerHigh
        : colorScheme.surfaceContainerLow;
    final pageTint = Color.alphaBlend(
      tint.withValues(alpha: isDark ? 0.16 : 0.1),
      pageBase,
    );
    final glassColor = pageTint.withValues(alpha: isDark ? 0.14 : 0.1);
    final effectiveBackerOpacity =
        (backerOpacity ?? (isDark ? 0.34 : 0.42)).clamp(0.0, 1.0).toDouble();
    final backerColor = pageTint.withValues(alpha: effectiveBackerOpacity);
    final glassShell = GlassContainer(
      height: height,
      shape: LiquidOval(),
      settings: LiquidGlassSettings(
        glassColor: glassColor,
        thickness: isDark ? 12 : 10,
        blur: isDark ? 6 : 5,
        chromaticAberration: 0.0015,
        lightIntensity: isDark ? 0.46 : 0.64,
        ambientStrength: isDark ? 0.08 : 0.11,
        ambientRim: 0.04,
        fresnelStrength: 0.48,
        refractiveIndex: 1.08,
        saturation: 1.02,
        standardOpacityMultiplier: 1.0,
        shadowElevation: 0.22,
        whitenStrength: isDark ? 0.04 : 0.06,
        backerColor: backerColor,
      ),
      useOwnLayer: true,
      // The top bar moves with a scrollable route. Standard is the package's
      // lightweight real-time Liquid Glass shader and remains stable here;
      // premium texture capture is reserved for static showcase surfaces.
      quality: GlassQuality.standard,
      clipBehavior: Clip.antiAlias,
      child: allowChildOverflow ? const SizedBox.expand() : child,
    );

    return RepaintBoundary(
      child: Container(
        height: height,
        margin: margin,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(borderRadius),
          boxShadow: _surfaceHaloShadows(
            haloColor: haloColor ?? tint,
            shadowColor: colorScheme.shadow,
            isDark: isDark,
            haloOpacity: haloOpacity,
          ),
        ),
        child: allowChildOverflow
            ? Stack(
                fit: StackFit.expand,
                clipBehavior: Clip.none,
                children: <Widget>[glassShell, child],
              )
            : glassShell,
      ),
    );
  }
}

/// Live blurred-glass treatment for the prominent surface. A single
/// [BackdropFilter] samples the backdrop every frame — far cheaper than the
/// premium pipeline's texture capture and immune to its mid-scroll desync —
/// while the white specular rim and tint gradient keep a strong frosted-glass
/// read over any wallpaper.
class _FrostedGlassSurface extends StatelessWidget {
  const _FrostedGlassSurface({
    required this.height,
    required this.margin,
    required this.borderRadius,
    required this.tint,
    required this.haloColor,
    required this.haloOpacity,
    required this.isDark,
    required this.backerOpacity,
    required this.allowChildOverflow,
    required this.child,
  });

  final double height;
  final EdgeInsetsGeometry margin;
  final double borderRadius;
  final Color tint;
  final Color? haloColor;
  final double? haloOpacity;
  final bool isDark;
  final double? backerOpacity;
  final bool allowChildOverflow;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final neutralBase = isDark ? colorScheme.scrim : colorScheme.surface;
    final baseAlpha =
        (backerOpacity ?? (isDark ? 0.34 : 0.46)).clamp(0.0, 1.0).toDouble();
    final baseColor = Color.alphaBlend(
      tint.withValues(alpha: isDark ? 0.2 : 0.14),
      neutralBase,
    ).withValues(alpha: baseAlpha);
    final highlightBase = isDark
        ? colorScheme.surfaceBright
        : colorScheme.surfaceContainerHighest;
    final highlightColor = Color.alphaBlend(
      highlightBase.withValues(alpha: isDark ? 0.12 : 0.18),
      baseColor.withValues(alpha: 1),
    ).withValues(alpha: isDark ? 0.4 : 0.52);

    final clippedSurface = ClipRSuperellipse(
      borderRadius: BorderRadius.circular(borderRadius),
      clipBehavior: Clip.antiAlias,
      child: BackdropFilter.grouped(
        filter: ui.ImageFilter.blur(
          sigmaX: 16,
          sigmaY: 16,
          tileMode: TileMode.clamp,
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: <Color>[highlightColor, baseColor],
            ),
            border: Border.all(
              color: Colors.white.withValues(
                alpha: isDark ? 0.4 : 0.62,
              ),
              width: 1,
            ),
          ),
          child: allowChildOverflow ? const SizedBox.expand() : child,
        ),
      ),
    );

    return RepaintBoundary(
      child: Padding(
        padding: margin,
        child: SizedBox(
          height: height,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(borderRadius),
              boxShadow: _surfaceHaloShadows(
                haloColor: haloColor ?? tint,
                shadowColor: colorScheme.shadow,
                isDark: isDark,
                haloOpacity: haloOpacity,
              ),
            ),
            child: allowChildOverflow
                ? Stack(
                    fit: StackFit.expand,
                    clipBehavior: Clip.none,
                    children: <Widget>[clippedSurface, child],
                  )
                : clippedSurface,
          ),
        ),
      ),
    );
  }
}

List<BoxShadow> _surfaceHaloShadows({
  required Color haloColor,
  required Color shadowColor,
  required bool isDark,
  double? haloOpacity,
}) {
  final opacity = (haloOpacity ?? 1.0).clamp(0.0, 1.0).toDouble();
  return [
    BoxShadow(
      color: haloColor.withValues(
        alpha: (isDark ? 0.16 : 0.22) * opacity,
      ),
      blurRadius: 26,
      spreadRadius: 1,
      offset: const Offset(0, 4),
    ),
    BoxShadow(
      color: shadowColor.withValues(
        alpha: (isDark ? 0.2 : 0.08) * opacity,
      ),
      blurRadius: 14,
      offset: const Offset(0, 5),
    ),
  ];
}

/// Rounded-top content shell for self-drawn bottom sheets.
///
/// Sheets that draw their own container inside a transparent
/// [showModalBottomSheet] bypass the themed bottom-sheet surface entirely;
/// this shell gives them the same adaptive liquid-glass treatment as cards
/// while the fallback keeps the caller's original decoration when the effect
/// is disabled.
class OptionalLiquidGlassSheet extends StatelessWidget {
  const OptionalLiquidGlassSheet({
    super.key,
    required this.child,
    required this.fallbackDecoration,
    this.topRadius = 24,
    this.padding,
  });

  final Widget child;
  final Decoration fallbackDecoration;
  final double topRadius;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return OptionalLiquidGlassPanel(
      mode: OptionalLiquidGlassPanelMode.adaptiveRepeated,
      highContrast: true,
      clipBehavior: Clip.antiAlias,
      borderRadiusGeometry:
          BorderRadius.vertical(top: Radius.circular(topRadius)),
      padding: padding,
      fallback: Container(
        padding: padding,
        decoration: fallbackDecoration,
        child: child,
      ),
      child: child,
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
    this.borderRadiusGeometry,
    this.highContrast = false,
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

  /// Per-corner override forwarded to the underlying panel; see
  /// [OptionalLiquidGlassPanel.borderRadiusGeometry].
  final BorderRadiusGeometry? borderRadiusGeometry;

  /// Boosts the fill opacity for dense-content surfaces; see
  /// [OptionalLiquidGlassPanel.highContrast].
  final bool highContrast;
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
      borderRadiusGeometry: borderRadiusGeometry,
      highContrast: highContrast,
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
