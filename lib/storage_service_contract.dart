part of 'storage_service.dart';
// ignore_for_file: constant_identifier_names, unused_element, unused_element_parameter, annotate_overrides

const String _recurrenceOccurrenceNamespace =
    'f3d51c4a-6d54-5c2f-8be4-1c0b54f4038e';
const String keyUsers = "users_data";
const String _storageService_keyUsers = "users_data";
const String keyLeaderboard = "leaderboard_data";
const String _storageService_keyLeaderboard = "leaderboard_data";
const String keySettings = "quiz_settings";
const String _storageService_keySettings = "quiz_settings";
const String keyCurrentUser = "current_login_user";
const String _storageService_keyCurrentUser = "current_login_user";
const String keyTodos = "user_todos";
const String _storageService_keyTodos = "user_todos";
const String keyTodoGroups = "user_todo_groups";
const String _storageService_keyTodoGroups = "user_todo_groups";
const String keyCountdowns = "user_countdowns";
const String _storageService_keyCountdowns = "user_countdowns";
const String keyScreenTimeCache = "screen_time_cache";
const String _storageService_keyScreenTimeCache = "screen_time_cache";
const String keyLastScreenTimeSync = "last_screen_time_sync";
const String _storageService_keyLastScreenTimeSync = "last_screen_time_sync";
const String keyScreenTimeHistory = "screen_time_history";
const String _storageService_keyScreenTimeHistory = "screen_time_history";
const String keyAppMappings = "app_category_mappings";
const String _storageService_keyAppMappings = "app_category_mappings";
const String keyLastMappingsSync = "last_mappings_sync";
const String _storageService_keyLastMappingsSync = "last_mappings_sync";
const String keyAuthToken = "auth_session_token";
const String _storageService_keyAuthToken = "auth_session_token";
const String keyDeviceId = "app_device_uuid";
const String _storageService_keyDeviceId = "app_device_uuid";
const String keySyncInterval = "app_sync_interval";
const String _storageService_keySyncInterval = "app_sync_interval";
const String keyThemeMode = "app_theme_mode";
const String _storageService_keyThemeMode = "app_theme_mode";
const String keyThemeColorMode = "app_theme_color_mode";
const String _storageService_keyThemeColorMode = "app_theme_color_mode";
const String keyCustomThemeColor = "app_custom_theme_color";
const String _storageService_keyCustomThemeColor = "app_custom_theme_color";
const String keyLastAutoSync = "last_auto_sync_time";
const String _storageService_keyLastAutoSync = "last_auto_sync_time";
const String keySemesterProgressEnabled = "semester_progress_enabled";
const String _storageService_keySemesterProgressEnabled =
    "semester_progress_enabled";
const String keySemesterStart = "semester_start_date";
const String _storageService_keySemesterStart = "semester_start_date";
const String keySemesterEnd = "semester_end_date";
const String _storageService_keySemesterEnd = "semester_end_date";
const String keySemesters = "semesters_list";
const String _storageService_keySemesters = "semesters_list";
const String keyActiveSemester = "active_semester_id";
const String _storageService_keyActiveSemester = "active_semester_id";
const String keyTimeLogs = "user_time_logs";
const String _storageService_keyTimeLogs = "user_time_logs";
const String keyIgnoredScheduleConflicts = "ignored_schedule_conflicts";
const String _storageService_keyIgnoredScheduleConflicts =
    "ignored_schedule_conflicts";
const String keyConflictDetectionEnabled = "conflict_detection_enabled";
const String _storageService_keyConflictDetectionEnabled =
    "conflict_detection_enabled";
const String keyServerChoice = "app_server_choice";
const String _storageService_keyServerChoice = "app_server_choice";
const String keySystemStartupEnabled = "system_startup_enabled";
const String _storageService_keySystemStartupEnabled = "system_startup_enabled";
const String keyPrivacyAgreed = "privacy_policy_agreed";
const String _storageService_keyPrivacyAgreed = "privacy_policy_agreed";
const String keyPrivacyDate = "privacy_policy_date";
const String _storageService_keyPrivacyDate = "privacy_policy_date";
const String keyPrivacyCachedVersion = "privacy_policy_cached_version";
const String _storageService_keyPrivacyCachedVersion =
    "privacy_policy_cached_version";
const String keyPrivacyCacheTime = "privacy_policy_cache_time";
const String _storageService_keyPrivacyCacheTime = "privacy_policy_cache_time";
const String privacyRawUrl =
    'https://raw.githubusercontent.com/Junpgle/CountdownTodo/refs/heads/master/PRIVACY_POLICY.md';
const String _storageService_privacyRawUrl =
    'https://raw.githubusercontent.com/Junpgle/CountdownTodo/refs/heads/master/PRIVACY_POLICY.md';
const Duration privacyCacheDuration = Duration(hours: 1);
const Duration _storageService_privacyCacheDuration = Duration(hours: 1);
const String keyLocalScreenTime = "local_screen_time_pending_upload";
const String _storageService_keyLocalScreenTime =
    "local_screen_time_pending_upload";
const String keyLlmRetryCount = "llm_retry_count";
const String _storageService_keyLlmRetryCount = "llm_retry_count";
const String keyPendingTodoConfirm = "pending_todo_confirm";
const String _storageService_keyPendingTodoConfirm = "pending_todo_confirm";
const String keyWallpaperProvider = "app_wallpaper_provider";
const String _storageService_keyWallpaperProvider = "app_wallpaper_provider";
const String keyWallpaperImageFormat = "app_wallpaper_image_format";
const String _storageService_keyWallpaperImageFormat =
    "app_wallpaper_image_format";
const String keyWallpaperIndex = "app_wallpaper_index";
const String _storageService_keyWallpaperIndex = "app_wallpaper_index";
const String keyWallpaperMkt = "app_wallpaper_mkt";
const String _storageService_keyWallpaperMkt = "app_wallpaper_mkt";
const String keyWallpaperResolution = "app_wallpaper_resolution";
const String _storageService_keyWallpaperResolution =
    "app_wallpaper_resolution";
const String keyWallpaperCacheCleanupTime = "app_wallpaper_cache_cleanup_time";
const String _storageService_keyWallpaperCacheCleanupTime =
    "app_wallpaper_cache_cleanup_time";
const String keyWallpaperCustomPath = "app_wallpaper_custom_path";
const String _storageService_keyWallpaperCustomPath =
    "app_wallpaper_custom_path";
const String keyNotifyLiveEnabled = "notify_live_activity_enabled";
const String _storageService_keyNotifyLiveEnabled =
    "notify_live_activity_enabled";
const String keyNotifyNormalEnabled = "notify_normal_enabled";
const String _storageService_keyNotifyNormalEnabled = "notify_normal_enabled";
const String keyNotifyCourseEnabled = "notify_course_enabled";
const String _storageService_keyNotifyCourseEnabled = "notify_course_enabled";
const String keyNotifyQuizEnabled = "notify_quiz_enabled";
const String _storageService_keyNotifyQuizEnabled = "notify_quiz_enabled";
const String keyNotifyTodoSummaryEnabled = "notify_todo_summary_enabled";
const String _storageService_keyNotifyTodoSummaryEnabled =
    "notify_todo_summary_enabled";
const String keyNotifyAppUpdatesEnabled = "notify_app_updates_enabled";
const String _storageService_keyNotifyAppUpdatesEnabled =
    "notify_app_updates_enabled";
const String keyTodoFoldersInline = "todo_folders_inline";
const String _storageService_keyTodoFoldersInline = "todo_folders_inline";
const String keyTodoFolderDisplayMode = "todo_folder_display_mode";
const String _storageService_keyTodoFolderDisplayMode =
    "todo_folder_display_mode";
const String keyNotifySpecialTodoEnabled = "notify_special_todo_enabled";
const String _storageService_keyNotifySpecialTodoEnabled =
    "notify_special_todo_enabled";
const String keyNotifyPomodoroEnabled = "notify_pomodoro_enabled";
const String _storageService_keyNotifyPomodoroEnabled =
    "notify_pomodoro_enabled";
const String keyNotifyTodoRecognizeEnabled = "notify_todo_recognize_enabled";
const String _storageService_keyNotifyTodoRecognizeEnabled =
    "notify_todo_recognize_enabled";
const String keyNotifyPomodoroEndEnabled = "notify_pomodoro_end_enabled";
const String _storageService_keyNotifyPomodoroEndEnabled =
    "notify_pomodoro_end_enabled";
const String keyNotifyTodoLiveEnabled = "notify_todo_live_enabled";
const String _storageService_keyNotifyTodoLiveEnabled =
    "notify_todo_live_enabled";
const String keyNotifyReminderEnabled = "notify_reminder_enabled";
const String _storageService_keyNotifyReminderEnabled =
    "notify_reminder_enabled";
const String keyCourseReminderMinutes = "course_reminder_minutes";
const String _storageService_keyCourseReminderMinutes =
    "course_reminder_minutes";
const String keyLastCourseImportUrl = "last_course_import_url";
const String _storageService_keyLastCourseImportUrl = "last_course_import_url";
const String keyCategoryReminderMinutes = "category_reminder_minutes";
const String _storageService_keyCategoryReminderMinutes =
    "category_reminder_minutes";
const String keyWindowsScheduledReminders = "windows_scheduled_reminders";
const String _storageService_keyWindowsScheduledReminders =
    "windows_scheduled_reminders";
const Duration _minSyncInterval = Duration(milliseconds: 3400);
const String _keyHomeTextConfig = 'home_text_config';

abstract class _StorageServiceBase {
  final Set<String> recentlyResolvedUuids = {};
  final Map<String, DateTime> recentlyResolvedTimes = {};
  SharedPreferences? _prefs;
  String? _lastRecurrenceCheckDate;
  final Map<String, bool> _recurrenceCheckCache = {};
  final Set<String> _recurrenceDedupeTombstoneIds = {};
  bool _isSyncing = false;
  Set<String> _pendingSyncOplogUuids = {};
  Set<String> _forceFlushProtectedUuids = {};
  final Set<String> _attemptedRecurrenceSeriesRepairUploads = {};
  bool _isCheckingRecurrence = false;
  ValueNotifier<String> themeNotifier = ValueNotifier('system');
  ValueNotifier<String> themeColorModeNotifier = ValueNotifier('default');
  ValueNotifier<Color?> customThemeColorNotifier = ValueNotifier(null);
  ValueNotifier<Color?> appWallpaperColorNotifier = ValueNotifier(null);
  final Map<String, Future<List<TodoItem>>> _inflightTodoRequests = {};
  final ValueNotifier<Map<String, dynamic>> conflictScanNotifier =
      ValueNotifier<Map<String, dynamic>>({
    'isScanning': false,
    'progress': 0,
    'current': 0,
    'total': 0,
    'message': '',
  });
  final ValueNotifier<int> dataRefreshNotifier = ValueNotifier<int>(0);

  /// Dedicated cache refresh signal for screen-time consumers. Keeping this
  /// beside StorageService avoids a reverse import from the storage layer to
  /// ScreenTimeService while still notifying every cache writer.
  final ValueNotifier<int> screenTimeRefreshNotifier = ValueNotifier<int>(0);
  final ValueNotifier<DataRefreshSignal> scopedDataRefreshNotifier =
      ValueNotifier<DataRefreshSignal>(const DataRefreshSignal.initial());
  final ValueNotifier<int> wallpaperRefreshNotifier = ValueNotifier<int>(0);
  Timer? _refreshDebouncer;
  final Set<DataRefreshDomain> _pendingRefreshDomains = {};
  Timer? _syncDebouncer;
  String? _queuedSyncUsername;
  int _lastSyncRequestAt = 0;
  void Function()? onDataChangedHook;
  bool isRecentlyResolved(String uuid);
  Future<SharedPreferences> get prefs;
  Future<void> saveFixedSchedules(
    String username,
    List<FixedScheduleItem> items, {
    bool sync = true,
    bool isSyncSource = false,
  });
  Future<List<FixedScheduleItem>> getFixedSchedules(
    String username, {
    bool includeDeleted = false,
  });
  Future<List<FixedScheduleItem>> getFixedSchedulesByDay(
    String username,
    DateTime day,
  );
  Future<void> deleteFixedSchedule(
    String username,
    FixedScheduleItem item,
  );
  Future<List<HabitGoal>> getHabitGoals();
  Future<void> saveHabitGoals(List<HabitGoal> items);
  Future<List<HabitGoalRuleRevision>> getHabitRules({
    String? habitUuid,
  });
  Future<void> saveHabitRules(
    List<HabitGoalRuleRevision> items,
  );
  Future<List<HabitCheckIn>> getHabitCheckIns({
    String? habitUuid,
    String? fromDate,
    String? toDate,
  });
  Future<void> saveHabitCheckIns(List<HabitCheckIn> items);
  Future<void> savePlanBlocks(String username, List<TodoPlanBlock> items,
      {bool sync = true, bool isSyncSource = false});
  Future<List<TodoPlanBlock>> getPlanBlocks(String username,
      {bool includeDeleted = false});
  Future<void> deletePlanBlockGlobally(String username, String idToDelete);
  Future<List<TodoPlanBlock>> getPlanBlocksByTodo(
      String username, String todoId);
  Future<List<TodoPlanBlock>> getPlanBlocksByDay(String username, DateTime day);
  void triggerRefresh([
    Set<DataRefreshDomain> domains = const {DataRefreshDomain.all},
  ]);
  void triggerWallpaperRefresh();
  void setForceFlushProtectedUuids(Set<String> uuids);
  Future<void> _updateOplogRowsByIds(
    Database db,
    Set<int> ids,
    Map<String, Object?> values,
  );
  void requestSync(String username);
  void _scheduleQueuedSync(Duration delay);
  int _normalizedRecurrenceIndex(TodoItem item);
  int _normalizedCustomIntervalDays(TodoItem item);
  int? _parseNullableInt(dynamic raw);
  Future<void> ignoreRemoteItem({
    required String table,
    required String uuid,
    String? teamUuid,
  });
  Future<void> unignoreRemoteItem(String uuid);
  Future<bool> isItemIgnored(String uuid);
  String _todoRequestKey(
    String username, {
    required bool includeDeleted,
    required int? limit,
  });
  List<TodoItem> _cloneTodoItems(List<TodoItem> items);
  Future<void> _clearTodoPrefsMirror(String username);
  String _scopedKey(String baseKey, String? username);
  Future<String> getDeviceFriendlyName();
  Future<String?> getCurrentUsername();
  Future<bool> rollbackLocalItem(String table, int logId, String username);
  Future<String> getDeviceId();
  Future<void> initTheme();
  Future<bool> register(String username, String password);
  Future<bool> login(String username, String password);
  Future<void> saveLoginSession(String username, {String? token});
  Future<String?> getLoginSession();
  Future<void> clearLoginSession();
  Future<void> saveSettings(Map<String, dynamic> settings);
  Future<Map<String, dynamic>> getSettings();
  Future<void> saveWindowsScheduledReminders(
      List<Map<String, dynamic>> reminders);
  Future<List<Map<String, dynamic>>> getWindowsScheduledReminders();
  Future<void> savePomodoroTags(
      String username, List<Map<String, dynamic>> tags);
  Future<void> saveHistory(
      String username, int score, int duration, String details);
  Future<List<String>> getHistory(String username);
  Future<Map<String, dynamic>> getMathStats(String username);
  Future<void> updateLeaderboard(String username, int score, int duration);
  Future<List<Map<String, dynamic>>> getLeaderboard();
  Future<void> saveCountdowns(String username, List<CountdownItem> items,
      {bool sync = true, bool isSyncSource = false});
  Future<void> _clearGhostConflictFlags(dynamic db);
  Future<List<CountdownItem>> getCountdowns(String username,
      {bool includeDeleted = false});
  Future<void> deleteCountdownGlobally(String username, String idToDelete);
  Future<void> saveTodos(String username, List<TodoItem> items,
      {bool sync = true,
      bool isSyncSource = false,
      bool recomputeScheduleConflicts = true});
  bool _hasSubstantialChange(Map<String, dynamic> before,
      Map<String, dynamic> after, List<String> fields);
  Future<void> _refreshTodoScheduleConflicts(
    String username, {
    Set<String>? affectedDayKeys,
  });
  Future<Map<String, int>> scanAllTodoConflicts(String username);
  Future<void> clearLocalTodoScheduleConflicts(String username);
  Future<void> ignoreLocalScheduleConflict(String username, TodoItem item);
  Future<Set<String>> _getIgnoredScheduleConflictKeys(String username);
  Future<void> _recordLocalAuditOptimized(
      String table,
      String uuid,
      Map<String, dynamic> afterData,
      String? teamUuid,
      Map<String, dynamic>? existingData);
  Future<void> _recordLocalAudit(String table, String uuid,
      Map<String, dynamic> afterData, String? teamUuid);
  Future<void> _syncTodosToBand(List<TodoItem> items);
  Future<void> updateSingleTodo(String username, TodoItem item,
      {bool sync = true});
  Future<void> permanentlyDeleteTodo(String username, String uuid);
  Future<void> clearTodoRecycleBin(String username);
  bool _isHistoricalTodo(TodoItem todo, DateTime today);
  Future<int> clearHistoricalTodos(String username);
  Future<void> permanentlyDeleteCountdown(String username, String uuid);
  Future<List<TodoItem>> getTodos(String username,
      {bool includeDeleted = false, int? limit});
  Future<List<TodoItem>> _getTodosInternal(String username,
      {bool includeDeleted = false, int? limit});
  Future<void> clearTeamItems(String teamUuid);
  Future<List<TodoItem>> _handleRecurrenceLogic(
      String username, List<TodoItem> todos);
  DateTime _getRecurrenceBaseDate(TodoItem todo);
  List<int> _recurrenceRollOffsets(
    TodoItem todo,
    DateTime baseDay,
    DateTime todayDay,
  );
  List<int> recurrenceRollOffsetsForTest(
    TodoItem todo,
    DateTime baseDay,
    DateTime todayDay,
  );
  List<TodoItem> futureRecurrenceOccurrencesForTest(
    TodoItem source,
    List<TodoItem> existing,
  );
  List<TodoItem> repairMissingPastRecurrenceOccurrencesForTest(
    TodoItem active,
    List<TodoItem> existing,
  );
  String recurrenceOccurrenceIdForTest(
    String seriesId,
    int startMs,
  );
  bool deduplicatePersistedRecurrenceOccurrencesForTest(
    List<TodoItem> todos,
  );
  bool pruneRecurrenceOccurrencesAfterEndDateForTest(
    List<TodoItem> todos, {
    required String seriesId,
    required DateTime recurrenceEndDate,
  });
  Set<String> pruneRecurrenceOccurrencesAfterEndDatesForTest(
    List<TodoItem> todos,
  );
  Set<String> _pruneRecurrenceOccurrencesAfterEndDates(
    List<TodoItem> todos,
  );
  Future<int> mergeRecurrenceSeries(
    String username, {
    required String targetSeriesId,
    required Set<String> seriesIds,
  });
  Set<String> mergeRecurrenceSeriesForTest(
    List<TodoItem> todos, {
    required String targetSeriesId,
    required Set<String> seriesIds,
  });
  Set<String> _mergeRecurrenceSeries(
    List<TodoItem> todos, {
    required String targetSeriesId,
    required Set<String> seriesIds,
  });
  List<int> _futureRecurrenceRollOffsets(
    TodoItem todo,
    DateTime baseLocal,
  );
  DateTime? _nextRecurrenceDate(DateTime current, TodoItem todo);
  ({TodoItem occurrence, bool isNew, bool didChange})
      _getOrCreateRecurrenceOccurrence({
    required TodoItem source,
    required int rollByDays,
    required String seriesId,
    required List<TodoItem> todos,
    required List<TodoItem> generatedOccurrences,
  });
  String _recurrenceLocalDayKey(int startMs);
  String _recurrenceOccurrenceId(String seriesId, int startMs);
  List<TodoItem> _repairMissingPastRecurrenceOccurrences({
    required TodoItem ruleSource,
    required TodoItem copySource,
    required String seriesId,
    required int throughStartMs,
    required List<TodoItem> todos,
    required List<TodoItem> generatedOccurrences,
  });
  bool _deduplicatePersistedRecurrenceOccurrences(List<TodoItem> todos,
      {Set<String>? changedIds});
  int _compareRecurrenceOccurrenceIdentity(TodoItem a, TodoItem b);
  bool _copyRecurrenceOccurrenceData(
    TodoItem source,
    TodoItem target,
  );
  String? _overlappingRecurrencePairKey(TodoItem previous, TodoItem next);
  TodoItem _copyForNextRecurrence(TodoItem source);
  void _rollRecurrenceDateByDays(TodoItem todo, int days);
  Future<bool> deleteTodoGlobally(String username, String idToDelete);
  Future<void> saveTodoGroups(String username, List<TodoGroup> items,
      {bool sync = true, bool isSyncSource = false});
  Future<void> _clearTodoGroupPrefsMirror(String username);
  Future<List<TodoGroup>> getTodoGroups(String username,
      {bool includeDeleted = false});
  Future<void> deleteTodoGroupGlobally(String username, String idToDelete);
  Future<void> saveTimeLogs(String username, List<TimeLogItem> items,
      {bool sync = true});
  Future<List<TimeLogItem>> getTimeLogs(String username, {int? limit});
  Future<bool> deleteTimeLogGlobally(String username, String idToDelete);
  Future<void> saveLocalScreenTime(Map<dynamic, dynamic> stats);
  Future<Map<String, dynamic>?> getLocalScreenTimePackage();
  Future<Map<String, dynamic>> getLocalScreenTimeMap();
  Future<List<dynamic>> getLocalScreenTime();
  Future<void> saveScreenTimeCache(List<dynamic> stats);
  Future<void> saveScreenTimeHistoryToSql(String date, List<dynamic> stats);
  Future<List<dynamic>> getScreenTimeCache();
  Future<Map<String, List<dynamic>>> getScreenTimeHistory();
  Future<void> updateLastScreenTimeSync();
  Future<DateTime?> getLastScreenTimeSync();
  Future<void> syncAppMappings();
  Future<Map<String, String>> getAppMappings();
  Future<void> resetSyncTime(String username);
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
  });
  bool recomputeLocalTodoScheduleConflictsForTest(
    List<TodoItem> todos,
  );
  bool _recomputeLocalTodoScheduleConflicts(
    List<TodoItem> todos, {
    Set<String> ignoredScheduleConflictKeys = const <String>{},
    Set<String> skipIds = const <String>{},
    void Function(int current, int total, String message)? onProgress,
  });
  bool _clearLocalTodoScheduleConflicts(List<TodoItem> todos);
  String _scheduleConflictPairKey(
    String aId,
    int aStart,
    int aEnd,
    String bId,
    int bStart,
    int bEnd,
  );
  String? _scheduleConflictKeyFromPayload(
      TodoItem item, Map<String, dynamic> peer);
  int? _parseMillis(dynamic value);
  bool _isSameRecurrenceSeries(TodoItem first, TodoItem second);
  bool _isRecurringTodoForLww(TodoItem todo);
  bool _isSameRecurrenceSeriesPayload(
    TodoItem item,
    Map<String, dynamic> peer,
  );
  bool _hasVersionConflict(Map<String, dynamic>? data);
  List<TodoItem> clearResolvedRecurrenceMigrationConflictsForTest(
    List<TodoItem> todos,
  );
  List<TodoItem> _clearResolvedRecurrenceMigrationConflicts(
    List<TodoItem> todos,
  );
  bool _payloadHasConflict(Map<String, dynamic> data);
  bool _payloadHasVersionConflict(Map<String, dynamic> data);
  bool _isLocalScheduleConflict(Map<String, dynamic>? data);
  Map<String, dynamic> _stripClientOnlyConflictForSync(
      Map<String, dynamic> data);
  void _preserveLocalTodoSourceFields(TodoItem local, TodoItem incoming);
  Set<String> repairMissingRemoteRecurrenceSeriesIdsForTest(
    List<TodoItem> incoming,
    List<TodoItem> local,
  );
  Set<String> _repairMissingRemoteRecurrenceSeriesIds(
    List<TodoItem> incoming,
    List<TodoItem> local,
  );
  String _resolveRecurrenceSeriesAlias(
    String seriesId,
    Map<String, TodoItem> todosById,
  );
  Set<String> repairLocalRecurrenceSeriesAliasesFromHistoryForTest(
    List<TodoItem> todos,
    Map<String, List<String>> historicalSeriesByTodoId,
  );
  Future<Set<String>> _repairLocalRecurrenceSeriesAliasesFromHistory(
    Database db,
    List<TodoItem> todos,
  );
  Set<String> _repairLocalRecurrenceSeriesAliases(
    List<TodoItem> todos,
    Map<String, List<String>> historicalSeriesByTodoId,
  );
  bool _isMissingRecurrenceSeriesId(TodoItem todo);
  String? _remoteRecurrencePlanSignature(TodoItem todo);
  bool _isRemoteOccurrenceOnRecurrence(
    TodoItem ruleSource,
    TodoItem candidate,
  );
  Map<String, dynamic> _conflictPeerSummary(_TodoInterval interval);
  String _classifyScheduleRelation(
      TodoItem current, List<Map<String, dynamic>> peers);
  String _localDayKey(int ms);
  Future<bool> syncScreenTimeAlone(String username, String deviceName);
  Future<void> saveAppSetting(String key, dynamic value);
  Future<int> getSyncInterval();
  Future<bool> getConflictDetectionEnabled();
  Future<String> getThemeMode();
  Future<void> setThemeColorMode(String mode);
  Future<void> setCustomThemeColor(Color color);
  void setAppWallpaperColor(Color? color);
  Future<void> saveServerChoice(String choice);
  Future<String> getServerChoice();
  Future<void> saveHomeTextConfig(Map<String, dynamic> config);
  Future<Map<String, dynamic>> getHomeTextConfig();
  Future<bool> getSemesterEnabled();
  Future<DateTime?> getSemesterStart();
  Future<DateTime?> getSemesterEnd();
  Future<List<SemesterInfo>> getSemesters();
  Future<void> saveSemesters(List<SemesterInfo> semesters);
  Future<String> getActiveSemesterId();
  Future<void> setActiveSemesterId(String semesterId);
  Future<DateTime?> getSemesterStartById(String semesterId);
  Future<SemesterInfo?> getSemesterByDate(DateTime date);
  Future<void> updateLastAutoSyncTime(String username);
  Future<DateTime?> getLastAutoSyncTime(String username);
  Future<void> saveIslandBounds(String islandId, Map<String, dynamic> bounds);
  Future<Map<String, dynamic>?> getIslandBounds(String islandId);
  Future<int> getLLMRetryCount();
  Future<void> setLLMRetryCount(int count);
  Future<void> savePendingTodoConfirm({
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
  });
  Future<void> updatePendingTodoConfirmStatus({
    required String status,
    int? currentAttempt,
    int? maxAttempts,
    String? errorMsg,
    List<Map<String, dynamic>>? results,
    List<Map<String, dynamic>>? financeResults,
    String? processingSessionId,
    String? recognitionChatSessionId,
    String? recognitionChatMessageId,
  });
  Future<Map<String, dynamic>?> getPendingTodoConfirm();
  Future<void> clearPendingTodoConfirm();
  Future<bool> isLiveActivityNotificationEnabled();
  Future<void> setLiveActivityNotificationEnabled(bool enabled);
  Future<bool> isNormalNotificationEnabled();
  Future<void> setNormalNotificationEnabled(bool enabled);
  Future<bool> isCourseNotificationEnabled();
  Future<void> setCourseNotificationEnabled(bool enabled);
  Future<bool> isQuizNotificationEnabled();
  Future<void> setQuizNotificationEnabled(bool enabled);
  Future<bool> isTodoSummaryNotificationEnabled();
  Future<void> setTodoSummaryNotificationEnabled(bool enabled);
  Future<bool> isSpecialTodoNotificationEnabled();
  Future<void> setSpecialTodoNotificationEnabled(bool enabled);
  Future<bool> isPomodoroNotificationEnabled();
  Future<void> setPomodoroNotificationEnabled(bool enabled);
  Future<bool> isTodoRecognizeNotificationEnabled();
  Future<void> setTodoRecognizeNotificationEnabled(bool enabled);
  Future<bool> isTodoLiveNotificationEnabled();
  Future<void> setTodoLiveNotificationEnabled(bool enabled);
  Future<bool> isPomodoroEndNotificationEnabled();
  Future<void> setPomodoroEndNotificationEnabled(bool enabled);
  Future<bool> isReminderNotificationEnabled();
  Future<void> setReminderNotificationEnabled(bool enabled);
  Future<int> getCourseReminderMinutes();
  Future<void> setCourseReminderMinutes(int minutes);
  Future<bool> isPrivacyPolicyAgreed();
  Future<void> setPrivacyPolicyAgreed(bool agreed, {String? date});
  Future<bool> isPrivacyPolicyUpToDate();
  Future<void> withdrawPrivacyAgreement();
  void dispose();
  Future<String> getWallpaperProvider();
  Future<void> saveWallpaperProvider(String provider);
  Future<String> getWallpaperImageFormat();
  Future<void> saveWallpaperImageFormat(String format);
  Future<int> getWallpaperIndex();
  Future<void> saveWallpaperIndex(int index);
  Future<String> getWallpaperMkt();
  Future<void> saveWallpaperMkt(String mkt);
  Future<String> getWallpaperResolution();
  Future<void> saveWallpaperResolution(String resolution);
  Future<int?> getWallpaperCacheCleanupTime();
  Future<void> saveWallpaperCacheCleanupTime(int timestamp);
  Future<String?> getWallpaperCustomPath();
  Future<void> saveWallpaperCustomPath(String path);
  Future<void> clearWallpaperCustomPath();
  Future<bool> getTodoFoldersInline();
  Future<void> setTodoFoldersInline(bool inline);
  Future<String> getTodoFolderDisplayMode();
  Future<void> setTodoFolderDisplayMode(String mode);
  Future<void> saveLastCourseImportUrl(String url);
  Future<String?> getLastCourseImportUrl();
  Future<Map<String, int>> getCategoryReminderMinutes(String username);
  Future<void> saveCategoryReminderMinutes(
      String username, Map<String, int> data);
  Future<List<Map<String, dynamic>>> getSyncFailures();
  Future<void> resolveConflictLocally({
    required String uuid,
    required String table,
    required Map<String, dynamic> resolvedData,
    bool createOplog = false,
    bool touchUpdatedAt = true,
  });
}

class _StorageServiceImpl extends _StorageServiceBase
    with
        _StorageFixed,
        _StorageCore,
        _StorageTodos,
        _StorageSync,
        _StorageConflict,
        _StorageSettings {}

class _TodoInterval {
  const _TodoInterval({
    required this.todo,
    required this.startMs,
    required this.endMs,
  });

  final TodoItem todo;
  final int startMs;
  final int endMs;
}
