import 'package:flutter/material.dart';

import '../../../utils/app_dialogs.dart';
import '../../../utils/page_transitions.dart';
import '../../../widgets/floating_glass_control.dart';
import '../../../widgets/optional_liquid_glass_surface.dart';
import '../services/habit_celebration_service.dart';
import '../services/habit_freeze_service.dart';
import 'habit_checkin_button.dart';

/// 习惯中心设置对话框/页面（收录免扣卡自动守护与打卡仪式感设置）。
class HabitCelebrationSettingsDialog extends StatefulWidget {
  final bool initialAutoProtectEnabled;
  final VoidCallback? onOpenSleepLogMigration;
  final bool asPage;

  const HabitCelebrationSettingsDialog({
    super.key,
    this.initialAutoProtectEnabled = true,
    this.onOpenSleepLogMigration,
    this.asPage = false,
  });

  /// 打开习惯中心设置。传入 [sourceKey] 时以容器共享动画展开为独立页面。
  static Future<void> show(
    BuildContext context, {
    GlobalKey? sourceKey,
    VoidCallback? onOpenSleepLogMigration,
  }) async {
    final results = await Future.wait<dynamic>([
      HabitCelebrationService.ensureInitialized(),
      HabitFreezeService.isAutoProtectEnabled(),
    ]);
    final autoProtectEnabled = results[1] as bool;
    if (!context.mounted) return;
    if (sourceKey != null) {
      await PageTransitions.pushFromRect<void>(
        context: context,
        page: HabitCelebrationSettingsDialog(
          initialAutoProtectEnabled: autoProtectEnabled,
          onOpenSleepLogMigration: onOpenSleepLogMigration,
          asPage: true,
        ),
        sourceKey: sourceKey,
        sourceBorderRadius: BorderRadius.circular(20),
        placeholderIcon: Icons.settings_outlined,
      );
      return;
    }
    await showAppDialog<void>(
      context: context,
      builder: (_) => HabitCelebrationSettingsDialog(
        initialAutoProtectEnabled: autoProtectEnabled,
        onOpenSleepLogMigration: onOpenSleepLogMigration,
      ),
    );
  }

  @override
  State<HabitCelebrationSettingsDialog> createState() =>
      _HabitCelebrationSettingsDialogState();
}

class _HabitCelebrationSettingsDialogState
    extends State<HabitCelebrationSettingsDialog> {
  late bool _autoProtectEnabled;
  late bool _holdToCheckin;
  late bool _hapticsEnabled;
  late bool _celebrationEnabled;
  int _testCount = 0;

  @override
  void initState() {
    super.initState();
    _autoProtectEnabled = widget.initialAutoProtectEnabled;
    _holdToCheckin = HabitCelebrationService.isHoldToCheckinEnabled;
    _hapticsEnabled = HabitCelebrationService.isHapticsEnabled;
    _celebrationEnabled = HabitCelebrationService.isCelebrationEnabled;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final content = _buildSettingsContent(colorScheme);

    if (widget.asPage) {
      return Scaffold(
        extendBodyBehindAppBar: true,
        appBar: FloatingGlassAppBar(
          flexibleSpace: const FloatingGlassTopBarBackground(),
          title: const Text('习惯中心设置'),
        ),
        body: floatingGlassSettingsBody(
          context,
          standalone: true,
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              16,
              floatingGlassSettingsContentTopInset(context),
              16,
              24,
            ),
            child: OptionalLiquidGlassCard(
              borderRadius: 16,
              highContrast: true,
              fallbackDecoration: BoxDecoration(
                color: colorScheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Padding(padding: const EdgeInsets.all(16), child: content),
            ),
          ),
        ),
      );
    }

    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.settings_rounded, color: colorScheme.primary),
          const SizedBox(width: 8),
          const Text('习惯中心设置'),
        ],
      ),
      content: SingleChildScrollView(child: content),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('完成'),
        ),
      ],
    );
  }

  Widget _buildSettingsContent(ColorScheme colorScheme) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.shield_outlined, size: 18, color: colorScheme.primary),
            const SizedBox(width: 6),
            Text(
              '免扣卡守护',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: colorScheme.primary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('自动使用免扣卡'),
          subtitle: const Text('昨日漏打卡且有可用免扣卡时，次日自动使用免扣卡守住连续记录；关闭后仅可手动补用。'),
          value: _autoProtectEnabled,
          onChanged: (val) async {
            setState(() => _autoProtectEnabled = val);
            await HabitFreezeService.setAutoProtectEnabled(val);
          },
        ),
        if (widget.onOpenSleepLogMigration != null) ...[
          const Divider(height: 24),
          Row(
            children: [
              Icon(
                Icons.bedtime_outlined,
                size: 18,
                color: colorScheme.primary,
              ),
              const SizedBox(width: 6),
              Text(
                '数据迁移',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: colorScheme.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('从时间日志迁移睡眠'),
            subtitle: const Text('根据近期睡眠记录生成早睡和早起习惯建议。'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () {
              Navigator.of(context).pop();
              widget.onOpenSleepLogMigration?.call();
            },
          ),
        ],
        const Divider(height: 24),
        const Row(
          children: [
            Icon(
              Icons.auto_awesome_rounded,
              size: 18,
              color: Color(0xFFFFB300),
            ),
            SizedBox(width: 6),
            Text(
              '打卡仪式感设置',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: Color(0xFFFFB300),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
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
            color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
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
                            color: colorScheme.onPrimaryContainer.withValues(
                              alpha: 0.8,
                            ),
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
    );
  }
}
