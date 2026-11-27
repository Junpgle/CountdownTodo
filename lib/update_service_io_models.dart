part of 'update_service_io.dart';

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
