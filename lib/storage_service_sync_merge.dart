part of 'storage_service.dart';

// ignore_for_file: unused_element, unused_element_parameter, annotate_overrides

mixin _StorageSyncMerge on _StorageServiceBase {
  @override
  Future<void> _mergeServerSyncResponse(_SyncRunContext ctx) async {
    final username = ctx.username;
    final deviceId = ctx.deviceId;
    final forceFullSync = ctx.forceFullSync;
    final syncTodos = ctx.syncTodos;
    final syncCountdowns = ctx.syncCountdowns;
    final syncTimeLogs = ctx.syncTimeLogs;
    final syncPomodoro = ctx.syncPomodoro;
    final syncPlanBlocks = ctx.syncPlanBlocks;
    final syncFixedSchedules = ctx.syncFixedSchedules;
    final syncHabits = ctx.syncHabits;
    final db = ctx.db;
    final response = ctx.response;
    final fixedSchedulesSupported = ctx.fixedSchedulesSupported;
    final habitsSupported = ctx.habitsSupported;
    final todoSkipStateSupported = ctx.todoSkipStateSupported;
    final currentTeams = ctx.currentTeams;
    final inFlightTodoMutationUuids = ctx.inFlightTodoMutationUuids;
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
    final localTodosById = ctx.localTodosById;
    final conflicts = ctx.conflicts;
    final updatedTodoIds = ctx.updatedTodoIds;
    final staleHabitConflictSnapshots = ctx.staleHabitConflictSnapshots;
    final autoResolvedHabitConflictIds = ctx.autoResolvedHabitConflictIds;
    // 6. 🛡️ 数据合并逻辑 (LWW - Last Write Wins) — O(1) HashMap lookup

    // 🚀 核心修复：获取本地忽略表，防止”僵尸数据”复活
    final ignoredRows = await db.query('ignored_remote_items');
    final Set<String> ignoredUuids = ignoredRows
        .map((e) => e['uuid'].toString())
        .toSet();

    // 合并 Todos。旧版服务端没有持久化 recurrence_series_id；先利用本地
    // 已知关系或唯一、可验证的循环轨迹修复，再进入常规 LWW 合并。
    List<dynamic> serverTodos = syncTodos
        ? (response['server_todos'] ?? [])
        : const [];
    final remoteTodoEntries = <({Map<String, dynamic> raw, TodoItem item})>[];
    for (final raw in serverTodos) {
      final serverRaw = raw is Map
          ? raw.cast<String, dynamic>()
          : <String, dynamic>{};
      final sanitizedServerRaw = _stripClientOnlyConflictForSync(serverRaw);
      remoteTodoEntries.add((
        raw: serverRaw,
        item: TodoItem.fromJson(sanitizedServerRaw),
      ));
    }
    for (final entry in remoteTodoEntries) {
      final local = localTodosById[entry.item.id];
      if (local == null || !local.isSkippedSyncPending) continue;
      final hasServerSkipValue =
          entry.raw.containsKey('is_skipped') ||
          entry.raw.containsKey('isSkipped');
      final acknowledged =
          todoSkipStateSupported &&
          hasServerSkipValue &&
          entry.item.isSkipped == local.isSkipped;
      if (acknowledged) {
        local.isSkippedSyncPending = false;
        entry.item.isSkippedSyncPending = false;
      } else {
        // An old server's missing field is not an acknowledgement and its
        // snapshot cannot erase the user's local skip.
        entry.item.isSkipped = local.isSkipped;
        entry.item.isSkippedSyncPending = true;
      }
    }
    final beforeRemoteRepair = {
      for (final todo in allLocalTodos) todo.id: todo.detachedCopy(),
    };
    final remoteRecurrenceBaselines = {
      for (final entry in remoteTodoEntries)
        entry.item.id: entry.item.detachedCopy(),
    };
    final rejectedMaintenanceIds =
        (response['todo_maintenance_rejected_uuids'] as List? ?? const [])
            .map((id) => id.toString())
            .toSet();
    final repairedRemoteTodoIds = _repairMissingRemoteRecurrenceSeriesIds(
      remoteTodoEntries.map((entry) => entry.item).toList(),
      allLocalTodos,
    );

    // Snapshot items with conflicts before merge, to detect resolutions after merge
    final Set<String> preMergeConflictIds = allLocalTodos
        .where((t) => t.hasConflict)
        .map((t) => t.id)
        .toSet();

    final Map<String, int> todosIndexMap = {
      for (var i = 0; i < allLocalTodos.length; i++) allLocalTodos[i].id: i,
    };
    for (final entry in remoteTodoEntries) {
      final serverRaw = entry.raw;
      final sItem = entry.item;
      if (ignoredUuids.contains(sItem.id)) {
        debugPrint('🚫 [合并跳过] UUID: ${sItem.id} 已在本地忽略列表中');
        continue;
      }
      // 🚀 核心防御：非所属团队的数据处理（防止退出/被踢后数据回流）
      if (ctx.isOutsideJoinedTeam(sItem.teamUuid)) {
        debugPrint(
          '🚫 [合并跳过] UUID: ${sItem.id} 团队 ${sItem.teamUuid} 已不在当前团队列表中',
        );
        continue;
      }
      final serverDeviceId = serverRaw['device_id']?.toString();
      final bool isUpdatedByOtherDevice =
          serverDeviceId != null &&
          serverDeviceId.isNotEmpty &&
          serverDeviceId != deviceId;
      if (todosIndexMap.containsKey(sItem.id)) {
        final idx = todosIndexMap[sItem.id]!;
        final local = allLocalTodos[idx];
        final usesStrictRecurringLww =
            _isRecurringTodoForLww(local) || _isRecurringTodoForLww(sItem);
        final serverWinsStrictRecurringLww =
            rejectedMaintenanceIds.contains(sItem.id) ||
            TodoLwwService.shouldReplaceRecurringSnapshot(
              incomingUpdatedAt: sItem.updatedAt,
              incomingVersion: sItem.version,
              currentUpdatedAt: local.updatedAt,
              currentVersion: local.version,
              incomingHasConflict: sItem.hasConflict,
            );

        // 请求前强制落库或请求期间新增的本地修改均跳过本次
        // merge，防止用请求发出前的旧内存/服务端快照覆盖用户意图。
        if (SyncOplogPolicy.shouldProtectTodoMerge(
          sItem.id,
          forceFlushUuids: _forceFlushProtectedUuids,
          inFlightMutationUuids: inFlightTodoMutationUuids,
        )) {
          debugPrint(
            '🛡️ [merge] SKIP UUID=${sItem.id} (local mutation protected)',
          );
          continue;
        }

        debugPrint(
          '🔄 [合并对比] UUID: ${sItem.id}, Server(V:${sItem.version}, D:${sItem.isDeleted}), Local(V:${local.version}, D:${local.isDeleted})',
        );

        // 防回滚：本地已删除且更”新”时，拒绝服务端旧的未删除数据复活
        if (!rejectedMaintenanceIds.contains(sItem.id) &&
            local.isDeleted &&
            !sItem.isDeleted &&
            local.updatedAt > sItem.updatedAt &&
            local.version >= sItem.version) {
          continue;
        }

        // 🚀 核心防护：本地已删除的团队待办，拒绝服务端未删除版本复活
        // 团队解散后，服务端可能因时序问题返回旧的未删除版本
        if (local.isDeleted &&
            !sItem.isDeleted &&
            local.teamUuid != null &&
            local.teamUuid!.isNotEmpty &&
            sItem.version <= local.version &&
            (!usesStrictRecurringLww || !serverWinsStrictRecurringLww)) {
          debugPrint(
            '🛡️ [防复活] UUID: ${sItem.id} 本地已删除(V:${local.version})，服务端未删除(V:${sItem.version})，拒绝复活',
          );
          continue;
        }
        // 🚀 补充防护：已解散团队的已删除待办，无条件拒绝未删除版本复活
        // 通过 currentTeams 判断团队是否已解散（兼容 joinedTeamUuids 为 null 的情况）
        if (local.isDeleted &&
            !sItem.isDeleted &&
            local.teamUuid != null &&
            local.teamUuid!.isNotEmpty &&
            currentTeams.isNotEmpty &&
            !currentTeams.contains(local.teamUuid)) {
          debugPrint(
            '🛡️ [防复活-强拦截] UUID: ${sItem.id} 团队 ${local.teamUuid} 已解散(currentTeams=$currentTeams)，拒绝未删除版本复活',
          );
          continue;
        }

        final mergeVersionCond = sItem.version > local.version;
        final mergeTimeCond =
            sItem.updatedAt > local.updatedAt && !sItem.hasConflict;
        if (sItem.hasConflict || local.hasConflict) {
          debugPrint(
            '🩺 [合并决策] UUID=${sItem.id} sV=${sItem.version} lV=${local.version} sU=${sItem.updatedAt} lU=${local.updatedAt} sConflict=${sItem.hasConflict} lConflict=${local.hasConflict} versionCond=$mergeVersionCond timeCond=$mergeTimeCond isDeleted=${sItem.isDeleted}',
          );
        }
        final shouldReplaceTodo = usesStrictRecurringLww
            ? serverWinsStrictRecurringLww
            : sItem.isDeleted || mergeVersionCond || mergeTimeCond;
        if (shouldReplaceTodo) {
          _preserveLocalTodoSourceFields(local, sItem);
          allLocalTodos[idx] = sItem;
          if (!sItem.isDeleted && isUpdatedByOtherDevice) {
            updatedTodoIds.add(sItem.id);
          }
          ctx.hasChanges = true;
        } else if (sItem.groupId != local.groupId &&
            (usesStrictRecurringLww
                ? serverWinsStrictRecurringLww
                : sItem.updatedAt >= local.updatedAt)) {
          // Only accept group_id changes if server item is at least as new
          // as local item, preserving LWW semantics for folder assignments.
          allLocalTodos[idx].groupId = sItem.groupId;
          ctx.hasChanges = true;
        }

        // Handle conflict flag divergence separately from content merge.
        // Prevents overwriting a local resolution while still syncing conflict state.
        if (!sItem.isDeleted && todosIndexMap.containsKey(sItem.id)) {
          final idx2 = todosIndexMap[sItem.id]!;
          final localItem = allLocalTodos[idx2];
          // 服务端 isDataDifferent 已排除 collabType=1 的纯完成状态变化，
          // 若服务端标记了冲突，说明确有内容差异，客户端应尊重该标记。
          if (sItem.hasConflict && !localItem.hasConflict) {
            if (isRecentlyResolved(localItem.id)) {
              debugPrint(
                '⏭️ [MemoryShield] Skipping conflict resurrection for recently resolved todo: ${localItem.id}',
              );
            } else {
              // Server still has conflict but local was resolved — sync conflict metadata only
              localItem.hasConflict = true;
              localItem.serverVersionData = sItem.serverVersionData;
              ctx.hasChanges = true;
            }
          } else if (!sItem.hasConflict && localItem.hasConflict) {
            // Server cleared conflict (resolved from another device) — accept cleared state
            localItem.hasConflict = false;
            localItem.serverVersionData = null;
            recentlyResolvedUuids.remove(sItem.id);
            recentlyResolvedTimes.remove(sItem.id);
            ctx.hasChanges = true;
          }
        }
      } else {
        if (!sItem.isDeleted) {
          todosIndexMap[sItem.id] = allLocalTodos.length;
          allLocalTodos.add(sItem);
          if (isUpdatedByOtherDevice) {
            updatedTodoIds.add(sItem.id);
          }
          ctx.hasChanges = true;
        }
      }
    }

    // 合并 TodoGroups
    List<dynamic> serverGroups = syncTodos
        ? (response['server_todo_groups'] ?? [])
        : const [];
    final Map<String, int> groupsIndexMap = {
      for (var i = 0; i < allLocalGroups.length; i++) allLocalGroups[i].id: i,
    };
    for (var raw in serverGroups) {
      TodoGroup sItem = TodoGroup.fromJson(raw);
      if (ignoredUuids.contains(sItem.id)) {
        debugPrint('🚫 [合并跳过] 文件夹 UUID: ${sItem.id} 已忽略');
        continue;
      }
      if (ctx.isOutsideJoinedTeam(sItem.teamUuid)) {
        debugPrint(
          '🚫 [合并跳过] 文件夹 UUID: ${sItem.id} 团队 ${sItem.teamUuid} 已不在当前团队列表中',
        );
        continue;
      }
      if (groupsIndexMap.containsKey(sItem.id)) {
        final idx = groupsIndexMap[sItem.id]!;
        final localGroupForGuard = allLocalGroups[idx];
        // 🚀 核心防护：本地已删除的团队文件夹，拒绝服务端未删除版本复活
        if (localGroupForGuard.isDeleted &&
            !sItem.isDeleted &&
            localGroupForGuard.teamUuid != null &&
            localGroupForGuard.teamUuid!.isNotEmpty &&
            sItem.version <= localGroupForGuard.version) {
          debugPrint('🛡️ [防复活] 文件夹 UUID: ${sItem.id} 本地已删除，拒绝复活');
          continue;
        }
        // 🚀 补充防护：已解散团队的已删除文件夹，无条件拒绝未删除版本复活
        if (localGroupForGuard.isDeleted &&
            !sItem.isDeleted &&
            localGroupForGuard.teamUuid != null &&
            localGroupForGuard.teamUuid!.isNotEmpty &&
            currentTeams.isNotEmpty &&
            !currentTeams.contains(localGroupForGuard.teamUuid)) {
          debugPrint('🛡️ [防复活-强拦截] 文件夹 UUID: ${sItem.id} 团队已解散，拒绝未删除版本复活');
          continue;
        }
        if (sItem.isDeleted ||
            sItem.version > allLocalGroups[idx].version ||
            sItem.updatedAt > allLocalGroups[idx].updatedAt) {
          allLocalGroups[idx] = sItem;
          ctx.hasChanges = true;
        }

        // Handle conflict flag divergence separately from content merge.
        if (!sItem.isDeleted) {
          final localGroup = allLocalGroups[idx];
          if (sItem.hasConflict && !localGroup.hasConflict) {
            if (isRecentlyResolved(localGroup.id)) {
              debugPrint(
                '⏭️ [MemoryShield] Skipping conflict resurrection for recently resolved group: ${localGroup.id}',
              );
            } else {
              localGroup.hasConflict = true;
              localGroup.conflictData = sItem.conflictData;
              ctx.hasChanges = true;
            }
          } else if (!sItem.hasConflict && localGroup.hasConflict) {
            localGroup.hasConflict = false;
            localGroup.conflictData = null;
            recentlyResolvedUuids.remove(sItem.id);
            recentlyResolvedTimes.remove(sItem.id);
            ctx.hasChanges = true;
          }
        }
      } else {
        if (!sItem.isDeleted) {
          groupsIndexMap[sItem.id] = allLocalGroups.length;
          allLocalGroups.add(sItem);
          ctx.hasChanges = true;
        }
      }
    }

    // 合并 Countdowns
    List<dynamic> serverCountdowns = syncCountdowns
        ? (response['server_countdowns'] ?? [])
        : const [];
    final Map<String, int> countdownsIndexMap = {
      for (var i = 0; i < allLocalCountdowns.length; i++)
        allLocalCountdowns[i].id: i,
    };
    for (var raw in serverCountdowns) {
      CountdownItem sItem = CountdownItem.fromJson(raw);
      if (ignoredUuids.contains(sItem.id)) {
        debugPrint('🚫 [合并跳过] 倒计时 UUID: ${sItem.id} 已忽略');
        continue;
      }
      if (ctx.isOutsideJoinedTeam(sItem.teamUuid)) {
        debugPrint(
          '🚫 [合并跳过] 倒计时 UUID: ${sItem.id} 团队 ${sItem.teamUuid} 已不在当前团队列表中',
        );
        continue;
      }
      if (countdownsIndexMap.containsKey(sItem.id)) {
        final idx = countdownsIndexMap[sItem.id]!;
        final localCountdownForGuard = allLocalCountdowns[idx];
        // 🚀 核心防护：本地已删除的团队倒计时，拒绝服务端未删除版本复活
        if (localCountdownForGuard.isDeleted &&
            !sItem.isDeleted &&
            localCountdownForGuard.teamUuid != null &&
            localCountdownForGuard.teamUuid!.isNotEmpty &&
            sItem.version <= localCountdownForGuard.version) {
          debugPrint('🛡️ [防复活] 倒计时 UUID: ${sItem.id} 本地已删除，拒绝复活');
          continue;
        }
        // 🚀 补充防护：已解散团队的已删除倒计时，无条件拒绝未删除版本复活
        if (localCountdownForGuard.isDeleted &&
            !sItem.isDeleted &&
            localCountdownForGuard.teamUuid != null &&
            localCountdownForGuard.teamUuid!.isNotEmpty &&
            currentTeams.isNotEmpty &&
            !currentTeams.contains(localCountdownForGuard.teamUuid)) {
          debugPrint('🛡️ [防复活-强拦截] 倒计时 UUID: ${sItem.id} 团队已解散，拒绝未删除版本复活');
          continue;
        }
        if (sItem.isDeleted ||
            sItem.version > allLocalCountdowns[idx].version ||
            (sItem.updatedAt > allLocalCountdowns[idx].updatedAt &&
                !sItem.hasConflict)) {
          allLocalCountdowns[idx] = sItem;
          ctx.hasChanges = true;
        }

        // Handle conflict flag divergence separately from content merge.
        if (!sItem.isDeleted) {
          final localCountdown = allLocalCountdowns[idx];
          if (sItem.hasConflict && !localCountdown.hasConflict) {
            if (isRecentlyResolved(localCountdown.id)) {
              debugPrint(
                '⏭️ [MemoryShield] Skipping conflict resurrection for recently resolved countdown: ${localCountdown.id}',
              );
            } else {
              localCountdown.hasConflict = true;
              localCountdown.conflictData = sItem.conflictData;
              ctx.hasChanges = true;
            }
          } else if (!sItem.hasConflict && localCountdown.hasConflict) {
            localCountdown.hasConflict = false;
            localCountdown.conflictData = null;
            recentlyResolvedUuids.remove(sItem.id);
            recentlyResolvedTimes.remove(sItem.id);
            ctx.hasChanges = true;
          }
        }
      } else {
        if (!sItem.isDeleted) {
          countdownsIndexMap[sItem.id] = allLocalCountdowns.length;
          allLocalCountdowns.add(sItem);
          ctx.hasChanges = true;
        }
      }
    }

    // 合并 TimeLogs
    List<dynamic> serverTimeLogs = syncTimeLogs
        ? (response['server_time_logs'] ?? [])
        : const [];
    final Map<String, int> timeLogsIndexMap = {
      for (var i = 0; i < allLocalTimeLogs.length; i++)
        allLocalTimeLogs[i].id: i,
    };
    for (var raw in serverTimeLogs) {
      TimeLogItem sItem = TimeLogItem.fromJson(raw);
      if (ctx.isOutsideJoinedTeam(sItem.teamUuid)) {
        debugPrint(
          '🚫 [合并跳过] 时间日志 UUID: ${sItem.id} 团队 ${sItem.teamUuid} 已不在当前团队列表中',
        );
        continue;
      }
      if (timeLogsIndexMap.containsKey(sItem.id)) {
        final idx = timeLogsIndexMap[sItem.id]!;
        if (sItem.isDeleted ||
            sItem.version > allLocalTimeLogs[idx].version ||
            sItem.updatedAt > allLocalTimeLogs[idx].updatedAt) {
          allLocalTimeLogs[idx] = sItem;
          ctx.hasChanges = true;
        }
      } else {
        if (!sItem.isDeleted) {
          timeLogsIndexMap[sItem.id] = allLocalTimeLogs.length;
          allLocalTimeLogs.add(sItem);
          ctx.hasChanges = true;
        }
      }
    }

    // 合并 TodoPlanBlocks
    if (syncPlanBlocks) {
      List<dynamic> serverPlanBlocks = response['server_plan_blocks'] ?? [];
      final Map<String, int> planBlocksIndexMap = {
        for (var i = 0; i < allLocalPlanBlocks.length; i++)
          allLocalPlanBlocks[i].id: i,
      };
      for (var raw in serverPlanBlocks) {
        TodoPlanBlock sItem = TodoPlanBlock.fromJson(
          (raw as Map).cast<String, dynamic>(),
        );
        if (ignoredUuids.contains(sItem.id)) {
          debugPrint('🚫 [合并跳过] 规划块 UUID: ${sItem.id} 已忽略');
          continue;
        }
        if (planBlocksIndexMap.containsKey(sItem.id)) {
          final idx = planBlocksIndexMap[sItem.id]!;
          final local = allLocalPlanBlocks[idx];
          if (sItem.isDeleted ||
              sItem.version > local.version ||
              sItem.updatedAt > local.updatedAt) {
            allLocalPlanBlocks[idx] = sItem;
            ctx.hasChanges = true;
          }
        } else if (!sItem.isDeleted) {
          planBlocksIndexMap[sItem.id] = allLocalPlanBlocks.length;
          allLocalPlanBlocks.add(sItem);
          ctx.hasChanges = true;
        }
      }
    }

    // 合并通用固定日程。只在服务端显式声明 v1 能力时读取，
    // 避免旧服务端的空字段被误解为“云端已全部删除”。
    if (syncFixedSchedules && fixedSchedulesSupported) {
      final serverFixedSchedules =
          (response['server_fixed_schedules'] as List?) ?? const [];
      final fixedSchedulesIndexMap = <String, int>{
        for (var i = 0; i < allLocalFixedSchedules.length; i++)
          allLocalFixedSchedules[i].id: i,
      };
      for (final raw in serverFixedSchedules) {
        if (raw is! Map) continue;
        final serverItem = FixedScheduleItem.fromJson(
          Map<String, dynamic>.from(raw),
        );
        if (ignoredUuids.contains(serverItem.id) ||
            ctx.isOutsideJoinedTeam(serverItem.teamUuid)) {
          continue;
        }
        final localIndex = fixedSchedulesIndexMap[serverItem.id];
        if (localIndex == null) {
          if (!serverItem.isDeleted) {
            fixedSchedulesIndexMap[serverItem.id] =
                allLocalFixedSchedules.length;
            allLocalFixedSchedules.add(serverItem);
            ctx.hasChanges = true;
          }
          continue;
        }
        final localItem = allLocalFixedSchedules[localIndex];
        if (TodoLwwService.isIncomingWinner(
          incomingUpdatedAt: serverItem.updatedAt,
          incomingVersion: serverItem.version,
          currentUpdatedAt: localItem.updatedAt,
          currentVersion: localItem.version,
        )) {
          allLocalFixedSchedules[localIndex] = serverItem;
          ctx.hasChanges = true;
        }
      }
    }

    // 合并习惯数据。只在服务端显式声明 habits v1 能力时读取，
    // 避免旧服务端的空字段被误解为“云端已全部删除”。
    if (syncHabits && habitsSupported) {
      final serverHabitGoals =
          (response['server_habit_goals'] as List?) ?? const [];
      final habitGoalsIndexMap = <String, int>{
        for (var i = 0; i < allLocalHabitGoals.length; i++)
          allLocalHabitGoals[i].uuid: i,
      };
      for (final raw in serverHabitGoals) {
        if (raw is! Map) continue;
        final serverItem = HabitGoal.fromJson(Map<String, dynamic>.from(raw));
        if (ignoredUuids.contains(serverItem.uuid)) continue;
        final localIndex = habitGoalsIndexMap[serverItem.uuid];
        if (localIndex == null) {
          if (!serverItem.isDeleted) {
            habitGoalsIndexMap[serverItem.uuid] = allLocalHabitGoals.length;
            allLocalHabitGoals.add(serverItem);
            ctx.hasChanges = true;
          }
          continue;
        }
        final localItem = allLocalHabitGoals[localIndex];
        if (serverItem.hasConflict) {
          staleHabitConflictSnapshots['habit_goals:${serverItem.uuid}'] =
              serverItem.toJson();
        }
        // 冲突标记会推高服务端 updated_at；时间路径必须排除冲突项，
        // 避免用冲突快照覆盖本地更新的内容（与倒计时合并规则一致）。
        final serverWins =
            serverItem.version > localItem.version ||
            (serverItem.updatedAt > localItem.updatedAt &&
                !serverItem.hasConflict);
        if (serverWins) {
          allLocalHabitGoals[localIndex] = serverItem;
          ctx.hasChanges = true;
        } else if (serverItem.hasConflict && !localItem.hasConflict) {
          // 服务端冲突标记与本地内容分开同步：不覆盖本地新内容，
          // 只让冲突状态保持一致，冲突收件箱可见。
          localItem.hasConflict = true;
          localItem.conflictData = serverItem.conflictData;
          ctx.hasChanges = true;
        } else if (!serverItem.hasConflict && localItem.hasConflict) {
          localItem.hasConflict = false;
          localItem.conflictData = null;
          ctx.hasChanges = true;
        }
      }

      final serverHabitRules =
          (response['server_habit_goal_rules'] as List?) ?? const [];
      final habitRulesIndexMap = <String, int>{
        for (var i = 0; i < allLocalHabitRules.length; i++)
          allLocalHabitRules[i].uuid: i,
      };
      for (final raw in serverHabitRules) {
        if (raw is! Map) continue;
        final serverItem = HabitGoalRuleRevision.fromJson(
          Map<String, dynamic>.from(raw),
        );
        if (ignoredUuids.contains(serverItem.uuid)) continue;
        final localIndex = habitRulesIndexMap[serverItem.uuid];
        if (localIndex == null) {
          if (!serverItem.isDeleted) {
            habitRulesIndexMap[serverItem.uuid] = allLocalHabitRules.length;
            allLocalHabitRules.add(serverItem);
            ctx.hasChanges = true;
          }
          continue;
        }
        final localItem = allLocalHabitRules[localIndex];
        if (serverItem.hasConflict) {
          staleHabitConflictSnapshots['habit_goal_rule_revisions:${serverItem.uuid}'] =
              serverItem.toJson();
        }
        // 与目标一致：冲突标记会推高服务端 updated_at，
        // 时间路径必须排除冲突项，避免冲突快照覆盖本地新内容。
        final serverWins =
            serverItem.version > localItem.version ||
            (serverItem.updatedAt > localItem.updatedAt &&
                !serverItem.hasConflict);
        if (serverWins) {
          allLocalHabitRules[localIndex] = serverItem;
          ctx.hasChanges = true;
        } else if (serverItem.hasConflict && !localItem.hasConflict) {
          localItem.hasConflict = true;
          localItem.conflictData = serverItem.conflictData;
          ctx.hasChanges = true;
        } else if (!serverItem.hasConflict && localItem.hasConflict) {
          localItem.hasConflict = false;
          localItem.conflictData = null;
          ctx.hasChanges = true;
        }
      }

      // 打卡采用事件合并：不同 UUID 全部保留，同一 UUID 按 LWW 更新。
      final serverHabitCheckIns =
          (response['server_habit_checkins'] as List?) ?? const [];
      final habitCheckInsIndexMap = <String, int>{
        for (var i = 0; i < allLocalHabitCheckIns.length; i++)
          allLocalHabitCheckIns[i].uuid: i,
      };
      for (final raw in serverHabitCheckIns) {
        if (raw is! Map) continue;
        final serverItem = HabitCheckIn.fromJson(
          Map<String, dynamic>.from(raw),
        );
        if (ignoredUuids.contains(serverItem.uuid)) continue;
        final localIndex = habitCheckInsIndexMap[serverItem.uuid];
        if (localIndex == null) {
          if (!serverItem.isDeleted) {
            habitCheckInsIndexMap[serverItem.uuid] =
                allLocalHabitCheckIns.length;
            allLocalHabitCheckIns.add(serverItem);
            ctx.hasChanges = true;
          }
          continue;
        }
        final localItem = allLocalHabitCheckIns[localIndex];
        if (TodoLwwService.isIncomingWinner(
          incomingUpdatedAt: serverItem.updatedAt,
          incomingVersion: serverItem.version,
          currentUpdatedAt: localItem.updatedAt,
          currentVersion: localItem.version,
        )) {
          allLocalHabitCheckIns[localIndex] = serverItem;
          ctx.hasChanges = true;
        }
      }

      // 睡眠训练计划是账号级配置，同一 UUID 按 LWW 合并；阶段本身不在
      // 这里持久化，而由同步后的打卡记录计算。
      final serverHabitSleepCoachingPlans =
          (response['server_habit_sleep_coaching_plans'] as List?) ?? const [];
      final sleepCoachingPlanIndexMap = <String, int>{
        for (var i = 0; i < allLocalHabitSleepCoachingPlans.length; i++)
          allLocalHabitSleepCoachingPlans[i].uuid: i,
      };
      for (final raw in serverHabitSleepCoachingPlans) {
        if (raw is! Map) continue;
        final serverItem = HabitSleepCoachingPlan.fromJson(
          Map<String, dynamic>.from(raw),
        );
        if (ignoredUuids.contains(serverItem.uuid)) continue;
        final localIndex = sleepCoachingPlanIndexMap[serverItem.uuid];
        if (localIndex == null) {
          if (!serverItem.isDeleted) {
            sleepCoachingPlanIndexMap[serverItem.uuid] =
                allLocalHabitSleepCoachingPlans.length;
            allLocalHabitSleepCoachingPlans.add(serverItem);
            ctx.hasChanges = true;
          }
          continue;
        }
        final localItem = allLocalHabitSleepCoachingPlans[localIndex];
        if (TodoLwwService.isIncomingWinner(
          incomingUpdatedAt: serverItem.updatedAt,
          incomingVersion: serverItem.version,
          currentUpdatedAt: localItem.updatedAt,
          currentVersion: localItem.version,
        )) {
          allLocalHabitSleepCoachingPlans[localIndex] = serverItem;
          ctx.hasChanges = true;
        }
      }

      final serverHabitDrinkOptions =
          (response['server_habit_drink_options'] as List?) ?? const [];
      final drinkOptionIndexMap = <String, int>{
        for (var i = 0; i < allLocalHabitDrinkOptions.length; i++)
          allLocalHabitDrinkOptions[i].uuid: i,
      };
      for (final raw in serverHabitDrinkOptions) {
        if (raw is! Map) continue;
        final serverItem = HabitDrinkOption.fromJson(
          Map<String, dynamic>.from(raw),
        );
        if (ignoredUuids.contains(serverItem.uuid)) continue;
        final localIndex = drinkOptionIndexMap[serverItem.uuid];
        if (localIndex == null) {
          drinkOptionIndexMap[serverItem.uuid] =
              allLocalHabitDrinkOptions.length;
          allLocalHabitDrinkOptions.add(serverItem);
          ctx.hasChanges = true;
          continue;
        }
        final localItem = allLocalHabitDrinkOptions[localIndex];
        if (TodoLwwService.isIncomingWinner(
          incomingUpdatedAt: serverItem.updatedAt,
          incomingVersion: serverItem.version,
          currentUpdatedAt: localItem.updatedAt,
          currentVersion: localItem.version,
        )) {
          allLocalHabitDrinkOptions[localIndex] = serverItem;
          ctx.hasChanges = true;
        }
      }
    }

    // 即使服务端暂未声明 habits 能力，也要处理本地遗留的假冲突：这些快照
    // 可能来自旧版本，不能因为本轮没有返回习惯列表就永久留在冲突中心。
    if (syncHabits) {
      final autoResolved = await _autoResolveEquivalentHabitConflicts(
        goals: allLocalHabitGoals,
        rules: allLocalHabitRules,
        snapshots: staleHabitConflictSnapshots,
      );
      if (autoResolved.isNotEmpty) {
        autoResolvedHabitConflictIds.addAll(autoResolved);
        ctx.hasChanges = true;
        debugPrint('🧹 [同步修复] 已自动清理 ${autoResolved.length} 条业务内容一致的习惯冲突标记');
      }
    }

    // 🚀 关键：将 conflicts 数组中的冲突也标记到本地数据上。
    // 服务器在标记 has_conflict=1 时可能不会同时更新 updated_at，
    // 导致该条目被 filterWithActualTime 过滤掉，不在 server_todos 中。
    // 这里从 conflicts 数组直接补标，确保 ConflictInboxScreen 能看到。
    final ignoredScheduleConflictKeys = await _getIgnoredScheduleConflictKeys(
      username,
    );
    if (conflicts.isNotEmpty) {
      final conflictDetectionEnabled = await getConflictDetectionEnabled();
      for (final c in conflicts) {
        final itemId = (c.item['uuid'] ?? c.item['id'] ?? '').toString();
        if (itemId.isEmpty) continue;
        if (isRecentlyResolved(itemId)) {
          debugPrint(
            '⏭️ [MemoryShield] Skipping re-flag of recently resolved item in conflicts: $itemId',
          );
          continue;
        }
        final serverVersion = c.conflictWith;
        if (c.type == 'schedule_conflict' &&
            todosIndexMap.containsKey(itemId)) {
          if (!conflictDetectionEnabled) continue;
          final todo = allLocalTodos[todosIndexMap[itemId]!];
          if (ConflictVisibilityService.isAllDayTodo(todo)) {
            if (ConflictVisibilityService.clearImpossibleTodoScheduleConflict(
              todo,
            )) {
              ctx.hasChanges = true;
            }
            continue;
          }
          final peer = Map<String, dynamic>.from(serverVersion);
          if (_isSameRecurrenceSeriesPayload(todo, peer)) continue;
          final conflictKey = _scheduleConflictKeyFromPayload(todo, peer);
          if (conflictKey != null &&
              ignoredScheduleConflictKeys.contains(conflictKey)) {
            continue;
          }
          final data = ConflictVisibilityService.scheduleConflictData(
            todo: todo,
            peers: [peer],
            source: 'server_detector',
          );
          if (!todo.hasConflict ||
              jsonEncode(todo.serverVersionData) != jsonEncode(data)) {
            todo.hasConflict = true;
            todo.serverVersionData = data;
            ctx.hasChanges = true;
          }
          continue;
        }

        final serverVersionId =
            (serverVersion['uuid'] ?? serverVersion['id'] ?? '').toString();
        final bool isSameItemServerVersion =
            serverVersionId.isNotEmpty && serverVersionId == itemId.toString();
        if (!isSameItemServerVersion) {
          debugPrint('⚠️ 跳过无可用云端快照的冲突标记: ${c.type} $itemId');
          continue;
        }

        if (todosIndexMap.containsKey(itemId)) {
          final todo = allLocalTodos[todosIndexMap[itemId]!];
          final serverConflictVer =
              (serverVersion['version'] as num?)?.toInt() ?? 0;
          // Skip if already resolved (hasConflict cleared) or version bumped above server
          if (!todo.hasConflict || todo.version > serverConflictVer) {
            debugPrint(
              '⏭️ Skipping re-flag of resolved todo $itemId '
              '(hasConflict=${todo.hasConflict}, localV=${todo.version}, serverV=$serverConflictVer)',
            );
          } else {
            todo.hasConflict = true;
            todo.serverVersionData = serverVersion;
            ctx.hasChanges = true;
          }
        }
        if (countdownsIndexMap.containsKey(itemId)) {
          final countdown = allLocalCountdowns[countdownsIndexMap[itemId]!];
          final serverConflictVer =
              (serverVersion['version'] as num?)?.toInt() ?? 0;
          if (!countdown.hasConflict || countdown.version > serverConflictVer) {
            // skip — already resolved
          } else {
            countdown.hasConflict = true;
            countdown.conflictData = serverVersion;
            ctx.hasChanges = true;
          }
        }
        if (groupsIndexMap.containsKey(itemId)) {
          final group = allLocalGroups[groupsIndexMap[itemId]!];
          final serverConflictVer =
              (serverVersion['version'] as num?)?.toInt() ?? 0;
          if (!group.hasConflict || group.version > serverConflictVer) {
            // skip — already resolved
          } else {
            group.hasConflict = true;
            group.conflictData = serverVersion;
            ctx.hasChanges = true;
          }
        }
        // TimeLogs don't have hasConflict field, skip
      }
    }

    // 合并 Pomodoro (Tags & Records)
    bool pomodoroChanged = false;
    if (syncPomodoro) {
      try {
        // 顺序：拉取标签 -> 上传标签 -> 上传记录 -> 拉取记录
        await PomodoroService.syncTagsFromCloud();
        await PomodoroService.syncTagsToCloud();
        await PomodoroService.syncRecordsToCloud(forceFullSync: forceFullSync);
        pomodoroChanged = await PomodoroService.syncRecordsFromCloud(
          forceFullSync: forceFullSync,
        );
        if (pomodoroChanged) ctx.hasChanges = true;
      } catch (pe) {
        debugPrint("Pomodoro sync error: $pe");
      }
    }

    ctx.remoteTodoEntries = remoteTodoEntries;
    ctx.beforeRemoteRepair = beforeRemoteRepair;
    ctx.remoteRecurrenceBaselines = remoteRecurrenceBaselines;
    ctx.rejectedMaintenanceIds = rejectedMaintenanceIds;
    ctx.repairedRemoteTodoIds = repairedRemoteTodoIds;
    ctx.preMergeConflictIds = preMergeConflictIds;
    ctx.todosIndexMap = todosIndexMap;
    ctx.ignoredScheduleConflictKeys = ignoredScheduleConflictKeys;
    ctx.pomodoroChanged = pomodoroChanged;
  }

  @override
  Future<Set<String>> _autoResolveEquivalentHabitConflicts({
    required List<HabitGoal> goals,
    required List<HabitGoalRuleRevision> rules,
    required Map<String, Map<String, dynamic>> snapshots,
  }) async {
    final goalsById = {for (final goal in goals) goal.uuid: goal};
    final rulesById = {for (final rule in rules) rule.uuid: rule};
    final candidates = <String, ({String table, String uuid})>{};

    for (final entry in snapshots.entries) {
      final separator = entry.key.indexOf(':');
      if (separator <= 0) continue;
      final table = entry.key.substring(0, separator);
      final uuid = entry.key.substring(separator + 1);
      final localJson = table == 'habit_goals'
          ? goalsById[uuid]?.toJson()
          : table == 'habit_goal_rule_revisions'
          ? rulesById[uuid]?.toJson()
          : null;
      if (localJson == null ||
          !HabitSyncConflictService.hasSameBusinessContent(
            localJson,
            entry.value,
          )) {
        continue;
      }
      candidates[entry.key] = (table: table, uuid: uuid);
    }

    if (candidates.isEmpty) return <String>{};

    final results = await Future.wait(
      candidates.values.map((candidate) async {
        final localJson = candidate.table == 'habit_goals'
            ? goalsById[candidate.uuid]?.toJson()
            : rulesById[candidate.uuid]?.toJson();
        if (localJson == null) {
          return (
            candidate: candidate,
            resolved: false,
            resolvedData: null as Map<String, dynamic>?,
          );
        }

        try {
          final result = await ApiService.resolveConflict(
            uuid: candidate.uuid,
            table: candidate.table,
            resolution: 'accept_server',
          );
          if (result['success'] == true) {
            return (
              candidate: candidate,
              resolved: true,
              resolvedData: null as Map<String, dynamic>?,
            );
          }
          debugPrint(
            '⚠️ [同步修复] 服务端清理习惯冲突失败 ${candidate.uuid}: ${result['error'] ?? '未知错误'}',
          );
        } catch (error) {
          debugPrint('⚠️ [同步修复] 服务端清理习惯冲突异常 ${candidate.uuid}: $error');
        }

        // 兼容旧服务端或解除接口暂时不可用的情况：本地先清理并排队一条
        // 高版本的干净数据，下一次普通同步仍可完成服务端收敛。
        try {
          final snapshot = snapshots['${candidate.table}:${candidate.uuid}'];
          final serverVersion =
              int.tryParse(snapshot?['version']?.toString() ?? '') ?? 0;
          final currentVersion =
              int.tryParse(localJson['version']?.toString() ?? '') ?? 1;
          final resolvedData = Map<String, dynamic>.from(localJson)
            ..['version'] =
                (serverVersion > currentVersion
                    ? serverVersion
                    : currentVersion) +
                1
            ..['updated_at'] = DateTime.now().millisecondsSinceEpoch
            ..['has_conflict'] = 0
            ..remove('conflict_data')
            ..remove('serverVersionData');
          await StorageService.resolveConflictLocally(
            uuid: candidate.uuid,
            table: candidate.table,
            resolvedData: resolvedData,
            createOplog: true,
            touchUpdatedAt: false,
          );
          final fallback = await ApiService.resolveConflict(
            uuid: candidate.uuid,
            table: candidate.table,
            resolution: 'keep_local',
            bumpedVersion: resolvedData['version'] as int,
            data: resolvedData,
          );
          if (fallback['success'] != true) {
            debugPrint(
              'ℹ️ [同步修复] 已清除本地习惯冲突并排队重试 ${candidate.uuid}: ${fallback['error'] ?? '等待下次同步'}',
            );
          }
          return (
            candidate: candidate,
            resolved: true,
            resolvedData: resolvedData,
          );
        } catch (error) {
          debugPrint('⚠️ [同步修复] 本地排队清理习惯冲突失败 ${candidate.uuid}: $error');
          return (
            candidate: candidate,
            resolved: false,
            resolvedData: null as Map<String, dynamic>?,
          );
        }
      }),
    );

    final resolvedIds = <String>{};
    _SyncListIndex<HabitGoal>? goalIndex;
    _SyncListIndex<HabitGoalRuleRevision>? ruleIndex;
    for (final result in results) {
      if (!result.resolved) continue;
      if (result.resolvedData != null) {
        if (result.candidate.table == 'habit_goals') {
          final index = (goalIndex ??= _SyncListIndex(
            goals,
            (goal) => goal.uuid,
          )).indexOf(result.candidate.uuid);
          if (index != null) {
            goals[index] = HabitGoal.fromJson(result.resolvedData!);
          }
        } else {
          final index = (ruleIndex ??= _SyncListIndex(
            rules,
            (rule) => rule.uuid,
          )).indexOf(result.candidate.uuid);
          if (index != null) {
            rules[index] = HabitGoalRuleRevision.fromJson(result.resolvedData!);
          }
        }
      } else {
        if (result.candidate.table == 'habit_goals') {
          final goal = goalsById[result.candidate.uuid];
          goal?.hasConflict = false;
          goal?.conflictData = null;
        } else {
          final rule = rulesById[result.candidate.uuid];
          rule?.hasConflict = false;
          rule?.conflictData = null;
        }
      }
      resolvedIds.add(result.candidate.uuid);
    }
    return resolvedIds;
  }
}
