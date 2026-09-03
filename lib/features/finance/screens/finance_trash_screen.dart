import '../../../widgets/floating_glass_control.dart';
import 'package:flutter/material.dart';

import '../models/finance_models.dart';
import '../services/finance_repository.dart';
import '../services/finance_storage.dart';
import '../widgets/finance_management_widgets.dart';
import '../widgets/finance_trash_manager.dart';

class FinanceTrashScreen extends StatefulWidget {
  const FinanceTrashScreen({super.key});

  @override
  State<FinanceTrashScreen> createState() => _FinanceTrashScreenState();
}

class _FinanceTrashScreenState extends State<FinanceTrashScreen> {
  List<FinanceTransaction> _transactions = const [];
  List<FinanceLoan> _loans = const [];
  List<FinanceBudget> _budgets = const [];
  List<FinanceRecurringRule> _rules = const [];
  List<FinanceEntryTemplate> _templates = const [];
  List<FinanceCategory> _categories = const [];
  bool _isLoading = true;
  String? _loadError;
  int _loadGeneration = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final generation = ++_loadGeneration;
    try {
      final values = await Future.wait<dynamic>([
        FinanceStorage.getDeletedTransactions(),
        FinanceStorage.getLoans(includeDeleted: true),
        FinanceStorage.getBudgets(includeDeleted: true),
        FinanceStorage.getRecurringRules(includeDeleted: true),
        FinanceStorage.getTemplates(includeDeleted: true),
        FinanceRepository.getCategories(includeArchived: true),
      ]);
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _transactions = values[0] as List<FinanceTransaction>;
        _loans = (values[1] as List<FinanceLoan>)
            .where((item) => item.isDeleted)
            .toList();
        _budgets = (values[2] as List<FinanceBudget>)
            .where((item) => item.isDeleted)
            .toList();
        _rules = (values[3] as List<FinanceRecurringRule>)
            .where((item) => item.isDeleted)
            .toList();
        _templates = (values[4] as List<FinanceEntryTemplate>)
            .where((item) => item.isDeleted)
            .toList();
        _categories = values[5] as List<FinanceCategory>;
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

  Future<void> _restore(FinanceTransaction transaction) async {
    final restoreMode = transaction.isInstallment
        ? await showDialog<String>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('恢复分期账单？'),
              content: Text(
                '这是第 ${transaction.installmentIndex}/${transaction.installmentCount} 期。',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('取消'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context, 'single'),
                  child: const Text('只恢复本期'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, 'group'),
                  child: const Text('恢复整组'),
                ),
              ],
            ),
          )
        : 'single';
    if (restoreMode == null || !mounted) return;
    if (restoreMode == 'group' && transaction.installmentGroupUuid != null) {
      await FinanceStorage.restoreInstallmentGroup(
        transaction.installmentGroupUuid!,
      );
    } else {
      await FinanceStorage.restoreTransaction(transaction.uuid);
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('账单已恢复')),
    );
    await _load();
  }

  Future<void> _restoreBudget(FinanceBudget budget) async {
    try {
      await FinanceStorage.restoreBudget(budget.uuid);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('恢复预算失败：$error')),
      );
      return;
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('预算已恢复')),
    );
    await _load();
  }

  Future<void> _restoreLoan(FinanceLoan loan) async {
    try {
      await FinanceStorage.restoreLoan(loan.uuid);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('恢复贷款失败：$error')),
      );
      return;
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('贷款已恢复')),
    );
    await _load();
  }

  Future<void> _restoreRule(FinanceRecurringRule rule) async {
    await FinanceStorage.restoreRecurringRule(rule.uuid);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('周期账单已恢复')),
    );
    await _load();
  }

  Future<void> _restoreTemplate(FinanceEntryTemplate template) async {
    await FinanceStorage.restoreTemplate(template.uuid);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('快捷模板已恢复')),
    );
    await _load();
  }

  List<FinanceTrashEntry> get _entries {
    final categories = {
      for (final category in _categories) category.uuid: category
    };
    return [
      for (final item in _transactions)
        FinanceTrashEntry(
          uuid: item.uuid,
          kind: FinanceTrashKind.transaction,
          title: item.merchant?.trim().isNotEmpty == true
              ? item.merchant!
              : categories[item.categoryUuid]?.name ?? item.type.label,
          details: [
            item.transactionDate,
            if (item.isInstallment)
              '第 ${item.installmentIndex}/${item.installmentCount} 期',
            if (item.note?.isNotEmpty == true) item.note!,
          ].join(' · '),
          amountLabel: item.type.label,
          amountMinor: item.amountMinor,
          onRestore: () => _restore(item),
        ),
      for (final item in _budgets)
        FinanceTrashEntry(
          uuid: item.uuid,
          kind: FinanceTrashKind.budget,
          title: item.isOverall
              ? '全部支出预算'
              : '${categories[item.categoryUuid]?.name ?? '已归档或未知分类'}预算',
          details: [
            item.monthKey,
            if (item.note?.isNotEmpty == true) item.note!
          ].join(' · '),
          amountLabel: '预算额度',
          amountMinor: item.amountMinor,
          onRestore: () => _restoreBudget(item),
        ),
      for (final item in _loans)
        FinanceTrashEntry(
          uuid: item.uuid,
          kind: FinanceTrashKind.loan,
          title: item.name,
          details:
              '${item.startDate} · ${item.repaymentMethod.label} · 年利率 ${formatFinanceInterestRate(item.annualInterestRateBps)}',
          amountLabel: '借款本金',
          amountMinor: item.principalMinor,
          onRestore: () => _restoreLoan(item),
        ),
      for (final item in _rules)
        FinanceTrashEntry(
          uuid: item.uuid,
          kind: FinanceTrashKind.rule,
          title: item.name,
          details: item.frequency == FinanceRecurringFrequency.yearly
              ? '每年 ${item.monthOfYear} 月 ${item.dayOfMonth} 日'
              : '每月 ${item.dayOfMonth} 日',
          amountLabel: item.type.label,
          amountMinor: item.amountMinor,
          onRestore: () => _restoreRule(item),
        ),
      for (final item in _templates)
        FinanceTrashEntry(
          uuid: item.uuid,
          kind: FinanceTrashKind.template,
          title: item.name,
          details: [
            if (item.merchant?.isNotEmpty == true) item.merchant!,
            if (item.note?.isNotEmpty == true) item.note!,
            '已使用 ${item.useCount} 次'
          ].join(' · '),
          amountLabel: item.type.label,
          amountMinor: item.amountMinor,
          onRestore: () => _restoreTemplate(item),
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: FloatingGlassAppBar(
        flexibleSpace: const FloatingGlassTopBarBackground(),
        title: const Text('记账回收站'),
        actions: [
          IconButton(
              tooltip: '刷新', onPressed: _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _loadError != null
              ? FinancePageList(children: [
                  FinanceEmptyState(
                    icon: Icons.error_outline_rounded,
                    title: '回收站加载失败',
                    description: '请重新加载后再恢复记录。',
                    actionLabel: '重新加载',
                    onAction: _load,
                  ),
                ])
              : RefreshIndicator(
                  onRefresh: _load,
                  child: FinanceTrashManager(entries: _entries),
                ),
    );
  }
}
