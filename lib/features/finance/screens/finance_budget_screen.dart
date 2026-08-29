import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/finance_models.dart';
import '../services/finance_repository.dart';
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
      if (budget.categoryUuid == null) return budget;
    }
    return null;
  }

  List<FinanceBudget> get _categoryBudgets =>
      _budgets.where((budget) => budget.categoryUuid != null).toList();

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
        FinanceRepository.getSummary(from: from, to: to),
        FinanceRepository.getCategories(
          type: FinanceCategoryType.expense,
          includeArchived: true,
        ),
      ]);
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _budgets = values[0] as List<FinanceBudget>;
        _summary = values[1] as FinanceSummary;
        _categories = values[2] as List<FinanceCategory>;
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

  Future<void> _openEditor([FinanceBudget? budget]) async {
    final result = await Navigator.of(context).push<FinanceBudget>(
      MaterialPageRoute(
        builder: (_) => FinanceBudgetEntryScreen(
          month: _month,
          budget: budget,
        ),
      ),
    );
    if (result != null && mounted) await _load();
  }

  Future<void> _deleteBudget(FinanceBudget budget) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除预算？'),
        content: const Text('删除预算不会影响已有账单。'),
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
        SnackBar(content: Text('删除预算失败：$error')),
      );
      return;
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('预算已删除')),
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
    if (budget.isOverall) {
      return math.max(0, _summary.netExpenseMinor);
    }
    return math.max(0, _summary.expenseByCategory[budget.categoryUuid] ?? 0);
  }

  String _budgetTitle(FinanceBudget budget) {
    if (budget.isOverall) return '全部支出';
    return _categoryMap[budget.categoryUuid]?.name ?? '已归档或未知分类';
  }

  String _budgetIcon(FinanceBudget budget) {
    if (budget.isOverall) return '🎯';
    return _categoryMap[budget.categoryUuid]?.icon ?? '🗃️';
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: FloatingGlassAppBar(
        flexibleSpace: const FloatingGlassTopBarBackground(),
        title: const Text('预算'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _loadError != null
              ? _buildError(colorScheme)
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                    children: [
                      _buildMonthBar(colorScheme),
                      const SizedBox(height: 8),
                      _buildSummaryCard(colorScheme),
                      const SizedBox(height: 24),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '预算项目',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                          ),
                          Text(
                            '${_budgets.length} 项',
                            style: TextStyle(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      if (_budgets.isEmpty)
                        _buildEmptyState(colorScheme)
                      else
                        for (final budget in _budgets)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: _buildBudgetCard(budget, colorScheme),
                          ),
                      if (_budgets.isNotEmpty && _overallBudget == null)
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
                    ],
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
                  Text(
                    '${_month.year} 年 ${_month.month} 月',
                    style: const TextStyle(fontWeight: FontWeight.w700),
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
    return Card(
      color: isOver ? colorScheme.errorContainer : colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          color: isOver
                              ? colorScheme.onErrorContainer
                              : colorScheme.onPrimaryContainer,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: TextStyle(
                          color: (isOver
                                  ? colorScheme.onErrorContainer
                                  : colorScheme.onPrimaryContainer)
                              .withValues(alpha: 0.72),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                if (overall != null && categoryBudgets.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(left: 12),
                    child: Text(
                      '分类独立统计',
                      style: TextStyle(
                        color: (isOver
                                ? colorScheme.onErrorContainer
                                : colorScheme.onPrimaryContainer)
                            .withValues(alpha: 0.72),
                        fontSize: 12,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              formatFinanceAmount(budgetTotal),
              style: TextStyle(
                color: isOver
                    ? colorScheme.onErrorContainer
                    : colorScheme.onPrimaryContainer,
                fontSize: 30,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              isOver
                  ? '已超支 ${formatFinanceAmount(-remaining, withSymbol: true)}'
                  : '剩余 ${formatFinanceAmount(remaining)}',
              style: TextStyle(
                color: isOver
                    ? colorScheme.onErrorContainer
                    : colorScheme.onPrimaryContainer,
              ),
            ),
            const SizedBox(height: 14),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                minHeight: 9,
                value: progress,
                backgroundColor: (isOver
                        ? colorScheme.onErrorContainer
                        : colorScheme.onPrimaryContainer)
                    .withValues(alpha: 0.18),
                color: isOver
                    ? colorScheme.onErrorContainer
                    : colorScheme.onPrimaryContainer,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '已使用 ${formatFinanceAmount(used)} / ${formatFinanceAmount(budgetTotal)}',
              style: TextStyle(
                color: (isOver
                        ? colorScheme.onErrorContainer
                        : colorScheme.onPrimaryContainer)
                    .withValues(alpha: 0.78),
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBudgetCard(
    FinanceBudget budget,
    ColorScheme colorScheme,
  ) {
    final used = _usedFor(budget);
    final remaining = budget.amountMinor - used;
    final isOver = remaining < 0;
    final progress = budget.amountMinor == 0
        ? 0.0
        : (used / budget.amountMinor).clamp(0.0, 1.0).toDouble();
    final progressColor = isOver ? colorScheme.error : colorScheme.primary;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 8, 12),
        child: Column(
          children: [
            Row(
              children: [
                Text(_budgetIcon(budget), style: const TextStyle(fontSize: 22)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _budgetTitle(budget),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                PopupMenuButton<String>(
                  onSelected: (value) {
                    if (value == 'edit') _openEditor(budget);
                    if (value == 'delete') _deleteBudget(budget);
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem(value: 'edit', child: Text('编辑')),
                    PopupMenuItem(value: 'delete', child: Text('删除')),
                  ],
                ),
              ],
            ),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '已用 ${formatFinanceAmount(used)}',
                    style: TextStyle(color: colorScheme.onSurfaceVariant),
                  ),
                ),
                Text(
                  '预算 ${formatFinanceAmount(budget.amountMinor)}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                minHeight: 8,
                value: progress,
                backgroundColor: colorScheme.surfaceContainerHighest,
                color: progressColor,
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: Text(
                    budget.note ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: colorScheme.onSurfaceVariant,
                      fontSize: 12,
                    ),
                  ),
                ),
                Text(
                  isOver
                      ? '超支 ${formatFinanceAmount(-remaining)}'
                      : '剩余 ${formatFinanceAmount(remaining)}',
                  style: TextStyle(
                    color: isOver ? colorScheme.error : colorScheme.primary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(ColorScheme colorScheme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Icon(Icons.track_changes_outlined,
                size: 48, color: colorScheme.onSurfaceVariant),
            const SizedBox(height: 12),
            Text(
              '本月还没有预算',
              style: TextStyle(color: colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            FilledButton.tonalIcon(
              onPressed: () => _openEditor(),
              icon: const Icon(Icons.add),
              label: const Text('添加预算'),
            ),
          ],
        ),
      ),
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
