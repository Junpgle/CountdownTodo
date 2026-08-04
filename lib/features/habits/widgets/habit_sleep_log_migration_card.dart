import 'package:flutter/material.dart';

import '../services/habit_sleep_log_migration_service.dart';

/// 旧时间日志迁移入口：放在习惯中心今日页最前面，避免用户错过历史数据的价值。
class HabitSleepLogMigrationCard extends StatelessWidget {
  final HabitSleepLogMigrationProposal proposal;
  final VoidCallback onTap;
  final VoidCallback onDismiss;

  const HabitSleepLogMigrationCard({
    super.key,
    required this.proposal,
    required this.onTap,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final missingCount = (proposal.createsEarlySleep ? 1 : 0) +
        (proposal.createsEarlyWake ? 1 : 0);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 840),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Material(
            color: colorScheme.secondaryContainer,
            borderRadius: BorderRadius.circular(20),
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(20),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: colorScheme.secondary,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(
                        Icons.bedtime_rounded,
                        color: colorScheme.onSecondary,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '把睡眠时间日志变成习惯',
                            style: TextStyle(
                              color: colorScheme.onSecondaryContainer,
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '已识别近 ${proposal.observedNights} 晚记录，建议以中位作息创建 $missingCount 个时间点习惯。',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: colorScheme.onSecondaryContainer
                                  .withValues(alpha: 0.78),
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 6,
                            children: [
                              _TimeChip(
                                icon: Icons.nightlight_round,
                                label:
                                    '早睡 ${HabitSleepLogMigrationService.formatMinute(proposal.bedtimeMinute)}',
                                colorScheme: colorScheme,
                              ),
                              _TimeChip(
                                icon: Icons.wb_twilight_rounded,
                                label:
                                    '早起 ${HabitSleepLogMigrationService.formatMinute(proposal.wakeMinute)}',
                                colorScheme: colorScheme,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 4),
                    IconButton(
                      tooltip: '稍后提醒',
                      onPressed: onDismiss,
                      icon: Icon(
                        Icons.close_rounded,
                        color: colorScheme.onSecondaryContainer,
                      ),
                    ),
                    Icon(
                      Icons.chevron_right_rounded,
                      color: colorScheme.onSecondaryContainer,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TimeChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final ColorScheme colorScheme;

  const _TimeChip({
    required this.icon,
    required this.label,
    required this.colorScheme,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: colorScheme.surface.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: colorScheme.onSecondaryContainer),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: colorScheme.onSecondaryContainer,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
