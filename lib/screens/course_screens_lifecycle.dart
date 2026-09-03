part of 'course_screens.dart';
// ignore_for_file: annotate_overrides, unused_element, unused_element_parameter

mixin _WeeklyCourseLifecycle on _WeeklyCourseScreenStateBase {
  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _pulseAnimation = Tween<double>(begin: 0.3, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _courseExpandCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _courseExpandAnim = CurvedAnimation(
      parent: _courseExpandCtrl,
      curve: Curves.easeOutCubic,
    );
    PowerSaveModeService.enabledListenable.addListener(_syncPowerSavePulse);
    _syncPowerSavePulse();
    _pageController = PageController(initialPage: 0);
    DeviceCalendarReadService.revision.addListener(_reloadDeviceCalendar);
    _loadData();
  }

  @override
  void dispose() {
    PowerSaveModeService.enabledListenable.removeListener(_syncPowerSavePulse);
    _pulseController.dispose();
    _courseExpandCtrl.dispose();
    _pageController.dispose();
    DeviceCalendarReadService.revision.removeListener(_reloadDeviceCalendar);
    super.dispose();
  }

  void _reloadDeviceCalendar() {
    _loadDeviceCalendarEventsForCurrentView().then((_) {
      if (!mounted) return;
      _checkCollapsedSlots();
      setState(() {});
    });
  }

  void _syncPowerSavePulse() {
    if (_viewMode == 0 && AndroidEnergyPolicy.shouldRunDecorativeMotion) {
      if (!_pulseController.isAnimating) {
        _pulseController.repeat(
          reverse: true,
          count: AndroidEnergyPolicy.decorativeRepeatCount(androidCount: 5),
        );
      }
    } else {
      _pulseController
        ..stop()
        ..reset();
    }
  }

  Future<void> _loadData() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    // 🚀 核心优化：并行加载所有基础数据，消除重复调用
    final results = await Future.wait([
      CourseService.getAllCourses(widget.username),
      StorageService.getTodos(widget.username),
      StorageService.getTimeLogs(widget.username),
      PomodoroService.getRecords(),
      PomodoroService.getTags(),
      StorageService.getPlanBlocks(widget.username),
      StorageService.getSemesterStart(),
      StorageService.getSemesters(), // 加载学期列表
    ]);

    // 🚀 核心优化：等待 300ms 让进入页面的过渡动画彻底完成
    // 避免在动画期间进行大量 CPU 计算导致界面掉帧
    await Future.delayed(const Duration(milliseconds: 300));

    if (!mounted) return;

    _allCourses = results[0] as List<CourseItem>;
    final List<TodoItem> allTodosRaw = results[1] as List<TodoItem>;
    final List<TimeLogItem> allLogsRaw = results[2] as List<TimeLogItem>;
    _allPomodoroRecords = results[3] as List<PomodoroRecord>;
    _pomodoroTags = results[4] as List<PomodoroTag>;
    DateTime? semStart = results[6] as DateTime?;
    _semesters = results[7] as List<SemesterInfo>;

    // 如果没有学期数据，从旧的 semesterStart 创建默认学期
    if (_semesters.isEmpty && semStart != null) {
      _semesters = [
        SemesterInfo(
          id: 'default',
          name: '当前学期',
          startDate: semStart,
          isCurrent: true,
        )
      ];
    }

    // 按开学日期排序学期
    _semesters.sort((a, b) => a.startDate.compareTo(b.startDate));

    // 不过滤课程，保留所有学期的课程
    // 课程会根据周次自动判断属于哪个学期

    // 1. 处理课程相关数据 - 收集所有学期的所有周次
    if (_allCourses.isNotEmpty) {
      _availableWeeks = _allCourses.map((c) => c.weekIndex).toSet().toList();
      _availableWeeks.sort();
    } else {
      _availableWeeks = List.generate(20, (index) => index + 1);
    }

    // 2. 处理待办
    _allTodos = allTodosRaw.where((t) => !t.isDeleted).toList();

    // 3. 处理日志
    _allTimeLogs = allLogsRaw.where((l) => !l.isDeleted).toList();

    // 4. 计算学期起始周 - 使用第一个学期的开学日期作为初始参考
    _allPlanBlocks =
        (results[5] as List<TodoPlanBlock>).where((p) => !p.isDeleted).toList();

    if (_semesters.isNotEmpty) {
      // 使用第一个学期的开学日期
      semStart = _semesters.first.startDate;
      _semesterMonday = semStart.subtract(Duration(days: semStart.weekday - 1));
    } else if (semStart != null) {
      _semesterMonday = semStart.subtract(Duration(days: semStart.weekday - 1));
    } else if (_allCourses.isNotEmpty) {
      final sortedCourses = List<CourseItem>.from(_allCourses)
        ..sort((a, b) => a.weekIndex.compareTo(b.weekIndex));
      final firstCourse = sortedCourses.first;
      if (firstCourse.date.isNotEmpty) {
        DateTime firstCourseDate =
            DateFormat('yyyy-MM-dd').parse(firstCourse.date);
        _semesterMonday = firstCourseDate
            .subtract(Duration(days: firstCourse.weekday - 1))
            .subtract(Duration(
                days: (firstCourse.weekIndex > 0 ? firstCourse.weekIndex : 0) *
                    7));
      }
    }

    if (_semesterMonday == null) {
      DateTime now = DateTime.now();
      _semesterMonday = now.subtract(Duration(days: now.weekday - 1));
    }

    // 5. 计算当前周 - 基于第一个学期
    DateTime now = DateTime.now();
    int daysOffset = now.difference(_semesterMonday!).inDays;
    _currentWeek = (daysOffset ~/ 7) + 1;

    // 6. 获取当前周课程 - 根据当前周次找到对应的学期，然后过滤课程
    _updateWeekCourses();

    // 7. 月视图数据按需构建，避免首次进入课程页就做全量逐日展开
    _monthDataPrepared = false;
    if (_viewMode == 2) {
      _groupDataForMonthView();
    }
    _updateWeekTodos();
    _updateWeekTimeLogsPomodorosAndPlans();
    await _loadDeviceCalendarEventsForCurrentView();
    _checkCollapsedSlots();

    if (mounted) {
      setState(() => _isLoading = false);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _courseExpandCtrl.forward();
          _syncPowerSavePulse();
        }
        _checkCoachMarks();
      });
    }
  }

  /// 根据当前周次找到对应的学期，然后过滤课程
  void _updateWeekCourses() {
    // 根据当前周次计算对应的日期
    if (_semesterMonday == null) return;

    // 计算当前周次对应的周一日期
    final currentWeekMonday =
        _semesterMonday!.add(Duration(days: (_currentWeek - 1) * 7));

    // 找到这个日期属于哪个学期，并计算在该学期中的相对周次
    String? targetSemesterId;
    int relativeWeek = _currentWeek;

    for (final semester in _semesters) {
      final semesterStart = DateTime(semester.startDate.year,
          semester.startDate.month, semester.startDate.day);
      final semesterEnd = semester.endDate != null
          ? DateTime(semester.endDate!.year, semester.endDate!.month,
              semester.endDate!.day)
          : semesterStart.add(const Duration(days: 120)); // 默认4个月

      // 检查当前周的周一是否在这个学期的范围内
      if (!currentWeekMonday.isBefore(semesterStart) &&
          !currentWeekMonday.isAfter(semesterEnd)) {
        targetSemesterId = semester.id;
        // 计算在该学期中的相对周次
        final semesterMonday =
            semesterStart.subtract(Duration(days: semesterStart.weekday - 1));
        relativeWeek =
            (currentWeekMonday.difference(semesterMonday).inDays ~/ 7) + 1;
        break;
      }
    }

    // 如果没有找到对应的学期，使用第一个学期
    targetSemesterId ??=
        _semesters.isNotEmpty ? _semesters.first.id : 'default';

    // 过滤课程：只显示当前学期当前相对周次的课程
    _weekCourses = _allCourses
        .where((c) =>
            c.semesterId == targetSemesterId && c.weekIndex == relativeWeek)
        .toList();
  }

  Future<void> _loadDeviceCalendarEventsForCurrentWeek() async {
    final requestedMode = _viewMode;
    final requestedWeek = _currentWeek;
    final requestedMonth = _selectedMonth;
    final range = _getDeviceCalendarReadRange();

    bool stillShowingRequestedPeriod() {
      return mounted &&
          _viewMode == requestedMode &&
          _currentWeek == requestedWeek &&
          _selectedMonth.year == requestedMonth.year &&
          _selectedMonth.month == requestedMonth.month;
    }

    if (!DeviceCalendarReadService.isSupported ||
        !await DeviceCalendarReadService.isEnabled()) {
      if (!stillShowingRequestedPeriod()) return;
      _deviceCalendarEvents = [];
      _updateWeekDeviceCalendarEvents();
      _updateMonthDeviceCalendarEvents();
      return;
    }

    try {
      final events = await DeviceCalendarReadService.readEvents(
        start: range.start,
        end: range.end,
      );
      if (!stillShowingRequestedPeriod()) return;
      _deviceCalendarEvents = events;
    } catch (_) {
      // A provider can disappear or reject access while the page is open.
      // Keep the app's own calendar usable and simply hide external entries.
      if (!stillShowingRequestedPeriod()) return;
      _deviceCalendarEvents = [];
    }
    _updateWeekDeviceCalendarEvents();
    _updateMonthDeviceCalendarEvents();
  }

  Future<void> _loadDeviceCalendarEventsForCurrentView() async {
    await _loadDeviceCalendarEventsForCurrentWeek();
  }

  ({DateTime start, DateTime end}) _getDeviceCalendarReadRange() {
    if (_viewMode == 2) {
      return (
        start: DeviceCalendarReadService.monthGridStart(_selectedMonth),
        end: DeviceCalendarReadService.monthGridEnd(_selectedMonth),
      );
    }

    final monday = _getMondayOfCurrentWeek();
    if (monday == null) {
      final today = DateTime.now();
      return (
        start: DateTime(today.year, today.month, today.day),
        end: DateTime(today.year, today.month, today.day + 14),
      );
    }

    final weekStart = DateTime(monday.year, monday.month, monday.day);
    if (_viewMode == 1) {
      return (
        start: weekStart,
        end: weekStart.add(const Duration(days: 14)),
      );
    }

    // The initial homepage query and the week view use the same month-grid
    // window. This lets all three views share one in-memory provider read.
    final now = DateTime.now();
    final currentWeekStart = DateTime(now.year, now.month, now.day)
        .subtract(Duration(days: now.weekday - 1));
    final anchor = DateUtils.isSameDay(weekStart, currentWeekStart)
        ? _selectedMonth
        : weekStart.add(const Duration(days: 3));
    return (
      start: DeviceCalendarReadService.monthGridStart(anchor),
      end: DeviceCalendarReadService.monthGridEnd(anchor),
    );
  }

  void _updateWeekDeviceCalendarEvents() {
    _allDayDeviceCalendarEventsPerDay = {
      1: [],
      2: [],
      3: [],
      4: [],
      5: [],
      6: [],
      7: [],
    };
    _timedDeviceCalendarEventsPerDay = {
      1: [],
      2: [],
      3: [],
      4: [],
      5: [],
      6: [],
      7: [],
    };
    final monday = _semesterMonday;
    if (monday == null) return;
    final weekStart = DateTime(
      monday.year,
      monday.month,
      monday.day + (_currentWeek - 1) * 7,
    );
    for (var dayIndex = 1; dayIndex <= 7; dayIndex++) {
      final dayStart = weekStart.add(Duration(days: dayIndex - 1));
      final dayEnd = dayStart.add(const Duration(days: 1));
      for (final event in _deviceCalendarEvents) {
        if (!event.overlaps(dayStart, dayEnd)) continue;
        if (event.allDay) {
          _allDayDeviceCalendarEventsPerDay[dayIndex]!.add(event);
        } else {
          _timedDeviceCalendarEventsPerDay[dayIndex]!.add(event);
        }
      }
    }
    for (var dayIndex = 1; dayIndex <= 7; dayIndex++) {
      _allDayDeviceCalendarEventsPerDay[dayIndex]!
          .sort((a, b) => a.title.compareTo(b.title));
      _timedDeviceCalendarEventsPerDay[dayIndex]!
          .sort((a, b) => a.start.compareTo(b.start));
    }
  }

  void _updateMonthDeviceCalendarEvents() {
    final grouped = <String, List<DeviceCalendarEvent>>{};
    final df = DateFormat('yyyy-MM-dd');

    for (final event in _deviceCalendarEvents) {
      final firstDay =
          DateTime(event.start.year, event.start.month, event.start.day);
      final lastDay = DateTime(event.end.year, event.end.month, event.end.day);
      final spanDays = lastDay.difference(firstDay).inDays;
      if (spanDays < 0 || spanDays > _maxExpandedSpanDays) continue;

      for (var offset = 0; offset <= spanDays; offset++) {
        final day = firstDay.add(Duration(days: offset));
        if (!event.overlaps(day, day.add(const Duration(days: 1)))) continue;
        grouped.putIfAbsent(df.format(day), () => []).add(event);
      }
    }

    for (final events in grouped.values) {
      events.sort((a, b) {
        final startOrder = a.start.compareTo(b.start);
        return startOrder != 0 ? startOrder : a.title.compareTo(b.title);
      });
    }
    _monthDeviceCalendarMap = grouped;
  }

  void _checkCoachMarks() async {
    if (!mounted || _showCoachMarks) return;

    final hasShown =
        await FeatureTipService.hasTipBeenShown('course_screen_guide');
    if (hasShown || !mounted) return;

    setState(() {
      _showCoachMarks = true;
    });

    CoachMarkOverlay.show(
      context: context,
      steps: [
        CoachMarkStep(
          targetKey: _viewModeKey,
          title: '视图切换',
          description: '在这里切换单周、双周和月视图。单双周视图支持自适应折叠空闲时间，月视图方便概览整月安排。',
        ),
        CoachMarkStep(
          targetKey: _filterKey,
          title: '数据筛选',
          description: '可以在这里勾选要在时间轴上显示的数据，比如待办、时间日志、番茄钟、今日规划等。',
        ),
        CoachMarkStep(
          targetKey: _timeLogKey,
          title: '记录日志',
          description: '点击这里可以快速进入时间日志页面，手动记录你花费的时间。',
        ),
        CoachMarkStep(
          targetKey: _allDayKey,
          title: '全天待办',
          description: '全天的待办会在顶部展示。',
        ),
        if (MediaQuery.of(context).size.width > 900)
          CoachMarkStep(
            targetKey: _dayHeaderKey,
            title: '单日所有任务',
            description: '宽屏设备下，点击表头上的某一天，还可以在侧边快速查看当天的所有任务！',
          ),
        CoachMarkStep(
          targetKey: _gridKey,
          title: '查看详情',
          description: '在日历网格中，点击任意一块课程、待办或日志，都能查看详细信息并进行编辑操作哦！',
        ),
      ],
      onFinish: () {
        if (mounted) {
          setState(() {
            _showCoachMarks = false;
          });
        }
        FeatureTipService.markTipShown('course_screen_guide');
      },
      onSkip: () {
        if (mounted) {
          setState(() {
            _showCoachMarks = false;
          });
        }
        FeatureTipService.markTipShown('course_screen_guide');
      },
    );
  }

  void _groupDataForMonthView() {
    _monthDataPrepared = true;
    _monthCourseMap = {};
    _monthTodoMap = {};
    _monthCrossDayTodoMap = {};
    _monthLogMap = {};
    _monthPomMap = {};
    _monthPlanMap = {};
    _monthDeviceCalendarMap = {};

    final df = DateFormat('yyyy-MM-dd');

    // 1. 课程分组
    for (var c in _allCourses) {
      if (c.date.isNotEmpty) {
        _monthCourseMap.putIfAbsent(c.date, () => []).add(c);
      } else if (_semesterMonday != null && c.weekIndex > 0) {
        final date = _semesterMonday!
            .add(Duration(days: (c.weekIndex - 1) * 7 + (c.weekday - 1)));
        _monthCourseMap.putIfAbsent(df.format(date), () => []).add(c);
      }
    }

    // 2. 待办分组 (优化：减少 DateFormat 调用)
    final recurrenceIndex = TodoRecurrenceCalendarIndex(_allTodos);
    for (var t in _allTodos) {
      if (!recurrenceIndex.shouldDisplayPersisted(t)) continue;
      DateTime tStart =
          DateTime.fromMillisecondsSinceEpoch(t.createdDate ?? t.createdAt)
              .toLocal();
      DateTime tEnd = t.dueDate ?? tStart.add(const Duration(hours: 1));

      bool isAllDay = t.dueDate != null &&
          tStart.hour == 0 &&
          tStart.minute == 0 &&
          t.dueDate!.hour == 23 &&
          t.dueDate!.minute == 59;
      bool isAcross = !(tStart.year == tEnd.year &&
          tStart.month == tEnd.month &&
          tStart.day == tEnd.day);

      _forEachExpandedDay(
        start: tStart,
        end: tEnd,
        debugLabel: 'todo:${t.id}',
        onDay: (cursor) {
          final dStr = df.format(cursor);
          if (isAllDay || isAcross) {
            _monthCrossDayTodoMap.putIfAbsent(dStr, () => []).add(t);
          } else {
            _monthTodoMap.putIfAbsent(dStr, () => []).add(t);
          }
        },
      );
    }

    // 3. 日志与番茄钟
    for (var l in _allTimeLogs) {
      DateTime lStart =
          DateTime.fromMillisecondsSinceEpoch(l.startTime).toLocal();
      DateTime lEnd = DateTime.fromMillisecondsSinceEpoch(l.endTime).toLocal();
      _forEachExpandedDay(
        start: lStart,
        end: lEnd,
        debugLabel: 'timeLog:${l.id}',
        onDay: (cursor) {
          _monthLogMap.putIfAbsent(df.format(cursor), () => []).add(l);
        },
      );
    }

    for (var p in _allPomodoroRecords) {
      if (p.startTime <= 0) continue;
      DateTime pStart =
          DateTime.fromMillisecondsSinceEpoch(p.startTime).toLocal();
      int pEndMs = p.endTime ?? (p.startTime + p.effectiveDuration * 1000);
      DateTime pEnd = DateTime.fromMillisecondsSinceEpoch(pEndMs).toLocal();
      _forEachExpandedDay(
        start: pStart,
        end: pEnd,
        debugLabel: 'pomodoro:${p.uuid}',
        onDay: (cursor) {
          _monthPomMap.putIfAbsent(df.format(cursor), () => []).add(p);
        },
      );
    }

    for (var plan in _allPlanBlocks) {
      if (plan.startTime <= 0 || plan.endTime <= plan.startTime) continue;
      final start =
          DateTime.fromMillisecondsSinceEpoch(plan.startTime).toLocal();
      final end = DateTime.fromMillisecondsSinceEpoch(plan.endTime).toLocal();
      _forEachExpandedDay(
        start: start,
        end: end,
        debugLabel: 'plan:${plan.uuid}',
        onDay: (cursor) {
          _monthPlanMap.putIfAbsent(df.format(cursor), () => []).add(plan);
        },
      );
    }

    _updateMonthDeviceCalendarEvents();
  }

  void _forEachExpandedDay({
    required DateTime start,
    required DateTime end,
    required String debugLabel,
    required void Function(DateTime day) onDay,
  }) {
    final dayStart = DateTime(start.year, start.month, start.day);
    final dayEnd = DateTime(end.year, end.month, end.day);
    final spanDays = dayEnd.difference(dayStart).inDays;

    if (spanDays < 0) {
      // debugPrint(
      //     '[CourseScreen] Skip invalid span for $debugLabel: start=$start end=$end');
      return;
    }
    if (spanDays > _maxExpandedSpanDays) {
      // debugPrint(
      //     '[CourseScreen] Skip oversized span for $debugLabel: ${spanDays + 1} days');
      return;
    }

    var cursor = dayStart;
    while (!cursor.isAfter(dayEnd)) {
      onDay(cursor);
      cursor = cursor.add(const Duration(days: 1));
    }
  }

  TodoItem _createRecurringOccurrence(TodoItem todo, DateTime targetDay) {
    DateTime origStart = DateTime.fromMillisecondsSinceEpoch(
            todo.createdDate ?? todo.createdAt,
            isUtc: true)
        .toLocal();
    DateTime origEnd = todo.dueDate ?? origStart.add(const Duration(hours: 1));

    DateTime newStart = DateTime(targetDay.year, targetDay.month, targetDay.day,
        origStart.hour, origStart.minute, origStart.second);
    int startDiffMs = newStart.difference(origStart).inMilliseconds;
    DateTime newEnd = origEnd.add(Duration(milliseconds: startDiffMs));

    return TodoItem(
      id: todo.id,
      title: todo.title,
      isDone: todo.isDone,
      isDeleted: todo.isDeleted,
      version: todo.version,
      createdAt: todo.createdAt,
      createdDate: newStart.toUtc().millisecondsSinceEpoch,
      recurrence: todo.recurrence,
      recurrenceSeriesId: todo.recurrenceSeriesId,
      customIntervalDays: todo.customIntervalDays,
      recurrenceEndDate: todo.recurrenceEndDate,
      dueDate: newEnd,
      remark: todo.remark,
      imagePath: todo.imagePath,
      originalText: todo.originalText,
      groupId: todo.groupId,
      reminderMinutes: todo.reminderMinutes,
      teamUuid: todo.teamUuid,
      creatorId: todo.creatorId,
      creatorName: todo.creatorName,
      teamName: todo.teamName,
      collabType: todo.collabType,
      isAllDay: todo.isAllDay,
      categoryId: todo.categoryId,
    );
  }

  List<TodoItem> _expandRecurringTodo(TodoItem todo, DateTime weekStart) {
    if (todo.recurrence == RecurrenceType.none) return [todo];

    // Use the ORIGINAL createdDate as anchor — do NOT use dueDate here,
    // because _handleRecurrenceLogic rolls dueDate forward daily for
    // daily/customDays recurrence, which would shift the anchor.
    final int startMs = todo.createdDate ?? todo.createdAt;
    final DateTime startDate =
        DateTime.fromMillisecondsSinceEpoch(startMs, isUtc: true).toLocal();
    final DateTime anchorDay =
        DateTime(startDate.year, startDate.month, startDate.day);

    // End boundary: for daily/customDays recurrence, _handleRecurrenceLogic
    // rolls dueDate forward to today, so dueDate cannot serve as end boundary.
    // Only use recurrenceEndDate for these types.
    // For other recurrence types (not rolled), dueDate is a valid end boundary.
    DateTime? endBoundary;
    if (todo.recurrence == RecurrenceType.daily ||
        todo.recurrence == RecurrenceType.customDays) {
      if (todo.recurrenceEndDate != null) {
        endBoundary = DateTime(todo.recurrenceEndDate!.year,
            todo.recurrenceEndDate!.month, todo.recurrenceEndDate!.day);
      }
    } else {
      if (todo.dueDate != null) {
        endBoundary = DateTime(
            todo.dueDate!.year, todo.dueDate!.month, todo.dueDate!.day);
      } else if (todo.recurrenceEndDate != null) {
        endBoundary = DateTime(todo.recurrenceEndDate!.year,
            todo.recurrenceEndDate!.month, todo.recurrenceEndDate!.day);
      }
    }

    List<TodoItem> occurrences = [];

    for (int i = 0; i < 7; i++) {
      DateTime targetDay = weekStart.add(Duration(days: i));

      // Skip days before the todo was created
      if (targetDay.isBefore(anchorDay)) continue;
      // Skip days after the end boundary
      if (endBoundary != null && targetDay.isAfter(endBoundary)) continue;

      bool matches = false;

      switch (todo.recurrence) {
        case RecurrenceType.daily:
          matches = true;
          break;
        case RecurrenceType.weekdays:
          matches = targetDay.weekday >= 1 && targetDay.weekday <= 5;
          break;
        case RecurrenceType.weekly:
          matches = targetDay.weekday == anchorDay.weekday;
          break;
        case RecurrenceType.monthly:
          matches = targetDay.day == anchorDay.day;
          break;
        case RecurrenceType.yearly:
          matches = targetDay.month == anchorDay.month &&
              targetDay.day == anchorDay.day;
          break;
        case RecurrenceType.customDays:
          if (todo.customIntervalDays != null && todo.customIntervalDays! > 0) {
            int diff = targetDay.difference(anchorDay).inDays;
            matches = diff >= 0 && diff % todo.customIntervalDays! == 0;
          }
          break;
        case RecurrenceType.none:
          break;
      }

      if (matches) {
        occurrences.add(_createRecurringOccurrence(todo, targetDay));
      }
    }

    return occurrences;
  }

  void _updateWeekTodos() {
    _allDayTodosPerDay = {1: [], 2: [], 3: [], 4: [], 5: [], 6: [], 7: []};
    _intraDayTodosPerDay = {1: [], 2: [], 3: [], 4: [], 5: [], 6: [], 7: []};

    if (_semesterMonday == null) return;

    DateTime currentWeekMonday =
        _semesterMonday!.add(Duration(days: (_currentWeek - 1) * 7));
    DateTime currentWeekMondayStart = DateTime(
        currentWeekMonday.year, currentWeekMonday.month, currentWeekMonday.day);
    final recurrenceIndex = TodoRecurrenceCalendarIndex(_allTodos);

    for (var todo in _allTodos) {
      if (!recurrenceIndex.shouldDisplayPersisted(todo)) continue;
      bool isRecurring = todo.recurrence != RecurrenceType.none;
      List<TodoItem> todosToPlace;

      if (isRecurring) {
        todosToPlace = _expandRecurringTodo(todo, currentWeekMondayStart)
            .where((occurrence) {
          final start = DateTime.fromMillisecondsSinceEpoch(
            occurrence.createdDate ?? occurrence.createdAt,
            isUtc: true,
          ).toLocal();
          return recurrenceIndex.shouldProjectVirtual(todo, start);
        }).toList();
      } else {
        todosToPlace = [todo];
      }

      for (var effectiveTodo in todosToPlace) {
        DateTime start = DateTime.fromMillisecondsSinceEpoch(
                effectiveTodo.createdDate ?? effectiveTodo.createdAt,
                isUtc: true)
            .toLocal();
        DateTime end =
            effectiveTodo.dueDate ?? start.add(const Duration(hours: 1));

        bool isAllDayFlag = effectiveTodo.dueDate != null &&
            start.hour == 0 &&
            start.minute == 0 &&
            effectiveTodo.dueDate!.hour == 23 &&
            effectiveTodo.dueDate!.minute == 59;
        bool isCrossDay = !(start.year == end.year &&
            start.month == end.month &&
            start.day == end.day);
        bool treatAsAllDay = isAllDayFlag || isCrossDay;

        if (_activeDataViews.contains('hideCrossDay') && isCrossDay) {
          continue;
        }

        for (int i = 1; i <= 7; i++) {
          DateTime dayStart = currentWeekMondayStart.add(Duration(days: i - 1));
          DateTime dayEnd =
              dayStart.add(const Duration(hours: 23, minutes: 59, seconds: 59));

          if (start.isBefore(dayEnd) && end.isAfter(dayStart)) {
            if (treatAsAllDay) {
              _allDayTodosPerDay[i]!.add(effectiveTodo);
            } else {
              _intraDayTodosPerDay[i]!.add(effectiveTodo);
            }
          }
        }
      }
    }

    // 排序：未完成优先
    for (int i = 1; i <= 7; i++) {
      _allDayTodosPerDay[i]!.sort((a, b) {
        if (a.isDone == b.isDone) return 0;
        return a.isDone ? 1 : -1;
      });
      _intraDayTodosPerDay[i]!.sort((a, b) {
        if (a.isDone == b.isDone) return 0;
        return a.isDone ? 1 : -1;
      });
    }
  }

  void _updateWeekTimeLogsPomodorosAndPlans() {
    _timeLogsPerDay = {1: [], 2: [], 3: [], 4: [], 5: [], 6: [], 7: []};
    _pomodorosPerDay = {1: [], 2: [], 3: [], 4: [], 5: [], 6: [], 7: []};
    _planBlocksPerDay = {1: [], 2: [], 3: [], 4: [], 5: [], 6: [], 7: []};

    if (_semesterMonday == null) return;

    DateTime currentWeekMonday =
        _semesterMonday!.add(Duration(days: (_currentWeek - 1) * 7));

    for (int i = 1; i <= 7; i++) {
      DateTime dayStart = currentWeekMonday.add(Duration(days: i - 1));
      DateTime dayStartMs =
          DateTime(dayStart.year, dayStart.month, dayStart.day);
      DateTime dayEndMs = dayStartMs.add(const Duration(days: 1));

      int dayStartMsEpoch = dayStartMs.millisecondsSinceEpoch;
      int dayEndMsEpoch = dayEndMs.millisecondsSinceEpoch;

      for (var log in _allTimeLogs) {
        if (log.endTime > dayStartMsEpoch && log.startTime < dayEndMsEpoch) {
          _timeLogsPerDay[i]!.add(log);
        }
      }

      for (var record in _allPomodoroRecords) {
        int recordEnd = record.endTime ??
            (record.startTime + record.effectiveDuration * 1000);
        if (recordEnd > dayStartMsEpoch && record.startTime < dayEndMsEpoch) {
          // 🚀 跳过与计划块关联的番茄钟，避免重复显示
          if (!_isPomodoroAssociatedWithPlan(record)) {
            _pomodorosPerDay[i]!.add(record);
          }
        }
      }

      for (var plan in _allPlanBlocks) {
        if (plan.endTime > dayStartMsEpoch && plan.startTime < dayEndMsEpoch) {
          _planBlocksPerDay[i]!.add(plan);
        }
      }
    }
  }
}
