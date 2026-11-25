part of '../time_log_screen.dart';

// ══════════════════════════════════════════════════════════
// 视图切换 Tab
// ══════════════════════════════════════════════════════════
class _ViewTab extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _ViewTab({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 5),
        decoration: BoxDecoration(
          color: selected ? accent.withValues(alpha: 0.12) : Colors.transparent,
          border: Border.all(
            color: selected
                ? accent.withValues(alpha: 0.4)
                : Colors.transparent,
          ),
          borderRadius: BorderRadius.circular(_timeLogActionChipRadius),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
            color: selected ? accent : _TC.textSub(context),
          ),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════
// 周视图
// ══════════════════════════════════════════════════════════
class _WeekView extends StatefulWidget {
  final DateTime weekStart;
  final List<TimeLogItem> logs;
  final List<PomodoroRecord> pomodoros;
  final List<TimeLogMappedSchedule> schedules;
  final List<PomodoroTag> tags;
  final void Function(DateTime) onDayTap;
  final void Function(PomodoroTag) onTagTap;
  final VoidCallback onManageTags, onAddLog;
  final void Function(PomodoroRecord) onPomodoroTap;
  final void Function(TimeLogItem) onTimeLogTap;
  final void Function(TimeLogMappedSchedule) onScheduleTap;
  final void Function(List<TimeLogMappedSchedule>, DateTime)
  onAggregatedSchedulesTap;
  final String username;

  const _WeekView({
    required this.weekStart,
    required this.logs,
    required this.pomodoros,
    this.schedules = const [],
    required this.tags,
    required this.onDayTap,
    required this.onTagTap,
    required this.onManageTags,
    required this.onAddLog,
    required this.onPomodoroTap,
    required this.onTimeLogTap,
    required this.onScheduleTap,
    required this.onAggregatedSchedulesTap,
    required this.username,
  });

  @override
  State<_WeekView> createState() => _WeekViewState();
}

class _WeekViewData {
  const _WeekViewData({
    required this.days,
    required this.todayMinutes,
    required this.dayStartMs,
    required this.dayEndMs,
    required this.logsByDay,
    required this.pomodorosByDay,
    required this.schedulesByDay,
    required this.minutesByDay,
    required this.minutesByTag,
  });

  final List<DateTime> days;
  final int todayMinutes;
  final List<int> dayStartMs;
  final List<int> dayEndMs;
  final List<List<TimeLogItem>> logsByDay;
  final List<List<PomodoroRecord>> pomodorosByDay;
  final List<List<TimeLogMappedSchedule>> schedulesByDay;
  final List<int> minutesByDay;
  final Map<String, int> minutesByTag;
}

class _WeekViewState extends State<_WeekView>
    with SingleTickerProviderStateMixin {
  late AnimationController _heatAnimCtrl;
  late Animation<double> _heatAnim;
  List<TimeLogItem>? _cachedLogs;
  List<PomodoroRecord>? _cachedPomodoros;
  List<TimeLogMappedSchedule>? _cachedSchedules;
  List<PomodoroTag>? _cachedTags;
  DateTime? _cachedWeekStart;
  int? _cachedTodayStartMs;
  int? _cachedTodayEndMs;
  _WeekViewData? _cachedWeekData;

  @override
  void initState() {
    super.initState();
    _heatAnimCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _heatAnim = _heatAnimCtrl.drive(CurveTween(curve: Curves.easeOutCubic));
    _heatAnimCtrl.forward();
  }

  @override
  void didUpdateWidget(_WeekView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.weekStart != widget.weekStart ||
        oldWidget.logs.length != widget.logs.length ||
        oldWidget.pomodoros.length != widget.pomodoros.length ||
        oldWidget.schedules.length != widget.schedules.length) {
      _heatAnimCtrl.reset();
      _heatAnimCtrl.forward();
    }
  }

  @override
  void dispose() {
    _heatAnimCtrl.dispose();
    super.dispose();
  }

  _WeekViewData _buildWeekViewData(
    List<DateTime> days,
    DateTime todayStart,
    DateTime todayEnd,
  ) {
    final dayStartMs = <int>[];
    final dayEndMs = <int>[];
    for (final day in days) {
      final range = CalendarDateMath.dayRange(day);
      dayStartMs.add(range.start.millisecondsSinceEpoch);
      dayEndMs.add(range.endExclusive.millisecondsSinceEpoch);
    }
    final logsByDay = List.generate(days.length, (_) => <TimeLogItem>[]);
    final pomodorosByDay = List.generate(
      days.length,
      (_) => <PomodoroRecord>[],
    );
    final schedulesByDay = List.generate(
      days.length,
      (_) => <TimeLogMappedSchedule>[],
    );
    final minutesByDay = List<int>.filled(days.length, 0);
    final visibleTagUuids = widget.tags.map((tag) => tag.uuid).toSet();
    final minutesByTag = <String, int>{};
    final seenTagUuids = <String>{};
    final weekStartMs = dayStartMs.first;
    final weekEndMs = dayEndMs.last;
    final todayStartMs = todayStart.millisecondsSinceEpoch;
    final todayEndMs = todayEnd.millisecondsSinceEpoch;
    var todayMinutes = 0;

    int firstDayEndingAfter(int instantMs) {
      var low = 0;
      var high = dayEndMs.length;
      while (low < high) {
        final middle = (low + high) ~/ 2;
        if (dayEndMs[middle] <= instantMs) {
          low = middle + 1;
        } else {
          high = middle;
        }
      }
      return low;
    }

    for (final log in widget.logs) {
      if (log.endTime > weekStartMs && log.startTime < weekEndMs) {
        final overlapMinutes = TimeLogRangeMath.overlapMinutes(
          intervalStartMs: log.startTime,
          intervalEndMs: log.endTime,
          rangeStartMs: weekStartMs,
          rangeEndMs: weekEndMs,
        );
        seenTagUuids.clear();
        for (final uuid in log.tagUuids) {
          if (!visibleTagUuids.contains(uuid) || !seenTagUuids.add(uuid)) {
            continue;
          }
          minutesByTag[uuid] = (minutesByTag[uuid] ?? 0) + overlapMinutes;
        }
      }
      if (log.endTime > todayStartMs && log.startTime < todayEndMs) {
        todayMinutes += TimeLogRangeMath.overlapMinutes(
          intervalStartMs: log.startTime,
          intervalEndMs: log.endTime,
          rangeStartMs: todayStartMs,
          rangeEndMs: todayEndMs,
        );
      }
      for (
        var dayIndex = firstDayEndingAfter(log.startTime);
        dayIndex < days.length && dayStartMs[dayIndex] < log.endTime;
        dayIndex++
      ) {
        logsByDay[dayIndex].add(log);
        minutesByDay[dayIndex] += TimeLogRangeMath.overlapMinutes(
          intervalStartMs: log.startTime,
          intervalEndMs: log.endTime,
          rangeStartMs: dayStartMs[dayIndex],
          rangeEndMs: dayEndMs[dayIndex],
        );
      }
    }
    for (final pomodoro in widget.pomodoros) {
      final endMs =
          pomodoro.endTime ??
          (pomodoro.startTime + pomodoro.effectiveDuration * 1000);
      if (pomodoro.startTime < weekEndMs && endMs > weekStartMs) {
        final durationMinutes = pomodoro.effectiveDuration ~/ 60;
        seenTagUuids.clear();
        for (final uuid in pomodoro.tagUuids) {
          if (!visibleTagUuids.contains(uuid) || !seenTagUuids.add(uuid)) {
            continue;
          }
          minutesByTag[uuid] = (minutesByTag[uuid] ?? 0) + durationMinutes;
        }
      }
      if (pomodoro.startTime < todayEndMs && endMs > todayStartMs) {
        todayMinutes += pomodoro.effectiveDuration ~/ 60;
      }
      for (
        var dayIndex = firstDayEndingAfter(pomodoro.startTime);
        dayIndex < days.length && dayStartMs[dayIndex] < endMs;
        dayIndex++
      ) {
        pomodorosByDay[dayIndex].add(pomodoro);
        minutesByDay[dayIndex] += pomodoro.effectiveDuration ~/ 60;
      }
    }

    for (final schedule in widget.schedules) {
      for (
        var dayIndex = firstDayEndingAfter(schedule.startTime);
        dayIndex < days.length && dayStartMs[dayIndex] < schedule.endTime;
        dayIndex++
      ) {
        schedulesByDay[dayIndex].add(schedule);
      }
    }

    return _WeekViewData(
      days: days,
      todayMinutes: todayMinutes,
      dayStartMs: dayStartMs,
      dayEndMs: dayEndMs,
      logsByDay: logsByDay,
      pomodorosByDay: pomodorosByDay,
      schedulesByDay: schedulesByDay,
      minutesByDay: minutesByDay,
      minutesByTag: minutesByTag,
    );
  }

  _WeekViewData _weekViewDataFor(
    DateTime weekStart,
    DateTime todayStart,
    DateTime todayEnd,
  ) {
    final normalizedWeekStart = CalendarDateMath.weekRange(weekStart).start;
    final todayStartMs = todayStart.millisecondsSinceEpoch;
    final todayEndMs = todayEnd.millisecondsSinceEpoch;
    final cached = _cachedWeekData;
    if (cached != null &&
        identical(_cachedLogs, widget.logs) &&
        identical(_cachedPomodoros, widget.pomodoros) &&
        identical(_cachedSchedules, widget.schedules) &&
        identical(_cachedTags, widget.tags) &&
        _cachedWeekStart == normalizedWeekStart &&
        _cachedTodayStartMs == todayStartMs &&
        _cachedTodayEndMs == todayEndMs) {
      return cached;
    }

    final days = List<DateTime>.generate(
      7,
      (index) => CalendarDateMath.addDays(normalizedWeekStart, index),
      growable: false,
    );
    final data = _buildWeekViewData(days, todayStart, todayEnd);
    _cachedLogs = widget.logs;
    _cachedPomodoros = widget.pomodoros;
    _cachedSchedules = widget.schedules;
    _cachedTags = widget.tags;
    _cachedWeekStart = normalizedWeekStart;
    _cachedTodayStartMs = todayStartMs;
    _cachedTodayEndMs = todayEndMs;
    return _cachedWeekData = data;
  }

  @override
  Widget build(BuildContext context) {
    final todayRange = CalendarDateMath.dayRange(DateTime.now());
    final weekData = _weekViewDataFor(
      widget.weekStart,
      todayRange.start,
      todayRange.endExclusive,
    );
    final days = weekData.days;

    return LayoutBuilder(
      builder: (ctx, outer) {
        final isWide = outer.maxWidth >= 720;
        return Column(
          children: [
            _buildTopBar(ctx, weekData.todayMinutes),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _buildGrid(
                      ctx,
                      days,
                      outer.maxWidth - (isWide ? 160.0 : 0),
                      weekData,
                    ),
                  ),
                  if (isWide) _buildTagSidebar(ctx, weekData.minutesByTag),
                ],
              ),
            ),
            if (!isWide) _buildTagChips(ctx, weekData.minutesByTag),
          ],
        );
      },
    );
  }

  Widget _buildTopBar(BuildContext ctx, int todayMin) {
    final useFloating = floatingBottomBarShouldFloat(ctx);
    final child = Container(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
      decoration: useFloating ? null : BoxDecoration(color: _TC.topBar(ctx)),
      child: Row(
        children: [
          // 今日统计
          _TopBarChip(
            label: '今日 ${todayMin}min',
            color: Theme.of(ctx).colorScheme.cdtSuccess,
            ctx: ctx,
          ),
          const Spacer(),
          SizedBox(
            key: timeLogTagKey,
            child: _TopBarChip(
              label: '标签',
              icon: Icons.label_outline,
              color: _TC.textSub(ctx).withValues(alpha: 0.8),
              ctx: ctx,
              onTap: widget.onManageTags,
            ),
          ),
          const SizedBox(width: 6),
          SizedBox(
            key: timeLogAddKey,
            child: _TopBarChip(
              label: '补录',
              icon: Icons.edit_calendar_outlined,
              color: Theme.of(ctx).colorScheme.primary,
              ctx: ctx,
              onTap: widget.onAddLog,
              filled: true,
            ),
          ),
          const SizedBox(width: 6),
          Builder(
            builder: (bCtx) => _TopBarChip(
              label: '恢复',
              icon: Icons.cloud_download_outlined,
              color: Theme.of(ctx).colorScheme.cdtSuccess,
              ctx: ctx,
              onTap: () async {
                await StorageService.resetSyncTime(widget.username);
                await StorageService.syncData(
                  widget.username,
                  forceFullSync: true,
                  syncTodos: true,
                  syncCountdowns: true,
                  syncTimeLogs: true,
                );
                if (bCtx.mounted) {
                  AppSnackBars.success(
                    bCtx,
                    '🎉 数据强拉成功！请点击右上角的【刷新图标 ↻】查看界面',
                    duration: const Duration(seconds: 4),
                  );
                }
              },
            ),
          ),
        ],
      ),
    );
    if (useFloating) {
      // The weekly calendar header sits directly below this action row. Keep
      // both on the same page surface so a floating glass capsule does not
      // read as a detached card pasted onto the grid.
      return Container(
        height: 52,
        margin: const EdgeInsets.only(top: 8),
        alignment: Alignment.center,
        color: _TC.topBar(ctx),
        child: child,
      );
    }

    return FloatingGlassControl(
      height: 52,
      borderRadius: 0,
      mobilePortraitOnly: true,
      child: child,
    );
  }

  Widget _buildGrid(
    BuildContext ctx,
    List<DateTime> days,
    double availW,
    _WeekViewData weekData,
  ) {
    const totalW = kWeekTimeW + kWeekDayW * 7;
    final scale = availW / totalW;
    final tW = kWeekTimeW * scale;
    final dW = kWeekDayW * scale;
    final colorScheme = Theme.of(ctx).colorScheme;
    final accent = colorScheme.primary;
    final isDark = Theme.of(ctx).brightness == Brightness.dark;

    return Column(
      children: [
        Container(
          height: 52,
          color: _TC.topBar(ctx),
          child: Row(
            children: [
              SizedBox(width: tW),
              ...List.generate(7, (i) {
                final d = days[i];
                final isToday = AppTimeFormats.isSameDay(d, DateTime.now());
                final dm = weekData.minutesByDay[i];
                return GestureDetector(
                  onTap: () => widget.onDayTap(d),
                  child: Container(
                    width: dW,
                    height: 52,
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    decoration: BoxDecoration(
                      color: isToday
                          ? accent.withValues(alpha: isDark ? 0.16 : 0.12)
                          : null,
                      borderRadius: isToday ? BorderRadius.circular(6) : null,
                      border: isToday
                          ? Border.all(
                              color: accent.withValues(alpha: 0.4),
                              width: 1,
                            )
                          : Border(
                              right: BorderSide(
                                color: _TC.divider(ctx).withValues(alpha: 0.2),
                              ),
                            ),
                    ),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                AppTimeFormats.weekdayLabelsZh[i],
                                style: TextStyle(
                                  fontSize: 9.5,
                                  color: isToday ? accent : _TC.textHint(ctx),
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.5,
                                ),
                              ),
                              if (isToday) ...[
                                const SizedBox(width: 2),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 3,
                                    vertical: 0.5,
                                  ),
                                  decoration: BoxDecoration(
                                    color: accent,
                                    borderRadius: BorderRadius.circular(3),
                                  ),
                                  child: Text(
                                    '今',
                                    style: TextStyle(
                                      color: colorScheme.onPrimary,
                                      fontSize: 7.5,
                                      fontWeight: FontWeight.bold,
                                      height: 1.1,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 1),
                          isToday
                              ? Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 5,
                                    vertical: 0.5,
                                  ),
                                  decoration: BoxDecoration(
                                    color: accent,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    '${d.day}',
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: colorScheme.onPrimary,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                )
                              : Text(
                                  '${d.day}',
                                  style: TextStyle(
                                    fontSize: 15,
                                    color: _TC.textSub(ctx),
                                    fontWeight: FontWeight.w400,
                                  ),
                                ),
                          if (dm > 0)
                            Text(
                              '${dm}m',
                              style: TextStyle(
                                fontSize: 8,
                                color: accent.withValues(alpha: 0.7),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                );
              }),
            ],
          ),
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (ctx2, gc) {
              final hourH = gc.maxHeight / 24;
              final totalH = hourH * 24;
              return SizedBox(
                height: totalH,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: tW,
                      height: totalH,
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: List.generate(
                          24,
                          (h) => Positioned(
                            top: h * hourH - 8,
                            right: 4,
                            child: Text(
                              h.toString().padLeft(2, '0'),
                              style: TextStyle(
                                fontSize: (tW * 0.16).clamp(7.0, 11.0),
                                color: _TC.timeLabel(ctx2, major: h % 6 == 0),
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    ...List.generate(days.length, (dayIndex) {
                      final ds = weekData.dayStartMs[dayIndex];
                      final de = weekData.dayEndMs[dayIndex];
                      final dLogs = weekData.logsByDay[dayIndex];
                      final dPoms = weekData.pomodorosByDay[dayIndex];
                      final dSchedules = weekData.schedulesByDay[dayIndex];
                      final isToday = AppTimeFormats.isSameDay(
                        days[dayIndex],
                        DateTime.now(),
                      );
                      return SizedBox(
                        width: dW,
                        height: totalH,
                        child: Stack(
                          children: [
                            if (isToday)
                              Positioned.fill(
                                child: IgnorePointer(
                                  child: Container(
                                    color: accent.withValues(
                                      alpha: isDark ? 0.07 : 0.038,
                                    ),
                                  ),
                                ),
                              ),
                            RepaintBoundary(
                              child: CustomPaint(
                                size: Size(dW, totalH),
                                painter: _WeekGridPainter(
                                  hourH: hourH,
                                  majorLineColor: colorScheme.outlineVariant,
                                  minorLineColor: colorScheme.outlineVariant
                                      .withValues(alpha: isDark ? 0.28 : 0.45),
                                ),
                              ),
                            ),
                            RepaintBoundary(
                              child: CustomPaint(
                                size: Size(dW, totalH),
                                painter: _WeekColPainter(
                                  dayLogs: dLogs,
                                  dayPoms: dPoms,
                                  daySchedules: dSchedules,
                                  tags: widget.tags,
                                  dayStartMs: ds,
                                  dayEndMs: de,
                                  isDark: isDark,
                                  hourH: hourH,
                                  animation: _heatAnim,
                                  focusColor: colorScheme.cdtFocus,
                                  logColor: colorScheme.cdtInfo,
                                ),
                              ),
                            ),
                            ...clusterTimeLogSchedules(dSchedules, ds, de).map((
                              cluster,
                            ) {
                              final top =
                                  (cluster.startTime - ds) / 3600000 * hourH;
                              final h =
                                  ((cluster.endTime - cluster.startTime) /
                                          3600000 *
                                          hourH)
                                      .clamp(3.0, 9999.0);
                              return Positioned(
                                top: top,
                                left: 0,
                                right: 0,
                                height: h,
                                child: GestureDetector(
                                  onTap: () {
                                    if (cluster.isAggregated) {
                                      widget.onAggregatedSchedulesTap(
                                        cluster.schedules,
                                        days[dayIndex],
                                      );
                                    } else {
                                      widget.onScheduleTap(cluster.primary);
                                    }
                                  },
                                  behavior: HitTestBehavior.opaque,
                                  child: const SizedBox.expand(),
                                ),
                              );
                            }),
                            ...dPoms.map((pom) {
                              final pe =
                                  pom.endTime ??
                                  (pom.startTime +
                                      pom.effectiveDuration * 1000);
                              final rs = max(pom.startTime, ds);
                              final re = min(pe, de);
                              final top = (rs - ds) / 3600000 * hourH;
                              final h = ((re - rs) / 3600000 * hourH).clamp(
                                3.0,
                                9999.0,
                              );
                              return Positioned(
                                top: top,
                                left: 0,
                                right: 0,
                                height: h,
                                child: GestureDetector(
                                  onTap: () => widget.onPomodoroTap(pom),
                                  behavior: HitTestBehavior.opaque,
                                  child: const SizedBox.expand(),
                                ),
                              );
                            }),
                            ...dLogs.map((log) {
                              final rs = max(log.startTime, ds);
                              final re = min(log.endTime, de);
                              final top = (rs - ds) / 3600000 * hourH;
                              final h = ((re - rs) / 3600000 * hourH).clamp(
                                3.0,
                                9999.0,
                              );
                              return Positioned(
                                top: top,
                                left: 0,
                                right: 0,
                                height: h,
                                child: GestureDetector(
                                  onTap: () => widget.onTimeLogTap(log),
                                  behavior: HitTestBehavior.opaque,
                                  child: const SizedBox.expand(),
                                ),
                              );
                            }),
                          ],
                        ),
                      );
                    }),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildTagSidebar(
    BuildContext ctx,
    Map<String, int> minutesByTag,
  ) => SizedBox(
    width: 160,
    child: OptionalLiquidGlassSheet(
      fallbackDecoration: BoxDecoration(
        color: _TC.card(ctx),
        border: Border(left: BorderSide(color: _TC.divider(ctx))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 14, 12, 8),
            child: Text(
              '本周标签',
              style: TextStyle(
                fontSize: 10,
                color: _TC.textHint(ctx),
                fontWeight: FontWeight.w700,
                letterSpacing: 1.5,
              ),
            ),
          ),
          Expanded(
            child: ListView.builder(
              findChildIndexCallback: (Key key) {
                if (key is ValueKey<String>) {
                  final uuid = key.value;
                  final index = widget.tags.indexWhere((t) => t.uuid == uuid);
                  return index != -1 ? index : null;
                }
                return null;
              },
              itemCount: widget.tags.length,
              itemBuilder: (context, index) {
                final t = widget.tags[index];
                final tw = minutesByTag[t.uuid] ?? 0;
                final c = hexColor(t.color);
                return RepaintBoundary(
                  key: ValueKey<String>(t.uuid),
                  child: GestureDetector(
                    onTap: () => widget.onTagTap(t),
                    child: Container(
                      margin: const EdgeInsets.fromLTRB(8, 0, 8, 6),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: c.withValues(alpha: 0.07),
                        border: Border.all(color: c.withValues(alpha: 0.25)),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: c,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  t.name,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: c,
                                    fontWeight: FontWeight.w700,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                Text(
                                  '${(tw / 60).toStringAsFixed(1)}h',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: _TC.text(ctx),
                                    fontWeight: FontWeight.w700,
                                  ),
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
              padding: const EdgeInsets.only(bottom: 8),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _buildTagChips(BuildContext ctx, Map<String, int> minutesByTag) =>
      Container(
        height: 56,
        color: _TC.topBar(ctx),
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          findChildIndexCallback: (Key key) {
            if (key is ValueKey<String>) {
              final uuid = key.value;
              final index = widget.tags.indexWhere((t) => t.uuid == uuid);
              return index != -1 ? index : null;
            }
            return null;
          },
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          itemCount: widget.tags.length,
          itemBuilder: (context, index) {
            final t = widget.tags[index];
            final tw = minutesByTag[t.uuid] ?? 0;
            final c = hexColor(t.color);
            return RepaintBoundary(
              key: ValueKey<String>(t.uuid),
              child: GestureDetector(
                onTap: () => widget.onTagTap(t),
                child: Container(
                  margin: const EdgeInsets.only(right: 8),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: c.withValues(alpha: 0.08),
                    border: Border.all(color: c.withValues(alpha: 0.3)),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        t.name,
                        style: TextStyle(
                          fontSize: 9,
                          color: c,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.8,
                        ),
                      ),
                      Text(
                        '${(tw / 60).toStringAsFixed(1)}h',
                        style: TextStyle(
                          fontSize: 11,
                          color: _TC.text(ctx),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      );
}
