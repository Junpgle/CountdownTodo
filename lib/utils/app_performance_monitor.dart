import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

/// Lightweight frame telemetry for debug/profile builds.
///
/// Release builds do not register the callback. This keeps production free of
/// per-frame bookkeeping while making regressions visible during profiling.
class AppPerformanceMonitor {
  AppPerformanceMonitor._();

  static const int _reportEveryFrames = 120;
  static const Duration _frameBudget = Duration(microseconds: 16667);
  static const Duration _severeBudget = Duration(milliseconds: 32);

  static bool _installed = false;
  static int _frameCount = 0;
  static int _slowBuildCount = 0;
  static int _slowRasterCount = 0;
  static int _severeFrameCount = 0;
  static Duration _maxFrameSpan = Duration.zero;

  static void install() {
    if (_installed || kReleaseMode) return;
    _installed = true;
    SchedulerBinding.instance.addTimingsCallback(_recordTimings);
  }

  static void _recordTimings(List<FrameTiming> timings) {
    for (final timing in timings) {
      _frameCount++;
      if (timing.buildDuration > _frameBudget) _slowBuildCount++;
      if (timing.rasterDuration > _frameBudget) _slowRasterCount++;
      if (timing.totalSpan > _severeBudget) _severeFrameCount++;
      if (timing.totalSpan > _maxFrameSpan) {
        _maxFrameSpan = timing.totalSpan;
      }
    }

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
}
