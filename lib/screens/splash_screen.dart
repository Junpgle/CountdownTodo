import 'package:flutter/material.dart';

import '../utils/local_image_provider.dart';
import '../widgets/splash_screen_shell.dart';

class SplashScreen extends StatelessWidget {
  final VoidCallback onComplete;
  final Map<String, dynamic> content;

  const SplashScreen({
    super.key,
    required this.onComplete,
    required this.content,
  });

  @override
  Widget build(BuildContext context) {
    final dynamic rawDuration = content['durationMs'];
    final durationMs = rawDuration is int
        ? rawDuration
        : (int.tryParse(rawDuration?.toString() ?? '') ?? 500);
    final safeDurationMs = durationMs.clamp(300, 8000);
    final imagePath = content['imagePath'] as String?;
    final hasImage = imagePath != null && localImageExists(imagePath);

    return SplashScreenShell(
      onComplete: onComplete,
      fadeDuration: const Duration(milliseconds: 200),
      displayDuration: Duration(milliseconds: safeDurationMs),
      startTimerAfterFirstFrame: false,
      contentBuilder: (context, size, pixelRatio, isWide, fadeAnimation) {
        if (!hasImage) {
          return FadeTransition(
            opacity: fadeAnimation,
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xFF4A90D9), Color(0xFF357ABD)],
                ),
              ),
            ),
          );
        }
        return isWide
            ? _buildWideLayout(imagePath, size, pixelRatio, fadeAnimation)
            : _buildNarrowLayout(imagePath, size, pixelRatio, fadeAnimation);
      },
    );
  }

  Widget _buildNarrowLayout(
    String imagePath,
    Size size,
    double pixelRatio,
    Animation<double> fadeAnimation,
  ) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: size.height * 0.7,
          child: FadeTransition(
            opacity: fadeAnimation,
            child: ClipRect(
              child: localImageWidget(
                imagePath,
                width: size.width,
                height: size.height,
                fit: BoxFit.cover,
              ),
            ),
          ),
        ),
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          height: size.height * 0.3,
          child: ClipRect(
            child: SplashDefaultAssetImage(
              assetName: 'assets/splash/default.webp',
              size: size,
              pixelRatio: pixelRatio,
              fadeAnimation: fadeAnimation,
              alignment: Alignment.bottomCenter,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildWideLayout(
    String imagePath,
    Size size,
    double pixelRatio,
    Animation<double> fadeAnimation,
  ) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned(
          top: 0,
          bottom: 0,
          left: 0,
          width: size.width * 0.6,
          child: FadeTransition(
            opacity: fadeAnimation,
            child: ClipRect(
              child: localImageWidget(
                imagePath,
                width: size.width,
                height: size.height,
                fit: BoxFit.cover,
              ),
            ),
          ),
        ),
        Positioned(
          top: 0,
          bottom: 0,
          right: 0,
          width: size.width * 0.4,
          child: ClipRect(
            child: SplashDefaultAssetImage(
              assetName: 'assets/splash/default_pad.webp',
              size: size,
              pixelRatio: pixelRatio,
              fadeAnimation: fadeAnimation,
              alignment: Alignment.centerRight,
            ),
          ),
        ),
      ],
    );
  }
}
