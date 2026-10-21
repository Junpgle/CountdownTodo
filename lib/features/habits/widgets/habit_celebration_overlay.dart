import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../widgets/celebration/liquid_glass_celebration_dialog.dart';
import '../models/habit_goal.dart';
import '../services/habit_celebration_service.dart';

const _inspirationalQuotes = <String>[
  '滴水穿石，每一天微小的坚持都在发生质变 ✨',
  '自律是送给未来自己最好的礼物 🌟',
  '干得漂亮！离理想中的自己又近了一步 💫',
  '日拱一卒，功不唐捐，今天的你非常棒 🌱',
  '点滴积累，终成江海。享受每一次坚持的成就感 🚀',
];

/// 习惯达成全屏庆祝弹层。
class HabitGoalMetOverlay extends StatefulWidget {
  final HabitGoal goal;
  final int streakDays;
  final VoidCallback? onDismiss;

  const HabitGoalMetOverlay({
    super.key,
    required this.goal,
    this.streakDays = 0,
    this.onDismiss,
  });

  @override
  State<HabitGoalMetOverlay> createState() => _HabitGoalMetOverlayState();
}

class _HabitGoalMetOverlayState extends State<HabitGoalMetOverlay> {
  late final String _quote;

  @override
  void initState() {
    super.initState();
    _quote = _inspirationalQuotes[math.Random().nextInt(_inspirationalQuotes.length)];
    HabitCelebrationService.playGoalMetImpact();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return LiquidGlassCelebrationDialog(
      onDismiss: widget.onDismiss,
      autoDismiss: true,
      headerBadge: LiquidGlassCelebrationDialog.buildGradientBadge(
        child: Text(
          widget.goal.icon.isNotEmpty ? widget.goal.icon : '🎯',
          style: const TextStyle(fontSize: 38),
        ),
        size: 72,
      ),
      titleWidget: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.verified_rounded,
            color: Color(0xFFFFB300),
            size: 20,
          ),
          const SizedBox(width: 6),
          Text(
            '今日习惯达成！',
            style: TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w800,
              color: colorScheme.onSurface,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 6),
          Text(
            '「${widget.goal.name}」',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: colorScheme.primary,
            ),
          ),
          if (widget.streakDays > 0) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 4,
              ),
              decoration: BoxDecoration(
                color: const Color(0xFFFF9100).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '🔥 已连续坚持 ${widget.streakDays} 天',
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFFFF6D00),
                ),
              ),
            ),
          ],
        ],
      ),
      description: _quote,
      actionLabel: '收到 ✨',
    );
  }
}

/// 弹出习惯达成庆祝弹窗。
Future<void> showHabitGoalMetCelebration(
  BuildContext context, {
  required HabitGoal goal,
  int streakDays = 0,
}) async {
  await HabitCelebrationService.ensureInitialized();
  if (!HabitCelebrationService.isCelebrationEnabled) return;

  if (!context.mounted) return;

  await LiquidGlassCelebrationDialog.show(
    context: context,
    builder: (dialogCtx) => HabitGoalMetOverlay(
      goal: goal,
      streakDays: streakDays,
      onDismiss: () {
        if (dialogCtx.mounted) {
          Navigator.of(dialogCtx).pop();
        }
      },
    ),
  );
}
