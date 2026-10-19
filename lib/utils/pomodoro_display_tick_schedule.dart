/// Returns the next second boundary at which a dashboard Pomodoro display
/// needs to refresh.
///
/// Long countdowns and count-up sessions show whole minutes, while the final
/// countdown minute shows seconds. The local dashboard also refreshes at the
/// 30-minute stop-control boundary.
int dashboardPomodoroDisplayTickDelaySeconds(
  int secondsRemaining, {
  required bool countUp,
  bool includeStopControlBoundary = false,
}) {
  final seconds = secondsRemaining < 0 ? 0 : secondsRemaining;
  if (countUp) return 60 - seconds % 60;
  if (seconds <= 60) return 1;

  final minutes = seconds ~/ 60;
  final nextDisplayThreshold = minutes == 1 ? 60 : minutes * 60 - 1;
  var delaySeconds = seconds - nextDisplayThreshold;

  if (includeStopControlBoundary && seconds > 30 * 60) {
    final stopControlDelay = seconds - 30 * 60;
    if (stopControlDelay < delaySeconds) {
      delaySeconds = stopControlDelay;
    }
  }

  return delaySeconds > 0 ? delaySeconds : 1;
}
