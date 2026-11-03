part of 'course_screens.dart';

// ignore_for_file: annotate_overrides, unused_element, unused_element_parameter

class _IdentityIndexCache<T extends Object> {
  Object? _source;
  Map<T, int>? _indices;

  Map<T, int> indicesFor(Object source, Iterable<T> items) {
    if (identical(_source, source)) return _indices!;

    final indices = HashMap<T, int>.identity();
    var index = 0;
    for (final item in items) {
      if (!indices.containsKey(item)) indices[item] = index;
      index++;
    }

    _source = source;
    _indices = indices;
    return indices;
  }
}

class _PlanPomodoroProgressIndex {
  _PlanPomodoroProgressIndex(this.plans, this.records) {
    final allocation = PomodoroPlanFocusAllocator.allocateByBlock(
      blocks: plans,
      records: records,
    );
    _secondsByPlanId = {
      for (var index = 0; index < plans.length; index++)
        plans[index].id: allocation.secondsByRecordByBlock[index],
    };
    _recordsByUuid = {
      for (final record in records)
        if (!record.isDeleted) record.uuid: record,
    };
  }

  final List<TodoPlanBlock> plans;
  final List<PomodoroRecord> records;
  late final Map<String, Map<String, int>> _secondsByPlanId;
  late final Map<String, PomodoroRecord> _recordsByUuid;
  final _progressByPlan =
      HashMap<TodoPlanBlock, Map<String, dynamic>>.identity();

  Map<String, dynamic> progressFor(
    TodoPlanBlock plan,
  ) => _progressByPlan.putIfAbsent(plan, () {
    if (plan.isDeleted) {
      return {'completed': 0, 'total': 0, 'actualSeconds': 0, 'progress': 0.0};
    }

    final attributedSeconds = _secondsByPlanId[plan.id] ?? const {};
    if (attributedSeconds.isEmpty) {
      return {'completed': 0, 'total': 0, 'actualSeconds': 0, 'progress': 0.0};
    }

    var totalSeconds = 0;
    var completedSeconds = 0;
    var actualSeconds = 0;
    for (final entry in attributedSeconds.entries) {
      final record = _recordsByUuid[entry.key];
      if (record == null) continue;
      final effective = entry.value;
      actualSeconds += effective;
      final originalEffective = record.effectiveDuration > 0
          ? record.effectiveDuration
          : 0;
      final planned = record.plannedDuration > 0
          ? record.plannedDuration
          : originalEffective;
      var base = planned > 0 ? planned : 1;
      if (originalEffective > 0 && effective < originalEffective) {
        final proratedBase = (planned * effective / originalEffective).round();
        base = proratedBase > 0 ? proratedBase : 1;
      }
      totalSeconds += base;
      completedSeconds += effective.clamp(0, base);
    }
    final progress = totalSeconds > 0 ? completedSeconds / totalSeconds : 0.0;
    return {
      'completed': completedSeconds,
      'total': totalSeconds,
      'actualSeconds': actualSeconds,
      'progress': progress.clamp(0.0, 1.0),
      'recordCount': attributedSeconds.length,
    };
  });
}

TodoPlanStatus _planStatusForActualFocus(
  TodoPlanBlock plan,
  int actualFocusSeconds,
) {
  if ((plan.status == TodoPlanStatus.planned ||
          plan.status == TodoPlanStatus.focusing) &&
      plan.plannedMinutes > 0 &&
      actualFocusSeconds >= plan.plannedMinutes * 60 * 0.8) {
    return TodoPlanStatus.finished;
  }
  return plan.status;
}

class _PomodoroPlanAssociationLookup {
  _PomodoroPlanAssociationLookup(Iterable<TodoPlanBlock> plans) {
    for (final plan in plans) {
      if (plan.isDeleted) continue;
      if (plan.id.isNotEmpty) _planIds.add(plan.id);
      _explicitRecordUuids.addAll(plan.pomodoroRecordIds);
      if (plan.todoId.isNotEmpty) {
        _plansByTodoId.putIfAbsent(plan.todoId, () => []).add(plan);
      }
    }
  }

  final _planIds = <String>{};
  final _explicitRecordUuids = <String>{};
  final _plansByTodoId = <String, List<TodoPlanBlock>>{};

  bool isAssociated(PomodoroRecord record, int recordEnd) {
    if (record.isDeleted) return false;
    if (_explicitRecordUuids.contains(record.uuid)) return true;

    final planBlockId = record.planBlockId;
    if (planBlockId != null &&
        planBlockId.isNotEmpty &&
        _planIds.contains(planBlockId)) {
      return true;
    }

    final todoUuid = record.todoUuid;
    if (todoUuid == null || todoUuid.isEmpty) return false;
    for (final plan in _plansByTodoId[todoUuid] ?? const <TodoPlanBlock>[]) {
      if (record.startTime < plan.endTime && recordEnd > plan.startTime) {
        return true;
      }
    }
    return false;
  }
}

class _PomodoroPlanDayAssociationIndex {
  _PomodoroPlanDayAssociationIndex(this._plans) {
    for (var index = 0; index < _plans.length; index++) {
      final plan = _plans[index];
      if (plan.isDeleted) continue;
      for (final recordUuid in plan.pomodoroRecordIds) {
        _planIndicesByRecordUuid.putIfAbsent(recordUuid, () => []).add(index);
      }
      if (plan.id.isNotEmpty) {
        _planIndicesById.putIfAbsent(plan.id, () => []).add(index);
      }
      if (plan.todoId.isNotEmpty) {
        _planIndicesByTodoId.putIfAbsent(plan.todoId, () => []).add(index);
      }
    }
  }

  final List<TodoPlanBlock> _plans;
  final _planIndicesByRecordUuid = <String, List<int>>{};
  final _planIndicesById = <String, List<int>>{};
  final _planIndicesByTodoId = <String, List<int>>{};

  List<TodoPlanBlock> matchingPlans(PomodoroRecord record, int recordEnd) {
    if (record.isDeleted) return const <TodoPlanBlock>[];
    Set<int>? matchingIndices;
    void addMatches(List<int>? indices) {
      if (indices == null || indices.isEmpty) return;
      (matchingIndices ??= <int>{}).addAll(indices);
    }

    addMatches(_planIndicesByRecordUuid[record.uuid]);
    final planBlockId = record.planBlockId;
    if (planBlockId != null && planBlockId.isNotEmpty) {
      addMatches(_planIndicesById[planBlockId]);
    }
    final todoUuid = record.todoUuid;
    if (todoUuid != null && todoUuid.isNotEmpty) {
      for (final index in _planIndicesByTodoId[todoUuid] ?? const <int>[]) {
        final plan = _plans[index];
        if (record.startTime < plan.endTime && recordEnd > plan.startTime) {
          (matchingIndices ??= <int>{}).add(index);
        }
      }
    }
    final matches = matchingIndices;
    if (matches == null || matches.isEmpty) return const <TodoPlanBlock>[];

    final orderedIndices = matches.toList()..sort();
    return [for (final index in orderedIndices) _plans[index]];
  }
}

mixin _WeeklyCourseGrid on _WeeklyCourseScreenStateBase {
  _PlanPomodoroProgressIndex? _cachedPlanPomodoroProgressIndex;
  Map<int, List<TodoPlanBlock>>? _visiblePlansSource;
  Map<TodoPlanBlock, int> _cachedVisiblePlanIndices = const {};
  List<_HiddenTimeRange>? _hiddenTimeRangesSource;
  List<double> _hiddenRangeDurationPrefix = const [0.0];
  final _todoIndexCache = _IdentityIndexCache<TodoItem>();
  final _timeLogIndexCache = _IdentityIndexCache<TimeLogItem>();
  final _pomodoroIndexCache = _IdentityIndexCache<PomodoroRecord>();
  final _courseIndexCache = _IdentityIndexCache<CourseItem>();

  @override
  void _invalidatePlanPomodoroProgressIndex() {
    _cachedPlanPomodoroProgressIndex = null;
  }

  _PlanPomodoroProgressIndex _planPomodoroProgressIndexFor() {
    final cached = _cachedPlanPomodoroProgressIndex;
    if (cached != null &&
        identical(cached.records, _allPomodoroRecords) &&
        identical(cached.plans, _allPlanBlocks)) {
      return cached;
    }
    final index = _PlanPomodoroProgressIndex(
      _allPlanBlocks,
      _allPomodoroRecords,
    );
    _cachedPlanPomodoroProgressIndex = index;
    return index;
  }

  void _prepareVisiblePlanCache() {
    final source = _planBlocksPerDay;
    if (identical(_visiblePlansSource, source)) return;

    final indices = HashMap<TodoPlanBlock, int>.identity();
    var index = 0;
    for (final dayPlans in source.values) {
      for (final plan in dayPlans) {
        if (!indices.containsKey(plan)) indices[plan] = index;
        index++;
      }
    }

    _visiblePlansSource = source;
    _cachedVisiblePlanIndices = indices;
  }

  void _prepareHiddenTimeRangeIndex() {
    final source = _hiddenTimeRanges;
    if (identical(_hiddenTimeRangesSource, source)) return;

    final durationPrefix = List<double>.filled(source.length + 1, 0.0);
    for (var index = 0; index < source.length; index++) {
      durationPrefix[index + 1] =
          durationPrefix[index] + source[index].duration;
    }

    _hiddenTimeRangesSource = source;
    _hiddenRangeDurationPrefix = durationPrefix;
  }

  int _hiddenRangeUpperBound(double minute) {
    var low = 0;
    var high = _hiddenTimeRanges.length;
    while (low < high) {
      final middle = low + ((high - low) >> 1);
      if (_hiddenTimeRanges[middle].startMinute <= minute) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    return low;
  }

  double get _totalHiddenMinutes {
    _prepareHiddenTimeRangeIndex();
    return _hiddenRangeDurationPrefix.last;
  }

  double _mapTimeToVirtualMinutes(int hour, int minute) {
    double m = (hour * 60 + minute).toDouble();
    final startMinute = startHour * 60.0;
    if (m < startMinute) return 0;

    _prepareHiddenTimeRangeIndex();
    final upperBound = _hiddenRangeUpperBound(m);
    var hiddenBefore = _hiddenRangeDurationPrefix[upperBound];
    if (upperBound > 0) {
      final range = _hiddenTimeRanges[upperBound - 1];
      if (m < range.endMinute) {
        hiddenBefore =
            _hiddenRangeDurationPrefix[upperBound - 1] +
            (m - range.startMinute);
      }
    }
    double virtualM = m - startMinute - hiddenBefore;
    return virtualM < 0 ? 0 : virtualM;
  }

  double _timeToY(int hour, int minute, double minuteHeight) {
    double virtualMinutes = _mapTimeToVirtualMinutes(hour, minute);
    return virtualMinutes * minuteHeight;
  }

  Color _harmonizeWeekEventColor(
    Color rawColor, {
    double opacity = 0.85,
    double maxSaturation = 0.52,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = colorScheme.brightness == Brightness.dark;
    final hsl = HSLColor.fromColor(rawColor);
    final toned = hsl
        .withSaturation(hsl.saturation.clamp(0.18, maxSaturation))
        .withLightness(
          hsl.lightness.clamp(isDark ? 0.34 : 0.38, isDark ? 0.48 : 0.50),
        )
        .toColor();
    final blended = Color.lerp(toned, colorScheme.surfaceTint, 0.14) ?? toned;
    return blended.withValues(alpha: opacity);
  }

  Color _getCourseColor(String courseName) {
    final colorScheme = Theme.of(context).colorScheme;
    final List<Color> baseColors = [
      colorScheme.secondary,
      colorScheme.tertiary,
      colorScheme.primary,
      colorScheme.cdtInfo,
      colorScheme.cdtSuccess,
      colorScheme.cdtWarning,
      Color.lerp(colorScheme.primary, colorScheme.tertiary, 0.5)!,
      Color.lerp(colorScheme.secondary, colorScheme.primary, 0.45)!,
    ];
    final int hash = courseName.hashCode.abs();
    return _harmonizeWeekEventColor(
      baseColors[hash % baseColors.length],
      opacity: 1.0,
      maxSaturation: 0.46,
    );
  }

  Color get _weekLazyLoadPlaceholderColor {
    return Theme.of(context).colorScheme.brightness == Brightness.dark
        ? Colors.black
        : Colors.white;
  }

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
                    itemCount: todos.length,
                    itemBuilder: (context, index) {
                      final todo = todos[index];
                      return ListTile(
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

          if (dayTodos.isEmpty &&
              fixedSchedules.isEmpty &&
              deviceEvents.isEmpty) {
            return const Expanded(child: SizedBox(height: 22));
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
          final colorScheme = Theme.of(context).colorScheme;
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

          final currentDay = CalendarDateMath.addDays(monday, index);
          final dayKey = _cachedDateFormat('yyyy-MM-dd').format(currentDay);
          final allDaySourceKey = deviceEvents.isEmpty
              ? null
              : _getDeviceCalendarCardKey(
                  deviceEvents.first.id,
                  dayKey,
                  surface: 'week-all-day',
                );

          return Expanded(
            child: GestureDetector(
              onTap: () {
                String dateStr = _cachedDateFormat('MM-dd').format(currentDay);
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
                margin: const EdgeInsets.symmetric(horizontal: 1, vertical: 1),
                padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
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
                        child: Icon(Icons.group, size: 10, color: onTodoColor),
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

  bool _timeRangesOverlap(
    int startA,
    int endAExclusive,
    int startB,
    int endBExclusive,
  ) {
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
      final int recordEnd =
          record.endTime ??
          (record.startTime + record.effectiveDuration * 1000);
      return _timeRangesOverlap(
        record.startTime,
        recordEnd,
        plan.startTime,
        plan.endTime,
      );
    }

    return false;
  }

  // --- 辅助方法：检查番茄钟是否被某个计划块关联 ---
  bool _isPomodoroAssociatedWithPlan(PomodoroRecord record) {
    return _allPlanBlocks.any(
      (plan) => _isRecordAssociatedWithPlan(record, plan),
    );
  }

  Map<String, dynamic> _calculatePlanPomodoroProgress(TodoPlanBlock plan) =>
      _PlanPomodoroProgressIndex(
        _allPlanBlocks,
        _allPomodoroRecords,
      ).progressFor(plan);

  Widget _buildHeader(DateTime? monday) {
    DateTime now = DateTime.now();
    final dateKeyFormat = _cachedDateFormat('yyyy-MM-dd');
    final headerDateFormat = _cachedDateFormat('M/dd');
    String todayStr = dateKeyFormat.format(now);
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
            currentDate = CalendarDateMath.addDays(monday, index);
            dateStr = headerDateFormat.format(currentDate);
            isToday = dateKeyFormat.format(currentDate) == todayStr;
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
    _prepareHiddenTimeRangeIndex();
    final upperBound = _hiddenRangeUpperBound(m);
    if (upperBound == 0) return false;
    final range = _hiddenTimeRanges[upperBound - 1];
    if (range.startMinute <= startHour * 60.0) {
      return m >= range.startMinute && m < range.endMinute;
    }
    if (range.endMinute >= endHour * 60.0) {
      return m > range.startMinute && m <= range.endMinute;
    }
    return range.contains(m);
  }

  String _formatMinute(double minute) {
    final int value = minute.round();
    final int h = value ~/ 60;
    final int m = value % 60;
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
  }

  String _buildLunchCollapseText(
    double rangeStart,
    double rangeEnd,
    double pre,
    double post,
  ) {
    final ranges = <String>[];
    if (pre > 0.0) {
      ranges.add(
        '${_formatMinute(rangeStart)}-${_formatMinute(rangeStart + pre)}',
      );
    }
    if (post > 0.0) {
      ranges.add(
        '${_formatMinute(rangeEnd - post)}-${_formatMinute(rangeEnd)}',
      );
    }
    return ranges.join(' & ');
  }

  bool _timelineColumnOverlaps(
    List<_TimelineEvent> column,
    _TimelineEvent event,
  ) {
    var low = 0;
    var high = column.length;
    while (low < high) {
      final middle = low + ((high - low) >> 1);
      if (column[middle].top < event.collisionBottom) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }

    // Events in a column are appended in start-time order and never overlap,
    // so only the last event starting before this interval's end can overlap.
    final candidateIndex = low - 1;
    return candidateIndex >= 0 &&
        column[candidateIndex].collisionBottom > event.top;
  }

  int _estimateWrappedLines(String text, double maxWidth, double fontSize) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return 0;
    final effectiveWidth = maxWidth.clamp(12.0, double.infinity);
    final charsPerLine = (effectiveWidth / fontSize).floorToDouble().clamp(
      1.0,
      100.0,
    );
    var totalLines = 0;
    for (final paragraph in trimmed.split('\n')) {
      if (paragraph.isEmpty) {
        totalLines += 1;
        continue;
      }
      var lineUnits = 0.0;
      for (final rune in paragraph.runes) {
        lineUnits += rune >= 0x2E80 ? 1.0 : 0.58;
      }
      totalLines += (lineUnits / charsPerLine).ceil().clamp(1, 20);
    }
    return totalLines.clamp(1, 20);
  }

  ({int titleMaxLines, int subMaxLines, bool showSubtitle})
  _computeCardTextLayout({
    required String title,
    required String? subtitle,
    required double width,
    required double height,
    required double effectiveHeight,
    required double titleFontSize,
    required double subFontSize,
    double extraReservedHeight = 0.0,
    double horizontalPadding = 6.0,
  }) {
    final double availHeight = (effectiveHeight - 5.0 - extraReservedHeight)
        .clamp(10.0, double.infinity);
    final double titleLineHeight = titleFontSize * 1.1;
    final double subLineHeight = subFontSize * 1.1;
    const double subTopGap = 1.5;

    final String? cleanSub = subtitle?.trim();
    final bool hasSub = cleanSub != null && cleanSub.isNotEmpty;
    final bool showSubtitle =
        hasSub &&
        effectiveHeight >= 22.0 &&
        availHeight >= (titleLineHeight + subTopGap + subLineHeight);

    if (!showSubtitle) {
      final int titleMaxLines = ((availHeight + 2.0) / titleLineHeight)
          .floor()
          .clamp(1, 15);
      return (
        titleMaxLines: titleMaxLines,
        subMaxLines: 0,
        showSubtitle: false,
      );
    }

    final double textWidth = (width - horizontalPadding - 1.0).clamp(
      10.0,
      double.infinity,
    );
    final int neededTitleLines = _estimateWrappedLines(
      title,
      textWidth,
      titleFontSize,
    );
    final int neededSubLines = _estimateWrappedLines(
      cleanSub,
      textWidth,
      subFontSize,
    );

    final int minSubLines =
        (availHeight >= 46.0 && neededSubLines >= 2) ? 2 : 1;
    final double minSubReserve = subTopGap + minSubLines * subLineHeight;
    final int titleMaxLines =
        ((availHeight - minSubReserve + 2.0) / titleLineHeight)
            .floor()
            .clamp(1, 15);
    final int actualTitleLines = neededTitleLines < titleMaxLines
        ? neededTitleLines
        : titleMaxLines;
    final double remainingForSub =
        availHeight - actualTitleLines * titleLineHeight - subTopGap;
    final int computedSubLines = ((remainingForSub + 2.0) / subLineHeight)
        .floor()
        .clamp(1, 15);
    final int subMaxLines = computedSubLines < minSubLines
        ? minSubLines
        : computedSubLines;

    return (
      titleMaxLines: titleMaxLines,
      subMaxLines: subMaxLines,
      showSubtitle: true,
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
    final weekdayStr = const ['周一', '周二', '周三', '周四', '周五', '周六', '周日'][
      (weekday - 1).clamp(0, 6)
    ];
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
                    itemCount: items.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (itemCtx, index) {
                      return _buildDetailSidebarItem(
                        itemCtx,
                        items[index],
                        sourceDate,
                        'week_agg_modal_$index',
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

  void _layoutAndRenderEventLayer({
    required Map<int, List<_TimelineEvent>> layerEventsPerDay,
    required double cellWidth,
    required List<Widget> children,
    required bool allowAggregation,
  }) {
    for (int weekday = 1; weekday <= 7; weekday++) {
      final List<_TimelineEvent> dayEvents = layerEventsPerDay[weekday]!;
      if (dayEvents.isEmpty) continue;

      dayEvents.sort((a, b) => a.top.compareTo(b.top));

      final List<List<_TimelineEvent>> columns = [];
      final List<_TimelineEvent> currentGroup = [];
      double groupBottom = -1;
      final double leftOffset = timeColumnWidth + (weekday - 1) * cellWidth;

      void flushCurrentGroup() {
        if (currentGroup.isEmpty) return;
        final int numCols = columns.length;
        for (final e in currentGroup) {
          e.maxColumns = numCols;
          e.colSpan = 1;
          for (int i = e.columnIndex + 1; i < numCols; i++) {
            if (_timelineColumnOverlaps(columns[i], e)) break;
            e.colSpan++;
          }
        }

        final double colWidth = (cellWidth - 2) / numCols;
        if (allowAggregation && currentGroup.length > 1 && colWidth < 24.0) {
          final groupSnapshot = List<_TimelineEvent>.of(currentGroup);
          final firstEvent = groupSnapshot.first;
          double minTop = firstEvent.top;
          double maxBottom = firstEvent.bottom;
          for (final e in groupSnapshot) {
            if (e.top < minTop) minTop = e.top;
            if (e.bottom > maxBottom) maxBottom = e.bottom;
          }
          final double height = (maxBottom - minTop).clamp(
            18.0,
            double.infinity,
          );
          final double width = cellWidth - 2;
          final double left = leftOffset + 1;
          final int extraCount = groupSnapshot.length - 1;
          final Color baseColor = firstEvent.color;
          final Color secondColor = groupSnapshot.length > 1
              ? groupSnapshot[1].color
              : baseColor;
          final double titleFontSize = (height * 0.32).clamp(9.0, 10.5);
          final double subFontSize = (height * 0.22).clamp(8.0, 9.0);
          String? previewSubtitle = firstEvent.subtitle;
          if (previewSubtitle == null || previewSubtitle.trim().isEmpty) {
            for (final e in groupSnapshot.skip(1)) {
              final s = e.subtitle?.trim();
              if (s != null && s.isNotEmpty) {
                previewSubtitle = s;
                break;
              }
            }
          }
          final textLayout = _computeCardTextLayout(
            title: firstEvent.title,
            subtitle: previewSubtitle,
            width: width > 8 ? width - 2 : width,
            height: height,
            effectiveHeight: height > 22 ? height - 2 : height,
            titleFontSize: titleFontSize,
            subFontSize: subFontSize,
            extraReservedHeight: height > 48.0 ? 10.0 : 0.0,
          );
          final items = [
            for (final e in groupSnapshot)
              if (e.sourceItem != null) e.sourceItem!,
          ];

          children.add(
            Positioned(
              top: minTop + 1,
              left: left,
              width: width,
              height: (height - 2).clamp(18.0, double.infinity),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _showAggregatedTimelineSheet(
                  context,
                  weekday,
                  items,
                ),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    // 底部叠牌阴影层，体现多张卡片折叠效果
                    if (width > 8)
                      Positioned(
                        top: 2,
                        left: 2,
                        right: 0,
                        bottom: 0,
                        child: Container(
                          decoration: BoxDecoration(
                            color: secondColor.withValues(alpha: 0.45),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ),
                    Positioned(
                      top: 0,
                      left: 0,
                      right: width > 8 ? 2 : 0,
                      bottom: height > 22 ? 2 : 0,
                      child: Container(
                        alignment: Alignment.topLeft,
                        clipBehavior: Clip.hardEdge,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 3,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: baseColor,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.5),
                            width: 0.5,
                          ),
                        ),
                        child: SingleChildScrollView(
                          physics: const NeverScrollableScrollPhysics(),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                firstEvent.title,
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: titleFontSize,
                                  fontWeight: FontWeight.bold,
                                  height: 1.1,
                                ),
                                maxLines: textLayout.titleMaxLines,
                                textAlign: TextAlign.left,
                                overflow: TextOverflow.ellipsis,
                              ),
                              if (textLayout.showSubtitle &&
                                  previewSubtitle != null)
                                Padding(
                                  padding: const EdgeInsets.only(top: 1.5),
                                  child: Text(
                                    previewSubtitle,
                                    style: TextStyle(
                                      color: Colors.white.withValues(
                                        alpha: 0.84,
                                      ),
                                      fontSize: subFontSize,
                                      height: 1.1,
                                    ),
                                    maxLines: textLayout.subMaxLines,
                                    textAlign: TextAlign.left,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    // 右上角/右下角 +N 角标
                    Positioned(
                      right: width > 8 ? 3 : 1,
                      bottom: height > 22 ? 3 : 1,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 3.5,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.65),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          '+$extraCount',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 8.5,
                            fontWeight: FontWeight.bold,
                            height: 1.0,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        } else {
          for (final event in currentGroup) {
            final double l = leftOffset + 1 + event.columnIndex * colWidth;
            final double width = colWidth * event.colSpan;
            children.add(event.builder(l, width));
          }
        }

        columns.clear();
        currentGroup.clear();
        groupBottom = -1;
      }

      for (final event in dayEvents) {
        if (event.top >= groupBottom && currentGroup.isNotEmpty) {
          flushCurrentGroup();
        }

        currentGroup.add(event);
        if (event.collisionBottom > groupBottom) {
          groupBottom = event.collisionBottom;
        }

        bool placed = false;
        for (int i = 0; i < columns.length; i++) {
          if (columns[i].last.collisionBottom <= event.top) {
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

      flushCurrentGroup();
    }
  }

  Widget _buildGrid(double cellWidth, double minuteHeight) {
    List<Widget> children = [];
    final colorScheme = Theme.of(context).colorScheme;
    final focusColor = colorScheme.cdtFocus;
    bool isDark = colorScheme.brightness == Brightness.dark;
    Color lineColor = isDark ? Colors.white10 : Colors.black12;
    Color textColor = isDark ? Colors.white70 : Colors.black87;
    Map<String, int>? tagOrderByUuid;
    Map<String, int> tagOrder() {
      final cached = tagOrderByUuid;
      if (cached != null) return cached;
      final result = <String, int>{};
      for (var index = 0; index < _pomodoroTags.length; index++) {
        result.putIfAbsent(_pomodoroTags[index].uuid, () => index);
      }
      tagOrderByUuid = result;
      return result;
    }

    PomodoroTag? firstTagFor(Iterable<String> uuids) {
      var firstIndex = _pomodoroTags.length;
      final orderByUuid = tagOrder();
      for (final uuid in uuids) {
        final index = orderByUuid[uuid];
        if (index != null && index < firstIndex) firstIndex = index;
      }
      return firstIndex == _pomodoroTags.length
          ? null
          : _pomodoroTags[firstIndex];
    }

    final hasVisiblePlans = _activeDataViews.contains('plans');
    if (hasVisiblePlans) _prepareVisiblePlanCache();
    final planIndices = hasVisiblePlans
        ? _cachedVisiblePlanIndices
        : const <TodoPlanBlock, int>{};
    final planPomodoroProgressIndex = _planPomodoroProgressIndexFor();

    for (int hour = startHour; hour <= endHour; hour++) {
      // 🚀 自适应时间隐藏：如果该小时正点落于本周的合并收窄区间中，跳过不绘制
      if (_isHourCollapsed(hour)) continue;

      double y = _timeToY(hour, 0, minuteHeight);

      children.add(
        Positioned(
          top: y,
          left: timeColumnWidth,
          right: 0,
          height: 1,
          child: Container(color: lineColor),
        ),
      );

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

        if (nextHour <= endHour && slotHeight >= 14.0) {
          children.add(
            Positioned(
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
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ),
          );
        }
      }
    }

    final lunchCardStart = _lunchCardStartMinute;
    if (lunchCardStart != null && _lunchCardDuration > 0.0) {
      final int lunchCardHour = lunchCardStart ~/ 60;
      final int lunchCardMinute = lunchCardStart.round() % 60;
      final double y1 = _timeToY(lunchCardHour, lunchCardMinute, minuteHeight);
      double collapseHeight = _lunchCardDuration * minuteHeight;

      children.add(
        Positioned(
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
        ),
      );
    }

    for (int i = 0; i <= 7; i++) {
      children.add(
        Positioned(
          top: 0,
          bottom: 0,
          left: timeColumnWidth + i * cellWidth,
          width: 0.5,
          child: Container(color: lineColor),
        ),
      );
    }

    Map<int, List<_TimelineEvent>> backgroundEventsPerDay = {
      1: [],
      2: [],
      3: [],
      4: [],
      5: [],
      6: [],
      7: [],
    };
    Map<int, List<_TimelineEvent>> foregroundEventsPerDay = {
      1: [],
      2: [],
      3: [],
      4: [],
      5: [],
      6: [],
      7: [],
    };

    double topInsetForBackgroundCard(
      int weekday,
      double bgTop,
      double bgBottom,
    ) {
      final fgEvents = foregroundEventsPerDay[weekday];
      if (fgEvents == null || fgEvents.isEmpty) return 0.0;
      double maxFgBottom = bgTop;
      for (final fg in fgEvents) {
        if (fg.top <= bgTop + 14.0 &&
            fg.bottom > maxFgBottom &&
            bgBottom - fg.bottom >= 18.0) {
          maxFgBottom = fg.bottom;
        }
      }
      return (maxFgBottom - bgTop).clamp(
        0.0,
        (bgBottom - bgTop - 16.0).clamp(0.0, double.infinity),
      );
    }

    if (_activeDataViews.contains('todos')) {
      final todoIndices = _todoIndexCache.indicesFor(
        _intraDayTodosPerDay,
        _intraDayTodosPerDay.values.expand((items) => items),
      );
      final collisionMap = <String, int>{};
      for (int weekday = 1; weekday <= 7; weekday++) {
        final dayTodos = _intraDayTodosPerDay[weekday] ?? [];
        for (var todo in dayTodos) {
          DateTime start = DateTime.fromMillisecondsSinceEpoch(
            todo.createdDate ?? todo.createdAt,
            isUtc: true,
          ).toLocal();
          DateTime end = todo.dueDate ?? start.add(const Duration(hours: 1));

          double top = _timeToY(start.hour, start.minute, minuteHeight);
          double bottom = _timeToY(end.hour, end.minute, minuteHeight);
          double height = bottom - top;

          if (height < 20.0) height = 20.0;

          final collisionKey = '${weekday}_${(top / 15).floor()}';
          final stackIndex = collisionMap[collisionKey] ?? 0;
          collisionMap[collisionKey] = stackIndex + 1;

          Color todoColor = todo.isDone
              ? _harmonizeWeekEventColor(
                  colorScheme.cdtSuccess,
                  opacity: 0.28,
                  maxSaturation: 0.40,
                )
              : _harmonizeWeekEventColor(
                  colorScheme.cdtWarning,
                  opacity: 0.85,
                );
          final Color todoTextColor = Colors.white.withValues(
            alpha: todo.isDone ? 0.65 : 1.0,
          );
          final todoCardKey = _getTodoCardKey(todo.id, weekday: weekday);
          final todoIndex = todoIndices[todo]!;

          foregroundEventsPerDay[weekday]!.add(
            _TimelineEvent(
              top: top,
              bottom: top + height,
              collisionBottom: bottom,
              sourceItem: todo,
              title: todo.title,
              subtitle: todo.remark,
              color: todoColor,
              builder: (left, width) {
                final double fontScale = (width / (cellWidth - 2)).clamp(
                  0.4,
                  1.0,
                );
                final double titleFontSize = (height * 0.32 * fontScale).clamp(
                  9.0,
                  10.5,
                );
                final double teamFontSize = (height * 0.22 * fontScale).clamp(
                  8.0,
                  9.0,
                );
                final bool showTeamBadge =
                    todo.teamUuid != null && height > 56.0;
                final textLayout = _computeCardTextLayout(
                  title: todo.title,
                  subtitle: todo.remark,
                  width: width,
                  height: height,
                  effectiveHeight: height,
                  titleFontSize: titleFontSize,
                  subFontSize: 8.0,
                  extraReservedHeight: showTeamBadge
                      ? (teamFontSize + 5.0)
                      : 0.0,
                );
                final bool showRemark = textLayout.showSubtitle;
                final int todoMaxLines = textLayout.titleMaxLines;
                final animationDelay = (todoIndex * 0.06).clamp(0.0, 0.5);
                final animationProgressScale = 1.0 / (1.0 - animationDelay);

                return Positioned(
                  top: top + 1,
                  left: left,
                  width: width,
                  height: (height - 2).clamp(18.0, double.infinity),
                  child: AnimatedBuilder(
                    animation: _courseExpandAnim,
                    builder: (ctx, child) {
                      final t =
                          ((_courseExpandAnim.value - animationDelay) *
                                  animationProgressScale)
                              .clamp(0.0, 1.0);
                      final scale = 0.7 + 0.3 * t;
                      final opacity = t;
                      return Transform.scale(
                        scale: scale,
                        child: Opacity(opacity: opacity, child: child),
                      );
                    },
                    child: GestureDetector(
                      onTap: () {
                        PageTransitions.pushFromRect(
                          context: context,
                          page: TodoDetailScreen(
                            todo: todo,
                            onCreateRelatedTodo: widget.onCreateRelatedTodo,
                          ),
                          sourceKey: todoCardKey,
                          sourceColor: _weekLazyLoadPlaceholderColor,
                          sourceBorderRadius: const BorderRadius.all(
                            Radius.circular(4),
                          ),
                          placeholderIcon: Icons.task_alt_rounded,
                        );
                      },
                      child: Container(
                        key: todoCardKey,
                        alignment: Alignment.topLeft,
                        clipBehavior: Clip.hardEdge,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 3,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: todoColor,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                            color: colorScheme.surface.withValues(alpha: 0.7),
                            width: 0.6,
                          ),
                          boxShadow: !todo.isDone && stackIndex > 0
                              ? [
                                  const BoxShadow(
                                    color: Colors.black12,
                                    blurRadius: 2,
                                    offset: Offset(-1, 1),
                                  ),
                                ]
                              : null,
                        ),
                        child: SingleChildScrollView(
                          physics: const NeverScrollableScrollPhysics(),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (showTeamBadge)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 2.0),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 2,
                                      vertical: 0.5,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withValues(
                                        alpha: todo.isDone ? 0.18 : 0.3,
                                      ),
                                      borderRadius: BorderRadius.circular(2),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.group,
                                          size: 8,
                                          color: todoTextColor,
                                        ),
                                        const SizedBox(width: 1),
                                        Flexible(
                                          child: Text(
                                            todo.teamName ?? '团队',
                                            style: TextStyle(
                                              color: todoTextColor,
                                              fontSize: teamFontSize,
                                              fontWeight: FontWeight.bold,
                                            ),
                                            maxLines: 1,
                                            textAlign: TextAlign.left,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              Text(
                                todo.title,
                                style: TextStyle(
                                  color: todoTextColor,
                                  fontSize: titleFontSize,
                                  fontWeight: FontWeight.bold,
                                  decoration: todo.isDone
                                      ? TextDecoration.lineThrough
                                      : null,
                                  height: 1.1,
                                ),
                                maxLines: todoMaxLines,
                                textAlign: TextAlign.left,
                                overflow: TextOverflow.ellipsis,
                              ),
                              if (showRemark && todo.remark != null)
                                Padding(
                                  padding: const EdgeInsets.only(top: 1.5),
                                  child: Text(
                                    todo.remark!,
                                    style: TextStyle(
                                      color: Colors.white.withValues(
                                        alpha: todo.isDone ? 0.52 : 0.78,
                                      ),
                                      fontSize: 8,
                                      height: 1.1,
                                    ),
                                    maxLines: textLayout.subMaxLines,
                                    textAlign: TextAlign.left,
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
              },
            ),
          );
        }
      }
    }

    if (_activeDataViews.contains('timeLogs')) {
      final logIndices = _timeLogIndexCache.indicesFor(
        _timeLogsPerDay,
        _timeLogsPerDay.values.expand((items) => items),
      );
      for (int weekday = 1; weekday <= 7; weekday++) {
        for (var log in _timeLogsPerDay[weekday]!) {
          DateTime start = DateTime.fromMillisecondsSinceEpoch(
            log.startTime,
            isUtc: true,
          ).toLocal();
          DateTime end = DateTime.fromMillisecondsSinceEpoch(
            log.endTime,
            isUtc: true,
          ).toLocal();

          double top = _timeToY(start.hour, start.minute, minuteHeight);
          double bottom = _timeToY(end.hour, end.minute, minuteHeight);
          double height = bottom - top;

          if (height < 18.0) height = 18.0;

          Color rawLogColor = colorScheme.cdtInfo;
          String logTitle = log.title.isNotEmpty ? log.title : '时间日志';
          if (log.tagUuids.isNotEmpty) {
            final tag = firstTagFor(log.tagUuids);
            if (tag != null) {
              rawLogColor = AppColorUtils.hexToColor(
                tag.color,
                fallback: colorScheme.cdtInfo,
              );
              if (logTitle == '时间日志') logTitle = tag.name;
            }
          }
          final Color logColor = _harmonizeWeekEventColor(
            rawLogColor,
            opacity: 0.78,
          );

          final int logDurationSeconds =
              ((log.endTime - log.startTime) / 1000).round();
          final String logDurationText =
              _formatEventDuration(logDurationSeconds);
          final logRemark = log.remark?.trim();
          final String effectiveLogSubtitle =
              (logRemark != null && logRemark.isNotEmpty)
                  ? '$logDurationText · $logRemark'
                  : logDurationText;

          final logCardKey = _getTimeLogCardKey(log.id, weekday: weekday);
          final logIndex = logIndices[log]!;

          foregroundEventsPerDay[weekday]!.add(
            _TimelineEvent(
              top: top,
              bottom: top + height,
              collisionBottom: bottom,
              sourceItem: log,
              title: logTitle,
              subtitle: effectiveLogSubtitle,
              color: logColor,
              builder: (left, width) {
                final double fontScale = (width / (cellWidth - 2)).clamp(
                  0.4,
                  1.0,
                );
                final double titleFontSize = (height * 0.32 * fontScale).clamp(
                  9.0,
                  10.5,
                );
                final double subFontSize = (height * 0.22 * fontScale).clamp(
                  8.0,
                  9.0,
                );
                final bool isShortLogCard = height < 22.0;
                final String displayLogTitle = isShortLogCard
                    ? '$logTitle · $logDurationText'
                    : logTitle;
                final String? displayLogSubtitle = isShortLogCard
                    ? null
                    : effectiveLogSubtitle;
                final textLayout = _computeCardTextLayout(
                  title: displayLogTitle,
                  subtitle: displayLogSubtitle,
                  width: width,
                  height: height,
                  effectiveHeight: height,
                  titleFontSize: titleFontSize,
                  subFontSize: subFontSize,
                );
                final bool showRemark = textLayout.showSubtitle;
                final int logMaxLines = textLayout.titleMaxLines;
                final animationDelay = (logIndex * 0.06).clamp(0.0, 0.5);
                final animationProgressScale = 1.0 / (1.0 - animationDelay);

                return Positioned(
                  top: top + 1,
                  left: left,
                  width: width,
                  height: (height - 2).clamp(18.0, double.infinity),
                  child: AnimatedBuilder(
                    animation: _courseExpandAnim,
                    builder: (ctx, child) {
                      final t =
                          ((_courseExpandAnim.value - animationDelay) *
                                  animationProgressScale)
                              .clamp(0.0, 1.0);
                      final scale = 0.7 + 0.3 * t;
                      final opacity = t;
                      return Transform.scale(
                        scale: scale,
                        child: Opacity(opacity: opacity, child: child),
                      );
                    },
                    child: GestureDetector(
                      onTap: () {
                        PageTransitions.pushFromRect(
                          context: context,
                          page: TimeLogDetailScreen(
                            log: log,
                            tags: _pomodoroTags,
                          ),
                          sourceKey: logCardKey,
                          sourceColor: _weekLazyLoadPlaceholderColor,
                          sourceBorderRadius: const BorderRadius.all(
                            Radius.circular(4),
                          ),
                          placeholderIcon: Icons.receipt_long_rounded,
                        );
                      },
                      child: Container(
                        key: logCardKey,
                        alignment: Alignment.topLeft,
                        clipBehavior: Clip.hardEdge,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 3,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: logColor,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                            color: logColor.withValues(alpha: 1.0),
                            width: 0.5,
                          ),
                        ),
                        child: SingleChildScrollView(
                          physics: const NeverScrollableScrollPhysics(),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                displayLogTitle,
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: titleFontSize,
                                  fontWeight: FontWeight.bold,
                                  height: 1.1,
                                ),
                                maxLines: logMaxLines,
                                textAlign: TextAlign.left,
                                overflow: TextOverflow.ellipsis,
                              ),
                              if (showRemark && displayLogSubtitle != null)
                                Padding(
                                  padding: const EdgeInsets.only(top: 1.5),
                                  child: Text(
                                    displayLogSubtitle,
                                    style: TextStyle(
                                      color: Colors.white.withValues(
                                        alpha: 0.82,
                                      ),
                                      fontSize: subFontSize,
                                      height: 1.1,
                                    ),
                                    maxLines: textLayout.subMaxLines,
                                    textAlign: TextAlign.left,
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
              },
            ),
          );
        }
      }
    }

    if (_activeDataViews.contains('plans')) {
      for (int weekday = 1; weekday <= 7; weekday++) {
        for (var plan in _planBlocksPerDay[weekday] ?? <TodoPlanBlock>[]) {
          final start = DateTime.fromMillisecondsSinceEpoch(plan.startTime)
              .toLocal();
          final end = DateTime.fromMillisecondsSinceEpoch(plan.endTime)
              .toLocal();

          double top = _timeToY(start.hour, start.minute, minuteHeight);
          double bottom = _timeToY(end.hour, end.minute, minuteHeight);
          double height = bottom - top;
          if (height < 18.0) height = 18.0;

          final title = plan.titleSnapshot ?? '规划任务';
          final planIndex = planIndices[plan]!;
          final planCardKey = _getPlanBlockCardKey(plan.uuid, weekday);

          // 计算关联的番茄钟完成进度
          final pomProgress = planPomodoroProgressIndex.progressFor(plan);
          final recordCount = (pomProgress['recordCount'] as int?) ?? 0;
          final hasAssociatedPomodoro = recordCount > 0;
          final actualFocusSeconds =
              (pomProgress['actualSeconds'] as int?) ?? 0;
          final double progressRatio =
              ((pomProgress['progress'] as double?) ?? 0.0).clamp(0.0, 1.0);
          final planStatus = _planStatusForActualFocus(
            plan,
            actualFocusSeconds,
          );
          final bool isPlanFinished =
              planStatus == TodoPlanStatus.finished || progressRatio >= 1.0;
          final planColor = isPlanFinished
              ? _harmonizeWeekEventColor(
                  colorScheme.cdtSuccess,
                  opacity: 0.26,
                  maxSaturation: 0.36,
                )
              : _harmonizeWeekEventColor(
                  colorScheme.secondary,
                  opacity: 0.56,
                  maxSaturation: 0.42,
                );
          final Color planTextColor = Colors.white.withValues(
            alpha: isPlanFinished ? 0.68 : 1.0,
          );
          final Color planSubTextColor = Colors.white.withValues(
            alpha: isPlanFinished ? 0.56 : 0.82,
          );
          final String? rawPlanSubtitle = hasAssociatedPomodoro
              ? '${(progressRatio * 100).toStringAsFixed(0)}%'
              : (plan.remark != null && plan.remark!.isNotEmpty
                    ? plan.remark
                    : null);

          backgroundEventsPerDay[weekday]!.add(
            _TimelineEvent(
              top: top,
              bottom: top + height,
              collisionBottom: bottom,
              sourceItem: plan,
              title: title,
              subtitle: rawPlanSubtitle,
              color: planColor,
              builder: (left, width) {
                final double topOccupied = topInsetForBackgroundCard(
                  weekday,
                  top,
                  top + height,
                );
                final double effectiveHeight = (height - topOccupied).clamp(
                  16.0,
                  double.infinity,
                );
                final double fontScale = (width / (cellWidth - 2)).clamp(
                  0.4,
                  1.0,
                );
                final double titleFontSize = (height * 0.32 * fontScale).clamp(
                  9.0,
                  10.5,
                );
                final double subFontSize = (height * 0.22 * fontScale).clamp(
                  8.0,
                  9.0,
                );
                final double cardWidth = width > 6 ? width - 6 : width;
                final textLayout = _computeCardTextLayout(
                  title: title,
                  subtitle: rawPlanSubtitle,
                  width: cardWidth,
                  height: height,
                  effectiveHeight: effectiveHeight,
                  titleFontSize: titleFontSize,
                  subFontSize: subFontSize,
                );
                final int planMaxLines = textLayout.titleMaxLines;
                final String? planSubtitle = textLayout.showSubtitle
                    ? rawPlanSubtitle
                    : null;
                final animationDelay = (planIndex * 0.04).clamp(0.0, 0.45);
                final animationProgressScale = 1.0 / (1.0 - animationDelay);

                final Widget planContent = Padding(
                  padding: EdgeInsets.fromLTRB(3, 2 + topOccupied, 3, 2),
                  child: SingleChildScrollView(
                    physics: const NeverScrollableScrollPhysics(),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            color: planTextColor,
                            fontSize: titleFontSize,
                            fontWeight: FontWeight.bold,
                            height: 1.1,
                          ),
                          maxLines: planMaxLines,
                          textAlign: TextAlign.left,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (planSubtitle != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 1.5),
                            child: Text(
                              planSubtitle,
                              style: TextStyle(
                                color: planSubTextColor,
                                fontSize: subFontSize,
                                fontWeight: hasAssociatedPomodoro
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                                height: 1.1,
                              ),
                              maxLines: textLayout.subMaxLines,
                              textAlign: TextAlign.left,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                    ),
                  ),
                );

                return Positioned(
                  top: top + 1,
                  left: left + 3,
                  width: width > 6 ? width - 6 : width,
                  height: (height - 2).clamp(16.0, double.infinity),
                  child: AnimatedBuilder(
                    animation: _courseExpandAnim,
                    builder: (ctx, child) {
                      final t =
                          ((_courseExpandAnim.value - animationDelay) *
                                  animationProgressScale)
                              .clamp(0.0, 1.0);
                      return Transform.scale(
                        scale: 0.8 + 0.2 * t,
                        child: Opacity(opacity: t, child: child),
                      );
                    },
                    child: GestureDetector(
                      onTap: () {
                        PageTransitions.pushFromRect(
                          context: context,
                          page: PlanBlockDetailScreen(
                            block: plan,
                            username: widget.username,
                          ),
                          sourceKey: planCardKey,
                          sourceColor: _weekLazyLoadPlaceholderColor,
                          sourceBorderRadius: const BorderRadius.all(
                            Radius.circular(4),
                          ),
                          placeholderIcon: Icons.event_note_rounded,
                        );
                      },
                      child: Container(
                        key: planCardKey,
                        alignment: Alignment.topLeft,
                        clipBehavior: Clip.hardEdge,
                        decoration: BoxDecoration(
                          color: planColor,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                            color: Colors.white.withValues(
                              alpha: isPlanFinished ? 0.18 : 0.35,
                            ),
                            width: 0.5,
                          ),
                        ),
                        // 如果有关联的番茄钟，用背景填充表示完成进度
                        child: hasAssociatedPomodoro
                            ? Stack(
                                fit: StackFit.expand,
                                children: [
                                  Align(
                                    alignment: Alignment.bottomCenter,
                                    child: FractionallySizedBox(
                                      heightFactor: progressRatio,
                                      widthFactor: 1.0,
                                      child: Container(
                                        decoration: BoxDecoration(
                                          color: Colors.white.withValues(
                                            alpha: isPlanFinished ? 0.10 : 0.22,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  Align(
                                    alignment: Alignment.topLeft,
                                    child: planContent,
                                  ),
                                ],
                              )
                            : planContent,
                      ),
                    ),
                  ),
                );
              },
            ),
          );
        }
      }
    }

    if (_activeDataViews.contains('fixedSchedules')) {
      final monday = _getMondayOfCurrentWeek();
      if (monday != null) {
        for (int weekday = 1; weekday <= 7; weekday++) {
          final dayStart = DateTime(
            monday.year,
            monday.month,
            monday.day + weekday - 1,
          );
          final dayEnd = CalendarDateMath.addDays(dayStart, 1);
          for (final schedule
              in (_fixedSchedulesPerDay[weekday] ?? const []).where(
                (item) => item.startTime != null,
              )) {
            final scheduleStart = DateTime.fromMillisecondsSinceEpoch(
              schedule.startTime!,
            );
            final scheduleEnd = schedule.endTime == null
                ? scheduleStart.add(const Duration(hours: 1))
                : DateTime.fromMillisecondsSinceEpoch(schedule.endTime!);
            final sliceStart = scheduleStart.isAfter(dayStart)
                ? scheduleStart
                : dayStart;
            final sliceEnd = scheduleEnd.isBefore(dayEnd)
                ? scheduleEnd
                : dayEnd;
            if (!sliceEnd.isAfter(sliceStart)) continue;

            final startMinutes = sliceStart.hour * 60 + sliceStart.minute;
            final endMinutes = sliceEnd == dayEnd
                ? 24 * 60
                : sliceEnd.hour * 60 + sliceEnd.minute;
            if (endMinutes <= startHour * 60 || startMinutes >= endHour * 60) {
              continue;
            }
            final visibleStart = startMinutes
                .clamp(startHour * 60, endHour * 60)
                .toInt();
            final visibleEnd = endMinutes
                .clamp(startHour * 60, endHour * 60)
                .toInt();
            final top = _timeToY(
              visibleStart ~/ 60,
              visibleStart % 60,
              minuteHeight,
            );
            final bottom = _timeToY(
              visibleEnd ~/ 60,
              visibleEnd % 60,
              minuteHeight,
            );
            var height = bottom - top;
            if (height < 18.0) height = 18.0;

            final fixedColor = colorScheme.primary.withValues(alpha: 0.82);
            final fixedSchedulePlaceholderColor =
                colorScheme.brightness == Brightness.dark
                ? Colors.black
                : Colors.white;
            final fixedScheduleCardKey = _getFixedScheduleCardKey(
              schedule.id,
              weekday,
            );
            final locText = schedule.location?.trim();
            final remText = schedule.remark?.trim();
            final detailParts = <String>[
              if (locText != null && locText.isNotEmpty) locText,
              if (remText != null && remText.isNotEmpty && remText != locText)
                remText,
            ];
            final String? location = detailParts.isEmpty
                ? null
                : detailParts.join(' · ');
            final bool isShortFixedCard = height < 24.0;
            final String displayFixedTitle =
                isShortFixedCard && location != null
                    ? '${schedule.title} · $location'
                    : schedule.title;
            final String? displayFixedLocation = isShortFixedCard
                ? null
                : location;
            backgroundEventsPerDay[weekday]!.add(
              _TimelineEvent(
                top: top,
                bottom: top + height,
                collisionBottom: bottom,
                sourceItem: schedule,
                title: schedule.title,
                subtitle: location,
                color: fixedColor,
                builder: (left, width) {
                  final double topOccupied = topInsetForBackgroundCard(
                    weekday,
                    top,
                    top + height,
                  );
                  final double effectiveHeight = (height - topOccupied).clamp(
                    16.0,
                    double.infinity,
                  );
                  final double fontScale = (width / (cellWidth - 2)).clamp(
                    0.4,
                    1.0,
                  );
                  final double titleSize = (height * 0.3 * fontScale).clamp(
                    9.0,
                    10.5,
                  );
                  final double subFontSize = (height * 0.22 * fontScale).clamp(
                    8.0,
                    9.0,
                  );
                  final textLayout = _computeCardTextLayout(
                    title: displayFixedTitle,
                    subtitle: displayFixedLocation,
                    width: width,
                    height: height,
                    effectiveHeight: effectiveHeight,
                    titleFontSize: titleSize,
                    subFontSize: subFontSize,
                  );
                  return Positioned(
                    top: top + 1,
                    left: left,
                    width: width,
                    height: (height - 2).clamp(16.0, double.infinity),
                    child: GestureDetector(
                      onTap: () => _openFixedScheduleDetail(
                        schedule,
                        sourceKey: fixedScheduleCardKey,
                        sourceColor: fixedSchedulePlaceholderColor,
                        sourceBorderRadius: const BorderRadius.all(
                          Radius.circular(4),
                        ),
                      ),
                      child: Container(
                        key: fixedScheduleCardKey,
                        alignment: Alignment.topLeft,
                        clipBehavior: Clip.hardEdge,
                        padding: EdgeInsets.fromLTRB(3, 2 + topOccupied, 3, 2),
                        decoration: BoxDecoration(
                          color: fixedColor,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.4),
                            width: 0.5,
                          ),
                        ),
                        child: SingleChildScrollView(
                          physics: const NeverScrollableScrollPhysics(),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                displayFixedTitle,
                                maxLines: textLayout.titleMaxLines,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.left,
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: titleSize,
                                  fontWeight: FontWeight.bold,
                                  height: 1.1,
                                ),
                              ),
                              if (textLayout.showSubtitle &&
                                  displayFixedLocation != null)
                                Padding(
                                  padding: const EdgeInsets.only(top: 1.5),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      if (locText != null &&
                                          locText.isNotEmpty) ...[
                                        Padding(
                                          padding: const EdgeInsets.only(
                                            top: 0.5,
                                            right: 1.5,
                                          ),
                                          child: Icon(
                                            Icons.location_on_rounded,
                                            size: subFontSize * 0.95,
                                            color: Colors.white.withValues(
                                              alpha: 0.85,
                                            ),
                                          ),
                                        ),
                                      ],
                                      Expanded(
                                        child: Text(
                                          displayFixedLocation,
                                          maxLines: textLayout.subMaxLines,
                                          overflow: TextOverflow.ellipsis,
                                          textAlign: TextAlign.left,
                                          style: TextStyle(
                                            color: Colors.white.withValues(
                                              alpha: 0.85,
                                            ),
                                            fontSize: subFontSize,
                                            height: 1.1,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            );
          }
        }
      }
    }

    if (_activeDataViews.contains('pomodoros')) {
      final pomodoroIndices = _pomodoroIndexCache.indicesFor(
        _pomodorosPerDay,
        _pomodorosPerDay.values.expand((items) => items),
      );
      for (int weekday = 1; weekday <= 7; weekday++) {
        final dayRecords = _pomodorosPerDay[weekday]!;
        final dayPlans = _activeDataViews.contains('plans')
            ? (_planBlocksPerDay[weekday] ?? const <TodoPlanBlock>[])
            : const <TodoPlanBlock>[];
        final planAssociationIndex =
            dayPlans.length <= 1 || dayPlans.length * dayRecords.length <= 128
            ? null
            : _PomodoroPlanDayAssociationIndex(dayPlans);
        for (var record in dayRecords) {
          DateTime pomStart = DateTime.fromMillisecondsSinceEpoch(
            record.startTime,
            isUtc: true,
          ).toLocal();
          int endMs =
              record.endTime ??
              (record.startTime + record.effectiveDuration * 1000);
          DateTime pomEnd = DateTime.fromMillisecondsSinceEpoch(
            endMs,
            isUtc: true,
          ).toLocal();

          final associatedPlans =
              planAssociationIndex?.matchingPlans(record, endMs) ??
              dayPlans
                  .where((plan) => _isRecordAssociatedWithPlan(record, plan))
                  .toList();

          List<Map<String, DateTime>> segments = [
            {'start': pomStart, 'end': pomEnd},
          ];

          for (var plan in associatedPlans) {
            DateTime planStart = DateTime.fromMillisecondsSinceEpoch(
              plan.startTime,
              isUtc: true,
            ).toLocal();
            DateTime planEnd = DateTime.fromMillisecondsSinceEpoch(
              plan.endTime,
              isUtc: true,
            ).toLocal();

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

            Color rawPomColor = colorScheme.cdtFocus;
            String pomTitle = '专注';
            String? pomTagName;

            if (record.tagUuids.isNotEmpty) {
              final tag = firstTagFor(record.tagUuids);
              if (tag != null) {
                rawPomColor = AppColorUtils.hexToColor(
                  tag.color,
                  fallback: colorScheme.cdtFocus,
                );
                pomTitle = tag.name;
                pomTagName = tag.name;
              }
            }
            final Color pomColor = _harmonizeWeekEventColor(
              rawPomColor,
              opacity: 0.78,
            );

            // 优先显示任务名，其次显示标签名
            if (record.todoTitle != null && record.todoTitle!.isNotEmpty) {
              pomTitle = record.todoTitle!;
            }
            final String? pomSubtitle =
                (pomTagName != null && pomTagName != pomTitle)
                ? pomTagName
                : null;

            final int segDurationSeconds = segments.length == 1 &&
                    record.effectiveDuration > 0
                ? record.effectiveDuration
                : ((end.millisecondsSinceEpoch - start.millisecondsSinceEpoch) /
                        1000)
                    .round();
            final String durationText =
                _formatEventDuration(segDurationSeconds);
            final String effectivePomSubtitle = pomSubtitle != null
                ? '$pomSubtitle · $durationText'
                : durationText;
            final bool isShortPomCard = height < 22.0;
            final String displayPomTitle = isShortPomCard
                ? '$pomTitle · $durationText'
                : pomTitle;
            final String? displayPomSubtitle = isShortPomCard
                ? null
                : effectivePomSubtitle;

            final pomCardKey = _getPomodoroCardKey(
              '${record.uuid}_${segmentIndex++}',
              weekday: weekday,
            );
            final pomIndex = pomodoroIndices[record]!;

            foregroundEventsPerDay[weekday]!.add(
              _TimelineEvent(
                top: top,
                bottom: top + height,
                collisionBottom: bottom,
                sourceItem: record,
                title: pomTitle,
                subtitle: effectivePomSubtitle,
                color: pomColor,
                builder: (left, width) {
                  final double fontScale = (width / (cellWidth - 2)).clamp(
                    0.4,
                    1.0,
                  );
                  final double titleFontSize = (height * 0.32 * fontScale)
                      .clamp(9.0, 10.5);
                  final double subFontSize = (height * 0.22 * fontScale).clamp(
                    8.0,
                    9.0,
                  );
                  final textLayout = _computeCardTextLayout(
                    title: displayPomTitle,
                    subtitle: displayPomSubtitle,
                    width: width,
                    height: height,
                    effectiveHeight: height,
                    titleFontSize: titleFontSize,
                    subFontSize: subFontSize,
                  );
                  final int pomMaxLines = textLayout.titleMaxLines;
                  final animationDelay = (pomIndex * 0.06).clamp(0.0, 0.5);
                  final animationProgressScale = 1.0 / (1.0 - animationDelay);

                  return Positioned(
                    top: top + 1,
                    left: left,
                    width: width,
                    height: (height - 2).clamp(18.0, double.infinity),
                    child: AnimatedBuilder(
                      animation: _courseExpandAnim,
                      builder: (ctx, child) {
                        final t =
                            ((_courseExpandAnim.value - animationDelay) *
                                    animationProgressScale)
                                .clamp(0.0, 1.0);
                        final scale = 0.7 + 0.3 * t;
                        final opacity = t;
                        return Transform.scale(
                          scale: scale,
                          child: Opacity(opacity: opacity, child: child),
                        );
                      },
                      child: GestureDetector(
                        onTap: () {
                          PageTransitions.pushFromRect(
                            context: context,
                            page: PomodoroDetailScreen(
                              record: record,
                              tags: _pomodoroTags,
                            ),
                            sourceKey: pomCardKey,
                            sourceColor: _weekLazyLoadPlaceholderColor,
                            sourceBorderRadius: const BorderRadius.all(
                              Radius.circular(4),
                            ),
                            placeholderIcon: Icons.timer_outlined,
                          );
                        },
                        child: Container(
                          key: pomCardKey,
                          alignment: Alignment.topLeft,
                          clipBehavior: Clip.hardEdge,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 3,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: pomColor,
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                              color: pomColor.withValues(alpha: 1.0),
                              width: 0.5,
                            ),
                          ),
                          child: SingleChildScrollView(
                            physics: const NeverScrollableScrollPhysics(),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  displayPomTitle,
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: titleFontSize,
                                    fontWeight: FontWeight.bold,
                                    height: 1.1,
                                  ),
                                  maxLines: pomMaxLines,
                                  textAlign: TextAlign.left,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                if (textLayout.showSubtitle &&
                                    displayPomSubtitle != null)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 1.5),
                                    child: Text(
                                      displayPomSubtitle,
                                      textAlign: TextAlign.left,
                                      style: TextStyle(
                                        color: Colors.white.withValues(
                                          alpha: 0.85,
                                        ),
                                        fontSize: subFontSize,
                                        height: 1.1,
                                      ),
                                      maxLines: textLayout.subMaxLines,
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
                },
              ),
            );
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
          final dayEnd = CalendarDateMath.addDays(dayStart, 1);
          for (final event
              in _timedDeviceCalendarEventsPerDay[weekday] ??
                  const <DeviceCalendarEvent>[]) {
            final sliceStart = event.start.isAfter(dayStart)
                ? event.start
                : dayStart;
            final sliceEnd = event.end.isBefore(dayEnd) ? event.end : dayEnd;
            if (!sliceEnd.isAfter(sliceStart)) continue;
            final startMinutes = sliceStart.hour * 60 + sliceStart.minute;
            final endMinutes = sliceEnd == dayEnd
                ? 24 * 60
                : sliceEnd.hour * 60 + sliceEnd.minute;
            if (endMinutes <= startHour * 60 || startMinutes >= endHour * 60) {
              continue;
            }
            final visibleStart = startMinutes
                .clamp(startHour * 60, endHour * 60)
                .toInt();
            final visibleEnd = endMinutes
                .clamp(startHour * 60, endHour * 60)
                .toInt();
            final top = _timeToY(
              visibleStart ~/ 60,
              visibleStart % 60,
              minuteHeight,
            );
            final bottom = _timeToY(
              visibleEnd ~/ 60,
              visibleEnd % 60,
              minuteHeight,
            );
            var height = bottom - top;
            if (height < 18.0) height = 18.0;
            final color = _harmonizeWeekEventColor(
              event.colorValue == null
                  ? colorScheme.tertiary
                  : Color(event.colorValue!),
              opacity: 0.78,
            );
            final calendarCardKey = _getDeviceCalendarCardKey(
              event.id,
              _cachedDateFormat('yyyy-MM-dd').format(dayStart),
              surface: 'week-timed',
            );
            final String? location =
                event.location?.trim().isNotEmpty == true
                ? event.location!.trim()
                : null;

            backgroundEventsPerDay[weekday]!.add(
              _TimelineEvent(
                top: top,
                bottom: top + height,
                collisionBottom: bottom,
                sourceItem: event,
                title: event.title,
                subtitle: location,
                color: color,
                builder: (left, width) {
                  final double topOccupied = topInsetForBackgroundCard(
                    weekday,
                    top,
                    top + height,
                  );
                  final double effectiveHeight = (height - topOccupied).clamp(
                    16.0,
                    double.infinity,
                  );
                  final double fontScale = (width / (cellWidth - 2)).clamp(
                    0.4,
                    1.0,
                  );
                  final double titleSize = (height * 0.28 * fontScale).clamp(
                    9.0,
                    10.5,
                  );
                  final double subFontSize = (height * 0.22 * fontScale).clamp(
                    8.0,
                    9.0,
                  );
                  final textLayout = _computeCardTextLayout(
                    title: event.title,
                    subtitle: location,
                    width: width,
                    height: height,
                    effectiveHeight: effectiveHeight,
                    titleFontSize: titleSize,
                    subFontSize: subFontSize,
                  );
                  return Positioned(
                    top: top + 1,
                    left: left,
                    width: width,
                    height: (height - 2).clamp(16.0, double.infinity),
                    child: GestureDetector(
                      onTap: () => _showDeviceCalendarEventDetail(
                        context,
                        event,
                        sourceKey: calendarCardKey,
                        sourceColor: color,
                      ),
                      child: Container(
                        key: calendarCardKey,
                        alignment: Alignment.topLeft,
                        clipBehavior: Clip.hardEdge,
                        padding: EdgeInsets.fromLTRB(3, 2 + topOccupied, 3, 2),
                        decoration: BoxDecoration(
                          color: color,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.45),
                            width: 0.5,
                          ),
                        ),
                        child: SingleChildScrollView(
                          physics: const NeverScrollableScrollPhysics(),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                event.title,
                                maxLines: textLayout.titleMaxLines,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.left,
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: titleSize,
                                  fontWeight: FontWeight.bold,
                                  height: 1.1,
                                ),
                              ),
                              if (textLayout.showSubtitle && location != null)
                                Padding(
                                  padding: const EdgeInsets.only(top: 1.5),
                                  child: Text(
                                    location,
                                    maxLines: textLayout.subMaxLines,
                                    overflow: TextOverflow.ellipsis,
                                    textAlign: TextAlign.left,
                                    style: TextStyle(
                                      color: Colors.white.withValues(
                                        alpha: 0.85,
                                      ),
                                      fontSize: subFontSize,
                                      height: 1.1,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            );
          }
        }
      }
    }

    if (_activeDataViews.contains('courses')) {
      final courseIndices = _courseIndexCache.indicesFor(
        _weekCourses,
        _weekCourses,
      );
      final bool isReviewCourse = _isReviewPerspective;
      for (var course in _weekCourses) {
        int sh = course.startTime ~/ 100;
        int sm = course.startTime % 100;
        int eh = course.endTime ~/ 100;
        int em = course.endTime % 100;

        double top = _timeToY(sh, sm, minuteHeight);
        double height = _timeToY(eh, em, minuteHeight) - top;

        final Color bgColor = isReviewCourse
            ? colorScheme.surfaceContainerHighest.withValues(
                alpha: isDark ? 0.35 : 0.65,
              )
            : _getCourseColor(course.courseName).withValues(alpha: 0.92);
        final Color courseTitleColor = isReviewCourse
            ? colorScheme.onSurfaceVariant.withValues(alpha: 0.62)
            : Colors.white;
        final Color courseSubColor = isReviewCourse
            ? colorScheme.onSurfaceVariant.withValues(alpha: 0.50)
            : Colors.white.withValues(alpha: 0.85);
        final cardKey = _getCourseCardKey(
          course.courseName,
          course.weekday,
          course.startTime,
          courseUuid: course.uuid,
        );
        final courseIndex = courseIndices[course]!;
        final String? courseSubtitle = course.roomName.trim().isNotEmpty
            ? course.roomName.trim()
            : null;

        backgroundEventsPerDay[course.weekday]!.add(
          _TimelineEvent(
            top: top,
            bottom: top + height,
            sourceItem: course,
            title: course.courseName,
            subtitle: courseSubtitle,
            color: bgColor,
            builder: (left, width) {
              final double topOccupied = topInsetForBackgroundCard(
                course.weekday,
                top,
                top + height,
              );
              final double effectiveHeight = (height - topOccupied).clamp(
                16.0,
                double.infinity,
              );
              final double fontScale = (width / (cellWidth - 2)).clamp(
                0.4,
                1.0,
              );
              final double titleFontSize = (height * 0.32 * fontScale).clamp(
                9.0,
                10.5,
              );
              final double subFontSize = (height * 0.22 * fontScale).clamp(
                8.0,
                9.0,
              );
              final textLayout = _computeCardTextLayout(
                title: course.courseName,
                subtitle: courseSubtitle,
                width: width,
                height: height,
                effectiveHeight: effectiveHeight,
                titleFontSize: titleFontSize,
                subFontSize: subFontSize,
              );
              final bool showRoom =
                  textLayout.showSubtitle && courseSubtitle != null;
              final int courseMaxLines = textLayout.titleMaxLines;
              final animationDelay = (courseIndex * 0.06).clamp(0.0, 0.5);
              final animationProgressScale = 1.0 / (1.0 - animationDelay);

              return Positioned(
                top: top + 1,
                left: left,
                width: width,
                height: height - 2,
                child: AnimatedBuilder(
                  animation: _courseExpandAnim,
                  builder: (ctx, child) {
                    final t =
                        ((_courseExpandAnim.value - animationDelay) *
                                animationProgressScale)
                            .clamp(0.0, 1.0);
                    final scale = 0.7 + 0.3 * t;
                    final opacity = t;
                    return Transform.scale(
                      scale: scale,
                      child: Opacity(opacity: opacity, child: child),
                    );
                  },
                  child: GestureDetector(
                    onTap: () {
                      PageTransitions.pushFromRect(
                        context: context,
                        page: CourseDetailScreen(
                          course: course,
                          courseSchedule: _allCourses,
                        ),
                        sourceKey: cardKey,
                        sourceColor: _weekLazyLoadPlaceholderColor,
                        sourceBorderRadius: const BorderRadius.all(
                          Radius.circular(4),
                        ),
                        placeholderIcon: Icons.calendar_month_rounded,
                      );
                    },
                    child: Container(
                      key: cardKey,
                      alignment: Alignment.topLeft,
                      clipBehavior: Clip.hardEdge,
                      padding: EdgeInsets.fromLTRB(3, 2 + topOccupied, 3, 2),
                      decoration: BoxDecoration(
                        color: bgColor,
                        borderRadius: BorderRadius.circular(4),
                        border: isReviewCourse
                            ? Border.all(
                                color: colorScheme.outlineVariant.withValues(
                                  alpha: 0.35,
                                ),
                                width: 0.5,
                              )
                            : null,
                        boxShadow: isReviewCourse
                            ? null
                            : const [
                                BoxShadow(
                                  color: Colors.black12,
                                  blurRadius: 1,
                                  offset: Offset(0, 1),
                                ),
                              ],
                      ),
                      child: SingleChildScrollView(
                        physics: const NeverScrollableScrollPhysics(),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              course.courseName,
                              style: TextStyle(
                                color: courseTitleColor,
                                fontSize: titleFontSize,
                                fontWeight: FontWeight.bold,
                                height: 1.1,
                              ),
                              maxLines: courseMaxLines,
                              textAlign: TextAlign.left,
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (showRoom)
                              Padding(
                                padding: const EdgeInsets.only(top: 1.5),
                                child: Text(
                                  courseSubtitle,
                                  style: TextStyle(
                                    color: courseSubColor,
                                    fontSize: subFontSize,
                                    height: 1.1,
                                  ),
                                  maxLines: textLayout.subMaxLines,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.left,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        );
      }
    }

    // 🚀 先绘制底层背景（课程、固定日程、规划块、手机日历），占满单日列宽，不与前景碎待办/专注记录平分列宽
    _layoutAndRenderEventLayer(
      layerEventsPerDay: backgroundEventsPerDay,
      cellWidth: cellWidth,
      children: children,
      allowAggregation: true,
    );

    // 🚀 再绘制前景层（日内待办、番茄钟记录、时间日志），当计算卡片宽度 < 24px 时自动折叠为叠牌 +N 角标
    _layoutAndRenderEventLayer(
      layerEventsPerDay: foregroundEventsPerDay,
      cellWidth: cellWidth,
      children: children,
      allowAggregation: true,
    );

    DateTime now = DateTime.now();
    if (now.hour >= startHour && now.hour <= endHour) {
      if (_semesterMonday != null) {
        DateTime currentMonday = CalendarDateMath.addDays(
          _semesterMonday!,
          (_currentWeek - 1) * 7,
        );
        int diffDays = CalendarDateMath.daysBetween(currentMonday, now);

        if (diffDays >= 0 && diffDays <= 6) {
          double nowY = _timeToY(now.hour, now.minute, minuteHeight);
          double lineLeft = timeColumnWidth + diffDays * cellWidth;

          children.add(
            Positioned(
              top: nowY,
              left: timeColumnWidth,
              width: cellWidth * 7,
              height: 1,
              child: RepaintBoundary(
                child: CustomPaint(
                  painter: _CurrentTimeRulePainter(
                    animation: _pulseAnimation,
                    color: focusColor,
                  ),
                ),
              ),
            ),
          );
          children.add(
            Positioned(
              top: nowY - 1,
              left: lineLeft,
              width: cellWidth,
              height: 2,
              child: RepaintBoundary(
                child: CustomPaint(
                  painter: _CurrentTimeMarkerPainter(
                    animation: _pulseAnimation,
                    color: focusColor,
                  ),
                ),
              ),
            ),
          );
        }
      }
    }

    return Stack(children: children);
  }
}

/// Paint pulse updates directly so the grid avoids rebuilding these lines
/// on each animation tick.
class _CurrentTimeRulePainter extends CustomPainter {
  _CurrentTimeRulePainter({required this.animation, required this.color})
    : super(repaint: animation);

  final Animation<double> animation;
  final Color color;
  final Paint _paint = Paint();

  @override
  void paint(Canvas canvas, Size size) {
    _paint.color = color.withValues(alpha: 0.3 + 0.2 * animation.value);
    canvas.drawRect(Offset.zero & size, _paint);
  }

  @override
  bool shouldRepaint(covariant _CurrentTimeRulePainter oldDelegate) =>
      oldDelegate.animation != animation || oldDelegate.color != color;
}

class _CurrentTimeMarkerPainter extends CustomPainter {
  _CurrentTimeMarkerPainter({required this.animation, required this.color})
    : super(repaint: animation);

  final Animation<double> animation;
  final Color color;
  final Paint _fillPaint = Paint();
  late final Paint _shadowPaint = BoxShadow(
    color: Colors.transparent,
    blurRadius: 6,
    spreadRadius: 1,
  ).toPaint();

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final progress = animation.value;
    _shadowPaint.color = color.withValues(alpha: 0.4 * progress);
    canvas.drawRect(rect.inflate(1), _shadowPaint);
    _fillPaint.color = color.withValues(alpha: 0.7 + 0.3 * progress);
    canvas.drawRect(rect, _fillPaint);
  }

  @override
  bool shouldRepaint(covariant _CurrentTimeMarkerPainter oldDelegate) =>
      oldDelegate.animation != animation || oldDelegate.color != color;
}
