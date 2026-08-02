import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/habit_adaptation_service.dart';

/// 领域化建议面板：可用于新建/编辑页和习惯详情页。
class HabitAdaptationPanel extends StatelessWidget {
  final HabitAdaptation adaptation;
  final double? currentValue;
  final double? targetValue;
  final ValueChanged<int>? onTargetSelected;
  final bool showTargetSuggestions;

  const HabitAdaptationPanel({
    super.key,
    required this.adaptation,
    this.currentValue,
    this.targetValue,
    this.onTargetSelected,
    this.showTargetSuggestions = true,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final progress =
        currentValue != null && targetValue != null && targetValue! > 0
            ? (currentValue! / targetValue!).clamp(0.0, 1.0)
            : null;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colorScheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: colorScheme.tertiary.withValues(alpha: 0.25),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.water_drop_rounded,
                  color: colorScheme.tertiary, size: 22),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  adaptation.title,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: colorScheme.onTertiaryContainer,
                  ),
                ),
              ),
              IconButton(
                tooltip: '查看参考文献',
                visualDensity: VisualDensity.compact,
                onPressed: () => showHabitCitations(context, adaptation),
                icon: Icon(Icons.menu_book_outlined,
                    size: 19, color: colorScheme.onTertiaryContainer),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            adaptation.headline,
            style: TextStyle(
              fontSize: 13,
              height: 1.45,
              fontWeight: FontWeight.w700,
              color: colorScheme.onTertiaryContainer,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            adaptation.explanation,
            style: TextStyle(
              fontSize: 12,
              height: 1.5,
              color: colorScheme.onTertiaryContainer.withValues(alpha: 0.85),
            ),
          ),
          if (progress != null) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 7,
                      backgroundColor: colorScheme.onTertiaryContainer
                          .withValues(alpha: 0.15),
                      valueColor: AlwaysStoppedAnimation(colorScheme.tertiary),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  '${_amount(currentValue!)} / ${_amount(targetValue!)} ml',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: colorScheme.onTertiaryContainer,
                  ),
                ),
              ],
            ),
          ],
          if (showTargetSuggestions && onTargetSelected != null) ...[
            const SizedBox(height: 12),
            Text(
              '快速选择每日目标',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: colorScheme.onTertiaryContainer,
              ),
            ),
            const SizedBox(height: 7),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: adaptation.targetSuggestions.map((suggestion) {
                final selected = targetValue == suggestion.value;
                return ChoiceChip(
                  selected: selected,
                  label: Text('${suggestion.label} ${suggestion.value} ml'),
                  onSelected: (_) => onTargetSelected!(suggestion.value),
                  selectedColor: colorScheme.tertiary,
                  labelStyle: TextStyle(
                    color: selected
                        ? colorScheme.onTertiary
                        : colorScheme.onTertiaryContainer,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                  ),
                );
              }).toList(),
            ),
          ],
          const SizedBox(height: 10),
          Text(
            adaptation.safetyNote,
            style: TextStyle(
              fontSize: 11,
              height: 1.45,
              color: colorScheme.onTertiaryContainer.withValues(alpha: 0.75),
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () => showHabitCitations(context, adaptation),
              icon: const Icon(Icons.open_in_new_rounded, size: 15),
              label: const Text('查看参考文献'),
              style: TextButton.styleFrom(
                foregroundColor: colorScheme.onTertiaryContainer,
                visualDensity: VisualDensity.compact,
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String _amount(double value) {
    return value == value.roundToDouble()
        ? value.round().toString()
        : value.toStringAsFixed(1);
  }
}

Future<void> showHabitCitations(
  BuildContext context,
  HabitAdaptation adaptation,
) async {
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Row(
        children: [
          Icon(Icons.menu_book_outlined,
              color: Theme.of(dialogContext).colorScheme.primary),
          const SizedBox(width: 8),
          const Expanded(child: Text('参考文献')),
        ],
      ),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: adaptation.citations
                .map((citation) => _CitationTile(citation: citation))
                .toList(),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('关闭'),
        ),
      ],
    ),
  );
}

class _CitationTile extends StatelessWidget {
  final HabitCitation citation;

  const _CitationTile({required this.citation});

  Future<void> _open(BuildContext context) async {
    final uri = Uri.parse(citation.url);
    if (await launchUrl(uri, mode: LaunchMode.platformDefault)) return;
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('无法打开参考文献链接')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(11),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(citation.title,
                style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 3),
            Text(citation.publisher,
                style: TextStyle(
                    fontSize: 11.5, color: colorScheme.onSurfaceVariant)),
            const SizedBox(height: 7),
            Text(citation.takeaway,
                style: TextStyle(
                    fontSize: 12, height: 1.45, color: colorScheme.onSurface)),
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () => _open(context),
                icon: const Icon(Icons.open_in_new_rounded, size: 15),
                label: const Text('打开原文'),
                style:
                    TextButton.styleFrom(visualDensity: VisualDensity.compact),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
