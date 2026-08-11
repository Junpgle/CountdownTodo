part of 'course_screens.dart';
// ignore_for_file: annotate_overrides, unused_element, unused_element_parameter

mixin _WeeklyCourseNavigation on _WeeklyCourseScreenStateBase {
  void _changeWeek(int delta) {
    _isNextSlide = delta > 0;
    _jumpToWeek(_currentWeek + delta);
  }

  void _jumpToWeek(int newWeek) {
    if (!mounted) return;
    setState(() {
      _currentWeek = newWeek;
      _isLoading = true;
    });

    // 🚀 核心优化：根据周次自动判断学期，然后过滤课程
    _updateWeekCourses();
    _updateWeekTodos();
    _updateWeekTimeLogsPomodorosAndPlans();
    _checkCollapsedSlots();

    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  void _toggleViewMode(int mode) {
    if (_viewMode == mode) return;
    setState(() {
      _viewMode = mode;
      if (mode == 0) {
        _updateWeekTodos();
        if (!_pulseController.isAnimating) {
          _pulseController.repeat(reverse: true);
        }
      } else {
        if (_pulseController.isAnimating) {
          _pulseController.stop();
        }
        if (mode == 2 && !_monthDataPrepared) {
          _groupDataForMonthView();
        }
      }
    });
  }

  void _changeMonth(int delta) {
    setState(() {
      _isNextSlide = delta > 0;
      _selectedMonth =
          DateTime(_selectedMonth.year, _selectedMonth.month + delta, 1);
    });
  }

  String _getWeekLabel() {
    if (_viewMode == 2) {
      return DateFormat('yyyy年M月').format(_selectedMonth);
    }
    if (_semesterMonday == null || _semesters.isEmpty) {
      return '第 $_currentWeek 周';
    }

    // 计算当前周次对应的周一日期
    DateTime currentWeekMonday =
        _semesterMonday!.add(Duration(days: (_currentWeek - 1) * 7));

    // 找到这个日期属于哪个学期，并计算在该学期中的相对周次
    String? targetSemesterName;
    int relativeWeek = _currentWeek;

    for (final semester in _semesters) {
      final semesterStart = DateTime(semester.startDate.year,
          semester.startDate.month, semester.startDate.day);
      final semesterEnd = semester.endDate != null
          ? DateTime(semester.endDate!.year, semester.endDate!.month,
              semester.endDate!.day)
          : semesterStart.add(const Duration(days: 120));

      // 检查当前周的周一是否在这个学期的范围内
      if (!currentWeekMonday.isBefore(semesterStart) &&
          !currentWeekMonday.isAfter(semesterEnd)) {
        targetSemesterName = semester.name;
        // 计算在该学期中的相对周次
        final semesterMonday =
            semesterStart.subtract(Duration(days: semesterStart.weekday - 1));
        relativeWeek =
            (currentWeekMonday.difference(semesterMonday).inDays ~/ 7) + 1;
        break;
      }
    }

    // 显示周次标签
    if (targetSemesterName != null && relativeWeek >= 1) {
      return '$targetSemesterName 第 $relativeWeek 周';
    } else {
      // 如果没有找到对应的学期，显示日期范围
      DateTime sunday = currentWeekMonday.add(const Duration(days: 6));
      return '${DateFormat('M/d').format(currentWeekMonday)}-${DateFormat('M/d').format(sunday)}';
    }
  }

  String _getBiWeekLabel() {
    if (_semesterMonday == null || _semesters.isEmpty) {
      return "第$_currentWeek-${_currentWeek + 1}周";
    }

    // 计算当前周次对应的周一日期
    DateTime w1Monday =
        _semesterMonday!.add(Duration(days: (_currentWeek - 1) * 7));
    DateTime w2Monday = w1Monday.add(const Duration(days: 7));

    // 找到这两个日期属于哪个学期
    String getSemesterWeekLabel(DateTime date) {
      for (final semester in _semesters) {
        final semesterStart = DateTime(semester.startDate.year,
            semester.startDate.month, semester.startDate.day);
        final semesterEnd = semester.endDate != null
            ? DateTime(semester.endDate!.year, semester.endDate!.month,
                semester.endDate!.day)
            : semesterStart.add(const Duration(days: 120));

        if (!date.isBefore(semesterStart) && !date.isAfter(semesterEnd)) {
          final semesterMonday =
              semesterStart.subtract(Duration(days: semesterStart.weekday - 1));
          final relativeWeek =
              (date.difference(semesterMonday).inDays ~/ 7) + 1;
          return '${semester.name} 第$relativeWeek周';
        }
      }
      return DateFormat('M/d').format(date);
    }

    String label1 = getSemesterWeekLabel(w1Monday);
    String label2 = getSemesterWeekLabel(w2Monday);

    // 如果两个周次在同一个学期，简写
    if (label1.split(' ').first == label2.split(' ').first) {
      final week1 = label1.split(' ').last;
      final week2 = label2.split(' ').last;
      final weekNumber1 = week1.replaceAll(RegExp(r'[^0-9]'), '');
      final weekNumber2 = week2.replaceAll(RegExp(r'[^0-9]'), '');
      return '${label1.split(' ').first} 第$weekNumber1-$weekNumber2周';
    } else {
      return '$label1-$label2';
    }
  }

  void _showWeekJumpDialog() {
    final TextEditingController controller =
        TextEditingController(text: '$_currentWeek');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('跳转到指定周'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: '周次',
                border: OutlineInputBorder(),
                suffixText: '周',
              ),
              autofocus: true,
            ),
            if (_availableWeeks.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                '有课周次：${_availableWeeks.first}-${_availableWeeks.last}周',
                style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 12),
              ),
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [
                ActionChip(
                  label: const Text('本周'),
                  onPressed: () {
                    Navigator.pop(ctx);
                    _jumpToCurrentWeek();
                  },
                ),
                if (_availableWeeks.isNotEmpty)
                  ActionChip(
                    label: Text('第${_availableWeeks.first}周'),
                    onPressed: () {
                      Navigator.pop(ctx);
                      _jumpToWeek(_availableWeeks.first);
                    },
                  ),
                if (_availableWeeks.isNotEmpty)
                  ActionChip(
                    label: Text('第${_availableWeeks.last}周'),
                    onPressed: () {
                      Navigator.pop(ctx);
                      _jumpToWeek(_availableWeeks.last);
                    },
                  ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
            onPressed: () {
              int? week = int.tryParse(controller.text.trim());
              if (week != null && week >= 1) {
                Navigator.pop(ctx);
                _jumpToWeek(week);
              }
            },
            child: const Text('跳转'),
          ),
        ],
      ),
    );
  }

  void _jumpToCurrentWeek() {
    if (_semesterMonday == null) return;
    DateTime now = DateTime.now();
    int daysDiff = now.difference(_semesterMonday!).inDays;
    int week = (daysDiff ~/ 7) + 1;
    if (week < 1) week = 1;
    _jumpToWeek(week);
  }

  Widget _buildMonthDaySidebar(DateTime day) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final String dateStr = DateFormat('yyyy年M月d日').format(day);
    final String weekdayStr =
        ['周一', '周二', '周三', '周四', '周五', '周六', '周日'][day.weekday - 1];

    final dStr = DateFormat('yyyy-MM-dd').format(day);
    final List<dynamic> items = [];

    // 根据筛选条件收集数据
    if (_activeDataViews.contains('courses')) {
      items.addAll(_monthCourseMap[dStr] ?? []);
    }

    if (_activeDataViews.contains('todos')) {
      items.addAll(_monthTodoMap[dStr] ?? []);
      if (!_activeDataViews.contains('hideCrossDay')) {
        items.addAll(_monthCrossDayTodoMap[dStr] ?? []);
      }
    }

    if (_activeDataViews.contains('timeLogs')) {
      items.addAll(_monthLogMap[dStr] ?? []);
    }

    if (_activeDataViews.contains('plans')) {
      items.addAll(_monthPlanMap[dStr] ?? []);
    }

    if (_activeDataViews.contains('pomodoros')) {
      items.addAll(_monthPomMap[dStr] ?? []);
    }

    items.sort((a, b) {
      int getStartTime(dynamic item) {
        if (item is CourseItem) {
          // 课程：转换为当天的分钟数进行比较
          return item.startTime;
        }
        if (item is TodoItem) {
          // 待办：如果是全天/跨天，取创建时间或 0 点；如果是日内，取 dueDate 的时间
          if (item.dueDate == null) return 0;
          return item.dueDate!.hour * 100 + item.dueDate!.minute;
        }
        if (item is TimeLogItem) {
          final dt =
              DateTime.fromMillisecondsSinceEpoch(item.startTime, isUtc: true)
                  .toLocal();
          return dt.hour * 100 + dt.minute;
        }
        if (item is TodoPlanBlock) {
          final dt =
              DateTime.fromMillisecondsSinceEpoch(item.startTime).toLocal();
          return dt.hour * 100 + dt.minute;
        }
        if (item is PomodoroRecord) {
          final dt =
              DateTime.fromMillisecondsSinceEpoch(item.startTime, isUtc: true)
                  .toLocal();
          return dt.hour * 100 + dt.minute;
        }
        return 9999;
      }

      final int timeA = getStartTime(a);
      final int timeB = getStartTime(b);

      if (timeA != timeB) return timeA.compareTo(timeB);

      // 如果时间相同，再按类型排优先级
      int getPriority(dynamic item) {
        if (item is CourseItem) return 0;
        if (item is TodoItem) return 1;
        if (item is TimeLogItem) return 2;
        if (item is TodoPlanBlock) return 3;
        if (item is PomodoroRecord) return 4;
        return 5;
      }

      return getPriority(a).compareTo(getPriority(b));
    });

    return Container(
      width: double.infinity,
      color: Theme.of(context).colorScheme.surfaceContainer,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        weekdayStr,
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        dateStr,
                        style: TextStyle(
                          fontSize: 14,
                          color: isDark ? Colors.white54 : Colors.black54,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => setState(() => _selectedMonthDay = null),
                  tooltip: '关闭详情',
                ),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20),
            child: Divider(),
          ),
          Expanded(
            child: items.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.event_available,
                            size: 64,
                            color: isDark ? Colors.white10 : Colors.black12),
                        const SizedBox(height: 16),
                        Text('该日无安排',
                            style: TextStyle(
                                color:
                                    isDark ? Colors.white24 : Colors.black26)),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                    itemCount: items.length,
                    itemBuilder: (context, index) =>
                        _buildDetailSidebarItem(context, items[index]),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailSidebarItem(BuildContext context, dynamic item) {
    if (item is CourseItem) {
      final color = _getCourseColor(item.courseName);
      return ListTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1), shape: BoxShape.circle),
          child: Icon(Icons.class_, color: color, size: 20),
        ),
        title: Text(item.courseName,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
        subtitle: Text(
            '${item.formattedStartTime}-${item.formattedEndTime} @ ${item.roomName}',
            style: const TextStyle(fontSize: 12)),
        onTap: () => Navigator.push(
            context,
            PageTransitions.material(
                builder: (_) => CourseDetailScreen(course: item))),
      );
    } else if (item is TodoItem) {
      final colorScheme = Theme.of(context).colorScheme;
      final statusColor =
          item.isDone ? colorScheme.cdtSuccess : colorScheme.cdtWarning;
      return ListTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: statusColor.withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(item.isDone ? Icons.check_circle : Icons.task_alt,
              color: statusColor, size: 20),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(item.title,
                  style: TextStyle(
                    fontSize: 15,
                    decoration: item.isDone ? TextDecoration.lineThrough : null,
                    color: item.isDone ? colorScheme.cdtDisabled : null,
                  )),
            ),
            if (item.teamUuid != null)
              Container(
                margin: const EdgeInsets.only(left: 4),
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: Theme.of(context)
                      .colorScheme
                      .primary
                      .withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                      color: Theme.of(context)
                          .colorScheme
                          .primary
                          .withValues(alpha: 0.3)),
                ),
                child: Icon(Icons.group,
                    size: 12, color: Theme.of(context).colorScheme.primary),
              ),
          ],
        ),
        subtitle: Text(
            (item.teamUuid != null ? '${item.teamName ?? '团队'} · ' : '') +
                (item.dueDate != null
                    ? '截止: ${DateFormat('HH:mm').format(item.dueDate!)}'
                    : '无截止时间') +
                (item.remark != null && item.remark!.isNotEmpty
                    ? ' · ${item.remark}'
                    : ''),
            style: const TextStyle(fontSize: 12),
            maxLines: 2,
            overflow: TextOverflow.ellipsis),
        onTap: () => Navigator.push(
            context,
            PageTransitions.material(
                builder: (_) => TodoDetailScreen(todo: item))),
      );
    } else if (item is TimeLogItem) {
      final color = Theme.of(context).colorScheme.primary;
      return ListTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1), shape: BoxShape.circle),
          child: Icon(Icons.edit_calendar, color: color, size: 20),
        ),
        title: Text(item.title.isNotEmpty ? item.title : '时间日志',
            style: const TextStyle(fontSize: 15)),
        subtitle: Text(
            '${DateFormat('HH:mm').format(DateTime.fromMillisecondsSinceEpoch(item.startTime, isUtc: true).toLocal())} - ${DateFormat('HH:mm').format(DateTime.fromMillisecondsSinceEpoch(item.endTime, isUtc: true).toLocal())}',
            style: const TextStyle(fontSize: 12)),
      );
    } else if (item is TodoPlanBlock) {
      final color = Theme.of(context).colorScheme.secondary;
      final start =
          DateTime.fromMillisecondsSinceEpoch(item.startTime).toLocal();
      final end = DateTime.fromMillisecondsSinceEpoch(item.endTime).toLocal();
      return ListTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1), shape: BoxShape.circle),
          child: Icon(
              item.status == TodoPlanStatus.finished
                  ? Icons.event_available
                  : Icons.event_note,
              color: color,
              size: 20),
        ),
        title: Text(item.titleSnapshot ?? '规划任务',
            style: const TextStyle(fontSize: 15)),
        subtitle: Text(
            '${DateFormat('HH:mm').format(start)} - ${DateFormat('HH:mm').format(end)} · 计划 ${item.plannedMinutes} 分钟',
            style: const TextStyle(fontSize: 12)),
      );
    } else if (item is PomodoroRecord) {
      final color = Theme.of(context).colorScheme.cdtFocus;
      return ListTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1), shape: BoxShape.circle),
          child: Icon(Icons.timer, color: color, size: 20),
        ),
        title: const Text('番茄专注', style: TextStyle(fontSize: 15)),
        subtitle: Text('时长: ${item.effectiveDuration ~/ 60} 分钟',
            style: const TextStyle(fontSize: 12)),
      );
    }
    return const SizedBox.shrink();
  }

  void _handleFilterSelection(String value) {
    setState(() {
      if (value == 'clearAll') {
        _activeDataViews.clear();
        _updateWeekTodos();
      } else if (value == 'selectAll') {
        _activeDataViews
            .addAll({'courses', 'todos', 'plans', 'timeLogs', 'pomodoros'});
        _updateWeekTodos();
      } else if (value == 'disableFreeTimeCollapse') {
        _collapseFreeTime = !_collapseFreeTime;
      } else {
        if (_activeDataViews.contains(value)) {
          _activeDataViews.remove(value);
        } else {
          _activeDataViews.add(value);
        }
        if (value == 'todos' || value == 'hideCrossDay') {
          _updateWeekTodos();
        }
      }
    });
    _checkCollapsedSlots();
  }

  Widget _buildCheckableMenuItem(String key, String label) {
    final bool isSelected = key == 'disableFreeTimeCollapse'
        ? !_collapseFreeTime
        : _activeDataViews.contains(key);
    return MenuItemButton(
      closeOnActivate: false,
      onPressed: () => _handleFilterSelection(key),
      child: SizedBox(
        width: 150,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isSelected ? Icons.check : null,
              size: 16,
              color: isSelected
                  ? Theme.of(context).colorScheme.primary
                  : Colors.transparent,
            ),
            const SizedBox(width: 8),
            Text(label),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterActionItem(
      String value, String label, IconData icon, Color color) {
    return MenuItemButton(
      closeOnActivate: false,
      onPressed: () => _handleFilterSelection(value),
      child: SizedBox(
        width: 150,
        child: Row(
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 8),
            Text(label, style: TextStyle(color: color)),
          ],
        ),
      ),
    );
  }

  DateTime? _getMondayOfCurrentWeek() {
    if (_semesterMonday != null) {
      return _semesterMonday!.add(Duration(days: (_currentWeek - 1) * 7));
    }
    return null;
  }

  void _checkCollapsedSlots() {
    if (!_collapseFreeTime) {
      setState(() {
        _hiddenTimeRanges = const [];
        _lunchCardStartMinute = null;
        _lunchCardDuration = 0.0;
        _lunchCollapseText = '';
      });
      return;
    }

    const earlyStart = 360.0;
    const earlyEnd = 480.0;
    const lunchStart = 720.0;
    const lunchEnd = 840.0;
    const lateStart = 1260.0;
    const lateEnd = 1440.0;
    const lunchReserve = 20.0;

    // 初始值：min >= max 表示该敏感区间完全空闲。
    double minEarly = earlyEnd, maxEarly = earlyStart;
    double minLunch = lunchEnd, maxLunch = lunchStart;
    double minLate = lateEnd, maxLate = lateStart;

    void updateBounds(double s, double e) {
      // 时段 A [06:00, 08:00]
      double sA = s.clamp(earlyStart, earlyEnd);
      double eA = e.clamp(earlyStart, earlyEnd);
      if (sA < eA) {
        if (sA < minEarly) minEarly = sA;
        if (eA > maxEarly) maxEarly = eA;
      }

      // 时段 B [720, 840]
      double sB = s.clamp(lunchStart, lunchEnd);
      double eB = e.clamp(lunchStart, lunchEnd);
      if (sB < eB) {
        if (sB < minLunch) minLunch = sB;
        if (eB > maxLunch) maxLunch = eB;
      }

      // 时段 C [21:00, 24:00]
      double sC = s.clamp(lateStart, lateEnd);
      double eC = e.clamp(lateStart, lateEnd);
      if (sC < eC) {
        if (sC < minLate) minLate = sC;
        if (eC > maxLate) maxLate = eC;
      }
    }

    // 1. 扫描当前可见课程数据
    if (_activeDataViews.contains('courses')) {
      for (var course in _weekCourses) {
        double cs = (course.startTime ~/ 100) * 60.0 + (course.startTime % 100);
        double ce = (course.endTime ~/ 100) * 60.0 + (course.endTime % 100);
        updateBounds(cs, ce);
      }
    }

    final weekMonday = _getMondayOfCurrentWeek();

    void updateBoundsFromEpochRange(int startMs, int endMs) {
      if (weekMonday == null || endMs <= startMs) return;

      final weekStart =
          DateTime(weekMonday.year, weekMonday.month, weekMonday.day);
      final weekEnd = weekStart.add(const Duration(days: 7));
      DateTime start =
          DateTime.fromMillisecondsSinceEpoch(startMs, isUtc: true).toLocal();
      DateTime end =
          DateTime.fromMillisecondsSinceEpoch(endMs, isUtc: true).toLocal();

      if (!end.isAfter(weekStart) || !start.isBefore(weekEnd)) return;
      if (start.isBefore(weekStart)) start = weekStart;
      if (end.isAfter(weekEnd)) end = weekEnd;

      DateTime dayStart = DateTime(start.year, start.month, start.day);
      while (dayStart.isBefore(end)) {
        final dayEnd = dayStart.add(const Duration(days: 1));
        final sliceStart = start.isAfter(dayStart) ? start : dayStart;
        final sliceEnd = end.isBefore(dayEnd) ? end : dayEnd;
        if (sliceEnd.isAfter(sliceStart)) {
          final double sliceStartMinute =
              sliceStart.hour * 60.0 + sliceStart.minute;
          final double sliceEndMinute = sliceEnd == dayEnd
              ? 1440.0
              : sliceEnd.hour * 60.0 + sliceEnd.minute;
          updateBounds(
            sliceStartMinute,
            sliceEndMinute,
          );
        }
        dayStart = dayEnd;
      }
    }

    // 2. 扫描当前可见日内待办
    if (_activeDataViews.contains('todos')) {
      for (int weekday = 1; weekday <= 7; weekday++) {
        for (var todo in _intraDayTodosPerDay[weekday] ?? []) {
          if (todo.dueDate == null) continue;
          DateTime dt = todo.dueDate!;
          double m = dt.hour * 60.0 + dt.minute;
          updateBounds(m, m + 1); // 截止时间点算作 1 分钟区间
        }
      }
    }

    // 3. 扫描当前可见时间日志
    if (_activeDataViews.contains('timeLogs')) {
      for (var log in _allTimeLogs) {
        updateBoundsFromEpochRange(log.startTime, log.endTime);
      }
    }

    // 4. 扫描当前可见计划块
    if (_activeDataViews.contains('plans')) {
      for (var plan in _allPlanBlocks) {
        updateBoundsFromEpochRange(plan.startTime, plan.endTime);
      }
    }

    // 5. 扫描当前可见专注记录。这里不能复用 _pomodorosPerDay，因为它会为避免
    // 界面重复显示而跳过已关联计划块的专注记录。
    if (_activeDataViews.contains('pomodoros')) {
      for (var record in _allPomodoroRecords) {
        final int endMs = record.endTime ??
            (record.startTime + record.effectiveDuration * 1000);
        updateBoundsFromEpochRange(record.startTime, endMs);
      }
    }

    ({double pre, double post}) buildHideLengths(
        double rangeStart, double rangeEnd, double minStart, double maxEnd,
        {bool onlyHideBefore = false}) {
      if (minStart >= maxEnd) {
        return (pre: rangeEnd - rangeStart, post: 0.0);
      }
      return (
        pre: (minStart - rangeStart).clamp(0.0, rangeEnd - rangeStart),
        post: onlyHideBefore
            ? 0.0
            : (rangeEnd - maxEnd).clamp(0.0, rangeEnd - rangeStart),
      );
    }

    void addRange(List<_HiddenTimeRange> ranges, double start, double end) {
      if (end - start > 0.01) {
        ranges.add(_HiddenTimeRange(start, end));
      }
    }

    void addTwoSidedRanges(
      List<_HiddenTimeRange> ranges,
      double rangeStart,
      double rangeEnd,
      double pre,
      double post,
    ) {
      addRange(ranges, rangeStart, rangeStart + pre);
      addRange(ranges, rangeEnd - post, rangeEnd);
    }

    final early = buildHideLengths(earlyStart, earlyEnd, minEarly, maxEarly,
        onlyHideBefore: true);
    final lunch = buildHideLengths(lunchStart, lunchEnd, minLunch, maxLunch);
    final late = buildHideLengths(lateStart, lateEnd, minLate, maxLate,
        onlyHideBefore: true);
    final String lunchCollapseText =
        _buildLunchCollapseText(lunchStart, lunchEnd, lunch.pre, lunch.post);

    double lunchPre = lunch.pre;
    double lunchPost = lunch.post;
    double? lunchCardStartMinute;
    double lunchCardDuration = 0.0;

    final double totalLunchHide = lunchPre + lunchPost;
    if (totalLunchHide > 0.0) {
      lunchCardDuration =
          totalLunchHide > lunchReserve ? lunchReserve : totalLunchHide;

      if (lunchPre > 0.0) {
        lunchCardStartMinute = lunchStart;
        final double reserveFromPre =
            lunchPre >= lunchCardDuration ? lunchCardDuration : lunchPre;
        lunchPre -= reserveFromPre;
        final double reserveRemain = lunchCardDuration - reserveFromPre;
        if (reserveRemain > 0.0) {
          lunchPost =
              (lunchPost - reserveRemain).clamp(0.0, lunchEnd - lunchStart);
        }
      } else {
        lunchCardStartMinute = lunchEnd - lunchPost;
        lunchPost =
            (lunchPost - lunchCardDuration).clamp(0.0, lunchEnd - lunchStart);
      }
    }

    final hiddenRanges = <_HiddenTimeRange>[];
    addTwoSidedRanges(
        hiddenRanges, earlyStart, earlyEnd, early.pre, early.post);
    addTwoSidedRanges(hiddenRanges, lunchStart, lunchEnd, lunchPre, lunchPost);
    addTwoSidedRanges(hiddenRanges, lateStart, lateEnd, late.pre, late.post);
    hiddenRanges.sort((a, b) => a.startMinute.compareTo(b.startMinute));

    setState(() {
      _hiddenTimeRanges = hiddenRanges;
      _lunchCardStartMinute = lunchCardStartMinute;
      _lunchCardDuration = lunchCardDuration;
      _lunchCollapseText = lunchCollapseText;
    });
  }
}
