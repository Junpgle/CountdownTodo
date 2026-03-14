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
import 'login_screen.dart';
import 'package:permission_handler/permission_handler.dart';

import 'feature_guide_screen.dart';
import '../services/course_service.dart';
import '../services/reminder_schedule_service.dart';

// 引入拆分的设置组件
import 'settings/widgets/account_section.dart';
import 'settings/widgets/course_section.dart';
import 'settings/widgets/semester_section.dart';
import 'settings/widgets/preference_section.dart';
import 'settings/widgets/permission_section.dart';
import 'settings/widgets/advanced_section.dart';
import 'settings/widgets/system_section.dart';

// 引入拆分的弹窗组件
import 'settings/dialogs/change_password_dialog.dart';
import 'settings/dialogs/home_section_manager_dialog.dart';
import 'settings/dialogs/zf_time_config_dialog.dart';
import 'settings/dialogs/migration_dialog.dart';

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
  String _serverChoice = 'aliyun';

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
      size += await _getTotalSizeOfFilesInDir(tempDir);

      final supportDir = await getApplicationSupportDirectory();
      size += await _getTotalSizeOfFilesInDir(supportDir);

      final docDir = await getApplicationDocumentsDirectory();
      size += await _getPackageSizeInDir(docDir);

      if (Platform.isAndroid) {
        final extDir = await getExternalStorageDirectory();
        if (extDir != null) {
          size += await _getPackageSizeInDir(extDir);
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

  Future<double> _getTotalSizeOfFilesInDir(FileSystemEntity file) async {
    if (file is File) {
      try {
        return (await file.length()).toDouble();
      } catch (_) {
        return 0;
      }
    }
    if (file is Directory) {
      double total = 0;
      try {
        await for (final child in file.list()) {
          total += await _getTotalSizeOfFilesInDir(child);
        }
      } catch (e) {}
      return total;
    }
    return 0;
  }

  Future<double> _getPackageSizeInDir(Directory dir) async {
    double total = 0;
    if (dir.existsSync()) {
      try {
        await for (var child in dir.list(recursive: true)) {
          if (child is File) {
            String name = child.path.toLowerCase();
            if (name.endsWith('.apk') || name.endsWith('.exe')) {
              total += await child.length();
            }
          }
        }
      } catch (e) {}
    }
    return total;
  }

  Future<void> _clearCache() async {
    _showLoadingDialog(context, "正在深度清理缓存...");

    try {
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();

      final tempDir = await getTemporaryDirectory();
      await _deleteDirectoryContents(tempDir);

      final supportDir = await getApplicationSupportDirectory();
      await _deleteDirectoryContents(supportDir);

      final docDir = await getApplicationDocumentsDirectory();
      await _deletePackageFilesInDir(docDir);

      if (Platform.isAndroid) {
        final extDir = await getExternalStorageDirectory();
        if (extDir != null) await _deletePackageFilesInDir(extDir);
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
        _closeLoadingDialog(context);
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('✅ 深度清理完成，设备空间已大幅释放！')));
        await _calculateCacheSize();
      }
    }
  }

  Future<void> _deleteDirectoryContents(Directory dir) async {
    if (dir.existsSync()) {
      try {
        await for (var child in dir.list()) {
          try {
            await child.delete(recursive: true);
          } catch (e) {}
        }
      } catch (e) {}
    }
  }

  Future<void> _deletePackageFilesInDir(Directory dir) async {
    if (dir.existsSync()) {
      try {
        await for (var child in dir.list(recursive: true)) {
          if (child is File) {
            String name = child.path.toLowerCase();
            if (name.endsWith('.apk') || name.endsWith('.exe')) {
              try {
                await child.delete();
              } catch (e) {}
            }
          }
        }
      } catch (e) {}
    }
  }

  Future<void> _showStorageAnalysis() async {
    _showLoadingDialog(context, "正在分析存储空间...");

    List<Map<String, dynamic>> allFiles = [];
    Map<String, double> dirSizes = {
      '沙盒真实根目录 (App Root)': 0,
      '外部存储 (External)': 0,
    };

    Future<void> scanDirectory(Directory? dir, String dirName) async {
      if (dir == null || !dir.existsSync()) return;
      try {
        double totalSize = 0;
        await for (var entity in dir.list(recursive: true, followLinks: false)) {
          if (entity is File) {
            try {
              final size = await entity.length();
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
        _closeLoadingDialog(context);
        _showFilesDialog(topFiles, dirSizes);
      }
    } catch (e) {
      if (mounted) {
        _closeLoadingDialog(context);
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
                                                  if (await file.exists()) {
                                                    await file.delete();
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
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => ChangePasswordDialog(
        userId: _userId!,
        onLogout: (force) => _handleLogout(force: force),
      ),
    );
  }

  void _showHomeSectionManager() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => const HomeSectionManagerDialog(),
    );
    if (result == true) {
      _loadSettings();
    }
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

  Future<Map<int, Map<String, int>>?> _showZfTimeConfigDialog(
      BuildContext context) async {
    return showDialog<Map<int, Map<String, int>>>(
      context: context,
      barrierDismissible: false,
      builder: (context) => const ZfTimeConfigDialog(),
    );
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
      }
      // 🚀 重点修改：正方系统适配
      else if (content.contains('timetable_con') || content.contains('id="table1"')) {
        sourceName = "正方教务系统";

        // A. 先关闭原本处于“正在识别”状态的加载弹窗
        if (dialogContext != null && dialogContext!.mounted) {
          Navigator.pop(dialogContext!);
        }

        // B. 弹出全新的时间配置表让用户确认（可独立修改开始和结束时间）
        Map<int, Map<String, int>>? userAdjustedTimes = await _showZfTimeConfigDialog(context);

        if (userAdjustedTimes == null) {
          return; // 用户取消了配置
        }

        // C. 重新显示进度弹窗进行导入操作
        _showLoadingDialog(context, "正在按照校准的时间导入课表...");

        if (_semesterStart == null) {
          _closeLoadingDialog(context);
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('⚠️ 请先设置开学日期')));
          return;
        }

        success = await CourseService.importZfSoftScheduleFromHtml(
            content,
            _semesterStart!,
            customTimes: userAdjustedTimes
        );
      }
      else if (['mhtml', 'html', 'htm'].contains(ext) ||
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

      // 如果是正方教务，导入逻辑已经由 showLoadingDialog 包装，这里需要处理一下 UI 关闭
      if (sourceName == "正方教务系统") {
        _closeLoadingDialog(context);
      }

      if (success) {
        statusNotifier.value = "✅ $sourceName 导入成功！\n请返回主页查看课表";
        _rescheduleReminders(); // 🐘 新增：导入成功后立即重新调度闹钟
        if (sourceName != "正方教务系统") {
          await Future.delayed(const Duration(milliseconds: 1200));
          if (dialogContext != null && dialogContext!.mounted) {
            Navigator.pop(dialogContext!);
          }
        } else {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('✅ $sourceName 导入成功！')));
        }
      } else {
        statusNotifier.value = "❌ 导入失败\n课表解析错误或文件已损坏";
        if (sourceName != "正方教务系统") {
          await Future.delayed(const Duration(seconds: 2));
          if (dialogContext != null && dialogContext!.mounted) {
            Navigator.pop(dialogContext!);
          }
        } else {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('❌ 导入失败')));
        }
      }
    } catch (e) {
      debugPrint("处理智能导入时崩溃: $e");
      statusNotifier.value = "❌ 发生异常\n读取文件失败或格式崩溃";
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
        _rescheduleReminders(); // 🐘 新增：全量同步后重新调度闹钟
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

    _showLoadingDialog(context, "正在同步到云端...");

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
    _closeLoadingDialog(context);

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

    _showLoadingDialog(context, "正在获取云端数据...");

    try {
      // 🚀 1. 并发拉取：同时获取【学期设置】和【课表数据】
      final userSettingsFuture = ApiService.fetchUserSettings();
      final coursesFuture = ApiService.fetchCourses(_userId!);

      final results = await Future.wait([userSettingsFuture, coursesFuture]);
      final Map<String, dynamic>? userSettings = results[0] as Map<String, dynamic>?;
      final List<dynamic> data = results[1] as List<dynamic>;

      if (!mounted) return;

      // 🚀 2. 如果云端有学期设置，优先同步并覆盖到本地
      if (userSettings != null) {
        final prefs = await SharedPreferences.getInstance();

        if (userSettings['semester_start'] != null) {
          _semesterStart = DateTime.fromMillisecondsSinceEpoch(userSettings['semester_start']);
          await prefs.setString(StorageService.KEY_SEMESTER_START, _semesterStart!.toIso8601String());
        }
        if (userSettings['semester_end'] != null) {
          _semesterEnd = DateTime.fromMillisecondsSinceEpoch(userSettings['semester_end']);
          await prefs.setString(StorageService.KEY_SEMESTER_END, _semesterEnd!.toIso8601String());
        }

        // 刷新页面状态，让 UI 立刻响应云端拉取下来的新日期
        setState(() {});
      }

      _closeLoadingDialog(context);

      if (data.isNotEmpty) {
        // 🚀 3. 再次校验：如果同步了设置后，_semesterStart 依然为空（说明云端和本地都没配过），再进行拦截
        if (_semesterStart == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('⚠️ 云端与本地均未配置开学日期，无法计算课表具体日期')),
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
          _rescheduleReminders(); // 🐘 新增：拉取后重新调度闹钟
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('✅ 成功从云端同步 ${courses.length} 条课程与学期设置')),
          );
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('❌ 获取失败，云端暂无课表数据')),
        );
      }
    } catch (e) {
      if (mounted) {
        _closeLoadingDialog(context);
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

  // Helper method to show a persistent loading dialog
  void _showLoadingDialog(BuildContext context, String message) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        content: Row(
          children: [
            const CircularProgressIndicator(),
            const SizedBox(width: 20),
            Expanded(child: Text(message)),
          ],
        ),
      ),
    );
  }

  // Helper method to close the loading dialog
  void _closeLoadingDialog(BuildContext context) {
    if (Navigator.of(context).canPop()) {
      Navigator.of(context, rootNavigator: true).pop();
    }
  }

  // ─── 重新调度所有保活提醒 ──────────────────────────────────────
  Future<void> _rescheduleReminders() async {
    if (_username.isEmpty || _username == "未登录") return;
    try {
      final todos = await StorageService.getTodos(_username);
      final courses = await CourseService.getAllCourses();
      await ReminderScheduleService.scheduleAll(todos: todos, courses: courses);
      debugPrint("✅ 设置页面：已触发提醒重新调度");
    } catch (e) {
      debugPrint("❌ 设置页面：重新调度提醒失败: $e");
    }
  }

  // ─── 一键迁移弹窗逻辑 ──────────────────────────────────────
  Future<void> _showMigrationDialog() async {
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => MigrationDialog(
        onSuccess: () => _fetchAccountStatus(),
      ),
    );
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
        AccountSection(
          username: _username,
          userId: _userId,
          userTier: _userTier,
          syncProgress: _syncProgress,
          isLoadingStatus: _isLoadingStatus,
          onRefreshStatus: _fetchAccountStatus,
          onForceFullSync: _forceFullSync,
          onLogout: () => _handleLogout(force: false),
          onChangePassword: _showChangePasswordDialog,
        ),
        CourseSection(
          onUploadCourses: _uploadCoursesToCloud,
          onSmartImport: _smartImportCourse,
          onFetchFromCloud: _fetchCoursesFromCloud,
          noCourseBehavior: _noCourseBehavior,
          onNoCourseBehaviorChanged: (val) {
            if (val != null) {
              setState(() => _noCourseBehavior = val);
              SharedPreferences.getInstance()
                  .then((prefs) => prefs.setString('no_course_behavior', val));
            }
          },
        ),
        SemesterSection(
          semesterEnabled: _semesterEnabled,
          onSemesterEnabledChanged: (val) {
            setState(() => _semesterEnabled = val);
            StorageService.saveAppSetting(
                StorageService.KEY_SEMESTER_PROGRESS_ENABLED, val);
          },
          semesterStart: _semesterStart,
          semesterEnd: _semesterEnd,
          onPickSemesterDate: _pickSemesterDate,
          onFetchFromCloud: _fetchCoursesFromCloud,
        ),
        PreferenceSection(
          onManageHomeSections: _showHomeSectionManager,
          syncInterval: _syncInterval,
          onSyncIntervalChanged: (val) {
            if (val != null) {
              setState(() => _syncInterval = val);
              StorageService.saveAppSetting(
                  StorageService.KEY_SYNC_INTERVAL, val);
            }
          },
          serverChoice: _serverChoice,
          onServerChoiceChanged: (val) async {
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
          themeMode: _themeMode,
          onThemeModeChanged: (val) {
            if (val != null) {
              setState(() => _themeMode = val);
              StorageService.saveAppSetting(StorageService.KEY_THEME_MODE, val);
              StorageService.themeNotifier.value = val;
            }
          },
          taiDbPath: _taiDbPath,
          onPickTaiDatabase: _pickTaiDatabase,
          floatWindowEnabled: _floatWindowEnabled,
          onFloatWindowEnabledChanged: Platform.isWindows
              ? (val) async {
            setState(() => _floatWindowEnabled = val);
            final prefs = await SharedPreferences.getInstance();
            await prefs.setBool('float_window_enabled', val);
          }
              : null,
        ),
        PermissionSection(
          permissionDefs: _permissionDefs,
          permissionStatuses: _permissionStatuses,
          isCheckingPermissions: _isCheckingPermissions,
          onCheckAllPermissions: _checkAllPermissions,
          onRequestOrOpenPermission: _requestOrOpenPermission,
        ),
        AdvancedSection(
          onShowMigrationDialog: _showMigrationDialog,
          onTestCourseNotification: _testCourseNotification,
          liveUpdatesStatus: _liveUpdatesStatus,
          onCheckAndOpenLiveUpdates: _checkAndOpenLiveUpdates,
          islandStatus: _islandStatus,
          onCheckIslandSupport: _checkIslandSupport,
        ),
        SystemSection(
          onOpenFeatureGuide: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) =>
                const FeatureGuideScreen(isManualReview: true),
              ),
            );
          },
          cacheSizeStr: _cacheSizeStr,
          onClearCache: _clearCache,
          onShowStorageAnalysis: _showStorageAnalysis,
          isCheckingUpdate: _isCheckingUpdate,
          onCheckUpdates: _checkUpdatesAndNotices,
          onLogout: () => _handleLogout(force: false),
        ),
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
                AccountSection(
                  username: _username,
                  userId: _userId,
                  userTier: _userTier,
                  syncProgress: _syncProgress,
                  isLoadingStatus: _isLoadingStatus,
                  onRefreshStatus: _fetchAccountStatus,
                  onForceFullSync: _forceFullSync,
                  onLogout: () => _handleLogout(force: false),
                  onChangePassword: _showChangePasswordDialog,
                ),
                CourseSection(
                  onUploadCourses: _uploadCoursesToCloud,
                  onSmartImport: _smartImportCourse,
                  onFetchFromCloud: _fetchCoursesFromCloud,
                  noCourseBehavior: _noCourseBehavior,
                  onNoCourseBehaviorChanged: (val) {
                    if (val != null) {
                      setState(() => _noCourseBehavior = val);
                      SharedPreferences.getInstance()
                          .then((prefs) => prefs.setString('no_course_behavior', val));
                    }
                  },
                ),
                SemesterSection(
                  semesterEnabled: _semesterEnabled,
                  onSemesterEnabledChanged: (val) {
                    setState(() => _semesterEnabled = val);
                    StorageService.saveAppSetting(
                        StorageService.KEY_SEMESTER_PROGRESS_ENABLED, val);
                  },
                  semesterStart: _semesterStart,
                  semesterEnd: _semesterEnd,
                  onPickSemesterDate: _pickSemesterDate,
                  onFetchFromCloud: _fetchCoursesFromCloud,
                ),
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
                PreferenceSection(
                  onManageHomeSections: _showHomeSectionManager,
                  syncInterval: _syncInterval,
                  onSyncIntervalChanged: (val) {
                    if (val != null) {
                      setState(() => _syncInterval = val);
                      StorageService.saveAppSetting(
                          StorageService.KEY_SYNC_INTERVAL, val);
                    }
                  },
                  serverChoice: _serverChoice,
                  onServerChoiceChanged: (val) async {
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
                  themeMode: _themeMode,
                  onThemeModeChanged: (val) {
                    if (val != null) {
                      setState(() => _themeMode = val);
                      StorageService.saveAppSetting(StorageService.KEY_THEME_MODE, val);
                      StorageService.themeNotifier.value = val;
                    }
                  },
                  taiDbPath: _taiDbPath,
                  onPickTaiDatabase: _pickTaiDatabase,
                  floatWindowEnabled: _floatWindowEnabled,
                  onFloatWindowEnabledChanged: Platform.isWindows
                      ? (val) async {
                    setState(() => _floatWindowEnabled = val);
                    final prefs = await SharedPreferences.getInstance();
                    await prefs.setBool('float_window_enabled', val);
                  }
                      : null,
                ),
                PermissionSection(
                  permissionDefs: _permissionDefs,
                  permissionStatuses: _permissionStatuses,
                  isCheckingPermissions: _isCheckingPermissions,
                  onCheckAllPermissions: _checkAllPermissions,
                  onRequestOrOpenPermission: _requestOrOpenPermission,
                ),
                AdvancedSection(
                  onShowMigrationDialog: _showMigrationDialog,
                  onTestCourseNotification: _testCourseNotification,
                  liveUpdatesStatus: _liveUpdatesStatus,
                  onCheckAndOpenLiveUpdates: _checkAndOpenLiveUpdates,
                  islandStatus: _islandStatus,
                  onCheckIslandSupport: _checkIslandSupport,
                ),
                SystemSection(
                  onOpenFeatureGuide: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) =>
                        const FeatureGuideScreen(isManualReview: true),
                      ),
                    );
                  },
                  cacheSizeStr: _cacheSizeStr,
                  onClearCache: _clearCache,
                  onShowStorageAnalysis: _showStorageAnalysis,
                  isCheckingUpdate: _isCheckingUpdate,
                  onCheckUpdates: _checkUpdatesAndNotices,
                  onLogout: () => _handleLogout(force: false),
                ),
                const SizedBox(height: 40),
              ],
            ),
          ),
        ],
      ),
    );
  }
}