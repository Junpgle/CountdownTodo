part of '../pomodoro_service.dart';

// ── 增量同步：从云端拉取并合并到本地 ────────────────────────

/// 从云端增量拉取专注记录（LWW 合并），返回是否有新增/变更
Future<bool> _pomoSyncRecordsFromCloud({
  int? fromMs,
  bool forceFullSync = false,
  http.Client? client,
}) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    // 获取上次拉取的时间戳，默认从 0 开始
    final lastDownloadKey = await _getScopedKey(_keyLastRecordDownload);

    int effectiveFromMs;
    if (forceFullSync) {
      effectiveFromMs = 0;
    } else if (fromMs != null) {
      effectiveFromMs = fromMs;
    } else {
      effectiveFromMs = prefs.getInt(lastDownloadKey) ?? 0;
      if (effectiveFromMs > 0) {
        effectiveFromMs -= 3600 * 1000; // 增量同步保留 1 小时回看窗口
      }
    }

    // debugPrint(
    //   '[PomodoroService] syncRecordsFromCloud forceFullSync=$forceFullSync, fromMs=$effectiveFromMs',
    // );

    final recordsRaw = await ApiService.fetchPomodoroSessions(
      fromMs: effectiveFromMs,
      includeDeleted: true,
      useUpdatedAt: true,
      client: client,
    );

    final remoteRecords = recordsRaw
        .map((e) => PomodoroRecord.fromJson(e as Map<String, dynamic>))
        .toList();

    return await _withRecordMutationQueue(() async {
      final db = await DatabaseHelper.instance.database;
      // 读取本地全量（SQL + 旧 prefs 兜底），避免只写入 prefs 导致 UI 读不到
      final sqlRows = await db.query(
        'pomodoro_records',
        orderBy: 'start_time DESC',
      );
      final sqlRecords = sqlRows
          .map((m) => PomodoroRecord.fromJson(m))
          .toList();

      final scopedKey = await _getScopedKey(_keyRecords, prefs: prefs);
      String? legacyRaw;
      if (sqlRows.isEmpty) {
        legacyRaw = prefs.getString(scopedKey) ?? prefs.getString(_keyRecords);
      } else {
        await _clearRecordPrefsMirror(prefs: prefs);
      }
      final legacyRecords = legacyRaw == null
          ? <PomodoroRecord>[]
          : (jsonDecode(legacyRaw) as List)
                .map((e) => PomodoroRecord.fromJson(e))
                .toList();

      final Map<String, PomodoroRecord> merged = {
        for (var r in sqlRecords) r.uuid: r,
      };
      for (final lr in legacyRecords) {
        final ex = merged[lr.uuid];
        if (ex == null || lr.updatedAt > ex.updatedAt) {
          merged[lr.uuid] = lr;
        }
      }
      bool hasChange = false;
      final planProgressChanges =
          <({PomodoroRecord? previous, PomodoroRecord current})>[];

      for (final rr in remoteRecords) {
        final ex = merged[rr.uuid];
        if (ex == null) {
          // 本地没有 → 直接用云端
          merged[rr.uuid] = rr;
          planProgressChanges.add((previous: null, current: rr));
          hasChange = true;
        } else {
          // 合并策略：
          // 1. 云端更新时间更新 → 采用云端数据为主
          // 2. 任何情况下：若云端有 tagUuids/todoTitle 而本地没有 → 补全（修复旧记录标签丢失）
          final cloudNewer =
              rr.updatedAt > ex.updatedAt ||
              (rr.updatedAt == ex.updatedAt && rr.version > ex.version);
          final needPatch =
              (rr.tagUuids.isNotEmpty && ex.tagUuids.isEmpty) ||
              (rr.todoTitle?.isNotEmpty == true && ex.todoTitle == null) ||
              (rr.planBlockId?.isNotEmpty == true && ex.planBlockId == null) ||
              (rr.note?.isNotEmpty == true && ex.note == null);
          if (cloudNewer || needPatch) {
            final updated = PomodoroRecord(
              uuid: rr.uuid,
              todoUuid: rr.todoUuid ?? ex.todoUuid,
              todoTitle: (rr.todoTitle?.isNotEmpty == true)
                  ? rr.todoTitle
                  : ex.todoTitle,
              tagUuids: rr.tagUuids.isNotEmpty ? rr.tagUuids : ex.tagUuids,
              startTime: cloudNewer ? rr.startTime : ex.startTime,
              endTime: cloudNewer ? rr.endTime : ex.endTime,
              plannedDuration: cloudNewer
                  ? rr.plannedDuration
                  : ex.plannedDuration,
              actualDuration: cloudNewer
                  ? rr.actualDuration
                  : ex.actualDuration,
              status: cloudNewer ? rr.status : ex.status,
              deviceId: rr.deviceId ?? ex.deviceId,
              planBlockId: cloudNewer
                  ? (rr.planBlockId ?? ex.planBlockId)
                  : (ex.planBlockId ?? rr.planBlockId),
              note: cloudNewer ? (rr.note ?? ex.note) : (ex.note ?? rr.note),
              totalPauseSeconds: cloudNewer
                  ? (rr.totalPauseSeconds ?? ex.totalPauseSeconds)
                  : (ex.totalPauseSeconds ?? rr.totalPauseSeconds),
              pauseIntervals: cloudNewer
                  ? (rr.pauseIntervals ?? ex.pauseIntervals)
                  : (ex.pauseIntervals ?? rr.pauseIntervals),
              isDeleted: cloudNewer ? rr.isDeleted : ex.isDeleted,
              version: cloudNewer ? rr.version : ex.version,
              createdAt: ex.createdAt,
              updatedAt: cloudNewer ? rr.updatedAt : ex.updatedAt,
              hasConflict: cloudNewer ? rr.hasConflict : ex.hasConflict,
              conflictData: cloudNewer ? rr.conflictData : ex.conflictData,
            );
            merged[rr.uuid] = updated;
            planProgressChanges.add((previous: ex, current: updated));
            hasChange = true;
          }
        }
      }

      final mergedRecords = merged.values.toList()
        ..sort((a, b) => b.startTime.compareTo(a.startTime));

      // 只要本次读到了旧 prefs 数据，或云端有变化，就同步回 SQL + prefs，确保统计页和历史页可见
      if (hasChange || legacyRecords.isNotEmpty || sqlRows.isEmpty) {
        await _saveRecords(mergedRecords);
      }
      for (final change in planProgressChanges) {
        await _updateLinkedPlanBlocks(
          change.previous,
          change.current,
          isSyncSource: true,
        );
      }

      // 更新最后拉取时间戳为当前服务器时间（或是本地当前时间，取决于业务场景）
      // 这里用本次拉取到的最新记录的 updatedAt 作为下次请求的起点
      int latestTs = 0;
      for (final r in remoteRecords) {
        if (r.updatedAt > latestTs) latestTs = r.updatedAt;
      }
      if (latestTs > 0) {
        final lastDownloadKey = await _getScopedKey(_keyLastRecordDownload);
        await prefs.setInt(lastDownloadKey, latestTs);
        // 🚀 同步更新 lastUpload，防止 syncRecordsToCloud 的时间窗口
        // 再次命中刚从云端拉下来的记录，导致上传→广播→下载→上传死循环
        final lastUploadKey = await _getScopedKey(_keyLastRecordUpload);
        final currentUpload = prefs.getInt(lastUploadKey) ?? 0;
        if (latestTs > currentUpload) {
          await prefs.setInt(lastUploadKey, latestTs);
        }
      }

      return hasChange;
    });
  } catch (e) {
    // debugPrint('[PomodoroService] syncRecordsFromCloud error: $e');
    return false;
  }
}

Future<bool> _pomoMergeRecordsLww(List<PomodoroRecord> remoteRecords) =>
    _withRecordMutationQueue(() => _mergeRecordsLww(remoteRecords));

Future<bool> _mergeRecordsLww(List<PomodoroRecord> remoteRecords) async {
  if (remoteRecords.isEmpty) return false;
  final localRecords = await _getAllRecordsRaw();
  final merged = {for (final r in localRecords) r.uuid: r};
  var hasChange = false;
  final planProgressChanges =
      <({PomodoroRecord? previous, PomodoroRecord current})>[];

  for (final remote in remoteRecords) {
    final existing = merged[remote.uuid];
    if (existing == null) {
      merged[remote.uuid] = remote;
      planProgressChanges.add((previous: null, current: remote));
      hasChange = true;
      continue;
    }

    final remoteWins =
        remote.updatedAt > existing.updatedAt ||
        (remote.updatedAt == existing.updatedAt &&
            remote.version > existing.version);
    final needsPatch =
        (remote.tagUuids.isNotEmpty && existing.tagUuids.isEmpty) ||
        (remote.todoTitle?.isNotEmpty == true && existing.todoTitle == null) ||
        (remote.planBlockId?.isNotEmpty == true &&
            existing.planBlockId == null) ||
        (remote.note?.isNotEmpty == true && existing.note == null);

    if (remoteWins) {
      merged[remote.uuid] = remote;
      planProgressChanges.add((previous: existing, current: remote));
      hasChange = true;
    } else if (needsPatch) {
      final updated = PomodoroRecord(
        uuid: existing.uuid,
        todoUuid: existing.todoUuid ?? remote.todoUuid,
        todoTitle: existing.todoTitle ?? remote.todoTitle,
        tagUuids: existing.tagUuids.isNotEmpty
            ? existing.tagUuids
            : remote.tagUuids,
        startTime: existing.startTime,
        endTime: existing.endTime,
        plannedDuration: existing.plannedDuration,
        actualDuration: existing.actualDuration,
        status: existing.status,
        deviceId: existing.deviceId ?? remote.deviceId,
        planBlockId: existing.planBlockId ?? remote.planBlockId,
        note: existing.note ?? remote.note,
        totalPauseSeconds:
            existing.totalPauseSeconds ?? remote.totalPauseSeconds,
        pauseIntervals: existing.pauseIntervals ?? remote.pauseIntervals,
        isDeleted: existing.isDeleted,
        version: existing.version,
        createdAt: existing.createdAt,
        updatedAt: existing.updatedAt,
        hasConflict: existing.hasConflict,
        conflictData: existing.conflictData,
      );
      merged[remote.uuid] = updated;
      planProgressChanges.add((previous: existing, current: updated));
      hasChange = true;
    }
  }

  if (hasChange) {
    final records = merged.values.toList()
      ..sort((a, b) => b.startTime.compareTo(a.startTime));
    await _saveRecords(records);
  }
  for (final change in planProgressChanges) {
    await _updateLinkedPlanBlocks(
      change.previous,
      change.current,
      isSyncSource: true,
    );
  }
  return hasChange;
}

Future<void> _pomoSyncRecordsToCloud({
  bool forceFullSync = false,
  http.Client? client,
}) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final db = await DatabaseHelper.instance.database;
    final lastUploadKey = await _getScopedKey(_keyLastRecordUpload);
    final lastUpload = prefs.getInt(lastUploadKey) ?? 0;
    final recoveryUploadKey = await _getScopedKey(_keyLastRecordRecoveryUpload);
    final lastRecoveryUpload = prefs.getInt(recoveryUploadKey) ?? 0;
    final all = await _getAllRecordsRaw();
    if (all.isEmpty) return;
    final pendingOps = await db.query(
      'op_logs',
      where: 'is_synced = 0 AND target_table = ?',
      whereArgs: ['pomodoro_records'],
      orderBy: 'timestamp ASC',
    );

    final Map<String, PomodoroRecord> dedup = {};
    final operationIdsByRecord = <String, List<Object>>{};

    if (!forceFullSync) {
      for (final op in pendingOps) {
        final raw = op['data_json']?.toString();
        if (raw == null || raw.isEmpty) continue;
        try {
          final j = jsonDecode(raw);
          late final PomodoroRecord record;
          if (j is Map<String, dynamic>) {
            record = PomodoroRecord.fromJson(j);
          } else if (j is Map) {
            record = PomodoroRecord.fromJson(j.cast<String, dynamic>());
          } else {
            continue;
          }
          dedup[record.uuid] = record;
          final operationId = op['id'];
          if (operationId != null) {
            operationIdsByRecord
                .putIfAbsent(record.uuid, () => <Object>[])
                .add(operationId);
          }
        } catch (_) {}
      }

      // One-time recovery window for records whose op_logs were consumed by
      // the main sync before Pomodoro upload ran. Advancing a separate
      // recovery watermark prevents repeated WebSocket broadcast loops.
      final recoveryWindowStart = lastUpload > 0
          ? lastUpload - const Duration(days: 2).inMilliseconds
          : 0;
      final uploadWindowStart = max(recoveryWindowStart, lastRecoveryUpload);
      for (final r in all) {
        if (r.updatedAt > uploadWindowStart) {
          dedup[r.uuid] = r;
        }
      }
    } else {
      // forceFullSync: 上传全量
      for (final r in all) {
        dedup[r.uuid] = r;
      }
    }

    final dirty = dedup.values.toList();
    final uploadedRecordIds = dedup.keys.toSet();
    final operationIdsToAcknowledge = <Object>{};
    if (forceFullSync) {
      final localRecordIds = all.map((record) => record.uuid).toSet();
      for (final op in pendingOps) {
        final operationId = op['id'];
        final recordId = op['target_uuid']?.toString();
        if (operationId != null && localRecordIds.contains(recordId)) {
          operationIdsToAcknowledge.add(operationId);
        }
      }
    } else {
      for (final entry in operationIdsByRecord.entries) {
        if (uploadedRecordIds.contains(entry.key)) {
          operationIdsToAcknowledge.addAll(entry.value);
        }
      }
    }

    // debugPrint(
    //   '[PomodoroService] syncRecordsToCloud forceFullSync=$forceFullSync, upload=${dirty.length}/${all.length}',
    // );
    if (dirty.isEmpty) return;
    final ok = await ApiService.uploadPomodoroRecords(
      dirty.map((r) => r.toJson()).toList(),
      client: client,
    );
    if (ok) {
      var latestUploadedAt = lastRecoveryUpload;
      for (final r in dirty) {
        if (r.updatedAt > latestUploadedAt) latestUploadedAt = r.updatedAt;
      }
      if (operationIdsToAcknowledge.isNotEmpty) {
        final batch = db.batch();
        for (final operationId in operationIdsToAcknowledge) {
          batch.update(
            'op_logs',
            {'is_synced': 1, 'sync_error': ''},
            where: 'id = ? AND is_synced = 0 AND target_table = ?',
            whereArgs: [operationId, 'pomodoro_records'],
          );
        }
        await batch.commit(noResult: true);
      }
      await prefs.setInt(lastUploadKey, DateTime.now().millisecondsSinceEpoch);
      if (latestUploadedAt > lastRecoveryUpload) {
        await prefs.setInt(recoveryUploadKey, latestUploadedAt);
      }
    }
  } catch (e) {
    // debugPrint('[PomodoroService] syncRecordsToCloud error: $e');
  }
}

/// 读取全量（含已删除）内部方法 —— 包含自动迁移逻辑
Future<List<PomodoroRecord>> _getAllRecordsRaw() async {
  final db = await DatabaseHelper.instance.database;
  final List<Map<String, dynamic>> maps = await db.query(
    'pomodoro_records',
    orderBy: 'start_time DESC',
  );

  if (maps.isNotEmpty) {
    unawaited(_clearRecordPrefsMirror());
    return maps.map((m) => PomodoroRecord.fromJson(m)).toList();
  }

  // 🚀 核心迁移：如果 SQL 为空，尝试从 Prefs 迁移
  final prefs = await SharedPreferences.getInstance();
  final scopedKey = await _getScopedKey(_keyRecords);
  final migrationKey = "pomo_migration_done_$scopedKey";

  if (!(prefs.getBool(migrationKey) ?? false)) {
    String? s = prefs.getString(scopedKey);
    // 兜底旧全局 Key
    if (s == null) {
      final username = prefs.getString(StorageService.keyCurrentUser);
      if (username != null) s = prefs.getString(_keyRecords);
    }

    if (s != null) {
      // debugPrint("🚀 [Pomodoro] 正在执行 Prefs -> SQL 增量迁移...");
      try {
        final List<dynamic> decoded = jsonDecode(s);
        final legacyRecords = decoded
            .map((e) => PomodoroRecord.fromJson(e))
            .toList();
        if (legacyRecords.isNotEmpty) {
          await _saveRecordsToSql(legacyRecords);
          await prefs.remove(scopedKey);
          await prefs.remove(_keyRecords);
          // debugPrint("✅ [Pomodoro] 成功迁移 ${legacyRecords.length} 条记录至 SQL");
        }
        await prefs.setBool(migrationKey, true);
        return legacyRecords;
      } catch (e) {
        // debugPrint("❌ [Pomodoro] 迁移失败: $e");
      }
    }
  }

  return [];
}

Future<void> _clearRecordPrefsMirror({SharedPreferences? prefs}) async {
  final resolvedPrefs = prefs ?? await SharedPreferences.getInstance();
  final scopedKey = await _getScopedKey(_keyRecords, prefs: resolvedPrefs);
  if (resolvedPrefs.containsKey(scopedKey)) {
    await resolvedPrefs.remove(scopedKey);
  }
  if (resolvedPrefs.containsKey(_keyRecords)) {
    await resolvedPrefs.remove(_keyRecords);
  }
}

/// 今日专注记录（本地，不含已删除）
Future<List<PomodoroRecord>> _pomoGetTodayRecords() async {
  final now = DateTime.now();
  final range = CalendarDateMath.dayRange(now);
  return _pomoGetRecordsInRange(range.start, range.endExclusive);
}

/// 昨日专注记录（本地，不含已删除）
Future<List<PomodoroRecord>> _pomoGetYesterdayRecords() async {
  final now = DateTime.now();
  final yesterday = CalendarDateMath.addDays(
    CalendarDateMath.dateOnly(now),
    -1,
  );
  final range = CalendarDateMath.dayRange(yesterday);
  return _pomoGetRecordsInRange(range.start, range.endExclusive);
}

/// 最近专注：今日有则返回今日，否则返回昨日；同时返回是哪天
Future<({List<PomodoroRecord> records, bool isToday})>
_pomoGetRecentRecords() async {
  final today = await _pomoGetTodayRecords();
  if (today.isNotEmpty) return (records: today, isToday: true);
  final yesterday = await _pomoGetYesterdayRecords();
  return (records: yesterday, isToday: false);
}

/// 查询绑定到指定 todoUuid 的所有专注记录
Future<List<PomodoroRecord>> _pomoGetRecordsByTodoUuid(String todoUuid) =>
    _pomoGetRecordsByTodoUuids([todoUuid]);

/// 查询绑定到一组待办的有效专注记录。
///
/// 编辑循环待办时，一个编辑对象可能对应多个历史 occurrence。这里直接
/// 按 todo_uuid 查询，避免先读取、反序列化全部专注历史再在 Dart 侧过滤。
Future<List<PomodoroRecord>> _pomoGetRecordsByTodoUuids(
  Iterable<String> todoUuids,
) async {
  final ids = todoUuids.where((id) => id.isNotEmpty).toSet().toList();
  if (ids.isEmpty) return const <PomodoroRecord>[];

  try {
    final db = await DatabaseHelper.instance.database;
    final records = <PomodoroRecord>[];
    const chunkSize = 500;
    for (var start = 0; start < ids.length; start += chunkSize) {
      final end = start + chunkSize < ids.length
          ? start + chunkSize
          : ids.length;
      final chunk = ids.sublist(start, end);
      final placeholders = List.filled(chunk.length, '?').join(',');
      final maps = await db.query(
        'pomodoro_records',
        where: 'is_deleted = 0 AND todo_uuid IN ($placeholders)',
        whereArgs: chunk,
        orderBy: 'start_time DESC',
      );
      records.addAll(maps.map(PomodoroRecord.fromJson));
    }
    records.sort((a, b) => b.startTime.compareTo(a.startTime));
    if (records.isNotEmpty) return records;

    // SQL 为空时，getRecords 会负责一次性的 Prefs -> SQL 迁移。已有
    // SQL 历史但当前待办没有记录时直接返回，避免退回全表读取。
    final count =
        Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM pomodoro_records'),
        ) ??
        0;
    if (count > 0) return records;
    final idsSet = ids.toSet();
    final all = await _pomoGetRecords();
    return all.where((record) => idsSet.contains(record.todoUuid)).toList()
      ..sort((a, b) => b.startTime.compareTo(a.startTime));
  } catch (_) {
    // SQL 不可用时保留旧路径，保证历史 Prefs 数据仍能访问。
    final idsSet = ids.toSet();
    final all = await _pomoGetRecords();
    return all.where((record) => idsSet.contains(record.todoUuid)).toList()
      ..sort((a, b) => b.startTime.compareTo(a.startTime));
  }
}

/// 更新一条记录（修改标签 / 绑定任务等）
/// 先本地保存（立即返回），云端上传在后台异步进行
Future<void> _pomoUpdateRecord(PomodoroRecord updated) async {
  final all = await _getAllRecordsRaw();
  final idx = all.indexWhere((r) => r.uuid == updated.uuid);
  if (idx != -1) {
    final old = all[idx];
    final merged = PomodoroRecord(
      uuid: old.uuid,
      todoUuid: updated.todoUuid,
      todoTitle: updated.todoTitle,
      tagUuids: updated.tagUuids,
      startTime: updated.startTime,
      endTime: updated.endTime,
      plannedDuration: updated.plannedDuration,
      actualDuration: updated.actualDuration,
      status: updated.status,
      deviceId: updated.deviceId ?? old.deviceId,
      planBlockId: updated.planBlockId,
      note: updated.note,
      totalPauseSeconds: updated.totalPauseSeconds ?? old.totalPauseSeconds,
      pauseIntervals: updated.pauseIntervals ?? old.pauseIntervals,
      isDeleted: updated.isDeleted,
      version: (updated.version <= old.version)
          ? (old.version + 1)
          : updated.version,
      createdAt: old.createdAt,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
      hasConflict: old.hasConflict,
      conflictData: old.conflictData,
    );
    await _pomoAddRecord(merged);
  } else {
    await _pomoAddRecord(
      PomodoroRecord(
        uuid: updated.uuid,
        todoUuid: updated.todoUuid,
        todoTitle: updated.todoTitle,
        tagUuids: updated.tagUuids,
        startTime: updated.startTime,
        endTime: updated.endTime,
        plannedDuration: updated.plannedDuration,
        actualDuration: updated.actualDuration,
        status: updated.status,
        deviceId: updated.deviceId,
        planBlockId: updated.planBlockId,
        note: updated.note,
        totalPauseSeconds: updated.totalPauseSeconds,
        pauseIntervals: updated.pauseIntervals,
        isDeleted: updated.isDeleted,
        version: updated.version,
        createdAt: updated.createdAt,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
        hasConflict: updated.hasConflict,
        conflictData: updated.conflictData,
      ),
    );
  }
}

/// 软删除一条记录
Future<void> _pomoDeleteRecord(String uuid) async {
  final all = await _getAllRecordsRaw();
  final idx = all.indexWhere((r) => r.uuid == uuid);
  if (idx != -1) {
    final old = all[idx];
    final deleted = PomodoroRecord(
      uuid: old.uuid,
      todoUuid: old.todoUuid,
      todoTitle: old.todoTitle,
      tagUuids: old.tagUuids,
      startTime: old.startTime,
      endTime: old.endTime,
      plannedDuration: old.plannedDuration,
      actualDuration: old.actualDuration,
      status: old.status,
      deviceId: old.deviceId,
      planBlockId: old.planBlockId,
      note: old.note,
      totalPauseSeconds: old.totalPauseSeconds,
      pauseIntervals: old.pauseIntervals,
      isDeleted: true,
      version: old.version + 1,
      createdAt: old.createdAt,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
      hasConflict: old.hasConflict,
      conflictData: old.conflictData,
    );
    await _pomoAddRecord(deleted);
  }
}

String _pomoStatusStr(PomodoroRecordStatus s) {
  switch (s) {
    case PomodoroRecordStatus.completed:
      return 'completed';
    case PomodoroRecordStatus.interrupted:
      return 'interrupted';
    case PomodoroRecordStatus.switched:
      return 'switched';
  }
}

/// 获取今日全站人均专注统计（带 60 秒内存缓存；无数据或离线时返回 null）
Future<PomodoroCommunityStats?> _pomoGetTodayCommunityStats({
  bool forceRefresh = false,
  DateTime? now,
  Future<Map<String, dynamic>?> Function(int fromMs, int toMs)? fetcher,
}) async {
  final current = now ?? DateTime.now();
  final range = CalendarDateMath.dayRange(current);
  final dayKey = '${range.start.year}-${range.start.month}-${range.start.day}';

  if (!forceRefresh && _communityStatsCache != null) {
    final cached = _communityStatsCache!;
    if (cached.dayKey == dayKey &&
        current.difference(cached.fetchedAt) < const Duration(seconds: 60)) {
      return cached.stats;
    }
  }

  final loadFn =
      fetcher ??
      ((fromMs, toMs) =>
          ApiService.fetchPomodoroCommunityStats(fromMs: fromMs, toMs: toMs));
  final raw = await loadFn(
    range.start.millisecondsSinceEpoch,
    range.endExclusive.millisecondsSinceEpoch,
  );
  final parsed = raw == null ? null : PomodoroCommunityStats.tryParse(raw);
  _communityStatsCache = (fetchedAt: current, dayKey: dayKey, stats: parsed);
  return parsed;
}

void _pomoClearCommunityStatsCacheForTest() {
  _communityStatsCache = null;
}
