part of 'home_dashboard.dart';

// ignore_for_file: annotate_overrides

mixin _HomeDashboardViewMixin
    on
        _HomeDashboardStateBase,
        _HomeDashboardWallpaperMixin,
        _HomeDashboardViewActionsMixin {
  late final Listenable _todoSectionListenable = Listenable.merge([
    _todosNotifier,
    _groupsNotifier,
  ]);
  late final Listenable _agendaSectionListenable = Listenable.merge([
    _scheduleRevision,
    _todosNotifier,
  ]);
  late final Listenable _bannerSectionListenable = Listenable.merge([
    _pomodoroTickNotifier,
    _todosNotifier,
    _courseDataNotifier,
    _scheduleRevision,
  ]);

  Widget build(BuildContext context) {
    bool isDarkMode = Theme.of(context).brightness == Brightness.dark;
    bool showWallpaper = !isDarkMode && _wallpaperShow && _wallpaperUrl != null;
    bool isLight = showWallpaper;
    final wallpaperUrl = _wallpaperUrl;
    final localWallpaperProvider =
        showWallpaper && wallpaperUrl != null && _isLocalFilePath(wallpaperUrl)
        ? _localWallpaperProviderFor(wallpaperUrl)
        : null;
    final Size screenSize = MediaQuery.sizeOf(context);
    final double screenWidth = screenSize.width;
    final bool isTablet = screenWidth >= 768;
    if (!showWallpaper) {
      _schedulePreblurredWallpaperSync(
        provider: null,
        url: null,
        viewportSize: Size.zero,
        showWallpaper: false,
      );
    } else if (_lastPreblurredProvider != null &&
        _lastPreblurredUrl == wallpaperUrl) {
      _schedulePreblurredWallpaperSync(
        provider: _lastPreblurredProvider,
        url: wallpaperUrl,
        viewportSize: screenSize,
        showWallpaper: true,
      );
    }
    final double drawerWidth = homeDrawerSlideWidthFor(
      screenWidth: screenWidth,
      isWide: isTablet,
    );
    final double topSystemInset = MediaQuery.paddingOf(context).top;
    final double bottomSystemInset = MediaQuery.viewPaddingOf(context).bottom;
    final Brightness cardBackgroundBrightness = isDarkMode
        ? Brightness.dark
        : Brightness.light;

    final mainScreen = Scaffold(
      // 让宽屏底栏叠在页面背景上，壁纸不会被 Scaffold 的底栏槽位截断。
      extendBody: true,
      resizeToAvoidBottomInset: !_isSearchOpen, // 🚀 关键：搜索时锁定背景，防止位移卡顿
      backgroundColor: (showWallpaper && !AppPlatform.isWindows)
          ? Colors.transparent
          : Theme.of(context).colorScheme.surface,
      body: Stack(
        key: _dashboardBackdropViewportKey,
        children: [
          if (showWallpaper && wallpaperUrl != null)
            Positioned.fill(
              child: IgnorePointer(
                child: _buildWallpaperWidget(
                  wallpaperUrl: wallpaperUrl,
                  localWallpaperProvider: localWallpaperProvider,
                  extractColor: true,
                ),
              ),
            ),
          SafeArea(
            // 仅避让顶部状态栏。列表需要继续绘制到 Android 手势导航区
            // 后方，末尾的滚动余量再保证卡片操作不会被底栏遮挡。
            top: false,
            bottom: false,
            child: FloatingGlassPinnedHeaderLayout(
              fadeContent: !showWallpaper,
              initialHeaderExtent:
                  (_selectedTabIndex != _homeFocusTabIndex || isTablet)
                  ? (78.0 + topSystemInset)
                  : 0.0,
              onHeaderExtentChanged: (extent) {
                if (isTablet) return;
                final target = _selectedTabIndex == _homeFocusTabIndex
                    ? _focusHeaderExtentNotifier
                    : _homeHeaderExtentNotifier;
                if ((extent - target.value).abs() > 0.5) {
                  target.value = extent;
                }
              },
              header: ValueListenableBuilder<int>(
                valueListenable: _selectedTabIndexNotifier,
                builder: (context, selectedTabIndex, _) {
                  final showTopBar =
                      selectedTabIndex != _homeFocusTabIndex || isTablet;
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildSemesterProgressBar(isLight),

                      if (showTopBar)
                        ValueListenableBuilder<bool>(
                          valueListenable: _isSyncingNotifier,
                          builder: (context, isSyncing, _) => HomeAppBar(
                            username: widget.username,
                            onCreateRelatedTodo: _saveTodoLinkedToFixedSchedule,
                            timeSalutation: _timeSalutation,
                            currentGreeting: _currentGreeting,
                            semesterWeek: _currentSemesterWeek,
                            textConfig: HomeTextConfig(
                              customTimeSalutation:
                                  _homeTextConfig['customTimeSalutation']
                                      as String?,
                              dateFormat:
                                  _homeTextConfig['dateFormat'] as String?,
                              usernameFormat:
                                  _homeTextConfig['usernameFormat'] as String?,
                            ),
                            isLight: isLight,
                            isSyncing: isSyncing,
                            onSync: _showSyncOptionsDialog,
                            onSearch: _showGlobalSearch,
                            onAiAssistant: _openAiAssistantFromAppBar,
                            searchKey: _searchButtonKey,
                            syncKey: _syncButtonKey,
                            teamsKey: _teamsButtonKey,
                            aiKey: _aiButtonKey,
                            settingsKey: _settingsButtonKey,
                            menuKey: _menuKey,
                            showMenuButton: true,
                            courseKey: _courseButtonKey,
                            showCourseButton: isTablet,
                            teamPendingCount: _teamPendingCount, // 🚀 绑定计数
                            hasTeamConflictDot: _hasTeamConflictDot,
                            onTeams: () async {
                              await PageTransitions.pushFromRect(
                                context: context,
                                page: TeamManagementScreen(
                                  username: widget.username,
                                ),
                                sourceKey: _teamsButtonKey,
                              );
                              final unreadBackgroundNotifications =
                                  await BackgroundNotificationService.getUnreadBackgroundNotifications();
                              final notificationIds =
                                  unreadBackgroundNotifications
                                      .map((e) => e['id'])
                                      .whereType<num>()
                                      .map((e) => e.toInt())
                                      .toList();
                              await ApiService.markNotificationsRead(
                                notificationIds,
                              );
                              await BackgroundNotificationService.clearUnreadBackgroundNotifications();
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
                        ),

                      // 🚀 Uni-Sync 4.0: 全局链路诊断横幅
                      if (showTopBar)
                        SyncStatusBanner(
                          onDiagnosticRequested: _showLinkDiagnostics,
                        ),

                      // DEBUG: 检查状态
                      // if (_activeAnnouncement != null) Text("DEBUG: Announcement exists: ${_activeAnnouncement!.title}"),

                      // 🚀 Uni-Sync 4.0: 团队置顶公告
                      if (_activeAnnouncement != null && showTopBar)
                        StickyAnnouncementBanner(
                          announcement: _activeAnnouncement!,
                          onAcknowledge: () async {
                            final uuid = _activeAnnouncement!.uuid;
                            setState(() => _activeAnnouncement = null);
                            await ApiService.markAnnouncementAsRead(uuid);
                          },
                        ),

                      if (_isThirtyDayChallengeActive && showTopBar)
                        _buildChallengeParticipationBanner(isLight),

                      // 待确认事项入口卡片（从图片识别来）
                      _buildPendingTodoConfirmCard(isLight),
                    ],
                  );
                },
              ),
              bodyListenableBuilder: (context, headerExtentListenable) => OptionalLiquidGlassBackdropScope(
                isSolidBackground: !showWallpaper,
                blurredWallpaperListenable: showWallpaper
                    ? _preblurredWallpaperController.snapshotListenable
                    : null,
                viewportKey: _dashboardBackdropViewportKey,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ValueListenableBuilder<bool>(
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
                                ? ValueListenableBuilder<double>(
                                    valueListenable: headerExtentListenable,
                                    builder: (context, headerExtent, _) =>
                                        _buildDashboardSkeleton(
                                          isLight,
                                          topPadding:
                                              homeDashboardPhoneScrollTopPadding(
                                                headerExtent: headerExtent,
                                                topInset: topSystemInset,
                                              ),
                                        ),
                                  )
                                : LayoutBuilder(
                                    builder: (context, constraints) {
                                      Widget wrapSectionBoundary(
                                        Widget child,
                                      ) => AppPlatform.isWindows
                                          ? child
                                          : RepaintBoundary(child: child);
                                      // RepaintBoundary isolates each section's
                                      // display-list cache without blocking
                                      // nested BackdropFilter / LiquidGlass
                                      // layers from sampling the wallpaper.
                                      const addListRepaintBoundaries = true;
                                      Widget
                                      buildCountdown() => wrapSectionBoundary(
                                        ValueListenableBuilder<
                                          List<CountdownItem>
                                        >(
                                          valueListenable: _countdownsNotifier,
                                          builder: (context, countdowns, _) =>
                                              CountdownSectionWidget(
                                                historyKey:
                                                    _countdownHistoryKey,
                                                countdowns: countdowns,
                                                dataRevision:
                                                    _countdownsDataRevision,
                                                username: widget.username,
                                                isLight: isLight,
                                                addKey: _addCountdownKey,
                                                onDataChanged: () {
                                                  _loadAllData(
                                                    domains: const {
                                                      DataRefreshDomain
                                                          .countdowns,
                                                    },
                                                  );
                                                  _timelineRevision.value++;
                                                },
                                              ),
                                        ),
                                      );
                                      Widget buildTodo() => wrapSectionBoundary(
                                        AnimatedBuilder(
                                          animation: _todoSectionListenable,
                                          builder: (context, _) {
                                            return TodoSectionWidget(
                                              folderKey: _todoFolderKey,
                                              historyKey: _todoHistoryKey,
                                              todos: _todos,
                                              dataRevision: _todoDataRevision,
                                              highlightedTodoIds:
                                                  _updatedByOthersTodoIds,
                                              remoteUpdateHighlightSignal:
                                                  _remoteTodoHighlightSignal,
                                              todoGroups: _todoGroups,
                                              conflicts: _latestSyncConflicts,
                                              username: widget.username,
                                              isLight: isLight,
                                              onTeamChanged:
                                                  (teamUuid, teamName) {
                                                    setState(() {
                                                      _currentSelectedTeamUuid =
                                                          teamUuid;
                                                      _currentSelectedTeamName =
                                                          teamName;
                                                    });
                                                  },
                                              onGroupsChanged: (newGroups) async {
                                                final allGroups =
                                                    await StorageService.getTodoGroups(
                                                      widget.username,
                                                    );
                                                final groupIndexById =
                                                    <String, int>{};
                                                for (
                                                  var index = 0;
                                                  index < allGroups.length;
                                                  index++
                                                ) {
                                                  groupIndexById.putIfAbsent(
                                                    allGroups[index].id,
                                                    () => index,
                                                  );
                                                }
                                                for (final group in newGroups) {
                                                  final index =
                                                      groupIndexById[group.id];
                                                  if (index == null) {
                                                    groupIndexById[group.id] =
                                                        allGroups.length;
                                                    allGroups.add(group);
                                                  } else if (group.updatedAt >=
                                                      allGroups[index]
                                                          .updatedAt) {
                                                    allGroups[index] = group;
                                                  }
                                                }
                                                await StorageService.saveTodoGroups(
                                                  widget.username,
                                                  allGroups,
                                                  sync: true,
                                                );
                                                if (!mounted) return;
                                                setState(() {
                                                  _todoGroups = newGroups
                                                      .where(
                                                        (group) =>
                                                            !group.isDeleted,
                                                      )
                                                      .toList();
                                                  _todoDataRevision++;
                                                });
                                              },
                                              onTodosChanged:
                                                  _handleTodosChanged,
                                              onManualTodoSaved:
                                                  _saveManualTodo,
                                              onEditorSave:
                                                  _handleTodoEditorSave,
                                              onEditorGroupsSave:
                                                  _handleTodoEditorGroupsSave,
                                              initialSelectedTeamUuid:
                                                  _currentSelectedTeamUuid,
                                              onRefreshRequested:
                                                  _handleManualSync,
                                              onLLMResultsParsed:
                                                  (
                                                    results,
                                                    imagePath,
                                                    originalText,
                                                    tUuid,
                                                    tName,
                                                  ) {
                                                    _navigateToTodoConfirm(
                                                      results,
                                                      imagePath,
                                                      originalText,
                                                      tUuid,
                                                      tName,
                                                    );
                                                  },
                                            );
                                          },
                                        ),
                                      );
                                      Widget
                                      buildScreenTime() => wrapSectionBoundary(
                                        KeyedSubtree(
                                          key: _screenTimeCardKey,
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              SectionHeader(
                                                title: "屏幕时间 (今日汇总)",
                                                icon: Icons.timer_outlined,
                                                isLight: isLight,
                                              ),
                                              ScreenTimeCard(
                                                stats: _screenTimeStats,
                                                isLight: isLight,
                                                hasPermission:
                                                    _hasUsagePermission,
                                                isLoading: _isLoadingScreenTime,
                                                lastSyncTime:
                                                    _lastScreenTimeSync,
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
                                                    page:
                                                        ScreenTimeDetailScreen(
                                                          todayStats:
                                                              _screenTimeStats,
                                                        ),
                                                    sourceKey:
                                                        _screenTimeCardKey,
                                                    placeholderIcon:
                                                        Icons.timer_outlined,
                                                  );
                                                },
                                              ),
                                            ],
                                          ),
                                        ),
                                      );
                                      Widget buildMath() =>
                                          ValueListenableBuilder<
                                            Map<String, dynamic>
                                          >(
                                            valueListenable: _mathStatsNotifier,
                                            builder: (context, stats, _) =>
                                                wrapSectionBoundary(
                                                  KeyedSubtree(
                                                    key: _mathCardKey,
                                                    child: Column(
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .start,
                                                      children: [
                                                        SectionHeader(
                                                          title: "数学测验",
                                                          icon: Icons.functions,
                                                          isLight: isLight,
                                                        ),
                                                        MathStatsCard(
                                                          stats: stats,
                                                          isLight: isLight,
                                                          onTap: () async {
                                                            await PageTransitions.pushFromRect(
                                                              context: context,
                                                              page: MathMenuScreen(
                                                                username: widget
                                                                    .username,
                                                              ),
                                                              sourceKey:
                                                                  _mathCardKey,
                                                              placeholderIcon:
                                                                  Icons
                                                                      .functions,
                                                            );
                                                            _loadAllData(
                                                              deferred: true,
                                                              domains: const {
                                                                DataRefreshDomain
                                                                    .mathStats,
                                                              },
                                                            );
                                                          },
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                ),
                                          );
                                      Widget
                                      buildTimeline() => wrapSectionBoundary(
                                        KeyedSubtree(
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
                                        ),
                                      );

                                      Widget
                                      buildPomodoro() => wrapSectionBoundary(
                                        ValueListenableBuilder<int>(
                                          valueListenable: _pomodoroRevision,
                                          builder: (context, trigger, _) {
                                            return KeyedSubtree(
                                              key: _pomodoroCardKey,
                                              child: PomodoroTodaySection(
                                                username: widget.username,
                                                isLight: isLight,
                                                refreshTrigger: trigger,
                                                onTap: () async {
                                                  await PageTransitions.pushFromRect(
                                                    context: context,
                                                    page: PomodoroScreen(
                                                      username: widget.username,
                                                      initialTab: 1,
                                                    ),
                                                    sourceKey: _pomodoroCardKey,
                                                    placeholderIcon:
                                                        Icons.bar_chart_rounded,
                                                  );
                                                  _pomodoroRevision.value++;
                                                },
                                              ),
                                            );
                                          },
                                        ),
                                      );

                                      Widget
                                      buildAgenda() => wrapSectionBoundary(
                                        AnimatedBuilder(
                                          animation: _agendaSectionListenable,
                                          builder: (context, _) {
                                            return PlanBlockTodaySection(
                                              unifiedAgenda: true,
                                              includeSchedules:
                                                  _sectionVisibility['agendaSchedules'] ??
                                                  true,
                                              includePlans:
                                                  _sectionVisibility['agendaPlans'] ??
                                                  true,
                                              todos: _todos,
                                              chartKey: _todayPlanChartKey,
                                              username: widget.username,
                                              isLight: isLight,
                                              refreshTrigger:
                                                  _scheduleRevision.value,
                                              repository:
                                                  widget.planReviewRepository,
                                              agendaRepository:
                                                  widget.agendaRepository,
                                              clock:
                                                  widget
                                                      .planReviewRepository
                                                      ?.clock ??
                                                  widget
                                                      .agendaRepository
                                                      ?.plans
                                                      .clock,
                                              enabled:
                                                  _sectionVisibility['agenda'] ??
                                                  true,
                                              onTodoAdded: (todo) async {
                                                await _saveManualTodo(todo);
                                              },
                                              onManualTodoSaved:
                                                  _saveManualTodo,
                                              onCreateRelatedTodo:
                                                  _saveTodoLinkedToFixedSchedule,
                                              onTap: ([sourceKey]) async {
                                                final page = TodoPlanScreen(
                                                  username: widget.username,
                                                  initialDate: widget
                                                      .planReviewRepository
                                                      ?.now,
                                                );
                                                if (sourceKey != null) {
                                                  await PageTransitions.pushFromRect(
                                                    context: context,
                                                    page: page,
                                                    sourceKey: sourceKey,
                                                    placeholderIcon: Icons
                                                        .calendar_month_rounded,
                                                  );
                                                } else {
                                                  await Navigator.of(
                                                    context,
                                                  ).push(
                                                    PageTransitions.material(
                                                      builder: (_) => page,
                                                    ),
                                                  );
                                                }
                                                _scheduleRevision.value++;
                                                _loadAllData(
                                                  domains: const {
                                                    DataRefreshDomain.todos,
                                                    DataRefreshDomain
                                                        .planBlocks,
                                                    DataRefreshDomain
                                                        .fixedSchedules,
                                                    DataRefreshDomain.courses,
                                                  },
                                                );
                                              },
                                            );
                                          },
                                        ),
                                      );
                                      Widget
                                      buildFinance() => wrapSectionBoundary(
                                        KeyedSubtree(
                                          key: _financeCardKey,
                                          child: FinanceTodaySection(
                                            username: widget.username,
                                            isLight: isLight,
                                            onTap: () async {
                                              await PageTransitions.pushFromRect(
                                                context: context,
                                                page: FinanceHomeScreen(
                                                  username: widget.username,
                                                ),
                                                sourceKey: _financeCardKey,
                                                placeholderIcon: Icons
                                                    .account_balance_wallet_outlined,
                                                sourceBorderRadius:
                                                    BorderRadius.circular(24),
                                              );
                                            },
                                          ),
                                        ),
                                      );

                                      Map<String, Widget Function()>
                                      sectionBuilders = {
                                        'banners': () => wrapSectionBoundary(
                                          AnimatedBuilder(
                                            animation: _bannerSectionListenable,
                                            builder: (_, _) =>
                                                _buildUniversalBanner(isLight),
                                          ),
                                        ),
                                        'agenda': buildAgenda,
                                        'countdowns': buildCountdown,
                                        'todos': buildTodo,
                                        'screenTime': buildScreenTime,
                                        'math': buildMath,
                                        'pomodoro': buildPomodoro,
                                        'timeline': buildTimeline,
                                        'finance': buildFinance,
                                        'habits': () => wrapSectionBoundary(
                                          KeyedSubtree(
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
                                                    await PageTransitions.pushFromRect(
                                                      context: context,
                                                      page: HabitCenterScreen(
                                                        username:
                                                            widget.username,
                                                      ),
                                                      sourceKey: _habitsCardKey,
                                                      placeholderIcon:
                                                          Icons.repeat_rounded,
                                                      sourceBorderRadius:
                                                          BorderRadius.circular(
                                                            24,
                                                          ),
                                                    );
                                                    _habitsRevision.value++;
                                                  },
                                                );
                                              },
                                            ),
                                          ),
                                        ),
                                      };

                                      if (!isTablet) {
                                        Widget buildScrollableSection(
                                          String key,
                                        ) {
                                          if (key == 'daily_ai_suggestion') {
                                            return HomeDashboardScrollSection(
                                              key: ValueKey<String>(key),
                                              keepAlive: !AppPlatform.isWindows,
                                              child: AppSystemUiRegion(
                                                backgroundBrightness:
                                                    cardBackgroundBrightness,
                                                child: wrapSectionBoundary(
                                                  _buildDailyAiSuggestionSection(
                                                    isLight,
                                                  ),
                                                ),
                                              ),
                                            );
                                          }
                                          return HomeDashboardScrollSection(
                                            key: ValueKey<String>(key),
                                            keepAlive: !AppPlatform.isWindows,
                                            child: AppSystemUiRegion(
                                              backgroundBrightness:
                                                  cardBackgroundBrightness,
                                              child: Padding(
                                                padding: EdgeInsets.only(
                                                  bottom: key == 'banners'
                                                      ? 0.0
                                                      : 24.0,
                                                ),
                                                child: sectionBuilders[key]!(),
                                              ),
                                            ),
                                          );
                                        }

                                        final tab1SectionKeys =
                                            _mobileHomeSections
                                                .where(
                                                  (key) =>
                                                      (_sectionVisibility[key] ??
                                                          true) &&
                                                      sectionBuilders
                                                          .containsKey(key),
                                                )
                                                .toList(growable: false);

                                        final tab3SectionKeys =
                                            _mobileFocusSections
                                                .where(
                                                  (key) =>
                                                      (_sectionVisibility[key] ??
                                                          true) &&
                                                      sectionBuilders
                                                          .containsKey(key),
                                                )
                                                .toList(growable: false);

                                        final hasCopyright =
                                            _wallpaperCopyright?.isNotEmpty ??
                                            false;

                                        Widget buildMobileList(
                                          bool focusPage,
                                          ValueListenable<double>
                                          listHeaderExtentListenable,
                                        ) {
                                          final baseSectionKeys = focusPage
                                              ? tab3SectionKeys
                                              : tab1SectionKeys;
                                          final sectionKeys = List<String>.from(
                                            baseSectionKeys,
                                          );
                                          if (!focusPage) {
                                            final bannersIndex = sectionKeys
                                                .indexOf('banners');
                                            sectionKeys.insert(
                                              bannersIndex >= 0
                                                  ? bannersIndex + 1
                                                  : 0,
                                              'daily_ai_suggestion',
                                            );
                                          }
                                          final hasOnboarding = !focusPage;
                                          final onboardingIndex = hasOnboarding
                                              ? sectionKeys.length
                                              : -1;
                                          final copyrightIndex = hasCopyright
                                              ? sectionKeys.length +
                                                    (hasOnboarding ? 1 : 0)
                                              : -1;
                                          final listContent = OptionalLiquidGlassScrollOptimizer(
                                            child: ValueListenableBuilder<double>(
                                              valueListenable:
                                                  listHeaderExtentListenable,
                                              builder: (context, listHeaderExtent, _) => ListView.builder(
                                                key: PageStorageKey<String>(
                                                  focusPage
                                                      ? 'home-focus-sections'
                                                      : 'home-main-sections',
                                                ),
                                                physics:
                                                    const AppFluidScrollPhysics(
                                                      parent:
                                                          AlwaysScrollableScrollPhysics(),
                                                    ),
                                                addRepaintBoundaries:
                                                    addListRepaintBoundaries,
                                                scrollCacheExtent:
                                                    AppPlatform.isWindows
                                                    ? const ScrollCacheExtent.viewport(
                                                        0.5,
                                                      )
                                                    : ScrollCacheExtent.pixels(
                                                        600,
                                                      ),
                                                padding: EdgeInsets.fromLTRB(
                                                  16,
                                                  homeDashboardPhoneScrollTopPadding(
                                                    headerExtent:
                                                        listHeaderExtent,
                                                    topInset: topSystemInset,
                                                  ),
                                                  16,
                                                  16,
                                                ),
                                                itemCount:
                                                    sectionKeys.length +
                                                    (hasOnboarding ? 1 : 0) +
                                                    (hasCopyright ? 1 : 0) +
                                                    1,
                                                findChildIndexCallback: (key) {
                                                  if (key
                                                      is! ValueKey<String>) {
                                                    return null;
                                                  }
                                                  if (hasOnboarding &&
                                                      key.value ==
                                                          'onboarding_checklist') {
                                                    return onboardingIndex;
                                                  }
                                                  final index = sectionKeys
                                                      .indexOf(key.value);
                                                  return index < 0
                                                      ? null
                                                      : index;
                                                },
                                                itemBuilder: (context, index) {
                                                  if (index <
                                                      sectionKeys.length) {
                                                    return buildScrollableSection(
                                                      sectionKeys[index],
                                                    );
                                                  }
                                                  if (index ==
                                                      onboardingIndex) {
                                                    return HomeDashboardScrollSection(
                                                      key:
                                                          const ValueKey<
                                                            String
                                                          >(
                                                            'onboarding_checklist',
                                                          ),
                                                      keepAlive: !AppPlatform
                                                          .isWindows,
                                                      child: AppSystemUiRegion(
                                                        backgroundBrightness:
                                                            cardBackgroundBrightness,
                                                        child: wrapSectionBoundary(
                                                          AnimatedBuilder(
                                                            animation:
                                                                _bannerSectionListenable,
                                                            builder: (_, _) =>
                                                                _buildOnboardingChecklistSection(
                                                                  isLight,
                                                                ),
                                                          ),
                                                        ),
                                                      ),
                                                    );
                                                  }
                                                  if (index == copyrightIndex) {
                                                    return _buildWallpaperCopyright(
                                                      isLight,
                                                    );
                                                  }
                                                  return SizedBox(
                                                    // The header overlays the list, so
                                                    // reserve it at the trailing edge
                                                    // to keep short pages scrollable.
                                                    height:
                                                        homeDashboardPhoneScrollTailExtent(
                                                          headerExtent: max(
                                                            listHeaderExtent,
                                                            topSystemInset,
                                                          ),
                                                          bottomInset:
                                                              bottomSystemInset,
                                                        ),
                                                  );
                                                },
                                              ),
                                            ),
                                          );
                                          final tabContentKey =
                                              ValueKey<String>(
                                                focusPage
                                                    ? 'home-focus-tab-content'
                                                    : 'home-main-tab-content',
                                              );
                                          return RepaintBoundary(
                                            key: tabContentKey,
                                            child: listContent,
                                          );
                                        }

                                        if (AppPlatform.isAndroid) {
                                          // Keep each visited list mounted so a
                                          // tab switch can reuse its painted card
                                          // layers and scroll position. The hidden
                                          // list neither paints nor runs tickers.
                                          final homeTabChild = buildMobileList(
                                            false,
                                            _homeHeaderExtentNotifier,
                                          );
                                          Widget? focusTabChild =
                                              _focusTabVisited
                                              ? buildMobileList(
                                                  true,
                                                  _focusHeaderExtentNotifier,
                                                )
                                              : null;
                                          return ValueListenableBuilder<int>(
                                            valueListenable:
                                                _selectedTabIndexNotifier,
                                            child: homeTabChild,
                                            builder:
                                                (
                                                  context,
                                                  selectedTabIndex,
                                                  cachedHomeTab,
                                                ) {
                                                  final showFocusTab =
                                                      selectedTabIndex ==
                                                      _homeFocusTabIndex;
                                                  if (showFocusTab) {
                                                    _focusTabVisited = true;
                                                  }
                                                  if (_focusTabVisited &&
                                                      focusTabChild == null) {
                                                    focusTabChild = buildMobileList(
                                                      true,
                                                      _focusHeaderExtentNotifier,
                                                    );
                                                  }
                                                  return Stack(
                                                    fit: StackFit.expand,
                                                    children: [
                                                      Offstage(
                                                        offstage: showFocusTab,
                                                        child: TickerMode(
                                                          enabled:
                                                              !showFocusTab,
                                                          child: cachedHomeTab!,
                                                        ),
                                                      ),
                                                      if (focusTabChild != null)
                                                        Offstage(
                                                          offstage:
                                                              !showFocusTab,
                                                          child: TickerMode(
                                                            enabled:
                                                                showFocusTab,
                                                            child:
                                                                focusTabChild!,
                                                          ),
                                                        ),
                                                    ],
                                                  );
                                                },
                                          );
                                        }

                                        return ValueListenableBuilder<int>(
                                          valueListenable:
                                              _selectedTabIndexNotifier,
                                          builder: (context, selectedTabIndex, _) {
                                            final showFocusTab =
                                                selectedTabIndex ==
                                                _homeFocusTabIndex;
                                            return AnimatedSwitcher(
                                              duration: const Duration(
                                                milliseconds: 280,
                                              ),
                                              reverseDuration: const Duration(
                                                milliseconds: 240,
                                              ),
                                              switchInCurve:
                                                  Curves.easeOutCubic,
                                              switchOutCurve:
                                                  Curves.easeInCubic,
                                              layoutBuilder:
                                                  (
                                                    currentChild,
                                                    previousChildren,
                                                  ) {
                                                    return Stack(
                                                      fit: StackFit.expand,
                                                      children: [
                                                        ...previousChildren,
                                                        ?currentChild,
                                                      ],
                                                    );
                                                  },
                                              transitionBuilder: (child, animation) {
                                                final focusPage =
                                                    child.key ==
                                                    const ValueKey<String>(
                                                      'home-focus-tab-content',
                                                    );
                                                final slidePosition =
                                                    Tween<Offset>(
                                                      begin: Offset(
                                                        focusPage
                                                            ? 0.035
                                                            : -0.035,
                                                        0,
                                                      ),
                                                      end: Offset.zero,
                                                    ).animate(animation);
                                                return AnimatedBuilder(
                                                  animation: animation,
                                                  child: child,
                                                  builder: (context, child) {
                                                    if (animation.value <=
                                                        0.001) {
                                                      return const SizedBox.shrink();
                                                    }
                                                    if (animation.value >=
                                                        0.999) {
                                                      return child!;
                                                    }
                                                    return FadeTransition(
                                                      opacity: animation,
                                                      child: SlideTransition(
                                                        position: slidePosition,
                                                        child: child,
                                                      ),
                                                    );
                                                  },
                                                );
                                              },
                                              child: buildMobileList(
                                                showFocusTab,
                                                headerExtentListenable,
                                              ),
                                            );
                                          },
                                        );
                                      }

                                      // Tablet Layout
                                      final currentLeft = _leftSections;
                                      final currentRight = _rightSections;

                                      if (AppPlatform.isWindows) {
                                        const estimatedHeights =
                                            <String, double>{
                                              'banners': 184,
                                              'agenda': 560,
                                              'countdowns': 360,
                                              'todos': 620,
                                              'screenTime': 400,
                                              'math': 280,
                                              'pomodoro': 520,
                                              'timeline': 480,
                                              'finance': 400,
                                              'habits': 480,
                                            };

                                        List<WindowsDashboardSection>
                                        buildSpecs(List<String> keys) => keys
                                            .where(
                                              (key) =>
                                                  (_sectionVisibility[key] ??
                                                      true) &&
                                                  sectionBuilders.containsKey(
                                                    key,
                                                  ),
                                            )
                                            .map((key) {
                                              return WindowsDashboardSection(
                                                id: key,
                                                estimatedHeight:
                                                    estimatedHeights[key] ??
                                                    360,
                                                builder: (context) {
                                                  final section =
                                                      sectionBuilders[key]!();
                                                  return AppSystemUiRegion(
                                                    backgroundBrightness:
                                                        cardBackgroundBrightness,
                                                    child: Padding(
                                                      padding:
                                                          const EdgeInsets.only(
                                                            bottom: 24,
                                                          ),
                                                      child: section,
                                                    ),
                                                  );
                                                },
                                              );
                                            })
                                            .toList(growable: false);

                                        final footer = Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            AppSystemUiRegion(
                                              backgroundBrightness:
                                                  cardBackgroundBrightness,
                                              child: AnimatedBuilder(
                                                animation:
                                                    _bannerSectionListenable,
                                                builder: (_, _) =>
                                                    _buildOnboardingChecklistSection(
                                                      isLight,
                                                    ),
                                              ),
                                            ),
                                            if (_wallpaperCopyright != null &&
                                                _wallpaperCopyright!.isNotEmpty)
                                              _buildWallpaperCopyright(isLight),
                                          ],
                                        );

                                        final leftSpecs = buildSpecs(
                                          currentLeft,
                                        ).toList();
                                        final windowsBannersIdx = leftSpecs
                                            .indexWhere(
                                              (s) => s.id == 'banners',
                                            );
                                        leftSpecs.insert(
                                          windowsBannersIdx >= 0
                                              ? windowsBannersIdx + 1
                                              : 0,
                                          WindowsDashboardSection(
                                            id: 'daily_ai_suggestion',
                                            estimatedHeight: 220,
                                            builder: (context) => AppSystemUiRegion(
                                              backgroundBrightness:
                                                  cardBackgroundBrightness,
                                              child:
                                                  _buildDailyAiSuggestionSection(
                                                    isLight,
                                                  ),
                                            ),
                                          ),
                                        );

                                        return OptionalLiquidGlassScrollOptimizer(
                                          child: ValueListenableBuilder<double>(
                                            valueListenable:
                                                headerExtentListenable,
                                            builder: (context, headerExtent, _) =>
                                                WindowsDashboardScrollCoordinator(
                                                  leftSections: leftSpecs,
                                                  rightSections: buildSpecs(
                                                    currentRight,
                                                  ),
                                                  footer: footer,
                                                  padding: EdgeInsets.fromLTRB(
                                                    32,
                                                    headerExtent + 16,
                                                    32,
                                                    16 +
                                                        bottomSystemInset +
                                                        100.0,
                                                  ),
                                                  maxWidth: 1400,
                                                ),
                                          ),
                                        );
                                      }

                                      final visibleLeftKeys = currentLeft
                                          .where(
                                            (key) =>
                                                (_sectionVisibility[key] ??
                                                    true) &&
                                                sectionBuilders.containsKey(
                                                  key,
                                                ),
                                          )
                                          .toList();
                                      final tabletBannersIdx = visibleLeftKeys
                                          .indexOf('banners');
                                      visibleLeftKeys.insert(
                                        tabletBannersIdx >= 0
                                            ? tabletBannersIdx + 1
                                            : 0,
                                        'daily_ai_suggestion',
                                      );
                                      final visibleRightKeys = currentRight
                                          .where(
                                            (key) =>
                                                (_sectionVisibility[key] ??
                                                    true) &&
                                                sectionBuilders.containsKey(
                                                  key,
                                                ),
                                          )
                                          .toList(growable: false);

                                      Widget buildWideSection(String key) {
                                        if (key == 'daily_ai_suggestion') {
                                          return HomeDashboardScrollSection(
                                            key: const ValueKey<String>(
                                              'daily_ai_suggestion',
                                            ),
                                            keepAlive: true,
                                            child: AppSystemUiRegion(
                                              backgroundBrightness:
                                                  cardBackgroundBrightness,
                                              child: wrapSectionBoundary(
                                                _buildDailyAiSuggestionSection(
                                                  isLight,
                                                ),
                                              ),
                                            ),
                                          );
                                        }
                                        return HomeDashboardScrollSection(
                                          key: ValueKey<String>(key),
                                          keepAlive: true,
                                          child: AppSystemUiRegion(
                                            backgroundBrightness:
                                                cardBackgroundBrightness,
                                            child: Padding(
                                              padding: EdgeInsets.only(
                                                bottom: key == 'banners'
                                                    ? 0.0
                                                    : 24.0,
                                              ),
                                              child: sectionBuilders[key]!(),
                                            ),
                                          ),
                                        );
                                      }

                                      int? findKeyIndex(
                                        List<String> keys,
                                        Key key,
                                      ) {
                                        if (key is! ValueKey<String>) {
                                          return null;
                                        }
                                        final index = keys.indexOf(key.value);
                                        return index < 0 ? null : index;
                                      }

                                      final hasCopyright =
                                          _wallpaperCopyright?.isNotEmpty ??
                                          false;
                                      final bottomPadding =
                                          16.0 +
                                          bottomSystemInset +
                                          (isTablet ? 100.0 : 0.0);

                                      return OptionalLiquidGlassScrollOptimizer(
                                        child: LayoutBuilder(
                                          builder: (context, constraints) {
                                            final availableWidth =
                                                constraints.maxWidth.isFinite
                                                ? constraints.maxWidth
                                                : screenWidth;
                                            final baseHorizontalPadding =
                                                isTablet ? 32.0 : 16.0;
                                            final horizontalPadding = max(
                                              baseHorizontalPadding,
                                              (availableWidth - 1400.0) / 2.0,
                                            );
                                            final columnsSliver = isTablet
                                                ? SliverCrossAxisGroup(
                                                    slivers: [
                                                      SliverCrossAxisExpanded(
                                                        flex: 10,
                                                        sliver: SliverList.builder(
                                                          addRepaintBoundaries:
                                                              addListRepaintBoundaries,
                                                          itemCount:
                                                              visibleLeftKeys
                                                                  .length,
                                                          findChildIndexCallback:
                                                              (
                                                                key,
                                                              ) => findKeyIndex(
                                                                visibleLeftKeys,
                                                                key,
                                                              ),
                                                          itemBuilder:
                                                              (
                                                                context,
                                                                index,
                                                              ) => buildWideSection(
                                                                visibleLeftKeys[index],
                                                              ),
                                                        ),
                                                      ),
                                                      if (visibleRightKeys
                                                          .isNotEmpty) ...[
                                                        const SliverConstrainedCrossAxis(
                                                          maxExtent: 40,
                                                          sliver: SliverToBoxAdapter(
                                                            child:
                                                                SizedBox.shrink(),
                                                          ),
                                                        ),
                                                        SliverCrossAxisExpanded(
                                                          flex: 11,
                                                          sliver: SliverList.builder(
                                                            addRepaintBoundaries:
                                                                addListRepaintBoundaries,
                                                            itemCount:
                                                                visibleRightKeys
                                                                    .length,
                                                            findChildIndexCallback:
                                                                (
                                                                  key,
                                                                ) => findKeyIndex(
                                                                  visibleRightKeys,
                                                                  key,
                                                                ),
                                                            itemBuilder:
                                                                (
                                                                  context,
                                                                  index,
                                                                ) => buildWideSection(
                                                                  visibleRightKeys[index],
                                                                ),
                                                          ),
                                                        ),
                                                      ],
                                                    ],
                                                  )
                                                : SliverList.builder(
                                                    addRepaintBoundaries:
                                                        addListRepaintBoundaries,
                                                    itemCount:
                                                        visibleLeftKeys.length +
                                                        visibleRightKeys.length,
                                                    itemBuilder: (context, index) {
                                                      final key =
                                                          index <
                                                              visibleLeftKeys
                                                                  .length
                                                          ? visibleLeftKeys[index]
                                                          : visibleRightKeys[index -
                                                                visibleLeftKeys
                                                                    .length];
                                                      return buildWideSection(
                                                        key,
                                                      );
                                                    },
                                                  );

                                            return CustomScrollView(
                                              key: const PageStorageKey<String>(
                                                'home-wide-dashboard-scroll',
                                              ),
                                              physics: const AppFluidScrollPhysics(
                                                parent:
                                                    AlwaysScrollableScrollPhysics(),
                                              ),
                                              scrollCacheExtent:
                                                  ScrollCacheExtent.pixels(400),
                                              slivers: [
                                                SliverToBoxAdapter(
                                                  child:
                                                      ValueListenableBuilder<
                                                        double
                                                      >(
                                                        valueListenable:
                                                            headerExtentListenable,
                                                        builder:
                                                            (
                                                              _,
                                                              headerExtent,
                                                              _,
                                                            ) => SizedBox(
                                                              height:
                                                                  headerExtent +
                                                                  6,
                                                            ),
                                                      ),
                                                ),
                                                SliverPadding(
                                                  padding: EdgeInsets.symmetric(
                                                    horizontal:
                                                        horizontalPadding,
                                                  ),
                                                  sliver: columnsSliver,
                                                ),
                                                SliverPadding(
                                                  padding: EdgeInsets.fromLTRB(
                                                    horizontalPadding,
                                                    0,
                                                    horizontalPadding,
                                                    hasCopyright
                                                        ? 0.0
                                                        : bottomPadding,
                                                  ),
                                                  sliver: SliverToBoxAdapter(
                                                    child: AppSystemUiRegion(
                                                      backgroundBrightness:
                                                          cardBackgroundBrightness,
                                                      child: wrapSectionBoundary(
                                                        AnimatedBuilder(
                                                          animation:
                                                              _bannerSectionListenable,
                                                          builder: (_, _) =>
                                                              _buildOnboardingChecklistSection(
                                                                isLight,
                                                              ),
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                                if (hasCopyright)
                                                  SliverPadding(
                                                    padding:
                                                        EdgeInsets.fromLTRB(
                                                          horizontalPadding,
                                                          0,
                                                          horizontalPadding,
                                                          bottomPadding,
                                                        ),
                                                    sliver: SliverToBoxAdapter(
                                                      child:
                                                          _buildWallpaperCopyright(
                                                            isLight,
                                                          ),
                                                    ),
                                                  ),
                                              ],
                                            );
                                          },
                                        ),
                                      );
                                    },
                                  ),
                          ],
                        );
                      },
                    ),
                    if (showWallpaper && wallpaperUrl != null)
                      ValueListenableBuilder<double>(
                        valueListenable: headerExtentListenable,
                        builder: (_, headerExtent, _) => headerExtent > 0.0
                            ? _buildWallpaperTopFadeCap(
                                headerExtent: headerExtent,
                                wallpaperUrl: wallpaperUrl,
                                localWallpaperProvider: localWallpaperProvider,
                              )
                            : const SizedBox.shrink(),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
      // Scaffold 的底部槽位负责底栏的布局，避免自绘 Positioned 把
      // 底栏锁在内容 Stack 内并遮挡最后一张卡片。所有屏幕尺寸统一使用
      // 底栏，宽屏不再额外堆叠番茄钟、记待办和记账悬浮按钮。
      bottomNavigationBar: _buildCustomBottomBar(isDarkMode, isLight, isTablet),
      floatingActionButton: null,
    );

    return ZoomDrawer(
      menuScreen: _getOrBuildDrawerMenu(),
      mainScreen: AppSystemUiRegion(
        backgroundBrightness: showWallpaper || isDarkMode
            ? Brightness.dark
            : Brightness.light,
        child: mainScreen,
      ),
      borderRadius: 24.0,
      showShadow: true,
      angle: 0.0,
      drawerShadowsBackgroundColor: Colors.grey.shade300,
      menuScreenWidth: isTablet ? drawerWidth : null,
      slideWidth: drawerWidth,
    );
  }

  Widget _getOrBuildDrawerMenu() {
    if (_cachedDrawerMenu != null &&
        _cachedDrawerUsername == widget.username &&
        _cachedDrawerTimeSalutation == _timeSalutation &&
        _cachedDrawerTeamPendingCount == _teamPendingCount &&
        _cachedDrawerHasTeamConflictDot == _hasTeamConflictDot) {
      return _cachedDrawerMenu!;
    }
    _cachedDrawerUsername = widget.username;
    _cachedDrawerTimeSalutation = _timeSalutation;
    _cachedDrawerTeamPendingCount = _teamPendingCount;
    _cachedDrawerHasTeamConflictDot = _hasTeamConflictDot;
    return _cachedDrawerMenu = HomeDrawerMenu(
      username: widget.username,
      timeSalutation: _timeSalutation,
      onSettings: _openSettingsFromDrawer,
      onOpenUpdateSettings: (sourceKey) => _openSettingsFromDrawer(
        sourceKey,
        initialTarget: 'update',
        sourceBorderRadius: BorderRadius.circular(6),
        placeholderIcon: Icons.new_releases_outlined,
      ),
      onAiAssistant: (sourceKey) =>
          _openAiAssistantFromAppBar(sourceKey: sourceKey),
      onTeams: (sourceKey) async {
        await PageTransitions.pushFromRect(
          context: context,
          page: TeamManagementScreen(username: widget.username),
          sourceKey: sourceKey,
          placeholderIcon: Icons.people_rounded,
        );
        if (!mounted) return;
        final unreadBackgroundNotifications =
            await BackgroundNotificationService.getUnreadBackgroundNotifications();
        final notificationIds = unreadBackgroundNotifications
            .map((e) => e['id'])
            .whereType<num>()
            .map((e) => e.toInt())
            .toList();
        await ApiService.markNotificationsRead(notificationIds);
        await BackgroundNotificationService.clearUnreadBackgroundNotifications();
        await _fetchTeamPendingCount();
        _loadAllData(deferred: true);
      },
      onFinance: (sourceKey) async {
        await PageTransitions.pushFromRect(
          context: context,
          page: FinanceHomeScreen(username: widget.username),
          sourceKey: sourceKey,
          placeholderIcon: Icons.account_balance_wallet_outlined,
        );
      },
      teamPendingCount: _teamPendingCount,
      hasTeamConflictDot: _hasTeamConflictDot,
      onTimeline: (sourceKey) async {
        await PageTransitions.pushFromRect(
          context: context,
          page: PersonalTimelineScreen(username: widget.username),
          sourceKey: sourceKey,
          placeholderIcon: Icons.timeline_rounded,
          sourceColor: Theme.of(context).brightness == Brightness.dark
              ? Colors.black
              : Colors.white,
        );
      },
      onJournal: (sourceKey) async {
        await PageTransitions.pushFromRect(
          context: context,
          page: JournalHomeScreen(username: widget.username),
          sourceKey: sourceKey,
          placeholderIcon: Icons.auto_stories_rounded,
        );
      },
      onScreenTime: (sourceKey) async {
        await PageTransitions.pushFromRect(
          context: context,
          page: TimeLogScreen(username: widget.username),
          sourceKey: sourceKey,
          placeholderIcon: Icons.pie_chart_rounded,
        );
      },
      onPlanCenter: (sourceKey) async {
        await PageTransitions.pushFromRect(
          context: context,
          page: TodoPlanScreen(username: widget.username),
          sourceKey: sourceKey,
          placeholderIcon: Icons.edit_calendar_rounded,
        );
        if (!mounted) return;
        _loadSemesterSettings();
        _loadAllData(
          deferred: true,
          domains: const {
            DataRefreshDomain.todos,
            DataRefreshDomain.planBlocks,
            DataRefreshDomain.fixedSchedules,
          },
        );
      },
      onHabits: (sourceKey) async {
        await PageTransitions.pushFromRect(
          context: context,
          page: HabitCenterScreen(username: widget.username),
          sourceKey: sourceKey,
          placeholderIcon: Icons.repeat_rounded,
        );
        if (mounted) _habitsRevision.value++;
      },
      onChangelog: (sourceKey) async {
        await PageTransitions.pushFromRect(
          context: Navigator.of(context, rootNavigator: true).context,
          page: FeatureGuideScreen(
            mode: FeatureGuideMode.changelog,
            loggedInUser: widget.username,
          ),
          sourceKey: sourceKey,
          placeholderIcon: Icons.system_update_rounded,
        );
      },
      onChallengeCenter: (sourceKey) async {
        await PageTransitions.pushFromRect(
          context: Navigator.of(context, rootNavigator: true).context,
          page: const ChallengeCenterScreen(),
          sourceKey: sourceKey,
          placeholderIcon: Icons.auto_awesome_rounded,
        );
        if (mounted) _loadThirtyDayChallengeStatus();
      },
      onUpdate: (sourceKey) => _openSettingsFromDrawer(
        sourceKey,
        initialTarget: 'update',
        checkUpdatesOnOpen: true,
        placeholderIcon: Icons.system_update_rounded,
      ),
      onFeatureExplorer: (sourceKey) async {
        await PageTransitions.pushFromRect(
          context: Navigator.of(context, rootNavigator: true).context,
          page: FeatureExplorerScreen(username: widget.username),
          sourceKey: sourceKey,
          placeholderIcon: Icons.explore_rounded,
        );
      },
    );
  }
}
