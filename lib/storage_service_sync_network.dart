part of 'storage_service.dart';

// ignore_for_file: unused_element, unused_element_parameter, annotate_overrides

mixin _StorageSyncNetwork on _StorageServiceBase {
  @override
  Future<void> _executeSyncNetworkRound(_SyncRunContext ctx) async {
    final username = ctx.username;
    final syncTodos = ctx.syncTodos;
    final syncCountdowns = ctx.syncCountdowns;
    final forceFullSync = ctx.forceFullSync;
    final syncScreenTime = ctx.syncScreenTime;
    final syncTimeLogs = ctx.syncTimeLogs;
    final syncPomodoro = ctx.syncPomodoro;
    final syncPlanBlocks = ctx.syncPlanBlocks;
    final syncFixedSchedules = ctx.syncFixedSchedules;
    final syncHabits = ctx.syncHabits;
    final financeSyncExplicitlyAuthorized = ctx.financeSyncExplicitlyAuthorized;
    final session = ctx.session;
    final prefs = ctx.prefs;
    final userId = ctx.userId;
    final db = ctx.db;
    final deviceId = ctx.deviceId;
    final fixedScheduleSyncInitialized = ctx.fixedScheduleSyncInitialized;
    final habitSyncInitialized = ctx.habitSyncInitialized;
    final lastSyncTime = ctx.lastSyncTime;
    final habitLastSyncTime = ctx.habitLastSyncTime;
    final financeRequest = ctx.financeRequest;
    final dirtyTodos = ctx.dirtyTodos;
    final dirtyGroups = ctx.dirtyGroups;
    final dirtyCountdowns = ctx.dirtyCountdowns;
    final dirtyTimeLogs = ctx.dirtyTimeLogs;
    final dirtyPlanBlocks = ctx.dirtyPlanBlocks;
    final dirtyFixedSchedules = ctx.dirtyFixedSchedules;
    final dirtyHabitGoals = ctx.dirtyHabitGoals;
    final dirtyHabitRules = ctx.dirtyHabitRules;
    final dirtyHabitCheckIns = ctx.dirtyHabitCheckIns;
    final dirtyHabitSleepCoachingPlans = ctx.dirtyHabitSleepCoachingPlans;
    final dirtyHabitDrinkOptions = ctx.dirtyHabitDrinkOptions;
    final allLocalTodos = ctx.allLocalTodos;
    final allLocalGroups = ctx.allLocalGroups;
    final allLocalCountdowns = ctx.allLocalCountdowns;
    final allLocalTimeLogs = ctx.allLocalTimeLogs;
    final allLocalFixedSchedules = ctx.allLocalFixedSchedules;
    final allLocalHabitGoals = ctx.allLocalHabitGoals;
    final allLocalHabitRules = ctx.allLocalHabitRules;
    final localTodosById = ctx.localTodosById;
    final requestOplogSnapshot = ctx.requestOplogSnapshot;
    final screenPayload = ctx.screenPayload;
    final updatedTodoIds = ctx.updatedTodoIds;
    final staleHabitConflictSnapshots = ctx.staleHabitConflictSnapshots;
    // 5. 发起网络同步请求
    final financePayload = financeRequest?.payload ?? const <String, dynamic>{};
    List<Map<String, dynamic>> financeChangesFor(String key) {
      final raw = financePayload[key];
      if (raw is! List) return const [];
      return raw
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList(growable: false);
    }

    Future<Map<String, dynamic>> sendSyncRequest() async {
      await UserSessionStorage.ensureCurrentSession(session);
      // Re-check immediately before every network attempt. This closes the
      // window between preparing the finance snapshot and the user turning
      // cloud sync off; explicit one-time manual sync remains authorized.
      if (ctx.syncFinance &&
          !financeSyncExplicitlyAuthorized &&
          !await AppSettingsStorage.isFinanceCloudSyncEnabled(username)) {
        ctx.syncFinance = false;
      }
      final syncResponse = await ApiService.postDeltaSync(
        userId: userId,
        lastSyncTime: lastSyncTime,
        deviceId: deviceId,
        todosChanges: dirtyTodos,
        todoGroupsChanges: dirtyGroups,
        countdownsChanges: dirtyCountdowns,
        timeLogsChanges: dirtyTimeLogs,
        planBlocksChanges: dirtyPlanBlocks,
        fixedSchedulesChanges: dirtyFixedSchedules,
        fixedSchedulesFullSync:
            syncFixedSchedules &&
            (!fixedScheduleSyncInitialized || forceFullSync),
        habitGoalsChanges: dirtyHabitGoals,
        habitRuleChanges: dirtyHabitRules,
        habitCheckInChanges: dirtyHabitCheckIns,
        habitSleepCoachingPlanChanges: dirtyHabitSleepCoachingPlans,
        habitDrinkOptionChanges: dirtyHabitDrinkOptions,
        habitFullSync: syncHabits && (!habitSyncInitialized || forceFullSync),
        habitLastSyncTime: syncHabits ? habitLastSyncTime : null,
        syncHabits: syncHabits,
        financeCategoryChanges: ctx.syncFinance
            ? financeChangesFor('finance_categories_changes')
            : const [],
        financePaymentMethodChanges: ctx.syncFinance
            ? financeChangesFor('finance_payment_methods_changes')
            : const [],
        financeTransactionChanges: ctx.syncFinance
            ? financeChangesFor('finance_transactions_changes')
            : const [],
        financeLoanChanges: ctx.syncFinance
            ? financeChangesFor('finance_loans_changes')
            : const [],
        financeLoanInstallmentChanges: ctx.syncFinance
            ? financeChangesFor('finance_loan_installments_changes')
            : const [],
        financeBudgetChanges: ctx.syncFinance
            ? financeChangesFor('finance_budgets_changes')
            : const [],
        financeRecurringRuleChanges: ctx.syncFinance
            ? financeChangesFor('finance_recurring_rules_changes')
            : const [],
        financeTemplateChanges: ctx.syncFinance
            ? financeChangesFor('finance_entry_templates_changes')
            : const [],
        financeFullSync: ctx.syncFinance && (financeRequest?.fullSync ?? false),
        financeLastSyncTime: ctx.syncFinance ? financeRequest?.cursor : null,
        syncFinance: ctx.syncFinance,
        screenTime: syncScreenTime ? screenPayload : null,
        forceFullSync: forceFullSync,
      );
      await UserSessionStorage.ensureCurrentSession(session);
      return syncResponse;
    }

    var response = await sendSyncRequest();
    await UserSessionStorage.ensureCurrentSession(session);
    bool hasPendingCoreUpload() =>
        dirtyTodos.isNotEmpty ||
        dirtyGroups.isNotEmpty ||
        dirtyCountdowns.isNotEmpty ||
        dirtyTimeLogs.isNotEmpty ||
        dirtyPlanBlocks.isNotEmpty ||
        dirtyFixedSchedules.isNotEmpty ||
        dirtyHabitGoals.isNotEmpty ||
        dirtyHabitRules.isNotEmpty ||
        dirtyHabitCheckIns.isNotEmpty ||
        dirtyHabitSleepCoachingPlans.isNotEmpty ||
        dirtyHabitDrinkOptions.isNotEmpty ||
        screenPayload != null;
    bool hasPendingFinanceUpload() =>
        ctx.syncFinance && (financeRequest?.hasPendingChanges ?? false);
    bool isDebounceIgnored(Map<String, dynamic> syncResponse) {
      final financeProtocolAvailable =
          ctx.syncFinance &&
          SyncCapabilityService.supportsFinance(
            syncResponse['sync_capabilities'],
          ) &&
          syncResponse['new_finance_sync_time'] != null &&
          syncResponse['finance_acknowledged_changes'] is List;
      final pendingForThisResponse =
          hasPendingCoreUpload() ||
          (financeProtocolAvailable && hasPendingFinanceUpload());
      if (!forceFullSync && !pendingForThisResponse) {
        return false;
      }
      final remotePayloadEmpty =
          (syncResponse['server_todos'] as List?)?.isEmpty == true &&
          (syncResponse['server_todo_groups'] as List?)?.isEmpty == true &&
          (syncResponse['server_countdowns'] as List?)?.isEmpty == true &&
          (syncResponse['server_time_logs'] as List?)?.isEmpty == true &&
          (syncResponse['server_pomodoros'] as List?)?.isEmpty == true &&
          (syncResponse['server_tags'] as List?)?.isEmpty == true &&
          (syncResponse['server_plan_blocks'] as List?)?.isEmpty == true &&
          (syncResponse['server_fixed_schedules'] as List?)?.isEmpty == true &&
          (syncResponse['server_habit_goals'] as List?)?.isEmpty == true &&
          (syncResponse['server_habit_goal_rules'] as List?)?.isEmpty == true &&
          (syncResponse['server_habit_checkins'] as List?)?.isEmpty == true &&
          (syncResponse['server_habit_sleep_coaching_plans'] as List?)
                  ?.isEmpty ==
              true &&
          (syncResponse['server_habit_drink_options'] as List?)?.isEmpty ==
              true &&
          (!financeProtocolAvailable ||
              ((syncResponse['server_finance_categories'] as List?)?.isEmpty ==
                      true &&
                  (syncResponse['server_finance_payment_methods'] as List?)
                          ?.isEmpty ==
                      true &&
                  (syncResponse['server_finance_transactions'] as List?)
                          ?.isEmpty ==
                      true &&
                  (syncResponse['server_finance_loans'] as List?)?.isEmpty ==
                      true &&
                  (syncResponse['server_finance_loan_installments'] as List?)
                          ?.isEmpty ==
                      true &&
                  (syncResponse['server_finance_budgets'] as List?)?.isEmpty ==
                      true &&
                  (syncResponse['server_finance_recurring_rules'] as List?)
                          ?.isEmpty ==
                      true &&
                  (syncResponse['server_finance_entry_templates'] as List?)
                          ?.isEmpty ==
                      true));
      final syncTimeUnchanged =
          (syncResponse['new_sync_time'] ?? -1) == lastSyncTime;
      final forceFullRelevant =
          forceFullSync &&
          (!ctx.syncFinance ||
              financeProtocolAvailable ||
              syncTodos ||
              syncCountdowns ||
              syncTimeLogs ||
              syncPomodoro ||
              syncPlanBlocks ||
              syncFixedSchedules ||
              syncHabits);
      return syncResponse['success'] == true &&
          syncTimeUnchanged &&
          remotePayloadEmpty &&
          (syncResponse['status'] == 'ignored' ||
              forceFullRelevant ||
              pendingForThisResponse);
    }

    if (isDebounceIgnored(response)) {
      debugPrint('⏳ [同步] 命中服务端防抖空响应，3.2s 后自动重试一次');
      await Future.delayed(const Duration(milliseconds: 3200));
      await UserSessionStorage.ensureCurrentSession(session);
      response = await sendSyncRequest();
      await UserSessionStorage.ensureCurrentSession(session);
      final financeProtocolAvailable =
          ctx.syncFinance &&
          SyncCapabilityService.supportsFinance(
            response['sync_capabilities'],
          ) &&
          response['new_finance_sync_time'] != null &&
          response['finance_acknowledged_changes'] is List;
      final hasPendingUploadForResponse =
          hasPendingCoreUpload() ||
          (financeProtocolAvailable && hasPendingFinanceUpload());
      if (isDebounceIgnored(response) && hasPendingUploadForResponse) {
        throw Exception('同步被服务端防抖延迟，已保留本地待同步记录');
      }
    }

    if (response['success'] != true) {
      final error = response['error']?.toString().trim().isNotEmpty == true
          ? response['error'].toString().trim()
          : response['message']?.toString().trim();
      throw Exception(error?.isNotEmpty == true ? error : '服务端未确认同步请求');
    }

    // /api/sync 是待办、习惯和记账共用的请求。用户在请求期间关闭
    // 记账同步时，只忽略本轮记账 ACK/快照，不取消整个请求，以免误伤
    // 其他数据域。未确认的记账修改保持 pending，不会前移记账游标。
    await UserSessionStorage.ensureCurrentSession(session);
    if (ctx.syncFinance &&
        !financeSyncExplicitlyAuthorized &&
        !await AppSettingsStorage.isFinanceCloudSyncEnabled(username)) {
      ctx.syncFinance = false;
      debugPrint('🔒 [记账同步] 请求期间授权已撤销，忽略本轮记账响应');
    }

    final fixedSchedulesSupported =
        SyncCapabilityService.supportsFixedSchedules(
          response['sync_capabilities'],
        );
    final acknowledgeFixedScheduleOps =
        SyncCapabilityService.shouldAcknowledgeFixedScheduleOps(
          syncEnabled: syncFixedSchedules,
          rawCapabilities: response['sync_capabilities'],
        );
    final habitsSupported = SyncCapabilityService.supportsHabits(
      response['sync_capabilities'],
    );
    final sleepCoachingSupported = SyncCapabilityService.supportsSleepCoaching(
      response['sync_capabilities'],
    );
    final habitDrinkOptionsSupported =
        SyncCapabilityService.supportsHabitDrinkOptions(
          response['sync_capabilities'],
        );
    final habitSyncCursorSupported =
        SyncCapabilityService.supportsHabitSyncCursor(
          response['sync_capabilities'],
        );
    final acknowledgeHabitOps = SyncCapabilityService.shouldAcknowledgeHabitOps(
      syncEnabled: syncHabits,
      rawCapabilities: response['sync_capabilities'],
    );
    final financeSupported = SyncCapabilityService.supportsFinance(
      response['sync_capabilities'],
    );
    final todoSkipStateSupported = SyncCapabilityService.supportsTodoSkipState(
      response['sync_capabilities'],
    );

    // 🚀 提取当前团队列表，用于孤立检测和合并防御
    final List<dynamic>? joinedTeamUuids = response['joined_team_uuids'];
    Set<String> currentTeams = joinedTeamUuids != null
        ? joinedTeamUuids.map((e) => e.toString()).toSet()
        : <String>{};

    // 🚀 补充：当 joinedTeamUuids 为 null 时，从本地 teams 表构建已知团队集合
    // 用于防复活守卫判断团队是否已解散
    if (joinedTeamUuids == null) {
      try {
        final localTeamRows = await db.query('teams', columns: ['uuid']);
        final localKnownTeams = localTeamRows
            .map((r) => r['uuid'].toString())
            .toSet();
        // 合并到 currentTeams 中，使孤立检测和防复活守卫也能受益
        currentTeams = localKnownTeams;
      } catch (_) {}
    }

    void markLoadedTeamItemsDeleted(String teamUuid) {
      final cleanupTime = DateTime.now().millisecondsSinceEpoch;

      for (final item in allLocalTodos) {
        if (item.teamUuid == teamUuid && !item.isDeleted) {
          item.isDeleted = true;
          item.version += 1;
          item.updatedAt = cleanupTime;
        }
      }
      for (final item in allLocalGroups) {
        if (item.teamUuid == teamUuid && !item.isDeleted) {
          item.isDeleted = true;
          item.version += 1;
          item.updatedAt = cleanupTime;
        }
      }
      for (final item in allLocalCountdowns) {
        if (item.teamUuid == teamUuid && !item.isDeleted) {
          item.isDeleted = true;
          item.version += 1;
          item.updatedAt = cleanupTime;
        }
      }
      for (final item in allLocalTimeLogs) {
        if (item.teamUuid == teamUuid && !item.isDeleted) {
          item.isDeleted = true;
          item.version += 1;
          item.updatedAt = cleanupTime;
        }
      }
      for (final item in allLocalFixedSchedules) {
        if (item.teamUuid == teamUuid && !item.isDeleted) {
          item.isDeleted = true;
          item.version += 1;
          item.updatedAt = cleanupTime;
        }
      }
    }

    var inFlightTodoMutationUuids = <String>{};
    var inFlightGroupMutationUuids = <String>{};
    var inFlightCountdownMutationUuids = <String>{};
    var inFlightTimeLogMutationUuids = <String>{};
    var inFlightPlanBlockMutationUuids = <String>{};
    var inFlightFixedScheduleMutationUuids = <String>{};
    var inFlightHabitGoalMutationUuids = <String>{};
    var inFlightHabitRuleMutationUuids = <String>{};
    var inFlightHabitCheckInMutationUuids = <String>{};
    var inFlightHabitSleepCoachingMutationUuids = <String>{};
    var inFlightHabitDrinkOptionMutationUuids = <String>{};
    if (response['success'] == true) {
      // 仅标记“未冲突”的本地操作为已同步。阻塞冲突对应的 oplog 必须保留，
      // 否则本地完成/取消完成会被服务端旧状态覆盖后失去再次上传机会。
      final List<dynamic> rawConflicts = (response['conflicts'] as List?) ?? [];
      final Set<String> blockingConflictUuids = <String>{};
      for (final c in rawConflicts) {
        if (c is! Map) continue;
        final type = c['type']?.toString();
        if (type == 'schedule_conflict' || type == 'pomodoro') {
          continue;
        }
        final item = c['item'];
        if (item is! Map) continue;
        final uuid = (item['uuid'] ?? item['id'] ?? item['todo_uuid'])
            ?.toString();
        if (uuid != null && uuid.isNotEmpty) {
          blockingConflictUuids.add(uuid);
        }
      }

      final oplogResolution = SyncOplogPolicy.resolveRequestSnapshot(
        requestSnapshot: requestOplogSnapshot,
        blockingConflictUuids: blockingConflictUuids,
        acknowledgeTodoOps: syncTodos,
        acknowledgeCountdownOps: syncCountdowns,
        acknowledgeTimeLogOps: syncTimeLogs,
        acknowledgePlanBlockOps: syncPlanBlocks,
        acknowledgeFixedScheduleOps: acknowledgeFixedScheduleOps,
        acknowledgeHabitOps: acknowledgeHabitOps,
        acknowledgeSleepCoachingOps: syncHabits && sleepCoachingSupported,
        acknowledgeHabitDrinkOptionOps:
            syncHabits && habitDrinkOptionsSupported,
      );
      await _updateOplogRowsByIds(db, oplogResolution.acknowledgedIds, {
        'is_synced': 1,
        'sync_error': '',
      });
      await _updateOplogRowsByIds(db, oplogResolution.blockedIds, {
        'is_synced': 0,
        'sync_error': 'server_conflict',
      });

      // 重新读取当前待同步日志。本次请求发出后新增的操作
      // 没有上传，不能被本次响应确认，也不能被旧的服务端快照覆盖。
      final currentPendingRows = await db.query(
        'op_logs',
        where: 'is_synced = 0',
        orderBy: 'timestamp ASC, id ASC',
      );
      final currentPendingEntries = currentPendingRows
          .map(SyncOplogEntry.fromRow)
          .whereType<SyncOplogEntry>()
          .toList(growable: false);
      _pendingSyncOplogUuids = SyncOplogPolicy.todoUuids(currentPendingEntries);
      inFlightTodoMutationUuids = SyncOplogPolicy.todoUuidsCreatedAfterSnapshot(
        requestSnapshot: requestOplogSnapshot,
        currentPending: currentPendingEntries,
      );
      inFlightGroupMutationUuids =
          SyncOplogPolicy.uuidsCreatedAfterSnapshotForTables(
            requestSnapshot: requestOplogSnapshot,
            currentPending: currentPendingEntries,
            tables: const {'todo_groups'},
          );
      inFlightCountdownMutationUuids =
          SyncOplogPolicy.uuidsCreatedAfterSnapshotForTables(
            requestSnapshot: requestOplogSnapshot,
            currentPending: currentPendingEntries,
            tables: const {'countdowns'},
          );
      inFlightTimeLogMutationUuids =
          SyncOplogPolicy.uuidsCreatedAfterSnapshotForTables(
            requestSnapshot: requestOplogSnapshot,
            currentPending: currentPendingEntries,
            tables: const {'time_logs'},
          );
      inFlightPlanBlockMutationUuids =
          SyncOplogPolicy.uuidsCreatedAfterSnapshotForTables(
            requestSnapshot: requestOplogSnapshot,
            currentPending: currentPendingEntries,
            tables: const {'todo_plan_blocks'},
          );
      inFlightFixedScheduleMutationUuids =
          SyncOplogPolicy.uuidsCreatedAfterSnapshotForTables(
            requestSnapshot: requestOplogSnapshot,
            currentPending: currentPendingEntries,
            tables: const {'fixed_schedules'},
          );
      inFlightHabitGoalMutationUuids =
          SyncOplogPolicy.uuidsCreatedAfterSnapshotForTables(
            requestSnapshot: requestOplogSnapshot,
            currentPending: currentPendingEntries,
            tables: const {HabitStorage.tableGoals},
          );
      inFlightHabitRuleMutationUuids =
          SyncOplogPolicy.uuidsCreatedAfterSnapshotForTables(
            requestSnapshot: requestOplogSnapshot,
            currentPending: currentPendingEntries,
            tables: const {HabitStorage.tableRules},
          );
      inFlightHabitCheckInMutationUuids =
          SyncOplogPolicy.uuidsCreatedAfterSnapshotForTables(
            requestSnapshot: requestOplogSnapshot,
            currentPending: currentPendingEntries,
            tables: const {HabitStorage.tableCheckIns},
          );
      inFlightHabitSleepCoachingMutationUuids =
          SyncOplogPolicy.uuidsCreatedAfterSnapshotForTables(
            requestSnapshot: requestOplogSnapshot,
            currentPending: currentPendingEntries,
            tables: const {HabitStorage.tableSleepCoachingPlans},
          );
      inFlightHabitDrinkOptionMutationUuids =
          SyncOplogPolicy.uuidsCreatedAfterSnapshotForTables(
            requestSnapshot: requestOplogSnapshot,
            currentPending: currentPendingEntries,
            tables: const {HabitStorage.tableDrinkOptions},
          );
      if (inFlightTodoMutationUuids.isNotEmpty) {
        // allLocalTodos 是请求发出前的快照。用当前 SQLite 值回基
        // 请求期间被修改的待办，使后续合并和全量落库都保留最新用户意图。
        final latestRows = await DatabaseHelper.instance.getTodoMaps(
          includeDeleted: true,
          uuids: inFlightTodoMutationUuids.toList(),
          includeConflictData: true,
        );
        final latestById = <String, TodoItem>{
          for (final row in latestRows)
            row['uuid'].toString(): TodoItem.fromJson(row),
        };
        for (var i = 0; i < allLocalTodos.length; i++) {
          final latest = latestById[allLocalTodos[i].id];
          if (latest != null) {
            allLocalTodos[i] = latest;
            localTodosById[latest.id] = latest;
          }
        }
      }

      // 🚀 处理独立待办完成情况
      final List<dynamic>? indCompletions = response['independent_completions'];
      //debugPrint(
      //    '🧪 [SyncDiag][IndepCompletion] indCompletions=${indCompletions?.length ?? "null"}');
      if (indCompletions != null) {
        final completionTodoUuids = <String>{};
        for (final ic in indCompletions) {
          if (ic is! Map) continue;
          final todoUuid = ic['todo_uuid']?.toString();
          if (todoUuid == null || todoUuid.isEmpty) continue;
          if (SyncOplogPolicy.shouldProtectTodoMerge(
            todoUuid,
            forceFlushUuids: _forceFlushProtectedUuids,
            inFlightMutationUuids: inFlightTodoMutationUuids,
          )) {
            continue;
          }
          completionTodoUuids.add(todoUuid);
        }

        final completionTodoUuidList = completionTodoUuids.toList(
          growable: false,
        );
        final localCompletionsByTodoUuid = <String, Map<String, Object?>>{};
        const queryChunkSize = 500;
        for (
          var start = 0;
          start < completionTodoUuidList.length;
          start += queryChunkSize
        ) {
          final end = start + queryChunkSize < completionTodoUuidList.length
              ? start + queryChunkSize
              : completionTodoUuidList.length;
          final chunk = completionTodoUuidList.sublist(start, end);
          final placeholders = List.filled(chunk.length, '?').join(', ');
          final completionRows = await db.query(
            'todo_completions',
            where: 'todo_uuid IN ($placeholders) AND user_id = ?',
            whereArgs: [...chunk, userId],
          );
          for (final row in completionRows) {
            final todoUuid = row['todo_uuid']?.toString();
            if (todoUuid != null) {
              localCompletionsByTodoUuid.putIfAbsent(todoUuid, () => row);
            }
          }
        }

        final batch = db.batch();
        var independentCompletionChanged = false;
        for (var ic in indCompletions) {
          if (ic is! Map) continue;
          final todoUuid = ic['todo_uuid']?.toString();
          if (todoUuid == null || todoUuid.isEmpty) continue;
          if (SyncOplogPolicy.shouldProtectTodoMerge(
            todoUuid,
            forceFlushUuids: _forceFlushProtectedUuids,
            inFlightMutationUuids: inFlightTodoMutationUuids,
          )) {
            continue;
          }
          if (!completionTodoUuids.contains(todoUuid)) {
            // Protection may have been lifted while the batched read was
            // awaiting SQLite; fetch this newly eligible row before merge.
            final rows = await db.query(
              'todo_completions',
              where: 'todo_uuid = ? AND user_id = ?',
              whereArgs: [todoUuid, userId],
              limit: 1,
            );
            if (rows.isNotEmpty) {
              localCompletionsByTodoUuid[todoUuid] = rows.first;
            }
            completionTodoUuids.add(todoUuid);
          }
          final rawCompleted = ic['is_completed'];
          final isCompleted =
              rawCompleted == 1 ||
              rawCompleted == true ||
              rawCompleted?.toString() == '1' ||
              rawCompleted?.toString().toLowerCase() == 'true';
          final rawSkipped = ic['is_skipped'];
          final serverIsSkipped =
              rawSkipped == 1 ||
              rawSkipped == true ||
              rawSkipped?.toString() == '1' ||
              rawSkipped?.toString().toLowerCase() == 'true';
          final serverUpdatedAt =
              int.tryParse(ic['updated_at']?.toString() ?? '') ?? 0;
          final existing = localCompletionsByTodoUuid[todoUuid];
          final existingIsSkipped =
              (existing?['is_skipped'] as num?)?.toInt() == 1;
          final existingSkipPending =
              (existing?['is_skipped_sync_pending'] as num?)?.toInt() == 1;
          final hasServerSkipValue = ic.containsKey('is_skipped');
          final skipAcknowledged =
              todoSkipStateSupported &&
              hasServerSkipValue &&
              (!existingSkipPending || serverIsSkipped == existingIsSkipped);
          final useServerSkipValue =
              todoSkipStateSupported &&
              hasServerSkipValue &&
              (!existingSkipPending || skipAcknowledged);
          final mergedIsSkipped = useServerSkipValue
              ? serverIsSkipped
              : existingIsSkipped;
          final mergedSkipPending = existingSkipPending && !skipAcknowledged;
          final localUpdatedAt =
              (existing?['updated_at'] as num?)?.toInt() ?? 0;
          // 🚀 时间戳比较修复：如果本地没有完成状态记录，判定为从未修改（localUpdatedAt=0），此时应接受服务端更新
          // 仅当本地有明确的更新时间且晚于服务端时，才跳过 DB 写入
          final hasLocalModification = localUpdatedAt > 0;
          if (hasLocalModification &&
              serverUpdatedAt > 0 &&
              serverUpdatedAt < localUpdatedAt) {
            // 本地有更新且晚于服务端，跳过 DB 写入，但仍需从 DB 读取正确值更新内存
            final localIsCompleted = (existing?['is_completed'] as int?) ?? 0;
            final localTodo = localTodosById[todoUuid];
            if (localTodo != null && localTodo.collabType == 1) {
              if (localTodo.isSkipped != existingIsSkipped ||
                  localTodo.isSkippedSyncPending != existingSkipPending) {
                localTodo.isSkipped = existingIsSkipped;
                localTodo.isSkippedSyncPending = existingSkipPending;
                independentCompletionChanged = true;
                if (!localTodo.isDeleted) updatedTodoIds.add(todoUuid);
              }
              if (localTodo.isDone != (localIsCompleted == 1)) {
                localTodo.isDone = localIsCompleted == 1;
                independentCompletionChanged = true;
                if (!localTodo.isDeleted) {
                  updatedTodoIds.add(todoUuid);
                }
              }
            }
            //debugPrint(
            //    '🧪 [SyncDiag][IndepCompletion] SKIP_DB $todoUuid (server $serverUpdatedAt < local $localUpdatedAt), memory isDone=${localIsCompleted == 1}');
            continue;
          }
          //debugPrint(
          //    '🧪 [SyncDiag][IndepCompletion] WRITE $todoUuid isCompleted=$isCompleted (raw=$rawCompleted)');
          batch.insert('todo_completions', {
            'todo_uuid': todoUuid,
            'user_id': userId,
            'is_completed': isCompleted ? 1 : 0,
            'is_skipped': mergedIsSkipped ? 1 : 0,
            'is_skipped_sync_pending': mergedSkipPending ? 1 : 0,
            'updated_at': serverUpdatedAt > 0
                ? serverUpdatedAt
                : DateTime.now().millisecondsSinceEpoch,
          }, conflictAlgorithm: ConflictAlgorithm.replace);
          final localTodo = localTodosById[todoUuid];
          if (localTodo != null && localTodo.collabType == 1) {
            if (localTodo.isSkipped != mergedIsSkipped ||
                localTodo.isSkippedSyncPending != mergedSkipPending) {
              localTodo.isSkipped = mergedIsSkipped;
              localTodo.isSkippedSyncPending = mergedSkipPending;
              independentCompletionChanged = true;
              if (!localTodo.isDeleted) updatedTodoIds.add(todoUuid);
            }
            if (localTodo.isDone != isCompleted) {
              localTodo.isDone = isCompleted;
              independentCompletionChanged = true;
              if (!localTodo.isDeleted) {
                updatedTodoIds.add(todoUuid);
              }
            }
            final serverCompletedAt = JsonValueParser.toInt(ic['completed_at']);
            if (isCompleted &&
                serverCompletedAt > 0 &&
                localTodo.completedAt != serverCompletedAt) {
              localTodo.completedAt = serverCompletedAt;
              independentCompletionChanged = true;
            } else if (!isCompleted && localTodo.completedAt != null) {
              localTodo.completedAt = null;
              independentCompletionChanged = true;
            }
          }
        }
        await batch.commit(noResult: true);
        if (independentCompletionChanged) {
          ctx.hasChanges = true;
        }
      }

      // 🚀 核心修复：清理本地孤立的团队数据 (处理离线被移出团队的情况)
      if (joinedTeamUuids != null) {
        // 获取本地所有存在的 team_uuid (联合查询：待办、倒计时、文件夹)
        final localTeamRows = await db.rawQuery('''
            SELECT DISTINCT team_uuid FROM todos
            WHERE team_uuid IS NOT NULL AND TRIM(team_uuid) != '' AND is_deleted = 0
            UNION
            SELECT DISTINCT team_uuid FROM countdowns
            WHERE team_uuid IS NOT NULL AND TRIM(team_uuid) != '' AND is_deleted = 0
            UNION
            SELECT DISTINCT team_uuid FROM todo_groups
            WHERE team_uuid IS NOT NULL AND TRIM(team_uuid) != '' AND is_deleted = 0
            UNION
            SELECT DISTINCT team_uuid FROM time_logs
            WHERE team_uuid IS NOT NULL AND TRIM(team_uuid) != '' AND is_deleted = 0
            UNION
            SELECT DISTINCT team_uuid FROM courses
            WHERE team_uuid IS NOT NULL AND TRIM(team_uuid) != '' AND is_deleted = 0
            UNION
            SELECT DISTINCT team_uuid FROM fixed_schedules
            WHERE team_uuid IS NOT NULL AND TRIM(team_uuid) != '' AND is_deleted = 0
          ''');
        bool teamChanged = false;
        for (var row in localTeamRows) {
          String? tUuid = row['team_uuid']?.toString();
          if (tUuid != null && !currentTeams.contains(tUuid)) {
            debugPrint("🧹 发现孤立团队数据: $tUuid, 正在清理...");
            await clearTeamItems(tUuid);
            markLoadedTeamItemsDeleted(tUuid);
            ctx.hasChanges = true;
            teamChanged = true;
          }
        }

        // 课程、待办等本地数据数量不能代表团队订阅数量：一个刚加入但
        // 尚无本地数据的团队也必须订阅，反之有残留数据的已退出团队也
        // 不应继续占用频道。只与 WebSocket 实际订阅集合比较。
        final subscribedTeamUuids =
            PomodoroSyncService.instance.subscribedTeamUuids;
        final subscriptionsChanged =
            currentTeams.length != subscribedTeamUuids.length ||
            !currentTeams.containsAll(subscribedTeamUuids) ||
            !subscribedTeamUuids.containsAll(currentTeams);
        if (teamChanged || subscriptionsChanged) {
          debugPrint("👥 [协同] 团队列表发生变化，请求 WebSocket 刷新订阅...");
          // 利用 resumeSync 内部的逻辑可以触发重连与重新订阅
          Future.microtask(() => PomodoroSyncService.instance.resumeSync());
        }
      }
    } else {
      final errorMsg = response['message']?.toString() ?? '同步失败';

      // 🚀 记录同步失败的原因，方便用户查看
      await db.update('op_logs', {
        'sync_error': errorMsg,
      }, where: 'is_synced = 0');
      throw Exception(errorMsg);
    }

    if (ctx.syncFinance && financeRequest != null) {
      final financeResult = await FinanceSyncService.finish(
        request: financeRequest,
        response: response,
        supported: financeSupported,
      );
      if (financeResult.hasChanges) ctx.hasChanges = true;
      if (financeResult.recurringRulesChanged) {
        unawaited(
          ReminderScheduleService.scheduleCurrentUser().catchError((error) {
            debugPrint('⚠️ [记账同步] 刷新周期账单提醒失败: $error');
          }),
        );
      }
      ctx.financeConflicts = financeResult.rejectedChanges;
      if (financeResult.localChangesDuringRequest) {
        debugPrint('🛡️ [记账同步] 请求期间发生本地修改，本轮不前移记账水位线');
      }
      if (financeResult.rejectedChanges.isNotEmpty) {
        debugPrint(
          '⚠️ [记账同步] 服务端拒绝 ${financeResult.rejectedChanges.length} 条无效或过期记录',
        );
      }
    }

    // 解析服务器返回的实时冲突
    if (response['conflicts'] is List) {
      ctx.conflicts = (response['conflicts'] as List)
          .map((c) => ConflictInfo.fromJson(c as Map<String, dynamic>))
          .toList();
    }

    // 服务端有时只在 conflicts 返回冲突快照，不会重复返回整条习惯记录。
    // 先把这些快照登记下来，后面可判断是否只是残留冲突标记。
    final localHabitGoalIds = allLocalHabitGoals
        .map((item) => item.uuid)
        .toSet();
    final localHabitRuleIds = allLocalHabitRules
        .map((item) => item.uuid)
        .toSet();
    for (final conflict in ctx.conflicts) {
      final itemId = (conflict.item['uuid'] ?? conflict.item['id'])?.toString();
      if (itemId == null || itemId.isEmpty || conflict.conflictWith.isEmpty) {
        continue;
      }
      final table = localHabitGoalIds.contains(itemId)
          ? 'habit_goals'
          : localHabitRuleIds.contains(itemId)
          ? 'habit_goal_rule_revisions'
          : null;
      if (table != null) {
        staleHabitConflictSnapshots['$table:$itemId'] =
            Map<String, dynamic>.from(conflict.conflictWith);
      }
    }

    // 🛡️ 屏幕时间逻辑优化：上传成功后，务必清理“待上传”缓存
    if (screenPayload != null) {
      await prefs.remove(_scopedKey(keyLocalScreenTime, username));
      debugPrint("✅ 本机屏幕时间上传成功，已清理待上传缓存");
    }

    ctx.response = response;
    ctx.fixedSchedulesSupported = fixedSchedulesSupported;
    ctx.acknowledgeFixedScheduleOps = acknowledgeFixedScheduleOps;
    ctx.habitsSupported = habitsSupported;
    ctx.sleepCoachingSupported = sleepCoachingSupported;
    ctx.habitDrinkOptionsSupported = habitDrinkOptionsSupported;
    ctx.habitSyncCursorSupported = habitSyncCursorSupported;
    ctx.acknowledgeHabitOps = acknowledgeHabitOps;
    ctx.financeSupported = financeSupported;
    ctx.todoSkipStateSupported = todoSkipStateSupported;
    ctx.joinedTeamUuids = joinedTeamUuids;
    ctx.currentTeams = currentTeams;
    ctx.inFlightTodoMutationUuids = inFlightTodoMutationUuids;
    ctx.inFlightGroupMutationUuids = inFlightGroupMutationUuids;
    ctx.inFlightCountdownMutationUuids = inFlightCountdownMutationUuids;
    ctx.inFlightTimeLogMutationUuids = inFlightTimeLogMutationUuids;
    ctx.inFlightPlanBlockMutationUuids = inFlightPlanBlockMutationUuids;
    ctx.inFlightFixedScheduleMutationUuids = inFlightFixedScheduleMutationUuids;
    ctx.inFlightHabitGoalMutationUuids = inFlightHabitGoalMutationUuids;
    ctx.inFlightHabitRuleMutationUuids = inFlightHabitRuleMutationUuids;
    ctx.inFlightHabitCheckInMutationUuids = inFlightHabitCheckInMutationUuids;
    ctx.inFlightHabitSleepCoachingMutationUuids =
        inFlightHabitSleepCoachingMutationUuids;
    ctx.inFlightHabitDrinkOptionMutationUuids =
        inFlightHabitDrinkOptionMutationUuids;
  }
}
