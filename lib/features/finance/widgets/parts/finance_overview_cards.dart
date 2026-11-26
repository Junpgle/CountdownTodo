part of '../finance_widgets.dart';

extension _FinanceOverviewCardsExt on _FinanceOverviewPanelState {
  Widget _buildQuickActionsRow(BuildContext context, ColorScheme colorScheme) {
    final activeTemplates = templates.where((t) => !t.isDeleted).toList()
      ..sort((a, b) => b.useCount.compareTo(a.useCount));
    final displayTemplates = activeTemplates.take(4).toList();

    final hasBudgetAction = widget.onOpenBudgets != null;
    final hasRecurringAction = widget.onOpenFutureCommitments != null;
    if (!hasBudgetAction && !hasRecurringAction && displayTemplates.isEmpty) {
      return const SizedBox.shrink();
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      child: Row(
        children: [
          if (hasBudgetAction) ...[
            _buildActionPill(
              context,
              colorScheme,
              icon: Icons.account_balance_wallet_outlined,
              label: '预算管理',
              onTap: widget.onOpenBudgets!,
            ),
            const SizedBox(width: 8),
          ],
          if (hasRecurringAction) ...[
            _buildActionPill(
              context,
              colorScheme,
              icon: Icons.event_repeat_rounded,
              label: '周期收支',
              onTap: widget.onOpenFutureCommitments!,
            ),
            const SizedBox(width: 8),
          ],
          for (final template in displayTemplates) ...[
            _buildTemplatePill(context, colorScheme, template),
            const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }

  Widget _buildActionPill(
    BuildContext context,
    ColorScheme colorScheme, {
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool isPrimary = false,
  }) {
    return Material(
      color: isPrimary
          ? colorScheme.primaryContainer
          : colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 15,
                color: isPrimary
                    ? colorScheme.onPrimaryContainer
                    : colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 5),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: isPrimary ? FontWeight.w600 : FontWeight.w500,
                  color: isPrimary
                      ? colorScheme.onPrimaryContainer
                      : colorScheme.onSurface,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTemplatePill(
    BuildContext context,
    ColorScheme colorScheme,
    FinanceEntryTemplate template,
  ) {
    final amountText = template.amountMinor > 0
        ? ' ${formatFinanceAmount(template.amountMinor)}'
        : '';
    return Material(
      color: colorScheme.surfaceContainerLowest,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: colorScheme.outlineVariant.withValues(alpha: 0.4),
          width: 0.8,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => widget.onOpenTemplate?.call(template),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6.5),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.flash_on_rounded,
                size: 14,
                color: colorScheme.secondary,
              ),
              const SizedBox(width: 4),
              Text(
                '${template.name}$amountText',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBudgetCard(
    BuildContext context,
    ColorScheme colorScheme,
    _FinanceOverviewPeriod period,
  ) {
    final monthKey =
        '${month.year.toString().padLeft(4, '0')}-${month.month.toString().padLeft(2, '0')}';
    final overallBudget = budgets.cast<FinanceBudget?>().firstWhere(
      (b) => b != null && !b.isDeleted && b.isOverall && b.monthKey == monthKey,
      orElse: () => null,
    );

    if (overallBudget == null) {
      if (widget.onOpenBudgets == null) return const SizedBox.shrink();
      return Card(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.35),
            width: 0.8,
          ),
        ),
        color: colorScheme.surfaceContainerLow,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: widget.onOpenBudgets,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: colorScheme.secondaryContainer.withValues(
                      alpha: 0.6,
                    ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.pie_chart_outline_rounded,
                    color: colorScheme.secondary,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${month.month}月未设定总预算',
                        style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '设定月度预算以实时掌握支出进度与日均额度',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  '去设置',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: colorScheme.primary,
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 16,
                  color: colorScheme.primary,
                ),
              ],
            ),
          ),
        ),
      );
    }

    final budgetMinor = overallBudget.amountMinor;
    final monthNetExpenseMinor = _view == _FinanceOverviewView.month
        ? period.summary.netExpenseMinor
        : () {
            var exp = 0;
            final prefix = monthKey;
            for (final tx in transactions) {
              if (tx.transactionDate.startsWith(prefix)) {
                if (tx.type == FinanceTransactionType.expense) {
                  exp += tx.amountMinor;
                } else if (tx.type == FinanceTransactionType.refund) {
                  exp -= tx.amountMinor;
                }
              }
            }
            return exp;
          }();

    final remainingMinor = budgetMinor - monthNetExpenseMinor;
    final progress = budgetMinor > 0
        ? (monthNetExpenseMinor / budgetMinor).clamp(0.0, 1.0)
        : 0.0;
    final percentNumber = budgetMinor > 0
        ? ((monthNetExpenseMinor / budgetMinor) * 100).toStringAsFixed(1)
        : '0.0';
    final isOverspent = remainingMinor < 0;

    final now = clock();
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    int daysRemaining;
    if (now.year == month.year && now.month == month.month) {
      daysRemaining = math.max(1, daysInMonth - now.day + 1);
    } else if (DateTime(
      month.year,
      month.month,
    ).isBefore(DateTime(now.year, now.month))) {
      daysRemaining = 0;
    } else {
      daysRemaining = daysInMonth;
    }

    final dailyAllowanceMinor = (!isOverspent && daysRemaining > 0)
        ? remainingMinor ~/ daysRemaining
        : 0;

    final progressColor = isOverspent
        ? colorScheme.error
        : progress > 0.85
        ? Colors.orange
        : colorScheme.primary;

    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: colorScheme.outlineVariant.withValues(alpha: 0.35),
          width: 0.8,
        ),
      ),
      color: colorScheme.surfaceContainerLow,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: widget.onOpenBudgets,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: progressColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.account_balance_wallet_rounded,
                      color: progressColor,
                      size: 16,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${month.month}月总预算',
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '总额 ${formatFinanceAmount(budgetMinor)}',
                    style: TextStyle(
                      fontSize: 12,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 16,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    isOverspent ? '已超支 ' : '剩余 ',
                    style: TextStyle(
                      fontSize: 12.5,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  Text(
                    formatFinanceAmount(remainingMinor.abs()),
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      letterSpacing: -0.5,
                      color: isOverspent
                          ? colorScheme.error
                          : colorScheme.primary,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '已用 $percentNumber%',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: progressColor,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 6,
                  backgroundColor: colorScheme.surfaceContainerHighest,
                  valueColor: AlwaysStoppedAnimation<Color>(progressColor),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Icon(
                    isOverspent
                        ? Icons.warning_amber_rounded
                        : Icons.calendar_today_rounded,
                    size: 13,
                    color: isOverspent
                        ? colorScheme.error
                        : colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(
                      isOverspent
                          ? '超出预算 ${formatFinanceAmount(remainingMinor.abs())}，建议合理规划后续开支'
                          : daysRemaining > 0
                          ? '剩余 $daysRemaining 天，建议日均支出额度 ${formatFinanceAmount(dailyAllowanceMinor)}'
                          : '本月已结束，最终节余 ${formatFinanceAmount(remainingMinor)}',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: isOverspent
                            ? colorScheme.error
                            : colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEnhancedInsightCard(
    BuildContext context,
    ColorScheme colorScheme,
    _FinanceOverviewPeriod period,
    _FinanceOverviewAnalytics analytics,
  ) {
    if (period.summary.transactionCount == 0) return const SizedBox.shrink();

    final averageMinor = analytics.outflowTransactionCount == 0
        ? 0
        : period.summary.netExpenseMinor ~/ analytics.outflowTransactionCount;

    final maxTx = analytics.maxExpenseTransaction;
    final prevPeriodExpense = analytics.previousPeriodNetExpenseMinor;

    final momDifference = (prevPeriodExpense != null && prevPeriodExpense > 0)
        ? period.summary.netExpenseMinor - prevPeriodExpense
        : null;
    final momPercent = (momDifference != null && prevPeriodExpense! > 0)
        ? ((momDifference.abs() / prevPeriodExpense) * 100).toStringAsFixed(1)
        : null;

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Card(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.35),
            width: 0.8,
          ),
        ),
        color: colorScheme.surfaceContainerLow,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: colorScheme.primaryContainer.withValues(
                        alpha: 0.5,
                      ),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.insights_rounded,
                      color: colorScheme.primary,
                      size: 16,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    period.isPlanned
                        ? '${period.shortTitle}计划小结与洞察'
                        : '${period.shortTitle}消费节奏与洞察',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13.5,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              LayoutBuilder(
                builder: (context, constraints) {
                  final isWide = constraints.maxWidth > 420;
                  final tiles = [
                    _buildInsightMetricTile(
                      context,
                      colorScheme,
                      label: period.isPlanned ? '平均计划支出' : '笔均支出',
                      value: formatFinanceAmount(averageMinor),
                      hint: '共 ${analytics.outflowTransactionCount} 笔支出/退款',
                    ),
                    if (maxTx != null)
                      () {
                        final desc = (maxTx.merchant?.trim().isNotEmpty == true)
                            ? maxTx.merchant!.trim()
                            : (maxTx.note?.trim().isNotEmpty == true
                                  ? maxTx.note!.trim()
                                  : '');
                        return _buildInsightMetricTile(
                          context,
                          colorScheme,
                          label: '最高单笔支出',
                          value: formatFinanceAmount(maxTx.amountMinor),
                          hint:
                              _categoryDisplayName(maxTx.categoryUuid) +
                              (desc.isNotEmpty ? ' · $desc' : ''),
                        );
                      }(),
                    if (momDifference != null && momPercent != null)
                      _buildInsightMetricTile(
                        context,
                        colorScheme,
                        label: '环比上月',
                        value: '${momDifference >= 0 ? '+' : '-'}$momPercent%',
                        valueColor: momDifference > 0
                            ? colorScheme.error
                            : Colors.green,
                        hint: momDifference >= 0
                            ? '多支出 ${formatFinanceAmount(momDifference)}'
                            : '少支出 ${formatFinanceAmount(momDifference.abs())}',
                      ),
                  ];

                  if (isWide) {
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (int i = 0; i < tiles.length; i++) ...[
                          Expanded(child: tiles[i]),
                          if (i < tiles.length - 1) const SizedBox(width: 8),
                        ],
                      ],
                    );
                  }
                  return Column(
                    children: [
                      for (int i = 0; i < tiles.length; i++) ...[
                        tiles[i],
                        if (i < tiles.length - 1) const SizedBox(height: 6),
                      ],
                    ],
                  );
                },
              ),
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerLowest,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  analytics.outflowTransactionCount == 0
                      ? (period.isPlanned
                            ? '共 ${period.summary.transactionCount} 笔待发生记录，本期暂无计划支出或退款记录。'
                            : '共 ${period.summary.transactionCount} 笔记录，本期暂无支出或退款记录。')
                      : (period.isPlanned
                            ? '共 ${period.summary.transactionCount} 笔记录，计划支出/退款 ${analytics.outflowTransactionCount} 笔，平均净支出 ${formatFinanceAmount(averageMinor)}。'
                            : '共 ${period.summary.transactionCount} 笔记录，支出/退款 ${analytics.outflowTransactionCount} 笔，平均净支出 ${formatFinanceAmount(averageMinor)}。'),
                  style: TextStyle(
                    color: colorScheme.onSurfaceVariant,
                    fontSize: 12,
                    height: 1.35,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInsightMetricTile(
    BuildContext context,
    ColorScheme colorScheme, {
    required String label,
    required String value,
    required String hint,
    Color? valueColor,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.bold,
              color: valueColor ?? colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            hint,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 10.5, color: colorScheme.outline),
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentMethodSpendingCard(
    BuildContext context,
    ColorScheme colorScheme,
    _FinanceOverviewPeriod period,
    _FinanceOverviewAnalytics analytics,
  ) {
    if (analytics.paymentMethodExpenseTotals.isEmpty) {
      return const SizedBox.shrink();
    }

    final pmMap = {for (final pm in paymentMethods) pm.uuid: pm};
    final items = <_PaymentMethodSpendingItem>[];
    var totalExpenseMinor = 0;

    for (final entry in analytics.paymentMethodExpenseTotals.entries) {
      if (entry.value <= 0) continue;
      totalExpenseMinor += entry.value;
      final pm = entry.key != null ? pmMap[entry.key] : null;
      items.add(
        _PaymentMethodSpendingItem(
          paymentMethod: pm,
          name: pm?.name ?? '未指定账户',
          icon: pm?.icon ?? '💳',
          amountMinor: entry.value,
        ),
      );
    }

    if (items.isEmpty || totalExpenseMinor <= 0) {
      return const SizedBox.shrink();
    }

    items.sort((a, b) => b.amountMinor.compareTo(a.amountMinor));

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Card(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.35),
            width: 0.8,
          ),
        ),
        color: colorScheme.surfaceContainerLow,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: colorScheme.secondaryContainer.withValues(
                        alpha: 0.5,
                      ),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.credit_card_rounded,
                      color: colorScheme.secondary,
                      size: 16,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    '账户支出分布',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13.5,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '点击快速查账',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              for (int i = 0; i < items.length; i++) ...[
                () {
                  final item = items[i];
                  final ratio = item.amountMinor / totalExpenseMinor;
                  final percent = (ratio * 100).toStringAsFixed(1);
                  return InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: item.paymentMethod != null
                        ? () => widget.onSelectPaymentMethod?.call(
                            item.paymentMethod!,
                          )
                        : null,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 6,
                      ),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Text(
                                item.icon,
                                style: const TextStyle(fontSize: 14),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  item.name,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                              Text(
                                '$percent%',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Text(
                                formatFinanceAmount(item.amountMinor),
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(2),
                            child: LinearProgressIndicator(
                              value: ratio,
                              minHeight: 3.5,
                              backgroundColor:
                                  colorScheme.surfaceContainerHighest,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                colorScheme.primary.withValues(alpha: 0.7),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }(),
                if (i < items.length - 1) const SizedBox(height: 4),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildUpcomingCommitmentsCard(
    BuildContext context,
    ColorScheme colorScheme,
  ) {
    if (recurringRules.isEmpty) return const SizedBox.shrink();

    final now = clock();
    final today = CalendarDateMath.dateOnly(now);
    final sevenDaysLater = today.add(
      const Duration(days: 7, hours: 23, minutes: 59),
    );

    final upcoming = <_UpcomingCommitmentItem>[];
    for (final rule in recurringRules) {
      if (!rule.isEnabled || rule.isDeleted) continue;
      final dueThisMonth = rule.dueDateFor(now.year, now.month);
      if (dueThisMonth != null &&
          !dueThisMonth.isBefore(today) &&
          !dueThisMonth.isAfter(sevenDaysLater)) {
        upcoming.add(
          _UpcomingCommitmentItem(rule: rule, dueDate: dueThisMonth),
        );
      }
      if (now.day > 20) {
        final nextMonthDate = DateTime(now.year, now.month + 1);
        final dueNextMonth = rule.dueDateFor(
          nextMonthDate.year,
          nextMonthDate.month,
        );
        if (dueNextMonth != null &&
            !dueNextMonth.isBefore(today) &&
            !dueNextMonth.isAfter(sevenDaysLater)) {
          upcoming.add(
            _UpcomingCommitmentItem(rule: rule, dueDate: dueNextMonth),
          );
        }
      }
    }

    if (upcoming.isEmpty) return const SizedBox.shrink();

    upcoming.sort((a, b) => a.dueDate.compareTo(b.dueDate));

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Card(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.35),
            width: 0.8,
          ),
        ),
        color: colorScheme.surfaceContainerLow,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: widget.onOpenFutureCommitments,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        color: colorScheme.tertiaryContainer.withValues(
                          alpha: 0.5,
                        ),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        Icons.event_repeat_rounded,
                        color: colorScheme.tertiary,
                        size: 16,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '未来7天待发生收支 (${upcoming.length})',
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13.5,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '周期收支',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: colorScheme.primary,
                      ),
                    ),
                    Icon(
                      Icons.chevron_right_rounded,
                      size: 16,
                      color: colorScheme.primary,
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                for (final item in upcoming.take(3)) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            item.dueDate.day == now.day
                                ? '今天'
                                : item.dueDate.day == now.day + 1
                                ? '明天'
                                : '${item.dueDate.month}/${item.dueDate.day}',
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w600,
                              color: item.dueDate.day == now.day
                                  ? colorScheme.error
                                  : colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            item.rule.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        Text(
                          '${item.rule.type == FinanceTransactionType.expense ? '-' : '+'}${formatFinanceAmount(item.rule.amountMinor)}',
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color:
                                item.rule.type == FinanceTransactionType.expense
                                ? colorScheme.onSurface
                                : Colors.green,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyCard(
    BuildContext context, {
    required IconData icon,
    required String message,
    bool nested = false,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: colorScheme.outlineVariant.withValues(alpha: 0.35),
          width: 0.8,
        ),
      ),
      child: Padding(
        padding: EdgeInsets.all(nested ? 8 : 24),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: colorScheme.onSurfaceVariant),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                message,
                textAlign: TextAlign.center,
                style: TextStyle(color: colorScheme.onSurfaceVariant),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
