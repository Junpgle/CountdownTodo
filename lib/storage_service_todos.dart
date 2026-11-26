part of 'storage_service.dart';

// ignore_for_file: annotate_overrides, unused_element, unused_element_parameter

final Expando<Object> _sharedInflightTodoFutures = Expando<Object>(
  'shared_inflight_todo_futures',
);
const Object _sharedInflightMarker = Object();

int? _parseNullableIntForIsolate(dynamic raw) {
  return JsonValueParser.toNullableInt(raw);
}

Future<bool> _fixedScheduleTodoSnapshotsMatch(
  DatabaseExecutor executor, {
  required Set<String> todoIds,
  required List<FixedScheduleItem> expectedSchedules,
}) async {
  final normalizedIds = todoIds
      .map((id) => id.trim())
      .where((id) => id.isNotEmpty)
      .toSet();
  final expectedById = <String, FixedScheduleItem>{};
  for (final schedule in expectedSchedules) {
    if (schedule.isDeleted ||
        !schedule.relatedTodoIds.any(
          (id) => normalizedIds.contains(id.trim()),
        ) ||
        expectedById.containsKey(schedule.id)) {
      return false;
    }
    expectedById[schedule.id] = schedule;
  }

  final currentSchedules = await _queryFixedSchedulesLinkedToTodoIds(
    executor,
    normalizedIds,
  );
  if (currentSchedules.length != expectedById.length) return false;
  for (final current in currentSchedules) {
    final expected = expectedById[current.id];
    if (expected == null ||
        jsonEncode(current.toJson()) != jsonEncode(expected.toJson())) {
      return false;
    }
  }
  return true;
}

List<TodoItem> _parseTodoItemsIsolate(List<Map<String, dynamic>> maps) {
  return maps.map((m) => TodoItem.fromSql(m)).toList();
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
  static const _todoSnapshotFields = <String>[
    'content',
    'remark',
    'is_completed',
    'completed_at',
    'is_skipped',
    'is_skipped_sync_pending',
    'is_deleted',
    'created_date',
    'due_date',
    'group_id',
    'team_uuid',
    'collab_type',
    'recurrence',
    'recurrence_series_id',
    'custom_interval_days',
    'recurrence_end_date',
    'is_all_day',
    'reminder_minutes',
    'has_conflict',
    'conflict_data',
    'image_path',
    'original_text',
    'version',
    'updated_at',
    'created_at',
    'team_name',
    'creator_id',
    'creator_name',
  ];

  static const _independentCompletionIgnoredFields = <String>{
    'is_completed',
    'completed_at',
    'completedAt',
    'is_skipped',
    'is_skipped_sync_pending',
    'version',
    'updated_at',
    'has_conflict',
    'conflict_data',
  };

  static final List<String> _collabSharedSnapshotFields = _todoSnapshotFields
      .where((field) => !_independentCompletionIgnoredFields.contains(field))
      .toList(growable: false);

  Future<void> saveTodos(
    String username,
    List<TodoItem> items, {
    bool sync = true,
    bool isSyncSource = false,
    bool recomputeScheduleConflicts = true,
    Set<String> authoritativeTodoIds = const {},
    Map<String, TodoItem>? recurrenceBaselines,
    Map<String, TodoItem?>? recurrenceUploadBaselines,
    List<TodoItem>? bandSyncSnapshot,
    Map<String, TodoItem>? expectedTodoBaselines,
    Map<String, Set<String>>? expectedSeriesMembership,
    bool expectedSeriesMembershipIncludesDeleted = false,
    Set<String>? expectedFixedScheduleTodoIds,
    List<FixedScheduleItem>? expectedFixedScheduleBaselines,
    FixedScheduleItem? linkedFixedScheduleBaseline,
    FixedScheduleItem? linkedFixedScheduleUpdate,
  }) async {
    if ((expectedFixedScheduleTodoIds == null) !=
        (expectedFixedScheduleBaselines == null)) {
      throw ArgumentError('关联固定日程复核需要同时提供待办范围和日程快照');
    }
    if ((linkedFixedScheduleBaseline == null) !=
        (linkedFixedScheduleUpdate == null)) {
      throw ArgumentError('创建关联待办需要同时提供固定日程原快照与更新快照');
    }
    if (linkedFixedScheduleBaseline != null &&
        (isSyncSource || expectedFixedScheduleTodoIds != null)) {
      throw ArgumentError('当前写入模式不能与关联固定日程创建同时使用');
    }
    final dedupeMap = <String, TodoItem>{};
    if (sync &&
        !isSyncSource &&
        items.any(
          (item) =>
              item.recurrence != RecurrenceType.none ||
              (item.recurrenceSeriesId?.isNotEmpty ?? false),
        )) {
      _recurrenceCheckCache.clear();
    }
    for (final source in items) {
      if (source.isDone && source.completedAt == null) {
        final isRecurrence =
            (source.recurrenceSeriesId != null &&
                source.recurrenceSeriesId!.trim().isNotEmpty) ||
            source.recurrence != RecurrenceType.none;
        source.completedAt = isRecurrence
            ? (source.createdDate ??
                  source.dueDate?.millisecondsSinceEpoch ??
                  source.createdAt)
            : source.updatedAt;
      } else if (!source.isDone && source.completedAt != null) {
        source.completedAt = null;
      }
      // Async reads must not share mutable UI objects with this write.
      var item = expectedTodoBaselines == null
          ? source.detachedCopy()
          : TodoItem.fromJson(source.toJson());
      if (item.isDone && item.isSkipped) {
        throw ArgumentError('待办不能同时处于已完成和已跳过状态');
      }
      if (item.isSkipped &&
          item.recurrence == RecurrenceType.none &&
          item.recurrenceSeriesId?.trim().isNotEmpty != true) {
        throw ArgumentError('仅可跳过重复待办的本期');
      }
      if (item.recurrence != RecurrenceType.none &&
          item.recurrenceSeriesId?.isNotEmpty != true) {
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
    final candidates = dedupeMap.values.toList();
    if (linkedFixedScheduleBaseline != null) {
      final baseline = linkedFixedScheduleBaseline;
      final update = linkedFixedScheduleUpdate!;
      if (candidates.length != 1 ||
          candidates.single.isDone ||
          candidates.single.isSkipped ||
          candidates.single.isDeleted ||
          candidates.single.recurrence != RecurrenceType.none) {
        throw ArgumentError('关联固定日程只支持保存一个单次未完成待办');
      }
      String? normalizeTeam(String? value) => AppTextUtils.trimToNull(value);

      final todo = candidates.single;
      final relatedId = todo.id.trim();
      final expectedSchedule = FixedScheduleItem.fromJson(baseline.toJson());
      if (relatedId.isEmpty ||
          baseline.isDeleted ||
          baseline.status == FixedScheduleStatus.cancelled ||
          normalizeTeam(todo.teamUuid) != normalizeTeam(baseline.teamUuid)) {
        throw StateError('固定日程或待办范围已变化，请重新打开后再保存。');
      }
      if (!expectedSchedule.relatedTodoIds.any(
        (id) => id.trim() == relatedId,
      )) {
        expectedSchedule.relatedTodoIds.add(relatedId);
        if (update.version != baseline.version + 1 ||
            update.updatedAt <= baseline.updatedAt) {
          throw ArgumentError('固定日程关系版本无效');
        }
        expectedSchedule.version = update.version;
        expectedSchedule.updatedAt = update.updatedAt;
      }
      if (update.id != baseline.id ||
          jsonEncode(expectedSchedule.toJson()) !=
              jsonEncode(update.toJson())) {
        throw ArgumentError('固定日程关系更新只能加入当前新待办');
      }
    }
    final maintenanceSeries = candidates
        .map((item) => item.recurrenceSeriesId)
        .toSet();
    final ruleBaselines =
        (recurrenceBaselines == null
                ? null
                : _recurrenceBoundaryRulesBySeries(recurrenceBaselines.values)
                      .values)
            ?.where(
              (item) => maintenanceSeries.contains(
                item.recurrenceSeriesId ?? item.id,
              ),
            )
            .toList() ??
        const <TodoItem>[];
    final rulesBySeries = <String, TodoItem>{};
    for (final rule in ruleBaselines) {
      rulesBySeries.putIfAbsent(rule.recurrenceSeriesId ?? rule.id, () => rule);
    }
    final validationIds = {
      ...dedupeMap.keys,
      ...ruleBaselines.map((item) => item.id),
      ...?expectedTodoBaselines?.keys,
    }.toList();
    final db = await DatabaseHelper.instance.databaseForUser(username);
    if (expectedFixedScheduleTodoIds != null && username.trim() != 'default') {
      await UserSessionStorage.ensureCurrentUsername(username);
    }
    final localPrefs = await prefs;
    final userId = localPrefs.getInt('current_user_id') ?? 0;
    final affectedDays = <String>{};
    final writtenIds = <String>{};
    final persistedItems = <String, TodoItem>{};
    UserSessionSnapshot? linkedScheduleSession;
    if (linkedFixedScheduleBaseline != null) {
      await UserSessionStorage.ensureCurrentUsername(username);
      linkedScheduleSession = await UserSessionStorage.captureSession(username);
      if (linkedScheduleSession == null) {
        throw StateError('账户状态已变化，请重新打开固定日程后再保存。');
      }
    }
    if (username.trim() != 'default') {
      await UserSessionStorage.ensureCurrentUsername(username);
    }

    // The current row, pending operations, row write and oplog must share the
    // same transaction. A pre-transaction check leaves a second rollback race.
    await db.transaction((txn) async {
      final linkBaseline = linkedFixedScheduleBaseline;
      if (linkBaseline != null) {
        await UserSessionStorage.ensureCurrentSession(linkedScheduleSession!);
        final rows = await txn.query(
          'fixed_schedules',
          where: 'uuid = ?',
          whereArgs: [linkBaseline.id],
          limit: 1,
        );
        if (rows.length != 1 ||
            jsonEncode(FixedScheduleItem.fromJson(rows.single).toJson()) !=
                jsonEncode(linkBaseline.toJson())) {
          throw StateError('固定日程已变化，请重新核对后再保存。');
        }
      }
      if (expectedFixedScheduleTodoIds != null) {
        if (username.trim() != 'default') {
          await UserSessionStorage.ensureCurrentUsername(username);
        }
        final snapshotsMatch = await _fixedScheduleTodoSnapshotsMatch(
          txn,
          todoIds: expectedFixedScheduleTodoIds,
          expectedSchedules: expectedFixedScheduleBaselines!,
        );
        if (!snapshotsMatch) {
          throw StateError('关联固定日程已有变化，请重新核对后保存。');
        }
      }
      final existingById = <String, Map<String, dynamic>>{};
      final pendingIds = <String>{};
      const chunkSize = 400;
      for (var start = 0; start < validationIds.length; start += chunkSize) {
        final ids = validationIds.skip(start).take(chunkSize).toList();
        final rows = await DatabaseHelper.instance.getTodoMaps(
          includeDeleted: true,
          uuids: ids,
          includeConflictData: true,
          databaseOverride: txn,
        );
        for (final row in rows) {
          existingById[row['uuid'].toString()] = row;
        }
        if (isSyncSource) {
          final placeholders = List.filled(ids.length, '?').join(',');
          final ops = await txn.query(
            'op_logs',
            columns: const ['target_uuid'],
            where:
                "is_synced = 0 AND target_table = 'todos' AND target_uuid IN ($placeholders)",
            whereArgs: ids,
          );
          pendingIds.addAll(ops.map((row) => row['target_uuid'].toString()));
        }
      }
      final linkBaselineForTodoId = linkedFixedScheduleBaseline;
      if (linkBaselineForTodoId != null) {
        final todo = candidates.single;
        final currentRow = existingById[todo.id];
        final alreadyLinked = linkBaselineForTodoId.relatedTodoIds.any(
          (id) => id.trim() == todo.id.trim(),
        );
        if (currentRow != null && !alreadyLinked) {
          throw StateError('待办标识已存在，请重新创建准备待办。');
        }
      }
      if (expectedSeriesMembership != null) {
        for (final entry in expectedSeriesMembership.entries) {
          final seriesId = entry.key.trim();
          if (seriesId.isEmpty) {
            throw StateError('循环系列标识无效，请重新打开后再编辑。');
          }
          final rows = await txn.query(
            'todos',
            columns: const ['uuid'],
            where: expectedSeriesMembershipIncludesDeleted
                ? "recurrence_series_id = ? OR "
                      "(uuid = ? AND TRIM(COALESCE(recurrence_series_id, '')) = '')"
                : "is_deleted = 0 AND (recurrence_series_id = ? OR "
                      "(uuid = ? AND TRIM(COALESCE(recurrence_series_id, '')) = ''))",
            whereArgs: [seriesId, seriesId],
          );
          final currentMembers = rows
              .map((row) => row['uuid']?.toString())
              .whereType<String>()
              .toSet();
          if (currentMembers.length != entry.value.length ||
              !currentMembers.containsAll(entry.value)) {
            throw StateError('循环系列已有变化，请重新打开后再编辑。');
          }
        }
      }
      final staleRuleSeries = <String>{};
      if (expectedTodoBaselines != null) {
        for (final entry in expectedTodoBaselines.entries) {
          final currentRow = existingById[entry.key];
          if (currentRow == null ||
              _hasSubstantialChange(
                TodoItem.fromSql(currentRow).toJson(),
                entry.value.toJson(),
                _todoSnapshotFields,
              )) {
            throw StateError('待办「${entry.value.title}」已在其他位置更新，请重新打开后再编辑。');
          }
        }
      }
      for (final rule in ruleBaselines) {
        final current = existingById[rule.id];
        if (current == null ||
            _hasSubstantialChange(
              TodoItem.fromSql(current).toJson(),
              rule.toJson(),
              _todoSnapshotFields,
            )) {
          staleRuleSeries.add(rule.recurrenceSeriesId ?? rule.id);
        }
      }
      final batch = txn.batch();
      for (var item in candidates) {
        if (item.isDone && item.completedAt == null) {
          final isRecurrence =
              (item.recurrenceSeriesId != null &&
                  item.recurrenceSeriesId!.trim().isNotEmpty) ||
              item.recurrence != RecurrenceType.none;
          item.completedAt = isRecurrence
              ? (item.createdDate ??
                    item.dueDate?.millisecondsSinceEpoch ??
                    item.createdAt)
              : item.updatedAt;
        } else if (!item.isDone && item.completedAt != null) {
          item.completedAt = null;
        }
        final oldData = existingById[item.id];
        final current = oldData == null ? null : TodoItem.fromSql(oldData);
        if (current != null) persistedItems[item.id] = current;
        if (!isSyncSource &&
            (current == null
                ? item.isSkipped
                : current.isSkipped != item.isSkipped)) {
          item.isSkippedSyncPending = true;
        }
        final baseline = recurrenceBaselines?[item.id];
        if (recurrenceBaselines != null) {
          // Missing baseline means insert-only automatic generation. Existing
          // maintenance is conditional on exactly the snapshot it inspected.
          if (staleRuleSeries.contains(item.recurrenceSeriesId) ||
              (baseline == null && current != null) ||
              (baseline != null &&
                  (current == null ||
                      _hasSubstantialChange(
                        current.toJson(),
                        baseline.toJson(),
                        _todoSnapshotFields,
                      )))) {
            _recurrenceCheckCache.clear();
            continue;
          }
        } else if (current != null &&
            !(isSyncSource && authoritativeTodoIds.contains(item.id)) &&
            TodoLwwService.compare(
                  incomingUpdatedAt: item.updatedAt,
                  incomingVersion: item.version,
                  currentUpdatedAt: current.updatedAt,
                  currentVersion: current.version,
                ) <
                0) {
          continue;
        }
        if (isSyncSource &&
            current != null &&
            (pendingIds.contains(item.id) ||
                _pendingSyncOplogUuids.contains(item.id) ||
                _forceFlushProtectedUuids.contains(item.id))) {
          final hasLocalConflictChange =
              current.hasConflict != item.hasConflict ||
              jsonEncode(current.serverVersionData) !=
                  jsonEncode(item.serverVersionData);
          final nonConflictFields = _todoSnapshotFields
              .where(
                (field) => field != 'has_conflict' && field != 'conflict_data',
              )
              .toList();
          final hasOtherChanges = _hasSubstantialChange(
            current.toJson(),
            item.toJson(),
            nonConflictFields,
          );
          if (!hasLocalConflictChange || hasOtherChanges) {
            // Protect pending user edits while rejecting any stale sync data.
            continue;
          }

          // Schedule-conflict metadata is local-only. Merge just these fields
          // onto the protected row so pending user content and its oplog stay
          // untouched while the conflict remains visible after a reload.
          final merged = current.detachedCopy();
          merged.hasConflict = item.hasConflict;
          merged.serverVersionData = item.serverVersionData == null
              ? null
              : JsonValueParser.toMap(jsonEncode(item.serverVersionData));
          item = merged;
        }
        final data = item.toJson();
        final hasChanged =
            current == null ||
            _hasSubstantialChange(current.toJson(), data, _todoSnapshotFields);
        if (!hasChanged) continue;
        final isIndependentCompletionOnly =
            !isSyncSource &&
            recurrenceBaselines == null &&
            current != null &&
            item.collabType == 1 &&
            !_hasSubstantialChange(
              current.toJson(),
              data,
              _collabSharedSnapshotFields,
            );
        if (isIndependentCompletionOnly) {
          // 各自完成状态的变更不递增共享任务版本号，避免抬高主表 version 触发版本冲突
          item.version = current.version;
          data['version'] = current.version;
        }
        if (!isSyncSource) {
          final payload = _stripClientOnlyConflictForSync(data);
          if (isIndependentCompletionOnly) {
            payload['_independent_completion_only'] = true;
          }
          if (recurrenceBaselines != null) {
            final uploadBaseline =
                recurrenceUploadBaselines?.containsKey(item.id) == true
                ? recurrenceUploadBaselines![item.id]
                : baseline;
            payload['_recurrence_maintenance'] = {
              'create_only': uploadBaseline == null,
              'base_version': uploadBaseline?.version,
              'base_updated_at': uploadBaseline?.updatedAt,
            };
            final rule = rulesBySeries[item.recurrenceSeriesId];
            if (rule != null && rule.id != item.id) {
              final ruleBaseline = recurrenceUploadBaselines?[rule.id] ?? rule;
              (payload['_recurrence_maintenance'] as Map)['rule'] = {
                'uuid': rule.id,
                'version': ruleBaseline.version,
                'updated_at': ruleBaseline.updatedAt,
              };
            }
          }
          if (item.isDeleted &&
              _recurrenceDedupeTombstoneIds.contains(item.id)) {
            payload['_recurrence_delete_reason'] = 'dedupe';
          }
          batch.insert('op_logs', {
            'op_type': 'UPSERT',
            'target_table': 'todos',
            'target_uuid': item.id,
            'data_json': jsonEncode(payload),
            'timestamp': DateTime.now().millisecondsSinceEpoch,
            'is_synced': 0,
            'sync_error': '',
          });
          try {
            await DatabaseHelper.instance.insertLocalAuditLog(
              databaseOverride: txn,
              userId: ApiService.currentUserId,
              targetTable: 'todos',
              targetUuid: item.id,
              opType: current == null ? 'INSERT' : 'UPDATE',
              beforeData: oldData,
              afterData: data,
              teamUuid: item.teamUuid,
              operatorName: '本人(离线)',
            );
          } catch (error) {
            debugPrint('⚠️ 记录待办审计失败: $error');
          }
        }
        if (_requiresScheduleConflictRefresh(item, oldData)) {
          affectedDays.addAll(
            _scheduleConflictDayKeysFor(item, previousData: oldData),
          );
        }
        batch.insert('todos', {
          'uuid': item.id,
          'content': item.title,
          'remark': item.remark,
          'team_uuid': item.teamUuid,
          'team_name': item.teamName,
          'creator_id': item.creatorId,
          'creator_name': item.creatorName,
          'is_completed': item.isDone ? 1 : 0,
          'is_skipped': item.collabType == 1 || !item.isSkipped ? 0 : 1,
          'is_skipped_sync_pending':
              item.collabType == 1 || !item.isSkippedSyncPending ? 0 : 1,
          'is_deleted': item.isDeleted ? 1 : 0,
          'version': item.version,
          'due_date': item.dueDate?.millisecondsSinceEpoch ?? 0,
          'group_id': item.groupId,
          'created_date': item.createdDate, // 业务开始时间可空，不回退到物理创建时间
          'created_at': item.createdAt,
          'updated_at': item.updatedAt,
          'completed_at': item.completedAt,
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
        }, conflictAlgorithm: ConflictAlgorithm.replace);
        // Maintenance does not constitute a new independent completion.
        if (!isSyncSource &&
            recurrenceBaselines == null &&
            item.collabType == 1 &&
            userId > 0) {
          batch.insert('todo_completions', {
            'todo_uuid': item.id,
            'user_id': userId,
            'is_completed': item.isDone ? 1 : 0,
            'is_skipped': item.isSkipped ? 1 : 0,
            'is_skipped_sync_pending': item.isSkippedSyncPending ? 1 : 0,
            'updated_at': item.updatedAt,
          }, conflictAlgorithm: ConflictAlgorithm.replace);
        }
        writtenIds.add(item.id);
        persistedItems[item.id] = item;
      }
      final linkedUpdate = linkedFixedScheduleUpdate;
      if (linkedUpdate != null &&
          jsonEncode(linkedUpdate.toJson()) !=
              jsonEncode(linkedFixedScheduleBaseline!.toJson())) {
        final data = linkedUpdate.toJson();
        batch.insert('op_logs', {
          'op_type': 'UPSERT',
          'target_table': 'fixed_schedules',
          'target_uuid': linkedUpdate.id,
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
      if (username.trim() != 'default') {
        if (linkedScheduleSession != null) {
          await UserSessionStorage.ensureCurrentSession(linkedScheduleSession);
        } else {
          await UserSessionStorage.ensureCurrentUsername(username);
        }
      }
      await batch.commit(noResult: true);
    });
    await _clearTodoPrefsMirror(username);
    if (writtenIds.isNotEmpty) {
      _inflightTodoRequests.clear();
      _inflightTodoSearchDateRequests.clear();
      _inflightTimelineTodoRequests.clear();
    }
    if (recomputeScheduleConflicts && affectedDays.isNotEmpty) {
      await _refreshTodoScheduleConflicts(
        username,
        affectedDayKeys: affectedDays,
        affectedTodoIds: writtenIds,
      );
    }
    if (sync) requestSync(username);
    if (persistedItems.isNotEmpty) {
      final bandItems = bandSyncSnapshot == null
          ? persistedItems.values.toList()
          : bandSyncSnapshot
                .map((item) => persistedItems[item.id] ?? item)
                .toList();
      Future.microtask(() => _syncTodosToBand(bandItems));
    }
    triggerRefresh({
      DataRefreshDomain.todos,
      if (linkedFixedScheduleUpdate != null &&
          jsonEncode(linkedFixedScheduleUpdate.toJson()) !=
              jsonEncode(linkedFixedScheduleBaseline!.toJson()))
        DataRefreshDomain.fixedSchedules,
    });
  }

  Future<bool> _saveRecurrenceMaintenance(
    String username,
    List<TodoItem> todos,
    Map<String, TodoItem> baselines, {
    Map<String, TodoItem?>? uploadBaselines,
  }) async {
    final changed = todos.where((item) {
      final baseline = baselines[item.id];
      return baseline == null ||
          _hasSubstantialChange(
            baseline.toJson(),
            item.toJson(),
            _todoSnapshotFields,
          );
    }).toList();
    if (changed.isEmpty) return true;
    for (final item in changed) {
      final baseline = baselines[item.id];
      if (baseline != null &&
          TodoLwwService.compare(
                incomingUpdatedAt: item.updatedAt,
                incomingVersion: item.version,
                currentUpdatedAt: baseline.updatedAt,
                currentVersion: baseline.version,
              ) <=
              0) {
        item.updatedAt = baseline.updatedAt;
        item.version = baseline.version + 1;
      }
    }
    await saveTodos(
      username,
      changed,
      recurrenceBaselines: baselines,
      recurrenceUploadBaselines: uploadBaselines,
      recomputeScheduleConflicts: false,
    );
    // A concurrent edit can reject maintenance. Return the committed state,
    // including completion/date changes, instead of the obsolete read result.
    final db = await DatabaseHelper.instance.databaseForUser(username);
    final currentById = <String, TodoItem>{};
    final seriesIds = changed.map((item) => item.recurrenceSeriesId).toSet();
    final readIdSet = {
      ...changed.map((item) => item.id),
      ..._recurrenceBoundaryRulesBySeries(baselines.values).values
          .where(
            (item) => seriesIds.contains(item.recurrenceSeriesId ?? item.id),
          )
          .map((item) => item.id),
    };
    final readIds = readIdSet.toList();
    const chunkSize = 400;
    for (var start = 0; start < readIds.length; start += chunkSize) {
      final rows = await DatabaseHelper.instance.getTodoMaps(
        includeDeleted: true,
        includeConflictData: true,
        uuids: readIds.skip(start).take(chunkSize).toList(),
        databaseOverride: db,
      );
      for (final row in rows) {
        currentById[row['uuid'].toString()] = TodoItem.fromSql(row);
      }
    }
    var saved = true;
    for (var i = 0; i < todos.length; i++) {
      final current = currentById[todos[i].id];
      if (readIdSet.contains(todos[i].id) &&
          (current == null ||
              _hasSubstantialChange(
                current.toJson(),
                todos[i].toJson(),
                _todoSnapshotFields,
              ))) {
        saved = false;
      }
      todos[i] = currentById[todos[i].id] ?? todos[i];
    }
    return saved;
  }

  Future<void> updateSingleTodo(
    String username,
    TodoItem item, {
    bool sync = true,
  }) => saveTodos(username, [item], sync: sync);

  Future<TodoItem?> getTodoByUuid(String username, String uuid) async {
    final db = await DatabaseHelper.instance.databaseForUser(username);
    final rows = await DatabaseHelper.instance.getTodoMaps(
      includeDeleted: true,
      uuids: [uuid],
      limit: 1,
      includeConflictData: true,
      databaseOverride: db,
    );
    if (rows.isEmpty) return null;
    return _parseTodoItemsIsolate(rows).first;
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

  Future<TodoRecurrenceDeletePlan> deleteRecurringTodoWithScope(
    String username,
    String todoId,
    TodoRecurrenceDeleteScope scope, {
    bool sync = true,
  }) async {
    // Run normal materialization first so a rule owner has the app's usual
    // look-ahead instances before resolving a deletion scope.
    final snapshot = await getTodos(username, includeDeleted: true);
    final plan = TodoRecurrenceDeleteService.plan(
      todos: snapshot,
      todoId: todoId,
      scope: scope,
    );
    if (plan.changedItems.isEmpty) {
      throw StateError('没有可保存的删除变更');
    }

    await saveTodos(
      username,
      plan.changedItems,
      sync: sync,
      expectedTodoBaselines: plan.baselines,
      expectedSeriesMembership: {plan.seriesId: plan.expectedActiveMemberIds},
    );
    // Only duplicate repair may reactivate its own tombstones. A user deleting
    // a logical period closes that exception for every same-day row.
    _recurrenceDedupeTombstoneIds.removeAll(plan.revivalBarrierIds);
    return plan;
  }

  Future<TodoRecurrenceRestorePlan> restoreRecurringTodoSeries(
    String username,
    String seriesId, {
    bool sync = true,
  }) async {
    final snapshot = await getTodos(username, includeDeleted: true);
    final groups = await getTodoGroups(username);
    final activeGroupIds = groups
        .where((group) => !group.isDeleted)
        .map((group) => group.id)
        .toSet();
    final plan = TodoRecurrenceRestoreService.tryPlan(
      todos: snapshot,
      seriesId: seriesId,
      activeGroupIds: activeGroupIds,
    );
    if (plan == null) {
      throw StateError('系列状态已变化或无法安全整组恢复，请刷新后逐期恢复。');
    }

    await saveTodos(
      username,
      plan.restoredItems,
      sync: sync,
      expectedTodoBaselines: plan.baselines,
      expectedSeriesMembership: {plan.seriesId: plan.expectedMemberIds},
      expectedSeriesMembershipIncludesDeleted: true,
    );
    _recurrenceDedupeTombstoneIds.removeAll(plan.expectedMemberIds);
    return plan;
  }

  Future<TodoTrashMultiRestorePlan> restoreTodoTrashSelection(
    String username,
    TodoTrashMultiRestorePlan plan, {
    bool sync = true,
  }) async {
    final restoredIds = plan.restoredItems.map((todo) => todo.id).toSet();
    if (plan.selectedTodoIds.isEmpty ||
        restoredIds.length != plan.restoredItems.length ||
        restoredIds.length != plan.selectedTodoIds.length ||
        !restoredIds.containsAll(plan.selectedTodoIds) ||
        plan.baselines.length != plan.selectedTodoIds.length ||
        !plan.baselines.keys.toSet().containsAll(plan.selectedTodoIds) ||
        plan.selectedTodoIds.any((id) => !plan.baselines[id]!.isDeleted) ||
        plan.restoredItems.any((todo) => todo.isDeleted)) {
      throw StateError('恢复范围无效，请重新选择回收站待办。');
    }

    await saveTodos(
      username,
      plan.restoredItems,
      sync: sync,
      expectedTodoBaselines: plan.baselines,
    );
    _recurrenceDedupeTombstoneIds.removeAll(plan.revivalBarrierIds);
    return plan;
  }

  Future<void> saveTodoGroups(
    String username,
    List<TodoGroup> items, {
    bool sync = true,
    bool isSyncSource = false,
    Map<String, TodoGroup>? expectedGroupBaselines,
  }) async {
    final Map<String, TodoGroup> dedupeMap = {};

    for (var item in items) {
      if (!dedupeMap.containsKey(item.id) ||
          item.updatedAt > dedupeMap[item.id]!.updatedAt) {
        dedupeMap[item.id] = item;
      }
    }

    final db = await DatabaseHelper.instance.databaseForUser(username);
    if (expectedGroupBaselines != null && username.trim() != 'default') {
      await UserSessionStorage.ensureCurrentUsername(username);
    }
    await db.transaction((txn) async {
      final existingRows = await txn.query('todo_groups');
      final existingItemsMap = <String, Map<String, dynamic>>{
        for (final row in existingRows) row['uuid'].toString(): row,
      };
      if (expectedGroupBaselines != null) {
        for (final entry in expectedGroupBaselines.entries) {
          final current = existingItemsMap[entry.key];
          if (current == null ||
              _hasSubstantialChange(current, entry.value.toJson(), [
                'name',
                'is_expanded',
                'is_deleted',
                'team_uuid',
                'team_name',
                'version',
                'updated_at',
                'created_at',
                'creator_id',
                'creator_name',
                'has_conflict',
                'conflict_data',
              ])) {
            throw StateError('文件夹「${entry.value.name}」已在其他位置更新，请重新打开后再修改。');
          }
        }
      }
      final batch = txn.batch();
      for (final item in dedupeMap.values) {
        final oldData = existingItemsMap[item.id];
        final hasChanged =
            oldData == null ||
            _hasSubstantialChange(oldData, item.toJson(), [
              'name',
              'is_expanded',
              'is_deleted',
              'team_uuid',
              'team_name',
              'version',
              'updated_at',
              'created_at',
              'creator_id',
              'creator_name',
              'has_conflict',
              'conflict_data',
            ]);

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

        if (hasChanged) {
          batch.insert('todo_groups', {
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
                : null,
          }, conflictAlgorithm: ConflictAlgorithm.replace);
        }
      }
      if (expectedGroupBaselines != null && username.trim() != 'default') {
        await UserSessionStorage.ensureCurrentUsername(username);
      }
      await batch.commit(noResult: true);
    });
    _inflightTodoRequests.clear();
    _inflightTodoSearchDateRequests.clear();
    _inflightTimelineTodoRequests.clear();

    unawaited(_clearTodoGroupPrefsMirror(username));
    if (sync) requestSync(username);
    triggerRefresh(const {DataRefreshDomain.todoGroups});
  }

  Future<void> _clearTodoGroupPrefsMirror(String username) async {
    final prefs = await SharedPreferences.getInstance();
    final scopedKey = _scopedKey(keyTodoGroups, username);
    if (prefs.containsKey(scopedKey)) {
      await prefs.remove(scopedKey);
    }
    if (prefs.containsKey(keyTodoGroups)) {
      await prefs.remove(keyTodoGroups);
    }
  }

  Future<List<TodoGroup>> getTodoGroups(
    String username, {
    bool includeDeleted = false,
  }) async {
    try {
      final dbHelper = DatabaseHelper.instance;
      final db = await dbHelper.databaseForUser(username);
      await _clearGhostConflictFlags(db, tables: const ['todo_groups']);
      // 1. 先从 SQL 读取，仅当无数据时才检查旧 Prefs 迁移
      List<Map<String, dynamic>> maps = await db.query(
        'todo_groups',
        where: includeDeleted ? null : 'is_deleted = 0',
      );
      if (maps.isEmpty) {
        final hasSqliteRows = includeDeleted
            ? const <Map<String, Object?>>[]
            : await db.rawQuery('SELECT 1 FROM todo_groups LIMIT 1');
        if (hasSqliteRows.isEmpty) {
          final prefs = await SharedPreferences.getInstance();
          List<String> legacyJsonList =
              prefs.getStringList(_scopedKey(keyTodoGroups, username)) ?? [];

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
            await saveTodoGroups(
              username,
              legacyData,
              sync: false,
              isSyncSource: true,
            );
            maps = await db.query(
              'todo_groups',
              where: includeDeleted ? null : 'is_deleted = 0',
            );
          }
        }
      }
      if (maps.isNotEmpty) {
        return maps
            .map(
              (m) => TodoGroup(
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
              ),
            )
            .toList();
      } else {
        return [];
      }
    } catch (e) {
      debugPrint("⚠️ TodoGroups SQL 引擎异常: $e");
    }

    // 逃生通道
    final prefs = await StorageService.prefs;
    List<String> list =
        prefs.getStringList(_scopedKey(keyTodoGroups, username)) ?? [];
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
    String username,
    String idToDelete,
  ) async {
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
