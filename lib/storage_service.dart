import 'dart:async';
import 'dart:convert';
import 'package:countdown_todo/services/pomodoro_sync_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import 'models.dart';

import 'services/api_service.dart';
import 'services/band_sync_service.dart';
import 'services/pomodoro_service.dart';
import 'services/database_helper.dart'; // 🚀 引入 Uni-Sync 新引擎
import 'services/sync_capability_service.dart';
import 'services/sync_oplog_policy.dart';
import 'services/todo_lww_service.dart';
import 'services/storage/app_settings_storage.dart';
import 'services/storage/countdown_storage.dart';
import 'services/storage/habit_storage.dart';
import 'services/storage/pomodoro_storage.dart';
import 'services/storage/storage_conflict_cleanup.dart';
import 'services/storage/storage_key_scope.dart';
import 'services/storage/user_session_storage.dart';
import 'utils/json_value_parser.dart';
import 'features/habits/models/habit_checkin.dart';
import 'features/habits/models/habit_goal.dart';
import 'features/habits/models/habit_goal_rule.dart';
import 'features/habits/models/habit_sleep_coaching_plan.dart';
import 'features/habits/services/habit_sync_conflict_service.dart';
import 'features/finance/services/finance_sync_service.dart';

part 'storage_service_fixed.dart';
part 'storage_service_core.dart';
part 'storage_service_todos.dart';
part 'storage_service_sync.dart';
part 'storage_service_conflict.dart';
part 'storage_service_settings.dart';
part 'storage_service_contract.dart';

enum DataRefreshDomain {
  todos,
  todoGroups,
  countdowns,
  mathStats,
  courses,
  planBlocks,
  fixedSchedules,
  timeLogs,
  pomodoro,
  habits,
  finance,
  teams,
  all,
}

@immutable
class DataRefreshSignal {
  const DataRefreshSignal({required this.revision, required this.domains});

  const DataRefreshSignal.initial()
      : revision = 0,
        domains = const {DataRefreshDomain.all};

  final int revision;
  final Set<DataRefreshDomain> domains;

  bool affects(DataRefreshDomain domain) =>
      domains.contains(DataRefreshDomain.all) || domains.contains(domain);
}

class StorageService {
  static final _storage = _StorageServiceImpl();

  static Set<String> get recentlyResolvedUuids =>
      _storage.recentlyResolvedUuids;

  static Map<String, DateTime> get recentlyResolvedTimes =>
      _storage.recentlyResolvedTimes;

  static const String keyUsers = _storageService_keyUsers;

  static const String keyLeaderboard = _storageService_keyLeaderboard;

  static const String keySettings = _storageService_keySettings;

  static const String keyCurrentUser = _storageService_keyCurrentUser;

  static const String keyTodos = _storageService_keyTodos;

  static const String keyTodoGroups = _storageService_keyTodoGroups;

  static const String keyCountdowns = _storageService_keyCountdowns;

  static const String keyScreenTimeCache = _storageService_keyScreenTimeCache;

  static const String keyLastScreenTimeSync =
      _storageService_keyLastScreenTimeSync;

  static const String keyScreenTimeHistory =
      _storageService_keyScreenTimeHistory;

  static const String keyAppMappings = _storageService_keyAppMappings;

  static const String keyLastMappingsSync = _storageService_keyLastMappingsSync;

  static const String keyAuthToken = _storageService_keyAuthToken;

  static const String keyDeviceId = _storageService_keyDeviceId;

  static const String keySyncInterval = _storageService_keySyncInterval;

  static const String keyThemeMode = _storageService_keyThemeMode;

  static const String keyThemeColorMode = _storageService_keyThemeColorMode;

  static const String keyCustomThemeColor = _storageService_keyCustomThemeColor;

  static const String keyLastAutoSync = _storageService_keyLastAutoSync;

  static const String keySemesterProgressEnabled =
      _storageService_keySemesterProgressEnabled;

  static const String keySemesterStart = _storageService_keySemesterStart;

  static const String keySemesterEnd = _storageService_keySemesterEnd;

  static const String keySemesters = _storageService_keySemesters;

  static const String keyActiveSemester = _storageService_keyActiveSemester;

  static const String keyTimeLogs = _storageService_keyTimeLogs;

  static const String keyIgnoredScheduleConflicts =
      _storageService_keyIgnoredScheduleConflicts;

  static const String keyConflictDetectionEnabled =
      _storageService_keyConflictDetectionEnabled;

  static const String keyServerChoice = _storageService_keyServerChoice;

  static const String keySystemStartupEnabled =
      _storageService_keySystemStartupEnabled;

  static const String keyPrivacyAgreed = _storageService_keyPrivacyAgreed;

  static const String keyPrivacyDate = _storageService_keyPrivacyDate;

  static const String keyPrivacyCachedVersion =
      _storageService_keyPrivacyCachedVersion;

  static const String keyPrivacyCacheTime = _storageService_keyPrivacyCacheTime;

  static const String privacyRawUrl = _storageService_privacyRawUrl;

  static const Duration privacyCacheDuration =
      _storageService_privacyCacheDuration;

  static const String keyLocalScreenTime = _storageService_keyLocalScreenTime;

  static const String keyLlmRetryCount = _storageService_keyLlmRetryCount;

  static const String keyPendingTodoConfirm =
      _storageService_keyPendingTodoConfirm;

  static const String keyWallpaperProvider =
      _storageService_keyWallpaperProvider;

  static const String keyWallpaperImageFormat =
      _storageService_keyWallpaperImageFormat;

  static const String keyWallpaperIndex = _storageService_keyWallpaperIndex;

  static const String keyWallpaperMkt = _storageService_keyWallpaperMkt;

  static const String keyWallpaperResolution =
      _storageService_keyWallpaperResolution;

  static const String keyWallpaperCacheCleanupTime =
      _storageService_keyWallpaperCacheCleanupTime;

  static const String keyWallpaperCustomPath =
      _storageService_keyWallpaperCustomPath;

  static const String keyNotifyLiveEnabled =
      _storageService_keyNotifyLiveEnabled;

  static const String keyNotifyNormalEnabled =
      _storageService_keyNotifyNormalEnabled;

  static const String keyNotifyCourseEnabled =
      _storageService_keyNotifyCourseEnabled;

  static const String keyNotifyQuizEnabled =
      _storageService_keyNotifyQuizEnabled;

  static const String keyNotifyTodoSummaryEnabled =
      _storageService_keyNotifyTodoSummaryEnabled;

  static const String keyNotifyAppUpdatesEnabled =
      _storageService_keyNotifyAppUpdatesEnabled;

  static const String keyTodoFoldersInline =
      _storageService_keyTodoFoldersInline;

  static const String keyTodoFolderDisplayMode =
      _storageService_keyTodoFolderDisplayMode;

  static const String keyNotifySpecialTodoEnabled =
      _storageService_keyNotifySpecialTodoEnabled;

  static const String keyNotifyPomodoroEnabled =
      _storageService_keyNotifyPomodoroEnabled;

  static const String keyNotifyTodoRecognizeEnabled =
      _storageService_keyNotifyTodoRecognizeEnabled;

  static const String keyNotifyPomodoroEndEnabled =
      _storageService_keyNotifyPomodoroEndEnabled;

  static const String keyNotifyTodoLiveEnabled =
      _storageService_keyNotifyTodoLiveEnabled;

  static const String keyNotifyReminderEnabled =
      _storageService_keyNotifyReminderEnabled;

  static const String keyCourseReminderMinutes =
      _storageService_keyCourseReminderMinutes;

  static const String keyLastCourseImportUrl =
      _storageService_keyLastCourseImportUrl;

  static const String keyCategoryReminderMinutes =
      _storageService_keyCategoryReminderMinutes;

  static const String keyWindowsScheduledReminders =
      _storageService_keyWindowsScheduledReminders;

  static ValueNotifier<String> get themeNotifier => _storage.themeNotifier;
  static set themeNotifier(ValueNotifier<String> value) =>
      _storage.themeNotifier = value;

  static ValueNotifier<String> get themeColorModeNotifier =>
      _storage.themeColorModeNotifier;
  static set themeColorModeNotifier(ValueNotifier<String> value) =>
      _storage.themeColorModeNotifier = value;

  static ValueNotifier<Color?> get customThemeColorNotifier =>
      _storage.customThemeColorNotifier;
  static set customThemeColorNotifier(ValueNotifier<Color?> value) =>
      _storage.customThemeColorNotifier = value;

  static ValueNotifier<Color?> get appWallpaperColorNotifier =>
      _storage.appWallpaperColorNotifier;
  static set appWallpaperColorNotifier(ValueNotifier<Color?> value) =>
      _storage.appWallpaperColorNotifier = value;

  static ValueNotifier<Map<String, dynamic>> get conflictScanNotifier =>
      _storage.conflictScanNotifier;

  static ValueNotifier<int> get dataRefreshNotifier =>
      _storage.dataRefreshNotifier;

  static ValueNotifier<int> get screenTimeRefreshNotifier =>
      _storage.screenTimeRefreshNotifier;

  static ValueNotifier<DataRefreshSignal> get scopedDataRefreshNotifier =>
      _storage.scopedDataRefreshNotifier;

  static ValueNotifier<int> get wallpaperRefreshNotifier =>
      _storage.wallpaperRefreshNotifier;

  static void Function()? get onDataChangedHook => _storage.onDataChangedHook;
  static set onDataChangedHook(void Function()? value) =>
      _storage.onDataChangedHook = value;

  static bool isRecentlyResolved(String uuid) =>
      _storage.isRecentlyResolved(uuid);

  static Future<SharedPreferences> get prefs => _storage.prefs;

  static Future<void> saveFixedSchedules(
    String username,
    List<FixedScheduleItem> items, {
    bool sync = true,
    bool isSyncSource = false,
  }) =>
      _storage.saveFixedSchedules(username, items,
          sync: sync, isSyncSource: isSyncSource);

  static Future<List<FixedScheduleItem>> getFixedSchedules(
    String username, {
    bool includeDeleted = false,
  }) =>
      _storage.getFixedSchedules(username, includeDeleted: includeDeleted);

  static Future<List<FixedScheduleItem>> getFixedSchedulesByDay(
    String username,
    DateTime day,
  ) =>
      _storage.getFixedSchedulesByDay(username, day);

  static Future<void> deleteFixedSchedule(
    String username,
    FixedScheduleItem item,
  ) =>
      _storage.deleteFixedSchedule(username, item);

  static Future<List<HabitGoal>> getHabitGoals() => _storage.getHabitGoals();

  static Future<void> saveHabitGoals(List<HabitGoal> items) =>
      _storage.saveHabitGoals(items);

  static Future<List<HabitGoalRuleRevision>> getHabitRules({
    String? habitUuid,
  }) =>
      _storage.getHabitRules(habitUuid: habitUuid);

  static Future<void> saveHabitRules(
    List<HabitGoalRuleRevision> items,
  ) =>
      _storage.saveHabitRules(items);

  static Future<List<HabitCheckIn>> getHabitCheckIns({
    String? habitUuid,
    String? fromDate,
    String? toDate,
  }) =>
      _storage.getHabitCheckIns(
          habitUuid: habitUuid, fromDate: fromDate, toDate: toDate);

  static Future<void> saveHabitCheckIns(List<HabitCheckIn> items) =>
      _storage.saveHabitCheckIns(items);

  static Future<void> savePlanBlocks(String username, List<TodoPlanBlock> items,
          {bool sync = true, bool isSyncSource = false}) =>
      _storage.savePlanBlocks(username, items,
          sync: sync, isSyncSource: isSyncSource);

  static Future<List<TodoPlanBlock>> getPlanBlocks(String username,
          {bool includeDeleted = false}) =>
      _storage.getPlanBlocks(username, includeDeleted: includeDeleted);

  static Future<void> deletePlanBlockGlobally(
          String username, String idToDelete) =>
      _storage.deletePlanBlockGlobally(username, idToDelete);

  static Future<List<TodoPlanBlock>> getPlanBlocksByTodo(
          String username, String todoId) =>
      _storage.getPlanBlocksByTodo(username, todoId);

  static Future<List<TodoPlanBlock>> getPlanBlocksByDay(
          String username, DateTime day) =>
      _storage.getPlanBlocksByDay(username, day);

  static void triggerRefresh([
    Set<DataRefreshDomain> domains = const {DataRefreshDomain.all},
  ]) =>
      _storage.triggerRefresh(domains);

  static void triggerWallpaperRefresh() => _storage.triggerWallpaperRefresh();

  static void setForceFlushProtectedUuids(Set<String> uuids) =>
      _storage.setForceFlushProtectedUuids(uuids);

  static void requestSync(String username) => _storage.requestSync(username);

  static Future<void> ignoreRemoteItem({
    required String table,
    required String uuid,
    String? teamUuid,
  }) =>
      _storage.ignoreRemoteItem(table: table, uuid: uuid, teamUuid: teamUuid);

  static Future<void> unignoreRemoteItem(String uuid) =>
      _storage.unignoreRemoteItem(uuid);

  static Future<bool> isItemIgnored(String uuid) =>
      _storage.isItemIgnored(uuid);

  static Future<String> getDeviceFriendlyName() =>
      _storage.getDeviceFriendlyName();

  static Future<String?> getCurrentUsername() => _storage.getCurrentUsername();

  static Future<bool> rollbackLocalItem(
          String table, int logId, String username) =>
      _storage.rollbackLocalItem(table, logId, username);

  static Future<String> getDeviceId() => _storage.getDeviceId();

  static Future<void> initTheme() => _storage.initTheme();

  static Future<bool> register(String username, String password) =>
      _storage.register(username, password);

  static Future<bool> login(String username, String password) =>
      _storage.login(username, password);

  static Future<void> saveLoginSession(String username, {String? token}) =>
      _storage.saveLoginSession(username, token: token);

  static Future<String?> getLoginSession() => _storage.getLoginSession();

  static Future<String?> getAuthToken() => _storage.restoreAuthToken();

  static Future<void> clearLoginSession() => _storage.clearLoginSession();

  static Future<void> saveSettings(Map<String, dynamic> settings) =>
      _storage.saveSettings(settings);

  static Future<Map<String, dynamic>> getSettings() => _storage.getSettings();

  static Future<void> saveWindowsScheduledReminders(
          List<Map<String, dynamic>> reminders) =>
      _storage.saveWindowsScheduledReminders(reminders);

  static Future<List<Map<String, dynamic>>> getWindowsScheduledReminders() =>
      _storage.getWindowsScheduledReminders();

  static Future<void> savePomodoroTags(
          String username, List<Map<String, dynamic>> tags) =>
      _storage.savePomodoroTags(username, tags);

  static Future<void> saveHistory(
          String username, int score, int duration, String details) =>
      _storage.saveHistory(username, score, duration, details);

  static Future<List<String>> getHistory(String username) =>
      _storage.getHistory(username);

  static Future<Map<String, dynamic>> getMathStats(String username) =>
      _storage.getMathStats(username);

  static Future<void> updateLeaderboard(
          String username, int score, int duration) =>
      _storage.updateLeaderboard(username, score, duration);

  static Future<List<Map<String, dynamic>>> getLeaderboard() =>
      _storage.getLeaderboard();

  static Future<void> saveCountdowns(String username, List<CountdownItem> items,
          {bool sync = true, bool isSyncSource = false}) =>
      _storage.saveCountdowns(username, items,
          sync: sync, isSyncSource: isSyncSource);

  static Future<List<CountdownItem>> getCountdowns(String username,
          {bool includeDeleted = false}) =>
      _storage.getCountdowns(username, includeDeleted: includeDeleted);

  static Future<void> deleteCountdownGlobally(
          String username, String idToDelete) =>
      _storage.deleteCountdownGlobally(username, idToDelete);

  static Future<void> saveTodos(String username, List<TodoItem> items,
          {bool sync = true,
          bool isSyncSource = false,
          bool recomputeScheduleConflicts = true}) =>
      _storage.saveTodos(username, items,
          sync: sync,
          isSyncSource: isSyncSource,
          recomputeScheduleConflicts: recomputeScheduleConflicts);

  static Future<Map<String, int>> scanAllTodoConflicts(String username) =>
      _storage.scanAllTodoConflicts(username);

  static Future<void> clearLocalTodoScheduleConflicts(String username) =>
      _storage.clearLocalTodoScheduleConflicts(username);

  static Future<void> ignoreLocalScheduleConflict(
          String username, TodoItem item) =>
      _storage.ignoreLocalScheduleConflict(username, item);

  static Future<void> updateSingleTodo(String username, TodoItem item,
          {bool sync = true}) =>
      _storage.updateSingleTodo(username, item, sync: sync);

  static Future<void> permanentlyDeleteTodo(String username, String uuid) =>
      _storage.permanentlyDeleteTodo(username, uuid);

  static Future<void> clearTodoRecycleBin(String username) =>
      _storage.clearTodoRecycleBin(username);

  static Future<int> clearHistoricalTodos(String username) =>
      _storage.clearHistoricalTodos(username);

  static Future<void> permanentlyDeleteCountdown(
          String username, String uuid) =>
      _storage.permanentlyDeleteCountdown(username, uuid);

  static Future<List<TodoItem>> getTodos(String username,
          {bool includeDeleted = false, int? limit}) =>
      _storage.getTodos(username, includeDeleted: includeDeleted, limit: limit);

  static Future<void> clearTeamItems(String teamUuid) =>
      _storage.clearTeamItems(teamUuid);

  static List<int> recurrenceRollOffsetsForTest(
    TodoItem todo,
    DateTime baseDay,
    DateTime todayDay,
  ) =>
      _storage.recurrenceRollOffsetsForTest(todo, baseDay, todayDay);

  static List<TodoItem> futureRecurrenceOccurrencesForTest(
    TodoItem source,
    List<TodoItem> existing,
  ) =>
      _storage.futureRecurrenceOccurrencesForTest(source, existing);

  static List<TodoItem> repairMissingPastRecurrenceOccurrencesForTest(
    TodoItem active,
    List<TodoItem> existing,
  ) =>
      _storage.repairMissingPastRecurrenceOccurrencesForTest(active, existing);

  static String recurrenceOccurrenceIdForTest(
    String seriesId,
    int startMs,
  ) =>
      _storage.recurrenceOccurrenceIdForTest(seriesId, startMs);

  static bool deduplicatePersistedRecurrenceOccurrencesForTest(
    List<TodoItem> todos,
  ) =>
      _storage.deduplicatePersistedRecurrenceOccurrencesForTest(todos);

  static bool pruneRecurrenceOccurrencesAfterEndDateForTest(
    List<TodoItem> todos, {
    required String seriesId,
    required DateTime recurrenceEndDate,
  }) =>
      _storage.pruneRecurrenceOccurrencesAfterEndDateForTest(
        todos,
        seriesId: seriesId,
        recurrenceEndDate: recurrenceEndDate,
      );

  static Set<String> pruneRecurrenceOccurrencesAfterEndDatesForTest(
    List<TodoItem> todos,
  ) =>
      _storage.pruneRecurrenceOccurrencesAfterEndDatesForTest(todos);

  static Future<int> mergeRecurrenceSeries(
    String username, {
    required String targetSeriesId,
    required Set<String> seriesIds,
  }) =>
      _storage.mergeRecurrenceSeries(username,
          targetSeriesId: targetSeriesId, seriesIds: seriesIds);

  static Set<String> mergeRecurrenceSeriesForTest(
    List<TodoItem> todos, {
    required String targetSeriesId,
    required Set<String> seriesIds,
  }) =>
      _storage.mergeRecurrenceSeriesForTest(todos,
          targetSeriesId: targetSeriesId, seriesIds: seriesIds);

  static Future<bool> deleteTodoGlobally(String username, String idToDelete) =>
      _storage.deleteTodoGlobally(username, idToDelete);

  static Future<void> saveTodoGroups(String username, List<TodoGroup> items,
          {bool sync = true, bool isSyncSource = false}) =>
      _storage.saveTodoGroups(username, items,
          sync: sync, isSyncSource: isSyncSource);

  static Future<List<TodoGroup>> getTodoGroups(String username,
          {bool includeDeleted = false}) =>
      _storage.getTodoGroups(username, includeDeleted: includeDeleted);

  static Future<void> deleteTodoGroupGlobally(
          String username, String idToDelete) =>
      _storage.deleteTodoGroupGlobally(username, idToDelete);

  static Future<void> saveTimeLogs(String username, List<TimeLogItem> items,
          {bool sync = true}) =>
      _storage.saveTimeLogs(username, items, sync: sync);

  static Future<List<TimeLogItem>> getTimeLogs(String username, {int? limit}) =>
      _storage.getTimeLogs(username, limit: limit);

  static Future<bool> deleteTimeLogGlobally(
          String username, String idToDelete) =>
      _storage.deleteTimeLogGlobally(username, idToDelete);

  static Future<void> saveLocalScreenTime(Map<dynamic, dynamic> stats) =>
      _storage.saveLocalScreenTime(stats);

  static Future<Map<String, dynamic>?> getLocalScreenTimePackage() =>
      _storage.getLocalScreenTimePackage();

  static Future<Map<String, dynamic>> getLocalScreenTimeMap() =>
      _storage.getLocalScreenTimeMap();

  static Future<List<dynamic>> getLocalScreenTime() =>
      _storage.getLocalScreenTime();

  static Future<void> saveScreenTimeCache(List<dynamic> stats) =>
      _storage.saveScreenTimeCache(stats);

  static Future<void> saveScreenTimeHistoryToSql(
          String date, List<dynamic> stats) =>
      _storage.saveScreenTimeHistoryToSql(date, stats);

  static Future<List<dynamic>> getScreenTimeCache() =>
      _storage.getScreenTimeCache();

  static Future<Map<String, List<dynamic>>> getScreenTimeHistory() =>
      _storage.getScreenTimeHistory();

  static Future<void> updateLastScreenTimeSync() =>
      _storage.updateLastScreenTimeSync();

  static Future<DateTime?> getLastScreenTimeSync() =>
      _storage.getLastScreenTimeSync();

  static Future<void> syncAppMappings() => _storage.syncAppMappings();

  static Future<Map<String, String>> getAppMappings() =>
      _storage.getAppMappings();

  static Future<void> resetSyncTime(String username) =>
      _storage.resetSyncTime(username);

  static Future<Map<String, dynamic>> syncData(
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
  }) =>
      _storage.syncData(username,
          syncTodos: syncTodos,
          syncCountdowns: syncCountdowns,
          forceFullSync: forceFullSync,
          uploadAllLocal: uploadAllLocal,
          context: context,
          syncScreenTime: syncScreenTime,
          syncTimeLogs: syncTimeLogs,
          syncPomodoro: syncPomodoro,
          syncPlanBlocks: syncPlanBlocks,
          syncFixedSchedules: syncFixedSchedules,
          syncHabits: syncHabits,
          syncFinance: syncFinance);

  static bool recomputeLocalTodoScheduleConflictsForTest(
    List<TodoItem> todos,
  ) =>
      _storage.recomputeLocalTodoScheduleConflictsForTest(todos);

  static List<TodoItem> clearResolvedRecurrenceMigrationConflictsForTest(
    List<TodoItem> todos,
  ) =>
      _storage.clearResolvedRecurrenceMigrationConflictsForTest(todos);

  static Set<String> repairMissingRemoteRecurrenceSeriesIdsForTest(
    List<TodoItem> incoming,
    List<TodoItem> local,
  ) =>
      _storage.repairMissingRemoteRecurrenceSeriesIdsForTest(incoming, local);

  static Set<String> repairLocalRecurrenceSeriesAliasesFromHistoryForTest(
    List<TodoItem> todos,
    Map<String, List<String>> historicalSeriesByTodoId,
  ) =>
      _storage.repairLocalRecurrenceSeriesAliasesFromHistoryForTest(
          todos, historicalSeriesByTodoId);

  static Future<bool> syncScreenTimeAlone(String username, String deviceName) =>
      _storage.syncScreenTimeAlone(username, deviceName);

  static Future<void> saveAppSetting(String key, dynamic value) =>
      _storage.saveAppSetting(key, value);

  static Future<int> getSyncInterval() => _storage.getSyncInterval();

  static Future<bool> getConflictDetectionEnabled() =>
      _storage.getConflictDetectionEnabled();

  static Future<String> getThemeMode() => _storage.getThemeMode();

  static Future<void> setThemeColorMode(String mode) =>
      _storage.setThemeColorMode(mode);

  static Future<void> setCustomThemeColor(Color color) =>
      _storage.setCustomThemeColor(color);

  static void setAppWallpaperColor(Color? color) =>
      _storage.setAppWallpaperColor(color);

  static Future<void> saveServerChoice(String choice) =>
      _storage.saveServerChoice(choice);

  static Future<String> getServerChoice() => _storage.getServerChoice();

  static Future<void> saveHomeTextConfig(Map<String, dynamic> config) =>
      _storage.saveHomeTextConfig(config);

  static Future<Map<String, dynamic>> getHomeTextConfig() =>
      _storage.getHomeTextConfig();

  static Future<bool> getSemesterEnabled() => _storage.getSemesterEnabled();

  static Future<DateTime?> getSemesterStart() => _storage.getSemesterStart();

  static Future<DateTime?> getSemesterEnd() => _storage.getSemesterEnd();

  static Future<List<SemesterInfo>> getSemesters() => _storage.getSemesters();

  static Future<void> saveSemesters(List<SemesterInfo> semesters) =>
      _storage.saveSemesters(semesters);

  static Future<String> getActiveSemesterId() => _storage.getActiveSemesterId();

  static Future<void> setActiveSemesterId(String semesterId) =>
      _storage.setActiveSemesterId(semesterId);

  static Future<DateTime?> getSemesterStartById(String semesterId) =>
      _storage.getSemesterStartById(semesterId);

  static Future<SemesterInfo?> getSemesterByDate(DateTime date) =>
      _storage.getSemesterByDate(date);

  static Future<void> updateLastAutoSyncTime(String username) =>
      _storage.updateLastAutoSyncTime(username);

  static Future<DateTime?> getLastAutoSyncTime(String username) =>
      _storage.getLastAutoSyncTime(username);

  static Future<void> saveIslandBounds(
          String islandId, Map<String, dynamic> bounds) =>
      _storage.saveIslandBounds(islandId, bounds);

  static Future<Map<String, dynamic>?> getIslandBounds(String islandId) =>
      _storage.getIslandBounds(islandId);

  static Future<int> getLLMRetryCount() => _storage.getLLMRetryCount();

  static Future<void> setLLMRetryCount(int count) =>
      _storage.setLLMRetryCount(count);

  static Future<void> savePendingTodoConfirm({
    required String imagePath,
    List<Map<String, dynamic>> results = const [],
    List<Map<String, dynamic>> financeResults = const [],
    String status = 'success',
    String? compressedPath,
    String? sourceKey,
    String? processingSessionId,
    String? recognitionChatSessionId,
    String? recognitionChatMessageId,
    int currentAttempt = 1,
    int maxAttempts = 1,
    String? errorMsg,
  }) =>
      _storage.savePendingTodoConfirm(
          imagePath: imagePath,
          results: results,
          financeResults: financeResults,
          status: status,
          compressedPath: compressedPath,
          sourceKey: sourceKey,
          processingSessionId: processingSessionId,
          recognitionChatSessionId: recognitionChatSessionId,
          recognitionChatMessageId: recognitionChatMessageId,
          currentAttempt: currentAttempt,
          maxAttempts: maxAttempts,
          errorMsg: errorMsg);

  static Future<void> updatePendingTodoConfirmStatus({
    required String status,
    int? currentAttempt,
    int? maxAttempts,
    String? errorMsg,
    List<Map<String, dynamic>>? results,
    List<Map<String, dynamic>>? financeResults,
    String? processingSessionId,
    String? recognitionChatSessionId,
    String? recognitionChatMessageId,
  }) =>
      _storage.updatePendingTodoConfirmStatus(
          status: status,
          currentAttempt: currentAttempt,
          maxAttempts: maxAttempts,
          errorMsg: errorMsg,
          results: results,
          financeResults: financeResults,
          processingSessionId: processingSessionId,
          recognitionChatSessionId: recognitionChatSessionId,
          recognitionChatMessageId: recognitionChatMessageId);

  static Future<Map<String, dynamic>?> getPendingTodoConfirm() =>
      _storage.getPendingTodoConfirm();

  static Future<void> clearPendingTodoConfirm() =>
      _storage.clearPendingTodoConfirm();

  static Future<bool> isLiveActivityNotificationEnabled() =>
      _storage.isLiveActivityNotificationEnabled();

  static Future<void> setLiveActivityNotificationEnabled(bool enabled) =>
      _storage.setLiveActivityNotificationEnabled(enabled);

  static Future<bool> isNormalNotificationEnabled() =>
      _storage.isNormalNotificationEnabled();

  static Future<void> setNormalNotificationEnabled(bool enabled) =>
      _storage.setNormalNotificationEnabled(enabled);

  static Future<bool> isCourseNotificationEnabled() =>
      _storage.isCourseNotificationEnabled();

  static Future<void> setCourseNotificationEnabled(bool enabled) =>
      _storage.setCourseNotificationEnabled(enabled);

  static Future<bool> isQuizNotificationEnabled() =>
      _storage.isQuizNotificationEnabled();

  static Future<void> setQuizNotificationEnabled(bool enabled) =>
      _storage.setQuizNotificationEnabled(enabled);

  static Future<bool> isTodoSummaryNotificationEnabled() =>
      _storage.isTodoSummaryNotificationEnabled();

  static Future<void> setTodoSummaryNotificationEnabled(bool enabled) =>
      _storage.setTodoSummaryNotificationEnabled(enabled);

  static Future<bool> isSpecialTodoNotificationEnabled() =>
      _storage.isSpecialTodoNotificationEnabled();

  static Future<void> setSpecialTodoNotificationEnabled(bool enabled) =>
      _storage.setSpecialTodoNotificationEnabled(enabled);

  static Future<bool> isPomodoroNotificationEnabled() =>
      _storage.isPomodoroNotificationEnabled();

  static Future<void> setPomodoroNotificationEnabled(bool enabled) =>
      _storage.setPomodoroNotificationEnabled(enabled);

  static Future<bool> isTodoRecognizeNotificationEnabled() =>
      _storage.isTodoRecognizeNotificationEnabled();

  static Future<void> setTodoRecognizeNotificationEnabled(bool enabled) =>
      _storage.setTodoRecognizeNotificationEnabled(enabled);

  static Future<bool> isTodoLiveNotificationEnabled() =>
      _storage.isTodoLiveNotificationEnabled();

  static Future<void> setTodoLiveNotificationEnabled(bool enabled) =>
      _storage.setTodoLiveNotificationEnabled(enabled);

  static Future<bool> isPomodoroEndNotificationEnabled() =>
      _storage.isPomodoroEndNotificationEnabled();

  static Future<void> setPomodoroEndNotificationEnabled(bool enabled) =>
      _storage.setPomodoroEndNotificationEnabled(enabled);

  static Future<bool> isReminderNotificationEnabled() =>
      _storage.isReminderNotificationEnabled();

  static Future<void> setReminderNotificationEnabled(bool enabled) =>
      _storage.setReminderNotificationEnabled(enabled);

  static Future<int> getCourseReminderMinutes() =>
      _storage.getCourseReminderMinutes();

  static Future<void> setCourseReminderMinutes(int minutes) =>
      _storage.setCourseReminderMinutes(minutes);

  static Future<bool> isPrivacyPolicyAgreed() =>
      _storage.isPrivacyPolicyAgreed();

  static Future<void> setPrivacyPolicyAgreed(bool agreed, {String? date}) =>
      _storage.setPrivacyPolicyAgreed(agreed, date: date);

  static Future<bool> isPrivacyPolicyUpToDate() =>
      _storage.isPrivacyPolicyUpToDate();

  static Future<void> withdrawPrivacyAgreement() =>
      _storage.withdrawPrivacyAgreement();

  static void dispose() => _storage.dispose();

  static Future<String> getWallpaperProvider() =>
      _storage.getWallpaperProvider();

  static Future<void> saveWallpaperProvider(String provider) =>
      _storage.saveWallpaperProvider(provider);

  static Future<String> getWallpaperImageFormat() =>
      _storage.getWallpaperImageFormat();

  static Future<void> saveWallpaperImageFormat(String format) =>
      _storage.saveWallpaperImageFormat(format);

  static Future<int> getWallpaperIndex() => _storage.getWallpaperIndex();

  static Future<void> saveWallpaperIndex(int index) =>
      _storage.saveWallpaperIndex(index);

  static Future<String> getWallpaperMkt() => _storage.getWallpaperMkt();

  static Future<void> saveWallpaperMkt(String mkt) =>
      _storage.saveWallpaperMkt(mkt);

  static Future<String> getWallpaperResolution() =>
      _storage.getWallpaperResolution();

  static Future<void> saveWallpaperResolution(String resolution) =>
      _storage.saveWallpaperResolution(resolution);

  static Future<int?> getWallpaperCacheCleanupTime() =>
      _storage.getWallpaperCacheCleanupTime();

  static Future<void> saveWallpaperCacheCleanupTime(int timestamp) =>
      _storage.saveWallpaperCacheCleanupTime(timestamp);

  static Future<String?> getWallpaperCustomPath() =>
      _storage.getWallpaperCustomPath();

  static Future<void> saveWallpaperCustomPath(String path) =>
      _storage.saveWallpaperCustomPath(path);

  static Future<void> clearWallpaperCustomPath() =>
      _storage.clearWallpaperCustomPath();

  static Future<bool> getTodoFoldersInline() => _storage.getTodoFoldersInline();

  static Future<void> setTodoFoldersInline(bool inline) =>
      _storage.setTodoFoldersInline(inline);

  static Future<String> getTodoFolderDisplayMode() =>
      _storage.getTodoFolderDisplayMode();

  static Future<void> setTodoFolderDisplayMode(String mode) =>
      _storage.setTodoFolderDisplayMode(mode);

  static Future<void> saveLastCourseImportUrl(String url) =>
      _storage.saveLastCourseImportUrl(url);

  static Future<String?> getLastCourseImportUrl() =>
      _storage.getLastCourseImportUrl();

  static Future<Map<String, int>> getCategoryReminderMinutes(String username) =>
      _storage.getCategoryReminderMinutes(username);

  static Future<void> saveCategoryReminderMinutes(
          String username, Map<String, int> data) =>
      _storage.saveCategoryReminderMinutes(username, data);

  static Future<List<Map<String, dynamic>>> getSyncFailures() =>
      _storage.getSyncFailures();

  static Future<void> resolveConflictLocally({
    required String uuid,
    required String table,
    required Map<String, dynamic> resolvedData,
    bool createOplog = false,
    bool touchUpdatedAt = true,
  }) =>
      _storage.resolveConflictLocally(
          uuid: uuid,
          table: table,
          resolvedData: resolvedData,
          createOplog: createOplog,
          touchUpdatedAt: touchUpdatedAt);
}
