import 'dart:math' as math;

import 'package:flutter/material.dart';

double homeBottomBarHorizontalMarginFor(double screenWidth) {
  final responsiveMargin = screenWidth >= 430
      ? 60.0
      : screenWidth >= 360
          ? 50.0
          : 40.0;
  final maxWidthMargin = (screenWidth - 440) / 2;
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
  });

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
    extends State<HomeBottomNavigationContent> {
  double? _draggedSelectionLeft;
  bool _draggingSelection = false;

  @override
  void didUpdateWidget(covariant HomeBottomNavigationContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedIndex != widget.selectedIndex) {
      _draggedSelectionLeft = null;
      _draggingSelection = false;
    }
  }

  void _startSelectionDrag(double maxSelectionLeft) {
    final selectionLeft = widget.selectedIndex == 2 ? maxSelectionLeft : 0.0;
    setState(() {
      _draggingSelection = true;
      _draggedSelectionLeft = selectionLeft;
    });
  }

  void _updateSelectionDrag(
    DragUpdateDetails details, {
    required double maxSelectionLeft,
  }) {
    if (!_draggingSelection || _draggedSelectionLeft == null) return;

    final delta = details.primaryDelta ?? details.delta.dx;
    setState(() {
      _draggedSelectionLeft = (_draggedSelectionLeft! + delta)
          .clamp(0.0, maxSelectionLeft)
          .toDouble();
    });
  }

  void _finishSelectionDrag(double maxSelectionLeft) {
    if (!_draggingSelection || _draggedSelectionLeft == null) {
      _draggedSelectionLeft = null;
      _draggingSelection = false;
      return;
    }

    final targetIndex = _draggedSelectionLeft! >= maxSelectionLeft / 2 ? 2 : 0;
    setState(() {
      _draggedSelectionLeft = null;
      _draggingSelection = false;
    });
    if (targetIndex != widget.selectedIndex) {
      widget.onTabSelected(targetIndex);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      child: LayoutBuilder(
        builder: (context, constraints) {
          const calendarSlotWidth = 72.0;
          final tabWidth = (constraints.maxWidth - calendarSlotWidth) / 2;
          final maxSelectionLeft = constraints.maxWidth - tabWidth;
          final selectionLeft =
              widget.selectedIndex == 2 ? maxSelectionLeft : 0.0;
          final visibleSelectionLeft = _draggedSelectionLeft ?? selectionLeft;
          return GestureDetector(
            key: const ValueKey<String>('home-bottom-navigation-gesture-layer'),
            behavior: HitTestBehavior.translucent,
            onHorizontalDragStart: (_) => _startSelectionDrag(maxSelectionLeft),
            onHorizontalDragUpdate: (details) => _updateSelectionDrag(
              details,
              maxSelectionLeft: maxSelectionLeft,
            ),
            onHorizontalDragEnd: (_) => _finishSelectionDrag(maxSelectionLeft),
            onHorizontalDragCancel: () =>
                _finishSelectionDrag(maxSelectionLeft),
            child: Stack(
              children: [
                AnimatedPositioned(
                  key:
                      const ValueKey<String>('home-bottom-selection-indicator'),
                  duration: _draggingSelection
                      ? Duration.zero
                      : const Duration(milliseconds: 280),
                  curve: Curves.easeOutCubic,
                  left: visibleSelectionLeft,
                  top: 1,
                  bottom: 1,
                  width: tabWidth,
                  child: DecoratedBox(
                    key: const ValueKey<String>(
                        'home-bottom-selection-indicator-fill'),
                    decoration: BoxDecoration(
                      color: widget.selectedBackgroundColor,
                      borderRadius: BorderRadius.circular(28),
                      border: Border.all(
                        color: widget.primaryColor.withValues(alpha: 0.22),
                        width: 0.8,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: widget.primaryColor.withValues(alpha: 0.1),
                          blurRadius: 10,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                  ),
                ),
                Row(
                  children: [
                    Expanded(
                      child: _HomeBottomTabItem(
                        index: 0,
                        icon: Icons.dashboard_rounded,
                        label: '首页',
                        selected: widget.selectedIndex == 0,
                        primaryColor: widget.primaryColor,
                        inactiveColor: widget.inactiveColor,
                        onTap: () => widget.onTabSelected(0),
                      ),
                    ),
                    SizedBox(
                      width: calendarSlotWidth,
                      child: Center(
                        child: Semantics(
                          button: true,
                          label: '日历视图',
                          child: SizedBox(
                            width: 56,
                            height: 44,
                            child: InkWell(
                              onTap: widget.onCalendarPressed,
                              borderRadius: BorderRadius.circular(22),
                              child: Container(
                                key: widget.calendarButtonKey,
                                decoration: BoxDecoration(
                                  color: widget.primaryColor,
                                  borderRadius: BorderRadius.circular(22),
                                  boxShadow: [
                                    BoxShadow(
                                      color: widget.primaryColor
                                          .withValues(alpha: 0.24),
                                      blurRadius: 8,
                                      offset: const Offset(0, 3),
                                    ),
                                  ],
                                ),
                                child: Icon(
                                  Icons.calendar_today_rounded,
                                  color:
                                      Theme.of(context).colorScheme.onPrimary,
                                  size: 22,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: _HomeBottomTabItem(
                        index: 2,
                        icon: Icons.adjust_rounded,
                        label: '专注',
                        selected: widget.selectedIndex == 2,
                        primaryColor: widget.primaryColor,
                        inactiveColor: widget.inactiveColor,
                        onTap: () => widget.onTabSelected(2),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _HomeBottomTabItem extends StatelessWidget {
  const _HomeBottomTabItem({
    required this.index,
    required this.icon,
    required this.label,
    required this.selected,
    required this.primaryColor,
    required this.inactiveColor,
    required this.onTap,
  });

  final int index;
  final IconData icon;
  final String label;
  final bool selected;
  final Color primaryColor;
  final Color inactiveColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final foregroundColor = selected ? primaryColor : inactiveColor;
    const duration = Duration(milliseconds: 220);
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(28),
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
        child: AnimatedScale(
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
        ),
      ),
    );
  }
}
