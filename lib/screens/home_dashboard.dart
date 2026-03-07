import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';
import 'package:intl/intl.dart';
import 'dart:math';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'dart:async';

// 引入服务和模型
import '../models.dart';
import '../storage_service.dart';
import '../update_service.dart';
import '../services/notification_service.dart';
import '../services/widget_service.dart';
import '../services/screen_time_service.dart';
import '../services/course_service.dart';
import '../services/external_share_handler.dart';

// 引入其他页面
import 'screen_time_detail_screen.dart';
import 'math_menu_screen.dart';
import 'home_settings_screen.dart';
import 'course_screens.dart';
import 'historical_countdowns_screen.dart';
import 'historical_todos_screen.dart';
import 'upgrade_guide_screen.dart';

// 引入拆分后的组件
import '../widgets/home_sections.dart';
import '../widgets/home_app_bar.dart';
import '../widgets/countdown_section_widget.dart';
import '../widgets/course_section_widget.dart';
import '../widgets/todo_section_widget.dart';
import 'pomodoro_screen.dart';

class HomeDashboard extends StatefulWidget {
  final String username;
  const HomeDashboard({super.key, required this.username});

  @override
  State<HomeDashboard> createState() => _HomeDashboardState();
}

class _HomeDashboardState extends State<HomeDashboard> with WidgetsBindingObserver {
  // === 状态变量 ===
  List<CountdownItem> _countdowns = [];
  List<TodoItem> _todos = [];
  Map<String, dynamic> _mathStats = {};
  List<dynamic> _screenTimeStats = [];
  Map<String, dynamic> _dashboardCourseData = {'title': '课程提醒', 'courses': <CourseItem>[]};

  String _noCourseBehavior = 'keep';
  bool _hasUsagePermission = true;
  bool _isSyncing = false;
  String? _wallpaperUrl;
  bool _isLoadingScreenTime = true;
  DateTime? _lastScreenTimeSync;
  String _currentGreeting = "";
  bool _semesterEnabled = false;
  DateTime? _semesterStart;
  DateTime? _semesterEnd;

  List<String> _leftSections = ['courses', 'todos', 'math'];
  List<String> _rightSections = ['countdowns', 'screenTime'];

  Map<String, bool> _sectionVisibility = {
    'courses': true, 'countdowns': true, 'todos': true, 'screenTime': true, 'math': true,
  };
  Timer? _courseTimer;
  final GlobalKey<TodoSectionWidgetState> _todoSectionKey = GlobalKey();

  // === 初始化与生命周期 ===
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadSectionPreferences();
    _loadSemesterSettings();
    _generateGreeting();
    _loadAllData();
    _fetchRandomWallpaper();
    WidgetService.init();

    const platform = MethodChannel('com.math_quiz.junpgle.com.math_quiz_app/notifications');
    platform.setMethodCallHandler((call) async {
      if (call.method == "markCurrentTodoDone") _markCurrentTodoDone();
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(milliseconds: 500), () { if (mounted) _initNotifications(); });
      Future.delayed(const Duration(milliseconds: 1000), () { if (mounted) _initScreenTime(); });
      Future.delayed(const Duration(milliseconds: 1500), () { if (mounted) StorageService.syncAppMappings(); });

      ExternalShareHandler.init(context, () { _loadAllData(); });
      _checkAutoSync();
      _checkUpdatesSilently();

      _courseTimer = Timer.periodic(const Duration(minutes: 1), (timer) { _checkUpcomingEvents(); });
    });
  }

  @override
  void dispose() {
    ExternalShareHandler.dispose();
    _courseTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // === 业务与辅助逻辑 ===
  Future<void> _checkUpcomingEvents() async {
    DateTime now = DateTime.now();

    final dashboardData = await CourseService.getDashboardCourses();
    List<CourseItem> courses = (dashboardData['courses'] as List?)?.cast<CourseItem>() ?? [];

    bool hasUpcomingCourse = false;
    for (var course in courses) {
      try {
        DateTime courseTime = DateFormat('yyyy-MM-dd HH:mm').parse('${course.date} ${course.formattedStartTime}');
        int diffMinutes = courseTime.difference(now).inMinutes;

        if (diffMinutes >= 0 && diffMinutes <= 20) {
          NotificationService.showCourseLiveActivity(
            courseName: course.courseName,
            room: course.roomName,
            timeStr: '${course.formattedStartTime} - ${course.formattedEndTime}',
            teacher: course.teacherName,
          );
          hasUpcomingCourse = true;
          break;
        }
      } catch (e) {
        debugPrint("检查课程通知失败: $e");
      }
    }

    if (hasUpcomingCourse) return;

    List<TodoItem> upcomingTodos = _todos.where((t) {
      if (t.isDone) return false;
      // 🚀 修正：优先使用 createdDate，兼容旧数据 fallback 到 createdAt
      bool isAllDay = t.dueDate != null && DateTime.fromMillisecondsSinceEpoch(t.createdDate ?? t.createdAt, isUtc: true).toLocal().hour == 0 && DateTime.fromMillisecondsSinceEpoch(t.createdDate ?? t.createdAt, isUtc: true).toLocal().minute == 0 && t.dueDate!.hour == 23 && t.dueDate!.minute == 59;
      if (isAllDay) return false;

      // 🚀 修正：优先使用 createdDate，兼容旧数据 fallback 到 createdAt
      DateTime created = DateTime.fromMillisecondsSinceEpoch(t.createdDate ?? t.createdAt, isUtc: true).toLocal();
      DateTime startTime = DateTime(now.year, now.month, now.day, created.hour, created.minute);
      int diffMinutes = startTime.difference(now).inMinutes;
      return diffMinutes >= 0 && diffMinutes <= 20;
    }).toList();

    if (upcomingTodos.isNotEmpty) {
      upcomingTodos.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      NotificationService.showUpcomingTodoNotification(upcomingTodos.first);
      return;
    }

    NotificationService.updateTodoNotification(_todos);
  }

  Future<void> _checkUpdatesSilently() async {
    if (!mounted) return;
    await UpdateService.checkUpdateAndPrompt(context, isManual: false);
  }

  Future<void> _loadSemesterSettings() async {
    bool enabled = await StorageService.getSemesterEnabled();
    DateTime? start = await StorageService.getSemesterStart();
    DateTime? end = await StorageService.getSemesterEnd();
    if (mounted) {
      setState(() {
        _semesterEnabled = enabled;
        _semesterStart = start;
        _semesterEnd = end;
      });
    }
  }

  double _calculateSemesterProgress() {
    if (_semesterStart == null || _semesterEnd == null) return 0.0;
    DateTime now = DateTime.now();
    if (now.isBefore(_semesterStart!)) return 0.0;
    if (now.isAfter(_semesterEnd!)) return 1.0;

    int totalMinutes = _semesterEnd!.difference(_semesterStart!).inMinutes;
    int passedMinutes = now.difference(_semesterStart!).inMinutes;
    if (totalMinutes <= 0) return 0.0;
    return (passedMinutes / totalMinutes).clamp(0.0, 1.0);
  }

  Future<void> _loadSectionPreferences() async {
    final prefs = await SharedPreferences.getInstance();

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
    } else {
      List<String> combined = [...leftOrder, ...rightOrder];
      for (var key in defaultOrder) {
        if (!combined.contains(key)) {
          leftOrder.insert(0, key);
        }
      }
    }

    String? savedVisibilityStr = prefs.getString('home_section_visibility');
    if (savedVisibilityStr != null) {
      if (mounted) {
        setState(() {
          Map<String, bool> savedMap = Map<String, bool>.from(jsonDecode(savedVisibilityStr));
          savedMap.putIfAbsent('courses', () => true);
          savedMap.putIfAbsent('countdowns', () => true);
          savedMap.putIfAbsent('todos', () => true);
          savedMap.putIfAbsent('screenTime', () => true);
          savedMap.putIfAbsent('math', () => true);
          _sectionVisibility = savedMap;
        });
      }
    }

    String? noCourseBehav = prefs.getString('no_course_behavior');
    if (mounted) {
      setState(() {
        _leftSections = leftOrder!;
        _rightSections = rightOrder!;
        if (noCourseBehav != null) _noCourseBehavior = noCourseBehav;
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkAutoSync();
      _loadSectionPreferences();
      _loadSemesterSettings();
      _checkUpdatesSilently();
    }
  }

  Future<void> _checkAutoSync() async {
    // 🛡️ 安全检查：升级引导未完成时禁止任何自动同步
    // 防止用户跳过引导进入主页后，空的本地数据被推送并覆盖云端数据
    final guideNeeded = await UpgradeGuideScreen.shouldShow();
    if (guideNeeded) return;

    int interval = await StorageService.getSyncInterval();
    DateTime? lastSync = await StorageService.getLastAutoSyncTime();
    DateTime now = DateTime.now();

    if (interval == 0) {
      _handleManualSync(silent: true);
    } else {
      if (lastSync == null || now.difference(lastSync).inMinutes >= interval) {
        _handleManualSync(silent: true);
      }
    }
  }

  void _markCurrentTodoDone() async {
    DateTime now = DateTime.now();
    DateTime today = DateTime(now.year, now.month, now.day);

    List<TodoItem> activeTodos = _todos.where((t) {
      if (t.dueDate == null) return true;
      DateTime d = DateTime(t.dueDate!.year, t.dueDate!.month, t.dueDate!.day);
      return !d.isAfter(today);
    }).toList();

    TodoItem? currentTodo;
    for (var t in activeTodos) {
      if (!t.isDone) {
        currentTodo = t;
        break;
      }
    }

    if (currentTodo != null) {
      setState(() {
        currentTodo!.isDone = true;
        currentTodo!.markAsChanged();
        _todos.sort((a, b) => a.isDone == b.isDone ? 0 : (a.isDone ? 1 : -1));
      });

      // 所有的待办都需要连同隐藏的逻辑删除数据一起存
      final allTodos = await StorageService.getTodos(widget.username);
      int idx = allTodos.indexWhere((x) => x.id == currentTodo!.id);
      if(idx != -1) allTodos[idx] = currentTodo!;
      await StorageService.saveTodos(widget.username, allTodos);

      _syncTodoNotification();
      await WidgetService.updateTodoWidget(_todos);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已完成: ${currentTodo.title}'), duration: const Duration(seconds: 1)),
        );
      }
    }
  }

  String get _timeSalutation {
    final hour = DateTime.now().hour;
    if (hour >= 5 && hour < 12) return "上午好";
    if (hour >= 12 && hour < 14) return "中午好";
    if (hour >= 14 && hour < 18) return "下午好";
    return "晚上好";
  }

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

  // 🚀 核心重构：渲染主页时，绝对不能将 isDeleted 的数据加载到视图层！
  Future<void> _loadAllData() async {
    final allCountdowns = await StorageService.getCountdowns(widget.username);
    final allTodos = await StorageService.getTodos(widget.username);
    final stats = await StorageService.getMathStats(widget.username);
    final courseData = await CourseService.getDashboardCourses();

    if (mounted) {
      setState(() {
        _countdowns = allCountdowns.where((c) => !c.isDeleted).toList();
        _todos = allTodos.where((t) => !t.isDeleted).toList();
        _mathStats = stats;
        _dashboardCourseData = courseData;
      });
      _syncTodoNotification();
      await WidgetService.updateTodoWidget(_todos);
    }
  }

  void _syncTodoNotification() {
    DateTime now = DateTime.now();
    DateTime today = DateTime(now.year, now.month, now.day);

    List<TodoItem> activeTodos = _todos.where((t) {
      if (t.dueDate == null) return true;
      DateTime d = DateTime(t.dueDate!.year, t.dueDate!.month, t.dueDate!.day);
      return !d.isAfter(today);
    }).toList();

    if (activeTodos.isEmpty || activeTodos.every((t) => t.isDone)) {
      const MethodChannel('com.math_quiz.junpgle.com.math_quiz_app/notifications')
          .invokeMethod('cancelNotification');
    } else {
      NotificationService.updateTodoNotification(activeTodos);
    }
  }

  Future<void> _handleManualSync({
    bool silent = false,
    bool syncTodos = true,
    bool syncCountdowns = true,
    bool syncScreenTime = true,
  }) async {
    if (_isSyncing) return;
    setState(() {
      _isSyncing = true;
      if (syncScreenTime) _isLoadingScreenTime = true;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      int? userId = prefs.getInt('current_user_id');
      if (userId == null) throw Exception("未登录");

      bool hasChanges = false;

      if (syncTodos || syncCountdowns) {
        hasChanges = await StorageService.syncData(
          widget.username,
          syncTodos: syncTodos,
          syncCountdowns: syncCountdowns,
          context: context,
        );
      }

      if (syncScreenTime) {
        await ScreenTimeService.syncScreenTime(userId);
        await _loadCachedScreenTime();
      }

      await StorageService.updateLastAutoSyncTime();

      if (mounted) {
        if (!silent) {
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('✅ 数据同步完成'), backgroundColor: Colors.green)
          );
        }
        if (hasChanges) _loadAllData();
      }
    } catch (e) {
      debugPrint("Sync Error: $e");
      if (mounted && !silent) {
        String msg = e.toString();
        if (msg.contains("LIMIT_EXCEEDED:")) {
          msg = msg.split("LIMIT_EXCEEDED:").last;
        } else {
          msg = "同步失败: 获取数据异常";
        }
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(msg), backgroundColor: Colors.redAccent)
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSyncing = false;
          _isLoadingScreenTime = false;
        });
      }
    }
  }

  void _showSyncOptionsDialog() {
    bool syncTodos = true;
    bool syncCountdowns = true;
    bool syncScreenTime = true;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text("手动同步", style: TextStyle(fontWeight: FontWeight.bold)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("请勾选你需要同步的数据模块：", style: TextStyle(fontSize: 13, color: Colors.grey)),
                  const SizedBox(height: 12),
                  CheckboxListTile(
                    title: const Text("待办事项"),
                    value: syncTodos,
                    onChanged: (val) => setDialogState(() => syncTodos = val ?? false),
                  ),
                  CheckboxListTile(
                    title: const Text("重要日与倒计时"),
                    value: syncCountdowns,
                    onChanged: (val) => setDialogState(() => syncCountdowns = val ?? false),
                  ),
                  CheckboxListTile(
                    title: const Text("屏幕使用时间"),
                    value: syncScreenTime,
                    onChanged: (val) => setDialogState(() => syncScreenTime = val ?? false),
                  ),
                ],
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("取消")),
                FilledButton(
                  onPressed: (syncTodos || syncCountdowns || syncScreenTime) ? () {
                    Navigator.pop(ctx);
                    _handleManualSync(
                      silent: false,
                      syncTodos: syncTodos,
                      syncCountdowns: syncCountdowns,
                      syncScreenTime: syncScreenTime,
                    );
                  } : null,
                  child: const Text("开始同步"),
                ),
              ],
            );
          }
      ),
    );
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

  Widget _buildSemesterProgressBar(bool isLight) {
    if (!_semesterEnabled || _semesterStart == null || _semesterEnd == null) return const SizedBox.shrink();

    double progress = _calculateSemesterProgress();

    return Container(
      width: double.infinity,
      height: 4.0,
      alignment: Alignment.centerLeft,
      child: FractionallySizedBox(
        widthFactor: progress,
        child: Container(
          decoration: BoxDecoration(
            color: isLight ? Colors.lightBlueAccent : Theme.of(context).colorScheme.primary,
            boxShadow: [
              if (progress > 0)
                BoxShadow(
                  color: (isLight ? Colors.lightBlueAccent : Theme.of(context).colorScheme.primary).withOpacity(0.5),
                  blurRadius: 4,
                  offset: const Offset(0, 1),
                )
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    bool isDarkMode = Theme.of(context).brightness == Brightness.dark;
    bool showWallpaper = !isDarkMode && _wallpaperUrl != null;
    bool isLight = showWallpaper;

    return Scaffold(
      backgroundColor: showWallpaper ? Colors.transparent : Theme.of(context).colorScheme.surface,
      body: Stack(
        children: [
          if (showWallpaper)
            Positioned.fill(child: CachedNetworkImage(imageUrl: _wallpaperUrl!, fit: BoxFit.cover, fadeInDuration: const Duration(milliseconds: 800), placeholder: (context, url) => Container(color: Theme.of(context).colorScheme.surface))),
          if (showWallpaper)
            Positioned.fill(child: Container(color: Colors.black.withOpacity(0.4))),

          SafeArea(
            child: Column(
              children: [
                _buildSemesterProgressBar(isLight),

                HomeAppBar(
                  username: widget.username,
                  timeSalutation: _timeSalutation,
                  currentGreeting: _currentGreeting,
                  isLight: isLight,
                  isSyncing: _isSyncing,
                  onSync: _showSyncOptionsDialog,
                  onSettings: () async {
                    await Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsPage()));
                    _loadSectionPreferences();
                    _loadSemesterSettings();
                    _loadAllData();
                  },
                ),

                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final bool isTablet = constraints.maxWidth >= 768;

                      Widget courseSection = CourseSectionWidget(dashboardCourseData: _dashboardCourseData, isLight: isLight);
                      Widget countdownSection = CountdownSectionWidget(countdowns: _countdowns, username: widget.username, isLight: isLight, onDataChanged: _loadAllData);
                      Widget todoSection = TodoSectionWidget(
                        key: _todoSectionKey, todos: _todos, username: widget.username, isLight: isLight,
                        onTodosChanged: (newTodos) async {
                          setState(() => _todos = newTodos);
                          // 🚀 这里只修改当前展示的待办，存回数据库前要和隐藏的老数据合并
                          final allTodos = await StorageService.getTodos(widget.username);
                          for(var newT in _todos){
                            int idx = allTodos.indexWhere((x) => x.id == newT.id);
                            if(idx != -1) allTodos[idx] = newT;
                            else allTodos.add(newT);
                          }
                          await StorageService.saveTodos(widget.username, allTodos);
                          _syncTodoNotification();
                          await WidgetService.updateTodoWidget(_todos);
                        },
                        onRefreshRequested: _loadAllData,
                      );
                      Widget screenTimeSection = Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SectionHeader(title: "屏幕时间 (今日汇总)", icon: Icons.timer_outlined, isLight: isLight),
                          ScreenTimeCard(
                            stats: _screenTimeStats, hasPermission: _hasUsagePermission, isLoading: _isLoadingScreenTime, lastSyncTime: _lastScreenTimeSync,
                            onOpenSettings: () async { await ScreenTimeService.openSettings(); _initScreenTime(); },
                            onViewDetail: () { Navigator.push(context, MaterialPageRoute(builder: (_) => ScreenTimeDetailScreen(todayStats: _screenTimeStats))); },
                          ),
                        ],
                      );
                      Widget mathSection = Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SectionHeader(title: "数学测验", icon: Icons.functions, isLight: isLight),
                          MathStatsCard(stats: _mathStats, onTap: () async { await Navigator.push(context, MaterialPageRoute(builder: (_) => MathMenuScreen(username: widget.username))); _loadAllData(); }),
                        ],
                      );

                      Map<String, Widget> sectionsMap = {
                        'courses': courseSection, 'countdowns': countdownSection, 'todos': todoSection, 'screenTime': screenTimeSection, 'math': mathSection,
                      };

                      bool hasNoCourse = (_dashboardCourseData['courses'] == null || (_dashboardCourseData['courses'] as List).isEmpty);
                      List<String> currentLeft = List.from(_leftSections);
                      List<String> currentRight = List.from(_rightSections);

                      void applyNoCourseBehavior(List<String> targetList) {
                        if (hasNoCourse && targetList.contains('courses')) {
                          if (_noCourseBehavior == 'hide') {
                            targetList.remove('courses');
                          } else if (_noCourseBehavior == 'bottom') {
                            targetList.remove('courses');
                            targetList.add('courses');
                          }
                        }
                      }
                      applyNoCourseBehavior(currentLeft);
                      applyNoCourseBehavior(currentRight);

                      List<Widget> buildColumnWidgets(List<String> keys) {
                        return keys
                            .where((key) => _sectionVisibility[key] == true && sectionsMap.containsKey(key))
                            .map((key) => Padding(padding: const EdgeInsets.only(bottom: 24.0), child: sectionsMap[key]!))
                            .toList();
                      }

                      List<Widget> leftWidgets = buildColumnWidgets(currentLeft);
                      List<Widget> rightWidgets = buildColumnWidgets(currentRight);

                      return SingleChildScrollView(
                        padding: EdgeInsets.symmetric(horizontal: isTablet ? 32 : 16, vertical: 16),
                        child: Align(
                          alignment: Alignment.topCenter,
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 1200),
                            child: isTablet
                                ? Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: leftWidgets)),
                                if (rightWidgets.isNotEmpty) const SizedBox(width: 32),
                                if (rightWidgets.isNotEmpty) Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: rightWidgets)),
                              ],
                            )
                                : Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [...leftWidgets, ...rightWidgets],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          FloatingActionButton.small(
            heroTag: 'fab_pomodoro',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => PomodoroScreen(username: widget.username),
                ),
              );
            },
            tooltip: '番茄钟',
            child: const Text('🍅', style: TextStyle(fontSize: 18)),
          ),
          const SizedBox(height: 8),
          FloatingActionButton.extended(
            heroTag: 'fab_todo',
            onPressed: () => _todoSectionKey.currentState?.showAddTodoDialog(),
            icon: const Icon(Icons.add_task),
            label: const Text("记待办"),
          ),
        ],
      ),
    );
  }
}