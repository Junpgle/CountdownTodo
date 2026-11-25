import 'package:shared_preferences/shared_preferences.dart';

import 'splash_service_shared.dart';

class SplashService {
  static const String splashConfigUrl = SplashServiceShared.splashConfigUrl;

  static Future<void> prefetchTomorrowContent() async {
    try {
      final today = DateTime.now();
      final tomorrow = DateTime(today.year, today.month, today.day + 1);
      await _fetchAndStore(
        date: tomorrow,
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
      await _fetchAndStore(
        date: DateTime.now(),
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

  static Future<void> _fetchAndStore({
    required DateTime date,
    required String dateKey,
    required String imageKey,
    required String titleKey,
    required String subtitleKey,
    required String bgTopKey,
    required String bgBottomKey,
    required String durationKey,
  }) async {
    final dateStr = SplashServiceShared.formatDate(date);
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getString(dateKey) == dateStr) return;

    final config = await SplashServiceShared.fetchConfig();
    final dayConfig = config?[dateStr] as Map<String, dynamic>?;
    if (dayConfig == null) return;

    await SplashServiceShared.storeDayContent(
      prefs,
      dateStr: dateStr,
      dayConfig: dayConfig,
      resolvedImagePath: dayConfig['image_url']?.toString(),
      dateKey: dateKey,
      imageKey: imageKey,
      titleKey: titleKey,
      subtitleKey: subtitleKey,
      bgTopKey: bgTopKey,
      bgBottomKey: bgBottomKey,
      durationKey: durationKey,
    );
  }

  static Future<Map<String, dynamic>?> getCachedContent() =>
      SplashServiceShared.getCachedContent();

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
