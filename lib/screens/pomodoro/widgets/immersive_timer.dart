import 'package:flutter/material.dart';
import '../../../services/pomodoro_service.dart';
import '../../../services/pomodoro_sync_service.dart';
import '../../../services/strict_focus_sensor_service.dart';
import '../../../services/power_save_mode_service.dart';
import '../../../utils/android_energy_policy.dart';

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
  final bool isStrictMode;
  final bool isStrictWaitingForFlip;
  final StrictFocusSensorState strictSensorState;

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
    this.isStrictMode = false,
    this.isStrictWaitingForFlip = false,
    this.strictSensorState = StrictFocusSensorState.waitingForFaceUp,
  });

  @override
  State<ImmersiveTimer> createState() => _ImmersiveTimerState();
}

class _ImmersiveTimerState extends State<ImmersiveTimer>
    with TickerProviderStateMixin {
  late AnimationController _celebrationController;
  late AnimationController _breathingController;

  @override
  void initState() {
    super.initState();
    _celebrationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _breathingController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2500),
    );
    PowerSaveModeService.enabledListenable
        .addListener(_syncPowerSaveAnimations);
    if (_shouldCelebrate(widget)) _startCelebration();
    if (_shouldBreathe(widget)) _startBreathing();
  }

  @override
  void didUpdateWidget(covariant ImmersiveTimer oldWidget) {
    super.didUpdateWidget(oldWidget);

    final wasCelebrating = _shouldCelebrate(oldWidget);
    final shouldCelebrate = _shouldCelebrate(widget);
    if (shouldCelebrate && !wasCelebrating) {
      _startCelebration();
    } else if (!shouldCelebrate && wasCelebrating) {
      _celebrationController
        ..stop()
        ..reset();
    }

    final wasBreathing = _shouldBreathe(oldWidget);
    final shouldBreathe = _shouldBreathe(widget);
    if (shouldBreathe && !wasBreathing) {
      _startBreathing();
    } else if (!shouldBreathe && wasBreathing) {
      _breathingController
        ..stop()
        ..reset();
    }
  }

  bool _shouldCelebrate(ImmersiveTimer value) =>
      value.phase == PomodoroPhase.finished &&
      AndroidEnergyPolicy.shouldRunDecorativeMotion;

  bool _shouldBreathe(ImmersiveTimer value) =>
      value.phase == PomodoroPhase.focusing &&
      !value.isPaused &&
      !value.isStrictWaitingForFlip &&
      AndroidEnergyPolicy.shouldRunDecorativeMotion;

  void _syncPowerSaveAnimations() {
    if (_shouldCelebrate(widget)) {
      _startCelebration();
    } else {
      _celebrationController
        ..stop()
        ..reset();
    }
    if (_shouldBreathe(widget)) {
      _startBreathing();
    } else {
      _breathingController
        ..stop()
        ..reset();
    }
  }

  void _startCelebration() {
    _celebrationController
      ..reset()
      ..repeat(
        count: AndroidEnergyPolicy.decorativeRepeatCount(androidCount: 3),
      );
  }

  void _startBreathing() {
    _breathingController
      ..reset()
      ..repeat(
        reverse: true,
        count: AndroidEnergyPolicy.decorativeRepeatCount(),
      );
  }

  @override
  void dispose() {
    PowerSaveModeService.enabledListenable
        .removeListener(_syncPowerSaveAnimations);
    _celebrationController.dispose();
    _breathingController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isFocusing = widget.phase == PomodoroPhase.focusing;
    final isBreaking = widget.phase == PomodoroPhase.breaking;
    final isFinished = widget.phase == PomodoroPhase.finished;
    final isRemote = widget.phase == PomodoroPhase.remoteWatching;
    final isStrictWaiting = widget.isStrictWaitingForFlip;
    // 等待翻转仍属于闲置态，保持较小圆环，避免在竖屏下把底部操作区顶出屏幕。
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

    final timeStr = isStrictWaiting
        ? '--:--'
        : effectiveIsCountUp
            ? formatTimerMMSS(widget.remainingSeconds)
            : formatCountdown(widget.remainingSeconds);

    Color ringColor = Theme.of(context).colorScheme.primary;
    if (isFocusing) ringColor = const Color(0xFFFF6B6B);
    if (isBreaking) ringColor = const Color(0xFF4ECDC4);
    if (isFinished) ringColor = const Color(0xFFFFD166);
    if (isRemote) ringColor = const Color(0xFFFF6B6B).withValues(alpha: 0.6);
    if (isStrictWaiting) {
      ringColor = Theme.of(context).colorScheme.primary;
    }

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

    final String labelText = isStrictWaiting
        ? (widget.strictSensorState == StrictFocusSensorState.waitingForFaceUp
            ? '请先将屏幕朝上'
            : '翻转手机开始计时')
        : isBreaking
            ? '☕ 休息中'
            : isFinished
                ? '🎉 完成！'
                : isFocusing
                    ? (widget.isPaused
                        ? (widget.isStrictMode
                            ? '⏸️ 请翻转手机继续'
                            : widget.pauseSeconds > 0
                                ? '⏸️ 暂停中 ${formatTimerMMSS(widget.pauseSeconds)}'
                                : '⏸️ 已暂停')
                        : (effectiveIsCountUp ? '正在正计时' : '保持专注'))
                    : isRemote
                        ? '$displayIdentifier ${widget.isRemoteCountUp ? '正计时' : '专注'}中'
                        : '准备开始';

    final String cycleText =
        isStrictWaiting || (widget.isStrictMode && isFocusing)
            ? '严格自由模式'
            : isRemote
                ? '同步观察'
                : (effectiveIsCountUp
                    ? '自由模式'
                    : '第 ${widget.currentCycle} / ${widget.totalCycles} 轮');

    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;
    final compactFactor = widget.isCompact ? 0.72 : 1.0;

    final double ringSize = (isLandscape
            ? (isActive ? 240.0 : 200.0)
            : (isActive ? 280.0 : 220.0)) *
        compactFactor;
    final double strokeW =
        isActive ? 14.0 * compactFactor : 10.0 * compactFactor;
    final double timeFontSize =
        (isLandscape ? (isActive ? 64.0 : 50.0) : (isActive ? 72.0 : 56.0)) *
            compactFactor;
    final double labelFontSize = (isActive ? 15.0 : 13.0) * compactFactor;

    return AnimatedBuilder(
      animation: _breathingController,
      builder: (context, child) {
        final breathValue =
            (isFocusing && !widget.isPaused) ? _breathingController.value : 0.0;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 500),
          curve: Curves.easeInOut,
          width: ringSize,
          height: ringSize,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Theme.of(context).colorScheme.surface,
            boxShadow: [
              if (isActive)
                BoxShadow(
                  color:
                      ringColor.withValues(alpha: 0.15 + (breathValue * 0.15)),
                  blurRadius: (24 + (breathValue * 16)) * compactFactor,
                  spreadRadius: (4 + (breathValue * 6)) * compactFactor,
                ),
              if (isActive)
                BoxShadow(
                  color: Theme.of(context)
                      .colorScheme
                      .shadow
                      .withValues(alpha: 0.08),
                  blurRadius: 16 * compactFactor,
                  offset: const Offset(0, 8),
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
                    valueColor:
                        AlwaysStoppedAnimation<Color>(color ?? trackColor),
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
                    valueColor:
                        AlwaysStoppedAnimation<Color>(color ?? ringColor),
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
                        final t =
                            ((_celebrationController.value - delay) % 1.0);
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
                                color:
                                    ringColor.withValues(alpha: opacity * 0.4),
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
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1.2,
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
                      fontWeight: FontWeight.w200,
                      color: timeColor,
                      fontFeatures: const [FontFeature.tabularFigures()],
                      letterSpacing: -1,
                    ),
                    child: Text(timeStr),
                  ),
                  const SizedBox(height: 2),
                  Container(
                    padding: EdgeInsets.symmetric(
                        horizontal: 12 * compactFactor,
                        vertical: 4 * compactFactor),
                    decoration: BoxDecoration(
                      color: cycleBgColor.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(12 * compactFactor),
                      border: Border.all(
                        color: cycleTextColor.withValues(alpha: 0.1),
                        width: 1,
                      ),
                    ),
                    child: Text(
                      cycleText,
                      style: TextStyle(
                        fontSize: 12 * compactFactor,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 0.5,
                        color: cycleTextColor,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}
