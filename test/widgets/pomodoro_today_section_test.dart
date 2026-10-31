import 'dart:io';

import 'package:countdown_todo/services/database_helper.dart';
import 'package:countdown_todo/services/pomodoro_service.dart';
import 'package:countdown_todo/widgets/pomodoro_today_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  const username = 'pomodoro_test_user';

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({'current_login_user': username});
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    directory = await Directory.systemTemp.createTemp('pomodoro-today-test-');
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

  testWidgets('PomodoroTodaySection renders empty state cleanly', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: PomodoroTodaySection(username: username),
          ),
        ),
      ),
    );

    await settle(tester);

    expect(find.text('最近专注'), findsOneWidget);
    expect(find.text('今日'), findsOneWidget);
    expect(find.text('暂无专注记录'), findsOneWidget);
    expect(find.text('开启今日专注'), findsOneWidget);
  });

  testWidgets(
    'PomodoroTodaySection renders unified card with records and chart',
    (tester) async {
      final now = DateTime.now();
      final startToday = DateTime(now.year, now.month, now.day, 10, 0);

      final record1 = PomodoroRecord(
        uuid: 'rec-1',
        startTime: startToday.toUtc().millisecondsSinceEpoch,
        endTime: startToday
            .add(const Duration(minutes: 25))
            .toUtc()
            .millisecondsSinceEpoch,
        plannedDuration: 1500,
        actualDuration: 1500,
        status: PomodoroRecordStatus.completed,
        todoTitle: '写代码与测试',
      );

      final record2 = PomodoroRecord(
        uuid: 'rec-2',
        startTime: startToday
            .add(const Duration(hours: 2))
            .toUtc()
            .millisecondsSinceEpoch,
        endTime: startToday
            .add(const Duration(hours: 2, minutes: 45))
            .toUtc()
            .millisecondsSinceEpoch,
        plannedDuration: 2700,
        actualDuration: 2700,
        status: PomodoroRecordStatus.completed,
        todoTitle: '阅读设计规范',
      );

      await tester.runAsync(() async {
        final db = await DatabaseHelper.instance.database;
        await db.insert('pomodoro_records', {
          'uuid': record1.uuid,
          'todo_title': record1.todoTitle,
          'tag_uuids': '[]',
          'start_time': record1.startTime,
          'end_time': record1.endTime,
          'planned_duration': record1.plannedDuration,
          'actual_duration': record1.actualDuration,
          'status': 'completed',
          'is_deleted': 0,
          'created_at': record1.createdAt,
          'updated_at': record1.updatedAt,
        });
        await db.insert('pomodoro_records', {
          'uuid': record2.uuid,
          'todo_title': record2.todoTitle,
          'tag_uuids': '[]',
          'start_time': record2.startTime,
          'end_time': record2.endTime,
          'planned_duration': record2.plannedDuration,
          'actual_duration': record2.actualDuration,
          'status': 'completed',
          'is_deleted': 0,
          'created_at': record2.createdAt,
          'updated_at': record2.updatedAt,
        });
      });

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: PomodoroTodaySection(username: username),
            ),
          ),
        ),
      );

      await settle(tester);

      // Verify Title & Tag
      expect(find.text('最近专注'), findsOneWidget);
      expect(find.text('今日'), findsOneWidget);

      // Total duration: 25 + 45 = 70 minutes = 1 hour 10 minutes
      expect(find.textContaining('1 时 10 分'), findsOneWidget);

      // Verify chips
      expect(find.text('2 次完成'), findsOneWidget);
      expect(find.text('均次 35分'), findsOneWidget);
      expect(find.text('最长 45分'), findsOneWidget);

      // Verify hourly chart header & records list
      expect(find.text('时段分布'), findsOneWidget);
      expect(find.text('专注明细'), findsOneWidget);
      expect(find.text('写代码与测试'), findsOneWidget);
      expect(find.text('阅读设计规范'), findsOneWidget);

      // Test collapse toggle
      final collapseBtn = find.byKey(
        const ValueKey<String>('pomodoro-toggle-collapse-btn'),
      );
      expect(collapseBtn, findsOneWidget);
      await tester.tap(collapseBtn);
      await settle(tester);

      // Detail section should be collapsed
      expect(find.text('写代码与测试'), findsNothing);
      // Core metrics should still be visible!
      expect(find.text('2 次完成'), findsOneWidget);

      // Expand back
      await tester.tap(collapseBtn);
      await settle(tester);

      expect(find.text('写代码与测试'), findsOneWidget);
    },
  );

  testWidgets(
    'PomodoroTodaySection distributes multi-hour session across multiple hours in chart',
    (tester) async {
      final now = DateTime.now();
      final start9am = DateTime(now.year, now.month, now.day, 9, 0);
      final end1150am = DateTime(now.year, now.month, now.day, 11, 50);

      final longRecord = PomodoroRecord(
        uuid: 'rec-long',
        startTime: start9am.toUtc().millisecondsSinceEpoch,
        endTime: end1150am.toUtc().millisecondsSinceEpoch,
        plannedDuration: 10200,
        actualDuration: 10200,
        status: PomodoroRecordStatus.completed,
        todoTitle: '深度研读技术文档',
      );

      await tester.runAsync(() async {
        final db = await DatabaseHelper.instance.database;
        await db.insert('pomodoro_records', {
          'uuid': longRecord.uuid,
          'todo_title': longRecord.todoTitle,
          'tag_uuids': '[]',
          'start_time': longRecord.startTime,
          'end_time': longRecord.endTime,
          'planned_duration': longRecord.plannedDuration,
          'actual_duration': longRecord.actualDuration,
          'status': 'completed',
          'is_deleted': 0,
          'created_at': longRecord.createdAt,
          'updated_at': longRecord.updatedAt,
        });
      });

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: PomodoroTodaySection(username: username),
            ),
          ),
        ),
      );

      await settle(tester);

      // Verify duration: 2 hours 50 minutes
      expect(find.textContaining('2 时 50 分'), findsOneWidget);

      // Verify peak hour shows 09:00 (1时)
      expect(find.textContaining('峰值 09:00 (1时)'), findsOneWidget);

      // Find the 24 hour bar GestureDetectors
      final hourBarsFinder = find.byWidgetPredicate((w) {
        if (w is GestureDetector && w.child is Column) {
          final col = w.child as Column;
          return col.children.any((c) => c is Expanded);
        }
        return false;
      });
      expect(hourBarsFinder, findsNWidgets(24));

      // Tap hour 10
      await tester.tap(hourBarsFinder.at(10));
      await settle(tester);
      expect(find.textContaining('10:00 - 11:00 · 1小时'), findsOneWidget);

      // Tap hour 11
      await tester.tap(hourBarsFinder.at(11));
      await settle(tester);
      expect(find.textContaining('11:00 - 12:00 · 50分'), findsOneWidget);
    },
  );

  testWidgets(
    'PomodoroTodaySection preserves content without showing spinner during background refreshTrigger update',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: PomodoroTodaySection(
                username: username,
                refreshTrigger: 0,
              ),
            ),
          ),
        ),
      );

      await settle(tester);
      expect(find.text('暂无专注记录'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);

      // Trigger background reload
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: PomodoroTodaySection(
                username: username,
                refreshTrigger: 1,
              ),
            ),
          ),
        ),
      );

      // Next frame should NOT switch to CircularProgressIndicator
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('暂无专注记录'), findsOneWidget);

      await settle(tester);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('暂无专注记录'), findsOneWidget);
    },
  );
}
