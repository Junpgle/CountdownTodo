part of 'update_service_io.dart';

Future<String> _updManifestGetUpdateSource() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getString(UpdateService._updateSourceKey) ??
      UpdateService.updateSourceGithub;
}

Future<void> _updManifestSetUpdateSource(String source) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(UpdateService._updateSourceKey, source);
}

Future<bool> _updManifestGetAutoDownloadOnWifi() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getBool(UpdateService._autoDownloadOnWifiKey) ?? true;
}

Future<void> _updManifestSetAutoDownloadOnWifi(bool enabled) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool(UpdateService._autoDownloadOnWifiKey, enabled);
  if (Platform.isAndroid) {
    try {
      await const MethodChannel(UpdateService._updateMethodChannelName)
          .invokeMethod<void>('UpdateService.setAutoDownloadOnWifi', enabled);
    } catch (error) {
      debugPrint('[UpdateService] 同步 Wi-Fi 自动下载设置失败: $error');
    }
  }
}

Future<bool> _updManifestIsWifiConnected() async {
  if (!Platform.isAndroid) return false;
  try {
    return await const MethodChannel(UpdateService._updateMethodChannelName)
            .invokeMethod<bool>('UpdateService.isWifiConnected') ??
        false;
  } catch (_) {
    return false;
  }
}

Future<String?> _updManifestReadDownloadedPackageVersion(
  String filePath,
) async {
  if (!Platform.isAndroid || filePath.trim().isEmpty) return null;
  try {
    final version = await const MethodChannel(
      UpdateService._updateMethodChannelName,
    ).invokeMethod<String>('getApkVersionName', {'path': filePath});
    return AppTextUtils.trimToNull(version);
  } catch (error) {
    debugPrint('[UpdateService] 读取 APK 内部版本失败: $error');
    return null;
  }
}

Future<void> _updManifestInitWallpaper() async {
  final prefs = await SharedPreferences.getInstance();
  UpdateService.wallpaperShowNotifier.value =
      prefs.getBool(UpdateService._wallpaperShowKey) ?? false;
  UpdateService.wallpaperUrlNotifier.value = prefs.getString(
    UpdateService._wallpaperUrlKey,
  );
}

Future<bool> _updManifestNeedsWallpaperRefresh() async {
  final prefs = await SharedPreferences.getInstance();
  final lastCheck = prefs.getInt(UpdateService._wallpaperLastCheckKey);
  if (lastCheck == null) return true;
  return DateTime.now().millisecondsSinceEpoch - lastCheck >
      UpdateService._wallpaperRefreshInterval.inMilliseconds;
}

Future<void> _updManifestUpdateWallpaperFromManifest() async {
  final manifest = await UpdateService.checkManifest();
  if (manifest != null) {
    final prefs = await SharedPreferences.getInstance();
    UpdateService.wallpaperShowNotifier.value = manifest.wallpaper.show;
    await prefs.setBool(
      UpdateService._wallpaperShowKey,
      manifest.wallpaper.show,
    );
    if (manifest.wallpaper.show && manifest.wallpaper.imageUrl.isNotEmpty) {
      UpdateService.wallpaperUrlNotifier.value = manifest.wallpaper.imageUrl;
      await prefs.setString(
        UpdateService._wallpaperUrlKey,
        manifest.wallpaper.imageUrl,
      );
    }
    await prefs.setInt(
      UpdateService._wallpaperLastCheckKey,
      DateTime.now().millisecondsSinceEpoch,
    );
  }
}

Future<void> _updManifestSyncBandVersionInfo() async {
  if (!BandSyncService.isInitialized || !BandSyncService.isConnected) return;

  // 🚀 核心优化：检查用户是否开启了自动更新功能
  final prefs = await SharedPreferences.getInstance();
  final autoUpdate = prefs.getBool('band_auto_update_enabled') ?? true;
  if (!autoUpdate) {
    debugPrint("🚀 手环自动更新功能已关闭，跳过推送");
    return;
  }

  // 获取手机端的 Manifest，里面包含了 changelog_history
  final manifest = await UpdateService.checkManifest(preferCache: true);
  if (manifest == null) return;

  // 构造发送给手环的信息
  final Map<String, dynamic> bandUpdateInfo = {
    'version_code': manifest.versionCode,
    'version_name': manifest.versionName,
    'update_info': {
      'title': manifest.updateInfo.title,
      'description': manifest.updateInfo.description,
    },
    'timestamp': DateTime.now().millisecondsSinceEpoch,
  };

  await BandSyncService.sendVersionUpdate(bandUpdateInfo);
  debugPrint("🚀 已向手环推送最新版本信息: ${manifest.versionName}");
}

Future<bool> _updManifestIsAnnouncementRead(String announcementId) async {
  if (announcementId.isEmpty) return false;
  final prefs = await SharedPreferences.getInstance();
  return prefs.getBool(
        '${UpdateService._announcementReadPrefix}$announcementId',
      ) ??
      false;
}

Future<void> _updManifestMarkAnnouncementAsRead(String announcementId) async {
  if (announcementId.isEmpty) return;
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool(
    '${UpdateService._announcementReadPrefix}$announcementId',
    true,
  );
}

bool _updManifestShouldShowAnnouncement(
  Announcement announcement,
  bool isRead,
  String currentVersion,
) {
  if (!announcement.show) return false;
  if (announcement.targetVersions.isNotEmpty) {
    // 如果指定了目标版本,当前版本必须在列表中(支持主版本号匹配,如"3"匹配"3.0.0")
    bool versionMatched = false;
    for (var target in announcement.targetVersions) {
      if (currentVersion == target) {
        versionMatched = true;
        break;
      }
      // 支持主版本匹配: target="3" 匹配 currentVersion="3.x.x"
      if (!target.contains('.') && currentVersion.startsWith('$target.')) {
        versionMatched = true;
        break;
      }
    }
    if (!versionMatched) return false;
  }
  if (announcement.remindMode == 'always') return true;
  return !isRead;
}

int _updManifestDateTimeToSortKey(DateTime dt) =>
    int.tryParse(AppTimeFormats.format(dt, 'yyyyMMddHHmmss')) ?? 0;

int _updManifestParseAnnouncementSortKey(String id) {
  if (id.isEmpty) return 0;

  final unixMs = UpdateService._announcementUnixMillisecondsPattern
      .firstMatch(id)
      ?.group(1);
  if (unixMs != null) {
    final ms = int.tryParse(unixMs);
    if (ms != null) {
      return _updManifestDateTimeToSortKey(
        AppTimeFormats.localFromServerTimestamp(ms),
      );
    }
  }

  final unixSec = UpdateService._announcementUnixSecondsPattern
      .firstMatch(id)
      ?.group(1);
  if (unixSec != null) {
    final sec = int.tryParse(unixSec);
    if (sec != null) {
      return _updManifestDateTimeToSortKey(
        AppTimeFormats.localFromServerTimestamp(sec * 1000),
      );
    }
  }

  final matches = UpdateService._announcementDateDigitsPattern
      .allMatches(id)
      .map((m) => m.group(0)!)
      .toList();
  if (matches.isEmpty) return 0;

  matches.sort((a, b) => b.length.compareTo(a.length));
  final raw = matches.first;

  if (raw.length == 14) return int.tryParse(raw) ?? 0;
  if (raw.length == 12) return int.tryParse('${raw}00') ?? 0;
  if (raw.length == 10) return int.tryParse('${raw}0000') ?? 0;
  return int.tryParse('${raw}000000') ?? 0;
}

List<Announcement> _updManifestSortAnnouncementsByIdDesc(
  List<Announcement> items,
) {
  final sorted = List<Announcement>.from(items);
  sorted.sort((a, b) {
    final keyA = UpdateService.parseAnnouncementSortKey(a.id);
    final keyB = UpdateService.parseAnnouncementSortKey(b.id);
    if (keyA != keyB) return keyB.compareTo(keyA);
    return b.id.compareTo(a.id);
  });
  return sorted;
}

Future<List<Announcement>?> _updManifestGetAnnouncementsForSettings() async {
  try {
    final manifest = await UpdateService.checkManifest();
    if (manifest == null) return null;

    final packageInfo = await PackageInfo.fromPlatform();
    final currentVersion = packageInfo.version;

    final visible = manifest.announcements
        .where(
          (ann) =>
              UpdateService.shouldShowAnnouncement(ann, false, currentVersion),
        )
        .toList();
    return UpdateService.sortAnnouncementsByIdDesc(visible);
  } catch (_) {
    return null;
  }
}

String _updManifestCleanVersion(String version) =>
    version.split('+').first.split('-').first.trim();

String _updManifestGiteePackageUrl(String url) {
  final uri = Uri.tryParse(url);
  if (uri?.scheme == 'https' && uri?.host.toLowerCase() == 'gitee.com') {
    return url;
  }
  debugPrint('[UpdateService] 忽略非 Gitee 安装包地址: $url');
  return '';
}

Future<AppManifest?> _updManifestReadManifestCache() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final cached = prefs.getString(UpdateService._manifestCacheKey);
    if (cached == null || cached.isEmpty) return null;
    return AppManifest.fromJson(jsonDecode(cached));
  } catch (_) {
    return null;
  }
}

Future<AppManifest?> _updManifestReadBundledManifest() async {
  try {
    final rawJson = await rootBundle.loadString('update_manifest.json');
    return AppManifest.fromJson(jsonDecode(rawJson));
  } catch (e) {
    debugPrint('[UpdateService] bundled manifest unavailable: $e');
    return null;
  }
}

Future<void> _updManifestWriteManifestCache(String rawJson) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(UpdateService._manifestCacheKey, rawJson);
    await prefs.setInt(
      UpdateService._manifestCacheTimeKey,
      DateTime.now().millisecondsSinceEpoch,
    );
  } catch (_) {}
}

Future<AppManifest?> _updManifestFetchManifestFromNetwork() async {
  final updateSource = await UpdateService.getUpdateSource();

  // 根据用户偏好选择数据源
  if (updateSource == UpdateService.updateSourceServer) {
    // 用户选择服务器优先
    return await _updManifestFetchFromServerFirst();
  } else {
    // 默认：GitHub 优先，失败降级服务器
    return await _updManifestFetchFromGitHubFirst();
  }
}

Future<AppManifest?> _updManifestFetchFromGitHubFirst() async {
  // 优先从 GitHub 获取
  try {
    final response = await UpdateService._resourceService
        .get(Uri.parse(UpdateService.manifestUrl))
        .timeout(const Duration(seconds: 8));
    if (response.statusCode == 200) {
      final body = utf8.decode(response.bodyBytes);
      final manifest = AppManifest.fromJson(jsonDecode(body));
      await _updManifestWriteManifestCache(body);
      debugPrint(
        '[UpdateService] GitHub manifest 获取成功: v${manifest.versionName}',
      );
      return manifest;
    }
  } catch (e) {
    debugPrint('[UpdateService] GitHub manifest 获取失败: $e');
  }

  // GitHub 失败，降级到服务器获取
  try {
    debugPrint('[UpdateService] 降级到服务器获取 manifest...');
    final response = await UpdateService._resourceService
        .get(Uri.parse(UpdateService.fallbackManifestUrl))
        .timeout(const Duration(seconds: 8));
    if (response.statusCode == 200) {
      final body = utf8.decode(response.bodyBytes);
      final manifest = AppManifest.fromJson(jsonDecode(body));
      await _updManifestWriteManifestCache(body);
      debugPrint('[UpdateService] 服务器 manifest 获取成功: v${manifest.versionName}');
      return manifest;
    }
  } catch (e) {
    debugPrint('[UpdateService] 服务器 manifest 获取失败: $e');
  }

  return null;
}

Future<AppManifest?> _updManifestFetchFromServerFirst() async {
  // 优先从服务器获取
  try {
    final response = await UpdateService._resourceService
        .get(Uri.parse(UpdateService.fallbackManifestUrl))
        .timeout(const Duration(seconds: 8));
    if (response.statusCode == 200) {
      final body = utf8.decode(response.bodyBytes);
      final manifest = AppManifest.fromJson(jsonDecode(body));
      await _updManifestWriteManifestCache(body);
      debugPrint('[UpdateService] 服务器 manifest 获取成功: v${manifest.versionName}');
      return manifest;
    }
  } catch (e) {
    debugPrint('[UpdateService] 服务器 manifest 获取失败: $e');
  }

  // 服务器失败，降级到 GitHub 获取
  try {
    debugPrint('[UpdateService] 降级到 GitHub 获取 manifest...');
    final response = await UpdateService._resourceService
        .get(Uri.parse(UpdateService.manifestUrl))
        .timeout(const Duration(seconds: 8));
    if (response.statusCode == 200) {
      final body = utf8.decode(response.bodyBytes);
      final manifest = AppManifest.fromJson(jsonDecode(body));
      await _updManifestWriteManifestCache(body);
      debugPrint(
        '[UpdateService] GitHub manifest 获取成功: v${manifest.versionName}',
      );
      return manifest;
    }
  } catch (e) {
    debugPrint('[UpdateService] GitHub manifest 获取失败: $e');
  }

  return null;
}

List<ChangelogEntry> _updManifestParseChangelogArchive(String rawJson) {
  final decoded = jsonDecode(rawJson);
  final source = decoded is List
      ? decoded
      : (decoded as Map<String, dynamic>)['changelog_history']
                as List<dynamic>? ??
            [];
  return source
      .map((e) => ChangelogEntry.fromJson(e as Map<String, dynamic>))
      .toList();
}

Future<List<ChangelogEntry>> _updManifestReadChangelogArchiveCache() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final cached = prefs.getString(UpdateService._changelogArchiveCacheKey);
    if (cached == null || cached.isEmpty) return const [];
    return _updManifestParseChangelogArchive(cached);
  } catch (_) {
    return const [];
  }
}

Future<List<ChangelogEntry>> _updManifestReadBundledChangelogArchive() async {
  try {
    final rawJson = await rootBundle.loadString(
      'update_changelog_archive.json',
    );
    return _updManifestParseChangelogArchive(rawJson);
  } catch (e) {
    debugPrint('[UpdateService] bundled changelog archive unavailable: $e');
    return const [];
  }
}

Future<void> _updManifestWriteChangelogArchiveCache(String rawJson) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(UpdateService._changelogArchiveCacheKey, rawJson);
    await prefs.setInt(
      UpdateService._changelogArchiveCacheTimeKey,
      DateTime.now().millisecondsSinceEpoch,
    );
  } catch (_) {}
}

Future<List<ChangelogEntry>> _updManifestLoadChangelogArchive({
  AppManifest? manifest,
  bool preferCache = true,
}) async {
  final archiveUrl = manifest?.changelogArchive.url.isNotEmpty == true
      ? manifest!.changelogArchive.url
      : UpdateService.changelogArchiveUrl;

  if (preferCache) {
    final cached = await _updManifestReadChangelogArchiveCache();
    if (cached.isNotEmpty) return cached;
  }

  try {
    final response = await UpdateService._resourceService.get(
      Uri.parse(archiveUrl),
    );
    if (response.statusCode == 200) {
      final body = utf8.decode(response.bodyBytes);
      final archive = _updManifestParseChangelogArchive(body);
      await _updManifestWriteChangelogArchiveCache(body);
      return archive;
    }
  } catch (_) {}

  final cached = await _updManifestReadChangelogArchiveCache();
  if (cached.isNotEmpty) return cached;

  return _updManifestReadBundledChangelogArchive();
}

Future<AppManifest?> _updManifestRefreshManifestCache({bool dedupe = true}) {
  if (dedupe && UpdateService._manifestRefreshFuture != null) {
    return UpdateService._manifestRefreshFuture!;
  }

  UpdateService._lastManifestRefreshAttemptMs =
      DateTime.now().millisecondsSinceEpoch;
  final future = _updManifestFetchManifestFromNetwork();
  UpdateService._manifestRefreshFuture = future;

  future.whenComplete(() {
    if (identical(UpdateService._manifestRefreshFuture, future)) {
      UpdateService._manifestRefreshFuture = null;
    }
  });

  return future;
}

Future<void> _updManifestPreloadManifestCache() async {
  final cached = await _updManifestReadManifestCache();
  if (cached == null) {
    await UpdateService.refreshManifestCache();
    return;
  }
  if (await _updManifestShouldRefreshManifestCache()) {
    unawaited(UpdateService.refreshManifestCache());
  }
}

Future<AppManifest?> _updManifestCheckManifest({
  bool preferCache = true,
  bool refreshInBackground = true,
}) async {
  if (preferCache) {
    final cached = await _updManifestReadManifestCache();
    if (cached != null) {
      if (refreshInBackground &&
          await _updManifestShouldRefreshManifestCache()) {
        unawaited(UpdateService.refreshManifestCache());
      }
      return cached;
    }
  }

  final network = await UpdateService.refreshManifestCache();
  if (network != null) return network;

  final cached = await _updManifestReadManifestCache();
  if (cached != null) return cached;

  return _updManifestReadBundledManifest();
}

Future<bool> _updManifestShouldRefreshManifestCache() async {
  final prefs = await SharedPreferences.getInstance();
  return UpdateService.isManifestRefreshDue(
    nowMs: DateTime.now().millisecondsSinceEpoch,
    lastSuccessfulRefreshMs: prefs.getInt(UpdateService._manifestCacheTimeKey),
    lastAttemptMs: UpdateService._lastManifestRefreshAttemptMs,
  );
}

bool _updManifestIsManifestRefreshDue({
  required int nowMs,
  int? lastSuccessfulRefreshMs,
  int? lastAttemptMs,
  Duration refreshInterval = UpdateService._manifestRefreshInterval,
  Duration retryInterval = UpdateService._manifestRetryInterval,
}) {
  if (lastAttemptMs != null) {
    final attemptAge = nowMs - lastAttemptMs;
    if (attemptAge >= 0 && attemptAge < retryInterval.inMilliseconds) {
      return false;
    }
  }
  if (lastSuccessfulRefreshMs == null) return true;

  final cacheAge = nowMs - lastSuccessfulRefreshMs;
  return cacheAge < 0 || cacheAge >= refreshInterval.inMilliseconds;
}
