import 'dart:async';
import 'dart:convert';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
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
    final path = join(dbPath, filePath);

    return await openDatabase(
      path,
      version: 2, // 🚀 升级版本
      onCreate: _createDB,
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          // 🚀 Uni-Sync 安全升级：手动增加缺失字段，不破坏现有数据
          try {
            await db.execute("ALTER TABLE todos ADD COLUMN team_uuid TEXT;");
            await db.execute("ALTER TABLE todos ADD COLUMN team_name TEXT;");
          } catch (_) { /* 忽略重复添加错误 */ }
          
          await db.execute('DROP TABLE IF EXISTS todos_fts');
          await _createDB(db, newVersion); // 重新创建触发器和虚表
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
          'created_at': json['created_at'] ?? json['created_date'] ?? DateTime.now().millisecondsSinceEpoch
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
        content $textType,
        remark $jsonType,
        team_name $jsonType, 
        is_completed $boolType DEFAULT 0,
        is_deleted $boolType DEFAULT 0,
        version $integerType DEFAULT 1,
        due_date $jsonType,
        created_at $integerType,
        updated_at $integerType
      )
    ''');

    // 2. 倒数日表
    await db.execute('''
      CREATE TABLE IF NOT EXISTS countdowns (
        id $idType,
        uuid $textType UNIQUE,
        team_uuid $jsonType,
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

    // 5. 🚀 Uni-Sync 核心：FTS5 全文搜索虚表
    await db.execute('''
      CREATE VIRTUAL TABLE IF NOT EXISTS todos_fts USING fts5(
        uuid UNINDEXED,
        content,
        remark,
        team_name, 
        tokenize='unicode61' 
      )
    ''');

    // 4. 触发器：自动同步 FTS 索引 (保持搜索实时性)
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
    // 使用 FTS5 进行高效 MATCH 搜索
    return await db.rawQuery('''
      SELECT t.* FROM todos t
      JOIN todos_fts f ON t.uuid = f.uuid
      WHERE todos_fts MATCH ?
      ORDER BY rank
    ''', [query]);
  }

  Future close() async {
    final db = await instance.database;
    db.close();
  }
}
