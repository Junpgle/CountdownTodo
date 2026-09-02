part of 'course_screens.dart';
// ignore_for_file: annotate_overrides, unused_element, unused_element_parameter

mixin _WeeklyCourseGrid on _WeeklyCourseScreenStateBase {
  double get _totalHiddenMinutes =>
      _hiddenTimeRanges.fold(0.0, (sum, range) => sum + range.duration);

  double _mapTimeToVirtualMinutes(int hour, int minute) {
    double m = (hour * 60 + minute).toDouble();
    final startMinute = startHour * 60.0;
    if (m < startMinute) return 0;

    final hiddenBefore = _hiddenTimeRanges.fold(
        0.0, (sum, range) => sum + range.hiddenBefore(m));
    double virtualM = m - startMinute - hiddenBefore;
    return virtualM < 0 ? 0 : virtualM;
  }

  double _timeToY(int hour, int minute, double minuteHeight) {
    double virtualMinutes = _mapTimeToVirtualMinutes(hour, minute);
    return virtualMinutes * minuteHeight;
  }

  Color _getCourseColor(String courseName) {
    final colorScheme = Theme.of(context).colorScheme;
    final List<Color> colors = [
      colorScheme.secondary,
      colorScheme.tertiary,
      colorScheme.primary,
      colorScheme.cdtWarning,
      colorScheme.cdtSuccess,
      colorScheme.error,
      colorScheme.secondaryContainer,
      colorScheme.tertiaryContainer,
    ];
    int hash = courseName.hashCode;
    return colors[hash % colors.length];
  }

  void _showAllDayTodos(
      BuildContext context, List<TodoItem> todos, String dateStr) {
    showAppModalBottomSheet(
        context: context,
        shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
        builder: (ctx) {
          final colorScheme = Theme.of(ctx).colorScheme;
          return SafeArea(
            child: Container(
                padding: const EdgeInsets.all(16),
                constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(context).size.height * 0.5),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Center(
                        child: Container(
                            width: 40,
                            height: 4,
                            decoration: BoxDecoration(
                                color: colorScheme.outlineVariant,
                                borderRadius: BorderRadius.circular(2))),
                      ),
                      const SizedBox(height: 16),
                      Text("$dateStr 全天/跨天待办",
                          style: const TextStyle(
                              fontSize: 18, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 16),
                      Expanded(
                          child: ListView.builder(
                              itemCount: todos.length,
                              itemBuilder: (context, index) {
                                final todo = todos[index];
                                return ListTile(
                                  leading: Icon(
                                      todo.isDone
                                          ? Icons.check_circle
                                          : Icons.task_alt,
                                      color: todo.isDone
                                          ? colorScheme.cdtSuccess
                                          : colorScheme.cdtWarning),
                                  title: Text(todo.title,
                                      style: TextStyle(
                                          decoration: todo.isDone
                                              ? TextDecoration.lineThrough
                                              : null)),
                                  subtitle: Column(
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
                                                  size: 12,
                                                  color: Theme.of(context)
                                                      .colorScheme
                                                      .primary),
                                              const SizedBox(width: 4),
                                              Text(
                                                  "${todo.teamName ?? '团队'} · ${todo.creatorName ?? '成员'}",
                                                  style: TextStyle(
                                                      fontSize: 11,
                                                      color: Theme.of(context)
                                                          .colorScheme
                                                          .primary,
                                                      fontWeight:
                                                          FontWeight.bold)),
                                            ],
                                          ),
                                        ),
                                      Text(
                                          "开始: ${DateFormat('MM-dd HH:mm').format(DateTime.fromMillisecondsSinceEpoch(todo.createdDate ?? todo.createdAt, isUtc: true).toLocal())}\n截止: ${todo.dueDate != null ? DateFormat('MM-dd HH:mm').format(todo.dueDate!) : '无'}"),
                                    ],
                                  ),
                                  onTap: () {
                                    Navigator.pop(ctx);
                                    Navigator.push(
                                        context,
                                        PageTransitions.slideHorizontal(
                                            TodoDetailScreen(todo: todo)));
                                  },
                                );
                              }))
                    ])),
          );
        });
  }

  void _showAllDayDeviceCalendarEvents(
    BuildContext context,
    List<DeviceCalendarEvent> events,
    String dateStr,
  ) {
    showAppModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('$dateStr 手机日历全天日程',
                  style: Theme.of(ctx).textTheme.titleMedium),
              const SizedBox(height: 8),
              ...events.map(
                (event) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.phone_android_rounded,
                      color: event.colorValue == null
                          ? Theme.of(ctx).colorScheme.tertiary
                          : Color(event.colorValue!)),
                  title: Text(event.title),
                  subtitle:
                      event.location == null ? null : Text(event.location!),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAllDayHeaderRow(DateTime? monday) {
    if (monday == null) {
      return const SizedBox.shrink();
    }

    final showTodos = _activeDataViews.contains('todos');
    final showDeviceCalendar = _activeDataViews.contains('deviceCalendar');
    bool hasAnyAllDay = (showTodos &&
            _allDayTodosPerDay.values.any((list) => list.isNotEmpty)) ||
        (showDeviceCalendar &&
            _allDayDeviceCalendarEventsPerDay.values
                .any((list) => list.isNotEmpty));
    if (!hasAnyAllDay) return const SizedBox.shrink();

    return Container(
      padding: EdgeInsets.only(left: timeColumnWidth, bottom: 2),
      color: Theme.of(context).colorScheme.surface,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: List.generate(7, (index) {
          int weekday = index + 1;
          List<TodoItem> dayTodos =
              showTodos ? (_allDayTodosPerDay[weekday] ?? []) : [];
          List<DeviceCalendarEvent> deviceEvents = showDeviceCalendar
              ? (_allDayDeviceCalendarEventsPerDay[weekday] ?? [])
              : [];

          if (dayTodos.isEmpty && deviceEvents.isEmpty) {
            return const Expanded(child: SizedBox(height: 22));
          }

          String text;
          if (dayTodos.isNotEmpty && deviceEvents.isNotEmpty) {
            text = '${dayTodos.length + deviceEvents.length}项全天日程';
          } else if (deviceEvents.isNotEmpty) {
            text = deviceEvents.length == 1
                ? deviceEvents.first.title
                : '${deviceEvents.length}项手机日历';
          } else {
            text = dayTodos.length == 1
                ? dayTodos.first.title
                : "${dayTodos.length}项全天待办";
          }
          bool allDone = dayTodos.every((t) => t.isDone);
          final colorScheme = Theme.of(context).colorScheme;
          final todoColor = deviceEvents.isNotEmpty && dayTodos.isEmpty
              ? (deviceEvents.first.colorValue == null
                  ? colorScheme.tertiary
                  : Color(deviceEvents.first.colorValue!))
              : (allDone ? colorScheme.cdtSuccess : colorScheme.cdtWarning);
          final onTodoColor =
              allDone ? colorScheme.onTertiary : colorScheme.onSecondary;

          return Expanded(
            child: GestureDetector(
              onTap: () {
                DateTime currentDay = monday.add(Duration(days: index));
                String dateStr = DateFormat('MM-dd').format(currentDay);
                if (deviceEvents.isNotEmpty && dayTodos.isEmpty) {
                  _showAllDayDeviceCalendarEvents(
                      context, deviceEvents, dateStr);
                } else {
                  _showAllDayTodos(context, dayTodos, dateStr);
                }
              },
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 1, vertical: 1),
                padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
                decoration: BoxDecoration(
                  color: todoColor.withValues(alpha: allDone ? 0.5 : 0.85),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (deviceEvents.isNotEmpty && dayTodos.isEmpty)
                      Padding(
                        padding: const EdgeInsets.only(right: 2),
                        child: Icon(Icons.phone_android_rounded,
                            size: 10, color: onTodoColor),
                      )
                    else if (dayTodos.any((t) => t.teamUuid != null))
                      Padding(
                        padding: const EdgeInsets.only(right: 2),
                        child: Icon(Icons.group, size: 10, color: onTodoColor),
                      ),
                    Flexible(
                      child: Text(
                        text,
                        style: TextStyle(
                          fontSize: 11,
                          color: onTodoColor,
                          decoration:
                              allDone ? TextDecoration.lineThrough : null,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  bool _timeRangesOverlap(
      int startA, int endAExclusive, int startB, int endBExclusive) {
    return endAExclusive > startB && startA < endBExclusive;
  }

  bool _isRecordAssociatedWithPlan(PomodoroRecord record, TodoPlanBlock plan) {
    if (record.isDeleted || plan.isDeleted) return false;

    if (plan.pomodoroRecordIds.contains(record.uuid)) {
      return true;
    }

    if (record.planBlockId != null &&
        record.planBlockId!.isNotEmpty &&
        record.planBlockId == plan.id) {
      return true;
    }

    if (plan.todoId.isNotEmpty &&
        record.todoUuid != null &&
        record.todoUuid!.isNotEmpty &&
        record.todoUuid == plan.todoId) {
      final int recordEnd = record.endTime ??
          (record.startTime + record.effectiveDuration * 1000);
      return _timeRangesOverlap(
          record.startTime, recordEnd, plan.startTime, plan.endTime);
    }

    return false;
  }

  // --- 辅助方法：计算规划块关联的番茄钟完成情况 ---
  Map<String, dynamic> _calculatePlanPomodoroProgress(TodoPlanBlock plan) {
    final associatedRecords = _allPomodoroRecords
        .where((record) => _isRecordAssociatedWithPlan(record, plan))
        .toList();

    if (associatedRecords.isEmpty) {
      return {'completed': 0, 'total': 0, 'progress': 0.0};
    }

    // 计算实际专注进度（秒）
    int totalSeconds = 0;
    int completedSeconds = 0;

    for (var record in associatedRecords) {
      final int effective =
          record.effectiveDuration > 0 ? record.effectiveDuration : 0;
      final int planned =
          record.plannedDuration > 0 ? record.plannedDuration : effective;
      final int base = planned > 0 ? planned : 1;
      totalSeconds += base;
      completedSeconds += effective.clamp(0, base);
    }

    final progress = totalSeconds > 0 ? completedSeconds / totalSeconds : 0.0;

    return {
      'completed': completedSeconds,
      'total': totalSeconds,
      'progress': progress.clamp(0.0, 1.0),
      'recordCount': associatedRecords.length,
    };
  }

  // --- 辅助方法：检查番茄钟是否被某个计划块关联 ---
  bool _isPomodoroAssociatedWithPlan(PomodoroRecord record) {
    return _allPlanBlocks
        .any((plan) => _isRecordAssociatedWithPlan(record, plan));
  }

  Widget _buildHeader(DateTime? monday) {
    DateTime now = DateTime.now();
    String todayStr = DateFormat('yyyy-MM-dd').format(now);
    bool isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      color: Theme.of(context).colorScheme.surface,
      padding: EdgeInsets.only(left: timeColumnWidth, top: 4, bottom: 4),
      child: Row(
        children: List.generate(7, (index) {
          DateTime? currentDate;
          String dateStr = '';
          bool isToday = false;

          if (monday != null) {
            currentDate = monday.add(Duration(days: index));
            dateStr = DateFormat('M/dd').format(currentDate);
            isToday = DateFormat('yyyy-MM-dd').format(currentDate) == todayStr;
          }

          List<String> weekdays = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];

          return Expanded(
            child: Column(
              children: [
                Text(
                  weekdays[index],
                  style: TextStyle(
                    color: isToday
                        ? Theme.of(context).colorScheme.primary
                        : (isDark ? Colors.white70 : Colors.black87),
                    fontWeight: isToday ? FontWeight.bold : FontWeight.normal,
                    fontSize: 13,
                  ),
                ),
                if (dateStr.isNotEmpty)
                  Text(
                    dateStr,
                    style: TextStyle(
                      color: isToday
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 11,
                    ),
                  ),
              ],
            ),
          );
        }),
      ),
    );
  }

  bool _isHourCollapsed(int hour) {
    double m = hour * 60.0;
    return _hiddenTimeRanges.any((range) => range.contains(m));
  }

  String _formatMinute(double minute) {
    final int value = minute.round();
    final int h = value ~/ 60;
    final int m = value % 60;
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
  }

  String _buildLunchCollapseText(
      double rangeStart, double rangeEnd, double pre, double post) {
    final ranges = <String>[];
    if (pre > 0.0) {
      ranges.add(
          '${_formatMinute(rangeStart)}-${_formatMinute(rangeStart + pre)}');
    }
    if (post > 0.0) {
      ranges
          .add('${_formatMinute(rangeEnd - post)}-${_formatMinute(rangeEnd)}');
    }
    return ranges.join(' & ');
  }

  Widget _buildGrid(double cellWidth, double minuteHeight) {
    List<Widget> children = [];
    bool isDark = Theme.of(context).brightness == Brightness.dark;
    Color lineColor = isDark ? Colors.white10 : Colors.black12;
    Color textColor = isDark ? Colors.white70 : Colors.black87;

    for (int hour = startHour; hour <= endHour; hour++) {
      // 🚀 自适应时间隐藏：如果该小时正点落于本周的合并收窄区间中，跳过不绘制
      if (_isHourCollapsed(hour)) continue;

      double y = _timeToY(hour, 0, minuteHeight);

      children.add(Positioned(
        top: y,
        left: timeColumnWidth,
        right: 0,
        height: 1,
        child: Container(color: lineColor),
      ));

      if (hour < endHour) {
        // 🚀 动态自适应刻度容器高：寻找下一个可见的刻度小时并求高差，避免刻度重叠挤压
        int nextHour = hour + 1;
        while (nextHour <= endHour) {
          if (_isHourCollapsed(nextHour)) {
            nextHour++;
            continue;
          }
          break;
        }
        double slotHeight = _timeToY(nextHour, 0, minuteHeight) - y;

        children.add(Positioned(
          top: y,
          left: 0,
          width: timeColumnWidth,
          height: slotHeight,
          child: Align(
            alignment: Alignment.topCenter,
            child: Padding(
              padding: const EdgeInsets.only(top: 2.0),
              child: Text(
                '${hour.toString().padLeft(2, '0')}:00',
                style: TextStyle(
                    fontSize: 12,
                    color: textColor,
                    fontWeight: FontWeight.w500),
              ),
            ),
          ),
        ));
      }
    }

    final lunchCardStart = _lunchCardStartMinute;
    if (lunchCardStart != null && _lunchCardDuration > 0.0) {
      final int lunchCardHour = lunchCardStart ~/ 60;
      final int lunchCardMinute = lunchCardStart.round() % 60;
      final double y1 = _timeToY(lunchCardHour, lunchCardMinute, minuteHeight);
      double collapseHeight = _lunchCardDuration * minuteHeight;

      children.add(Positioned(
        top: y1 + 1,
        left: timeColumnWidth + 1,
        right: 1,
        height: (collapseHeight - 2).clamp(2.0, double.infinity).toDouble(),
        child: Container(
          decoration: BoxDecoration(
            color: isDark
                ? Colors.white.withValues(alpha: 0.06)
                : Colors.black.withValues(alpha: 0.035),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: isDark ? Colors.white10 : Colors.black12,
              width: 0.5,
            ),
          ),
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: isDark
                    ? [
                        Colors.white.withValues(alpha: 0.012),
                        Colors.white.withValues(alpha: 0.012),
                        Colors.white.withValues(alpha: 0.04),
                        Colors.white.withValues(alpha: 0.04),
                        Colors.white.withValues(alpha: 0.012),
                        Colors.white.withValues(alpha: 0.012),
                      ]
                    : [
                        Colors.black.withValues(alpha: 0.008),
                        Colors.black.withValues(alpha: 0.008),
                        Colors.black.withValues(alpha: 0.028),
                        Colors.black.withValues(alpha: 0.028),
                        Colors.black.withValues(alpha: 0.008),
                        Colors.black.withValues(alpha: 0.008),
                      ],
                stops: const [0.0, 0.18, 0.18, 0.32, 0.32, 1.0],
              ),
            ),
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    '☕ 午休区间已折叠 ($_lunchCollapseText)',
                    style: TextStyle(
                      fontSize: 10,
                      color: isDark ? Colors.white54 : Colors.black54,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ));
    }

    for (int i = 0; i <= 7; i++) {
      children.add(Positioned(
        top: 0,
        bottom: 0,
        left: timeColumnWidth + i * cellWidth,
        width: 0.5,
        child: Container(color: lineColor),
      ));
    }

    Map<int, List<_TimelineEvent>> eventsPerDay = {
      1: [],
      2: [],
      3: [],
      4: [],
      5: [],
      6: [],
      7: [],
    };

    if (_activeDataViews.contains('todos')) {
      final collisionMap = <String, int>{};
      for (int weekday = 1; weekday <= 7; weekday++) {
        final dayTodos = _intraDayTodosPerDay[weekday] ?? [];
        for (var todo in dayTodos) {
          DateTime start = DateTime.fromMillisecondsSinceEpoch(
                  todo.createdDate ?? todo.createdAt,
                  isUtc: true)
              .toLocal();
          DateTime end = todo.dueDate ?? start.add(const Duration(hours: 1));

          double top = _timeToY(start.hour, start.minute, minuteHeight);
          double bottom = _timeToY(end.hour, end.minute, minuteHeight);
          double height = bottom - top;

          if (height < 20.0) height = 20.0;

          final collisionKey = '${weekday}_${(top / 15).floor()}';
          final stackIndex = collisionMap[collisionKey] ?? 0;
          collisionMap[collisionKey] = stackIndex + 1;

          final colorScheme = Theme.of(context).colorScheme;
          Color todoColor =
              (todo.isDone ? colorScheme.cdtSuccess : colorScheme.cdtWarning)
                  .withValues(alpha: todo.isDone ? 0.5 : 0.85);
          final todoCardKey = _getTodoCardKey(todo.id, weekday: weekday);
          final todoIndex = _intraDayTodosPerDay.values
              .expand((e) => e)
              .toList()
              .indexOf(todo);

          eventsPerDay[weekday]!.add(_TimelineEvent(
              top: top,
              bottom: top + height,
              builder: (left, width) {
                final double fontScale =
                    (width / (cellWidth - 2)).clamp(0.4, 1.0);
                final double titleFontSize =
                    (height * 0.32 * fontScale).clamp(9.0, 10.5);
                final double teamFontSize =
                    (height * 0.22 * fontScale).clamp(8.0, 9.0);
                final double availableForTodo =
                    (todo.teamUuid != null && height >= 32)
                        ? height - (teamFontSize + 7.0)
                        : height - 2.0;
                int todoMaxLines =
                    (availableForTodo / (titleFontSize + 1.0)).floor();
                if (todoMaxLines < 1) todoMaxLines = 1;

                return Positioned(
                  top: top,
                  left: left,
                  width: width,
                  height: height,
                  child: AnimatedBuilder(
                    animation: _courseExpandAnim,
                    builder: (ctx, child) {
                      final delay = (todoIndex * 0.06).clamp(0.0, 0.5);
                      final t =
                          ((_courseExpandAnim.value - delay) / (1.0 - delay))
                              .clamp(0.0, 1.0);
                      final scale = 0.7 + 0.3 * t;
                      final opacity = t;
                      return Transform.scale(
                        scale: scale,
                        child: Opacity(
                          opacity: opacity,
                          child: child,
                        ),
                      );
                    },
                    child: GestureDetector(
                      onTap: () {
                        final renderBox = todoCardKey.currentContext
                            ?.findRenderObject() as RenderBox?;
                        if (renderBox != null) {
                          final rect = renderBox.localToGlobal(Offset.zero) &
                              renderBox.size;
                          Navigator.push(
                            context,
                            ContainerTransformRoute(
                              page: TodoDetailScreen(todo: todo),
                              sourceRect: rect,
                              sourceColor: todoColor,
                              sourceBorderRadius:
                                  const BorderRadius.all(Radius.circular(4)),
                            ),
                          );
                        } else {
                          Navigator.push(
                              context,
                              PageTransitions.slideHorizontal(
                                  TodoDetailScreen(todo: todo)));
                        }
                      },
                      child: Container(
                        key: todoCardKey,
                        alignment: Alignment.center,
                        clipBehavior: Clip.hardEdge,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 2, vertical: 1),
                        decoration: BoxDecoration(
                            color: todoColor,
                            borderRadius: BorderRadius.circular(4),
                            boxShadow: stackIndex > 0
                                ? [
                                    const BoxShadow(
                                        color: Colors.black12,
                                        blurRadius: 2,
                                        offset: Offset(-1, 1))
                                  ]
                                : null),
                        child: height < 20
                            ? Icon(
                                todo.isDone
                                    ? Icons.check_circle
                                    : Icons.task_alt,
                                size: 10,
                                color: Colors.white)
                            : SingleChildScrollView(
                                physics: const NeverScrollableScrollPhysics(),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (todo.teamUuid != null && height >= 32)
                                      Padding(
                                        padding:
                                            const EdgeInsets.only(bottom: 2.0),
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 2, vertical: 0.5),
                                          decoration: BoxDecoration(
                                            color: Colors.white
                                                .withValues(alpha: 0.3),
                                            borderRadius:
                                                BorderRadius.circular(2),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              const Icon(Icons.group,
                                                  size: 8, color: Colors.white),
                                              const SizedBox(width: 1),
                                              Flexible(
                                                // 🚀 强制填满剩余空间并截断
                                                child: Text(
                                                  todo.teamName ?? '团队',
                                                  style: TextStyle(
                                                      color: Colors.white,
                                                      fontSize: teamFontSize,
                                                      fontWeight:
                                                          FontWeight.bold),
                                                  maxLines: 1,
                                                  textAlign: TextAlign.center,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    if (height >= 38) ...[
                                      Icon(
                                          todo.isDone
                                              ? Icons.check_circle
                                              : Icons.task_alt,
                                          size: 10,
                                          color: Colors.white),
                                      const SizedBox(height: 2),
                                    ],
                                    Text(
                                      todo.title,
                                      style: TextStyle(
                                          color: Colors.white,
                                          fontSize: titleFontSize,
                                          fontWeight: FontWeight.bold,
                                          decoration: todo.isDone
                                              ? TextDecoration.lineThrough
                                              : null,
                                          height: 1.0),
                                      maxLines: todoMaxLines,
                                      textAlign: TextAlign.center,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    if (todo.remark != null &&
                                        todo.remark!.isNotEmpty &&
                                        height > 32)
                                      Flexible(
                                        child: Text(
                                          todo.remark!,
                                          style: TextStyle(
                                            color: Colors.white
                                                .withValues(alpha: 0.75),
                                            fontSize: 8,
                                            height: 1.2,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                      ),
                    ),
                  ),
                );
              }));
        }
      }
    }

    if (_activeDataViews.contains('timeLogs')) {
      for (int weekday = 1; weekday <= 7; weekday++) {
        for (var log in _timeLogsPerDay[weekday]!) {
          DateTime start =
              DateTime.fromMillisecondsSinceEpoch(log.startTime, isUtc: true)
                  .toLocal();
          DateTime end =
              DateTime.fromMillisecondsSinceEpoch(log.endTime, isUtc: true)
                  .toLocal();

          double top = _timeToY(start.hour, start.minute, minuteHeight);
          double bottom = _timeToY(end.hour, end.minute, minuteHeight);
          double height = bottom - top;

          if (height < 18.0) height = 18.0;

          Color logColor =
              Theme.of(context).colorScheme.cdtInfo.withValues(alpha: 0.7);
          String logTitle = log.title.isNotEmpty ? log.title : '时间日志';
          if (log.tagUuids.isNotEmpty) {
            final tag = _pomodoroTags.cast<PomodoroTag?>().firstWhere(
                (t) => log.tagUuids.contains(t?.uuid),
                orElse: () => null);
            if (tag != null) {
              logColor = AppColorUtils.hexToColor(
                tag.color,
                fallback: Theme.of(context).colorScheme.cdtInfo,
                opacity: 0.7,
              );
              if (logTitle == '时间日志') logTitle = tag.name;
            }
          }

          final logCardKey = _getTimeLogCardKey(log.id);
          final logIndex =
              _timeLogsPerDay.values.expand((e) => e).toList().indexOf(log);

          eventsPerDay[weekday]!.add(_TimelineEvent(
              top: top,
              bottom: top + height,
              builder: (left, width) {
                final double fontScale =
                    (width / (cellWidth - 2)).clamp(0.4, 1.0);
                final double titleFontSize =
                    (height * 0.32 * fontScale).clamp(9.0, 10.5);
                final double timeFontSize =
                    (height * 0.22 * fontScale).clamp(8.0, 9.0);
                final double availableForLog =
                    height > 22 ? height - (timeFontSize + 2.0) : height - 2.0;
                int logMaxLines =
                    (availableForLog / (titleFontSize + 1.0)).floor();
                if (logMaxLines < 1) logMaxLines = 1;

                return Positioned(
                  top: top,
                  left: left,
                  width: width,
                  height: height,
                  child: AnimatedBuilder(
                    animation: _courseExpandAnim,
                    builder: (ctx, child) {
                      final delay = (logIndex * 0.06).clamp(0.0, 0.5);
                      final t =
                          ((_courseExpandAnim.value - delay) / (1.0 - delay))
                              .clamp(0.0, 1.0);
                      final scale = 0.7 + 0.3 * t;
                      final opacity = t;
                      return Transform.scale(
                        scale: scale,
                        child: Opacity(
                          opacity: opacity,
                          child: child,
                        ),
                      );
                    },
                    child: GestureDetector(
                      onTap: () {
                        final renderBox = logCardKey.currentContext
                            ?.findRenderObject() as RenderBox?;
                        if (renderBox != null) {
                          final rect = renderBox.localToGlobal(Offset.zero) &
                              renderBox.size;
                          Navigator.push(
                            context,
                            ContainerTransformRoute(
                              page: TimeLogDetailScreen(
                                  log: log, tags: _pomodoroTags),
                              sourceRect: rect,
                              sourceColor: logColor,
                              sourceBorderRadius:
                                  const BorderRadius.all(Radius.circular(4)),
                            ),
                          );
                        } else {
                          Navigator.push(
                              context,
                              PageTransitions.slideHorizontal(
                                  TimeLogDetailScreen(
                                      log: log, tags: _pomodoroTags)));
                        }
                      },
                      child: Container(
                        key: logCardKey,
                        alignment: Alignment.center,
                        clipBehavior: Clip.hardEdge,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 2, vertical: 1),
                        decoration: BoxDecoration(
                            color: logColor,
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                                color: logColor.withValues(alpha: 1.0),
                                width: 0.5)),
                        child: height < 18
                            ? const Icon(Icons.edit_calendar,
                                size: 8, color: Colors.white)
                            : SingleChildScrollView(
                                physics: const NeverScrollableScrollPhysics(),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (height >= 38) ...[
                                      Icon(Icons.edit_calendar,
                                          size: 8, color: Colors.white),
                                      const SizedBox(height: 2),
                                    ],
                                    Text(
                                      logTitle,
                                      style: TextStyle(
                                          color: Colors.white,
                                          fontSize: titleFontSize,
                                          fontWeight: FontWeight.bold,
                                          height: 1.0),
                                      maxLines: logMaxLines,
                                      textAlign: TextAlign.center,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    if (height > 22)
                                      Text(
                                        '${start.hour.toString().padLeft(2, '0')}:${start.minute.toString().padLeft(2, '0')}-${end.hour.toString().padLeft(2, '0')}:${end.minute.toString().padLeft(2, '0')}',
                                        style: TextStyle(
                                            color: Colors.white
                                                .withValues(alpha: 0.8),
                                            fontSize: timeFontSize,
                                            height: 1.0),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                  ],
                                ),
                              ),
                      ),
                    ),
                  ),
                );
              }));
        }
      }
    }

    if (_activeDataViews.contains('plans')) {
      for (int weekday = 1; weekday <= 7; weekday++) {
        for (var plan in _planBlocksPerDay[weekday] ?? <TodoPlanBlock>[]) {
          final start =
              DateTime.fromMillisecondsSinceEpoch(plan.startTime).toLocal();
          final end =
              DateTime.fromMillisecondsSinceEpoch(plan.endTime).toLocal();

          double top = _timeToY(start.hour, start.minute, minuteHeight);
          double bottom = _timeToY(end.hour, end.minute, minuteHeight);
          double height = bottom - top;
          if (height < 18.0) height = 18.0;

          final colorScheme = Theme.of(context).colorScheme;
          final planColor = plan.status == TodoPlanStatus.finished
              ? colorScheme.cdtSuccess.withValues(alpha: 0.58)
              : colorScheme.secondary.withValues(alpha: 0.58);
          final title = plan.titleSnapshot ?? '规划任务';
          final planIndex =
              _planBlocksPerDay.values.expand((e) => e).toList().indexOf(plan);

          // 计算关联的番茄钟完成进度
          final pomProgress = _calculatePlanPomodoroProgress(plan);
          final recordCount = (pomProgress['recordCount'] as int?) ?? 0;
          final hasAssociatedPomodoro = recordCount > 0;

          eventsPerDay[weekday]!.add(_TimelineEvent(
              top: top,
              bottom: top + height,
              builder: (left, width) {
                final double fontScale =
                    (width / (cellWidth - 2)).clamp(0.4, 1.0);
                final double titleFontSize =
                    (height * 0.32 * fontScale).clamp(9.0, 10.5);
                final double subFontSize =
                    (height * 0.22 * fontScale).clamp(8.0, 9.0);

                int planMaxLines = 2;
                if (hasAssociatedPomodoro) {
                  double availableForPlan = height > 32
                      ? height - (subFontSize * 2 + 5.0)
                      : (height > 24
                          ? height - (subFontSize + 4.0)
                          : height - 4.0);
                  planMaxLines =
                      (availableForPlan / (titleFontSize + 1.0)).floor();
                  if (planMaxLines < 1) planMaxLines = 1;
                } else {
                  double availableForPlan =
                      height > 24 ? height - (subFontSize + 4.0) : height - 4.0;
                  planMaxLines =
                      (availableForPlan / (titleFontSize + 1.0)).floor();
                  if (planMaxLines < 1) planMaxLines = 1;
                }

                return Positioned(
                  top: top,
                  left: left + 3,
                  width: width > 6 ? width - 6 : width,
                  height: height,
                  child: AnimatedBuilder(
                    animation: _courseExpandAnim,
                    builder: (ctx, child) {
                      final delay = (planIndex * 0.04).clamp(0.0, 0.45);
                      final t =
                          ((_courseExpandAnim.value - delay) / (1.0 - delay))
                              .clamp(0.0, 1.0);
                      return Transform.scale(
                        scale: 0.8 + 0.2 * t,
                        child: Opacity(opacity: t, child: child),
                      );
                    },
                    child: Container(
                      alignment: Alignment.center,
                      clipBehavior: Clip.hardEdge,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 3, vertical: 2),
                      decoration: BoxDecoration(
                        color: planColor,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                            color: Colors.white.withValues(alpha: 0.35),
                            width: 0.5),
                      ),
                      // 如果有关联的番茄钟，用背景填充表示完成进度
                      child: hasAssociatedPomodoro
                          ? Stack(
                              fit: StackFit.expand,
                              children: [
                                // 背景进度条（从下往上）
                                Align(
                                  alignment: Alignment.bottomCenter,
                                  child: FractionallySizedBox(
                                    heightFactor:
                                        ((pomProgress['progress'] as double?) ??
                                                0.0)
                                            .clamp(0.0, 1.0),
                                    widthFactor: 1.0,
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color: Colors.white
                                            .withValues(alpha: 0.25),
                                      ),
                                    ),
                                  ),
                                ),
                                // 内容层
                                Center(
                                  child: SingleChildScrollView(
                                    physics:
                                        const NeverScrollableScrollPhysics(),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.center,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        if (height >= 38) ...[
                                          Icon(
                                              plan.status ==
                                                      TodoPlanStatus.finished
                                                  ? Icons.event_available
                                                  : Icons.event_note,
                                              size: 9,
                                              color: Colors.white),
                                          const SizedBox(height: 2),
                                        ],
                                        Text(
                                          title,
                                          style: TextStyle(
                                              color: Colors.white,
                                              fontSize: titleFontSize,
                                              fontWeight: FontWeight.bold,
                                              height: 1.0),
                                          maxLines: height < 28 ? 1 : 2,
                                          textAlign: TextAlign.center,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        if (height > 24)
                                          Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.center,
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Text(
                                                '${plan.plannedMinutes}min',
                                                style: TextStyle(
                                                    color: Colors.white
                                                        .withValues(
                                                            alpha: 0.85),
                                                    fontSize: subFontSize,
                                                    height: 1.0),
                                                maxLines: 1,
                                                textAlign: TextAlign.center,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                              // 显示番茄钟完成情况
                                              if (height > 32)
                                                Text(
                                                  '${(((pomProgress['progress'] as double?) ?? 0.0) * 100).toStringAsFixed(0)}%',
                                                  style: TextStyle(
                                                      color: Colors.white
                                                          .withValues(
                                                              alpha: 0.7),
                                                      fontSize: 6,
                                                      height: 1.0,
                                                      fontWeight:
                                                          FontWeight.bold),
                                                  maxLines: 1,
                                                  textAlign: TextAlign.center,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                            ],
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            )
                          : (height < 18
                              ? const Icon(Icons.event_note,
                                  size: 8, color: Colors.white)
                              : SingleChildScrollView(
                                  physics: const NeverScrollableScrollPhysics(),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.center,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (height >= 38) ...[
                                        Icon(
                                            plan.status ==
                                                    TodoPlanStatus.finished
                                                ? Icons.event_available
                                                : Icons.event_note,
                                            size: titleFontSize,
                                            color: Colors.white),
                                        const SizedBox(height: 2),
                                      ],
                                      Text(
                                        title,
                                        style: TextStyle(
                                            color: Colors.white,
                                            fontSize: titleFontSize,
                                            fontWeight: FontWeight.bold,
                                            height: 1.0),
                                        maxLines: height < 28 ? 1 : 2,
                                        textAlign: TextAlign.center,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      if (height > 24)
                                        Text(
                                          '${plan.plannedMinutes}min',
                                          style: TextStyle(
                                              color: Colors.white
                                                  .withValues(alpha: 0.85),
                                              fontSize: subFontSize,
                                              height: 1.0),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                    ],
                                  ))),
                    ),
                  ),
                );
              }));
        }
      }
    }

    if (_activeDataViews.contains('pomodoros')) {
      for (int weekday = 1; weekday <= 7; weekday++) {
        for (var record in _pomodorosPerDay[weekday]!) {
          DateTime pomStart =
              DateTime.fromMillisecondsSinceEpoch(record.startTime, isUtc: true)
                  .toLocal();
          int endMs = record.endTime ??
              (record.startTime + record.effectiveDuration * 1000);
          DateTime pomEnd =
              DateTime.fromMillisecondsSinceEpoch(endMs, isUtc: true).toLocal();

          final associatedPlans = (_planBlocksPerDay[weekday] ?? [])
              .where((plan) => _isRecordAssociatedWithPlan(record, plan))
              .toList();

          List<Map<String, DateTime>> segments = [
            {'start': pomStart, 'end': pomEnd}
          ];

          for (var plan in associatedPlans) {
            DateTime planStart =
                DateTime.fromMillisecondsSinceEpoch(plan.startTime, isUtc: true)
                    .toLocal();
            DateTime planEnd =
                DateTime.fromMillisecondsSinceEpoch(plan.endTime, isUtc: true)
                    .toLocal();

            List<Map<String, DateTime>> newSegments = [];
            for (var seg in segments) {
              DateTime s = seg['start']!;
              DateTime e = seg['end']!;

              if (e.isBefore(planStart) ||
                  e.isAtSameMomentAs(planStart) ||
                  s.isAfter(planEnd) ||
                  s.isAtSameMomentAs(planEnd)) {
                newSegments.add(seg);
              } else {
                if (s.isBefore(planStart)) {
                  newSegments.add({'start': s, 'end': planStart});
                }
                if (e.isAfter(planEnd)) {
                  newSegments.add({'start': planEnd, 'end': e});
                }
              }
            }
            segments = newSegments;
          }

          int segmentIndex = 0;
          for (var seg in segments) {
            DateTime start = seg['start']!;
            DateTime end = seg['end']!;

            double top = _timeToY(start.hour, start.minute, minuteHeight);
            double bottom = _timeToY(end.hour, end.minute, minuteHeight);
            double height = bottom - top;

            if (height < 5.0) continue;
            if (height < 18.0) height = 18.0;

            Color pomColor =
                Theme.of(context).colorScheme.cdtFocus.withValues(alpha: 0.6);
            String pomTitle = '专注';

            if (record.tagUuids.isNotEmpty) {
              final tag = _pomodoroTags.cast<PomodoroTag?>().firstWhere(
                  (t) => record.tagUuids.contains(t?.uuid),
                  orElse: () => null);
              if (tag != null) {
                pomColor = AppColorUtils.hexToColor(
                  tag.color,
                  fallback: Theme.of(context).colorScheme.cdtFocus,
                  opacity: 0.6,
                );
                pomTitle = tag.name;
              }
            }

            // 优先显示任务名，其次显示标签名
            if (record.todoTitle != null && record.todoTitle!.isNotEmpty) {
              pomTitle = record.todoTitle!;
            }

            final pomCardKey =
                _getPomodoroCardKey('${record.uuid}_${segmentIndex++}');
            final pomIndex = _pomodorosPerDay.values
                .expand((e) => e)
                .toList()
                .indexOf(record);

            eventsPerDay[weekday]!.add(_TimelineEvent(
                top: top,
                bottom: top + height,
                builder: (left, width) {
                  final double fontScale =
                      (width / (cellWidth - 2)).clamp(0.4, 1.0);
                  final double titleFontSize =
                      (height * 0.32 * fontScale).clamp(9.0, 10.5);
                  final double timeFontSize =
                      (height * 0.22 * fontScale).clamp(8.0, 9.0);
                  final double availableForPom = height > 22
                      ? height - (timeFontSize + 2.0)
                      : height - 2.0;
                  int pomMaxLines =
                      (availableForPom / (titleFontSize + 1.0)).floor();
                  if (pomMaxLines < 1) pomMaxLines = 1;

                  return Positioned(
                    top: top,
                    left: left,
                    width: width,
                    height: height,
                    child: AnimatedBuilder(
                      animation: _courseExpandAnim,
                      builder: (ctx, child) {
                        final delay = (pomIndex * 0.06).clamp(0.0, 0.5);
                        final t =
                            ((_courseExpandAnim.value - delay) / (1.0 - delay))
                                .clamp(0.0, 1.0);
                        final scale = 0.7 + 0.3 * t;
                        final opacity = t;
                        return Transform.scale(
                          scale: scale,
                          child: Opacity(
                            opacity: opacity,
                            child: child,
                          ),
                        );
                      },
                      child: GestureDetector(
                        onTap: () {
                          final renderBox = pomCardKey.currentContext
                              ?.findRenderObject() as RenderBox?;
                          if (renderBox != null) {
                            final rect = renderBox.localToGlobal(Offset.zero) &
                                renderBox.size;
                            Navigator.push(
                              context,
                              ContainerTransformRoute(
                                page: PomodoroDetailScreen(
                                    record: record, tags: _pomodoroTags),
                                sourceRect: rect,
                                sourceColor: pomColor,
                                sourceBorderRadius:
                                    const BorderRadius.all(Radius.circular(4)),
                              ),
                            );
                          } else {
                            Navigator.push(
                                context,
                                PageTransitions.slideHorizontal(
                                    PomodoroDetailScreen(
                                        record: record, tags: _pomodoroTags)));
                          }
                        },
                        child: Container(
                          key: pomCardKey,
                          alignment: Alignment.center,
                          clipBehavior: Clip.hardEdge,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 2, vertical: 1),
                          decoration: BoxDecoration(
                              color: pomColor,
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                  color: pomColor.withValues(alpha: 1.0),
                                  width: 0.5)),
                          child: height < 18
                              ? const Icon(Icons.local_fire_department,
                                  size: 8, color: Colors.white)
                              : SingleChildScrollView(
                                  physics: const NeverScrollableScrollPhysics(),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.center,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (height >= 38) ...[
                                        Icon(Icons.local_fire_department,
                                            size: titleFontSize,
                                            color: Colors.white),
                                        const SizedBox(height: 2),
                                      ],
                                      Text(
                                        pomTitle,
                                        style: TextStyle(
                                            color: Colors.white,
                                            fontSize: titleFontSize,
                                            fontWeight: FontWeight.bold,
                                            height: 1.0),
                                        maxLines: pomMaxLines,
                                        textAlign: TextAlign.center,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      if (height > 22)
                                        Text(
                                          '${end.difference(start).inMinutes}min',
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                              color: Colors.white
                                                  .withValues(alpha: 0.85),
                                              fontSize: timeFontSize,
                                              height: 1.0),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                    ],
                                  ),
                                ),
                        ),
                      ),
                    ),
                  );
                }));
          }
        }
      }
    }

    if (_activeDataViews.contains('deviceCalendar')) {
      final monday = _getMondayOfCurrentWeek();
      if (monday != null) {
        for (int weekday = 1; weekday <= 7; weekday++) {
          final dayStart = DateTime(
            monday.year,
            monday.month,
            monday.day + weekday - 1,
          );
          final dayEnd = dayStart.add(const Duration(days: 1));
          for (final event in _timedDeviceCalendarEventsPerDay[weekday] ??
              const <DeviceCalendarEvent>[]) {
            final sliceStart =
                event.start.isAfter(dayStart) ? event.start : dayStart;
            final sliceEnd = event.end.isBefore(dayEnd) ? event.end : dayEnd;
            if (!sliceEnd.isAfter(sliceStart)) continue;
            final startMinutes = sliceStart.hour * 60 + sliceStart.minute;
            final endMinutes = sliceEnd == dayEnd
                ? 24 * 60
                : sliceEnd.hour * 60 + sliceEnd.minute;
            if (endMinutes <= startHour * 60 || startMinutes >= endHour * 60) {
              continue;
            }
            final visibleStart =
                startMinutes.clamp(startHour * 60, endHour * 60).toInt();
            final visibleEnd =
                endMinutes.clamp(startHour * 60, endHour * 60).toInt();
            final top =
                _timeToY(visibleStart ~/ 60, visibleStart % 60, minuteHeight);
            var height =
                _timeToY(visibleEnd ~/ 60, visibleEnd % 60, minuteHeight) - top;
            if (height < 18.0) height = 18.0;
            final color = event.colorValue == null
                ? Theme.of(context).colorScheme.tertiary.withValues(alpha: 0.78)
                : Color(event.colorValue!).withValues(alpha: 0.78);

            eventsPerDay[weekday]!.add(_TimelineEvent(
              top: top,
              bottom: top + height,
              builder: (left, width) {
                final titleSize =
                    (height * 0.28 * (width / (cellWidth - 2)).clamp(0.4, 1.0))
                        .clamp(9.0, 10.5);
                return Positioned(
                  top: top,
                  left: left,
                  width: width,
                  height: height,
                  child: Container(
                    alignment: Alignment.center,
                    clipBehavior: Clip.hardEdge,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.45),
                        width: 0.5,
                      ),
                    ),
                    child: height < 28
                        ? const Icon(Icons.phone_android_rounded,
                            size: 9, color: Colors.white)
                        : Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              if (height >= 40)
                                const Icon(Icons.phone_android_rounded,
                                    size: 9, color: Colors.white),
                              if (height >= 40) const SizedBox(height: 2),
                              Text(
                                event.title,
                                maxLines: height >= 52 ? 2 : 1,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: titleSize,
                                  fontWeight: FontWeight.bold,
                                  height: 1.0,
                                ),
                              ),
                            ],
                          ),
                  ),
                );
              },
            ));
          }
        }
      }
    }

    if (_activeDataViews.contains('courses')) {
      for (var course in _weekCourses) {
        int sh = course.startTime ~/ 100;
        int sm = course.startTime % 100;
        int eh = course.endTime ~/ 100;
        int em = course.endTime % 100;

        double top = _timeToY(sh, sm, minuteHeight);
        double height = _timeToY(eh, em, minuteHeight) - top;

        Color bgColor = _getCourseColor(course.courseName);
        final cardKey = _getCourseCardKey(
            course.courseName, course.weekday, course.startTime);
        final courseIndex = _weekCourses.indexOf(course);

        eventsPerDay[course.weekday]!.add(_TimelineEvent(
            top: top,
            bottom: top + height,
            builder: (left, width) {
              final double fontScale =
                  (width / (cellWidth - 2)).clamp(0.4, 1.0);
              final double titleFontSize =
                  (height * 0.32 * fontScale).clamp(9.0, 10.5);
              final double subFontSize =
                  (height * 0.22 * fontScale).clamp(8.0, 9.0);
              final double titleLineHeight = titleFontSize * 1.15 + 1.0;
              const double paddingTotal = 2.0;
              const double gapHeight = 2.0;

              int courseMaxLines = 1;
              if (course.roomName.isNotEmpty && height > 30) {
                // 标题最多占一半高度，剩余给地点
                double halfHeight = (height - paddingTotal - gapHeight) / 2;
                courseMaxLines = (halfHeight / titleLineHeight).floor();
                if (courseMaxLines < 1) courseMaxLines = 1;
              } else {
                double availableForTitle = (height - paddingTotal) - 5.0;
                courseMaxLines = (availableForTitle / titleLineHeight).floor();
                if (courseMaxLines < 1) courseMaxLines = 1;
              }

              return Positioned(
                top: top + 1,
                left: left,
                width: width,
                height: height - 2,
                child: AnimatedBuilder(
                  animation: _courseExpandAnim,
                  builder: (ctx, child) {
                    final delay = (courseIndex * 0.06).clamp(0.0, 0.5);
                    final t =
                        ((_courseExpandAnim.value - delay) / (1.0 - delay))
                            .clamp(0.0, 1.0);
                    final scale = 0.7 + 0.3 * t;
                    final opacity = t;
                    return Transform.scale(
                      scale: scale,
                      child: Opacity(
                        opacity: opacity,
                        child: child,
                      ),
                    );
                  },
                  child: GestureDetector(
                    onTap: () {
                      final renderBox = cardKey.currentContext
                          ?.findRenderObject() as RenderBox?;
                      if (renderBox != null) {
                        final rect = renderBox.localToGlobal(Offset.zero) &
                            renderBox.size;
                        Navigator.push(
                          context,
                          ContainerTransformRoute(
                            page: CourseDetailScreen(course: course),
                            sourceRect: rect,
                            sourceColor: bgColor.withValues(alpha: 0.95),
                            sourceBorderRadius:
                                const BorderRadius.all(Radius.circular(4)),
                          ),
                        );
                      } else {
                        Navigator.push(
                            context,
                            PageTransitions.slideHorizontal(
                              CourseDetailScreen(course: course),
                            ));
                      }
                    },
                    child: Container(
                      key: cardKey,
                      alignment: Alignment.center,
                      clipBehavior: Clip.hardEdge,
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                          color: bgColor.withValues(alpha: 0.95),
                          borderRadius: BorderRadius.circular(4),
                          boxShadow: const [
                            BoxShadow(
                                color: Colors.black12,
                                blurRadius: 1,
                                offset: Offset(0, 1))
                          ]),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Text(
                            course.courseName,
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: titleFontSize,
                                fontWeight: FontWeight.bold,
                                height: 1.15),
                            maxLines: courseMaxLines,
                            textAlign: TextAlign.center,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (height > 30) ...[
                            const SizedBox(height: 2),
                            Flexible(
                              child: Text(
                                course.roomName,
                                style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.85),
                                    fontSize: subFontSize,
                                    height: 1.1),
                                overflow: TextOverflow.clip,
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }));
      }
    }

    for (int weekday = 1; weekday <= 7; weekday++) {
      List<_TimelineEvent> dayEvents = eventsPerDay[weekday]!;
      if (dayEvents.isEmpty) continue;

      dayEvents.sort((a, b) => a.top.compareTo(b.top));

      List<List<_TimelineEvent>> columns = [];
      List<_TimelineEvent> currentGroup = [];
      double groupBottom = -1;

      for (var event in dayEvents) {
        if (event.top >= groupBottom && currentGroup.isNotEmpty) {
          for (var e in currentGroup) {
            e.maxColumns = columns.length;
            e.colSpan = 1;
            for (int i = e.columnIndex + 1; i < columns.length; i++) {
              bool overlap = false;
              for (var other in columns[i]) {
                if (other.top < e.bottom && other.bottom > e.top) {
                  overlap = true;
                  break;
                }
              }
              if (overlap) break;
              e.colSpan++;
            }
          }
          columns.clear();
          currentGroup.clear();
          groupBottom = -1;
        }

        currentGroup.add(event);
        if (event.bottom > groupBottom) {
          groupBottom = event.bottom;
        }

        bool placed = false;
        for (int i = 0; i < columns.length; i++) {
          if (columns[i].last.bottom <= event.top) {
            columns[i].add(event);
            event.columnIndex = i;
            placed = true;
            break;
          }
        }
        if (!placed) {
          event.columnIndex = columns.length;
          columns.add([event]);
        }
      }

      for (var e in currentGroup) {
        e.maxColumns = columns.length;
        e.colSpan = 1;
        for (int i = e.columnIndex + 1; i < columns.length; i++) {
          bool overlap = false;
          for (var other in columns[i]) {
            if (other.top < e.bottom && other.bottom > e.top) {
              overlap = true;
              break;
            }
          }
          if (overlap) break;
          e.colSpan++;
        }
      }

      double leftOffset = timeColumnWidth + (weekday - 1) * cellWidth;
      for (var event in dayEvents) {
        double w = (cellWidth - 2) / event.maxColumns;
        double l = leftOffset + 1 + event.columnIndex * w;
        double width = w * event.colSpan;
        children.add(event.builder(l, width));
      }
    }

    DateTime now = DateTime.now();
    if (now.hour >= startHour && now.hour <= endHour) {
      if (_semesterMonday != null) {
        DateTime currentMonday =
            _semesterMonday!.add(Duration(days: (_currentWeek - 1) * 7));
        int diffDays = DateTime(now.year, now.month, now.day)
            .difference(currentMonday)
            .inDays;

        if (diffDays >= 0 && diffDays <= 6) {
          double nowY = _timeToY(now.hour, now.minute, minuteHeight);
          double lineLeft = timeColumnWidth + diffDays * cellWidth;

          children.add(Positioned(
            top: nowY,
            left: timeColumnWidth,
            width: cellWidth * 7,
            height: 1,
            child: AnimatedBuilder(
              animation: _pulseAnimation,
              builder: (context, child) {
                return Container(
                  color: Theme.of(context)
                      .colorScheme
                      .cdtFocus
                      .withValues(alpha: 0.3 + 0.2 * _pulseAnimation.value),
                );
              },
            ),
          ));
          children.add(Positioned(
            top: nowY - 1,
            left: lineLeft,
            width: cellWidth,
            height: 2,
            child: AnimatedBuilder(
              animation: _pulseAnimation,
              builder: (context, child) {
                final focusColor = Theme.of(context).colorScheme.cdtFocus;
                return Container(
                  decoration: BoxDecoration(
                    color: focusColor.withValues(
                        alpha: 0.7 + 0.3 * _pulseAnimation.value),
                    boxShadow: [
                      BoxShadow(
                        color: focusColor.withValues(
                            alpha: 0.4 * _pulseAnimation.value),
                        blurRadius: 6,
                        spreadRadius: 1,
                      )
                    ],
                  ),
                );
              },
            ),
          ));
        }
      }
    }

    return Stack(children: children);
  }
}
