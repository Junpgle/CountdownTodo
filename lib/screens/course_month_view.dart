import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models.dart';
import '../services/device_calendar_read_service.dart';
import '../services/pomodoro_service.dart';
import '../utils/app_color_utils.dart';
import '../utils/calendar_date_math.dart';

String? _courseMonthDateLocale;
final _courseMonthDateFormatters = <String, DateFormat>{};

DateFormat _courseMonthDateFormat(String pattern) {
  final locale = Intl.defaultLocale;
  if (_courseMonthDateLocale != locale) {
    _courseMonthDateLocale = locale;
    _courseMonthDateFormatters.clear();
  }
  return _courseMonthDateFormatters.putIfAbsent(
    pattern,
    () => DateFormat(pattern, locale),
  );
}

class _GanttTodoInterval {
  final TodoItem todo;
  final DateTime start;
  final DateTime end;

  const _GanttTodoInterval({
    required this.todo,
    required this.start,
    required this.end,
  });
}

class _CourseMonthDerivedKey {
  const _CourseMonthDerivedKey({
    required this.courseMap,
    required this.todoMap,
    required this.crossDayTodoMap,
    required this.logMap,
    required this.pomMap,
    required this.fixedScheduleMap,
    required this.deviceCalendarMap,
    required this.pomodoroTags,
    required this.allTodos,
    required this.startDateMicros,
    required this.showDays,
    required this.viewMode,
    required this.viewFlags,
    required this.timeZoneOffsetSeconds,
    required this.locale,
  });

  final Object courseMap;
  final Object todoMap;
  final Object crossDayTodoMap;
  final Object logMap;
  final Object pomMap;
  final Object fixedScheduleMap;
  final Object deviceCalendarMap;
  final Object pomodoroTags;
  final Object allTodos;
  final int startDateMicros;
  final int showDays;
  final int viewMode;
  final int viewFlags;
  final int timeZoneOffsetSeconds;
  final String? locale;

  bool matches(_CourseMonthDerivedKey other) =>
      identical(courseMap, other.courseMap) &&
      identical(todoMap, other.todoMap) &&
      identical(crossDayTodoMap, other.crossDayTodoMap) &&
      identical(logMap, other.logMap) &&
      identical(pomMap, other.pomMap) &&
      identical(fixedScheduleMap, other.fixedScheduleMap) &&
      identical(deviceCalendarMap, other.deviceCalendarMap) &&
      identical(pomodoroTags, other.pomodoroTags) &&
      identical(allTodos, other.allTodos) &&
      startDateMicros == other.startDateMicros &&
      showDays == other.showDays &&
      viewMode == other.viewMode &&
      viewFlags == other.viewFlags &&
      timeZoneOffsetSeconds == other.timeZoneOffsetSeconds &&
      locale == other.locale;
}

class _CourseMonthDerivedData {
  _CourseMonthDerivedData({
    required this.weeks,
    required this.weekDateKeys,
    required this.densityMap,
    required this.ganttTodosByWeek,
    required this.tagIndexByUuid,
  });

  final List<List<DateTime>> weeks;
  final List<List<String>> weekDateKeys;
  final Map<String, int> densityMap;
  final List<List<_GanttTodoInterval>> ganttTodosByWeek;
  final Map<String, int> tagIndexByUuid;
  final Map<int, List<List<Map<String, dynamic>>>> clusteredRowsByWeek = {};
}

typedef _CourseMonthDerivedBuilder = Widget Function(
  BuildContext context,
  _CourseMonthDerivedData data,
);

class _CourseMonthDerivedView extends StatefulWidget {
  const _CourseMonthDerivedView({
    required this.selectedMonth,
    required this.courseMap,
    required this.todoMap,
    required this.crossDayTodoMap,
    required this.logMap,
    required this.pomMap,
    required this.fixedScheduleMap,
    required this.deviceCalendarMap,
    required this.pomodoroTags,
    required this.activeDataViews,
    required this.allTodos,
    required this.viewMode,
    required this.currentWeekMonday,
    required this.builder,
  });

  final DateTime selectedMonth;
  final Map<String, List<CourseItem>> courseMap;
  final Map<String, List<TodoItem>> todoMap;
  final Map<String, List<TodoItem>> crossDayTodoMap;
  final Map<String, List<TimeLogItem>> logMap;
  final Map<String, List<PomodoroRecord>> pomMap;
  final Map<String, List<FixedScheduleItem>> fixedScheduleMap;
  final Map<String, List<DeviceCalendarEvent>> deviceCalendarMap;
  final List<PomodoroTag> pomodoroTags;
  final Set<String> activeDataViews;
  final List<TodoItem> allTodos;
  final int viewMode;
  final DateTime? currentWeekMonday;
  final _CourseMonthDerivedBuilder builder;

  @override
  State<_CourseMonthDerivedView> createState() =>
      _CourseMonthDerivedViewState();
}

class _CourseMonthDerivedViewState extends State<_CourseMonthDerivedView> {
  _CourseMonthDerivedKey? _cachedKey;
  _CourseMonthDerivedData? _cachedData;

  _CourseMonthDerivedData _dataForCurrentInputs() {
    final DateTime startDate;
    final int showDays;
    if (widget.viewMode == 2) {
      final firstDayOfMonth = DateTime(
        widget.selectedMonth.year,
        widget.selectedMonth.month,
        1,
      );
      final daysBefore = firstDayOfMonth.weekday - 1;
      startDate = CalendarDateMath.addDays(firstDayOfMonth, -daysBefore);
      showDays =
          daysBefore +
          DateTime(
            widget.selectedMonth.year,
            widget.selectedMonth.month + 1,
            0,
          ).day;
    } else {
      startDate = CalendarDateMath.dateOnly(
        widget.currentWeekMonday ?? widget.selectedMonth,
      );
      showDays = 14;
    }

    const viewFlagNames = [
      'courses',
      'todos',
      'timeLogs',
      'pomodoros',
      'fixedSchedules',
      'deviceCalendar',
      'hideCrossDay',
    ];
    var viewFlags = 0;
    for (var index = 0; index < viewFlagNames.length; index++) {
      if (widget.activeDataViews.contains(viewFlagNames[index])) {
        viewFlags |= 1 << index;
      }
    }
    final key = _CourseMonthDerivedKey(
      courseMap: widget.courseMap,
      todoMap: widget.todoMap,
      crossDayTodoMap: widget.crossDayTodoMap,
      logMap: widget.logMap,
      pomMap: widget.pomMap,
      fixedScheduleMap: widget.fixedScheduleMap,
      deviceCalendarMap: widget.deviceCalendarMap,
      pomodoroTags: widget.pomodoroTags,
      allTodos: widget.allTodos,
      startDateMicros: startDate.microsecondsSinceEpoch,
      showDays: showDays,
      viewMode: widget.viewMode,
      viewFlags: viewFlags,
      timeZoneOffsetSeconds: DateTime.now().timeZoneOffset.inSeconds,
      locale: Intl.defaultLocale,
    );
    final cachedKey = _cachedKey;
    final cachedData = _cachedData;
    if (cachedKey != null && cachedData != null && cachedKey.matches(key)) {
      return cachedData;
    }

    final dateKeyFormat = _courseMonthDateFormat('yyyy-MM-dd');
    final rowCount = (showDays / 7).ceil();
    final weeks = List.generate(
      rowCount,
      (weekIndex) => List.generate(
        7,
        (dayIndex) =>
            CalendarDateMath.addDays(startDate, weekIndex * 7 + dayIndex),
      ),
    );
    final weekDateKeys = [
      for (final week in weeks)
        [for (final day in week) dateKeyFormat.format(day)],
    ];

    final tagIndexByUuid = <String, int>{};
    if (widget.activeDataViews.contains('timeLogs') ||
        widget.activeDataViews.contains('pomodoros')) {
      for (var index = 0; index < widget.pomodoroTags.length; index++) {
        tagIndexByUuid.putIfAbsent(
          widget.pomodoroTags[index].uuid,
          () => index,
        );
      }
    }

    final densityMap = <String, int>{};
    void addDensity(String dateKey, int weight) {
      if (weight != 0) {
        densityMap[dateKey] = (densityMap[dateKey] ?? 0) + weight;
      }
    }

    final showCourses = widget.activeDataViews.contains('courses');
    final showTodos = widget.activeDataViews.contains('todos');
    final showTimeLogs = widget.activeDataViews.contains('timeLogs');
    final showPomodoros = widget.activeDataViews.contains('pomodoros');
    final showFixedSchedules = widget.activeDataViews.contains(
      'fixedSchedules',
    );
    final showDeviceCalendar = widget.activeDataViews.contains(
      'deviceCalendar',
    );
    for (final weekKeys in weekDateKeys) {
      for (final dateKey in weekKeys) {
        if (showCourses) {
          addDensity(dateKey, 3 * (widget.courseMap[dateKey]?.length ?? 0));
        }
        if (showTodos) {
          addDensity(dateKey, widget.todoMap[dateKey]?.length ?? 0);
          addDensity(dateKey, widget.crossDayTodoMap[dateKey]?.length ?? 0);
        }
        if (showTimeLogs) {
          addDensity(dateKey, 2 * (widget.logMap[dateKey]?.length ?? 0));
        }
        if (showPomodoros) {
          addDensity(dateKey, 2 * (widget.pomMap[dateKey]?.length ?? 0));
        }
        if (showFixedSchedules) {
          addDensity(
            dateKey,
            3 * (widget.fixedScheduleMap[dateKey]?.length ?? 0),
          );
        }
        if (showDeviceCalendar) {
          addDensity(
            dateKey,
            2 * (widget.deviceCalendarMap[dateKey]?.length ?? 0),
          );
        }
      }
    }

    final ganttTodos = <_GanttTodoInterval>[];
    if (showTodos) {
      final hideCrossDay = widget.activeDataViews.contains('hideCrossDay');
      for (final todo in widget.allTodos) {
        final dueDate = todo.dueDate;
        if (todo.isDeleted || dueDate == null) continue;

        final start = DateTime.fromMillisecondsSinceEpoch(
          todo.createdDate ?? todo.createdAt,
        ).toLocal();
        final isCrossDay = !DateUtils.isSameDay(start, dueDate);
        if (isCrossDay && hideCrossDay) continue;
        ganttTodos.add(
          _GanttTodoInterval(todo: todo, start: start, end: dueDate),
        );
      }
    }
    final ganttTodosByWeek = List<List<_GanttTodoInterval>>.generate(
      weeks.length,
      (_) => <_GanttTodoInterval>[],
    );
    if (ganttTodos.isNotEmpty) {
      final weekStarts = [for (final week in weeks) week.first];
      final weekEnds = [
        for (final week in weeks)
          CalendarDateMath.addDays(
            week.last,
            1,
          ).subtract(const Duration(microseconds: 1)),
      ];
      for (final interval in ganttTodos) {
        if (DateUtils.isSameDay(interval.start, interval.end)) continue;

        var low = 0;
        var high = weekEnds.length;
        while (low < high) {
          final middle = (low + high) ~/ 2;
          if (weekEnds[middle].isBefore(interval.start)) {
            low = middle + 1;
          } else {
            high = middle;
          }
        }
        for (
          var weekIndex = low;
          weekIndex < weekStarts.length &&
              !weekStarts[weekIndex].isAfter(interval.end);
          weekIndex++
        ) {
          if (interval.start.isAfter(weekEnds[weekIndex]) ||
              interval.end.isBefore(weekStarts[weekIndex])) {
            continue;
          }
          ganttTodosByWeek[weekIndex].add(interval);
        }
      }
    }

    final data = _CourseMonthDerivedData(
      weeks: weeks,
      weekDateKeys: weekDateKeys,
      densityMap: densityMap,
      ganttTodosByWeek: ganttTodosByWeek,
      tagIndexByUuid: tagIndexByUuid,
    );
    _cachedKey = key;
    _cachedData = data;
    return data;
  }

  @override
  Widget build(BuildContext context) =>
      widget.builder(context, _dataForCurrentInputs());
}

class CourseMonthView extends StatelessWidget {
  final DateTime selectedMonth;
  final Map<String, List<CourseItem>> courseMap;
  final Map<String, List<TodoItem>> todoMap;
  final Map<String, List<TodoItem>> crossDayTodoMap;
  final Map<String, List<TimeLogItem>> logMap;
  final Map<String, List<PomodoroRecord>> pomMap;
  final Map<String, List<FixedScheduleItem>> fixedScheduleMap;
  final Map<String, List<DeviceCalendarEvent>> deviceCalendarMap;
  final List<PomodoroTag> pomodoroTags;
  final Set<String> activeDataViews;
  final Function(DateTime) onMonthChanged;
  final Function(DateTime) onDayTapped;
  final List<TodoItem> allTodos;
  final int viewMode;
  final Function(TodoItem)? onGanttTodoTap;
  final DateTime? currentWeekMonday;
  final void Function(DeviceCalendarEvent event, GlobalKey? sourceKey)?
  onDeviceCalendarTap;
  final GlobalKey? Function(DeviceCalendarEvent event, String dateKey)?
  deviceCalendarCardKeyBuilder;

  const CourseMonthView({
    super.key,
    required this.selectedMonth,
    required this.courseMap,
    required this.todoMap,
    required this.crossDayTodoMap,
    required this.logMap,
    required this.pomMap,
    this.fixedScheduleMap = const {},
    this.deviceCalendarMap = const {},
    required this.pomodoroTags,
    required this.activeDataViews,
    required this.onMonthChanged,
    required this.onDayTapped,
    this.allTodos = const [],
    this.viewMode = 2,
    this.onGanttTodoTap,
    this.currentWeekMonday,
    this.onDeviceCalendarTap,
    this.deviceCalendarCardKeyBuilder,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    DateFormat? eventTimeFormat;
    DateFormat getEventTimeFormat() =>
        eventTimeFormat ??= _courseMonthDateFormat('HH:mm');

    return _CourseMonthDerivedView(
      selectedMonth: selectedMonth,
      courseMap: courseMap,
      todoMap: todoMap,
      crossDayTodoMap: crossDayTodoMap,
      logMap: logMap,
      pomMap: pomMap,
      fixedScheduleMap: fixedScheduleMap,
      deviceCalendarMap: deviceCalendarMap,
      pomodoroTags: pomodoroTags,
      activeDataViews: activeDataViews,
      allTodos: allTodos,
      viewMode: viewMode,
      currentWeekMonday: currentWeekMonday,
      builder: (context, data) => Column(
        children: [
          _buildWeekdayHeader(context),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final availableHeight = constraints.maxHeight;
                final rowHeight = (availableHeight / data.weeks.length).clamp(
                  110.0,
                  1000.0,
                );
                return ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: data.weeks.length,
                  itemBuilder: (context, weekIndex) {
                    return _buildWeekRow(
                      context,
                      data.weeks[weekIndex],
                      data.weekDateKeys[weekIndex],
                      data.ganttTodosByWeek[weekIndex],
                      data.densityMap,
                      isDark,
                      rowHeight,
                      getEventTimeFormat,
                      data.tagIndexByUuid,
                      data,
                      weekIndex,
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  List<List<Map<String, dynamic>>> _clusteredRowsForWeek(
    _CourseMonthDerivedData derivedData,
    int weekIndex,
    List<DateTime> weekDays,
    List<String> weekDateKeys,
    List<_GanttTodoInterval> weekGanttTodos,
    DateFormat Function() getEventTimeFormat,
    Map<String, int> tagIndexByUuid,
  ) {
    return derivedData.clusteredRowsByWeek.putIfAbsent(weekIndex, () {
      final weekBars = <Map<String, dynamic>>[];
      final weekStart = weekDays.first;
      final weekEnd = CalendarDateMath.addDays(
        weekDays.last,
        1,
      ).subtract(const Duration(microseconds: 1));

      // 1. 收集课程和单日待办 (按天遍历)
      for (var i = 0; i < weekDays.length; i++) {
        final dateKey = weekDateKeys[i];

        if (activeDataViews.contains('courses')) {
          for (final course in courseMap[dateKey] ?? const <CourseItem>[]) {
            weekBars.add({
              'course': course,
              'start': i,
              'end': i,
              'title': course.courseName,
            });
          }
        }

        if (activeDataViews.contains('fixedSchedules')) {
          for (final schedule
              in fixedScheduleMap[dateKey] ?? const <FixedScheduleItem>[]) {
            weekBars.add({
              'fixedSchedule': schedule,
              'start': i,
              'end': i,
              'title': schedule.title,
            });
          }
        }

        if (activeDataViews.contains('todos')) {
          for (final todo in todoMap[dateKey] ?? const <TodoItem>[]) {
            // 只添加非跨周任务，跨周任务统一在下面处理
            final start = DateTime.fromMillisecondsSinceEpoch(
              todo.createdDate ?? todo.createdAt,
            ).toLocal();
            final end = todo.dueDate ?? start;
            if (DateUtils.isSameDay(start, end)) {
              weekBars.add({
                'todo': todo,
                'start': i,
                'end': i,
                'title': todo.title,
              });
            }
          }
        }

        if (activeDataViews.contains('timeLogs')) {
          for (final log in logMap[dateKey] ?? const <TimeLogItem>[]) {
            final tag = _firstTag(log.tagUuids, tagIndexByUuid);
            weekBars.add({
              'timeLog': log,
              'start': i,
              'end': i,
              'title': log.title.isNotEmpty ? log.title : tag?.name ?? '时间日志',
              '_tagColor': tag == null ? null : _hexToColor(tag.color),
            });
          }
        }

        if (activeDataViews.contains('pomodoros')) {
          for (final pomodoro in pomMap[dateKey] ?? const <PomodoroRecord>[]) {
            final tag = _firstTag(pomodoro.tagUuids, tagIndexByUuid);
            weekBars.add({
              'pomodoro': pomodoro,
              'start': i,
              'end': i,
              'title': tag?.name ?? '番茄钟',
              '_tagColor': tag == null ? null : _hexToColor(tag.color),
            });
          }
        }

        if (activeDataViews.contains('deviceCalendar')) {
          for (final event
              in deviceCalendarMap[dateKey] ?? const <DeviceCalendarEvent>[]) {
            weekBars.add({
              'deviceCalendar': event,
              'start': i,
              'end': i,
              'title': _deviceCalendarTitle(event, getEventTimeFormat),
            });
          }
        }
      }

      // 2. 收集跨周/跨天待办 (区间判定)
      if (activeDataViews.contains('todos')) {
        for (final interval in weekGanttTodos) {
          final todo = interval.todo;
          final start = interval.start;
          final end = interval.end;

          // 计算在本周内的显示范围 (0-6)
          final startIndex = start.isBefore(weekStart)
              ? 0
              : CalendarDateMath.daysBetween(weekStart, start);
          final endIndex = end.isAfter(weekEnd)
              ? 6
              : CalendarDateMath.daysBetween(weekStart, end);

          weekBars.add({
            'todo': todo,
            'start': startIndex.clamp(0, 6),
            'end': endIndex.clamp(0, 6),
            'title': todo.title,
          });
        }
      }

      // 3. 排序 (未完成待办优先，然后课程、时间日志、番茄钟、已完成待办)
      final cacheSortPriorities = weekBars.length > 4;
      if (cacheSortPriorities) {
        for (final bar in weekBars) {
          bar['_sortPriority'] = _barPriority(bar);
        }
      }
      weekBars.sort((a, b) {
        final priorityA = cacheSortPriorities
            ? a['_sortPriority'] as int
            : _barPriority(a);
        final priorityB = cacheSortPriorities
            ? b['_sortPriority'] as int
            : _barPriority(b);
        if (priorityA != priorityB) return priorityA.compareTo(priorityB);

        final lengthA = (a['end'] as int) - (a['start'] as int);
        final lengthB = (b['end'] as int) - (b['start'] as int);
        if (lengthA != lengthB) return lengthB.compareTo(lengthA);

        return (a['start'] as int).compareTo(b['start'] as int);
      });

      return _clusterBars(weekBars);
    });
  }

  Widget _buildWeekRow(
    BuildContext context,
    List<DateTime> weekDays,
    List<String> weekDateKeys,
    List<_GanttTodoInterval> weekGanttTodos,
    Map<String, int> densityMap,
    bool isDark,
    double cellHeight,
    DateFormat Function() getEventTimeFormat,
    Map<String, int> tagIndexByUuid,
    _CourseMonthDerivedData derivedData,
    int weekIndex,
  ) {
    final clusteredRows = _clusteredRowsForWeek(
      derivedData,
      weekIndex,
      weekDays,
      weekDateKeys,
      weekGanttTodos,
      getEventTimeFormat,
      tagIndexByUuid,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        double cellWidth = constraints.maxWidth / 7;
        return Container(
          height: cellHeight,
          margin: const EdgeInsets.only(bottom: 2),
          child: Stack(
            children: [
              // 背景层：热力图
              Row(
                children: List.generate(weekDays.length, (dayIndex) {
                  final day = weekDays[dayIndex];
                  final dStr = weekDateKeys[dayIndex];
                  int count = densityMap[dStr] ?? 0;
                  Color? heatColor;
                  if (count > 0) {
                    double opacity = (count / 15).clamp(0.05, 0.4);
                    heatColor = Theme.of(context).colorScheme.primary
                        .withValues(alpha: opacity);
                  }

                  final List<CourseItem> dayCourses =
                      activeDataViews.contains('courses')
                      ? (courseMap[dStr] ?? [])
                      : [];
                  final List<TodoItem> dayTodos =
                      activeDataViews.contains('todos')
                      ? (todoMap[dStr] ?? [])
                      : [];
                  final List<TimeLogItem> dayLogs =
                      activeDataViews.contains('timeLogs')
                      ? (logMap[dStr] ?? [])
                      : [];
                  final List<PomodoroRecord> dayPoms =
                      activeDataViews.contains('pomodoros')
                      ? (pomMap[dStr] ?? [])
                      : [];
                  final List<FixedScheduleItem> dayFixedSchedules =
                      activeDataViews.contains('fixedSchedules')
                      ? (fixedScheduleMap[dStr] ?? [])
                      : [];

                  return Expanded(
                    child: RepaintBoundary(
                      child: GestureDetector(
                        onTap: () => onDayTapped(day),
                        child: _buildDetailedDayBackground(
                          context,
                          day,
                          heatColor,
                          isDark,
                          cellHeight,
                          dayCourses,
                          dayTodos,
                          dayLogs,
                          dayPoms,
                          dayFixedSchedules,
                        ),
                      ),
                    ),
                  );
                }),
              ),

              // 甘特图层
              Positioned(
                left: 0,
                right: 0,
                top: 25,
                bottom: viewMode == 2 ? 12 : 4,
                child: LayoutBuilder(
                  builder: (context, ganttConstraints) {
                    if (clusteredRows.isEmpty) return const SizedBox.shrink();

                    final bool isHalfMonthView = viewMode != 2;
                    final double rowSpacing = isHalfMonthView ? 4.0 : 2.0;
                    final double minRowHeight = 18.0;

                    final double calculatedRowHeight =
                        (ganttConstraints.maxHeight -
                            ((clusteredRows.length - 1) * rowSpacing)) /
                        clusteredRows.length;
                    final double rowHeight = calculatedRowHeight.clamp(
                      minRowHeight,
                      isHalfMonthView ? 40.0 : 24.0,
                    );
                    final double barHeight = (rowHeight - 4).clamp(14.0, 22.0);

                    return SingleChildScrollView(
                      physics: const BouncingScrollPhysics(),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.start,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: clusteredRows.map((rowGroup) {
                          return Container(
                            height: rowHeight,
                            margin: EdgeInsets.only(
                              bottom: rowGroup == clusteredRows.last
                                  ? 0
                                  : rowSpacing,
                            ),
                            child: Stack(
                              clipBehavior: Clip.none,
                              children: rowGroup.map((bar) {
                                final todo = bar['todo'] as TodoItem?;
                                final course = bar['course'] as CourseItem?;
                                final fixedSchedule =
                                    bar['fixedSchedule'] as FixedScheduleItem?;
                                final timeLog = bar['timeLog'] as TimeLogItem?;
                                final pomodoro =
                                    bar['pomodoro'] as PomodoroRecord?;
                                final deviceCalendarEvent =
                                    bar['deviceCalendar']
                                        as DeviceCalendarEvent?;
                                final int start = bar['start'];
                                final int end = bar['end'];
                                final String dateKey = weekDateKeys[start];
                                final sourceKey = deviceCalendarEvent == null
                                    ? null
                                    : deviceCalendarCardKeyBuilder?.call(
                                        deviceCalendarEvent,
                                        dateKey,
                                      );

                                final Color barColor = _barColor(
                                  bar,
                                  isDark,
                                  Theme.of(context).colorScheme.tertiary,
                                  Theme.of(context).colorScheme.primary,
                                );
                                final Color textColor = _barTextColor(
                                  bar,
                                  isDark,
                                );

                                return Positioned(
                                  left: start * cellWidth + 2,
                                  width: (end - start + 1) * cellWidth - 4,
                                  height: barHeight,
                                  child: GestureDetector(
                                    behavior: HitTestBehavior.opaque,
                                    onTap: () {
                                      if (deviceCalendarEvent != null) {
                                        onDeviceCalendarTap?.call(
                                          deviceCalendarEvent,
                                          sourceKey,
                                        );
                                      } else if (course != null) {
                                        onDayTapped(weekDays[start]);
                                      } else if (fixedSchedule != null) {
                                        onDayTapped(weekDays[start]);
                                      } else if (todo != null) {
                                        onGanttTodoTap?.call(todo);
                                      } else if (timeLog != null ||
                                          pomodoro != null) {
                                        onDayTapped(weekDays[start]);
                                      }
                                    },
                                    child: Container(
                                      key: sourceKey,
                                      decoration: BoxDecoration(
                                        color: barColor,
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 4,
                                      ),
                                      alignment: Alignment.centerLeft,
                                      child: deviceCalendarEvent == null
                                          ? Text(
                                              bar['title'] ?? '',
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                color: textColor,
                                                fontSize: (barHeight * 0.6)
                                                    .clamp(8.0, 11.0),
                                                fontWeight: FontWeight.w500,
                                                decoration:
                                                    (todo?.isDone ?? false)
                                                    ? TextDecoration.lineThrough
                                                    : null,
                                              ),
                                            )
                                          : Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(
                                                  Icons.phone_android_rounded,
                                                  size: 9,
                                                  color: textColor,
                                                ),
                                                const SizedBox(width: 2),
                                                Flexible(
                                                  child: Text(
                                                    bar['title'] ?? '',
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: TextStyle(
                                                      color: textColor,
                                                      fontSize:
                                                          (barHeight * 0.6)
                                                              .clamp(8.0, 11.0),
                                                      fontWeight:
                                                          FontWeight.w500,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                          );
                        }).toList(),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  List<List<Map<String, dynamic>>> _clusterBars(
    List<Map<String, dynamic>> bars,
  ) {
    final rows = <List<Map<String, dynamic>>>[];
    final occupiedDayMasks = <int>[];
    final rowsWithNonStandardIntervals = <bool>[];

    for (final bar in bars) {
      final start = bar['start'] as int;
      final end = bar['end'] as int;
      final hasStandardInterval = start >= 0 && start <= end && end <= 6;
      final barMask = hasStandardInterval
          ? ((1 << (end - start + 1)) - 1) << start
          : 0;
      var placed = false;

      for (var rowIndex = 0; rowIndex < rows.length; rowIndex++) {
        final row = rows[rowIndex];
        final overlap =
            hasStandardInterval && !rowsWithNonStandardIntervals[rowIndex]
            ? (occupiedDayMasks[rowIndex] & barMask) != 0
            : row.any(
                (existing) =>
                    !(end < existing['start'] || start > existing['end']),
              );
        if (!overlap) {
          row.add(bar);
          if (hasStandardInterval && !rowsWithNonStandardIntervals[rowIndex]) {
            occupiedDayMasks[rowIndex] |= barMask;
          } else {
            rowsWithNonStandardIntervals[rowIndex] = true;
          }
          placed = true;
          break;
        }
      }

      if (!placed) {
        rows.add([bar]);
        occupiedDayMasks.add(barMask);
        rowsWithNonStandardIntervals.add(!hasStandardInterval);
      }
    }
    return rows;
  }

  int _barPriority(Map<String, dynamic> bar) {
    final todo = bar['todo'] as TodoItem?;
    if (todo != null) return todo.isDone ? 4 : 0;
    if (bar['course'] != null) return 1;
    if (bar['fixedSchedule'] != null) return 1;
    if (bar['deviceCalendar'] != null) return 2;
    if (bar['timeLog'] != null) return 2;
    if (bar['pomodoro'] != null) return 3;
    return 5;
  }

  Color _barColor(
    Map<String, dynamic> bar,
    bool isDark, [
    Color? deviceCalendarFallback,
    Color? fixedScheduleFallback,
  ]) {
    final todo = bar['todo'] as TodoItem?;
    final log = bar['timeLog'] as TimeLogItem?;
    final pomodoro = bar['pomodoro'] as PomodoroRecord?;
    final deviceCalendarEvent = bar['deviceCalendar'] as DeviceCalendarEvent?;

    if (bar['course'] != null) {
      return Colors.blue.withValues(alpha: 0.85);
    }
    if (bar['fixedSchedule'] != null) {
      return (fixedScheduleFallback ?? deviceCalendarFallback ?? Colors.indigo)
          .withValues(alpha: 0.86);
    }
    if (todo != null) {
      final isTeam = todo.teamUuid != null;
      return todo.isDone
          ? (isDark ? Colors.white24 : Colors.black12)
          : (isTeam
                ? Colors.green.withValues(alpha: 0.7)
                : Colors.orange.withValues(alpha: 0.7));
    }
    if (log != null) {
      final tagColor = bar['_tagColor'] as Color?;
      return (tagColor ?? const Color(0xFF3B82F6)).withValues(alpha: 0.72);
    }
    if (pomodoro != null) {
      final tagColor = bar['_tagColor'] as Color?;
      return (tagColor ?? Colors.redAccent).withValues(alpha: 0.68);
    }
    if (deviceCalendarEvent != null) {
      final color = deviceCalendarEvent.colorValue == null
          ? (deviceCalendarFallback ?? Colors.teal)
          : Color(deviceCalendarEvent.colorValue!);
      return color.withValues(alpha: 0.82);
    }
    return isDark ? Colors.white24 : Colors.black12;
  }

  Color _barTextColor(Map<String, dynamic> bar, bool isDark) {
    final todo = bar['todo'] as TodoItem?;
    if (todo != null && todo.isDone) {
      return isDark ? Colors.white38 : Colors.black38;
    }
    return Colors.white;
  }

  String _deviceCalendarTitle(
    DeviceCalendarEvent event,
    DateFormat Function() getEventTimeFormat,
  ) {
    final timeLabel = event.allDay
        ? '全天'
        : getEventTimeFormat().format(event.start);
    return '$timeLabel · ${event.title}';
  }

  PomodoroTag? _firstTag(
    List<String> tagUuids,
    Map<String, int> tagIndexByUuid,
  ) {
    if (tagUuids.isEmpty) return null;
    var firstIndex = pomodoroTags.length;
    for (final uuid in tagUuids) {
      final index = tagIndexByUuid[uuid];
      if (index != null && index < firstIndex) firstIndex = index;
    }
    return firstIndex == pomodoroTags.length ? null : pomodoroTags[firstIndex];
  }

  Color _hexToColor(String hex) {
    return AppColorUtils.hexToColor(hex, fallback: const Color(0xFF607D8B));
  }

  Widget _buildDetailedDayBackground(
    BuildContext context,
    DateTime day,
    Color? heatColor,
    bool isDark,
    double height,
    List<CourseItem> courses,
    List<TodoItem> todos,
    List<TimeLogItem> logs,
    List<PomodoroRecord> poms,
    List<FixedScheduleItem> fixedSchedules,
  ) {
    bool isToday = DateUtils.isSameDay(day, DateTime.now());
    bool isCurrentMonth = day.month == selectedMonth.month;

    // Small dots and the detailed timeline honor the cross-day visibility setting.
    final showDetailedTodos = viewMode == 1 && height > 150;
    final showTodoMiniDot = viewMode == 2;
    final filteredTodos = showDetailedTodos ? todos : const <TodoItem>[];
    final hasVisibleTodos = showTodoMiniDot && todos.isNotEmpty;

    return Container(
      decoration: BoxDecoration(
        color:
            heatColor ??
            (isCurrentMonth
                ? (isDark ? Colors.white.withValues(alpha: 0.02) : Colors.white)
                : Colors.transparent),
        border: Border.all(
          color: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.03),
          width: 0.5,
        ),
      ),
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.all(4.0),
            child: Text(
              '${day.day}',
              style: TextStyle(
                fontSize: 10.5,
                color: isToday
                    ? Colors.redAccent
                    : (isCurrentMonth
                          ? (isDark ? Colors.white70 : Colors.black87)
                          : Colors.grey.withValues(alpha: 0.3)),
                fontWeight: isToday ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
          if (viewMode == 1 && height > 150)
            Positioned(
              top: 25,
              left: 4,
              right: 4,
              bottom: 4,
              child: Stack(
                children: [
                  Column(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: List.generate(
                      4,
                      (i) => Container(
                        height: 0.5,
                        width: double.infinity,
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.05)
                            : Colors.black.withValues(alpha: 0.05),
                      ),
                    ),
                  ),
                  ...courses.map(
                    (c) => _buildVerticalBar(
                      c.startTime,
                      c.endTime,
                      Theme.of(context).colorScheme.primary
                          .withValues(alpha: 0.6),
                      height,
                    ),
                  ),
                  ...filteredTodos
                      .where((t) => t.dueDate != null)
                      .map(
                        (t) => _buildTimeDot(
                          t.dueDate!.hour * 100 + t.dueDate!.minute,
                          Colors.amber,
                          height,
                        ),
                      ),
                  ...logs.map((l) {
                    DateTime s = DateTime.fromMillisecondsSinceEpoch(
                      l.startTime,
                    ).toLocal();
                    DateTime e = DateTime.fromMillisecondsSinceEpoch(l.endTime)
                        .toLocal();
                    return _buildVerticalBar(
                      s.hour * 100 + s.minute,
                      e.hour * 100 + e.minute,
                      Theme.of(context).colorScheme.secondary
                          .withValues(alpha: 0.4),
                      height,
                    );
                  }),
                  ...poms.map((p) {
                    final DateTime s = DateTime.fromMillisecondsSinceEpoch(
                      p.startTime,
                    ).toLocal();
                    final int endMs =
                        p.endTime ?? (p.startTime + p.effectiveDuration * 1000);
                    final DateTime e = DateTime.fromMillisecondsSinceEpoch(
                      endMs,
                    ).toLocal();
                    return _buildVerticalBar(
                      s.hour * 100 + s.minute,
                      e.hour * 100 + e.minute,
                      Colors.redAccent.withValues(alpha: 0.4),
                      height,
                    );
                  }),
                  ...fixedSchedules.where((item) => item.startTime != null).map(
                    (item) {
                      final start = DateTime.fromMillisecondsSinceEpoch(
                        item.startTime!,
                      );
                      final end = item.endTime == null
                          ? start.add(const Duration(hours: 1))
                          : DateTime.fromMillisecondsSinceEpoch(item.endTime!);
                      final startTime = start.hour * 100 + start.minute;
                      final endTime = end.day == start.day
                          ? end.hour * 100 + end.minute
                          : 2400;
                      return _buildVerticalBar(
                        startTime,
                        endTime,
                        Theme.of(context).colorScheme.primary
                            .withValues(alpha: 0.55),
                        height,
                      );
                    },
                  ),
                ],
              ),
            ),
          if (viewMode == 2)
            Positioned(
              bottom: 4,
              left: 4,
              right: 4,
              child: Wrap(
                spacing: 2,
                children: [
                  if (courses.isNotEmpty)
                    _buildMiniDot(Theme.of(context).colorScheme.primary),
                  if (hasVisibleTodos) _buildMiniDot(Colors.amber),
                  if (logs.isNotEmpty)
                    _buildMiniDot(Theme.of(context).colorScheme.secondary),
                  if (poms.isNotEmpty) _buildMiniDot(Colors.redAccent),
                  if (fixedSchedules.isNotEmpty)
                    _buildMiniDot(Theme.of(context).colorScheme.primary),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildVerticalBar(int start, int end, Color color, double height) {
    double startY = _calculateTimeY(start, 600, 2400);
    double endY = _calculateTimeY(end, 600, 2400);
    return Positioned(
      top: startY * (height - 30),
      height: (endY - startY).clamp(0.02, 1.0) * (height - 30),
      left: 0,
      width: 3,
      child: Container(
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(1),
        ),
      ),
    );
  }

  Widget _buildTimeDot(int time, Color color, double height) {
    double y = _calculateTimeY(time, 600, 2400);
    return Positioned(
      top: y * (height - 30),
      left: 4,
      width: 4,
      height: 4,
      child: Container(
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
    );
  }

  Widget _buildMiniDot(Color color) => Container(
    width: 4,
    height: 4,
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.6),
      shape: BoxShape.circle,
    ),
  );

  double _calculateTimeY(int time, int start, int end) {
    int minutes = (time ~/ 100) * 60 + (time % 100);
    return ((minutes - (start ~/ 100 * 60)) /
            ((end ~/ 100 * 60) - (start ~/ 100 * 60)))
        .clamp(0.0, 1.0);
  }

  Widget _buildWeekdayHeader(BuildContext context) {
    final weekdays = ['一', '二', '三', '四', '五', '六', '日'];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: weekdays
            .map(
              (day) => Expanded(
                child: Center(
                  child: Text(
                    day,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Colors.grey,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            )
            .toList(),
      ),
    );
  }
}
