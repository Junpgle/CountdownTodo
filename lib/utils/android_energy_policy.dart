import 'app_platform.dart';
import '../services/power_save_mode_service.dart';

/// Shared Android-only limits for energy-sensitive UI and sensor work.
abstract final class AndroidEnergyPolicy {
  static const Duration androidStrictFocusSensorPeriod =
      Duration(milliseconds: 200);
  static const Duration androidPowerSaveStrictFocusSensorPeriod =
      Duration(milliseconds: 500);
  static const Duration defaultStrictFocusSensorPeriod =
      Duration(milliseconds: 100);
  static const Duration androidDisconnectedSyncProbeInterval =
      Duration(minutes: 2);
  static const Duration androidPowerSaveDisconnectedSyncProbeInterval =
      Duration(minutes: 5);
  static const Duration defaultDisconnectedSyncProbeInterval =
      Duration(minutes: 1);
  static const Duration androidForegroundWidgetRefreshInterval =
      Duration(hours: 1);
  static const Duration defaultForegroundWidgetRefreshInterval =
      Duration(minutes: 30);
  static const Duration androidPowerSaveVisibleClockInterval =
      Duration(minutes: 1);
  static const Duration defaultVisibleClockInterval = Duration(seconds: 1);

  static Duration get strictFocusSensorPeriod => strictFocusSensorPeriodFor(
        isAndroid: AppPlatform.isAndroid,
        isPowerSaveMode: PowerSaveModeService.isEnabled,
      );

  static Duration strictFocusSensorPeriodFor({
    required bool isAndroid,
    bool isPowerSaveMode = false,
  }) {
    if (isAndroid && isPowerSaveMode) {
      return androidPowerSaveStrictFocusSensorPeriod;
    }
    return isAndroid
        ? androidStrictFocusSensorPeriod
        : defaultStrictFocusSensorPeriod;
  }

  /// HTTP probing is only a fallback used while the realtime connection is
  /// already disconnected. Android waits longer between probes to avoid
  /// needless radio wakeups; WebSocket state changes still update instantly.
  static Duration get disconnectedSyncProbeInterval =>
      disconnectedSyncProbeIntervalFor(
        isAndroid: AppPlatform.isAndroid,
        isPowerSaveMode: PowerSaveModeService.isEnabled,
      );

  static Duration disconnectedSyncProbeIntervalFor({
    required bool isAndroid,
    bool isPowerSaveMode = false,
  }) {
    if (isAndroid && isPowerSaveMode) {
      return androidPowerSaveDisconnectedSyncProbeInterval;
    }
    return isAndroid
        ? androidDisconnectedSyncProbeInterval
        : defaultDisconnectedSyncProbeInterval;
  }

  /// Low-priority marquee/danmaku motion needs fewer timer wakeups on Android.
  /// Callers scale their movement distance by the returned interval so the
  /// perceived pixels-per-second speed remains unchanged.
  static Duration decorativeScrollInterval(Duration defaultInterval) {
    return decorativeScrollIntervalFor(
      isAndroid: AppPlatform.isAndroid,
      isPowerSaveMode: PowerSaveModeService.isEnabled,
      defaultInterval: defaultInterval,
    );
  }

  static Duration decorativeScrollIntervalFor({
    required bool isAndroid,
    bool isPowerSaveMode = false,
    required Duration defaultInterval,
  }) {
    assert(defaultInterval > Duration.zero);
    if (!isAndroid) return defaultInterval;
    return Duration(
      microseconds: defaultInterval.inMicroseconds * (isPowerSaveMode ? 4 : 2),
    );
  }

  /// Decorative motion is paused while Android Battery Saver is active.
  static bool get shouldRunDecorativeMotion => shouldRunDecorativeMotionFor(
        isAndroid: AppPlatform.isAndroid,
        isPowerSaveMode: PowerSaveModeService.isEnabled,
      );

  static bool shouldRunDecorativeMotionFor({
    required bool isAndroid,
    required bool isPowerSaveMode,
  }) {
    return !isAndroid || !isPowerSaveMode;
  }

  /// Android's native widget providers already perform their own scheduled
  /// refreshes, while data mutations trigger immediate Flutter-side updates.
  /// The foreground full-database fallback can therefore run less often.
  static Duration get foregroundWidgetRefreshInterval =>
      foregroundWidgetRefreshIntervalFor(isAndroid: AppPlatform.isAndroid);

  static bool get shouldRunForegroundWidgetRefresh =>
      shouldRunForegroundWidgetRefreshFor(
        isAndroid: AppPlatform.isAndroid,
        isPowerSaveMode: PowerSaveModeService.isEnabled,
      );

  static bool shouldRunForegroundWidgetRefreshFor({
    required bool isAndroid,
    required bool isPowerSaveMode,
  }) {
    return !isAndroid || !isPowerSaveMode;
  }

  static Duration foregroundWidgetRefreshIntervalFor({
    required bool isAndroid,
  }) {
    return isAndroid
        ? androidForegroundWidgetRefreshInterval
        : defaultForegroundWidgetRefreshInterval;
  }

  /// Android decorative loops settle after a few passes so static screens can
  /// stop requesting frames. Other platforms keep their existing motion.
  static int? decorativeRepeatCount({int androidCount = 4}) {
    return decorativeRepeatCountFor(
      isAndroid: AppPlatform.isAndroid,
      isPowerSaveMode: PowerSaveModeService.isEnabled,
      androidCount: androidCount,
    );
  }

  static int? decorativeRepeatCountFor({
    required bool isAndroid,
    bool isPowerSaveMode = false,
    int androidCount = 4,
  }) {
    assert(androidCount > 0);
    if (!isAndroid) return null;
    return isPowerSaveMode ? 1 : androidCount;
  }

  /// Visible clocks only need minute-level updates while Android Battery Saver
  /// is active. Countdown engines and notification timing remain untouched.
  static Duration get visibleClockInterval => visibleClockIntervalFor(
        isAndroid: AppPlatform.isAndroid,
        isPowerSaveMode: PowerSaveModeService.isEnabled,
      );

  static Duration visibleClockIntervalFor({
    required bool isAndroid,
    required bool isPowerSaveMode,
  }) {
    return isAndroid && isPowerSaveMode
        ? androidPowerSaveVisibleClockInterval
        : defaultVisibleClockInterval;
  }
}
