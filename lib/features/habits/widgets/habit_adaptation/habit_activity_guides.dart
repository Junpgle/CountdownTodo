part of '../habit_adaptation_panel.dart';

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
    final isDurationUnit =
        normalizedUnit.isEmpty ||
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
    final weeklyLabel = weeklyMinutes == null
        ? '切换为分钟后计算'
        : '$weeklyMinutes 分钟/周';

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
              Icon(
                Icons.directions_run_rounded,
                size: 19,
                color: colorScheme.primary,
              ),
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
    final targetLabel = periodType == HabitPeriodType.weekly
        ? '$target 分钟/周'
        : '$target 分钟/天';

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
              Icon(
                Icons.menu_book_rounded,
                size: 19,
                color: colorScheme.primary,
              ),
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
    ('读得越久、页数越多越好吗？', '不一定。阅读还包括理解和回忆；如果注意力已经明显下降，可以先停下来休息或拆成两个阅读块。'),
    ('只读不做笔记可以吗？', '可以。笔记不是必需品，但读完后用自己的话回忆一句或说出 3 个要点，通常比被动重读更能检验理解。'),
    ('纸书和电子书应该选哪个？', '优先选择更容易持续、眼睛和姿势更舒服的载体。屏幕阅读时注意远眺、眨眼和亮度，出现持续不适就减少屏幕时长。'),
    ('今天读不下去怎么办？', '把目标降到 10–15 分钟，换成更容易进入状态的章节，或者只完成“读一小节并复述一句”；先保留节奏，再逐步增加。'),
  ];

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
          initiallyExpanded: false,
          tilePadding: EdgeInsets.zero,
          childrenPadding: const EdgeInsets.only(bottom: 2),
          leading: Icon(
            Icons.help_outline_rounded,
            size: 19,
            color: colorScheme.primary,
          ),
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
                  child: _HabitGuideMetric.fromData(metrics[i], colorScheme),
                ),
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
