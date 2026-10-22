import 'package:flutter/material.dart';

import '../../../utils/app_dialogs.dart';
import '../services/habit_celebration_service.dart';
import 'habit_checkin_button.dart';

/// 习惯打卡仪式感与偏好设置对话框。
class HabitCelebrationSettingsDialog extends StatefulWidget {
  const HabitCelebrationSettingsDialog({super.key});

  /// 打开打卡设置对话框。
  static Future<void> show(BuildContext context) async {
    await HabitCelebrationService.ensureInitialized();
    if (!context.mounted) return;
    await showAppDialog<void>(
      context: context,
      builder: (_) => const HabitCelebrationSettingsDialog(),
    );
  }

  @override
  State<HabitCelebrationSettingsDialog> createState() =>
      _HabitCelebrationSettingsDialogState();
}

class _HabitCelebrationSettingsDialogState
    extends State<HabitCelebrationSettingsDialog> {
  late bool _holdToCheckin;
  late bool _hapticsEnabled;
  late bool _celebrationEnabled;
  int _testCount = 0;

  @override
  void initState() {
    super.initState();
    _holdToCheckin = HabitCelebrationService.isHoldToCheckinEnabled;
    _hapticsEnabled = HabitCelebrationService.isHapticsEnabled;
    _celebrationEnabled = HabitCelebrationService.isCelebrationEnabled;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.auto_awesome_rounded, color: Color(0xFFFFB300)),
          SizedBox(width: 8),
          Text('打卡仪式感设置'),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('长按蓄力打卡'),
              subtitle: const Text('按住约 0.6 秒才打卡；轻触会取消蓄力。关闭时轻触即发。'),
              value: _holdToCheckin,
              onChanged: (val) async {
                setState(() => _holdToCheckin = val);
                await HabitCelebrationService.setHoldToCheckinEnabled(val);
              },
            ),
            const Divider(height: 16),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('打卡触觉反馈'),
              subtitle: const Text('在蓄力和打卡达成瞬间提供细腻的震动反馈。'),
              value: _hapticsEnabled,
              onChanged: (val) async {
                setState(() => _hapticsEnabled = val);
                await HabitCelebrationService.setHapticsEnabled(val);
              },
            ),
            const Divider(height: 16),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('目标达成庆祝动效'),
              subtitle: const Text('习惯今日达标或打破连胜时弹出专属勋章与微粒子庆祝。'),
              value: _celebrationEnabled,
              onChanged: (val) async {
                setState(() => _celebrationEnabled = val);
                await HabitCelebrationService.setCelebrationEnabled(val);
              },
            ),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest.withValues(
                  alpha: 0.6,
                ),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: colorScheme.outlineVariant.withValues(alpha: 0.4),
                ),
              ),
              child: Column(
                children: [
                  Text(
                    '手感与动效试玩',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 12),
                  HabitCelebrationTrigger(
                    enableHoldToCheckin: _holdToCheckin,
                    burstColor: const Color(0xFFFFB300),
                    holdHint: '请长按蓄力盖章打卡',
                    semanticLabel: '打卡手感与动效试玩',
                    onCheckIn: () async {
                      setState(() => _testCount++);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _holdToCheckin
                                ? Icons.touch_app_rounded
                                : Icons.check_circle_rounded,
                            size: 18,
                            color: colorScheme.onPrimaryContainer,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _holdToCheckin ? '长按蓄力体验' : '点击打卡体验',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: colorScheme.onPrimaryContainer,
                            ),
                          ),
                          if (_testCount > 0) ...[
                            const SizedBox(width: 6),
                            Text(
                              '· 已试玩 $_testCount 次',
                              style: TextStyle(
                                fontSize: 11,
                                color: colorScheme.onPrimaryContainer
                                    .withValues(alpha: 0.8),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('完成'),
        ),
      ],
    );
  }
}
