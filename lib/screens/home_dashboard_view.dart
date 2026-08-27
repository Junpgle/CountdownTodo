part of 'home_dashboard.dart';
// ignore_for_file: annotate_overrides

mixin _HomeDashboardViewMixin on _HomeDashboardStateBase {
  Widget build(BuildContext context) {
    bool isDarkMode = Theme.of(context).brightness == Brightness.dark;
    bool showWallpaper = !isDarkMode && _wallpaperShow && _wallpaperUrl != null;
    bool isLight = showWallpaper;
    final bool isTablet = MediaQuery.of(context).size.width >= 768;
    final double bottomSystemInset = MediaQuery.viewPaddingOf(context).bottom;
    final Brightness cardBackgroundBrightness =
        isDarkMode ? Brightness.dark : Brightness.light;

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
            // 仅避让顶部状态栏。列表需要继续绘制到 Android 手势导航区
            // 后方，末尾的滚动余量再保证卡片操作不会被底栏遮挡。
            bottom: false,
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
                    syncKey: _syncButtonKey,
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
                                    Widget courseSection = AnimatedBuilder(
                                      animation: Listenable.merge([
                                        _todosNotifier,
                                        _courseDataNotifier,
                                        _scheduleRevision,
                                      ]),
                                      builder: (context, _) {
                                        return CourseSectionWidget(
                                          dashboardCourseData:
                                              _dashboardCourseData,
                                          todos: _todos,
                                          isLight: isLight,
                                          username: widget.username,
                                          refreshTrigger:
                                              _scheduleRevision.value,
                                          actionKey: _todayPlanChartKey,
                                          onTodoAdded: (todo) =>
                                              _handleTodosChanged([
                                            ..._todos,
                                            todo,
                                          ]),
                                        );
                                      },
                                    );
                                    Widget countdownSection =
                                        ValueListenableBuilder<
                                            List<CountdownItem>>(
                                      valueListenable: _countdownsNotifier,
                                      builder: (context, countdowns, _) =>
                                          CountdownSectionWidget(
                                              historyKey: _countdownHistoryKey,
                                              countdowns: countdowns,
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
                                              }),
                                    );
                                    Widget todoSection = AnimatedBuilder(
                                      animation: Listenable.merge([
                                        _todosNotifier,
                                        _groupsNotifier,
                                        _todoUpdateSignalNotifier,
                                      ]),
                                      builder: (context, _) {
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
                                                          _screenTimeStats),
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
                                    Widget mathSection = ValueListenableBuilder<
                                        Map<String, dynamic>>(
                                      valueListenable: _mathStatsNotifier,
                                      builder: (context, stats, _) =>
                                          RepaintBoundary(
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
                                                  stats: stats,
                                                  isLight: isLight,
                                                  onTap: () async {
                                                    await PageTransitions
                                                        .pushFromRect(
                                                      context: context,
                                                      page: MathMenuScreen(
                                                          username:
                                                              widget.username),
                                                      sourceKey: _mathCardKey,
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
                                                  }),
                                            ],
                                          ),
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

                                    Map<String, Widget> sectionsMap = {
                                      'banners': AnimatedBuilder(
                                        animation: Listenable.merge([
                                          _pomodoroTickNotifier,
                                          _todosNotifier,
                                          _courseDataNotifier,
                                          _scheduleRevision,
                                        ]),
                                        builder: (_, __) =>
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
                                                    placeholderIcon:
                                                        Icons.repeat_rounded,
                                                    sourceBorderRadius:
                                                        BorderRadius.circular(
                                                            24),
                                                  );
                                                  _habitsRevision.value++;
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

                                      Widget buildScrollableSection(
                                          String key) {
                                        return AppSystemUiRegion(
                                          backgroundBrightness:
                                              cardBackgroundBrightness,
                                          child: Padding(
                                            padding: const EdgeInsets.only(
                                                bottom: 24.0),
                                            child: sectionsMap[key]!,
                                          ),
                                        );
                                      }

                                      List<Widget> tab1Widgets = tab1Order
                                          .where((key) =>
                                              (_sectionVisibility[key] ??
                                                  true) &&
                                              sectionsMap.containsKey(key))
                                          .map(buildScrollableSection)
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
                                              .map(buildScrollableSection)
                                              .toList();

                                      final showFocusTab =
                                          _selectedTabIndex == 2;
                                      final activeWidgets = showFocusTab
                                          ? tab3Widgets
                                          : tab1Widgets;
                                      final hasCopyright =
                                          _wallpaperCopyright?.isNotEmpty ??
                                              false;
                                      return AnimatedSwitcher(
                                        duration:
                                            const Duration(milliseconds: 280),
                                        reverseDuration:
                                            const Duration(milliseconds: 240),
                                        switchInCurve: Curves.easeOutCubic,
                                        switchOutCurve: Curves.easeInCubic,
                                        layoutBuilder:
                                            (currentChild, previousChildren) {
                                          return Stack(
                                            fit: StackFit.expand,
                                            children: [
                                              ...previousChildren,
                                              if (currentChild != null)
                                                currentChild,
                                            ],
                                          );
                                        },
                                        transitionBuilder: (child, animation) {
                                          final focusPage = child.key ==
                                              const ValueKey<String>(
                                                  'home-focus-tab-content');
                                          return FadeTransition(
                                            opacity: animation,
                                            child: SlideTransition(
                                              position: Tween<Offset>(
                                                begin: Offset(
                                                    focusPage ? 0.035 : -0.035,
                                                    0),
                                                end: Offset.zero,
                                              ).animate(animation),
                                              child: child,
                                            ),
                                          );
                                        },
                                        child: RepaintBoundary(
                                          key: ValueKey<String>(showFocusTab
                                              ? 'home-focus-tab-content'
                                              : 'home-main-tab-content'),
                                          child:
                                              OptionalLiquidGlassScrollOptimizer(
                                            child: ListView.builder(
                                              key: PageStorageKey<String>(
                                                showFocusTab
                                                    ? 'home-focus-sections'
                                                    : 'home-main-sections',
                                              ),
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                horizontal: 16,
                                                vertical: 16,
                                              ),
                                              itemCount: activeWidgets.length +
                                                  (hasCopyright ? 1 : 0) +
                                                  1,
                                              itemBuilder: (context, index) {
                                                if (index <
                                                    activeWidgets.length) {
                                                  return activeWidgets[index];
                                                }
                                                if (hasCopyright &&
                                                    index ==
                                                        activeWidgets.length) {
                                                  return _buildWallpaperCopyright(
                                                      isLight);
                                                }
                                                return SizedBox(
                                                  // 浮动底栏原有 100dp 余量之外，再补上
                                                  // 系统手势区，使最后一张卡片能完整滚出遮挡。
                                                  height:
                                                      100 + bottomSystemInset,
                                                );
                                              },
                                            ),
                                          ),
                                        ),
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
                                          .map((key) => AppSystemUiRegion(
                                                backgroundBrightness:
                                                    cardBackgroundBrightness,
                                                child: Padding(
                                                  padding:
                                                      const EdgeInsets.only(
                                                          bottom: 24.0),
                                                  child: sectionsMap[key]!,
                                                ),
                                              ))
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
                                          16,
                                          isTablet ? 32 : 16,
                                          16 + bottomSystemInset,
                                        ),
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
                                                if (_wallpaperCopyright !=
                                                        null &&
                                                    _wallpaperCopyright!
                                                        .isNotEmpty)
                                                  _buildWallpaperCopyright(
                                                      isLight),
                                              ],
                                            ),
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
      // 专注页的卡片自身带有「开始专注/查看记录」按钮，悬浮按钮会覆盖
      // 这些操作，因此仅在首页显示浮动入口。
      floatingActionButton: (!isTablet && _selectedTabIndex == 2)
          ? null
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                HomeQuickActionButton.compact(
                  key: _fabPomodoroKey,
                  heroTag: 'fab_pomodoro',
                  onPressed: () async {
                    await PageTransitions.pushFromRect(
                      context: context,
                      page: PomodoroScreen(username: widget.username),
                      sourceKey: _fabPomodoroKey,
                      placeholderIcon: Icons.timer_outlined,
                      sourceBorderRadius:
                          const BorderRadius.all(Radius.circular(16)),
                    );
                    if (mounted) {
                      _pomodoroRevision.value++;
                      _timelineRevision.value++;
                    }
                  },
                  tooltip: '番茄钟',
                  tint: Theme.of(context).colorScheme.primary,
                  foregroundColor: Theme.of(context).colorScheme.primary,
                  isDark: isDarkMode,
                  child: const Text('🍅', style: TextStyle(fontSize: 18)),
                ),
                const SizedBox(height: 8),
                HomeQuickActionButton.extended(
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
                          await _loadAllData(
                            deferred: true,
                            domains: const {DataRefreshDomain.fixedSchedules},
                          );
                        }
                      },
                      onTodoAdded: (todo) async {
                        final allTodos =
                            await StorageService.getTodos(widget.username);
                        allTodos.add(todo);
                        await StorageService.saveTodos(
                            widget.username, allTodos);
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
                          await _loadAllData(
                            deferred: true,
                            domains: const {DataRefreshDomain.todos},
                          );
                        }
                      },
                      onTodosBatchAdded: (todos) async {
                        final allTodos =
                            await StorageService.getTodos(widget.username);
                        allTodos.addAll(todos);
                        await StorageService.saveTodos(
                            widget.username, allTodos);
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
                        if (mounted) {
                          await _loadAllData(
                            deferred: true,
                            domains: const {DataRefreshDomain.todos},
                          );
                        }
                      },
                      onLLMResultsParsed:
                          (results, imagePath, originalText, tUuid, tName) {
                        Navigator.pop(context);
                        _navigateToTodoConfirm(
                            results, imagePath, originalText, tUuid, tName);
                      },
                    ),
                    sourceKey: _fabTodoKey,
                    sourceBorderRadius:
                        const BorderRadius.all(Radius.circular(16)),
                  ),
                  tooltip: '记待办',
                  tint: Theme.of(context).colorScheme.primary,
                  foregroundColor: Theme.of(context).colorScheme.primary,
                  isDark: isDarkMode,
                  icon: const Icon(Icons.add_task),
                  label: const Text("记待办"),
                ),
                const SizedBox(height: 100), // 避开底部的悬浮导航栏
              ],
            ),
    );

    if (isTablet) {
      return AppSystemUiRegion(
        backgroundBrightness:
            showWallpaper || isDarkMode ? Brightness.dark : Brightness.light,
        child: mainScreen,
      );
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
        onOpenUpdateSettings: () {
          Future.delayed(const Duration(milliseconds: 350), () async {
            if (!context.mounted) return;
            await PageTransitions.pushFromRect(
              context: context,
              page: const SettingsPage(initialTarget: 'update'),
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
              sourceKey: _timelineCardKey,
              placeholderIcon: Icons.timeline_rounded,
              sourceColor: Theme.of(context).brightness == Brightness.dark
                  ? Colors.black
                  : Colors.white,
            );
          });
        },
        onJournal: () {
          Future.delayed(const Duration(milliseconds: 300), () async {
            if (!context.mounted) return;
            await PageTransitions.pushFromRect(
              context: context,
              page: JournalHomeScreen(username: widget.username),
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
              sourceKey: _screenTimeCardKey,
              placeholderIcon: Icons.timer_outlined,
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
            _loadAllData(
              deferred: true,
              domains: const {
                DataRefreshDomain.todos,
                DataRefreshDomain.planBlocks,
                DataRefreshDomain.fixedSchedules,
              },
            );
          });
        },
        onHabits: () {
          Future.delayed(const Duration(milliseconds: 300), () async {
            if (!context.mounted) return;
            await PageTransitions.pushFromRect(
              context: context,
              page: HabitCenterScreen(username: widget.username),
              sourceKey: _habitsCardKey,
              placeholderIcon: Icons.repeat_rounded,
            );
            _habitsRevision.value++;
          });
        },
        onChangelog: () {
          Future.delayed(const Duration(milliseconds: 350), () {
            if (!context.mounted) return;
            Navigator.of(context, rootNavigator: true).push(
              PageTransitions.material(
                builder: (context) => FeatureGuideScreen(
                  mode: FeatureGuideMode.changelog,
                  loggedInUser: widget.username,
                ),
              ),
            );
          });
        },
        onChallengeCenter: () {
          Future.delayed(const Duration(milliseconds: 350), () async {
            if (!context.mounted) return;
            await Navigator.of(context, rootNavigator: true).push(
              PageTransitions.slideHorizontal(
                const ThirtyDayChallengeScreen(),
              ),
            );
            if (mounted) _loadThirtyDayChallengeStatus();
          });
        },
        onUpdate: () {
          Future.delayed(const Duration(milliseconds: 300), () {
            if (!context.mounted) return;
            UpdateService.checkUpdateAndPrompt(context, isManual: true);
          });
        },
      ),
      mainScreen: AppSystemUiRegion(
        backgroundBrightness:
            showWallpaper || isDarkMode ? Brightness.dark : Brightness.light,
        child: mainScreen,
      ),
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
        final response =
            await _githubResourceService.get(Uri.parse(wallpaperUrl));
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
    final horizontalMargin =
        homeBottomBarHorizontalMarginFor(MediaQuery.sizeOf(context).width);
    final margin = EdgeInsets.fromLTRB(
      horizontalMargin,
      0,
      horizontalMargin,
      24,
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
      calendarButtonKey: _courseCenterKey,
      height: height,
      margin: margin,
      isDarkMode: isDarkMode,
      glassTint: glassTint,
      onTabSelected: (index) {
        setState(() => _selectedTabIndex = index);
        if (index == 2) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _checkFocusTabCoachMarks();
          });
        }
      },
      onCalendarPressed: () {
        PageTransitions.pushFromRect(
          context: context,
          page: WeeklyCourseScreen(username: widget.username),
          sourceKey: _courseCenterKey,
        );
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

class _HomeDashboardBottomBar extends StatefulWidget {
  const _HomeDashboardBottomBar({
    required this.selectedIndex,
    required this.primaryColor,
    required this.inactiveColor,
    required this.selectedBackgroundColor,
    required this.calendarButtonKey,
    required this.onTabSelected,
    required this.onCalendarPressed,
    required this.height,
    required this.margin,
    required this.isDarkMode,
    required this.glassTint,
  });

  final int selectedIndex;
  final Color primaryColor;
  final Color inactiveColor;
  final Color selectedBackgroundColor;
  final Key calendarButtonKey;
  final ValueChanged<int> onTabSelected;
  final VoidCallback onCalendarPressed;
  final double height;
  final EdgeInsets margin;
  final bool isDarkMode;
  final Color glassTint;

  @override
  State<_HomeDashboardBottomBar> createState() =>
      _HomeDashboardBottomBarState();
}

class _HomeDashboardBottomBarState extends State<_HomeDashboardBottomBar> {
  final ValueNotifier<double> _stretchNotifier = ValueNotifier<double>(0.0);

  @override
  void dispose() {
    _stretchNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final navContent = HomeBottomNavigationContent(
      selectedIndex: widget.selectedIndex,
      primaryColor: widget.primaryColor,
      inactiveColor: widget.inactiveColor,
      selectedBackgroundColor: widget.selectedBackgroundColor,
      calendarButtonKey: widget.calendarButtonKey,
      onTabSelected: widget.onTabSelected,
      onCalendarPressed: widget.onCalendarPressed,
      onDragStretchChanged: (stretch) {
        _stretchNotifier.value = stretch;
      },
    );

    final fallback = Container(
      height: widget.height,
      margin: widget.margin,
      decoration: BoxDecoration(
        color: widget.isDarkMode
            ? colorScheme.surfaceContainerHighest.withValues(alpha: 0.78)
            : colorScheme.surface.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(34),
        border: Border.all(
          color: colorScheme.outlineVariant
              .withValues(alpha: widget.isDarkMode ? 0.42 : 0.54),
          width: 0.8,
        ),
        boxShadow: [
          BoxShadow(
            color: widget.primaryColor
                .withValues(alpha: widget.isDarkMode ? 0.12 : 0.2),
            blurRadius: 26,
            spreadRadius: 1,
            offset: const Offset(0, 4),
          ),
          BoxShadow(
            color: colorScheme.shadow.withValues(alpha: 0.12),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Stack(
        fit: StackFit.expand,
        clipBehavior: Clip.none,
        children: [
          // BackdropFilter 会让整块壁纸进入离屏模糊，在 Android 上很容易造成
          // Raster Jank。Android 保留半透明底色，其他平台继续使用毛玻璃效果。
          if (!AppPlatform.isAndroid)
            ClipRRect(
              borderRadius: BorderRadius.circular(34),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                child: const SizedBox.expand(),
              ),
            ),
          navContent,
        ],
      ),
    );

    final surface = OptionalLiquidGlassSurface(
      height: widget.height,
      margin: widget.margin,
      borderRadius: 34,
      tint: widget.glassTint,
      haloColor: widget.primaryColor,
      isDark: widget.isDarkMode,
      allowChildOverflow: true,
      fallback: fallback,
      child: navContent,
    );

    return ValueListenableBuilder<double>(
      valueListenable: _stretchNotifier,
      builder: (context, stretch, child) {
        final scaleX = 1.0 + stretch * 0.045;
        return Transform(
          alignment: Alignment.bottomCenter,
          transform: Matrix4.diagonal3Values(scaleX, 1.0, 1.0),
          child: child,
        );
      },
      child: surface,
    );
  }
}
