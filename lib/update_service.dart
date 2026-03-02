import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_downloader/flutter_downloader.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:open_file/open_file.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:cached_network_image/cached_network_image.dart';

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

    // 我们要写入公共目录的子文件夹，所以必须请求权限
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
        return customDir.path; // 成功返回 /storage/emulated/0/Download/CountdownTodo
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

  // =========================================================================
  // 👉 提取的公共逻辑：自动检查更新与公告并弹窗 (首页与设置页通用)
  // =========================================================================
  static Future<void> checkUpdateAndPrompt(BuildContext context, {bool isManual = false}) async {
    AppManifest? manifest = await checkManifest();
    if (manifest == null) {
      if (isManual && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('检查失败，请检查网络')));
      }
      return;
    }

    PackageInfo packageInfo = await PackageInfo.fromPlatform();
    int localBuild = int.tryParse(packageInfo.buildNumber) ?? 0;
    String localVersion = packageInfo.version;

    bool hasUpdate = false;
    try {
      // 智能比对点分十进制版本号 (例如 1.4.8 -> 1.4.9)
      List<int> v1 = manifest.versionName.split('.').map(int.parse).toList();
      List<int> v2 = localVersion.split('.').map(int.parse).toList();
      int minLen = v1.length < v2.length ? v1.length : v2.length;
      bool isVersionDifferent = false;

      for (int i = 0; i < minLen; i++) {
        if (v1[i] > v2[i]) {
          hasUpdate = true;
          isVersionDifferent = true;
          break;
        } else if (v1[i] < v2[i]) {
          hasUpdate = false;
          isVersionDifferent = true;
          break;
        }
      }

      // 如果前面都一样，对比 versionCode
      if (!isVersionDifferent) {
        hasUpdate = manifest.versionCode > localBuild;
      }
    } catch (e) {
      hasUpdate = manifest.versionCode > localBuild;
    }

    bool hasNotice = manifest.announcement.show;

    if (!hasUpdate && !hasNotice) {
      if (isManual && context.mounted) {
        showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
                title: const Text("检查完成"),
                content: Text("当前版本 ($localVersion) 已是最新。"),
                actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("好"))]
            )
        );
      }
      return;
    }

    if (context.mounted) {
      showUpdateDialog(context, manifest, localVersion, hasUpdate: hasUpdate, hasNotice: hasNotice);
    }
  }

  // =========================================================================
  // 👉 提取的公共 UI 方法：展示更新弹窗
  // =========================================================================
  static void showUpdateDialog(BuildContext context, AppManifest manifest, String currentVersion, {bool hasUpdate = true, bool hasNotice = false}) {
    showDialog(
      context: context,
      barrierDismissible: !manifest.forceUpdate,
      builder: (ctx) {
        return AlertDialog(
          contentPadding: EdgeInsets.zero,
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (manifest.wallpaper.show && manifest.wallpaper.imageUrl.isNotEmpty)
                  ClipRRect(
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                      child: CachedNetworkImage(
                        imageUrl: manifest.wallpaper.imageUrl,
                        height: 200,
                        fit: BoxFit.cover,
                        errorWidget: (context, url, error) => Container(color: Colors.grey[200]),
                      )
                  ),
                Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (hasUpdate) ...[
                        Row(
                            children: [
                              const Icon(Icons.new_releases, color: Colors.blue),
                              const SizedBox(width: 8),
                              Text(manifest.updateInfo.title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18))
                            ]
                        ),
                        const SizedBox(height: 6),
                        Text("当前: $currentVersion  →  最新: ${manifest.versionName}", style: const TextStyle(fontSize: 12, color: Colors.blue, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 10),
                        Text(manifest.updateInfo.description),
                        const SizedBox(height: 15),
                        if (manifest.updateInfo.fullPackageUrl.isNotEmpty)
                          ElevatedButton.icon(
                              icon: const Icon(Icons.download),
                              label: const Text("立即安装新版本"),
                              onPressed: () {
                                Navigator.pop(ctx); // 点击下载后关闭弹窗
                                startDownload(context, manifest); // 调用统一的下载逻辑
                              }
                          ),
                        if (hasNotice) const Divider(height: 30),
                      ],
                      if (hasNotice) ...[
                        Row(
                            children: [
                              const Icon(Icons.campaign, color: Colors.orange),
                              const SizedBox(width: 8),
                              Text(manifest.announcement.title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18))
                            ]
                        ),
                        const SizedBox(height: 8),
                        Text(manifest.announcement.content),
                      ]
                    ],
                  ),
                )
              ],
            ),
          ),
          actions: [
            if (!manifest.forceUpdate)
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("关闭"))
          ],
        );
      },
    );
  }

  // =========================================================================
  // 👉 提取的公共逻辑：处理下载前置检查和发起下载
  // =========================================================================
  static Future<void> startDownload(BuildContext context, AppManifest manifest) async {
    // 1. 先检查是否已经下载过这个版本的完整包
    String? existingPath = await isApkAlreadyDownloaded(manifest.versionName);

    if (existingPath != null) {
      print("检测到本地已存在完整安装包，直接安装");
      await installApk(existingPath);
      return;
    }

    // 2. 如果没有，则准备环境（清理旧版本包并请求权限）
    bool ready = await prepareForDownload(manifest.versionName);
    if (!ready) return;

    final path = await getDownloadDirectory();
    if (path == null) return;

    // 3. 执行真正的下载
    await FlutterDownloader.enqueue(
      url: manifest.updateInfo.fullPackageUrl,
      savedDir: path, // 路径指向 /storage/emulated/0/Download/CountdownTodo
      fileName: getUpdateFileName(manifest.versionName),
      showNotification: true,
      openFileFromNotification: false,
      // 💡 核心修复：这里必须设为 false ！！！
      // 设为 false 后，下载器不再调用 MediaStore（媒体库会无视子目录强制放入 Download 根目录）
      // 而是直接使用我们申请好的 MANAGE_EXTERNAL_STORAGE 权限，把文件写入 savedDir 制定的子目录里。
      saveInPublicStorage: false,
    );

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("正在后台下载更新，完成后将自动弹出安装界面..."))
      );
    }
  }
}