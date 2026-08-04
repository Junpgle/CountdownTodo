part of 'home_dashboard.dart';
// ignore_for_file: annotate_overrides

mixin _HomeDashboardViewMixin on _HomeDashboardStateBase {
  Widget build(BuildContext context) {
    bool isDarkMode = Theme.of(context).brightness == Brightness.dark;
    bool showWallpaper = !isDarkMode && _wallpaperShow && _wallpaperUrl != null;
    bool isLight = showWallpaper;
    final bool isTablet = MediaQuery.of(context).size.width >= 768;

    final mainScreen = Scaffold(
      extendBody: true,
      resizeToAvoidBottomInset: !_isSearchOpen, // 🚀 关键：搜索时锁定背景，防止位移卡顿
      backgroundColor: (showWallpaper && !AppPlatform.isWindows)
          ? Colors.transparent
          : Theme.of(context).colorScheme.surface,
      body: Stack(
        children: [
          if (showWallpaper)
            Positioned.fill(
              child: _wallpaperUrl!.startsWith('assets/')
                  ? Builder(
                      builder: (context) {
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (_wallpaperDominantColor == null) {
                            _extractColorFromProvider(
                                AssetImage(_wallpaperUrl!), _wallpaperUrl!);
                          }
                        });
                        return Image.asset(
                          _wallpaperUrl!,
                          fit: BoxFit.cover,
                        );
                      },
                    )
                  : _isLocalFilePath(_wallpaperUrl!) &&
                          localImageProvider(_wallpaperUrl!) != null
                      ? Builder(
                          builder: (context) {
                            final provider =
                                localImageProvider(_wallpaperUrl!)!;
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              if (_wallpaperDominantColor == null) {
                                _extractColorFromProvider(
                                    provider, _wallpaperUrl!);
                              }
                            });
                            return Image(
                              image: provider,
                              fit: BoxFit.cover,
                            );
                          },
                        )
                      : _WallpaperNetworkImage(
                          url: _wallpaperUrl!,
                          onImageProvider: (provider) {
                            _extractColorFromProvider(provider, _wallpaperUrl!);
                          },
                          onSuccess: () {
                            _wallpaperRetryCount = 0;
                          },
                          onError: () {
                            _handleWallpaperError();
                          },
                        ),
            ),
          if (showWallpaper)
            Positioned.fill(
                child: Container(color: Colors.black.withValues(alpha: 0.4))),
          SafeArea(
            child: Column(
              children: [
                _buildSemesterProgressBar(isLight),

                if (_selectedTabIndex != 1 || isTablet)
                  HomeAppBar(
                    username: widget.username,
                    timeSalutation: _timeSalutation,
                    currentGreeting: _currentGreeting,
                    textConfig: HomeTextConfig(
                      customTimeSalutation:
                          _homeTextConfig['customTimeSalutation'] as String?,
                      dateFormat: _homeTextConfig['dateFormat'] as String?,
                      usernameFormat:
                          _homeTextConfig['usernameFormat'] as String?,
                    ),
                    isLight: isLight,
                    isSyncing: _isSyncing,
                    onSync: _showSyncOptionsDialog,
                    onSearch: _showGlobalSearch,
                    onAiAssistant: _openAiAssistantFromAppBar,
                    searchKey: _searchButtonKey,
                    teamsKey: _teamsButtonKey,
                    aiKey: _aiButtonKey,
                    settingsKey: _settingsButtonKey,
                    menuKey: _menuKey,
                    courseKey: _courseButtonKey,
                    showCourseButton: isTablet,
                    teamPendingCount: _teamPendingCount, // 🚀 绑定计数
                    hasTeamConflictDot: _hasTeamConflictDot,
                    onTeams: () async {
                      await PageTransitions.pushFromRect(
                        context: context,
                        page: TeamManagementScreen(username: widget.username),
                        sourceKey: _teamsButtonKey,
                      );
                      final unreadBackgroundNotifications =
                          await BackgroundNotificationService
                              .getUnreadBackgroundNotifications();
                      final notificationIds = unreadBackgroundNotifications
                          .map((e) => e['id'])
                          .whereType<num>()
                          .map((e) => e.toInt())
                          .toList();
                      await ApiService.markNotificationsRead(notificationIds);
                      await BackgroundNotificationService
                          .clearUnreadBackgroundNotifications();
                      await _fetchTeamPendingCount();
                      _loadAllData(deferred: true);
                    },
                    onSettings: () async {
                      await PageTransitions.pushFromRect(
                        context: context,
                        page: const SettingsPage(),
                        sourceKey: _settingsButtonKey,
                      );
                      _loadSectionPreferences();
                      _loadSemesterSettings();
                      await _loadHomeTextConfig();
                      _loadAllData(deferred: true);
                    },
                  ),

                // 🚀 Uni-Sync 4.0: 全局链路诊断横幅
                if (_selectedTabIndex != 1 || isTablet)
                  SyncStatusBanner(
                    onDiagnosticRequested: _showLinkDiagnostics,
                  ),

                // DEBUG: 检查状态
                // if (_activeAnnouncement != null) Text("DEBUG: Announcement exists: ${_activeAnnouncement!.title}"),

                // 🚀 Uni-Sync 4.0: 团队置顶公告
                if (_activeAnnouncement != null &&
                    (_selectedTabIndex != 1 || isTablet))
                  StickyAnnouncementBanner(
                    announcement: _activeAnnouncement!,
                    onAcknowledge: () async {
                      final uuid = _activeAnnouncement!.uuid;
                      setState(() => _activeAnnouncement = null);
                      await ApiService.markAnnouncementAsRead(uuid);
                    },
                  ),

                if (_isThirtyDayChallengeActive &&
                    (_selectedTabIndex != 1 || isTablet))
                  _buildChallengeParticipationBanner(isLight),

                // 待确认事项入口卡片（从图片识别来）
                _buildPendingTodoConfirmCard(isLight),

                Expanded(
                  child: ValueListenableBuilder<bool>(
                    valueListenable: _isGlobalLoadingNotifier,
                    builder: (context, isLoading, child) {
                      // 🚀 核心优化：只有当数据完全为空且正在加载时才显示骨架屏，避免背景刷新时的闪烁
                      return Stack(
                        children: [
                          (isLoading &&
                                  _todos.isEmpty &&
                                  (_dashboardCourseData['courses'] as List? ??
                                          [])
                                      .isEmpty)
                              ? _buildDashboardSkeleton(isLight)
                              : LayoutBuilder(
                                  builder: (context, constraints) {
                                    // ... (rest of section definitions)
                                    Widget courseSection =
                                        ValueListenableBuilder<int>(
                                      valueListenable: _scheduleRevision,
                                      builder: (context, trigger, _) {
                                        return CourseSectionWidget(
                                          dashboardCourseData:
                                              _dashboardCourseData,
                                          todos: _todos,
                                          isLight: isLight,
                                          username: widget.username,
                                          refreshTrigger: trigger,
                                          actionKey: _todayPlanChartKey,
                                        );
                                      },
                                    );
                                    Widget countdownSection =
                                        CountdownSectionWidget(
                                            historyKey: _countdownHistoryKey,
                                            countdowns: _countdowns,
                                            username: widget.username,
                                            isLight: isLight,
                                            addKey: _addCountdownKey,
                                            onDataChanged: () {
                                              _loadAllData();
                                              _timelineRevision.value++;
                                            });
                                    Widget todoSection =
                                        ValueListenableBuilder<int>(
                                      valueListenable:
                                          _todoUpdateSignalNotifier,
                                      builder: (context, signal, _) {
                                        return TodoSectionWidget(
                                          folderKey: _todoFolderKey,
                                          historyKey: _todoHistoryKey,
                                          todos: _todos,
                                          highlightedTodoIds:
                                              _updatedByOthersTodoIds,
                                          remoteUpdateHighlightSignal:
                                              _remoteTodoHighlightSignal,
                                          todoGroups: _todoGroups,
                                          conflicts: _latestSyncConflicts,
                                          username: widget.username,
                                          isLight: isLight,
                                          onTeamChanged: (teamUuid, teamName) {
                                            setState(() {
                                              _currentSelectedTeamUuid =
                                                  teamUuid;
                                              _currentSelectedTeamName =
                                                  teamName;
                                            });
                                          },
                                          onGroupsChanged: (newGroups) async {
                                            setState(() => _todoGroups =
                                                newGroups
                                                    .where((g) => !g.isDeleted)
                                                    .toList());
                                            final allGroups =
                                                await StorageService
                                                    .getTodoGroups(
                                                        widget.username);
                                            for (var g in newGroups) {
                                              int idx = allGroups.indexWhere(
                                                  (x) => x.id == g.id);
                                              if (idx != -1) {
                                                if (g.updatedAt >=
                                                    allGroups[idx].updatedAt) {
                                                  allGroups[idx] = g;
                                                }
                                              } else {
                                                allGroups.add(g);
                                              }
                                            }
                                            await StorageService.saveTodoGroups(
                                                widget.username, allGroups,
                                                sync: true);
                                          },
                                          onTodosChanged: _handleTodosChanged,
                                          initialSelectedTeamUuid:
                                              _currentSelectedTeamUuid,
                                          onRefreshRequested: _handleManualSync,
                                          onLLMResultsParsed: (results,
                                              imagePath,
                                              originalText,
                                              tUuid,
                                              tName) {
                                            _navigateToTodoConfirm(
                                                results,
                                                imagePath,
                                                originalText,
                                                tUuid,
                                                tName);
                                          },
                                        );
                                      },
                                    );
                                    Widget screenTimeSection = RepaintBoundary(
                                      child: KeyedSubtree(
                                        key: _screenTimeCardKey,
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            SectionHeader(
                                                title: "屏幕时间 (今日汇总)",
                                                icon: Icons.timer_outlined,
                                                isLight: isLight),
                                            ScreenTimeCard(
                                              stats: _screenTimeStats,
                                              hasPermission:
                                                  _hasUsagePermission,
                                              isLoading: _isLoadingScreenTime,
                                              lastSyncTime: _lastScreenTimeSync,
                                              onOpenSettings: () async {
                                                if (AppPlatform.isAndroid ||
                                                    AppPlatform.isIOS) {
                                                  await _permissionCoordinator
                                                      .request(
                                                    AppPermissionKind
                                                        .usageStats,
                                                    onResult: (_) =>
                                                        _initScreenTime(),
                                                  );
                                                } else {
                                                  _initScreenTime();
                                                }
                                              },
                                              onViewDetail: () {
                                                PageTransitions.pushFromRect(
                                                  context: context,
                                                  page: ScreenTimeDetailScreen(
                                                      todayStats:
                                                          _screenTimeStats),
                                                  sourceKey: _screenTimeCardKey,
                                                );
                                              },
                                            ),
                                          ],
                                        ),
                                      ),
                                    );
                                    Widget mathSection = RepaintBoundary(
                                      child: KeyedSubtree(
                                        key: _mathCardKey,
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            SectionHeader(
                                                title: "数学测验",
                                                icon: Icons.functions,
                                                isLight: isLight),
                                            MathStatsCard(
                                                stats: _mathStats,
                                                onTap: () async {
                                                  await PageTransitions
                                                      .pushFromRect(
                                                    context: context,
                                                    page: MathMenuScreen(
                                                        username:
                                                            widget.username),
                                                    sourceKey: _mathCardKey,
                                                  );
                                                  _loadAllData(deferred: true);
                                                }),
                                          ],
                                        ),
                                      ),
                                    );
                                    Widget timelineSection = KeyedSubtree(
                                      key: _timelineCardKey,
                                      child: ValueListenableBuilder<int>(
                                        valueListenable: _timelineRevision,
                                        builder: (context, trigger, _) {
                                          return PersonalTimelineSection(
                                            username: widget.username,
                                            isLight: isLight,
                                            refreshTrigger: trigger,
                                          );
                                        },
                                      ),
                                    );

                                    Widget pomodoroSection = RepaintBoundary(
                                      child: ValueListenableBuilder<int>(
                                        valueListenable: _pomodoroRevision,
                                        builder: (context, trigger, _) {
                                          return KeyedSubtree(
                                            key: _pomodoroCardKey,
                                            child: PomodoroTodaySection(
                                              username: widget.username,
                                              isLight: isLight,
                                              refreshTrigger: trigger,
                                              onTap: () async {
                                                await PageTransitions
                                                    .pushFromRect(
                                                  context: context,
                                                  page: PomodoroScreen(
                                                    username: widget.username,
                                                    initialTab: 1,
                                                  ),
                                                  sourceKey: _pomodoroCardKey,
                                                );
                                                _pomodoroRevision.value++;
                                                _loadAllData();
                                              },
                                            ),
                                          );
                                        },
                                      ),
                                    );

                                    Widget planBlockSection = RepaintBoundary(
                                      child: ValueListenableBuilder<int>(
                                        valueListenable: _scheduleRevision,
                                        builder: (context, trigger, _) {
                                          return PlanBlockTodaySection(
                                            chartKey: _todayPlanChartKey,
                                            username: widget.username,
                                            isLight: isLight,
                                            refreshTrigger: trigger,
                                            onTap: () async {
                                              await Navigator.of(context).push(
                                                PageTransitions.material(
                                                  builder: (_) =>
                                                      TodoPlanScreen(
                                                          username:
                                                              widget.username),
                                                ),
                                              );
                                              _scheduleRevision.value++;
                                              _loadAllData();
                                            },
                                          );
                                        },
                                      ),
                                    );

                                    Map<String, Widget> sectionsMap = {
                                      'banners': ValueListenableBuilder<int>(
                                        valueListenable: _pomodoroTickNotifier,
                                        builder: (_, __, ___) =>
                                            _buildUniversalBanner(isLight),
                                      ),
                                      'courses': courseSection,
                                      'countdowns': countdownSection,
                                      'todos': todoSection,
                                      'planBlocks': planBlockSection,
                                      'screenTime': screenTimeSection,
                                      'math': mathSection,
                                      'pomodoro': pomodoroSection,
                                      'timeline': timelineSection,
                                      'habits': RepaintBoundary(
                                        child: KeyedSubtree(
                                          key: _habitsCardKey,
                                          child: ValueListenableBuilder<int>(
                                            valueListenable: _habitsRevision,
                                            builder: (context, trigger, _) {
                                              return HabitTodaySection(
                                                username: widget.username,
                                                isLight: isLight,
                                                compact: true,
                                                displayLimit:
                                                    _habitDisplayLimit,
                                                refreshTrigger: trigger,
                                                onTap: () async {
                                                  await PageTransitions
                                                      .pushFromRect(
                                                    context: context,
                                                    page: HabitCenterScreen(
                                                      username: widget.username,
                                                    ),
                                                    sourceKey: _habitsCardKey,
                                                    sourceBorderRadius:
                                                        BorderRadius.circular(
                                                            24),
                                                  );
                                                  _habitsRevision.value++;
                                                  _loadAllData();
                                                },
                                              );
                                            },
                                          ),
                                        ),
                                      ),
                                    };

                                    bool isCourseEmpty =
                                        (_dashboardCourseData['courses'] ==
                                                    null ||
                                                (_dashboardCourseData['courses']
                                                        as List)
                                                    .isEmpty) ||
                                            (_dashboardCourseData['title']
                                                    ?.toString()
                                                    .contains('天后') ??
                                                false) ||
                                            _dashboardCourseData['title'] ==
                                                '最近无课' ||
                                            _dashboardCourseData['title'] ==
                                                '暂无课表';

                                    bool hasNoCourse = isCourseEmpty;
                                    if (isCourseEmpty) {
                                      final nowMs =
                                          DateTime.now().millisecondsSinceEpoch;
                                      final tomorrowEndMs = DateTime(
                                              DateTime.now().year,
                                              DateTime.now().month,
                                              DateTime.now().day + 2)
                                          .millisecondsSinceEpoch;
                                      bool hasActivePlans = _planBlocks.any(
                                          (b) =>
                                              !b.isDeleted &&
                                              b.endTime > nowMs &&
                                              b.startTime < tomorrowEndMs);
                                      bool hasActiveTodos = _todos.any((t) {
                                        if (t.isDeleted ||
                                            t.dueDate == null ||
                                            t.isAllDayTask) {
                                          return false;
                                        }
                                        final startMs =
                                            t.createdDate ?? t.createdAt;
                                        return startMs > 0 &&
                                            t.dueDate!.millisecondsSinceEpoch >
                                                nowMs &&
                                            startMs < tomorrowEndMs;
                                      });
                                      if (hasActivePlans || hasActiveTodos) {
                                        hasNoCourse = false;
                                      }
                                    }

                                    if (!isTablet) {
                                      List<String> tab1Order =
                                          List<String>.from(
                                              _mobileHomeSections);
                                      if (hasNoCourse) {
                                        if (_noCourseBehavior == 'hide') {
                                          tab1Order.remove('courses');
                                        } else if (_noCourseBehavior ==
                                            'bottom') {
                                          tab1Order.remove('courses');
                                          tab1Order.add('courses');
                                        }
                                      }

                                      List<Widget> tab1Widgets = tab1Order
                                          .where((key) =>
                                              (_sectionVisibility[key] ??
                                                  true) &&
                                              sectionsMap.containsKey(key))
                                          .map((key) => Padding(
                                              padding: const EdgeInsets.only(
                                                  bottom: 24.0),
                                              child: sectionsMap[key]!))
                                          .toList();

                                      List<String> tab3WidgetsConfig =
                                          List<String>.from(
                                              _mobileFocusSections);

                                      List<Widget> tab3Widgets =
                                          tab3WidgetsConfig
                                              .where((key) =>
                                                  (_sectionVisibility[key] ??
                                                      true) &&
                                                  sectionsMap.containsKey(key))
                                              .map((key) => Padding(
                                                  padding:
                                                      const EdgeInsets.only(
                                                          bottom: 24.0),
                                                  child: sectionsMap[key]!))
                                              .toList();

                                      return IndexedStack(
                                        index: _selectedTabIndex == 2 ? 1 : 0,
                                        children: [
                                          // Tab 1: 重要日、课程、待办
                                          RepaintBoundary(
                                            child: SingleChildScrollView(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 16,
                                                      vertical: 16),
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  ...tab1Widgets,
                                                  if (_wallpaperCopyright !=
                                                          null &&
                                                      _wallpaperCopyright!
                                                          .isNotEmpty)
                                                    _buildWallpaperCopyright(
                                                        isLight),
                                                  const SizedBox(
                                                      height: 100), // 为悬浮底栏留出空间
                                                ],
                                              ),
                                            ),
                                          ),
                                          // Tab 2 (mapped to index 2 in bottom bar): 今日专注、屏幕时间
                                          RepaintBoundary(
                                            child: SingleChildScrollView(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 16,
                                                      vertical: 16),
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  ...tab3Widgets,
                                                  if (_wallpaperCopyright !=
                                                          null &&
                                                      _wallpaperCopyright!
                                                          .isNotEmpty)
                                                    _buildWallpaperCopyright(
                                                        isLight),
                                                  const SizedBox(
                                                      height: 100), // 为悬浮底栏留出空间
                                                ],
                                              ),
                                            ),
                                          ),
                                        ],
                                      );
                                    }

                                    // Tablet Layout
                                    List<String> currentLeft =
                                        List.from(_leftSections);
                                    List<String> currentRight =
                                        List.from(_rightSections);

                                    void applyNoCourseBehavior(
                                        List<String> targetList) {
                                      if (hasNoCourse &&
                                          targetList.contains('courses')) {
                                        if (_noCourseBehavior == 'hide') {
                                          targetList.remove('courses');
                                        } else if (_noCourseBehavior ==
                                            'bottom') {
                                          targetList.remove('courses');
                                          targetList.add('courses');
                                        }
                                      }
                                    }

                                    applyNoCourseBehavior(currentLeft);
                                    applyNoCourseBehavior(currentRight);

                                    List<Widget> buildColumnWidgets(
                                        List<String> keys) {
                                      return keys
                                          .where((key) =>
                                              (_sectionVisibility[key] ??
                                                  true) &&
                                              sectionsMap.containsKey(key))
                                          .map((key) => Padding(
                                              padding: const EdgeInsets.only(
                                                  bottom: 24.0),
                                              child: sectionsMap[key]!))
                                          .toList();
                                    }

                                    List<Widget> leftWidgets =
                                        buildColumnWidgets(currentLeft);
                                    List<Widget> rightWidgets =
                                        buildColumnWidgets(currentRight);

                                    return SingleChildScrollView(
                                      padding: EdgeInsets.symmetric(
                                          horizontal: isTablet ? 32 : 16,
                                          vertical: 16),
                                      child: Align(
                                        alignment: Alignment.topCenter,
                                        child: ConstrainedBox(
                                          constraints: const BoxConstraints(
                                              maxWidth: 1400),
                                          child: Column(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              isTablet
                                                  ? Row(
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .start,
                                                      children: [
                                                        Expanded(
                                                            flex: 10,
                                                            child: Column(
                                                                crossAxisAlignment:
                                                                    CrossAxisAlignment
                                                                        .start,
                                                                children:
                                                                    leftWidgets)),
                                                        if (rightWidgets
                                                            .isNotEmpty)
                                                          const SizedBox(
                                                              width: 40),
                                                        if (rightWidgets
                                                            .isNotEmpty)
                                                          Expanded(
                                                              flex: 11,
                                                              child: Column(
                                                                  crossAxisAlignment:
                                                                      CrossAxisAlignment
                                                                          .start,
                                                                  children:
                                                                      rightWidgets)),
                                                      ],
                                                    )
                                                  : Column(
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .start,
                                                      children: [
                                                        ...leftWidgets,
                                                        ...rightWidgets,
                                                      ],
                                                    ),
                                              if (_wallpaperCopyright != null &&
                                                  _wallpaperCopyright!
                                                      .isNotEmpty)
                                                _buildWallpaperCopyright(
                                                    isLight),
                                            ],
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                                ),
                          // 🚀 移动端底部悬浮胶囊底栏 (始终显示，不受加载状态影响)
                          if (!isTablet)
                            Positioned(
                              left: 0,
                              right: 0,
                              bottom: 0,
                              child: _buildCustomBottomBar(isDarkMode, isLight),
                            ),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: null,
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          FloatingActionButton.small(
            key: _fabPomodoroKey,
            heroTag: 'fab_pomodoro',
            onPressed: () async {
              await PageTransitions.pushFromRect(
                context: context,
                page: PomodoroScreen(username: widget.username),
                sourceKey: _fabPomodoroKey,
                sourceBorderRadius: const BorderRadius.all(Radius.circular(16)),
              );
              if (mounted) {
                _pomodoroRevision.value++;
                _timelineRevision.value++;
                _loadAllData(deferred: true);
              }
            },
            tooltip: '番茄钟',
            child: const Text('🍅', style: TextStyle(fontSize: 18)),
          ),
          const SizedBox(height: 8),
          FloatingActionButton.extended(
            key: _fabTodoKey,
            heroTag: 'fab_todo',
            onPressed: () => PageTransitions.pushFromRect(
              context: context,
              page: AddTodoScreen(
                todoGroups: _todoGroups,
                initialTeamUuid: _currentSelectedTeamUuid,
                initialTeamName: _currentSelectedTeamName,
                onFixedScheduleAdded: (item) async {
                  await StorageService.saveFixedSchedules(
                    widget.username,
                    [item],
                  );
                  if (mounted) {
                    _scheduleRevision.value++;
                    _timelineRevision.value++;
                    await _loadAllData(deferred: true);
                  }
                },
                onTodoAdded: (todo) async {
                  final allTodos =
                      await StorageService.getTodos(widget.username);
                  allTodos.add(todo);
                  await StorageService.saveTodos(widget.username, allTodos);
                  if (todo.teamUuid != null) {
                    PomodoroSyncService.instance
                        .sendTeamUpdateSignal(todo.teamUuid!);
                  }
                  await _saveTodosToSharedFile(allTodos);
                  FloatWindowService.triggerReminderCheck();
                  FloatWindowService.invalidateSlotCache();
                  _syncTodoNotification();
                  _rescheduleAlarms();
                  await WidgetService.updateTodoWidget(allTodos);
                  if (mounted) {
                    await _loadAllData(deferred: true);
                    setState(() {});
                  }
                },
                onTodosBatchAdded: (todos) async {
                  final allTodos =
                      await StorageService.getTodos(widget.username);
                  allTodos.addAll(todos);
                  await StorageService.saveTodos(widget.username, allTodos);
                  final updatedTeamUuid = todos
                      .firstWhere((t) => t.teamUuid != null,
                          orElse: () => todos.first)
                      .teamUuid;
                  if (updatedTeamUuid != null) {
                    PomodoroSyncService.instance
                        .sendTeamUpdateSignal(updatedTeamUuid);
                  }
                  await _saveTodosToSharedFile(allTodos);
                  FloatWindowService.triggerReminderCheck();
                  FloatWindowService.invalidateSlotCache();
                  _syncTodoNotification();
                  _rescheduleAlarms();
                  await WidgetService.updateTodoWidget(allTodos);
                  if (mounted) await _loadAllData(deferred: true);
                },
                onLLMResultsParsed:
                    (results, imagePath, originalText, tUuid, tName) {
                  Navigator.pop(context);
                  _navigateToTodoConfirm(
                      results, imagePath, originalText, tUuid, tName);
                },
              ),
              sourceKey: _fabTodoKey,
              sourceBorderRadius: const BorderRadius.all(Radius.circular(16)),
            ),
            icon: const Icon(Icons.add_task),
            label: const Text("记待办"),
          ),
          const SizedBox(height: 100), // 避开底部的悬浮导航栏
        ],
      ),
    );

    if (isTablet) {
      return mainScreen;
    }

    return ZoomDrawer(
      menuScreen: HomeDrawerMenu(
        username: widget.username,
        timeSalutation: _timeSalutation,
        onSettings: () {
          Future.delayed(const Duration(milliseconds: 350), () async {
            if (!context.mounted) return;
            await PageTransitions.pushFromRect(
              context: context,
              page: const SettingsPage(),
              sourceKey: _settingsButtonKey,
            );
            if (!mounted) return;
            _loadSectionPreferences();
            _loadSemesterSettings();
            await _loadHomeTextConfig();
            _loadAllData(deferred: true);
          });
        },
        onAiAssistant: () {
          Future.delayed(const Duration(milliseconds: 300), () {
            if (!mounted) return;
            _openAiAssistantFromAppBar();
          });
        },
        onTeams: () {
          Future.delayed(const Duration(milliseconds: 300), () async {
            if (!context.mounted) return;
            await PageTransitions.pushFromRect(
              context: context,
              page: TeamManagementScreen(username: widget.username),
              sourceKey: _teamsButtonKey,
            );
            if (!mounted) return;
            final unreadBackgroundNotifications =
                await BackgroundNotificationService
                    .getUnreadBackgroundNotifications();
            final notificationIds = unreadBackgroundNotifications
                .map((e) => e['id'])
                .whereType<num>()
                .map((e) => e.toInt())
                .toList();
            await ApiService.markNotificationsRead(notificationIds);
            await BackgroundNotificationService
                .clearUnreadBackgroundNotifications();
            await _fetchTeamPendingCount();
            _loadAllData(deferred: true);
          });
        },
        teamPendingCount: _teamPendingCount,
        hasTeamConflictDot: _hasTeamConflictDot,
        onTimeline: () {
          Future.delayed(const Duration(milliseconds: 300), () async {
            if (!context.mounted) return;
            await PageTransitions.pushFromRect(
              context: context,
              page: PersonalTimelineScreen(username: widget.username),
              sourceKey: GlobalKey(),
            );
          });
        },
        onScreenTime: () {
          Future.delayed(const Duration(milliseconds: 300), () async {
            if (!context.mounted) return;
            await PageTransitions.pushFromRect(
              context: context,
              page: TimeLogScreen(username: widget.username),
              sourceKey: GlobalKey(),
            );
          });
        },
        onPlanCenter: () {
          Future.delayed(const Duration(milliseconds: 300), () async {
            if (!context.mounted) return;
            await PageTransitions.pushFromRect(
              context: context,
              page: TodoPlanScreen(username: widget.username),
              sourceKey: GlobalKey(),
            );
            _loadSemesterSettings();
            _loadAllData(deferred: true);
          });
        },
        onHabits: () {
          Future.delayed(const Duration(milliseconds: 300), () async {
            if (!context.mounted) return;
            await PageTransitions.pushFromRect(
              context: context,
              page: HabitCenterScreen(username: widget.username),
              sourceKey: _habitsCardKey,
            );
            _habitsRevision.value++;
            _loadAllData(deferred: true);
          });
        },
        onGuide: () {
          Future.delayed(const Duration(milliseconds: 350), () {
            if (!context.mounted) return;
            Navigator.of(context, rootNavigator: true).push(
              PageTransitions.material(
                builder: (context) => FeatureGuideScreen(
                  isManualReview: true,
                  loggedInUser: widget.username,
                ),
              ),
            );
          });
        },
        onUpdate: () {
          Future.delayed(const Duration(milliseconds: 300), () {
            if (!context.mounted) return;
            UpdateService.checkUpdateAndPrompt(context, isManual: true);
          });
        },
      ),
      mainScreen: mainScreen,
      borderRadius: 24.0,
      showShadow: true,
      angle: 0.0,
      drawerShadowsBackgroundColor: Colors.grey.shade300,
      slideWidth: MediaQuery.of(context).size.width * 0.72,
    );
  }

  Widget _buildWallpaperCopyright(bool isLight) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.only(top: 16.0, bottom: 32.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _wallpaperCopyright!,
              style: TextStyle(
                fontSize: 12,
                color: isLight
                    ? Colors.white.withValues(alpha: 0.7)
                    : Colors.grey[600],
                fontStyle: FontStyle.italic,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            GestureDetector(
              onTap: _downloadWallpaper,
              child: Text(
                '喜欢该壁纸？点此下载',
                style: TextStyle(
                  fontSize: 12,
                  color: isLight
                      ? Colors.white.withValues(alpha: 0.9)
                      : Theme.of(context).colorScheme.primary,
                  decoration: TextDecoration.underline,
                  decorationColor: isLight
                      ? Colors.white.withValues(alpha: 0.9)
                      : Theme.of(context).colorScheme.primary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _downloadWallpaper() async {
    if (_wallpaperUrl == null) return;
    try {
      final wallpaperUrl = _wallpaperUrl!;
      late final List<int> bytes;
      late final String ext;

      if (_wallpaperUrl!.startsWith('http://') ||
          _wallpaperUrl!.startsWith('https://')) {
        final response = await http.get(Uri.parse(wallpaperUrl));
        if (response.statusCode != 200) {
          throw Exception('HTTP ${response.statusCode}');
        }
        bytes = response.bodyBytes;
        ext = _wallpaperExtension(wallpaperUrl);
      } else if (wallpaperUrl.startsWith('assets/')) {
        final data = await rootBundle.load(wallpaperUrl);
        bytes = data.buffer.asUint8List();
        ext = _wallpaperExtension(wallpaperUrl);
      } else if (wallpaperUrl.startsWith('data:')) {
        final data = UriData.parse(wallpaperUrl);
        bytes = data.contentAsBytes();
        ext = data.mimeType.split('/').last;
      } else if (_isLocalFilePath(_wallpaperUrl!)) {
        throw Exception('当前平台无法直接下载本地路径壁纸');
      } else {
        throw Exception('不支持的壁纸来源');
      }

      final ts = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final savedPath = await BrowserFileService.saveBytesFile(
        Uint8List.fromList(bytes),
        'wallpaper_$ts.$ext',
        mimeType: 'image/$ext',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已保存到 $savedPath')),
        );
      }
    } catch (e) {
      // debugPrint('下载壁纸失败: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('下载失败: $e')),
        );
      }
    }
  }

  String _wallpaperExtension(String url) {
    final ext = url.split('?').first.split('.').last.toLowerCase();
    if (ext == 'png' || ext == 'webp' || ext == 'gif') return ext;
    return 'jpg';
  }

  Widget _buildCustomBottomBar(bool isDarkMode, bool isLight) {
    final Color primaryColor =
        _wallpaperDominantColor ?? Theme.of(context).colorScheme.primary;
    final Color inactiveColor =
        (isLight || !isDarkMode) ? Colors.black87 : Colors.white70;
    final double bottomPadding = MediaQuery.of(context).padding.bottom;

    return Container(
      height: 60 + (bottomPadding > 0 ? bottomPadding * 0.5 : 6),
      margin: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      decoration: BoxDecoration(
        color: isDarkMode
            ? Colors.white.withValues(alpha: 0.18)
            : Colors.white.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(40),
        border: Border.all(
          color: isDarkMode
              ? Colors.white.withValues(alpha: 0.08)
              : Colors.black.withValues(alpha: 0.05),
          width: 0.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(40),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              children: [
                Expanded(
                  child: _buildTabItem(0, Icons.dashboard_rounded, '首页',
                      primaryColor, inactiveColor),
                ),
                SizedBox(
                  width: 64,
                  child: Center(child: _buildCourseCenterButton(primaryColor)),
                ),
                Expanded(
                  child: _buildTabItem(2, Icons.adjust_rounded, '专注',
                      primaryColor, inactiveColor),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTabItem(
      int index, IconData icon, String label, Color primary, Color inactive) {
    bool isSelected = _selectedTabIndex == index;
    return InkWell(
      onTap: () {
        setState(() => _selectedTabIndex = index);
        if (index == 2) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _checkFocusTabCoachMarks();
          });
        }
      },
      splashColor: Colors.transparent,
      highlightColor: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              color: isSelected ? primary : inactive,
              size: 24,
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? primary : inactive,
                fontSize: 10,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCourseCenterButton(Color primary) {
    return SizedBox(
      width: 48,
      height: 48,
      child: InkWell(
        onTap: () {
          PageTransitions.pushFromRect(
            context: context,
            page: WeeklyCourseScreen(username: widget.username),
            sourceKey: _courseCenterKey,
          );
        },
        borderRadius: BorderRadius.circular(24),
        child: Container(
          key: _courseCenterKey,
          decoration: BoxDecoration(
            color: primary,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: primary.withValues(alpha: 0.3),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: const Icon(
            Icons.calendar_today_rounded,
            color: Colors.white,
            size: 22,
          ),
        ),
      ),
    );
  }

  // 🚀 辅助方法：内容级深度比较，用于按需刷新
  bool _isListEqual(List a, List b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  bool _isMapEqual(Map a, Map b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (final key in a.keys) {
      if (!b.containsKey(key) || a[key] != b[key]) return false;
    }
    return true;
  }

  Widget _buildDashboardSkeleton(bool isLight) {
    final baseColor =
        isLight ? Colors.white.withValues(alpha: 0.3) : Colors.grey[800]!;
    return SingleChildScrollView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          _buildSkeletonCard(baseColor, height: 120),
          const SizedBox(height: 16),
          _buildSkeletonCard(baseColor, height: 180),
          const SizedBox(height: 16),
          _buildSkeletonCard(baseColor, height: 240),
        ],
      ),
    );
  }

  Widget _buildSkeletonCard(Color color, {required double height}) {
    return Container(
      width: double.infinity,
      height: height,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(16),
      ),
    );
  }
}
