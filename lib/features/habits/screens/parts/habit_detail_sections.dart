part of '../habit_detail_screen.dart';

extension _HabitDetailSections on _HabitDetailScreenState {
  // ── 今日进度卡 ──────────────────────────────────────
  Widget _buildTodayCard(ColorScheme colorScheme) {
    final progress = _todayProgress!;
    final isHydration =
        HabitAdaptationService.forHabit(_goal)?.kind ==
        HabitAdaptationKind.hydration;
    final dayProgress = HabitDayProgress(
      habit: _goal,
      logicalDate: HabitSleepDurationService.displayLogicalDateFor(
        _goal,
        DateTime.now(),
      ),
      status: progress.dayStatus,
      progress: progress,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        HabitCard(
          key: ValueKey('habit-detail-${_goal.uuid}'),
          goal: _goal,
          rule: _rule,
          dayProgress: dayProgress,
          username: widget.username,
          onChanged: _loadData,
          onStartFocus: (_) => _startFocus(),
          animationKey: _detailCardKey,
          onViewRecords: () => _openHistory(sourceKey: _detailCardKey),
        ),
        if (isHydration)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: HabitWaterProgressCard(
              currentValue: progress.currentValue,
              targetValue: progress.targetValue,
              unit: _rule.unit.isEmpty ? 'ml' : _rule.unit,
              recordCount: progress.recordCount,
            ),
          ),
        if (_goal.sourceType == HabitSourceType.quantityCheckIn ||
            _goal.sourceType == HabitSourceType.timeCheckIn)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _openHistory(sourceKey: _detailCardKey),
                    icon: const Icon(Icons.history_rounded, size: 16),
                    label: const Text('历史记录'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _addBackfill,
                    icon: const Icon(
                      Icons.add_circle_outline_rounded,
                      size: 16,
                    ),
                    label: const Text('补录'),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  // ── 今日专注记录（时长型）────────────────────────────
  Widget _buildFocusRecordSection(ColorScheme colorScheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '今日专注（${_todayFocusRecords.length}）',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: colorScheme.onSurface,
                ),
              ),
            ),
            TextButton(
              onPressed: () => _openHistory(sourceKey: _detailCardKey),
              child: const Text('查看全部'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ..._todayFocusRecords.map(
          (record) => Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(Icons.timer_rounded, size: 18, color: colorScheme.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        HabitText.formatDuration(
                          record.actualDuration ?? record.plannedDuration,
                        ),
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          color: colorScheme.onSurface,
                        ),
                      ),
                      if (record.note?.isNotEmpty == true)
                        Text(
                          record.note!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11.5,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
                Text(
                  HabitText.timeOfDay(
                    DateTime.fromMillisecondsSinceEpoch(record.startTime)
                        .toLocal(),
                  ),
                  style: TextStyle(
                    fontSize: 12,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ── 今日记录列表 ────────────────────────────────────
  Widget _buildRecordSection(ColorScheme colorScheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '$_displayPeriodLabel记录（${_todayCheckIns.length}）',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: colorScheme.onSurface,
                ),
              ),
            ),
            TextButton(
              onPressed: () => _openHistory(sourceKey: _detailCardKey),
              child: const Text('查看全部'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        for (final checkIn in _todayCheckIns)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(
                  checkIn.source == HabitCheckInSource.freeze
                      ? Icons.shield_outlined
                      : (_goal.sourceType == HabitSourceType.timeCheckIn
                            ? Icons.schedule_rounded
                            : Icons.add_circle_outline_rounded),
                  size: 18,
                  color: checkIn.source == HabitCheckInSource.freeze
                      ? colorScheme.secondary
                      : colorScheme.primary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      HabitEmojiText(
                        _recordMainText(checkIn),
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          color: colorScheme.onSurface,
                        ),
                      ),
                      if (checkIn.note?.isNotEmpty == true)
                        HabitEmojiText(
                          checkIn.note!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11.5,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
                Text(
                  HabitText.timeOfDay(
                    DateTime.fromMillisecondsSinceEpoch(checkIn.occurredAt)
                        .toLocal(),
                  ),
                  style: TextStyle(
                    fontSize: 12,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                if (checkIn.source != HabitCheckInSource.skip &&
                    checkIn.source != HabitCheckInSource.freeze)
                  IconButton(
                    tooltip: '编辑记录',
                    onPressed: () => _editRecord(checkIn),
                    icon: const Icon(Icons.edit_outlined, size: 18),
                  ),
                IconButton(
                  tooltip: '删除记录',
                  onPressed: () => _deleteRecord(checkIn),
                  icon: Icon(
                    Icons.delete_outline_rounded,
                    size: 18,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildDrinkStatsCard(ColorScheme colorScheme) {
    final stats = _drinkStats ?? const HabitDrinkStats.empty();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.45),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.local_cafe_rounded,
                size: 18,
                color: colorScheme.primary,
              ),
              const SizedBox(width: 6),
              Text(
                '饮品摄入统计',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: colorScheme.onSurface,
                ),
              ),
              const Spacer(),
              Text(
                '按饮品记录统计',
                style: TextStyle(
                  fontSize: 11.5,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildDrinkStatTile(
                  colorScheme,
                  label: '近 7 天喝了',
                  value: '${stats.last7DaysDrinks} 次',
                  subtitle: stats.last7DaysDrinkDays > 0
                      ? '${stats.last7DaysDrinkDays} 天有记录'
                      : '近 7 天未喝饮料',
                  highlight: stats.last7DaysDrinks > 0,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildDrinkStatTile(
                  colorScheme,
                  label: '累计喝了',
                  value: '${stats.totalDrinks} 次',
                  subtitle: stats.totalDrinkDays > 0
                      ? '共 ${stats.totalDrinkDays} 天有记录'
                      : '暂无饮料记录',
                  highlight: false,
                ),
              ),
            ],
          ),
          if (stats.breakdown.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: stats.breakdown.map((item) {
                final detailText = item.last7DaysCount > 0
                    ? '累计 ${item.totalCount} · 近7天 ${item.last7DaysCount}'
                    : '累计 ${item.totalCount}';
                return Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest.withValues(
                      alpha: 0.6,
                    ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${item.icon} ${item.label} · $detailText',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: colorScheme.onSurface,
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDrinkStatTile(
    ColorScheme colorScheme, {
    required String label,
    required String value,
    required String subtitle,
    required bool highlight,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: highlight
            ? colorScheme.errorContainer.withValues(alpha: 0.45)
            : colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: highlight ? colorScheme.error : colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 11.5,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAdaptationSection(ColorScheme colorScheme) {
    final adaptation = HabitAdaptationService.forHabit(_goal);
    if (adaptation == null) return const SizedBox.shrink();
    final isSleepAdaptation =
        adaptation.kind == HabitAdaptationKind.earlyWake ||
        adaptation.kind == HabitAdaptationKind.earlySleep;
    final isPushUpAdaptation = adaptation.kind == HabitAdaptationKind.pushUp;
    final isRunningAdaptation = adaptation.kind == HabitAdaptationKind.running;
    final isReadingAdaptation = adaptation.kind == HabitAdaptationKind.reading;
    final isLearningAdaptation =
        adaptation.kind == HabitAdaptationKind.learning;
    final isVocabularyAdaptation =
        adaptation.kind == HabitAdaptationKind.vocabulary;
    final isMeditationAdaptation =
        adaptation.kind == HabitAdaptationKind.meditation;
    final isSleepDurationAdaptation =
        adaptation.kind == HabitAdaptationKind.sleepDuration;
    final isQuitSugaryDrinksAdaptation =
        adaptation.kind == HabitAdaptationKind.quitSugaryDrinks;
    final isFocusDurationAdaptation =
        isReadingAdaptation || isLearningAdaptation || isMeditationAdaptation;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        HabitAdaptationPanel(
          adaptation: adaptation,
          currentValue: (isSleepAdaptation || isQuitSugaryDrinksAdaptation)
              ? null
              : isSleepDurationAdaptation
              ? _todayProgress == null
                    ? null
                    : _todayProgress!.currentValue / 3600
              : isFocusDurationAdaptation
              ? _todayProgress == null
                    ? null
                    : _todayProgress!.currentValue / 60
              : _todayProgress?.currentValue,
          targetValue: (isSleepAdaptation || isQuitSugaryDrinksAdaptation)
              ? null
              : isSleepDurationAdaptation
              ? _rule.targetValue / 3600
              : isFocusDurationAdaptation
              ? _rule.targetValue / 60
              : _rule.targetValue,
          targetUnitOverride: isSleepDurationAdaptation
              ? '小时'
              : _rule.unit.isEmpty
              ? null
              : _rule.unit,
        ),
        if (isSleepAdaptation || isSleepDurationAdaptation) ...[
          const SizedBox(height: 12),
          HabitSleepCoachingCard(
            kind: adaptation.kind,
            snapshot: _sleepCoachingSnapshot,
            onEnable: _enableSleepCoaching,
            onPauseChanged: _setSleepCoachingPaused,
            onEnabledChanged: _setSleepCoachingEnabled,
            onSettingsChanged: _updateSleepCoachingSettings,
          ),
        ],
        if (isSleepAdaptation) ...[
          const SizedBox(height: 12),
          HabitSleepTimingGuide(
            adaptation: adaptation,
            targetMinute: _rule.targetTimeMinute ?? 0,
          ),
        ],
        if (isPushUpAdaptation) ...[
          const SizedBox(height: 12),
          HabitPushUpGuide(
            targetValue: _rule.targetValue.round(),
            periodType: _rule.periodType,
          ),
        ],
        if (isRunningAdaptation) ...[
          const SizedBox(height: 12),
          HabitRunningGuide(
            targetValue: _rule.targetValue.round(),
            periodType: _rule.periodType,
            weekdaysMask: _rule.weekdaysMask,
            unit: _rule.unit,
          ),
        ],
        if (isReadingAdaptation) ...[
          const SizedBox(height: 12),
          HabitReadingGuide(
            targetMinutes: (_rule.targetValue / 60).round(),
            defaultFocusMinutes: _goal.defaultFocusMinutes,
            periodType: _rule.periodType,
            weekdaysMask: _rule.weekdaysMask,
          ),
        ],
        if (isLearningAdaptation) ...[
          const SizedBox(height: 12),
          HabitLearningGuide(
            targetMinutes: (_rule.targetValue / 60).round(),
            defaultFocusMinutes: _goal.defaultFocusMinutes,
            periodType: _rule.periodType,
            weekdaysMask: _rule.weekdaysMask,
          ),
        ],
        if (isVocabularyAdaptation) ...[
          const SizedBox(height: 12),
          HabitVocabularyGuide(
            targetValue: _rule.targetValue.round(),
            periodType: _rule.periodType,
            weekdaysMask: _rule.weekdaysMask,
            unit: _rule.unit,
          ),
        ],
        if (isMeditationAdaptation) ...[
          const SizedBox(height: 12),
          HabitMeditationGuide(
            targetMinutes: (_rule.targetValue / 60).round(),
            periodType: _rule.periodType,
            weekdaysMask: _rule.weekdaysMask,
          ),
        ],
        if (isQuitSugaryDrinksAdaptation) ...[
          const SizedBox(height: 12),
          _buildDrinkStatsCard(colorScheme),
        ],
        if (isSleepDurationAdaptation) ...[
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '数据来源：配对“早睡”和“早起”打卡节点自动计算。自动记录可在历史页编辑，编辑后将保留你的手动修正。',
              style: TextStyle(
                fontSize: 12.5,
                height: 1.45,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ],
    );
  }

  String _recordMainText(HabitCheckIn checkIn) {
    if (checkIn.source == HabitCheckInSource.freeze) {
      return '🛡️ 免扣卡守护';
    }
    if (checkIn.source == HabitCheckInSource.skip) {
      return '已跳过';
    }
    if (_goal.sourceType == HabitSourceType.timeCheckIn) {
      return '打卡 ${HabitText.timeOfDay(DateTime.fromMillisecondsSinceEpoch(checkIn.occurredAt).toLocal())}';
    }
    final value = checkIn.value;
    if (_goal.sourceType == HabitSourceType.durationCheckIn) {
      final label =
          HabitAdaptationService.forHabit(_goal)?.kind ==
              HabitAdaptationKind.sleepDuration
          ? '睡眠'
          : '时长';
      return '$label ${HabitText.formatDuration(value.round())}';
    }
    final text = value == value.roundToDouble()
        ? value.round().toString()
        : value.toString();
    final unit = _rule.unit;
    return '记录 $text${unit.isNotEmpty ? ' $unit' : ''}';
  }

  // ── 目标信息 ────────────────────────────────────────
  Widget _buildRuleSection(ColorScheme colorScheme) {
    final rule = _rule;
    final items = <(String, String)>[
      ('周期', HabitText.periodLabel(rule)),
      ('类型', HabitText.sourceTypeLabel(_goal.sourceType)),
    ];
    switch (_goal.sourceType) {
      case HabitSourceType.recurringTodo:
        items.add(('目标', '完成 1 次 / 周期'));
        break;
      case HabitSourceType.pomodoroTag:
        items.add(('目标', '${(rule.targetValue / 60).round()} 分钟 / 周期'));
      case HabitSourceType.durationCheckIn:
        items.add((
          '目标',
          '${(rule.targetValue / 3600).toStringAsFixed(1)} 小时 / 晚',
        ));
      case HabitSourceType.quantityCheckIn:
        final target = rule.targetValue;
        final text = target == target.roundToDouble()
            ? target.round().toString()
            : target.toString();
        items.add(('目标', '$text ${rule.unit}'));
        if (rule.quickValues.isNotEmpty) {
          items.add(('快捷', rule.quickValues.join('、')));
        }
      case HabitSourceType.timeCheckIn:
        items.add(('目标', HabitText.targetTime(rule.targetTimeMinute)));
        items.add((
          '条件',
          '${rule.timeComparison == HabitTimeComparison.before ? '早于' : '晚于'} '
              '${HabitText.targetTime(rule.targetTimeMinute)}'
              '${rule.timeToleranceMinutes > 0 ? '（±${rule.timeToleranceMinutes} 分钟）' : ''}',
        ));
        if (rule.dayBoundaryMinute > 0) {
          items.add((
            '日期分界',
            HabitText.dayBoundaryLabel(rule.dayBoundaryMinute),
          ));
        }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '目标信息',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              for (final (label, value) in items)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 7),
                  child: Row(
                    children: [
                      Text(
                        label,
                        style: TextStyle(
                          fontSize: 13,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        value,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: colorScheme.onSurface,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  // ── 统计 ────────────────────────────────────────────
  Widget _buildDurationSummarySection(ColorScheme colorScheme) {
    final summary = _summary!;
    final unit = _periodUnit();
    final isSleepDuration =
        HabitAdaptationService.forHabit(_goal)?.kind ==
        HabitAdaptationKind.sleepDuration;
    final averageDuration = summary.averageDuration == null
        ? '—'
        : HabitText.formatDuration(summary.averageDuration!.round());

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '时长统计（近 30 周期）',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: _statCell(
                      isSleepDuration ? '平均睡眠' : '平均时长/$unit',
                      averageDuration,
                    ),
                  ),
                  Expanded(
                    child: _statCell('当前连续', '${summary.currentStreak} $unit'),
                  ),
                  Expanded(
                    child: _statCell('最长连续', '${summary.longestStreak} $unit'),
                  ),
                  Expanded(child: _statCell('完成率 7', _percent(summary.rate7))),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _statCell('完成率 30', _percent(summary.rate30)),
                  ),
                  Expanded(
                    child: _statCell(
                      '已完成',
                      '${summary.completedCount}/${summary.plannedCount}',
                    ),
                  ),
                  Expanded(child: _statCell('未达标', '${summary.overdueCount}')),
                  Expanded(
                    child: _statCell(
                      '目标',
                      isSleepDuration
                          ? HabitText.formatDuration(_rule.targetValue.round())
                          : '${(_rule.targetValue / 60).round()} 分钟',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 8,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: summary.rate30.clamp(0.0, 1.0),
                    backgroundColor: colorScheme.surfaceContainerHighest,
                    valueColor: AlwaysStoppedAnimation(colorScheme.tertiary),
                  ),
                ),
              ),
              if (summary.weakestWeekday != null) ...[
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '最容易中断：${_weekdayLabel(summary.weakestWeekday!)}',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSummarySection(ColorScheme colorScheme) {
    final summary = _summary!;
    final unit = _periodUnit();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '近 30 周期统计',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: _statCell('最长连续', '${summary.longestStreak} $unit'),
                  ),
                  Expanded(child: _statCell('完成率 7', _percent(summary.rate7))),
                  Expanded(
                    child: _statCell('完成率 30', _percent(summary.rate30)),
                  ),
                  Expanded(
                    child: _statCell(
                      '计划',
                      '${summary.completedCount}/${summary.plannedCount}',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              SizedBox(
                height: 8,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: summary.rate30.clamp(0.0, 1.0),
                    backgroundColor: colorScheme.surfaceContainerHighest,
                    valueColor: AlwaysStoppedAnimation(colorScheme.tertiary),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _statCell(String label, String value) {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            color: colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(fontSize: 10.5, color: colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }

  String _periodUnit() {
    switch (_rule.periodType) {
      case HabitPeriodType.weekly:
        return '周';
      case HabitPeriodType.monthly:
        return '月';
      default:
        return '天';
    }
  }

  String _percent(double value) => '${(value * 100).round()}%';
}
