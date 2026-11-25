import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:countdown_todo/services/band_sync_service.dart';
import 'package:countdown_todo/services/notification_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show MethodChannel, rootBundle;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_file/open_file.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'services/android_delta_service.dart';
import 'services/api_service.dart';
import 'services/permission_request_coordinator.dart';
import 'services/github_resource_service.dart';
import './utils/app_dialogs.dart';

// 数据模型类

part 'update_service_io_models.dart';
part 'update_service_io_manifest.dart';
part 'update_service_io_download.dart';
part 'update_service_io_dialogs.dart';

class UpdateService {
  static final GitHubResourceService _resourceService = GitHubResourceService();
  static final RegExp _announcementUnixMillisecondsPattern = RegExp(
    r'(1\d{12})',
  );
  static final RegExp _announcementUnixSecondsPattern = RegExp(r'(1\d{9})');
  static final RegExp _announcementDateDigitsPattern = RegExp(
    r'(\d{14}|\d{12}|\d{10}|\d{8})',
  );
  static const String manifestUrl =
      "https://raw.githubusercontent.com/Junpgle/CountdownTodo/refs/heads/master/update_manifest.json";
  static String get fallbackManifestUrl {
    final baseUrl = ApiService.effectiveBaseUrl;
    final base = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    return '$base/api/manifest';
  }

  static const String changelogArchiveUrl =
      "https://raw.githubusercontent.com/Junpgle/CountdownTodo/refs/heads/master/update_changelog_archive.json";
  static const String _manifestCacheKey = 'update_manifest_cache_json';
  static const String _manifestCacheTimeKey = 'update_manifest_cache_time';
  static const String _changelogArchiveCacheKey =
      'changelog_archive_cache_json';
  static const String _changelogArchiveCacheTimeKey =
      'changelog_archive_cache_time';
  static const String _updateDialogSnoozeTodayKey =
      'update_dialog_snooze_today';
  static const String _updateMethodChannelName =
      'com.math_quiz.junpgle.com.math_quiz_app/app_update';

  // 更新源偏好设置
  static const String _updateSourceKey = 'update_source_preference';
  static const String _autoDownloadOnWifiKey = 'auto_download_updates_on_wifi';
  static const String updateSourceGithub = 'github';
  static const String updateSourceServer = 'server';

  /// 获取用户选择的更新源
  static Future<AppManifest?>? _manifestRefreshFuture;
  static Future<void>? _updateCheckFuture;
  static int? _lastManifestRefreshAttemptMs;
  static const Duration _manifestRefreshInterval = Duration(hours: 6);
  static const Duration _manifestRetryInterval = Duration(minutes: 30);

  static bool _isDialogShowing = false;
  static bool _isAnnouncementDialogShowing = false;
  static String? _lastPromptedUpdateVersion;
  static DateTime? _lastPromptedUpdateAt;

  // 全局壁纸状态管理
  static ValueNotifier<String?> wallpaperUrlNotifier = ValueNotifier<String?>(
    null,
  );
  static ValueNotifier<bool> wallpaperShowNotifier = ValueNotifier<bool>(false);
  static const String _wallpaperUrlKey = 'manifest_wallpaper_url';
  static const String _wallpaperShowKey = 'manifest_wallpaper_show';
  static const String _wallpaperLastCheckKey = 'manifest_wallpaper_last_check';
  static const Duration _wallpaperRefreshInterval = Duration(hours: 24);

  static const String _announcementReadPrefix = 'announcement_read_';

  static bool _isDownloading = false;
  static double _downloadProgress = 0.0;
  static bool _isDownloaded = false;
  static String? _localPackagePath;
  static StreamSubscription<List<int>>? _downloadSubscription;

  static Function(double)? _uiProgressCallback;
  static Function(String)? _uiCompleteCallback;
  static Function(String)? _uiErrorCallback;

  // 🚀 动态区分 Android 和 Windows 的安装包后缀
  static const List<String> supportedAndroidPackageAbis = [
    'arm64-v8a',
    'armeabi-v7a',
    'x86_64',
  ];

  static Future<String> getUpdateSource() => _updManifestGetUpdateSource();

  /// 保存用户选择的更新源
  static Future<void> setUpdateSource(String source) =>
      _updManifestSetUpdateSource(source);

  /// Whether Android may download a discovered update automatically on Wi-Fi.
  static Future<bool> getAutoDownloadOnWifi() =>
      _updManifestGetAutoDownloadOnWifi();

  static Future<void> setAutoDownloadOnWifi(bool enabled) =>
      _updManifestSetAutoDownloadOnWifi(enabled);

  /// Returns true only when Android reports that the active network is Wi-Fi.
  /// Automatic package downloads deliberately do not run on mobile data.
  static Future<bool> isWifiConnected() => _updManifestIsWifiConnected();

  /// Reads the version embedded in a downloaded Android APK.
  ///
  /// The filename is not authoritative: release URLs may be saved as
  /// `latest.apk` or use another server-provided name.
  static Future<String?> readDownloadedPackageVersion(String filePath) =>
      _updManifestReadDownloadedPackageVersion(filePath);

  static Future<void> initWallpaper() => _updManifestInitWallpaper();

  // 检查是否需要兜底刷新(超过24小时未检查)
  static Future<bool> needsWallpaperRefresh() =>
      _updManifestNeedsWallpaperRefresh();

  static Future<void> updateWallpaperFromManifest() =>
      _updManifestUpdateWallpaperFromManifest();

  /// 检查手表版本并推送给手表 (如果有连接)
  static Future<void> syncBandVersionInfo() =>
      _updManifestSyncBandVersionInfo();

  static Future<bool> isAnnouncementRead(String announcementId) =>
      _updManifestIsAnnouncementRead(announcementId);

  static Future<void> markAnnouncementAsRead(String announcementId) =>
      _updManifestMarkAnnouncementAsRead(announcementId);

  // 检查是否需要显示公告(考虑已读状态、提醒模式、目标版本)
  static bool shouldShowAnnouncement(
    Announcement announcement,
    bool isRead,
    String currentVersion,
  ) => _updManifestShouldShowAnnouncement(announcement, isRead, currentVersion);

  /// 从公告 id 中解析时间片段用于排序。
  /// 支持：
  /// - ann_YYYYMMDD_NNN（按 YYYYMMDD）
  /// - ann_YYYYMMDDHHmm / ann_YYYYMMDDHHmmss
  /// - 10/13 位 Unix 时间戳
  static int parseAnnouncementSortKey(String id) =>
      _updManifestParseAnnouncementSortKey(id);

  static List<Announcement> sortAnnouncementsByIdDesc(
    List<Announcement> items,
  ) => _updManifestSortAnnouncementsByIdDesc(items);

  /// 设置页公告：忽略已读状态，只按 show + target_versions 过滤。
  /// 返回按 id 时间片段降序后的列表，首条即最新公告。
  /// 发生网络/解析异常时返回 null，便于 UI 区分“无公告”和“加载失败”。
  static Future<List<Announcement>?> getAnnouncementsForSettings() =>
      _updManifestGetAnnouncementsForSettings();

  static Future<List<ChangelogEntry>> loadChangelogArchive({
    AppManifest? manifest,
    bool preferCache = true,
  }) => _updManifestLoadChangelogArchive(
    manifest: manifest,
    preferCache: preferCache,
  );

  /// 强制联网刷新 Manifest 缓存。
  /// 默认进行请求去重：已有进行中的请求时复用同一 Future。
  static Future<AppManifest?> refreshManifestCache({bool dedupe = true}) =>
      _updManifestRefreshManifestCache(dedupe: dedupe);

  /// 启动预热：优先确保本地有可读缓存，同时异步联网更新。
  static Future<void> preloadManifestCache() =>
      _updManifestPreloadManifestCache();

  /// Manifest 读取策略：默认优先返回本地缓存，同时后台刷新网络。
  /// [preferCache] 为 false 时将优先走网络（如手动检查更新）。
  static Future<AppManifest?> checkManifest({
    bool preferCache = true,
    bool refreshInBackground = true,
  }) => _updManifestCheckManifest(
    preferCache: preferCache,
    refreshInBackground: refreshInBackground,
  );

  @visibleForTesting
  static bool isManifestRefreshDue({
    required int nowMs,
    int? lastSuccessfulRefreshMs,
    int? lastAttemptMs,
    Duration refreshInterval = _manifestRefreshInterval,
    Duration retryInterval = _manifestRetryInterval,
  }) => _updManifestIsManifestRefreshDue(
    nowMs: nowMs,
    lastSuccessfulRefreshMs: lastSuccessfulRefreshMs,
    lastAttemptMs: lastAttemptMs,
    refreshInterval: refreshInterval,
    retryInterval: retryInterval,
  );

  static String getUpdateFileName(String versionName) =>
      _updDownloadGetUpdateFileName(versionName);

  static String selectAndroidArchitecture(Iterable<String> supportedAbis) =>
      _updDownloadSelectAndroidArchitecture(supportedAbis);

  // 🚀 获取当前设备架构
  static Future<String> getDeviceArchitecture() =>
      _updDownloadGetDeviceArchitecture();

  // 🚀 根据设备架构获取对应的下载链接
  static Future<String> getDownloadUrlForArch(AppManifest manifest) =>
      _updDownloadGetDownloadUrlForArch(manifest);

  /// Validates that an update package URL uses HTTPS with a non-empty host.
  @visibleForTesting
  static Uri validateDownloadUrl(String url) =>
      _updDownloadValidateDownloadUrl(url);

  /// Verifies [file] against [expectedSha256] when a digest is provided.
  @visibleForTesting
  static Future<void> verifyArtifactSha256(File file, String? expectedSha256) =>
      _updDownloadVerifyArtifactSha256(file, expectedSha256);

  /// Returns whether this device can build a usable incremental package for
  /// the manifest's target version. The check also verifies the installed APK
  /// hash, so the UI never offers a delta that cannot be applied locally.
  static Future<bool> hasUsableDeltaPackage(AppManifest manifest) =>
      _updDownloadHasUsableDeltaPackage(manifest);

  static Future<String?> isPackageAlreadyDownloaded(String versionName) =>
      _updDownloadIsPackageAlreadyDownloaded(versionName);

  static Future<void> clearDownloadedPackage(String filePath) =>
      _updDownloadClearDownloadedPackage(filePath);

  static Future<bool> prepareForDownload(
    BuildContext context,
    String targetVersionName,
  ) => _updDownloadPrepareForDownload(context, targetVersionName);

  static Future<String?> getDownloadDirectory() =>
      _updDownloadGetDownloadDirectory();

  static Future<void> installPackage(String filePath) =>
      _updDownloadInstallPackage(filePath);

  /// Downloads the selected update artifact and returns the generated APK.
  ///
  /// On Android, [preferDelta] selects a verified incremental package when
  /// one matches the installed APK. A failed delta application falls back to
  /// the architecture-matched full APK, so the install flow remains usable.
  static Future<void> downloadLatestPackage(
    BuildContext context,
    AppManifest manifest, {
    bool preferDelta = true,
    required void Function(double) onProgress,
    required void Function(String) onComplete,
    required void Function(String) onError,
  }) => _updDownloadDownloadLatestPackage(
    context,
    manifest,
    preferDelta: preferDelta,
    onProgress: onProgress,
    onComplete: onComplete,
    onError: onError,
  );

  /// 强制下载最新版本，忽略当前版本，下载完成后跳转安装
  static Future<void> forceDownloadLatest(
    BuildContext context, {
    required Function(double) onProgress,
    required Function(String) onComplete,
    required Function(String) onError,
  }) => _updDownloadForceDownloadLatest(
    context,
    onProgress: onProgress,
    onComplete: onComplete,
    onError: onError,
  );

  static Future<void> checkUpdateAndPrompt(
    BuildContext context, {
    bool isManual = false,
  }) => _updDialogCheckUpdateAndPrompt(context, isManual: isManual);

  // 🚀 新增：专为 WebSocket 推送设计的更新触发器，直接复用现有的弹窗和下载逻辑
  static Future<void> triggerWebSocketUpdate(
    BuildContext context, {
    required String latestVersion,
    required String releaseNotes,
    required String downloadUrl,
  }) => _updDialogTriggerWebSocketUpdate(
    context,
    latestVersion: latestVersion,
    releaseNotes: releaseNotes,
    downloadUrl: downloadUrl,
  );

  /// Starts a background package download when the update is discovered over
  /// Wi-Fi. Installation is never automatic; the update dialog exposes the
  /// completed package through an explicit install button.
  static Future<void> autoDownloadLatestOnWifi(
    BuildContext context,
    AppManifest manifest, {
    void Function(double)? onProgress,
    void Function(String)? onComplete,
    void Function(String)? onError,
  }) => _updDialogAutoDownloadLatestOnWifi(
    context,
    manifest,
    onProgress: onProgress,
    onComplete: onComplete,
    onError: onError,
  );

  static Future<void> showAnnouncementDialog(
    BuildContext context,
    List<Announcement> announcements,
    VoidCallback? onDismissed,
  ) => _updDialogShowAnnouncementDialog(context, announcements, onDismissed);

  static Future<void> showUpdateDialog(
    BuildContext context,
    AppManifest manifest,
    String currentVersion, {
    bool hasUpdate = true,
    bool hasNotice = false,
    bool respectTodaySnooze = true,
  }) => _updDialogShowUpdateDialog(
    context,
    manifest,
    currentVersion,
    hasUpdate: hasUpdate,
    hasNotice: hasNotice,
    respectTodaySnooze: respectTodaySnooze,
  );
}
