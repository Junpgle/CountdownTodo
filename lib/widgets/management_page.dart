import 'package:flutter/material.dart';

/// Theme-aware card surface. Content and actions remain caller-owned.
class ManagementCard extends StatelessWidget {
  const ManagementCard({
    super.key,
    required this.child,
    this.margin = const EdgeInsets.only(bottom: 12),
    this.padding = const EdgeInsets.all(16),
    this.borderRadius = 18,
    this.backgroundColor,
    this.borderColor,
    this.clipBehavior = Clip.none,
  });

  final Widget child;
  final EdgeInsetsGeometry margin;
  final EdgeInsetsGeometry padding;
  final double borderRadius;
  final Color? backgroundColor;
  final Color? borderColor;
  final Clip clipBehavior;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      margin: margin,
      color: backgroundColor ?? scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(borderRadius),
        side: BorderSide(
            color: borderColor ?? scheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      clipBehavior: clipBehavior,
      child: Padding(padding: padding, child: child),
    );
  }
}

/// Action row that wraps naturally on narrow screens or with large text.
/// Buttons retain their own callbacks, enabled states and confirmation flows.
class ManagementActionBar extends StatelessWidget {
  const ManagementActionBar({
    super.key,
    required this.children,
    this.alignment = WrapAlignment.end,
    this.crossAxisAlignment = WrapCrossAlignment.start,
    this.spacing = 8,
    this.runSpacing = 8,
  });

  final List<Widget> children;
  final WrapAlignment alignment;
  final WrapCrossAlignment crossAxisAlignment;
  final double spacing;
  final double runSpacing;

  @override
  Widget build(BuildContext context) => Wrap(
        alignment: alignment,
        crossAxisAlignment: crossAxisAlignment,
        spacing: spacing,
        runSpacing: runSpacing,
        children: children,
      );
}

class ManagementFilterOption<T> {
  const ManagementFilterOption({required this.value, required this.label});
  final T value;
  final String label;
}

/// Controlled, single-selection filter. The caller owns selection and data.
class ManagementFilterBar<T> extends StatelessWidget {
  const ManagementFilterBar(
      {super.key,
      required this.value,
      required this.options,
      required this.onChanged});

  final T value;
  final List<ManagementFilterOption<T>> options;
  final ValueChanged<T>? onChanged;

  @override
  Widget build(BuildContext context) => Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final option in options)
            ChoiceChip(
              key: ValueKey(option.value),
              label: Text(option.label),
              selected: option.value == value,
              onSelected:
                  onChanged == null ? null : (_) => onChanged!(option.value),
            ),
        ],
      );
}

/// Full-page or inline retry feedback; never starts requests on its own.
class ManagementLoadError extends StatelessWidget {
  const ManagementLoadError(
      {super.key,
      required this.title,
      this.description,
      required this.onRetry,
      this.inline = false});

  final String title;
  final String? description;
  final VoidCallback? onRetry;
  final bool inline;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (inline) {
      return Card(
        margin: const EdgeInsets.only(bottom: 16),
        elevation: 0,
        color: scheme.errorContainer,
        child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(title, style: TextStyle(color: scheme.onErrorContainer)),
                if (description != null) ...[
                  const SizedBox(height: 8),
                  Text(description!,
                      style: TextStyle(color: scheme.onErrorContainer)),
                ],
                Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: onRetry,
                      style: TextButton.styleFrom(
                          foregroundColor: scheme.onErrorContainer),
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('重新加载'),
                    )),
              ],
            )),
      );
    }
    return Column(children: [
      ManagementEmptyState(
          icon: Icons.cloud_off_outlined,
          title: title,
          description: description ?? ''),
      Center(
          child: FilledButton.tonalIcon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('重新加载'))),
    ]);
  }
}

/// Scrollable body for a bounded-height Scaffold or Expanded.
///
/// Keeps app bars, data loading, navigation and persistence in the caller.
/// See docs/ui/management_components.md for composition examples.
class ManagementPage extends StatelessWidget {
  const ManagementPage(
      {super.key, required this.children, this.maxWidth = 960});

  final List<Widget> children;
  final double maxWidth;

  @override
  Widget build(BuildContext context) => SafeArea(
        top: false,
        child: LayoutBuilder(builder: (context, constraints) {
          final inset = ((constraints.maxWidth - maxWidth) / 2)
              .clamp(16.0, double.infinity);
          return ListView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.fromLTRB(inset, 16, inset, 32),
            children: children,
          );
        }),
      );
}

class ManagementIntro extends StatelessWidget {
  const ManagementIntro(
      {super.key,
      required this.icon,
      required this.title,
      required this.description});

  final IconData icon;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(16)),
          child: Icon(icon, color: theme.colorScheme.onPrimaryContainer),
        ),
        const SizedBox(width: 14),
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title,
              style: theme.textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text(description,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        ])),
      ]),
    );
  }
}

class ManagementSearchField extends StatelessWidget {
  const ManagementSearchField(
      {super.key,
      required this.controller,
      required this.hintText,
      required this.onChanged});

  final TextEditingController controller;
  final String hintText;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) =>
      ValueListenableBuilder<TextEditingValue>(
        valueListenable: controller,
        builder: (context, value, _) => TextField(
          controller: controller,
          onChanged: onChanged,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: hintText,
            prefixIcon: const Icon(Icons.search_rounded),
            suffixIcon: value.text.isEmpty
                ? null
                : IconButton(
                    tooltip: '清空搜索',
                    onPressed: () {
                      controller.clear();
                      onChanged('');
                    },
                    icon: const Icon(Icons.close_rounded),
                  ),
            filled: true,
            fillColor: Theme.of(context).colorScheme.surfaceContainerLow,
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none),
          ),
        ),
      );
}

class ManagementEmptyState extends StatelessWidget {
  const ManagementEmptyState(
      {super.key,
      required this.icon,
      required this.title,
      required this.description});

  final IconData icon;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 36),
        child: Column(children: [
          Icon(icon, size: 44, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 16),
          Text(title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(description,
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ]),
      );
}
