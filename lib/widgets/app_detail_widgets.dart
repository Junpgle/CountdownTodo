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

class AppDetailInfoCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;
  final Color? valueColor;
  final VoidCallback? onTap;

  const AppDetailInfoCard({
    super.key,
    required this.icon,
    required this.title,
    required this.value,
    this.valueColor,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    
    Widget card = Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: colorScheme.primary, size: 22),
          const SizedBox(height: 8),
          Text(title, style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant)),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 14, 
              fontWeight: FontWeight.bold, 
              color: valueColor ?? colorScheme.onSurface
            ),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );

    if (onTap != null) {
      card = Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: card,
        ),
      );
    }

    return card;
  }
}

class AppDetailWideCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;
  final VoidCallback? onTap;
  final bool isLink;
  final int maxLines;
  final Color? valueColor;

  const AppDetailWideCard({
    super.key,
    required this.icon,
    required this.title,
    required this.value,
    this.onTap,
    this.isLink = false,
    this.maxLines = 3,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    
    Widget card = Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          Icon(icon, color: colorScheme.primary, size: 22),
          const SizedBox(width: 12),
          Text(title, style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant)),
          const SizedBox(width: 16),
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Expanded(
                  child: Text(
                    value,
                    style: TextStyle(
                      fontSize: 14, 
                      fontWeight: FontWeight.bold, 
                      color: valueColor ?? (isLink ? colorScheme.primary : colorScheme.onSurface)
                    ),
                    textAlign: TextAlign.right,
                    maxLines: maxLines,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (isLink) ...[
                  const SizedBox(width: 4),
                  Icon(Icons.chevron_right_rounded, size: 18, color: colorScheme.primary),
                ],
              ],
            ),
          ),
        ],
      ),
    );

    if (onTap != null) {
      card = Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: card,
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: card,
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
  final List<Widget>? leftSections;

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
    this.leftSections,
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
            final contentWidth =
                constraints.maxWidth > 900 ? 900.0 : constraints.maxWidth;
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
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
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
                          if (leftSections != null && leftSections!.isNotEmpty) ...[
                            const SizedBox(height: 20),
                            ...leftSections!,
                          ],
                        ],
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
              if (leftSections != null && leftSections!.isNotEmpty) ...[
                const SizedBox(height: 20),
                ...leftSections!,
              ],
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
