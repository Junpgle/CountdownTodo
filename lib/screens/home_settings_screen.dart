import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:io';
import 'dart:math';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:flutter_downloader/flutter_downloader.dart';
import 'package:path_provider/path_provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../storage_service.dart';
import '../update_service.dart';
import '../services/api_service.dart';
import 'login_screen.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({Key? key}) : super(key: key);

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  static const platform = MethodChannel('com.math_quiz.junpgle.com.math_quiz_app/notifications');

  String _shizukuStatus = "点击右侧按钮获取或检查权限";
  String _islandStatus = "点击检测设备是否支持";
  bool _isCheckingUpdate = false;

  // 用户与偏好设置状态
  String _username = "加载中...";
  int? _userId;
  int _syncInterval = 0; // 0:每次打开, 5:五分钟, 10:十分钟, 60:一小时
  String _themeMode = 'system'; // 'system', 'light', 'dark'

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _username = prefs.getString(StorageService.KEY_CURRENT_USER) ?? "未登录";
      _userId = prefs.getInt('current_user_id');
    });

    int interval = await StorageService.getSyncInterval();
    String theme = await StorageService.getThemeMode();
    setState(() {
      _syncInterval = interval;
      _themeMode = theme;
    });
  }

  // 修改密码对话框
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

                      // 如果修改成功，选择强制用户重新登录
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

  // 检测超级岛支持
  Future<void> _checkIslandSupport() async {
    try {
      final bool result = await platform.invokeMethod('checkIslandSupport');
      setState(() {
        if (result) {
          _islandStatus = "✅ 设备已支持超级岛！";
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('检测成功：您的设备支持超级岛功能！')),
          );
        } else {
          _islandStatus = "❌ 不支持，或未开启状态栏显示权限";
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('设备不支持，请检查系统版本或是否开启"在状态栏显示"权限')),
          );
        }
      });
    } on PlatformException catch (e) {
      setState(() {
        _islandStatus = "检测失败: '${e.message}'.";
      });
    }
  }

  // 请求 Shizuku 权限
  Future<void> _requestShizukuPermission() async {
    try {
      final bool result = await platform.invokeMethod('requestShizukuPermission');
      setState(() {
        if (result) {
          _shizukuStatus = "已获得权限，或系统已弹出授权提示";
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('如果您通过了授权/ADB指令，配置将自动生效')),
          );
        } else {
          _shizukuStatus = "未检测到 Shizuku 服务，请确保后台已激活 Shizuku";
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Shizuku 未运行，请先去激活')),
          );
        }
      });
    } on PlatformException catch (e) {
      setState(() {
        _shizukuStatus = "请求失败: '${e.message}'.";
      });
    }
  }

  // 检查更新与通知
  Future<void> _checkUpdatesAndNotices() async {
    setState(() => _isCheckingUpdate = true);
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('正在检查更新...'), duration: Duration(seconds: 1)));

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
                  ClipRRect(borderRadius: const BorderRadius.vertical(top: Radius.circular(20)), child: CachedNetworkImage(imageUrl: manifest.wallpaper.imageUrl, height: 200, fit: BoxFit.cover)),
                Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (hasUpdate) ...[
                        Row(children: [const Icon(Icons.new_releases, color: Colors.blue), const SizedBox(width: 8), Text(manifest.updateInfo.title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18))]),
                        const SizedBox(height: 6), Text("当前: ${packageInfo.version}  →  最新: ${manifest.versionName}", style: const TextStyle(fontSize: 12, color: Colors.blue, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 10), Text(manifest.updateInfo.description), const SizedBox(height: 15),
                        if (manifest.updateInfo.fullPackageUrl.isNotEmpty) ElevatedButton.icon(icon: const Icon(Icons.download), label: const Text("下载更新 (APK)"), onPressed: () {
                          Navigator.pop(context); // 点击下载后关闭弹窗
                          _startBackgroundDownload(manifest.updateInfo.fullPackageUrl);
                        }),
                        const Divider(height: 30),
                      ],
                      if (hasNotice) ...[
                        Row(children: [const Icon(Icons.campaign, color: Colors.orange), const SizedBox(width: 8), Text(manifest.announcement.title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18))]),
                        const SizedBox(height: 8), Text(manifest.announcement.content),
                      ]
                    ],
                  ),
                )
              ],
            ),
          ),
          actions: [if (!manifest.forceUpdate) TextButton(onPressed: () => Navigator.pop(context), child: const Text("关闭"))],
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

  Future<void> _startBackgroundDownload(String url) async {
    if (!Platform.isAndroid) return UpdateService.launchURL(url);
    final dir = await getExternalStorageDirectory();
    if (dir != null) {
      await FlutterDownloader.enqueue(url: url, savedDir: dir.path, fileName: 'update.apk', showNotification: true, openFileFromNotification: true);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已开始后台下载，请下拉检查系统通知栏')));
    }
  }

  // 退出账号
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

  // 构建统一风格的卡片组
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
              leading: const Icon(Icons.sync),
              title: const Text('自动同步数据'),
              trailing: DropdownButton<int>(
                value: _syncInterval,
                underline: const SizedBox(),
                items: const [
                  DropdownMenuItem(value: 0, child: Text('每次打开App')),
                  DropdownMenuItem(value: 5, child: Text('每 5 分钟')),
                  DropdownMenuItem(value: 10, child: Text('每 10 分钟')),
                  DropdownMenuItem(value: 60, child: Text('每小时')),
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
                    // 核心修改：通知全局主题状态变化，立即重绘 MaterialApp
                    StorageService.themeNotifier.value = val;
                  }
                },
              ),
            ),
          ]),

          // 3. 高级设置
          _buildSection('高级设置 (用于超级岛通知)', [
            ListTile(
              leading: const CircleAvatar(backgroundColor: Colors.deepPurpleAccent, child: Icon(Icons.smart_button, color: Colors.white, size: 20)),
              title: const Text('超级岛特性支持'),
              subtitle: Text(_islandStatus, style: TextStyle(color: Colors.grey[600], fontSize: 12)),
              trailing: ElevatedButton(
                style: ElevatedButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))),
                onPressed: _checkIslandSupport, child: const Text('检测'),
              ),
            ),
            const Divider(height: 1, indent: 56),
            ListTile(
              leading: const CircleAvatar(backgroundColor: Colors.blueAccent, child: Icon(Icons.adb, color: Colors.white, size: 20)),
              title: const Text('Shizuku 授权'),
              subtitle: Text(_shizukuStatus, style: TextStyle(color: Colors.grey[600], fontSize: 12)),
              trailing: ElevatedButton(
                style: ElevatedButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))),
                onPressed: _requestShizukuPermission, child: const Text('授权'),
              ),
            ),
          ]),

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