import 'dart:async';
import 'dart:convert';
import 'package:path/path.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'environment_service.dart';
import 'package:flutter/foundation.dart';
import '../models.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    final prefs = await SharedPreferences.getInstance();
    final username = prefs.getString('current_login_user') ?? 'default';

    if (_database != null) {
      // 🚀 核心校验：如果当前打开的数据库与当前登录用户不符，则强制关闭并重新打开
      if (!_database!.path.contains('uni_sync_$username')) {
        debugPrint("🔄 Database: 检测到用户切换 ($username)，正在强制重定向数据库文件...");
        await closeDatabase();
      } else {
        return _database!;
      }
    }
    _database = await _initDB('uni_sync_$username.db');
    return _database!;
  }

  /// 🚀 Uni-Sync: 强制关闭并重置数据库连接（用于登出或切换用户）
  Future<void> closeDatabase() async {
    if (_database != null) {
      await _database!.close();
      _database = null;
    }
  }

  Future<Database> _initDB(String filePath) async {
    // 🚀 桌面端 SQL 引擎初始化已由 main.dart 统一处理

    final dbPath = await getDatabasesPath();
    // 🚀 根据环境动态选择前缀（隔离测试数据）
    final envPrefix = EnvironmentService.isTest ? 'test_v5_' : 'v4_';
    final targetName = envPrefix + filePath;
    final path = join(dbPath, targetName);

    return await openDatabase(
        path,
        version: 19, // 🚀 V19: 倒数日增加 is_completed 字段支持时间轴统计
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
                    await db.execute("ALTER TABLE $table ADD COLUMN $col TEXT;");
                  }
                } catch (_) { }
              }
            }
          }

          // 🚀 Version 5: 核心加固 - 补全基础字段与 FTS 模块动态嗅探
          if (oldVersion < 5) {
            debugPrint("🔄 Database: 执行 Version 5 核心修复程序...");

            // 1. 深度补全缺失的核心业务列
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

            for (var task in repairTasks) {
              try {
                final info = await db.rawQuery("PRAGMA table_info(${task['table']})");
                if (!info.any((row) => row['name'] == task['col'])) {
                  await db.execute("ALTER TABLE ${task['table']} ADD COLUMN ${task['col']} ${task['type']};");
                  debugPrint("✅ Database: 修复字段 ${task['table']}.${task['col']}");
                }
              } catch (e) {
                debugPrint("⚠️ Database: 修复字段 ${task['table']}.${task['col']} 失败: $e");
              }
            }

            // 2. 强制重建 FTS 架构（采用动态嗅探）
            await _setupFts(db);
          }

          if (oldVersion < 6) {
            try {
              final info = await db.rawQuery("PRAGMA table_info(todos)");
              if (!info.any((row) => row['name'] == 'collab_type')) {
                await db.execute("ALTER TABLE todos ADD COLUMN collab_type INTEGER DEFAULT 0;");
                debugPrint("✅ Database: 修复字段 todos.collab_type");
              }
            } catch (e) {
              debugPrint("⚠️ Database: 修复字段 todos.collab_type 失败: $e");
            }
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
              debugPrint("✅ Database: 创建 todo_completions 表");
            } catch (e) {
              debugPrint("⚠️ Database: 创建 todo_completions 表失败: $e");
            }
          }

          if (oldVersion < 8) {
            try {
              final columns = [
                {'name': 'recurrence', 'type': 'INTEGER DEFAULT 0'},
                {'name': 'custom_interval_days', 'type': 'INTEGER'},
                {'name': 'recurrence_end_date', 'type': 'INTEGER'},
                {'name': 'reminder_minutes', 'type': 'INTEGER'},
              ];
              for (var col in columns) {
                final info = await db.rawQuery("PRAGMA table_info(todos)");
                if (!info.any((row) => row['name'] == col['name'])) {
                  await db.execute("ALTER TABLE todos ADD COLUMN ${col['name']} ${col['type']};");
                  debugPrint("✅ Database: 修复字段 todos.${col['name']}");
                }
              }
            } catch (e) {
              debugPrint("⚠️ Database: 修复字段 todos 循环任务字段失败: $e");
            }
          }
          if (oldVersion < 9) {
            try {
              final tables = ['todos', 'countdowns', 'todo_groups'];
              for (var table in tables) {
                final info = await db.rawQuery("PRAGMA table_info($table)");
                if (!info.any((row) => row['name'] == 'has_conflict')) {
                  await db.execute("ALTER TABLE $table ADD COLUMN has_conflict INTEGER DEFAULT 0;");
                  await db.execute("ALTER TABLE $table ADD COLUMN conflict_data TEXT;");
                  debugPrint("✅ Database: 修复字段 $table.has_conflict");
                }
              }
              // 特别补全 todos 的 is_all_day
              final todoInfo = await db.rawQuery("PRAGMA table_info(todos)");
              if (!todoInfo.any((row) => row['name'] == 'is_all_day')) {
                await db.execute("ALTER TABLE todos ADD COLUMN is_all_day INTEGER DEFAULT 0;");
              }
            } catch (e) {
              debugPrint("⚠️ Database: 修复冲突检测字段失败: $e");
            }
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
              debugPrint("✅ Database: 创建 local_audit_logs 表");
            } catch (e) {
              debugPrint("⚠️ Database: 创建 local_audit_logs 失败: $e");
            }
          }
          if (oldVersion < 11) {
            try {
              // 1. 创建番茄钟记录表
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
              // 2. 创建课表表
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
              debugPrint("✅ Database: 创建 pomodoro_records 与 courses 表");
            } catch (e) {
              debugPrint("⚠️ Database: 创建新业务表失败: $e");
            }
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
              debugPrint("✅ Database: 创建 time_logs 表");
            } catch (e) {
              debugPrint("⚠️ Database: 创建 time_logs 失败: $e");
            }
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
              debugPrint("✅ Database: 创建 pomodoro_tags 表");
            } catch (e) {
              debugPrint("⚠️ Database: 创建 pomodoro_tags 失败: $e");
            }
          }

          if (oldVersion < 14) {
            try {
              // 修正时间日志表字段
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
              debugPrint("✅ Database: 重新创建 time_logs 表 (V14)");
            } catch (e) {
              debugPrint("⚠️ Database: 升级 V14 失败: $e");
            }
          }
          if (oldVersion < 15) {
            try {
              final info = await db.rawQuery("PRAGMA table_info(op_logs)");
              if (!info.any((row) => row['name'] == 'sync_error')) {
                await db.execute("ALTER TABLE op_logs ADD COLUMN sync_error TEXT;");
                debugPrint("✅ Database: 为 op_logs 添加 sync_error 字段 (V15)");
              }
            } catch (e) {
              debugPrint("⚠️ Database: 升级 V15 失败: $e");
            }
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
              debugPrint("✅ Database: 创建 search_history 表 (V17)");
            } catch (e) {
              debugPrint("⚠️ Database: 升级 V17 失败: $e");
            }
          }
          if (oldVersion < 18) {
            try {
              // 为历史记录增加分时统计列
              await db.execute("ALTER TABLE search_history ADD COLUMN morning_count INTEGER DEFAULT 0;");
              await db.execute("ALTER TABLE search_history ADD COLUMN afternoon_count INTEGER DEFAULT 0;");
              await db.execute("ALTER TABLE search_history ADD COLUMN evening_count INTEGER DEFAULT 0;");
              await db.execute("ALTER TABLE search_history ADD COLUMN night_count INTEGER DEFAULT 0;");
              debugPrint("✅ Database: 升级 search_history 分时统计字段 (V18)");
            } catch (e) {
              debugPrint("⚠️ Database: 升级 V18 失败: $e");
            }
          }
          if (oldVersion < 19) {
            try {
              final info = await db.rawQuery("PRAGMA table_info(countdowns)");
              if (!info.any((row) => row['name'] == 'is_completed')) {
                await db.execute("ALTER TABLE countdowns ADD COLUMN is_completed INTEGER DEFAULT 0;");
                debugPrint("✅ Database: 为 countdowns 添加 is_completed 字段 (V19)");
              }
            } catch (e) {
              debugPrint("⚠️ Database: 升级 V19 失败: $e");
            }
          }
        }
    );
  }

  // ==========================================
  // 🚀 Uni-Sync 4.0: 离线审计系统核心方法
  // ==========================================

  /// 记录本地审计日志
  Future<void> insertLocalAuditLog({
    String? teamUuid,
    required int userId,
    required String targetTable,
    required String targetUuid,
    required String opType,
    Map<String, dynamic>? beforeData,
    Map<String, dynamic>? afterData,
    String? operatorName,
  }) async {
    final db = await database;
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
  Future<List<Map<String, dynamic>>> getLocalAuditLogs(String uuid, String table) async {
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

  /// 执行本地回滚 (离线模式)
  Future<bool> rollbackFromLocalLog(int logId) async {
    final db = await database;
    final log = await db.query('local_audit_logs', where: 'id = ?', whereArgs: [logId]);
    if (log.isEmpty) return false;

    final targetTable = log.first['target_table'] as String;
    final targetUuid = log.first['target_uuid'] as String;
    final beforeDataStr = log.first['before_data'] as String?;

    if (beforeDataStr == null) return false;
    final Map<String, dynamic> beforeData = jsonDecode(beforeDataStr);

    // 根据表名还原数据
    if (targetTable == 'todos') {
      await db.update('todos', {
        'content': beforeData['content'],
        'remark': beforeData['remark'],
        'is_completed': (beforeData['is_completed'] == 1 || beforeData['is_completed'] == true) ? 1 : 0,
        'due_date': beforeData['due_date'] ?? 0,
        'created_date': beforeData['created_date'] ?? 0,
        'group_id': beforeData['group_id'],
        'team_uuid': beforeData['team_uuid'],
        'collab_type': beforeData['collab_type'] ?? 0,
        'is_all_day': (beforeData['is_all_day'] == 1 || beforeData['is_all_day'] == true) ? 1 : 0,
        'recurrence': beforeData['recurrence'] ?? 0,
        'reminder_minutes': beforeData['reminder_minutes'] ?? -1,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
        'version': (beforeData['version'] ?? 0) + 1,
      }, where: 'uuid = ?', whereArgs: [targetUuid]);
    } else if (targetTable == 'countdowns') {
      await db.update('countdowns', {
        'title': beforeData['title'],
        'target_time': beforeData['target_time'],
        'is_deleted': (beforeData['is_deleted'] == 1 || beforeData['is_deleted'] == true) ? 1 : 0,
        'is_completed': (beforeData['is_completed'] == 1 || beforeData['is_completed'] == true) ? 1 : 0,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
        'version': (beforeData['version'] ?? 0) + 1,
      }, where: 'uuid = ?', whereArgs: [targetUuid]);
    }
    return true;
  }

  /// 🚀 Uni-Sync 4.0: 从传统的 SharedPreferences 迁移数据到 SQL
  Future<void> migrateFromPrefs(String username, List<Map<String, dynamic>> legacyData) async {
    final db = await database;
    await db.transaction((txn) async {
      for (var json in legacyData) {
        await txn.insert('todos', {
          'uuid': json['uuid'] ?? json['id'],
          'content': json['content'] ?? json['title'],
          'remark': json['remark'],
          'is_completed': (json['is_completed'] == 1 || json['is_done'] == true) ? 1 : 0,
          'is_deleted': (json['is_deleted'] == 1 || json['is_deleted'] == true) ? 1 : 0,
          'version': json['version'] ?? 1,
          'updated_at': json['updated_at'] ?? DateTime.now().millisecondsSinceEpoch,
          'created_at': json['created_at'] ?? json['createdDate'] ?? DateTime.now().millisecondsSinceEpoch,
          'created_date': json['created_date'] ?? json['created_at'] ?? json['createdDate'] ?? DateTime.now().millisecondsSinceEpoch,
          // 🚀 核心防御：提供 0 兜底，防止 SQLite NOT NULL 报错
          'due_date': json['due_date'] ?? json['dueDate'] ?? 0,
          // 🚀 补全协作元数据
          'team_uuid': json['team_uuid'] ?? json['teamUuid'],
          'creator_id': json['creator_id'] ?? json['creatorId'],
          'creator_name': json['creator_name'] ?? json['creatorName'],
          'team_name': json['team_name'] ?? json['teamName'],
          'group_id': json['group_id'] ?? json['groupId'],
          'recurrence': json['recurrence'] ?? 0,
          'custom_interval_days': json['custom_interval_days'] ?? json['customIntervalDays'] ?? 0,
          // 🚀 核心防御：提供 0 / -1 兜底，防止 SQLite NOT NULL 报错
          'recurrence_end_date': json['recurrence_end_date'] ?? json['recurrenceEndDate'] ?? 0,
          'reminder_minutes': json['reminder_minutes'] ?? json['reminderMinutes'] ?? -1,
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
      }
    });
    debugPrint("✅ Database Migration: $username's data moved to SQLite.");
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
        is_deleted $boolType DEFAULT 0,
        version $integerType DEFAULT 1,
        due_date $jsonType,
        created_date $integerType,
        created_at $integerType,
        updated_at $integerType,
        collab_type $integerType DEFAULT 0,
        recurrence $integerType DEFAULT 0,
        custom_interval_days INTEGER NOT NULL DEFAULT 0,
        recurrence_end_date INTEGER,
        reminder_minutes INTEGER,
        has_conflict INTEGER DEFAULT 0,
        conflict_data TEXT,
        is_all_day INTEGER DEFAULT 0
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
        is_synced $boolType DEFAULT 0
      )
    ''');

    // 5. 独立待办完成情况表
    await db.execute('''
      CREATE TABLE IF NOT EXISTS todo_completions (
        todo_uuid TEXT,
        user_id INTEGER,
        is_completed INTEGER,
        updated_at INTEGER,
        PRIMARY KEY(todo_uuid, user_id)
      )
    ''');

    // 6. 🚀 Uni-Sync 核心：持久化索引
    await db.execute('CREATE INDEX IF NOT EXISTS idx_todos_team ON todos(team_uuid)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_todos_uuid ON todos(uuid)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_countdowns_team ON countdowns(team_uuid)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_countdowns_uuid ON countdowns(uuid)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_todo_groups_team ON todo_groups(team_uuid)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_todo_groups_uuid ON todo_groups(uuid)');

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
        is_deleted $boolType DEFAULT 0,
        version $integerType DEFAULT 1,
        created_at $integerType,
        updated_at $integerType
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
        version $integerType DEFAULT 1,
        created_at $integerType,
        updated_at $integerType
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
  }

  /// 🚀 初始化 FTS 搜索引擎，支持 FTS5 -> FTS4 -> LIKE 逐级降级 (带主动探测)
  Future<void> _setupFts(Database db) async {
    // 0. 清理阶段：强制移除所有虚表和触发器，确保状态干净
    final cleanups = [
      'DROP TRIGGER IF EXISTS todos_after_insert',
      'DROP TRIGGER IF EXISTS todos_after_update',
      'DROP TRIGGER IF EXISTS todos_after_delete',
      'DROP TABLE IF EXISTS todos_fts',
    ];
    for (var sql in cleanups) {
      try { await db.execute(sql); } catch (_) {}
    }

    // 1. 尝试 FTS5 (主动探测模块是否存在)
    bool useFts5 = false;
    try {
      await db.execute('CREATE VIRTUAL TABLE _fts5_test USING fts5(c)');
      await db.execute('DROP TABLE _fts5_test');
      useFts5 = true;
    } catch (_) {}

    if (useFts5) {
      try {
        await db.execute('''
          CREATE VIRTUAL TABLE todos_fts USING fts5(
            uuid UNINDEXED, content, remark, team_name, tokenize='unicode61' 
          )
        ''');
        // 🚀 核心修复：将存量数据导入 FTS 索引
        await db.execute('''
          INSERT INTO todos_fts(uuid, content, remark, team_name)
          SELECT uuid, content, remark, team_name FROM todos WHERE is_deleted = 0
        ''');
        await _createFtsTriggers(db);
        debugPrint("✅ Database: FTS5 搜索引擎就绪并已同步存量数据");
        return;
      } catch (e) {
        debugPrint("⚠️ Database: FTS5 初始化失败: $e");
      }
    }

    // 2. 尝试 FTS4 (主动探测)
    bool useFts4 = false;
    try {
      await db.execute('CREATE VIRTUAL TABLE _fts4_test USING fts4(c)');
      await db.execute('DROP TABLE _fts4_test');
      useFts4 = true;
    } catch (_) {}

    if (useFts4) {
      try {
        await db.execute('''
          CREATE VIRTUAL TABLE todos_fts USING fts4(
            uuid, content, remark, team_name, tokenize=unicode61
          )
        ''');
        // 🚀 核心修复：将存量数据导入 FTS 索引
        await db.execute('''
          INSERT INTO todos_fts(uuid, content, remark, team_name)
          SELECT uuid, content, remark, team_name FROM todos WHERE is_deleted = 0
        ''');
        await _createFtsTriggers(db);
        debugPrint("✅ Database: FTS4 搜索引擎就绪并已同步存量数据");
        return;
      } catch (e) {
        debugPrint("⚠️ Database: FTS4 初始化失败: $e");
      }
    }

    debugPrint("❌ Database: 硬件/系统不支持 FTS 索引，已切换至 LIKE 模式");
  }

  /// 🚀 创建 FTS 实时同步触发器
  Future<void> _createFtsTriggers(Database db) async {
    await db.execute('''
      CREATE TRIGGER IF NOT EXISTS todos_after_insert AFTER INSERT ON todos BEGIN
        INSERT INTO todos_fts(uuid, content, remark, team_name) VALUES (new.uuid, new.content, new.remark, new.team_name);
      END;
    ''');

    await db.execute('''
      CREATE TRIGGER IF NOT EXISTS todos_after_update AFTER UPDATE ON todos BEGIN
        UPDATE todos_fts SET content = new.content, remark = new.remark, team_name = new.team_name WHERE uuid = old.uuid;
      END;
    ''');

    await db.execute('''
      CREATE TRIGGER IF NOT EXISTS todos_after_delete AFTER DELETE ON todos BEGIN
        DELETE FROM todos_fts WHERE uuid = old.uuid;
      END;
    ''');
  }

  // --- 通用操作接口 ---

  Future<int> insertOpLog(String opType, String table, String uuid, Map<String, dynamic> data) async {
    final db = await instance.database;
    return await db.insert('op_logs', {
      'op_type': opType,
      'target_table': table,
      'target_uuid': uuid,
      'data_json': jsonEncode(data),
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'is_synced': 0
    });
  }

  Future<Map<String, dynamic>?> getTodoByUuid(String uuid) async {
    final db = await instance.database;
    final results = await db.query('todos', where: 'uuid = ?', whereArgs: [uuid], limit: 1);
    return results.isNotEmpty ? results.first : null;
  }

  Future<List<Map<String, dynamic>>> searchTodos(String query) async {
    final db = await instance.database;
    final Map<String, Map<String, dynamic>> resultsMap = {};

    // 1. 尝试 FTS 搜索引擎 (高性能前缀匹配)
    final tables = await db.rawQuery("SELECT name FROM sqlite_master WHERE type='table' AND name='todos_fts'");
    if (tables.isNotEmpty) {
      try {
        final ftsCount = Sqflite.firstIntValue(await db.rawQuery("SELECT COUNT(*) FROM todos_fts")) ?? 0;
        final actualCount = Sqflite.firstIntValue(await db.rawQuery("SELECT COUNT(*) FROM todos WHERE is_deleted = 0")) ?? 0;
        if (ftsCount == 0 && actualCount > 0) {
          await db.execute("INSERT INTO todos_fts(uuid, content, remark, team_name) SELECT uuid, content, remark, team_name FROM todos WHERE is_deleted = 0");
        }

        final ftsQuery = query.split(' ').where((s) => s.isNotEmpty).map((s) => '$s*').join(' ');
        final ftsResults = await db.rawQuery('''
          SELECT t.* FROM todos t
          JOIN todos_fts f ON t.uuid = f.uuid
          WHERE todos_fts MATCH ?
          AND t.is_deleted = 0
          LIMIT 20
        ''', [ftsQuery]);
        
        for (var r in ftsResults) {
          resultsMap[r['uuid'].toString()] = r;
        }
      } catch (e) {
        debugPrint("FTS error: $e");
      }
    }

    // 2. 补全 LIKE 搜索 (解决中文分词无法匹配中间词的问题)
    // 如果 FTS 结果不足，或者包含中文字符，则使用 LIKE 增强召回
    if (resultsMap.length < 20) {
      final likeResults = await db.rawQuery('''
        SELECT * FROM todos 
        WHERE is_deleted = 0 
        AND (content LIKE ? OR remark LIKE ?)
        ORDER BY updated_at DESC
        LIMIT 20
      ''', ['%$query%', '%$query%']);
      
      for (var r in likeResults) {
        resultsMap[r['uuid'].toString()] = r;
      }
    }

    final finalResults = resultsMap.values.toList();
    // 按更新时间降序排序
    finalResults.sort((a, b) => (b['updated_at'] ?? 0).compareTo(a['updated_at'] ?? 0));
    return finalResults.take(20).toList();
  }

  Future<List<Map<String, dynamic>>> searchTodoGroups(String query) async {
    final db = await instance.database;
    return await db.rawQuery('''
      SELECT * FROM todo_groups 
      WHERE is_deleted = 0 
      AND name LIKE ?
      ORDER BY updated_at DESC
      LIMIT 10
    ''', ['%$query%']);
  }

  Future<List<Map<String, dynamic>>> searchCourses(String query) async {
    final db = await instance.database;
    return await db.rawQuery('''
      SELECT * FROM courses 
      WHERE is_deleted = 0 
      AND (course_name LIKE ? OR teacher_name LIKE ? OR room_name LIKE ?)
      ORDER BY updated_at DESC
      LIMIT 15
    ''', ['%$query%', '%$query%', '%$query%']);
  }

  Future<List<Map<String, dynamic>>> searchCountdowns(String query) async {
    final db = await instance.database;
    return await db.rawQuery('''
      SELECT * FROM countdowns 
      WHERE is_deleted = 0 
      AND (title LIKE ? OR team_name LIKE ?)
      ORDER BY updated_at DESC
      LIMIT 10
    ''', ['%$query%', '%$query%']);
  }

  Future<List<Map<String, dynamic>>> searchTimeLogs(String query) async {
    final db = await instance.database;
    return await db.rawQuery('''
      SELECT * FROM time_logs 
      WHERE is_deleted = 0 
      AND (title LIKE ? OR remark LIKE ?)
      ORDER BY start_time DESC
      LIMIT 15
    ''', ['%$query%', '%$query%']);
  }

  Future close() async {
    final db = await instance.database;
    db.close();
  }

  // 🚀 Uni-Sync 4.0: 获取所有待办事项（用于缓存重载）
  Future<List<TodoItem>> getTodos() async {
    final db = await instance.database;
    final List<Map<String, dynamic>> maps = await db.query('todos');
    return List.generate(maps.length, (i) => TodoItem.fromSql(maps[i]));
  }

  // 🚀 Uni-Sync 4.0: 获取所有待办组
  Future<List<TodoGroup>> getTodoGroups() async {
    final db = await instance.database;
    final List<Map<String, dynamic>> maps = await db.query('todo_groups');
    return List.generate(maps.length, (i) => TodoGroup.fromSql(maps[i]));
  }

  // 🚀 Uni-Sync 4.0: 获取所有倒计时
  Future<List<CountdownItem>> getCountdowns() async {
    final db = await instance.database;
    final List<Map<String, dynamic>> maps = await db.query('countdowns');
    return List.generate(maps.length, (i) => CountdownItem.fromSql(maps[i]));
  }

  // --- 搜索历史管理 ---

  Future<void> insertSearchHistory(String query) async {
    final db = await database;
    final hour = DateTime.now().hour;
    String column = 'morning_count';
    if (hour >= 12 && hour < 18) column = 'afternoon_count';
    else if (hour >= 18 && hour < 24) column = 'evening_count';
    else if (hour >= 0 && hour < 6) column = 'night_count';

    await db.rawInsert('''
      INSERT INTO search_history (query, timestamp, frequency, $column)
      VALUES (?, ?, 1, 1)
      ON CONFLICT(query) DO UPDATE SET
        frequency = frequency + 1,
        timestamp = ?,
        $column = $column + 1
    ''', [query, DateTime.now().millisecondsSinceEpoch, DateTime.now().millisecondsSinceEpoch]);
  }

  Future<List<Map<String, dynamic>>> getRecentSearches({int limit = 10, int? currentHour}) async {
    final db = await database;
    final hour = currentHour ?? DateTime.now().hour;
    
    String timeWeightCol = 'morning_count';
    if (hour >= 12 && hour < 18) timeWeightCol = 'afternoon_count';
    else if (hour >= 18 && hour < 24) timeWeightCol = 'evening_count';
    else if (hour >= 0 && hour < 6) timeWeightCol = 'night_count';

    return await db.query(
      'search_history',
      orderBy: '$timeWeightCol DESC, frequency DESC, timestamp DESC',
      limit: limit,
    );
  }
}