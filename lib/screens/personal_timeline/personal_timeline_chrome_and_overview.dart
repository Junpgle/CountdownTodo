part of '../personal_timeline_screen.dart';

const LinearGradient _timelineTopFadeGradient = LinearGradient(
  begin: Alignment.topCenter,
  end: Alignment.bottomCenter,
  stops: [0.0, 0.18, 0.78, 1.0],
  colors: [Colors.white, Colors.white, Color(0x24FFFFFF), Colors.transparent],
);
Rect? _cachedTimelineTopFadeBounds;
Shader? _cachedTimelineTopFadeShader;

Shader _resolveTimelineTopFadeShader(Rect bounds) {
  if (_cachedTimelineTopFadeBounds == bounds &&
      _cachedTimelineTopFadeShader != null) {
    return _cachedTimelineTopFadeShader!;
  }
  _cachedTimelineTopFadeBounds = bounds;
  return _cachedTimelineTopFadeShader = _timelineTopFadeGradient.createShader(
    bounds,
  );
}

extension _PersonalTimelineChromeOverviewExt on _PersonalTimelineScreenState {
  Widget _buildSkeleton(ColorScheme cs) {
    return Column(
      key: const ValueKey('skeleton'),
      children: [
        Container(
          height: 110,
          width: double.infinity,
          decoration: BoxDecoration(
            color: cs.onSurface.withValues(alpha: 0.03),
            borderRadius: BorderRadius.circular(32),
          ),
        ),
        const SizedBox(height: 40),
        ...List.generate(
          3,
          (i) => Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Container(
              height: 90,
              width: double.infinity,
              decoration: BoxDecoration(
                color: cs.onSurface.withValues(alpha: 0.02),
                borderRadius: BorderRadius.circular(24),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTimelineTopFadeCap(ColorScheme cs, double topBarHeight) {
    final fadeHeight = topBarHeight + floatingGlassTopBarDefaultFadeTail;
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      height: fadeHeight,
      child: IgnorePointer(
        child: RepaintBoundary(
          child: Builder(
            builder: (context) {
              final screenSize = MediaQuery.sizeOf(context);
              return ShaderMask(
                blendMode: BlendMode.dstIn,
                shaderCallback: _resolveTimelineTopFadeShader,
                child: ClipRect(
                  child: OverflowBox(
                    alignment: Alignment.topCenter,
                    minWidth: screenSize.width,
                    maxWidth: screenSize.width,
                    minHeight: screenSize.height,
                    maxHeight: screenSize.height,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            cs.surface,
                            cs.primaryContainer.withValues(alpha: 0.08),
                            cs.secondaryContainer.withValues(alpha: 0.04),
                            cs.surface,
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildBackground(ColorScheme cs) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            cs.surface,
            cs.primaryContainer.withValues(alpha: 0.08),
            cs.secondaryContainer.withValues(alpha: 0.04),
            cs.surface,
          ],
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            bottom: 100,
            left: -100,
            child: _buildBlob(cs.secondary.withValues(alpha: 0.03), 400),
          ),
        ],
      ),
    );
  }

  Widget _buildBlob(Color color, double size) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      // Windows 的 BackdropFilter 会给透明窗口增加额外混合开销，
      // 这个 blob 只是背景光晕装饰，在 Windows 保留半透明圆形即可。
      child: AppPlatform.isWindows
          ? const SizedBox.shrink()
          : BackdropFilter(
              filter: AppImageFilters.blur80,
              child: Container(color: Colors.transparent),
            ),
    );
  }

  Widget _buildAppBar(BuildContext context) {
    // The visible toolbar lives in the fixed foreground layer below. This
    // sliver only reserves its height in the scrollable content; an empty
    // SliverAppBar would still introduce a material/shadow boundary.
    return SliverToBoxAdapter(
      child: SizedBox(
        height: MediaQuery.paddingOf(context).top + kToolbarHeight,
      ),
    );
  }

  Widget _buildTimelineToolbar(ColorScheme cs) {
    final isDark = cs.brightness == Brightness.dark;

    return FloatingGlassAppBar(
      primary: false,
      automaticallyImplyLeading: false,
      automaticallyImplyActions: false,
      backgroundColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      shadowColor: Colors.transparent,
      foregroundColor: cs.onSurface,
      forceMaterialTransparency: true,
      clipBehavior: Clip.hardEdge,
      centerTitle: true,
      // Do not use FloatingGlassAppBar's default full-width glass backdrop.
      // The timeline owns a separate paint-only fade mask below this
      // foreground toolbar.
      flexibleSpace: const SizedBox.shrink(),
      leadingWidth: 64,
      title: ValueListenableBuilder<double>(
        valueListenable: _timelineTitleProgress,
        builder: (context, progress, _) =>
            _buildTimelineAppBarTitle(cs, progress),
      ),
      leading: IconButton(
        tooltip: '返回',
        style: floatingGlassPlainIconButtonStyle(),
        icon: const Icon(Icons.arrow_back_rounded),
        iconSize: 22,
        onPressed: () => Navigator.pop(context),
      ),
      actionsPadding: const EdgeInsets.only(right: 8),
      actions: [
        IconButton(
          tooltip: '保存分享长图',
          style: floatingGlassPlainIconButtonStyle(),
          icon: _isExportingPoster
              ? SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: cs.primary,
                  ),
                )
              : const Icon(Icons.ios_share_outlined),
          iconSize: 22,
          onPressed: _isLoading || _isExportingPoster
              ? null
              : _chooseAndExportTimelinePoster,
        ),
      ],
      floatingControlTint: cs.surface,
      floatingControlIsDark: isDark,
    );
  }

  void _handleTimelineScroll() {
    if (!_timelineScrollController.hasClients) return;

    final scrollOffset = math.max(0.0, _timelineScrollController.offset);
    final labelOffset = _timelinePeriodLabelOffset(context);
    final titleProgress = floatingGlassTopBarTitleProgress(
      scrollOffset: scrollOffset,
      contentOffset: labelOffset,
    );
    if ((titleProgress - _timelineTitleProgress.value).abs() > 0.001) {
      _timelineTitleProgress.value = titleProgress;
    }
  }

  double _timelinePeriodLabelOffset(BuildContext context) {
    return _timelineGreetingTopPadding(context) + 21.0;
  }

  double _timelineGreetingTopPadding(BuildContext context) {
    final isCompact = MediaQuery.sizeOf(context).width < 600;
    return isCompact ? 24.0 : 32.0;
  }

  Widget _buildTimelineAppBarTitle(ColorScheme cs, double titleProgress) {
    final clamped = titleProgress.clamp(0.0, 1.0);
    if (clamped <= 0.001) return const SizedBox.shrink();
    return Text(
      _timelinePeriodLabel(),
      style: TextStyle(
        color: cs.onSurface.withValues(alpha: clamped),
        fontSize: 17,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.2,
      ),
    );
  }

  Widget _buildGreeting(ColorScheme cs) {
    final label = _timelinePeriodLabel();
    final sub = _timelinePeriodSubtitle();

    return Padding(
      padding: EdgeInsets.fromLTRB(
        24,
        _timelineGreetingTopPadding(context),
        24,
        8,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  sub,
                  style: TextStyle(
                    fontSize: 14,
                    color: cs.primary,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'Serif',
                  ),
                ),
                if (_dimension != TimelineDimension.daily) ...[
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHighest.withValues(alpha: 0.35),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      _getDateRangeString(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        color: cs.onSurfaceVariant.withValues(alpha: 0.72),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                Text(
                  _getMotivationText(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: cs.onSurfaceVariant.withValues(alpha: 0.6),
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ),
          ),
          Row(
            children: [
              _buildNavButton(Icons.chevron_left_rounded, () => _navigate(-1)),
              const SizedBox(width: 8),
              _buildNavButton(Icons.chevron_right_rounded, () => _navigate(1)),
            ],
          ),
        ],
      ),
    );
  }

  String _timelinePeriodLabel() {
    switch (_dimension) {
      case TimelineDimension.daily:
        return _timelineDateFormat('yyyy年MM月dd日').format(_selectedDate);
      case TimelineDimension.weekly:
        final start = AppTimeFormats.localDayStartOffset(
          AppTimeFormats.dayStart(_selectedDate),
          -(_selectedDate.weekday - 1),
        );
        final end = AppTimeFormats.localDayStartOffset(start, 6);
        return '${_timelineDateFormat('MM/dd').format(start)} - ${_timelineDateFormat('MM/dd').format(end)}';
      case TimelineDimension.monthly:
        return _timelineDateFormat('yyyy年MM月').format(_selectedDate);
      case TimelineDimension.yearly:
        return '${_selectedDate.year}年';
    }
  }

  String _timelinePeriodSubtitle() {
    switch (_dimension) {
      case TimelineDimension.daily:
        return _timelineDateFormat('EEEE', 'zh_CN').format(_selectedDate);
      case TimelineDimension.weekly:
        return '本周回顾';
      case TimelineDimension.monthly:
        return '月度总结';
      case TimelineDimension.yearly:
        return '年度回顾';
    }
  }

  Widget _buildNavButton(IconData icon, VoidCallback onTap) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, size: 20, color: cs.onSurfaceVariant),
      ),
    );
  }

  void _navigate(int direction) {
    _mutateState(() {
      switch (_dimension) {
        case TimelineDimension.daily:
          _selectedDate = AppTimeFormats.localDayStartOffset(
            _selectedDate,
            direction,
          );
          break;
        case TimelineDimension.weekly:
          _selectedDate = AppTimeFormats.localDayStartOffset(
            _selectedDate,
            direction * 7,
          );
          break;
        case TimelineDimension.monthly:
          _selectedDate = DateTime(
            _selectedDate.year,
            _selectedDate.month + direction,
            1,
          );
          break;
        case TimelineDimension.yearly:
          _selectedDate = DateTime(_selectedDate.year + direction, 1, 1);
          break;
      }
    });
    _loadData();
  }

  String _getDimensionName(TimelineDimension d) {
    switch (d) {
      case TimelineDimension.daily:
        return '日';
      case TimelineDimension.weekly:
        return '周';
      case TimelineDimension.monthly:
        return '月';
      case TimelineDimension.yearly:
        return '年';
    }
  }

  String _getDateRangeString() {
    if (_summary != null &&
        _summary!.actualStartTime != null &&
        _summary!.actualEndTime != null) {
      return '${_timelineDateFormat('yyyy.MM.dd').format(_summary!.actualStartTime!)} - ${_timelineDateFormat('yyyy.MM.dd').format(_summary!.actualEndTime!)}';
    }

    DateTime start;
    DateTime end;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(
      _selectedDate.year,
      _selectedDate.month,
      _selectedDate.day,
    );

    switch (_dimension) {
      case TimelineDimension.daily:
        return _timelineDateFormat('yyyy.MM.dd').format(day);
      case TimelineDimension.weekly:
        start = AppTimeFormats.localDayStartOffset(day, -(day.weekday - 1));
        end = AppTimeFormats.localDayStartOffset(start, 6);
        final displayEnd = end.isAfter(today) ? today : end;
        return '${_timelineDateFormat('yyyy.MM.dd').format(start)} - ${_timelineDateFormat('yyyy.MM.dd').format(displayEnd)}';
      case TimelineDimension.monthly:
        start = DateTime(day.year, day.month, 1);
        end = DateTime(day.year, day.month + 1, 0);
        final displayEnd = end.isAfter(today) ? today : end;
        return '${_timelineDateFormat('yyyy.MM.dd').format(start)} - ${_timelineDateFormat('yyyy.MM.dd').format(displayEnd)}';
      case TimelineDimension.yearly:
        start = DateTime(day.year, 1, 1);
        end = DateTime(day.year, 12, 31);
        final displayEnd = end.isAfter(today) ? today : end;
        return '${_timelineDateFormat('yyyy.MM.dd').format(start)} - ${_timelineDateFormat('yyyy.MM.dd').format(displayEnd)}';
    }
  }

  Widget _buildStatsOverview(ColorScheme cs, bool isWide) {
    final summary = _summary;
    if (summary == null) return const SizedBox();

    final focusTimeStr = _formatMinutes(_totalFocusMinutes);
    final completionRate = _totalCount > 0
        ? _completedCount / _totalCount
        : 0.0;
    final focusSessionCount = _pomodoroCount + _timeLogCount;
    final planAchievementRate = _plannedMinutes > 0
        ? _planActualSeconds / (_plannedMinutes * 60)
        : 0.0;
    final screenConversion = _screenTimeSeconds > 0
        ? (_totalFocusMinutes * 60) / _screenTimeSeconds
        : 0.0;
    final topSub = summary.topSubject;
    final subRatio = _subjectRatio(summary, topSub);
    final subjectName = topSub != '全能型' ? topSub : '多主题任务';
    final keywordText = _buildKeywordText(summary);
    final habitSummary = summary.habitSummary;
    final financeSummary = _financeSummary;
    final financeAccent = financeSummary.netExpenseMinor > 0
        ? cs.error
        : cs.primary;
    final qualityLine = focusSessionCount > 0
        ? '平均每段 ${summary.avgPomodoroMinutes.toStringAsFixed(0)} 分钟，深度投入占 ${_formatPercent(summary.deepWorkCount / focusSessionCount)}。'
        : '暂时没有可统计的专注质量数据。';
    final consecutiveLabel = _buildConsecutiveActiveLabel(
      summary.consecutiveActiveDays,
    );
    final achievements = <String>[
      if (_completedCount > 0 || _recurringCompletedCount == 0)
        '完成 $_completedCount 个任务',
      if (_recurringCompletedCount > 0) '完成 $_recurringCompletedCount 期重复任务',
      if (habitSummary.completedCount > 0)
        '完成 ${habitSummary.completedCount} 个习惯周期',
    ].join('，');

    final hero = OptionalLiquidGlassCard(
      width: double.infinity,
      padding: EdgeInsets.all(isWide ? 28 : 22),
      borderRadius: 32,
      highContrast: true,
      tint: cs.primary.withValues(alpha: 0.16),
      fallbackDecoration: BoxDecoration(
        color: cs.surfaceContainer.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.45)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(
              alpha: cs.brightness == Brightness.dark ? 0.18 : 0.04,
            ),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${_getPeriodName()}你累计投入 $focusTimeStr，$achievements。',
            style: TextStyle(
              fontSize: isWide ? 24 : 20,
              height: 1.25,
              fontWeight: FontWeight.w800,
              color: cs.onSurface,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '${summary.peakHour}:00 是你的黄金产出时段，$subjectName 占据了你 ${subRatio > 0 ? subRatio : (summary.homeworkRatio * 100).toInt()}% 的精力。$qualityLine',
            style: TextStyle(
              fontSize: 14,
              height: 1.55,
              color: cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 20),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _buildInsightPill(
                '完成率 ${_formatPercent(completionRate)}',
                Icons.check_circle_outline_rounded,
                cs.primary,
                cs,
              ),
              if (_planBlockCount > 0)
                _buildInsightPill(
                  '规划达成 ${_formatPercent(planAchievementRate)}',
                  Icons.event_available_outlined,
                  cs.tertiary,
                  cs,
                ),
              _buildInsightPill(
                consecutiveLabel,
                Icons.local_fire_department_outlined,
                Colors.deepOrange,
                cs,
              ),
              if (_recurringScheduledCount > 0)
                _buildInsightPill(
                  '重复完成 ${_formatPercent(_recurringResolvedCount > 0 ? _recurringCompletedCount / _recurringResolvedCount : 0)}',
                  Icons.repeat_rounded,
                  cs.secondary,
                  cs,
                ),
              if (habitSummary.habitCount > 0)
                _buildInsightPill(
                  '习惯完成 ${_formatPercent(habitSummary.completionRate)}',
                  Icons.self_improvement_outlined,
                  cs.tertiary,
                  cs,
                ),
              if (_pauseCount > 0)
                _buildInsightPill(
                  '暂停 $_pauseCount 次 · ${_formatSecondsCompact(_pauseSeconds)}',
                  Icons.pause_circle_outline_rounded,
                  cs.error,
                  cs,
                ),
              _buildInsightPill(
                '转化率 ${_formatPercent(screenConversion)}',
                Icons.desktop_windows_outlined,
                Colors.teal,
                cs,
              ),
              _buildInsightPill(
                '屏幕偏好 ${_topAppCategory ?? '学习办公'}',
                Icons.category_outlined,
                Colors.orange,
                cs,
              ),
              if (financeSummary.transactionCount > 0)
                _buildInsightPill(
                  '净支出 ${formatFinanceAmount(financeSummary.netExpenseMinor)}',
                  Icons.account_balance_wallet_outlined,
                  financeAccent,
                  cs,
                ),
              _buildInsightPill(
                '关键词 $keywordText',
                Icons.sell_outlined,
                Colors.indigo,
                cs,
              ),
            ],
          ),
        ],
      ),
    );

    Widget statsGrid;
    if (isWide) {
      statsGrid = Container(
        padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _buildStatItem(
              '总投入',
              focusTimeStr,
              '',
              Icons.spa_outlined,
              cs.primary,
              cs,
            ),
            _buildStatItem(
              '任务完成',
              '$_completedCount/$_totalCount',
              '',
              Icons.task_alt_rounded,
              cs.secondary,
              cs,
            ),
            _buildStatItem(
              '完成率',
              _formatPercent(completionRate),
              '',
              Icons.pie_chart_outline_rounded,
              Colors.green,
              cs,
            ),
            _buildStatItem(
              '平均投入',
              summary.avgPomodoroMinutes.toStringAsFixed(0),
              'min',
              Icons.psychology_outlined,
              Colors.purple,
              cs,
            ),
            _buildStatItem(
              'DDL冲刺',
              '$_deadlineSprintCount',
              '次',
              Icons.auto_graph_rounded,
              Colors.redAccent,
              cs,
            ),
            _buildStatItem(
              '最强主题',
              subjectName,
              '',
              Icons.category_outlined,
              Colors.orange,
              cs,
            ),
          ],
        ),
      );
    } else {
      statsGrid = Container(
        padding: const EdgeInsets.symmetric(vertical: 22),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildStatItem(
                  '总投入',
                  focusTimeStr,
                  '',
                  Icons.spa_outlined,
                  cs.primary,
                  cs,
                ),
                _buildStatItem(
                  '任务完成',
                  '$_completedCount/$_totalCount',
                  '',
                  Icons.task_alt_rounded,
                  cs.secondary,
                  cs,
                ),
                _buildStatItem(
                  '完成率',
                  _formatPercent(completionRate),
                  '',
                  Icons.pie_chart_outline_rounded,
                  Colors.green,
                  cs,
                ),
              ],
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildStatItem(
                  '平均投入',
                  summary.avgPomodoroMinutes.toStringAsFixed(0),
                  'min',
                  Icons.psychology_outlined,
                  Colors.purple,
                  cs,
                ),
                _buildStatItem(
                  'DDL冲刺',
                  '$_deadlineSprintCount',
                  '次',
                  Icons.auto_graph_rounded,
                  Colors.redAccent,
                  cs,
                ),
                _buildStatItem(
                  '最强主题',
                  subjectName,
                  '',
                  Icons.category_outlined,
                  Colors.orange,
                  cs,
                ),
              ],
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        hero,
        const SizedBox(height: 14),
        statsGrid,
        const SizedBox(height: 10),
        _buildAchievementStrip(cs),
      ],
    );
  }

  Widget _buildInsightPill(
    String text,
    IconData icon,
    Color color,
    ColorScheme cs,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 6),
          Text(
            text,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: cs.onSurface,
            ),
          ),
        ],
      ),
    );
  }

  String _buildConsecutiveActiveLabel(int days) {
    switch (_dimension) {
      case TimelineDimension.daily:
        return '截至${_formatTimelinePeriod(_dimension, _selectedDate)}连续活跃 $days 天';
      case TimelineDimension.weekly:
        return '本周最长连续活跃 $days 天';
      case TimelineDimension.monthly:
        return '本月最长连续活跃 $days 天';
      case TimelineDimension.yearly:
        return '本年最长连续活跃 $days 天';
    }
  }

  Widget _buildAchievementStrip(ColorScheme cs) {
    final badges = _earnedMedals();
    if (badges.isEmpty) return const SizedBox();

    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: badges.take(4).map((badge) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: cs.surfaceContainerLow,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.3)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(badge.icon, color: badge.color, size: 18),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    badge.title,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    badge.desc,
                    style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant),
                  ),
                ],
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  List<
    ({
      String title,
      String desc,
      DateTime? earnedAt,
      IconData icon,
      Color color,
    })
  >
  _earnedMedals() {
    // 这里的预览只展示当前时段内“第一次获得”的新勋章
    final rangeTarget = _medalRecommendation;
    final allTimeTarget = _allTimeRecommendation;
    if (rangeTarget == null || rangeTarget.earnedMedals.isEmpty) {
      return const [];
    }

    final allTimeProgressById = allTimeTarget == null
        ? null
        : _allTimeMedalIndexFor(allTimeTarget);
    final rangeStart = allTimeTarget == null ? null : _medalRangeStart();

    return rangeTarget.earnedMedals
        .where((p) {
          // 如果全记录数据还没好，先展示当前的（保底逻辑）
          if (allTimeTarget == null) return true;

          final allTimeProgress = allTimeProgressById![p.medal.id] ?? p;

          // 如果全量统计显示这个勋章是在当前选定时段之前获得的，就不要在预览里重复展示了
          if (allTimeProgress.earned && allTimeProgress.firstEarnedAt != null) {
            if (allTimeProgress.firstEarnedAt!.isBefore(rangeStart!)) {
              return false;
            }
          }
          return true;
        })
        .map((p) {
          return (
            title: p.medal.title,
            desc: p.medal.description,
            earnedAt: p.earnedAt ?? p.firstEarnedAt,
            icon: p.medal.icon,
            color: p.medal.color,
          );
        })
        .toList();
  }

  Map<String, MedalProgress> _allTimeMedalIndexFor(
    MedalRecommendation recommendation,
  ) {
    if (identical(_allTimeMedalIndexSource, recommendation)) {
      return _allTimeMedalProgressById;
    }

    final progressById = <String, MedalProgress>{};
    for (final progress in recommendation.allMedals) {
      progressById.putIfAbsent(progress.medal.id, () => progress);
    }
    _allTimeMedalIndexSource = recommendation;
    _allTimeMedalProgressById = progressById;
    return progressById;
  }

  DateTime _medalRangeStart() {
    switch (_dimension) {
      case TimelineDimension.daily:
        return DateTime(
          _selectedDate.year,
          _selectedDate.month,
          _selectedDate.day,
        );
      case TimelineDimension.weekly:
        return AppTimeFormats.localDayStartOffset(
          AppTimeFormats.dayStart(_selectedDate),
          -(_selectedDate.weekday - 1),
        );
      case TimelineDimension.monthly:
        return DateTime(_selectedDate.year, _selectedDate.month, 1);
      case TimelineDimension.yearly:
        return DateTime(_selectedDate.year, 1, 1);
    }
  }

  Widget _buildMedalWall(ColorScheme cs, bool isWide) {
    final medals = _earnedMedals();

    return Padding(
      padding: const EdgeInsets.only(top: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildSectionHeader('勋章墙', Icons.emoji_events_outlined, cs),
              // "进入勋章墙" 按钮
              if (_medalRecommendation != null)
                ElevatedButton.icon(
                  onPressed: () => _navigateToMedalWall(),
                  icon: const Icon(Icons.open_in_new_rounded, size: 18),
                  label: const Text('全部勋章'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: cs.primaryContainer,
                    foregroundColor: cs.onPrimaryContainer,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          if (medals.isEmpty)
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: cs.surfaceContainerLow,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  Icon(
                    Icons.emoji_events_outlined,
                    size: 48,
                    color: cs.outline,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '继续努力，您即将获得第一个勋章！',
                    style: TextStyle(color: cs.onSurfaceVariant),
                  ),
                ],
              ),
            )
          else
            GridView.builder(
              padding: EdgeInsets.zero,
              primary: false,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              findChildIndexCallback: (Key key) {
                if (key is ValueKey<String>) {
                  final title = key.value;
                  final idx = medals.indexWhere((m) => m.title == title);
                  return idx != -1 ? idx : null;
                }
                return null;
              },
              itemCount: medals.length,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: isWide ? 3 : 2,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                mainAxisExtent: 104,
              ),
              itemBuilder: (context, index) {
                final medal = medals[index];
                return RepaintBoundary(
                  key: ValueKey<String>(medal.title),
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: cs.outlineVariant.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 46,
                          height: 46,
                          decoration: BoxDecoration(
                            color: medal.color.withValues(alpha: 0.12),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(medal.icon, color: medal.color, size: 24),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                medal.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w900,
                                  color: cs.onSurface,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                medal.desc,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: cs.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                '获得于 ${_formatMedalTime(medal.earnedAt)}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 10,
                                  color: cs.onSurfaceVariant.withValues(
                                    alpha: 0.64,
                                  ),
                                  fontWeight: FontWeight.w600,
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
            ),
        ],
      ),
    );
  }

  String _formatMedalTime(DateTime? time) {
    if (time == null) return _getDateRangeString();
    switch (_dimension) {
      case TimelineDimension.daily:
        return _timelineDateFormat('HH:mm').format(time);
      case TimelineDimension.weekly:
      case TimelineDimension.monthly:
        return _timelineDateFormat('MM/dd HH:mm').format(time);
      case TimelineDimension.yearly:
        return _timelineDateFormat('yyyy/MM/dd').format(time);
    }
  }

  Widget _buildStatItem(
    String label,
    String value,
    String unit,
    IconData icon,
    Color color,
    ColorScheme cs,
  ) {
    return Expanded(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 12),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: cs.onSurface,
                  ),
                ),
                if (unit.isNotEmpty)
                  Text(
                    ' $unit',
                    style: TextStyle(
                      fontSize: 10,
                      color: cs.onSurfaceVariant.withValues(alpha: 0.5),
                    ),
                  ),
              ],
            ),
          ),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: cs.onSurfaceVariant.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }

  String _formatMinutes(int minutes) {
    final hours = minutes ~/ 60;
    final mins = minutes % 60;
    if (hours > 0 && mins > 0) return '$hours 小时 $mins 分钟';
    if (hours > 0) return '$hours 小时';
    return '$mins 分钟';
  }

  int get _recurringResolvedCount =>
      _recurringCompletedCount + _recurringMissedCount;

  int get _recurringEndingStreak => _recurrenceSeries.fold<int>(
    0,
    (longest, series) => math.max(longest, series.endingStreak),
  );

  String _formatSecondsCompact(int seconds) => formatDurationCompact(seconds);
}
