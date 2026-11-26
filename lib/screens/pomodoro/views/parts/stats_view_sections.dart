part of '../stats_view.dart';

extension _PomodoroStatsSections on PomodoroStatsState {
  Widget _buildTrendChart() {
    // Prepare seven adjacent bucket starts, then aggregate each session once.
    final chartRange = _getChartRange();
    final bucketStarts = List<DateTime>.generate(7, (index) {
      if (_dimension == 0) {
        return CalendarDateMath.addDays(chartRange.start, index);
      }
      if (_dimension == 1) {
        return CalendarDateMath.addDays(chartRange.start, index * 7);
      }
      if (_dimension == 2) {
        return DateTime(
          chartRange.start.year,
          chartRange.start.month + index,
          1,
        );
      }
      return DateTime(chartRange.start.year + index, 1, 1);
    }, growable: false);
    final bucketStartEpochs = bucketStarts
        .map((start) => start.millisecondsSinceEpoch)
        .toList(growable: false);
    final focusSecondsByBucket = List<int>.filled(7, 0);
    final chartEndEpoch = chartRange.end.millisecondsSinceEpoch;
    if (_dimension != 3) {
      for (final session in _chartSessions) {
        final startEpoch = session.startTime;
        if (startEpoch < bucketStartEpochs.first ||
            startEpoch >= chartEndEpoch) {
          continue;
        }

        var low = 0;
        var high = bucketStartEpochs.length;
        while (low < high) {
          final middle = (low + high) >> 1;
          if (bucketStartEpochs[middle] <= startEpoch) {
            low = middle + 1;
          } else {
            high = middle;
          }
        }
        final bucketIndex = low - 1;
        if (bucketIndex >= 0) {
          focusSecondsByBucket[bucketIndex] += session.effectiveDuration;
        }
      }
    }

    final selectedWeekRange = _dimension == 1 ? _getRange() : null;
    final dataPoints = <ChartData>[];

    for (int i = 0; i < 7; i++) {
      final start = bucketStarts[i];
      String label;
      bool isSelected = false;

      if (_dimension == 0) {
        label = AppTimeFormats.dateFormatter('MM/dd').format(start);
        isSelected = AppTimeFormats.isSameDay(start, _selected);
      } else if (_dimension == 1) {
        label = AppTimeFormats.dateFormatter('MM/dd').format(start);
        isSelected = start.isAtSameMomentAs(selectedWeekRange!.start);
      } else if (_dimension == 2) {
        label = AppTimeFormats.dateFormatter('MM月').format(start);
        isSelected =
            start.year == _selected.year && start.month == _selected.month;
      } else {
        label = '${start.year}';
        isSelected = start.year == _selected.year;
      }

      final focusSecs = _dimension == 3
          ? (_yearlyFocusSeconds[start.year] ?? 0)
          : focusSecondsByBucket[i];
      dataPoints.add(ChartData(label, focusSecs, isSelected, start));
    }

    return PomodoroTrendChart(
      data: dataPoints,
      onSelect: (date) {
        _mutateState(() {
          _selected = date;
        });
        _loadLocal();
      },
    );
  }

  Widget _buildSummaryCard(int totalSecs, int completedCount) {
    final h = totalSecs ~/ 3600;
    final m = (totalSecs % 3600) ~/ 60;
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            colorScheme.primaryContainer,
            colorScheme.surfaceContainerHighest,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('总专注时长', style: TextStyle(fontSize: 14)),
                const SizedBox(height: 4),
                RichText(
                  text: TextSpan(
                    style: TextStyle(
                      color: colorScheme.onSurface,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                    children: [
                      TextSpan(text: '$h'),
                      const TextSpan(
                        text: ' 小时 ',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.normal,
                        ),
                      ),
                      TextSpan(text: '$m'),
                      const TextSpan(
                        text: ' 分钟',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.normal,
                        ),
                      ),
                    ],
                  ),
                ),
                if (_dimension == 0 &&
                    DateUtils.isSameDay(_selected, DateTime.now()) &&
                    _communityStats != null) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: colorScheme.surface.withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.groups_rounded,
                          size: 14,
                          color: colorScheme.primary,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '今日全站人均 ${formatDurationChinese(_communityStats!.avgSeconds)}',
                          style: TextStyle(
                            fontSize: 12,
                            color: colorScheme.onSurfaceVariant,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: colorScheme.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                Text(
                  '$completedCount',
                  style: TextStyle(
                    color: colorScheme.primary,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Text('完成番茄', style: TextStyle(fontSize: 11)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTagDistribution(Map<String, int> byTag, int totalSecs) {
    if (byTag.isEmpty) {
      return Container(
        height: 100,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest
              .withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Text('本期暂无数据', style: TextStyle(color: Colors.grey)),
      );
    }

    final sorted = byTag.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Column(
      children: sorted.map((e) {
        final tag = _tagsByUuid[e.key];
        final name = tag?.name ?? '未知';
        final color = AppColorUtils.parseHex(tag?.color ?? '#9E9E9E');
        final pct = totalSecs > 0 ? e.value / totalSecs : 0.0;

        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    name,
                    style: const TextStyle(fontWeight: FontWeight.w500),
                  ),
                  Text(
                    PomodoroService.formatDuration(e.value),
                    style: const TextStyle(color: Colors.grey),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: pct,
                  backgroundColor: color.withValues(alpha: 0.1),
                  color: color,
                  minHeight: 8,
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  List<Widget> _buildSessionList() {
    final timeFormatter = AppTimeFormats.dateFormatter('HH:mm');

    if (_dimension == 0) {
      return _sessions.map((session) {
        final localStart = AppTimeFormats.localFromServerTimestamp(
          session.startTime,
        );
        return _buildSessionCard(
          session,
          startLocal: localStart,
          timeFormatter: timeFormatter,
        );
      }).toList();
    }

    final dayLabelFormatter = (_dimension == 1 || _dimension == 2)
        ? AppTimeFormats.dateFormatter('MM月dd日')
        : AppTimeFormats.dateFormatter('yyyy年MM月dd日');
    final widgets = <Widget>[];
    DateTime? previousDay;
    for (final session in _sessions) {
      final localStart = AppTimeFormats.localFromServerTimestamp(
        session.startTime,
      );
      final isNewDay =
          previousDay == null ||
          previousDay.year != localStart.year ||
          previousDay.month != localStart.month ||
          previousDay.day != localStart.day;
      if (isNewDay) {
        final dayDate = DateTime(
          localStart.year,
          localStart.month,
          localStart.day,
        );
        widgets.add(
          Padding(
            padding: const EdgeInsets.only(top: 16, bottom: 8),
            child: InkWell(
              borderRadius: BorderRadius.circular(6),
              onTap: () => _openDay(dayDate),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      dayLabelFormatter.format(localStart),
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      Icons.chevron_right_rounded,
                      size: 16,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      }
      widgets.add(
        _buildSessionCard(
          session,
          startLocal: localStart,
          timeFormatter: timeFormatter,
        ),
      );
      previousDay = localStart;
    }
    return widgets;
  }

  List<Widget> _buildYearlyOverview() {
    final colorScheme = Theme.of(context).colorScheme;
    final maxFocusSeconds = _yearlyMonthlySummaries.fold<int>(
      0,
      (maximum, summary) =>
          summary.focusSeconds > maximum ? summary.focusSeconds : maximum,
    );

    return [
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Text(
          '按月份查看专注时长和次数，点击有记录的月份可展开明细。',
          style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
        ),
      ),
      ..._yearlyMonthlySummaries.map((summary) {
        final ratio = maxFocusSeconds > 0
            ? summary.focusSeconds / maxFocusSeconds
            : 0.0;
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Material(
            color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.32),
            borderRadius: BorderRadius.circular(14),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: summary.sessionCount == 0
                  ? null
                  : () => _openMonth(summary.month),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 38,
                          height: 38,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: colorScheme.primary.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(11),
                          ),
                          child: Text(
                            '${summary.month}月',
                            style: TextStyle(
                              color: colorScheme.primary,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            '${summary.sessionCount} 次专注 · 完成 ${summary.completedCount} 次',
                            style: TextStyle(
                              color: colorScheme.onSurfaceVariant,
                              fontSize: 12,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          PomodoroService.formatDuration(summary.focusSeconds),
                          style: TextStyle(
                            color: colorScheme.onSurface,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: ratio,
                        minHeight: 4,
                        backgroundColor: colorScheme.primary.withValues(
                          alpha: 0.1,
                        ),
                        color: colorScheme.primary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      }),
    ];
  }

  void _openMonth(int month) {
    _mutateState(() {
      _dimension = 2;
      _selected = DateTime(_selected.year, month, 1);
    });
    _loadLocal();
  }

  Widget _buildSessionCard(
    PomodoroSession s, {
    required DateTime startLocal,
    required DateFormat timeFormatter,
  }) {
    final tagNames = s.tagUuids.isNotEmpty
        ? s.tagUuids.map((uuid) => _tagsByUuid[uuid]?.name ?? uuid).join(', ')
        : null;
    final timeLabel = timeFormatter.format(startLocal);
    final cardKey = GlobalKey();

    final content = widget.isCompact
        ? Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: s.isCompleted
                      ? const Color(0xFF4ECDC4).withValues(alpha: 0.2)
                      : const Color(0xFFFF6B6B).withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  s.isCompleted
                      ? Icons.check_circle_rounded
                      : Icons.timer_off_rounded,
                  color: s.isCompleted
                      ? const Color(0xFF4ECDC4)
                      : const Color(0xFFFF6B6B),
                  size: 14,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      s.todoTitle ?? '自由专注',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Text(
                          timeLabel,
                          style: const TextStyle(
                            fontSize: 10,
                            color: Colors.grey,
                          ),
                        ),
                        if (tagNames != null) ...[
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              tagNames,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 10,
                                color: Colors.grey,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (s.note != null && s.note!.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        s.note!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 10,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                PomodoroService.formatDuration(s.effectiveDuration),
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.more_vert, size: 16),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: () => _editSession(s),
              ),
            ],
          )
        : ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 4,
            ),
            leading: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: s.isCompleted
                    ? const Color(0xFF4ECDC4).withValues(alpha: 0.2)
                    : const Color(0xFFFF6B6B).withValues(alpha: 0.2),
                shape: BoxShape.circle,
              ),
              child: Icon(
                s.isCompleted
                    ? Icons.check_circle_rounded
                    : Icons.timer_off_rounded,
                color: s.isCompleted
                    ? const Color(0xFF4ECDC4)
                    : const Color(0xFFFF6B6B),
              ),
            ),
            title: Text(
              s.todoTitle ?? '自由专注',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(timeLabel, style: const TextStyle(fontSize: 13)),
                      if (tagNames != null) ...[
                        const SizedBox(width: 8),
                        Flexible(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Theme.of(context)
                                  .colorScheme
                                  .surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              tagNames,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 11),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (s.note != null && s.note!.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      s.note!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                  ],
                ],
              ),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  PomodoroService.formatDuration(s.effectiveDuration),
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(width: 4),
                IconButton(
                  icon: const Icon(Icons.more_vert, size: 20),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: () => _editSession(s),
                ),
              ],
            ),
          );

    return OptionalLiquidGlassCard(
      key: cardKey,
      borderRadius: widget.isCompact ? 12 : 16,
      margin: const EdgeInsets.only(bottom: 8),
      fallbackDecoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest
            .withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(widget.isCompact ? 12 : 16),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(widget.isCompact ? 12 : 16),
        onTap: () {
          PageTransitions.pushFromRect(
            context: context,
            page: PomodoroDetailScreen(record: s, tags: _tags),
            sourceKey: cardKey,
            sourceBorderRadius: BorderRadius.circular(
              widget.isCompact ? 12 : 16,
            ),
          );
        },
        child: Padding(
          padding: widget.isCompact
              ? const EdgeInsets.symmetric(horizontal: 10, vertical: 8)
              : EdgeInsets.zero,
          child: content,
        ),
      ),
    );
  }

  // 🚀 骨架屏：模拟趋势图和统计卡片
  Widget _buildSkeleton() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseColor = isDark
        ? Colors.white10
        : Colors.black.withValues(alpha: 0.05);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 导航栏骨架
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: baseColor,
                  shape: BoxShape.circle,
                ),
              ),
              Container(
                width: 120,
                height: 24,
                decoration: BoxDecoration(
                  color: baseColor,
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: baseColor,
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          // 图表骨架
          Container(
            height: 220,
            decoration: BoxDecoration(
              color: baseColor,
              borderRadius: BorderRadius.circular(24),
            ),
          ),
          const SizedBox(height: 20),
          // 概览卡片骨架
          Container(
            height: 100,
            decoration: BoxDecoration(
              color: baseColor,
              borderRadius: BorderRadius.circular(20),
            ),
          ),
          const SizedBox(height: 24),
          // 列表骨架
          ...List.generate(
            3,
            (i) => Container(
              height: 70,
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: baseColor,
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
