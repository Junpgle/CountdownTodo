import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import 'package:intl/intl.dart';
import 'dart:io';
import 'dart:math'; // 新增：用于随机数
import 'dart:convert'; // 新增：用于解析JSON
import 'package:http/http.dart' as http; // 新增：用于请求API
import 'package:flutter_downloader/flutter_downloader.dart';
import 'package:path_provider/path_provider.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:cached_network_image/cached_network_image.dart'; // 新增：缓存图片库
import '../models.dart';
import '../storage_service.dart';
import '../update_service.dart';
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

  // 壁纸状态
  String? _wallpaperUrl;

  // 待办折叠状态
  bool _isTodoExpanded = true;

  @override
  void initState() {
    super.initState();
    _loadAllData();
    _fetchRandomWallpaper(); // 启动时获取随机壁纸

    // 页面加载完成后自动检查更新 (静默模式)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkUpdatesAndNotices(isManual: false);
    });
  }

  // 当从二级界面返回时刷新数据
  void _refreshData() {
    _loadAllData();
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

        bool allDone = _todos.isNotEmpty && _todos.every((t) => t.isDone);
        if (allDone) {
          _isTodoExpanded = false;
        } else {
          _isTodoExpanded = true;
        }
      });
    }
  }

  // --- 壁纸逻辑 ---

  Future<void> _fetchRandomWallpaper() async {
    // GitHub API 地址，获取 wallpaper 目录下的文件列表
    const String repoApiUrl = "https://api.github.com/repos/Junpgle/math_quiz_app/contents/wallpaper";

    try {
      final response = await http.get(Uri.parse(repoApiUrl));
      if (response.statusCode == 200) {
        // 解析 JSON 列表
        List<dynamic> files = jsonDecode(response.body);

        // 筛选图片文件 (jpg, png, jpeg)
        List<String> imageUrls = files
            .where((file) {
          String name = file['name'].toString().toLowerCase();
          return name.endsWith('.jpg') || name.endsWith('.png') || name.endsWith('.jpeg');
        })
            .map((file) => file['download_url'].toString())
            .toList();

        if (imageUrls.isNotEmpty) {
          // 随机选择一张
          final random = Random();
          String selectedUrl = imageUrls[random.nextInt(imageUrls.length)];

          if (mounted) {
            setState(() {
              _wallpaperUrl = selectedUrl;
            });
          }
        }
      }
    } catch (e) {
      print("获取随机壁纸失败: $e");
      // 可以在这里设置一个本地兜底图，或者保持 null 使用默认背景
    }
  }

  // --- 更新检查与下载逻辑 ---

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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('需要通知权限才能显示下载进度')),
        );
      }
    }

    final dir = await getExternalStorageDirectory();

    if (dir != null) {
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }

      String fileName = url.split('/').last;
      if (fileName.contains('?')) {
        fileName = fileName.split('?').first;
      }
      if (fileName.isEmpty || !fileName.endsWith('.apk')) {
        fileName = 'update.apk';
      }

      final file = File('${dir.path}/$fileName');
      if (await file.exists()) {
        try {
          await file.delete();
        } catch (e) {
          print("Delete old file failed: $e");
        }
      }

      try {
        await FlutterDownloader.enqueue(
          url: url,
          savedDir: dir.path,
          fileName: fileName,
          showNotification: true,
          openFileFromNotification: true,
          saveInPublicStorage: false,
        );

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已开始后台下载，请查看通知栏')),
        );
      } catch (e) {
        print("Download error: $e");
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('下载启动失败，请检查权限或重试')),
        );
      }
    }
  }

  bool _shouldUpdate({
    required int localBuild,
    required String localVersion,
    required int remoteBuild,
    required String remoteVersion
  }) {
    if (remoteBuild > localBuild) return true;
    if (remoteBuild == localBuild) {
      return _compareSemVer(remoteVersion, localVersion) > 0;
    }
    return false;
  }

  int _compareSemVer(String v1, String v2) {
    try {
      List<int> v1Parts = v1.split('.').map(int.parse).toList();
      List<int> v2Parts = v2.split('.').map(int.parse).toList();
      int len = v1Parts.length < v2Parts.length ? v1Parts.length : v2Parts.length;

      for (int i = 0; i < len; i++) {
        if (v1Parts[i] > v2Parts[i]) return 1;
        if (v1Parts[i] < v2Parts[i]) return -1;
      }

      if (v1Parts.length > v2Parts.length) return 1;
      if (v1Parts.length < v2Parts.length) return -1;
    } catch (e) {
      return 0;
    }
    return 0;
  }

  Future<void> _checkUpdatesAndNotices({bool isManual = false}) async {
    if (isManual) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('正在检查更新...'), duration: Duration(seconds: 1)),
      );
    }

    AppManifest? manifest = await UpdateService.checkManifest();

    if (manifest == null) {
      if (isManual && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('检查失败，请检查网络连接')),
        );
      }
      return;
    }

    // 注意：不再从 manifest 获取壁纸，改用随机 API 逻辑
    // 但如果 API 获取失败，manifest 里的可以作为备选，这里暂不处理备选逻辑以保持随机性

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
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text("检查完成"),
            content: Text("当前版本 ($localVersionName) 已是最新。"),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("好"))
            ],
          ),
        );
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
                            Text(manifest.updateInfo.title,
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.blue.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            "版本: $localVersionName -> ${manifest.versionName}",
                            style: TextStyle(color: Colors.blue[800], fontSize: 12, fontWeight: FontWeight.bold),
                          ),
                        ),
                        const SizedBox(height: 10),
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
                                onPressed: () => _startBackgroundDownload(manifest.updateInfo.fullPackageUrl),
                              ),
                          ],
                        ),
                        const Divider(height: 30),
                      ],

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

  // --- 倒计时和待办逻辑 ---

  void _addCountdown() {
    TextEditingController titleCtrl = TextEditingController();
    DateTime selectedDate = DateTime.now().add(const Duration(days: 1));

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text("添加倒计时"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: titleCtrl, decoration: const InputDecoration(labelText: "事项名称")),
              const SizedBox(height: 10),
              ListTile(
                title: Text("目标日期: ${DateFormat('yyyy-MM-dd').format(selectedDate)}"),
                trailing: const Icon(Icons.calendar_today),
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    firstDate: DateTime.now(),
                    lastDate: DateTime(2100),
                    initialDate: selectedDate,
                  );
                  if (picked != null) setState(() => selectedDate = picked);
                },
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("取消")),
            FilledButton(
              onPressed: () {
                if (titleCtrl.text.isNotEmpty) {
                  setState(() {
                    _countdowns.add(CountdownItem(title: titleCtrl.text, targetDate: selectedDate));
                  });
                  StorageService.saveCountdowns(widget.username, _countdowns);
                  _loadAllData(); // 刷新界面
                  Navigator.pop(ctx);
                }
              },
              child: const Text("添加"),
            )
          ],
        ),
      ),
    );
  }

  void _deleteCountdown(int index) {
    setState(() {
      _countdowns.removeAt(index);
    });
    StorageService.saveCountdowns(widget.username, _countdowns);
  }

  void _addTodo() {
    TextEditingController titleCtrl = TextEditingController();
    RecurrenceType recurrence = RecurrenceType.none;
    int? customDays;
    DateTime? endDate;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text("添加待办"),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: titleCtrl, decoration: const InputDecoration(labelText: "待办内容")),
                const SizedBox(height: 10),
                DropdownButtonFormField<RecurrenceType>(
                  value: recurrence,
                  decoration: const InputDecoration(labelText: "重复设置"),
                  items: const [
                    DropdownMenuItem(value: RecurrenceType.none, child: Text("不重复")),
                    DropdownMenuItem(value: RecurrenceType.daily, child: Text("每天重复")),
                    DropdownMenuItem(value: RecurrenceType.customDays, child: Text("隔几天重复")),
                  ],
                  onChanged: (val) {
                    setDialogState(() => recurrence = val!);
                  },
                ),
                if (recurrence == RecurrenceType.customDays)
                  TextField(
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: "间隔天数"),
                    onChanged: (val) => customDays = int.tryParse(val),
                  ),
                if (recurrence != RecurrenceType.none)
                  ListTile(
                    title: Text(endDate == null ? "设置截止日期 (可选)" : "截止: ${DateFormat('yyyy-MM-dd').format(endDate!)}"),
                    trailing: const Icon(Icons.event_busy),
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        firstDate: DateTime.now(),
                        lastDate: DateTime(2100),
                        initialDate: DateTime.now().add(const Duration(days: 30)),
                      );
                      if (picked != null) setDialogState(() => endDate = picked);
                    },
                  )
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("取消")),
            FilledButton(
              onPressed: () {
                if (titleCtrl.text.isNotEmpty) {
                  final newTodo = TodoItem(
                    id: const Uuid().v4(),
                    title: titleCtrl.text,
                    recurrence: recurrence,
                    customIntervalDays: customDays,
                    recurrenceEndDate: endDate,
                    lastUpdated: DateTime.now(),
                  );
                  this.setState(() {
                    _todos.insert(0, newTodo);
                  });
                  StorageService.saveTodos(widget.username, _todos);
                  _loadAllData();
                  Navigator.pop(ctx);
                }
              },
              child: const Text("添加"),
            )
          ],
        ),
      ),
    );
  }

  void _toggleTodo(int index) {
    setState(() {
      _todos[index].isDone = !_todos[index].isDone;
      _todos[index].lastUpdated = DateTime.now();
      _todos.sort((a, b) {
        if (a.isDone == b.isDone) return 0;
        return a.isDone ? 1 : -1;
      });
    });
    StorageService.saveTodos(widget.username, _todos);
  }

  void _deleteTodo(String id) {
    setState(() {
      _todos.removeWhere((t) => t.id == id);
    });
    StorageService.saveTodos(widget.username, _todos);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _wallpaperUrl != null ? Colors.transparent : Theme.of(context).colorScheme.surface,
      // 使用 Stack 将壁纸放在最底层
      body: Stack(
        children: [
          // 1. 壁纸层 (使用 CachedNetworkImage)
          if (_wallpaperUrl != null)
            Positioned.fill(
              child: CachedNetworkImage(
                imageUrl: _wallpaperUrl!,
                fit: BoxFit.cover,
                // 渐显时间
                fadeInDuration: const Duration(milliseconds: 800),
                placeholder: (context, url) => Container(color: Theme.of(context).colorScheme.surface),
                errorWidget: (context, url, error) => Container(color: Theme.of(context).colorScheme.surface),
              ),
            ),

          // 2. 压暗遮罩层 (实现轻微压暗，防止按钮看不清)
          if (_wallpaperUrl != null)
            Positioned.fill(
              child: Container(
                color: Colors.black.withValues(alpha: 0.4), // 40% 不透明度的黑色遮罩
              ),
            ),

          // 3. 内容层
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
                    icon: Icon(Icons.system_update, color: _wallpaperUrl != null ? Colors.white : null),
                    tooltip: "检查更新",
                    onPressed: () => _checkUpdatesAndNotices(isManual: true),
                  ),
                  IconButton(
                    icon: Icon(Icons.logout, color: _wallpaperUrl != null ? Colors.white : null),
                    tooltip: "退出登录",
                    onPressed: () async {
                      await StorageService.clearLoginSession();
                      if (context.mounted) {
                        Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const LoginScreen()));
                      }
                    },
                  )
                ],
              ),

              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 1. 倒计时板块
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
                              return Dismissible(
                                key: ValueKey(item.title + index.toString()),
                                direction: DismissDirection.up,
                                onDismissed: (_) => _deleteCountdown(index),
                                child: Card(
                                  color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.9),
                                  margin: const EdgeInsets.only(right: 12),
                                  child: Container(
                                    width: 140,
                                    padding: const EdgeInsets.all(12),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis,
                                            style: TextStyle(color: Theme.of(context).colorScheme.onPrimaryContainer)),
                                        const Spacer(),
                                        Text("$diff天",
                                            style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold,
                                                color: Theme.of(context).colorScheme.onPrimaryContainer)),
                                        Text("目标日: ${DateFormat('MM-dd').format(item.targetDate)}",
                                            style: const TextStyle(fontSize: 10)),
                                      ],
                                    ),
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
                          Expanded(
                            child: _buildSectionHeader("今日待办", Icons.check_circle_outline, onAdd: _addTodo),
                          ),
                          IconButton(
                            icon: Icon(_isTodoExpanded ? Icons.expand_less : Icons.expand_more, color: _wallpaperUrl != null ? Colors.white70 : null),
                            onPressed: () => setState(() => _isTodoExpanded = !_isTodoExpanded),
                          )
                        ],
                      ),
                      if (_todos.isEmpty)
                        _buildEmptyState("今日无待办")
                      else if (!_isTodoExpanded)
                        Builder(
                            builder: (context) {
                              int pendingCount = _todos.where((t) => !t.isDone).length;
                              bool isAllDone = pendingCount == 0;
                              return Card(
                                elevation: 0,
                                color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.8),
                                child: ListTile(
                                  leading: Icon(
                                      isAllDone ? Icons.check_circle : Icons.pending_actions,
                                      color: isAllDone ? Colors.green : Colors.orange
                                  ),
                                  title: Text(isAllDone ? "所有待办均已完成" : "还有 $pendingCount 个待办未完成"),
                                  trailing: const Icon(Icons.expand_more),
                                  onTap: () => setState(() => _isTodoExpanded = true),
                                ),
                              );
                            }
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
                                color: todo.isDone
                                    ? Theme.of(context).disabledColor.withValues(alpha: 0.1)
                                    : Theme.of(context).colorScheme.surfaceContainer.withValues(alpha: 0.95),
                                child: ListTile(
                                  leading: Checkbox(
                                    value: todo.isDone,
                                    onChanged: (_) => _toggleTodo(idx),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                                  ),
                                  title: Text(
                                    todo.title,
                                    style: TextStyle(
                                      decoration: todo.isDone ? TextDecoration.lineThrough : null,
                                      color: todo.isDone ? Colors.grey : null,
                                    ),
                                  ),
                                  subtitle: todo.recurrence != RecurrenceType.none ?
                                  Row(
                                    children: [
                                      const Icon(Icons.repeat, size: 12),
                                      const SizedBox(width: 4),
                                      Text(todo.recurrence == RecurrenceType.daily ? "每天" : "每${todo.customIntervalDays}天", style: const TextStyle(fontSize: 12))
                                    ],
                                  ) : null,
                                ),
                              ),
                            );
                          }).toList(),
                        ),

                      const SizedBox(height: 24),

                      // 3. 数学测验板块
                      _buildSectionHeader("数学测验", Icons.functions),
                      Card(
                        elevation: 2,
                        clipBehavior: Clip.antiAlias,
                        color: Theme.of(context).cardColor.withValues(alpha: 0.95),
                        child: InkWell(
                          onTap: () async {
                            await Navigator.push(
                                context,
                                MaterialPageRoute(builder: (_) => MathMenuScreen(username: widget.username))
                            );
                            _refreshData();
                          },
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text("最佳战绩 (全对)", style: TextStyle(color: Theme.of(context).colorScheme.secondary)),
                                      Text(
                                        _mathStats['bestTime'] != null ? "${_mathStats['bestTime']}秒" : "--",
                                        style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                                      ),
                                      const SizedBox(height: 10),
                                      Text("总正确率", style: TextStyle(color: Theme.of(context).colorScheme.secondary)),
                                      LinearProgressIndicator(value: _mathStats['accuracy'] ?? 0.0, borderRadius: BorderRadius.circular(4)),
                                      const SizedBox(height: 4),
                                      Text("${((_mathStats['accuracy'] ?? 0.0) * 100).toStringAsFixed(1)}%", style: const TextStyle(fontWeight: FontWeight.bold)),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 20),
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: Theme.of(context).colorScheme.primary,
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(Icons.arrow_forward, color: Colors.white),
                                )
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
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addTodo,
        icon: const Icon(Icons.add_task),
        label: const Text("记待办"),
      ),
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
            IconButton(
              onPressed: onAdd,
              icon: Icon(Icons.add_circle_outline, color: iconColor),
              tooltip: "添加",
            )
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
      decoration: BoxDecoration(
        border: Border.all(color: borderColor),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(text, style: TextStyle(color: textColor)),
    );
  }
}