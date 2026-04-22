import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SplashService {
  static const String splashConfigUrl =
      'https://raw.githubusercontent.com/Junpgle/CountDownTodo/master/splash/config.json';

  static const String _cachedContentDateKey = 'splash_cached_content_date';
  static const String _cachedImagePath = 'splash_cached_image_path';
  static const String _cachedTitle = 'splash_cached_title';
  static const String _cachedSubtitle = 'splash_cached_subtitle';
  static const String _cachedBgColorTop = 'splash_bg_color_top';
  static const String _cachedBgColorBottom = 'splash_bg_color_bottom';
  static const String _cachedDurationMs = 'splash_duration_ms';

  static const String _prefetchedContentDateKey = 'splash_prefetched_content_date';
  static const String _prefetchedImagePath = 'splash_prefetched_image_path';
  static const String _prefetchedTitle = 'splash_prefetched_title';
  static const String _prefetchedSubtitle = 'splash_prefetched_subtitle';
  static const String _prefetchedBgColorTop = 'splash_prefetched_bg_color_top';
  static const String _prefetchedBgColorBottom = 'splash_prefetched_bg_color_bottom';
  static const String _prefetchedDurationMs = 'splash_prefetched_duration_ms';

  static Future<void> prefetchTomorrowContent() async {
    try {
      final today = DateTime.now();
      final tomorrow = DateTime(today.year, today.month, today.day + 1);
      final tomorrowStr = _formatDate(tomorrow);

      final prefs = await SharedPreferences.getInstance();
      final prefetchedDate = prefs.getString(_prefetchedContentDateKey);
      if (prefetchedDate == tomorrowStr) return;

      final config = await _fetchConfig();
      if (config == null) return;

      final Map<String, dynamic>? dayConfig = config[tomorrowStr];
      if (dayConfig == null) {
        debugPrint('[Splash] 明天 ($tomorrowStr) 暂无开屏内容');
        return;
      }

      String? localImagePath;
      final imageUrl = dayConfig['image_url'];
      if (imageUrl != null && imageUrl.isNotEmpty) {
        localImagePath = await _downloadImage(imageUrl);
      }

      await prefs.setString(_prefetchedContentDateKey, tomorrowStr);
      if (localImagePath != null) {
        await prefs.setString(_prefetchedImagePath, localImagePath);
      } else {
        await prefs.remove(_prefetchedImagePath);
      }
      await prefs.setString(_prefetchedTitle, dayConfig['title'] ?? '');
      await prefs.setString(_prefetchedSubtitle, dayConfig['subtitle'] ?? '');
      if (dayConfig['bg_color_top'] != null) {
        await prefs.setString(_prefetchedBgColorTop, dayConfig['bg_color_top']);
      }
      if (dayConfig['bg_color_bottom'] != null) {
        await prefs.setString(
            _prefetchedBgColorBottom, dayConfig['bg_color_bottom']);
      }
      if (dayConfig['duration_ms'] != null) {
        await prefs.setInt(_prefetchedDurationMs, dayConfig['duration_ms'] as int);
      }

    } catch (e) {
      debugPrint('[Splash] 预取失败: $e');
    }
  }

  static Future<void> fetchAndCacheTodayContent() async {
    try {
      final today = DateTime.now();
      final todayStr = _formatDate(today);

      final prefs = await SharedPreferences.getInstance();
      final cachedDate = prefs.getString(_cachedContentDateKey);
      if (cachedDate == todayStr) return;

      final config = await _fetchConfig();
      if (config == null) return;

      final Map<String, dynamic>? dayConfig = config[todayStr];
      if (dayConfig == null) {
        debugPrint('[Splash] 今天 ($todayStr) 暂无开屏内容');
        return;
      }

      String? localImagePath;
      final imageUrl = dayConfig['image_url'];
      if (imageUrl != null && imageUrl.isNotEmpty) {
        localImagePath = await _downloadImage(imageUrl);
      }

      await prefs.setString(_cachedContentDateKey, todayStr);
      if (localImagePath != null) {
        await prefs.setString(_cachedImagePath, localImagePath);
      } else {
        await prefs.remove(_cachedImagePath);
      }
      await prefs.setString(_cachedTitle, dayConfig['title'] ?? '');
      await prefs.setString(_cachedSubtitle, dayConfig['subtitle'] ?? '');
      if (dayConfig['bg_color_top'] != null) {
        await prefs.setString(_cachedBgColorTop, dayConfig['bg_color_top']);
      }
      if (dayConfig['bg_color_bottom'] != null) {
        await prefs.setString(
            _cachedBgColorBottom, dayConfig['bg_color_bottom']);
      }
      if (dayConfig['duration_ms'] != null) {
        await prefs.setInt(_cachedDurationMs, dayConfig['duration_ms'] as int);
      }

    } catch (e) {
      debugPrint('[Splash] 获取今天内容失败: $e');
    }
  }

  static Future<Map<String, dynamic>?> getCachedContent() async {
    final prefs = await SharedPreferences.getInstance();
    final today = DateTime.now();
    final todayStr = _formatDate(today);

    final current = _readCachedBlock(
      prefs,
      dateKey: _cachedContentDateKey,
      imageKey: _cachedImagePath,
      titleKey: _cachedTitle,
      subtitleKey: _cachedSubtitle,
      bgTopKey: _cachedBgColorTop,
      bgBottomKey: _cachedBgColorBottom,
      durationKey: _cachedDurationMs,
      expectedDate: todayStr,
    );
    if (current != null) return current;

    final prefetched = _readCachedBlock(
      prefs,
      dateKey: _prefetchedContentDateKey,
      imageKey: _prefetchedImagePath,
      titleKey: _prefetchedTitle,
      subtitleKey: _prefetchedSubtitle,
      bgTopKey: _prefetchedBgColorTop,
      bgBottomKey: _prefetchedBgColorBottom,
      durationKey: _prefetchedDurationMs,
      expectedDate: todayStr,
    );
    if (prefetched != null) {
      // 把“昨天预取、今天生效”的内容提升为当前缓存，确保下次启动稳定命中。
      await prefs.setString(_cachedContentDateKey, todayStr);
      await prefs.setString(_cachedImagePath, prefetched['imagePath'] as String);
      await prefs.setString(_cachedTitle, prefetched['title'] as String);
      await prefs.setString(_cachedSubtitle, prefetched['subtitle'] as String);
      final bgTop = prefetched['bgColorTop'] as String?;
      final bgBottom = prefetched['bgColorBottom'] as String?;
      final durationMs = prefetched['durationMs'] as int;
      if (bgTop != null) await prefs.setString(_cachedBgColorTop, bgTop);
      if (bgBottom != null) await prefs.setString(_cachedBgColorBottom, bgBottom);
      await prefs.setInt(_cachedDurationMs, durationMs);
      return prefetched;
    }

    return null;
  }

  static Map<String, dynamic>? _readCachedBlock(
    SharedPreferences prefs, {
    required String dateKey,
    required String imageKey,
    required String titleKey,
    required String subtitleKey,
    required String bgTopKey,
    required String bgBottomKey,
    required String durationKey,
    required String expectedDate,
  }) {
    final cachedDate = prefs.getString(dateKey);
    if (cachedDate != expectedDate) return null;

    final title = prefs.getString(titleKey);
    if (title == null || title.isEmpty) return null;

    final imagePath = prefs.getString(imageKey);
    if (imagePath == null || imagePath.isEmpty) return null;
    if (!File(imagePath).existsSync()) return null;

    return {
      'title': title,
      'subtitle': prefs.getString(subtitleKey) ?? '',
      'imagePath': imagePath,
      'bgColorTop': prefs.getString(bgTopKey),
      'bgColorBottom': prefs.getString(bgBottomKey),
      'durationMs': prefs.getInt(durationKey) ?? 500,
    };
  }

  static Future<Map<String, dynamic>?> _fetchConfig() async {
    try {
      final response = await http.get(Uri.parse(splashConfigUrl));
      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
      return null;
    } catch (e) {
      debugPrint('[Splash] 获取配置失败: $e');
      return null;
    }
  }

  static Future<String?> _downloadImage(String url) async {
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final dir = await getApplicationCacheDirectory();
        final filePath =
            '${dir.path}/splash_image_${DateTime.now().millisecondsSinceEpoch}.png';
        final file = File(filePath);
        await file.writeAsBytes(response.bodyBytes);
        return filePath;
      }
      return null;
    } catch (e) {
      debugPrint('[Splash] 图片下载失败: $e');
      return null;
    }
  }

  static String _formatDate(DateTime date) {
    return '${date.year}-${_twoDigits(date.month)}-${_twoDigits(date.day)}';
  }

  static String _twoDigits(int n) => n.toString().padLeft(2, '0');

  static Future<void> cacheTestContent({
    String title = '测试开屏',
    String subtitle = '这是一个测试内容',
    String? imagePath,
    String bgColorTop = '#4A90D9',
    String bgColorBottom = '#357ABD',
    int durationMs = 2000,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final today = DateTime.now();
    final todayStr = _formatDate(today);

    await prefs.setString(_cachedContentDateKey, todayStr);
    await prefs.setString(_cachedTitle, title);
    await prefs.setString(_cachedSubtitle, subtitle);
    if (imagePath != null) {
      await prefs.setString(_cachedImagePath, imagePath);
    } else {
      await prefs.remove(_cachedImagePath);
    }
    await prefs.setString(_cachedBgColorTop, bgColorTop);
    await prefs.setString(_cachedBgColorBottom, bgColorBottom);
    await prefs.setInt(_cachedDurationMs, durationMs);
  }

  static Future<void> clearCachedContent() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_cachedContentDateKey);
    await prefs.remove(_cachedTitle);
    await prefs.remove(_cachedSubtitle);
    await prefs.remove(_cachedImagePath);
    await prefs.remove(_cachedBgColorTop);
    await prefs.remove(_cachedBgColorBottom);
    await prefs.remove(_cachedDurationMs);
    await prefs.remove(_prefetchedContentDateKey);
    await prefs.remove(_prefetchedImagePath);
    await prefs.remove(_prefetchedTitle);
    await prefs.remove(_prefetchedSubtitle);
    await prefs.remove(_prefetchedBgColorTop);
    await prefs.remove(_prefetchedBgColorBottom);
    await prefs.remove(_prefetchedDurationMs);
  }
}
