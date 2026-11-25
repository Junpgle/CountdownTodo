part of 'storage_service.dart';

// ignore_for_file: unused_element, unused_element_parameter, annotate_overrides

mixin _StorageSyncPersist on _StorageServiceBase {
  @override
  Future<void> _persistSyncMergeResults(_SyncRunContext ctx) async {
    final username = ctx.username;
    final session = ctx.session;
    final db = ctx.db;
    final syncTodos = ctx.syncTodos;
    final syncCountdowns = ctx.syncCountdowns;
    final syncTimeLogs = ctx.syncTimeLogs;
    final syncPomodoro = ctx.syncPomodoro;
    final syncPlanBlocks = ctx.syncPlanBlocks;
    final syncFixedSchedules = ctx.syncFixedSchedules;
    final syncHabits = ctx.syncHabits;
    final fixedSchedulesSupported = ctx.fixedSchedulesSupported;
    final habitsSupported = ctx.habitsSupported;
    final pomodoroChanged = ctx.pomodoroChanged;
    final allLocalTodos = ctx.allLocalTodos;
    final allLocalGroups = ctx.allLocalGroups;
    final allLocalCountdowns = ctx.allLocalCountdowns;
    final allLocalTimeLogs = ctx.allLocalTimeLogs;
    final allLocalPlanBlocks = ctx.allLocalPlanBlocks;
    final allLocalFixedSchedules = ctx.allLocalFixedSchedules;
    final allLocalHabitGoals = ctx.allLocalHabitGoals;
    final allLocalHabitRules = ctx.allLocalHabitRules;
    final allLocalHabitCheckIns = ctx.allLocalHabitCheckIns;
    final allLocalHabitSleepCoachingPlans = ctx.allLocalHabitSleepCoachingPlans;
    final allLocalHabitDrinkOptions = ctx.allLocalHabitDrinkOptions;
    final remoteTodoEntries = ctx.remoteTodoEntries;
    final beforeRemoteRepair = ctx.beforeRemoteRepair;
    final remoteRecurrenceBaselines = ctx.remoteRecurrenceBaselines;
    final rejectedMaintenanceIds = ctx.rejectedMaintenanceIds;
    final repairedRemoteTodoIds = ctx.repairedRemoteTodoIds;
    final preMergeConflictIds = ctx.preMergeConflictIds;
    final todosIndexMap = ctx.todosIndexMap;
    final ignoredScheduleConflictKeys = ctx.ignoredScheduleConflictKeys;
    final inFlightGroupMutationUuids = ctx.inFlightGroupMutationUuids;
    final inFlightCountdownMutationUuids = ctx.inFlightCountdownMutationUuids;
    final inFlightTimeLogMutationUuids = ctx.inFlightTimeLogMutationUuids;
    final inFlightPlanBlockMutationUuids = ctx.inFlightPlanBlockMutationUuids;
    final inFlightFixedScheduleMutationUuids =
        ctx.inFlightFixedScheduleMutationUuids;
    final inFlightHabitGoalMutationUuids = ctx.inFlightHabitGoalMutationUuids;
    final inFlightHabitRuleMutationUuids = ctx.inFlightHabitRuleMutationUuids;
    final inFlightHabitCheckInMutationUuids =
        ctx.inFlightHabitCheckInMutationUuids;
    final inFlightHabitSleepCoachingMutationUuids =
        ctx.inFlightHabitSleepCoachingMutationUuids;
    final inFlightHabitDrinkOptionMutationUuids =
        ctx.inFlightHabitDrinkOptionMutationUuids;
    // 7. 持久化数据
    // Compute IDs of items whose conflict was cleared in this sync cycle
    final Set<String> recentlyResolvedIds = preMergeConflictIds.where((id) {
      final idx = todosIndexMap[id];
      if (idx == null) return false;
      return !allLocalTodos[idx].hasConflict;
    }).toSet();
    final receivedRecurringTodos = remoteTodoEntries.any(
      (entry) => _isRecurringTodoForLww(entry.item),
    );
    final recurrenceDedupeChangedIds = <String>{};
    if (repairedRemoteTodoIds.isNotEmpty || receivedRecurringTodos) {
      if (_deduplicatePersistedRecurrenceOccurrences(
        allLocalTodos,
        changedIds: recurrenceDedupeChangedIds,
      )) {
        repairedRemoteTodoIds.addAll(recurrenceDedupeChangedIds);
        ctx.hasChanges = true;
      }
      // A sync-source save intentionally does not clear this cache. Remote
      // recurring snapshots are different: the just-downloaded tombstones
      // or occurrences can expose a series-day gap that must be repaired on
      // the next read instead of waiting until tomorrow.
      _recurrenceCheckCache.clear();
    }
    // 远端旧设备可能仍保存着“重复截止日期”之后的实例。即使它们在
    // LWW 合并中赢过本机删除标记，也不能让已结束的循环再次复活；把
    // 这些实例转成删除 tombstone，并将修复结果回传给云端。
    final recurrenceBoundaryChangedIds =
        _pruneRecurrenceOccurrencesAfterEndDates(allLocalTodos);
    if (recurrenceBoundaryChangedIds.isNotEmpty) {
      repairedRemoteTodoIds.addAll(recurrenceBoundaryChangedIds);
      ctx.hasChanges = true;
      _recurrenceCheckCache.clear();
    }
    if (await getConflictDetectionEnabled()) {
      if (_recomputeLocalTodoScheduleConflicts(
        allLocalTodos,
        ignoredScheduleConflictKeys: ignoredScheduleConflictKeys,
        skipIds: recentlyResolvedIds,
      )) {
        ctx.hasChanges = true;
      }
    } else if (_clearLocalTodoScheduleConflicts(allLocalTodos)) {
      ctx.hasChanges = true;
    }

    if (ctx.hasChanges) {
      await UserSessionStorage.ensureCurrentSession(session);
      if (syncTodos) {
        await saveTodos(
          username,
          allLocalTodos,
          sync: false,
          isSyncSource: true,
          authoritativeTodoIds: rejectedMaintenanceIds,
        );
        if (inFlightGroupMutationUuids.isNotEmpty) {
          final latestGroups = await getTodoGroups(
            username,
            includeDeleted: true,
          );
          _overlayInFlightLocalMutations(
            allLocalGroups,
            latestGroups,
            inFlightGroupMutationUuids,
            (item) => item.id,
          );
        }
        await saveTodoGroups(
          username,
          allLocalGroups,
          sync: false,
          isSyncSource: true,
        );
      }
      if (syncCountdowns) {
        if (inFlightCountdownMutationUuids.isNotEmpty) {
          final latestCountdowns = await getCountdowns(
            username,
            includeDeleted: true,
          );
          _overlayInFlightLocalMutations(
            allLocalCountdowns,
            latestCountdowns,
            inFlightCountdownMutationUuids,
            (item) => item.id,
          );
        }
        await saveCountdowns(
          username,
          allLocalCountdowns,
          sync: false,
          isSyncSource: true,
        );
      }
      if (syncTimeLogs) {
        if (inFlightTimeLogMutationUuids.isNotEmpty) {
          final latestTimeLogs = await getTimeLogs(username);
          _overlayInFlightLocalMutations(
            allLocalTimeLogs,
            latestTimeLogs,
            inFlightTimeLogMutationUuids,
            (item) => item.id,
          );
        }
        await saveTimeLogs(username, allLocalTimeLogs, sync: false);
      }
      if (syncPlanBlocks) {
        if (inFlightPlanBlockMutationUuids.isNotEmpty) {
          final latestPlanBlocks = await getPlanBlocks(
            username,
            includeDeleted: true,
          );
          _overlayInFlightLocalMutations(
            allLocalPlanBlocks,
            latestPlanBlocks,
            inFlightPlanBlockMutationUuids,
            (item) => item.id,
          );
        }
        await savePlanBlocks(
          username,
          allLocalPlanBlocks,
          sync: false,
          isSyncSource: true,
        );
      }
      if (syncFixedSchedules && fixedSchedulesSupported) {
        if (inFlightFixedScheduleMutationUuids.isNotEmpty) {
          final latestFixedSchedules = await getFixedSchedules(
            username,
            includeDeleted: true,
          );
          _overlayInFlightLocalMutations(
            allLocalFixedSchedules,
            latestFixedSchedules,
            inFlightFixedScheduleMutationUuids,
            (item) => item.id,
          );
        }
        await saveFixedSchedules(
          username,
          allLocalFixedSchedules,
          sync: false,
          isSyncSource: true,
        );
      }
      if (syncHabits && habitsSupported) {
        if (inFlightHabitGoalMutationUuids.isNotEmpty) {
          final latestGoals = await HabitStorage.getHabitGoals(
            includeDeleted: true,
          );
          _overlayInFlightLocalMutations(
            allLocalHabitGoals,
            latestGoals,
            inFlightHabitGoalMutationUuids,
            (item) => item.uuid,
          );
        }
        if (inFlightHabitRuleMutationUuids.isNotEmpty) {
          final latestRules = await HabitStorage.getRuleRevisions();
          _overlayInFlightLocalMutations(
            allLocalHabitRules,
            latestRules,
            inFlightHabitRuleMutationUuids,
            (item) => item.uuid,
          );
        }
        if (inFlightHabitCheckInMutationUuids.isNotEmpty) {
          final latestCheckIns = await HabitStorage.getCheckIns(
            includeDeleted: true,
          );
          _overlayInFlightLocalMutations(
            allLocalHabitCheckIns,
            latestCheckIns,
            inFlightHabitCheckInMutationUuids,
            (item) => item.uuid,
          );
        }
        if (inFlightHabitSleepCoachingMutationUuids.isNotEmpty) {
          final latestCoaching = await HabitStorage.getSleepCoachingPlans(
            includeDeleted: true,
          );
          _overlayInFlightLocalMutations(
            allLocalHabitSleepCoachingPlans,
            latestCoaching,
            inFlightHabitSleepCoachingMutationUuids,
            (item) => item.uuid,
          );
        }
        if (inFlightHabitDrinkOptionMutationUuids.isNotEmpty) {
          final latestDrinks = await HabitStorage.getDrinkOptions(
            includeDeleted: true,
          );
          _overlayInFlightLocalMutations(
            allLocalHabitDrinkOptions,
            latestDrinks,
            inFlightHabitDrinkOptionMutationUuids,
            (item) => item.uuid,
          );
        }
        await HabitStorage.saveHabitGoals(
          allLocalHabitGoals,
          isSyncSource: true,
        );
        await HabitStorage.saveRuleRevisions(
          allLocalHabitRules,
          isSyncSource: true,
        );
        await HabitStorage.saveCheckIns(
          allLocalHabitCheckIns,
          isSyncSource: true,
        );
        await HabitStorage.saveSleepCoachingPlans(
          allLocalHabitSleepCoachingPlans,
          isSyncSource: true,
        );
        await HabitStorage.saveDrinkOptions(
          allLocalHabitDrinkOptions,
          isSyncSource: true,
        );
      }
      _pendingSyncOplogUuids.clear(); // 🚀 清除保护，防止跨同步周期的旧 UUID 干扰
      _forceFlushProtectedUuids.clear(); // 🚀 清除 force-flush 保护
    }

    if (syncPomodoro && syncPlanBlocks && pomodoroChanged) {
      await PomodoroService.reconcilePlanBlockProgress(username);
    }

    // Queue structural repairs without changing their user-write timestamps.
    // Local CAS checks the just-persisted row; server CAS checks the original
    // server snapshot, before series repair/dedupe changed its contents.
    if (repairedRemoteTodoIds.isNotEmpty) {
      final repairIdsToUpload = repairedRemoteTodoIds
          .where(
            (id) =>
                recurrenceDedupeChangedIds.contains(id) ||
                recurrenceBoundaryChangedIds.contains(id) ||
                !_attemptedRecurrenceSeriesRepairUploads.contains(
                  '$username|$id',
                ),
          )
          .toSet();
      final repairCandidates = allLocalTodos
          .where((todo) => repairIdsToUpload.contains(todo.id))
          .toList();
      final boundaryRepairSeries = repairCandidates
          .where((todo) => recurrenceBoundaryChangedIds.contains(todo.id))
          .map((todo) => todo.recurrenceSeriesId)
          .toSet();
      final boundaryRules = _recurrenceBoundaryRulesBySeries(allLocalTodos)
          .values
          .where(
            (rule) => boundaryRepairSeries.contains(rule.recurrenceSeriesId),
          )
          .toList();
      final repairReadIds = {
        ...repairCandidates.map((todo) => todo.id),
        ...boundaryRules.map((rule) => rule.id),
      }.toList();
      final repairBaselines = <String, TodoItem>{};
      final uploadBaselines = <String, TodoItem?>{};
      final repairedItems = <TodoItem>[];
      final persistedRepairItems = <String, TodoItem>{};
      const repairChunkSize = 400;
      for (
        var start = 0;
        start < repairReadIds.length;
        start += repairChunkSize
      ) {
        final rows = await DatabaseHelper.instance.getTodoMaps(
          includeDeleted: true,
          includeConflictData: true,
          uuids: repairReadIds.skip(start).take(repairChunkSize).toList(),
          databaseOverride: db,
        );
        for (final row in rows) {
          persistedRepairItems[row['uuid'].toString()] = TodoItem.fromSql(row);
        }
      }
      final staleBoundarySeries = <String?>{};
      for (final rule in boundaryRules) {
        final current = persistedRepairItems[rule.id];
        if (current == null ||
            _hasSubstantialChange(
              current.toJson(),
              rule.toJson(),
              _StorageTodos._todoSnapshotFields,
            )) {
          staleBoundarySeries.add(rule.recurrenceSeriesId);
          continue;
        }
        // A boundary repair depends on the rule as well as the extra row.
        // Carry both snapshots through local/server CAS, even after expiry
        // has cleared the rule's recurrence field.
        repairBaselines[rule.id] = current;
        uploadBaselines[rule.id] =
            remoteRecurrenceBaselines[rule.id] ?? beforeRemoteRepair[rule.id];
      }
      for (final todo in repairCandidates) {
        if (staleBoundarySeries.contains(todo.recurrenceSeriesId)) continue;
        final current = persistedRepairItems[todo.id];
        if (current == null ||
            _hasSubstantialChange(
              current.toJson(),
              todo.toJson(),
              _StorageTodos._todoSnapshotFields,
            )) {
          continue;
        }
        repairBaselines[todo.id] = current;
        uploadBaselines[todo.id] =
            remoteRecurrenceBaselines[todo.id] ?? beforeRemoteRepair[todo.id];
        todo.markRecurrenceMaintenanceChanged();
        repairedItems.add(todo);
      }
      if (repairedItems.isNotEmpty) {
        final saved = await _saveRecurrenceMaintenance(
          username,
          repairedItems,
          repairBaselines,
          uploadBaselines: uploadBaselines,
        );
        if (saved) {
          _attemptedRecurrenceSeriesRepairUploads.addAll(
            repairedItems.map((todo) => '$username|${todo.id}'),
          );
        }
        ctx.hasChanges = true;
        debugPrint('🧩 [同步修复] 已恢复并排队回传 ${repairedItems.length} 个循环实例的系列关系');
      }
    }
  }

  @override
  Future<void> _finalizeSyncWatermarksAndNotify(_SyncRunContext ctx) async {
    final username = ctx.username;
    final session = ctx.session;
    final prefs = ctx.prefs;
    final serverKey = ctx.serverKey;
    final fixedScheduleBootstrapKey = ctx.fixedScheduleBootstrapKey;
    final habitBootstrapKey = ctx.habitBootstrapKey;
    final habitCursorBootstrapKey = ctx.habitCursorBootstrapKey;
    final habitCursorCapabilityKey = ctx.habitCursorCapabilityKey;
    final syncTodos = ctx.syncTodos;
    final syncCountdowns = ctx.syncCountdowns;
    final syncScreenTime = ctx.syncScreenTime;
    final syncTimeLogs = ctx.syncTimeLogs;
    final syncPlanBlocks = ctx.syncPlanBlocks;
    final syncFixedSchedules = ctx.syncFixedSchedules;
    final syncHabits = ctx.syncHabits;
    final response = ctx.response;
    final fixedSchedulesSupported = ctx.fixedSchedulesSupported;
    final habitsSupported = ctx.habitsSupported;
    final habitSyncCursorSupported = ctx.habitSyncCursorSupported;
    final hasChanges = ctx.hasChanges;
    final scopedRefreshDomains = ctx.scopedRefreshDomains;
    final conflicts = ctx.conflicts;
    final allLocalTodos = ctx.allLocalTodos;
    final allLocalHabitGoals = ctx.allLocalHabitGoals;
    final allLocalHabitRules = ctx.allLocalHabitRules;
    final autoResolvedHabitConflictIds = ctx.autoResolvedHabitConflictIds;
    // 8. 更新同步水位线
    int newSyncTime =
        response['new_sync_time'] ?? DateTime.now().millisecondsSinceEpoch;
    final updatesSharedCoreCursor =
        syncTodos &&
        syncCountdowns &&
        syncTimeLogs &&
        syncPlanBlocks &&
        syncFixedSchedules;
    if (updatesSharedCoreCursor) {
      await prefs.setInt('last_sync_time_${serverKey}_$username', newSyncTime);
    }
    if (syncHabits && habitsSupported) {
      await prefs.setBool(habitCursorCapabilityKey, habitSyncCursorSupported);
      final rawHabitSyncTime = response['new_habit_sync_time'];
      final newHabitSyncTime = rawHabitSyncTime is num
          ? rawHabitSyncTime.toInt()
          : int.tryParse(rawHabitSyncTime?.toString() ?? '');
      if (habitSyncCursorSupported &&
          newHabitSyncTime != null &&
          newHabitSyncTime > 0) {
        await prefs.setInt(
          'habit_last_sync_time_${serverKey}_$username',
          newHabitSyncTime,
        );
        await prefs.setBool(habitCursorBootstrapKey, true);
      } else if (!habitSyncCursorSupported) {
        // 旧服务端没有独立 habits 水位，退回旧的全局水位，并标记
        // legacy cursor 已初始化，避免每次同步都重新全量上传习惯。
        await prefs.setInt(
          'habit_last_sync_time_${serverKey}_$username',
          newSyncTime,
        );
        await prefs.setBool(habitCursorBootstrapKey, true);
      }
    }
    if (syncFixedSchedules && fixedSchedulesSupported) {
      await prefs.setBool(fixedScheduleBootstrapKey, true);
    }
    if (syncHabits && habitsSupported) {
      await prefs.setBool(habitBootstrapKey, true);
    }

    // 如果屏幕时间同步成功，可以在这里刷新 UI 用的 Cache 数据（如果后端有返回最新的聚合数据）
    if (syncScreenTime && response['screen_time_results'] != null) {
      await UserSessionStorage.ensureCurrentSession(session);
      await saveScreenTimeCache(
        response['screen_time_results'],
        username: session.username,
      );
    }

    // 9. 只通知实际参与本轮同步的数据域，避免时间日志、习惯等局部同步
    // 重新读取整个首页数据集。
    if (hasChanges && scopedRefreshDomains.isNotEmpty) {
      triggerRefresh(scopedRefreshDomains);
    }

    final shouldIndexConflictItems =
        conflicts.length > 1 &&
        allLocalTodos.length +
                allLocalHabitGoals.length +
                allLocalHabitRules.length >
            64;
    Map<String, TodoItem>? localTodosByConflictId;
    Map<String, HabitGoal>? localHabitGoalsByConflictId;
    Map<String, HabitGoalRuleRevision>? localHabitRulesByConflictId;
    if (shouldIndexConflictItems) {
      final conflictIds = <String>{};
      var unresolvedConflictCount = 0;
      for (final conflict in conflicts) {
        final itemId = (conflict.item['uuid'] ?? conflict.item['id'])
            ?.toString();
        if (itemId == null ||
            itemId.isEmpty ||
            autoResolvedHabitConflictIds.contains(itemId)) {
          continue;
        }
        unresolvedConflictCount++;
        conflictIds.add(itemId);
      }
      if (unresolvedConflictCount > 1) {
        final todosById = <String, TodoItem>{};
        for (final todo in allLocalTodos) {
          if (conflictIds.contains(todo.id)) {
            todosById.putIfAbsent(todo.id, () => todo);
          }
        }
        localTodosByConflictId = todosById;

        final goalsById = <String, HabitGoal>{};
        for (final goal in allLocalHabitGoals) {
          if (conflictIds.contains(goal.uuid)) {
            goalsById.putIfAbsent(goal.uuid, () => goal);
          }
        }
        localHabitGoalsByConflictId = goalsById;

        final rulesById = <String, HabitGoalRuleRevision>{};
        for (final rule in allLocalHabitRules) {
          if (conflictIds.contains(rule.uuid)) {
            rulesById.putIfAbsent(rule.uuid, () => rule);
          }
        }
        localHabitRulesByConflictId = rulesById;
      }
    }

    TodoItem? findLocalTodo(String id) {
      final indexed = localTodosByConflictId;
      if (indexed != null) return indexed[id];
      for (final todo in allLocalTodos) {
        if (todo.id == id) return todo;
      }
      return null;
    }

    HabitGoal? findLocalHabitGoal(String id) {
      final indexed = localHabitGoalsByConflictId;
      if (indexed != null) return indexed[id];
      for (final goal in allLocalHabitGoals) {
        if (goal.uuid == id) return goal;
      }
      return null;
    }

    HabitGoalRuleRevision? findLocalHabitRule(String id) {
      final indexed = localHabitRulesByConflictId;
      if (indexed != null) return indexed[id];
      for (final rule in allLocalHabitRules) {
        if (rule.uuid == id) return rule;
      }
      return null;
    }

    conflicts.removeWhere((conflict) {
      final itemId = (conflict.item['uuid'] ?? conflict.item['id'])?.toString();
      if (itemId == null || itemId.isEmpty) return false;
      if (autoResolvedHabitConflictIds.contains(itemId)) return true;
      final local = findLocalTodo(itemId);
      if (local != null && (local.isDeleted || !local.hasConflict)) {
        return true;
      }
      final goal = findLocalHabitGoal(itemId);
      if (goal != null) return goal.isDeleted || !goal.hasConflict;
      final rule = findLocalHabitRule(itemId);
      if (rule != null) return rule.isDeleted || !rule.hasConflict;
      return false;
    });

    // 10. 🛡️ 内存守卫：同步成功后，自动从锁定集合中清理掉在最新 conflicts 中不再包含的 ID
    final serverConflictIds = conflicts
        .map((c) => (c.item['uuid'] ?? c.item['id'] ?? '').toString())
        .toSet();
    recentlyResolvedUuids.removeWhere((id) => !serverConflictIds.contains(id));
    recentlyResolvedTimes.removeWhere(
      (id, _) => !serverConflictIds.contains(id),
    );
    if (recentlyResolvedUuids.isNotEmpty) {
      debugPrint(
        '🛡️ [MemoryShield] Remaining locked items in memory shield: $recentlyResolvedUuids',
      );
    }

    await UserSessionStorage.ensureCurrentSession(session);
  }
}
