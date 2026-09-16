import 'package:flutter/material.dart';

import '../../../widgets/floating_bottom_bar.dart';
import '../models/finance_models.dart';
import '../services/finance_repository.dart';
import '../screens/finance_category_detail_screen.dart';

/// Leaves enough scrollable room for the shared navigation bar and its bottom
/// margin, so the final finance card can clear the bar completely.
double financeBottomContentPaddingFor(BuildContext context) {
  return floatingBottomNavigationContentPaddingFor(context);
}

enum _FinanceOverviewView { month, week, day }

class FinanceOverviewPanel extends StatefulWidget {
  final double topPadding;
  final DateTime month;
  final FinanceSummary summary;
  final List<FinanceTransaction> transactions;
  final Map<String, FinanceCategory> categories;
  final VoidCallback onAdd;
  final GlobalKey addActionKey;
  final Future<void> Function() onRefresh;
  final ValueChanged<DateTime>? onMonthChanged;
  final ValueChanged<String>? onCategorySelected;

  const FinanceOverviewPanel({
    super.key,
    this.topPadding = 0,
    required this.month,
    required this.summary,
    required this.transactions,
    required this.categories,
    required this.onAdd,
    required this.addActionKey,
    required this.onRefresh,
    this.onMonthChanged,
    this.onCategorySelected,
  });

  @override
  State<FinanceOverviewPanel> createState() => _FinanceOverviewPanelState();
}

class _FinanceOverviewPanelState extends State<FinanceOverviewPanel> {
  _FinanceOverviewView _view = _FinanceOverviewView.month;
  late DateTime _focusedDate;

  DateTime get month => widget.month;
  FinanceSummary get summary => widget.summary;
  List<FinanceTransaction> get transactions => widget.transactions;
  Map<String, FinanceCategory> get categories => widget.categories;
  VoidCallback get onAdd => widget.onAdd;
  GlobalKey get addActionKey => widget.addActionKey;
  Future<void> Function() get onRefresh => widget.onRefresh;
  ValueChanged<DateTime>? get onMonthChanged => widget.onMonthChanged;
  ValueChanged<String>? get onCategorySelected => widget.onCategorySelected;

  @override
  void initState() {
    super.initState();
    _focusedDate = _initialFocusDate(month);
  }

  @override
  void didUpdateWidget(covariant FinanceOverviewPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.month.year != month.year ||
        oldWidget.month.month != month.month) {
      _focusedDate = _initialFocusDate(month);
    }
  }

  DateTime _initialFocusDate(DateTime selectedMonth) {
    final today = DateTime.now();
    if (today.year == selectedMonth.year &&
        today.month == selectedMonth.month) {
      return DateTime(today.year, today.month, today.day);
    }
    return DateTime(selectedMonth.year, selectedMonth.month, 1);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final period = _currentPeriod;
    final topCategories = _topExpenseCategories(period);
    final maxCategory = topCategories.isEmpty ? 1 : topCategories.first.value;
    final bottomPadding = financeBottomContentPaddingFor(context);

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        padding:
            EdgeInsets.fromLTRB(16, widget.topPadding + 12, 16, bottomPadding),
        children: [
          _buildViewSelector(context),
          const SizedBox(height: 10),
          _buildPeriodNavigator(context),
          const SizedBox(height: 12),
          _buildSummaryCard(context, colorScheme, period),
          const SizedBox(height: 16),
          FilledButton.tonalIcon(
            key: addActionKey,
            onPressed: onAdd,
            icon: const Icon(Icons.add),
            label: const Text('记一笔'),
          ),
          const SizedBox(height: 24),
          Text(
            '支出分类',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 8),
          if (topCategories.isEmpty)
            _buildEmptyCard(
              context,
              icon: Icons.pie_chart_outline,
              message: '${period.shortTitle}还没有支出记录',
            )
          else
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    for (final entry in topCategories.take(8))
                      _buildCategoryBar(
                        context,
                        entry,
                        maxCategory,
                        colorScheme,
                        period,
                      ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 24),
          Text(
            _spendingChartTitle,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 16, 12, 12),
              child: _buildSpendingChart(context, colorScheme, period),
            ),
          ),
          const SizedBox(height: 24),
          _buildInsightCard(context, colorScheme, period),
        ],
      ),
    );
  }

  _FinanceOverviewPeriod get _currentPeriod {
    final range = _periodRange;
    final periodTransactions = _transactionsInRange(range);
    final periodSummary = _view == _FinanceOverviewView.month
        ? summary
        : _summarizeFinanceTransactions(periodTransactions);
    final title = switch (_view) {
      _FinanceOverviewView.month => '${month.year} 年 ${month.month} 月',
      _FinanceOverviewView.week =>
        _formatFinanceDateRange(range.from, range.to),
      _FinanceOverviewView.day => _formatFinanceDayLabel(dateKey(_focusedDate)),
    };
    final shortTitle = switch (_view) {
      _FinanceOverviewView.month => '本月',
      _FinanceOverviewView.week => '本周',
      _FinanceOverviewView.day => '当天',
    };
    return _FinanceOverviewPeriod(
      from: range.from,
      to: range.to,
      title: title,
      shortTitle: shortTitle,
      summary: periodSummary,
      transactions: periodTransactions,
    );
  }

  String get _spendingChartTitle => switch (_view) {
        _FinanceOverviewView.month => '每日支出',
        _FinanceOverviewView.week => '本周每日支出',
        _FinanceOverviewView.day => '当天时段支出',
      };

  _FinanceDateRange get _periodRange {
    switch (_view) {
      case _FinanceOverviewView.month:
        return _FinanceDateRange(
          DateTime(month.year, month.month),
          DateTime(month.year, month.month + 1),
        );
      case _FinanceOverviewView.week:
        final weekStart = _startOfWeek(_focusedDate);
        return _FinanceDateRange(
            weekStart, weekStart.add(const Duration(days: 7)));
      case _FinanceOverviewView.day:
        final day =
            DateTime(_focusedDate.year, _focusedDate.month, _focusedDate.day);
        return _FinanceDateRange(day, day.add(const Duration(days: 1)));
    }
  }

  DateTime _startOfWeek(DateTime value) {
    final day = DateTime(value.year, value.month, value.day);
    return day.subtract(Duration(days: day.weekday - DateTime.monday));
  }

  List<FinanceTransaction> _transactionsInRange(_FinanceDateRange range) {
    final fromKey = dateKey(range.from);
    final toKey = dateKey(range.to);
    return transactions
        .where(
          (transaction) =>
              transaction.transactionDate.compareTo(fromKey) >= 0 &&
              transaction.transactionDate.compareTo(toKey) < 0,
        )
        .toList();
  }

  Widget _buildViewSelector(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '时间视图',
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
        ),
        const SizedBox(height: 6),
        SizedBox(
          width: double.infinity,
          child: SegmentedButton<_FinanceOverviewView>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(
                value: _FinanceOverviewView.month,
                label: Text('月视图'),
              ),
              ButtonSegment(
                value: _FinanceOverviewView.week,
                label: Text('周视图'),
              ),
              ButtonSegment(
                value: _FinanceOverviewView.day,
                label: Text('日视图'),
              ),
            ],
            selected: {_view},
            onSelectionChanged: (selection) {
              setState(() => _view = selection.first);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildPeriodNavigator(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final period = _periodRange;
    final isMonthView = _view == _FinanceOverviewView.month;
    final title = switch (_view) {
      _FinanceOverviewView.month => '${month.year}年${month.month}月',
      _FinanceOverviewView.week =>
        _formatFinanceDateRange(period.from, period.to),
      _FinanceOverviewView.day => _formatFinanceDayLabel(dateKey(_focusedDate)),
    };
    final subtitle = switch (_view) {
      _FinanceOverviewView.month => '选择月份',
      _FinanceOverviewView.week => '周一至周日',
      _FinanceOverviewView.day => '选择具体日期',
    };
    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: Row(
        children: [
          IconButton(
            key: const ValueKey('finance-overview-period-previous'),
            tooltip: isMonthView
                ? '上个月'
                : _view == _FinanceOverviewView.week
                    ? '上一周'
                    : '前一天',
            onPressed: isMonthView
                ? () => _shiftMonth(-1)
                : () => _shiftFocusedPeriod(-1),
            icon: const Icon(Icons.chevron_left),
          ),
          Expanded(
            child: InkWell(
              key: const ValueKey('finance-overview-period-picker'),
              borderRadius: BorderRadius.circular(12),
              onTap: isMonthView ? _pickMonth : _pickFocusedDate,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Column(
                  children: [
                    Text(
                      title,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: colorScheme.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          IconButton(
            key: const ValueKey('finance-overview-period-next'),
            tooltip: isMonthView
                ? '下个月'
                : _view == _FinanceOverviewView.week
                    ? '下一周'
                    : '后一天',
            onPressed: isMonthView
                ? () => _shiftMonth(1)
                : () => _shiftFocusedPeriod(1),
            icon: const Icon(Icons.chevron_right),
          ),
        ],
      ),
    );
  }

  void _shiftMonth(int delta) {
    onMonthChanged?.call(DateTime(month.year, month.month + delta));
  }

  Future<void> _pickMonth() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: month,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 3650)),
      helpText: '选择月份',
    );
    if (picked != null && mounted) {
      onMonthChanged?.call(DateTime(picked.year, picked.month));
    }
  }

  Future<void> _pickFocusedDate() async {
    final lastDay = DateTime(month.year, month.month + 1, 0).day;
    final picked = await showDatePicker(
      context: context,
      initialDate: _focusedDate,
      firstDate: DateTime(month.year, month.month),
      lastDate: DateTime(month.year, month.month, lastDay),
      helpText: _view == _FinanceOverviewView.week ? '选择周视图日期' : '选择日视图日期',
    );
    if (picked != null && mounted) {
      setState(
          () => _focusedDate = DateTime(picked.year, picked.month, picked.day));
    }
  }

  void _shiftFocusedPeriod(int delta) {
    final next = _view == _FinanceOverviewView.week
        ? _focusedDate.add(Duration(days: delta * 7))
        : _focusedDate.add(Duration(days: delta));
    setState(() => _focusedDate = _clampToSelectedMonth(next));
  }

  DateTime _clampToSelectedMonth(DateTime value) {
    final lastDay = DateTime(month.year, month.month + 1, 0).day;
    final day = value.day.clamp(1, lastDay).toInt();
    return DateTime(month.year, month.month, day);
  }

  Widget _buildSummaryCard(
    BuildContext context,
    ColorScheme colorScheme,
    _FinanceOverviewPeriod period,
  ) {
    return Card(
      color: colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              period.title,
              style: TextStyle(color: colorScheme.onPrimaryContainer),
            ),
            const SizedBox(height: 8),
            Text(
              formatFinanceAmount(period.summary.netExpenseMinor),
              style: TextStyle(
                color: colorScheme.onPrimaryContainer,
                fontSize: 32,
                fontWeight: FontWeight.w800,
              ),
            ),
            Text(
              '净支出',
              style: TextStyle(color: colorScheme.onPrimaryContainer),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: _buildSummaryMetric(
                    context,
                    label: '收入',
                    value: formatFinanceAmount(period.summary.incomeMinor),
                    color: colorScheme.onPrimaryContainer,
                  ),
                ),
                Expanded(
                  child: _buildSummaryMetric(
                    context,
                    label: '实际支出',
                    value: formatFinanceAmount(period.summary.netExpenseMinor),
                    color: colorScheme.onPrimaryContainer,
                  ),
                ),
                Expanded(
                  child: _buildSummaryMetric(
                    context,
                    label: '结余',
                    value: formatFinanceAmount(period.summary.balanceMinor),
                    color: colorScheme.onPrimaryContainer,
                  ),
                ),
              ],
            ),
          ],
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

  Widget _buildCategoryBar(
    BuildContext context,
    _FinanceCategoryTotal entry,
    int maxCategory,
    ColorScheme colorScheme,
    _FinanceOverviewPeriod period,
  ) {
    final category =
        entry.categoryUuid == null ? null : categories[entry.categoryUuid];
    final categoryName = category == null ? '未分类' : category.name;
    final categoryKey = ValueKey(
      'finance-overview-category-${entry.categoryUuid ?? 'uncategorized'}',
    );
    return Semantics(
      button: true,
      label: '查看$categoryName支出详情',
      child: InkWell(
        key: categoryKey,
        borderRadius: BorderRadius.circular(12),
        onTap: () => _openCategoryDetail(entry, period),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
          child: Row(
            children: [
              SizedBox(
                width: 82,
                child: Text(
                  category == null ? '未分类' : '${category.icon} $categoryName',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    minHeight: 8,
                    value: entry.value / maxCategory,
                    backgroundColor: colorScheme.surfaceContainerHighest,
                    color: colorScheme.primary,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                formatFinanceAmount(entry.value),
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(width: 2),
              Icon(
                Icons.chevron_right,
                size: 18,
                color: colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<_FinanceCategoryTotal> _topExpenseCategories(
    _FinanceOverviewPeriod period,
  ) {
    final totals = <String, int>{};
    for (final transaction in period.transactions) {
      final amount = switch (transaction.type) {
        FinanceTransactionType.expense => transaction.amountMinor,
        FinanceTransactionType.refund => -transaction.amountMinor,
        FinanceTransactionType.income => 0,
      };
      if (amount == 0) continue;
      final category = categories[transaction.categoryUuid];
      final rootUuid = category == null ? '' : _rootCategory(category).uuid;
      totals[rootUuid] = (totals[rootUuid] ?? 0) + amount;
    }
    final result = [
      for (final entry in totals.entries)
        if (entry.value > 0)
          _FinanceCategoryTotal(
            categoryUuid: entry.key.isEmpty ? null : entry.key,
            value: entry.value,
          ),
    ];
    result.sort((a, b) => b.value.compareTo(a.value));
    return result;
  }

  FinanceCategory _rootCategory(FinanceCategory category) {
    var current = category;
    final visited = <String>{};
    while (visited.add(current.uuid)) {
      final parentUuid = current.parentUuid?.trim();
      if (parentUuid == null || parentUuid.isEmpty) break;
      final parent = categories[parentUuid];
      if (parent == null || parent.type != current.type) break;
      current = parent;
    }
    return current;
  }

  Future<void> _openCategoryDetail(
    _FinanceCategoryTotal entry,
    _FinanceOverviewPeriod period,
  ) async {
    final selectedCategoryUuid = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => FinanceCategoryDetailScreen(
          periodTitle: period.title,
          rootCategoryUuid: entry.categoryUuid,
          transactions: period.transactions,
          categories: categories,
        ),
      ),
    );
    if (selectedCategoryUuid != null && mounted) {
      onCategorySelected?.call(selectedCategoryUuid);
    }
  }

  Widget _buildSpendingChart(
    BuildContext context,
    ColorScheme colorScheme,
    _FinanceOverviewPeriod period,
  ) {
    if (_view == _FinanceOverviewView.day) {
      final values = List<int>.filled(24, 0);
      for (final transaction in period.transactions) {
        if (transaction.type == FinanceTransactionType.income) continue;
        final hour = _financeTransactionHour(transaction);
        values[hour] += transaction.type == FinanceTransactionType.refund
            ? -transaction.amountMinor
            : transaction.amountMinor;
      }
      return _buildBarChart(
        context,
        colorScheme,
        values: values,
        labels: [
          for (var hour = 0; hour < values.length; hour++)
            hour % 3 == 0 ? '$hour时' : '',
        ],
        tooltips: [
          for (var hour = 0; hour < values.length; hour++)
            '$hour时 · 净支出 ${formatFinanceAmount(values[hour])}',
        ],
        emptyMessage: '${period.shortTitle}还没有支出记录',
        barWidth: 28,
      );
    }

    final count = _view == _FinanceOverviewView.month
        ? DateTime(month.year, month.month + 1, 0).day
        : 7;
    final values = List<int>.generate(
      count,
      (index) =>
          period.summary
              .expenseByDate[dateKey(period.from.add(Duration(days: index)))] ??
          0,
    );
    final dates = List<DateTime>.generate(
      count,
      (index) => period.from.add(Duration(days: index)),
    );
    return _buildBarChart(
      context,
      colorScheme,
      values: values,
      labels: [
        for (final date in dates) _formatFinanceChartDayLabel(date),
      ],
      tooltips: [
        for (var index = 0; index < dates.length; index++)
          '${_formatFinanceDayLabel(dateKey(dates[index]))} · '
              '净支出 ${formatFinanceAmount(values[index])}',
      ],
      emptyMessage: '${period.shortTitle}还没有支出记录',
      barWidth: _view == _FinanceOverviewView.month ? 24 : 40,
    );
  }

  int _financeTransactionHour(FinanceTransaction transaction) {
    final occurredAt = transaction.occurredAt;
    if (occurredAt == null) return 12;
    final occurred = DateTime.fromMillisecondsSinceEpoch(occurredAt);
    return dateKey(occurred) == transaction.transactionDate
        ? occurred.hour
        : 12;
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
    final maxValue =
        values.fold<int>(0, (max, value) => value > max ? value : max);
    if (maxValue == 0) {
      return _buildEmptyCard(
        context,
        icon: Icons.bar_chart_outlined,
        message: emptyMessage,
        nested: true,
      );
    }
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
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Expanded(
                        child: Align(
                          alignment: Alignment.bottomCenter,
                          child: Tooltip(
                            message: tooltips[index],
                            preferBelow: false,
                            child: Container(
                              width: 12,
                              height: values[index] <= 0
                                  ? 2
                                  : 88 * values[index] / maxValue + 2,
                              decoration: BoxDecoration(
                                color: colorScheme.primary,
                                borderRadius: BorderRadius.circular(6),
                              ),
                            ),
                          ),
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

  Widget _buildInsightCard(
    BuildContext context,
    ColorScheme colorScheme,
    _FinanceOverviewPeriod period,
  ) {
    if (period.summary.transactionCount == 0) return const SizedBox.shrink();
    final average =
        period.summary.netExpenseMinor ~/ period.summary.transactionCount;
    return Card(
      child: ListTile(
        leading: Icon(Icons.lightbulb_outline, color: colorScheme.primary),
        title: Text('${period.shortTitle}小结'),
        subtitle: Text(
          '共 ${period.summary.transactionCount} 笔记录，平均每笔 ${formatFinanceAmount(average)}。',
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
      child: Padding(
        padding: EdgeInsets.all(nested ? 8 : 24),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: colorScheme.onSurfaceVariant),
            const SizedBox(width: 8),
            Text(
              message,
              style: TextStyle(color: colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

class FinanceLedgerPanel extends StatefulWidget {
  final double topPadding;
  final List<FinanceTransaction> transactions;
  final Map<String, FinanceCategory> categories;
  final Map<String, FinancePaymentMethod> paymentMethods;
  final String keyword;
  final FinanceTransactionType? filterType;
  final String? categoryUuid;
  final void Function(FinanceTransaction, GlobalKey) onOpenDetail;
  final ValueChanged<String> onKeywordChanged;
  final ValueChanged<FinanceTransactionType?> onFilterChanged;
  final ValueChanged<String?>? onCategoryChanged;
  final ValueChanged<FinanceTransaction> onEdit;
  final ValueChanged<FinanceTransaction> onDelete;
  final ValueChanged<FinanceTransaction> onRefund;

  const FinanceLedgerPanel({
    super.key,
    this.topPadding = 0,
    required this.transactions,
    required this.categories,
    required this.paymentMethods,
    required this.keyword,
    required this.filterType,
    this.categoryUuid,
    required this.onOpenDetail,
    required this.onKeywordChanged,
    required this.onFilterChanged,
    this.onCategoryChanged,
    required this.onEdit,
    required this.onDelete,
    required this.onRefund,
  });

  @override
  State<FinanceLedgerPanel> createState() => _FinanceLedgerPanelState();
}

class _FinanceLedgerPanelState extends State<FinanceLedgerPanel> {
  final Map<String, GlobalKey> _cardKeys = {};

  List<FinanceTransaction> get transactions => widget.transactions;
  Map<String, FinanceCategory> get categories => widget.categories;
  Map<String, FinancePaymentMethod> get paymentMethods => widget.paymentMethods;
  String get keyword => widget.keyword;
  FinanceTransactionType? get filterType => widget.filterType;
  String? get categoryUuid => widget.categoryUuid;
  void Function(FinanceTransaction, GlobalKey) get onOpenDetail =>
      widget.onOpenDetail;
  ValueChanged<String> get onKeywordChanged => widget.onKeywordChanged;
  ValueChanged<FinanceTransactionType?> get onFilterChanged =>
      widget.onFilterChanged;
  ValueChanged<String?>? get onCategoryChanged => widget.onCategoryChanged;
  ValueChanged<FinanceTransaction> get onEdit => widget.onEdit;
  ValueChanged<FinanceTransaction> get onDelete => widget.onDelete;
  ValueChanged<FinanceTransaction> get onRefund => widget.onRefund;

  GlobalKey _cardKeyFor(FinanceTransaction transaction) {
    return _cardKeys.putIfAbsent(transaction.uuid, GlobalKey.new);
  }

  @override
  Widget build(BuildContext context) {
    final filtered = transactions.where((transaction) {
      if (filterType != null && transaction.type != filterType) return false;
      if (categoryUuid != null && transaction.categoryUuid != categoryUuid) {
        return false;
      }
      if (keyword.trim().isEmpty) return true;
      final query = keyword.trim().toLowerCase();
      final category = categories[transaction.categoryUuid];
      final payment = paymentMethods[transaction.paymentMethodUuid];
      final categoryName = category == null
          ? null
          : financeCategoryDisplayName(category, categories.values);
      final content = [
        transaction.merchant,
        transaction.note,
        categoryName,
        payment?.name,
        transaction.transactionDate,
      ].whereType<String>().join(' ').toLowerCase();
      return content.contains(query);
    }).toList();
    final dayGroups = _groupFinanceTransactionsByDay(filtered);
    final bottomPadding = financeBottomContentPaddingFor(context);

    return Column(
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(16, widget.topPadding + 12, 16, 4),
          child: TextField(
            onChanged: onKeywordChanged,
            decoration: InputDecoration(
              hintText: '搜索商家、备注或分类',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: keyword.isEmpty
                  ? null
                  : IconButton(
                      onPressed: () => onKeywordChanged(''),
                      icon: const Icon(Icons.clear),
                    ),
              border: const OutlineInputBorder(),
              isDense: true,
            ),
          ),
        ),
        SizedBox(
          height: 48,
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            scrollDirection: Axis.horizontal,
            children: [
              _buildFilterChip(context, '全部', null),
              for (final type in FinanceTransactionType.values)
                _buildFilterChip(context, type.label, type),
              if (categoryUuid != null) _buildCategoryFilterChip(context),
            ],
          ),
        ),
        Expanded(
          child: filtered.isEmpty
              ? _buildEmptyState(context)
              : ListView(
                  padding: EdgeInsets.fromLTRB(16, 4, 16, bottomPadding),
                  children: [
                    for (var groupIndex = 0;
                        groupIndex < dayGroups.length;
                        groupIndex++) ...[
                      _buildDayHeader(context, dayGroups[groupIndex]),
                      for (var transactionIndex = 0;
                          transactionIndex <
                              dayGroups[groupIndex].transactions.length;
                          transactionIndex++) ...[
                        _buildTransactionTile(
                          context,
                          dayGroups[groupIndex].transactions[transactionIndex],
                        ),
                        if (transactionIndex + 1 <
                            dayGroups[groupIndex].transactions.length)
                          const SizedBox(height: 8),
                      ],
                      if (groupIndex + 1 < dayGroups.length)
                        const SizedBox(height: 8),
                    ],
                  ],
                ),
        ),
      ],
    );
  }

  Widget _buildFilterChip(
    BuildContext context,
    String label,
    FinanceTransactionType? type,
  ) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: filterType == type,
        onSelected: (_) => onFilterChanged(type),
      ),
    );
  }

  Widget _buildCategoryFilterChip(BuildContext context) {
    final category = categories[categoryUuid];
    final label = category == null
        ? '分类筛选'
        : '分类 · ${financeCategoryDisplayName(category, categories.values)}';
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        key: const ValueKey('finance-ledger-category-filter'),
        avatar: category == null ? null : Text(category.icon),
        label: Text(label),
        selected: true,
        onSelected: onCategoryChanged == null
            ? null
            : (_) => onCategoryChanged?.call(null),
      ),
    );
  }

  Widget _buildDayHeader(BuildContext context, _FinanceDayGroup group) {
    final colorScheme = Theme.of(context).colorScheme;
    final hasExpenseFlow = group.expenseMinor > 0 || group.refundMinor > 0;
    final amountLabels = <String>[
      if (hasExpenseFlow) '净支出 ${formatFinanceAmount(group.netExpenseMinor)}',
      if (group.incomeMinor > 0) '收入 ${formatFinanceAmount(group.incomeMinor)}',
    ];
    if (amountLabels.isEmpty) {
      amountLabels.add('${group.transactions.length} 笔');
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 10, 4, 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(
            Icons.calendar_today_outlined,
            size: 18,
            color: colorScheme.primary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _formatFinanceDayLabel(group.date),
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                Text(
                  '${group.transactions.length} 笔账单',
                  style: TextStyle(
                    color: colorScheme.onSurfaceVariant,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (final label in amountLabels)
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: label.startsWith('收入')
                          ? colorScheme.primary
                          : group.netExpenseMinor > 0
                              ? colorScheme.error
                              : colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTransactionTile(
    BuildContext context,
    FinanceTransaction transaction,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    final category = categories[transaction.categoryUuid];
    final payment = paymentMethods[transaction.paymentMethodUuid];
    final categoryName = category == null
        ? null
        : financeCategoryDisplayName(category, categories.values);
    final title = transaction.merchant?.isNotEmpty == true
        ? transaction.merchant!
        : categoryName ?? transaction.type.label;
    final subtitleParts = <String>[
      if (category != null) '${category.icon} $categoryName',
      if (payment != null) '${payment.icon} ${payment.name}',
      if (transaction.installmentLabel != null)
        '分期 ${transaction.installmentLabel}',
      if (transaction.note?.isNotEmpty == true) transaction.note!,
    ];
    final amountColor = transaction.type == FinanceTransactionType.expense
        ? colorScheme.error
        : colorScheme.primary;
    final sourceKey = _cardKeyFor(transaction);
    return Card(
      key: sourceKey,
      child: ListTile(
        onTap: () => onOpenDetail(transaction, sourceKey),
        leading: CircleAvatar(
          backgroundColor: colorScheme.secondaryContainer,
          child: Text(
            category?.icon ?? '💰',
            style: const TextStyle(fontSize: 20),
          ),
        ),
        title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          subtitleParts.isEmpty
              ? transaction.type.label
              : subtitleParts.join(' · '),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              formatSignedFinanceAmount(
                  transaction.amountMinor, transaction.type),
              style: TextStyle(
                color: amountColor,
                fontWeight: FontWeight.w700,
              ),
            ),
            PopupMenuButton<String>(
              onSelected: (value) {
                if (value == 'refund') onRefund(transaction);
                if (value == 'edit') onEdit(transaction);
                if (value == 'delete') onDelete(transaction);
              },
              itemBuilder: (context) => [
                if (transaction.type == FinanceTransactionType.expense)
                  const PopupMenuItem(
                    value: 'refund',
                    child: Text('退款'),
                  ),
                const PopupMenuItem(value: 'edit', child: Text('编辑')),
                const PopupMenuItem(value: 'delete', child: Text('删除')),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.receipt_long_outlined,
              size: 48, color: colorScheme.onSurfaceVariant),
          const SizedBox(height: 12),
          Text(
            keyword.isEmpty && filterType == null && categoryUuid == null
                ? '本月还没有账单'
                : '没有匹配的账单',
            style: TextStyle(color: colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _FinanceDateRange {
  final DateTime from;
  final DateTime to;

  const _FinanceDateRange(this.from, this.to);
}

class _FinanceOverviewPeriod {
  final DateTime from;
  final DateTime to;
  final String title;
  final String shortTitle;
  final FinanceSummary summary;
  final List<FinanceTransaction> transactions;

  const _FinanceOverviewPeriod({
    required this.from,
    required this.to,
    required this.title,
    required this.shortTitle,
    required this.summary,
    required this.transactions,
  });
}

class _FinanceCategoryTotal {
  final String? categoryUuid;
  final int value;

  const _FinanceCategoryTotal({
    required this.categoryUuid,
    required this.value,
  });
}

FinanceSummary _summarizeFinanceTransactions(
  Iterable<FinanceTransaction> transactions,
) {
  var income = 0;
  var expense = 0;
  var refund = 0;
  var transactionCount = 0;
  final expenseByCategory = <String, int>{};
  final incomeByCategory = <String, int>{};
  final expenseByDate = <String, int>{};

  for (final transaction in transactions) {
    transactionCount++;
    final categoryUuid = transaction.categoryUuid ?? '';
    switch (transaction.type) {
      case FinanceTransactionType.income:
        income += transaction.amountMinor;
        incomeByCategory[categoryUuid] =
            (incomeByCategory[categoryUuid] ?? 0) + transaction.amountMinor;
      case FinanceTransactionType.expense:
        expense += transaction.amountMinor;
        expenseByCategory[categoryUuid] =
            (expenseByCategory[categoryUuid] ?? 0) + transaction.amountMinor;
        expenseByDate[transaction.transactionDate] =
            (expenseByDate[transaction.transactionDate] ?? 0) +
                transaction.amountMinor;
      case FinanceTransactionType.refund:
        refund += transaction.amountMinor;
        expenseByCategory[categoryUuid] =
            (expenseByCategory[categoryUuid] ?? 0) - transaction.amountMinor;
        expenseByDate[transaction.transactionDate] =
            (expenseByDate[transaction.transactionDate] ?? 0) -
                transaction.amountMinor;
    }
  }

  return FinanceSummary(
    incomeMinor: income,
    expenseMinor: expense,
    refundMinor: refund,
    transactionCount: transactionCount,
    expenseByCategory: expenseByCategory,
    incomeByCategory: incomeByCategory,
    expenseByDate: expenseByDate,
  );
}

String _formatFinanceDateRange(DateTime from, DateTime to) {
  final lastDay = to.subtract(const Duration(days: 1));
  if (from.year == lastDay.year && from.month == lastDay.month) {
    return '${from.month}月${from.day}日 - ${lastDay.day}日';
  }
  if (from.year == lastDay.year) {
    return '${from.month}月${from.day}日 - '
        '${lastDay.month}月${lastDay.day}日';
  }
  return '${dateKey(from)} - ${dateKey(lastDay)}';
}

class _FinanceDayGroup {
  final String date;
  final List<FinanceTransaction> transactions;
  final int expenseMinor;
  final int refundMinor;
  final int incomeMinor;

  const _FinanceDayGroup({
    required this.date,
    required this.transactions,
    required this.expenseMinor,
    required this.refundMinor,
    required this.incomeMinor,
  });

  int get netExpenseMinor => expenseMinor - refundMinor;
}

List<_FinanceDayGroup> _groupFinanceTransactionsByDay(
  Iterable<FinanceTransaction> transactions,
) {
  final grouped = <String, List<FinanceTransaction>>{};
  for (final transaction in transactions) {
    grouped.putIfAbsent(transaction.transactionDate, () => []).add(transaction);
  }

  final dates = grouped.keys.toList()..sort((a, b) => b.compareTo(a));
  final result = <_FinanceDayGroup>[];
  for (final date in dates) {
    final items = List<FinanceTransaction>.of(grouped[date]!)
      ..sort((a, b) {
        final occurredComparison = (b.occurredAt ?? b.updatedAt).compareTo(
          a.occurredAt ?? a.updatedAt,
        );
        if (occurredComparison != 0) return occurredComparison;
        final updatedComparison = b.updatedAt.compareTo(a.updatedAt);
        if (updatedComparison != 0) return updatedComparison;
        return b.uuid.compareTo(a.uuid);
      });
    var expenseMinor = 0;
    var refundMinor = 0;
    var incomeMinor = 0;
    for (final item in items) {
      switch (item.type) {
        case FinanceTransactionType.expense:
          expenseMinor += item.amountMinor;
        case FinanceTransactionType.refund:
          refundMinor += item.amountMinor;
        case FinanceTransactionType.income:
          incomeMinor += item.amountMinor;
      }
    }
    result.add(_FinanceDayGroup(
      date: date,
      transactions: items,
      expenseMinor: expenseMinor,
      refundMinor: refundMinor,
      incomeMinor: incomeMinor,
    ));
  }
  return result;
}

String _formatFinanceDayLabel(String value) {
  final date = dateFromKey(value);
  const weekdays = <String>['', '周一', '周二', '周三', '周四', '周五', '周六', '周日'];
  final weekday = date.weekday >= 1 && date.weekday <= 7
      ? ' ${weekdays[date.weekday]}'
      : '';
  return '${date.month}月${date.day}日$weekday';
}
