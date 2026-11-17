import 'dart:ui';

import 'package:flutter/material.dart';

import '../services/liquid_glass_effect_service.dart';
import '../services/power_save_mode_service.dart';
import '../utils/app_platform.dart';

/// Avoids creating an offscreen blurred texture by default on Windows.
/// Windows can opt into the standard blur through the Liquid Glass setting.
///
/// The caller still supplies the same child, so bypassing blur only removes the
/// expensive compositing step while preserving the supplied clipping.
class PlatformBackdropFilter extends StatelessWidget {
  final ImageFilter filter;
  final Widget child;
  final bool bypassWhenLiquidGlassEnabled;
  final BorderRadiusGeometry? clipBorderRadius;
  final Clip clipBehavior;

  const PlatformBackdropFilter({
    super.key,
    required this.filter,
    required this.child,
    this.bypassWhenLiquidGlassEnabled = false,
    this.clipBorderRadius,
    this.clipBehavior = Clip.antiAlias,
  });

  Widget _clipIfNeeded(Widget content, {bool forceClipRect = false}) {
    final borderRadius = clipBorderRadius;
    final effectiveClipBehavior =
        AppPlatform.isWindows && clipBehavior == Clip.antiAlias
        ? Clip.hardEdge
        : clipBehavior;

    if (borderRadius != null) {
      return ClipRRect(
        borderRadius: borderRadius,
        clipBehavior: effectiveClipBehavior,
        child: content,
      );
    }

    if (forceClipRect) {
      return ClipRect(clipBehavior: effectiveClipBehavior, child: content);
    }

    return content;
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge(<Listenable>[
        LiquidGlassEffectService.configurationListenable,
        PowerSaveModeService.enabledListenable,
      ]),
      builder: (context, _) {
        if (PowerSaveModeService.isEnabled ||
            Theme.of(context).brightness == Brightness.dark ||
            bypassWhenLiquidGlassEnabled) {
          return _clipIfNeeded(child);
        }
        final configuration = LiquidGlassEffectService.configuration;
        if (AppPlatform.isWindows && !configuration.enabled) {
          return _clipIfNeeded(child);
        }
        return _clipIfNeeded(
          BackdropFilter.grouped(filter: filter, child: child),
          forceClipRect: true,
        );
      },
    );
  }
}
