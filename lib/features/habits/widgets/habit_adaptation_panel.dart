import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/habit_goal_rule.dart';
import '../services/habit_adaptation_service.dart';
import '../../../utils/app_dialogs.dart';
import '../../../utils/time_utils.dart';
import 'habit_guide_faq.dart';

part 'habit_adaptation/habit_activity_guides.dart';
part 'habit_adaptation/habit_sleep_clock_guide.dart';

/// 领域化建议面板：可用于新建/编辑页和习惯详情页。
class HabitAdaptationPanel extends StatelessWidget {
  final HabitAdaptation adaptation;
  final double? currentValue;
  final double? targetValue;
  final ValueChanged<int>? onTargetSelected;
  final bool showTargetSuggestions;
  final String? targetUnitOverride;

  const HabitAdaptationPanel({
    super.key,
    required this.adaptation,
    this.currentValue,
    this.targetValue,
    this.onTargetSelected,
    this.showTargetSuggestions = true,
    this.targetUnitOverride,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final adaptationIcon = switch (adaptation.kind) {
      HabitAdaptationKind.hydration => Icons.water_drop_rounded,
      HabitAdaptationKind.pushUp => Icons.fitness_center_rounded,
      HabitAdaptationKind.running => Icons.directions_run_rounded,
      HabitAdaptationKind.reading => Icons.menu_book_rounded,
      HabitAdaptationKind.learning => Icons.school_rounded,
      HabitAdaptationKind.vocabulary => Icons.translate_rounded,
      HabitAdaptationKind.meditation => Icons.self_improvement_rounded,
      HabitAdaptationKind.earlyWake => Icons.wb_sunny_rounded,
      HabitAdaptationKind.earlySleep => Icons.bedtime_rounded,
      HabitAdaptationKind.sleepDuration => Icons.hotel_rounded,
      HabitAdaptationKind.quitSugaryDrinks => Icons.no_drinks_rounded,
    };
    final displayUnit = (targetUnitOverride ?? adaptation.targetUnit).trim();
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
        border: Border.all(color: colorScheme.tertiary.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(adaptationIcon, color: colorScheme.tertiary, size: 22),
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
                icon: Icon(
                  Icons.menu_book_outlined,
                  size: 19,
                  color: colorScheme.onTertiaryContainer,
                ),
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
                  '${_amount(currentValue!)} / ${_amount(targetValue!)}'
                  '${displayUnit.isNotEmpty ? ' $displayUnit' : ''}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: colorScheme.onTertiaryContainer,
                  ),
                ),
              ],
            ),
          ],
          if (showTargetSuggestions &&
              onTargetSelected != null &&
              adaptation.targetSuggestions.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              adaptation.targetSuggestionTitle,
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
                  label: Text(
                    '${suggestion.label} '
                    '${suggestion.displayValue ?? '${suggestion.value} $displayUnit'}',
                  ),
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

/// 俯卧撑的训练安排与动作质量提示。
class HabitPushUpGuide extends StatelessWidget {
  final int targetValue;
  final HabitPeriodType? periodType;

  const HabitPushUpGuide({
    super.key,
    required this.targetValue,
    this.periodType,
  });

  @override
  Widget build(BuildContext context) {
    final target = targetValue > 0 ? targetValue : 24;
    final setCount = target <= 12 ? 1 : math.min(5, (target / 12).ceil());
    final repsPerSet = (target / setCount).ceil();
    final frequency = periodType == HabitPeriodType.weekdays
        ? '当前：按指定训练日'
        : '建议：每周 2–3 天';

    return _HabitDomainGuide(
      icon: Icons.fitness_center_rounded,
      title: '训练安排',
      targetLabel: '$target 个/次',
      metrics: [
        _HabitGuideMetricData(
          icon: Icons.view_agenda_outlined,
          title: '分组完成',
          value: '$setCount 组 × $repsPerSet 个',
        ),
        _HabitGuideMetricData(
          icon: Icons.event_repeat_rounded,
          title: '训练频率',
          value: frequency,
        ),
      ],
      sectionTitle: '动作质量优先',
      tips: const [
        _HabitGuideTipData(
          icon: Icons.straighten_rounded,
          text: '头、背、髋尽量保持一条线，核心收紧。',
        ),
        _HabitGuideTipData(
          icon: Icons.swap_vert_rounded,
          text: '下放和撑起都保持受控，做不到标准姿势就降低难度。',
        ),
        _HabitGuideTipData(
          icon: Icons.pause_circle_outline_rounded,
          text: '组间充分休息；出现明显疼痛、头晕或异常气短时停止。',
        ),
      ],
      footer: const Padding(
        padding: EdgeInsets.only(top: 6),
        child: HabitGuideFaq(items: _pushUpFaqItems),
      ),
    );
  }
}

const List<HabitGuideFaqItem> _pushUpFaqItems = [
  HabitGuideFaqItem(
    '一次做得越多越好吗？',
    '不一定。俯卧撑的有效训练取决于动作质量、总训练量和持续性，不是单次硬撑到最大数量。出现塌腰、耸肩或动作幅度明显变小，就应停止这一组或降低难度。',
  ),
  HabitGuideFaqItem(
    '需要每天做吗？',
    '不需要。模板默认安排每周 2–3 个训练日，让同一肌群有恢复时间；其他日子可以休息，或训练下肢、背部等不同肌群。',
  ),
  HabitGuideFaqItem(
    '做不到标准俯卧撑怎么办？',
    '可以先从斜板俯卧撑、跪姿俯卧撑或更高支撑面开始。选择能保持身体稳定和完整控制的版本，比勉强做标准动作更合适。',
  ),
  HabitGuideFaqItem(
    '每组都要做到力竭吗？',
    '不需要。保留动作质量比做到完全力竭更重要；当下一次重复可能破坏姿势时结束这一组，之后再逐步增加次数或难度。',
  ),
  HabitGuideFaqItem(
    '肌肉酸痛还能继续做吗？',
    '轻微延迟性酸痛可以先休息或降低训练量；关节疼痛、刺痛、明显肿胀，或伴随胸闷头晕时不要硬练，应停止并视情况咨询专业人士。',
  ),
];

class _HabitGuideCardShell extends StatelessWidget {
  final IconData icon;
  final String title;
  final String trailingLabel;
  final FontWeight trailingFontWeight;
  final Widget child;

  const _HabitGuideCardShell({
    required this.icon,
    required this.title,
    required this.trailingLabel,
    this.trailingFontWeight = FontWeight.w800,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 19, color: colorScheme.primary),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: colorScheme.onSurface,
                ),
              ),
              const Spacer(),
              Text(
                trailingLabel,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: trailingFontWeight,
                  color: colorScheme.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _HabitGuideMetric extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;
  final ColorScheme colorScheme;

  const _HabitGuideMetric({
    required this.icon,
    required this.title,
    required this.value,
    required this.colorScheme,
  });

  factory _HabitGuideMetric.fromData(
    _HabitGuideMetricData data,
    ColorScheme colorScheme,
  ) {
    return _HabitGuideMetric(
      icon: data.icon,
      title: data.title,
      value: data.value,
      colorScheme: colorScheme,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, size: 17, color: colorScheme.primary),
          const SizedBox(width: 7),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 10.5,
                    color: colorScheme.onPrimaryContainer,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: colorScheme.onPrimaryContainer,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HabitGuideTip extends StatelessWidget {
  final IconData icon;
  final String text;
  final ColorScheme colorScheme;

  const _HabitGuideTip({
    required this.icon,
    required this.text,
    required this.colorScheme,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 15, color: colorScheme.onSurfaceVariant),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 11.5,
                height: 1.4,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CitationTile extends StatelessWidget {
  final HabitCitation citation;

  const _CitationTile({required this.citation});

  Future<void> _open(BuildContext context) async {
    final uri = Uri.parse(citation.url);
    if (await launchUrl(uri, mode: LaunchMode.platformDefault)) return;
    if (context.mounted) {
      AppSnackBars.showSnackBar(
        context,
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
            Text(
              citation.title,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 3),
            Text(
              citation.publisher,
              style: TextStyle(
                fontSize: 11.5,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 7),
            Text(
              citation.takeaway,
              style: TextStyle(
                fontSize: 12,
                height: 1.45,
                color: colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () => _open(context),
                icon: const Icon(Icons.open_in_new_rounded, size: 15),
                label: const Text('打开原文'),
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
