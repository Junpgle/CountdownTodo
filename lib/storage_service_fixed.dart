part of 'storage_service.dart';

// ignore_for_file: annotate_overrides, unused_element, unused_element_parameter

List<TodoPlanBlock> _parsePlanBlockItemsIsolate(
  List<Map<String, dynamic>> maps,
) {
  return maps.map((m) => TodoPlanBlock.fromJson(m)).toList();
}

mixin _StorageFixed on _StorageServiceBase {
  bool isRecentlyResolved(String uuid) {
    if (!recentlyResolvedUuids.contains(uuid)) return false;
    final time = recentlyResolvedTimes[uuid];
    if (time == null) return true;
    // 🛡️ [MemoryShield] 竞态阻断锁自动超时阈值定为 30 秒。
    // 超过该时间则认定之前的竞态场景早已结束，自动解锁，以防用户离线等极端同步失败情况下产生死锁。
    if (DateTime.now().difference(time).inSeconds > 30) {
      recentlyResolvedUuids.remove(uuid);
      recentlyResolvedTimes.remove(uuid);
      debugPrint(
        '🔓 [MemoryShield] Timeout auto-released recently resolved item: $uuid',
      );
      return false;
    }
    return true;
  }

  Future<SharedPreferences> get prefs async {
    if (_prefs != null) return _prefs!;
    _prefs = await SharedPreferences.getInstance();
    return _prefs!;
  }

  Future<void> saveFixedSchedules(
    String username,
    List<FixedScheduleItem> items, {
    bool sync = true,
    bool isSyncSource = false,
  }) async {
    if (items.isEmpty) return;
    final deduped = <String, FixedScheduleItem>{};
    for (final item in items) {
      final existing = deduped[item.id];
      if (existing == null ||
          TodoLwwService.isIncomingWinner(
            incomingUpdatedAt: item.updatedAt,
            incomingVersion: item.version,
            currentUpdatedAt: existing.updatedAt,
            currentVersion: existing.version,
          )) {
        deduped[item.id] = item;
      }
    }

    final db = await DatabaseHelper.instance.databaseForUser(username);
    final ids = deduped.keys.toList();
    final existingById = <String, Map<String, dynamic>>{};
    if (ids.isNotEmpty) {
      final placeholders = List.filled(ids.length, '?').join(',');
      final existingRows = await db.query(
        'fixed_schedules',
        where: 'uuid IN ($placeholders)',
        whereArgs: ids,
      );
      for (final row in existingRows) {
        existingById[row['uuid'].toString()] = row;
      }
    }

    final batch = db.batch();
    var wroteAny = false;
    for (final item in deduped.values) {
      final data = item.toJson();
      final existing = existingById[item.id];
      final hasChanged =
          existing == null ||
          _hasSubstantialChange(existing, data, [
            'title',
            'date',
            'start_time',
            'end_time',
            'status',
            'source',
            'location',
            'remark',
            'reminder_minutes',
            'timezone',
            'recurrence',
            'custom_interval_days',
            'recurrence_series_id',
            'related_todo_ids',
            'external_source',
            'external_id',
            'team_uuid',
            'owner_user_id',
            'device_id',
            'is_deleted',
            'version',
            'created_at',
            'updated_at',
          ]);
      if (!hasChanged) continue;
      wroteAny = true;
      if (!isSyncSource) {
        batch.insert('op_logs', {
          'op_type': 'UPSERT',
          'target_table': 'fixed_schedules',
          'target_uuid': item.id,
          'data_json': jsonEncode(data),
          'timestamp': DateTime.now().millisecondsSinceEpoch,
          'is_synced': 0,
          'sync_error': '',
        });
      }
      batch.insert(
        'fixed_schedules',
        data,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    if (wroteAny) await batch.commit(noResult: true);
    if (sync && wroteAny) requestSync(username);
    if (wroteAny) {
      triggerRefresh(const {DataRefreshDomain.fixedSchedules});
    }
  }

  /// Atomically validates the loaded series snapshot and writes its edits.
  /// Returns false when another local or sync writer changed a row or the
  /// series membership while the editor was open.
  Future<bool> saveFixedSchedulesIfUnchanged(
    String username, {
    required List<FixedScheduleItem> baseline,
    required List<FixedScheduleItem> items,
    bool sync = true,
  }) async {
    if (items.isEmpty) return true;

    final deduped = <String, FixedScheduleItem>{};
    for (final item in items) {
      final existing = deduped[item.id];
      if (existing == null ||
          TodoLwwService.isIncomingWinner(
            incomingUpdatedAt: item.updatedAt,
            incomingVersion: item.version,
            currentUpdatedAt: existing.updatedAt,
            currentVersion: existing.version,
          )) {
        deduped[item.id] = item;
      }
    }

    final db = await DatabaseHelper.instance.databaseForUser(username);
    var wroteAny = false;
    final accepted = await db.transaction<bool>((txn) async {
      final baselineById = {for (final item in baseline) item.id: item};
      if (baselineById.length != baseline.length) return false;

      final baselineIds = baselineById.keys.toList();
      final currentById = <String, Map<String, Object?>>{};
      if (baselineIds.isNotEmpty) {
        final placeholders = List.filled(baselineIds.length, '?').join(',');
        final rows = await txn.query(
          'fixed_schedules',
          where: 'uuid IN ($placeholders)',
          whereArgs: baselineIds,
        );
        for (final row in rows) {
          currentById[row['uuid'].toString()] = row;
        }
      }

      for (final expected in baseline) {
        final raw = currentById[expected.id];
        if (raw == null) return false;
        final current = FixedScheduleItem.fromJson(raw);
        if (jsonEncode(current.toJson()) != jsonEncode(expected.toJson())) {
          return false;
        }
      }

      final expectedIdsBySeries = <String, Set<String>>{};
      for (final item in baseline) {
        final seriesId = item.recurrenceSeriesId?.trim();
        if (seriesId == null || seriesId.isEmpty) continue;
        expectedIdsBySeries
            .putIfAbsent(seriesId, () => <String>{})
            .add(item.id);
      }
      for (final entry in expectedIdsBySeries.entries) {
        final rows = await txn.query(
          'fixed_schedules',
          columns: ['uuid'],
          where: 'recurrence_series_id = ?',
          whereArgs: [entry.key],
        );
        final currentIds = rows.map((row) => row['uuid'].toString()).toSet();
        if (currentIds.length != entry.value.length ||
            !currentIds.containsAll(entry.value)) {
          return false;
        }
      }

      final changedRowsById = <String, Map<String, Object?>>{};
      final changeIds = deduped.keys.toList();
      if (changeIds.isNotEmpty) {
        final placeholders = List.filled(changeIds.length, '?').join(',');
        final rows = await txn.query(
          'fixed_schedules',
          where: 'uuid IN ($placeholders)',
          whereArgs: changeIds,
        );
        for (final row in rows) {
          changedRowsById[row['uuid'].toString()] = row;
        }
      }

      if (deduped.keys.any(
        (id) =>
            !baselineById.containsKey(id) && changedRowsById.containsKey(id),
      )) {
        return false;
      }

      final batch = txn.batch();
      for (final item in deduped.values) {
        final data = item.toJson();
        final existing = changedRowsById[item.id];
        final hasChanged =
            existing == null ||
            _hasSubstantialChange(existing, data, [
              'title',
              'date',
              'start_time',
              'end_time',
              'status',
              'source',
              'location',
              'remark',
              'reminder_minutes',
              'timezone',
              'recurrence',
              'custom_interval_days',
              'recurrence_series_id',
              'related_todo_ids',
              'external_source',
              'external_id',
              'team_uuid',
              'owner_user_id',
              'device_id',
              'is_deleted',
              'version',
              'created_at',
              'updated_at',
            ]);
        if (!hasChanged) continue;
        wroteAny = true;
        batch.insert('op_logs', {
          'op_type': 'UPSERT',
          'target_table': 'fixed_schedules',
          'target_uuid': item.id,
          'data_json': jsonEncode(data),
          'timestamp': DateTime.now().millisecondsSinceEpoch,
          'is_synced': 0,
          'sync_error': '',
        });
        batch.insert(
          'fixed_schedules',
          data,
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      if (wroteAny) await batch.commit(noResult: true);
      return true;
    });

    if (!accepted) return false;
    if (wroteAny && sync) requestSync(username);
    if (wroteAny) triggerRefresh(const {DataRefreshDomain.fixedSchedules});
    return true;
  }

  Future<List<FixedScheduleItem>> getFixedSchedules(
    String username, {
    bool includeDeleted = false,
  }) async {
    try {
      final db = await DatabaseHelper.instance.databaseForUser(username);
      final maps = await db.query(
        'fixed_schedules',
        where: includeDeleted ? null : 'is_deleted = 0',
        orderBy: 'date ASC, start_time ASC, updated_at DESC',
      );
      return maps.map(FixedScheduleItem.fromJson).toList();
    } catch (error) {
      debugPrint('⚠️ FixedSchedules SQL 引擎异常: $error');
      return const [];
    }
  }

  /// Reads non-deleted fixed schedules that may reference [todoId].
  ///
  /// Unlike the broad list methods, this relation-specific lookup deliberately
  /// lets database and decoding failures propagate so callers can distinguish
  /// an unavailable result from a genuinely empty relationship.
  Future<List<FixedScheduleItem>> getFixedSchedulesByRelatedTodo(
    String username,
    String todoId,
  ) async {
    final normalizedId = todoId.trim();
    if (normalizedId.isEmpty) return const [];
    final db = await DatabaseHelper.instance.databaseForUser(username);
    final encodedId = jsonEncode(normalizedId);
    final maps = await db.query(
      'fixed_schedules',
      where: 'is_deleted = 0 AND instr(related_todo_ids, ?) > 0',
      whereArgs: [encodedId],
      orderBy: 'date ASC, start_time ASC, updated_at DESC',
    );
    return maps
        .map(FixedScheduleItem.fromJson)
        .where((item) => item.relatedTodoIds.contains(normalizedId))
        .toList(growable: false);
  }

  Future<List<FixedScheduleItem>> getFixedSchedulesByDay(
    String username,
    DateTime day,
  ) async {
    final date = time_utils.AppTimeFormats.date(day.toLocal());
    try {
      final db = await DatabaseHelper.instance.databaseForUser(username);
      final maps = await db.query(
        'fixed_schedules',
        where: 'is_deleted = 0 AND date = ?',
        whereArgs: [date],
        orderBy: 'start_time ASC, updated_at DESC',
      );
      return maps.map(FixedScheduleItem.fromJson).toList();
    } catch (error) {
      debugPrint('⚠️ FixedSchedules SQL 引擎异常: $error');
      return const [];
    }
  }

  Future<List<FixedScheduleItem>> getFixedSchedulesByDateRange(
    String username, {
    required DateTime from,
    required DateTime to,
  }) async {
    final localFrom = from.toLocal();
    final localTo = to.toLocal();
    final startDate = DateTime(localFrom.year, localFrom.month, localFrom.day);
    final endDate = DateTime(localTo.year, localTo.month, localTo.day);
    if (!endDate.isAfter(startDate)) return const [];

    final dateFormat = time_utils.AppTimeFormats.dateFormatter('yyyy-MM-dd');
    try {
      final db = await DatabaseHelper.instance.databaseForUser(username);
      final maps = await db.query(
        'fixed_schedules',
        where: 'is_deleted = 0 AND date >= ? AND date < ?',
        whereArgs: [dateFormat.format(startDate), dateFormat.format(endDate)],
        orderBy: 'date ASC, start_time ASC, updated_at DESC',
      );
      return maps.map(FixedScheduleItem.fromJson).toList();
    } catch (error) {
      debugPrint('⚠️ FixedSchedules SQL 范围读取异常: $error');
      return const [];
    }
  }

  Future<void> deleteFixedSchedule(
    String username,
    FixedScheduleItem item,
  ) async {
    item.isDeleted = true;
    item.markAsChanged();
    await saveFixedSchedules(username, [item]);
  }

  Future<List<HabitGoal>> getHabitGoals() => HabitStorage.getHabitGoals();
  Future<void> saveHabitGoals(List<HabitGoal> items) =>
      HabitStorage.saveHabitGoals(items);
  Future<List<HabitGoalRuleRevision>> getHabitRules({String? habitUuid}) =>
      HabitStorage.getRuleRevisions(habitUuid: habitUuid);
  Future<void> saveHabitRules(List<HabitGoalRuleRevision> items) =>
      HabitStorage.saveRuleRevisions(items);
  Future<List<HabitCheckIn>> getHabitCheckIns({
    String? habitUuid,
    String? fromDate,
    String? toDate,
  }) => HabitStorage.getCheckIns(
    habitUuid: habitUuid,
    fromDate: fromDate,
    toDate: toDate,
  );
  Future<void> saveHabitCheckIns(List<HabitCheckIn> items) =>
      HabitStorage.saveCheckIns(items);
  Future<void> savePlanBlocks(
    String username,
    List<TodoPlanBlock> items, {
    bool sync = true,
    bool isSyncSource = false,
  }) async {
    final Map<String, TodoPlanBlock> dedupeMap = {};
    for (var item in items) {
      if (!dedupeMap.containsKey(item.id) ||
          item.updatedAt > dedupeMap[item.id]!.updatedAt) {
        dedupeMap[item.id] = item;
      }
    }

    final dedupeList = dedupeMap.values.toList();
    final db = await DatabaseHelper.instance.databaseForUser(username);

    // 🚀 批量获取现有数据，用于审计
    Map<String, Map<String, dynamic>> existingItemsMap = {};
    if (!isSyncSource && dedupeList.isNotEmpty) {
      final uuids = dedupeList.map((e) => "'${e.id}'").join(',');
      final List<Map<String, dynamic>> existing = await db.rawQuery(
        'SELECT * FROM todo_plan_blocks WHERE uuid IN ($uuids)',
      );
      for (var row in existing) {
        existingItemsMap[row['uuid']] = row;
      }
    }

    final batch = db.batch();
    for (var item in dedupeList) {
      bool hasChanged = true;
      final itemData = item.toDbJson();
      final oldData = existingItemsMap[item.id];
      // Automatic reminder maintenance may carry a snapshot read before a
      // reviewed cancellation. It must never revive that cancelled block.
      if (!isSyncSource &&
          oldData?['status'] == TodoPlanStatus.cancelled.index &&
          item.status == TodoPlanStatus.reminded) {
        continue;
      }
      if (oldData != null) {
        hasChanged = _hasSubstantialChange(oldData, itemData, [
          'todo_uuid',
          'title_snapshot',
          'start_time',
          'end_time',
          'planned_minutes',
          'status',
          'actual_focus_seconds',
          'pomodoro_record_ids',
          'source',
          'remark',
          'reminder_minutes',
          'pomodoro_minutes',
          'pomodoro_rounds',
          'calendar_event_id',
          'is_deleted',
          'version',
          'updated_at',
        ]);
      }

      if (!isSyncSource && item.status == TodoPlanStatus.reminded) {
        // These predicates run inside batch.commit's write transaction, so a
        // cancellation committed after the audit read is protected as well.
        const guard =
            'NOT EXISTS (SELECT 1 FROM todo_plan_blocks WHERE uuid=? AND status=3)';
        if (hasChanged) {
          batch.rawInsert(
            '''INSERT INTO op_logs
            (op_type,target_table,target_uuid,data_json,timestamp,is_synced,sync_error)
            SELECT 'UPSERT','todo_plan_blocks',?,?,?,0,'' WHERE $guard''',
            [
              item.id,
              jsonEncode(itemData),
              DateTime.now().millisecondsSinceEpoch,
              item.id,
            ],
          );
        }
        if (hasChanged || oldData == null) {
          final keys = itemData.keys.toList();
          batch.rawInsert(
            'INSERT INTO todo_plan_blocks (${keys.join(',')}) '
            'SELECT ${List.filled(keys.length, '?').join(',')} WHERE $guard '
            'ON CONFLICT(uuid) DO UPDATE SET ${keys.where((k) => k != 'uuid').map((k) => '$k=excluded.$k').join(',')}',
            [...keys.map((k) => itemData[k]), item.id],
          );
        }
        continue;
      }
      if (!isSyncSource && hasChanged) {
        batch.insert('op_logs', {
          'op_type': 'UPSERT',
          'target_table': 'todo_plan_blocks',
          'target_uuid': item.id,
          'data_json': jsonEncode(itemData),
          'timestamp': DateTime.now().millisecondsSinceEpoch,
          'is_synced': 0,
          'sync_error': '',
        });
      }

      if (hasChanged || oldData == null) {
        batch.insert(
          'todo_plan_blocks',
          itemData,
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    }

    if (dedupeList.isNotEmpty) {
      await batch.commit(noResult: true);
    }

    if (sync) requestSync(username);
    if (dedupeList.isNotEmpty) {
      triggerRefresh(const {DataRefreshDomain.planBlocks});
    }
  }

  Future<List<TodoPlanBlock>> cancelPlanBlocksReviewed(
    String username,
    PlanCleanupRequest request, {
    required Future<void> Function(DatabaseExecutor executor, bool retry)
    validate,
    bool sync = true,
  }) async {
    if (username != request.identity.username ||
        request.rows.isEmpty ||
        request.rows.length > 50 ||
        request.ids.toSet().length != request.rows.length ||
        request.rows.any(
          (row) =>
              row['uuid'] is! String ||
              (row['uuid'] as String).trim().isEmpty ||
              row['todo_uuid'] != request.todoId ||
              ![0, 2, 4].contains(row['status']) ||
              row['version'] is! int ||
              (row['version'] as int) < 1 ||
              row['updated_at'] is! int,
        )) {
      throw StateError('收尾请求无效，请重新核对');
    }
    await request.identity.check();
    final db = await DatabaseHelper.instance.databaseForUser(username);
    var changed = false;
    final saved = await db.transaction((tx) async {
      final current = await tx.query(
        'todo_plan_blocks',
        where: 'uuid IN (${List.filled(request.ids.length, '?').join(',')})',
        whereArgs: request.ids,
      );
      final byId = {for (final row in current) row['uuid']: row};
      final original =
          current.length == request.rows.length &&
          request.rows.every(
            (row) => PlanCleanupRequest.sameRow(byId[row['uuid']]!, row),
          );
      final retry =
          current.length == request.rows.length &&
          request.rows.every(
            (row) => PlanCleanupRequest.sameRow(
              byId[row['uuid']]!,
              request.cancelledRow(row),
            ),
          );
      if (!original && !retry) throw StateError('规划已变化，请核对后再试；尚未取消任何规划');
      await validate(tx, retry);
      await request.identity.check();
      final result = <TodoPlanBlock>[];
      for (final row in request.rows) {
        final next = request.cancelledRow(row);
        if (!retry) {
          await tx.update(
            'todo_plan_blocks',
            {
              'status': next['status'],
              'version': next['version'],
              'updated_at': next['updated_at'],
            },
            where: 'uuid=?',
            whereArgs: [row['uuid']],
          );
          final payload = {...next}..remove('id');
          await tx.insert('op_logs', {
            'op_type': 'UPSERT',
            'target_table': 'todo_plan_blocks',
            'target_uuid': row['uuid'],
            'data_json': jsonEncode(payload),
            'timestamp': request.cancelledAt,
            'is_synced': 0,
            'sync_error': '',
          });
        }
        result.add(TodoPlanBlock.fromJson(next)..isChangedLocally = true);
      }
      await request.identity.check();
      changed = !retry;
      return result;
    });
    if (changed) {
      if (sync) requestSync(username);
      triggerRefresh(const {DataRefreshDomain.planBlocks});
    }
    return saved;
  }

  Future<List<TodoPlanBlock>> savePlanBlocksCreated(
    String username,
    List<TodoPlanBlock> drafts, {
    required Future<void> Function(DatabaseExecutor executor) beforeWrite,
    bool sync = true,
  }) async {
    if (drafts.length < 2 ||
        drafts.length > 6 ||
        drafts.map((b) => b.id).toSet().length != drafts.length ||
        drafts.any(
          (b) =>
              b.id.isEmpty ||
              b.todoId != drafts.first.todoId ||
              b.status != TodoPlanStatus.planned ||
              b.isDeleted ||
              b.startTime <= 0 ||
              b.endTime <= b.startTime ||
              b.endTime - b.startTime != b.plannedMinutes * 60000 ||
              b.plannedMinutes < 15 ||
              b.plannedMinutes > 120 ||
              b.actualFocusSeconds != 0 ||
              b.pomodoroRecordIds.isNotEmpty ||
              b.calendarEventId != null,
        )) {
      throw StateError('分段新建内容无效');
    }
    final db = await DatabaseHelper.instance.databaseForUser(username);
    var created = false;
    final saved = await db.transaction((txn) async {
      final existing = <TodoPlanBlock>[];
      for (final draft in drafts) {
        final rows = await txn.query(
          'todo_plan_blocks',
          where: 'uuid=?',
          whereArgs: [draft.id],
        );
        if (rows.isNotEmpty) {
          final block = TodoPlanBlock.fromJson(rows.single);
          if (rows.single['has_conflict'] == 1 ||
              block.isDeleted ||
              block.status != TodoPlanStatus.planned ||
              block.actualFocusSeconds != 0 ||
              block.pomodoroRecordIds.isNotEmpty ||
              block.version != draft.version ||
              (block.titleSnapshot ?? '') != (draft.titleSnapshot ?? '') ||
              block.todoId != draft.todoId ||
              block.startTime != draft.startTime ||
              block.endTime != draft.endTime ||
              block.plannedMinutes != draft.plannedMinutes ||
              (block.remark ?? '') != (draft.remark ?? '') ||
              block.reminderMinutes != draft.reminderMinutes ||
              block.pomodoroMinutes != draft.pomodoroMinutes ||
              block.pomodoroRounds != draft.pomodoroRounds) {
            throw StateError('分段目标已存在或变化，请核对已有规划');
          }
          existing.add(block);
        }
      }
      if (existing.isNotEmpty && existing.length != drafts.length) {
        throw StateError('部分分段已存在，请核对已有规划；尚未新增任何分段');
      }
      await beforeWrite(txn);
      if (existing.isNotEmpty) return existing;
      final result = [
        for (final b in drafts) TodoPlanBlock.fromJson(b.toJson()),
      ];
      for (final block in result) {
        block.titleSnapshot ??= '';
        final data = block.toDbJson();
        await txn.insert('todo_plan_blocks', data);
        await txn.insert('op_logs', {
          'op_type': 'UPSERT',
          'target_table': 'todo_plan_blocks',
          'target_uuid': block.id,
          'data_json': jsonEncode(data),
          'timestamp': DateTime.now().millisecondsSinceEpoch,
          'is_synced': 0,
          'sync_error': '',
        });
      }
      created = true;
      return result;
    });
    if (created) {
      if (sync) requestSync(username);
      triggerRefresh(const {DataRefreshDomain.planBlocks});
    }
    return saved;
  }

  Future<TodoPlanBlock> savePlanBlockEdited(
    String username,
    TodoPlanBlock draft, {
    int? expectedVersion,
    int? expectedUpdatedAt,
    Future<void> Function(DatabaseExecutor executor)? beforeWrite,
    bool sync = true,
    TodoPlanStatus? newStatus,
  }) async {
    final db = await DatabaseHelper.instance.databaseForUser(username);
    final saved = await db.transaction((txn) async {
      final rows = await txn.query(
        'todo_plan_blocks',
        where: 'uuid = ?',
        whereArgs: [draft.id],
        limit: 1,
      );
      final existing = rows.isEmpty
          ? null
          : TodoPlanBlock.fromJson(rows.single);
      if (expectedVersion == null
          ? existing != null
          : existing == null ||
                existing.isDeleted ||
                existing.version != expectedVersion ||
                existing.updatedAt != expectedUpdatedAt) {
        throw StateError('规划已被修改或删除，请读取最新记录后重新编辑');
      }
      if (beforeWrite != null) await beforeWrite(txn);
      final result = existing == null
          ? TodoPlanBlock.fromJson(draft.toJson())
          : TodoPlanBlock.fromJson(existing.toJson());
      result
        ..todoId = draft.todoId
        ..titleSnapshot = draft.titleSnapshot ?? existing?.titleSnapshot ?? ''
        ..startTime = draft.startTime
        ..endTime = draft.endTime
        ..plannedMinutes = draft.plannedMinutes
        ..remark = draft.remark
        ..reminderMinutes = draft.reminderMinutes
        ..pomodoroMinutes = draft.pomodoroMinutes
        ..pomodoroRounds = draft.pomodoroRounds;
      if (newStatus != null) result.status = newStatus;
      if (existing != null) result.markAsChanged();
      final data = result.toDbJson();
      await txn.insert(
        'todo_plan_blocks',
        data,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      await txn.insert('op_logs', {
        'op_type': 'UPSERT',
        'target_table': 'todo_plan_blocks',
        'target_uuid': result.id,
        'data_json': jsonEncode(data),
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'is_synced': 0,
        'sync_error': '',
      });
      return result;
    });
    if (sync) requestSync(username);
    triggerRefresh(const {DataRefreshDomain.planBlocks});
    return saved;
  }

  Future<List<TodoPlanBlock>> getPlanBlocks(
    String username, {
    bool includeDeleted = false,
    DateTime? from,
    DateTime? to,
  }) async {
    try {
      final db = await DatabaseHelper.instance.databaseForUser(username);
      final where = <String>[];
      final whereArgs = <Object?>[];
      if (!includeDeleted) where.add('is_deleted = 0');
      if (from != null) {
        where.add('start_time >= ?');
        whereArgs.add(from.millisecondsSinceEpoch);
      }
      if (to != null) {
        where.add('start_time < ?');
        whereArgs.add(to.millisecondsSinceEpoch);
      }
      final List<Map<String, dynamic>> maps = await db.query(
        'todo_plan_blocks',
        where: where.isEmpty ? null : where.join(' AND '),
        whereArgs: whereArgs.isEmpty ? null : whereArgs,
      );

      if (maps.isNotEmpty) {
        if (maps.length > 50) {
          return await compute(_parsePlanBlockItemsIsolate, maps);
        }
        return maps.map((m) => TodoPlanBlock.fromJson(m)).toList();
      }
    } catch (e) {
      debugPrint("⚠️ PlanBlocks SQL 引擎异常: $e");
    }
    return [];
  }

  Future<List<TodoPlanBlock>> getPlanBlocksForReminderWindow(
    String username, {
    required DateTime now,
    required DateTime limit,
  }) async {
    try {
      final db = await DatabaseHelper.instance.databaseForUser(username);
      final maps = await db.query(
        'todo_plan_blocks',
        where:
            'is_deleted = 0 '
            'AND COALESCE(reminder_minutes, 5) > 0 '
            'AND start_time > ? '
            'AND start_time - COALESCE(reminder_minutes, 5) * 60000 < ?',
        whereArgs: [now.millisecondsSinceEpoch, limit.millisecondsSinceEpoch],
      );
      if (maps.length > 50) {
        return await compute(_parsePlanBlockItemsIsolate, maps);
      }
      return maps.map(TodoPlanBlock.fromJson).toList();
    } catch (e) {
      debugPrint('⚠️ Plan block reminder window read failed: $e');
      return [];
    }
  }

  Future<List<TodoPlanBlock>> getDashboardPlanBlocks(
    String username, {
    required DateTime now,
  }) async {
    try {
      final db = await DatabaseHelper.instance.databaseForUser(username);
      final nowMs = now.millisecondsSinceEpoch;
      final maps = await db.rawQuery(
        '''
        SELECT rowid AS _dashboard_rowid, * FROM todo_plan_blocks
        WHERE is_deleted = 0 AND end_time >= ?
        UNION ALL
        SELECT rowid AS _dashboard_rowid, * FROM todo_plan_blocks
        WHERE is_deleted = 0 AND status = ?
          AND (end_time < ? OR end_time IS NULL)
        ORDER BY _dashboard_rowid ASC
      ''',
        [nowMs, TodoPlanStatus.focusing.index, nowMs],
      );
      if (maps.length > 50) {
        return await compute(_parsePlanBlockItemsIsolate, maps);
      }
      return maps.map(TodoPlanBlock.fromJson).toList();
    } catch (e) {
      debugPrint("⚠️ Dashboard PlanBlocks SQL read failed: $e");
      return [];
    }
  }

  Future<void> deletePlanBlockGlobally(
    String username,
    String idToDelete,
  ) async {
    final blocks = await getPlanBlocks(username, includeDeleted: true);
    final index = blocks.indexWhere((b) => b.id == idToDelete);
    if (index != -1) {
      blocks[index].isDeleted = true;
      blocks[index].markAsChanged();
      await savePlanBlocks(username, [blocks[index]], sync: true);
    }
  }

  Future<List<TodoPlanBlock>> getPlanBlocksByTodo(
    String username,
    String todoId,
  ) async {
    try {
      final db = await DatabaseHelper.instance.databaseForUser(username);
      final maps = await db.query(
        'todo_plan_blocks',
        where: 'todo_uuid = ? AND is_deleted = 0',
        whereArgs: [todoId],
        orderBy: 'start_time ASC',
      );
      if (maps.length > 50) {
        return await compute(_parsePlanBlockItemsIsolate, maps);
      }
      return maps.map(TodoPlanBlock.fromJson).toList();
    } catch (e) {
      debugPrint('⚠️ PlanBlocks 按待办查询异常: $e');
      final all = await getPlanBlocks(username);
      return all.where((block) => block.todoId == todoId).toList();
    }
  }

  Future<List<TodoPlanBlock>> getPlanBlocksByDay(
    String username,
    DateTime day,
  ) async {
    final startOfDay = DateTime(
      day.year,
      day.month,
      day.day,
    ).millisecondsSinceEpoch;
    final endOfDay = DateTime(
      day.year,
      day.month,
      day.day + 1,
    ).millisecondsSinceEpoch;

    try {
      final db = await DatabaseHelper.instance.databaseForUser(username);
      final List<Map<String, dynamic>> maps = await db.query(
        'todo_plan_blocks',
        where: 'is_deleted = 0 AND start_time >= ? AND start_time < ?',
        whereArgs: [startOfDay, endOfDay],
        orderBy: 'start_time ASC',
      );

      if (maps.isNotEmpty) {
        if (maps.length > 50) {
          return await compute(_parsePlanBlockItemsIsolate, maps);
        }
        return maps.map((m) => TodoPlanBlock.fromJson(m)).toList();
      }
    } catch (e) {
      debugPrint("⚠️ PlanBlocks SQL 引擎异常: $e");
    }
    return [];
  }
}
