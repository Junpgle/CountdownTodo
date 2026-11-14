import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:countdown_todo/screens/about_screen.dart';
import 'package:countdown_todo/services/app_memory_monitor.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'enable_animations': false,
      'update_manifest_cache_time': DateTime.now().millisecondsSinceEpoch,
      'update_manifest_cache_json': jsonEncode({
        'version_name': '7.22.6',
        'version_code': 100,
        'update_info': {'title': '测试更新', 'description': '更新说明'},
      }),
    });
    PackageInfo.setMockInitialValues(
      appName: 'CountdownTodo',
      packageName: 'com.countdown.todo',
      version: '7.22.6',
      buildNumber: '100',
      buildSignature: '',
    );
    await AppMemoryMonitor.init();
    AppMemoryMonitor.setAutoRefresh(false);
  });

  tearDown(() {
    AppMemoryMonitor.setAutoRefresh(false);
  });

  testWidgets(
    'AboutScreen renders memory card with current usage and options',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: AboutScreen())),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // 验证内存占用与优化标题
      expect(find.text('内存占用与优化'), findsOneWidget);

      // 验证当前内存占用核心标签
      expect(find.text('当前占用内存'), findsOneWidget);

      // 验证内存选项：一键释放
      expect(find.text('一键释放图片缓存与内存'), findsOneWidget);

      // 验证内存选项：实时刷新开关
      expect(find.text('实时刷新内存占用'), findsOneWidget);

      // 验证内存选项：缓存策略
      expect(find.text('缓存策略'), findsOneWidget);

      // 点击一键释放按钮
      final cleanButton = find.text('一键释放图片缓存与内存');
      expect(cleanButton, findsOneWidget);
      await tester.tap(cleanButton);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
    },
  );
}
