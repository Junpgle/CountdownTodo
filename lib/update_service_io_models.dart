part of 'update_service_io.dart';

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
        Announcement.fromJson(json['announcement'] as Map<String, dynamic>),
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
      changelogArchive: ChangelogArchiveConfig.fromJson(
        json['changelog_archive'] ?? {},
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
  final String fullPackageSha256;
  final String pcPackageSha256;
  final String macPackageSha256;
  final Map<String, String> macArchPackages;
  final Map<String, String> macArchSha256;
  final Map<String, String> androidArchPackages;
  final Map<String, String> androidArchSha256;
  final Map<String, List<AndroidDeltaPackage>> androidDeltaPackages;

  UpdateInfo.fromJson(Map<String, dynamic> json)
    : title = json['title'] ?? '版本更新',
      description = json['description'] ?? '',
      fullPackageUrl = json['full_package_url'] ?? '',
      pcPackageUrl = json['PC_package_url'] ?? '',
      macPackageUrl = json['mac_package_url'] ?? '',
      fullPackageSha256 = json['full_package_sha256']?.toString().trim() ?? '',
      pcPackageSha256 =
          (json['PC_package_sha256'] ?? json['pc_package_sha256'])
              ?.toString()
              .trim() ??
          '',
      macPackageSha256 = json['mac_package_sha256']?.toString().trim() ?? '',
      macArchPackages = json['mac_arch_packages'] != null
          ? Map<String, String>.from(json['mac_arch_packages'])
          : {},
      macArchSha256 = json['mac_arch_sha256'] != null
          ? Map<String, String>.from(json['mac_arch_sha256'])
          : {},
      androidArchPackages = json['android_arch_packages'] != null
          ? Map<String, String>.from(json['android_arch_packages'])
          : {},
      androidArchSha256 = json['android_arch_sha256'] != null
          ? Map<String, String>.from(json['android_arch_sha256'])
          : {},
      androidDeltaPackages = _parseAndroidDeltaPackages(
        json['android_delta_packages'],
      );

  static Map<String, List<AndroidDeltaPackage>> _parseAndroidDeltaPackages(
    dynamic raw,
  ) {
    if (raw is! Map) return {};

    final result = <String, List<AndroidDeltaPackage>>{};
    raw.forEach((key, value) {
      if (value is! List) return;
      final packages = value
          .whereType<Map>()
          .map(
            (entry) =>
                AndroidDeltaPackage.fromJson(Map<String, dynamic>.from(entry)),
          )
          .where((entry) => entry.isUsable)
          .toList();
      if (packages.isNotEmpty) {
        result[key.toString()] = packages;
      }
    });
    return result;
  }
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
      targetVersions =
          (json['target_versions'] as List<dynamic>?)
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

class _UpdateArtifact {
  final String url;
  final String fileName;
  final AndroidDeltaPackage? delta;
  final String? baseApkPath;
  final String? expectedSha256;

  const _UpdateArtifact({
    required this.url,
    required this.fileName,
    this.delta,
    this.baseApkPath,
    this.expectedSha256,
  });

  bool get isDelta => delta != null;
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
