import 'dart:async';
import 'dart:convert';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'environment_service.dart';
import 'package:flutter/foundation.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('uni_sync.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    // 🚀 根据环境动态选择数据库文件名（隔离测试数据）
    final targetName = EnvironmentService.dbName;
    final path = join(dbPath, targetName);

    return await openDatabase(
      path,
      version: 8, // 🚀 升级版本至 8，补全循环任务与提醒字段
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
      }
    );
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
          'due_date': json['due_date'] ?? json['dueDate'],
          // 🚀 补全协作元数据
          'team_uuid': json['team_uuid'] ?? json['teamUuid'],
          'creator_id': json['creator_id'] ?? json['creatorId'],
          'creator_name': json['creator_name'] ?? json['creatorName'],
          'team_name': json['team_name'] ?? json['teamName'],
          'group_id': json['group_id'] ?? json['groupId'],
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
        custom_interval_days $integerType,
        recurrence_end_date $integerType,
        reminder_minutes $integerType
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
        version $integerType DEFAULT 1,
        created_at $integerType,
        updated_at $integerType
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
        updated_at $integerType
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

    // 🚀 Uni-Sync 核心：初始化 FTS 搜索引擎 (带嗅探)
    await _setupFts(db);
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
        await _createFtsTriggers(db);
        debugPrint("✅ Database: FTS5 搜索引擎就绪");
        return;
      } catch (_) {}
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
        await _createFtsTriggers(db);
        debugPrint("✅ Database: FTS4 搜索引擎就绪");
        return;
      } catch (_) {}
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

  Future<List<Map<String, dynamic>>> searchTodos(String query) async {
    final db = await instance.database;
    
    // 1. 动态探测 FTS 虚表是否存在
    final tables = await db.rawQuery("SELECT name FROM sqlite_master WHERE type='table' AND name='todos_fts'");
    
    if (tables.isNotEmpty) {
      try {
        // 🚀 深度防御：先尝试执行一个极简的 MATCH 探测虚表是否真的可用
        // 防止那种“表名存在但在 module 缺失环境下无法加载”的僵尸表情况
        await db.rawQuery("SELECT 1 FROM todos_fts WHERE todos_fts MATCH 'test' LIMIT 0");

        // 2. 优先尝试 FTS 搜索 (FTS5 支持 rank，FTS4 仅支持 content 检索)
        // 注意：FTS4 没有内建 rank 字段，这里我们做一个简单的兼容处理
        final hasRank = (await db.rawQuery("PRAGMA table_info(todos_fts)")).any((col) => col['name'] == 'rank');

        return await db.rawQuery('''
          SELECT t.* FROM todos t
          JOIN todos_fts f ON t.uuid = f.uuid
          WHERE todos_fts MATCH ?
          ${hasRank ? 'ORDER BY rank' : ''}
        ''', [query]);
      } catch (e) {
        debugPrint("⚠️ FTS 查询异常，退化为 LIKE 模式: $e");
      }
    }
    
    // 3. 兜底方案：使用标准 SQL LIKE 模糊查询
    return await db.rawQuery('''
      SELECT * FROM todos 
      WHERE is_deleted = 0 
      AND (content LIKE ? OR remark LIKE ?)
      ORDER BY updated_at DESC
    ''', ['%$query%', '%$query%']);
  }

  Future close() async {
    final db = await instance.database;
    db.close();
  }
}
