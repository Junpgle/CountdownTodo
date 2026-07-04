import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppSettingsStorage {
  const AppSettingsStorage._();

  static const String _notifyLiveEnabled = "notify_live_activity_enabled";
  static const String _notifyNormalEnabled = "notify_normal_enabled";
  static const String _notifyCourseEnabled = "notify_course_enabled";
  static const String _notifyQuizEnabled = "notify_quiz_enabled";
  static const String _notifyTodoSummaryEnabled = "notify_todo_summary_enabled";
  static const String _notifySpecialTodoEnabled = "notify_special_todo_enabled";
  static const String _notifyPomodoroEnabled = "notify_pomodoro_enabled";
  static const String _notifyTodoRecognizeEnabled =
      "notify_todo_recognize_enabled";
  static const String _notifyPomodoroEndEnabled = "notify_pomodoro_end_enabled";
  static const String _notifyTodoLiveEnabled = "notify_todo_live_enabled";
  static const String _notifyReminderEnabled = "notify_reminder_enabled";
  static const String _courseReminderMinutes = "course_reminder_minutes";

  static const String _privacyAgreed = "privacy_policy_agreed";
  static const String _privacyDate = "privacy_policy_date";
  static const String _privacyCachedVersion = "privacy_policy_cached_version";
  static const String _privacyCacheTime = "privacy_policy_cache_time";
  static const String _privacyRawUrl =
      'https://raw.githubusercontent.com/Junpgle/CountdownTodo/refs/heads/master/PRIVACY_POLICY.md';
  static const Duration _privacyCacheDuration = Duration(hours: 1);

  static const String _wallpaperProvider = "app_wallpaper_provider";
  static const String _wallpaperImageFormat = "app_wallpaper_image_format";
  static const String _wallpaperIndex = "app_wallpaper_index";
  static const String _wallpaperMkt = "app_wallpaper_mkt";
  static const String _wallpaperResolution = "app_wallpaper_resolution";
  static const String _wallpaperCacheCleanupTime =
      "app_wallpaper_cache_cleanup_time";
  static const String _wallpaperCustomPath = "app_wallpaper_custom_path";

  static const String _todoFoldersInline = "todo_folders_inline";
  static const String _todoFolderDisplayMode = "todo_folder_display_mode";
  static const String _lastCourseImportUrl = "last_course_import_url";
  static const String _categoryReminderMinutes = "category_reminder_minutes";

  static Future<SharedPreferences> get _prefs =>
      SharedPreferences.getInstance();

  static Future<bool> isLiveActivityNotificationEnabled() async {
    final prefs = await _prefs;
    return prefs.getBool(_notifyLiveEnabled) ?? true;
  }

  static Future<void> setLiveActivityNotificationEnabled(bool enabled) async {
    final prefs = await _prefs;
    await prefs.setBool(_notifyLiveEnabled, enabled);
  }

  static Future<bool> isNormalNotificationEnabled() async {
    final prefs = await _prefs;
    return prefs.getBool(_notifyNormalEnabled) ?? true;
  }

  static Future<void> setNormalNotificationEnabled(bool enabled) async {
    final prefs = await _prefs;
    await prefs.setBool(_notifyNormalEnabled, enabled);
  }

  static Future<bool> isCourseNotificationEnabled() async {
    final prefs = await _prefs;
    return prefs.getBool(_notifyCourseEnabled) ?? true;
  }

  static Future<void> setCourseNotificationEnabled(bool enabled) async {
    final prefs = await _prefs;
    await prefs.setBool(_notifyCourseEnabled, enabled);
  }

  static Future<bool> isQuizNotificationEnabled() async {
    final prefs = await _prefs;
    return prefs.getBool(_notifyQuizEnabled) ?? true;
  }

  static Future<void> setQuizNotificationEnabled(bool enabled) async {
    final prefs = await _prefs;
    await prefs.setBool(_notifyQuizEnabled, enabled);
  }

  static Future<bool> isTodoSummaryNotificationEnabled() async {
    final prefs = await _prefs;
    return prefs.getBool(_notifyTodoSummaryEnabled) ?? true;
  }

  static Future<void> setTodoSummaryNotificationEnabled(bool enabled) async {
    final prefs = await _prefs;
    await prefs.setBool(_notifyTodoSummaryEnabled, enabled);
  }

  static Future<bool> isSpecialTodoNotificationEnabled() async {
    final prefs = await _prefs;
    return prefs.getBool(_notifySpecialTodoEnabled) ?? true;
  }

  static Future<void> setSpecialTodoNotificationEnabled(bool enabled) async {
    final prefs = await _prefs;
    await prefs.setBool(_notifySpecialTodoEnabled, enabled);
  }

  static Future<bool> isPomodoroNotificationEnabled() async {
    final prefs = await _prefs;
    return prefs.getBool(_notifyPomodoroEnabled) ?? true;
  }

  static Future<void> setPomodoroNotificationEnabled(bool enabled) async {
    final prefs = await _prefs;
    await prefs.setBool(_notifyPomodoroEnabled, enabled);
  }

  static Future<bool> isTodoRecognizeNotificationEnabled() async {
    final prefs = await _prefs;
    return prefs.getBool(_notifyTodoRecognizeEnabled) ?? true;
  }

  static Future<void> setTodoRecognizeNotificationEnabled(bool enabled) async {
    final prefs = await _prefs;
    await prefs.setBool(_notifyTodoRecognizeEnabled, enabled);
  }

  static Future<bool> isTodoLiveNotificationEnabled() async {
    final prefs = await _prefs;
    return prefs.getBool(_notifyTodoLiveEnabled) ?? true;
  }

  static Future<void> setTodoLiveNotificationEnabled(bool enabled) async {
    final prefs = await _prefs;
    await prefs.setBool(_notifyTodoLiveEnabled, enabled);
  }

  static Future<bool> isPomodoroEndNotificationEnabled() async {
    final prefs = await _prefs;
    return prefs.getBool(_notifyPomodoroEndEnabled) ?? true;
  }

  static Future<void> setPomodoroEndNotificationEnabled(bool enabled) async {
    final prefs = await _prefs;
    await prefs.setBool(_notifyPomodoroEndEnabled, enabled);
  }

  static Future<bool> isReminderNotificationEnabled() async {
    final prefs = await _prefs;
    return prefs.getBool(_notifyReminderEnabled) ?? true;
  }

  static Future<void> setReminderNotificationEnabled(bool enabled) async {
    final prefs = await _prefs;
    await prefs.setBool(_notifyReminderEnabled, enabled);
  }

  static Future<int> getCourseReminderMinutes() async {
    final prefs = await _prefs;
    return prefs.getInt(_courseReminderMinutes) ?? 15;
  }

  static Future<void> setCourseReminderMinutes(int minutes) async {
    final prefs = await _prefs;
    await prefs.setInt(_courseReminderMinutes, minutes);
  }

  static Future<bool> isPrivacyPolicyAgreed() async {
    final prefs = await _prefs;
    return prefs.getBool(_privacyAgreed) ?? false;
  }

  static Future<void> setPrivacyPolicyAgreed(bool agreed,
      {String? date}) async {
    final prefs = await _prefs;
    await prefs.setBool(_privacyAgreed, agreed);
    if (agreed) {
      final versionDate = date ?? await _getPrivacyPolicyCurrentVersion();
      await prefs.setString(_privacyDate, versionDate);
    }
  }

  static Future<bool> isPrivacyPolicyUpToDate() async {
    final prefs = await _prefs;
    final storedDate = prefs.getString(_privacyDate);
    if (storedDate == null) return false;

    final cachedVersion = prefs.getString(_privacyCachedVersion);
    final cacheTime = prefs.getInt(_privacyCacheTime) ?? 0;
    final now = DateTime.now().millisecondsSinceEpoch;

    if (cachedVersion == null ||
        now - cacheTime >= _privacyCacheDuration.inMilliseconds) {
      _getPrivacyPolicyCurrentVersion();
    }

    if (cachedVersion != null) {
      return _compareDates(storedDate, cachedVersion) >= 0;
    }
    return true;
  }

  static Future<String> _getPrivacyPolicyCurrentVersion() async {
    final prefs = await _prefs;
    final cachedVersion = prefs.getString(_privacyCachedVersion);
    final cacheTime = prefs.getInt(_privacyCacheTime) ?? 0;
    final now = DateTime.now().millisecondsSinceEpoch;

    if (cachedVersion != null &&
        now - cacheTime < _privacyCacheDuration.inMilliseconds) {
//       debugPrint('[Privacy] Using cached version: $cachedVersion');
      return cachedVersion;
    }

    try {
      final response = await http
          .get(Uri.parse(_privacyRawUrl))
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final version = _extractPrivacyVersionDate(response.body);
        if (version.isNotEmpty) {
          await prefs.setString(_privacyCachedVersion, version);
          await prefs.setInt(_privacyCacheTime, now);
//           debugPrint('[Privacy] Updated version: $version');
          return version;
        }
      }
    } catch (_) {}

    if (cachedVersion != null) return cachedVersion;
    return DateFormat('yyyy-MM-dd').format(DateTime.now());
  }

  static String _extractPrivacyVersionDate(String content) {
    try {
      final pattern1 = RegExp(r'版本日期[：:]?\s*(\d{4})年(\d{1,2})月(\d{1,2})日');
      final match1 = pattern1.firstMatch(content);
      if (match1 != null) {
        final year = match1.group(1)!;
        final month = match1.group(2)!.padLeft(2, '0');
        final day = match1.group(3)!.padLeft(2, '0');
        return '$year-$month-$day';
      }

      final pattern2 = RegExp(r'版本日期[：:]?\s*(\d{4}-\d{2}-\d{2})');
      final match2 = pattern2.firstMatch(content);
      if (match2 != null) return match2.group(1)!;

//       debugPrint('[Privacy] Could not extract version date from content');
      return '';
    } catch (e) {
//       debugPrint('[Privacy] Error extracting version date: $e');
      return '';
    }
  }

  static int _compareDates(String a, String b) {
    try {
      final dateA = DateTime.parse(a);
      final dateB = DateTime.parse(b);
      return dateA.compareTo(dateB);
    } catch (_) {
      return a.compareTo(b);
    }
  }

  static Future<void> withdrawPrivacyAgreement() async {
    final prefs = await _prefs;
    await prefs.remove(_privacyAgreed);
    await prefs.remove(_privacyDate);
  }

  static Future<String> getWallpaperProvider() async {
    final prefs = await _prefs;
    return prefs.getString(_wallpaperProvider) ?? 'bing';
  }

  static Future<void> saveWallpaperProvider(String provider) async {
    final prefs = await _prefs;
    await prefs.setString(_wallpaperProvider, provider);
  }

  static Future<String> getWallpaperImageFormat() async {
    final prefs = await _prefs;
    return prefs.getString(_wallpaperImageFormat) ?? 'jpg';
  }

  static Future<void> saveWallpaperImageFormat(String format) async {
    final prefs = await _prefs;
    await prefs.setString(_wallpaperImageFormat, format);
  }

  static Future<int> getWallpaperIndex() async {
    final prefs = await _prefs;
    return prefs.getInt(_wallpaperIndex) ?? 0;
  }

  static Future<void> saveWallpaperIndex(int index) async {
    final prefs = await _prefs;
    await prefs.setInt(_wallpaperIndex, index);
  }

  static Future<String> getWallpaperMkt() async {
    final prefs = await _prefs;
    return prefs.getString(_wallpaperMkt) ?? 'zh-CN';
  }

  static Future<void> saveWallpaperMkt(String mkt) async {
    final prefs = await _prefs;
    await prefs.setString(_wallpaperMkt, mkt);
  }

  static Future<String> getWallpaperResolution() async {
    final prefs = await _prefs;
    return prefs.getString(_wallpaperResolution) ?? '1920';
  }

  static Future<void> saveWallpaperResolution(String resolution) async {
    final prefs = await _prefs;
    await prefs.setString(_wallpaperResolution, resolution);
  }

  static Future<int?> getWallpaperCacheCleanupTime() async {
    final prefs = await _prefs;
    return prefs.getInt(_wallpaperCacheCleanupTime);
  }

  static Future<void> saveWallpaperCacheCleanupTime(int timestamp) async {
    final prefs = await _prefs;
    await prefs.setInt(_wallpaperCacheCleanupTime, timestamp);
  }

  static Future<String?> getWallpaperCustomPath() async {
    final prefs = await _prefs;
    return prefs.getString(_wallpaperCustomPath);
  }

  static Future<void> saveWallpaperCustomPath(String path) async {
    final prefs = await _prefs;
    await prefs.setString(_wallpaperCustomPath, path);
  }

  static Future<void> clearWallpaperCustomPath() async {
    final prefs = await _prefs;
    await prefs.remove(_wallpaperCustomPath);
  }

  static Future<bool> getTodoFoldersInline() async {
    final prefs = await _prefs;
    return prefs.getBool(_todoFoldersInline) ?? true;
  }

  static Future<void> setTodoFoldersInline(bool inline) async {
    final prefs = await _prefs;
    await prefs.setBool(_todoFoldersInline, inline);
  }

  static Future<String> getTodoFolderDisplayMode() async {
    final prefs = await _prefs;
    final mode = prefs.getString(_todoFolderDisplayMode);
    if (mode != null && mode.isNotEmpty) return mode;
    return (prefs.getBool(_todoFoldersInline) ?? true) ? 'inline' : 'separate';
  }

  static Future<void> setTodoFolderDisplayMode(String mode) async {
    final prefs = await _prefs;
    await prefs.setString(_todoFolderDisplayMode, mode);
    await prefs.setBool(_todoFoldersInline, mode != 'separate');
  }

  static Future<void> saveLastCourseImportUrl(String url) async {
    final prefs = await _prefs;
    await prefs.setString(_lastCourseImportUrl, url);
  }

  static Future<String?> getLastCourseImportUrl() async {
    final prefs = await _prefs;
    return prefs.getString(_lastCourseImportUrl);
  }

  static Future<Map<String, int>> getCategoryReminderMinutes(
      String username) async {
    final prefs = await _prefs;
    final jsonStr = prefs.getString("${_categoryReminderMinutes}_$username");
    if (jsonStr == null) return {};
    try {
      final Map<String, dynamic> rawResult = jsonDecode(jsonStr);
      return rawResult.map((key, value) => MapEntry(key, value as int));
    } catch (_) {
      return {};
    }
  }

  static Future<void> saveCategoryReminderMinutes(
      String username, Map<String, int> data) async {
    final prefs = await _prefs;
    await prefs.setString(
        "${_categoryReminderMinutes}_$username", jsonEncode(data));
  }
}
