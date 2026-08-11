part of 'course_screens.dart';
// ignore_for_file: annotate_overrides, unused_element, unused_element_parameter

mixin _WeeklyCourseView on _WeeklyCourseScreenStateBase {
  Widget _buildTodaySidebar() {
    DateTime now = DateTime.now();
    String dateStr = DateFormat('M月d日').format(now);
    String weekdayStr =
        ['周一', '周二', '周三', '周四', '周五', '周六', '周日'][now.weekday - 1];
    bool isDark = Theme.of(context).brightness == Brightness.dark;

    List<TodoItem> todayAllDay = !_activeDataViews.contains('todos')
        ? []
        : _allTodos.where((todo) {
            DateTime start = DateTime.fromMillisecondsSinceEpoch(
                    todo.createdDate ?? todo.createdAt,
                    isUtc: true)
                .toLocal();
            DateTime end = todo.dueDate ?? start.add(const Duration(hours: 1));

            bool isAllDayFlag = todo.dueDate != null &&
                start.hour == 0 &&
                start.minute == 0 &&
                todo.dueDate!.hour == 23 &&
                todo.dueDate!.minute == 59;
            bool isCrossDay = !(start.year == end.year &&
                start.month == end.month &&
                start.day == end.day);
            bool treatAsAllDay = isAllDayFlag || isCrossDay;

            if (!treatAsAllDay) return false;

            // 如果开启了隐藏跨天，且该任务是跨天任务，则过滤掉
            if (_activeDataViews.contains('hideCrossDay') && isCrossDay) {
              return false;
            }

            DateTime todayStart = DateTime(now.year, now.month, now.day);
            DateTime todayEnd = todayStart
                .add(const Duration(hours: 23, minutes: 59, seconds: 59));

            return start.isBefore(todayEnd) && end.isAfter(todayStart);
          }).toList();

    // 排序：未完成优先
    todayAllDay.sort((a, b) {
      if (a.isDone == b.isDone) return 0;
      return a.isDone ? 1 : -1;
    });

    // 🚀 平板适配：如果是在月视图且选中了日期，展示该日的详情
    if (_viewMode == 2 && _selectedMonthDay != null) {
      return _buildMonthDaySidebar(_selectedMonthDay!);
    }

    return Container(
      width: double.infinity,
      color: Theme.of(context).colorScheme.surfaceContainer,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "今日全天事项",
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  "$dateStr · $weekdayStr",
                  style: TextStyle(
                    fontSize: 14,
                    color: isDark ? Colors.white54 : Colors.black54,
                  ),
                ),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20),
            child: Divider(),
          ),
          Expanded(
            child: todayAllDay.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.event_available,
                            size: 48,
                            color: isDark ? Colors.white12 : Colors.black12),
                        const SizedBox(height: 16),
                        Text(
                          "今天没有全天待办",
                          style: TextStyle(
                            color: isDark ? Colors.white24 : Colors.black26,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: todayAllDay.length,
                    itemBuilder: (context, index) {
                      final todo = todayAllDay[index];
                      return Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 4),
                        child: InkWell(
                          onTap: () {
                            Navigator.push(
                                context,
                                PageTransitions.slideHorizontal(
                                    TodoDetailScreen(todo: todo)));
                          },
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: todo.isDone
                                  ? (isDark
                                      ? Theme.of(context)
                                          .colorScheme
                                          .cdtSuccess
                                          .withValues(alpha: 0.1)
                                      : Theme.of(context)
                                          .colorScheme
                                          .cdtSuccess
                                          .withValues(alpha: 0.05))
                                  : (isDark
                                      ? Theme.of(context)
                                          .colorScheme
                                          .cdtWarning
                                          .withValues(alpha: 0.1)
                                      : Theme.of(context)
                                          .colorScheme
                                          .cdtWarning
                                          .withValues(alpha: 0.05)),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: todo.isDone
                                    ? Theme.of(context)
                                        .colorScheme
                                        .cdtSuccess
                                        .withValues(alpha: 0.3)
                                    : Theme.of(context)
                                        .colorScheme
                                        .cdtWarning
                                        .withValues(alpha: 0.3),
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  todo.isDone
                                      ? Icons.check_circle
                                      : Icons.task_alt,
                                  size: 20,
                                  color: todo.isDone
                                      ? Theme.of(context).colorScheme.cdtSuccess
                                      : Theme.of(context)
                                          .colorScheme
                                          .cdtWarning,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      if (todo.teamUuid != null)
                                        Padding(
                                          padding:
                                              const EdgeInsets.only(bottom: 2),
                                          child: Row(
                                            children: [
                                              Icon(Icons.group,
                                                  size: 10,
                                                  color: Theme.of(context)
                                                      .colorScheme
                                                      .primary),
                                              const SizedBox(width: 4),
                                              Text(todo.teamName ?? '团队',
                                                  style: TextStyle(
                                                      fontSize: 10,
                                                      color: Theme.of(context)
                                                          .colorScheme
                                                          .primary,
                                                      fontWeight:
                                                          FontWeight.bold)),
                                            ],
                                          ),
                                        ),
                                      Text(
                                        todo.title,
                                        style: TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w500,
                                          decoration: todo.isDone
                                              ? TextDecoration.lineThrough
                                              : null,
                                          color: todo.isDone
                                              ? (isDark
                                                  ? Colors.white38
                                                  : Colors.black38)
                                              : (isDark
                                                  ? Colors.white
                                                  : Colors.black87),
                                        ),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
          Padding(
            padding: const EdgeInsets.all(20.0),
            child: Text(
              "共 ${todayAllDay.length} 项全天事项",
              style: TextStyle(
                  fontSize: 12,
                  color: isDark ? Colors.white24 : Colors.black26),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    bool isDark = Theme.of(context).brightness == Brightness.dark;
    final bool isDesktop = MediaQuery.of(context).size.width >= 768;

    return Scaffold(
      appBar: AppBar(
        title: LayoutBuilder(
          builder: (context, constraints) {
            final navigationWidth =
                constraints.maxWidth < 420 ? constraints.maxWidth : 420.0;

            return SizedBox(
              width: navigationWidth,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  IconButton(
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    icon: const Icon(Icons.arrow_back_ios, size: 13),
                    onPressed: () {
                      if (_viewMode == 2) {
                        _changeMonth(-1);
                      } else if (_viewMode == 1) {
                        _changeWeek(-2);
                      } else {
                        _changeWeek(-1);
                      }
                    },
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: GestureDetector(
                      onTap: _viewMode == 0 ? _showWeekJumpDialog : null,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.center,
                        child: Text(
                          _viewMode == 2
                              ? DateFormat('yyyy年M月').format(_selectedMonth)
                              : (_viewMode == 1
                                  ? _getBiWeekLabel()
                                  : _getWeekLabel()),
                          maxLines: 1,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              fontSize: 15, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    icon: const Icon(Icons.arrow_forward_ios, size: 13),
                    onPressed: () {
                      if (_viewMode == 2) {
                        _changeMonth(1);
                      } else if (_viewMode == 1) {
                        _changeWeek(2);
                      } else {
                        _changeWeek(1);
                      }
                    },
                  ),
                ],
              ),
            );
          },
        ),
        centerTitle: true,
        titleSpacing: 0,
        actions: [
          IconButton(
            key: _viewModeKey,
            visualDensity: const VisualDensity(horizontal: -2),
            icon: Icon(
                _viewMode == 2
                    ? Icons.view_week
                    : (_viewMode == 1
                        ? Icons.calendar_month
                        : Icons.calendar_view_week),
                size: 20),
            tooltip: '切换视图模式',
            onPressed: () => _toggleViewMode((_viewMode + 1) % 3),
          ),
          if (isDesktop)
            IconButton(
              key: _timeLogKey,
              visualDensity: const VisualDensity(horizontal: -2),
              icon: const Icon(Icons.edit_calendar, size: 20),
              tooltip: '记录时间日志',
              onPressed: () async {
                final result = await Navigator.push(
                  context,
                  PageTransitions.material(
                    builder: (context) =>
                        TimeLogScreen(username: widget.username),
                  ),
                );
                if (result == true) {
                  _loadData();
                }
              },
            ),
          MenuAnchor(
            key: _filterKey,
            menuChildren: [
              _buildCheckableMenuItem('courses', '课表'),
              _buildCheckableMenuItem('todos', '待办'),
              _buildCheckableMenuItem('timeLogs', '时间日志'),
              _buildCheckableMenuItem('plans', '今日规划'),
              _buildCheckableMenuItem('pomodoros', '番茄钟'),
              const Divider(height: 1),
              _buildCheckableMenuItem('hideCrossDay', '隐藏跨天待办'),
              _buildCheckableMenuItem('disableFreeTimeCollapse', '不折叠空余时间'),
              const Divider(height: 1),
              _buildFilterActionItem(
                'selectAll',
                '一键全选',
                Icons.select_all,
                Theme.of(context).colorScheme.primary,
              ),
              _buildFilterActionItem(
                'clearAll',
                '一键清除',
                Icons.clear_all,
                Theme.of(context).colorScheme.error,
              ),
            ],
            builder: (context, controller, child) {
              return IconButton(
                visualDensity: const VisualDensity(horizontal: -2),
                icon: const Icon(Icons.filter_list, size: 20),
                tooltip: '筛选显示内容',
                onPressed: () {
                  if (controller.isOpen) {
                    controller.close();
                  } else {
                    controller.open();
                  }
                },
              );
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _isLoading
          ? _buildSkeleton()
          : LayoutBuilder(
              builder: (context, constraints) {
                final bool isWide = constraints.maxWidth > 900;

                return Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onScaleUpdate: (details) {
                          final now = DateTime.now();
                          if (_lastModeSwitch != null &&
                              now.difference(_lastModeSwitch!).inMilliseconds <
                                  800) {
                            return;
                          }

                          if (details.scale < 0.7) {
                            if (_viewMode < 2) {
                              _toggleViewMode(_viewMode + 1);
                              _lastModeSwitch = now;
                              HapticFeedback.lightImpact();
                            }
                          } else if (details.scale > 1.5) {
                            if (_viewMode > 0) {
                              _toggleViewMode(_viewMode - 1);
                              _lastModeSwitch = now;
                              HapticFeedback.lightImpact();
                            }
                          }
                        },
                        onHorizontalDragUpdate: (details) {
                          // 让视图跟手移动
                          setState(() {
                            _dragOffset += details.delta.dx;
                          });
                        },
                        onHorizontalDragEnd: (details) {
                          final screenWidth = MediaQuery.of(context).size.width;
                          final threshold = screenWidth * 0.2; // 20% 宽度触发切换

                          if (_dragOffset.abs() > threshold ||
                              details.primaryVelocity!.abs() > 300) {
                            if (_dragOffset > 0 ||
                                (details.primaryVelocity ?? 0) > 300) {
                              // 向右滑动 -> 上一个
                              if (_viewMode == 2) {
                                _changeMonth(-1);
                              } else {
                                _changeWeek(-1);
                              }
                            } else {
                              // 向左滑动 -> 下一个
                              if (_viewMode == 2) {
                                _changeMonth(1);
                              } else {
                                _changeWeek(1);
                              }
                            }
                            HapticFeedback.lightImpact();
                          }

                          // 重置位移（AnimatedSwitcher 会处理新旧视图的平滑切换）
                          setState(() {
                            _dragOffset = 0;
                          });
                        },
                        child: Column(
                          children: [
                            if (_viewMode == 0) ...[
                              SizedBox(
                                key: _dayHeaderKey,
                                child: _buildHeader(_getMondayOfCurrentWeek()),
                              ),
                              SizedBox(
                                key: _allDayKey,
                                child: _buildAllDayHeaderRow(
                                    _getMondayOfCurrentWeek()),
                              ),
                              Divider(
                                  height: 1,
                                  thickness: 0.5,
                                  color:
                                      isDark ? Colors.white10 : Colors.black12),
                            ],
                            Expanded(
                              child: _viewMode > 0
                                  ? CourseMonthView(
                                      key: ValueKey(
                                          'MonthView_${_selectedMonth.year}_${_selectedMonth.month}_mode$_viewMode'),
                                      selectedMonth: _selectedMonth,
                                      courseMap: _monthCourseMap,
                                      todoMap: _monthTodoMap,
                                      crossDayTodoMap: _monthCrossDayTodoMap,
                                      logMap: _monthLogMap,
                                      pomMap: _monthPomMap,
                                      pomodoroTags: _pomodoroTags,
                                      activeDataViews: _activeDataViews,
                                      allTodos: _allTodos,
                                      viewMode: _viewMode,
                                      currentWeekMonday:
                                          _getMondayOfCurrentWeek(),
                                      onMonthChanged: (m) =>
                                          setState(() => _selectedMonth = m),
                                      onDayTapped: (d) {
                                        setState(() => _selectedMonthDay = d);
                                        if (constraints.maxWidth <= 900) {
                                          _showDayDetailSheet(d);
                                        }
                                      },
                                      onGanttTodoTap: (todo) {
                                        if (todo.dueDate != null) {
                                          setState(() =>
                                              _selectedMonthDay = todo.dueDate);
                                          if (constraints.maxWidth <= 900) {
                                            _showDayDetailSheet(todo.dueDate!);
                                          }
                                        }
                                      },
                                    )
                                  : AnimatedSwitcher(
                                      key: _gridKey,
                                      duration:
                                          const Duration(milliseconds: 400),
                                      transitionBuilder: (child, animation) {
                                        return Transform.translate(
                                          offset: Offset(
                                              _dragOffset *
                                                  (1.0 - animation.value),
                                              0),
                                          child: SlideTransition(
                                            position: Tween<Offset>(
                                              begin: Offset(
                                                  _isNextSlide ? 1.0 : -1.0,
                                                  0.0),
                                              end: Offset.zero,
                                            ).animate(CurvedAnimation(
                                                parent: animation,
                                                curve: Curves.easeOutCubic)),
                                            child: FadeTransition(
                                                opacity: animation,
                                                child: child),
                                          ),
                                        );
                                      },
                                      child: RepaintBoundary(
                                        key: ValueKey('WeekView_$_currentWeek'),
                                        child: LayoutBuilder(
                                          builder: (context, innerConstraints) {
                                            double cellWidth =
                                                (innerConstraints.maxWidth -
                                                        timeColumnWidth) /
                                                    7;
                                            double totalMinutes =
                                                (endHour - startHour) * 60.0 -
                                                    _totalHiddenMinutes;
                                            double minuteHeight =
                                                innerConstraints.maxHeight /
                                                    totalMinutes;

                                            return _buildGrid(
                                                cellWidth, minuteHeight);
                                          },
                                        ),
                                      ),
                                    ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (isWide)
                      Container(
                        width: 350,
                        decoration: BoxDecoration(
                          border: Border(
                            left: BorderSide(
                              color: isDark ? Colors.white10 : Colors.black12,
                              width: 1,
                            ),
                          ),
                        ),
                        child: _selectedMonthDay != null
                            ? _buildMonthDaySidebar(_selectedMonthDay!)
                            : _buildTodaySidebar(),
                      ),
                  ],
                );
              },
            ),
    );
  }

  Widget _buildSkeleton() {
    bool isDark = Theme.of(context).brightness == Brightness.dark;
    Color baseColor =
        isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.05);

    return FadeTransition(
      opacity: _pulseAnimation,
      child: Column(
        children: [
          // 头部骨架 (日期)
          Container(
            height: 60,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Container(width: timeColumnWidth),
                for (int i = 0; i < 7; i++)
                  Expanded(
                    child: Center(
                      child: Container(
                        width: 30,
                        height: 12,
                        decoration: BoxDecoration(
                          color: baseColor,
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          // 网格骨架
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                double cellWidth = (constraints.maxWidth - timeColumnWidth) / 7;
                return Row(
                  children: [
                    Container(width: timeColumnWidth),
                    Expanded(
                      child: Stack(
                        children: [
                          // 纵向分割线
                          for (int i = 0; i <= 7; i++)
                            Positioned(
                              left: i * cellWidth,
                              top: 0,
                              bottom: 0,
                              child: Container(width: 0.5, color: baseColor),
                            ),
                          // 几个占位框，模拟课表布局
                          _buildSkeletonBox(cellWidth, 120, 80, 1, baseColor),
                          _buildSkeletonBox(cellWidth, 250, 60, 2, baseColor),
                          _buildSkeletonBox(cellWidth, 150, 100, 4, baseColor),
                          _buildSkeletonBox(cellWidth, 400, 90, 5, baseColor),
                          _buildSkeletonBox(cellWidth, 200, 70, 0, baseColor),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSkeletonBox(
      double cellWidth, double top, double height, int dayIndex, Color color) {
    return Positioned(
      left: dayIndex * cellWidth + 4,
      top: top,
      width: cellWidth - 8,
      height: height,
      child: Container(
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );
  }

  void _showDayDetailSheet(DateTime day) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.75,
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
        ),
        child: ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
          child: _buildMonthDaySidebar(day),
        ),
      ),
    );
  }
}
