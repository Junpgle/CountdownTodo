import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:io';
import 'dart:math';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:flutter_downloader/flutter_downloader.dart';
import 'package:path_provider/path_provider.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../storage_service.dart';
import '../update_service.dart';
import 'login_screen.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({Key? key}) : super(key: key);

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  static const platform = MethodChannel('com.math_quiz.junpgle.com.math_quiz_app/notifications');

  String _shizukuStatus = "点击右侧按钮获取或检查权限";
  String _islandStatus = "点击检测设备是否支持"; // 新增状态变量
  bool _isCheckingUpdate = false;

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

  // 退出账号
  Future<void> _handleLogout() async {
    bool? confirm = await showDialog<bool>(
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
    );

    if (confirm == true) {
      await StorageService.clearLoginSession();
      if (mounted) {
        // 清除所有路由栈并跳转回登录页
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const LoginScreen()),
              (route) => false,
        );
      }
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('设置'),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          // 第一组：超级岛与高级权限
          const Padding(
            padding: EdgeInsets.only(bottom: 8.0),
            child: Text(
              '高级设置 (用于超级岛通知)',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.grey),
            ),
          ),
          // --- 新增：超级岛支持检测 ---
          Card(
            elevation: 2,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              leading: const CircleAvatar(
                backgroundColor: Colors.deepPurpleAccent,
                child: Icon(Icons.smart_button, color: Colors.white),
              ),
              title: const Text('超级岛特性支持', style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 4.0),
                child: Text(_islandStatus, style: TextStyle(color: Colors.grey[600], fontSize: 13)),
              ),
              trailing: ElevatedButton(
                style: ElevatedButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))),
                onPressed: _checkIslandSupport,
                child: const Text('检测'),
              ),
            ),
          ),
          const SizedBox(height: 12),
          // --- 现有的 Shizuku 检测 ---
          Card(
            elevation: 2,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              leading: const CircleAvatar(
                backgroundColor: Colors.blueAccent,
                child: Icon(Icons.adb, color: Colors.white),
              ),
              title: const Text('Shizuku 授权', style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 4.0),
                child: Text(_shizukuStatus, style: TextStyle(color: Colors.grey[600], fontSize: 13)),
              ),
              trailing: ElevatedButton(
                style: ElevatedButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))),
                onPressed: _requestShizukuPermission,
                child: const Text('授权'),
              ),
            ),
          ),

          const SizedBox(height: 24),

          // 第二组：常规与关于
          const Padding(
            padding: EdgeInsets.only(bottom: 8.0),
            child: Text(
              '系统与账户',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.grey),
            ),
          ),
          Card(
            elevation: 2,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Column(
              children: [
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
                  onTap: _handleLogout,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}