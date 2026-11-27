import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'github_resource_service.dart';

/// 开屏配置抓取与本地偏好缓存的跨平台共享辅助逻辑（无 `dart:io` 依赖）。
class SplashServiceShared {
  const SplashServiceShared._();

  static final GitHubResourceService _resourceService = GitHubResourceService();
  static const String splashConfigUrl =
      'https://raw.githubusercontent.com/Junpgle/CountDownTodo/master/splash/config.json';

  static const String cachedContentDateKey = 'splash_cached_content_date';
  static const String cachedImagePathKey = 'splash_cached_image_path';
  static const String cachedTitleKey = 'splash_cached_title';
  static const String cachedSubtitleKey = 'splash_cached_subtitle';
  static const String cachedBgColorTopKey = 'splash_bg_color_top';
  static const String cachedBgColorBottomKey = 'splash_bg_color_bottom';
  static const String cachedDurationMsKey = 'splash_duration_ms';

  static const String prefetchedContentDateKey =
      'splash_prefetched_content_date';
  static const String prefetchedImagePathKey = 'splash_prefetched_image_path';
  static const String prefetchedTitleKey = 'splash_prefetched_title';
  static const String prefetchedSubtitleKey = 'splash_prefetched_subtitle';
  static const String prefetchedBgColorTopKey =
      'splash_prefetched_bg_color_top';
  static const String prefetchedBgColorBottomKey =
      'splash_prefetched_bg_color_bottom';
  static const String prefetchedDurationMsKey = 'splash_prefetched_duration_ms';

  static String formatDate(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '${date.year}-$month-$day';
  }

  static Future<Map<String, dynamic>?> fetchConfig() async {
    try {
      final response = await _resourceService.get(Uri.parse(splashConfigUrl));
      if (response.statusCode == 200) {
        return (jsonDecode(response.body) as Map).cast<String, dynamic>();
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  static Map<String, dynamic>? readCachedBlock(
    SharedPreferences prefs, {
    required String dateKey,
    required String imageKey,
    required String titleKey,
    required String subtitleKey,
    required String bgTopKey,
    required String bgBottomKey,
    required String durationKey,
    required String expectedDate,
    bool Function(String imagePath)? imageExists,
  }) {
    if (prefs.getString(dateKey) != expectedDate) return null;

    final title = prefs.getString(titleKey);
    if (title == null || title.isEmpty) return null;

    final imagePath = prefs.getString(imageKey);
    if (imagePath == null || imagePath.isEmpty) return null;
    if (imageExists != null && !imageExists(imagePath)) return null;

    return {
      'title': title,
      'subtitle': prefs.getString(subtitleKey) ?? '',
      'imagePath': imagePath,
      'bgColorTop': prefs.getString(bgTopKey),
      'bgColorBottom': prefs.getString(bgBottomKey),
      'durationMs': prefs.getInt(durationKey) ?? 500,
    };
  }

  static Future<void> storeDayContent(
    SharedPreferences prefs, {
    required String dateStr,
    required Map<String, dynamic> dayConfig,
    required String? resolvedImagePath,
    required String dateKey,
    required String imageKey,
    required String titleKey,
    required String subtitleKey,
    required String bgTopKey,
    required String bgBottomKey,
    required String durationKey,
  }) async {
    await prefs.setString(dateKey, dateStr);
    if (resolvedImagePath != null && resolvedImagePath.isNotEmpty) {
      await prefs.setString(imageKey, resolvedImagePath);
    } else {
      await prefs.remove(imageKey);
    }
    await prefs.setString(titleKey, dayConfig['title']?.toString() ?? '');
    await prefs.setString(subtitleKey, dayConfig['subtitle']?.toString() ?? '');
    if (dayConfig['bg_color_top'] != null) {
      await prefs.setString(bgTopKey, dayConfig['bg_color_top'].toString());
    }
    if (dayConfig['bg_color_bottom'] != null) {
      await prefs.setString(
        bgBottomKey,
        dayConfig['bg_color_bottom'].toString(),
      );
    }
    final duration = int.tryParse(dayConfig['duration_ms']?.toString() ?? '');
    if (duration != null) {
      await prefs.setInt(durationKey, duration);
    }
  }

  static Future<Map<String, dynamic>?> getCachedContent({
    bool Function(String imagePath)? imageExists,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final todayStr = formatDate(DateTime.now());

    final current = readCachedBlock(
      prefs,
      dateKey: cachedContentDateKey,
      imageKey: cachedImagePathKey,
      titleKey: cachedTitleKey,
      subtitleKey: cachedSubtitleKey,
      bgTopKey: cachedBgColorTopKey,
      bgBottomKey: cachedBgColorBottomKey,
      durationKey: cachedDurationMsKey,
      expectedDate: todayStr,
      imageExists: imageExists,
    );
    if (current != null) return current;

    final prefetched = readCachedBlock(
      prefs,
      dateKey: prefetchedContentDateKey,
      imageKey: prefetchedImagePathKey,
      titleKey: prefetchedTitleKey,
      subtitleKey: prefetchedSubtitleKey,
      bgTopKey: prefetchedBgColorTopKey,
      bgBottomKey: prefetchedBgColorBottomKey,
      durationKey: prefetchedDurationMsKey,
      expectedDate: todayStr,
      imageExists: imageExists,
    );
    if (prefetched == null) return null;

    await prefs.setString(cachedContentDateKey, todayStr);
    await prefs.setString(
      cachedImagePathKey,
      prefetched['imagePath'] as String,
    );
    await prefs.setString(cachedTitleKey, prefetched['title'] as String);
    await prefs.setString(cachedSubtitleKey, prefetched['subtitle'] as String);
    final bgTop = prefetched['bgColorTop'] as String?;
    final bgBottom = prefetched['bgColorBottom'] as String?;
    if (bgTop != null) await prefs.setString(cachedBgColorTopKey, bgTop);
    if (bgBottom != null) {
      await prefs.setString(cachedBgColorBottomKey, bgBottom);
    }
    await prefs.setInt(cachedDurationMsKey, prefetched['durationMs'] as int);
    return prefetched;
  }

  static Future<void> cacheTestContent({
    String title = '测试开屏',
    String subtitle = '这是一个测试内容',
    String? imagePath,
    String bgColorTop = '#4A90D9',
    String bgColorBottom = '#357ABD',
    int durationMs = 2000,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(cachedContentDateKey, formatDate(DateTime.now()));
    await prefs.setString(cachedTitleKey, title);
    await prefs.setString(cachedSubtitleKey, subtitle);
    if (imagePath != null && imagePath.isNotEmpty) {
      await prefs.setString(cachedImagePathKey, imagePath);
    } else {
      await prefs.remove(cachedImagePathKey);
    }
    await prefs.setString(cachedBgColorTopKey, bgColorTop);
    await prefs.setString(cachedBgColorBottomKey, bgColorBottom);
    await prefs.setInt(cachedDurationMsKey, durationMs);
  }

  static Future<void> clearCachedContent() async {
    final prefs = await SharedPreferences.getInstance();
    for (final key in [
      cachedContentDateKey,
      cachedTitleKey,
      cachedSubtitleKey,
      cachedImagePathKey,
      cachedBgColorTopKey,
      cachedBgColorBottomKey,
      cachedDurationMsKey,
      prefetchedContentDateKey,
      prefetchedImagePathKey,
      prefetchedTitleKey,
      prefetchedSubtitleKey,
      prefetchedBgColorTopKey,
      prefetchedBgColorBottomKey,
      prefetchedDurationMsKey,
    ]) {
      await prefs.remove(key);
    }
  }
}
