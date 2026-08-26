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
class HomeBottomNavigationContent extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      child: LayoutBuilder(
        builder: (context, constraints) {
          const calendarSlotWidth = 72.0;
          final tabWidth = (constraints.maxWidth - calendarSlotWidth) / 2;
          final selectionLeft =
              selectedIndex == 2 ? constraints.maxWidth - tabWidth : 0.0;
          return Stack(
            children: [
              AnimatedPositioned(
                key: const ValueKey<String>('home-bottom-selection-indicator'),
                duration: const Duration(milliseconds: 280),
                curve: Curves.easeOutCubic,
                left: selectionLeft,
                top: 1,
                bottom: 1,
                width: tabWidth,
                child: DecoratedBox(
                  key: const ValueKey<String>(
                      'home-bottom-selection-indicator-fill'),
                  decoration: BoxDecoration(
                    color: selectedBackgroundColor,
                    borderRadius: BorderRadius.circular(28),
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
                      selected: selectedIndex == 0,
                      primaryColor: primaryColor,
                      inactiveColor: inactiveColor,
                      onTap: () => onTabSelected(0),
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
                            onTap: onCalendarPressed,
                            borderRadius: BorderRadius.circular(22),
                            child: Container(
                              key: calendarButtonKey,
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
                      selected: selectedIndex == 2,
                      primaryColor: primaryColor,
                      inactiveColor: inactiveColor,
                      onTap: () => onTabSelected(2),
                    ),
                  ),
                ],
              ),
            ],
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
