part of '../time_log_screen.dart';

// ══════════════════════════════════════════════════════════
// 日视图 — 网格（24行×5分钟格）
// ══════════════════════════════════════════════════════════
class _DayGridView extends StatefulWidget {
  final DateTime date;
  final List<TimeLogItem> logs;
  final List<PomodoroRecord> pomodoros;
  final List<TimeLogMappedSchedule> schedules;
  final List<PomodoroTag> tags;
  final void Function(PomodoroRecord) onPomodoroTap;
  final void Function(TimeLogItem) onTimeLogTap;
  final void Function(TimeLogMappedSchedule) onScheduleTap;
  final VoidCallback onSwitchEdit;

  const _DayGridView({
    required this.date,
    required this.logs,
    required this.pomodoros,
    this.schedules = const [],
    required this.tags,
    required this.onPomodoroTap,
    required this.onTimeLogTap,
    required this.onScheduleTap,
    required this.onSwitchEdit,
  });

  @override
  State<_DayGridView> createState() => _DayGridViewState();
}

class _DayGridViewState extends State<_DayGridView> {
  List<TimeLogItem>? _dayLogsSource;
  List<PomodoroRecord>? _dayPomodorosSource;
  List<TimeLogMappedSchedule>? _daySchedulesSource;
  int? _dayDataStartMs;
  int? _dayDataEndMs;
  List<TimeLogItem> _dayLogs = const [];
  List<PomodoroRecord> _dayPomodoros = const [];
  List<TimeLogMappedSchedule> _daySchedules = const [];
  List<MapEntry<String, int>> _sortedTagMinutes = const [];
  List<PomodoroTag>? _tagIndexSource;
  List<PomodoroTag>? _tagIndexSnapshot;
  Map<String, PomodoroTag> _tagsByUuid = const {};
  Map<String, int> _tagIndicesByUuid = const {};
  int _dayLogMinutes = 0;
  int _dayPomodoroMinutes = 0;
  int _dayScheduleMinutes = 0;

  void _ensureTagIndex() {
    final cachedTags = _tagIndexSnapshot;
    if (identical(_tagIndexSource, widget.tags) &&
        cachedTags != null &&
        cachedTags.length == widget.tags.length) {
      var tagsUnchanged = true;
      for (var index = 0; index < widget.tags.length; index++) {
        if (!identical(cachedTags[index], widget.tags[index])) {
          tagsUnchanged = false;
          break;
        }
      }
      if (tagsUnchanged) return;
    }

    final tagsByUuid = <String, PomodoroTag>{};
    final tagIndicesByUuid = <String, int>{};
    for (var index = 0; index < widget.tags.length; index++) {
      final tag = widget.tags[index];
      tagsByUuid.putIfAbsent(tag.uuid, () => tag);
      tagIndicesByUuid.putIfAbsent(tag.uuid, () => index);
    }
    _tagIndexSource = widget.tags;
    _tagIndexSnapshot = List<PomodoroTag>.of(widget.tags, growable: false);
    _tagsByUuid = tagsByUuid;
    _tagIndicesByUuid = tagIndicesByUuid;
  }

  void _ensureDayData(int dayStartMs, int dayEndMs) {
    if (identical(_dayLogsSource, widget.logs) &&
        identical(_dayPomodorosSource, widget.pomodoros) &&
        identical(_daySchedulesSource, widget.schedules) &&
        _dayDataStartMs == dayStartMs &&
        _dayDataEndMs == dayEndMs) {
      return;
    }

    final dayLogs = <TimeLogItem>[];
    final dayPomodoros = <PomodoroRecord>[];
    final daySchedules = <TimeLogMappedSchedule>[];
    final tagMinutesByUuid = <String, int>{};
    var logMinutes = 0;
    for (final log in widget.logs) {
      if (log.endTime <= dayStartMs || log.startTime >= dayEndMs) continue;
      dayLogs.add(log);
      final overlapMinutes = TimeLogRangeMath.overlapMinutes(
        intervalStartMs: log.startTime,
        intervalEndMs: log.endTime,
        rangeStartMs: dayStartMs,
        rangeEndMs: dayEndMs,
      );
      logMinutes += overlapMinutes;
      for (final uuid in log.tagUuids) {
        tagMinutesByUuid[uuid] = (tagMinutesByUuid[uuid] ?? 0) + overlapMinutes;
      }
    }

    var pomodoroMinutes = 0;
    for (final pomodoro in widget.pomodoros) {
      final endMs =
          pomodoro.endTime ??
          (pomodoro.startTime + pomodoro.effectiveDuration * 1000);
      if (endMs <= dayStartMs || pomodoro.startTime >= dayEndMs) continue;
      dayPomodoros.add(pomodoro);
      final durationMinutes = pomodoro.effectiveDuration ~/ 60;
      pomodoroMinutes += durationMinutes;
      for (final uuid in pomodoro.tagUuids) {
        tagMinutesByUuid[uuid] =
            (tagMinutesByUuid[uuid] ?? 0) + durationMinutes;
      }
    }

    var scheduleMinutes = 0;
    for (final schedule in widget.schedules) {
      if (schedule.endTime <= dayStartMs || schedule.startTime >= dayEndMs) {
        continue;
      }
      daySchedules.add(schedule);
      final overlapMinutes = TimeLogRangeMath.overlapMinutes(
        intervalStartMs: schedule.startTime,
        intervalEndMs: schedule.endTime,
        rangeStartMs: dayStartMs,
        rangeEndMs: dayEndMs,
      );
      scheduleMinutes += overlapMinutes;
    }

    _dayLogsSource = widget.logs;
    _dayPomodorosSource = widget.pomodoros;
    _daySchedulesSource = widget.schedules;
    _dayDataStartMs = dayStartMs;
    _dayDataEndMs = dayEndMs;
    _dayLogs = dayLogs;
    _dayPomodoros = dayPomodoros;
    _daySchedules = daySchedules;
    _sortedTagMinutes = tagMinutesByUuid.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    _dayLogMinutes = logMinutes;
    _dayPomodoroMinutes = pomodoroMinutes;
    _dayScheduleMinutes = scheduleMinutes;
  }

  @override
  Widget build(BuildContext context) {
    final dayRange = CalendarDateMath.dayRange(widget.date);
    final ds = dayRange.start.millisecondsSinceEpoch;
    final de = dayRange.endExclusive.millisecondsSinceEpoch;
    _ensureDayData(ds, de);
    _ensureTagIndex();
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final colorScheme = theme.colorScheme;
    final totalMin = _dayLogMinutes + _dayPomodoroMinutes;

    return Column(
      children: [
        _buildSummary(
          context,
          totalMin,
          _dayLogMinutes,
          _dayPomodoroMinutes,
          _dayScheduleMinutes,
          _sortedTagMinutes,
          _tagsByUuid,
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (ctx, constraints) {
              final gridAreaW = constraints.maxWidth - kTimeAxisW;
              final colW = gridAreaW / kColsPerH;
              final rowH = constraints.maxHeight / kTotalRows;

              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: kTimeAxisW,
                    height: constraints.maxHeight,
                    child: _TimeLabels(isDark: isDark, rowH: rowH),
                  ),
                  Expanded(
                    child: SizedBox(
                      width: gridAreaW,
                      height: constraints.maxHeight,
                      child: _GridCanvas(
                        colW: colW,
                        rowW: gridAreaW,
                        rowH: rowH,
                        dayStartMs: ds,
                        dLogs: _dayLogs,
                        dPoms: _dayPomodoros,
                        dSchedules: _daySchedules,
                        tags: widget.tags,
                        tagIndicesByUuid: _tagIndicesByUuid,
                        isDark: isDark,
                        focusColor: colorScheme.cdtFocus,
                        logColor: colorScheme.cdtInfo,
                        onPomodoroTap: widget.onPomodoroTap,
                        onTimeLogTap: widget.onTimeLogTap,
                        onScheduleTap: widget.onScheduleTap,
                        date: widget.date,
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildSummary(
    BuildContext ctx,
    int total,
    int logMin,
    int pomMin,
    int scheduleMin,
    List<MapEntry<String, int>> sortedTagMinutes,
    Map<String, PomodoroTag> tagsByUuid,
  ) {
    final accent = Theme.of(ctx).colorScheme.primary;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
      color: _TC.topBar(ctx),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                height: _timeLogSummaryChipHeight,
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.1),
                  border: Border.all(color: accent.withValues(alpha: 0.3)),
                  borderRadius: BorderRadius.circular(_timeLogActionChipRadius),
                ),
                child: Text(
                  '${(total / 60).toStringAsFixed(1)}h  今日合计',
                  style: TextStyle(
                    fontSize: 11,
                    color: accent,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              if (pomMin > 0)
                _miniPill(
                  ctx,
                  '专注 ${pomMin}m',
                  Theme.of(ctx).colorScheme.cdtFocus,
                ),
              if (logMin > 0) ...[
                const SizedBox(width: 6),
                _miniPill(
                  ctx,
                  '补录 ${logMin}m',
                  Theme.of(ctx).colorScheme.cdtInfo,
                ),
              ],
              if (scheduleMin > 0) ...[
                const SizedBox(width: 6),
                _miniPill(
                  ctx,
                  '排程 ${scheduleMin}m',
                  Theme.of(ctx).colorScheme.tertiary,
                ),
              ],
              const Spacer(),
              GestureDetector(
                onTap: widget.onSwitchEdit,
                child: Container(
                  height: _timeLogSummaryChipHeight,
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.1),
                    border: Border.all(color: accent.withValues(alpha: 0.3)),
                    borderRadius: BorderRadius.circular(
                      _timeLogActionChipRadius,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.edit_note, size: 14, color: accent),
                      const SizedBox(width: 4),
                      Text(
                        '补录',
                        style: TextStyle(
                          fontSize: 11,
                          color: accent,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          if (sortedTagMinutes.isNotEmpty && total > 0) ...[
            const SizedBox(height: 8),
            _TagProgressBar(
              sortedTagMinutes: sortedTagMinutes,
              totalMin: total,
              tagsByUuid: tagsByUuid,
            ),
          ],
        ],
      ),
    );
  }

  Widget _miniPill(BuildContext ctx, String text, Color c) => Container(
    height: _timeLogSummaryChipHeight,
    alignment: Alignment.center,
    padding: const EdgeInsets.symmetric(horizontal: 12),
    decoration: BoxDecoration(
      color: c.withValues(alpha: 0.08),
      border: Border.all(color: c.withValues(alpha: 0.3)),
      borderRadius: BorderRadius.circular(_timeLogActionChipRadius),
    ),
    child: Text(
      text,
      style: TextStyle(fontSize: 11, color: c, fontWeight: FontWeight.w600),
    ),
  );
}

// ══════════════════════════════════════════════════════════
// 左侧时间标签列
// ══════════════════════════════════════════════════════════
class _TimeLabels extends StatelessWidget {
  final bool isDark;
  final double rowH;

  const _TimeLabels({required this.isDark, required this.rowH});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: kTimeAxisW,
      height: rowH * kTotalRows,
      child: Stack(
        children: List.generate(kTotalRows, (h) {
          return Positioned(
            top: h * rowH,
            left: 0,
            right: 0,
            child: SizedBox(
              height: rowH,
              child: Align(
                alignment: Alignment.topRight,
                child: Padding(
                  padding: const EdgeInsets.only(right: 8, top: 3),
                  child: Text(
                    '${h.toString().padLeft(2, '0')}:00',
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: h % 6 == 0
                          ? FontWeight.w700
                          : FontWeight.w400,
                      color: _TC.timeLabel(context, major: h % 6 == 0),
                    ),
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════
// 网格 Canvas
// ══════════════════════════════════════════════════════════
class _GridCanvas extends StatelessWidget {
  final double colW, rowW, rowH;
  final int dayStartMs;
  final List<TimeLogItem> dLogs;
  final List<PomodoroRecord> dPoms;
  final List<TimeLogMappedSchedule> dSchedules;
  final List<PomodoroTag> tags;
  final Map<String, int> tagIndicesByUuid;
  final bool isDark;
  final Color focusColor;
  final Color logColor;
  final DateTime date;
  final void Function(PomodoroRecord) onPomodoroTap;
  final void Function(TimeLogItem) onTimeLogTap;
  final void Function(TimeLogMappedSchedule) onScheduleTap;

  const _GridCanvas({
    required this.colW,
    required this.rowW,
    required this.rowH,
    required this.dayStartMs,
    required this.dLogs,
    required this.dPoms,
    this.dSchedules = const [],
    required this.tags,
    required this.tagIndicesByUuid,
    required this.isDark,
    required this.focusColor,
    required this.logColor,
    required this.date,
    required this.onPomodoroTap,
    required this.onTimeLogTap,
    required this.onScheduleTap,
  });

  PomodoroTag? _firstTagForUuids(List<String> uuids) {
    int? firstIndex;
    for (final uuid in uuids) {
      final index = tagIndicesByUuid[uuid];
      if (index != null && (firstIndex == null || index < firstIndex)) {
        firstIndex = index;
      }
    }
    return firstIndex == null ? null : tags[firstIndex];
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final dayEndMs = _dayEndMs(DateTime.fromMillisecondsSinceEpoch(dayStartMs));
    final colorScheme = Theme.of(context).colorScheme;
    final isToday = AppTimeFormats.isSameDay(now, date);
    final nowTotalMin = isToday ? now.hour * 60 + now.minute : -1;

    return Stack(
      children: [
        RepaintBoundary(
          child: CustomPaint(
            size: Size(rowW, rowH * kTotalRows),
            painter: _GridBgPainter(
              colW: colW,
              rowH: rowH,
              rowMajorColor: colorScheme.outlineVariant,
              rowNormalColor: colorScheme.outlineVariant.withValues(
                alpha: isDark ? 0.38 : 0.58,
              ),
              colHourColor: colorScheme.outline,
              colHalfColor: colorScheme.outlineVariant,
              colCellColor: colorScheme.outlineVariant.withValues(
                alpha: isDark ? 0.26 : 0.42,
              ),
              labelMajorColor: colorScheme.onSurfaceVariant.withValues(
                alpha: 0.48,
              ),
              labelMinorColor: colorScheme.onSurfaceVariant.withValues(
                alpha: 0.34,
              ),
            ),
          ),
        ),
        if (nowTotalMin >= 0) _buildNowLine(nowTotalMin),
        // 排程（课程 / 固定日程，发生冲突时上下两行紧凑排列）
        ..._buildScheduleBlocks(
          schedules: dSchedules,
          dayStartMs: dayStartMs,
          colW: colW,
          rowW: rowW,
          rowH: rowH,
          isDark: isDark,
          onScheduleTap: onScheduleTap,
        ),
        // 番茄钟
        ...dPoms.expand((pom) {
          final pe =
              pom.endTime ?? (pom.startTime + pom.effectiveDuration * 1000);
          PomodoroTag? tag;
          if (pom.tagUuids.isNotEmpty) {
            tag = _firstTagForUuids(pom.tagUuids);
          }
          final base = tag != null ? hexColor(tag.color) : focusColor;
          final title = tag?.name ?? '专注';
          return _buildEventBlocks(
            startMs: max(pom.startTime, dayStartMs),
            endMs: min(pe, dayEndMs),
            dayStartMs: dayStartMs,
            colW: colW,
            rowW: rowW,
            rowH: rowH,
            fillColor: base.withValues(alpha: isDark ? 0.30 : 0.22),
            barColor: base,
            title: title,
            onTap: () => onPomodoroTap(pom),
          );
        }),

        // 补录日志
        ...dLogs.expand((log) {
          PomodoroTag? tag;
          if (log.tagUuids.isNotEmpty) {
            tag = _firstTagForUuids(log.tagUuids);
          }
          final base = tag != null ? hexColor(tag.color) : logColor;
          final title = log.title.isNotEmpty ? log.title : (tag?.name ?? '补录');
          return _buildEventBlocks(
            startMs: max(log.startTime, dayStartMs),
            endMs: min(log.endTime, dayEndMs),
            dayStartMs: dayStartMs,
            colW: colW,
            rowW: rowW,
            rowH: rowH,
            fillColor: base.withValues(alpha: isDark ? 0.26 : 0.18),
            barColor: base,
            title: title,
            onTap: () => onTimeLogTap(log),
          );
        }),

        Positioned(
          top: 9 * rowH,
          left: rowW / 3,
          width: rowW / 3,
          height: rowH,
          child: SizedBox(key: timeLogDragKey),
        ),
      ],
    );
  }

  Widget _buildNowLine(int nowTotalMin) {
    final nowHour = nowTotalMin ~/ 60;
    final minInHour = nowTotalMin % 60;
    final x = (minInHour / kMinsPerCol) * colW;
    final y = nowHour * rowH;

    return Stack(
      children: [
        Positioned(
          top: y,
          left: 0,
          right: 0,
          height: 1.0,
          child: Container(color: focusColor.withValues(alpha: 0.20)),
        ),
        Positioned(
          top: y,
          left: x,
          width: 1.5,
          height: rowH,
          child: Container(color: focusColor.withValues(alpha: 0.80)),
        ),
        Positioned(
          top: y + rowH / 2 - 3,
          left: x - 3,
          child: Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: focusColor,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: focusColor.withValues(alpha: 0.5),
                  blurRadius: 4,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  List<Widget> _buildEventBlocks({
    required int startMs,
    required int endMs,
    required int dayStartMs,
    required double colW,
    required double rowW,
    required double rowH,
    required Color fillColor,
    required Color barColor,
    required String title,
    required VoidCallback onTap,
  }) {
    if (endMs <= startMs) return [];

    final startMinF = (startMs - dayStartMs) / 60000.0;
    final endMinF = (endMs - dayStartMs) / 60000.0;
    final List<Widget> result = [];

    int row = startMinF ~/ 60;
    bool isFirst = true;

    while (row < kTotalRows) {
      final rowStartMin = row * 60.0;
      final rowEndMin = rowStartMin + 60.0;
      final segStartMin = startMinF.clamp(rowStartMin, rowEndMin);
      final segEndMin = endMinF.clamp(rowStartMin, rowEndMin);

      if (segEndMin <= segStartMin) {
        if (endMinF <= rowStartMin) break;
        row++;
        continue;
      }

      final colStart = (segStartMin - rowStartMin) / kMinsPerCol;
      final colEnd = (segEndMin - rowStartMin) / kMinsPerCol;
      final left = colStart * colW;
      final width = ((colEnd - colStart) * colW).clamp(1.0, double.infinity);
      final isLast = endMinF <= rowEndMin;

      // ── 色块背景（每一行都画）──────────────────────────
      result.add(
        Positioned(
          top: row * rowH + 1,
          left: left + 1,
          width: width - 2,
          height: rowH - 2,
          child: GestureDetector(
            onTap: onTap,
            behavior: HitTestBehavior.opaque,
            child: ClipRRect(
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(isFirst ? 3 : 0),
                bottomLeft: Radius.circular(isLast ? 3 : 0),
                topRight: Radius.circular(isFirst && isLast ? 3 : 0),
                bottomRight: Radius.circular(isFirst && isLast ? 3 : 0),
              ),
              child: Container(
                decoration: BoxDecoration(
                  color: fillColor,
                  border: Border(
                    left: BorderSide(color: barColor, width: 2.5),
                    top: isFirst
                        ? BorderSide(
                            color: barColor.withValues(alpha: 0.45),
                            width: 1.0,
                          )
                        : BorderSide.none,
                    bottom: isLast
                        ? BorderSide(
                            color: barColor.withValues(alpha: 0.45),
                            width: 1.0,
                          )
                        : BorderSide.none,
                    right: isLast && colEnd < kColsPerH
                        ? BorderSide(
                            color: barColor.withValues(alpha: 0.25),
                            width: 1.0,
                          )
                        : BorderSide.none,
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      // ── 文字：只在第一行，横跨整行宽度（从 left+3 到行末）──
      if (isFirst) {
        result.add(
          Positioned(
            top: row * rowH + 1,
            left: left + 3, // 紧贴左边彩条右侧
            right: 2, // 贴到行右边，让文字尽量展开
            height: rowH - 2,
            child: GestureDetector(
              onTap: onTap,
              behavior: HitTestBehavior.translucent,
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 10,
                    color: barColor,
                    fontWeight: FontWeight.w700,
                    height: 1.2,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ),
            ),
          ),
        );
      }

      if (isLast) break;
      isFirst = false;
      row++;
    }

    return result;
  }

  List<Widget> _buildScheduleBlocks({
    required List<TimeLogMappedSchedule> schedules,
    required int dayStartMs,
    required double colW,
    required double rowW,
    required double rowH,
    required bool isDark,
    required void Function(TimeLogMappedSchedule) onScheduleTap,
  }) {
    if (schedules.isEmpty) return const [];

    final List<List<_ScheduleRowSegment>> segmentsByRow = List.generate(
      kTotalRows,
      (_) => <_ScheduleRowSegment>[],
    );

    for (final schedule in schedules) {
      final sMs = max(schedule.startTime, dayStartMs);
      final eMs = min(schedule.endTime, dayStartMs + 24 * 3600 * 1000);
      if (eMs <= sMs) continue;

      final startMinF = (sMs - dayStartMs) / 60000.0;
      final endMinF = (eMs - dayStartMs) / 60000.0;
      final isCourse = schedule.isCourse;
      final base = isCourse
          ? (isDark ? const Color(0xFF64B5F6) : const Color(0xFF1E88E5))
          : (isDark ? const Color(0xFFFFB74D) : const Color(0xFFFB8C00));
      final title =
          '${isCourse ? "课程" : "日程"}: ${schedule.title}${schedule.subtitle != null && schedule.subtitle!.isNotEmpty ? " · ${schedule.subtitle}" : ""}';
      final fillColor = base.withValues(alpha: isDark ? 0.16 : 0.10);
      final barColor = base.withValues(alpha: 0.75);
      final borderColor = base.withValues(alpha: isDark ? 0.40 : 0.30);
      void onTap() => onScheduleTap(schedule);

      int row = startMinF ~/ 60;
      bool isFirst = true;

      while (row < kTotalRows) {
        final rowStartMin = row * 60.0;
        final rowEndMin = rowStartMin + 60.0;
        final segStartMin = startMinF.clamp(rowStartMin, rowEndMin);
        final segEndMin = endMinF.clamp(rowStartMin, rowEndMin);

        if (segEndMin <= segStartMin) {
          if (endMinF <= rowStartMin) break;
          row++;
          continue;
        }

        final isLast = endMinF <= rowEndMin;
        segmentsByRow[row].add(
          _ScheduleRowSegment(
            schedule: schedule,
            row: row,
            segStartMin: segStartMin,
            segEndMin: segEndMin,
            isFirst: isFirst,
            isLast: isLast,
            fillColor: fillColor,
            barColor: barColor,
            borderColor: borderColor,
            title: title,
            onTap: onTap,
          ),
        );

        if (isLast) break;
        isFirst = false;
        row++;
      }
    }

    final List<Widget> result = [];

    for (int row = 0; row < kTotalRows; row++) {
      final rowSegments = segmentsByRow[row];
      if (rowSegments.isEmpty) continue;

      // 稳定排序：课程优先排在上半行（lane 0），日程排在下半行（lane 1）
      rowSegments.sort((a, b) {
        if (a.schedule.isCourse != b.schedule.isCourse) {
          return a.schedule.isCourse ? -1 : 1;
        }
        final cmpStart = a.schedule.startTime.compareTo(b.schedule.startTime);
        if (cmpStart != 0) return cmpStart;
        return a.schedule.id.compareTo(b.schedule.id);
      });

      // 检查当前行中的片段是否存在时间水平重叠
      final laneAssignment = <_ScheduleRowSegment, int>{};
      final laneTotalCount = <_ScheduleRowSegment, int>{};

      for (int i = 0; i < rowSegments.length; i++) {
        final current = rowSegments[i];
        final overlapping = <_ScheduleRowSegment>[];
        for (int j = 0; j < rowSegments.length; j++) {
          final other = rowSegments[j];
          if (current.segStartMin < other.segEndMin &&
              other.segStartMin < current.segEndMin) {
            overlapping.add(other);
          }
        }

        if (overlapping.length <= 1) {
          laneAssignment[current] = 0;
          laneTotalCount[current] = 1;
        } else {
          final indexInOverlap = overlapping.indexOf(current);
          laneAssignment[current] = indexInOverlap.clamp(0, 1);
          laneTotalCount[current] = min(overlapping.length, 2);
        }
      }

      for (final seg in rowSegments) {
        final lane = laneAssignment[seg] ?? 0;
        final totalLanes = laneTotalCount[seg] ?? 1;

        final rowStartMin = row * 60.0;
        final colStart = (seg.segStartMin - rowStartMin) / kMinsPerCol;
        final colEnd = (seg.segEndMin - rowStartMin) / kMinsPerCol;
        final left = colStart * colW;
        final width = ((colEnd - colStart) * colW).clamp(1.0, double.infinity);

        final double topOffset;
        final double blockHeight;
        final double fontSize;

        if (totalLanes >= 2) {
          // 冲突时间段：一行分两行用，上下紧凑排列
          final laneH = (rowH - 3.0) / 2.0;
          blockHeight = laneH;
          topOffset = row * rowH + 1.0 + lane * (laneH + 1.0);
          fontSize = (laneH * 0.72).clamp(7.5, 9.5);
        } else {
          blockHeight = rowH - 2.0;
          topOffset = row * rowH + 1.0;
          fontSize = (blockHeight * 0.40).clamp(9.0, 10.5);
        }

        result.add(
          Positioned(
            top: topOffset,
            left: left + 1,
            width: width - 2,
            height: blockHeight,
            child: GestureDetector(
              onTap: seg.onTap,
              behavior: HitTestBehavior.opaque,
              child: ClipRRect(
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(seg.isFirst ? 3 : 0),
                  bottomLeft: Radius.circular(seg.isLast ? 3 : 0),
                  topRight: Radius.circular(seg.isFirst && seg.isLast ? 3 : 0),
                  bottomRight: Radius.circular(
                    seg.isFirst && seg.isLast ? 3 : 0,
                  ),
                ),
                child: Container(
                  decoration: BoxDecoration(
                    color: seg.fillColor,
                    border: Border(
                      left: BorderSide(
                        color: seg.barColor,
                        width: totalLanes >= 2 ? 2.0 : 2.5,
                      ),
                      top: BorderSide(color: seg.borderColor, width: 0.8),
                      bottom: BorderSide(color: seg.borderColor, width: 0.8),
                      right: seg.isLast && colEnd < kColsPerH
                          ? BorderSide(color: seg.borderColor, width: 0.8)
                          : BorderSide.none,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );

        if (seg.isFirst) {
          result.add(
            Positioned(
              top: topOffset,
              left: left + 4,
              right: 2,
              height: blockHeight,
              child: IgnorePointer(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    seg.title,
                    style: TextStyle(
                      fontSize: fontSize,
                      color: seg.barColor,
                      fontWeight: FontWeight.w700,
                      height: 1.1,
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                ),
              ),
            ),
          );
        }
      }
    }

    return result;
  }
}

class _ScheduleRowSegment {
  final TimeLogMappedSchedule schedule;
  final int row;
  final double segStartMin;
  final double segEndMin;
  final bool isFirst;
  final bool isLast;
  final Color fillColor;
  final Color barColor;
  final Color borderColor;
  final String title;
  final VoidCallback onTap;

  _ScheduleRowSegment({
    required this.schedule,
    required this.row,
    required this.segStartMin,
    required this.segEndMin,
    required this.isFirst,
    required this.isLast,
    required this.fillColor,
    required this.barColor,
    required this.borderColor,
    required this.title,
    required this.onTap,
  });
}

// ══════════════════════════════════════════════════════════
// 网格背景 Painter
// ══════════════════════════════════════════════════════════
class _GridBgPainter extends CustomPainter {
  final double colW;
  final double rowH;
  final Color rowMajorColor;
  final Color rowNormalColor;
  final Color colHourColor;
  final Color colHalfColor;
  final Color colCellColor;
  final Color labelMajorColor;
  final Color labelMinorColor;

  static final Paint _rowMajor = Paint()..strokeWidth = 0.9;
  static final Paint _rowNormal = Paint()..strokeWidth = 0.5;
  static final Paint _colHour = Paint()..strokeWidth = 0.9;
  static final Paint _colHalf = Paint()..strokeWidth = 0.5;
  static final Paint _colCell = Paint()..strokeWidth = 0.3;

  const _GridBgPainter({
    required this.colW,
    required this.rowH,
    required this.rowMajorColor,
    required this.rowNormalColor,
    required this.colHourColor,
    required this.colHalfColor,
    required this.colCellColor,
    required this.labelMajorColor,
    required this.labelMinorColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    _rowMajor.color = rowMajorColor;
    _rowNormal.color = rowNormalColor;

    for (int r = 0; r <= kTotalRows; r++) {
      final y = r * rowH;
      canvas.drawLine(
        Offset(0, y),
        Offset(size.width, y),
        r % 6 == 0 ? _rowMajor : _rowNormal,
      );
    }

    _colHour.color = colHourColor;
    _colHalf.color = colHalfColor;
    _colCell.color = colCellColor;

    for (int c = 0; c <= kTotalCols; c++) {
      final x = c * colW;
      final Paint p;
      if (c % kColsPerH == 0) {
        p = _colHour;
      } else if (c % 5 == 0) {
        p = _colHalf;
      } else {
        p = _colCell;
      }
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), p);
    }

    final tp = TextPainter(textDirection: ui.TextDirection.ltr);
    try {
      for (int h = 0; h < kTotalRows; h++) {
        final rowTop = h * rowH;

        _drawLabel(
          tp,
          canvas,
          '${h.toString().padLeft(2, '0')}:00',
          Offset(h * kColsPerH * colW + 3, rowTop + 2),
          fontSize: 8.0,
          color: labelMajorColor,
          bold: true,
        );

        if (colW >= 14) {
          _drawLabel(
            tp,
            canvas,
            '${h.toString().padLeft(2, '0')}:30',
            Offset((h * kColsPerH + 5) * colW + 3, rowTop + 2),
            fontSize: 7.0,
            color: labelMinorColor,
            bold: false,
          );
        }
      }
    } finally {
      tp.dispose();
    }
  }

  void _drawLabel(
    TextPainter tp,
    Canvas canvas,
    String text,
    Offset offset, {
    required double fontSize,
    required Color color,
    required bool bold,
  }) {
    tp
      ..text = TextSpan(
        text: text,
        style: TextStyle(
          fontSize: fontSize,
          color: color,
          fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
        ),
      )
      ..layout();
    tp.paint(canvas, offset);
  }

  @override
  bool shouldRepaint(covariant _GridBgPainter o) =>
      o.colW != colW ||
      o.rowH != rowH ||
      o.rowMajorColor != rowMajorColor ||
      o.rowNormalColor != rowNormalColor ||
      o.colHourColor != colHourColor ||
      o.colHalfColor != colHalfColor ||
      o.colCellColor != colCellColor ||
      o.labelMajorColor != labelMajorColor ||
      o.labelMinorColor != labelMinorColor;
}

// ══════════════════════════════════════════════════════════
// 标签色条
// ══════════════════════════════════════════════════════════
class _TagProgressBar extends StatelessWidget {
  final List<MapEntry<String, int>> sortedTagMinutes;
  final int totalMin;
  final Map<String, PomodoroTag> tagsByUuid;

  const _TagProgressBar({
    required this.sortedTagMinutes,
    required this.totalMin,
    required this.tagsByUuid,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: SizedBox(
            height: 5,
            width: double.infinity,
            child: Row(
              children: sortedTagMinutes.map((e) {
                final t = tagsByUuid[e.key];
                final c = t != null
                    ? hexColor(t.color)
                    : Theme.of(context).colorScheme.cdtInfo;
                return Expanded(
                  flex: e.value,
                  child: Container(color: c),
                );
              }).toList(),
            ),
          ),
        ),
        const SizedBox(height: 5),
        Wrap(
          spacing: 10,
          runSpacing: 3,
          children: sortedTagMinutes.map((e) {
            final t = tagsByUuid[e.key];
            if (t == null) return const SizedBox.shrink();
            final c = hexColor(t.color);
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(color: c, shape: BoxShape.circle),
                ),
                const SizedBox(width: 4),
                Text(
                  t.name,
                  style: TextStyle(
                    fontSize: 10,
                    color: c,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 3),
                Text(
                  '${e.value}m',
                  style: TextStyle(fontSize: 10, color: _TC.textSub(context)),
                ),
              ],
            );
          }).toList(),
        ),
      ],
    );
  }
}
