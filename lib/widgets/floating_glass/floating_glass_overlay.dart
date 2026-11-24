part of '../floating_glass_control.dart';

/// A shared liquid-glass shell for controls that visually float above content.
///
/// The child owns semantics and interaction. This widget owns the visual
/// treatment, responsive opt-out, spacing, and neutral fallback when Liquid
/// Glass is disabled. Keep this class as the single entry point for floating
/// bottom bars, action strips, and custom fixed controls.
class FloatingGlassControl extends StatelessWidget {
  const FloatingGlassControl({
    super.key,
    required this.child,
    this.fallback,
    this.height = 56,
    this.margin = EdgeInsets.zero,
    this.borderRadius = 28,
    this.tint,
    this.haloColor,
    this.haloOpacity,
    this.backerOpacity,
    this.useTopBarGlass = false,
    this.useLiquidGlass = true,
    this.isDark,
    this.mobilePortraitOnly = false,
    this.allowChildOverflow = false,
  });

  final Widget child;
  final Widget? fallback;

  /// A fixed height for compact controls. Leave it null when the child has a
  /// content-driven height, such as a chat composer or permission banner.
  final double? height;
  final EdgeInsetsGeometry margin;
  final double borderRadius;
  final Color? tint;
  final Color? haloColor;
  final double? haloOpacity;
  final double? backerOpacity;
  final bool useTopBarGlass;

  /// Keeps the shared geometry and material fallback while opting out of the
  /// shader/backdrop renderer. This is useful for interactive content such as
  /// editable fields on Android devices whose compositor cannot reliably
  /// composite a content-sized glass surface above the input connection.
  final bool useLiquidGlass;
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
    final resolvedTint =
        tint ??
        Color.alphaBlend(
          colorScheme.primary.withValues(alpha: 0.08),
          colorScheme.surface,
        ).withValues(alpha: dark ? 0.24 : 0.32);
    final resolvedHalo = haloColor ?? colorScheme.primary;
    final childWithoutNestedGlass = Theme(
      data: _floatingGlassChildTheme(context),
      child: child,
    );

    final fallbackWidget =
        fallback ??
        _FloatingGlassControlFallback(
          height: height,
          margin: margin,
          borderRadius: borderRadius,
          haloColor: resolvedHalo,
          isDark: dark,
          allowChildOverflow: allowChildOverflow,
          child: childWithoutNestedGlass,
        );

    if (!useLiquidGlass) return fallbackWidget;

    if (height == null) {
      return OptionalLiquidGlassPanel(
        margin: margin,
        borderRadius: borderRadius,
        tint: resolvedTint,
        isDark: dark,
        fallback: fallbackWidget,
        child: childWithoutNestedGlass,
      );
    }

    return OptionalLiquidGlassSurface(
      height: height!,
      margin: margin,
      borderRadius: borderRadius,
      tint: resolvedTint,
      haloColor: resolvedHalo,
      haloOpacity: haloOpacity,
      backerOpacity: backerOpacity,
      useTopBarGlass: useTopBarGlass,
      isDark: dark,
      allowChildOverflow: allowChildOverflow,
      fallback: fallbackWidget,
      child: childWithoutNestedGlass,
    );
  }
}

class _FloatingGlassAppBarScope
    extends InheritedNotifier<ValueNotifier<double>> {
  const _FloatingGlassAppBarScope({
    required ValueNotifier<double> collapseProgress,
    required super.child,
  }) : super(notifier: collapseProgress);

  static ValueNotifier<double>? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<_FloatingGlassAppBarScope>()
        ?.notifier;
  }
}

class _FloatingGlassAppBarHost extends StatefulWidget {
  const _FloatingGlassAppBarHost({
    required this.notificationPredicate,
    required this.builder,
    this.observeScroll = true,
    this.scrollDistance = _floatingGlassAppBarScrollDistance,
  });

  final ScrollNotificationPredicate notificationPredicate;
  final Widget Function(BuildContext, ValueNotifier<double>) builder;
  final bool observeScroll;
  final double scrollDistance;

  @override
  State<_FloatingGlassAppBarHost> createState() =>
      _FloatingGlassAppBarHostState();
}

class _FloatingGlassAppBarHostState extends State<_FloatingGlassAppBarHost> {
  final ValueNotifier<double> _collapseProgress = ValueNotifier<double>(0.0);
  ScrollNotificationObserverState? _scrollNotificationObserver;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final nextObserver = widget.observeScroll
        ? ScrollNotificationObserver.maybeOf(context)
        : null;
    if (nextObserver == _scrollNotificationObserver) return;

    _scrollNotificationObserver?.removeListener(_handleScrollNotification);
    _scrollNotificationObserver = nextObserver;
    _scrollNotificationObserver?.addListener(_handleScrollNotification);
  }

  @override
  void didUpdateWidget(covariant _FloatingGlassAppBarHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.observeScroll != widget.observeScroll ||
        oldWidget.notificationPredicate != widget.notificationPredicate ||
        oldWidget.scrollDistance != widget.scrollDistance) {
      final nextObserver = widget.observeScroll
          ? ScrollNotificationObserver.maybeOf(context)
          : null;
      _scrollNotificationObserver?.removeListener(_handleScrollNotification);
      _scrollNotificationObserver = nextObserver;
      _scrollNotificationObserver?.addListener(_handleScrollNotification);
    }
  }

  @override
  void dispose() {
    _scrollNotificationObserver?.removeListener(_handleScrollNotification);
    _collapseProgress.dispose();
    super.dispose();
  }

  void _handleScrollNotification(ScrollNotification notification) {
    if (!widget.notificationPredicate(notification)) return;
    if (notification is! ScrollUpdateNotification) return;

    final nextProgress = _floatingGlassAppBarProgressForMetrics(
      notification.metrics,
      scrollDistance: widget.scrollDistance,
    );
    if ((nextProgress - _collapseProgress.value).abs() > 0.001) {
      _collapseProgress.value = nextProgress;
    }
  }

  @override
  Widget build(BuildContext context) {
    return widget.builder(context, _collapseProgress);
  }
}

/// Shares the standard scroll-aware top-control state with a custom toolbar
/// that is laid out outside Flutter's [AppBar] or [SliverAppBar] slots.
class FloatingGlassScrollAware extends StatelessWidget {
  const FloatingGlassScrollAware({
    super.key,
    required this.child,
    this.notificationPredicate = defaultScrollNotificationPredicate,
  });

  final Widget child;
  final ScrollNotificationPredicate notificationPredicate;

  @override
  Widget build(BuildContext context) {
    return _FloatingGlassAppBarHost(
      notificationPredicate: notificationPredicate,
      builder: (context, collapseProgress) => _FloatingGlassAppBarScope(
        collapseProgress: collapseProgress,
        child: child,
      ),
    );
  }
}

/// Lays out a fixed header above a full-screen scrollable body.
///
/// The body receives the measured header height so it can add equivalent
/// initial scroll padding. That keeps the first frame unchanged while letting
/// later content travel underneath the header and its shared top fade.
class FloatingGlassPinnedHeaderLayout extends StatefulWidget {
  const FloatingGlassPinnedHeaderLayout({
    super.key,
    required this.header,
    required this.bodyBuilder,
    this.initialHeaderExtent = 0.0,
    this.fadeContent = true,
    this.fadeTailExtent = floatingGlassTopBarDefaultFadeTail,
  });

  final Widget header;
  final Widget Function(BuildContext context, double headerExtent) bodyBuilder;
  final double initialHeaderExtent;
  final bool fadeContent;
  final double fadeTailExtent;

  @override
  State<FloatingGlassPinnedHeaderLayout> createState() =>
      _FloatingGlassPinnedHeaderLayoutState();
}

class _FloatingGlassPinnedHeaderLayoutState
    extends State<FloatingGlassPinnedHeaderLayout> {
  double? _measuredHeaderExtent;
  double? _pendingHeaderExtent;
  bool _measureScheduled = false;

  void _handleHeaderExtentChanged(double nextExtent) {
    if (_measuredHeaderExtent != null &&
        (nextExtent - _measuredHeaderExtent!).abs() <= 0.5) {
      return;
    }
    _pendingHeaderExtent = nextExtent;
    if (_measureScheduled) return;
    _measureScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _measureScheduled = false;
      if (!mounted) return;
      final pending = _pendingHeaderExtent;
      if (pending == null) return;
      if (_measuredHeaderExtent == null ||
          (pending - _measuredHeaderExtent!).abs() > 0.5) {
        setState(() => _measuredHeaderExtent = pending);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final headerExtent =
        _measuredHeaderExtent ??
        widget.initialHeaderExtent.clamp(0.0, 2000.0).toDouble();
    final body = widget.bodyBuilder(context, headerExtent);
    final fadedBody = widget.fadeContent && headerExtent > 0.0
        ? FloatingGlassTopBarContentFade(
            topBarHeight: headerExtent,
            tailExtent: widget.fadeTailExtent,
            child: body,
          )
        : body;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(child: fadedBody),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: RepaintBoundary(
            child: FloatingGlassScrollAware(
              child: _FloatingGlassHeaderSizeObserver(
                onExtentChanged: _handleHeaderExtentChanged,
                child: widget.header,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _FloatingGlassHeaderSizeObserver extends SingleChildRenderObjectWidget {
  const _FloatingGlassHeaderSizeObserver({
    required this.onExtentChanged,
    required super.child,
  });

  final ValueChanged<double> onExtentChanged;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _RenderFloatingGlassHeaderSizeObserver(onExtentChanged);
  }

  @override
  void updateRenderObject(
    BuildContext context,
    covariant _RenderFloatingGlassHeaderSizeObserver renderObject,
  ) {
    renderObject.onExtentChanged = onExtentChanged;
  }
}

class _RenderFloatingGlassHeaderSizeObserver extends RenderProxyBox {
  _RenderFloatingGlassHeaderSizeObserver(this.onExtentChanged);

  ValueChanged<double> onExtentChanged;
  double? _lastReportedExtent;

  @override
  void performLayout() {
    super.performLayout();
    final nextExtent = size.height;
    if (_lastReportedExtent == null ||
        (nextExtent - _lastReportedExtent!).abs() > 0.5) {
      _lastReportedExtent = nextExtent;
      onExtentChanged(nextExtent);
    }
  }
}

/// A fixed top layer for scrollable screens whose content is painted after a
/// pinned sliver app bar.
///
/// A [BackdropFilter] inside a sliver is painted before the following content
/// sliver, so it cannot blur that content once it passes underneath the pinned
/// toolbar. This shared layer is placed above the scroll view by the caller;
/// it starts at the exact overlap point and ramps the blur in as content moves
/// farther under the top bar. [excludedRegions] keeps the native controls
/// above the effect instead of blurring the controls themselves.
class FloatingGlassTopBarOverlay extends StatefulWidget {
  const FloatingGlassTopBarOverlay({
    super.key,
    required this.height,
    required this.overlapStart,
    this.fadeExtent = 72.0,
    this.fadeTailExtent = 28.0,
    this.fadeFromTop = false,
    this.effectStrength = 1.0,
    this.blur = false,
    this.excludedRegions = const <Rect>[],
    this.notificationPredicate = defaultScrollNotificationPredicate,
    this.tint,
    this.isDark,
  });

  /// The pinned top-bar height, including the status-bar inset.
  final double height;

  /// Scroll offset at which the first body pixel reaches the pinned toolbar.
  final double overlapStart;

  /// Distance over which the top fade reaches its resting strength.
  final double fadeExtent;

  /// Extra transparent feather below the toolbar. It lets content fade out
  /// after crossing the toolbar edge instead of ending on a hard horizontal
  /// seam.
  final double fadeTailExtent;

  /// Paint the fade from the top edge downwards. This is useful for a fixed
  /// toolbar whose scrollable viewport starts immediately below it, where the
  /// content enters the effect from the viewport's top edge rather than from
  /// the bottom of a pinned sliver.
  final bool fadeFromTop;

  /// Scales the fade without changing when the effect starts. Lower values
  /// are useful over high-contrast wallpapers where a strong surface would
  /// hide too much of the content beneath it.
  final double effectStrength;

  /// Whether the overlay should blur the content behind it. The shared top-bar
  /// treatment is gradient-only by default; enable this only for a surface
  /// that explicitly needs the legacy blur treatment.
  final bool blur;

  /// Circular holes in the overlay for leading/action controls.
  final List<Rect> excludedRegions;

  final ScrollNotificationPredicate notificationPredicate;
  final Color? tint;
  final bool? isDark;

  @override
  State<FloatingGlassTopBarOverlay> createState() =>
      _FloatingGlassTopBarOverlayState();
}

class _FloatingGlassTopBarOverlayState
    extends State<FloatingGlassTopBarOverlay> {
  final ValueNotifier<double> _overlapProgress = ValueNotifier<double>(0.0);
  ScrollNotificationObserverState? _scrollNotificationObserver;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final nextObserver = ScrollNotificationObserver.maybeOf(context);
    if (nextObserver == _scrollNotificationObserver) return;

    _scrollNotificationObserver?.removeListener(_handleScrollNotification);
    _scrollNotificationObserver = nextObserver;
    _scrollNotificationObserver?.addListener(_handleScrollNotification);
  }

  @override
  void dispose() {
    _scrollNotificationObserver?.removeListener(_handleScrollNotification);
    _overlapProgress.dispose();
    super.dispose();
  }

  void _handleScrollNotification(ScrollNotification notification) {
    if (!widget.notificationPredicate(notification)) return;
    if (notification is! ScrollUpdateNotification &&
        notification is! OverscrollNotification &&
        notification is! ScrollMetricsNotification) {
      return;
    }

    final metrics = notification.metrics;
    if (metrics.axis != Axis.vertical) return;
    final fadeExtent = widget.fadeExtent.clamp(1.0, double.infinity);
    final nextProgress = ((metrics.pixels - widget.overlapStart) / fadeExtent)
        .clamp(0.0, 1.0);
    if ((nextProgress - _overlapProgress.value).abs() > 0.001) {
      _overlapProgress.value = nextProgress;
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<double>(
      valueListenable: _overlapProgress,
      builder: (context, progress, _) {
        if (progress <= 0.001) return const SizedBox.shrink();

        return IgnorePointer(child: _buildOverlay(context, progress));
      },
    );
  }

  Widget _buildOverlay(BuildContext context, double progress) {
    return ValueListenableBuilder<LiquidGlassEffectConfiguration>(
      valueListenable: LiquidGlassEffectService.configurationListenable,
      builder: (context, configuration, _) {
        // A gradient-only fade is a layout treatment, not a Liquid Glass
        // effect. Keep it available when the optional glass feature is off;
        // only the BackdropFilter variant depends on that feature switch.
        if (!configuration.enabled && widget.blur) {
          return const SizedBox.shrink();
        }

        final colorScheme = Theme.of(context).colorScheme;
        final dark = widget.isDark ?? colorScheme.brightness == Brightness.dark;
        final base = widget.tint ?? colorScheme.surface;
        final topColor = Color.alphaBlend(
          colorScheme.primary.withValues(alpha: dark ? 0.08 : 0.05),
          base,
        );
        final tailExtent = widget.fadeTailExtent.clamp(0.0, 200.0).toDouble();
        final totalHeight = widget.height + tailExtent;
        final bandHeight = math.min(
          totalHeight,
          widget.fadeFromTop
              ? 12.0 + progress * widget.fadeExtent
              : tailExtent + 12.0 + progress * widget.fadeExtent,
        );
        final bandTop = widget.fadeFromTop ? 0.0 : totalHeight - bandHeight;
        final effectStrength = widget.effectStrength.clamp(0.0, 1.0).toDouble();
        final blur = 3.0 + progress * 13.0 * effectStrength;
        final topAlpha = widget.blur
            ? (0.22 + progress * 0.66) * effectStrength
            : (0.04 + progress * 0.12) * effectStrength;
        final middleAlpha = widget.blur
            ? (0.08 + progress * 0.34) * effectStrength
            : (0.015 + progress * 0.04) * effectStrength;

        Widget surface = DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              stops: const [0.0, 0.54, 1.0],
              colors: [
                topColor.withValues(alpha: topAlpha),
                topColor.withValues(alpha: middleAlpha),
                topColor.withValues(alpha: 0),
              ],
            ),
          ),
          child: const SizedBox.expand(),
        );

        if (widget.blur) {
          surface = BackdropFilter.grouped(
            filter: AppImageFilters.quantizedClampedBlur(blur),
            child: surface,
          );
        }

        if (widget.excludedRegions.isNotEmpty) {
          surface = ClipPath(
            clipper: _FloatingGlassTopBarHoleClipper(
              widget.excludedRegions
                  .map((region) => region.shift(Offset(0, -bandTop)))
                  .toList(growable: false),
            ),
            child: surface,
          );
        } else {
          surface = ClipRect(child: surface);
        }

        return SizedBox(
          width: double.infinity,
          height: totalHeight,
          child: Align(
            alignment: Alignment.bottomCenter,
            child: SizedBox(
              width: double.infinity,
              height: bandHeight,
              child: surface,
            ),
          ),
        );
      },
    );
  }
}

class _FloatingGlassTopBarHoleClipper extends CustomClipper<Path> {
  const _FloatingGlassTopBarHoleClipper(this.holes);

  final List<Rect> holes;

  @override
  Path getClip(Size size) {
    final path = Path()..addRect(Offset.zero & size);
    for (final hole in holes) {
      path.addOval(hole);
    }
    path.fillType = PathFillType.evenOdd;
    return path;
  }

  @override
  bool shouldReclip(_FloatingGlassTopBarHoleClipper oldClipper) =>
      oldClipper.holes != holes;
}

class _FloatingGlassCollapseReporter extends StatelessWidget {
  const _FloatingGlassCollapseReporter({
    required this.collapseProgress,
    required this.child,
  });

  final ValueNotifier<double> collapseProgress;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final settings = context
        .dependOnInheritedWidgetOfExactType<FlexibleSpaceBarSettings>();
    if (settings != null) {
      final nextProgress = _floatingGlassAppBarProgressForFlexibleSpace(
        settings,
      );
      if ((nextProgress - collapseProgress.value).abs() > 0.001) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (context.mounted &&
              (nextProgress - collapseProgress.value).abs() > 0.001) {
            collapseProgress.value = nextProgress;
          }
        });
      }
    }
    return child;
  }
}
