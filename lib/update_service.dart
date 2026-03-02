import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_downloader/flutter_downloader.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:open_file/open_file.dart';

// 数据模型类：映射服务器端的 update_manifest.json 结构
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
  // 云端更新配置文件地址
  static const String MANIFEST_URL = "https://raw.githubusercontent.com/Junpgle/CountdownTodo/refs/heads/master/update_manifest.json";

  // 1. 检查并获取配置对象
  static Future<AppManifest?> checkManifest() async {
    try {
      final response = await http.get(Uri.parse(MANIFEST_URL));
      if (response.statusCode == 200) {
        String body = utf8.decode(response.bodyBytes);
        return AppManifest.fromJson(jsonDecode(body));
      }
    } catch (e) {
      print("获取更新配置失败: $e");
    }
    return null;
  }

  // 2. 获取下载目录：强制定位至 Android 公共 Download 目录
  static Future<String?> getDownloadDirectory() async {
    if (Platform.isAndroid) {
      // 这里的路径是安卓的标准公共下载目录
      const String downloadPath = '/storage/emulated/0/Download';
      final directory = Directory(downloadPath);
      if (await directory.exists()) {
        return downloadPath;
      }
      // 如果上述路径不可用，回退到应用外部目录
      final externalDir = await getExternalStorageDirectory();
      return externalDir?.path;
    } else {
      final downloadDir = await getDownloadsDirectory();
      return downloadDir?.path;
    }
  }

  // 3. 核心修复：调用系统包管理器安装 APK
  static Future<void> installApk(String filePath) async {
    final file = File(filePath);
    if (await file.exists()) {
      print("准备安装 APK，路径: $filePath");
      // 显式指定 type，防止弹出“打开方式”选择框
      final result = await OpenFile.open(
        filePath,
        type: "application/vnd.android.package-archive",
      );
      print("安装唤起结果: ${result.message}");
    } else {
      print("安装失败：找不到文件 $filePath");
    }
  }

  static Future<void> launchURL(String url) async {
    final Uri uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      throw '无法打开下载链接 $url';
    }
  }
}