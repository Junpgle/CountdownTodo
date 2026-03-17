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
  });

  @override
  Widget build(BuildContext context) {
    if (isRemoteWatching) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.info_outline, size: 18,
                color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.6)),
            const SizedBox(width: 6),
            Text(
              '请在专注发起端进行操作',
              style: TextStyle(
                fontSize: 13,
                color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
              ),
            ),
          ],
        ),
      );
    }

    if (isIdle) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: onShowBindTodo,
                icon: Icon(
                  boundTodo != null ? Icons.task_alt : Icons.add_task,
                  size: 20,
                  color: boundTodo != null
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                label: Text(
                  boundTodo?.title ?? '绑定任务',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: boundTodo != null ? FontWeight.w600 : FontWeight.normal,
                    color: boundTodo != null
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                  side: BorderSide(
                    color: boundTodo != null
                        ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.6)
                        : Theme.of(context).colorScheme.outlineVariant,
                  ),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton.icon(
                key: const ValueKey('start_btn'),
                onPressed: onStartFocus,
                icon: const Icon(Icons.play_arrow_rounded, size: 24),
                label: Text(
                  phase == PomodoroPhase.finished ? '再来一轮' : '开始专注',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
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
                  icon: const Icon(Icons.check_circle_outline, size: 20),
                  label: const Text('提前完成', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    backgroundColor: const Color(0xFF4CAF50),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onAbandonFocus,
                  icon: const Icon(Icons.stop_circle_outlined, size: 20),
                  label: const Text('放弃专注', style: TextStyle(fontSize: 15)),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
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
      padding: const EdgeInsets.only(bottom: 8),
      child: OutlinedButton.icon(
        key: const ValueKey('skip_break_btn'),
        onPressed: onSkipBreak,
        icon: const Icon(Icons.skip_next_rounded),
        label: const Text('跳过休息', style: TextStyle(fontSize: 16)),
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(double.infinity, 52),
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
      ),
    );
  }
}
