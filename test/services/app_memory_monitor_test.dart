import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:countdown_todo/services/app_memory_monitor.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await AppMemoryMonitor.init();
    AppMemoryMonitor.setAutoRefresh(false);
  });

  tearDown(() {
    AppMemoryMonitor.setAutoRefresh(false);
  });

  group('AppMemoryMonitor & MemorySnapshot tests', () {
    test('formatBytes formats zero and various data sizes correctly', () {
      expect(AppMemoryMonitor.formatBytes(0), '0 B');
      expect(AppMemoryMonitor.formatBytes(512), '512 B');
      expect(AppMemoryMonitor.formatBytes(1024), '1.0 KB');
      expect(AppMemoryMonitor.formatBytes(1024 * 1024), '1.0 MB');
      expect(AppMemoryMonitor.formatBytes(150 * 1024 * 1024), '150.0 MB');
      expect(
        AppMemoryMonitor.formatBytes((2.5 * 1024 * 1024 * 1024).round()),
        '2.5 GB',
      );
    });

    test('MemorySnapshot fields and health evaluations', () {
      final normalSnapshot = MemorySnapshot(
        currentRss: 120 * 1024 * 1024,
        maxRss: 200 * 1024 * 1024,
        imageCacheBytes: 15 * 1024 * 1024,
        imageCacheCount: 10,
        maxImageCacheBytes: 96 * 1024 * 1024,
        maxImageCacheCount: 100,
        timestamp: DateTime.now(),
        isProcessMemorySupported: true,
      );

      expect(normalSnapshot.currentRssFormatted, '120.0 MB');
      expect(normalSnapshot.maxRssFormatted, '200.0 MB');
      expect(normalSnapshot.imageCacheFormatted, '15.0 MB');
      expect(normalSnapshot.maxImageCacheBytesFormatted, '96.0 MB');
      expect(normalSnapshot.healthLevel, MemoryHealthLevel.normal);
      expect(normalSnapshot.healthDescription, '正常');
      expect(normalSnapshot.peakRatio, closeTo(0.6, 0.01));
    });

    test('policy mode switches runtime imageCache limits', () async {
      final imageCache = PaintingBinding.instance.imageCache;

      await AppMemoryMonitor.setPolicyMode(MemoryPolicyMode.eco);
      expect(AppMemoryMonitor.policyMode.value, MemoryPolicyMode.eco);
      final ecoLimit = imageCache.maximumSizeBytes;

      await AppMemoryMonitor.setPolicyMode(MemoryPolicyMode.performance);
      expect(AppMemoryMonitor.policyMode.value, MemoryPolicyMode.performance);
      final perfLimit = imageCache.maximumSizeBytes;

      expect(perfLimit, greaterThan(ecoLimit));

      await AppMemoryMonitor.setPolicyMode(MemoryPolicyMode.balanced);
      expect(AppMemoryMonitor.policyMode.value, MemoryPolicyMode.balanced);
    });

    test(
      'cleanCache executes without errors and produces valid snapshot',
      () async {
        final freed = await AppMemoryMonitor.cleanCache();
        expect(freed, greaterThanOrEqualTo(0));

        final snapshot = AppMemoryMonitor.currentSnapshot;
        expect(snapshot.timestamp, isNotNull);
        expect(snapshot.imageCacheBytes, greaterThanOrEqualTo(0));
      },
    );

    test('autoRefresh toggle starts and stops timer gracefully', () async {
      expect(AppMemoryMonitor.isAutoRefreshing.value, isFalse);

      AppMemoryMonitor.setAutoRefresh(
        true,
        interval: const Duration(milliseconds: 50),
      );
      expect(AppMemoryMonitor.isAutoRefreshing.value, isTrue);

      await Future<void>.delayed(const Duration(milliseconds: 120));

      AppMemoryMonitor.setAutoRefresh(false);
      expect(AppMemoryMonitor.isAutoRefreshing.value, isFalse);
    });
  });
}
