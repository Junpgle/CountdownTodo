import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/finance_models.dart';
import '../services/finance_automation_service.dart';
import '../services/finance_repository.dart';
import '../services/finance_storage.dart';
import '../services/ai_usage_cost_service.dart';
import '../../../widgets/floating_bottom_bar.dart';
import '../../../widgets/floating_glass_control.dart';
import '../../../widgets/home_bottom_navigation_content.dart';
import '../../../utils/page_transitions.dart';
import '../widgets/finance_widgets.dart';
import 'finance_automation_screen.dart';
import 'ai_usage_cost_screen.dart';
import 'finance_budget_screen.dart';
import 'finance_entry_screen.dart';
import 'finance_loan_screen.dart';
import 'finance_settings_screen.dart';
import 'finance_text_recognition_screen.dart';
import 'finance_trash_screen.dart';
import 'finance_transaction_detail_screen.dart';
import '../../../utils/app_dialogs.dart';

typedef _FinanceHomeData = ({
  List<FinanceTransaction> transactions,
  FinanceSummary summary,
  List<FinanceCategory> categories,
  List<FinancePaymentMethod> paymentMethods,
  List<FinanceTransaction> overviewTransactions,
  List<FinanceRecurringRule> recurringRules,
});

class FinanceHomeScreen extends StatefulWidget {
  final String username;
  final bool openQuickEntry;
  final DateTime Function() clock;
  final DateTime? initialMonth;
  final String? initialCategoryFilterUuid;
  final _FinanceHomeData? _initialData;

  const FinanceHomeScreen({
    super.key,
    required this.username,
    this.openQuickEntry = false,
    this.clock = DateTime.now,
  }) : initialMonth = null,
       initialCategoryFilterUuid = null,
       _initialData = null;

  const FinanceHomeScreen._categoryLedger({
    required this.username,
    required DateTime month,
    required String categoryUuid,
    required this._initialData,
    this.clock = DateTime.now,
  }) : openQuickEntry = false,
       initialMonth = month,
       initialCategoryFilterUuid = categoryUuid;

  @override
  State<FinanceHomeScreen> createState() => _FinanceHomeScreenState();
}

class _FinanceHomeScreenState extends State<FinanceHomeScreen> {
  late DateTime _month;
  List<FinanceTransaction> _transactions = const [];
  List<FinanceTransaction> _overviewTransactions = const [];
  List<FinanceCategory> _categories = const [];
  List<FinancePaymentMethod> _paymentMethods = const [];
  List<FinanceRecurringRule> _recurringRules = const [];
  FinanceSummary _summary = const FinanceSummary();
  String _keyword = '';
  FinanceTransactionType? _filterType;
  String? _categoryFilterUuid;
  int _selectedIndex = 0;
  bool _isLoading = true;
  String? _loadError;
  int _loadGeneration = 0;
  bool _maintenanceScheduled = false;
  Future<void>? _maintenanceFuture;
  String? _lastRecurringRuleSignature;
  Timer? _upcomingTransactionTimer;
  Timer? _autoGenerationTimer;
  Timer? _financeChangeRefreshTimer;
  final GlobalKey _overviewAddActionKey = GlobalKey();
  final GlobalKey _bottomAddActionKey = GlobalKey();

  Map<String, FinanceCategory> get _categoryMap => {
    for (final item in _categories) item.uuid: item,
  };

  Map<String, FinancePaymentMethod> get _paymentMethodMap => {
    for (final item in _paymentMethods) item.uuid: item,
  };

  bool get _hasLedgerFilters =>
      _keyword.trim().isNotEmpty ||
      _filterType != null ||
      _categoryFilterUuid != null;

  bool get _isCategoryLedgerRoute => widget.initialCategoryFilterUuid != null;

  bool get _hasManualLedgerFilters =>
      _keyword.trim().isNotEmpty || _filterType != null;

  bool get _clearFiltersBeforePop =>
      _isCategoryLedgerRoute ? _hasManualLedgerFilters : _hasLedgerFilters;

  bool get _handleLedgerBack =>
      _selectedIndex == 1 &&
      (!_isCategoryLedgerRoute || _clearFiltersBeforePop);

  void _clearLedgerFilters() {
    if (!_clearFiltersBeforePop) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _keyword = '';
      _filterType = null;
      if (!_isCategoryLedgerRoute) _categoryFilterUuid = null;
    });
  }

  void _returnToOverview() {
    if (_selectedIndex != 1) return;
    FocusScope.of(context).unfocus();
    setState(() => _selectedIndex = 0);
  }

  void _handleBack() {
    if (_clearFiltersBeforePop) {
      _clearLedgerFilters();
    } else if (_isCategoryLedgerRoute) {
      unawaited(Navigator.of(context).maybePop());
    } else {
      _returnToOverview();
    }
  }

  @override
  void initState() {
    super.initState();
    FinanceStorage.revision.addListener(_onFinanceStorageChanged);
    final initialMonth = widget.initialMonth ?? widget.clock();
    _month = DateTime(initialMonth.year, initialMonth.month);
    if (_isCategoryLedgerRoute) {
      _categoryFilterUuid = widget.initialCategoryFilterUuid;
      _selectedIndex = 1;
    }
    final initialData = widget._initialData;
    if (initialData == null) {
      _load();
    } else {
      _transactions = initialData.transactions;
      _summary = initialData.summary;
      _categories = initialData.categories;
      _paymentMethods = initialData.paymentMethods;
      _overviewTransactions = initialData.overviewTransactions;
      _recurringRules = initialData.recurringRules;
      _lastRecurringRuleSignature = _recurringRuleSignature(
        initialData.recurringRules,
      );
      _isLoading = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _scheduleUpcomingTransactionRefresh();
        _scheduleNextAutoGeneration();
      });
    }
    if (widget.openQuickEntry) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _openEntry();
      });
    }
  }

  @override
  void dispose() {
    _upcomingTransactionTimer?.cancel();
    _autoGenerationTimer?.cancel();
    _financeChangeRefreshTimer?.cancel();
    FinanceStorage.revision.removeListener(_onFinanceStorageChanged);
    super.dispose();
  }

  void _onFinanceStorageChanged() {
    _financeChangeRefreshTimer?.cancel();
    _financeChangeRefreshTimer = Timer(const Duration(milliseconds: 100), () {
      _financeChangeRefreshTimer = null;
      if (mounted) unawaited(_load(showLoading: false));
    });
  }

  Future<void> _load({bool showLoading = true}) async {
    _upcomingTransactionTimer?.cancel();
    _upcomingTransactionTimer = null;
    _autoGenerationTimer?.cancel();
    _autoGenerationTimer = null;
    final generation = ++_loadGeneration;
    if (mounted && showLoading) {
      setState(() {
        _isLoading = true;
        _loadError = null;
      });
    }
    try {
      final data = await _loadOverviewData();
      if (!mounted || generation != _loadGeneration) return;
      final recurringRuleSignature = _recurringRuleSignature(
        data.recurringRules,
      );
      final shouldReconcileRecurringRules =
          _lastRecurringRuleSignature != null &&
          _lastRecurringRuleSignature != recurringRuleSignature;
      _lastRecurringRuleSignature = recurringRuleSignature;
      setState(() {
        _transactions = data.transactions;
        _summary = data.summary;
        _categories = data.categories;
        _paymentMethods = data.paymentMethods;
        _overviewTransactions = data.overviewTransactions;
        _recurringRules = data.recurringRules;
        _isLoading = false;
      });
      _scheduleUpcomingTransactionRefresh();
      _scheduleNextAutoGeneration();
      if (!_isCategoryLedgerRoute) {
        _startBackgroundMaintenance(generation);
        if (shouldReconcileRecurringRules) {
          unawaited(_reconcileAutoGeneration());
        }
      }
    } catch (error) {
      if (!mounted || generation != _loadGeneration) return;
      if (showLoading) {
        setState(() {
          _isLoading = false;
          _loadError = error.toString();
        });
      }
    }
  }

  String _recurringRuleSignature(Iterable<FinanceRecurringRule> rules) {
    final values = rules
        .map(
          (rule) => [
            rule.uuid,
            rule.name,
            rule.type.name,
            rule.amountMinor,
            rule.currencyCode,
            rule.categoryUuid,
            rule.paymentMethodUuid,
            rule.merchant,
            rule.note,
            rule.frequency.name,
            rule.dayOfMonth,
            rule.monthOfYear,
            rule.startDate,
            rule.endDate,
            rule.reminderMinutes,
            rule.autoGenerate,
            rule.isEnabled,
          ],
        )
        .toList()
      ..sort(
        (left, right) => left.first.toString().compareTo(right.first.toString()),
      );
    return jsonEncode(values);
  }

  Future<_FinanceHomeData> _loadOverviewData() async {
    final from = DateTime(_month.year, _month.month);
    final to = DateTime(_month.year, _month.month + 1);
    // 周视图需要覆盖月初前和月末后的完整自然周，避免边界日期被截断。
    final overviewFrom = financeCalendarDayOffset(from, -7);
    final overviewTo = financeCalendarDayOffset(to, 7);
    final values = await Future.wait<dynamic>([
      // 这个范围已经包含本月，后续在内存中切出本月账单，避免重复查询。
      FinanceRepository.getTransactions(from: overviewFrom, to: overviewTo),
      FinanceRepository.getCategories(includeArchived: true),
      FinanceRepository.getPaymentMethods(includeArchived: true),
      FinanceRepository.getRecurringRules(enabledOnly: true),
    ]);
    final overviewTransactions = values[0] as List<FinanceTransaction>;
    final fromKey = dateKey(from);
    final toKey = dateKey(to);
    final transactions = overviewTransactions
        .where(
          (transaction) =>
              transaction.transactionDate.compareTo(fromKey) >= 0 &&
              transaction.transactionDate.compareTo(toKey) < 0,
        )
        .toList(growable: false);
    final now = widget.clock();
    final isCurrentMonth = from.year == now.year && from.month == now.month;
    return (
      transactions: transactions,
      summary: FinanceSummary.fromTransactions(
        transactions,
        asOfAt: isCurrentMonth ? now.millisecondsSinceEpoch : null,
      ),
      categories: values[1] as List<FinanceCategory>,
      paymentMethods: values[2] as List<FinancePaymentMethod>,
      overviewTransactions: overviewTransactions,
      recurringRules: values[3] as List<FinanceRecurringRule>,
    );
  }

  void _scheduleUpcomingTransactionRefresh() {
    _upcomingTransactionTimer?.cancel();
    _upcomingTransactionTimer = null;
    final currentDate = widget.clock();
    final now = currentDate.millisecondsSinceEpoch;
    final currentMonth = DateTime(currentDate.year, currentDate.month);
    if (_month.isBefore(currentMonth)) {
      return;
    }

    final monthStart = DateTime(_month.year, _month.month);
    var nextEventAt = monthStart.isAfter(currentMonth)
        ? monthStart.millisecondsSinceEpoch
        : DateTime(_month.year, _month.month + 1).millisecondsSinceEpoch;
    for (final transaction in _overviewTransactions) {
      final eventAt = transaction.balanceEventAt();
      if (eventAt > now && eventAt < nextEventAt) {
        nextEventAt = eventAt;
      }
    }
    final delayMs = (nextEventAt - now + 1)
        .clamp(1, const Duration(days: 24).inMilliseconds)
        .toInt();
    _upcomingTransactionTimer = Timer(Duration(milliseconds: delayMs), () {
      _upcomingTransactionTimer = null;
      if (mounted) unawaited(_load(showLoading: false));
    });
  }

  void _scheduleNextAutoGeneration() {
    _autoGenerationTimer?.cancel();
    _autoGenerationTimer = null;
    final now = widget.clock();
    final dueAt = FinanceAutomationService.nextAutoGenerationDueAfter(
      _recurringRules,
      now: now,
    );
    if (dueAt == null) return;

    final delayMs =
        (dueAt.millisecondsSinceEpoch - now.millisecondsSinceEpoch + 1)
            .clamp(1, const Duration(days: 24).inMilliseconds)
            .toInt();
    _autoGenerationTimer = Timer(Duration(milliseconds: delayMs), () {
      _autoGenerationTimer = null;
      if (mounted) unawaited(_reconcileAutoGeneration());
    });
  }

  Future<void> _reconcileAutoGeneration() async {
    try {
      await FinanceAutomationService.reconcileCurrentPeriod(
        now: widget.clock(),
      );
    } catch (error) {
      // 自动账单补偿失败不应影响已经打开的记账首页。
    }
    if (mounted) await _load(showLoading: false);
  }

  void _startBackgroundMaintenance(int generation) {
    if (_maintenanceFuture != null || _maintenanceScheduled) return;
    _maintenanceScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _maintenanceScheduled = false;
      if (!mounted ||
          generation != _loadGeneration ||
          _maintenanceFuture != null) {
        return;
      }
      final future = _reconcileAfterFirstPaint(generation);
      _maintenanceFuture = future;
      unawaited(future);
    });
  }

  Future<void> _reconcileAfterFirstPaint(int generation) async {
    try {
      var needsRefresh = false;
      try {
        needsRefresh =
            await FinanceAutomationService.reconcileCurrentPeriod(
              now: widget.clock(),
            ) >
            0;
      } catch (_) {
        // 自动化异常不应阻断已有账单的查看和手动记账。
      }
      try {
        needsRefresh =
            await AiUsageCostService.reconcileCurrentMonth() || needsRefresh;
      } catch (_) {
        // AI 费用补偿失败不应阻断已有账单的查看和手动记账。
      }
      if (!needsRefresh || !mounted || generation != _loadGeneration) return;

      final data = await _loadOverviewData();
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _transactions = data.transactions;
        _summary = data.summary;
        _categories = data.categories;
        _paymentMethods = data.paymentMethods;
        _overviewTransactions = data.overviewTransactions;
      });
    } catch (_) {
      // 后台补偿失败不覆盖已经可见的首屏数据。
    }
  }

  Future<void> _openEntry({
    FinanceTransaction? transaction,
    FinanceEntryTemplate? initialTemplate,
    GlobalKey? sourceKey,
  }) async {
    final page = FinanceEntryScreen(
      transaction: transaction,
      initialTemplate: initialTemplate,
    );
    final result = sourceKey == null
        ? await Navigator.of(context).push<FinanceTransaction>(
            PageTransitions.material(builder: (_) => page),
          )
        : await PageTransitions.pushFromRect<FinanceTransaction>(
            context: context,
            page: page,
            sourceKey: sourceKey,
            placeholderIcon: Icons.account_balance_wallet_outlined,
            sourceBorderRadius: BorderRadius.circular(18),
          );
    if (result != null && mounted) await _load();
  }

  Future<void> _openRefund(FinanceTransaction original) async {
    final remaining = await FinanceRepository.getRemainingRefundableMinor(
      original.uuid,
    );
    if (!mounted) return;
    if (remaining <= 0) {
      AppSnackBars.showSnackBar(
        context,
        const SnackBar(content: Text('该账单已全部退款')),
      );
      return;
    }
    final result = await Navigator.of(context).push<FinanceTransaction>(
      PageTransitions.material(
        builder: (_) => FinanceEntryScreen(originalTransaction: original),
      ),
    );
    if (result != null && mounted) await _load();
  }

  Future<void> _openDetail(
    FinanceTransaction transaction,
    GlobalKey sourceKey,
  ) async {
    final colorScheme = Theme.of(context).colorScheme;
    final category = _categoryMap[transaction.categoryUuid];
    final categoryDisplayName = category == null
        ? null
        : financeCategoryDisplayName(category, _categories);
    final result = await PageTransitions.pushFromRect<FinanceTransaction>(
      context: context,
      page: FinanceTransactionDetailScreen(
        transaction: transaction,
        category: category,
        categoryDisplayName: categoryDisplayName,
        paymentMethod: _paymentMethodMap[transaction.paymentMethodUuid],
      ),
      sourceKey: sourceKey,
      sourceColor: colorScheme.surfaceContainerLow,
      placeholderBuilder: (_) => Text(
        category?.icon.isNotEmpty == true ? category!.icon : '💰',
        style: const TextStyle(fontSize: 30),
      ),
      sourceBorderRadius: BorderRadius.circular(18),
    );
    if (result != null && mounted) await _load();
  }

  Future<void> _openSettings() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => FinanceSettingsScreen(username: widget.username),
      ),
    );
    if (mounted) await _load();
  }

  Future<void> _openTextRecognition() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const FinanceTextRecognitionScreen()),
    );
    if (mounted) await _load();
  }

  Future<void> _openBudgets() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => FinanceBudgetScreen(initialMonth: _month),
      ),
    );
    if (mounted) await _load();
  }

  Future<void> _openLoans() async {
    await Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const FinanceLoanScreen()));
    if (mounted) await _load();
  }

  Future<void> _openAutomation() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const FinanceAutomationScreen()));
    if (mounted) await _load();
  }

  String _deleteTransactionDescription(
    FinanceTransaction transaction, {
    required bool hasPaymentMethod,
  }) {
    if (transaction.balanceEventAt() > widget.clock().millisecondsSinceEpoch) {
      final label = switch (transaction.type) {
        FinanceTransactionType.expense => '支出',
        FinanceTransactionType.income => '收入',
        FinanceTransactionType.refund => '退款',
      };
      final effect = hasPaymentMethod
          ? '，不会影响当前付款方式余额'
          : transaction.type == FinanceTransactionType.refund
          ? '，不再抵扣净支出'
          : '';
      return '删除后，这笔计划$label会从未来账单中移除$effect。确认继续吗？';
    }

    return switch (transaction.type) {
      FinanceTransactionType.expense => hasPaymentMethod
          ? '删除后，这笔支出不再计入统计，付款方式余额会相应增加。确认继续吗？'
          : '删除后不会计入统计，确认继续吗？',
      FinanceTransactionType.income => hasPaymentMethod
          ? '删除后，这笔收入不再计入统计，付款方式余额会相应减少。确认继续吗？'
          : '删除后不会计入统计，确认继续吗？',
      FinanceTransactionType.refund => hasPaymentMethod
          ? '删除后，这笔退款不再抵扣净支出，也不再增加该付款方式的余额。确认继续吗？'
          : '删除后，这笔退款不再抵扣净支出。确认继续吗？',
    };
  }

  Future<void> _deleteTransaction(FinanceTransaction transaction) async {
    if (transaction.type == FinanceTransactionType.expense) {
      final transactionsToCheck =
          transaction.isInstallment && transaction.installmentGroupUuid != null
          ? await FinanceRepository.getInstallmentGroup(
              transaction.installmentGroupUuid!,
            )
          : [transaction];
      for (final item in transactionsToCheck) {
        final refunds = await FinanceRepository.getRefundsForTransaction(
          item.uuid,
        );
        if (refunds.isEmpty) continue;
        if (!mounted) return;
        AppSnackBars.showSnackBar(
          context,
          const SnackBar(content: Text('该账单已关联退款，请先处理退款记录')),
        );
        return;
      }
    }
    if (!mounted) return;
    final hasPaymentMethod = _paymentMethodMap.containsKey(
      transaction.paymentMethodUuid?.trim(),
    );
    final deleteDescription = _deleteTransactionDescription(
      transaction,
      hasPaymentMethod: hasPaymentMethod,
    );
    final installmentDeleteDescription = switch (transaction.type) {
      FinanceTransactionType.expense => hasPaymentMethod
          ? '删除后不会计入统计；已发生期次会相应增加付款方式余额，'
              '未发生期次会从未来计划中移除。'
          : '删除后不会计入统计；未发生期次会从未来计划中移除。',
      FinanceTransactionType.income => hasPaymentMethod
          ? '删除后不会计入统计；已发生期次会相应减少付款方式余额，'
              '未发生期次会从未来计划中移除。'
          : '删除后不会计入统计；未发生期次会从未来计划中移除。',
      FinanceTransactionType.refund => hasPaymentMethod
          ? '删除后不会计入统计；已发生期次不再抵扣净支出，也不再增加付款方式余额，'
              '未发生期次会从未来计划中移除。'
          : '删除后不会计入统计；未发生期次会从未来计划中移除。',
    };
    final deleteMode = transaction.isInstallment
        ? await showAppDialog<String>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('删除分期账单？'),
              content: Text(
                '这是第 ${transaction.installmentIndex}/${transaction.installmentCount} 期。'
                '$installmentDeleteDescription',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('取消'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context, 'single'),
                  child: const Text('只删本期'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, 'group'),
                  child: const Text('删除整组'),
                ),
              ],
            ),
          )
        : await showAppDialog<String>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('删除账单？'),
              content: Text(deleteDescription),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, 'single'),
                  child: const Text('删除'),
                ),
              ],
            ),
          );
    if (deleteMode == null) return;
    try {
      if (deleteMode == 'group' && transaction.installmentGroupUuid != null) {
        await FinanceRepository.deleteInstallmentGroup(
          transaction.installmentGroupUuid!,
        );
      } else {
        await FinanceRepository.deleteTransaction(transaction.uuid);
      }
    } catch (error) {
      if (!mounted) return;
      AppSnackBars.showSnackBar(
        context,
        SnackBar(
          content: Text(
            error is StateError ? error.message.toString() : '删除账单失败：$error',
          ),
        ),
      );
      return;
    }
    if (mounted) {
      AppSnackBars.showSnackBar(
        context,
        SnackBar(content: Text(deleteMode == 'group' ? '整组分期账单已删除' : '账单已删除')),
      );
      await _load();
    }
  }

  Future<void> _exportCsv() async {
    try {
      final path = await FinanceRepository.exportCsv(
        transactions: _transactions,
        categories: _categoryMap,
        paymentMethods: _paymentMethodMap,
      );
      if (!mounted) return;
      AppSnackBars.showSnackBar(
        context,
        SnackBar(
          content: Text(
            path == null
                ? '已取消导出'
                : '已导出$_selectedMonthLabel账单${path.isEmpty ? '' : '：$path'}',
          ),
          duration: const Duration(seconds: 4),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      AppSnackBars.showSnackBar(
        context,
        SnackBar(
          content: Text('导出失败：$error'),
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  String get _selectedMonthLabel {
    final now = widget.clock();
    return _month.year == now.year && _month.month == now.month
        ? '本月'
        : '${_month.year}年${_month.month}月';
  }

  void _setMonth(DateTime value) {
    setState(() {
      _month = DateTime(value.year, value.month);
    });
    _load();
  }

  Future<void> _pushCategoryLedger(
    String categoryUuid,
    GlobalKey sourceKey,
    List<FinanceTransaction> periodTransactions,
  ) async {
    final category = _categoryMap[categoryUuid];
    final colorScheme = Theme.of(context).colorScheme;
    await PageTransitions.pushFromRect<void>(
      context: context,
      page: FinanceHomeScreen._categoryLedger(
        username: widget.username,
        month: _month,
        categoryUuid: categoryUuid,
        initialData: (
          transactions: periodTransactions,
          summary: _summary,
          categories: _categories,
          paymentMethods: _paymentMethods,
          overviewTransactions: _overviewTransactions,
          recurringRules: _recurringRules,
        ),
        clock: widget.clock,
      ),
      sourceKey: sourceKey,
      sourceColor: colorScheme.brightness == Brightness.dark
          ? Colors.black
          : Colors.white,
      placeholderBuilder: (_) =>
          Text(category?.icon ?? '💰', style: const TextStyle(fontSize: 30)),
      sourceBorderRadius: BorderRadius.circular(12),
    );
    if (mounted) await _load(showLoading: false);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final topBarHeight = floatingGlassTopBarHeight(context);
    final scaffold = Scaffold(
      extendBody: true,
      extendBodyBehindAppBar: true,
      appBar: FloatingGlassAppBar(
        flexibleSpace: const FloatingGlassTopBarBackground(),
        title: const Text('记账'),
        leading: _selectedIndex == 1
            ? IconButton(
                style: floatingGlassPlainIconButtonStyle(),
                tooltip: _clearFiltersBeforePop
                    ? _isCategoryLedgerRoute
                          ? '取消附加筛选'
                          : '返回全部账单'
                    : _isCategoryLedgerRoute
                    ? '返回支出分类'
                    : '返回概览',
                onPressed: _handleBack,
                icon: const Icon(Icons.arrow_back_ios_new_rounded),
              )
            : null,
        actions: [
          IconButton(
            style: floatingGlassPlainIconButtonStyle(),
            tooltip: '预算',
            onPressed: _openBudgets,
            icon: const Icon(Icons.track_changes_outlined),
          ),
          PopupMenuButton<String>(
            style: floatingGlassPlainIconButtonStyle(),
            tooltip: '更多操作',
            onSelected: (value) {
              if (value == 'settings') _openSettings();
              if (value == 'text') _openTextRecognition();
              if (value == 'automation') _openAutomation();
              if (value == 'loans') _openLoans();
              if (value == 'ai_cost') {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const AiUsageCostScreen()),
                );
              }
              if (value == 'export') _exportCsv();
              if (value == 'trash') {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const FinanceTrashScreen()),
                );
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'text',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.text_snippet_outlined),
                  title: Text('文本识别记账'),
                ),
              ),
              PopupMenuItem(
                value: 'export',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.file_download_outlined),
                  title: Text('导出$_selectedMonthLabel账单 CSV'),
                ),
              ),
              const PopupMenuItem(
                value: 'automation',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.autorenew_outlined),
                  title: Text('自动化与快捷模板'),
                ),
              ),
              const PopupMenuItem(
                value: 'loans',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.account_balance_outlined),
                  title: Text('贷款'),
                ),
              ),
              const PopupMenuItem(
                value: 'ai_cost',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.auto_awesome_outlined),
                  title: Text('AI 调用费用'),
                ),
              ),
              PopupMenuItem(
                value: 'settings',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.settings_outlined),
                  title: Text('记账设置'),
                ),
              ),
              const PopupMenuItem(
                value: 'trash',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.delete_outline),
                  title: Text('记账回收站'),
                ),
              ),
            ],
          ),
        ],
      ),
      body: FloatingGlassTopBarContentFade(
        topBarHeight: topBarHeight,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _loadError != null
            ? _buildError(colorScheme)
            : Column(
                children: [
                  Expanded(
                    child: IndexedStack(
                      index: _selectedIndex,
                      children: [
                        FinanceOverviewPanel(
                          topPadding: topBarHeight,
                          month: _month,
                          clock: widget.clock,
                          summary: _summary,
                          transactions: _overviewTransactions,
                          categories: _categoryMap,
                          onAdd: () =>
                              _openEntry(sourceKey: _overviewAddActionKey),
                          addActionKey: _overviewAddActionKey,
                          onRefresh: _load,
                          onMonthChanged: _setMonth,
                          onCategorySelected: _pushCategoryLedger,
                        ),
                        FinanceLedgerPanel(
                          topPadding: topBarHeight,
                          month: _month,
                          clock: widget.clock,
                          transactions: _transactions,
                          categories: _categoryMap,
                          paymentMethods: _paymentMethodMap,
                          keyword: _keyword,
                          filterType: _filterType,
                          categoryUuid: _categoryFilterUuid,
                          onOpenDetail: _openDetail,
                          onKeywordChanged: (value) =>
                              setState(() => _keyword = value),
                          onFilterChanged: (value) =>
                              setState(() => _filterType = value),
                          onCategoryChanged: (value) =>
                              setState(() => _categoryFilterUuid = value),
                          onEdit: (transaction) =>
                              _openEntry(transaction: transaction),
                          onDelete: _deleteTransaction,
                          onRefund: _openRefund,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
      ),
      // 记账入口固定在底栏中央，避免扩展 FAB 覆盖账单内容。
      bottomNavigationBar: FloatingBottomNavigationBar(
        mobilePortraitOnly: false,
        items: [
          const FloatingBottomNavigationItem(
            icon: Icons.insights_outlined,
            label: '概览',
          ),
          FloatingBottomNavigationItem(
            label: '记一笔',
            selectable: false,
            onPressed: () => _openEntry(sourceKey: _bottomAddActionKey),
            builder: (context, selectedLayer, interactive) => Center(
              child: HomeBottomNavigationActionButton(
                buttonKey: selectedLayer ? null : _bottomAddActionKey,
                primaryColor: colorScheme.primary,
                interactive: interactive,
                onPressed: () => _openEntry(sourceKey: _bottomAddActionKey),
                semanticsLabel: '记一笔',
                child: Icon(
                  Icons.add_rounded,
                  color: colorScheme.onPrimary,
                  size: 28,
                ),
              ),
            ),
          ),
          const FloatingBottomNavigationItem(
            icon: Icons.receipt_long_outlined,
            label: '账单',
          ),
        ],
        selectedIndex: _selectedIndex == 0 ? 0 : 2,
        onTabSelected: (index) {
          if (index == 0) {
            setState(() => _selectedIndex = 0);
          } else if (index == 2) {
            setState(() => _selectedIndex = 1);
          }
        },
      ),
    );
    final guardedScaffold = PopScope<Object?>(
      canPop: !_handleLedgerBack,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _handleLedgerBack) {
          _handleBack();
        }
      },
      child: scaffold,
    );

    final isDesktop =
        !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.windows ||
            defaultTargetPlatform == TargetPlatform.macOS ||
            defaultTargetPlatform == TargetPlatform.linux);
    if (!isDesktop) return guardedScaffold;
    return Shortcuts(
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.keyN, control: true, shift: true):
            _FinanceQuickEntryIntent(),
        SingleActivator(LogicalKeyboardKey.keyN, meta: true, shift: true):
            _FinanceQuickEntryIntent(),
      },
      child: Actions(
        actions: {
          _FinanceQuickEntryIntent: CallbackAction<_FinanceQuickEntryIntent>(
            onInvoke: (_) {
              unawaited(_openEntry());
              return null;
            },
          ),
        },
        child: Focus(autofocus: true, child: guardedScaffold),
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
            const Text('记账数据加载失败'),
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

class _FinanceQuickEntryIntent extends Intent {
  const _FinanceQuickEntryIntent();
}
