import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/finance_models.dart';
import '../services/finance_repository.dart';
import '../widgets/finance_management_widgets.dart';
import '../../../widgets/floating_glass_control.dart';
import 'finance_budget_entry_screen.dart';

class FinanceBudgetScreen extends StatefulWidget {
  final DateTime? initialMonth;

  const FinanceBudgetScreen({super.key, this.initialMonth});

  @override
  State<FinanceBudgetScreen> createState() => _FinanceBudgetScreenState();
}

class _FinanceBudgetScreenState extends State<FinanceBudgetScreen> {
  late DateTime _month;
  List<FinanceBudget> _budgets = const [];
  List<FinanceCategory> _categories = const [];
  List<FinancePaymentMethod> _paymentMethods = const [];
  List<FinanceTransaction> _transactions = const [];
  FinanceSummary _summary = const FinanceSummary();
  bool _isLoading = true;
  String? _loadError;
  int _loadGeneration = 0;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialMonth ?? DateTime.now();
    _month = DateTime(initial.year, initial.month);
    _load();
  }

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

  List<FinanceBudget> get _paymentBudgets =>
      _budgets.where((budget) => budget.isPaymentMethod).toList();

  Map<String, FinancePaymentMethod> get _paymentMethodMap => {
        for (final method in _paymentMethods) method.uuid: method,
      };

  Future<void> _load() async {
    final generation = ++_loadGeneration;
    if (mounted) {
      setState(() {
        _isLoading = true;
        _loadError = null;
      });
    }
    try {
      final from = DateTime(_month.year, _month.month);
      final to = DateTime(_month.year, _month.month + 1);
      final values = await Future.wait<dynamic>([
        FinanceRepository.getBudgets(monthKey: financeMonthKey(_month)),
        FinanceRepository.getCategories(
          type: FinanceCategoryType.expense,
          includeArchived: true,
        ),
        FinanceRepository.getPaymentMethods(includeArchived: true),
        FinanceRepository.getTransactions(from: from, to: to),
      ]);
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _budgets = values[0] as List<FinanceBudget>;
        _categories = values[1] as List<FinanceCategory>;
        _paymentMethods = values[2] as List<FinancePaymentMethod>;
        _transactions = values[3] as List<FinanceTransaction>;
        _summary = FinanceRepository.summarizeTransactions(_transactions);
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _isLoading = false;
        _loadError = error.toString();
      });
    }
  }

  Future<void> _openEditor([
    FinanceBudget? budget,
    String? paymentMethodUuid,
  ]) async {
    final result = await Navigator.of(context).push<FinanceBudget>(
      MaterialPageRoute(
        builder: (_) => FinanceBudgetEntryScreen(
          month: _month,
          budget: budget,
          initialPaymentMethodUuid: paymentMethodUuid,
        ),
      ),
    );
    if (result != null && mounted) await _load();
  }

  Future<void> _choosePaymentMethodForBudget() async {
    final methods = _paymentMethods
        .where((method) => !method.isArchived && !method.isDeleted)
        .toList(growable: false);
    if (methods.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先添加或恢复一个付款方式')),
      );
      return;
    }
    final paymentMethodUuid = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
              child: Text(
                '选择付款方式',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
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
    for (final budget in _paymentBudgets) {
      if (budget.paymentMethodUuid == paymentMethodUuid) {
        existing = budget;
        break;
      }
    }
    await _openEditor(existing, paymentMethodUuid);
  }

  Future<void> _deleteBudget(FinanceBudget budget) async {
    final itemName = budget.isPaymentMethod ? '付款方式余额' : '预算';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('删除$itemName？'),
        content: Text('删除$itemName记录不会影响已有账单。'),
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('删除$itemName失败：$error')),
      );
      return;
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$itemName已删除')),
    );
    await _load();
  }

  void _changeMonth(int delta) {
    setState(() => _month = DateTime(_month.year, _month.month + delta));
    _load();
  }

  Future<void> _pickMonth() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _month,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 3650)),
      helpText: '选择预算月份',
    );
    if (picked == null || !mounted) return;
    setState(() => _month = DateTime(picked.year, picked.month));
    await _load();
  }

  int _usedFor(FinanceBudget budget) {
    if (budget.paymentMethodUuid != null) {
      final paymentMethodUuid = budget.paymentMethodUuid!;
      final snapshotAt = budget.updatedAt;
      final snapshotDate = dateKey(
        DateTime.fromMillisecondsSinceEpoch(snapshotAt),
      );
      final today = dateKey(DateTime.now());
      final transactionsAfterSnapshot = _transactions.where((transaction) {
        if (transaction.paymentMethodUuid != paymentMethodUuid ||
            transaction.transactionDate.compareTo(today) > 0) {
          return false;
        }
        final dateComparison =
            transaction.transactionDate.compareTo(snapshotDate);
        return dateComparison > 0 ||
            (dateComparison == 0 && transaction.createdAt > snapshotAt);
      });
      final usage = FinanceRepository.summarizePaymentMethodSpending(
        transactionsAfterSnapshot,
      )[paymentMethodUuid];
      return usage ?? 0;
    }
    if (budget.isOverall) {
      return math.max(0, _summary.netExpenseMinor);
    }
    return math.max(0, _summary.expenseByCategory[budget.categoryUuid] ?? 0);
  }

  String _budgetTitle(FinanceBudget budget) {
    if (budget.isOverall) return '全部支出';
    if (budget.paymentMethodUuid != null) {
      return _paymentMethodMap[budget.paymentMethodUuid]?.name ?? '已归档或未知付款方式';
    }
    final category = _categoryMap[budget.categoryUuid];
    return category == null
        ? '已归档或未知分类'
        : financeCategoryDisplayName(category, _categories);
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
                                style: Theme.of(context)
                                    .textTheme
                                    .titleMedium
                                    ?.copyWith(fontWeight: FontWeight.w700),
                              ),
                            ),
                            Text(
                              '${_budgets.where((budget) => !budget.isPaymentMethod).length} 项',
                              style: TextStyle(
                                color: colorScheme.onSurfaceVariant,
                              ),
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
                                _buildBudgetCard(budget, colorScheme)
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
                                '付款方式实时余额',
                                style: Theme.of(context)
                                    .textTheme
                                    .titleMedium
                                    ?.copyWith(fontWeight: FontWeight.w700),
                              ),
                            ),
                            Text(
                              '${_paymentBudgets.length} 项',
                              style: TextStyle(
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(width: 4),
                            IconButton(
                              tooltip: '录入付款方式余额',
                              onPressed: _choosePaymentMethodForBudget,
                              icon: const Icon(Icons.add_circle_outline),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        if (_paymentBudgets.isEmpty)
                          _buildPaymentEmptyState(colorScheme)
                        else
                          FinanceAdaptiveFields(
                            minChildWidth: 330,
                            children: [
                              for (final budget in _paymentBudgets)
                                _buildBudgetCard(budget, colorScheme)
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
          onPressed: () => _changeMonth(-1),
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
                  Icon(Icons.expand_more,
                      size: 18, color: colorScheme.onSurfaceVariant),
                ],
              ),
            ),
          ),
        ),
        IconButton(
          tooltip: '下个月',
          onPressed: () => _changeMonth(1),
          icon: const Icon(Icons.chevron_right),
        ),
      ],
    );
  }

  Widget _buildSummaryCard(ColorScheme colorScheme) {
    final overall = _overallBudget;
    final categoryBudgets = _categoryBudgets;
    final budgetTotal = overall?.amountMinor ??
        categoryBudgets.fold<int>(0, (sum, item) => sum + item.amountMinor);
    final used = overall == null
        ? categoryBudgets.fold<int>(
            0,
            (sum, item) => sum + _usedFor(item),
          )
        : _usedFor(overall);
    final remaining = budgetTotal - used;
    final progress = budgetTotal == 0
        ? 0.0
        : (used / budgetTotal).clamp(0.0, 1.0).toDouble();
    final isOver = remaining < 0;
    final title = overall == null ? '分类预算合计' : '本月总预算';
    final subtitle = overall == null ? '只汇总已设置分类的预算' : '所有支出按本月账单计算';
    final foreground =
        isOver ? colorScheme.onErrorContainer : colorScheme.onPrimaryContainer;
    return FinanceSectionCard(
      color: isOver ? colorScheme.errorContainer : colorScheme.primaryContainer,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title,
            style: TextStyle(color: foreground, fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        Text(subtitle,
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: foreground.withValues(alpha: 0.75))),
        const SizedBox(height: 16),
        Text(formatFinanceAmount(budgetTotal),
            style: Theme.of(context)
                .textTheme
                .headlineLarge
                ?.copyWith(color: foreground, fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        Text(
            isOver
                ? '已超支 ${formatFinanceAmount(-remaining)}'
                : '剩余 ${formatFinanceAmount(remaining)}',
            style: TextStyle(color: foreground)),
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
            '已使用 ${formatFinanceAmount(used)} / ${formatFinanceAmount(budgetTotal)}',
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: foreground.withValues(alpha: 0.8))),
        if (overall != null && categoryBudgets.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text('分类预算独立统计，不叠加到总预算。',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: foreground.withValues(alpha: 0.75))),
        ],
        if (_paymentBudgets.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text('付款方式实时余额单独显示，不计入总额和分类预算。',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: foreground.withValues(alpha: 0.75))),
        ],
      ]),
    );
  }

  Widget _buildBudgetCard(
    FinanceBudget budget,
    ColorScheme colorScheme,
  ) {
    final used = _usedFor(budget);
    final remaining = budget.amountMinor - used;
    final isOver = remaining < 0;
    final snapshotAt = DateTime.fromMillisecondsSinceEpoch(budget.updatedAt);
    final progress = budget.amountMinor == 0
        ? 0.0
        : (used / budget.amountMinor).clamp(0.0, 1.0).toDouble();
    final progressColor = isOver ? colorScheme.error : colorScheme.primary;
    return FinanceSectionCard(
      key: ValueKey('finance-budget-card-${budget.uuid}'),
      onTap: () => _openEditor(budget),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          SizedBox.square(
              dimension: 36,
              child: FittedBox(
                  child: Text(_budgetIcon(budget),
                      textScaler: TextScaler.noScaling))),
          const SizedBox(width: 12),
          Expanded(
              child: Text(_budgetTitle(budget),
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700))),
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
        ]),
        const SizedBox(height: 16),
        FinanceAdaptiveFields(minChildWidth: 150, children: [
          _budgetMetric(
            budget.isPaymentMethod && used < 0
                ? '录入后退款净加回'
                : budget.isPaymentMethod
                    ? '录入后净扣减'
                    : '已使用',
            budget.isPaymentMethod ? used.abs() : used,
          ),
          _budgetMetric(
            budget.isPaymentMethod
                ? '${snapshotAt.month}月${snapshotAt.day}日录入时余额'
                : '预算额度',
            budget.amountMinor,
          ),
        ]),
        const SizedBox(height: 18),
        LinearProgressIndicator(
          value: progress,
          minHeight: 7,
          borderRadius: BorderRadius.circular(8),
          backgroundColor: colorScheme.surfaceContainerHighest,
          color: progressColor,
        ),
        const SizedBox(height: 12),
        FinanceStatusBadge(
          label: budget.isPaymentMethod
              ? isOver
                  ? '当前余额不足 ${formatFinanceAmount(-remaining)}'
                  : '当前余额 ${formatFinanceAmount(remaining)}'
              : isOver
                  ? '超支 ${formatFinanceAmount(-remaining)}'
                  : '剩余 ${formatFinanceAmount(remaining)}',
          isError: isOver,
          highlighted: !isOver,
        ),
        if (budget.note?.isNotEmpty == true) ...[
          const SizedBox(height: 10),
          Text(budget.note!,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: colorScheme.onSurfaceVariant)),
        ],
      ]),
    );
  }

  Widget _budgetMetric(String label, int amount) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant)),
      const SizedBox(height: 4),
      Text(formatFinanceAmount(amount),
          style: Theme.of(context)
              .textTheme
              .titleMedium
              ?.copyWith(fontWeight: FontWeight.w700)),
    ]);
  }

  Widget _buildEmptyState(ColorScheme colorScheme) {
    return FinanceEmptyState(
      icon: Icons.track_changes_outlined,
      title: '本月还没有预算',
      description: '设置总预算或分类额度，随时了解还能花多少。',
      actionLabel: '添加预算',
      onAction: () => _openEditor(),
    );
  }

  Widget _buildPaymentEmptyState(ColorScheme colorScheme) {
    return FinanceEmptyState(
      icon: Icons.account_balance_wallet_outlined,
      title: '还没有付款方式余额记录',
      description: '录入此刻的剩余金额，之后的支出会扣减，退款会加回。',
      actionLabel: '选择付款方式并录入余额',
      onAction: _choosePaymentMethodForBudget,
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
