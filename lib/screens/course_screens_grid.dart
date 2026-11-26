part of 'course_screens.dart';

// ignore_for_file: unused_element, unused_element_parameter, annotate_overrides

mixin _WeeklyCourseGrid on _WeeklyCourseScreenStateBase {
  _PlanPomodoroProgressIndex? _cachedPlanPomodoroProgressIndex;
  Map<int, List<TodoPlanBlock>>? _visiblePlansSource;
  Map<TodoPlanBlock, int> _cachedVisiblePlanIndices = const {};
  List<_HiddenTimeRange>? _hiddenTimeRangesSource;
  List<double> _hiddenRangeDurationPrefix = const [0.0];

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

  String _formatMinute(double minute) =>
      AppTimeFormats.minuteOfDay(minute.round());

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

    final int minSubLines = (availHeight >= 46.0 && neededSubLines >= 2)
        ? 2
        : 1;
    final double minSubReserve = subTopGap + minSubLines * subLineHeight;
    final int titleMaxLines =
        ((availHeight - minSubReserve + 2.0) / titleLineHeight).floor().clamp(
          1,
          15,
        );
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
                onTap: () =>
                    _showAggregatedTimelineSheet(context, weekday, items),
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
    final bool isWideScreen =
        cellWidth >= 80.0 || MediaQuery.sizeOf(context).width > 900;
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

    // 🚀 周视图“今天”整列纵向柔和高光：贯穿网格全高，作为底层聚光灯使今天一眼可辨
    final weekMonday = _getMondayOfCurrentWeek();
    int? todayColumnIndex;
    if (weekMonday != null) {
      final now = DateTime.now();
      final diff = CalendarDateMath.daysBetween(weekMonday, now);
      if (diff >= 0 && diff < 7) {
        todayColumnIndex = diff;
      }
    }

    if (todayColumnIndex != null) {
      children.add(
        Positioned(
          top: 0,
          bottom: 0,
          left: timeColumnWidth + todayColumnIndex * cellWidth,
          width: cellWidth,
          child: IgnorePointer(
            child: Container(
              decoration: BoxDecoration(
                color: colorScheme.primary.withValues(
                  alpha: isDark ? 0.07 : 0.038,
                ),
              ),
            ),
          ),
        ),
      );
    }

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

    final layerContext = _WeeklyGridLayerContext(
      cellWidth: cellWidth,
      minuteHeight: minuteHeight,
      colorScheme: colorScheme,
      isWideScreen: isWideScreen,
      isDark: isDark,
      planIndices: planIndices,
      planPomodoroProgressIndex: planPomodoroProgressIndex,
      backgroundEventsPerDay: backgroundEventsPerDay,
      foregroundEventsPerDay: foregroundEventsPerDay,
      firstTagFor: firstTagFor,
      topInsetForBackgroundCard: topInsetForBackgroundCard,
    );

    if (_activeDataViews.contains('todos')) {
      _collectTodoGridEvents(layerContext);
    }
    if (_activeDataViews.contains('timeLogs')) {
      _collectTimeLogGridEvents(layerContext);
    }
    if (_activeDataViews.contains('plans')) {
      _collectPlanBlockGridEvents(layerContext);
    }
    if (_activeDataViews.contains('fixedSchedules')) {
      _collectFixedScheduleGridEvents(layerContext);
    }
    if (_activeDataViews.contains('pomodoros')) {
      _collectPomodoroGridEvents(layerContext);
    }
    if (_activeDataViews.contains('deviceCalendar')) {
      _collectDeviceCalendarGridEvents(layerContext);
    }
    if (_activeDataViews.contains('courses')) {
      _collectCourseGridEvents(layerContext);
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
              top: nowY - 5,
              left: lineLeft - 5,
              width: cellWidth + 5,
              height: 10,
              child: RepaintBoundary(
                child: CustomPaint(
                  painter: _CurrentTimeMarkerPainter(
                    animation: _pulseAnimation,
                    color: colorScheme.primary,
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
