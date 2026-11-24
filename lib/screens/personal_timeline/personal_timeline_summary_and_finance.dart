part of '../personal_timeline_screen.dart';

extension _PersonalTimelineSummaryFinanceExt on _PersonalTimelineScreenState {
  String _formatPercent(double value) {
    if (value.isNaN || value.isInfinite) return '0%';
    return '${(value.clamp(0.0, 1.0) * 100).round()}%';
  }

  int _subjectRatio(TimelineSummary summary, String subject) {
    if (!summary.subjectDistribution.containsKey(subject)) return 0;
    final total = summary.subjectDistribution.values.fold(0.0, (a, b) => a + b);
    if (total <= 0) return 0;
    return ((summary.subjectDistribution[subject]! / total) * 100).round();
  }

  String _buildKeywordText(TimelineSummary summary) {
    final words = <String>[
      ...summary.subjectDistribution.entries
          .where((e) => e.key != '其他')
          .map((e) => e.key),
      if (summary.examPrepCount > 0) '备考',
      if (summary.deepWorkCount > 0) '深度专注',
      if (_deadlineSprintCount > 0) 'DDL',
    ];
    if (words.isEmpty) return '专注、计划';
    const maxChars = 14;
    final buffer = StringBuffer();
    for (final word in words) {
      final next = buffer.isEmpty ? word : '、$word';
      if (buffer.length + next.length > maxChars) {
        if (buffer.isEmpty) {
          return '${word.substring(0, maxChars - 1)}…';
        }
        return '${buffer.toString()}…';
      }
      buffer.write(next);
    }
    return buffer.toString();
  }

  String _getTaskCompositionReason() {
    final homework = (_summary?.homeworkRatio ?? 0) * 100;
    final exam = (_summary?.examRatio ?? 0) * 100;
    if (homework > 40) return '作业类占比 ${homework.round()}%，高于 40%';
    if (exam > 20) return '备考类占比 ${exam.round()}%，高于 20%';
    return '作业和备考都未单独占主导';
  }

  Widget _buildSectionTitle(String title, IconData icon, ColorScheme cs) {
    return Row(
      children: [
        Icon(icon, size: 20, color: cs.onSurfaceVariant.withValues(alpha: 0.6)),
        const SizedBox(width: 8),
        Text(
          title,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: cs.onSurface,
            letterSpacing: 0.5,
          ),
        ),
      ],
    );
  }

  Widget _buildTimelineFlow(ColorScheme cs) {
    if (_events.isEmpty) return _buildEmptyState(cs);
    return Column(
      children: _events.map((e) => _buildJournalEntry(e, cs)).toList(),
    );
  }

  Widget _buildEmptyState(ColorScheme cs) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 40),
        child: Text(
          '这段时间静悄悄的，\n休息也是为了更好地出发。',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: cs.onSurfaceVariant.withValues(alpha: 0.4),
            fontStyle: FontStyle.italic,
          ),
        ),
      ),
    );
  }

  Widget _buildJournalEntry(TimelineEvent event, ColorScheme cs) {
    final timeStr = _timelineDateFormat('HH:mm').format(event.timestamp);
    final isImportant =
        event.type == TimelineEventType.pomodoroEnd ||
        event.type == TimelineEventType.todoCompleted ||
        event.type == TimelineEventType.timeLog ||
        event.type == TimelineEventType.planBlock ||
        event.type == TimelineEventType.habitCheckIn ||
        event.type == TimelineEventType.financeTransaction;
    String? financeTransactionId;
    if (event.type == TimelineEventType.financeTransaction) {
      financeTransactionId = event.extraData?['transaction_uuid']?.toString();
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 24.0),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: financeTransactionId == null
            ? null
            : () => _openFinanceEvent(financeTransactionId!),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                timeStr,
                style: TextStyle(
                  fontSize: 12,
                  fontFamily: 'monospace',
                  color: cs.onSurfaceVariant.withValues(alpha: 0.5),
                ),
              ),
              const SizedBox(width: 20),
              if (event.type == TimelineEventType.financeTransaction) ...[
                Icon(
                  Icons.account_balance_wallet_outlined,
                  size: 16,
                  color: cs.tertiary,
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _formatEventTitle(event),
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: isImportant
                            ? FontWeight.w600
                            : FontWeight.normal,
                        color: cs.onSurface,
                      ),
                    ),
                    if (event.subtitle != null)
                      Text(
                        event.subtitle!,
                        style: TextStyle(
                          fontSize: 13,
                          color: cs.onSurfaceVariant.withValues(alpha: 0.7),
                        ),
                      ),
                  ],
                ),
              ),
              if (financeTransactionId != null) ...[
                const SizedBox(width: 8),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 18,
                  color: cs.onSurfaceVariant.withValues(alpha: 0.45),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRangeSummary(ColorScheme cs, bool isWide) {
    if (_summary == null) return _buildEmptyState(cs);
    final summary = _summary!;

    final List<Widget> cards = [
      _buildTrendCard(
        '有效投入',
        _formatMinutes(_totalFocusMinutes),
        '$_pomodoroCount 次番茄 · $_timeLogCount 条时间日志',
        Icons.timer_rounded,
        cs.primary,
        cs,
        trend: _summary!.dailyTrend,
        extraItems: [
          const SizedBox(height: 8),
          _buildRankItem(
            0,
            '番茄专注',
            _formatSecondsCompact(_pomodoroFocusSeconds),
            cs,
          ),
          _buildRankItem(0, '手动日志', _formatSecondsCompact(_timeLogSeconds), cs),
          if (_pauseCount > 0)
            _buildRankItem(
              0,
              '暂停损耗',
              '$_pauseCount次 · ${_formatSecondsCompact(_pauseSeconds)}',
              cs,
            ),
        ],
      ),
      _buildStatCard(
        '最长单段投入',
        '${_summary!.longestPomodoroMinutes} 分钟',
        _summary!.longestPomodoroTitle != null
            ? '投入「${_summary!.longestPomodoroTitle}」'
            : '挑战自我极限',
        Icons.workspace_premium_rounded,
        Colors.amber,
        cs,
        extraItems: _summary!.topFocusSessions.length > 1
            ? _summary!.topFocusSessions
                  .skip(1)
                  .take(4)
                  .toList()
                  .asMap()
                  .entries
                  .map((e) {
                    final session = e.value;
                    final dur = (session['actual_duration'] as num? ?? 0)
                        .toInt();
                    return _buildRankItem(
                      e.key + 2,
                      session['todo_title'] as String? ?? '无题',
                      '${dur ~/ 60}m',
                      cs,
                    );
                  })
                  .toList()
            : null,
      ),
      _buildStatCard(
        '专注质量',
        '中断率 ${(_summary!.interruptionRate * 100).toStringAsFixed(1)}%',
        '${_summary!.interruptionCount} 次提前放弃',
        Icons.shield_moon_rounded,
        Colors.indigo,
        cs,
        extraItems: [
          const SizedBox(height: 8),
          _buildRankItem(0, '深度心流', '${_summary!.deepWorkCount}次', cs),
          _buildRankItem(
            0,
            '平均时长',
            '${_summary!.avgPomodoroMinutes.toStringAsFixed(0)}m',
            cs,
          ),
          _buildRankItem(0, '暂停次数', '$_pauseCount次', cs),
        ],
      ),
      _buildStatCard(
        '任务执行力',
        '完成率 ${_formatPercent(_totalCount > 0 ? _completedCount / _totalCount : 0)}',
        '计划 $_totalCount 项，完成 $_completedCount 项',
        Icons.done_all_rounded,
        Colors.green,
        cs,
        extraItems: [
          const SizedBox(height: 8),
          _buildRankItem(0, '提前完成', '$_earlyCompletionCount项', cs),
          _buildRankItem(0, '截止前24小时完成', '$_deadlineSprintCount项', cs),
        ],
      ),
      if (_recurringScheduledCount > 0)
        _buildStatCard(
          '重复待办',
          _recurringResolvedCount > 0
              ? '完成率 ${_formatPercent(_recurringCompletedCount / _recurringResolvedCount)}'
              : '重复计划进行中',
          '${_recurrenceSeries.length} 个系列 · $_recurringScheduledCount 个周期实例',
          Icons.repeat_rounded,
          cs.secondary,
          cs,
          extraItems: [
            const SizedBox(height: 8),
            _buildRankItem(0, '按期完成', '$_recurringCompletedCount期', cs),
            _buildRankItem(0, '已逾期', '$_recurringMissedCount期', cs),
            if (_recurringSkippedCount > 0)
              _buildRankItem(0, '已跳过', '$_recurringSkippedCount期', cs),
            if (_recurringPendingCount > 0)
              _buildRankItem(0, '进行中', '$_recurringPendingCount期', cs),
            _buildRankItem(0, '阶段末连续完成', '$_recurringEndingStreak期', cs),
            _buildRankItem(0, '最长连续完成', '$_recurringLongestStreak期', cs),
            if (_bestRecurrenceSeries != null) ...[
              const SizedBox(height: 8),
              _buildRankItem(
                1,
                '最稳定 · ${_bestRecurrenceSeries!.title}',
                '${_bestRecurrenceSeries!.completedCount}/${_bestRecurrenceSeries!.resolvedCount}期',
                cs,
              ),
            ],
            ..._recurrenceSeries
                .where(
                  (series) =>
                      series.seriesId != _bestRecurrenceSeries?.seriesId,
                )
                .take(2)
                .toList()
                .asMap()
                .entries
                .map((entry) {
                  final series = entry.value;
                  return _buildRankItem(
                    entry.key + 2,
                    series.title,
                    '${series.completedCount}/${series.resolvedCount}期',
                    cs,
                  );
                }),
          ],
        ),
      if (summary.habitSummary.habitCount > 0)
        _buildStatCard(
          '习惯坚持',
          '${summary.habitSummary.completedCount}/${summary.habitSummary.plannedCount}',
          '${summary.habitSummary.habitCount} 个习惯 · 打卡 ${summary.habitSummary.recordedCount} 次',
          Icons.self_improvement_outlined,
          cs.tertiary,
          cs,
          extraItems: [
            const SizedBox(height: 8),
            _buildRankItem(
              0,
              '完成率',
              _formatPercent(summary.habitSummary.completionRate),
              cs,
            ),
            _buildRankItem(
              0,
              '未达标',
              '${summary.habitSummary.missedCount} 个周期',
              cs,
            ),
          ],
        ),
      if (_planBlockCount > 0)
        _buildStatCard(
          '规划达成',
          _formatPercent(
            _plannedMinutes > 0
                ? _planActualSeconds / (_plannedMinutes * 60)
                : 0,
          ),
          '计划 ${_formatMinutes(_plannedMinutes)} · 实际 ${_formatSecondsCompact(_planActualSeconds)}',
          Icons.event_available_outlined,
          cs.tertiary,
          cs,
          extraItems: [
            const SizedBox(height: 8),
            _buildRankItem(
              0,
              '达成规划块',
              '$_planCompletedCount/$_planBlockCount',
              cs,
            ),
            _buildRankItem(0, '漏做', '$_planMissedCount个', cs),
            _buildRankItem(0, '跳过/取消', '$_planSkippedCount个', cs),
          ],
        ),
      if (_topFocusTags.isNotEmpty)
        _buildStatCard(
          '专注标签',
          _topFocusTags.first.key,
          '跨番茄与时间日志聚合',
          Icons.sell_outlined,
          cs.secondary,
          cs,
          extraItems: _topFocusTags.asMap().entries.map((entry) {
            final tag = entry.value;
            return _buildRankItem(
              entry.key + 1,
              tag.key,
              _formatSecondsCompact(tag.value),
              cs,
            );
          }).toList(),
        ),
      _buildStatCard(
        '屏幕时间转化',
        _formatPercent(
          _screenTimeSeconds > 0
              ? (_totalFocusMinutes * 60) / _screenTimeSeconds
              : 0,
        ),
        '屏幕使用 ${_formatSecondsCompact(_screenTimeSeconds)}，专注 ${_formatMinutes(_totalFocusMinutes)}',
        Icons.monitor_heart_outlined,
        Colors.teal,
        cs,
        extraItems: [
          const SizedBox(height: 8),
          _buildRankItem(
            0,
            '生产力应用',
            _formatPercent(
              _screenTimeSeconds > 0
                  ? _productiveScreenSeconds / _screenTimeSeconds
                  : 0,
            ),
            cs,
          ),
          _buildRankItem(
            0,
            '分心应用',
            _formatSecondsCompact(_distractionScreenSeconds),
            cs,
          ),
          ..._topScreenApps.take(3).toList().asMap().entries.map((e) {
            final app = e.value;
            return _buildRankItem(
              e.key + 1,
              app.key,
              _formatSecondsCompact(app.value),
              cs,
            );
          }),
        ],
      ),
      _buildTrendCard(
        '深度工作',
        '${_summary!.deepWorkCount} 次',
        '单次专注达到 60 分钟',
        Icons.bolt_rounded,
        Colors.amber,
        cs,
        extraItems: [
          const SizedBox(height: 8),
          _buildMiniBarChart(
            _summary!.hourlyDistribution.map((v) => v.toDouble()).toList(),
            cs.primary,
            cs,
          ),
        ],
      ),
      if (_courseCount > 0)
        _buildStatCard(
          '课程节律',
          '$_courseCount 节课',
          _maxDailyCourseCount > 0 ? '最满一天 $_maxDailyCourseCount 节课' : '课表联动统计',
          Icons.school_outlined,
          Colors.deepPurple,
          cs,
          extraItems: [
            const SizedBox(height: 8),
            _buildRankItem(0, '课后任务完成', '${_summary!.todoCompletedCount}项', cs),
            _buildRankItem(0, '备考任务信号', '${_summary!.examPrepCount}次', cs),
          ],
        ),
      if (_summary!.examPrepCount > 0)
        _buildStatCard(
          '备考冲刺波',
          '${_summary!.examPrepCount} 次备考',
          '检测到高强度考试准备',
          Icons.auto_graph_rounded,
          Colors.redAccent,
          cs,
          extraItems: [
            const SizedBox(height: 8),
            ..._summary!.examSubjectDist.entries.take(5).map((e) {
              final maxVal = _summary!.examSubjectDist.values.isNotEmpty
                  ? _summary!.examSubjectDist.values.reduce(math.max).toDouble()
                  : 1.0;
              return Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          e.key,
                          style: TextStyle(
                            fontSize: 10,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                        Text(
                          '${e.value}次',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: cs.onSurface,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: LinearProgressIndicator(
                        value: maxVal > 0 ? e.value / maxVal : 0,
                        backgroundColor: Colors.redAccent.withValues(
                          alpha: 0.1,
                        ),
                        color: Colors.redAccent,
                        minHeight: 4,
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      _buildStatCard(
        '知识探索',
        '${_summary!.searchCount} 次检索',
        _summary!.topSearchQuery != null
            ? '最常搜索: ${_summary!.topSearchQuery}'
            : '探索未知的边界',
        Icons.travel_explore_rounded,
        Colors.teal,
        cs,
        extraItems: _summary!.topSearchQueries
            .take(5)
            .toList()
            .asMap()
            .entries
            .map((e) {
              final q = e.value;
              return _buildRankItem(
                e.key + 1,
                q['query'] as String? ?? '',
                '${q['freq']}x',
                cs,
              );
            })
            .toList(),
      ),
      _buildStatCard(
        '任务构成',
        _summary!.homeworkRatio > 0.4
            ? '作业攻坚型'
            : (_summary!.examRatio > 0.2 ? '备考冲刺型' : '全面均衡型'),
        _getTaskCompositionReason(),
        Icons.donut_large_rounded,
        Colors.blueGrey,
        cs,
        extraItems: [
          const SizedBox(height: 12),
          Row(
            children: [
              SizedBox(
                height: 48,
                width: 48,
                child: RepaintBoundary(
                  child: CustomPaint(
                    painter: _DonutPainter(
                      [
                        MapEntry('HW', _summary!.homeworkRatio),
                        MapEntry('EX', _summary!.examRatio),
                        MapEntry(
                          'OT',
                          (1.0 - _summary!.homeworkRatio - _summary!.examRatio)
                              .clamp(0.0, 1.0),
                        ),
                      ],
                      [cs.primary, cs.secondary, cs.outlineVariant],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  children: [
                    _buildRankItem(
                      0,
                      '作业类',
                      _formatPercent(_summary!.homeworkRatio),
                      cs,
                    ),
                    _buildRankItem(
                      0,
                      '备考类',
                      _formatPercent(_summary!.examRatio),
                      cs,
                    ),
                    _buildRankItem(
                      0,
                      '其他主题',
                      _formatPercent(
                        (1.0 - _summary!.homeworkRatio - _summary!.examRatio)
                            .clamp(0.0, 1.0),
                      ),
                      cs,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    ];

    final int colCount = isWide
        ? (MediaQuery.sizeOf(context).width > 1200 ? 4 : 3)
        : 2;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildFinanceSummaryCard(cs),
        const SizedBox(height: 12),
        _buildBalancedCardRows(cards, colCount),
      ],
    );
  }

  Widget _buildFinanceSummaryCard(ColorScheme cs) {
    final summary = _financeSummary;
    final metrics = _financeCardMetrics;
    final categoryMap = metrics.categoryByUuid;
    final topCategories = metrics.topCategories;
    final maxCategory = metrics.maxCategory;
    final averagePerDay = metrics.spendingDays == 0
        ? 0
        : summary.netExpenseMinor ~/ metrics.spendingDays;
    final outflowTransactionCount = metrics.expenseCount + metrics.refundCount;
    final averagePerTransaction = outflowTransactionCount == 0
        ? 0
        : summary.netExpenseMinor ~/ outflowTransactionCount;
    final hasTransactions = summary.transactionCount > 0;
    final financeAccent = summary.netExpenseMinor > 0 ? cs.error : cs.primary;
    final peakDay = metrics.peakDay;
    final expenseCount = metrics.expenseCount;
    final incomeCount = metrics.incomeCount;
    final refundCount = metrics.refundCount;

    String categoryLabel(String uuid) {
      final category = categoryMap[uuid];
      return category == null ? '未分类' : '${category.icon} ${category.name}';
    }

    return OptionalLiquidGlassCard(
      padding: const EdgeInsets.all(18),
      borderRadius: 26,
      highContrast: true,
      tint: cs.tertiary.withValues(alpha: 0.08),
      fallbackDecoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.account_balance_wallet_outlined,
                color: financeAccent,
                size: 18,
              ),
              const SizedBox(width: 8),
              Text(
                '账本统计',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: cs.onSurface,
                ),
              ),
              const Spacer(),
              if (hasTransactions)
                Text(
                  '${summary.transactionCount} 笔记录',
                  style: TextStyle(
                    fontSize: 11,
                    color: cs.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          if (!hasTransactions)
            Text(
              '这一段时间还没有账单，记下一笔生活开销后，这里会同步展示收支趋势。',
              style: TextStyle(
                fontSize: 13,
                height: 1.45,
                color: cs.onSurfaceVariant,
              ),
            )
          else ...[
            Text(
              formatFinanceAmount(summary.netExpenseMinor),
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.5,
                color: financeAccent,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              '净支出 · ${_getPeriodName()}',
              style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                _buildFinanceMetric(
                  label: '收入',
                  value: formatFinanceAmount(summary.incomeMinor),
                  color: cs.primary,
                ),
                _buildFinanceMetricDivider(cs),
                _buildFinanceMetric(
                  label: '结余',
                  value: formatFinanceAmount(summary.balanceMinor),
                  color: cs.onSurface,
                ),
                _buildFinanceMetricDivider(cs),
                _buildFinanceMetric(
                  label: '记账日均',
                  value: formatFinanceAmount(averagePerDay),
                  color: financeAccent,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Divider(
              height: 1,
              thickness: 0.6,
              color: cs.outlineVariant.withValues(alpha: 0.45),
            ),
            const SizedBox(height: 10),
            _buildRankItem(
              0,
              '收支构成',
              '支出 $expenseCount · 收入 $incomeCount · 退款 $refundCount',
              cs,
            ),
            _buildRankItem(
              0,
              '平均每笔净支出',
              formatFinanceAmount(averagePerTransaction),
              cs,
            ),
            if (peakDay != null)
              _buildRankItem(
                0,
                '最高支出日',
                '${_timelineDateFormat('MM/dd').format(dateFromKey(peakDay.key))} · '
                    '${formatFinanceAmount(peakDay.value)}',
                cs,
              ),
            if (topCategories.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                '支出分类',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: cs.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 6),
              for (final entry in topCategories.take(3))
                _buildFinanceCategoryBar(
                  label: categoryLabel(entry.key),
                  amount: entry.value,
                  maxAmount: maxCategory,
                  color: financeAccent,
                  cs: cs,
                ),
            ],
          ],
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.tonalIcon(
                onPressed: _openFinanceEntry,
                icon: const Icon(Icons.add_rounded, size: 17),
                label: const Text('记一笔'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, 38),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 9,
                  ),
                ),
              ),
              OutlinedButton.icon(
                onPressed: _openFinanceLedger,
                icon: const Icon(Icons.open_in_new_rounded, size: 16),
                label: const Text('打开账本'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 38),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 9,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  _FinanceCardMetrics _createFinanceCardMetrics({
    required FinanceSummary summary,
    required List<FinanceTransaction> transactions,
    required List<FinanceCategory> categories,
  }) {
    final categoryByUuid = <String, FinanceCategory>{
      for (final category in categories) category.uuid: category,
    };
    final topCategories =
        summary.expenseByCategory.entries
            .where((entry) => entry.value > 0)
            .toList()
          ..sort((a, b) => b.value.compareTo(a.value));

    var spendingDays = 0;
    MapEntry<String, int>? peakDay;
    for (final entry in summary.expenseByDate.entries) {
      if (entry.value <= 0) continue;
      spendingDays++;
      if (peakDay == null || entry.value > peakDay.value) peakDay = entry;
    }

    var expenseCount = 0;
    var incomeCount = 0;
    var refundCount = 0;
    for (final transaction in transactions) {
      switch (transaction.type) {
        case FinanceTransactionType.expense:
          expenseCount++;
        case FinanceTransactionType.income:
          incomeCount++;
        case FinanceTransactionType.refund:
          refundCount++;
        case FinanceTransactionType.transfer:
          break;
      }
    }

    return (
      categoryByUuid: categoryByUuid,
      topCategories: topCategories,
      maxCategory: topCategories.isEmpty ? 1 : topCategories.first.value,
      spendingDays: spendingDays,
      peakDay: peakDay,
      expenseCount: expenseCount,
      incomeCount: incomeCount,
      refundCount: refundCount,
    );
  }

  Widget _buildFinanceMetric({
    required String label,
    required String value,
    required Color color,
  }) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              color: color.withValues(alpha: 0.72),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 14,
              color: color,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFinanceMetricDivider(ColorScheme cs) {
    return Container(
      width: 1,
      height: 30,
      margin: const EdgeInsets.symmetric(horizontal: 10),
      color: cs.outlineVariant.withValues(alpha: 0.45),
    );
  }

  Widget _buildFinanceCategoryBar({
    required String label,
    required int amount,
    required int maxAmount,
    required Color color,
    required ColorScheme cs,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          SizedBox(
            width: 92,
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                minHeight: 6,
                value: maxAmount > 0 ? amount / maxAmount : 0,
                backgroundColor: cs.surfaceContainerHighest,
                color: color.withValues(alpha: 0.72),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            formatFinanceAmount(amount),
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: cs.onSurface,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBalancedCardRows(List<Widget> cards, int maxColumns) {
    if (cards.isEmpty) return const SizedBox();

    final columns = math.min(maxColumns, cards.length);
    final rowCount = (cards.length / columns).ceil();
    final baseSize = cards.length ~/ rowCount;
    final remainder = cards.length % rowCount;

    int cursor = 0;
    final rows = <List<Widget>>[];
    for (int row = 0; row < rowCount; row++) {
      final rowSize = baseSize + (row < remainder ? 1 : 0);
      rows.add(cards.sublist(cursor, cursor + rowSize));
      cursor += rowSize;
    }

    return Column(
      children: [
        for (int rowIndex = 0; rowIndex < rows.length; rowIndex++)
          Padding(
            padding: EdgeInsets.only(
              bottom: rowIndex == rows.length - 1 ? 0 : 12,
            ),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (
                    int colIndex = 0;
                    colIndex < rows[rowIndex].length;
                    colIndex++
                  )
                    Expanded(
                      child: Padding(
                        padding: EdgeInsets.only(
                          left: colIndex == 0 ? 0 : 6,
                          right: colIndex == rows[rowIndex].length - 1 ? 0 : 6,
                        ),
                        child: rows[rowIndex][colIndex],
                      ),
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildMiniBarChart(List<double> data, Color color, ColorScheme cs) {
    if (data.isEmpty) return const SizedBox();
    final max = data.reduce((a, b) => a > b ? a : b);
    if (max == 0) return const SizedBox();

    return SizedBox(
      height: 38,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: data
            .map(
              (v) => Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 0.5),
                  child: Container(
                    height: math.max(3, (v / max) * 38),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(1),
                    ),
                  ),
                ),
              ),
            )
            .toList(),
      ),
    );
  }

  Widget _buildTrendCard(
    String title,
    String content,
    String subtitle,
    IconData icon,
    Color color,
    ColorScheme cs, {
    List<double>? trend,
    List<Widget>? extraItems,
  }) {
    return OptionalLiquidGlassCard(
      padding: const EdgeInsets.all(16),
      borderRadius: 24,
      highContrast: true,
      fallbackDecoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.3)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 16),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurfaceVariant,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (trend != null && trend.length >= 2) ...[
            SizedBox(
              height: 44,
              width: double.infinity,
              child: RepaintBoundary(
                child: CustomPaint(
                  painter: _SparklinePainter(
                    trend,
                    color.withValues(alpha: 0.5),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
          Text(
            content,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              letterSpacing: -0.5,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 10,
              color: cs.onSurfaceVariant.withValues(alpha: 0.7),
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (extraItems != null && extraItems.isNotEmpty) ...[
            const Divider(height: 16, thickness: 0.5),
            ...extraItems,
          ],
        ],
      ),
    );
  }

  Widget _buildStatCard(
    String title,
    String content,
    String subtitle,
    IconData icon,
    Color color,
    ColorScheme cs, {
    List<Widget>? extraItems,
  }) {
    return OptionalLiquidGlassCard(
      padding: const EdgeInsets.all(16),
      borderRadius: 24,
      highContrast: true,
      fallbackDecoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.3)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 16),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurfaceVariant,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            content,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              letterSpacing: -0.5,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 10,
              color: cs.onSurfaceVariant.withValues(alpha: 0.7),
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (extraItems != null && extraItems.isNotEmpty) ...[
            const Divider(height: 16, thickness: 0.5),
            ...extraItems,
          ],
        ],
      ),
    );
  }

  Widget _buildRankItem(int rank, String label, String value, ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          if (rank > 0) ...[
            Container(
              width: 12,
              height: 12,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: cs.onSurfaceVariant.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(3),
              ),
              child: Text(
                '$rank',
                style: TextStyle(
                  fontSize: 8,
                  fontWeight: FontWeight.bold,
                  color: cs.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(width: 6),
          ],
          Expanded(
            child: Text(
              label,
              style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: cs.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}
