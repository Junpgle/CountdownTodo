import 'dart:async';
import 'dart:ui';
import 'package:flutter/foundation.dart'; // 引入 kIsWeb
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
// video_player_win plugin
// webview_win_floating plugin
import 'package:shared_preferences/shared_preferences.dart';

import 'update_service.dart';
import 'utils/page_transitions.dart';
import 'utils/app_platform.dart';
import 'screens/login_screen.dart';
import 'screens/home_dashboard.dart';
import 'screens/team_management_screen.dart';
import 'screens/feature_guide_screen.dart';
import 'screens/splash_screen.dart';
import 'screens/default_splash_screen.dart';
import 'screens/share_view_screen.dart';
import 'services/team_share_link.dart';
import 'services/api_service.dart';
import 'widgets/privacy_policy_dialog.dart';
import 'storage_service.dart';
import 'models.dart';
import 'services/float_window_service.dart';
import 'services/window_service.dart';
import 'services/band_sync_service.dart';
import 'services/notification_service.dart';
import 'services/android_window_rendering_policy.dart';
import 'services/pomodoro_service.dart';
import 'widgets/macos_menu_bar.dart';
import 'services/pomodoro_sync_service.dart';
import 'services/widget_service.dart';
import 'services/splash_service.dart';
import 'services/course_service.dart';
import 'services/environment_service.dart';
import 'services/app_deep_link_service.dart';
import 'services/platform_bootstrap.dart';
import 'services/minor_mode_service.dart';
import 'services/liquid_glass_effect_service.dart';
import 'services/power_save_mode_service.dart';
import 'theme/app_liquid_glass_theme.dart';
import 'widgets/island_debug_host.dart';

import 'utils/navigator_utils.dart';
import 'utils/url_hash.dart';
import 'utils/app_performance_monitor.dart';
import 'utils/system_ui_style.dart';

typedef CloseDialogCallback = Future<bool> Function();
CloseDialogCallback? _onShowCloseDialog;

const String _webFontFamily = 'NotoSansCJKsc';
const List<String> _webFontFamilyFallback = [
  'PingFang SC',
  'Hiragino Sans GB',
  'Microsoft YaHei',
  'Noto Sans CJK SC',
  'Noto Sans SC',
  'Source Han Sans SC',
  'Arial Unicode MS',
  'sans-serif',
];

void registerCloseDialogCallback(CloseDialogCallback callback) {
  _onShowCloseDialog = callback;
}

Future<bool> showCloseDialog() async {
  // debugPrint('[Main] showCloseDialog requested');
  if (_onShowCloseDialog != null) {
    try {
      final result = await _onShowCloseDialog!();
      // debugPrint('[Main] Dialog result: $result');
      return result;
    } catch (e) {
      // debugPrint('[Main] Error in close dialog callback: $e');
    }
  }
  // debugPrint(
  //     '[Main] No callback registered or error occurred, allowing close by default');
  return true;
}

Future<T?> _runStartupTask<T>(
  String label,
  Future<T> future, {
  Duration timeout = const Duration(seconds: 3),
}) async {
  try {
    return await future.timeout(timeout);
  } catch (e) {
    // debugPrint('[Main] $label startup skipped: $e');
    return null;
  }
}

Future<void> _initializePlatformBeforeHome(List<String> args) async {
  // Read Android Battery Saver first, then start the independent tasks together
  // while the Flutter splash is visible. This prevents optional shader warm-up
  // from racing ahead of the system low-power override.
  // Bind the deep-link channel before starting the other platform tasks. A
  // synchronous startup failure in an earlier task must not prevent a widget
  // intent from being captured during a cold start.
  final deepLinkReady = _runStartupTask(
    'AppDeepLinkService.init',
    AppDeepLinkService.init(args),
    timeout: const Duration(seconds: 2),
  );
  await _runStartupTask(
    'PowerSaveModeService.initialize',
    PowerSaveModeService.initialize(),
    timeout: const Duration(seconds: 1),
  );
  final powerSaveMode = PowerSaveModeService.isEnabled;
  PageTransitions.setPowerSaveMode(powerSaveMode);
  await LiquidGlassEffectService.setPowerSaveMode(powerSaveMode);
  await Future.wait<dynamic>([
    _runStartupTask(
      'NotificationService.bindNativeChannel',
      NotificationService.bindNativeChannel(),
      timeout: const Duration(seconds: 1),
    ),
    _runStartupTask(
      'AndroidWindowRenderingPolicy.initialize',
      AndroidWindowRenderingPolicy.initialize(),
      timeout: const Duration(seconds: 1),
    ),
    _runStartupTask(
      'PlatformBootstrap.initDatabaseFactory',
      PlatformBootstrap.initDatabaseFactory(),
      timeout: const Duration(seconds: 2),
    ),
    _runStartupTask(
      'PageTransitions.init',
      PageTransitions.init(),
      timeout: const Duration(seconds: 1),
    ),
    deepLinkReady,
    _runStartupTask(
      'WindowService.init',
      PlatformBootstrap.initWindowService(),
      timeout: const Duration(seconds: 3),
    ),
    _runStartupTask(
      'MinorModeService.initialize',
      MinorModeService.instance.initialize(),
      timeout: const Duration(seconds: 2),
    ),
    _runStartupTask(
      'LiquidGlassEffectService.initialize',
      LiquidGlassEffectService.initialize(),
      timeout: const Duration(seconds: 2),
    ),
  ]);
}

String? _detectInitialShareCode() {
  if (!kIsWeb) return null;

  final routes = <String>[];
  try {
    routes.add(getUrlHash());
  } catch (_) {}
  try {
    routes.add(Uri.base.toString());
  } catch (_) {}

  for (final route in routes) {
    final code = TeamShareLink.codeFromRoute(route);
    if (code != null && code.isNotEmpty) return code;
  }
  return null;
}

void _configureRuntimeCaches({bool powerSaveMode = false}) {
  final imageCache = PaintingBinding.instance.imageCache;
  if (AppPlatform.isWeb) {
    imageCache.maximumSize = 120;
    imageCache.maximumSizeBytes = 80 << 20; // 80MB
    return;
  }

  if (AppPlatform.isMobile) {
    final useAndroidPowerSaveCache = AppPlatform.isAndroid && powerSaveMode;
    imageCache.maximumSize = useAndroidPowerSaveCache ? 64 : 100;
    imageCache.maximumSizeBytes = (useAndroidPowerSaveCache ? 64 : 96) << 20;
  } else {
    imageCache.maximumSize = 180;
    imageCache.maximumSizeBytes = 192 << 20; // Desktop 192MB
  }

  // 启动时清理一次悬挂的 live image 引用，降低冷启动内存峰值。
  imageCache.clearLiveImages();
}

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  AppPerformanceMonitor.install();
  unawaited(AppPerformanceMonitor.loadSettings());

  await AppSystemUiStyle.enableEdgeToEdge(
    initialBrightness:
        WidgetsBinding.instance.platformDispatcher.platformBrightness,
  );

  // Secondary desktop_multi_window engines must not run the main-window
  // startup chain. In release this can keep the island from ever reaching its
  // own entrypoint, leaving the floating window alive but data-less.
  if (await PlatformBootstrap.routeSecondaryWindow(args)) {
    return;
  }

  _configureRuntimeCaches();

  // 原生端绕过 SSL 证书验证，解决迁移时旧服务器握手失败问题；Web 端 no-op。
  PlatformBootstrap.configureHttpOverrides();

  final platformReady = _initializePlatformBeforeHome(args);

  // 预热 SharedPreferences 缓存，避免启动时多次重复 load
  unawaited(StorageService.prefs);

  // Register island entry as a tear-off so the desktop_multi_window plugin
  // can start a new Dart isolate using this symbol name. The plugin expects
  // the entrypoint to be available; when creating windows it passes the
  // entrypoint string (we use 'island') and the native side will launch an
  // isolate that invokes this function.
  // Note: desktop_multi_window typically locates a top-level function by
  // name; ensure your build includes this symbol. We expose `islandMain` by
  // importing island_entry above.
  // There's no extra code required here; the `island_entry.islandMain`
  // function is available as a top-level symbol when compiled.

  // 立刻运行 App。平台初始化在开屏可见期间并行完成，避免原生启动页
  // 因多个串行 timeout 最坏阻塞数秒。
  final initialShareCode = _detectInitialShareCode();
  runApp(
    LiquidGlassWidgets.wrap(
      child: MyApp(
        platformReady: platformReady,
        initialShareCode: initialShareCode,
      ),
      brightnessResolver: Theme.maybeBrightnessOf,
    ),
  );
}

class MyApp extends StatefulWidget {
  const MyApp({super.key, this.platformReady, this.initialShareCode});

  final Future<void>? platformReady;
  final String? initialShareCode;

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  static const int _isolateTransformThreshold = 60;
  static const Duration _systemUiRestoreDelay = Duration(milliseconds: 150);

  String? _loggedInUser;
  bool _isChecking = true;
  bool _showFeatureGuide = false;
  Map<String, dynamic>? _splashContent;
  bool _showDefaultSplash = true;
  bool _showHolidaySplash = false;
  bool _showPrivacyUpdate = false;
  bool _defaultSplashCompleted = false;
  bool _splashSequenceReady = false;
  bool _windowReadyForSplashTransition = true;
  bool _deepLinkConsumptionScheduled = false;
  Timer? _defaultSplashFallbackTimer;
  Timer? _systemUiRestoreTimer;
  String? _shareCode;

  @override
  void initState() {
    super.initState();
    if (AppPlatform.isAndroid) {
      WidgetsBinding.instance.addObserver(this);
      PowerSaveModeService.enabledListenable
          .addListener(_handlePowerSaveModeChanged);
      _handlePowerSaveModeChanged();
    }
    _shareCode = widget.initialShareCode;
    // ── 最先检查分享路由，避免启动多余逻辑 ──
    _checkShareRoute();
    _windowReadyForSplashTransition =
        AppPlatform.isWeb || !AppPlatform.isDesktop;
    WindowService.onShowCloseConfirm = _showCloseConfirmDialog;
    if (_shareCode == null) {
      // Web release 模式下 URL hash 可能延迟加载，首帧后再检查一次
      if (kIsWeb) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_shareCode == null) {
            _checkShareRoute();
            if (_shareCode != null && mounted) setState(() {});
          }
        });
        // 再给一次机会，防止首帧时 hash 仍未就绪
        Timer(const Duration(milliseconds: 300), () {
          if (_shareCode == null) {
            _checkShareRoute();
            if (_shareCode != null && mounted) setState(() {});
          }
        });
      }
      _defaultSplashFallbackTimer =
          Timer(const Duration(milliseconds: 1500), _onDefaultSplashComplete);
      _scheduleSplashReadinessFallback();
      _initializeApp();
      _startSplashSequence();
    }
  }

  @override
  void didChangeMetrics() {
    _scheduleSystemUiRestore();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(PowerSaveModeService.refresh());
      WidgetService.setAppForeground(true);
      _scheduleSystemUiRestore();
    } else if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      WidgetService.setAppForeground(false);
    }
  }

  @override
  void didHaveMemoryPressure() {
    if (!AppPlatform.isAndroid) return;

    // Android 17 can terminate a process that exceeds the device-specific
    // memory budget. Drop decoded images as soon as the framework signals
    // pressure so the next frame can rebuild only what is visible.
    final imageCache = PaintingBinding.instance.imageCache;
    imageCache.clear();
    imageCache.clearLiveImages();
  }

  void _handlePowerSaveModeChanged() {
    final enabled = PowerSaveModeService.isEnabled;
    PageTransitions.setPowerSaveMode(enabled);
    unawaited(LiquidGlassEffectService.setPowerSaveMode(enabled));
    _configureRuntimeCaches(powerSaveMode: enabled);
  }

  void _scheduleSystemUiRestore() {
    if (!AppPlatform.isAndroid) return;

    _systemUiRestoreTimer?.cancel();
    _systemUiRestoreTimer = Timer(_systemUiRestoreDelay, () {
      if (!mounted) return;
      unawaited(AppSystemUiStyle.restoreAfterWindowChange());
    });
  }

  void _checkShareRoute() {
    if (_shareCode == null) {
      final routes = <String>[];
      try {
        routes.add(getUrlHash());
      } catch (_) {}
      if (kIsWeb) {
        // Some browsers expose the hash late through window.location. Uri.base
        // gives us a second synchronous source during the first app build.
        try {
          routes.add(Uri.base.toString());
        } catch (_) {}
      }

      for (final route in routes) {
        final code = TeamShareLink.codeFromRoute(route);
        if (code != null && code.isNotEmpty) {
          _shareCode = code;
          break;
        }
      }
    }

    // 分享页会跳过常规启动流程，因此需要单独选择 Web API 入口。
    if (_shareCode != null && kIsWeb) {
      ApiService.setServerChoice('aliyun');
    }
  }

  Future<void> _startSplashSequence() async {
    Map<String, dynamic>? splashContent;
    try {
      // 异步获取节日开屏内容，不在这加延迟，让 DefaultSplashScreen 自己跑
      splashContent = await SplashService.getCachedContent()
          .timeout(const Duration(seconds: 1));
    } catch (e) {
      // debugPrint('[Main] 开屏缓存读取失败，跳过节日开屏: $e');
    }
    if (!mounted) return;
    setState(() {
      _splashContent = splashContent;
      // 避免竞态：如果默认开屏已结束但缓存稍后才返回，也要能切到节日开屏。
      if (_defaultSplashCompleted && splashContent != null) {
        _showHolidaySplash = true;
      }
    });
    _splashSequenceReady = true;
    if (_defaultSplashCompleted) _applySplashTransitionIfReady();
    _scheduleDeepLinkConsumption();
  }

  Future<bool> _showCloseConfirmDialog() async {
    // debugPrint('[Main] _showCloseConfirmDialog called, mounted=$mounted');

    if (!mounted) {
      // debugPrint('[Main] Widget not mounted, falling back to native dialog');
      return true;
    }

    final context = appNavigatorKey.currentContext;
    if (context == null) {
      // debugPrint(
      //     '[Main] appNavigatorKey.currentContext is null, falling back to native dialog');
      return true;
    }

    // 确保 Navigator 可用
    if (!context.mounted) {
      // debugPrint('[Main] Context not mounted, falling back to native dialog');
      return true;
    }

    try {
      // debugPrint('[Main] Attempting to show Flutter dialog...');
      final result = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          title: const Text('关闭确认'),
          content: const Text('选择操作：'),
          actions: [
            TextButton(
              onPressed: () {
                // debugPrint('[Main] User chose: minimize');
                Navigator.of(dialogContext).pop(false);
              },
              child: const Text('最小化到托盘'),
            ),
            TextButton(
              onPressed: () {
                // debugPrint('[Main] User chose: exit');
                Navigator.of(dialogContext).pop(true);
              },
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('退出程序'),
            ),
          ],
        ),
      ).timeout(
        const Duration(seconds: 3),
        onTimeout: () {
          // debugPrint('[Main] Dialog timeout, defaulting to false (minimize)');
          return false;
        },
      );
      // debugPrint('[Main] Dialog result: $result');
      return result ?? false;
    } catch (e) {
      // debugPrint('[Main] Dialog error (will use native fallback): $e');
      rethrow; // 抛出异常让 WindowService 使用原生对话框
    }
  }

  // 将所有耗时的初始化工作放到异步方法中
  Future<void> _initializeApp() async {
    try {
      // 🚀 核心优化：并发执行所有不互相依赖的初始化任务
      final results = await Future.wait([
        StorageService.initTheme(),
        EnvironmentService.init(),
        StorageService.getLoginSession(),
        StorageService.isPrivacyPolicyUpToDate(),
        StorageService.isPrivacyPolicyAgreed(),
        FeatureGuideScreen.shouldShow()
            .timeout(const Duration(seconds: 2), onTimeout: () => false),
        widget.platformReady ?? Future<void>.value(),
      ]).timeout(const Duration(seconds: 5));

      // 解析并发结果
      final String? user = results[2] as String?;
      final bool privacyNeedsUpdate = results[3] as bool;
      final bool wasAgreed = results[4] as bool;
      final bool needGuide = results[5] as bool;

      // 0.6 初始化壁纸(从manifest获取)，延后到首帧后避免占用启动关键路径
      SchedulerBinding.instance.addPostFrameCallback((_) {
        unawaited(UpdateService.initWallpaper());
      });

      final wasLoggedIn = user != null && user.isNotEmpty;

      // 3. 判断是否需要弹窗：已登录但未同意过，或版本已过期
      final shouldShowPrivacyDialog =
          wasLoggedIn && (!wasAgreed || !privacyNeedsUpdate);

      if (mounted) {
        setState(() {
          _loggedInUser = user;
          _showFeatureGuide = needGuide;
          _isChecking = false;
          _showPrivacyUpdate = shouldShowPrivacyDialog;
        });

        // 4. 如果需要弹窗，在界面渲染后弹出
        if (_showPrivacyUpdate) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _showPrivacyUpdateDialog();
          });
        }
        _scheduleDeepLinkConsumption();
      }
    } catch (e) {
      // debugPrint('[Main] 初始化失败: $e');
      if (mounted) {
        setState(() {
          _isChecking = false;
        });
        _scheduleDeepLinkConsumption();
      }
    }

    // 5. 异步初始化耗时的底层插件 (非关键路径)。
    // 推迟到首帧后执行，避免与首屏渲染竞争主线程时间片。
    SchedulerBinding.instance.addPostFrameCallback((_) {
      unawaited(_initHeavyPlugins());
      // 6. 初始化手环通信服务（全局）
      unawaited(_initBandService());
      // 7. 后台预取今天的开屏内容（不阻塞启动）
      unawaited(_prefetchSplashContent());
    });
  }

  void _scheduleSplashReadinessFallback() {
    if (AppPlatform.isWeb ||
        !AppPlatform.isDesktop ||
        _windowReadyForSplashTransition) {
      return;
    }

    // 桌面端窗口 ready 回调偶发不返回时，不能让默认开屏永久卡住。
    Future.delayed(const Duration(seconds: 3), () {
      if (!mounted || _windowReadyForSplashTransition) {
        return;
      }
      setState(() {
        _windowReadyForSplashTransition = true;
      });
      _applySplashTransitionIfReady();
    });
  }

  Future<void> _showPrivacyUpdateDialog() async {
    final navContext = appNavigatorKey.currentContext;
    if (navContext == null) return;
    final result = await showDialog<bool>(
      context: navContext,
      barrierDismissible: false,
      builder: (dialogContext) => PrivacyPolicyDialog(
        isUpdate: true,
        onAgree: () {
          StorageService.setPrivacyPolicyAgreed(true);
          Navigator.pop(dialogContext, true);
        },
        onDisagree: () async {
          await StorageService.clearLoginSession();
          final prefs = await SharedPreferences.getInstance();
          await prefs.clear();
          if (dialogContext.mounted) {
            Navigator.pop(dialogContext, false);
          }
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              setState(() {
                _loggedInUser = null;
              });
            }
          });
        },
      ),
    );
    if (result == false) {
      // 用户不同意更新后的隐私协议，退出登录并清除数据
      await StorageService.clearLoginSession();
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() {
            _loggedInUser = null;
          });
        }
      });
    }
  }

  Future<void> _prefetchSplashContent() async {
    try {
      await SplashService.fetchAndCacheTodayContent();
      await SplashService.prefetchTomorrowContent();
    } catch (e) {
      // debugPrint('[Main] 开屏内容预取失败: $e');
    }
  }

  void _onDefaultSplashComplete() {
    _defaultSplashFallbackTimer?.cancel();
    _defaultSplashFallbackTimer = null;
    _defaultSplashCompleted = true;
    _applySplashTransitionIfReady();
  }

  void _applySplashTransitionIfReady() {
    if (!_defaultSplashCompleted ||
        !_splashSequenceReady ||
        !_windowReadyForSplashTransition ||
        !mounted) {
      return;
    }
    final showHolidaySplash = _splashContent != null;
    if (mounted) {
      setState(() {
        _showDefaultSplash = false;
        // 如果有开屏图，切换到开屏图状态
        _showHolidaySplash = showHolidaySplash;
      });
    }
    if (!showHolidaySplash) _scheduleDeepLinkConsumption();
  }

  void _onHolidaySplashComplete() {
    if (mounted) {
      setState(() {
        _showHolidaySplash = false;
        _splashContent = null;
      });
      _scheduleDeepLinkConsumption();
    }
  }

  /// Wait until the authenticated root page and every startup splash route
  /// have settled before consuming a widget deep link. MaterialApp can rebuild
  /// its initial `/` route during the splash handoff; navigating earlier would
  /// leave the target page underneath that replacement route.
  void _scheduleDeepLinkConsumption() {
    if (!mounted ||
        !_splashSequenceReady ||
        !_defaultSplashCompleted ||
        _showDefaultSplash ||
        _showHolidaySplash ||
        _isChecking ||
        _deepLinkConsumptionScheduled) {
      return;
    }
    _deepLinkConsumptionScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _deepLinkConsumptionScheduled = false;
      if (!mounted ||
          !_splashSequenceReady ||
          !_defaultSplashCompleted ||
          _showDefaultSplash ||
          _showHolidaySplash ||
          _isChecking) {
        return;
      }
      unawaited(AppDeepLinkService.consumePendingAfterAppReady());
    });
  }

  StreamSubscription? _bandPomodoroSub;

  Future<void> _initBandService() async {
    if (!AppPlatform.isAndroid) return;

    try {
      await BandSyncService.init(
        onDeviceConnected: (info) {
          BandSyncService.registerListener();
        },
        onDeviceDisconnected: () {},
        onMessageReceived: (data) {
          // debugPrint('[Band] 收到消息: $data');
        },
        onPermissionGranted: (permissions) {
          // debugPrint('[Band] 权限已授予: $permissions');
          BandSyncService.registerListener();
        },
      );
    } catch (e) {
      // debugPrint('[Band] 初始化失败: $e');
    }

    // 设置同步数据提供者
    BandSyncService.setSyncDataProvider(_provideSyncData);

    // 全局监听手环番茄钟操作（finish/abandon）
    _bandPomodoroSub =
        BandSyncService.onBandPomodoroAction.listen((actionData) {
      final action = actionData['action']?.toString();
      // debugPrint('[Band] 番茄钟操作: $action');
      if (action == 'finish' || action == 'abandon') {
        _handleBandPomodoroAction(action!);
      }
    });
  }

  Future<List<Map<String, dynamic>>> _provideSyncData(String type) async {
    final user = _loggedInUser;
    if (user == null || user.isEmpty) return [];

    switch (type) {
      case 'todo':
        final todos = await StorageService.getTodos(user);
        return _transformForBand<TodoItem>(todos, _transformTodosForBand);

      case 'course':
        final courses = await CourseService.getAllCourses(user);
        return _transformForBand<dynamic>(courses, _transformCoursesForBand);

      case 'countdown':
        final countdowns = await StorageService.getCountdowns(user);
        return _transformForBand<CountdownItem>(
          countdowns,
          _transformCountdownsForBand,
        );

      case 'pomodoro':
        final records = await PomodoroService.getRecords();
        // 仅提供最近 30 条记录供手环查看，避免数据量过大
        final limitedRecords = records.take(30).toList();
        return _transformForBand<PomodoroRecord>(
          limitedRecords,
          _transformPomodorosForBand,
        );

      default:
        return [];
    }
  }

  Future<List<Map<String, dynamic>>> _transformForBand<T>(
    List<T> data,
    List<Map<String, dynamic>> Function(List<T>) transformer,
  ) async {
    if (data.length < _isolateTransformThreshold) {
      return transformer(data);
    }
    return compute(transformer, data);
  }

  // --- 静态转换方法，供 compute (Isolate) 调用 ---

  static List<Map<String, dynamic>> _transformTodosForBand(
      List<TodoItem> todos) {
    return todos.where((t) => !t.isDeleted && !t.isDone).map((t) {
      final j = t.toJson();
      j.remove('image_path');
      j.remove('imagePath');
      j.remove('original_text');
      j.remove('originalText');
      j.remove('conflict_data');
      j['is_completed'] = 0;
      j['content'] = t.title;
      if (t.dueDate != null) {
        j['due_date'] = t.dueDate!.millisecondsSinceEpoch;
      }
      if (t.createdDate != null) j['created_date'] = t.createdDate!;
      if (t.remark != null && t.remark!.isNotEmpty) j['remark'] = t.remark;
      return j;
    }).toList();
  }

  static List<Map<String, dynamic>> _transformCoursesForBand(
      List<dynamic> courses) {
    return courses
        .map((c) => (c as dynamic).toJson() as Map<String, dynamic>)
        .toList();
  }

  static List<Map<String, dynamic>> _transformCountdownsForBand(
      List<CountdownItem> countdowns) {
    return countdowns
        .where((c) => !c.isDeleted)
        .map((c) => c.toJson())
        .toList();
  }

  static List<Map<String, dynamic>> _transformPomodorosForBand(
      List<PomodoroRecord> records) {
    return records.map((r) => r.toJson()).toList();
  }

  Future<void> _handleBandPomodoroAction(String action) async {
    // debugPrint('[Band] _handleBandPomodoroAction called: $action');
    final runState = await PomodoroService.loadRunState();
    // debugPrint('[Band] loadRunState result: ${runState?.phase}');
    if (runState == null || runState.phase == PomodoroPhase.idle) {
      // debugPrint('[Band] 无运行中的番茄钟，忽略操作: $action');
      return;
    }

    // debugPrint('[Band] 处理手环操作: $action');
    if (action == 'finish') {
      final now = DateTime.now().millisecondsSinceEpoch;
      final record = PomodoroRecord.fromRunState(
        state: runState,
        status: PomodoroRecordStatus.completed,
        endMs: now,
      );
      await PomodoroService.addRecord(record);
      // debugPrint('[Band] Clearing run state');
      await PomodoroService.clearRunState();
    } else if (action == 'abandon') {
      final now = DateTime.now().millisecondsSinceEpoch;
      final actualSeconds = PomodoroRunState.computeActualSeconds(
          runState.sessionStartMs, runState.accumulatedMs,
          endMs: now);
      if (actualSeconds > 5) {
        final record = PomodoroRecord.fromRunState(
          state: runState,
          status: PomodoroRecordStatus.interrupted,
          endMs: now,
        );
        // debugPrint('[Band] Adding abandoned record: ${actualSeconds}s');
        await PomodoroService.addRecord(record);
      }
      // debugPrint('[Band] Clearing run state (abandon)');
      await PomodoroService.clearRunState();
      // debugPrint('[Band] 番茄钟已放弃');
    }
  }

  @override
  void dispose() {
    _defaultSplashFallbackTimer?.cancel();
    _systemUiRestoreTimer?.cancel();
    if (AppPlatform.isAndroid) {
      WidgetsBinding.instance.removeObserver(this);
      PowerSaveModeService.enabledListenable
          .removeListener(_handlePowerSaveModeChanged);
    }
    _bandPomodoroSub?.cancel();
    unawaited(FloatWindowService.dispose());
    BandSyncService.dispose();
    PomodoroService.dispose();
    PomodoroSyncService.instance.dispose();
    StorageService.dispose();
    WidgetService.dispose();
    unawaited(PowerSaveModeService.dispose());
    super.dispose();
  }

  Future<void> _initHeavyPlugins() async {
    try {
      await PlatformBootstrap.initMobileDownloader();
    } catch (e) {
      // debugPrint("Downloader init failed: $e");
    }

    if (AppPlatform.isDesktop) {
      PlatformBootstrap.waitUntilDesktopReady(
        onReady: () {
          if (mounted && !_windowReadyForSplashTransition) {
            setState(() {
              _windowReadyForSplashTransition = true;
            });
            _applySplashTransitionIfReady();
          }
        },
      );

      // 回退保护：避免极端情况下桌面窗口回调未触发导致流程阻塞。
      Future.delayed(const Duration(seconds: 3), () {
        if (!mounted || _windowReadyForSplashTransition) {
          return;
        }
        setState(() {
          _windowReadyForSplashTransition = true;
        });
        _applySplashTransitionIfReady();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    _checkShareRoute();

    return ValueListenableBuilder<String>(
      valueListenable: StorageService.themeNotifier,
      builder: (context, themeModeString, child) {
        ThemeMode currentThemeMode;
        switch (themeModeString) {
          case 'light':
            currentThemeMode = ThemeMode.light;
            break;
          case 'dark':
            currentThemeMode = ThemeMode.dark;
            break;
          default:
            currentThemeMode = ThemeMode.system;
        }

        return ValueListenableBuilder<String>(
          valueListenable: StorageService.themeColorModeNotifier,
          builder: (context, colorMode, _) {
            return ValueListenableBuilder<Color?>(
              valueListenable: StorageService.customThemeColorNotifier,
              builder: (context, customColor, _) {
                return ValueListenableBuilder<Color?>(
                  valueListenable: StorageService.appWallpaperColorNotifier,
                  builder: (context, appWallpaperColor, _) {
                    return DynamicColorBuilder(
                      builder: (ColorScheme? lightDynamic,
                          ColorScheme? darkDynamic) {
                        ColorScheme lightScheme;
                        ColorScheme darkScheme;

                        if (colorMode == 'system_wallpaper' &&
                            lightDynamic != null &&
                            darkDynamic != null) {
                          lightScheme = lightDynamic.harmonized();
                          darkScheme = darkDynamic.harmonized();
                        } else if ((colorMode == 'custom' ||
                                colorMode == 'image_extracted') &&
                            customColor != null) {
                          lightScheme = ColorScheme.fromSeed(
                              seedColor: customColor,
                              brightness: Brightness.light);
                          darkScheme = ColorScheme.fromSeed(
                              seedColor: customColor,
                              brightness: Brightness.dark);
                        } else if (colorMode == 'app_wallpaper' &&
                            appWallpaperColor != null) {
                          lightScheme = ColorScheme.fromSeed(
                              seedColor: appWallpaperColor,
                              brightness: Brightness.light);
                          darkScheme = ColorScheme.fromSeed(
                              seedColor: appWallpaperColor,
                              brightness: Brightness.dark);
                        } else {
                          lightScheme = ColorScheme.fromSeed(
                              seedColor: Theme.of(context).colorScheme.primary,
                              brightness: Brightness.light);
                          darkScheme = ColorScheme.fromSeed(
                              seedColor: Theme.of(context).colorScheme.primary,
                              brightness: Brightness.dark);
                        }

                        return ValueListenableBuilder<
                            LiquidGlassEffectConfiguration>(
                          valueListenable:
                              LiquidGlassEffectService.configurationListenable,
                          builder: (context, liquidGlassConfiguration, _) {
                            final lightTheme = applyAppLiquidGlassTheme(
                              ThemeData(
                                colorScheme: lightScheme,
                                useMaterial3: true,
                                fontFamily:
                                    AppPlatform.isWeb ? _webFontFamily : null,
                                fontFamilyFallback: AppPlatform.isWeb
                                    ? _webFontFamilyFallback
                                    : null,
                                pageTransitionsTheme: PageTransitions.theme,
                              ),
                              enabled: liquidGlassConfiguration.enabled,
                              mode: liquidGlassConfiguration.mode,
                            );
                            final darkTheme = applyAppLiquidGlassTheme(
                              ThemeData(
                                colorScheme: darkScheme,
                                useMaterial3: true,
                                fontFamily:
                                    AppPlatform.isWeb ? _webFontFamily : null,
                                fontFamilyFallback: AppPlatform.isWeb
                                    ? _webFontFamilyFallback
                                    : null,
                                pageTransitionsTheme: PageTransitions.theme,
                              ),
                              enabled: liquidGlassConfiguration.enabled,
                              mode: liquidGlassConfiguration.mode,
                            );

                            return MacosMenuBar(
                              child: MaterialApp(
                                title: 'CountDownTodo',
                                debugShowCheckedModeBanner: false,
                                navigatorKey: appNavigatorKey,
                                navigatorObservers: [
                                  AppPerformanceNavigatorObserver(),
                                ],
                                themeMode: currentThemeMode,
                                scrollBehavior:
                                    const MaterialScrollBehavior().copyWith(
                                  dragDevices: {
                                    PointerDeviceKind.mouse,
                                    PointerDeviceKind.touch,
                                    PointerDeviceKind.trackpad,
                                    PointerDeviceKind.stylus,
                                  },
                                ),
                                theme: lightTheme,
                                darkTheme: darkTheme,
                                localizationsDelegates: const [
                                  GlobalMaterialLocalizations.delegate,
                                  GlobalWidgetsLocalizations.delegate,
                                  GlobalCupertinoLocalizations.delegate,
                                ],
                                supportedLocales: const [
                                  Locale('zh', 'CN'),
                                  Locale('en', 'US'),
                                ],
                                routes: {
                                  '/login': (context) => const LoginScreen(),
                                  '/home': (context) => HomeDashboard(
                                      username: _loggedInUser ?? ''),
                                  '/teams': (context) => TeamManagementScreen(
                                      username: _loggedInUser ?? ''),
                                  '/dev/island': (context) =>
                                      IslandDebugHost.route(),
                                },
                                onGenerateRoute: (settings) {
                                  final name = settings.name ?? '';
                                  if (name.startsWith('/share')) {
                                    final code =
                                        TeamShareLink.codeFromRoute(name);
                                    if (code != null && code.isNotEmpty) {
                                      _shareCode = code;
                                      if (kIsWeb) {
                                        ApiService.setServerChoice('aliyun');
                                      }
                                      return MaterialPageRoute(
                                        builder: (_) =>
                                            ShareViewScreen(shareCode: code),
                                      );
                                    }
                                  }
                                  return null;
                                },
                                builder: (context, child) {
                                  final content =
                                      child ?? const SizedBox.shrink();
                                  final appContent =
                                      IslandDebugHost.shouldShowOverlay
                                          ? Stack(
                                              children: [
                                                content,
                                                IslandDebugHost.overlay(),
                                              ],
                                            )
                                          : content;

                                  return ValueListenableBuilder<bool>(
                                    valueListenable:
                                        AndroidWindowRenderingPolicy
                                            .disableShaderContentFade,
                                    child: appContent,
                                    builder: (context, _, child) {
                                      return ValueListenableBuilder<bool>(
                                        valueListenable: PowerSaveModeService
                                            .enabledListenable,
                                        child: child,
                                        builder:
                                            (context, powerSaveMode, child) {
                                          final content =
                                              child ?? const SizedBox.shrink();
                                          final mediaQuery =
                                              MediaQuery.maybeOf(context);
                                          final normalizedMediaQuery =
                                              mediaQuery == null
                                                  ? null
                                                  : AndroidWindowRenderingPolicy
                                                      .normalizeCompactWindowMediaQuery(
                                                      mediaQuery,
                                                    );
                                          final shouldDisableAnimations =
                                              AppPlatform.isAndroid &&
                                                  powerSaveMode;
                                          final effectiveMediaQuery =
                                              normalizedMediaQuery != null &&
                                                      shouldDisableAnimations &&
                                                      !normalizedMediaQuery
                                                          .disableAnimations
                                                  ? normalizedMediaQuery
                                                      .copyWith(
                                                      disableAnimations: true,
                                                    )
                                                  : normalizedMediaQuery;
                                          final adaptedContent =
                                              effectiveMediaQuery != null &&
                                                      !identical(
                                                        effectiveMediaQuery,
                                                        mediaQuery,
                                                      )
                                                  ? MediaQuery(
                                                      data: effectiveMediaQuery,
                                                      child: content,
                                                    )
                                                  : content;

                                          return AppSystemUiRegion(
                                            backgroundBrightness:
                                                Theme.of(context).brightness,
                                            child: adaptedContent,
                                          );
                                        },
                                      );
                                    },
                                  );
                                },
                                home: _shareCode != null
                                    ? ShareViewScreen(shareCode: _shareCode!)
                                    : _showDefaultSplash
                                        ? DefaultSplashScreen(
                                            onComplete:
                                                _onDefaultSplashComplete)
                                        : _showHolidaySplash
                                            ? SplashScreen(
                                                content: _splashContent!,
                                                onComplete:
                                                    _onHolidaySplashComplete,
                                              )
                                            : _isChecking
                                                ? Scaffold(
                                                    backgroundColor:
                                                        currentThemeMode ==
                                                                ThemeMode.dark
                                                            ? Colors.grey[900]
                                                            : Theme.of(context)
                                                                .colorScheme
                                                                .primary,
                                                    body: const Center(
                                                      child:
                                                          CircularProgressIndicator(
                                                              color:
                                                                  Colors.white),
                                                    ),
                                                  )
                                                : _showFeatureGuide
                                                    ? FeatureGuideScreen(
                                                        loggedInUser:
                                                            _loggedInUser)
                                                    : (_loggedInUser != null &&
                                                            _loggedInUser!
                                                                .isNotEmpty)
                                                        ? HomeDashboard(
                                                            key: ValueKey(
                                                                _loggedInUser),
                                                            username:
                                                                _loggedInUser!,
                                                          )
                                                        : const LoginScreen(),
                              ),
                            );
                          },
                        );
                      },
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }
}
