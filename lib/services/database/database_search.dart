part of '../database_helper.dart';

mixin _DatabaseHelperSearchMixin on _DatabaseHelperBase {
  /// 🚀 初始化 FTS 搜索引擎，支持 FTS5 -> FTS4 -> LIKE 逐级降级 (带主动探测)
  @override
  Future<void> _setupFts(Database db) async {
    // 0. 清理阶段：强制移除所有虚表和触发器，确保状态干净
    final cleanups = [
      'DROP TRIGGER IF EXISTS todos_after_insert',
      'DROP TRIGGER IF EXISTS todos_after_update',
      'DROP TRIGGER IF EXISTS todos_after_delete',
      'DROP TRIGGER IF EXISTS todos_after_soft_delete',
      'DROP TRIGGER IF EXISTS todos_after_restore',
      'DROP TRIGGER IF EXISTS todos_after_searchable_update',
      'DROP TABLE IF EXISTS todos_fts',
    ];
    for (var sql in cleanups) {
      try {
        await db.execute(sql);
      } catch (_) {}
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
        //         debugPrint("✅ Database: FTS5 搜索引擎就绪并已同步存量数据");
        return;
      } catch (e) {
        //         debugPrint("⚠️ Database: FTS5 初始化失败: $e");
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
        //         debugPrint("✅ Database: FTS4 搜索引擎就绪并已同步存量数据");
        return;
      } catch (e) {
        //         debugPrint("⚠️ Database: FTS4 初始化失败: $e");
      }
    }

    //     debugPrint("❌ Database: 硬件/系统不支持 FTS 索引，已切换至 LIKE 模式");
  }

  /// 🚀 创建 FTS 实时同步触发器
  Future<void> _createFtsTriggers(Database db) async {
    await db.execute('''
      CREATE TRIGGER IF NOT EXISTS todos_after_insert
      AFTER INSERT ON todos WHEN new.is_deleted = 0 BEGIN
        INSERT INTO todos_fts(uuid, content, remark, team_name) VALUES (new.uuid, new.content, new.remark, new.team_name);
      END;
    ''');

    await db.execute('''
      CREATE TRIGGER IF NOT EXISTS todos_after_soft_delete
      AFTER UPDATE OF is_deleted ON todos WHEN new.is_deleted != 0 BEGIN
        DELETE FROM todos_fts WHERE uuid = old.uuid;
      END;
    ''');

    await db.execute('''
      CREATE TRIGGER IF NOT EXISTS todos_after_restore
      AFTER UPDATE OF is_deleted ON todos
      WHEN old.is_deleted != 0 AND new.is_deleted = 0 BEGIN
        DELETE FROM todos_fts WHERE uuid = new.uuid;
        INSERT INTO todos_fts(uuid, content, remark, team_name) VALUES (new.uuid, new.content, new.remark, new.team_name);
      END;
    ''');

    await db.execute('''
      CREATE TRIGGER IF NOT EXISTS todos_after_searchable_update
      AFTER UPDATE OF content, remark, team_name ON todos
      WHEN new.is_deleted = 0 BEGIN
        UPDATE todos_fts SET content = new.content, remark = new.remark, team_name = new.team_name WHERE uuid = old.uuid;
      END;
    ''');

    await db.execute('''
      CREATE TRIGGER IF NOT EXISTS todos_after_delete AFTER DELETE ON todos BEGIN
        DELETE FROM todos_fts WHERE uuid = old.uuid;
      END;
    ''');
  }

  Future<List<Map<String, dynamic>>> searchTodos(String query) async {
    final db = await DatabaseHelper.instance.database;
    final Map<String, int> resultScores = {};

    // 1. 尝试 FTS 搜索引擎 (高性能前缀匹配)
    if (await _canUseTodoFts(db)) {
      try {
        final ftsQuery = query
            .split(' ')
            .where((s) => s.isNotEmpty)
            .map((s) => '$s*')
            .join(' ');
        final ftsResults = await db.rawQuery(
          '''
          SELECT t.uuid, t.updated_at FROM todos t
          JOIN todos_fts f ON t.uuid = f.uuid
          WHERE todos_fts MATCH ?
          AND t.is_deleted = 0
        ''',
          [ftsQuery],
        );

        for (var r in ftsResults) {
          resultScores[r['uuid'].toString()] = (r['updated_at'] as int?) ?? 0;
        }
      } catch (e) {
        //         debugPrint("FTS error: $e");
      }
    }

    // 2. LIKE 补全中间词和团队名，不能因为 FTS 已命中部分记录
    // 就跳过其余匹配项。
    final likeResults = await db.rawQuery(
      '''
        SELECT uuid, updated_at FROM todos 
        WHERE is_deleted = 0 
        AND (content LIKE ? OR remark LIKE ? OR team_name LIKE ?)
        ORDER BY updated_at DESC
      ''',
      ['%$query%', '%$query%', '%$query%'],
    );

    for (var r in likeResults) {
      resultScores[r['uuid'].toString()] = (r['updated_at'] as int?) ?? 0;
    }

    if (resultScores.isEmpty) return [];

    final finalResults = await _getSearchTodoMaps(
      db,
      resultScores.keys.toList(),
    );
    // 按更新时间降序排序
    finalResults.sort(
      (a, b) => (resultScores[b['uuid'].toString()] ?? 0).compareTo(
        resultScores[a['uuid'].toString()] ?? 0,
      ),
    );
    return finalResults;
  }

  Future<List<Map<String, dynamic>>> searchTodosByTerms(
    List<String> terms,
  ) async {
    final uniqueTerms = <String>[];
    final seenTerms = <String>{};
    for (final term in terms) {
      if (seenTerms.add(term)) uniqueTerms.add(term);
    }
    if (uniqueTerms.isEmpty) return [];

    final db = await DatabaseHelper.instance.database;
    final useFts = await _canUseTodoFts(db);
    const termsPerBatch = 300;
    final rowsByUuid = <String, Map<String, dynamic>>{};

    try {
      for (
        var offset = 0;
        offset < uniqueTerms.length;
        offset += termsPerBatch
      ) {
        final nextOffset = offset + termsPerBatch;
        final end = nextOffset < uniqueTerms.length
            ? nextOffset
            : uniqueTerms.length;
        final chunk = uniqueTerms.sublist(offset, end);
        final termRows = List.filled(chunk.length, '(?)').join(', ');
        final ctes = <String>['search_terms(term) AS (VALUES $termRows)'];
        final queryArgs = <Object?>[...chunk];
        var ftsCondition = '';
        if (useFts) {
          final ftsQueries = chunk
              .map(
                (term) => term
                    .split(' ')
                    .where((part) => part.isNotEmpty)
                    .map((part) => '$part*')
                    .join(' '),
              )
              .where((query) => query.isNotEmpty)
              .toList(growable: false);
          if (ftsQueries.isNotEmpty) {
            final ftsBranches = List.filled(
              ftsQueries.length,
              'SELECT uuid FROM todos_fts WHERE todos_fts MATCH ?',
            ).join(' UNION ALL ');
            ctes.add('fts_matches(uuid) AS ($ftsBranches)');
            queryArgs.addAll(ftsQueries);
            ftsCondition = ' OR t.uuid IN (SELECT uuid FROM fts_matches)';
          }
        }

        final rows = await db.rawQuery('''
          WITH ${ctes.join(', ')}
          SELECT t.*
          FROM todos AS t
          WHERE t.is_deleted = 0
            AND (
              EXISTS (
                SELECT 1
                FROM search_terms AS s
                WHERE t.content LIKE '%' || s.term || '%'
                  OR t.remark LIKE '%' || s.term || '%'
                  OR t.team_name LIKE '%' || s.term || '%'
              )$ftsCondition
            )
          ORDER BY t.updated_at DESC
          ''', queryArgs);
        for (final row in rows) {
          rowsByUuid[row['uuid'].toString()] = row;
        }
      }
      final results = rowsByUuid.values.toList(growable: false);
      if (uniqueTerms.length > termsPerBatch) {
        results.sort(
          (a, b) => ((b['updated_at'] as int?) ?? 0).compareTo(
            (a['updated_at'] as int?) ?? 0,
          ),
        );
      }
      return results;
    } catch (_) {
      // A batched FTS statement can reject an individual user term. Retain the
      // per-term parser fallback used by searchTodos for those queries.
      final fallbackRowsByUuid = <String, Map<String, dynamic>>{};
      for (final term in uniqueTerms) {
        for (final row in await searchTodos(term)) {
          fallbackRowsByUuid[row['uuid'].toString()] = row;
        }
      }
      return fallbackRowsByUuid.values.toList(growable: false);
    }
  }

  Future<void> warmSearchIndex() async {
    final db = await DatabaseHelper.instance.database;
    await _canUseTodoFts(db);
  }

  Future<bool> _canUseTodoFts(Database db) async {
    if (!identical(_todoFtsDatabase, db)) {
      _todoFtsDatabase = db;
      _todoFtsAvailable = null;
      _todoFtsAvailabilityFuture = null;
    }
    final cached = _todoFtsAvailable;
    if (cached != null) return cached;

    return _todoFtsAvailabilityFuture ??= _probeTodoFts(db);
  }

  Future<bool> _probeTodoFts(Database db) async {
    var available = false;
    try {
      final tables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='todos_fts'",
      );
      if (tables.isEmpty) {
        return _cacheTodoFtsAvailability(db, available);
      }
      final ftsCount =
          Sqflite.firstIntValue(
            await db.rawQuery("SELECT COUNT(*) FROM todos_fts"),
          ) ??
          0;
      final actualCount =
          Sqflite.firstIntValue(
            await db.rawQuery(
              "SELECT COUNT(*) FROM todos WHERE is_deleted = 0",
            ),
          ) ??
          0;
      if (ftsCount == 0 && actualCount > 0) {
        await db.execute(
          "INSERT INTO todos_fts(uuid, content, remark, team_name) SELECT uuid, content, remark, team_name FROM todos WHERE is_deleted = 0",
        );
      }
      available = true;
    } catch (_) {}
    return _cacheTodoFtsAvailability(db, available);
  }

  bool _cacheTodoFtsAvailability(Database db, bool available) {
    if (identical(_todoFtsDatabase, db)) {
      _todoFtsAvailable = available;
    }
    return available;
  }

  Future<List<Map<String, dynamic>>> searchTodosByDate(
    int startInclusive,
    int endExclusive,
  ) async {
    final db = await DatabaseHelper.instance.database;
    final ids = await db.rawQuery(
      '''
      SELECT uuid, updated_at
      FROM todos
      WHERE is_deleted = 0
        AND (
          (due_date >= ? AND due_date < ?)
          OR
          (created_date >= ? AND created_date < ?)
        )
      ORDER BY updated_at DESC
    ''',
      [startInclusive, endExclusive, startInclusive, endExclusive],
    );
    if (ids.isEmpty) return const [];

    final scoreById = <String, int>{
      for (final row in ids)
        row['uuid'].toString(): (row['updated_at'] as num?)?.toInt() ?? 0,
    };
    final rows = await _getSearchTodoMaps(db, scoreById.keys.toList());
    rows.sort(
      (a, b) => (scoreById[b['uuid'].toString()] ?? 0).compareTo(
        scoreById[a['uuid'].toString()] ?? 0,
      ),
    );
    return rows;
  }

  Future<List<Map<String, dynamic>>> _getSearchTodoMaps(
    Database db,
    List<String> uuids,
  ) async {
    const batchSize = 400;
    final rows = <Map<String, dynamic>>[];
    for (var start = 0; start < uuids.length; start += batchSize) {
      rows.addAll(
        await getTodoMaps(
          includeDeleted: true,
          uuids: uuids.sublist(
            start,
            start + batchSize > uuids.length ? uuids.length : start + batchSize,
          ),
          databaseOverride: db,
        ),
      );
    }
    return rows;
  }

  Future<int> countOverdueTodos(
    int beforeExclusive, {
    Set<String> excludedRecurrenceSeriesIds = const <String>{},
  }) async {
    final db = await DatabaseHelper.instance.database;
    final excludedSeriesIds = excludedRecurrenceSeriesIds
        .where((seriesId) => seriesId.isNotEmpty)
        .toList(growable: false);
    final excludedSeriesClause = excludedSeriesIds.isEmpty
        ? ''
        : 'AND (recurrence_series_id IS NULL OR recurrence_series_id NOT IN '
              '(${List.filled(excludedSeriesIds.length, '?').join(', ')}))';
    return Sqflite.firstIntValue(
          await db.rawQuery(
            '''
      SELECT COUNT(*)
      FROM todos
      WHERE is_deleted = 0
        AND is_completed = 0
        AND due_date IS NOT NULL
        AND due_date != 0
        AND due_date < ?
        $excludedSeriesClause
    ''',
            [beforeExclusive, ...excludedSeriesIds],
          ),
        ) ??
        0;
  }

  Future<List<Map<String, dynamic>>> searchTodoGroupsByTerms(
    List<String> terms,
  ) => _searchRowsByTerms(
    table: 'todo_groups',
    matchColumns: const ['name'],
    orderColumn: 'updated_at',
    terms: terms,
  );

  Future<List<Map<String, dynamic>>> searchCoursesByTerms(List<String> terms) =>
      _searchRowsByTerms(
        table: 'courses',
        matchColumns: const ['course_name', 'teacher_name', 'room_name'],
        orderColumn: 'updated_at',
        terms: terms,
      );

  Future<List<Map<String, dynamic>>> searchCountdownsByTerms(
    List<String> terms,
  ) => _searchRowsByTerms(
    table: 'countdowns',
    matchColumns: const ['title', 'team_name'],
    orderColumn: 'updated_at',
    terms: terms,
  );

  Future<List<Map<String, dynamic>>> searchTimeLogsByTerms(
    List<String> terms,
  ) => _searchRowsByTerms(
    table: 'time_logs',
    matchColumns: const ['title', 'remark'],
    orderColumn: 'start_time',
    terms: terms,
  );

  Future<List<Map<String, dynamic>>> _searchRowsByTerms({
    required String table,
    required List<String> matchColumns,
    required String orderColumn,
    required List<String> terms,
  }) async {
    final uniqueTerms = <String>[];
    final seenTerms = <String>{};
    for (final term in terms) {
      if (seenTerms.add(term)) uniqueTerms.add(term);
    }
    if (uniqueTerms.isEmpty) return [];

    final db = await DatabaseHelper.instance.database;
    const chunkSize = 900;
    final rowsByUuid = <String, Map<String, dynamic>>{};
    final matchExpression = matchColumns
        .map((column) => "t.$column LIKE '%' || s.term || '%'")
        .join(' OR ');

    for (var offset = 0; offset < uniqueTerms.length; offset += chunkSize) {
      final end = offset + chunkSize < uniqueTerms.length
          ? offset + chunkSize
          : uniqueTerms.length;
      final chunk = uniqueTerms.sublist(offset, end);
      final termRows = List.generate(
        chunk.length,
        (index) => '(?, $index)',
      ).join(', ');
      final rows = await db.rawQuery('''
        WITH search_terms(term, term_order) AS (VALUES $termRows)
        SELECT t.*
        FROM $table AS t
        JOIN search_terms AS s ON ($matchExpression)
        WHERE t.is_deleted = 0
        GROUP BY t.uuid
        ORDER BY MIN(s.term_order), t.$orderColumn DESC
        ''', chunk);
      for (final row in rows) {
        rowsByUuid[row['uuid'].toString()] = row;
      }
    }

    return rowsByUuid.values.toList(growable: false);
  }

  Future<List<Map<String, dynamic>>> searchTodoGroups(String query) async {
    final db = await DatabaseHelper.instance.database;
    return await db.rawQuery(
      '''
      SELECT * FROM todo_groups 
      WHERE is_deleted = 0 
      AND name LIKE ?
      ORDER BY updated_at DESC
    ''',
      ['%$query%'],
    );
  }

  Future<List<Map<String, dynamic>>> searchCourses(String query) async {
    final db = await DatabaseHelper.instance.database;
    return await db.rawQuery(
      '''
      SELECT * FROM courses 
      WHERE is_deleted = 0 
      AND (course_name LIKE ? OR teacher_name LIKE ? OR room_name LIKE ?)
      ORDER BY updated_at DESC
    ''',
      ['%$query%', '%$query%', '%$query%'],
    );
  }

  Future<List<Map<String, dynamic>>> searchCountdowns(String query) async {
    final db = await DatabaseHelper.instance.database;
    return await db.rawQuery(
      '''
      SELECT * FROM countdowns 
      WHERE is_deleted = 0 
      AND (title LIKE ? OR team_name LIKE ?)
      ORDER BY updated_at DESC
    ''',
      ['%$query%', '%$query%'],
    );
  }

  Future<List<Map<String, dynamic>>> searchTimeLogs(String query) async {
    final db = await DatabaseHelper.instance.database;
    return await db.rawQuery(
      '''
      SELECT * FROM time_logs 
      WHERE is_deleted = 0 
      AND (title LIKE ? OR remark LIKE ?)
      ORDER BY start_time DESC
    ''',
      ['%$query%', '%$query%'],
    );
  }

  Future<List<Map<String, dynamic>>> searchTimeLogsByDate(
    int startInclusive,
    int endExclusive,
  ) async {
    final db = await DatabaseHelper.instance.database;
    return db.rawQuery(
      '''
      SELECT * FROM time_logs
      WHERE is_deleted = 0
        AND start_time >= ?
        AND start_time < ?
      ORDER BY start_time DESC
    ''',
      [startInclusive, endExclusive],
    );
  }
}
