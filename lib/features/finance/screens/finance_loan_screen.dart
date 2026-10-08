import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../widgets/floating_glass_control.dart';
import '../models/finance_models.dart';
import '../services/finance_repository.dart';
import '../services/finance_storage.dart';
import '../widgets/finance_management_widgets.dart';
import '../widgets/finance_loan_payment_dialog.dart';
import 'finance_loan_entry_screen.dart';
import '../../../utils/app_dialogs.dart';

const _maxOverdueRefreshDelay = Duration(days: 24);

DateTime? _nextOverdueBoundary(
  Iterable<FinanceLoanInstallment> installments,
  DateTime now,
) {
  DateTime? nextBoundary;
  for (final installment in installments) {
    if (installment.isPaid) continue;
    final dueDate = dateFromKey(installment.dueDate);
    final boundary = DateTime(dueDate.year, dueDate.month, dueDate.day + 1);
    if (boundary.isAfter(now) &&
        (nextBoundary == null || boundary.isBefore(nextBoundary))) {
      nextBoundary = boundary;
    }
  }
  return nextBoundary;
}

class FinanceLoanScreen extends StatefulWidget {
  final DateTime Function() clock;

  const FinanceLoanScreen({super.key, this.clock = DateTime.now});

  @override
  State<FinanceLoanScreen> createState() => _FinanceLoanScreenState();
}

class _FinanceLoanScreenState extends State<FinanceLoanScreen>
    with WidgetsBindingObserver {
  List<FinanceLoanOverview> _overviews = const [];
  bool? _paidOffFilter;
  bool _isLoading = true;
  String? _loadError;
  int _loadGeneration = 0;
  Timer? _overdueRefreshTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    FinanceStorage.revision.addListener(_onFinanceChanged);
    _load();
  }

  @override
  void dispose() {
    _overdueRefreshTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    FinanceStorage.revision.removeListener(_onFinanceChanged);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed || !mounted) return;
    setState(() {});
    _scheduleOverdueRefresh();
  }

  void _scheduleOverdueRefresh() {
    _overdueRefreshTimer?.cancel();
    final now = widget.clock();
    final boundary = _nextOverdueBoundary(
      _overviews.expand((overview) => overview.installments),
      now,
    );
    if (boundary == null) return;
    final remaining = boundary.difference(now);
    final delay = remaining > _maxOverdueRefreshDelay
        ? _maxOverdueRefreshDelay
        : remaining;
    _overdueRefreshTimer = Timer(delay, () {
      if (!mounted) return;
      setState(() {});
      _scheduleOverdueRefresh();
    });
  }

  void _onFinanceChanged() => _load(showLoading: false);

  String _displayName(FinanceLoan loan) => financeLoanDisplayName(
    loan,
    _overviews.map((overview) => overview.loan),
  );

  Future<void> _load({bool showLoading = true}) async {
    final generation = ++_loadGeneration;
    if (mounted && showLoading) {
      setState(() {
        _isLoading = true;
        _loadError = null;
      });
    }
    try {
      final loans = await FinanceRepository.getLoans();
      final installments = await Future.wait(
        loans.map((loan) => FinanceRepository.getLoanInstallments(loan.uuid)),
      );
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _overviews = [
          for (var index = 0; index < loans.length; index++)
            FinanceLoanOverview(
              loan: loans[index],
              installments: installments[index],
            ),
        ];
        _isLoading = false;
        _loadError = null;
      });
      _scheduleOverdueRefresh();
    } catch (error) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _isLoading = false;
        _loadError = error.toString();
      });
    }
  }

  Future<void> _openEditor([FinanceLoan? loan]) async {
    final result = await Navigator.of(context).push<FinanceLoan>(
      MaterialPageRoute(builder: (_) => FinanceLoanEntryScreen(loan: loan)),
    );
    if (result != null && mounted) await _load();
  }

  Future<void> _openDetail(FinanceLoanOverview overview) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            FinanceLoanDetailScreen(loan: overview.loan, clock: widget.clock),
      ),
    );
    if (mounted) await _load();
  }

  Future<void> _deleteLoan(FinanceLoan loan) async {
    final displayName = _displayName(loan);
    final confirmed = await showAppDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('删除“$displayName”？'),
        content: const Text(
          '贷款和还款计划会进入记账回收站，已发生的还款扣款和利息账单会保留。'
          '如需恢复余额，请先撤销对应还款。',
        ),
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
      AppSnackBars.showSnackBar(
        context,
        const SnackBar(content: Text('贷款已删除')),
      );
      await _load();
    } catch (error) {
      if (!mounted) return;
      _showError('删除贷款失败：$error');
    }
  }

  void _showError(String message) {
    AppSnackBars.showSnackBar(context, SnackBar(content: Text(message)));
  }

  Widget _buildLoanCard(BuildContext context, FinanceLoanOverview overview) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final loan = overview.loan;
    final displayName = _displayName(loan);
    final due = overview.nextInstallment;
    final isOverdue = due?.isOverdueAt(widget.clock()) == true;
    final progress = overview.installments.isEmpty
        ? 0.0
        : overview.paidCount / overview.installments.length;
    return FinanceSectionCard(
      key: ValueKey('finance-loan-card-${loan.uuid}'),
      onTap: () => _openDetail(overview),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      displayName,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      [
                        if (loan.lender?.isNotEmpty == true) loan.lender!,
                        loan.repaymentMethod.label,
                        '年利率 ${formatFinanceInterestRate(loan.annualInterestRateBps)}',
                      ].join(' · '),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                tooltip: '$displayName的更多操作',
                onSelected: (value) {
                  if (value == 'edit') _openEditor(loan);
                  if (value == 'delete') _deleteLoan(loan);
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'edit', child: Text('编辑')),
                  PopupMenuItem(value: 'delete', child: Text('移入回收站')),
                ],
              ),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            '剩余本金',
            style: theme.textTheme.labelMedium?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            formatFinanceAmount(overview.outstandingPrincipalMinor),
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 16),
          FinanceAdaptiveFields(
            minChildWidth: 145,
            children: [
              _metric(
                context,
                '预计总利息',
                formatFinanceAmount(overview.totalInterestMinor),
              ),
              _metric(
                context,
                '已还期数',
                '${overview.paidCount}/${overview.installments.length} 期',
              ),
            ],
          ),
          const SizedBox(height: 18),
          LinearProgressIndicator(
            value: progress,
            minHeight: 6,
            borderRadius: BorderRadius.circular(8),
            backgroundColor: colors.surfaceContainerHighest,
          ),
          const SizedBox(height: 14),
          FinanceStatusBadge(
            label: overview.isPaidOff
                ? '已全部还清'
                : (isOverdue ? '有逾期待还' : '还款中'),
            icon: overview.isPaidOff
                ? Icons.check_circle_outline
                : Icons.schedule_outlined,
            highlighted: overview.isPaidOff,
            isError: isOverdue,
          ),
          if (!overview.isPaidOff) ...[
            const SizedBox(height: 10),
            Text(
              '下期 ${due?.dueDate ?? '-'} · 应还 ${formatFinanceAmount(due?.paymentMinor ?? 0)}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () => _openDetail(overview),
              icon: const Icon(Icons.arrow_forward_rounded, size: 18),
              label: const Text('查看还款计划'),
            ),
          ),
        ],
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
          style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 12),
        ),
        const SizedBox(height: 3),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
      ],
    );
  }

  Widget _buildBody(ColorScheme colorScheme, double topPadding) {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    if (_loadError != null) {
      return FinancePageList(
        topPadding: topPadding,
        children: [
          FinanceEmptyState(
            icon: Icons.error_outline_rounded,
            title: '贷款加载失败',
            description: '请重新加载后查看还款进度。',
            actionLabel: '重试',
            onAction: _load,
          ),
        ],
      );
    }
    final visible = _overviews
        .where(
          (item) => _paidOffFilter == null || item.isPaidOff == _paidOffFilter,
        )
        .toList();
    final remaining = _overviews.fold<int>(
      0,
      (sum, item) => sum + item.outstandingPrincipalMinor,
    );
    return RefreshIndicator(
      onRefresh: _load,
      child: FinancePageList(
        topPadding: topPadding,
        bottomPadding: 112,
        children: [
          const FinancePageIntro(
            icon: Icons.account_balance_outlined,
            title: '贷款与还款',
            description: '本金、利息与还款进度，清楚地分开记录。',
          ),
          const SizedBox(height: 24),
          FinanceSectionCard(
            color: colorScheme.primaryContainer,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '剩余待还本金',
                  style: TextStyle(color: colorScheme.onPrimaryContainer),
                ),
                const SizedBox(height: 10),
                Text(
                  formatFinanceAmount(remaining),
                  style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                    color: colorScheme.onPrimaryContainer,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  '${_overviews.where((item) => !item.isPaidOff).length} 笔还款中 · ${_overviews.where((item) => item.isPaidOff).length} 笔已还清',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colorScheme.onPrimaryContainer.withValues(
                      alpha: 0.8,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              ChoiceChip(
                label: const Text('全部'),
                selected: _paidOffFilter == null,
                showCheckmark: false,
                onSelected: (_) => setState(() => _paidOffFilter = null),
              ),
              ChoiceChip(
                label: const Text('还款中'),
                selected: _paidOffFilter == false,
                showCheckmark: false,
                onSelected: (_) => setState(() => _paidOffFilter = false),
              ),
              ChoiceChip(
                label: const Text('已还清'),
                selected: _paidOffFilter == true,
                showCheckmark: false,
                onSelected: (_) => setState(() => _paidOffFilter = true),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (visible.isEmpty)
            FinanceEmptyState(
              icon: Icons.account_balance_wallet_outlined,
              title: _overviews.isEmpty ? '还没有贷款记录' : '这个分组暂无贷款',
              description: _overviews.isEmpty
                  ? '添加一笔贷款，自动生成每期还款计划。'
                  : '切换分组查看其他贷款。',
              actionLabel: _overviews.isEmpty ? '新增贷款' : '查看全部',
              onAction: _overviews.isEmpty
                  ? () => _openEditor()
                  : () => setState(() => _paidOffFilter = null),
            )
          else
            FinanceAdaptiveFields(
              minChildWidth: 330,
              children: [
                for (final overview in visible)
                  _buildLoanCard(context, overview),
              ],
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final topBarHeight = floatingGlassTopBarHeight(context);
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: FloatingGlassAppBar(
        flexibleSpace: const FloatingGlassTopBarBackground(),
        title: const Text('贷款'),
      ),
      body: FloatingGlassTopBarContentFade(
        topBarHeight: topBarHeight,
        child: _buildBody(colorScheme, topBarHeight),
      ),
      floatingActionButton: _isLoading || _loadError != null
          ? null
          : FloatingGlassActionButton.extended(
              onPressed: () => _openEditor(),
              icon: const Icon(Icons.add),
              label: const Text('新增贷款'),
            ),
    );
  }
}

class FinanceLoanDetailScreen extends StatefulWidget {
  final FinanceLoan loan;
  final DateTime Function() clock;

  const FinanceLoanDetailScreen({
    super.key,
    required this.loan,
    this.clock = DateTime.now,
  });

  @override
  State<FinanceLoanDetailScreen> createState() =>
      _FinanceLoanDetailScreenState();
}

class _FinanceLoanDetailScreenState extends State<FinanceLoanDetailScreen>
    with WidgetsBindingObserver {
  FinanceLoan? _loan;
  List<FinanceLoanInstallment> _installments = const [];
  List<FinancePaymentMethod> _paymentMethods = const [];
  bool? _paidFilter;
  final _updating = <String>{};
  bool _isLoading = true;
  String? _loadError;
  int _loadGeneration = 0;
  Timer? _overdueRefreshTimer;

  FinanceLoan get _currentLoan => _loan ?? widget.loan;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    FinanceStorage.revision.addListener(_onFinanceChanged);
    _load();
  }

  @override
  void dispose() {
    _overdueRefreshTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    FinanceStorage.revision.removeListener(_onFinanceChanged);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed || !mounted) return;
    setState(() {});
    _scheduleOverdueRefresh();
  }

  void _scheduleOverdueRefresh() {
    _overdueRefreshTimer?.cancel();
    final now = widget.clock();
    final boundary = _nextOverdueBoundary(_installments, now);
    if (boundary == null) return;
    final remaining = boundary.difference(now);
    final delay = remaining > _maxOverdueRefreshDelay
        ? _maxOverdueRefreshDelay
        : remaining;
    _overdueRefreshTimer = Timer(delay, () {
      if (!mounted) return;
      setState(() {});
      _scheduleOverdueRefresh();
    });
  }

  void _onFinanceChanged() => _load(showLoading: false);

  Future<void> _load({bool showLoading = true}) async {
    final generation = ++_loadGeneration;
    if (mounted && showLoading) {
      setState(() {
        _isLoading = true;
        _loadError = null;
      });
    }
    try {
      final loan = await FinanceRepository.getLoan(widget.loan.uuid);
      if (loan == null) throw StateError('贷款不存在或已删除');
      final installments = await FinanceRepository.getLoanInstallments(
        loan.uuid,
      );
      final paymentMethods = await FinanceRepository.getPaymentMethods(
        includeArchived: true,
      );
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _loan = loan;
        _installments = installments;
        _paymentMethods = paymentMethods;
        _isLoading = false;
        _loadError = null;
      });
      _scheduleOverdueRefresh();
    } catch (error) {
      if (!mounted || generation != _loadGeneration) return;
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

  Future<void> _togglePaid(
    FinanceLoanInstallment installment, {
    bool edit = false,
  }) async {
    if (!_updating.add(installment.uuid)) return;
    setState(() {});
    try {
      if (installment.isPaid && !edit) {
        await FinanceRepository.setLoanInstallmentPaid(installment.uuid, false);
      } else {
        final selection = await showAppDialog<FinanceLoanPaymentSelection>(
          context: context,
          builder: (_) => FinanceLoanPaymentDialog(
            installment: installment,
            paymentMethods: _paymentMethods,
          ),
        );
        if (selection == null || !mounted) return;
        await FinanceRepository.setLoanInstallmentPaid(
          installment.uuid,
          true,
          paymentMethodUuid: selection.paymentMethodUuid,
          paidAt: selection.paidAt,
        );
      }
    } catch (error) {
      if (!mounted) return;
      AppSnackBars.showSnackBar(
        context,
        SnackBar(
          content: Text(
            '更新还款状态失败：${error is StateError ? error.message : error}',
          ),
        ),
      );
    } finally {
      _updating.remove(installment.uuid);
      if (mounted) setState(() {});
    }
  }

  Widget _buildSummary(BuildContext context, FinanceLoanOverview overview) {
    final colors = Theme.of(context).colorScheme;
    return FinanceSectionCard(
      color: colors.primaryContainer,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            overview.loan.name,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              color: colors.onPrimaryContainer,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '${overview.loan.repaymentMethod.label} · 年利率 ${formatFinanceInterestRate(overview.loan.annualInterestRateBps)} · ${overview.loan.termMonths} 个月',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: colors.onPrimaryContainer.withValues(alpha: 0.8),
            ),
          ),
          const SizedBox(height: 22),
          Text(
            '剩余本金',
            style: TextStyle(
              color: colors.onPrimaryContainer.withValues(alpha: 0.8),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            formatFinanceAmount(overview.outstandingPrincipalMinor),
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
              color: colors.onPrimaryContainer,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 20),
          FinanceAdaptiveFields(
            minChildWidth: 150,
            children: [
              _summaryMetric(
                colors,
                '已付利息',
                formatFinanceAmount(overview.paidInterestMinor),
              ),
              _summaryMetric(
                colors,
                '已还期数',
                '${overview.paidCount}/${overview.installments.length}',
              ),
            ],
          ),
          if (overview.loan.note?.isNotEmpty == true) ...[
            const SizedBox(height: 16),
            Text(
              overview.loan.note!,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: colors.onPrimaryContainer.withValues(alpha: 0.8),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _summaryMetric(ColorScheme colors, String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: colors.onPrimaryContainer.withValues(alpha: 0.75),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: colors.onPrimaryContainer,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }

  String _repaymentAccountLabel(String? paymentMethodUuid) {
    if (paymentMethodUuid == null) return '未关联还款账户';
    final paymentMethod = _paymentMethods
        .where((item) => item.uuid == paymentMethodUuid)
        .firstOrNull;
    if (paymentMethod == null) return '还款账户：未知账户';
    final name = financePaymentMethodDisplayName(
      paymentMethod,
      _paymentMethods,
    );
    final archivedLabel = paymentMethod.isArchived ? '（已归档）' : '';
    return '还款账户：$name$archivedLabel';
  }

  Widget _buildInstallmentTile(
    BuildContext context,
    FinanceLoanInstallment installment,
  ) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final updating = _updating.contains(installment.uuid);
    final isOverdue = installment.isOverdueAt(widget.clock());
    return FinanceSectionCard(
      key: ValueKey('finance-loan-installment-${installment.uuid}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                '第 ${installment.installmentIndex} 期',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                installment.dueDate,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
              FinanceStatusBadge(
                label: installment.isPaid
                    ? '已还'
                    : isOverdue
                    ? '已逾期'
                    : '待还',
                highlighted: installment.isPaid,
                isError: !installment.isPaid && isOverdue,
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            '本期应还',
            style: theme.textTheme.labelMedium?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            formatFinanceAmount(installment.paymentMinor),
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 16),
          FinanceAdaptiveFields(
            minChildWidth: 150,
            children: [
              _installmentMetric('本金', installment.principalMinor),
              _installmentMetric('利息', installment.interestMinor),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            '还款后剩余 ${formatFinanceAmount(installment.remainingPrincipalMinor)}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 14),
          if (installment.isPaid) ...[
            Text(_repaymentAccountLabel(installment.paymentMethodUuid)),
            if (installment.paidAt != null)
              Text(
                '实际还款：${DateFormat('yyyy年M月d日 HH:mm').format(DateTime.fromMillisecondsSinceEpoch(installment.paidAt!))}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
            TextButton(
              key: ValueKey('finance-loan-payment-edit-${installment.uuid}'),
              onPressed: updating
                  ? null
                  : () => _togglePaid(installment, edit: true),
              child: const Text('修改还款账户或时间'),
            ),
          ],
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.tonalIcon(
              key: ValueKey('finance-loan-paid-${installment.uuid}'),
              onPressed: updating ? null : () => _togglePaid(installment),
              icon: Icon(
                installment.isPaid ? Icons.undo_rounded : Icons.check_rounded,
                size: 18,
              ),
              label: Text(
                updating
                    ? '更新中…'
                    : installment.isPaid
                    ? '撤销已还'
                    : '标记已还',
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _installmentMetric(String label, int amount) {
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
              ?.copyWith(fontWeight: FontWeight.w600),
        ),
      ],
    );
  }

  Widget _buildBody(ColorScheme colorScheme, double topPadding) {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    if (_loadError != null) {
      return FinancePageList(
        topPadding: topPadding,
        children: [
          FinanceEmptyState(
            icon: Icons.error_outline_rounded,
            title: '贷款加载失败',
            description: '请重新加载后查看还款计划。',
            actionLabel: '重试',
            onAction: _load,
          ),
        ],
      );
    }
    final overview = FinanceLoanOverview(
      loan: _currentLoan,
      installments: _installments,
    );
    final visible = _installments
        .where((item) => _paidFilter == null || item.isPaid == _paidFilter)
        .toList();
    final paidCount = _installments.where((item) => item.isPaid).length;
    return RefreshIndicator(
      onRefresh: _load,
      child: FinancePageList(
        topPadding: topPadding,
        maxWidth: 840,
        children: [
          _buildSummary(context, overview),
          const SizedBox(height: 24),
          Text(
            '还款计划',
            style: Theme.of(context).textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              ChoiceChip(
                key: const ValueKey('finance-loan-filter-all'),
                label: Text('全部 ${_installments.length}'),
                selected: _paidFilter == null,
                showCheckmark: false,
                onSelected: (_) => setState(() => _paidFilter = null),
              ),
              ChoiceChip(
                key: const ValueKey('finance-loan-filter-unpaid'),
                label: Text('待还 ${_installments.length - paidCount}'),
                selected: _paidFilter == false,
                showCheckmark: false,
                onSelected: (_) => setState(() => _paidFilter = false),
              ),
              ChoiceChip(
                key: const ValueKey('finance-loan-filter-paid'),
                label: Text('已还 $paidCount'),
                selected: _paidFilter == true,
                showCheckmark: false,
                onSelected: (_) => setState(() => _paidFilter = true),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (visible.isEmpty)
            FinanceEmptyState(
              icon: Icons.event_available_outlined,
              title: _paidFilter == false ? '没有待还的期数' : '这个分组暂无记录',
              description: '切换分组查看完整还款计划。',
              actionLabel: '查看全部',
              onAction: () => setState(() => _paidFilter = null),
            ),
          for (final installment in visible) ...[
            _buildInstallmentTile(context, installment),
            const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final topBarHeight = floatingGlassTopBarHeight(context);
    return Scaffold(
      extendBodyBehindAppBar: true,
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
      body: FloatingGlassTopBarContentFade(
        topBarHeight: topBarHeight,
        child: _buildBody(Theme.of(context).colorScheme, topBarHeight),
      ),
    );
  }
}
