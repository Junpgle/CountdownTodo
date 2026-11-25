part of 'storage_service.dart';

// ignore_for_file: unused_element, unused_element_parameter, annotate_overrides

class _SyncRunContext {
  _SyncRunContext({
    required this.username,
    required this.syncTodos,
    required this.syncCountdowns,
    required this.forceFullSync,
    required this.uploadAllLocal,
    required this.shouldUploadAllLocal,
    required this.syncScreenTime,
    required this.syncTimeLogs,
    required this.syncPomodoro,
    required this.syncPlanBlocks,
    required this.syncFixedSchedules,
    required this.syncHabits,
    required this.syncFinance,
    required this.financeSyncExplicitlyAuthorized,
    required this.session,
    required this.prefs,
    required this.userId,
    required this.deviceId,
    required this.friendlyName,
    required this.serverKey,
    required this.fixedScheduleServerScope,
    required this.fixedScheduleBootstrapKey,
    required this.fixedScheduleSyncInitialized,
    required this.habitBootstrapKey,
    required this.habitSyncInitialized,
    required this.habitCursorBootstrapKey,
    required this.habitSyncCursorInitialized,
    required this.habitCursorCapabilityKey,
    required this.habitCursorCapabilityKnown,
    required this.habitCursorSupportedByLastServer,
    required this.lastSyncTime,
    required this.habitLastSyncTime,
    required this.financeRequest,
    required this.scopedRefreshDomains,
  });

  final String username;
  final bool syncTodos;
  final bool syncCountdowns;
  final bool forceFullSync;
  final bool uploadAllLocal;
  final bool shouldUploadAllLocal;
  final bool syncScreenTime;
  final bool syncTimeLogs;
  final bool syncPomodoro;
  final bool syncPlanBlocks;
  final bool syncFixedSchedules;
  final bool syncHabits;
  bool syncFinance;
  final bool financeSyncExplicitlyAuthorized;
  final dynamic session;
  final SharedPreferences prefs;
  final int userId;
  final String deviceId;
  final String friendlyName;
  final String serverKey;
  final String fixedScheduleServerScope;
  final String fixedScheduleBootstrapKey;
  final bool fixedScheduleSyncInitialized;
  final String habitBootstrapKey;
  final bool habitSyncInitialized;
  final String habitCursorBootstrapKey;
  final bool habitSyncCursorInitialized;
  final String habitCursorCapabilityKey;
  final bool habitCursorCapabilityKnown;
  final bool habitCursorSupportedByLastServer;
  int lastSyncTime;
  final int habitLastSyncTime;
  final FinanceSyncRequest? financeRequest;
  final Set<DataRefreshDomain> scopedRefreshDomains;

  bool hasChanges = false;
  List<dynamic> financeConflicts = const [];
  List<ConflictInfo> conflicts = [];
  final Set<String> updatedTodoIds = <String>{};
  final Map<String, Map<String, dynamic>> staleHabitConflictSnapshots = {};
  final Set<String> autoResolvedHabitConflictIds = <String>{};

  late Database db;
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

  late List<TodoItem> allLocalTodos;
  late List<TodoGroup> allLocalGroups;
  late List<CountdownItem> allLocalCountdowns;
  late List<TimeLogItem> allLocalTimeLogs;
  late List<TodoPlanBlock> allLocalPlanBlocks;
  late List<FixedScheduleItem> allLocalFixedSchedules;
  late List<HabitGoal> allLocalHabitGoals;
  late List<HabitGoalRuleRevision> allLocalHabitRules;
  late List<HabitCheckIn> allLocalHabitCheckIns;
  late List<HabitSleepCoachingPlan> allLocalHabitSleepCoachingPlans;
  late List<HabitDrinkOption> allLocalHabitDrinkOptions;
  Set<String> conflictedHabitGoalIds = const <String>{};
  Set<String> conflictedHabitRuleIds = const <String>{};
  late Map<String, TodoItem> localTodosById;
  late List<Map<String, dynamic>> pendingOps;
  late List<SyncOplogEntry> requestOplogSnapshot;
  Map<String, dynamic>? screenPayload;

  late Map<String, dynamic> response;
  bool fixedSchedulesSupported = false;
  bool acknowledgeFixedScheduleOps = false;
  bool habitsSupported = false;
  bool sleepCoachingSupported = false;
  bool habitDrinkOptionsSupported = false;
  bool habitSyncCursorSupported = false;
  bool acknowledgeHabitOps = false;
  bool financeSupported = false;
  bool todoSkipStateSupported = false;
  List<dynamic>? joinedTeamUuids;
  Set<String> currentTeams = <String>{};

  Set<String> inFlightTodoMutationUuids = <String>{};
  Set<String> inFlightGroupMutationUuids = <String>{};
  Set<String> inFlightCountdownMutationUuids = <String>{};
  Set<String> inFlightTimeLogMutationUuids = <String>{};
  Set<String> inFlightPlanBlockMutationUuids = <String>{};
  Set<String> inFlightFixedScheduleMutationUuids = <String>{};
  Set<String> inFlightHabitGoalMutationUuids = <String>{};
  Set<String> inFlightHabitRuleMutationUuids = <String>{};
  Set<String> inFlightHabitCheckInMutationUuids = <String>{};
  Set<String> inFlightHabitSleepCoachingMutationUuids = <String>{};
  Set<String> inFlightHabitDrinkOptionMutationUuids = <String>{};

  late List<({Map<String, dynamic> raw, TodoItem item})> remoteTodoEntries;
  late Map<String, TodoItem> beforeRemoteRepair;
  late Map<String, TodoItem> remoteRecurrenceBaselines;
  late Set<String> rejectedMaintenanceIds;
  late Set<String> repairedRemoteTodoIds;
  late Set<String> preMergeConflictIds;
  late Map<String, int> todosIndexMap;
  late Set<String> ignoredScheduleConflictKeys;
  bool pomodoroChanged = false;

  bool isOutsideJoinedTeam(String? teamUuid) {
    return joinedTeamUuids != null &&
        teamUuid != null &&
        teamUuid.isNotEmpty &&
        !currentTeams.contains(teamUuid);
  }
}

mixin _StorageSync on _StorageServiceBase {
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
    bool syncFinance = true,
    bool financeSyncExplicitlyAuthorized = false,
  }) async {
    username = username.trim();
    if (username.isEmpty) {
      return {'success': false, 'hasChanges': false, 'error': '账户未登录，无法同步'};
    }
    if (await AppSettingsStorage.isOfflineModeEnabled()) {
      return {
        'success': false,
        'hasChanges': false,
        'offline': true,
        'error': '离线模式已开启，已跳过服务器同步',
      };
    }
    final session = await UserSessionStorage.captureSession(username);
    if (session == null) {
      return {'success': false, 'hasChanges': false, 'error': '账户已切换，已取消旧账户同步'};
    }

    if (syncFinance &&
        !financeSyncExplicitlyAuthorized &&
        !await AppSettingsStorage.isFinanceCloudSyncEnabled(username)) {
      syncFinance = false;
    }
    final bool shouldUploadAllLocal = uploadAllLocal || forceFullSync;
    // 1. 状态锁：防止重复进入
    if (!syncTodos &&
        !syncCountdowns &&
        !syncTimeLogs &&
        !syncPomodoro &&
        !syncPlanBlocks &&
        !syncFixedSchedules &&
        !syncHabits &&
        !syncFinance &&
        !syncScreenTime) {
      return {'success': false, 'hasChanges': false};
    }
    if (_isSyncing) {
      return {'success': false, 'hasChanges': false, 'error': '同步进行中，请稍后重试'};
    }
    _isSyncing = true;
    FinanceSyncRequest? financeRequest;
    final scopedRefreshDomains = <DataRefreshDomain>{
      if (syncTodos) DataRefreshDomain.todos,
      if (syncTodos) DataRefreshDomain.todoGroups,
      if (syncCountdowns) DataRefreshDomain.countdowns,
      if (syncTimeLogs) DataRefreshDomain.timeLogs,
      if (syncPomodoro) DataRefreshDomain.pomodoro,
      if (syncPlanBlocks) DataRefreshDomain.planBlocks,
      if (syncFixedSchedules) DataRefreshDomain.fixedSchedules,
      if (syncHabits) DataRefreshDomain.habits,
      if (syncFinance) DataRefreshDomain.finance,
    };

    try {
      await UserSessionStorage.ensureCurrentSession(session);
      final prefs = await SharedPreferences.getInstance();
      final userId = session.userId;

      // 2. 环境信息准备
      final String deviceId = await UserSessionStorage.getDeviceIdForUser(
        username,
      );
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
      final habitCursorBootstrapKey =
          'habit_sync_cursor_v1_${fixedScheduleServerScope}_$username';
      final habitSyncCursorInitialized =
          prefs.getBool(habitCursorBootstrapKey) == true;
      final habitCursorCapabilityKey =
          'habit_sync_cursor_capability_v1_${fixedScheduleServerScope}_$username';
      final habitCursorCapabilityKnown = prefs.containsKey(
        habitCursorCapabilityKey,
      );
      final habitCursorSupportedByLastServer =
          prefs.getBool(habitCursorCapabilityKey) == true;
      int lastSyncTime = forceFullSync
          ? 0
          : (prefs.getInt('last_sync_time_${serverKey}_$username') ?? 0);
      int habitLastSyncTime = forceFullSync
          ? 0
          : (!habitSyncCursorInitialized
                ? 0
                : (!habitCursorCapabilityKnown ||
                          habitCursorSupportedByLastServer
                      ? (prefs.getInt(
                              'habit_last_sync_time_${serverKey}_$username',
                            ) ??
                            0)
                      : lastSyncTime));
      _lastSyncRequestAt = DateTime.now().millisecondsSinceEpoch;

      if (syncFinance) {
        financeRequest = await FinanceSyncService.prepare(
          username: username,
          forceFullSync: forceFullSync,
        );
      }

      final ctx = _SyncRunContext(
        username: username,
        syncTodos: syncTodos,
        syncCountdowns: syncCountdowns,
        forceFullSync: forceFullSync,
        uploadAllLocal: uploadAllLocal,
        shouldUploadAllLocal: shouldUploadAllLocal,
        syncScreenTime: syncScreenTime,
        syncTimeLogs: syncTimeLogs,
        syncPomodoro: syncPomodoro,
        syncPlanBlocks: syncPlanBlocks,
        syncFixedSchedules: syncFixedSchedules,
        syncHabits: syncHabits,
        syncFinance: syncFinance,
        financeSyncExplicitlyAuthorized: financeSyncExplicitlyAuthorized,
        session: session,
        prefs: prefs,
        userId: userId,
        deviceId: deviceId,
        friendlyName: friendlyName,
        serverKey: serverKey,
        fixedScheduleServerScope: fixedScheduleServerScope,
        fixedScheduleBootstrapKey: fixedScheduleBootstrapKey,
        fixedScheduleSyncInitialized: fixedScheduleSyncInitialized,
        habitBootstrapKey: habitBootstrapKey,
        habitSyncInitialized: habitSyncInitialized,
        habitCursorBootstrapKey: habitCursorBootstrapKey,
        habitSyncCursorInitialized: habitSyncCursorInitialized,
        habitCursorCapabilityKey: habitCursorCapabilityKey,
        habitCursorCapabilityKnown: habitCursorCapabilityKnown,
        habitCursorSupportedByLastServer: habitCursorSupportedByLastServer,
        lastSyncTime: lastSyncTime,
        habitLastSyncTime: habitLastSyncTime,
        financeRequest: financeRequest,
        scopedRefreshDomains: scopedRefreshDomains,
      );

      await _prepareSyncUploadPayload(ctx);
      await _executeSyncNetworkRound(ctx);
      await _mergeServerSyncResponse(ctx);
      await _persistSyncMergeResults(ctx);
      await _finalizeSyncWatermarksAndNotify(ctx);

      await UserSessionStorage.ensureCurrentSession(session);
      return {
        'success': true,
        'hasChanges': ctx.hasChanges,
        'conflicts': ctx.conflicts,
        'financeConflicts': ctx.financeConflicts,
        'updatedTodoIds': ctx.updatedTodoIds.toList(),
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
}

final class _SyncListIndex<T> {
  static const int _linearSearchLimit = 64;

  _SyncListIndex(this._items, this._idOf);

  final List<T> _items;
  final String Function(T) _idOf;
  Map<String, int>? _firstIndexById;
  var _largeListLinearSearches = 0;

  int? indexOf(String id) {
    if (_items.length <= _linearSearchLimit) return _linearIndexOf(id);
    if (_firstIndexById == null && _largeListLinearSearches == 0) {
      _largeListLinearSearches++;
      return _linearIndexOf(id);
    }
    final indexes = _firstIndexById ??= _buildFirstIndex();
    return indexes[id];
  }

  int? _linearIndexOf(String id) {
    final index = _items.indexWhere((item) => _idOf(item) == id);
    return index < 0 ? null : index;
  }

  Map<String, int> _buildFirstIndex() {
    final indexes = <String, int>{};
    for (var index = 0; index < _items.length; index++) {
      indexes.putIfAbsent(_idOf(_items[index]), () => index);
    }
    return indexes;
  }
}

void _overlayInFlightLocalMutations<T>(
  List<T> target,
  List<T> latest,
  Set<String> inFlightUuids,
  String Function(T) idOf,
) {
  if (inFlightUuids.isEmpty || latest.isEmpty) return;
  final latestById = <String, T>{
    for (final item in latest)
      if (inFlightUuids.contains(idOf(item))) idOf(item): item,
  };
  if (latestById.isEmpty) return;
  final seen = <String>{};
  for (var i = 0; i < target.length; i++) {
    final id = idOf(target[i]);
    final replacement = latestById[id];
    if (replacement != null) {
      target[i] = replacement;
      seen.add(id);
    }
  }
  for (final entry in latestById.entries) {
    if (!seen.contains(entry.key)) {
      target.add(entry.value);
    }
  }
}
