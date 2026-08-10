import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A frame which exceeded the configured diagnostic threshold.
class FramePerformanceEvent {
  const FramePerformanceEvent({
    required this.frameNumber,
    required this.observedAt,
    required this.buildDuration,
    required this.rasterDuration,
    required this.totalSpan,
    required this.screen,
  });

  final int frameNumber;
  final DateTime observedAt;
  final Duration buildDuration;
  final Duration rasterDuration;
  final Duration totalSpan;
  final String screen;
}

/// A snapshot of the opt-in frame diagnostics session.
class AppPerformanceSnapshot {
  const AppPerformanceSnapshot({
    required this.frameCount,
    required this.slowBuildCount,
    required this.slowRasterCount,
    required this.overThresholdCount,
    required this.maxFrameSpan,
    required this.thresholdMilliseconds,
    required this.events,
  });

  final int frameCount;
  final int slowBuildCount;
  final int slowRasterCount;
  final int overThresholdCount;
  final Duration maxFrameSpan;
  final int thresholdMilliseconds;
  final List<FramePerformanceEvent> events;
}

/// Lightweight frame telemetry for debug/profile builds.
///
/// Release builds do not register the callback. The existing periodic log is
/// kept for profiling, while the detailed event list is opt-in so opening the
/// debug panel does not itself add per-frame UI work unless requested.
class AppPerformanceMonitor {
  AppPerformanceMonitor._();

  static const int _reportEveryFrames = 120;
  static const Duration _frameBudget = Duration(microseconds: 16667);
  static const int _defaultThresholdMilliseconds = 32;
  static const int _maxEvents = 50;
  static const String _enabledKey = 'debug_performance_monitor_enabled';
  static const String _screenTrackingKey =
      'debug_performance_monitor_screen_tracking';
  static const String _thresholdKey = 'debug_performance_monitor_threshold';

  static final ValueNotifier<int> changes = ValueNotifier<int>(0);

  static bool _installed = false;
  static bool _settingsLoaded = false;
  static Future<void>? _settingsLoadFuture;
  static bool _enabled = false;
  static bool _screenTrackingEnabled = true;
  static int _thresholdMilliseconds = _defaultThresholdMilliseconds;
  static String _currentScreen = '启动流程';

  // Existing periodic log counters. These deliberately retain their old
  // reset window and output format.
  static int _frameCount = 0;
  static int _slowBuildCount = 0;
  static int _slowRasterCount = 0;
  static int _severeFrameCount = 0;
  static Duration _maxFrameSpan = Duration.zero;

  // Opt-in diagnostic session counters.
  static int _diagnosticFrameCount = 0;
  static int _diagnosticSlowBuildCount = 0;
  static int _diagnosticSlowRasterCount = 0;
  static int _diagnosticOverThresholdCount = 0;
  static Duration _diagnosticMaxFrameSpan = Duration.zero;
  static final List<FramePerformanceEvent> _events = [];
  static int _framesSinceNotify = 0;

  /// Whether this feature can be shown. It is intentionally unavailable in
  /// release builds, even if a preference from a debug build remains on disk.
  static bool get isAvailable => !kReleaseMode;

  static bool get isEnabled => isAvailable && _enabled;

  static bool get isScreenTrackingEnabled =>
      isAvailable && _screenTrackingEnabled;

  static int get thresholdMilliseconds => _thresholdMilliseconds;

  static List<int> get availableThresholds =>
      List.unmodifiable(_allowedThresholds);

  static AppPerformanceSnapshot get snapshot => AppPerformanceSnapshot(
        frameCount: _diagnosticFrameCount,
        slowBuildCount: _diagnosticSlowBuildCount,
        slowRasterCount: _diagnosticSlowRasterCount,
        overThresholdCount: _diagnosticOverThresholdCount,
        maxFrameSpan: _diagnosticMaxFrameSpan,
        thresholdMilliseconds: _thresholdMilliseconds,
        events: List.unmodifiable(_events),
      );

  /// Installs the low-level callback used by both the existing log and the
  /// opt-in diagnostics panel.
  static void install() {
    if (_installed || !isAvailable) return;
    _installed = true;
    SchedulerBinding.instance.addTimingsCallback(_recordTimings);
  }

  /// Loads debug preferences without making startup wait for them.
  static Future<void> loadSettings() {
    if (!isAvailable || _settingsLoaded) return Future<void>.value();
    return _settingsLoadFuture ??= _loadSettings();
  }

  static Future<void> _loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _enabled = prefs.getBool(_enabledKey) ?? false;
      _screenTrackingEnabled = prefs.getBool(_screenTrackingKey) ?? true;
      final threshold =
          prefs.getInt(_thresholdKey) ?? _defaultThresholdMilliseconds;
      _thresholdMilliseconds = _allowedThresholds.contains(threshold)
          ? threshold
          : _defaultThresholdMilliseconds;
    } catch (_) {
      // Debug telemetry must never affect app startup if preferences are
      // unavailable on a platform or in a test environment.
    } finally {
      _settingsLoaded = true;
      _notifyChanged();
    }
  }

  static const List<int> _allowedThresholds = [16, 32, 50, 100];

  static Future<void> setEnabled(bool value) async {
    if (!isAvailable) return;
    _enabled = value;
    _notifyChanged();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_enabledKey, value);
    } catch (_) {}
  }

  static Future<void> setScreenTrackingEnabled(bool value) async {
    if (!isAvailable) return;
    _screenTrackingEnabled = value;
    _notifyChanged();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_screenTrackingKey, value);
    } catch (_) {}
  }

  static Future<void> setThresholdMilliseconds(int value) async {
    if (!isAvailable || !_allowedThresholds.contains(value)) return;
    _thresholdMilliseconds = value;
    _notifyChanged();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_thresholdKey, value);
    } catch (_) {}
  }

  static void clear() {
    _diagnosticFrameCount = 0;
    _diagnosticSlowBuildCount = 0;
    _diagnosticSlowRasterCount = 0;
    _diagnosticOverThresholdCount = 0;
    _diagnosticMaxFrameSpan = Duration.zero;
    _events.clear();
    _framesSinceNotify = 0;
    _notifyChanged();
  }

  /// Updates the label attached to the next frame timings callback.
  static void setCurrentScreen(String screen) {
    final normalized = screen.trim();
    if (!isAvailable || normalized.isEmpty || normalized == _currentScreen) {
      return;
    }
    _currentScreen = normalized;
  }

  /// Makes page transition helpers report the concrete page type. This keeps
  /// the fallback useful even when a route has no explicit RouteSettings name.
  static String screenNameForWidget(Widget widget) {
    final typeName = widget.runtimeType.toString();
    const knownNames = <String, String>{
      'HomeDashboard': '首页',
      'LoginScreen': '登录页',
      'SettingsPage': '设置',
      'AboutScreen': '关于此应用',
      'TeamManagementScreen': '团队管理',
      'ShareViewScreen': '分享查看',
      'PomodoroScreen': '番茄钟',
      'TodoPlanScreen': '计划',
      'HabitCenterScreen': '习惯中心',
      'FeatureGuideScreen': '功能引导',
    };
    return knownNames[typeName] ?? typeName.replaceFirst(RegExp(r'^_+'), '');
  }

  static void _recordTimings(List<FrameTiming> timings) {
    for (final timing in timings) {
      _recordLegacyTiming(timing);
      if (_enabled) {
        _recordDiagnosticTiming(timing);
      }
    }
    _reportLegacyTimingsIfReady();
  }

  static void _recordLegacyTiming(FrameTiming timing) {
    _frameCount++;
    if (timing.buildDuration > _frameBudget) _slowBuildCount++;
    if (timing.rasterDuration > _frameBudget) _slowRasterCount++;
    if (timing.totalSpan > const Duration(milliseconds: 32)) {
      _severeFrameCount++;
    }
    if (timing.totalSpan > _maxFrameSpan) {
      _maxFrameSpan = timing.totalSpan;
    }
  }

  static void _reportLegacyTimingsIfReady() {
    if (_frameCount < _reportEveryFrames) return;
    if (_slowBuildCount > 0 || _slowRasterCount > 0 || _severeFrameCount > 0) {
      debugPrint(
        '[Performance] $_frameCount frames: '
        'slowBuild=$_slowBuildCount, slowRaster=$_slowRasterCount, '
        'over32ms=$_severeFrameCount, '
        'max=${(_maxFrameSpan.inMicroseconds / 1000).toStringAsFixed(1)}ms',
      );
    }
    _frameCount = 0;
    _slowBuildCount = 0;
    _slowRasterCount = 0;
    _severeFrameCount = 0;
    _maxFrameSpan = Duration.zero;
  }

  static void _recordDiagnosticTiming(FrameTiming timing) {
    _recordDiagnosticDurations(
      buildDuration: timing.buildDuration,
      rasterDuration: timing.rasterDuration,
      totalSpan: timing.totalSpan,
    );
  }

  static void _recordDiagnosticDurations({
    required Duration buildDuration,
    required Duration rasterDuration,
    required Duration totalSpan,
  }) {
    _diagnosticFrameCount++;
    if (buildDuration > _frameBudget) _diagnosticSlowBuildCount++;
    if (rasterDuration > _frameBudget) _diagnosticSlowRasterCount++;
    if (totalSpan > _diagnosticMaxFrameSpan) {
      _diagnosticMaxFrameSpan = totalSpan;
    }

    final threshold = Duration(milliseconds: _thresholdMilliseconds);
    if (totalSpan > threshold) {
      _diagnosticOverThresholdCount++;
      _events.insert(
        0,
        FramePerformanceEvent(
          frameNumber: _diagnosticFrameCount,
          observedAt: DateTime.now(),
          buildDuration: buildDuration,
          rasterDuration: rasterDuration,
          totalSpan: totalSpan,
          screen: _screenTrackingEnabled ? _currentScreen : '界面追踪已关闭',
        ),
      );
      if (_events.length > _maxEvents) _events.removeLast();
      _notifyChanged();
    }
    _framesSinceNotify++;
    if (_framesSinceNotify >= 30) {
      _notifyChanged();
      _framesSinceNotify = 0;
    }
  }

  static void _notifyChanged() {
    if (changes.value == 0x7fffffff) {
      changes.value = 0;
    } else {
      changes.value++;
    }
  }

  @visibleForTesting
  static void recordFrameForTesting({
    required Duration buildDuration,
    required Duration rasterDuration,
    required Duration totalSpan,
  }) {
    _enabled = true;
    _recordDiagnosticDurations(
      buildDuration: buildDuration,
      rasterDuration: rasterDuration,
      totalSpan: totalSpan,
    );
  }

  @visibleForTesting
  static void resetForTesting() {
    _enabled = false;
    _screenTrackingEnabled = true;
    _thresholdMilliseconds = _defaultThresholdMilliseconds;
    _currentScreen = '启动流程';
    clear();
  }

  @visibleForTesting
  static void setThresholdForTesting(int value) {
    if (_allowedThresholds.contains(value)) _thresholdMilliseconds = value;
  }

  @visibleForTesting
  static void setScreenTrackingForTesting(bool value) {
    _screenTrackingEnabled = value;
  }
}

/// Captures named routes for cases which do not go through PageTransitions.
class AppPerformanceNavigatorObserver extends NavigatorObserver {
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _setRouteScreen(route);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (previousRoute != null) _setRouteScreen(previousRoute);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    if (newRoute != null) _setRouteScreen(newRoute);
  }

  void _setRouteScreen(Route<dynamic> route) {
    final name = route.settings.name;
    if (name == null || name.isEmpty || name == '/') return;
    const routeNames = <String, String>{
      '/home': '首页',
      '/login': '登录页',
      '/teams': '团队管理',
      '/dev/island': '灵动岛调试',
    };
    AppPerformanceMonitor.setCurrentScreen(routeNames[name] ?? name);
  }
}
