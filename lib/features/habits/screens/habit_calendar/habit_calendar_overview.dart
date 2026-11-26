part of '../habit_calendar_tab.dart';

extension _HabitCalendarOverview on _HabitCalendarTabState {
  // ── 总览聚合月历视图 ───────────────────────────────────
  Widget _buildOverviewCalendarView(
    BuildContext context, {
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
        _buildWeekdayHeader(),
        const SizedBox(height: 4),
        _buildDayGrid(),
        const SizedBox(height: 16),
        _buildLegend(),
      ],
      detailSection: _buildSelectedDayDetail(),
      narrowDetailSpacing: 16,
    );
  }

  Widget _buildWeekdayHeader() {
    return Row(
      children: AppTimeFormats.weekdayShortLabelsZh
          .map(
            (label) => Expanded(
              child: Center(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          )
          .toList(),
    );
  }

  Widget _buildDayGrid() {
    final colorScheme = Theme.of(context).colorScheme;
    return _buildMonthDayGrid(
      cellBuilder: (date, day, isToday, isSelected, isFuture) {
        final aggData = _aggregate(date);
        final aggregate = aggData.status;
        final ratio = aggData.ratio;
        final litIcons = _litIconsForDay(date);
        final hasLit = litIcons.isNotEmpty;
        final key = HabitRuleResolver.dayKey(date);

        Color bg = Colors.transparent;
        Color dot = colorScheme.outlineVariant;
        if (hasLit) {
          if (aggregate == _DayAggregate.allMet) {
            bg = colorScheme.tertiaryContainer.withValues(alpha: 0.8);
            dot = colorScheme.tertiary;
          } else if (aggregate == _DayAggregate.noneMet) {
            bg = colorScheme.errorContainer.withValues(alpha: 0.42);
            dot = colorScheme.error;
          } else {
            bg = colorScheme.primaryContainer.withValues(alpha: 0.55);
            dot = colorScheme.primary;
          }
        } else {
          switch (aggregate) {
            case _DayAggregate.allMet:
              bg = colorScheme.tertiaryContainer;
              dot = colorScheme.tertiary;
            case _DayAggregate.partial:
              bg = Colors.transparent;
              dot = colorScheme.tertiary;
            case _DayAggregate.noneMet:
            case _DayAggregate.none:
            case _DayAggregate.future:
              bg = Colors.transparent;
              dot = colorScheme.outlineVariant;
            case _DayAggregate.skipped:
              bg = colorScheme.surfaceContainerHighest.withValues(alpha: 0.45);
              dot = colorScheme.outline;
          }
        }

        return _buildCalendarDayCellShell(
          key: ValueKey('habit_calendar_day_$key'),
          onTap: () => _handleDayTap(date),
          backgroundColor: bg,
          borderColor: isSelected
              ? colorScheme.primary
              : isToday
              ? colorScheme.primary.withValues(alpha: 0.45)
              : hasLit
              ? colorScheme.primary.withValues(alpha: 0.22)
              : Colors.transparent,
          borderWidth: isSelected ? 2 : 1,
          backgroundOverlay:
              (!hasLit && ratio > 0.0 && aggregate == _DayAggregate.partial)
              ? Align(
                  alignment: Alignment.bottomCenter,
                  child: FractionallySizedBox(
                    heightFactor: ratio,
                    widthFactor: 1.0,
                    child: Container(
                      color: colorScheme.tertiaryContainer.withValues(
                        alpha: 0.6,
                      ),
                    ),
                  ),
                )
              : null,
          contentChildren: [
            Text(
              '$day',
              style: TextStyle(
                fontSize: hasLit ? 11.5 : 13,
                fontWeight: isToday || isSelected
                    ? FontWeight.w800
                    : FontWeight.w500,
                color: isFuture
                    ? colorScheme.onSurfaceVariant.withValues(alpha: 0.38)
                    : isSelected
                    ? colorScheme.primary
                    : colorScheme.onSurface,
              ),
            ),
            if (hasLit) ...[
              const SizedBox(height: 1),
              Flexible(child: _buildDayLitIcons(litIcons, colorScheme)),
            ] else ...[
              const SizedBox(height: 2),
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color:
                      aggregate == _DayAggregate.none ||
                          aggregate == _DayAggregate.future
                      ? Colors.transparent
                      : dot,
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  Widget _buildLegend() {
    final colorScheme = Theme.of(context).colorScheme;
    return Wrap(
      spacing: 16,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _buildLegendItem(colorScheme, colorScheme.tertiary, '全部完成'),
        _buildLegendItem(
          colorScheme,
          colorScheme.tertiary.withValues(alpha: 0.5),
          '部分完成',
        ),
        _buildLegendItem(colorScheme, colorScheme.outline, '已跳过'),
        Text(
          '点击日期可点亮习惯图标',
          style: TextStyle(
            fontSize: 11,
            color: colorScheme.primary,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  // ── 选中日明细（全部习惯列表） ──────────────────────────
  Widget _buildSelectedDayDetail() {
    final colorScheme = Theme.of(context).colorScheme;
    final dayLabel = _formatSelectedDayLabel(_selectedDay);
    final rows = <Widget>[];
    final key = HabitRuleResolver.dayKey(_selectedDay);

    for (final goal in _goals) {
      final dayProgress = _dayByHabitAndLogicalDate[goal.uuid]?[key];
      if (dayProgress == null) continue;
      if (goal.isArchived && !_hasHistoricalRecord(dayProgress)) continue;
      rows.add(_buildDayRow(goal, dayProgress));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                dayLabel,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: colorScheme.onSurface,
                ),
              ),
            ),
            if (!_isFutureDate(_selectedDay))
              FilledButton.tonalIcon(
                onPressed: () => _openLightUpSheet(_selectedDay),
                icon: const Icon(Icons.auto_awesome_rounded, size: 15),
                label: const Text('点亮图标', style: TextStyle(fontSize: 12.5)),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  minimumSize: const Size(0, 32),
                ),
              ),
          ],
        ),
        const SizedBox(height: 16),
        if (rows.isEmpty)
          _buildEmptyDayDetailCard(colorScheme, '这一天没有习惯计划')
        else
          ...rows,
      ],
    );
  }

  bool _hasHistoricalRecord(HabitDayProgress day) {
    final progress = day.progress;
    return progress.hasRecord ||
        progress.goalMet ||
        progress.isSkipped ||
        progress.isFrozen;
  }

  Widget _buildDayRow(HabitGoal goal, HabitDayProgress day) {
    final colorScheme = Theme.of(context).colorScheme;
    final status = day.status;
    final (Color color, String label) = switch (status) {
      HabitDayStatus.met => (colorScheme.tertiary, '已完成'),
      HabitDayStatus.missed => (colorScheme.error, '未完成'),
      HabitDayStatus.inProgress => (colorScheme.secondary, '进行中'),
      HabitDayStatus.notPlanned => (colorScheme.outline, '无计划'),
      HabitDayStatus.skipped => (colorScheme.outline, '已跳过'),
      HabitDayStatus.frozen => (colorScheme.primary, '免扣保护'),
    };

    final dayKey = HabitRuleResolver.dayKey(day.logicalDate);
    final dayCheckIns =
        _checkInsByHabitAndLogicalDate[goal.uuid]?[dayKey] ??
        const <HabitCheckIn>[];
    final drinkSummary = HabitDrinkLogService.formatDrinkSummary(dayCheckIns);
    final isDrinkChoice = HabitDrinkLogService.isDrinkChoiceHabit(goal);
    final rawDetail = _dayValueText(goal, day);
    final detail = drinkSummary.isNotEmpty
        ? (isDrinkChoice ? '破戒：$drinkSummary' : drinkSummary)
        : (isDrinkChoice && status == HabitDayStatus.met
              ? '没喝饮料 · 打卡成功'
              : rawDetail);
    final rowIcon = drinkSummary.isNotEmpty
        ? HabitDrinkLogService.extractDrinkIcons(dayCheckIns).first
        : (goal.icon.isNotEmpty ? goal.icon : '🎯');

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          InkWell(
            onTap: () {
              _mutateState(() => _selectedHabitUuid = goal.uuid);
            },
            borderRadius: BorderRadius.circular(8),
            child: Text(rowIcon, style: const TextStyle(fontSize: 22)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: InkWell(
              onTap: () {
                _mutateState(() => _selectedHabitUuid = goal.uuid);
              },
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          goal.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: colorScheme.onSurface,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          label,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: color,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (detail.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    HabitEmojiText(
                      detail,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          if (!isDrinkChoice) ...[
            _buildFreezeButton(goal, day, colorScheme),
            const SizedBox(width: 8),
            if (goal.sourceType == HabitSourceType.recurringTodo) ...[
              _buildMakeUpButton(goal, day),
              const SizedBox(width: 8),
              _buildSkipButton(goal, day, colorScheme, label),
            ] else
              _buildSkipButton(goal, day, colorScheme, label),
          ] else if (!_isFutureDate(day.logicalDate)) ...[
            OutlinedButton(
              onPressed: () => _openDrinkPickerForDate(goal, day.logicalDate),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                minimumSize: const Size(0, 32),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text('记录饮品'),
            ),
            const SizedBox(width: 6),
            _buildSkipButton(goal, day, colorScheme, label),
          ],
        ],
      ),
    );
  }

  /// 计划内且非未来日期支持「使用免扣卡 / 取消免扣守护」。
  Widget _buildFreezeButton(
    HabitGoal goal,
    HabitDayProgress day,
    ColorScheme colorScheme,
  ) {
    final now = DateTime.now();
    final today = CalendarDateMath.dateOnly(now);
    if (day.logicalDate.isAfter(today) || !day.progress.isPlanned) {
      return const SizedBox.shrink();
    }
    final isFrozen = day.status == HabitDayStatus.frozen;
    final isMissed = day.status == HabitDayStatus.missed;
    if (!isFrozen && !isMissed) return const SizedBox.shrink();

    return OutlinedButton.icon(
      onPressed: () async {
        final rule = HabitRuleResolver.effectiveRule(
          _rulesByHabit[goal.uuid] ?? const [],
          day.logicalDate,
        );
        if (rule == null) return;
        if (isFrozen) {
          final checkIns = await HabitRepository.getCheckIns(
            habitUuid: goal.uuid,
          );
          final dateKey = HabitRuleResolver.dayKey(day.logicalDate);
          final freezeCheckIn = checkIns
              .where(
                (c) =>
                    !c.isDeleted &&
                    c.logicalDate == dateKey &&
                    c.source == HabitCheckInSource.freeze,
              )
              .firstOrNull;
          if (freezeCheckIn != null) {
            await HabitFreezeService.revokeFreeze(
              goal: goal,
              freezeCheckIn: freezeCheckIn,
            );
            _loadData();
          }
        } else {
          final checkIns = await HabitRepository.getCheckIns(
            habitUuid: goal.uuid,
          );
          final validation = await HabitFreezeService.canApplyFreeze(
            goal: goal,
            rule: rule,
            logicalDate: day.logicalDate,
            checkIns: checkIns,
            rules: _rulesByHabit[goal.uuid],
          );
          if (!validation.canApply) {
            if (mounted) {
              AppSnackBars.showSnackBar(
                context,
                SnackBar(content: Text(validation.reason ?? '当前条件不满足')),
              );
            }
            return;
          }
          await HabitFreezeService.applyFreeze(
            goal: goal,
            rule: rule,
            logicalDate: day.logicalDate,
            username: widget.username,
            rules: _rulesByHabit[goal.uuid],
          );
          _loadData();
        }
      },
      icon: Icon(
        Icons.shield_outlined,
        size: 13,
        color: isFrozen ? colorScheme.secondary : colorScheme.primary,
      ),
      label: Text(isFrozen ? '取消免扣' : '用免扣卡'),
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        minimumSize: const Size(0, 32),
        foregroundColor: isFrozen ? colorScheme.secondary : colorScheme.primary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  /// 非完成型习惯：计划内且非未来日期支持「跳过 / 取消跳过」。
  Widget _buildSkipButton(
    HabitGoal goal,
    HabitDayProgress day,
    ColorScheme colorScheme,
    String label,
  ) {
    final now = DateTime.now();
    final today = CalendarDateMath.dateOnly(now);
    if (day.logicalDate.isAfter(today) || !day.progress.isPlanned) {
      return const SizedBox.shrink();
    }
    final skipped = day.status == HabitDayStatus.skipped;
    return OutlinedButton(
      onPressed: () async {
        final rule = HabitRuleResolver.effectiveRule(
          _rulesByHabit[goal.uuid] ?? const [],
          day.logicalDate,
        );
        if (rule == null) return;
        await HabitRepository.toggleSkipped(
          goal: goal,
          rule: rule,
          localDate: day.logicalDate,
        );
        _loadData();
      },
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        minimumSize: const Size(0, 32),
        foregroundColor: skipped
            ? colorScheme.onSurfaceVariant
            : colorScheme.outline,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      child: Text(skipped ? '取消跳过' : '跳过'),
    );
  }

  String _dayValueText(HabitGoal goal, HabitDayProgress day) {
    final progress = day.progress;
    switch (goal.sourceType) {
      case HabitSourceType.recurringTodo:
        return '';
      case HabitSourceType.pomodoroTag:
        return HabitText.durationProgress(progress);
      case HabitSourceType.durationCheckIn:
        return HabitText.durationProgressForGoal(goal, progress);
      case HabitSourceType.quantityCheckIn:
        return HabitText.amountProgress(progress, _unitOf(goal));
      case HabitSourceType.timeCheckIn:
        final actual = progress.firstRecordAt;
        if (actual == null) return '未打卡';
        return '${HabitText.timeOfDay(actual)} · '
            '${HabitText.timePointStatus(_ruleOf(goal), progress)}';
    }
  }

  String _unitOf(HabitGoal goal) {
    final rules = _rulesByHabit[goal.uuid];
    if (rules == null || rules.isEmpty) return '';
    final rule = HabitRuleResolver.effectiveRule(rules, _selectedDay);
    return rule?.unit ?? '';
  }

  HabitGoalRuleRevision _ruleOf(HabitGoal goal) {
    final rules = _rulesByHabit[goal.uuid] ?? const [];
    return HabitRuleResolver.effectiveRule(rules, _selectedDay) ??
        HabitGoalRuleRevision(
          habitUuid: goal.uuid,
          effectiveFromDate: '',
          periodType: HabitPeriodType.daily,
        );
  }

  /// 完成型习惯：历史日期补卡 / 撤销。
  Widget _buildMakeUpButton(HabitGoal goal, HabitDayProgress day) {
    final colorScheme = Theme.of(context).colorScheme;
    final met = day.status == HabitDayStatus.met;
    return OutlinedButton(
      onPressed: () async {
        await HabitRepository.toggleCompletion(
          goal: goal,
          logicalDate: day.logicalDate,
          username: widget.username,
        );
        _loadData();
      },
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        minimumSize: const Size(0, 32),
        foregroundColor: met
            ? colorScheme.onSurfaceVariant
            : colorScheme.primary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      child: Text(met ? '撤销' : '补卡'),
    );
  }
}
