import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_downloader/flutter_downloader.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:open_file/open_file.dart';
import 'package:device_info_plus/device_info_plus.dart';

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

  UpdateInfo.fromJson(Map<String, dynamic> json)
      : title = json['title'] ?? '版本更新',
        description = json['description'] ?? '',
        fullPackageUrl = json['full_package_url'] ?? '';
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
  static const String MANIFEST_URL = "https://raw.githubusercontent.com/Junpgle/CountdownTodo/refs/heads/master/update_manifest.json";

  // 强制固定文件名，不带任何后缀变体
  static const String UPDATE_FILE_NAME = "MathQuiz_Update.apk";

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

  /// 1. 环境准备：物理清理所有可能的冲突文件
  static Future<bool> prepareForDownload() async {
    if (!Platform.isAndroid) return true;

    // A. 权限请求
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

    // B. 👉 彻底清理：删除 .apk, .apk.zip, .apk.1 等所有残留 👈
    try {
      final path = await getDownloadDirectory();
      if (path != null) {
        final dir = Directory(path);
        if (await dir.exists()) {
          final List<FileSystemEntity> files = dir.listSync();
          for (var file in files) {
            if (file is File && file.path.contains("MathQuiz_Update")) {
              print("发现冲突文件，正在物理删除: ${file.path}");
              await file.delete();
            }
          }
        }
      }
    } catch (e) {
      print("预清理旧文件失败: $e");
    }

    return true;
  }

  /// 2. 获取公共下载目录
  static Future<String?> getDownloadDirectory() async {
    if (Platform.isAndroid) {
      final directory = Directory('/storage/emulated/0/Download/CountDownTodo');
      if (await directory.exists()) {
        return directory.path;
      }
      final externalDir = await getExternalStorageDirectory();
      return externalDir?.path;
    }
    final downloadDir = await getDownloadsDirectory();
    return downloadDir?.path;
  }

  /// 3. 核心修复：显式调用安装程序并强制 MIME
  static Future<void> installApk(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) {
      // 容错处理：如果系统还是偷偷加了 .zip 后缀
      final zipFile = File("$filePath.zip");
      if (await zipFile.exists()) {
        print("检测到系统自动添加了 .zip 后缀，正在重命名还原...");
        await zipFile.rename(filePath);
      } else {
        print("安装失败：找不到文件 $filePath");
        return;
      }
    }

    print("正在唤起安装程序: $filePath");

    // 指定精确 MIME 类型：跳过打开方式选择，直接进入安装确认
    final result = await OpenFile.open(
      filePath,
      type: "application/vnd.android.package-archive",
    );

    print("OpenFile 结果: ${result.message}");
  }

  static Future<void> launchURL(String url) async {
    final Uri uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      throw '无法打开链接 $url';
    }
  }
}