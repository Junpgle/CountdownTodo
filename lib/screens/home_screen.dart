import 'package:flutter/material.dart';
import 'dart:io'; // 新增
import 'package:flutter_downloader/flutter_downloader.dart'; // 新增
import 'package:path_provider/path_provider.dart'; // 新增
import 'quiz_screen.dart';
import 'other_screens.dart';
import 'login_screen.dart';
import 'settings_screen.dart';
import '../update_service.dart'; // 引入更新服务

class HomeScreen extends StatefulWidget {
  final String username;
  const HomeScreen({super.key, required this.username});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {

  @override
  void initState() {
    super.initState();
    // 页面加载完成后自动检查更新 (静默模式)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkUpdatesAndNotices(isManual: false);
    });
  }

  // 新增：后台下载方法
  Future<void> _startBackgroundDownload(String url) async {
    if (!Platform.isAndroid) {
      // 非Android平台回退到浏览器下载
      UpdateService.launchURL(url);
      return;
    }

    // 获取Android外部存储路径 (无需额外权限即可写入 app-specific 目录)
    // 路径通常为: /storage/emulated/0/Android/data/com.example.math_quiz_app/files
    final dir = await getExternalStorageDirectory();

    if (dir != null) {
      await FlutterDownloader.enqueue(
        url: url,
        savedDir: dir.path,
        showNotification: true, // 显示下载进度通知
        openFileFromNotification: true, // 点击通知打开文件(安装APK)
        saveInPublicStorage: false,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已开始后台下载，请查看通知栏')),
      );
    }
  }

  // 修改：增加 isManual 参数，区分自动检查和手动检查
  Future<void> _checkUpdatesAndNotices({bool isManual = false}) async {
    if (isManual) {
      // 手动检查时显示加载提示
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('正在检查更新...'), duration: Duration(seconds: 1)),
      );
    }

    // 1. 获取远程配置
    AppManifest? manifest = await UpdateService.checkManifest();

    if (manifest == null) {
      if (isManual && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('检查失败，请检查网络连接')),
        );
      }
      return;
    }

    // 2. 获取本地版本
    int localBuild = await UpdateService.getCurrentBuildNumber();

    // 3. 判断是否需要展示 (有更新 或者 有公告)
    bool hasUpdate = manifest.versionCode > localBuild;
    bool hasNotice = manifest.announcement.show;
    bool hasWallpaper = manifest.wallpaper.show;

    // 如果没有任何更新/公告
    if (!hasUpdate && !hasNotice && !hasWallpaper) {
      if (isManual && mounted) {
        // 手动检查且无更新时，明确告知用户
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text("检查完成"),
            content: Text("当前版本 (${manifest.versionName}) 已是最新。"),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("好"))
            ],
          ),
        );
      }
      return;
    }

    // 如果是自动检查，且没有更新也没有强制公告，可能就不打扰用户（取决于你的策略，这里保持只要有内容就弹窗）

    if (!mounted) return;

    // 4. 弹出对话框
    showDialog(
      context: context,
      barrierDismissible: !manifest.forceUpdate, // 强制更新时点击背景无法关闭
      builder: (context) {
        return AlertDialog(
          contentPadding: EdgeInsets.zero,
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // --- 壁纸区域 (如果有) ---
                if (hasWallpaper && manifest.wallpaper.imageUrl.isNotEmpty)
                  ClipRRect(
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                    child: Image.network(
                      manifest.wallpaper.imageUrl,
                      height: 200,
                      fit: BoxFit.cover,
                      errorBuilder: (ctx, err, stack) => const SizedBox(
                          height: 100,
                          child: Center(child: Icon(Icons.broken_image))
                      ),
                      loadingBuilder: (ctx, child, loadingProgress) {
                        if (loadingProgress == null) return child;
                        return const SizedBox(
                            height: 200,
                            child: Center(child: CircularProgressIndicator())
                        );
                      },
                    ),
                  ),

                Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // --- 版本更新信息 ---
                      if (hasUpdate) ...[
                        Row(
                          children: [
                            const Icon(Icons.new_releases, color: Colors.blue),
                            const SizedBox(width: 8),
                            Text(manifest.updateInfo.title,
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(manifest.updateInfo.description),
                        const SizedBox(height: 15),
                        Wrap(
                          spacing: 10,
                          children: [
                            if (manifest.updateInfo.fullPackageUrl.isNotEmpty)
                              ElevatedButton.icon(
                                icon: const Icon(Icons.download),
                                label: const Text("下载全量包 (APK)"),
                                style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, foregroundColor: Colors.white),
                                // 修改：调用后台下载
                                onPressed: () => _startBackgroundDownload(manifest.updateInfo.fullPackageUrl),
                              ),
                            if (manifest.updateInfo.patchPackageUrl.isNotEmpty)
                              OutlinedButton.icon(
                                icon: const Icon(Icons.compress),
                                label: const Text("下载增量包"),
                                // 修改：调用后台下载
                                onPressed: () {
                                  // 注意：这里仅演示下载，App目前无法直接安装增量包
                                  _startBackgroundDownload(manifest.updateInfo.patchPackageUrl);
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('增量包仅下载，需配合专门的合并工具使用')),
                                  );
                                },
                              ),
                          ],
                        ),
                        const Divider(height: 30),
                      ],

                      // --- 公告信息 ---
                      if (hasNotice) ...[
                        Row(
                          children: [
                            const Icon(Icons.campaign, color: Colors.orange),
                            const SizedBox(width: 8),
                            Text(manifest.announcement.title,
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                          ],
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
                onPressed: () => Navigator.pop(context),
                child: const Text("关闭"),
              )
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 180.0,
            floating: false,
            pinned: true,
            flexibleSpace: FlexibleSpaceBar(
              title: const Text(
                  '数学测验',
                  style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      shadows: [Shadow(color: Colors.black26, offset: Offset(0, 1), blurRadius: 2)]
                  )
              ),
              background: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF4facfe), Color(0xFF00f2fe)],
                  ),
                ),
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SizedBox(height: 30),
                      const CircleAvatar(
                        radius: 30,
                        backgroundColor: Colors.white24,
                        child: Icon(Icons.person, size: 36, color: Colors.white),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        "欢迎回来, ${widget.username}",
                        style: const TextStyle(fontSize: 18, color: Colors.white, fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.settings, color: Colors.white),
                tooltip: "设置",
                onPressed: () {
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen()));
                },
              ),
            ],
          ),
          SliverPadding(
            padding: const EdgeInsets.all(16.0),
            sliver: SliverGrid.count(
              crossAxisCount: 2,
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
              childAspectRatio: 1.1,
              children: [
                _MenuCard(
                  title: "开始答题",
                  subtitle: "挑战自我",
                  colorStart: const Color(0xFF4facfe),
                  colorEnd: const Color(0xFF00f2fe),
                  icon: Icons.play_arrow_rounded,
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => QuizScreen(username: widget.username))),
                ),

                _MenuCard(
                  title: "题目设置",
                  subtitle: "自定义难度",
                  colorStart: const Color(0xFF43e97b),
                  colorEnd: const Color(0xFF38f9d7),
                  icon: Icons.tune_rounded,
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen())),
                ),

                _MenuCard(
                  title: "排行榜",
                  subtitle: "查看排名",
                  colorStart: const Color(0xFFfa709a),
                  colorEnd: const Color(0xFFfee140),
                  icon: Icons.emoji_events_rounded,
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const LeaderboardScreen())),
                ),

                _MenuCard(
                  title: "历史记录",
                  subtitle: "过往成绩",
                  colorStart: const Color(0xFF667eea),
                  colorEnd: const Color(0xFF764ba2),
                  icon: Icons.history_edu_rounded,
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => HistoryScreen(username: widget.username))),
                ),

                _MenuCard(
                  title: "检查更新",
                  subtitle: "获取新版本",
                  colorStart: const Color(0xFF30cfd0),
                  colorEnd: const Color(0xFF330867),
                  icon: Icons.system_update_rounded,
                  onTap: () => _checkUpdatesAndNotices(isManual: true),
                ),

                _MenuCard(
                  title: "切换账号",
                  subtitle: "重新登录",
                  colorStart: const Color(0xFFff9a9e),
                  colorEnd: const Color(0xFFfecfef),
                  icon: Icons.logout_rounded,
                  onTap: () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const LoginScreen())),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MenuCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final Color colorStart;
  final Color colorEnd;
  final IconData icon;
  final VoidCallback onTap;

  const _MenuCard({
    required this.title,
    required this.subtitle,
    required this.colorStart,
    required this.colorEnd,
    required this.icon,
    required this.onTap
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [colorStart, colorEnd],
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, color: Colors.white, size: 28),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                        title,
                        style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.white
                        )
                    ),
                    const SizedBox(height: 4),
                    Text(
                        subtitle,
                        style: const TextStyle(
                            fontSize: 12,
                            color: Colors.white70
                        )
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}