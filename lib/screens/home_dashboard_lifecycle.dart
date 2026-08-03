part of 'home_dashboard.dart';
// ignore_for_file: annotate_overrides

mixin _HomeDashboardLifecycleMixin on _HomeDashboardStateBase {
  @override
  void initState() {
    super.initState();
    _permissionCoordinator = PermissionRequestCoordinator(context: context);
    WidgetsBinding.instance.addObserver(this);
    // 冷启动清理残留通知
    NotificationService.cancelSpecialTodoNotification(12351); // 番茄钟结束提醒
    NotificationService.cancelTodoRecognizeNotification(); // 图片识别通知
    _loadSectionPreferences();
    _loadSemesterSettings();
    _loadHomeTextConfig();
    ThirtyDayChallengeRepository.activityRevision
        .addListener(_onThirtyDayChallengeActivityChanged);
    unawaited(_loadThirtyDayChallengeStatus());
    _generateGreeting();
    _initManifestWallpaper();
    WidgetService.init();
    // 首页首轮加载完成后会把同一批数据直接交给灵动岛，避免冷启动时
    // 灵动岛与首页并发执行两套完整的 SQLite 查询。
    MacPomodoroStatusBarService.init(deferOngoingActivityRestore: true);
    _macIslandCommandSub =
        MacPomodoroStatusBarService.onCommand.listen(_handleMacIslandCommand);
    _configureBackgroundNotificationPoll();
    _initCrossDevicePomodoro(); // 首页也连接 WS
    _initLocalPomodoroMonitoring(); // 🚀 修改：使用 Stream 监测本地专注状态
    // 🚀 Granular Refresh Initialization
    _todosNotifier = ValueNotifier<List<TodoItem>>(_todos);
    _groupsNotifier = ValueNotifier<List<TodoGroup>>(_todoGroups);
    _courseDataNotifier =
        ValueNotifier<Map<String, dynamic>>(_dashboardCourseData);
    _countdownsNotifier = ValueNotifier<List<CountdownItem>>(_countdowns);
    _mathStatsNotifier = ValueNotifier<Map<String, dynamic>>(_mathStats);

    // 🚀 核心修复：监听全局数据刷新信号，实现背景同步后的 UI 自动响应
    StorageService.dataRefreshNotifier.addListener(_loadAllData);
    StorageService.wallpaperRefreshNotifier.addListener(_onWallpaperRefresh);
    // 在细粒度通知器和刷新监听都就绪后再启动首轮数据读取。
    unawaited(_loadAllData());

    // 🚀 使用集中式事件分发，避免多个页面覆盖同一个 MethodChannel handler
    if (AppPlatform.isAndroid || AppPlatform.isIOS) {
      _notifSubs.add(NotificationService.listen('markCurrentTodoDone', (call) {
        // debugPrint("📱 收到 markCurrentTodoDone 调用: arguments=${call.arguments}");
        final args = call.arguments;
        int? notifId;
        if (args is Map) {
          notifId = args['notificationId'] as int?;
        }
        // debugPrint("📱 解析 notifId: $notifId");
        _markCurrentTodoDone(notifId: notifId);
      }));
      _notifSubs.add(NotificationService.listen('openTodoConfirm', (call) {
        _checkPendingTodoConfirm();
      }));
      _notifSubs.add(NotificationService.listen('openShortcut', (call) {
        final shortcutType = call.arguments as String?;
        // debugPrint("⚡ 收到 openShortcut 调用: $shortcutType");
        if (shortcutType != null) {
          _handleShortcut(shortcutType);
        }
      }));
      _notifSubs.add(NotificationService.listen('viewAnalysisImage', (call) {
        final imagePath = call.arguments as String?;
        if (imagePath != null && mounted) {
          _showAnalysisImage(imagePath);
        }
      }));
      _notifSubs.add(NotificationService.listen('viewOriginalText', (call) {
        final text = call.arguments as String?;
        if (text != null && mounted) {
          _showOriginalText(text);
        }
      }));
      _notifSubs.add(NotificationService.listen('openPlanBlock', (call) {
        // debugPrint("📅 收到 openPlanBlock 调用: arguments=${call.arguments}");
        if (mounted) {
          _handleOpenPlanBlock(call.arguments);
        }
      }));
      _notifSubs.add(NotificationService.listen('openPomodoro', (call) {
        // debugPrint("🍅 收到 openPomodoro 调用");
        _navigateToPomodoro();
      }));
      _notifSubs.add(NotificationService.listen('openTodoList', (call) {
        // debugPrint("📋 收到 openTodoList 调用");
        if (mounted) {
          Navigator.of(context).popUntil((route) => route.isFirst);
        }
      }));
      // 习惯目标提醒：点击打开习惯中心。
      _notifSubs.add(NotificationService.listen('openHabitCenter', (call) {
        if (!mounted) return;
        Navigator.of(context).popUntil((route) => route.isFirst);
        PageTransitions.pushFromRect(
          context: context,
          page: HabitCenterScreen(username: widget.username),
          sourceKey: GlobalKey(),
        );
        _habitsRevision.value++;
      }));
      // 通知按钮事件：如果不在番茄钟页，先导航过去，
      // PomodoroScreen 的 listen() 会自动 replay pending 事件。
      for (final action in ['pomodoroFinishEarly', 'pomodoroAbandon']) {
        _notifSubs.add(NotificationService.listen(action, (call) {
          // debugPrint("🍅 收到 $action");
          _navigateToPomodoro();
        }));
      }
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      // 首次进入首页的交互按固定顺序串行，避免公告、操作指引和
      // 系统权限弹窗同时出现。
      unawaited(_runStartupPrompts());
      Future.delayed(const Duration(milliseconds: 1000), () {
        if (mounted) _initScreenTime();
      });
      // 灵动岛启动时自动显示 idle 状态
      Future.delayed(const Duration(milliseconds: 1500), () {
        if (mounted) {
          StorageService.syncAppMappings();
          _initIslandOnStartup();
          _checkOfficialHolidayPreset();
        }
      });

      ExternalShareHandler.init(
        context,
        () {
          _loadAllData();
        },
        onTodoRecognized: (results, imagePath) {
          // 刷新待确认数据（从 StorageService 获取最新状态）
          _checkPendingTodoConfirm().then((_) {
            // 如果识别成功且有结果，自动打开确认页面
            if (results.isNotEmpty && mounted) {
              _navigateToTodoConfirm(results, imagePath, null);
            }
          });
        },
      );

      // 检查是否有待确认的事项数据（从通知点击进入）
      _checkPendingTodoConfirm();

      _checkAutoSync();

      _courseTimer = Timer.periodic(const Duration(minutes: 1), (timer) {
        _checkUpcomingEvents();
      });

      // 🚀 Banner 倒计时实时刷新：每 10 秒触发 Banner 区域重绘，确保”剩 Xm”动态更新
      _bannerRefreshTimer =
          Timer.periodic(const Duration(seconds: 10), (timer) {
        if (mounted) _pomodoroTickNotifier.value++;
      });

      // 立即执行一次
      Future.delayed(Duration(milliseconds: 500), () {
        if (mounted) {
          _checkUpcomingEvents();
          setState(() {});
        }
      });
      _checkAndNavigateToPomodoro();
      // 🚀 预热搜索索引，确保首次点击秒开
      SearchService.instance.warmup();
      // 🚀 清理 7 天前的过期图片
      TodoItem.cleanupAnalysisImages();
    });
  }

  Future<void> _configureBackgroundNotificationPoll() async {
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getInt('current_user_id');
    final token =
        ApiService.getToken() ?? prefs.getString(StorageService.keyAuthToken);
    if (userId == null || token == null || token.isEmpty) return;
    await BackgroundNotificationService.configureNotificationPoll(
      userId: userId,
      token: token,
      apiBaseUrl: ApiService.effectiveBaseUrl,
    );
  }

  @override
  void dispose() {
    _permissionCoordinator.dispose();
    for (final sub in _notifSubs) {
      sub.cancel();
    }
    StorageService.dataRefreshNotifier.removeListener(_loadAllData);
    StorageService.wallpaperRefreshNotifier.removeListener(_onWallpaperRefresh);
    ThirtyDayChallengeRepository.activityRevision
        .removeListener(_onThirtyDayChallengeActivityChanged);
    _todosNotifier.dispose();
    _groupsNotifier.dispose();
    _courseDataNotifier.dispose();
    _countdownsNotifier.dispose();
    _mathStatsNotifier.dispose();
    _connStateSub?.cancel();
    _remotePomodoroSub?.cancel();
    _localPomodoroSub?.cancel();
    _macIslandCommandSub?.cancel();
    _remotePomodoroTicker?.cancel();
    _localPomodoroTicker?.cancel();
    ExternalShareHandler.dispose();
    _courseTimer?.cancel();
    _todoPersistDebounce?.cancel();
    if (_todoPersistDebounceCompleter?.isCompleted == false) {
      _todoPersistDebounceCompleter!.complete();
    }
    _collaborativeSyncDebouncer?.cancel();
    _remoteTodoHighlightTimer?.cancel();
    _bannerRefreshTimer?.cancel();
    _dashboardLoadRetryTimer?.cancel();
    _todoNotificationDebouncer?.cancel();
    _teamPendingDebouncer?.cancel();
    _announcementDebouncer?.cancel();
    _todoWidgetDebouncer?.cancel();
    _reminderScheduleDebouncer?.cancel();
    _pomodoroTickNotifier.dispose();
    MacPomodoroStatusBarService.dispose();
    StorageService.wallpaperRefreshNotifier.removeListener(_onWallpaperRefresh);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Future<void> _loadThirtyDayChallengeStatus() async {
    try {
      final hasStarted = await ThirtyDayChallengeRepository.hasStarted();
      final isActive =
          hasStarted && !await ThirtyDayChallengeRepository.isPaused();
      var completedCount = 0;
      if (isActive) {
        final state = await ThirtyDayChallengeRepository.load();
        completedCount = state.completedCount;
      }
      if (!mounted ||
          (isActive == _isThirtyDayChallengeActive &&
              completedCount == _thirtyDayChallengeCompletedCount)) {
        return;
      }
      setState(() {
        _isThirtyDayChallengeActive = isActive;
        _thirtyDayChallengeCompletedCount = completedCount;
      });
    } catch (_) {
      // 首页 Banner 不应影响首页主体加载。
    }
  }

  @override
  void _onThirtyDayChallengeActivityChanged() {
    unawaited(_loadThirtyDayChallengeStatus());
  }

  /// 检查 Android 12+ 精确闹钟权限，未授权时弹一次引导 SnackBar

  Future<void> _checkUpdatesSilently() async {
    if (!mounted) return;
    await UpdateService.checkUpdateAndPrompt(context, isManual: false);
  }

  Future<void> _runStartupPrompts() {
    return _startupPromptsFuture ??= _runStartupPromptsInOrder();
  }

  Future<void> _runStartupPromptsInOrder() async {
    try {
      // checkUpdateAndPrompt 会等到公告（以及紧随其后的更新提示）关闭。
      try {
        await _checkUpdatesSilently();
      } catch (_) {
        // 公告检查失败不应阻断本地引导和权限流程。
      }
      if (!mounted) return;

      try {
        await _checkCoachMarks();
      } catch (_) {
        // 引导状态读取失败时仍继续进行必要的权限初始化。
      }
      if (!mounted) return;

      await _initNotifications();
      if (!mounted) return;

      // 精确闹钟的授权提示也放到队列末尾，不覆盖前面的引导。
      await _checkExactAlarmPermission();
    } finally {
      _startupPromptsCompleted = true;
    }
  }

  Future<void> _loadSemesterSettings() async {
    bool enabled = await StorageService.getSemesterEnabled();
    DateTime? start = await StorageService.getSemesterStart();
    DateTime? end = await StorageService.getSemesterEnd();
    if (mounted) {
      setState(() {
        _semesterEnabled = enabled;
        _semesterStart = start;
        _semesterEnd = end;
      });
    }
  }

  double _calculateSemesterProgress() {
    if (_semesterStart == null || _semesterEnd == null) return 0.0;
    DateTime now = DateTime.now();
    if (now.isBefore(_semesterStart!)) return 0.0;
    if (now.isAfter(_semesterEnd!)) return 1.0;

    int totalMinutes = _semesterEnd!.difference(_semesterStart!).inMinutes;
    int passedMinutes = now.difference(_semesterStart!).inMinutes;
    if (totalMinutes <= 0) return 0.0;
    return (passedMinutes / totalMinutes).clamp(0.0, 1.0);
  }

  Future<void> _loadSectionPreferences() async {
    final prefs = await SharedPreferences.getInstance();

    // 均按照默认排序
    // 首页: 重要日(countdowns), 课程(courses), 待办(todos)
    // 专注页: 最近专注(pomodoro), 屏幕时间(screenTime), 测验(math)

    // 平板双栏布局固定分配 (左侧重要日待办, 右侧课程最近专注\屏幕时间\测验)
    _leftSections = ['banners', 'countdowns', 'todos'];
    _rightSections = [
      'courses',
      'timeline',
      'pomodoro',
      'habits',
      'screenTime',
      'math'
    ];

    // 忽略之前的可见性设置，全部强制显示
    _sectionVisibility = {
      'courses': true,
      'countdowns': true,
      'todos': true,
      'planBlocks': true,
      'screenTime': true,
      'math': true,
      'pomodoro': true,
      'timeline': true,
      'habits': true,
    };

    String? noCourseBehav = prefs.getString('no_course_behavior');
    if (mounted) {
      setState(() {
        if (noCourseBehav != null) _noCourseBehavior = noCourseBehav;
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkAutoSync(force: true);
      _loadSectionPreferences();
      _loadSemesterSettings();
      // 冷启动的公告/引导/权限队列结束前，恢复事件不重复发起公告。
      if (_startupPromptsCompleted) {
        _checkUpdatesSilently();
      }
      // 🚀 唤醒时重置壁纸重试计数，防止因最小化导致的短暂断网触发兜底
      _wallpaperRetryCount = 0;
      // 从番茄钟页或任何前台切换回来时，刷新所有卡片
      if (mounted) {
        _todoRevision.value++;
        _scheduleRevision.value++;
        _timelineRevision.value++;
        _pomodoroRevision.value++;
        _habitsRevision.value++;
      }
      // 平板/手机从后台唤醒时，强制重连触发服务器推送最新跨端专注状态
      _syncService.resumeSync();
      // 清理残留的一次性通知
      NotificationService.cancelSpecialTodoNotification(12351); // 番茄钟结束提醒
      NotificationService.cancelTodoRecognizeNotification(); // 图片识别通知
    }
  }

  /// 启动时检测是否有正在进行的番茄钟，有则跳转至计时界面
  Future<void> _checkAndNavigateToPomodoro() async {
    // 稍微延迟，让首页先完成渲染
    await Future.delayed(const Duration(milliseconds: 800));
    if (!mounted) return;
    // 🚀 有待确认事项时不劫持导航，优先让用户处理识别结果
    if (_pendingTodoConfirm != null) return;
    final saved = await PomodoroService.loadRunState();
    if (saved == null) return;
    if (saved.phase != PomodoroPhase.focusing &&
        saved.phase != PomodoroPhase.breaking) {
      return;
    }
    // 确认倒计时还没结束
    final remaining = saved.targetEndMs - DateTime.now().millisecondsSinceEpoch;
    if (saved.mode == TimerMode.countdown && remaining <= 0) return;

    if (AppPlatform.isWindows) {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool('float_window_enabled') ?? true) {
        final allTags = await PomodoroService.getTags();
        final tagNames = saved.tagUuids
            .map((uuid) =>
                allTags.where((t) => t.uuid == uuid).firstOrNull?.name ?? '')
            .where((n) => n.isNotEmpty)
            .toList();
        final isCountUp = saved.mode == TimerMode.countUp;
        await FloatWindowService.update(
          endMs: isCountUp ? saved.sessionStartMs : saved.targetEndMs,
          title: saved.todoTitle ?? '',
          tags: tagNames,
          isLocal: true,
          mode: isCountUp ? 1 : 0,
        );
      }
    }

    if (!mounted) return;
    await PageTransitions.pushFromRect(
      context: context,
      page: PomodoroScreen(username: widget.username),
      sourceKey: _pomodoroCardKey,
    );
    if (mounted) {
      _pomodoroRevision.value++;
      _timelineRevision.value++;
      _loadAllData(deferred: true);
    }
  }

  /// 启动时自动初始化灵动岛（如果用户已开启）
  Future<void> _initIslandOnStartup() async {
    if (!AppPlatform.isWindows) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final style = prefs.getInt('float_window_style') ?? 0;
      if (style != 1) return;

      // 检查是否有正在进行的番茄钟，如果有，_checkAndNavigateToPomodoro 已处理
      final saved = await PomodoroService.loadRunState();
      if (saved != null &&
          (saved.phase == PomodoroPhase.focusing ||
              saved.phase == PomodoroPhase.breaking)) {
        final remaining =
            saved.targetEndMs - DateTime.now().millisecondsSinceEpoch;
        if (saved.mode == TimerMode.countdown && remaining <= 0) return;
        // 番茄钟场景已由 _checkAndNavigateToPomodoro 处理
        return;
      }

      // 无番茄钟时，显示 idle 状态的灵动岛
      // debugPrint('[HomeDashboard] Initializing island on startup (idle state)');
      await FloatWindowService.update(forceReset: true);
    } catch (e) {
      // debugPrint('[HomeDashboard] Island startup init failed: $e');
    }
  }

  /// 🚀 Uni-Sync 4.0: 获取所有团队待处理申请总数
  /// 🚀 Uni-Sync 4.0: 获取当前置顶公告
  Future<void> _fetchActiveAnnouncements() async {
    try {
      final list = await ApiService.fetchUnreadPriorityAnnouncements();
      if (list.isNotEmpty && mounted) {
        setState(() {
          _activeAnnouncement = TeamAnnouncement.fromJson(list.first);
        });
      } else if (mounted) {
        setState(() => _activeAnnouncement = null);
      }
    } catch (e) {
      // debugPrint('❌ [首页] 获取置顶公告失败: $e');
    }
  }

  Future<void> _fetchTeamPendingCount() async {
    try {
      final rawTeams = await ApiService.fetchTeams();
      int totalPending = 0;

      // 并发获取各团队待处理数
      await Future.wait(rawTeams.map((t) async {
        if (t['role'] == 0) {
          // 如果是管理员
          final reqs = await ApiService.fetchPendingRequests(t['uuid']);
          totalPending += reqs.length;
        }
      }));

      if (mounted) {
        final backgroundUnread = await BackgroundNotificationService
            .getUnreadBackgroundNotifications();
        setState(
            () => _teamPendingCount = totalPending + backgroundUnread.length);
      }
    } catch (e) {
      // debugPrint('❌ [首页] 获取团队消息计数失败: $e');
    }
  }

  Future<void> _checkAutoSync({bool force = false}) async {
    // 🛡️ 安全检查：升级引导未完成时禁止任何自动同步
    // 防止用户跳过引导进入主页后，空的本地数据被推送并覆盖云端数据
    final guideNeeded = await FeatureGuideScreen.shouldShow();
    if (guideNeeded) return;

    int interval = await StorageService.getSyncInterval();
    DateTime? lastSync =
        await StorageService.getLastAutoSyncTime(widget.username);
    DateTime now = DateTime.now();

    if (force || interval == 0) {
      _handleManualSync(silent: true);
    } else {
      if (lastSync == null || now.difference(lastSync).inMinutes >= interval) {
        _handleManualSync(silent: true);
      }
    }
  }

  void _markCurrentTodoDone({int? notifId}) async {
    // debugPrint(
    //     "📱 _markCurrentTodoDone 被调用: notifId=$notifId, todos数量=${_todos.length}");

    DateTime now = DateTime.now();
    DateTime today = DateTime(now.year, now.month, now.day);

    List<TodoItem> activeTodos = _todos.where((t) {
      if (t.dueDate == null) return true;
      DateTime d = DateTime(t.dueDate!.year, t.dueDate!.month, t.dueDate!.day);
      return !d.isAfter(today);
    }).toList();

    // debugPrint("📱 activeTodos数量=${activeTodos.length}");

    // 普通待办通知的 ID 是 12345，特殊待办通知的 ID 是 todo.id.hashCode
    const int normalTodoNotifId = 12345;

    // 检测是否为特殊待办
    bool isSpecialTodo(String title) =>
        ItemSemanticsService.specialTodoTypeForTitle(title) != 'default';

    TodoItem? currentTodo;

    if (notifId == null || notifId == normalTodoNotifId) {
      // 普通待办通知：完成第一个未完成的**普通**待办（跳过特殊待办）
      for (var t in activeTodos) {
        if (!t.isDone && !isSpecialTodo(t.title)) {
          currentTodo = t;
          break;
        }
      }
      // debugPrint("📱 普通待办通知，完成第一个未完成的普通待办: ${currentTodo?.title}");
    } else {
      // 特殊待办通知：通过 notifId 找到对应的待办
      currentTodo = activeTodos
          .where((t) => t.id.hashCode == notifId && !t.isDone)
          .firstOrNull;
      // debugPrint("📱 特殊待办通知，找到待办: ${currentTodo?.title}");
    }

    // 找不到待办，不执行任何操作
    if (currentTodo == null) {
      // debugPrint("找不到对应的待办: notifId=$notifId");
      return;
    }

    // debugPrint("📱 准备完成待办: ${currentTodo.title}");

    // 取消特殊待办的通知
    await NotificationService.cancelSpecialTodoNotification(
        currentTodo.id.hashCode);

    setState(() {
      currentTodo!.isDone = true;
      currentTodo.markAsChanged();
      _todos.sort((a, b) => a.isDone == b.isDone ? 0 : (a.isDone ? 1 : -1));
    });

    setState(() {
      currentTodo!.isDone = true;
      currentTodo.markAsChanged();
      _todos.sort((a, b) => a.isDone == b.isDone ? 0 : (a.isDone ? 1 : -1));
    });

    // 🚀 跨端联动：完成待办的同时，告知云端停止对应的番茄钟（如果有设备在观察的话）
    PomodoroSyncService().sendStopSignal(
      todoUuid: currentTodo.id,
      sessionUuid: _localPomodoro?.sessionUuid,
    );

    // 🚀 Uni-Sync 4.0 优化：改用单条原子化更新，性能提升显著
    await StorageService.updateSingleTodo(widget.username, currentTodo);

    // 注意：共享文件的更新逻辑可保持异步，不阻塞主线程交互
    Future.microtask(() async {
      final allTodos = await StorageService.getTodos(widget.username);
      await _saveTodosToSharedFile(allTodos);
    });

    // 通知 Island 检查提醒并刷新槽位缓存
    FloatWindowService.triggerReminderCheck();
    FloatWindowService.invalidateSlotCache();

    _syncTodoNotification();
    await WidgetService.updateTodoWidget(_todos);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('已完成: ${currentTodo.title}'),
            duration: const Duration(seconds: 1)),
      );
    }
  }
}
