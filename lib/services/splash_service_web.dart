import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
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

  static const String _prefetchedContentDateKey =
      'splash_prefetched_content_date';
  static const String _prefetchedImagePath = 'splash_prefetched_image_path';
  static const String _prefetchedTitle = 'splash_prefetched_title';
  static const String _prefetchedSubtitle = 'splash_prefetched_subtitle';
  static const String _prefetchedBgColorTop = 'splash_prefetched_bg_color_top';
  static const String _prefetchedBgColorBottom =
      'splash_prefetched_bg_color_bottom';
  static const String _prefetchedDurationMs = 'splash_prefetched_duration_ms';

  static Future<void> prefetchTomorrowContent() async {
    try {
      final today = DateTime.now();
      final tomorrow = DateTime(today.year, today.month, today.day + 1);
      await _fetchAndStore(
        date: tomorrow,
        dateKey: _prefetchedContentDateKey,
        imageKey: _prefetchedImagePath,
        titleKey: _prefetchedTitle,
        subtitleKey: _prefetchedSubtitle,
        bgTopKey: _prefetchedBgColorTop,
        bgBottomKey: _prefetchedBgColorBottom,
        durationKey: _prefetchedDurationMs,
      );
    } catch (e) {
      debugPrint('[Splash] Web prefetch failed: $e');
    }
  }

  static Future<void> fetchAndCacheTodayContent() async {
    try {
      final today = DateTime.now();
      await _fetchAndStore(
        date: today,
        dateKey: _cachedContentDateKey,
        imageKey: _cachedImagePath,
        titleKey: _cachedTitle,
        subtitleKey: _cachedSubtitle,
        bgTopKey: _cachedBgColorTop,
        bgBottomKey: _cachedBgColorBottom,
        durationKey: _cachedDurationMs,
      );
    } catch (e) {
      debugPrint('[Splash] Web fetch failed: $e');
    }
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
    final dateStr = _formatDate(date);
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getString(dateKey) == dateStr) return;

    final config = await _fetchConfig();
    final dayConfig = config?[dateStr] as Map<String, dynamic>?;
    if (dayConfig == null) return;

    final imageUrl = dayConfig['image_url']?.toString();
    await prefs.setString(dateKey, dateStr);
    if (imageUrl != null && imageUrl.isNotEmpty) {
      await prefs.setString(imageKey, imageUrl);
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
          bgBottomKey, dayConfig['bg_color_bottom'].toString());
    }
    final duration = int.tryParse(dayConfig['duration_ms']?.toString() ?? '');
    if (duration != null) {
      await prefs.setInt(durationKey, duration);
    }
  }

  static Future<Map<String, dynamic>?> getCachedContent() async {
    final prefs = await SharedPreferences.getInstance();
    final todayStr = _formatDate(DateTime.now());

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
    if (prefetched == null) return null;

    await prefs.setString(_cachedContentDateKey, todayStr);
    await prefs.setString(_cachedImagePath, prefetched['imagePath'] as String);
    await prefs.setString(_cachedTitle, prefetched['title'] as String);
    await prefs.setString(_cachedSubtitle, prefetched['subtitle'] as String);
    final bgTop = prefetched['bgColorTop'] as String?;
    final bgBottom = prefetched['bgColorBottom'] as String?;
    if (bgTop != null) await prefs.setString(_cachedBgColorTop, bgTop);
    if (bgBottom != null) await prefs.setString(_cachedBgColorBottom, bgBottom);
    await prefs.setInt(_cachedDurationMs, prefetched['durationMs'] as int);
    return prefetched;
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
    if (prefs.getString(dateKey) != expectedDate) return null;

    final title = prefs.getString(titleKey);
    final imagePath = prefs.getString(imageKey);
    if (title == null || title.isEmpty) return null;
    if (imagePath == null || imagePath.isEmpty) return null;

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
        return (jsonDecode(response.body) as Map).cast<String, dynamic>();
      }
    } catch (_) {}
    return null;
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
    await prefs.setString(_cachedContentDateKey, _formatDate(DateTime.now()));
    await prefs.setString(_cachedTitle, title);
    await prefs.setString(_cachedSubtitle, subtitle);
    if (imagePath != null && imagePath.isNotEmpty) {
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
    for (final key in [
      _cachedContentDateKey,
      _cachedTitle,
      _cachedSubtitle,
      _cachedImagePath,
      _cachedBgColorTop,
      _cachedBgColorBottom,
      _cachedDurationMs,
      _prefetchedContentDateKey,
      _prefetchedImagePath,
      _prefetchedTitle,
      _prefetchedSubtitle,
      _prefetchedBgColorTop,
      _prefetchedBgColorBottom,
      _prefetchedDurationMs,
    ]) {
      await prefs.remove(key);
    }
  }
}
