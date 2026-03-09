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

  static Future<AppManifest?> checkManifest() async {
    try {
      final response = await http.get(Uri.parse(MANIFEST_URL));
      if (response.statusCode == 200) {
        String body = utf8.decode(response.bodyBytes);
        return AppManifest.fromJson(jsonDecode(body));
      }
    } catch (e) {
      debugPrint("获取更新配置失败: $e");
    }
    return null;
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
            String name = file.path.split(Platform.pathSeparator).last.toLowerCase();
            if (name.endsWith(".apk") || name.endsWith(".exe") || name.endsWith(".zip") || name.endsWith(".download")) {
              await file.delete();
            }
          }
        }
      }
    } catch (e) {
      debugPrint("预清理旧文件失败: $e");
    }

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

    await OpenFile.open(
      file.path,
      type: Platform.isAndroid ? "application/vnd.android.package-archive" : null,
    );
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
    String localVersion = packageInfo.version;

    bool hasUpdate = false;
    try {
      // 🚀 核心修复：纯三位数版本号对比，不依赖任何 BuildNumber 和 versionCode
      String cleanManifestVersion = manifest.versionName.split('+')[0].split('-')[0];
      String cleanLocalVersion = localVersion.split('+')[0].split('-')[0];

      List<int> v1 = cleanManifestVersion.split('.').map((e) => int.tryParse(e) ?? 0).toList();
      List<int> v2 = cleanLocalVersion.split('.').map((e) => int.tryParse(e) ?? 0).toList();

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

    if (!_isDownloading && !_isDownloaded) {
      String? existingPath = await isPackageAlreadyDownloaded(manifest.versionName);
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
                                        // 🚀 核心防崩区域：安全地保留纯 Text，禁止外部包裹任何 Expanded/Flexible
                                        ElevatedButton.icon(
                                          icon: const Icon(Icons.system_update),
                                          label: const Text("下载完成，立即安装", overflow: TextOverflow.ellipsis),
                                          style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
                                          onPressed: () {
                                            if (_localPackagePath != null) installPackage(_localPackagePath!);
                                          },
                                        ),
                                        TextButton(
                                          onPressed: () {
                                            if (_isDownloading) return;
                                            setState(() {});
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
                                          label: const Text("立即下载新版本", overflow: TextOverflow.ellipsis),
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
                          child: Text(_isDownloading ? "后台下载" : (_isDownloaded ? "关闭" : "稍后再说"), style: const TextStyle(color: Colors.grey))
                      ),
                  ],
                );
              }
          ),
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