import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:liquid_glass_widgets/theme/glass_theme_helpers.dart';

import '../services/android_window_rendering_policy.dart';
import '../services/liquid_glass_effect_service.dart';
import '../utils/app_image_filters.dart';
import '../utils/app_platform.dart';
import 'optional_liquid_glass_surface.dart';

part 'floating_glass/floating_glass_inputs.dart';
part 'floating_glass/floating_glass_fade.dart';
part 'floating_glass/floating_glass_overlay.dart';
part 'floating_glass/floating_glass_app_bar.dart';
part 'floating_glass/floating_glass_sliver_and_buttons.dart';

/// Whether a floating control should use the phone portrait treatment.
///
/// The reference treatment is intentionally kept to phone-sized portrait
/// layouts. Wide windows and landscape layouts retain their normal geometry so
/// controls do not become cramped capsules on desktop or tablets.
@visibleForTesting
bool floatingBottomBarShouldFloatFor({
  required bool isMobile,
  required double width,
  required double height,
  double maxPhoneShortestSide = 600,
}) {
  final shortestSide = math.min(width, height);
  return isMobile && height > width && shortestSide < maxPhoneShortestSide;
}

/// The runtime phone-portrait check used by shared floating controls.
bool floatingBottomBarShouldFloat(BuildContext context) {
  final size = MediaQuery.sizeOf(context);
  return floatingBottomBarShouldFloatFor(
    isMobile: AppPlatform.isMobile,
    width: size.width,
    height: size.height,
  );
}

const double _floatingGlassAppBarScrollDistance = 72.0;
const double _floatingGlassAppBarControlThreshold = 0.58;

/// Shared diameter for compact floating controls.
///
/// Keeping this in the common control layer prevents app-bar actions and
/// dashboard quick actions from drifting into separate 40/48 dp systems.
const double floatingGlassStandardControlSize = 48.0;

/// Canonical switch geometry shared by every settings surface.
const double liquidGlassSwitchWidth = 58.0;
const double liquidGlassSwitchHeight = 26.0;

/// Returns a native-looking icon-button style for controls that live in a
/// glass-enabled page but should not become glass themselves.
///
/// The explicit identity [ButtonStyle.backgroundBuilder] is important: a
/// page-level icon-button theme may otherwise add a second glass surface while
/// the caller is intentionally using a plain icon control.
ButtonStyle floatingGlassPlainIconButtonStyle() {
  return ButtonStyle(
    backgroundBuilder: _floatingGlassIdentityButtonBackground,
    backgroundColor: const WidgetStatePropertyAll(Colors.transparent),
    side: const WidgetStatePropertyAll(BorderSide.none),
    elevation: const WidgetStatePropertyAll(0),
    shadowColor: const WidgetStatePropertyAll(Colors.transparent),
    surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
  );
}

Widget _floatingGlassIdentityButtonBackground(
  BuildContext context,
  Set<WidgetState> states,
  Widget? child,
) {
  return child ?? const SizedBox.shrink();
}

ButtonStyle _floatingGlassChildButtonStyle(ButtonStyle? style) {
  return (style ?? const ButtonStyle()).copyWith(
    // FloatingGlassControl owns the only surface around its child. Preserve
    // the child's shape, colors, padding, and interaction settings, but stop
    // the app-wide liquid-glass button theme from adding another container or
    // outline around the child.
    backgroundBuilder: _floatingGlassIdentityButtonBackground,
    side: const WidgetStatePropertyAll<BorderSide?>(BorderSide.none),
  );
}

Widget _floatingGlassSegmentedButtonBackground(
  BuildContext context,
  Set<WidgetState> states,
  Widget? child,
) {
  final selected = states.contains(WidgetState.selected);
  final colorScheme = Theme.of(context).colorScheme;
  return DecoratedBox(
    decoration: BoxDecoration(
      color: selected ? colorScheme.secondaryContainer : Colors.transparent,
      borderRadius: BorderRadius.circular(16),
    ),
    child: child ?? const SizedBox.shrink(),
  );
}

ButtonStyle _floatingGlassChildSegmentedButtonStyle(ButtonStyle? style) {
  return _floatingGlassChildButtonStyle(style).copyWith(
    // The floating control suppresses nested glass surfaces, but selected
    // segments still need a solid fill to remain distinguishable.
    backgroundBuilder: _floatingGlassSegmentedButtonBackground,
  );
}

ThemeData _floatingGlassChildTheme(BuildContext context) {
  final theme = Theme.of(context);
  return theme.copyWith(
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: _floatingGlassChildButtonStyle(theme.elevatedButtonTheme.style),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: _floatingGlassChildButtonStyle(theme.filledButtonTheme.style),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: _floatingGlassChildButtonStyle(theme.outlinedButtonTheme.style),
    ),
    textButtonTheme: TextButtonThemeData(
      style: _floatingGlassChildButtonStyle(theme.textButtonTheme.style),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: _floatingGlassChildButtonStyle(theme.iconButtonTheme.style),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: _floatingGlassChildSegmentedButtonStyle(
        theme.segmentedButtonTheme.style,
      ),
    ),
  );
}
