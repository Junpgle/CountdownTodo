import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:countdown_todo/screens/pomodoro/views/stats_view.dart';
import 'package:countdown_todo/services/database_helper.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  const username = 'pomodoro_stats_test_user';

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({'current_login_user': username});
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    directory = await Directory.systemTemp.createTemp('pomodoro-stats-test-');
    await databaseFactory.setDatabasesPath(directory.path);
  });

  tearDownAll(() async {
    try {
      if (directory.existsSync()) {
        directory.deleteSync(recursive: true);
      }
    } catch (_) {}
  });

  setUp(() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('current_login_user', username);

    final db = await DatabaseHelper.instance.database;
    await db.delete('pomodoro_records');
  });

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump(const Duration(milliseconds: 200));
    }
  }

  testWidgets('月视图点击标题能弹出月份选择器并支持跳转', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: PomodoroStats(
            username: username,
            initialDimension: 2, // 月视图
            isCompact: false,
          ),
        ),
      ),
    );
    await settle(tester);

    // 标题处应包含下拉箭头
    expect(find.byIcon(Icons.arrow_drop_down_rounded), findsOneWidget);

    // 点击月份标题（如 2026年11月）
    final now = DateTime.now();
    final titleFinder = find.text(
      '${now.year}年${now.month.toString().padLeft(2, '0')}月',
    );
    expect(titleFinder, findsOneWidget);
    await tester.tap(titleFinder);
    await settle(tester);

    // 应弹出月份选择弹窗，包含月份网格
    expect(find.text('1月'), findsOneWidget);
    expect(find.text('2月'), findsOneWidget);
    expect(find.text('取消'), findsOneWidget);

    // 点击 1月 进行快速跳转
    await tester.tap(find.text('1月'));
    await settle(tester);

    // 标题应更新为 1月
    expect(find.text('${now.year}年01月'), findsOneWidget);
  });

  testWidgets('日视图与周视图均带有下拉选择指示并支持点击触发选择器', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: PomodoroStats(
            username: username,
            initialDimension: 0, // 日视图
            isCompact: false,
          ),
        ),
      ),
    );
    await settle(tester);

    // 日视图标题处带有下拉箭头
    expect(find.byIcon(Icons.arrow_drop_down_rounded), findsOneWidget);

    // 点击日视图标题
    final dropDownIcon = find.byIcon(Icons.arrow_drop_down_rounded);
    await tester.tap(dropDownIcon);
    await settle(tester);

    // 弹出了 showAppDatePicker 日期选择对话框
    expect(find.text('选择日期'), findsOneWidget);
    expect(find.text('取消'), findsOneWidget);

    // 取消弹窗
    await tester.tap(find.text('取消'));
    await settle(tester);

    // 切换到周视图
    await tester.tap(find.text('周'));
    await settle(tester);

    // 周视图标题处带有下拉箭头
    expect(find.byIcon(Icons.arrow_drop_down_rounded), findsOneWidget);

    // 点击周视图标题
    await tester.tap(find.byIcon(Icons.arrow_drop_down_rounded));
    await settle(tester);

    // 弹出周日期选择对话框
    expect(find.text('选择周内任意日期以跳转到该周'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await settle(tester);
  });

  testWidgets('年视图点击标题可正常弹出年份选择框', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: PomodoroStats(
            username: username,
            initialDimension: 3, // 年视图
            isCompact: false,
          ),
        ),
      ),
    );
    await settle(tester);

    expect(find.byIcon(Icons.arrow_drop_down_rounded), findsOneWidget);

    await tester.tap(find.byIcon(Icons.arrow_drop_down_rounded));
    await settle(tester);

    expect(find.text('选择年份'), findsOneWidget);
  });
}
