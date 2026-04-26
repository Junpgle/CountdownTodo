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
import 'package:uuid/uuid.dart';
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
import '../services/notification_service.dart';
import '../services/widget_service.dart';
import '../services/screen_time_service.dart';
import '../services/course_service.dart';
import '../services/external_share_handler.dart';
import '../services/pomodoro_service.dart';
import '../services/pomodoro_sync_service.dart';
import '../services/reminder_schedule_service.dart';
import '../services/float_window_service.dart';

// 引入其他页面
import 'screen_time_detail_screen.dart';
import 'math_menu_screen.dart';
import 'home_settings_screen.dart';
import 'feature_guide_screen.dart';
import 'todo_confirm_screen.dart';
import 'add_todo_screen.dart';
import 'course_screens.dart';
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
import '../widgets/conflict_alert_dialog.dart';
import '../widgets/sync_status_banner.dart'; // 🚀 引入
import '../widgets/sticky_announcement_banner.dart'; // 🚀 引入
import 'pomodoro_screen.dart';
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
  List<String> _rightSections = ['countdowns', 'screenTime', 'timeline', 'pomodoro'];

  Map<String, bool> _sectionVisibility = {
    'courses': true,
    'countdowns': true,
    'todos': true,
    'screenTime': true,
    'math': true,
    'pomodoro': true,
    'timeline': true,
  };
  Timer? _courseTimer;
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
  final ValueNotifier<int> _timelineRefreshTriggerNotifier = ValueNotifier<int>(0);

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
  TeamAnnouncement? _activeAnnouncement; // 🚀 新增：当前置顶公告

  // ── 本地专注状态 ──
  PomodoroRunState? _localPomodoro;
  bool _isDataLoading = false; // 🚀 加载锁，防止并发触发导致的数据库竞争
  int _todoUpdateSignal = 0; // 🚀 协同更新信号
  final Set<String> _updatedByOthersTodoIds = <String>{};
  int _remoteTodoHighlightSignal = 0;
  Timer? _remoteTodoHighlightTimer;
  int _teamPendingCount = 0; // 🚀 Uni-Sync 4.0: 团队待处理消息数
  String? _currentSelectedTeamUuid; // 🚀 选中的团队 ID
  String? _currentSelectedTeamName; // 🚀 选中的团队名称
  Timer? _localPomodoroTicker;
  int _localPomodoroRemaining = 0;
  StreamSubscription<PomodoroRunState?>? _localPomodoroSub; // 🚀 新增：本地专注状态订阅
  Timer? _collaborativeSyncDebouncer; // 🚀 协同同步防抖器

  // 🚀 Granular Refresh Notifiers
  late final ValueNotifier<List<TodoItem>> _todosNotifier;
  late final ValueNotifier<List<TodoGroup>> _groupsNotifier;
  late final ValueNotifier<Map<String, dynamic>> _courseDataNotifier;
  late final ValueNotifier<List<CountdownItem>> _countdownsNotifier;
  late final ValueNotifier<Map<String, dynamic>> _mathStatsNotifier;

  final ValueNotifier<bool> _isGlobalLoadingNotifier = ValueNotifier<bool>(false);
  final ValueNotifier<int> _todoUpdateSignalNotifier = ValueNotifier<int>(0);

  // 🚀 GlobalKeys for Zoom Animations
  final GlobalKey _searchButtonKey = GlobalKey();
  final GlobalKey _teamsButtonKey = GlobalKey();
  final GlobalKey _courseCenterKey = GlobalKey();

  // === 初始化与生命周期 ===
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadSectionPreferences();
    _loadSemesterSettings();
    _generateGreeting();
    _loadAllData();
    _initManifestWallpaper();
    WidgetService.init();
    _initCrossDevicePomodoro(); // 首页也连接 WS
    _initLocalPomodoroMonitoring(); // 🚀 修改：使用 Stream 监测本地专注状态

    // 🚀 Granular Refresh Initialization
    _todosNotifier = ValueNotifier<List<TodoItem>>(_todos);
    _groupsNotifier = ValueNotifier<List<TodoGroup>>(_todoGroups);
    _courseDataNotifier = ValueNotifier<Map<String, dynamic>>(_dashboardCourseData);
    _countdownsNotifier = ValueNotifier<List<CountdownItem>>([]);
    _mathStatsNotifier = ValueNotifier<Map<String, dynamic>>(_mathStats);
    
    // 🚀 核心修复：监听全局数据刷新信号，实现背景同步后的 UI 自动响应
    StorageService.dataRefreshNotifier.addListener(_loadAllData);

    // 🚀 桌面端拦截：确保只在移动设备监听通道
    if (Platform.isAndroid || Platform.isIOS) {
      const platform = MethodChannel(
          'com.math_quiz.junpgle.com.math_quiz_app/notifications');
      platform.setMethodCallHandler((call) async {
        switch (call.method) {
          case "markCurrentTodoDone":
            debugPrint(
                "📱 收到 markCurrentTodoDone 调用: arguments=${call.arguments}");
            final args = call.arguments;
            int? notifId;
            if (args is Map) {
              notifId = args['notificationId'] as int?;
            }
            debugPrint("📱 解析 notifId: $notifId");
            _markCurrentTodoDone(notifId: notifId);
            break;
          case "openTodoConfirm":
            _checkPendingTodoConfirm();
            break;
          case "openShortcut":
            final shortcutType = call.arguments as String?;
            debugPrint("⚡ 收到 openShortcut 调用: $shortcutType");
            if (shortcutType != null) {
              _handleShortcut(shortcutType);
            }
            break;
          case "viewAnalysisImage":
            final imagePath = call.arguments as String?;
            if (imagePath != null && mounted) {
              _showAnalysisImage(imagePath);
            }
            break;
          case "viewOriginalText":
            final text = call.arguments as String?;
            if (text != null && mounted) {
              _showOriginalText(text);
            }
            break;
          // pomodoroFinishEarly 和 pomodoroAbandon 由 PomodoroScreen 处理
        }
      });
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
          // 图片识别到待办，显示确认页面
          _navigateToTodoConfirm(results, imagePath, null);
        },
      );

      // 检查是否有待确认的待办数据（从通知点击进入）
      _checkPendingTodoConfirm();

      _checkAutoSync();
      _checkUpdatesSilently();

      _courseTimer = Timer.periodic(const Duration(minutes: 1), (timer) {
        _checkUpcomingEvents();
      });
      // 立即执行一次
      Future.delayed(Duration(milliseconds: 500), () {
        if (mounted) _checkUpcomingEvents();
      });
      _checkAndNavigateToPomodoro();
      // 🚀 预热搜索索引，确保首次点击秒开
      SearchService.instance.warmup();
      // 🚀 清理 7 天前的过期图片
      TodoItem.cleanupAnalysisImages();
    });
  }

  @override
  void dispose() {
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
    _collaborativeSyncDebouncer?.cancel();
    _remoteTodoHighlightTimer?.cancel();
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
  void _navigateToTodoConfirm(List<Map<String, dynamic>> results,
      String? imagePath, String? originalText, [String? teamUuid, String? teamName]) {
    if (!mounted || results.isEmpty) return;

    Navigator.push(
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
        },
      )),
    );
  }

  /// 批量添加待办 (支持团队上下文关联)
  Future<void> _batchAddTodos(List<Map<String, dynamic>> todosData, [String? teamUuid, String? teamName]) async {
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
        imagePath: data['imagePath'], // 📸 关联图片路径
        originalText: data['originalText'], // 📄 原始分析文本
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
      final results = pendingData['results'] as List<dynamic>?;

      if (imagePath != null && results != null && results.isNotEmpty) {
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

  /// 打开待确认待办页面
  void _openPendingTodoConfirm() {
    if (_pendingTodoConfirm == null) return;

    final imagePath = _pendingTodoConfirm!['imagePath'] as String?;
    final results = _pendingTodoConfirm!['results'] as List<dynamic>?;

    if (imagePath == null || results == null || results.isEmpty) return;

    final List<Map<String, dynamic>> typedResults =
        results.map((e) => Map<String, dynamic>.from(e as Map)).toList();

    _navigateToTodoConfirm(typedResults, imagePath, null);

    // 导航后清除待确认数据和入口
    setState(() {
      _pendingTodoConfirm = null;
    });
    ExternalShareHandler.clearPendingTodoConfirm();
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
      authToken = prefs.getString('auth_token');
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
    if (signal.sourceDevice == 'flutter_$_deviceId') return;

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
            );
          }
        }
        break;

      case 'STOP':
      case 'INTERRUPT':
      case 'FOCUS_DISCONNECTED':
        _stopRemotePomodoroTicker();
        setState(() => _remotePomodoro = null);

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
          );
          if (isCountUp) {
            _remotePomodoroRemaining = 0; // 🚀 关键：同步侧归零
          }
        });
        if (isCountUp) {
          _startRemotePomodoroTicker(_remotePomodoro!.targetEndMs ?? 0, true);
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
        setState(() => _remotePomodoroRemaining++);
      } else {
        final rem =
            ((targetEndMs - DateTime.now().millisecondsSinceEpoch) / 1000)
                .ceil();
        if (rem <= 0) {
          _remotePomodoroTicker?.cancel();
          if (mounted) setState(() => _remotePomodoro = null);
        } else {
          setState(() => _remotePomodoroRemaining = rem);
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
      setState(() {
        if (isCountUp) {
          _localPomodoroRemaining++;
        } else {
          _localPomodoroRemaining--;
          if (_localPomodoroRemaining <= 0) {
            _localPomodoroRemaining = 0;
            _stopLocalTicker();
          }
        }
      });
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
    final todoCount = results?.length ?? 0;

    if (todoCount == 0) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Material(
        color: isLight ? Colors.white : Colors.grey[900],
        borderRadius: BorderRadius.circular(16),
        elevation: 2,
        child: InkWell(
          onTap: _openPendingTodoConfirm,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                // 图片缩略图
                if (imagePath != null && File(imagePath).existsSync())
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
                      color: Colors.deepPurple.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child:
                        const Icon(Icons.checklist, color: Colors.deepPurple),
                  ),
                const SizedBox(width: 12),
                // 文字信息
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'AI识别完成',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: isLight ? Colors.black87 : Colors.white,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '发现 $todoCount 个待办，点击查看',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
                // 箭头图标
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

  /// 首页顶部的专注 Banner (统一处理本地和远程)
  Widget _buildFocusBanner(bool isLight) {
    // 优先显示本地，本地没有显示远程
    if (_localPomodoro != null) {
      return _buildFocusCard(
        isLight: isLight,
        isLocal: true,
        title: _localPomodoro!.todoTitle,
        remaining: _localPomodoroRemaining,
        mode: _localPomodoro!.mode,
        label: '正在专注 (本机)',
      );
    }
    if (_remotePomodoro != null) {
      final deviceLabel = _remotePomodoro!.sourceDevice
              ?.replaceFirst('flutter_', '')
              .substring(0, 8) ??
          '其他设备';
      return _buildFocusCard(
        isLight: isLight,
        isLocal: false,
        title: _remotePomodoro!.todoTitle,
        remaining: _remotePomodoroRemaining,
        mode: _remotePomodoro!.mode == 1
            ? TimerMode.countUp
            : TimerMode.countdown,
        label: '$deviceLabel 正在专注',
      );
    }
    return const SizedBox.shrink();
  }

  Widget _buildFocusCard({
    required bool isLight,
    required bool isLocal,
    required String? title,
    required int remaining,
    required TimerMode mode,
    required String label,
  }) {
    final m = remaining ~/ 60;
    final s = remaining % 60;
    final isCountUp = mode == TimerMode.countUp;
    final timeStr = isCountUp
        ? '已专注 ${remaining ~/ 60} 分钟'
        : (remaining > 60
            ? '$m 分钟'
            : '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}');

    final baseColor =
        isLocal ? const Color(0xFF4F46E5) : const Color(0xFFFF6B6B);

    return GestureDetector(
      key: _focusBannerKey,
      onTap: () async {
        await PageTransitions.pushFromRect(
          context: context,
          page: PomodoroScreen(username: widget.username),
          sourceKey: _focusBannerKey,
        );
        if (mounted) {
          _timelineRefreshTriggerNotifier.value++;
          _loadAllData();
        }
      },
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: baseColor.withValues(alpha: isLight ? 0.85 : 0.15),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: baseColor.withValues(alpha: 0.4)),
        ),
        child: Row(
          children: [
            Text(isLocal ? '⚡' : '🍅', style: const TextStyle(fontSize: 18)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: isLight ? Colors.white : baseColor,
                    ),
                  ),
                  if (title != null && title.isNotEmpty)
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 12,
                        color: isLight ? Colors.white70 : null,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            Text(
              timeStr,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: isLight ? Colors.white : baseColor,
              ),
            ),
            const SizedBox(width: 4),
            Icon(Icons.chevron_right,
                color: isLight ? Colors.white70 : baseColor, size: 18),
          ],
        ),
      ),
    );
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

  Future<void> _checkUpcomingEvents() async {
    DateTime now = DateTime.now();

    final dashboardData = await CourseService.getDashboardCourses(widget.username);
    List<CourseItem> courses =
        (dashboardData['courses'] as List?)?.cast<CourseItem>() ?? [];

    bool hasUpcomingCourse = false;
    for (var course in courses) {
      try {
        final courseTime = _resolveCourseStartTime(course, now);
        if (courseTime == null) continue;
        int diffMinutes = courseTime.difference(now).inMinutes;

        if (diffMinutes >= 0 && diffMinutes <= 20) {
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

    if (hasUpcomingCourse) return;

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

    // ── 待办提醒 ────────────────────────────────────────────────
    // 1. 特殊待办 (快递/外卖等): 今天所有的都显示 (保持原逻辑)
    final specialTodosToday = _todos.where((t) {
      if (t.isDone || t.isDeleted) return false;
      if (t.dueDate == null) return false;
      final todoType = detectTodoType(t.title);
      if (todoType == 'default') return false;
      return _isSameDay(t.dueDate!.toLocal(), now);
    }).toList();

    for (final todo in specialTodosToday) {
      await NotificationService.showUpcomingTodoNotification(todo);
    }

    // 2. 普通待办 (非全天): 如果即将开始 (例如 30 分钟内)，则上岛显示
    final upcomingRegularTodos = _todos.where((t) {
      if (t.isDone || t.isDeleted) return false;
      if (t.dueDate == null) return false;
      final todoType = detectTodoType(t.title);
      if (todoType != 'default') return false;

      // 排除全天待办 (00:00 - 23:59)
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

      // 检查是否即将开始 (提前 30 分钟到甚至已经开始但没结束)
      // 这里的 logic 可以根据需求调整，通常我们希望在开始前一段时间“上岛”
      final diff = startDate.difference(now).inMinutes;
      return diff >= -15 && diff <= 30; // 开始前 30min 到开始后 15min 内显示
    }).toList();

    for (final todo in upcomingRegularTodos) {
      await NotificationService.showUpcomingTodoNotification(todo);
    }

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
    _leftSections = ['countdowns', 'todos'];
    _rightSections = ['courses', 'timeline', 'pomodoro', 'screenTime', 'math'];

    // 忽略之前的可见性设置，全部强制显示
    _sectionVisibility = {
      'courses': true,
      'countdowns': true,
      'todos': true,
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
    }
  }

  /// 启动时检测是否有正在进行的番茄钟，有则跳转至计时界面
  Future<void> _checkAndNavigateToPomodoro() async {
    // 稍微延迟，让首页先完成渲染
    await Future.delayed(const Duration(milliseconds: 800));
    if (!mounted) return;
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
        if (t['role'] == 0) { // 如果是管理员
          final reqs = await ApiService.fetchPendingRequests(t['uuid']);
          totalPending += reqs.length;
        }
      }));

      if (mounted) {
        setState(() => _teamPendingCount = totalPending);
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
    DateTime? lastSync = await StorageService.getLastAutoSyncTime(widget.username);
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

              if (!mounted) return;

              // 2. 彻底关闭弹窗并切断路由栈，回到登录页
              Navigator.of(ctx).pop();
              Navigator.pushNamedAndRemoveUntil(
                  context, '/login', (route) => false);
            },
            child: const Text("重新登录"),
          ),
        ],
      ),
    );
  }

  void _debounceCollaborativeSync() {
    _collaborativeSyncDebouncer?.cancel();
    _collaborativeSyncDebouncer = Timer(const Duration(milliseconds: 1500), () async {
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
      debugPrint("⚡ [DashboardLoader] $name 加载成功 ($duration ms)");
      return result;
    } catch (e) {
      debugPrint("❌ [DashboardLoader] $name 加载超时或异常: $e");
      return null;
    }
  }

  // 🚀 核心重构：渲染主页时，绝对不能将 isDeleted 的数据加载到视图层！
  Future<void> _loadAllData({bool deferred = false}) async {
    if (_isGlobalLoadingNotifier.value) return;

    if (deferred) {
      // 🚀 核心优化：延迟 400ms 刷新，确保返回动画（Pop）执行完毕后再处理数据
      // 避免 CPU 密集型任务与动画冲突导致卡顿
      await Future.delayed(const Duration(milliseconds: 400));
    }
    
    _isGlobalLoadingNotifier.value = true;

    try {
      final startTime = DateTime.now();
      debugPrint("⏳ [DashboardLoader] 开始并发加载 5 项核心任务...");

      // 1. 读取基础数据 (并发执行，带超时保护)
      final results = await Future.wait([
        _loadDataTask("Todos", StorageService.getTodos(widget.username, limit: 500)),
        _loadDataTask("Groups", StorageService.getTodoGroups(widget.username)),
        _loadDataTask("Countdowns", StorageService.getCountdowns(widget.username)),
        _loadDataTask("Math", StorageService.getMathStats(widget.username)),
        _loadDataTask("Courses", CourseService.getDashboardCourses(widget.username)),
      ]);

      final List<TodoItem> allTodos = ((results[0] ?? []) as List<TodoItem>).where((t) => !t.isDeleted).toList();
      final List<TodoGroup> allGroups = ((results[1] ?? []) as List<TodoGroup>).where((g) => !g.isDeleted).toList();
      final List<CountdownItem> allCountdowns = ((results[2] ?? []) as List<CountdownItem>).where((c) => !c.isDeleted).toList();
      final Map<String, dynamic> mathStats = (results[3] ?? {}) as Map<String, dynamic>;
      final Map<String, dynamic> courseData = (results[4] ?? {'title': '课程提醒', 'courses': []}) as Map<String, dynamic>;

      if (mounted) {
        // 🚀 Granular Update: Only update notifiers if content actually changed
        if (!_isListEqual(_todos, allTodos)) {
          _todos = allTodos;
          _todosNotifier.value = allTodos;
        }
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
      }
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
      // 🚀 桌面端拦截
      if (Platform.isAndroid || Platform.isIOS) {
        const MethodChannel(
                'com.math_quiz.junpgle.com.math_quiz_app/notifications')
            .invokeMethod('cancelNotification');
      }
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
      debugPrint('[HomeDashboard] Saved ${todos.length} todos to shared file');
    } catch (e) {
      debugPrint('[HomeDashboard] Failed to save todos to shared file: $e');
    }
  }

  Future<void> _handleManualSync({
    bool silent = false,
    bool syncTodos = true,
    bool syncCountdowns = true,
    bool syncScreenTime = true,
    bool syncPomodoro = true,
    bool syncTimeLogs = true, // 🚀 1. 新增同步时间日志的参数
  }) async {
    if (_isSyncing) return;
    setState(() {
      _isSyncing = true;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      int? userId = prefs.getInt('current_user_id');
      if (userId == null) throw Exception("未登录");

      bool hasChanges = false;

      // 🚀 2. 判断条件加入 syncTimeLogs
      if (syncTodos || syncCountdowns || syncTimeLogs) {
        final syncResult = await StorageService.syncData(
          widget.username,
          syncTodos: syncTodos,
          syncCountdowns: syncCountdowns,
          syncTimeLogs: syncTimeLogs, // 🚀 3. 将参数传给底层的增量同步引擎
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
          _remoteTodoHighlightTimer =
              Timer(const Duration(seconds: 8), () {
            if (!mounted) return;
            setState(() => _updatedByOthersTodoIds.clear());
          });
        }

        // 🚀 新增：处理冲突信息
        final List<ConflictInfo> conflicts = syncResult['conflicts'] ?? [];
        if (conflicts.isNotEmpty && mounted) {
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
                const Text("链路诊断报告", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ],
            ),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            content: SizedBox(
              width: double.maxFinite,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildDiagnosticItem("核心 API 服务", ApiService.ping()),
                  _buildDiagnosticItem("实时同步通道", Future.value(PomodoroSyncService.instance.connectionState == SyncConnectionState.connected)),
                  _buildDiagnosticItem("增量引擎状态", Future.value(true)), // 逻辑始终为真，仅展示
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
                    Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
                    if (!isLoading)
                      Text(
                        isOk == true ? "服务运行正常" : "连接受阻，部分功能受限",
                        style: TextStyle(fontSize: 11, color: isOk == true ? Colors.grey : Colors.redAccent.withValues(alpha: 0.8)),
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
          _buildInfoRow("当前接入点", isTest ? "Aliyun (Test Node)" : "Aliyun (Global Node)"),
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
        Text(value, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
      ],
    );
  }

  void _showSyncOptionsDialog() {
    bool syncTodos = true;
    bool syncCountdowns = true;
    bool syncScreenTime = true;
    bool syncPomodoro = true;
    bool syncTimeLogs = true; // 🚀 1. 新增弹窗状态变量

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
                // 🚀 2. 新增时间日志的勾选项
                CheckboxListTile(
                  title: const Text("时间日志 (补录)"),
                  value: syncTimeLogs,
                  onChanged: (val) =>
                      setDialogState(() => syncTimeLogs = val ?? false),
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
                      syncTimeLogs)
                  ? () {
                      Navigator.pop(ctx);
                      _handleManualSync(
                        silent: false,
                        syncTodos: syncTodos,
                        syncCountdowns: syncCountdowns,
                        syncScreenTime: syncScreenTime,
                        syncPomodoro: syncPomodoro,
                        syncTimeLogs: syncTimeLogs, // 🚀 4. 传递给执行函数
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
    debugPrint("[Wallpaper] Current URL failed: $_wallpaperUrl. Trying fallback...");

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
    final size = MediaQuery.of(context).size;
    final bool isCompact = size.shortestSide < 600;
    final double maxWidth = isCompact ? size.width : 1180;
    final double panelWidth = (size.width - 40).clamp(0, maxWidth);
    final double left = (size.width - panelWidth) / 2;
    
    // 🚀 核心改进：计算搜索面板在 Overlay 中的实际位置，使动画不再铺满全屏，而是缩放到板块
    // 修复对齐问题：需要加上 SafeArea 的顶部高度（状态栏）
    final statusBarHeight = MediaQuery.of(context).padding.top;
    final targetRect = Rect.fromLTWH(left, statusBarHeight + 60, panelWidth, 150); // 150px 约等于搜索框+快捷提示的高度
    final targetBorderRadius = BorderRadius.circular(28);

    PageTransitions.pushFromRect(
      context: context,
      page: const GlobalSearchOverlay(),
      sourceKey: _searchButtonKey,
      targetRect: targetRect,
      targetBorderRadius: targetBorderRadius,
    ).then((_) async {
      // 🚀 延迟 200ms 恢复，确保键盘收起后再允许背景重排，彻底消除跳变
      await Future.delayed(const Duration(milliseconds: 200));
      if (mounted) setState(() {
        _isSearchOpen = false;
        _timelineRefreshTriggerNotifier.value++; // 🚀 搜索完成后刷新时间轴（记录搜索历史）
      });
      _loadAllData(deferred: true);
    });
  }

  // 辅助方法：显示通用全屏层 (透明背景)
  static Future<T?> showGeneralPage<T>({
    required BuildContext context,
    required RoutePageBuilder pageBuilder,
    RouteTransitionsBuilder? transitionBuilder,
    Duration transitionDuration = const Duration(milliseconds: 200),
    bool barrierDismissible = true,
    Color barrierColor = Colors.transparent,
    String? barrierLabel,
  }) {
    return Navigator.of(context).push<T>(PageRouteBuilder(
      opaque: false,
      barrierDismissible: barrierDismissible,
      barrierColor: barrierColor,
      barrierLabel: barrierLabel,
      pageBuilder: pageBuilder,
      transitionsBuilder: transitionBuilder ?? (ctx, anim1, anim2, child) => child,
      transitionDuration: transitionDuration,
    ));
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
      backgroundColor: showWallpaper
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
                    searchKey: _searchButtonKey,
                    teamsKey: _teamsButtonKey,
                    settingsKey: _settingsButtonKey,
                    courseKey: _courseButtonKey,
                    showCourseButton: isTablet,
                    teamPendingCount: _teamPendingCount, // 🚀 绑定计数
                    onTeams: () async {
                      await PageTransitions.pushFromRect(
                        context: context,
                        page: TeamManagementScreen(username: widget.username),
                        sourceKey: _teamsButtonKey,
                      );
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
                if (_activeAnnouncement != null && (_selectedTabIndex != 1 || isTablet))
                  StickyAnnouncementBanner(
                    announcement: _activeAnnouncement!,
                    onAcknowledge: () async {
                      final uuid = _activeAnnouncement!.uuid;
                      setState(() => _activeAnnouncement = null);
                      await ApiService.markAnnouncementAsRead(uuid);
                    },
                  ),

                // 🚀 统一处理本地与远程专注 Banner
                if (_selectedTabIndex != 1 || isTablet)
                  _buildFocusBanner(isLight),

                // 待确认待办入口卡片（从图片识别来）
                if (_selectedTabIndex != 1 || isTablet)
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
                                  (_dashboardCourseData['courses'] as List? ?? []).isEmpty)
                              ? _buildDashboardSkeleton(isLight)
                              : LayoutBuilder(
                                  builder: (context, constraints) {

                      // ... (rest of section definitions)
                      Widget courseSection = CourseSectionWidget(
                          dashboardCourseData: _dashboardCourseData,
                          isLight: isLight);
                      Widget countdownSection = CountdownSectionWidget(
                          countdowns: _countdowns,
                          username: widget.username,
                          isLight: isLight,
                          onDataChanged: () {
                            _loadAllData();
                            _timelineRefreshTriggerNotifier.value++;
                          });
                      Widget todoSection = ValueListenableBuilder<int>(
                        valueListenable: _todoUpdateSignalNotifier,
                        builder: (context, signal, _) {
                          return TodoSectionWidget(
                            todos: _todos,
                            highlightedTodoIds: _updatedByOthersTodoIds,
                            remoteUpdateHighlightSignal: _remoteTodoHighlightSignal,
                            todoGroups: _todoGroups,
                            username: widget.username,
                            isLight: isLight,
                            onTeamChanged: (teamUuid, teamName) {
                              setState(() {
                                _currentSelectedTeamUuid = teamUuid;
                                _currentSelectedTeamName = teamName;
                              });
                            },
                            onGroupsChanged: (newGroups) async {
                              setState(() => _todoGroups = newGroups.where((g) => !g.isDeleted).toList());
                              final allGroups = await StorageService.getTodoGroups(widget.username);
                              for (var g in newGroups) {
                                int idx = allGroups.indexWhere((x) => x.id == g.id);
                                if (idx != -1) {
                                  if (g.updatedAt >= allGroups[idx].updatedAt) allGroups[idx] = g;
                                } else {
                                  allGroups.add(g);
                                }
                              }
                              await StorageService.saveTodoGroups(widget.username, allGroups, sync: true);
                            },
                            onTodosChanged: (newTodos) async {
                              // 🚀 记录变更，用于通知清除
                              final oldTodos = List<TodoItem>.from(_todos);
                              _todos = newTodos;
                              _timelineRefreshTriggerNotifier.value++;
    
                              // 🚀 核心修复：任务完成后自动清除对应通知
                              for (var nt in newTodos) {
                                if (nt.isDone) {
                                  final ot = oldTodos.firstWhere((t) => t.id == nt.id, orElse: () => nt);
                                  if (!ot.isDone) {
                                    // 刚完成
                                    debugPrint("🧹 任务 ${nt.title} 已完成，尝试清除通知 ${nt.id.hashCode}");
                                    NotificationService.cancelSpecialTodoNotification(nt.id.hashCode);
                                  }
                                }
                              }

                              final allTodos = await StorageService.getTodos(widget.username);
                              for (var newT in _todos) {
                                int idx = allTodos.indexWhere((x) => x.id == newT.id);
                                if (idx != -1) {
                                  allTodos[idx] = newT;
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
                              await WidgetService.updateTodoWidget(_todos);

                              _todoUpdateSignalNotifier.value++; // 🚀 触发局部更新
                            },
                            initialSelectedTeamUuid: _currentSelectedTeamUuid,
                            onRefreshRequested: _handleManualSync, 
                            onLLMResultsParsed: (results, imagePath, originalText, tUuid, tName) {
                              _navigateToTodoConfirm(
                                  results, imagePath, originalText, tUuid, tName);
                            },
                          );
                        },
                      );
                      Widget screenTimeSection = RepaintBoundary(
                        child: KeyedSubtree(
                          key: _screenTimeCardKey,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SectionHeader(
                                  title: "屏幕时间 (今日汇总)",
                                  icon: Icons.timer_outlined,
                                  isLight: isLight),
                              ScreenTimeCard(
                                stats: _screenTimeStats,
                                hasPermission: _hasUsagePermission,
                                isLoading: _isLoadingScreenTime,
                                lastSyncTime: _lastScreenTimeSync,
                                onOpenSettings: () async {
                                  if (Platform.isAndroid || Platform.isIOS) {
                                    await ScreenTimeService.openSettings();
                                  }
                                  _initScreenTime();
                                },
                                onViewDetail: () {
                                  PageTransitions.pushFromRect(
                                    context: context,
                                    page: ScreenTimeDetailScreen(
                                        todayStats: _screenTimeStats),
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
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SectionHeader(
                                  title: "数学测验",
                                  icon: Icons.functions,
                                  isLight: isLight),
                              MathStatsCard(
                                  stats: _mathStats,
                                  onTap: () async {
                                    await PageTransitions.pushFromRect(
                                      context: context,
                                      page: MathMenuScreen(
                                          username: widget.username),
                                      sourceKey: _mathCardKey,
                                    );
                                    _loadAllData(deferred: true);
                                  }),
                            ],
                          ),
                        ),
                      );
                      Widget timelineSection = ValueListenableBuilder<int>(
                        valueListenable: _timelineRefreshTriggerNotifier,
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
                          valueListenable: _timelineRefreshTriggerNotifier,
                          builder: (context, trigger, _) {
                            return KeyedSubtree(
                              key: _pomodoroCardKey,
                              child: PomodoroTodaySection(
                                username: widget.username,
                                isLight: isLight,
                                refreshTrigger: trigger,
                                onTap: () async {
                                  await PageTransitions.pushFromRect(
                                    context: context,
                                    page: PomodoroScreen(
                                      username: widget.username,
                                      initialTab: 1,
                                    ),
                                    sourceKey: _pomodoroCardKey,
                                  );
                                  _timelineRefreshTriggerNotifier.value++;
                                  _loadAllData();
                                },
                              ),
                            );
                          },
                        ),
                      );

                      Map<String, Widget> sectionsMap = {
                        'courses': courseSection,
                        'countdowns': countdownSection,
                        'todos': todoSection,
                        'screenTime': screenTimeSection,
                        'math': mathSection,
                        'pomodoro': pomodoroSection,
                        'timeline': timelineSection,
                      };

                      bool hasNoCourse = (_dashboardCourseData['courses'] ==
                              null ||
                          (_dashboardCourseData['courses'] as List).isEmpty);

                      if (!isTablet) {
                        List<String> tab1Order = ['countdowns', 'courses', 'todos'];
                        if (hasNoCourse) {
                          if (_noCourseBehavior == 'hide') {
                            tab1Order.remove('courses');
                          } else if (_noCourseBehavior == 'bottom') {
                            tab1Order.remove('courses');
                            tab1Order.add('courses');
                          }
                        }

                        List<Widget> tab1Widgets = tab1Order
                            .where((key) =>
                                (_sectionVisibility[key] ?? true) &&
                                sectionsMap.containsKey(key))
                            .map((key) => Padding(
                                padding: const EdgeInsets.only(bottom: 24.0),
                                child: sectionsMap[key]!))
                            .toList();

                        List<Widget> tab3Widgets = ['timeline', 'pomodoro', 'screenTime', 'math']
                            .where((key) =>
                                (_sectionVisibility[key] ?? true) &&
                                sectionsMap.containsKey(key))
                            .map((key) => Padding(
                                padding: const EdgeInsets.only(bottom: 24.0),
                                child: sectionsMap[key]!))
                            .toList();

                        return IndexedStack(
                          index: _selectedTabIndex == 2 ? 1 : 0,
                          children: [
                            // Tab 1: 重要日、课程、待办
                            RepaintBoundary(
                              child: SingleChildScrollView(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    ...tab1Widgets,
                                    if (_wallpaperCopyright != null && _wallpaperCopyright!.isNotEmpty)
                                      _buildWallpaperCopyright(isLight),
                                    const SizedBox(height: 100), // 为悬浮底栏留出空间
                                  ],
                                ),
                              ),
                            ),
                            // Tab 2 (mapped to index 2 in bottom bar): 今日专注、屏幕时间
                            RepaintBoundary(
                              child: SingleChildScrollView(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    ...tab3Widgets,
                                    if (_wallpaperCopyright != null && _wallpaperCopyright!.isNotEmpty)
                                      _buildWallpaperCopyright(isLight),
                                    const SizedBox(height: 100), // 为悬浮底栏留出空间
                                  ],
                                ),
                              ),
                            ),
                          ],
                        );
                      }

                      // Tablet Layout
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
                            .where((key) =>
                                (_sectionVisibility[key] ?? true) &&
                                sectionsMap.containsKey(key))
                            .map((key) => Padding(
                                padding: const EdgeInsets.only(bottom: 24.0),
                                child: sectionsMap[key]!))
                            .toList();
                      }

                      List<Widget> leftWidgets =
                          buildColumnWidgets(currentLeft);
                      List<Widget> rightWidgets =
                          buildColumnWidgets(currentRight);

                      return SingleChildScrollView(
                        padding: EdgeInsets.symmetric(
                            horizontal: isTablet ? 32 : 16, vertical: 16),
                        child: Align(
                          alignment: Alignment.topCenter,
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 1400),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                isTablet
                                    ? Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Expanded(
                                              flex: 10,
                                              child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: leftWidgets)),
                                          if (rightWidgets.isNotEmpty)
                                            const SizedBox(width: 40),
                                          if (rightWidgets.isNotEmpty)
                                            Expanded(
                                                flex: 11,
                                                child: Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment.start,
                                                    children: rightWidgets)),
                                        ],
                                      )
                                    : Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          ...leftWidgets,
                                          ...rightWidgets,
                                        ],
                                      ),
                                if (_wallpaperCopyright != null &&
                                    _wallpaperCopyright!.isNotEmpty)
                                  Center(
                                    child: Padding(
                                      padding: const EdgeInsets.only(
                                          top: 16.0, bottom: 32.0),
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
                initialTeamUuid: _currentSelectedTeamUuid, // 🚀 关键修复：将当前选中的团队 Tab 传给创建页
                initialTeamName: _currentSelectedTeamName,
                onTodoAdded: (todo) async {
                  final allTodos = await StorageService.getTodos(widget.username);
                  allTodos.add(todo);
                  await StorageService.saveTodos(widget.username, allTodos);
                  // 🚀 协作实时化：发送更新信号
                  if (todo.teamUuid != null) {
                    PomodoroSyncService.instance.sendTeamUpdateSignal(todo.teamUuid);
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
                  final allTodos = await StorageService.getTodos(widget.username);
                  allTodos.addAll(todos);
                  await StorageService.saveTodos(widget.username, allTodos);
                  // 🚀 协作实时化：发送更新信号
                  final updatedTeamUuid = todos.firstWhere((t) => t.teamUuid != null, orElse: () => todos.first).teamUuid;
                  if (updatedTeamUuid != null) {
                    PomodoroSyncService.instance.sendTeamUpdateSignal(updatedTeamUuid);
                  }
                  await _saveTodosToSharedFile(allTodos);
                  FloatWindowService.triggerReminderCheck();
                  FloatWindowService.invalidateSlotCache();
                  _syncTodoNotification();
                  _rescheduleAlarms();
                  await WidgetService.updateTodoWidget(allTodos);
                  if (mounted) await _loadAllData(deferred: true);
                },
                onLLMResultsParsed: (results, imagePath, originalText, tUuid, tName) {
                  Navigator.pop(context); // 关闭添加页面
                  _navigateToTodoConfirm(results, imagePath, originalText, tUuid, tName);
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
    final Color inactiveColor = (isLight || !isDarkMode) ? Colors.black45 : Colors.white54;
    final double bottomPadding = MediaQuery.of(context).padding.bottom;

    return Container(
      height: 54 + (bottomPadding > 0 ? bottomPadding * 0.5 : 6), // 进一步压缩高度
      margin: const EdgeInsets.fromLTRB(40, 0, 40, 12), // 增加左右间距以减小宽度
      decoration: BoxDecoration(
        color: isDarkMode ? Colors.black.withValues(alpha: 0.4) : Colors.white.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(40), // 更圆润的边缘
        border: Border.all(
          color: isDarkMode ? Colors.white.withValues(alpha: 0.05) : Colors.white.withValues(alpha: 0.2),
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
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildTabItem(0, Icons.dashboard_rounded, '首页', primaryColor, inactiveColor),
                _buildCourseCenterButton(primaryColor),
                _buildTabItem(2, Icons.adjust_rounded, '专注', primaryColor, inactiveColor),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTabItem(int index, IconData icon, String label, Color primary, Color inactive) {
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
    return InkWell(
      onTap: () {
        PageTransitions.pushFromRect(
          context: context,
          page: WeeklyCourseScreen(username: widget.username),
          sourceKey: _courseCenterKey,
        );
      },
      child: Container(
        key: _courseCenterKey,
        width: 48, // 缩小中键按钮
        height: 48,
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
    )
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
    final baseColor = isLight ? Colors.white.withValues(alpha: 0.3) : Colors.grey[800]!;
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
