import 'package:flutter/material.dart';
import '../../../services/pomodoro_service.dart';
import '../../../services/pomodoro_sync_service.dart';

class ImmersiveTimer extends StatefulWidget {
  final PomodoroPhase phase;
  final int remainingSeconds;
  final int focusMinutes;
  final int breakMinutes;
  final int currentCycle;
  final int totalCycles;
  final bool isCountUp;
  final bool isRemoteCountUp;
  final CrossDevicePomodoroState? remoteState;
  final bool isCompact;
  final bool isPaused;
  final int pauseSeconds;

  const ImmersiveTimer({
    super.key,
    required this.phase,
    required this.remainingSeconds,
    required this.focusMinutes,
    required this.breakMinutes,
    required this.currentCycle,
    required this.totalCycles,
    this.isCountUp = false,
    this.isRemoteCountUp = false,
    this.remoteState,
    this.isCompact = false,
    this.isPaused = false,
    this.pauseSeconds = 0,
  });

  @override
  State<ImmersiveTimer> createState() => _ImmersiveTimerState();
}

class _ImmersiveTimerState extends State<ImmersiveTimer>
    with SingleTickerProviderStateMixin {
  late AnimationController _celebrationController;

  @override
  void initState() {
    super.initState();
    _celebrationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _celebrationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isFocusing = widget.phase == PomodoroPhase.focusing;
    final isBreaking = widget.phase == PomodoroPhase.breaking;
    final isFinished = widget.phase == PomodoroPhase.finished;
    final isRemote = widget.phase == PomodoroPhase.remoteWatching;
    final isActive = isFocusing || isBreaking || isRemote;

    final bool effectiveIsCountUp =
        isRemote ? widget.isRemoteCountUp : (isFocusing && widget.isCountUp);

    final totalSeconds =
        isBreaking ? widget.breakMinutes * 60 : widget.focusMinutes * 60;

    double progress = 0.0;
    if (effectiveIsCountUp) {
      progress = (widget.remainingSeconds % 60) / 60.0;
    } else {
      progress = totalSeconds > 0
          ? 1.0 - (widget.remainingSeconds / totalSeconds).clamp(0.0, 1.0)
          : 0.0;
    }

    final mins = widget.remainingSeconds ~/ 60;
    final secs = widget.remainingSeconds % 60;
    String timeStr = '';

    if (effectiveIsCountUp) {
      timeStr =
          '${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
    } else {
      timeStr = widget.remainingSeconds > 60
          ? "${((widget.remainingSeconds / 60).ceil())}'"
          : '${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
    }

    Color ringColor = Theme.of(context).colorScheme.primary;
    if (isFocusing) ringColor = const Color(0xFFFF6B6B);
    if (isBreaking) ringColor = const Color(0xFF4ECDC4);
    if (isFinished) ringColor = const Color(0xFFFFD166);
    if (isRemote) ringColor = const Color(0xFFFF6B6B).withValues(alpha: 0.6);

    final labelColor =
        Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6);
    final timeColor = Theme.of(context).colorScheme.onSurface;
    final cycleTextColor = Theme.of(context).colorScheme.onSurfaceVariant;
    final cycleBgColor = Theme.of(context).colorScheme.surfaceContainerHighest;
    final trackColor = Theme.of(context)
        .colorScheme
        .surfaceContainerHighest
        .withValues(alpha: 0.5);

    final remoteTotal = widget.remoteState?.duration;
    final remoteProgress = (isRemote && remoteTotal != null && remoteTotal > 0)
        ? 1.0 - (widget.remainingSeconds / remoteTotal).clamp(0.0, 1.0)
        : progress;

    final sourceIdentifier =
        widget.remoteState?.sourceDevice?.replaceFirst('flutter_', '') ??
            '其他设备';
    final displayIdentifier = sourceIdentifier.length > 12
        ? '${sourceIdentifier.substring(0, 10)}...'
        : sourceIdentifier;

    final String labelText = isBreaking
        ? '☕ 休息中'
        : isFinished
            ? '🎉 完成！'
            : isFocusing
                ? (widget.isPaused
                    ? (widget.pauseSeconds > 0
                        ? '⏸️ 暂停中 ${widget.pauseSeconds ~/ 60}:${(widget.pauseSeconds % 60).toString().padLeft(2, '0')}'
                        : '⏸️ 已暂停')
                    : (effectiveIsCountUp ? '📈 正在正计时' : '🍅 保持专注'))
                : isRemote
                    ? '👀 $displayIdentifier ${widget.isRemoteCountUp ? '正计时' : '专注'}中'
                    : '准备开始';

    final String cycleText = isRemote
        ? '同步观察'
        : (effectiveIsCountUp
            ? '自由模式'
            : '第 ${widget.currentCycle} / ${widget.totalCycles} 轮');

    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;
    final compactFactor = widget.isCompact ? 0.72 : 1.0;

    final double ringSize = (isLandscape
            ? (isActive ? 240.0 : 200.0)
            : (isActive ? 268.0 : 210.0)) *
        compactFactor;
    final double strokeW =
        isActive ? 12.0 * compactFactor : 10.0 * compactFactor;
    final double timeFontSize =
        (isLandscape ? (isActive ? 56.0 : 44.0) : (isActive ? 60.0 : 48.0)) *
            compactFactor;
    final double labelFontSize = (isActive ? 13.0 : 12.0) * compactFactor;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeInOut,
      width: ringSize,
      height: ringSize,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          if (isActive)
            BoxShadow(
              color: ringColor.withValues(alpha: 0.2),
              blurRadius: 36 * compactFactor,
              spreadRadius: 8 * compactFactor,
            ),
        ],
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: ringSize,
            height: ringSize,
            child: TweenAnimationBuilder<Color?>(
              tween: ColorTween(begin: trackColor, end: trackColor),
              duration: const Duration(milliseconds: 400),
              builder: (context, color, child) => CircularProgressIndicator(
                value: 1.0,
                strokeWidth: strokeW,
                valueColor: AlwaysStoppedAnimation<Color>(color ?? trackColor),
              ),
            ),
          ),
          SizedBox(
            width: ringSize,
            height: ringSize,
            child: TweenAnimationBuilder<Color?>(
              tween: ColorTween(begin: ringColor, end: ringColor),
              duration: const Duration(milliseconds: 600),
              curve: Curves.easeInOut,
              builder: (context, color, child) => CircularProgressIndicator(
                value: remoteProgress,
                strokeWidth: strokeW,
                strokeCap: StrokeCap.round,
                valueColor: AlwaysStoppedAnimation<Color>(color ?? ringColor),
              ),
            ),
          ),
          if (isFinished)
            AnimatedBuilder(
              animation: _celebrationController,
              builder: (context, child) {
                return Stack(
                  alignment: Alignment.center,
                  children: List.generate(3, (i) {
                    final delay = i * 0.33;
                    final t = ((_celebrationController.value - delay) % 1.0);
                    final scale = 1.0 + t * 0.5;
                    final opacity = (1.0 - t).clamp(0.0, 1.0);
                    return Transform.scale(
                      scale: scale,
                      child: Container(
                        width: ringSize,
                        height: ringSize,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: ringColor.withValues(alpha: opacity * 0.4),
                            width: 2.0 * compactFactor,
                          ),
                        ),
                      ),
                    );
                  }),
                );
              },
            ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: Text(
                  labelText,
                  key: ValueKey(widget.phase),
                  style: TextStyle(
                    fontSize: labelFontSize,
                    fontWeight: FontWeight.w500,
                    color: labelColor,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(height: 2),
              AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 400),
                curve: Curves.easeInOut,
                style: TextStyle(
                  fontSize: timeFontSize,
                  fontWeight: FontWeight.w300,
                  color: timeColor,
                  fontFeatures: const [FontFeature.tabularFigures()],
                  letterSpacing: -2,
                ),
                child: Text(timeStr),
              ),
              const SizedBox(height: 2),
              Container(
                padding: EdgeInsets.symmetric(
                    horizontal: 10 * compactFactor,
                    vertical: 3 * compactFactor),
                decoration: BoxDecoration(
                  color: cycleBgColor,
                  borderRadius: BorderRadius.circular(10 * compactFactor),
                ),
                child: Text(
                  cycleText,
                  style: TextStyle(
                    fontSize: 11 * compactFactor,
                    fontWeight: FontWeight.w600,
                    color: cycleTextColor,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
