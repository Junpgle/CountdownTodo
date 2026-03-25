import 'package:flutter/foundation.dart'; // 引入 kIsWeb
import 'package:flutter/material.dart';
import 'dart:io'; // 用于 Platform Check
import 'package:flutter_downloader/flutter_downloader.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:window_manager/window_manager.dart'; // Desktop 窗口管理
import 'package:video_player_win/video_player_win_plugin.dart'; // video_player_win plugin

import 'screens/login_screen.dart';
import 'screens/home_dashboard.dart';
import 'screens/feature_guide_screen.dart';
import 'storage_service.dart';
import 'services/api_service.dart';
import 'services/float_window_service.dart';
import 'windows_island/island_debug.dart';

final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

// 全局绕过 SSL 证书校验，修复 Cloudflare D1 旧服务器 HandshakeException
class MyHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)
      ..badCertificateCallback = (X509Certificate cert, String host, int port) => true;
  }
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // 绕过 SSL 证书验证，解决迁移时旧服务器握手失败问题
  HttpOverrides.global = MyHttpOverrides();

  // 初始化 FloatWindowService（注册 native handler）
  FloatWindowService.init();

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
    _initializeApp();
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

    if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
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