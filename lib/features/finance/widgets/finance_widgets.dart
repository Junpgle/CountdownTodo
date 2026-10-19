import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../widgets/floating_bottom_bar.dart';
import '../../../utils/page_transitions.dart';
import '../models/finance_models.dart';
import '../services/finance_repository.dart';
import '../screens/finance_category_detail_screen.dart';

import '../../../utils/app_dialogs.dart';

/// Leaves enough scrollable room for the shared navigation bar and its bottom
/// margin, so the final finance card can clear the bar completely.
double financeBottomContentPaddingFor(BuildContext context) {
  return floatingBottomNavigationContentPaddingFor(context);
}

enum _FinanceOverviewView { month, week, day }

typedef _FinanceOverviewPeriodCacheKey = ({
  List<FinanceTransaction> transactions,
  FinanceSummary summary,
  Map<String, FinanceCategory> categories,
  DateTime from,
  DateTime to,
  _FinanceOverviewView view,
  DateTime Function() clock,
  bool includesNow,
  bool isPlanned,
  bool selectedMonthIsCurrent,
  bool focusedDateIsToday,
});

typedef FinanceCategorySelectionCallback = Future<void> Function(
  String categoryUuid,
  GlobalKey sourceKey,
  List<FinanceTransaction> periodTransactions,
);

class FinanceOverviewPanel extends StatefulWidget {
  final double topPadding;
  final DateTime Function() clock;
  final DateTime month;
  final FinanceSummary summary;
  final List<FinanceTransaction> transactions;
  final List<FinanceCumulativeBalanceEvent> cumulativeBalanceEvents;
  final int openingBalanceMinor;
  final String? openingBalanceStartDate;
  final Map<String, FinanceCategory> categories;
  final VoidCallback onAdd;
  final VoidCallback? onEditOpeningBalance;
  final GlobalKey addActionKey;
  final bool categoryTapOpensLedger;
  final Future<void> Function() onRefresh;
  final ValueChanged<DateTime>? onMonthChanged;
  final FinanceCategorySelectionCallback? onCategorySelected;

  const FinanceOverviewPanel({
    super.key,
    this.topPadding = 0,
    this.clock = DateTime.now,
    required this.month,
    required this.summary,
    required this.transactions,
    this.cumulativeBalanceEvents = const [],
    this.openingBalanceMinor = 0,
    this.openingBalanceStartDate,
    required this.categories,
    required this.onAdd,
    this.onEditOpeningBalance,
    required this.addActionKey,
    this.categoryTapOpensLedger = true,
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
  int? _cumulativeBalanceMinor;
  final Map<String, GlobalKey> _categorySourceKeys = {};
  Map<String, FinanceCategory>? _categoryDisplayNamesSource;
  final Map<String, String> _categoryDisplayNames = {};
  Map<String, FinanceCategory>? _categoryRootCacheSource;
  Map<String, FinanceCategory> _categoryRootsByUuid = const {};
  _FinanceOverviewPeriodCacheKey? _periodCacheKey;
  _FinanceOverviewPeriod? _cachedPeriod;
  _FinanceOverviewPeriod? _analyticsSourcePeriod;
  _FinanceOverviewAnalytics? _cachedAnalytics;

  DateTime get month => widget.month;
  FinanceSummary get summary => widget.summary;
  List<FinanceTransaction> get transactions => widget.transactions;
  Map<String, FinanceCategory> get categories => widget.categories;
  VoidCallback get onAdd => widget.onAdd;
  GlobalKey get addActionKey => widget.addActionKey;
  Future<void> Function() get onRefresh => widget.onRefresh;
  DateTime Function() get clock => widget.clock;
  ValueChanged<DateTime>? get onMonthChanged => widget.onMonthChanged;
  FinanceCategorySelectionCallback? get onCategorySelected =>
      widget.onCategorySelected;

  String _categoryDisplayName(String? categoryUuid) {
    if (!identical(_categoryDisplayNamesSource, categories)) {
      _categoryDisplayNamesSource = categories;
      _categoryDisplayNames.clear();
    }
    return _categoryDisplayNames.putIfAbsent(
      categoryUuid ?? '',
      () => financeCategoryReferenceDisplayName(
        categoryUuid,
        categories.values,
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _focusedDate = _initialFocusDate(month);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _refreshCumulativeBalance();
    });
  }

  @override
  void didUpdateWidget(covariant FinanceOverviewPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    var refreshBalance = false;
    if (oldWidget.month.year != month.year ||
        oldWidget.month.month != month.month) {
      _focusedDate = _initialFocusDate(month);
      refreshBalance = true;
    }
    if (!identical(
          oldWidget.cumulativeBalanceEvents,
          widget.cumulativeBalanceEvents,
        ) ||
        oldWidget.openingBalanceMinor != widget.openingBalanceMinor ||
        oldWidget.openingBalanceStartDate != widget.openingBalanceStartDate) {
      refreshBalance = true;
    }
    if (refreshBalance) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _refreshCumulativeBalance();
      });
    }
  }

  DateTime _initialFocusDate(DateTime selectedMonth) {
    final today = clock();
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
    final analytics = _overviewAnalytics(period);
    final topCategories = analytics.topExpenseCategories;
    final categoryExpenseShares = analytics.categoryExpenseShares;
    final maxCategory = topCategories.isEmpty ? 1 : topCategories.first.value;
    final bottomPadding = financeBottomContentPaddingFor(context);

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        padding: EdgeInsets.fromLTRB(
          16,
          widget.topPadding + 12,
          16,
          bottomPadding,
        ),
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
            period.isPlanned ? '计划支出分类' : '支出分类',
            style: Theme.of(context).textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          if (topCategories.isEmpty)
            _buildEmptyCard(
              context,
              icon: Icons.pie_chart_outline,
              message: period.isPlanned
                  ? '${period.shortTitle}没有可展示的计划净支出分类'
                  : '${period.shortTitle}没有可展示的净支出分类',
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
          _buildInsightCard(
            context,
            colorScheme,
            period,
            analytics.outflowTransactionCount,
          ),
          const SizedBox(height: 24),
          Text(
            _spendingChartTitle(period),
            style: Theme.of(context).textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 16, 12, 12),
              child: _buildSpendingChart(
                context,
                colorScheme,
                period,
                analytics,
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            period.isPlanned ? '计划支出占比' : '各类别支出占比',
            style: Theme.of(context).textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          _buildCategoryShareCard(
            context,
            colorScheme,
            categoryExpenseShares,
            period,
          ),
          const SizedBox(height: 24),
          _buildCumulativeBalanceCard(context, colorScheme),
        ],
      ),
    );
  }

  _FinanceOverviewPeriod get _currentPeriod {
    final range = _periodRange;
    final now = clock();
    final includesNow = !now.isBefore(range.from) && now.isBefore(range.to);
    final isPlanned = range.from.isAfter(now);
    final selectedMonthIsCurrent =
        now.year == month.year && now.month == month.month;
    final focusedDateIsToday = dateKey(now) == dateKey(_focusedDate);
    final cacheKey = (
      transactions: transactions,
      summary: summary,
      categories: categories,
      from: range.from,
      to: range.to,
      view: _view,
      clock: clock,
      includesNow: includesNow,
      isPlanned: isPlanned,
      selectedMonthIsCurrent: selectedMonthIsCurrent,
      focusedDateIsToday: focusedDateIsToday,
    );
    final cachedPeriod = _cachedPeriod;
    if (cachedPeriod != null && _periodCacheKey == cacheKey) {
      return cachedPeriod;
    }

    final periodTransactions = _transactionsInRange(
      range,
      includedThrough: includesNow ? now.millisecondsSinceEpoch : null,
    );
    final periodSummary = _view == _FinanceOverviewView.month && !includesNow
        ? summary
        : FinanceRepository.summarizeTransactions(periodTransactions);
    final title = switch (_view) {
      _FinanceOverviewView.month => '${month.year} 年 ${month.month} 月',
      _FinanceOverviewView.week => _formatFinanceDateRange(
        range.from,
        range.to,
      ),
      _FinanceOverviewView.day => _formatFinanceDayLabel(dateKey(_focusedDate)),
    };
    final shortTitle = switch (_view) {
      _FinanceOverviewView.month =>
        selectedMonthIsCurrent ? '本月' : '${month.year}年${month.month}月',
      _FinanceOverviewView.week =>
        includesNow ? '本周' : _formatFinanceDateRange(range.from, range.to),
      _FinanceOverviewView.day =>
          focusedDateIsToday
              ? '今天'
              : _formatFinanceDayLabel(dateKey(_focusedDate)),
    };
    final period = _FinanceOverviewPeriod(
      from: range.from,
      to: range.to,
      title: title,
      shortTitle: shortTitle,
      summary: periodSummary,
      transactions: periodTransactions,
      isPlanned: isPlanned,
    );
    _periodCacheKey = cacheKey;
    return _cachedPeriod = period;
  }

  String _spendingChartTitle(_FinanceOverviewPeriod period) {
    if (period.isPlanned) {
      return switch (_view) {
        _FinanceOverviewView.month => '计划每日净支出',
        _FinanceOverviewView.week =>
          '计划${_formatFinanceDateRange(period.from, period.to)}每日净支出',
        _FinanceOverviewView.day =>
          '计划${_formatFinanceDayLabel(dateKey(_focusedDate))}时段净支出',
      };
    }
    final now = clock();
    return switch (_view) {
      _FinanceOverviewView.month => '每日净支出',
      _FinanceOverviewView.week =>
        !now.isBefore(_periodRange.from) && now.isBefore(_periodRange.to)
            ? '本周每日净支出'
            : '${_formatFinanceDateRange(_periodRange.from, _periodRange.to)}每日净支出',
      _FinanceOverviewView.day =>
        dateKey(now) == dateKey(_focusedDate)
            ? '当天时段净支出'
            : '${_formatFinanceDayLabel(dateKey(_focusedDate))}时段净支出',
    };
  }

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
          weekStart,
          financeCalendarDayOffset(weekStart, 7),
        );
      case _FinanceOverviewView.day:
        final day = DateTime(
          _focusedDate.year,
          _focusedDate.month,
          _focusedDate.day,
        );
        return _FinanceDateRange(day, financeCalendarDayOffset(day, 1));
    }
  }

  DateTime _startOfWeek(DateTime value) {
    final day = DateTime(value.year, value.month, value.day);
    return financeCalendarDayOffset(day, DateTime.monday - day.weekday);
  }

  List<FinanceTransaction> _transactionsInRange(
    _FinanceDateRange range, {
    int? includedThrough,
  }) {
    final fromKey = dateKey(range.from);
    final toKey = dateKey(range.to);
    return transactions
        .where((transaction) {
          if (transaction.transactionDate.compareTo(fromKey) < 0 ||
              transaction.transactionDate.compareTo(toKey) >= 0) {
            return false;
          }
          return includedThrough == null ||
              transaction.balanceEventAt() <= includedThrough;
        })
        .toList(growable: includedThrough == null);
  }

  Widget _buildViewSelector(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '时间视图',
          style: Theme.of(context).textTheme.labelLarge
              ?.copyWith(fontWeight: FontWeight.w700),
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
              _refreshCumulativeBalance();
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
    final canShiftPrevious = _canShiftFocusedPeriod(-1);
    final canShiftNext = _canShiftFocusedPeriod(1);
    final VoidCallback? previousAction;
    if (isMonthView) {
      previousAction = canShiftPrevious ? () => _shiftMonth(-1) : null;
    } else if (canShiftPrevious) {
      previousAction = () => _shiftFocusedPeriod(-1);
    } else {
      previousAction = null;
    }
    final VoidCallback? nextAction;
    if (isMonthView) {
      nextAction = canShiftNext ? () => _shiftMonth(1) : null;
    } else if (canShiftNext) {
      nextAction = () => _shiftFocusedPeriod(1);
    } else {
      nextAction = null;
    }
    final title = switch (_view) {
      _FinanceOverviewView.month => '${month.year}年${month.month}月',
      _FinanceOverviewView.week => _formatFinanceDateRange(
        period.from,
        period.to,
      ),
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
            onPressed: previousAction,
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
            onPressed: nextAction,
            icon: const Icon(Icons.chevron_right),
          ),
        ],
      ),
    );
  }

  void _shiftMonth(int delta) {
    if (!_canShiftFocusedPeriod(delta)) return;
    onMonthChanged?.call(DateTime(month.year, month.month + delta));
  }

  Future<void> _pickMonth() async {
    final picked = await showAppDatePicker(
      context: context,
      initialDate: month,
      firstDate: DateTime(2000),
      lastDate: clock().add(const Duration(days: 3650)),
      helpText: '选择月份',
    );
    if (picked != null && mounted) {
      onMonthChanged?.call(DateTime(picked.year, picked.month));
    }
  }

  Future<void> _pickFocusedDate() async {
    final lastDay = DateTime(month.year, month.month + 1, 0).day;
    final picked = await showAppDatePicker(
      context: context,
      initialDate: _focusedDate,
      firstDate: DateTime(month.year, month.month),
      lastDate: DateTime(month.year, month.month, lastDay),
      helpText: _view == _FinanceOverviewView.week ? '选择周视图日期' : '选择日视图日期',
    );
    if (picked != null && mounted) {
      setState(
        () => _focusedDate = DateTime(picked.year, picked.month, picked.day),
      );
      _refreshCumulativeBalance();
    }
  }

  void _shiftFocusedPeriod(int delta) {
    final next = _view == _FinanceOverviewView.week
        ? financeCalendarDayOffset(_focusedDate, delta * 7)
        : financeCalendarDayOffset(_focusedDate, delta);
    setState(() => _focusedDate = _clampToSelectedMonth(next));
    _refreshCumulativeBalance();
  }

  DateTime _clampToSelectedMonth(DateTime value) {
    final firstDay = DateTime(month.year, month.month);
    final nextMonth = DateTime(month.year, month.month + 1);
    if (value.isBefore(firstDay)) return firstDay;
    if (!value.isBefore(nextMonth)) {
      return DateTime(month.year, month.month + 1, 0);
    }
    return DateTime(value.year, value.month, value.day);
  }

  bool _canShiftFocusedPeriod(int delta) {
    if (_view == _FinanceOverviewView.month) {
      final nextMonth = DateTime(month.year, month.month + delta);
      final firstAllowedMonth = DateTime(2000);
      final lastAllowedDate = clock().add(const Duration(days: 3650));
      final lastAllowedMonth = DateTime(
        lastAllowedDate.year,
        lastAllowedDate.month,
      );
      return !nextMonth.isBefore(firstAllowedMonth) &&
          !nextMonth.isAfter(lastAllowedMonth);
    }
    final days = _view == _FinanceOverviewView.week ? delta * 7 : delta;
    final next = _clampToSelectedMonth(
      financeCalendarDayOffset(_focusedDate, days),
    );
    if (_view == _FinanceOverviewView.week) {
      return dateKey(_startOfWeek(next)) != dateKey(_startOfWeek(_focusedDate));
    }
    return dateKey(next) != dateKey(_focusedDate);
  }

  DateTime get _cumulativeBalanceAsOf {
    final now = clock();
    final range = _periodRange;
    if (range.from.isAfter(now)) return now;
    if (!range.to.isAfter(now)) {
      return range.to.subtract(const Duration(milliseconds: 1));
    }
    return now;
  }

  void _refreshCumulativeBalance() {
    final asOf = _cumulativeBalanceAsOf;
    final balance = FinanceRepository.cumulativeBalanceAt(
      events: widget.cumulativeBalanceEvents,
      asOfAt: asOf.millisecondsSinceEpoch,
      openingBalanceMinor: widget.openingBalanceMinor,
      openingBalanceStartDate: widget.openingBalanceStartDate,
    );
    if (!mounted) return;
    setState(() => _cumulativeBalanceMinor = balance);
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
              period.isPlanned ? '计划净支出' : '净支出',
              style: TextStyle(color: colorScheme.onPrimaryContainer),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: _buildSummaryMetric(
                    context,
                    label: period.isPlanned ? '计划收入' : '收入',
                    value: formatFinanceAmount(period.summary.incomeMinor),
                    color: colorScheme.onPrimaryContainer,
                  ),
                ),
                Expanded(
                  child: _buildSummaryMetric(
                    context,
                    label: period.isPlanned ? '计划总支出' : '总支出',
                    value: formatFinanceAmount(period.summary.expenseMinor),
                    color: colorScheme.onPrimaryContainer,
                  ),
                ),
                Expanded(
                  child: _buildSummaryMetric(
                    context,
                    label: period.isPlanned ? '计划结余' : '本期结余',
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
    final category = entry.categoryUuid == null
        ? null
        : categories[entry.categoryUuid];
    final categoryName = _categoryDisplayName(entry.categoryUuid);
    final categoryLabel = category == null
        ? categoryName
        : '${category.isArchived ? '已归档 ' : ''}$categoryName';
    final categoryKey = ValueKey(
      'finance-overview-category-${entry.categoryUuid ?? 'uncategorized'}',
    );
    final sourceKey = _categorySourceKeys.putIfAbsent(
      entry.categoryUuid ?? 'uncategorized',
      GlobalKey.new,
    );
    return Semantics(
      key: categoryKey,
      button: true,
      label: '查看$categoryLabel支出详情',
      child: InkWell(
        key: sourceKey,
        borderRadius: BorderRadius.circular(12),
        onTap: () => _openCategoryDetail(entry, period, sourceKey),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
          child: Row(
            children: [
              SizedBox(
                width: 105,
                child: Text(
                  category == null
                      ? categoryLabel
                      : '${category.icon} $categoryLabel',
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

  Widget _buildCategoryShareCard(
    BuildContext context,
    ColorScheme colorScheme,
    List<_FinanceCategoryTotal> categoryTotals,
    _FinanceOverviewPeriod period,
  ) {
    final total = categoryTotals.fold<int>(
      0,
      (sum, entry) => sum + entry.value,
    );
    if (total <= 0) {
      return _buildEmptyCard(
        context,
        icon: Icons.pie_chart_outline,
        message: period.isPlanned ? '暂无计划支出占比' : '暂无消费占比数据',
        nested: true,
      );
    }

    final slices = <_FinancePieSlice>[
      for (var index = 0; index < categoryTotals.length; index++)
        _FinancePieSlice(
          value: categoryTotals[index].value,
          color: _categoryShareColor(categoryTotals[index], index, colorScheme),
        ),
    ];
    final semanticSummary = [
      for (var index = 0; index < categoryTotals.length; index++)
        '${_categoryShareLabel(categoryTotals[index])} '
            '${(categoryTotals[index].value / total * 100).toStringAsFixed(1)}%',
    ].join('、');

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Semantics(
              label: period.isPlanned
                  ? '计划支出占比：$semanticSummary'
                  : '各类别支出占比：$semanticSummary',
              child: SizedBox(
                height: 176,
                child: Center(
                  child: CustomPaint(
                    size: const Size.square(168),
                    painter: _FinancePiePainter(
                      slices: slices,
                      total: total,
                      separatorColor: colorScheme.surface,
                    ),
                  ),
                ),
              ),
            ),
            const Divider(height: 24),
            for (var index = 0; index < categoryTotals.length; index++)
              _buildCategoryShareLegendEntry(
                context,
                categoryTotals[index],
                color: slices[index].color,
                total: total,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildCategoryShareLegendEntry(
    BuildContext context,
    _FinanceCategoryTotal entry, {
    required Color color,
    required int total,
  }) {
    final category = entry.categoryUuid == null
        ? null
        : categories[entry.categoryUuid];
    final percentage = (entry.value / total * 100).toStringAsFixed(1);
    final label = _categoryShareLabel(entry);
    final colorScheme = Theme.of(context).colorScheme;
    return Semantics(
      label: '$label，支出${formatFinanceAmount(entry.value)}，占$percentage%',
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 8),
            if (category != null) ...[
              Text(category.icon),
              const SizedBox(width: 6),
            ],
            Expanded(
              child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '$percentage%',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                Text(
                  formatFinanceAmount(entry.value),
                  style: TextStyle(
                    color: colorScheme.onSurfaceVariant,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _categoryShareLabel(_FinanceCategoryTotal entry) {
    return _categoryDisplayName(entry.categoryUuid);
  }

  Color _categoryShareColor(
    _FinanceCategoryTotal entry,
    int index,
    ColorScheme colorScheme,
  ) {
    final category = entry.categoryUuid == null
        ? null
        : categories[entry.categoryUuid];
    final customColor = category?.colorValue;
    if (customColor != null) return Color(customColor);

    final primary = HSLColor.fromColor(colorScheme.primary);
    return primary
        .withHue((primary.hue + index * 137.508) % 360)
        .withSaturation(primary.saturation.clamp(0.55, 0.85).toDouble())
        .withLightness(colorScheme.brightness == Brightness.dark ? 0.68 : 0.52)
        .toColor();
  }

  _FinanceOverviewAnalytics _overviewAnalytics(_FinanceOverviewPeriod period) {
    final cached = _cachedAnalytics;
    if (cached != null && identical(_analyticsSourcePeriod, period)) {
      return cached;
    }

    final topTotals = <String, int>{};
    final shareTotals = <String, int>{};
    final hourlyNetExpenseMinor = _view == _FinanceOverviewView.day
        ? List<int>.filled(25, 0)
        : null;
    var outflowTransactionCount = 0;

    for (final transaction in period.transactions) {
      if (transaction.isExpenseLike) outflowTransactionCount++;
      if (hourlyNetExpenseMinor != null &&
          transaction.type != FinanceTransactionType.income) {
        final hour = _financeTransactionHour(transaction) ?? 24;
        hourlyNetExpenseMinor[hour] +=
            transaction.type == FinanceTransactionType.refund
            ? -transaction.amountMinor
            : transaction.amountMinor;
      }

      final topAmount = switch (transaction.type) {
        FinanceTransactionType.expense => transaction.amountMinor,
        FinanceTransactionType.refund => -transaction.amountMinor,
        FinanceTransactionType.income => 0,
      };
      final includeInShares =
          transaction.type == FinanceTransactionType.expense &&
          transaction.amountMinor > 0;
      if (topAmount == 0 && !includeInShares) continue;

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

    final analytics = _FinanceOverviewAnalytics(
      topExpenseCategories: topExpenseCategories,
      categoryExpenseShares: categoryExpenseShares,
      outflowTransactionCount: outflowTransactionCount,
      hourlyNetExpenseMinor: hourlyNetExpenseMinor,
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
    GlobalKey sourceKey,
  ) async {
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

  Widget _buildInsightCard(
    BuildContext context,
    ColorScheme colorScheme,
    _FinanceOverviewPeriod period,
    int outflowTransactionCount,
  ) {
    if (period.summary.transactionCount == 0) return const SizedBox.shrink();
    final average = outflowTransactionCount == 0
        ? 0
        : period.summary.netExpenseMinor ~/ outflowTransactionCount;
    return Card(
      child: ListTile(
        leading: Icon(Icons.lightbulb_outline, color: colorScheme.primary),
        title: Text(
          period.isPlanned
              ? '${period.shortTitle}计划小结'
              : '${period.shortTitle}小结',
        ),
        subtitle: Text(
          outflowTransactionCount == 0
              ? period.isPlanned
                    ? '共 ${period.summary.transactionCount} 笔待发生记录，'
                          '本期暂无计划支出或退款记录。'
                    : '共 ${period.summary.transactionCount} 笔记录，'
                          '本期暂无支出或退款记录。'
              : period.isPlanned
              ? '共 ${period.summary.transactionCount} 笔待发生记录，'
                    '计划支出/退款 $outflowTransactionCount 笔，'
                    '平均计划净支出 ${formatFinanceAmount(average)}。'
              : '共 ${period.summary.transactionCount} 笔记录，'
                    '支出/退款 $outflowTransactionCount 笔，'
                    '平均净支出 ${formatFinanceAmount(average)}。',
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

class _FinanceLedgerSearchEntry {
  const _FinanceLedgerSearchEntry({
    required this.transaction,
    required this.eventAt,
    required this.normalizedText,
  });

  final FinanceTransaction transaction;
  final int eventAt;
  final String normalizedText;
}

class _FinanceLedgerOrderEntry {
  const _FinanceLedgerOrderEntry({
    required this.transaction,
    required this.eventAt,
  });

  final FinanceTransaction transaction;
  final int eventAt;
}

typedef _FinanceLedgerFilterKey = ({
  FinanceTransactionType? type,
  String? categoryUuid,
});

class FinanceLedgerPanel extends StatefulWidget {
  final double topPadding;
  final DateTime? month;
  final DateTime Function() clock;
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
    this.month,
    this.clock = DateTime.now,
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
  final Map<String, String> _categoryDisplayNameCache = {};
  final Map<String, String> _paymentMethodDisplayNameCache = {};
  late final TextEditingController _keywordController;
  late String _localKeyword;
  FinanceTransactionType? _localFilterType;
  String? _localCategoryUuid;
  List<FinanceTransaction>? _searchSourceTransactions;
  Map<String, FinanceCategory>? _searchSourceCategories;
  Map<String, FinancePaymentMethod>? _searchSourcePaymentMethods;
  List<_FinanceLedgerSearchEntry> _searchEntries = const [];
  bool _searchEntriesBuilt = false;
  List<FinanceTransaction>? _orderedSourceTransactions;
  _FinanceLedgerFilterKey? _orderedFilterKey;
  List<_FinanceLedgerOrderEntry> _orderedEntries = const [];

  List<FinanceTransaction> get transactions => widget.transactions;
  Map<String, FinanceCategory> get categories => widget.categories;
  Map<String, FinancePaymentMethod> get paymentMethods => widget.paymentMethods;
  String get keyword => _localKeyword;
  FinanceTransactionType? get filterType => _localFilterType;
  String? get categoryUuid => _localCategoryUuid;
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
  void initState() {
    super.initState();
    _localKeyword = widget.keyword;
    _localFilterType = widget.filterType;
    _localCategoryUuid = widget.categoryUuid;
    _keywordController = TextEditingController(text: widget.keyword);
  }

  @override
  void didUpdateWidget(covariant FinanceLedgerPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_localKeyword != widget.keyword) _localKeyword = widget.keyword;
    if (_keywordController.text != widget.keyword) {
      _keywordController.value = TextEditingValue(
        text: widget.keyword,
        selection: TextSelection.collapsed(offset: widget.keyword.length),
      );
    }
    if (_localFilterType != widget.filterType) {
      _localFilterType = widget.filterType;
    }
    if (_localCategoryUuid != widget.categoryUuid) {
      _localCategoryUuid = widget.categoryUuid;
    }
  }

  @override
  void dispose() {
    _keywordController.dispose();
    super.dispose();
  }

  String _categoryDisplayName(String? categoryUuid) {
    final cacheKey = categoryUuid ?? '';
    return _categoryDisplayNameCache.putIfAbsent(
      cacheKey,
      () =>
          financeCategoryReferenceDisplayName(categoryUuid, categories.values),
    );
  }

  String _paymentMethodDisplayName(FinancePaymentMethod paymentMethod) {
    return _paymentMethodDisplayNameCache.putIfAbsent(
      paymentMethod.uuid,
      () =>
          financePaymentMethodDisplayName(paymentMethod, paymentMethods.values),
    );
  }

  void _syncSearchInputs() {
    final transactionsChanged =
        !identical(_searchSourceTransactions, transactions);
    if (!transactionsChanged &&
        identical(_searchSourceCategories, categories) &&
        identical(_searchSourcePaymentMethods, paymentMethods)) {
      return;
    }

    _searchSourceTransactions = transactions;
    _searchSourceCategories = categories;
    _searchSourcePaymentMethods = paymentMethods;
    if (transactionsChanged) {
      _orderedSourceTransactions = null;
      _orderedFilterKey = null;
      _orderedEntries = const [];
    }
    _categoryDisplayNameCache.clear();
    _paymentMethodDisplayNameCache.clear();
    _searchEntries = const [];
    _searchEntriesBuilt = false;
  }

  List<_FinanceLedgerOrderEntry> _ensureOrderedEntries({
    required FinanceTransactionType? filterType,
    required String? categoryUuid,
  }) {
    _syncSearchInputs();
    final filterKey = (type: filterType, categoryUuid: categoryUuid);
    if (identical(_orderedSourceTransactions, transactions) &&
        _orderedFilterKey == filterKey) {
      return _orderedEntries;
    }

    final entries = <_FinanceLedgerOrderEntry>[];
    for (final transaction in transactions) {
      if (filterType != null && transaction.type != filterType) continue;
      if (categoryUuid != null) {
        final matchesCategory =
            categoryUuid == financeUncategorizedCategoryFilterUuid
            ? transaction.categoryUuid == null ||
                  transaction.categoryUuid!.trim().isEmpty
            : transaction.categoryUuid == categoryUuid;
        if (!matchesCategory) continue;
      }
      entries.add(
        _FinanceLedgerOrderEntry(
          transaction: transaction,
          eventAt: transaction.balanceEventAt(),
        ),
      );
    }
    entries.sort((a, b) {
      final dateComparison = b.transaction.transactionDate.compareTo(
        a.transaction.transactionDate,
      );
      if (dateComparison != 0) return dateComparison;
      final eventComparison = b.eventAt.compareTo(a.eventAt);
      if (eventComparison != 0) return eventComparison;
      final updatedComparison = b.transaction.updatedAt.compareTo(
        a.transaction.updatedAt,
      );
      if (updatedComparison != 0) return updatedComparison;
      return b.transaction.uuid.compareTo(a.transaction.uuid);
    });
    _orderedSourceTransactions = transactions;
    _orderedFilterKey = filterKey;
    _searchEntries = const [];
    _searchEntriesBuilt = false;
    return _orderedEntries = entries;
  }

  void _ensureSearchEntries(List<_FinanceLedgerOrderEntry> orderedEntries) {
    if (_searchEntriesBuilt) return;

    final entries = [
      for (final orderedEntry in orderedEntries)
        _FinanceLedgerSearchEntry(
          transaction: orderedEntry.transaction,
          eventAt: orderedEntry.eventAt,
          normalizedText: _searchableTextFor(orderedEntry.transaction),
        ),
    ];
    _searchEntries = entries;
    _searchEntriesBuilt = true;
  }

  String _searchableTextFor(FinanceTransaction transaction) {
    final category = categories[transaction.categoryUuid];
    final payment = paymentMethods[transaction.paymentMethodUuid];
    final paymentName = payment == null
        ? null
        : _paymentMethodDisplayName(payment);
    final hasPaymentMethodUuid =
        transaction.paymentMethodUuid?.trim().isNotEmpty == true;
    final unknownPaymentLabel = hasPaymentMethodUuid
        ? switch (transaction.type) {
            FinanceTransactionType.expense => '已删除或未知付款方式',
            FinanceTransactionType.income => '已删除或未知到账账户',
            FinanceTransactionType.refund => '已删除或未知退款到账账户',
          }
        : null;

    return [
      transaction.merchant,
      transaction.note,
      _categoryDisplayName(transaction.categoryUuid),
      payment?.name,
      paymentName,
      if (category?.isArchived == true || payment?.isArchived == true) '已归档',
      unknownPaymentLabel,
      if (hasPaymentMethodUuid) '已删除或未知付款方式',
    ].whereType<String>().join(' ').toLowerCase();
  }

  void _updateKeyword(String value) {
    if (_localKeyword != value) {
      setState(() => _localKeyword = value);
    }
    onKeywordChanged(value);
  }

  void _updateFilterType(FinanceTransactionType? value) {
    if (_localFilterType != value) {
      setState(() => _localFilterType = value);
    }
    onFilterChanged(value);
  }

  void _updateCategoryFilter(String? value) {
    if (_localCategoryUuid != value) {
      setState(() => _localCategoryUuid = value);
    }
    onCategoryChanged?.call(value);
  }

  @override
  Widget build(BuildContext context) {
    final query = keyword.trim().toLowerCase();
    final hasKeyword = query.isNotEmpty;
    final orderedEntries = _ensureOrderedEntries(
      filterType: filterType,
      categoryUuid: categoryUuid,
    );
    if (hasKeyword) _ensureSearchEntries(orderedEntries);

    final List<_FinanceLedgerOrderEntry> filtered;
    if (!hasKeyword) {
      filtered = orderedEntries;
    } else {
      filtered = <_FinanceLedgerOrderEntry>[];
      final dateMatches = <String, bool>{};

      for (final entry in _searchEntries) {
        final transaction = entry.transaction;
        final matchesDate = dateMatches.putIfAbsent(
          transaction.transactionDate,
          () => _matchesFinanceLedgerDate(transaction.transactionDate, query),
        );
        if (entry.normalizedText.contains(query) || matchesDate) {
          filtered.add(
            _FinanceLedgerOrderEntry(
              transaction: transaction,
              eventAt: entry.eventAt,
            ),
          );
        }
      }
    }
    final nowAt = widget.clock().millisecondsSinceEpoch;
    final dayGroups = _groupFinanceTransactionsByDay(filtered, asOfAt: nowAt);
    final ledgerRows = <_FinanceLedgerRow>[];
    for (var groupIndex = 0; groupIndex < dayGroups.length; groupIndex++) {
      final group = dayGroups[groupIndex];
      ledgerRows.add(_FinanceLedgerRow.header(group));
      for (
        var transactionIndex = 0;
        transactionIndex < group.transactions.length;
        transactionIndex++
      ) {
        ledgerRows.add(
          _FinanceLedgerRow.transaction(group.transactions[transactionIndex]),
        );
        if (transactionIndex + 1 < group.transactions.length ||
            groupIndex + 1 < dayGroups.length) {
          ledgerRows.add(const _FinanceLedgerRow.spacer());
        }
      }
    }
    final keyedRowIndices = <Key, int>{};
    for (var rowIndex = 0; rowIndex < ledgerRows.length; rowIndex++) {
      final transaction = ledgerRows[rowIndex].transaction;
      if (transaction == null) continue;
      final cardKey = _cardKeys[transaction.uuid];
      if (cardKey != null) keyedRowIndices[cardKey] = rowIndex;
    }
    final bottomPadding = financeBottomContentPaddingFor(context);

    return Column(
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(16, widget.topPadding + 12, 16, 4),
          child: TextField(
            controller: _keywordController,
            onChanged: _updateKeyword,
            decoration: InputDecoration(
              hintText: '搜索商家、备注、分类、关联账户或日期',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: keyword.isEmpty
                  ? null
                  : IconButton(
                      onPressed: () => _updateKeyword(''),
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
              : ListView.builder(
                  padding: EdgeInsets.fromLTRB(16, 4, 16, bottomPadding),
                  itemCount: ledgerRows.length,
                  findChildIndexCallback: (key) => keyedRowIndices[key],
                  itemBuilder: (context, index) {
                    final row = ledgerRows[index];
                    if (row.isSpacer) return const SizedBox(height: 8);
                    final group = row.group;
                    if (group != null) return _buildDayHeader(context, group);
                    return _buildTransactionTile(
                      context,
                      row.transaction!,
                      nowAt,
                    );
                  },
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
        onSelected: (_) => _updateFilterType(type),
      ),
    );
  }

  Widget _buildCategoryFilterChip(BuildContext context) {
    final isUncategorized =
        categoryUuid == financeUncategorizedCategoryFilterUuid;
    final category = isUncategorized ? null : categories[categoryUuid];
    final label = isUncategorized
        ? '分类 · 未分类'
        : categoryUuid == null
        ? '分类筛选'
        : '分类 · ${_categoryDisplayName(categoryUuid)}';
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        key: const ValueKey('finance-ledger-category-filter'),
        avatar: category == null ? null : Text(category.icon),
        label: Text(label),
        selected: true,
        onSelected: onCategoryChanged == null
            ? null
            : (_) => _updateCategoryFilter(null),
      ),
    );
  }

  Widget _buildDayHeader(BuildContext context, _FinanceDayGroup group) {
    final colorScheme = Theme.of(context).colorScheme;
    final hasExpenseFlow = group.expenseMinor > 0 || group.refundMinor > 0;
    final hasPlannedExpenseFlow =
        group.plannedExpenseMinor > 0 || group.plannedRefundMinor > 0;
    final amountLabels = <String>[
      if (hasExpenseFlow) '净支出 ${formatFinanceAmount(group.netExpenseMinor)}',
      if (hasPlannedExpenseFlow)
        '计划净支出 ${formatFinanceAmount(group.plannedNetExpenseMinor)}',
      if (group.incomeMinor > 0) '收入 ${formatFinanceAmount(group.incomeMinor)}',
      if (group.plannedIncomeMinor > 0)
        '计划收入 ${formatFinanceAmount(group.plannedIncomeMinor)}',
    ];
    if (amountLabels.isEmpty) {
      amountLabels.add('${group.transactions.length} 笔');
    }
    Color labelColor(String label) {
      if (label.contains('收入')) return colorScheme.primary;
      final netExpenseMinor = label.startsWith('计划净支出')
          ? group.plannedNetExpenseMinor
          : group.netExpenseMinor;
      return netExpenseMinor > 0
          ? colorScheme.error
          : colorScheme.onSurfaceVariant;
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
                  style: Theme.of(context).textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700),
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
                      color: labelColor(label),
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
    int asOfAt,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    final category = categories[transaction.categoryUuid];
    final payment = paymentMethods[transaction.paymentMethodUuid];
    final paymentName = payment == null
        ? null
        : _paymentMethodDisplayName(payment);
    final categoryName = _categoryDisplayName(transaction.categoryUuid);
    final title = transaction.merchant?.isNotEmpty == true
        ? transaction.merchant!
        : category == null &&
              (transaction.categoryUuid == null ||
                  transaction.categoryUuid!.trim().isEmpty)
        ? transaction.type.label
        : categoryName;
    final subtitleParts = <String>[
      if (transaction.balanceEventAt() > asOfAt) '待发生',
      category == null
          ? categoryName
          : '${category.icon} $categoryName${category.isArchived ? '（已归档）' : ''}',
      if (payment != null)
        '${payment.icon} $paymentName${payment.isArchived ? '（已归档）' : ''}'
      else if (transaction.paymentMethodUuid?.trim().isNotEmpty == true)
        switch (transaction.type) {
          FinanceTransactionType.expense => '已删除或未知付款方式',
          FinanceTransactionType.income => '已删除或未知到账账户',
          FinanceTransactionType.refund => '已删除或未知退款到账账户',
        },
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
        trailing: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: (MediaQuery.sizeOf(context).width - 120).clamp(
              0.0,
              double.infinity,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  formatSignedFinanceAmount(
                    transaction.amountMinor,
                    transaction.type,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: amountColor,
                    fontWeight: FontWeight.w700,
                  ),
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
                    const PopupMenuItem(value: 'refund', child: Text('退款')),
                  const PopupMenuItem(value: 'edit', child: Text('编辑')),
                  const PopupMenuItem(value: 'delete', child: Text('删除')),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final now = widget.clock();
    final selectedMonth = widget.month ?? now;
    final monthLabel =
        selectedMonth.year == now.year && selectedMonth.month == now.month
        ? '本月'
        : '${selectedMonth.year}年${selectedMonth.month}月';
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.receipt_long_outlined,
            size: 48,
            color: colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 12),
          Text(
            keyword.trim().isEmpty && filterType == null && categoryUuid == null
                ? '$monthLabel还没有账单'
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
  final bool isPlanned;

  const _FinanceOverviewPeriod({
    required this.from,
    required this.to,
    required this.title,
    required this.shortTitle,
    required this.summary,
    required this.transactions,
    required this.isPlanned,
  });
}

class _FinanceOverviewAnalytics {
  final List<_FinanceCategoryTotal> topExpenseCategories;
  final List<_FinanceCategoryTotal> categoryExpenseShares;
  final int outflowTransactionCount;
  final List<int>? hourlyNetExpenseMinor;

  const _FinanceOverviewAnalytics({
    required this.topExpenseCategories,
    required this.categoryExpenseShares,
    required this.outflowTransactionCount,
    required this.hourlyNetExpenseMinor,
  });

  bool get hasOutflowTransactions => outflowTransactionCount > 0;
}

class _FinanceCategoryTotal {
  final String? categoryUuid;
  final int value;

  const _FinanceCategoryTotal({
    required this.categoryUuid,
    required this.value,
  });
}

class _FinancePieSlice {
  final int value;
  final Color color;

  const _FinancePieSlice({required this.value, required this.color});
}

class _FinancePiePainter extends CustomPainter {
  final List<_FinancePieSlice> slices;
  final int total;
  final Color separatorColor;

  const _FinancePiePainter({
    required this.slices,
    required this.total,
    required this.separatorColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (total <= 0 || slices.isEmpty) return;

    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 - 1;
    final bounds = Rect.fromCircle(center: center, radius: radius);
    final fillPaint = Paint()
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;
    final separatorPaint = Paint()
      ..color = separatorColor
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..isAntiAlias = true;
    var startAngle = -math.pi / 2;

    for (final slice in slices) {
      final sweepAngle = math.pi * 2 * slice.value / total;
      fillPaint.color = slice.color;
      canvas.drawArc(bounds, startAngle, sweepAngle, true, fillPaint);
      if (slices.length > 1) {
        final edge = Offset(
          center.dx + radius * math.cos(startAngle),
          center.dy + radius * math.sin(startAngle),
        );
        canvas.drawLine(center, edge, separatorPaint);
      }
      startAngle += sweepAngle;
    }

    canvas.drawCircle(center, radius, separatorPaint..strokeWidth = 1);
  }

  @override
  bool shouldRepaint(covariant _FinancePiePainter oldDelegate) {
    if (oldDelegate.total != total ||
        oldDelegate.separatorColor != separatorColor ||
        oldDelegate.slices.length != slices.length) {
      return true;
    }
    for (var index = 0; index < slices.length; index++) {
      if (oldDelegate.slices[index].value != slices[index].value ||
          oldDelegate.slices[index].color != slices[index].color) {
        return true;
      }
    }
    return false;
  }
}

String _formatFinanceDateRange(DateTime from, DateTime to) {
  final lastDay = financeCalendarDayOffset(to, -1);
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
  final int plannedExpenseMinor;
  final int plannedRefundMinor;
  final int plannedIncomeMinor;

  const _FinanceDayGroup({
    required this.date,
    required this.transactions,
    required this.expenseMinor,
    required this.refundMinor,
    required this.incomeMinor,
    required this.plannedExpenseMinor,
    required this.plannedRefundMinor,
    required this.plannedIncomeMinor,
  });

  int get netExpenseMinor => expenseMinor - refundMinor;
  int get plannedNetExpenseMinor => plannedExpenseMinor - plannedRefundMinor;
}

class _FinanceLedgerRow {
  final _FinanceDayGroup? group;
  final FinanceTransaction? transaction;
  final bool isSpacer;

  const _FinanceLedgerRow.header(this.group)
    : transaction = null,
      isSpacer = false;

  const _FinanceLedgerRow.transaction(this.transaction)
    : group = null,
      isSpacer = false;

  const _FinanceLedgerRow.spacer()
    : group = null,
      transaction = null,
      isSpacer = true;
}

List<_FinanceDayGroup> _groupFinanceTransactionsByDay(
  Iterable<_FinanceLedgerOrderEntry> entries, {
  required int asOfAt,
}) {
  final grouped = <String, List<FinanceTransaction>>{};
  final totalsByDate = <String, List<int>>{};
  for (final entry in entries) {
    final transaction = entry.transaction;
    final date = transaction.transactionDate;
    final eventAt = entry.eventAt;
    grouped.putIfAbsent(date, () => []).add(transaction);

    final totals = totalsByDate.putIfAbsent(date, () => List<int>.filled(6, 0));
    final metricOffset = eventAt > asOfAt ? 3 : 0;
    final metricIndex = switch (transaction.type) {
      FinanceTransactionType.expense => metricOffset,
      FinanceTransactionType.refund => metricOffset + 1,
      FinanceTransactionType.income => metricOffset + 2,
    };
    totals[metricIndex] += transaction.amountMinor;
  }

  final result = <_FinanceDayGroup>[];
  for (final entry in grouped.entries) {
    final date = entry.key;
    final totals = totalsByDate[date]!;
    result.add(
      _FinanceDayGroup(
        date: date,
        transactions: entry.value,
        expenseMinor: totals[0],
        refundMinor: totals[1],
        incomeMinor: totals[2],
        plannedExpenseMinor: totals[3],
        plannedRefundMinor: totals[4],
        plannedIncomeMinor: totals[5],
      ),
    );
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

final _financeFullChineseDatePattern = RegExp(
  r'^(\d{4})年(\d{1,2})月(\d{1,2})日?$',
);
final _financeChineseYearMonthPattern = RegExp(r'^(\d{4})年(\d{1,2})月$');
final _financeChineseMonthDayPattern = RegExp(r'^(\d{1,2})月(\d{1,2})日?$');
final _financeChineseMonthPattern = RegExp(r'^(\d{1,2})月$');
final _financeSlashMonthDayPattern = RegExp(r'^(\d{1,2})/(\d{1,2})$');

bool _matchesFinanceLedgerDate(String value, String query) {
  if (value.contains(query)) return true;
  if (!isFinanceDateKey(value)) return false;
  final date = DateTime.parse(value);

  final fullChineseDate = _financeFullChineseDatePattern.firstMatch(query);
  if (fullChineseDate != null) {
    return int.parse(fullChineseDate.group(1)!) == date.year &&
        int.parse(fullChineseDate.group(2)!) == date.month &&
        int.parse(fullChineseDate.group(3)!) == date.day;
  }
  final chineseYearMonth = _financeChineseYearMonthPattern.firstMatch(query);
  if (chineseYearMonth != null) {
    return int.parse(chineseYearMonth.group(1)!) == date.year &&
        int.parse(chineseYearMonth.group(2)!) == date.month;
  }
  final chineseMonthDay = _financeChineseMonthDayPattern.firstMatch(query);
  if (chineseMonthDay != null) {
    return int.parse(chineseMonthDay.group(1)!) == date.month &&
        int.parse(chineseMonthDay.group(2)!) == date.day;
  }
  final chineseMonth = _financeChineseMonthPattern.firstMatch(query);
  if (chineseMonth != null) {
    return int.parse(chineseMonth.group(1)!) == date.month;
  }
  final slashMonthDay = _financeSlashMonthDayPattern.firstMatch(query);
  if (slashMonthDay != null) {
    return int.parse(slashMonthDay.group(1)!) == date.month &&
        int.parse(slashMonthDay.group(2)!) == date.day;
  }
  return _formatFinanceDayLabel(value).toLowerCase().contains(query);
}
