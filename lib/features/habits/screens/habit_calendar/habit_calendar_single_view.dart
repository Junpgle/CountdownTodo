part of '../habit_calendar_tab.dart';

extension _HabitCalendarSingleView on _HabitCalendarTabState {
  // ── 单习惯打卡日历大视图 ──────────────────────────────────
  Widget _buildSingleHabitView(
    BuildContext context, {
    required HabitGoal goal,
    required bool isWide,
    required double bottomPadding,
  }) {
    return _buildResponsiveCalendarView(
      isWide: isWide,
      bottomPadding: bottomPadding,
      calendarChildren: [
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
      detailSection: _buildSingleHabitDayDetail(goal),
      narrowDetailSpacing: 14,
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
    return _buildMonthDayGrid(
      cellBuilder: (date, day, isToday, isSelected, isFuture) {
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
            HabitDrinkLogService.extractDrinkIcons(dayCheckIns).isNotEmpty;

        return _buildCalendarDayCellShell(
          key: ValueKey('habit_calendar_single_day_$key'),
          onTap: () => _handleDayTap(date, focusedGoal: goal),
          backgroundColor: cellBg,
          borderColor: isSelected
              ? colorScheme.primary
              : isToday
              ? colorScheme.primary.withValues(alpha: 0.45)
              : isLit
              ? colorScheme.tertiary.withValues(alpha: 0.25)
              : Colors.transparent,
          borderWidth: isSelected ? 2 : 1,
          contentChildren: [
            Text(
              '$day',
              style: TextStyle(
                fontSize: isLit ? 11.5 : 13,
                fontWeight: isToday || isSelected
                    ? FontWeight.w800
                    : FontWeight.w500,
                color: isSelected ? colorScheme.primary : textColor,
              ),
            ),
            if (isLit) ...[
              const SizedBox(height: 1),
              Flexible(child: _buildDayLitIcons(litIcons, colorScheme)),
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
        );
      },
    );
  }

  // ── 单习惯图例 ─────────────────────────────────────
  Widget _buildSingleHabitLegend() {
    final colorScheme = Theme.of(context).colorScheme;
    return Wrap(
      spacing: 14,
      runSpacing: 8,
      children: [
        _buildLegendItem(colorScheme, colorScheme.tertiary, '已达标'),
        _buildLegendItem(colorScheme, colorScheme.error, '未完成'),
        _buildLegendItem(colorScheme, colorScheme.secondary, '进行中'),
        _buildLegendItem(
          colorScheme,
          colorScheme.secondary,
          '免扣保护',
          icon: Icon(
            Icons.shield_rounded,
            size: 12,
            color: colorScheme.secondary,
          ),
        ),
        _buildLegendItem(colorScheme, colorScheme.outline, '已跳过'),
      ],
    );
  }

  // ── 单习惯选中日明细 ──────────────────────────────────
  Widget _buildSingleHabitDayDetail(HabitGoal goal) {
    final colorScheme = Theme.of(context).colorScheme;
    final dayLabel = _formatSelectedDayLabel(_selectedDay);
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
          _buildEmptyDayDetailCard(colorScheme, '这一天没有打卡计划')
        else
          _buildDayRow(goal, dayProgress),
      ],
    );
  }
}
