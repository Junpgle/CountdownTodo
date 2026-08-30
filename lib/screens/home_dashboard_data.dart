part of 'home_dashboard.dart';
// ignore_for_file: annotate_overrides

mixin _HomeDashboardDataMixin on _HomeDashboardStateBase {
  static const Set<DataRefreshDomain> _dashboardDataDomains = {
    DataRefreshDomain.todos,
    DataRefreshDomain.todoGroups,
    DataRefreshDomain.countdowns,
    DataRefreshDomain.mathStats,
    DataRefreshDomain.courses,
    DataRefreshDomain.planBlocks,
    DataRefreshDomain.fixedSchedules,
  };

  Set<DataRefreshDomain> _normalizedDashboardDomains(
    Set<DataRefreshDomain>? domains,
  ) {
    if (domains == null || domains.contains(DataRefreshDomain.all)) {
      return Set<DataRefreshDomain>.from(_dashboardDataDomains);
    }
    return domains.where(_dashboardDataDomains.contains).toSet();
  }

  bool _hasNoCourseLayout(
    List<TodoItem> todos,
    Map<String, dynamic> courseData,
    List<TodoPlanBlock> planBlocks,
  ) {
    final courses = courseData['courses'];
    final isCourseEmpty = courses == null ||
        (courses is List && courses.isEmpty) ||
        (courseData['title']?.toString().contains('天后') ?? false) ||
        courseData['title'] == '最近无课' ||
        courseData['title'] == '暂无课表';
    if (!isCourseEmpty) return false;

    final now = DateTime.now();
    final nowMs = now.millisecondsSinceEpoch;
    final tomorrowEndMs =
        DateTime(now.year, now.month, now.day + 2).millisecondsSinceEpoch;
    final hasActivePlans = planBlocks.any(
      (block) =>
          !block.isDeleted &&
          block.endTime > nowMs &&
          block.startTime < tomorrowEndMs,
    );
    final hasActiveTodos = todos.any((todo) {
      if (todo.isDeleted || todo.dueDate == null || todo.isAllDayTask) {
        return false;
      }
      final startMs = todo.createdDate ?? todo.createdAt;
      return startMs > 0 &&
          todo.dueDate!.millisecondsSinceEpoch > nowMs &&
          startMs < tomorrowEndMs;
    });
    return !hasActivePlans && !hasActiveTodos;
  }

  void _mergePendingDashboardDomains(Set<DataRefreshDomain> domains) {
    _pendingReloadDomains.addAll(_normalizedDashboardDomains(domains));
  }

  void _onScopedDataRefresh() {
    if (!mounted) return;
    final signal = StorageService.scopedDataRefreshNotifier.value;
    final domains = signal.domains;
    final refreshAll = domains.contains(DataRefreshDomain.all);

    if (refreshAll || domains.contains(DataRefreshDomain.habits)) {
      _habitsRevision.value++;
    }
    if (refreshAll || domains.contains(DataRefreshDomain.pomodoro)) {
      _pomodoroRevision.value++;
    }
    if (refreshAll ||
        domains.contains(DataRefreshDomain.timeLogs) ||
        domains.contains(DataRefreshDomain.pomodoro)) {
      _timelineRevision.value++;
    }
    if (refreshAll || domains.contains(DataRefreshDomain.teams)) {
      _debouncedFetchTeamPending();
      _debouncedFetchAnnouncements();
    }

    final dashboardDomains = _normalizedDashboardDomains(domains);
    if (dashboardDomains.isNotEmpty) {
      unawaited(_loadAllData(domains: dashboardDomains));
    }
  }

  void _onScreenTimeDataRefresh() {
    if (!mounted) return;
    unawaited(_loadCachedScreenTime());
  }

  String get _timeSalutation {
    // 从配置中获取时间问候语模式
    final salutationMode =
        _homeTextConfig['salutationMode'] as String? ?? 'timed';

    if (salutationMode == 'fixed') {
      // 固定模式：返回固定的问候语
      final fixedSalutation = _homeTextConfig['fixedSalutation'] as String?;
      if (fixedSalutation != null && fixedSalutation.isNotEmpty) {
        return fixedSalutation;
      }
      return '你好';
    }

    // 分时段模式：根据配置或默认值返回
    final salutationSlots =
        _homeTextConfig['salutationSlots'] as List<dynamic>?;
    if (salutationSlots != null && salutationSlots.isNotEmpty) {
      final now = DateTime.now();
      final currentMinutes = now.hour * 60 + now.minute;

      for (var slot in salutationSlots) {
        final slotMap = slot as Map<String, dynamic>;
        final startHour = slotMap['startHour'] as int;
        final startMinute = slotMap['startMinute'] as int;
        final endHour = slotMap['endHour'] as int;
        final endMinute = slotMap['endMinute'] as int;
        final text = slotMap['text'] as String?;

        if (text == null || text.isEmpty) continue;

        final startMinutes = startHour * 60 + startMinute;
        final endMinutes = endHour * 60 + endMinute;

        bool isInSlot;
        if (endMinutes <= startMinutes) {
          isInSlot =
              currentMinutes >= startMinutes || currentMinutes < endMinutes;
        } else {
          isInSlot =
              currentMinutes >= startMinutes && currentMinutes < endMinutes;
        }

        if (isInSlot) return text;
      }
    }

    // 默认分时段逻辑
    final hour = DateTime.now().hour;
    if (hour >= 5 && hour < 12) return "上午好";
    if (hour >= 12 && hour < 14) return "中午好";
    if (hour >= 14 && hour < 18) return "下午好";
    return "晚上好";
  }

  void _generateGreeting() {
    final now = DateTime.now();
    final currentMinutes = now.hour * 60 + now.minute;

    // 从配置中获取问候语模式
    final greetingMode = _homeTextConfig['greetingMode'] as String? ?? 'timed';

    if (greetingMode == 'fixed') {
      // 固定模式：从固定问候语列表中随机选择
      final fixedGreetings =
          _homeTextConfig['fixedGreetings'] as List<dynamic>?;
      if (fixedGreetings != null && fixedGreetings.isNotEmpty) {
        _currentGreeting =
            fixedGreetings[Random().nextInt(fixedGreetings.length)] as String;
        return;
      }
    } else {
      // 分时段模式：根据当前时间匹配时段
      final timeSlots = _homeTextConfig['timeSlots'] as List<dynamic>?;
      if (timeSlots != null) {
        for (var slot in timeSlots) {
          final slotMap = slot as Map<String, dynamic>;
          final startHour = slotMap['startHour'] as int;
          final startMinute = slotMap['startMinute'] as int;
          final endHour = slotMap['endHour'] as int;
          final endMinute = slotMap['endMinute'] as int;
          final greetings =
              (slotMap['greetings'] as List<dynamic>?)?.cast<String>();

          if (greetings == null || greetings.isEmpty) continue;

          final startMinutes = startHour * 60 + startMinute;
          final endMinutes = endHour * 60 + endMinute;

          bool isInSlot;
          if (endMinutes <= startMinutes) {
            // 跨天时段
            isInSlot =
                currentMinutes >= startMinutes || currentMinutes < endMinutes;
          } else {
            // 正常时段
            isInSlot =
                currentMinutes >= startMinutes && currentMinutes < endMinutes;
          }

          if (isInSlot) {
            _currentGreeting = greetings[Random().nextInt(greetings.length)];
            return;
          }
        }
      }
    }

    // 兜底：使用默认问候语
    _currentGreeting = "愿你今天一切顺利！";
  }

  Future<void> _loadHomeTextConfig() async {
    final config = await StorageService.getHomeTextConfig();
    if (mounted) {
      setState(() {
        _homeTextConfig = config;
        _generateGreeting();
      });
    }
  }

  Future<void> _initNotifications() async {
    await NotificationService.init();
    // 习惯提醒：应用启动时重排今日提醒（跨天后固定时刻需要刷新）。
    unawaited(HabitReminderService.rescheduleAll());
    // 🚀 桌面端拦截：Windows 暂无原生通知权限请求
    if (AppPlatform.isAndroid || AppPlatform.isIOS) {
      await _permissionCoordinator.request(AppPermissionKind.notification);
    }
  }

  Future<void> _initScreenTime() async {
    if (mounted) setState(() => _isLoadingScreenTime = true);

    if (!AppPlatform.isAndroid && !AppPlatform.isIOS) {
      // 桌面端：直接走缓存读取+Tai同步，不需要权限检查
      if (mounted) setState(() => _hasUsagePermission = true);
      await _loadCachedScreenTime();
      return;
    }

    bool permit = await ScreenTimeService.checkPermission();
    if (mounted) {
      setState(() {
        _hasUsagePermission = permit;
        if (!permit) _isLoadingScreenTime = false;
      });
    }
    if (permit) _loadCachedScreenTime();
  }

  Future<void> _loadCachedScreenTime() async {
    final loadGeneration = ++_screenTimeLoadGeneration;
    final prefs = await SharedPreferences.getInstance();
    int? userId = prefs.getInt('current_user_id');
    if (userId == null) {
      if (mounted) setState(() => _isLoadingScreenTime = false);
      return;
    }

    var stats = await ScreenTimeService.getScreenTimeData(userId);
    var lastSync = await StorageService.getLastScreenTimeSync();

    if (mounted && loadGeneration == _screenTimeLoadGeneration) {
      setState(() {
        _screenTimeStats = stats;
        _lastScreenTimeSync = lastSync;
        _isLoadingScreenTime = false;
      });
    }
  }

  void _showTokenExpiredDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text("登录已失效"),
        content: const Text("由于您的 Token 无效，请重新登录以同步数据。"),
        actions: [
          FilledButton(
            onPressed: () async {
              // 使用统一会话清理入口，避免遗漏真实的用户名、Token 和数据库状态。
              await StorageService.clearLoginSession();

              if (!mounted || !ctx.mounted) return;

              // 2. 彻底关闭弹窗并切断路由栈，回到登录页
              Navigator.of(ctx).pop();
              Navigator.pushNamedAndRemoveUntil(
                context,
                '/login',
                (route) => false,
              );
            },
            child: const Text("重新登录"),
          ),
        ],
      ),
    );
  }

  void _debounceCollaborativeSync() {
    _collaborativeSyncDebouncer?.cancel();
    _collaborativeSyncDebouncer =
        Timer(const Duration(milliseconds: 1500), () async {
      if (!mounted) return;
      // debugPrint('🔄 [协同] 防抖触发：执行批量同步与界面刷新...');
      await _handleManualSync(silent: true);
    });
  }

  /// 🚀 辅助：带超时和错误捕获的任务加载器
  Future<T?> _loadDataTask<T>(String name, Future<T> task) async {
    try {
      final result = await task.timeout(const Duration(seconds: 5));
      return result;
    } catch (e) {
      // debugPrint("❌ [DashboardLoader] $name 加载超时或异常: $e");
      return null;
    }
  }

  List<TElement> _safeListResult<TElement>(dynamic value) {
    if (value is List<TElement>) {
      return value;
    }
    if (value is List) {
      return value.whereType<TElement>().toList();
    }
    return <TElement>[];
  }

  // 🚀 核心重构：渲染主页时，绝对不能将 isDeleted 的数据加载到视图层！
  Future<void> _loadAllData({
    bool deferred = false,
    Set<DataRefreshDomain>? domains,
  }) async {
    final requestedDomains = _normalizedDashboardDomains(domains);
    if (requestedDomains.isEmpty) return;

    if (_isDashboardLoadInProgress) {
      _mergePendingDashboardDomains(requestedDomains);
      return;
    }

    if (deferred) {
      // 🚀 核心优化：延迟 400ms 刷新，确保返回动画（Pop）执行完毕后再处理数据
      // 避免 CPU 密集型任务与动画冲突导致卡顿
      await Future.delayed(const Duration(milliseconds: 400));
      if (!mounted) return;
      if (_isDashboardLoadInProgress) {
        _mergePendingDashboardDomains(requestedDomains);
        return;
      }
    }

    _isDashboardLoadInProgress = true;
    final showInitialSkeleton = _todos.isEmpty &&
        (_dashboardCourseData['courses'] as List? ?? const []).isEmpty;
    if (showInitialSkeleton) _isGlobalLoadingNotifier.value = true;
    var hadTaskFailure = false;
    final failedDomains = <DataRefreshDomain>{};
    try {
      //debugPrint("⏳ [DashboardLoader] 开始并发加载 5 项核心任务...");

      // 1. 读取基础数据 (并发执行，带超时保护)
      final loadTodos = requestedDomains.contains(DataRefreshDomain.todos);
      final loadGroups =
          requestedDomains.contains(DataRefreshDomain.todoGroups);
      final loadCountdowns =
          requestedDomains.contains(DataRefreshDomain.countdowns);
      final loadMath = requestedDomains.contains(DataRefreshDomain.mathStats);
      final loadCourses = requestedDomains.contains(DataRefreshDomain.courses);
      final loadPlanBlocks =
          requestedDomains.contains(DataRefreshDomain.planBlocks);
      final loadFixedSchedules =
          requestedDomains.contains(DataRefreshDomain.fixedSchedules);
      final requestedTasks = [
        loadTodos,
        loadGroups,
        loadCountdowns,
        loadMath,
        loadCourses,
        loadPlanBlocks,
        loadFixedSchedules,
      ];

      final results = await Future.wait<dynamic>([
        if (loadTodos)
          _loadDataTask(
              "Todos", StorageService.getTodos(widget.username, limit: 200))
        else
          Future<dynamic>.value(_todos),
        if (loadGroups)
          _loadDataTask("Groups", StorageService.getTodoGroups(widget.username))
        else
          Future<dynamic>.value(_todoGroups),
        if (loadCountdowns)
          _loadDataTask(
              "Countdowns", StorageService.getCountdowns(widget.username))
        else
          Future<dynamic>.value(_countdowns),
        if (loadMath)
          _loadDataTask("Math", StorageService.getMathStats(widget.username))
        else
          Future<dynamic>.value(_mathStats),
        if (loadCourses)
          _loadDataTask(
              "Courses", CourseService.getDashboardCourses(widget.username))
        else
          Future<dynamic>.value(_dashboardCourseData),
        if (loadPlanBlocks)
          _loadDataTask(
              "PlanBlocks", StorageService.getPlanBlocks(widget.username))
        else
          Future<dynamic>.value(_planBlocks),
        if (loadFixedSchedules)
          _loadDataTask("FixedSchedules",
              StorageService.getFixedSchedules(widget.username))
        else
          Future<dynamic>.value(_fixedSchedules),
      ]);

      const resultDomains = [
        DataRefreshDomain.todos,
        DataRefreshDomain.todoGroups,
        DataRefreshDomain.countdowns,
        DataRefreshDomain.mathStats,
        DataRefreshDomain.courses,
        DataRefreshDomain.planBlocks,
        DataRefreshDomain.fixedSchedules,
      ];
      for (var index = 0; index < results.length; index++) {
        if (requestedTasks[index] && results[index] == null) {
          failedDomains.add(resultDomains[index]);
        }
      }
      hadTaskFailure = failedDomains.isNotEmpty;

      final List<TodoItem> allTodos = _mergePendingTodoSnapshots(
        (results[0] == null
                ? List<TodoItem>.from(_todos)
                : _safeListResult<TodoItem>(results[0]))
            .where((t) => !t.isDeleted)
            .toList(),
      );
      final List<TodoGroup> allGroups = (results[1] == null
              ? List<TodoGroup>.from(_todoGroups)
              : _safeListResult<TodoGroup>(results[1]))
          .where((g) => !g.isDeleted)
          .toList();
      final List<CountdownItem> allCountdowns = _safeListResult<CountdownItem>(
        results[2] ?? _countdowns,
      ).where((c) => !c.isDeleted).toList();
      final conflictInputsChanged = loadTodos || loadGroups || loadCountdowns;
      final conflictDetectionEnabled = conflictInputsChanged
          ? await StorageService.getConflictDetectionEnabled()
          : false;

      final bool hasTeamConflict = !conflictInputsChanged
          ? _hasTeamConflictDot
          : conflictDetectionEnabled &&
              ConflictVisibilityService.hasTeamConflict(
                todos: allTodos,
                groups: allGroups,
                countdowns: allCountdowns,
              );

      final Map<String, dynamic> mathStats = results[3] == null
          ? Map<String, dynamic>.from(_mathStats)
          : Map<String, dynamic>.from(results[3] as Map);
      final Map<String, dynamic> courseData = results[4] == null
          ? Map<String, dynamic>.from(_dashboardCourseData)
          : Map<String, dynamic>.from(results[4] as Map);
      final List<TodoPlanBlock> allPlanBlocks = results[5] == null
          ? List<TodoPlanBlock>.from(_planBlocks)
          : _safeListResult<TodoPlanBlock>(results[5]);
      final List<FixedScheduleItem> allFixedSchedules = results[6] == null
          ? List<FixedScheduleItem>.from(_fixedSchedules)
          : _safeListResult<FixedScheduleItem>(results[6]);
      final activityInputsChanged = loadTodos ||
          loadGroups ||
          loadCourses ||
          loadPlanBlocks ||
          loadFixedSchedules;
      final activityInputsReady = activityInputsChanged &&
          (!loadTodos || results[0] != null) &&
          (!loadGroups || results[1] != null) &&
          (!loadCourses || results[4] != null) &&
          (!loadPlanBlocks || results[5] != null) &&
          (!loadFixedSchedules || results[6] != null);

      if (mounted) {
        final bool todosChanged = !_isListEqual(_todos, allTodos);
        final bool groupsChanged = !_isListEqual(_todoGroups, allGroups);
        final bool countdownsChanged =
            !_isListEqual(_countdowns, allCountdowns);
        final bool mathChanged = !_isMapEqual(_mathStats, mathStats);
        final bool coursesChanged =
            !_isMapEqual(_dashboardCourseData, courseData);
        final bool plansChanged = !_isListEqual(_planBlocks, allPlanBlocks);
        final bool fixedSchedulesChanged =
            !_isListEqual(_fixedSchedules, allFixedSchedules);
        final conflictDotChanged = _hasTeamConflictDot != hasTeamConflict;
        final noCourseLayoutChanged = todosChanged &&
            _hasNoCourseLayout(_todos, _dashboardCourseData, _planBlocks) !=
                _hasNoCourseLayout(allTodos, courseData, allPlanBlocks);
        final requiresRootLayoutRebuild = coursesChanged ||
            plansChanged ||
            fixedSchedulesChanged ||
            noCourseLayoutChanged;

        if (todosChanged) {
          _todos = allTodos;
          _todosNotifier.value = allTodos;
          _todoUpdateSignalNotifier.value++;
        }
        if (groupsChanged) {
          _todoGroups = allGroups;
          _groupsNotifier.value = allGroups;
          _todoUpdateSignalNotifier.value++;
        }
        if (countdownsChanged) {
          _countdowns = allCountdowns;
          _countdownsNotifier.value = allCountdowns;
        }
        if (mathChanged) {
          _mathStats = mathStats;
          _mathStatsNotifier.value = mathStats;
        }
        if (coursesChanged) {
          _dashboardCourseData = courseData;
          _courseDataNotifier.value = courseData;
        }
        if (plansChanged) {
          _planBlocks = allPlanBlocks;
        }
        if (fixedSchedulesChanged) {
          _fixedSchedules = allFixedSchedules;
        }
        if (requiresRootLayoutRebuild || conflictDotChanged) {
          setState(() => _hasTeamConflictDot = hasTeamConflict);
        } else {
          _hasTeamConflictDot = hasTeamConflict;
        }

        if (todosChanged || countdownsChanged) {
          _timelineRevision.value++;
        }
        if (plansChanged || coursesChanged || fixedSchedulesChanged) {
          _scheduleRevision.value++;
        }

        if (activityInputsReady) {
          unawaited(MacPomodoroStatusBarService.syncOngoingActivityFromData(
            todos: allTodos,
            todoGroups: allGroups,
            planBlocks: allPlanBlocks,
            courses: _safeListResult<CourseItem>(courseData['courses']),
            fixedSchedules: allFixedSchedules,
          ));
        }

        _debouncedSyncTodoNotification(todosChanged);
        if (domains == null || domains.contains(DataRefreshDomain.all)) {
          _debouncedFetchTeamPending();
          _debouncedFetchAnnouncements();
        }
        _debouncedUpdateTodoWidget(allTodos, todosChanged);
        _debouncedScheduleAllReminders(todosChanged || coursesChanged);
      }
      if (!hadTaskFailure) {
        _dashboardLoadRetryAttempt = 0;
        _dashboardLoadRetryTimer?.cancel();
        _dashboardLoadRetryTimer = null;
      }
    } catch (e) {
      hadTaskFailure = true;
      failedDomains.addAll(requestedDomains);
      // debugPrint('❌ [DashboardLoader] 加载失败: $e');
    } finally {
      if (mounted) {
        _isDashboardLoadInProgress = false;
        if (_isGlobalLoadingNotifier.value) {
          _isGlobalLoadingNotifier.value = false;
        }
        if (_pendingReloadDomains.isNotEmpty) {
          final pendingDomains =
              Set<DataRefreshDomain>.from(_pendingReloadDomains);
          _pendingReloadDomains.clear();
          // 局部刷新不能吞掉本轮失败域；两者合并后立即重试，
          // 后续仍会沿用既有的指数退避策略。
          if (hadTaskFailure) pendingDomains.addAll(failedDomains);
          _dashboardLoadRetryTimer?.cancel();
          _dashboardLoadRetryTimer = null;
          unawaited(_loadAllData(domains: pendingDomains));
        } else if (hadTaskFailure && _dashboardLoadRetryAttempt < 3) {
          final retryDelay = Duration(
            milliseconds: 400 * (1 << _dashboardLoadRetryAttempt),
          );
          _dashboardLoadRetryAttempt++;
          _dashboardLoadRetryTimer?.cancel();
          _dashboardLoadRetryTimer = Timer(retryDelay, () {
            if (mounted) {
              unawaited(_loadAllData(
                domains:
                    failedDomains.isEmpty ? requestedDomains : failedDomains,
              ));
            }
          });
        }
      } else {
        _isDashboardLoadInProgress = false;
      }
    }
  }

  Future<void> _checkCoachMarks() async {
    if (_showCoachMarks || !mounted) return;
    final hasSeenCoachMarks =
        await FeatureTipService.hasTipBeenShown('coach_home_intro');
    if (hasSeenCoachMarks) return;
    if (mounted) {
      _showCoachMarks = true;
      final isTablet = MediaQuery.of(context).size.shortestSide >= 600 ||
          MediaQuery.of(context).size.width > 800;

      final finished = await CoachMarkOverlay.show(
        context: context,
        steps: [
          CoachMarkStep(
            targetKey: _homeAddActionKey,
            title: isTablet ? '创建待办' : '新增入口',
            description: isTablet
                ? '点击此处记下你的第一个待办事项，支持设置提醒和截止日期。'
                : '点击中间的加号，可选择增加待办、倒计时或记账。',
          ),
          CoachMarkStep(
            targetKey: _homePomodoroActionKey,
            title: '开始专注',
            description: '点击此处开始番茄钟专注计时，可绑定待办任务。',
          ),
          CoachMarkStep(
            targetKey: _addCountdownKey,
            title: '添加重要日',
            description: '在这里可以添加即将到来的考试、纪念日，或者其他任何对你非常重要的倒数日。',
          ),
          CoachMarkStep(
            targetKey: _searchButtonKey,
            title: '全局搜索',
            description: '随时在这里搜索所有内容，待办、倒计时、番茄钟、设置、时间日志、屏幕时间通通拿下。',
          ),
          CoachMarkStep(
            targetKey: _todoFolderKey,
            title: '待办文件夹',
            description: '将不同任务分类归纳到文件夹，让待办列表井井有条。',
          ),
          CoachMarkStep(
            targetKey: _todoHistoryKey,
            title: '历史待办',
            description: '在这里回顾所有已经完成或归档的历史待办。',
          ),
          CoachMarkStep(
            targetKey: _countdownHistoryKey,
            title: '历史倒数日',
            description: '在这里查看已经结束或过期的重要日子。',
          ),
          CoachMarkStep(
            targetKey: _todayPlanChartKey,
            title: '规划统计',
            description: '快速查看今日规划的时间安排与执行统计情况。',
          ),
          CoachMarkStep(
            targetKey: _menuKey,
            title: '侧边栏',
            description: '点击这里，即可调出侧栏，涵盖多个功能的快捷入口，设置也从这里进入哦~',
          ),
        ],
        onFinish: () {
          _dismissCoachMarks();
        },
        onSkip: () {
          _dismissCoachMarks();
        },
      );

      // 如果是平板/宽屏模式（左右两栏同时显示），播完首页引导后延迟接着播专注Tab引导
      if (finished && isTablet && mounted) {
        await Future.delayed(const Duration(milliseconds: 500));
        await _checkFocusTabCoachMarks();
      }
    }
  }

  // 🚀 新增：检查并显示专注 Tab 的引导
  Future<void> _checkFocusTabCoachMarks() async {
    if (_showCoachMarks || !mounted) return;
    final hasSeenCoachMarks =
        await FeatureTipService.hasTipBeenShown('coach_focus_tab');
    if (hasSeenCoachMarks) return;
    if (mounted) {
      _showCoachMarks = true;
      await CoachMarkOverlay.show(
        context: context,
        steps: [
          CoachMarkStep(
            targetKey: _timelineCardKey,
            title: '个人时间轴',
            description: '这是你专属的个人时间轴，点进去可以查看详尽的分析报告，洞察你的时间都去哪儿了。',
          ),
          CoachMarkStep(
            targetKey: _pomodoroCardKey,
            title: '最近专注',
            description: '这里会展示你最近一段时间的专注统计，包括累计专注时长和专注趋势。',
          ),
          CoachMarkStep(
            targetKey: _screenTimeCardKey,
            title: '屏幕时间',
            description: '授权后，这里将统计你每日的手机应用使用情况，帮助你减少分心。',
          ),
          CoachMarkStep(
            targetKey: _habitsCardKey,
            title: '今日习惯',
            description: '这里会展示今天需要完成的习惯，点击卡片即可进入习惯中心，查看打卡、历史和统计。',
          ),
        ],
        onFinish: () {
          _dismissCoachMarks(tipId: 'coach_focus_tab');
        },
        onSkip: () {
          _dismissCoachMarks(tipId: 'coach_focus_tab');
        },
      );
    }
  }

  Future<void> _dismissCoachMarks({String tipId = 'coach_home_intro'}) async {
    if (!mounted) return;
    _showCoachMarks = false;
    await FeatureTipService.markTipShown(tipId);
  }

  Future<void> _checkOfficialHolidayPreset() async {
    if (_hasCheckedHolidayPreset || !mounted) return;
    _hasCheckedHolidayPreset = true;

    final window =
        await CourseCalendarAdjustmentService.pendingOfficialHolidayWindow();
    if (window == null || !mounted) return;

    final action = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${window.name}课表调整提醒'),
        content: const Text('临近法定节假日。不同学校放假和补课安排可能不同，请手动选择放假日期，并确认哪一天的课调到哪一天。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'later'),
            child: const Text('稍后'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'snooze_today'),
            child: const Text('今日不再提醒'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, 'open'),
            child: const Text('去选择'),
          ),
        ],
      ),
    );

    if (action == 'snooze_today') {
      await CourseCalendarAdjustmentService.snoozeOfficialHolidayPromptForToday(
          window.key);
      return;
    }

    if (action == 'open' && mounted) {
      await Navigator.push(
        context,
        PageTransitions.slideHorizontal(
          CourseCalendarAdjustmentScreen(
            initialOfficialHolidayKey: window.key,
          ),
        ),
      );
      if (mounted) {
        await _loadAllData(
          deferred: true,
          domains: const {
            DataRefreshDomain.courses,
            DataRefreshDomain.fixedSchedules,
          },
        );
      }
    }
  }

  Future<void> _rescheduleAlarms() async {
    final courses = await CourseService.getAllCourses(widget.username);
    await ReminderScheduleService.scheduleAll(
      todos: _todos,
      courses: courses,
    );
  }

  void _syncTodoNotification() {
    DateTime now = DateTime.now();
    DateTime today = DateTime(now.year, now.month, now.day);

    List<TodoItem> activeTodos = _todos.where((t) {
      if (t.dueDate == null) return true;
      DateTime d = DateTime(t.dueDate!.year, t.dueDate!.month, t.dueDate!.day);
      return !d.isAfter(today);
    }).toList();

    if (activeTodos.isEmpty || activeTodos.every((t) => t.isDone)) {
      NotificationService.cancelSpecialTodoNotification(12345);
    } else {
      NotificationService.updateTodoNotification(activeTodos);
    }

    // 立即检查并显示特殊待办通知
    _checkUpcomingEvents();
  }

  void _debouncedSyncTodoNotification(bool needsSync) {
    _todoNotificationDebouncer?.cancel();
    if (!needsSync) return;
    _todoNotificationDebouncer = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      _syncTodoNotification();
    });
  }

  void _debouncedFetchTeamPending() {
    _teamPendingDebouncer?.cancel();
    _teamPendingDebouncer = Timer(const Duration(seconds: 2), () {
      if (!mounted) return;
      _fetchTeamPendingCount();
    });
  }

  void _debouncedFetchAnnouncements() {
    _announcementDebouncer?.cancel();
    _announcementDebouncer = Timer(const Duration(seconds: 3), () {
      if (!mounted) return;
      _fetchActiveAnnouncements();
    });
  }

  void _debouncedUpdateTodoWidget(List<TodoItem> todos, bool needsSync) {
    _todoWidgetDebouncer?.cancel();
    if (!needsSync) return;
    _todoWidgetDebouncer = Timer(const Duration(milliseconds: 500), () {
      if (!mounted) return;
      WidgetService.updateTodoWidget(_todos);
    });
  }

  void _debouncedScheduleAllReminders(bool needsSync) {
    _reminderScheduleDebouncer?.cancel();
    if (!needsSync) return;
    _reminderScheduleDebouncer = Timer(const Duration(milliseconds: 800), () {
      if (!mounted) return;
      CourseService.getAllCourses(widget.username).then((allCourses) {
        if (!mounted) return;
        ReminderScheduleService.scheduleAll(todos: _todos, courses: allCourses);
      });
    });
  }
}
