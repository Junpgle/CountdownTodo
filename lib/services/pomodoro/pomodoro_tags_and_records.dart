part of '../pomodoro_service.dart';

Future<T> _withRecordMutationQueue<T>(Future<T> Function() operation) async {
  final previousMutation = _recordMutationQueue;
  final releaseMutation = Completer<void>();
  _recordMutationQueue = releaseMutation.future;
  await previousMutation;
  try {
    return await operation();
  } finally {
    releaseMutation.complete();
  }
}

void _pomoDispose() {
  if (!_runStateCtrl.isClosed) _runStateCtrl.close();
}

// ── 私有助手：获取隔离的存储 Key ──────────────────────────
Future<String> _getScopedKey(String baseKey, {SharedPreferences? prefs}) async {
  final username = prefs != null
      ? prefs.getString(StorageService.keyCurrentUser)
      : await UserSessionStorage.getCurrentUsername();
  return StorageKeyScope.scoped(baseKey, username);
}

// ── 设置 ─────────────────────────────────────────────────

Future<PomodoroSettings> _pomoGetSettings() async {
  final prefs = await SharedPreferences.getInstance();
  final scopedKey = await _getScopedKey(_keySettings);
  String? s = prefs.getString(scopedKey);

  // 迁移检查
  if (s == null) {
    final String? username = prefs.getString(StorageService.keyCurrentUser);
    if (username != null && username.isNotEmpty) {
      final markerKey = "${_keySettings}_${username}_migrated";
      if (!(prefs.getBool(markerKey) ?? false)) {
        s = prefs.getString(_keySettings);
        if (s != null) {
          await prefs.setString(scopedKey, s);
          await prefs.setBool(markerKey, true);
        }
      }
    }
  }

  if (s == null) return PomodoroSettings();
  try {
    return PomodoroSettings.fromJson(jsonDecode(s));
  } catch (_) {
    return PomodoroSettings();
  }
}

Future<void> _pomoSaveSettings(PomodoroSettings settings) async {
  final prefs = await SharedPreferences.getInstance();
  final scopedKey = await _getScopedKey(_keySettings);
  await prefs.setString(scopedKey, jsonEncode(settings.toJson()));
  // 异步同步到云端（忽略失败）
  ApiService.syncPomodoroSettings(settings.toJson()).catchError((_) => false);
}

// ── 运行状态（防误杀）────────────────────────────────────

Future<PomodoroRunState?> _pomoLoadRunState() async {
  final prefs = await SharedPreferences.getInstance();
  final scopedKey = await _getScopedKey(_keyRunState, prefs: prefs);
  final s = prefs.getString(scopedKey);
  if (s == null) return null;
  try {
    return PomodoroRunState.fromJson(jsonDecode(s));
  } catch (_) {
    return null;
  }
}

Future<void> _pomoSaveRunState(PomodoroRunState state) async {
  final prefs = await SharedPreferences.getInstance();
  final scopedKey = await _getScopedKey(_keyRunState, prefs: prefs);
  await prefs.setString(scopedKey, jsonEncode(state.toJson()));
  _runStateCtrl.add(state); // 🚀 发送变更信号
}

Future<void> _pomoClearRunState() async {
  final prefs = await SharedPreferences.getInstance();
  final scopedKey = await _getScopedKey(_keyRunState, prefs: prefs);
  if (prefs.containsKey(scopedKey)) {
    await prefs.remove(scopedKey);
  }
  await FocusDoNotDisturbService.setActive(false, force: true);
  _runStateCtrl.add(null); // 🚀 发送清除信号
}

// ── 标签（本地 + 云端 Delta Sync）───────────────────────

Future<List<PomodoroTag>> _pomoGetTags() async {
  // 1. 优先 SQL
  try {
    final db = await DatabaseHelper.instance.database;
    final List<Map<String, dynamic>> maps = await db.query(
      'pomodoro_tags',
      where: 'is_deleted = 0',
    );
    if (maps.isNotEmpty) {
      return maps.map((m) => PomodoroTag.fromJson(m)).toList();
    }
  } catch (e) {
    // debugPrint("⚠️ Tag SQL 读取异常: $e");
  }

  // 2. 迁移逻辑
  final prefs = await SharedPreferences.getInstance();
  final scopedKey = await _getScopedKey(_keyTags);
  final migrationKey = "tags_migration_done_$scopedKey";

  if (!(prefs.getBool(migrationKey) ?? false)) {
    String? s = prefs.getString(scopedKey);
    if (s == null) {
      final username = prefs.getString(StorageService.keyCurrentUser);
      if (username != null) s = prefs.getString(_keyTags);
    }

    if (s != null) {
      // debugPrint("🚀 [Tags] 正在执行 Prefs -> SQL 迁移...");
      try {
        final List<dynamic> decoded = jsonDecode(s);
        final legacyTags = decoded.map((e) => PomodoroTag.fromJson(e)).toList();
        if (legacyTags.isNotEmpty) {
          await _saveTagsToSql(legacyTags);
        }
        await prefs.setBool(migrationKey, true);
        return legacyTags.where((t) => !t.isDeleted).toList();
      } catch (_) {}
    }
  }

  return [];
}

/// 获取所有标签（包括已删除的），用于识别未知标签
Future<List<PomodoroTag>> _pomoGetAllTagsIncludingDeleted() async {
  try {
    final db = await DatabaseHelper.instance.database;
    final List<Map<String, dynamic>> maps = await db.query('pomodoro_tags');
    if (maps.isNotEmpty) {
      return maps.map((m) => PomodoroTag.fromJson(m)).toList();
    }
  } catch (e) {
    // debugPrint("⚠️ Tag SQL 读取异常: $e");
  }
  return [];
}

Future<void> _saveTagsToSql(List<PomodoroTag> tags) async {
  final db = await DatabaseHelper.instance.database;
  final batch = db.batch();
  for (var t in tags) {
    batch.insert('pomodoro_tags', {
      'uuid': t.uuid,
      'name': t.name,
      'color': t.color,
      'is_deleted': t.isDeleted ? 1 : 0,
      'version': t.version,
      'created_at': t.createdAt,
      'updated_at': t.updatedAt,
      'has_conflict': t.hasConflict ? 1 : 0,
      'conflict_data': t.conflictData != null
          ? jsonEncode(t.conflictData)
          : null,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }
  await batch.commit(noResult: true);
}

/// 保存标签（自动检测丢失的项并转化为墓碑，防止云端同步时复活）
Future<void> _pomoSaveTags(
  List<PomodoroTag> tagsToSave, {
  bool isSyncSource = false,
}) async {
  final prefs = await SharedPreferences.getInstance();
  final scopedKey = await _getScopedKey(_keyTags);

  // 1. 获取全量（包含已删除）用于 Tombstone 处理
  final db = await DatabaseHelper.instance.database;
  final List<Map<String, dynamic>> maps = await db.query('pomodoro_tags');
  final List<PomodoroTag> allLocal = maps
      .map((m) => PomodoroTag.fromJson(m))
      .toList();

  // 将本次要保存的活动标签存入 Map
  final Map<String, PomodoroTag> newMap = {for (var t in tagsToSave) t.uuid: t};

  // 遍历本地全量历史数据，找回被“硬删除”的项和原有的墓碑
  for (var old in allLocal) {
    if (!newMap.containsKey(old.uuid)) {
      if (!old.isDeleted) {
        old.isDeleted = true;
        old.updatedAt = DateTime.now().millisecondsSinceEpoch;
        old.version += 1;
      }
      newMap[old.uuid] = old;
    }
  }

  final finalTags = newMap.values.toList();
  // 2. 写入 SQL & OpLog
  final batch = db.batch();
  for (var t in finalTags) {
    if (!isSyncSource) {
      batch.insert('op_logs', {
        'op_type': 'UPSERT',
        'target_table': 'pomodoro_tags',
        'target_uuid': t.uuid,
        'data_json': jsonEncode(t.toJson()),
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'is_synced': 0,
        'sync_error': '',
      });
    }
    batch.insert('pomodoro_tags', {
      'uuid': t.uuid,
      'name': t.name,
      'color': t.color,
      'is_deleted': t.isDeleted ? 1 : 0,
      'is_archived': t.isArchived ? 1 : 0,
      'version': t.version,
      'created_at': t.createdAt,
      'updated_at': t.updatedAt,
      'has_conflict': t.hasConflict ? 1 : 0,
      'conflict_data': t.conflictData != null
          ? jsonEncode(t.conflictData)
          : null,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }
  await batch.commit(noResult: true);

  // 3. 补齐 Prefs 备份
  await prefs.setString(
    scopedKey,
    jsonEncode(finalTags.map((t) => t.toJson()).toList()),
  );
}

/// 软删除一个标签（打上 tombstone 标记），以便同步时告诉云端删除
Future<void> _pomoDeleteTag(String uuid) async {
  final db = await DatabaseHelper.instance.database;
  final List<Map<String, dynamic>> maps = await db.query(
    'pomodoro_tags',
    where: 'uuid = ?',
    whereArgs: [uuid],
  );

  if (maps.isNotEmpty) {
    final tag = PomodoroTag.fromJson(maps.first);
    if (!tag.isDeleted) {
      tag.isDeleted = true;
      tag.updatedAt = DateTime.now().millisecondsSinceEpoch;
      tag.version += 1;

      final batch = db.batch();
      // 记录 OpLog
      batch.insert('op_logs', {
        'op_type': 'UPSERT',
        'target_table': 'pomodoro_tags',
        'target_uuid': tag.uuid,
        'data_json': jsonEncode(tag.toJson()),
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'is_synced': 0,
        'sync_error': '',
      });
      // 更新 SQL
      batch.update(
        'pomodoro_tags',
        {'is_deleted': 1, 'updated_at': tag.updatedAt, 'version': tag.version},
        where: 'uuid = ?',
        whereArgs: [uuid],
      );
      await batch.commit(noResult: true);

      // 更新 Prefs 备份
      final activeTags = await _pomoGetTags();
      await _pomoSaveTags(activeTags, isSyncSource: true);

      // 立即触发同步
      final username = await SharedPreferences.getInstance().then(
        (p) => p.getString(StorageService.keyCurrentUser) ?? '',
      );
      if (username.isNotEmpty) {
        StorageService.requestSync(username);
      }
    }
  }
}

Future<void> _pomoSyncTagsToCloud() async {
  final prefs = await SharedPreferences.getInstance();
  final scopedKey = await _getScopedKey(_keyTags);
  final s = prefs.getString(scopedKey);
  if (s == null) return;
  final allTags = (jsonDecode(s) as List)
      .map((e) => PomodoroTag.fromJson(e))
      .toList();
  if (allTags.isEmpty) return;
  final ok = await ApiService.syncPomodoroTags(
    allTags.map((t) => t.toJson()).toList(),
  );
  if (ok) {
    final db = await DatabaseHelper.instance.database;
    await db.update(
      'op_logs',
      {'is_synced': 1, 'sync_error': ''},
      where: 'is_synced = 0 AND target_table = ?',
      whereArgs: ['pomodoro_tags'],
    );
    final lastSyncKey = await _getScopedKey('pomodoro_last_tag_sync');
    await prefs.setInt(lastSyncKey, DateTime.now().millisecondsSinceEpoch);
  }
}

Future<void> _pomoSyncTagsFromCloud() async {
  final remoteList = await ApiService.fetchPomodoroTags();
  if (remoteList.isEmpty) return;
  final remoteTags = remoteList
      .map((e) => PomodoroTag.fromJson(e as Map<String, dynamic>))
      .toList();
  // 读取所有本地标签（含已删除）
  final prefs = await SharedPreferences.getInstance();
  final scopedKey = await _getScopedKey(_keyTags);
  // 优先读当前账号隔离 key，兼容回退旧全局 key
  final s = prefs.getString(scopedKey) ?? prefs.getString(_keyTags);
  final localAll = s == null
      ? <PomodoroTag>[]
      : (jsonDecode(s) as List).map((e) => PomodoroTag.fromJson(e)).toList();
  final Map<String, PomodoroTag> merged = {for (var t in localAll) t.uuid: t};
  for (final rt in remoteTags) {
    final ex = merged[rt.uuid];
    if (ex == null || rt.updatedAt > ex.updatedAt) merged[rt.uuid] = rt;
  }
  await _pomoSaveTags(merged.values.toList(), isSyncSource: true);
}

// ── 专注记录（本地缓存 + 云端上传）─────────────────────

/// 读取有效记录（不含已删除）
Future<List<PomodoroRecord>> _pomoGetRecords() async {
  final all = await _getAllRecordsRaw();
  return all.where((r) => !r.isDeleted).toList();
}

/// Reads only the newest active record for summary surfaces.
/// Falls back to the full reader when SQL has no active row so legacy
/// preference data can still be migrated exactly as before.
Future<PomodoroRecord?> _pomoGetLatestRecord() async {
  try {
    final db = await DatabaseHelper.instance.database;
    final rows = await db.query(
      'pomodoro_records',
      where: 'is_deleted = 0',
      orderBy: 'start_time DESC',
      limit: 1,
    );
    if (rows.isNotEmpty) {
      unawaited(_clearRecordPrefsMirror());
      return PomodoroRecord.fromJson(rows.first);
    }
  } catch (_) {
    // Preserve the legacy migration and recovery path below.
  }
  final records = await _pomoGetRecords();
  return records.isEmpty ? null : records.first;
}

Future<void> _saveRecordsToSql(List<PomodoroRecord> records) async {
  final db = await DatabaseHelper.instance.database;
  final batch = db.batch();
  for (var r in records) {
    batch.insert('pomodoro_records', {
      'uuid': r.uuid,
      'todo_uuid': r.todoUuid,
      'todo_title': r.todoTitle,
      'tag_uuids': jsonEncode(r.tagUuids),
      'start_time': r.startTime,
      'end_time': r.endTime,
      'planned_duration': r.plannedDuration,
      'actual_duration': r.actualDuration,
      'status': _pomoStatusStr(r.status),
      'device_id': r.deviceId,
      'plan_block_id': r.planBlockId,
      'note': r.note,
      'total_pause_seconds': r.totalPauseSeconds,
      'pause_intervals': r.pauseIntervals != null
          ? jsonEncode(r.pauseIntervals!.map((e) => e.toJson()).toList())
          : null,
      'is_deleted': r.isDeleted ? 1 : 0,
      'version': r.version,
      'created_at': r.createdAt,
      'updated_at': r.updatedAt,
      'has_conflict': r.hasConflict ? 1 : 0,
      'conflict_data': r.conflictData != null
          ? jsonEncode(r.conflictData)
          : null,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }
  await batch.commit(noResult: true);
}

Future<void> _saveRecords(List<PomodoroRecord> records) async {
  // 🚀 双轨存储：优先 SQL
  await _saveRecordsToSql(records);

  // SQL 已是主存储。全量记录 JSON 写入 SharedPreferences 会通过
  // Android MethodChannel 传输超大字符串，在低内存设备上触发 OOM。
  await _clearRecordPrefsMirror();
}

/// 添加一条专注记录，本地保存后立即尝试上传云端
Future<void> _pomoAddRecord(
  PomodoroRecord record, {
  bool isSyncSource = false,
}) async {
  // Serialize record writes with each other and with cloud merges so the
  // plan-block delta always compares against the latest stored record.
  await _withRecordMutationQueue<void>(
    () => _addRecord(record, isSyncSource: isSyncSource),
  );
}

Future<void> _addRecord(
  PomodoroRecord record, {
  required bool isSyncSource,
}) async {
  // 1. 写入 SQLite & OpLog
  final db = await DatabaseHelper.instance.database;
  final previousRows = await db.query(
    'pomodoro_records',
    where: 'uuid = ?',
    whereArgs: [record.uuid],
    limit: 1,
  );
  final previousRecord = previousRows.isEmpty
      ? null
      : PomodoroRecord.fromJson(previousRows.first);
  final batch = db.batch();

  if (!isSyncSource) {
    batch.insert('op_logs', {
      'op_type': 'UPSERT',
      'target_table': 'pomodoro_records',
      'target_uuid': record.uuid,
      'data_json': jsonEncode(record.toJson()),
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'is_synced': 0,
      'sync_error': '',
    });
  }

  batch.insert('pomodoro_records', {
    'uuid': record.uuid,
    'todo_uuid': record.todoUuid,
    'todo_title': record.todoTitle,
    'tag_uuids': jsonEncode(record.tagUuids),
    'start_time': record.startTime,
    'end_time': record.endTime,
    'planned_duration': record.plannedDuration,
    'actual_duration': record.actualDuration,
    'status': _pomoStatusStr(record.status),
    'device_id': record.deviceId,
    'plan_block_id': record.planBlockId,
    'note': record.note,
    'total_pause_seconds': record.totalPauseSeconds,
    'pause_intervals': record.pauseIntervals != null
        ? jsonEncode(record.pauseIntervals!.map((e) => e.toJson()).toList())
        : null,
    'is_deleted': record.isDeleted ? 1 : 0,
    'version': record.version,
    'created_at': record.createdAt,
    'updated_at': record.updatedAt,
  }, conflictAlgorithm: ConflictAlgorithm.replace);

  await batch.commit(noResult: true);

  // 2. 清理旧 Prefs 备份，避免 shared_preferences 通过 MethodChannel
  // 写入全量记录 JSON 导致 Android OOM。
  final prefs = await SharedPreferences.getInstance();
  await _clearRecordPrefsMirror(prefs: prefs);

  await _updateLinkedPlanBlocks(
    previousRecord,
    record,
    isSyncSource: isSyncSource,
  );

  // debugPrint(
  //     '[PomodoroService] addRecord OK (SQL+Cache), uuid=${record.uuid}');

  StorageService.triggerRefresh({DataRefreshDomain.pomodoro});

  // 3. 立即尝试同步
  if (!isSyncSource) {
    final username = prefs.getString(StorageService.keyCurrentUser) ?? '';
    if (username.isNotEmpty) {
      StorageService.requestSync(username);
    }
  }
}

Future<void> _updateLinkedPlanBlocks(
  PomodoroRecord? previousRecord,
  PomodoroRecord record, {
  required bool isSyncSource,
}) async {
  final affectedBlockIds = <String>{
    if (previousRecord?.planBlockId?.isNotEmpty == true)
      previousRecord!.planBlockId!,
    if (record.planBlockId?.isNotEmpty == true) record.planBlockId!,
  };
  if (affectedBlockIds.isEmpty) return;

  final prefs = await SharedPreferences.getInstance();
  final username = prefs.getString(StorageService.keyCurrentUser) ?? 'default';
  try {
    final db = await DatabaseHelper.instance.databaseForUser(username);
    final where = <String>[];
    final whereArgs = <Object?>[];
    if (affectedBlockIds.isNotEmpty) {
      where.add(
        'uuid IN (${List.filled(affectedBlockIds.length, '?').join(', ')})',
      );
      whereArgs.addAll(affectedBlockIds);
    }
    // Legacy records may only be linked through the block's CSV UUID list.
    where.add(
      "INSTR(',' || COALESCE(pomodoro_record_ids, '') || ',', ',' || ? || ',') > 0",
    );
    whereArgs.add(record.uuid);
    final rows = await db.query(
      'todo_plan_blocks',
      where: '(${where.join(' OR ')})',
      whereArgs: whereArgs,
      orderBy: 'rowid ASC',
    );
    final blocks = rows.map(TodoPlanBlock.fromJson).toList();
    for (final block in blocks) {
      final containsLegacyLink = block.pomodoroRecordIds.contains(record.uuid);
      if (!affectedBlockIds.contains(block.uuid) && !containsLegacyLink) {
        continue;
      }

      final previouslyLinked =
          previousRecord != null &&
          !previousRecord.isDeleted &&
          (previousRecord.planBlockId == block.uuid ||
              ((previousRecord.planBlockId?.isEmpty ?? true) &&
                  containsLegacyLink));
      final currentlyLinked =
          !record.isDeleted && record.planBlockId == block.uuid;
      final previousSeconds = previouslyLinked
          ? previousRecord.effectiveDuration
          : 0;
      final currentSeconds = currentlyLinked ? record.effectiveDuration : 0;
      final secondsDelta = currentSeconds - previousSeconds;

      var oldLinkCount = 0;
      block.pomodoroRecordIds.removeWhere((uuid) {
        final matches = uuid == record.uuid;
        if (matches) oldLinkCount++;
        return matches;
      });
      if (currentlyLinked) block.pomodoroRecordIds.add(record.uuid);
      final linkChanged = currentlyLinked
          ? oldLinkCount != 1
          : oldLinkCount != 0;

      if (secondsDelta == 0 && !linkChanged) continue;

      block.actualFocusSeconds = max(
        0,
        block.actualFocusSeconds + secondsDelta,
      );
      if (secondsDelta != 0 &&
          (block.status == TodoPlanStatus.planned ||
              block.status == TodoPlanStatus.focusing)) {
        if (block.actualFocusSeconds >= block.plannedMinutes * 60 * 0.8) {
          block.status = TodoPlanStatus.finished;
        } else {
          block.status = TodoPlanStatus.planned;
        }
      }
      block.markAsChanged();
      await StorageService.savePlanBlocks(
        username,
        [block],
        sync: !isSyncSource,
        isSyncSource: isSyncSource,
      );
    }
  } catch (_) {
    // Keep the Pomodoro record write available if its plan block is missing
    // or its independent storage update fails.
  }
}

/// Rebuilds derived plan progress after the outer data sync saves its
/// snapshot of plan blocks, which may predate the Pomodoro record merge.
Future<void> _pomoReconcilePlanBlockProgress(String username) async {
  try {
    final blocks = await StorageService.getPlanBlocks(
      username,
      includeDeleted: true,
    );
    if (blocks.isEmpty) return;

    final db = await DatabaseHelper.instance.databaseForUser(username);
    final recordRows = await db.query(
      'pomodoro_records',
      where: 'is_deleted = 0',
    );
    final records = recordRows.map(PomodoroRecord.fromJson).toList();
    final linkedSecondsByBlock =
        PomodoroPlanFocusAllocator.linkedSecondsByBlock(
          blocks: blocks,
          records: records,
        );
    final recordsByPlanBlock = <String, List<PomodoroRecord>>{};
    final legacyRecordsByUuid = <String, PomodoroRecord>{};
    final recordOrderByUuid = <String, int>{};
    for (var index = 0; index < records.length; index++) {
      final record = records[index];
      final planBlockId = record.planBlockId;
      if (planBlockId != null) {
        (recordsByPlanBlock[planBlockId] ??= <PomodoroRecord>[]).add(record);
      }
      if (planBlockId == null || planBlockId.isEmpty) {
        legacyRecordsByUuid[record.uuid] = record;
      }
      recordOrderByUuid[record.uuid] = index;
    }

    for (var blockIndex = 0; blockIndex < blocks.length; blockIndex++) {
      final block = blocks[blockIndex];
      if (block.isDeleted) continue;
      final linkedRecordsByUuid = <String, PomodoroRecord>{
        for (final record in recordsByPlanBlock[block.uuid] ?? const [])
          record.uuid: record,
      };
      for (final recordUuid in block.pomodoroRecordIds.toSet()) {
        final legacyRecord = legacyRecordsByUuid[recordUuid];
        if (legacyRecord != null) {
          linkedRecordsByUuid.putIfAbsent(recordUuid, () => legacyRecord);
        }
      }
      final linkedRecords = linkedRecordsByUuid.values.toList()
        ..sort(
          (left, right) => recordOrderByUuid[left.uuid]!.compareTo(
            recordOrderByUuid[right.uuid]!,
          ),
        );
      final actualFocusSeconds = linkedSecondsByBlock[blockIndex];
      final linkedRecordIds = linkedRecords
          .map((record) => record.uuid)
          .toSet();
      final currentRecordIds = block.pomodoroRecordIds.toSet();
      final linksChanged =
          linkedRecordIds.length != block.pomodoroRecordIds.length ||
          !linkedRecordIds.containsAll(currentRecordIds) ||
          !currentRecordIds.containsAll(linkedRecordIds);
      var statusChanged = false;
      if (actualFocusSeconds > 0 &&
          (block.status == TodoPlanStatus.planned ||
              block.status == TodoPlanStatus.focusing)) {
        final nextStatus = actualFocusSeconds >= block.plannedMinutes * 60 * 0.8
            ? TodoPlanStatus.finished
            : block.status == TodoPlanStatus.focusing
            ? TodoPlanStatus.planned
            : block.status;
        statusChanged = block.status != nextStatus;
        block.status = nextStatus;
      }

      if (block.actualFocusSeconds == actualFocusSeconds &&
          !linksChanged &&
          !statusChanged) {
        continue;
      }
      block.actualFocusSeconds = actualFocusSeconds;
      if (linksChanged) block.pomodoroRecordIds = linkedRecordIds.toList();
      block.markAsChanged();
      await StorageService.savePlanBlocks(
        username,
        [block],
        sync: false,
        isSyncSource: true,
      );
    }
  } catch (_) {
    // Plan progress is derived data; it must not fail the account sync.
  }
}

/// 按半开时间范围 `[from, to)` 查询有效记录。
Future<List<PomodoroRecord>> _pomoGetRecordsInRange(
  DateTime from,
  DateTime to,
) async {
  try {
    final db = await DatabaseHelper.instance.database;
    final List<Map<String, dynamic>> maps = await db.query(
      'pomodoro_records',
      where: 'is_deleted = 0 AND start_time >= ? AND start_time < ?',
      whereArgs: [from.millisecondsSinceEpoch, to.millisecondsSinceEpoch],
      orderBy: 'start_time DESC',
    );
    if (maps.isNotEmpty) {
      return maps.map((m) => PomodoroRecord.fromJson(m)).toList();
    }
    final hasSqlRecords = await db.rawQuery(
      'SELECT 1 FROM pomodoro_records LIMIT 1',
    );
    if (hasSqlRecords.isNotEmpty) {
      unawaited(_clearRecordPrefsMirror());
      return [];
    }
  } catch (e) {
    // debugPrint("⚠️ Pomodoro SQL 范围查询异常: $e");
  }

  // 逃生通道：Dart 内存过滤
  final all = await _pomoGetRecords();
  final fromMs = from.millisecondsSinceEpoch;
  final toMs = to.millisecondsSinceEpoch;
  return all.where((r) => r.startTime >= fromMs && r.startTime < toMs).toList();
}

/// 按半开时间范围读取专注统计所需的轻量字段。
/// 年视图只显示汇总，不需要解码备注、暂停区间等完整记录内容。
Future<List<PomodoroSessionSummary>> _pomoGetSessionSummariesInRange(
  DateTime from,
  DateTime to, {
  DateTime? tagsFrom,
  DateTime? tagsTo,
}) async {
  try {
    final db = await DatabaseHelper.instance.database;
    final maps = await db.query(
      'pomodoro_records',
      columns: const [
        'start_time',
        'actual_duration',
        'planned_duration',
        'status',
        'tag_uuids',
      ],
      where: 'is_deleted = 0 AND start_time >= ? AND start_time < ?',
      whereArgs: [from.millisecondsSinceEpoch, to.millisecondsSinceEpoch],
    );
    if (maps.isNotEmpty) {
      final tagsFromMs = tagsFrom?.millisecondsSinceEpoch;
      final tagsToMs = tagsTo?.millisecondsSinceEpoch;
      return maps.map((values) {
        final startTime = JsonValueParser.toInt(
          values['start_time'],
          fallback: 0,
        );
        final includeTagUuids =
            tagsFromMs == null ||
            tagsToMs == null ||
            (startTime >= tagsFromMs && startTime < tagsToMs);
        return PomodoroSessionSummary.fromDatabaseMap(
          values,
          includeTagUuids: includeTagUuids,
        );
      }).toList();
    }

    final activeCount =
        Sqflite.firstIntValue(
          await db.rawQuery(
            'SELECT COUNT(*) FROM pomodoro_records WHERE is_deleted = 0',
          ),
        ) ??
        0;
    if (activeCount > 0) return const [];
  } catch (_) {
    // 保留旧版偏好设置数据和不支持 SQL 的平台的兼容路径。
  }

  final records = await _pomoGetRecordsInRange(from, to);
  final tagsFromMs = tagsFrom?.millisecondsSinceEpoch;
  final tagsToMs = tagsTo?.millisecondsSinceEpoch;
  return records.map((record) {
    final includeTagUuids =
        tagsFromMs == null ||
        tagsToMs == null ||
        (record.startTime >= tagsFromMs && record.startTime < tagsToMs);
    return PomodoroSessionSummary.fromRecord(
      record,
      includeTagUuids: includeTagUuids,
    );
  }).toList();
}

// ── 统计工具 ─────────────────────────────────────────────

/// 总专注时长（秒），使用 effectiveDuration
int _pomoTotalFocusSeconds(List<PomodoroRecord> records) =>
    records.fold(0, (sum, r) => sum + r.effectiveDuration);

/// 按标签统计专注时长（秒）
Map<String, int> _pomoFocusByTag(List<PomodoroRecord> records) {
  final Map<String, int> result = {};
  for (final r in records) {
    for (final uuid in r.tagUuids) {
      result[uuid] = (result[uuid] ?? 0) + r.effectiveDuration;
    }
    if (r.tagUuids.isEmpty) {
      result['__none__'] = (result['__none__'] ?? 0) + r.effectiveDuration;
    }
  }
  return result;
}

/// 格式化时长
String _pomoFormatDuration(int totalSeconds) =>
    formatDurationChinese(totalSeconds);
