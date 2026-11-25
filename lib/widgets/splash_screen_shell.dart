import 'dart:async';

import 'package:flutter/material.dart';

import 'floating_glass_control.dart';

/// 启动页主体内容构造器。
typedef SplashContentBuilder = Widget Function(
  BuildContext context,
  Size size,
  double pixelRatio,
  bool isWide,
  Animation<double> fadeAnimation,
);

/// 启动页淡入动画、自动完成计时与右上角「跳过」按钮公共容器。
class SplashScreenShell extends StatefulWidget {
  final VoidCallback onComplete;
  final Duration displayDuration;
  final Duration fadeDuration;
  final bool startTimerAfterFirstFrame;
  final SplashContentBuilder contentBuilder;

  const SplashScreenShell({
    super.key,
    required this.onComplete,
    required this.displayDuration,
    this.fadeDuration = const Duration(milliseconds: 150),
    this.startTimerAfterFirstFrame = false,
    required this.contentBuilder,
  });

  @override
  State<SplashScreenShell> createState() => _SplashScreenShellState();
}

class _SplashScreenShellState extends State<SplashScreenShell>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fadeAnimation;
  Timer? _completeTimer;
  bool _completed = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.fadeDuration,
    );
    _fadeAnimation = _controller.drive(CurveTween(curve: Curves.easeIn));
    _controller.forward();

    if (widget.startTimerAfterFirstFrame) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _completed) return;
        _completeTimer = Timer(widget.displayDuration, _completeOnce);
      });
    } else {
      _completeTimer = Timer(widget.displayDuration, _completeOnce);
    }
  }

  @override
  void dispose() {
    _completeTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _skip() {
    _controller.stop();
    _completeOnce();
  }

  void _completeOnce() {
    if (_completed || !mounted) return;
    _completed = true;
    _completeTimer?.cancel();
    widget.onComplete();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final pixelRatio = MediaQuery.devicePixelRatioOf(context);
    final colorScheme = Theme.of(context).colorScheme;
    final isWide = size.width > 600;

    return Scaffold(
      body: SizedBox(
        width: size.width,
        height: size.height,
        child: Stack(
          fit: StackFit.expand,
          children: [
            widget.contentBuilder(
              context,
              size,
              pixelRatio,
              isWide,
              _fadeAnimation,
            ),
            Positioned(
              top: 48,
              right: 16,
              child: SafeArea(
                child: FloatingGlassControl(
                  height: 48,
                  borderRadius: 24,
                  tint: colorScheme.surface,
                  haloColor: colorScheme.primary,
                  child: TextButton(
                    onPressed: _skip,
                    style: TextButton.styleFrom(
                      minimumSize: const Size(72, 48),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: Text(
                      '跳过',
                      style: TextStyle(
                        fontSize: 16,
                        color: colorScheme.onSurface,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 按设备像素比缓存解码的默认开屏资源图。
class SplashDefaultAssetImage extends StatelessWidget {
  final String assetName;
  final Size size;
  final double pixelRatio;
  final Animation<double> fadeAnimation;
  final AlignmentGeometry alignment;

  const SplashDefaultAssetImage({
    super.key,
    required this.assetName,
    required this.size,
    required this.pixelRatio,
    required this.fadeAnimation,
    this.alignment = Alignment.center,
  });

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      assetName,
      width: size.width,
      height: size.height,
      cacheWidth: (size.width * pixelRatio).round().clamp(1, 4096),
      cacheHeight: (size.height * pixelRatio).round().clamp(1, 4096),
      fit: BoxFit.cover,
      alignment: alignment,
      opacity: fadeAnimation,
    );
  }
}
