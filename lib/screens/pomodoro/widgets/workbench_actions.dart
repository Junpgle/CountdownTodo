import 'package:flutter/material.dart';
import '../../../models.dart';
import '../../../services/pomodoro_service.dart';

class WorkbenchActions extends StatelessWidget {
  final bool isIdle;
  final bool isFocusing;
  final bool isRemoteWatching;
  final PomodoroPhase phase;
  final TodoItem? boundTodo;
  final VoidCallback onShowBindTodo;
  final VoidCallback onStartFocus;
  final VoidCallback onFinishEarly;
  final VoidCallback onAbandonFocus;
  final VoidCallback onSkipBreak;

  // New: compact rendering flag
  final bool isCompact;

  // New: whether to show the mode toggle (caller can hide it in landscape active state)
  final bool showModeToggle;

  const WorkbenchActions({
    super.key,
    required this.isIdle,
    required this.isFocusing,
    required this.isRemoteWatching,
    required this.phase,
    this.boundTodo,
    required this.onShowBindTodo,
    required this.onStartFocus,
    required this.onFinishEarly,
    required this.onAbandonFocus,
    required this.onSkipBreak,
    this.isCompact = false,
    this.showModeToggle = true,
  });

  @override
  Widget build(BuildContext context) {
    if (isRemoteWatching) {
      final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;
      return Padding(
        padding: EdgeInsets.only(bottom: isLandscape ? 0 : (isCompact ? 6 : 8)),
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: isCompact ? 12 : 16, vertical: isCompact ? 10 : 12),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.5)),
          ),
          child: Row(
            mainAxisAlignment: isLandscape ? MainAxisAlignment.start : MainAxisAlignment.center,
            mainAxisSize: isLandscape ? MainAxisSize.max : MainAxisSize.min,
            children: [
              Icon(Icons.devices_outlined, size: isCompact ? 16 : 18,
                  color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.7)),
              SizedBox(width: isCompact ? 8 : 10),
              Flexible(
                child: Text(
                  '同步模式：请在发起端进行操作',
                  style: TextStyle(
                    fontSize: isCompact ? 12 : 13,
                    fontWeight: FontWeight.w500,
                    color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.8),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (isIdle) {
      return Padding(
        padding: EdgeInsets.only(bottom: isCompact ? 6 : 8),
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: onShowBindTodo,
                icon: Icon(
                  boundTodo != null ? Icons.task_alt : Icons.add_task,
                  size: isCompact ? 18 : 20,
                  color: boundTodo != null
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                label: Text(
                  boundTodo?.title ?? '绑定任务',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: isCompact ? 13 : 14,
                    fontWeight: boundTodo != null ? FontWeight.w600 : FontWeight.normal,
                    color: boundTodo != null
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  padding: EdgeInsets.symmetric(horizontal: isCompact ? 10 : 12, vertical: isCompact ? 10 : 14),
                  side: BorderSide(
                    color: boundTodo != null
                        ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.6)
                        : Theme.of(context).colorScheme.outlineVariant,
                  ),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
              ),
            ),
            SizedBox(width: isCompact ? 8 : 12),
            Expanded(
              child: FilledButton.icon(
                key: const ValueKey('start_btn'),
                onPressed: onStartFocus,
                icon: Icon(Icons.play_arrow_rounded, size: isCompact ? 20 : 24),
                label: Text(
                  phase == PomodoroPhase.finished ? '再来一轮' : '开始专注',
                  style: TextStyle(fontSize: isCompact ? 14 : 16, fontWeight: FontWeight.bold),
                ),
                style: FilledButton.styleFrom(
                  padding: EdgeInsets.symmetric(vertical: isCompact ? 12 : 14),
                  backgroundColor: const Color(0xFFFF6B6B),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  elevation: 2,
                ),
              ),
            ),
          ],
        ),
      );
    }

    if (isFocusing) {
      return Column(
        key: const ValueKey('focus_btns'),
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: onFinishEarly,
                  icon: Icon(Icons.check_circle_outline, size: isCompact ? 18 : 20),
                  label: Text('提前完成', style: TextStyle(fontSize: isCompact ? 14 : 15, fontWeight: FontWeight.bold)),
                  style: FilledButton.styleFrom(
                    padding: EdgeInsets.symmetric(vertical: isCompact ? 12 : 14),
                    backgroundColor: const Color(0xFF4CAF50),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                ),
              ),
              SizedBox(width: isCompact ? 8 : 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onAbandonFocus,
                  icon: Icon(Icons.stop_circle_outlined, size: isCompact ? 18 : 20),
                  label: Text('放弃专注', style: TextStyle(fontSize: isCompact ? 14 : 15)),
                  style: OutlinedButton.styleFrom(
                    padding: EdgeInsets.symmetric(vertical: isCompact ? 12 : 14),
                    foregroundColor: Theme.of(context).colorScheme.onSurfaceVariant,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                ),
              ),
            ],
          ),
        ],
      );
    }

    return Padding(
      padding: EdgeInsets.only(bottom: isCompact ? 6 : 8),
      child: OutlinedButton.icon(
        key: const ValueKey('skip_break_btn'),
        onPressed: onSkipBreak,
        icon: Icon(Icons.skip_next_rounded, size: isCompact ? 18 : 24),
        label: Text('跳过休息', style: TextStyle(fontSize: isCompact ? 14 : 16)),
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(double.infinity, 52),
          padding: EdgeInsets.symmetric(vertical: isCompact ? 12 : 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
      ),
    );
  }
}
