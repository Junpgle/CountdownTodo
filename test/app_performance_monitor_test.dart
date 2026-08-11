import 'package:flutter_test/flutter_test.dart';
import 'package:countdown_todo/utils/app_performance_monitor.dart';

void main() {
  setUp(AppPerformanceMonitor.resetForTesting);

  test('records slow frame details with the current screen', () {
    AppPerformanceMonitor.setCurrentScreen('首页');
    AppPerformanceMonitor.recordFrameForTesting(
      buildDuration: const Duration(milliseconds: 20),
      rasterDuration: const Duration(milliseconds: 4),
      totalSpan: const Duration(milliseconds: 35),
    );

    final snapshot = AppPerformanceMonitor.snapshot;

    expect(snapshot.frameCount, 1);
    expect(snapshot.slowBuildCount, 1);
    expect(snapshot.slowRasterCount, 0);
    expect(snapshot.overThresholdCount, 1);
    expect(snapshot.maxFrameSpan, const Duration(milliseconds: 35));
    expect(snapshot.events.single.screen, '首页');
    expect(
        snapshot.events.single.buildDuration, const Duration(milliseconds: 20));
    expect(
        snapshot.events.single.rasterDuration, const Duration(milliseconds: 4));
  });

  test('threshold and screen tracking can be changed for a session', () {
    AppPerformanceMonitor.setThresholdForTesting(50);
    AppPerformanceMonitor.setScreenTrackingForTesting(false);
    AppPerformanceMonitor.setCurrentScreen('番茄钟');

    AppPerformanceMonitor.recordFrameForTesting(
      buildDuration: const Duration(milliseconds: 10),
      rasterDuration: const Duration(milliseconds: 10),
      totalSpan: const Duration(milliseconds: 35),
    );

    expect(AppPerformanceMonitor.snapshot.overThresholdCount, 0);

    AppPerformanceMonitor.recordFrameForTesting(
      buildDuration: const Duration(milliseconds: 10),
      rasterDuration: const Duration(milliseconds: 10),
      totalSpan: const Duration(milliseconds: 60),
    );

    expect(AppPerformanceMonitor.snapshot.events.single.screen, '界面追踪已关闭');
  });
}
