part of '../floating_glass_control.dart';

/// A shared app-bar control adapter with a scroll-aware transition.
///
/// At the expanded/resting position this returns the original control, so the
/// top bar stays visually native. As the shared app-bar collapse progress
/// advances, the same control continuously cross-fades and scales into an
/// independent round glass shell. The child remains the owner of semantics
/// and callbacks.
class FloatingGlassAppBarAction extends StatelessWidget {
  const FloatingGlassAppBarAction({
    super.key,
    required this.child,
    this.size = floatingGlassStandardControlSize,
    this.borderRadius = floatingGlassStandardControlSize / 2,
    this.margin = EdgeInsets.zero,
    this.tint,
    this.haloColor,
    this.haloOpacity = 0.28,
    this.backerOpacity,
    this.useTopBarGlass = false,
    this.isDark,
    this.collapseProgress,
    this.floatingThreshold = _floatingGlassAppBarControlThreshold,
  });

  final Widget child;
  final double size;
  final double borderRadius;
  final EdgeInsetsGeometry margin;
  final Color? tint;
  final Color? haloColor;
  final double? haloOpacity;
  final double? backerOpacity;
  final bool useTopBarGlass;
  final bool? isDark;
  final ValueListenable<double>? collapseProgress;
  final double floatingThreshold;

  @override
  Widget build(BuildContext context) {
    final progress =
        collapseProgress ?? _FloatingGlassAppBarScope.maybeOf(context);
    if (progress == null) {
      return _FloatingGlassAppBarHost(
        notificationPredicate: defaultScrollNotificationPredicate,
        builder: (context, standaloneProgress) => _FloatingGlassAppBarScope(
          collapseProgress: standaloneProgress,
          child: _FloatingGlassAppBarActionContent(
            size: size,
            borderRadius: borderRadius,
            margin: margin,
            tint: tint,
            haloColor: haloColor,
            haloOpacity: haloOpacity,
            backerOpacity: backerOpacity,
            useTopBarGlass: useTopBarGlass,
            isDark: isDark,
            collapseProgress: standaloneProgress,
            floatingThreshold: floatingThreshold,
            child: child,
          ),
        ),
      );
    }

    return _FloatingGlassAppBarActionContent(
      size: size,
      borderRadius: borderRadius,
      margin: margin,
      tint: tint,
      haloColor: haloColor,
      haloOpacity: haloOpacity,
      backerOpacity: backerOpacity,
      useTopBarGlass: useTopBarGlass,
      isDark: isDark,
      collapseProgress: progress,
      floatingThreshold: floatingThreshold,
      child: child,
    );
  }
}

Widget _neutralizeFloatingAppBarButtons(BuildContext context, Widget child) {
  final colorScheme = Theme.of(context).colorScheme;
  return Theme(
    data: Theme.of(context).copyWith(
      // The app-wide glass button theme applies to ordinary page controls.
      // Top-bar actions have their own scroll-aware shell, so keep the
      // resting child visually native and avoid a second glass surface.
      iconButtonTheme: IconButtonThemeData(
        style: ButtonStyle(
          // A non-null identity builder is required here: null would allow
          // the app-wide glass backgroundBuilder to merge back in and paint
          // a second circle inside the app-bar shell.
          backgroundBuilder: (context, states, child) =>
              child ?? const SizedBox.shrink(),
          backgroundColor: const WidgetStatePropertyAll(Colors.transparent),
          foregroundColor: WidgetStatePropertyAll(colorScheme.onSurface),
          side: const WidgetStatePropertyAll(BorderSide.none),
          elevation: const WidgetStatePropertyAll(0),
          shadowColor: const WidgetStatePropertyAll(Colors.transparent),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        ),
      ),
    ),
    child: child,
  );
}

Widget _buildScrollAnimatedControlProgress({
  required ValueListenable<double> collapseProgress,
  required double floatingThreshold,
  required Widget staticChild,
  required Widget Function(
    BuildContext context,
    double progress,
    Widget cachedChild,
  )
  builder,
}) {
  return ValueListenableBuilder<double>(
    valueListenable: collapseProgress,
    child: staticChild,
    builder: (context, value, cachedStaticChild) {
      final transitionStart = math.max(0.0, floatingThreshold - 0.22);
      final transitionEnd = math.min(1.0, floatingThreshold + 0.22);
      final transitionRange = math.max(0.001, transitionEnd - transitionStart);
      final target = ((value - transitionStart) / transitionRange).clamp(
        0.0,
        1.0,
      );

      // Scroll notifications already provide a frame-by-frame progress
      // signal. Animating each new target again with a 180 ms tween makes
      // Android controls trail the scroll and schedules redundant work.
      if (AppPlatform.isAndroid) {
        return builder(context, target, cachedStaticChild!);
      }

      return TweenAnimationBuilder<double>(
        tween: Tween<double>(end: target),
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        child: cachedStaticChild,
        builder: (context, progress, innerStaticChild) =>
            builder(context, progress, innerStaticChild!),
      );
    },
  );
}

Widget? _wrapAnimatedGlassShell({
  required double progress,
  required Widget Function(double progress) buildClippedShell,
}) {
  if (progress <= 0.001) return null;
  final clamped = progress >= 0.999 ? 1.0 : progress.clamp(0.0, 1.0).toDouble();
  final clippedControl = buildClippedShell(clamped);
  // Modulate shell alpha inside the glass/fallback surface instead of wrapping
  // a BackdropFilterLayer in an ancestor OpacityLayer offscreen saveLayer.
  return IgnorePointer(
    child: clamped >= 1.0
        ? clippedControl
        : Transform.scale(
            scale: 0.82 + clamped * 0.18,
            child: RepaintBoundary(child: clippedControl),
          ),
  );
}

class _FloatingGlassAppBarActionContent extends StatelessWidget {
  const _FloatingGlassAppBarActionContent({
    required this.child,
    required this.size,
    required this.borderRadius,
    required this.margin,
    required this.tint,
    required this.haloColor,
    required this.haloOpacity,
    required this.backerOpacity,
    required this.useTopBarGlass,
    required this.isDark,
    required this.collapseProgress,
    required this.floatingThreshold,
  });

  final Widget child;
  final double size;
  final double borderRadius;
  final EdgeInsetsGeometry margin;
  final Color? tint;
  final Color? haloColor;
  final double? haloOpacity;
  final double? backerOpacity;
  final bool useTopBarGlass;
  final bool? isDark;
  final ValueListenable<double> collapseProgress;
  final double floatingThreshold;

  @override
  Widget build(BuildContext context) {
    final nativeChild = _neutralizeFloatingAppBarButtons(context, child);
    return _buildScrollAnimatedControlProgress(
      collapseProgress: collapseProgress,
      floatingThreshold: floatingThreshold,
      staticChild: Center(child: nativeChild),
      builder: _buildForProgress,
    );
  }

  Widget _buildForProgress(
    BuildContext context,
    double progress,
    Widget centeredNativeChild,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    final resolvedTint = tint ?? _floatingAppBarTint(colorScheme, null);
    final glassShell = _wrapAnimatedGlassShell(
      progress: progress,
      buildClippedShell: (shellOpacity) => ClipOval(
        // The glass surface owns an outer halo shadow. Clip
        // it to the circular control so it cannot leave a
        // square/irregular shadow around the action button.
        child: FloatingGlassControl(
          height: size,
          borderRadius: borderRadius,
          tint: resolvedTint,
          haloColor: haloColor ?? colorScheme.primary,
          haloOpacity: haloOpacity,
          backerOpacity: backerOpacity,
          shellOpacity: shellOpacity,
          useTopBarGlass: useTopBarGlass,
          isDark: isDark,
          child: const SizedBox.shrink(),
        ),
      ),
    );

    return Padding(
      padding: margin,
      child: Center(
        child: SizedBox(
          width: size,
          height: size,
          child: Stack(
            alignment: Alignment.center,
            fit: StackFit.expand,
            children: [?glassShell, centeredNativeChild],
          ),
        ),
      ),
    );
  }
}

/// Groups adjacent app-bar actions inside a single shared Liquid Glass pill
/// capsule once scrolled, matching Apple's grouped toolbar chrome while keeping
/// top-bar glass to one shader/backdrop pass instead of one per button.
class FloatingGlassAppBarActionGroup extends StatelessWidget {
  const FloatingGlassAppBarActionGroup({
    super.key,
    required this.children,
    this.height = floatingGlassStandardControlSize,
    this.borderRadius,
    this.margin = EdgeInsets.zero,
    this.padding = const EdgeInsets.symmetric(horizontal: 4),
    this.spacing = 0,
    this.tint,
    this.haloColor,
    this.haloOpacity = 0.28,
    this.backerOpacity,
    this.useTopBarGlass = true,
    this.isDark,
    this.collapseProgress,
    this.floatingThreshold = _floatingGlassAppBarControlThreshold,
  });

  final List<Widget> children;
  final double height;
  final double? borderRadius;
  final EdgeInsetsGeometry margin;
  final EdgeInsetsGeometry padding;
  final double spacing;
  final Color? tint;
  final Color? haloColor;
  final double? haloOpacity;
  final double? backerOpacity;
  final bool useTopBarGlass;
  final bool? isDark;
  final ValueListenable<double>? collapseProgress;
  final double floatingThreshold;

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) return const SizedBox.shrink();
    final progress =
        collapseProgress ?? _FloatingGlassAppBarScope.maybeOf(context);
    Widget buildContent(ValueListenable<double> activeProgress) {
      return _FloatingGlassAppBarActionGroupContent(
        height: height,
        borderRadius: borderRadius ?? height / 2,
        margin: margin,
        padding: padding,
        spacing: spacing,
        tint: tint,
        haloColor: haloColor,
        haloOpacity: haloOpacity,
        backerOpacity: backerOpacity,
        useTopBarGlass: useTopBarGlass,
        isDark: isDark,
        collapseProgress: activeProgress,
        floatingThreshold: floatingThreshold,
        children: children,
      );
    }

    if (progress == null) {
      return _FloatingGlassAppBarHost(
        notificationPredicate: defaultScrollNotificationPredicate,
        builder: (context, standaloneProgress) => _FloatingGlassAppBarScope(
          collapseProgress: standaloneProgress,
          child: buildContent(standaloneProgress),
        ),
      );
    }

    return buildContent(progress);
  }
}

class _FloatingGlassAppBarActionGroupContent extends StatelessWidget {
  const _FloatingGlassAppBarActionGroupContent({
    required this.children,
    required this.height,
    required this.borderRadius,
    required this.margin,
    required this.padding,
    required this.spacing,
    required this.tint,
    required this.haloColor,
    required this.haloOpacity,
    required this.backerOpacity,
    required this.useTopBarGlass,
    required this.isDark,
    required this.collapseProgress,
    required this.floatingThreshold,
  });

  final List<Widget> children;
  final double height;
  final double borderRadius;
  final EdgeInsetsGeometry margin;
  final EdgeInsetsGeometry padding;
  final double spacing;
  final Color? tint;
  final Color? haloColor;
  final double? haloOpacity;
  final double? backerOpacity;
  final bool useTopBarGlass;
  final bool? isDark;
  final ValueListenable<double> collapseProgress;
  final double floatingThreshold;

  @override
  Widget build(BuildContext context) {
    final spacedChildren = spacing <= 0 || children.length <= 1
        ? children
        : <Widget>[
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0) SizedBox(width: spacing),
              children[i],
            ],
          ];
    final nativeRow = _neutralizeFloatingAppBarButtons(
      context,
      Padding(
        padding: padding,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: spacedChildren,
        ),
      ),
    );

    return _buildScrollAnimatedControlProgress(
      collapseProgress: collapseProgress,
      floatingThreshold: floatingThreshold,
      staticChild: nativeRow,
      builder: _buildForProgress,
    );
  }

  Widget _buildForProgress(
    BuildContext context,
    double progress,
    Widget cachedRow,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    final resolvedTint = tint ?? _floatingAppBarTint(colorScheme, null);
    final capsuleRadius = BorderRadius.circular(borderRadius);
    final glassShell = _wrapAnimatedGlassShell(
      progress: progress,
      buildClippedShell: (shellOpacity) => ClipRSuperellipse(
        borderRadius: capsuleRadius,
        child: FloatingGlassControl(
          height: height,
          borderRadius: borderRadius,
          tint: resolvedTint,
          haloColor: haloColor ?? colorScheme.primary,
          haloOpacity: haloOpacity,
          backerOpacity: backerOpacity,
          shellOpacity: shellOpacity,
          useTopBarGlass: useTopBarGlass,
          isDark: isDark,
          child: const SizedBox.shrink(),
        ),
      ),
    );

    return Padding(
      padding: margin,
      child: Center(
        child: SizedBox(
          height: height,
          child: Stack(
            alignment: Alignment.center,
            children: [
              if (glassShell != null) Positioned.fill(child: glassShell),
              cachedRow,
            ],
          ),
        ),
      ),
    );
  }
}

/// A drop-in [AppBar] adapter that floats every leading/action control.
///
/// Keeping the native [AppBar] as the rendered child preserves Material's
/// route dismissal, drawer affordances, title semantics, and scroll behavior.
/// The adapter resolves those implicit controls first, then applies the shared
/// [FloatingGlassAppBarAction] shell to them as well as explicit actions.
class FloatingGlassAppBar extends StatelessWidget
    implements PreferredSizeWidget {
  const FloatingGlassAppBar({
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
    this.notificationPredicate = defaultScrollNotificationPredicate,
    this.shadowColor,
    this.surfaceTintColor,
    this.shape,
    this.backgroundColor,
    this.foregroundColor,
    this.iconTheme,
    this.actionsIconTheme,
    this.primary = true,
    this.centerTitle,
    this.excludeHeaderSemantics = false,
    this.titleSpacing,
    this.toolbarOpacity = 1.0,
    this.bottomOpacity = 1.0,
    this.toolbarHeight,
    this.leadingWidth,
    this.toolbarTextStyle,
    this.titleTextStyle,
    this.systemOverlayStyle,
    this.forceMaterialTransparency = false,
    this.useDefaultSemanticsOrder = true,
    this.clipBehavior,
    this.actionsPadding,
    this.animateColor = false,
    this.useFloatingControls = true,
    this.floatingControlTint,
    this.floatingControlIsDark,
    this.floatingControlScrollDistance = _floatingGlassAppBarScrollDistance,
  });

  final Widget? leading;
  final bool automaticallyImplyLeading;
  final Widget? title;
  final List<Widget>? actions;
  final bool automaticallyImplyActions;
  final Widget? flexibleSpace;
  final PreferredSizeWidget? bottom;
  final double? elevation;
  final double? scrolledUnderElevation;
  final ScrollNotificationPredicate notificationPredicate;
  final Color? shadowColor;
  final Color? surfaceTintColor;
  final ShapeBorder? shape;
  final Color? backgroundColor;
  final Color? foregroundColor;
  final IconThemeData? iconTheme;
  final IconThemeData? actionsIconTheme;
  final bool primary;
  final bool? centerTitle;
  final bool excludeHeaderSemantics;
  final double? titleSpacing;
  final double toolbarOpacity;
  final double bottomOpacity;
  final double? toolbarHeight;
  final double? leadingWidth;
  final TextStyle? toolbarTextStyle;
  final TextStyle? titleTextStyle;
  final SystemUiOverlayStyle? systemOverlayStyle;
  final bool forceMaterialTransparency;
  final bool useDefaultSemanticsOrder;
  final Clip? clipBehavior;
  final EdgeInsetsGeometry? actionsPadding;
  final bool animateColor;

  /// Whether leading/actions become independent glass lenses as the bar
  /// collapses. Disable this when a screen already owns one continuous top
  /// surface; the controls then remain plain inside that surface.
  final bool useFloatingControls;

  /// Optional appearance override for the independently floating controls.
  /// This is useful when the native AppBar remains transparent over a custom
  /// backdrop whose brightness cannot be inferred from [backgroundColor].
  final Color? floatingControlTint;
  final bool? floatingControlIsDark;
  final double floatingControlScrollDistance;

  @override
  Size get preferredSize => Size.fromHeight(
    (toolbarHeight ?? kToolbarHeight) + (bottom?.preferredSize.height ?? 0),
  );

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    // Every screen that opts into the shared adapter should start as a
    // native, background-connected toolbar. Callers can still provide an
    // explicit background/elevation when they intentionally need a different
    // surface, but the default must not recreate Material's opaque AppBar
    // slab or let the platform infer the wrong status-bar icon contrast.
    final resolvedBackgroundColor = backgroundColor ?? Colors.transparent;
    final resolvedForegroundColor = foregroundColor ?? colorScheme.onSurface;
    final resolvedElevation = elevation ?? 0.0;
    final resolvedScrolledUnderElevation = scrolledUnderElevation ?? 0.0;
    final resolvedSurfaceTintColor = surfaceTintColor ?? Colors.transparent;
    final resolvedShadowColor = shadowColor ?? Colors.transparent;
    final resolvedSystemOverlayStyle =
        systemOverlayStyle ?? floatingGlassTopBarSystemOverlayStyle(context);
    final resolvedForceMaterialTransparency =
        forceMaterialTransparency || backgroundColor == null;
    final glassTint =
        floatingControlTint ??
        _floatingAppBarTint(colorScheme, backgroundColor);
    final glassIsDark =
        floatingControlIsDark ??
        _floatingAppBarIsDark(colorScheme, backgroundColor);
    final resolvedLeading = _resolveFloatingAppBarLeading(context);
    final resolvedActions = _resolveFloatingAppBarActions(context);
    final decoratedLeading = !useFloatingControls || resolvedLeading == null
        ? null
        : FloatingGlassAppBarAction(
            tint: glassTint,
            haloColor: colorScheme.primary,
            useTopBarGlass: true,
            isDark: glassIsDark,
            child: resolvedLeading,
          );
    final decoratedActions = !useFloatingControls
        ? resolvedActions
        : resolvedActions
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

    Widget buildAppBar(ValueNotifier<double> collapseProgress) {
      final appBar = AppBar(
        leading:
            decoratedLeading ?? (useFloatingControls ? null : resolvedLeading),
        automaticallyImplyLeading: false,
        title: title,
        actions: decoratedActions,
        automaticallyImplyActions: false,
        flexibleSpace: _FloatingGlassCollapseReporter(
          collapseProgress: collapseProgress,
          child: flexibleSpace ?? const FloatingGlassTopBarBackground(),
        ),
        bottom: bottom,
        elevation: resolvedElevation,
        scrolledUnderElevation: resolvedScrolledUnderElevation,
        notificationPredicate: notificationPredicate,
        shadowColor: resolvedShadowColor,
        surfaceTintColor: resolvedSurfaceTintColor,
        shape: shape,
        backgroundColor: resolvedBackgroundColor,
        foregroundColor: resolvedForegroundColor,
        iconTheme: iconTheme,
        actionsIconTheme: actionsIconTheme,
        primary: primary,
        centerTitle: centerTitle,
        excludeHeaderSemantics: excludeHeaderSemantics,
        titleSpacing: titleSpacing,
        toolbarOpacity: toolbarOpacity,
        bottomOpacity: bottomOpacity,
        toolbarHeight: toolbarHeight,
        leadingWidth:
            leadingWidth ??
            (useFloatingControls && decoratedLeading != null
                ? _floatingAppBarLeadingWidth
                : null),
        toolbarTextStyle: toolbarTextStyle,
        titleTextStyle: titleTextStyle,
        systemOverlayStyle: resolvedSystemOverlayStyle,
        forceMaterialTransparency: resolvedForceMaterialTransparency,
        useDefaultSemanticsOrder: useDefaultSemanticsOrder,
        clipBehavior: clipBehavior,
        actionsPadding:
            actionsPadding ??
            (!useFloatingControls ||
                    decoratedActions == null ||
                    decoratedActions.isEmpty
                ? null
                : _floatingAppBarActionsPadding),
        animateColor: animateColor,
      );

      if (!useFloatingControls) {
        return Theme(
          // A continuous top surface owns the visual treatment. Neutralize
          // the app-wide button glass theme for its plain child controls.
          data: _floatingGlassChildTheme(context),
          child: appBar,
        );
      }

      if (decoratedLeading != null || (decoratedActions?.isNotEmpty ?? false)) {
        return BackdropGroup(child: GlassBackdropGroup(child: appBar));
      }
      return appBar;
    }

    return _FloatingGlassAppBarHost(
      notificationPredicate: notificationPredicate,
      scrollDistance: floatingControlScrollDistance,
      builder: (context, collapseProgress) => _FloatingGlassAppBarScope(
        collapseProgress: collapseProgress,
        child: buildAppBar(collapseProgress),
      ),
    );
  }

  Widget? _resolveFloatingAppBarLeading(BuildContext context) {
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

  List<Widget>? _resolveFloatingAppBarActions(BuildContext context) {
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

const double _floatingAppBarLeadingWidth = 72;
const EdgeInsets _floatingAppBarActionsPadding = EdgeInsets.only(right: 12);

bool _isFloatingGlassAppBarLayoutOnly(Widget action) {
  // Text actions must keep their intrinsic width. The circular glass shell
  // is reserved for compact controls such as IconButton and PopupMenuButton;
  // forcing a TextButton into 48 px would clip labels and overflow its row.
  // Composite controls already own their shape and width; wrapping a
  // SegmentedButton in another circular shell makes its two segments look
  // like a broken split-circle control.
  if (action is Padding && action.child != null) {
    return _isFloatingGlassAppBarLayoutOnly(action.child!);
  }

  return action is SizedBox ||
      action is Spacer ||
      action is ButtonStyleButton ||
      action is SegmentedButton<dynamic>;
}

Color _floatingAppBarResolvedBackground(
  ColorScheme colorScheme,
  Color? backgroundColor,
) {
  final surface = colorScheme.surfaceContainerLow;
  return backgroundColor == null
      ? surface
      : Color.alphaBlend(backgroundColor, surface);
}

Color _floatingAppBarTint(ColorScheme colorScheme, Color? backgroundColor) {
  final base = _floatingAppBarResolvedBackground(colorScheme, backgroundColor);
  // Keep the lens in the same tonal family as the page. A very small primary
  // lift prevents transparent AppBars from falling back to a detached gray
  // disk while still letting the backdrop show through the glass.
  return Color.alphaBlend(
    colorScheme.primary.withValues(
      alpha: colorScheme.brightness == Brightness.dark ? 0.08 : 0.045,
    ),
    base,
  );
}

bool _floatingAppBarIsDark(ColorScheme colorScheme, Color? backgroundColor) {
  // A transparent Color has black RGB channels. Reading its raw luminance
  // classifies a light page's transparent AppBar as dark and paints a dark
  // circle behind its leading and action icons.
  return _floatingAppBarResolvedBackground(
        colorScheme,
        backgroundColor,
      ).computeLuminance() <
      0.22;
}
