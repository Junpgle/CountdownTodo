import 'app_platform.dart';

/// Shared Android-only limits for energy-sensitive UI and sensor work.
abstract final class AndroidEnergyPolicy {
  static const Duration androidStrictFocusSensorPeriod =
      Duration(milliseconds: 200);
  static const Duration defaultStrictFocusSensorPeriod =
      Duration(milliseconds: 100);
  static const Duration androidDisconnectedSyncProbeInterval =
      Duration(minutes: 2);
  static const Duration defaultDisconnectedSyncProbeInterval =
      Duration(minutes: 1);
  static const Duration androidForegroundWidgetRefreshInterval =
      Duration(hours: 1);
  static const Duration defaultForegroundWidgetRefreshInterval =
      Duration(minutes: 30);

  static Duration get strictFocusSensorPeriod => strictFocusSensorPeriodFor(
        isAndroid: AppPlatform.isAndroid,
      );

  static Duration strictFocusSensorPeriodFor({required bool isAndroid}) {
    return isAndroid
        ? androidStrictFocusSensorPeriod
        : defaultStrictFocusSensorPeriod;
  }

  /// HTTP probing is only a fallback used while the realtime connection is
  /// already disconnected. Android waits longer between probes to avoid
  /// needless radio wakeups; WebSocket state changes still update instantly.
  static Duration get disconnectedSyncProbeInterval =>
      disconnectedSyncProbeIntervalFor(isAndroid: AppPlatform.isAndroid);

  static Duration disconnectedSyncProbeIntervalFor({
    required bool isAndroid,
  }) {
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
      defaultInterval: defaultInterval,
    );
  }

  static Duration decorativeScrollIntervalFor({
    required bool isAndroid,
    required Duration defaultInterval,
  }) {
    assert(defaultInterval > Duration.zero);
    if (!isAndroid) return defaultInterval;
    return Duration(microseconds: defaultInterval.inMicroseconds * 2);
  }

  /// Android's native widget providers already perform their own scheduled
  /// refreshes, while data mutations trigger immediate Flutter-side updates.
  /// The foreground full-database fallback can therefore run less often.
  static Duration get foregroundWidgetRefreshInterval =>
      foregroundWidgetRefreshIntervalFor(isAndroid: AppPlatform.isAndroid);

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
      androidCount: androidCount,
    );
  }

  static int? decorativeRepeatCountFor({
    required bool isAndroid,
    int androidCount = 4,
  }) {
    assert(androidCount > 0);
    return isAndroid ? androidCount : null;
  }
}
