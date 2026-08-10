part of 'storage_service.dart';
// ignore_for_file: annotate_overrides, unused_element, unused_element_parameter

int? _parseNullableIntForIsolate(dynamic raw) {
  if (raw == null) return null;
  if (raw is int) return raw;
  if (raw is num) return raw.toInt();
  return int.tryParse(raw.toString());
}

List<TodoItem> _parseTodoItemsIsolate(List<Map<String, dynamic>> maps) {
  return maps
      .map((m) => TodoItem(
            id: m['uuid'],
            title: m['content'] ?? '',
            remark: m['remark'],
            isDone: m['is_completed'] == 1,
            isDeleted: m['is_deleted'] == 1,
            version: m['version'] ?? 1,
            updatedAt: m['updated_at'] ?? DateTime.now().millisecondsSinceEpoch,
            createdAt: m['created_at'] ?? DateTime.now().millisecondsSinceEpoch,
            createdDate: m['created_date'] != null
                ? int.tryParse(m['created_date'].toString())
                : null,
            dueDate: (m['due_date'] != null &&
                    m['due_date'].toString() != '0' &&
                    m['due_date'].toString() != 'null' &&
                    m['due_date'].toString().isNotEmpty)
                ? DateTime.fromMillisecondsSinceEpoch(
                    int.tryParse(m['due_date'].toString()) ?? 0)
                : null,
            teamUuid: m['team_uuid'],
            teamName: m['team_name'],
            creatorId: m['creator_id'],
            creatorName: m['creator_name'],
            groupId: m['group_id'],
            collabType: m['collab_type'] ?? 0,
            recurrence: RecurrenceType.values[
                (_parseNullableIntForIsolate(m['recurrence']) ?? 0)
                    .clamp(0, RecurrenceType.values.length - 1)],
            recurrenceSeriesId: m['recurrence_series_id']?.toString(),
            customIntervalDays:
                _parseNullableIntForIsolate(m['custom_interval_days']),
            recurrenceEndDate: (m['recurrence_end_date'] != null &&
                    m['recurrence_end_date'].toString() != '0')
                ? DateTime.fromMillisecondsSinceEpoch(
                    int.tryParse(m['recurrence_end_date'].toString()) ?? 0)
                : null,
            reminderMinutes: (m['reminder_minutes'] != null &&
                    m['reminder_minutes'].toString() != '-1')
                ? int.tryParse(m['reminder_minutes'].toString())
                : null,
            imagePath: m['image_path']?.toString(),
            originalText: m['original_text']?.toString(),
            isAllDay: m['is_all_day'] == 1 || m['is_all_day'] == true,
            hasConflict: m['has_conflict'] == 1 || m['has_conflict'] == true,
            serverVersionData: m['conflict_data'] != null
                ? (m['conflict_data'] is String
                    ? Map<String, dynamic>.from(jsonDecode(m['conflict_data']))
                    : Map<String, dynamic>.from(m['conflict_data']))
                : null,
          ))
      .toList();
}

List<TodoItem> _parseTodoJsonItemsIsolate(List<String> jsonList) {
  return jsonList
      .map((e) {
        try {
          return TodoItem.fromJson(jsonDecode(e));
        } catch (_) {
          return null;
        }
      })
      .whereType<TodoItem>()
      .toList();
}

mixin _StorageTodos on _StorageServiceBase {
  Future<void> saveTodos(String username, List<TodoItem> items,
      {bool sync = true,
      bool isSyncSource = false,
      bool recomputeScheduleConflicts = true}) async {
    final Map<String, TodoItem> dedupeMap = {};

    // 🚀 核心优化：只有在非同步源保存时才清理，防止 saveTodos -> getTodos 循环触发
    if (sync && !isSyncSource) {
      _recurrenceCheckCache.clear();
    }

    for (var item in items) {
      if (item.recurrence != RecurrenceType.none &&
          (item.recurrenceSeriesId == null ||
              item.recurrenceSeriesId!.isEmpty)) {
        item.recurrenceSeriesId = item.id;
      }
      final existing = dedupeMap[item.id];
      if (existing == null ||
          TodoLwwService.isIncomingWinner(
            incomingUpdatedAt: item.updatedAt,
            incomingVersion: item.version,
            currentUpdatedAt: existing.updatedAt,
            currentVersion: existing.version,
          )) {
        dedupeMap[item.id] = item;
      }
    }

    List<TodoItem> dedupeList = dedupeMap.values.toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

    // SQL 已是主存储。超大 Todo 列表写回 SharedPreferences 会在 Android 上触发 OOM，
    // 因此这里仅清理旧镜像，不再持续维护整份 prefs 缓存。
    unawaited(_clearTodoPrefsMirror(username));

    final db = await DatabaseHelper.instance.database;

    // 🚀 核心优化：批量获取现有数据，用于审计对比，避免循环中重复查询 DB
    Map<String, Map<String, dynamic>> existingItemsMap = {};
    if (!isSyncSource && dedupeList.isNotEmpty) {
      final List<Map<String, dynamic>> existing =
          await DatabaseHelper.instance.getTodoMaps(
        includeDeleted: true,
        uuids: dedupeList.map((e) => e.id).toList(),
        includeConflictData: true,
      );
      for (var row in existing) {
        existingItemsMap[row['uuid']] = row;
      }
    }
    // 同步来源也需要旧的时间字段，用来只重算被修改待办所在的日期；它不参与
    // 审计或 LWW 判定，避免改变同步写入语义。
    Map<String, Map<String, dynamic>> existingScheduleItemsMap =
        existingItemsMap;
    if (isSyncSource && dedupeList.isNotEmpty) {
      final existing = await DatabaseHelper.instance.getTodoMaps(
        includeDeleted: true,
        uuids: dedupeList.map((item) => item.id).toList(),
      );
      existingScheduleItemsMap = {
        for (final row in existing) row['uuid'].toString(): row,
      };
    }
    final affectedScheduleConflictDays = <String>{};
    // 🚀 同步写入时，查询 force-flush 保护或有待同步 oplog 的待办的 is_completed，防止同步覆盖用户本地修改
    // 优先级：force-flush > pending oplog > normal sync
    Map<String, int> existingCompletionMap = {};
    if (isSyncSource && dedupeList.isNotEmpty) {
      // 同步请求返回后到真正落库前，UI 仍可能产生新的完成/取消完成操作。
      // 在写入边界再读一次 oplog，避免仅依赖请求结束时的内存快照。
      final allItemIds = dedupeList.map((item) => item.id).toList();
      const chunkSize = 500;
      for (var start = 0; start < allItemIds.length; start += chunkSize) {
        final end = start + chunkSize < allItemIds.length
            ? start + chunkSize
            : allItemIds.length;
        final chunk = allItemIds.sublist(start, end);
        final placeholders = List.filled(chunk.length, '?').join(',');
        final rows = await db.query(
          'op_logs',
          columns: const ['target_uuid'],
          where:
              "is_synced = 0 AND target_table = 'todos' AND target_uuid IN ($placeholders)",
          whereArgs: chunk,
        );
        _pendingSyncOplogUuids.addAll(
          rows
              .map((row) => row['target_uuid']?.toString() ?? '')
              .where((uuid) => uuid.isNotEmpty),
        );
      }
    }
    if (isSyncSource &&
        dedupeList.isNotEmpty &&
        (_forceFlushProtectedUuids.isNotEmpty ||
            _pendingSyncOplogUuids.isNotEmpty)) {
      final localPrefs = await prefs;
      final int currentUserId = localPrefs.getInt('current_user_id') ?? 0;
      if (currentUserId > 0) {
        // 需要保护的 UUID = force-flush 的 + pending oplog 的
        final uuidsToPreserve = dedupeList
            .where((item) =>
                _forceFlushProtectedUuids.contains(item.id) ||
                _pendingSyncOplogUuids.contains(item.id))
            .map((item) => item.id)
            .toList();
        if (uuidsToPreserve.isNotEmpty) {
          final placeholders =
              List.filled(uuidsToPreserve.length, '?').join(',');
          final rows = await db.rawQuery(
            'SELECT t.uuid, CASE WHEN t.collab_type = 1 AND c.is_completed IS NOT NULL THEN c.is_completed ELSE t.is_completed END AS is_completed '
            'FROM todos t LEFT JOIN todo_completions c ON t.uuid = c.todo_uuid AND c.user_id = ? '
            'WHERE t.uuid IN ($placeholders)',
            [currentUserId, ...uuidsToPreserve],
          );
          for (var row in rows) {
            existingCompletionMap[row['uuid'] as String] =
                (row['is_completed'] as int?) ?? 0;
          }
          //debugPrint(
          //  '🧪 [SyncDiag][saveTodos-sync] preserving ${existingCompletionMap.length} protected completions (force-flush=${_forceFlushProtectedUuids.length}, pending-oplog=${_pendingSyncOplogUuids.length})');
        }
      }
    }

    // 🚀 Batch 极速批量写入
    final batch = db.batch();
    for (var item in dedupeList) {
      bool hasChanged = true;
      final oldData = existingItemsMap[item.id];

      if (oldData != null) {
        // 检测是否有实质性变更，如果没有则跳过审计和 Oplog
        hasChanged = _hasSubstantialChange(oldData, item.toJson(), [
          'content',
          'title',
          'remark',
          'is_completed',
          'is_deleted',
          'due_date',
          'group_id',
          'recurrence',
          'recurrence_series_id',
          'is_all_day',
          'reminder_minutes',
          'has_conflict',
          'conflict_data',
          'image_path',
          'original_text',
          'version',
          'updated_at',
        ]);
      }

      if (!isSyncSource && hasChanged) {
        final syncPayload = _stripClientOnlyConflictForSync(item.toJson());
        if (item.isDeleted && _recurrenceDedupeTombstoneIds.contains(item.id)) {
          syncPayload['_recurrence_delete_reason'] = 'dedupe';
        }
        // 记录审计日志 (传入已有的 oldData 避免再次查询)
        unawaited(_recordLocalAuditOptimized(
            'todos', item.id, item.toJson(), item.teamUuid, oldData));

        batch.insert('op_logs', {
          'op_type': 'UPSERT',
          'target_table': 'todos',
          'target_uuid': item.id,
          'data_json': jsonEncode(syncPayload),
          'timestamp': DateTime.now().millisecondsSinceEpoch,
          'is_synced': 0,
          'sync_error': '',
        });
        //if (!isSyncSource) {
        //debugPrint(
        //    '🧪 [SyncDiag][oplog] CREATE UUID=${item.id} isDone=${item.isDone} is_completed=${item.isDone ? 1 : 0} collabType=${item.collabType}');
        //}
      }

      if (hasChanged || oldData == null) {
        final previousScheduleData = existingScheduleItemsMap[item.id];
        if (_requiresScheduleConflictRefresh(item, previousScheduleData)) {
          affectedScheduleConflictDays.addAll(
            _scheduleConflictDayKeysFor(
              item,
              previousData: previousScheduleData,
            ),
          );
        }
        // 🚀 同步写入时，如果有待同步 oplog，保留 DB 中的 is_completed，
        // 防止 syncData 的 saveTodos 覆盖用户本地修改（force-flush 写入的值）
        final int isCompleted;
        if (isSyncSource && existingCompletionMap.containsKey(item.id)) {
          isCompleted = existingCompletionMap[item.id]!;
          /*debugPrint(
              '🧪 [SyncDiag][saveTodos-sync] PRESERVED UUID=${item.id} isCompleted=$isCompleted');
              */
        } else {
          isCompleted = item.isDone ? 1 : 0;
          if (isSyncSource) {
            /*debugPrint(
                '🧪 [SyncDiag][saveTodos-sync] OVERWRITE UUID=${item.id} isCompleted=$isCompleted (from merge)');
          */
          }
        }
        batch.insert(
            'todos',
            {
              'uuid': item.id,
              'content': item.title,
              'remark': item.remark,
              'team_uuid': item.teamUuid,
              'team_name': item.teamName,
              'creator_id': item.creatorId,
              'creator_name': item.creatorName,
              'is_completed': isCompleted,
              'is_deleted': item.isDeleted ? 1 : 0,
              'version': item.version,
              'due_date': item.dueDate?.millisecondsSinceEpoch ?? 0,
              'group_id': item.groupId,
              'created_date': item.createdDate ?? item.createdAt,
              'created_at': item.createdAt,
              'updated_at': item.updatedAt,
              'collab_type': item.collabType,
              'recurrence': _normalizedRecurrenceIndex(item),
              'recurrence_series_id': item.recurrenceSeriesId,
              'custom_interval_days': _normalizedCustomIntervalDays(item),
              'recurrence_end_date':
                  item.recurrenceEndDate?.millisecondsSinceEpoch ?? 0,
              'reminder_minutes': item.reminderMinutes ?? -1,
              'is_all_day': item.isAllDay ? 1 : 0,
              'has_conflict': item.hasConflict ? 1 : 0,
              'image_path': item.imagePath,
              'original_text': item.originalText,
              'conflict_data': item.serverVersionData != null
                  ? jsonEncode(item.serverVersionData)
                  : null,
            },
            conflictAlgorithm: ConflictAlgorithm.replace);
      }
    }

    if (dedupeList.isNotEmpty) {
      await batch.commit(noResult: true);
      _inflightTodoRequests.clear();

      // 🚀 针对各自独立团队待办（collabType == 1），同步写入 todo_completions
      if (!isSyncSource) {
        try {
          final localPrefs = await prefs;
          final int userId = localPrefs.getInt('current_user_id') ?? 0;
          if (userId > 0) {
            final compBatch = db.batch();
            for (var item in dedupeList) {
              if (item.collabType == 1) {
                compBatch.insert(
                    'todo_completions',
                    {
                      'todo_uuid': item.id,
                      'user_id': userId,
                      'is_completed': item.isDone ? 1 : 0,
                      'updated_at': DateTime.now().millisecondsSinceEpoch,
                    },
                    conflictAlgorithm: ConflictAlgorithm.replace);
              }
            }
            await compBatch.commit(noResult: true);
          }
        } catch (e) {
          debugPrint("⚠️ StorageService: 写入本地 todo_completions 状态失败: $e");
        }
      }
    }

    if (recomputeScheduleConflicts && affectedScheduleConflictDays.isNotEmpty) {
      await _refreshTodoScheduleConflicts(
        username,
        affectedDayKeys: affectedScheduleConflictDays,
        affectedTodoIds: dedupeList.map((item) => item.id).toSet(),
      );
    }

    if (sync) requestSync(username);
    Future.microtask(() => _syncTodosToBand(dedupeList));
    triggerRefresh(const {DataRefreshDomain.todos});
  }

  bool _hasSubstantialChange(Map<String, dynamic> before,
      Map<String, dynamic> after, List<String> fields) {
    for (var field in fields) {
      var valA = after[field];
      var valB = before[field];

      // 归一化处理
      bool isAEmpty = valA == null ||
          valA == 0 ||
          valA == "" ||
          valA == false ||
          (field == 'reminder_minutes' && valA == -1);
      bool isBEmpty = valB == null ||
          valB == 0 ||
          valB == "" ||
          valB == false ||
          (field == 'reminder_minutes' && valB == -1);

      if (isAEmpty && isBEmpty) continue;
      if (isAEmpty || isBEmpty) return true;
      if (valA != valB) return true;
    }
    return false;
  }

  Future<void> _refreshTodoScheduleConflicts(
    String username, {
    Set<String>? affectedDayKeys,
    Set<String>? affectedTodoIds,
  }) async {
    try {
      final ids = affectedTodoIds ?? const <String>{};
      final todos = await _loadScheduleConflictCandidates(
        username,
        affectedDayKeys: affectedDayKeys,
        affectedTodoIds: ids,
      );
      if (todos.isEmpty) return;
      final beforeConflictState = <String, String>{
        for (final todo in todos)
          todo.id: '${todo.hasConflict}:${jsonEncode(todo.serverVersionData)}',
      };
      if (!await getConflictDetectionEnabled()) {
        _clearLocalTodoScheduleConflicts(todos);
        final changedTodos = todos
            .where((todo) =>
                beforeConflictState[todo.id] !=
                '${todo.hasConflict}:${jsonEncode(todo.serverVersionData)}')
            .toList();
        if (changedTodos.isNotEmpty) {
          await saveTodos(
            username,
            changedTodos,
            sync: false,
            isSyncSource: true,
            recomputeScheduleConflicts: false,
          );
        }
        return;
      }
      final ignoredKeys = await _getIgnoredScheduleConflictKeys(username);
      _recomputeLocalTodoScheduleConflicts(todos,
          ignoredScheduleConflictKeys: ignoredKeys);
      final changedTodos = todos
          .where((todo) =>
              beforeConflictState[todo.id] !=
              '${todo.hasConflict}:${jsonEncode(todo.serverVersionData)}')
          .toList();
      if (changedTodos.isNotEmpty) {
        await saveTodos(
          username,
          changedTodos,
          sync: false,
          isSyncSource: true,
          recomputeScheduleConflicts: false,
        );
      }
    } catch (e) {
      debugPrint('refreshTodoScheduleConflicts error: $e');
    }
  }

  Future<List<TodoItem>> _loadScheduleConflictCandidates(
    String username, {
    Set<String>? affectedDayKeys,
    Set<String> affectedTodoIds = const <String>{},
  }) async {
    if (affectedDayKeys == null) {
      return getTodos(username, includeDeleted: true);
    }

    final rowsById = <String, Map<String, dynamic>>{};
    if (affectedTodoIds.isNotEmpty) {
      final rows = await DatabaseHelper.instance.getTodoMaps(
        includeDeleted: true,
        uuids: affectedTodoIds.toList(),
        includeConflictData: true,
      );
      for (final row in rows) {
        rowsById[row['uuid'].toString()] = row;
      }
    }

    for (final dayKey in affectedDayKeys) {
      final day = DateTime.tryParse(dayKey);
      if (day == null) continue;
      final startMs = day.millisecondsSinceEpoch;
      final endMs = day.add(const Duration(days: 1)).millisecondsSinceEpoch;
      final rows = await DatabaseHelper.instance.getTodoMaps(
        includeDeleted: true,
        includeConflictData: true,
        where: '(t.created_date >= $startMs AND t.created_date < $endMs) '
            'OR (t.due_date >= $startMs AND t.due_date < $endMs)',
      );
      for (final row in rows) {
        rowsById[row['uuid'].toString()] = row;
      }
    }

    return rowsById.values.map(TodoItem.fromSql).toList();
  }

  bool _requiresScheduleConflictRefresh(
    TodoItem item,
    Map<String, dynamic>? previousData,
  ) {
    if (previousData == null) {
      return _scheduleConflictDayKeysFor(item).isNotEmpty;
    }
    final previousStart = _parseMillis(
      previousData['created_date'] ?? previousData['createdDate'],
    );
    final previousEnd = _parseMillis(
      previousData['due_date'] ?? previousData['dueDate'],
    );
    final previousAllDay =
        previousData['is_all_day'] == 1 || previousData['is_all_day'] == true;
    final previousDeleted =
        previousData['is_deleted'] == 1 || previousData['is_deleted'] == true;
    return previousStart != (item.createdDate ?? item.createdAt) ||
        previousEnd != item.dueDate?.millisecondsSinceEpoch ||
        previousAllDay != item.isAllDay ||
        previousDeleted != item.isDeleted ||
        previousData['content']?.toString() != item.title ||
        previousData['team_uuid']?.toString() != item.teamUuid?.toString() ||
        previousData['recurrence_series_id']?.toString() !=
            item.recurrenceSeriesId?.toString();
  }

  Set<String> _scheduleConflictDayKeysFor(
    TodoItem item, {
    Map<String, dynamic>? previousData,
  }) {
    final days = <String>{};

    void addRange(int? startMs, int? endMs, bool isAllDay) {
      if (isAllDay || startMs == null || endMs == null) return;
      if (startMs <= 0 || endMs <= 0 || startMs >= endMs) return;
      final startDay = _localDayKey(startMs);
      if (startDay == _localDayKey(endMs)) days.add(startDay);
    }

    addRange(
      item.createdDate ?? item.createdAt,
      item.dueDate?.millisecondsSinceEpoch,
      item.isAllDay,
    );
    if (previousData != null) {
      addRange(
        _parseMillis(
            previousData['created_date'] ?? previousData['createdDate']),
        _parseMillis(previousData['due_date'] ?? previousData['dueDate']),
        previousData['is_all_day'] == 1 || previousData['is_all_day'] == true,
      );
    }
    return days;
  }

  Set<String> _scheduleConflictDayKeysForRow(Map<String, dynamic> row) {
    if (row['is_all_day'] == 1 || row['is_all_day'] == true) {
      return const <String>{};
    }
    final startMs = _parseMillis(row['created_date'] ?? row['created_at']);
    final endMs = _parseMillis(row['due_date']);
    if (startMs == null || endMs == null || startMs <= 0 || endMs <= startMs) {
      return const <String>{};
    }
    final startDay = _localDayKey(startMs);
    return startDay == _localDayKey(endMs) ? {startDay} : const <String>{};
  }

  Future<Map<String, int>> scanAllTodoConflicts(String username) async {
    final allTodos = await getTodos(username, includeDeleted: true);
    if (!await getConflictDetectionEnabled()) {
      final changed = _clearLocalTodoScheduleConflicts(allTodos);
      try {
        if (changed) {
          await saveTodos(
            username,
            allTodos,
            sync: false,
            isSyncSource: true,
            recomputeScheduleConflicts: false,
          );
        } else {
          triggerRefresh(const {DataRefreshDomain.todos});
        }
      } finally {
        conflictScanNotifier.value = {
          'isScanning': false,
          'progress': 100,
          'current': allTodos.length,
          'total': allTodos.length,
          'message': '冲突检测已关闭',
        };
      }
      return {
        'total': 0,
        'personal_personal': 0,
        'personal_team': 0,
        'team_team': 0,
      };
    }
    final ignoredKeys = await _getIgnoredScheduleConflictKeys(username);
    final changed = _recomputeLocalTodoScheduleConflicts(
      allTodos,
      ignoredScheduleConflictKeys: ignoredKeys,
      onProgress: (current, total, message) {
        final progress = total <= 0 ? 0 : ((current / total) * 100).round();
        conflictScanNotifier.value = {
          'isScanning': true,
          'progress': progress.clamp(0, 100),
          'current': current,
          'total': total,
          'message': message,
        };
      },
    );

    try {
      if (changed) {
        await saveTodos(
          username,
          allTodos,
          sync: false,
          isSyncSource: true,
          recomputeScheduleConflicts: false,
        );
      } else {
        triggerRefresh(const {DataRefreshDomain.todos});
      }
    } finally {
      conflictScanNotifier.value = {
        'isScanning': false,
        'progress': 100,
        'current': allTodos.length,
        'total': allTodos.length,
        'message': '扫描完成',
      };
    }

    int total = 0;
    int personalPersonal = 0;
    int personalTeam = 0;
    int teamTeam = 0;

    for (final todo in allTodos) {
      if (todo.isDeleted) continue;
      if (!todo.hasConflict) continue;
      final data = todo.serverVersionData;
      if (!_isLocalScheduleConflict(data)) continue;
      total++;
      switch (data?['relation_type']) {
        case 'personal_personal':
          personalPersonal++;
          break;
        case 'personal_team':
          personalTeam++;
          break;
        case 'team_team':
          teamTeam++;
          break;
      }
    }

    return {
      'total': total,
      'personal_personal': personalPersonal,
      'personal_team': personalTeam,
      'team_team': teamTeam,
    };
  }

  Future<void> clearLocalTodoScheduleConflicts(String username) async {
    final allTodos = await getTodos(username, includeDeleted: true);
    if (!_clearLocalTodoScheduleConflicts(allTodos)) return;
    await saveTodos(
      username,
      allTodos,
      sync: false,
      isSyncSource: true,
      recomputeScheduleConflicts: false,
    );
  }

  Future<void> ignoreLocalScheduleConflict(
      String username, TodoItem item) async {
    final data = item.serverVersionData;
    if (!_isLocalScheduleConflict(data)) return;

    final ignoredKeys = await _getIgnoredScheduleConflictKeys(username);
    final startMs =
        _parseMillis(data?['start_time']) ?? item.createdDate ?? item.createdAt;
    final endMs =
        _parseMillis(data?['end_time']) ?? item.dueDate?.millisecondsSinceEpoch;
    if (startMs <= 0 || endMs == null || endMs <= 0) return;

    final peers = data?['conflict_with'];
    if (peers is List) {
      for (final peer in peers) {
        if (peer is! Map) continue;
        final peerId = (peer['uuid'] ?? peer['id'] ?? '').toString();
        final peerStart = _parseMillis(peer['start_time']);
        final peerEnd = _parseMillis(peer['end_time']);
        if (peerId.isEmpty || peerStart == null || peerEnd == null) continue;
        ignoredKeys.add(_scheduleConflictPairKey(
          item.id,
          startMs,
          endMs,
          peerId,
          peerStart,
          peerEnd,
        ));
      }
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _scopedKey(keyIgnoredScheduleConflicts, username),
      ignoredKeys.toList()..sort(),
    );

    final allTodos = await getTodos(username, includeDeleted: true);
    var changed = false;
    for (final todo in allTodos) {
      final conflictData = todo.serverVersionData;
      if (!_isLocalScheduleConflict(conflictData)) continue;

      if (todo.id == item.id) {
        todo.hasConflict = false;
        todo.serverVersionData = null;
        changed = true;
        continue;
      }

      final peers = conflictData?['conflict_with'];
      if (peers is! List) continue;
      final containsIgnoredItem = peers.any((peer) {
        if (peer is! Map) return false;
        final peerId = (peer['uuid'] ?? peer['id'] ?? '').toString();
        return peerId == item.id;
      });
      if (containsIgnoredItem) {
        todo.hasConflict = false;
        todo.serverVersionData = null;
        changed = true;
      }
    }

    if (changed) {
      _recomputeLocalTodoScheduleConflicts(
        allTodos,
        ignoredScheduleConflictKeys: ignoredKeys,
      );
      await saveTodos(
        username,
        allTodos,
        sync: false,
        isSyncSource: true,
        recomputeScheduleConflicts: false,
      );
    }
  }

  Future<Set<String>> _getIgnoredScheduleConflictKeys(String username) async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList(
              _scopedKey(keyIgnoredScheduleConflicts, username),
            ) ??
            const <String>[])
        .toSet();
  }

  Future<void> _recordLocalAuditOptimized(
      String table,
      String uuid,
      Map<String, dynamic> afterData,
      String? teamUuid,
      Map<String, dynamic>? existingData) async {
    try {
      if (existingData == null) {
        await DatabaseHelper.instance.insertLocalAuditLog(
          userId: ApiService.currentUserId,
          targetTable: table,
          targetUuid: uuid,
          opType: 'INSERT',
          beforeData: null,
          afterData: afterData,
          teamUuid: teamUuid,
          operatorName: '本人(离线)',
        );
        return;
      }

      // 已经在外部做过实质性变更检测了，此处直接记录
      await DatabaseHelper.instance.insertLocalAuditLog(
        userId: ApiService.currentUserId,
        targetTable: table,
        targetUuid: uuid,
        opType: 'UPDATE',
        beforeData: existingData,
        afterData: afterData,
        teamUuid: teamUuid,
        operatorName: '本人(离线)',
      );
    } catch (e) {
      debugPrint("⚠️ 记录本地审计失败: $e");
    }
  }

  Future<void> _recordLocalAudit(String table, String uuid,
      Map<String, dynamic> afterData, String? teamUuid) async {
    try {
      final db = await DatabaseHelper.instance.database;
      // 1. 获取旧数据快照
      final List<Map<String, dynamic>> existing =
          await db.query(table, where: 'uuid = ?', whereArgs: [uuid]);
      if (existing.isEmpty) {
        // 新增操作，直接记录
        await DatabaseHelper.instance.insertLocalAuditLog(
          userId: ApiService.currentUserId,
          targetTable: table,
          targetUuid: uuid,
          opType: 'INSERT',
          beforeData: null,
          afterData: afterData,
          teamUuid: teamUuid,
          operatorName: '本人(离线)',
        );
        return;
      }

      Map<String, dynamic> beforeData =
          Map<String, dynamic>.from(existing.first);

      // 🚀 核心优化：实质性变更检测
      // 排除掉 version, updated_at 等会自动变动的字段，只对比业务字段
      bool hasSubstantialChange = false;
      final businessFields = [
        'content',
        'title',
        'remark',
        'is_completed',
        'is_deleted',
        'due_date',
        'target_time',
        'group_id',
        'category_id',
        'recurrence',
        'recurrence_series_id',
        'is_all_day',
        'reminder_minutes',
        'recurrence_end_date',
        'custom_interval_days'
      ];

      for (var field in businessFields) {
        if (afterData.containsKey(field) || beforeData.containsKey(field)) {
          var valA = afterData[field];
          var valB = beforeData[field];

          // 🚀 核心修复：全面的值归一化处理
          // 处理 null 和 0/""/"false" 的等价性
          // 特别处理 reminder_minutes: -1 和 null 的等价性
          bool isAEmpty = valA == null ||
              valA == 0 ||
              valA == "" ||
              valA == false ||
              (field == 'reminder_minutes' && valA == -1);
          bool isBEmpty = valB == null ||
              valB == 0 ||
              valB == "" ||
              valB == false ||
              (field == 'reminder_minutes' && valB == -1);

          if (isAEmpty && isBEmpty) continue; // 两个都是"空"，认为相同
          if (isAEmpty || isBEmpty) {
            // 一个是空，一个不是空，判断为有变更（除非都是0的情况）
            if ((valA == 0 || valB == 0) && (valA ?? valB) == 0) continue;
            hasSubstantialChange = true;
            break;
          }

          // 两个都不是"空"，直接比较
          if (valA != valB) {
            hasSubstantialChange = true;
            break;
          }
        }
      }

      if (!hasSubstantialChange) return; // 没有实质性变化，不记录日志

      Map<String, dynamic> enrichedAfter = Map<String, dynamic>.from(afterData);

      // 🚀 核心优化：本地名称解析 - 让离线历史也显示人类可读的名称
      Future<String?> lookupName(String targetTable, String? targetUuid) async {
        if (targetUuid == null || targetUuid.isEmpty) return null;
        try {
          final List<Map<String, dynamic>> res = await db.query(targetTable,
              columns: ['name'], where: 'uuid = ?', whereArgs: [targetUuid]);
          return res.isNotEmpty ? res.first['name'] as String? : null;
        } catch (_) {
          return null;
        }
      }

      if (beforeData['group_id'] != null) {
        beforeData['group_name'] =
            await lookupName('todo_groups', beforeData['group_id']);
      }
      if (beforeData['team_uuid'] != null) {
        beforeData['team_name'] =
            await lookupName('teams', beforeData['team_uuid']);
      }
      if (enrichedAfter['group_id'] != null) {
        enrichedAfter['group_name'] =
            await lookupName('todo_groups', enrichedAfter['group_id']);
      }
      if (enrichedAfter['team_uuid'] != null) {
        enrichedAfter['team_name'] =
            await lookupName('teams', enrichedAfter['team_uuid']);
      }

      // 2. 存入本地审计表
      await DatabaseHelper.instance.insertLocalAuditLog(
        userId: ApiService.currentUserId,
        targetTable: table,
        targetUuid: uuid,
        opType: 'UPDATE',
        beforeData: beforeData,
        afterData: enrichedAfter,
        teamUuid: teamUuid,
        operatorName: '本人(离线)',
      );
    } catch (e) {
      debugPrint("⚠️ 记录本地审计失败: $e");
    }
  }

  Future<void> _syncTodosToBand(List<TodoItem> items) async {
    if (!BandSyncService.isInitialized || !BandSyncService.isConnected) return;
    try {
      final activeTodos = items.where((t) => !t.isDeleted).map((t) {
        final data = t.toJson();
        data.remove('image_path');
        data.remove('imagePath');
        data.remove('original_text');
        data.remove('originalText');
        data.remove('conflict_data');
        return data;
      }).toList();
      await BandSyncService.syncTodos(activeTodos);
    } catch (_) {}
  }

  Future<void> updateSingleTodo(String username, TodoItem item,
      {bool sync = true}) async {
    if (item.recurrence != RecurrenceType.none &&
        (item.recurrenceSeriesId == null || item.recurrenceSeriesId!.isEmpty)) {
      item.recurrenceSeriesId = item.id;
    }
    // 1. 记录本地审计日志 (必须在更新前，因为需要获取旧快照)
    await _recordLocalAudit('todos', item.id, item.toJson(), item.teamUuid);

    final db = await DatabaseHelper.instance.database;
    final previousRows = await db.query(
      'todos',
      where: 'uuid = ?',
      whereArgs: [item.id],
      limit: 1,
    );
    final previousData = previousRows.isEmpty
        ? null
        : Map<String, dynamic>.from(previousRows.first);

    // 2. 同步更新 SQLite
    await db.insert(
        'todos',
        {
          'uuid': item.id,
          'content': item.title,
          'remark': item.remark,
          'team_uuid': item.teamUuid,
          'team_name': item.teamName,
          'creator_id': item.creatorId,
          'creator_name': item.creatorName,
          'is_completed': item.isDone ? 1 : 0,
          'is_deleted': item.isDeleted ? 1 : 0,
          'version': item.version,
          'updated_at': item.updatedAt,
          'created_at': item.createdAt,
          // 🚀 核心防御：0 兜底
          'due_date': item.dueDate?.millisecondsSinceEpoch ?? 0,
          'group_id': item.groupId,
          'created_date': item.createdDate,
          'collab_type': item.collabType,
          'recurrence': _normalizedRecurrenceIndex(item),
          'recurrence_series_id': item.recurrenceSeriesId,
          'custom_interval_days': _normalizedCustomIntervalDays(item),
          // 🚀 核心防御：0 兜底
          'recurrence_end_date':
              item.recurrenceEndDate?.millisecondsSinceEpoch ?? 0,
          'reminder_minutes': item.reminderMinutes ?? -1,
          'is_all_day': item.isAllDay ? 1 : 0,
          'has_conflict': item.hasConflict ? 1 : 0,
          'conflict_data': item.serverVersionData != null
              ? jsonEncode(item.serverVersionData)
              : null,
          'image_path': item.imagePath,
          'original_text': item.originalText,
        },
        conflictAlgorithm: ConflictAlgorithm.replace);

    // 2.1 针对各自独立团队待办（collabType == 1），同步在本地 todo_completions 表中为当前用户写入/更新完成状态
    if (item.collabType == 1) {
      try {
        final localPrefs = await prefs;
        final int userId = localPrefs.getInt('current_user_id') ?? 0;
        if (userId > 0) {
          await db.insert(
              'todo_completions',
              {
                'todo_uuid': item.id,
                'user_id': userId,
                'is_completed': item.isDone ? 1 : 0,
                'updated_at': DateTime.now().millisecondsSinceEpoch,
              },
              conflictAlgorithm: ConflictAlgorithm.replace);
        }
      } catch (e) {
        debugPrint("⚠️ StorageService: 写入本地 todo_completions 状态失败: $e");
      }
    }

    // 3. 补齐 Oplog，确保离线更新能被同步
    await db.insert('op_logs', {
      'op_type': 'UPSERT',
      'target_table': 'todos',
      'target_uuid': item.id,
      'data_json': jsonEncode(_stripClientOnlyConflictForSync(item.toJson())),
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'is_synced': 0,
      'sync_error': '',
    });

    // 不再维护超大的 SharedPreferences Todo 镜像，避免 Android 插件层 OOM
    await _clearTodoPrefsMirror(username);

    if (_requiresScheduleConflictRefresh(item, previousData)) {
      final affectedDayKeys =
          _scheduleConflictDayKeysFor(item, previousData: previousData);
      if (affectedDayKeys.isNotEmpty) {
        await _refreshTodoScheduleConflicts(
          username,
          affectedDayKeys: affectedDayKeys,
          affectedTodoIds: {item.id},
        );
      }
    }

    if (sync) requestSync(username);
    triggerRefresh(const {DataRefreshDomain.todos});
  }

  Future<void> permanentlyDeleteTodo(String username, String uuid) async {
    final db = await DatabaseHelper.instance.database;
    final existingRows = await db.query(
      'todos',
      columns: const ['created_date', 'created_at', 'due_date', 'is_all_day'],
      where: 'uuid = ?',
      whereArgs: [uuid],
      limit: 1,
    );
    final affectedDays = existingRows.isEmpty
        ? <String>{}
        : _scheduleConflictDayKeysForRow(existingRows.first);
    await db.delete('todos', where: 'uuid = ?', whereArgs: [uuid]);

    await _clearTodoPrefsMirror(username);

    // 记录删除操作到 Oplog (物理删除也需要同步给其它端)
    await db.insert('op_logs', {
      'op_type': 'DELETE',
      'target_table': 'todos',
      'target_uuid': uuid,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'is_synced': 0,
      'sync_error': '',
    });

    if (affectedDays.isNotEmpty) {
      await _refreshTodoScheduleConflicts(
        username,
        affectedDayKeys: affectedDays,
      );
    }
    triggerRefresh(const {DataRefreshDomain.todos});
  }

  Future<void> clearTodoRecycleBin(String username) async {
    final db = await DatabaseHelper.instance.database;

    // 1. 获取所有待删除的 UUID，用于记录 Oplog
    final List<Map<String, dynamic>> deletedItems = await db.query(
      'todos',
      columns: const [
        'uuid',
        'created_date',
        'created_at',
        'due_date',
        'is_all_day',
      ],
      where: 'is_deleted = 1',
    );
    final affectedDays = <String>{};
    for (final item in deletedItems) {
      affectedDays.addAll(_scheduleConflictDayKeysForRow(item));
    }

    final batch = db.batch();
    for (var item in deletedItems) {
      final uuid = item['uuid']?.toString();
      if (uuid == null) continue;
      batch.delete('todos', where: 'uuid = ?', whereArgs: [uuid]);
      batch.insert('op_logs', {
        'op_type': 'DELETE',
        'target_table': 'todos',
        'target_uuid': uuid,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'is_synced': 0,
        'sync_error': '',
      });
    }
    await batch.commit(noResult: true);

    await _clearTodoPrefsMirror(username);

    if (affectedDays.isNotEmpty) {
      await _refreshTodoScheduleConflicts(
        username,
        affectedDayKeys: affectedDays,
      );
    }
    triggerRefresh(const {DataRefreshDomain.todos});
  }

  bool _isHistoricalTodo(TodoItem todo, DateTime today) {
    if (!todo.isDone || todo.isDeleted) return false;

    if (todo.dueDate != null) {
      final due = todo.dueDate!;
      final dueDay = DateTime(due.year, due.month, due.day);
      return dueDay.isBefore(today);
    }

    final created = DateTime.fromMillisecondsSinceEpoch(
      todo.createdDate ?? todo.createdAt,
      isUtc: true,
    ).toLocal();
    final createdDay = DateTime(created.year, created.month, created.day);
    return createdDay.isBefore(today);
  }

  Future<int> clearHistoricalTodos(String username) async {
    final todayNow = DateTime.now();
    final today = DateTime(todayNow.year, todayNow.month, todayNow.day);
    final allTodos = await getTodos(username, includeDeleted: true);
    final historicalIds = allTodos
        .where((todo) => _isHistoricalTodo(todo, today))
        .map((todo) => todo.id)
        .toList();

    if (historicalIds.isEmpty) return 0;

    final db = await DatabaseHelper.instance.database;
    final now = DateTime.now().millisecondsSinceEpoch;
    final batch = db.batch();
    for (final uuid in historicalIds) {
      batch.delete('todo_completions',
          where: 'todo_uuid = ?', whereArgs: [uuid]);
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
    final db = await DatabaseHelper.instance.database;
    await db.delete('countdowns', where: 'uuid = ?', whereArgs: [uuid]);

    // 同步清理 Prefs 缓存
    final prefs = await SharedPreferences.getInstance();
    List<String> list = prefs.getStringList("${keyCountdowns}_$username") ?? [];
    list.removeWhere((jsonStr) {
      try {
        final map = jsonDecode(jsonStr);
        return map['id'] == uuid || map['uuid'] == uuid;
      } catch (_) {
        return false;
      }
    });
    await prefs.setStringList("${keyCountdowns}_$username", list);

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

  Future<List<TodoItem>> getTodos(String username,
      {bool includeDeleted = false, int? limit}) async {
    final requestKey = _todoRequestKey(
      username,
      includeDeleted: includeDeleted,
      limit: limit,
    );
    final inflight = _inflightTodoRequests[requestKey];
    if (inflight != null) {
      debugPrint("🔁 getTodos 复用进行中请求: $requestKey");
      final shared = await inflight;
      return _cloneTodoItems(shared);
    }

    final future = _getTodosInternal(
      username,
      includeDeleted: includeDeleted,
      limit: limit,
    );
    _inflightTodoRequests[requestKey] = future;

    try {
      final result = await future;
      return _cloneTodoItems(result);
    } finally {
      if (identical(_inflightTodoRequests[requestKey], future)) {
        _inflightTodoRequests.remove(requestKey);
      }
    }
  }

  Future<List<TodoItem>> _getTodosInternal(String username,
      {bool includeDeleted = false, int? limit}) async {
    final prefs = await StorageService.prefs;
    final startedAt = DateTime.now();
    // 🚀 Uni-Sync 安全方案：双轨读取 + 逃生通道
    try {
      final dbHelper = DatabaseHelper.instance;
      final db = await dbHelper.database;
      await _clearGhostConflictFlags(db);

      final migrationKey = "migration_marker_${username}_v4";
      bool alreadyMigrated = prefs.getBool(migrationKey) ?? false;

      if (alreadyMigrated) {
        await _clearTodoPrefsMirror(username);
      }

      // 🚀 核心补丁：清理先前版本迁移后遗留的超大数据 (解决 170MB+ 内存占用与启动卡顿)
      final String cleanupKey = "cleanup_done_${username}_v4_repair";
      if (alreadyMigrated && !(prefs.getBool(cleanupKey) ?? false)) {
        await prefs.remove("${keyTodos}_$username");
        await prefs.remove(keyTodos);
        await prefs.setBool(cleanupKey, true);
        debugPrint("🗑️ Todos 残留数据修复清理完成。");
      }

      if (!alreadyMigrated) {
        List<String> legacyJsonList =
            prefs.getStringList("${keyTodos}_$username") ?? [];
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
          await saveTodos(username, legacyItems,
              sync: false, isSyncSource: true);
          // 🚀 迁移成功后，必须物理清除 SharedPreferences 中的巨大 JSON 块
          // 否则 Android 的原生 SharedPreferences 会一直将此 170MB+ 的数据留在内存中导致 OOM
          await prefs.remove("${keyTodos}_$username");
          await prefs.remove(keyTodos);
          debugPrint("✅ 老数据增量迁移完成并已物理清理。");
        }
        await prefs.setBool(migrationKey, true);
      }

      List<Map<String, dynamic>> maps = await dbHelper.getTodoMaps(
        includeDeleted: includeDeleted,
        limit: limit,
        includeConflictData: true,
      );
      if (limit != null && maps.isNotEmpty) {
        final activeSeriesIds = maps
            .where((map) => (_parseNullableInt(map['recurrence']) ?? 0) != 0)
            .map((map) => map['recurrence_series_id']?.toString().trim())
            .whereType<String>()
            .where((seriesId) => seriesId.isNotEmpty)
            .toSet();
        if (activeSeriesIds.isNotEmpty) {
          final seriesMaps = await dbHelper.getTodoMaps(
            includeDeleted: includeDeleted,
            recurrenceSeriesIds: activeSeriesIds,
            includeConflictData: true,
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
      if (maps.isNotEmpty) {
        List<TodoItem> todos;
        // 🚀 性能优化：当待办数量较多时，使用 Isolate 解析，减少主线程解析耗时导致的 UI 卡顿
        if (maps.length > 50) {
          todos = await compute(_parseTodoItemsIsolate, maps);
        } else {
          todos = maps
              .map((m) => TodoItem(
                    id: m['uuid'],
                    title: m['content'] ?? '',
                    remark: m['remark'],
                    isDone: m['is_completed'] == 1,
                    isDeleted: m['is_deleted'] == 1,
                    version: m['version'] ?? 1,
                    updatedAt: m['updated_at'] ??
                        DateTime.now().millisecondsSinceEpoch,
                    createdAt: m['created_at'] ??
                        DateTime.now().millisecondsSinceEpoch,
                    createdDate: m['created_date'] != null
                        ? int.tryParse(m['created_date'].toString())
                        : null,
                    dueDate: (m['due_date'] != null &&
                            m['due_date'].toString() != '0' &&
                            m['due_date'].toString() != 'null' &&
                            m['due_date'].toString().isNotEmpty)
                        ? DateTime.fromMillisecondsSinceEpoch(
                            int.tryParse(m['due_date'].toString()) ?? 0)
                        : null,
                    teamUuid: m['team_uuid'],
                    teamName: m['team_name'],
                    creatorId: m['creator_id'],
                    creatorName: m['creator_name'],
                    groupId: m['group_id'],
                    collabType: m['collab_type'] ?? 0,
                    recurrence: RecurrenceType.values[
                        (_parseNullableInt(m['recurrence']) ?? 0)
                            .clamp(0, RecurrenceType.values.length - 1)],
                    recurrenceSeriesId: m['recurrence_series_id']?.toString(),
                    customIntervalDays:
                        _parseNullableInt(m['custom_interval_days']),
                    recurrenceEndDate: (m['recurrence_end_date'] != null &&
                            m['recurrence_end_date'].toString() != '0')
                        ? DateTime.fromMillisecondsSinceEpoch(
                            int.tryParse(m['recurrence_end_date'].toString()) ??
                                0)
                        : null,
                    reminderMinutes: (m['reminder_minutes'] != null &&
                            m['reminder_minutes'].toString() != '-1')
                        ? int.tryParse(m['reminder_minutes'].toString())
                        : null,
                    imagePath: m['image_path']?.toString(),
                    originalText: m['original_text']?.toString(),
                    isAllDay: m['is_all_day'] == 1 || m['is_all_day'] == true,
                    hasConflict:
                        m['has_conflict'] == 1 || m['has_conflict'] == true,
                    serverVersionData: m['conflict_data'] != null
                        ? (m['conflict_data'] is String
                            ? Map<String, dynamic>.from(
                                jsonDecode(m['conflict_data']))
                            : Map<String, dynamic>.from(m['conflict_data']))
                        : null,
                  ))
              .toList();
        }
        final handledTodos = await _handleRecurrenceLogic(username, todos);
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
    List<String> list = prefs.getStringList("${keyTodos}_$username") ?? [];
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
    final handledLegacyTodos =
        await _handleRecurrenceLogic(username, legacyTodos);
    Iterable<TodoItem> filtered = handledLegacyTodos;
    if (!includeDeleted) {
      filtered = filtered.where((todo) => !todo.isDeleted);
    }
    if (limit != null && limit >= 0) {
      filtered = filtered.take(limit);
    }
    final result = filtered.toList();
    debugPrint(
        "📦 getTodos(Prefs Fallback) 完成: count=${result.length}, includeDeleted=$includeDeleted, limit=$limit, cost=${DateTime.now().difference(startedAt).inMilliseconds}ms");
    return result;
  }

  Future<void> clearTeamItems(String teamUuid) async {
    final db = await DatabaseHelper.instance.database;
    final now = DateTime.now().millisecondsSinceEpoch;

    // 1. 软删除 (标记 isDeleted，通过同步传播到服务器)
    await db.rawUpdate(
        "UPDATE todos SET is_deleted = 1, version = version + 1, updated_at = ? WHERE team_uuid = ? AND is_deleted = 0",
        [now, teamUuid]);
    await db.rawUpdate(
        "UPDATE todo_groups SET is_deleted = 1, version = version + 1, updated_at = ? WHERE team_uuid = ? AND is_deleted = 0",
        [now, teamUuid]);
    await db.rawUpdate(
        "UPDATE countdowns SET is_deleted = 1, version = version + 1, updated_at = ? WHERE team_uuid = ? AND is_deleted = 0",
        [now, teamUuid]);
    await db.rawUpdate(
        "UPDATE time_logs SET is_deleted = 1, version = version + 1, updated_at = ? WHERE team_uuid = ? AND is_deleted = 0",
        [now, teamUuid]);
    await db.rawUpdate(
        "UPDATE courses SET is_deleted = 1, version = version + 1, updated_at = ? WHERE team_uuid = ? AND is_deleted = 0",
        [now, teamUuid]);
    await db.rawUpdate(
        "UPDATE fixed_schedules SET is_deleted = 1, version = version + 1, updated_at = ? WHERE team_uuid = ? AND is_deleted = 0",
        [now, teamUuid]);
    // 规划块本身不保存 team_uuid，需通过关联待办级联清理；否则退出团队后
    // 仍会在首页计划区看到已经失去权限的团队安排。
    await db.rawUpdate('''UPDATE todo_plan_blocks
           SET is_deleted = 1, version = version + 1, updated_at = ?
           WHERE todo_uuid IN (
             SELECT uuid FROM todos WHERE team_uuid = ?
           ) AND is_deleted = 0''', [now, teamUuid]);

    await db.delete(
      'todo_completions',
      where: 'todo_uuid IN (SELECT uuid FROM todos WHERE team_uuid = ?)',
      whereArgs: [teamUuid],
    );

    // 🚀 关键：为软删除的项创建 op_log，使同步引擎能将删除传播到服务端
    final deletedTodos = await db.query('todos',
        columns: ['uuid', 'version', 'updated_at'],
        where: 'team_uuid = ? AND is_deleted = 1 AND updated_at = ?',
        whereArgs: [teamUuid, now]);
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
    final deletedGroups = await db.query('todo_groups',
        columns: ['uuid', 'version', 'updated_at'],
        where: 'team_uuid = ? AND is_deleted = 1 AND updated_at = ?',
        whereArgs: [teamUuid, now]);
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
    final deletedCountdowns = await db.query('countdowns',
        columns: ['uuid', 'version', 'updated_at'],
        where: 'team_uuid = ? AND is_deleted = 1 AND updated_at = ?',
        whereArgs: [teamUuid, now]);
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
    final deletedTimeLogs = await db.query('time_logs',
        columns: ['uuid', 'version', 'updated_at'],
        where: 'team_uuid = ? AND is_deleted = 1 AND updated_at = ?',
        whereArgs: [teamUuid, now]);
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
    final deletedPlanBlocks = await db.query('todo_plan_blocks',
        columns: ['uuid', 'version', 'updated_at'],
        where: '''todo_uuid IN (
                   SELECT uuid FROM todos WHERE team_uuid = ?
                 ) AND is_deleted = 1 AND updated_at = ?''',
        whereArgs: [teamUuid, now]);
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

  Future<List<TodoItem>> _handleRecurrenceLogic(
      String username, List<TodoItem> todos) async {
    final today = DateTime.now();
    final todayKey = '${today.year}-${today.month}-${today.day}';

    if (_lastRecurrenceCheckDate != todayKey) {
      _lastRecurrenceCheckDate = todayKey;
      _recurrenceCheckCache.clear();
    }

    final cacheKey = 'recurrence_instances_v4_$username';
    if (_recurrenceCheckCache.containsKey(cacheKey) || _isCheckingRecurrence) {
      return todos;
    }

    _isCheckingRecurrence = true;

    try {
      bool needSave = false;
      if (_deduplicatePersistedRecurrenceOccurrences(todos)) {
        needSave = true;
      }
      final List<TodoItem> generatedOccurrences = [];
      final Set<String> generatedRecurrenceConflictKeys = {};
      final processedSeriesIds = <String>{};
      for (final todo in List<TodoItem>.from(todos)) {
        if (todo.isDeleted || todo.recurrence == RecurrenceType.none) continue;

        final hasSeriesId = todo.recurrenceSeriesId != null &&
            todo.recurrenceSeriesId!.isNotEmpty;
        final seriesId = hasSeriesId ? todo.recurrenceSeriesId! : todo.id;
        todo.recurrenceSeriesId = seriesId;
        if (!processedSeriesIds.add(seriesId)) continue;

        final DateTime baseLocal = _getRecurrenceBaseDate(todo);
        final DateTime baseDay =
            DateTime(baseLocal.year, baseLocal.month, baseLocal.day);
        final DateTime todayDay = DateTime(today.year, today.month, today.day);
        final rollOffsets = _recurrenceRollOffsets(todo, baseDay, todayDay);
        final recurrence = todo.recurrence;
        final recurrenceEndDay = todo.recurrenceEndDate == null
            ? null
            : DateTime(
                todo.recurrenceEndDate!.year,
                todo.recurrenceEndDate!.month,
                todo.recurrenceEndDate!.day,
              );
        final keepSeriesActive =
            recurrenceEndDay == null || !todayDay.isAfter(recurrenceEndDay);
        if (recurrenceEndDay != null) {
          // 结束日期可能只修改了当前锚点，或来自另一台设备的同步；不能
          // 依赖编辑页一定把所有未来实例一起带回来。存储层每次处理规则
          // 时都清理结束日期之后的旧实例，避免它们继续留在系列中，或在
          // 旧锚点仍存活时被再次生成。
          if (_pruneRecurrenceOccurrencesAfterEndDate(
            todos
                .where((occurrence) => occurrence.id != todo.id)
                .followedBy(generatedOccurrences),
            seriesId: seriesId,
            recurrenceEndDate: recurrenceEndDay,
          )) {
            needSave = true;
          }
        }
        final seriesChain = <TodoItem>[todo];
        var activeOccurrence = todo;
        var todoChanged = !hasSeriesId;

        for (var i = 0; i < rollOffsets.length; i++) {
          final result = _getOrCreateRecurrenceOccurrence(
            source: todo,
            rollByDays: rollOffsets[i],
            seriesId: seriesId,
            todos: todos,
            generatedOccurrences: generatedOccurrences,
          );
          final occurrence = result.occurrence;
          final targetRecurrence =
              i == rollOffsets.length - 1 && keepSeriesActive
                  ? recurrence
                  : RecurrenceType.none;
          if (occurrence.recurrence != targetRecurrence) {
            occurrence.recurrence = targetRecurrence;
            if (!result.isNew) occurrence.markAsChanged();
            needSave = true;
          }
          if (result.didChange) needSave = true;
          seriesChain.add(occurrence);
          activeOccurrence = occurrence;
        }

        final repairedPastOccurrences = _repairMissingPastRecurrenceOccurrences(
          ruleSource: todo,
          copySource: activeOccurrence,
          seriesId: seriesId,
          throughStartMs:
              activeOccurrence.createdDate ?? activeOccurrence.createdAt,
          todos: todos,
          generatedOccurrences: generatedOccurrences,
        );
        if (repairedPastOccurrences.isNotEmpty) {
          seriesChain.addAll(repairedPastOccurrences);
          needSave = true;
        }

        if (rollOffsets.isNotEmpty) {
          // 原实例保留自己的完成状态，当前日期对应实例接管循环锚点。
          todo.recurrence = RecurrenceType.none;
          todoChanged = true;
        }

        // 如果结束日期被改到了当前锚点之前，rollOffsets 为空，原有逻辑
        // 会错误地继续保留 recurrence，导致后续每次读取都把它当作活动规则。
        if (!keepSeriesActive && todo.recurrence != RecurrenceType.none) {
          todo.recurrence = RecurrenceType.none;
          todoChanged = true;
        }

        if (todoChanged) {
          todo.markAsChanged();
          needSave = true;
        }

        if (activeOccurrence.recurrence != RecurrenceType.none) {
          final activeBase = _getRecurrenceBaseDate(activeOccurrence);
          final futureOffsets = _futureRecurrenceRollOffsets(
            activeOccurrence,
            activeBase,
          );
          for (final offset in futureOffsets) {
            final result = _getOrCreateRecurrenceOccurrence(
              source: activeOccurrence,
              rollByDays: offset,
              seriesId: seriesId,
              todos: todos,
              generatedOccurrences: generatedOccurrences,
            );
            final occurrence = result.occurrence;
            if (occurrence.recurrence != RecurrenceType.none) {
              occurrence.recurrence = RecurrenceType.none;
              if (!result.isNew) occurrence.markAsChanged();
              needSave = true;
            }
            if (result.didChange) needSave = true;
            seriesChain.add(occurrence);
          }
        }

        final uniqueSeriesChain = <String, TodoItem>{
          for (final occurrence in seriesChain) occurrence.id: occurrence,
        }.values.toList();
        for (var i = 0; i < uniqueSeriesChain.length; i++) {
          for (var j = i + 1; j < uniqueSeriesChain.length; j++) {
            final conflictKey = _overlappingRecurrencePairKey(
              uniqueSeriesChain[i],
              uniqueSeriesChain[j],
            );
            if (conflictKey != null) {
              generatedRecurrenceConflictKeys.add(conflictKey);
            }
          }
        }
      }

      if (needSave) {
        todos.addAll(generatedOccurrences);
        if (generatedRecurrenceConflictKeys.isNotEmpty) {
          final ignoredKeys = await _getIgnoredScheduleConflictKeys(username)
            ..addAll(generatedRecurrenceConflictKeys);
          final prefs = await SharedPreferences.getInstance();
          await prefs.setStringList(
            _scopedKey(keyIgnoredScheduleConflicts, username),
            ignoredKeys.toList()..sort(),
          );
        }
        debugPrint("🚀 [Recurrence] 发现重复任务需要滚动，正在保存...");
        await saveTodos(username, todos, sync: true);
      }
      _recurrenceCheckCache[cacheKey] = true;
      _isCheckingRecurrence = false;
      return todos;
    } catch (e) {
      debugPrint("❌ [Recurrence] 逻辑异常: $e");
      _isCheckingRecurrence = false;
      return todos;
    }
  }

  DateTime _getRecurrenceBaseDate(TodoItem todo) {
    if (todo.createdDate != null) {
      return DateTime.fromMillisecondsSinceEpoch(todo.createdDate!, isUtc: true)
          .toLocal();
    }
    return todo.dueDate ??
        DateTime.fromMillisecondsSinceEpoch(todo.createdAt, isUtc: true)
            .toLocal();
  }

  List<int> _recurrenceRollOffsets(
    TodoItem todo,
    DateTime baseDay,
    DateTime todayDay,
  ) {
    var targetDay = todayDay;
    if (todo.recurrenceEndDate != null) {
      final end = todo.recurrenceEndDate!;
      final endDay = DateTime(end.year, end.month, end.day);
      if (endDay.isBefore(targetDay)) targetDay = endDay;
    }
    if (!targetDay.isAfter(baseDay)) return const [];

    final offsets = <int>[];
    final diffDays = targetDay.difference(baseDay).inDays;
    switch (todo.recurrence) {
      case RecurrenceType.daily:
        for (var day = 1; day <= diffDays; day++) {
          offsets.add(day);
        }
      case RecurrenceType.customDays:
        final interval = todo.customIntervalDays ?? 0;
        if (interval > 0) {
          for (var day = interval; day <= diffDays; day += interval) {
            offsets.add(day);
          }
        }
      case RecurrenceType.weekdays:
        for (var day = 1; day <= diffDays; day++) {
          final candidate = DateTime(
            baseDay.year,
            baseDay.month,
            baseDay.day + day,
          );
          if (candidate.weekday != DateTime.saturday &&
              candidate.weekday != DateTime.sunday) {
            offsets.add(day);
          }
        }
      case RecurrenceType.weekly:
        for (var day = 7; day <= diffDays; day += 7) {
          offsets.add(day);
        }
      case RecurrenceType.monthly:
        for (var month = 1;; month++) {
          final monthStart = DateTime(baseDay.year, baseDay.month + month);
          final lastDay =
              DateTime(monthStart.year, monthStart.month + 1, 0).day;
          final candidate = DateTime(
            monthStart.year,
            monthStart.month,
            baseDay.day.clamp(1, lastDay),
          );
          if (candidate.isAfter(targetDay)) break;
          offsets.add(candidate.difference(baseDay).inDays);
        }
      case RecurrenceType.yearly:
        for (var year = 1;; year++) {
          final targetYear = baseDay.year + year;
          final lastDay = DateTime(targetYear, baseDay.month + 1, 0).day;
          final candidate = DateTime(
            targetYear,
            baseDay.month,
            baseDay.day.clamp(1, lastDay),
          );
          if (candidate.isAfter(targetDay)) break;
          offsets.add(candidate.difference(baseDay).inDays);
        }
      case RecurrenceType.none:
        break;
    }

    // 防止长期未启动后一次性生成过量记录，同时优先保留最近周期。
    const maxBackfilledOccurrences = 90;
    if (offsets.length <= maxBackfilledOccurrences) return offsets;
    return offsets.sublist(offsets.length - maxBackfilledOccurrences);
  }

  List<int> recurrenceRollOffsetsForTest(
    TodoItem todo,
    DateTime baseDay,
    DateTime todayDay,
  ) =>
      _recurrenceRollOffsets(todo, baseDay, todayDay);
  List<TodoItem> futureRecurrenceOccurrencesForTest(
    TodoItem source,
    List<TodoItem> existing,
  ) {
    final generated = <TodoItem>[];
    final seriesId = source.recurrenceSeriesId ?? source.id;
    source.recurrenceSeriesId = seriesId;
    final base = _getRecurrenceBaseDate(source);
    for (final offset in _futureRecurrenceRollOffsets(source, base)) {
      final result = _getOrCreateRecurrenceOccurrence(
        source: source,
        rollByDays: offset,
        seriesId: seriesId,
        todos: existing,
        generatedOccurrences: generated,
      );
      result.occurrence.recurrence = RecurrenceType.none;
    }
    return generated;
  }

  List<TodoItem> repairMissingPastRecurrenceOccurrencesForTest(
    TodoItem active,
    List<TodoItem> existing,
  ) {
    final generated = <TodoItem>[];
    final seriesId = active.recurrenceSeriesId ?? active.id;
    active.recurrenceSeriesId = seriesId;
    return _repairMissingPastRecurrenceOccurrences(
      ruleSource: active,
      copySource: active,
      seriesId: seriesId,
      throughStartMs: active.createdDate ?? active.createdAt,
      todos: existing,
      generatedOccurrences: generated,
    );
  }

  bool pruneRecurrenceOccurrencesAfterEndDateForTest(
    List<TodoItem> todos, {
    required String seriesId,
    required DateTime recurrenceEndDate,
  }) =>
      _pruneRecurrenceOccurrencesAfterEndDate(
        todos,
        seriesId: seriesId,
        recurrenceEndDate: recurrenceEndDate,
      );

  String recurrenceOccurrenceIdForTest(
    String seriesId,
    int startMs,
  ) =>
      _recurrenceOccurrenceId(seriesId, startMs);
  bool deduplicatePersistedRecurrenceOccurrencesForTest(
    List<TodoItem> todos,
  ) =>
      _deduplicatePersistedRecurrenceOccurrences(todos);
  Future<int> mergeRecurrenceSeries(
    String username, {
    required String targetSeriesId,
    required Set<String> seriesIds,
  }) async {
    final todos = await getTodos(username, includeDeleted: true);
    final changedIds = _mergeRecurrenceSeries(
      todos,
      targetSeriesId: targetSeriesId,
      seriesIds: seriesIds,
    );
    if (changedIds.isEmpty) return 0;

    final changedItems =
        todos.where((todo) => changedIds.contains(todo.id)).toList();
    await saveTodos(
      username,
      changedItems,
      sync: true,
      recomputeScheduleConflicts: false,
    );
    await _refreshTodoScheduleConflicts(username);
    triggerRefresh(const {DataRefreshDomain.todos});
    return changedItems.length;
  }

  Set<String> mergeRecurrenceSeriesForTest(
    List<TodoItem> todos, {
    required String targetSeriesId,
    required Set<String> seriesIds,
  }) =>
      _mergeRecurrenceSeries(
        todos,
        targetSeriesId: targetSeriesId,
        seriesIds: seriesIds,
      );
  Set<String> _mergeRecurrenceSeries(
    List<TodoItem> todos, {
    required String targetSeriesId,
    required Set<String> seriesIds,
  }) {
    final selectedSeriesIds = <String>{...seriesIds, targetSeriesId}
      ..removeWhere((seriesId) => seriesId.trim().isEmpty);
    final participating = todos
        .where((todo) =>
            todo.recurrenceSeriesId != null &&
            selectedSeriesIds.contains(todo.recurrenceSeriesId))
        .toList();
    final activeSeriesIds = participating
        .where((todo) => !todo.isDeleted)
        .map((todo) => todo.recurrenceSeriesId)
        .whereType<String>()
        .toSet();
    if (activeSeriesIds.length < 2 ||
        !activeSeriesIds.contains(targetSeriesId)) {
      return <String>{};
    }

    TodoItem? canonicalActive;
    final activeRules = participating
        .where(
            (todo) => !todo.isDeleted && todo.recurrence != RecurrenceType.none)
        .toList()
      ..sort((a, b) {
        final startCompare = (b.createdDate ?? b.createdAt)
            .compareTo(a.createdDate ?? a.createdAt);
        if (startCompare != 0) return startCompare;
        return b.version.compareTo(a.version);
      });
    for (final todo in activeRules) {
      if (todo.recurrenceSeriesId == targetSeriesId) {
        canonicalActive = todo;
        break;
      }
    }
    canonicalActive ??= activeRules.isEmpty ? null : activeRules.first;

    final versionsBefore = {
      for (final todo in participating) todo.id: todo.version,
    };
    final fieldChangedIds = <String>{};

    // 系列被拆分并多次去重后，完成状态可能只保留在源系列中已经删除的
    // 重复实例上。合并时按发生日期取完成状态并集，再写回该日仍可见的
    // 实例；目标系列中早已删除的旧状态不参与，避免覆盖用户后续的取消完成。
    final completedDays = participating
        .where((todo) =>
            todo.isDone &&
            (!todo.isDeleted || todo.recurrenceSeriesId != targetSeriesId))
        .map((todo) => _recurrenceLocalDayKey(
              todo.createdDate ?? todo.createdAt,
            ))
        .toSet();
    for (final todo in participating) {
      if (todo.isDeleted || todo.isDone) continue;
      final dayKey = _recurrenceLocalDayKey(
        todo.createdDate ?? todo.createdAt,
      );
      if (!completedDays.contains(dayKey)) continue;
      todo.isDone = true;
      fieldChangedIds.add(todo.id);
    }

    for (final todo in participating) {
      if (todo.recurrenceSeriesId != targetSeriesId) {
        todo.recurrenceSeriesId = targetSeriesId;
        fieldChangedIds.add(todo.id);
      }
      if (todo.recurrence != RecurrenceType.none &&
          todo.id != canonicalActive?.id) {
        todo.recurrence = RecurrenceType.none;
        fieldChangedIds.add(todo.id);
      }
    }

    _deduplicatePersistedRecurrenceOccurrences(participating);
    final changedIds = <String>{};
    for (final todo in participating) {
      if (todo.version != versionsBefore[todo.id]) {
        changedIds.add(todo.id);
      }
    }
    for (final todo in participating) {
      if (!fieldChangedIds.contains(todo.id)) continue;
      if (todo.version == versionsBefore[todo.id]) {
        todo.markAsChanged();
      }
      changedIds.add(todo.id);
    }
    return changedIds;
  }

  List<int> _futureRecurrenceRollOffsets(
    TodoItem todo,
    DateTime baseLocal,
  ) {
    final baseDay = DateTime(baseLocal.year, baseLocal.month, baseLocal.day);
    final recurrenceEnd = todo.recurrenceEndDate;
    if (recurrenceEnd != null) {
      final endDay =
          DateTime(recurrenceEnd.year, recurrenceEnd.month, recurrenceEnd.day);
      return _recurrenceRollOffsets(todo, baseDay, endDay);
    }

    final offsets = <int>[];
    var cursor = baseLocal;
    for (var i = 0; i < 2; i++) {
      final next = _nextRecurrenceDate(cursor, todo);
      if (next == null || !next.isAfter(cursor)) break;
      offsets.add(
          DateTime(next.year, next.month, next.day).difference(baseDay).inDays);
      cursor = next;
    }
    return offsets;
  }

  DateTime? _nextRecurrenceDate(DateTime current, TodoItem todo) {
    switch (todo.recurrence) {
      case RecurrenceType.daily:
        return DateTime(current.year, current.month, current.day + 1,
            current.hour, current.minute, current.second, current.millisecond);
      case RecurrenceType.customDays:
        final days = todo.customIntervalDays ?? 0;
        if (days <= 0) return null;
        return DateTime(current.year, current.month, current.day + days,
            current.hour, current.minute, current.second, current.millisecond);
      case RecurrenceType.weekly:
        return DateTime(current.year, current.month, current.day + 7,
            current.hour, current.minute, current.second, current.millisecond);
      case RecurrenceType.weekdays:
        var next = DateTime(current.year, current.month, current.day + 1,
            current.hour, current.minute, current.second, current.millisecond);
        while (next.weekday == DateTime.saturday ||
            next.weekday == DateTime.sunday) {
          next = DateTime(next.year, next.month, next.day + 1, next.hour,
              next.minute, next.second, next.millisecond);
        }
        return next;
      case RecurrenceType.monthly:
        final targetMonth = DateTime(current.year, current.month + 1);
        final lastDay =
            DateTime(targetMonth.year, targetMonth.month + 1, 0).day;
        return DateTime(
          targetMonth.year,
          targetMonth.month,
          current.day.clamp(1, lastDay),
          current.hour,
          current.minute,
          current.second,
          current.millisecond,
        );
      case RecurrenceType.yearly:
        final lastDay = DateTime(current.year + 1, current.month + 1, 0).day;
        return DateTime(
          current.year + 1,
          current.month,
          current.day.clamp(1, lastDay),
          current.hour,
          current.minute,
          current.second,
          current.millisecond,
        );
      case RecurrenceType.none:
        return null;
    }
  }

  ({TodoItem occurrence, bool isNew, bool didChange})
      _getOrCreateRecurrenceOccurrence({
    required TodoItem source,
    required int rollByDays,
    required String seriesId,
    required List<TodoItem> todos,
    required List<TodoItem> generatedOccurrences,
  }) {
    final candidate = _copyForNextRecurrence(source);
    candidate.recurrenceSeriesId = seriesId;
    _rollRecurrenceDateByDays(candidate, rollByDays);
    final candidateStart = candidate.createdDate ?? candidate.createdAt;
    final candidateDayKey = _recurrenceLocalDayKey(candidateStart);
    candidate.id = _recurrenceOccurrenceId(seriesId, candidateStart);

    final matches = <TodoItem>[];
    for (final existing in todos.followedBy(generatedOccurrences)) {
      if (existing.recurrenceSeriesId != seriesId ||
          _recurrenceLocalDayKey(
                existing.createdDate ?? existing.createdAt,
              ) !=
              candidateDayKey) {
        continue;
      }
      matches.add(existing);
    }

    final liveMatches = matches.where((todo) => !todo.isDeleted).toList();
    if (liveMatches.isNotEmpty) {
      liveMatches.sort(_compareRecurrenceOccurrenceIdentity);
      return (
        occurrence: liveMatches.first,
        isNew: false,
        didChange: false,
      );
    }

    final deletedDeterministic =
        matches.where((todo) => todo.id == candidate.id).firstOrNull;
    if (deletedDeterministic != null) {
      _copyRecurrenceOccurrenceData(candidate, deletedDeterministic);
      deletedDeterministic.isDeleted = false;
      deletedDeterministic.markAsChanged();
      _recurrenceDedupeTombstoneIds.remove(deletedDeterministic.id);
      return (
        occurrence: deletedDeterministic,
        isNew: false,
        didChange: true,
      );
    }

    generatedOccurrences.add(candidate);
    return (occurrence: candidate, isNew: true, didChange: true);
  }

  String _recurrenceLocalDayKey(int startMs) {
    final start =
        DateTime.fromMillisecondsSinceEpoch(startMs, isUtc: true).toLocal();
    final month = start.month.toString().padLeft(2, '0');
    final day = start.day.toString().padLeft(2, '0');
    return '${start.year}-$month-$day';
  }

  String _recurrenceOccurrenceId(String seriesId, int startMs) {
    final dayKey = _recurrenceLocalDayKey(startMs);
    return const Uuid().v5(
      _recurrenceOccurrenceNamespace,
      'countdown-todo/recurrence-occurrence/v1/$seriesId/$dayKey',
    );
  }

  List<TodoItem> _repairMissingPastRecurrenceOccurrences({
    required TodoItem ruleSource,
    required TodoItem copySource,
    required String seriesId,
    required int throughStartMs,
    required List<TodoItem> todos,
    required List<TodoItem> generatedOccurrences,
  }) {
    final knownByDay = <String, DateTime>{};
    for (final occurrence in todos.followedBy(generatedOccurrences)) {
      if (occurrence.isDeleted || occurrence.recurrenceSeriesId != seriesId) {
        continue;
      }
      final startMs = occurrence.createdDate ?? occurrence.createdAt;
      if (startMs > throughStartMs) continue;
      final start =
          DateTime.fromMillisecondsSinceEpoch(startMs, isUtc: true).toLocal();
      final day = DateTime(start.year, start.month, start.day);
      knownByDay['${day.year}-${day.month}-${day.day}'] = day;
    }

    final knownDays = knownByDay.values.toList()..sort();
    if (knownDays.length < 2) return const [];

    final copyBase = _getRecurrenceBaseDate(copySource);
    final copyBaseDay = DateTime(copyBase.year, copyBase.month, copyBase.day);
    final repaired = <TodoItem>[];
    for (var index = 0; index < knownDays.length - 1; index++) {
      final previousDay = knownDays[index];
      final nextKnownDay = knownDays[index + 1];
      final candidateOffsets = _recurrenceRollOffsets(
        ruleSource,
        previousDay,
        nextKnownDay,
      );
      for (final candidateOffset in candidateOffsets) {
        final candidateDay = DateTime(
          previousDay.year,
          previousDay.month,
          previousDay.day + candidateOffset,
        );
        if (!candidateDay.isBefore(nextKnownDay)) continue;

        final rollByDays = DateTime.utc(
          candidateDay.year,
          candidateDay.month,
          candidateDay.day,
        )
            .difference(DateTime.utc(
              copyBaseDay.year,
              copyBaseDay.month,
              copyBaseDay.day,
            ))
            .inDays;
        final result = _getOrCreateRecurrenceOccurrence(
          source: copySource,
          rollByDays: rollByDays,
          seriesId: seriesId,
          todos: todos,
          generatedOccurrences: generatedOccurrences,
        );
        if (!result.didChange) continue;
        result.occurrence.recurrence = RecurrenceType.none;
        repaired.add(result.occurrence);
      }
    }
    return repaired;
  }

  bool _deduplicatePersistedRecurrenceOccurrences(List<TodoItem> todos,
      {Set<String>? changedIds}) {
    final occurrencesBySeriesDay = <String, List<TodoItem>>{};
    for (final todo in todos) {
      final seriesId = todo.recurrenceSeriesId;
      if (seriesId == null || seriesId.isEmpty) continue;
      final startMs = todo.createdDate ?? todo.createdAt;
      final key = '$seriesId|${_recurrenceLocalDayKey(startMs)}';
      occurrencesBySeriesDay.putIfAbsent(key, () => []).add(todo);
    }

    var changed = false;
    for (final occurrences in occurrencesBySeriesDay.values) {
      if (occurrences.length <= 1) continue;
      final liveOccurrences =
          occurrences.where((todo) => !todo.isDeleted).toList();
      if (liveOccurrences.isEmpty) continue;

      // Identity must not depend on mutable LWW fields. Every device will
      // eventually select the same oldest physical occurrence, even if it
      // initially saw only a subset of the duplicates.
      occurrences.sort(_compareRecurrenceOccurrenceIdentity);
      final canonical = occurrences.first;
      // 复用普通待办的严格 LWW 顺序：updated_at 优先，只有时间相同才比较
      // version。旧设备可能因为本地重复实例修复而拥有更高 version，但这
      // 不代表它的完成状态比服务器上较新的实例更可信。
      liveOccurrences.sort(_compareRecurrenceOccurrenceLwwDescending);
      final dataWinner = liveOccurrences.first;
      final completionWinner = dataWinner;
      final activeOccurrences = liveOccurrences
          .where((todo) => todo.recurrence != RecurrenceType.none)
          .toList()
        ..sort(_compareRecurrenceOccurrenceLwwDescending);
      final mergedRecurrence = activeOccurrences.isEmpty
          ? RecurrenceType.none
          : activeOccurrences.first.recurrence;

      var canonicalChanged = false;
      if (!identical(canonical, dataWinner)) {
        canonicalChanged =
            _copyRecurrenceOccurrenceData(dataWinner, canonical) ||
                canonicalChanged;
      }
      if (canonical.isDeleted) {
        canonical.isDeleted = false;
        canonicalChanged = true;
      }
      if (canonical.isDone != completionWinner.isDone) {
        canonical.isDone = completionWinner.isDone;
        canonicalChanged = true;
      }
      if (canonical.recurrence != mergedRecurrence) {
        canonical.recurrence = mergedRecurrence;
        canonicalChanged = true;
      }
      if (canonicalChanged) {
        // 这是结构性去重，不是用户的新编辑。沿用获胜实例的 LWW 元数据，
        // 避免把旧的未完成副本通过 markAsChanged() 伪装成当前新写入。
        canonical.version = dataWinner.version;
        canonical.updatedAt = dataWinner.updatedAt;
        _recurrenceDedupeTombstoneIds.remove(canonical.id);
        changedIds?.add(canonical.id);
        changed = true;
      }

      for (final duplicate in occurrences) {
        if (identical(duplicate, canonical)) continue;
        if (duplicate.isDeleted &&
            duplicate.recurrence == RecurrenceType.none) {
          continue;
        }
        duplicate.isDeleted = true;
        duplicate.recurrence = RecurrenceType.none;
        duplicate.markAsChanged();
        _recurrenceDedupeTombstoneIds.add(duplicate.id);
        changedIds?.add(duplicate.id);
        changed = true;
      }
    }
    return changed;
  }

  bool _pruneRecurrenceOccurrencesAfterEndDate(
    Iterable<TodoItem> todos, {
    required String seriesId,
    required DateTime recurrenceEndDate,
  }) {
    final endDay = DateTime(
      recurrenceEndDate.year,
      recurrenceEndDate.month,
      recurrenceEndDate.day,
    );
    var changed = false;
    for (final occurrence in todos) {
      if (occurrence.isDeleted || occurrence.recurrenceSeriesId != seriesId) {
        continue;
      }
      final startMs = occurrence.createdDate ?? occurrence.createdAt;
      final start = DateTime.fromMillisecondsSinceEpoch(
        startMs,
        isUtc: true,
      ).toLocal();
      final startDay = DateTime(start.year, start.month, start.day);
      if (!startDay.isAfter(endDay)) continue;

      occurrence.isDeleted = true;
      occurrence.recurrence = RecurrenceType.none;
      occurrence.markAsChanged();
      changed = true;
    }
    return changed;
  }

  int _compareRecurrenceOccurrenceLwwDescending(TodoItem a, TodoItem b) {
    final lwwOrder = TodoLwwService.compare(
      incomingUpdatedAt: a.updatedAt,
      incomingVersion: a.version,
      currentUpdatedAt: b.updatedAt,
      currentVersion: b.version,
    );
    if (lwwOrder != 0) return -lwwOrder;
    return a.id.compareTo(b.id);
  }

  int _compareRecurrenceOccurrenceIdentity(TodoItem a, TodoItem b) {
    final createdAtComparison = a.createdAt.compareTo(b.createdAt);
    if (createdAtComparison != 0) return createdAtComparison;
    return a.id.compareTo(b.id);
  }

  bool _copyRecurrenceOccurrenceData(
    TodoItem source,
    TodoItem target,
  ) {
    var changed = false;

    void assign<T>(T current, T next, void Function(T) setter) {
      if (current == next) return;
      setter(next);
      changed = true;
    }

    assign(target.title, source.title, (value) => target.title = value);
    assign(target.createdDate, source.createdDate,
        (value) => target.createdDate = value);
    assign(target.dueDate, source.dueDate, (value) => target.dueDate = value);
    assign(target.recurrenceSeriesId, source.recurrenceSeriesId,
        (value) => target.recurrenceSeriesId = value);
    assign(target.customIntervalDays, source.customIntervalDays,
        (value) => target.customIntervalDays = value);
    assign(target.recurrenceEndDate, source.recurrenceEndDate,
        (value) => target.recurrenceEndDate = value);
    assign(target.remark, source.remark, (value) => target.remark = value);
    assign(target.imagePath, source.imagePath,
        (value) => target.imagePath = value);
    assign(target.originalText, source.originalText,
        (value) => target.originalText = value);
    assign(target.groupId, source.groupId, (value) => target.groupId = value);
    assign(target.reminderMinutes, source.reminderMinutes,
        (value) => target.reminderMinutes = value);
    assign(
        target.teamUuid, source.teamUuid, (value) => target.teamUuid = value);
    assign(target.creatorId, source.creatorId,
        (value) => target.creatorId = value);
    assign(target.creatorName, source.creatorName,
        (value) => target.creatorName = value);
    assign(
        target.teamName, source.teamName, (value) => target.teamName = value);
    assign(target.collabType, source.collabType,
        (value) => target.collabType = value);
    assign(
        target.isAllDay, source.isAllDay, (value) => target.isAllDay = value);
    assign(target.categoryId, source.categoryId,
        (value) => target.categoryId = value);
    return changed;
  }

  String? _overlappingRecurrencePairKey(TodoItem previous, TodoItem next) {
    final previousStart = previous.createdDate ?? previous.createdAt;
    final previousEnd = previous.dueDate?.millisecondsSinceEpoch;
    final nextStart = next.createdDate ?? next.createdAt;
    final nextEnd = next.dueDate?.millisecondsSinceEpoch;
    if (previousEnd == null || nextEnd == null) return null;
    if (previousStart >= nextEnd || nextStart >= previousEnd) return null;
    return _scheduleConflictPairKey(
      previous.id,
      previousStart,
      previousEnd,
      next.id,
      nextStart,
      nextEnd,
    );
  }

  TodoItem _copyForNextRecurrence(TodoItem source) {
    return TodoItem(
      title: source.title,
      createdDate: source.createdDate,
      recurrence: source.recurrence,
      recurrenceSeriesId: source.recurrenceSeriesId ?? source.id,
      customIntervalDays: source.customIntervalDays,
      recurrenceEndDate: source.recurrenceEndDate,
      dueDate: source.dueDate,
      remark: source.remark,
      imagePath: source.imagePath,
      originalText: source.originalText,
      groupId: source.groupId,
      reminderMinutes: source.reminderMinutes,
      teamUuid: source.teamUuid,
      creatorId: source.creatorId,
      creatorName: source.creatorName,
      teamName: source.teamName,
      collabType: source.collabType,
      isAllDay: source.isAllDay,
      categoryId: source.categoryId,
    );
  }

  void _rollRecurrenceDateByDays(TodoItem todo, int days) {
    if (todo.dueDate != null) {
      final originalDueDate = todo.dueDate!;
      todo.dueDate = DateTime(
        originalDueDate.year,
        originalDueDate.month,
        originalDueDate.day + days,
        originalDueDate.hour,
        originalDueDate.minute,
        originalDueDate.second,
        originalDueDate.millisecond,
        originalDueDate.microsecond,
      );
    }
    if (todo.createdDate != null) {
      final originalCreatedDate =
          DateTime.fromMillisecondsSinceEpoch(todo.createdDate!, isUtc: true)
              .toLocal();
      todo.createdDate = DateTime(
        originalCreatedDate.year,
        originalCreatedDate.month,
        originalCreatedDate.day + days,
        originalCreatedDate.hour,
        originalCreatedDate.minute,
        originalCreatedDate.second,
        originalCreatedDate.millisecond,
      ).millisecondsSinceEpoch;
    }
  }

  Future<bool> deleteTodoGlobally(String username, String idToDelete) async {
    List<TodoItem> localTodos = await getTodos(username);
    int index = localTodos.indexWhere((t) => t.id == idToDelete);

    if (index == -1) return false;

    localTodos[index].isDeleted = true;

    try {
      localTodos[index].markAsChanged();
    } catch (_) {
      localTodos[index].updatedAt = DateTime.now().millisecondsSinceEpoch;
      localTodos[index].version += 1;
    }

    await saveTodos(username, localTodos, sync: true);
    return true;
  }

  Future<void> saveTodoGroups(String username, List<TodoGroup> items,
      {bool sync = true, bool isSyncSource = false}) async {
    final Map<String, TodoGroup> dedupeMap = {};

    for (var item in items) {
      if (!dedupeMap.containsKey(item.id) ||
          item.updatedAt > dedupeMap[item.id]!.updatedAt) {
        dedupeMap[item.id] = item;
      }
    }

    final db = await DatabaseHelper.instance.database;
    final existingRows = await db.query('todo_groups');
    final existingItemsMap = <String, Map<String, dynamic>>{
      for (final row in existingRows) row['uuid'].toString(): row,
    };
    final batch = db.batch();
    for (var item in dedupeMap.values) {
      bool hasChanged = true;
      final oldData = existingItemsMap[item.id];
      if (oldData != null) {
        hasChanged = _hasSubstantialChange(oldData, item.toJson(), [
          'name',
          'is_expanded',
          'is_deleted',
          'team_uuid',
          'version',
          'updated_at',
          'has_conflict',
          'conflict_data',
        ]);
      }

      if (!isSyncSource && hasChanged) {
        batch.insert('op_logs', {
          'op_type': 'UPSERT',
          'target_table': 'todo_groups',
          'target_uuid': item.id,
          'data_json': jsonEncode(item.toJson()),
          'timestamp': DateTime.now().millisecondsSinceEpoch,
          'is_synced': 0,
          'sync_error': '',
        });
      }

      if (hasChanged || oldData == null) {
        batch.insert(
            'todo_groups',
            {
              'uuid': item.id,
              'team_uuid': item.teamUuid,
              'team_name': item.teamName,
              'creator_id': item.creatorId,
              'creator_name': item.creatorName,
              'name': item.name,
              'is_expanded': item.isExpanded ? 1 : 0,
              'is_deleted': item.isDeleted ? 1 : 0,
              'version': item.version,
              'updated_at': item.updatedAt,
              'created_at': item.createdAt,
              'has_conflict': item.hasConflict ? 1 : 0,
              'conflict_data': item.conflictData != null
                  ? jsonEncode(item.conflictData)
                  : null
            },
            conflictAlgorithm: ConflictAlgorithm.replace);
      }
    }
    await batch.commit(noResult: true);
    _inflightTodoRequests.clear();

    unawaited(_clearTodoGroupPrefsMirror(username));
    if (sync) requestSync(username);
    triggerRefresh(const {DataRefreshDomain.todoGroups});
  }

  Future<void> _clearTodoGroupPrefsMirror(String username) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove("${keyTodoGroups}_$username");
    await prefs.remove(keyTodoGroups);
  }

  Future<List<TodoGroup>> getTodoGroups(String username,
      {bool includeDeleted = false}) async {
    try {
      final dbHelper = DatabaseHelper.instance;
      final db = await dbHelper.database;
      await _clearGhostConflictFlags(db);
      final prefs = await SharedPreferences.getInstance();

      // 1. 迁移检查
      final List<Map<String, dynamic>> sqliteCount =
          await db.rawQuery('SELECT COUNT(*) as cnt FROM todo_groups');
      if (sqliteCount.first['cnt'] == 0) {
        List<String> legacyJsonList =
            prefs.getStringList("${keyTodoGroups}_$username") ?? [];

        // 🚀 核心修复：增加一次性迁移保护
        if (legacyJsonList.isEmpty && username.isNotEmpty) {
          final String markerKey = "${keyTodoGroups}_${username}_migrated";
          if (!(prefs.getBool(markerKey) ?? false)) {
            legacyJsonList = prefs.getStringList(keyTodoGroups) ?? [];
            if (legacyJsonList.isNotEmpty) {
              await prefs.setBool(markerKey, true);
            }
          }
        }

        if (legacyJsonList.isNotEmpty) {
          debugPrint("🚀 自动迁移待办组数据至 SQLite...");
          List<TodoGroup> legacyData = legacyJsonList
              .map((e) => TodoGroup.fromJson(jsonDecode(e)))
              .toList();
          await saveTodoGroups(username, legacyData,
              sync: false, isSyncSource: true);
        }
      }

      // 2. 从 SQL 读取 (排除逻辑删除)
      final List<Map<String, dynamic>> maps = await db.query('todo_groups',
          where: includeDeleted ? null : 'is_deleted = 0');
      if (maps.isNotEmpty) {
        return maps
            .map((m) => TodoGroup(
                  id: m['uuid'],
                  name: m['name'] ?? '',
                  isExpanded: m['is_expanded'] == 1,
                  isDeleted: m['is_deleted'] == 1,
                  version: m['version'] ?? 1,
                  updatedAt:
                      m['updated_at'] ?? DateTime.now().millisecondsSinceEpoch,
                  createdAt:
                      m['created_at'] ?? DateTime.now().millisecondsSinceEpoch,
                  teamUuid: m['team_uuid'],
                  teamName: m['team_name'],
                  creatorId: m['creator_id'],
                  creatorName: m['creator_name'],
                  hasConflict: m['has_conflict'] == 1,
                  conflictData: m['conflict_data'] != null
                      ? jsonDecode(m['conflict_data'])
                      : null,
                ))
            .toList();
      } else {
        return [];
      }
    } catch (e) {
      debugPrint("⚠️ TodoGroups SQL 引擎异常: $e");
    }

    // 逃生通道
    final prefs = await StorageService.prefs;
    List<String> list = prefs.getStringList("${keyTodoGroups}_$username") ?? [];
    List<TodoGroup> result = [];

    for (var e in list) {
      try {
        result.add(TodoGroup.fromJson(jsonDecode(e)));
      } catch (err) {
        debugPrint("Parse TodoGroup Error: $err");
      }
    }
    return result;
  }

  Future<void> deleteTodoGroupGlobally(
      String username, String idToDelete) async {
    List<TodoGroup> localGroups = await getTodoGroups(username);
    int index = localGroups.indexWhere((t) => t.id == idToDelete);

    if (index != -1) {
      localGroups[index].isDeleted = true;
      localGroups[index].markAsChanged();
      await saveTodoGroups(username, localGroups, sync: true);
    }

    // 同时将组内的待办恢复为未分组状态
    List<TodoItem> allTodos = await getTodos(username);
    bool todoChanged = false;
    for (var t in allTodos) {
      if (t.groupId == idToDelete) {
        t.groupId = null;
        t.markAsChanged();
        todoChanged = true;
      }
    }
    if (todoChanged) {
      await saveTodos(username, allTodos, sync: true);
    }
  }
}
