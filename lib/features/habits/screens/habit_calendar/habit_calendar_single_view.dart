part of '../habit_calendar_tab.dart';

extension _HabitCalendarSingleView on _HabitCalendarTabState {
  // ── 单习惯打卡日历大视图 ──────────────────────────────────
  Widget _buildSingleHabitView(
    BuildContext context, {
    required HabitGoal goal,
    required bool isWide,
    required double bottomPadding,
  }) {
    if (isWide) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 5,
            child: RefreshIndicator(
              edgeOffset: widget.topPadding,
              onRefresh: _loadData,
              child: ListView(
                padding: EdgeInsets.fromLTRB(
                  16,
                  widget.topPadding + 12,
                  16,
                  bottomPadding,
                ),
                children: [
                  _buildMonthHeader(),
                  const SizedBox(height: 10),
                  _buildHabitFilterBar(),
                  const SizedBox(height: 14),
                  _buildSingleHabitSummaryCard(goal),
                  const SizedBox(height: 14),
                  _buildWeekdayHeader(),
                  const SizedBox(height: 4),
                  _buildSingleHabitDayGrid(goal),
                  const SizedBox(height: 14),
                  _buildSingleHabitLegend(),
                ],
              ),
            ),
          ),
          const VerticalDivider(width: 1, thickness: 1, color: Colors.black12),
          Expanded(
            flex: 4,
            child: ListView(
              padding: EdgeInsets.fromLTRB(
                16,
                widget.topPadding + 12,
                16,
                bottomPadding,
              ),
              children: [_buildSingleHabitDayDetail(goal)],
            ),
          ),
        ],
      );
    }

    return RefreshIndicator(
      edgeOffset: widget.topPadding,
      onRefresh: _loadData,
      child: ListView(
        padding: EdgeInsets.fromLTRB(
          16,
          widget.topPadding + 12,
          16,
          bottomPadding,
        ),
        children: [
          _buildMonthHeader(),
          const SizedBox(height: 10),
          _buildHabitFilterBar(),
          const SizedBox(height: 14),
          _buildSingleHabitSummaryCard(goal),
          const SizedBox(height: 14),
          _buildWeekdayHeader(),
          const SizedBox(height: 4),
          _buildSingleHabitDayGrid(goal),
          const SizedBox(height: 14),
          _buildSingleHabitLegend(),
          const SizedBox(height: 14),
          _buildSingleHabitDayDetail(goal),
        ],
      ),
    );
  }

  // ── 单习惯本月打卡统计小卡片 ─────────────────────────────
  Widget _buildSingleHabitSummaryCard(HabitGoal goal) {
    final colorScheme = Theme.of(context).colorScheme;
    final summary = _computeGoalMonthSummary(goal);
    final ratePercent = (summary.rate * 100).round();

    Widget statItem({
      required String label,
      required String value,
      Color? valueColor,
    }) {
      return Expanded(
        child: Column(
          children: [
            Text(
              value,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: valueColor ?? colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 11.5,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Text(
                goal.icon.isNotEmpty ? goal.icon : '🎯',
                style: const TextStyle(fontSize: 20),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${goal.name} · 本月打卡日历',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                    color: colorScheme.onSurface,
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: () async {
                  final changed = await Navigator.of(context).push<bool>(
                    PageTransitions.material(
                      builder: (_) => HabitDetailScreen(
                        goal: goal,
                        username: widget.username,
                      ),
                    ),
                  );
                  if (changed == true && mounted) {
                    _loadData();
                  }
                },
                icon: const Icon(Icons.arrow_forward_ios_rounded, size: 12),
                label: const Text('详情', style: TextStyle(fontSize: 12.5)),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: const Size(0, 30),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Divider(height: 1, thickness: 0.5),
          const SizedBox(height: 10),
          Row(
            children: [
              statItem(
                label: '已达标',
                value: '${summary.metDays}天',
                valueColor: colorScheme.tertiary,
              ),
              statItem(
                label: '达成率',
                value: '$ratePercent%',
                valueColor: colorScheme.primary,
              ),
              statItem(label: '计划天数', value: '${summary.plannedDays}天'),
              statItem(
                label: '免扣/跳过',
                value: '${summary.frozenDays}/${summary.skippedDays}天',
                valueColor: summary.frozenDays > 0
                    ? colorScheme.secondary
                    : null,
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── 单习惯大日历网格 ──────────────────────────────────
  Widget _buildSingleHabitDayGrid(HabitGoal goal) {
    final colorScheme = Theme.of(context).colorScheme;
    final firstDay = DateTime(_month.year, _month.month, 1);
    final daysInMonth = DateTime(_month.year, _month.month + 1, 0).day;
    final leadingBlanks = firstDay.weekday - 1;

    final cells = <Widget>[];
    for (int i = 0; i < leadingBlanks; i++) {
      cells.add(const SizedBox.shrink());
    }

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    for (int day = 1; day <= daysInMonth; day++) {
      final date = DateTime(_month.year, _month.month, day);
      final isToday =
          date.year == today.year &&
          date.month == today.month &&
          date.day == today.day;
      final isSelected =
          date.year == _selectedDay.year &&
          date.month == _selectedDay.month &&
          date.day == _selectedDay.day;
      final isFuture = date.isAfter(today);

      final key = HabitRuleResolver.dayKey(date);
      final dayProgress = _dayByHabitAndLogicalDate[goal.uuid]?[key];
      final dayCheckIns =
          _checkInsByHabitAndLogicalDate[goal.uuid]?[key] ??
          const <HabitCheckIn>[];
      final isLit = _isHabitLitOnDay(goal, date);
      final hasDrinkFailure =
          !isFuture &&
          HabitDrinkLogService.isDrinkChoiceHabit(goal) &&
          HabitDrinkLogService.extractDrinkIcons(dayCheckIns).isNotEmpty;

      HabitDayStatus? status;
      if (!isFuture && dayProgress != null) {
        if (!goal.isArchived || _hasHistoricalRecord(dayProgress)) {
          status = dayProgress.status;
        }
      }

      Color cellBg = Colors.transparent;
      Color textColor = colorScheme.onSurface;
      Color dotColor = Colors.transparent;
      String subText = '';

      if (isFuture) {
        textColor = colorScheme.onSurfaceVariant.withValues(alpha: 0.35);
      } else if (hasDrinkFailure) {
        cellBg = colorScheme.errorContainer.withValues(alpha: 0.45);
        textColor = colorScheme.onErrorContainer;
        dotColor = colorScheme.error;
      } else if (isLit) {
        cellBg = colorScheme.tertiaryContainer.withValues(alpha: 0.82);
        textColor = colorScheme.onTertiaryContainer;
        dotColor = colorScheme.tertiary;
        if (dayProgress != null) {
          final compact = _compactDayValue(goal, dayProgress);
          if (compact.isNotEmpty && compact != '✓') {
            subText = compact;
          }
        }
      } else {
        switch (status) {
          case HabitDayStatus.met:
            cellBg = colorScheme.tertiaryContainer;
            textColor = colorScheme.onTertiaryContainer;
            dotColor = colorScheme.tertiary;
          case HabitDayStatus.frozen:
            cellBg = colorScheme.secondaryContainer.withValues(alpha: 0.55);
            textColor = colorScheme.onSecondaryContainer;
            dotColor = colorScheme.secondary;
          case HabitDayStatus.skipped:
            cellBg = colorScheme.surfaceContainerHighest.withValues(
              alpha: 0.45,
            );
            textColor = colorScheme.outline;
            dotColor = colorScheme.outline;
          case HabitDayStatus.inProgress:
            cellBg = Colors.transparent;
            dotColor = colorScheme.secondary;
          case HabitDayStatus.missed:
            cellBg = colorScheme.errorContainer.withValues(alpha: 0.15);
            dotColor = colorScheme.error;
          case HabitDayStatus.notPlanned:
          case null:
            textColor = colorScheme.onSurfaceVariant.withValues(alpha: 0.4);
        }
      }

      final litIcons = _litIconsForHabitOnDay(goal, date);
      final hasDrinkSelection =
          isLit &&
          HabitDrinkLogService.extractDrinkIcons(
            _checkInsByHabitAndLogicalDate[goal.uuid]?[key] ??
                const <HabitCheckIn>[],
          ).isNotEmpty;

      cells.add(
        GestureDetector(
          key: ValueKey('habit_calendar_single_day_$key'),
          onTap: () => _handleDayTap(date, focusedGoal: goal),
          child: Container(
            margin: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: isSelected
                    ? colorScheme.primary
                    : isToday
                    ? colorScheme.primary.withValues(alpha: 0.45)
                    : isLit
                    ? colorScheme.tertiary.withValues(alpha: 0.25)
                    : Colors.transparent,
                width: isSelected ? 2 : 1,
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Stack(
                children: [
                  Container(color: cellBg),
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 2,
                        vertical: 2,
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            '$day',
                            style: TextStyle(
                              fontSize: isLit ? 11.5 : 13,
                              fontWeight: isToday || isSelected
                                  ? FontWeight.w800
                                  : FontWeight.w500,
                              color: isSelected
                                  ? colorScheme.primary
                                  : textColor,
                            ),
                          ),
                          if (isLit) ...[
                            const SizedBox(height: 1),
                            Flexible(
                              child: _buildDayLitIcons(litIcons, colorScheme),
                            ),
                            if (!hasDrinkSelection && subText.isNotEmpty)
                              FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  subText,
                                  maxLines: 1,
                                  style: TextStyle(
                                    fontSize: 8.5,
                                    fontWeight: FontWeight.w700,
                                    color: colorScheme.tertiary,
                                  ),
                                ),
                              ),
                          ] else if (status == HabitDayStatus.frozen) ...[
                            const SizedBox(height: 2),
                            Icon(
                              Icons.shield_rounded,
                              size: 8.5,
                              color: colorScheme.secondary,
                            ),
                          ] else ...[
                            const SizedBox(height: 2),
                            Container(
                              width: 5.5,
                              height: 5.5,
                              decoration: BoxDecoration(
                                color: dotColor,
                                shape: BoxShape.circle,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return GridView.count(
      padding: EdgeInsets.zero,
      primary: false,
      crossAxisCount: 7,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: 0.84,
      children: cells,
    );
  }

  // ── 单习惯图例 ─────────────────────────────────────
  Widget _buildSingleHabitLegend() {
    final colorScheme = Theme.of(context).colorScheme;
    Widget item(Color color, String label, {Widget? icon}) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null)
            icon
          else
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
          ),
        ],
      );
    }

    return Wrap(
      spacing: 14,
      runSpacing: 8,
      children: [
        item(colorScheme.tertiary, '已达标'),
        item(colorScheme.error, '未完成'),
        item(colorScheme.secondary, '进行中'),
        item(
          colorScheme.secondary,
          '免扣保护',
          icon: Icon(
            Icons.shield_rounded,
            size: 12,
            color: colorScheme.secondary,
          ),
        ),
        item(colorScheme.outline, '已跳过'),
      ],
    );
  }

  // ── 单习惯选中日明细 ──────────────────────────────────
  Widget _buildSingleHabitDayDetail(HabitGoal goal) {
    final colorScheme = Theme.of(context).colorScheme;
    final dayLabel =
        '${_selectedDay.month} 月 ${_selectedDay.day} 日'
        ' · 周${'一二三四五六日'[_selectedDay.weekday - 1]}';
    final key = HabitRuleResolver.dayKey(_selectedDay);
    final dayProgress = _dayByHabitAndLogicalDate[goal.uuid]?[key];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              dayLabel,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: colorScheme.onSurface,
              ),
            ),
            TextButton.icon(
              onPressed: () => _mutateState(() => _selectedHabitUuid = null),
              icon: const Icon(Icons.arrow_back_rounded, size: 14),
              label: const Text('查看全部', style: TextStyle(fontSize: 12.5)),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (dayProgress == null)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 24),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(
              '这一天没有打卡计划',
              style: TextStyle(
                fontSize: 14,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          )
        else
          _buildDayRow(goal, dayProgress),
      ],
    );
  }
}
