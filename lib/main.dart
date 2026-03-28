import 'package:flutter/foundation.dart'; // 引入 kIsWeb
import 'package:flutter/material.dart';
import 'dart:io'; // 用于 Platform Check
import 'package:flutter_downloader/flutter_downloader.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:window_manager/window_manager.dart'; // Desktop 窗口管理
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player_win/video_player_win_plugin.dart'; // video_player_win plugin

import 'screens/login_screen.dart';
import 'screens/home_dashboard.dart';
import 'screens/feature_guide_screen.dart';
import 'storage_service.dart';
import 'services/api_service.dart';
import 'services/float_window_service.dart';
import 'services/window_service.dart';
import 'windows_island/island_debug.dart';
import 'windows_island/island_entry.dart' as island_entry;
import 'windows_island/island_manager.dart';
import 'windows_island/island_ui.dart';

final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

typedef CloseDialogCallback = Future<bool> Function();
CloseDialogCallback? _onShowCloseDialog;

void registerCloseDialogCallback(CloseDialogCallback callback) {
  _onShowCloseDialog = callback;
}

Future<bool> showCloseDialog() async {
  debugPrint(
      '[Main] showCloseDialog called, callback: ${_onShowCloseDialog != null}');
  if (_onShowCloseDialog != null) {
    final result = await _onShowCloseDialog!();
    debugPrint('[Main] Dialog result: $result');
    return result;
  }
  debugPrint('[Main] No callback registered, allowing close');
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

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();

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

  // 初始化 FloatWindowService（注册 native handler）
  FloatWindowService.init();

  // 初始化 WindowService（监听窗口关闭事件）
  WindowService.init();

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
  String? _loggedInUser;
  bool _isChecking = true;
  bool _showFeatureGuide = false;

  @override
  void initState() {
    super.initState();
    registerCloseDialogCallback(_showCloseConfirmDialog);
    _initializeApp();
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
    // 0. 读取主题偏好
    await StorageService.initTheme();

    // Initialize server choice
    String serverChoice = await StorageService.getServerChoice();
    ApiService.setServerChoice(serverChoice);

    // 1. 读取登录状态
    final user = await StorageService.getLoginSession();

    // 2. 检查升级引导
    final needGuide = await FeatureGuideScreen.shouldShow();

    if (mounted) {
      setState(() {
        _loggedInUser = user;
        _showFeatureGuide = needGuide;
        _isChecking = false;
      });
    }

    // 3. 异步初始化耗时的底层插件
    _initHeavyPlugins();
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
      if (Platform.isWindows) {
        WindowsVideoPlayer.registerWith();
      }
      await windowManager.ensureInitialized();
      WindowOptions windowOptions = const WindowOptions(
        size: Size(1280, 720),
        center: true,
        backgroundColor: Colors.transparent,
        skipTaskbar: false,
        titleBarStyle: TitleBarStyle.normal,
      );
      windowManager.waitUntilReadyToShow(windowOptions, () async {
        await windowManager.show();
        await windowManager.focus();
        // Try to create the island window on Windows. Before creating, probe
        // whether desktop_multi_window exposes the core methods we need. If
        // not, we'll fall back to an in-layout island overlay powered by
        // FloatWindowService.debugPayload.
        if (Platform.isWindows) {
          try {
            await FloatWindowService.init();
            // Only create island if the setting is enabled (style == 1)
            final prefs = await SharedPreferences.getInstance();
            final style = prefs.getInt('float_window_style') ?? 0;
            if (style == 1) {
              await IslandManager().createIsland('island-1');
            }
          } catch (e) {
            debugPrint('Island create failed: $e');
          }
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // 关键点：使用 ValueListenableBuilder 监听全局主题状态
    return ValueListenableBuilder<String>(
      valueListenable: StorageService.themeNotifier,
      builder: (context, themeModeString, child) {
        // 将设置中的字符串映射为 Flutter 引擎识别的 ThemeMode
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

          // 绑定动态主题模式
          themeMode: currentThemeMode,

          // 配置浅色模式主题
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(
              seedColor: Colors.blue,
              brightness: Brightness.light,
            ),
            useMaterial3: true,
          ),

          // 核心修复：配置深色模式主题 (必须要配置这个，darkTheme 才生效)
          darkTheme: ThemeData(
            colorScheme: ColorScheme.fromSeed(
              seedColor: Colors.blue,
              brightness: Brightness.dark, // 设为暗色模式
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

          // 🚀 添加这一段
          routes: {
            '/login': (context) => const LoginScreen(),
            '/home': (context) => HomeDashboard(username: _loggedInUser ?? ''),
            '/dev/island': (context) => const IslandDebugPage(),
          },

          // Inject an in-layout island overlay when needed via builder so it
          // sits above all routes. The overlay listens to
          // FloatWindowService.debugPayload to show an in-app island when
          // multi-window features are unavailable.
          builder: (context, child) {
            return Stack(
              children: [
                child ?? const SizedBox.shrink(),
                // In-layout island overlay
                const SizedBox.expand(child: SizedBox()),
                InLayoutIslandOverlay(),
              ],
            );
          },

          // 路由控制：加载中 → 升级引导 → 主页/登录
          // 若有进行中的番茄钟，先进主页，再由主页自动 push 番茄钟（保留返回栈）
          home: _isChecking
              ? Scaffold(
                  backgroundColor: currentThemeMode == ThemeMode.dark
                      ? Colors.grey[900]
                      : Colors.blue,
                  body: const Center(
                    child: CircularProgressIndicator(color: Colors.white),
                  ),
                )
              : _showFeatureGuide
                  ? FeatureGuideScreen(loggedInUser: _loggedInUser)
                  : (_loggedInUser != null && _loggedInUser!.isNotEmpty)
                      ? HomeDashboard(
                          username: _loggedInUser!,
                        )
                      : const LoginScreen(),
        );
      },
    );
  }
}

class InLayoutIslandOverlay extends StatefulWidget {
  const InLayoutIslandOverlay({super.key});

  @override
  State<InLayoutIslandOverlay> createState() => _InLayoutIslandOverlayState();
}

class _InLayoutIslandOverlayState extends State<InLayoutIslandOverlay> {
  Offset _pos = const Offset(40, 400);

  @override
  void initState() {
    super.initState();
    FloatWindowService.debugPayload.addListener(_onPayload);
  }

  void _onPayload() => setState(() {});

  @override
  void dispose() {
    FloatWindowService.debugPayload.removeListener(_onPayload);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final payload = FloatWindowService.debugPayload.value;
    if (payload == null) return const SizedBox.shrink();

    // Render a small draggable island in-layout
    return Positioned(
      left: _pos.dx,
      top: _pos.dy,
      child: GestureDetector(
        onPanUpdate: (d) => setState(() => _pos += d.delta),
        child: Material(
          elevation: 6,
          borderRadius: BorderRadius.circular(28),
          color: Colors.transparent,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 380, maxHeight: 300),
            child: IslandUI(initialPayload: payload),
          ),
        ),
      ),
    );
  }
}
