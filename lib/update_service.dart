import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:CountDownTodo/services/band_sync_service.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:open_file/open_file.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shared_preferences/shared_preferences.dart';

// 数据模型类
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
        versionName: json['version_name'] ?? '',
        date: json['date'] ?? '',
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

  AppManifest({
    required this.versionCode,
    required this.versionName,
    required this.forceUpdate,
    required this.updateInfo,
    required this.announcements,
    required this.wallpaper,
    this.changelogHistory = const [],
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
      versionCode: json['version_code'] ?? 0,
      versionName: json['version_name'] ?? '',
      forceUpdate: json['force_update'] ?? false,
      updateInfo: UpdateInfo.fromJson(json['update_info'] ?? {}),
      announcements: announcementsList,
      wallpaper: WallpaperConfig.fromJson(json['wallpaper'] ?? {}),
      changelogHistory: (json['changelog_history'] as List<dynamic>? ?? [])
          .map((e) => ChangelogEntry.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

class UpdateInfo {
  final String title;
  final String description;
  final String fullPackageUrl;
  final String pcPackageUrl;
  final Map<String, String> androidArchPackages;

  UpdateInfo.fromJson(Map<String, dynamic> json)
      : title = json['title'] ?? '版本更新',
        description = json['description'] ?? '',
        fullPackageUrl = json['full_package_url'] ?? '',
        pcPackageUrl = json['PC_package_url'] ?? '',
        androidArchPackages = json['android_arch_packages'] != null
            ? Map<String, String>.from(json['android_arch_packages'])
            : {};
}

class Announcement {
  final bool show;
  final String id;
  final String title;
  final String content;
  final String remindMode;
  final List<String> targetVersions; // 空列表=所有版本, 非空=仅指定版本可见

  Announcement.fromJson(Map<String, dynamic> json)
      : show = json['show'] ?? false,
        id = json['id'] ?? '',
        title = json['title'] ?? '',
        content = json['content'] ?? '',
        remindMode = json['remind_mode'] ?? 'once',
        targetVersions = (json['target_versions'] as List<dynamic>?)
                ?.map((e) => e.toString())
                .toList() ??
            [];
}

class WallpaperConfig {
  final bool show;
  final String imageUrl;

  WallpaperConfig.fromJson(Map<String, dynamic> json)
      : show = json['show'] ?? false,
        imageUrl = json['image_url'] ?? '';
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

    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.campaign, color: Colors.orange),
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
                        ? Colors.orange
                        : Colors.grey[300],
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
            onPressed: () {
              setState(() => _currentIndex--);
            },
            child: const Text("上一条"),
          ),
        TextButton(
          onPressed: () {
            Navigator.pop(context);
          },
          child: const Text("关闭"),
        ),
        if (!isLast)
          ElevatedButton(
            onPressed: () {
              setState(() => _currentIndex++);
            },
            child: const Text("下一条"),
          )
        else
          ElevatedButton(
            onPressed: () async {
              for (var ann in widget.announcements) {
                if (ann.remindMode == 'once') {
                  await UpdateService.markAnnouncementAsRead(ann.id);
                }
              }
              if (context.mounted) {
                Navigator.pop(context);
              }
            },
            child: const Text("全部已读"),
          ),
      ],
    );
  }
}

class UpdateService {
  static const String MANIFEST_URL =
      "https://raw.githubusercontent.com/Junpgle/CountdownTodo/refs/heads/master/update_manifest.json";
  static const String _manifestCacheKey = 'update_manifest_cache_json';
  static const String _manifestCacheTimeKey = 'update_manifest_cache_time';
  static Future<AppManifest?>? _manifestRefreshFuture;

  static bool _isDialogShowing = false;
  static bool _isAnnouncementDialogShowing = false;

  // 全局壁纸状态管理
  static ValueNotifier<String?> wallpaperUrlNotifier =
      ValueNotifier<String?>(null);
  static ValueNotifier<bool> wallpaperShowNotifier = ValueNotifier<bool>(false);
  static const String _wallpaperUrlKey = 'manifest_wallpaper_url';
  static const String _wallpaperShowKey = 'manifest_wallpaper_show';
  static const String _wallpaperLastCheckKey = 'manifest_wallpaper_last_check';
  static const Duration _wallpaperRefreshInterval = Duration(hours: 24);

  static Future<void> initWallpaper() async {
    final prefs = await SharedPreferences.getInstance();
    wallpaperShowNotifier.value = prefs.getBool(_wallpaperShowKey) ?? false;
    wallpaperUrlNotifier.value = prefs.getString(_wallpaperUrlKey);
  }

  // 检查是否需要兜底刷新(超过24小时未检查)
  static Future<bool> needsWallpaperRefresh() async {
    final prefs = await SharedPreferences.getInstance();
    final lastCheck = prefs.getInt(_wallpaperLastCheckKey);
    if (lastCheck == null) return true;
    return DateTime.now().millisecondsSinceEpoch - lastCheck >
        _wallpaperRefreshInterval.inMilliseconds;
  }

  static Future<void> updateWallpaperFromManifest() async {
    final manifest = await checkManifest();
    if (manifest != null) {
      final prefs = await SharedPreferences.getInstance();
      wallpaperShowNotifier.value = manifest.wallpaper.show;
      await prefs.setBool(_wallpaperShowKey, manifest.wallpaper.show);
      if (manifest.wallpaper.show && manifest.wallpaper.imageUrl.isNotEmpty) {
        wallpaperUrlNotifier.value = manifest.wallpaper.imageUrl;
        await prefs.setString(_wallpaperUrlKey, manifest.wallpaper.imageUrl);
      }
      await prefs.setInt(
          _wallpaperLastCheckKey, DateTime.now().millisecondsSinceEpoch);
    }
  }

  // --- 手表端更新维护 ---
  
  /// 检查手表版本并推送给手表 (如果有连接)
  static Future<void> syncBandVersionInfo() async {
    if (!BandSyncService.isInitialized || !BandSyncService.isConnected) return;
    
    // 🚀 核心优化：检查用户是否开启了自动更新功能
    final prefs = await SharedPreferences.getInstance();
    final autoUpdate = prefs.getBool('band_auto_update_enabled') ?? true;
    if (!autoUpdate) {
      debugPrint("🚀 手环自动更新功能已关闭，跳过推送");
      return;
    }
    
    // 获取手机端的 Manifest，里面包含了 changelog_history
    final manifest = await checkManifest(preferCache: true);
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

  // 公告已读状态管理
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

  // 检查是否需要显示公告(考虑已读状态、提醒模式、目标版本)
  static bool shouldShowAnnouncement(
      Announcement announcement, bool isRead, String currentVersion) {
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

  static int _dateTimeToSortKey(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    final ss = dt.second.toString().padLeft(2, '0');
    return int.tryParse('$y$m$d$hh$mm$ss') ?? 0;
  }

  /// 从公告 id 中解析时间片段用于排序。
  /// 支持：
  /// - ann_YYYYMMDD_NNN（按 YYYYMMDD）
  /// - ann_YYYYMMDDHHmm / ann_YYYYMMDDHHmmss
  /// - 10/13 位 Unix 时间戳
  static int parseAnnouncementSortKey(String id) {
    if (id.isEmpty) return 0;

    final unixMs = RegExp(r'(1\d{12})').firstMatch(id)?.group(1);
    if (unixMs != null) {
      final ms = int.tryParse(unixMs);
      if (ms != null) {
        return _dateTimeToSortKey(
            DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true).toLocal());
      }
    }

    final unixSec = RegExp(r'(1\d{9})').firstMatch(id)?.group(1);
    if (unixSec != null) {
      final sec = int.tryParse(unixSec);
      if (sec != null) {
        return _dateTimeToSortKey(
            DateTime.fromMillisecondsSinceEpoch(sec * 1000, isUtc: true)
                .toLocal());
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
      List<Announcement> items) {
    final sorted = List<Announcement>.from(items);
    sorted.sort((a, b) {
      final keyA = parseAnnouncementSortKey(a.id);
      final keyB = parseAnnouncementSortKey(b.id);
      if (keyA != keyB) return keyB.compareTo(keyA);
      return b.id.compareTo(a.id);
    });
    return sorted;
  }

  /// 设置页公告：忽略已读状态，只按 show + target_versions 过滤。
  /// 返回按 id 时间片段降序后的列表，首条即最新公告。
  /// 发生网络/解析异常时返回 null，便于 UI 区分“无公告”和“加载失败”。
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

  // 全局下载状态：脱离UI独立存活，弹窗重开也能接上进度
  static bool _isDownloading = false;
  static double _downloadProgress = 0.0;
  static bool _isDownloaded = false;
  static String? _localPackagePath;
  static StreamSubscription<List<int>>? _downloadSubscription;

  static Function(double)? _uiProgressCallback;
  static Function(String)? _uiCompleteCallback;
  static Function(String)? _uiErrorCallback;

  // 🚀 动态区分 Android 和 Windows 的安装包后缀
  static String getUpdateFileName(String versionName) {
    if (Platform.isWindows) return "MathQuiz_v$versionName.exe";
    return "MathQuiz_v$versionName.apk";
  }

  // 🚀 获取当前设备架构
  static Future<String> getDeviceArchitecture() async {
    if (Platform.isWindows) return 'windows';
    final deviceInfo = DeviceInfoPlugin();
    final androidInfo = await deviceInfo.androidInfo;
    final supportedAbis = androidInfo.supportedAbis;
    if (supportedAbis.contains('arm64-v8a')) return 'arm64-v8a';
    if (supportedAbis.contains('armeabi-v7a')) return 'armeabi-v7a';
    if (supportedAbis.contains('x86_64')) return 'x86_64';
    return supportedAbis.isNotEmpty ? supportedAbis.first : 'arm64-v8a';
  }

  // 🚀 根据设备架构获取对应的下载链接
  static String getDownloadUrlForArch(AppManifest manifest) {
    if (Platform.isWindows && manifest.updateInfo.pcPackageUrl.isNotEmpty) {
      return manifest.updateInfo.pcPackageUrl;
    }
    final archPackages = manifest.updateInfo.androidArchPackages;
    if (archPackages.isNotEmpty) {
      // 返回第一个可用的架构包（通常服务端会按优先级排列）
      return archPackages.values.first;
    }
    return manifest.updateInfo.fullPackageUrl;
  }

  static Future<AppManifest?> _readManifestCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getString(_manifestCacheKey);
      if (cached == null || cached.isEmpty) return null;
      return AppManifest.fromJson(jsonDecode(cached));
    } catch (_) {
      return null;
    }
  }

  static Future<void> _writeManifestCache(String rawJson) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_manifestCacheKey, rawJson);
      await prefs.setInt(
          _manifestCacheTimeKey, DateTime.now().millisecondsSinceEpoch);
    } catch (_) {}
  }

  static Future<AppManifest?> _fetchManifestFromNetwork() async {
    try {
      final response = await http.get(Uri.parse(MANIFEST_URL));
      if (response.statusCode == 200) {
        final body = utf8.decode(response.bodyBytes);
        final manifest = AppManifest.fromJson(jsonDecode(body));
        await _writeManifestCache(body);
        return manifest;
      }
    } catch (_) {}
    return null;
  }

  /// 强制联网刷新 Manifest 缓存。
  /// 默认进行请求去重：已有进行中的请求时复用同一 Future。
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

  /// 启动预热：优先确保本地有可读缓存，同时异步联网更新。
  static Future<void> preloadManifestCache() async {
    final cached = await _readManifestCache();
    if (cached == null) {
      await refreshManifestCache();
      return;
    }
    unawaited(refreshManifestCache());
  }

  /// Manifest 读取策略：默认优先返回本地缓存，同时后台刷新网络。
  /// [preferCache] 为 false 时将优先走网络（如手动检查更新）。
  static Future<AppManifest?> checkManifest(
      {bool preferCache = true, bool refreshInBackground = true}) async {
    if (preferCache) {
      final cached = await _readManifestCache();
      if (cached != null) {
        if (refreshInBackground) {
          unawaited(refreshManifestCache());
        }
        return cached;
      }
    }

    final network = await refreshManifestCache();
    if (network != null) return network;

    return preferCache ? _readManifestCache() : null;
  }

  static Future<String?> isPackageAlreadyDownloaded(String versionName) async {
    final path = await getDownloadDirectory();
    if (path == null) return null;

    final fileName = getUpdateFileName(versionName);
    File file = File("$path/$fileName");

    if (!await file.exists()) {
      final zipFile = File("$path/$fileName.zip");
      if (await zipFile.exists()) file = zipFile;
    }

    if (await file.exists() && await file.length() > 1024 * 1024) {
      return file.path;
    }
    return null;
  }

  static Future<bool> prepareForDownload(String targetVersionName) async {
    // Windows 直接放行，跳过移动端权限申请
    if (!Platform.isAndroid) return true;

    final deviceInfo = DeviceInfoPlugin();
    final androidInfo = await deviceInfo.androidInfo;

    if (androidInfo.version.sdkInt >= 30) {
      if (!await Permission.manageExternalStorage.isGranted) {
        await Permission.manageExternalStorage.request();
      }
    } else {
      if (!await Permission.storage.isGranted) {
        await Permission.storage.request();
      }
    }

    if (!await Permission.requestInstallPackages.isGranted) {
      await Permission.requestInstallPackages.request();
    }

    try {
      final path = await getDownloadDirectory();
      if (path != null) {
        final dir = Directory(path);
        if (await dir.exists()) {
          final List<FileSystemEntity> files = dir.listSync();
          for (var file in files) {
            String name =
                file.path.split(Platform.pathSeparator).last.toLowerCase();
            if (name.endsWith(".apk") ||
                name.endsWith(".exe") ||
                name.endsWith(".zip") ||
                name.endsWith(".download")) {
              await file.delete();
            }
          }
        }
      }
    } catch (e) {}

    return true;
  }

  static Future<String?> getDownloadDirectory() async {
    if (Platform.isAndroid) {
      const String baseDownloadPath = '/storage/emulated/0/Download';
      final String customPath = '$baseDownloadPath/CountdownTodo';
      final customDir = Directory(customPath);

      try {
        if (!await customDir.exists()) await customDir.create(recursive: true);
        return customDir.path;
      } catch (e) {
        final externalDir = await getExternalStorageDirectory();
        return externalDir?.path;
      }
    }

    // Windows 获取系统 Downloads 文件夹
    final downloadDir = await getDownloadsDirectory();
    if (downloadDir != null) {
      final customDir = Directory('${downloadDir.path}/CountdownTodo');
      if (!await customDir.exists()) await customDir.create(recursive: true);
      return customDir.path;
    }
    return null;
  }

  static Future<void> installPackage(String filePath) async {
    File file = File(filePath);

    if (!await file.exists()) {
      final zipFile = File("$filePath.zip");
      if (await zipFile.exists()) {
        file = await zipFile.rename(filePath);
      } else {
        if (filePath.endsWith(".zip")) {
          final apkPath = filePath.substring(0, filePath.length - 4);
          file = await file.rename(apkPath);
        } else {
          return;
        }
      }
    } else {
      if (filePath.endsWith(".zip")) {
        final apkPath = filePath.substring(0, filePath.length - 4);
        file = await file.rename(apkPath);
      }
    }

    if (Platform.isWindows) {
      await Process.run(file.path, [], runInShell: true);
      return;
    }

    await OpenFile.open(
      file.path,
      type:
          Platform.isAndroid ? "application/vnd.android.package-archive" : null,
    );
  }

  static Future<void> checkUpdateAndPrompt(BuildContext context,
      {bool isManual = false}) async {
    if (_isDialogShowing) return;

    AppManifest? manifest = await checkManifest(
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

    PackageInfo packageInfo = await PackageInfo.fromPlatform();
    String localVersion = packageInfo.version;

    bool hasUpdate = false;
    try {
      // 🚀 核心修复：纯三位数版本号对比，不依赖任何 BuildNumber 和 versionCode
      String cleanManifestVersion =
          manifest.versionName.split('+')[0].split('-')[0];
      String cleanLocalVersion = localVersion.split('+')[0].split('-')[0];

      List<int> v1 = cleanManifestVersion
          .split('.')
          .map((e) => int.tryParse(e) ?? 0)
          .toList();
      List<int> v2 = cleanLocalVersion
          .split('.')
          .map((e) => int.tryParse(e) ?? 0)
          .toList();

      int maxLen = v1.length > v2.length ? v1.length : v2.length;
      bool isVersionDifferent = false;

      for (int i = 0; i < maxLen; i++) {
        int p1 = i < v1.length ? v1[i] : 0;
        int p2 = i < v2.length ? v2[i] : 0;

        if (p1 > p2) {
          hasUpdate = true;
          isVersionDifferent = true;
          break;
        } else if (p1 < p2) {
          hasUpdate = false;
          isVersionDifferent = true;
          break;
        }
      }

      // 如果 versionName 字符串一致，绝对禁止误判更新
      if (!isVersionDifferent) {
        hasUpdate = false;
      }
    } catch (e) {
      hasUpdate = false;
    }

    // 筛选需要显示的公告
    List<Announcement> announcementsToShow = [];
    for (var ann in manifest.announcements) {
      if (!ann.show) continue;
      bool annRead = await isAnnouncementRead(ann.id);
      if (shouldShowAnnouncement(ann, annRead, localVersion)) {
        announcementsToShow.add(ann);
      }
    }
    bool hasNotice = announcementsToShow.isNotEmpty;

    if (!hasUpdate && !hasNotice) {
      if (isManual && context.mounted) {
        showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
                    title: const Text("检查完成"),
                    content: Text("当前版本 ($localVersion) 已是最新。"),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: const Text("好"))
                    ]));
      }
      return;
    }

    if (context.mounted) {
      if (hasNotice) {
        showAnnouncementDialog(context, announcementsToShow, () {
          if (hasUpdate && context.mounted) {
            showUpdateDialog(context, manifest, localVersion,
                hasUpdate: true, hasNotice: false);
          }
        });
      } else if (hasUpdate) {
        showUpdateDialog(context, manifest, localVersion,
            hasUpdate: true, hasNotice: false);
      }
    }
  }

  // 🚀 新增：专为 WebSocket 推送设计的更新触发器，直接复用现有的弹窗和下载逻辑
  static Future<void> triggerWebSocketUpdate(
    BuildContext context, {
    required String latestVersion,
    required String releaseNotes,
    required String downloadUrl,
  }) async {
    if (_isDialogShowing) return;

    PackageInfo packageInfo = await PackageInfo.fromPlatform();
    String localVersion = packageInfo.version;

    // 核心版本对比逻辑（提取出来复用）
    bool hasUpdate = _compareVersions(latestVersion, localVersion);

    if (!hasUpdate) return;

    // 🚀 偷梁换柱：用 WebSocket 发来的直链数据，动态组装一个虚拟的 AppManifest
    // 这样就能完美欺骗 showUpdateDialog，让它以为这是从 GitHub 抓下来的
    AppManifest mockManifest = AppManifest(
      versionCode: 0,
      versionName: latestVersion,
      forceUpdate: false,
      updateInfo: UpdateInfo.fromJson({
        'title': '发现新版本 $latestVersion',
        'description': releaseNotes,
        'full_package_url': downloadUrl,
        'PC_package_url': downloadUrl,
      }),
      announcements: [],
      wallpaper: WallpaperConfig.fromJson({'show': false}),
    );

    if (context.mounted) {
      // 完美复用你原有的精美更新弹窗和底层下载框架！
      showUpdateDialog(context, mockManifest, localVersion,
          hasUpdate: true, hasNotice: false);
    }
  }

  // 🚀 提取出来的纯净版本号对比算法
  static bool _compareVersions(String manifestVersion, String localVersion) {
    try {
      String cleanManifestVersion = manifestVersion.split('+')[0].split('-')[0];
      String cleanLocalVersion = localVersion.split('+')[0].split('-')[0];

      List<int> v1 = cleanManifestVersion
          .split('.')
          .map((e) => int.tryParse(e) ?? 0)
          .toList();
      List<int> v2 = cleanLocalVersion
          .split('.')
          .map((e) => int.tryParse(e) ?? 0)
          .toList();

      int maxLen = v1.length > v2.length ? v1.length : v2.length;
      for (int i = 0; i < maxLen; i++) {
        int p1 = i < v1.length ? v1[i] : 0;
        int p2 = i < v2.length ? v2[i] : 0;
        if (p1 > p2) return true;
        if (p1 < p2) return false;
      }
    } catch (_) {}
    return false;
  }

  static Future<void> showAnnouncementDialog(BuildContext context,
      List<Announcement> announcements, VoidCallback? onDismissed) async {
    if (_isAnnouncementDialogShowing) return;
    if (announcements.isEmpty) return;
    _isAnnouncementDialogShowing = true;

    if (!context.mounted) {
      _isAnnouncementDialogShowing = false;
      return;
    }

    await showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        return _AnnouncementCarouselDialog(
          announcements: announcements,
        );
      },
    );

    _isAnnouncementDialogShowing = false;
    onDismissed?.call();
  }

  static Future<void> showUpdateDialog(
      BuildContext context, AppManifest manifest, String currentVersion,
      {bool hasUpdate = true, bool hasNotice = false}) async {
    if (_isDialogShowing) return;
    _isDialogShowing = true;

    if (!_isDownloading && !_isDownloaded) {
      String? existingPath =
          await isPackageAlreadyDownloaded(manifest.versionName);
      if (existingPath != null) {
        _isDownloaded = true;
        _localPackagePath = existingPath;
      }
    }

    if (!context.mounted) {
      _isDialogShowing = false;
      return;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return PopScope(
          canPop: !manifest.forceUpdate,
          child: StatefulBuilder(
              builder: (BuildContext context, StateSetter setState) {
            _uiProgressCallback = (p) {
              if (context.mounted) setState(() {});
            };
            _uiCompleteCallback = (path) {
              if (context.mounted) setState(() {});
            };
            _uiErrorCallback = (err) {
              if (context.mounted) {
                setState(() {});
                ScaffoldMessenger.of(ctx)
                    .showSnackBar(SnackBar(content: Text(err)));
              }
            };

            return AlertDialog(
              contentPadding: EdgeInsets.zero,
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (manifest.wallpaper.show &&
                        manifest.wallpaper.imageUrl.isNotEmpty)
                      ClipRRect(
                          borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(20)),
                          child: CachedNetworkImage(
                            imageUrl: manifest.wallpaper.imageUrl,
                            height: 200,
                            fit: BoxFit.cover,
                            errorWidget: (context, url, error) =>
                                Container(color: Colors.grey[200]),
                          )),
                    Padding(
                      padding: const EdgeInsets.all(20.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (hasUpdate) ...[
                            Row(children: [
                              const Icon(Icons.new_releases,
                                  color: Colors.blue),
                              const SizedBox(width: 8),
                              Text(manifest.updateInfo.title,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 18))
                            ]),
                            const SizedBox(height: 6),
                            Text(
                                "当前: $currentVersion  →  最新: ${manifest.versionName}",
                                style: const TextStyle(
                                    fontSize: 12,
                                    color: Colors.blue,
                                    fontWeight: FontWeight.bold)),
                            const SizedBox(height: 10),
                            Text(manifest.updateInfo.description),
                            const SizedBox(height: 20),
                            if (manifest.updateInfo.fullPackageUrl.isNotEmpty)
                              if (_isDownloaded)
                                Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    // 🚀 核心防崩区域：安全地保留纯 Text，禁止外部包裹任何 Expanded/Flexible
                                    ElevatedButton.icon(
                                      icon: const Icon(Icons.system_update),
                                      label: const Text("下载完成，立即安装",
                                          overflow: TextOverflow.ellipsis),
                                      style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.green,
                                          foregroundColor: Colors.white),
                                      onPressed: () {
                                        if (_localPackagePath != null) {
                                          installPackage(_localPackagePath!);
                                        }
                                      },
                                    ),
                                    TextButton(
                                      onPressed: () {
                                        if (_isDownloading) return;
                                        setState(() {});
                                        _startForegroundDownload(manifest);
                                      },
                                      child: const Text("安装失败？点击强制重新下载",
                                          style: TextStyle(
                                              color: Colors.grey,
                                              fontSize: 13,
                                              decoration:
                                                  TextDecoration.underline)),
                                    )
                                  ],
                                )
                              else if (_isDownloading)
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        const Text("正在下载更新包...",
                                            style: TextStyle(
                                                fontSize: 13,
                                                color: Colors.grey)),
                                        Text(
                                            "${(_downloadProgress * 100).toStringAsFixed(1)}%",
                                            style: const TextStyle(
                                                fontSize: 13,
                                                color: Colors.blue,
                                                fontWeight: FontWeight.bold)),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(8),
                                      child: LinearProgressIndicator(
                                        value: _downloadProgress,
                                        minHeight: 12,
                                        backgroundColor: Colors.grey[200],
                                        valueColor:
                                            const AlwaysStoppedAnimation<Color>(
                                                Colors.blueAccent),
                                      ),
                                    ),
                                  ],
                                )
                              else
                                SizedBox(
                                  width: double.infinity,
                                  child: ElevatedButton.icon(
                                      icon: const Icon(Icons.download),
                                      label: const Text("立即下载新版本",
                                          overflow: TextOverflow.ellipsis),
                                      onPressed: () {
                                        if (_isDownloading) return;
                                        setState(() {});
                                        _startForegroundDownload(manifest);
                                      }),
                                ),
                            if (hasNotice) const Divider(height: 30),
                          ],
                        ],
                      ),
                    )
                  ],
                ),
              ),
              actions: [
                if (!manifest.forceUpdate)
                  TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: Text(
                          _isDownloading
                              ? "后台下载"
                              : (_isDownloaded ? "关闭" : "稍后再说"),
                          style: const TextStyle(color: Colors.grey))),
              ],
            );
          }),
        );
      },
    ).then((_) {
      _isDialogShowing = false;
      _uiProgressCallback = null;
      _uiCompleteCallback = null;
      _uiErrorCallback = null;
    });
  }

  static Future<void> _startForegroundDownload(AppManifest manifest) async {
    await _downloadSubscription?.cancel();

    _isDownloading = true;
    _isDownloaded = false;
    _downloadProgress = 0.0;
    _uiProgressCallback?.call(0.0);

    bool ready = await prepareForDownload(manifest.versionName);
    if (!ready) {
      _isDownloading = false;
      _uiErrorCallback?.call("准备下载环境失败，请检查存储权限");
      return;
    }

    final path = await getDownloadDirectory();
    if (path == null) {
      _isDownloading = false;
      _uiErrorCallback?.call("无法获取下载保存目录");
      return;
    }

    String fileName = getUpdateFileName(manifest.versionName);
    String savePath = "$path/$fileName";
    String tempPath = "$savePath.download";
    File tempFile = File(tempPath);

    final String downloadUrl = getDownloadUrlForArch(manifest);

    try {
      var client = HttpClient();
      var request = await client.getUrl(Uri.parse(downloadUrl));
      var response = await request.close();

      if (response.statusCode == 200) {
        int totalBytes = response.contentLength;
        int receivedBytes = 0;
        var sink = tempFile.openWrite();

        _downloadSubscription = response.listen(
          (List<int> chunk) {
            receivedBytes += chunk.length;
            sink.add(chunk);
            if (totalBytes > 0) {
              _downloadProgress = receivedBytes / totalBytes;
              _uiProgressCallback?.call(_downloadProgress);
            }
          },
          onDone: () async {
            await sink.close();
            File finalFile = await tempFile.rename(savePath);

            _isDownloading = false;
            _isDownloaded = true;
            _localPackagePath = finalFile.path;

            _uiCompleteCallback?.call(finalFile.path);
          },
          onError: (e) async {
            await sink.close();
            _isDownloading = false;
            _uiErrorCallback?.call("下载连接中断: $e");
          },
          cancelOnError: true,
        );
      } else {
        _isDownloading = false;
        _uiErrorCallback?.call("服务器响应异常: HTTP ${response.statusCode}");
      }
    } catch (e) {
      _isDownloading = false;
      _uiErrorCallback?.call("网络请求发生异常: $e");
    }
  }
}
