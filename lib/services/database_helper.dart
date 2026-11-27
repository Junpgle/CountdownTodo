import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import 'environment_service.dart';

import 'package:flutter/foundation.dart';

import '../models.dart';
import '../utils/app_platform.dart';
import '../utils/json_value_parser.dart';
import 'database_path_resolver.dart';
import 'database_schema_history.dart';

part 'database/database_schema.dart';
part 'database/database_init_and_migrations.dart';
part 'database/database_search.dart';
part 'database/database_queries.dart';

enum TodoMapsOrdering { updatedAtDescending, fixedScheduleRelations }

abstract class _DatabaseHelperBase {
  final Set<String> _verifiedSchemaPaths = <String>{};
  bool? _todoFtsAvailable;
  Database? _todoFtsDatabase;
  Future<bool>? _todoFtsAvailabilityFuture;

  Future<Database> get database;
  Future<Database> databaseForUser(String username);
  Future<void> closeDatabase();
  Future<void> _setupFts(Database db);
  Future<List<Map<String, dynamic>>> getTodoMaps({
    bool includeDeleted = false,
    bool deletedOnly = false,
    String? where,
    List<Object?>? whereArgs,
    List<String>? uuids,
    Set<String>? recurrenceSeriesIds,
    int? limit,
    int offset = 0,
    TodoMapsOrdering ordering = TodoMapsOrdering.updatedAtDescending,
    bool inlineTextColumns = false,
    bool includeConflictData = false,
    DatabaseExecutor? databaseOverride,
  });
}

class DatabaseHelper extends _DatabaseHelperBase
    with
        _DatabaseHelperInitMixin,
        _DatabaseHelperSearchMixin,
        _DatabaseHelperQueriesMixin {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;
  static Future<Database>? _openingDatabase;
  static String? _activeUsername;
  static int _openGeneration = 0;

  DatabaseHelper._init();

  @visibleForTesting
  static String databaseFileNameFor(String username) =>
      _databaseFileNameFor(username);

  static String _databaseFileNameFor(String username) {
    final envPrefix = EnvironmentService.isTest ? 'test_v5_' : 'v4_';
    return '${envPrefix}uni_sync_$username.db';
  }

  /// Checks whether [dbPath] points to the exact database file for [username].
  ///
  /// Matching the exact basename instead of `path.contains('uni_sync_$username')`
  /// prevents prefix collisions such as `alice` matching `alice_work`.
  @visibleForTesting
  static bool matchesDatabaseFileForUser(String dbPath, String username) {
    final expectedFileName = _databaseFileNameFor(username);
    final normalizedPath = dbPath.replaceAll('\\', '/');
    final separatorIndex = normalizedPath.lastIndexOf('/');
    final baseName = separatorIndex == -1
        ? normalizedPath
        : normalizedPath.substring(separatorIndex + 1);
    return baseName == expectedFileName;
  }

  Future<Database> _openOrReuseDatabaseFor(String username) async {
    final existingDb = _database;
    if (existingDb != null) {
      // 🚀 核心校验：如果当前打开的数据库与当前登录用户不符，则强制关闭并重新打开
      if (_activeUsername != username ||
          !matchesDatabaseFileForUser(existingDb.path, username)) {
        await closeDatabase();
      } else {
        return existingDb;
      }
    }

    if (_openingDatabase != null) {
      final opening = _openingDatabase!;
      final opened = await opening;
      if (_activeUsername == username &&
          matchesDatabaseFileForUser(opened.path, username)) {
        _database = opened;
        return opened;
      }
      await closeDatabase();
    }

    _activeUsername = username;
    final myGen = _openGeneration;
    final opening = _initDB('uni_sync_$username.db');
    _openingDatabase = opening;
    try {
      final openedDb = await opening;
      if (_openGeneration != myGen || _activeUsername != username) {
        _verifiedSchemaPaths.remove(openedDb.path);
        try {
          await openedDb.close();
        } catch (_) {}
        throw StateError('数据库在打开期间被关闭或切换账户: $username');
      }
      _database = openedDb;
    } finally {
      if (identical(_openingDatabase, opening)) {
        _openingDatabase = null;
      }
    }
    return _database!;
  }

  @override
  Future<Database> get database async {
    final prefs = await SharedPreferences.getInstance();
    final rawUsername = prefs.getString('current_login_user');
    final username = (rawUsername != null && rawUsername.isNotEmpty)
        ? rawUsername
        : 'default';
    return _openOrReuseDatabaseFor(username);
  }

  /// Returns the database for the active account and rejects stale callers.
  ///
  /// The database file is selected from `current_login_user`, while most
  /// storage APIs also receive a username argument.  Keeping the check here
  /// prevents an async operation that started for one account from silently
  /// reading or writing the database opened for another account.
  @override
  Future<Database> databaseForUser(String username) async {
    if (username.isEmpty) {
      throw ArgumentError.value(username, 'username', '账户名不能为空');
    }
    final prefs = await SharedPreferences.getInstance();
    final activeUsername = prefs.getString('current_login_user');
    final hasActiveUsername =
        activeUsername != null && activeUsername.isNotEmpty;
    if (hasActiveUsername && activeUsername != username) {
      throw StateError(
        '账户已切换，拒绝使用旧账户数据: expected=$activeUsername, requested=$username',
      );
    }

    final existingDb = _database;
    if (existingDb != null &&
        _openingDatabase == null &&
        _activeUsername == username &&
        matchesDatabaseFileForUser(existingDb.path, username)) {
      return existingDb;
    }

    final targetUsername = hasActiveUsername ? activeUsername : 'default';
    final db = await _openOrReuseDatabaseFor(targetUsername);
    final latestActiveUsername = prefs.getString('current_login_user');
    final latestHasActiveUsername =
        latestActiveUsername != null && latestActiveUsername.isNotEmpty;
    if (latestHasActiveUsername && latestActiveUsername != username) {
      throw StateError(
        '账户已切换，拒绝使用旧账户数据: expected=$latestActiveUsername, requested=$username',
      );
    }
    if ((hasActiveUsername || latestHasActiveUsername) &&
        _activeUsername != username) {
      throw StateError(
        '账户数据库已切换，拒绝使用旧账户数据: active=$_activeUsername, requested=$username',
      );
    }
    return db;
  }

  /// 🚀 Uni-Sync: 强制关闭并重置数据库连接（用于登出或切换用户）
  @override
  Future<void> closeDatabase() async {
    _openGeneration++;
    _verifiedSchemaPaths.clear();
    final opening = _openingDatabase;
    _openingDatabase = null;
    if (opening != null) {
      try {
        final openedDb = await opening;
        if (!identical(openedDb, _database)) {
          await openedDb.close();
        }
      } catch (_) {}
    }
    final currentDb = _database;
    _database = null;
    if (currentDb != null) {
      await currentDb.close();
    }
    _activeUsername = null;
    _todoFtsAvailable = null;
    _todoFtsDatabase = null;
    _todoFtsAvailabilityFuture = null;
  }

  static Future<void> ensureCourseTableSchema(Database db) =>
      _ensureCourseTableSchema(db);
  static Future<void> ensureTodoClientLocalSchema(Database db) =>
      _ensureTodoClientLocalSchema(db);
  static Future<void> ensureTodoSkipStateSchema(Database db) =>
      _ensureTodoSkipStateSchema(db);
  static Future<void> ensureTodoCompletionTimestampSchema(Database db) =>
      _ensureTodoCompletionTimestampSchema(db);
  static Future<void> ensureTodoPlanBlockSchema(Database db) =>
      _ensureTodoPlanBlockSchema(db);
  static Future<void> ensureFixedScheduleSchema(Database db) =>
      _ensureFixedScheduleSchema(db);
  static Future<void> ensureHabitSchema(Database db) => _ensureHabitSchema(db);
  static Future<void> ensureSuggestionFeedbackSchema(Database db) =>
      _ensureSuggestionFeedbackSchema(db);
  static Future<void> ensurePlanEditorDraftSchema(Database db) =>
      _ensurePlanEditorDraftSchema(db);
  static Future<void> ensureJournalSchema(Database db) =>
      _ensureJournalSchema(db);
  static Future<void> ensureFinanceSchema(Database db) =>
      _ensureFinanceSchema(db);
  static Future<void> ensureAiUsageSchema(Database db) =>
      _ensureAiUsageSchema(db);
  static Future<void> ensureTeamsSchema(Database db) => _ensureTeamsSchema(db);
  static Future<void> ensureScreenTimeSchema(Database db) =>
      _ensureScreenTimeSchema(db);
  static Future<void> ensureMissingIndexes(Database db) =>
      _ensureMissingIndexes(db);
}
