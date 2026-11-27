import 'package:flutter/material.dart';

import '../widgets/splash_screen_shell.dart';

class DefaultSplashScreen extends StatelessWidget {
  final VoidCallback onComplete;

  const DefaultSplashScreen({super.key, required this.onComplete});

  @override
  Widget build(BuildContext context) {
    return SplashScreenShell(
      onComplete: onComplete,
      fadeDuration: const Duration(milliseconds: 150),
      displayDuration: const Duration(milliseconds: 650),
      startTimerAfterFirstFrame: true,
      contentBuilder: (context, size, pixelRatio, isWide, fadeAnimation) {
        final assetName = isWide
            ? 'assets/splash/default_pad.webp'
            : 'assets/splash/default.webp';
        return SplashDefaultAssetImage(
          assetName: assetName,
          size: size,
          pixelRatio: pixelRatio,
          fadeAnimation: fadeAnimation,
        );
      },
    );
  }
}
