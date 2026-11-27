import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'github_resource_service.dart';
import 'splash_service_shared.dart';
import '../utils/time_utils.dart';

class SplashService {
  static final GitHubResourceService _resourceService = GitHubResourceService();
  static const String splashConfigUrl = SplashServiceShared.splashConfigUrl;

  static Future<void> prefetchTomorrowContent() async {
    try {
      final today = DateTime.now();
      final tomorrow = AppTimeFormats.localDayStartOffset(today, 1);
      final tomorrowStr = SplashServiceShared.formatDate(tomorrow);

      final prefs = await SharedPreferences.getInstance();
      if (prefs.getString(SplashServiceShared.prefetchedContentDateKey) ==
          tomorrowStr) {
        return;
      }

      final config = await SplashServiceShared.fetchConfig();
      if (config == null) return;

      final Map<String, dynamic>? dayConfig = config[tomorrowStr];
      if (dayConfig == null) return;

      String? localImagePath;
      final imageUrl = dayConfig['image_url'];
      if (imageUrl != null && imageUrl.isNotEmpty) {
        localImagePath = await _downloadImage(imageUrl);
      }

      await SplashServiceShared.storeDayContent(
        prefs,
        dateStr: tomorrowStr,
        dayConfig: dayConfig,
        resolvedImagePath: localImagePath,
        dateKey: SplashServiceShared.prefetchedContentDateKey,
        imageKey: SplashServiceShared.prefetchedImagePathKey,
        titleKey: SplashServiceShared.prefetchedTitleKey,
        subtitleKey: SplashServiceShared.prefetchedSubtitleKey,
        bgTopKey: SplashServiceShared.prefetchedBgColorTopKey,
        bgBottomKey: SplashServiceShared.prefetchedBgColorBottomKey,
        durationKey: SplashServiceShared.prefetchedDurationMsKey,
      );
    } catch (_) {}
  }

  static Future<void> fetchAndCacheTodayContent() async {
    try {
      final todayStr = SplashServiceShared.formatDate(DateTime.now());

      final prefs = await SharedPreferences.getInstance();
      if (prefs.getString(SplashServiceShared.cachedContentDateKey) ==
          todayStr) {
        return;
      }

      final config = await SplashServiceShared.fetchConfig();
      if (config == null) return;

      final Map<String, dynamic>? dayConfig = config[todayStr];
      if (dayConfig == null) return;

      String? localImagePath;
      final imageUrl = dayConfig['image_url'];
      if (imageUrl != null && imageUrl.isNotEmpty) {
        localImagePath = await _downloadImage(imageUrl);
      }

      await SplashServiceShared.storeDayContent(
        prefs,
        dateStr: todayStr,
        dayConfig: dayConfig,
        resolvedImagePath: localImagePath,
        dateKey: SplashServiceShared.cachedContentDateKey,
        imageKey: SplashServiceShared.cachedImagePathKey,
        titleKey: SplashServiceShared.cachedTitleKey,
        subtitleKey: SplashServiceShared.cachedSubtitleKey,
        bgTopKey: SplashServiceShared.cachedBgColorTopKey,
        bgBottomKey: SplashServiceShared.cachedBgColorBottomKey,
        durationKey: SplashServiceShared.cachedDurationMsKey,
      );
    } catch (_) {}
  }

  static Future<Map<String, dynamic>?> getCachedContent() =>
      SplashServiceShared.getCachedContent(
        imageExists: (imagePath) => File(imagePath).existsSync(),
      );

  static Future<String?> _downloadImage(String url) async {
    try {
      final response = await _resourceService.getUrl(url);
      if (response.statusCode == 200) {
        final dir = await getApplicationCacheDirectory();
        final filePath =
            '${dir.path}/splash_image_${DateTime.now().millisecondsSinceEpoch}.png';
        final file = File(filePath);
        await file.writeAsBytes(response.bodyBytes);
        return filePath;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  static Future<void> cacheTestContent({
    String title = '测试开屏',
    String subtitle = '这是一个测试内容',
    String? imagePath,
    String bgColorTop = '#4A90D9',
    String bgColorBottom = '#357ABD',
    int durationMs = 2000,
  }) => SplashServiceShared.cacheTestContent(
    title: title,
    subtitle: subtitle,
    imagePath: imagePath,
    bgColorTop: bgColorTop,
    bgColorBottom: bgColorBottom,
    durationMs: durationMs,
  );

  static Future<void> clearCachedContent() =>
      SplashServiceShared.clearCachedContent();
}
