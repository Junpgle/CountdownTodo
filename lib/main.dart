import 'package:flutter/material.dart';
import 'package:flutter_downloader/flutter_downloader.dart';
import 'screens/login_screen.dart';
import 'screens/home_screen.dart'; // 引入 Home Screen
import 'storage_service.dart'; // 引入 Storage Service

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 初始化下载插件
  try {
    await FlutterDownloader.initialize(
        debug: true,
        ignoreSsl: true
    );
  } catch (e) {
    print("Downloader init failed: $e");
  }

  // 关键修改：启动前检查是否已有保存的登录用户
  String? loggedInUser = await StorageService.getLoginSession();

  runApp(MyApp(initialUser: loggedInUser));
}

class MyApp extends StatelessWidget {
  final String? initialUser;

  // 构造函数接收初始用户
  const MyApp({super.key, this.initialUser});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '小学生数学测验系统',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      // 如果有保存的用户且不为空，直接进主页，否则进登录页
      home: initialUser != null && initialUser!.isNotEmpty
          ? HomeScreen(username: initialUser!)
          : const LoginScreen(),
    );
  }
}