part of 'storage_service.dart';
// ignore_for_file: annotate_overrides, unused_element, unused_element_parameter

mixin _StorageSync on _StorageServiceBase {
  Future<void> saveTimeLogs(String username, List<TimeLogItem> items,
          {bool sync = true}) =>
      PomodoroStorage.saveTimeLogs(
        username,
        items,
        sync: sync,
        requestSync: requestSync,
      );
  Future<List<TimeLogItem>> getTimeLogs(String username, {int? limit}) =>
      PomodoroStorage.getTimeLogs(
        username,
        limit: limit,
        saveMigratedTimeLogs: saveTimeLogs,
      );
  Future<bool> deleteTimeLogGlobally(String username, String idToDelete) async {
    List<TimeLogItem> localLogs = await getTimeLogs(username);
    int index = localLogs.indexWhere((t) => t.id == idToDelete);

    if (index == -1) return false;

    localLogs[index].isDeleted = true;
    localLogs[index].markAsChanged();

    await saveTimeLogs(username, localLogs, sync: true);
    return true;
  }

  Future<void> saveLocalScreenTime(Map<dynamic, dynamic> stats) async {
    final prefs = await StorageService.prefs;
    final String? username = prefs.getString(keyCurrentUser);
    final key = _scopedKey(keyLocalScreenTime, username);
    await prefs.setString(key, jsonEncode(stats));
  }

  Future<Map<String, dynamic>?> getLocalScreenTimePackage() async {
    final prefs = await StorageService.prefs;
    final String? username = prefs.getString(keyCurrentUser);
    final key = _scopedKey(keyLocalScreenTime, username);
    String? s = prefs.getString(key);
    // 仅在未登录的旧版流程中读取全局 key。登录后禁止回退到可能属于
    // 其他账号的缓存，避免账号切换时串出屏幕时间数据。
    if (s == null && (username == null || username.isEmpty)) {
      s = prefs.getString(keyLocalScreenTime);
    }
    return s != null ? jsonDecode(s) as Map<String, dynamic> : null;
  }

  Future<Map<String, dynamic>> getLocalScreenTimeMap() async {
    return await getLocalScreenTimePackage() ?? {};
  }

  Future<List<dynamic>> getLocalScreenTime() async {
    final map = await getLocalScreenTimeMap();
    return map['apps'] as List<dynamic>? ?? [];
  }

  Future<void> saveScreenTimeCache(List<dynamic> stats) async {
    if (stats.isEmpty) return;

    final prefs = await StorageService.prefs;
    final String? username = prefs.getString(keyCurrentUser);
    final historyKey = _scopedKey(keyScreenTimeHistory, username);
    final cacheKey = _scopedKey(keyScreenTimeCache, username);
    final syncKey = _scopedKey(keyLastScreenTimeSync, username);
    final now = DateTime.now();
    final String today = DateFormat('yyyy-MM-dd').format(now);

    // 1. 获取已有的历史记录
    String? histStr = prefs.getString(historyKey);
    if (histStr == null && (username == null || username.isEmpty)) {
      histStr = prefs.getString(keyScreenTimeHistory);
    }
    Map<String, dynamic> history = {};
    if (histStr != null) {
      try {
        history = jsonDecode(histStr);
      } catch (e) {
        debugPrint("解析历史记录失败: $e");
      }
    }

    // 2. 更新历史记录
    // 即使 stats 里混入了旧数据，我们也只将其视为“今日最新快照”存储在 today 键下
    // 如果你想更严格，可以在此处对 stats 进行过滤，确保 e['date'] == today
    history[today] = stats;

    // 3. 维护 14 天滑动窗口 (删除最旧的记录)
    if (history.length > 14) {
      var sortedKeys = history.keys.toList()..sort();
      while (history.length > 14) {
        history.remove(sortedKeys.removeAt(0));
      }
    }

    // 4. 原子化写入本地存储
    // 🚀 核心优化：逐步弃用 Prefs 存储历史记录，迁移至 SQL
    try {
      await saveScreenTimeHistoryToSql(today, stats);
      // 如果写入 SQL 成功，可以尝试清理一下 Prefs 里的旧数据（如果它太大了）
      if (histStr != null && histStr.length > 1024 * 500) {
        // > 500KB
        await prefs.remove(historyKey);
        debugPrint("🗑️ 已清理过大的 ScreenTime Prefs 历史记录");
      }
    } catch (e) {
      await prefs.setString(historyKey, jsonEncode(history));
    }

    // 5. 更新“当前视图快照” (keyScreenTimeCache)
    // 🚀 核心修复：只有当最新更新日期确实是今天时，才更新首页显示的 Cache
    // 这样如果凌晨同步了旧数据，首页不会被错误覆盖
    await prefs.setString(cacheKey, jsonEncode(stats));

    // 更新最后同步成功的时间戳（记录到毫秒）
    await prefs.setInt(syncKey, now.millisecondsSinceEpoch);
    screenTimeRefreshNotifier.value++;
  }

  Future<void> saveScreenTimeHistoryToSql(
      String date, List<dynamic> stats) async {
    final dbHelper = DatabaseHelper.instance;
    final db = await dbHelper.database;
    final batch = db.batch();

    // 覆盖写：先删除该日期的旧记录
    batch.delete('screen_time', where: 'record_date = ?', whereArgs: [date]);

    for (var stat in stats) {
      batch.insert('screen_time', {
        'record_date': date,
        'package_name': stat['package_name']?.toString() ?? '',
        'app_name': stat['app_name']?.toString() ?? '',
        'device_name': stat['device_name']?.toString() ?? '',
        'category': stat['category']?.toString() ?? '未分类',
        'duration':
            (stat['duration'] is num) ? (stat['duration'] as num).toInt() : 0,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      });
    }
    await batch.commit(noResult: true);
  }

  Future<List<dynamic>> getScreenTimeCache() async {
    final prefs = await StorageService.prefs;
    final String? username = prefs.getString(keyCurrentUser);
    final cacheKey = _scopedKey(keyScreenTimeCache, username);
    final syncKey = _scopedKey(keyLastScreenTimeSync, username);

    // 检查缓存是否是今天的
    int? lastSyncMs = prefs.getInt(syncKey);
    if (lastSyncMs == null && (username == null || username.isEmpty)) {
      lastSyncMs = prefs.getInt(keyLastScreenTimeSync);
    }
    if (lastSyncMs != null) {
      DateTime lastSyncDate =
          DateTime.fromMillisecondsSinceEpoch(lastSyncMs).toLocal();
      DateTime now = DateTime.now();

      // 如果缓存日期不是今天，说明缓存已过期，返回空列表触发新的同步
      if (lastSyncDate.year != now.year ||
          lastSyncDate.month != now.month ||
          lastSyncDate.day != now.day) {
        debugPrint("缓存已过期 (日期不匹配)，清理过期数据");
        await prefs.remove(cacheKey);
        return [];
      }
    }

    String? jsonStr = prefs.getString(cacheKey);
    if (jsonStr == null && (username == null || username.isEmpty)) {
      jsonStr = prefs.getString(keyScreenTimeCache);
    }
    if (jsonStr != null) {
      try {
        return jsonDecode(jsonStr);
      } catch (_) {
        return [];
      }
    }
    return [];
  }

  Future<Map<String, List<dynamic>>> getScreenTimeHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final String? username = prefs.getString(keyCurrentUser);
    final String historyKey = _scopedKey(keyScreenTimeHistory, username);
    final dbHelper = DatabaseHelper.instance;

    try {
      // 1. 迁移检查 (一次性从 Prefs 搬运到 SQL)
      final String migrationKey = "migrated_screentime_$username";
      if (!(prefs.getBool(migrationKey) ?? false)) {
        String? jsonStr = prefs.getString(historyKey);
        if (jsonStr == null && (username == null || username.isEmpty)) {
          jsonStr = prefs.getString(keyScreenTimeHistory);
        }
        if (jsonStr != null && jsonStr.isNotEmpty) {
          debugPrint("🚀 发现 ScreenTime 历史记录，正在执行 SQL 迁移...");
          try {
            Map<String, dynamic> history = jsonDecode(jsonStr);
            for (var entry in history.entries) {
              if (entry.value is List) {
                await saveScreenTimeHistoryToSql(
                    entry.key, entry.value as List);
              }
            }
            await prefs.remove(historyKey);
            await prefs.remove(keyScreenTimeHistory);
            debugPrint("✅ ScreenTime 迁移完成并已清理 Prefs");
          } catch (e) {
            debugPrint("⚠️ ScreenTime 迁移解析失败: $e");
          }
        }
        await prefs.setBool(migrationKey, true);
      }

      final db = await dbHelper.database;
      // 2. 从 SQL 读取所有记录并按日期分组
      final List<Map<String, dynamic>> maps = await db.query(
        'screen_time',
        orderBy: 'record_date DESC',
      );

      Map<String, List<dynamic>> result = {};
      for (var m in maps) {
        String date = m['record_date']?.toString() ?? '';
        if (date.isEmpty) continue;
        result.putIfAbsent(date, () => []);
        result[date]!.add({
          'package_name': m['package_name'],
          'app_name': m['app_name'],
          'device_name': m['device_name'],
          'category': m['category'],
          'duration': m['duration'],
        });
      }
      final int userId = prefs.getInt('current_user_id') ?? 0;
      if (userId > 0) {
        final datesNeedingDeviceNames = result.entries
            .where((entry) => entry.value.any((item) {
                  final deviceName = item['device_name']?.toString() ?? '';
                  return deviceName.isEmpty;
                }))
            .map((entry) => entry.key)
            .toList();

        for (final date in datesNeedingDeviceNames) {
          try {
            final cloudStats = await ApiService.fetchScreenTime(userId, date);
            if (cloudStats.isNotEmpty) {
              await saveScreenTimeHistoryToSql(date, cloudStats);
              result[date] = cloudStats;
            }
          } catch (e) {
            debugPrint("⚠️ ScreenTime History 云端补齐失败($date): $e");
          }
        }
      }
      return result;
    } catch (e) {
      debugPrint("⚠️ ScreenTime History SQL 异常: $e");
      String? jsonStr = prefs.getString(historyKey);
      if (jsonStr == null && (username == null || username.isEmpty)) {
        jsonStr = prefs.getString(keyScreenTimeHistory);
      }
      if (jsonStr != null && jsonStr.isNotEmpty) {
        try {
          Map<String, dynamic> raw = jsonDecode(jsonStr);
          return raw
              .map((key, value) => MapEntry(key, List<dynamic>.from(value)));
        } catch (_) {}
      }
    }
    return {};
  }

  Future<void> updateLastScreenTimeSync() async {
    final prefs = await SharedPreferences.getInstance();
    final String? username = prefs.getString(keyCurrentUser);
    await prefs.setInt(_scopedKey(keyLastScreenTimeSync, username),
        DateTime.now().millisecondsSinceEpoch);
  }

  Future<DateTime?> getLastScreenTimeSync() async {
    final prefs = await SharedPreferences.getInstance();
    final String? username = prefs.getString(keyCurrentUser);
    int? timestamp = prefs.getInt(_scopedKey(keyLastScreenTimeSync, username));
    if (timestamp == null && (username == null || username.isEmpty)) {
      timestamp = prefs.getInt(keyLastScreenTimeSync);
    }
    if (timestamp != null) {
      return DateTime.fromMillisecondsSinceEpoch(timestamp, isUtc: true)
          .toLocal();
    }
    return null;
  }

  Future<void> syncAppMappings() async {
    final prefs = await SharedPreferences.getInstance();
    int? lastSync = prefs.getInt(keyLastMappingsSync);
    DateTime now = DateTime.now();
    if (lastSync != null) {
      DateTime lastDate =
          DateTime.fromMillisecondsSinceEpoch(lastSync, isUtc: true).toLocal();
      if (now.difference(lastDate).inDays < 7) return;
    }
    List<dynamic> mappings = await ApiService.fetchAppMappings();
    if (mappings.isNotEmpty) {
      Map<String, String> lookupMap = {};
      for (var item in mappings) {
        String pkg = item['package_name'] ?? '';
        String mapped = item['mapped_name'] ?? '';
        String cat = item['category'] ?? '未分类';
        if (pkg.isNotEmpty) lookupMap[pkg] = cat;
        if (mapped.isNotEmpty) lookupMap[mapped] = cat;
      }
      await prefs.setString(keyAppMappings, jsonEncode(lookupMap));
      await prefs.setInt(keyLastMappingsSync, now.millisecondsSinceEpoch);
    }
  }

  Future<Map<String, String>> getAppMappings() async {
    final prefs = await SharedPreferences.getInstance();
    String? jsonStr = prefs.getString(keyAppMappings);
    if (jsonStr != null) {
      try {
        return Map<String, String>.from(jsonDecode(jsonStr));
      } catch (_) {}
    }
    return {};
  }

  Future<void> resetSyncTime(String username) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('last_sync_time_${ApiService.syncServerKey}_$username');
    await prefs.remove('last_sync_time_aliyun_$username');
    await prefs.remove('last_sync_time_aliyun_test_$username');
    await prefs.remove('last_sync_time_cf_$username');
    await prefs.remove('last_sync_time_$username'); // 兼容旧版本
  }

  Future<Map<String, dynamic>> syncData(
    String username, {
    bool syncTodos = true,
    bool syncCountdowns = true,
    bool forceFullSync = false,
    bool uploadAllLocal = false,
    BuildContext? context,
    bool syncScreenTime = true,
    bool syncTimeLogs = true,
    bool syncPomodoro = true,
    bool syncPlanBlocks = true,
    bool syncFixedSchedules = true,
    bool syncHabits = true,
  }) async {
    final bool shouldUploadAllLocal = uploadAllLocal || forceFullSync;
    // 1. 状态锁：防止重复进入
    if (!syncTodos &&
        !syncCountdowns &&
        !syncTimeLogs &&
        !syncPomodoro &&
        !syncPlanBlocks &&
        !syncFixedSchedules &&
        !syncHabits) {
      return {'success': false, 'hasChanges': false};
    }
    if (_isSyncing) {
      return {'success': false, 'hasChanges': false, 'error': '同步进行中，请稍后重试'};
    }
    _isSyncing = true;
    bool hasChanges = false;
    final scopedRefreshDomains = <DataRefreshDomain>{
      if (syncTodos) DataRefreshDomain.todos,
      if (syncTodos) DataRefreshDomain.todoGroups,
      if (syncCountdowns) DataRefreshDomain.countdowns,
      if (syncTimeLogs) DataRefreshDomain.timeLogs,
      if (syncPomodoro) DataRefreshDomain.pomodoro,
      if (syncPlanBlocks) DataRefreshDomain.planBlocks,
      if (syncFixedSchedules) DataRefreshDomain.fixedSchedules,
      if (syncHabits) DataRefreshDomain.habits,
    };
    List<ConflictInfo> conflicts = [];
    final Set<String> updatedTodoIds = <String>{};
    final staleHabitConflictSnapshots = <String, Map<String, dynamic>>{};
    final autoResolvedHabitConflictIds = <String>{};

    try {
      final prefs = await SharedPreferences.getInstance();
      int? userId = prefs.getInt('current_user_id');
      if (userId == null) throw Exception("用户未登录");

      // 2. 环境信息准备
      final String deviceId =
          await UserSessionStorage.getDeviceIdForUser(username);
      final String friendlyName =
          await UserSessionStorage.getDeviceFriendlyName();
      final String serverKey = ApiService.syncServerKey;
      final fixedScheduleServerScope = base64Url
          .encode(utf8.encode(ApiService.effectiveBaseUrl))
          .replaceAll('=', '');
      final fixedScheduleBootstrapKey =
          'fixed_schedule_sync_v1_${fixedScheduleServerScope}_$username';
      final fixedScheduleSyncInitialized =
          prefs.getBool(fixedScheduleBootstrapKey) == true;
      final habitBootstrapKey =
          'habit_sync_v1_${fixedScheduleServerScope}_$username';
      final habitSyncInitialized = prefs.getBool(habitBootstrapKey) == true;
      int lastSyncTime = forceFullSync
          ? 0
          : (prefs.getInt('last_sync_time_${serverKey}_$username') ?? 0);
      _lastSyncRequestAt = DateTime.now().millisecondsSinceEpoch;

      // 3. 🛡️ 核心修复：基于 op_logs 识别脏数据，并进行 UUID 去重处理（防止 1000+ 冗余同步）
      final db = await DatabaseHelper.instance.database;
      List<Map<String, dynamic>> dirtyTodos = [];
      List<Map<String, dynamic>> dirtyGroups = [];
      List<Map<String, dynamic>> dirtyCountdowns = [];
      List<Map<String, dynamic>> dirtyTimeLogs = [];
      List<Map<String, dynamic>> dirtyPlanBlocks = [];
      List<Map<String, dynamic>> dirtyFixedSchedules = [];
      List<Map<String, dynamic>> dirtyHabitGoals = [];
      List<Map<String, dynamic>> dirtyHabitRules = [];
      List<Map<String, dynamic>> dirtyHabitCheckIns = [];
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
      // 有些历史冲突只保存在本地 conflict_data，服务端后续同步不一定
      // 再把它放进 conflicts 或 server_habit_goals，因此这里也要登记快照。
      for (final goal in allLocalHabitGoals) {
        if (!goal.hasConflict || goal.conflictData == null) continue;
        staleHabitConflictSnapshots['habit_goals:${goal.uuid}'] =
            Map<String, dynamic>.from(goal.conflictData!);
      }
      for (final rule in allLocalHabitRules) {
        if (!rule.hasConflict || rule.conflictData == null) continue;
        staleHabitConflictSnapshots['habit_goal_rule_revisions:${rule.uuid}'] =
            Map<String, dynamic>.from(rule.conflictData!);
      }
      final autoResolvedMigrationConflicts =
          _clearResolvedRecurrenceMigrationConflicts(allLocalTodos);
      if (autoResolvedMigrationConflicts.isNotEmpty) {
        await saveTodos(
          username,
          autoResolvedMigrationConflicts,
          sync: true,
          recomputeScheduleConflicts: false,
        );
        hasChanges = true;
        debugPrint(
            '🧹 [同步修复] 已自动消解 ${autoResolvedMigrationConflicts.length} 条仅由循环系列迁移产生的版本冲突');
      }
      final repairedLocalSeriesIds =
          await _repairLocalRecurrenceSeriesAliasesFromHistory(
        db,
        allLocalTodos,
      );
      if (repairedLocalSeriesIds.isNotEmpty) {
        final versionsBeforeDedupe = {
          for (final todo in allLocalTodos) todo.id: todo.version,
        };
        final deletedBeforeDedupe = {
          for (final todo in allLocalTodos)
            if (todo.isDeleted) todo.id,
        };
        _deduplicatePersistedRecurrenceOccurrences(allLocalTodos);
        repairedLocalSeriesIds.addAll(allLocalTodos
            .where((todo) =>
                todo.isDeleted && !deletedBeforeDedupe.contains(todo.id))
            .map((todo) => todo.id));

        final repairedItems = allLocalTodos
            .where((todo) => repairedLocalSeriesIds.contains(todo.id))
            .toList();
        for (final todo in repairedItems) {
          // 去重分支已经提升过版本，只为单纯归并系列的实例补一次变更。
          if (todo.version == versionsBeforeDedupe[todo.id]) {
            todo.markAsChanged();
          }
        }
        await saveTodos(
          username,
          repairedItems,
          sync: true,
          recomputeScheduleConflicts: false,
        );
        hasChanges = true;
        debugPrint(
            '🧷 [同步修复] 根据本机同步历史将 ${repairedItems.length} 个被拆分的循环实例归回原系列');
      }
      final localTodosById = {for (final item in allLocalTodos) item.id: item};
      final localGroupsById = {
        for (final item in allLocalGroups) item.id: item
      };
      final localCountdownsById = {
        for (final item in allLocalCountdowns) item.id: item
      };
      if (!forceFullSync &&
          ((syncCountdowns && allLocalCountdowns.isEmpty) ||
              (syncTimeLogs && allLocalTimeLogs.isEmpty))) {
        debugPrint('🔄 本地倒数日/时间日志为空，自动降级为全量拉取以修复空库');
        lastSyncTime = 0;
      }

      // 按时间戳升序排列，这样 Map 的 putIfAbsent/赋值逻辑会自然保留最后一次更新
      final List<Map<String, dynamic>> pendingOps = await db.query('op_logs',
          where: 'is_synced = 0', orderBy: 'timestamp ASC');
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
          final hasLocalVersionConflict = localTodo != null &&
              localTodo.hasConflict &&
              _hasVersionConflict(localTodo.serverVersionData);
          if (_payloadHasVersionConflict(data) || hasLocalVersionConflict) {
            if (opId != null) consumedConflictOpIds.add(opId);
            continue;
          }
          dedupTodos[uuid] = _stripClientOnlyConflictForSync(data);
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
              (allLocalHabitGoals
                  .any((g) => g.uuid == uuid && g.hasConflict))) {
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
              (allLocalHabitRules
                  .any((r) => r.uuid == uuid && r.hasConflict))) {
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
        }
      }

      if (consumedConflictOpIds.isNotEmpty) {
        final placeholders =
            List.filled(consumedConflictOpIds.length, '?').join(',');
        await db.update(
          'op_logs',
          {'is_synced': 1, 'sync_error': ''},
          where: 'id IN ($placeholders)',
          whereArgs: consumedConflictOpIds,
        );
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

      // 兜底：除 op_logs 外，再按 updatedAt 增量补采，避免日志遗漏导致改删/新增不同步
      if (syncTodos) {
        for (final item in allLocalTodos) {
          if (item.updatedAt > lastSyncTime) {
            if (item.hasConflict &&
                _hasVersionConflict(item.serverVersionData)) {
              continue;
            }
            final data = item.toJson();
            data.remove('image_path');
            data.remove('imagePath');
            if (item.isDeleted &&
                _recurrenceDedupeTombstoneIds.contains(item.id)) {
              data['_recurrence_delete_reason'] = 'dedupe';
            }
            dedupTodos[item.id] = _stripClientOnlyConflictForSync(data);
          }
        }
        dirtyTodos = dedupTodos.values.toList();
      }
      if (syncCountdowns) {
        for (final item in allLocalCountdowns) {
          if (item.updatedAt > lastSyncTime) {
            if (item.hasConflict) continue;
            dedupCountdowns[item.id] = item.toJson();
          }
        }
        dirtyCountdowns = dedupCountdowns.values.toList();
      }
      if (syncTodos) {
        for (final item in allLocalGroups) {
          if (item.updatedAt > lastSyncTime) {
            if (item.hasConflict) continue;
            dedupGroups[item.id] = item.toJson();
          }
        }
        dirtyGroups = dedupGroups.values.toList();
      }

      // 兜底：规划块除 op_logs 外，再按 updatedAt 增量补采一遍，避免个别日志遗漏导致改删不同步
      if (syncPlanBlocks) {
        for (final item in allLocalPlanBlocks) {
          if (item.updatedAt > lastSyncTime) {
            dedupPlanBlocks[item.id] = item.toJson();
          }
        }
        dirtyPlanBlocks = dedupPlanBlocks.values.toList();
      }

      // 首次与支持 fixed_schedules v1 的服务端握手前，全量携带本地固定
      // 日程，确保“本地纵向切片”时期创建的数据不会因旧水位线而漏传。
      if (syncFixedSchedules) {
        for (final item in allLocalFixedSchedules) {
          if (!fixedScheduleSyncInitialized || item.updatedAt > lastSyncTime) {
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
          if (!habitSyncInitialized || item.updatedAt > lastSyncTime) {
            dedupHabitGoals[item.uuid] = item.toJson();
          }
        }
        for (final item in allLocalHabitRules) {
          if (!habitSyncInitialized || item.updatedAt > lastSyncTime) {
            dedupHabitRules[item.uuid] = item.toJson();
          }
        }
        for (final item in allLocalHabitCheckIns) {
          if (!habitSyncInitialized || item.updatedAt > lastSyncTime) {
            dedupHabitCheckIns[item.uuid] = item.toJson();
          }
        }
        dirtyHabitGoals = dedupHabitGoals.values.toList();
        dirtyHabitRules = dedupHabitRules.values.toList();
        dirtyHabitCheckIns = dedupHabitCheckIns.values.toList();
      }

      if (shouldUploadAllLocal) {
        if (syncTodos) {
          for (final item in allLocalTodos) {
            if (item.hasConflict &&
                _hasVersionConflict(item.serverVersionData)) {
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
        }
        dirtyTodos = dedupTodos.values.toList();
        dirtyGroups = dedupGroups.values.toList();
        dirtyCountdowns = dedupCountdowns.values.toList();
        dirtyPlanBlocks = dedupPlanBlocks.values.toList();
        dirtyFixedSchedules = dedupFixedSchedules.values.toList();
        dirtyHabitGoals = dedupHabitGoals.values.toList();
        dirtyHabitRules = dedupHabitRules.values.toList();
        dirtyHabitCheckIns = dedupHabitCheckIns.values.toList();
      }

      // TimeLogs 暂时保持原有逻辑 (直到迁移至 SQL)
      if (syncTimeLogs) {
        dirtyTimeLogs = allLocalTimeLogs
            .where((t) => t.updatedAt > lastSyncTime)
            .map((t) => t.toJson())
            .toList();
      }

      // debugPrint('🔍 [同步判定] lastSyncTime: $lastSyncTime, 本地总任务数: ${allLocalTodos.length}');

      // 4. 读取本机待同步屏幕时间 (改为 Map 结构)。局部同步关闭该域时，
      // 不能把待上传缓存偷偷带入通用 delta 请求。
      final localPackage = syncScreenTime
          ? await getLocalScreenTimeMap()
          : const <String, dynamic>{};
      List<dynamic> localScreenStats = localPackage['apps'] ?? [];
      String? recordDate = localPackage['date']; // 🚀 从缓存中拿原始日期

      Map<String, dynamic>? screenPayload;
      if (localScreenStats.isNotEmpty) {
        try {
          // 如果没有记录日期（旧版本升级上来），退而求其次用今天
          final String finalDate =
              recordDate ?? DateFormat('yyyy-MM-dd').format(DateTime.now());

          screenPayload = {
            'device_name': friendlyName,
            'record_date': finalDate,
            'apps': localScreenStats
                .whereType<Map>()
                .map((e) => {
                      'app_name': e['app_name']?.toString() ?? 'Unknown',
                      'duration': (e['duration'] is int) ? e['duration'] : 0,
                    })
                .toList(),
          };
          debugPrint(
              "🚀 准备同步本机屏幕时间 ($finalDate): ${localScreenStats.length} 条数据");
        } catch (se) {
          debugPrint("屏幕时间 payload 构造失败: $se");
        }
      } else {
        // null
      }

      // 5. 发起网络同步请求
      Future<Map<String, dynamic>> sendSyncRequest() {
        return ApiService.postDeltaSync(
          userId: userId,
          lastSyncTime: lastSyncTime,
          deviceId: deviceId,
          todosChanges: dirtyTodos,
          todoGroupsChanges: dirtyGroups,
          countdownsChanges: dirtyCountdowns,
          timeLogsChanges: dirtyTimeLogs,
          planBlocksChanges: dirtyPlanBlocks,
          fixedSchedulesChanges: dirtyFixedSchedules,
          fixedSchedulesFullSync: syncFixedSchedules &&
              (!fixedScheduleSyncInitialized || forceFullSync),
          habitGoalsChanges: dirtyHabitGoals,
          habitRuleChanges: dirtyHabitRules,
          habitCheckInChanges: dirtyHabitCheckIns,
          habitFullSync: syncHabits && (!habitSyncInitialized || forceFullSync),
          screenTime: syncScreenTime ? screenPayload : null,
          forceFullSync: forceFullSync,
        );
      }

      Map<String, dynamic> response = await sendSyncRequest();
      bool hasPendingUpload() =>
          dirtyTodos.isNotEmpty ||
          dirtyGroups.isNotEmpty ||
          dirtyCountdowns.isNotEmpty ||
          dirtyTimeLogs.isNotEmpty ||
          dirtyPlanBlocks.isNotEmpty ||
          dirtyFixedSchedules.isNotEmpty ||
          dirtyHabitGoals.isNotEmpty ||
          dirtyHabitRules.isNotEmpty ||
          dirtyHabitCheckIns.isNotEmpty ||
          screenPayload != null;

      bool isDebounceIgnored(Map<String, dynamic> syncResponse) {
        if (!forceFullSync && !hasPendingUpload()) {
          return false;
        }
        final remotePayloadEmpty = (syncResponse['server_todos'] as List?)
                    ?.isEmpty ==
                true &&
            (syncResponse['server_todo_groups'] as List?)?.isEmpty == true &&
            (syncResponse['server_countdowns'] as List?)?.isEmpty == true &&
            (syncResponse['server_time_logs'] as List?)?.isEmpty == true &&
            (syncResponse['server_pomodoros'] as List?)?.isEmpty == true &&
            (syncResponse['server_tags'] as List?)?.isEmpty == true &&
            (syncResponse['server_plan_blocks'] as List?)?.isEmpty == true &&
            (syncResponse['server_fixed_schedules'] as List?)?.isEmpty ==
                true &&
            (syncResponse['server_habit_goals'] as List?)?.isEmpty == true &&
            (syncResponse['server_habit_goal_rules'] as List?)?.isEmpty ==
                true &&
            (syncResponse['server_habit_checkins'] as List?)?.isEmpty == true;
        final syncTimeUnchanged =
            (syncResponse['new_sync_time'] ?? -1) == lastSyncTime;
        return syncResponse['success'] == true &&
            syncTimeUnchanged &&
            remotePayloadEmpty &&
            (syncResponse['status'] == 'ignored' ||
                forceFullSync ||
                hasPendingUpload());
      }

      if (isDebounceIgnored(response)) {
        debugPrint('⏳ [同步] 命中服务端防抖空响应，3.2s 后自动重试一次');
        await Future.delayed(const Duration(milliseconds: 3200));
        response = await sendSyncRequest();
        if (isDebounceIgnored(response) && hasPendingUpload()) {
          throw Exception('同步被服务端防抖延迟，已保留本地待同步记录');
        }
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
      final acknowledgeHabitOps =
          SyncCapabilityService.shouldAcknowledgeHabitOps(
        syncEnabled: syncHabits,
        rawCapabilities: response['sync_capabilities'],
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
          final localKnownTeams =
              localTeamRows.map((r) => r['uuid'].toString()).toSet();
          // 合并到 currentTeams 中，使孤立检测和防复活守卫也能受益
          currentTeams = localKnownTeams;
        } catch (_) {}
      }

      bool isOutsideJoinedTeam(String? teamUuid) {
        return joinedTeamUuids != null &&
            teamUuid != null &&
            teamUuid.isNotEmpty &&
            !currentTeams.contains(teamUuid);
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
      if (response['success'] == true) {
        // 仅标记“未冲突”的本地操作为已同步。阻塞冲突对应的 oplog 必须保留，
        // 否则本地完成/取消完成会被服务端旧状态覆盖后失去再次上传机会。
        final List<dynamic> rawConflicts =
            (response['conflicts'] as List?) ?? [];
        final Set<String> blockingConflictUuids = <String>{};
        for (final c in rawConflicts) {
          if (c is! Map) continue;
          final type = c['type']?.toString();
          if (type == 'schedule_conflict' || type == 'pomodoro') {
            continue;
          }
          final item = c['item'];
          if (item is! Map) continue;
          final uuid =
              (item['uuid'] ?? item['id'] ?? item['todo_uuid'])?.toString();
          if (uuid != null && uuid.isNotEmpty) {
            blockingConflictUuids.add(uuid);
          }
        }

        final oplogResolution = SyncOplogPolicy.resolveRequestSnapshot(
          requestSnapshot: requestOplogSnapshot,
          blockingConflictUuids: blockingConflictUuids,
          acknowledgeFixedScheduleOps: acknowledgeFixedScheduleOps,
          acknowledgeHabitOps: acknowledgeHabitOps,
        );
        await _updateOplogRowsByIds(
          db,
          oplogResolution.acknowledgedIds,
          {'is_synced': 1, 'sync_error': ''},
        );
        await _updateOplogRowsByIds(
          db,
          oplogResolution.blockedIds,
          {'is_synced': 0, 'sync_error': 'server_conflict'},
        );

        // 重新读取当前待同步日志。本次请求发出后新增的操作
        // 没有上传，不能被本次响应确认，也不能被旧的服务端快照覆盖。
        final currentPendingRows = await db.query(
          'op_logs',
          where: 'is_synced = 0',
          orderBy: 'timestamp ASC',
        );
        final currentPendingEntries = currentPendingRows
            .map(SyncOplogEntry.fromRow)
            .whereType<SyncOplogEntry>()
            .toList(growable: false);
        _pendingSyncOplogUuids =
            SyncOplogPolicy.todoUuids(currentPendingEntries);
        inFlightTodoMutationUuids =
            SyncOplogPolicy.todoUuidsCreatedAfterSnapshot(
          requestSnapshot: requestOplogSnapshot,
          currentPending: currentPendingEntries,
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
            if (latest != null) allLocalTodos[i] = latest;
          }
        }

        // 🚀 处理独立待办完成情况
        final List<dynamic>? indCompletions =
            response['independent_completions'];
        //debugPrint(
        //    '🧪 [SyncDiag][IndepCompletion] indCompletions=${indCompletions?.length ?? "null"}');
        if (indCompletions != null) {
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
            final rawCompleted = ic['is_completed'];
            final isCompleted = rawCompleted == 1 ||
                rawCompleted == true ||
                rawCompleted?.toString() == '1' ||
                rawCompleted?.toString().toLowerCase() == 'true';
            final serverUpdatedAt =
                int.tryParse(ic['updated_at']?.toString() ?? '') ?? 0;
            final existing = await db.query(
              'todo_completions',
              where: 'todo_uuid = ? AND user_id = ?',
              whereArgs: [todoUuid, userId],
              limit: 1,
            );
            final localUpdatedAt = existing.isNotEmpty
                ? (existing.first['updated_at'] as num?)?.toInt() ?? 0
                : 0;
            // 🚀 时间戳比较修复：如果本地没有完成状态记录，判定为从未修改（localUpdatedAt=0），此时应接受服务端更新
            // 仅当本地有明确的更新时间且晚于服务端时，才跳过 DB 写入
            final hasLocalModification = localUpdatedAt > 0;
            if (hasLocalModification &&
                serverUpdatedAt > 0 &&
                serverUpdatedAt < localUpdatedAt) {
              // 本地有更新且晚于服务端，跳过 DB 写入，但仍需从 DB 读取正确值更新内存
              final localIsCompleted = existing.isNotEmpty
                  ? (existing.first['is_completed'] as int?) ?? 0
                  : 0;
              final localIdx =
                  allLocalTodos.indexWhere((todo) => todo.id == todoUuid);
              if (localIdx != -1 && allLocalTodos[localIdx].collabType == 1) {
                if (allLocalTodos[localIdx].isDone != (localIsCompleted == 1)) {
                  allLocalTodos[localIdx].isDone = localIsCompleted == 1;
                  independentCompletionChanged = true;
                  if (!allLocalTodos[localIdx].isDeleted) {
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
            batch.insert(
                'todo_completions',
                {
                  'todo_uuid': todoUuid,
                  'user_id': userId,
                  'is_completed': isCompleted ? 1 : 0,
                  'updated_at': serverUpdatedAt > 0
                      ? serverUpdatedAt
                      : DateTime.now().millisecondsSinceEpoch,
                },
                conflictAlgorithm: ConflictAlgorithm.replace);
            final localIdx =
                allLocalTodos.indexWhere((todo) => todo.id == todoUuid);
            if (localIdx != -1 && allLocalTodos[localIdx].collabType == 1) {
              if (allLocalTodos[localIdx].isDone != isCompleted) {
                allLocalTodos[localIdx].isDone = isCompleted;
                independentCompletionChanged = true;
                if (!allLocalTodos[localIdx].isDeleted) {
                  updatedTodoIds.add(todoUuid);
                }
              }
            }
          }
          await batch.commit(noResult: true);
          if (independentCompletionChanged) {
            hasChanges = true;
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
              hasChanges = true;
              teamChanged = true;
            }
          }

          // 🚀 核心优化：如果发现同步返回的团队列表与本地认知不符，或者刚刚清理了孤立团队，则提示 WS 重新订阅新频道
          if (teamChanged || currentTeams.length != localTeamRows.length) {
            debugPrint("👥 [协同] 团队列表发生变化，请求 WebSocket 刷新订阅...");
            // 利用 resumeSync 内部的逻辑可以触发重连与重新订阅
            Future.microtask(() => PomodoroSyncService.instance.resumeSync());
          }
        }
      } else {
        final errorMsg = response['message']?.toString() ?? '同步失败';

        // 🚀 记录同步失败的原因，方便用户查看
        await db.update('op_logs', {'sync_error': errorMsg},
            where: 'is_synced = 0');
        throw Exception(errorMsg);
      }

      // 解析服务器返回的实时冲突
      if (response['conflicts'] is List) {
        conflicts = (response['conflicts'] as List)
            .map((c) => ConflictInfo.fromJson(c as Map<String, dynamic>))
            .toList();
      }

      // 服务端有时只在 conflicts 返回冲突快照，不会重复返回整条习惯记录。
      // 先把这些快照登记下来，后面可判断是否只是残留冲突标记。
      final localHabitGoalIds =
          allLocalHabitGoals.map((item) => item.uuid).toSet();
      final localHabitRuleIds =
          allLocalHabitRules.map((item) => item.uuid).toSet();
      for (final conflict in conflicts) {
        final itemId =
            (conflict.item['uuid'] ?? conflict.item['id'])?.toString();
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

      // 6. 🛡️ 数据合并逻辑 (LWW - Last Write Wins) — O(1) HashMap lookup

      // 🚀 核心修复：获取本地忽略表，防止”僵尸数据”复活
      final ignoredRows = await db.query('ignored_remote_items');
      final Set<String> ignoredUuids =
          ignoredRows.map((e) => e['uuid'].toString()).toSet();

      // 合并 Todos。旧版服务端没有持久化 recurrence_series_id；先利用本地
      // 已知关系或唯一、可验证的循环轨迹修复，再进入常规 LWW 合并。
      List<dynamic> serverTodos =
          syncTodos ? (response['server_todos'] ?? []) : const [];
      final remoteTodoEntries = <({Map<String, dynamic> raw, TodoItem item})>[];
      for (final raw in serverTodos) {
        final serverRaw =
            raw is Map ? raw.cast<String, dynamic>() : <String, dynamic>{};
        final sanitizedServerRaw = _stripClientOnlyConflictForSync(serverRaw);
        remoteTodoEntries.add((
          raw: serverRaw,
          item: TodoItem.fromJson(sanitizedServerRaw),
        ));
      }
      final repairedRemoteTodoIds = _repairMissingRemoteRecurrenceSeriesIds(
        remoteTodoEntries.map((entry) => entry.item).toList(),
        allLocalTodos,
      );

      // Snapshot items with conflicts before merge, to detect resolutions after merge
      final Set<String> preMergeConflictIds =
          allLocalTodos.where((t) => t.hasConflict).map((t) => t.id).toSet();

      final Map<String, int> todosIndexMap = {
        for (var i = 0; i < allLocalTodos.length; i++) allLocalTodos[i].id: i
      };
      for (final entry in remoteTodoEntries) {
        final serverRaw = entry.raw;
        final sItem = entry.item;
        if (ignoredUuids.contains(sItem.id)) {
          debugPrint('🚫 [合并跳过] UUID: ${sItem.id} 已在本地忽略列表中');
          continue;
        }
        // 🚀 核心防御：非所属团队的数据处理（防止退出/被踢后数据回流）
        if (isOutsideJoinedTeam(sItem.teamUuid)) {
          debugPrint(
              '🚫 [合并跳过] UUID: ${sItem.id} 团队 ${sItem.teamUuid} 已不在当前团队列表中');
          continue;
        }
        final serverDeviceId = serverRaw['device_id']?.toString();
        final bool isUpdatedByOtherDevice = serverDeviceId != null &&
            serverDeviceId.isNotEmpty &&
            serverDeviceId != deviceId;
        if (todosIndexMap.containsKey(sItem.id)) {
          final idx = todosIndexMap[sItem.id]!;
          final local = allLocalTodos[idx];
          final usesStrictRecurringLww =
              _isRecurringTodoForLww(local) || _isRecurringTodoForLww(sItem);
          final serverWinsStrictRecurringLww =
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
                '🛡️ [merge] SKIP UUID=${sItem.id} (local mutation protected)');
            continue;
          }

          debugPrint(
              '🔄 [合并对比] UUID: ${sItem.id}, Server(V:${sItem.version}, D:${sItem.isDeleted}), Local(V:${local.version}, D:${local.isDeleted})');

          // 防回滚：本地已删除且更”新”时，拒绝服务端旧的未删除数据复活
          if (local.isDeleted &&
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
                '🛡️ [防复活] UUID: ${sItem.id} 本地已删除(V:${local.version})，服务端未删除(V:${sItem.version})，拒绝复活');
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
                '🛡️ [防复活-强拦截] UUID: ${sItem.id} 团队 ${local.teamUuid} 已解散(currentTeams=$currentTeams)，拒绝未删除版本复活');
            continue;
          }

          final mergeVersionCond = sItem.version > local.version;
          final mergeTimeCond =
              sItem.updatedAt > local.updatedAt && !sItem.hasConflict;
          if (sItem.hasConflict || local.hasConflict) {
            debugPrint(
                '🩺 [合并决策] UUID=${sItem.id} sV=${sItem.version} lV=${local.version} sU=${sItem.updatedAt} lU=${local.updatedAt} sConflict=${sItem.hasConflict} lConflict=${local.hasConflict} versionCond=$mergeVersionCond timeCond=$mergeTimeCond isDeleted=${sItem.isDeleted}');
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
            hasChanges = true;
          } else if (sItem.groupId != local.groupId &&
              (usesStrictRecurringLww
                  ? serverWinsStrictRecurringLww
                  : sItem.updatedAt >= local.updatedAt)) {
            // Only accept group_id changes if server item is at least as new
            // as local item, preserving LWW semantics for folder assignments.
            allLocalTodos[idx].groupId = sItem.groupId;
            hasChanges = true;
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
                    '⏭️ [MemoryShield] Skipping conflict resurrection for recently resolved todo: ${localItem.id}');
              } else {
                // Server still has conflict but local was resolved — sync conflict metadata only
                localItem.hasConflict = true;
                localItem.serverVersionData = sItem.serverVersionData;
                hasChanges = true;
              }
            } else if (!sItem.hasConflict && localItem.hasConflict) {
              // Server cleared conflict (resolved from another device) — accept cleared state
              localItem.hasConflict = false;
              localItem.serverVersionData = null;
              recentlyResolvedUuids.remove(sItem.id);
              recentlyResolvedTimes.remove(sItem.id);
              hasChanges = true;
            }
          }
        } else {
          if (!sItem.isDeleted) {
            todosIndexMap[sItem.id] = allLocalTodos.length;
            allLocalTodos.add(sItem);
            if (isUpdatedByOtherDevice) {
              updatedTodoIds.add(sItem.id);
            }
            hasChanges = true;
          }
        }
      }

      // 合并 TodoGroups
      List<dynamic> serverGroups =
          syncTodos ? (response['server_todo_groups'] ?? []) : const [];
      final Map<String, int> groupsIndexMap = {
        for (var i = 0; i < allLocalGroups.length; i++) allLocalGroups[i].id: i
      };
      for (var raw in serverGroups) {
        TodoGroup sItem = TodoGroup.fromJson(raw);
        if (ignoredUuids.contains(sItem.id)) {
          debugPrint('🚫 [合并跳过] 文件夹 UUID: ${sItem.id} 已忽略');
          continue;
        }
        if (isOutsideJoinedTeam(sItem.teamUuid)) {
          debugPrint(
              '🚫 [合并跳过] 文件夹 UUID: ${sItem.id} 团队 ${sItem.teamUuid} 已不在当前团队列表中');
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
            hasChanges = true;
          }

          // Handle conflict flag divergence separately from content merge.
          if (!sItem.isDeleted) {
            final localGroup = allLocalGroups[idx];
            if (sItem.hasConflict && !localGroup.hasConflict) {
              if (isRecentlyResolved(localGroup.id)) {
                debugPrint(
                    '⏭️ [MemoryShield] Skipping conflict resurrection for recently resolved group: ${localGroup.id}');
              } else {
                localGroup.hasConflict = true;
                localGroup.conflictData = sItem.conflictData;
                hasChanges = true;
              }
            } else if (!sItem.hasConflict && localGroup.hasConflict) {
              localGroup.hasConflict = false;
              localGroup.conflictData = null;
              recentlyResolvedUuids.remove(sItem.id);
              recentlyResolvedTimes.remove(sItem.id);
              hasChanges = true;
            }
          }
        } else {
          if (!sItem.isDeleted) {
            groupsIndexMap[sItem.id] = allLocalGroups.length;
            allLocalGroups.add(sItem);
            hasChanges = true;
          }
        }
      }

      // 合并 Countdowns
      List<dynamic> serverCountdowns =
          syncCountdowns ? (response['server_countdowns'] ?? []) : const [];
      final Map<String, int> countdownsIndexMap = {
        for (var i = 0; i < allLocalCountdowns.length; i++)
          allLocalCountdowns[i].id: i
      };
      for (var raw in serverCountdowns) {
        CountdownItem sItem = CountdownItem.fromJson(raw);
        if (ignoredUuids.contains(sItem.id)) {
          debugPrint('🚫 [合并跳过] 倒计时 UUID: ${sItem.id} 已忽略');
          continue;
        }
        if (isOutsideJoinedTeam(sItem.teamUuid)) {
          debugPrint(
              '🚫 [合并跳过] 倒计时 UUID: ${sItem.id} 团队 ${sItem.teamUuid} 已不在当前团队列表中');
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
            hasChanges = true;
          }

          // Handle conflict flag divergence separately from content merge.
          if (!sItem.isDeleted) {
            final localCountdown = allLocalCountdowns[idx];
            if (sItem.hasConflict && !localCountdown.hasConflict) {
              if (isRecentlyResolved(localCountdown.id)) {
                debugPrint(
                    '⏭️ [MemoryShield] Skipping conflict resurrection for recently resolved countdown: ${localCountdown.id}');
              } else {
                localCountdown.hasConflict = true;
                localCountdown.conflictData = sItem.conflictData;
                hasChanges = true;
              }
            } else if (!sItem.hasConflict && localCountdown.hasConflict) {
              localCountdown.hasConflict = false;
              localCountdown.conflictData = null;
              recentlyResolvedUuids.remove(sItem.id);
              recentlyResolvedTimes.remove(sItem.id);
              hasChanges = true;
            }
          }
        } else {
          if (!sItem.isDeleted) {
            countdownsIndexMap[sItem.id] = allLocalCountdowns.length;
            allLocalCountdowns.add(sItem);
            hasChanges = true;
          }
        }
      }

      // 合并 TimeLogs
      List<dynamic> serverTimeLogs =
          syncTimeLogs ? (response['server_time_logs'] ?? []) : const [];
      final Map<String, int> timeLogsIndexMap = {
        for (var i = 0; i < allLocalTimeLogs.length; i++)
          allLocalTimeLogs[i].id: i
      };
      for (var raw in serverTimeLogs) {
        TimeLogItem sItem = TimeLogItem.fromJson(raw);
        if (isOutsideJoinedTeam(sItem.teamUuid)) {
          debugPrint(
              '🚫 [合并跳过] 时间日志 UUID: ${sItem.id} 团队 ${sItem.teamUuid} 已不在当前团队列表中');
          continue;
        }
        if (timeLogsIndexMap.containsKey(sItem.id)) {
          final idx = timeLogsIndexMap[sItem.id]!;
          if (sItem.isDeleted ||
              sItem.version > allLocalTimeLogs[idx].version ||
              sItem.updatedAt > allLocalTimeLogs[idx].updatedAt) {
            allLocalTimeLogs[idx] = sItem;
            hasChanges = true;
          }
        } else {
          if (!sItem.isDeleted) {
            timeLogsIndexMap[sItem.id] = allLocalTimeLogs.length;
            allLocalTimeLogs.add(sItem);
            hasChanges = true;
          }
        }
      }

      // 合并 TodoPlanBlocks
      if (syncPlanBlocks) {
        List<dynamic> serverPlanBlocks = response['server_plan_blocks'] ?? [];
        final Map<String, int> planBlocksIndexMap = {
          for (var i = 0; i < allLocalPlanBlocks.length; i++)
            allLocalPlanBlocks[i].id: i
        };
        for (var raw in serverPlanBlocks) {
          TodoPlanBlock sItem =
              TodoPlanBlock.fromJson((raw as Map).cast<String, dynamic>());
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
              hasChanges = true;
            }
          } else if (!sItem.isDeleted) {
            planBlocksIndexMap[sItem.id] = allLocalPlanBlocks.length;
            allLocalPlanBlocks.add(sItem);
            hasChanges = true;
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
              isOutsideJoinedTeam(serverItem.teamUuid)) {
            continue;
          }
          final localIndex = fixedSchedulesIndexMap[serverItem.id];
          if (localIndex == null) {
            if (!serverItem.isDeleted) {
              fixedSchedulesIndexMap[serverItem.id] =
                  allLocalFixedSchedules.length;
              allLocalFixedSchedules.add(serverItem);
              hasChanges = true;
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
            hasChanges = true;
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
          final serverItem = HabitGoal.fromJson(
            Map<String, dynamic>.from(raw),
          );
          if (ignoredUuids.contains(serverItem.uuid)) continue;
          final localIndex = habitGoalsIndexMap[serverItem.uuid];
          if (localIndex == null) {
            if (!serverItem.isDeleted) {
              habitGoalsIndexMap[serverItem.uuid] = allLocalHabitGoals.length;
              allLocalHabitGoals.add(serverItem);
              hasChanges = true;
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
          final serverWins = serverItem.version > localItem.version ||
              (serverItem.updatedAt > localItem.updatedAt &&
                  !serverItem.hasConflict);
          if (serverWins) {
            allLocalHabitGoals[localIndex] = serverItem;
            hasChanges = true;
          } else if (serverItem.hasConflict && !localItem.hasConflict) {
            // 服务端冲突标记与本地内容分开同步：不覆盖本地新内容，
            // 只让冲突状态保持一致，冲突收件箱可见。
            localItem.hasConflict = true;
            localItem.conflictData = serverItem.conflictData;
            hasChanges = true;
          } else if (!serverItem.hasConflict && localItem.hasConflict) {
            localItem.hasConflict = false;
            localItem.conflictData = null;
            hasChanges = true;
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
              hasChanges = true;
            }
            continue;
          }
          final localItem = allLocalHabitRules[localIndex];
          if (serverItem.hasConflict) {
            staleHabitConflictSnapshots[
                    'habit_goal_rule_revisions:${serverItem.uuid}'] =
                serverItem.toJson();
          }
          // 与目标一致：冲突标记会推高服务端 updated_at，
          // 时间路径必须排除冲突项，避免冲突快照覆盖本地新内容。
          final serverWins = serverItem.version > localItem.version ||
              (serverItem.updatedAt > localItem.updatedAt &&
                  !serverItem.hasConflict);
          if (serverWins) {
            allLocalHabitRules[localIndex] = serverItem;
            hasChanges = true;
          } else if (serverItem.hasConflict && !localItem.hasConflict) {
            localItem.hasConflict = true;
            localItem.conflictData = serverItem.conflictData;
            hasChanges = true;
          } else if (!serverItem.hasConflict && localItem.hasConflict) {
            localItem.hasConflict = false;
            localItem.conflictData = null;
            hasChanges = true;
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
              hasChanges = true;
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
            hasChanges = true;
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
          hasChanges = true;
          debugPrint('🧹 [同步修复] 已自动清理 ${autoResolved.length} 条业务内容一致的习惯冲突标记');
        }
      }

      // 🚀 关键：将 conflicts 数组中的冲突也标记到本地数据上。
      // 服务器在标记 has_conflict=1 时可能不会同时更新 updated_at，
      // 导致该条目被 filterWithActualTime 过滤掉，不在 server_todos 中。
      // 这里从 conflicts 数组直接补标，确保 ConflictInboxScreen 能看到。
      final ignoredScheduleConflictKeys =
          await _getIgnoredScheduleConflictKeys(username);
      if (conflicts.isNotEmpty) {
        final conflictDetectionEnabled = await getConflictDetectionEnabled();
        for (final c in conflicts) {
          final itemId = (c.item['uuid'] ?? c.item['id'] ?? '').toString();
          if (itemId.isEmpty) continue;
          if (isRecentlyResolved(itemId)) {
            debugPrint(
                '⏭️ [MemoryShield] Skipping re-flag of recently resolved item in conflicts: $itemId');
            continue;
          }
          final serverVersion = c.conflictWith;
          if (c.type == 'schedule_conflict' &&
              todosIndexMap.containsKey(itemId)) {
            if (!conflictDetectionEnabled) continue;
            final todo = allLocalTodos[todosIndexMap[itemId]!];
            final peer = Map<String, dynamic>.from(serverVersion);
            if (_isSameRecurrenceSeriesPayload(todo, peer)) continue;
            final conflictKey = _scheduleConflictKeyFromPayload(todo, peer);
            if (conflictKey != null &&
                ignoredScheduleConflictKeys.contains(conflictKey)) {
              continue;
            }
            final data = {
              'uuid': todo.id,
              'id': todo.id,
              'content': todo.title,
              'team_uuid': todo.teamUuid,
              'schedule_scope':
                  (todo.teamUuid?.isNotEmpty ?? false) ? 'team' : 'personal',
              'relation_type': 'personal_personal',
              'conflict_kind': 'logic',
              'conflict_type': 'local_schedule_conflict',
              'source': 'server_detector',
              'start_time': todo.createdDate ?? todo.createdAt,
              'end_time': todo.dueDate?.millisecondsSinceEpoch,
              'conflict_with': [peer],
            };
            if (!todo.hasConflict ||
                jsonEncode(todo.serverVersionData) != jsonEncode(data)) {
              todo.hasConflict = true;
              todo.serverVersionData = data;
              hasChanges = true;
            }
            continue;
          }

          final serverVersionId =
              (serverVersion['uuid'] ?? serverVersion['id'] ?? '').toString();
          final bool isSameItemServerVersion = serverVersionId.isNotEmpty &&
              serverVersionId == itemId.toString();
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
              debugPrint('⏭️ Skipping re-flag of resolved todo $itemId '
                  '(hasConflict=${todo.hasConflict}, localV=${todo.version}, serverV=$serverConflictVer)');
            } else {
              todo.hasConflict = true;
              todo.serverVersionData = serverVersion;
              hasChanges = true;
            }
          }
          if (countdownsIndexMap.containsKey(itemId)) {
            final countdown = allLocalCountdowns[countdownsIndexMap[itemId]!];
            final serverConflictVer =
                (serverVersion['version'] as num?)?.toInt() ?? 0;
            if (!countdown.hasConflict ||
                countdown.version > serverConflictVer) {
              // skip — already resolved
            } else {
              countdown.hasConflict = true;
              countdown.conflictData = serverVersion;
              hasChanges = true;
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
              hasChanges = true;
            }
          }
          // TimeLogs don't have hasConflict field, skip
        }
      }

      // 合并 Pomodoro (Tags & Records)
      if (syncPomodoro) {
        try {
          // 顺序：拉取标签 -> 上传标签 -> 上传记录 -> 拉取记录
          await PomodoroService.syncTagsFromCloud();
          await PomodoroService.syncTagsToCloud();
          await PomodoroService.syncRecordsToCloud(
              forceFullSync: forceFullSync);
          bool pomodoroChanged = await PomodoroService.syncRecordsFromCloud(
              forceFullSync: forceFullSync);
          if (pomodoroChanged) hasChanges = true;
        } catch (pe) {
          debugPrint("Pomodoro sync error: $pe");
        }
      }

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
          hasChanges = true;
        }
        // A sync-source save intentionally does not clear this cache. Remote
        // recurring snapshots are different: the just-downloaded tombstones
        // or occurrences can expose a series-day gap that must be repaired on
        // the next read instead of waiting until tomorrow.
        _recurrenceCheckCache.clear();
      }
      if (await getConflictDetectionEnabled()) {
        if (_recomputeLocalTodoScheduleConflicts(
          allLocalTodos,
          ignoredScheduleConflictKeys: ignoredScheduleConflictKeys,
          skipIds: recentlyResolvedIds,
        )) {
          hasChanges = true;
        }
      } else if (_clearLocalTodoScheduleConflicts(allLocalTodos)) {
        hasChanges = true;
      }

      if (hasChanges) {
        if (syncTodos) {
          await saveTodos(username, allLocalTodos,
              sync: false, isSyncSource: true);
          await saveTodoGroups(username, allLocalGroups,
              sync: false, isSyncSource: true);
        }
        if (syncCountdowns) {
          await saveCountdowns(username, allLocalCountdowns,
              sync: false, isSyncSource: true);
        }
        if (syncTimeLogs) {
          await saveTimeLogs(username, allLocalTimeLogs, sync: false);
        }
        if (syncPlanBlocks) {
          await savePlanBlocks(username, allLocalPlanBlocks,
              sync: false, isSyncSource: true);
        }
        if (syncFixedSchedules && fixedSchedulesSupported) {
          await saveFixedSchedules(
            username,
            allLocalFixedSchedules,
            sync: false,
            isSyncSource: true,
          );
        }
        if (syncHabits && habitsSupported) {
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
        }
        _pendingSyncOplogUuids.clear(); // 🚀 清除保护，防止跨同步周期的旧 UUID 干扰
        _forceFlushProtectedUuids.clear(); // 🚀 清除 force-flush 保护
      }

      // 将从旧云端响应中恢复出的系列关系作为一次真实本地修复重新上传。
      // 先完成同步源落库，再提升版本，确保 saveTodos 能生成待上传 oplog。
      if (repairedRemoteTodoIds.isNotEmpty) {
        final repairIdsToUpload = repairedRemoteTodoIds.where((id) =>
            recurrenceDedupeChangedIds.contains(id) ||
            !_attemptedRecurrenceSeriesRepairUploads.contains('$username|$id'));
        final repairedItems = allLocalTodos
            .where((todo) => repairIdsToUpload.contains(todo.id))
            .toList();
        for (final todo in repairedItems) {
          todo.markAsChanged();
        }
        if (repairedItems.isNotEmpty) {
          await saveTodos(
            username,
            repairedItems,
            sync: true,
            recomputeScheduleConflicts: false,
          );
          _attemptedRecurrenceSeriesRepairUploads.addAll(
            repairedItems.map((todo) => '$username|${todo.id}'),
          );
          hasChanges = true;
          debugPrint('🧩 [同步修复] 已恢复并排队回传 ${repairedItems.length} 个循环实例的系列关系');
        }
      }

      // 8. 更新同步水位线
      int newSyncTime =
          response['new_sync_time'] ?? DateTime.now().millisecondsSinceEpoch;
      await prefs.setInt('last_sync_time_${serverKey}_$username', newSyncTime);
      if (syncFixedSchedules && fixedSchedulesSupported) {
        await prefs.setBool(fixedScheduleBootstrapKey, true);
      }
      if (syncHabits && habitsSupported) {
        await prefs.setBool(habitBootstrapKey, true);
      }

      // 如果屏幕时间同步成功，可以在这里刷新 UI 用的 Cache 数据（如果后端有返回最新的聚合数据）
      if (syncScreenTime && response['screen_time_results'] != null) {
        await saveScreenTimeCache(response['screen_time_results']);
      }

      // 9. 只通知实际参与本轮同步的数据域，避免时间日志、习惯等局部同步
      // 重新读取整个首页数据集。
      if (hasChanges && scopedRefreshDomains.isNotEmpty) {
        triggerRefresh(scopedRefreshDomains);
      }

      conflicts.removeWhere((conflict) {
        final itemId =
            (conflict.item['uuid'] ?? conflict.item['id'])?.toString();
        if (itemId == null || itemId.isEmpty) return false;
        if (autoResolvedHabitConflictIds.contains(itemId)) return true;
        TodoItem? local;
        for (final todo in allLocalTodos) {
          if (todo.id == itemId) {
            local = todo;
            break;
          }
        }
        if (local != null && (local.isDeleted || !local.hasConflict)) {
          return true;
        }
        for (final goal in allLocalHabitGoals) {
          if (goal.uuid == itemId) return goal.isDeleted || !goal.hasConflict;
        }
        for (final rule in allLocalHabitRules) {
          if (rule.uuid == itemId) return rule.isDeleted || !rule.hasConflict;
        }
        return false;
      });

      // 10. 🛡️ 内存守卫：同步成功后，自动从锁定集合中清理掉在最新 conflicts 中不再包含的 ID
      final serverConflictIds = conflicts
          .map((c) => (c.item['uuid'] ?? c.item['id'] ?? '').toString())
          .toSet();
      recentlyResolvedUuids
          .removeWhere((id) => !serverConflictIds.contains(id));
      recentlyResolvedTimes
          .removeWhere((id, _) => !serverConflictIds.contains(id));
      if (recentlyResolvedUuids.isNotEmpty) {
        debugPrint(
            '🛡️ [MemoryShield] Remaining locked items in memory shield: $recentlyResolvedUuids');
      }

      return {
        'success': true,
        'hasChanges': hasChanges,
        'conflicts': conflicts,
        'updatedTodoIds': updatedTodoIds.toList(),
      };
    } catch (e) {
      debugPrint("syncData error: $e");
      return {'success': false, 'hasChanges': false, 'error': e.toString()};
    } finally {
      _isSyncing = false;
      // 🚀 无条件清除保护，防止跨越同步周期
      _pendingSyncOplogUuids.clear();
      _forceFlushProtectedUuids.clear();
    }
  }

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

    final results = await Future.wait(candidates.values.map((candidate) async {
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
            '⚠️ [同步修复] 服务端清理习惯冲突失败 ${candidate.uuid}: ${result['error'] ?? '未知错误'}');
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
          ..['version'] = (serverVersion > currentVersion
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
              'ℹ️ [同步修复] 已清除本地习惯冲突并排队重试 ${candidate.uuid}: ${fallback['error'] ?? '等待下次同步'}');
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
    }));

    final resolvedIds = <String>{};
    for (final result in results) {
      if (!result.resolved) continue;
      if (result.resolvedData != null) {
        if (result.candidate.table == 'habit_goals') {
          final index = goals.indexWhere(
            (goal) => goal.uuid == result.candidate.uuid,
          );
          if (index >= 0) {
            goals[index] = HabitGoal.fromJson(result.resolvedData!);
          }
        } else {
          final index = rules.indexWhere(
            (rule) => rule.uuid == result.candidate.uuid,
          );
          if (index >= 0) {
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
