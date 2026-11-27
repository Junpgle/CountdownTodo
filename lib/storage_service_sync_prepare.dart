part of 'storage_service.dart';

// ignore_for_file: unused_element, unused_element_parameter, annotate_overrides

mixin _StorageSyncPrepare on _StorageServiceBase {
  @override
  Future<void> _prepareSyncUploadPayload(_SyncRunContext ctx) async {
    final username = ctx.username;
    final syncTodos = ctx.syncTodos;
    final syncCountdowns = ctx.syncCountdowns;
    final forceFullSync = ctx.forceFullSync;
    final shouldUploadAllLocal = ctx.shouldUploadAllLocal;
    final syncScreenTime = ctx.syncScreenTime;
    final syncTimeLogs = ctx.syncTimeLogs;
    final syncPlanBlocks = ctx.syncPlanBlocks;
    final syncFixedSchedules = ctx.syncFixedSchedules;
    final syncHabits = ctx.syncHabits;
    final session = ctx.session;
    final friendlyName = ctx.friendlyName;
    final fixedScheduleSyncInitialized = ctx.fixedScheduleSyncInitialized;
    final habitSyncInitialized = ctx.habitSyncInitialized;
    final habitLastSyncTime = ctx.habitLastSyncTime;
    final staleHabitConflictSnapshots = ctx.staleHabitConflictSnapshots;
    // 3. 🛡️ 核心修复：基于 op_logs 识别脏数据，并进行 UUID 去重处理（防止 1000+ 冗余同步）
    await UserSessionStorage.ensureCurrentSession(session);
    final db = await DatabaseHelper.instance.databaseForUser(username);
    List<Map<String, dynamic>> dirtyTodos = [];
    List<Map<String, dynamic>> dirtyGroups = [];
    List<Map<String, dynamic>> dirtyCountdowns = [];
    List<Map<String, dynamic>> dirtyTimeLogs = [];
    List<Map<String, dynamic>> dirtyPlanBlocks = [];
    List<Map<String, dynamic>> dirtyFixedSchedules = [];
    List<Map<String, dynamic>> dirtyHabitGoals = [];
    List<Map<String, dynamic>> dirtyHabitRules = [];
    List<Map<String, dynamic>> dirtyHabitCheckIns = [];
    List<Map<String, dynamic>> dirtyHabitSleepCoachingPlans = [];
    List<Map<String, dynamic>> dirtyHabitDrinkOptions = [];
    // Read independent local stores concurrently and skip disabled domains.
    // SQLite may serialize the native queries, but model decoding/isolate
    // work and SharedPreferences-backed stores no longer form one long chain.
    final localSnapshots = await Future.wait<dynamic>([
      syncTodos
          ? getTodos(username, includeDeleted: true)
          : Future<List<TodoItem>>.value(const []),
      syncTodos
          ? getTodoGroups(username, includeDeleted: true)
          : Future<List<TodoGroup>>.value(const []),
      syncCountdowns
          ? getCountdowns(username, includeDeleted: true)
          : Future<List<CountdownItem>>.value(const []),
      syncTimeLogs
          ? getTimeLogs(username)
          : Future<List<TimeLogItem>>.value(const []),
      syncPlanBlocks
          ? getPlanBlocks(username, includeDeleted: true)
          : Future<List<TodoPlanBlock>>.value(const []),
      syncFixedSchedules
          ? getFixedSchedules(username, includeDeleted: true)
          : Future<List<FixedScheduleItem>>.value(const []),
      syncHabits
          ? HabitStorage.getHabitGoals(includeDeleted: true)
          : Future<List<HabitGoal>>.value(const []),
      syncHabits
          ? HabitStorage.getRuleRevisions()
          : Future<List<HabitGoalRuleRevision>>.value(const []),
      syncHabits
          ? HabitStorage.getCheckIns(includeDeleted: true)
          : Future<List<HabitCheckIn>>.value(const []),
      syncHabits
          ? HabitStorage.getSleepCoachingPlans(includeDeleted: true)
          : Future<List<HabitSleepCoachingPlan>>.value(const []),
      syncHabits
          ? HabitStorage.getDrinkOptions(includeDeleted: true)
          : Future<List<HabitDrinkOption>>.value(const []),
    ]);
    final List<TodoItem> allLocalTodos = localSnapshots[0];
    final List<TodoGroup> allLocalGroups = localSnapshots[1];
    final List<CountdownItem> allLocalCountdowns = localSnapshots[2];
    final List<TimeLogItem> allLocalTimeLogs = localSnapshots[3];
    final List<TodoPlanBlock> allLocalPlanBlocks = localSnapshots[4];
    final List<FixedScheduleItem> allLocalFixedSchedules = localSnapshots[5];
    final List<HabitGoal> allLocalHabitGoals = localSnapshots[6];
    final List<HabitGoalRuleRevision> allLocalHabitRules = localSnapshots[7];
    final List<HabitCheckIn> allLocalHabitCheckIns = localSnapshots[8];
    final List<HabitSleepCoachingPlan> allLocalHabitSleepCoachingPlans =
        localSnapshots[9];
    final List<HabitDrinkOption> allLocalHabitDrinkOptions = localSnapshots[10];
    final conflictedHabitGoalIds = syncHabits ? <String>{} : const <String>{};
    // 有些历史冲突只保存在本地 conflict_data，服务端后续同步不一定
    // 再把它放进 conflicts 或 server_habit_goals，因此这里也要登记快照。
    for (final goal in allLocalHabitGoals) {
      if (!goal.hasConflict) continue;
      conflictedHabitGoalIds.add(goal.uuid);
      if (goal.conflictData == null) continue;
      staleHabitConflictSnapshots['habit_goals:${goal.uuid}'] =
          Map<String, dynamic>.from(goal.conflictData!);
    }
    final conflictedHabitRuleIds = syncHabits ? <String>{} : const <String>{};
    for (final rule in allLocalHabitRules) {
      if (!rule.hasConflict) continue;
      conflictedHabitRuleIds.add(rule.uuid);
      if (rule.conflictData == null) continue;
      staleHabitConflictSnapshots['habit_goal_rule_revisions:${rule.uuid}'] =
          Map<String, dynamic>.from(rule.conflictData!);
    }
    final conflictRepairBaselines = {
      for (final todo in allLocalTodos) todo.id: todo.detachedCopy(),
    };
    final autoResolvedMigrationConflicts =
        _clearResolvedRecurrenceMigrationConflicts(allLocalTodos);
    if (autoResolvedMigrationConflicts.isNotEmpty) {
      await _saveRecurrenceMaintenance(
        username,
        allLocalTodos,
        conflictRepairBaselines,
      );
      ctx.hasChanges = true;
      debugPrint(
        '🧹 [同步修复] 已自动消解 ${autoResolvedMigrationConflicts.length} 条仅由循环系列迁移产生的版本冲突',
      );
    }
    final autoResolvedCollabConflicts = _clearResolvedCollabCompletionConflicts(
      allLocalTodos,
    );
    if (autoResolvedCollabConflicts.isNotEmpty) {
      await saveTodos(
        username,
        autoResolvedCollabConflicts,
        sync: false,
        isSyncSource: true,
        recomputeScheduleConflicts: false,
      );
      ctx.hasChanges = true;
      debugPrint(
        '🧹 [同步修复] 已自动消解 ${autoResolvedCollabConflicts.length} 条仅由各自完成状态差异产生的版本冲突',
      );
    }
    final localSeriesBaselines = {
      for (final todo in allLocalTodos) todo.id: todo.detachedCopy(),
    };
    final repairedLocalSeriesIds =
        await _repairLocalRecurrenceSeriesAliasesFromHistory(db, allLocalTodos);
    if (repairedLocalSeriesIds.isNotEmpty) {
      final deletedBeforeDedupe = {
        for (final todo in allLocalTodos)
          if (todo.isDeleted) todo.id,
      };
      _deduplicatePersistedRecurrenceOccurrences(allLocalTodos);
      repairedLocalSeriesIds.addAll(
        allLocalTodos
            .where(
              (todo) =>
                  todo.isDeleted && !deletedBeforeDedupe.contains(todo.id),
            )
            .map((todo) => todo.id),
      );

      await _saveRecurrenceMaintenance(
        username,
        allLocalTodos,
        localSeriesBaselines,
      );
      ctx.hasChanges = true;
      debugPrint(
        '🧷 [同步修复] 根据本机同步历史将 ${repairedLocalSeriesIds.length} 个被拆分的循环实例归回原系列',
      );
    }
    final localTodosById = {for (final item in allLocalTodos) item.id: item};
    final localGroupsById = {for (final item in allLocalGroups) item.id: item};
    final localCountdownsById = {
      for (final item in allLocalCountdowns) item.id: item,
    };
    if (!forceFullSync &&
        allLocalTodos.isEmpty &&
        allLocalGroups.isEmpty &&
        allLocalCountdowns.isEmpty &&
        allLocalTimeLogs.isEmpty &&
        (syncTodos || syncCountdowns || syncTimeLogs)) {
      debugPrint('🔄 本地核心同步表为空，自动降级为全量拉取以修复空库');
      ctx.lastSyncTime = 0;
    }

    // 按时间戳升序排列，这样 Map 的 putIfAbsent/赋值逻辑会自然保留最后一次更新
    final List<Map<String, dynamic>> pendingOps = await db.query(
      'op_logs',
      where: 'is_synced = 0',
      orderBy: 'timestamp ASC, id ASC',
    );
    final requestOplogSnapshot = pendingOps
        .map(SyncOplogEntry.fromRow)
        .whereType<SyncOplogEntry>()
        .toList(growable: false);
    // 🚀 记录有待同步 oplog 的 待办 UUID，防止 saveTodos(isSyncSource=true) 覆盖用户修改
    _pendingSyncOplogUuids = pendingOps
        .where((op) => op['target_table'] == 'todos')
        .map((op) => op['target_uuid']?.toString() ?? '')
        .where((uuid) => uuid.isNotEmpty)
        .toSet();
    final pendingByTable = <String, int>{};
    for (final op in pendingOps) {
      final t = (op['target_table'] ?? 'unknown').toString();
      pendingByTable[t] = (pendingByTable[t] ?? 0) + 1;
    }
    /*debugPrint(
          '🧪 [SyncDiag][PendingOps] total=${pendingOps.length} byTable=$pendingByTable');*/

    final Map<String, Map<String, dynamic>> dedupTodos = {};
    final Map<String, Map<String, dynamic>> dedupGroups = {};
    final Map<String, Map<String, dynamic>> dedupCountdowns = {};
    final Map<String, Map<String, dynamic>> dedupPlanBlocks = {};
    final Map<String, Map<String, dynamic>> dedupFixedSchedules = {};
    final Map<String, Map<String, dynamic>> dedupHabitGoals = {};
    final Map<String, Map<String, dynamic>> dedupHabitRules = {};
    final Map<String, Map<String, dynamic>> dedupHabitCheckIns = {};
    final Map<String, Map<String, dynamic>> dedupHabitSleepCoachingPlans = {};
    final Map<String, Map<String, dynamic>> dedupHabitDrinkOptions = {};
    final List<int> consumedConflictOpIds = [];

    for (var op in pendingOps) {
      final table = op['target_table'];
      final uuid = op['target_uuid']?.toString();
      final dataJson = op['data_json'];
      final opId = (op['id'] as num?)?.toInt();

      if (dataJson == null || uuid == null) continue;
      final data = jsonDecode(dataJson.toString());

      if (table == 'todos' && syncTodos) {
        data.remove('image_path');
        data.remove('imagePath');
        // 🚀 已失败的冲突 op_log 不再重新发送（避免无限循环）
        if (op['sync_error'] == 'server_conflict') {
          if (opId != null) consumedConflictOpIds.add(opId);
          continue;
        }
        final localTodo = localTodosById[uuid];
        final hasLocalVersionConflict =
            localTodo != null &&
            localTodo.hasConflict &&
            ConflictVisibilityService.isVersionConflictData(
              localTodo.serverVersionData,
            );
        if (_payloadHasVersionConflict(data) || hasLocalVersionConflict) {
          if (opId != null) consumedConflictOpIds.add(opId);
          continue;
        }
        SyncOplogPolicy.collectTodoPayload(
          dedupTodos,
          uuid,
          _stripClientOnlyConflictForSync(data),
        );
      } else if (table == 'todo_groups' && syncTodos) {
        if (op['sync_error'] == 'server_conflict') {
          if (opId != null) consumedConflictOpIds.add(opId);
          continue;
        }
        if (_payloadHasConflict(data) ||
            (localGroupsById[uuid]?.hasConflict ?? false)) {
          if (opId != null) consumedConflictOpIds.add(opId);
          continue;
        }
        dedupGroups[uuid] = data;
      } else if (table == 'countdowns' && syncCountdowns) {
        if (op['sync_error'] == 'server_conflict') {
          if (opId != null) consumedConflictOpIds.add(opId);
          continue;
        }
        if (_payloadHasConflict(data) ||
            (localCountdownsById[uuid]?.hasConflict ?? false)) {
          if (opId != null) consumedConflictOpIds.add(opId);
          continue;
        }
        dedupCountdowns[uuid] = data;
      } else if (table == 'todo_plan_blocks' && syncPlanBlocks) {
        dedupPlanBlocks[uuid] = data;
      } else if (table == 'fixed_schedules' && syncFixedSchedules) {
        dedupFixedSchedules[uuid] = data;
      } else if (table == 'habit_goals' && syncHabits) {
        if (op['sync_error'] == 'server_conflict') {
          if (opId != null) consumedConflictOpIds.add(opId);
          continue;
        }
        if (_payloadHasConflict(data) ||
            conflictedHabitGoalIds.contains(uuid)) {
          if (opId != null) consumedConflictOpIds.add(opId);
          continue;
        }
        dedupHabitGoals[uuid] = data;
      } else if (table == 'habit_goal_rule_revisions' && syncHabits) {
        if (op['sync_error'] == 'server_conflict') {
          if (opId != null) consumedConflictOpIds.add(opId);
          continue;
        }
        if (_payloadHasConflict(data) ||
            conflictedHabitRuleIds.contains(uuid)) {
          if (opId != null) consumedConflictOpIds.add(opId);
          continue;
        }
        dedupHabitRules[uuid] = data;
      } else if (table == 'habit_checkins' && syncHabits) {
        if (op['sync_error'] == 'server_conflict') {
          if (opId != null) consumedConflictOpIds.add(opId);
          continue;
        }
        dedupHabitCheckIns[uuid] = data;
      } else if (table == 'habit_sleep_coaching_plans' && syncHabits) {
        if (op['sync_error'] == 'server_conflict') {
          if (opId != null) consumedConflictOpIds.add(opId);
          continue;
        }
        dedupHabitSleepCoachingPlans[uuid] = data;
      } else if (table == 'habit_drink_options' && syncHabits) {
        if (op['sync_error'] == 'server_conflict') {
          if (opId != null) consumedConflictOpIds.add(opId);
          continue;
        }
        dedupHabitDrinkOptions[uuid] = data;
      }
    }

    if (consumedConflictOpIds.isNotEmpty) {
      await _updateOplogRowsByIds(db, consumedConflictOpIds.toSet(), {
        'is_synced': 1,
        'sync_error': '',
      });
      /*debugPrint(
            '🧪 [SyncDiag][PendingOps] consumed conflict ops=${consumedConflictOpIds.length}');*/
    }

    dirtyTodos = dedupTodos.values.toList();
    dirtyGroups = dedupGroups.values.toList();
    dirtyCountdowns = dedupCountdowns.values.toList();
    dirtyPlanBlocks = dedupPlanBlocks.values.toList();
    dirtyFixedSchedules = dedupFixedSchedules.values.toList();
    dirtyHabitGoals = dedupHabitGoals.values.toList();
    dirtyHabitRules = dedupHabitRules.values.toList();
    dirtyHabitCheckIns = dedupHabitCheckIns.values.toList();
    dirtyHabitSleepCoachingPlans = dedupHabitSleepCoachingPlans.values.toList();
    dirtyHabitDrinkOptions = dedupHabitDrinkOptions.values.toList();

    // 兜底：除 op_logs 外，再按 updatedAt 增量补采，避免日志遗漏导致改删/新增不同步
    if (syncTodos) {
      for (final item in allLocalTodos) {
        if (item.updatedAt > ctx.lastSyncTime) {
          if (item.hasConflict &&
              ConflictVisibilityService.isVersionConflictData(
                item.serverVersionData,
              )) {
            continue;
          }
          final data = item.toJson();
          data.remove('image_path');
          data.remove('imagePath');
          if (item.isDeleted &&
              _recurrenceDedupeTombstoneIds.contains(item.id)) {
            data['_recurrence_delete_reason'] = 'dedupe';
          }
          // The pending payload can be newer than this earlier read snapshot,
          // and can carry insert-only/maintenance semantics absent on models.
          dedupTodos.putIfAbsent(
            item.id,
            () => _stripClientOnlyConflictForSync(data),
          );
        }
      }
      dirtyTodos = dedupTodos.values.toList();
    }
    if (syncCountdowns) {
      for (final item in allLocalCountdowns) {
        if (item.updatedAt > ctx.lastSyncTime) {
          if (item.hasConflict) continue;
          dedupCountdowns[item.id] = item.toJson();
        }
      }
      dirtyCountdowns = dedupCountdowns.values.toList();
    }
    if (syncTodos) {
      for (final item in allLocalGroups) {
        if (item.updatedAt > ctx.lastSyncTime) {
          if (item.hasConflict) continue;
          dedupGroups[item.id] = item.toJson();
        }
      }
      dirtyGroups = dedupGroups.values.toList();
    }

    // 兜底：规划块除 op_logs 外，再按 updatedAt 增量补采一遍，避免个别日志遗漏导致改删不同步
    if (syncPlanBlocks) {
      for (final item in allLocalPlanBlocks) {
        if (item.updatedAt > ctx.lastSyncTime) {
          dedupPlanBlocks[item.id] = item.toJson();
        }
      }
      dirtyPlanBlocks = dedupPlanBlocks.values.toList();
    }

    // 首次与支持 fixed_schedules v1 的服务端握手前，全量携带本地固定
    // 日程，确保“本地纵向切片”时期创建的数据不会因旧水位线而漏传。
    if (syncFixedSchedules) {
      for (final item in allLocalFixedSchedules) {
        if (!fixedScheduleSyncInitialized ||
            item.updatedAt > ctx.lastSyncTime) {
          dedupFixedSchedules[item.id] = item.toJson();
        }
      }
      dirtyFixedSchedules = dedupFixedSchedules.values.toList();
    }

    // 习惯：与固定日程一致的引导策略。首次与支持 habits v1 的服务端
    // 握手前全量携带本地习惯数据，避免 PR5 之前（未写 oplog）创建的
    // 习惯因旧水位线而漏传。
    if (syncHabits) {
      for (final item in allLocalHabitGoals) {
        if (!habitSyncInitialized || item.updatedAt > habitLastSyncTime) {
          dedupHabitGoals[item.uuid] = item.toJson();
        }
      }
      for (final item in allLocalHabitRules) {
        if (!habitSyncInitialized || item.updatedAt > habitLastSyncTime) {
          dedupHabitRules[item.uuid] = item.toJson();
        }
      }
      for (final item in allLocalHabitCheckIns) {
        if (!habitSyncInitialized || item.updatedAt > habitLastSyncTime) {
          dedupHabitCheckIns[item.uuid] = item.toJson();
        }
      }
      for (final item in allLocalHabitSleepCoachingPlans) {
        if (!habitSyncInitialized || item.updatedAt > habitLastSyncTime) {
          dedupHabitSleepCoachingPlans[item.uuid] = item.toJson();
        }
      }
      for (final item in allLocalHabitDrinkOptions) {
        if (!habitSyncInitialized || item.updatedAt > habitLastSyncTime) {
          dedupHabitDrinkOptions[item.uuid] = item.toJson();
        }
      }
      dirtyHabitGoals = dedupHabitGoals.values.toList();
      dirtyHabitRules = dedupHabitRules.values.toList();
      dirtyHabitCheckIns = dedupHabitCheckIns.values.toList();
      dirtyHabitSleepCoachingPlans = dedupHabitSleepCoachingPlans.values
          .toList();
      dirtyHabitDrinkOptions = dedupHabitDrinkOptions.values.toList();
    }

    if (shouldUploadAllLocal) {
      if (syncTodos) {
        for (final item in allLocalTodos) {
          if (item.hasConflict &&
              ConflictVisibilityService.isVersionConflictData(
                item.serverVersionData,
              )) {
            continue;
          }
          final data = _stripClientOnlyConflictForSync(item.toJson());
          data.remove('image_path');
          data.remove('imagePath');
          if (item.isDeleted &&
              _recurrenceDedupeTombstoneIds.contains(item.id)) {
            data['_recurrence_delete_reason'] = 'dedupe';
          }
          dedupTodos.putIfAbsent(item.id, () => data);
        }
        for (final item in allLocalGroups) {
          if (item.hasConflict) continue;
          final data = item.toJson();
          dedupGroups.putIfAbsent(item.id, () => data);
        }
      }
      if (syncCountdowns) {
        for (final item in allLocalCountdowns) {
          if (item.hasConflict) continue;
          final data = item.toJson();
          dedupCountdowns.putIfAbsent(item.id, () => data);
        }
      }
      if (syncPlanBlocks) {
        for (final item in allLocalPlanBlocks) {
          final data = item.toJson();
          dedupPlanBlocks.putIfAbsent(item.id, () => data);
        }
      }
      if (syncFixedSchedules) {
        for (final item in allLocalFixedSchedules) {
          dedupFixedSchedules.putIfAbsent(item.id, item.toJson);
        }
      }
      if (syncHabits) {
        for (final item in allLocalHabitGoals) {
          dedupHabitGoals.putIfAbsent(item.uuid, item.toJson);
        }
        for (final item in allLocalHabitRules) {
          dedupHabitRules.putIfAbsent(item.uuid, item.toJson);
        }
        for (final item in allLocalHabitCheckIns) {
          dedupHabitCheckIns.putIfAbsent(item.uuid, item.toJson);
        }
        for (final item in allLocalHabitSleepCoachingPlans) {
          dedupHabitSleepCoachingPlans.putIfAbsent(item.uuid, item.toJson);
        }
        for (final item in allLocalHabitDrinkOptions) {
          dedupHabitDrinkOptions.putIfAbsent(item.uuid, item.toJson);
        }
      }
      dirtyTodos = dedupTodos.values.toList();
      dirtyGroups = dedupGroups.values.toList();
      dirtyCountdowns = dedupCountdowns.values.toList();
      dirtyPlanBlocks = dedupPlanBlocks.values.toList();
      dirtyFixedSchedules = dedupFixedSchedules.values.toList();
      dirtyHabitGoals = dedupHabitGoals.values.toList();
      dirtyHabitRules = dedupHabitRules.values.toList();
      dirtyHabitCheckIns = dedupHabitCheckIns.values.toList();
      dirtyHabitSleepCoachingPlans = dedupHabitSleepCoachingPlans.values
          .toList();
      dirtyHabitDrinkOptions = dedupHabitDrinkOptions.values.toList();
    }

    // Re-send skip state until an explicitly capable server confirms it.
    // The pending flag is local metadata and is removed by the sync payload
    // sanitizer before this row leaves the device.
    if (syncTodos) {
      for (final item in allLocalTodos) {
        if (!item.isSkippedSyncPending || item.hasConflict) continue;
        final data = _stripClientOnlyConflictForSync(item.toJson());
        data.remove('image_path');
        data.remove('imagePath');
        dedupTodos[item.id] = data;
      }
      dirtyTodos = dedupTodos.values.toList();
    }

    // TimeLogs 暂时保持原有逻辑 (直到迁移至 SQL)
    if (syncTimeLogs) {
      dirtyTimeLogs = allLocalTimeLogs
          .where((t) => t.updatedAt > ctx.lastSyncTime)
          .map((t) => t.toJson())
          .toList();
    }

    // debugPrint('🔍 [同步判定] ctx.lastSyncTime: $ctx.lastSyncTime, 本地总任务数: ${allLocalTodos.length}');

    // 4. 读取本机待同步屏幕时间 (改为 Map 结构)。局部同步关闭该域时，
    // 不能把待上传缓存偷偷带入通用 delta 请求。
    final localPackage = syncScreenTime
        ? await getLocalScreenTimeMap(username: session.username)
        : const <String, dynamic>{};
    List<dynamic> localScreenStats = localPackage['apps'] ?? [];
    String? recordDate = localPackage['date']; // 🚀 从缓存中拿原始日期

    Map<String, dynamic>? screenPayload;
    if (localScreenStats.isNotEmpty) {
      try {
        // 如果没有记录日期（旧版本升级上来），退而求其次用今天
        final String finalDate =
            recordDate ?? time_utils.AppTimeFormats.date(DateTime.now());

        screenPayload = {
          'device_name': friendlyName,
          'record_date': finalDate,
          'apps': localScreenStats
              .whereType<Map>()
              .map(
                (e) => {
                  'app_name': e['app_name']?.toString() ?? 'Unknown',
                  'duration': (e['duration'] is int) ? e['duration'] : 0,
                },
              )
              .toList(),
        };
        debugPrint(
          "🚀 准备同步本机屏幕时间 ($finalDate): ${localScreenStats.length} 条数据",
        );
      } catch (se) {
        debugPrint("屏幕时间 payload 构造失败: $se");
      }
    } else {
      // null
    }

    ctx.db = db;
    ctx.dirtyTodos = dirtyTodos;
    ctx.dirtyGroups = dirtyGroups;
    ctx.dirtyCountdowns = dirtyCountdowns;
    ctx.dirtyTimeLogs = dirtyTimeLogs;
    ctx.dirtyPlanBlocks = dirtyPlanBlocks;
    ctx.dirtyFixedSchedules = dirtyFixedSchedules;
    ctx.dirtyHabitGoals = dirtyHabitGoals;
    ctx.dirtyHabitRules = dirtyHabitRules;
    ctx.dirtyHabitCheckIns = dirtyHabitCheckIns;
    ctx.dirtyHabitSleepCoachingPlans = dirtyHabitSleepCoachingPlans;
    ctx.dirtyHabitDrinkOptions = dirtyHabitDrinkOptions;
    ctx.allLocalTodos = allLocalTodos;
    ctx.allLocalGroups = allLocalGroups;
    ctx.allLocalCountdowns = allLocalCountdowns;
    ctx.allLocalTimeLogs = allLocalTimeLogs;
    ctx.allLocalPlanBlocks = allLocalPlanBlocks;
    ctx.allLocalFixedSchedules = allLocalFixedSchedules;
    ctx.allLocalHabitGoals = allLocalHabitGoals;
    ctx.allLocalHabitRules = allLocalHabitRules;
    ctx.allLocalHabitCheckIns = allLocalHabitCheckIns;
    ctx.allLocalHabitSleepCoachingPlans = allLocalHabitSleepCoachingPlans;
    ctx.allLocalHabitDrinkOptions = allLocalHabitDrinkOptions;
    ctx.conflictedHabitGoalIds = conflictedHabitGoalIds;
    ctx.conflictedHabitRuleIds = conflictedHabitRuleIds;
    ctx.localTodosById = localTodosById;
    ctx.pendingOps = pendingOps;
    ctx.requestOplogSnapshot = requestOplogSnapshot;
    ctx.screenPayload = screenPayload;
  }
}
