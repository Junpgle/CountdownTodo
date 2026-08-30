import '../../../widgets/floating_glass_control.dart';
import 'package:flutter/material.dart';

import '../models/finance_models.dart';
import '../services/finance_repository.dart';
import '../services/finance_storage.dart';

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
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final values = await Future.wait<dynamic>([
      FinanceStorage.getDeletedTransactions(),
      FinanceStorage.getLoans(includeDeleted: true),
      FinanceStorage.getBudgets(includeDeleted: true),
      FinanceStorage.getRecurringRules(includeDeleted: true),
      FinanceStorage.getTemplates(includeDeleted: true),
    ]);
    if (!mounted) return;
    setState(() {
      _transactions = values[0] as List<FinanceTransaction>;
      _loans = (values[1] as List<FinanceLoan>)
          .where((loan) => loan.isDeleted)
          .toList();
      _budgets = (values[2] as List<FinanceBudget>)
          .where((budget) => budget.isDeleted)
          .toList();
      _rules = (values[3] as List<FinanceRecurringRule>)
          .where((rule) => rule.isDeleted)
          .toList();
      _templates = (values[4] as List<FinanceEntryTemplate>)
          .where((template) => template.isDeleted)
          .toList();
      _isLoading = false;
    });
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
    if (restoreMode == null) return;
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

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: FloatingGlassAppBar(
          flexibleSpace: const FloatingGlassTopBarBackground(),
          title: const Text('记账回收站')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _transactions.isEmpty &&
                  _loans.isEmpty &&
                  _budgets.isEmpty &&
                  _rules.isEmpty &&
                  _templates.isEmpty
              ? Center(
                  child: Text(
                    '回收站是空的',
                    style: TextStyle(color: colorScheme.onSurfaceVariant),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    if (_transactions.isNotEmpty) ...[
                      const Text(
                        '账单',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 8),
                      for (final transaction in _transactions) ...[
                        Card(
                          child: ListTile(
                            title: Text(
                                transaction.merchant ?? transaction.type.label),
                            subtitle: Text(
                              '${transaction.transactionDate} · ${transaction.note ?? '无备注'}',
                            ),
                            trailing: TextButton(
                              onPressed: () => _restore(transaction),
                              child: const Text('恢复'),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                      ],
                    ],
                    if (_budgets.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      const Text(
                        '预算',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 8),
                      for (final budget in _budgets) ...[
                        Card(
                          child: ListTile(
                            title: Text(
                              budget.isOverall ? '全部支出预算' : '分类预算',
                            ),
                            subtitle: Text(
                              '${budget.monthKey} · ${formatFinanceAmount(budget.amountMinor)}${budget.note == null ? '' : ' · ${budget.note}'}',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: TextButton(
                              onPressed: () => _restoreBudget(budget),
                              child: const Text('恢复'),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                      ],
                    ],
                    if (_loans.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      const Text(
                        '贷款',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 8),
                      for (final loan in _loans) ...[
                        Card(
                          child: ListTile(
                            title: Text(loan.name),
                            subtitle: Text(
                              '${loan.startDate} · ${loan.repaymentMethod.label} · 年利率 ${formatFinanceInterestRate(loan.annualInterestRateBps)}',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: TextButton(
                              onPressed: () => _restoreLoan(loan),
                              child: const Text('恢复'),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                      ],
                    ],
                    if (_rules.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      const Text(
                        '周期账单',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 8),
                      for (final rule in _rules) ...[
                        Card(
                          child: ListTile(
                            title: Text(rule.name),
                            subtitle: Text(
                              '${rule.frequency.label} · ${formatFinanceAmount(rule.amountMinor)}',
                            ),
                            trailing: TextButton(
                              onPressed: () => _restoreRule(rule),
                              child: const Text('恢复'),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                      ],
                    ],
                    if (_templates.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      const Text(
                        '快捷模板',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 8),
                      for (final template in _templates) ...[
                        Card(
                          child: ListTile(
                            title: Text(template.name),
                            subtitle: Text(
                              '${template.type.label} · ${formatFinanceAmount(template.amountMinor)}',
                            ),
                            trailing: TextButton(
                              onPressed: () => _restoreTemplate(template),
                              child: const Text('恢复'),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                      ],
                    ],
                  ],
                ),
    );
  }
}
