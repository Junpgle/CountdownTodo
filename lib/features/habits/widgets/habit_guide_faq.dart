import 'package:flutter/material.dart';

/// 习惯领域指导卡中的单条常见问题问答项。
class HabitGuideFaqItem {
  final String question;
  final String answer;

  const HabitGuideFaqItem(this.question, this.answer);
}

/// 习惯指导卡共用的可折叠常见问题面板，使用 Material 3 动态配色。
class HabitGuideFaq extends StatelessWidget {
  final List<HabitGuideFaqItem> items;
  final String title;
  final IconData icon;
  final bool initiallyExpanded;

  const HabitGuideFaq({
    super.key,
    required this.items,
    this.title = '常见问题',
    this.icon = Icons.help_outline_rounded,
    this.initiallyExpanded = false,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Theme(
      data: Theme.of(
        context,
      ).copyWith(dividerColor: colorScheme.outlineVariant.withValues(alpha: 0)),
      child: Material(
        color: Colors.transparent,
        child: ExpansionTile(
          initiallyExpanded: initiallyExpanded,
          tilePadding: EdgeInsets.zero,
          childrenPadding: const EdgeInsets.only(bottom: 2),
          leading: Icon(icon, size: 19, color: colorScheme.primary),
          title: Text(
            title,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w800,
              color: colorScheme.onSurface,
            ),
          ),
          children: [
            for (final item in items)
              _HabitGuideFaqRow(item: item, colorScheme: colorScheme),
          ],
        ),
      ),
    );
  }
}

class _HabitGuideFaqRow extends StatelessWidget {
  final HabitGuideFaqItem item;
  final ColorScheme colorScheme;

  const _HabitGuideFaqRow({required this.item, required this.colorScheme});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, right: 4, bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            item.question,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
              color: colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            item.answer,
            style: TextStyle(
              fontSize: 11.5,
              height: 1.45,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
