part of 'storage_service.dart';

// ignore_for_file: annotate_overrides, unused_element, unused_element_parameter

mixin _StorageTodoConflicts on _StorageServiceBase {
  bool _hasSubstantialChange(
    Map<String, dynamic> before,
    Map<String, dynamic> after,
    List<String> fields,
  ) {
    for (var field in fields) {
      var valA = after[field];
      var valB = before[field];

      // 归一化处理
      bool isAEmpty =
          valA == null ||
          valA == 0 ||
          valA == "" ||
          valA == false ||
          (field == 'reminder_minutes' && valA == -1);
      bool isBEmpty =
          valB == null ||
          valB == 0 ||
          valB == "" ||
          valB == false ||
          (field == 'reminder_minutes' && valB == -1);

      if (isAEmpty && isBEmpty) continue;
      if (isAEmpty || isBEmpty) return true;
      if (valA is Map && valB is Map && jsonEncode(valA) == jsonEncode(valB)) {
        continue;
      }
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
            .where(
              (todo) =>
                  beforeConflictState[todo.id] !=
                  '${todo.hasConflict}:${jsonEncode(todo.serverVersionData)}',
            )
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
      _recomputeLocalTodoScheduleConflicts(
        todos,
        ignoredScheduleConflictKeys: ignoredKeys,
      );
      final changedTodos = todos
          .where(
            (todo) =>
                beforeConflictState[todo.id] !=
                '${todo.hasConflict}:${jsonEncode(todo.serverVersionData)}',
          )
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
      final endMs = time_utils.AppTimeFormats.localDayStartOffset(
        day,
        1,
      ).millisecondsSinceEpoch;
      final rows = await DatabaseHelper.instance.getTodoMaps(
        includeDeleted: true,
        includeConflictData: true,
        where:
            '(t.created_date >= $startMs AND t.created_date < $endMs) '
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
          previousData['created_date'] ?? previousData['createdDate'],
        ),
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
      if (!ConflictVisibilityService.isLocalScheduleConflictData(data)) {
        continue;
      }
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
    String username,
    TodoItem item,
  ) async {
    final data = item.serverVersionData;
    if (!ConflictVisibilityService.isLocalScheduleConflictData(data)) return;

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
        ignoredKeys.add(
          _scheduleConflictPairKey(
            item.id,
            startMs,
            endMs,
            peerId,
            peerStart,
            peerEnd,
          ),
        );
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
      if (!ConflictVisibilityService.isLocalScheduleConflictData(
        conflictData,
      )) {
        continue;
      }

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
    String username,
    String table,
    String uuid,
    Map<String, dynamic> afterData,
    String? teamUuid,
    Map<String, dynamic>? existingData,
  ) async {
    try {
      final db = await DatabaseHelper.instance.databaseForUser(username);
      if (existingData == null) {
        await DatabaseHelper.instance.insertLocalAuditLog(
          databaseOverride: db,
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
        databaseOverride: db,
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

  Future<void> _recordLocalAudit(
    String username,
    String table,
    String uuid,
    Map<String, dynamic> afterData,
    String? teamUuid,
  ) async {
    try {
      final db = await DatabaseHelper.instance.databaseForUser(username);
      // 1. 获取旧数据快照
      final List<Map<String, dynamic>> existing = await db.query(
        table,
        where: 'uuid = ?',
        whereArgs: [uuid],
      );
      if (existing.isEmpty) {
        // 新增操作，直接记录
        await DatabaseHelper.instance.insertLocalAuditLog(
          databaseOverride: db,
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

      Map<String, dynamic> beforeData = Map<String, dynamic>.from(
        existing.first,
      );

      // 🚀 核心优化：实质性变更检测
      // 排除掉 version, updated_at 等会自动变动的字段，只对比业务字段
      bool hasSubstantialChange = false;
      final businessFields = [
        'content',
        'title',
        'remark',
        'is_completed',
        'completed_at',
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
        'custom_interval_days',
      ];

      for (var field in businessFields) {
        if (afterData.containsKey(field) || beforeData.containsKey(field)) {
          var valA = afterData[field];
          var valB = beforeData[field];

          // 🚀 核心修复：全面的值归一化处理
          // 处理 null 和 0/""/"false" 的等价性
          // 特别处理 reminder_minutes: -1 和 null 的等价性
          bool isAEmpty =
              valA == null ||
              valA == 0 ||
              valA == "" ||
              valA == false ||
              (field == 'reminder_minutes' && valA == -1);
          bool isBEmpty =
              valB == null ||
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
          final List<Map<String, dynamic>> res = await db.query(
            targetTable,
            columns: ['name'],
            where: 'uuid = ?',
            whereArgs: [targetUuid],
          );
          return res.isNotEmpty ? res.first['name'] as String? : null;
        } catch (_) {
          return null;
        }
      }

      if (beforeData['group_id'] != null) {
        beforeData['group_name'] = await lookupName(
          'todo_groups',
          beforeData['group_id'],
        );
      }
      if (beforeData['team_uuid'] != null) {
        beforeData['team_name'] = await lookupName(
          'teams',
          beforeData['team_uuid'],
        );
      }
      if (enrichedAfter['group_id'] != null) {
        enrichedAfter['group_name'] = await lookupName(
          'todo_groups',
          enrichedAfter['group_id'],
        );
      }
      if (enrichedAfter['team_uuid'] != null) {
        enrichedAfter['team_name'] = await lookupName(
          'teams',
          enrichedAfter['team_uuid'],
        );
      }

      // 2. 存入本地审计表
      await DatabaseHelper.instance.insertLocalAuditLog(
        databaseOverride: db,
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
}
