part of 'course_screens.dart';

// ignore_for_file: unused_element, unused_element_parameter, annotate_overrides

mixin _WeeklyCourseGridHeader on _WeeklyCourseScreenStateBase {
  void _showAllDayTodos(
    BuildContext context,
    List<TodoItem> todos,
    String dateStr,
  ) {
    showAppModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        final colorScheme = Theme.of(ctx).colorScheme;
        return SafeArea(
          child: Container(
            padding: const EdgeInsets.all(16),
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(ctx).height * 0.5,
            ),
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
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  "$dateStr 全天/跨天待办",
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: ListView.builder(
                    findChildIndexCallback: (Key key) {
                      if (key is ValueKey<String>) {
                        final id = key.value;
                        final index = todos.indexWhere((t) => t.id == id);
                        return index != -1 ? index : null;
                      }
                      return null;
                    },
                    itemCount: todos.length,
                    itemBuilder: (context, index) {
                      final todo = todos[index];
                      return ListTile(
                        key: ValueKey<String>(todo.id),
                        leading: Icon(
                          todo.isDone ? Icons.check_circle : Icons.task_alt,
                          color: todo.isDone
                              ? colorScheme.cdtSuccess
                              : colorScheme.cdtWarning,
                        ),
                        title: Text(
                          todo.title,
                          style: TextStyle(
                            decoration: todo.isDone
                                ? TextDecoration.lineThrough
                                : null,
                          ),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (todo.teamUuid != null)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 2),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.group,
                                      size: 12,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .primary,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      "${todo.teamName ?? '团队'} · ${todo.creatorName ?? '成员'}",
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Theme.of(context)
                                            .colorScheme
                                            .primary,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            Text(
                              "开始: ${_cachedDateFormat('MM-dd HH:mm').format(DateTime.fromMillisecondsSinceEpoch(todo.createdDate ?? todo.createdAt, isUtc: true).toLocal())}\n截止: ${todo.dueDate != null ? _cachedDateFormat('MM-dd HH:mm').format(todo.dueDate!) : '无'}",
                            ),
                          ],
                        ),
                        onTap: () {
                          Navigator.pop(ctx);
                          Navigator.push(
                            context,
                            PageTransitions.slideHorizontal(
                              TodoDetailScreen(
                                todo: todo,
                                onCreateRelatedTodo: widget.onCreateRelatedTodo,
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showAllDayDeviceCalendarEvents(
    BuildContext context,
    List<DeviceCalendarEvent> events,
    String dateStr, {
    GlobalKey? sourceKey,
    Color? sourceColor,
  }) {
    showAppModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$dateStr 手机日历全天日程',
                style: Theme.of(ctx).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              ...events.map(
                (event) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    Icons.phone_android_rounded,
                    color: event.colorValue == null
                        ? Theme.of(ctx).colorScheme.tertiary
                        : Color(event.colorValue!),
                  ),
                  title: Text(event.title),
                  subtitle: Text(
                    event.location?.isNotEmpty == true
                        ? event.location!
                        : '全天 · 手机日历（只读）',
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    _showDeviceCalendarEventDetail(
                      context,
                      event,
                      sourceKey: sourceKey,
                      sourceColor: sourceColor,
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showDeviceCalendarEventDetail(
    BuildContext context,
    DeviceCalendarEvent event, {
    GlobalKey? sourceKey,
    Color? sourceColor,
  }) {
    final color =
        sourceColor ??
        (event.colorValue == null
            ? Theme.of(context).colorScheme.tertiary
            : Color(event.colorValue!));
    if (sourceKey != null) {
      PageTransitions.pushFromRect(
        context: context,
        page: DeviceCalendarEventDetailScreen(event: event),
        sourceKey: sourceKey,
        sourceColor: color,
        sourceBorderRadius: BorderRadius.circular(4),
        placeholderIcon: Icons.phone_android_rounded,
      );
      return;
    }
    Navigator.of(context).push(
      PageTransitions.slideHorizontal(
        DeviceCalendarEventDetailScreen(event: event),
      ),
    );
  }

  Widget _buildAllDayHeaderRow(DateTime? monday) {
    if (monday == null) {
      return const SizedBox.shrink();
    }

    final dateKeyFormat = _cachedDateFormat('yyyy-MM-dd');
    final String todayKey = dateKeyFormat.format(DateTime.now());
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final showTodos = _activeDataViews.contains('todos');
    final showFixedSchedules = _activeDataViews.contains('fixedSchedules');
    final showDeviceCalendar = _activeDataViews.contains('deviceCalendar');
    bool hasAnyAllDay =
        (showTodos &&
            _allDayTodosPerDay.values.any((list) => list.isNotEmpty)) ||
        (showFixedSchedules &&
            _fixedSchedulesPerDay.values.any(
              (list) => list.any((item) => item.startTime == null),
            )) ||
        (showDeviceCalendar &&
            _allDayDeviceCalendarEventsPerDay.values.any(
              (list) => list.isNotEmpty,
            ));
    if (!hasAnyAllDay) return const SizedBox.shrink();

    return Container(
      padding: EdgeInsets.only(left: timeColumnWidth, bottom: 2),
      color: Theme.of(context).colorScheme.surface,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: List.generate(7, (index) {
          int weekday = index + 1;
          List<TodoItem> dayTodos = showTodos
              ? (_allDayTodosPerDay[weekday] ?? [])
              : [];
          List<FixedScheduleItem> fixedSchedules = showFixedSchedules
              ? (_fixedSchedulesPerDay[weekday] ?? [])
                    .where((item) => item.startTime == null)
                    .toList()
              : [];
          List<DeviceCalendarEvent> deviceEvents = showDeviceCalendar
              ? (_allDayDeviceCalendarEventsPerDay[weekday] ?? [])
              : [];

          final currentDay = CalendarDateMath.addDays(monday, index);
          final dayKey = dateKeyFormat.format(currentDay);
          final bool isToday = dayKey == todayKey;
          final colorScheme = Theme.of(context).colorScheme;

          if (dayTodos.isEmpty &&
              fixedSchedules.isEmpty &&
              deviceEvents.isEmpty) {
            return Expanded(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 1.0),
                decoration: isToday
                    ? BoxDecoration(
                        color: colorScheme.primary.withValues(
                          alpha: isDark ? 0.06 : 0.035,
                        ),
                        borderRadius: BorderRadius.circular(4),
                      )
                    : null,
                height: 22,
              ),
            );
          }

          final labels = <String>[];
          if (deviceEvents.isNotEmpty) {
            labels.add(
              deviceEvents.length == 1
                  ? deviceEvents.first.title
                  : '${deviceEvents.length}项手机日历',
            );
          }
          if (fixedSchedules.isNotEmpty) {
            String scheduleLabel;
            if (fixedSchedules.length == 1) {
              final first = fixedSchedules.first;
              final loc = first.location?.trim();
              scheduleLabel = (loc != null && loc.isNotEmpty)
                  ? '${first.title} ($loc)'
                  : first.title;
            } else {
              scheduleLabel = '${fixedSchedules.length}项固定日程';
            }
            labels.add(scheduleLabel);
          }
          if (dayTodos.isNotEmpty) {
            labels.add(
              dayTodos.length == 1
                  ? dayTodos.first.title
                  : "${dayTodos.length}项全天待办",
            );
          }
          final text = labels.join(' · ');
          bool allDone = dayTodos.every((t) => t.isDone);
          final todoColor = deviceEvents.isNotEmpty
              ? (deviceEvents.first.colorValue == null
                    ? colorScheme.tertiary
                    : Color(deviceEvents.first.colorValue!))
              : (fixedSchedules.isNotEmpty
                    ? colorScheme.primary
                    : (allDone
                          ? colorScheme.cdtSuccess
                          : colorScheme.cdtWarning));
          final onTodoColor = deviceEvents.isNotEmpty
              ? _colorForAllDayDeviceEvent(context, deviceEvents.first)
              : (fixedSchedules.isNotEmpty
                    ? colorScheme.onPrimary
                    : (allDone
                          ? colorScheme.onSurface.withValues(alpha: 0.75)
                          : Colors.white));
          final allDaySourceKey = deviceEvents.isEmpty
              ? null
              : _getDeviceCalendarCardKey(
                  deviceEvents.first.id,
                  dayKey,
                  surface: 'week-all-day',
                );

          return Expanded(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 1.0),
              decoration: isToday
                  ? BoxDecoration(
                      color: colorScheme.primary.withValues(
                        alpha: isDark ? 0.06 : 0.035,
                      ),
                      borderRadius: BorderRadius.circular(4),
                    )
                  : null,
              child: GestureDetector(
                onTap: () {
                  String dateStr = _cachedDateFormat('MM-dd')
                      .format(currentDay);
                  if (fixedSchedules.isNotEmpty || dayTodos.isNotEmpty) {
                    _showDayDetailSheet(currentDay);
                  } else if (deviceEvents.isNotEmpty) {
                    if (deviceEvents.length == 1) {
                      _showDeviceCalendarEventDetail(
                        context,
                        deviceEvents.first,
                        sourceKey: allDaySourceKey,
                        sourceColor: todoColor.withValues(alpha: 0.92),
                      );
                    } else {
                      _showAllDayDeviceCalendarEvents(
                        context,
                        deviceEvents,
                        dateStr,
                        sourceKey: allDaySourceKey,
                        sourceColor: todoColor.withValues(alpha: 0.92),
                      );
                    }
                  } else {
                    _showAllDayTodos(context, dayTodos, dateStr);
                  }
                },
                child: Container(
                  key: allDaySourceKey,
                  margin: const EdgeInsets.symmetric(
                    horizontal: 1,
                    vertical: 1,
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 2,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: todoColor.withValues(
                      alpha: deviceEvents.isNotEmpty
                          ? 0.92
                          : (fixedSchedules.isNotEmpty
                                ? 0.85
                                : (allDone ? 0.28 : 0.85)),
                    ),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (deviceEvents.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(right: 2),
                          child: Icon(
                            Icons.phone_android_rounded,
                            size: 10,
                            color: onTodoColor,
                          ),
                        )
                      else if (fixedSchedules.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(right: 2),
                          child: Icon(
                            Icons.event_available,
                            size: 10,
                            color: onTodoColor,
                          ),
                        )
                      else if (dayTodos.any((t) => t.teamUuid != null))
                        Padding(
                          padding: const EdgeInsets.only(right: 2),
                          child: Icon(
                            Icons.group,
                            size: 10,
                            color: onTodoColor,
                          ),
                        ),
                      Flexible(
                        child: Text(
                          text,
                          style: TextStyle(
                            fontSize: 11,
                            color: onTodoColor,
                            decoration: allDone
                                ? TextDecoration.lineThrough
                                : null,
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
            ),
          );
        }),
      ),
    );
  }

  Color _colorForAllDayDeviceEvent(
    BuildContext context,
    DeviceCalendarEvent event,
  ) {
    final background = event.colorValue == null
        ? Theme.of(context).colorScheme.tertiary
        : Color(event.colorValue!);
    return ThemeData.estimateBrightnessForColor(background) == Brightness.dark
        ? Colors.white
        : Colors.black87;
  }

  Widget _buildHeader(DateTime? monday) {
    DateTime now = DateTime.now();
    final dateKeyFormat = _cachedDateFormat('yyyy-MM-dd');
    final headerDateFormat = _cachedDateFormat('M/dd');
    String todayStr = dateKeyFormat.format(now);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    bool isDark = theme.brightness == Brightness.dark;

    return Container(
      color: colorScheme.surface,
      padding: EdgeInsets.only(left: timeColumnWidth, top: 4, bottom: 4),
      child: Row(
        children: List.generate(7, (index) {
          DateTime? currentDate;
          String dateStr = '';
          bool isToday = false;

          if (monday != null) {
            currentDate = CalendarDateMath.addDays(monday, index);
            dateStr = headerDateFormat.format(currentDate);
            isToday = dateKeyFormat.format(currentDate) == todayStr;
          }

          const weekdays = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
          final weekdayLabel = weekdays[index];

          return Expanded(
            child: Semantics(
              label: isToday
                  ? '今天，$weekdayLabel $dateStr'
                  : '$weekdayLabel $dateStr',
              child: Container(
                margin: const EdgeInsets.symmetric(
                  horizontal: 1.5,
                  vertical: 1.0,
                ),
                padding: const EdgeInsets.symmetric(
                  vertical: 3.0,
                  horizontal: 1.0,
                ),
                decoration: isToday
                    ? BoxDecoration(
                        color: colorScheme.primaryContainer.withValues(
                          alpha: isDark ? 0.42 : 0.60,
                        ),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: colorScheme.primary.withValues(alpha: 0.45),
                          width: 1,
                        ),
                      )
                    : null,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            weekdayLabel,
                            style: TextStyle(
                              color: isToday
                                  ? colorScheme.primary
                                  : (isDark ? Colors.white70 : Colors.black87),
                              fontWeight: isToday
                                  ? FontWeight.bold
                                  : FontWeight.w500,
                              fontSize: 12.5,
                            ),
                          ),
                          if (isToday) ...[
                            const SizedBox(width: 2),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 3.5,
                                vertical: 0.5,
                              ),
                              decoration: BoxDecoration(
                                color: colorScheme.primary,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                '今',
                                style: TextStyle(
                                  color: colorScheme.onPrimary,
                                  fontSize: 8.5,
                                  fontWeight: FontWeight.bold,
                                  height: 1.1,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 2),
                    if (dateStr.isNotEmpty)
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: isToday
                            ? Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 5,
                                  vertical: 1,
                                ),
                                decoration: BoxDecoration(
                                  color: colorScheme.primary,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  dateStr,
                                  style: TextStyle(
                                    color: colorScheme.onPrimary,
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.bold,
                                    height: 1.1,
                                  ),
                                ),
                              )
                            : Text(
                                dateStr,
                                style: TextStyle(
                                  color: colorScheme.onSurfaceVariant,
                                  fontSize: 11,
                                ),
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

  void _showAggregatedTimelineSheet(
    BuildContext context,
    int weekday,
    List<Object> items,
  ) {
    final monday = _getMondayOfCurrentWeek();
    final day = monday != null
        ? CalendarDateMath.addDays(monday, weekday - 1)
        : DateTime.now();
    final dateStr = _cachedDateFormat('M月d日').format(day);
    final weekdayStr = const [
      '周一',
      '周二',
      '周三',
      '周四',
      '周五',
      '周六',
      '周日',
    ][(weekday - 1).clamp(0, 6)];
    final sourceDate = _cachedDateFormat('yyyy-MM-dd').format(day);

    showAppModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        final colorScheme = Theme.of(ctx).colorScheme;
        return SafeArea(
          child: Container(
            padding: const EdgeInsets.all(16),
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(ctx).height * 0.55,
            ),
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
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  '$dateStr $weekdayStr · 重叠日程 (${items.length}项)',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    findItemIndexCallback: (Key key) {
                      if (key is ValueKey<String> &&
                          key.value.startsWith('week_agg_modal_')) {
                        final idx = int.tryParse(
                          key.value.substring('week_agg_modal_'.length),
                        );
                        if (idx != null && idx >= 0 && idx < items.length) {
                          return idx;
                        }
                      }
                      return null;
                    },
                    itemCount: items.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (itemCtx, index) {
                      return RepaintBoundary(
                        key: ValueKey<String>('week_agg_modal_$index'),
                        child: _buildDetailSidebarItem(
                          itemCtx,
                          items[index],
                          sourceDate,
                          'week_agg_modal_$index',
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
