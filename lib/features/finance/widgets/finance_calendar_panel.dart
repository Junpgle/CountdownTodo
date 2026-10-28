import 'package:flutter/material.dart';

import '../../../utils/app_dialogs.dart';
import '../../../widgets/floating_bottom_bar.dart';
import '../models/finance_models.dart';
import '../services/finance_repository.dart';
import 'finance_glass_segment_selector.dart';

enum _FinanceCalendarMetric { expense, income, cashflow, balance }

class FinanceCalendarPanel extends StatefulWidget {
  final double topPadding;
  final DateTime Function() clock;
  final DateTime month;
  final List<FinanceTransaction> transactions;
  final List<FinanceCumulativeBalanceEvent> cumulativeBalanceEvents;
  final int openingBalanceMinor;
  final String? openingBalanceStartDate;
  final Map<String, FinanceCategory> categories;
  final Future<void> Function() onRefresh;
  final ValueChanged<DateTime> onMonthChanged;
  final VoidCallback onShowReport;
  final Future<void> Function(DateTime date, GlobalKey sourceKey)? onAdd;
  final Future<void> Function(
    FinanceTransaction transaction,
    GlobalKey sourceKey,
  )?
  onOpenTransaction;

  const FinanceCalendarPanel({
    super.key,
    this.topPadding = 0,
    this.clock = DateTime.now,
    required this.month,
    required this.transactions,
    required this.cumulativeBalanceEvents,
    required this.openingBalanceMinor,
    required this.openingBalanceStartDate,
    required this.categories,
    required this.onRefresh,
    required this.onMonthChanged,
    required this.onShowReport,
    this.onAdd,
    this.onOpenTransaction,
  });

  @override
  State<FinanceCalendarPanel> createState() => _FinanceCalendarPanelState();
}

class _FinanceCalendarPanelState extends State<FinanceCalendarPanel> {
  late DateTime _selectedDate;
  _FinanceCalendarMetric _metric = _FinanceCalendarMetric.expense;
  Set<FinanceTransactionType> _selectedTypes = FinanceTransactionType.values
      .toSet();
  Set<String> _selectedCategoryUuids = <String>{};
  final GlobalKey _addActionKey = GlobalKey(
    debugLabel: 'finance-calendar-add-entry',
  );

  DateTime get month => DateTime(widget.month.year, widget.month.month);
  DateTime get now => widget.clock();
  String get todayKey => dateKey(now);

  @override
  void initState() {
    super.initState();
    _selectedDate = _initialDate(month);
  }

  @override
  void didUpdateWidget(covariant FinanceCalendarPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.month.year != month.year ||
        oldWidget.month.month != month.month) {
      final selectedMonth = DateTime(_selectedDate.year, _selectedDate.month);
      if (selectedMonth != month) _selectedDate = _initialDate(month);
    }
  }

  DateTime _initialDate(DateTime value) {
    final current = now;
    if (current.year == value.year && current.month == value.month) {
      return DateTime(current.year, current.month, current.day);
    }
    return DateTime(value.year, value.month, 1);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return RefreshIndicator(
      onRefresh: widget.onRefresh,
      child: ListView(
        padding: EdgeInsets.fromLTRB(
          16,
          widget.topPadding + 12,
          16,
          floatingBottomNavigationContentPaddingFor(context),
        ),
        children: [
          _buildModeSelector(),
          const SizedBox(height: 12),
          _buildMonthNavigator(),
          const SizedBox(height: 10),
          _buildFilterAndMetricSelectors(colorScheme),
          const SizedBox(height: 12),
          _buildCalendarCard(context),
          const SizedBox(height: 12),
          _buildMonthlySummary(context),
          const SizedBox(height: 20),
          _buildSelectedDayHeader(context),
          const SizedBox(height: 8),
          ..._buildSelectedDayTransactions(context),
        ],
      ),
    );
  }

  Widget _buildModeSelector() {
    return FinanceGlassSegmentSelector<bool>(
      keyPrefix: 'finance-calendar-mode-selector',
      segments: const [
        FinanceGlassSegment(id: 'report', label: '报表', value: false),
        FinanceGlassSegment(id: 'calendar', label: '日历', value: true),
      ],
      selected: true,
      onSelected: (value) {
        if (!value) widget.onShowReport();
      },
    );
  }

  Widget _buildMonthNavigator() {
    final colorScheme = Theme.of(context).colorScheme;
    final currentMonth = DateTime(now.year, now.month);
    final firstMonth = DateTime(2000);
    final lastDate = now.add(const Duration(days: 3650));
    final lastMonth = DateTime(lastDate.year, lastDate.month);
    final previous = DateTime(month.year, month.month - 1);
    final next = DateTime(month.year, month.month + 1);
    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: Row(
        children: [
          IconButton(
            key: const ValueKey('finance-calendar-month-previous'),
            tooltip: '上个月',
            onPressed: previous.isBefore(firstMonth)
                ? null
                : () => _shiftMonth(-1),
            icon: const Icon(Icons.chevron_left),
          ),
          Expanded(
            child: InkWell(
              key: const ValueKey('finance-calendar-month-picker'),
              borderRadius: BorderRadius.circular(12),
              onTap: _pickMonth,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 7),
                child: Column(
                  children: [
                    Text(
                      '${month.year}年${month.month}月',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    Text(
                      month == currentMonth ? '本月账单日历' : '选择月份',
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
            key: const ValueKey('finance-calendar-month-next'),
            tooltip: '下个月',
            onPressed: next.isAfter(lastMonth) ? null : () => _shiftMonth(1),
            icon: const Icon(Icons.chevron_right),
          ),
        ],
      ),
    );
  }

  Future<void> _pickMonth() async {
    final picked = await showAppDatePicker(
      context: context,
      initialDate: month,
      firstDate: DateTime(2000),
      lastDate: now.add(const Duration(days: 3650)),
      helpText: '选择月份',
    );
    if (picked == null || !mounted) return;
    final newMonth = DateTime(picked.year, picked.month);
    _setMonth(newMonth, selectedDay: 1);
  }

  void _shiftMonth(int delta) {
    final nextMonth = DateTime(month.year, month.month + delta);
    final daysInNextMonth = DateTime(
      nextMonth.year,
      nextMonth.month + 1,
      0,
    ).day;
    _setMonth(
      nextMonth,
      selectedDay: _selectedDate.day.clamp(1, daysInNextMonth),
    );
  }

  void _setMonth(DateTime value, {required int selectedDay}) {
    setState(() {
      _selectedDate = DateTime(
        value.year,
        value.month,
        selectedDay.clamp(1, DateTime(value.year, value.month + 1, 0).day),
      );
    });
    widget.onMonthChanged(DateTime(value.year, value.month));
  }

  Widget _buildFilterAndMetricSelectors(ColorScheme colorScheme) {
    final activeFilterCount =
        (_selectedTypes.length == FinanceTransactionType.values.length
            ? 0
            : 1) +
        (_selectedCategoryUuids.isEmpty ? 0 : 1);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            TextButton.icon(
              key: const ValueKey('finance-calendar-filter'),
              onPressed: _showFilters,
              icon: const Icon(Icons.tune_rounded, size: 18),
              label: Text(
                activeFilterCount == 0 ? '筛选' : '筛选 $activeFilterCount',
              ),
            ),
            const Spacer(),
            Text(
              _metric == _FinanceCalendarMetric.balance
                  ? '结余按全账本口径'
                  : '颜色越深，金额越高',
              style: TextStyle(
                color: colorScheme.onSurfaceVariant,
                fontSize: 12,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        FinanceGlassSegmentSelector<_FinanceCalendarMetric>(
          keyPrefix: 'finance-calendar-metric-selector',
          height: 50,
          segments: const [
            FinanceGlassSegment(
              id: 'expense',
              label: '支出',
              value: _FinanceCalendarMetric.expense,
            ),
            FinanceGlassSegment(
              id: 'income',
              label: '收入',
              value: _FinanceCalendarMetric.income,
            ),
            FinanceGlassSegment(
              id: 'cashflow',
              label: '收支',
              value: _FinanceCalendarMetric.cashflow,
            ),
            FinanceGlassSegment(
              id: 'balance',
              label: '结余',
              value: _FinanceCalendarMetric.balance,
            ),
          ],
          selected: _metric,
          onSelected: (value) => setState(() => _metric = value),
        ),
      ],
    );
  }

  Future<void> _showFilters() async {
    final initialTypes = Set<FinanceTransactionType>.of(_selectedTypes);
    final initialCategories = Set<String>.of(_selectedCategoryUuids);
    final result =
        await showModalBottomSheet<
          ({Set<FinanceTransactionType> types, Set<String> categories})
        >(
          context: context,
          isScrollControlled: true,
          showDragHandle: true,
          builder: (context) {
            var types = initialTypes;
            var categoryUuids = initialCategories;
            final sortedCategories = widget.categories.values.toList()
              ..sort((a, b) {
                final order = a.sortOrder.compareTo(b.sortOrder);
                return order != 0 ? order : a.name.compareTo(b.name);
              });
            return StatefulBuilder(
              builder: (context, setSheetState) => SafeArea(
                child: SizedBox(
                  height: MediaQuery.sizeOf(context).height * 0.7,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 4, 20, 10),
                        child: Text(
                          '筛选日历账单',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Text(
                          '账单类型',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        child: Wrap(
                          spacing: 8,
                          children: [
                            for (final type in FinanceTransactionType.values)
                              FilterChip(
                                label: Text(type.label),
                                selected: types.contains(type),
                                onSelected: (selected) => setSheetState(() {
                                  types = Set<FinanceTransactionType>.of(types);
                                  if (selected) {
                                    types.add(type);
                                  } else {
                                    types.remove(type);
                                  }
                                }),
                              ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
                        child: Text(
                          '账单分类（不选时显示全部）',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                      ),
                      Expanded(
                        child: ListView(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          children: [
                            CheckboxListTile(
                              title: const Text('全部分类'),
                              value: categoryUuids.isEmpty,
                              onChanged: (_) => setSheetState(
                                () => categoryUuids = <String>{},
                              ),
                            ),
                            for (final category in sortedCategories)
                              CheckboxListTile(
                                dense: true,
                                secondary: Text(
                                  category.icon,
                                  style: const TextStyle(fontSize: 20),
                                ),
                                title: Text(category.name),
                                subtitle: Text(category.type.label),
                                value: categoryUuids.contains(category.uuid),
                                onChanged: (selected) => setSheetState(() {
                                  categoryUuids = Set<String>.of(categoryUuids);
                                  if (selected == true) {
                                    categoryUuids.add(category.uuid);
                                  } else {
                                    categoryUuids.remove(category.uuid);
                                  }
                                }),
                              ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () => setSheetState(() {
                                  types = FinanceTransactionType.values.toSet();
                                  categoryUuids = <String>{};
                                }),
                                child: const Text('重置'),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: FilledButton(
                                onPressed: () => Navigator.pop(context, (
                                  types: types,
                                  categories: categoryUuids,
                                )),
                                child: const Text('应用筛选'),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
    if (result == null || !mounted) return;
    setState(() {
      _selectedTypes = result.types;
      _selectedCategoryUuids = result.categories;
    });
  }

  Widget _buildCalendarCard(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final firstOfMonth = DateTime(month.year, month.month);
    final leadingDays = (firstOfMonth.weekday - DateTime.monday) % 7;
    final gridStart = financeCalendarDayOffset(firstOfMonth, -leadingDays);
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final gridDayCount = ((leadingDays + daysInMonth + 6) ~/ 7) * 7;
    final allDates = List.generate(
      gridDayCount,
      (index) => financeCalendarDayOffset(gridStart, index),
    );
    final maxMagnitude = allDates.fold<int>(0, (maximum, date) {
      final amount = _valueForDate(date)?.abs() ?? 0;
      return amount > maximum ? amount : maximum;
    });
    return Card(
      color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.7),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 12, 8, 10),
        child: Column(
          children: [
            Row(
              children: [
                for (final label in const [
                  '周一',
                  '周二',
                  '周三',
                  '周四',
                  '周五',
                  '周六',
                  '周日',
                ])
                  Expanded(
                    child: Center(
                      child: Text(
                        label,
                        style: TextStyle(
                          color: colorScheme.onSurfaceVariant,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            for (var weekStart = 0; weekStart < allDates.length; weekStart += 7)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final date in allDates.skip(weekStart).take(7))
                      Expanded(
                        child: _buildDayCell(
                          date,
                          maxMagnitude,
                          isCurrentMonth:
                              date.month == month.month &&
                              date.year == month.year,
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildDayCell(
    DateTime date,
    int maxMagnitude, {
    required bool isCurrentMonth,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final selected = dateKey(date) == dateKey(_selectedDate);
    final amount = _valueForDate(date);
    final backgroundColor = amount == null || amount == 0 || maxMagnitude == 0
        ? colorScheme.surfaceContainerLow
        : _metricColor(
            amount,
            colorScheme,
          ).withValues(alpha: 0.1 + 0.42 * amount.abs() / maxMagnitude);
    final textColor = isCurrentMonth
        ? colorScheme.onSurface
        : colorScheme.onSurfaceVariant.withValues(alpha: 0.55);
    return Padding(
      padding: const EdgeInsets.all(2),
      child: Material(
        color: colorScheme.surface.withValues(alpha: 0),
        child: InkWell(
          key: ValueKey('finance-calendar-day-${dateKey(date)}'),
          borderRadius: BorderRadius.circular(14),
          onTap: () => _selectDate(date),
          child: Container(
            height: 64,
            decoration: BoxDecoration(
              color: backgroundColor,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: selected
                    ? colorScheme.primary
                    : colorScheme.surface.withValues(alpha: 0),
                width: selected ? 1.8 : 0,
              ),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 5),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '${date.day}',
                  style: TextStyle(
                    color: textColor,
                    fontSize: 14,
                    fontWeight: selected || dateKey(date) == todayKey
                        ? FontWeight.w800
                        : FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 3),
                if (amount != null && amount != 0)
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      formatFinanceAmount(amount, withSymbol: false),
                      maxLines: 1,
                      style: TextStyle(
                        color: _metricColor(amount, colorScheme),
                        fontSize: 9.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  )
                else
                  const SizedBox(height: 11),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _selectDate(DateTime date) {
    final normalized = DateTime(date.year, date.month, date.day);
    setState(() => _selectedDate = normalized);
    if (normalized.year != month.year || normalized.month != month.month) {
      widget.onMonthChanged(DateTime(normalized.year, normalized.month));
    }
  }

  Widget _buildMonthlySummary(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final summary = _monthSummary;
    final currentMonth = DateTime(now.year, now.month) == month;
    final plannedMonth = month.isAfter(DateTime(now.year, now.month));
    final periodBalance = summary.balanceMinor;
    final latestDate = currentMonth
        ? DateTime(now.year, now.month, now.day)
        : DateTime(month.year, month.month + 1, 0);
    final balance = _balanceAt(latestDate);
    final firstValue = switch (_metric) {
      _FinanceCalendarMetric.expense => summary.netExpenseMinor,
      _FinanceCalendarMetric.income => summary.incomeMinor,
      _FinanceCalendarMetric.cashflow => periodBalance,
      _FinanceCalendarMetric.balance => periodBalance,
    };
    final firstLabel = switch (_metric) {
      _FinanceCalendarMetric.expense => plannedMonth ? '计划净支出' : '月净支出',
      _FinanceCalendarMetric.income => plannedMonth ? '计划收入' : '月收入',
      _FinanceCalendarMetric.cashflow => plannedMonth ? '计划收支' : '月收支',
      _FinanceCalendarMetric.balance => plannedMonth ? '计划收支' : '月收支',
    };
    final secondValue = switch (_metric) {
      _FinanceCalendarMetric.expense => _averagePerDay(summary.netExpenseMinor),
      _FinanceCalendarMetric.income => _averagePerDay(summary.incomeMinor),
      _FinanceCalendarMetric.cashflow => _averagePerDay(periodBalance),
      _FinanceCalendarMetric.balance => balance,
    };
    final secondLabel = switch (_metric) {
      _FinanceCalendarMetric.expense => '日均净支出',
      _FinanceCalendarMetric.income => '日均收入',
      _FinanceCalendarMetric.cashflow => '日均收支',
      _FinanceCalendarMetric.balance =>
        currentMonth
            ? '当前结余'
            : plannedMonth
            ? '预计结余'
            : '月末结余',
    };
    return Card(
      color: colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Expanded(
              child: _summaryMetric(
                context,
                firstLabel,
                firstValue,
                colorScheme,
                useErrorColor:
                    _metric == _FinanceCalendarMetric.expense ||
                    ((_metric == _FinanceCalendarMetric.cashflow ||
                            _metric == _FinanceCalendarMetric.balance) &&
                        firstValue < 0),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _summaryMetric(
                context,
                secondLabel,
                secondValue,
                colorScheme,
                useErrorColor:
                    _metric == _FinanceCalendarMetric.expense ||
                    ((_metric == _FinanceCalendarMetric.cashflow ||
                            _metric == _FinanceCalendarMetric.balance) &&
                        (secondValue ?? 0) < 0),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _summaryMetric(
    BuildContext context,
    String label,
    int? value,
    ColorScheme colorScheme, {
    bool useErrorColor = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(label, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 4),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            value == null ? '暂无余额数据' : formatFinanceAmount(value),
            style: TextStyle(
              color: value == null
                  ? colorScheme.onSurfaceVariant
                  : useErrorColor
                  ? colorScheme.error
                  : colorScheme.primary,
              fontWeight: FontWeight.w800,
              fontSize: 17,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSelectedDayHeader(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final summary = _summaryForDate(_selectedDate);
    final value = _valueForDate(_selectedDate);
    final dateLabel = '${_selectedDate.month}月${_selectedDate.day}日账单';
    final valueLabel = _metric == _FinanceCalendarMetric.balance
        ? '结余 ${value == null ? '暂无' : formatFinanceAmount(value)}'
        : '$_metricLabel ${value == null ? '暂无' : formatFinanceAmount(value)}';
    return Row(
      children: [
        Expanded(
          child: Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            children: [
              Text(
                dateLabel,
                style: Theme.of(context).textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              Text(
                valueLabel,
                style: TextStyle(
                  color: _metricColor(value ?? 0, colorScheme),
                  fontSize: 13,
                ),
              ),
              if (_metric == _FinanceCalendarMetric.balance)
                Text(
                  '${summary.transactionCount} 笔',
                  style: TextStyle(
                    color: colorScheme.onSurfaceVariant,
                    fontSize: 12,
                  ),
                ),
            ],
          ),
        ),
        TextButton.icon(
          key: const ValueKey('finance-calendar-add-entry'),
          onPressed: widget.onAdd == null
              ? null
              : () => widget.onAdd!(_selectedDate, _addActionKey),
          icon: const Icon(Icons.add, size: 18),
          label: const Text('记一笔'),
        ),
      ],
    );
  }

  List<Widget> _buildSelectedDayTransactions(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final items = _transactionsForDate(_selectedDate)
      ..sort((left, right) {
        final timeOrder = right.balanceEventAt().compareTo(
          left.balanceEventAt(),
        );
        return timeOrder != 0 ? timeOrder : right.uuid.compareTo(left.uuid);
      });
    if (items.isEmpty) {
      return [
        Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 22),
            child: Row(
              children: [
                Icon(Icons.receipt_long_outlined, color: colorScheme.outline),
                const SizedBox(width: 12),
                const Expanded(child: Text('这一天还没有账单')),
              ],
            ),
          ),
        ),
      ];
    }
    return [
      Card(
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            for (var index = 0; index < items.length; index++) ...[
              if (index > 0)
                Divider(
                  height: 1,
                  indent: 68,
                  color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                ),
              _buildTransactionTile(context, items[index]),
            ],
          ],
        ),
      ),
    ];
  }

  Widget _buildTransactionTile(
    BuildContext context,
    FinanceTransaction transaction,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    final category = widget.categories[transaction.categoryUuid];
    final categoryName = financeCategoryReferenceDisplayName(
      transaction.categoryUuid,
      widget.categories.values,
    );
    final merchant = transaction.merchant?.trim();
    final note = transaction.note?.trim();
    final title = merchant?.isNotEmpty == true
        ? merchant!
        : note?.isNotEmpty == true
        ? note!
        : categoryName;
    final time = transaction.occurrenceLocalTime;
    final future = transaction.balanceEventAt() > now.millisecondsSinceEpoch;
    final subtitle = [
      if (future) '待发生',
      transaction.type.label,
      if (title != categoryName) categoryName,
      if (time != null)
        '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}',
    ].join(' · ');
    final sourceKey = GlobalKey(
      debugLabel: 'finance-calendar-${transaction.uuid}',
    );
    return ListTile(
      key: ValueKey('finance-calendar-transaction-${transaction.uuid}'),
      onTap: widget.onOpenTransaction == null
          ? null
          : () => widget.onOpenTransaction!(transaction, sourceKey),
      leading: CircleAvatar(
        backgroundColor: colorScheme.secondaryContainer,
        child: Text(category?.icon ?? '💰'),
      ),
      title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: Text(
        formatSignedFinanceAmount(transaction.amountMinor, transaction.type),
        style: TextStyle(
          color: transaction.type == FinanceTransactionType.expense
              ? colorScheme.error
              : colorScheme.primary,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  List<FinanceTransaction> _transactionsForDate(DateTime date) {
    final key = dateKey(date);
    final nextDay = financeCalendarDayOffset(date, 1);
    final dayEndAt = nextDay.millisecondsSinceEpoch - 1;
    final asOfAt = dateKey(date).compareTo(todayKey) > 0
        ? dayEndAt
        : (dayEndAt < now.millisecondsSinceEpoch
              ? dayEndAt
              : now.millisecondsSinceEpoch);
    return widget.transactions
        .where((transaction) {
          if (transaction.transactionDate != key ||
              !_selectedTypes.contains(transaction.type)) {
            return false;
          }
          if (_selectedCategoryUuids.isNotEmpty &&
              !_selectedCategoryUuids.contains(transaction.categoryUuid)) {
            return false;
          }
          return transaction.balanceEventAt() <= asOfAt;
        })
        .toList(growable: true);
  }

  FinanceSummary get _monthSummary {
    final fromKey = dateKey(month);
    final toKey = dateKey(DateTime(month.year, month.month + 1));
    final nowAt = now.millisecondsSinceEpoch;
    final currentMonth = month.year == now.year && month.month == now.month;
    final items = widget.transactions.where((transaction) {
      if (transaction.transactionDate.compareTo(fromKey) < 0 ||
          transaction.transactionDate.compareTo(toKey) >= 0 ||
          !_selectedTypes.contains(transaction.type)) {
        return false;
      }
      if (_selectedCategoryUuids.isNotEmpty &&
          !_selectedCategoryUuids.contains(transaction.categoryUuid)) {
        return false;
      }
      return true;
    });
    return FinanceSummary.fromTransactions(
      items,
      asOfAt: currentMonth ? nowAt : null,
    );
  }

  FinanceSummary _summaryForDate(DateTime date) =>
      FinanceSummary.fromTransactions(_transactionsForDate(date));

  int _averagePerDay(int amountMinor) {
    final currentMonth = month.year == now.year && month.month == now.month;
    final days = currentMonth
        ? now.day
        : DateTime(month.year, month.month + 1, 0).day;
    return amountMinor ~/ (days == 0 ? 1 : days);
  }

  int? _valueForDate(DateTime date) {
    if (_metric == _FinanceCalendarMetric.balance) return _balanceAt(date);
    final summary = _summaryForDate(date);
    return switch (_metric) {
      _FinanceCalendarMetric.expense => summary.netExpenseMinor,
      _FinanceCalendarMetric.income => summary.incomeMinor,
      _FinanceCalendarMetric.cashflow => summary.balanceMinor,
      _FinanceCalendarMetric.balance => _balanceAt(date),
    };
  }

  int? _balanceAt(DateTime date) {
    final nextDay = financeCalendarDayOffset(date, 1);
    var asOfAt = nextDay.millisecondsSinceEpoch - 1;
    if (dateKey(date).compareTo(todayKey) >= 0 &&
        asOfAt > now.millisecondsSinceEpoch &&
        dateKey(date) == todayKey) {
      asOfAt = now.millisecondsSinceEpoch;
    }
    return FinanceRepository.cumulativeBalanceAt(
      events: widget.cumulativeBalanceEvents,
      asOfAt: asOfAt,
      openingBalanceMinor: widget.openingBalanceMinor,
      openingBalanceStartDate: widget.openingBalanceStartDate,
    );
  }

  Color _metricColor(int amount, ColorScheme colorScheme) {
    return switch (_metric) {
      _FinanceCalendarMetric.expense =>
        amount < 0 ? colorScheme.primary : colorScheme.error,
      _FinanceCalendarMetric.income => colorScheme.primary,
      _FinanceCalendarMetric.cashflow =>
        amount < 0 ? colorScheme.error : colorScheme.primary,
      _FinanceCalendarMetric.balance =>
        amount < 0 ? colorScheme.error : colorScheme.tertiary,
    };
  }

  String get _metricLabel => switch (_metric) {
    _FinanceCalendarMetric.expense => '净支出',
    _FinanceCalendarMetric.income => '收入',
    _FinanceCalendarMetric.cashflow => '收支',
    _FinanceCalendarMetric.balance => '结余',
  };
}
