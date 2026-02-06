import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

// 数据模型类
class AppManifest {
  final int versionCode;
  final String versionName;
  final bool forceUpdate;
  final UpdateInfo updateInfo;
  final Announcement announcement;
  final WallpaperConfig wallpaper;

  AppManifest({
    required this.versionCode,
    required this.versionName,
    required this.forceUpdate,
    required this.updateInfo,
    required this.announcement,
    required this.wallpaper,
  });

  factory AppManifest.fromJson(Map<String, dynamic> json) {
    return AppManifest(
      versionCode: json['version_code'] ?? 0,
      versionName: json['version_name'] ?? '',
      forceUpdate: json['force_update'] ?? false,
      updateInfo: UpdateInfo.fromJson(json['update_info'] ?? {}),
      announcement: Announcement.fromJson(json['announcement'] ?? {}),
      wallpaper: WallpaperConfig.fromJson(json['wallpaper'] ?? {}),
    );
  }
}

class UpdateInfo {
  final String title;
  final String description;
  final String fullPackageUrl;
  final String patchPackageUrl;

  UpdateInfo.fromJson(Map<String, dynamic> json)
      : title = json['title'] ?? '版本更新',
        description = json['description'] ?? '',
        fullPackageUrl = json['full_package_url'] ?? '',
        patchPackageUrl = json['patch_package_url'] ?? '';
}

class Announcement {
  final bool show;
  final String title;
  final String content;

  Announcement.fromJson(Map<String, dynamic> json)
      : show = json['show'] ?? false,
        title = json['title'] ?? '',
        content = json['content'] ?? '';
}

class WallpaperConfig {
  final bool show;
  final String imageUrl;

  WallpaperConfig.fromJson(Map<String, dynamic> json)
      : show = json['show'] ?? false,
        imageUrl = json['image_url'] ?? '';
}

class UpdateService {
  // 替换成你真实的 GitHub Raw URL
  static const String MANIFEST_URL = "https://raw.githubusercontent.com/Junpgle/math_quiz_app/refs/heads/master/update_manifest.json";

  // 检查并获取配置
  static Future<AppManifest?> checkManifest() async {
    try {
      final response = await http.get(Uri.parse(MANIFEST_URL));
      if (response.statusCode == 200) {
        // 防止中文乱码
        String body = utf8.decode(response.bodyBytes);
        return AppManifest.fromJson(jsonDecode(body));
      }
    } catch (e) {
      print("Fetch manifest failed: $e");
    }
    return null;
  }

  // 获取当前版本号
  static Future<int> getCurrentBuildNumber() async {
    PackageInfo packageInfo = await PackageInfo.fromPlatform();
    // pubspec.yaml 中的 version: 1.0.0，这里获取的是 + 号后面的数字
    return int.tryParse(packageInfo.buildNumber) ?? 0;
  }

  // 打开浏览器下载
  static Future<void> launchURL(String url) async {
    final Uri uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      throw 'Could not launch $url';
    }
  }
}