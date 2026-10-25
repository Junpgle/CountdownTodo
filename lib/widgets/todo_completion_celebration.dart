import 'package:flutter/material.dart';

import '../services/todo_completion_celebration_service.dart';
import 'celebration/liquid_glass_celebration_dialog.dart';

/// 今日待办全部达成庆祝弹层。
class TodoCelebrationOverlay extends StatelessWidget {
  final int completedTodayCount;
  final VoidCallback? onDismiss;

  const TodoCelebrationOverlay({
    super.key,
    required this.completedTodayCount,
    this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    return LiquidGlassCelebrationDialog(
      onDismiss: onDismiss,
      autoDismiss: true,
      headerBadge: LiquidGlassCelebrationDialog.buildGradientBadge(
        icon: Icons.celebration_rounded,
        iconColor: const Color(0xFFFFB300),
        size: 72,
        iconSize: 44,
      ),
      title: '今日待办全部达成！',
      description: completedTodayCount > 0
          ? '今日已完成 $completedTodayCount 项任务\n今日事今日毕，尽情享受闲暇时光 ✨'
          : '今日任务已全部清空，放松一下吧 ✨',
      actionLabel: '太棒了',
      actionKey: const ValueKey('celebration_dismiss_btn'),
    );
  }
}

/// 弹出今日待办全部达成庆祝弹窗。
Future<void> showTodoAllDoneCelebration(
  BuildContext context, {
  required int completedTodayCount,
}) async {
  await TodoCompletionCelebrationService.ensureInitialized();
  if (!TodoCompletionCelebrationService.isCelebrationEnabled) return;

  if (!context.mounted) return;

  await LiquidGlassCelebrationDialog.show(
    context: context,
    builder: (dialogCtx) => TodoCelebrationOverlay(
      completedTodayCount: completedTodayCount,
      onDismiss: () {
        if (dialogCtx.mounted) {
          Navigator.of(dialogCtx).pop();
        }
      },
    ),
  );
}
