part of '../floating_glass_control.dart';

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
  return (1.0 - (settings.currentExtent - settings.minExtent) / range).clamp(
    0.0,
    1.0,
  );
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
    final groupedChild = BackdropGroup(child: child);
    return ValueListenableBuilder<bool>(
      valueListenable: AndroidWindowRenderingPolicy.disableShaderContentFade,
      child: groupedChild,
      builder: (context, disableShader, child) {
        // Android 17 freeform windows can drop the entire TextureView subtree
        // when a destination-in mask is involved. The top bar remains a
        // foreground layer, so keeping the scroll content unmasked is the
        // safest fallback and prevents the page from becoming blank.
        if (disableShader) return child!;

        return _FloatingGlassTopBarContentFadeBox(
          fadeHeight: topBarHeight <= 0.0 ? 0.0 : topBarHeight + tailExtent,
          child: child,
        );
      },
    );
  }
}

/// Applies the pinned-header alpha fade only to the top fade band.
///
/// A normal [ShaderMask] allocates its blend layer for the full scrollable
/// viewport even though this gradient becomes fully opaque below the toolbar.
/// Restricting the mask rectangle to the fade band preserves the same result
/// while avoiding a full-screen offscreen blend on every scroll frame.
class _FloatingGlassTopBarContentFadeBox extends SingleChildRenderObjectWidget {
  const _FloatingGlassTopBarContentFadeBox({
    required this.fadeHeight,
    required super.child,
  });

  final double fadeHeight;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _RenderFloatingGlassTopBarContentFadeBox(fadeHeight: fadeHeight);
  }

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderFloatingGlassTopBarContentFadeBox renderObject,
  ) {
    renderObject.fadeHeight = fadeHeight;
  }
}

class _RenderFloatingGlassTopBarContentFadeBox extends RenderProxyBox {
  _RenderFloatingGlassTopBarContentFadeBox({required this._fadeHeight});

  @override
  ShaderMaskLayer? get layer => super.layer as ShaderMaskLayer?;

  double _fadeHeight;
  Shader? _cachedShader;
  double? _cachedWidth;
  double? _cachedMaskHeight;

  double get fadeHeight => _fadeHeight;

  set fadeHeight(double value) {
    if (_fadeHeight == value) return;
    final wasZero = _fadeHeight <= 0.0;
    final isZero = value <= 0.0;
    _fadeHeight = value;
    _cachedShader = null;
    if (wasZero != isZero) {
      markNeedsCompositingBitsUpdate();
    }
    markNeedsPaint();
  }

  @override
  bool get alwaysNeedsCompositing =>
      child != null &&
      _fadeHeight > 0.0 &&
      !AndroidWindowRenderingPolicy.disableShaderContentFade.value;

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    AndroidWindowRenderingPolicy.disableShaderContentFade.addListener(
      _handleRenderingPolicyChanged,
    );
  }

  @override
  void detach() {
    AndroidWindowRenderingPolicy.disableShaderContentFade.removeListener(
      _handleRenderingPolicyChanged,
    );
    _cachedShader = null;
    super.detach();
  }

  void _handleRenderingPolicyChanged() {
    markNeedsCompositingBitsUpdate();
    markNeedsPaint();
  }

  Shader _resolveShader(double width, double maskHeight) {
    if (_cachedShader != null &&
        _cachedWidth == width &&
        _cachedMaskHeight == maskHeight) {
      return _cachedShader!;
    }
    _cachedWidth = width;
    _cachedMaskHeight = maskHeight;
    return _cachedShader = floatingGlassTopBarContentFadeShader(
      Rect.fromLTWH(0.0, 0.0, width, maskHeight),
      fadeHeight: maskHeight,
    );
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final child = this.child;
    if (child == null) return;

    if (AndroidWindowRenderingPolicy.disableShaderContentFade.value) {
      layer = null;
      context.paintChild(child, offset);
      return;
    }

    final maskHeight = math.min(size.height, math.max(0.0, _fadeHeight));
    if (size.width <= 0.0 || maskHeight <= 0.0) {
      layer = null;
      context.paintChild(child, offset);
      return;
    }

    final maskRect = Rect.fromLTWH(
      offset.dx,
      offset.dy,
      size.width,
      maskHeight,
    );
    layer ??= ShaderMaskLayer();
    layer!
      ..shader = _resolveShader(size.width, maskHeight)
      ..maskRect = maskRect
      ..blendMode = BlendMode.dstIn;
    context.pushLayer(layer!, super.paint, offset);
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
  if (!standalone) return RepaintBoundary(child: child);

  return RepaintBoundary(
    child: FloatingGlassTopBarContentFade(
      topBarHeight: topBarHeight,
      tailExtent: tailExtent,
      child: child,
    ),
  );
}

/// Applies the same alpha fade to a group of slivers while leaving a pinned
/// [FloatingGlassSliverAppBar] outside the mask. Android 17 freeform windows
/// switch the render object to an unmasked path through the shared policy.
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
  void updateRenderObject(BuildContext context, RenderObject renderObject) {
    (renderObject as _RenderFloatingGlassSliverContentFade).fadeHeight =
        topBarHeight + tailExtent;
  }
}

class _RenderFloatingGlassSliverContentFade extends RenderProxySliver {
  _RenderFloatingGlassSliverContentFade({required this._fadeHeight});

  double _fadeHeight;
  Shader? _cachedShader;
  double? _cachedWidth;
  double? _cachedMaskHeight;

  double get fadeHeight => _fadeHeight;

  set fadeHeight(double value) {
    if (_fadeHeight == value) return;
    final wasZero = _fadeHeight <= 0.0;
    final isZero = value <= 0.0;
    _fadeHeight = value;
    _cachedShader = null;
    if (wasZero != isZero) {
      markNeedsCompositingBitsUpdate();
    }
    markNeedsPaint();
  }

  @override
  bool get alwaysNeedsCompositing =>
      child != null &&
      _fadeHeight > 0.0 &&
      !AndroidWindowRenderingPolicy.disableShaderContentFade.value;

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    AndroidWindowRenderingPolicy.disableShaderContentFade.addListener(
      _handleRenderingPolicyChanged,
    );
  }

  @override
  void detach() {
    AndroidWindowRenderingPolicy.disableShaderContentFade.removeListener(
      _handleRenderingPolicyChanged,
    );
    _cachedShader = null;
    super.detach();
  }

  void _handleRenderingPolicyChanged() {
    markNeedsCompositingBitsUpdate();
    markNeedsPaint();
  }

  @override
  ShaderMaskLayer? get layer => super.layer as ShaderMaskLayer?;

  Shader _resolveShader(double width, double maskHeight) {
    if (_cachedShader != null &&
        _cachedWidth == width &&
        _cachedMaskHeight == maskHeight) {
      return _cachedShader!;
    }
    _cachedWidth = width;
    _cachedMaskHeight = maskHeight;
    return _cachedShader = floatingGlassTopBarContentFadeShader(
      Rect.fromLTWH(0.0, 0.0, width, maskHeight),
      fadeHeight: maskHeight,
    );
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final child = this.child;
    final geometry = child?.geometry;
    if (child == null || geometry == null || !geometry.visible) return;

    if (AndroidWindowRenderingPolicy.disableShaderContentFade.value) {
      context.paintChild(child, offset);
      return;
    }

    final viewportWidth = constraints.crossAxisExtent;
    final viewportHeight = constraints.viewportMainAxisExtent;
    if (viewportWidth <= 0.0 || viewportHeight <= 0.0) {
      context.paintChild(child, offset);
      return;
    }

    final maskHeight = math.min(viewportHeight, math.max(0.0, fadeHeight));
    if (maskHeight <= 0.0) {
      context.paintChild(child, offset);
      return;
    }

    final maskRect = Rect.fromLTWH(offset.dx, 0.0, viewportWidth, maskHeight);
    layer ??= ShaderMaskLayer();
    layer!
      ..shader = _resolveShader(viewportWidth, maskHeight)
      ..maskRect = maskRect
      ..blendMode = BlendMode.dstIn;
    context.pushLayer(layer!, super.paint, offset);
  }
}
