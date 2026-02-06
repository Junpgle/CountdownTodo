import 'package:flutter/material.dart';
import 'package:flutter_downloader/flutter_downloader.dart'; // 新增引用
import 'screens/login_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 初始化下载插件
  await FlutterDownloader.initialize(
      debug: true, // 开发阶段开启调试日志
      ignoreSsl: true // 忽略SSL证书错误（可选）
  );

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '小学生数学测验系统',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const LoginScreen(),
    );
  }
}