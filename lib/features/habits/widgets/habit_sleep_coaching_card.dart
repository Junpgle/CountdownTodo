import 'package:flutter/material.dart';

import '../../../utils/app_dialogs.dart';
import '../../../widgets/floating_glass_control.dart';
import '../models/habit_sleep_coaching_plan.dart';
import '../services/habit_adaptation_service.dart';
import '../services/habit_sleep_coaching_service.dart';

/// 早睡、早起、睡眠时长详情页共用的可选训练入口。
class HabitSleepCoachingCard extends StatelessWidget {
  final HabitAdaptationKind kind;
  final HabitSleepCoachingSnapshot? snapshot;
  final VoidCallback onEnable;
  final ValueChanged<bool> onPauseChanged;
  final ValueChanged<bool> onEnabledChanged;
  final Future<void> Function(int stepMinutes, int stageDays)?
      onSettingsChanged;

  const HabitSleepCoachingCard({
    super.key,
    required this.kind,
    required this.snapshot,
    required this.onEnable,
    required this.onPauseChanged,
    required this.onEnabledChanged,
    this.onSettingsChanged,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final plan = snapshot?.plan;
    final metric = snapshot?.metricFor(kind);
    final isEnabled = plan?.enabled == true;
    final isPaused = plan?.paused == true;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer.withValues(alpha: 0.58),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorScheme.primary.withValues(alpha: 0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.route_rounded, color: colorScheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '渐进作息训练',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: colorScheme.onPrimaryContainer,
                  ),
                ),
              ),
              if (plan == null)
                TextButton(onPressed: onEnable, child: const Text('开启'))
              else
                LiquidGlassSwitch(
                  value: isEnabled && !isPaused,
                  onChanged: (value) {
                    if (value) {
                      if (isPaused) {
                        onPauseChanged(false);
                      } else {
                        onEnable();
                      }
                    } else {
                      onEnabledChanged(false);
                    }
                  },
                ),
            ],
          ),
          Text(
            '根据你最近的睡眠打卡，每次只调整 ${plan?.stepMinutes ?? 15} 分钟，稳定 ${plan?.stageDays ?? 4} 天后再进入下一步。',
            style: TextStyle(
              fontSize: 12,
              height: 1.45,
              color: colorScheme.onPrimaryContainer.withValues(alpha: 0.86),
            ),
          ),
          if (plan == null) ...[
            const SizedBox(height: 8),
            Text(
              '这是可选功能，不会自动修改原有习惯目标；训练计划会在多端同步。',
              style: TextStyle(
                fontSize: 11.5,
                color: colorScheme.onPrimaryContainer.withValues(alpha: 0.72),
              ),
            ),
          ] else if (isEnabled) ...[
            const SizedBox(height: 12),
            _buildActiveBody(context, metric),
            const SizedBox(height: 8),
            Row(
              children: [
                TextButton.icon(
                  onPressed: () => onPauseChanged(!isPaused),
                  icon: Icon(isPaused
                      ? Icons.play_arrow_rounded
                      : Icons.pause_rounded),
                  label: Text(isPaused ? '继续训练' : '暂停训练'),
                ),
                const Spacer(),
                if (onSettingsChanged != null)
                  TextButton(
                    onPressed: () => _showSettings(context, plan),
                    child: const Text('调整节奏'),
                  ),
              ],
            ),
          ] else ...[
            const SizedBox(height: 8),
            Text(
              '训练已关闭，原有睡眠打卡不受影响。',
              style: TextStyle(
                fontSize: 12,
                color: colorScheme.onPrimaryContainer.withValues(alpha: 0.75),
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(onPressed: onEnable, child: const Text('重新开启')),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildActiveBody(
    BuildContext context,
    HabitSleepCoachingMetric? metric,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    final current = metric?.currentValue;
    final stageTarget = metric?.stageTarget;
    final finalTarget = metric?.targetValue;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              '第 ${(snapshot?.stageIndex ?? 0) + 1} 阶段',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: colorScheme.onPrimaryContainer,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '已稳定 ${snapshot?.stageProgressDays ?? 0}/${snapshot?.plan.stageDays ?? 4} 天',
              style: TextStyle(
                fontSize: 11.5,
                color: colorScheme.onPrimaryContainer.withValues(alpha: 0.72),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            _valueChip(context, '本期建议', _formatValue(stageTarget)),
            _valueChip(context, '最终目标', _formatValue(finalTarget)),
            if (current != null)
              _valueChip(context, '最近打卡', _formatValue(current)),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          metric == null
              ? '当前详情还没有可用的睡眠目标，先完成一次打卡即可计算训练建议。'
              : '完成本期建议后，系统会自动把下一设备看到的训练阶段保持一致。',
          style: TextStyle(
            fontSize: 11.5,
            height: 1.4,
            color: colorScheme.onPrimaryContainer.withValues(alpha: 0.75),
          ),
        ),
      ],
    );
  }

  Widget _valueChip(BuildContext context, String label, String value) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: colorScheme.surface.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        '$label $value',
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          color: colorScheme.onSurface,
        ),
      ),
    );
  }

  String _formatValue(int? value) {
    if (value == null) return '待记录';
    if (kind == HabitAdaptationKind.sleepDuration) {
      final hours = value ~/ 60;
      final minutes = value % 60;
      return minutes == 0 ? '$hours 小时' : '$hours 小时 $minutes 分';
    }
    final minute = value % (24 * 60);
    return '${(minute ~/ 60).toString().padLeft(2, '0')}:${(minute % 60).toString().padLeft(2, '0')}';
  }

  Future<void> _showSettings(
    BuildContext context,
    HabitSleepCoachingPlan plan,
  ) async {
    var step = plan.stepMinutes;
    var days = plan.stageDays;
    final result = await showAppModalBottomSheet<(int, int)>(
      context: context,
      showDragHandle: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            0,
            20,
            MediaQuery.paddingOf(context).bottom + 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('训练节奏',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              const Text('节奏越慢越容易坚持；阶段天数用于判断是否稳定。'),
              const SizedBox(height: 14),
              DropdownButtonFormField<int>(
                initialValue: step,
                decoration: const InputDecoration(labelText: '每次调整'),
                items: const [5, 10, 15, 20, 30]
                    .map((value) => DropdownMenuItem(
                        value: value, child: Text('$value 分钟')))
                    .toList(),
                onChanged: (value) => setModalState(() => step = value ?? step),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                initialValue: days,
                decoration: const InputDecoration(labelText: '每阶段稳定天数'),
                items: const [2, 3, 4, 5, 7]
                    .map((value) =>
                        DropdownMenuItem(value: value, child: Text('$value 天')))
                    .toList(),
                onChanged: (value) => setModalState(() => days = value ?? days),
              ),
              const SizedBox(height: 14),
              FilledButton(
                onPressed: () => Navigator.of(context).pop((step, days)),
                child: const Text('保存'),
              ),
            ],
          ),
        ),
      ),
    );
    if (result != null) await onSettingsChanged?.call(result.$1, result.$2);
  }
}
