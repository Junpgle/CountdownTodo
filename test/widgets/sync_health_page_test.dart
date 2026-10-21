import 'dart:convert';

import 'package:countdown_todo/screens/settings/pages/sync_health_page.dart';
import 'package:countdown_todo/storage_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/plan_availability_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late PlanAvailabilityFixture fixture;
  const username = PlanAvailabilityFixture.username;

  setUpAll(() {
    SharedPreferences.setMockInitialValues({
      'current_login_user': username,
      'current_user_id': 42,
    });
  });

  setUp(() async {
    fixture = PlanAvailabilityFixture();
    await fixture.initialize(resetPreferences: false);
    debugDefaultTargetPlatformOverride = fixture.previousPlatform;
    final prefs = await StorageService.prefs;
    await prefs.clear();
    await prefs.setString(StorageService.keyCurrentUser, username);
    await prefs.setInt('current_user_id', 42);
  });

  tearDown(() async {
    await fixture.dispose();
  });

  Future<void> addPendingTodoOperation({String syncError = ''}) =>
      fixture.db.insert('op_logs', {
        'op_type': 'UPDATE',
        'target_table': 'todos',
        'target_uuid': 'todo-target',
        'data_json': jsonEncode({'uuid': 'todo-target'}),
        'timestamp': DateTime(2026, 10, 21, 9).millisecondsSinceEpoch,
        'is_synced': 0,
        'sync_error': syncError,
      });

  testWidgets('shows grouped pending status and incremental retry entry', (
    tester,
  ) async {
    await addPendingTodoOperation();

    await tester.pumpWidget(
      const MaterialApp(home: SyncHealthPage(username: username)),
    );
    await tester.pumpAndSettle();

    expect(find.text('同步状态'), findsOneWidget);
    expect(find.text('1 项等待同步'), findsOneWidget);
    expect(find.text('待处理'), findsOneWidget);
    expect(find.text('待办与清单'), findsOneWidget);
    expect(find.text('重试可同步项目'), findsOneWidget);
    expect(find.textContaining('请求成功不代表每条记录都已确认'), findsOneWidget);
  });

  testWidgets('conflict-only modules direct to review without retry', (
    tester,
  ) async {
    await fixture.db.update(
      'todos',
      {
        'has_conflict': 1,
        'conflict_data': jsonEncode({'conflict_type': 'version_conflict'}),
      },
      where: 'uuid = ?',
      whereArgs: ['todo-target'],
    );

    await tester.pumpWidget(
      const MaterialApp(home: SyncHealthPage(username: username)),
    );
    await tester.pumpAndSettle();

    expect(find.text('有冲突需要核对'), findsOneWidget);
    expect(find.text('前往冲突中心核对'), findsOneWidget);
    expect(find.text('重试可同步项目'), findsNothing);
  });

  testWidgets('centers the content column on a wide desktop viewport', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await addPendingTodoOperation();

    await tester.pumpWidget(
      const MaterialApp(home: SyncHealthPage(username: username)),
    );
    await tester.pumpAndSettle();

    expect(tester.getSize(find.byType(ListView).first).width, 960);
    expect(tester.takeException(), isNull);
  });

  testWidgets('dark mode and enlarged text fit a narrow phone viewport', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.5;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await addPendingTodoOperation();

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF5268A5),
            brightness: Brightness.dark,
          ),
        ),
        home: const SyncHealthPage(username: username),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('重试可同步项目'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('authentication details are redacted in operation errors', (
    tester,
  ) async {
    await addPendingTodoOperation(syncError: 'Bearer fixture-token-secret');

    await tester.pumpWidget(
      const MaterialApp(home: SyncHealthPage(username: username)),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Bearer [已隐藏]'), findsOneWidget);
    expect(find.textContaining('fixture-token-secret'), findsNothing);
  });

  testWidgets(
    'shows a recoverable message when the account snapshot is stale',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: SyncHealthPage(username: 'previous-account')),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('账户已切换'), findsOneWidget);
      expect(find.text('重新读取'), findsOneWidget);
    },
  );
}
