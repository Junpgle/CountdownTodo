import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'dart:math';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'dart:async';
import 'dart:ui';
import 'package:path_provider/path_provider.dart';
import '../services/search_service.dart';
import '../utils/page_transitions.dart';

// 引入服务和模型
import '../models.dart';
import '../storage_service.dart';
import '../update_service.dart';
import '../services/api_service.dart';
import '../services/background_notification_service.dart';
import '../services/notification_service.dart';
import '../services/widget_service.dart';
import '../services/screen_time_service.dart';
import '../services/course_service.dart';
import '../services/course_calendar_adjustment_service.dart';
import '../services/external_share_handler.dart';
import '../services/wallpaper_cache_service.dart';
import '../services/pomodoro_service.dart';
import '../services/pomodoro_control_service.dart';
import '../services/pomodoro_sync_service.dart';
import '../services/reminder_schedule_service.dart';
import '../services/float_window_service.dart';
import '../services/island_slot_provider.dart';
import '../services/ai_todo_chat_launcher.dart';

// 引入其他页面
import 'screen_time_detail_screen.dart';
import 'math_menu_screen.dart';
import 'home_settings_screen.dart';
import 'feature_guide_screen.dart';
import 'todo_confirm_screen.dart';
import 'add_todo_screen.dart';
import 'course_screens.dart';
import 'course_calendar_adjustment_screen.dart';
import 'band_sync_screen.dart';
import 'conflict_inbox_screen.dart';
import 'team_management_screen.dart';
// 引入拆分后的组件
import '../widgets/home_sections.dart';
import '../widgets/home_app_bar.dart';
import '../widgets/countdown_section_widget.dart';
import '../widgets/course_section_widget.dart';
import '../widgets/todo_section_widget.dart';
import '../widgets/pomodoro_today_section.dart';
import '../widgets/plan_block_today_section.dart';
import '../widgets/conflict_alert_dialog.dart';
import '../widgets/sync_status_banner.dart'; // 🚀 引入
import '../widgets/sticky_announcement_banner.dart'; // 🚀 引入
import 'pomodoro_screen.dart';
import 'todo_plan_screen.dart';
// 🚀 引入
// 🚀 引入
import '../widgets/global_search_overlay.dart';
import '../widgets/personal_timeline_section.dart';

class HomeDashboard extends StatefulWidget {
  final String username;
  const HomeDashboard({
    super.key,
    required this.username,
  });

  @override
  State<HomeDashboard> createState() => _HomeDashboardState();
}

class _HomeDashboardState extends State<HomeDashboard>
    with WidgetsBindingObserver {
  bool _isSameDay(DateTime date1, DateTime date2) {
    return date1.year == date2.year &&
        date1.month == date2.month &&
        date1.day == date2.day;
  }

  // === 状态变量 ===
  List<CountdownItem> _countdowns = [];
  List<TodoItem> _todos = [];
  List<TodoGroup> _todoGroups = [];
  List<ConflictInfo> _latestSyncConflicts = [];
  Map<String, dynamic> _mathStats = {};
  List<dynamic> _screenTimeStats = [];
  Map<String, dynamic> _dashboardCourseData = {
    'title': '课程提醒',
    'courses': <CourseItem>[]
  };

  String _noCourseBehavior = 'keep';
  bool _hasUsagePermission = true;
  bool _isSyncing = false;
  String? _wallpaperUrl;
  String? _wallpaperCopyright;
  bool _wallpaperShow = false;
  bool _isLoadingScreenTime = true;
  DateTime? _lastScreenTimeSync;
  String _currentGreeting = "";
  bool _semesterEnabled = false;
  DateTime? _semesterStart;
  DateTime? _semesterEnd;

  List<String> _leftSections = ['courses', 'todos', 'math'];
  List<String> _rightSections = [
    'countdowns',
    'screenTime',
    'timeline',
    'pomodoro'
  ];

  Map<String, bool> _sectionVisibility = {
    'courses': true,
    'countdowns': true,
    'todos': true,
    'planBlocks': true,
    'screenTime': true,
    'math': true,
    'pomodoro': true,
    'timeline': true,
  };
  Timer? _courseTimer;
  final Set<String> _coursesWithScheduledAlarms = {};
  final Set<int> _activeTodoNotifIds = {};
  Timer? _todoPersistDebounce;
  Completer<void>? _todoPersistDebounceCompleter;
  Future<void> _todoPersistChain = Future.value();
  List<TodoItem>? _pendingTodosToPersist;
  List<TodoItem>? _persistingTodosSnapshot;
  final GlobalKey<TodoSectionWidgetState> _todoSectionKey = GlobalKey();
  final GlobalKey _settingsButtonKey = GlobalKey();
  final GlobalKey _pomodoroCardKey = GlobalKey();
  final GlobalKey _mathCardKey = GlobalKey();
  final GlobalKey _screenTimeCardKey = GlobalKey();
  final GlobalKey _focusBannerKey = GlobalKey();
  final GlobalKey _fabPomodoroKey = GlobalKey();
  final GlobalKey _fabTodoKey = GlobalKey();
  final GlobalKey _courseButtonKey = GlobalKey();
  // 每次自增触发首页专注记录卡片与时间轴刷新
  final ValueNotifier<int> _timelineRefreshTriggerNotifier =
      ValueNotifier<int>(0);

  int _selectedTabIndex = 0;

  // 待确认的待办数据（从图片识别来）
  Map<String, dynamic>? _pendingTodoConfirm;

  // ── 跨端专注感知 ──
  CrossDevicePomodoroState? _remotePomodoro; // 其他设备正在进行的专注
  Timer? _remotePomodoroTicker;
  int _remotePomodoroRemaining = 0;
  StreamSubscription? _remotePomodoroSub;
  StreamSubscription? _connStateSub; // 🚀 兼容性修复：改为通配订阅类型
  final _syncService = PomodoroSyncService();
  String _deviceId = '';
  bool _hasShownUpdate = false;
  bool _hasCheckedHolidayPreset = false;
  TeamAnnouncement? _activeAnnouncement; // 🚀 新增：当前置顶公告

  // ── 本地专注状态 ──
  PomodoroRunState? _localPomodoro;
  List<TodoPlanBlock> _planBlocks = [];
  bool _pendingReloadRequested = false;

  final List<StreamSubscription<MethodCall>> _notifSubs = [];
  bool _navigatingToPomodoro = false;
  Route<dynamic>? _pomodoroRoute;
  final Set<String> _updatedByOthersTodoIds = <String>{};
  int _remoteTodoHighlightSignal = 0;
  Timer? _remoteTodoHighlightTimer;
  int _teamPendingCount = 0; // 🚀 Uni-Sync 4.0: 团队待处理消息数
  bool _hasTeamConflictDot = false;
  String? _currentSelectedTeamUuid; // 🚀 选中的团队 ID
  String? _currentSelectedTeamName; // 🚀 选中的团队名称
  final Set<int> _handledForegroundNotificationIds = <int>{};
  Timer? _localPomodoroTicker;
  int _localPomodoroRemaining = 0;
  StreamSubscription<PomodoroRunState?>? _localPomodoroSub; // 🚀 新增：本地专注状态订阅
  Timer? _collaborativeSyncDebouncer; // 🚀 协同同步防抖器
  Timer? _bannerRefreshTimer; // 🚀 新增：Banner 倒计时刷新定时器
  final ValueNotifier<int> _pomodoroTickNotifier = ValueNotifier<int>(0);

  // 🚀 Granular Refresh Notifiers
  late final ValueNotifier<List<TodoItem>> _todosNotifier;
  late final ValueNotifier<List<TodoGroup>> _groupsNotifier;
  late final ValueNotifier<Map<String, dynamic>> _courseDataNotifier;
  late final ValueNotifier<List<CountdownItem>> _countdownsNotifier;
  late final ValueNotifier<Map<String, dynamic>> _mathStatsNotifier;

  final ValueNotifier<bool> _isGlobalLoadingNotifier =
      ValueNotifier<bool>(false);
  final ValueNotifier<int> _todoUpdateSignalNotifier = ValueNotifier<int>(0);

  // 🚀 GlobalKeys for Zoom Animations
  final GlobalKey _searchButtonKey = GlobalKey();
  final GlobalKey _teamsButtonKey = GlobalKey();
  final GlobalKey _aiButtonKey = GlobalKey();
  final GlobalKey _courseCenterKey = GlobalKey();

  Future<void> _openAiAssistantFromAppBar() async {
    final todoState = _todoSectionKey.currentState;
    if (todoState != null) {
      await todoState.openAiAssistant(sourceKey: _aiButtonKey);
      return;
    }

    try {
      final results = await Future.wait<dynamic>([
        CourseService.getAllCourses(widget.username),
        StorageService.getTimeLogs(widget.username),
        PomodoroService.getRecords(),
        ApiService.fetchTeams(),
      ]);
      final courses = (results[0] as List<CourseItem>)
          .where((course) => !course.isDeleted)
          .toList();
      final timeLogs = (results[1] as List<TimeLogItem>)
          .where((log) => !log.isDeleted)
          .toList();
      final pomodoroRecords = (results[2] as List<PomodoroRecord>)
          .where((record) => !record.isDeleted)
          .toList();
      final teams = (results[3] as List)
          .whereType<Map>()
          .map((t) => Team.fromJson(Map<String, dynamic>.from(t)))
          .toList();
      final categoryReminderDefaults =
          await StorageService.getCategoryReminderMinutes(widget.username);

      if (!mounted) return;
      await AiTodoChatLauncher.open(
        context,
        username: widget.username,
        sourceKey: _aiButtonKey,
        todos: _todos.where((t) => !t.isDone && !t.isDeleted).toList(),
        todoGroups: _todoGroups,
        courses: courses,
        timeLogs: timeLogs,
        pomodoroRecords: pomodoroRecords,
        conflicts: _latestSyncConflicts,
        teams: teams,
        categoryReminderDefaults: categoryReminderDefaults,
        onTodoGroupsChanged: (groups) {
          unawaited(_handleAiTodoGroupsChanged(groups));
        },
        onTodosBatchAction: (inserted, updated) {
          unawaited(_handleAiTodosBatchAction(inserted, updated));
        },
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('打开AI助手失败: $e')),
      );
    }
  }

  Future<void> _handleAiTodoGroupsChanged(List<TodoGroup> groups) async {
    if (!mounted) return;
    setState(() => _todoGroups = groups.where((g) => !g.isDeleted).toList());
    await StorageService.saveTodoGroups(widget.username, groups, sync: true);
  }

  Future<void> _handleAiTodosBatchAction(
    List<TodoItem> inserted,
    List<TodoItem> updated,
  ) async {
    final nextTodos = List<TodoItem>.from(_todos)..addAll(inserted);
    for (final item in updated) {
      final idx = nextTodos.indexWhere((t) => t.id == item.id);
      if (idx >= 0) {
        nextTodos[idx] = item;
      } else {
        nextTodos.add(item);
      }
    }
    if (!mounted) return;
    setState(() => _todos = nextTodos);
    await StorageService.saveTodos(widget.username, nextTodos);
    await _saveTodosToSharedFile(nextTodos);
    _timelineRefreshTriggerNotifier.value++;
    _todoUpdateSignalNotifier.value++;
    FloatWindowService.triggerReminderCheck();
    FloatWindowService.invalidateSlotCache();
    FloatWindowService.update();
    _syncTodoNotification();
    _rescheduleAlarms();
    await WidgetService.updateTodoWidget(nextTodos);
  }

  // === 初始化与生命周期 ===
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // 冷启动清理残留通知
    NotificationService.cancelSpecialTodoNotification(12351); // 番茄钟结束提醒
    NotificationService.cancelTodoRecognizeNotification(); // 图片识别通知
    _loadSectionPreferences();
    _loadSemesterSettings();
    _generateGreeting();
    _loadAllData();
    _initManifestWallpaper();
    WidgetService.init();
    _configureBackgroundNotificationPoll();
    _initCrossDevicePomodoro(); // 首页也连接 WS
    _initLocalPomodoroMonitoring(); // 🚀 修改：使用 Stream 监测本地专注状态

    // 🚀 Granular Refresh Initialization
    _todosNotifier = ValueNotifier<List<TodoItem>>(_todos);
    _groupsNotifier = ValueNotifier<List<TodoGroup>>(_todoGroups);
    _courseDataNotifier =
        ValueNotifier<Map<String, dynamic>>(_dashboardCourseData);
    _countdownsNotifier = ValueNotifier<List<CountdownItem>>(_countdowns);
    _mathStatsNotifier = ValueNotifier<Map<String, dynamic>>(_mathStats);

    // 🚀 核心修复：监听全局数据刷新信号，实现背景同步后的 UI 自动响应
    StorageService.dataRefreshNotifier.addListener(_loadAllData);

    // 🚀 使用集中式事件分发，避免多个页面覆盖同一个 MethodChannel handler
    if (Platform.isAndroid || Platform.isIOS) {
      _notifSubs.add(NotificationService.listen('markCurrentTodoDone', (call) {
        debugPrint("📱 收到 markCurrentTodoDone 调用: arguments=${call.arguments}");
        final args = call.arguments;
        int? notifId;
        if (args is Map) {
          notifId = args['notificationId'] as int?;
        }
        debugPrint("📱 解析 notifId: $notifId");
        _markCurrentTodoDone(notifId: notifId);
      }));
      _notifSubs.add(NotificationService.listen('openTodoConfirm', (call) {
        _checkPendingTodoConfirm();
      }));
      _notifSubs.add(NotificationService.listen('openShortcut', (call) {
        final shortcutType = call.arguments as String?;
        debugPrint("⚡ 收到 openShortcut 调用: $shortcutType");
        if (shortcutType != null) {
          _handleShortcut(shortcutType);
        }
      }));
      _notifSubs.add(NotificationService.listen('viewAnalysisImage', (call) {
        final imagePath = call.arguments as String?;
        if (imagePath != null && mounted) {
          _showAnalysisImage(imagePath);
        }
      }));
      _notifSubs.add(NotificationService.listen('viewOriginalText', (call) {
        final text = call.arguments as String?;
        if (text != null && mounted) {
          _showOriginalText(text);
        }
      }));
      _notifSubs.add(NotificationService.listen('openPlanBlock', (call) {
        debugPrint("📅 收到 openPlanBlock 调用: arguments=${call.arguments}");
        if (mounted) {
          _handleOpenPlanBlock(call.arguments);
        }
      }));
      _notifSubs.add(NotificationService.listen('openPomodoro', (call) {
        debugPrint("🍅 收到 openPomodoro 调用");
        _navigateToPomodoro();
      }));
      _notifSubs.add(NotificationService.listen('openTodoList', (call) {
        debugPrint("📋 收到 openTodoList 调用");
        if (mounted) {
          Navigator.of(context).popUntil((route) => route.isFirst);
        }
      }));
      // 通知按钮事件：如果不在番茄钟页，先导航过去，
      // PomodoroScreen 的 listen() 会自动 replay pending 事件。
      for (final action in ['pomodoroFinishEarly', 'pomodoroAbandon']) {
        _notifSubs.add(NotificationService.listen(action, (call) {
          debugPrint("🍅 收到 $action");
          _navigateToPomodoro();
        }));
      }
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) _initNotifications();
      });
      Future.delayed(const Duration(milliseconds: 1000), () {
        if (mounted) _initScreenTime();
      });
      // 灵动岛启动时自动显示 idle 状态
      Future.delayed(const Duration(milliseconds: 1500), () {
        if (mounted) {
          StorageService.syncAppMappings();
          _initIslandOnStartup();
          _checkOfficialHolidayPreset();
        }
      });

      // 保活：检查精确闹钟权限（Android 12+），仅首次提示一次
      Future.delayed(const Duration(milliseconds: 2000), () {
        if (mounted) _checkExactAlarmPermission();
      });

      ExternalShareHandler.init(
        context,
        () {
          _loadAllData();
        },
        onTodoRecognized: (results, imagePath) {
          // 刷新待确认数据（从 StorageService 获取最新状态）
          _checkPendingTodoConfirm().then((_) {
            // 如果识别成功且有结果，自动打开确认页面
            if (results.isNotEmpty && mounted) {
              _navigateToTodoConfirm(results, imagePath, null);
            }
          });
        },
      );

      // 检查是否有待确认的待办数据（从通知点击进入）
      _checkPendingTodoConfirm();

      _checkAutoSync();
      _checkUpdatesSilently();

      _courseTimer = Timer.periodic(const Duration(minutes: 1), (timer) {
        _checkUpcomingEvents();
      });

      // 🚀 Banner 倒计时实时刷新：每 10 秒触发 Banner 区域重绘，确保”剩 Xm”动态更新
      _bannerRefreshTimer =
          Timer.periodic(const Duration(seconds: 10), (timer) {
        if (mounted) _pomodoroTickNotifier.value++;
      });

      // 立即执行一次
      Future.delayed(Duration(milliseconds: 500), () {
        if (mounted) {
          _checkUpcomingEvents();
          setState(() {});
        }
      });
      _checkAndNavigateToPomodoro();
      // 🚀 预热搜索索引，确保首次点击秒开
      SearchService.instance.warmup();
      // 🚀 清理 7 天前的过期图片
      TodoItem.cleanupAnalysisImages();
    });
  }

  Future<void> _configureBackgroundNotificationPoll() async {
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getInt('current_user_id');
    final token =
        ApiService.getToken() ?? prefs.getString(StorageService.KEY_AUTH_TOKEN);
    if (userId == null || token == null || token.isEmpty) return;
    await BackgroundNotificationService.configureNotificationPoll(
      userId: userId,
      token: token,
      apiBaseUrl: ApiService.effectiveBaseUrl,
    );
  }

  @override
  void dispose() {
    for (final sub in _notifSubs) {
      sub.cancel();
    }
    _todosNotifier.dispose();
    _groupsNotifier.dispose();
    _courseDataNotifier.dispose();
    _countdownsNotifier.dispose();
    _mathStatsNotifier.dispose();
    _connStateSub?.cancel();
    _remotePomodoroSub?.cancel();
    _localPomodoroSub?.cancel();
    _remotePomodoroTicker?.cancel();
    _localPomodoroTicker?.cancel();
    ExternalShareHandler.dispose();
    _courseTimer?.cancel();
    _todoPersistDebounce?.cancel();
    if (_todoPersistDebounceCompleter?.isCompleted == false) {
      _todoPersistDebounceCompleter!.complete();
    }
    _collaborativeSyncDebouncer?.cancel();
    _remoteTodoHighlightTimer?.cancel();
    _bannerRefreshTimer?.cancel();
    _pomodoroTickNotifier.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// 检查 Android 12+ 精确闹钟权限，未授权时弹一次引导 SnackBar
  Future<void> _checkExactAlarmPermission() async {
    final granted = await NotificationService.checkExactAlarmPermission();
    if (granted) return;
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('⏰ 需要「精确闹钟」权限才能在 App 被杀后准时发送提醒'),
        action: SnackBarAction(
          label: '去授权',
          onPressed: NotificationService.openExactAlarmSettings,
        ),
        duration: const Duration(seconds: 8),
      ),
    );
  }

  /// 导航到待办确认页面
  Future<dynamic> _navigateToTodoConfirm(List<Map<String, dynamic>> results,
      String? imagePath, String? originalText,
      [String? teamUuid, String? teamName]) async {
    if (!mounted || results.isEmpty) return null;

    return Navigator.push(
      context,
      PageTransitions.slideHorizontal(TodoConfirmScreen(
        llmResults: results,
        imagePath: imagePath,
        originalText: originalText,
        initialTeamUuid: teamUuid,
        initialTeamName: teamName,
        onConfirm: (confirmedResults) {
          // 用户确认后，直接批量添加待办
          _batchAddTodos(confirmedResults, teamUuid, teamName);
          // 清除待确认数据（如果有）
          if (_pendingTodoConfirm != null) {
            setState(() => _pendingTodoConfirm = null);
            ExternalShareHandler.clearPendingTodoConfirm();
          }
        },
        onSkip: () {
          // 用户跳过全部待办，清除待确认数据
          if (_pendingTodoConfirm != null) {
            setState(() => _pendingTodoConfirm = null);
            ExternalShareHandler.clearPendingTodoConfirm();
          }
        },
      )),
    );
  }

  /// 批量添加待办 (支持团队上下文关联)
  Future<void> _batchAddTodos(List<Map<String, dynamic>> todosData,
      [String? teamUuid, String? teamName]) async {
    if (todosData.isEmpty) return;

    final newTodos = todosData.map((data) {
      DateTime? dueDate;
      int? createdDate;

      if (data['endTime'] != null) {
        dueDate = DateTime.tryParse(data['endTime']);
      }

      if (data['startTime'] != null) {
        final startTime = DateTime.tryParse(data['startTime']);
        if (startTime != null) {
          createdDate = startTime.millisecondsSinceEpoch;
        }
      }

      return TodoItem(
        title: data['title'] ?? '',
        remark: data['remark'],
        dueDate: dueDate,
        createdDate: createdDate,
        createdAt: DateTime.now().millisecondsSinceEpoch,
        // 📸 关联图片路径（兼容确认页与存储层两种字段名）
        imagePath: (data['imagePath'] ?? data['image_path']) as String?,
        // 📄 原始分析文本
        originalText:
            (data['originalText'] ?? data['original_text']) as String?,
        teamUuid: data['team_uuid'] ?? teamUuid, // 🚀 关联团队
        teamName: data['team_name'] ?? teamName, // 🚀 团队名称
      );
    }).toList();

    // 更新本地列表
    setState(() {
      _todos = [...newTodos, ..._todos];
      _timelineRefreshTriggerNotifier.value++; // 🚀 触发时间轴刷新
    });

    // 保存到数据库
    final allTodos = await StorageService.getTodos(widget.username);
    for (var newT in newTodos) {
      int idx = allTodos.indexWhere((x) => x.id == newT.id);
      if (idx != -1) {
        allTodos[idx] = newT;
      } else {
        allTodos.add(newT);
      }
    }
    await StorageService.saveTodos(widget.username, allTodos);

    // 将待办数据写入共享文件供 Island 读取
    await _saveTodosToSharedFile(allTodos);

    // 通知 Island 检查提醒并刷新槽位缓存
    FloatWindowService.triggerReminderCheck();
    FloatWindowService.invalidateSlotCache();
    _syncTodoNotification();
    await WidgetService.updateTodoWidget(_todos);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('已添加 ${newTodos.length} 个待办'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  /// 检查是否有待确认的待办数据（从通知点击进入）
  Future<void> _checkPendingTodoConfirm() async {
    final pendingData = await ExternalShareHandler.getPendingTodoConfirm();
    if (!mounted) return;

    if (pendingData != null) {
      final imagePath = pendingData['imagePath'] as String?;
      // 只要有 imagePath 就显示卡片（支持 processing/retrying/failed/success 状态）
      if (imagePath != null) {
        // 保存待确认数据，显示入口卡片
        setState(() {
          _pendingTodoConfirm = pendingData;
        });
        return;
      }
    }

    // 没有待确认数据，清除状态
    setState(() {
      _pendingTodoConfirm = null;
    });
  }

  /// 显示全屏图片预览（针对分析产生的图片）
  void _showAnalysisImage(String imagePath) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
            title: const Text("原本分析图片"),
          ),
          body: Center(
            child: InteractiveViewer(
              minScale: 0.5,
              maxScale: 4.0,
              child: Image.file(
                File(imagePath),
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) {
                  return const Center(
                    child: Text(
                      "图片加载失败，文件可能已过期删除",
                      style: TextStyle(color: Colors.white),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 显示原始分析文本对话框
  void _showOriginalText(String text) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("分析原始文字"),
        content: SingleChildScrollView(
          child: SelectableText(
            text,
            style: const TextStyle(fontSize: 14, height: 1.5),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("确定"),
          ),
        ],
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );
  }

  /// 将已有的 PomodoroScreen 带到前台，或 push 新的。
  /// 用 remove + push 代替 popUntil，避免破坏栈中其他路由。
  void _navigateToPomodoro() {
    if (!mounted || _navigatingToPomodoro) return;
    final nav = Navigator.of(context);

    if (_pomodoroRoute != null) {
      if (_pomodoroRoute!.isCurrent) return; // 已在栈顶，无需操作
      // 已有番茄钟页但被其他页面盖住：remove 后重新 push 到顶部
      try {
        nav.removeRoute(_pomodoroRoute!);
      } catch (_) {
        // route 已被 pop（如用户手动返回），清除引用
        _pomodoroRoute = null;
      }
    }

    // push 新的（或被 remove 的）番茄钟页
    _navigatingToPomodoro = true;
    final route = MaterialPageRoute(
      builder: (_) => PomodoroScreen(username: widget.username),
      settings: const RouteSettings(name: 'pomodoro'),
    );
    _pomodoroRoute = route;
    nav.push(route).whenComplete(() {
      _navigatingToPomodoro = false;
      // 如果是被用户手动 pop 的（不是 removeRoute），清除引用
      if (_pomodoroRoute == route) _pomodoroRoute = null;
    });
  }

  /// 处理 App Shortcut 导航
  void _handleShortcut(String shortcutType) {
    if (!mounted) return;
    debugPrint("⚡ 处理 Shortcut: $shortcutType");
    switch (shortcutType) {
      case 'settings':
        Navigator.of(context).push(
          PageTransitions.slideHorizontal(const SettingsPage()),
        );
        break;
      case 'schedule':
        PageTransitions.pushFromRect(
          context: context,
          page: WeeklyCourseScreen(username: widget.username),
          sourceKey: _courseButtonKey,
        );
        break;
      case 'band':
        Navigator.of(context).push(
          PageTransitions.slideHorizontal(const BandSyncScreen()),
        );
        break;
    }
  }

  /// 处理规划块通知点击，导航到规划页面
  Future<void> _handleOpenPlanBlock(dynamic arguments) async {
    // notifId 33001-33999，减去 33001 得到 plan block 在调度列表中的 index
    int? notifId;
    String? planBlockId;
    if (arguments is Map) {
      notifId = arguments['notifId'] as int?;
      planBlockId =
          (arguments['planBlockId'] ?? arguments['plan_block_id'])?.toString();
    }
    debugPrint("📅 打开规划提醒, notifId=$notifId, planBlockId=$planBlockId");
    TodoPlanBlock? target;
    final blocks = await StorageService.getPlanBlocks(widget.username);
    if (planBlockId != null && planBlockId.isNotEmpty) {
      for (final block in blocks) {
        if (block.uuid == planBlockId && !block.isDeleted) {
          target = block;
          break;
        }
      }
    }
    if (target == null && notifId != null) {
      const baseId = 33001;
      final idx = notifId - baseId;
      if (idx >= 0 && idx < blocks.length) target = blocks[idx];
    }
    if (target != null) {
      if (target.status == TodoPlanStatus.planned ||
          target.status == TodoPlanStatus.reminded) {
        target.status = TodoPlanStatus.reminded;
        target.markAsChanged();
        await StorageService.savePlanBlocks(widget.username, [target],
            sync: true);
      }
      // 导航到规划页面，由用户手动决定是否开始专注
      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => TodoPlanScreen(
            username: widget.username,
            initialDate: DateTime.now(),
          ),
        ),
      );
      return;
    }
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TodoPlanScreen(
          username: widget.username,
          initialDate: DateTime.now(),
        ),
      ),
    );
  }

  /// 打开待确认待办页面
  Future<void> _openPendingTodoConfirm() async {
    if (_pendingTodoConfirm == null) return;

    final imagePath = _pendingTodoConfirm!['imagePath'] as String?;
    final results = _pendingTodoConfirm!['results'] as List<dynamic>?;

    if (imagePath == null || results == null || results.isEmpty) return;

    final List<Map<String, dynamic>> typedResults =
        results.map((e) => Map<String, dynamic>.from(e as Map)).toList();

    final confirmedResults =
        await _navigateToTodoConfirm(typedResults, imagePath, null);

    // 只有用户实际确认了待办才清除，直接返回则保留
    if (confirmedResults != null && (confirmedResults as List).isNotEmpty) {
      setState(() {
        _pendingTodoConfirm = null;
      });
      ExternalShareHandler.clearPendingTodoConfirm();
    }
  }

  Future<void> _initCrossDevicePomodoro() async {
    _deviceId = await StorageService.getDeviceId();
    final prefs = await SharedPreferences.getInstance();
    final userIdInt = prefs.getInt('current_user_id');
    if (userIdInt == null || _deviceId.isEmpty) return;

    _remotePomodoroSub?.cancel();
    _remotePomodoroSub =
        _syncService.onStateChanged.listen(_handleRemotePomodoroSignal);

    // 🍅 发起端重连后，服务端回推了历史专注状态
    // 若本地已无对应状态（说明已被用户关闭/完成），则通知云端清除残留
    _syncService.onStaleSyncFocus = (state) async {
      debugPrint('[首页] 收到服务端回推的残留状态，校验本地...');
      final saved = await PomodoroService.loadRunState();
      if (saved == null ||
          (saved.phase != PomodoroPhase.focusing &&
              saved.phase != PomodoroPhase.breaking)) {
        debugPrint('[首页] 本地无运行中的专注状态，发送 CLEAR_FOCUS 清除云端残留');
        _syncService.sendClearFocusSignal();
      } else {
        debugPrint('[首页] 本地仍有运行中的专注，保留云端状态');
      }
    };

    // 监听网络重连，主动上报本地专注状态
    _connStateSub?.cancel();
    _connStateSub = _syncService.onConnectionChanged.listen((state) async {
      if (state == SyncConnectionState.connected) {
        final saved = await PomodoroService.loadRunState();
        if (saved == null) return;

        if (saved.phase == PomodoroPhase.focusing ||
            saved.phase == PomodoroPhase.breaking) {
          final isCountUp = saved.mode == TimerMode.countUp;
          final remaining = isCountUp
              ? 1
              : saved.targetEndMs - DateTime.now().millisecondsSinceEpoch;
          if (remaining > 0) {
            debugPrint("🔗 [首页] WS已连上，主动向云端同步本地运行中的专注状态");

            final allTags = await PomodoroService.getTags();
            List<String> realTagNames = [];
            for (String uuid in saved.tagUuids) {
              final tag = allTags.where((t) => t.uuid == uuid).firstOrNull;
              if (tag != null) {
                realTagNames.add(tag.name);
              }
            }

            _syncService.sendReconnectSyncSignal(
              sessionUuid: saved.sessionUuid,
              todoUuid: saved.todoUuid,
              todoTitle: saved.todoTitle,
              durationSeconds: saved.phase == PomodoroPhase.focusing
                  ? saved.plannedFocusSeconds
                  : saved.breakSeconds,
              targetEndMs: saved.targetEndMs,
              tagNames: realTagNames,
              mode: saved.mode.index,
              customTimestamp: saved.sessionStartMs, // 🚀 关键：使用真实的起点时间
            );
          }
        }
      }
    });

    // 🚀 显式获取版本号传给底层服务（双重保险）
    String appVersion = 'unknown';
    try {
      final info = await PackageInfo.fromPlatform();
      appVersion = info.version;
    } catch (_) {}

    // 🚀 获取 auth token 用于 WebSocket 鉴权
    String? authToken = ApiService.getToken();
    if (authToken == null || authToken.isEmpty) {
      authToken = prefs.getString(StorageService.KEY_AUTH_TOKEN);
      // 同步回 ApiService 以防万一
      if (authToken != null) ApiService.setToken(authToken);
    }

    await _syncService.ensureConnected(
        userIdInt.toString(), 'flutter_$_deviceId',
        authToken: authToken, appVersion: appVersion);
  }

  // FloatWindow channel is now handled by FloatWindowService

  // 🚀 修改：处理云端发来的 UPDATE_AVAILABLE 信号
  Future<void> _handleRemotePomodoroSignal(
      CrossDevicePomodoroState signal) async {
    if (!mounted || _deviceId.isEmpty) return;
    if (signal.sourceDevice == _deviceId ||
        signal.sourceDevice == 'flutter_$_deviceId') {
      return;
    }

    switch (signal.action) {
      // 🚀 新增：拦截云端的更新推送
      case 'UPDATE_AVAILABLE':
        if (!_hasShownUpdate && mounted && signal.manifestData != null) {
          _hasShownUpdate = true;
          final manifest = AppManifest.fromJson(signal.manifestData!);

          PackageInfo packageInfo = await PackageInfo.fromPlatform();
          if (!mounted) return;

          // 复用强大的 UpdateService 弹窗
          UpdateService.showUpdateDialog(context, manifest, packageInfo.version,
              hasUpdate: true);
        }
        break;
      case 'TEAM_REMOVED':
        debugPrint('🚀 [协同] 收到强制移除信号，立即执行同步与本地清理...');
        await _handleManualSync(silent: true);
        if (mounted) _loadAllData();
        break;

      case 'TEAM_UPDATE':
      case 'SYNC_DATA':
      case 'JOIN_REQUEST_APPROVED':
      case 'TEAM_MEMBER_JOINED':
      case 'NEW_INVITATION':
        debugPrint('🚀 [协同信号] 收到 ${signal.action}, 触发静默同步');
        _debounceCollaborativeSync();
        break;

      case 'NEW_JOIN_REQUEST':
      case 'PENDING_COUNTS':
        _fetchTeamPendingCount();
        break;

      case 'NOTIFICATION_EVENT':
        _fetchTeamPendingCount();
        final eventId = signal.delta is Map
            ? int.tryParse(signal.delta['id']?.toString() ?? '')
            : null;
        if (eventId != null && eventId > 0) {
          unawaited(
            BackgroundNotificationService.markNotificationEventShown(
              eventId,
            ),
          );
          if (!_handledForegroundNotificationIds.add(eventId)) {
            break;
          }
        }
        final title =
            signal.delta is Map ? signal.delta['title']?.toString() : null;
        final body =
            signal.delta is Map ? signal.delta['body']?.toString() : null;
        if (title != null && title.isNotEmpty) {
          NotificationService.showGenericNotification(
            title: title,
            body: body ?? '',
          );
        }
        break;

      case 'NEW_ANNOUNCEMENT':
      case 'ANNOUNCEMENT_RECALLED':
        _fetchActiveAnnouncements();
        break;

      case 'START':
      case 'SYNC_FOCUS':
      case 'RECONNECT_SYNC':
        final isCountUp = signal.mode == 1;
        final endMs = signal.targetEndMs;
        if (endMs == null) return;

        int rem = 0;
        if (isCountUp) {
          final timestamp =
              signal.timestamp ?? DateTime.now().millisecondsSinceEpoch;
          rem = ((DateTime.now().millisecondsSinceEpoch - timestamp) / 1000)
              .floor();
        } else {
          rem = ((endMs - DateTime.now().millisecondsSinceEpoch) / 1000).ceil();
          if (rem <= 0) return;
        }

        setState(() {
          _remotePomodoro = signal;
          _remotePomodoroRemaining = rem;
        });
        _startRemotePomodoroTicker(endMs, isCountUp);

        if (Platform.isWindows) {
          final prefs = await SharedPreferences.getInstance();
          if (prefs.getBool('float_window_enabled') ?? true) {
            await FloatWindowService.update(
              endMs: isCountUp ? signal.timestamp : endMs,
              title: signal.todoTitle ?? '',
              tags: signal.tags,
              isLocal: false,
              mode: isCountUp ? 1 : 0,
              note: signal.note ?? '',
            );
          }
        }
        break;

      case 'STOP':
      case 'INTERRUPT':
      case 'FOCUS_DISCONNECTED':
        _stopRemotePomodoroTicker();
        setState(() => _remotePomodoro = null);

        // 远端专注结束/断连后，将本地仍为 focusing 状态的规划块重置
        _resetStalePlanBlockFocus();

        if (Platform.isWindows) {
          await FloatWindowService.update(endMs: 0, isLocal: false);
        }
        break;

      case 'SWITCH':
        if (_remotePomodoro == null) return;
        final isCountUp = _remotePomodoro!.mode == 1;
        setState(() {
          _remotePomodoro = CrossDevicePomodoroState(
            action: _remotePomodoro!.action,
            sessionUuid: signal.sessionUuid ?? _remotePomodoro!.sessionUuid,
            todoUuid: signal.todoUuid ?? _remotePomodoro!.todoUuid,
            todoTitle: signal.todoTitle ?? _remotePomodoro!.todoTitle,
            duration: _remotePomodoro!.duration,
            targetEndMs: _remotePomodoro!.targetEndMs,
            sourceDevice: _remotePomodoro!.sourceDevice,
            timestamp: signal.timestamp ?? _remotePomodoro!.timestamp,
            mode: _remotePomodoro!.mode,
            tags: _remotePomodoro!.tags,
            note: signal.note ?? _remotePomodoro!.note,
          );
          if (isCountUp) {
            _remotePomodoroRemaining = 0; // 🚀 关键：同步侧归零
          }
        });
        if (isCountUp) {
          _startRemotePomodoroTicker(_remotePomodoro!.targetEndMs ?? 0, true);
        }
        if (Platform.isWindows) {
          await FloatWindowService.update(
            endMs: isCountUp
                ? (_remotePomodoro!.timestamp ??
                    DateTime.now().millisecondsSinceEpoch)
                : (_remotePomodoro!.targetEndMs ?? 0),
            title: _remotePomodoro!.todoTitle ?? '',
            tags: _remotePomodoro!.tags,
            isLocal: false,
            mode: isCountUp ? 1 : 0,
            note: _remotePomodoro!.note ?? '',
          );
        }
        break;

      case 'UPDATE_NOTE':
        if (_remotePomodoro == null) return;
        if (signal.sessionUuid != null &&
            signal.sessionUuid != _remotePomodoro!.sessionUuid) {
          return;
        }
        final isCountUp = _remotePomodoro!.mode == 1;
        setState(() {
          _remotePomodoro = CrossDevicePomodoroState(
            action: _remotePomodoro!.action,
            sessionUuid: _remotePomodoro!.sessionUuid,
            todoUuid: _remotePomodoro!.todoUuid,
            todoTitle: _remotePomodoro!.todoTitle,
            duration: _remotePomodoro!.duration,
            targetEndMs: _remotePomodoro!.targetEndMs,
            sourceDevice: _remotePomodoro!.sourceDevice,
            timestamp: _remotePomodoro!.timestamp,
            mode: _remotePomodoro!.mode,
            tags: _remotePomodoro!.tags,
            note: signal.note ?? '',
          );
        });
        if (Platform.isWindows) {
          await FloatWindowService.update(
            endMs: isCountUp
                ? (_remotePomodoro!.timestamp ??
                    DateTime.now().millisecondsSinceEpoch)
                : (_remotePomodoro!.targetEndMs ?? 0),
            title: _remotePomodoro!.todoTitle ?? '',
            tags: _remotePomodoro!.tags,
            isLocal: false,
            mode: isCountUp ? 1 : 0,
            note: _remotePomodoro!.note ?? '',
          );
        }
        break;
    }
  }

  void _startRemotePomodoroTicker(int targetEndMs, bool isCountUp) {
    _remotePomodoroTicker?.cancel();
    _remotePomodoroTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) {
        _remotePomodoroTicker?.cancel();
        return;
      }
      if (isCountUp) {
        _remotePomodoroRemaining++;
        _pomodoroTickNotifier.value++;
      } else {
        final rem =
            ((targetEndMs - DateTime.now().millisecondsSinceEpoch) / 1000)
                .ceil();
        if (rem <= 0) {
          _remotePomodoroTicker?.cancel();
          if (mounted) setState(() => _remotePomodoro = null);
        } else {
          _remotePomodoroRemaining = rem;
          _pomodoroTickNotifier.value++;
        }
      }
    });
  }

  void _stopRemotePomodoroTicker() {
    _remotePomodoroTicker?.cancel();
    _remotePomodoroTicker = null;
  }

  /// 🚀 重新实现：监测本地专注状态
  /// 不再使用 1 秒一次的轮询读取 Storage，改为监听 Stream
  void _initLocalPomodoroMonitoring() {
    _localPomodoroSub?.cancel();
    _localPomodoroSub = PomodoroService.onRunStateChanged.listen((saved) {
      if (!mounted) return;
      if (saved != null &&
          (saved.phase == PomodoroPhase.focusing ||
              saved.phase == PomodoroPhase.breaking)) {
        final now = DateTime.now().millisecondsSinceEpoch;
        final isCountUp = saved.mode == TimerMode.countUp;
        final rem = isCountUp
            ? ((now - saved.sessionStartMs) / 1000).floor()
            : ((saved.targetEndMs - now) / 1000).ceil();

        setState(() {
          _localPomodoro = saved;
          _localPomodoroRemaining = rem;
        });
        _startLocalTicker(isCountUp);
      } else {
        _stopLocalTicker();
        setState(() {
          _localPomodoro = null;
          _localPomodoroRemaining = 0;
        });
      }
    });

    // 初始加载一次
    PomodoroService.loadRunState().then((saved) {
      if (!mounted || saved == null) return;
      if (saved.phase == PomodoroPhase.focusing ||
          saved.phase == PomodoroPhase.breaking) {
        final now = DateTime.now().millisecondsSinceEpoch;
        final isCountUp = saved.mode == TimerMode.countUp;
        final rem = isCountUp
            ? ((now - saved.sessionStartMs) / 1000).floor()
            : ((saved.targetEndMs - now) / 1000).ceil();

        setState(() {
          _localPomodoro = saved;
          _localPomodoroRemaining = rem;
        });
        _startLocalTicker(isCountUp);
      }
    });
  }

  void _startLocalTicker(bool isCountUp) {
    _localPomodoroTicker?.cancel();
    _localPomodoroTicker = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted || _localPomodoro == null) {
        timer.cancel();
        return;
      }
      final now = DateTime.now().millisecondsSinceEpoch;
      final pomMode = _localPomodoro!.mode;
      final isActuallyCountUp = pomMode == TimerMode.countUp;

      final rem = isActuallyCountUp
          ? ((now - _localPomodoro!.sessionStartMs) / 1000).floor()
          : ((_localPomodoro!.targetEndMs - now) / 1000).ceil();

      _localPomodoroRemaining = rem;
      if (!isActuallyCountUp && _localPomodoroRemaining <= 0) {
        _localPomodoroRemaining = 0;
        _stopLocalTicker();
      }
      _pomodoroTickNotifier.value++;
    });
  }

  void _stopLocalTicker() {
    _localPomodoroTicker?.cancel();
    _localPomodoroTicker = null;
  }

  /// 待确认待办入口卡片（从图片识别来）
  Widget _buildPendingTodoConfirmCard(bool isLight) {
    if (_pendingTodoConfirm == null) return const SizedBox.shrink();

    final imagePath = _pendingTodoConfirm!['imagePath'] as String?;
    final results = _pendingTodoConfirm!['results'] as List<dynamic>?;
    final status = _pendingTodoConfirm!['status'] as String? ?? 'success';
    final todoCount = results?.length ?? 0;
    final currentAttempt = _pendingTodoConfirm!['currentAttempt'] as int? ?? 1;
    final maxAttempts = _pendingTodoConfirm!['maxAttempts'] as int? ?? 1;
    final errorMsg = _pendingTodoConfirm!['errorMsg'] as String?;

    // 处理中或重试中状态
    final isProcessing = status == 'processing' || status == 'retrying';
    // 失败状态
    final isFailed = status == 'failed';
    // 成功状态
    final isSuccess = status == 'success';

    // 成功状态但没有结果，不显示卡片
    if (isSuccess && todoCount == 0) return const SizedBox.shrink();

    // 根据状态确定图标、标题、副标题
    IconData statusIcon;
    Color iconColor;
    String title;
    String subtitle;

    if (isProcessing) {
      statusIcon = Icons.hourglass_top;
      iconColor = Colors.orange;
      title = 'AI识别中...';
      subtitle = '第$currentAttempt/$maxAttempts次尝试，请稍候';
    } else if (isFailed) {
      statusIcon = Icons.error_outline;
      iconColor = Colors.red;
      title = 'AI识别失败';
      subtitle = errorMsg != null && errorMsg.length > 30
          ? '${errorMsg.substring(0, 30)}...'
          : (errorMsg ?? '点击重试');
    } else {
      statusIcon = Icons.check_circle_outline;
      iconColor = Colors.green;
      title = 'AI识别完成';
      subtitle = '发现 $todoCount 个待办，点击查看';
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Material(
        color: isLight ? Colors.white : Colors.grey[900],
        borderRadius: BorderRadius.circular(16),
        elevation: 2,
        child: InkWell(
          onTap: isProcessing
              ? null // 处理中不允许点击
              : (isFailed
                  ? _retryPendingTodoRecognition
                  : _openPendingTodoConfirm),
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                // 图片缩略图或状态图标
                if (isProcessing)
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: Colors.orange.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: Colors.orange,
                      ),
                    ),
                  )
                else if (imagePath != null && File(imagePath).existsSync())
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.file(
                      File(imagePath),
                      width: 48,
                      height: 48,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: Colors.grey[300],
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.image, color: Colors.grey),
                      ),
                    ),
                  )
                else
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: iconColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(statusIcon, color: iconColor),
                  ),
                const SizedBox(width: 12),
                // 文字信息
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: isLight ? Colors.black87 : Colors.white,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 13,
                          color: isFailed ? Colors.red[400] : Colors.grey[600],
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                // 右侧操作按钮
                if (isProcessing)
                  const SizedBox.shrink()
                else if (isFailed)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // 忽略按钮
                      GestureDetector(
                        onTap: _ignorePendingTodoRecognition,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.grey.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '忽略',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Colors.grey[600],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // 重试按钮
                      GestureDetector(
                        onTap: _retryPendingTodoRecognition,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.red.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Text(
                            '重试',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Colors.red,
                            ),
                          ),
                        ),
                      ),
                    ],
                  )
                else
                  Icon(
                    Icons.arrow_forward_ios,
                    size: 16,
                    color: Colors.grey[400],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 重试图片识别
  Future<void> _retryPendingTodoRecognition() async {
    // 更新状态为重试中
    setState(() {
      _pendingTodoConfirm = {
        ...?_pendingTodoConfirm,
        'status': 'retrying',
      };
    });

    await ExternalShareHandler.retryTodoRecognition(
      onTodoRecognized: (results, imagePath) {
        if (!mounted) return;
        // 刷新待确认数据
        _checkPendingTodoConfirm().then((_) {
          // 如果识别成功且有结果，打开确认页面
          if (results.isNotEmpty) {
            _openPendingTodoConfirm();
          }
        });
      },
    );

    // 重试完成后刷新首页状态（无论成功或失败）
    if (mounted) {
      await _checkPendingTodoConfirm();
    }
  }

  /// 忽略图片识别失败
  Future<void> _ignorePendingTodoRecognition() async {
    // 清除待确认数据
    setState(() {
      _pendingTodoConfirm = null;
    });
    await ExternalShareHandler.clearPendingTodoConfirm();
    // 取消通知
    await NotificationService.cancelTodoRecognizeNotification();
  }

  /// 首页顶部的智能通用 Banner (整合专注、课程、待办)
  Widget _buildUniversalBanner(bool isLight) {
    final events = _collectBannerEvents();
    if (events.isEmpty) return const SizedBox.shrink();

    return Column(
      key: _focusBannerKey,
      mainAxisSize: MainAxisSize.min,
      children: events.map((e) => _buildBannerCard(e, isLight)).toList(),
    );
  }

  Widget _buildBannerCard(HomeBannerEvent event, bool isLight) {
    final baseColor = event.baseColor;
    return GestureDetector(
      onTap: event.onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: baseColor.withValues(alpha: isLight ? 0.85 : 0.15),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: baseColor.withValues(alpha: 0.4)),
        ),
        child: Row(
          children: [
            Text(event.icon, style: const TextStyle(fontSize: 18)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    event.label,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: isLight
                          ? Colors.white.withValues(alpha: 0.9)
                          : baseColor,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          event.title,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: isLight ? Colors.white : null,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (event.isTeam)
                        Container(
                          margin: const EdgeInsets.only(left: 6),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: isLight
                                ? Colors.white.withValues(alpha: 0.2)
                                : baseColor.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                                color: isLight
                                    ? Colors.white38
                                    : baseColor.withValues(alpha: 0.3)),
                          ),
                          child: Text(
                            '团队',
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                              color: isLight ? Colors.white : baseColor,
                            ),
                          ),
                        ),
                    ],
                  ),
                  if (event.subtitle != null && event.subtitle!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Row(
                        children: [
                          Icon(
                            event.type == 'course'
                                ? Icons.location_on_outlined
                                : event.type == 'special_todo'
                                    ? Icons.confirmation_number_outlined
                                    : Icons.sticky_note_2_outlined,
                            size: 11,
                            color: isLight ? Colors.white70 : Colors.grey[600],
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              event.subtitle!,
                              style: TextStyle(
                                fontSize: 11,
                                color:
                                    isLight ? Colors.white70 : Colors.grey[600],
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Text(
              event.timeInfo,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: isLight ? Colors.white : baseColor,
              ),
            ),
            if (event.actionLabel != null) ...[
              const SizedBox(width: 8),
              GestureDetector(
                onTap: event.onAction,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: isLight
                        ? Colors.white.withValues(alpha: 0.25)
                        : baseColor.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (event.actionIcon != null) ...[
                        Icon(event.actionIcon,
                            size: 14,
                            color: isLight ? Colors.white : baseColor),
                        const SizedBox(width: 4),
                      ],
                      Text(
                        event.actionLabel!,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: isLight ? Colors.white : baseColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(width: 4),
            Icon(Icons.chevron_right,
                color: isLight ? Colors.white70 : baseColor, size: 18),
          ],
        ),
      ),
    );
  }

  List<HomeBannerEvent> _collectBannerEvents() {
    final List<HomeBannerEvent> events = [];
    final now = DateTime.now();

    // 1. 番茄钟 (优先级最高)
    if (_localPomodoro != null) {
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      final isCountUp = _localPomodoro!.mode == TimerMode.countUp;
      final rem = isCountUp
          ? ((nowMs - _localPomodoro!.sessionStartMs) / 1000).floor()
          : ((_localPomodoro!.targetEndMs - nowMs) / 1000).ceil();

      final m = rem ~/ 60;
      final s = rem % 60;
      final timeStr = isCountUp
          ? '已专注 ${rem ~/ 60}m'
          : (rem > 60
              ? '$m 分钟'
              : '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}');

      // 规划块即将结束时显示停止按钮
      final hasActivePlanBlock = _planBlocks
          .any((b) => !b.isDeleted && b.status == TodoPlanStatus.focusing);
      final bool showStopBtn =
          hasActivePlanBlock && !isCountUp && rem > 0 && rem <= 1800;

      events.add(HomeBannerEvent(
        type: 'pomodoro',
        title: _localPomodoro!.todoTitle ?? '无标题专注',
        label: '⚡ 正在专注 (本机)',
        timeInfo: timeStr,
        baseColor: const Color(0xFF4F46E5),
        icon: '🍅',
        priority: 0,
        actionLabel: showStopBtn ? '关闭' : null,
        actionIcon: showStopBtn ? Icons.stop_rounded : null,
        onAction: showStopBtn ? _stopPlanBlockPomodoro : null,
        onTap: () async {
          await PageTransitions.pushFromRect(
            context: context,
            page: PomodoroScreen(username: widget.username),
            sourceKey: _focusBannerKey,
          );
          if (mounted) _loadAllData();
        },
      ));
    } else if (_remotePomodoro != null) {
      final deviceLabel = _remotePomodoro!.sourceDevice
              ?.replaceFirst('flutter_', '')
              .substring(0, 8) ??
          '其他设备';
      final rem = _remotePomodoroRemaining;
      final m = rem ~/ 60;
      final s = rem % 60;
      final isCountUp = _remotePomodoro!.mode == 1;
      final timeStr = isCountUp
          ? '已专注 ${rem ~/ 60}m'
          : (rem > 60
              ? '$m 分钟'
              : '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}');

      events.add(HomeBannerEvent(
        type: 'pomodoro',
        title: _remotePomodoro!.todoTitle ?? '其他设备专注',
        label: '📱 $deviceLabel 正在专注',
        timeInfo: timeStr,
        baseColor: const Color(0xFFFF6B6B),
        icon: '🍅',
        priority: 1,
        onTap: () => PageTransitions.pushFromRect(
          context: context,
          page: PomodoroScreen(username: widget.username),
          sourceKey: _focusBannerKey,
        ),
      ));
    }

    // 1.5 规划块 (无本地/远端番茄钟运行时展示，支持一键开始/重新开始)
    // 仅在开始前 30 分钟内、进行中、或专注中断时提醒
    if (_localPomodoro == null && _remotePomodoro == null) {
      final nowMs = now.millisecondsSinceEpoch;
      const lookAheadMs = 30 * 60 * 1000;
      final activeBlock = _planBlocks.where((b) {
        if (b.isDeleted) return false;
        if (!_isPlanBlockStartable(b.status)) return false;
        if (nowMs > b.endTime) return false;
        if (b.status == TodoPlanStatus.focusing) return true;
        return nowMs >= b.startTime - lookAheadMs;
      }).firstOrNull;
      if (activeBlock != null) {
        final title = activeBlock.titleSnapshot?.isNotEmpty == true
            ? activeBlock.titleSnapshot!
            : '规划任务';
        final isInterrupted = activeBlock.status == TodoPlanStatus.focusing;
        final remainMin = ((activeBlock.endTime - nowMs) / 60000).ceil();
        final timeText = isInterrupted
            ? (remainMin > 0 ? '剩 ${remainMin}m' : '已超时')
            : (nowMs < activeBlock.startTime
                ? _planBlockStartText(activeBlock.startTime, nowMs)
                : (remainMin > 0 ? '剩 ${remainMin}m' : '进行中'));

        events.add(HomeBannerEvent(
          type: 'plan_block',
          title: title,
          label: isInterrupted ? '⏱ 专注中断' : '📋 规划待专注',
          timeInfo: timeText,
          baseColor:
              isInterrupted ? Colors.deepOrange : const Color(0xFF7C4DFF),
          icon: '📋',
          priority: 1,
          actionLabel: isInterrupted ? '重新开始' : '开始',
          actionIcon: Icons.play_arrow_rounded,
          onTap: () async {
            await Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => TodoPlanScreen(
                  username: widget.username,
                  initialDate: DateTime.now(),
                ),
              ),
            );
            _timelineRefreshTriggerNotifier.value++;
            _loadAllData();
          },
          onAction: () => _startPlanBlockFocus(activeBlock),
        ));
      }
    }

    // 2. 课程
    final List<CourseItem> courses =
        (_dashboardCourseData['courses'] as List?)?.cast<CourseItem>() ?? [];
    for (final course in courses) {
      final startTime = _resolveCourseStartTime(course, now);
      if (startTime == null) continue;

      final endHour = course.endTime ~/ 100;
      final endMin = course.endTime % 100;
      final endTime = DateTime(
          startTime.year, startTime.month, startTime.day, endHour, endMin);

      final diffStart = startTime.difference(now).inMinutes;
      final isOngoing = now.isAfter(startTime) && now.isBefore(endTime);

      if (isOngoing) {
        final remaining = endTime.difference(now).inMinutes;
        events.add(HomeBannerEvent(
          type: 'course',
          title: course.courseName,
          subtitle: course.roomName,
          label: '📖 正在进行的课程',
          timeInfo: '剩 ${remaining}m',
          baseColor: Colors.teal,
          icon: '🏫',
          priority: 2,
          isTeam: course.teamUuid != null,
          onTap: () => Navigator.push(
            context,
            PageTransitions.slideHorizontal(CourseDetailScreen(course: course)),
          ),
        ));
      } else if (diffStart >= 0 && diffStart <= 20) {
        events.add(HomeBannerEvent(
          type: 'course',
          title: course.courseName,
          subtitle: course.roomName,
          label: '🔔 即将开始的课程',
          timeInfo: '${diffStart}m 后开始',
          baseColor: Colors.cyan,
          icon: '🏫',
          priority: 4,
          isTeam: course.teamUuid != null,
          onTap: () => Navigator.push(
            context,
            PageTransitions.slideHorizontal(CourseDetailScreen(course: course)),
          ),
        ));
      }
    }

    // 3. 特殊待办 (快递/取餐/餐饮等): 当天都进入 Banner
    for (final todo in _todos) {
      if (todo.isDone || todo.isDeleted || todo.dueDate == null) continue;

      final specialType = IslandSlotProvider.detectTodoType(todo.title);
      if (specialType == 'default') continue;
      if (!_isSameDay(todo.dueDate!.toLocal(), now)) continue;

      events.add(HomeBannerEvent(
        type: 'special_todo',
        title: todo.title,
        subtitle: todo.remark,
        label: _specialTodoBannerLabel(specialType),
        timeInfo: _specialTodoBannerTimeInfo(todo, now),
        baseColor: _specialTodoBannerColor(specialType),
        icon: _specialTodoBannerIcon(specialType),
        priority: 2,
        isTeam: todo.teamUuid != null,
        onTap: () => _openTodoEditor(todo),
      ));
    }

    // 4. 普通待办 (临近或进行中)
    for (final todo in _todos) {
      if (todo.isDone || todo.isDeleted || todo.dueDate == null) continue;
      if (IslandSlotProvider.detectTodoType(todo.title) != 'default') continue;

      final startMs = todo.createdDate ?? todo.createdAt;
      final startTime = DateTime.fromMillisecondsSinceEpoch(startMs).toLocal();
      final endTime = todo.dueDate!.toLocal();

      // 判定全天任务或跨天任务
      bool isAllDay = startTime.hour == 0 &&
          startTime.minute == 0 &&
          endTime.hour == 23 &&
          endTime.minute == 59;
      bool isCrossDay = startTime.year != endTime.year ||
          startTime.month != endTime.month ||
          startTime.day != endTime.day;
      if (isAllDay || isCrossDay) continue;

      final diffStart = startTime.difference(now).inMinutes;
      final isOngoing = now.isAfter(startTime) && now.isBefore(endTime);

      if (isOngoing) {
        final remaining = endTime.difference(now).inMinutes;
        events.add(HomeBannerEvent(
          type: 'todo',
          title: todo.title,
          subtitle: todo.remark,
          label: '📌 正在进行的任务',
          timeInfo: '剩 ${remaining}m',
          baseColor: Colors.amber[700]!,
          icon: '📝',
          priority: 3,
          isTeam: todo.teamUuid != null,
          onTap: () => _openTodoEditor(todo),
        ));
      } else if (diffStart >= 0 && diffStart <= 30) {
        events.add(HomeBannerEvent(
          type: 'todo',
          title: todo.title,
          subtitle: todo.remark,
          label: '⏰ 即将开始的任务',
          timeInfo: '${diffStart}m 后开始',
          baseColor: Colors.orange,
          icon: '📝',
          priority: 5,
          isTeam: todo.teamUuid != null,
          onTap: () => _openTodoEditor(todo),
        ));
      }
    }

    // 排序: 优先级数值越小越靠前
    events.sort((a, b) => a.priority.compareTo(b.priority));
    return events;
  }

  bool _isPlanBlockStartable(TodoPlanStatus status) {
    return status == TodoPlanStatus.planned ||
        status == TodoPlanStatus.reminded ||
        status == TodoPlanStatus.delayed ||
        status == TodoPlanStatus.focusing;
  }

  /// 远端专注结束/断连后，将 focusing 状态但无对应本地/远端番茄钟的规划块重置为 delayed
  Future<void> _resetStalePlanBlockFocus() async {
    final hasLocal = _localPomodoro != null;
    final hasRemote = _remotePomodoro != null;
    if (hasLocal || hasRemote) return;

    final changed = <TodoPlanBlock>[];
    for (final b in _planBlocks) {
      if (b.isDeleted) continue;
      if (b.status == TodoPlanStatus.focusing) {
        b.status = TodoPlanStatus.delayed;
        b.markAsChanged();
        changed.add(b);
      }
    }
    if (changed.isNotEmpty) {
      await StorageService.savePlanBlocks(widget.username, changed);
      if (mounted) {
        setState(() {});
      }
    }
  }

  String _planBlockStartText(int startTimeMs, int nowMs) {
    final minutes = ((startTimeMs - nowMs) / 60000).ceil();
    return minutes <= 1 ? '马上开始' : '$minutes 分钟后开始';
  }

  Future<void> _startPlanBlockFocus(TodoPlanBlock block) async {
    try {
      final todos = await StorageService.getTodos(widget.username);
      TodoItem? boundTodo;
      for (final todo in todos) {
        if (todo.id == block.todoId && !todo.isDeleted) {
          boundTodo = todo;
          break;
        }
      }
      boundTodo ??= TodoItem(
        id: block.todoId,
        title: block.titleSnapshot?.isNotEmpty == true
            ? block.titleSnapshot!
            : '规划任务',
      );

      final configuredPomodoroMinutes = block.pomodoroRounds > 0
          ? block.pomodoroMinutes * block.pomodoroRounds
          : 0;
      final plannedMinutes = configuredPomodoroMinutes > 0
          ? configuredPomodoroMinutes
          : (block.plannedMinutes > 0
              ? block.plannedMinutes
              : ((block.endTime - block.startTime) / 60000).round());
      block.status = TodoPlanStatus.focusing;
      block.markAsChanged();
      await StorageService.savePlanBlocks(widget.username, [block]);
      final settings = await PomodoroService.getSettings();
      await PomodoroControlService.startFocus(
        settings: settings,
        boundTodo: boundTodo,
        durationMinutes: plannedMinutes < 1 ? 1 : plannedMinutes,
        planBlockId: block.uuid,
      );

      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PomodoroScreen(username: widget.username),
        ),
      );
      if (mounted) {
        _timelineRefreshTriggerNotifier.value++;
        _loadAllData();
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('启动专注失败: $e')),
      );
    }
  }

  Future<void> _stopPlanBlockPomodoro() async {
    try {
      await PomodoroControlService.stopCurrentFocus(
        username: widget.username,
        status: PomodoroRecordStatus.interrupted,
      );
      if (mounted) {
        _timelineRefreshTriggerNotifier.value++;
        _loadAllData();
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('停止专注失败: $e')),
      );
    }
  }

  void _openTodoEditor(TodoItem todo) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TodoEditScreen(
          todo: todo,
          todos: _todos,
          onTodosChanged: _handleTodosChanged,
          todoGroups: _todoGroups,
          onGroupsChanged: (newGroups) async {
            setState(() => _todoGroups = newGroups);
            final allGroups =
                await StorageService.getTodoGroups(widget.username);
            for (var g in newGroups) {
              int idx = allGroups.indexWhere((x) => x.id == g.id);
              if (idx != -1) {
                allGroups[idx] = g;
              } else {
                allGroups.add(g);
              }
            }
            await StorageService.saveTodoGroups(widget.username, allGroups);
            _loadAllData();
          },
          username: widget.username,
        ),
      ),
    );
  }

  String _specialTodoBannerLabel(String specialType) {
    switch (specialType) {
      case 'delivery':
        return '📦 取件待办';
      case 'cafe':
      case 'food':
        return '🥡 取餐待办';
      case 'restaurant':
        return '🍽️ 餐饮待办';
      default:
        return '📌 特殊待办';
    }
  }

  String _specialTodoBannerIcon(String specialType) {
    switch (specialType) {
      case 'delivery':
        return '📦';
      case 'cafe':
        return '☕';
      case 'food':
        return '🥡';
      case 'restaurant':
        return '🍽️';
      default:
        return '📌';
    }
  }

  Color _specialTodoBannerColor(String specialType) {
    switch (specialType) {
      case 'delivery':
        return const Color(0xFFFF8A65);
      case 'cafe':
        return const Color(0xFF8D6E63);
      case 'food':
        return const Color(0xFFFF7043);
      case 'restaurant':
        return const Color(0xFFFFB74D);
      default:
        return Colors.amber[700]!;
    }
  }

  String _specialTodoBannerTimeInfo(TodoItem todo, DateTime now) {
    final dueDate = todo.dueDate?.toLocal();
    if (dueDate == null) return '今日';

    final startMs = todo.createdDate ?? todo.createdAt;
    final startTime = DateTime.fromMillisecondsSinceEpoch(startMs).toLocal();
    final isAllDay = startTime.hour == 0 &&
        startTime.minute == 0 &&
        dueDate.hour == 23 &&
        dueDate.minute == 59;

    if (dueDate.isBefore(now)) return '待处理';
    if (isAllDay) return '今日';
    return DateFormat('HH:mm').format(dueDate);
  }

  // === 业务与辅助逻辑 ===
  DateTime? _resolveCourseStartTime(CourseItem course, DateTime now) {
    final dateText = course.date.trim();

    DateTime? day;
    if (dateText.isNotEmpty) {
      // Prefer strict date parsing, then allow DateTime-compatible fallback.
      try {
        day = DateFormat('yyyy-MM-dd').parseStrict(dateText);
      } catch (_) {
        day = DateTime.tryParse(dateText);
      }
    }

    // Fallback for legacy records without date: infer the day from weekday.
    day ??= DateUtils.dateOnly(now)
        .add(Duration(days: course.weekday - now.weekday));

    final int hour = course.startTime ~/ 100;
    final int minute = course.startTime % 100;
    if (hour < 0 || hour > 23 || minute < 0 || minute > 59) return null;

    return DateTime(day.year, day.month, day.day, hour, minute);
  }

  DateTime? _resolveCourseEndTime(CourseItem course, DateTime now) {
    final dateText = course.date.trim();

    DateTime? day;
    if (dateText.isNotEmpty) {
      try {
        day = DateFormat('yyyy-MM-dd').parseStrict(dateText);
      } catch (_) {
        day = DateTime.tryParse(dateText);
      }
    }

    day ??= DateUtils.dateOnly(now)
        .add(Duration(days: course.weekday - now.weekday));

    final int hour = course.endTime ~/ 100;
    final int minute = course.endTime % 100;
    if (hour < 0 || hour > 23 || minute < 0 || minute > 59) return null;

    return DateTime(day.year, day.month, day.day, hour, minute);
  }

  Future<void> _checkUpcomingEvents() async {
    DateTime now = DateTime.now();

    // 🚀 核心优化：取消一开始就将上一轮通知全量物理注销的逻辑
    // 改为记录上一轮的活跃 ID，本轮计算结束后做差集物理注销
    final previousTodoIds = Set<int>.from(_activeTodoNotifIds);
    final newTodoNotifIds = <int>{};

    // ── 获取已注册闹钟，构建课程去重集合 ──
    try {
      final scheduled = await NotificationService.getScheduledReminders();
      for (final r in scheduled) {
        if (r['type'] == 'course' && r['courseName'] != null) {
          _coursesWithScheduledAlarms.add(r['courseName'] as String);
        }
      }
    } catch (_) {}

    // ── 课程通知 ────────────────────────────────────────────────
    const int courseNotificationId = 12347;

    final dashboardData =
        await CourseService.getDashboardCourses(widget.username);
    List<CourseItem> courses =
        (dashboardData['courses'] as List?)?.cast<CourseItem>() ?? [];

    bool hasUpcomingCourse = false;
    for (var course in courses) {
      try {
        final courseTime = _resolveCourseStartTime(course, now);
        final courseEndTime = _resolveCourseEndTime(course, now);
        if (courseTime == null || courseEndTime == null) continue;

        // 显示窗口：自上课前 20 分钟起，直到下课结束
        final isInsideWindow =
            now.isAfter(courseTime.subtract(const Duration(minutes: 20))) &&
                now.isBefore(courseEndTime);
        if (isInsideWindow) {
          // 已有定时闹钟的课程不再弹实时活动通知
          if (_coursesWithScheduledAlarms.contains(course.courseName)) {
            hasUpcomingCourse = true;
            break;
          }
          NotificationService.showCourseLiveActivity(
            courseName: course.courseName,
            room: course.roomName,
            timeStr:
                '${course.formattedStartTime} - ${course.formattedEndTime}',
            teacher: course.teacherName,
          );
          hasUpcomingCourse = true;
          break;
        }
      } catch (e) {
        debugPrint(
            "检查课程通知失败: $e (course=${course.courseName}, date='${course.date}', start=${course.startTime})");
      }
    }

    // 没有课程在窗口内，仅取消课程通知（不影响待办等其他通知）
    if (!hasUpcomingCourse) {
      NotificationService.cancelSpecialTodoNotification(courseNotificationId);
    }

    // ── 待办提醒 ────────────────────────────────────────────────
    String detectTodoType(String title) {
      final lowerTitle = title.toLowerCase();
      if (lowerTitle.contains('快递') ||
          lowerTitle.contains('取件') ||
          lowerTitle.contains('顺丰') ||
          lowerTitle.contains('京东') ||
          lowerTitle.contains('菜鸟') ||
          lowerTitle.contains('中通') ||
          lowerTitle.contains('圆通') ||
          lowerTitle.contains('韵达') ||
          lowerTitle.contains('申通')) {
        return 'delivery';
      } else if (lowerTitle.contains('奶茶') ||
          lowerTitle.contains('咖啡') ||
          lowerTitle.contains('古茗') ||
          lowerTitle.contains('茶百道') ||
          lowerTitle.contains('蜜雪冰城') ||
          lowerTitle.contains('瑞幸') ||
          lowerTitle.contains('星巴克') ||
          lowerTitle.contains('库迪') ||
          lowerTitle.contains('coco') ||
          lowerTitle.contains('一点点')) {
        return 'cafe';
      } else if (lowerTitle.contains('取餐') ||
          lowerTitle.contains('外卖') ||
          lowerTitle.contains('肯德基') ||
          lowerTitle.contains('麦当劳') ||
          lowerTitle.contains('KFC')) {
        return 'food';
      } else if (lowerTitle.contains('海底捞') ||
          lowerTitle.contains('太二') ||
          lowerTitle.contains('外婆家') ||
          lowerTitle.contains('西贝') ||
          lowerTitle.contains('必胜客') ||
          lowerTitle.contains('堂食') ||
          lowerTitle.contains('餐饮')) {
        return 'restaurant';
      }
      return 'default';
    }

    // 1. 特殊待办 (快递/外卖等): 今天所有的都显示
    final specialTodosToday = _todos.where((t) {
      if (t.isDone || t.isDeleted) return false;
      if (t.dueDate == null) return false;
      final todoType = detectTodoType(t.title);
      if (todoType == 'default') return false;
      return _isSameDay(t.dueDate!.toLocal(), now);
    }).toList();

    for (final todo in specialTodosToday) {
      final int notifId = todo.id.hashCode;
      newTodoNotifIds.add(notifId);
      await NotificationService.showUpcomingTodoNotification(todo);
    }

    // 2. 普通待办 (非全天): 在时间段内（提前 30 分钟直到截止时间）均显示为活动状态
    final upcomingRegularTodos = _todos.where((t) {
      if (t.isDone || t.isDeleted) return false;
      if (t.dueDate == null) return false;
      final todoType = detectTodoType(t.title);
      if (todoType != 'default') return false;

      DateTime localDueDate = t.dueDate!.toLocal();
      DateTime startDate = DateTime.fromMillisecondsSinceEpoch(
              t.createdDate ?? t.createdAt,
              isUtc: true)
          .toLocal();
      bool isAllDay = startDate.hour == 0 &&
          startDate.minute == 0 &&
          localDueDate.hour == 23 &&
          localDueDate.minute == 59;
      if (isAllDay) return false;

      // 🚀 核心改动：在待办执行的时间段内（提前 30 分钟直到截止时间）皆视为正在活动并在通知栏展示
      return now.isAfter(startDate.subtract(const Duration(minutes: 30))) &&
          now.isBefore(localDueDate);
    }).toList();

    for (final todo in upcomingRegularTodos) {
      final int notifId = todo.id.hashCode;
      newTodoNotifIds.add(notifId);
      await NotificationService.showUpcomingTodoNotification(todo);
    }

    // 3. 全天待办汇总
    final allDayTodos = _todos.where((t) {
      if (t.isDone) return false;
      if (t.dueDate == null) return false;
      final todoType = detectTodoType(t.title);
      if (todoType != 'default') return false;
      DateTime localDueDate = t.dueDate!.toLocal();
      if (!_isSameDay(localDueDate, now)) return false;
      DateTime startDate = DateTime.fromMillisecondsSinceEpoch(
              t.createdDate ?? t.createdAt,
              isUtc: true)
          .toLocal();
      return startDate.hour == 0 &&
          startDate.minute == 0 &&
          localDueDate.hour == 23 &&
          localDueDate.minute == 59;
    }).toList();

    NotificationService.updateTodoNotification(allDayTodos);

    // 🚀 4. 差集物理取消不再需要的通知
    final idsToCancel = previousTodoIds.difference(newTodoNotifIds);
    for (final id in idsToCancel) {
      await NotificationService.cancelSpecialTodoNotification(id);
    }

    // 🚀 5. 更新当前的活跃集合
    _activeTodoNotifIds.clear();
    _activeTodoNotifIds.addAll(newTodoNotifIds);
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

    // 均按照默认排序
    // 首页: 重要日(countdowns), 课程(courses), 待办(todos)
    // 专注页: 最近专注(pomodoro), 屏幕时间(screenTime), 测验(math)

    // 平板双栏布局固定分配 (左侧重要日待办, 右侧课程最近专注\屏幕时间\测验)
    _leftSections = ['banners', 'countdowns', 'todos'];
    _rightSections = ['courses', 'timeline', 'pomodoro', 'screenTime', 'math'];

    // 忽略之前的可见性设置，全部强制显示
    _sectionVisibility = {
      'courses': true,
      'countdowns': true,
      'todos': true,
      'planBlocks': true,
      'screenTime': true,
      'math': true,
      'pomodoro': true,
      'timeline': true,
    };

    String? noCourseBehav = prefs.getString('no_course_behavior');
    if (mounted) {
      setState(() {
        if (noCourseBehav != null) _noCourseBehavior = noCourseBehav;
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkAutoSync(force: true);
      _loadSectionPreferences();
      _loadSemesterSettings();
      _checkUpdatesSilently();
      // 🚀 唤醒时重置壁纸重试计数，防止因最小化导致的短暂断网触发兜底
      _wallpaperRetryCount = 0;
      // 从番茄钟页或任何前台切换回来时，刷新专注记录卡片
      if (mounted) _timelineRefreshTriggerNotifier.value++;
      // 平板/手机从后台唤醒时，强制重连触发服务器推送最新跨端专注状态
      _syncService.resumeSync();
      // 清理残留的一次性通知
      NotificationService.cancelSpecialTodoNotification(12351); // 番茄钟结束提醒
      NotificationService.cancelTodoRecognizeNotification(); // 图片识别通知
    }
  }

  /// 启动时检测是否有正在进行的番茄钟，有则跳转至计时界面
  Future<void> _checkAndNavigateToPomodoro() async {
    // 稍微延迟，让首页先完成渲染
    await Future.delayed(const Duration(milliseconds: 800));
    if (!mounted) return;
    // 🚀 有待确认待办时不劫持导航，优先让用户处理识别结果
    if (_pendingTodoConfirm != null) return;
    final saved = await PomodoroService.loadRunState();
    if (saved == null) return;
    if (saved.phase != PomodoroPhase.focusing &&
        saved.phase != PomodoroPhase.breaking) {
      return;
    }
    // 确认倒计时还没结束
    final remaining = saved.targetEndMs - DateTime.now().millisecondsSinceEpoch;
    if (saved.mode == TimerMode.countdown && remaining <= 0) return;

    if (Platform.isWindows) {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool('float_window_enabled') ?? true) {
        final allTags = await PomodoroService.getTags();
        final tagNames = saved.tagUuids
            .map((uuid) =>
                allTags.where((t) => t.uuid == uuid).firstOrNull?.name ?? '')
            .where((n) => n.isNotEmpty)
            .toList();
        final isCountUp = saved.mode == TimerMode.countUp;
        await FloatWindowService.update(
          endMs: isCountUp ? saved.sessionStartMs : saved.targetEndMs,
          title: saved.todoTitle ?? '',
          tags: tagNames,
          isLocal: true,
          mode: isCountUp ? 1 : 0,
        );
      }
    }

    if (!mounted) return;
    await PageTransitions.pushFromRect(
      context: context,
      page: PomodoroScreen(username: widget.username),
      sourceKey: _pomodoroCardKey,
    );
    if (mounted) {
      _timelineRefreshTriggerNotifier.value++;
      _loadAllData(deferred: true);
    }
  }

  /// 启动时自动初始化灵动岛（如果用户已开启）
  Future<void> _initIslandOnStartup() async {
    if (!Platform.isWindows) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final style = prefs.getInt('float_window_style') ?? 0;
      if (style != 1) return;

      // 检查是否有正在进行的番茄钟，如果有，_checkAndNavigateToPomodoro 已处理
      final saved = await PomodoroService.loadRunState();
      if (saved != null &&
          (saved.phase == PomodoroPhase.focusing ||
              saved.phase == PomodoroPhase.breaking)) {
        final remaining =
            saved.targetEndMs - DateTime.now().millisecondsSinceEpoch;
        if (saved.mode == TimerMode.countdown && remaining <= 0) return;
        // 番茄钟场景已由 _checkAndNavigateToPomodoro 处理
        return;
      }

      // 无番茄钟时，显示 idle 状态的灵动岛
      debugPrint('[HomeDashboard] Initializing island on startup (idle state)');
      await FloatWindowService.update(forceReset: true);
    } catch (e) {
      debugPrint('[HomeDashboard] Island startup init failed: $e');
    }
  }

  /// 🚀 Uni-Sync 4.0: 获取所有团队待处理申请总数
  /// 🚀 Uni-Sync 4.0: 获取当前置顶公告
  Future<void> _fetchActiveAnnouncements() async {
    try {
      final list = await ApiService.fetchUnreadPriorityAnnouncements();
      if (list.isNotEmpty && mounted) {
        setState(() {
          _activeAnnouncement = TeamAnnouncement.fromJson(list.first);
        });
      } else if (mounted) {
        setState(() => _activeAnnouncement = null);
      }
    } catch (e) {
      debugPrint('❌ [首页] 获取置顶公告失败: $e');
    }
  }

  Future<void> _fetchTeamPendingCount() async {
    try {
      final rawTeams = await ApiService.fetchTeams();
      int totalPending = 0;

      // 并发获取各团队待处理数
      await Future.wait(rawTeams.map((t) async {
        if (t['role'] == 0) {
          // 如果是管理员
          final reqs = await ApiService.fetchPendingRequests(t['uuid']);
          totalPending += reqs.length;
        }
      }));

      if (mounted) {
        final backgroundUnread = await BackgroundNotificationService
            .getUnreadBackgroundNotifications();
        setState(
            () => _teamPendingCount = totalPending + backgroundUnread.length);
      }
    } catch (e) {
      debugPrint('❌ [首页] 获取团队消息计数失败: $e');
    }
  }

  Future<void> _checkAutoSync({bool force = false}) async {
    // 🛡️ 安全检查：升级引导未完成时禁止任何自动同步
    // 防止用户跳过引导进入主页后，空的本地数据被推送并覆盖云端数据
    final guideNeeded = await FeatureGuideScreen.shouldShow();
    if (guideNeeded) return;

    int interval = await StorageService.getSyncInterval();
    DateTime? lastSync =
        await StorageService.getLastAutoSyncTime(widget.username);
    DateTime now = DateTime.now();

    if (force || interval == 0) {
      _handleManualSync(silent: true);
    } else {
      if (lastSync == null || now.difference(lastSync).inMinutes >= interval) {
        _handleManualSync(silent: true);
      }
    }
  }

  void _markCurrentTodoDone({int? notifId}) async {
    debugPrint(
        "📱 _markCurrentTodoDone 被调用: notifId=$notifId, todos数量=${_todos.length}");

    DateTime now = DateTime.now();
    DateTime today = DateTime(now.year, now.month, now.day);

    List<TodoItem> activeTodos = _todos.where((t) {
      if (t.dueDate == null) return true;
      DateTime d = DateTime(t.dueDate!.year, t.dueDate!.month, t.dueDate!.day);
      return !d.isAfter(today);
    }).toList();

    debugPrint("📱 activeTodos数量=${activeTodos.length}");

    // 普通待办通知的 ID 是 12345，特殊待办通知的 ID 是 todo.id.hashCode
    const int normalTodoNotifId = 12345;

    // 检测是否为特殊待办
    bool isSpecialTodo(String title) {
      final lowerTitle = title.toLowerCase();
      return lowerTitle.contains('快递') ||
          lowerTitle.contains('取件') ||
          lowerTitle.contains('顺丰') ||
          lowerTitle.contains('京东') ||
          lowerTitle.contains('菜鸟') ||
          lowerTitle.contains('中通') ||
          lowerTitle.contains('圆通') ||
          lowerTitle.contains('韵达') ||
          lowerTitle.contains('申通') ||
          lowerTitle.contains('奶茶') ||
          lowerTitle.contains('咖啡') ||
          lowerTitle.contains('古茗') ||
          lowerTitle.contains('茶百道') ||
          lowerTitle.contains('蜜雪冰城') ||
          lowerTitle.contains('瑞幸') ||
          lowerTitle.contains('星巴克') ||
          lowerTitle.contains('库迪') ||
          lowerTitle.contains('coco') ||
          lowerTitle.contains('一点点') ||
          lowerTitle.contains('取餐') ||
          lowerTitle.contains('外卖') ||
          lowerTitle.contains('肯德基') ||
          lowerTitle.contains('麦当劳') ||
          lowerTitle.contains('KFC') ||
          lowerTitle.contains('海底捞') ||
          lowerTitle.contains('太二') ||
          lowerTitle.contains('外婆家') ||
          lowerTitle.contains('西贝') ||
          lowerTitle.contains('必胜客') ||
          lowerTitle.contains('堂食') ||
          lowerTitle.contains('餐饮');
    }

    TodoItem? currentTodo;

    if (notifId == null || notifId == normalTodoNotifId) {
      // 普通待办通知：完成第一个未完成的**普通**待办（跳过特殊待办）
      for (var t in activeTodos) {
        if (!t.isDone && !isSpecialTodo(t.title)) {
          currentTodo = t;
          break;
        }
      }
      debugPrint("📱 普通待办通知，完成第一个未完成的普通待办: ${currentTodo?.title}");
    } else {
      // 特殊待办通知：通过 notifId 找到对应的待办
      currentTodo = activeTodos
          .where((t) => t.id.hashCode == notifId && !t.isDone)
          .firstOrNull;
      debugPrint("📱 特殊待办通知，找到待办: ${currentTodo?.title}");
    }

    // 找不到待办，不执行任何操作
    if (currentTodo == null) {
      debugPrint("找不到对应的待办: notifId=$notifId");
      return;
    }

    debugPrint("📱 准备完成待办: ${currentTodo.title}");

    // 取消特殊待办的通知
    await NotificationService.cancelSpecialTodoNotification(
        currentTodo.id.hashCode);

    setState(() {
      currentTodo!.isDone = true;
      currentTodo.markAsChanged();
      _todos.sort((a, b) => a.isDone == b.isDone ? 0 : (a.isDone ? 1 : -1));
    });

    setState(() {
      currentTodo!.isDone = true;
      currentTodo.markAsChanged();
      _todos.sort((a, b) => a.isDone == b.isDone ? 0 : (a.isDone ? 1 : -1));
    });

    // 🚀 跨端联动：完成待办的同时，告知云端停止对应的番茄钟（如果有设备在观察的话）
    PomodoroSyncService().sendStopSignal(
      todoUuid: currentTodo.id,
      sessionUuid: _localPomodoro?.sessionUuid,
    );

    // 🚀 Uni-Sync 4.0 优化：改用单条原子化更新，性能提升显著
    await StorageService.updateSingleTodo(widget.username, currentTodo);

    // 注意：共享文件的更新逻辑可保持异步，不阻塞主线程交互
    Future.microtask(() async {
      final allTodos = await StorageService.getTodos(widget.username);
      await _saveTodosToSharedFile(allTodos);
    });

    // 通知 Island 检查提醒并刷新槽位缓存
    FloatWindowService.triggerReminderCheck();
    FloatWindowService.invalidateSlotCache();

    _syncTodoNotification();
    await WidgetService.updateTodoWidget(_todos);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('已完成: ${currentTodo.title}'),
            duration: const Duration(seconds: 1)),
      );
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
      greetings = [
        "今天也要元气超标！",
        "新的一天，把快乐置顶。",
        "迎着光，做自己的小太阳。",
        "起床充电，活力满格。",
        "今日宜：开心、努力、好运。"
      ];
    } else if (hour >= 11 && hour < 14) {
      greetings = [
        "吃饱喝足，继续奔赴。",
        "中场能量补给，快乐不打烊。",
        "稳住状态，万事可期。",
        "生活不慌不忙，慢慢发光。",
        "好好吃饭，就是好好爱自己。"
      ];
    } else if (hour >= 14 && hour < 18) {
      greetings = [
        "保持热爱，保持冲劲。",
        "状态在线，干劲拉满。",
        "不急不躁，温柔又有力量。",
        "把普通日子，过得热气腾腾。",
        "继续向前，好运正在路上。"
      ];
    } else if (hour >= 18 && hour < 23) {
      greetings = [
        "晚风轻踩云朵，今天辛苦啦。",
        "卸下疲惫，拥抱温柔。",
        "今日圆满，万事顺心。",
        "把烦恼清空，把快乐装满。",
        "好好休息，明天依旧闪亮。"
      ];
    } else if (hour >= 23 || hour < 3) {
      greetings = [
        "愿你心安，好梦常伴。",
        "安静沉淀，积蓄力量。",
        "不慌不忙，自在生长。",
        "温柔治愈，接纳所有情绪。",
        "今夜安睡，明日更好。"
      ];
    } else {
      greetings = [
        "凌晨的星光，为你照亮前路。",
        "此刻努力，未来可期。",
        "安静时光，悄悄变优秀。",
        "不负自己，不负岁月。",
        "愿你眼里有光，心中有梦。"
      ];
    }

    _currentGreeting = greetings[Random().nextInt(greetings.length)];
  }

  Future<void> _initNotifications() async {
    await NotificationService.init();
    // 🚀 桌面端拦截：Windows 暂无原生通知权限请求
    if (Platform.isAndroid || Platform.isIOS) {
      if (await Permission.notification.isDenied) {
        await Permission.notification.request();
      }
    }
  }

  Future<void> _initScreenTime() async {
    if (mounted) setState(() => _isLoadingScreenTime = true);

    if (!Platform.isAndroid && !Platform.isIOS) {
      // 桌面端：直接走缓存读取+Tai同步，不需要权限检查
      if (mounted) setState(() => _hasUsagePermission = true);
      await _loadCachedScreenTime();
      return;
    }

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

  void _showTokenExpiredDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text("登录已失效"),
        content: const Text("由于您的 Token 无效，请重新登录以同步数据。"),
        actions: [
          FilledButton(
            onPressed: () async {
              // 1. 清理本地所有登录相关的持久化数据
              // 假设你的 StorageService 有清理方法，或者直接操作 prefs
              final prefs = await SharedPreferences.getInstance();
              await prefs.remove('current_user_id');
              await prefs.remove('logged_in_username'); // 顺便清理用户名

              if (!mounted || !ctx.mounted) return;

              // 2. 彻底关闭弹窗并切断路由栈，回到登录页
              Navigator.of(ctx).pop();
              Navigator.pushNamedAndRemoveUntil(
                context,
                '/login',
                (route) => false,
              );
            },
            child: const Text("重新登录"),
          ),
        ],
      ),
    );
  }

  void _debounceCollaborativeSync() {
    _collaborativeSyncDebouncer?.cancel();
    _collaborativeSyncDebouncer =
        Timer(const Duration(milliseconds: 1500), () async {
      if (!mounted) return;
      debugPrint('🔄 [协同] 防抖触发：执行批量同步与界面刷新...');
      await _handleManualSync(silent: true);
      // 🚀 核心修复：协作信号驱动下，强制重新加载数据，不依赖 hasChanges 判断
      if (mounted) {
        _loadAllData();
      }
    });
  }

  /// 🚀 辅助：带超时和错误捕获的任务加载器
  Future<T?> _loadDataTask<T>(String name, Future<T> task) async {
    try {
      final start = DateTime.now();
      final result = await task.timeout(const Duration(seconds: 5));
      final duration = DateTime.now().difference(start).inMilliseconds;
      return result;
    } catch (e) {
      debugPrint("❌ [DashboardLoader] $name 加载超时或异常: $e");
      return null;
    }
  }

  List<TElement> _safeListResult<TElement>(dynamic value) {
    if (value is List<TElement>) {
      return value;
    }
    if (value is List) {
      return value.whereType<TElement>().toList();
    }
    return <TElement>[];
  }

  // 🚀 核心重构：渲染主页时，绝对不能将 isDeleted 的数据加载到视图层！
  Future<void> _loadAllData({bool deferred = false}) async {
    if (_isGlobalLoadingNotifier.value) {
      _pendingReloadRequested = true;
      return;
    }

    if (deferred) {
      // 🚀 核心优化：延迟 400ms 刷新，确保返回动画（Pop）执行完毕后再处理数据
      // 避免 CPU 密集型任务与动画冲突导致卡顿
      await Future.delayed(const Duration(milliseconds: 400));
      if (!mounted) return;
      if (_isGlobalLoadingNotifier.value) {
        _pendingReloadRequested = true;
        return;
      }
    }

    _isGlobalLoadingNotifier.value = true;
    try {
      //debugPrint("⏳ [DashboardLoader] 开始并发加载 5 项核心任务...");

      // 1. 读取基础数据 (并发执行，带超时保护)
      final results = await Future.wait([
        _loadDataTask(
            "Todos", StorageService.getTodos(widget.username, limit: 200)),
        _loadDataTask("Groups", StorageService.getTodoGroups(widget.username)),
        _loadDataTask(
            "Countdowns", StorageService.getCountdowns(widget.username)),
        _loadDataTask("Math", StorageService.getMathStats(widget.username)),
        _loadDataTask(
            "Courses", CourseService.getDashboardCourses(widget.username)),
        _loadDataTask(
            "PlanBlocks", StorageService.getPlanBlocks(widget.username)),
      ]);

      final List<TodoItem> allTodos = _mergePendingTodoSnapshots(
        _safeListResult<TodoItem>(results[0])
            .where((t) => !t.isDeleted)
            .toList(),
      );
      final List<TodoGroup> allGroups = _safeListResult<TodoGroup>(results[1])
          .where((g) => !g.isDeleted)
          .toList();
      final List<CountdownItem> allCountdowns = _safeListResult<CountdownItem>(
        results[2],
      ).where((c) => !c.isDeleted).toList();
      final conflictDetectionEnabled =
          await StorageService.getConflictDetectionEnabled();

      final bool hasTeamConflict = conflictDetectionEnabled &&
          (allTodos.any((t) {
                if (!t.hasConflict || t.collabType == 1 || (t.teamUuid?.isEmpty ?? true)) {
                  return false;
                }
                if (t.isAllDayTask) return false;
                final data = t.serverVersionData;
                if (data != null &&
                    (data['type'] == 'schedule' ||
                        data['conflict_with'] != null)) {
                  final peers = data['conflict_with'];
                  if (peers is List) {
                    final hasValidPeer = peers.any((p) =>
                        p is Map &&
                        !TodoItem.fromJson(Map<String, dynamic>.from(p))
                            .isAllDayTask);
                    if (!hasValidPeer) return false;
                  }
                }
                return true;
              }) ||
              allGroups.any(
                  (g) => g.hasConflict && (g.teamUuid?.isNotEmpty ?? false)) ||
              allCountdowns.any(
                  (c) => c.hasConflict && (c.teamUuid?.isNotEmpty ?? false)));

      final Map<String, dynamic> mathStats =
          (results[3] ?? {}) as Map<String, dynamic>;
      final Map<String, dynamic> courseData = (results[4] ??
          {'title': '课程提醒', 'courses': []}) as Map<String, dynamic>;
      final List<TodoPlanBlock> allPlanBlocks =
          _safeListResult<TodoPlanBlock>(results[5]);

      if (mounted) {
        // 🚀 诊断日志：打印 collabType=1 的 is_completed 值
        for (final t in allTodos.where((t) => t.collabType == 1 && !t.isDeleted)) {
          debugPrint('🧪 [SyncDiag][_loadAllData] collab1 UUID=${t.id} isDone=${t.isDone} version=${t.version}');
        }
        // 🚀 Granular Update: Only update notifiers if content actually changed
        if (!_isListEqual(_todos, allTodos)) {
          _todos = allTodos;
          _todosNotifier.value = allTodos;
        }
        _hasTeamConflictDot = hasTeamConflict;
        if (!_isListEqual(_todoGroups, allGroups)) {
          _todoGroups = allGroups;
          _groupsNotifier.value = allGroups;
        }
        if (!_isListEqual(_countdowns, allCountdowns)) {
          _countdowns = allCountdowns;
          _countdownsNotifier.value = allCountdowns;
        }
        if (!_isMapEqual(_mathStats, mathStats)) {
          _mathStats = mathStats;
          _mathStatsNotifier.value = mathStats;
        }
        if (!_isMapEqual(_dashboardCourseData, courseData)) {
          _dashboardCourseData = courseData;
          _courseDataNotifier.value = courseData;
        }
        _planBlocks = allPlanBlocks;

        _todoUpdateSignalNotifier.value++; // 🚀 触发待办局部更新
        _timelineRefreshTriggerNotifier.value++; // 🚀 触发时间轴与专注卡片局部更新

        // 2. 交互与同步逻辑 (异步执行)
        _syncTodoNotification();
        _fetchTeamPendingCount(); // 🚀 Uni-Sync 4.0: 加载团队消息计数
        _fetchActiveAnnouncements(); // 🚀 Uni-Sync 4.0: 获取置顶公告
        WidgetService.updateTodoWidget(allTodos);

        final allCourses = await CourseService.getAllCourses(widget.username);
        unawaited(ReminderScheduleService.scheduleAll(
          todos: allTodos,
          courses: allCourses,
        ));
      }
    } catch (e) {
      debugPrint('❌ [DashboardLoader] 加载失败: $e');
    } finally {
      if (mounted) {
        _isGlobalLoadingNotifier.value = false;
        if (_pendingReloadRequested) {
          _pendingReloadRequested = false;
          unawaited(_loadAllData());
        }
      }
    }
  }

  Future<void> _checkOfficialHolidayPreset() async {
    if (_hasCheckedHolidayPreset || !mounted) return;
    _hasCheckedHolidayPreset = true;

    final window =
        await CourseCalendarAdjustmentService.pendingOfficialHolidayWindow();
    if (window == null || !mounted) return;

    final action = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${window.name}课表调整提醒'),
        content: const Text('临近法定节假日。不同学校放假和补课安排可能不同，请手动选择放假日期，并确认哪一天的课调到哪一天。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'later'),
            child: const Text('稍后'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'snooze_today'),
            child: const Text('今日不再提醒'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, 'open'),
            child: const Text('去选择'),
          ),
        ],
      ),
    );

    if (action == 'snooze_today') {
      await CourseCalendarAdjustmentService.snoozeOfficialHolidayPromptForToday(
          window.key);
      return;
    }

    if (action == 'open' && mounted) {
      await Navigator.push(
        context,
        PageTransitions.slideHorizontal(
          CourseCalendarAdjustmentScreen(
            initialOfficialHolidayKey: window.key,
          ),
        ),
      );
      if (mounted) await _loadAllData(deferred: true);
    }
  }

  Future<void> _rescheduleAlarms() async {
    final courses = await CourseService.getAllCourses(widget.username);
    await ReminderScheduleService.scheduleAll(
      todos: _todos,
      courses: courses,
    );
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
      NotificationService.cancelSpecialTodoNotification(12345);
    } else {
      NotificationService.updateTodoNotification(activeTodos);
    }

    // 立即检查并显示特殊待办通知
    _checkUpcomingEvents();
  }

  Future<void> _saveTodosToSharedFile(List<TodoItem> todos) async {
    try {
      final dir = await getApplicationSupportDirectory();
      final file = File('${dir.path}/island_todos.json');
      final todosJson = todos
          .map((t) => {
                'id': t.id,
                'title': t.title,
                'remark': t.remark,
                'dueDate': t.dueDate?.toUtc().millisecondsSinceEpoch,
                'createdDate': t.createdDate,
                'createdAt': t.createdAt,
                'isDone': t.isDone,
                'isDeleted': t.isDeleted,
              })
          .toList();
      await file.writeAsString(jsonEncode(todosJson));
      // debugPrint('[HomeDashboard] Saved ${todos.length} todos to shared file');
    } catch (e) {
      debugPrint('[HomeDashboard] Failed to save todos to shared file: $e');
    }
  }

  List<TodoItem> _cloneTodosForPersistence(List<TodoItem> todos) {
    return todos.map((todo) => TodoItem.fromJson(todo.toJson())).toList();
  }

  List<TodoItem> _mergePendingTodoSnapshots(List<TodoItem> loadedTodos) {
    final snapshots = [
      _persistingTodosSnapshot,
      _pendingTodosToPersist,
    ].whereType<List<TodoItem>>();
    if (snapshots.isEmpty) return loadedTodos;

    final byId = {for (final todo in loadedTodos) todo.id: todo};
    for (final snapshot in snapshots) {
      for (final pending in snapshot) {
        final existing = byId[pending.id];
        // 🚀 用户主动修改优先：updatedAt >= 时信任挂起快照
        if (existing == null || pending.updatedAt >= existing.updatedAt) {
          byId[pending.id] = pending;
        }
      }
    }
    return byId.values.where((todo) => !todo.isDeleted).toList();
  }

  Future<void> _handleTodosChanged(List<TodoItem> newTodos) async {
    final oldTodos = List<TodoItem>.from(_todos);
    final nextTodos = List<TodoItem>.from(newTodos);

    if (mounted) {
      setState(() => _todos = nextTodos);
    } else {
      _todos = nextTodos;
    }
    _timelineRefreshTriggerNotifier.value++;

    for (var nt in nextTodos) {
      if (nt.isDone) {
        final ot = oldTodos.firstWhere((t) => t.id == nt.id, orElse: () => nt);
        if (!ot.isDone) {
          debugPrint("🧹 任务 ${nt.title} 已完成，尝试清除通知 ${nt.id.hashCode}");
          NotificationService.cancelSpecialTodoNotification(nt.id.hashCode);
        }
      }
    }

    _pendingTodosToPersist = _cloneTodosForPersistence(nextTodos);
    _todoPersistDebounce?.cancel();
    if (_todoPersistDebounceCompleter?.isCompleted == false) {
      _todoPersistDebounceCompleter!.complete();
    }

    final completer = Completer<void>();
    _todoPersistDebounceCompleter = completer;
    _todoPersistDebounce = Timer(const Duration(milliseconds: 220), () {
      _todoPersistChain = _todoPersistChain.catchError((_) {}).then((_) async {
        final snapshot = _pendingTodosToPersist;
        if (snapshot == null) return;
        _pendingTodosToPersist = null;
        await _persistTodosSnapshot(snapshot);
      }).catchError((e) {
        debugPrint('[HomeDashboard] persist todos failed: $e');
      }).whenComplete(() {
        if (!completer.isCompleted) completer.complete();
      });
    });

    return completer.future;
  }

  Future<void> _persistTodosSnapshot(List<TodoItem> todosSnapshot) async {
    _persistingTodosSnapshot = todosSnapshot;
    final allTodos = await StorageService.getTodos(widget.username);
    try {
      for (var newT in todosSnapshot) {
        int idx = allTodos.indexWhere((x) => x.id == newT.id);
        if (idx != -1) {
          if (newT.updatedAt >= allTodos[idx].updatedAt) {
            allTodos[idx] = newT;
          }
        } else {
          allTodos.add(newT);
        }
      }
      await StorageService.saveTodos(widget.username, allTodos);
      await _saveTodosToSharedFile(allTodos);

      FloatWindowService.triggerReminderCheck();
      FloatWindowService.invalidateSlotCache();
      FloatWindowService.update();
      _syncTodoNotification();
      _rescheduleAlarms();
      await WidgetService.updateTodoWidget(todosSnapshot);

      _todoUpdateSignalNotifier.value++;
    } finally {
      if (identical(_persistingTodosSnapshot, todosSnapshot)) {
        _persistingTodosSnapshot = null;
      }
    }
  }

  Future<void> _handleManualSync({
    bool silent = false,
    bool syncTodos = true,
    bool syncCountdowns = true,
    bool syncScreenTime = true,
    bool syncPomodoro = true,
    bool syncTimeLogs = true,
    bool syncPlanBlocks = true,
  }) async {
    if (_isSyncing) return;

    // 🚀 核心修复：同步前先强制保存用户未持久化的修改（如取消勾选），
    // 防止 syncData 的 saveTodos(isSyncSource=true) 覆盖用户意图。
    final pendingSnapshotBeforeSync = _pendingTodosToPersist;
    if (pendingSnapshotBeforeSync != null) {
      _pendingTodosToPersist = null;
      _todoPersistDebounce?.cancel();
      final changedDesc = pendingSnapshotBeforeSync
          .where((t) => !t.isDeleted)
          .map((t) => '${t.id.substring(0,8)} isDone=${t.isDone}')
          .join(', ');
      debugPrint('🧪 [SyncDiag][forceFlush] 保存 ${pendingSnapshotBeforeSync.length} 条: $changedDesc');
      await StorageService.saveTodos(widget.username, pendingSnapshotBeforeSync);
      // 🚀 设置保护：merge 时跳过这些待办，防止同步覆盖用户刚做的修改
      StorageService.setForceFlushProtectedUuids(
          pendingSnapshotBeforeSync.map((t) => t.id).toSet());
    }

    setState(() {
      _isSyncing = true;
    });

    try {
      // 🚀 核心加固：增加 30 秒超时强制释放锁，防止由于网络异常导致的图标“永动机”
      Timer(const Duration(seconds: 30), () {
        if (mounted && _isSyncing) {
          setState(() => _isSyncing = false);
        }
      });
      final prefs = await SharedPreferences.getInstance();
      int? userId = prefs.getInt('current_user_id');
      if (userId == null) throw Exception("未登录");
      if (!mounted) return;

      bool hasChanges = false;

      // 🚀 2. 判断条件加入 syncTimeLogs
      if (syncTodos || syncCountdowns || syncTimeLogs || syncPlanBlocks) {
        final syncResult = await StorageService.syncData(
          widget.username,
          syncTodos: syncTodos,
          syncCountdowns: syncCountdowns,
          syncTimeLogs: syncTimeLogs,
          syncPlanBlocks: syncPlanBlocks,
          syncPomodoro: false,
          context: context,
        );
        hasChanges = syncResult['hasChanges'] ?? false;
        final List<String> updatedTodoIds =
            (syncResult['updatedTodoIds'] as List?)
                    ?.map((e) => e.toString())
                    .where((e) => e.isNotEmpty)
                    .toList() ??
                const <String>[];
        if (updatedTodoIds.isNotEmpty && mounted) {
          _remoteTodoHighlightTimer?.cancel();
          setState(() {
            _updatedByOthersTodoIds
              ..clear()
              ..addAll(updatedTodoIds);
            _remoteTodoHighlightSignal++;
          });
          _remoteTodoHighlightTimer = Timer(const Duration(seconds: 8), () {
            if (!mounted) return;
            setState(() => _updatedByOthersTodoIds.clear());
          });
        }

        // 🚀 新增：处理冲突信息
        final List<ConflictInfo> conflicts = syncResult['conflicts'] ?? [];
        if (mounted) {
          setState(() => _latestSyncConflicts = conflicts);
        }
        final conflictDetectionEnabled =
            await StorageService.getConflictDetectionEnabled();
        if (conflictDetectionEnabled && conflicts.isNotEmpty && mounted) {
          final shouldOpenConflictCenter =
              await ConflictAlertDialog.show(context, conflicts);
          if (shouldOpenConflictCenter == true && mounted) {
            await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ConflictInboxScreen(
                  username: widget.username,
                  syncConflicts: conflicts,
                ),
              ),
            );
          }
        }
      }

      if (syncPomodoro) {
        await PomodoroService.syncRecordsToCloud();
        await PomodoroService.syncRecordsFromCloud();
        await PomodoroService.syncTagsToCloud();
        await PomodoroService.syncTagsFromCloud();
      }

      if (syncScreenTime) {
        await ScreenTimeService.syncScreenTime(userId);
        await _loadCachedScreenTime();
      }

      await StorageService.updateLastAutoSyncTime(widget.username);

      if (mounted) {
        if (!silent) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('✅ 数据同步完成'), backgroundColor: Colors.green));
        }
        if (hasChanges) {
          // 同步后数据有变化，刷新 Island 槽位缓存
          FloatWindowService.invalidateSlotCache();
          _loadAllData(); // _loadAllData 内部会重新 scheduleAll
        }

        // 🚀 同步手环版本信息
        unawaited(UpdateService.syncBandVersionInfo());
      }
      // ... 前面代码保持不变
    } catch (e) {
      debugPrint("Sync Error: $e");
      String msg = e.toString();

      // 🚀 核心修复 1：Token 检查必须移出 !silent 判断
      // 无论是否是“静默同步”，只要登录失效，就必须强制弹窗
      if (msg.contains("无效的token") ||
          msg.contains("无效的Token") || // 适配你日志中的大写 T
          msg.contains("INVALID_TOKEN") ||
          msg.contains("401")) {
        if (mounted) {
          _showTokenExpiredDialog();
        }
        return; // 拦截后续所有提示
      }

      // 只有非静默同步（手动点击）时，才显示普通的错误 SnackBar
      if (mounted && !silent) {
        if (msg.contains("LIMIT_EXCEEDED:")) {
          msg = msg.split("LIMIT_EXCEEDED:").last;
        } else {
          msg = "同步失败: 获取数据异常";
        }
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(msg), backgroundColor: Colors.redAccent));
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSyncing = false;
        });
      }
      // 🚀 同步完成后清除保护，防止后续加载被干扰
      _pendingTodosToPersist = null;
      _persistingTodosSnapshot = null;
      StorageService.setForceFlushProtectedUuids({});
    }
  }

  /// 🚀 Uni-Sync 4.0: 链路可视化诊断报告
  Future<void> _showLinkDiagnostics() async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: Row(
              children: [
                const Icon(Icons.analytics_outlined, color: Colors.blueAccent),
                const SizedBox(width: 10),
                const Text("链路诊断报告",
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ],
            ),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            content: SizedBox(
              width: double.maxFinite,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildDiagnosticItem("核心 API 服务", ApiService.ping()),
                  _buildDiagnosticItem(
                      "实时同步通道",
                      Future.value(
                          PomodoroSyncService.instance.connectionState ==
                              SyncConnectionState.connected)),
                  _buildDiagnosticItem(
                      "增量引擎状态", Future.value(true)), // 逻辑始终为真，仅展示
                  const Divider(height: 32),
                  _buildEnvironmentInfo(),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text("关闭"),
              ),
              FilledButton.tonalIcon(
                onPressed: () {
                  Navigator.pop(context);
                  _handleManualSync(silent: false);
                },
                icon: const Icon(Icons.sync, size: 18),
                label: const Text("强制同步数据"),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildDiagnosticItem(String label, Future<bool> checkFuture) {
    return FutureBuilder<bool>(
      future: checkFuture,
      builder: (context, snapshot) {
        bool? isOk = snapshot.data;
        bool isLoading = snapshot.connectionState == ConnectionState.waiting;

        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              SizedBox(
                width: 20,
                height: 20,
                child: isLoading
                    ? const CircularProgressIndicator(strokeWidth: 2)
                    : Icon(
                        isOk == true ? Icons.check_circle : Icons.error,
                        size: 20,
                        color: isOk == true ? Colors.green : Colors.redAccent,
                      ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label,
                        style: const TextStyle(fontWeight: FontWeight.w500)),
                    if (!isLoading)
                      Text(
                        isOk == true ? "服务运行正常" : "连接受阻，部分功能受限",
                        style: TextStyle(
                            fontSize: 11,
                            color: isOk == true
                                ? Colors.grey
                                : Colors.redAccent.withValues(alpha: 0.8)),
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildEnvironmentInfo() {
    final isTest = ApiService.baseUrl.contains(':8084');
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          const SizedBox(height: 4),
          _buildInfoRow(
              "当前接入点", isTest ? "Aliyun (Test Node)" : "Aliyun (Global Node)"),
          const SizedBox(height: 4),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey)),
        Text(value,
            style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: Colors.blueGrey)),
      ],
    );
  }

  void _showSyncOptionsDialog() {
    bool syncTodos = true;
    bool syncCountdowns = true;
    bool syncScreenTime = true;
    bool syncPomodoro = true;
    bool syncTimeLogs = true;
    bool syncPlanBlocks = true;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (context, setDialogState) {
        return AlertDialog(
          title:
              const Text("手动同步", style: TextStyle(fontWeight: FontWeight.bold)),
          content: SingleChildScrollView(
            // 加入滚动防止选项过多溢出屏幕
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("请勾选你需要同步的数据模块：",
                    style: TextStyle(fontSize: 13, color: Colors.grey)),
                const SizedBox(height: 12),
                CheckboxListTile(
                  title: const Text("待办事项"),
                  value: syncTodos,
                  onChanged: (val) =>
                      setDialogState(() => syncTodos = val ?? false),
                ),
                CheckboxListTile(
                  title: const Text("重要日与倒计时"),
                  value: syncCountdowns,
                  onChanged: (val) =>
                      setDialogState(() => syncCountdowns = val ?? false),
                ),
                CheckboxListTile(
                  title: const Text("屏幕使用时间"),
                  value: syncScreenTime,
                  onChanged: (val) =>
                      setDialogState(() => syncScreenTime = val ?? false),
                ),
                CheckboxListTile(
                  title: const Text("番茄钟记录"),
                  value: syncPomodoro,
                  onChanged: (val) =>
                      setDialogState(() => syncPomodoro = val ?? false),
                ),
                CheckboxListTile(
                  title: const Text("时间日志 (补录)"),
                  value: syncTimeLogs,
                  onChanged: (val) =>
                      setDialogState(() => syncTimeLogs = val ?? false),
                ),
                CheckboxListTile(
                  title: const Text("今日规划"),
                  value: syncPlanBlocks,
                  onChanged: (val) =>
                      setDialogState(() => syncPlanBlocks = val ?? false),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx), child: const Text("取消")),
            FilledButton(
              // 🚀 3. 按钮启用条件加入 syncTimeLogs
              onPressed: (syncTodos ||
                      syncCountdowns ||
                      syncScreenTime ||
                      syncPomodoro ||
                      syncTimeLogs ||
                      syncPlanBlocks)
                  ? () {
                      Navigator.pop(ctx);
                      _handleManualSync(
                        silent: false,
                        syncTodos: syncTodos,
                        syncCountdowns: syncCountdowns,
                        syncScreenTime: syncScreenTime,
                        syncPomodoro: syncPomodoro,
                        syncTimeLogs: syncTimeLogs,
                        syncPlanBlocks: syncPlanBlocks,
                      );
                    }
                  : null,
              child: const Text("开始同步"),
            ),
          ],
        );
      }),
    );
  }

  // --- Wallpaper Fallback Logic ---
  int _wallpaperRetryCount = 0;
  List<String> _randomWallpaperUrls = [];
  bool _isWallpaperLoadingError = false;

  void _handleWallpaperError() {
    if (!mounted || _isWallpaperLoadingError) return;
    debugPrint(
        "[Wallpaper] Current URL failed: $_wallpaperUrl. Trying fallback...");

    setState(() {
      _wallpaperRetryCount++;
    });

    _triggerNextWallpaperFallback();
  }

  Future<void> _triggerNextWallpaperFallback() async {
    // Priority: Manifest -> Bing -> Random List -> Asset Fallback -> None
    final prefs = await SharedPreferences.getInstance();
    final provider = prefs.getString('wallpaper_provider') ?? 'bing';

    if (_wallpaperRetryCount == 1) {
      // If manifest failed (or was first), try provider
      if (provider == 'bing') {
        _fetchBingWallpaper(isFallback: true);
      } else {
        _fetchRandomWallpaper(isFallback: true);
      }
    } else if (_wallpaperRetryCount == 2) {
      // If provider failed, try random (if not already tried)
      if (provider == 'bing') {
        _fetchRandomWallpaper(isFallback: true);
      } else {
        _tryAnotherRandomWallpaper();
      }
    } else if (_wallpaperRetryCount >= 3 && _wallpaperRetryCount < 6) {
      // Keep trying randoms a few times
      _tryAnotherRandomWallpaper();
    } else if (_wallpaperRetryCount == 6) {
      // 🚀 Final Fallback: Local Asset
      debugPrint("[Wallpaper] Using local asset fallback.");
      if (mounted) {
        setState(() {
          _wallpaperUrl = 'assets/images/default_wallpaper.png';
          _isWallpaperLoadingError = false; // Reset to allow this to show
        });
      }
    } else {
      // Total failure
      debugPrint("[Wallpaper] All fallbacks exhausted. Disabling wallpaper.");
      if (mounted) {
        setState(() {
          _wallpaperShow = false;
          _isWallpaperLoadingError = true;
        });
      }
    }
  }

  void _tryAnotherRandomWallpaper() {
    if (_randomWallpaperUrls.isNotEmpty) {
      final nextUrl =
          _randomWallpaperUrls[Random().nextInt(_randomWallpaperUrls.length)];
      if (mounted) {
        setState(() {
          _wallpaperUrl = nextUrl;
        });
      }
    } else {
      _fetchRandomWallpaper(isFallback: true);
    }
  }

  Future<void> _fetchBingWallpaper({bool isFallback = false}) async {
    final format = await StorageService.getWallpaperImageFormat();
    final index = await StorageService.getWallpaperIndex();
    final mkt = await StorageService.getWallpaperMkt();
    final resolution = await StorageService.getWallpaperResolution();

    final String bingApiUrl =
        "https://bing.biturl.top/?resolution=$resolution&format=json&index=$index&mkt=$mkt&image_format=$format";
    try {
      final response = await http.get(Uri.parse(bingApiUrl));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final String? url = data['url'];
        final String? copyright = data['copyright'];
        if (url != null && url.isNotEmpty && mounted) {
          setState(() {
            _wallpaperShow = true;
            _wallpaperUrl = url;
            _wallpaperCopyright = copyright;
          });
        }
      } else {
        // 失败兜底
        _fetchRandomWallpaper();
      }
    } catch (e) {
      debugPrint("获取Bing壁纸失败: $e");
      if (!isFallback) _fetchRandomWallpaper();
    }
  }

  Future<void> _initManifestWallpaper() async {
    await WallpaperCacheService.cleanupIfNeeded();
    await UpdateService.initWallpaper();
    final manifestShow = UpdateService.wallpaperShowNotifier.value;
    final manifestUrl = UpdateService.wallpaperUrlNotifier.value;

    if (manifestShow && manifestUrl != null && manifestUrl.isNotEmpty) {
      setState(() {
        _wallpaperShow = true;
        _wallpaperUrl = manifestUrl;
        _wallpaperRetryCount = 0;
        _isWallpaperLoadingError = false;
      });
    } else {
      final provider = await StorageService.getWallpaperProvider();
      if (provider == 'bing') {
        await _fetchBingWallpaper();
      } else {
        await _fetchRandomWallpaper();
      }
    }

    // 启动时立即检查是否需要兜底刷新
    if (await UpdateService.needsWallpaperRefresh()) {
      UpdateService.updateWallpaperFromManifest();
    }

    UpdateService.wallpaperShowNotifier.addListener(() {
      if (mounted) {
        final show = UpdateService.wallpaperShowNotifier.value;
        final url = UpdateService.wallpaperUrlNotifier.value;
        if (show && url != null && url.isNotEmpty) {
          setState(() {
            _wallpaperShow = true;
            _wallpaperUrl = url;
            _wallpaperRetryCount = 0; // Reset on manual/auto update
            _isWallpaperLoadingError = false;
          });
        } else if (mounted) {
          StorageService.getWallpaperProvider().then((provider) {
            if (provider == 'bing') {
              _fetchBingWallpaper();
            } else {
              _fetchRandomWallpaper();
            }
          });
        }
      }
    });
    UpdateService.wallpaperUrlNotifier.addListener(() {
      if (mounted) {
        final show = UpdateService.wallpaperShowNotifier.value;
        final url = UpdateService.wallpaperUrlNotifier.value;
        if (show && url != null && url.isNotEmpty) {
          setState(() {
            _wallpaperShow = true;
            _wallpaperUrl = url;
          });
        }
      }
    });
  }

  Future<void> _fetchRandomWallpaper({bool isFallback = false}) async {
    const String repoApiUrl =
        "https://api.github.com/repos/Junpgle/math_quiz_app/contents/wallpaper";
    try {
      final response = await http.get(Uri.parse(repoApiUrl));
      if (response.statusCode == 200) {
        List<dynamic> files = jsonDecode(response.body);
        List<String> urls = files
            .where((f) =>
                f['name'].toString().toLowerCase().endsWith('.jpg') ||
                f['name'].toString().toLowerCase().endsWith('.png'))
            .map((f) => f['download_url'].toString())
            .toList();
        if (urls.isNotEmpty && mounted) {
          _randomWallpaperUrls = urls;
          setState(() {
            _wallpaperShow = true;
            _wallpaperUrl = urls[Random().nextInt(urls.length)];
          });
        }
      }
    } catch (e) {
      debugPrint("获取壁纸失败: $e");
    }
  }

  Widget _buildSemesterProgressBar(bool isLight) {
    if (!_semesterEnabled || _semesterStart == null || _semesterEnd == null) {
      return const SizedBox.shrink();
    }

    double progress = _calculateSemesterProgress();

    return Container(
      width: double.infinity,
      height: 4.0,
      alignment: Alignment.centerLeft,
      child: FractionallySizedBox(
        widthFactor: progress,
        child: Container(
          decoration: BoxDecoration(
            color: isLight
                ? Colors.lightBlueAccent
                : Theme.of(context).colorScheme.primary,
            boxShadow: [
              if (progress > 0)
                BoxShadow(
                  color: (isLight
                          ? Colors.lightBlueAccent
                          : Theme.of(context).colorScheme.primary)
                      .withValues(alpha: 0.5),
                  blurRadius: 4,
                  offset: const Offset(0, 1),
                )
            ],
          ),
        ),
      ),
    );
  }

  bool _isSearchOpen = false; // 🚀 记录搜索层是否打开

  void _showGlobalSearch() {
    PageTransitions.pushFromRect(
      context: context,
      page: const GlobalSearchOverlay(),
      sourceKey: _searchButtonKey,
    ).then((_) async {
      // 🚀 延迟 200ms 恢复，确保键盘收起后再允许背景重排，彻底消除跳变
      await Future.delayed(const Duration(milliseconds: 200));
      if (mounted) {
        setState(() {
          _isSearchOpen = false;
          _timelineRefreshTriggerNotifier.value++; // 🚀 搜索完成后刷新时间轴（记录搜索历史）
        });
      }
      _loadAllData(deferred: true);
    });
  }

  @override
  Widget build(BuildContext context) {
    bool isDarkMode = Theme.of(context).brightness == Brightness.dark;
    bool showWallpaper = !isDarkMode && _wallpaperShow && _wallpaperUrl != null;
    bool isLight = showWallpaper;
    final bool isTablet = MediaQuery.of(context).size.width >= 768;

    return Scaffold(
      extendBody: true,
      resizeToAvoidBottomInset: !_isSearchOpen, // 🚀 关键：搜索时锁定背景，防止位移卡顿
      backgroundColor: (showWallpaper && !Platform.isWindows)
          ? Colors.transparent
          : Theme.of(context).colorScheme.surface,
      body: Stack(
        children: [
          if (showWallpaper)
            Positioned.fill(
              child: _wallpaperUrl!.startsWith('assets/')
                  ? Image.asset(
                      _wallpaperUrl!,
                      fit: BoxFit.cover,
                    )
                  : CachedNetworkImage(
                      cacheManager: WallpaperCacheService.cacheManager,
                      imageUrl: _wallpaperUrl!,
                      fit: BoxFit.cover,
                      memCacheWidth: 1080,
                      maxWidthDiskCache: 1920,
                      fadeInDuration: const Duration(milliseconds: 800),
                      imageBuilder: (context, imageProvider) {
                        // 🚀 成功加载网络图片后，重置重试计数
                        _wallpaperRetryCount = 0;
                        return Container(
                          decoration: BoxDecoration(
                            image: DecorationImage(
                              image: imageProvider,
                              fit: BoxFit.cover,
                            ),
                          ),
                        );
                      },
                      placeholder: (context, url) => Image.asset(
                        'assets/images/default_wallpaper.png',
                        fit: BoxFit.cover,
                      ),
                      errorWidget: (context, url, error) {
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          _handleWallpaperError();
                        });
                        return Image.asset(
                          'assets/images/default_wallpaper.png',
                          fit: BoxFit.cover,
                        );
                      },
                    ),
            ),
          if (showWallpaper)
            Positioned.fill(
                child: Container(color: Colors.black.withValues(alpha: 0.4))),
          SafeArea(
            child: Column(
              children: [
                _buildSemesterProgressBar(isLight),

                if (_selectedTabIndex != 1 || isTablet)
                  HomeAppBar(
                    username: widget.username,
                    timeSalutation: _timeSalutation,
                    currentGreeting: _currentGreeting,
                    isLight: isLight,
                    isSyncing: _isSyncing,
                    onSync: _showSyncOptionsDialog,
                    onSearch: _showGlobalSearch,
                    onAiAssistant: _openAiAssistantFromAppBar,
                    searchKey: _searchButtonKey,
                    teamsKey: _teamsButtonKey,
                    aiKey: _aiButtonKey,
                    settingsKey: _settingsButtonKey,
                    courseKey: _courseButtonKey,
                    showCourseButton: isTablet,
                    teamPendingCount: _teamPendingCount, // 🚀 绑定计数
                    hasTeamConflictDot: _hasTeamConflictDot,
                    onTeams: () async {
                      await PageTransitions.pushFromRect(
                        context: context,
                        page: TeamManagementScreen(username: widget.username),
                        sourceKey: _teamsButtonKey,
                      );
                      final unreadBackgroundNotifications =
                          await BackgroundNotificationService
                              .getUnreadBackgroundNotifications();
                      final notificationIds = unreadBackgroundNotifications
                          .map((e) => e['id'])
                          .whereType<num>()
                          .map((e) => e.toInt())
                          .toList();
                      await ApiService.markNotificationsRead(notificationIds);
                      await BackgroundNotificationService
                          .clearUnreadBackgroundNotifications();
                      await _fetchTeamPendingCount();
                      _loadAllData(deferred: true);
                    },
                    onSettings: () async {
                      await PageTransitions.pushFromRect(
                        context: context,
                        page: const SettingsPage(),
                        sourceKey: _settingsButtonKey,
                      );
                      _loadSectionPreferences();
                      _loadSemesterSettings();
                      _loadAllData(deferred: true);
                    },
                  ),

                // 🚀 Uni-Sync 4.0: 全局链路诊断横幅
                if (_selectedTabIndex != 1 || isTablet)
                  SyncStatusBanner(
                    onDiagnosticRequested: _showLinkDiagnostics,
                  ),

                // DEBUG: 检查状态
                // if (_activeAnnouncement != null) Text("DEBUG: Announcement exists: ${_activeAnnouncement!.title}"),

                // 🚀 Uni-Sync 4.0: 团队置顶公告
                if (_activeAnnouncement != null &&
                    (_selectedTabIndex != 1 || isTablet))
                  StickyAnnouncementBanner(
                    announcement: _activeAnnouncement!,
                    onAcknowledge: () async {
                      final uuid = _activeAnnouncement!.uuid;
                      setState(() => _activeAnnouncement = null);
                      await ApiService.markAnnouncementAsRead(uuid);
                    },
                  ),

                // 待确认待办入口卡片（从图片识别来）
                _buildPendingTodoConfirmCard(isLight),

                Expanded(
                  child: ValueListenableBuilder<bool>(
                    valueListenable: _isGlobalLoadingNotifier,
                    builder: (context, isLoading, child) {
                      // 🚀 核心优化：只有当数据完全为空且正在加载时才显示骨架屏，避免背景刷新时的闪烁
                      return Stack(
                        children: [
                          (isLoading &&
                                  _todos.isEmpty &&
                                  (_dashboardCourseData['courses'] as List? ??
                                          [])
                                      .isEmpty)
                              ? _buildDashboardSkeleton(isLight)
                              : LayoutBuilder(
                                  builder: (context, constraints) {
                                    // ... (rest of section definitions)
                                    Widget courseSection =
                                        ValueListenableBuilder<int>(
                                      valueListenable:
                                          _timelineRefreshTriggerNotifier,
                                      builder: (context, trigger, _) {
                                        return CourseSectionWidget(
                                          dashboardCourseData:
                                              _dashboardCourseData,
                                          todos: _todos,
                                          isLight: isLight,
                                          username: widget.username,
                                          refreshTrigger: trigger,
                                        );
                                      },
                                    );
                                    Widget countdownSection =
                                        CountdownSectionWidget(
                                            countdowns: _countdowns,
                                            username: widget.username,
                                            isLight: isLight,
                                            onDataChanged: () {
                                              _loadAllData();
                                              _timelineRefreshTriggerNotifier
                                                  .value++;
                                            });
                                    Widget todoSection =
                                        ValueListenableBuilder<int>(
                                      valueListenable:
                                          _todoUpdateSignalNotifier,
                                      builder: (context, signal, _) {
                                        return TodoSectionWidget(
                                          todos: _todos,
                                          highlightedTodoIds:
                                              _updatedByOthersTodoIds,
                                          remoteUpdateHighlightSignal:
                                              _remoteTodoHighlightSignal,
                                          todoGroups: _todoGroups,
                                          conflicts: _latestSyncConflicts,
                                          username: widget.username,
                                          isLight: isLight,
                                          onTeamChanged: (teamUuid, teamName) {
                                            setState(() {
                                              _currentSelectedTeamUuid =
                                                  teamUuid;
                                              _currentSelectedTeamName =
                                                  teamName;
                                            });
                                          },
                                          onGroupsChanged: (newGroups) async {
                                            setState(() => _todoGroups =
                                                newGroups
                                                    .where((g) => !g.isDeleted)
                                                    .toList());
                                            final allGroups =
                                                await StorageService
                                                    .getTodoGroups(
                                                        widget.username);
                                            for (var g in newGroups) {
                                              int idx = allGroups.indexWhere(
                                                  (x) => x.id == g.id);
                                              if (idx != -1) {
                                                if (g.updatedAt >=
                                                    allGroups[idx].updatedAt) {
                                                  allGroups[idx] = g;
                                                }
                                              } else {
                                                allGroups.add(g);
                                              }
                                            }
                                            await StorageService.saveTodoGroups(
                                                widget.username, allGroups,
                                                sync: true);
                                          },
                                          onTodosChanged: _handleTodosChanged,
                                          initialSelectedTeamUuid:
                                              _currentSelectedTeamUuid,
                                          onRefreshRequested: _handleManualSync,
                                          onLLMResultsParsed: (results,
                                              imagePath,
                                              originalText,
                                              tUuid,
                                              tName) {
                                            _navigateToTodoConfirm(
                                                results,
                                                imagePath,
                                                originalText,
                                                tUuid,
                                                tName);
                                          },
                                        );
                                      },
                                    );
                                    Widget screenTimeSection = RepaintBoundary(
                                      child: KeyedSubtree(
                                        key: _screenTimeCardKey,
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            SectionHeader(
                                                title: "屏幕时间 (今日汇总)",
                                                icon: Icons.timer_outlined,
                                                isLight: isLight),
                                            ScreenTimeCard(
                                              stats: _screenTimeStats,
                                              hasPermission:
                                                  _hasUsagePermission,
                                              isLoading: _isLoadingScreenTime,
                                              lastSyncTime: _lastScreenTimeSync,
                                              onOpenSettings: () async {
                                                if (Platform.isAndroid ||
                                                    Platform.isIOS) {
                                                  await ScreenTimeService
                                                      .openSettings();
                                                }
                                                _initScreenTime();
                                              },
                                              onViewDetail: () {
                                                PageTransitions.pushFromRect(
                                                  context: context,
                                                  page: ScreenTimeDetailScreen(
                                                      todayStats:
                                                          _screenTimeStats),
                                                  sourceKey: _screenTimeCardKey,
                                                );
                                              },
                                            ),
                                          ],
                                        ),
                                      ),
                                    );
                                    Widget mathSection = RepaintBoundary(
                                      child: KeyedSubtree(
                                        key: _mathCardKey,
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            SectionHeader(
                                                title: "数学测验",
                                                icon: Icons.functions,
                                                isLight: isLight),
                                            MathStatsCard(
                                                stats: _mathStats,
                                                onTap: () async {
                                                  await PageTransitions
                                                      .pushFromRect(
                                                    context: context,
                                                    page: MathMenuScreen(
                                                        username:
                                                            widget.username),
                                                    sourceKey: _mathCardKey,
                                                  );
                                                  _loadAllData(deferred: true);
                                                }),
                                          ],
                                        ),
                                      ),
                                    );
                                    Widget timelineSection =
                                        ValueListenableBuilder<int>(
                                      valueListenable:
                                          _timelineRefreshTriggerNotifier,
                                      builder: (context, trigger, _) {
                                        return PersonalTimelineSection(
                                          username: widget.username,
                                          isLight: isLight,
                                          refreshTrigger: trigger,
                                        );
                                      },
                                    );

                                    Widget pomodoroSection = RepaintBoundary(
                                      child: ValueListenableBuilder<int>(
                                        valueListenable:
                                            _timelineRefreshTriggerNotifier,
                                        builder: (context, trigger, _) {
                                          return KeyedSubtree(
                                            key: _pomodoroCardKey,
                                            child: PomodoroTodaySection(
                                              username: widget.username,
                                              isLight: isLight,
                                              refreshTrigger: trigger,
                                              onTap: () async {
                                                await PageTransitions
                                                    .pushFromRect(
                                                  context: context,
                                                  page: PomodoroScreen(
                                                    username: widget.username,
                                                    initialTab: 1,
                                                  ),
                                                  sourceKey: _pomodoroCardKey,
                                                );
                                                _timelineRefreshTriggerNotifier
                                                    .value++;
                                                _loadAllData();
                                              },
                                            ),
                                          );
                                        },
                                      ),
                                    );

                                    Widget planBlockSection = RepaintBoundary(
                                      child: ValueListenableBuilder<int>(
                                        valueListenable:
                                            _timelineRefreshTriggerNotifier,
                                        builder: (context, trigger, _) {
                                          return PlanBlockTodaySection(
                                            username: widget.username,
                                            isLight: isLight,
                                            refreshTrigger: trigger,
                                            onTap: () async {
                                              await Navigator.of(context).push(
                                                MaterialPageRoute(
                                                  builder: (_) =>
                                                      TodoPlanScreen(
                                                          username:
                                                              widget.username),
                                                ),
                                              );
                                              _timelineRefreshTriggerNotifier
                                                  .value++;
                                              _loadAllData();
                                            },
                                          );
                                        },
                                      ),
                                    );

                                    Map<String, Widget> sectionsMap = {
                                      'banners': ValueListenableBuilder<int>(
                                        valueListenable: _pomodoroTickNotifier,
                                        builder: (_, __, ___) => _buildUniversalBanner(isLight),
                                      ),
                                      'courses': courseSection,
                                      'countdowns': countdownSection,
                                      'todos': todoSection,
                                      'planBlocks': planBlockSection,
                                      'screenTime': screenTimeSection,
                                      'math': mathSection,
                                      'pomodoro': pomodoroSection,
                                      'timeline': timelineSection,
                                    };

                                    bool hasNoCourse =
                                        (_dashboardCourseData['courses'] ==
                                                null ||
                                            (_dashboardCourseData['courses']
                                                    as List)
                                                .isEmpty);

                                    if (!isTablet) {
                                      List<String> tab1Order = [
                                        'banners',
                                        'countdowns',
                                        'courses',
                                        'todos',
                                      ];
                                      if (hasNoCourse) {
                                        if (_noCourseBehavior == 'hide') {
                                          tab1Order.remove('courses');
                                        } else if (_noCourseBehavior ==
                                            'bottom') {
                                          tab1Order.remove('courses');
                                          tab1Order.add('courses');
                                        }
                                      }

                                      List<Widget> tab1Widgets = tab1Order
                                          .where((key) =>
                                              (_sectionVisibility[key] ??
                                                  true) &&
                                              sectionsMap.containsKey(key))
                                          .map((key) => Padding(
                                              padding: const EdgeInsets.only(
                                                  bottom: 24.0),
                                              child: sectionsMap[key]!))
                                          .toList();

                                      List<Widget> tab3Widgets = [
                                        'timeline',
                                        'pomodoro',
                                        'screenTime',
                                        'math'
                                      ]
                                          .where((key) =>
                                              (_sectionVisibility[key] ??
                                                  true) &&
                                              sectionsMap.containsKey(key))
                                          .map((key) => Padding(
                                              padding: const EdgeInsets.only(
                                                  bottom: 24.0),
                                              child: sectionsMap[key]!))
                                          .toList();

                                      return IndexedStack(
                                        index: _selectedTabIndex == 2 ? 1 : 0,
                                        children: [
                                          // Tab 1: 重要日、课程、待办
                                          RepaintBoundary(
                                            child: SingleChildScrollView(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 16,
                                                      vertical: 16),
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  ...tab1Widgets,
                                                  if (_wallpaperCopyright !=
                                                          null &&
                                                      _wallpaperCopyright!
                                                          .isNotEmpty)
                                                    _buildWallpaperCopyright(
                                                        isLight),
                                                  const SizedBox(
                                                      height: 100), // 为悬浮底栏留出空间
                                                ],
                                              ),
                                            ),
                                          ),
                                          // Tab 2 (mapped to index 2 in bottom bar): 今日专注、屏幕时间
                                          RepaintBoundary(
                                            child: SingleChildScrollView(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 16,
                                                      vertical: 16),
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  ...tab3Widgets,
                                                  if (_wallpaperCopyright !=
                                                          null &&
                                                      _wallpaperCopyright!
                                                          .isNotEmpty)
                                                    _buildWallpaperCopyright(
                                                        isLight),
                                                  const SizedBox(
                                                      height: 100), // 为悬浮底栏留出空间
                                                ],
                                              ),
                                            ),
                                          ),
                                        ],
                                      );
                                    }

                                    // Tablet Layout
                                    List<String> currentLeft =
                                        List.from(_leftSections);
                                    List<String> currentRight =
                                        List.from(_rightSections);

                                    void applyNoCourseBehavior(
                                        List<String> targetList) {
                                      if (hasNoCourse &&
                                          targetList.contains('courses')) {
                                        if (_noCourseBehavior == 'hide') {
                                          targetList.remove('courses');
                                        } else if (_noCourseBehavior ==
                                            'bottom') {
                                          targetList.remove('courses');
                                          targetList.add('courses');
                                        }
                                      }
                                    }

                                    applyNoCourseBehavior(currentLeft);
                                    applyNoCourseBehavior(currentRight);

                                    List<Widget> buildColumnWidgets(
                                        List<String> keys) {
                                      return keys
                                          .where((key) =>
                                              (_sectionVisibility[key] ??
                                                  true) &&
                                              sectionsMap.containsKey(key))
                                          .map((key) => Padding(
                                              padding: const EdgeInsets.only(
                                                  bottom: 24.0),
                                              child: sectionsMap[key]!))
                                          .toList();
                                    }

                                    List<Widget> leftWidgets =
                                        buildColumnWidgets(currentLeft);
                                    List<Widget> rightWidgets =
                                        buildColumnWidgets(currentRight);

                                    return SingleChildScrollView(
                                      padding: EdgeInsets.symmetric(
                                          horizontal: isTablet ? 32 : 16,
                                          vertical: 16),
                                      child: Align(
                                        alignment: Alignment.topCenter,
                                        child: ConstrainedBox(
                                          constraints: const BoxConstraints(
                                              maxWidth: 1400),
                                          child: Column(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              isTablet
                                                  ? Row(
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .start,
                                                      children: [
                                                        Expanded(
                                                            flex: 10,
                                                            child: Column(
                                                                crossAxisAlignment:
                                                                    CrossAxisAlignment
                                                                        .start,
                                                                children:
                                                                    leftWidgets)),
                                                        if (rightWidgets
                                                            .isNotEmpty)
                                                          const SizedBox(
                                                              width: 40),
                                                        if (rightWidgets
                                                            .isNotEmpty)
                                                          Expanded(
                                                              flex: 11,
                                                              child: Column(
                                                                  crossAxisAlignment:
                                                                      CrossAxisAlignment
                                                                          .start,
                                                                  children:
                                                                      rightWidgets)),
                                                      ],
                                                    )
                                                  : Column(
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .start,
                                                      children: [
                                                        ...leftWidgets,
                                                        ...rightWidgets,
                                                      ],
                                                    ),
                                              if (_wallpaperCopyright != null &&
                                                  _wallpaperCopyright!
                                                      .isNotEmpty)
                                                Center(
                                                  child: Padding(
                                                    padding:
                                                        const EdgeInsets.only(
                                                            top: 16.0,
                                                            bottom: 32.0),
                                                    child: Text(
                                                      _wallpaperCopyright!,
                                                      style: TextStyle(
                                                        fontSize: 12,
                                                        color: isLight
                                                            ? Colors.white
                                                                .withValues(
                                                                    alpha: 0.7)
                                                            : Colors.grey[600],
                                                        fontStyle:
                                                            FontStyle.italic,
                                                      ),
                                                      textAlign:
                                                          TextAlign.center,
                                                    ),
                                                  ),
                                                ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                                ),
                          // 🚀 移动端底部悬浮胶囊底栏 (始终显示，不受加载状态影响)
                          if (!isTablet)
                            Positioned(
                              left: 0,
                              right: 0,
                              bottom: 0,
                              child: _buildCustomBottomBar(isDarkMode, isLight),
                            ),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: null,
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          FloatingActionButton.small(
            key: _fabPomodoroKey,
            heroTag: 'fab_pomodoro',
            onPressed: () async {
              await PageTransitions.pushFromRect(
                context: context,
                page: PomodoroScreen(username: widget.username),
                sourceKey: _fabPomodoroKey,
                sourceBorderRadius: const BorderRadius.all(Radius.circular(16)),
              );
              if (mounted) {
                _timelineRefreshTriggerNotifier.value++;
                _loadAllData(deferred: true);
              }
            },
            tooltip: '番茄钟',
            child: const Text('🍅', style: TextStyle(fontSize: 18)),
          ),
          const SizedBox(height: 8),
          FloatingActionButton.extended(
            key: _fabTodoKey,
            heroTag: 'fab_todo',
            onPressed: () => PageTransitions.pushFromRect(
              context: context,
              page: AddTodoScreen(
                todoGroups: _todoGroups,
                initialTeamUuid:
                    _currentSelectedTeamUuid, // 🚀 关键修复：将当前选中的团队 Tab 传给创建页
                initialTeamName: _currentSelectedTeamName,
                onTodoAdded: (todo) async {
                  final allTodos =
                      await StorageService.getTodos(widget.username);
                  allTodos.add(todo);
                  await StorageService.saveTodos(widget.username, allTodos);
                  // 🚀 协作实时化：发送更新信号
                  if (todo.teamUuid != null) {
                    PomodoroSyncService.instance
                        .sendTeamUpdateSignal(todo.teamUuid);
                  }
                  await _saveTodosToSharedFile(allTodos);
                  FloatWindowService.triggerReminderCheck();
                  FloatWindowService.invalidateSlotCache();
                  _syncTodoNotification();
                  _rescheduleAlarms();
                  await WidgetService.updateTodoWidget(allTodos);
                  if (mounted) {
                    await _loadAllData(deferred: true);
                    // 🧪 额外加固：确保 UI 刷新
                    setState(() {});
                  }
                },
                onTodosBatchAdded: (todos) async {
                  final allTodos =
                      await StorageService.getTodos(widget.username);
                  allTodos.addAll(todos);
                  await StorageService.saveTodos(widget.username, allTodos);
                  // 🚀 协作实时化：发送更新信号
                  final updatedTeamUuid = todos
                      .firstWhere((t) => t.teamUuid != null,
                          orElse: () => todos.first)
                      .teamUuid;
                  if (updatedTeamUuid != null) {
                    PomodoroSyncService.instance
                        .sendTeamUpdateSignal(updatedTeamUuid);
                  }
                  await _saveTodosToSharedFile(allTodos);
                  FloatWindowService.triggerReminderCheck();
                  FloatWindowService.invalidateSlotCache();
                  _syncTodoNotification();
                  _rescheduleAlarms();
                  await WidgetService.updateTodoWidget(allTodos);
                  if (mounted) await _loadAllData(deferred: true);
                },
                onLLMResultsParsed:
                    (results, imagePath, originalText, tUuid, tName) {
                  Navigator.pop(context); // 关闭添加页面
                  _navigateToTodoConfirm(
                      results, imagePath, originalText, tUuid, tName);
                },
              ),
              sourceKey: _fabTodoKey,
              sourceBorderRadius: const BorderRadius.all(Radius.circular(16)),
            ),
            icon: const Icon(Icons.add_task),
            label: const Text("记待办"),
          ),
          const SizedBox(height: 100), // 🚀 关键：将 FAB 抬高，避开下方的悬浮底栏
        ],
      ),
    );
  }

  Widget _buildWallpaperCopyright(bool isLight) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.only(top: 16.0, bottom: 32.0),
        child: Text(
          _wallpaperCopyright!,
          style: TextStyle(
            fontSize: 12,
            color: isLight
                ? Colors.white.withValues(alpha: 0.7)
                : Colors.grey[600],
            fontStyle: FontStyle.italic,
          ),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }

  Widget _buildCustomBottomBar(bool isDarkMode, bool isLight) {
    final Color primaryColor = Theme.of(context).colorScheme.primary;
    final Color inactiveColor =
        (isLight || !isDarkMode) ? Colors.black45 : Colors.white54;
    final double bottomPadding = MediaQuery.of(context).padding.bottom;

    return Container(
      height: 54 + (bottomPadding > 0 ? bottomPadding * 0.5 : 6), // 进一步压缩高度
      margin: const EdgeInsets.fromLTRB(40, 0, 40, 12), // 增加左右间距以减小宽度
      decoration: BoxDecoration(
        color: isDarkMode
            ? Colors.black.withValues(alpha: 0.4)
            : Colors.white.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(40), // 更圆润的边缘
        border: Border.all(
          color: isDarkMode
              ? Colors.white.withValues(alpha: 0.05)
              : Colors.white.withValues(alpha: 0.2),
          width: 0.5,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(40),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Expanded(
                  child: _buildTabItem(0, Icons.dashboard_rounded, '首页',
                      primaryColor, inactiveColor),
                ),
                SizedBox(
                  width: 64,
                  child: Center(child: _buildCourseCenterButton(primaryColor)),
                ),
                Expanded(
                  child: _buildTabItem(2, Icons.adjust_rounded, '专注',
                      primaryColor, inactiveColor),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTabItem(
      int index, IconData icon, String label, Color primary, Color inactive) {
    bool isSelected = _selectedTabIndex == index;
    return InkWell(
      onTap: () => setState(() => _selectedTabIndex = index),
      splashColor: Colors.transparent,
      highlightColor: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: isSelected ? primary : inactive,
              size: 22, // 缩小图标
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? primary : inactive,
                fontSize: 9, // 缩小文字
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCourseCenterButton(Color primary) {
    return SizedBox(
      width: 48,
      height: 48,
      child: InkWell(
        onTap: () {
          PageTransitions.pushFromRect(
            context: context,
            page: WeeklyCourseScreen(username: widget.username),
            sourceKey: _courseCenterKey,
          );
        },
        borderRadius: BorderRadius.circular(24),
        child: Container(
          key: _courseCenterKey,
          decoration: BoxDecoration(
            color: primary,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: primary.withValues(alpha: 0.3),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: const Icon(
            Icons.calendar_today_rounded,
            color: Colors.white,
            size: 22,
          ),
        ),
      ),
    );
  }

  // 🚀 辅助方法：内容级深度比较，用于按需刷新
  bool _isListEqual(List a, List b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  bool _isMapEqual(Map a, Map b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (final key in a.keys) {
      if (!b.containsKey(key) || a[key] != b[key]) return false;
    }
    return true;
  }

  Widget _buildDashboardSkeleton(bool isLight) {
    final baseColor =
        isLight ? Colors.white.withValues(alpha: 0.3) : Colors.grey[800]!;
    return SingleChildScrollView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          _buildSkeletonCard(baseColor, height: 120),
          const SizedBox(height: 16),
          _buildSkeletonCard(baseColor, height: 180),
          const SizedBox(height: 16),
          _buildSkeletonCard(baseColor, height: 240),
        ],
      ),
    );
  }

  Widget _buildSkeletonCard(Color color, {required double height}) {
    return Container(
      width: double.infinity,
      height: height,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(16),
      ),
    );
  }
}

/// 🚀 首页 Banner 事件模型
class HomeBannerEvent {
  final String
      type; // 'pomodoro', 'course', 'todo', 'special_todo', 'plan_block'
  final String title;
  final String? subtitle; // 地点或备注
  final String label; // e.g. "正在进行的课程"
  final String timeInfo; // 时间段或倒计时
  final Color baseColor;
  final String icon;
  final VoidCallback onTap;
  final int priority;
  final bool isTeam;
  final String? actionLabel; // 右侧操作按钮文字
  final IconData? actionIcon; // 右侧操作按钮图标
  final VoidCallback? onAction; // 右侧操作按钮回调

  HomeBannerEvent({
    required this.type,
    required this.title,
    this.subtitle,
    required this.label,
    required this.timeInfo,
    required this.baseColor,
    required this.icon,
    required this.onTap,
    required this.priority,
    this.isTeam = false,
    this.actionLabel,
    this.actionIcon,
    this.onAction,
  });
}
