import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:countdown_todo/services/api_service.dart';
import 'package:countdown_todo/services/sync_health_service.dart';
import 'package:countdown_todo/services/storage/app_settings_storage.dart';
import 'package:countdown_todo/storage_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/plan_availability_fixture.dart';

class _LocalHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = super.createHttpClient(context);
    client.findProxy = (uri) {
      if (uri.host != '127.0.0.1') throw StateError('Only loopback is allowed');
      return 'DIRECT';
    };
    return client;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late PlanAvailabilityFixture fixture;
  late SharedPreferences prefs;
  const username = PlanAvailabilityFixture.username;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({
      StorageService.keyCurrentUser: username,
      'current_user_id': 42,
    });
  });

  setUp(() async {
    fixture = PlanAvailabilityFixture();
    await fixture.initialize(resetPreferences: false);
    prefs = await StorageService.prefs;
    await prefs.clear();
    await prefs.setString(StorageService.keyCurrentUser, username);
    await prefs.setInt('current_user_id', 42);
  });

  tearDown(() async {
    ApiService.clearBaseUrlOverride();
    await fixture.dispose();
  });

  Future<void> addOperation({
    required String table,
    required String uuid,
    String error = '',
    String operation = 'UPDATE',
  }) async {
    await fixture.db.insert('op_logs', {
      'op_type': operation,
      'target_table': table,
      'target_uuid': uuid,
      'data_json': jsonEncode({'uuid': uuid}),
      'timestamp': DateTime(2026, 10, 21, 9).millisecondsSinceEpoch,
      'is_synced': 0,
      'sync_error': error,
    });
  }

  test(
    'aggregates queues by module and keeps conflicts out of retry counts',
    () async {
      await AppSettingsStorage.setFinanceCloudSyncEnabled(username, true);
      await fixture.db.update(
        'todos',
        {
          'has_conflict': 1,
          'conflict_data': jsonEncode({'conflict_type': 'version_conflict'}),
        },
        where: 'uuid = ?',
        whereArgs: ['todo-target'],
      );
      await fixture.todo('schedule-conflict', '时间冲突待办');
      await fixture.db.update(
        'todos',
        {
          'has_conflict': 1,
          'conflict_data': jsonEncode({
            'conflict_type': 'local_schedule_conflict',
            'source': 'local_detector',
          }),
        },
        where: 'uuid = ?',
        whereArgs: ['schedule-conflict'],
      );

      await addOperation(table: 'todos', uuid: 'todo-target');
      await addOperation(
        table: 'todos',
        uuid: 'todo-target',
        error: 'server_conflict',
      );
      await addOperation(
        table: 'countdowns',
        uuid: 'countdown-1',
        error: 'HTTP 503',
      );
      await addOperation(table: 'courses', uuid: 'course-1');
      await addOperation(table: 'future_table', uuid: 'future-1');

      await fixture.db.insert('finance_transactions', {
        'uuid': 'finance-pending',
        'type': 'expense',
        'amount_minor': 100,
        'transaction_date': '2026-10-21',
        'created_at': 1,
        'updated_at': 2,
        'pending_sync': 1,
      });
      await StorageService.saveLocalScreenTime({
        'date': '2026-10-21',
        'apps': [
          {'app_name': 'App A', 'duration': 60},
          {'app_name': 'App B', 'duration': 120},
        ],
      }, username: username);
      await StorageService.updateLastAutoSyncTime(username);

      final snapshot = await SyncHealthService.load(username);

      expect(
        snapshot.statusFor(SyncHealthModule.todos).queuedOperationCount,
        2,
      );
      expect(snapshot.statusFor(SyncHealthModule.todos).conflictCount, 1);
      expect(snapshot.statusFor(SyncHealthModule.todos).retryableCount, 1);
      expect(snapshot.statusFor(SyncHealthModule.todos).failedCount, 0);
      expect(snapshot.statusFor(SyncHealthModule.countdowns).failedCount, 1);
      expect(snapshot.statusFor(SyncHealthModule.courses).retryableCount, 0);
      expect(
        snapshot.statusFor(SyncHealthModule.other).queuedOperationCount,
        1,
      );
      expect(snapshot.statusFor(SyncHealthModule.other).retryableCount, 0);
      expect(snapshot.statusFor(SyncHealthModule.finance).localPendingCount, 1);
      expect(
        snapshot.statusFor(SyncHealthModule.screenTime).localPendingCount,
        2,
      );
      expect(snapshot.totalRetryableCount, 5);
      expect(snapshot.totalConflictCount, 1);
      expect(snapshot.lastSuccessfulRequestAt, isNotNull);
    },
  );

  test('finance markers remain local when cloud sync is disabled', () async {
    await fixture.db.insert('finance_transactions', {
      'uuid': 'local-only-finance',
      'type': 'expense',
      'amount_minor': 100,
      'transaction_date': '2026-10-21',
      'created_at': 1,
      'updated_at': 2,
      'pending_sync': 1,
    });

    final snapshot = await SyncHealthService.load(username);
    final finance = snapshot.statusFor(SyncHealthModule.finance);

    expect(finance.cloudSyncEnabled, isFalse);
    expect(finance.localPendingCount, 1);
    expect(finance.canRetry, isFalse);

    final result = await SyncHealthService.retryModules(
      username: username,
      modules: const {SyncHealthModule.finance},
    );
    expect(result.success, isFalse);
    expect(result.error, contains('云同步未开启'));
  });

  test(
    'module selection maps to only the selected incremental sync domains',
    () {
      final selection = SyncHealthSyncSelection.fromModules({
        SyncHealthModule.todos,
        SyncHealthModule.finance,
        SyncHealthModule.screenTime,
        SyncHealthModule.courses,
        SyncHealthModule.other,
      });

      expect(selection.todos, isTrue);
      expect(selection.countdowns, isFalse);
      expect(selection.finance, isTrue);
      expect(selection.screenTime, isTrue);
      expect(selection.hasAnyDomain, isTrue);
      expect(
        SyncHealthService.moduleForTable('courses'),
        SyncHealthModule.courses,
      );
      expect(
        SyncHealthService.moduleForTable('unknown_table'),
        SyncHealthModule.other,
      );
    },
  );

  test('maps every queued business table to its status module', () {
    const expected = {
      'todos': SyncHealthModule.todos,
      'todo_groups': SyncHealthModule.todos,
      'countdowns': SyncHealthModule.countdowns,
      'pomodoro_records': SyncHealthModule.pomodoro,
      'pomodoro_tags': SyncHealthModule.pomodoro,
      'time_logs': SyncHealthModule.timeLogs,
      'todo_plan_blocks': SyncHealthModule.planBlocks,
      'fixed_schedules': SyncHealthModule.fixedSchedules,
      'habit_goals': SyncHealthModule.habits,
      'habit_goal_rule_revisions': SyncHealthModule.habits,
      'habit_checkins': SyncHealthModule.habits,
      'habit_sleep_coaching_plans': SyncHealthModule.habits,
      'courses': SyncHealthModule.courses,
    };

    for (final entry in expected.entries) {
      expect(
        SyncHealthService.moduleForTable(entry.key),
        entry.value,
        reason: entry.key,
      );
    }
    expect(
      SyncHealthService.moduleForTable('future_table'),
      SyncHealthModule.other,
    );
  });

  test('screen-time-only retry sends no unrelated sync domains', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    ApiService.setBaseUrlOverride('http://127.0.0.1:${server.port}');
    final requestReceived = Completer<Map>();
    server.listen((request) async {
      final body = jsonDecode(await utf8.decoder.bind(request).join()) as Map;
      if (!requestReceived.isCompleted) requestReceived.complete(body);
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode({
          'success': true,
          'new_sync_time': DateTime.now().millisecondsSinceEpoch,
          'screen_time_results': [],
          'server_todos': [],
          'server_todo_groups': [],
          'server_countdowns': [],
          'server_time_logs': [],
          'server_pomodoros': [],
          'server_tags': [],
          'server_plan_blocks': [],
          'server_fixed_schedules': [],
          'server_habit_goals': [],
          'server_habit_goal_rules': [],
          'server_habit_checkins': [],
          'server_habit_sleep_coaching_plans': [],
          'conflicts': [],
          'joined_team_uuids': [],
        }),
      );
      await request.response.close();
    });
    await StorageService.saveLocalScreenTime({
      'date': '2026-10-21',
      'apps': [
        {'app_name': 'App A', 'duration': 60},
      ],
    }, username: username);
    await prefs.setInt('last_auto_sync_time_$username', 1);

    final result = await HttpOverrides.runWithHttpOverrides(
      () => SyncHealthService.retryModules(
        username: username,
        modules: const {SyncHealthModule.screenTime},
      ),
      _LocalHttpOverrides(),
    );
    final body = await requestReceived.future.timeout(
      const Duration(seconds: 5),
    );

    expect(result.success, isTrue, reason: result.error);
    expect(body['screen_time'], isNotNull);
    expect(body['todos'], isEmpty);
    expect(body['todo_groups'], isEmpty);
    expect(body['countdowns'], isEmpty);
    expect(body['sync_finance'], isFalse);
    expect(body['sync_habits'], isFalse);
    expect(body['force_full_sync'], isFalse);
    expect(
      (await StorageService.getLastAutoSyncTime(username))!
          .millisecondsSinceEpoch,
      greaterThan(1),
    );
    expect(await StorageService.getLocalScreenTimeMap(username: username), {});
    await server.close(force: true);
  });

  test(
    'rejected server response preserves the cache and success timestamp',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      ApiService.setBaseUrlOverride('http://127.0.0.1:${server.port}');
      final requestReceived = Completer<void>();
      server.listen((request) async {
        await utf8.decoder.bind(request).join();
        if (!requestReceived.isCompleted) requestReceived.complete();
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({'success': false, 'error': 'server rejected sync'}),
        );
        await request.response.close();
      });
      await StorageService.saveLocalScreenTime({
        'date': '2026-10-21',
        'apps': [
          {'app_name': 'App A', 'duration': 60},
        ],
      }, username: username);
      await prefs.setInt('last_auto_sync_time_$username', 123);

      final result = await HttpOverrides.runWithHttpOverrides(
        () => SyncHealthService.retryModules(
          username: username,
          modules: const {SyncHealthModule.screenTime},
        ),
        _LocalHttpOverrides(),
      );
      await requestReceived.future.timeout(const Duration(seconds: 5));

      expect(result.success, isFalse);
      expect(result.error, contains('server rejected sync'));
      expect(
        (await StorageService.getLastAutoSyncTime(username))!
            .millisecondsSinceEpoch,
        123,
      );
      expect(
        (await StorageService.getLocalScreenTimeMap(
          username: username,
        ))['apps'],
        hasLength(1),
      );
      await server.close(force: true);
    },
  );
}
