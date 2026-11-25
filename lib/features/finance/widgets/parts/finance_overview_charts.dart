part of '../finance_widgets.dart';

extension _FinanceOverviewChartsExt on _FinanceOverviewPanelState {
  Widget _buildCumulativeBalanceTrendCard(
    BuildContext context,
    ColorScheme colorScheme,
  ) {
    final now = clock();
    final points = FinanceRepository.cumulativeBalanceTrend(
      events: widget.cumulativeBalanceEvents,
      selectedMonth: month,
      nowAt: now.millisecondsSinceEpoch,
      openingBalanceMinor: widget.openingBalanceMinor,
      openingBalanceStartDate: widget.openingBalanceStartDate,
    );
    final matchingIndex = points.indexWhere(
      (point) => dateKey(point.month) == _selectedCumulativeTrendMonthKey,
    );
    final selectedIndex = matchingIndex >= 0
        ? matchingIndex
        : points.length - 1;
    final selectedPoint = selectedIndex >= 0 ? points[selectedIndex] : null;
    final rangeLabel = points.isEmpty
        ? '最多显示近 12 个月'
        : '${points.first.month.year}年${points.first.month.month}月'
              ' — ${points.last.month.year}年${points.last.month.month}月';
    final effectiveEndMonth =
        DateTime(month.year, month.month).isAfter(DateTime(now.year, now.month))
        ? DateTime(now.year, now.month)
        : DateTime(month.year, month.month);
    final rangeEndDate =
        effectiveEndMonth.year == now.year &&
            effectiveEndMonth.month == now.month
        ? dateKey(now)
        : dateKey(
            DateTime(effectiveEndMonth.year, effectiveEndMonth.month + 1, 0),
          );
    final isBeforeOpeningDate =
        widget.openingBalanceStartDate != null &&
        rangeEndDate.compareTo(widget.openingBalanceStartDate!) < 0;
    final hasNoBalanceHistory =
        widget.cumulativeBalanceEvents.isEmpty &&
        widget.openingBalanceMinor == 0 &&
        widget.openingBalanceStartDate == null;

    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: colorScheme.outlineVariant.withValues(alpha: 0.35),
          width: 0.8,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '月度累计结余趋势',
              style: Theme.of(context).textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 2),
            Text(
              rangeLabel,
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: colorScheme.onSurfaceVariant),
            ),
            if (selectedPoint case final point?) ...[
              const SizedBox(height: 12),
              Semantics(
                liveRegion: true,
                label:
                    '${point.month.year}年${point.month.month}月，'
                    '${point.isCurrentMonth ? '截至今天' : '月末'}累计结余'
                    ' ${formatFinanceAmount(point.balanceMinor)}',
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${point.month.year}年${point.month.month}月 · '
                        '${point.isCurrentMonth ? '截至今天' : '月末'}',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                    Text(
                      formatFinanceAmount(point.balanceMinor),
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: colorScheme.primary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              if (widget.onOpenMonthLedger != null)
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    key: _selectedTrendLedgerActionKey,
                    onPressed: () => unawaited(
                      widget.onOpenMonthLedger!(
                        selectedPoint.month,
                        _selectedTrendLedgerActionKey,
                      ),
                    ),
                    icon: const Icon(Icons.receipt_long_outlined, size: 18),
                    label: const Text('查看当月账单'),
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                  ),
                ),
              const SizedBox(height: 4),
              SizedBox(
                height: 148,
                width: double.infinity,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final semanticPoints = points
                        .map(
                          (item) =>
                              '${item.month.year}年${item.month.month}月'
                              '${item.isCurrentMonth ? '截至今天' : '月末'}'
                              '${formatFinanceAmount(item.balanceMinor)}',
                        )
                        .join('；');
                    return Semantics(
                      button: true,
                      label: '月度累计结余趋势。$semanticPoints。点击图表选择月份。',
                      customSemanticsActions: {
                        if (selectedIndex > 0)
                          const CustomSemanticsAction(label: '前一个月'): () =>
                              _selectCumulativeTrendPoint(
                                points,
                                selectedIndex - 1,
                              ),
                        if (selectedIndex < points.length - 1)
                          const CustomSemanticsAction(label: '后一个月'): () =>
                              _selectCumulativeTrendPoint(
                                points,
                                selectedIndex + 1,
                              ),
                      },
                      child: GestureDetector(
                        key: const ValueKey(
                          'finance-cumulative-balance-trend-chart',
                        ),
                        behavior: HitTestBehavior.opaque,
                        onTapUp: (details) {
                          final index = _cumulativeTrendIndexForPosition(
                            details.localPosition.dx,
                            constraints.maxWidth,
                            points.length,
                          );
                          _selectCumulativeTrendPoint(points, index);
                        },
                        child: RepaintBoundary(
                          child: CustomPaint(
                            size: Size(constraints.maxWidth, 148),
                            painter: _FinanceCumulativeBalanceTrendPainter(
                              points: points,
                              selectedIndex: selectedIndex,
                              colorScheme: colorScheme,
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ] else ...[
              const SizedBox(height: 16),
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  child: Text(
                    isBeforeOpeningDate
                        ? '尚未到期初结余起算日期'
                        : hasNoBalanceHistory
                        ? '暂无可展示的结余趋势'
                        : '所选月份没有可用的累计结余',
                    style: Theme.of(context).textTheme.bodyMedium
                        ?.copyWith(color: colorScheme.onSurfaceVariant),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  int _cumulativeTrendIndexForPosition(
    double position,
    double width,
    int pointCount,
  ) {
    if (pointCount < 2) return 0;
    const horizontalInset = 18.0;
    final plotWidth = math.max(1.0, width - horizontalInset * 2);
    final fraction = ((position - horizontalInset) / plotWidth).clamp(0.0, 1.0);
    return (fraction * (pointCount - 1)).round();
  }

  void _selectCumulativeTrendPoint(
    List<FinanceCumulativeBalancePoint> points,
    int index,
  ) {
    if (index < 0 || index >= points.length) return;
    _mutateState(() {
      _selectedCumulativeTrendMonthKey = dateKey(points[index].month);
    });
  }

  Widget _buildCumulativeBalanceCard(
    BuildContext context,
    ColorScheme colorScheme,
  ) {
    final asOfDate = _cumulativeBalanceAsOf;
    final asOfDateKey = dateKey(asOfDate);
    final isToday = asOfDateKey == dateKey(clock());
    final openingStartDate = widget.openingBalanceStartDate;
    final isBeforeOpeningDate =
        openingStartDate != null && asOfDateKey.compareTo(openingStartDate) < 0;
    final sourceLabel = openingStartDate == null
        ? '按全部历史账单累计'
        : '从 $openingStartDate 起算，期初 '
              '${formatFinanceAmount(widget.openingBalanceMinor)}';

    return Card(
      color: colorScheme.secondaryContainer,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: colorScheme.outlineVariant.withValues(alpha: 0.35),
          width: 0.8,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 14, 10, 14),
        child: Row(
          children: [
            Icon(
              Icons.savings_outlined,
              color: colorScheme.onSecondaryContainer,
              size: 28,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '累计结余',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: colorScheme.onSecondaryContainer,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    isToday ? '截至今天' : '截至 $asOfDateKey',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSecondaryContainer.withValues(
                        alpha: 0.75,
                      ),
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    isBeforeOpeningDate
                        ? '—'
                        : _cumulativeBalanceMinor == null
                        ? '计算中…'
                        : formatFinanceAmount(_cumulativeBalanceMinor!),
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: colorScheme.onSecondaryContainer,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    isBeforeOpeningDate ? '尚未到期初起算日' : sourceLabel,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSecondaryContainer.withValues(
                        alpha: 0.75,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (widget.onEditOpeningBalance != null)
              IconButton(
                tooltip: '设置期初结余',
                onPressed: widget.onEditOpeningBalance,
                icon: const Icon(Icons.tune_rounded),
                color: colorScheme.onSecondaryContainer,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryCard(
    BuildContext context,
    ColorScheme colorScheme,
    _FinanceOverviewPeriod period,
  ) {
    return Card(
      color: colorScheme.primaryContainer,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(
          color: colorScheme.outlineVariant.withValues(alpha: 0.35),
          width: 0.8,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth >= 640;
            final headerRow = Row(
              children: [
                Flexible(
                  child: Text(
                    period.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: colorScheme.onPrimaryContainer.withValues(
                        alpha: 0.85,
                      ),
                      fontWeight: FontWeight.w600,
                      fontSize: 13.5,
                    ),
                  ),
                ),
                if (!isWide) const Spacer(),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: colorScheme.surface.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    period.isPlanned ? '计划收支' : '实时统计',
                    style: TextStyle(
                      color: colorScheme.onPrimaryContainer,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            );

            final metricsContainer = Container(
              decoration: BoxDecoration(
                color: colorScheme.surface.withValues(alpha: 0.32),
                borderRadius: BorderRadius.circular(16),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: _buildSummaryMetric(
                      context,
                      label: period.isPlanned ? '计划收入' : '收入',
                      value: formatFinanceAmount(period.summary.incomeMinor),
                      color: colorScheme.onPrimaryContainer,
                    ),
                  ),
                  Container(
                    height: 28,
                    width: 1,
                    color: colorScheme.onPrimaryContainer.withValues(
                      alpha: 0.15,
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(left: 12),
                      child: _buildSummaryMetric(
                        context,
                        label: period.isPlanned ? '计划总支出' : '总支出',
                        value: formatFinanceAmount(period.summary.expenseMinor),
                        color: colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                  Container(
                    height: 28,
                    width: 1,
                    color: colorScheme.onPrimaryContainer.withValues(
                      alpha: 0.15,
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(left: 12),
                      child: _buildSummaryMetric(
                        context,
                        label: period.isPlanned ? '计划结余' : '本期结余',
                        value: formatFinanceAmount(period.summary.balanceMinor),
                        color: colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                ],
              ),
            );

            if (isWide) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    flex: 4,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        headerRow,
                        const SizedBox(height: 6),
                        Text(
                          formatFinanceAmount(period.summary.netExpenseMinor),
                          style: TextStyle(
                            color: colorScheme.onPrimaryContainer,
                            fontSize: 32,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.5,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          period.isPlanned ? '计划净支出' : '净支出',
                          style: TextStyle(
                            color: colorScheme.onPrimaryContainer.withValues(
                              alpha: 0.8,
                            ),
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(flex: 5, child: metricsContainer),
                ],
              );
            }

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                headerRow,
                const SizedBox(height: 6),
                Text(
                  formatFinanceAmount(period.summary.netExpenseMinor),
                  style: TextStyle(
                    color: colorScheme.onPrimaryContainer,
                    fontSize: 30,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  period.isPlanned ? '计划净支出' : '净支出',
                  style: TextStyle(
                    color: colorScheme.onPrimaryContainer.withValues(
                      alpha: 0.8,
                    ),
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 12),
                metricsContainer,
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildSummaryMetric(
    BuildContext context, {
    required String label,
    required String value,
    required Color color,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(color: color.withValues(alpha: 0.75), fontSize: 12),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: color, fontWeight: FontWeight.w700),
        ),
      ],
    );
  }

  Widget _buildUnifiedCategoryCard(
    BuildContext context,
    ColorScheme colorScheme,
    List<_FinanceCategoryTotal> topCategories,
    List<_FinanceCategoryTotal> shareTotals,
    _FinanceOverviewPeriod period, {
    required FinanceCategoryType categoryType,
  }) {
    return _FinanceUnifiedCategoryCard(
      colorScheme: colorScheme,
      topCategories: topCategories,
      shareTotals: shareTotals,
      period: period,
      categoryType: categoryType,
      categories: categories,
      categoryDisplayName: _categoryDisplayName,
      onOpenCategoryDetail: (entry, period, sourceKey) => _openCategoryDetail(
        entry,
        period,
        sourceKey,
        categoryType: categoryType,
      ),
      categorySourceKeys: _categorySourceKeys,
      view: _view,
    );
  }

  _FinanceOverviewAnalytics _overviewAnalytics(_FinanceOverviewPeriod period) {
    final cached = _cachedAnalytics;
    if (cached != null && identical(_analyticsSourcePeriod, period)) {
      return cached;
    }

    final topTotals = <String, int>{};
    final shareTotals = <String, int>{};
    final incomeTotals = <String, int>{};
    final hourlyNetExpenseMinor = _view == _FinanceOverviewView.day
        ? List<int>.filled(25, 0)
        : null;
    var outflowTransactionCount = 0;

    for (final transaction in period.transactions) {
      if (transaction.isExpenseLike) outflowTransactionCount++;
      if (hourlyNetExpenseMinor != null && transaction.isExpenseLike) {
        final hour = _financeTransactionHour(transaction) ?? 24;
        hourlyNetExpenseMinor[hour] +=
            transaction.type == FinanceTransactionType.refund
            ? -transaction.amountMinor
            : transaction.amountMinor;
      }

      final topAmount = switch (transaction.type) {
        FinanceTransactionType.expense => transaction.amountMinor,
        FinanceTransactionType.refund => -transaction.amountMinor,
        FinanceTransactionType.income || FinanceTransactionType.transfer => 0,
      };
      final includeInShares =
          transaction.type == FinanceTransactionType.expense &&
          transaction.amountMinor > 0;
      final includeInIncome =
          transaction.type == FinanceTransactionType.income &&
          transaction.amountMinor > 0;
      if (topAmount == 0 && !includeInShares && !includeInIncome) continue;

      final categoryUuid = transaction.categoryUuid?.trim();
      final category = categoryUuid == null || categoryUuid.isEmpty
          ? null
          : categories[categoryUuid];
      final rootUuid = category == null
          ? categoryUuid ?? ''
          : _rootCategory(category).uuid;

      if (topAmount != 0) {
        topTotals[rootUuid] = (topTotals[rootUuid] ?? 0) + topAmount;
      }
      if (includeInShares) {
        shareTotals[rootUuid] =
            (shareTotals[rootUuid] ?? 0) + transaction.amountMinor;
      }
      if (includeInIncome) {
        incomeTotals[rootUuid] =
            (incomeTotals[rootUuid] ?? 0) + transaction.amountMinor;
      }
    }

    final topExpenseCategories = [
      for (final entry in topTotals.entries)
        if (entry.value > 0)
          _FinanceCategoryTotal(
            categoryUuid: entry.key.isEmpty ? null : entry.key,
            value: entry.value,
          ),
    ]..sort((a, b) => b.value.compareTo(a.value));
    final categoryExpenseShares = [
      for (final entry in shareTotals.entries)
        _FinanceCategoryTotal(
          categoryUuid: entry.key.isEmpty ? null : entry.key,
          value: entry.value,
        ),
    ]..sort((a, b) => b.value.compareTo(a.value));
    final topIncomeCategories = [
      for (final entry in incomeTotals.entries)
        if (entry.value > 0)
          _FinanceCategoryTotal(
            categoryUuid: entry.key.isEmpty ? null : entry.key,
            value: entry.value,
          ),
    ]..sort((a, b) => b.value.compareTo(a.value));

    FinanceTransaction? maxExpenseTransaction;
    final paymentMethodExpenseTotals = <String?, int>{};
    for (final transaction in period.transactions) {
      if (transaction.type == FinanceTransactionType.expense) {
        if (maxExpenseTransaction == null ||
            transaction.amountMinor > maxExpenseTransaction.amountMinor) {
          maxExpenseTransaction = transaction;
        }
        final pmUuid = transaction.paymentMethodUuid?.trim();
        paymentMethodExpenseTotals[pmUuid] =
            (paymentMethodExpenseTotals[pmUuid] ?? 0) + transaction.amountMinor;
      }
    }

    int? previousPeriodNetExpenseMinor;
    if (_view == _FinanceOverviewView.month) {
      final prevMonth = DateTime(month.year, month.month - 1);
      final prevFromKey = dateKey(DateTime(prevMonth.year, prevMonth.month));
      final prevToKey = dateKey(DateTime(prevMonth.year, prevMonth.month + 1));
      var prevExpense = 0;
      for (final transaction in transactions) {
        if (transaction.transactionDate.compareTo(prevFromKey) >= 0 &&
            transaction.transactionDate.compareTo(prevToKey) < 0) {
          if (transaction.type == FinanceTransactionType.expense) {
            prevExpense += transaction.amountMinor;
          } else if (transaction.type == FinanceTransactionType.refund) {
            prevExpense -= transaction.amountMinor;
          }
        }
      }
      previousPeriodNetExpenseMinor = prevExpense;
    }

    final analytics = _FinanceOverviewAnalytics(
      topExpenseCategories: topExpenseCategories,
      categoryExpenseShares: categoryExpenseShares,
      topIncomeCategories: topIncomeCategories,
      outflowTransactionCount: outflowTransactionCount,
      hourlyNetExpenseMinor: hourlyNetExpenseMinor,
      maxExpenseTransaction: maxExpenseTransaction,
      previousPeriodNetExpenseMinor: previousPeriodNetExpenseMinor,
      paymentMethodExpenseTotals: paymentMethodExpenseTotals,
    );
    _analyticsSourcePeriod = period;
    return _cachedAnalytics = analytics;
  }

  FinanceCategory _rootCategory(FinanceCategory category) {
    if (!identical(_categoryRootCacheSource, categories)) {
      final rootsByUuid = <String, FinanceCategory>{};
      for (final currentCategory in categories.values) {
        var current = currentCategory;
        final visited = <String>{};
        while (visited.add(current.uuid)) {
          final parentUuid = current.parentUuid?.trim();
          if (parentUuid == null || parentUuid.isEmpty) break;
          final parent = categories[parentUuid];
          if (parent == null || parent.type != current.type) break;
          current = parent;
        }
        rootsByUuid[currentCategory.uuid] = current;
      }
      _categoryRootCacheSource = categories;
      _categoryRootsByUuid = rootsByUuid;
    }
    return _categoryRootsByUuid[category.uuid] ?? category;
  }

  Future<void> _openCategoryDetail(
    _FinanceCategoryTotal entry,
    _FinanceOverviewPeriod period,
    GlobalKey sourceKey, {
    FinanceCategoryType categoryType = FinanceCategoryType.expense,
  }) async {
    final category = entry.categoryUuid == null
        ? null
        : categories[entry.categoryUuid];
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final detailPage = FinanceCategoryDetailScreen(
      periodTitle: period.title,
      periodStart: period.from,
      periodEnd: period.to,
      clock: clock,
      isPlanned: period.isPlanned,
      categoryType: categoryType,
      rootCategoryUuid: entry.categoryUuid,
      categoryTapOpensLedger: widget.categoryTapOpensLedger,
      transactions: period.transactions,
      categories: categories,
      onCategorySelected: onCategorySelected == null
          ? null
          : (categoryUuid, sourceKey, periodTransactions) =>
                onCategorySelected!(
                  categoryUuid,
                  sourceKey,
                  periodTransactions,
                ),
      onCategorySelectedWithRange: onCategorySelectedWithRange == null
          ? null
          : (categoryUuid, sourceKey, periodTransactions, periodRange) =>
                onCategorySelectedWithRange!(
                  categoryUuid,
                  sourceKey,
                  periodTransactions,
                  periodRange,
                ),
      onOpenTransaction: widget.onOpenTransaction,
    );
    await PageTransitions.pushFromRect<String>(
      context: context,
      page: detailPage,
      sourceKey: sourceKey,
      sourceColor: colorScheme.brightness == Brightness.dark
          ? Colors.black
          : Colors.white,
      placeholderBuilder: (_) =>
          Text(category?.icon ?? '💰', style: const TextStyle(fontSize: 30)),
      sourceBorderRadius: BorderRadius.circular(12),
    );
  }

  Widget _buildSpendingChart(
    BuildContext context,
    ColorScheme colorScheme,
    _FinanceOverviewPeriod period,
    _FinanceOverviewAnalytics analytics,
  ) {
    final spendingLabel = period.isPlanned ? '计划净支出' : '净支出';
    final emptyMessage = analytics.hasOutflowTransactions
        ? period.isPlanned
              ? '计划支出与退款相抵，计划净支出为 ${formatFinanceAmount(0)}'
              : '支出与退款相抵，净支出为 ${formatFinanceAmount(0)}'
        : period.isPlanned
        ? '${period.shortTitle}还没有计划净支出记录'
        : '${period.shortTitle}还没有净支出记录';
    if (_view == _FinanceOverviewView.day) {
      const unknownHourIndex = 24;
      final values = analytics.hourlyNetExpenseMinor!;
      return _buildBarChart(
        context,
        colorScheme,
        values: values,
        labels: [
          for (var hour = 0; hour < values.length; hour++)
            if (hour == unknownHourIndex)
              '未知'
            else if (hour % 3 == 0)
              '$hour时'
            else
              '',
        ],
        tooltips: [
          for (var hour = 0; hour < values.length; hour++)
            hour == unknownHourIndex
                ? '未知时刻 · $spendingLabel ${formatFinanceAmount(values[hour])}'
                : '$hour时 · $spendingLabel ${formatFinanceAmount(values[hour])}',
        ],
        emptyMessage: emptyMessage,
        barWidth: 28,
      );
    }

    final count = _view == _FinanceOverviewView.month
        ? DateTime(month.year, month.month + 1, 0).day
        : 7;
    final values = List<int>.generate(
      count,
      (index) =>
          period.summary.expenseByDate[dateKey(
            financeCalendarDayOffset(period.from, index),
          )] ??
          0,
    );
    final dates = List<DateTime>.generate(
      count,
      (index) => financeCalendarDayOffset(period.from, index),
    );
    return _buildBarChart(
      context,
      colorScheme,
      values: values,
      labels: [for (final date in dates) _formatFinanceChartDayLabel(date)],
      tooltips: [
        for (var index = 0; index < dates.length; index++)
          '${_formatFinanceDayLabel(dateKey(dates[index]))} · '
              '$spendingLabel ${formatFinanceAmount(values[index])}',
      ],
      emptyMessage: emptyMessage,
      barWidth: _view == _FinanceOverviewView.month ? 24 : 40,
    );
  }

  int? _financeTransactionHour(FinanceTransaction transaction) {
    final occurred = transaction.occurrenceLocalTime;
    if (occurred == null || dateKey(occurred) != transaction.transactionDate) {
      return null;
    }
    return occurred.hour;
  }

  String _formatFinanceChartDayLabel(DateTime date) {
    return _view == _FinanceOverviewView.month
        ? '${date.day}'
        : '${date.month}/${date.day}';
  }

  Widget _buildBarChart(
    BuildContext context,
    ColorScheme colorScheme, {
    required List<int> values,
    required List<String> labels,
    required List<String> tooltips,
    required String emptyMessage,
    required double barWidth,
  }) {
    final maxMagnitude = values.fold<int>(0, (maximum, value) {
      final magnitude = value.abs();
      return magnitude > maximum ? magnitude : maximum;
    });
    if (maxMagnitude == 0) {
      return _buildEmptyCard(
        context,
        icon: Icons.bar_chart_outlined,
        message: emptyMessage,
        nested: true,
      );
    }
    const plotHeight = 88.0;
    final hasPositive = values.any((value) => value > 0);
    final hasNegative = values.any((value) => value < 0);
    final baseline = hasPositive && hasNegative
        ? plotHeight / 2
        : hasPositive
        ? plotHeight
        : 0.0;
    return SizedBox(
      height: 142,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (var index = 0; index < values.length; index++)
              SizedBox(
                width: barWidth,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: Column(
                    children: [
                      SizedBox(
                        height: plotHeight,
                        child: Stack(
                          children: [
                            if (hasPositive && hasNegative)
                              Positioned(
                                left: 0,
                                right: 0,
                                top: baseline,
                                child: Container(
                                  height: 1,
                                  color: colorScheme.outlineVariant,
                                ),
                              ),
                            Positioned(
                              left: (barWidth - 18) / 2,
                              top:
                                  values[index] < 0 ||
                                      (values[index] == 0 && !hasPositive)
                                  ? baseline
                                  : null,
                              bottom:
                                  values[index] < 0 ||
                                      (values[index] == 0 && !hasPositive)
                                  ? null
                                  : plotHeight - baseline,
                              child: Tooltip(
                                message: tooltips[index],
                                preferBelow: false,
                                child: Container(
                                  width: 12,
                                  height: values[index] == 0
                                      ? 2
                                      : ((values[index].abs() / maxMagnitude) *
                                                (values[index] < 0
                                                    ? plotHeight - baseline
                                                    : baseline))
                                            .clamp(2, plotHeight)
                                            .toDouble(),
                                  decoration: BoxDecoration(
                                    color: values[index] < 0
                                        ? colorScheme.primary
                                        : colorScheme.error,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        labels[index],
                        style: TextStyle(
                          fontSize: 10,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
