import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _springOut = Cubic(0.34, 1.2, 0.64, 1.0);
const _springIn = Cubic(0.5, 0.0, 0.75, 0.0);
const _springInOut = Cubic(0.38, 0.0, 0.22, 1.0);

class _AnimSettings {
  static bool enabled = true;
  static bool lazyLoad = true;
  static bool screenRadius = true;
  static int duration = 500;

  static Future<void> load() async {
    try {
      final prefs = await _prefs();
      enabled = prefs.getBool('enable_animations') ?? true;
      lazyLoad = prefs.getBool('enable_lazy_load') ?? true;
      screenRadius = prefs.getBool('enable_screen_radius') ?? true;
      duration = prefs.getInt('animation_duration') ?? 500;
    } catch (_) {}
  }

  static Future<void> save({
    bool? enabled,
    bool? lazyLoad,
    bool? screenRadius,
    int? duration,
  }) async {
    try {
      final prefs = await _prefs();
      if (enabled != null) {
        prefs.setBool('enable_animations', enabled);
        _AnimSettings.enabled = enabled;
      }
      if (lazyLoad != null) {
        prefs.setBool('enable_lazy_load', lazyLoad);
        _AnimSettings.lazyLoad = lazyLoad;
      }
      if (screenRadius != null) {
        prefs.setBool('enable_screen_radius', screenRadius);
        _AnimSettings.screenRadius = screenRadius;
      }
      if (duration != null) {
        prefs.setInt('animation_duration', duration);
        _AnimSettings.duration = duration;
      }
    } catch (_) {}
  }

  static Future<SharedPreferences> _prefs() => SharedPreferences.getInstance();
}

class PageTransitions {
  static Future<void> init() => _AnimSettings.load();

  static Future<T?> pushFromRect<T>({
    required BuildContext context,
    required Widget page,
    required GlobalKey sourceKey,
    Color? sourceColor,
    BorderRadius sourceBorderRadius =
        const BorderRadius.all(Radius.circular(16)),
  }) async {
    await _AnimSettings.load();
    if (!_AnimSettings.enabled) {
      return Navigator.push(context, MaterialPageRoute(builder: (_) => page));
    }

    await Future.delayed(const Duration(milliseconds: 16));
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
        sourceColor: color,
        sourceBorderRadius: sourceBorderRadius,
      ),
    );
  }

  static Route<T> slideHorizontal<T>(Widget page) {
    return _SlideRoute<T>(page: page, direction: Axis.horizontal);
  }

  static Route<T> slideUp<T>(Widget page) {
    return _SlideRoute<T>(page: page, direction: Axis.vertical);
  }

  static Route<T> fadeThrough<T>(Widget page) {
    return _FadeRoute<T>(page: page);
  }
}

class ContainerTransformRoute<T> extends PageRouteBuilder<T> {
  final Widget page;
  final Rect sourceRect;
  final Color sourceColor;
  final BorderRadius sourceBorderRadius;

  ContainerTransformRoute({
    required this.page,
    required this.sourceRect,
    required this.sourceColor,
    this.sourceBorderRadius = const BorderRadius.all(Radius.circular(16)),
  }) : super(
          pageBuilder: (context, animation, secondaryAnimation) => page,
          transitionDuration: Duration(milliseconds: _AnimSettings.duration),
          reverseTransitionDuration:
              Duration(milliseconds: (_AnimSettings.duration * 0.75).round()),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return _ContainerTransformWidget(
              animation: animation,
              secondaryAnimation: secondaryAnimation,
              sourceRect: sourceRect,
              sourceColor: sourceColor,
              sourceBorderRadius: sourceBorderRadius,
              child: child,
            );
          },
        );
}

class _ContainerTransformWidget extends StatefulWidget {
  final Animation<double> animation;
  final Animation<double> secondaryAnimation;
  final Rect sourceRect;
  final Color sourceColor;
  final BorderRadius sourceBorderRadius;
  final Widget child;

  const _ContainerTransformWidget({
    required this.animation,
    required this.secondaryAnimation,
    required this.sourceRect,
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

  @override
  void initState() {
    super.initState();
    if (_AnimSettings.lazyLoad) {
      Future.delayed(
          Duration(milliseconds: (_AnimSettings.duration * 0.3).round()), () {
        if (mounted) setState(() => _contentVisible = true);
      });
    } else {
      _contentVisible = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;

    return AnimatedBuilder(
      animation: widget.animation,
      builder: (context, child) {
        final tRaw = CurvedAnimation(
          parent: widget.animation,
          curve: _springOut,
          reverseCurve: _springIn,
        ).value;
        final t = tRaw.clamp(0.0, 1.0);
        final tBounce = tRaw.clamp(0.0, 1.0);

        final begin = widget.sourceRect;
        final end = Rect.fromLTWH(0, 0, screenSize.width, screenSize.height);

        final left = begin.left + (end.left - begin.left) * tBounce;
        final top = begin.top + (end.top - begin.top) * tBounce;
        final width = begin.width + (end.width - begin.width) * tBounce;
        final height = begin.height + (end.height - begin.height) * tBounce;

        final beginR = widget.sourceBorderRadius;
        final endR = BorderRadius.zero;
        final borderRadius = BorderRadius.only(
          topLeft: Radius.lerp(beginR.topLeft, endR.topLeft, t)!,
          topRight: Radius.lerp(beginR.topRight, endR.topRight, t)!,
          bottomLeft: Radius.lerp(beginR.bottomLeft, endR.bottomLeft, t)!,
          bottomRight: Radius.lerp(beginR.bottomRight, endR.bottomRight, t)!,
        );

        final fadeIn = _AnimSettings.lazyLoad
            ? (t < 0.35 ? 0.0 : ((t - 0.35) / 0.65).clamp(0.0, 1.0))
            : 1.0;

        Widget? deviceClip;
        if (_AnimSettings.screenRadius) {
          final pad = MediaQuery.of(context).padding;
          final r = pad.top > 30
              ? 24.0
              : pad.top > 20
                  ? 16.0
                  : 0.0;
          if (r > 0) {
            deviceClip = ClipRRect(
              borderRadius: BorderRadius.circular(r),
              child: widget.child,
            );
          }
        }

        final content = deviceClip ?? widget.child;

        return Stack(
          fit: StackFit.expand,
          children: [
            Positioned(
              left: left,
              top: top,
              width: width,
              height: height,
              child: ClipRRect(
                borderRadius: borderRadius,
                child: Container(color: widget.sourceColor),
              ),
            ),
            if (_contentVisible)
              Positioned.fill(
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 100),
                  opacity: fadeIn,
                  child: IgnorePointer(ignoring: fadeIn < 1.0, child: content),
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
  final Axis direction;

  _SlideRoute({required this.page, required this.direction})
      : super(
          pageBuilder: (context, animation, secondaryAnimation) => page,
          transitionDuration: Duration(milliseconds: _AnimSettings.duration),
          reverseTransitionDuration:
              Duration(milliseconds: (_AnimSettings.duration * 0.75).round()),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return _SlideWidget(
              animation: animation,
              secondaryAnimation: secondaryAnimation,
              direction: direction,
              child: child,
            );
          },
        );
}

class _SlideWidget extends StatefulWidget {
  final Animation<double> animation;
  final Animation<double> secondaryAnimation;
  final Axis direction;
  final Widget child;

  const _SlideWidget({
    required this.animation,
    required this.secondaryAnimation,
    required this.direction,
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
    final begin = widget.direction == Axis.horizontal
        ? const Offset(1.0, 0.0)
        : const Offset(0.0, 1.0);
    final offsetCurve = CurvedAnimation(
      parent: widget.animation,
      curve: _springOut,
      reverseCurve: _springIn,
    );
    final tween = Tween(begin: begin, end: Offset.zero);
    final offsetAnim = offsetCurve.drive(tween);
    final fadeAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: widget.animation, curve: Curves.easeInOut),
    );
    final secBegin = widget.direction == Axis.horizontal
        ? const Offset(-0.15, 0.0)
        : const Offset(0.0, 0.2);
    final secCurve = CurvedAnimation(
      parent: widget.secondaryAnimation,
      curve: Curves.easeInOutCubic,
    );
    final secTween = Tween(begin: Offset.zero, end: secBegin);
    final secOffset = secCurve.drive(secTween);
    final secFade = Tween<double>(begin: 1.0, end: 0.7).animate(
      CurvedAnimation(
          parent: widget.secondaryAnimation, curve: Curves.easeInOut),
    );

    return SlideTransition(
      position: offsetAnim,
      child: FadeTransition(
        opacity: fadeAnim,
        child: SlideTransition(
          position: secOffset,
          child: FadeTransition(
            opacity: secFade,
            child: _visible ? widget.child : const SizedBox.shrink(),
          ),
        ),
      ),
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
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            final fade = Tween<double>(begin: 0.0, end: 1.0).animate(
              CurvedAnimation(parent: animation, curve: Curves.easeInOut),
            );
            final secFade = Tween<double>(begin: 1.0, end: 0.0).animate(
              CurvedAnimation(
                  parent: secondaryAnimation, curve: Curves.easeInOut),
            );
            return FadeTransition(
                opacity: fade,
                child: FadeTransition(opacity: secFade, child: child));
          },
        );
}
