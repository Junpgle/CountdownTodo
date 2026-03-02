import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:io';
import 'dart:math';
import 'dart:convert';
import 'dart:ui';
import 'dart:isolate';
import 'package:intl/intl.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:flutter_downloader/flutter_downloader.dart';
import 'package:path_provider/path_provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models.dart';
import '../storage_service.dart';
import '../update_service.dart';
import '../services/api_service.dart';
import 'login_screen.dart';

// 🌟 核心修复：必须作为顶级函数放在所有类的外部！
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

  // 新增学期进度状态
  bool _semesterEnabled = false;
  DateTime? _semesterStart;
  DateTime? _semesterEnd;

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _setupDownloadListener(); // 初始化下载状态监听
  }

  @override
  void dispose() {
    IsolateNameServer.removePortNameMapping('downloader_send_port');
    _port.close(); // 释放端口资源
    super.dispose();
  }

  // ---------------------------------------------------------
  // 核心监听：监听下载任务状态，完成后自动唤起安装
  // ---------------------------------------------------------

  void _setupDownloadListener() {
    // 💡 核心修复：热重启时 dispose 不会执行，必须在注册前强行解绑旧端口！
    // 否则后台 Isolate 会把消息发给死掉的旧端口，导致 UI 接收不到 100% 下载完成的通知
    IsolateNameServer.removePortNameMapping('downloader_send_port');
    IsolateNameServer.registerPortWithName(_port.sendPort, 'downloader_send_port');

    _port.listen((dynamic data) {
      String id = data[0];
      DownloadTaskStatus status = DownloadTaskStatus.fromInt(data[1]);

      // 下载完成时触发安装
      if (status == DownloadTaskStatus.complete) {
        print("UI 线程监听到下载完成，准备弹出安装器...");
        _handleDownloadCompleted(id);
      }
    });

    // 注册顶级函数
    FlutterDownloader.registerCallback(downloadCallback);
  }

  Future<void> _handleDownloadCompleted(String taskId) async {
    final tasks = await FlutterDownloader.loadTasks();
    if (tasks == null) return;
    try {
      final task = tasks.firstWhere((t) => t.taskId == taskId);
      if (task.filename != null) {
        final String fullPath = "${task.savedDir}/${task.filename}";
        // 延迟 1.5 秒，确保 Android 系统已经将文件完全从缓存写入磁盘
        await Future.delayed(const Duration(milliseconds: 1500));
        await UpdateService.installApk(fullPath);
      }
    } catch (e) {
      print("自动安装逻辑异常: $e");
    }
  }

  // ---------------------------------------------------------
  // 其他设置逻辑
  // ---------------------------------------------------------

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    int interval = await StorageService.getSyncInterval();
    String theme = await StorageService.getThemeMode();

    // 加载学期设置
    bool sEnabled = await StorageService.getSemesterEnabled();
    DateTime? sStart = await StorageService.getSemesterStart();
    DateTime? sEnd = await StorageService.getSemesterEnd();

    setState(() {
      _username = prefs.getString(StorageService.KEY_CURRENT_USER) ?? "未登录";
      _userId = prefs.getInt('current_user_id');
      _syncInterval = interval;
      _themeMode = theme;
      _semesterEnabled = sEnabled;
      _semesterStart = sStart;
      _semesterEnd = sEnd;
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
    List<String> order = prefs.getStringList('home_section_order') ?? ['countdowns', 'todos', 'screenTime', 'math'];
    Map<String, bool> visibility = {'countdowns': true, 'todos': true, 'screenTime': true, 'math': true};

    String? visStr = prefs.getString('home_section_visibility');
    if (visStr != null) {
      visibility = Map<String, bool>.from(jsonDecode(visStr));
    }

    Map<String, String> names = {
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
              return AlertDialog(
                title: const Text("首页模块管理"),
                content: SizedBox(
                  width: double.maxFinite,
                  height: 320,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(bottom: 8.0),
                        child: Text("长按拖拽可改变显示顺序，勾选可控制是否展示。", style: TextStyle(color: Colors.grey, fontSize: 13)),
                      ),
                      Expanded(
                        child: ReorderableListView(
                          shrinkWrap: true,
                          onReorder: (oldIndex, newIndex) {
                            setDialogState(() {
                              if (newIndex > oldIndex) newIndex -= 1;
                              final item = order.removeAt(oldIndex);
                              order.insert(newIndex, item);
                            });
                          },
                          children: order.map((key) {
                            return CheckboxListTile(
                              key: Key(key),
                              contentPadding: EdgeInsets.zero,
                              title: Text(names[key] ?? key),
                              value: visibility[key],
                              secondary: const Icon(Icons.drag_handle, color: Colors.grey),
                              onChanged: (val) {
                                setDialogState(() {
                                  visibility[key] = val ?? true;
                                });
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
                      prefs.setStringList('home_section_order', order);
                      prefs.setString('home_section_visibility', jsonEncode(visibility));
                      Navigator.pop(ctx);
                    },
                    child: const Text("保存并应用"),
                  )
                ],
              );
            }
        )
    );
  }

  void _showHistoricalCountdowns() async {
    final countdowns = await StorageService.getCountdowns(_username);
    List<CountdownItem> history = countdowns.where((item) {
      return item.targetDate.difference(DateTime.now()).inDays + 1 < 0;
    }).toList();

    if (!mounted) return;

    showDialog(
        context: context,
        builder: (ctx) => StatefulBuilder(
            builder: (context, setDialogState) {
              return AlertDialog(
                title: const Text("历史倒计时"),
                content: SizedBox(
                  width: double.maxFinite,
                  height: 350,
                  child: history.isEmpty
                      ? const Center(child: Text("暂无已过期的历史记录", style: TextStyle(color: Colors.grey)))
                      : ListView.builder(
                      itemCount: history.length,
                      itemBuilder: (context, index) {
                        final item = history[index];
                        final diff = (item.targetDate.difference(DateTime.now()).inDays + 1).abs();

                        return Card(
                          elevation: 0,
                          color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.4),
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          child: ListTile(
                            title: Text(item.title, style: const TextStyle(fontWeight: FontWeight.bold)),
                            subtitle: Text("目标日: ${DateFormat('yyyy-MM-dd').format(item.targetDate)}  (已过 $diff 天)"),
                            trailing: IconButton(
                              icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                              onPressed: () {
                                setDialogState(() => history.removeAt(index));
                                countdowns.removeWhere((c) => c.title == item.title && c.targetDate == item.targetDate);
                                StorageService.saveCountdowns(_username, countdowns);
                              },
                            ),
                          ),
                        );
                      }
                  ),
                ),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("关闭"))
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

  Future<void> _requestShizukuPermission() async {
    try {
      final bool result = await platform.invokeMethod('requestShizukuPermission');
      setState(() {
        if (result) {
          _shizukuStatus = "已获得权限，或系统已弹出提示";
        } else {
          _shizukuStatus = "未检测到服务，请激活 Shizuku";
        }
      });
    } on PlatformException catch (e) {
      setState(() => _shizukuStatus = "请求失败: '${e.message}'.");
    }
  }

  Future<void> _checkUpdatesAndNotices() async {
    setState(() => _isCheckingUpdate = true);
    ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('正在检查更新...'), duration: Duration(seconds: 1))
    );

    AppManifest? manifest = await UpdateService.checkManifest();
    if (manifest == null) {
      setState(() => _isCheckingUpdate = false);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('检查失败，请检查网络')));
      return;
    }

    PackageInfo packageInfo = await PackageInfo.fromPlatform();
    bool hasUpdate = _shouldUpdate(
        localVersion: packageInfo.version,
        localBuild: int.tryParse(packageInfo.buildNumber) ?? 0,
        remoteVersion: manifest.versionName,
        remoteBuild: manifest.versionCode
    );
    bool hasNotice = manifest.announcement.show;

    setState(() => _isCheckingUpdate = false);

    if (!hasUpdate && !hasNotice) {
      if (mounted) {
        showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
                title: const Text("检查完成"),
                content: Text("当前版本 (${packageInfo.version}) 已是最新。"),
                actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("好"))]
            )
        );
      }
      return;
    }

    if (!mounted) return;

    showDialog(
      context: context, barrierDismissible: !manifest.forceUpdate,
      builder: (context) {
        return AlertDialog(
          contentPadding: EdgeInsets.zero,
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (manifest.wallpaper.show && manifest.wallpaper.imageUrl.isNotEmpty)
                  ClipRRect(
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                      child: CachedNetworkImage(imageUrl: manifest.wallpaper.imageUrl, height: 200, fit: BoxFit.cover)
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
                        Text("当前: ${packageInfo.version}  →  最新: ${manifest.versionName}", style: const TextStyle(fontSize: 12, color: Colors.blue, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 10),
                        Text(manifest.updateInfo.description),
                        const SizedBox(height: 15),
                        if (manifest.updateInfo.fullPackageUrl.isNotEmpty)
                          ElevatedButton.icon(
                              icon: const Icon(Icons.download),
                              label: const Text("立即安装新版本"),
                              onPressed: () {
                                Navigator.pop(context); // 点击下载后关闭弹窗
                                _startDownload(manifest);
                              }
                          ),
                        const Divider(height: 30),
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
              TextButton(onPressed: () => Navigator.pop(context), child: const Text("关闭"))
          ],
        );
      },
    );
  }

  bool _shouldUpdate({required String localVersion, required int localBuild, required String remoteVersion, required int remoteBuild}) {
    List<int> v1 = remoteVersion.split('.').map(int.parse).toList();
    List<int> v2 = localVersion.split('.').map(int.parse).toList();
    for (int i = 0; i < min(v1.length, v2.length); i++) {
      if (v1[i] > v2[i]) return true;
      if (v1[i] < v2[i]) return false;
    }
    return remoteBuild > localBuild;
  }

  Future<void> _startDownload(AppManifest manifest) async {
    // 1. 先检查是否已经下载过这个版本的完整包
    String? existingPath = await UpdateService.isApkAlreadyDownloaded(manifest.versionName);

    if (existingPath != null) {
      print("检测到本地已存在完整安装包，直接安装");
      await UpdateService.installApk(existingPath);
      return;
    }

    // 2. 如果没有，则准备环境（清理旧版本包）
    bool ready = await UpdateService.prepareForDownload(manifest.versionName);
    if (!ready) return;

    final path = await UpdateService.getDownloadDirectory();
    if (path == null) return;

    // 3. 执行真正的下载
    await FlutterDownloader.enqueue(
      url: manifest.updateInfo.fullPackageUrl,
      savedDir: path,
      fileName: UpdateService.getUpdateFileName(manifest.versionName),
      showNotification: true,
      openFileFromNotification: false,
      saveInPublicStorage: true,
    );

    ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("正在下载更新，完成后将自动弹出安装界面..."))
    );
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
          // 1. 账户管理
          _buildSection('账户管理', [
            ListTile(
              leading: CircleAvatar(backgroundColor: Theme.of(context).colorScheme.primaryContainer, child: const Icon(Icons.person)),
              title: Text(_username, style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text(_userId != null ? "UID: $_userId" : "离线模式"),
              trailing: const Icon(Icons.edit_square, size: 20, color: Colors.grey),
              onTap: _showChangePasswordDialog,
            ),
          ]),

          // 2. 偏好与数据设置
          _buildSection('偏好设置', [
            ListTile(
              leading: const Icon(Icons.dashboard_customize_outlined),
              title: const Text('首页模块管理'),
              trailing: const Icon(Icons.chevron_right),
              onTap: _showHomeSectionManager,
            ),
            const Divider(height: 1, indent: 56),
            ListTile(
              leading: const Icon(Icons.history),
              title: const Text('历史倒计时'),
              trailing: const Icon(Icons.chevron_right),
              onTap: _showHistoricalCountdowns,
            ),
            const Divider(height: 1, indent: 56),

            // 学期进度设置项
            SwitchListTile(
              secondary: const Icon(Icons.linear_scale),
              title: const Text('显示学期进度条'),
              subtitle: const Text('在首页顶部显示距离放假的时间进度'),
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
            const Divider(height: 1, indent: 56),
            ListTile(
              leading: const Icon(Icons.sync),
              title: const Text('自动同步数据'),
              trailing: DropdownButton<int>(
                value: _syncInterval,
                underline: const SizedBox(),
                items: const [
                  DropdownMenuItem(value: 5, child: Text('每 5 分钟')),
                  DropdownMenuItem(value: 10, child: Text('每 10 分钟')),
                  DropdownMenuItem(value: 60, child: Text('每小时')),
                  DropdownMenuItem(value: 0, child: Text('每次打开App')),
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
              title: const Text('外观主题'),
              trailing: DropdownButton<String>(
                value: _themeMode,
                underline: const SizedBox(),
                items: const [
                  DropdownMenuItem(value: 'system', child: Text('跟随系统')),
                  DropdownMenuItem(value: 'light', child: Text('浅色模式')),
                  DropdownMenuItem(value: 'dark', child: Text('深色模式')),
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
            child: Text('高级设置 (用于超级岛通知)', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.grey)),
          ),

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

          Card(
            elevation: 2,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              leading: const CircleAvatar(backgroundColor: Colors.blueAccent, child: Icon(Icons.adb, color: Colors.white)),
              title: const Text('Shizuku 授权', style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Padding(
                  padding: const EdgeInsets.only(top: 4.0),
                  child: Text(_shizukuStatus, style: TextStyle(color: Colors.grey[600], fontSize: 13))
              ),
              trailing: ElevatedButton(
                  style: ElevatedButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))),
                  onPressed: _requestShizukuPermission,
                  child: const Text('授权')
              ),
            ),
          ),

          // 4. 系统与账户
          _buildSection('系统与关于', [
            ListTile(
              leading: const Icon(Icons.system_update, color: Colors.green),
              title: const Text('检查更新'),
              trailing: _isCheckingUpdate
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.chevron_right),
              onTap: _isCheckingUpdate ? null : _checkUpdatesAndNotices,
            ),
            const Divider(height: 1, indent: 56),
            ListTile(
              leading: const Icon(Icons.logout, color: Colors.redAccent),
              title: const Text('退出账号', style: TextStyle(color: Colors.redAccent)),
              onTap: () => _handleLogout(force: false),
            ),
          ]),

          const SizedBox(height: 30),
        ],
      ),
    );
  }
}