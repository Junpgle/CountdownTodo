part of '../personal_timeline_screen.dart';

extension _PersonalTimelineDataExt on _PersonalTimelineScreenState {
  Future<void> _loadData() async {
    _financeOccurrenceRefreshTimer?.cancel();
    _financeOccurrenceRefreshTimer = null;
    final loadGeneration = ++_loadGeneration;
    _mutateState(() {
      _isLoading = true;
      _mlInsights = [];
    });

    final dateRange = timelineDateRange(_dimension, _selectedDate);
    final start = dateRange.start;
    final end = dateRange.end;
    final day = AppTimeFormats.dayStart(_selectedDate);

    try {
      final screenTimeDateFormat = AppTimeFormats.dateFormatter('yyyy-MM-dd');
      Future<
        ({
          List<FinanceTransaction> transactions,
          List<FinanceCategory> categories,
        })?
      >
      loadFinance() async {
        try {
          final financeData = await Future.wait<dynamic>([
            FinanceRepository.getTransactions(from: start, to: end),
            FinanceRepository.getCategories(includeArchived: true),
          ]);
          return (
            transactions: financeData[0] as List<FinanceTransaction>,
            categories: financeData[1] as List<FinanceCategory>,
          );
        } catch (error) {
          debugPrint('❌ get timeline finance data error: $error');
          return null;
        }
      }

      // 并行加载所有独立的范围统计数据源，避免 10+ 次串行 SQLite/Prefs 等待
      final loaded = await Future.wait<dynamic>([
        TimelineService.instance.getSummaryForRange(
          widget.username,
          start,
          end,
        ),
        _dimension == TimelineDimension.daily
            ? TimelineService.instance.getEventsForDay(widget.username, day)
            : Future<List<TimelineEvent>>.value(const <TimelineEvent>[]),
        loadFinance(),
        PomodoroService.getRecordsInRange(start, end),
        StorageService.getTimeLogs(widget.username, from: start, to: end),
        StorageService.getPlanBlocks(widget.username, from: start, to: end),
        PomodoroService.getAllTagsIncludingDeleted(),
        StorageService.getScreenTimeHistory(
          username: widget.username,
          fromDate: screenTimeDateFormat.format(start),
          toDate: screenTimeDateFormat.format(end),
        ),
        StorageService.getAppMappings(),
        StorageService.getTodosForTimelineRange(
          widget.username,
          from: start,
          to: end,
        ),
        HabitRepository.getHabitOnlyRecurringTodoSeriesIds(),
        CourseService.getCoursesForDateRange(
          widget.username,
          from: start,
          to: end,
        ),
      ]);
      if (!mounted || loadGeneration != _loadGeneration) return;

      final summary = loaded[0] as TimelineSummary;
      _events = loaded[1] as List<TimelineEvent>;
      final financeLoaded =
          loaded[2]
              as ({
                List<FinanceTransaction> transactions,
                List<FinanceCategory> categories,
              })?;
      final records = loaded[3] as List<PomodoroRecord>;
      final timeLogs = loaded[4] as List<TimeLogItem>;
      final planBlocks = loaded[5] as List<TodoPlanBlock>;
      final tags = loaded[6] as List<PomodoroTag>;
      final screenStats = loaded[7] as Map<String, List<dynamic>>;
      final appMappings = loaded[8] as Map<String, String>;
      final todos = loaded[9] as List<TodoItem>;
      final habitOnlyRecurringSeriesIds = loaded[10] as Set<String>;
      final courses = loaded[11] as List<CourseItem>;

      FinanceSummary financeSummary = const FinanceSummary();
      List<FinanceTransaction> financeTransactions = const [];
      List<FinanceTransaction> allFinanceTransactions = const [];
      List<FinanceCategory> financeCategories = const [];
      _FinanceCardMetrics financeCardMetrics = (
        categoryByUuid: const {},
        topCategories: const [],
        maxCategory: 1,
        spendingDays: 0,
        peakDay: null,
        expenseCount: 0,
        incomeCount: 0,
        refundCount: 0,
      );
      DateTime? financeAsOf;
      if (financeLoaded != null) {
        allFinanceTransactions = financeLoaded.transactions;
        financeCategories = financeLoaded.categories;
        financeAsOf = DateTime.now();
        financeTransactions = TimelineService.financeTransactionsThroughNow(
          transactions: allFinanceTransactions,
          periodStart: start,
          now: financeAsOf,
        );
        financeSummary = FinanceSummary.fromTransactions(financeTransactions);
        financeCardMetrics = _createFinanceCardMetrics(
          summary: financeSummary,
          transactions: financeTransactions,
          categories: financeCategories,
        );
      }

      Map<String, int> catUsage = {};
      Map<String, int> appUsage = {};
      final categoryCache = <(String, String, String?), String>{};
      int screenTotal = 0;
      int productiveScreen = 0;
      int distractionScreen = 0;

      // Iterate through days in range
      DateTime cursor = start;
      while (cursor.isBefore(end)) {
        final dateStr = screenTimeDateFormat.format(cursor);
        final stats = screenStats[dateStr] ?? [];
        for (var item in stats) {
          final appName =
              item['app_name']?.toString() ??
              item['package_name']?.toString() ??
              '未知应用';
          final packageName = item['package_name']?.toString() ?? '';
          final backendCategory = item['category']?.toString();
          final duration = (item['duration'] as num?)?.toInt() ?? 0;
          final cat = categoryCache.putIfAbsent(
            (appName, packageName, backendCategory),
            () => _getScreenCategoryForApp(
              appName: appName,
              packageName: packageName,
              backendCategory: backendCategory,
              mappings: appMappings,
            ),
          );
          catUsage[cat] = (catUsage[cat] ?? 0) + duration;
          appUsage[appName] = (appUsage[appName] ?? 0) + duration;
          screenTotal += duration;
          if (_isProductiveScreenCategory(cat)) productiveScreen += duration;
          if (_isDistractionScreenCategory(cat)) distractionScreen += duration;
        }
        cursor = AppTimeFormats.localDayStartOffset(cursor, 1);
      }

      final startMs = start.millisecondsSinceEpoch;
      final endMs = end.millisecondsSinceEpoch;
      var regularCompletedCount = 0;
      var regularPlannedCount = 0;
      var sprintCount = 0;
      var earlyCount = 0;
      for (final todo in todos) {
        if (todo.isDeleted) continue;
        final completedInRange =
            todo.isDone && todo.updatedAt >= startMs && todo.updatedAt < endMs;
        final createdInRange =
            todo.createdAt >= startMs && todo.createdAt < endMs;
        DateTime? dueEnd;
        if (todo.dueDate != null) {
          dueEnd = _effectiveTodoDueEnd(todo);
        }
        final dueInRange =
            todo.dueDate != null &&
            dueEnd != null &&
            !dueEnd.isBefore(start) &&
            dueEnd.isBefore(end);
        final plannedInRange = createdInRange || dueInRange || completedInRange;
        if (!plannedInRange || _isRecurringTodo(todo)) continue;

        regularPlannedCount++;
        if (completedInRange) {
          regularCompletedCount++;
          final completionDue = todo.dueDate == null
              ? _effectiveTodoDueEnd(todo)
              : dueEnd;
          if (completionDue != null) {
            final doneAt = DateTime.fromMillisecondsSinceEpoch(todo.updatedAt);
            final diff = completionDue.difference(doneAt);
            if (!diff.isNegative && diff.inHours <= 24) sprintCount++;
            if (diff.inHours >= 24) earlyCount++;
          }
        }
      }

      final rangeStatistics = TimelineStatisticsService.calculate(
        start: start,
        end: end,
        pomodoroRecords: records,
        timeLogs: timeLogs,
        planBlocks: planBlocks,
        todos: todos,
        tags: tags,
        excludedRecurrenceSeriesIds: habitOnlyRecurringSeriesIds,
      );
      final totalSecs = rangeStatistics.totalFocusSeconds;
      final regularTotalCount = regularPlannedCount == 0
          ? regularCompletedCount
          : regularPlannedCount;
      final medalCompletedCount =
          regularCompletedCount + rangeStatistics.recurringCompletedCount;
      final medalTotalCount =
          regularTotalCount + rangeStatistics.recurringScheduledCount;

      final Map<String, int> coursesByDay = {};
      var courseCount = 0;
      var maxDailyCourseCount = 0;
      final courseDateFormat = AppTimeFormats.dateFormatter('yyyy-MM-dd');
      for (final course in courses) {
        DateTime? courseDay;
        try {
          courseDay = courseDateFormat.parseStrict(course.date);
        } catch (_) {
          courseDay = null;
        }
        if (courseDay == null ||
            courseDay.isBefore(start) ||
            !courseDay.isBefore(end)) {
          continue;
        }
        final dayCount = (coursesByDay[course.date] ?? 0) + 1;
        coursesByDay[course.date] = dayCount;
        courseCount++;
        if (dayCount > maxDailyCourseCount) {
          maxDailyCourseCount = dayCount;
        }
      }

      String? topCat;
      if (catUsage.isNotEmpty) {
        topCat = catUsage.entries
            .reduce((a, b) => a.value > b.value ? a : b)
            .key;
      }

      if (mounted && loadGeneration == _loadGeneration) {
        _mutateState(() {
          _summary = summary;
          _totalFocusMinutes = totalSecs ~/ 60;

          // Smart Top Category: Prioritize task-based subject if app category is generic
          String? displayCat = topCat;
          if (displayCat == null || displayCat == '其他') {
            if (summary.subjectDistribution.entries.isNotEmpty) {
              final topSub = summary.subjectDistribution.entries
                  .reduce((a, b) => a.value > b.value ? a : b)
                  .key;
              if (topSub != '其他') {
                displayCat = topSub;
              }
            }
          }
          _topAppCategory = displayCat ?? '学习';
          _completedCount = regularCompletedCount;
          _totalCount = regularTotalCount;
          _screenTimeSeconds = screenTotal;
          _productiveScreenSeconds = productiveScreen;
          _distractionScreenSeconds = distractionScreen;
          _deadlineSprintCount = sprintCount;
          _earlyCompletionCount = earlyCount;
          _courseCount = courseCount;
          _maxDailyCourseCount = maxDailyCourseCount;
          _topScreenApps = appUsage.entries.toList()
            ..sort((a, b) => b.value.compareTo(a.value));
          _topScreenApps = _topScreenApps.take(5).toList();
          _pomodoroFocusSeconds = rangeStatistics.pomodoroFocusSeconds;
          _timeLogSeconds = rangeStatistics.timeLogSeconds;
          _pomodoroCount = rangeStatistics.pomodoroCount;
          _timeLogCount = rangeStatistics.timeLogCount;
          _pauseSeconds = rangeStatistics.pauseSeconds;
          _pauseCount = rangeStatistics.pauseCount;
          _plannedMinutes = rangeStatistics.plannedMinutes;
          _planActualSeconds = rangeStatistics.planActualSeconds;
          _planBlockCount = rangeStatistics.planBlockCount;
          _planCompletedCount = rangeStatistics.planCompletedCount;
          _planMissedCount = rangeStatistics.planMissedCount;
          _planSkippedCount = rangeStatistics.planSkippedCount;
          _recurringCompletedCount = rangeStatistics.recurringCompletedCount;
          _recurringScheduledCount = rangeStatistics.recurringScheduledCount;
          _recurringMissedCount = rangeStatistics.recurringMissedCount;
          _recurringSkippedCount = rangeStatistics.recurringSkippedCount;
          _recurringPendingCount = rangeStatistics.recurringPendingCount;
          _recurrenceSeries = rangeStatistics.recurrenceSeries;
          _bestRecurrenceSeries = rangeStatistics.bestRecurrenceSeries;
          _recurringLongestStreak = rangeStatistics.recurringLongestStreak;
          _topFocusTags = rangeStatistics.topFocusTags;
          _financeSummary = financeSummary;
          _financeCardMetrics = financeCardMetrics;

          // Calculate ML Medal Recommendations
          _medalRecommendation = MedalRecommendationService.getRecommendations(
            summary,
            totalSecs ~/ 60,
            medalCompletedCount,
            medalTotalCount,
            earlyCount,
            sprintCount,
            courseCount,
            maxDailyCourseCount,
            screenTotal,
            productiveScreen,
            distractionScreen,
          );

          // Get earned medals in this session (this time period)
          _earnedThisSession = _medalRecommendation?.earnedMedals ?? [];

          _isLoading = false;
        });

        if (financeAsOf != null) {
          _scheduleFinanceOccurrenceRefresh(
            transactions: allFinanceTransactions,
            periodStart: start,
            now: financeAsOf,
          );
        }

        // Async ML insights generation
        TimelineMLService.instance
            .generateInsights(
              username: widget.username,
              summary: summary,
              totalFocusMinutes: totalSecs ~/ 60,
              completedCount: regularCompletedCount,
              totalCount: regularPlannedCount == 0
                  ? regularCompletedCount
                  : regularPlannedCount,
              screenTimeSeconds: screenTotal,
              productiveScreenSeconds: productiveScreen,
              distractionScreenSeconds: distractionScreen,
              earlyCompletionCount: earlyCount,
              deadlineSprintCount: sprintCount,
              startDate: start,
              endDate: end,
            )
            .then((insights) {
              if (mounted &&
                  loadGeneration == _loadGeneration &&
                  insights.isNotEmpty) {
                _mutateState(() {
                  _mlInsights = insights;
                });
              }
            });

        // Async ML enhancement for range-specific recommendations
        final allMedals = _medalRecommendation?.allMedals;
        if (allMedals != null) {
          MedalRecommendationService.recommendNextML(
            allMedals,
            summary,
            totalSecs ~/ 60,
            regularCompletedCount,
            regularPlannedCount == 0
                ? regularCompletedCount
                : regularPlannedCount,
            earlyCount,
            sprintCount,
            screenTotal,
            productiveScreen,
            distractionScreen,
          ).then((mlResult) {
            if (mounted &&
                loadGeneration == _loadGeneration &&
                mlResult.topRecommendations.isNotEmpty) {
              _mutateState(() {
                _medalRecommendation = mlResult;
              });
            }
          });
        }

        // Trigger All-time medal calculation if not yet loaded
        if (_allTimeRecommendation == null) {
          _loadAllTimeMedalData();
        }
      }
    } catch (e) {
      // debugPrint('Error loading insight data: $e');
      if (mounted && loadGeneration == _loadGeneration) {
        _mutateState(() => _isLoading = false);
      }
    }
  }

  void _scheduleFinanceOccurrenceRefresh({
    required Iterable<FinanceTransaction> transactions,
    required DateTime periodStart,
    required DateTime now,
  }) {
    _financeOccurrenceRefreshTimer?.cancel();
    _financeOccurrenceRefreshTimer = null;
    if (periodStart.isAfter(now)) return;

    final nowAt = now.millisecondsSinceEpoch;
    int? nextEventAt;
    for (final transaction in transactions) {
      final eventAt = transaction.balanceEventAt();
      if (eventAt > nowAt && (nextEventAt == null || eventAt < nextEventAt)) {
        nextEventAt = eventAt;
      }
    }
    if (nextEventAt == null) return;

    final delayMs = (nextEventAt - nowAt + 1)
        .clamp(1, const Duration(days: 24).inMilliseconds)
        .toInt();
    _financeOccurrenceRefreshTimer = Timer(Duration(milliseconds: delayMs), () {
      _financeOccurrenceRefreshTimer = null;
      if (mounted) unawaited(_loadData());
    });
  }

  Future<void> _openFinanceEntry() async {
    final saved = await Navigator.of(context).push<FinanceTransaction>(
      PageTransitions.material(builder: (_) => const FinanceEntryScreen()),
    );
    if (saved != null && mounted) await _loadData();
  }

  Future<void> _openFinanceEvent(String transactionUuid) async {
    final transaction = await FinanceRepository.getTransaction(transactionUuid);
    if (transaction == null || !mounted) return;
    final saved = await Navigator.of(context).push<FinanceTransaction>(
      PageTransitions.material(
        builder: (_) => FinanceEntryScreen(transaction: transaction),
      ),
    );
    if (saved != null && mounted) await _loadData();
  }

  Future<void> _openFinanceLedger() async {
    await Navigator.of(context).push(
      PageTransitions.material(
        builder: (_) => FinanceHomeScreen(username: widget.username),
      ),
    );
    if (mounted) await _loadData();
  }

  Future<void> _loadAllTimeMedalData() async {
    if (_isLoadingAllTimeMedals) return;
    _isLoadingAllTimeMedals = true;
    try {
      final start = DateTime(2020);
      final end = AppTimeFormats.localDayStartOffset(DateTime.now(), 1);

      final allTimeScreenTimeDateFormat = AppTimeFormats.dateFormatter(
        'yyyy-MM-dd',
      );
      final loaded = await Future.wait<dynamic>([
        TimelineService.instance.getSummaryForRange(
          widget.username,
          start,
          end,
        ),
        StorageService.getScreenTimeHistory(
          username: widget.username,
          fromDate: allTimeScreenTimeDateFormat.format(start),
          toDate: allTimeScreenTimeDateFormat.format(end),
        ),
        StorageService.getAppMappings(),
        StorageService.getTodos(widget.username),
        CourseService.getAllCourses(widget.username),
      ]);
      if (!mounted) return;

      final summary = loaded[0] as TimelineSummary;
      final totalSecs = summary.totalFocusMinutes * 60;
      final screenStats = loaded[1] as Map<String, List<dynamic>>;
      final appMappings = loaded[2] as Map<String, String>;
      final todos = loaded[3] as List<TodoItem>;
      final courses = loaded[4] as List<CourseItem>;

      final categoryCache = <(String, String, String?), String>{};
      int screenTotal = 0;
      int productiveScreen = 0;
      int distractionScreen = 0;

      for (var stats in screenStats.values) {
        for (var item in stats) {
          final appName = item['app_name']?.toString() ?? '未知应用';
          final packageName = item['package_name']?.toString() ?? '';
          final duration = (item['duration'] as num?)?.toInt() ?? 0;
          final backendCategory = item['category']?.toString();
          final cat = categoryCache.putIfAbsent(
            (appName, packageName, backendCategory),
            () => _getScreenCategoryForApp(
              appName: appName,
              packageName: packageName,
              backendCategory: backendCategory,
              mappings: appMappings,
            ),
          );
          screenTotal += duration;
          if (_isProductiveScreenCategory(cat)) productiveScreen += duration;
          if (_isDistractionScreenCategory(cat)) distractionScreen += duration;
        }
      }

      var completedTodoCount = 0;
      var plannedTodoCount = 0;
      var sprintCount = 0;
      var earlyCount = 0;
      for (final todo in todos) {
        if (todo.isDeleted) continue;
        plannedTodoCount++;
        if (!todo.isDone) continue;
        completedTodoCount++;

        final due = _effectiveTodoDueEnd(todo);
        if (due == null) continue;
        final doneAt = DateTime.fromMillisecondsSinceEpoch(todo.updatedAt);
        final diff = due.difference(doneAt);
        if (!diff.isNegative && diff.inHours <= 24) sprintCount++;
        if (diff.inHours >= 24) earlyCount++;
      }

      final Map<String, int> coursesByDay = {};
      var maxDailyCourseCount = 0;
      for (final course in courses) {
        final dayCount = (coursesByDay[course.date] ?? 0) + 1;
        coursesByDay[course.date] = dayCount;
        if (dayCount > maxDailyCourseCount) {
          maxDailyCourseCount = dayCount;
        }
      }

      final recommendation = MedalRecommendationService.getRecommendations(
        summary,
        totalSecs ~/ 60,
        completedTodoCount,
        plannedTodoCount,
        earlyCount,
        sprintCount,
        courses.length,
        maxDailyCourseCount,
        screenTotal,
        productiveScreen,
        distractionScreen,
      );

      if (mounted) {
        _mutateState(() {
          _allTimeSummary = summary;
          _allTimeRecommendation = recommendation;
        });
      }

      // Async ML enhancement for all-time recommendations
      MedalRecommendationService.recommendNextML(
        recommendation.allMedals,
        summary,
        totalSecs ~/ 60,
        completedTodoCount,
        plannedTodoCount,
        earlyCount,
        sprintCount,
        screenTotal,
        productiveScreen,
        distractionScreen,
      ).then((mlResult) {
        if (mounted && mlResult.topRecommendations.isNotEmpty) {
          _mutateState(() {
            _allTimeRecommendation = mlResult;
          });
        }
      });
    } catch (e) {
      // debugPrint('Error loading all-time medal data: $e');
    } finally {
      _isLoadingAllTimeMedals = false;
    }
  }

  void _navigateToMedalWall() {
    // 勋章墙必须展示全纪录统计，不能受当前时段切换影响
    if (_allTimeRecommendation == null || _allTimeSummary == null) {
      AppSnackBars.showSnackBar(
        context,
        const SnackBar(content: Text('正在汇总全纪录数据，请稍候...')),
      );
      return;
    }

    Navigator.push(
      context,
      PageTransitions.material(
        builder: (context) => MedalWallPage(
          recommendation: _allTimeRecommendation!,
          earnedThisSession: _earnedThisSession,
          summary: _allTimeSummary!,
        ),
      ),
    );
  }

  String _getScreenCategoryForApp({
    required String appName,
    required String packageName,
    required String? backendCategory,
    required Map<String, String> mappings,
  }) {
    final mappedByName = mappings[appName];
    if (mappedByName != null && mappedByName != '未分类') {
      return mappedByName;
    }

    final mappedByPackage = mappings[packageName];
    if (mappedByPackage != null && mappedByPackage != '未分类') {
      return mappedByPackage;
    }

    if (backendCategory != null &&
        backendCategory.isNotEmpty &&
        backendCategory != '未分类') {
      return backendCategory;
    }

    return _guessScreenCategory(appName);
  }

  String _guessScreenCategory(String appName) {
    final l = appName.toLowerCase();
    if (l.contains('微信') ||
        l.contains('qq') ||
        l.contains('小红书') ||
        l.contains('微博')) {
      return '社交通讯';
    }
    if (l.contains('抖音') ||
        l.contains('哔哩') ||
        l.contains('bilibili') ||
        l.contains('音乐') ||
        l.contains('视频') ||
        l.contains('直播') ||
        l.contains('游戏')) {
      return '影音娱乐';
    }
    if (l.contains('studio') ||
        l.contains('code') ||
        l.contains('visual studio') ||
        l.contains('vscode') ||
        l.contains('vs code') ||
        l.contains('intellij') ||
        l.contains('idea') ||
        l.contains('pycharm') ||
        l.contains('webstorm') ||
        l.contains('clion') ||
        l.contains('cursor') ||
        l.contains('trae') ||
        l.contains('sublime') ||
        l.contains('notepad++') ||
        l.contains('terminal') ||
        l.contains('powershell') ||
        l.contains('cmd') ||
        l.contains('git') ||
        l.contains('github') ||
        l.contains('docker') ||
        l.contains('postman') ||
        l.contains('dev') ||
        l.contains('flutter') ||
        l.contains('dart') ||
        l.contains('python') ||
        l.contains('java') ||
        l.contains('node') ||
        l.contains('npm') ||
        l.contains('编程') ||
        l.contains('代码') ||
        l.contains('开发') ||
        l.contains('调试') ||
        l.contains('word') ||
        l.contains('excel') ||
        l.contains('笔记') ||
        l.contains('论文') ||
        l.contains('学习')) {
      return '学习办公';
    }
    if (l.contains('edge') ||
        l.contains('chrome') ||
        l.contains('浏览') ||
        l.contains('计算器') ||
        l.contains('设置')) {
      return '实用工具';
    }
    return '其他';
  }

  bool _isProductiveScreenCategory(String category) {
    return category == '学习办公' || category == '实用工具';
  }

  bool _isDistractionScreenCategory(String category) {
    return category == '社交通讯' || category == '影音娱乐' || category == '游戏与辅助';
  }

  bool _isRecurringTodo(TodoItem todo) {
    final seriesId = todo.recurrenceSeriesId?.trim();
    return seriesId != null && seriesId.isNotEmpty;
  }

  DateTime? _effectiveTodoDueEnd(TodoItem todo) {
    final due = todo.dueDate;
    if (due == null) return null;

    final localDue = due.toLocal();
    final looksDateOnly =
        localDue.hour == 0 &&
        localDue.minute == 0 &&
        localDue.second == 0 &&
        localDue.millisecond == 0;
    if (!todo.isAllDayTask && !looksDateOnly) return localDue;

    return DateTime(
      localDue.year,
      localDue.month,
      localDue.day,
      23,
      59,
      59,
      999,
    );
  }
}
