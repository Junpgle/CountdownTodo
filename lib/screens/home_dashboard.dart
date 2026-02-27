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
import '../services/notification_service.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models.dart';
import '../storage_service.dart';
import '../update_service.dart';
import '../services/api_service.dart';
import '../services/screen_time_service.dart';
import '../widgets/home_sections.dart';
import 'screen_time_detail_screen.dart';
import 'math_menu_screen.dart';
import 'login_screen.dart';
import '../widgets/home_sections.dart';

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
  List<dynamic> _screenTimeStats = [];

  bool _hasUsagePermission = true;
  bool _isSyncing = false;
  String? _wallpaperUrl;

  bool _isTodoExpanded = true;
  bool _isPastTodosExpanded = false; // 控制以往待办是否展开

  // 屏幕时间的加载与更新状态
  bool _isLoadingScreenTime = true;
  DateTime? _lastScreenTimeSync;

  // 动态问候语
  String _currentGreeting = "";

  @override
  void initState() {
    super.initState();

    // 0. 初始化动态问候语
    _generateGreeting();

    // 1. 极速加载本地轻量级数据，立刻展现 UI
    _loadAllData();
    _fetchRandomWallpaper();

    // 2. 错峰执行耗时操作
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) _initNotifications();
      });
      Future.delayed(const Duration(milliseconds: 1000), () {
        if (mounted) _initScreenTime();
      });
      Future.delayed(const Duration(milliseconds: 1500), () {
        if (mounted) StorageService.syncAppMappings();
      });
      Future.delayed(const Duration(milliseconds: 2000), () {
        if (mounted) _checkUpdatesAndNotices(isManual: false);
      });
    });
  }

  // 动态时段打招呼
  String get _timeSalutation {
    final hour = DateTime.now().hour;
    if (hour >= 5 && hour < 12) return "上午好";
    if (hour >= 12 && hour < 14) return "中午好";
    if (hour >= 14 && hour < 18) return "下午好";
    return "晚上好";
  }

  // 根据当前时间随机生成问候语
  void _generateGreeting() {
    final hour = DateTime.now().hour;
    List<String> greetings;

    if (hour >= 5 && hour < 11) {
      greetings = ["今天也要元气超标！", "新的一天，把快乐置顶。", "迎着光，做自己的小太阳。", "起床充电，活力满格。", "今日宜：开心、努力、好运。"];
    } else if (hour >= 11 && hour < 14) {
      greetings = ["吃饱喝足，继续奔赴。", "中场能量补给，快乐不打烊。", "稳住状态，万事可期。", "生活不慌不忙，慢慢发光。", "好好吃饭，就是好好爱自己。"];
    } else if (hour >= 14 && hour < 18) {
      greetings = ["保持热爱，保持冲劲。", "状态在线，干劲拉满。", "不急不躁，温柔又有力量。", "把普通日子，过得热气腾腾。", "继续向前，好运正在路上。"];
    } else if (hour >= 18 && hour < 23) {
      greetings = ["晚风轻踩云朵，今天辛苦啦。", "卸下疲惫，拥抱温柔。", "今日圆满，万事顺心。", "把烦恼清空，把快乐装满。", "好好休息，明天依旧闪亮。"];
    } else if (hour >= 23 || hour < 3) {
      greetings = ["愿你心安，好梦常伴。", "安静沉淀，积蓄力量。", "不慌不忙，自在生长。", "温柔治愈，接纳所有情绪。", "今夜安睡，明日更好。"];
    } else {
      greetings = ["凌晨的星光，为你照亮前路。", "此刻努力，未来可期。", "安静时光，悄悄变优秀。", "不负自己，不负岁月。", "愿你眼里有光，心中有梦。"];
    }

    _currentGreeting = greetings[Random().nextInt(greetings.length)];
  }

  Future<void> _initNotifications() async {
    await NotificationService.init();
    if (await Permission.notification.isDenied) {
      await Permission.notification.request();
    }
  }

  Future<void> _initScreenTime() async {
    if (mounted) setState(() => _isLoadingScreenTime = true);

    bool permit = await ScreenTimeService.checkPermission();
    if (mounted) {
      setState(() {
        _hasUsagePermission = permit;
        if (!permit) _isLoadingScreenTime = false;
      });
    }
    if (permit) _loadCachedScreenTime();
  }

  Future<void> _loadCachedScreenTime() async {
    final prefs = await SharedPreferences.getInstance();
    int? userId = prefs.getInt('current_user_id');
    if (userId == null) {
      if (mounted) setState(() => _isLoadingScreenTime = false);
      return;
    }

    var stats = await ScreenTimeService.getScreenTimeData(userId);
    var lastSync = await StorageService.getLastScreenTimeSync();

    if (mounted) {
      setState(() {
        _screenTimeStats = stats;
        _lastScreenTimeSync = lastSync;
        _isLoadingScreenTime = false;
      });
    }
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

  Future<void> _handleManualSync() async {
    if (_isSyncing) return;
    setState(() {
      _isSyncing = true;
      _isLoadingScreenTime = true;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      int? userId = prefs.getInt('current_user_id');
      if (userId == null) throw Exception("未登录");

      bool hasChanges = await StorageService.syncData(widget.username);
      await ScreenTimeService.syncScreenTime(userId);
      await _loadCachedScreenTime();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('✅ 数据同步完成'), backgroundColor: Colors.green));
        if (hasChanges) _loadAllData();
      }
    } catch (e) {
      debugPrint("Sync Error: $e");
    } finally {
      if (mounted) {
        setState(() {
          _isSyncing = false;
          _isLoadingScreenTime = false;
        });
      }
    }
  }

  Future<void> _checkUpdatesAndNotices({bool isManual = false}) async {
    if (isManual) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('正在检查更新...'), duration: Duration(seconds: 1)));
    AppManifest? manifest = await UpdateService.checkManifest();
    if (manifest == null) {
      if (isManual && mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('检查失败，请检查网络')));
      return;
    }
    PackageInfo packageInfo = await PackageInfo.fromPlatform();
    bool hasUpdate = _shouldUpdate(localVersion: packageInfo.version, localBuild: int.tryParse(packageInfo.buildNumber) ?? 0, remoteVersion: manifest.versionName, remoteBuild: manifest.versionCode);
    bool hasNotice = manifest.announcement.show;
    if (!hasUpdate && !hasNotice) {
      if (isManual && mounted) showDialog(context: context, builder: (ctx) => AlertDialog(title: const Text("检查完成"), content: Text("当前版本 (${packageInfo.version}) 已是最新。"), actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("好"))]));
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
                        if (manifest.updateInfo.fullPackageUrl.isNotEmpty) ElevatedButton.icon(icon: const Icon(Icons.download), label: const Text("下载更新 (APK)"), onPressed: () => _startBackgroundDownload(manifest.updateInfo.fullPackageUrl)),
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
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已开始后台下载，请检查通知栏')));
    }
  }

  Future<void> _fetchRandomWallpaper() async {
    const String repoApiUrl = "https://api.github.com/repos/Junpgle/math_quiz_app/contents/wallpaper";
    try {
      final response = await http.get(Uri.parse(repoApiUrl));
      if (response.statusCode == 200) {
        List<dynamic> files = jsonDecode(response.body);
        List<String> urls = files.where((f) => f['name'].toString().toLowerCase().endsWith('.jpg') || f['name'].toString().toLowerCase().endsWith('.png')).map((f) => f['download_url'].toString()).toList();
        if (urls.isNotEmpty && mounted) setState(() => _wallpaperUrl = urls[Random().nextInt(urls.length)]);
      }
    } catch (e) { debugPrint("获取壁纸失败: $e"); }
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
                title: Text("目标日期: ${DateFormat('yyyy-MM-dd').format(selectedDate)}"), trailing: const Icon(Icons.calendar_today),
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
                  setState(() => _countdowns.add(CountdownItem(title: titleCtrl.text, targetDate: selectedDate, lastUpdated: DateTime.now())));
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

  void _deleteCountdown(int index) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("删除倒计时"),
        content: const Text("确定要删除这条倒计时吗？"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("取消")),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () {
              String titleToDelete = _countdowns[index].title;
              setState(() {
                _countdowns.removeAt(index);
              });
              StorageService.deleteCountdownGlobally(widget.username, titleToDelete);
              Navigator.pop(ctx);
            },
            child: const Text("删除"),
          ),
        ],
      ),
    );
  }

  void _addTodo() {
    TextEditingController titleCtrl = TextEditingController();
    DateTime createdAt = DateTime.now(); // 默认今日创建
    DateTime? dueDate; // 任务截止日期
    RecurrenceType recurrence = RecurrenceType.none;
    TextEditingController customDaysCtrl = TextEditingController();
    int? customDays;
    DateTime? recurrenceEndDate; // 重复截止日期

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
                // 1. 待办创建日期设置
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text("创建日期: ${DateFormat('yyyy-MM-dd').format(createdAt)}"),
                  trailing: const Icon(Icons.edit_calendar, size: 20),
                  onTap: () async {
                    final picked = await showDatePicker(
                        context: context,
                        firstDate: DateTime(2000),
                        lastDate: DateTime(2100),
                        initialDate: createdAt
                    );
                    if (picked != null) setDialogState(() => createdAt = picked);
                  },
                ),
                // 2. 待办截止日期选择
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(dueDate == null ? "设置截止日期 (可选)" : "截止日期: ${DateFormat('yyyy-MM-dd').format(dueDate!)}"),
                  trailing: const Icon(Icons.event, size: 20),
                  onTap: () async {
                    final picked = await showDatePicker(
                        context: context,
                        firstDate: DateTime(2000),
                        lastDate: DateTime(2100),
                        initialDate: dueDate ?? createdAt
                    );
                    if (picked != null) setDialogState(() => dueDate = picked);
                  },
                ),
                const Divider(),
                DropdownButtonFormField<RecurrenceType>(
                  value: recurrence, decoration: const InputDecoration(labelText: "循环设置 (可选)"),
                  items: const [
                    DropdownMenuItem(value: RecurrenceType.none, child: Text("不重复")),
                    DropdownMenuItem(value: RecurrenceType.daily, child: Text("每天重复")),
                    DropdownMenuItem(value: RecurrenceType.customDays, child: Text("隔几天重复")),
                  ],
                  onChanged: (val) => setDialogState(() => recurrence = val!),
                ),
                if (recurrence == RecurrenceType.customDays)
                  TextField(
                      controller: customDaysCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: "间隔天数"),
                      onChanged: (val) => customDays = int.tryParse(val)
                  ),
                if (recurrence != RecurrenceType.none)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(recurrenceEndDate == null ? "循环截止日期 (可选)" : "循环结束: ${DateFormat('yyyy-MM-dd').format(recurrenceEndDate!)}"),
                    trailing: const Icon(Icons.event_busy, size: 20),
                    onTap: () async {
                      final picked = await showDatePicker(
                          context: context,
                          firstDate: DateTime.now(),
                          lastDate: DateTime(2100),
                          initialDate: DateTime.now().add(const Duration(days: 30))
                      );
                      if (picked != null) setDialogState(() => recurrenceEndDate = picked);
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
                    recurrenceEndDate: recurrenceEndDate,
                    lastUpdated: DateTime.now(),
                    dueDate: dueDate,
                    createdAt: createdAt, // 保存用户选择的创建日期
                  );
                  setState(() => _todos.insert(0, newTodo));
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

  // 新增：编辑待办功能
  void _editTodo(TodoItem todo) {
    TextEditingController titleCtrl = TextEditingController(text: todo.title);
    DateTime createdAt = todo.createdAt;
    DateTime? dueDate = todo.dueDate;
    RecurrenceType recurrence = todo.recurrence;
    int? customDays = todo.customIntervalDays;
    TextEditingController customDaysCtrl = TextEditingController(text: customDays?.toString() ?? "");
    DateTime? recurrenceEndDate = todo.recurrenceEndDate;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text("编辑待办"),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: titleCtrl, decoration: const InputDecoration(labelText: "待办内容")),
                const SizedBox(height: 10),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text("创建日期: ${DateFormat('yyyy-MM-dd').format(createdAt)}"),
                  trailing: const Icon(Icons.edit_calendar, size: 20),
                  onTap: () async {
                    final picked = await showDatePicker(
                        context: context,
                        firstDate: DateTime(2000),
                        lastDate: DateTime(2100),
                        initialDate: createdAt
                    );
                    if (picked != null) setDialogState(() => createdAt = picked);
                  },
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(dueDate == null ? "设置截止日期 (可选)" : "截止日期: ${DateFormat('yyyy-MM-dd').format(dueDate!)}"),
                  trailing: const Icon(Icons.event, size: 20),
                  onTap: () async {
                    final picked = await showDatePicker(
                        context: context,
                        firstDate: DateTime(2000),
                        lastDate: DateTime(2100),
                        initialDate: dueDate ?? createdAt
                    );
                    if (picked != null) setDialogState(() => dueDate = picked);
                  },
                ),
                const Divider(),
                DropdownButtonFormField<RecurrenceType>(
                  value: recurrence, decoration: const InputDecoration(labelText: "循环设置 (可选)"),
                  items: const [
                    DropdownMenuItem(value: RecurrenceType.none, child: Text("不重复")),
                    DropdownMenuItem(value: RecurrenceType.daily, child: Text("每天重复")),
                    DropdownMenuItem(value: RecurrenceType.customDays, child: Text("隔几天重复")),
                  ],
                  onChanged: (val) => setDialogState(() => recurrence = val!),
                ),
                if (recurrence == RecurrenceType.customDays)
                  TextField(
                      controller: customDaysCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: "间隔天数"),
                      onChanged: (val) => customDays = int.tryParse(val)
                  ),
                if (recurrence != RecurrenceType.none)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(recurrenceEndDate == null ? "循环截止日期 (可选)" : "循环结束: ${DateFormat('yyyy-MM-dd').format(recurrenceEndDate!)}"),
                    trailing: const Icon(Icons.event_busy, size: 20),
                    onTap: () async {
                      final picked = await showDatePicker(
                          context: context,
                          firstDate: DateTime.now(),
                          lastDate: DateTime(2100),
                          initialDate: recurrenceEndDate ?? DateTime.now().add(const Duration(days: 30))
                      );
                      if (picked != null) setDialogState(() => recurrenceEndDate = picked);
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
                  setState(() {
                    todo.title = titleCtrl.text;
                    todo.createdAt = createdAt;
                    todo.dueDate = dueDate;
                    todo.recurrence = recurrence;
                    todo.customIntervalDays = customDays;
                    todo.recurrenceEndDate = recurrenceEndDate;
                    todo.lastUpdated = DateTime.now();
                  });
                  StorageService.saveTodos(widget.username, _todos);
                  _loadAllData();
                  Navigator.pop(ctx);
                }
              },
              child: const Text("保存"),
            )
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    bool isLight = _wallpaperUrl != null;

    return Scaffold(
      backgroundColor: isLight ? Colors.transparent : Theme.of(context).colorScheme.surface,
      body: Stack(
        children: [
          // 动态壁纸背景
          if (isLight)
            Positioned.fill(child: CachedNetworkImage(imageUrl: _wallpaperUrl!, fit: BoxFit.cover, fadeInDuration: const Duration(milliseconds: 800), placeholder: (context, url) => Container(color: Theme.of(context).colorScheme.surface))),
          if (isLight)
            Positioned.fill(child: Container(color: Colors.black.withOpacity(0.4))),

          Column(
            children: [
              _buildAppBar(isLight),

              // 核心布局：响应式区域
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final bool isTablet = constraints.maxWidth >= 800; // 设定分栏断点

                    // 构建各个板块
                    Widget countdownSection = Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SectionHeader(title: "重要日", icon: Icons.timer, onAdd: _addCountdown, isLight: isLight),
                        _buildCountdownList(isLight),
                      ],
                    );

                    Widget todoSection = Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(child: SectionHeader(title: "待办清单", icon: Icons.check_circle_outline, onAdd: _addTodo, isLight: isLight)),
                            IconButton(
                                icon: Icon(_isTodoExpanded ? Icons.expand_less : Icons.expand_more, color: isLight ? Colors.white70 : null),
                                onPressed: () => setState(() => _isTodoExpanded = !_isTodoExpanded)
                            )
                          ],
                        ),
                        _buildTodoList(isLight),
                      ],
                    );

                    Widget screenTimeSection = Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SectionHeader(title: "屏幕时间 (今日汇总)", icon: Icons.timer_outlined, isLight: isLight),
                        ScreenTimeCard(
                          stats: _screenTimeStats,
                          hasPermission: _hasUsagePermission,
                          isLoading: _isLoadingScreenTime,
                          lastSyncTime: _lastScreenTimeSync,
                          onOpenSettings: () async { await ScreenTimeService.openSettings(); _initScreenTime(); },
                          onViewDetail: () { Navigator.push(context, MaterialPageRoute(builder: (_) => ScreenTimeDetailScreen(todayStats: _screenTimeStats))); },
                        ),
                      ],
                    );

                    Widget mathSection = Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SectionHeader(title: "数学测验", icon: Icons.functions, isLight: isLight),
                        MathStatsCard(
                            stats: _mathStats,
                            onTap: () async {
                              await Navigator.push(context, MaterialPageRoute(builder: (_) => MathMenuScreen(username: widget.username)));
                              _loadAllData();
                            }
                        ),
                      ],
                    );

                    return SingleChildScrollView(
                      padding: EdgeInsets.symmetric(
                          horizontal: isTablet ? 32 : 16,
                          vertical: 16
                      ),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 1200),
                          child: isTablet
                              ? Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                flex: 5,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    countdownSection,
                                    const SizedBox(height: 32),
                                    todoSection,
                                    const SizedBox(height: 40),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 32),
                              Expanded(
                                flex: 6,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    screenTimeSection,
                                    const SizedBox(height: 32),
                                    mathSection,
                                    const SizedBox(height: 40),
                                  ],
                                ),
                              ),
                            ],
                          )
                              : Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              countdownSection,
                              const SizedBox(height: 24),
                              todoSection,
                              const SizedBox(height: 24),
                              screenTimeSection,
                              const SizedBox(height: 24),
                              mathSection,
                              const SizedBox(height: 40),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
          onPressed: _addTodo,
          icon: const Icon(Icons.add_task),
          label: const Text("记待办")
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(bool isLight) {
    return AppBar(
      backgroundColor: isLight ? Colors.transparent : null,
      elevation: 0,
      toolbarHeight: 100, // 增高AppBar以容纳三行文字
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // 第一行：用户名 + 早/中/晚好
          Text("$_timeSalutation, ${widget.username}",
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: isLight ? Colors.white : null)),
          const SizedBox(height: 4),
          // 第二行：日期
          Text(DateFormat('MM月dd日 EEEE', 'zh_CN').format(DateTime.now()),
              style: TextStyle(fontSize: 14, color: isLight ? Colors.white.withOpacity(0.9) : Colors.blueGrey)),
          const SizedBox(height: 2),
          // 第三行：动态问候语
          Text(_currentGreeting,
              style: TextStyle(fontSize: 12, color: isLight ? Colors.white.withOpacity(0.8) : Colors.grey)),
        ],
      ),
      actions: [
        IconButton(icon: _isSyncing ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : Icon(Icons.cloud_sync, color: isLight ? Colors.white : null), onPressed: _handleManualSync),
        IconButton(icon: Icon(Icons.system_update, color: isLight ? Colors.white : null), onPressed: () => _checkUpdatesAndNotices(isManual: true)),
        IconButton(icon: Icon(Icons.logout, color: isLight ? Colors.white : null), onPressed: () async { await StorageService.clearLoginSession(); if (mounted) Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const LoginScreen())); }),
      ],
    );
  }

  Widget _buildCountdownList(bool isLight) {
    if (_countdowns.isEmpty) return EmptyState(text: "暂无倒计时", isLight: isLight);
    return SizedBox(
      height: 110,
      child: ListView.builder(
        scrollDirection: Axis.horizontal, itemCount: _countdowns.length,
        itemBuilder: (context, index) {
          final item = _countdowns[index];
          final diff = item.targetDate.difference(DateTime.now()).inDays + 1;

          return Stack(
            children: [
              Card(
                color: Theme.of(context).colorScheme.primaryContainer.withOpacity(0.9), margin: const EdgeInsets.only(right: 12),
                child: Container(
                  width: 140, padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(right: 16.0), // 为删除按钮留出空间
                        child: Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: Theme.of(context).colorScheme.onPrimaryContainer)),
                      ),
                      const Spacer(),
                      Text("$diff天", style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.onPrimaryContainer)),
                      Text("目标日: ${DateFormat('MM-dd').format(item.targetDate)}", style: const TextStyle(fontSize: 10)),
                    ],
                  ),
                ),
              ),
              // 右上角删除按钮
              Positioned(
                right: 16,
                top: 4,
                child: InkWell(
                  onTap: () => _deleteCountdown(index),
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    child: Icon(
                        Icons.close,
                        size: 16,
                        color: Theme.of(context).colorScheme.onPrimaryContainer.withOpacity(0.5)
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  // 构建统一格式的单条待办卡片 (包含独立的进度条与编辑入口)
  Widget _buildTodoItemCard(TodoItem todo, bool isLight, {required bool isPast, required bool isFuture}) {
    // 【核心修复】强制卡片内部文字不跟随全局壁纸变白，而是与卡片自身颜色形成绝对对比
    Color cardColor = todo.isDone
        ? Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.3)
        : Theme.of(context).colorScheme.surface.withOpacity(isPast || isFuture ? 0.5 : 0.95);

    Color titleColor = todo.isDone
        ? Theme.of(context).colorScheme.onSurface.withOpacity(0.4)
        : (isPast || isFuture
        ? Theme.of(context).colorScheme.onSurface.withOpacity(0.6)
        : Theme.of(context).colorScheme.onSurface);

    Widget titleWidget = Text(
      todo.title,
      style: TextStyle(
        decoration: todo.isDone ? TextDecoration.lineThrough : null,
        color: titleColor,
        fontSize: isPast || isFuture ? 14 : 16,
        fontWeight: isPast || isFuture ? FontWeight.normal : FontWeight.w500, // 今日重点加粗
      ),
    );

    Widget? subtitleWidget;
    if (todo.dueDate != null) {
      String dateStr = DateFormat('MM-dd').format(todo.dueDate!);
      if (isFuture) {
        DateTime now = DateTime.now();
        DateTime today = DateTime(now.year, now.month, now.day);
        DateTime target = DateTime(todo.dueDate!.year, todo.dueDate!.month, todo.dueDate!.day);
        int days = target.difference(today).inDays;
        dateStr = "$dateStr ($days天后)";
      } else if (isPast) {
        dateStr = "已逾期: $dateStr";
      } else {
        dateStr = "今天截止";
      }

      Color subColor = todo.isDone
          ? Theme.of(context).colorScheme.onSurface.withOpacity(0.4)
          : (isPast ? Colors.redAccent.shade400 : Theme.of(context).colorScheme.onSurface.withOpacity(0.5));

      Widget dateText = Text(dateStr, style: TextStyle(fontSize: 12, color: subColor));

      // 核心计算：基于每个待办自身的进度条 (已过天数 / 总天数 = 1 - 剩余/总数)
      double progress = 0.0;
      bool showProgress = false;

      DateTime start = DateTime(todo.createdAt.year, todo.createdAt.month, todo.createdAt.day);
      DateTime end = DateTime(todo.dueDate!.year, todo.dueDate!.month, todo.dueDate!.day);
      DateTime now = DateTime.now();
      DateTime today = DateTime(now.year, now.month, now.day);

      int totalDays = end.difference(start).inDays;
      if (totalDays > 0) {
        int passedDays = today.difference(start).inDays;
        progress = (passedDays / totalDays).clamp(0.0, 1.0);
        showProgress = true;
      } else if (totalDays == 0) {
        // 如果创建日期和截止日期是同一天，那么今天过了没？
        progress = today.isBefore(start) ? 0.0 : 1.0;
        showProgress = true;
      }

      if (showProgress) {
        subtitleWidget = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 2),
            dateText,
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 5,
                      // 【核心修复】让进度条的底轨在任何时候都清晰可见
                      backgroundColor: Theme.of(context).colorScheme.onSurface.withOpacity(0.1),
                      valueColor: AlwaysStoppedAnimation<Color>(
                          todo.isDone ? Theme.of(context).colorScheme.onSurface.withOpacity(0.2) : Theme.of(context).colorScheme.primary
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text("${(progress * 100).toInt()}%", style: TextStyle(fontSize: 11, color: subColor, fontWeight: FontWeight.bold)),
              ],
            ),
          ],
        );
      } else {
        subtitleWidget = dateText;
      }
    }

    return Dismissible(
      key: Key(todo.id),
      background: Container(color: Colors.red, alignment: Alignment.centerRight, padding: const EdgeInsets.only(right: 20), child: const Icon(Icons.delete, color: Colors.white)),
      onDismissed: (_) {
        String titleToDelete = todo.title;
        setState(() => _todos.removeWhere((t) => t.id == todo.id));
        StorageService.deleteTodoGlobally(widget.username, titleToDelete);
      },
      child: Card(
        elevation: 0,
        color: cardColor,
        margin: const EdgeInsets.only(bottom: 6),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12) // 去掉多余边框让画面更清爽
        ),
        child: ListTile(
          dense: isPast || isFuture, // 压缩非核心待办的上下间距
          onTap: () => _editTodo(todo),
          leading: Checkbox(
              value: todo.isDone,
              onChanged: (val) {
                setState(() {
                  todo.isDone = val!;
                  todo.lastUpdated = DateTime.now();
                  _todos.sort((a, b) => a.isDone == b.isDone ? 0 : (a.isDone ? 1 : -1));
                });
                StorageService.saveTodos(widget.username, _todos);
              }
          ),
          title: titleWidget,
          subtitle: subtitleWidget,
        ),
      ),
    );
  }

  Widget _buildTodoList(bool isLight) {
    if (_todos.isEmpty) return EmptyState(text: "暂无待办", isLight: isLight);

    // 智能分组
    List<TodoItem> pastTodos = [];
    List<TodoItem> todayTodos = [];
    List<TodoItem> futureTodos = [];

    DateTime now = DateTime.now();
    DateTime today = DateTime(now.year, now.month, now.day);

    for (var t in _todos) {
      if (t.dueDate != null) {
        DateTime d = DateTime(t.dueDate!.year, t.dueDate!.month, t.dueDate!.day);
        if (d.isBefore(today)) {
          pastTodos.add(t);
        } else if (d.isAfter(today)) {
          futureTodos.add(t);
        } else {
          todayTodos.add(t);
        }
      } else {
        todayTodos.add(t);
      }
    }

    List<Widget> sections = [];

    // 1. 以往待办（默认折叠）
    if (pastTodos.isNotEmpty) {
      sections.add(
          InkWell(
            onTap: () => setState(() => _isPastTodosExpanded = !_isPastTodosExpanded),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 4.0),
              child: Row(
                children: [
                  Icon(_isPastTodosExpanded ? Icons.expand_more : Icons.chevron_right, size: 20, color: isLight ? Colors.white70 : Colors.grey),
                  const SizedBox(width: 8),
                  Text("以往待办 (${pastTodos.length})", style: TextStyle(color: isLight ? Colors.white70 : Colors.grey, fontWeight: FontWeight.bold, fontSize: 13)),
                ],
              ),
            ),
          )
      );
      if (_isPastTodosExpanded) {
        sections.addAll(pastTodos.map((t) => _buildTodoItemCard(t, isLight, isPast: true, isFuture: false)));
      }
      sections.add(const SizedBox(height: 8));
    }

    // 2. 今日待办 (受总开关控制)
    if (!_isTodoExpanded) {
      sections.add(
          ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(todayTodos.every((t) => t.isDone) ? "今日待办均已完成" : "还有 ${todayTodos.where((t) => !t.isDone).length} 个今日待办未完成", style: TextStyle(color: isLight ? Colors.white : null)),
              trailing: Icon(Icons.expand_more, color: isLight ? Colors.white70 : null),
              onTap: () => setState(() => _isTodoExpanded = true)
          )
      );
    } else {
      if (todayTodos.isNotEmpty) {
        sections.addAll(todayTodos.map((t) => _buildTodoItemCard(t, isLight, isPast: false, isFuture: false)));
      } else if (futureTodos.isEmpty) {
        sections.add(Padding(padding: const EdgeInsets.all(8.0), child: Text("今日无待办", style: TextStyle(color: isLight ? Colors.white70 : Colors.grey))));
      }
    }

    // 3. 未来待办 (置于今日待办下方，视觉减淡)
    if (_isTodoExpanded && futureTodos.isNotEmpty) {
      sections.add(
          Padding(
            padding: const EdgeInsets.only(top: 20.0, bottom: 8.0, left: 4.0),
            child: Row(
              children: [
                Icon(Icons.calendar_month, size: 16, color: isLight ? Colors.white60 : Colors.grey),
                const SizedBox(width: 6),
                Text("未来待办", style: TextStyle(color: isLight ? Colors.white70 : Colors.grey, fontWeight: FontWeight.bold, fontSize: 13)),
              ],
            ),
          )
      );
      sections.addAll(futureTodos.map((t) => _buildTodoItemCard(t, isLight, isPast: false, isFuture: true)));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: sections,
    );
  }
}