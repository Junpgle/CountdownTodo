import 'package:flutter/material.dart';
import '../../../services/pomodoro_service.dart';
import '../../../services/pomodoro_sync_service.dart';

class ImmersiveTimer extends StatelessWidget {
  final PomodoroPhase phase;
  final int remainingSeconds;
  final int focusMinutes;
  final int breakMinutes;
  final int currentCycle;
  final int totalCycles;
  final bool isCountUp;
  final bool isRemoteCountUp;
  final CrossDevicePomodoroState? remoteState;

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
  });

  @override
  Widget build(BuildContext context) {
    final isFocusing = phase == PomodoroPhase.focusing;
    final isBreaking = phase == PomodoroPhase.breaking;
    final isFinished = phase == PomodoroPhase.finished;
    final isRemote   = phase == PomodoroPhase.remoteWatching;
    final isActive   = isFocusing || isBreaking || isRemote;

    // 🚀 正计时模式判断：直接使用传入的 flag
    final bool effectiveIsCountUp = isRemote ? isRemoteCountUp : (isFocusing && isCountUp);

    final totalSeconds = isBreaking
        ? breakMinutes * 60
        : focusMinutes * 60;

    double progress = 0.0;
    if (effectiveIsCountUp) {
      // 正计时模式：每分钟循环一次
      progress = (remainingSeconds % 60) / 60.0;
    } else {
      progress = totalSeconds > 0
          ? 1.0 - (remainingSeconds / totalSeconds).clamp(0.0, 1.0)
          : 0.0;
    }

    final mins = remainingSeconds ~/ 60;
    final secs = remainingSeconds % 60;
    String timeStr = '';

    if (effectiveIsCountUp) {
      // 正计时显示已过时长
      timeStr = '${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
    } else {
      // 倒计时显示剩余时长
      timeStr = remainingSeconds > 60
          ? "${((remainingSeconds / 60).ceil())}'"
          : '${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
    }

    Color ringColor = Theme.of(context).colorScheme.primary;
    if (isFocusing) ringColor = const Color(0xFFFF6B6B);
    if (isBreaking) ringColor = const Color(0xFF4ECDC4);
    if (isFinished) ringColor = const Color(0xFFFFD166);
    if (isRemote)   ringColor = const Color(0xFFFF6B6B).withValues(alpha: 0.6);

    final labelColor = Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6);
    final timeColor  = Theme.of(context).colorScheme.onSurface;
    final cycleTextColor = Theme.of(context).colorScheme.onSurfaceVariant;
    final cycleBgColor   = Theme.of(context).colorScheme.surfaceContainerHighest;
    final trackColor     = Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5);

    final remoteTotal = remoteState?.duration;
    final remoteProgress = (isRemote && remoteTotal != null && remoteTotal > 0)
        ? 1.0 - (remainingSeconds / remoteTotal).clamp(0.0, 1.0)
        : progress;

    final String labelText = isBreaking  ? '☕ 休息中'
        : isFinished ? '🎉 完成！'
        : isFocusing ? (effectiveIsCountUp ? '📈 正在正计时' : '🍅 保持专注')
        : isRemote   ? '👀 ${remoteState?.sourceDevice?.replaceFirst('flutter_', '') ?? '其他设备'} ${isRemoteCountUp ? '正计时' : '专注'}中'
        : '准备开始';

    final String cycleText = isRemote
        ? '同步观察'
        : (effectiveIsCountUp ? '自由模式' : '第 $currentCycle / $totalCycles 轮');

    final double ringSize = isActive ? 268.0 : 210.0;
    final double strokeW  = isActive ? 12.0 : 10.0;
    final double timeFontSize  = isActive ? 60.0 : 48.0;
    final double labelFontSize = isActive ? 13.0 : 12.0;

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
              blurRadius: 36,
              spreadRadius: 8,
            ),
        ],
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: ringSize,
            height: ringSize,
            child: CircularProgressIndicator(
              value: 1.0,
              strokeWidth: strokeW,
              valueColor: AlwaysStoppedAnimation<Color>(trackColor),
            ),
          ),
          SizedBox(
            width: ringSize,
            height: ringSize,
            child: CircularProgressIndicator(
              value: remoteProgress,
              strokeWidth: strokeW,
              strokeCap: StrokeCap.round,
              valueColor: AlwaysStoppedAnimation<Color>(ringColor),
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: Text(
                  labelText,
                  key: ValueKey(phase),
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
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(
                  color: cycleBgColor,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  cycleText,
                  style: TextStyle(
                    fontSize: 11,
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
