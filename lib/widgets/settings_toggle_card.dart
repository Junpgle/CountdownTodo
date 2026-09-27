import 'package:flutter/material.dart';

import 'floating_glass_control.dart';

/// Shared animated toggle card used by settings sections.
class SettingsToggleCard extends StatelessWidget {
  const SettingsToggleCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.value,
    required this.onChanged,
    this.isDesktop = false,
    this.switchKey,
    this.unselectedTitleColor,
    this.mobileTopSpacing = 8,
    this.mobileUseSpacer = false,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final bool isDesktop;
  final Key? switchKey;
  final Color? unselectedTitleColor;
  final double mobileTopSpacing;
  final bool mobileUseSpacer;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final titleStyle = TextStyle(
      fontWeight: FontWeight.bold,
      fontSize: 14,
      color: value
          ? colorScheme.primary
          : unselectedTitleColor ?? theme.textTheme.bodyMedium?.color,
      fontFamily: theme.textTheme.bodyMedium?.fontFamily,
    );
    final iconWidget = AnimatedSwitcher(
      duration: const Duration(milliseconds: 400),
      switchInCurve: Curves.easeOutBack,
      switchOutCurve: Curves.easeInBack,
      transitionBuilder: (child, animation) => ScaleTransition(
        scale: animation,
        child: RotationTransition(
          turns: Tween<double>(begin: -0.1, end: 0).animate(animation),
          child: child,
        ),
      ),
      child: Icon(
        icon,
        key: ValueKey<bool>(value),
        color: value ? colorScheme.primary : colorScheme.onSurfaceVariant,
        size: isDesktop ? 28 : 32,
      ),
    );
    final switchWidget = SizedBox(
      height: 24,
      child: FittedBox(
        fit: BoxFit.fill,
        child: LiquidGlassSwitch(
          key: switchKey,
          value: value,
          onChanged: onChanged,
          activeThumbColor: colorScheme.primary,
        ),
      ),
    );
    final titleWidget = AnimatedDefaultTextStyle(
      duration: const Duration(milliseconds: 300),
      style: titleStyle,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      child: Text(title),
    );
    final subtitleWidget = Text(
      subtitle,
      maxLines: isDesktop ? 1 : 2,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
    );

    return GestureDetector(
      onTap: onChanged == null ? null : () => onChanged!(!value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
        padding: EdgeInsets.all(isDesktop ? 16 : 12),
        decoration: BoxDecoration(
          color: value
              ? colorScheme.primary.withValues(alpha: 0.1)
              : colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: value ? colorScheme.primary : Colors.transparent,
            width: 2,
          ),
        ),
        child: isDesktop
            ? Row(
                children: [
                  iconWidget,
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        titleWidget,
                        const SizedBox(height: 3),
                        subtitleWidget,
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  switchWidget,
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [iconWidget, switchWidget],
                  ),
                  if (mobileUseSpacer)
                    const Spacer()
                  else
                    SizedBox(height: mobileTopSpacing),
                  titleWidget,
                  const SizedBox(height: 2),
                  subtitleWidget,
                ],
              ),
      ),
    );
  }
}
