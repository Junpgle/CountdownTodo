part of '../database_helper.dart';

const int _todoTextChunkSize = 8192;
const List<String> _todoBaseColumns = [
  'uuid',
  'team_uuid',
  'group_id',
  'team_name',
  'creator_id',
  'creator_name',
  'is_completed',
  'completed_at',
  'is_skipped',
  'is_skipped_sync_pending',
  'is_deleted',
  'version',
  'due_date',
  'created_date',
  'created_at',
  'updated_at',
  'collab_type',
  'recurrence',
  'recurrence_series_id',
  'custom_interval_days',
  'recurrence_end_date',
  'reminder_minutes',
  'has_conflict',
  'is_all_day',
  'image_path',
  'original_text',
];

mixin _DatabaseHelperQueriesMixin on _DatabaseHelperBase {
  // --- 通用操作接口 ---

  Future<int> insertOpLog(
    String opType,
    String table,
    String uuid,
    Map<String, dynamic> data,
  ) async {
    final db = await DatabaseHelper.instance.database;
    return await db.insert('op_logs', {
      'op_type': opType,
      'target_table': table,
      'target_uuid': uuid,
      'data_json': jsonEncode(data),
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'is_synced': 0,
      'sync_error': '',
    });
  }

  Future<Map<String, dynamic>?> getTodoByUuid(String uuid) async {
    final results = await getTodoMaps(
      includeDeleted: true,
      uuids: [uuid],
      limit: 1,
    );
    return results.isNotEmpty ? results.first : null;
  }

  // ==========================================
  // 🧹 数据库清理与去重
  // ==========================================

  /// 清理重复课程：基于名称、时间、地点去重，保留最新的一条，其余标记为删除（支持同步）
  Future<int> deduplicateCourses() async {
    final db = await database;
    try {
      // 1. 查找所有存在重复的课程组
      final List<Map<String, dynamic>> results = await db.rawQuery('''
        SELECT course_name, weekday, start_time, week_index, room_name, COUNT(*) as cnt
        FROM courses 
        WHERE is_deleted = 0
        GROUP BY course_name, weekday, start_time, week_index, room_name
        HAVING cnt > 1
      ''');

      int totalRemoved = 0;
      final now = DateTime.now().millisecondsSinceEpoch;

      for (var group in results) {
        final String name = group['course_name'] ?? '';
        final int weekday = group['weekday'] ?? 0;
        final int start = group['start_time'] ?? 0;
        final int week = group['week_index'] ?? 0;
        final String room = group['room_name'] ?? '';

        // 2. 获取该组内所有有效记录，按更新时间排序
        final List<Map<String, dynamic>> records = await db.query(
          'courses',
          where: 'course_name = ? AND weekday = ? AND start_time = ? AND week_index = ? AND room_name = ? AND is_deleted = 0',
          whereArgs: [name, weekday, start, week, room],
          orderBy: 'updated_at DESC',
        );

        if (records.length > 1) {
          // 3. 保留第1条（最新的），其余标记删除
          for (int i = 1; i < records.length; i++) {
            final String uuid = records[i]['uuid'];
            final newVersion = (records[i]['version'] as int? ?? 1) + 1;

            await db.update(
              'courses',
              {'is_deleted': 1, 'updated_at': now, 'version': newVersion},
              where: 'uuid = ?',
              whereArgs: [uuid],
            );

            // 4. 写入操作日志以同步到其他设备
            await db.insert('op_logs', {
              'op_type': 'UPDATE',
              'target_table': 'courses',
              'target_uuid': uuid,
              'data_json': jsonEncode({
                'uuid': uuid,
                'is_deleted': 1,
                'updated_at': now,
                'version': newVersion,
              }),
              'timestamp': now,
              'is_synced': 0,
              'sync_error': '',
            });
            totalRemoved++;
          }
        }
      }
      return totalRemoved;
    } catch (e) {
      //       debugPrint("❌ deduplicateCourses error: $e");
      return 0;
    }
  }

  Future close() async {
    final db = await DatabaseHelper.instance.database;
    db.close();
  }

  @override
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
  }) async {
    // Callers that already captured a user-scoped database must keep using
    // that handle.  Re-opening the current database here creates a window in
    // which an account switch can make the read come from another user.
    final db = databaseOverride ?? await DatabaseHelper.instance.database;
    final prefs = await SharedPreferences.getInstance();
    final int userId = prefs.getInt('current_user_id') ?? 0;

    final whereParts = <String>[];
    final queryArgs = <Object?>[];

    if (whereArgs?.isNotEmpty ?? false) {
      if (where == null || where.isEmpty) {
        throw ArgumentError.value(
          whereArgs,
          'whereArgs',
          'requires a non-empty where clause',
        );
      }
      queryArgs.addAll(whereArgs!);
    }
    if (where != null && where.isNotEmpty) {
      whereParts.add(where);
    } else if (deletedOnly) {
      whereParts.add('t.is_deleted IS 1');
    } else if (!includeDeleted) {
      whereParts.add('t.is_deleted IS NOT 1');
    }
    if (uuids != null && uuids.isNotEmpty) {
      whereParts.add(
        't.uuid IN (${List.filled(uuids.length, '?').join(', ')})',
      );
      queryArgs.addAll(uuids);
    }
    if (recurrenceSeriesIds != null && recurrenceSeriesIds.isNotEmpty) {
      whereParts.add(
        't.recurrence_series_id IN '
        '(${List.filled(recurrenceSeriesIds.length, '?').join(', ')})',
      );
      queryArgs.addAll(recurrenceSeriesIds);
    }

    final List<String> projectedColumns = _todoBaseColumns.map((col) {
      if (col == 'is_completed') {
        return 'CASE WHEN t.collab_type = 1 AND c.is_completed IS NOT NULL THEN c.is_completed ELSE t.is_completed END AS is_completed';
      }
      if (col == 'is_skipped') {
        return 'CASE WHEN t.collab_type = 1 AND c.is_skipped IS NOT NULL THEN c.is_skipped ELSE t.is_skipped END AS is_skipped';
      }
      if (col == 'is_skipped_sync_pending') {
        return 'CASE WHEN t.collab_type = 1 AND c.is_skipped_sync_pending IS NOT NULL '
            'THEN c.is_skipped_sync_pending ELSE t.is_skipped_sync_pending '
            'END AS is_skipped_sync_pending';
      }
      return 't.$col AS $col';
    }).toList();

    final sql = StringBuffer()..write('SELECT ');
    if (inlineTextColumns) {
      sql
        ..write(projectedColumns.join(', '))
        ..write(', t.content AS content, t.remark AS remark');
      if (includeConflictData) {
        sql.write(', t.conflict_data AS conflict_data');
      }
    } else {
      sql
        ..write(projectedColumns.join(', '))
        // Most todo text is tiny. Returning those values with the primary
        // query avoids one query per populated text column and row. Oversized
        // values keep using the chunked fallback below so a legacy/invalid
        // record cannot create a large platform-channel allocation.
        ..write(
          ', CASE WHEN LENGTH(t.content) <= $_todoTextChunkSize THEN t.content END AS content',
        )
        ..write(
          ', CASE WHEN LENGTH(t.remark) <= $_todoTextChunkSize THEN t.remark END AS remark',
        )
        ..write(', LENGTH(t.content) AS _content_length')
        ..write(', LENGTH(t.remark) AS _remark_length');
      if (includeConflictData) {
        sql
          ..write(
            ', CASE WHEN LENGTH(t.conflict_data) <= $_todoTextChunkSize THEN t.conflict_data END AS conflict_data',
          )
          ..write(', LENGTH(t.conflict_data) AS _conflict_length');
      }
    }
    sql.write(
      ' FROM todos t LEFT JOIN todo_completions c ON t.uuid = c.todo_uuid AND c.user_id = $userId',
    );
    if (whereParts.isNotEmpty) {
      sql.write(' WHERE ${whereParts.join(' AND ')}');
    }
    switch (ordering) {
      case TodoMapsOrdering.updatedAtDescending:
        sql.write(' ORDER BY t.updated_at DESC');
        break;
      case TodoMapsOrdering.fixedScheduleRelations:
        sql.write(
          ' ORDER BY '
          'CASE WHEN '
          '(CASE WHEN t.collab_type = 1 AND c.is_completed IS NOT NULL '
          'THEN c.is_completed ELSE t.is_completed END) = 0 AND '
          '(CASE WHEN t.collab_type = 1 AND c.is_skipped IS NOT NULL '
          'THEN c.is_skipped ELSE t.is_skipped END) = 0 '
          'THEN 0 ELSE 1 END ASC, '
          'CASE WHEN due_date IS NULL OR CAST(due_date AS INTEGER) = 0 THEN 1 ELSE 0 END ASC, '
          'CAST(due_date AS INTEGER) ASC, '
          "CASE WHEN TRIM(COALESCE(t.content, '')) = '' "
          "THEN '未命名待办' ELSE LOWER(t.content) END ASC, t.uuid ASC",
        );
        break;
    }
    if (limit != null) {
      sql.write(' LIMIT $limit');
      if (offset > 0) sql.write(' OFFSET $offset');
    }

    final rows = await db.rawQuery(sql.toString(), queryArgs);
    if (inlineTextColumns) {
      return rows;
    }
    final hydratedRows = <Map<String, dynamic>>[];
    for (final resultRow in rows) {
      // sqflite returns unmodifiable row maps; hydration removes helper
      // columns from rows that do not need the chunked text fallback.
      final row = Map<String, dynamic>.from(resultRow);
      final contentLength = _toNullableInt(row['_content_length']) ?? 0;
      final remarkLength = _toNullableInt(row['_remark_length']) ?? 0;
      final conflictLength = includeConflictData
          ? (_toNullableInt(row['_conflict_length']) ?? 0)
          : 0;
      final hasOversizedText =
          contentLength > _todoTextChunkSize ||
          remarkLength > _todoTextChunkSize ||
          conflictLength > _todoTextChunkSize;
      if (hasOversizedText) {
        hydratedRows.add(
          await _hydrateTodoRow(
            db,
            row,
            includeConflictData: includeConflictData,
          ),
        );
        continue;
      }

      row
        ..remove('_content_length')
        ..remove('_remark_length');
      if (includeConflictData) row.remove('_conflict_length');
      hydratedRows.add(row);
    }
    return hydratedRows;
  }

  /// Returns the todo fields consumed by home-screen widgets without loading
  /// remarks, images, original analysis text, or conflict payloads.
  Future<List<Map<String, dynamic>>> getTodoWidgetMaps(String username) async {
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getInt('current_user_id') ?? 0;
    final db = await databaseForUser(username);
    final rows = await db.rawQuery('''
      SELECT
        t.uuid AS uuid,
        t.team_name AS team_name,
        CASE
          WHEN t.collab_type = 1 AND c.is_completed IS NOT NULL
          THEN c.is_completed
          ELSE t.is_completed
        END AS is_completed,
        CASE
          WHEN t.collab_type = 1 AND c.is_skipped IS NOT NULL
          THEN c.is_skipped
          ELSE t.is_skipped
        END AS is_skipped,
        CASE
          WHEN t.collab_type = 1 AND c.is_skipped_sync_pending IS NOT NULL
          THEN c.is_skipped_sync_pending
          ELSE t.is_skipped_sync_pending
        END AS is_skipped_sync_pending,
        t.is_deleted AS is_deleted,
        t.version AS version,
        t.due_date AS due_date,
        t.created_date AS created_date,
        t.created_at AS created_at,
        t.updated_at AS updated_at,
        t.completed_at AS completed_at,
        t.recurrence AS recurrence,
        t.recurrence_series_id AS recurrence_series_id,
        t.custom_interval_days AS custom_interval_days,
        t.recurrence_end_date AS recurrence_end_date,
        t.is_all_day AS is_all_day,
        CASE
          WHEN LENGTH(t.content) <= $_todoTextChunkSize THEN t.content
        END AS content,
        LENGTH(t.content) AS _content_length
      FROM todos t
      LEFT JOIN todo_completions c
        ON t.uuid = c.todo_uuid AND c.user_id = $userId
      WHERE t.is_deleted IS NOT 1
      ORDER BY t.updated_at DESC
    ''');

    final hydratedRows = <Map<String, dynamic>>[];
    for (final resultRow in rows) {
      final row = Map<String, dynamic>.from(resultRow);
      final contentLength = _toNullableInt(row['_content_length']) ?? 0;
      if (contentLength > _todoTextChunkSize) {
        row['content'] = await _readTodoTextColumn(
          db,
          row['uuid']?.toString() ?? '',
          'content',
          contentLength,
        );
      }
      row.remove('_content_length');
      hydratedRows.add(row);
    }
    return hydratedRows;
  }

  Future<Map<String, dynamic>> _hydrateTodoRow(
    DatabaseExecutor db,
    Map<String, dynamic> row, {
    bool includeConflictData = false,
  }) async {
    final hydrated = Map<String, dynamic>.from(row);
    final uuid = hydrated['uuid']?.toString();
    if (uuid == null || uuid.isEmpty) {
      hydrated.remove('_content_length');
      hydrated.remove('_remark_length');
      if (includeConflictData) {
        hydrated.remove('_conflict_length');
      }
      return hydrated;
    }

    if (hydrated['content'] == null) {
      hydrated['content'] = await _readTodoTextColumn(
        db,
        uuid,
        'content',
        _toNullableInt(row['_content_length']),
      );
    }
    if (hydrated['remark'] == null) {
      hydrated['remark'] = await _readTodoTextColumn(
        db,
        uuid,
        'remark',
        _toNullableInt(row['_remark_length']),
      );
    }
    if (includeConflictData) {
      if (hydrated['conflict_data'] == null) {
        hydrated['conflict_data'] = await _readTodoTextColumn(
          db,
          uuid,
          'conflict_data',
          _toNullableInt(row['_conflict_length']),
        );
      }
    }
    hydrated.remove('_content_length');
    hydrated.remove('_remark_length');
    if (includeConflictData) {
      hydrated.remove('_conflict_length');
    }
    return hydrated;
  }

  Future<String?> _readTodoTextColumn(
    DatabaseExecutor db,
    String uuid,
    String column,
    int? textLength,
  ) async {
    if (textLength == null || textLength <= 0) return null;

    final buffer = StringBuffer();
    for (var offset = 0; offset < textLength; offset += _todoTextChunkSize) {
      final result = await db.rawQuery(
        'SELECT substr($column, ?, ?) AS value FROM todos WHERE uuid = ? LIMIT 1',
        [offset + 1, _todoTextChunkSize, uuid],
      );
      if (result.isEmpty) break;
      final chunk = result.first['value']?.toString() ?? '';
      if (chunk.isEmpty) break;
      buffer.write(chunk);
    }

    final value = buffer.toString();
    return value.isEmpty ? null : value;
  }

  int? _toNullableInt(dynamic value) {
    return JsonValueParser.toNullableInt(value);
  }

  // 🚀 Uni-Sync 4.0: 获取所有待办事项（用于缓存重载）
  Future<List<TodoItem>> getTodos() async {
    final List<Map<String, dynamic>> maps = await getTodoMaps(
      includeDeleted: true,
    );
    return List.generate(maps.length, (i) => TodoItem.fromSql(maps[i]));
  }

  // 🚀 Uni-Sync 4.0: 获取所有待办组
  Future<List<TodoGroup>> getTodoGroups() async {
    final db = await DatabaseHelper.instance.database;
    final List<Map<String, dynamic>> maps = await db.query('todo_groups');
    return List.generate(maps.length, (i) => TodoGroup.fromSql(maps[i]));
  }

  // 🚀 Uni-Sync 4.0: 获取所有倒计时
  Future<List<CountdownItem>> getCountdowns() async {
    final db = await DatabaseHelper.instance.database;
    final List<Map<String, dynamic>> maps = await db.query('countdowns');
    return List.generate(maps.length, (i) => CountdownItem.fromSql(maps[i]));
  }

  // --- 搜索历史管理 ---

  Future<void> insertSearchHistory(String query) async {
    final db = await database;
    final hour = DateTime.now().hour;
    String column = 'morning_count';
    if (hour >= 12 && hour < 18) {
      column = 'afternoon_count';
    } else if (hour >= 18 && hour < 24) {
      column = 'evening_count';
    } else if (hour >= 0 && hour < 6) {
      column = 'night_count';
    }

    await db.rawInsert(
      '''
      INSERT INTO search_history (query, timestamp, frequency, $column)
      VALUES (?, ?, 1, 1)
      ON CONFLICT(query) DO UPDATE SET
        frequency = frequency + 1,
        timestamp = ?,
        $column = $column + 1
    ''',
      [
        query,
        DateTime.now().millisecondsSinceEpoch,
        DateTime.now().millisecondsSinceEpoch,
      ],
    );
  }

  Future<List<Map<String, dynamic>>> getRecentSearches({
    int limit = 10,
    int? currentHour,
  }) async {
    final db = await database;
    final hour = currentHour ?? DateTime.now().hour;

    String timeWeightCol = 'morning_count';
    if (hour >= 12 && hour < 18) {
      timeWeightCol = 'afternoon_count';
    } else if (hour >= 18 && hour < 24) {
      timeWeightCol = 'evening_count';
    } else if (hour >= 0 && hour < 6) {
      timeWeightCol = 'night_count';
    }

    return await db.query(
      'search_history',
      orderBy: '$timeWeightCol DESC, frequency DESC, timestamp DESC',
      limit: limit,
    );
  }
}
