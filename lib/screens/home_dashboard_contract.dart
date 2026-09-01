part of 'home_dashboard.dart';
// ignore_for_file: unused_element, unused_element_parameter

// 所有页面分片共享的成员契约。
// 具体实现仍位于各职责 mixin，这里只为 Dart 提供跨分片的静态类型信息。
mixin _HomeDashboardContract {
  Future<void> _openAiAssistantFromAppBar();

  Future<void> _openPendingRecognitionChat();

  Future<void> _handleAiTodoGroupsChanged(List<TodoGroup> groups);

  Future<void> _handleAiTodosBatchAction(
    List<TodoItem> inserted,
    List<TodoItem> updated,
  );

  Future<void> _configureBackgroundNotificationPoll();

  Future<void> _checkUpdatesSilently();

  Future<void> _runStartupPrompts();

  Future<void> _runStartupPromptsInOrder();

  Future<void> _loadSemesterSettings();

  double _calculateSemesterProgress();

  Future<void> _loadSectionPreferences();

  Future<void> _checkAndNavigateToPomodoro();

  Future<void> _initIslandOnStartup();

  Future<void> _fetchActiveAnnouncements();

  Future<void> _fetchTeamPendingCount();

  Future<void> _checkAutoSync({bool force = false});

  void _markCurrentTodoDone({int? notifId});

  Future<void> _checkExactAlarmPermission();

  Future<dynamic> _navigateToTodoConfirm(List<Map<String, dynamic>> results,
      String? imagePath, String? originalText,
      [String? teamUuid, String? teamName]);

  Future<void> _batchAddTodos(List<Map<String, dynamic>> todosData,
      [String? teamUuid, String? teamName]);

  Future<void> _checkPendingTodoConfirm();

  Future<void> _openRecognizedFinanceDrafts(
    List<FinanceEntryDraft> drafts,
  );

  void _showAnalysisImage(String imagePath);

  void _showOriginalText(String text);

  void _navigateToPomodoro();

  Future<void> _handleMacIslandCommand(MacIslandCommand command);

  Future<void> _openIslandEntity(String kind, String id);

  Future<void> _startIslandEntityFocus(String kind, String id);

  Future<void> _completeIslandTodo(String id);

  Future<TodoItem?> _findIslandTodo(String id);

  Future<TodoPlanBlock?> _findIslandPlanBlock(String id);

  Future<CourseItem?> _findIslandCourse(String id);

  Future<FixedScheduleItem?> _findIslandFixedSchedule(String id);

  Future<void> _handleShortcut(String shortcutType);

  Future<void> _handleOpenPlanBlock(dynamic arguments);

  Future<void> _openPendingTodoConfirm();

  Future<void> _initCrossDevicePomodoro();

  Future<void> _handleRemotePomodoroSignal(CrossDevicePomodoroState signal);

  void _startRemotePomodoroTicker(int targetEndMs, bool isCountUp);

  void _stopRemotePomodoroTicker();

  void _initLocalPomodoroMonitoring();

  void _startLocalTicker(bool isCountUp);

  void _stopLocalTicker();

  bool _isPlanBlockStartable(TodoPlanStatus status);

  Future<void> _resetStalePlanBlockFocus();

  String _planBlockStartText(int startTimeMs, int nowMs);

  Future<void> _startPlanBlockFocus(TodoPlanBlock block);

  Future<void> _stopPlanBlockPomodoro();

  Widget _buildPendingTodoConfirmCard(bool isLight);

  Future<void> _retryPendingTodoRecognition();

  Future<void> _ignorePendingTodoRecognition();

  Widget _buildUniversalBanner(bool isLight);

  Widget _buildChallengeParticipationBanner(bool isLight);

  Widget _buildBannerCard(HomeBannerEvent event, bool isLight);

  List<HomeBannerEvent> _collectBannerEvents();

  void _openTodoEditor(TodoItem todo);

  String _specialTodoBannerLabel(String specialType);

  String _specialTodoBannerIcon(String specialType);

  Color _specialTodoBannerColor(String specialType);

  String _specialTodoBannerTimeInfo(TodoItem todo, DateTime now);

  DateTime? _resolveCourseStartTime(CourseItem course, DateTime now);

  DateTime? _resolveCourseEndTime(CourseItem course, DateTime now);

  Future<void> _checkUpcomingEvents();

  Future<void> _performUpcomingEventsCheck();

  String get _timeSalutation;

  void _generateGreeting();

  Future<void> _loadHomeTextConfig();

  Future<void> _loadThirtyDayChallengeStatus();

  void _onThirtyDayChallengeActivityChanged();

  Future<void> _initNotifications();

  Future<void> _initScreenTime();

  Future<void> _loadCachedScreenTime();

  void _showTokenExpiredDialog();

  void _debounceCollaborativeSync();

  Future<T?> _loadDataTask<T>(String name, Future<T> task);

  List<TElement> _safeListResult<TElement>(dynamic value);

  void _onScopedDataRefresh();

  Future<void> _loadAllData({
    bool deferred = false,
    Set<DataRefreshDomain>? domains,
  });

  Future<void> _checkCoachMarks();

  Future<void> _checkFocusTabCoachMarks();

  Future<void> _dismissCoachMarks({String tipId = 'coach_home_intro'});

  Future<void> _checkOfficialHolidayPreset();

  Future<void> _rescheduleAlarms();

  void _syncTodoNotification();

  void _debouncedSyncTodoNotification(bool needsSync);

  void _debouncedFetchTeamPending();

  void _debouncedFetchAnnouncements();

  void _debouncedUpdateTodoWidget(List<TodoItem> todos, bool needsSync);

  void _debouncedScheduleAllReminders(bool needsSync);

  Future<void> _saveTodosToSharedFile(List<TodoItem> todos);

  List<TodoItem> _cloneTodosForPersistence(List<TodoItem> todos);

  List<TodoItem> _mergePendingTodoSnapshots(List<TodoItem> loadedTodos);

  Future<void> _handleTodosChanged(List<TodoItem> newTodos);

  Future<void> _persistTodosSnapshot(List<TodoItem> todosSnapshot);

  Future<void> _handleManualSync({
    bool silent = false,
    bool syncTodos = true,
    bool syncCountdowns = true,
    bool syncScreenTime = true,
    bool syncPomodoro = true,
    bool syncTimeLogs = true,
    bool syncPlanBlocks = true,
    bool syncFixedSchedules = true,
    bool syncHabits = true,
  });

  void _onScreenTimeDataRefresh();

  Future<void> _showLinkDiagnostics();

  Widget _buildDiagnosticItem(String label, Future<bool> checkFuture);

  Widget _buildEnvironmentInfo();

  Widget _buildInfoRow(String label, String value);

  void _showSyncOptionsDialog();

  bool _isLocalFilePath(String path);

  void _handleWallpaperError();

  Future<void> _triggerNextWallpaperFallback();

  void _tryAnotherRandomWallpaper();

  Future<void> _fetchBingWallpaper({bool isFallback = false});

  Future<void> _initManifestWallpaper();

  void _onWallpaperRefresh();

  Future<void> _refreshWallpaper();

  void _setupWallpaperListeners();

  void _disposeWallpaperListeners();

  Future<void> _fetchRandomWallpaper({bool isFallback = false});

  Widget _buildSemesterProgressBar(bool isLight);

  void _showGlobalSearch();

  Widget _buildWallpaperCopyright(bool isLight);

  Future<void> _downloadWallpaper();

  String _wallpaperExtension(String url);

  Widget _buildCustomBottomBar(bool isDarkMode, bool isLight);

  bool _isListEqual(List a, List b);

  bool _isMapEqual(Map a, Map b);

  Widget _buildDashboardSkeleton(bool isLight);

  Widget _buildSkeletonCard(Color color, {required double height});
}
