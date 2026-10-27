part of 'home_dashboard.dart';

// ignore_for_file: annotate_overrides

enum _HomeAddAction { todo, countdown, finance }

/// The phone homepage body is painted underneath its pinned header. Its final
/// spacer must therefore reserve both the floating bottom bar and the header;
/// otherwise a short page has no positive scroll extent and a slow upward
/// drag only produces an overscroll bounce.
@visibleForTesting
double homeDashboardPhoneScrollTailExtent({
  required double headerExtent,
  required double bottomInset,
}) => headerExtent.clamp(0.0, 2000.0).toDouble() + 100.0 + bottomInset;

mixin _HomeDashboardViewMixin
    on _HomeDashboardStateBase, _HomeDashboardWallpaperMixin {
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

  Widget _buildWallpaperDisplay(ImageProvider<Object> provider) {
    Widget display(ImageProvider<Object> imageProvider) => Image(
      image: imageProvider,
      fit: BoxFit.cover,
      color: const Color(0x66000000),
      colorBlendMode: BlendMode.srcOver,
    );
    if (!AppPlatform.isWindows) return display(provider);
    return StableImageDecodeSize(
      builder: (_, width, height) => display(
        ResizeImage(
          provider,
          width: width,
          height: height,
          policy: ResizeImagePolicy.fit,
        ),
      ),
    );
  }

  Widget build(BuildContext context) {
    bool isDarkMode = Theme.of(context).brightness == Brightness.dark;
    bool showWallpaper = !isDarkMode && _wallpaperShow && _wallpaperUrl != null;
    bool isLight = showWallpaper;
    final wallpaperUrl = _wallpaperUrl;
    final localWallpaperProvider =
        showWallpaper && wallpaperUrl != null && _isLocalFilePath(wallpaperUrl)
        ? _localWallpaperProviderFor(wallpaperUrl)
        : null;
    final double screenWidth = MediaQuery.sizeOf(context).width;
    final bool isTablet = screenWidth >= 768;
    final double drawerWidth = homeDrawerSlideWidthFor(
      screenWidth: screenWidth,
      isWide: isTablet,
    );
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
        children: [
          if (showWallpaper && wallpaperUrl != null)
            Positioned.fill(
              child: wallpaperUrl.startsWith('assets/')
                  ? Builder(
                      builder: (context) {
                        final provider = AssetImage(wallpaperUrl);
                        _scheduleWallpaperColorExtraction(
                          provider,
                          wallpaperUrl,
                        );
                        return _buildWallpaperDisplay(provider);
                      },
                    )
                  : localWallpaperProvider != null
                  ? Builder(
                      builder: (context) {
                        final provider = localWallpaperProvider;
                        _scheduleWallpaperColorExtraction(
                          provider,
                          wallpaperUrl,
                        );
                        return _buildWallpaperDisplay(provider);
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
          SafeArea(
            // 仅避让顶部状态栏。列表需要继续绘制到 Android 手势导航区
            // 后方，末尾的滚动余量再保证卡片操作不会被底栏遮挡。
            top: false,
            bottom: false,
            child: FloatingGlassPinnedHeaderLayout(
              initialHeaderExtent:
                  (_selectedTabIndex != _homeFocusTabIndex || isTablet)
                  ? (112.0 + MediaQuery.paddingOf(context).top)
                  : 0.0,
              fadeContent: !showWallpaper,
              header: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildSemesterProgressBar(isLight),

                  if (_selectedTabIndex != _homeFocusTabIndex || isTablet)
                    HomeAppBar(
                      username: widget.username,
                      onCreateRelatedTodo: _saveTodoLinkedToFixedSchedule,
                      timeSalutation: _timeSalutation,
                      currentGreeting: _currentGreeting,
                      semesterWeek: _currentSemesterWeek,
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
                          page: TeamManagementScreen(username: widget.username),
                          sourceKey: _teamsButtonKey,
                        );
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
                  if (_selectedTabIndex != _homeFocusTabIndex || isTablet)
                    SyncStatusBanner(
                      onDiagnosticRequested: _showLinkDiagnostics,
                    ),

                  // DEBUG: 检查状态
                  // if (_activeAnnouncement != null) Text("DEBUG: Announcement exists: ${_activeAnnouncement!.title}"),

                  // 🚀 Uni-Sync 4.0: 团队置顶公告
                  if (_activeAnnouncement != null &&
                      (_selectedTabIndex != _homeFocusTabIndex || isTablet))
                    StickyAnnouncementBanner(
                      announcement: _activeAnnouncement!,
                      onAcknowledge: () async {
                        final uuid = _activeAnnouncement!.uuid;
                        setState(() => _activeAnnouncement = null);
                        await ApiService.markAnnouncementAsRead(uuid);
                      },
                    ),

                  if (_isThirtyDayChallengeActive &&
                      (_selectedTabIndex != _homeFocusTabIndex || isTablet))
                    _buildChallengeParticipationBanner(isLight),

                  // 待确认事项入口卡片（从图片识别来）
                  _buildPendingTodoConfirmCard(isLight),
                ],
              ),
              bodyBuilder: (context, headerExtent) => Stack(
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
                              ? _buildDashboardSkeleton(
                                  isLight,
                                  topPadding: headerExtent + 16,
                                )
                              : LayoutBuilder(
                                  builder: (context, constraints) {
                                    Widget wrapSectionBoundary(Widget child) =>
                                        showWallpaper || AppPlatform.isWindows
                                            ? child
                                            : RepaintBoundary(
                                                child: child,
                                              );
                                    Widget buildCountdown() =>
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
                                        );
                                    Widget buildTodo() => AnimatedBuilder(
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
                                          onTeamChanged: (teamUuid, teamName) {
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
                                                  allGroups[index].updatedAt) {
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
                                                    (group) => !group.isDeleted,
                                                  )
                                                  .toList();
                                              _todoDataRevision++;
                                            });
                                          },
                                          onTodosChanged: _handleTodosChanged,
                                          onManualTodoSaved: _saveManualTodo,
                                          onEditorSave: _handleTodoEditorSave,
                                          onEditorGroupsSave:
                                              _handleTodoEditorGroupsSave,
                                          initialSelectedTeamUuid:
                                              _currentSelectedTeamUuid,
                                          onRefreshRequested: _handleManualSync,
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
                                                        _screenTimeStats,
                                                  ),
                                                  sourceKey: _screenTimeCardKey,
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
                                                                Icons.functions,
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
                                    Widget buildTimeline() => KeyedSubtree(
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

                                    Widget buildAgenda() => wrapSectionBoundary(
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
                                                (_sectionVisibility['agenda'] ??
                                                    true) &&
                                                (isTablet ||
                                                    (_selectedTabIndex ==
                                                                _homeFocusTabIndex
                                                            ? _mobileFocusSections
                                                            : _mobileHomeSections)
                                                        .contains('agenda')),
                                            onTodoAdded: (todo) async {
                                              await _saveManualTodo(todo);
                                            },
                                            onManualTodoSaved: _saveManualTodo,
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
                                                await Navigator.of(context)
                                                    .push(
                                                      PageTransitions.material(
                                                        builder: (_) => page,
                                                      ),
                                                    );
                                              }
                                              _scheduleRevision.value++;
                                              _loadAllData(
                                                domains: const {
                                                  DataRefreshDomain.todos,
                                                  DataRefreshDomain.planBlocks,
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
                                      'banners': () => AnimatedBuilder(
                                        animation: _bannerSectionListenable,
                                        builder: (_, _) =>
                                            _buildUniversalBanner(isLight),
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
                                                      username: widget.username,
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
                                        return HomeDashboardScrollSection(
                                          key: ValueKey<String>(key),
                                          keepAlive: !AppPlatform.isWindows,
                                          child: AppSystemUiRegion(
                                            backgroundBrightness:
                                                cardBackgroundBrightness,
                                            child: Padding(
                                              padding: const EdgeInsets.only(
                                                bottom: 24.0,
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
                                                    sectionBuilders.containsKey(
                                                      key,
                                                    ),
                                              )
                                              .toList(growable: false);

                                      final tab3SectionKeys =
                                          _mobileFocusSections
                                              .where(
                                                (key) =>
                                                    (_sectionVisibility[key] ??
                                                        true) &&
                                                    sectionBuilders.containsKey(
                                                      key,
                                                    ),
                                              )
                                              .toList(growable: false);

                                      final showFocusTab =
                                          _selectedTabIndex ==
                                          _homeFocusTabIndex;
                                      final hasCopyright =
                                          _wallpaperCopyright?.isNotEmpty ??
                                          false;

                                      Widget buildMobileList(
                                        bool focusPage,
                                        double listHeaderExtent,
                                      ) {
                                        final sectionKeys = focusPage
                                            ? tab3SectionKeys
                                            : tab1SectionKeys;
                                        final hasOnboarding = !focusPage;
                                        final onboardingIndex = hasOnboarding
                                            ? sectionKeys.length
                                            : -1;
                                        final copyrightIndex = hasCopyright
                                            ? sectionKeys.length +
                                                  (hasOnboarding ? 1 : 0)
                                            : -1;
                                        final listContent = OptionalLiquidGlassScrollOptimizer(
                                          child: ListView.builder(
                                            key: PageStorageKey<String>(
                                              focusPage
                                                  ? 'home-focus-sections'
                                                  : 'home-main-sections',
                                            ),
                                            addRepaintBoundaries:
                                                !showWallpaper,
                                            scrollCacheExtent:
                                                AppPlatform.isWindows
                                                ? const ScrollCacheExtent.viewport(
                                                    0.5,
                                                  )
                                                : null,
                                            padding: EdgeInsets.fromLTRB(
                                              16,
                                              listHeaderExtent + 16,
                                              16,
                                              16,
                                            ),
                                            itemCount:
                                                sectionKeys.length +
                                                (hasOnboarding ? 1 : 0) +
                                                (hasCopyright ? 1 : 0) +
                                                1,
                                            findChildIndexCallback: (key) {
                                              if (key is! ValueKey<String>) {
                                                return null;
                                              }
                                              if (hasOnboarding &&
                                                  key.value ==
                                                      'onboarding_checklist') {
                                                return onboardingIndex;
                                              }
                                              final index = sectionKeys.indexOf(
                                                key.value,
                                              );
                                              return index < 0 ? null : index;
                                            },
                                            itemBuilder: (context, index) {
                                              if (index < sectionKeys.length) {
                                                return buildScrollableSection(
                                                  sectionKeys[index],
                                                );
                                              }
                                              if (index == onboardingIndex) {
                                                return HomeDashboardScrollSection(
                                                  key: const ValueKey<String>(
                                                    'onboarding_checklist',
                                                  ),
                                                  keepAlive:
                                                      !AppPlatform.isWindows,
                                                  child: AppSystemUiRegion(
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
                                                      headerExtent:
                                                          listHeaderExtent,
                                                      bottomInset:
                                                          bottomSystemInset,
                                                    ),
                                              );
                                            },
                                          ),
                                        );
                                        return showWallpaper
                                            ? listContent
                                            : RepaintBoundary(
                                                key: ValueKey<String>(
                                                  focusPage
                                                      ? 'home-focus-tab-content'
                                                      : 'home-main-tab-content',
                                                ),
                                                child: listContent,
                                              );
                                      }

                                      if (AppPlatform.isAndroid) {
                                        if (showFocusTab) {
                                          _lastFocusHeaderExtent = headerExtent;
                                        } else {
                                          _lastHomeHeaderExtent = headerExtent;
                                        }
                                        // Keep each visited list mounted so a
                                        // tab switch can reuse its painted card
                                        // layers and scroll position. The hidden
                                        // list neither paints nor runs tickers.
                                        return Stack(
                                          fit: StackFit.expand,
                                          children: [
                                            Offstage(
                                              offstage: showFocusTab,
                                              child: TickerMode(
                                                enabled: !showFocusTab,
                                                child: buildMobileList(
                                                  false,
                                                  _lastHomeHeaderExtent,
                                                ),
                                              ),
                                            ),
                                            if (_focusTabVisited)
                                              Offstage(
                                                offstage: !showFocusTab,
                                                child: TickerMode(
                                                  enabled: showFocusTab,
                                                  child: buildMobileList(
                                                    true,
                                                    _lastFocusHeaderExtent,
                                                  ),
                                                ),
                                              ),
                                          ],
                                        );
                                      }

                                      return AnimatedSwitcher(
                                        duration: const Duration(
                                          milliseconds: 280,
                                        ),
                                        reverseDuration: const Duration(
                                          milliseconds: 240,
                                        ),
                                        switchInCurve: Curves.easeOutCubic,
                                        switchOutCurve: Curves.easeInCubic,
                                        layoutBuilder:
                                            (currentChild, previousChildren) {
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
                                          final enteringPage = SlideTransition(
                                            position: Tween<Offset>(
                                              begin: Offset(
                                                focusPage ? 0.035 : -0.035,
                                                0,
                                              ),
                                              end: Offset.zero,
                                            ).animate(animation),
                                            child: child,
                                          );
                                          return FadeTransition(
                                            opacity: animation,
                                            child: enteringPage,
                                          );
                                        },
                                        child: buildMobileList(
                                          showFocusTab,
                                          headerExtent,
                                        ),
                                      );
                                    }

                                    // Tablet Layout
                                    final currentLeft = _leftSections;
                                    final currentRight = _rightSections;

                                    if (AppPlatform.isWindows) {
                                      const estimatedHeights = <String, double>{
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

                                      List<WindowsDashboardSection> buildSpecs(
                                        List<String> keys,
                                      ) => keys
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
                                                  estimatedHeights[key] ?? 360,
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

                                      return OptionalLiquidGlassScrollOptimizer(
                                        child:
                                            WindowsDashboardScrollCoordinator(
                                              leftSections: buildSpecs(
                                                currentLeft,
                                              ),
                                              rightSections: buildSpecs(
                                                currentRight,
                                              ),
                                              footer: footer,
                                              padding: EdgeInsets.fromLTRB(
                                                32,
                                                headerExtent + 16,
                                                32,
                                                16 + bottomSystemInset + 100.0,
                                              ),
                                              maxWidth: 1400,
                                            ),
                                      );
                                    }

                                    List<Widget> buildColumnWidgets(
                                      List<String> keys,
                                    ) {
                                      return keys
                                          .where(
                                            (key) =>
                                                (_sectionVisibility[key] ??
                                                    true) &&
                                                sectionBuilders.containsKey(
                                                  key,
                                                ),
                                          )
                                          .map((key) {
                                            final section =
                                                sectionBuilders[key]!();
                                            final isolateTabletSection =
                                                isTablet &&
                                                const <String>{
                                                  'agenda',
                                                  'countdowns',
                                                  'todos',
                                                  'timeline',
                                                }.contains(key);
                                            final columnSection =
                                                AppSystemUiRegion(
                                                  backgroundBrightness:
                                                      cardBackgroundBrightness,
                                                  child: Padding(
                                                    padding:
                                                        const EdgeInsets.only(
                                                          bottom: 24.0,
                                                        ),
                                                    child:
                                                        isolateTabletSection &&
                                                            !showWallpaper
                                                        ? RepaintBoundary(
                                                            child: section,
                                                          )
                                                        : section,
                                                  ),
                                                );
                                            return columnSection;
                                          })
                                          .toList();
                                    }

                                    List<Widget> leftWidgets =
                                        buildColumnWidgets(currentLeft);
                                    List<Widget> rightWidgets =
                                        buildColumnWidgets(currentRight);

                                    return OptionalLiquidGlassScrollOptimizer(
                                      child: SingleChildScrollView(
                                        padding: EdgeInsets.fromLTRB(
                                          isTablet ? 32 : 16,
                                          headerExtent + 16,
                                          isTablet ? 32 : 16,
                                          16 +
                                              bottomSystemInset +
                                              (isTablet ? 100.0 : 0.0),
                                        ),
                                        child: Align(
                                          alignment: Alignment.topCenter,
                                          child: ConstrainedBox(
                                            constraints: const BoxConstraints(
                                              maxWidth: 1400,
                                            ),
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
                                                                  leftWidgets,
                                                            ),
                                                          ),
                                                          if (rightWidgets
                                                              .isNotEmpty)
                                                            const SizedBox(
                                                              width: 40,
                                                            ),
                                                          if (rightWidgets
                                                              .isNotEmpty)
                                                            Expanded(
                                                              flex: 11,
                                                              child: Column(
                                                                crossAxisAlignment:
                                                                    CrossAxisAlignment
                                                                        .start,
                                                                children:
                                                                    rightWidgets,
                                                              ),
                                                            ),
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
                                                if (_wallpaperCopyright !=
                                                        null &&
                                                    _wallpaperCopyright!
                                                        .isNotEmpty)
                                                  _buildWallpaperCopyright(
                                                    isLight,
                                                  ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                                ),
                        ],
                      );
                    },
                  ),
                ],
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
      menuScreen: HomeDrawerMenu(
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
      ),
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

  Future<void> _openSettingsFromDrawer(
    GlobalKey sourceKey, {
    String? initialTarget,
    bool checkUpdatesOnOpen = false,
    BorderRadius sourceBorderRadius = const BorderRadius.all(
      Radius.circular(16),
    ),
    IconData placeholderIcon = Icons.settings_rounded,
  }) async {
    await PageTransitions.pushFromRect(
      context: context,
      page: SettingsPage(
        initialTarget: initialTarget,
        checkUpdatesOnOpen: checkUpdatesOnOpen,
      ),
      sourceKey: sourceKey,
      sourceBorderRadius: sourceBorderRadius,
      placeholderIcon: placeholderIcon,
    );
    if (!mounted) return;
    _loadSectionPreferences();
    _loadSemesterSettings();
    await _loadHomeTextConfig();
    if (mounted) _loadAllData(deferred: true);
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
        final response = await _githubResourceService.get(
          Uri.parse(wallpaperUrl),
        );
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
        AppSnackBars.showSnackBar(
          context,
          SnackBar(content: Text('已保存到 $savedPath')),
        );
      }
    } catch (e) {
      // debugPrint('下载壁纸失败: $e');
      if (mounted) {
        AppSnackBars.showSnackBar(context, SnackBar(content: Text('下载失败: $e')));
      }
    }
  }

  String _wallpaperExtension(String url) {
    final ext = url.split('?').first.split('.').last.toLowerCase();
    if (ext == 'png' || ext == 'webp' || ext == 'gif') return ext;
    return 'jpg';
  }

  Future<void> _openHomePomodoro({GlobalKey? sourceKey}) async {
    final page = PomodoroScreen(username: widget.username);
    if (sourceKey == null) {
      await Navigator.of(context).push(PageTransitions.slideHorizontal(page));
    } else {
      await PageTransitions.pushFromRect(
        context: context,
        page: page,
        sourceKey: sourceKey,
        placeholderIcon: Icons.timer_outlined,
        sourceBorderRadius: const BorderRadius.all(Radius.circular(16)),
      );
    }
    if (mounted) {
      _pomodoroRevision.value++;
      _timelineRevision.value++;
    }
  }

  Future<void> _openHomeFinanceQuickEntry() async {
    await PageTransitions.pushFromRect<FinanceTransaction>(
      context: context,
      page: const FinanceEntryScreen(),
      sourceKey: _homeAddActionKey,
      placeholderIcon: Icons.account_balance_wallet_outlined,
      sourceBorderRadius: const BorderRadius.all(Radius.circular(22)),
    );
  }

  Future<TodoCreateSaveResult> _saveManualTodo(TodoItem todo) async {
    final allTodos = await StorageService.getTodos(widget.username);
    final existingIndex = allTodos.indexWhere((item) => item.id == todo.id);
    if (existingIndex < 0) {
      allTodos.add(todo);
    } else {
      allTodos[existingIndex] = todo;
    }
    await StorageService.saveTodos(widget.username, allTodos);

    return _finishManualTodoSave(todo, allTodos);
  }

  Future<FixedScheduleTodoSaveResult> _saveTodoLinkedToFixedSchedule(
    TodoItem todo,
    FixedScheduleItem baseline,
  ) async {
    final updatedSchedule = await StorageService.saveTodoLinkedToFixedSchedule(
      widget.username,
      todo,
      baseline,
    );
    var snapshotReady = true;
    List<TodoItem> allTodos;
    try {
      allTodos = await StorageService.getTodos(widget.username);
    } catch (_) {
      snapshotReady = false;
      allTodos = _todos.map((item) => item.detachedCopy()).toList();
      final index = allTodos.indexWhere((item) => item.id == todo.id);
      if (index < 0) {
        allTodos.add(todo);
      } else {
        allTodos[index] = todo;
      }
    }
    final saveResult = await _finishManualTodoSave(
      todo,
      allTodos,
      refreshDomains: const {
        DataRefreshDomain.todos,
        DataRefreshDomain.fixedSchedules,
      },
      updateSharedSnapshots: snapshotReady,
      extraWarnings: snapshotReady ? const [] : const ['待办列表刷新失败'],
    );
    return FixedScheduleTodoSaveResult(
      schedule: updatedSchedule,
      warnings: saveResult.warnings,
    );
  }

  Future<TodoCreateSaveResult> _finishManualTodoSave(
    TodoItem todo,
    List<TodoItem> allTodos, {
    Set<DataRefreshDomain> refreshDomains = const {DataRefreshDomain.todos},
    bool updateSharedSnapshots = true,
    List<String> extraWarnings = const [],
  }) async {
    final warnings = <String>[...extraWarnings];
    Future<void> tryUpdate(
      String warning,
      FutureOr<void> Function() update,
    ) async {
      try {
        await update();
      } catch (_) {
        warnings.add(warning);
      }
    }

    if (todo.teamUuid != null) {
      await tryUpdate('团队状态待更新', () {
        PomodoroSyncService.instance.sendTeamUpdateSignal(todo.teamUuid!);
      });
    }
    if (updateSharedSnapshots) {
      await tryUpdate('共享状态待更新', () async {
        if (!await _saveTodosToSharedFile(allTodos)) {
          throw StateError('shared todo snapshot was not updated');
        }
      });
    } else {
      warnings.add('共享状态与桌面小组件待更新');
    }
    await tryUpdate('提醒待更新', () {
      FloatWindowService.triggerReminderCheck();
      FloatWindowService.invalidateSlotCache();
      _syncTodoNotification();
      _rescheduleAlarms();
    });
    if (updateSharedSnapshots) {
      await tryUpdate('桌面小组件待更新', () async {
        await WidgetService.updateTodoWidget(allTodos);
      });
    }
    await tryUpdate('首页列表待刷新', () async {
      if (mounted) {
        await _loadAllData(deferred: true, domains: refreshDomains);
        if (refreshDomains.contains(DataRefreshDomain.fixedSchedules)) {
          _scheduleRevision.value++;
          _timelineRevision.value++;
        }
      }
    });
    return TodoCreateSaveResult(warnings: warnings);
  }

  Future<void> _openHomeTodo({GlobalKey? sourceKey}) async {
    final page = AddTodoScreen(
      todoGroups: _todoGroups,
      initialTeamUuid: _currentSelectedTeamUuid,
      initialTeamName: _currentSelectedTeamName,
      onFixedScheduleAdded: (item) async {
        await StorageService.saveFixedSchedules(widget.username, [item]);
        if (mounted) {
          _scheduleRevision.value++;
          _timelineRevision.value++;
          await _loadAllData(
            deferred: true,
            domains: const {DataRefreshDomain.fixedSchedules},
          );
        }
      },
      onTodoAdded: (todo) async {
        await _saveManualTodo(todo);
      },
      onManualTodoSaved: _saveManualTodo,
      onTodosBatchAdded: (todos) async {
        final allTodos = await StorageService.getTodos(widget.username);
        final indexById = <String, int>{};
        for (var index = 0; index < allTodos.length; index++) {
          indexById.putIfAbsent(allTodos[index].id, () => index);
        }
        for (final todo in todos) {
          final index = indexById[todo.id];
          if (index == null) {
            indexById[todo.id] = allTodos.length;
            allTodos.add(todo);
          } else {
            allTodos[index] = todo;
          }
        }
        await StorageService.saveTodos(widget.username, allTodos);
        final warnings = <String>[];
        final updatedTeamUuid = todos
            .firstWhere((t) => t.teamUuid != null, orElse: () => todos.first)
            .teamUuid;
        if (updatedTeamUuid != null) {
          try {
            PomodoroSyncService.instance.sendTeamUpdateSignal(updatedTeamUuid);
          } catch (_) {
            warnings.add('团队状态待更新');
          }
        }
        if (!await _saveTodosToSharedFile(allTodos)) {
          warnings.add('共享状态待更新');
        }
        try {
          FloatWindowService.triggerReminderCheck();
          FloatWindowService.invalidateSlotCache();
          _syncTodoNotification();
          _rescheduleAlarms();
        } catch (_) {
          warnings.add('提醒状态待更新');
        }
        try {
          await WidgetService.updateTodoWidget(allTodos);
        } catch (_) {
          warnings.add('桌面小组件待更新');
        }
        try {
          if (mounted) {
            await _loadAllData(
              deferred: true,
              domains: const {DataRefreshDomain.todos},
            );
          }
        } catch (_) {
          warnings.add('首页列表待刷新');
        }
        if (mounted && warnings.isNotEmpty) {
          AppSnackBars.showSnackBar(
            context,
            SnackBar(content: Text('待办已保存；${warnings.join('；')}')),
          );
        }
      },
      onLLMResultsParsed: (results, imagePath, originalText, tUuid, tName) {
        Navigator.pop(context);
        _navigateToTodoConfirm(results, imagePath, originalText, tUuid, tName);
      },
    );
    if (sourceKey == null) {
      await Navigator.of(context).push(PageTransitions.slideHorizontal(page));
    } else {
      await PageTransitions.pushFromRect(
        context: context,
        page: page,
        sourceKey: sourceKey,
        sourceBorderRadius: const BorderRadius.all(Radius.circular(16)),
      );
    }
  }

  Future<void> _openHomeAddCountdown() {
    return showCountdownEditorDialog(
      context: context,
      username: widget.username,
      countdowns: _countdowns,
      onDataChanged: () {
        _loadAllData(domains: const {DataRefreshDomain.countdowns});
        _timelineRevision.value++;
      },
    );
  }

  Widget _buildHomeAddOption(
    BuildContext context, {
    required Key key,
    required _HomeAddAction action,
    required IconData icon,
    required String title,
    required String subtitle,
    void Function(ModalRoute<_HomeAddAction>?)? onBeforeSelect,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.42),
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: key,
        onTap: () {
          onBeforeSelect?.call(ModalRoute.of<_HomeAddAction>(context));
          Navigator.of(context).pop(action);
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer,
                  shape: BoxShape.circle,
                ),
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Icon(
                    icon,
                    color: colorScheme.onPrimaryContainer,
                    size: 24,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 3),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openHomeAddMenu() async {
    ModalRoute<_HomeAddAction>? menuRoute;
    final action = await showAppModalBottomSheet<_HomeAddAction>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
              child: Text(
                '新增',
                style: Theme.of(context).textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
            ),
            SizedBox(
              height: 132,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: _buildHomeAddOption(
                      context,
                      key: const ValueKey<String>('home-add-todo'),
                      action: _HomeAddAction.todo,
                      icon: Icons.add_task_rounded,
                      title: '待办',
                      subtitle: '记录任务',
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _buildHomeAddOption(
                      context,
                      key: const ValueKey<String>('home-add-countdown'),
                      action: _HomeAddAction.countdown,
                      icon: Icons.timer_rounded,
                      title: '倒计时',
                      subtitle: '设定目标日',
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _buildHomeAddOption(
                      context,
                      key: const ValueKey<String>('home-add-finance'),
                      action: _HomeAddAction.finance,
                      icon: Icons.account_balance_wallet_outlined,
                      title: '记账',
                      subtitle: '收入或支出',
                      onBeforeSelect: (route) => menuRoute = route,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;

    if (action == _HomeAddAction.finance) {
      // The sheet result arrives before its exit animation finishes.
      await menuRoute?.completed;
      if (!mounted) return;
    }

    switch (action) {
      case _HomeAddAction.todo:
        await _openHomeTodo(sourceKey: _homeAddActionKey);
      case _HomeAddAction.countdown:
        await _openHomeAddCountdown();
      case _HomeAddAction.finance:
        await _openHomeFinanceQuickEntry();
    }
  }

  Widget _buildCustomBottomBar(bool isDarkMode, bool isLight, bool isWide) {
    final colorScheme = Theme.of(context).colorScheme;
    final Color primaryColor = homeBottomBarPrimaryColor(
      colorScheme: colorScheme,
      hasWallpaper: isLight,
      wallpaperDominantColor: _wallpaperDominantColor,
    );
    final Color inactiveColor = isLight
        ? colorScheme.scrim.withValues(alpha: 0.86)
        : colorScheme.onSurfaceVariant;
    final double bottomPadding = MediaQuery.viewPaddingOf(context).bottom;
    // The reference rests as a neutral frosted capsule. Keep only a trace of
    // the action color here; the icon and label carry the strong selection.
    final selectedBackgroundColor = homeBottomBarSelectedBackgroundColor(
      colorScheme: colorScheme,
      primaryColor: primaryColor,
      isDark: isDarkMode,
    );

    final double height =
        60.0 + (bottomPadding > 0 ? bottomPadding * 0.5 : 6.0);
    final margin = floatingBottomNavigationMarginFor(
      context,
      itemCount: isWide ? 3 : 5,
    );

    final glassTint = Color.alphaBlend(
      primaryColor.withValues(alpha: 0.08),
      colorScheme.surface,
    ).withValues(alpha: isDarkMode ? 0.24 : 0.32);

    return _HomeDashboardBottomBar(
      selectedIndex: _selectedTabIndex,
      primaryColor: primaryColor,
      inactiveColor: inactiveColor,
      selectedBackgroundColor: selectedBackgroundColor,
      weeklyButtonKey: _courseCenterKey,
      addButtonKey: _homeAddActionKey,
      pomodoroButtonKey: _homePomodoroActionKey,
      isWide: isWide,
      height: height,
      margin: margin,
      isDarkMode: isDarkMode,
      glassTint: glassTint,
      onTabSelected: (index) {
        setState(() {
          _selectedTabIndex = index;
          if (index == _homeFocusTabIndex) {
            _focusTabVisited = true;
          }
        });
        if (index == _homeFocusTabIndex) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _checkFocusTabCoachMarks();
          });
        }
      },
      onWeeklyPressed: () {
        PageTransitions.pushFromRect(
          context: context,
          page: WeeklyCourseScreen(
            username: widget.username,
            onCreateRelatedTodo: _saveTodoLinkedToFixedSchedule,
          ),
          sourceKey: _courseCenterKey,
        );
      },
      onAddPressed: () {
        _openHomeAddMenu();
      },
      onAddLongPress: _openQuickVoiceChat,
      onAddLongPressStart: _startQuickVoiceGesture,
      onAddLongPressMoveUpdate: _moveQuickVoiceGesture,
      onAddLongPressEnd: _endQuickVoiceGesture,
      onAddLongPressCancel: _cancelQuickVoiceGesture,
      onPomodoroPressed: () {
        _openHomePomodoro(sourceKey: _homePomodoroActionKey);
      },
    );
  }

  bool _isRevisionedEntityEqual(Object? a, Object? b) {
    if (a is TodoItem && b is TodoItem) {
      return a.id == b.id &&
          a.version == b.version &&
          a.updatedAt == b.updatedAt &&
          a.isDone == b.isDone &&
          a.isDeleted == b.isDeleted &&
          a.hasConflict == b.hasConflict;
    }
    if (a is TodoGroup && b is TodoGroup) {
      return a.id == b.id &&
          a.version == b.version &&
          a.updatedAt == b.updatedAt &&
          a.isExpanded == b.isExpanded &&
          a.isDeleted == b.isDeleted &&
          a.hasConflict == b.hasConflict;
    }
    if (a is CountdownItem && b is CountdownItem) {
      return a.id == b.id &&
          a.version == b.version &&
          a.updatedAt == b.updatedAt &&
          a.isCompleted == b.isCompleted &&
          a.isDeleted == b.isDeleted &&
          a.hasConflict == b.hasConflict;
    }
    if (a is TodoPlanBlock && b is TodoPlanBlock) {
      return a.id == b.id &&
          a.version == b.version &&
          a.updatedAt == b.updatedAt &&
          a.status == b.status &&
          a.isDeleted == b.isDeleted;
    }
    if (a is FixedScheduleItem && b is FixedScheduleItem) {
      return a.id == b.id &&
          a.version == b.version &&
          a.updatedAt == b.updatedAt &&
          a.status == b.status &&
          a.isDeleted == b.isDeleted;
    }
    if (a is CourseItem && b is CourseItem) {
      return a.uuid == b.uuid &&
          a.version == b.version &&
          a.updatedAt == b.updatedAt &&
          a.isDeleted == b.isDeleted;
    }
    return false;
  }

  bool _isDeepValueEqual(Object? a, Object? b) {
    if (identical(a, b)) return true;
    if (a == null || b == null || a.runtimeType != b.runtimeType) return false;
    if (_isRevisionedEntityEqual(a, b)) return true;
    if (a is List && b is List) {
      if (a.length != b.length) return false;
      for (var index = 0; index < a.length; index++) {
        if (!_isDeepValueEqual(a[index], b[index])) return false;
      }
      return true;
    }
    if (a is Map && b is Map) {
      if (a.length != b.length) return false;
      for (final key in a.keys) {
        if (!b.containsKey(key) || !_isDeepValueEqual(a[key], b[key])) {
          return false;
        }
      }
      return true;
    }
    return a == b;
  }

  // 内容级比较用于阻止相同数据库快照触发无意义的模块重建。
  bool _isListEqual(List a, List b) {
    return _isDeepValueEqual(a, b);
  }

  bool _isMapEqual(Map a, Map b) {
    return _isDeepValueEqual(a, b);
  }

  Widget _buildOnboardingChecklistSection(bool isLight) {
    final courses = _safeListResult<CourseItem>(
      _dashboardCourseData['courses'],
    );
    final hasTodosOrCountdowns =
        _todos.any((t) => !t.isDeleted) || _countdowns.any((c) => !c.isDeleted);
    final hasCoursesOrSchedules = courses.any((c) => !c.isDeleted);
    final hasPlanBlocks = _planBlocks.any((b) => !b.isDeleted);

    return OnboardingChecklistCard(
      isLight: isLight,
      hasTodosOrCountdowns: hasTodosOrCountdowns,
      hasCoursesOrSchedules: hasCoursesOrSchedules,
      hasPlanBlocks: hasPlanBlocks,
      onLaunchTask: _handleOnboardingTaskLaunch,
      onSpotlightTask: _handleOnboardingTaskSpotlight,
      onOpenFeatureExplorer: () {
        Navigator.of(context, rootNavigator: true).push(
          PageTransitions.slideHorizontal(
            FeatureExplorerScreen(username: widget.username),
          ),
        );
      },
    );
  }

  Future<void> _handleOnboardingTaskLaunch(String taskId) async {
    await OnboardingChecklistService.markTaskCompleted(taskId);
    if (!mounted) return;
    switch (taskId) {
      case OnboardingChecklistService.taskCreateTodoOrCountdown:
        await _openHomeAddMenu();
      case OnboardingChecklistService.taskCourseOrSchedule:
        await PageTransitions.pushFromRect(
          context: context,
          page: WeeklyCourseScreen(
            username: widget.username,
            onCreateRelatedTodo: _saveTodoLinkedToFixedSchedule,
          ),
          sourceKey: _courseCenterKey,
        );
      case OnboardingChecklistService.taskPlanBlock:
        await Navigator.of(context).push(
          PageTransitions.material(
            builder: (_) => TodoPlanScreen(username: widget.username),
          ),
        );
        if (mounted) {
          _scheduleRevision.value++;
          _loadAllData(
            domains: const {
              DataRefreshDomain.todos,
              DataRefreshDomain.planBlocks,
              DataRefreshDomain.fixedSchedules,
            },
          );
        }
      case OnboardingChecklistService.taskPomodoroFocus:
        await _openHomePomodoro(sourceKey: _homePomodoroActionKey);
      case OnboardingChecklistService.taskAiOrQuickVoice:
        await _openAiAssistantFromAppBar();
      case OnboardingChecklistService.taskExploreFeatureHub:
        await Navigator.of(context, rootNavigator: true).push(
          PageTransitions.slideHorizontal(
            FeatureExplorerScreen(username: widget.username),
          ),
        );
    }
  }

  Future<void> _handleOnboardingTaskSpotlight(String taskId) async {
    if (_showCoachMarks || !mounted) return;
    final CoachMarkStep? step = switch (taskId) {
      OnboardingChecklistService.taskCreateTodoOrCountdown => CoachMarkStep(
        targetKey: _homeAddActionKey,
        title: '新建待办 / 倒计时 / 记账',
        description: '点这里可快速创建待办事项、重要日倒计时或记一笔账；长按还能直接语音速记！',
        buttonLabel: '立即打开',
        finishOnButtonTap: true,
        onButtonTap: () {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _handleOnboardingTaskLaunch(taskId);
          });
        },
      ),
      OnboardingChecklistService.taskCourseOrSchedule => CoachMarkStep(
        targetKey: _courseCenterKey,
        title: '周视图与课程表/固定日程',
        description: '在这里查看整周课程表、创建每周重复的固定日程，并支持将待办关联到固定日程。',
        buttonLabel: '进入周视图',
        finishOnButtonTap: true,
        onButtonTap: () {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _handleOnboardingTaskLaunch(taskId);
          });
        },
      ),
      OnboardingChecklistService.taskPlanBlock => CoachMarkStep(
        targetKey: _todayPlanChartKey,
        title: '今日日程与规划中心',
        description: '点击这里可将待办安排到具体时间块，把“要做什么”变成“什么时候做”。',
        buttonLabel: '去规划',
        finishOnButtonTap: true,
        onButtonTap: () {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _handleOnboardingTaskLaunch(taskId);
          });
        },
      ),
      OnboardingChecklistService.taskPomodoroFocus => CoachMarkStep(
        targetKey: _homePomodoroActionKey,
        title: '番茄钟专注工作台',
        description: '点击这里开启番茄钟倒计时或正计时专注，支持绑定待办并跨设备实时同步专注状态。',
        buttonLabel: '去专注',
        finishOnButtonTap: true,
        onButtonTap: () {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _handleOnboardingTaskLaunch(taskId);
          });
        },
      ),
      OnboardingChecklistService.taskAiOrQuickVoice => CoachMarkStep(
        targetKey: _aiButtonKey,
        title: 'AI 智能助手',
        description: '点击顶部机器人图标进入 AI 对话，或长按底部「+」按钮语音速记，一句话搞定排期与记账。',
        buttonLabel: '打开 AI 助手',
        finishOnButtonTap: true,
        onButtonTap: () {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _handleOnboardingTaskLaunch(taskId);
          });
        },
      ),
      OnboardingChecklistService.taskExploreFeatureHub => CoachMarkStep(
        targetKey: _menuKey,
        title: '侧边栏与功能百宝箱',
        description: '点击左上角打开侧边栏，可随时进入「功能百宝箱」、记账、习惯中心、挑战中心、私密日记与设置中心。',
        buttonLabel: '打开百宝箱',
        finishOnButtonTap: true,
        onButtonTap: () {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _handleOnboardingTaskLaunch(taskId);
          });
        },
      ),
      _ => null,
    };
    if (step == null || step.targetKey.currentContext == null) {
      await _handleOnboardingTaskLaunch(taskId);
      return;
    }
    _showCoachMarks = true;
    try {
      await CoachMarkOverlay.show(
        context: context,
        steps: [step],
        onFinish: () => _showCoachMarks = false,
        onSkip: () => _showCoachMarks = false,
      );
    } finally {
      _showCoachMarks = false;
    }
  }

  Widget _buildDashboardSkeleton(bool isLight, {double topPadding = 16}) {
    final baseColor = isLight
        ? Colors.white.withValues(alpha: 0.3)
        : Colors.grey[800]!;
    return SingleChildScrollView(
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(16, topPadding, 16, 16),
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

class _HomeDashboardBottomBar extends StatelessWidget {
  const _HomeDashboardBottomBar({
    required this.selectedIndex,
    required this.primaryColor,
    required this.inactiveColor,
    required this.selectedBackgroundColor,
    required this.weeklyButtonKey,
    required this.addButtonKey,
    required this.pomodoroButtonKey,
    required this.isWide,
    required this.onTabSelected,
    required this.onWeeklyPressed,
    required this.onAddPressed,
    required this.onAddLongPress,
    required this.onAddLongPressStart,
    required this.onAddLongPressMoveUpdate,
    required this.onAddLongPressEnd,
    required this.onAddLongPressCancel,
    required this.onPomodoroPressed,
    required this.height,
    required this.margin,
    required this.isDarkMode,
    required this.glassTint,
  });

  final int selectedIndex;
  final Color primaryColor;
  final Color inactiveColor;
  final Color selectedBackgroundColor;
  final Key weeklyButtonKey;
  final Key addButtonKey;
  final Key pomodoroButtonKey;
  final bool isWide;
  final ValueChanged<int> onTabSelected;
  final VoidCallback onWeeklyPressed;
  final VoidCallback onAddPressed;
  final VoidCallback onAddLongPress;
  final GestureLongPressStartCallback onAddLongPressStart;
  final GestureLongPressMoveUpdateCallback onAddLongPressMoveUpdate;
  final GestureLongPressEndCallback onAddLongPressEnd;
  final VoidCallback onAddLongPressCancel;
  final VoidCallback onPomodoroPressed;
  final double height;
  final EdgeInsets margin;
  final bool isDarkMode;
  final Color glassTint;

  @override
  Widget build(BuildContext context) {
    FloatingBottomNavigationItem buildWeeklyItem() {
      return FloatingBottomNavigationItem(
        key: weeklyButtonKey,
        label: '周视图',
        icon: Icons.calendar_today_outlined,
        selectedIcon: Icons.calendar_today_rounded,
        selectable: false,
        onPressed: onWeeklyPressed,
        semanticsLabel: '周视图',
      );
    }

    FloatingBottomNavigationItem buildAddItem() {
      return FloatingBottomNavigationItem(
        label: '新增',
        selectable: false,
        onPressed: onAddPressed,
        onLongPress: onAddLongPress,
        onLongPressStart: onAddLongPressStart,
        onLongPressMoveUpdate: onAddLongPressMoveUpdate,
        onLongPressEnd: onAddLongPressEnd,
        onLongPressCancel: onAddLongPressCancel,
        builder: (context, selectedLayer, interactive) => Center(
          child: AiWaterRippleBorder(
            isLight: Theme.of(context).brightness == Brightness.light,
            borderRadius: BorderRadius.circular(28),
            child: HomeBottomNavigationActionButton(
              buttonKey: selectedLayer ? null : addButtonKey,
              primaryColor: primaryColor,
              interactive: interactive,
              onPressed: onAddPressed,
              onLongPress: onAddLongPress,
              semanticsLabel: '新增',
              child: Icon(
                selectedLayer ? Icons.add_circle_rounded : Icons.add_rounded,
                color: Theme.of(context).colorScheme.onPrimary,
                size: 28,
              ),
            ),
          ),
        ),
      );
    }

    FloatingBottomNavigationItem buildPomodoroItem() {
      return FloatingBottomNavigationItem(
        key: pomodoroButtonKey,
        label: '番茄钟',
        icon: Icons.timer_outlined,
        selectedIcon: Icons.timer_rounded,
        selectable: false,
        onPressed: onPomodoroPressed,
        semanticsLabel: '番茄钟',
      );
    }

    final items = isWide
        ? <FloatingBottomNavigationItem>[
            buildWeeklyItem(),
            buildAddItem(),
            buildPomodoroItem(),
          ]
        : <FloatingBottomNavigationItem>[
            const FloatingBottomNavigationItem(
              icon: Icons.dashboard_outlined,
              selectedIcon: Icons.dashboard_rounded,
              label: '首页',
            ),
            buildWeeklyItem(),
            buildAddItem(),
            buildPomodoroItem(),
            const FloatingBottomNavigationItem(
              icon: Icons.center_focus_weak_rounded,
              selectedIcon: Icons.center_focus_strong_rounded,
              label: '专注',
            ),
          ];

    return FloatingBottomNavigationBar(
      items: items,
      selectedIndex: isWide ? 0 : selectedIndex,
      primaryColor: primaryColor,
      inactiveColor: inactiveColor,
      selectedBackgroundColor: selectedBackgroundColor,
      onTabSelected: onTabSelected,
      height: height,
      margin: margin,
      tint: glassTint,
      haloColor: primaryColor,
      isDark: isDarkMode,
      mobilePortraitOnly: false,
      showSelectionLens: !isWide,
      keyPrefix: 'home-bottom',
    );
  }
}
