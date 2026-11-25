part of '../habit_detail_screen.dart';

extension _HabitDetailInsightsAndHeader on _HabitDetailScreenState {
  Widget _buildTimeLogImportSection(ColorScheme colorScheme) {
    final preview = _timeLogImportPreview!;
    final isBedtime = _timeLogImportPart == HabitTimeLogImportPart.bedtime;
    final habitLabel = isBedtime ? '早睡' : '早起';
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 10, 14),
      decoration: BoxDecoration(
        color: colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: colorScheme.secondary,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.history_rounded, color: colorScheme.onSecondary),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '发现历史睡眠日志',
                  style: TextStyle(
                    color: colorScheme.onSecondaryContainer,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '有 ${preview.pendingLogs.length} 条记录可以导入到这个$habitLabel习惯的历史打卡中。',
                  style: TextStyle(
                    color: colorScheme.onSecondaryContainer.withValues(
                      alpha: 0.78,
                    ),
                    fontSize: 12.5,
                  ),
                ),
                if (preview.alreadyImportedCount > 0) ...[
                  const SizedBox(height: 3),
                  Text(
                    '已导入 ${preview.alreadyImportedCount} 条，重复导入不会新增记录。',
                    style: TextStyle(
                      color: colorScheme.onSecondaryContainer.withValues(
                        alpha: 0.68,
                      ),
                      fontSize: 11.5,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 4),
          TextButton(onPressed: _openTimeLogImport, child: const Text('导入')),
        ],
      ),
    );
  }

  // ── 时间点型：打卡趋势、实际时间与统计 ─────────────────
  Widget _buildTimePointSection(ColorScheme colorScheme) {
    final visibleTrend = _timeTrend.length <= _timeTrendRangeDays
        ? _timeTrend
        : _timeTrend.sublist(_timeTrend.length - _timeTrendRangeDays);
    final recordedDays = visibleTrend
        .where((day) => day.progress.firstRecordAt != null)
        .toList(growable: false);
    final recentRecordedDays = recordedDays.reversed.take(7);
    final summary = _summary;
    final chartData = visibleTrend
        .map((day) {
          final rule =
              HabitRuleResolver.effectiveRule(_rules, day.logicalDate) ?? _rule;
          return HabitTimePointChartData(
            date: day.logicalDate,
            actualTime: day.progress.firstRecordAt,
            onTime: day.progress.goalMet,
            targetTimeMinute: rule.targetTimeMinute,
            dayBoundaryMinute: rule.dayBoundaryMinute > 0
                ? rule.dayBoundaryMinute
                : HabitRuleResolver.defaultDayBoundaryMinute,
          );
        })
        .toList(growable: false);
    final hasTargetTime = chartData.any(
      (point) => point.targetTimeMinute != null,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '近 $_timeTrendRangeDays 天打卡趋势',
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
        const SizedBox(height: 4),
        Align(
          alignment: Alignment.centerRight,
          child: SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 7, label: Text('7 天')),
              ButtonSegment(value: 30, label: Text('30 天')),
            ],
            selected: {_timeTrendRangeDays},
            showSelectedIcon: false,
            style: SegmentedButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              textStyle: const TextStyle(fontSize: 12),
            ),
            onSelectionChanged: (selection) {
              if (selection.isNotEmpty) {
                _mutateState(() => _timeTrendRangeDays = selection.first);
              }
            },
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_timeTrend.isEmpty)
                Text(
                  '暂无可展示的趋势数据',
                  style: TextStyle(
                    fontSize: 13,
                    color: colorScheme.onSurfaceVariant,
                  ),
                )
              else ...[
                HabitTimePointChart(
                  data: chartData,
                  rangeDays: _timeTrendRangeDays,
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 12,
                  runSpacing: 4,
                  children: [
                    _trendLegend(colorScheme.tertiary, '达标', colorScheme),
                    _trendLegend(colorScheme.error, '未达标', colorScheme),
                    _trendLegend(
                      colorScheme.surfaceContainerHighest,
                      '未打卡',
                      colorScheme,
                    ),
                    if (hasTargetTime)
                      _trendLegend(
                        colorScheme.primary,
                        '目标时间',
                        colorScheme,
                        dashed: true,
                      ),
                  ],
                ),
              ],
              if (recordedDays.isNotEmpty) ...[
                const SizedBox(height: 12),
                Divider(color: colorScheme.outlineVariant),
                const SizedBox(height: 4),
                Text(
                  '最近打卡时间',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 4),
                ...recentRecordedDays.map(
                  (day) => _buildTimeTrendDayRow(day, colorScheme),
                ),
              ],
            ],
          ),
        ),
        if (summary != null) ...[
          const SizedBox(height: 10),
          _buildTimePointStats(summary, colorScheme),
        ],
      ],
    );
  }

  Widget _trendLegend(
    Color color,
    String label,
    ColorScheme colorScheme, {
    bool dashed = false,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 12,
          height: 8,
          child: CustomPaint(
            painter: _TrendLegendPainter(color: color, dashed: dashed),
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }

  Widget _buildTimeTrendDayRow(HabitDayProgress day, ColorScheme colorScheme) {
    final actual = day.progress.firstRecordAt!;
    final rule =
        HabitRuleResolver.effectiveRule(_rules, day.logicalDate) ?? _rule;
    final statusColor = day.progress.goalMet
        ? colorScheme.tertiary
        : colorScheme.error;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          SizedBox(
            width: 48,
            child: Text(
              _shortDate(day.logicalDate),
              style: TextStyle(
                fontSize: 12,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Icon(Icons.schedule_rounded, size: 16, color: statusColor),
          const SizedBox(width: 6),
          Text(
            HabitText.timeOfDay(actual),
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: colorScheme.onSurface,
            ),
          ),
          const Spacer(),
          Text(
            HabitText.timePointStatus(rule, day.progress),
            style: TextStyle(fontSize: 11.5, color: statusColor),
          ),
        ],
      ),
    );
  }

  Widget _buildTimePointStats(
    HabitStreakSummary summary,
    ColorScheme colorScheme,
  ) {
    final averageTime = summary.averageTimeMinute == null
        ? '—'
        : HabitText.targetTime(summary.averageTimeMinute!.round());
    final onTimeRate = summary.onTimeRate == null
        ? '—'
        : _percent(summary.onTimeRate!);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '时间点统计',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _statCell('平均时间', averageTime)),
              Expanded(child: _statCell('准时率', onTimeRate)),
              Expanded(child: _statCell('当前连续', '${summary.currentStreak} 天')),
              Expanded(child: _statCell('最长连续', '${summary.longestStreak} 天')),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _statCell('完成率 7', _percent(summary.rate7))),
              Expanded(child: _statCell('完成率 30', _percent(summary.rate30))),
              Expanded(
                child: _statCell(
                  '已完成',
                  '${summary.completedCount}/${summary.plannedCount}',
                ),
              ),
              Expanded(child: _statCell('未达标', '${summary.overdueCount}')),
            ],
          ),
          if (summary.weakestWeekday != null) ...[
            const SizedBox(height: 10),
            Text(
              '最容易中断：${_weekdayLabel(summary.weakestWeekday!)}',
              style: TextStyle(
                fontSize: 11.5,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _shortDate(DateTime date) => '${date.month}/${date.day}';

  String _weekdayLabel(int weekday) {
    return weekday >= 0 && weekday < AppTimeFormats.weekdayLabelsZh.length
        ? AppTimeFormats.weekdayLabelsZh[weekday]
        : '—';
  }

  // ── 头部：图标 + 连续 ────────────────────────────────
  Widget _buildHeader(ColorScheme colorScheme) {
    return Row(
      children: [
        Container(
          width: 56,
          height: 56,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Text(
            _goal.icon.isNotEmpty ? _goal.icon : '🎯',
            style: const TextStyle(fontSize: 30),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _goal.name,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                HabitText.periodLabel(_rule),
                style: TextStyle(
                  fontSize: 13,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        if (_summary != null && _summary!.currentStreak > 0) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: colorScheme.tertiaryContainer,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.local_fire_department_rounded,
                  size: 16,
                  color: colorScheme.tertiary,
                ),
                const SizedBox(width: 4),
                Text(
                  '连续 ${_summary!.currentStreak}',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    color: colorScheme.onTertiaryContainer,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
        ],
        _buildFreezeCardBadge(colorScheme),
      ],
    );
  }

  Widget _buildFreezeCardBadge(ColorScheme colorScheme) {
    return InkWell(
      onTap: () => _showStreakFreezeInfoSheet(colorScheme),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: colorScheme.secondaryContainer.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: colorScheme.secondary.withValues(alpha: 0.3),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.shield_outlined, size: 15, color: colorScheme.secondary),
            const SizedBox(width: 4),
            Text(
              '免扣卡 $_freezeBalance/2',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: colorScheme.secondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showStreakFreezeInfoSheet(ColorScheme colorScheme) async {
    final curStreak = _summary?.currentStreak ?? 0;
    final isFull = _freezeBalance >= HabitFreezeService.kMaxFreezeCards;
    final needed =
        HabitFreezeService.kStreakIntervalForReward -
        (curStreak % HabitFreezeService.kStreakIntervalForReward);

    // 检查昨日是否可以补用免扣卡
    final now = DateTime.now();
    final yesterday = HabitRuleResolver.addCalendarDays(now, -1);
    final effectiveRule =
        HabitRuleResolver.effectiveRule(_rules, yesterday) ?? _rule;
    final allCheckIns = await HabitRepository.getCheckIns(
      habitUuid: _goal.uuid,
    );
    final validation = await HabitFreezeService.canApplyFreeze(
      goal: _goal,
      rule: effectiveRule,
      logicalDate: yesterday,
      checkIns: allCheckIns,
      rules: _rules,
    );
    final canRemedyYesterday = validation.canApply;

    if (!mounted) return;

    await AppDialogs.showAppBottomSheet(
      context: context,
      builder: (sheetContext) {
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: colorScheme.secondaryContainer.withValues(
                        alpha: 0.7,
                      ),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.shield_rounded,
                      color: colorScheme.secondary,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '习惯免扣卡守护',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: colorScheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '包容生活的意外，守护每一份坚持',
                          style: TextStyle(
                            fontSize: 12.5,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              // 当前库存卡片
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: colorScheme.secondaryContainer.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: colorScheme.secondary.withValues(alpha: 0.2),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '当前可用免扣卡',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: colorScheme.secondary,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            '$_freezeBalance / ${HabitFreezeService.kMaxFreezeCards} 张',
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w800,
                              color: colorScheme.onSecondary,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    HabitEmojiText(
                      isFull
                          ? '🌟 免扣卡已达存放上限（2 张），继续保持连胜状态吧！'
                          : '🌱 当前连续 $curStreak 天，还需连续达标 $needed 天可获得下 1 张免扣卡',
                      style: TextStyle(
                        fontSize: 12,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              Text(
                '守护制度规则',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 10),
              _freezeRuleItem(
                icon: Icons.calendar_month_outlined,
                color: colorScheme.primary,
                title: '连续 7 天奖励 1 张',
                desc: '坚持满完整一周，自动获得 1 张免扣卡奖励（单个习惯最多存储 2 张）。',
                colorScheme: colorScheme,
              ),
              _freezeRuleItem(
                icon: Icons.card_giftcard_rounded,
                color: colorScheme.tertiary,
                title: '新手启航礼遇',
                desc: '每个习惯启程初始赠送 1 张保底免扣卡，保护起步阶段不轻易受挫。',
                colorScheme: colorScheme,
              ),
              _freezeRuleItem(
                icon: Icons.shield_outlined,
                color: colorScheme.secondary,
                title: '意外漏打卡智能守护',
                desc: '生病、突发加班未打卡时，免扣卡守护连胜不中断，在日历与统计中点亮蓝冰盾牌。',
                colorScheme: colorScheme,
              ),
              _freezeRuleItem(
                icon: Icons.repeat_one_outlined,
                color: colorScheme.error,
                title: '绝不连续错过两次',
                desc: '遵循习惯心理学法则，免扣卡不可连续两天使用，守护真实的习惯养成。',
                colorScheme: colorScheme,
              ),
              const SizedBox(height: 20),
              if (canRemedyYesterday) ...[
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () async {
                      Navigator.pop(sheetContext);
                      final applied = await HabitFreezeService.applyFreeze(
                        goal: _goal,
                        rule: effectiveRule,
                        logicalDate: yesterday,
                        note: '🛡️ 手动补用免扣卡',
                        rules: _rules,
                      );
                      if (applied && mounted) {
                        AppSnackBars.showSnackBar(
                          context,
                          const SnackBar(
                            content: Text('🛡️ 已为昨天使用免扣卡，连胜记录已成功守护！'),
                          ),
                        );
                        _loadData();
                      }
                    },
                    icon: const Icon(Icons.shield_rounded, size: 18),
                    label: const Text('为昨日使用免扣卡'),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
              ],
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(sheetContext),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: const Text('我知道啦'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _freezeRuleItem({
    required IconData icon,
    required Color color,
    required String title,
    required String desc,
    required ColorScheme colorScheme,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 16, color: color),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  desc,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: colorScheme.onSurfaceVariant,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TrendLegendPainter extends CustomPainter {
  final Color color;
  final bool dashed;

  static final Paint _paint = Paint()
    ..strokeWidth = 2
    ..strokeCap = StrokeCap.round;

  const _TrendLegendPainter({required this.color, required this.dashed});

  @override
  void paint(Canvas canvas, Size size) {
    _paint
      ..color = color
      ..style = dashed ? PaintingStyle.stroke : PaintingStyle.fill;
    if (dashed) {
      canvas.drawLine(
        Offset.zero.translate(0, size.height / 2),
        Offset(size.width, size.height / 2),
        _paint,
      );
    } else {
      canvas.drawRRect(
        RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(2)),
        _paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _TrendLegendPainter oldDelegate) {
    return oldDelegate.color != color || oldDelegate.dashed != dashed;
  }
}
