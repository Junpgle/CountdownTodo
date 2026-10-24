import 'dart:async';

import 'package:flutter/material.dart';

import '../../../widgets/floating_glass_control.dart';
import '../models/finance_models.dart';
import '../services/finance_future_commitments_service.dart';
import '../services/finance_repository.dart';
import '../services/finance_storage.dart';
import '../widgets/finance_management_widgets.dart';
import 'finance_automation_screen.dart';
import 'finance_loan_screen.dart';
import 'finance_transaction_detail_screen.dart';

typedef FinanceFutureCommitmentLoader =
    Future<FinanceFutureCommitmentForecast> Function(DateTime now, int months);
typedef FinancePaymentMethodsLoader =
    Future<List<FinancePaymentMethod>> Function();
typedef FinanceCategoriesLoader = Future<List<FinanceCategory>> Function();

class FinanceFutureCommitmentsScreen extends StatefulWidget {
  final DateTime Function() clock;
  final FinanceFutureCommitmentLoader? loader;
  final FinancePaymentMethodsLoader? paymentMethodsLoader;
  final FinanceCategoriesLoader? categoriesLoader;

  const FinanceFutureCommitmentsScreen({
    super.key,
    this.clock = DateTime.now,
    this.loader,
    this.paymentMethodsLoader,
    this.categoriesLoader,
  });

  @override
  State<FinanceFutureCommitmentsScreen> createState() =>
      _FinanceFutureCommitmentsScreenState();
}

class _FinanceFutureCommitmentsScreenState
    extends State<FinanceFutureCommitmentsScreen>
    with WidgetsBindingObserver {
  int _horizonMonths = 3;
  int _loadGeneration = 0;
  FinanceFutureCommitmentForecast? _forecast;
  List<FinancePaymentMethod> _paymentMethods = const [];
  List<FinanceCategory> _categories = const [];
  bool _isLoading = true;
  String? _loadError;
  Timer? _revisionRefreshTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    FinanceStorage.revision.addListener(_onFinanceChanged);
    _load();
  }

  @override
  void dispose() {
    _revisionRefreshTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    FinanceStorage.revision.removeListener(_onFinanceChanged);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      unawaited(_load(showLoading: false));
    }
  }

  void _onFinanceChanged() {
    _revisionRefreshTimer?.cancel();
    _revisionRefreshTimer = Timer(const Duration(milliseconds: 100), () {
      _revisionRefreshTimer = null;
      if (mounted) unawaited(_load(showLoading: false));
    });
  }

  Future<FinanceFutureCommitmentForecast> _read(DateTime now, int months) =>
      widget.loader?.call(now, months) ??
      FinanceFutureCommitmentsService.read(now: now, horizonMonths: months);

  Future<void> _load({bool showLoading = true}) async {
    final generation = ++_loadGeneration;
    if (mounted && showLoading) {
      setState(() {
        _isLoading = true;
        _loadError = null;
      });
    }
    try {
      final forecast = await _read(widget.clock(), _horizonMonths);
      List<FinancePaymentMethod> methods = const [];
      try {
        methods =
            await (widget.paymentMethodsLoader?.call() ??
                FinanceRepository.getPaymentMethods(includeArchived: true));
      } catch (_) {
        // Payment method names are supplementary; keep the forecast usable.
      }
      List<FinanceCategory> categories = const [];
      try {
        categories =
            await (widget.categoriesLoader?.call() ??
                FinanceRepository.getCategories(
                  includeArchived: true,
                  includeDeleted: true,
                ));
      } catch (_) {
        // Category names are supplementary; keep the forecast usable.
      }
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _forecast = forecast;
        _paymentMethods = methods;
        _categories = categories;
        _isLoading = false;
        _loadError = null;
      });
    } catch (error) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _isLoading = false;
        _loadError = error.toString();
      });
    }
  }

  Future<void> _selectHorizon(int months) async {
    if (months == _horizonMonths) return;
    setState(() {
      _horizonMonths = months;
      _isLoading = true;
      _loadError = null;
    });
    await _load(showLoading: false);
  }

  Future<void> _openRecurringRule() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const FinanceAutomationScreen()));
    if (mounted) await _load(showLoading: false);
  }

  Future<void> _openLoan(FinanceLoan loan) async {
    final forecast = _forecast;
    final loans = <String, FinanceLoan>{};
    for (final item in [
      ...?forecast?.commitments,
      ...?forecast?.overdueLoanInstallments,
    ]) {
      final itemLoan = item.loan;
      if (itemLoan != null) loans[itemLoan.uuid] = itemLoan;
    }
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => FinanceLoanDetailScreen(
          loan: loan,
          loanDisplayName: financeLoanDisplayName(loan, loans.values),
          clock: widget.clock,
        ),
      ),
    );
    if (mounted) await _load(showLoading: false);
  }

  Future<void> _openTransaction(FinanceTransaction transaction) async {
    final category = _categories
        .where((item) => item.uuid == transaction.categoryUuid)
        .firstOrNull;
    final paymentMethod = _paymentMethods
        .where((item) => item.uuid == transaction.paymentMethodUuid)
        .firstOrNull;
    await Navigator.of(context).push<FinanceTransaction>(
      MaterialPageRoute(
        builder: (_) => FinanceTransactionDetailScreen(
          transaction: transaction,
          category: category,
          categoryDisplayName: financeCategoryReferenceDisplayName(
            transaction.categoryUuid,
            _categories,
          ),
          paymentMethod: paymentMethod,
          paymentMethods: _paymentMethods,
        ),
      ),
    );
    if (mounted) await _load(showLoading: false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: FloatingGlassAppBar(
        flexibleSpace: const FloatingGlassTopBarBackground(),
        title: const Text('未来收支'),
        actions: [
          IconButton(
            tooltip: '刷新',
            onPressed: () => _load(),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _loadError != null
          ? FinancePageList(
              children: [
                FinanceEmptyState(
                  icon: Icons.cloud_off_outlined,
                  title: '未来收支加载失败',
                  description: '本地规则或还款计划暂时无法读取。\n$_loadError',
                  actionLabel: '重新加载',
                  onAction: () => _load(),
                ),
              ],
            )
          : RefreshIndicator(
              onRefresh: () => _load(showLoading: false),
              child: _buildContent(_forecast!),
            ),
    );
  }

  Widget _buildContent(FinanceFutureCommitmentForecast forecast) {
    final months = List<DateTime>.generate(
      forecast.horizonMonths,
      (index) => DateTime(forecast.now.year, forecast.now.month + index),
    );
    return FinancePageList(
      children: [
        const FinancePageIntro(
          icon: Icons.event_repeat_outlined,
          title: '已登记的未来安排',
          description: '汇总未来账单、周期规则和未还贷款计划；这是预计收支，不代表账户余额。',
        ),
        const SizedBox(height: 18),
        _buildHorizonSelector(),
        const SizedBox(height: 16),
        _buildRangeSummary(forecast),
        if (forecast.overdueLoanInstallments.isNotEmpty) ...[
          const SizedBox(height: 18),
          _buildOverdueSection(forecast.overdueLoanInstallments),
        ],
        for (final month in months) ...[
          const SizedBox(height: 18),
          _buildMonthSection(month, forecast),
        ],
        const SizedBox(height: 10),
        Text(
          '不同币种分别计算。标记“可能重复”的项目仍会分别计入合计，请核对后编辑账单或计划。',
          style: Theme.of(context).textTheme.bodySmall
              ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildHorizonSelector() {
    return SegmentedButton<int>(
      segments: const [
        ButtonSegment(value: 3, label: Text('3个月')),
        ButtonSegment(value: 6, label: Text('6个月')),
        ButtonSegment(value: 12, label: Text('12个月')),
      ],
      selected: {_horizonMonths},
      showSelectedIcon: false,
      onSelectionChanged: (selection) => _selectHorizon(selection.first),
    );
  }

  Widget _buildRangeSummary(FinanceFutureCommitmentForecast forecast) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final entries = forecast.totalsByCurrency.entries.toList()
      ..sort((left, right) => left.key.compareTo(right.key));
    return FinanceSectionCard(
      title: '未来${forecast.horizonMonths}个月合计',
      icon: Icons.account_balance_wallet_outlined,
      description: '从今天起，按币种分别汇总已登记项目。',
      child: entries.isEmpty
          ? Text(
              '当前范围内没有已登记的固定收支。',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            )
          : Column(
              children: [
                for (final entry in entries) ...[
                  if (entries.first.key != entry.key) const Divider(height: 24),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      entry.key,
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: colors.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  FinanceAdaptiveFields(
                    minChildWidth: 140,
                    maxColumns: 3,
                    spacing: 12,
                    children: [
                      _metric(
                        '预计流入',
                        _money(entry.value.inflowMinor, entry.key),
                      ),
                      _metric(
                        '预计支出',
                        _money(entry.value.outflowMinor, entry.key),
                      ),
                      _metric('预计净额', _money(entry.value.netMinor, entry.key)),
                    ],
                  ),
                ],
              ],
            ),
    );
  }

  Widget _metric(String label, String amount) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          amount,
          softWrap: true,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }

  Widget _buildOverdueSection(List<FinanceFutureCommitment> items) {
    final colors = Theme.of(context).colorScheme;
    return FinanceSectionCard(
      title: '逾期待还',
      icon: Icons.warning_amber_rounded,
      description: '${items.length} 期未还贷款，不计入未来月份小计。',
      color: colors.errorContainer.withValues(alpha: 0.45),
      child: Column(
        children: [
          for (var index = 0; index < items.length; index++) ...[
            if (index > 0) const Divider(height: 20),
            _buildCommitmentRow(items[index], overdue: true),
          ],
        ],
      ),
    );
  }

  Widget _buildMonthSection(
    DateTime month,
    FinanceFutureCommitmentForecast forecast,
  ) {
    final monthKey = financeMonthKey(month);
    final items = forecast.commitments
        .where((item) => financeMonthKey(item.dueAt) == monthKey)
        .toList(growable: false);
    final currencies = forecast.monthlyTotalsByCurrency[monthKey] ?? const {};
    final currencyKeys = currencies.keys.toList()..sort();
    final grouped = <String, List<FinanceFutureCommitment>>{};
    for (final item in items) {
      grouped.putIfAbsent(dateKey(item.dueAt), () => []).add(item);
    }
    final theme = Theme.of(context);
    return FinanceSectionCard(
      title: '${month.year}年${month.month}月',
      icon: Icons.calendar_month_outlined,
      description: currencyKeys.isEmpty
          ? '本月没有已登记的固定收支'
          : currencyKeys
                .map((currency) {
                  final totals = currencies[currency]!;
                  return '$currency · 流入 ${_money(totals.inflowMinor, currency)} · 支出 ${_money(totals.outflowMinor, currency)}';
                })
                .join('\n'),
      child: items.isEmpty
          ? Text(
              '本月没有已登记的固定收支。',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            )
          : Column(
              children: [
                for (final entry in grouped.entries) ...[
                  if (grouped.keys.first != entry.key)
                    const Divider(height: 24),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      _dateHeading(entry.key, forecast.now),
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  for (var index = 0; index < entry.value.length; index++) ...[
                    if (index > 0) const Divider(height: 18),
                    _buildCommitmentRow(entry.value[index]),
                  ],
                ],
              ],
            ),
    );
  }

  String _dateHeading(String key, DateTime now) {
    final day = dateFromKey(key);
    final label = '${day.month}月${day.day}日';
    final today = DateTime(now.year, now.month, now.day);
    final value = DateTime(day.year, day.month, day.day);
    return value == today ? '$label · 今天' : label;
  }

  Widget _buildCommitmentRow(
    FinanceFutureCommitment item, {
    bool overdue = false,
  }) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final isInflow = item.inflowMinor > 0;
    final transaction = item.transaction;
    final title = transaction != null
        ? _transactionTitle(transaction)
        : item.recurringRule?.name ?? item.loan?.name ?? '未命名安排';
    final amount = item.isLoanInstallment
        ? item.installment!.paymentMinor
        : item.amountMinor;
    final detail = transaction != null
        ? _transactionDetail(transaction)
        : item.installment == null
        ? _recurringDetail(item.recurringRule!)
        : _installmentDetail(item.installment!, item.currencyCode);
    return InkWell(
      key: ValueKey('future-commitment-${item.id}'),
      borderRadius: BorderRadius.circular(12),
      onTap: transaction != null
          ? () => _openTransaction(transaction)
          : item.isLoanInstallment
          ? () => _openLoan(item.loan!)
          : _openRecurringRule,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: overdue
                    ? colors.errorContainer
                    : isInflow
                    ? colors.tertiaryContainer
                    : colors.secondaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                item.isLoanInstallment
                    ? Icons.account_balance_outlined
                    : item.isTransaction
                    ? Icons.receipt_long_outlined
                    : isInflow
                    ? Icons.south_west_rounded
                    : Icons.north_east_rounded,
                size: 19,
                color: overdue
                    ? colors.onErrorContainer
                    : isInflow
                    ? colors.onTertiaryContainer
                    : colors.onSecondaryContainer,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    detail,
                    softWrap: true,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: overdue
                          ? colors.onErrorContainer
                          : colors.onSurfaceVariant,
                      height: 1.4,
                    ),
                  ),
                  if (item.possibleOverlapLabels.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.info_outline_rounded,
                          size: 14,
                          color: colors.tertiary,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            '可能与${item.possibleOverlapLabels.join('、')}重叠；两项均计入合计',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                '${isInflow ? '+' : '−'}${_money(amount, item.currencyCode)}',
                textAlign: TextAlign.end,
                softWrap: true,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: overdue
                      ? colors.error
                      : isInflow
                      ? colors.tertiary
                      : colors.onSurface,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _recurringDetail(FinanceRecurringRule rule) {
    final paymentMethodUuid = rule.paymentMethodUuid;
    final paymentMethod = _paymentMethods
        .where((item) => item.uuid == paymentMethodUuid)
        .firstOrNull;
    final paymentName = paymentMethodUuid == null
        ? '未指定付款方式'
        : paymentMethod == null
        ? '付款方式不可用'
        : financePaymentMethodDisplayName(paymentMethod, _paymentMethods);
    final mode = rule.autoGenerate ? '到期自动记账' : '到期需手动记账';
    return '${rule.frequency.label} · $paymentName · $mode';
  }

  String _installmentDetail(
    FinanceLoanInstallment installment,
    String currencyCode,
  ) =>
      '第 ${installment.installmentIndex} 期 · 本金 ${_money(installment.principalMinor, currencyCode)} · 利息 ${_money(installment.interestMinor, currencyCode)}';

  String _transactionTitle(FinanceTransaction transaction) {
    final merchant = transaction.merchant?.trim();
    if (merchant != null && merchant.isNotEmpty) return merchant;
    final category = financeCategoryReferenceDisplayName(
      transaction.categoryUuid,
      _categories,
    );
    return category == '未分类' ? transaction.type.label : category;
  }

  String _transactionDetail(FinanceTransaction transaction) {
    final parts = <String>[
      '已录入账单 · ${_transactionSourceLabel(transaction.source)}',
      if (transaction.categoryUuid?.trim().isNotEmpty == true)
        financeCategoryReferenceDisplayName(
          transaction.categoryUuid,
          _categories,
        ),
      if (transaction.note?.trim().isNotEmpty == true)
        '备注：${transaction.note!.trim()}',
    ];
    return parts.join(' · ');
  }

  String _transactionSourceLabel(FinanceEntrySource source) => switch (source) {
    FinanceEntrySource.manual => '手工录入',
    FinanceEntrySource.import => '导入',
    FinanceEntrySource.ai => 'AI录入',
    FinanceEntrySource.automation => '自动记账',
  };

  String _money(int minor, String currencyCode) {
    final sign = minor < 0 ? '−' : '';
    final amount = formatFinanceAmount(minor.abs(), withSymbol: false);
    return currencyCode.toUpperCase() == 'CNY'
        ? '$sign¥$amount'
        : '$sign$amount $currencyCode';
  }
}
