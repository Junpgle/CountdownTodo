part of 'storage_service.dart';
// ignore_for_file: annotate_overrides, unused_element, unused_element_parameter

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
          '🔓 [MemoryShield] Timeout auto-released recently resolved item: $uuid');
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

    final db = await DatabaseHelper.instance.database;
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
      final hasChanged = existing == null ||
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
    triggerRefresh();
  }

  Future<List<FixedScheduleItem>> getFixedSchedules(
    String username, {
    bool includeDeleted = false,
  }) async {
    try {
      final db = await DatabaseHelper.instance.database;
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

  Future<List<FixedScheduleItem>> getFixedSchedulesByDay(
    String username,
    DateTime day,
  ) async {
    final date = DateFormat('yyyy-MM-dd').format(day.toLocal());
    try {
      final db = await DatabaseHelper.instance.database;
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
  Future<List<HabitGoalRuleRevision>> getHabitRules({
    String? habitUuid,
  }) =>
      HabitStorage.getRuleRevisions(habitUuid: habitUuid);
  Future<void> saveHabitRules(
    List<HabitGoalRuleRevision> items,
  ) =>
      HabitStorage.saveRuleRevisions(items);
  Future<List<HabitCheckIn>> getHabitCheckIns({
    String? habitUuid,
    String? fromDate,
    String? toDate,
  }) =>
      HabitStorage.getCheckIns(
        habitUuid: habitUuid,
        fromDate: fromDate,
        toDate: toDate,
      );
  Future<void> saveHabitCheckIns(List<HabitCheckIn> items) =>
      HabitStorage.saveCheckIns(items);
  Future<void> savePlanBlocks(String username, List<TodoPlanBlock> items,
      {bool sync = true, bool isSyncSource = false}) async {
    final Map<String, TodoPlanBlock> dedupeMap = {};
    for (var item in items) {
      if (!dedupeMap.containsKey(item.id) ||
          item.updatedAt > dedupeMap[item.id]!.updatedAt) {
        dedupeMap[item.id] = item;
      }
    }

    final dedupeList = dedupeMap.values.toList();
    final db = await DatabaseHelper.instance.database;

    // 🚀 批量获取现有数据，用于审计
    Map<String, Map<String, dynamic>> existingItemsMap = {};
    if (!isSyncSource && dedupeList.isNotEmpty) {
      final uuids = dedupeList.map((e) => "'${e.id}'").join(',');
      final List<Map<String, dynamic>> existing = await db
          .rawQuery('SELECT * FROM todo_plan_blocks WHERE uuid IN ($uuids)');
      for (var row in existing) {
        existingItemsMap[row['uuid']] = row;
      }
    }

    final batch = db.batch();
    for (var item in dedupeList) {
      bool hasChanged = true;
      final itemData = item.toDbJson();
      final oldData = existingItemsMap[item.id];
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
          'updated_at'
        ]);
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
        batch.insert('todo_plan_blocks', itemData,
            conflictAlgorithm: ConflictAlgorithm.replace);
      }
    }

    if (dedupeList.isNotEmpty) {
      await batch.commit(noResult: true);
    }

    if (sync) requestSync(username);
    triggerRefresh();
  }

  Future<List<TodoPlanBlock>> getPlanBlocks(String username,
      {bool includeDeleted = false}) async {
    try {
      final db = await DatabaseHelper.instance.database;
      final List<Map<String, dynamic>> maps = await db.query('todo_plan_blocks',
          where: includeDeleted ? null : 'is_deleted = 0');

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

  List<TodoPlanBlock> _parsePlanBlockItemsIsolate(
      List<Map<String, dynamic>> maps) {
    return maps.map((m) => TodoPlanBlock.fromJson(m)).toList();
  }

  Future<void> deletePlanBlockGlobally(
      String username, String idToDelete) async {
    final blocks = await getPlanBlocks(username, includeDeleted: true);
    final index = blocks.indexWhere((b) => b.id == idToDelete);
    if (index != -1) {
      blocks[index].isDeleted = true;
      blocks[index].markAsChanged();
      await savePlanBlocks(username, [blocks[index]], sync: true);
    }
  }

  Future<List<TodoPlanBlock>> getPlanBlocksByTodo(
      String username, String todoId) async {
    final all = await getPlanBlocks(username);
    return all.where((b) => b.todoId == todoId).toList();
  }

  Future<List<TodoPlanBlock>> getPlanBlocksByDay(
      String username, DateTime day) async {
    final startOfDay =
        DateTime(day.year, day.month, day.day).millisecondsSinceEpoch;
    final endOfDay =
        DateTime(day.year, day.month, day.day + 1).millisecondsSinceEpoch;

    try {
      final db = await DatabaseHelper.instance.database;
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
