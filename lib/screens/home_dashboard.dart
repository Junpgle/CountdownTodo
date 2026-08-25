import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_zoom_drawer/flutter_zoom_drawer.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'dart:async';
import '../widgets/home_drawer_menu.dart';
import 'package:intl/intl.dart';
import 'dart:math';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:ui';
import 'package:palette_generator/palette_generator.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/search_service.dart';
import '../utils/page_transitions.dart';

// 引入服务和模型
import '../models.dart';
import '../storage_service.dart';
import '../update_service.dart';
import '../services/api_service.dart';
import '../services/github_resource_service.dart';
import '../services/background_notification_service.dart';
import '../services/notification_service.dart';
import '../services/todo_notification_policy.dart';
import '../services/widget_service.dart';
import '../services/screen_time_service.dart';
import '../services/permission_request_coordinator.dart';
import '../services/macos_pomodoro_status_bar_service.dart';
import '../services/course_service.dart';
import '../services/course_calendar_adjustment_service.dart';
import '../services/external_share_handler.dart';
import '../services/browser_file_service.dart';
import '../services/island_todo_snapshot.dart';
import '../services/wallpaper_cache_service.dart';
import '../services/pomodoro_service.dart';
import '../services/pomodoro_control_service.dart';
import '../services/pomodoro_sync_service.dart';
import '../services/reminder_schedule_service.dart';
import '../services/float_window_service.dart';
import '../services/island_slot_provider.dart';
import '../services/item_semantics_service.dart';
import '../services/conflict_visibility_service.dart';
import '../services/ai_todo_action_executor.dart';
import '../services/ai_todo_chat_launcher.dart';
import '../utils/app_platform.dart';
import '../utils/json_value_parser.dart';
import '../utils/local_image_provider.dart';
import '../utils/system_ui_style.dart';

// 引入其他页面
import 'screen_time_detail_screen.dart';
import 'math_menu_screen.dart';
import 'home_settings_screen.dart';
import 'feature_guide_screen.dart';
import 'todo_confirm_screen.dart';
import 'add_todo_screen.dart';
import 'fixed_schedule_editor_screen.dart';
import 'course_screens.dart';
import 'course_calendar_adjustment_screen.dart';
import 'time_log_screen.dart';
import 'band_sync_screen.dart';
import 'conflict_inbox_screen.dart';
import 'team_management_screen.dart';
import 'personal_timeline_screen.dart';
import '../features/journal/screens/journal_home_screen.dart';
// 引入拆分后的组件
import '../widgets/home_sections.dart';
import '../widgets/home_app_bar.dart';
import '../widgets/countdown_section_widget.dart';
import '../widgets/course_section_widget.dart';
import '../widgets/todo_section_widget.dart';
import '../widgets/pomodoro_today_section.dart';
import '../widgets/plan_block_today_section.dart';
import '../features/habits/screens/habit_center_screen.dart';
import '../features/habits/services/habit_reminder_service.dart';
import '../features/habits/widgets/habit_today_section.dart';
import '../features/thirty_day_challenge/repositories/thirty_day_challenge_repository.dart';
import '../features/thirty_day_challenge/models/thirty_day_challenge.dart';
import '../features/thirty_day_challenge/screens/thirty_day_challenge_screen.dart';
import '../features/thirty_day_challenge/screens/new_challenge_screen.dart';
import '../features/thirty_day_challenge/services/clipboard_share_detector.dart';
import '../widgets/conflict_alert_dialog.dart';
import '../widgets/sync_status_banner.dart'; // 🚀 引入
import '../widgets/sticky_announcement_banner.dart'; // 🚀 引入
import 'pomodoro_screen.dart';
import 'todo_plan_screen.dart';
// 🚀 引入
// 🚀 引入
import '../widgets/global_search_overlay.dart';
import '../widgets/personal_timeline_section.dart';
import '../widgets/coach_mark_overlay.dart';
import '../widgets/home_bottom_navigation_content.dart';
import '../widgets/home_quick_action_button.dart';
import '../widgets/app_status_toast.dart';
import '../services/feature_tip_service.dart';
import '../services/home_layout_service.dart';
import '../widgets/optional_liquid_glass_surface.dart';

part 'home_dashboard_ai.dart';
part 'home_dashboard_contract.dart';
part 'home_dashboard_lifecycle.dart';
part 'home_dashboard_navigation.dart';
part 'home_dashboard_pomodoro.dart';
part 'home_dashboard_banner.dart';
part 'home_dashboard_data.dart';
part 'home_dashboard_persistence.dart';
part 'home_dashboard_wallpaper.dart';
part 'home_dashboard_view.dart';

class HomeDashboard extends StatefulWidget {
  final String username;
  const HomeDashboard({
    super.key,
    required this.username,
  });

  @override
  State<HomeDashboard> createState() => _HomeDashboardState();
}

abstract class _HomeDashboardStateBase extends State<HomeDashboard>
    with WidgetsBindingObserver, _HomeDashboardContract {
  late final PermissionRequestCoordinator _permissionCoordinator;
  final GitHubResourceService _githubResourceService = GitHubResourceService();

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
  Color? _wallpaperDominantColor;
  String? _extractedWallpaperUrl;
  String? _wallpaperCopyright;
  bool _wallpaperShow = false;
  bool _isLoadingScreenTime = true;
  bool _isThirtyDayChallengeActive = false;
  int _screenTimeLoadGeneration = 0;
  int _thirtyDayChallengeCompletedCount = 0;
  int _thirtyDayChallengeTaskCount = 30;
  String _thirtyDayChallengeTitle = ThirtyDayChallengeState.defaultTitle;
  DateTime? _lastScreenTimeSync;
  String _currentGreeting = "";
  bool _semesterEnabled = false;
  DateTime? _semesterStart;
  DateTime? _semesterEnd;
  Map<String, dynamic> _homeTextConfig = {};

  List<String> _leftSections = ['courses', 'todos', 'math'];
  List<String> _rightSections = [
    'countdowns',
    'screenTime',
    'timeline',
    'pomodoro'
  ];
  List<String> _mobileHomeSections =
      HomeLayoutService.defaultOrder(HomeLayoutTarget.mobileHome);
  List<String> _mobileFocusSections =
      HomeLayoutService.defaultOrder(HomeLayoutTarget.mobileFocus);
  int _habitDisplayLimit = HomeLayoutService.defaultHabitDisplayLimit;

  Map<String, bool> _sectionVisibility = {
    'courses': true,
    'countdowns': true,
    'todos': true,
    'planBlocks': true,
    'screenTime': true,
    'math': true,
    'pomodoro': true,
    'timeline': true,
    'habits': true,
  };
  Timer? _courseTimer;
  final Set<String> _coursesWithScheduledAlarms = {};
  final Set<String> _todosWithScheduledAlarms = {};
  String? _activeCourseNotificationKey;
  final Set<int> _activeTodoNotifIds = {};
  bool _isCheckingUpcomingEvents = false;
  Timer? _todoPersistDebounce;
  Completer<void>? _todoPersistDebounceCompleter;
  Future<void> _todoPersistChain = Future.value();
  List<TodoItem>? _pendingTodosToPersist;
  List<TodoItem>? _persistingTodosSnapshot;
  final GlobalKey<TodoSectionWidgetState> _todoSectionKey = GlobalKey();
  final GlobalKey _settingsButtonKey = GlobalKey();
  final GlobalKey _syncButtonKey = GlobalKey();
  final GlobalKey _pomodoroCardKey = GlobalKey(); // 恢复：用于卡片动画源
  final GlobalKey _addCountdownKey = GlobalKey(); // 🚀 新增：倒数日添加按钮
  final GlobalKey _timelineCardKey = GlobalKey(); // 🚀 新增：专注Tab时间轴
  final GlobalKey _mathCardKey = GlobalKey();
  final GlobalKey _screenTimeCardKey = GlobalKey();
  final GlobalKey _habitsCardKey = GlobalKey();
  final GlobalKey _focusBannerKey = GlobalKey();
  final GlobalKey _fabPomodoroKey = GlobalKey();
  final GlobalKey _fabTodoKey = GlobalKey();
  final GlobalKey _courseButtonKey = GlobalKey();

  // 🚀 新增：首页引导用的新增 Keys
  final GlobalKey _todoFolderKey = GlobalKey();
  final GlobalKey _todoHistoryKey = GlobalKey();
  final GlobalKey _countdownHistoryKey = GlobalKey();
  final GlobalKey _todayPlanChartKey = GlobalKey();
  // 独立刷新信号，避免单一计数器同时触发多个重型模块
  final ValueNotifier<int> _scheduleRevision = ValueNotifier<int>(0);
  final ValueNotifier<int> _timelineRevision = ValueNotifier<int>(0);
  final ValueNotifier<int> _pomodoroRevision = ValueNotifier<int>(0);
  final ValueNotifier<int> _habitsRevision = ValueNotifier<int>(0);

  Future<void> _extractColorFromProvider(
      ImageProvider provider, String url) async {
    if (_extractedWallpaperUrl == url) return;
    _extractedWallpaperUrl = url;
    try {
      // 缩小图片尺寸可大幅提升解析速度，防止卡顿和 OOM 取色失败
      final resizedProvider = ResizeImage(provider, width: 256);
      final palette = await PaletteGenerator.fromImageProvider(
        resizedProvider,
        maximumColorCount: 16,
      );
      if (mounted) {
        setState(() {
          // 增加多级降级策略，确保一定能取到颜色
          _wallpaperDominantColor = palette.dominantColor?.color ??
              palette.vibrantColor?.color ??
              palette.mutedColor?.color ??
              palette.lightVibrantColor?.color ??
              palette.darkVibrantColor?.color ??
              (palette.colors.isNotEmpty ? palette.colors.first : null);

          StorageService.setAppWallpaperColor(_wallpaperDominantColor);
        });
      }
    } catch (e) {
      // debugPrint("Failed to extract color: $e");
    }
  }

  int _selectedTabIndex = 0;

  // 待确认的事项数据（从图片识别来）
  Map<String, dynamic>? _pendingTodoConfirm;

  // ── 跨端专注感知 ──
  CrossDevicePomodoroState? _remotePomodoro; // 其他设备正在进行的专注
  Timer? _remotePomodoroTicker;
  bool _isDashboardInForeground = true;
  int _remotePomodoroRemaining = 0;
  StreamSubscription? _remotePomodoroSub;
  StreamSubscription? _connStateSub; // 🚀 兼容性修复：改为通配订阅类型
  final _syncService = PomodoroSyncService();
  String _deviceId = '';
  bool _hasShownUpdate = false;
  bool _hasCheckedHolidayPreset = false;
  bool _showCoachMarks = false;
  Future<void>? _startupPromptsFuture;
  bool _startupPromptsCompleted = false;
  TeamAnnouncement? _activeAnnouncement; // 🚀 新增：当前置顶公告

  // ── 本地专注状态 ──
  PomodoroRunState? _localPomodoro;
  List<TodoPlanBlock> _planBlocks = [];
  List<FixedScheduleItem> _fixedSchedules = [];
  final Set<DataRefreshDomain> _pendingReloadDomains = <DataRefreshDomain>{};
  Timer? _dashboardLoadRetryTimer;
  int _dashboardLoadRetryAttempt = 0;

  final List<StreamSubscription<MethodCall>> _notifSubs = [];
  bool _navigatingToPomodoro = false;
  Route<dynamic>? _pomodoroRoute;
  int _lastPomodoroNavigateMs = 0;
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
  StreamSubscription<MacIslandCommand>? _macIslandCommandSub;
  Timer? _collaborativeSyncDebouncer; // 🚀 协同同步防抖器
  Timer? _syncWatchdogTimer;
  int _syncAttemptGeneration = 0;
  Timer? _bannerRefreshTimer; // 🚀 新增：Banner 倒计时刷新定时器
  Timer? _todoNotificationDebouncer;
  Timer? _teamPendingDebouncer;
  Timer? _announcementDebouncer;
  Timer? _todoWidgetDebouncer;
  Timer? _reminderScheduleDebouncer;
  final ValueNotifier<int> _pomodoroTickNotifier = ValueNotifier<int>(0);

  // 🚀 Granular Refresh Notifiers
  late final ValueNotifier<List<TodoItem>> _todosNotifier;
  late final ValueNotifier<List<TodoGroup>> _groupsNotifier;
  late final ValueNotifier<Map<String, dynamic>> _courseDataNotifier;
  late final ValueNotifier<List<CountdownItem>> _countdownsNotifier;
  late final ValueNotifier<Map<String, dynamic>> _mathStatsNotifier;

  final ValueNotifier<bool> _isGlobalLoadingNotifier =
      ValueNotifier<bool>(false);
  bool _isDashboardLoadInProgress = false;
  final ValueNotifier<int> _todoUpdateSignalNotifier = ValueNotifier<int>(0);

  // 🚀 GlobalKeys for Zoom Animations
  final GlobalKey _searchButtonKey = GlobalKey();
  final GlobalKey _teamsButtonKey = GlobalKey();
  final GlobalKey _aiButtonKey = GlobalKey();
  final GlobalKey _courseCenterKey = GlobalKey();
  final GlobalKey _menuKey = GlobalKey(); // 🚀 新增：侧边栏菜单按钮

  // 壁纸与搜索状态属于页面基础状态，避免散落在视图分片中。
  int _wallpaperRetryCount = 0;
  List<String> _randomWallpaperUrls = [];
  bool _isWallpaperLoadingError = false;
  VoidCallback? _wallpaperShowListener;
  VoidCallback? _wallpaperUrlListener;
  bool _isSearchOpen = false;
  bool _isCheckingClipboardShare = false;
  bool _isClipboardShareDialogVisible = false;
  String? _lastClipboardShareSignature;
}

class _HomeDashboardState extends _HomeDashboardStateBase
    with
        _HomeDashboardAiMixin,
        _HomeDashboardLifecycleMixin,
        _HomeDashboardNavigationMixin,
        _HomeDashboardPomodoroMixin,
        _HomeDashboardBannerMixin,
        _HomeDashboardDataMixin,
        _HomeDashboardPersistenceMixin,
        _HomeDashboardWallpaperMixin,
        _HomeDashboardViewMixin {}

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

class _WallpaperNetworkImage extends StatefulWidget {
  final String url;
  final VoidCallback onSuccess;
  final VoidCallback onError;
  final void Function(ImageProvider)? onImageProvider;

  const _WallpaperNetworkImage({
    required this.url,
    required this.onSuccess,
    required this.onError,
    this.onImageProvider,
  });

  @override
  State<_WallpaperNetworkImage> createState() => _WallpaperNetworkImageState();
}

class _WallpaperNetworkImageState extends State<_WallpaperNetworkImage> {
  bool _reported = false;

  @override
  void didUpdateWidget(covariant _WallpaperNetworkImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      _reported = false;
    }
  }

  void _reportSuccess(ImageProvider provider) {
    if (_reported) return;
    _reported = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      widget.onSuccess();
      widget.onImageProvider?.call(provider);
    });
  }

  void _reportFailure() {
    if (_reported) return;
    _reported = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      widget.onError();
      widget.onImageProvider
          ?.call(const AssetImage('assets/images/default_wallpaper.webp'));
    });
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.sizeOf(context);
    final pixelRatio = MediaQuery.devicePixelRatioOf(context);
    final cacheWidth =
        (media.width * pixelRatio).round().clamp(1, 4096).toInt();
    final cacheHeight =
        (media.height * pixelRatio).round().clamp(1, 4096).toInt();
    return CachedNetworkImage(
      imageUrl: widget.url,
      cacheManager: WallpaperCacheService.cacheManager,
      fit: BoxFit.cover,
      memCacheWidth: cacheWidth,
      memCacheHeight: cacheHeight,
      fadeInDuration: const Duration(milliseconds: 350),
      useOldImageOnUrlChange: true,
      httpHeaders: const {
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36',
      },
      imageBuilder: (context, provider) {
        _reportSuccess(provider);
        return Image(
          image: provider,
          fit: BoxFit.cover,
          filterQuality: FilterQuality.medium,
        );
      },
      placeholder: (context, url) => Image.asset(
        'assets/images/default_wallpaper.webp',
        fit: BoxFit.cover,
      ),
      errorWidget: (context, url, error) {
        _reportFailure();
        return Image.asset(
          'assets/images/default_wallpaper.webp',
          fit: BoxFit.cover,
        );
      },
    );
  }
}
