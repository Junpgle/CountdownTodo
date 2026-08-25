import 'dart:ui' as ui show ImageFilter, lerpDouble;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'app_performance_monitor.dart';

const _pageLayerCurve = Cubic(0.4, 0.65, 0.25, 1.0);
const _defaultPageLayerBackgroundScale = 0.875;
const _defaultPageLayerBackgroundMask = 0.24;
const _defaultPageLayerMaxBlur = 12.0;
const _defaultContainerContentStart = 0.28;
const _epsilon = 0.001;
// Limit the maximum interactive progress for the predictive back gesture.
// 0.15 means the route progress drops from 1.0 to 0.85 (shrinks to 85%).
const _predictiveBackMaxInteractiveProgress = 0.50;

/// Raw progress of the predictive back gesture currently driving the
/// top-most route (0.0–1.0, 0.0 when idle). Only one gesture runs at a time,
/// so this is shared across all route transitions.
///
/// Two reasons this cannot be derived inside the transition itself:
/// 1. Flutter drives predictive back by assigning `_controller.value`
///    directly, so [AnimationStatus] stays completed during the drag and only
///    flips to reverse once the pop starts.
/// 2. The route curve eases out near 1.0, swallowing the small progress
///    deltas of a drag — corners must follow the raw gesture progress.
final ValueNotifier<double> _predictiveBackGestureProgress =
    ValueNotifier<double>(0.0);

class _AnimSettings {
  static bool enabled = true;
  static bool lazyLoad = true;
  static bool screenRadius = true;
  static bool layerBlur = false;
  static bool motionBlur = false;
  static bool predictiveBack = true;
  static int duration = 500;
  static int pageLayerDepth = 60;
  static int containerContentStart = 28;

  static Future<void> load() async {
    try {
      final prefs = await _prefs();
      final isAndroid =
          !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
      enabled = prefs.getBool('enable_animations') ?? true;
      lazyLoad = prefs.getBool('enable_lazy_load') ?? true;
      screenRadius = prefs.getBool('enable_screen_radius') ?? true;
      layerBlur = prefs.getBool('enable_layer_blur') ?? false;
      motionBlur = prefs.getBool('enable_motion_blur') ?? false;
      predictiveBack = prefs.getBool('enable_predictive_back') ?? true;
      // Android defaults to the performance-first profile. It keeps short,
      // useful transitions but avoids spending the first frames on expensive
      // layer composition on lower-end devices.
      duration = prefs.getInt('animation_duration') ?? (isAndroid ? 220 : 500);
      pageLayerDepth =
          prefs.getInt('page_layer_depth') ?? (isAndroid ? 18 : 60);
      containerContentStart =
          prefs.getInt('container_content_start') ?? (isAndroid ? 12 : 28);
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

  static double motionBlurFor(double progress) {
    if (!motionBlur) return 0.0;
    final clamped = progress.clamp(0.0, 1.0);
    final peak = 1.0 - ((clamped - 0.5).abs() * 2.0).clamp(0.0, 1.0);
    return 7.0 * peak;
  }

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
    AppPerformanceMonitor.setCurrentScreen(
      AppPerformanceMonitor.screenNameForWidget(page),
    );
    await _AnimSettings.load();
    if (!context.mounted) {
      return null;
    }
    if (!_AnimSettings.enabled) {
      return Navigator.push(context, material(builder: (_) => page));
    }

    await Future.delayed(const Duration(milliseconds: 16));
    if (!context.mounted) {
      return null;
    }
    final renderBox =
        sourceKey.currentContext?.findRenderObject() as RenderBox?;

    if (renderBox == null || renderBox.size.isEmpty) {
      return Navigator.push(context, material(builder: (_) => page));
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

  static MaterialPageRoute<T> material<T>({
    required WidgetBuilder builder,
    RouteSettings? settings,
    bool maintainState = true,
    bool fullscreenDialog = false,
    bool allowSnapshotting = true,
  }) {
    return _ConfiguredMaterialPageRoute<T>(
      builder: (context) {
        final page = builder(context);
        AppPerformanceMonitor.setCurrentScreen(
          AppPerformanceMonitor.screenNameForWidget(page),
        );
        return page;
      },
      settings: settings,
      maintainState: maintainState,
      fullscreenDialog: fullscreenDialog,
      allowSnapshotting: allowSnapshotting,
    );
  }

  static Route<T> slideHorizontal<T>(Widget page, {RouteSettings? settings}) {
    AppPerformanceMonitor.setCurrentScreen(
      AppPerformanceMonitor.screenNameForWidget(page),
    );
    return _SlideRoute<T>(
        page: page, mode: _PageLayerRouteMode.slideEnd, settings: settings);
  }

  static Route<T> slideUp<T>(Widget page, {RouteSettings? settings}) {
    AppPerformanceMonitor.setCurrentScreen(
      AppPerformanceMonitor.screenNameForWidget(page),
    );
    return _SlideRoute<T>(
        page: page, mode: _PageLayerRouteMode.slideBottom, settings: settings);
  }

  static Route<T> fadeThrough<T>(Widget page, {RouteSettings? settings}) {
    AppPerformanceMonitor.setCurrentScreen(
      AppPerformanceMonitor.screenNameForWidget(page),
    );
    return _FadeRoute<T>(page: page, settings: settings);
  }
}

class _ConfiguredMaterialPageRoute<T> extends MaterialPageRoute<T> {
  _ConfiguredMaterialPageRoute({
    required super.builder,
    super.settings,
    super.maintainState,
    super.fullscreenDialog,
    super.allowSnapshotting,
  });

  @override
  Duration get transitionDuration => _AnimSettings.enabled
      ? Duration(milliseconds: _AnimSettings.duration)
      : Duration.zero;

  @override
  Duration get reverseTransitionDuration => _AnimSettings.enabled
      ? Duration(milliseconds: (_AnimSettings.duration * 0.75).round())
      : Duration.zero;
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

  /// Whether this bridge started the current gesture. The raw progress stays
  /// above zero through the committed pop so the exit transition keeps its
  /// rounded corners, and is reset when this route's subtree is disposed.
  bool _ownsGesture = false;

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
    if (_ownsGesture) {
      _ownsGesture = false;
      // Unmount runs while the widget tree is locked — notifying listeners
      // (live transitions below this route) here would throw. Defer the
      // reset to the end of the frame.
      final ValueNotifier<double> progress = _predictiveBackGestureProgress;
      if (progress.value > 0.0) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          progress.value = 0.0;
        });
      }
    }
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _setGestureProgress(PredictiveBackEvent backEvent) {
    _predictiveBackGestureProgress.value =
        backEvent.progress.clamp(0.0, 1.0);
  }

  @override
  bool handleStartBackGesture(PredictiveBackEvent backEvent) {
    if (!_canHandle) {
      return false;
    }
    _ownsGesture = true;
    _setGestureProgress(backEvent);
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
    if (_ownsGesture) {
      _setGestureProgress(backEvent);
    }
    widget.route.handleUpdateBackGestureProgress(
      progress: _routeProgressForBackGesture(backEvent),
    );
  }

  @override
  void handleCancelBackGesture() {
    if (_ownsGesture) {
      _predictiveBackGestureProgress.value = 0.0;
      _ownsGesture = false;
    }
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

  // Cached _AnimSettings values.
  late double _bgScale;
  late double _bgBlur;
  late double _bgMask;
  late bool _useScreenRadius;
  late bool _useMotionBlur;

  /// 懒加载揭示闩锁：转场期间显示占位遮罩，入场动画完成（页面已完成构建
  /// 与首帧挂载）后揭示真实内容。一旦揭示不再回退——预测返回手势会让
  /// 动画短暂回到 forward 状态，不能因此重新遮住页面。
  bool _revealed = false;

  // Frame-skip cache.
  double _lastRoute = -1;
  double _lastBg = -1;
  double _lastGestureProgress = -1;
  Widget? _cachedFrame;

  @override
  void initState() {
    super.initState();
    _initAnimations();
    _cacheSettings();
    _cacheMediaQuery();
    // 懒加载开启时，入场转场先用占位遮罩；动画已完成（例如从后台恢复的
    // 页面）则直接揭示。
    _revealed =
        !_AnimSettings.lazyLoad || _isEntranceAlreadyComplete;
    WidgetsBinding.instance.addObserver(this);
  }

  bool get _isEntranceAlreadyComplete =>
      widget.animation.status == AnimationStatus.completed;

  void _cacheSettings() {
    _bgScale = _AnimSettings.backgroundScale;
    _bgBlur = _AnimSettings.backgroundBlur;
    _bgMask = _AnimSettings.backgroundMask;
    _useScreenRadius = _AnimSettings.screenRadius;
    _useMotionBlur = _AnimSettings.motionBlur;
  }

  @override
  void didChangeMetrics() {
    _cacheMediaQuery();
    _lastRoute = -1;
    _lastBg = -1;
    _lastGestureProgress = -1;
    _cachedFrame = null;
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
      _lastRoute = -1;
      _lastBg = -1;
      _lastGestureProgress = -1;
      _cachedFrame = null;
    } else if (oldWidget.child != widget.child ||
        oldWidget.mode != widget.mode) {
      _lastRoute = -1;
      _lastBg = -1;
      _lastGestureProgress = -1;
      _cachedFrame = null;
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
      // Rebuild when a predictive back gesture starts, moves or ends — the
      // raw progress drives clipping independently of the eased route value.
      _predictiveBackGestureProgress,
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
    // 懒加载：入场转场未完成前，先渲染占位遮罩层（类似原生启动页），
    // 页面内容在遮罩下完成构建与首帧挂载，动画结束后整体揭示。
    if (!_revealed) {
      return AnimatedBuilder(
        animation: widget.animation,
        builder: (context, _) {
          if (_isEntranceAlreadyComplete) {
            _revealed = true;
          }
          return _revealed
              ? _buildRevealedBody()
              : _buildLazyPlaceholder(context);
        },
      );
    }
    return _buildRevealedBody();
  }

  Widget _buildRevealedBody() {
    // Wrap child ONCE outside builder — Flutter caches this as the
    // AnimatedBuilder.child parameter across frames.
    final wrappedChild = RepaintBoundary(child: widget.child);

    return AnimatedBuilder(
      animation: _mergedAnimation,
      child: wrappedChild,
      builder: (context, child) {
        final routeVal = _routeCurve.value;
        final bgVal = _backgroundCurve.value;
        final gestureProgress = _predictiveBackGestureProgress.value;

        // Frame-skip — return cached widget when animation is idle.
        if (routeVal == _lastRoute &&
            bgVal == _lastBg &&
            gestureProgress == _lastGestureProgress &&
            _cachedFrame != null) {
          return _cachedFrame!;
        }
        _lastRoute = routeVal;
        _lastBg = bgVal;
        _lastGestureProgress = gestureProgress;

        final backgroundProgress = bgVal.clamp(0.0, 1.0);
        final foregroundProgress = routeVal.clamp(0.0, 1.0);
        final isBackground = backgroundProgress > 0.0;

        Widget current = child ?? const SizedBox.shrink();

        if (isBackground) {
          final isReverse = widget.animation.status == AnimationStatus.reverse;
          current = _buildBackgroundPage(current, backgroundProgress,
              isReverse: isReverse);
        }

        if (foregroundProgress < 1.0 ||
            widget.animation.status == AnimationStatus.reverse ||
            gestureProgress > 0.0) {
          current = _buildForegroundPage(
            current,
            foregroundProgress,
            gestureProgress: gestureProgress,
          );
        }

        _cachedFrame = current;
        return current;
      },
    );
  }

  Widget _buildBackgroundPage(Widget child, double progress,
      {required bool isReverse}) {
    // Direct arithmetic with cached settings — avoids per-frame getter calls.
    final scale = 1.0 + (_bgScale - 1.0) * progress;
    final maskOpacity = _bgMask * progress;

    Widget current = scale < 1.0 - _epsilon
        ? Transform.scale(scale: scale, child: child)
        : child;

    // Skip expensive ClipRRect + blur during reverse (pop) animation.
    if (!isReverse) {
      final clip = _cachedScreenRadius * progress;
      if (_useScreenRadius && clip > 0.5) {
        current = ClipRRect(
          clipBehavior: Clip.hardEdge,
          borderRadius: BorderRadius.circular(clip),
          child: current,
        );
      }
      final blur = _bgBlur * progress;
      if (blur > 0.01) {
        current = ImageFiltered(
          imageFilter: ui.ImageFilter.blur(sigmaX: blur, sigmaY: blur),
          child: current,
        );
      }
    }

    if (maskOpacity <= _epsilon) return current;

    return Stack(
      fit: StackFit.expand,
      children: [
        current,
        IgnorePointer(
          child: ColoredBox(color: Color.fromRGBO(0, 0, 0, maskOpacity)),
        ),
      ],
    );
  }

  Widget _buildForegroundPage(
    Widget child,
    double progress, {
    required double gestureProgress,
  }) {
    final eased = progress;
    Widget current = child;

    // Rounded corners follow the "screen radius" animation setting
    // (_AnimSettings.screenRadius). During a predictive back gesture the page
    // shrinks into a floating layer, so keep the clip through both the drag
    // and the committed pop — [AnimationStatus.reverse] alone cannot be used,
    // because Flutter drives the drag by setting the controller value while
    // the status stays completed.
    final isReverse = widget.animation.status == AnimationStatus.reverse;
    if (_useScreenRadius && (!isReverse || gestureProgress > 0.0)) {
      final double cornerFactor;
      if (gestureProgress > 0.0) {
        // Follow the RAW gesture progress (not the eased route value, which
        // the curve flattens near 1.0): full screen radius at half drag,
        // held constant while the committed pop finishes.
        cornerFactor = (gestureProgress * 2.0).clamp(0.0, 1.0);
      } else {
        cornerFactor = (1.0 - eased).clamp(0.0, 1.0);
      }
      final corner = _cachedScreenRadius * cornerFactor;
      if (corner > 0.5) {
        current = ClipRRect(
          clipBehavior: Clip.hardEdge,
          borderRadius: BorderRadius.circular(corner),
          child: current,
        );
      }
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
        current = opacity < 1.0 - _epsilon
            ? FadeTransition(
                opacity: AlwaysStoppedAnimation(opacity),
                child: current,
              )
            : current;
        return _withMotionBlur(current, eased);
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
        current = opacity < 1.0 - _epsilon
            ? FadeTransition(
                opacity: AlwaysStoppedAnimation(opacity),
                child: current,
              )
            : current;
        return _withMotionBlur(current, eased);
      case _PageLayerRouteMode.fade:
        current = eased < 1.0 - _epsilon
            ? FadeTransition(
                opacity: AlwaysStoppedAnimation(eased),
                child: current,
              )
            : current;
        return _withMotionBlur(current, eased);
    }
  }

  Widget _withMotionBlur(Widget child, double progress) {
    if (!_useMotionBlur) return child;
    final sigma = _AnimSettings.motionBlurFor(progress);
    if (sigma <= 0.01) return child;
    return ImageFiltered(
      imageFilter: ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
      child: child,
    );
  }

  /// 占位遮罩层：类似原生启动页，转场期间先绘制一层主题化底色与图标，
  /// 避免在动画最重的阶段同步构建整个目标页面。
  Widget _buildLazyPlaceholder(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ColoredBox(
      key: const ValueKey('page-lazy-placeholder'),
      color: scheme.surface,
      child: Center(
        child: SizedBox(
          width: 64,
          height: 64,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: scheme.primary.withValues(alpha: 0.16)),
            ),
            child: Icon(
              Icons.blur_on_rounded,
              size: 30,
              color: scheme.primary.withValues(alpha: 0.45),
            ),
          ),
        ),
      ),
    );
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
          transitionDuration: _AnimSettings.enabled
              ? Duration(milliseconds: _AnimSettings.duration)
              : Duration.zero,
          reverseTransitionDuration: _AnimSettings.enabled
              ? Duration(milliseconds: (_AnimSettings.duration * 0.75).round())
              : Duration.zero,
        );

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (!_AnimSettings.enabled) {
      return child;
    }
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

class _ContainerTransformWidgetState extends State<_ContainerTransformWidget> {
  bool _contentVisible = false;
  late final CurvedAnimation _forwardCurve;
  late final CurvedAnimation _backgroundCurve;

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
    if (_AnimSettings.lazyLoad) {
      // 懒加载：容器变换动画期间只显示来源色遮罩盒（类似启动遮罩），
      // 入场动画完成后一次性揭示页面内容。
      _contentVisible = false;
      widget.animation.addStatusListener(_revealOnEntranceCompleted);
    } else {
      _contentVisible = true;
    }
  }

  void _revealOnEntranceCompleted(AnimationStatus status) {
    if (status != AnimationStatus.completed) return;
    widget.animation.removeStatusListener(_revealOnEntranceCompleted);
    if (mounted) setState(() => _contentVisible = true);
  }

  @override
  void dispose() {
    widget.animation.removeStatusListener(_revealOnEntranceCompleted);
    _forwardCurve.dispose();
    _backgroundCurve.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;

    return AnimatedBuilder(
      animation: Listenable.merge(
        <Listenable>[widget.animation, widget.secondaryAnimation],
      ),
      builder: (context, child) {
        final t = _forwardCurve.value.clamp(0.0, 1.0);
        final backgroundProgress = _backgroundCurve.value.clamp(0.0, 1.0);

        final begin = widget.sourceRect;
        final end = widget.targetRect ??
            Rect.fromLTWH(0, 0, screenSize.width, screenSize.height);

        final left = ui.lerpDouble(begin.left, end.left, t)!;
        final top = ui.lerpDouble(begin.top, end.top, t)!;
        final width = ui.lerpDouble(begin.width, end.width, t)!;
        final height = ui.lerpDouble(begin.height, end.height, t)!;

        final beginR = widget.sourceBorderRadius;
        final endR = widget.targetBorderRadius;
        final borderRadius = BorderRadius.only(
          topLeft: Radius.lerp(beginR.topLeft, endR.topLeft, t)!,
          topRight: Radius.lerp(beginR.topRight, endR.topRight, t)!,
          bottomLeft: Radius.lerp(beginR.bottomLeft, endR.bottomLeft, t)!,
          bottomRight: Radius.lerp(beginR.bottomRight, endR.bottomRight, t)!,
        );

        final contentStart = _AnimSettings.lazyLoad
            ? _AnimSettings.contentStart
            : _defaultContainerContentStart;
        final contentProgress =
            ((t - contentStart) / (1 - contentStart)).clamp(0.0, 1.0);
        final fadeIn = _AnimSettings.lazyLoad ? contentProgress : 1.0;
        final maskOpacity = ui.lerpDouble(
            0.0, _AnimSettings.backgroundMask, backgroundProgress)!;

        Widget content = RepaintBoundary(child: widget.child);

        // Morph into the button's shape for both opening and closing animations.
        // We scale the content so its width exactly matches the current box width.
        final scaleX = width / screenSize.width;

        content = Transform.scale(
          scale: scaleX,
          alignment: Alignment.topCenter,
          child: content,
        );

        if (fadeIn < 1.0 - _epsilon) {
          content = Opacity(opacity: fadeIn, child: content);
        }

        return Stack(
          fit: StackFit.expand,
          children: [
            if (maskOpacity > _epsilon)
              IgnorePointer(
                child: ColoredBox(
                  color: Colors.black.withValues(alpha: maskOpacity),
                ),
              ),
            Positioned(
              left: left,
              top: top,
              width: width,
              height: height,
              child: ClipRRect(
                borderRadius: borderRadius,
                child: ColoredBox(
                  color: widget.sourceColor,
                  child: _contentVisible
                      ? IgnorePointer(
                          ignoring: fadeIn < 1.0,
                          child: SizedBox(
                            width: screenSize.width,
                            height: screenSize.height,
                            child: content,
                          ),
                        )
                      : null,
                ),
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

  // ignore: use_super_parameters
  _SlideRoute({required this.page, required this.mode, RouteSettings? settings})
      : super(
          settings: settings,
          pageBuilder: (context, animation, secondaryAnimation) => page,
          transitionDuration: _AnimSettings.enabled
              ? Duration(milliseconds: _AnimSettings.duration)
              : Duration.zero,
          reverseTransitionDuration: _AnimSettings.enabled
              ? Duration(milliseconds: (_AnimSettings.duration * 0.75).round())
              : Duration.zero,
        );

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (!_AnimSettings.enabled) {
      return child;
    }
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
  @override
  Widget build(BuildContext context) {
    // 懒加载的占位与揭示由 _PageLayerTransition 统一处理。
    return _PageLayerTransition(
      animation: widget.animation,
      secondaryAnimation: widget.secondaryAnimation,
      mode: widget.mode,
      child: widget.child,
    );
  }
}

class _FadeRoute<T> extends PageRouteBuilder<T> {
  final Widget page;

  // ignore: use_super_parameters
  _FadeRoute({required this.page, RouteSettings? settings})
      : super(
          settings: settings,
          pageBuilder: (context, animation, secondaryAnimation) => page,
          transitionDuration: _AnimSettings.enabled
              ? Duration(milliseconds: _AnimSettings.duration)
              : Duration.zero,
          reverseTransitionDuration: _AnimSettings.enabled
              ? Duration(milliseconds: _AnimSettings.duration)
              : Duration.zero,
        );

  @override
  Widget buildTransitions(
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
