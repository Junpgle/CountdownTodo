import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../../../widgets/floating_bottom_bar.dart';
import '../../../utils/page_transitions.dart';
import '../models/finance_models.dart';
import '../services/finance_repository.dart';
import '../screens/finance_category_detail_screen.dart';
import 'finance_calendar_panel.dart';
import 'finance_glass_segment_selector.dart';

import '../../../utils/app_dialogs.dart';

/// Leaves enough scrollable room for the shared navigation bar and its bottom
/// margin, so the final finance card can clear the bar completely.
double financeBottomContentPaddingFor(BuildContext context) {
  return floatingBottomNavigationContentPaddingFor(context);
}

enum _FinanceOverviewView { month, week, day }

enum _FinanceOverviewMode { report, calendar }

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

typedef FinanceCategoryRangeSelectionCallback = Future<void> Function(
  String categoryUuid,
  GlobalKey sourceKey,
  List<FinanceTransaction> periodTransactions,
  DateTimeRange periodRange,
);

typedef FinanceMonthLedgerCallback = Future<void> Function(
  DateTime month,
  GlobalKey sourceKey,
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
  final Future<void> Function(DateTime date, GlobalKey sourceKey)? onAddForDate;
  final VoidCallback? onEditOpeningBalance;
  final GlobalKey addActionKey;
  final bool categoryTapOpensLedger;
  final Future<void> Function() onRefresh;
  final ValueChanged<DateTime>? onMonthChanged;
  final FinanceCategorySelectionCallback? onCategorySelected;
  final FinanceCategoryRangeSelectionCallback? onCategorySelectedWithRange;
  final FinanceMonthLedgerCallback? onOpenMonthLedger;
  final Future<void> Function(
    FinanceTransaction transaction,
    GlobalKey sourceKey,
  )?
  onOpenTransaction;

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
    this.onAddForDate,
    this.onEditOpeningBalance,
    required this.addActionKey,
    this.categoryTapOpensLedger = true,
    required this.onRefresh,
    this.onMonthChanged,
    this.onCategorySelected,
    this.onCategorySelectedWithRange,
    this.onOpenMonthLedger,
    this.onOpenTransaction,
  });

  @override
  State<FinanceOverviewPanel> createState() => _FinanceOverviewPanelState();
}

class _FinanceOverviewPanelState extends State<FinanceOverviewPanel> {
  _FinanceOverviewMode _mode = _FinanceOverviewMode.report;
  _FinanceOverviewView _view = _FinanceOverviewView.month;
  late DateTime _focusedDate;
  int? _cumulativeBalanceMinor;
  String? _selectedCumulativeTrendMonthKey;
  final GlobalKey _selectedTrendLedgerActionKey = GlobalKey(
    debugLabel: 'finance-cumulative-trend-open-ledger',
  );
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
  FinanceCategoryRangeSelectionCallback? get onCategorySelectedWithRange =>
      widget.onCategorySelectedWithRange;

  String _categoryDisplayName(String? categoryUuid) {
    if (!identical(_categoryDisplayNamesSource, categories)) {
      _categoryDisplayNamesSource = categories;
      _categoryDisplayNames.clear();
    }
    return _categoryDisplayNames.putIfAbsent(
      categoryUuid ?? '',
      () =>
          financeCategoryReferenceDisplayName(categoryUuid, categories.values),
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
      _selectedCumulativeTrendMonthKey = null;
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
    if (_mode == _FinanceOverviewMode.calendar) {
      return FinanceCalendarPanel(
        topPadding: widget.topPadding,
        clock: clock,
        month: month,
        transactions: transactions,
        cumulativeBalanceEvents: widget.cumulativeBalanceEvents,
        openingBalanceMinor: widget.openingBalanceMinor,
        openingBalanceStartDate: widget.openingBalanceStartDate,
        categories: categories,
        onRefresh: onRefresh,
        onMonthChanged: (value) => onMonthChanged?.call(value),
        onShowReport: () => setState(() => _mode = _FinanceOverviewMode.report),
        onAdd: widget.onAddForDate == null
            ? null
            : (date, sourceKey) => widget.onAddForDate!(date, sourceKey),
        onOpenTransaction: widget.onOpenTransaction,
      );
    }
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
          _buildOverviewModeSelector(),
          const SizedBox(height: 10),
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
          _buildCumulativeBalanceTrendCard(context, colorScheme),
          const SizedBox(height: 12),
          _buildCumulativeBalanceCard(context, colorScheme),
        ],
      ),
    );
  }

  Widget _buildOverviewModeSelector() {
    return FinanceGlassSegmentSelector<_FinanceOverviewMode>(
      keyPrefix: 'finance-overview-mode-selector',
      segments: const [
        FinanceGlassSegment(
          id: 'report',
          label: '报表',
          value: _FinanceOverviewMode.report,
        ),
        FinanceGlassSegment(
          id: 'calendar',
          label: '日历',
          value: _FinanceOverviewMode.calendar,
        ),
      ],
      selected: _mode,
      onSelected: (value) => setState(() => _mode = value),
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
                        child: CustomPaint(
                          size: Size(constraints.maxWidth, 148),
                          painter: _FinanceCumulativeBalanceTrendPainter(
                            points: points,
                            selectedIndex: selectedIndex,
                            colorScheme: colorScheme,
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
    setState(() {
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
  String categoryKey,
  String? rangeStartKey,
  String? rangeEndKey,
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
  final Set<String>? categoryUuids;
  final DateTimeRange? dateRange;
  final bool isLoading;
  final String? queryError;
  final VoidCallback? onRetry;
  final void Function(FinanceTransaction, GlobalKey) onOpenDetail;
  final ValueChanged<String> onKeywordChanged;
  final ValueChanged<FinanceTransactionType?> onFilterChanged;
  final ValueChanged<String?>? onCategoryChanged;
  final ValueChanged<Set<String>>? onCategoryUuidsChanged;
  final ValueChanged<DateTimeRange?>? onDateRangeChanged;
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
    this.categoryUuids,
    this.dateRange,
    this.isLoading = false,
    this.queryError,
    this.onRetry,
    required this.onOpenDetail,
    required this.onKeywordChanged,
    required this.onFilterChanged,
    this.onCategoryChanged,
    this.onCategoryUuidsChanged,
    this.onDateRangeChanged,
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
  Set<String> _localCategoryUuids = <String>{};
  DateTimeRange? _localDateRange;
  final Set<String> _selectedTransactionUuids = <String>{};
  bool _selectionMode = false;
  bool _hasCommittedSelection = false;
  bool _summaryExpanded = true;
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
  Set<String> get categoryUuids => _localCategoryUuids;
  DateTimeRange? get dateRange =>
      widget.onDateRangeChanged == null ? _localDateRange : widget.dateRange;
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
    _localCategoryUuids =
        widget.categoryUuids?.toSet() ??
        (widget.categoryUuid == null
            ? <String>{}
            : <String>{widget.categoryUuid!});
    _localDateRange = widget.dateRange;
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
    if (widget.categoryUuids != null) {
      _localCategoryUuids = widget.categoryUuids!.toSet();
    } else if (widget.categoryUuids == null &&
        _localCategoryUuids.length == 1 &&
        !_localCategoryUuids.contains(widget.categoryUuid)) {
      _localCategoryUuids = widget.categoryUuid == null
          ? <String>{}
          : <String>{widget.categoryUuid!};
    }
    if (widget.onDateRangeChanged != null) {
      _localDateRange = widget.dateRange;
    }
    if (oldWidget.dateRange != widget.dateRange) {
      _selectedTransactionUuids.clear();
      _hasCommittedSelection = false;
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
    final transactionsChanged = !identical(
      _searchSourceTransactions,
      transactions,
    );
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
    required Set<String> categoryUuids,
  }) {
    _syncSearchInputs();
    final selectedRange = dateRange;
    final filterKey = (
      type: filterType,
      categoryKey: (categoryUuids.toList()..sort()).join('\u0000'),
      rangeStartKey: selectedRange == null
          ? null
          : dateKey(selectedRange.start),
      rangeEndKey: selectedRange == null ? null : dateKey(selectedRange.end),
    );
    if (identical(_orderedSourceTransactions, transactions) &&
        _orderedFilterKey == filterKey) {
      return _orderedEntries;
    }

    final entries = <_FinanceLedgerOrderEntry>[];
    for (final transaction in transactions) {
      if (filterType != null && transaction.type != filterType) continue;
      if (!_matchesSelectedCategories(transaction)) continue;
      if (selectedRange != null) {
        final transactionDate = transaction.transactionDate;
        if (transactionDate.compareTo(dateKey(selectedRange.start)) < 0 ||
            transactionDate.compareTo(dateKey(selectedRange.end)) > 0) {
          continue;
        }
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
    _selectedTransactionUuids.clear();
    _hasCommittedSelection = false;
    if (_localKeyword != value) {
      setState(() => _localKeyword = value);
    }
    onKeywordChanged(value);
  }

  void _updateFilterType(FinanceTransactionType? value) {
    _selectedTransactionUuids.clear();
    _hasCommittedSelection = false;
    if (_localFilterType != value) {
      setState(() => _localFilterType = value);
    }
    onFilterChanged(value);
  }

  void _updateCategoryFilters(Set<String> values) {
    _selectedTransactionUuids.clear();
    _hasCommittedSelection = false;
    setState(() => _localCategoryUuids = values);
    widget.onCategoryUuidsChanged?.call(values);
    if (widget.onCategoryUuidsChanged == null) {
      onCategoryChanged?.call(values.length == 1 ? values.first : null);
    }
  }

  Future<void> _pickDateRange() async {
    final now = widget.clock();
    final month = widget.month ?? now;
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      initialDateRange:
          dateRange ??
          DateTimeRange(
            start: DateTime(month.year, month.month),
            end: DateTime(month.year, month.month + 1, 0),
          ),
      helpText: '选择统计日期范围',
      saveText: '应用',
    );
    if (picked == null || !mounted) return;
    _selectedTransactionUuids.clear();
    _hasCommittedSelection = false;
    if (widget.onDateRangeChanged == null) {
      setState(() => _localDateRange = picked);
    } else {
      widget.onDateRangeChanged!(picked);
    }
  }

  void _resetDateRange() {
    _selectedTransactionUuids.clear();
    _hasCommittedSelection = false;
    if (widget.onDateRangeChanged == null) {
      setState(() => _localDateRange = null);
    } else {
      widget.onDateRangeChanged!(null);
    }
  }

  Future<void> _pickCategories() async {
    final selected = await showDialog<Set<String>>(
      context: context,
      builder: (context) => _FinanceLedgerCategoryPickerDialog(
        categories: categories,
        initialSelection: categoryUuids,
        categoryCounts: widget.isLoading || widget.queryError != null
            ? null
            : _categoryCountsForPicker(),
      ),
    );
    if (selected == null || !mounted) return;
    _updateCategoryFilters(selected);
  }

  Map<String, int> _categoryCountsForPicker() {
    final counts = <String, int>{};
    final selectedRange = dateRange;
    final query = keyword.trim().toLowerCase();
    final dateMatches = <String, bool>{};

    for (final transaction in transactions) {
      if (filterType != null && transaction.type != filterType) continue;
      if (selectedRange != null) {
        final transactionDate = transaction.transactionDate;
        if (transactionDate.compareTo(dateKey(selectedRange.start)) < 0 ||
            transactionDate.compareTo(dateKey(selectedRange.end)) > 0) {
          continue;
        }
      }
      if (query.isNotEmpty) {
        final matchesText = _searchableTextFor(transaction).contains(query);
        final matchesDate = dateMatches.putIfAbsent(
          transaction.transactionDate,
          () => _matchesFinanceLedgerDate(transaction.transactionDate, query),
        );
        if (!matchesText && !matchesDate) continue;
      }

      final categoryUuid = transaction.categoryUuid?.trim();
      if (categoryUuid == null || categoryUuid.isEmpty) {
        counts.update(
          financeUncategorizedCategoryFilterUuid,
          (count) => count + 1,
          ifAbsent: () => 1,
        );
        continue;
      }

      var category = categories[categoryUuid];
      final visited = <String>{};
      while (category != null && visited.add(category.uuid)) {
        counts.update(category.uuid, (count) => count + 1, ifAbsent: () => 1);
        final parentUuid = category.parentUuid?.trim();
        if (parentUuid == null || parentUuid.isEmpty) break;
        final parent = categories[parentUuid];
        if (parent == null || parent.type != category.type) break;
        category = parent;
      }
    }

    return counts;
  }

  void _toggleSelectionMode() {
    setState(() {
      _selectionMode = !_selectionMode;
      if (_selectionMode) {
        _summaryExpanded = true;
      } else {
        _hasCommittedSelection = _selectedTransactionUuids.isNotEmpty;
      }
    });
  }

  void _clearSelection() {
    setState(() {
      _selectedTransactionUuids.clear();
      _hasCommittedSelection = false;
    });
  }

  void _toggleTransactionSelection(FinanceTransaction transaction) {
    setState(() {
      if (!_selectedTransactionUuids.add(transaction.uuid)) {
        _selectedTransactionUuids.remove(transaction.uuid);
      }
    });
  }

  void _toggleSelectAll(List<_FinanceLedgerOrderEntry> filtered) {
    final visibleUuids = filtered
        .map((entry) => entry.transaction.uuid)
        .toSet();
    setState(() {
      if (visibleUuids.isNotEmpty &&
          visibleUuids.every(_selectedTransactionUuids.contains)) {
        _selectedTransactionUuids.removeAll(visibleUuids);
      } else {
        _selectedTransactionUuids.addAll(visibleUuids);
      }
    });
  }

  bool _matchesSelectedCategories(FinanceTransaction transaction) {
    if (categoryUuids.isEmpty) return true;
    final selected = categoryUuids;
    final transactionCategoryUuid = transaction.categoryUuid?.trim();
    if (transactionCategoryUuid == null || transactionCategoryUuid.isEmpty) {
      return selected.contains(financeUncategorizedCategoryFilterUuid);
    }
    var current = categories[transactionCategoryUuid];
    final visited = <String>{};
    while (current != null && visited.add(current.uuid)) {
      if (selected.contains(current.uuid)) return true;
      final parentUuid = current.parentUuid?.trim();
      if (parentUuid == null || parentUuid.isEmpty) break;
      final parent = categories[parentUuid];
      if (parent == null || parent.type != current.type) break;
      current = parent;
    }
    return selected.contains(transactionCategoryUuid);
  }

  @override
  Widget build(BuildContext context) {
    final query = keyword.trim().toLowerCase();
    final hasKeyword = query.isNotEmpty;
    final orderedEntries = _ensureOrderedEntries(
      filterType: filterType,
      categoryUuids: categoryUuids,
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
    final screenSize = MediaQuery.sizeOf(context);
    const summaryPanelHorizontalMargin = 16.0;
    final summaryPanelWidth = math
        .min(
          540.0,
          math.max(0.0, screenSize.width - summaryPanelHorizontalMargin * 2),
        )
        .toDouble();
    final summaryPanelMaxHeight = math
        .min(260.0, math.max(140.0, screenSize.height * 0.40))
        .toDouble();
    final listBottomPadding =
        financeBottomContentPaddingFor(context) +
        (_summaryExpanded ? summaryPanelMaxHeight : 56.0) +
        16;
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
    return Stack(
      fit: StackFit.expand,
      children: [
        Column(
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
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 6,
                ),
                scrollDirection: Axis.horizontal,
                children: [
                  _buildFilterChip(context, '全部', null),
                  for (final type in FinanceTransactionType.values)
                    _buildFilterChip(context, type.label, type),
                  if (widget.onDateRangeChanged != null)
                    _buildDateRangeFilterChip(context),
                  _buildCategoryFilterChip(context),
                ],
              ),
            ),
            Expanded(
              child: widget.queryError != null
                  ? _buildQueryError(context, widget.queryError!)
                  : widget.isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : filtered.isEmpty
                  ? _buildEmptyState(context)
                  : ListView.builder(
                      padding: EdgeInsets.fromLTRB(
                        16,
                        4,
                        16,
                        listBottomPadding,
                      ),
                      itemCount: ledgerRows.length,
                      findChildIndexCallback: (key) => keyedRowIndices[key],
                      itemBuilder: (context, index) {
                        final row = ledgerRows[index];
                        if (row.isSpacer) return const SizedBox(height: 8);
                        final group = row.group;
                        if (group != null) {
                          return _buildDayHeader(
                            context,
                            group,
                            hideAmountsDuplicatedByFooter:
                                _summaryExpanded &&
                                dayGroups.length == 1 &&
                                !_selectionMode &&
                                !_hasCommittedSelection,
                          );
                        }
                        return _buildTransactionTile(
                          context,
                          row.transaction!,
                          nowAt,
                          selectionMode: _selectionMode,
                          selected: _selectedTransactionUuids.contains(
                            row.transaction!.uuid,
                          ),
                          onToggleSelection: () =>
                              _toggleTransactionSelection(row.transaction!),
                        );
                      },
                    ),
            ),
          ],
        ),
        Positioned(
          right: summaryPanelHorizontalMargin,
          bottom: financeBottomContentPaddingFor(context),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 240),
            reverseDuration: const Duration(milliseconds: 200),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            transitionBuilder: (child, animation) {
              return FadeTransition(
                opacity: animation,
                child: ScaleTransition(
                  scale: animation,
                  alignment: Alignment.bottomRight,
                  child: child,
                ),
              );
            },
            layoutBuilder: (currentChild, previousChildren) {
              return Stack(
                alignment: Alignment.bottomRight,
                children: [
                  ...previousChildren.map(
                    (child) => IgnorePointer(child: child),
                  ),
                  ?currentChild,
                ],
              );
            },
            child: _summaryExpanded
                ? SizedBox(
                    key: const ValueKey('finance-ledger-summary-panel'),
                    width: summaryPanelWidth,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight: summaryPanelMaxHeight,
                      ),
                      child: SingleChildScrollView(
                        child: _buildSummaryFooter(
                          context,
                          filtered,
                          nowAt,
                          onCollapse: () =>
                              setState(() => _summaryExpanded = false),
                        ),
                      ),
                    ),
                  )
                : FloatingActionButton.small(
                    key: const ValueKey('finance-ledger-summary-button'),
                    heroTag: null,
                    tooltip: '查看账单合计',
                    backgroundColor: Theme.of(context)
                        .colorScheme
                        .primaryContainer,
                    foregroundColor: Theme.of(context)
                        .colorScheme
                        .onPrimaryContainer,
                    elevation: 3,
                    onPressed: () => setState(() => _summaryExpanded = true),
                    child: const Icon(Icons.calculate_outlined),
                  ),
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
    final selected = categoryUuids;
    final category =
        selected.length == 1 &&
            selected.first != financeUncategorizedCategoryFilterUuid
        ? categories[selected.first]
        : null;
    final label = selected.isEmpty
        ? '分类筛选'
        : selected.length == 1 &&
              selected.first == financeUncategorizedCategoryFilterUuid
        ? '分类 · 未分类'
        : '分类 · ${selected.length} 项';
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        key: const ValueKey('finance-ledger-category-filter'),
        avatar: category == null ? null : Text(category.icon),
        label: Text(label),
        selected: selected.isNotEmpty,
        onSelected: (_) {
          if (widget.categoryUuids == null &&
              widget.categoryUuid != null &&
              widget.onCategoryUuidsChanged == null) {
            _updateCategoryFilters(<String>{});
          } else {
            _pickCategories();
          }
        },
      ),
    );
  }

  Widget _buildDateRangeFilterChip(BuildContext context) {
    final now = widget.clock();
    final month = widget.month ?? now;
    final range =
        dateRange ??
        DateTimeRange(
          start: DateTime(month.year, month.month),
          end: DateTime(month.year, month.month + 1, 0),
        );
    final isCustomRange = dateRange != null;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: InputChip(
        key: const ValueKey('finance-ledger-date-range-filter'),
        avatar: const Icon(Icons.date_range_outlined, size: 18),
        label: Text(
          '${dateKey(range.start)} – ${dateKey(range.end)}',
          maxLines: 1,
        ),
        onPressed: _pickDateRange,
        onDeleted: isCustomRange ? _resetDateRange : null,
        deleteButtonTooltipMessage: '恢复当前月',
      ),
    );
  }

  Widget _buildSummaryFooter(
    BuildContext context,
    List<_FinanceLedgerOrderEntry> filtered,
    int nowAt, {
    required VoidCallback onCollapse,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final showSelectedTotals = _selectionMode || _hasCommittedSelection;
    final selectedEntries = showSelectedTotals
        ? filtered
              .where(
                (entry) =>
                    _selectedTransactionUuids.contains(entry.transaction.uuid),
              )
              .toList(growable: false)
        : filtered;
    final totals = _FinanceLedgerTotals.fromEntries(selectedEntries, nowAt);
    final selectedCount = selectedEntries.length;
    final allVisibleSelected =
        filtered.isNotEmpty &&
        filtered.every(
          (entry) => _selectedTransactionUuids.contains(entry.transaction.uuid),
        );
    final amountLabels = <String>[
      if (totals.expenseMinor > 0)
        '支出 ${formatFinanceAmount(totals.expenseMinor)}',
      if (totals.refundMinor > 0)
        '退款 ${formatFinanceAmount(totals.refundMinor)}',
      if (totals.expenseMinor > 0 || totals.refundMinor > 0)
        '净支出 ${formatFinanceAmount(totals.netExpenseMinor)}',
      if (totals.incomeMinor > 0)
        '收入 ${formatFinanceAmount(totals.incomeMinor)}',
    ];
    final plannedLabels = <String>[
      if (totals.plannedExpenseMinor > 0)
        '计划支出 ${formatFinanceAmount(totals.plannedExpenseMinor)}',
      if (totals.plannedRefundMinor > 0)
        '计划退款 ${formatFinanceAmount(totals.plannedRefundMinor)}',
      if (totals.plannedIncomeMinor > 0)
        '计划收入 ${formatFinanceAmount(totals.plannedIncomeMinor)}',
    ];

    return Card(
      color: colorScheme.surfaceContainerHigh,
      surfaceTintColor: Colors.transparent,
      shadowColor: colorScheme.shadow.withValues(alpha: 0.16),
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: colorScheme.outlineVariant.withValues(alpha: 0.45),
        ),
      ),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 8, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(5),
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    _selectionMode
                        ? Icons.checklist_rounded
                        : Icons.analytics_outlined,
                    size: 16,
                    color: colorScheme.primary,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    showSelectedTotals
                        ? '${_selectionMode ? '已选' : '所选'} $selectedCount 笔 / ${filtered.length} 笔'
                        : '筛选结果 · ${filtered.length} 笔',
                    style: Theme.of(context).textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                if (_selectionMode) ...[
                  TextButton(
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                    onPressed: filtered.isEmpty
                        ? null
                        : () => _toggleSelectAll(filtered),
                    child: Text(allVisibleSelected ? '取消全选' : '全选'),
                  ),
                  FilledButton.tonal(
                    style: FilledButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      minimumSize: const Size(0, 32),
                    ),
                    onPressed: _toggleSelectionMode,
                    child: const Text('完成'),
                  ),
                ] else if (_hasCommittedSelection) ...[
                  TextButton(
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                    ),
                    onPressed: _toggleSelectionMode,
                    child: const Text('继续选择'),
                  ),
                  TextButton(
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                    ),
                    onPressed: _clearSelection,
                    child: const Text('清除'),
                  ),
                ] else ...[
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                    onPressed: _toggleSelectionMode,
                    icon: const Icon(Icons.checklist_rounded, size: 16),
                    label: const Text('选择账单'),
                  ),
                ],
                const SizedBox(width: 2),
                IconButton(
                  key: const ValueKey('finance-ledger-summary-collapse'),
                  tooltip: '收起账单合计',
                  visualDensity: VisualDensity.compact,
                  onPressed: onCollapse,
                  icon: const Icon(Icons.close_rounded, size: 18),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (amountLabels.isNotEmpty)
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  for (final label in amountLabels)
                    _buildSummaryMetricChip(context, label),
                ],
              )
            else if (selectedCount == 0)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(
                  _selectionMode ? '勾选账单后查看所选合计' : '暂无可合计的账目',
                  style: TextStyle(
                    color: colorScheme.onSurfaceVariant,
                    fontSize: 12,
                  ),
                ),
              ),
            if (plannedLabels.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest.withValues(
                    alpha: 0.35,
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.schedule_rounded,
                      size: 13,
                      color: colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Text(
                        plannedLabels.join(' · '),
                        style: TextStyle(
                          color: colorScheme.onSurfaceVariant,
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryMetricChip(BuildContext context, String label) {
    final colorScheme = Theme.of(context).colorScheme;
    final isIncome = label.startsWith('收入');
    final isNetExpense = label.startsWith('净支出');
    final isRefund = label.startsWith('退款');

    final Color fgColor;
    final Color bgColor;
    final Color borderColor;
    final IconData icon;

    if (isNetExpense) {
      fgColor = colorScheme.error;
      bgColor = colorScheme.errorContainer.withValues(alpha: 0.28);
      borderColor = colorScheme.error.withValues(alpha: 0.22);
      icon = Icons.trending_down_rounded;
    } else if (isIncome) {
      fgColor = colorScheme.primary;
      bgColor = colorScheme.primaryContainer.withValues(alpha: 0.32);
      borderColor = colorScheme.primary.withValues(alpha: 0.22);
      icon = Icons.trending_up_rounded;
    } else if (isRefund) {
      fgColor = colorScheme.tertiary;
      bgColor = colorScheme.tertiaryContainer.withValues(alpha: 0.28);
      borderColor = colorScheme.tertiary.withValues(alpha: 0.22);
      icon = Icons.replay_rounded;
    } else {
      fgColor = colorScheme.onSurface;
      bgColor = colorScheme.surfaceContainerHighest.withValues(alpha: 0.45);
      borderColor = colorScheme.outlineVariant.withValues(alpha: 0.3);
      icon = Icons.shopping_bag_outlined;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: borderColor, width: 0.8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: fgColor),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: fgColor,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.2,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDayHeader(
    BuildContext context,
    _FinanceDayGroup group, {
    required bool hideAmountsDuplicatedByFooter,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final hasExpenseFlow = group.expenseMinor > 0 || group.refundMinor > 0;
    final hasPlannedExpenseFlow =
        group.plannedExpenseMinor > 0 || group.plannedRefundMinor > 0;
    final amountLabels = <String>[
      if (hasExpenseFlow && !hideAmountsDuplicatedByFooter)
        '净支出 ${formatFinanceAmount(group.netExpenseMinor)}',
      if (hasPlannedExpenseFlow)
        '计划净支出 ${formatFinanceAmount(group.plannedNetExpenseMinor)}',
      if (group.incomeMinor > 0 && !hideAmountsDuplicatedByFooter)
        '收入 ${formatFinanceAmount(group.incomeMinor)}',
      if (group.plannedIncomeMinor > 0 && !hideAmountsDuplicatedByFooter)
        '计划收入 ${formatFinanceAmount(group.plannedIncomeMinor)}',
    ];
    if (amountLabels.isEmpty && !hideAmountsDuplicatedByFooter) {
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
      padding: const EdgeInsets.fromLTRB(4, 12, 4, 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(5),
            decoration: BoxDecoration(
              color: colorScheme.primaryContainer.withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              Icons.calendar_today_outlined,
              size: 15,
              color: colorScheme.primary,
            ),
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
                      fontSize: 12.5,
                      letterSpacing: -0.2,
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
    int asOfAt, {
    required bool selectionMode,
    required bool selected,
    required VoidCallback onToggleSelection,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final category = categories[transaction.categoryUuid];
    final payment = paymentMethods[transaction.paymentMethodUuid];
    final paymentName = payment == null
        ? null
        : _paymentMethodDisplayName(payment);
    final categoryName = _categoryDisplayName(transaction.categoryUuid);
    final merchant = transaction.merchant?.trim();
    final note = transaction.note?.trim();
    final hasCategory =
        category != null || transaction.categoryUuid?.trim().isNotEmpty == true;
    final titleUsesCategory =
        merchant?.isNotEmpty != true && note?.isNotEmpty != true && hasCategory;
    final title = merchant?.isNotEmpty == true
        ? merchant!
        : note?.isNotEmpty == true
        ? note!
        : titleUsesCategory
        ? categoryName
        : transaction.type.label;
    final subtitleParts = <String>[
      if (transaction.balanceEventAt() > asOfAt) '待发生',
      if (!titleUsesCategory)
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
      if (note?.isNotEmpty == true && note != title) note!,
    ];
    final amountColor = transaction.type == FinanceTransactionType.expense
        ? colorScheme.error
        : colorScheme.primary;
    final sourceKey = _cardKeyFor(transaction);
    return Card(
      key: sourceKey,
      elevation: 0,
      margin: EdgeInsets.zero,
      color: selected
          ? colorScheme.primaryContainer.withValues(alpha: 0.25)
          : colorScheme.surfaceContainerLowest,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: selected
              ? colorScheme.primary.withValues(alpha: 0.8)
              : colorScheme.outlineVariant.withValues(alpha: 0.35),
          width: selected ? 1.5 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        onTap: selectionMode
            ? onToggleSelection
            : () => onOpenDetail(transaction, sourceKey),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 3),
        leading: selectionMode
            ? Checkbox(
                value: selected,
                onChanged: (_) => onToggleSelection(),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(4),
                ),
              )
            : Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: colorScheme.secondaryContainer.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(13),
                ),
                alignment: Alignment.center,
                child: Text(
                  category?.icon ?? '💰',
                  style: const TextStyle(fontSize: 22),
                ),
              ),
        title: Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodyLarge
              ?.copyWith(fontWeight: FontWeight.w600, letterSpacing: -0.2),
        ),
        subtitle: Text(
          subtitleParts.isEmpty
              ? transaction.type.label
              : subtitleParts.join(' · '),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodySmall
              ?.copyWith(color: colorScheme.onSurfaceVariant),
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
                    fontSize: 16,
                    letterSpacing: -0.3,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              PopupMenuButton<String>(
                icon: Icon(
                  Icons.more_vert_rounded,
                  size: 20,
                  color: colorScheme.onSurfaceVariant.withValues(alpha: 0.8),
                ),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
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
            keyword.trim().isEmpty &&
                    filterType == null &&
                    categoryUuids.isEmpty &&
                    dateRange == null
                ? '$monthLabel还没有账单'
                : '没有匹配的账单',
            style: TextStyle(color: colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  Widget _buildQueryError(BuildContext context, String error) {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 42, color: colorScheme.error),
            const SizedBox(height: 10),
            const Text('筛选账单加载失败'),
            const SizedBox(height: 6),
            Text(
              error,
              textAlign: TextAlign.center,
              style: TextStyle(color: colorScheme.onSurfaceVariant),
            ),
            if (widget.onRetry != null) ...[
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: widget.onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('重试'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _FinanceLedgerCategoryPickerDialog extends StatefulWidget {
  final Map<String, FinanceCategory> categories;
  final Set<String> initialSelection;
  final Map<String, int>? categoryCounts;

  const _FinanceLedgerCategoryPickerDialog({
    required this.categories,
    required this.initialSelection,
    required this.categoryCounts,
  });

  @override
  State<_FinanceLedgerCategoryPickerDialog> createState() =>
      _FinanceLedgerCategoryPickerDialogState();
}

class _FinanceLedgerCategoryPickerDialogState
    extends State<_FinanceLedgerCategoryPickerDialog> {
  late final Set<String> _selected = widget.initialSelection.toSet();
  final Set<String> _expandedRootUuids = <String>{};

  List<FinanceCategory> get _orderedCategories =>
      widget.categories.values.toList()..sort((left, right) {
        final typeOrder = left.type.index.compareTo(right.type.index);
        if (typeOrder != 0) return typeOrder;
        final parentOrder = (left.parentUuid ?? '').compareTo(
          right.parentUuid ?? '',
        );
        if (parentOrder != 0) return parentOrder;
        final sortOrder = left.sortOrder.compareTo(right.sortOrder);
        return sortOrder != 0 ? sortOrder : left.uuid.compareTo(right.uuid);
      });

  List<FinanceCategory> _childrenOf(FinanceCategory parent) =>
      _orderedCategories
          .where((category) => category.parentUuid == parent.uuid)
          .toList(growable: false);

  bool _isRootSelected(FinanceCategory root) => _selected.contains(root.uuid);

  bool _isChildSelected(FinanceCategory parent, FinanceCategory child) =>
      _isRootSelected(parent) || _selected.contains(child.uuid);

  void _toggleRoot(FinanceCategory root) {
    final children = _childrenOf(root);
    setState(() {
      if (!_selected.add(root.uuid)) {
        _selected.remove(root.uuid);
        for (final child in children) {
          _selected.remove(child.uuid);
        }
      } else {
        for (final child in children) {
          _selected.remove(child.uuid);
        }
      }
    });
  }

  void _toggleRootExpansion(FinanceCategory root) {
    setState(() {
      if (!_expandedRootUuids.add(root.uuid)) {
        _expandedRootUuids.remove(root.uuid);
      }
    });
  }

  void _toggleChild(FinanceCategory parent, FinanceCategory child) {
    setState(() {
      if (_selected.remove(parent.uuid)) {
        for (final sibling in _childrenOf(parent)) {
          if (sibling.uuid != child.uuid) _selected.add(sibling.uuid);
        }
        return;
      }
      if (!_selected.add(child.uuid)) _selected.remove(child.uuid);
    });
  }

  String _categoryLabel(FinanceCategory category) {
    final status = category.isDeleted
        ? '（已删除）'
        : category.isArchived
        ? '（已归档）'
        : '';
    return '${category.icon} ${financeCategorySiblingDisplayName(category, _orderedCategories)}$status';
  }

  @override
  Widget build(BuildContext context) {
    final categoryByUuid = widget.categories;
    final roots = _orderedCategories
        .where((category) {
          final parentUuid = category.parentUuid?.trim();
          if (parentUuid == null || parentUuid.isEmpty) return true;
          final parent = categoryByUuid[parentUuid];
          return parent == null || parent.type != category.type;
        })
        .toList(growable: false);
    final expenseRoots = roots
        .where((category) => category.type == FinanceCategoryType.expense)
        .toList(growable: false);
    final incomeRoots = roots
        .where((category) => category.type == FinanceCategoryType.income)
        .toList(growable: false);
    return AlertDialog(
      title: const Text('选择分类'),
      content: SizedBox(
        width: 420,
        height: 480,
        child: ListView(
          children: [
            CheckboxListTile(
              value: _selected.contains(financeUncategorizedCategoryFilterUuid),
              title: const Text('未分类'),
              secondary: _countLabel(
                widget.categoryCounts?[financeUncategorizedCategoryFilterUuid],
              ),
              onChanged: (_) => setState(() {
                if (!_selected.add(financeUncategorizedCategoryFilterUuid)) {
                  _selected.remove(financeUncategorizedCategoryFilterUuid);
                }
              }),
              contentPadding: EdgeInsets.zero,
            ),
            for (final section in [
              ('支出', expenseRoots),
              ('收入', incomeRoots),
            ]) ...[
              Padding(
                padding: const EdgeInsets.only(top: 12, bottom: 4),
                child: Text(
                  section.$1,
                  style: Theme.of(context).textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              for (final root in section.$2) ...[
                Builder(
                  builder: (context) {
                    final children = _childrenOf(root);
                    final isExpanded = _expandedRootUuids.contains(root.uuid);
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: InkWell(
                                borderRadius: BorderRadius.circular(8),
                                onTap: children.isEmpty
                                    ? () => _toggleRoot(root)
                                    : () => _toggleRootExpansion(root),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 12,
                                    horizontal: 4,
                                  ),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Text(_categoryLabel(root)),
                                      ),
                                      if (widget.categoryCounts != null) ...[
                                        const SizedBox(width: 8),
                                        _countLabel(
                                          widget.categoryCounts![root.uuid] ??
                                              0,
                                        )!,
                                      ],
                                      if (children.isNotEmpty)
                                        Icon(
                                          isExpanded
                                              ? Icons.expand_less
                                              : Icons.expand_more,
                                          color: Theme.of(context)
                                              .colorScheme
                                              .onSurfaceVariant,
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            Checkbox(
                              value: _isRootSelected(root),
                              onChanged: (_) => _toggleRoot(root),
                            ),
                          ],
                        ),
                        if (isExpanded)
                          for (final child in children)
                            CheckboxListTile(
                              value: _isChildSelected(root, child),
                              title: Text(_categoryLabel(child)),
                              secondary: _countLabel(
                                widget.categoryCounts?[child.uuid],
                              ),
                              onChanged: (_) => _toggleChild(root, child),
                              contentPadding: const EdgeInsets.only(left: 24),
                              dense: true,
                            ),
                      ],
                    );
                  },
                ),
              ],
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => setState(_selected.clear),
          child: const Text('清空'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_selected.toSet()),
          child: const Text('应用'),
        ),
      ],
    );
  }

  Widget? _countLabel(int? count) {
    if (count == null) return null;
    return Text(
      '$count笔',
      style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
    );
  }
}

class _FinanceLedgerTotals {
  final int expenseMinor;
  final int refundMinor;
  final int incomeMinor;
  final int plannedExpenseMinor;
  final int plannedRefundMinor;
  final int plannedIncomeMinor;

  const _FinanceLedgerTotals({
    required this.expenseMinor,
    required this.refundMinor,
    required this.incomeMinor,
    required this.plannedExpenseMinor,
    required this.plannedRefundMinor,
    required this.plannedIncomeMinor,
  });

  int get netExpenseMinor => expenseMinor - refundMinor;

  factory _FinanceLedgerTotals.fromEntries(
    Iterable<_FinanceLedgerOrderEntry> entries,
    int nowAt,
  ) {
    var expenseMinor = 0;
    var refundMinor = 0;
    var incomeMinor = 0;
    var plannedExpenseMinor = 0;
    var plannedRefundMinor = 0;
    var plannedIncomeMinor = 0;
    for (final entry in entries) {
      final isPlanned = entry.eventAt > nowAt;
      final transaction = entry.transaction;
      switch (transaction.type) {
        case FinanceTransactionType.expense:
          if (isPlanned) {
            plannedExpenseMinor += transaction.amountMinor;
          } else {
            expenseMinor += transaction.amountMinor;
          }
        case FinanceTransactionType.refund:
          if (isPlanned) {
            plannedRefundMinor += transaction.amountMinor;
          } else {
            refundMinor += transaction.amountMinor;
          }
        case FinanceTransactionType.income:
          if (isPlanned) {
            plannedIncomeMinor += transaction.amountMinor;
          } else {
            incomeMinor += transaction.amountMinor;
          }
      }
    }
    return _FinanceLedgerTotals(
      expenseMinor: expenseMinor,
      refundMinor: refundMinor,
      incomeMinor: incomeMinor,
      plannedExpenseMinor: plannedExpenseMinor,
      plannedRefundMinor: plannedRefundMinor,
      plannedIncomeMinor: plannedIncomeMinor,
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

class _FinanceCumulativeBalanceTrendPainter extends CustomPainter {
  final List<FinanceCumulativeBalancePoint> points;
  final int selectedIndex;
  final ColorScheme colorScheme;

  const _FinanceCumulativeBalanceTrendPainter({
    required this.points,
    required this.selectedIndex,
    required this.colorScheme,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty || size.width <= 0 || size.height <= 0) return;

    const leftInset = 18.0;
    const rightInset = 18.0;
    const topInset = 10.0;
    const bottomInset = 28.0;
    final plot = Rect.fromLTRB(
      leftInset,
      topInset,
      size.width - rightInset,
      size.height - bottomInset,
    );
    if (plot.width <= 0 || plot.height <= 0) return;

    var minimum = points.first.balanceMinor;
    var maximum = minimum;
    for (final point in points.skip(1)) {
      minimum = math.min(minimum, point.balanceMinor);
      maximum = math.max(maximum, point.balanceMinor);
    }
    minimum = math.min(minimum, 0);
    maximum = math.max(maximum, 0);

    double xFor(int index) => points.length == 1
        ? plot.center.dx
        : plot.left + plot.width * index / (points.length - 1);

    double yFor(int value) {
      if (minimum == maximum) return plot.center.dy;
      return plot.top + (maximum - value) / (maximum - minimum) * plot.height;
    }

    final gridPaint = Paint()
      ..color = colorScheme.outlineVariant.withValues(alpha: 0.45)
      ..strokeWidth = 1;
    canvas.drawLine(plot.topLeft, plot.topRight, gridPaint);
    canvas.drawLine(plot.bottomLeft, plot.bottomRight, gridPaint);
    if (minimum <= 0 && maximum >= 0) {
      final zeroY = yFor(0);
      canvas.drawLine(
        Offset(plot.left, zeroY),
        Offset(plot.right, zeroY),
        gridPaint,
      );
    }

    const baselineValue = 0;
    final fillPath = Path()..moveTo(xFor(0), yFor(baselineValue));
    final linePath = Path()..moveTo(xFor(0), yFor(points.first.balanceMinor));
    for (var index = 1; index < points.length; index++) {
      final point = points[index];
      final x = xFor(index);
      final y = yFor(point.balanceMinor);
      linePath.lineTo(x, y);
      fillPath.lineTo(x, y);
    }
    fillPath
      ..lineTo(xFor(points.length - 1), yFor(baselineValue))
      ..close();
    canvas.drawPath(
      fillPath,
      Paint()
        ..color = colorScheme.primary.withValues(alpha: 0.09)
        ..style = PaintingStyle.fill,
    );
    canvas.drawPath(
      linePath,
      Paint()
        ..color = colorScheme.primary
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke,
    );

    for (var index = 0; index < points.length; index++) {
      final center = Offset(xFor(index), yFor(points[index].balanceMinor));
      if (index == selectedIndex) {
        canvas.drawCircle(
          center,
          6,
          Paint()
            ..color = colorScheme.surface
            ..style = PaintingStyle.fill,
        );
        canvas.drawCircle(
          center,
          5,
          Paint()
            ..color = colorScheme.primary
            ..style = PaintingStyle.fill,
        );
      } else {
        canvas.drawCircle(
          center,
          3.25,
          Paint()
            ..color = colorScheme.primary
            ..style = PaintingStyle.fill,
        );
      }

      final showLabel =
          index.isEven || index == points.length - 1 || index == selectedIndex;
      if (!showLabel) continue;
      final label = TextPainter(
        text: TextSpan(
          text: '${points[index].month.month}月',
          style: TextStyle(fontSize: 10, color: colorScheme.onSurfaceVariant),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout(maxWidth: 34);
      final labelX = (center.dx - label.width / 2).clamp(
        0.0,
        size.width - label.width,
      );
      label.paint(canvas, Offset(labelX, size.height - label.height));
    }
  }

  @override
  bool shouldRepaint(covariant _FinanceCumulativeBalanceTrendPainter old) =>
      old.points != points ||
      old.selectedIndex != selectedIndex ||
      old.colorScheme.primary != colorScheme.primary ||
      old.colorScheme.surface != colorScheme.surface ||
      old.colorScheme.outlineVariant != colorScheme.outlineVariant ||
      old.colorScheme.onSurfaceVariant != colorScheme.onSurfaceVariant;
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
