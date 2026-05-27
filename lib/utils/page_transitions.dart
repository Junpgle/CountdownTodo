import 'dart:ui' as ui show ImageFilter, lerpDouble;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _pageLayerCurve = Cubic(0.4, 0.65, 0.25, 1.0);
const _defaultPageLayerBackgroundScale = 0.875;
const _defaultPageLayerBackgroundMask = 0.24;
const _defaultPageLayerMaxBlur = 12.0;
const _defaultContainerContentStart = 0.28;
const _epsilon = 0.001;
const _predictiveBackMaxInteractiveProgress = 0.68;

class _AnimSettings {
  static bool enabled = true;
  static bool lazyLoad = true;
  static bool screenRadius = true;
  static bool layerBlur = false;
  static bool predictiveBack = true;
  static int duration = 500;
  static int pageLayerDepth = 60;
  static int containerContentStart = 28;

  static Future<void> load() async {
    try {
      final prefs = await _prefs();
      enabled = prefs.getBool('enable_animations') ?? true;
      lazyLoad = prefs.getBool('enable_lazy_load') ?? true;
      screenRadius = prefs.getBool('enable_screen_radius') ?? true;
      layerBlur = prefs.getBool('enable_layer_blur') ?? false;
      predictiveBack = prefs.getBool('enable_predictive_back') ?? true;
      duration = prefs.getInt('animation_duration') ?? 500;
      pageLayerDepth = prefs.getInt('page_layer_depth') ?? 60;
      containerContentStart = prefs.getInt('container_content_start') ?? 28;
    } catch (_) {}
  }

  static Future<SharedPreferences> _prefs() => SharedPreferences.getInstance();

  static bool get usePredictiveBack =>
      !kIsWeb &&
      defaultTargetPlatform == TargetPlatform.android &&
      predictiveBack;

  static double get depthFactor => (pageLayerDepth / 100).clamp(0.0, 1.0);

  static double get backgroundScale =>
      ui.lerpDouble(1.0, _defaultPageLayerBackgroundScale, depthFactor)!;

  static double get backgroundMask =>
      _defaultPageLayerBackgroundMask * depthFactor;

  static double get backgroundBlur =>
      layerBlur ? _defaultPageLayerMaxBlur * depthFactor : 0.0;

  static double get contentStart {
    final value = containerContentStart / 100;
    return value.clamp(0.0, 0.6);
  }
}

class PageTransitions {
  static Future<void> init() => _AnimSettings.load();

  static const PageTransitionsTheme theme = PageTransitionsTheme(
    builders: <TargetPlatform, PageTransitionsBuilder>{
      TargetPlatform.android: _PageLayerMaterialPageTransitionsBuilder(),
      TargetPlatform.iOS: _PageLayerMaterialPageTransitionsBuilder(),
      TargetPlatform.macOS: _PageLayerMaterialPageTransitionsBuilder(),
      TargetPlatform.windows: _PageLayerMaterialPageTransitionsBuilder(),
      TargetPlatform.linux: _PageLayerMaterialPageTransitionsBuilder(),
      TargetPlatform.fuchsia: _PageLayerMaterialPageTransitionsBuilder(),
    },
  );

  static Future<T?> pushFromRect<T>({
    required BuildContext context,
    required Widget page,
    required GlobalKey sourceKey,
    Rect? targetRect,
    BorderRadius targetBorderRadius = BorderRadius.zero,
    Color? sourceColor,
    BorderRadius sourceBorderRadius =
        const BorderRadius.all(Radius.circular(16)),
  }) async {
    await _AnimSettings.load();
    if (!context.mounted) {
      return null;
    }
    if (!_AnimSettings.enabled) {
      return Navigator.push(context, MaterialPageRoute(builder: (_) => page));
    }

    await Future.delayed(const Duration(milliseconds: 16));
    if (!context.mounted) {
      return null;
    }
    final renderBox =
        sourceKey.currentContext?.findRenderObject() as RenderBox?;

    if (renderBox == null || renderBox.size.isEmpty) {
      return Navigator.push(context, MaterialPageRoute(builder: (_) => page));
    }

    final position = renderBox.localToGlobal(Offset.zero);
    final rect = position & renderBox.size;
    final theme = Theme.of(context);
    final color = sourceColor ?? theme.colorScheme.surface;

    return Navigator.push<T>(
      context,
      ContainerTransformRoute<T>(
        page: page,
        sourceRect: rect,
        targetRect: targetRect,
        targetBorderRadius: targetBorderRadius,
        sourceColor: color,
        sourceBorderRadius: sourceBorderRadius,
      ),
    );
  }

  static Route<T> slideHorizontal<T>(Widget page) {
    return _SlideRoute<T>(page: page, mode: _PageLayerRouteMode.slideEnd);
  }

  static Route<T> slideUp<T>(Widget page) {
    return _SlideRoute<T>(page: page, mode: _PageLayerRouteMode.slideBottom);
  }

  static Route<T> fadeThrough<T>(Widget page) {
    return _FadeRoute<T>(page: page);
  }
}

enum _PageLayerRouteMode {
  scale,
  slideEnd,
  slideBottom,
  fade,
}

class _PageLayerMaterialPageTransitionsBuilder extends PageTransitionsBuilder {
  const _PageLayerMaterialPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (!_AnimSettings.enabled) {
      return child;
    }
    final transition = _PageLayerTransition(
      animation: animation,
      secondaryAnimation: secondaryAnimation,
      mode: _PageLayerRouteMode.scale,
      child: child,
    );
    if (!_AnimSettings.usePredictiveBack) {
      return transition;
    }
    return _PredictiveBackGestureBridge<T>(
      route: route,
      child: transition,
    );
  }
}

class _PredictiveBackGestureBridge<T> extends StatefulWidget {
  final PageRoute<T> route;
  final Widget child;

  const _PredictiveBackGestureBridge({
    required this.route,
    required this.child,
  });

  @override
  State<_PredictiveBackGestureBridge<T>> createState() =>
      _PredictiveBackGestureBridgeState<T>();
}

class _PredictiveBackGestureBridgeState<T>
    extends State<_PredictiveBackGestureBridge<T>> with WidgetsBindingObserver {
  bool get _canHandle =>
      _AnimSettings.usePredictiveBack &&
      widget.route.isCurrent &&
      widget.route.popGestureEnabled;

  double _routeProgressForBackGesture(PredictiveBackEvent backEvent) {
    final gestureProgress = backEvent.progress.clamp(0.0, 1.0);
    final visualPopProgress =
        gestureProgress * _predictiveBackMaxInteractiveProgress;
    return 1.0 - visualPopProgress;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  bool handleStartBackGesture(PredictiveBackEvent backEvent) {
    if (!_canHandle) {
      return false;
    }
    widget.route.handleStartBackGesture(
      progress: _routeProgressForBackGesture(backEvent),
    );
    return true;
  }

  @override
  void handleUpdateBackGestureProgress(PredictiveBackEvent backEvent) {
    if (!widget.route.isCurrent) {
      return;
    }
    widget.route.handleUpdateBackGestureProgress(
      progress: _routeProgressForBackGesture(backEvent),
    );
  }

  @override
  void handleCancelBackGesture() {
    if (!widget.route.isCurrent) {
      return;
    }
    widget.route.handleCancelBackGesture();
  }

  @override
  void handleCommitBackGesture() {
    if (!widget.route.isCurrent) {
      return;
    }
    final navigator = widget.route.navigator;
    if (navigator == null) {
      return;
    }

    // Flutter's default TransitionRoute implementation reverses from the
    // controller upper bound on commit. For this route, the predictive gesture
    // has already driven the controller to the correct progress, so popping
    // directly avoids a visible jump back to the fully-open page state.
    navigator.pop();
    navigator.didStopUserGesture();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _PageLayerTransition extends StatefulWidget {
  final Animation<double> animation;
  final Animation<double> secondaryAnimation;
  final _PageLayerRouteMode mode;
  final Widget child;

  const _PageLayerTransition({
    required this.animation,
    required this.secondaryAnimation,
    required this.mode,
    required this.child,
  });

  @override
  State<_PageLayerTransition> createState() => _PageLayerTransitionState();
}

class _PageLayerTransitionState extends State<_PageLayerTransition>
    with WidgetsBindingObserver {
  late CurvedAnimation _routeCurve;
  late CurvedAnimation _backgroundCurve;
  late Listenable _mergedAnimation;

  // Cached MediaQuery values — avoid calling MediaQuery.of(context) every frame.
  double _cachedScreenRadius = 12.0;

  @override
  void initState() {
    super.initState();
    _initAnimations();
    _cacheMediaQuery();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeMetrics() {
    _cacheMediaQuery();
  }

  void _cacheMediaQuery() {
    final padding =
        WidgetsBinding.instance.platformDispatcher.views.first.padding;
    _cachedScreenRadius = padding.top > 30
        ? 24.0
        : padding.top > 20
            ? 16.0
            : 12.0;
  }

  @override
  void didUpdateWidget(covariant _PageLayerTransition oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.animation != widget.animation ||
        oldWidget.secondaryAnimation != widget.secondaryAnimation) {
      _disposeAnimations();
      _initAnimations();
    }
  }

  void _initAnimations() {
    _routeCurve = CurvedAnimation(
      parent: widget.animation,
      curve: _pageLayerCurve,
      reverseCurve: _pageLayerCurve,
    );
    _backgroundCurve = CurvedAnimation(
      parent: widget.secondaryAnimation,
      curve: _pageLayerCurve,
      reverseCurve: _pageLayerCurve,
    );
    _mergedAnimation = Listenable.merge(<Listenable>[
      _routeCurve,
      _backgroundCurve,
    ]);
  }

  void _disposeAnimations() {
    _routeCurve.dispose();
    _backgroundCurve.dispose();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _disposeAnimations();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _mergedAnimation,
      child: widget.child,
      builder: (context, child) {
        final backgroundProgress = _backgroundCurve.value.clamp(0.0, 1.0);
        final foregroundProgress = _routeCurve.value.clamp(0.0, 1.0);
        final isBackground = backgroundProgress > 0.0;

        Widget current = child ?? const SizedBox.shrink();

        if (isBackground) {
          current = _buildBackgroundPage(current, backgroundProgress);
        }

        if (foregroundProgress < 1.0 ||
            widget.animation.status == AnimationStatus.reverse) {
          current = _buildForegroundPage(current, foregroundProgress);
        }

        return current;
      },
    );
  }

  Widget _buildBackgroundPage(Widget child, double progress) {
    // Direct arithmetic — avoids ui.lerpDouble overhead.
    final bgScale = _AnimSettings.backgroundScale;
    final scale = 1.0 + (bgScale - 1.0) * progress;
    final blur = _AnimSettings.backgroundBlur * progress;
    final maskOpacity = _AnimSettings.backgroundMask * progress;
    final clip = _cachedScreenRadius * progress;

    Widget current = scale < 1.0 - _epsilon
        ? Transform.scale(scale: scale, child: child)
        : child;

    if (_AnimSettings.screenRadius && clip > 0.5) {
      current = ClipRRect(
        clipBehavior: Clip.hardEdge,
        borderRadius: BorderRadius.circular(clip),
        child: current,
      );
    }

    if (blur > 0.01) {
      current = ImageFiltered(
        imageFilter: ui.ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: current,
      );
    }

    if (maskOpacity <= _epsilon) return current;

    return DecoratedBox(
      position: DecorationPosition.foreground,
      decoration: BoxDecoration(
        color: Color.fromRGBO(0, 0, 0, maskOpacity),
      ),
      child: current,
    );
  }

  Widget _buildForegroundPage(Widget child, double progress) {
    final eased = progress;
    final corner = _cachedScreenRadius * (1.0 - eased);
    Widget current = child;

    if (_AnimSettings.screenRadius && corner > 0.5) {
      current = ClipRRect(
        clipBehavior: Clip.hardEdge,
        borderRadius: BorderRadius.circular(corner),
        child: current,
      );
    }

    switch (widget.mode) {
      case _PageLayerRouteMode.scale:
        // Direct arithmetic: scale = 0.92 + 0.08 * eased
        final scale = 0.92 + 0.08 * eased;
        final opacity = 0.75 + 0.25 * eased;
        if (scale < 1.0 - _epsilon) {
          current = Transform.scale(
            scale: scale,
            alignment: const Alignment(0, -0.45),
            child: current,
          );
        }
        return opacity < 1.0 - _epsilon
            ? FadeTransition(
                opacity: AlwaysStoppedAnimation(opacity),
                child: current,
              )
            : current;
      case _PageLayerRouteMode.slideEnd:
      case _PageLayerRouteMode.slideBottom:
        final isEnd = widget.mode == _PageLayerRouteMode.slideEnd;
        // Direct arithmetic: offset component = 1.0 - eased
        final d = 1.0 - eased;
        if (d > _epsilon) {
          current = FractionalTranslation(
            translation: isEnd ? Offset(d, 0.0) : Offset(0.0, d),
            child: current,
          );
        }
        final opacity = 0.9 + 0.1 * eased;
        return opacity < 1.0 - _epsilon
            ? FadeTransition(
                opacity: AlwaysStoppedAnimation(opacity),
                child: current,
              )
            : current;
      case _PageLayerRouteMode.fade:
        return eased < 1.0 - _epsilon
            ? FadeTransition(
                opacity: AlwaysStoppedAnimation(eased),
                child: current,
              )
            : current;
    }
  }
}

class ContainerTransformRoute<T> extends PageRouteBuilder<T> {
  final Widget page;
  final Rect sourceRect;
  final Rect? targetRect;
  final BorderRadius targetBorderRadius;
  final Color sourceColor;
  final BorderRadius sourceBorderRadius;

  ContainerTransformRoute({
    required this.page,
    required this.sourceRect,
    required this.sourceColor,
    this.targetRect,
    this.targetBorderRadius = BorderRadius.zero,
    this.sourceBorderRadius = const BorderRadius.all(Radius.circular(16)),
  }) : super(
          pageBuilder: (context, animation, secondaryAnimation) => page,
          transitionDuration: Duration(milliseconds: _AnimSettings.duration),
          reverseTransitionDuration:
              Duration(milliseconds: (_AnimSettings.duration * 0.75).round()),
        );

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final transition = _ContainerTransformWidget(
      animation: animation,
      secondaryAnimation: secondaryAnimation,
      sourceRect: sourceRect,
      targetRect: targetRect,
      targetBorderRadius: targetBorderRadius,
      sourceColor: sourceColor,
      sourceBorderRadius: sourceBorderRadius,
      child: child,
    );
    if (!_AnimSettings.usePredictiveBack) {
      return transition;
    }
    return _PredictiveBackGestureBridge<T>(
      route: this,
      child: transition,
    );
  }
}

class _ContainerTransformWidget extends StatefulWidget {
  final Animation<double> animation;
  final Animation<double> secondaryAnimation;
  final Rect sourceRect;
  final Rect? targetRect;
  final BorderRadius targetBorderRadius;
  final Color sourceColor;
  final BorderRadius sourceBorderRadius;
  final Widget child;

  const _ContainerTransformWidget({
    required this.animation,
    required this.secondaryAnimation,
    required this.sourceRect,
    this.targetRect,
    this.targetBorderRadius = BorderRadius.zero,
    required this.sourceColor,
    required this.sourceBorderRadius,
    required this.child,
  });

  @override
  State<_ContainerTransformWidget> createState() =>
      _ContainerTransformWidgetState();
}

class _ContainerTransformWidgetState extends State<_ContainerTransformWidget>
    with WidgetsBindingObserver {
  bool _contentVisible = false;
  late final CurvedAnimation _forwardCurve;
  late final CurvedAnimation _backgroundCurve;
  late final Listenable _mergedAnimation;

  // Cached layout values — avoid MediaQuery.of(context) per frame.
  late Size _screenSize;
  late double _screenRadius;
  late double _contentStartThreshold;

  @override
  void initState() {
    super.initState();
    _forwardCurve = CurvedAnimation(
      parent: widget.animation,
      curve: _pageLayerCurve,
      reverseCurve: _pageLayerCurve,
    );
    _backgroundCurve = CurvedAnimation(
      parent: widget.secondaryAnimation,
      curve: _pageLayerCurve,
      reverseCurve: _pageLayerCurve,
    );
    _mergedAnimation = Listenable.merge(
      <Listenable>[_forwardCurve, _backgroundCurve],
    );
    _contentStartThreshold = _AnimSettings.lazyLoad
        ? _AnimSettings.contentStart
        : _defaultContainerContentStart;
    _cacheScreenMetrics();
    WidgetsBinding.instance.addObserver(this);
    if (_AnimSettings.lazyLoad) {
      Future.delayed(
          Duration(milliseconds: (_AnimSettings.duration * 0.12).round()), () {
        if (mounted) setState(() => _contentVisible = true);
      });
    } else {
      _contentVisible = true;
    }
  }

  @override
  void didChangeMetrics() {
    _cacheScreenMetrics();
  }

  void _cacheScreenMetrics() {
    final view = WidgetsBinding.instance.platformDispatcher.views.first;
    _screenSize = view.physicalSize / view.devicePixelRatio;
    final padding = view.padding;
    _screenRadius = padding.top > 30
        ? 24.0
        : padding.top > 20
            ? 16.0
            : 12.0;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _forwardCurve.dispose();
    _backgroundCurve.dispose();
    super.dispose();
  }

  // Pre-allocated matrix reused every gesture frame to avoid per-frame alloc.
  static final Matrix4 _gestureMatrix = Matrix4.identity();

  @override
  Widget build(BuildContext context) {
    // Pre-compute values that don't depend on animation t.
    final begin = widget.sourceRect;
    final end = widget.targetRect ??
        Rect.fromLTWH(0, 0, _screenSize.width, _screenSize.height);
    final beginR = widget.sourceBorderRadius;
    final endR = widget.targetBorderRadius;
    final useScreenRadius = _AnimSettings.screenRadius;
    final useLazyLoad = _AnimSettings.lazyLoad;
    final bgMask = _AnimSettings.backgroundMask;
    final contentStartThreshold = _contentStartThreshold;
    final screenWidth = _screenSize.width;
    final screenHeight = _screenSize.height;

    // Pre-compute deltas — direct arithmetic in builder instead of lerpDouble.
    final dLeft = end.left - begin.left;
    final dTop = end.top - begin.top;
    final dWidth = end.width - begin.width;
    final dHeight = end.height - begin.height;
    final halfWScreen = screenWidth / 2;
    final halfHScreen = screenHeight / 2;
    final invScreenWidth = 1.0 / screenWidth;
    final invContentRange = contentStartThreshold < 1.0
        ? 1.0 / (1.0 - contentStartThreshold)
        : 1.0;

    // Build content once — OverflowBox forces full-screen constraints so
    // responsive content never reflows during back gesture shrinking.
    // Cached as AnimatedBuilder.child so Flutter reuses across frames.
    final cachedContent = _contentVisible
        ? OverflowBox(
            alignment: Alignment.topLeft,
            maxWidth: screenWidth,
            maxHeight: screenHeight,
            child: RepaintBoundary(child: widget.child),
          )
        : null;

    return AnimatedBuilder(
      animation: _mergedAnimation,
      child: cachedContent,
      builder: (context, child) {
        final t = _forwardCurve.value;
        final backgroundProgress = _backgroundCurve.value;

        // Direct arithmetic — avoids ui.lerpDouble function call overhead.
        final left = begin.left + dLeft * t;
        final top = begin.top + dTop * t;
        final width = begin.width + dWidth * t;
        final height = begin.height + dHeight * t;

        final isReverse =
            widget.animation.status == AnimationStatus.reverse;

        final contentProgress =
            ((t - contentStartThreshold) * invContentRange).clamp(0.0, 1.0);
        final fadeIn = useLazyLoad ? contentProgress : 1.0;
        final maskOpacity = bgMask * backgroundProgress;

        // Build content layer — cached child (OverflowBox) avoids re-layout.
        Widget contentLayer = child ?? const SizedBox.shrink();

        if (isReverse) {
          // Gesture: single Transform with precomputed matrix (scale + translate).
          final s = width * invScreenWidth;
          final tx = left - halfWScreen + width / 2;
          final ty = top - halfHScreen + height / 2;
          _gestureMatrix
              .setValues(s, 0, 0, 0, 0, s, 0, 0, 0, 0, 1, 0, tx, ty, 0, 1);
          contentLayer = Transform(
            transform: _gestureMatrix,
            transformHitTests: false,
            child: contentLayer,
          );
        } else {
          // Forward: screen-radius clip + content scale + fade.
          if (useScreenRadius) {
            final corner = _screenRadius * (1.0 - t);
            if (corner > 0.5) {
              contentLayer = ClipRRect(
                clipBehavior: Clip.hardEdge,
                borderRadius: BorderRadius.circular(corner),
                child: contentLayer,
              );
            }
          }
          final contentScale = 0.96 + 0.04 * contentProgress;
          if (contentScale < 1.0 - _epsilon) {
            contentLayer = Transform.scale(
              scale: contentScale,
              alignment: const Alignment(0, -0.45),
              child: contentLayer,
            );
          }
          if (fadeIn < 1.0 - _epsilon) {
            contentLayer = FadeTransition(
              opacity: AlwaysStoppedAnimation(fadeIn),
              child: contentLayer,
            );
          }
        }

        // Mask overlay — skip widget when fully transparent.
        final maskWidget = maskOpacity > _epsilon
            ? ColoredBox(color: Color.fromRGBO(0, 0, 0, maskOpacity))
            : null;

        // Container border radius — direct Radius interpolation.
        final borderRadius = isReverse
            ? BorderRadius.zero
            : BorderRadius.only(
                topLeft: Radius.elliptical(
                    beginR.topLeft.x + (endR.topLeft.x - beginR.topLeft.x) * t,
                    beginR.topLeft.y +
                        (endR.topLeft.y - beginR.topLeft.y) * t),
                topRight: Radius.elliptical(
                    beginR.topRight.x +
                        (endR.topRight.x - beginR.topRight.x) * t,
                    beginR.topRight.y +
                        (endR.topRight.y - beginR.topRight.y) * t),
                bottomLeft: Radius.elliptical(
                    beginR.bottomLeft.x +
                        (endR.bottomLeft.x - beginR.bottomLeft.x) * t,
                    beginR.bottomLeft.y +
                        (endR.bottomLeft.y - beginR.bottomLeft.y) * t),
                bottomRight: Radius.elliptical(
                    beginR.bottomRight.x +
                        (endR.bottomRight.x - beginR.bottomRight.x) * t,
                    beginR.bottomRight.y +
                        (endR.bottomRight.y - beginR.bottomRight.y) * t),
              );

        Widget container = ColoredBox(
          color: widget.sourceColor,
          child: contentLayer,
        );
        if (!isReverse && borderRadius != BorderRadius.zero) {
          container = ClipRRect(
            clipBehavior: Clip.hardEdge,
            borderRadius: borderRadius,
            child: container,
          );
        }

        return Stack(
          fit: StackFit.expand,
          children: [
            if (maskWidget != null) maskWidget,
            Positioned(
              left: left,
              top: top,
              width: width,
              height: height,
              child: IgnorePointer(
                ignoring: !isReverse && fadeIn < 1.0,
                child: container,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _SlideRoute<T> extends PageRouteBuilder<T> {
  final Widget page;
  final _PageLayerRouteMode mode;

  _SlideRoute({required this.page, required this.mode})
      : super(
          pageBuilder: (context, animation, secondaryAnimation) => page,
          transitionDuration: Duration(milliseconds: _AnimSettings.duration),
          reverseTransitionDuration:
              Duration(milliseconds: (_AnimSettings.duration * 0.75).round()),
        );

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final transition = _SlideWidget(
      animation: animation,
      secondaryAnimation: secondaryAnimation,
      mode: mode,
      child: child,
    );
    if (!_AnimSettings.usePredictiveBack) {
      return transition;
    }
    return _PredictiveBackGestureBridge<T>(
      route: this,
      child: transition,
    );
  }
}

class _SlideWidget extends StatefulWidget {
  final Animation<double> animation;
  final Animation<double> secondaryAnimation;
  final _PageLayerRouteMode mode;
  final Widget child;

  const _SlideWidget({
    required this.animation,
    required this.secondaryAnimation,
    required this.mode,
    required this.child,
  });

  @override
  State<_SlideWidget> createState() => _SlideWidgetState();
}

class _SlideWidgetState extends State<_SlideWidget> {
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    if (_AnimSettings.lazyLoad) {
      Future.delayed(
          Duration(milliseconds: (_AnimSettings.duration * 0.2).round()), () {
        if (mounted) setState(() => _visible = true);
      });
    } else {
      _visible = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    return _PageLayerTransition(
      animation: widget.animation,
      secondaryAnimation: widget.secondaryAnimation,
      mode: widget.mode,
      child: _visible ? widget.child : const SizedBox.shrink(),
    );
  }
}

class _FadeRoute<T> extends PageRouteBuilder<T> {
  final Widget page;

  _FadeRoute({required this.page})
      : super(
          pageBuilder: (context, animation, secondaryAnimation) => page,
          transitionDuration: Duration(milliseconds: _AnimSettings.duration),
          reverseTransitionDuration:
              Duration(milliseconds: _AnimSettings.duration),
        );

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final transition = _PageLayerTransition(
      animation: animation,
      secondaryAnimation: secondaryAnimation,
      mode: _PageLayerRouteMode.fade,
      child: child,
    );
    if (!_AnimSettings.usePredictiveBack) {
      return transition;
    }
    return _PredictiveBackGestureBridge<T>(
      route: this,
      child: transition,
    );
  }
}
