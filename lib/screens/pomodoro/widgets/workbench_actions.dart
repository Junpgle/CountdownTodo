import 'package:flutter/material.dart';
import '../../../models.dart';
import '../../../services/pomodoro_service.dart';

/// The workbench buttons own their fill treatment, so do not inherit the
/// app-wide glass background builder as a second surface.
Widget _keepButtonBackground(
    BuildContext context, Set<WidgetState> states, Widget? child) {
  return child ?? const SizedBox.shrink();
}

class WorkbenchActions extends StatefulWidget {
  final bool isIdle;
  final bool isFocusing;
  final bool isRemoteWatching;
  final bool isStrictWaitingForFlip;
  final bool isStrictMode;
  final PomodoroPhase phase;
  final TodoItem? boundTodo;
  final VoidCallback onShowBindTodo;
  final VoidCallback onStartFocus;
  final VoidCallback? onCancelStrictWaiting;
  final VoidCallback onFinishEarly;
  final VoidCallback onAbandonFocus;
  final VoidCallback? onPauseFocus;
  final VoidCallback? onShowPauseDialog;
  final VoidCallback onSkipBreak;

  final bool isCompact;
  final bool showModeToggle;
  final Key? bindKey;

  const WorkbenchActions({
    super.key,
    required this.isIdle,
    required this.isFocusing,
    required this.isRemoteWatching,
    this.isStrictWaitingForFlip = false,
    this.isStrictMode = false,
    required this.phase,
    this.boundTodo,
    required this.onShowBindTodo,
    required this.onStartFocus,
    this.onCancelStrictWaiting,
    required this.onFinishEarly,
    required this.onAbandonFocus,
    this.onPauseFocus,
    this.onShowPauseDialog,
    required this.onSkipBreak,
    this.isCompact = false,
    this.showModeToggle = true,
    this.bindKey,
  });

  @override
  State<WorkbenchActions> createState() => _WorkbenchActionsState();
}

class _WorkbenchActionsState extends State<WorkbenchActions>
    with SingleTickerProviderStateMixin {
  late AnimationController _pressController;
  late Animation<double> _pressAnimation;

  @override
  void initState() {
    super.initState();
    _pressController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
      reverseDuration: const Duration(milliseconds: 300),
    );
    _pressAnimation = Tween<double>(begin: 1.0, end: 0.92).animate(
      CurvedAnimation(
        parent: _pressController,
        curve: Curves.easeInOut,
      ),
    );
  }

  @override
  void dispose() {
    _pressController.dispose();
    super.dispose();
  }

  void _onStartFocusPressed() {
    _pressController.forward().then((_) {
      _pressController.reverse();
    });
    widget.onStartFocus();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isRemoteWatching) {
      final isLandscape =
          MediaQuery.of(context).orientation == Orientation.landscape;
      return Padding(
        padding: EdgeInsets.only(
            bottom: isLandscape ? 0 : (widget.isCompact ? 6 : 8)),
        child: Container(
          padding: EdgeInsets.symmetric(
              horizontal: widget.isCompact ? 12 : 16,
              vertical: widget.isCompact ? 10 : 12),
          decoration: BoxDecoration(
            color: Theme.of(context)
                .colorScheme
                .surfaceContainerHighest
                .withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
                color: Theme.of(context)
                    .colorScheme
                    .outlineVariant
                    .withValues(alpha: 0.5)),
          ),
          child: Row(
            mainAxisAlignment: isLandscape
                ? MainAxisAlignment.start
                : MainAxisAlignment.center,
            mainAxisSize: isLandscape ? MainAxisSize.max : MainAxisSize.min,
            children: [
              Icon(Icons.devices_outlined,
                  size: widget.isCompact ? 16 : 18,
                  color: Theme.of(context)
                      .colorScheme
                      .primary
                      .withValues(alpha: 0.7)),
              SizedBox(width: widget.isCompact ? 8 : 10),
              Flexible(
                child: Text(
                  '同步模式：请在发起端进行操作',
                  style: TextStyle(
                    fontSize: widget.isCompact ? 12 : 13,
                    fontWeight: FontWeight.w500,
                    color: Theme.of(context)
                        .colorScheme
                        .onSurfaceVariant
                        .withValues(alpha: 0.8),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (widget.isStrictWaitingForFlip) {
      return Padding(
        padding: EdgeInsets.only(bottom: widget.isCompact ? 6 : 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.screen_lock_portrait_outlined,
                  size: widget.isCompact ? 18 : 20,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  '请将手机屏幕朝下翻转',
                  style: TextStyle(
                    fontSize: widget.isCompact ? 13 : 14,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: widget.onCancelStrictWaiting,
              icon: const Icon(Icons.close_rounded),
              label: const Text('取消等待'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(double.infinity, 48),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
          ],
        ),
      );
    }

    if (widget.isIdle) {
      final actionButtonHeight = widget.isCompact ? 40.0 : 48.0;
      return Padding(
        padding: EdgeInsets.only(bottom: widget.isCompact ? 6 : 8),
        child: Row(
          children: [
            Expanded(
              child: SizedBox(
                height: actionButtonHeight,
                child: OutlinedButton.icon(
                  key: widget.bindKey,
                  onPressed: widget.onShowBindTodo,
                  icon: Icon(
                    widget.boundTodo != null ? Icons.task_alt : Icons.add_task,
                    size: widget.isCompact ? 18 : 20,
                    color: widget.boundTodo != null
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  label: Text(
                    widget.boundTodo?.title ?? '绑定任务',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: widget.isCompact ? 13 : 14,
                      fontWeight: widget.boundTodo != null
                          ? FontWeight.w600
                          : FontWeight.normal,
                      color: widget.boundTodo != null
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    padding: EdgeInsets.symmetric(
                        horizontal: widget.isCompact ? 10 : 12,
                        vertical: widget.isCompact ? 10 : 14),
                    side: BorderSide(
                      color: widget.boundTodo != null
                          ? Theme.of(context)
                              .colorScheme
                              .primary
                              .withValues(alpha: 0.6)
                          : Theme.of(context).colorScheme.outlineVariant,
                    ),
                    backgroundBuilder: _keepButtonBackground,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                  ),
                ),
              ),
            ),
            SizedBox(width: widget.isCompact ? 8 : 12),
            Expanded(
              child: SizedBox(
                height: actionButtonHeight,
                child: AnimatedBuilder(
                  animation: _pressAnimation,
                  builder: (context, child) {
                    return Transform.scale(
                      scale: _pressAnimation.value,
                      child: TweenAnimationBuilder<Color?>(
                        tween: ColorTween(
                          begin: const Color(0xFFFF6B6B),
                          end: widget.phase == PomodoroPhase.finished
                              ? const Color(0xFF4ECDC4)
                              : const Color(0xFFFF6B6B),
                        ),
                        duration: const Duration(milliseconds: 400),
                        builder: (context, color, child) {
                          return FilledButton.icon(
                            key: const ValueKey('start_btn'),
                            onPressed: _onStartFocusPressed,
                            icon: Icon(Icons.play_arrow_rounded,
                                size: widget.isCompact ? 18 : 20),
                            label: Text(
                              widget.phase == PomodoroPhase.finished
                                  ? '再来一轮'
                                  : '开始专注',
                              style: TextStyle(
                                  fontSize: widget.isCompact ? 13 : 14,
                                  fontWeight: FontWeight.bold),
                            ),
                            style: FilledButton.styleFrom(
                              alignment: Alignment.center,
                              iconAlignment: IconAlignment.start,
                              padding: EdgeInsets.symmetric(
                                  vertical: widget.isCompact ? 8 : 10),
                              backgroundColor: color ?? const Color(0xFFFF6B6B),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16)),
                              backgroundBuilder: _keepButtonBackground,
                              elevation: 2,
                            ),
                          );
                        },
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      );
    }

    if (widget.isFocusing) {
      final isLandscape =
          MediaQuery.of(context).orientation == Orientation.landscape;
      return Padding(
        key: const ValueKey('focus_btns'),
        padding: EdgeInsets.only(top: widget.isCompact ? 8 : 12),
        child: Wrap(
          alignment: isLandscape ? WrapAlignment.start : WrapAlignment.center,
          spacing: widget.isCompact ? 8 : 16,
          runSpacing: 4,
          children: [
            TextButton.icon(
              onPressed: widget.onAbandonFocus,
              icon: Icon(Icons.stop_rounded, size: widget.isCompact ? 16 : 18),
              label: Text('放弃',
                  style: TextStyle(fontSize: widget.isCompact ? 13 : 14)),
              style: TextButton.styleFrom(
                foregroundColor: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withValues(alpha: 0.4),
                padding: EdgeInsets.symmetric(
                    horizontal: widget.isCompact ? 12 : 16, vertical: 12),
              ),
            ),
            if (widget.isStrictMode)
              TextButton.icon(
                onPressed: null,
                icon: Icon(Icons.screen_rotation_alt_rounded,
                    size: widget.isCompact ? 18 : 20),
                label: Text('翻转控制',
                    style: TextStyle(fontSize: widget.isCompact ? 14 : 15)),
                style: TextButton.styleFrom(
                  padding: EdgeInsets.symmetric(
                      horizontal: widget.isCompact ? 20 : 24, vertical: 12),
                ),
              )
            else
              TextButton.icon(
                onPressed: widget.onShowPauseDialog,
                icon: Icon(
                    widget.onPauseFocus == null
                        ? Icons.play_arrow_rounded
                        : Icons.pause_rounded,
                    size: widget.isCompact ? 18 : 20),
                label: Text(widget.onPauseFocus == null ? '继续' : '暂停',
                    style: TextStyle(fontSize: widget.isCompact ? 14 : 15)),
                style: TextButton.styleFrom(
                  foregroundColor: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.6),
                  backgroundColor: Theme.of(context)
                      .colorScheme
                      .surfaceContainerHighest
                      .withValues(alpha: 0.3),
                  padding: EdgeInsets.symmetric(
                      horizontal: widget.isCompact ? 20 : 24, vertical: 12),
                ),
              ),
            TextButton.icon(
              onPressed: widget.onFinishEarly,
              icon: Icon(Icons.check_rounded, size: widget.isCompact ? 16 : 18),
              label: Text('完成',
                  style: TextStyle(fontSize: widget.isCompact ? 13 : 14)),
              style: TextButton.styleFrom(
                foregroundColor: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withValues(alpha: 0.4),
                padding: EdgeInsets.symmetric(
                    horizontal: widget.isCompact ? 12 : 16, vertical: 12),
              ),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: EdgeInsets.only(bottom: widget.isCompact ? 6 : 8),
      child: OutlinedButton.icon(
        key: const ValueKey('skip_break_btn'),
        onPressed: widget.onSkipBreak,
        icon: Icon(Icons.skip_next_rounded, size: widget.isCompact ? 18 : 24),
        label: Text('跳过休息',
            style: TextStyle(fontSize: widget.isCompact ? 14 : 16)),
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(double.infinity, 52),
          padding: EdgeInsets.symmetric(vertical: widget.isCompact ? 12 : 14),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
      ),
    );
  }
}
