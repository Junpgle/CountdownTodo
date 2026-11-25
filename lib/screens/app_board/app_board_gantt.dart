part of '../app_board_screen.dart';

class _GanttTaskLayoutInput {
  const _GanttTaskLayoutInput({
    required this.todo,
    required this.isDone,
    required this.createdAt,
    required this.dueDateMicros,
    required this.dueDateIsUtc,
    required this.dueDateYear,
    required this.dueDateMonth,
    required this.dueDateDay,
    required this.dueDateHour,
    required this.dueDateMinute,
    required this.dueDateOffsetSeconds,
  });

  factory _GanttTaskLayoutInput.from(TodoItem todo) {
    final dueDate = todo.dueDate;
    return _GanttTaskLayoutInput(
      todo: todo,
      isDone: todo.isDone,
      createdAt: todo.createdAt,
      dueDateMicros: dueDate?.microsecondsSinceEpoch,
      dueDateIsUtc: dueDate?.isUtc,
      dueDateYear: dueDate?.year,
      dueDateMonth: dueDate?.month,
      dueDateDay: dueDate?.day,
      dueDateHour: dueDate?.hour,
      dueDateMinute: dueDate?.minute,
      dueDateOffsetSeconds: dueDate?.timeZoneOffset.inSeconds,
    );
  }

  final TodoItem todo;
  final bool isDone;
  final int createdAt;
  final int? dueDateMicros;
  final bool? dueDateIsUtc;
  final int? dueDateYear;
  final int? dueDateMonth;
  final int? dueDateDay;
  final int? dueDateHour;
  final int? dueDateMinute;
  final int? dueDateOffsetSeconds;

  bool matches(TodoItem candidate) {
    final dueDate = candidate.dueDate;
    return identical(todo, candidate) &&
        isDone == candidate.isDone &&
        createdAt == candidate.createdAt &&
        dueDateMicros == dueDate?.microsecondsSinceEpoch &&
        dueDateIsUtc == dueDate?.isUtc &&
        dueDateYear == dueDate?.year &&
        dueDateMonth == dueDate?.month &&
        dueDateDay == dueDate?.day &&
        dueDateHour == dueDate?.hour &&
        dueDateMinute == dueDate?.minute &&
        dueDateOffsetSeconds == dueDate?.timeZoneOffset.inSeconds;
  }
}

class _GanttLayout {
  const _GanttLayout({
    required this.minDate,
    required this.totalDays,
    required this.startDates,
    required this.activeRows,
    required this.completedRows,
  });

  final DateTime minDate;
  final int totalDays;
  final Map<TodoItem, DateTime> startDates;
  final List<List<TodoItem>> activeRows;
  final List<List<TodoItem>> completedRows;
}

class _GanttDayGridPainter extends CustomPainter {
  const _GanttDayGridPainter({
    required this.dayCount,
    required this.dayWidth,
    required this.color,
  });

  final int dayCount;
  final double dayWidth;
  final Color color;

  static final Paint _paint = Paint()
    ..strokeWidth = 1
    ..style = PaintingStyle.stroke;
  static final Path _gridPath = Path();

  @override
  void paint(Canvas canvas, Size size) {
    if (dayCount <= 0 || size.height <= 0) return;

    _gridPath.reset();
    for (var day = 1; day <= dayCount; day++) {
      final x = day * dayWidth - 0.5;
      _gridPath
        ..moveTo(x, 0)
        ..lineTo(x, size.height);
    }
    _paint.color = color;
    canvas.drawPath(_gridPath, _paint);
  }

  @override
  bool shouldRepaint(covariant _GanttDayGridPainter oldDelegate) =>
      dayCount != oldDelegate.dayCount ||
      dayWidth != oldDelegate.dayWidth ||
      color != oldDelegate.color;
}

class GanttChart extends StatefulWidget {
  final List<TodoItem> todos;
  final double dayWidth;
  final Function(TodoItem) onTaskClick;

  const GanttChart({
    super.key,
    required this.todos,
    required this.dayWidth,
    required this.onTaskClick,
  });

  @override
  State<GanttChart> createState() => _GanttChartState();
}

class _GanttChartState extends State<GanttChart> {
  final ScrollController _scrollController = ScrollController();
  final ValueNotifier<double> _horizontalOffset = ValueNotifier<double>(0);
  bool _hasScrolledToToday = false;
  List<TodoItem>? _layoutTodoSource;
  List<_GanttTaskLayoutInput>? _layoutInputs;
  DateTime? _layoutToday;
  int? _layoutTimeZoneOffsetSeconds;
  _GanttLayout? _cachedLayout;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_handleHorizontalScroll);
  }

  @override
  void didUpdateWidget(covariant GanttChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.dayWidth != widget.dayWidth ||
        oldWidget.todos.length != widget.todos.length) {
      _hasScrolledToToday = false;
    }
  }

  @override
  void dispose() {
    _scrollController.removeListener(_handleHorizontalScroll);
    _scrollController.dispose();
    _horizontalOffset.dispose();
    super.dispose();
  }

  void _handleHorizontalScroll() {
    if (!mounted) return;
    _horizontalOffset.value = _scrollController.offset;
  }

  void _scheduleScrollToToday(DateTime minDate, double dayWidth) {
    if (_hasScrolledToToday) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      if (!_scrollController.position.hasContentDimensions) return;

      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final todayOffset = CalendarDateMath.dayOffset(minDate, today) * dayWidth;
      final viewportWidth = _scrollController.position.viewportDimension;
      final targetOffset = todayOffset - (viewportWidth / 2) + (dayWidth / 2);
      final clampedOffset = targetOffset
          .clamp(0.0, _scrollController.position.maxScrollExtent)
          .toDouble();

      _scrollController.jumpTo(clampedOffset);
      _hasScrolledToToday = true;
    });
  }

  List<List<TodoItem>> _packTasks(
    List<TodoItem> tasks,
    Map<TodoItem, DateTime> startDates,
    DateTime minDate,
    DateTime maxDate,
  ) {
    if (tasks.isEmpty) return [];

    final sorted = List<TodoItem>.from(tasks)
      ..sort((a, b) {
        return startDates[a]!.compareTo(startDates[b]!);
      });

    final List<List<TodoItem>> rows = [];
    final rowHasValidIntervals = <bool>[];
    const overlapPaddingMicroseconds = 2 * 60 * 60 * 1000000;

    bool intervalsOverlap(
      TodoItem existingTask,
      int taskStartMicroseconds,
      int taskEndMicroseconds,
    ) {
      final existingStartMicroseconds =
          startDates[existingTask]!.microsecondsSinceEpoch;
      final existingEndMicroseconds =
          existingTask.dueDate!.microsecondsSinceEpoch;
      return taskEndMicroseconds >
              existingStartMicroseconds - overlapPaddingMicroseconds &&
          taskStartMicroseconds <
              existingEndMicroseconds + overlapPaddingMicroseconds;
    }

    for (final task in sorted) {
      final start = startDates[task]!;
      final end = task.dueDate!;
      if (end.isBefore(minDate) || start.isAfter(maxDate)) continue;
      final startMicroseconds = start.microsecondsSinceEpoch;
      final endMicroseconds = end.microsecondsSinceEpoch;
      final hasValidInterval = !end.isBefore(start);

      bool placed = false;
      for (var rowIndex = 0; rowIndex < rows.length; rowIndex++) {
        final row = rows[rowIndex];
        bool rowOverlaps = false;
        // Rows are start-sorted and non-overlapping; for valid intervals only
        // the latest task can conflict with this later-starting task.
        if (hasValidInterval && rowHasValidIntervals[rowIndex]) {
          rowOverlaps = intervalsOverlap(
            row.last,
            startMicroseconds,
            endMicroseconds,
          );
        } else {
          for (final existingTask in row) {
            if (intervalsOverlap(
              existingTask,
              startMicroseconds,
              endMicroseconds,
            )) {
              rowOverlaps = true;
              break;
            }
          }
        }
        if (!rowOverlaps) {
          row.add(task);
          rowHasValidIntervals[rowIndex] =
              rowHasValidIntervals[rowIndex] && hasValidInterval;
          placed = true;
          break;
        }
      }
      if (!placed) {
        rows.add([task]);
        rowHasValidIntervals.add(hasValidInterval);
      }
    }

    return rows;
  }

  DateTime _taskStartDate(TodoItem task) {
    return task.createdAt != 0
        ? DateTime.fromMillisecondsSinceEpoch(task.createdAt)
        : task.dueDate!.subtract(const Duration(days: 3));
  }

  _GanttLayout _layoutFor(List<TodoItem> todos, DateTime now) {
    final today = CalendarDateMath.dateOnly(now);
    final timeZoneOffsetSeconds = now.timeZoneOffset.inSeconds;
    final cachedInputs = _layoutInputs;
    final cachedLayout = _cachedLayout;
    if (identical(_layoutTodoSource, todos) &&
        _layoutToday == today &&
        _layoutTimeZoneOffsetSeconds == timeZoneOffsetSeconds &&
        cachedLayout != null &&
        cachedInputs != null &&
        cachedInputs.length == todos.length) {
      var inputsUnchanged = true;
      for (var index = 0; index < todos.length; index++) {
        if (!cachedInputs[index].matches(todos[index])) {
          inputsUnchanged = false;
          break;
        }
      }
      if (inputsUnchanged) return cachedLayout;
    }

    DateTime minDate = CalendarDateMath.addDays(today, -7);
    DateTime maxDate = CalendarDateMath.addDays(today, 30);
    final activeTodos = <TodoItem>[];
    final completedTodos = <TodoItem>[];
    final layoutInputs = <_GanttTaskLayoutInput>[];
    final startDates = Map<TodoItem, DateTime>.identity();
    for (final todo in todos) {
      layoutInputs.add(_GanttTaskLayoutInput.from(todo));
      if (todo.isDone) {
        completedTodos.add(todo);
      } else {
        activeTodos.add(todo);
      }

      final start = _taskStartDate(todo);
      startDates[todo] = start;
      final end = todo.dueDate!;
      if (start.isBefore(minDate)) minDate = start;
      if (end.isAfter(maxDate)) maxDate = end;
    }

    minDate = CalendarDateMath.addDays(CalendarDateMath.dateOnly(minDate), -7);
    maxDate = CalendarDateMath.addDays(CalendarDateMath.dateOnly(maxDate), 7);
    final totalDays = CalendarDateMath.daysBetween(minDate, maxDate);
    final layout = _GanttLayout(
      minDate: minDate,
      totalDays: totalDays,
      startDates: startDates,
      activeRows: _packTasks(activeTodos, startDates, minDate, maxDate),
      completedRows: _packTasks(completedTodos, startDates, minDate, maxDate),
    );

    _layoutTodoSource = todos;
    _layoutToday = today;
    _layoutTimeZoneOffsetSeconds = timeZoneOffsetSeconds;
    _layoutInputs = layoutInputs;
    return _cachedLayout = layout;
  }

  Widget _buildTaskRow({
    required List<TodoItem> rowTasks,
    required Map<TodoItem, DateTime> startDates,
    required DateTime minDate,
    required double effectiveDayWidth,
    required double rowHeight,
    required double taskFontSize,
    required bool isCompleted,
  }) {
    return SizedBox(
      height: rowHeight,
      child: Stack(
        children: rowTasks.map((task) {
          final start = startDates[task]!;
          final end = task.dueDate!;
          final left = math.max(
            0.0,
            CalendarDateMath.dayOffset(minDate, start) * effectiveDayWidth,
          );
          final width = math.max(
            effectiveDayWidth * 0.5,
            CalendarDateMath.dayOffset(start, end) * effectiveDayWidth,
          );

          return Positioned(
            left: left,
            width: width,
            top: 0,
            bottom: 0,
            child: GestureDetector(
              onTap: () => widget.onTaskClick(task),
              child: Container(
                decoration: BoxDecoration(
                  color:
                      (task.teamUuid != null
                              ? Theme.of(context).colorScheme.primary
                              : emerald)
                          .withValues(alpha: isCompleted ? 0.05 : 0.1),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color:
                        (task.teamUuid != null
                                ? Theme.of(context).colorScheme.primary
                                : emerald)
                            .withValues(alpha: isCompleted ? 0.16 : 0.3),
                  ),
                ),
                clipBehavior: Clip.hardEdge,
                child: Stack(
                  children: [
                    ValueListenableBuilder<double>(
                      valueListenable: _horizontalOffset,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          task.title,
                          style: TextStyle(
                            color: isCompleted ? Colors.white38 : Colors.white,
                            fontSize: taskFontSize,
                            fontWeight: FontWeight.w900,
                            decoration: isCompleted
                                ? TextDecoration.lineThrough
                                : null,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      builder: (context, horizontalOffset, child) {
                        return Positioned(
                          left: (horizontalOffset - left + 4)
                              .clamp(4.0, math.max(4.0, width - 24))
                              .toDouble(),
                          right: 4,
                          top: 0,
                          bottom: 0,
                          child: child!,
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.todos.isEmpty) {
      return const Center(
        child: Text('暂无带日期的任务', style: TextStyle(color: Colors.white24)),
      );
    }

    final now = DateTime.now();

    final layout = _layoutFor(widget.todos, now);
    final minDate = layout.minDate;
    final totalDays = layout.totalDays;
    final startDates = layout.startDates;
    final activeRows = layout.activeRows;
    final completedRows = layout.completedRows;

    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth;
        final effectiveDayWidth = widget.dayWidth <= 0
            ? availableWidth / totalDays
            : widget.dayWidth;

        final totalWidth = totalDays * effectiveDayWidth;
        const taskTopOffset = 50.0;
        final taskAreaHeight = math.max(
          0.0,
          constraints.maxHeight - taskTopOffset - 8,
        );
        final completedHeight = completedRows.isEmpty
            ? 0.0
            : activeRows.isEmpty
            ? taskAreaHeight
            : math.min(120.0, math.max(56.0, taskAreaHeight * 0.25));
        final activeAreaHeight = math.max(
          0.0,
          taskAreaHeight -
              completedHeight -
              (completedRows.isEmpty || activeRows.isEmpty ? 0 : 10),
        );
        final activeRowGap = activeRows.length > 10 ? 1.0 : 4.0;
        final activeRowHeight = activeRows.isEmpty
            ? 0.0
            : math.min(
                28.0,
                math.max(
                  1.0,
                  (activeAreaHeight -
                          (activeRowGap * (activeRows.length - 1))) /
                      activeRows.length,
                ),
              );
        final activeFontSize = math.max(
          5.0,
          math.min(8.0, activeRowHeight * 0.55),
        );
        final completedRowHeight = math.min(
          24.0,
          math.max(14.0, completedHeight * 0.35),
        );
        final completedFontSize = math.max(
          6.0,
          math.min(8.0, completedRowHeight * 0.55),
        );
        _scheduleScrollToToday(minDate, effectiveDayWidth);
        final weekdayFormatter = _appBoardDateFormat('E');

        return SingleChildScrollView(
          controller: _scrollController,
          scrollDirection: Axis.horizontal,
          physics: totalWidth <= availableWidth + 1
              ? const NeverScrollableScrollPhysics()
              : const BouncingScrollPhysics(),
          child: SizedBox(
            width: totalWidth,
            child: Stack(
              children: [
                // Grid Lines & Header
                Column(
                  children: [
                    Row(
                      children: List.generate(totalDays, (index) {
                        final date = CalendarDateMath.addDays(minDate, index);
                        final isToday =
                            date.day == now.day &&
                            date.month == now.month &&
                            date.year == now.year;
                        return Container(
                          width: effectiveDayWidth,
                          height: 40,
                          decoration: BoxDecoration(
                            border: Border(
                              right: BorderSide(
                                color: Colors.white.withValues(alpha: 0.05),
                              ),
                            ),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                weekdayFormatter.format(date).toUpperCase(),
                                style: TextStyle(
                                  color: isToday
                                      ? Theme.of(context).colorScheme.primary
                                      : Colors.white12,
                                  fontSize: math.max(
                                    6.0,
                                    effectiveDayWidth / 5,
                                  ),
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              Text(
                                date.day.toString(),
                                style: TextStyle(
                                  color: isToday
                                      ? Colors.white
                                      : Colors.white30,
                                  fontSize: math.max(
                                    8.0,
                                    effectiveDayWidth / 4,
                                  ),
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        );
                      }),
                    ),
                    Expanded(
                      child: RepaintBoundary(
                        child: CustomPaint(
                          painter: _GanttDayGridPainter(
                            dayCount: totalDays,
                            dayWidth: effectiveDayWidth,
                            color: Colors.white.withValues(alpha: 0.02),
                          ),
                          child: const SizedBox.expand(),
                        ),
                      ),
                    ),
                  ],
                ),
                // Today Line
                Positioned(
                  left:
                      CalendarDateMath.dayOffset(minDate, now) *
                      effectiveDayWidth,
                  top: 0,
                  bottom: 0,
                  child: Container(
                    width: 1,
                    color: Theme.of(context).colorScheme.primary
                        .withValues(alpha: 0.5),
                  ),
                ),
                // Task Rows
                Positioned(
                  left: 0,
                  right: 0,
                  top: taskTopOffset,
                  child: Column(
                    children: [
                      ...List.generate(activeRows.length, (rowIndex) {
                        final rowTasks = activeRows[rowIndex];
                        return Padding(
                          padding: EdgeInsets.only(
                            bottom: rowIndex == activeRows.length - 1
                                ? 0
                                : activeRowGap,
                          ),
                          child: _buildTaskRow(
                            rowTasks: rowTasks,
                            startDates: startDates,
                            minDate: minDate,
                            effectiveDayWidth: effectiveDayWidth,
                            rowHeight: activeRowHeight,
                            taskFontSize: activeFontSize,
                            isCompleted: false,
                          ),
                        );
                      }),
                      if (activeRows.isEmpty)
                        SizedBox(
                          height: math.max(0.0, activeAreaHeight),
                          child: const Center(
                            child: Text(
                              '暂无未完成日期任务',
                              style: TextStyle(color: Colors.white24),
                            ),
                          ),
                        ),
                      if (completedRows.isNotEmpty && activeRows.isNotEmpty)
                        const SizedBox(height: 10),
                      if (completedRows.isNotEmpty)
                        SizedBox(
                          height: completedHeight,
                          child: SingleChildScrollView(
                            physics: const BouncingScrollPhysics(),
                            child: Column(
                              children: List.generate(completedRows.length, (
                                rowIndex,
                              ) {
                                final rowTasks = completedRows[rowIndex];
                                return Padding(
                                  padding: EdgeInsets.only(
                                    bottom: rowIndex == completedRows.length - 1
                                        ? 0
                                        : 3,
                                  ),
                                  child: _buildTaskRow(
                                    rowTasks: rowTasks,
                                    startDates: startDates,
                                    minDate: minDate,
                                    effectiveDayWidth: effectiveDayWidth,
                                    rowHeight: completedRowHeight,
                                    taskFontSize: completedFontSize,
                                    isCompleted: true,
                                  ),
                                );
                              }),
                            ),
                          ),
                        ),
                    ],
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
