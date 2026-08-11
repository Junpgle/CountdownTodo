import 'dart:ui';

import 'package:flutter/material.dart';

import '../utils/app_platform.dart';

/// Avoids creating an offscreen blurred texture on Android.
///
/// Backdrop blur is visually pleasant on desktop and iOS, but it can make a
/// full-screen wallpaper or a scrolling card miss the 120Hz raster budget on
/// Android. The caller still supplies the same child, so the platform change
/// only removes the expensive compositing step.
class PlatformBackdropFilter extends StatelessWidget {
  final ImageFilter filter;
  final Widget child;

  const PlatformBackdropFilter({
    super.key,
    required this.filter,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    if (AppPlatform.isAndroid) return child;
    return BackdropFilter(filter: filter, child: child);
  }
}
