part of '../finance_widgets.dart';

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

  /// When true, selected categories match only bills recorded directly in
  /// them, without including their subcategories.
  final bool exactCategoryMatch;
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
  final ValueChanged<DateTime>? onMonthChanged;
  final ValueChanged<FinanceTransaction> onEdit;
  final ValueChanged<FinanceTransaction> onDelete;
  final ValueChanged<FinanceTransaction> onRefund;
  final Future<void> Function(List<FinanceTransaction> updated)? onBatchSave;
  final Future<void> Function(List<FinanceTransaction> deleted)? onBatchDelete;

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
    this.exactCategoryMatch = false,
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
    this.onMonthChanged,
    required this.onEdit,
    required this.onDelete,
    required this.onRefund,
    this.onBatchSave,
    this.onBatchDelete,
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
  bool _isBatchSaving = false;
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
  bool get _exactCategoryMatch => widget.exactCategoryMatch;
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
      categoryKey:
          '${_exactCategoryMatch ? 'exact:' : ''}'
          '${(categoryUuids.toList()..sort()).join('\u0000')}',
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
            FinanceTransactionType.transfer => '已删除或未知转出账户',
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

  bool _canShiftLedgerPeriod(int delta) {
    final firstAllowedDate = DateTime(2000);
    final lastAllowedDate = widget.clock().add(const Duration(days: 3650));
    if (dateRange == null) {
      final now = widget.clock();
      final month = widget.month ?? now;
      final nextMonth = DateTime(month.year, month.month + delta);
      final lastAllowedMonth = DateTime(
        lastAllowedDate.year,
        lastAllowedDate.month,
      );
      return !nextMonth.isBefore(firstAllowedDate) &&
          !nextMonth.isAfter(lastAllowedMonth);
    }
    final range = dateRange!;
    final spanDays = math.max(1, range.end.difference(range.start).inDays + 1);
    final nextStart = financeCalendarDayOffset(range.start, delta * spanDays);
    final nextEnd = financeCalendarDayOffset(range.end, delta * spanDays);
    return !nextStart.isBefore(firstAllowedDate) &&
        !nextEnd.isAfter(lastAllowedDate);
  }

  void _shiftLedgerPeriod(int delta) {
    if (!_canShiftLedgerPeriod(delta)) return;
    if (dateRange == null) {
      final now = widget.clock();
      final month = widget.month ?? now;
      final nextMonth = DateTime(month.year, month.month + delta);
      widget.onMonthChanged?.call(nextMonth);
      return;
    }
    final range = dateRange!;
    final spanDays = math.max(1, range.end.difference(range.start).inDays + 1);
    final nextStart = financeCalendarDayOffset(range.start, delta * spanDays);
    final nextEnd = financeCalendarDayOffset(range.end, delta * spanDays);
    final nextRange = DateTimeRange(start: nextStart, end: nextEnd);
    _selectedTransactionUuids.clear();
    _hasCommittedSelection = false;
    if (widget.onDateRangeChanged == null) {
      setState(() => _localDateRange = nextRange);
    } else {
      widget.onDateRangeChanged!(nextRange);
    }
    if (nextStart.year != (widget.month?.year ?? -1) ||
        nextStart.month != (widget.month?.month ?? -1)) {
      widget.onMonthChanged?.call(DateTime(nextStart.year, nextStart.month));
    }
  }

  Widget _buildPeriodNavigator(
    BuildContext context, {
    EdgeInsetsGeometry margin = const EdgeInsets.fromLTRB(16, 4, 16, 4),
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final now = widget.clock();
    final month = widget.month ?? now;
    final canShiftPrevious = _canShiftLedgerPeriod(-1);
    final canShiftNext = _canShiftLedgerPeriod(1);
    final isCustomRange = dateRange != null;

    final String title = '${month.year}年${month.month}月';
    final String subtitle = isCustomRange ? '自定义区间' : '月账单';

    return Container(
      height: 46,
      margin: margin,
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.35),
          width: 0.8,
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: Row(
        children: [
          IconButton(
            key: const ValueKey('finance-ledger-period-previous'),
            tooltip: isCustomRange ? '前一周期' : '上个月',
            style: IconButton.styleFrom(
              backgroundColor: colorScheme.surfaceContainerHighest.withValues(
                alpha: 0.5,
              ),
              padding: const EdgeInsets.all(6),
            ),
            onPressed: canShiftPrevious ? () => _shiftLedgerPeriod(-1) : null,
            icon: const Icon(Icons.chevron_left_rounded, size: 20),
          ),
          Expanded(
            child: InkWell(
              key: const ValueKey('finance-ledger-period-picker'),
              borderRadius: BorderRadius.circular(10),
              onTap: _pickDateRange,
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
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      Icons.keyboard_arrow_down_rounded,
                      size: 18,
                      color: colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 1.5,
                      ),
                      decoration: BoxDecoration(
                        color: colorScheme.primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        subtitle,
                        style: TextStyle(
                          color: colorScheme.primary,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    if (isCustomRange) ...[
                      const SizedBox(width: 6),
                      GestureDetector(
                        key: const ValueKey('finance-ledger-period-reset'),
                        onTap: _resetDateRange,
                        child: Tooltip(
                          message: '恢复当前月',
                          child: Container(
                            padding: const EdgeInsets.all(2),
                            decoration: BoxDecoration(
                              color: colorScheme.onSurface.withValues(
                                alpha: 0.1,
                              ),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.close_rounded,
                              size: 14,
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          IconButton(
            key: const ValueKey('finance-ledger-period-next'),
            tooltip: isCustomRange ? '后一周期' : '下个月',
            style: IconButton.styleFrom(
              backgroundColor: colorScheme.surfaceContainerHighest.withValues(
                alpha: 0.5,
              ),
              padding: const EdgeInsets.all(6),
            ),
            onPressed: canShiftNext ? () => _shiftLedgerPeriod(1) : null,
            icon: const Icon(Icons.chevron_right_rounded, size: 20),
          ),
        ],
      ),
    );
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

  bool _matchesSelectedCategories(FinanceTransaction transaction) {
    if (categoryUuids.isEmpty) return true;
    final selected = categoryUuids;
    final transactionCategoryUuid = transaction.categoryUuid?.trim();
    if (transactionCategoryUuid == null || transactionCategoryUuid.isEmpty) {
      return selected.contains(financeUncategorizedCategoryFilterUuid);
    }
    if (_exactCategoryMatch) return selected.contains(transactionCategoryUuid);
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
            LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth >= 640;
                final searchField = TextField(
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
                );

                if (isWide) {
                  return Padding(
                    padding: EdgeInsets.fromLTRB(
                      16,
                      widget.topPadding + 12,
                      16,
                      4,
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(flex: 6, child: searchField),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 4,
                          child: _buildPeriodNavigator(
                            context,
                            margin: EdgeInsets.zero,
                          ),
                        ),
                      ],
                    ),
                  );
                }

                return Column(
                  children: [
                    Padding(
                      padding: EdgeInsets.fromLTRB(
                        16,
                        widget.topPadding + 12,
                        16,
                        4,
                      ),
                      child: searchField,
                    ),
                    _buildPeriodNavigator(context),
                  ],
                );
              },
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
                  return FadeTransition(
                    opacity: animation,
                    child: ScaleTransition(
                      scale: animation,
                      alignment: Alignment.bottomRight,
                      child: child,
                    ),
                  );
                },
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

  void _mutateState(VoidCallback fn) => setState(fn);
}
