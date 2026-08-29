import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../services/liquid_glass_effect_service.dart';
import '../utils/app_platform.dart';
import 'optional_liquid_glass_surface.dart';

/// Whether a floating control should use the phone portrait treatment.
///
/// The reference treatment is intentionally kept to phone-sized portrait
/// layouts. Wide windows and landscape layouts retain their normal geometry so
/// controls do not become cramped capsules on desktop or tablets.
@visibleForTesting
bool floatingBottomBarShouldFloatFor({
  required bool isMobile,
  required double width,
  required double height,
  double maxPhoneShortestSide = 600,
}) {
  final shortestSide = math.min(width, height);
  return isMobile && height > width && shortestSide < maxPhoneShortestSide;
}

/// The runtime phone-portrait check used by shared floating controls.
bool floatingBottomBarShouldFloat(BuildContext context) {
  final size = MediaQuery.sizeOf(context);
  return floatingBottomBarShouldFloatFor(
    isMobile: AppPlatform.isMobile,
    width: size.width,
    height: size.height,
  );
}

const double _floatingGlassAppBarScrollDistance = 72.0;
const double _floatingGlassAppBarControlThreshold = 0.58;

/// Shared diameter for compact floating controls.
///
/// Keeping this in the common control layer prevents app-bar actions and
/// dashboard quick actions from drifting into separate 40/48 dp systems.
const double floatingGlassStandardControlSize = 48.0;

/// Returns a native-looking icon-button style for controls that live in a
/// glass-enabled page but should not become glass themselves.
///
/// The explicit identity [ButtonStyle.backgroundBuilder] is important: a
/// page-level icon-button theme may otherwise add a second glass surface while
/// the caller is intentionally using a plain icon control.
ButtonStyle floatingGlassPlainIconButtonStyle() {
  return ButtonStyle(
    backgroundBuilder: (context, states, child) =>
        child ?? const SizedBox.shrink(),
    backgroundColor: const WidgetStatePropertyAll(Colors.transparent),
    side: const WidgetStatePropertyAll(BorderSide.none),
    elevation: const WidgetStatePropertyAll(0),
    shadowColor: const WidgetStatePropertyAll(Colors.transparent),
    surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
  );
}

double _floatingGlassAppBarProgressForMetrics(
  ScrollMetrics metrics, {
  double scrollDistance = _floatingGlassAppBarScrollDistance,
}) {
  if (metrics.axis != Axis.vertical) return 0.0;

  final offset = switch (metrics.axisDirection) {
    AxisDirection.up => metrics.extentAfter,
    AxisDirection.down => metrics.extentBefore,
    AxisDirection.left || AxisDirection.right => 0.0,
  };
  return (offset / math.max(1.0, scrollDistance)).clamp(0.0, 1.0);
}

double _floatingGlassAppBarProgressForFlexibleSpace(
  FlexibleSpaceBarSettings settings,
) {
  final range = settings.maxExtent - settings.minExtent;
  if (range <= 0.0) return 1.0;
  return (1.0 - (settings.currentExtent - settings.minExtent) / range)
      .clamp(0.0, 1.0);
}

/// The default feather below a shared top bar.
const double floatingGlassTopBarDefaultFadeTail = 36.0;

/// Resolves the full top-bar height, including the status-bar inset.
double floatingGlassTopBarHeight(
  BuildContext context, {
  double toolbarHeight = kToolbarHeight,
  PreferredSizeWidget? bottom,
  bool primary = true,
}) {
  final topInset = primary ? MediaQuery.paddingOf(context).top : 0.0;
  return topInset + toolbarHeight + (bottom?.preferredSize.height ?? 0.0);
}

/// Returns the initial scroll inset that keeps a standalone settings page's
/// first item in the same place after its body starts behind the top bar.
double floatingGlassSettingsContentTopInset(
  BuildContext context, {
  double extra = 0.0,
  PreferredSizeWidget? bottom,
}) {
  return floatingGlassTopBarHeight(context, bottom: bottom) + extra;
}

/// Resolves the platform status-bar appearance for a transparent top bar.
SystemUiOverlayStyle floatingGlassTopBarSystemOverlayStyle(
  BuildContext context,
) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  return SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
    statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
  );
}

/// Computes the reveal progress for a title that lives in the scrollable body.
///
/// [contentOffset] is the body's initial distance from the top of the
/// viewport. The title starts revealing [revealBefore] pixels before it
/// reaches the toolbar and settles [settleAfter] pixels after that point.
double floatingGlassTopBarTitleProgress({
  required double scrollOffset,
  required double contentOffset,
  double revealBefore = 36.0,
  double settleAfter = 10.0,
}) {
  final start = contentOffset - revealBefore;
  final end = contentOffset + settleAfter;
  return ((scrollOffset - start) / math.max(1.0, end - start)).clamp(0.0, 1.0);
}

/// Builds the alpha-only fade used when scrollable pixels pass under a fixed
/// top bar. It deliberately does not blur or paint a tinted rectangle.
Shader floatingGlassTopBarContentFadeShader(
  Rect bounds, {
  required double fadeHeight,
}) {
  final height = math.min(bounds.height, math.max(1.0, fadeHeight));
  return LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    stops: const [0.0, 0.18, 0.78, 1.0],
    colors: [
      Colors.transparent,
      Colors.transparent,
      Colors.white.withValues(alpha: 0.86),
      Colors.white,
    ],
  ).createShader(Rect.fromLTWH(0.0, 0.0, bounds.width, height));
}

/// Applies the shared content fade without changing the page background.
class FloatingGlassTopBarContentFade extends StatelessWidget {
  const FloatingGlassTopBarContentFade({
    super.key,
    required this.child,
    required this.topBarHeight,
    this.tailExtent = floatingGlassTopBarDefaultFadeTail,
  });

  final Widget child;
  final double topBarHeight;
  final double tailExtent;

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      blendMode: BlendMode.dstIn,
      shaderCallback: (bounds) => floatingGlassTopBarContentFadeShader(
        bounds,
        fadeHeight: topBarHeight + tailExtent,
      ),
      child: child,
    );
  }
}

/// Applies the shared top-bar fade only to standalone settings routes.
///
/// Settings pages are also embedded in the wide two-pane settings shell. In
/// that mode there is no route-level top bar to overlap the content, so the
/// body must remain untouched. Keeping this decision in one helper prevents
/// individual settings pages from drifting apart again.
Widget floatingGlassSettingsBody(
  BuildContext context, {
  required Widget child,
  required bool standalone,
  double topBarHeight = kToolbarHeight,
  double tailExtent = floatingGlassTopBarDefaultFadeTail,
}) {
  if (!standalone) return child;

  return FloatingGlassTopBarContentFade(
    topBarHeight: topBarHeight,
    tailExtent: tailExtent,
    child: child,
  );
}

/// Applies the same alpha fade to a group of slivers while leaving a pinned
/// [FloatingGlassSliverAppBar] outside the mask.
class FloatingGlassSliverContentFadeGroup extends StatelessWidget {
  const FloatingGlassSliverContentFadeGroup({
    super.key,
    required this.slivers,
    required this.topBarHeight,
    this.tailExtent = floatingGlassTopBarDefaultFadeTail,
  });

  final List<Widget> slivers;
  final double topBarHeight;
  final double tailExtent;

  @override
  Widget build(BuildContext context) {
    return FloatingGlassSliverContentFade(
      topBarHeight: topBarHeight,
      tailExtent: tailExtent,
      sliver: SliverMainAxisGroup(slivers: slivers),
    );
  }
}

/// Sliver render-object counterpart to [FloatingGlassTopBarContentFade].
class FloatingGlassSliverContentFade extends SingleChildRenderObjectWidget {
  const FloatingGlassSliverContentFade({
    super.key,
    required this.sliver,
    required this.topBarHeight,
    this.tailExtent = floatingGlassTopBarDefaultFadeTail,
  }) : super(child: sliver);

  final Widget sliver;
  final double topBarHeight;
  final double tailExtent;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _RenderFloatingGlassSliverContentFade(
      fadeHeight: topBarHeight + tailExtent,
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    RenderObject renderObject,
  ) {
    (renderObject as _RenderFloatingGlassSliverContentFade).fadeHeight =
        topBarHeight + tailExtent;
  }
}

class _RenderFloatingGlassSliverContentFade extends RenderProxySliver {
  _RenderFloatingGlassSliverContentFade({required double fadeHeight})
      : _fadeHeight = fadeHeight;

  double _fadeHeight;

  double get fadeHeight => _fadeHeight;

  set fadeHeight(double value) {
    if (_fadeHeight == value) return;
    _fadeHeight = value;
    markNeedsPaint();
  }

  @override
  bool get alwaysNeedsCompositing => child != null;

  @override
  ShaderMaskLayer? get layer => super.layer as ShaderMaskLayer?;

  @override
  void paint(PaintingContext context, Offset offset) {
    final child = this.child;
    final geometry = child?.geometry;
    if (child == null || geometry == null || !geometry.visible) return;

    final viewportWidth = constraints.crossAxisExtent;
    final viewportHeight = constraints.viewportMainAxisExtent;
    if (viewportWidth <= 0.0 || viewportHeight <= 0.0) {
      context.paintChild(child, offset);
      return;
    }

    final maskRect = Rect.fromLTWH(
      offset.dx,
      0.0,
      viewportWidth,
      viewportHeight,
    );
    layer ??= ShaderMaskLayer();
    layer!
      ..shader = floatingGlassTopBarContentFadeShader(
        Rect.fromLTWH(0.0, 0.0, viewportWidth, viewportHeight),
        fadeHeight: fadeHeight,
      )
      ..maskRect = maskRect
      ..blendMode = BlendMode.dstIn;
    context.pushLayer(layer!, super.paint, offset);
  }
}

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
    final resolvedTint = tint ??
        Color.alphaBlend(
          colorScheme.primary.withValues(alpha: 0.08),
          colorScheme.surface,
        ).withValues(alpha: dark ? 0.24 : 0.32);
    final resolvedHalo = haloColor ?? colorScheme.primary;

    final fallbackWidget = fallback ??
        _FloatingGlassControlFallback(
          height: height,
          margin: margin,
          borderRadius: borderRadius,
          haloColor: resolvedHalo,
          isDark: dark,
          allowChildOverflow: allowChildOverflow,
          child: child,
        );

    if (height == null) {
      return OptionalLiquidGlassPanel(
        margin: margin,
        borderRadius: borderRadius,
        tint: resolvedTint,
        isDark: dark,
        fallback: fallbackWidget,
        child: child,
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
      child: child,
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
/// later content travel underneath the header and its shared alpha fade.
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
  final GlobalKey _headerKey = GlobalKey();
  double? _measuredHeaderExtent;
  bool _measureScheduled = false;

  void _scheduleHeaderMeasurement() {
    if (_measureScheduled) return;
    _measureScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _measureScheduled = false;
      if (!mounted) return;

      final renderObject = _headerKey.currentContext?.findRenderObject();
      if (renderObject is! RenderBox || !renderObject.hasSize) return;
      final nextExtent = renderObject.size.height;
      if ((_measuredHeaderExtent == null ||
              (nextExtent - _measuredHeaderExtent!).abs() > 0.5) &&
          mounted) {
        setState(() => _measuredHeaderExtent = nextExtent);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    _scheduleHeaderMeasurement();
    final headerExtent = _measuredHeaderExtent ??
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
        Positioned.fill(
          child: fadedBody,
        ),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: KeyedSubtree(
            key: _headerKey,
            child: widget.header,
          ),
        ),
      ],
    );
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
    final nextProgress =
        ((metrics.pixels - widget.overlapStart) / fadeExtent).clamp(0.0, 1.0);
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

        return IgnorePointer(
          child: _buildOverlay(context, progress),
        );
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
          surface = BackdropFilter(
            filter: ui.ImageFilter.blur(
              sigmaX: blur,
              sigmaY: blur,
              tileMode: TileMode.clamp,
            ),
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
    final settings =
        context.dependOnInheritedWidgetOfExactType<FlexibleSpaceBarSettings>();
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
    return ValueListenableBuilder<double>(
      valueListenable: collapseProgress,
      builder: (context, value, _) {
        final transitionStart = math.max(0.0, floatingThreshold - 0.22);
        final transitionEnd = math.min(1.0, floatingThreshold + 0.22);
        final transitionRange =
            math.max(0.001, transitionEnd - transitionStart);
        final target =
            ((value - transitionStart) / transitionRange).clamp(0.0, 1.0);

        return TweenAnimationBuilder<double>(
          tween: Tween<double>(end: target),
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          builder: (context, progress, _) {
            return _buildForProgress(context, progress);
          },
        );
      },
    );
  }

  Widget _buildForProgress(BuildContext context, double progress) {
    final colorScheme = Theme.of(context).colorScheme;
    final resolvedTint = tint ?? _floatingAppBarTint(colorScheme, null);
    final nativeChild = Theme(
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

    return Padding(
      padding: margin,
      child: Center(
        child: SizedBox(
          width: size,
          height: size,
          child: Stack(
            alignment: Alignment.center,
            fit: StackFit.expand,
            children: [
              Visibility(
                visible: progress > 0.001,
                child: IgnorePointer(
                  child: Opacity(
                    opacity: progress,
                    child: Transform.scale(
                      scale: 0.82 + progress * 0.18,
                      child: ClipOval(
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
                          useTopBarGlass: useTopBarGlass,
                          isDark: isDark,
                          child: const SizedBox.shrink(),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Center(child: nativeChild),
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
    final glassTint = floatingControlTint ??
        _floatingAppBarTint(colorScheme, backgroundColor);
    final glassIsDark = floatingControlIsDark ??
        _floatingAppBarIsDark(
          colorScheme,
          backgroundColor,
        );
    final resolvedLeading = _resolveFloatingAppBarLeading(context);
    final resolvedActions = _resolveFloatingAppBarActions(context);
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
          (action) => _isFloatingGlassAppBarLayoutOnly(action) ||
                  action is FloatingGlassAppBarAction
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

    return _FloatingGlassAppBarHost(
      notificationPredicate: notificationPredicate,
      scrollDistance: floatingControlScrollDistance,
      builder: (context, collapseProgress) => _FloatingGlassAppBarScope(
        collapseProgress: collapseProgress,
        child: AppBar(
          leading: decoratedLeading,
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
          leadingWidth: leadingWidth ??
              (decoratedLeading == null ? null : _floatingAppBarLeadingWidth),
          toolbarTextStyle: toolbarTextStyle,
          titleTextStyle: titleTextStyle,
          systemOverlayStyle: resolvedSystemOverlayStyle,
          forceMaterialTransparency: resolvedForceMaterialTransparency,
          useDefaultSemanticsOrder: useDefaultSemanticsOrder,
          clipBehavior: clipBehavior,
          actionsPadding: actionsPadding ??
              (decoratedActions == null || decoratedActions.isEmpty
                  ? null
                  : _floatingAppBarActionsPadding),
          animateColor: animateColor,
        ),
      ),
    );
  }

  Widget? _resolveFloatingAppBarLeading(BuildContext context) {
    if (leading != null || !automaticallyImplyLeading) return leading;

    final scaffold = Scaffold.maybeOf(context);
    final route = ModalRoute.of(context);
    if (scaffold?.hasDrawer ?? false) {
      return DrawerButton(
        style: IconButton.styleFrom(iconSize: iconTheme?.size ?? 24),
      );
    }
    if (route?.impliesAppBarDismissal ?? false) {
      return route?.fullscreenDialog ?? false
          ? const CloseButton()
          : const BackButton();
    }
    return null;
  }

  List<Widget>? _resolveFloatingAppBarActions(BuildContext context) {
    if (actions != null && actions!.isNotEmpty) return actions;
    if (automaticallyImplyActions &&
        (Scaffold.maybeOf(context)?.hasEndDrawer ?? false)) {
      return <Widget>[
        EndDrawerButton(
          style: IconButton.styleFrom(iconSize: actionsIconTheme?.size ?? 24),
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

Color _floatingAppBarTint(ColorScheme colorScheme, Color? backgroundColor) {
  final base = backgroundColor == null || backgroundColor.a == 0
      ? colorScheme.surfaceContainerLow
      : backgroundColor;
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

bool _floatingAppBarIsDark(
  ColorScheme colorScheme,
  Color? backgroundColor,
) {
  return colorScheme.brightness == Brightness.dark ||
      (backgroundColor != null && backgroundColor.computeLuminance() < 0.22);
}

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
  })  : assert(floating || !snap),
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
  })  : assert(floating || !snap),
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
  })  : assert(floating || !snap),
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
    final glassTint = floatingControlTint ??
        _floatingAppBarTint(colorScheme, backgroundColor);
    final glassIsDark = floatingControlIsDark ??
        _floatingAppBarIsDark(
          colorScheme,
          backgroundColor,
        );
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
          (action) => _isFloatingGlassAppBarLayoutOnly(action) ||
                  action is FloatingGlassAppBarAction
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
    final effectiveLeadingWidth = leadingWidth ??
        (decoratedLeading == null ? null : _floatingAppBarLeadingWidth);
    final effectiveActionsPadding = actionsPadding ??
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
        style: IconButton.styleFrom(iconSize: iconTheme?.size ?? 24),
      );
    }
    if (route?.impliesAppBarDismissal ?? false) {
      return route?.fullscreenDialog ?? false
          ? const CloseButton()
          : const BackButton();
    }
    return null;
  }

  List<Widget>? _resolveFloatingSliverAppBarActions(BuildContext context) {
    if (actions != null && actions!.isNotEmpty) return actions;
    if (automaticallyImplyActions &&
        (Scaffold.maybeOf(context)?.hasEndDrawer ?? false)) {
      return <Widget>[
        EndDrawerButton(
          style: IconButton.styleFrom(iconSize: actionsIconTheme?.size ?? 24),
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
  })  : _extended = true,
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
  })  : _extended = false,
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

    final interactive = Semantics(
      button: true,
      enabled: enabled,
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
                          style:
                              Theme.of(context).textTheme.labelLarge!.copyWith(
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
                ),
        ),
      ),
    );

    Widget content = interactive;
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

    return FloatingGlassControl(
      height: 56,
      margin: margin,
      borderRadius: borderRadius,
      tint: resolvedTint.withValues(alpha: isDark ? 0.22 : 0.28),
      haloColor: resolvedTint,
      isDark: isDark,
      allowChildOverflow: false,
      fallback: fallback,
      child: content,
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
    if (scopedProgress == null) {
      return _buildBackground(
        context,
        progress: 0.0,
        useFlexibleSpaceSettings: false,
      );
    }

    return ValueListenableBuilder<double>(
      valueListenable: scopedProgress,
      builder: (context, progress, _) => _buildBackground(
        context,
        progress: progress,
        useFlexibleSpaceSettings: true,
      ),
    );
  }

  Widget _buildBackground(
    BuildContext context, {
    required double progress,
    required bool useFlexibleSpaceSettings,
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
        return LayoutBuilder(
          builder: (context, constraints) {
            final hasBoundedHeight = constraints.hasBoundedHeight;
            final content = hasBoundedHeight
                ? const SizedBox.expand()
                : SizedBox(
                    height: (unboundedHeight ??
                            kToolbarHeight + MediaQuery.paddingOf(context).top)
                        .clamp(0.0, 1000.0),
                  );

            if (blur && !configuration.enabled) return content;

            final intensity =
                (resolvedProgress * fadeExtent.clamp(0.0, 1.0)).clamp(0.0, 1.0);
            if (intensity <= 0.001) return content;

            final colorScheme = Theme.of(context).colorScheme;
            final dark = isDark ?? colorScheme.brightness == Brightness.dark;
            final base = tint ?? colorScheme.surface;
            final topColor = Color.alphaBlend(
              colorScheme.primary.withValues(alpha: dark ? 0.08 : 0.05),
              base,
            );
            final blurSigma = 10.0 + (intensity * 14.0);
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
                    topColor.withValues(
                      alpha: topAlpha * (dark ? 0.94 : 1.0),
                    ),
                    topColor.withValues(
                      alpha: middleAlpha * (dark ? 0.9 : 1.0),
                    ),
                    topColor.withValues(
                      alpha: lowerAlpha * (dark ? 0.9 : 1.0),
                    ),
                    topColor.withValues(alpha: 0),
                  ],
                ),
              ),
              child: content,
            );

            if (blur) {
              surface = BackdropFilter(
                filter: ui.ImageFilter.blur(
                  sigmaX: blurSigma,
                  sigmaY: blurSigma,
                  tileMode: TileMode.clamp,
                ),
                child: surface,
              );
            }

            return ClipRect(child: surface);
          },
        );
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
    final settings =
        context.dependOnInheritedWidgetOfExactType<FlexibleSpaceBarSettings>();
    final extent = settings == null
        ? 1.0
        : ((settings.currentExtent - settings.minExtent) /
                (settings.maxExtent - settings.minExtent))
            .clamp(0.0, 1.0);
    final colorScheme = Theme.of(context).colorScheme;
    final expandedStyle = Theme.of(context).textTheme.headlineMedium?.copyWith(
          color: colorScheme.onSurface,
        );

    return Stack(
      fit: StackFit.expand,
      children: [
        FloatingGlassTopBarBackground(tint: tint, isDark: isDark),
        Align(
          alignment: Alignment.bottomLeft,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
            child: Opacity(
              opacity: extent,
              child: expandedStyle == null
                  ? title
                  : DefaultTextStyle(style: expandedStyle, child: title),
            ),
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
  });

  final double? height;
  final EdgeInsetsGeometry margin;
  final double borderRadius;
  final Color haloColor;
  final bool isDark;
  final bool allowChildOverflow;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final decoration = BoxDecoration(
      color: isDark
          ? colorScheme.surfaceContainerHighest.withValues(alpha: 0.82)
          : colorScheme.surface.withValues(alpha: 0.9),
      borderRadius: BorderRadius.circular(borderRadius),
      border: Border.all(
        color: colorScheme.outlineVariant.withValues(
          alpha: isDark ? 0.42 : 0.54,
        ),
        width: 0.8,
      ),
      boxShadow: <BoxShadow>[
        BoxShadow(
          color: haloColor.withValues(alpha: isDark ? 0.12 : 0.2),
          blurRadius: 26,
          spreadRadius: 1,
          offset: const Offset(0, 4),
        ),
        BoxShadow(
          color: colorScheme.shadow.withValues(alpha: 0.12),
          blurRadius: 15,
          offset: const Offset(0, 5),
        ),
      ],
    );

    final content = Stack(
      fit: height == null ? StackFit.passthrough : StackFit.expand,
      clipBehavior: allowChildOverflow ? Clip.none : Clip.hardEdge,
      children: [
        // Keep the neutral fallback inexpensive on Android while preserving
        // the frosted read on platforms where a small bounded blur is cheap.
        if (!AppPlatform.isAndroid)
          Positioned.fill(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(borderRadius),
              child: BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                child: const SizedBox.expand(),
              ),
            ),
          ),
        child,
      ],
    );

    return Container(
      height: height,
      margin: margin,
      decoration: decoration,
      child: content,
    );
  }
}
