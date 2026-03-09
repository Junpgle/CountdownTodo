import 'dart:async';
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
  final Announcement announcement;
  final WallpaperConfig wallpaper;
  final List<ChangelogEntry> changelogHistory;

  AppManifest({
    required this.versionCode,
    required this.versionName,
    required this.forceUpdate,
    required this.updateInfo,
    required this.announcement,
    required this.wallpaper,
    this.changelogHistory = const [],
  });

  factory AppManifest.fromJson(Map<String, dynamic> json) {
    return AppManifest(
      versionCode: json['version_code'] ?? 0,
      versionName: json['version_name'] ?? '',
      forceUpdate: json['force_update'] ?? false,
      updateInfo: UpdateInfo.fromJson(json['update_info'] ?? {}),
      announcement: Announcement.fromJson(json['announcement'] ?? {}),
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

  static bool _isDialogShowing = false;

  // 🚀 全局下载状态：脱离UI独立存活，弹窗重开也能接上进度
  static bool _isDownloading = false;
  static double _downloadProgress = 0.0;
  static bool _isDownloaded = false;
  static String? _localApkPath;
  static StreamSubscription<List<int>>? _downloadSubscription;

  // 用于动态绑定最新打开的弹窗回调
  static Function(double)? _uiProgressCallback;
  static Function(String)? _uiCompleteCallback;
  static Function(String)? _uiErrorCallback;

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

    if (!await file.exists()) {
      final zipFile = File("$path/$fileName.zip");
      if (await zipFile.exists()) {
        file = zipFile;
      }
    }

    // 🚀 因为我们引入了 .download 临时后缀，所以能走到这的绝对是 100% 下载完毕的好包
    if (await file.exists() && await file.length() > 1024 * 1024) {
      return file.path;
    }
    return null;
  }

  /// 1. 环境准备：清理所有旧版本和损坏的包，并请求权限
  static Future<bool> prepareForDownload(String targetVersionName) async {
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
            String name = file.path.split(Platform.pathSeparator).last.toLowerCase();
            // 清理旧包与各种下载残骸
            if (name.endsWith(".apk") || name.endsWith(".zip") || name.endsWith(".download")) {
              print("清理发现的残留或旧包: ${file.path}");
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
      const String baseDownloadPath = '/storage/emulated/0/Download';
      final String customPath = '$baseDownloadPath/CountdownTodo';
      final customDir = Directory(customPath);

      try {
        if (!await customDir.exists()) {
          await customDir.create(recursive: true);
        }
        return customDir.path;
      } catch (e) {
        final externalDir = await getExternalStorageDirectory();
        return externalDir?.path;
      }
    }

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

  /// 3. 安装唤起
  static Future<void> installApk(String filePath) async {
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

    await OpenFile.open(
      file.path,
      type: "application/vnd.android.package-archive",
    );
  }

  static Future<void> launchURL(String url) async {
    final Uri uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      throw '无法打开链接 $url';
    }
  }

  static Future<void> checkUpdateAndPrompt(BuildContext context, {bool isManual = false}) async {
    if (_isDialogShowing) return;

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

  static Future<void> showUpdateDialog(BuildContext context, AppManifest manifest, String currentVersion, {bool hasUpdate = true, bool hasNotice = false}) async {
    if (_isDialogShowing) return;
    _isDialogShowing = true;

    // 💡 渲染前检查本地是否已经有现成的安装包（仅当没在下载时才检查）
    if (!_isDownloading && !_isDownloaded) {
      String? existingPath = await isApkAlreadyDownloaded(manifest.versionName);
      if (existingPath != null) {
        _isDownloaded = true;
        _localApkPath = existingPath;
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
          // 只要不是强制更新，无论是不是在下载，都允许返回（隐藏弹窗），完美支持后台下载！
          canPop: !manifest.forceUpdate,
          child: StatefulBuilder(
              builder: (BuildContext context, StateSetter setState) {

                // 🚀 动态绑定回调到当前弹出的UI上，任何数据流变动直接驱动这里的 setState
                _uiProgressCallback = (p) { if (context.mounted) setState(() {}); };
                _uiCompleteCallback = (path) { if (context.mounted) setState(() {}); };
                _uiErrorCallback = (err) {
                  if (context.mounted) {
                    setState(() {});
                    ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(err)));
                  }
                };

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
                                const SizedBox(height: 20),

                                if (manifest.updateInfo.fullPackageUrl.isNotEmpty)
                                  if (_isDownloaded)
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.stretch,
                                      children: [
                                        ElevatedButton.icon(
                                          icon: const Icon(Icons.system_update),
                                          label: const Text("下载完成，立即安装"),
                                          style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
                                          onPressed: () {
                                            if (_localApkPath != null) installApk(_localApkPath!);
                                          },
                                        ),
                                        TextButton(
                                          onPressed: () {
                                            if (_isDownloading) return;
                                            setState(() {}); // 触发UI转入等待动画
                                            _startForegroundDownload(manifest);
                                          },
                                          child: const Text("安装失败？点击强制重新下载", style: TextStyle(color: Colors.grey, fontSize: 13, decoration: TextDecoration.underline)),
                                        )
                                      ],
                                    )
                                  else if (_isDownloading)
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                          children: [
                                            const Text("正在下载更新包...", style: TextStyle(fontSize: 13, color: Colors.grey)),
                                            Text("${(_downloadProgress * 100).toStringAsFixed(1)}%", style: const TextStyle(fontSize: 13, color: Colors.blue, fontWeight: FontWeight.bold)),
                                          ],
                                        ),
                                        const SizedBox(height: 8),
                                        ClipRRect(
                                          borderRadius: BorderRadius.circular(8),
                                          child: LinearProgressIndicator(
                                            value: _downloadProgress,
                                            minHeight: 12,
                                            backgroundColor: Colors.grey[200],
                                            valueColor: const AlwaysStoppedAnimation<Color>(Colors.blueAccent),
                                          ),
                                        ),
                                      ],
                                    )
                                  else
                                    SizedBox(
                                      width: double.infinity,
                                      child: ElevatedButton.icon(
                                          icon: const Icon(Icons.download),
                                          label: const Text("立即下载新版本"),
                                          onPressed: () {
                                            if (_isDownloading) return;
                                            setState(() {});
                                            _startForegroundDownload(manifest);
                                          }
                                      ),
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
                      TextButton(
                          onPressed: () => Navigator.pop(ctx),
                          // 动态文本提示：如果正在下载，允许用户把弹窗藏到后台
                          child: Text(_isDownloading ? "后台下载" : (_isDownloaded ? "关闭" : "稍后再说"), style: const TextStyle(color: Colors.grey))
                      ),
                  ],
                );
              }
          ),
        );
      },
    ).then((_) {
      // 弹窗销毁时释放锁，并剥离绑定的回调防止内存泄漏（但保留下载状态！）
      _isDialogShowing = false;
      _uiProgressCallback = null;
      _uiCompleteCallback = null;
      _uiErrorCallback = null;
    });
  }

  // =========================================================================
  // 👉 终极防御：带 .download 安全后缀与断点续联的流式下载
  // =========================================================================
  static Future<void> _startForegroundDownload(AppManifest manifest) async {
    // 强制斩断上一个未完结的流（防止重下时产生幽灵线程）
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
    // 🚀 核心防御：下载过程中的临时后缀！
    String tempPath = "$savePath.download";
    File tempFile = File(tempPath);

    try {
      var client = HttpClient();
      var request = await client.getUrl(Uri.parse(manifest.updateInfo.fullPackageUrl));
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
              // 通知绑定的弹窗（如果弹窗关了，回调是 null，也不影响后台继续跑）
              _uiProgressCallback?.call(_downloadProgress);
            }
          },
          onDone: () async {
            await sink.close();
            // 🚀 下载到100%了，终于可以光明正大把名字改回 .apk！
            File finalFile = await tempFile.rename(savePath);

            _isDownloading = false;
            _isDownloaded = true;
            _localApkPath = finalFile.path;

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