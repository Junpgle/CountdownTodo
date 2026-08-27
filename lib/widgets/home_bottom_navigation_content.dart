import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import '../services/liquid_glass_effect_service.dart';

double homeBottomBarHorizontalMarginFor(double screenWidth) {
  final responsiveMargin = screenWidth >= 430
      ? 78.0
      : screenWidth >= 360
          ? 64.0
          : 40.0;
  final maxWidthMargin = (screenWidth - 380) / 2;
  return math.max(responsiveMargin, maxWidthMargin);
}

Color homeBottomBarPrimaryColor({
  required ColorScheme colorScheme,
  required bool hasWallpaper,
  Color? wallpaperDominantColor,
}) {
  if (hasWallpaper && wallpaperDominantColor != null) {
    return wallpaperDominantColor;
  }
  return colorScheme.primary;
}

Color homeBottomBarSelectedBackgroundColor({
  required ColorScheme colorScheme,
  required Color primaryColor,
  required bool isDark,
}) {
  final neutralBase = Color.alphaBlend(
    colorScheme.onSurface.withValues(alpha: isDark ? 0.12 : 0.08),
    colorScheme.surface,
  );
  return Color.alphaBlend(
    primaryColor.withValues(alpha: isDark ? 0.05 : 0.025),
    neutralBase,
  ).withValues(alpha: isDark ? 0.5 : 0.72);
}

/// The three-entry content used inside the home screen's floating navigation
/// capsule. The outer material (Liquid Glass or the platform fallback) is
/// provided by the home screen so this widget only owns layout and selection.
class HomeBottomNavigationContent extends StatefulWidget {
  const HomeBottomNavigationContent({
    super.key,
    required this.selectedIndex,
    required this.primaryColor,
    required this.inactiveColor,
    required this.selectedBackgroundColor,
    required this.calendarButtonKey,
    required this.onTabSelected,
    required this.onCalendarPressed,
  }) : assert(
          selectedIndex == 0 || selectedIndex == 2,
          'The home bottom bar only supports the home and focus tabs.',
        );

  final int selectedIndex;
  final Color primaryColor;
  final Color inactiveColor;
  final Color selectedBackgroundColor;
  final Key calendarButtonKey;
  final ValueChanged<int> onTabSelected;
  final VoidCallback onCalendarPressed;

  @override
  State<HomeBottomNavigationContent> createState() =>
      _HomeBottomNavigationContentState();
}

class _HomeBottomNavigationContentState
    extends State<HomeBottomNavigationContent> with TickerProviderStateMixin {
  static const int _slotCount = 3;
  static const Duration _snapDuration = Duration(milliseconds: 220);
  static const Duration _interactionDuration = Duration(milliseconds: 150);
  static const EdgeInsets _indicatorPadding = EdgeInsets.all(4);
  static const EdgeInsets _indicatorExpansion = EdgeInsets.symmetric(
    horizontal: 30,
    vertical: 11,
  );
  // Keep the resting lens compact horizontally, while a restrained vertical
  // scale lets its rim cross the bar by only a pixel or two. The content stays
  // centered on the same baseline as every inactive item.
  static const double _indicatorHorizontalScale = 1.1;
  static const double _indicatorVerticalScale = 1.02;
  static const double _indicatorRadius = 9999;
  static const LiquidGlassSettings _indicatorSettings = LiquidGlassSettings(
    glassColor: Color(0x3DFFFFFF),
    thickness: 28,
    blur: 0,
    chromaticAberration: 0.16,
    lightIntensity: 0.9,
    ambientStrength: 0.22,
    refractiveIndex: 1.16,
    saturation: 1.08,
    shadowElevation: 5,
  );

  final GlobalKey _indicatorBackgroundKey = GlobalKey();

  late final SingleSpringController _positionSpring;
  late final SingleSpringController _interactionSpring;
  bool _draggingSelection = false;
  double _directDragVelocity = 0;
  double? _lastDragAlignment;
  Duration? _lastDragTimestamp;
  int? _motionTargetIndex;
  int? _awaitingWidgetIndex;
  bool _notifyTargetWhenReady = false;
  int _motionEpoch = 0;

  double _alignmentForIndex(int index) => index == 2 ? 1 : -1;

  @override
  void initState() {
    super.initState();
    _positionSpring = SingleSpringController(
      vsync: this,
      spring: GlassSpring.interactive(
        duration: _snapDuration,
        extraBounce: 0.05,
      ),
      initialValue: _alignmentForIndex(widget.selectedIndex),
      lowerBound: -1.12,
      upperBound: 1.12,
    )..addListener(_handleSpringTick);
    _interactionSpring = SingleSpringController(
      vsync: this,
      spring: GlassSpring.interactive(
        duration: _interactionDuration,
        extraBounce: 0.08,
      ),
      lowerBound: 0,
      upperBound: 1,
    )..addListener(_handleSpringTick);
  }

  @override
  void didUpdateWidget(covariant HomeBottomNavigationContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedIndex != widget.selectedIndex) {
      if (_awaitingWidgetIndex == widget.selectedIndex) {
        _awaitingWidgetIndex = null;
        return;
      }
      _animateToTab(widget.selectedIndex, notifyOnSettle: false);
    }
  }

  @override
  void dispose() {
    _positionSpring
      ..removeListener(_handleSpringTick)
      ..dispose();
    _interactionSpring
      ..removeListener(_handleSpringTick)
      ..dispose();
    super.dispose();
  }

  void _handleSpringTick() {
    if (!mounted) return;
    setState(() {});
    _completeMotionIfSettled();
  }

  void _completeMotionIfSettled() {
    final targetIndex = _motionTargetIndex;
    if (_draggingSelection || targetIndex == null) return;

    final targetAlignment = _alignmentForIndex(targetIndex);
    final distance = (_positionSpring.value - targetAlignment).abs();
    int? indexToNotify;

    // Commit just before the spring's imperceptible tail finishes. The page
    // now responds when the lens is visually attached to the destination,
    // instead of waiting for velocity to decay all the way to zero.
    if (_notifyTargetWhenReady &&
        widget.selectedIndex != targetIndex &&
        distance <= 0.065) {
      _notifyTargetWhenReady = false;
      _awaitingWidgetIndex = targetIndex;
      indexToNotify = targetIndex;
    }

    if (distance <= 0.006 && _positionSpring.velocity.abs() <= 0.08) {
      _motionTargetIndex = null;
      _notifyTargetWhenReady = false;
      _directDragVelocity = 0;
      _interactionSpring.animateTo(0);
    }

    if (indexToNotify != null) {
      widget.onTabSelected(indexToNotify);
    }
  }

  void _handleTabTap(int index) {
    if (index == widget.selectedIndex && _motionTargetIndex == null) {
      final epoch = ++_motionEpoch;
      _interactionSpring.animateTo(1);
      Future<void>.delayed(const Duration(milliseconds: 90), () {
        if (!mounted || epoch != _motionEpoch || _draggingSelection) return;
        _interactionSpring.animateTo(0);
      });
      return;
    }

    _animateToTab(
      index,
      notifyOnSettle: index != widget.selectedIndex,
    );
  }

  void _handleBarTap(TapUpDetails details, double width) {
    if (width <= 0) return;
    final slot = (details.localPosition.dx / (width / _slotCount))
        .floor()
        .clamp(0, _slotCount - 1);
    if (slot == 1) {
      widget.onCalendarPressed();
      return;
    }
    _handleTabTap(slot == 0 ? 0 : 2);
  }

  void _animateToTab(
    int index, {
    required bool notifyOnSettle,
    double initialVelocity = 0,
  }) {
    _motionEpoch++;
    _draggingSelection = false;
    _lastDragAlignment = null;
    _lastDragTimestamp = null;
    _directDragVelocity = 0;
    _motionTargetIndex = index;
    _notifyTargetWhenReady = notifyOnSettle;
    _positionSpring.spring = GlassSpring.interactive(
      duration: _snapDuration,
      extraBounce: 0.05,
    );
    _interactionSpring.animateTo(1);
    _positionSpring.animateTo(
      _alignmentForIndex(index),
      fromVelocity: initialVelocity,
    );
  }

  double _alignmentForLocalX(double localX, double width) {
    final indicatorWidth = width / _slotCount;
    final travelWidth = width - indicatorWidth;
    if (travelWidth <= 0) return _alignmentForIndex(widget.selectedIndex);

    final normalized = (localX - indicatorWidth / 2) / travelWidth;
    final rawAlignment = normalized * 2 - 1;
    if (rawAlignment < -1) {
      return (-1 + (rawAlignment + 1) * 0.24).clamp(-1.12, -1.0);
    }
    if (rawAlignment > 1) {
      return (1 + (rawAlignment - 1) * 0.24).clamp(1.0, 1.12);
    }
    return rawAlignment;
  }

  void _startSelectionDrag(DragStartDetails details, double width) {
    _motionEpoch++;
    _motionTargetIndex = null;
    _notifyTargetWhenReady = false;
    _draggingSelection = true;
    _directDragVelocity = 0;
    _interactionSpring.animateTo(1);

    final alignment = _alignmentForLocalX(details.localPosition.dx, width);
    _lastDragAlignment = alignment;
    _lastDragTimestamp = details.sourceTimeStamp;
    _positionSpring.setValue(alignment);
  }

  void _updateSelectionDrag(DragUpdateDetails details, double width) {
    if (!_draggingSelection) return;

    final alignment = _alignmentForLocalX(details.localPosition.dx, width);
    final previousAlignment = _lastDragAlignment;
    final timestamp = details.sourceTimeStamp;
    final previousTimestamp = _lastDragTimestamp;
    if (previousAlignment != null) {
      var seconds = 1 / 60;
      if (timestamp != null && previousTimestamp != null) {
        final elapsed = timestamp - previousTimestamp;
        if (elapsed > Duration.zero) {
          seconds = elapsed.inMicroseconds / Duration.microsecondsPerSecond;
        }
      }
      final rawVelocity = ((alignment - previousAlignment) / seconds)
          .clamp(-14.0, 14.0)
          .toDouble();
      _directDragVelocity = (_directDragVelocity * 0.35 + rawVelocity * 0.65)
          .clamp(-14.0, 14.0)
          .toDouble();
    }
    _lastDragAlignment = alignment;
    _lastDragTimestamp = timestamp;
    _positionSpring.setValue(alignment);
  }

  void _finishSelectionDrag(DragEndDetails details, double width) {
    if (!_draggingSelection) return;

    final travelWidth = width * (1 - 1 / _slotCount);
    final releaseVelocity = travelWidth <= 0
        ? 0.0
        : (details.velocity.pixelsPerSecond.dx * 2 / travelWidth)
            .clamp(-14.0, 14.0)
            .toDouble();
    final projectedAlignment =
        (_positionSpring.value + releaseVelocity * 0.065).clamp(-1.0, 1.0);
    final targetIndex = projectedAlignment >= 0 ? 2 : 0;

    _animateToTab(
      targetIndex,
      notifyOnSettle: targetIndex != widget.selectedIndex,
      initialVelocity: releaseVelocity,
    );
  }

  void _cancelSelectionDrag() {
    if (!_draggingSelection) return;
    _animateToTab(widget.selectedIndex, notifyOnSettle: false);
  }

  Matrix4 _jellyTransform(double velocity, GlassQuality quality) {
    final speed = velocity.abs();
    if (speed == 0 || !speed.isFinite) return Matrix4.identity();

    final maxDistortion = quality == GlassQuality.premium ? 0.8 : 0.35;
    final distortion = (speed / 10).clamp(0.0, 1.0) * maxDistortion;
    final scaleX = 1 - distortion * 0.5;
    final scaleY = 1 + distortion * 0.3;
    return Matrix4.diagonal3Values(scaleX, scaleY, 1);
  }

  GlassQuality _qualityFor(LiquidGlassEffectConfiguration configuration) {
    if (!configuration.enabled) return GlassQuality.minimal;
    return configuration.mode == LiquidGlassEffectMode.enhanced
        ? GlassQuality.premium
        : GlassQuality.standard;
  }

  Widget _buildNavigationRow(
    BuildContext context, {
    required bool selectedLayer,
  }) {
    return Row(
      children: [
        Expanded(
          child: _HomeBottomTabItem(
            index: 0,
            icon: Icons.dashboard_rounded,
            label: '首页',
            selected: selectedLayer,
            semanticsSelected: widget.selectedIndex == 0,
            interactive: !selectedLayer,
            primaryColor: widget.primaryColor,
            inactiveColor: widget.inactiveColor,
            onTap: () => _handleTabTap(0),
          ),
        ),
        Expanded(
          child: Center(
            child: _HomeCalendarButton(
              buttonKey: selectedLayer ? null : widget.calendarButtonKey,
              primaryColor: widget.primaryColor,
              interactive: !selectedLayer,
              onPressed: widget.onCalendarPressed,
            ),
          ),
        ),
        Expanded(
          child: _HomeBottomTabItem(
            index: 2,
            icon: Icons.adjust_rounded,
            label: '专注',
            selected: selectedLayer,
            semanticsSelected: widget.selectedIndex == 2,
            interactive: !selectedLayer,
            primaryColor: widget.primaryColor,
            inactiveColor: widget.inactiveColor,
            onTap: () => _handleTabTap(2),
          ),
        ),
      ],
    );
  }

  Widget _buildIndicator({
    required Key key,
    required Alignment alignment,
    required double thickness,
    required double velocity,
    required GlassQuality quality,
    required bool paintBackground,
    required bool paintGlass,
  }) {
    return Positioned.fill(
      child: IgnorePointer(
        child: Transform(
          key: paintGlass
              ? const ValueKey<String>(
                  'home-bottom-selection-overflow-layer',
                )
              : null,
          alignment: Alignment(
            alignment.x * (1 - 1 / _slotCount),
            0,
          ),
          transform: Matrix4.diagonal3Values(
            _indicatorHorizontalScale,
            _indicatorVerticalScale,
            1,
          ),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              AnimatedGlassIndicator(
                key: key,
                velocity: velocity,
                itemCount: _slotCount,
                alignment: alignment,
                thickness: thickness,
                quality: quality,
                indicatorColor: widget.selectedBackgroundColor,
                isBackgroundIndicator: false,
                paintBackground: paintBackground,
                paintGlass: paintGlass,
                padding: _indicatorPadding,
                expansion: _indicatorExpansion,
                settings: _indicatorSettings,
                borderRadius: _indicatorRadius,
                pinchStrength: 0.85,
                shadows: paintBackground
                    ? <BoxShadow>[
                        BoxShadow(
                          color: widget.primaryColor.withValues(alpha: 0.08),
                          blurRadius: 16,
                          offset: const Offset(0, 3),
                        ),
                      ]
                    : null,
                backgroundKey: paintGlass && quality != GlassQuality.minimal
                    ? _indicatorBackgroundKey
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNavigationContent(
    BuildContext context,
    LiquidGlassEffectConfiguration configuration,
  ) {
    final quality = _qualityFor(configuration);
    final alignment = Alignment(_positionSpring.value, 0);
    final thickness = _interactionSpring.value.clamp(0.0, 1.0).toDouble();
    final velocity =
        (_draggingSelection ? _directDragVelocity : _positionSpring.velocity)
            .clamp(-14.0, 14.0)
            .toDouble();
    final jellyTransform = _jellyTransform(velocity, quality);
    final directionalMotion = (velocity / 14).clamp(-1.0, 1.0).toDouble();
    final contentTransform = Matrix4.identity()
      ..translateByDouble(
        directionalMotion * 3,
        0,
        0,
        1,
      )
      ..rotateZ(directionalMotion * 0.008)
      ..scaleByDouble(
        1 + thickness * 0.006,
        1 + thickness * 0.012,
        1,
        1,
      );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: LayoutBuilder(
        builder: (context, constraints) {
          return GestureDetector(
            key: const ValueKey<String>('home-bottom-navigation-gesture-layer'),
            behavior: HitTestBehavior.translucent,
            onHorizontalDragStart: (details) =>
                _startSelectionDrag(details, constraints.maxWidth),
            onHorizontalDragUpdate: (details) =>
                _updateSelectionDrag(details, constraints.maxWidth),
            onHorizontalDragEnd: (details) =>
                _finishSelectionDrag(details, constraints.maxWidth),
            onHorizontalDragCancel: _cancelSelectionDrag,
            onTapUp: (details) => _handleBarTap(details, constraints.maxWidth),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(
                  child: IgnorePointer(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(34),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: RadialGradient(
                            center: Alignment(alignment.x * 0.72, -1.05),
                            radius: 1.15,
                            colors: <Color>[
                              widget.primaryColor.withValues(
                                alpha: 0.035 + thickness * 0.05,
                              ),
                              widget.primaryColor.withValues(alpha: 0),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Transform(
                  alignment: Alignment.center,
                  transform: contentTransform,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      _buildIndicator(
                        key: const ValueKey<String>(
                          'home-bottom-selection-indicator-fill',
                        ),
                        alignment: alignment,
                        thickness: thickness,
                        velocity: velocity,
                        quality: quality,
                        paintBackground: true,
                        paintGlass: false,
                      ),
                      RepaintBoundary(
                        key: _indicatorBackgroundKey,
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            ClipPath(
                              clipBehavior: Clip.antiAliasWithSaveLayer,
                              clipper: _OverflowingJellyClipper(
                                itemCount: _slotCount,
                                alignment: alignment,
                                thickness: thickness,
                                expansion: _indicatorExpansion,
                                transform: jellyTransform,
                                borderRadius: _indicatorRadius,
                                horizontalScale: _indicatorHorizontalScale,
                                verticalScale: _indicatorVerticalScale,
                                inverse: true,
                              ),
                              child: _buildNavigationRow(
                                context,
                                selectedLayer: false,
                              ),
                            ),
                            ExcludeSemantics(
                              child: IgnorePointer(
                                child: ClipPath(
                                  clipBehavior: Clip.antiAliasWithSaveLayer,
                                  clipper: _OverflowingJellyClipper(
                                    itemCount: _slotCount,
                                    alignment: alignment,
                                    thickness: thickness,
                                    expansion: _indicatorExpansion,
                                    transform: jellyTransform,
                                    borderRadius: _indicatorRadius,
                                    horizontalScale: _indicatorHorizontalScale,
                                    verticalScale: _indicatorVerticalScale,
                                  ),
                                  child: Transform.scale(
                                    scale: 1 + thickness * 0.035,
                                    child: _buildNavigationRow(
                                      context,
                                      selectedLayer: true,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      _buildIndicator(
                        key: const ValueKey<String>(
                          'home-bottom-selection-indicator',
                        ),
                        alignment: alignment,
                        thickness: thickness,
                        velocity: velocity,
                        quality: quality,
                        paintBackground: false,
                        paintGlass: true,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<LiquidGlassEffectConfiguration>(
      valueListenable: LiquidGlassEffectService.configurationListenable,
      builder: (context, configuration, _) =>
          _buildNavigationContent(context, configuration),
    );
  }
}

/// Expands the package's jelly path around its vertical center without
/// expanding the full-size inverse region. Only the glass crosses the bar's
/// bounds; the selected content remains centered on the standard baseline.
class _OverflowingJellyClipper extends CustomClipper<Path> {
  _OverflowingJellyClipper({
    required this.itemCount,
    required this.alignment,
    required this.thickness,
    required this.expansion,
    required this.transform,
    required this.borderRadius,
    required this.horizontalScale,
    required this.verticalScale,
    this.inverse = false,
  });

  final int itemCount;
  final Alignment alignment;
  final double thickness;
  final EdgeInsets expansion;
  final Matrix4 transform;
  final double borderRadius;
  final double horizontalScale;
  final double verticalScale;
  final bool inverse;

  @override
  Path getClip(Size size) {
    final basePath = JellyClipper(
      itemCount: itemCount,
      alignment: alignment,
      thickness: thickness,
      expansion: expansion,
      transform: transform,
      borderRadius: borderRadius,
    ).getClip(size);
    final center = basePath.getBounds().center;
    final shapeTransform = Matrix4.identity()
      ..translateByDouble(center.dx, center.dy, 0, 1)
      ..scaleByDouble(horizontalScale, verticalScale, 1, 1)
      ..translateByDouble(-center.dx, -center.dy, 0, 1);
    final indicatorPath = basePath.transform(shapeTransform.storage);

    if (!inverse) return indicatorPath;
    return Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addPath(indicatorPath, Offset.zero);
  }

  @override
  bool shouldReclip(_OverflowingJellyClipper oldClipper) {
    return itemCount != oldClipper.itemCount ||
        alignment != oldClipper.alignment ||
        thickness != oldClipper.thickness ||
        expansion != oldClipper.expansion ||
        transform != oldClipper.transform ||
        borderRadius != oldClipper.borderRadius ||
        horizontalScale != oldClipper.horizontalScale ||
        verticalScale != oldClipper.verticalScale ||
        inverse != oldClipper.inverse;
  }
}

class _HomeCalendarButton extends StatelessWidget {
  const _HomeCalendarButton({
    required this.buttonKey,
    required this.primaryColor,
    required this.interactive,
    required this.onPressed,
  });

  final Key? buttonKey;
  final Color primaryColor;
  final bool interactive;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final visual = Container(
      key: buttonKey,
      decoration: BoxDecoration(
        color: primaryColor,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: primaryColor.withValues(alpha: 0.24),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Icon(
        Icons.calendar_today_rounded,
        color: Theme.of(context).colorScheme.onPrimary,
        size: 22,
      ),
    );

    return SizedBox(
      width: 56,
      height: 44,
      child: interactive
          ? Semantics(
              button: true,
              label: '日历视图',
              onTap: onPressed,
              child: visual,
            )
          : visual,
    );
  }
}

class _HomeBottomTabItem extends StatelessWidget {
  const _HomeBottomTabItem({
    required this.index,
    required this.icon,
    required this.label,
    required this.selected,
    required this.semanticsSelected,
    required this.interactive,
    required this.primaryColor,
    required this.inactiveColor,
    required this.onTap,
  });

  final int index;
  final IconData icon;
  final String label;
  final bool selected;
  final bool semanticsSelected;
  final bool interactive;
  final Color primaryColor;
  final Color inactiveColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final foregroundColor = selected ? primaryColor : inactiveColor;
    const duration = Duration(milliseconds: 220);
    final visual = AnimatedScale(
      key: ValueKey<String>('home-bottom-tab-surface-$index'),
      scale: selected ? 1.04 : 1,
      duration: duration,
      curve: Curves.easeOutCubic,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TweenAnimationBuilder<Color?>(
              tween: ColorTween(end: foregroundColor),
              duration: duration,
              builder: (context, color, _) =>
                  Icon(icon, color: color, size: 24),
            ),
            const SizedBox(height: 2),
            AnimatedDefaultTextStyle(
              duration: duration,
              curve: Curves.easeOutCubic,
              style: TextStyle(
                color: foregroundColor,
                fontSize: 10,
                fontWeight: selected ? FontWeight.bold : FontWeight.w500,
              ),
              child: Text(label),
            ),
          ],
        ),
      ),
    );

    if (!interactive) return visual;
    return Semantics(
      button: true,
      selected: semanticsSelected,
      label: label,
      excludeSemantics: true,
      onTap: onTap,
      child: visual,
    );
  }
}
