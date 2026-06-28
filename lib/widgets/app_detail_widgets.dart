import 'package:flutter/material.dart';

import '../utils/theme_color_tokens.dart';

class AppDetailHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Color? color;
  final double iconSize;
  final double titleSize;
  final TextDecoration? titleDecoration;
  final Color? titleColor;
  final double? progress;
  final Color? progressColor;

  const AppDetailHeader({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.color,
    this.iconSize = 72,
    this.titleSize = 24,
    this.titleDecoration,
    this.titleColor,
    this.progress,
    this.progressColor,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final accent = color ?? colorScheme.primary;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: colorScheme.shadow.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Icon(icon, size: iconSize, color: accent),
          const SizedBox(height: 16),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: titleSize,
              fontWeight: FontWeight.bold,
              decoration: titleDecoration,
              color: titleColor ?? colorScheme.onSurface,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 8),
            Text(
              subtitle!,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: colorScheme.onSurfaceVariant,
                fontSize: 14,
              ),
            ),
          ],
          if (progress != null) ...[
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: progress!.clamp(0.0, 1.0),
                      minHeight: 8,
                      backgroundColor: accent.withValues(alpha: 0.1),
                      valueColor: AlwaysStoppedAnimation<Color>(
                        progressColor ?? accent,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  '${(progress!.clamp(0.0, 1.0) * 100).toInt()}%',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: progressColor ?? accent,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class AppDetailSection extends StatelessWidget {
  final String title;
  final List<Widget> children;
  final EdgeInsetsGeometry margin;
  final EdgeInsetsGeometry padding;

  const AppDetailSection({
    super.key,
    required this.title,
    required this.children,
    this.margin = const EdgeInsets.only(bottom: 20),
    this.padding = const EdgeInsets.all(20),
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      margin: margin,
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: colorScheme.onSurfaceVariant,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }
}

class AppDetailRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;
  final VoidCallback? onTap;
  final int valueMaxLines;
  final EdgeInsetsGeometry padding;

  const AppDetailRow({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor,
    this.onTap,
    this.valueMaxLines = 1,
    this.padding = const EdgeInsets.symmetric(vertical: 10),
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final row = Padding(
      padding: padding,
      child: Row(
        crossAxisAlignment: valueMaxLines > 1
            ? CrossAxisAlignment.start
            : CrossAxisAlignment.center,
        children: [
          Icon(icon, size: 18, color: colorScheme.onSurfaceVariant),
          const SizedBox(width: 12),
          Text(
            label,
            style: TextStyle(
              fontSize: 14,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              value,
              maxLines: valueMaxLines,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: valueColor ?? colorScheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
    if (onTap == null) return row;
    return InkWell(onTap: onTap, child: row);
  }
}

class AppDetailDivider extends StatelessWidget {
  const AppDetailDivider({super.key});

  @override
  Widget build(BuildContext context) {
    return Divider(
      height: 1,
      color: Theme.of(context).colorScheme.cdtDivider,
    );
  }
}

class AppDetailScreen extends StatelessWidget {
  final String appBarTitle;
  final IconData icon;
  final String title;
  final String? headerSubtitle;
  final Color? color;
  final double iconSize;
  final double titleSize;
  final TextDecoration? titleDecoration;
  final Color? titleColor;
  final double? progress;
  final Color? progressColor;
  final List<Widget> sections;
  final List<Widget>? appBarActions;
  final EdgeInsetsGeometry padding;
  final ScrollPhysics? scrollPhysics;
  final Color? backgroundColor;

  const AppDetailScreen({
    super.key,
    required this.appBarTitle,
    required this.icon,
    required this.title,
    this.headerSubtitle,
    this.color,
    this.iconSize = 72,
    this.titleSize = 24,
    this.titleDecoration,
    this.titleColor,
    this.progress,
    this.progressColor,
    required this.sections,
    this.appBarActions,
    this.padding = const EdgeInsets.all(24),
    this.scrollPhysics,
    this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        title: Text(appBarTitle),
        actions: appBarActions,
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth > 700;

          if (isWide) {
            final contentWidth = constraints.maxWidth > 900 ? 900.0 : constraints.maxWidth;
            final horizontalInset = (constraints.maxWidth - contentWidth) / 2;
            final resolvedPadding = padding.resolve(Directionality.of(context));

            return Center(
              child: SingleChildScrollView(
                physics: scrollPhysics,
                padding: EdgeInsets.symmetric(
                  horizontal: horizontalInset + resolvedPadding.left,
                  vertical: 48,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 4,
                      child: AppDetailHeader(
                        icon: icon,
                        title: title,
                        subtitle: headerSubtitle,
                        color: color,
                        iconSize: iconSize,
                        titleSize: titleSize,
                        titleDecoration: titleDecoration,
                        titleColor: titleColor,
                        progress: progress,
                        progressColor: progressColor,
                      ),
                    ),
                    const SizedBox(width: 32),
                    Expanded(
                      flex: 6,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: sections,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }

          return ListView(
            padding: padding,
            physics: scrollPhysics,
            children: [
              AppDetailHeader(
                icon: icon,
                title: title,
                subtitle: headerSubtitle,
                color: color,
                iconSize: iconSize,
                titleSize: titleSize,
                titleDecoration: titleDecoration,
                titleColor: titleColor,
                progress: progress,
                progressColor: progressColor,
              ),
              const SizedBox(height: 20),
              ...sections,
            ],
          );
        },
      ),
    );
  }
}

class AppMetricChip extends StatelessWidget {
  final String label;
  final Color color;
  final IconData? icon;

  const AppMetricChip({
    super.key,
    required this.label,
    required this.color,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        border: Border.all(color: color.withValues(alpha: 0.4)),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
