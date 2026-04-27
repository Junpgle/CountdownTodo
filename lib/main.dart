import 'dart:async';
import 'dart:ui';
import 'package:flutter/foundation.dart'; // 引入 kIsWeb
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'dart:io'; // 用于 Platform Check
import 'package:flutter_downloader/flutter_downloader.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:window_manager/window_manager.dart'; // Desktop 窗口管理
// video_player_win plugin
// webview_win_floating plugin
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'update_service.dart';
import 'utils/page_transitions.dart';
import 'screens/login_screen.dart';
import 'screens/home_dashboard.dart';
import 'screens/team_management_screen.dart';
import 'screens/feature_guide_screen.dart';
import 'screens/splash_screen.dart';
import 'screens/default_splash_screen.dart';
import 'widgets/privacy_policy_dialog.dart';
import 'storage_service.dart';
import 'models.dart';
import 'services/float_window_service.dart';
import 'services/window_service.dart';
import 'services/band_sync_service.dart';
import 'services/pomodoro_service.dart';
import 'services/pomodoro_sync_service.dart';
import 'services/widget_service.dart';
import 'services/splash_service.dart';
import 'services/course_service.dart';
import 'services/environment_service.dart';
import 'windows_island/island_debug.dart';
import 'windows_island/island_entry.dart' as island_entry;
import 'windows_island/island_ui.dart';

final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

typedef CloseDialogCallback = Future<bool> Function();
CloseDialogCallback? _onShowCloseDialog;

void registerCloseDialogCallback(CloseDialogCallback callback) {
  _onShowCloseDialog = callback;
}

Future<bool> showCloseDialog() async {
  debugPrint('[Main] showCloseDialog requested');
  if (_onShowCloseDialog != null) {
    try {
      final result = await _onShowCloseDialog!();
      debugPrint('[Main] Dialog result: $result');
      return result;
    } catch (e) {
      debugPrint('[Main] Error in close dialog callback: $e');
    }
  }
  debugPrint('[Main] No callback registered or error occurred, allowing close by default');
  return true;
}

// 全局绕过 SSL 证书校验，修复 Cloudflare D1 旧服务器 HandshakeException
class MyHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)
      ..badCertificateCallback =
          (X509Certificate cert, String host, int port) => true;
  }
}

void _configureRuntimeCaches() {
  final imageCache = PaintingBinding.instance.imageCache;
  if (kIsWeb) {
    imageCache.maximumSize = 120;
    imageCache.maximumSizeBytes = 80 << 20; // 80MB
    return;
  }

  if (Platform.isAndroid || Platform.isIOS) {
    imageCache.maximumSize = 100;
    imageCache.maximumSizeBytes = 96 << 20; // 96MB
  } else {
    imageCache.maximumSize = 180;
    imageCache.maximumSizeBytes = 192 << 20; // Desktop 192MB
  }

  // 启动时清理一次悬挂的 live image 引用，降低冷启动内存峰值。
  imageCache.clearLiveImages();
}

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  _configureRuntimeCaches();

  // 🚀 核心修复：桌面端 SQL 引擎初始化 (解决 databaseFactory not initialized)
  if (!kIsWeb && (Platform.isWindows || Platform.isLinux)) {
    debugPrint("🛠️ [Main] 检测到桌面平台，正在全局初始化 SQL FFI 引擎...");
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  await PageTransitions.init();

  // If this engine was launched by desktop_multi_window for a secondary
  // window, the embedder will pass arguments like: ["multi_window", windowId, windowArgument]
  // In that case we should route directly to the island entrypoint instead
  // of starting the full main app (which would spawn a duplicate main window).
  try {
    if (args.isNotEmpty && args[0] == 'multi_window') {
      // Delegate to island entrypoint. islandMain will call runApp for the
      // island UI and return.
      await island_entry.islandMain(args);
      return;
    }
  } catch (_) {}

  // 绕过 SSL 证书验证，解决迁移时旧服务器握手失败问题
  HttpOverrides.global = MyHttpOverrides();

  // 初始化 WindowService（监听窗口关闭事件）
  await WindowService.init();

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

  // 立刻运行 App，让引擎画出第一帧，彻底消除黑屏
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  static const int _isolateTransformThreshold = 60;

  late final ThemeData _lightTheme = ThemeData(
    colorScheme: ColorScheme.fromSeed(
      seedColor: Colors.blue,
      brightness: Brightness.light,
    ),
    useMaterial3: true,
  );

  late final ThemeData _darkTheme = ThemeData(
    colorScheme: ColorScheme.fromSeed(
      seedColor: Colors.blue,
      brightness: Brightness.dark,
    ),
    useMaterial3: true,
  );

  String? _loggedInUser;
  bool _isChecking = true;
  bool _showFeatureGuide = false;
  Map<String, dynamic>? _splashContent;
  bool _showDefaultSplash = true;
  bool _showHolidaySplash = false;
  bool _showPrivacyUpdate = false;
  bool _defaultSplashCompleted = false;
  bool _windowReadyForSplashTransition = true;

  @override
  void initState() {
    super.initState();
    _windowReadyForSplashTransition =
        kIsWeb || !(Platform.isWindows || Platform.isLinux || Platform.isMacOS);
    registerCloseDialogCallback(_showCloseConfirmDialog);
    // 立即开始初始化，不等待首屏动画
    _initializeApp();
    // 处理开屏序列逻辑
    _startSplashSequence();
  }

  Future<void> _startSplashSequence() async {
    // 异步获取节日开屏内容，不在这加延迟，让 DefaultSplashScreen 自己跑
    final splashContent = await SplashService.getCachedContent();
    if (mounted) {
      setState(() {
        _splashContent = splashContent;
        // 避免竞态：如果默认开屏已结束但缓存稍后才返回，也要能切到节日开屏。
        if (_defaultSplashCompleted && splashContent != null) {
          _showHolidaySplash = true;
        }
      });
    }
  }

  Future<bool> _showCloseConfirmDialog() async {
    if (!mounted) return true;

    final context = appNavigatorKey.currentContext;
    if (context == null) {
      debugPrint('[Main] appNavigatorKey.currentContext is null');
      return true;
    }

    try {
      final result = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          title: const Text('关闭确认'),
          content: const Text('选择操作：'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('最小化到托盘'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('退出程序'),
            ),
          ],
        ),
      );
      return result ?? false;
    } catch (e) {
      debugPrint('[Main] Dialog error: $e');
      return true;
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
      ]);

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
      }
    } catch (e) {
      debugPrint('[Main] 初始化失败: $e');
      if (mounted) {
        setState(() {
          _isChecking = false;
        });
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
          if (mounted) {
            setState(() {
              _loggedInUser = null;
            });
          }
          Navigator.pop(dialogContext, false);
        },
      ),
    );
    if (result == false) {
      // 用户不同意更新后的隐私协议，退出登录并清除数据
      await StorageService.clearLoginSession();
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();
      if (mounted) {
        setState(() {
          _loggedInUser = null;
        });
      }
    }
  }

  Future<void> _prefetchSplashContent() async {
    try {
      await SplashService.fetchAndCacheTodayContent();
      await SplashService.prefetchTomorrowContent();
    } catch (e) {
      debugPrint('[Main] 开屏内容预取失败: $e');
    }
  }

  void _onDefaultSplashComplete() {
    _defaultSplashCompleted = true;
    _applySplashTransitionIfReady();
  }

  void _applySplashTransitionIfReady() {
    if (!_defaultSplashCompleted || !_windowReadyForSplashTransition || !mounted) {
      return;
    }
    if (mounted) {
      setState(() {
        _showDefaultSplash = false;
        // 如果有开屏图，切换到开屏图状态
        if (_splashContent != null) {
          _showHolidaySplash = true;
        }
      });
    }
  }

  void _onHolidaySplashComplete() {
    if (mounted) {
      setState(() {
        _showHolidaySplash = false;
        _splashContent = null;
      });
    }
  }

  StreamSubscription? _bandPomodoroSub;

  Future<void> _initBandService() async {
    try {
      await BandSyncService.init(
        onDeviceConnected: (info) {
          BandSyncService.registerListener();
        },
        onDeviceDisconnected: () {
        },
        onMessageReceived: (data) {
          debugPrint('[Band] 收到消息: $data');
        },
        onPermissionGranted: (permissions) {
          debugPrint('[Band] 权限已授予: $permissions');
          BandSyncService.registerListener();
        },
      );
    } catch (e) {
      debugPrint('[Band] 初始化失败: $e');
    }

    // 设置同步数据提供者
    BandSyncService.setSyncDataProvider(_provideSyncData);

    // 全局监听手环番茄钟操作（finish/abandon）
    _bandPomodoroSub =
        BandSyncService.onBandPomodoroAction.listen((actionData) {
      final action = actionData['action']?.toString();
      debugPrint('[Band] 番茄钟操作: $action');
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

  static List<Map<String, dynamic>> _transformTodosForBand(List<TodoItem> todos) {
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

  static List<Map<String, dynamic>> _transformCoursesForBand(List<dynamic> courses) {
    return courses.map((c) => (c as dynamic).toJson() as Map<String, dynamic>).toList();
  }

  static List<Map<String, dynamic>> _transformCountdownsForBand(List<CountdownItem> countdowns) {
    return countdowns
        .where((c) => !c.isDeleted)
        .map((c) => c.toJson())
        .toList();
  }

  static List<Map<String, dynamic>> _transformPomodorosForBand(List<PomodoroRecord> records) {
    return records.map((r) => r.toJson()).toList();
  }




  Future<void> _handleBandPomodoroAction(String action) async {
    debugPrint('[Band] _handleBandPomodoroAction called: $action');
    final runState = await PomodoroService.loadRunState();
    debugPrint('[Band] loadRunState result: ${runState?.phase}');
    if (runState == null || runState.phase == PomodoroPhase.idle) {
      debugPrint('[Band] 无运行中的番茄钟，忽略操作: $action');
      return;
    }

    debugPrint('[Band] 处理手环操作: $action');
    if (action == 'finish') {
      final now = DateTime.now().millisecondsSinceEpoch;
      final actualSeconds = ((now - runState.sessionStartMs) / 1000).round();
      final plannedSeconds = runState.plannedFocusSeconds;
      final record = PomodoroRecord(
        startTime: runState.sessionStartMs,
        endTime: now,
        plannedDuration: plannedSeconds,
        actualDuration: actualSeconds,
        tagUuids: runState.tagUuids,
        todoUuid: runState.todoUuid,
        todoTitle: runState.todoTitle,
        status: PomodoroRecordStatus.completed,
      );
      debugPrint('[Band] Adding record: ${actualSeconds}s');
      await PomodoroService.addRecord(record);
      debugPrint('[Band] Clearing run state');
      await PomodoroService.clearRunState();
      debugPrint('[Band] 番茄钟已完成，已记录 ${actualSeconds}s');
    } else if (action == 'abandon') {
      debugPrint('[Band] Clearing run state (abandon)');
      await PomodoroService.clearRunState();
      debugPrint('[Band] 番茄钟已放弃');
    }
  }

  @override
  void dispose() {
    _bandPomodoroSub?.cancel();
    BandSyncService.dispose();
    PomodoroService.dispose();
    PomodoroSyncService.instance.dispose();
    StorageService.dispose();
    WidgetService.dispose();
    super.dispose();
  }

  Future<void> _initHeavyPlugins() async {
    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
      try {
        await FlutterDownloader.initialize(debug: kDebugMode, ignoreSsl: true);
      } catch (e) {
        debugPrint("Downloader init failed: $e");
      }
    }

    if (!kIsWeb &&
        (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
      await windowManager.ensureInitialized();
      WindowOptions windowOptions = const WindowOptions(
        size: Size(1280, 720),
        center: true,
        backgroundColor: Colors.transparent,
        skipTaskbar: false,
        titleBarStyle: TitleBarStyle.normal,
      );
      windowManager.waitUntilReadyToShow(windowOptions, () async {
        if (mounted && !_windowReadyForSplashTransition) {
          setState(() {
            _windowReadyForSplashTransition = true;
          });
          _applySplashTransitionIfReady();
        }
        await windowManager.show();
        await windowManager.focus();
        // Try to create the island window on Windows. Before creating, probe
        // whether desktop_multi_window exposes the core methods we need. If
        // not, we'll fall back to an in-layout island overlay powered by
        // FloatWindowService.debugPayload.
        if (Platform.isWindows) {
          try {
            await FloatWindowService.init();
            // 岛窗口由 HomeDashboard 加载后统一创建, 避免启动竞争
          } catch (e) {
            debugPrint('FloatWindowService init failed: $e');
          }
        }
      });

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

        return MaterialApp(
          title: 'CountDownTodo',
          debugShowCheckedModeBanner: false,
          navigatorKey: appNavigatorKey,
          themeMode: currentThemeMode,
          scrollBehavior: const MaterialScrollBehavior().copyWith(
            dragDevices: {
              PointerDeviceKind.mouse,
              PointerDeviceKind.touch,
              PointerDeviceKind.trackpad,
              PointerDeviceKind.stylus,
            },
          ),
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(
              seedColor: Colors.blue,
              brightness: Brightness.light,
            ),
            useMaterial3: true,
          ),
          darkTheme: ThemeData(
            colorScheme: ColorScheme.fromSeed(
              seedColor: Colors.blue,
              brightness: Brightness.dark,
            ),
            useMaterial3: true,
          ),
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
            '/home': (context) => HomeDashboard(username: _loggedInUser ?? ''),
            '/teams': (context) => TeamManagementScreen(username: _loggedInUser ?? ''),
            '/dev/island': (context) => const IslandDebugPage(),
          },
          builder: (context, child) {
            final content = child ?? const SizedBox.shrink();
            if (!(Platform.isWindows && kDebugMode)) {
              return content;
            }

            return Stack(
              children: [
                content,
                ValueListenableBuilder<Map<String, dynamic>?>(
                  valueListenable: FloatWindowService.debugPayload,
                  builder: (context, payload, _) {
                    if (payload == null || payload.isEmpty) {
                      return const SizedBox.shrink();
                    }
                    return Positioned(
                      top: 16,
                      right: 16,
                      child: SizedBox(
                        width: 380,
                        height: 220,
                        child: IslandUI(
                          inLayoutDebugMode: true,
                          payloadNotifier: FloatWindowService.debugPayload,
                          initialPayload: payload,
                        ),
                      ),
                    );
                  },
                ),
              ],
            );
          },
          home: _showDefaultSplash
              ? DefaultSplashScreen(onComplete: _onDefaultSplashComplete)
              : _showHolidaySplash
                  ? SplashScreen(
                      content: _splashContent!,
                      onComplete: _onHolidaySplashComplete,
                    )
                  : _isChecking
                      ? Scaffold(
                          backgroundColor: currentThemeMode == ThemeMode.dark
                              ? Colors.grey[900]
                              : Colors.blue,
                          body: const Center(
                            child:
                                CircularProgressIndicator(color: Colors.white),
                          ),
                        )
                      : _showFeatureGuide
                          ? FeatureGuideScreen(loggedInUser: _loggedInUser)
                          : (_loggedInUser != null && _loggedInUser!.isNotEmpty)
                              ? HomeDashboard(
                                  key: ValueKey(_loggedInUser),
                                  username: _loggedInUser!,
                                )
                              : const LoginScreen(),
        );
      },
    );
  }
}
