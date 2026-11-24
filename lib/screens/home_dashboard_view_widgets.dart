part of 'home_dashboard.dart';

enum _HomeAddAction { todo, countdown, finance }

/// The phone homepage body is painted underneath its pinned header. Its final
/// spacer must therefore reserve both the floating bottom bar and the header;
/// otherwise a short page has no positive scroll extent and a slow upward
/// drag only produces an overscroll bounce.
@visibleForTesting
double homeDashboardPhoneScrollTailExtent({
  required double headerExtent,
  required double bottomInset,
}) => headerExtent.clamp(0.0, 2000.0).toDouble() + 100.0 + bottomInset;

/// Computes the effective top padding for phone dashboard scroll views.
/// When the pinned header is collapsed or omitted (e.g. on the Focus tab),
/// the list must still clear the system status bar safe area.
@visibleForTesting
double homeDashboardPhoneScrollTopPadding({
  required double headerExtent,
  required double topInset,
}) =>
    max(
      headerExtent.clamp(0.0, 2000.0).toDouble(),
      topInset.clamp(0.0, 2000.0).toDouble(),
    ) +
    6.0;

class _HomeDashboardBottomBar extends StatelessWidget {
  const _HomeDashboardBottomBar({
    required this.selectedIndex,
    required this.primaryColor,
    required this.inactiveColor,
    required this.selectedBackgroundColor,
    required this.weeklyButtonKey,
    required this.addButtonKey,
    required this.pomodoroButtonKey,
    required this.isWide,
    required this.onTabSelected,
    required this.onWeeklyPressed,
    required this.onAddPressed,
    required this.onAddLongPress,
    required this.onAddLongPressStart,
    required this.onAddLongPressMoveUpdate,
    required this.onAddLongPressEnd,
    required this.onAddLongPressCancel,
    required this.onPomodoroPressed,
    required this.height,
    required this.margin,
    required this.isDarkMode,
    required this.glassTint,
  });

  final int selectedIndex;
  final Color primaryColor;
  final Color inactiveColor;
  final Color selectedBackgroundColor;
  final Key weeklyButtonKey;
  final Key addButtonKey;
  final Key pomodoroButtonKey;
  final bool isWide;
  final ValueChanged<int> onTabSelected;
  final VoidCallback onWeeklyPressed;
  final VoidCallback onAddPressed;
  final VoidCallback onAddLongPress;
  final GestureLongPressStartCallback onAddLongPressStart;
  final GestureLongPressMoveUpdateCallback onAddLongPressMoveUpdate;
  final GestureLongPressEndCallback onAddLongPressEnd;
  final VoidCallback onAddLongPressCancel;
  final VoidCallback onPomodoroPressed;
  final double height;
  final EdgeInsets margin;
  final bool isDarkMode;
  final Color glassTint;

  @override
  Widget build(BuildContext context) {
    FloatingBottomNavigationItem buildWeeklyItem() {
      return FloatingBottomNavigationItem(
        key: weeklyButtonKey,
        label: '周视图',
        icon: Icons.calendar_today_outlined,
        selectedIcon: Icons.calendar_today_rounded,
        selectable: false,
        onPressed: onWeeklyPressed,
        semanticsLabel: '周视图',
      );
    }

    FloatingBottomNavigationItem buildAddItem() {
      return FloatingBottomNavigationItem(
        label: '新增',
        selectable: false,
        onPressed: onAddPressed,
        onLongPress: onAddLongPress,
        onLongPressStart: onAddLongPressStart,
        onLongPressMoveUpdate: onAddLongPressMoveUpdate,
        onLongPressEnd: onAddLongPressEnd,
        onLongPressCancel: onAddLongPressCancel,
        builder: (context, selectedLayer, interactive) => Center(
          child: AiWaterRippleBorder(
            isLight: Theme.of(context).brightness == Brightness.light,
            borderRadius: BorderRadius.circular(28),
            child: HomeBottomNavigationActionButton(
              buttonKey: selectedLayer ? null : addButtonKey,
              primaryColor: primaryColor,
              interactive: interactive,
              onPressed: onAddPressed,
              onLongPress: onAddLongPress,
              semanticsLabel: '新增',
              child: Icon(
                selectedLayer ? Icons.add_circle_rounded : Icons.add_rounded,
                color: Theme.of(context).colorScheme.onPrimary,
                size: 28,
              ),
            ),
          ),
        ),
      );
    }

    FloatingBottomNavigationItem buildPomodoroItem() {
      return FloatingBottomNavigationItem(
        key: pomodoroButtonKey,
        label: '番茄钟',
        icon: Icons.timer_outlined,
        selectedIcon: Icons.timer_rounded,
        selectable: false,
        onPressed: onPomodoroPressed,
        semanticsLabel: '番茄钟',
      );
    }

    final items = isWide
        ? <FloatingBottomNavigationItem>[
            buildWeeklyItem(),
            buildAddItem(),
            buildPomodoroItem(),
          ]
        : <FloatingBottomNavigationItem>[
            const FloatingBottomNavigationItem(
              icon: Icons.dashboard_outlined,
              selectedIcon: Icons.dashboard_rounded,
              label: '首页',
            ),
            buildWeeklyItem(),
            buildAddItem(),
            buildPomodoroItem(),
            const FloatingBottomNavigationItem(
              icon: Icons.center_focus_weak_rounded,
              selectedIcon: Icons.center_focus_strong_rounded,
              label: '专注',
            ),
          ];

    return FloatingBottomNavigationBar(
      items: items,
      selectedIndex: isWide ? 0 : selectedIndex,
      primaryColor: primaryColor,
      inactiveColor: inactiveColor,
      selectedBackgroundColor: selectedBackgroundColor,
      onTabSelected: onTabSelected,
      height: height,
      margin: margin,
      tint: glassTint,
      haloColor: primaryColor,
      isDark: isDarkMode,
      mobilePortraitOnly: false,
      showSelectionLens: !isWide,
      keyPrefix: 'home-bottom',
    );
  }
}
