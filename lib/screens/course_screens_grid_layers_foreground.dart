part of 'course_screens.dart';

// ignore_for_file: unused_element, unused_element_parameter, annotate_overrides

mixin _WeeklyCourseGridForegroundLayers on _WeeklyCourseScreenStateBase {
  @override
  void _collectTodoGridEvents(_WeeklyGridLayerContext ctx) {
    final colorScheme = ctx.colorScheme;
    final cellWidth = ctx.cellWidth;
    final minuteHeight = ctx.minuteHeight;
    final foregroundEventsPerDay = ctx.foregroundEventsPerDay;
    final todoIndices = _todoIndexCache.indicesFor(
      _intraDayTodosPerDay,
      _intraDayTodosPerDay.values.expand((items) => items),
    );
    final collisionMap = <String, int>{};
    for (int weekday = 1; weekday <= 7; weekday++) {
      final dayTodos = _intraDayTodosPerDay[weekday] ?? [];
      for (var todo in dayTodos) {
        DateTime start = AppTimeFormats.localFromServerTimestamp(
          todo.createdDate ?? todo.createdAt,
        );
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
            : _harmonizeWeekEventColor(colorScheme.cdtWarning, opacity: 0.85);
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
              final bool showTeamBadge = todo.teamUuid != null && height > 56.0;
              final textLayout = _computeCardTextLayout(
                title: todo.title,
                subtitle: todo.remark,
                width: width,
                height: height,
                effectiveHeight: height,
                titleFontSize: titleFontSize,
                subFontSize: 8.0,
                extraReservedHeight: showTeamBadge ? (teamFontSize + 5.0) : 0.0,
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
                    if (t >= 0.999) return child!;
                    if (t <= 0.001) return const SizedBox.shrink();
                    final scale = 0.7 + 0.3 * t;
                    return Transform.scale(
                      scale: scale,
                      child: Opacity(opacity: t, child: child),
                    );
                  },
                  child: RepaintBoundary(
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
                ),
              );
            },
          ),
        );
      }
    }
  }

  @override
  void _collectTimeLogGridEvents(_WeeklyGridLayerContext ctx) {
    final colorScheme = ctx.colorScheme;
    final cellWidth = ctx.cellWidth;
    final minuteHeight = ctx.minuteHeight;
    final isWideScreen = ctx.isWideScreen;
    final firstTagFor = ctx.firstTagFor;
    final foregroundEventsPerDay = ctx.foregroundEventsPerDay;
    final logIndices = _timeLogIndexCache.indicesFor(
      _timeLogsPerDay,
      _timeLogsPerDay.values.expand((items) => items),
    );
    for (int weekday = 1; weekday <= 7; weekday++) {
      for (var log in _timeLogsPerDay[weekday]!) {
        DateTime start = AppTimeFormats.localFromServerTimestamp(log.startTime);
        DateTime end = AppTimeFormats.localFromServerTimestamp(log.endTime);

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

        final int logDurationSeconds = ((log.endTime - log.startTime) / 1000)
            .round();
        final String logDurationText = _formatEventDuration(logDurationSeconds);
        final logRemark = log.remark?.trim();
        final String effectiveLogSubtitle =
            (logRemark != null && logRemark.isNotEmpty)
            ? (isWideScreen
                  ? '$logDurationText · $logRemark'
                  : '$logDurationText $logRemark')
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
                  ? (isWideScreen
                        ? '$logTitle · $logDurationText'
                        : '$logTitle $logDurationText')
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
                    if (t >= 0.999) return child!;
                    if (t <= 0.001) return const SizedBox.shrink();
                    final scale = 0.7 + 0.3 * t;
                    return Transform.scale(
                      scale: scale,
                      child: Opacity(opacity: t, child: child),
                    );
                  },
                  child: RepaintBoundary(
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
                ),
              );
            },
          ),
        );
      }
    }
  }

  @override
  void _collectPomodoroGridEvents(_WeeklyGridLayerContext ctx) {
    final colorScheme = ctx.colorScheme;
    final cellWidth = ctx.cellWidth;
    final minuteHeight = ctx.minuteHeight;
    final isWideScreen = ctx.isWideScreen;
    final firstTagFor = ctx.firstTagFor;
    final foregroundEventsPerDay = ctx.foregroundEventsPerDay;
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
        DateTime pomStart = AppTimeFormats.localFromServerTimestamp(
          record.startTime,
        );
        int endMs =
            record.endTime ??
            (record.startTime + record.effectiveDuration * 1000);
        DateTime pomEnd = AppTimeFormats.localFromServerTimestamp(endMs);

        final associatedPlans =
            planAssociationIndex?.matchingPlans(record, endMs) ??
            dayPlans
                .where((plan) => _isRecordAssociatedWithPlan(record, plan))
                .toList();

        List<Map<String, DateTime>> segments = [
          {'start': pomStart, 'end': pomEnd},
        ];

        for (var plan in associatedPlans) {
          DateTime planStart = AppTimeFormats.localFromServerTimestamp(
            plan.startTime,
          );
          DateTime planEnd = AppTimeFormats.localFromServerTimestamp(
            plan.endTime,
          );

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

          final int segDurationSeconds =
              segments.length == 1 && record.effectiveDuration > 0
              ? record.effectiveDuration
              : ((end.millisecondsSinceEpoch - start.millisecondsSinceEpoch) /
                        1000)
                    .round();
          final String durationText = _formatPomodoroDuration(
            segDurationSeconds,
          );
          final String effectivePomSubtitle = pomSubtitle != null
              ? (isWideScreen
                    ? '$pomSubtitle · $durationText'
                    : '$pomSubtitle $durationText')
              : durationText;
          final bool isShortPomCard = height < 22.0;
          final String displayPomTitle = isShortPomCard
              ? (isWideScreen
                    ? '$pomTitle · $durationText'
                    : '$pomTitle $durationText')
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
                final double titleFontSize = (height * 0.32 * fontScale).clamp(
                  9.0,
                  10.5,
                );
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
                      if (t >= 0.999) return child!;
                      if (t <= 0.001) return const SizedBox.shrink();
                      final scale = 0.7 + 0.3 * t;
                      return Transform.scale(
                        scale: scale,
                        child: Opacity(opacity: t, child: child),
                      );
                    },
                    child: RepaintBoundary(
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
                  ),
                );
              },
            ),
          );
        }
      }
    }
  }
}
