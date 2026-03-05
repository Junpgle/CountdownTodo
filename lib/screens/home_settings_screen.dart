import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:io';
import 'dart:math';
import 'dart:convert';
import 'dart:ui';
import 'dart:isolate';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:flutter_downloader/flutter_downloader.dart';
import 'package:path_provider/path_provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:file_picker/file_picker.dart';

import '../models.dart';
import '../storage_service.dart';
import '../update_service.dart';
import '../services/api_service.dart';
import '../services/notification_service.dart';
import 'login_screen.dart';

// 引入课程数据服务来处理导入和通知测试
import '../services/course_service.dart';

@pragma('vm:entry-point')
void downloadCallback(String id, int status, int progress) {
  final SendPort? send = IsolateNameServer.lookupPortByName('downloader_send_port');
  send?.send([id, status, progress]);
}

class SettingsPage extends StatefulWidget {
  const SettingsPage({Key? key}) : super(key: key);

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  static const platform = MethodChannel('com.math_quiz.junpgle.com.math_quiz_app/notifications');
  final ReceivePort _port = ReceivePort();

  String _shizukuStatus = "点击右侧按钮获取或检查权限";
  String _islandStatus = "点击检测设备是否支持";
  String _liveUpdatesStatus = "点击检测或去开启 (Android 16+)";
  bool _isCheckingUpdate = false;

  // 用户与偏好设置状态
  String _username = "加载中...";
  int? _userId;
  int _syncInterval = 0;
  String _themeMode = 'system';
  String _noCourseBehavior = 'keep';

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

  @override
  void initState() {
    super.initState();
    _loadSettings().then((_) => _fetchAccountStatus());
    _setupDownloadListener();
    _calculateCacheSize();
  }

  @override
  void dispose() {
    IsolateNameServer.removePortNameMapping('downloader_send_port');
    _port.close();
    super.dispose();
  }

  // 获取当前账户等级和同步额度
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
      final DateTime lastSync = DateTime.fromMillisecondsSinceEpoch(lastSyncTime);
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
        } catch(e) {
          useCache = false;
        }
      }
    }

    if (useCache) return;

    try {
      final response = await http.get(Uri.parse('${ApiService.baseUrl}/api/user/status?user_id=$_userId'));
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
        if (mounted) setState(() { _userTier = "Free"; _isLoadingStatus = false; });
      }
    } catch (e) {
      if (mounted) setState(() { _userTier = "未知"; _isLoadingStatus = false; });
    }
  }

  // === 深度缓存计算与清理 ===
  Future<void> _calculateCacheSize() async {
    try {
      double size = 0;

      final tempDir = await getTemporaryDirectory();
      size += _getTotalSizeOfFilesInDir(tempDir);

      final supportDir = await getApplicationSupportDirectory();
      size += _getTotalSizeOfFilesInDir(supportDir);

      final docDir = await getApplicationDocumentsDirectory();
      size += _getApkSizeInDir(docDir);

      if (Platform.isAndroid) {
        final extDir = await getExternalStorageDirectory();
        if (extDir != null) {
          size += _getApkSizeInDir(extDir);
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

  double _getApkSizeInDir(Directory dir) {
    double total = 0;
    if (dir.existsSync()) {
      try {
        for (var child in dir.listSync(recursive: true)) {
          if (child is File && child.path.toLowerCase().endsWith('.apk')) {
            total += child.lengthSync();
          }
        }
      } catch (e) {}
    }
    return total;
  }

  String _formatSize(double value) {
    if (value == 0) return '0 B';
    if (value < 1024) return '${value.toStringAsFixed(0)} B';
    if (value < 1024 * 1024) return '${(value / 1024).toStringAsFixed(2)} KB';
    if (value < 1024 * 1024 * 1024) return '${(value / (1024 * 1024)).toStringAsFixed(2)} MB';
    return '${(value / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
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
      _deleteApkFilesInDir(docDir);

      if (Platform.isAndroid) {
        final extDir = await getExternalStorageDirectory();
        if (extDir != null) _deleteApkFilesInDir(extDir);
      }

      try {
        final tasks = await FlutterDownloader.loadTasks();
        if (tasks != null) {
          for (var task in tasks) {
            await FlutterDownloader.remove(taskId: task.taskId, shouldDeleteContent: true);
          }
        }
      } catch (e) {}

    } catch (e) {
      debugPrint("深度清理缓存失败: $e");
    } finally {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('✅ 深度清理完成，设备空间已大幅释放！')));
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

  void _deleteApkFilesInDir(Directory dir) {
    if (dir.existsSync()) {
      try {
        for (var child in dir.listSync(recursive: true)) {
          if (child is File && child.path.toLowerCase().endsWith('.apk')) {
            try {
              child.deleteSync();
            } catch (e) {}
          }
        }
      } catch (e) {}
    }
  }

  // === 空间占用超级底层分析工具 ===
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
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('扫描失败: $e')));
      }
    }
  }

  void _showFilesDialog(List<Map<String, dynamic>> topFiles, Map<String, double> dirSizes) {
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
                    const Text("📁 目录总览:", style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    ...dirSizes.entries.map((e) => Padding(
                      padding: const EdgeInsets.only(bottom: 4.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(e.key, style: const TextStyle(fontSize: 13)),
                          Text(_formatSize(e.value), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                        ],
                      ),
                    )),
                    const Divider(height: 24),
                    const Text("📄 Top 100 大文件 (点击垃圾桶可直删):", style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Expanded(
                      child: topFiles.isEmpty
                          ? const Center(child: Text("未发现大于 50KB 的文件"))
                          : ListView.separated(
                        itemCount: topFiles.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
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
                                  isCore ? Icons.warning_amber_rounded : Icons.insert_drive_file,
                                  color: isCore ? Colors.orange : Colors.grey
                              ),
                              title: Text(
                                fileName,
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: isCore ? Colors.orange : null),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Text(
                                  path,
                                  style: const TextStyle(fontSize: 10, color: Colors.grey),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis
                              ),
                              trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(_formatSize(size.toDouble()), style: const TextStyle(color: Colors.redAccent, fontSize: 12, fontWeight: FontWeight.bold)),
                                    IconButton(
                                        padding: const EdgeInsets.only(left: 8),
                                        constraints: const BoxConstraints(),
                                        icon: const Icon(Icons.delete_outline, size: 20),
                                        onPressed: () async {
                                          if (isCore) {
                                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('⚠️ 这个是应用运行核心文件或你的用户数据库，禁止删除！')));
                                            return;
                                          }
                                          try {
                                            if (file.existsSync()) {
                                              file.deleteSync();
                                              setDialogState(() {
                                                topFiles.removeAt(index);
                                              });
                                              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('✅ 文件已删除')));
                                            }
                                          } catch(e) {
                                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('删除失败: $e')));
                                          }
                                        }
                                    )
                                  ]
                              )
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("关闭")),
              ],
            );
          },
        );
      },
    );
  }

  // === 既有逻辑 ===
  void _setupDownloadListener() {
    IsolateNameServer.removePortNameMapping('downloader_send_port');
    IsolateNameServer.registerPortWithName(_port.sendPort, 'downloader_send_port');

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
        await UpdateService.installApk(fullPath);
      }
    } catch (e) {}
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    int interval = await StorageService.getSyncInterval();
    String theme = await StorageService.getThemeMode();

    bool sEnabled = await StorageService.getSemesterEnabled();
    DateTime? sStart = await StorageService.getSemesterStart();
    DateTime? sEnd = await StorageService.getSemesterEnd();

    String? noCourseBehaviorPref = prefs.getString('no_course_behavior');

    setState(() {
      _username = prefs.getString(StorageService.KEY_CURRENT_USER) ?? "未登录";
      _userId = prefs.getInt('current_user_id');
      _syncInterval = interval;
      _themeMode = theme;
      _semesterEnabled = sEnabled;
      _semesterStart = sStart;
      _semesterEnd = sEnd;
      if (noCourseBehaviorPref != null) {
        _noCourseBehavior = noCourseBehaviorPref;
      }
    });
  }

  Future<void> _pickSemesterDate(bool isStart) async {
    DateTime initialDate = (isStart ? _semesterStart : _semesterEnd) ?? DateTime.now();
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
          StorageService.saveAppSetting(StorageService.KEY_SEMESTER_START, picked.toIso8601String());
        } else {
          _semesterEnd = picked;
          StorageService.saveAppSetting(StorageService.KEY_SEMESTER_END, picked.toIso8601String());
        }
      });
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
        builder: (ctx) => StatefulBuilder(
            builder: (context, setDialogState) {
              return AlertDialog(
                title: const Text("修改密码"),
                content: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: oldPassCtrl, obscureText: true,
                        decoration: const InputDecoration(labelText: "当前密码", prefixIcon: Icon(Icons.lock_outline)),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: newPassCtrl, obscureText: true,
                        decoration: const InputDecoration(labelText: "新密码", prefixIcon: Icon(Icons.lock)),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: confirmPassCtrl, obscureText: true,
                        decoration: const InputDecoration(labelText: "确认新密码", prefixIcon: Icon(Icons.check_circle_outline)),
                      ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                      onPressed: isSubmitting ? null : () => Navigator.pop(ctx),
                      child: const Text("取消")
                  ),
                  FilledButton(
                    onPressed: isSubmitting ? null : () async {
                      if (newPassCtrl.text != confirmPassCtrl.text) {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('两次输入的新密码不一致')));
                        return;
                      }
                      if (newPassCtrl.text.isEmpty || oldPassCtrl.text.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请填写完整')));
                        return;
                      }

                      setDialogState(() => isSubmitting = true);
                      final res = await ApiService.changePassword(_userId!, oldPassCtrl.text, newPassCtrl.text);
                      setDialogState(() => isSubmitting = false);

                      if (!context.mounted) return;
                      Navigator.pop(ctx);
                      ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(res['message'] ?? (res['success'] ? '修改成功' : '修改失败')))
                      );

                      if (res['success']) {
                        _handleLogout(force: true);
                      }
                    },
                    child: isSubmitting
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Text("确认修改"),
                  ),
                ],
              );
            }
        )
    );
  }

  void _showHomeSectionManager() async {
    final prefs = await SharedPreferences.getInstance();

    final bool isTablet = MediaQuery.of(context).size.width >= 768;

    List<String>? leftOrder = prefs.getStringList('home_section_order_left');
    List<String>? rightOrder = prefs.getStringList('home_section_order_right');

    final List<String> defaultOrder = ['courses', 'countdowns', 'todos', 'screenTime', 'math'];

    if (leftOrder == null || rightOrder == null) {
      List<String> oldOrder = prefs.getStringList('home_section_order') ?? defaultOrder;
      leftOrder = [];
      rightOrder = [];
      for (int i = 0; i < oldOrder.length; i++) {
        if (i % 2 == 0) leftOrder.add(oldOrder[i]);
        else rightOrder.add(oldOrder[i]);
      }
    }

    List<String> combined = [...leftOrder, ...rightOrder];
    for (var key in defaultOrder) {
      if (!combined.contains(key)) leftOrder.add(key);
    }
    leftOrder.removeWhere((key) => !defaultOrder.contains(key));
    rightOrder.removeWhere((key) => !defaultOrder.contains(key));

    List<String> mobileCombinedOrder = [...leftOrder, ...rightOrder];

    Map<String, bool> visibility = {'courses': true, 'countdowns': true, 'todos': true, 'screenTime': true, 'math': true};
    String? visStr = prefs.getString('home_section_visibility');
    if (visStr != null) visibility = Map<String, bool>.from(jsonDecode(visStr));
    for (var key in defaultOrder) visibility.putIfAbsent(key, () => true);

    Map<String, String> names = {
      'courses': '课程提醒',
      'countdowns': '重要日与倒计时',
      'todos': '待办事项清单',
      'screenTime': '屏幕时间面板',
      'math': '数学测验入口'
    };

    if (!mounted) return;

    showDialog(
        context: context,
        builder: (ctx) => StatefulBuilder(
            builder: (context, setDialogState) {

              void moveItem(String item, {String? targetKey, bool? toLeftList}) {
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
                    if (toLeftList) leftOrder!.add(item);
                    else rightOrder!.add(item);
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
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(color: Theme.of(context).colorScheme.primaryContainer.withOpacity(0.9), borderRadius: BorderRadius.circular(8)),
                      child: Text(names[key] ?? key, style: TextStyle(fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.onPrimaryContainer)),
                    ),
                  ),
                  childWhenDragging: Opacity(
                    opacity: 0.3,
                    child: CheckboxListTile(title: Text(names[key] ?? key), value: visibility[key], onChanged: null),
                  ),
                  child: DragTarget<String>(
                      onWillAccept: (data) => data != key,
                      onAccept: (data) => moveItem(data, targetKey: key),
                      builder: (context, candidateData, rejectedData) {
                        return Container(
                          decoration: BoxDecoration(
                            border: candidateData.isNotEmpty ? Border(top: BorderSide(color: Theme.of(context).colorScheme.primary, width: 3)) : null,
                          ),
                          child: CheckboxListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(names[key] ?? key, style: const TextStyle(fontSize: 14)),
                            value: visibility[key],
                            secondary: const Icon(Icons.drag_indicator, color: Colors.grey, size: 20),
                            onChanged: (val) => setDialogState(() => visibility[key] = val ?? true),
                          ),
                        );
                      }
                  ),
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
                            color: candidateData.isNotEmpty ? Theme.of(context).colorScheme.primaryContainer.withOpacity(0.1) : Colors.transparent,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.grey.withOpacity(0.2)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(
                                padding: const EdgeInsets.all(8.0),
                                child: Text(isLeft ? "屏幕左栏" : "屏幕右栏", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
                              ),
                              ...items.map((key) => buildDraggableItem(key)),
                            ],
                          ),
                        );
                      }
                  ),
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
                            isTablet ? "长按模块，可跨越左右栏进行拖拽。\n勾选控制该模块是否在首页展示。" : "长按右侧把手拖拽改变顺序，勾选控制是否展示。",
                            style: const TextStyle(color: Colors.grey, fontSize: 13)
                        ),
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
                              final item = mobileCombinedOrder.removeAt(oldIndex);
                              mobileCombinedOrder.insert(newIndex, item);
                            });
                          },
                          children: mobileCombinedOrder.map((key) {
                            return CheckboxListTile(
                              key: Key(key),
                              contentPadding: EdgeInsets.zero,
                              title: Text(names[key] ?? key),
                              value: visibility[key] ?? true,
                              secondary: const Icon(Icons.drag_handle, color: Colors.grey),
                              onChanged: (val) {
                                setDialogState(() => visibility[key] = val ?? true);
                              },
                            );
                          }).toList(),
                        ),
                      ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("取消")),
                  FilledButton(
                    onPressed: () {
                      if (!isTablet) {
                        leftOrder!.clear();
                        rightOrder!.clear();
                        int mid = (mobileCombinedOrder.length / 2).ceil();
                        for (int i = 0; i < mobileCombinedOrder.length; i++) {
                          if (i < mid) leftOrder!.add(mobileCombinedOrder[i]);
                          else rightOrder!.add(mobileCombinedOrder[i]);
                        }
                      }

                      prefs.setStringList('home_section_order_left', leftOrder!);
                      prefs.setStringList('home_section_order_right', rightOrder!);
                      prefs.setString('home_section_visibility', jsonEncode(visibility));
                      Navigator.pop(ctx);
                      ScaffoldMessenger.of(this.context).showSnackBar(const SnackBar(content: Text('已保存，请返回主页查看更新')));
                    },
                    child: const Text("保存并应用"),
                  )
                ],
              );
            }
        )
    );
  }

  Future<void> _checkAndOpenLiveUpdates() async {
    try {
      final bool hasPermission = await platform.invokeMethod('checkLiveUpdatesPermission') ?? true;
      if (!hasPermission) {
        setState(() => _liveUpdatesStatus = "权限未开启，尝试跳转设置...");
        final bool opened = await platform.invokeMethod('openLiveUpdatesSettings') ?? false;

        if (opened) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('请在设置中打开“推广的通知/实时更新”权限'), duration: Duration(seconds: 3)),
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

  // 🚀 弹出课表来源选择面板
  void _showImportSourcePicker() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.all(16.0),
                child: Text('选择课表来源', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ),
              ListTile(
                leading: const Icon(Icons.school, color: Colors.blue),
                title: const Text('聚在工大 (合肥工业大学)'),
                subtitle: const Text('支持 JSON / TXT 格式数据'),
                onTap: () {
                  Navigator.pop(ctx);
                  _importCourse('hfut');
                },
              ),
              ListTile(
                leading: const Icon(Icons.account_balance, color: Colors.redAccent),
                title: const Text('我的课表App (厦门大学)'),
                subtitle: const Text('支持 MHTML / HTML 网页导出格式'),
                onTap: () {
                  Navigator.pop(ctx);
                  _importCourse('xmu');
                },
              ),
              const SizedBox(height: 10),
            ],
          ),
        );
      },
    );
  }

  // 🚀 统一的课表导入处理逻辑
  Future<void> _importCourse(String source) async {
    // 厦大课表需要知道开学日期来推算具体的上课日期 (yyyy-MM-dd)
    if (source == 'xmu' && _semesterStart == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('⚠️ 请先在下方【学期设置】中设置“开学日期”！')),
      );
      return;
    }

    // 🚀 核心修复：将 type 改为 FileType.any，完全绕过安卓自带的文件类型过滤限制
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.any,
    );

    if (result != null && result.files.single.path != null) {
      String filePath = result.files.single.path!;
      String ext = filePath.split('.').last.toLowerCase();

      // 在 Dart 层面做简单的后缀名软提示
      if (source == 'xmu' && !['mhtml', 'html', 'txt'].contains(ext)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('⚠️ 提示：建议选择 .mhtml 或 .html 格式的文件')),
        );
      } else if (source == 'hfut' && !['json', 'txt'].contains(ext)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('⚠️ 提示：建议选择 .json 格式的文件')),
        );
      }

      File file = File(filePath);
      String fileContent = await file.readAsString();
      bool success = false;

      // 显示 Loading 弹窗
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Center(child: CircularProgressIndicator()),
      );

      try {
        if (source == 'hfut') {
          success = await CourseService.importScheduleFromJson(fileContent);
        } else if (source == 'xmu') {
          success = await CourseService.importXmuScheduleFromHtml(fileContent, _semesterStart!);
        }
      } catch (e) {
        debugPrint('导入课表发生异常: $e');
      }

      if (mounted) {
        Navigator.pop(context); // 关闭 Loading 弹窗
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(success ? '✅ 课表导入成功' : '❌ 课表解析失败，请检查文件格式')),
        );
      }
    }
  }

  Future<void> _testCourseNotification() async {
    final dashboardData = await CourseService.getDashboardCourses();
    List<CourseItem> courses = (dashboardData['courses'] as List?)?.cast<CourseItem>() ?? [];

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
        timeStr: '${testCourse.formattedStartTime} - ${testCourse.formattedEndTime}',
        teacher: testCourse.teacherName,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('✅ 已发送测试实时通知，请查看状态栏')));
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('❌ 尚未导入课表数据，请先在“课程设置”中导入')));
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
        content: const Text(
            "这将覆盖你云端的所有课表数据。\n\n用于与电脑或其他设备同步。\n\n是否继续？"),
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

  Future<void> _checkUpdatesAndNotices() async {
    setState(() => _isCheckingUpdate = true);
    await UpdateService.checkUpdateAndPrompt(context, isManual: true);
    if (mounted) setState(() => _isCheckingUpdate = false);
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
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("取消")),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text("退出"),
            ),
          ],
        ),
      ) ?? false;
    }

    if (confirm) {
      await StorageService.clearLoginSession();
      if (mounted) {
        Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => const LoginScreen()), (route) => false);
      }
    }
  }

  Widget _buildSection(String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 8.0, bottom: 8.0, top: 16.0),
          child: Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.grey)),
        ),
        Card(
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Column(children: children),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('设置'), centerTitle: true),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          // --- 1. 账户管理 ---
          _buildSection('账户管理', [
            ListTile(
              leading: CircleAvatar(backgroundColor: Theme.of(context).colorScheme.primaryContainer, child: const Icon(Icons.person)),
              title: Text(_username, style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text(_userId != null ? "UID: $_userId" : "离线模式"),
              trailing: const Icon(Icons.edit_square, size: 20, color: Colors.grey),
              onTap: _showChangePasswordDialog,
            ),
            const Divider(height: 1, indent: 56),
            Padding(
              padding: const EdgeInsets.only(left: 56, right: 16, top: 12, bottom: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text("账户等级", style: TextStyle(fontSize: 14)),
                      _isLoadingStatus
                          ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                          : Text(
                        _userTier.toUpperCase(),
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: _userTier.toLowerCase() == 'pro' || _userTier.toLowerCase() == 'admin'
                              ? Colors.orangeAccent
                              : Colors.grey,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Text("今日同步额度", style: TextStyle(fontSize: 12, color: Colors.grey)),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: _syncProgress,
                      minHeight: 6,
                      backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                      valueColor: AlwaysStoppedAnimation<Color>(
                          _syncProgress > 0.9 ? Colors.redAccent : Theme.of(context).colorScheme.primary
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ]),

          // --- 2. 课程设置 ---
          _buildSection('课程设置', [
            ListTile(
              leading: const Icon(Icons.cloud_upload_outlined, color: Colors.blue),
              title: const Text('上传课表到云端'),
              subtitle: const Text('用于与电脑或其他设备同步'),
              trailing: const Icon(Icons.chevron_right),
              onTap: _uploadCoursesToCloud,
            ),
            // 🚀 替换为全新的多来源导入菜单
            ListTile(
              leading: const Icon(Icons.file_upload_outlined),
              title: const Text('导入本地课表'),
              subtitle: const Text('支持多高校格式 (聚在工大 / 厦大)'),
              trailing: const Icon(Icons.chevron_right),
              onTap: _showImportSourcePicker,
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
                    SharedPreferences.getInstance().then((prefs) => prefs.setString('no_course_behavior', val));
                  }
                },
              ),
            ),
          ]),

          // --- 3. 学期设置 ---
          _buildSection('学期设置', [
            SwitchListTile(
              secondary: const Icon(Icons.linear_scale),
              title: const Text('首页学期进度条'),
              value: _semesterEnabled,
              onChanged: (val) {
                setState(() => _semesterEnabled = val);
                StorageService.saveAppSetting(StorageService.KEY_SEMESTER_PROGRESS_ENABLED, val);
              },
            ),
            if (_semesterEnabled) ...[
              ListTile(
                contentPadding: const EdgeInsets.only(left: 56, right: 16),
                title: const Text('开学日期'),
                trailing: Text(_semesterStart == null ? "未设置" : DateFormat('yyyy-MM-dd').format(_semesterStart!)),
                onTap: () => _pickSemesterDate(true),
              ),
              ListTile(
                contentPadding: const EdgeInsets.only(left: 56, right: 16),
                title: const Text('放假日期'),
                trailing: Text(_semesterEnd == null ? "未设置" : DateFormat('yyyy-MM-dd').format(_semesterEnd!)),
                onTap: () => _pickSemesterDate(false),
              ),
            ],
          ]),

          // --- 4. 偏好与通用 ---
          _buildSection('偏好设置', [
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
                    StorageService.saveAppSetting(StorageService.KEY_SYNC_INTERVAL, val);
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
          ]),

          // 3. 高级设置
          const Padding(
            padding: EdgeInsets.only(left: 8.0, bottom: 8.0, top: 16.0),
            child: Text('高级设置', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.grey)),
          ),

          Card(
            elevation: 2,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              leading: const Icon(Icons.notification_important_outlined, color: Colors.amber),
              title: const Text('测试课程实时通知'),
              subtitle: const Text('强制发送一个课程提醒用于排查显示问题'),
              trailing: TextButton(onPressed: _testCourseNotification, child: const Text("发送测试")),
            ),
          ),
          const SizedBox(height: 12),

          Card(
            elevation: 2,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              leading: const CircleAvatar(backgroundColor: Colors.teal, child: Icon(Icons.notifications_active, color: Colors.white)),
              title: const Text('Android 16 实时活动', style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Padding(
                  padding: const EdgeInsets.only(top: 4.0),
                  child: Text(_liveUpdatesStatus, style: TextStyle(color: Colors.grey[600], fontSize: 13))
              ),
              trailing: ElevatedButton(
                  style: ElevatedButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))),
                  onPressed: _checkAndOpenLiveUpdates,
                  child: const Text('去开启')
              ),
            ),
          ),
          const SizedBox(height: 12),

          Card(
            elevation: 2,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              leading: const CircleAvatar(backgroundColor: Colors.deepPurpleAccent, child: Icon(Icons.smart_button, color: Colors.white)),
              title: const Text('小米超级岛支持', style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Padding(
                  padding: const EdgeInsets.only(top: 4.0),
                  child: Text(_islandStatus, style: TextStyle(color: Colors.grey[600], fontSize: 13))
              ),
              trailing: ElevatedButton(
                  style: ElevatedButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))),
                  onPressed: _checkIslandSupport,
                  child: const Text('检测')
              ),
            ),
          ),
          const SizedBox(height: 12),

          // --- 7. 关于与系统 ---
          _buildSection('系统与关于', [
            ListTile(
              leading: const Icon(Icons.cleaning_services, color: Colors.blueAccent),
              title: const Text('深度清理缓存与冗余'),
              subtitle: const Text('包含更新残留包与深度图片缓存'),
              trailing: Text(_cacheSizeStr, style: const TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
              onTap: () async {
                bool confirm = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text("深度清理空间"),
                    content: Text("检测到大约 $_cacheSizeStr 可释放空间。\n这会彻底清除你过往下载的版本更新安装包 (APK) 以及深度的图片缓存，释放大量“用户数据”占用。\n\n(你的本地待办、倒计时与课表数据绝对安全，不受影响)"),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("取消")),
                      FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("清理")),
                    ],
                  ),
                ) ?? false;

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
            const Divider(height: 1, indent: 56),
            ListTile(
              leading: const Icon(Icons.system_update, color: Colors.green),
              title: const Text('检查新版本'),
              trailing: _isCheckingUpdate
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.chevron_right),
              onTap: _isCheckingUpdate ? null : _checkUpdatesAndNotices,
            ),
            const Divider(height: 1, indent: 56),
            ListTile(
              leading: const Icon(Icons.logout, color: Colors.redAccent),
              title: const Text('退出当前账号', style: TextStyle(color: Colors.redAccent)),
              onTap: () => _handleLogout(force: false),
            ),
          ]),

          const SizedBox(height: 40),
        ],
      ),
    );
  }
}