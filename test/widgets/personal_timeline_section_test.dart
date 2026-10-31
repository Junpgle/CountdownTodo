import 'dart:io';

import 'package:countdown_todo/features/finance/services/finance_storage.dart';
import 'package:countdown_todo/services/database_helper.dart';
import 'package:countdown_todo/widgets/optional_liquid_glass_surface.dart';
import 'package:countdown_todo/widgets/personal_timeline_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  const username = 'timeline_test_user';

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({'current_login_user': username});
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    directory = await Directory.systemTemp.createTemp(
      'personal-timeline-test-',
    );
    await databaseFactory.setDatabasesPath(directory.path);
    await FinanceStorage.ensureReady();
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
    await db.delete('todos');
    await db.delete('pomodoro_records');
    await db.delete('search_history');
  });

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 20; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump(const Duration(milliseconds: 100));
      if (find.byType(CircularProgressIndicator).evaluate().isEmpty) {
        break;
      }
    }
  }

  testWidgets('PersonalTimelineSection renders empty state cleanly', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: PersonalTimelineSection(username: username),
          ),
        ),
      ),
    );

    await settle(tester);

    expect(find.text('个人时间轴'), findsOneWidget);
    expect(find.text('今日暂无时光轨迹'), findsOneWidget);
    expect(find.textContaining('完成待办、习惯打卡或记录账单后'), findsOneWidget);
  });

  testWidgets(
    'PersonalTimelineSection renders timeline stream with events and collapse toggle',
    (tester) async {
      final now = DateTime.now();

      await tester.runAsync(() async {
        final db = await DatabaseHelper.instance.database;
        await db.insert('todos', {
          'uuid': 'todo-test-1',
          'content': '完成技术文档编写',
          'is_completed': 1,
          'is_deleted': 0,
          'created_at': now
              .subtract(const Duration(hours: 2))
              .millisecondsSinceEpoch,
          'updated_at': now
              .subtract(const Duration(hours: 2))
              .millisecondsSinceEpoch,
        });

        await db.insert('pomodoro_records', {
          'uuid': 'pomo-test-1',
          'todo_title': '系统重构专注',
          'tag_uuids': '[]',
          'start_time': now
              .subtract(const Duration(hours: 1))
              .millisecondsSinceEpoch,
          'end_time': now
              .subtract(const Duration(minutes: 35))
              .millisecondsSinceEpoch,
          'planned_duration': 1500,
          'actual_duration': 1500,
          'status': 'completed',
          'is_deleted': 0,
          'created_at': now.millisecondsSinceEpoch,
          'updated_at': now.millisecondsSinceEpoch,
        });
      });

      var tapCount = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: PersonalTimelineSection(
                username: username,
                onTap: () => tapCount++,
              ),
            ),
          ),
        ),
      );

      await settle(tester);

      // Verify Title & Tag Badge
      expect(find.text('个人时间轴'), findsOneWidget);
      expect(find.textContaining('项足迹'), findsWidgets);

      // Verify timeline stream content
      expect(find.text('完成技术文档编写'), findsNWidgets(2));
      expect(find.text('新增待办'), findsOneWidget);
      expect(find.text('完成待办'), findsOneWidget);
      expect(find.textContaining('系统重构专注'), findsWidgets);

      // Test collapse toggle
      final collapseBtn = find.byKey(
        const ValueKey<String>('timeline-toggle-collapse-btn'),
      );
      expect(collapseBtn, findsOneWidget);

      await tester.tap(collapseBtn);
      await settle(tester);

      // Stream should be collapsed
      expect(find.text('完成技术文档编写'), findsNothing);

      // Expand back
      await tester.tap(collapseBtn);
      await settle(tester);
      expect(find.text('完成技术文档编写'), findsNWidgets(2));

      // Test tap open button
      final openBtn = find.byKey(
        const ValueKey<String>('timeline-open-screen-btn'),
      );
      expect(openBtn, findsOneWidget);
      await tester.tap(openBtn);
      expect(tapCount, 1);
    },
  );

  testWidgets(
    'PersonalTimelineSection renders opaque fallback decoration when isLight is true',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: PersonalTimelineSection(username: username, isLight: true),
            ),
          ),
        ),
      );

      await settle(tester);

      final cardFinder = find.byType(OptionalLiquidGlassCard);
      expect(cardFinder, findsOneWidget);
      final card = tester.widget<OptionalLiquidGlassCard>(cardFinder);
      final decoration = card.fallbackDecoration as BoxDecoration;
      // When isLight is true in light mode, color opacity should be 0.92, NOT 0.15!
      expect(decoration.color?.a, closeTo(0.92, 0.01));
    },
  );
}
