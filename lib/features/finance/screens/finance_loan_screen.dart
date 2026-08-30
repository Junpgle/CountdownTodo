import 'package:flutter/material.dart';

import '../../../widgets/floating_glass_control.dart';
import '../models/finance_models.dart';
import '../services/finance_repository.dart';
import 'finance_loan_entry_screen.dart';

class FinanceLoanScreen extends StatefulWidget {
  const FinanceLoanScreen({super.key});

  @override
  State<FinanceLoanScreen> createState() => _FinanceLoanScreenState();
}

class _FinanceLoanScreenState extends State<FinanceLoanScreen> {
  List<FinanceLoanOverview> _overviews = const [];
  bool _isLoading = true;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _isLoading = true;
        _loadError = null;
      });
    }
    try {
      final loans = await FinanceRepository.getLoans();
      final installments = await Future.wait(
        loans.map(
          (loan) => FinanceRepository.getLoanInstallments(loan.uuid),
        ),
      );
      if (!mounted) return;
      setState(() {
        _overviews = [
          for (var index = 0; index < loans.length; index++)
            FinanceLoanOverview(
              loan: loans[index],
              installments: installments[index],
            ),
        ];
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _loadError = error.toString();
      });
    }
  }

  Future<void> _openEditor([FinanceLoan? loan]) async {
    final result = await Navigator.of(context).push<FinanceLoan>(
      MaterialPageRoute(
        builder: (_) => FinanceLoanEntryScreen(loan: loan),
      ),
    );
    if (result != null && mounted) await _load();
  }

  Future<void> _openDetail(FinanceLoanOverview overview) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => FinanceLoanDetailScreen(loan: overview.loan),
      ),
    );
    if (mounted) await _load();
  }

  Future<void> _deleteLoan(FinanceLoan loan) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除贷款？'),
        content: const Text('贷款和还款计划会进入记账回收站，已经记录的利息账单不会被删除。'),
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
      await FinanceRepository.deleteLoan(loan.uuid);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('贷款已删除')),
      );
      await _load();
    } catch (error) {
      if (!mounted) return;
      _showError('删除贷款失败：$error');
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Widget _buildLoanCard(
    BuildContext context,
    FinanceLoanOverview overview,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    final loan = overview.loan;
    final next = overview.nextInstallment;
    final progress = overview.installments.isEmpty
        ? 0.0
        : overview.paidCount / overview.installments.length;
    final statusColor =
        overview.isPaidOff ? colorScheme.primary : colorScheme.onSurfaceVariant;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _openDetail(overview),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    backgroundColor: colorScheme.tertiaryContainer,
                    child: Icon(
                      Icons.account_balance_outlined,
                      color: colorScheme.onTertiaryContainer,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          loan.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        Text(
                          [
                            if (loan.lender?.isNotEmpty == true) loan.lender!,
                            loan.repaymentMethod.label,
                            '年利率 ${formatFinanceInterestRate(loan.annualInterestRateBps)}',
                          ].join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: colorScheme.onSurfaceVariant,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  PopupMenuButton<String>(
                    onSelected: (value) {
                      if (value == 'edit') _openEditor(loan);
                      if (value == 'delete') _deleteLoan(loan);
                    },
                    itemBuilder: (context) => const [
                      PopupMenuItem(value: 'edit', child: Text('编辑')),
                      PopupMenuItem(value: 'delete', child: Text('删除')),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: _metric(
                      context,
                      '剩余本金',
                      formatFinanceAmount(overview.outstandingPrincipalMinor),
                    ),
                  ),
                  Expanded(
                    child: _metric(
                      context,
                      '预计总利息',
                      formatFinanceAmount(overview.totalInterestMinor),
                    ),
                  ),
                  Expanded(
                    child: _metric(
                      context,
                      '进度',
                      '${overview.paidCount}/${overview.installments.length} 期',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 6,
                  backgroundColor: colorScheme.surfaceContainerHighest,
                  color: colorScheme.primary,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                overview.isPaidOff
                    ? '已全部还清'
                    : '下期 ${next?.dueDate ?? '-'} · 应还 ${formatFinanceAmount(next?.paymentMinor ?? 0)}',
                style: TextStyle(color: statusColor, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _metric(BuildContext context, String label, String value) {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: colorScheme.onSurfaceVariant,
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ],
    );
  }

  Widget _buildBody(ColorScheme colorScheme) {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    if (_loadError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('贷款加载失败：$_loadError', textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton.tonal(
                onPressed: _load,
                child: const Text('重试'),
              ),
            ],
          ),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Card(
            color: colorScheme.primaryContainer,
            child: ListTile(
              leading: Icon(
                Icons.account_balance_outlined,
                color: colorScheme.onPrimaryContainer,
              ),
              title: Text(
                '贷款负债',
                style: TextStyle(
                  color: colorScheme.onPrimaryContainer,
                  fontWeight: FontWeight.w700,
                ),
              ),
              subtitle: Text(
                '记录本金、利率和还款进度；标记已还后利息会进入支出。',
                style: TextStyle(
                  color: colorScheme.onPrimaryContainer.withValues(alpha: 0.78),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (_overviews.isEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    Icon(
                      Icons.account_balance_wallet_outlined,
                      size: 44,
                      color: colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      '还没有贷款记录',
                      style: TextStyle(color: colorScheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 14),
                    FilledButton.tonalIcon(
                      onPressed: () => _openEditor(),
                      icon: const Icon(Icons.add),
                      label: const Text('新增贷款'),
                    ),
                  ],
                ),
              ),
            )
          else
            for (final overview in _overviews) ...[
              _buildLoanCard(context, overview),
              const SizedBox(height: 10),
            ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: FloatingGlassAppBar(
        flexibleSpace: const FloatingGlassTopBarBackground(),
        title: const Text('贷款'),
        actions: [
          IconButton(
            tooltip: '新增贷款',
            onPressed: () => _openEditor(),
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      body: _buildBody(colorScheme),
    );
  }
}

class FinanceLoanDetailScreen extends StatefulWidget {
  final FinanceLoan loan;

  const FinanceLoanDetailScreen({super.key, required this.loan});

  @override
  State<FinanceLoanDetailScreen> createState() =>
      _FinanceLoanDetailScreenState();
}

class _FinanceLoanDetailScreenState extends State<FinanceLoanDetailScreen> {
  FinanceLoan? _loan;
  List<FinanceLoanInstallment> _installments = const [];
  bool _isLoading = true;
  String? _loadError;

  FinanceLoan get _currentLoan => _loan ?? widget.loan;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _isLoading = true;
        _loadError = null;
      });
    }
    try {
      final loan = await FinanceRepository.getLoan(widget.loan.uuid);
      if (loan == null) throw StateError('贷款不存在或已删除');
      final installments =
          await FinanceRepository.getLoanInstallments(loan.uuid);
      if (!mounted) return;
      setState(() {
        _loan = loan;
        _installments = installments;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _loadError = error.toString();
      });
    }
  }

  Future<void> _editLoan() async {
    final result = await Navigator.of(context).push<FinanceLoan>(
      MaterialPageRoute(
        builder: (_) => FinanceLoanEntryScreen(loan: _currentLoan),
      ),
    );
    if (result != null && mounted) await _load();
  }

  Future<void> _togglePaid(FinanceLoanInstallment installment) async {
    try {
      await FinanceRepository.setLoanInstallmentPaid(
        installment.uuid,
        !installment.isPaid,
      );
      await _load();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('更新还款状态失败：$error')),
      );
    }
  }

  Widget _buildSummary(
    BuildContext context,
    FinanceLoanOverview overview,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      color: colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              overview.loan.name,
              style: TextStyle(
                color: colorScheme.onPrimaryContainer,
                fontSize: 20,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${overview.loan.repaymentMethod.label} · 年利率 ${formatFinanceInterestRate(overview.loan.annualInterestRateBps)} · ${overview.loan.termMonths} 个月',
              style: TextStyle(
                color: colorScheme.onPrimaryContainer.withValues(alpha: 0.78),
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: _summaryMetric(
                    colorScheme,
                    '剩余本金',
                    formatFinanceAmount(overview.outstandingPrincipalMinor),
                  ),
                ),
                Expanded(
                  child: _summaryMetric(
                    colorScheme,
                    '已付利息',
                    formatFinanceAmount(overview.paidInterestMinor),
                  ),
                ),
                Expanded(
                  child: _summaryMetric(
                    colorScheme,
                    '已还期数',
                    '${overview.paidCount}/${overview.installments.length}',
                  ),
                ),
              ],
            ),
            if (overview.loan.note?.isNotEmpty == true) ...[
              const SizedBox(height: 14),
              Text(
                overview.loan.note!,
                style: TextStyle(
                  color: colorScheme.onPrimaryContainer.withValues(alpha: 0.82),
                  fontSize: 12,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _summaryMetric(
    ColorScheme colorScheme,
    String label,
    String value,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: colorScheme.onPrimaryContainer.withValues(alpha: 0.7),
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: colorScheme.onPrimaryContainer,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }

  Widget _buildInstallmentTile(
    BuildContext context,
    FinanceLoanInstallment installment,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    final statusColor = installment.isPaid
        ? colorScheme.primary
        : installment.isOverdue
            ? colorScheme.error
            : colorScheme.onSurfaceVariant;
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: installment.isPaid
              ? colorScheme.primaryContainer
              : colorScheme.surfaceContainerHighest,
          child: Text(
            '${installment.installmentIndex}',
            style: TextStyle(
              color: installment.isPaid
                  ? colorScheme.onPrimaryContainer
                  : colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        title: Text(
          '第 ${installment.installmentIndex} 期 · ${installment.dueDate}',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          '应还 ${formatFinanceAmount(installment.paymentMinor)} · '
          '本金 ${formatFinanceAmount(installment.principalMinor)} · '
          '利息 ${formatFinanceAmount(installment.interestMinor)}\n'
          '还款后剩余 ${formatFinanceAmount(installment.remainingPrincipalMinor)}',
          style: TextStyle(color: statusColor, fontSize: 12),
        ),
        isThreeLine: true,
        trailing: Checkbox(
          value: installment.isPaid,
          onChanged: (_) => _togglePaid(installment),
          semanticLabel: installment.isPaid ? '撤销已还' : '标记已还',
        ),
      ),
    );
  }

  Widget _buildBody(ColorScheme colorScheme) {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    if (_loadError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('贷款加载失败：$_loadError', textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton.tonal(onPressed: _load, child: const Text('重试')),
            ],
          ),
        ),
      );
    }
    final overview = FinanceLoanOverview(
      loan: _currentLoan,
      installments: _installments,
    );
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          _buildSummary(context, overview),
          const SizedBox(height: 18),
          Text(
            '还款计划',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          for (final installment in _installments) ...[
            _buildInstallmentTile(context, installment),
            const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: FloatingGlassAppBar(
        flexibleSpace: const FloatingGlassTopBarBackground(),
        title: const Text('贷款详情'),
        actions: [
          IconButton(
            tooltip: '编辑贷款',
            onPressed: _isLoading ? null : _editLoan,
            icon: const Icon(Icons.edit_outlined),
          ),
        ],
      ),
      body: _buildBody(Theme.of(context).colorScheme),
    );
  }
}
