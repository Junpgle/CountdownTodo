import 'dart:ui';

import 'package:flutter/material.dart';

import '../services/liquid_glass_effect_service.dart';
import '../utils/app_platform.dart';

/// Avoids creating an offscreen blurred texture on Windows.
///
/// Backdrop blur is visually pleasant across mobile and desktop platforms, but
/// it can conflict with transparent window compositions on Windows. The caller
/// still supplies the same child, so the platform change only removes the
/// compositing step on Windows.
class PlatformBackdropFilter extends StatelessWidget {
  final ImageFilter filter;
  final Widget child;
  final bool bypassWhenLiquidGlassEnabled;

  const PlatformBackdropFilter({
    super.key,
    required this.filter,
    required this.child,
    this.bypassWhenLiquidGlassEnabled = false,
  });

  @override
  Widget build(BuildContext context) {
    if (AppPlatform.isWindows) return child;
    if (bypassWhenLiquidGlassEnabled) {
      return ValueListenableBuilder<LiquidGlassEffectConfiguration>(
        valueListenable: LiquidGlassEffectService.configurationListenable,
        builder: (context, configuration, _) {
          if (configuration.enabled) return child;
          return BackdropFilter(filter: filter, child: child);
        },
      );
    }
    return BackdropFilter(filter: filter, child: child);
  }
}
