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

  // 生成基于版本号的文件名，确保唯一性
  static String getUpdateFileName(String versionName) => "MathQuiz_v$versionName.apk";

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

  /// 检查特定版本的安装包是否已经完整下载到本地
  static Future<String?> isApkAlreadyDownloaded(String versionName) async {
    final path = await getDownloadDirectory();
    if (path == null) return null;

    final fileName = getUpdateFileName(versionName);
    File file = File("$path/$fileName");

    // 如果正常的 apk 找不到，看看有没有被加了 .zip 后缀的
    if (!await file.exists()) {
      final zipFile = File("$path/$fileName.zip");
      if (await zipFile.exists()) {
        file = zipFile; // 如果有 zip，就检查这个 zip 的大小
      }
    }

    if (await file.exists()) {
      if (await file.length() > 1024 * 1024) { // 大于 1MB 认为完整
        return file.path;
      }
    }
    return null;
  }

  /// 1. 环境准备：清理旧版本残留包，并仅请求安装权限
  static Future<bool> prepareForDownload(String targetVersionName) async {
    if (!Platform.isAndroid) return true;

    // 因为我们要写入公共目录，所以还是需要请求存储权限
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

    // 强力物理清理：扫描指定目录，删除所有“非本次版本”的安装包
    try {
      final path = await getDownloadDirectory();
      if (path != null) {
        final dir = Directory(path);
        if (await dir.exists()) {
          final List<FileSystemEntity> files = dir.listSync();
          final targetFileName = getUpdateFileName(targetVersionName);

          for (var file in files) {
            String name = file.path.split(Platform.pathSeparator).last;
            // 清理旧版本包 (包含 .apk 和 .apk.zip)
            if (name.startsWith("MathQuiz_v") && !name.contains(targetFileName)) {
              print("发现旧版本包，正在物理删除: ${file.path}");
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

  /// 2. 获取公开下载目录中的专属文件夹
  static Future<String?> getDownloadDirectory() async {
    if (Platform.isAndroid) {
      // 尝试在公共 Download 目录下创建 CountdownTodo 文件夹
      const String baseDownloadPath = '/storage/emulated/0/Download';
      final String customPath = '$baseDownloadPath/CountdownTodo';
      final customDir = Directory(customPath);

      try {
        if (!await customDir.exists()) {
          await customDir.create(recursive: true);
        }
        return customDir.path;
      } catch (e) {
        print("创建公开专属目录失败，回退到私有目录: $e");
        // 如果因为权限或其他原因创建失败，回退到应用专属外部目录
        final externalDir = await getExternalStorageDirectory();
        return externalDir?.path;
      }
    }

    // 非 Android 平台逻辑
    final downloadDir = await getDownloadsDirectory();
    if (downloadDir != null) {
      final customDir = Directory('${downloadDir.path}/CountdownTodo');
      if (!await customDir.exists()) {
        await customDir.create(recursive: true);
      }
      return customDir.path;
    }
    return null;
  }

  /// 3. 安装唤起：处理恶心的 .zip 后缀，精准匹配 MIME 拉起安装器
  static Future<void> installApk(String filePath) async {
    File file = File(filePath);

    // 💡 终极杀招：检查文件到底叫什么，并强制重命名回 .apk
    if (!await file.exists()) {
      // 假设我们传进来的是 .apk，但实际被存成了 .apk.zip
      final zipFile = File("$filePath.zip");
      if (await zipFile.exists()) {
        print("检测到该死的 .zip 后缀，正在强制改回 .apk ...");
        file = await zipFile.rename(filePath); // 改名回原本的 .apk
      } else {
        // 反过来：假设传进来的是 .apk.zip，把它改成 .apk
        if (filePath.endsWith(".zip")) {
          final apkPath = filePath.substring(0, filePath.length - 4); // 去掉 .zip
          print("收到 .zip 路径，正在重命名为纯正的 APK: $apkPath");
          file = await file.rename(apkPath);
        } else {
          print("安装失败：找不到文件 $filePath，连 .zip 也没有。");
          return;
        }
      }
    } else {
      // 如果文件存在，但后缀是 .zip，也要改掉它，否则安装器不认
      if (filePath.endsWith(".zip")) {
        final apkPath = filePath.substring(0, filePath.length - 4);
        print("文件存在，但带着 .zip 尾巴，正在重命名...");
        file = await file.rename(apkPath);
      }
    }

    print("正在唤起包管理器安装，文件路径: ${file.path}，大小: ${await file.length()} 字节");

    // 唤起安装
    final result = await OpenFile.open(
      file.path,
      type: "application/vnd.android.package-archive",
    );

    print("安装唤起结果: ${result.message}");
  }

  static Future<void> launchURL(String url) async {
    final Uri uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      throw '无法打开链接 $url';
    }
  }
}