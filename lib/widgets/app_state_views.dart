import 'package:flutter/material.dart';

class AppLoadingIndicator extends StatelessWidget {
  final double size;
  final double strokeWidth;

  const AppLoadingIndicator({super.key, this.size = 20, this.strokeWidth = 2});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CircularProgressIndicator(strokeWidth: strokeWidth),
    );
  }
}

class AppLoadingView extends StatelessWidget {
  final String? message;
  final EdgeInsetsGeometry padding;
  final double indicatorSize;

  const AppLoadingView({
    super.key,
    this.message,
    this.padding = const EdgeInsets.all(16),
    this.indicatorSize = 24,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: padding,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppLoadingIndicator(size: indicatorSize),
            if (message != null) ...[
              const SizedBox(height: 12),
              Text(
                message!,
                textAlign: TextAlign.center,
                style: TextStyle(color: colorScheme.onSurfaceVariant),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class AppEmptyState extends StatelessWidget {
  final IconData icon;
  final double iconSize;
  final Color? iconColor;
  final String title;
  final String? message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final Widget? action;
  final EdgeInsetsGeometry padding;

  const AppEmptyState({
    super.key,
    this.icon = Icons.inbox_outlined,
    this.iconSize = 56,
    this.iconColor,
    required this.title,
    this.message,
    this.actionLabel,
    this.onAction,
    this.action,
    this.padding = const EdgeInsets.all(32),
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: padding,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: iconSize,
              color:
                  iconColor ??
                  colorScheme.onSurfaceVariant.withValues(alpha: 0.55),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: colorScheme.onSurface,
              ),
            ),
            if (message != null) ...[
              const SizedBox(height: 8),
              Text(
                message!,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium
                    ?.copyWith(color: colorScheme.onSurfaceVariant),
              ),
            ],
            if (action != null) ...[
              const SizedBox(height: 16),
              action!,
            ] else if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 20),
              FilledButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}
