part of '../finance_widgets.dart';

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
  final List<FinancePaymentMethod> paymentMethods;
  final List<FinanceBudget> budgets;
  final List<FinanceEntryTemplate> templates;
  final List<FinanceRecurringRule> recurringRules;
  final VoidCallback? onOpenBudgets;
  final VoidCallback? onOpenFutureCommitments;
  final VoidCallback? onOpenTextRecognition;
  final ValueChanged<FinanceEntryTemplate>? onOpenTemplate;
  final ValueChanged<FinancePaymentMethod>? onSelectPaymentMethod;
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
    this.paymentMethods = const [],
    this.budgets = const [],
    this.templates = const [],
    this.recurringRules = const [],
    this.onOpenBudgets,
    this.onOpenFutureCommitments,
    this.onOpenTextRecognition,
    this.onOpenTemplate,
    this.onSelectPaymentMethod,
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
  FinanceCategoryType _categoryChartType = FinanceCategoryType.expense;
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
  List<FinancePaymentMethod> get paymentMethods => widget.paymentMethods;
  List<FinanceBudget> get budgets => widget.budgets;
  List<FinanceEntryTemplate> get templates => widget.templates;
  List<FinanceRecurringRule> get recurringRules => widget.recurringRules;

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
      if (_focusedDate.year != month.year ||
          _focusedDate.month != month.month) {
        _focusedDate = _initialFocusDate(month);
      }
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
    final colorScheme = Theme.of(context).colorScheme;
    final bottomPadding = financeBottomContentPaddingFor(context);

    return Column(
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(16, widget.topPadding + 8, 16, 8),
          child: _buildOverviewModeSelector(),
        ),
        Expanded(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 260),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeOutCubic,
            transitionBuilder: (child, animation) {
              return AnimatedBuilder(
                animation: animation,
                child: child,
                builder: (context, child) {
                  if (animation.value <= 0.001) {
                    return const SizedBox.shrink();
                  }
                  if (animation.value >= 0.999) {
                    return child!;
                  }
                  return FadeTransition(opacity: animation, child: child);
                },
              );
            },
            child: _mode == _FinanceOverviewMode.calendar
                ? KeyedSubtree(
                    key: const ValueKey('finance-overview-calendar-view'),
                    child: FinanceCalendarPanel(
                      topPadding: 0,
                      clock: clock,
                      month: month,
                      transactions: transactions,
                      cumulativeBalanceEvents: widget.cumulativeBalanceEvents,
                      openingBalanceMinor: widget.openingBalanceMinor,
                      openingBalanceStartDate: widget.openingBalanceStartDate,
                      categories: categories,
                      onRefresh: onRefresh,
                      onMonthChanged: (value) => onMonthChanged?.call(value),
                      onShowReport: () =>
                          setState(() => _mode = _FinanceOverviewMode.report),
                      onAdd: widget.onAddForDate == null
                          ? null
                          : (date, sourceKey) =>
                                widget.onAddForDate!(date, sourceKey),
                      onOpenTransaction: widget.onOpenTransaction,
                      showModeSelector: false,
                    ),
                  )
                : KeyedSubtree(
                    key: const ValueKey('finance-overview-report-view'),
                    child: _buildReportBody(
                      context,
                      colorScheme,
                      bottomPadding,
                    ),
                  ),
          ),
        ),
      ],
    );
  }

  Widget _buildReportBody(
    BuildContext context,
    ColorScheme colorScheme,
    double bottomPadding,
  ) {
    final period = _currentPeriod;
    final analytics = _overviewAnalytics(period);
    final isIncomeChart = _categoryChartType == FinanceCategoryType.income;
    final topCategories = isIncomeChart
        ? analytics.topIncomeCategories
        : analytics.topExpenseCategories;
    final categoryShares = isIncomeChart
        ? analytics.topIncomeCategories
        : analytics.categoryExpenseShares;

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        scrollCacheExtent: ScrollCacheExtent.pixels(2500),
        padding: EdgeInsets.fromLTRB(16, 0, 16, bottomPadding),
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth >= 640;
              if (isWide) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(flex: 5, child: _buildViewSelector(context)),
                    const SizedBox(width: 14),
                    Expanded(
                      flex: 5,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '统计周期',
                            style: Theme.of(context).textTheme.labelLarge
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 4),
                          _buildPeriodNavigator(context),
                        ],
                      ),
                    ),
                  ],
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildViewSelector(context),
                  const SizedBox(height: 8),
                  _buildPeriodNavigator(context),
                ],
              );
            },
          ),
          const SizedBox(height: 10),
          _buildQuickActionsRow(context, colorScheme),
          const SizedBox(height: 10),
          _buildSummaryCard(context, colorScheme, period),
          const SizedBox(height: 10),
          _buildBudgetCard(context, colorScheme, period),
          const SizedBox(height: 16),
          _buildCategoryChartHeader(context, period),
          const SizedBox(height: 8),
          if (topCategories.isEmpty)
            _buildEmptyCard(
              context,
              icon: Icons.pie_chart_outline,
              message: isIncomeChart
                  ? (period.isPlanned
                        ? '${period.shortTitle}没有可展示的计划收入分类'
                        : '${period.shortTitle}没有可展示的收入分类')
                  : (period.isPlanned
                        ? '${period.shortTitle}没有可展示的计划净支出分类'
                        : '${period.shortTitle}没有可展示的净支出分类'),
            )
          else
            _buildUnifiedCategoryCard(
              context,
              colorScheme,
              topCategories,
              categoryShares,
              period,
              categoryType: _categoryChartType,
            ),
          _buildEnhancedInsightCard(context, colorScheme, period, analytics),
          _buildPaymentMethodSpendingCard(
            context,
            colorScheme,
            period,
            analytics,
          ),
          _buildUpcomingCommitmentsCard(context, colorScheme),
          const SizedBox(height: 16),
          Text(
            _spendingChartTitle(period),
            style: Theme.of(context).textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: BorderSide(
                color: colorScheme.outlineVariant.withValues(alpha: 0.35),
                width: 0.8,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 16, 14, 14),
              child: _buildSpendingChart(
                context,
                colorScheme,
                period,
                analytics,
              ),
            ),
          ),
          const SizedBox(height: 24),
          _buildCumulativeBalanceTrendCard(context, colorScheme),
          const SizedBox(height: 12),
          _buildCumulativeBalanceCard(context, colorScheme),
        ],
      ),
    );
  }

  Widget _buildCategoryChartHeader(
    BuildContext context,
    _FinanceOverviewPeriod period,
  ) {
    final isIncome = _categoryChartType == FinanceCategoryType.income;
    final title = isIncome
        ? (period.isPlanned ? '计划收入分类' : '收入分类')
        : (period.isPlanned ? '计划支出分类' : '支出分类');
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
        ),
        const SizedBox(width: 12),
        SizedBox(
          width: 148,
          child: FinanceGlassSegmentSelector<FinanceCategoryType>(
            keyPrefix: 'finance-overview-category-type-selector',
            height: 40,
            segments: const [
              FinanceGlassSegment(
                id: 'expense',
                label: '支出',
                value: FinanceCategoryType.expense,
              ),
              FinanceGlassSegment(
                id: 'income',
                label: '收入',
                value: FinanceCategoryType.income,
              ),
            ],
            selected: _categoryChartType,
            onSelected: (value) {
              if (_categoryChartType == value) return;
              setState(() => _categoryChartType = value);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildOverviewModeSelector() {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: FinanceGlassSegmentSelector<_FinanceOverviewMode>(
          keyPrefix: 'finance-overview-mode-selector',
          alternateKeyPrefixes: const ['finance-calendar-mode-selector'],
          height: 44,
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
        ),
      ),
    );
  }

  _FinanceOverviewPeriod get _currentPeriod {
    final range = _periodRange;
    final now = clock();
    final includesNow = !now.isBefore(range.from) && now.isBefore(range.to);
    final selectedMonthIsCurrent =
        now.year == month.year && now.month == month.month;
    final selectedMonthIsFuture =
        month.year > now.year ||
        (month.year == now.year && month.month > now.month);
    final isPlanned = range.from.isAfter(now) || selectedMonthIsFuture;
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
        const SizedBox(height: 4),
        FinanceGlassSegmentSelector<_FinanceOverviewView>(
          keyPrefix: 'finance-overview-view-selector',
          height: 42,
          segments: const [
            FinanceGlassSegment(
              id: 'month',
              label: '月视图',
              value: _FinanceOverviewView.month,
            ),
            FinanceGlassSegment(
              id: 'week',
              label: '周视图',
              value: _FinanceOverviewView.week,
            ),
            FinanceGlassSegment(
              id: 'day',
              label: '日视图',
              value: _FinanceOverviewView.day,
            ),
          ],
          selected: _view,
          onSelected: (value) {
            setState(() => _view = value);
            _refreshCumulativeBalance();
          },
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
      height: 42,
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.35),
          width: 0.8,
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      child: Row(
        children: [
          IconButton(
            key: const ValueKey('finance-overview-period-previous'),
            tooltip: isMonthView
                ? '上个月'
                : _view == _FinanceOverviewView.week
                ? '上一周'
                : '前一天',
            style: IconButton.styleFrom(
              backgroundColor: colorScheme.surfaceContainerHighest.withValues(
                alpha: 0.5,
              ),
              padding: const EdgeInsets.all(6),
            ),
            onPressed: previousAction,
            icon: const Icon(Icons.chevron_left_rounded, size: 22),
          ),
          Expanded(
            child: InkWell(
              key: const ValueKey('finance-overview-period-picker'),
              borderRadius: BorderRadius.circular(12),
              onTap: isMonthView ? _pickMonth : _pickFocusedDate,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        title,
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 16.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      Icons.keyboard_arrow_down_rounded,
                      size: 20,
                      color: colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: colorScheme.primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        subtitle,
                        style: TextStyle(
                          color: colorScheme.primary,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
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
            style: IconButton.styleFrom(
              backgroundColor: colorScheme.surfaceContainerHighest.withValues(
                alpha: 0.5,
              ),
              padding: const EdgeInsets.all(6),
            ),
            onPressed: nextAction,
            icon: const Icon(Icons.chevron_right_rounded, size: 22),
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
    final picked = await showAppDatePicker(
      context: context,
      initialDate: _focusedDate,
      firstDate: DateTime(2000),
      lastDate: clock().add(const Duration(days: 3650)),
      helpText: _view == _FinanceOverviewView.week ? '选择周视图日期' : '选择日视图日期',
    );
    if (picked != null && mounted) {
      final pickedDate = DateTime(picked.year, picked.month, picked.day);
      setState(() => _focusedDate = pickedDate);
      if (pickedDate.year != month.year || pickedDate.month != month.month) {
        onMonthChanged?.call(DateTime(pickedDate.year, pickedDate.month));
      }
      _refreshCumulativeBalance();
    }
  }

  void _shiftFocusedPeriod(int delta) {
    if (!_canShiftFocusedPeriod(delta)) return;
    final next = _view == _FinanceOverviewView.week
        ? financeCalendarDayOffset(_focusedDate, delta * 7)
        : financeCalendarDayOffset(_focusedDate, delta);
    setState(() => _focusedDate = next);
    if (next.year != month.year || next.month != month.month) {
      onMonthChanged?.call(DateTime(next.year, next.month));
    }
    _refreshCumulativeBalance();
  }

  bool _canShiftFocusedPeriod(int delta) {
    final firstAllowedDate = DateTime(2000);
    final lastAllowedDate = clock().add(const Duration(days: 3650));
    if (_view == _FinanceOverviewView.month) {
      final nextMonth = DateTime(month.year, month.month + delta);
      final lastAllowedMonth = DateTime(
        lastAllowedDate.year,
        lastAllowedDate.month,
      );
      return !nextMonth.isBefore(firstAllowedDate) &&
          !nextMonth.isAfter(lastAllowedMonth);
    }
    final days = _view == _FinanceOverviewView.week ? delta * 7 : delta;
    final next = financeCalendarDayOffset(_focusedDate, days);
    return !next.isBefore(firstAllowedDate) && !next.isAfter(lastAllowedDate);
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

  void _mutateState(VoidCallback fn) => setState(fn);
}
