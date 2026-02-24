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
import '../screen_time_service.dart';
import '../widgets/home_sections.dart';
import 'screen_time_detail_screen.dart';
import 'math_menu_screen.dart';
import 'login_screen.dart';

class HomeDashboard extends StatefulWidget {
  final String username;
  const HomeDashboard({super.key, required this.username});

  @override
  State<HomeDashboard> createState() => _HomeDashboardState();
}

class _HomeDashboardState extends State<HomeDashboard> {
  // 数据状态
  List<CountdownItem> _countdowns = [];
  List<TodoItem> _todos = [];
  Map<String, dynamic> _mathStats = {};
  List<dynamic> _screenTimeStats = [];

  // 交互与显示状态
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
    _initScreenTime();

    // 页面加载完成后检查更新
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkUpdatesAndNotices(isManual: false);
    });
  }

  // --- 初始化与同步逻辑 ---

  Future<void> _initNotifications() async {
    await NotificationService.init();
    if (await Permission.notification.isDenied) {
      await Permission.notification.request();
    }
  }

  Future<void> _initScreenTime() async {
    bool permit = await ScreenTimeService.checkPermission();
    if (mounted) setState(() => _hasUsagePermission = permit);

    if (permit) {
      // 这里的逻辑变成了：读取本地（如果是第一次运行或满足间隔则后台自动同步）
      _loadCachedScreenTime();
    }
  }

  Future<void> _loadCachedScreenTime() async {
    final prefs = await SharedPreferences.getInstance();
    int? userId = prefs.getInt('current_user_id');
    if (userId == null) return;

    // 获取数据（内部包含自动同步逻辑）
    var stats = await ScreenTimeService.getScreenTimeData(userId);

    if (mounted) {
      setState(() {
        _screenTimeStats = stats;
      });
    }
  }

  Future<void> _refreshScreenTime() async {
    final prefs = await SharedPreferences.getInstance();
    int? userId = prefs.getInt('current_user_id');
    if (userId == null) return;
    await ScreenTimeService.syncScreenTime(userId);
    String today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    var stats = await ApiService.fetchScreenTime(userId, today);
    if (mounted) setState(() => _screenTimeStats = stats);
  }

  Future<void> _loadAllData() async {
    final countdowns = await StorageService.getCountdowns(widget.username);
    final todos = await StorageService.getTodos(widget.username);
    final stats = await StorageService.getMathStats(widget.username);
    if (mounted) {
      setState(() {
        _countdowns = countdowns;
        _todos = todos;
        _mathStats = stats;
        _isTodoExpanded = !_todos.every((t) => t.isDone);
      });
      NotificationService.updateTodoNotification(_todos);
    }
  }

  // 修改手动同步按钮
  Future<void> _handleManualSync() async {
    if (_isSyncing) return;
    setState(() => _isSyncing = true);

    try {
      final prefs = await SharedPreferences.getInstance();
      int? userId = prefs.getInt('current_user_id');
      if (userId == null) throw Exception("未登录");

      // 1. 同步常规数据
      bool hasChanges = await StorageService.syncData(widget.username);

      // 2. 强制同步屏幕时间（不走缓存判断）
      await ScreenTimeService.syncScreenTime(userId);
      await _loadCachedScreenTime(); // 重新加载

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✅ 数据同步完成'), backgroundColor: Colors.green),
        );
        if (hasChanges) _loadAllData();
      }
    } catch (e) {
      // 错误处理
    } finally {
      if (mounted) setState(() => _isSyncing = false);
    }
  }

  // --- 更新逻辑与 APK 下载 ---

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
    String localVersionName = packageInfo.version;
    int localBuild = int.tryParse(packageInfo.buildNumber) ?? 0;

    bool hasUpdate = _shouldUpdate(
      localVersion: localVersionName,
      localBuild: localBuild,
      remoteVersion: manifest.versionName,
      remoteBuild: manifest.versionCode,
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
                    child: CachedNetworkImage(imageUrl: manifest.wallpaper.imageUrl, height: 200, fit: BoxFit.cover),
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
                            label: const Text("下载更新 (APK)"),
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
    if (!Platform.isAndroid) {
      UpdateService.launchURL(url);
      return;
    }
    final dir = await getExternalStorageDirectory();
    if (dir != null) {
      await FlutterDownloader.enqueue(
        url: url,
        savedDir: dir.path,
        fileName: 'update.apk',
        showNotification: true,
        openFileFromNotification: true,
      );
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已开始后台下载，请检查通知栏')));
    }
  }

  // --- 壁纸逻辑 ---

  Future<void> _fetchRandomWallpaper() async {
    const String repoApiUrl = "https://api.github.com/repos/Junpgle/math_quiz_app/contents/wallpaper";
    try {
      final response = await http.get(Uri.parse(repoApiUrl));
      if (response.statusCode == 200) {
        List<dynamic> files = jsonDecode(response.body);
        List<String> urls = files
            .where((f) => f['name'].toString().toLowerCase().endsWith('.jpg') || f['name'].toString().toLowerCase().endsWith('.png'))
            .map((f) => f['download_url'].toString())
            .toList();
        if (urls.isNotEmpty && mounted) {
          setState(() => _wallpaperUrl = urls[Random().nextInt(urls.length)]);
        }
      }
    } catch (e) {
      debugPrint("获取壁纸失败: $e");
    }
  }

  // --- 构建方法 ---

  @override
  Widget build(BuildContext context) {
    bool isLight = _wallpaperUrl != null;

    return Scaffold(
      backgroundColor: isLight ? Colors.transparent : Theme.of(context).colorScheme.surface,
      body: Stack(
        children: [
          if (isLight)
            Positioned.fill(
              child: CachedNetworkImage(
                imageUrl: _wallpaperUrl!,
                fit: BoxFit.cover,
                fadeInDuration: const Duration(milliseconds: 800),
                placeholder: (context, url) => Container(color: Theme.of(context).colorScheme.surface),
              ),
            ),
          if (isLight) Positioned.fill(child: Container(color: Colors.black.withOpacity(0.4))),
          Column(
            children: [
              _buildAppBar(isLight),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SectionHeader(title: "重要日", icon: Icons.timer, onAdd: _addCountdown, isLight: isLight),
                      _buildCountdownList(isLight),
                      const SizedBox(height: 24),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(child: SectionHeader(title: "今日待办", icon: Icons.check_circle_outline, onAdd: _addTodo, isLight: isLight)),
                          IconButton(
                            icon: Icon(_isTodoExpanded ? Icons.expand_less : Icons.expand_more, color: isLight ? Colors.white70 : null),
                            onPressed: () => setState(() => _isTodoExpanded = !_isTodoExpanded),
                          )
                        ],
                      ),
                      _buildTodoList(isLight),
                      const SizedBox(height: 24),
                      SectionHeader(title: "屏幕时间 (今日汇总)", icon: Icons.timer_outlined, isLight: isLight),
                      ScreenTimeCard(
                        stats: _screenTimeStats,
                        hasPermission: _hasUsagePermission,
                        onOpenSettings: () async {
                          await ScreenTimeService.openSettings();
                          _initScreenTime();
                        },
                        onViewDetail: () {
                          // 点击卡片进入二级界面
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => ScreenTimeDetailScreen(stats: _screenTimeStats),
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 24),
                      SectionHeader(title: "数学测验", icon: Icons.functions, isLight: isLight),
                      MathStatsCard(
                        stats: _mathStats,
                        onTap: () async {
                          await Navigator.push(context, MaterialPageRoute(builder: (_) => MathMenuScreen(username: widget.username)));
                          _loadAllData();
                        },
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

  // --- UI 构建片段 ---

  PreferredSizeWidget _buildAppBar(bool isLight) {
    return AppBar(
      backgroundColor: isLight ? Colors.transparent : null,
      elevation: 0,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("早安, ${widget.username}", style: TextStyle(fontSize: 16, color: isLight ? Colors.white : null)),
          Text(DateFormat('MM月dd日 EEEE', 'zh_CN').format(DateTime.now()),
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: isLight ? Colors.white : null)),
        ],
      ),
      toolbarHeight: 80,
      actions: [
        IconButton(
          icon: _isSyncing
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : Icon(Icons.cloud_sync, color: isLight ? Colors.white : null),
          onPressed: _handleManualSync,
        ),
        IconButton(icon: Icon(Icons.system_update, color: isLight ? Colors.white : null), onPressed: () => _checkUpdatesAndNotices(isManual: true)),
        IconButton(
          icon: Icon(Icons.logout, color: isLight ? Colors.white : null),
          onPressed: () async {
            await StorageService.clearLoginSession();
            if (mounted) Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const LoginScreen()));
          },
        ),
      ],
    );
  }

  Widget _buildCountdownList(bool isLight) {
    if (_countdowns.isEmpty) return EmptyState(text: "暂无倒计时", isLight: isLight);
    return SizedBox(
      height: 110,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: _countdowns.length,
        itemBuilder: (context, index) {
          final item = _countdowns[index];
          final diff = item.targetDate.difference(DateTime.now()).inDays + 1;
          return Card(
            color: Theme.of(context).colorScheme.primaryContainer.withOpacity(0.9),
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
    );
  }

  Widget _buildTodoList(bool isLight) {
    if (_todos.isEmpty) return EmptyState(text: "今日无待办", isLight: isLight);
    if (!_isTodoExpanded) {
      return ListTile(
        title: Text(_todos.every((t) => t.isDone) ? "所有待办均已完成" : "还有 ${_todos.where((t) => !t.isDone).length} 个待办未完成"),
        trailing: const Icon(Icons.expand_more),
        onTap: () => setState(() => _isTodoExpanded = true),
      );
    }
    return Column(
      children: _todos.asMap().entries.map((entry) {
        int idx = entry.key;
        TodoItem todo = entry.value;
        return Dismissible(
          key: Key(todo.id),
          background: Container(color: Colors.red, alignment: Alignment.centerRight, padding: const EdgeInsets.only(right: 20), child: const Icon(Icons.delete, color: Colors.white)),
          onDismissed: (_) {
            setState(() => _todos.removeWhere((t) => t.id == todo.id));
            StorageService.saveTodos(widget.username, _todos);
          },
          child: Card(
            elevation: 0,
            color: todo.isDone ? Theme.of(context).disabledColor.withOpacity(0.1) : Theme.of(context).colorScheme.surfaceContainer.withOpacity(0.95),
            child: ListTile(
              leading: Checkbox(
                  value: todo.isDone,
                  onChanged: (val) {
                    setState(() {
                      _todos[idx].isDone = val!;
                      _todos[idx].lastUpdated = DateTime.now();
                      _todos.sort((a, b) => a.isDone == b.isDone ? 0 : (a.isDone ? 1 : -1));
                    });
                    StorageService.saveTodos(widget.username, _todos);
                  }),
              title: Text(todo.title, style: TextStyle(decoration: todo.isDone ? TextDecoration.lineThrough : null, color: todo.isDone ? Colors.grey : null)),
            ),
          ),
        );
      }).toList(),
    );
  }

  // --- 交互 Dialog ---

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
}