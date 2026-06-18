import 'package:flutter/material.dart';

import '../utils/theme_color_tokens.dart';

class AppSettingsSection extends StatelessWidget {
  final String title;
  final List<Widget> children;
  final Widget? trailing;
  final EdgeInsetsGeometry headerPadding;
  final double elevation;
  final BorderRadiusGeometry borderRadius;

  const AppSettingsSection({
    super.key,
    required this.title,
    required this.children,
    this.trailing,
    this.headerPadding = const EdgeInsets.only(left: 8, bottom: 8, top: 16),
    this.elevation = 2,
    this.borderRadius = const BorderRadius.all(Radius.circular(12)),
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppSettingsSectionHeader(
          title: title,
          trailing: trailing,
          padding: headerPadding,
        ),
        AppSettingsCard(
          elevation: elevation,
          borderRadius: borderRadius,
          child: Column(children: children),
        ),
      ],
    );
  }
}

class AppSettingsSectionHeader extends StatelessWidget {
  final String title;
  final Widget? trailing;
  final EdgeInsetsGeometry padding;

  const AppSettingsSectionHeader({
    super.key,
    required this.title,
    this.trailing,
    this.padding = const EdgeInsets.only(left: 8, bottom: 8, top: 16),
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: padding,
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

class AppSettingsCard extends StatelessWidget {
  final Widget child;
  final double elevation;
  final BorderRadiusGeometry borderRadius;

  const AppSettingsCard({
    super.key,
    required this.child,
    this.elevation = 2,
    this.borderRadius = const BorderRadius.all(Radius.circular(12)),
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: elevation,
      shape: RoundedRectangleBorder(borderRadius: borderRadius),
      child: child,
    );
  }
}

class AppSettingsHighlightedTile extends StatelessWidget {
  final String targetId;
  final String? highlightTarget;
  final Map<String, GlobalKey>? itemKeys;
  final Widget child;
  final BorderRadiusGeometry borderRadius;

  const AppSettingsHighlightedTile({
    super.key,
    required this.targetId,
    required this.child,
    this.highlightTarget,
    this.itemKeys,
    this.borderRadius = const BorderRadius.all(Radius.circular(8)),
  });

  @override
  Widget build(BuildContext context) {
    final isHighlighted = highlightTarget == targetId;
    return Container(
      key: itemKeys?[targetId],
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOut,
        decoration: BoxDecoration(
          color: isHighlighted
              ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.2)
              : Colors.transparent,
          borderRadius: borderRadius,
        ),
        child: child,
      ),
    );
  }
}

class AppSettingsDivider extends StatelessWidget {
  final double height;
  final double indent;
  final double endIndent;

  const AppSettingsDivider({
    super.key,
    this.height = 1,
    this.indent = 56,
    this.endIndent = 0,
  });

  @override
  Widget build(BuildContext context) {
    return Divider(
      height: height,
      indent: indent,
      endIndent: endIndent,
      color: Theme.of(context).colorScheme.cdtDivider,
    );
  }
}

class AppSettingsChoiceCard<T> extends StatelessWidget {
  final T value;
  final T groupValue;
  final String title;
  final IconData? icon;
  final ValueChanged<T>? onSelected;
  final EdgeInsetsGeometry padding;

  const AppSettingsChoiceCard({
    super.key,
    required this.value,
    required this.groupValue,
    required this.title,
    this.icon,
    this.onSelected,
    this.padding = const EdgeInsets.symmetric(vertical: 12),
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isSelected = value == groupValue;
    final foreground =
        isSelected ? colorScheme.primary : colorScheme.onSurfaceVariant;

    return Semantics(
      button: true,
      selected: isSelected,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onSelected == null ? null : () => onSelected!(value),
          child: Container(
            padding: padding,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: isSelected
                  ? colorScheme.primary.withValues(alpha: 0.1)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isSelected
                    ? colorScheme.primary
                    : colorScheme.outlineVariant,
                width: 1.5,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(icon, color: foreground, size: 20),
                  const SizedBox(height: 4),
                ],
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight:
                        isSelected ? FontWeight.bold : FontWeight.normal,
                    color: foreground,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
