@TestOn('vm')
library;

import 'dart:io';

import 'package:countdown_todo/services/database_helper.dart';
import 'package:countdown_todo/services/database_path_resolver.dart';
import 'package:countdown_todo/services/database_schema_history.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late DatabaseFactory previousFactory;
  TargetPlatform? previousPlatform;

  setUp(() async {
    previousPlatform = debugDefaultTargetPlatformOverride;
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    sqfliteFfiInit();
    try {
      previousFactory = databaseFactory;
    } on StateError {
      previousFactory = databaseFactoryFfiNoIsolate;
    }
    databaseFactory = databaseFactoryFfiNoIsolate;
    tempDir = await Directory.systemTemp.createTemp('cdt_db_upgrade_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async => tempDir.path,
        );
    await databaseFactory.setDatabasesPath(tempDir.path);
    await DatabaseHelper.instance.closeDatabase();
  });

  tearDown(() async {
    await DatabaseHelper.instance.closeDatabase();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
    databaseFactory = previousFactory;
    debugDefaultTargetPlatformOverride = previousPlatform;
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  Future<Set<String>> columnNames(Database db, String table) async {
    final rows = await db.rawQuery('PRAGMA table_info($table)');
    return rows.map((row) => row['name'] as String).toSet();
  }

  Future<bool> tableExists(Database db, String table) async {
    final rows = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?",
      [table],
    );
    return rows.isNotEmpty;
  }

  test('V1 database upgrades cleanly through all ascending migrations to currentVersion', () async {
    const username = 'db-upgrade-v1';
    SharedPreferences.setMockInitialValues({'current_login_user': username});
    final dbPath = await resolveDatabasePath(
      DatabaseHelper.databaseFileNameFor(username),
    );

    final legacyDb = await databaseFactory.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, version) async {
          await db.execute('''
              CREATE TABLE todos (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                uuid TEXT UNIQUE,
                content TEXT,
                remark TEXT,
                due_date INTEGER,
                created_date INTEGER NOT NULL,
                is_completed INTEGER DEFAULT 0,
                is_deleted INTEGER DEFAULT 0,
                version INTEGER DEFAULT 1,
                created_at INTEGER,
                updated_at INTEGER
              )
            ''');
          await db.execute('''
              CREATE TABLE countdowns (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                uuid TEXT UNIQUE,
                title TEXT,
                target_time INTEGER,
                is_deleted INTEGER DEFAULT 0,
                version INTEGER DEFAULT 1,
                created_at INTEGER,
                updated_at INTEGER
              )
            ''');
          await db.execute('''
              CREATE TABLE todo_groups (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                uuid TEXT UNIQUE,
                name TEXT,
                is_expanded INTEGER DEFAULT 0,
                is_deleted INTEGER DEFAULT 0,
                version INTEGER DEFAULT 1,
                created_at INTEGER,
                updated_at INTEGER
              )
            ''');
          await db.execute('''
              CREATE TABLE op_logs (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                op_type TEXT,
                target_table TEXT,
                target_uuid TEXT,
                data_json TEXT,
                timestamp INTEGER,
                is_synced INTEGER DEFAULT 0
              )
            ''');
          await db.insert('todos', {
            'uuid': 'legacy-todo-1',
            'content': '历史待办',
            'remark': 'V1 数据保留',
            'created_date': 1700000000000,
            'is_completed': 0,
            'is_deleted': 0,
            'version': 1,
            'created_at': 1700000000000,
            'updated_at': 1700000000000,
          });
        },
      ),
    );
    await legacyDb.close();

    final upgradedDb = await DatabaseHelper.instance.databaseForUser(username);
    expect(await upgradedDb.getVersion(), DatabaseSchemaHistory.currentVersion);

    final preserved = await upgradedDb.query(
      'todos',
      where: 'uuid = ?',
      whereArgs: ['legacy-todo-1'],
    );
    expect(preserved, hasLength(1));
    expect(preserved.single['content'], '历史待办');

    final todoInfo = await upgradedDb.rawQuery('PRAGMA table_info(todos)');
    final createdDateCol = todoInfo.firstWhere(
      (row) => row['name'] == 'created_date',
    );
    expect(createdDateCol['notnull'], 0);

    final todoCols = todoInfo.map((row) => row['name'] as String).toSet();
    expect(
      todoCols,
      containsAll([
        'team_name',
        'is_skipped',
        'completed_at',
        'image_path',
        'recurrence_series_id',
      ]),
    );

    // Verify V25/V26/V29/V32 columns exist on pomodoro_records created in V11.
    final recordCols = await columnNames(upgradedDb, 'pomodoro_records');
    expect(
      recordCols,
      containsAll([
        'plan_block_id',
        'has_conflict',
        'conflict_data',
        'note',
        'total_pause_seconds',
        'pause_intervals',
      ]),
    );

    // Verify V26/V31 columns exist on pomodoro_tags created in V13.
    final tagCols = await columnNames(upgradedDb, 'pomodoro_tags');
    expect(
      tagCols,
      containsAll(['has_conflict', 'conflict_data', 'is_archived']),
    );

    for (final table in const [
      'courses',
      'todo_plan_blocks',
      'local_plan_editor_drafts',
      'habit_goals',
      'journal_entries',
      'finance_transactions',
      'ai_usage_records',
    ]) {
      expect(await tableExists(upgradedDb, table), isTrue, reason: table);
    }
  });

  test('V59 database runs V60 nullable created_date before V61 completed_at migration', () async {
    const username = 'db-upgrade-v59';
    SharedPreferences.setMockInitialValues({'current_login_user': username});

    // Initialize the full real schema first, then downgrade `todos` to V59
    // (`created_date INTEGER NOT NULL` and without `completed_at`).
    final initialDb = await DatabaseHelper.instance.databaseForUser(username);
    final dependentObjects = await initialDb.rawQuery('''
        SELECT sql FROM sqlite_master
        WHERE tbl_name = 'todos'
          AND type IN ('index', 'trigger')
          AND sql IS NOT NULL
        ORDER BY type, name
      ''');

    await initialDb.execute('DROP TABLE todos');
    await initialDb.execute('''
        CREATE TABLE todos (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          uuid TEXT NOT NULL UNIQUE,
          team_uuid TEXT,
          group_id TEXT,
          content TEXT NOT NULL,
          remark TEXT,
          team_name TEXT,
          creator_id TEXT,
          creator_name TEXT,
          is_completed INTEGER NOT NULL DEFAULT 0,
          is_skipped INTEGER NOT NULL DEFAULT 0,
          is_skipped_sync_pending INTEGER NOT NULL DEFAULT 0,
          is_deleted INTEGER NOT NULL DEFAULT 0,
          version INTEGER NOT NULL DEFAULT 1,
          due_date TEXT,
          created_date INTEGER NOT NULL,
          created_at INTEGER NOT NULL,
          updated_at INTEGER NOT NULL,
          collab_type INTEGER NOT NULL DEFAULT 0,
          recurrence INTEGER NOT NULL DEFAULT 0,
          recurrence_series_id TEXT,
          custom_interval_days INTEGER NOT NULL DEFAULT 0,
          recurrence_end_date INTEGER,
          reminder_minutes INTEGER,
          has_conflict INTEGER DEFAULT 0,
          conflict_data TEXT,
          is_all_day INTEGER DEFAULT 0,
          image_path TEXT,
          original_text TEXT
        )
      ''');
    for (final object in dependentObjects) {
      final sql = object['sql'];
      if (sql is String && sql.isNotEmpty) {
        await initialDb.execute(sql);
      }
    }
    await initialDb.insert('todos', {
      'uuid': 'todo-v59',
      'content': 'V59 待办',
      'created_date': 1700000000000,
      'is_completed': 1,
      'is_deleted': 0,
      'version': 1,
      'created_at': 1700000000000,
      'updated_at': 1700000000000,
    });
    await initialDb.setVersion(59);
    await DatabaseHelper.instance.closeDatabase();

    final upgradedDb = await DatabaseHelper.instance.databaseForUser(username);
    expect(await upgradedDb.getVersion(), DatabaseSchemaHistory.currentVersion);

    final todoInfo = await upgradedDb.rawQuery('PRAGMA table_info(todos)');
    final createdDateCol = todoInfo.firstWhere(
      (row) => row['name'] == 'created_date',
    );
    expect(createdDateCol['notnull'], 0);
    expect(await columnNames(upgradedDb, 'todos'), contains('completed_at'));

    // Verify existing row survived, got backfilled, and NULL created_date is accepted.
    final preserved = await upgradedDb.query(
      'todos',
      where: 'uuid = ?',
      whereArgs: ['todo-v59'],
    );
    expect(preserved, hasLength(1));
    expect(preserved.single['completed_at'], 1700000000000);

    await upgradedDb.insert('todos', {
      'uuid': 'todo-unscheduled-after-upgrade',
      'content': '无日期待办',
      'created_date': null,
      'completed_at': 1700000001000,
      'is_completed': 1,
      'is_deleted': 0,
      'version': 1,
      'created_at': 1700000001000,
      'updated_at': 1700000001000,
    });
    final inserted = await upgradedDb.query(
      'todos',
      where: 'uuid = ?',
      whereArgs: ['todo-unscheduled-after-upgrade'],
    );
    expect(inserted.single['created_date'], isNull);
    expect(inserted.single['completed_at'], 1700000001000);
  });
}
