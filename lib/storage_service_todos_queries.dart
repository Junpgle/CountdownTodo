part of 'storage_service.dart';

// ignore_for_file: annotate_overrides, unused_element, unused_element_parameter

mixin _StorageTodoQueries on _StorageServiceBase {
  Future<TodoTrashPurgePlan> previewPermanentTodoDelete(
    String username,
    String uuid,
  ) async {
    final db = await DatabaseHelper.instance.databaseForUser(username);
    final rows = await db.query('todos', where: 'uuid = ?', whereArgs: [uuid]);
    final todos = _parseTodoItemsIsolate(rows);
    if (todos.isEmpty) throw StateError('待办已不存在，请刷新后再试。');
    return TodoTrashPurgeService.forItem(todos.single);
  }

  Future<TodoTrashPurgePlan> previewPermanentTodoSeriesDelete(
    String username,
    String seriesId,
  ) async {
    final normalizedId = seriesId.trim();
    if (normalizedId.isEmpty) throw StateError('系列标识无效，无法批量清理。');
    final db = await DatabaseHelper.instance.databaseForUser(username);
    final rows = await db.query(
      'todos',
      where:
          'recurrence_series_id = ? OR '
          "(uuid = ? AND TRIM(COALESCE(recurrence_series_id, '')) = '')",
      whereArgs: [normalizedId, normalizedId],
    );
    return TodoTrashPurgeService.forSeries(
      _parseTodoItemsIsolate(rows),
      normalizedId,
    );
  }

  Future<TodoTrashPurgePlan> previewClearTodoRecycleBin(String username) async {
    final db = await DatabaseHelper.instance.databaseForUser(username);
    final rows = await db.query('todos', where: 'is_deleted = 1');
    return TodoTrashPurgeService.forRecycleBin(_parseTodoItemsIsolate(rows));
  }

  Future<TodoTrashPurgeResult> purgeTodoTrash(
    String username,
    TodoTrashPurgePlan plan,
  ) async {
    if (plan.targetEntries.isEmpty ||
        plan.targetIds.length != plan.targetEntries.length) {
      throw StateError('删除范围无效，请刷新后重新确认。');
    }
    final db = await DatabaseHelper.instance.databaseForUser(username);
    final affectedDays = <String>{};
    final deletedIds = <String>[];
    final now = DateTime.now().millisecondsSinceEpoch;

    await db.transaction((txn) async {
      late List<Map<String, dynamic>> currentRows;
      late TodoTrashPurgePlan currentPlan;
      switch (plan.scope) {
        case TodoTrashPurgeScope.item:
          final id = plan.targetEntries.single.uuid;
          currentRows = await txn.query(
            'todos',
            where: 'uuid = ?',
            whereArgs: [id],
          );
          final currentTodos = _parseTodoItemsIsolate(currentRows);
          if (currentTodos.isEmpty) {
            throw StateError('待办已不存在，请刷新列表后重试。');
          }
          currentPlan = TodoTrashPurgeService.forItem(currentTodos.single);
        case TodoTrashPurgeScope.series:
          final seriesId = plan.seriesId?.trim();
          if (seriesId == null || seriesId.isEmpty) {
            throw StateError('系列标识无效，请刷新列表后重试。');
          }
          currentRows = await txn.query(
            'todos',
            where:
                'recurrence_series_id = ? OR '
                "(uuid = ? AND TRIM(COALESCE(recurrence_series_id, '')) = '')",
            whereArgs: [seriesId, seriesId],
          );
          currentPlan = TodoTrashPurgeService.forSeries(
            _parseTodoItemsIsolate(currentRows),
            seriesId,
          );
        case TodoTrashPurgeScope.recycleBin:
          currentRows = await txn.query('todos', where: 'is_deleted = 1');
          currentPlan = TodoTrashPurgeService.forRecycleBin(
            _parseTodoItemsIsolate(currentRows),
          );
      }

      if (!TodoTrashPurgeService.sameSnapshot(
            currentPlan.guardEntries,
            plan.guardEntries,
          ) ||
          !TodoTrashPurgeService.sameSnapshot(
            currentPlan.targetEntries,
            plan.targetEntries,
          )) {
        throw StateError('回收站内容已变化，请刷新列表后重新确认。');
      }

      final rowsById = {
        for (final row in currentRows) row['uuid']?.toString() ?? '': row,
      };
      for (final entry in plan.targetEntries) {
        final row = rowsById[entry.uuid];
        if (row == null || row['is_deleted'] != 1) {
          throw StateError('部分待办已不在回收站，未执行删除，请刷新后重试。');
        }
        affectedDays.addAll(_scheduleConflictDayKeysForRow(row));
        final deleted = await txn.delete(
          'todos',
          where: 'uuid = ? AND is_deleted = 1',
          whereArgs: [entry.uuid],
        );
        if (deleted != 1) {
          throw StateError('部分待办状态已变化，未执行删除，请刷新后重试。');
        }
        await txn.insert('op_logs', {
          'op_type': 'DELETE',
          'target_table': 'todos',
          'target_uuid': entry.uuid,
          'timestamp': now,
          'is_synced': 0,
          'sync_error': '',
        });
        deletedIds.add(entry.uuid);
      }
    });

    _recurrenceCheckCache.remove('recurrence_instances_v4_$username');
    var cacheCleared = true;
    try {
      await _clearTodoPrefsMirror(username);
    } catch (_) {
      cacheCleared = false;
    }

    var conflictsRefreshed = true;
    if (affectedDays.isNotEmpty) {
      try {
        await _refreshTodoScheduleConflicts(
          username,
          affectedDayKeys: affectedDays,
        );
      } catch (_) {
        conflictsRefreshed = false;
      }
    }
    triggerRefresh(const {DataRefreshDomain.todos});
    return TodoTrashPurgeResult(
      deletedCount: deletedIds.length,
      cacheCleared: cacheCleared,
      conflictsRefreshed: conflictsRefreshed,
    );
  }

  Future<void> permanentlyDeleteTodo(String username, String uuid) async {
    final plan = await previewPermanentTodoDelete(username, uuid);
    await purgeTodoTrash(username, plan);
  }

  Future<void> clearTodoRecycleBin(String username) async {
    final plan = await previewClearTodoRecycleBin(username);
    await purgeTodoTrash(username, plan);
  }

  bool _isHistoricalTodo(TodoItem todo, DateTime today) {
    if (!todo.isDone || todo.isDeleted) return false;

    if (todo.dueDate != null) {
      final due = todo.dueDate!;
      final dueDay = CalendarDateMath.dateOnly(due);
      return dueDay.isBefore(today);
    }

    final created = AppTimeFormats.localFromServerTimestamp(
      todo.createdDate ?? todo.createdAt,
    );
    final createdDay = CalendarDateMath.dateOnly(created);
    return createdDay.isBefore(today);
  }

  Future<int> clearHistoricalTodos(String username) async {
    final todayNow = DateTime.now();
    final today = CalendarDateMath.dateOnly(todayNow);
    final allTodos = await getTodos(username, includeDeleted: true);
    final historicalIds = allTodos
        .where((todo) => _isHistoricalTodo(todo, today))
        .map((todo) => todo.id)
        .toList();

    if (historicalIds.isEmpty) return 0;

    final db = await DatabaseHelper.instance.databaseForUser(username);
    final now = DateTime.now().millisecondsSinceEpoch;
    final batch = db.batch();
    for (final uuid in historicalIds) {
      batch.delete(
        'todo_completions',
        where: 'todo_uuid = ?',
        whereArgs: [uuid],
      );
      batch.delete('todos', where: 'uuid = ?', whereArgs: [uuid]);
      batch.insert('op_logs', {
        'op_type': 'DELETE',
        'target_table': 'todos',
        'target_uuid': uuid,
        'timestamp': now,
        'is_synced': 0,
        'sync_error': '',
      });
    }
    await batch.commit(noResult: true);

    await _clearTodoPrefsMirror(username);
    triggerRefresh(const {DataRefreshDomain.todos});
    requestSync(username);
    return historicalIds.length;
  }

  Future<void> permanentlyDeleteCountdown(String username, String uuid) async {
    final db = await DatabaseHelper.instance.databaseForUser(username);
    await db.delete('countdowns', where: 'uuid = ?', whereArgs: [uuid]);

    // 同步清理 Prefs 缓存
    final prefs = await SharedPreferences.getInstance();
    final countdownsKey = _scopedKey(keyCountdowns, username);
    List<String> list = prefs.getStringList(countdownsKey) ?? [];
    list.removeWhere((jsonStr) {
      try {
        final map = jsonDecode(jsonStr);
        return map['id'] == uuid || map['uuid'] == uuid;
      } catch (_) {
        return false;
      }
    });
    await prefs.setStringList(countdownsKey, list);

    // 记录删除操作到 Oplog
    await db.insert('op_logs', {
      'op_type': 'DELETE',
      'target_table': 'countdowns',
      'target_uuid': uuid,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'is_synced': 0,
      'sync_error': '',
    });

    triggerRefresh(const {DataRefreshDomain.countdowns});
  }

  Future<List<TodoItem>> getTodos(
    String username, {
    bool includeDeleted = false,
    int? limit,
    int offset = 0,
  }) async {
    final requestKey = _todoRequestKey(
      username,
      includeDeleted: includeDeleted,
      limit: limit,
      offset: offset,
    );
    final inflight = _inflightTodoRequests[requestKey];
    if (inflight != null) {
      debugPrint("🔁 getTodos 复用进行中请求: $requestKey");
      _sharedInflightTodoFutures[inflight] = _sharedInflightMarker;
      final shared = await inflight;
      return _cloneTodoItems(shared);
    }

    final future = _getTodosInternal(
      username,
      includeDeleted: includeDeleted,
      limit: limit,
      offset: offset,
    );
    _inflightTodoRequests[requestKey] = future;

    try {
      final result = await future;
      if (_sharedInflightTodoFutures[future] != null) {
        return _cloneTodoItems(result);
      }
      return result;
    } finally {
      if (identical(_inflightTodoRequests[requestKey], future)) {
        _inflightTodoRequests.remove(requestKey);
      }
    }
  }

  /// Preserve the legacy preference migration performed by the normal read
  /// path before strict fixed-schedule relationship reads.
  Future<void> _ensureFixedScheduleRelationMigration(
    String username, {
    bool boundedRead = false,
  }) async {
    final migrationKey = 'migration_marker_${username}_v4';
    final sharedPrefs = await prefs;
    if (!(sharedPrefs.getBool(migrationKey) ?? false)) {
      await getTodos(
        username,
        includeDeleted: true,
        limit: boundedRead ? 1 : null,
      );
    }
  }

  /// Reads complete todo snapshots for compatibility with relationship callers.
  /// The final database query deliberately remains strict and can throw.
  Future<List<TodoItem>> getTodosForFixedScheduleRelations(
    String username,
  ) async {
    await _ensureFixedScheduleRelationMigration(username);

    final db = await DatabaseHelper.instance.databaseForUser(username);
    final maps = await DatabaseHelper.instance.getTodoMaps(
      includeDeleted: true,
      includeConflictData: true,
      databaseOverride: db,
    );
    return _parseTodoItemsIsolate(maps);
  }

  Future<({List<TodoItem> todos, bool hasMore})>
  getTodosForFixedScheduleRelationPage(
    String username, {
    required String? teamUuid,
    required String query,
    required int limit,
    required int offset,
  }) async {
    await _ensureFixedScheduleRelationMigration(username, boundedRead: true);

    final safeLimit = limit.clamp(1, 100).toInt();
    final safeOffset = offset < 0 ? 0 : offset;
    final normalizedTeamUuid = teamUuid?.trim();
    final teamValue = normalizedTeamUuid == null || normalizedTeamUuid.isEmpty
        ? ''
        : normalizedTeamUuid;
    final whereParts = <String>[
      't.is_deleted IS NOT 1',
      "COALESCE(TRIM(t.team_uuid), '') = ?",
    ];
    final whereArgs = <Object?>[teamValue];
    final normalizedQuery = query.trim().toLowerCase();
    if (normalizedQuery.isNotEmpty) {
      final escapedQuery = normalizedQuery
          .replaceAll('!', '!!')
          .replaceAll('%', '!%')
          .replaceAll('_', '!_');
      whereParts.add("LOWER(COALESCE(t.content, '')) LIKE ? ESCAPE '!'");
      whereArgs.add('%$escapedQuery%');
    }

    final db = await DatabaseHelper.instance.databaseForUser(username);
    final maps = await DatabaseHelper.instance.getTodoMaps(
      where: whereParts.join(' AND '),
      whereArgs: whereArgs,
      limit: safeLimit + 1,
      offset: safeOffset,
      ordering: TodoMapsOrdering.fixedScheduleRelations,
      includeConflictData: true,
      databaseOverride: db,
    );
    final hasMore = maps.length > safeLimit;
    final pageMaps = hasMore ? maps.take(safeLimit).toList() : maps;
    return (todos: _parseTodoItemsIsolate(pageMaps), hasMore: hasMore);
  }

  Future<List<TodoItem>> getTodosForFixedScheduleRelationIds(
    String username,
    Set<String> todoIds,
  ) async {
    final normalizedIds = todoIds
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toSet();
    if (normalizedIds.isEmpty) return const [];

    await _ensureFixedScheduleRelationMigration(username, boundedRead: true);

    final db = await DatabaseHelper.instance.databaseForUser(username);
    final ids = normalizedIds.toList(growable: false);
    final rowsById = <String, Map<String, dynamic>>{};
    const chunkSize = 400;
    for (var offset = 0; offset < ids.length; offset += chunkSize) {
      final chunk = ids.skip(offset).take(chunkSize).toList(growable: false);
      final maps = await DatabaseHelper.instance.getTodoMaps(
        includeDeleted: true,
        uuids: chunk,
        includeConflictData: true,
        databaseOverride: db,
      );
      for (final map in maps) {
        final id = map['uuid']?.toString();
        if (id != null && id.isNotEmpty) rowsById[id] = map;
      }
    }
    return _parseTodoItemsIsolate(rowsById.values.toList(growable: false));
  }

  Future<List<TodoItem>> getTodosForWidget(String username) async {
    final now = DateTime.now();
    final todayKey = '${now.year}-${now.month}-${now.day}';
    if (_lastRecurrenceCheckDate != todayKey) {
      _lastRecurrenceCheckDate = todayKey;
      _recurrenceCheckCache.clear();
    }

    final recurrenceCacheKey = 'recurrence_instances_v4_$username';
    final prefs = await StorageService.prefs;
    final migrationComplete =
        prefs.getBool('migration_marker_${username}_v4') ?? false;
    final cleanupComplete =
        prefs.getBool('cleanup_done_${username}_v4_repair') ?? false;
    if (!_recurrenceCheckCache.containsKey(recurrenceCacheKey) ||
        !migrationComplete) {
      return getTodos(username);
    }

    try {
      if (!cleanupComplete) {
        await _clearTodoPrefsMirror(username);
        await prefs.setBool('cleanup_done_${username}_v4_repair', true);
      }
      final maps = await DatabaseHelper.instance.getTodoWidgetMaps(username);
      return maps.map(TodoItem.fromSql).toList(growable: false);
    } catch (_) {
      return getTodos(username);
    }
  }

  Future<List<TodoItem>> getTodosForSearchDateRange(
    String username, {
    required DateTime from,
    required DateTime to,
  }) async {
    final startMs = from.millisecondsSinceEpoch;
    final endMs = to.millisecondsSinceEpoch;
    final requestKey = (username, startMs, endMs);
    final inflight = _inflightTodoSearchDateRequests[requestKey];
    if (inflight != null) {
      _sharedInflightTodoFutures[inflight] = _sharedInflightMarker;
      return _cloneTodoItems(await inflight);
    }

    final future = _getTodosForSearchDateRangeInternal(
      username,
      startMs: startMs,
      endMs: endMs,
    );
    _inflightTodoSearchDateRequests[requestKey] = future;
    try {
      final result = await future;
      if (_sharedInflightTodoFutures[future] != null) {
        return _cloneTodoItems(result);
      }
      return result;
    } finally {
      if (identical(_inflightTodoSearchDateRequests[requestKey], future)) {
        _inflightTodoSearchDateRequests.remove(requestKey);
      }
    }
  }

  Future<List<TodoItem>> _getTodosForSearchDateRangeInternal(
    String username, {
    required int startMs,
    required int endMs,
  }) async {
    if (endMs <= startMs) return const <TodoItem>[];

    final now = DateTime.now();
    final todayKey = '${now.year}-${now.month}-${now.day}';
    if (_lastRecurrenceCheckDate != todayKey) {
      _lastRecurrenceCheckDate = todayKey;
      _recurrenceCheckCache.clear();
    }

    final recurrenceCacheKey = 'recurrence_instances_v4_$username';
    final prefs = await StorageService.prefs;
    final migrationComplete =
        prefs.getBool('migration_marker_${username}_v4') ?? false;
    if (!_recurrenceCheckCache.containsKey(recurrenceCacheKey) ||
        !migrationComplete) {
      final allTodos = await getTodos(username);
      return _filterTodosForSearchDateRange(allTodos, startMs, endMs);
    }

    try {
      final db = await DatabaseHelper.instance.databaseForUser(username);
      final maps = await DatabaseHelper.instance.getTodoMaps(
        where:
            't.is_deleted IS NOT 1 AND '
            '((t.due_date >= $startMs AND t.due_date < $endMs) OR '
            '(t.created_date >= $startMs AND t.created_date < $endMs))',
        includeConflictData: true,
        databaseOverride: db,
      );
      if (maps.isEmpty) return const <TodoItem>[];

      // getTodos normally repairs these flags while loading the full table.
      // For this indexed subset, apply the same normalization only to rows
      // returned for the requested day instead of scanning every todo.
      for (final map in maps) {
        final hasConflict = _parseNullableInt(map['has_conflict']) ?? 0;
        final conflictData = map['conflict_data']?.toString();
        final hasConflictData =
            conflictData != null &&
            conflictData.trim().isNotEmpty &&
            conflictData != 'null';
        if ((hasConflict == 1 && !hasConflictData) ||
            (hasConflict == 0 && hasConflictData)) {
          map['has_conflict'] = hasConflict == 1 && hasConflictData ? 1 : 0;
          map['conflict_data'] = null;
        }
      }

      final candidates = maps.length > 50
          ? await compute(_parseTodoItemsIsolate, maps)
          : maps.map(TodoItem.fromSql).toList();
      final todos = _filterTodosForSearchDateRange(candidates, startMs, endMs);
      final clearedScheduleConflicts = todos
          .where(ConflictVisibilityService.clearImpossibleTodoScheduleConflict)
          .toList();
      if (clearedScheduleConflicts.isNotEmpty) {
        await saveTodos(
          username,
          clearedScheduleConflicts,
          sync: false,
          isSyncSource: true,
          recomputeScheduleConflicts: false,
        );
      }
      return todos;
    } catch (_) {
      return _filterTodosForSearchDateRange(
        await getTodos(username),
        startMs,
        endMs,
      );
    }
  }

  List<TodoItem> _filterTodosForSearchDateRange(
    Iterable<TodoItem> todos,
    int startMs,
    int endMs,
  ) {
    return todos.where((todo) {
      if (todo.isDeleted) return false;
      final dueAt = todo.dueDate?.millisecondsSinceEpoch;
      final createdAt = todo.createdDate;
      return (dueAt != null && dueAt >= startMs && dueAt < endMs) ||
          (createdAt != null && createdAt >= startMs && createdAt < endMs);
    }).toList();
  }

  Future<List<TodoItem>> getTodosForTimelineRange(
    String username, {
    required DateTime from,
    required DateTime to,
  }) async {
    final startMs = from.millisecondsSinceEpoch;
    final endMs = to.millisecondsSinceEpoch;
    final requestKey = (username, startMs, endMs);
    final inflight = _inflightTimelineTodoRequests[requestKey];
    if (inflight != null) {
      _sharedInflightTodoFutures[inflight] = _sharedInflightMarker;
      return _cloneTodoItems(await inflight);
    }

    final future = _getTodosForTimelineRangeInternal(
      username,
      startMs: startMs,
      endMs: endMs,
    );
    _inflightTimelineTodoRequests[requestKey] = future;
    try {
      final result = await future;
      if (_sharedInflightTodoFutures[future] != null) {
        return _cloneTodoItems(result);
      }
      return result;
    } finally {
      if (identical(_inflightTimelineTodoRequests[requestKey], future)) {
        _inflightTimelineTodoRequests.remove(requestKey);
      }
    }
  }

  Future<List<TodoItem>> _getTodosForTimelineRangeInternal(
    String username, {
    required int startMs,
    required int endMs,
  }) async {
    if (endMs <= startMs) return const <TodoItem>[];

    final now = DateTime.now();
    final todayKey = '${now.year}-${now.month}-${now.day}';
    if (_lastRecurrenceCheckDate != todayKey) {
      _lastRecurrenceCheckDate = todayKey;
      _recurrenceCheckCache.clear();
    }

    final recurrenceCacheKey = 'recurrence_instances_v4_$username';
    if (!_recurrenceCheckCache.containsKey(recurrenceCacheKey)) {
      final allTodos = await getTodos(username);
      return _filterTodosForTimelineRange(allTodos, startMs, endMs);
    }

    try {
      final db = await DatabaseHelper.instance.databaseForUser(username);
      await _clearGhostConflictFlags(db, tables: const ['todos']);
      final where =
          """
        t.is_deleted IS NOT 1 AND (
          (t.created_at >= $startMs AND t.created_at < $endMs) OR
          (t.due_date >= $startMs AND t.due_date < $endMs) OR
          (t.is_completed = 0 AND t.updated_at >= $startMs AND t.updated_at < $endMs) OR
          (t.is_completed = 1 AND COALESCE(t.completed_at, CASE WHEN TRIM(COALESCE(t.recurrence_series_id, '')) != '' THEN COALESCE(t.created_date, t.due_date, t.created_at, t.updated_at) ELSE t.updated_at END) >= $startMs AND
           COALESCE(t.completed_at, CASE WHEN TRIM(COALESCE(t.recurrence_series_id, '')) != '' THEN COALESCE(t.created_date, t.due_date, t.created_at, t.updated_at) ELSE t.updated_at END) < $endMs) OR
          (TRIM(COALESCE(t.recurrence_series_id, '')) != '' AND
            COALESCE(t.created_date, t.created_at) >= $startMs AND
            COALESCE(t.created_date, t.created_at) < $endMs)
        )
      """;
      final maps = await DatabaseHelper.instance.getTodoMaps(
        where: where,
        includeConflictData: true,
        databaseOverride: db,
      );
      if (maps.isEmpty) {
        final activeTodos = await db.rawQuery(
          'SELECT 1 FROM todos WHERE is_deleted IS NOT 1 LIMIT 1',
        );
        if (activeTodos.isNotEmpty) return const <TodoItem>[];
        return _filterTodosForTimelineRange(
          await getTodos(username),
          startMs,
          endMs,
        );
      }

      final todos = maps.length > 50
          ? await compute(_parseTodoItemsIsolate, maps)
          : maps.map(TodoItem.fromSql).toList();
      final clearedScheduleConflicts = todos
          .where(ConflictVisibilityService.clearImpossibleTodoScheduleConflict)
          .toList();
      if (clearedScheduleConflicts.isNotEmpty) {
        await saveTodos(
          username,
          clearedScheduleConflicts,
          sync: false,
          isSyncSource: true,
          recomputeScheduleConflicts: false,
        );
      }
      return todos;
    } catch (_) {
      return _filterTodosForTimelineRange(
        await getTodos(username),
        startMs,
        endMs,
      );
    }
  }

  List<TodoItem> _filterTodosForTimelineRange(
    Iterable<TodoItem> todos,
    int startMs,
    int endMs,
  ) {
    bool isInRange(int timestamp) => timestamp >= startMs && timestamp < endMs;

    return todos.where((todo) {
      final seriesId = todo.recurrenceSeriesId?.trim();
      final recurrenceStartInRange =
          seriesId != null &&
          seriesId.isNotEmpty &&
          isInRange(todo.createdDate ?? todo.createdAt);
      final dueAt = todo.dueDate?.millisecondsSinceEpoch;
      final completedAt =
          todo.completedAt ??
          (seriesId != null && seriesId.isNotEmpty
              ? (todo.createdDate ?? dueAt ?? todo.createdAt)
              : null);
      return isInRange(todo.createdAt) ||
          (dueAt != null && isInRange(dueAt)) ||
          (completedAt != null && isInRange(completedAt)) ||
          (!todo.isDone && isInRange(todo.updatedAt)) ||
          recurrenceStartInRange;
    }).toList();
  }

  Future<List<TodoItem>> _getTodosInternal(
    String username, {
    bool includeDeleted = false,
    int? limit,
    int offset = 0,
  }) async {
    final prefs = await StorageService.prefs;
    final startedAt = DateTime.now();
    // 🚀 Uni-Sync 安全方案：双轨读取 + 逃生通道
    try {
      final dbHelper = DatabaseHelper.instance;
      final db = await dbHelper.databaseForUser(username);
      await _clearGhostConflictFlags(db, tables: const ['todos']);

      final migrationKey = "migration_marker_${username}_v4";
      bool alreadyMigrated = prefs.getBool(migrationKey) ?? false;

      if (alreadyMigrated) {
        await _clearTodoPrefsMirror(username);
      }

      // 🚀 核心补丁：清理先前版本迁移后遗留的超大数据 (解决 170MB+ 内存占用与启动卡顿)
      final String cleanupKey = "cleanup_done_${username}_v4_repair";
      if (alreadyMigrated && !(prefs.getBool(cleanupKey) ?? false)) {
        await prefs.remove(_scopedKey(keyTodos, username));
        await prefs.remove(keyTodos);
        await prefs.setBool(cleanupKey, true);
        debugPrint("🗑️ Todos 残留数据修复清理完成。");
      }

      if (!alreadyMigrated) {
        List<String> legacyJsonList =
            prefs.getStringList(_scopedKey(keyTodos, username)) ?? [];
        if (legacyJsonList.isEmpty && username.isNotEmpty) {
          legacyJsonList = prefs.getStringList(keyTodos) ?? [];
        }

        if (legacyJsonList.isNotEmpty) {
          debugPrint("🚀 发现未迁移老数据，正在执行增量迁移...");
          List<TodoItem> legacyItems = [];
          for (var e in legacyJsonList) {
            try {
              legacyItems.add(TodoItem.fromJson(jsonDecode(e)));
            } catch (_) {}
          }
          // 本地存储迁移不是用户修改，不生成 oplog，避免用迁移时间和云端制造冲突。
          await saveTodos(
            username,
            legacyItems,
            sync: false,
            isSyncSource: true,
          );
          // 🚀 迁移成功后，必须物理清除 SharedPreferences 中的巨大 JSON 块
          // 否则 Android 的原生 SharedPreferences 会一直将此 170MB+ 的数据留在内存中导致 OOM
          await prefs.remove(_scopedKey(keyTodos, username));
          await prefs.remove(keyTodos);
          debugPrint("✅ 老数据增量迁移完成并已物理清理。");
        }
        await prefs.setBool(migrationKey, true);
      }

      List<Map<String, dynamic>> maps = await dbHelper.getTodoMaps(
        includeDeleted: includeDeleted,
        limit: limit,
        offset: offset,
        includeConflictData: true,
        databaseOverride: db,
      );
      if (maps.isNotEmpty) {
        final recurrenceSeriesIds = maps
            .where(
              (map) =>
                  (includeDeleted || map['is_deleted'] != 1) &&
                  (_parseNullableInt(map['recurrence']) ?? 0) != 0,
            )
            .map((map) {
              final seriesId = map['recurrence_series_id']?.toString().trim();
              return seriesId == null || seriesId.isEmpty
                  ? map['uuid']?.toString()
                  : seriesId;
            })
            .whereType<String>()
            .where((seriesId) => seriesId.isNotEmpty)
            .toSet();
        if (recurrenceSeriesIds.isNotEmpty) {
          final loadCompleteSeries = limit != null;
          final shouldLoadSeries = loadCompleteSeries || !includeDeleted;
          if (shouldLoadSeries) {
            // Unbounded list reads already include every row. Limited reads
            // need complete series for progress summaries and safe recycle-bin
            // restore previews, including series whose rule carrier is deleted.
            // Non-deleted-only reads also add deleted tombstones for recurrence
            // repair.
            final seriesMaps = await dbHelper.getTodoMaps(
              includeDeleted: true,
              deletedOnly: !loadCompleteSeries,
              recurrenceSeriesIds: recurrenceSeriesIds,
              includeConflictData: true,
              databaseOverride: db,
            );
            final mapsById = <String, Map<String, dynamic>>{
              for (final map in maps) map['uuid'].toString(): map,
            };
            for (final map in seriesMaps) {
              mapsById[map['uuid'].toString()] = map;
            }
            maps = mapsById.values.toList();
          }
        }
      }
      if (maps.isNotEmpty) {
        List<TodoItem> todos;
        // 🚀 性能优化：当待办数量较多时，使用 Isolate 解析，减少主线程解析耗时导致的 UI 卡顿
        if (maps.length > 50) {
          todos = await compute(_parseTodoItemsIsolate, maps);
        } else {
          todos = maps.map((m) => TodoItem.fromSql(m)).toList();
        }
        final handledTodos = await _handleRecurrenceLogic(username, todos);
        final clearedScheduleConflicts = handledTodos
            .where(
              ConflictVisibilityService.clearImpossibleTodoScheduleConflict,
            )
            .toList();
        if (clearedScheduleConflicts.isNotEmpty) {
          await saveTodos(
            username,
            clearedScheduleConflicts,
            sync: false,
            isSyncSource: true,
            recomputeScheduleConflicts: false,
          );
        }
        //debugPrint(
        //    "📦 getTodos(SQL) 完成: count=${handledTodos.length}, includeDeleted=$includeDeleted, limit=$limit, cost=${DateTime.now().difference(startedAt).inMilliseconds}ms");
        if (!includeDeleted) {
          return handledTodos.where((todo) => !todo.isDeleted).toList();
        }
        return handledTodos;
      } else {
        return [];
      }
    } catch (e) {
      debugPrint("⚠️ SQL 引擎异常，启动逃生通道: $e");
    }

    // 🚀 逃生通道：兜底读取 Prefs
    List<String> list =
        prefs.getStringList(_scopedKey(keyTodos, username)) ?? [];
    List<TodoItem> legacyTodos;

    if (list.length > 50) {
      legacyTodos = await compute(_parseTodoJsonItemsIsolate, list);
    } else {
      legacyTodos = [];
      for (var e in list) {
        try {
          legacyTodos.add(TodoItem.fromJson(jsonDecode(e)));
        } catch (_) {}
      }
    }
    final handledLegacyTodos = await _handleRecurrenceLogic(
      username,
      legacyTodos,
    );
    final clearedLegacyScheduleConflicts = handledLegacyTodos
        .where(ConflictVisibilityService.clearImpossibleTodoScheduleConflict)
        .toList();
    if (clearedLegacyScheduleConflicts.isNotEmpty) {
      await prefs.setStringList(
        _scopedKey(keyTodos, username),
        handledLegacyTodos.map((todo) => jsonEncode(todo.toJson())).toList(),
      );
    }
    Iterable<TodoItem> filtered = handledLegacyTodos;
    if (!includeDeleted) {
      filtered = filtered.where((todo) => !todo.isDeleted);
    }
    if (offset > 0) filtered = filtered.skip(offset);
    if (limit != null && limit >= 0) {
      filtered = filtered.take(limit);
    }
    final result = filtered.toList();
    debugPrint(
      "📦 getTodos(Prefs Fallback) 完成: count=${result.length}, includeDeleted=$includeDeleted, limit=$limit, cost=${DateTime.now().difference(startedAt).inMilliseconds}ms",
    );
    return result;
  }

  Future<void> clearTeamItems(String teamUuid) async {
    final db = await DatabaseHelper.instance.database;
    final now = DateTime.now().millisecondsSinceEpoch;

    // 1. 软删除 (标记 isDeleted，通过同步传播到服务器)
    await db.rawUpdate(
      "UPDATE todos SET is_deleted = 1, version = version + 1, updated_at = ? WHERE team_uuid = ? AND is_deleted = 0",
      [now, teamUuid],
    );
    await db.rawUpdate(
      "UPDATE todo_groups SET is_deleted = 1, version = version + 1, updated_at = ? WHERE team_uuid = ? AND is_deleted = 0",
      [now, teamUuid],
    );
    await db.rawUpdate(
      "UPDATE countdowns SET is_deleted = 1, version = version + 1, updated_at = ? WHERE team_uuid = ? AND is_deleted = 0",
      [now, teamUuid],
    );
    await db.rawUpdate(
      "UPDATE time_logs SET is_deleted = 1, version = version + 1, updated_at = ? WHERE team_uuid = ? AND is_deleted = 0",
      [now, teamUuid],
    );
    await db.rawUpdate(
      "UPDATE courses SET is_deleted = 1, version = version + 1, updated_at = ? WHERE team_uuid = ? AND is_deleted = 0",
      [now, teamUuid],
    );
    await db.rawUpdate(
      "UPDATE fixed_schedules SET is_deleted = 1, version = version + 1, updated_at = ? WHERE team_uuid = ? AND is_deleted = 0",
      [now, teamUuid],
    );
    // 规划块本身不保存 team_uuid，需通过关联待办级联清理；否则退出团队后
    // 仍会在首页计划区看到已经失去权限的团队安排。
    await db.rawUpdate(
      '''UPDATE todo_plan_blocks
           SET is_deleted = 1, version = version + 1, updated_at = ?
           WHERE todo_uuid IN (
             SELECT uuid FROM todos WHERE team_uuid = ?
           ) AND is_deleted = 0''',
      [now, teamUuid],
    );

    await db.delete(
      'todo_completions',
      where: 'todo_uuid IN (SELECT uuid FROM todos WHERE team_uuid = ?)',
      whereArgs: [teamUuid],
    );

    // 🚀 关键：为软删除的项创建 op_log，使同步引擎能将删除传播到服务端
    final deletedTodos = await db.query(
      'todos',
      columns: ['uuid', 'version', 'updated_at'],
      where: 'team_uuid = ? AND is_deleted = 1 AND updated_at = ?',
      whereArgs: [teamUuid, now],
    );
    for (var row in deletedTodos) {
      await db.insert('op_logs', {
        'op_type': 'UPSERT',
        'target_table': 'todos',
        'target_uuid': row['uuid'],
        'data_json': jsonEncode({
          'uuid': row['uuid'],
          'is_deleted': true,
          'version': row['version'],
          'updated_at': row['updated_at'],
        }),
        'timestamp': now,
        'is_synced': 0,
        'sync_error': '',
      });
    }
    final deletedGroups = await db.query(
      'todo_groups',
      columns: ['uuid', 'version', 'updated_at'],
      where: 'team_uuid = ? AND is_deleted = 1 AND updated_at = ?',
      whereArgs: [teamUuid, now],
    );
    for (var row in deletedGroups) {
      await db.insert('op_logs', {
        'op_type': 'UPSERT',
        'target_table': 'todo_groups',
        'target_uuid': row['uuid'],
        'data_json': jsonEncode({
          'uuid': row['uuid'],
          'is_deleted': true,
          'version': row['version'],
          'updated_at': row['updated_at'],
        }),
        'timestamp': now,
        'is_synced': 0,
        'sync_error': '',
      });
    }
    final deletedCountdowns = await db.query(
      'countdowns',
      columns: ['uuid', 'version', 'updated_at'],
      where: 'team_uuid = ? AND is_deleted = 1 AND updated_at = ?',
      whereArgs: [teamUuid, now],
    );
    for (var row in deletedCountdowns) {
      await db.insert('op_logs', {
        'op_type': 'UPSERT',
        'target_table': 'countdowns',
        'target_uuid': row['uuid'],
        'data_json': jsonEncode({
          'uuid': row['uuid'],
          'is_deleted': true,
          'version': row['version'],
          'updated_at': row['updated_at'],
        }),
        'timestamp': now,
        'is_synced': 0,
        'sync_error': '',
      });
    }
    final deletedTimeLogs = await db.query(
      'time_logs',
      columns: ['uuid', 'version', 'updated_at'],
      where: 'team_uuid = ? AND is_deleted = 1 AND updated_at = ?',
      whereArgs: [teamUuid, now],
    );
    for (var row in deletedTimeLogs) {
      await db.insert('op_logs', {
        'op_type': 'UPSERT',
        'target_table': 'time_logs',
        'target_uuid': row['uuid'],
        'data_json': jsonEncode({
          'uuid': row['uuid'],
          'is_deleted': true,
          'version': row['version'],
          'updated_at': row['updated_at'],
        }),
        'timestamp': now,
        'is_synced': 0,
        'sync_error': '',
      });
    }
    final deletedPlanBlocks = await db.query(
      'todo_plan_blocks',
      columns: ['uuid', 'version', 'updated_at'],
      where: '''todo_uuid IN (
                   SELECT uuid FROM todos WHERE team_uuid = ?
                 ) AND is_deleted = 1 AND updated_at = ?''',
      whereArgs: [teamUuid, now],
    );
    for (var row in deletedPlanBlocks) {
      await db.insert('op_logs', {
        'op_type': 'UPSERT',
        'target_table': 'todo_plan_blocks',
        'target_uuid': row['uuid'],
        'data_json': jsonEncode({
          'uuid': row['uuid'],
          'is_deleted': true,
          'version': row['version'],
          'updated_at': row['updated_at'],
        }),
        'timestamp': now,
        'is_synced': 0,
        'sync_error': '',
      });
    }

    // 2. 🚀 关键：同步清理 SharedPreferences 缓存，防止主页残余
    final prefs = await SharedPreferences.getInstance();
    final username = prefs.getString(keyCurrentUser) ?? "";
    if (username.isNotEmpty) {
      Future<void> cleanCache(String key) async {
        List<String> list = prefs.getStringList("${key}_$username") ?? [];
        if (list.isEmpty) return;
        int originalLen = list.length;
        list.removeWhere((jsonStr) {
          try {
            final map = jsonDecode(jsonStr);
            return map['team_uuid'] == teamUuid || map['teamUuid'] == teamUuid;
          } catch (_) {
            return false;
          }
        });
        if (list.length != originalLen) {
          await prefs.setStringList("${key}_$username", list);
        }
      }

      await cleanCache(keyTodos);
      await cleanCache(keyTodoGroups);
      await cleanCache(keyCountdowns);
      await cleanCache(keyTimeLogs);
      // 🚀 补充清理：课程表与番茄记录缓存 (Key 映射已在 Service 中定义)
      await cleanCache('course_schedule_json');
      await cleanCache('pomodoro_records');
    }

    debugPrint("🧹 已清理团队 $teamUuid 的本地数据 (SQL + Cache)");
    triggerRefresh(const {
      DataRefreshDomain.todos,
      DataRefreshDomain.todoGroups,
      DataRefreshDomain.countdowns,
      DataRefreshDomain.fixedSchedules,
      DataRefreshDomain.courses,
      DataRefreshDomain.timeLogs,
      DataRefreshDomain.planBlocks,
    });
  }
}
