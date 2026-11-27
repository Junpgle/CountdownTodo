part of '../floating_glass_control.dart';

enum _FloatingGlassSliverAppBarVariant { small, medium, large }

/// Sliver counterpart to [FloatingGlassAppBar].
class FloatingGlassSliverAppBar extends StatelessWidget {
  const FloatingGlassSliverAppBar({
    super.key,
    this.leading,
    this.automaticallyImplyLeading = true,
    this.title,
    this.actions,
    this.automaticallyImplyActions = true,
    this.flexibleSpace,
    this.bottom,
    this.elevation,
    this.scrolledUnderElevation,
    this.shadowColor,
    this.surfaceTintColor,
    this.forceElevated = false,
    this.backgroundColor,
    this.foregroundColor,
    this.iconTheme,
    this.actionsIconTheme,
    this.primary = true,
    this.centerTitle,
    this.excludeHeaderSemantics = false,
    this.titleSpacing,
    this.collapsedHeight,
    this.expandedHeight,
    this.floating = false,
    this.pinned = false,
    this.snap = false,
    this.stretch = false,
    this.stretchTriggerOffset = 100.0,
    this.onStretchTrigger,
    this.shape,
    this.toolbarHeight = kToolbarHeight,
    this.leadingWidth,
    this.toolbarTextStyle,
    this.titleTextStyle,
    this.systemOverlayStyle,
    this.forceMaterialTransparency = false,
    this.useDefaultSemanticsOrder = true,
    this.clipBehavior,
    this.actionsPadding,
    this.floatingControlTint,
    this.floatingControlIsDark,
    this.floatingControlScrollDistance,
  }) : assert(floating || !snap),
       assert(stretchTriggerOffset > 0.0),
       assert(collapsedHeight == null || collapsedHeight >= toolbarHeight),
       _variant = _FloatingGlassSliverAppBarVariant.small;

  const FloatingGlassSliverAppBar.medium({
    super.key,
    this.leading,
    this.automaticallyImplyLeading = true,
    this.title,
    this.actions,
    this.automaticallyImplyActions = true,
    this.flexibleSpace,
    this.bottom,
    this.elevation,
    this.scrolledUnderElevation,
    this.shadowColor,
    this.surfaceTintColor,
    this.forceElevated = false,
    this.backgroundColor,
    this.foregroundColor,
    this.iconTheme,
    this.actionsIconTheme,
    this.primary = true,
    this.centerTitle,
    this.excludeHeaderSemantics = false,
    this.titleSpacing,
    this.collapsedHeight,
    this.expandedHeight,
    this.floating = false,
    this.pinned = true,
    this.snap = false,
    this.stretch = false,
    this.stretchTriggerOffset = 100.0,
    this.onStretchTrigger,
    this.shape,
    this.toolbarHeight = 64.0,
    this.leadingWidth,
    this.toolbarTextStyle,
    this.titleTextStyle,
    this.systemOverlayStyle,
    this.forceMaterialTransparency = false,
    this.useDefaultSemanticsOrder = true,
    this.clipBehavior,
    this.actionsPadding,
    this.floatingControlTint,
    this.floatingControlIsDark,
    this.floatingControlScrollDistance,
  }) : assert(floating || !snap),
       assert(stretchTriggerOffset > 0.0),
       assert(collapsedHeight == null || collapsedHeight >= toolbarHeight),
       _variant = _FloatingGlassSliverAppBarVariant.medium;

  const FloatingGlassSliverAppBar.large({
    super.key,
    this.leading,
    this.automaticallyImplyLeading = true,
    this.title,
    this.actions,
    this.automaticallyImplyActions = true,
    this.flexibleSpace,
    this.bottom,
    this.elevation,
    this.scrolledUnderElevation,
    this.shadowColor,
    this.surfaceTintColor,
    this.forceElevated = false,
    this.backgroundColor,
    this.foregroundColor,
    this.iconTheme,
    this.actionsIconTheme,
    this.primary = true,
    this.centerTitle,
    this.excludeHeaderSemantics = false,
    this.titleSpacing,
    this.collapsedHeight,
    this.expandedHeight,
    this.floating = false,
    this.pinned = true,
    this.snap = false,
    this.stretch = false,
    this.stretchTriggerOffset = 100.0,
    this.onStretchTrigger,
    this.shape,
    this.toolbarHeight = 64.0,
    this.leadingWidth,
    this.toolbarTextStyle,
    this.titleTextStyle,
    this.systemOverlayStyle,
    this.forceMaterialTransparency = false,
    this.useDefaultSemanticsOrder = true,
    this.clipBehavior,
    this.actionsPadding,
    this.floatingControlTint,
    this.floatingControlIsDark,
    this.floatingControlScrollDistance,
  }) : assert(floating || !snap),
       assert(stretchTriggerOffset > 0.0),
       assert(collapsedHeight == null || collapsedHeight >= toolbarHeight),
       _variant = _FloatingGlassSliverAppBarVariant.large;

  final Widget? leading;
  final bool automaticallyImplyLeading;
  final Widget? title;
  final List<Widget>? actions;
  final bool automaticallyImplyActions;
  final Widget? flexibleSpace;
  final PreferredSizeWidget? bottom;
  final double? elevation;
  final double? scrolledUnderElevation;
  final Color? shadowColor;
  final Color? surfaceTintColor;
  final bool forceElevated;
  final Color? backgroundColor;
  final Color? foregroundColor;
  final IconThemeData? iconTheme;
  final IconThemeData? actionsIconTheme;
  final bool primary;
  final bool? centerTitle;
  final bool excludeHeaderSemantics;
  final double? titleSpacing;
  final double? collapsedHeight;
  final double? expandedHeight;
  final bool floating;
  final bool pinned;
  final bool snap;
  final bool stretch;
  final double stretchTriggerOffset;
  final AsyncCallback? onStretchTrigger;
  final ShapeBorder? shape;
  final double toolbarHeight;
  final double? leadingWidth;
  final TextStyle? toolbarTextStyle;
  final TextStyle? titleTextStyle;
  final SystemUiOverlayStyle? systemOverlayStyle;
  final bool forceMaterialTransparency;
  final bool useDefaultSemanticsOrder;
  final Clip? clipBehavior;
  final EdgeInsetsGeometry? actionsPadding;
  final Color? floatingControlTint;
  final bool? floatingControlIsDark;
  final double? floatingControlScrollDistance;
  final _FloatingGlassSliverAppBarVariant _variant;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final glassTint =
        floatingControlTint ??
        _floatingAppBarTint(colorScheme, backgroundColor);
    final glassIsDark =
        floatingControlIsDark ??
        _floatingAppBarIsDark(colorScheme, backgroundColor);
    final resolvedLeading = _resolveFloatingSliverAppBarLeading(context);
    final resolvedActions = _resolveFloatingSliverAppBarActions(context);
    final decoratedLeading = resolvedLeading == null
        ? null
        : FloatingGlassAppBarAction(
            tint: glassTint,
            haloColor: colorScheme.primary,
            useTopBarGlass: true,
            isDark: glassIsDark,
            child: resolvedLeading,
          );
    final decoratedActions = resolvedActions
        ?.map(
          (action) =>
              _isFloatingGlassAppBarLayoutOnly(action) ||
                  action is FloatingGlassAppBarAction ||
                  action is FloatingGlassAppBarActionGroup
              ? action
              : FloatingGlassAppBarAction(
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  tint: glassTint,
                  haloColor: colorScheme.primary,
                  useTopBarGlass: true,
                  isDark: glassIsDark,
                  child: action,
                ),
        )
        .toList(growable: false);
    final effectiveLeadingWidth =
        leadingWidth ??
        (decoratedLeading == null ? null : _floatingAppBarLeadingWidth);
    final effectiveActionsPadding =
        actionsPadding ??
        (decoratedActions == null || decoratedActions.isEmpty
            ? null
            : _floatingAppBarActionsPadding);

    return _FloatingGlassAppBarHost(
      observeScroll: true,
      scrollDistance:
          floatingControlScrollDistance ?? _floatingGlassAppBarScrollDistance,
      notificationPredicate: defaultScrollNotificationPredicate,
      builder: (context, collapseProgress) {
        final flexibleSpaceChild =
            flexibleSpace ?? const FloatingGlassTopBarBackground();
        return _FloatingGlassAppBarScope(
          collapseProgress: collapseProgress,
          child: switch (_variant) {
            _FloatingGlassSliverAppBarVariant.small => SliverAppBar(
              key: key,
              leading: decoratedLeading,
              automaticallyImplyLeading: false,
              title: title,
              actions: decoratedActions,
              automaticallyImplyActions: false,
              flexibleSpace: flexibleSpaceChild,
              bottom: bottom,
              elevation: elevation,
              scrolledUnderElevation: scrolledUnderElevation,
              shadowColor: shadowColor,
              surfaceTintColor: surfaceTintColor,
              forceElevated: forceElevated,
              backgroundColor: backgroundColor,
              foregroundColor: foregroundColor,
              iconTheme: iconTheme,
              actionsIconTheme: actionsIconTheme,
              primary: primary,
              centerTitle: centerTitle,
              excludeHeaderSemantics: excludeHeaderSemantics,
              titleSpacing: titleSpacing,
              collapsedHeight: collapsedHeight,
              expandedHeight: expandedHeight,
              floating: floating,
              pinned: pinned,
              snap: snap,
              stretch: stretch,
              stretchTriggerOffset: stretchTriggerOffset,
              onStretchTrigger: onStretchTrigger,
              shape: shape,
              toolbarHeight: toolbarHeight,
              leadingWidth: effectiveLeadingWidth,
              toolbarTextStyle: toolbarTextStyle,
              titleTextStyle: titleTextStyle,
              systemOverlayStyle: systemOverlayStyle,
              forceMaterialTransparency: forceMaterialTransparency,
              useDefaultSemanticsOrder: useDefaultSemanticsOrder,
              clipBehavior: clipBehavior,
              actionsPadding: effectiveActionsPadding,
            ),
            _FloatingGlassSliverAppBarVariant.medium => SliverAppBar.medium(
              key: key,
              leading: decoratedLeading,
              automaticallyImplyLeading: false,
              title: title,
              actions: decoratedActions,
              automaticallyImplyActions: false,
              flexibleSpace: flexibleSpaceChild,
              bottom: bottom,
              elevation: elevation,
              scrolledUnderElevation: scrolledUnderElevation,
              shadowColor: shadowColor,
              surfaceTintColor: surfaceTintColor,
              forceElevated: forceElevated,
              backgroundColor: backgroundColor,
              foregroundColor: foregroundColor,
              iconTheme: iconTheme,
              actionsIconTheme: actionsIconTheme,
              primary: primary,
              centerTitle: centerTitle,
              excludeHeaderSemantics: excludeHeaderSemantics,
              titleSpacing: titleSpacing,
              collapsedHeight: collapsedHeight,
              expandedHeight: expandedHeight,
              floating: floating,
              pinned: pinned,
              snap: snap,
              stretch: stretch,
              stretchTriggerOffset: stretchTriggerOffset,
              onStretchTrigger: onStretchTrigger,
              shape: shape,
              toolbarHeight: toolbarHeight,
              leadingWidth: effectiveLeadingWidth,
              toolbarTextStyle: toolbarTextStyle,
              titleTextStyle: titleTextStyle,
              systemOverlayStyle: systemOverlayStyle,
              forceMaterialTransparency: forceMaterialTransparency,
              useDefaultSemanticsOrder: useDefaultSemanticsOrder,
              clipBehavior: clipBehavior,
              actionsPadding: effectiveActionsPadding,
            ),
            _FloatingGlassSliverAppBarVariant.large => SliverAppBar.large(
              key: key,
              leading: decoratedLeading,
              automaticallyImplyLeading: false,
              title: title,
              actions: decoratedActions,
              automaticallyImplyActions: false,
              flexibleSpace: flexibleSpaceChild,
              bottom: bottom,
              elevation: elevation,
              scrolledUnderElevation: scrolledUnderElevation,
              shadowColor: shadowColor,
              surfaceTintColor: surfaceTintColor,
              forceElevated: forceElevated,
              backgroundColor: backgroundColor,
              foregroundColor: foregroundColor,
              iconTheme: iconTheme,
              actionsIconTheme: actionsIconTheme,
              primary: primary,
              centerTitle: centerTitle,
              excludeHeaderSemantics: excludeHeaderSemantics,
              titleSpacing: titleSpacing,
              collapsedHeight: collapsedHeight,
              expandedHeight: expandedHeight,
              floating: floating,
              pinned: pinned,
              snap: snap,
              stretch: stretch,
              stretchTriggerOffset: stretchTriggerOffset,
              onStretchTrigger: onStretchTrigger,
              shape: shape,
              toolbarHeight: toolbarHeight,
              leadingWidth: effectiveLeadingWidth,
              toolbarTextStyle: toolbarTextStyle,
              titleTextStyle: titleTextStyle,
              systemOverlayStyle: systemOverlayStyle,
              forceMaterialTransparency: forceMaterialTransparency,
              useDefaultSemanticsOrder: useDefaultSemanticsOrder,
              clipBehavior: clipBehavior,
              actionsPadding: effectiveActionsPadding,
            ),
          },
        );
      },
    );
  }

  Widget? _resolveFloatingSliverAppBarLeading(BuildContext context) {
    if (leading != null || !automaticallyImplyLeading) return leading;

    final scaffold = Scaffold.maybeOf(context);
    final route = ModalRoute.of(context);
    if (scaffold?.hasDrawer ?? false) {
      return DrawerButton(
        style: floatingGlassPlainIconButtonStyle().copyWith(
          iconSize: WidgetStatePropertyAll(iconTheme?.size ?? 24),
        ),
      );
    }
    if (route?.impliesAppBarDismissal ?? false) {
      return route?.fullscreenDialog ?? false
          ? CloseButton(style: floatingGlassPlainIconButtonStyle())
          : BackButton(style: floatingGlassPlainIconButtonStyle());
    }
    return null;
  }

  List<Widget>? _resolveFloatingSliverAppBarActions(BuildContext context) {
    if (actions != null && actions!.isNotEmpty) return actions;
    if (automaticallyImplyActions &&
        (Scaffold.maybeOf(context)?.hasEndDrawer ?? false)) {
      return <Widget>[
        EndDrawerButton(
          style: floatingGlassPlainIconButtonStyle().copyWith(
            iconSize: WidgetStatePropertyAll(actionsIconTheme?.size ?? 24),
          ),
        ),
      ];
    }
    return actions;
  }
}

/// A shared glass action button for screens that use the Scaffold FAB slot.
///
/// It intentionally mirrors the common `FloatingActionButton` constructors,
/// so screen-level actions can be upgraded without duplicating glass styling.
class FloatingGlassActionButton extends StatelessWidget {
  const FloatingGlassActionButton.extended({
    super.key,
    required this.onPressed,
    required this.icon,
    required this.label,
    this.heroTag,
    this.tooltip,
    this.backgroundColor,
    this.foregroundColor,
    this.elevation,
    this.margin = EdgeInsets.zero,
  }) : _extended = true,
       child = null;

  const FloatingGlassActionButton.small({
    super.key,
    required this.onPressed,
    required this.child,
    this.heroTag,
    this.tooltip,
    this.backgroundColor,
    this.foregroundColor,
    this.elevation,
    this.margin = EdgeInsets.zero,
  }) : _extended = false,
       icon = null,
       label = null;

  final VoidCallback? onPressed;
  final Object? heroTag;
  final String? tooltip;
  final Color? backgroundColor;
  final Color? foregroundColor;
  final double? elevation;
  final EdgeInsetsGeometry margin;
  final bool _extended;
  final Widget? icon;
  final Widget? label;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = colorScheme.brightness == Brightness.dark;
    final enabled = onPressed != null;
    final resolvedForeground = enabled
        ? (foregroundColor ?? colorScheme.onPrimaryContainer)
        : colorScheme.onSurface.withValues(alpha: 0.38);
    final resolvedTint = enabled
        ? (backgroundColor ?? colorScheme.primaryContainer)
        : colorScheme.surfaceContainerHighest;
    final borderRadius = _extended ? 18.0 : 28.0;

    final fallback = _extended
        ? FloatingActionButton.extended(
            heroTag: heroTag,
            onPressed: onPressed,
            tooltip: tooltip,
            backgroundColor: backgroundColor,
            foregroundColor: foregroundColor,
            elevation: elevation,
            icon: icon!,
            label: label!,
          )
        : FloatingActionButton.small(
            heroTag: heroTag,
            onPressed: onPressed,
            tooltip: tooltip,
            backgroundColor: backgroundColor,
            foregroundColor: foregroundColor,
            elevation: elevation,
            child: child,
          );

    return ValueListenableBuilder<LiquidGlassEffectConfiguration>(
      valueListenable: LiquidGlassEffectService.configurationListenable,
      builder: (context, configuration, _) {
        if (!configuration.enabled) return fallback;

        final enhanced = configuration.mode == LiquidGlassEffectMode.enhanced;
        final glassContent = _extended
            ? SizedBox(
                height: 56,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconTheme(
                        data: IconThemeData(
                          color: resolvedForeground,
                          size: 24,
                        ),
                        child: icon!,
                      ),
                      const SizedBox(width: 8),
                      DefaultTextStyle(
                        style: Theme.of(context).textTheme.labelLarge!.copyWith(
                          color: resolvedForeground,
                          fontWeight: FontWeight.w600,
                        ),
                        child: label!,
                      ),
                    ],
                  ),
                ),
              )
            : SizedBox(
                width: 56,
                height: 56,
                child: Center(
                  child: IconTheme.merge(
                    data: IconThemeData(color: resolvedForeground),
                    child: child!,
                  ),
                ),
              );
        final glassButton = GlassButton.custom(
          onTap: onPressed ?? () {},
          enabled: enabled,
          label: tooltip ?? '',
          width: _extended ? null : 56,
          height: 56,
          shape: _extended
              ? LiquidRoundedSuperellipse(borderRadius: borderRadius)
              : const LiquidOval(),
          settings: LiquidGlassSettings(
            bodyMode: GlassBodyMode.clear,
            glassColor: resolvedTint.withValues(
              alpha: liquidGlassBackerOpacity(
                isDark ? 0.18 : 0.12,
                configuration,
              ),
            ),
            thickness: enhanced ? 22 : 18,
            blur: enhanced ? 11 : 8,
            chromaticAberration: 0.0015,
            lightIntensity: isDark ? 0.5 : 0.6,
            ambientStrength: isDark ? 0.08 : 0.1,
            fresnelStrength: 0.55,
            refractiveIndex: 1.08,
            saturation: 1.0,
            standardOpacityMultiplier: 1.0,
            shadowElevation: 0.35,
          ),
          useOwnLayer: true,
          quality:
              (AppPlatform.isAndroid &&
                  MediaQuery.sizeOf(context).width >= 768 &&
                  configuration.mode == LiquidGlassEffectMode.enhanced)
              ? GlassQuality.standard
              : (liquidGlassPrefersStaticChromeFor(
                      isAndroid: AppPlatform.isAndroid,
                      viewportWidth: MediaQuery.sizeOf(context).width,
                      mode: configuration.mode,
                      hasBackdropScope:
                          OptionalLiquidGlassBackdropScope.maybeOf(context) !=
                          null,
                    )
                    ? GlassQuality.minimal
                    : liquidGlassQualityForMode(configuration.mode)),
          interactionScale: 1.04,
          stretch: _extended ? 0.28 : 0.4,
          resistance: 0.015,
          glowColor: resolvedTint,
          glowOpacity: enabled ? 0.7 : 0.2,
          style: _extended
              ? GlassButtonStyle.prominent
              : GlassButtonStyle.filled,
          child: glassContent,
        );

        Widget content = glassButton;
        if (tooltip != null && tooltip!.isNotEmpty) {
          content = Tooltip(
            message: tooltip!,
            preferBelow: false,
            child: content,
          );
        }
        if (heroTag != null) {
          content = Hero(tag: heroTag!, child: content);
        }

        return Padding(padding: margin, child: content);
      },
    );
  }
}

/// Fade used by shared AppBar callsites and custom top toolbars.
///
/// The default treatment is a low-contrast gradient only. It keeps the page
/// continuous while content moves beneath the toolbar; the optional blur is
/// reserved for callsites that explicitly opt into a stronger glass surface.
class FloatingGlassTopBarBackground extends StatelessWidget {
  const FloatingGlassTopBarBackground({
    super.key,
    this.fadeExtent = 0.8,
    this.tint,
    this.isDark,
    this.unboundedHeight,
    this.blur = false,
  });

  final double fadeExtent;
  final Color? tint;
  final bool? isDark;

  /// Height used when an embedded [AppBar] gives its flexible space an
  /// unbounded vertical constraint. Normal Scaffold/SliverAppBar callsites
  /// remain fully constraint-driven.
  final double? unboundedHeight;
  final bool blur;

  @override
  Widget build(BuildContext context) {
    final scopedProgress = _FloatingGlassAppBarScope.maybeOf(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final content = constraints.hasBoundedHeight
            ? const SizedBox.expand()
            : SizedBox(
                height:
                    (unboundedHeight ??
                            kToolbarHeight + MediaQuery.paddingOf(context).top)
                        .clamp(0.0, 1000.0),
              );
        if (scopedProgress == null) {
          return _buildBackground(
            context,
            progress: 0.0,
            useFlexibleSpaceSettings: false,
            content: content,
          );
        }

        return ValueListenableBuilder<double>(
          valueListenable: scopedProgress,
          builder: (context, progress, _) => _buildBackground(
            context,
            progress: progress,
            useFlexibleSpaceSettings: true,
            content: content,
          ),
        );
      },
    );
  }

  Widget _buildBackground(
    BuildContext context, {
    required double progress,
    required bool useFlexibleSpaceSettings,
    required Widget content,
  }) {
    final settings = useFlexibleSpaceSettings
        ? context.dependOnInheritedWidgetOfExactType<FlexibleSpaceBarSettings>()
        : null;
    final resolvedProgress =
        settings == null || settings.maxExtent <= settings.minExtent
        ? progress
        : _floatingGlassAppBarProgressForFlexibleSpace(settings);

    return ValueListenableBuilder<LiquidGlassEffectConfiguration>(
      valueListenable: LiquidGlassEffectService.configurationListenable,
      builder: (context, configuration, _) {
        if (blur && !configuration.enabled) return content;

        final intensity = (resolvedProgress * fadeExtent.clamp(0.0, 1.0)).clamp(
          0.0,
          1.0,
        );
        if (intensity <= 0.001) return content;

        final colorScheme = Theme.of(context).colorScheme;
        final dark = isDark ?? colorScheme.brightness == Brightness.dark;
        final base = tint ?? colorScheme.surface;
        final topColor = Color.alphaBlend(
          colorScheme.primary.withValues(alpha: dark ? 0.08 : 0.05),
          base,
        );
        final topAlpha = blur
            ? (0.12 + (intensity * 0.74)).clamp(0.0, 1.0)
            : (0.04 + (intensity * 0.12)).clamp(0.0, 1.0);
        final middleAlpha = blur
            ? (0.06 + (intensity * 0.58)).clamp(0.0, 1.0)
            : (0.015 + (intensity * 0.04)).clamp(0.0, 1.0);
        final lowerAlpha = blur
            ? (intensity * 0.22).clamp(0.0, 1.0)
            : (intensity * 0.02).clamp(0.0, 1.0);

        Widget surface = DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              stops: const [0, 0.38, 0.72, 1],
              colors: [
                topColor.withValues(alpha: topAlpha * (dark ? 0.94 : 1.0)),
                topColor.withValues(alpha: middleAlpha * (dark ? 0.9 : 1.0)),
                topColor.withValues(alpha: lowerAlpha * (dark ? 0.9 : 1.0)),
                topColor.withValues(alpha: 0),
              ],
            ),
          ),
          child: content,
        );

        if (blur) {
          surface = BackdropFilter.grouped(
            filter: AppImageFilters.quantizedClampedBlur(16.0),
            child: surface,
          );
        }

        return ClipRect(child: surface);
      },
    );
  }
}

/// Flexible space for a Material 3 large sliver app bar.
///
/// Supplying a custom [SliverAppBar.large.flexibleSpace] replaces Flutter's
/// built-in large-title layout, so this small companion keeps the expanded
/// title while adding the shared glass fade behind it.
class FloatingGlassLargeFlexibleSpace extends StatelessWidget {
  const FloatingGlassLargeFlexibleSpace({
    super.key,
    required this.title,
    this.tint,
    this.isDark,
  });

  final Widget title;
  final Color? tint;
  final bool? isDark;

  @override
  Widget build(BuildContext context) {
    final settings = context
        .dependOnInheritedWidgetOfExactType<FlexibleSpaceBarSettings>();
    final extent = settings == null
        ? 1.0
        : ((settings.currentExtent - settings.minExtent) /
                  (settings.maxExtent - settings.minExtent))
              .clamp(0.0, 1.0);
    final colorScheme = Theme.of(context).colorScheme;
    final expandedStyle = Theme.of(context).textTheme.headlineMedium
        ?.copyWith(color: colorScheme.onSurface);

    final baseTitleColor = expandedStyle?.color ?? colorScheme.onSurface;
    final styledTitle = DefaultTextStyle(
      style: (expandedStyle ?? const TextStyle()).copyWith(
        color: extent >= 0.999
            ? baseTitleColor
            : baseTitleColor.withValues(alpha: extent),
      ),
      child: title,
    );

    return Stack(
      fit: StackFit.expand,
      children: [
        FloatingGlassTopBarBackground(tint: tint, isDark: isDark),
        if (extent > 0.001)
          Align(
            alignment: Alignment.bottomLeft,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
              child: styledTitle,
            ),
          ),
      ],
    );
  }
}

class _FloatingGlassControlFallback extends StatelessWidget {
  const _FloatingGlassControlFallback({
    required this.height,
    required this.margin,
    required this.borderRadius,
    required this.haloColor,
    required this.isDark,
    required this.allowChildOverflow,
    required this.child,
    this.shellOpacity = 1.0,
  });

  final double? height;
  final EdgeInsetsGeometry margin;
  final double borderRadius;
  final Color haloColor;
  final bool isDark;
  final bool allowChildOverflow;
  final Widget child;
  final double shellOpacity;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final opacity = shellOpacity.clamp(0.0, 1.0).toDouble();
    final decoration = BoxDecoration(
      color:
          (isDark
                  ? colorScheme.surfaceContainerHighest.withValues(alpha: 0.82)
                  : colorScheme.surface.withValues(alpha: 0.9))
              .withValues(alpha: (isDark ? 0.82 : 0.9) * opacity),
      borderRadius: BorderRadius.circular(borderRadius),
      border: Border.all(
        color: colorScheme.outlineVariant.withValues(
          alpha: (isDark ? 0.42 : 0.54) * opacity,
        ),
        width: 0.8,
      ),
      boxShadow: <BoxShadow>[
        BoxShadow(
          color: haloColor.withValues(alpha: (isDark ? 0.12 : 0.2) * opacity),
          blurRadius: 26,
          spreadRadius: 1,
          offset: const Offset(0, 4),
        ),
        BoxShadow(
          color: colorScheme.shadow.withValues(alpha: 0.12 * opacity),
          blurRadius: 15,
          offset: const Offset(0, 5),
        ),
      ],
    );

    return Container(
      height: height,
      margin: margin,
      decoration: decoration,
      clipBehavior: allowChildOverflow ? Clip.none : Clip.hardEdge,
      child: child,
    );
  }
}
