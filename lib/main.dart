import 'package:flutter/foundation.dart'; // 引入 kIsWeb
import 'package:flutter/material.dart';
import 'dart:io'; // 用于 Platform Check
import 'package:flutter_downloader/flutter_downloader.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:window_manager/window_manager.dart'; // Desktop 窗口管理

import 'screens/login_screen.dart';
import 'screens/home_dashboard.dart';
import 'storage_service.dart';

void main() {
  // 极速启动核心：绝对不要在 runApp 之前使用任何 await！
  WidgetsFlutterBinding.ensureInitialized();

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

  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  // 将所有耗时的初始化工作放到异步方法中
  Future<void> _initializeApp() async {
    // 1. 读取硬盘获取登录状态
    final user = await StorageService.getLoginSession();

    if (mounted) {
      setState(() {
        _loggedInUser = user;
        _isChecking = false; // 检查完毕，切换页面
      });
    }

    // 2. 异步初始化耗时的底层插件
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
    return MaterialApp(
      title: '效率 & 数学',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: Brightness.light,
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
      // 路由控制：如果在检查中，显示纯蓝屏+加载圈；检查完毕再跳转
      home: _isChecking
          ? const Scaffold(
        backgroundColor: Colors.blue,
        body: Center(
          child: CircularProgressIndicator(color: Colors.white),
        ),
      )
          : (_loggedInUser != null && _loggedInUser!.isNotEmpty
          ? HomeDashboard(username: _loggedInUser!)
          : const LoginScreen()),
    );
  }
}