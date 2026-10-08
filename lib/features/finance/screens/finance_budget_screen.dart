import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/finance_models.dart';
import '../services/finance_repository.dart';
import '../services/finance_storage.dart';
import '../services/finance_sync_service.dart';
import '../widgets/finance_management_widgets.dart';
import '../../../widgets/floating_glass_control.dart';
import 'finance_budget_entry_screen.dart';
import '../../../utils/app_dialogs.dart';

class FinanceBudgetScreen extends StatefulWidget {
  final DateTime? initialMonth;
  final DateTime Function() clock;

  const FinanceBudgetScreen({
    super.key,
    this.initialMonth,
    this.clock = DateTime.now,
  });

  @override
  State<FinanceBudgetScreen> createState() => _FinanceBudgetScreenState();
}

class _FinanceBudgetScreenState extends State<FinanceBudgetScreen> {
  late DateTime _month;
  List<FinanceBudget> _budgets = const [];
  List<FinanceBudget> _balanceSnapshots = const [];
  List<FinanceCategory> _categories = const [];
  List<FinancePaymentMethod> _paymentMethods = const [];
  List<FinanceTransaction> _transactions = const [];
  List<FinanceTransaction> _balanceTransactions = const [];
  List<FinanceLoanInstallment> _loanRepayments = const [];
  Set<String> _loanInterestTransactionUuids = const {};
  bool? _balanceSyncSupported;
  FinanceSummary _summary = const FinanceSummary();
  bool _isLoading = true;
  String? _loadError;
  int _loadGeneration = 0;
  Timer? _balanceRefreshTimer;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialMonth ?? widget.clock();
    _month = DateTime(initial.year, initial.month);
    FinanceStorage.revision.addListener(_onFinanceChanged);
    _load();
  }

  @override
  void dispose() {
    _balanceRefreshTimer?.cancel();
    FinanceStorage.revision.removeListener(_onFinanceChanged);
    super.dispose();
  }

  void _onFinanceChanged() => _load(showLoading: false);

  Map<String, FinanceCategory> get _categoryMap => {
    for (final item in _categories) item.uuid: item,
  };

  FinanceBudget? get _overallBudget {
    for (final budget in _budgets) {
      if (budget.isOverall) return budget;
    }
    return null;
  }

  List<FinanceBudget> get _categoryBudgets => _budgets
      .where((budget) => !budget.isPaymentMethod && budget.categoryUuid != null)
      .toList();

  List<FinanceBudget> get _paymentBudgets {
    if (_isFutureMonth) return const [];
    return _latestPaymentSnapshots(_balanceSnapshots, _balanceAsOfAt);
  }

  Map<String, FinancePaymentMethod> get _paymentMethodMap => {
    for (final method in _paymentMethods) method.uuid: method,
  };

  bool get _isFutureMonth {
    final now = widget.clock();
    return _month.isAfter(DateTime(now.year, now.month));
  }

  bool get _isCurrentMonth {
    final now = widget.clock();
    return _month.year == now.year && _month.month == now.month;
  }

  String get _monthLabel =>
      _isCurrentMonth ? '本月' : DateFormat('yyyy年M月').format(_month);

  String get _paymentBalanceSectionTitle {
    if (_isCurrentMonth) return '付款方式实时余额';
    if (_isFutureMonth) return '付款方式余额';
    return '月末付款方式余额';
  }

  int get _balanceAsOfAt {
    if (_isCurrentMonth) return widget.clock().millisecondsSinceEpoch;
    return DateTime(_month.year, _month.month + 1).millisecondsSinceEpoch - 1;
  }

  List<FinanceBudget> _latestPaymentSnapshots(
    Iterable<FinanceBudget> budgets,
    int asOfAt,
  ) {
    final snapshots = FinanceRepository.latestPaymentBalanceSnapshots(
      budgets,
      asOfAt: asOfAt,
      nowAt: widget.clock().millisecondsSinceEpoch,
    ).toList()
      ..sort((left, right) => _budgetTitle(left).compareTo(_budgetTitle(right)));
    return snapshots;
  }

  Future<void> _load({bool showLoading = true}) async {
    _balanceRefreshTimer?.cancel();
    _balanceRefreshTimer = null;
    final generation = ++_loadGeneration;
    if (mounted && showLoading) {
      setState(() {
        _isLoading = true;
        _loadError = null;
      });
    }
    try {
      final month = _month;
      final from = DateTime(month.year, month.month);
      final to = DateTime(month.year, month.month + 1);
      final now = widget.clock();
      final isCurrentMonth =
          month.year == now.year && month.month == now.month;
      final asOfAt = isCurrentMonth
          ? now.millisecondsSinceEpoch
          : to.millisecondsSinceEpoch - 1;
      final values = await Future.wait<dynamic>([
        FinanceRepository.getBudgets(),
        FinanceRepository.getCategories(
          type: FinanceCategoryType.expense,
          includeArchived: true,
        ),
        FinanceRepository.getPaymentMethods(includeArchived: true),
        FinanceRepository.getTransactions(from: from, to: to),
        FinanceRepository.getPaidLoanInstallments(),
        FinanceSyncService.balanceSyncSupport(),
      ]);
      final allBudgets = values[0] as List<FinanceBudget>;
      final balanceSnapshots = allBudgets
          .where((budget) => budget.isPaymentMethod)
          .toList(growable: false);
      final applicableSnapshots = month.isAfter(
        DateTime(now.year, now.month),
      )
          ? const <FinanceBudget>[]
          : _latestPaymentSnapshots(balanceSnapshots, asOfAt);
      final earliestSnapshotAt = applicableSnapshots
          .map((budget) => budget.effectiveBalanceSnapshotAt)
          .fold<int?>(null, (current, value) {
            if (current == null || value < current) return value;
            return current;
          });
      final balanceTransactions = earliestSnapshotAt == null
          ? const <FinanceTransaction>[]
          : await FinanceRepository.getBalanceTransactions(
              snapshotAt: earliestSnapshotAt,
              before: to,
              paymentMethodUuids: applicableSnapshots
                  .map((budget) => budget.paymentMethodUuid!)
                  .toSet(),
            );
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _budgets = allBudgets
            .where((budget) => budget.monthKey == financeMonthKey(month))
            .toList(growable: false);
        _balanceSnapshots = balanceSnapshots;
        _categories = values[1] as List<FinanceCategory>;
        _paymentMethods = values[2] as List<FinancePaymentMethod>;
        _transactions = values[3] as List<FinanceTransaction>;
        _balanceTransactions = balanceTransactions;
        _loanRepayments = values[4] as List<FinanceLoanInstallment>;
        _loanInterestTransactionUuids = _loanRepayments
            .map((item) => item.interestTransactionUuid)
            .whereType<String>()
            .toSet();
        _balanceSyncSupported = values[5] as bool?;
        _summary = _summaryForCurrentView();
        _isLoading = false;
        _loadError = null;
      });
      _scheduleBalanceRefresh();
    } catch (error) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _isLoading = false;
        _loadError = error.toString();
      });
    }
  }

  void _scheduleBalanceRefresh() {
    _balanceRefreshTimer?.cancel();
    _balanceRefreshTimer = null;
    if (!mounted) return;

    final currentDate = widget.clock();
    final currentMonth = DateTime(currentDate.year, currentDate.month);
    if (_month.isBefore(currentMonth)) return;

    final snapshotsByMethod = {
      for (final budget in _paymentBudgets)
        budget.paymentMethodUuid!: budget.effectiveBalanceSnapshotAt,
    };

    final now = currentDate.millisecondsSinceEpoch;
    final monthStart = DateTime(_month.year, _month.month);
    final nextMonthAt = DateTime(
      _month.year,
      _month.month + 1,
    ).millisecondsSinceEpoch;
    final monthEndAt = nextMonthAt - 1;
    // Refresh when a future selected month starts, or when the current month
    // ends, even if there are no scheduled finance events.
    final refreshDataAtMonthStart = monthStart.isAfter(currentMonth);
    int? nextEventAt = refreshDataAtMonthStart
        ? monthStart.millisecondsSinceEpoch
        : nextMonthAt;
    for (final transaction in _transactions) {
      final eventAt = _balanceEventTime(transaction);
      if (eventAt <= now ||
          eventAt > monthEndAt ||
          (nextEventAt != null && eventAt >= nextEventAt)) {
        continue;
      }
      nextEventAt = eventAt;
    }
    for (final transaction in _balanceTransactions) {
      final paymentMethodUuid = transaction.paymentMethodUuid;
      final snapshotAt = snapshotsByMethod[paymentMethodUuid];
      if (paymentMethodUuid == null || snapshotAt == null) continue;
      final eventAt = _balanceEventTime(
        transaction,
        snapshotAt: snapshotAt,
      );
      if (eventAt <= snapshotAt) continue;
      final eligibleAt = eventAt;
      if (eligibleAt <= now ||
          eligibleAt > monthEndAt ||
          (nextEventAt != null && eligibleAt >= nextEventAt)) {
        continue;
      }
      nextEventAt = eligibleAt;
    }
    for (final repayment in _loanRepayments) {
      final snapshotAt = snapshotsByMethod[repayment.paymentMethodUuid];
      final paidAt = repayment.paidAt;
      if (snapshotAt == null || paidAt == null) continue;
      // Match paymentMethodBalanceAt: picker precision can put a repayment's
      // paidAt in the same minute as a balance snapshot even though the
      // repayment was recorded later. Refresh when that record becomes active.
      final eventAt = paidAt <= snapshotAt &&
              paidAt ~/ 60000 == snapshotAt ~/ 60000 &&
              repayment.updatedAt > snapshotAt
          ? repayment.updatedAt
          : paidAt;
      if (eventAt <= snapshotAt ||
          eventAt <= now ||
          eventAt > monthEndAt ||
          (nextEventAt != null && eventAt >= nextEventAt)) {
        continue;
      }
      nextEventAt = eventAt;
    }
    if (nextEventAt == null) return;

    final delay = Duration(
      milliseconds: math
          .max(1, nextEventAt - now + 1)
          .clamp(1, const Duration(days: 24).inMilliseconds)
          .toInt(),
    );
    _balanceRefreshTimer = Timer(delay, () {
      if (!mounted) return;
      if (refreshDataAtMonthStart) {
        unawaited(_load(showLoading: false));
        return;
      }
      setState(() => _summary = _summaryForCurrentView());
      _scheduleBalanceRefresh();
    });
  }

  Future<void> _openEditor([
    FinanceBudget? budget,
    String? paymentMethodUuid,
  ]) async {
    final editorMonth = budget?.isPaymentMethod == true
        ? DateFormat('yyyy-MM').parseStrict(budget!.monthKey)
        : _month;
    final result = await Navigator.of(context).push<FinanceBudget>(
      MaterialPageRoute(
        builder: (_) => FinanceBudgetEntryScreen(
          month: editorMonth,
          budget: budget,
          initialPaymentMethodUuid: paymentMethodUuid,
        ),
      ),
    );
    if (result != null && mounted) await _load();
  }

  Future<void> _choosePaymentMethodForBudget() async {
    if (_isFutureMonth) {
      AppSnackBars.showSnackBar(
        context,
        const SnackBar(content: Text('余额对应时间不能在未来，请先切换到当前或历史月份')),
      );
      return;
    }
    final methods = _paymentMethods
        .where((method) => !method.isArchived && !method.isDeleted)
        .toList(growable: false);
    if (methods.isEmpty) {
      AppSnackBars.showSnackBar(
        context,
        const SnackBar(content: Text('请先添加或恢复一个付款方式')),
      );
      return;
    }
    final paymentMethodUuid = await showAppModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
              child: Text(
                '选择付款方式',
                style: Theme.of(context).textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            for (final method in methods)
              ListTile(
                leading: Text(method.icon),
                title: Text(method.name),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).pop(method.uuid),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (paymentMethodUuid == null || !mounted) return;
    FinanceBudget? existing;
    for (final budget in _budgets) {
      if (budget.isPaymentMethod &&
          budget.paymentMethodUuid == paymentMethodUuid) {
        existing = budget;
        break;
      }
    }
    await _openEditor(existing, paymentMethodUuid);
  }

  Future<void> _deleteBudget(FinanceBudget budget) async {
    final itemName = budget.isPaymentMethod ? '付款方式余额' : '预算';
    final warning = budget.isPaymentMethod
        ? '删除这条余额快照后，会按更早的余额快照和账单重新计算；如果没有更早快照，该付款方式将不再显示余额。已有账单不会删除。'
        : '删除预算记录不会影响已有账单。';
    final confirmed = await showAppDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('删除$itemName？'),
        content: Text(warning),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await FinanceRepository.deleteBudget(budget.uuid);
    } catch (error) {
      if (!mounted) return;
      AppSnackBars.showSnackBar(
        context,
        SnackBar(content: Text('删除$itemName失败：$error')),
      );
      return;
    }
    if (!mounted) return;
    AppSnackBars.showSnackBar(context, SnackBar(content: Text('$itemName已删除')));
    await _load();
  }

  void _changeMonth(int delta) {
    if (!_canChangeMonth(delta)) return;
    setState(() => _month = DateTime(_month.year, _month.month + delta));
    _load();
  }

  bool _canChangeMonth(int delta) {
    final nextMonth = DateTime(_month.year, _month.month + delta);
    final firstAllowedMonth = DateTime(2000);
    final lastAllowedDate = widget.clock().add(const Duration(days: 3650));
    final lastAllowedMonth =
        DateTime(lastAllowedDate.year, lastAllowedDate.month);
    return !nextMonth.isBefore(firstAllowedMonth) &&
        !nextMonth.isAfter(lastAllowedMonth);
  }

  void _showCurrentMonth() {
    final now = widget.clock();
    setState(() => _month = DateTime(now.year, now.month));
    _load();
  }

  Future<void> _pickMonth() async {
    final picked = await showAppDatePicker(
      context: context,
      initialDate: _month,
      firstDate: DateTime(2000),
      lastDate: widget.clock().add(const Duration(days: 3650)),
      helpText: '选择预算月份',
    );
    if (picked == null || !mounted) return;
    setState(() => _month = DateTime(picked.year, picked.month));
    await _load();
  }

  int _usedFor(FinanceBudget budget) {
    if (budget.paymentMethodUuid != null) {
      return budget.amountMinor - FinanceRepository.paymentMethodBalanceAt(
        snapshot: budget,
        transactions: _balanceTransactions,
        loanRepayments: _loanRepayments,
        loanInterestTransactionUuids: _loanInterestTransactionUuids,
        asOfAt: _balanceAsOfAt,
      );
    }
    return _summary.spendingForBudget(budget, _categories);
  }

  int _balanceEventTime(
    FinanceTransaction transaction, {
    int? snapshotAt,
  }) {
    return transaction.balanceEventAt(snapshotAt: snapshotAt);
  }

  FinanceSummary _summaryForCurrentView([int? asOfAt]) {
    if (!_isCurrentMonth) {
      return FinanceRepository.summarizeTransactions(_transactions);
    }
    final cutoff = asOfAt ?? _balanceAsOfAt;
    return FinanceSummary.fromTransactions(
      _transactions,
      asOfAt: cutoff,
    );
  }

  String _budgetTitle(FinanceBudget budget) {
    if (budget.isOverall) return '全部支出';
    if (budget.paymentMethodUuid != null) {
      final paymentMethod = _paymentMethodMap[budget.paymentMethodUuid];
      if (paymentMethod == null) return '已归档或未知付款方式';
      return '${paymentMethod.name}${paymentMethod.isArchived ? '（已归档）' : ''}';
    }
    final category = _categoryMap[budget.categoryUuid];
    return category == null
        ? '已归档或未知分类'
        : '${financeCategoryDisplayName(category, _categories)}${category.isArchived ? '（已归档）' : ''}';
  }

  String _budgetIcon(FinanceBudget budget) {
    if (budget.isOverall) return '🎯';
    if (budget.paymentMethodUuid != null) {
      return _paymentMethodMap[budget.paymentMethodUuid]?.icon ?? '💼';
    }
    return _categoryMap[budget.categoryUuid]?.icon ?? '🗃️';
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final topBarHeight = floatingGlassTopBarHeight(context);
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: FloatingGlassAppBar(
        flexibleSpace: const FloatingGlassTopBarBackground(),
        title: const Text('预算与付款余额'),
      ),
      body: FloatingGlassTopBarContentFade(
        topBarHeight: topBarHeight,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _loadError != null
            ? _buildError(colorScheme)
            : RefreshIndicator(
                onRefresh: _load,
                child: FinancePageList(
                  topPadding: topBarHeight,
                  bottomPadding: 112,
                  children: [
                    _buildMonthBar(colorScheme),
                    const SizedBox(height: 8),
                    _buildSummaryCard(colorScheme),
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '总额与分类预算',
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                        ),
                        Text(
                          '${_budgets.where((budget) => !budget.isPaymentMethod).length} 项',
                          style: TextStyle(color: colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (_budgets
                        .where((budget) => !budget.isPaymentMethod)
                        .isEmpty)
                      _buildEmptyState(colorScheme)
                    else
                      FinanceAdaptiveFields(
                        minChildWidth: 330,
                        children: [
                          for (final budget in _budgets.where(
                            (budget) => !budget.isPaymentMethod,
                          ))
                            _buildBudgetCard(budget, colorScheme),
                        ],
                      ),
                    if (_budgets.any((budget) => !budget.isPaymentMethod) &&
                        _overallBudget == null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          '当前仅统计已设置分类预算的进度；想控制整月支出，可以再添加“全部支出”预算。',
                          style: TextStyle(
                            color: colorScheme.onSurfaceVariant,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            _paymentBalanceSectionTitle,
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                        ),
                        Text(
                          '${_paymentBudgets.length} 项',
                          style: TextStyle(color: colorScheme.onSurfaceVariant),
                        ),
                        const SizedBox(width: 4),
                        IconButton(
                          tooltip: '录入付款方式余额',
                          onPressed: _isFutureMonth
                              ? null
                              : _choosePaymentMethodForBudget,
                          icon: const Icon(Icons.add_circle_outline),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (_balanceSyncSupported == false) ...[
                      Text(
                        '当前服务暂不支持余额云同步，余额和还款账户保存在本机。',
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: colorScheme.onSurfaceVariant),
                      ),
                      const SizedBox(height: 8),
                    ],
                    if (_paymentBudgets.isEmpty)
                      _buildPaymentEmptyState(colorScheme)
                    else
                      FinanceAdaptiveFields(
                        minChildWidth: 330,
                        children: [
                          for (final budget in _paymentBudgets)
                            _buildBudgetCard(budget, colorScheme),
                        ],
                      ),
                  ],
                ),
              ),
      ),
      floatingActionButton: _isLoading || _loadError != null
          ? null
          : FloatingGlassActionButton.extended(
              onPressed: () => _openEditor(),
              icon: const Icon(Icons.add),
              label: const Text('新增预算'),
            ),
    );
  }

  Widget _buildMonthBar(ColorScheme colorScheme) {
    return Row(
      children: [
        IconButton(
          tooltip: '上个月',
          onPressed: _canChangeMonth(-1) ? () => _changeMonth(-1) : null,
          icon: const Icon(Icons.chevron_left),
        ),
        Expanded(
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: _pickMonth,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Flexible(
                    child: Text(
                      '${_month.year} 年 ${_month.month} 月',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    Icons.expand_more,
                    size: 18,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
        ),
        IconButton(
          tooltip: '下个月',
          onPressed: _canChangeMonth(1) ? () => _changeMonth(1) : null,
          icon: const Icon(Icons.chevron_right),
        ),
      ],
    );
  }

  Widget _buildSummaryCard(ColorScheme colorScheme) {
    final overall = _overallBudget;
    final categoryBudgets = _categoryBudgets;
    final summaryBudgets = FinanceBudget.nonOverlappingCategories(
      categoryBudgets,
      _categories,
    );
    final budgetTotal =
        overall?.amountMinor ??
        summaryBudgets.fold<int>(0, (sum, item) => sum + item.amountMinor);
    final used = overall == null
        ? summaryBudgets.fold<int>(0, (sum, item) => sum + _usedFor(item))
        : _usedFor(overall);
    final remaining = budgetTotal - used;
    final progress = budgetTotal == 0
        ? 0.0
        : (used / budgetTotal).clamp(0.0, 1.0).toDouble();
    final isOver = remaining < 0;
    final monthLabel = _monthLabel;
    final title = overall == null
        ? '$monthLabel分类预算合计'
        : '$monthLabel总预算';
    final subtitle = overall != null
        ? _isFutureMonth
            ? '根据$monthLabel待发生账单估算'
            : '所有支出按$monthLabel账单计算'
        : summaryBudgets.length < categoryBudgets.length
            ? '父子分类按大类汇总，细分类预算单独显示'
            : '只汇总已设置分类的预算';
    final remainingLabel = _isFutureMonth ? '计划剩余' : '剩余';
    final overBudgetLabel = _isFutureMonth ? '计划超出' : '已超支';
    final usedLabel = _isFutureMonth ? '计划使用' : '已使用';
    final foreground = isOver
        ? colorScheme.onErrorContainer
        : colorScheme.onPrimaryContainer;
    return FinanceSectionCard(
      color: isOver ? colorScheme.errorContainer : colorScheme.primaryContainer,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(color: foreground, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: foreground.withValues(alpha: 0.75)),
          ),
          const SizedBox(height: 16),
          Text(
            formatFinanceAmount(budgetTotal),
            style: Theme.of(context).textTheme.headlineLarge
                ?.copyWith(color: foreground, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Text(
            isOver
                ? '$overBudgetLabel ${formatFinanceAmount(-remaining)}'
                : '$remainingLabel ${formatFinanceAmount(remaining)}',
            style: TextStyle(color: foreground),
          ),
          const SizedBox(height: 20),
          LinearProgressIndicator(
            value: progress,
            minHeight: 8,
            borderRadius: BorderRadius.circular(8),
            color: foreground,
            backgroundColor: foreground.withValues(alpha: 0.14),
          ),
          const SizedBox(height: 10),
          Text(
            '$usedLabel ${formatFinanceAmount(used)} / ${formatFinanceAmount(budgetTotal)}',
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: foreground.withValues(alpha: 0.8)),
          ),
          if (overall != null && categoryBudgets.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              '分类预算独立统计，不叠加到总预算。',
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: foreground.withValues(alpha: 0.75)),
            ),
          ],
          if (_paymentBudgets.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              _isCurrentMonth
                  ? '付款方式实时余额单独显示，不计入总额和分类预算。'
                  : '余额按所选月份月末计算，不计入总额和分类预算。',
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: foreground.withValues(alpha: 0.75)),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildBudgetCard(FinanceBudget budget, ColorScheme colorScheme) {
    final used = _usedFor(budget);
    final remaining = budget.amountMinor - used;
    final isOver = remaining < 0;
    final usageLabel = _isFutureMonth
        ? '计划使用'
        : budget.isPaymentMethod
        ? (used < 0
            ? '录入后净增加'
            : used > 0
                ? '录入后净扣减'
                : '录入后余额不变')
        : '已使用';
    final snapshotAt = DateTime.fromMillisecondsSinceEpoch(
      budget.effectiveBalanceSnapshotAt,
    );
    final progress = budget.amountMinor == 0
        ? 0.0
        : (used / budget.amountMinor).clamp(0.0, 1.0).toDouble();
    final progressColor = isOver ? colorScheme.error : colorScheme.primary;
    return FinanceSectionCard(
      key: ValueKey('finance-budget-card-${budget.uuid}'),
      onTap: () => _openEditor(budget),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox.square(
                dimension: 36,
                child: FittedBox(
                  child: Text(
                    _budgetIcon(budget),
                    textScaler: TextScaler.noScaling,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _budgetTitle(budget),
                  style: Theme.of(context).textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              PopupMenuButton<String>(
                tooltip:
                    '${_budgetTitle(budget)}${budget.isPaymentMethod ? '余额' : '预算'}的更多操作',
                onSelected: (value) {
                  if (value == 'edit') _openEditor(budget);
                  if (value == 'delete') _deleteBudget(budget);
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'edit', child: Text('编辑')),
                  PopupMenuItem(value: 'delete', child: Text('移入回收站')),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          FinanceAdaptiveFields(
            minChildWidth: 150,
            children: [
              _budgetMetric(
                usageLabel,
                budget.isPaymentMethod ? used.abs() : used,
              ),
              _budgetMetric(
                budget.isPaymentMethod
                    ? '${DateFormat('yyyy年M月d日 HH:mm').format(snapshotAt)} 的余额'
                    : '预算额度',
                budget.amountMinor,
              ),
            ],
          ),
          if (!budget.isPaymentMethod) ...[
            const SizedBox(height: 18),
            LinearProgressIndicator(
              value: progress,
              minHeight: 7,
              borderRadius: BorderRadius.circular(8),
              backgroundColor: colorScheme.surfaceContainerHighest,
              color: progressColor,
            ),
          ],
          const SizedBox(height: 12),
          FinanceStatusBadge(
            label: budget.isPaymentMethod
                ? isOver
                      ? '${_isCurrentMonth ? '当前余额' : '该月余额'}不足 ${formatFinanceAmount(-remaining)}'
                      : '${_isCurrentMonth ? '当前余额' : '该月余额'} ${formatFinanceAmount(remaining)}'
                : isOver
                ? '${_isFutureMonth ? '计划超出' : '超支'} ${formatFinanceAmount(-remaining)}'
                : '${_isFutureMonth ? '计划剩余' : '剩余'} ${formatFinanceAmount(remaining)}',
            isError: isOver,
            highlighted: !isOver,
          ),
          if (budget.note?.isNotEmpty == true) ...[
            const SizedBox(height: 10),
            Text(
              budget.note!,
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: colorScheme.onSurfaceVariant),
            ),
          ],
        ],
      ),
    );
  }

  Widget _budgetMetric(String label, int amount) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall
              ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 4),
        Text(
          formatFinanceAmount(amount),
          style: Theme.of(context).textTheme.titleMedium
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
      ],
    );
  }

  Widget _buildEmptyState(ColorScheme colorScheme) {
    final monthLabel = _monthLabel;
    return FinanceEmptyState(
      icon: Icons.track_changes_outlined,
      title: '$monthLabel还没有预算',
      description: '设置总预算或分类额度，随时了解$monthLabel的支出预算。',
      actionLabel: '添加预算',
      onAction: () => _openEditor(),
    );
  }

  Widget _buildPaymentEmptyState(ColorScheme colorScheme) {
    return FinanceEmptyState(
      icon: Icons.account_balance_wallet_outlined,
      title: _isFutureMonth ? '未来月份不显示余额' : '还没有付款方式余额记录',
      description: _isFutureMonth
          ? '余额对应时间不能在未来；切换回当前月份后再记录。'
          : '填写余额并选择对应的日期和时刻；之后同账户账单会跨月连续更新，支出扣减，收入和退款加回。',
      actionLabel: _isFutureMonth ? '切换到当前月份' : '选择付款方式并录入余额',
      onAction: _isFutureMonth
          ? _showCurrentMonth
          : _choosePaymentMethodForBudget,
    );
  }

  Widget _buildError(ColorScheme colorScheme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: colorScheme.error),
            const SizedBox(height: 12),
            const Text('预算数据加载失败'),
            const SizedBox(height: 8),
            Text(
              _loadError ?? '',
              textAlign: TextAlign.center,
              style: TextStyle(color: colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh),
              label: const Text('重试'),
            ),
          ],
        ),
      ),
    );
  }
}
