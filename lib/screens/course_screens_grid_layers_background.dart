part of 'course_screens.dart';

// ignore_for_file: unused_element, unused_element_parameter, annotate_overrides

mixin _WeeklyCourseGridBackgroundLayers on _WeeklyCourseScreenStateBase {
  @override
  void _collectPlanBlockGridEvents(_WeeklyGridLayerContext ctx) {
    final colorScheme = ctx.colorScheme;
    final cellWidth = ctx.cellWidth;
    final minuteHeight = ctx.minuteHeight;
    final planIndices = ctx.planIndices;
    final planPomodoroProgressIndex = ctx.planPomodoroProgressIndex;
    final backgroundEventsPerDay = ctx.backgroundEventsPerDay;
    final topInsetForBackgroundCard = ctx.topInsetForBackgroundCard;
    for (int weekday = 1; weekday <= 7; weekday++) {
      for (var plan in _planBlocksPerDay[weekday] ?? <TodoPlanBlock>[]) {
        final start = DateTime.fromMillisecondsSinceEpoch(plan.startTime)
            .toLocal();
        final end = DateTime.fromMillisecondsSinceEpoch(plan.endTime).toLocal();

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
        final actualFocusSeconds = (pomProgress['actualSeconds'] as int?) ?? 0;
        final double progressRatio =
            ((pomProgress['progress'] as double?) ?? 0.0).clamp(0.0, 1.0);
        final planStatus = _planStatusForActualFocus(plan, actualFocusSeconds);
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
                    if (t >= 0.999) return child!;
                    if (t <= 0.001) return const SizedBox.shrink();
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

  @override
  void _collectFixedScheduleGridEvents(_WeeklyGridLayerContext ctx) {
    final colorScheme = ctx.colorScheme;
    final cellWidth = ctx.cellWidth;
    final minuteHeight = ctx.minuteHeight;
    final backgroundEventsPerDay = ctx.backgroundEventsPerDay;
    final topInsetForBackgroundCard = ctx.topInsetForBackgroundCard;
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
          final sliceEnd = scheduleEnd.isBefore(dayEnd) ? scheduleEnd : dayEnd;
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
          final String displayFixedTitle = isShortFixedCard && location != null
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
                                  crossAxisAlignment: CrossAxisAlignment.start,
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

  @override
  void _collectDeviceCalendarGridEvents(_WeeklyGridLayerContext ctx) {
    final colorScheme = ctx.colorScheme;
    final cellWidth = ctx.cellWidth;
    final minuteHeight = ctx.minuteHeight;
    final backgroundEventsPerDay = ctx.backgroundEventsPerDay;
    final topInsetForBackgroundCard = ctx.topInsetForBackgroundCard;
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
          final String? location = event.location?.trim().isNotEmpty == true
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
                                    color: Colors.white.withValues(alpha: 0.85),
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

  @override
  void _collectCourseGridEvents(_WeeklyGridLayerContext ctx) {
    final colorScheme = ctx.colorScheme;
    final cellWidth = ctx.cellWidth;
    final minuteHeight = ctx.minuteHeight;
    final isDark = ctx.isDark;
    final backgroundEventsPerDay = ctx.backgroundEventsPerDay;
    final topInsetForBackgroundCard = ctx.topInsetForBackgroundCard;
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
            final double fontScale = (width / (cellWidth - 2)).clamp(0.4, 1.0);
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
                  if (t >= 0.999) return child!;
                  if (t <= 0.001) return const SizedBox.shrink();
                  final scale = 0.7 + 0.3 * t;
                  return Transform.scale(
                    scale: scale,
                    child: Opacity(opacity: t, child: child),
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
}
