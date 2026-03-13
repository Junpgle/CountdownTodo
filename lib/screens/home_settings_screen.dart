import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:io';
import 'dart:math';
import 'dart:convert';
import 'dart:ui';
import 'dart:isolate';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_downloader/flutter_downloader.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:file_picker/file_picker.dart';
import '../services/tai_service.dart';

import '../storage_service.dart';
import '../update_service.dart';
import '../services/api_service.dart';
import '../services/notification_service.dart';
import '../services/migration_service.dart';
import 'login_screen.dart';
import 'package:permission_handler/permission_handler.dart';

import 'feature_guide_screen.dart';

// 引入课程数据服务来处理导入和通知测试
import '../services/course_service.dart';

@pragma('vm:entry-point')
void downloadCallback(String id, int status, int progress) {
  final SendPort? send =
      IsolateNameServer.lookupPortByName('downloader_send_port');
  send?.send([id, status, progress]);
}

class SettingsPage extends StatefulWidget {
  const SettingsPage({Key? key}) : super(key: key);

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  static const platform =
      MethodChannel('com.math_quiz.junpgle.com.math_quiz_app/notifications');
  final ReceivePort _port = ReceivePort();

  String _shizukuStatus = "点击右侧按钮获取或检查权限";
  String _islandStatus = "点击检测设备是否支持";
  String _liveUpdatesStatus = "点击检测或去开启 (Android 16+)";
  bool _isCheckingUpdate = false;
  String _taiDbPath = '';
  bool _floatWindowEnabled = true;

  // 用户与偏好设置状态
  String _username = "加载中...";
  int? _userId;
  int _syncInterval = 0;
  String _themeMode = 'system';
  String _noCourseBehavior = 'keep';
  String _serverChoice = 'cloudflare';

  // 学期进度状态
  bool _semesterEnabled = false;
  DateTime? _semesterStart;
  DateTime? _semesterEnd;

  // 缓存大小状态
  String _cacheSizeStr = "计算中...";

  // 账户状态：等级与同步额度
  String _userTier = "加载中...";
  double _syncProgress = 0.0;
  bool _isLoadingStatus = true;

  // 权限状态：key → PermissionStatus（null 表示还未检查）
  final Map<String, PermissionStatus?> _permissionStatuses = {};
  bool _isCheckingPermissions = false;

  // 所有应用权限的元数据定义
  static const List<Map<String, dynamic>> _permissionDefs = [
    {
      'key': 'notification',
      'label': '通知',
      'desc': '课程提醒、待办闹钟、下载进度推送',
      'icon': Icons.notifications_outlined,
      'color': Colors.blue,
      'critical': true,
    },
    {
      'key': 'storage',
      'label': '存储读写',
      'desc': '导入课表文件、下载版本更新安装包',
      'icon': Icons.folder_outlined,
      'color': Colors.orange,
      'critical': false,
    },
    {
      'key': 'usage_stats',
      'label': '应用使用情况',
      'desc': '屏幕时间统计功能（统计各 App 使用时长）',
      'icon': Icons.bar_chart_outlined,
      'color': Colors.purple,
      'critical': false,
    },
    {
      'key': 'request_install',
      'label': '安装未知来源应用',
      'desc': '允许应用内直接安装版本更新包',
      'icon': Icons.install_mobile_outlined,
      'color': Colors.teal,
      'critical': false,
    },
    {
      'key': 'exact_alarm',
      'label': '精确提醒',
      'desc': '保活核心权限：App 被杀后仍能在准确时刻推送待办/课程提醒',
      'icon': Icons.alarm_outlined,
      'color': Colors.red,
      'critical': true,
    },
  ];

  Future<void> _checkAllPermissions() async {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    setState(() => _isCheckingPermissions = true);

    final Map<String, PermissionStatus> results = {};

    // 通知权限
    results['notification'] = await Permission.notification.status;

    // 存储权限（Android 13+ 用 photos/videos，低版本用 storage）
    if (Platform.isAndroid) {
      final storageStatus = await Permission.storage.status;
      final manageStatus = await Permission.manageExternalStorage.status;
      results['storage'] = (storageStatus.isGranted || manageStatus.isGranted)
          ? PermissionStatus.granted
          : storageStatus;
    } else {
      results['storage'] = await Permission.storage.status;
    }

    // 应用使用情况（Android only，通过 MethodChannel 检查）
    if (Platform.isAndroid) {
      try {
        final bool hasUsage =
            await platform.invokeMethod('checkUsageStatsPermission') ?? false;
        results['usage_stats'] =
            hasUsage ? PermissionStatus.granted : PermissionStatus.denied;
      } catch (_) {
        results['usage_stats'] = PermissionStatus.denied;
      }
    } else {
      results['usage_stats'] = PermissionStatus.granted;
    }

    // 安装未知来源
    if (Platform.isAndroid) {
      results['request_install'] =
          await Permission.requestInstallPackages.status;
    } else {
      results['request_install'] = PermissionStatus.granted;
    }

    // 精确闹钟（Android 12+ 需要用户在设置里单独授权）
    if (Platform.isAndroid) {
      try {
        final bool granted = await const MethodChannel(
                    'com.math_quiz.junpgle.com.math_quiz_app/notifications')
                .invokeMethod<bool>('checkExactAlarmPermission') ??
            true;
        results['exact_alarm'] =
            granted ? PermissionStatus.granted : PermissionStatus.denied;
      } catch (_) {
        results['exact_alarm'] = PermissionStatus.granted;
      }
    } else {
      results['exact_alarm'] = PermissionStatus.granted;
    }

    if (mounted) {
      setState(() {
        for (final entry in results.entries) {
          _permissionStatuses[entry.key] = entry.value;
        }
        _isCheckingPermissions = false;
      });
    }
  }

  Future<void> _requestOrOpenPermission(String key) async {
    if (!Platform.isAndroid && !Platform.isIOS) return;

    switch (key) {
      case 'notification':
        final status = await Permission.notification.request();
        if (status.isPermanentlyDenied) await openAppSettings();
        break;
      case 'storage':
        if (Platform.isAndroid) {
          final status = await Permission.manageExternalStorage.request();
          if (status.isPermanentlyDenied || status.isDenied) {
            await openAppSettings();
          }
        } else {
          final status = await Permission.storage.request();
          if (status.isPermanentlyDenied) await openAppSettings();
        }
        break;
      case 'usage_stats':
        try {
          final bool opened =
              await platform.invokeMethod('openUsageStatsSettings') ?? false;
          if (!opened) await openAppSettings();
        } catch (_) {
          await openAppSettings();
        }
        break;
      case 'request_install':
        final status = await Permission.requestInstallPackages.request();
        if (status.isPermanentlyDenied || status.isDenied)
          await openAppSettings();
        break;
      case 'exact_alarm':
        try {
          await const MethodChannel(
                  'com.math_quiz.junpgle.com.math_quiz_app/notifications')
              .invokeMethod('openExactAlarmSettings');
        } catch (_) {
          await openAppSettings();
        }
        break;
    }

    await Future.delayed(const Duration(milliseconds: 500));
    await _checkAllPermissions();
  }

  @override
  void initState() {
    super.initState();
    _loadSettings().then((_) => _fetchAccountStatus());
    _setupDownloadListener();
    _calculateCacheSize();
    _checkAllPermissions();
  }

  @override
  void dispose() {
    IsolateNameServer.removePortNameMapping('downloader_send_port');
    _port.close();
    super.dispose();
  }

  Future<void> _fetchAccountStatus() async {
    if (_userId == null) {
      if (mounted) {
        setState(() {
          _userTier = "离线";
          _syncProgress = 0.0;
          _isLoadingStatus = false;
        });
      }
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final String cacheKey = 'account_status_cache_$_userId';
    final String timeKey = 'account_status_time_$_userId';

    final String? cachedDataStr = prefs.getString(cacheKey);
    final int? lastSyncTime = prefs.getInt(timeKey);

    bool useCache = false;
    if (cachedDataStr != null && lastSyncTime != null) {
      final DateTime lastSync =
          DateTime.fromMillisecondsSinceEpoch(lastSyncTime, isUtc: true)
              .toLocal();
      if (DateTime.now().difference(lastSync).inMinutes < 5) {
        useCache = true;
        try {
          final data = jsonDecode(cachedDataStr);
          if (mounted) {
            setState(() {
              _userTier = data['tier'] ?? 'Free';
              int count = data['sync_count'] ?? 0;
              int limit = data['sync_limit'] ?? 50;
              _syncProgress = limit > 0 ? (count / limit).clamp(0.0, 1.0) : 0.0;
              _isLoadingStatus = false;
            });
          }
        } catch (e) {
          useCache = false;
        }
      }
    }

    if (useCache) return;

    try {
      final response = await http.get(
          Uri.parse('${ApiService.baseUrl}/api/user/status?user_id=$_userId'));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        await prefs.setString(cacheKey, response.body);
        await prefs.setInt(timeKey, DateTime.now().millisecondsSinceEpoch);

        if (mounted) {
          setState(() {
            _userTier = data['tier'] ?? 'Free';
            int count = data['sync_count'] ?? 0;
            int limit = data['sync_limit'] ?? 50;
            _syncProgress = limit > 0 ? (count / limit).clamp(0.0, 1.0) : 0.0;
            _isLoadingStatus = false;
          });
        }
      } else {
        if (mounted)
          setState(() {
            _userTier = "Free";
            _isLoadingStatus = false;
          });
      }
    } catch (e) {
      if (mounted)
        setState(() {
          _userTier = "未知";
          _isLoadingStatus = false;
        });
    }
  }

  String _formatSize(double size) {
    if (size <= 0) return "0 B";
    const List<String> suffixes = ["B", "KB", "MB", "GB", "TB"];
    int i = (log(size) / log(1024)).floor();
    return '${(size / pow(1024, i)).toStringAsFixed(2)} ${suffixes[i]}';
  }

  Future<void> _calculateCacheSize() async {
    try {
      double size = 0;

      final tempDir = await getTemporaryDirectory();
      size += _getTotalSizeOfFilesInDir(tempDir);

      final supportDir = await getApplicationSupportDirectory();
      size += _getTotalSizeOfFilesInDir(supportDir);

      final docDir = await getApplicationDocumentsDirectory();
      size += _getPackageSizeInDir(docDir);

      if (Platform.isAndroid) {
        final extDir = await getExternalStorageDirectory();
        if (extDir != null) {
          size += _getPackageSizeInDir(extDir);
        }
      }

      if (mounted) {
        setState(() {
          _cacheSizeStr = _formatSize(size);
        });
      }
    } catch (e) {
      if (mounted) setState(() => _cacheSizeStr = "未知");
    }
  }

  double _getTotalSizeOfFilesInDir(FileSystemEntity file) {
    if (file is File) {
      return file.lengthSync().toDouble();
    }
    if (file is Directory) {
      double total = 0;
      try {
        final List<FileSystemEntity> children = file.listSync();
        for (final FileSystemEntity child in children) {
          total += _getTotalSizeOfFilesInDir(child);
        }
      } catch (e) {}
      return total;
    }
    return 0;
  }

  double _getPackageSizeInDir(Directory dir) {
    double total = 0;
    if (dir.existsSync()) {
      try {
        for (var child in dir.listSync(recursive: true)) {
          if (child is File) {
            String name = child.path.toLowerCase();
            if (name.endsWith('.apk') || name.endsWith('.exe')) {
              total += child.lengthSync();
            }
          }
        }
      } catch (e) {}
    }
    return total;
  }

  Future<void> _clearCache() async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(child: CircularProgressIndicator()),
    );

    try {
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();

      final tempDir = await getTemporaryDirectory();
      _deleteDirectoryContents(tempDir);

      final supportDir = await getApplicationSupportDirectory();
      _deleteDirectoryContents(supportDir);

      final docDir = await getApplicationDocumentsDirectory();
      _deletePackageFilesInDir(docDir);

      if (Platform.isAndroid) {
        final extDir = await getExternalStorageDirectory();
        if (extDir != null) _deletePackageFilesInDir(extDir);
      }

      try {
        final tasks = await FlutterDownloader.loadTasks();
        if (tasks != null) {
          for (var task in tasks) {
            await FlutterDownloader.remove(
                taskId: task.taskId, shouldDeleteContent: true);
          }
        }
      } catch (e) {}
    } catch (e) {
      debugPrint("深度清理缓存失败: $e");
    } finally {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('✅ 深度清理完成，设备空间已大幅释放！')));
        _calculateCacheSize();
      }
    }
  }

  void _deleteDirectoryContents(Directory dir) {
    if (dir.existsSync()) {
      try {
        for (var child in dir.listSync()) {
          try {
            child.deleteSync(recursive: true);
          } catch (e) {}
        }
      } catch (e) {}
    }
  }

  void _deletePackageFilesInDir(Directory dir) {
    if (dir.existsSync()) {
      try {
        for (var child in dir.listSync(recursive: true)) {
          if (child is File) {
            String name = child.path.toLowerCase();
            if (name.endsWith('.apk') || name.endsWith('.exe')) {
              try {
                child.deleteSync();
              } catch (e) {}
            }
          }
        }
      } catch (e) {}
    }
  }

  Future<void> _showStorageAnalysis() async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(child: CircularProgressIndicator()),
    );

    List<Map<String, dynamic>> allFiles = [];
    Map<String, double> dirSizes = {
      '沙盒真实根目录 (App Root)': 0,
      '外部存储 (External)': 0,
    };

    Future<void> scanDirectory(Directory? dir, String dirName) async {
      if (dir == null || !dir.existsSync()) return;
      try {
        double totalSize = 0;
        for (var entity in dir.listSync(recursive: true, followLinks: false)) {
          if (entity is File) {
            try {
              final size = entity.lengthSync();
              totalSize += size;
              if (size > 50 * 1024) {
                allFiles.add({
                  'path': entity.path,
                  'size': size,
                  'file': entity,
                });
              }
            } catch (e) {}
          }
        }
        dirSizes[dirName] = totalSize;
      } catch (e) {}
    }

    try {
      final docDir = await getApplicationDocumentsDirectory();
      final rootDir = docDir.parent;

      await scanDirectory(rootDir, '沙盒真实根目录 (App Root)');

      if (Platform.isAndroid) {
        final extDir = await getExternalStorageDirectory();
        if (extDir != null) await scanDirectory(extDir, '外部存储 (External)');
      }

      allFiles.sort((a, b) => b['size'].compareTo(a['size']));
      final topFiles = allFiles.take(100).toList();

      if (mounted) {
        Navigator.pop(context);
        _showFilesDialog(topFiles, dirSizes);
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('扫描失败: $e')));
      }
    }
  }

  void _showFilesDialog(
      List<Map<String, dynamic>> topFiles, Map<String, double> dirSizes) {
    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('空间占用深度分析', style: TextStyle(fontSize: 18)),
              contentPadding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              content: SizedBox(
                width: double.maxFinite,
                height: MediaQuery.of(context).size.height * 0.7,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("📁 目录总览:",
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    ...dirSizes.entries.map((e) => Padding(
                          padding: const EdgeInsets.only(bottom: 4.0),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(e.key, style: const TextStyle(fontSize: 13)),
                              Text(_formatSize(e.value),
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13)),
                            ],
                          ),
                        )),
                    const Divider(height: 24),
                    const Text("📄 Top 100 大文件 (点击垃圾桶可直删):",
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Expanded(
                      child: topFiles.isEmpty
                          ? const Center(child: Text("未发现大于 50KB 的文件"))
                          : ListView.separated(
                              itemCount: topFiles.length,
                              separatorBuilder: (_, __) =>
                                  const Divider(height: 1),
                              itemBuilder: (context, index) {
                                final fileInfo = topFiles[index];
                                final path = fileInfo['path'] as String;
                                final size = fileInfo['size'] as int;
                                final fileName = path.split('/').last;
                                final File file = fileInfo['file'] as File;

                                bool isCore = path.contains('flutter_assets') ||
                                    path.endsWith('.db') ||
                                    path.contains('shared_prefs') ||
                                    path.contains('databases');

                                return ListTile(
                                    contentPadding: EdgeInsets.zero,
                                    leading: Icon(
                                        isCore
                                            ? Icons.warning_amber_rounded
                                            : Icons.insert_drive_file,
                                        color: isCore
                                            ? Colors.orange
                                            : Colors.grey),
                                    title: Text(
                                      fileName,
                                      style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13,
                                          color: isCore ? Colors.orange : null),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    subtitle: Text(path,
                                        style: const TextStyle(
                                            fontSize: 10, color: Colors.grey),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis),
                                    trailing: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(_formatSize(size.toDouble()),
                                              style: const TextStyle(
                                                  color: Colors.redAccent,
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.bold)),
                                          IconButton(
                                              padding: const EdgeInsets.only(
                                                  left: 8),
                                              constraints:
                                                  const BoxConstraints(),
                                              icon: const Icon(
                                                  Icons.delete_outline,
                                                  size: 20),
                                              onPressed: () async {
                                                if (isCore) {
                                                  ScaffoldMessenger.of(context)
                                                      .showSnackBar(const SnackBar(
                                                          content: Text(
                                                              '⚠️ 这个是应用运行核心文件或你的用户数据库，禁止删除！')));
                                                  return;
                                                }
                                                try {
                                                  if (file.existsSync()) {
                                                    file.deleteSync();
                                                    setDialogState(() {
                                                      topFiles.removeAt(index);
                                                    });
                                                    ScaffoldMessenger.of(
                                                            context)
                                                        .showSnackBar(
                                                            const SnackBar(
                                                                content: Text(
                                                                    '✅ 文件已删除')));
                                                  }
                                                } catch (e) {
                                                  ScaffoldMessenger.of(context)
                                                      .showSnackBar(SnackBar(
                                                          content: Text(
                                                              '删除失败: $e')));
                                                }
                                              })
                                        ]));
                              },
                            ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text("关闭")),
              ],
            );
          },
        );
      },
    );
  }

  void _setupDownloadListener() {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    IsolateNameServer.removePortNameMapping('downloader_send_port');
    IsolateNameServer.registerPortWithName(
        _port.sendPort, 'downloader_send_port');

    _port.listen((dynamic data) {
      String id = data[0];
      DownloadTaskStatus status = DownloadTaskStatus.fromInt(data[1]);

      if (status == DownloadTaskStatus.complete) {
        _handleDownloadCompleted(id);
      }
    });

    FlutterDownloader.registerCallback(downloadCallback);
  }

  Future<void> _handleDownloadCompleted(String taskId) async {
    final tasks = await FlutterDownloader.loadTasks();
    if (tasks == null) return;
    try {
      final task = tasks.firstWhere((t) => t.taskId == taskId);
      if (task.filename != null) {
        final String fullPath = "${task.savedDir}/${task.filename}";
        await Future.delayed(const Duration(milliseconds: 1500));
        await UpdateService.installPackage(fullPath);
      }
    } catch (e) {}
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    int interval = await StorageService.getSyncInterval();
    String theme = await StorageService.getThemeMode();
    String serverUrlChoice = await StorageService.getServerChoice();

    bool sEnabled = await StorageService.getSemesterEnabled();
    DateTime? sStart = await StorageService.getSemesterStart();
    DateTime? sEnd = await StorageService.getSemesterEnd();

    String? noCourseBehaviorPref = prefs.getString('no_course_behavior');
    bool floatEnabled = prefs.getBool('float_window_enabled') ?? true;

    setState(() {
      _username = prefs.getString(StorageService.KEY_CURRENT_USER) ?? "未登录";
      _userId = prefs.getInt('current_user_id');
      _syncInterval = interval;
      _themeMode = theme;
      _serverChoice = serverUrlChoice;
      _semesterEnabled = sEnabled;
      _semesterStart = sStart;
      _semesterEnd = sEnd;
      if (noCourseBehaviorPref != null) {
        _noCourseBehavior = noCourseBehaviorPref;
      }
      _floatWindowEnabled = floatEnabled;
    });
    if (Platform.isWindows) {
      final taiPath = await TaiService.getSavedDbPath() ??
          await TaiService.detectDefaultPath();
      if (taiPath != null) await TaiService.saveDbPath(taiPath);
      setState(() => _taiDbPath = taiPath ?? '');
    }
  }

  Future<void> _pickSemesterDate(bool isStart) async {
    DateTime initialDate =
        (isStart ? _semesterStart : _semesterEnd) ?? DateTime.now();
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      helpText: isStart ? "选择开学日期" : "选择放假日期",
    );

    if (picked != null) {
      setState(() {
        if (isStart) {
          _semesterStart = picked;
          StorageService.saveAppSetting(
              StorageService.KEY_SEMESTER_START, picked.toIso8601String());
        } else {
          _semesterEnd = picked;
          StorageService.saveAppSetting(
              StorageService.KEY_SEMESTER_END, picked.toIso8601String());
        }
      });
      if (_userId != null) {
        final startMs = _semesterStart != null
            ? DateTime(_semesterStart!.year, _semesterStart!.month,
                    _semesterStart!.day)
                .millisecondsSinceEpoch
            : null;
        final endMs = _semesterEnd != null
            ? DateTime(
                    _semesterEnd!.year, _semesterEnd!.month, _semesterEnd!.day)
                .millisecondsSinceEpoch
            : null;
        ApiService.uploadUserSettings(
            semesterStartMs: startMs, semesterEndMs: endMs);
      }
    }
  }

  void _showChangePasswordDialog() {
    if (_userId == null) return;
    final oldPassCtrl = TextEditingController();
    final newPassCtrl = TextEditingController();
    final confirmPassCtrl = TextEditingController();
    bool isSubmitting = false;

    showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => StatefulBuilder(builder: (context, setDialogState) {
              return AlertDialog(
                title: const Text("修改密码"),
                content: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: oldPassCtrl,
                        obscureText: true,
                        decoration: const InputDecoration(
                            labelText: "当前密码",
                            prefixIcon: Icon(Icons.lock_outline)),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: newPassCtrl,
                        obscureText: true,
                        decoration: const InputDecoration(
                            labelText: "新密码", prefixIcon: Icon(Icons.lock)),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: confirmPassCtrl,
                        obscureText: true,
                        decoration: const InputDecoration(
                            labelText: "确认新密码",
                            prefixIcon: Icon(Icons.check_circle_outline)),
                      ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                      onPressed: isSubmitting ? null : () => Navigator.pop(ctx),
                      child: const Text("取消")),
                  FilledButton(
                    onPressed: isSubmitting
                        ? null
                        : () async {
                            if (newPassCtrl.text != confirmPassCtrl.text) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('两次输入的新密码不一致')));
                              return;
                            }
                            if (newPassCtrl.text.isEmpty ||
                                oldPassCtrl.text.isEmpty) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('请填写完整')));
                              return;
                            }

                            setDialogState(() => isSubmitting = true);
                            final res = await ApiService.changePassword(
                                _userId!, oldPassCtrl.text, newPassCtrl.text);
                            setDialogState(() => isSubmitting = false);

                            if (!context.mounted) return;
                            Navigator.pop(ctx);
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                content: Text(res['message'] ??
                                    (res['success'] ? '修改成功' : '修改失败'))));

                            if (res['success']) {
                              _handleLogout(force: true);
                            }
                          },
                    child: isSubmitting
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Text("确认修改"),
                  ),
                ],
              );
            }));
  }

  void _showHomeSectionManager() async {
    final prefs = await SharedPreferences.getInstance();

    final bool isTablet = MediaQuery.of(context).size.width >= 768;

    List<String>? leftOrder = prefs.getStringList('home_section_order_left');
    List<String>? rightOrder = prefs.getStringList('home_section_order_right');

    final List<String> defaultOrder = [
      'courses',
      'countdowns',
      'todos',
      'screenTime',
      'math',
      'pomodoro'
    ];

    if (leftOrder == null || rightOrder == null) {
      List<String> oldOrder =
          prefs.getStringList('home_section_order') ?? defaultOrder;
      leftOrder = [];
      rightOrder = [];
      for (int i = 0; i < oldOrder.length; i++) {
        if (i % 2 == 0)
          leftOrder.add(oldOrder[i]);
        else
          rightOrder.add(oldOrder[i]);
      }
    }

    List<String> combined = [...leftOrder, ...rightOrder];
    for (var key in defaultOrder) {
      if (!combined.contains(key)) leftOrder.add(key);
    }
    leftOrder.removeWhere((key) => !defaultOrder.contains(key));
    rightOrder.removeWhere((key) => !defaultOrder.contains(key));

    List<String> mobileCombinedOrder = [...leftOrder, ...rightOrder];

    Map<String, bool> visibility = {
      'courses': true,
      'countdowns': true,
      'todos': true,
      'screenTime': true,
      'math': true,
      'pomodoro': true
    };
    String? visStr = prefs.getString('home_section_visibility');
    if (visStr != null) visibility = Map<String, bool>.from(jsonDecode(visStr));
    for (var key in defaultOrder) visibility.putIfAbsent(key, () => true);

    Map<String, String> names = {
      'courses': '课程提醒',
      'countdowns': '重要日与倒计时',
      'todos': '待办事项清单',
      'screenTime': '屏幕时间面板',
      'math': '数学测验入口',
      'pomodoro': '今日专注统计',
    };

    if (!mounted) return;

    showDialog(
        context: context,
        builder: (ctx) => StatefulBuilder(builder: (context, setDialogState) {
              void moveItem(String item,
                  {String? targetKey, bool? toLeftList}) {
                setDialogState(() {
                  leftOrder!.remove(item);
                  rightOrder!.remove(item);
                  if (targetKey != null) {
                    if (leftOrder!.contains(targetKey)) {
                      leftOrder!.insert(leftOrder!.indexOf(targetKey), item);
                    } else if (rightOrder!.contains(targetKey)) {
                      rightOrder!.insert(rightOrder!.indexOf(targetKey), item);
                    }
                  } else if (toLeftList != null) {
                    if (toLeftList)
                      leftOrder!.add(item);
                    else
                      rightOrder!.add(item);
                  }
                });
              }

              Widget buildDraggableItem(String key) {
                return LongPressDraggable<String>(
                  data: key,
                  delay: const Duration(milliseconds: 200),
                  feedback: Material(
                    elevation: 8,
                    borderRadius: BorderRadius.circular(8),
                    color: Colors.transparent,
                    child: Container(
                      width: 250,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                          color: Theme.of(context)
                              .colorScheme
                              .primaryContainer
                              .withOpacity(0.9),
                          borderRadius: BorderRadius.circular(8)),
                      child: Text(names[key] ?? key,
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onPrimaryContainer)),
                    ),
                  ),
                  childWhenDragging: Opacity(
                    opacity: 0.3,
                    child: CheckboxListTile(
                        title: Text(names[key] ?? key),
                        value: visibility[key],
                        onChanged: null),
                  ),
                  child: DragTarget<String>(
                      onWillAccept: (data) => data != key,
                      onAccept: (data) => moveItem(data, targetKey: key),
                      builder: (context, candidateData, rejectedData) {
                        return Container(
                          decoration: BoxDecoration(
                            border: candidateData.isNotEmpty
                                ? Border(
                                    top: BorderSide(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .primary,
                                        width: 3))
                                : null,
                          ),
                          child: CheckboxListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(names[key] ?? key,
                                style: const TextStyle(fontSize: 14)),
                            value: visibility[key],
                            secondary: const Icon(Icons.drag_indicator,
                                color: Colors.grey, size: 20),
                            onChanged: (val) => setDialogState(
                                () => visibility[key] = val ?? true),
                          ),
                        );
                      }),
                );
              }

              Widget buildDragColumn(List<String> items, bool isLeft) {
                return Expanded(
                  child: DragTarget<String>(
                      onWillAccept: (data) => true,
                      onAccept: (data) => moveItem(data, toLeftList: isLeft),
                      builder: (context, candidateData, rejectedData) {
                        return Container(
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          padding: const EdgeInsets.only(bottom: 60),
                          decoration: BoxDecoration(
                            color: candidateData.isNotEmpty
                                ? Theme.of(context)
                                    .colorScheme
                                    .primaryContainer
                                    .withOpacity(0.1)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(8),
                            border:
                                Border.all(color: Colors.grey.withOpacity(0.2)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(
                                padding: const EdgeInsets.all(8.0),
                                child: Text(isLeft ? "屏幕左栏" : "屏幕右栏",
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: Colors.grey)),
                              ),
                              ...items.map((key) => buildDraggableItem(key)),
                            ],
                          ),
                        );
                      }),
                );
              }

              return AlertDialog(
                title: const Text("首页模块管理"),
                content: SizedBox(
                  width: isTablet ? 600 : double.maxFinite,
                  height: 400,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12.0),
                        child: Text(
                            isTablet
                                ? "长按模块，可跨越左右栏进行拖拽。\n勾选控制该模块是否在首页展示。"
                                : "长按右侧把手拖拽改变顺序，勾选控制是否展示。",
                            style: const TextStyle(
                                color: Colors.grey, fontSize: 13)),
                      ),
                      Expanded(
                        child: isTablet
                            ? Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  buildDragColumn(leftOrder!, true),
                                  buildDragColumn(rightOrder!, false),
                                ],
                              )
                            : ReorderableListView(
                                shrinkWrap: true,
                                onReorder: (oldIndex, newIndex) {
                                  setDialogState(() {
                                    if (newIndex > oldIndex) newIndex -= 1;
                                    final item =
                                        mobileCombinedOrder.removeAt(oldIndex);
                                    mobileCombinedOrder.insert(newIndex, item);
                                  });
                                },
                                children: mobileCombinedOrder.map((key) {
                                  return CheckboxListTile(
                                    key: Key(key),
                                    contentPadding: EdgeInsets.zero,
                                    title: Text(names[key] ?? key),
                                    value: visibility[key] ?? true,
                                    secondary: const Icon(Icons.drag_handle,
                                        color: Colors.grey),
                                    onChanged: (val) {
                                      setDialogState(
                                          () => visibility[key] = val ?? true);
                                    },
                                  );
                                }).toList(),
                              ),
                      ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text("取消")),
                  FilledButton(
                    onPressed: () {
                      if (!isTablet) {
                        leftOrder!.clear();
                        rightOrder!.clear();
                        int mid = (mobileCombinedOrder.length / 2).ceil();
                        for (int i = 0; i < mobileCombinedOrder.length; i++) {
                          if (i < mid)
                            leftOrder!.add(mobileCombinedOrder[i]);
                          else
                            rightOrder!.add(mobileCombinedOrder[i]);
                        }
                      }

                      prefs.setStringList(
                          'home_section_order_left', leftOrder!);
                      prefs.setStringList(
                          'home_section_order_right', rightOrder!);
                      prefs.setString(
                          'home_section_visibility', jsonEncode(visibility));
                      Navigator.pop(ctx);
                      ScaffoldMessenger.of(this.context).showSnackBar(
                          const SnackBar(content: Text('已保存，请返回主页查看更新')));
                    },
                    child: const Text("保存并应用"),
                  )
                ],
              );
            }));
  }

  Future<void> _checkAndOpenLiveUpdates() async {
    try {
      final bool hasPermission =
          await platform.invokeMethod('checkLiveUpdatesPermission') ?? true;
      if (!hasPermission) {
        setState(() => _liveUpdatesStatus = "权限未开启，尝试跳转设置...");
        final bool opened =
            await platform.invokeMethod('openLiveUpdatesSettings') ?? false;

        if (opened) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('请在设置中打开"推广的通知/实时更新"权限'),
                duration: Duration(seconds: 3)),
          );
        } else {
          setState(() => _liveUpdatesStatus = "跳转失败，设备可能不是 Android 16+");
        }
      } else {
        setState(() => _liveUpdatesStatus = "✅ 已拥有实时通知权限");
      }
    } on PlatformException catch (e) {
      setState(() => _liveUpdatesStatus = "检测失败: '${e.message}'.");
    }
  }

  Future<void> _checkIslandSupport() async {
    try {
      final bool result = await platform.invokeMethod('checkIslandSupport');
      setState(() {
        if (result) {
          _islandStatus = "✅ 设备已支持超级岛！";
        } else {
          _islandStatus = "❌ 不支持，或未开启状态栏显示权限";
        }
      });
    } on PlatformException catch (e) {
      setState(() => _islandStatus = "检测失败: '${e.message}'.");
    }
  }

  Future<void> _smartImportCourse() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.any,
    );

    if (result == null || result.files.single.path == null) return;

    String filePath = result.files.single.path!;
    File file = File(filePath);

    ValueNotifier<String> statusNotifier = ValueNotifier("获取课表文件中...");
    BuildContext? dialogContext;

    showDialog(
      context: context,
      barrierDismissible: false,
      useRootNavigator: true,
      builder: (ctx) {
        dialogContext = ctx;
        return AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          content: Row(
            children: [
              const CircularProgressIndicator(),
              const SizedBox(width: 20),
              Expanded(
                child: ValueListenableBuilder<String>(
                  valueListenable: statusNotifier,
                  builder: (context, value, child) {
                    return Text(
                      value,
                      style: const TextStyle(fontSize: 15, height: 1.4),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );

    try {
      await Future.delayed(const Duration(milliseconds: 400));
      statusNotifier.value = "正在智能识别文件类型...";

      String content;
      String ext = filePath.split('.').last.toLowerCase();

      try {
        content = await file.readAsString();
      } catch (e) {
        List<int> bytes = await file.readAsBytes();
        content = utf8.decode(bytes, allowMalformed: true);
      }

      await Future.delayed(const Duration(milliseconds: 400));

      bool success = false;
      String sourceName = "";

      if (ext == 'ics' || content.contains('BEGIN:VCALENDAR')) {
        sourceName = "西安电子科技大学";
        statusNotifier.value = "识别到: $sourceName\n正在导入...";

        if (_semesterStart == null) {
          statusNotifier.value = "⚠️ 导入中断\n请先在设置中配置【开学日期】";
          await Future.delayed(const Duration(seconds: 2));
          if (dialogContext != null && dialogContext!.mounted)
            Navigator.pop(dialogContext!);
          return;
        }
        success = await CourseService.importXidianScheduleFromIcs(
            content, _semesterStart!);
      } else if (['mhtml', 'html', 'htm'].contains(ext) ||
          content.contains('quoted-printable') ||
          content.toLowerCase().contains('<html')) {
        sourceName = "厦门大学";
        statusNotifier.value = "识别到: $sourceName\n正在深度解码导入...";

        if (_semesterStart == null) {
          statusNotifier.value = "⚠️ 导入中断\n请先在设置中配置【开学日期】";
          await Future.delayed(const Duration(seconds: 2));
          if (dialogContext != null && dialogContext!.mounted)
            Navigator.pop(dialogContext!);
          return;
        }
        success = await CourseService.importXmuScheduleFromHtml(
            content, _semesterStart!);
      } else if (['json', 'txt'].contains(ext) ||
          content.trim().startsWith('[') ||
          content.trim().startsWith('{')) {
        sourceName = "聚在工大";
        statusNotifier.value = "识别到: $sourceName\n正在导入...";
        success = await CourseService.importScheduleFromJson(content);
      } else {
        statusNotifier.value = "❌ 未知的文件格式\n暂不支持解析该文件";
        await Future.delayed(const Duration(seconds: 2));
        if (dialogContext != null && dialogContext!.mounted)
          Navigator.pop(dialogContext!);
        return;
      }

      if (success) {
        statusNotifier.value = "✅ $sourceName 导入成功！\n请返回主页查看课表";
        await Future.delayed(const Duration(milliseconds: 1200));
        if (dialogContext != null && dialogContext!.mounted) {
          Navigator.pop(dialogContext!);
        }
      } else {
        statusNotifier.value = "❌ 导入失败\n课表解析错误或文件已损坏";
        await Future.delayed(const Duration(seconds: 2));
        if (dialogContext != null && dialogContext!.mounted) {
          Navigator.pop(dialogContext!);
        }
      }
    } catch (e) {
      debugPrint("处理智能导入时崩溃: $e");
      statusNotifier.value = "❌ 发生异常\n读取文件失败或格式崩溃";
      await Future.delayed(const Duration(seconds: 2));
      if (dialogContext != null && dialogContext!.mounted) {
        Navigator.pop(dialogContext!);
      }
    }
  }

  Future<void> _testCourseNotification() async {
    final dashboardData = await CourseService.getDashboardCourses();
    List<CourseItem> courses =
        (dashboardData['courses'] as List?)?.cast<CourseItem>() ?? [];

    CourseItem? testCourse;
    if (courses.isNotEmpty) {
      testCourse = courses.first;
    } else {
      final allCourses = await CourseService.getAllCourses();
      if (allCourses.isNotEmpty) {
        testCourse = allCourses.first;
      }
    }

    if (testCourse != null) {
      NotificationService.showCourseLiveActivity(
        courseName: testCourse.courseName,
        room: testCourse.roomName,
        timeStr:
            '${testCourse.formattedStartTime} - ${testCourse.formattedEndTime}',
        teacher: testCourse.teacherName,
      );
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('✅ 已发送测试实时通知，请查看状态栏')));
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('❌ 尚未导入课表数据，请先在"课程设置"中导入')));
      }
    }
  }

  Future<void> _forceFullSync() async {
    if (_username.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先登录账号')),
      );
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('强制全量同步'),
        content: const Text(
          '这将重置本地同步记录，从云端拉取所有最新数据。\n\n本地未同步的数据会先上传，再合并云端数据。\n\n是否继续？',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('确认')),
        ],
      ),
    );
    if (confirm != true) return;

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
          content: Text('🔄 正在全量同步...'), duration: Duration(seconds: 10)),
    );

    try {
      await StorageService.resetSyncTime(_username);
      await StorageService.syncData(_username, forceFullSync: true);

      if (mounted) {
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✅ 全量同步完成')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ 同步失败: $e')),
        );
      }
    }
  }

  Future<void> _uploadCoursesToCloud() async {
    if (_userId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先登录账号')),
      );
      return;
    }

    final allCourses = await CourseService.getAllCourses();
    if (allCourses.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('当前没有课表数据可上传')),
      );
      return;
    }

    bool confirm = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text("上传课表到云端"),
            content: const Text("这将覆盖你云端的所有课表数据。\n\n用于与电脑或其他设备同步。\n\n是否继续？"),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text("取消")),
              FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text("上传")),
            ],
          ),
        ) ??
        false;

    if (!confirm) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    final result = await CourseService.syncCoursesToCloud(_userId!);

    if (result['success'] == true) {
      final startMs = _semesterStart != null
          ? DateTime(_semesterStart!.year, _semesterStart!.month,
                  _semesterStart!.day)
              .millisecondsSinceEpoch
          : null;
      final endMs = _semesterEnd != null
          ? DateTime(_semesterEnd!.year, _semesterEnd!.month, _semesterEnd!.day)
              .millisecondsSinceEpoch
          : null;
      await ApiService.uploadUserSettings(
          semesterStartMs: startMs, semesterEndMs: endMs);
    }

    if (!mounted) return;
    Navigator.pop(context);

    if (result['success'] == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('✅ 课表已成功同步到云端')),
      );
      _fetchAccountStatus();
    } else if (result['isLimitExceeded'] == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result['message'] ?? '今日同步次数已达上限')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result['message'] ?? '同步失败')),
      );
    }
  }

  Future<void> _fetchCoursesFromCloud() async {
    if (_userId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先登录账号')),
      );
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('从云端获取课表'),
        content: const Text('这将用云端课表数据覆盖本地课表。\n\n本地已有的课表数据将被替换。\n\n是否继续？'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('获取')),
        ],
      ),
    );
    if (confirm != true) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final List<dynamic> data = await ApiService.fetchCourses(_userId!);

      if (!mounted) return;
      Navigator.pop(context);

      if (data.isNotEmpty) {
        if (_semesterStart == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('⚠️ 请先在学期设置中配置开学日期')),
          );
          return;
        }

        final DateTime semesterMonday = _semesterStart!.subtract(
          Duration(days: _semesterStart!.weekday - 1),
        );

        final courses = data.map<CourseItem>((c) {
          final int weekIndex = (c['week_index'] as num?)?.toInt() ?? 1;
          final int weekday = (c['weekday'] as num?)?.toInt() ?? 1;

          final DateTime courseDate = semesterMonday
              .add(Duration(days: (weekIndex - 1) * 7 + (weekday - 1)));
          final String dateStr = DateFormat('yyyy-MM-dd').format(courseDate);

          return CourseItem(
            courseName: c['course_name'] ?? '',
            roomName: c['room_name'] ?? '',
            teacherName: c['teacher_name'] ?? '',
            startTime: (c['start_time'] as num?)?.toInt() ?? 0,
            endTime: (c['end_time'] as num?)?.toInt() ?? 0,
            weekday: weekday,
            weekIndex: weekIndex,
            lessonType: c['lesson_type'] ?? '',
            date: dateStr,
          );
        }).toList();

        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(
          'course_schedule_json',
          jsonEncode(courses.map((c) => c.toJson()).toList()),
        );

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('✅ 已从云端同步 ${courses.length} 条课程数据')),
          );
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('❌ 获取失败，请检查网络或云端暂无数据')),
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ 发生错误: $e')),
        );
      }
    }
  }

  Future<String> _getAuthToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('auth_token') ?? '';
  }

  Future<void> _checkUpdatesAndNotices() async {
    setState(() => _isCheckingUpdate = true);
    await UpdateService.checkUpdateAndPrompt(context, isManual: true);
    if (mounted) setState(() => _isCheckingUpdate = false);
  }

  Future<void> _pickTaiDatabase() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['db', 'sqlite'],
      dialogTitle: '选择 Tai 数据库文件',
    );
    if (result == null || result.files.single.path == null) return;

    final path = result.files.single.path!;
    final valid = await TaiService.validateDb(path);

    if (!valid) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('❌ 无效的 Tai 数据库文件')),
        );
      }
      return;
    }

    await TaiService.saveDbPath(path);
    setState(() => _taiDbPath = path);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('✅ 数据库路径已保存')),
      );
    }
  }

  Future<void> _handleLogout({bool force = false}) async {
    bool confirm = force;
    if (!force) {
      confirm = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text("退出账号"),
              content: const Text("确定要退出当前账号吗？"),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text("取消")),
                FilledButton(
                  style:
                      FilledButton.styleFrom(backgroundColor: Colors.redAccent),
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text("退出"),
                ),
              ],
            ),
          ) ??
          false;
    }

    if (confirm) {
      await StorageService.clearLoginSession();
      if (mounted) {
        Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(builder: (_) => const LoginScreen()),
            (route) => false);
      }
    }
  }

  // ─── 权限检查板块 ──────────────────────────────────────────────
  Widget _buildPermissionSection() {
    if (!Platform.isAndroid && !Platform.isIOS) return const SizedBox.shrink();

    final allGranted = _permissionDefs.every((def) {
      final status = _permissionStatuses[def['key'] as String];
      return status == PermissionStatus.granted ||
          status == PermissionStatus.limited;
    });
    final undoneCount = _permissionDefs.where((d) {
      final s = _permissionStatuses[d['key'] as String];
      return s != null &&
          s != PermissionStatus.granted &&
          s != PermissionStatus.limited;
    }).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 8.0, bottom: 8.0, top: 16.0),
          child: Row(
            children: [
              const Text('权限管理',
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey)),
              const SizedBox(width: 8),
              if (_permissionStatuses.isNotEmpty)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: allGranted
                        ? Colors.green.withOpacity(0.12)
                        : Colors.orange.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    allGranted ? '全部已授权' : '$undoneCount 项未授权',
                    style: TextStyle(
                        fontSize: 11,
                        color: allGranted ? Colors.green : Colors.orange,
                        fontWeight: FontWeight.bold),
                  ),
                ),
              const Spacer(),
              GestureDetector(
                onTap: _isCheckingPermissions ? null : _checkAllPermissions,
                child: Padding(
                  padding: const EdgeInsets.all(4.0),
                  child: _isCheckingPermissions
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.refresh, size: 18, color: Colors.grey),
                ),
              ),
            ],
          ),
        ),
        Card(
          elevation: 2,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Column(
            children: [
              for (int i = 0; i < _permissionDefs.length; i++) ...[
                if (i > 0) const Divider(height: 1, indent: 56),
                _buildPermissionTile(_permissionDefs[i]),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPermissionTile(Map<String, dynamic> def) {
    final String key = def['key'] as String;
    final String label = def['label'] as String;
    final String desc = def['desc'] as String;
    final IconData icon = def['icon'] as IconData;
    final Color color = def['color'] as Color;
    final bool critical = def['critical'] as bool;

    final PermissionStatus? status = _permissionStatuses[key];
    final bool granted = status == PermissionStatus.granted ||
        status == PermissionStatus.limited;
    final bool denied = status != null && !granted;

    Widget statusIcon;
    if (_isCheckingPermissions && status == null) {
      statusIcon = const SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2));
    } else if (status == null) {
      statusIcon = const Icon(Icons.help_outline, size: 20, color: Colors.grey);
    } else if (granted) {
      statusIcon =
          const Icon(Icons.check_circle, size: 20, color: Colors.green);
    } else {
      statusIcon = Icon(
        critical ? Icons.error : Icons.warning_amber_rounded,
        size: 20,
        color: critical ? Colors.redAccent : Colors.orange,
      );
    }

    return ListTile(
      leading: CircleAvatar(
        radius: 18,
        backgroundColor: color.withOpacity(0.12),
        child: Icon(icon, size: 18, color: color),
      ),
      title: Row(
        children: [
          Text(label,
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: denied && critical ? Colors.redAccent : null)),
          if (critical) ...[
            const SizedBox(width: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: Colors.redAccent.withOpacity(0.1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text('必要',
                  style: TextStyle(
                      fontSize: 10,
                      color: Colors.redAccent,
                      fontWeight: FontWeight.bold)),
            ),
          ],
        ],
      ),
      subtitle: Text(desc,
          style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5))),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          statusIcon,
          if (denied) ...[
            const SizedBox(width: 8),
            FilledButton.tonal(
              onPressed: () => _requestOrOpenPermission(key),
              style: FilledButton.styleFrom(
                minimumSize: const Size(60, 32),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text('去开启', style: TextStyle(fontSize: 12)),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSection(String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 8.0, bottom: 8.0, top: 16.0),
          child: Text(title,
              style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey)),
        ),
        Card(
          elevation: 2,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Column(children: children),
        ),
      ],
    );
  }

  // ─── 构建账户管理 Section ────────────────────────────────────────
  Widget _buildAccountSection() {
    return _buildSection('账户管理', [
      ListTile(
        leading: CircleAvatar(
            backgroundColor: Theme.of(context).colorScheme.primaryContainer,
            child: const Icon(Icons.person)),
        title: Text(_username,
            style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(_userId != null ? "UID: $_userId" : "离线模式"),
        trailing: const Icon(Icons.edit_square, size: 20, color: Colors.grey),
        onTap: _showChangePasswordDialog,
      ),
      const Divider(height: 1, indent: 56),
      Padding(
        padding:
            const EdgeInsets.only(left: 56, right: 16, top: 12, bottom: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text("账户等级", style: TextStyle(fontSize: 14)),
                _isLoadingStatus
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : Text(
                        _userTier.toUpperCase(),
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: _userTier.toLowerCase() == 'pro' ||
                                  _userTier.toLowerCase() == 'admin'
                              ? Colors.orangeAccent
                              : Colors.grey,
                        ),
                      ),
              ],
            ),
            const SizedBox(height: 12),
            const Text("今日同步额度",
                style: TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: _syncProgress,
                minHeight: 6,
                backgroundColor:
                    Theme.of(context).colorScheme.surfaceContainerHighest,
                valueColor: AlwaysStoppedAnimation<Color>(_syncProgress > 0.9
                    ? Colors.redAccent
                    : Theme.of(context).colorScheme.primary),
              ),
            ),
          ],
        ),
      ),
      const Divider(height: 1, indent: 56),
      ListTile(
        leading: const Icon(Icons.cloud_sync, color: Colors.deepPurple),
        title: const Text('强制全量同步'),
        subtitle: const Text('重置同步水位，从云端拉取所有最新数据'),
        trailing: const Icon(Icons.chevron_right),
        onTap: _forceFullSync,
      ),
    ]);
  }

  // ─── 构建课程设置 Section ────────────────────────────────────────
  Widget _buildCourseSection() {
    return _buildSection('课程设置', [
      ListTile(
        leading: const Icon(Icons.cloud_upload_outlined, color: Colors.blue),
        title: const Text('上传课表到云端'),
        subtitle: const Text('用于与电脑或其他设备同步'),
        trailing: const Icon(Icons.chevron_right),
        onTap: _uploadCoursesToCloud,
      ),
      ListTile(
        leading: const Icon(Icons.file_upload_outlined),
        title: const Text('智能导入本地课表'),
        subtitle: const Text('自动嗅探文件格式 (工大/厦大/西电)'),
        trailing: const Icon(Icons.chevron_right),
        onTap: _smartImportCourse,
      ),
      const Divider(height: 1, indent: 56),
      ListTile(
        leading: const Icon(Icons.cloud_download_outlined, color: Colors.green),
        title: const Text('从云端获取课表'),
        subtitle: const Text('将云端课表同步到本机，覆盖本地数据'),
        trailing: const Icon(Icons.chevron_right),
        onTap: _fetchCoursesFromCloud,
      ),
      const Divider(height: 1, indent: 56),
      ListTile(
        leading: const Icon(Icons.layers_clear_outlined),
        title: const Text('无课时板块行为'),
        trailing: DropdownButton<String>(
          value: _noCourseBehavior,
          underline: const SizedBox(),
          items: const [
            DropdownMenuItem(value: 'keep', child: Text('保持位置')),
            DropdownMenuItem(value: 'bottom', child: Text('排到最后')),
            DropdownMenuItem(value: 'hide', child: Text('自动隐藏')),
          ],
          onChanged: (val) {
            if (val != null) {
              setState(() => _noCourseBehavior = val);
              SharedPreferences.getInstance()
                  .then((prefs) => prefs.setString('no_course_behavior', val));
            }
          },
        ),
      ),
    ]);
  }

  // ─── 构建学期设置 Section ────────────────────────────────────────
  Widget _buildSemesterSection() {
    return _buildSection('学期设置', [
      SwitchListTile(
        secondary: const Icon(Icons.linear_scale),
        title: const Text('首页学期进度条'),
        value: _semesterEnabled,
        onChanged: (val) {
          setState(() => _semesterEnabled = val);
          StorageService.saveAppSetting(
              StorageService.KEY_SEMESTER_PROGRESS_ENABLED, val);
        },
      ),
      ListTile(
        contentPadding: const EdgeInsets.only(left: 56, right: 16),
        title: const Text('开学日期'),
        trailing: Text(_semesterStart == null
            ? "未设置"
            : DateFormat('yyyy-MM-dd').format(_semesterStart!)),
        onTap: () => _pickSemesterDate(true),
      ),
      ListTile(
        contentPadding: const EdgeInsets.only(left: 56, right: 16),
        title: const Text('放假日期'),
        trailing: Text(_semesterEnd == null
            ? "未设置"
            : DateFormat('yyyy-MM-dd').format(_semesterEnd!)),
        onTap: () => _pickSemesterDate(false),
      ),
      const Divider(height: 1, indent: 56),
      ListTile(
        leading: const Icon(Icons.cloud_download_outlined, color: Colors.teal),
        title: const Text('从云端同步开学/放假时间'),
        subtitle: const Text('将另一设备设置的学期日期同步到本机'),
        trailing: const Icon(Icons.chevron_right),
        onTap: _fetchCoursesFromCloud,
      ),
    ]);
  }

  // ─── 构建偏好设置 Section ────────────────────────────────────────
  Widget _buildPreferenceSection() {
    return _buildSection('偏好设置', [
      ListTile(
        leading: const Icon(Icons.dashboard_customize_outlined),
        title: const Text('首页模块管理'),
        trailing: const Icon(Icons.chevron_right),
        onTap: _showHomeSectionManager,
      ),
      const Divider(height: 1, indent: 56),
      ListTile(
        leading: const Icon(Icons.sync),
        title: const Text('自动同步频率'),
        trailing: DropdownButton<int>(
          value: _syncInterval,
          underline: const SizedBox(),
          items: const [
            DropdownMenuItem(value: 5, child: Text('每 5 分钟')),
            DropdownMenuItem(value: 10, child: Text('每 10 分钟')),
            DropdownMenuItem(value: 60, child: Text('每小时')),
            DropdownMenuItem(value: 0, child: Text('每次启动')),
          ],
          onChanged: (val) {
            if (val != null) {
              setState(() => _syncInterval = val);
              StorageService.saveAppSetting(
                  StorageService.KEY_SYNC_INTERVAL, val);
            }
          },
        ),
      ),
      const Divider(height: 1, indent: 56),
      ListTile(
        leading: const Icon(Icons.cloud_queue),
        title: const Text('云端数据接口线路'),
        subtitle: const Text('建议不要改动此处，除非你知道自己在做什么'),
        trailing: DropdownButton<String>(
          value: _serverChoice,
          underline: const SizedBox(),
          items: const [
            DropdownMenuItem(value: 'cloudflare', child: Text('Cloudflare (推荐)')),
            DropdownMenuItem(value: 'aliyun', child: Text('阿里云ECS (不安全)')),
          ],
          onChanged: (val) async {
            if (val != null && val != _serverChoice) {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('切换服务器'),
                  content: const Text('不同服务器的登录凭证不互通，切换后需要重新登录。\n\n确定要切换吗？'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
                    FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('切换并重新登录')),
                  ],
                ),
              ) ?? false;

              if (confirm && mounted) {
                await StorageService.saveServerChoice(val);
                await StorageService.clearLoginSession();
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => const LoginScreen()),
                  (route) => false,
                );
              }
            }
          },
        ),
      ),
      const Divider(height: 1, indent: 56),
      ListTile(
        leading: const Icon(Icons.palette_outlined),
        title: const Text('深色模式/主题'),
        trailing: DropdownButton<String>(
          value: _themeMode,
          underline: const SizedBox(),
          items: const [
            DropdownMenuItem(value: 'system', child: Text('跟随系统')),
            DropdownMenuItem(value: 'light', child: Text('浅色')),
            DropdownMenuItem(value: 'dark', child: Text('深色')),
          ],
          onChanged: (val) {
            if (val != null) {
              setState(() => _themeMode = val);
              StorageService.saveAppSetting(StorageService.KEY_THEME_MODE, val);
              StorageService.themeNotifier.value = val;
            }
          },
        ),
      ),
      if (Platform.isWindows) ...[
        const Divider(height: 1, indent: 56),
        ListTile(
          leading: const Icon(Icons.timer_outlined, color: Colors.indigo),
          title: const Text('Tai 屏幕时间数据库'),
          subtitle: Text(
            _taiDbPath.isEmpty ? '未设置，点击选择 data.db 文件' : _taiDbPath,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              color: _taiDbPath.isEmpty ? Colors.orange : Colors.grey,
            ),
          ),
          trailing: const Icon(Icons.folder_open_outlined),
          onTap: _pickTaiDatabase,
        ),
        const Divider(height: 1, indent: 56),
        SwitchListTile(
          secondary: const Icon(Icons.picture_in_picture_alt_outlined,
              color: Colors.indigo),
          title: const Text('番茄钟悬浮窗'),
          subtitle: const Text('专注/跨端观察时显示桌面悬浮倒计时'),
          value: _floatWindowEnabled,
          onChanged: Platform.isWindows
              ? (val) async {
                  setState(() => _floatWindowEnabled = val);
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.setBool('float_window_enabled', val);
                }
              : null,
        ),
      ],
    ]);
  }

  // ─── 构建高级设置 Section ────────────────────────────────────────
  Widget _buildAdvancedSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(left: 8.0, bottom: 8.0, top: 16.0),
          child: Text('高级设置与数据迁移',
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey)),
        ),
        Card(
          elevation: 2,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: ListTile(
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            leading: const CircleAvatar(
                backgroundColor: Colors.blueAccent,
                child: Icon(Icons.rocket_launch, color: Colors.white)),
            title: const Text('从 Cloudflare 后端一键全量迁移',
                style: TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Padding(
                padding: const EdgeInsets.only(top: 4.0),
                child: Text('自动将 D1 上您的整套账户(密码)、待办、番茄钟打包移植至当前阿里云节点，实现无缝搬家。',
                    style: TextStyle(color: Colors.grey[600], fontSize: 13))),
            trailing: ElevatedButton(
                style: ElevatedButton.styleFrom(
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20))),
                onPressed: _showMigrationDialog,
                child: const Text('开始')),
          ),
        ),
        const SizedBox(height: 12),
        if (Platform.isAndroid) ...[
          Card(
            elevation: 2,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: ListTile(
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              leading: const Icon(Icons.notification_important_outlined,
                  color: Colors.amber),
              title: const Text('测试课程实时通知'),
              subtitle: const Text('强制发送一个课程提醒用于排查显示问题'),
              trailing: TextButton(
                  onPressed: _testCourseNotification, child: const Text("发送测试")),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            elevation: 2,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: ListTile(
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              leading: const CircleAvatar(
                  backgroundColor: Colors.teal,
                  child: Icon(Icons.notifications_active, color: Colors.white)),
              title: const Text('Android 16 实时活动',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Padding(
                  padding: const EdgeInsets.only(top: 4.0),
                  child: Text(_liveUpdatesStatus,
                      style: TextStyle(color: Colors.grey[600], fontSize: 13))),
              trailing: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20))),
                  onPressed: _checkAndOpenLiveUpdates,
                  child: const Text('去开启')),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            elevation: 2,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: ListTile(
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              leading: const CircleAvatar(
                  backgroundColor: Colors.deepPurpleAccent,
                  child: Icon(Icons.smart_button, color: Colors.white)),
              title: const Text('小米超级岛支持',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Padding(
                  padding: const EdgeInsets.only(top: 4.0),
                  child: Text(_islandStatus,
                      style: TextStyle(color: Colors.grey[600], fontSize: 13))),
              trailing: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20))),
                  onPressed: _checkIslandSupport,
                  child: const Text('检测')),
            ),
          ),
        ],
      ],
    );
  }

  // ─── 一键迁移弹窗逻辑 ──────────────────────────────────────
  Future<void> _showMigrationDialog() async {
    final emailCtrl = TextEditingController();
    final passCtrl = TextEditingController();
    bool isMigrating = false;
    String statusText = "";

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text("一键全量账号与数据迁移"),
            content: isMigrating
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(),
                    const SizedBox(height: 20),
                    Text(statusText, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13), textAlign: TextAlign.center),
                  ],
                )
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('请输入您最初在 Cloudflare 服务器上注册用的邮箱与密码。系统会自动验证拉取，随后向阿里云注入您的配置。', style: TextStyle(fontSize: 13)),
                    const SizedBox(height: 16),
                    TextField(
                      controller: emailCtrl,
                      decoration: const InputDecoration(labelText: '旧账号邮箱', border: OutlineInputBorder()),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: passCtrl,
                      obscureText: true,
                      decoration: const InputDecoration(labelText: '旧账号密码', border: OutlineInputBorder()),
                    ),
                  ],
                ),
            actions: isMigrating
                ? null
                : [
                    TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("取消")),
                    FilledButton(
                      onPressed: () async {
                        if (emailCtrl.text.isEmpty || passCtrl.text.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('不能留空哦')));
                          return;
                        }
                        
                        setDialogState(() {
                          isMigrating = true;
                          statusText = "准备中...";
                        });

                        try {
                          await MigrationService.runMigration(
                            context: context,
                            oldUrl: ApiService.cloudflareUrl,  // D1 URL
                            newUrl: ApiService.aliyunUrl, // ECS URL
                            email: emailCtrl.text,
                            password: passCtrl.text,
                            onProgress: (msg) {
                              setDialogState(() => statusText = msg);
                            }
                          );

                          if (mounted) {
                            Navigator.pop(ctx);
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('✅ 迁移大成功！您的所有数据和账户已落户阿里云。')));
                            _fetchAccountStatus(); // Refresh credentials visually
                          }
                        } catch (e) {
                          setDialogState(() {
                            isMigrating = false;
                            statusText = "";
                          });
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('❌ 迁移失败: $e')));
                          }
                        }
                      },
                      child: const Text("验证并开始迁移")
                    ),
                  ],
          );
        }
      ),
    );
  }

  // ─── 构建系统与关于 Section ──────────────────────────────────────
  Widget _buildSystemSection() {
    return _buildSection('系统与关于', [
      ListTile(
        leading: const Icon(Icons.school_rounded, color: Colors.indigo),
        title: const Text('重新查看新版教程与权限设置'),
        subtitle: const Text('可再次查看功能介绍与重新配置各项权限'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) =>
                  const FeatureGuideScreen(isManualReview: true),
            ),
          );
        },
      ),
      if (!Platform.isWindows) ...[
      const Divider(height: 1, indent: 56),
      ListTile(
        leading: const Icon(Icons.cleaning_services, color: Colors.blueAccent),
        title: const Text('深度清理缓存与冗余'),
        subtitle: const Text('包含更新残留包与深度图片缓存'),
        trailing: Text(_cacheSizeStr,
            style: const TextStyle(
                color: Colors.grey, fontWeight: FontWeight.bold)),
        onTap: () async {
          bool confirm = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text("深度清理空间"),
                  content: Text(
                      "检测到大约 $_cacheSizeStr 可释放空间。\n这会彻底清除你过往下载的版本更新安装包 (APK/EXE) 以及深度的图片缓存，释放大量“用户数据”占用。\n\n(你的本地待办、倒计时与课表数据绝对安全，不受影响"),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text("取消")),
                    FilledButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text("清理")),
                  ],
                ),
              ) ??
              false;

          if (confirm) {
            _clearCache();
          }
        },
      ),
      const Divider(height: 1, indent: 56),
      ListTile(
        leading: const Icon(Icons.data_usage, color: Colors.orange),
        title: const Text('存储空间深度分析'),
        subtitle: const Text('找出占用数百MB的隐藏文件'),
        trailing: const Icon(Icons.chevron_right),
        onTap: _showStorageAnalysis,
      ),
      ],
      ListTile(
        leading: const Icon(Icons.system_update, color: Colors.green),
        title: const Text('检查新版本'),
        trailing: _isCheckingUpdate
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.chevron_right),
        onTap: _isCheckingUpdate ? null : _checkUpdatesAndNotices,
      ),
      const Divider(height: 1, indent: 56),
      ListTile(
        leading: const Icon(Icons.logout, color: Colors.redAccent),
        title: const Text('退出当前账号', style: TextStyle(color: Colors.redAccent)),
        onTap: () => _handleLogout(force: false),
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('设置'), centerTitle: true),
      body: LayoutBuilder(
        builder: (context, constraints) {
          // 宽屏阈值：768px 以上切换为双栏布局
          final bool isWide = constraints.maxWidth >= 768;

          if (isWide) {
            return _buildWideLayout();
          } else {
            return _buildNarrowLayout();
          }
        },
      ),
    );
  }

  // ─── 窄屏：单列 ListView（原始布局）───────────────────────────────
  Widget _buildNarrowLayout() {
    return ListView(
      padding: const EdgeInsets.all(16.0),
      children: [
        _buildAccountSection(),
        _buildCourseSection(),
        _buildSemesterSection(),
        _buildPreferenceSection(),
        _buildPermissionSection(),
        _buildAdvancedSection(),
        _buildSystemSection(),
        const SizedBox(height: 40),
      ],
    );
  }

  // ─── 宽屏：双栏布局 ───────────────────────────────────────────────
  // 左栏：账户、课程、学期
  // 右栏：偏好、权限、高级、系统
  Widget _buildWideLayout() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── 左栏 ──
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildAccountSection(),
                _buildCourseSection(),
                _buildSemesterSection(),
                const SizedBox(height: 40),
              ],
            ),
          ),

          const SizedBox(width: 20),

          // ── 右栏 ──
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildPreferenceSection(),
                _buildPermissionSection(),
                _buildAdvancedSection(),
                _buildSystemSection(),
                const SizedBox(height: 40),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
