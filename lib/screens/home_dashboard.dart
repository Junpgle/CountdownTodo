import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import 'package:intl/intl.dart';
import 'dart:io';
import 'dart:math';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_downloader/flutter_downloader.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../notification_service.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models.dart';
import '../storage_service.dart';
import '../update_service.dart';
import '../api_service.dart';
import '../screen_time_service.dart'; // 引入屏幕时间服务
import 'math_menu_screen.dart';
import 'login_screen.dart';

class HomeDashboard extends StatefulWidget {
  final String username;
  const HomeDashboard({super.key, required this.username});

  @override
  State<HomeDashboard> createState() => _HomeDashboardState();
}

class _HomeDashboardState extends State<HomeDashboard> {
  List<CountdownItem> _countdowns = [];
  List<TodoItem> _todos = [];
  Map<String, dynamic> _mathStats = {};

  List<dynamic> _screenTimeStats = []; // 存储 Top Apps
  bool _hasUsagePermission = true;
  bool _isSyncing = false;
  String? _wallpaperUrl;
  bool _isTodoExpanded = true;

  @override
  void initState() {
    super.initState();
    _initNotifications();
    _loadAllData();
    _fetchRandomWallpaper();
    _initScreenTime(); // 初始化屏幕时间
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkUpdatesAndNotices(isManual: false);
    });
  }

  // 初始化权限检测并触发第一次数据加载
  Future<void> _initScreenTime() async {
    bool permit = await ScreenTimeService.checkPermission();
    if (mounted) setState(() => _hasUsagePermission = permit);
    if (permit) _refreshScreenTime();
  }

  Future<void> _initNotifications() async {
    await NotificationService.init();
    if (await Permission.notification.isDenied) {
      await Permission.notification.request();
    }
  }

  // 刷新屏幕时间数据
  Future<void> _refreshScreenTime() async {
    final prefs = await SharedPreferences.getInstance();
    int? userId = prefs.getInt('current_user_id');
    if (userId == null) return;

    await ScreenTimeService.syncScreenTime(userId);
    String today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    var stats = await ApiService.fetchScreenTime(userId, today);

    if (mounted) setState(() => _screenTimeStats = stats);
  }

  // 刷新本地界面数据
  Future<void> _loadAllData() async {
    final countdowns = await StorageService.getCountdowns(widget.username);
    final todos = await StorageService.getTodos(widget.username);
    final stats = await StorageService.getMathStats(widget.username);

    if (mounted) {
      setState(() {
        _countdowns = countdowns;
        _todos = todos;
        _mathStats = stats;

        bool allDone = _todos.isNotEmpty && _todos.every((t) => t.isDone);
        _isTodoExpanded = !allDone;
      });
      NotificationService.updateTodoNotification(_todos);
    }
  }

  // 手动同步逻辑
  Future<void> _handleManualSync() async {
    if (_isSyncing) return;
    setState(() => _isSyncing = true);
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('正在同步云端数据...'), duration: Duration(seconds: 2)));

    try {
      final prefs = await SharedPreferences.getInstance();
      int? userId = prefs.getInt('current_user_id');
      if (userId == null) throw Exception("未登录");

      // 1. 同步常规数据
      bool hasChanges = await StorageService.syncData(widget.username);
      // 2. 同步屏幕时间
      await _refreshScreenTime();

      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('✅ 同步完成'), backgroundColor: Colors.green));
        if (hasChanges) _loadAllData();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('同步失败: $e'), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _isSyncing = false);
    }
  }

  // --- UI 板块构建 ---
  Widget _buildScreenTimeCard() {
    if (!_hasUsagePermission) {
      return Card(
        color: Colors.amber.withValues(alpha: 0.1),
        margin: const EdgeInsets.only(bottom: 24),
        child: ListTile(
          leading: const Icon(Icons.lock_clock, color: Colors.orange),
          title: const Text("未开启屏幕时间统计"),
          subtitle: const Text("点击前往开启权限以同步手机使用时长"),
          onTap: () async {
            await ScreenTimeService.openSettings();
            _initScreenTime();
          },
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader("屏幕时间 (今日汇总)", Icons.timer_outlined),
        Card(
          elevation: 2,
          color: Theme.of(context).cardColor.withValues(alpha: 0.95),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: _screenTimeStats.isEmpty
                ? const Center(
              child: Padding(
                padding: EdgeInsets.all(20),
                child: Text(
                  "暂无数据，请确保已在 Android 设置中授权",
                  textAlign: TextAlign.center,
                ),
              ),
            )
                : Column(
              children: _screenTimeStats.take(3).map((app) {
                int min = app['duration'];
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      const Icon(Icons.app_registration, size: 18, color: Colors.blue),
                      const SizedBox(width: 12),
                      Expanded(child: Text(app['app_name'], style: const TextStyle(fontWeight: FontWeight.w500), overflow: TextOverflow.ellipsis)),
                      Text("${min ~/ 60}h ${min % 60}m", style: const TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _wallpaperUrl != null
          ? Colors.transparent
          : Theme.of(context).colorScheme.surface,
      body: Stack(
        children: [
          if (_wallpaperUrl != null)
            Positioned.fill(
              child: CachedNetworkImage(
                imageUrl: _wallpaperUrl!,
                fit: BoxFit.cover,
                fadeInDuration: const Duration(milliseconds: 800),
                placeholder: (context, url) => Container(color: Theme.of(context).colorScheme.surface),
                errorWidget: (context, url, error) => Container(color: Theme.of(context).colorScheme.surface),
              ),
            ),
          if (_wallpaperUrl != null)
            Positioned.fill(
              child: Container(color: Colors.black.withValues(alpha: 0.4)),
            ),
          Column(
            children: [
              AppBar(
                backgroundColor: _wallpaperUrl != null ? Colors.transparent : null,
                elevation: 0,
                title: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("早安, ${widget.username}",
                        style: TextStyle(fontSize: 16, color: _wallpaperUrl != null ? Colors.white : null)),
                    Text(DateFormat('MM月dd日 EEEE', 'zh_CN').format(DateTime.now()),
                        style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: _wallpaperUrl != null ? Colors.white : null)),
                  ],
                ),
                toolbarHeight: 80,
                actions: [
                  IconButton(
                    icon: _isSyncing
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : Icon(Icons.cloud_sync, color: _wallpaperUrl != null ? Colors.white : null),
                    tooltip: "云端同步",
                    onPressed: _handleManualSync,
                  ),
                  IconButton(
                    icon: Icon(Icons.system_update, color: _wallpaperUrl != null ? Colors.white : null),
                    tooltip: "检查更新",
                    onPressed: () => _checkUpdatesAndNotices(isManual: true),
                  ),
                  IconButton(
                    icon: Icon(Icons.logout, color: _wallpaperUrl != null ? Colors.white : null),
                    tooltip: "退出登录",
                    onPressed: () async {
                      await StorageService.clearLoginSession();
                      if (context.mounted) Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const LoginScreen()));
                    },
                  ),
                ],
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 1. 重要日板块
                      _buildSectionHeader("重要日", Icons.timer, onAdd: _addCountdown),
                      if (_countdowns.isEmpty)
                        _buildEmptyState("暂无倒计时")
                      else
                        SizedBox(
                          height: 110,
                          child: ListView.builder(
                            scrollDirection: Axis.horizontal,
                            itemCount: _countdowns.length,
                            itemBuilder: (context, index) {
                              final item = _countdowns[index];
                              final diff = item.targetDate.difference(DateTime.now()).inDays + 1;
                              return Card(
                                color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.9),
                                margin: const EdgeInsets.only(right: 12),
                                child: Container(
                                  width: 140,
                                  padding: const EdgeInsets.all(12),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: Theme.of(context).colorScheme.onPrimaryContainer)),
                                      const Spacer(),
                                      Text("$diff天", style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.onPrimaryContainer)),
                                      Text("目标日: ${DateFormat('MM-dd').format(item.targetDate)}", style: const TextStyle(fontSize: 10)),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      const SizedBox(height: 24),

                      // 2. 今日待办板块
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(child: _buildSectionHeader("今日待办", Icons.check_circle_outline, onAdd: _addTodo)),
                          IconButton(
                            icon: Icon(_isTodoExpanded ? Icons.expand_less : Icons.expand_more, color: _wallpaperUrl != null ? Colors.white70 : null),
                            onPressed: () => setState(() => _isTodoExpanded = !_isTodoExpanded),
                          )
                        ],
                      ),
                      if (_todos.isEmpty)
                        _buildEmptyState("今日无待办")
                      else if (!_isTodoExpanded)
                        ListTile(
                          title: Text(_todos.every((t) => t.isDone) ? "所有待办均已完成" : "还有 ${_todos.where((t) => !t.isDone).length} 个待办未完成"),
                          trailing: const Icon(Icons.expand_more),
                          onTap: () => setState(() => _isTodoExpanded = true),
                        )
                      else
                        Column(
                          children: _todos.asMap().entries.map((entry) {
                            int idx = entry.key;
                            TodoItem todo = entry.value;
                            return Dismissible(
                              key: Key(todo.id),
                              background: Container(color: Colors.red, alignment: Alignment.centerRight, padding: const EdgeInsets.only(right: 20), child: const Icon(Icons.delete, color: Colors.white)),
                              onDismissed: (_) => _deleteTodo(todo.id),
                              child: Card(
                                elevation: 0,
                                color: todo.isDone ? Theme.of(context).disabledColor.withValues(alpha: 0.1) : Theme.of(context).colorScheme.surfaceContainer.withValues(alpha: 0.95),
                                child: ListTile(
                                  leading: Checkbox(value: todo.isDone, onChanged: (_) => _toggleTodo(idx)),
                                  title: Text(todo.title, style: TextStyle(decoration: todo.isDone ? TextDecoration.lineThrough : null, color: todo.isDone ? Colors.grey : null)),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      const SizedBox(height: 24),

                      // 3. 屏幕时间板块
                      _buildScreenTimeCard(),

                      // 4. 数学测验板块
                      _buildSectionHeader("数学测验", Icons.functions),
                      Card(
                        elevation: 2,
                        clipBehavior: Clip.antiAlias,
                        color: Theme.of(context).cardColor.withValues(alpha: 0.95),
                        child: InkWell(
                          onTap: () async {
                            await Navigator.push(context, MaterialPageRoute(builder: (_) => MathMenuScreen(username: widget.username)));
                            _loadAllData();
                          },
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon((_mathStats['todayCount'] ?? 0) > 0 ? Icons.check_circle : Icons.error_outline, color: (_mathStats['todayCount'] ?? 0) > 0 ? Colors.green : Colors.orangeAccent, size: 30),
                                    const SizedBox(width: 12),
                                    Expanded(child: Text((_mathStats['todayCount'] ?? 0) > 0 ? "今日已完成 ${_mathStats['todayCount']} 次测验" : "今日还未完成测验", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: (_mathStats['todayCount'] ?? 0) > 0 ? Colors.green : Colors.orangeAccent))),
                                    const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey),
                                  ],
                                ),
                                const SizedBox(height: 20),
                                const Divider(),
                                const SizedBox(height: 10),
                                Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text("最佳战绩 (全对)", style: TextStyle(color: Theme.of(context).colorScheme.secondary, fontSize: 12)),
                                          const SizedBox(height: 4),
                                          Text(_mathStats['bestTime'] != null ? "${_mathStats['bestTime']}秒" : "--", style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                                        ],
                                      ),
                                    ),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text("总正确率", style: TextStyle(color: Theme.of(context).colorScheme.secondary, fontSize: 12)),
                                          const SizedBox(height: 4),
                                          Text("${((_mathStats['accuracy'] ?? 0.0) * 100).toStringAsFixed(1)}%", style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                                          const SizedBox(height: 4),
                                          LinearProgressIndicator(value: _mathStats['accuracy'] ?? 0.0, borderRadius: BorderRadius.circular(4)),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 40),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(onPressed: _addTodo, icon: const Icon(Icons.add_task), label: const Text("记待办")),
    );
  }

  // --- 逻辑与辅助方法 ---

  Future<void> _fetchRandomWallpaper() async {
    const String repoApiUrl = "https://api.github.com/repos/Junpgle/math_quiz_app/contents/wallpaper";
    try {
      final response = await http.get(Uri.parse(repoApiUrl));
      if (response.statusCode == 200) {
        List<dynamic> files = jsonDecode(response.body);
        List<String> imageUrls = files
            .where((file) {
          String name = file['name'].toString().toLowerCase();
          return name.endsWith('.jpg') || name.endsWith('.png') || name.endsWith('.jpeg');
        })
            .map((file) => file['download_url'].toString())
            .toList();

        if (imageUrls.isNotEmpty && mounted) {
          setState(() => _wallpaperUrl = imageUrls[Random().nextInt(imageUrls.length)]);
        }
      }
    } catch (e) {
      debugPrint("获取壁纸失败: $e");
    }
  }

  Future<void> _startBackgroundDownload(String url) async {
    if (!Platform.isAndroid) {
      UpdateService.launchURL(url);
      return;
    }
    var status = await Permission.notification.status;
    if (!status.isGranted) {
      status = await Permission.notification.request();
      if (!status.isGranted) {
        if (!mounted) return;
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('需要通知权限才能显示进度')));
      }
    }
    final dir = await getExternalStorageDirectory();
    if (dir != null) {
      if (!await dir.exists()) await dir.create(recursive: true);
      String fileName = 'update.apk';
      try {
        await FlutterDownloader.enqueue(
          url: url,
          savedDir: dir.path,
          fileName: fileName,
          showNotification: true,
          openFileFromNotification: true,
          saveInPublicStorage: false,
        );
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已开始后台下载')));
      } catch (e) {
        debugPrint("Download error: $e");
      }
    }
  }

  void _addCountdown() {
    TextEditingController titleCtrl = TextEditingController();
    DateTime selectedDate = DateTime.now().add(const Duration(days: 1));
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text("添加倒计时"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: titleCtrl, decoration: const InputDecoration(labelText: "事项名称")),
              ListTile(
                title: Text("目标日期: ${DateFormat('yyyy-MM-dd').format(selectedDate)}"),
                trailing: const Icon(Icons.calendar_today),
                onTap: () async {
                  final picked = await showDatePicker(context: context, firstDate: DateTime.now(), lastDate: DateTime(2100), initialDate: selectedDate);
                  if (picked != null) setDialogState(() => selectedDate = picked);
                },
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("取消")),
            FilledButton(
              onPressed: () {
                if (titleCtrl.text.isNotEmpty) {
                  setState(() => _countdowns.add(CountdownItem(title: titleCtrl.text, targetDate: selectedDate)));
                  StorageService.saveCountdowns(widget.username, _countdowns);
                  _loadAllData();
                  Navigator.pop(ctx);
                }
              },
              child: const Text("添加"),
            ),
          ],
        ),
      ),
    );
  }

  void _addTodo() {
    TextEditingController titleCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("添加待办"),
        content: TextField(controller: titleCtrl, decoration: const InputDecoration(labelText: "待办内容")),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("取消")),
          FilledButton(
            onPressed: () {
              if (titleCtrl.text.isNotEmpty) {
                final newTodo = TodoItem(id: const Uuid().v4(), title: titleCtrl.text, lastUpdated: DateTime.now());
                setState(() => _todos.insert(0, newTodo));
                StorageService.saveTodos(widget.username, _todos);
                _loadAllData();
                Navigator.pop(ctx);
              }
            },
            child: const Text("添加"),
          ),
        ],
      ),
    );
  }

  void _toggleTodo(int index) {
    setState(() {
      _todos[index].isDone = !_todos[index].isDone;
      _todos[index].lastUpdated = DateTime.now();
      _todos.sort((a, b) => a.isDone == b.isDone ? 0 : (a.isDone ? 1 : -1));
    });
    StorageService.saveTodos(widget.username, _todos);
    NotificationService.updateTodoNotification(_todos);
  }

  void _deleteTodo(String id) {
    setState(() => _todos.removeWhere((t) => t.id == id));
    StorageService.saveTodos(widget.username, _todos);
    NotificationService.updateTodoNotification(_todos);
  }

  bool _shouldUpdate({required int localBuild, required String localVersion, required int remoteBuild, required String remoteVersion}) {
    try {
      List<int> v1Parts = remoteVersion.split('.').map(int.parse).toList();
      List<int> v2Parts = localVersion.split('.').map(int.parse).toList();
      int len = v1Parts.length < v2Parts.length ? v1Parts.length : v2Parts.length;
      for (int i = 0; i < len; i++) {
        if (v1Parts[i] > v2Parts[i]) return true;
        if (v1Parts[i] < v2Parts[i]) return false;
      }
      if (v1Parts.length > v2Parts.length) return true;
      return remoteBuild > localBuild;
    } catch (e) {
      return false;
    }
  }

  Future<void> _checkUpdatesAndNotices({bool isManual = false}) async {
    if (isManual) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('正在检查更新...'), duration: Duration(seconds: 1)));
    }
    AppManifest? manifest = await UpdateService.checkManifest();
    if (manifest == null) {
      if (isManual && mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('检查失败，请检查网络')));
      return;
    }

    PackageInfo packageInfo = await PackageInfo.fromPlatform();
    int localBuild = int.tryParse(packageInfo.buildNumber) ?? 0;
    String localVersionName = packageInfo.version;

    bool hasUpdate = _shouldUpdate(
      localBuild: localBuild,
      localVersion: localVersionName,
      remoteBuild: manifest.versionCode,
      remoteVersion: manifest.versionName,
    );
    bool hasNotice = manifest.announcement.show;

    if (!hasUpdate && !hasNotice) {
      if (isManual && mounted) {
        showDialog(context: context, builder: (ctx) => AlertDialog(title: const Text("检查完成"), content: Text("当前版本 ($localVersionName) 已是最新。"), actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("好"))]));
      }
      return;
    }

    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: !manifest.forceUpdate,
      builder: (context) {
        return AlertDialog(
          contentPadding: EdgeInsets.zero,
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (manifest.wallpaper.show && manifest.wallpaper.imageUrl.isNotEmpty)
                  ClipRRect(
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                    child: Image.network(
                      manifest.wallpaper.imageUrl,
                      height: 200,
                      fit: BoxFit.cover,
                      errorBuilder: (ctx, err, stack) => const SizedBox(height: 100, child: Center(child: Icon(Icons.broken_image))),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (hasUpdate) ...[
                        Row(children: [const Icon(Icons.new_releases, color: Colors.blue), const SizedBox(width: 8), Text(manifest.updateInfo.title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18))]),
                        const SizedBox(height: 6),
                        Text("当前: $localVersionName  →  最新: ${manifest.versionName}", style: const TextStyle(fontSize: 12, color: Colors.blue, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 10),
                        Text(manifest.updateInfo.description),
                        const SizedBox(height: 15),
                        if (manifest.updateInfo.fullPackageUrl.isNotEmpty)
                          ElevatedButton.icon(
                            icon: const Icon(Icons.download),
                            label: const Text("下载全量包 (APK)"),
                            onPressed: () => _startBackgroundDownload(manifest.updateInfo.fullPackageUrl),
                          ),
                        const Divider(height: 30),
                      ],
                      if (hasNotice) ...[
                        Row(children: [const Icon(Icons.campaign, color: Colors.orange), const SizedBox(width: 8), Text(manifest.announcement.title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18))]),
                        const SizedBox(height: 8),
                        Text(manifest.announcement.content),
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

  Widget _buildSectionHeader(String title, IconData icon, {VoidCallback? onAdd}) {
    Color? textColor = _wallpaperUrl != null ? Colors.white : null;
    Color iconColor = _wallpaperUrl != null ? Colors.white70 : Theme.of(context).colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, size: 20, color: iconColor),
          const SizedBox(width: 8),
          Text(title, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold, color: textColor)),
          if (onAdd != null) ...[
            const Spacer(),
            IconButton(onPressed: onAdd, icon: Icon(Icons.add_circle_outline, color: iconColor), tooltip: "添加"),
          ]
        ],
      ),
    );
  }

  Widget _buildEmptyState(String text) {
    Color borderColor = _wallpaperUrl != null ? Colors.white30 : Colors.grey.withValues(alpha: 0.3);
    Color textColor = _wallpaperUrl != null ? Colors.white70 : Colors.grey;
    return Container(
      padding: const EdgeInsets.all(20),
      alignment: Alignment.center,
      decoration: BoxDecoration(border: Border.all(color: borderColor), borderRadius: BorderRadius.circular(12)),
      child: Text(text, style: TextStyle(color: textColor)),
    );
  }
}