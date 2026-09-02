import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/finance_repository.dart';

/// Keeps finance tools comfortable on both a phone and a wide desktop window.
class FinancePageList extends StatelessWidget {
  final List<Widget> children;
  final double maxWidth;
  final double bottomPadding;

  const FinancePageList({
    super.key,
    required this.children,
    this.maxWidth = 1000,
    this.bottomPadding = 32,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      bottom: false,
      child: LayoutBuilder(builder: (context, constraints) {
        final inset = math.max(16.0, (constraints.maxWidth - maxWidth) / 2);
        return ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: EdgeInsets.fromLTRB(
            inset,
            12,
            inset,
            bottomPadding + MediaQuery.paddingOf(context).bottom,
          ),
          children: children,
        );
      }),
    );
  }
}

class FinancePageIntro extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;

  const FinancePageIntro({
    super.key,
    required this.icon,
    required this.title,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            color: colors.primaryContainer,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Icon(icon, color: colors.onPrimaryContainer),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: theme.textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 5),
              Text(description,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: colors.onSurfaceVariant, height: 1.5)),
            ],
          ),
        ),
      ],
    );
  }
}

class FinanceSectionCard extends StatelessWidget {
  final String? title;
  final String? description;
  final IconData? icon;
  final Widget child;
  final Color? color;
  final VoidCallback? onTap;

  const FinanceSectionCard({
    super.key,
    this.title,
    this.description,
    this.icon,
    required this.child,
    this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: color ?? colors.surfaceContainerLow,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: colors.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (title != null) ...[
                Row(children: [
                  if (icon != null) ...[
                    Icon(icon, color: colors.primary, size: 20),
                    const SizedBox(width: 10),
                  ],
                  Expanded(
                    child: Text(title!,
                        style: theme.textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w700)),
                  ),
                ]),
                if (description != null) ...[
                  const SizedBox(height: 6),
                  Text(description!,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: colors.onSurfaceVariant)),
                ],
                const SizedBox(height: 18),
              ],
              child,
            ],
          ),
        ),
      ),
    );
  }
}

/// Fields and metrics stack instead of squeezing labels at larger text sizes.
class FinanceAdaptiveFields extends StatelessWidget {
  final List<Widget> children;
  final double minChildWidth;
  final int maxColumns;
  final double spacing;

  const FinanceAdaptiveFields({
    super.key,
    required this.children,
    this.minChildWidth = 220,
    this.maxColumns = 2,
    this.spacing = 14,
  });

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) return const SizedBox.shrink();
    return LayoutBuilder(builder: (context, constraints) {
      final scale =
          math.max(1.0, MediaQuery.textScalerOf(context).scale(14) / 14);
      final columns =
          ((constraints.maxWidth + spacing) / (minChildWidth * scale + spacing))
              .floor()
              .clamp(1, math.min(maxColumns, children.length));
      final width = (constraints.maxWidth - spacing * (columns - 1)) / columns;
      return Wrap(
        spacing: spacing,
        runSpacing: spacing,
        children: [
          for (final child in children) SizedBox(width: width, child: child)
        ],
      );
    });
  }
}

class FinanceStatusBadge extends StatelessWidget {
  final String label;
  final IconData? icon;
  final bool highlighted;
  final bool isError;

  const FinanceStatusBadge({
    super.key,
    required this.label,
    this.icon,
    this.highlighted = false,
    this.isError = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final foreground = isError
        ? colors.onErrorContainer
        : highlighted
            ? colors.onSecondaryContainer
            : colors.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: isError
            ? colors.errorContainer
            : highlighted
                ? colors.secondaryContainer
                : colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text.rich(
        TextSpan(children: [
          if (icon != null)
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: Padding(
                padding: const EdgeInsets.only(right: 5),
                child: Icon(icon, size: 14, color: foreground),
              ),
            ),
          TextSpan(text: label),
        ]),
        style: Theme.of(context)
            .textTheme
            .labelMedium
            ?.copyWith(color: foreground),
      ),
    );
  }
}

class FinanceEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  final String? actionLabel;
  final VoidCallback? onAction;

  const FinanceEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.description,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return FinanceSectionCard(
      child: SizedBox(
        width: double.infinity,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 18),
          child: Column(children: [
            Icon(icon, size: 40, color: colors.primary),
            const SizedBox(height: 14),
            Text(title,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text(description,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: colors.onSurfaceVariant, height: 1.5)),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 18),
              FilledButton.tonal(
                  onPressed: onAction, child: Text(actionLabel!)),
            ],
          ]),
        ),
      ),
    );
  }
}

InputDecoration financeFieldDecoration(
  BuildContext context, {
  required String label,
  String? hint,
  IconData? icon,
  String? helper,
  String? suffix,
}) {
  final colors = Theme.of(context).colorScheme;
  return InputDecoration(
    labelText: label,
    hintText: hint,
    helperText: helper,
    helperMaxLines: 3,
    errorMaxLines: 3,
    suffixText: suffix,
    prefixIcon: icon == null ? null : Icon(icon, size: 20),
    filled: true,
    fillColor: colors.surface,
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide(color: colors.outlineVariant),
    ),
  );
}

class FinanceAmountField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final bool autofocus;
  final ValueChanged<String>? onChanged;

  const FinanceAmountField({
    super.key,
    required this.controller,
    this.label = '金额',
    this.autofocus = false,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      autofocus: autofocus,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
      decoration: financeFieldDecoration(context, label: label, hint: '0.00')
          .copyWith(
              prefixText: '¥ ',
              prefixStyle:
                  TextStyle(color: Theme.of(context).colorScheme.primary)),
      style: Theme.of(context)
          .textTheme
          .headlineMedium
          ?.copyWith(fontWeight: FontWeight.w700),
      validator: (value) =>
          parseFinanceAmount(value ?? '') == null ? '请输入大于 0、最多两位小数的金额' : null,
      onChanged: onChanged,
    );
  }
}

/// Uses explicit bounds instead of AlertDialog's intrinsic sizing, so adaptive
/// fields can lay out safely while the keyboard reduces the available height.
class FinanceEditorDialog extends StatelessWidget {
  final Widget title;
  final Widget content;
  final List<Widget> actions;

  const FinanceEditorDialog({
    super.key,
    required this.title,
    required this.content,
    required this.actions,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(8, 0, 8, 20),
                      child: Semantics(
                        namesRoute: true,
                        child: DefaultTextStyle(
                          style: Theme.of(context).textTheme.headlineSmall!,
                          child: title,
                        ),
                      ),
                    ),
                    content,
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: OverflowBar(
                alignment: MainAxisAlignment.end,
                spacing: 8,
                overflowSpacing: 8,
                children: actions,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class FinanceFormActions extends StatelessWidget {
  final bool isSaving;
  final VoidCallback onSave;
  final String label;

  const FinanceFormActions(
      {super.key,
      required this.isSaving,
      required this.onSave,
      required this.label});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(
            top: BorderSide(
                color: colors.outlineVariant.withValues(alpha: 0.5))),
      ),
      child: SafeArea(
        top: false,
        child: Center(
          heightFactor: 1,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 752),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: isSaving ? null : onSave,
                  style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 14)),
                  icon: isSaving
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.check_rounded),
                  label: Text(isSaving ? '保存中…' : label),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
