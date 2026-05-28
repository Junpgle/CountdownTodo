import 'package:flutter/foundation.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

import '../storage_service.dart';

class WallpaperCacheService {
  WallpaperCacheService._();

  static const Duration cleanupInterval = Duration(days: 7);

  static final CacheManager cacheManager = CacheManager(
    Config(
      'wallpaperImageCache',
      stalePeriod: cleanupInterval,
      maxNrOfCacheObjects: 10,
    ),
  );

  static Future<void> cleanupIfNeeded() async {
    final now = DateTime.now();
    final lastCleanupTimestamp =
        await StorageService.getWallpaperCacheCleanupTime();

    if (lastCleanupTimestamp != null) {
      final lastCleanup =
          DateTime.fromMillisecondsSinceEpoch(lastCleanupTimestamp);
      if (now.difference(lastCleanup) < cleanupInterval) {
        return;
      }
    }

    try {
      await cacheManager.emptyCache();
      await StorageService.saveWallpaperCacheCleanupTime(
        now.millisecondsSinceEpoch,
      );
    } catch (e) {
      debugPrint('[WallpaperCache] 清理壁纸缓存失败: $e');
    }
  }
}
