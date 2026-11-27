part of '../database_helper.dart';

bool _isDatabaseLockedError(Object error) {
  final text = error.toString().toLowerCase();
  return text.contains('database is locked') ||
      text.contains('sqlite_error: 5');
}

mixin _DatabaseHelperInitMixin on _DatabaseHelperBase {
  /// Keeps an unscheduled todo's business start date nullable in local SQLite.
  ///
  /// Called from onUpgrade, which runs transactionally. Rebuilding from the
  /// stored CREATE TABLE SQL changes only the created_date constraint while
  /// preserving the exact columns and table constraints of older databases.
  Future<void> _ensureTodoCreatedDateNullable(Database db) async {
    final columns = await db.rawQuery('PRAGMA table_info(todos)');
    if (columns.isEmpty) return;

    final createdDateColumns = columns
        .where((column) => column['name'] == 'created_date')
        .toList(growable: false);
    if (createdDateColumns.isEmpty ||
        createdDateColumns.single['notnull'] != 1) {
      return;
    }

    const temporaryTable = 'todos_created_date_nullable_migration';
    final createRows = await db.rawQuery(
      "SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'todos'",
    );
    final createSql = createRows.isEmpty ? null : createRows.single['sql'];
    if (createSql is! String) {
      throw StateError('无法读取 todos 表结构，取消 created_date 迁移');
    }

    final renamedCreateSql = createSql.replaceFirst(
      _rxCached28_1,
      'CREATE TABLE $temporaryTable',
    );
    if (renamedCreateSql == createSql) {
      throw StateError('无法安全重建 todos 表，取消 created_date 迁移');
    }

    final nullableCreateSql = renamedCreateSql.replaceFirstMapped(
      _rxCached28_2,
      (match) => match.group(1)!,
    );
    if (nullableCreateSql == renamedCreateSql) {
      throw StateError('无法移除 created_date 的 NOT NULL 约束');
    }

    final dependentObjects = await db.rawQuery('''
      SELECT sql FROM sqlite_master
      WHERE tbl_name = 'todos'
        AND type IN ('index', 'trigger')
        AND sql IS NOT NULL
      ORDER BY type, name
    ''');

    // The onUpgrade callback is transactional, so any copy/rebuild failure
    // rolls the schema back without discarding existing todo data.
    await db.execute(nullableCreateSql);
    await db.execute('INSERT INTO $temporaryTable SELECT * FROM todos');
    await db.execute('DROP TABLE todos');
    await db.execute('ALTER TABLE $temporaryTable RENAME TO todos');

    for (final object in dependentObjects) {
      final sql = object['sql'];
      if (sql is String && sql.isNotEmpty) {
        await db.execute(sql);
      }
    }
  }

  Future<Database> _initDB(String filePath) async {
    // 🚀 桌面端 SQL 引擎初始化已由 main.dart 统一处理

    // 🚀 根据环境动态选择前缀（隔离测试数据）
    final envPrefix = EnvironmentService.isTest ? 'test_v5_' : 'v4_';
    final targetName = envPrefix + filePath;
    final path = await _resolveDatabasePath(targetName);

    for (int attempt = 0; attempt < 5; attempt++) {
      try {
        return await openDatabase(
          path,
          version: DatabaseSchemaHistory.currentVersion,
          onConfigure: (db) async {
            // 🚀 Skip busy_timeout on Android - not supported in onConfigure callback
            // Only configure WAL for desktop platforms
            if (!kIsWeb &&
                (AppPlatform.isWindows ||
                    AppPlatform.isLinux ||
                    AppPlatform.isMacOS)) {
              try {
                await db.execute('PRAGMA journal_mode = WAL');
              } catch (e) {
                //                 debugPrint("⚠️ Database: PRAGMA journal_mode failed: $e");
              }
            }
            if (!kIsWeb) {
              try {
                await db.execute('PRAGMA foreign_keys = ON');
              } catch (e) {
                //                 debugPrint("⚠️ Database: PRAGMA foreign_keys failed: $e");
              }
            }
          },
          onCreate: _createDB,
          onUpgrade: (db, oldVersion, newVersion) async {
            if (oldVersion < 3) {
              // 🚀 Uni-Sync 安全升级：为核心业务表补全协作元数据
              final tables = ['todos', 'countdowns', 'todo_groups'];
              final columns = ['creator_id', 'creator_name', 'team_name'];

              for (final table in tables) {
                for (final col in columns) {
                  try {
                    final info = await db.rawQuery('PRAGMA table_info($table)');
                    if (!info.any((row) => row['name'] == col)) {
                      await db.execute(
                        "ALTER TABLE $table ADD COLUMN $col TEXT;",
                      );
                    }
                  } catch (_) {}
                }
              }
            }

            // 🚀 Version 5: 核心加固 - 补全基础业务字段
            if (oldVersion < 5) {
              final repairTasks = [
                {'table': 'todos', 'col': 'group_id', 'type': 'TEXT'},
                {'table': 'todos', 'col': 'created_date', 'type': 'INTEGER'},
                {'table': 'todos', 'col': 'team_uuid', 'type': 'TEXT'},
                {'table': 'todos', 'col': 'team_name', 'type': 'TEXT'},
                {'table': 'todos', 'col': 'creator_id', 'type': 'TEXT'},
                {'table': 'todos', 'col': 'creator_name', 'type': 'TEXT'},
                {'table': 'todo_groups', 'col': 'team_uuid', 'type': 'TEXT'},
                {'table': 'todo_groups', 'col': 'team_name', 'type': 'TEXT'},
              ];

              for (final task in repairTasks) {
                try {
                  final info = await db.rawQuery(
                    "PRAGMA table_info(${task['table']})",
                  );
                  if (!info.any((row) => row['name'] == task['col'])) {
                    await db.execute(
                      "ALTER TABLE ${task['table']} ADD COLUMN ${task['col']} ${task['type']};",
                    );
                  }
                } catch (_) {}
              }
            }

            if (oldVersion < 6) {
              try {
                final info = await db.rawQuery("PRAGMA table_info(todos)");
                if (!info.any((row) => row['name'] == 'collab_type')) {
                  await db.execute(
                    "ALTER TABLE todos ADD COLUMN collab_type INTEGER DEFAULT 0;",
                  );
                }
              } catch (_) {}
            }

            if (oldVersion < 7) {
              try {
                await db.execute('''
                CREATE TABLE IF NOT EXISTS todo_completions (
                  todo_uuid TEXT,
                  user_id INTEGER,
                  is_completed INTEGER,
                  updated_at INTEGER,
                  PRIMARY KEY(todo_uuid, user_id)
                )
              ''');
              } catch (_) {}
            }

            if (oldVersion < 8) {
              try {
                final columns = [
                  {'name': 'recurrence', 'type': 'INTEGER DEFAULT 0'},
                  {'name': 'custom_interval_days', 'type': 'INTEGER'},
                  {'name': 'recurrence_end_date', 'type': 'INTEGER'},
                  {'name': 'reminder_minutes', 'type': 'INTEGER'},
                ];
                final info = await db.rawQuery("PRAGMA table_info(todos)");
                for (final col in columns) {
                  if (!info.any((row) => row['name'] == col['name'])) {
                    await db.execute(
                      "ALTER TABLE todos ADD COLUMN ${col['name']} ${col['type']};",
                    );
                  }
                }
              } catch (_) {}
            }

            if (oldVersion < 9) {
              try {
                final tables = ['todos', 'countdowns', 'todo_groups'];
                for (final table in tables) {
                  final info = await db.rawQuery("PRAGMA table_info($table)");
                  if (!info.any((row) => row['name'] == 'has_conflict')) {
                    await db.execute(
                      "ALTER TABLE $table ADD COLUMN has_conflict INTEGER DEFAULT 0;",
                    );
                    await db.execute(
                      "ALTER TABLE $table ADD COLUMN conflict_data TEXT;",
                    );
                  }
                }
                final todoInfo = await db.rawQuery("PRAGMA table_info(todos)");
                if (!todoInfo.any((row) => row['name'] == 'is_all_day')) {
                  await db.execute(
                    "ALTER TABLE todos ADD COLUMN is_all_day INTEGER DEFAULT 0;",
                  );
                }
              } catch (_) {}
            }

            if (oldVersion < 10) {
              try {
                await db.execute('''
                CREATE TABLE IF NOT EXISTS local_audit_logs (
                  id INTEGER PRIMARY KEY AUTOINCREMENT,
                  team_uuid TEXT,
                  user_id INTEGER,
                  target_table TEXT,
                  target_uuid TEXT,
                  op_type TEXT,
                  before_data TEXT,
                  after_data TEXT,
                  timestamp INTEGER,
                  operator_name TEXT
                )
              ''');
              } catch (_) {}
            }

            if (oldVersion < 11) {
              try {
                await db.execute('''
                CREATE TABLE IF NOT EXISTS pomodoro_records (
                  id INTEGER PRIMARY KEY AUTOINCREMENT,
                  uuid TEXT UNIQUE,
                  todo_uuid TEXT,
                  todo_title TEXT,
                  tag_uuids TEXT,
                  start_time INTEGER,
                  end_time INTEGER,
                  planned_duration INTEGER,
                  actual_duration INTEGER,
                  status TEXT,
                  device_id TEXT,
                  is_deleted INTEGER DEFAULT 0,
                  version INTEGER DEFAULT 1,
                  created_at INTEGER,
                  updated_at INTEGER
                )
              ''');
                await db.execute('''
                CREATE TABLE IF NOT EXISTS courses (
                  id INTEGER PRIMARY KEY AUTOINCREMENT,
                  uuid TEXT UNIQUE,
                  course_name TEXT,
                  teacher_name TEXT,
                  date TEXT,
                  weekday INTEGER,
                  start_time INTEGER,
                  end_time INTEGER,
                  week_index INTEGER,
                  room_name TEXT,
                  lesson_type TEXT,
                  team_uuid TEXT
                )
              ''');
              } catch (_) {}
            }

            if (oldVersion < 12) {
              try {
                await db.execute('''
                CREATE TABLE IF NOT EXISTS time_logs (
                  id INTEGER PRIMARY KEY AUTOINCREMENT,
                  uuid TEXT UNIQUE,
                  task_name TEXT,
                  category TEXT,
                  start_time INTEGER,
                  end_time INTEGER,
                  notes TEXT,
                  color TEXT,
                  is_deleted INTEGER DEFAULT 0,
                  version INTEGER DEFAULT 1,
                  updated_at INTEGER
                )
              ''');
              } catch (_) {}
            }

            if (oldVersion < 13) {
              try {
                await db.execute('''
                CREATE TABLE IF NOT EXISTS pomodoro_tags (
                  id INTEGER PRIMARY KEY AUTOINCREMENT,
                  uuid TEXT UNIQUE,
                  name TEXT,
                  color TEXT,
                  is_deleted INTEGER DEFAULT 0,
                  version INTEGER DEFAULT 1,
                  created_at INTEGER,
                  updated_at INTEGER
                )
              ''');
              } catch (_) {}
            }

            if (oldVersion < 14) {
              try {
                await db.execute("DROP TABLE IF EXISTS time_logs");
                await db.execute('''
                CREATE TABLE IF NOT EXISTS time_logs (
                  id INTEGER PRIMARY KEY AUTOINCREMENT,
                  uuid TEXT UNIQUE,
                  title TEXT,
                  tag_uuids TEXT,
                  start_time INTEGER,
                  end_time INTEGER,
                  remark TEXT,
                  is_deleted INTEGER DEFAULT 0,
                  version INTEGER DEFAULT 1,
                  updated_at INTEGER,
                  created_at INTEGER,
                  device_id TEXT,
                  team_uuid TEXT
                )
              ''');
              } catch (_) {}
            }

            if (oldVersion < 15) {
              try {
                final info = await db.rawQuery("PRAGMA table_info(op_logs)");
                if (!info.any((row) => row['name'] == 'sync_error')) {
                  await db.execute(
                    "ALTER TABLE op_logs ADD COLUMN sync_error TEXT;",
                  );
                }
              } catch (_) {}
            }

            if (oldVersion < 17) {
              try {
                await db.execute('''
                CREATE TABLE IF NOT EXISTS search_history (
                  id INTEGER PRIMARY KEY AUTOINCREMENT,
                  query TEXT NOT NULL,
                  timestamp INTEGER NOT NULL,
                  frequency INTEGER DEFAULT 1,
                  UNIQUE(query)
                )
              ''');
              } catch (_) {}
            }

            if (oldVersion < 18) {
              try {
                final info = await db.rawQuery(
                  "PRAGMA table_info(search_history)",
                );
                for (final col in const [
                  'morning_count',
                  'afternoon_count',
                  'evening_count',
                  'night_count',
                ]) {
                  if (!info.any((row) => row['name'] == col)) {
                    await db.execute(
                      "ALTER TABLE search_history ADD COLUMN $col INTEGER DEFAULT 0;",
                    );
                  }
                }
              } catch (_) {}
            }

            if (oldVersion < 19) {
              try {
                final info = await db.rawQuery("PRAGMA table_info(countdowns)");
                if (!info.any((row) => row['name'] == 'is_completed')) {
                  await db.execute(
                    "ALTER TABLE countdowns ADD COLUMN is_completed INTEGER DEFAULT 0;",
                  );
                }
              } catch (_) {}
            }

            if (oldVersion < 20) {
              try {
                final info = await db.rawQuery("PRAGMA table_info(op_logs)");
                if (!info.any((row) => row['name'] == 'sync_error')) {
                  await db.execute(
                    "ALTER TABLE op_logs ADD COLUMN sync_error TEXT;",
                  );
                }
              } catch (_) {}
            }

            if (oldVersion < 21) {
              try {
                await db.execute('''
                CREATE TABLE IF NOT EXISTS screen_time (
                  id INTEGER PRIMARY KEY AUTOINCREMENT,
                  record_date TEXT,
                  package_name TEXT,
                  app_name TEXT,
                  device_name TEXT,
                  category TEXT,
                  duration INTEGER,
                  updated_at INTEGER
                )
              ''');
                await db.execute(
                  'CREATE INDEX IF NOT EXISTS idx_screen_time_date ON screen_time (record_date)',
                );
                await db.execute('''
      CREATE TABLE IF NOT EXISTS ignored_remote_items (
        uuid TEXT PRIMARY KEY,
        team_uuid TEXT,
        table_name TEXT,
        ignored_at INTEGER
      )
    ''');
              } catch (_) {}
            }

            if (oldVersion < 22) {
              try {
                await db.execute('''
                CREATE TABLE IF NOT EXISTS ignored_remote_items (
                  uuid TEXT PRIMARY KEY,
                  team_uuid TEXT,
                  table_name TEXT,
                  ignored_at INTEGER
                )
              ''');
              } catch (_) {}
            }

            if (oldVersion < 24) {
              await _ensureCourseTableSchema(db);
              await _ensureTodoClientLocalSchema(db);
            }

            if (oldVersion < 25) {
              try {
                await db.execute('''
                CREATE TABLE IF NOT EXISTS todo_plan_blocks (
                  id INTEGER PRIMARY KEY AUTOINCREMENT,
                  uuid TEXT UNIQUE,
                  todo_uuid TEXT,
                  title_snapshot TEXT,
                  start_time INTEGER,
                  end_time INTEGER,
                  planned_minutes INTEGER,
                  status INTEGER,
                  actual_focus_seconds INTEGER,
                  pomodoro_record_ids TEXT,
                  source INTEGER,
                  remark TEXT,
                  reminder_minutes INTEGER,
                  pomodoro_minutes INTEGER DEFAULT 25,
                  pomodoro_rounds INTEGER DEFAULT 0,
                  calendar_event_id TEXT,
                  is_deleted INTEGER DEFAULT 0,
                  version INTEGER DEFAULT 1,
                  created_at INTEGER,
                  updated_at INTEGER,
                  device_id TEXT
                )
              ''');
                final info = await db.rawQuery(
                  "PRAGMA table_info(pomodoro_records)",
                );
                if (!info.any((row) => row['name'] == 'plan_block_id')) {
                  await db.execute(
                    "ALTER TABLE pomodoro_records ADD COLUMN plan_block_id TEXT;",
                  );
                }
              } catch (_) {}
            }

            if (oldVersion < 26) {
              try {
                for (final table in ['pomodoro_tags', 'pomodoro_records']) {
                  final info = await db.rawQuery("PRAGMA table_info($table)");
                  if (!info.any((row) => row['name'] == 'has_conflict')) {
                    await db.execute(
                      "ALTER TABLE $table ADD COLUMN has_conflict INTEGER DEFAULT 0;",
                    );
                    await db.execute(
                      "ALTER TABLE $table ADD COLUMN conflict_data TEXT;",
                    );
                  }
                }
              } catch (_) {}
            }

            if (oldVersion < 27) {
              try {
                await db.execute('''
                  CREATE TABLE IF NOT EXISTS medal_recommendations (
                    medal_id TEXT PRIMARY KEY,
                    alpha REAL DEFAULT 1.0,
                    beta_ REAL DEFAULT 1.0,
                    impression_count INTEGER DEFAULT 0,
                    success_count INTEGER DEFAULT 0,
                    last_shown_at INTEGER DEFAULT 0,
                    last_outcome_at INTEGER DEFAULT 0,
                    feature_score_cache REAL DEFAULT 0.0,
                    updated_at INTEGER DEFAULT 0
                  )
                ''');
              } catch (_) {}
            }

            if (oldVersion < 28) {
              await _ensureSuggestionFeedbackSchema(db);
            }

            if (oldVersion < 29) {
              try {
                final info = await db.rawQuery(
                  "PRAGMA table_info(pomodoro_records)",
                );
                if (!info.any((row) => row['name'] == 'note')) {
                  await db.execute(
                    "ALTER TABLE pomodoro_records ADD COLUMN note TEXT;",
                  );
                }
              } catch (_) {}
            }

            if (oldVersion < 30) {
              await _ensureScreenTimeSchema(db);
            }

            if (oldVersion < 31) {
              try {
                final info = await db.rawQuery(
                  "PRAGMA table_info(pomodoro_tags)",
                );
                if (!info.any((row) => row['name'] == 'is_archived')) {
                  await db.execute(
                    "ALTER TABLE pomodoro_tags ADD COLUMN is_archived INTEGER DEFAULT 0;",
                  );
                }
              } catch (_) {}
            }

            if (oldVersion < 32) {
              try {
                final info = await db.rawQuery(
                  "PRAGMA table_info(pomodoro_records)",
                );
                if (!info.any((row) => row['name'] == 'total_pause_seconds')) {
                  await db.execute(
                    "ALTER TABLE pomodoro_records ADD COLUMN total_pause_seconds INTEGER;",
                  );
                }
                if (!info.any((row) => row['name'] == 'pause_intervals')) {
                  await db.execute(
                    "ALTER TABLE pomodoro_records ADD COLUMN pause_intervals TEXT;",
                  );
                }
              } catch (_) {}
            }

            if (oldVersion < 35) {
              await _ensureFixedScheduleSchema(db);
            }

            if (oldVersion < 38) {
              // 重建 FTS 会清除历史软删除条目，并安装仅监听搜索字段的触发器。
              await _setupFts(db);
            }

            if (oldVersion < 43) {
              await _ensureHabitSchema(db);
            }

            if (oldVersion < 44) {
              await _ensureJournalSchema(db);
            }

            if (oldVersion < 52) {
              await _ensureAiUsageSchema(db);
            }

            if (oldVersion < 54) {
              await _ensureFinanceSchema(db);
            }

            if (oldVersion < 58) {
              await _ensurePlanEditorDraftSchema(db);
            }

            if (oldVersion < 59) {
              await _ensureTodoSkipStateSchema(db);
            }

            if (oldVersion < 60) {
              await _ensureTodoCreatedDateNullable(db);
            }

            if (oldVersion < 61) {
              await _ensureTodoCompletionTimestampSchema(db);
            }
          },
          onOpen: (db) async {
            if (_verifiedSchemaPaths.contains(db.path)) return;
            await _ensureTodoCompletionTimestampSchema(db);
            await _ensurePlanEditorDraftSchema(db);
            await _ensureCourseTableSchema(db);
            await _ensureTodoClientLocalSchema(db);
            await _ensureTodoSkipStateSchema(db);
            await _ensureTodoPlanBlockSchema(db);
            await _ensureFixedScheduleSchema(db);
            await _ensureSuggestionFeedbackSchema(db);
            await _ensureTeamsSchema(db);
            await _ensureScreenTimeSchema(db);
            await _ensureHabitSchema(db);
            await _ensureJournalSchema(db);
            await _ensureFinanceSchema(db);
            await _ensureAiUsageSchema(db);
            await _ensureMissingIndexes(db);
            _verifiedSchemaPaths.add(db.path);
          },
        );
      } catch (e) {
        if (!_isDatabaseLockedError(e) || attempt == 4) rethrow;
        //         debugPrint('⏳ Database: 打开数据库遇到锁，${200 * (attempt + 1)}ms 后重试: $e');
        await Future.delayed(Duration(milliseconds: 200 * (attempt + 1)));
      }
    }

    throw StateError('Database open retry exhausted: $path');
  }

  // ==========================================
  // 🚀 Uni-Sync 4.0: 离线审计系统核心方法
  // ==========================================

  /// 记录本地审计日志
  Future<void> insertLocalAuditLog({
    DatabaseExecutor? databaseOverride,
    String? teamUuid,
    required int userId,
    required String targetTable,
    required String targetUuid,
    required String opType,
    Map<String, dynamic>? beforeData,
    Map<String, dynamic>? afterData,
    String? operatorName,
  }) async {
    final db = databaseOverride ?? await database;
    await db.insert('local_audit_logs', {
      'team_uuid': teamUuid,
      'user_id': userId,
      'target_table': targetTable,
      'target_uuid': targetUuid,
      'op_type': opType,
      'before_data': beforeData != null ? jsonEncode(beforeData) : null,
      'after_data': afterData != null ? jsonEncode(afterData) : null,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'operator_name': operatorName ?? '本地用户',
    });
  }

  /// 获取本地审计日志
  Future<List<Map<String, dynamic>>> getLocalAuditLogs(
    String uuid,
    String table,
  ) async {
    final db = await database;
    final List<Map<String, dynamic>> logs = await db.query(
      'local_audit_logs',
      where: 'target_uuid = ? AND target_table = ?',
      whereArgs: [uuid, table],
      orderBy: 'timestamp DESC',
      limit: 50,
    );
    return logs;
  }

  Future<String> _resolveDatabasePath(String targetName) async {
    return resolveDatabasePath(targetName);
  }

  /// 执行本地回滚 (离线模式)
  Future<bool> rollbackFromLocalLog(int logId) async {
    final db = await database;
    final log = await db.query(
      'local_audit_logs',
      where: 'id = ?',
      whereArgs: [logId],
    );
    if (log.isEmpty) return false;

    final targetTable = log.first['target_table'] as String;
    final targetUuid = log.first['target_uuid'] as String;
    final beforeDataStr = log.first['before_data'] as String?;

    if (beforeDataStr == null) return false;
    final Map<String, dynamic> beforeData = jsonDecode(beforeDataStr);

    // 根据表名还原数据
    if (targetTable == 'todos') {
      await db.update(
        'todos',
        {
          'content': beforeData['content'],
          'remark': beforeData['remark'],
          'is_completed':
              (beforeData['is_completed'] == 1 ||
                  beforeData['is_completed'] == true)
              ? 1
              : 0,
          'due_date': beforeData['due_date'] ?? 0,
          'created_date': beforeData['created_date'] ?? 0,
          'group_id': beforeData['group_id'],
          'team_uuid': beforeData['team_uuid'],
          'collab_type': beforeData['collab_type'] ?? 0,
          'is_all_day':
              (beforeData['is_all_day'] == 1 ||
                  beforeData['is_all_day'] == true)
              ? 1
              : 0,
          'recurrence': beforeData['recurrence'] ?? 0,
          'reminder_minutes': beforeData['reminder_minutes'] ?? -1,
          'updated_at': DateTime.now().millisecondsSinceEpoch,
          'version': (beforeData['version'] ?? 0) + 1,
        },
        where: 'uuid = ?',
        whereArgs: [targetUuid],
      );
    } else if (targetTable == 'countdowns') {
      await db.update(
        'countdowns',
        {
          'title': beforeData['title'],
          'target_time': beforeData['target_time'],
          'is_deleted':
              (beforeData['is_deleted'] == 1 ||
                  beforeData['is_deleted'] == true)
              ? 1
              : 0,
          'is_completed':
              (beforeData['is_completed'] == 1 ||
                  beforeData['is_completed'] == true)
              ? 1
              : 0,
          'updated_at': DateTime.now().millisecondsSinceEpoch,
          'version': (beforeData['version'] ?? 0) + 1,
        },
        where: 'uuid = ?',
        whereArgs: [targetUuid],
      );
    }
    return true;
  }

  /// 🚀 Uni-Sync 4.0: 从传统的 SharedPreferences 迁移数据到 SQL
  Future<void> migrateFromPrefs(
    String username,
    List<Map<String, dynamic>> legacyData,
  ) async {
    final db = await database;
    await db.transaction((txn) async {
      for (var json in legacyData) {
        await txn.insert('todos', {
          'uuid': json['uuid'] ?? json['id'],
          'content': json['content'] ?? json['title'],
          'remark': json['remark'],
          'is_completed': (json['is_completed'] == 1 || json['is_done'] == true)
              ? 1
              : 0,
          'is_deleted': (json['is_deleted'] == 1 || json['is_deleted'] == true)
              ? 1
              : 0,
          'version': json['version'] ?? 1,
          'updated_at':
              json['updated_at'] ?? DateTime.now().millisecondsSinceEpoch,
          'created_at':
              json['created_at'] ??
              json['createdDate'] ??
              DateTime.now().millisecondsSinceEpoch,
          'created_date':
              json['created_date'] ??
              json['created_at'] ??
              json['createdDate'] ??
              DateTime.now().millisecondsSinceEpoch,
          // 🚀 核心防御：提供 0 兜底，防止 SQLite NOT NULL 报错
          'due_date': json['due_date'] ?? json['dueDate'] ?? 0,
          // 🚀 补全协作元数据
          'team_uuid': json['team_uuid'] ?? json['teamUuid'],
          'creator_id': json['creator_id'] ?? json['creatorId'],
          'creator_name': json['creator_name'] ?? json['creatorName'],
          'team_name': json['team_name'] ?? json['teamName'],
          'group_id': json['group_id'] ?? json['groupId'],
          'recurrence': json['recurrence'] ?? 0,
          'recurrence_series_id':
              json['recurrence_series_id'] ?? json['recurrenceSeriesId'],
          'custom_interval_days':
              json['custom_interval_days'] ?? json['customIntervalDays'] ?? 0,
          // 🚀 核心防御：提供 0 / -1 兜底，防止 SQLite NOT NULL 报错
          'recurrence_end_date':
              json['recurrence_end_date'] ?? json['recurrenceEndDate'] ?? 0,
          'reminder_minutes':
              json['reminder_minutes'] ?? json['reminderMinutes'] ?? -1,
          'image_path': json['image_path'] ?? json['imagePath'],
          'original_text': json['original_text'] ?? json['originalText'],
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
      }
    });
    //     debugPrint("✅ Database Migration: $username's data moved to SQLite.");
  }

  Future _createDB(Database db, int version) async {
    const idType = 'INTEGER PRIMARY KEY AUTOINCREMENT';
    const textType = 'TEXT NOT NULL';
    const jsonType = 'TEXT';
    const integerType = 'INTEGER NOT NULL';
    const boolType = 'INTEGER NOT NULL'; // 0 or 1

    // 1. 核心任务表 (兼容现有字段)
    await db.execute('''
      CREATE TABLE IF NOT EXISTS todos (
        id $idType,
        uuid $textType UNIQUE,
        team_uuid $jsonType,
        group_id $jsonType,
        content $textType,
        remark $jsonType,
        team_name $jsonType, 
        creator_id $jsonType,
        creator_name $jsonType,
        is_completed $boolType DEFAULT 0,
        is_skipped $boolType DEFAULT 0,
        is_skipped_sync_pending $boolType DEFAULT 0,
        is_deleted $boolType DEFAULT 0,
        version $integerType DEFAULT 1,
        due_date $jsonType,
        created_date INTEGER,
        created_at $integerType,
        updated_at $integerType,
        collab_type $integerType DEFAULT 0,
        recurrence $integerType DEFAULT 0,
        recurrence_series_id TEXT,
        custom_interval_days INTEGER NOT NULL DEFAULT 0,
        recurrence_end_date INTEGER,
        reminder_minutes INTEGER,
        has_conflict INTEGER DEFAULT 0,
        conflict_data TEXT,
        is_all_day INTEGER DEFAULT 0,
        image_path TEXT,
        original_text TEXT,
        completed_at INTEGER
      )
    ''');

    // 2. 倒数日表
    await db.execute('''
      CREATE TABLE IF NOT EXISTS countdowns (
        id $idType,
        uuid $textType UNIQUE,
        team_uuid $jsonType,
        team_name $jsonType,
        creator_id $jsonType,
        creator_name $jsonType,
        title $textType,
        target_time $integerType,
        is_deleted $boolType DEFAULT 0,
        is_completed $boolType DEFAULT 0,
        version $integerType DEFAULT 1,
        created_at $integerType,
        updated_at $integerType,
        has_conflict INTEGER DEFAULT 0,
        conflict_data TEXT
      )
    ''');

    // 3. 待办组表 (文件夹)
    await db.execute('''
      CREATE TABLE IF NOT EXISTS todo_groups (
        id $idType,
        uuid $textType UNIQUE,
        team_uuid $jsonType,
        team_name $jsonType,
        creator_id $jsonType,
        creator_name $jsonType,
        name $textType,
        is_expanded $boolType DEFAULT 0,
        is_deleted $boolType DEFAULT 0,
        version $integerType DEFAULT 1,
        created_at $integerType,
        updated_at $integerType,
        has_conflict INTEGER DEFAULT 0,
        conflict_data TEXT
      )
    ''');

    // 4. 🚀 Uni-Sync 核心：离线操作日志表 (Oplog)
    await db.execute('''
      CREATE TABLE IF NOT EXISTS op_logs (
        id $idType,
        op_type $textType, 
        target_table $textType,
        target_uuid $textType,
        data_json $jsonType,
        timestamp $integerType,
        is_synced $boolType DEFAULT 0,
        sync_error $textType
      )
    ''');

    // 5. 独立待办完成情况表
    await db.execute('''
      CREATE TABLE IF NOT EXISTS todo_completions (
        todo_uuid TEXT,
        user_id INTEGER,
        is_completed INTEGER,
        is_skipped INTEGER NOT NULL DEFAULT 0,
        is_skipped_sync_pending INTEGER NOT NULL DEFAULT 0,
        updated_at INTEGER,
        PRIMARY KEY(todo_uuid, user_id)
      )
    ''');

    // 6. 🚀 Uni-Sync 核心：持久化索引
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_todos_team ON todos(team_uuid)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_todos_uuid ON todos(uuid)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_countdowns_team ON countdowns(team_uuid)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_countdowns_uuid ON countdowns(uuid)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_todo_groups_team ON todo_groups(team_uuid)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_todo_groups_uuid ON todo_groups(uuid)',
    );

    // 7. 🚀 Uni-Sync 核心：离线审计日志 (支持离线查看版本记录)
    await db.execute('''
      CREATE TABLE IF NOT EXISTS local_audit_logs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        team_uuid TEXT,
        user_id INTEGER,
        target_table TEXT,
        target_uuid TEXT,
        op_type TEXT,
        before_data TEXT,
        after_data TEXT,
        timestamp INTEGER,
        operator_name TEXT
      )
    ''');

    // 🚀 Uni-Sync 核心：初始化 FTS 搜索引擎 (带嗅探)
    await _setupFts(db);

    // 8. 创建番茄钟记录表
    await db.execute('''
      CREATE TABLE IF NOT EXISTS pomodoro_records (
        id $idType,
        uuid $textType UNIQUE,
        todo_uuid $jsonType,
        todo_title $jsonType,
        tag_uuids $jsonType,
        start_time $integerType,
        end_time $integerType,
        planned_duration $integerType,
        actual_duration $integerType,
        status $textType,
        device_id $jsonType,
        plan_block_id TEXT,
        note TEXT,
        total_pause_seconds INTEGER,
        pause_intervals TEXT,
        is_deleted $boolType DEFAULT 0,
        version $integerType DEFAULT 1,
        created_at $integerType,
        updated_at $integerType,
        has_conflict INTEGER DEFAULT 0,
        conflict_data TEXT
      )
    ''');

    // 9. 创建课表表
    await db.execute('''
      CREATE TABLE IF NOT EXISTS courses (
        id $idType,
        uuid $textType UNIQUE,
        course_name $textType,
        teacher_name $jsonType,
        date $textType,
        weekday $integerType,
        start_time $integerType,
        end_time $integerType,
        week_index $integerType,
        room_name $jsonType,
        lesson_type $jsonType,
        team_uuid $jsonType,
        is_deleted $boolType DEFAULT 0,
        version $integerType DEFAULT 1,
        updated_at $integerType,
        created_at $integerType
      )
    ''');

    // 10. 创建时间日志表
    await db.execute('''
      CREATE TABLE IF NOT EXISTS time_logs (
        id $idType,
        uuid $textType UNIQUE,
        title $textType,
        tag_uuids $jsonType,
        start_time $integerType,
        end_time $integerType,
        remark $jsonType,
        is_deleted $boolType DEFAULT 0,
        version $integerType DEFAULT 1,
        updated_at $integerType,
        created_at $integerType,
        device_id $textType,
        team_uuid $textType
      )
    ''');

    // 11. 创建番茄钟标签表
    await db.execute('''
      CREATE TABLE IF NOT EXISTS pomodoro_tags (
        id $idType,
        uuid $textType UNIQUE,
        name $textType,
        color $jsonType,
        is_deleted $boolType DEFAULT 0,
        is_archived $boolType DEFAULT 0,
        version $integerType DEFAULT 1,
        created_at $integerType,
        updated_at $integerType,
        has_conflict INTEGER DEFAULT 0,
        conflict_data TEXT
      )
    ''');

    // 12. 创建搜索历史表
    await db.execute('''
      CREATE TABLE IF NOT EXISTS search_history (
        id $idType,
        query $textType UNIQUE,
        timestamp $integerType,
        frequency $integerType DEFAULT 1,
        morning_count INTEGER DEFAULT 0,
        afternoon_count INTEGER DEFAULT 0,
        evening_count INTEGER DEFAULT 0,
        night_count INTEGER DEFAULT 0
      )
    ''');
    // 🚀 Version 21: 新增屏幕时间记录表
    await db.execute('''
      CREATE TABLE IF NOT EXISTS screen_time (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        record_date TEXT,
        package_name TEXT,
        app_name TEXT,
        device_name TEXT,
        category TEXT,
        duration INTEGER,
        updated_at INTEGER
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_screen_time_date ON screen_time (record_date)',
    );
    // 🚀 Version 22: 新增 ignored_remote_items 表
    await db.execute('''
      CREATE TABLE IF NOT EXISTS ignored_remote_items (
        uuid TEXT PRIMARY KEY,
        team_uuid TEXT,
        table_name TEXT,
        ignored_at INTEGER
      )
    ''');
    //     debugPrint('✅ Database: onCreate 创建 ignored_remote_items 表');

    // 13. 创建规划块表
    await db.execute('''
      CREATE TABLE IF NOT EXISTS todo_plan_blocks (
        id $idType,
        uuid $textType UNIQUE,
        todo_uuid $jsonType,
        title_snapshot $textType,
        start_time $integerType,
        end_time $integerType,
        planned_minutes $integerType,
        status $integerType DEFAULT 0,
        actual_focus_seconds $integerType DEFAULT 0,
        pomodoro_record_ids $jsonType,
        source $integerType DEFAULT 0,
        remark $jsonType,
        reminder_minutes $integerType DEFAULT 5,
        pomodoro_minutes $integerType DEFAULT 25,
        pomodoro_rounds $integerType DEFAULT 0,
        calendar_event_id $textType,
        is_deleted $boolType DEFAULT 0,
        version $integerType DEFAULT 1,
        created_at $integerType,
        updated_at $integerType,
        device_id $jsonType
      )
    ''');

    // 14. 创建固定日程表
    await _ensureFixedScheduleSchema(db);

    // 15. 创建勋章推荐 ML 跟踪表
    await db.execute('''
      CREATE TABLE IF NOT EXISTS medal_recommendations (
        medal_id TEXT PRIMARY KEY,
        alpha REAL DEFAULT 1.0,
        beta_ REAL DEFAULT 1.0,
        impression_count INTEGER DEFAULT 0,
        success_count INTEGER DEFAULT 0,
        last_shown_at INTEGER DEFAULT 0,
        last_outcome_at INTEGER DEFAULT 0,
        feature_score_cache REAL DEFAULT 0.0,
        updated_at INTEGER DEFAULT 0
      )
    ''');

    // 16. 创建建议反馈表
    await _ensureSuggestionFeedbackSchema(db);

    // 17. 创建团队缓存表
    await _ensureTeamsSchema(db);

    // 18. 创建习惯追踪表
    await _ensureHabitSchema(db);

    // 19. 创建本地私密日记表
    await _ensureJournalSchema(db);

    // 20. 创建个人记账表、预算和自动化表
    await _ensureFinanceSchema(db);
    await _ensureAiUsageSchema(db);

    // 21. 创建性能索引
    await _ensureCourseTableSchema(db);
    await _ensurePlanEditorDraftSchema(db);
    await _ensureMissingIndexes(db);
  }
}

// Cached RegExp patterns
final RegExp _rxCached28_1 = RegExp(
  r'^\s*CREATE\s+TABLE\s+(?:IF\s+NOT\s+EXISTS\s+)?(?:"todos"|`todos`|\[todos\]|todos)(?=\s*\()',
  caseSensitive: false,
);
final RegExp _rxCached28_2 = RegExp(
  r'(\bcreated_date\b\s+INTEGER)\s+NOT\s+NULL\b',
  caseSensitive: false,
);
