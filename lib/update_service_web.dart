import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:CountDownTodo/services/notification_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:web/web.dart' as web;

class ChangelogEntry {
  final String versionName;
  final String date;
  final List<String> items;

  const ChangelogEntry({
    required this.versionName,
    required this.date,
    required this.items,
  });

  factory ChangelogEntry.fromJson(Map<String, dynamic> json) => ChangelogEntry(
        versionName: json['version_name']?.toString() ?? '',
        date: json['date']?.toString() ?? '',
        items: (json['items'] as List<dynamic>? ?? [])
            .map((e) => e.toString())
            .toList(),
      );
}

class AppManifest {
  final int versionCode;
  final String versionName;
  final bool forceUpdate;
  final UpdateInfo updateInfo;
  final List<Announcement> announcements;
  final WallpaperConfig wallpaper;
  final List<ChangelogEntry> changelogHistory;
  final ChangelogArchiveConfig changelogArchive;

  AppManifest({
    required this.versionCode,
    required this.versionName,
    required this.forceUpdate,
    required this.updateInfo,
    required this.announcements,
    required this.wallpaper,
    this.changelogHistory = const [],
    required this.changelogArchive,
  });

  factory AppManifest.fromJson(Map<String, dynamic> json) {
    List<Announcement> announcementsList = [];
    if (json['announcements'] != null) {
      announcementsList = (json['announcements'] as List<dynamic>)
          .map((e) => Announcement.fromJson(e as Map<String, dynamic>))
          .toList();
    } else if (json['announcement'] != null) {
      announcementsList = [
        Announcement.fromJson(json['announcement'] as Map<String, dynamic>)
      ];
    }

    return AppManifest(
      versionCode: int.tryParse(json['version_code']?.toString() ?? '0') ?? 0,
      versionName: json['version_name']?.toString() ?? '',
      forceUpdate: json['force_update'] == true,
      updateInfo: UpdateInfo.fromJson(
        (json['update_info'] as Map?)?.cast<String, dynamic>() ?? {},
      ),
      announcements: announcementsList,
      wallpaper: WallpaperConfig.fromJson(
        (json['wallpaper'] as Map?)?.cast<String, dynamic>() ?? {},
      ),
      changelogHistory: (json['changelog_history'] as List<dynamic>? ?? [])
          .map((e) => ChangelogEntry.fromJson(e as Map<String, dynamic>))
          .toList(),
      changelogArchive: ChangelogArchiveConfig.fromJson(
        (json['changelog_archive'] as Map?)?.cast<String, dynamic>() ?? {},
      ),
    );
  }
}

class ChangelogArchiveConfig {
  final String url;
  final int count;
  final String latestVersion;
  final String oldestVersion;

  const ChangelogArchiveConfig({
    required this.url,
    this.count = 0,
    this.latestVersion = '',
    this.oldestVersion = '',
  });

  bool get isAvailable => url.isNotEmpty && count > 0;

  factory ChangelogArchiveConfig.fromJson(Map<String, dynamic> json) =>
      ChangelogArchiveConfig(
        url: json['url']?.toString() ?? '',
        count: int.tryParse(json['count']?.toString() ?? '0') ?? 0,
        latestVersion: json['latest_version']?.toString() ?? '',
        oldestVersion: json['oldest_version']?.toString() ?? '',
      );
}

class UpdateInfo {
  final String title;
  final String description;
  final String fullPackageUrl;
  final String pcPackageUrl;
  final String macPackageUrl;
  final Map<String, String> androidArchPackages;

  UpdateInfo.fromJson(Map<String, dynamic> json)
      : title = json['title']?.toString() ?? '版本更新',
        description = json['description']?.toString() ?? '',
        fullPackageUrl = json['full_package_url']?.toString() ?? '',
        pcPackageUrl = json['PC_package_url']?.toString() ?? '',
        macPackageUrl = json['mac_package_url']?.toString() ?? '',
        androidArchPackages = json['android_arch_packages'] != null
            ? Map<String, String>.from(json['android_arch_packages'] as Map)
            : {};
}

class Announcement {
  final bool show;
  final String id;
  final String title;
  final String content;
  final String remindMode;
  final List<String> targetVersions;

  Announcement.fromJson(Map<String, dynamic> json)
      : show = json['show'] == true,
        id = json['id']?.toString() ?? '',
        title = json['title']?.toString() ?? '',
        content = json['content']?.toString() ?? '',
        remindMode = json['remind_mode']?.toString() ?? 'once',
        targetVersions = (json['target_versions'] as List<dynamic>?)
                ?.map((e) => e.toString())
                .toList() ??
            [];
}

class WallpaperConfig {
  final bool show;
  final String imageUrl;

  WallpaperConfig.fromJson(Map<String, dynamic> json)
      : show = json['show'] == true,
        imageUrl = json['image_url']?.toString() ?? '';
}

class _AnnouncementCarouselDialog extends StatefulWidget {
  final List<Announcement> announcements;

  const _AnnouncementCarouselDialog({required this.announcements});

  @override
  State<_AnnouncementCarouselDialog> createState() =>
      _AnnouncementCarouselDialogState();
}

class _AnnouncementCarouselDialogState
    extends State<_AnnouncementCarouselDialog> {
  int _currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    final announcement = widget.announcements[_currentIndex];
    final isLast = _currentIndex == widget.announcements.length - 1;
    final isFirst = _currentIndex == 0;
    final colorScheme = Theme.of(context).colorScheme;

    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.campaign, color: colorScheme.primary),
          const SizedBox(width: 8),
          Expanded(child: Text(announcement.title)),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(announcement.content),
          if (widget.announcements.length > 1) ...[
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                widget.announcements.length,
                (index) => Container(
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _currentIndex == index
                        ? colorScheme.primary
                        : colorScheme.outlineVariant,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
      actions: [
        if (!isFirst)
          TextButton(
            onPressed: () => setState(() => _currentIndex--),
            child: const Text('上一条'),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('关闭'),
        ),
        if (!isLast)
          ElevatedButton(
            onPressed: () => setState(() => _currentIndex++),
            child: const Text('下一条'),
          )
        else
          ElevatedButton(
            onPressed: () async {
              for (final ann in widget.announcements) {
                if (ann.remindMode == 'once') {
                  await UpdateService.markAnnouncementAsRead(ann.id);
                }
              }
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('全部已读'),
          ),
      ],
    );
  }
}

class UpdateService {
  static const String MANIFEST_URL =
      'https://raw.githubusercontent.com/Junpgle/CountdownTodo/refs/heads/master/update_manifest.json';
  static const String FALLBACK_MANIFEST_URL =
      'https://api-cdt.junpgle.me/api/manifest';
  static const String CHANGELOG_ARCHIVE_URL =
      'https://raw.githubusercontent.com/Junpgle/CountdownTodo/refs/heads/master/update_changelog_archive.json';
  static const String _manifestCacheKey = 'update_manifest_cache_json';
  static const String _manifestCacheTimeKey = 'update_manifest_cache_time';
  static const String _changelogArchiveCacheKey =
      'changelog_archive_cache_json';
  static const String _changelogArchiveCacheTimeKey =
      'changelog_archive_cache_time';
  static const String _updateDialogSnoozeTodayKey =
      'update_dialog_snooze_today';
  static const String _updateSourceKey = 'update_source_preference';
  static const String UPDATE_SOURCE_GITHUB = 'github';
  static const String UPDATE_SOURCE_SERVER = 'server';

  static Future<AppManifest?>? _manifestRefreshFuture;
  static bool _isDialogShowing = false;
  static bool _isAnnouncementDialogShowing = false;

  static ValueNotifier<String?> wallpaperUrlNotifier =
      ValueNotifier<String?>(null);
  static ValueNotifier<bool> wallpaperShowNotifier = ValueNotifier<bool>(false);
  static const String _wallpaperUrlKey = 'manifest_wallpaper_url';
  static const String _wallpaperShowKey = 'manifest_wallpaper_show';
  static const String _wallpaperLastCheckKey = 'manifest_wallpaper_last_check';
  static const Duration _wallpaperRefreshInterval = Duration(hours: 24);

  static Future<String> getUpdateSource() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_updateSourceKey) ?? UPDATE_SOURCE_GITHUB;
  }

  static Future<void> setUpdateSource(String source) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_updateSourceKey, source);
  }

  static Future<void> initWallpaper() async {
    final prefs = await SharedPreferences.getInstance();
    wallpaperShowNotifier.value = prefs.getBool(_wallpaperShowKey) ?? false;
    wallpaperUrlNotifier.value = prefs.getString(_wallpaperUrlKey);
  }

  static Future<bool> needsWallpaperRefresh() async {
    final prefs = await SharedPreferences.getInstance();
    final lastCheck = prefs.getInt(_wallpaperLastCheckKey);
    if (lastCheck == null) return true;
    return DateTime.now().millisecondsSinceEpoch - lastCheck >
        _wallpaperRefreshInterval.inMilliseconds;
  }

  static Future<void> updateWallpaperFromManifest() async {
    final manifest = await checkManifest();
    if (manifest == null) return;
    final prefs = await SharedPreferences.getInstance();
    wallpaperShowNotifier.value = manifest.wallpaper.show;
    await prefs.setBool(_wallpaperShowKey, manifest.wallpaper.show);
    if (manifest.wallpaper.show && manifest.wallpaper.imageUrl.isNotEmpty) {
      wallpaperUrlNotifier.value = manifest.wallpaper.imageUrl;
      await prefs.setString(_wallpaperUrlKey, manifest.wallpaper.imageUrl);
    }
    await prefs.setInt(
      _wallpaperLastCheckKey,
      DateTime.now().millisecondsSinceEpoch,
    );
  }

  static Future<void> syncBandVersionInfo() async {}

  static const String _announcementReadPrefix = 'announcement_read_';

  static Future<bool> isAnnouncementRead(String announcementId) async {
    if (announcementId.isEmpty) return false;
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('$_announcementReadPrefix$announcementId') ?? false;
  }

  static Future<void> markAnnouncementAsRead(String announcementId) async {
    if (announcementId.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('$_announcementReadPrefix$announcementId', true);
  }

  static bool shouldShowAnnouncement(
    Announcement announcement,
    bool isRead,
    String currentVersion,
  ) {
    if (!announcement.show) return false;
    if (announcement.targetVersions.isNotEmpty) {
      var versionMatched = false;
      for (final target in announcement.targetVersions) {
        if (currentVersion == target ||
            (!target.contains('.') && currentVersion.startsWith('$target.'))) {
          versionMatched = true;
          break;
        }
      }
      if (!versionMatched) return false;
    }
    if (announcement.remindMode == 'always') return true;
    return !isRead;
  }

  static int _dateTimeToSortKey(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    final ss = dt.second.toString().padLeft(2, '0');
    return int.tryParse('$y$m$d$hh$mm$ss') ?? 0;
  }

  static int parseAnnouncementSortKey(String id) {
    if (id.isEmpty) return 0;

    final unixMs = RegExp(r'(1\d{12})').firstMatch(id)?.group(1);
    if (unixMs != null) {
      final ms = int.tryParse(unixMs);
      if (ms != null) {
        return _dateTimeToSortKey(
          DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true).toLocal(),
        );
      }
    }

    final unixSec = RegExp(r'(1\d{9})').firstMatch(id)?.group(1);
    if (unixSec != null) {
      final sec = int.tryParse(unixSec);
      if (sec != null) {
        return _dateTimeToSortKey(
          DateTime.fromMillisecondsSinceEpoch(sec * 1000, isUtc: true)
              .toLocal(),
        );
      }
    }

    final matches = RegExp(r'(\d{14}|\d{12}|\d{10}|\d{8})')
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

  static List<Announcement> sortAnnouncementsByIdDesc(
    List<Announcement> items,
  ) {
    final sorted = List<Announcement>.from(items);
    sorted.sort((a, b) {
      final keyA = parseAnnouncementSortKey(a.id);
      final keyB = parseAnnouncementSortKey(b.id);
      if (keyA != keyB) return keyB.compareTo(keyA);
      return b.id.compareTo(a.id);
    });
    return sorted;
  }

  static Future<List<Announcement>?> getAnnouncementsForSettings() async {
    try {
      final manifest = await checkManifest();
      if (manifest == null) return null;

      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version;

      final visible = manifest.announcements
          .where((ann) => shouldShowAnnouncement(ann, false, currentVersion))
          .toList();
      return sortAnnouncementsByIdDesc(visible);
    } catch (_) {
      return null;
    }
  }

  static String getUpdateFileName(String versionName) =>
      'CountdownTodo_v$versionName.zip';

  static Future<String> getDeviceArchitecture() async => 'web';

  static String getDownloadUrlForArch(AppManifest manifest) {
    if (manifest.updateInfo.fullPackageUrl.isNotEmpty) {
      return manifest.updateInfo.fullPackageUrl;
    }
    if (manifest.updateInfo.pcPackageUrl.isNotEmpty) {
      return manifest.updateInfo.pcPackageUrl;
    }
    if (manifest.updateInfo.macPackageUrl.isNotEmpty) {
      return manifest.updateInfo.macPackageUrl;
    }
    if (manifest.updateInfo.androidArchPackages.isNotEmpty) {
      return manifest.updateInfo.androidArchPackages.values.first;
    }
    return '';
  }

  static Future<AppManifest?> _readManifestCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getString(_manifestCacheKey);
      if (cached == null || cached.isEmpty) return null;
      return AppManifest.fromJson(
        (jsonDecode(cached) as Map).cast<String, dynamic>(),
      );
    } catch (_) {
      return null;
    }
  }

  static Future<AppManifest?> _readBundledManifest() async {
    try {
      final rawJson = await rootBundle.loadString('update_manifest.json');
      return AppManifest.fromJson(
        (jsonDecode(rawJson) as Map).cast<String, dynamic>(),
      );
    } catch (_) {
      return null;
    }
  }

  static Future<void> _writeManifestCache(String rawJson) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_manifestCacheKey, rawJson);
      await prefs.setInt(
        _manifestCacheTimeKey,
        DateTime.now().millisecondsSinceEpoch,
      );
    } catch (_) {}
  }

  static Future<AppManifest?> _fetchManifestFromNetwork() async {
    final source = await getUpdateSource();
    if (source == UPDATE_SOURCE_SERVER) {
      return _fetchFromServerFirst();
    }
    return _fetchFromGitHubFirst();
  }

  static Future<AppManifest?> _fetchFromGitHubFirst() async {
    final github = await _fetchManifestUrl(MANIFEST_URL);
    if (github != null) return github;
    return _fetchManifestUrl(FALLBACK_MANIFEST_URL);
  }

  static Future<AppManifest?> _fetchFromServerFirst() async {
    final server = await _fetchManifestUrl(FALLBACK_MANIFEST_URL);
    if (server != null) return server;
    return _fetchManifestUrl(MANIFEST_URL);
  }

  static Future<AppManifest?> _fetchManifestUrl(String url) async {
    try {
      final response =
          await http.get(Uri.parse(url)).timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) return null;
      final body = utf8.decode(response.bodyBytes);
      final manifest = AppManifest.fromJson(
        (jsonDecode(body) as Map).cast<String, dynamic>(),
      );
      await _writeManifestCache(body);
      return manifest;
    } catch (_) {
      return null;
    }
  }

  static List<ChangelogEntry> _parseChangelogArchive(String rawJson) {
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

  static Future<List<ChangelogEntry>> _readChangelogArchiveCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getString(_changelogArchiveCacheKey);
      if (cached == null || cached.isEmpty) return const [];
      return _parseChangelogArchive(cached);
    } catch (_) {
      return const [];
    }
  }

  static Future<List<ChangelogEntry>> _readBundledChangelogArchive() async {
    try {
      final rawJson =
          await rootBundle.loadString('update_changelog_archive.json');
      return _parseChangelogArchive(rawJson);
    } catch (_) {
      return const [];
    }
  }

  static Future<void> _writeChangelogArchiveCache(String rawJson) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_changelogArchiveCacheKey, rawJson);
      await prefs.setInt(
        _changelogArchiveCacheTimeKey,
        DateTime.now().millisecondsSinceEpoch,
      );
    } catch (_) {}
  }

  static Future<List<ChangelogEntry>> loadChangelogArchive({
    AppManifest? manifest,
    bool preferCache = true,
  }) async {
    final archiveUrl = manifest?.changelogArchive.url.isNotEmpty == true
        ? manifest!.changelogArchive.url
        : CHANGELOG_ARCHIVE_URL;

    if (preferCache) {
      final cached = await _readChangelogArchiveCache();
      if (cached.isNotEmpty) return cached;
    }

    try {
      final response = await http.get(Uri.parse(archiveUrl));
      if (response.statusCode == 200) {
        final body = utf8.decode(response.bodyBytes);
        final archive = _parseChangelogArchive(body);
        await _writeChangelogArchiveCache(body);
        return archive;
      }
    } catch (_) {}

    final cached = await _readChangelogArchiveCache();
    if (cached.isNotEmpty) return cached;
    return _readBundledChangelogArchive();
  }

  static Future<AppManifest?> refreshManifestCache({bool dedupe = true}) {
    if (dedupe && _manifestRefreshFuture != null) {
      return _manifestRefreshFuture!;
    }

    final future = _fetchManifestFromNetwork();
    _manifestRefreshFuture = future;
    future.whenComplete(() {
      if (identical(_manifestRefreshFuture, future)) {
        _manifestRefreshFuture = null;
      }
    });
    return future;
  }

  static Future<void> preloadManifestCache() async {
    final cached = await _readManifestCache();
    if (cached == null) {
      await refreshManifestCache();
      return;
    }
    unawaited(refreshManifestCache());
  }

  static Future<AppManifest?> checkManifest({
    bool preferCache = true,
    bool refreshInBackground = true,
  }) async {
    if (preferCache) {
      final cached = await _readManifestCache();
      if (cached != null) {
        if (refreshInBackground) unawaited(refreshManifestCache());
        return cached;
      }
    }

    final network = await refreshManifestCache();
    if (network != null) return network;

    final cached = await _readManifestCache();
    if (cached != null) return cached;

    return _readBundledManifest();
  }

  static Future<String?> isPackageAlreadyDownloaded(String versionName) async =>
      null;

  static Future<bool> prepareForDownload(String targetVersionName) async =>
      true;

  static Future<String?> getDownloadDirectory() async => null;

  static Future<void> installPackage(String filePath) async {
    final uri = Uri.tryParse(filePath);
    if (uri != null && uri.hasScheme) {
      await launchUrl(uri, webOnlyWindowName: '_blank');
    }
  }

  static Future<void> forceDownloadLatest(
    BuildContext context, {
    required Function(double) onProgress,
    required Function(String) onComplete,
    required Function(String) onError,
  }) async {
    final manifest = await checkManifest(
      preferCache: false,
      refreshInBackground: false,
    );
    if (manifest == null) {
      onError('获取版本信息失败，请检查网络');
      return;
    }
    final downloadUrl = getDownloadUrlForArch(manifest);
    if (downloadUrl.isEmpty) {
      onError('未找到可用的下载链接');
      return;
    }
    onProgress(1);
    final launched =
        await launchUrl(Uri.parse(downloadUrl), webOnlyWindowName: '_blank');
    if (launched) {
      onComplete(downloadUrl);
    } else {
      onError('无法打开下载链接');
    }
  }

  static Future<void> checkUpdateAndPrompt(
    BuildContext context, {
    bool isManual = false,
  }) async {
    if (_isDialogShowing) return;

    final manifest = await checkManifest(
      preferCache: !isManual,
      refreshInBackground: !isManual,
    );
    if (manifest == null) {
      if (isManual && context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('检查失败，请检查网络')));
      }
      return;
    }

    final packageInfo = await PackageInfo.fromPlatform();
    final localVersion = packageInfo.version;
    var hasUpdate = _compareVersions(manifest.versionName, localVersion);

    final announcementsToShow = <Announcement>[];
    for (final ann in manifest.announcements) {
      final annRead = await isAnnouncementRead(ann.id);
      if (shouldShowAnnouncement(ann, annRead, localVersion)) {
        announcementsToShow.add(ann);
      }
    }
    final hasNotice = announcementsToShow.isNotEmpty;

    if (hasUpdate &&
        !manifest.forceUpdate &&
        !isManual &&
        await _isUpdateDialogSnoozedToday(manifest.versionName)) {
      hasUpdate = false;
    }

    if (!hasUpdate && !hasNotice) {
      if (isManual && context.mounted) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('检查完成'),
            content: Text('当前版本 ($localVersion) 已是最新。'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('好'),
              ),
            ],
          ),
        );
      }
      return;
    }

    if (hasUpdate) {
      NotificationService.showUpdateNotification(
        versionName: manifest.versionName,
        updateTitle: '发现新版本',
        updateContent: manifest.updateInfo.description,
      );
    }

    if (!context.mounted) return;
    if (hasNotice) {
      showAnnouncementDialog(context, announcementsToShow, () {
        if (hasUpdate && context.mounted) {
          showUpdateDialog(
            context,
            manifest,
            localVersion,
            hasUpdate: true,
            hasNotice: false,
            respectTodaySnooze: !isManual,
          );
        }
      });
    } else if (hasUpdate) {
      showUpdateDialog(
        context,
        manifest,
        localVersion,
        hasUpdate: true,
        hasNotice: false,
        respectTodaySnooze: !isManual,
      );
    }
  }

  static Future<void> triggerWebSocketUpdate(
    BuildContext context, {
    required String latestVersion,
    required String releaseNotes,
    required String downloadUrl,
  }) async {
    final packageInfo = await PackageInfo.fromPlatform();
    final localVersion = packageInfo.version;
    if (!_compareVersions(latestVersion, localVersion)) return;
    if (await _isUpdateDialogSnoozedToday(latestVersion)) return;
    if (_isDialogShowing) return;

    final manifest = AppManifest(
      versionCode: 0,
      versionName: latestVersion,
      forceUpdate: false,
      updateInfo: UpdateInfo.fromJson({
        'title': '发现新版本 $latestVersion',
        'description': releaseNotes,
        'full_package_url': downloadUrl,
      }),
      announcements: [],
      wallpaper: WallpaperConfig.fromJson({'show': false}),
      changelogArchive: const ChangelogArchiveConfig(url: ''),
    );

    if (context.mounted) {
      showUpdateDialog(context, manifest, localVersion);
    }
  }

  static bool _compareVersions(String manifestVersion, String localVersion) {
    try {
      final v1 = manifestVersion
          .split('+')[0]
          .split('-')[0]
          .split('.')
          .map((e) => int.tryParse(e) ?? 0)
          .toList();
      final v2 = localVersion
          .split('+')[0]
          .split('-')[0]
          .split('.')
          .map((e) => int.tryParse(e) ?? 0)
          .toList();
      final maxLen = v1.length > v2.length ? v1.length : v2.length;
      for (var i = 0; i < maxLen; i++) {
        final p1 = i < v1.length ? v1[i] : 0;
        final p2 = i < v2.length ? v2[i] : 0;
        if (p1 > p2) return true;
        if (p1 < p2) return false;
      }
    } catch (_) {}
    return false;
  }

  static Future<void> showAnnouncementDialog(
    BuildContext context,
    List<Announcement> announcements,
    VoidCallback? onDismissed,
  ) async {
    if (_isAnnouncementDialogShowing || announcements.isEmpty) return;
    _isAnnouncementDialogShowing = true;

    if (!context.mounted) {
      _isAnnouncementDialogShowing = false;
      return;
    }

    await showDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) => _AnnouncementCarouselDialog(
        announcements: announcements,
      ),
    );

    _isAnnouncementDialogShowing = false;
    onDismissed?.call();
  }

  static Future<void> showUpdateDialog(
    BuildContext context,
    AppManifest manifest,
    String currentVersion, {
    bool hasUpdate = true,
    bool hasNotice = false,
    bool respectTodaySnooze = true,
  }) async {
    if (_isDialogShowing) return;
    if (hasUpdate &&
        respectTodaySnooze &&
        !manifest.forceUpdate &&
        await _isUpdateDialogSnoozedToday(manifest.versionName)) {
      return;
    }
    _isDialogShowing = true;
    NotificationService.cancelUpdateNotification();

    if (!context.mounted) {
      _isDialogShowing = false;
      return;
    }

    showDialog(
      context: context,
      barrierDismissible: !manifest.forceUpdate,
      builder: (ctx) {
        return PopScope(
          canPop: !manifest.forceUpdate,
          child: AlertDialog(
            contentPadding: EdgeInsets.zero,
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (manifest.wallpaper.show &&
                      manifest.wallpaper.imageUrl.isNotEmpty)
                    ClipRRect(
                      borderRadius:
                          const BorderRadius.vertical(top: Radius.circular(20)),
                      child: Image.network(
                        manifest.wallpaper.imageUrl,
                        height: 200,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) =>
                            const SizedBox(height: 0),
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: _buildUpdateDialogContent(
                      ctx,
                      manifest,
                      currentVersion,
                      hasUpdate,
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              if (!manifest.forceUpdate && hasUpdate)
                TextButton(
                  onPressed: () async {
                    await _snoozeUpdateDialogForToday(manifest.versionName);
                    if (ctx.mounted) Navigator.pop(ctx);
                  },
                  child: const Text('今日不再提醒'),
                ),
              if (!manifest.forceUpdate)
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('稍后再说'),
                ),
            ],
          ),
        );
      },
    ).then((_) {
      _isDialogShowing = false;
    });
  }

  static Widget _buildUpdateDialogContent(
    BuildContext context,
    AppManifest manifest,
    String currentVersion,
    bool hasUpdate,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (hasUpdate) ...[
          Row(
            children: [
              Icon(Icons.new_releases, color: colorScheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  manifest.updateInfo.title,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '当前: $currentVersion  ->  最新: ${manifest.versionName}',
            style: TextStyle(
              fontSize: 12,
              color: colorScheme.primary,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 10),
          Text(manifest.updateInfo.description),
          const SizedBox(height: 10),
          Text(
            '网页版会通过刷新页面加载最新资源；若已有待更新的离线缓存，会先应用缓存更新再刷新。',
            style: TextStyle(
              fontSize: 12,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('刷新网页获取最新版本'),
              onPressed: _refreshWebApp,
            ),
          ),
        ],
      ],
    );
  }

  static void _refreshWebApp() {
    try {
      if (globalContext.has('cdtPwa')) {
        final pwa = globalContext['cdtPwa'] as JSObject?;
        if (pwa != null) {
          pwa.callMethod<JSAny?>('refreshApp'.toJS);
          return;
        }
      }
    } catch (_) {}

    web.window.location.reload();
  }

  static String _todayKey([DateTime? now]) {
    final date = now ?? DateTime.now();
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '${date.year}-$month-$day';
  }

  static String _snoozeValue(String versionName, [DateTime? now]) =>
      '${_todayKey(now)}|$versionName';

  static Future<bool> _isUpdateDialogSnoozedToday(String versionName) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_updateDialogSnoozeTodayKey) ==
        _snoozeValue(versionName);
  }

  static Future<void> _snoozeUpdateDialogForToday(String versionName) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _updateDialogSnoozeTodayKey,
      _snoozeValue(versionName),
    );
  }
}
