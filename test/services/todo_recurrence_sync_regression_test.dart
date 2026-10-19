import 'dart:io';
import 'dart:convert';
import 'dart:async';

import 'package:countdown_todo/models.dart';
import 'package:countdown_todo/services/database_helper.dart';
import 'package:countdown_todo/services/api_service.dart';
import 'package:countdown_todo/services/sync_oplog_policy.dart';
import 'package:countdown_todo/services/todo_lww_service.dart';
import 'package:countdown_todo/storage_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

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

// Exercise real storage against isolated SQLite databases.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late String username;
  var sequence = 0;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    directory = await Directory.systemTemp.createTemp('todo-stale-probe-');
    await databaseFactory.setDatabasesPath(directory.path);
  });

  setUp(() async {
    username = 'probe-${sequence++}';
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    await prefs.setString('current_login_user', username);
    await prefs.setInt('current_user_id', 0);
    await prefs.setBool('migration_marker_${username}_v4', true);
    await prefs.setBool('cleanup_done_${username}_v4_repair', true);
    await prefs.setBool('conflict_detection_enabled', false);
  });

  tearDown(() async {
    await Future<void>.delayed(const Duration(milliseconds: 200));
    await DatabaseHelper.instance.closeDatabase();
  });

  tearDownAll(() async {
    debugDefaultTargetPlatformOverride = null;
    await directory.delete(recursive: true);
  });

  Future<void> seed(List<TodoItem> items) => StorageService.saveTodos(
    username,
    items,
    sync: false,
    isSyncSource: true,
    recomputeScheduleConflicts: false,
  );

  TodoItem historical({bool done = false, int? updatedAt, DateTime? dueDate}) {
    final now = DateTime.now();
    return TodoItem(
      id: '00000000-0000-4000-8000-000000000001',
      title: 'daily task',
      recurrenceSeriesId: '00000000-0000-4000-8000-000000000002',
      customIntervalDays: 0,
      isDone: done,
      version: done ? 4 : 2,
      updatedAt:
          updatedAt ??
          now.subtract(const Duration(hours: 2)).millisecondsSinceEpoch,
      createdAt: now.subtract(const Duration(days: 3)).millisecondsSinceEpoch,
      createdDate: DateTime(
        now.year,
        now.month,
        now.day - 1,
        9,
      ).millisecondsSinceEpoch,
      dueDate: dueDate ?? DateTime(now.year, now.month, now.day - 1, 10),
    );
  }

  test('automatic rollover preserves the source write time and cannot undo cloud completion', () async {
    final stale = historical()..recurrence = RecurrenceType.daily;
    final remoteCompleted = historical(
      done: true,
      updatedAt: DateTime.now()
          .subtract(const Duration(minutes: 1))
          .millisecondsSinceEpoch,
    );
    await seed([stale]);
    final loaded = await StorageService.getTodos(
      username,
      includeDeleted: true,
    );
    final rolled = loaded.singleWhere((item) => item.id == stale.id);
    final wins = TodoLwwService.isIncomingWinner(
      incomingUpdatedAt: rolled.updatedAt,
      incomingVersion: rolled.version,
      currentUpdatedAt: remoteCompleted.updatedAt,
      currentVersion: remoteCompleted.version,
    );
    expect(rolled.isDone, isFalse);
    expect(rolled.updatedAt, stale.updatedAt);
    expect(wins, isFalse);
    final db = await DatabaseHelper.instance.databaseForUser(username);
    final ops = await db.query(
      'op_logs',
      where: 'target_uuid = ?',
      whereArgs: [stale.id],
    );
    expect(ops, hasLength(1));
    final payload = jsonDecode(ops.single['data_json'] as String) as Map;
    expect(payload['_recurrence_maintenance'], {
      'create_only': false,
      'base_version': stale.version,
      'base_updated_at': stale.updatedAt,
    });
  });

  test('old batch cannot overwrite a newer completion or due date', () async {
    final stale = historical();
    await seed([stale]);
    final snapshot = await StorageService.getTodos(
      username,
      includeDeleted: true,
    );
    final newer = historical(
      done: true,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
      dueDate: stale.dueDate!.add(const Duration(hours: 3)),
    );
    await StorageService.updateSingleTodo(username, newer, sync: false);
    await StorageService.saveTodos(
      username,
      snapshot,
      sync: false,
      recomputeScheduleConflicts: false,
    );
    final db = await DatabaseHelper.instance.databaseForUser(username);
    final row = (await db.query(
      'todos',
      where: 'uuid = ?',
      whereArgs: [stale.id],
    )).single;
    expect(row['is_completed'], 1);
    expect(
      int.parse(row['due_date'].toString()),
      newer.dueDate!.millisecondsSinceEpoch,
    );
    expect(row['updated_at'], newer.updatedAt);
  });

  test(
    'pending user operations protect the complete row during sync persistence',
    () async {
      final stale = historical();
      await seed([stale]);
      final newer = historical(
        done: true,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
        dueDate: stale.dueDate!.add(const Duration(hours: 3)),
      );
      await StorageService.updateSingleTodo(username, newer, sync: false);
      await seed([stale]);
      final db = await DatabaseHelper.instance.databaseForUser(username);
      final row = (await db.query(
        'todos',
        where: 'uuid = ?',
        whereArgs: [stale.id],
      )).single;
      expect(row['is_completed'], 1);
      expect(
        int.parse(row['due_date'].toString()),
        newer.dueDate!.millisecondsSinceEpoch,
      );
      expect(row['updated_at'], newer.updatedAt);
      expect(row['version'], newer.version);
    },
  );

  test(
    'pending user edits protect dates even against a newer sync timestamp',
    () async {
      final original = historical();
      await seed([original]);
      final userEdit = historical(
        done: true,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
        dueDate: original.dueDate!.add(const Duration(hours: 3)),
      );
      await StorageService.updateSingleTodo(username, userEdit, sync: false);
      final remote = original.detachedCopy()
        ..updatedAt = userEdit.updatedAt + 1000
        ..version = 99;
      await seed([remote]);
      final actual = (await StorageService.getTodoByUuid(
        username,
        original.id,
      ))!;
      expect(actual.toJson(), userEdit.toJson());
    },
  );

  test('a new explicit cancellation is still saved and uploaded', () async {
    final completed = historical(done: true);
    await seed([completed]);
    final cancelled = completed.detachedCopy()..isDone = false;
    cancelled.markAsChanged();
    await StorageService.updateSingleTodo(username, cancelled, sync: false);
    final actual = (await StorageService.getTodoByUuid(
      username,
      completed.id,
    ))!;
    expect(actual.isDone, isFalse);
    expect(actual.updatedAt, cancelled.updatedAt);
    final db = await DatabaseHelper.instance.databaseForUser(username);
    final ops = await db.query(
      'op_logs',
      where: 'target_uuid = ?',
      whereArgs: [completed.id],
    );
    final payload = jsonDecode(ops.single['data_json'] as String) as Map;
    expect(payload.containsKey('_recurrence_maintenance'), isFalse);
    expect(payload['is_completed'], 0);
  });

  test(
    'missing generated instances inherit source time rather than current time',
    () {
      final source = historical()..recurrence = RecurrenceType.daily;
      final generated = StorageService.futureRecurrenceOccurrencesForTest(
        source,
        [source],
      );
      expect(generated, isNotEmpty);
      expect(
        generated.every((item) => item.updatedAt == source.updatedAt),
        isTrue,
      );
    },
  );

  test('old batch cannot change an independent completion row', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('current_user_id', 42);
    final old = historical()..collabType = 1;
    await seed([old]);
    final completed = old.detachedCopy()..isDone = true;
    completed.markAsChanged();
    await StorageService.updateSingleTodo(username, completed, sync: false);
    await StorageService.saveTodos(
      username,
      [old],
      sync: false,
      recomputeScheduleConflicts: false,
    );
    final db = await DatabaseHelper.instance.databaseForUser(username);
    final completion = (await db.query('todo_completions')).single;
    expect(completion['is_completed'], 1);
    expect(completion['updated_at'], completed.updatedAt);
    final ops = await db.query('op_logs');
    expect(ops, hasLength(1));
  });

  test(
    'a later maintenance operation cannot replace a pending user payload',
    () {
      final payloads = <String, Map<String, dynamic>>{};
      final userEdit = <String, dynamic>{'is_completed': 1};
      final maintenance = <String, dynamic>{
        '_recurrence_maintenance': {'create_only': false},
      };
      SyncOplogPolicy.collectTodoPayload(payloads, 'id', userEdit);
      SyncOplogPolicy.collectTodoPayload(payloads, 'id', maintenance);
      expect(payloads['id'], userEdit);
      final cancellation = <String, dynamic>{'is_completed': 0};
      SyncOplogPolicy.collectTodoPayload(payloads, 'id', cancellation);
      expect(payloads['id'], cancellation);
    },
  );

  test('concurrent saves keep the latest row and matching oplog', () async {
    final older = historical();
    final newer = historical(
      done: true,
      updatedAt: older.updatedAt + 1000,
      dueDate: older.dueDate!.add(const Duration(hours: 3)),
    );
    await Future.wait([
      StorageService.saveTodos(
        username,
        [newer],
        sync: false,
        recomputeScheduleConflicts: false,
      ),
      StorageService.saveTodos(
        username,
        [older],
        sync: false,
        recomputeScheduleConflicts: false,
      ),
    ]);
    final actual = (await StorageService.getTodoByUuid(username, newer.id))!;
    expect(actual.toJson(), newer.toJson());
    final db = await DatabaseHelper.instance.databaseForUser(username);
    final ops = await db.query('op_logs', orderBy: 'id DESC');
    final payload = jsonDecode(ops.first['data_json'] as String) as Map;
    expect(payload['updated_at'], newer.updatedAt);
    expect(payload['is_completed'], 1);
  });

  Future<Map<String, dynamic>> syncTodosOnly() => StorageService.syncData(
    username,
    syncCountdowns: false,
    syncScreenTime: false,
    syncTimeLogs: false,
    syncPomodoro: false,
    syncPlanBlocks: false,
    syncFixedSchedules: false,
    syncHabits: false,
    syncFinance: false,
  );

  test(
    'rejected insert-only generation restores the server row across two syncs',
    () async {
      final now = DateTime.now();
      final source = historical()
        ..createdDate = DateTime(
          now.year,
          now.month,
          now.day,
          9,
        ).millisecondsSinceEpoch
        ..dueDate = DateTime(now.year, now.month, now.day, 10)
        ..recurrence = RecurrenceType.daily
        ..updatedAt = now.millisecondsSinceEpoch;
      await seed([source]);
      final generated = await StorageService.getTodos(
        username,
        includeDeleted: true,
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));
      final child = generated.firstWhere((todo) => todo.id != source.id);
      final serverVersion = child.detachedCopy()
        ..isDone = true
        ..recurrence = RecurrenceType.none
        ..updatedAt = child.updatedAt - 60000
        ..version = 2
        ..dueDate = child.dueDate!.add(const Duration(hours: 3));
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('current_user_id', 42);
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      ApiService.setBaseUrlOverride('http://127.0.0.1:${server.port}');
      var requests = 0;
      server.listen((request) async {
        final body = jsonDecode(await utf8.decoder.bind(request).join()) as Map;
        expect(request.uri.path, '/api/sync');
        if (requests == 0) {
          final sent = (body['todos'] as List).cast<Map>();
          final payload = sent.singleWhere((item) => item['uuid'] == child.id);
          expect(
            (payload['_recurrence_maintenance'] as Map)['create_only'],
            isTrue,
          );
        }
        requests++;
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'success': true,
            'server_todos': [serverVersion.toJson()],
            'todo_maintenance_rejected_uuids': [child.id],
            'new_sync_time': DateTime.now().millisecondsSinceEpoch,
          }),
        );
        await request.response.close();
      });
      try {
        await HttpOverrides.runWithHttpOverrides(() async {
          for (var round = 0; round < 2; round++) {
            final result = await syncTodosOnly();
            expect(result['success'], isTrue, reason: result.toString());
            final actual = (await StorageService.getTodoByUuid(
              username,
              child.id,
            ))!;
            expect(actual.isDone, isTrue);
            expect(actual.dueDate, serverVersion.dueDate);
            expect(actual.updatedAt, serverVersion.updatedAt);
          }
        }, _LocalHttpOverrides());
        expect(requests, 2);
      } finally {
        await prefs.setInt('current_user_id', 0);
        ApiService.clearBaseUrlOverride();
        await server.close(force: true);
      }
    },
  );

  test(
    'an edit while the request is in flight survives two sync responses',
    () async {
      final original = historical();
      await seed([original]);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('current_user_id', 42);
      final received = Completer<void>();
      final release = Completer<void>();
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      ApiService.setBaseUrlOverride('http://127.0.0.1:${server.port}');
      var requests = 0;
      server.listen((request) async {
        await request.drain<void>();
        requests++;
        if (requests == 1) {
          received.complete();
          await release.future;
        }
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'success': true,
            'server_todos': [original.toJson()],
            'new_sync_time': DateTime.now().millisecondsSinceEpoch,
          }),
        );
        await request.response.close();
      });
      try {
        await HttpOverrides.runWithHttpOverrides(() async {
          final future = syncTodosOnly();
          await received.future.timeout(const Duration(seconds: 5));
          final userEdit = original.detachedCopy()
            ..isDone = true
            ..dueDate = original.dueDate!.add(const Duration(hours: 3));
          userEdit.markAsChanged();
          await StorageService.updateSingleTodo(
            username,
            userEdit,
            sync: false,
          );
          release.complete();
          expect((await future)['success'], isTrue);
          var actual = (await StorageService.getTodoByUuid(
            username,
            original.id,
          ))!;
          expect(actual.toJson(), userEdit.toJson());
          final db = await DatabaseHelper.instance.databaseForUser(username);
          final pending = await db.query('op_logs', where: 'is_synced = 0');
          expect(pending, hasLength(1));
          expect((await syncTodosOnly())['success'], isTrue);
          actual = (await StorageService.getTodoByUuid(username, original.id))!;
          expect(actual.toJson(), userEdit.toJson());
        }, _LocalHttpOverrides());
      } finally {
        if (!release.isCompleted) release.complete();
        await prefs.setInt('current_user_id', 0);
        ApiService.clearBaseUrlOverride();
        await server.close(force: true);
      }
    },
  );
}
