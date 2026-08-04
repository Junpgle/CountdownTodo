import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/habit_goal_rule.dart';
import '../services/habit_adaptation_service.dart';

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
          if (showTargetSuggestions && onTargetSelected != null) ...[
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
    final colorScheme = Theme.of(context).colorScheme;
    final target = targetValue > 0 ? targetValue : 24;
    final setCount = target <= 12 ? 1 : math.min(5, (target / 12).ceil());
    final repsPerSet = (target / setCount).ceil();
    final frequency =
        periodType == HabitPeriodType.weekdays ? '当前：按指定训练日' : '建议：每周 2–3 天';

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
              Icon(Icons.fitness_center_rounded,
                  size: 19, color: colorScheme.primary),
              const SizedBox(width: 8),
              Text(
                '训练安排',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: colorScheme.onSurface,
                ),
              ),
              const Spacer(),
              Text(
                '$target 个/次',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: colorScheme.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _HabitGuideMetric(
                  icon: Icons.view_agenda_outlined,
                  title: '分组完成',
                  value: '$setCount 组 × $repsPerSet 个',
                  colorScheme: colorScheme,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _HabitGuideMetric(
                  icon: Icons.event_repeat_rounded,
                  title: '训练频率',
                  value: frequency,
                  colorScheme: colorScheme,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            '动作质量优先',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 6),
          _HabitGuideTip(
            icon: Icons.straighten_rounded,
            text: '头、背、髋尽量保持一条线，核心收紧。',
            colorScheme: colorScheme,
          ),
          _HabitGuideTip(
            icon: Icons.swap_vert_rounded,
            text: '下放和撑起都保持受控，做不到标准姿势就降低难度。',
            colorScheme: colorScheme,
          ),
          _HabitGuideTip(
            icon: Icons.pause_circle_outline_rounded,
            text: '组间充分休息；出现明显疼痛、头晕或异常气短时停止。',
            colorScheme: colorScheme,
          ),
          const SizedBox(height: 6),
          const _PushUpFaq(),
        ],
      ),
    );
  }
}

class _PushUpFaq extends StatelessWidget {
  const _PushUpFaq();

  static const _items = [
    (
      '一次做得越多越好吗？',
      '不一定。俯卧撑的有效训练取决于动作质量、总训练量和持续性，不是单次硬撑到最大数量。出现塌腰、耸肩或动作幅度明显变小，就应停止这一组或降低难度。',
    ),
    (
      '需要每天做吗？',
      '不需要。模板默认安排每周 2–3 个训练日，让同一肌群有恢复时间；其他日子可以休息，或训练下肢、背部等不同肌群。',
    ),
    (
      '做不到标准俯卧撑怎么办？',
      '可以先从斜板俯卧撑、跪姿俯卧撑或更高支撑面开始。选择能保持身体稳定和完整控制的版本，比勉强做标准动作更合适。',
    ),
    (
      '每组都要做到力竭吗？',
      '不需要。保留动作质量比做到完全力竭更重要；当下一次重复可能破坏姿势时结束这一组，之后再逐步增加次数或难度。',
    ),
    (
      '肌肉酸痛还能继续做吗？',
      '轻微延迟性酸痛可以先休息或降低训练量；关节疼痛、刺痛、明显肿胀，或伴随胸闷头晕时不要硬练，应停止并视情况咨询专业人士。',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Theme(
      data: Theme.of(context).copyWith(
        dividerColor: colorScheme.outlineVariant.withValues(alpha: 0),
      ),
      child: Material(
        color: Colors.transparent,
        child: ExpansionTile(
          initiallyExpanded: false,
          tilePadding: EdgeInsets.zero,
          childrenPadding: const EdgeInsets.only(bottom: 2),
          leading: Icon(Icons.help_outline_rounded,
              size: 19, color: colorScheme.primary),
          title: Text(
            '常见问题',
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w800,
              color: colorScheme.onSurface,
            ),
          ),
          children: [
            for (final item in _items)
              _PushUpFaqItem(
                question: item.$1,
                answer: item.$2,
                colorScheme: colorScheme,
              ),
          ],
        ),
      ),
    );
  }
}

class _PushUpFaqItem extends StatelessWidget {
  final String question;
  final String answer;
  final ColorScheme colorScheme;

  const _PushUpFaqItem({
    required this.question,
    required this.answer,
    required this.colorScheme,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, right: 4, bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            question,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
              color: colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            answer,
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

/// 跑步的每次目标、每周总量和安全起步提示。
class HabitRunningGuide extends StatelessWidget {
  final int targetValue;
  final HabitPeriodType periodType;
  final int weekdaysMask;
  final String? unit;

  const HabitRunningGuide({
    super.key,
    required this.targetValue,
    required this.periodType,
    this.weekdaysMask = 127,
    this.unit,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final target = targetValue > 0 ? targetValue : 30;
    final normalizedUnit = (unit ?? '分钟').trim().toLowerCase();
    final isDurationUnit = normalizedUnit.isEmpty ||
        normalizedUnit == '分钟' ||
        normalizedUnit == 'minute' ||
        normalizedUnit == 'minutes' ||
        normalizedUnit == 'min';
    final isWeeklyTarget = periodType == HabitPeriodType.weekly;
    final sessions = _sessionsPerWeek();
    final weeklyMinutes = isDurationUnit
        ? isWeeklyTarget
            ? target
            : sessions == null
                ? null
                : target * sessions
        : null;
    final schedule = _scheduleLabel(sessions);
    final targetLabel = isWeeklyTarget ? '$target 分钟/周' : '$target 分钟/次';
    final weeklyLabel =
        weeklyMinutes == null ? '切换为分钟后计算' : '$weeklyMinutes 分钟/周';

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
              Icon(Icons.directions_run_rounded,
                  size: 19, color: colorScheme.primary),
              const SizedBox(width: 8),
              Text(
                '跑步安排',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: colorScheme.onSurface,
                ),
              ),
              const Spacer(),
              Text(
                targetLabel,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: colorScheme.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _HabitGuideMetric(
                  icon: Icons.event_repeat_rounded,
                  title: '当前安排',
                  value: schedule,
                  colorScheme: colorScheme,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _HabitGuideMetric(
                  icon: Icons.timelapse_rounded,
                  title: '估算周总量',
                  value: weeklyLabel,
                  colorScheme: colorScheme,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            '运动量参考',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 6),
          _HabitGuideTip(
            icon: Icons.flag_outlined,
            text: '成年人每周可先以 75 分钟高强度，或 150 分钟中等强度有氧活动为起点；跑步强度因人而异。',
            colorScheme: colorScheme,
          ),
          _HabitGuideTip(
            icon: Icons.record_voice_over_outlined,
            text: '能说完整句但不能唱歌≈中等强度；只能说几句话就要换气≈高强度。',
            colorScheme: colorScheme,
          ),
          _HabitGuideTip(
            icon: Icons.directions_walk_rounded,
            text: '每次先快走 5–10 分钟热身，结束后放慢走几分钟；初学者可跑走交替，跑步日之间留恢复时间。',
            colorScheme: colorScheme,
          ),
          if (!isDurationUnit) ...[
            const SizedBox(height: 9),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: colorScheme.tertiaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '当前单位为“$unit”。健康指南以每周活动时长衡量，建议改用“分钟”记录，便于判断周运动量。',
                style: TextStyle(
                  fontSize: 11.5,
                  height: 1.4,
                  color: colorScheme.onTertiaryContainer,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  int? _sessionsPerWeek() {
    switch (periodType) {
      case HabitPeriodType.daily:
        return 7;
      case HabitPeriodType.weekdays:
        var count = 0;
        for (var i = 0; i < 7; i++) {
          if ((weekdaysMask & (1 << i)) != 0) count++;
        }
        return count == 0 ? null : count;
      case HabitPeriodType.weekly:
      case HabitPeriodType.monthly:
      case HabitPeriodType.custom:
        return null;
    }
  }

  String _scheduleLabel(int? sessions) {
    switch (periodType) {
      case HabitPeriodType.daily:
        return '每天 · 约 7 次/周';
      case HabitPeriodType.weekdays:
        return sessions == null ? '未选择训练日' : '$sessions 次/周';
      case HabitPeriodType.weekly:
        return '每周累计';
      case HabitPeriodType.monthly:
        return '按月安排';
      case HabitPeriodType.custom:
        return '自定义周期';
    }
  }
}

/// 阅读的专注节奏、理解闭环与屏幕阅读提示。
class HabitReadingGuide extends StatelessWidget {
  final int targetMinutes;
  final int? defaultFocusMinutes;
  final HabitPeriodType periodType;
  final int weekdaysMask;

  const HabitReadingGuide({
    super.key,
    required this.targetMinutes,
    this.defaultFocusMinutes,
    required this.periodType,
    this.weekdaysMask = 127,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final target = targetMinutes > 0 ? targetMinutes : 30;
    final focus = math.min(defaultFocusMinutes ?? 25, target);
    final schedule = _scheduleLabel();
    final pace = _paceLabel(target, focus);
    final targetLabel =
        periodType == HabitPeriodType.weekly ? '$target 分钟/周' : '$target 分钟/天';

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
              Icon(Icons.menu_book_rounded,
                  size: 19, color: colorScheme.primary),
              const SizedBox(width: 8),
              Text(
                '阅读安排',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: colorScheme.onSurface,
                ),
              ),
              const Spacer(),
              Text(
                targetLabel,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: colorScheme.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _HabitGuideMetric(
                  icon: Icons.timer_outlined,
                  title: '专注节奏',
                  value: pace,
                  colorScheme: colorScheme,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _HabitGuideMetric(
                  icon: Icons.event_repeat_rounded,
                  title: '阅读安排',
                  value: schedule,
                  colorScheme: colorScheme,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            '把阅读变成理解闭环',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 6),
          _HabitGuideTip(
            icon: Icons.help_outline_rounded,
            text: '读前：用 30 秒写下今天想回答的问题或阅读目的。',
            colorScheme: colorScheme,
          ),
          _HabitGuideTip(
            icon: Icons.bookmark_outline_rounded,
            text: '读中：少量标记关键内容，每读完一小节停下来概括一句。',
            colorScheme: colorScheme,
          ),
          _HabitGuideTip(
            icon: Icons.lightbulb_outline_rounded,
            text: '读后：合上书回忆 3 个要点；学习型内容下次先复述上次内容。',
            colorScheme: colorScheme,
          ),
          _HabitGuideTip(
            icon: Icons.visibility_outlined,
            text: '屏幕阅读可采用 20-20-20：每 20 分钟看向约 6 米外 20 秒。',
            colorScheme: colorScheme,
          ),
          const SizedBox(height: 6),
          const _ReadingFaq(),
        ],
      ),
    );
  }

  String _scheduleLabel() {
    switch (periodType) {
      case HabitPeriodType.daily:
        return '每天 · 7 次/周';
      case HabitPeriodType.weekdays:
        var count = 0;
        for (var i = 0; i < 7; i++) {
          if ((weekdaysMask & (1 << i)) != 0) count++;
        }
        return '$count 次/周';
      case HabitPeriodType.weekly:
        return '每周累计';
      case HabitPeriodType.monthly:
        return '按月安排';
      case HabitPeriodType.custom:
        return '自定义周期';
    }
  }

  String _paceLabel(int target, int focus) {
    if (target <= focus) return '$target 分钟 × 1 块';
    final fullBlocks = target ~/ focus;
    final remainder = target % focus;
    if (remainder == 0) return '$focus 分钟 × $fullBlocks 块';
    return '$focus 分钟 × $fullBlocks + $remainder 分钟';
  }
}

class _ReadingFaq extends StatelessWidget {
  const _ReadingFaq();

  static const _items = [
    (
      '一定要每天读 30 分钟吗？',
      '不一定。30 分钟只是可编辑起点，没有适合所有人的统一阅读处方。先选择能长期坚持的时长，比一开始定得很高更重要。',
    ),
    (
      '读得越久、页数越多越好吗？',
      '不一定。阅读还包括理解和回忆；如果注意力已经明显下降，可以先停下来休息或拆成两个阅读块。',
    ),
    (
      '只读不做笔记可以吗？',
      '可以。笔记不是必需品，但读完后用自己的话回忆一句或说出 3 个要点，通常比被动重读更能检验理解。',
    ),
    (
      '纸书和电子书应该选哪个？',
      '优先选择更容易持续、眼睛和姿势更舒服的载体。屏幕阅读时注意远眺、眨眼和亮度，出现持续不适就减少屏幕时长。',
    ),
    (
      '今天读不下去怎么办？',
      '把目标降到 10–15 分钟，换成更容易进入状态的章节，或者只完成“读一小节并复述一句”；先保留节奏，再逐步增加。',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Theme(
      data: Theme.of(context).copyWith(
        dividerColor: colorScheme.outlineVariant.withValues(alpha: 0),
      ),
      child: Material(
        color: Colors.transparent,
        child: ExpansionTile(
          initiallyExpanded: false,
          tilePadding: EdgeInsets.zero,
          childrenPadding: const EdgeInsets.only(bottom: 2),
          leading: Icon(Icons.help_outline_rounded,
              size: 19, color: colorScheme.primary),
          title: Text(
            '常见问题',
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w800,
              color: colorScheme.onSurface,
            ),
          ),
          children: [
            for (final item in _items)
              _ReadingFaqItem(
                question: item.$1,
                answer: item.$2,
                colorScheme: colorScheme,
              ),
          ],
        ),
      ),
    );
  }
}

class _ReadingFaqItem extends StatelessWidget {
  final String question;
  final String answer;
  final ColorScheme colorScheme;

  const _ReadingFaqItem({
    required this.question,
    required this.answer,
    required this.colorScheme,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, right: 4, bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            question,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
              color: colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            answer,
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

/// 学习、单词和冥想共用的轻量领域指导卡，避免把建议硬编码进通用目标控件。
class _HabitDomainGuide extends StatelessWidget {
  final IconData icon;
  final String title;
  final String targetLabel;
  final List<_HabitGuideMetricData> metrics;
  final String sectionTitle;
  final List<_HabitGuideTipData> tips;

  const _HabitDomainGuide({
    required this.icon,
    required this.title,
    required this.targetLabel,
    required this.metrics,
    required this.sectionTitle,
    required this.tips,
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
                targetLabel,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: colorScheme.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              for (var i = 0; i < metrics.length; i++) ...[
                if (i > 0) const SizedBox(width: 10),
                Expanded(
                    child: _HabitGuideMetric.fromData(metrics[i], colorScheme)),
              ],
            ],
          ),
          const SizedBox(height: 12),
          Text(
            sectionTitle,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 6),
          for (final tip in tips)
            _HabitGuideTip(
              icon: tip.icon,
              text: tip.text,
              colorScheme: colorScheme,
            ),
        ],
      ),
    );
  }
}

class _HabitGuideMetricData {
  final IconData icon;
  final String title;
  final String value;

  const _HabitGuideMetricData({
    required this.icon,
    required this.title,
    required this.value,
  });
}

class _HabitGuideTipData {
  final IconData icon;
  final String text;

  const _HabitGuideTipData({required this.icon, required this.text});
}

/// 主动回忆、间隔复习和专注块的学习安排。
class HabitLearningGuide extends StatelessWidget {
  final int targetMinutes;
  final int? defaultFocusMinutes;
  final HabitPeriodType periodType;
  final int weekdaysMask;

  const HabitLearningGuide({
    super.key,
    required this.targetMinutes,
    this.defaultFocusMinutes,
    required this.periodType,
    this.weekdaysMask = 127,
  });

  @override
  Widget build(BuildContext context) {
    final target = targetMinutes > 0 ? targetMinutes : 45;
    final focus = math.min(defaultFocusMinutes ?? 25, target);
    return _HabitDomainGuide(
      icon: Icons.school_rounded,
      title: '学习安排',
      targetLabel: _habitPeriodTargetLabel(target, periodType, '分钟'),
      metrics: [
        _HabitGuideMetricData(
          icon: Icons.timer_outlined,
          title: '专注节奏',
          value: _habitBlockLabel(target, focus),
        ),
        _HabitGuideMetricData(
          icon: Icons.event_repeat_rounded,
          title: '学习安排',
          value: _habitScheduleLabel(periodType, weekdaysMask),
        ),
      ],
      sectionTitle: '把学习变成记忆闭环',
      tips: const [
        _HabitGuideTipData(
          icon: Icons.flag_outlined,
          text: '开始前：写下这一块要解决的一个问题或产出。',
        ),
        _HabitGuideTipData(
          icon: Icons.visibility_off_outlined,
          text: '结束后：合上资料，先凭记忆说出 3 个要点，再查看遗漏。',
        ),
        _HabitGuideTipData(
          icon: Icons.event_repeat_outlined,
          text: '之后：把困难内容安排到后续间隔复习，不要只在当天反复重读。',
        ),
        _HabitGuideTipData(
          icon: Icons.pause_circle_outline_rounded,
          text: '专注块之间可以短暂走动、喝水或远眺；总时长不必一次完成。',
        ),
      ],
    );
  }
}

/// 将新增和复习拆开，避免单词目标退化成只追求新增量。
class HabitVocabularyGuide extends StatelessWidget {
  final int targetValue;
  final HabitPeriodType periodType;
  final int weekdaysMask;
  final String unit;

  const HabitVocabularyGuide({
    super.key,
    required this.targetValue,
    required this.periodType,
    this.weekdaysMask = 127,
    this.unit = '个',
  });

  @override
  Widget build(BuildContext context) {
    final target = targetValue > 0 ? targetValue : 30;
    final displayUnit = unit.trim().isEmpty ? '个' : unit.trim();
    return _HabitDomainGuide(
      icon: Icons.translate_rounded,
      title: '单词安排',
      targetLabel: _habitPeriodTargetLabel(target, periodType, displayUnit),
      metrics: [
        _HabitGuideMetricData(
          icon: Icons.format_list_numbered_rounded,
          title: '每日目标',
          value: '$target $displayUnit',
        ),
        _HabitGuideMetricData(
          icon: Icons.sync_rounded,
          title: '建议拆分',
          value: _vocabularySplitLabel(target),
        ),
      ],
      sectionTitle: '让词汇进入长期记忆',
      tips: const [
        _HabitGuideTipData(
          icon: Icons.replay_rounded,
          text: '先完成到期复习，再添加新词；复习时遮住释义主动回忆。',
        ),
        _HabitGuideTipData(
          icon: Icons.edit_note_rounded,
          text: '对容易混淆的词补一个短语或例句，不必为每个词制作很长笔记。',
        ),
        _HabitGuideTipData(
          icon: Icons.event_repeat_outlined,
          text: '当天、隔天和更晚时间都安排短暂回忆，按实际记忆表现调整间隔。',
        ),
        _HabitGuideTipData(
          icon: Icons.tune_rounded,
          text: '连续几天遗忘较多时，先减少新增量，不要用更快刷词来掩盖复习不足。',
        ),
      ],
    );
  }
}

/// 以短时、稳定和不评判的练习方式呈现冥想建议。
class HabitMeditationGuide extends StatelessWidget {
  final int targetMinutes;
  final HabitPeriodType periodType;
  final int weekdaysMask;

  const HabitMeditationGuide({
    super.key,
    required this.targetMinutes,
    required this.periodType,
    this.weekdaysMask = 127,
  });

  @override
  Widget build(BuildContext context) {
    final target = targetMinutes > 0 ? targetMinutes : 10;
    return _HabitDomainGuide(
      icon: Icons.self_improvement_rounded,
      title: '冥想安排',
      targetLabel: _habitPeriodTargetLabel(target, periodType, '分钟'),
      metrics: [
        _HabitGuideMetricData(
          icon: Icons.timer_outlined,
          title: '练习时长',
          value: '$target 分钟',
        ),
        _HabitGuideMetricData(
          icon: Icons.event_repeat_rounded,
          title: '练习安排',
          value: _habitScheduleLabel(periodType, weekdaysMask),
        ),
      ],
      sectionTitle: '用一个锚点完成练习',
      tips: const [
        _HabitGuideTipData(
          icon: Icons.air_rounded,
          text: '选择呼吸、声音或身体感受作为锚点，坐姿以舒适和稳定为先。',
        ),
        _HabitGuideTipData(
          icon: Icons.refresh_rounded,
          text: '注意力走神很正常；发现后温和地回到锚点，不把走神当成失败。',
        ),
        _HabitGuideTipData(
          icon: Icons.directions_walk_rounded,
          text: '结束后先活动一下再进入下一件事，让练习和日常生活自然衔接。',
        ),
        _HabitGuideTipData(
          icon: Icons.warning_amber_rounded,
          text: '若练习引发明显恐慌、解离或持续低落，先停止并寻求专业帮助。',
        ),
      ],
    );
  }
}

String _habitPeriodTargetLabel(
  int target,
  HabitPeriodType periodType,
  String unit,
) {
  final suffix = periodType == HabitPeriodType.weekly ? '/周' : '/天';
  return '$target $unit$suffix';
}

String _habitBlockLabel(int target, int focus) {
  final safeFocus = math.max(1, focus);
  if (target <= safeFocus) return '$target 分钟 × 1 块';
  final fullBlocks = target ~/ safeFocus;
  final remainder = target % safeFocus;
  if (remainder == 0) return '$safeFocus 分钟 × $fullBlocks 块';
  return '$safeFocus 分钟 × $fullBlocks + $remainder 分钟';
}

String _habitScheduleLabel(HabitPeriodType periodType, int weekdaysMask) {
  switch (periodType) {
    case HabitPeriodType.daily:
      return '每天 · 7 次/周';
    case HabitPeriodType.weekdays:
      var count = 0;
      for (var i = 0; i < 7; i++) {
        if ((weekdaysMask & (1 << i)) != 0) count++;
      }
      return '$count 次/周';
    case HabitPeriodType.weekly:
      return '每周累计';
    case HabitPeriodType.monthly:
      return '按月安排';
    case HabitPeriodType.custom:
      return '自定义周期';
  }
}

String _vocabularySplitLabel(int target) {
  if (target >= 30) return '10 新 + ${target - 10} 复习';
  if (target >= 20) return '5 新 + ${target - 5} 复习';
  return '以复习为主';
}

/// 早起 / 早睡的时间关系提示。
///
/// 目标时间不是医学上的统一标准，这里只根据 7–9 小时的常用成人睡眠
/// 建议做反推，帮助用户发现目标时间是否会压缩睡眠。
class HabitSleepTimingGuide extends StatelessWidget {
  final HabitAdaptation adaptation;
  final int targetMinute;
  final ValueChanged<int>? onTargetChanged;

  const HabitSleepTimingGuide({
    super.key,
    required this.adaptation,
    required this.targetMinute,
    this.onTargetChanged,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isWake = adaptation.kind == HabitAdaptationKind.earlyWake;
    final counterpartMinute =
        isWake ? targetMinute - 8 * 60 : targetMinute + 8 * 60;
    final counterpartLabel = isWake ? '建议入睡' : '建议起床';
    final counterpartRange = isWake
        ? '${_formatMinute(targetMinute - 9 * 60)}–'
            '${_formatMinute(targetMinute - 7 * 60)}'
        : '${_formatMinute(targetMinute + 7 * 60)}–'
            '${_formatMinute(targetMinute + 9 * 60)}';

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
              Icon(Icons.bedtime_outlined,
                  size: 19, color: colorScheme.primary),
              const SizedBox(width: 8),
              Text(
                '睡眠时间反推',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: colorScheme.onSurface,
                ),
              ),
              const Spacer(),
              Text(
                '7–9 小时',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: colorScheme.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          HabitSleepClock(
            goalMinute: targetMinute,
            goalLabel: isWake ? '目标起床' : '目标入睡',
            counterpartMinute: counterpartMinute,
            counterpartLabel: counterpartLabel,
            counterpartRangeLabel: counterpartRange,
            goalIsSleep: !isWake,
            onTargetChanged: onTargetChanged,
          ),
          const SizedBox(height: 10),
          if (onTargetChanged != null)
            Text(
              '拖动目标时针调整小时，拖动分针调整分钟；起床标记会随睡眠时长同步反推。',
              style: TextStyle(
                fontSize: 11.5,
                height: 1.45,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          if (onTargetChanged != null) const SizedBox(height: 6),
          Text(
            '目标时间只是可持续作息的锚点；尽量让入睡和起床时间每天保持相近，周末也不要大幅漂移。',
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

  String _formatMinute(int minute) {
    final normalized = minute % (24 * 60);
    final safe = normalized < 0 ? normalized + 24 * 60 : normalized;
    final hour = safe ~/ 60;
    final min = safe % 60;
    return '${hour.toString().padLeft(2, '0')}:${min.toString().padLeft(2, '0')}';
  }
}

/// 新建配对目标时，展示已有早睡 / 早起目标反推出的建议。
class HabitSleepPairSuggestionCard extends StatelessWidget {
  final HabitSleepPairSuggestion suggestion;
  final int currentTargetMinute;
  final ValueChanged<int> onApply;

  const HabitSleepPairSuggestionCard({
    super.key,
    required this.suggestion,
    required this.currentTargetMinute,
    required this.onApply,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final targetLabel =
        suggestion.targetKind == HabitAdaptationKind.earlyWake ? '早起' : '早睡';
    final sourceLabel =
        suggestion.sourceKind == HabitAdaptationKind.earlyWake ? '早起' : '早睡';
    final applied = currentTargetMinute == suggestion.recommendedMinute;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorScheme.secondary.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.sync_alt_rounded,
                  size: 19, color: colorScheme.onSecondaryContainer),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '根据已有目标自动反推',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: colorScheme.onSecondaryContainer,
                  ),
                ),
              ),
              if (applied)
                Icon(Icons.check_circle_rounded,
                    size: 18, color: colorScheme.onSecondaryContainer),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '已有「${suggestion.sourceName}」$sourceLabel目标 '
            '${_formatMinute(suggestion.sourceMinute)}：'
            '建议将「$targetLabel」设置为 ${_formatMinute(suggestion.recommendedMinute)}。',
            style: TextStyle(
              fontSize: 12.5,
              height: 1.45,
              color: colorScheme.onSecondaryContainer,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '按 7–9 小时睡眠反推的建议区间：'
            '${_formatMinute(suggestion.rangeStartMinute)}–'
            '${_formatMinute(suggestion.rangeEndMinute)}。默认先采用 8 小时，可手动修改。',
            style: TextStyle(
              fontSize: 11.5,
              height: 1.45,
              color: colorScheme.onSecondaryContainer.withValues(alpha: 0.82),
            ),
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.tonalIcon(
              onPressed:
                  applied ? null : () => onApply(suggestion.recommendedMinute),
              icon: Icon(
                applied ? Icons.check_rounded : Icons.auto_awesome_rounded,
                size: 16,
              ),
              label: Text(applied ? '已应用建议' : '应用 8 小时建议'),
            ),
          ),
        ],
      ),
    );
  }

  String _formatMinute(int minute) {
    final normalized = minute % (24 * 60);
    final safe = normalized < 0 ? normalized + 24 * 60 : normalized;
    final hour = safe ~/ 60;
    final min = safe % 60;
    return '${hour.toString().padLeft(2, '0')}:${min.toString().padLeft(2, '0')}';
  }
}

/// 一个可交互的大时钟：目标时间使用时针 / 分针，另一端使用彩色标记。
///
/// 目标时间只保存一个时间点；拖动另一端的起床 / 入睡标记时，会按 8 小时
/// 反推目标时间，避免引入第二个不落库的目标字段。
class HabitSleepClock extends StatefulWidget {
  final int goalMinute;
  final String goalLabel;
  final int counterpartMinute;
  final String counterpartLabel;
  final String? counterpartRangeLabel;
  final bool goalIsSleep;
  final ValueChanged<int>? onTargetChanged;

  const HabitSleepClock({
    super.key,
    required this.goalMinute,
    required this.goalLabel,
    required this.counterpartMinute,
    required this.counterpartLabel,
    required this.counterpartRangeLabel,
    required this.goalIsSleep,
    this.onTargetChanged,
  });

  @override
  State<HabitSleepClock> createState() => _HabitSleepClockState();
}

enum _SleepClockDragMode { hour, minute, counterpart }

class _HabitSleepClockState extends State<HabitSleepClock> {
  _SleepClockDragMode? _dragMode;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final goalText = _formatMinute(widget.goalMinute);
    final counterpartText = _formatMinute(widget.counterpartMinute);
    return Column(
      children: [
        Semantics(
          container: true,
          label: '${widget.goalLabel} $goalText，'
              '${widget.counterpartLabel} $counterpartText'
              '${widget.counterpartRangeLabel == null ? '' : '，建议窗口 ${widget.counterpartRangeLabel}'}',
          child: Align(
            alignment: Alignment.center,
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: 320,
                maxHeight: 320,
              ),
              child: AspectRatio(
                aspectRatio: 1,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final size =
                        Size(constraints.maxWidth, constraints.maxHeight);
                    return GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onPanStart: widget.onTargetChanged == null
                          ? null
                          : (details) =>
                              _startDrag(details.localPosition, size),
                      onPanUpdate: widget.onTargetChanged == null
                          ? null
                          : (details) =>
                              _updateDrag(details.localPosition, size),
                      onPanEnd: widget.onTargetChanged == null
                          ? null
                          : (_) => setState(() => _dragMode = null),
                      onPanCancel: widget.onTargetChanged == null
                          ? null
                          : () => setState(() => _dragMode = null),
                      child: CustomPaint(
                        painter: _SleepScheduleClockPainter(
                          goalMinute: widget.goalMinute,
                          counterpartMinute: widget.counterpartMinute,
                          goalIsSleep: widget.goalIsSleep,
                          activeMode: _dragMode,
                          colorScheme: colorScheme,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 14,
          runSpacing: 5,
          children: [
            _SleepClockLegend(
              color: colorScheme.primary,
              label: '${widget.goalLabel} $goalText',
              colorScheme: colorScheme,
            ),
            _SleepClockLegend(
              color: colorScheme.tertiary,
              label: '${widget.counterpartLabel} $counterpartText',
              colorScheme: colorScheme,
            ),
          ],
        ),
        if (widget.counterpartRangeLabel != null) ...[
          const SizedBox(height: 4),
          Text(
            '建议窗口 ${widget.counterpartRangeLabel}',
            style: TextStyle(
              fontSize: 11,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }

  void _startDrag(Offset position, Size size) {
    final geometry = _SleepClockGeometry.fromSize(size);
    final points = <_SleepClockDragMode, Offset>{
      _SleepClockDragMode.hour:
          geometry.handTip(widget.goalMinute, geometry.hourHandLength),
      _SleepClockDragMode.minute: geometry.minuteHandTip(widget.goalMinute),
      _SleepClockDragMode.counterpart:
          geometry.timeMarker(widget.counterpartMinute),
    };
    final nearest = points.entries.reduce(
      (a, b) => (position - a.value).distance <= (position - b.value).distance
          ? a
          : b,
    );
    if ((position - nearest.value).distance > geometry.hitRadius) return;
    setState(() => _dragMode = nearest.key);
  }

  void _updateDrag(Offset position, Size size) {
    final mode = _dragMode;
    if (mode == null || widget.onTargetChanged == null) return;
    final angle = _SleepClockGeometry.angleFromTop(
      position,
      _SleepClockGeometry.fromSize(size).center,
    );
    final next = switch (mode) {
      _SleepClockDragMode.hour => _targetFromHour(angle),
      _SleepClockDragMode.minute => _targetFromMinute(angle),
      _SleepClockDragMode.counterpart => _targetFromCounterpart(angle),
    };
    widget.onTargetChanged!(next);
  }

  int _targetFromHour(double angle) {
    final dialHour = (angle / (2 * math.pi) * 12).round() % 12;
    final currentHour = (widget.goalMinute ~/ 60) % 24;
    int nextHour;
    if (widget.goalIsSleep && dialHour == 0) {
      nextHour = 0;
    } else if (widget.goalIsSleep && dialHour >= 10) {
      nextHour = dialHour + 12;
    } else if (widget.goalIsSleep && currentHour >= 18 && dialHour >= 5) {
      nextHour = dialHour + 12;
    } else {
      nextHour = dialHour;
    }
    return nextHour * 60 + widget.goalMinute % 60;
  }

  int _targetFromMinute(double angle) {
    final minute = (angle / (2 * math.pi) * 60).round() % 60;
    final current = widget.goalMinute;
    final currentHour = (current ~/ 60) * 60;
    final candidates = [
      currentHour - 60 + minute,
      currentHour + minute,
      currentHour + 60 + minute,
    ];
    final nearest = candidates.reduce(
      (a, b) => (a - current).abs() <= (b - current).abs() ? a : b,
    );
    return _normalizeMinute(nearest);
  }

  int _targetFromCounterpart(double angle) {
    final twelveHourMinute =
        (angle / (2 * math.pi) * 12 * 60).round() % (12 * 60);
    final current = widget.counterpartMinute;
    final candidates = [twelveHourMinute, twelveHourMinute + 12 * 60];
    final nextCounterpart = candidates.reduce(
      (a, b) => (a - current).abs() <= (b - current).abs() ? a : b,
    );
    return widget.goalIsSleep
        ? _normalizeMinute(nextCounterpart - 8 * 60)
        : _normalizeMinute(nextCounterpart + 8 * 60);
  }

  String _formatMinute(int minute) {
    final safe = _normalizeMinute(minute);
    return '${(safe ~/ 60).toString().padLeft(2, '0')}:${(safe % 60).toString().padLeft(2, '0')}';
  }

  int _normalizeMinute(int minute) {
    final normalized = minute % (24 * 60);
    return normalized < 0 ? normalized + 24 * 60 : normalized;
  }
}

class _SleepClockLegend extends StatelessWidget {
  final Color color;
  final String label;
  final ColorScheme colorScheme;

  const _SleepClockLegend({
    required this.color,
    required this.label,
    required this.colorScheme,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            color: colorScheme.onSurface,
          ),
        ),
      ],
    );
  }
}

class _SleepClockGeometry {
  final Offset center;
  final double radius;

  const _SleepClockGeometry(this.center, this.radius);

  double get hourHandLength => radius * 0.47;
  double get minuteHandLength => radius * 0.7;
  double get hitRadius => math.max(28, radius * 0.18);

  factory _SleepClockGeometry.fromSize(Size size) {
    return _SleepClockGeometry(
      Offset(size.width / 2, size.height / 2),
      math.min(size.width, size.height) / 2 - 14,
    );
  }

  Offset handTip(int minute, double length) {
    return _pointAt(_hourAngle(minute), length);
  }

  Offset minuteHandTip(int minute) {
    return _pointAt(_minuteAngle(minute), minuteHandLength);
  }

  Offset timeMarker(int minute) {
    return _pointAt(_timeAngle(minute), radius * 0.88);
  }

  Offset _pointAt(double angle, double length) {
    return Offset(
      center.dx + math.cos(angle) * length,
      center.dy + math.sin(angle) * length,
    );
  }

  double _hourAngle(int minute) {
    final normalized = _normalizeMinute(minute);
    final hour = (normalized ~/ 60) % 12 + (normalized % 60) / 60;
    return hour * math.pi / 6 - math.pi / 2;
  }

  double _minuteAngle(int minute) {
    return (minute % 60) * math.pi / 30 - math.pi / 2;
  }

  double _timeAngle(int minute) {
    final twelveHourMinute = _normalizeMinute(minute) % (12 * 60);
    return twelveHourMinute * math.pi / (6 * 60) - math.pi / 2;
  }

  static double angleFromTop(Offset position, Offset center) {
    var angle = math.atan2(position.dy - center.dy, position.dx - center.dx) +
        math.pi / 2;
    if (angle < 0) angle += 2 * math.pi;
    return angle;
  }

  static int _normalizeMinute(int minute) {
    final normalized = minute % (24 * 60);
    return normalized < 0 ? normalized + 24 * 60 : normalized;
  }
}

class _SleepScheduleClockPainter extends CustomPainter {
  final int goalMinute;
  final int counterpartMinute;
  final bool goalIsSleep;
  final _SleepClockDragMode? activeMode;
  final ColorScheme colorScheme;

  const _SleepScheduleClockPainter({
    required this.goalMinute,
    required this.counterpartMinute,
    required this.goalIsSleep,
    required this.activeMode,
    required this.colorScheme,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final geometry = _SleepClockGeometry.fromSize(size);
    final center = geometry.center;
    final radius = geometry.radius;
    final primary = colorScheme.primary;
    final secondary = colorScheme.tertiary;
    final face = Paint()..color = colorScheme.surfaceContainerHighest;
    final outline = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..color = colorScheme.outlineVariant;
    canvas.drawCircle(center, radius, face);
    canvas.drawCircle(center, radius, outline);

    _drawSleepArc(canvas, geometry, primary, secondary);
    _drawTicksAndLabels(canvas, geometry);
    _drawCounterpartMarker(canvas, geometry, secondary);
    _drawTargetHands(canvas, geometry, primary);
  }

  void _drawSleepArc(
    Canvas canvas,
    _SleepClockGeometry geometry,
    Color primary,
    Color secondary,
  ) {
    final startMinute = goalIsSleep ? goalMinute : counterpartMinute;
    final endMinute = goalIsSleep ? counterpartMinute : goalMinute;
    final start = _SleepClockGeometry.angleFromTop(
            geometry.timeMarker(startMinute), geometry.center) -
        math.pi / 2;
    final end = _SleepClockGeometry.angleFromTop(
            geometry.timeMarker(endMinute), geometry.center) -
        math.pi / 2;
    var sweep = end - start;
    if (sweep < 0) sweep += 2 * math.pi;
    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 7
      ..strokeCap = StrokeCap.round
      ..color = secondary.withValues(alpha: 0.35);
    final rect =
        Rect.fromCircle(center: geometry.center, radius: geometry.radius - 7);
    canvas.drawArc(rect, start, sweep, false, arc);
  }

  void _drawTicksAndLabels(Canvas canvas, _SleepClockGeometry geometry) {
    for (var index = 0; index < 60; index++) {
      final angle = index * math.pi / 30 - math.pi / 2;
      final major = index % 5 == 0;
      final outer = geometry.radius - 4;
      final inner = geometry.radius - (major ? 16 : 10);
      final tick = Paint()
        ..color =
            major ? colorScheme.onSurfaceVariant : colorScheme.outlineVariant
        ..strokeWidth = major ? 2 : 1
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(
        Offset(
          geometry.center.dx + math.cos(angle) * inner,
          geometry.center.dy + math.sin(angle) * inner,
        ),
        Offset(
          geometry.center.dx + math.cos(angle) * outer,
          geometry.center.dy + math.sin(angle) * outer,
        ),
        tick,
      );
      if (major) {
        final number = index ~/ 5 == 0 ? '12' : '${index ~/ 5}';
        final textPainter = TextPainter(
          text: TextSpan(
            text: number,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        final labelRadius = geometry.radius - 31;
        final labelCenter = Offset(
          geometry.center.dx + math.cos(angle) * labelRadius,
          geometry.center.dy + math.sin(angle) * labelRadius,
        );
        textPainter.paint(
          canvas,
          labelCenter - Offset(textPainter.width / 2, textPainter.height / 2),
        );
      }
    }
  }

  void _drawCounterpartMarker(
    Canvas canvas,
    _SleepClockGeometry geometry,
    Color color,
  ) {
    final marker = geometry.timeMarker(counterpartMinute);
    final markerPaint = Paint()..color = color;
    canvas.drawCircle(marker,
        activeMode == _SleepClockDragMode.counterpart ? 14 : 11, markerPaint);
    canvas.drawCircle(
      marker,
      4,
      Paint()..color = colorScheme.onTertiary,
    );
  }

  void _drawTargetHands(
    Canvas canvas,
    _SleepClockGeometry geometry,
    Color color,
  ) {
    final hourTip = geometry.handTip(goalMinute, geometry.hourHandLength);
    final minuteTip = geometry.minuteHandTip(goalMinute);
    _drawHand(canvas, geometry.center, hourTip, color, 6,
        activeMode == _SleepClockDragMode.hour);
    _drawHand(canvas, geometry.center, minuteTip, color, 3.5,
        activeMode == _SleepClockDragMode.minute);
    canvas.drawCircle(geometry.center, 7, Paint()..color = color);
    canvas.drawCircle(
      geometry.center,
      3,
      Paint()..color = colorScheme.onPrimary,
    );
  }

  void _drawHand(
    Canvas canvas,
    Offset center,
    Offset tip,
    Color color,
    double strokeWidth,
    bool active,
  ) {
    final hand = Paint()
      ..color = active ? color : color.withValues(alpha: 0.9)
      ..strokeWidth = active ? strokeWidth + 2 : strokeWidth
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(center, tip, hand);
  }

  @override
  bool shouldRepaint(covariant _SleepScheduleClockPainter oldDelegate) {
    return oldDelegate.goalMinute != goalMinute ||
        oldDelegate.counterpartMinute != counterpartMinute ||
        oldDelegate.goalIsSleep != goalIsSleep ||
        oldDelegate.activeMode != activeMode ||
        oldDelegate.colorScheme != colorScheme;
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
