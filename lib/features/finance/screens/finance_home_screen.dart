import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../services/storage/app_settings_storage.dart';
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
import '../widgets/finance_intro_guide.dart';
import 'finance_automation_screen.dart';
import 'ai_usage_cost_screen.dart';
import 'finance_budget_screen.dart';
import 'finance_entry_screen.dart';
import 'finance_future_commitments_screen.dart';
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
  List<FinanceCumulativeBalanceEvent> cumulativeBalanceEvents,
  List<FinanceRecurringRule> recurringRules,
});

class FinanceHomeScreen extends StatefulWidget {
  final String username;
  final bool openQuickEntry;
  final DateTime Function() clock;
  final DateTime? initialMonth;
  final String? initialCategoryFilterUuid;
  final DateTimeRange? initialLedgerDateRange;
  final _FinanceHomeData? _initialData;
  final bool _isMonthLedgerRoute;

  const FinanceHomeScreen({
    super.key,
    required this.username,
    this.openQuickEntry = false,
    this.clock = DateTime.now,
  }) : initialMonth = null,
       initialCategoryFilterUuid = null,
       initialLedgerDateRange = null,
       _initialData = null,
       _isMonthLedgerRoute = false;

  const FinanceHomeScreen._categoryLedger({
    required this.username,
    required DateTime month,
    required String categoryUuid,
    required this.initialLedgerDateRange,
    required this._initialData,
    this.clock = DateTime.now,
  }) : openQuickEntry = false,
       initialMonth = month,
       initialCategoryFilterUuid = categoryUuid,
       _isMonthLedgerRoute = false;

  const FinanceHomeScreen._monthLedger({
    required this.username,
    required DateTime month,
    required this.initialLedgerDateRange,
    required this._initialData,
    this.clock = DateTime.now,
  }) : openQuickEntry = false,
       initialMonth = month,
       initialCategoryFilterUuid = null,
       _isMonthLedgerRoute = true;

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
  List<FinanceCumulativeBalanceEvent> _cumulativeBalanceEvents = const [];
  FinanceSummary _summary = const FinanceSummary();
  int _openingBalanceMinor = 0;
  String? _openingBalanceStartDate;
  DateTimeRange? _ledgerDateRange;
  bool _isLedgerQueryLoading = false;
  String? _ledgerQueryError;
  String _keyword = '';
  FinanceTransactionType? _filterType;
  Set<String> _categoryFilterUuids = <String>{};
  bool _categoryTapOpensLedger = true;
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
  final GlobalKey _budgetActionKey = GlobalKey();
  final GlobalKey _moreActionKey = GlobalKey();
  bool _guideScheduled = false;
  bool _guideAttempted = false;
  bool _showingGuide = false;
  bool _quickEntryInProgress = false;
  List<FinanceCategory>? _categoryMapSource;
  Map<String, FinanceCategory>? _cachedCategoryMap;
  List<FinancePaymentMethod>? _paymentMethodMapSource;
  Map<String, FinancePaymentMethod>? _cachedPaymentMethodMap;

  Map<String, FinanceCategory> get _categoryMap {
    if (!identical(_categoryMapSource, _categories)) {
      _categoryMapSource = _categories;
      _cachedCategoryMap = {for (final item in _categories) item.uuid: item};
    }
    return _cachedCategoryMap!;
  }

  Map<String, FinancePaymentMethod> get _paymentMethodMap {
    if (!identical(_paymentMethodMapSource, _paymentMethods)) {
      _paymentMethodMapSource = _paymentMethods;
      _cachedPaymentMethodMap = {
        for (final item in _paymentMethods) item.uuid: item,
      };
    }
    return _cachedPaymentMethodMap!;
  }

  bool get _isCategoryLedgerRoute => widget.initialCategoryFilterUuid != null;

  bool get _isLedgerDrilldownRoute =>
      _isCategoryLedgerRoute || widget._isMonthLedgerRoute;

  bool _shouldClearFiltersBeforePop({
    required String keyword,
    required FinanceTransactionType? filterType,
    required Set<String> categoryUuids,
  }) {
    final hasManualFilters = keyword.trim().isNotEmpty || filterType != null;
    return _isCategoryLedgerRoute
        ? hasManualFilters
        : hasManualFilters || categoryUuids.isNotEmpty;
  }

  bool get _clearFiltersBeforePop => _shouldClearFiltersBeforePop(
    keyword: _keyword,
    filterType: _filterType,
    categoryUuids: _categoryFilterUuids,
  );

  bool get _handleLedgerBack =>
      _selectedIndex == 1 &&
      (!_isLedgerDrilldownRoute || _clearFiltersBeforePop);

  void _updateLedgerFilter({
    required VoidCallback update,
    required String keyword,
    required FinanceTransactionType? filterType,
    required Set<String> categoryUuids,
  }) {
    final willHaveClearableFilters = _shouldClearFiltersBeforePop(
      keyword: keyword,
      filterType: filterType,
      categoryUuids: categoryUuids,
    );
    if (willHaveClearableFilters != _clearFiltersBeforePop) {
      setState(update);
    } else {
      update();
    }
  }

  void _clearLedgerFilters() {
    if (!_clearFiltersBeforePop) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _keyword = '';
      _filterType = null;
      if (!_isCategoryLedgerRoute) _categoryFilterUuids.clear();
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
    } else if (_isLedgerDrilldownRoute) {
      unawaited(Navigator.of(context).maybePop());
    } else {
      _returnToOverview();
    }
  }

  @override
  void initState() {
    super.initState();
    _quickEntryInProgress = widget.openQuickEntry;
    FinanceStorage.revision.addListener(_onFinanceStorageChanged);
    _ledgerDateRange = widget.initialLedgerDateRange;
    _isLedgerQueryLoading = widget._isMonthLedgerRoute;
    final initialMonth = widget.initialMonth ?? widget.clock();
    _month = DateTime(initialMonth.year, initialMonth.month);
    if (_isLedgerDrilldownRoute) _selectedIndex = 1;
    if (_isCategoryLedgerRoute) {
      _categoryFilterUuids = <String>{widget.initialCategoryFilterUuid!};
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
      _cumulativeBalanceEvents = initialData.cumulativeBalanceEvents;
      _recurringRules = initialData.recurringRules;
      _lastRecurringRuleSignature = _recurringRuleSignature(
        initialData.recurringRules,
      );
      _isLoading = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _scheduleUpcomingTransactionRefresh();
        _scheduleNextAutoGeneration();
        if (widget._isMonthLedgerRoute) {
          unawaited(_loadMonthLedgerRange());
        }
      });
    }
    if (widget.openQuickEntry) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        try {
          await _openEntry();
        } finally {
          _quickEntryInProgress = false;
          if (mounted) _scheduleIntroGuide();
        }
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

  Future<void> _load({
    bool showLoading = true,
    bool refreshCumulativeBalanceEvents = true,
  }) async {
    _upcomingTransactionTimer?.cancel();
    _upcomingTransactionTimer = null;
    _autoGenerationTimer?.cancel();
    _autoGenerationTimer = null;
    final generation = ++_loadGeneration;
    if (mounted && (showLoading || _ledgerDateRange != null)) {
      setState(() {
        if (showLoading) {
          _isLoading = true;
          _loadError = null;
        }
        if (_ledgerDateRange != null) _isLedgerQueryLoading = true;
        if (_ledgerDateRange != null) _ledgerQueryError = null;
      });
    }
    try {
      final values = await Future.wait<Object>([
        _loadOverviewData(
          refreshCumulativeBalanceEvents: refreshCumulativeBalanceEvents,
        ),
        AppSettingsStorage.isFinanceCategoryTapOpensLedger(),
        AppSettingsStorage.getFinanceOpeningBalance(
          widget.username,
          now: widget.clock(),
        ),
      ]);
      final data = values[0] as _FinanceHomeData;
      final categoryTapOpensLedger = values[1] as bool;
      final openingBalance =
          values[2] as ({int amountMinor, String? startDate});
      var ledgerTransactions = data.transactions;
      final selectedRange = _ledgerDateRange;
      if (selectedRange != null) {
        ledgerTransactions = await FinanceRepository.getTransactions(
          from: selectedRange.start,
          to: financeCalendarDayOffset(selectedRange.end, 1),
        );
      }
      if (!mounted || generation != _loadGeneration) return;
      final recurringRuleSignature = _recurringRuleSignature(
        data.recurringRules,
      );
      final shouldReconcileRecurringRules =
          _lastRecurringRuleSignature != null &&
          _lastRecurringRuleSignature != recurringRuleSignature;
      _lastRecurringRuleSignature = recurringRuleSignature;
      setState(() {
        _transactions = ledgerTransactions;
        _summary = data.summary;
        _categories = data.categories;
        _paymentMethods = data.paymentMethods;
        _overviewTransactions = data.overviewTransactions;
        _cumulativeBalanceEvents = data.cumulativeBalanceEvents;
        _recurringRules = data.recurringRules;
        _categoryTapOpensLedger = categoryTapOpensLedger;
        _openingBalanceMinor = openingBalance.amountMinor;
        _openingBalanceStartDate = openingBalance.startDate;
        _isLedgerQueryLoading = false;
        _ledgerQueryError = null;
        _isLoading = false;
      });
      _scheduleUpcomingTransactionRefresh();
      _scheduleNextAutoGeneration();
      if (!_isLedgerDrilldownRoute) {
        _scheduleIntroGuide();
        _startBackgroundMaintenance(generation);
        if (shouldReconcileRecurringRules) {
          unawaited(_reconcileAutoGeneration());
        }
      }
    } catch (error) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        if (_isLedgerQueryLoading || _ledgerDateRange != null) {
          _ledgerQueryError = error.toString();
        }
        _isLedgerQueryLoading = false;
        if (showLoading) {
          _isLoading = false;
          _loadError = error.toString();
        }
      });
    }
  }

  void _scheduleIntroGuide() {
    if (_guideScheduled ||
        _guideAttempted ||
        _quickEntryInProgress ||
        _isLedgerDrilldownRoute ||
        _isLoading ||
        _loadError != null ||
        _selectedIndex != 0) {
      return;
    }
    _guideScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _guideScheduled = false;
      if (!mounted ||
          _quickEntryInProgress ||
          _selectedIndex != 0 ||
          ModalRoute.of(context)?.isCurrent == false) {
        return;
      }
      _guideAttempted = true;
      unawaited(_showIntroGuide());
    });
  }

  Future<void> _showIntroGuide({bool force = false}) async {
    if (_showingGuide ||
        !mounted ||
        _isLoading ||
        _loadError != null ||
        _quickEntryInProgress ||
        _isLedgerDrilldownRoute ||
        (!force && _selectedIndex != 0)) {
      return;
    }
    _showingGuide = true;
    try {
      if (_selectedIndex != 0) {
        setState(() => _selectedIndex = 0);
        await WidgetsBinding.instance.endOfFrame;
        if (!mounted) return;
      }
      await FinanceIntroGuide.show(
        context: context,
        addKey: _bottomAddActionKey,
        budgetKey: _budgetActionKey,
        moreKey: _moreActionKey,
        onOpenSettings: _openSettings,
        force: force,
      );
    } catch (error) {
      debugPrint('记账新手指引暂时无法显示：$error');
    } finally {
      _showingGuide = false;
    }
  }

  String _recurringRuleSignature(Iterable<FinanceRecurringRule> rules) {
    final values =
        rules
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
            (left, right) =>
                left.first.toString().compareTo(right.first.toString()),
          );
    return jsonEncode(values);
  }

  Future<_FinanceHomeData> _loadOverviewData({
    bool refreshCumulativeBalanceEvents = true,
  }) async {
    final from = DateTime(_month.year, _month.month);
    final to = DateTime(_month.year, _month.month + 1);
    // 周视图需要覆盖月初前和月末后的完整自然周，避免边界日期被截断。
    final overviewFrom = financeCalendarDayOffset(from, -7);
    final overviewTo = financeCalendarDayOffset(to, 7);
    final now = widget.clock();
    final balanceEventsThroughAt = overviewTo.isAfter(now)
        ? overviewTo.millisecondsSinceEpoch - 1
        : now.millisecondsSinceEpoch;
    final values = await Future.wait<dynamic>([
      // 这个范围已经包含本月，后续在内存中切出本月账单，避免重复查询。
      FinanceRepository.getTransactions(from: overviewFrom, to: overviewTo),
      refreshCumulativeBalanceEvents
          ? FinanceRepository.getCumulativeBalanceEvents(
              throughAt: balanceEventsThroughAt,
            )
          : Future.value(_cumulativeBalanceEvents),
      FinanceRepository.getCategories(
        includeArchived: true,
        includeDeleted: true,
      ),
      FinanceRepository.getPaymentMethods(includeArchived: true),
      FinanceRepository.getRecurringRules(enabledOnly: true),
    ]);
    final overviewTransactions = values[0] as List<FinanceTransaction>;
    final cumulativeBalanceEvents =
        values[1] as List<FinanceCumulativeBalanceEvent>;
    final fromKey = dateKey(from);
    final toKey = dateKey(to);
    final transactions = overviewTransactions
        .where(
          (transaction) =>
              transaction.transactionDate.compareTo(fromKey) >= 0 &&
              transaction.transactionDate.compareTo(toKey) < 0,
        )
        .toList(growable: false);
    final isCurrentMonth = from.year == now.year && from.month == now.month;
    return (
      transactions: transactions,
      summary: FinanceSummary.fromTransactions(
        transactions,
        asOfAt: isCurrentMonth ? now.millisecondsSinceEpoch : null,
      ),
      categories: values[2] as List<FinanceCategory>,
      paymentMethods: values[3] as List<FinancePaymentMethod>,
      overviewTransactions: overviewTransactions,
      cumulativeBalanceEvents: cumulativeBalanceEvents,
      recurringRules: values[4] as List<FinanceRecurringRule>,
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
    if (_month.year == currentDate.year && _month.month == currentDate.month) {
      final nextDayStartAt = DateTime(
        currentDate.year,
        currentDate.month,
        currentDate.day + 1,
      ).millisecondsSinceEpoch;
      if (nextDayStartAt < nextEventAt) nextEventAt = nextDayStartAt;
    }
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
        _cumulativeBalanceEvents = data.cumulativeBalanceEvents;
      });
    } catch (_) {
      // 后台补偿失败不覆盖已经可见的首屏数据。
    }
  }

  Future<void> _openEntry({
    FinanceTransaction? transaction,
    FinanceEntryTemplate? initialTemplate,
    DateTime? initialDate,
    GlobalKey? sourceKey,
  }) async {
    final page = FinanceEntryScreen(
      transaction: transaction,
      initialTemplate: initialTemplate,
      initialDate: initialDate,
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
    final categoryDisplayName = financeCategoryReferenceDisplayName(
      transaction.categoryUuid,
      _categories,
    );
    final result = await PageTransitions.pushFromRect<FinanceTransaction>(
      context: context,
      page: FinanceTransactionDetailScreen(
        transaction: transaction,
        category: category,
        categoryDisplayName: categoryDisplayName,
        paymentMethod: _paymentMethodMap[transaction.paymentMethodUuid],
        paymentMethods: _paymentMethods,
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
    final colorScheme = Theme.of(context).colorScheme;
    await PageTransitions.pushFromRect<void>(
      context: context,
      page: FinanceBudgetScreen(initialMonth: _month),
      sourceKey: _budgetActionKey,
      sourceColor: colorScheme.brightness == Brightness.dark
          ? Colors.black
          : Colors.white,
      sourceBorderRadius: BorderRadius.circular(24),
      placeholderBuilder: (_) => Icon(
        Icons.track_changes_outlined,
        color: colorScheme.primary,
        size: 30,
      ),
    );
    if (mounted) await _load();
  }

  Future<void> _openLoans() async {
    await Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const FinanceLoanScreen()));
    if (mounted) await _load();
  }

  Future<void> _openFutureCommitments() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => FinanceFutureCommitmentsScreen(clock: widget.clock),
      ),
    );
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
    required bool includedInBalanceSnapshot,
  }) {
    if (transaction.balanceEventAt() > widget.clock().millisecondsSinceEpoch) {
      final label = switch (transaction.type) {
        FinanceTransactionType.expense => '支出',
        FinanceTransactionType.income => '收入',
        FinanceTransactionType.refund => '退款',
      };
      final effect = hasPaymentMethod
          ? switch (transaction.type) {
              FinanceTransactionType.expense => '，不会影响当前付款方式余额',
              FinanceTransactionType.income => '，不会影响当前到账账户余额',
              FinanceTransactionType.refund => '，不会影响当前退款到账账户余额',
            }
          : transaction.type == FinanceTransactionType.refund
          ? '，不再抵扣净支出'
          : '';
      return '删除后，这笔计划$label会从未来账单中移除$effect。确认继续吗？';
    }

    if (hasPaymentMethod && includedInBalanceSnapshot) {
      return switch (transaction.type) {
        FinanceTransactionType.expense =>
          '删除后，这笔支出不再计入统计；当前余额以录入的余额快照为准，不会变化。确认继续吗？',
        FinanceTransactionType.income =>
          '删除后，这笔收入不再计入统计；当前余额以录入的余额快照为准，不会变化。确认继续吗？',
        FinanceTransactionType.refund =>
          '删除后，这笔退款不再抵扣净支出；当前余额以录入的余额快照为准，不会变化。确认继续吗？',
      };
    }

    return switch (transaction.type) {
      FinanceTransactionType.expense =>
        hasPaymentMethod
            ? '删除后，这笔支出不再计入统计，付款方式余额会相应增加。确认继续吗？'
            : '删除后不会计入统计，确认继续吗？',
      FinanceTransactionType.income =>
        hasPaymentMethod
            ? '删除后，这笔收入不再计入统计，到账账户余额会相应减少。确认继续吗？'
            : '删除后不会计入统计，确认继续吗？',
      FinanceTransactionType.refund =>
        hasPaymentMethod
            ? '删除后，这笔退款不再抵扣净支出，也不再增加退款到账账户的余额。确认继续吗？'
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
    final includedInBalanceSnapshot = hasPaymentMethod
        ? await _isIncludedInBalanceSnapshot(transaction)
        : false;
    if (!mounted) return;
    final deleteDescription = _deleteTransactionDescription(
      transaction,
      hasPaymentMethod: hasPaymentMethod,
      includedInBalanceSnapshot: includedInBalanceSnapshot,
    );
    final installmentDeleteDescription = switch (transaction.type) {
      FinanceTransactionType.expense =>
        hasPaymentMethod
            ? '删除后不会计入统计；已发生期次会从账户流水中移除，余额按余额快照和剩余流水重新计算，'
                  '未发生期次会从未来计划中移除。'
            : '删除后不会计入统计；未发生期次会从未来计划中移除。',
      FinanceTransactionType.income =>
        hasPaymentMethod
            ? '删除后不会计入统计；已发生期次会从账户流水中移除，余额按余额快照和剩余流水重新计算，'
                  '未发生期次会从未来计划中移除。'
            : '删除后不会计入统计；未发生期次会从未来计划中移除。',
      FinanceTransactionType.refund =>
        hasPaymentMethod
            ? '删除后不会计入统计，也不再抵扣净支出；已发生期次会从账户流水中移除，'
                  '余额按余额快照和剩余流水重新计算，'
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

  Future<bool> _isIncludedInBalanceSnapshot(
    FinanceTransaction transaction,
  ) async {
    final paymentMethodUuid = transaction.paymentMethodUuid?.trim();
    if (paymentMethodUuid == null || paymentMethodUuid.isEmpty) return false;
    final nowAt = widget.clock().millisecondsSinceEpoch;
    if (transaction.balanceEventAt() > nowAt) return false;
    final snapshots = FinanceRepository.latestPaymentBalanceSnapshots(
      await FinanceRepository.getBudgets(),
      asOfAt: nowAt,
      nowAt: nowAt,
    );
    for (final snapshot in snapshots) {
      if (snapshot.paymentMethodUuid != paymentMethodUuid) continue;
      final snapshotAt = snapshot.effectiveBalanceSnapshotAt;
      return transaction.balanceEventAt(snapshotAt: snapshotAt) <= snapshotAt;
    }
    return false;
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
    final selectedMonth = DateTime(value.year, value.month);
    final now = widget.clock();
    final isFutureMonth = selectedMonth.isAfter(DateTime(now.year, now.month));
    setState(() {
      _month = selectedMonth;
    });
    _load(refreshCumulativeBalanceEvents: isFutureMonth);
  }

  Future<void> _setLedgerDateRange(DateTimeRange? value) async {
    final current = _ledgerDateRange;
    if (current == null && value == null) return;
    if (current != null &&
        value != null &&
        dateKey(current.start) == dateKey(value.start) &&
        dateKey(current.end) == dateKey(value.end)) {
      return;
    }
    setState(() {
      _ledgerDateRange = value;
      _isLedgerQueryLoading = true;
      _ledgerQueryError = null;
      _transactions = const [];
    });
    await _load(showLoading: false);
  }

  Future<void> _editOpeningBalance() async {
    final now = widget.clock();
    final today = dateKey(now);
    final storedStartDate = _openingBalanceStartDate;
    final initialStartDate =
        storedStartDate != null && storedStartDate.compareTo(today) <= 0
        ? storedStartDate
        : FinanceRepository.defaultCumulativeBalanceStartDate(
            events: _cumulativeBalanceEvents,
            nowAt: now.millisecondsSinceEpoch,
          );
    final result = await showAppDialog<_FinanceOpeningBalanceDraft>(
      context: context,
      builder: (_) => _FinanceOpeningBalanceDialog(
        initialAmountMinor: _openingBalanceMinor,
        initialStartDate: initialStartDate,
        clock: widget.clock,
      ),
    );
    if (result == null || !mounted) return;

    try {
      if (result.amountMinor == null) {
        await AppSettingsStorage.clearFinanceOpeningBalance(widget.username);
        if (!mounted) return;
        setState(() {
          _openingBalanceMinor = 0;
          _openingBalanceStartDate = null;
        });
      } else {
        final startDate = result.startDate;
        if (startDate == null) return;
        await AppSettingsStorage.setFinanceOpeningBalance(
          widget.username,
          amountMinor: result.amountMinor!,
          startDate: startDate,
          now: now,
        );
        if (!mounted) return;
        setState(() {
          _openingBalanceMinor = result.amountMinor!;
          _openingBalanceStartDate = startDate;
        });
      }
    } catch (_) {
      if (!mounted) return;
      AppSnackBars.showSnackBar(
        context,
        const SnackBar(content: Text('期初结余保存失败，请稍后重试')),
      );
    }
  }

  Future<void> _pushCategoryLedger(
    String categoryUuid,
    GlobalKey sourceKey,
    List<FinanceTransaction> periodTransactions,
  ) => _openCategoryLedger(categoryUuid, sourceKey, periodTransactions);

  Future<void> _pushCategoryLedgerWithRange(
    String categoryUuid,
    GlobalKey sourceKey,
    List<FinanceTransaction> periodTransactions,
    DateTimeRange periodRange,
  ) => _openCategoryLedger(
    categoryUuid,
    sourceKey,
    periodTransactions,
    initialDateRange: periodRange,
  );

  Future<void> _openCategoryLedger(
    String categoryUuid,
    GlobalKey sourceKey,
    List<FinanceTransaction> periodTransactions, {
    DateTimeRange? initialDateRange,
  }) async {
    final category = _categoryMap[categoryUuid];
    final colorScheme = Theme.of(context).colorScheme;
    await PageTransitions.pushFromRect<void>(
      context: context,
      page: FinanceHomeScreen._categoryLedger(
        username: widget.username,
        month: _month,
        categoryUuid: categoryUuid,
        initialLedgerDateRange: initialDateRange,
        initialData: (
          transactions: periodTransactions,
          summary: _summary,
          categories: _categories,
          paymentMethods: _paymentMethods,
          overviewTransactions: _overviewTransactions,
          cumulativeBalanceEvents: _cumulativeBalanceEvents,
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

  Future<void> _openMonthLedger(
    DateTime selectedMonth,
    GlobalKey sourceKey,
  ) async {
    final now = widget.clock();
    final currentMonth = DateTime(now.year, now.month);
    final requestedMonth = DateTime(selectedMonth.year, selectedMonth.month);
    final month = requestedMonth.isAfter(currentMonth)
        ? currentMonth
        : requestedMonth;
    final start = DateTime(month.year, month.month);
    final end = month.year == now.year && month.month == now.month
        ? DateTime(now.year, now.month, now.day)
        : DateTime(month.year, month.month + 1, 0);
    final colorScheme = Theme.of(context).colorScheme;
    await PageTransitions.pushFromRect<void>(
      context: context,
      page: FinanceHomeScreen._monthLedger(
        username: widget.username,
        month: month,
        initialLedgerDateRange: DateTimeRange(start: start, end: end),
        initialData: (
          transactions: const <FinanceTransaction>[],
          summary: _summary,
          categories: _categories,
          paymentMethods: _paymentMethods,
          overviewTransactions: _overviewTransactions,
          cumulativeBalanceEvents: _cumulativeBalanceEvents,
          recurringRules: _recurringRules,
        ),
        clock: widget.clock,
      ),
      sourceKey: sourceKey,
      sourceColor: colorScheme.brightness == Brightness.dark
          ? Colors.black
          : Colors.white,
      placeholderBuilder: (_) =>
          const Icon(Icons.receipt_long_outlined, size: 30),
      sourceBorderRadius: BorderRadius.circular(12),
    );
    if (mounted) await _load(showLoading: false);
  }

  Future<void> _loadMonthLedgerRange() async {
    final selectedRange = _ledgerDateRange;
    if (selectedRange == null) return;
    final generation = ++_loadGeneration;
    try {
      final transactions = await FinanceRepository.getTransactions(
        from: selectedRange.start,
        to: financeCalendarDayOffset(selectedRange.end, 1),
      );
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _transactions = transactions;
        _isLedgerQueryLoading = false;
        _ledgerQueryError = null;
      });
    } catch (error) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _isLedgerQueryLoading = false;
        _ledgerQueryError = error.toString();
      });
    }
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
                          : _isLedgerDrilldownRoute
                          ? '清除附加筛选'
                          : '返回全部账单'
                    : _isCategoryLedgerRoute
                    ? '返回支出分类'
                    : widget._isMonthLedgerRoute
                    ? '返回结余趋势'
                    : '返回概览',
                onPressed: _handleBack,
                icon: const Icon(Icons.arrow_back_ios_new_rounded),
              )
            : null,
        actions: [
          IconButton(
            key: _budgetActionKey,
            style: floatingGlassPlainIconButtonStyle(),
            tooltip: '预算',
            onPressed: _openBudgets,
            icon: const Icon(Icons.track_changes_outlined),
          ),
          PopupMenuButton<String>(
            key: _moreActionKey,
            style: floatingGlassPlainIconButtonStyle(),
            tooltip: '更多操作',
            onSelected: (value) {
              if (value == 'guide') _showIntroGuide(force: true);
              if (value == 'settings') _openSettings();
              if (value == 'text') _openTextRecognition();
              if (value == 'automation') _openAutomation();
              if (value == 'loans') _openLoans();
              if (value == 'future_commitments') _openFutureCommitments();
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
                value: 'future_commitments',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.event_repeat_outlined),
                  title: Text('未来收支'),
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
              if (!_isLedgerDrilldownRoute)
                const PopupMenuItem(
                  value: 'guide',
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.help_outline_rounded),
                    title: Text('记账新手指引'),
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
                          cumulativeBalanceEvents: _cumulativeBalanceEvents,
                          openingBalanceMinor: _openingBalanceMinor,
                          openingBalanceStartDate: _openingBalanceStartDate,
                          onEditOpeningBalance: _editOpeningBalance,
                          categories: _categoryMap,
                          categoryTapOpensLedger: _categoryTapOpensLedger,
                          onAdd: () =>
                              _openEntry(sourceKey: _overviewAddActionKey),
                          onAddForDate: (date, sourceKey) => _openEntry(
                            initialDate: date,
                            sourceKey: sourceKey,
                          ),
                          addActionKey: _overviewAddActionKey,
                          onRefresh: _load,
                          onMonthChanged: _setMonth,
                          onCategorySelected: _pushCategoryLedger,
                          onCategorySelectedWithRange:
                              _pushCategoryLedgerWithRange,
                          onOpenMonthLedger: _openMonthLedger,
                          onOpenTransaction: _openDetail,
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
                          categoryUuids: _categoryFilterUuids,
                          dateRange: _ledgerDateRange,
                          isLoading: _isLedgerQueryLoading,
                          queryError: _ledgerQueryError,
                          onRetry: () => unawaited(_load(showLoading: false)),
                          onDateRangeChanged: _setLedgerDateRange,
                          onOpenDetail: _openDetail,
                          onKeywordChanged: (value) => _updateLedgerFilter(
                            update: () => _keyword = value,
                            keyword: value,
                            filterType: _filterType,
                            categoryUuids: _categoryFilterUuids,
                          ),
                          onFilterChanged: (value) => _updateLedgerFilter(
                            update: () => _filterType = value,
                            keyword: _keyword,
                            filterType: value,
                            categoryUuids: _categoryFilterUuids,
                          ),
                          onCategoryUuidsChanged: (value) =>
                              _updateLedgerFilter(
                                update: () => _categoryFilterUuids = value,
                                keyword: _keyword,
                                filterType: _filterType,
                                categoryUuids: value,
                              ),
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
            _scheduleIntroGuide();
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

class _FinanceOpeningBalanceDraft {
  final int? amountMinor;
  final String? startDate;

  const _FinanceOpeningBalanceDraft({
    required this.amountMinor,
    required this.startDate,
  });

  const _FinanceOpeningBalanceDraft.clear()
    : amountMinor = null,
      startDate = null;
}

class _FinanceOpeningBalanceDialog extends StatefulWidget {
  final int initialAmountMinor;
  final String initialStartDate;
  final DateTime Function() clock;

  const _FinanceOpeningBalanceDialog({
    required this.initialAmountMinor,
    required this.initialStartDate,
    required this.clock,
  });

  @override
  State<_FinanceOpeningBalanceDialog> createState() =>
      _FinanceOpeningBalanceDialogState();
}

class _FinanceOpeningBalanceDialogState
    extends State<_FinanceOpeningBalanceDialog> {
  late final TextEditingController _amountController;
  late DateTime _startDate;
  String? _amountError;
  String? _dateError;

  @override
  void initState() {
    super.initState();
    _amountController = TextEditingController(
      text: formatFinanceAmountInput(widget.initialAmountMinor),
    );
    _startDate = dateFromKey(widget.initialStartDate);
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _pickStartDate() async {
    final now = widget.clock();
    final today = DateTime(now.year, now.month, now.day);
    final initialDate = _startDate.isAfter(today) ? today : _startDate;
    final picked = await showAppDatePicker(
      context: context,
      initialDate: initialDate.isBefore(DateTime(2000))
          ? DateTime(2000)
          : initialDate,
      firstDate: DateTime(2000),
      lastDate: today,
      currentDate: today,
      helpText: '选择期初结余起算日期',
    );
    if (picked == null || !mounted) return;
    setState(() {
      _startDate = DateTime(picked.year, picked.month, picked.day);
      _dateError = null;
    });
  }

  void _save() {
    final amountMinor = parseFinanceAmount(
      _amountController.text,
      allowZero: true,
    );
    if (amountMinor == null) {
      setState(() => _amountError = '请输入不小于 0、最多两位小数的金额');
      return;
    }
    if (dateKey(_startDate).compareTo(dateKey(widget.clock())) > 0) {
      setState(() => _dateError = '起算日期不能晚于今天');
      return;
    }
    Navigator.of(context).pop(
      _FinanceOpeningBalanceDraft(
        amountMinor: amountMinor,
        startDate: dateKey(_startDate),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return AlertDialog(
      title: const Text('设置期初结余'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '填写起算日开始时已有的结余；起算日当天及之后的已记录收支会继续累加。',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _amountController,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
              ],
              decoration: InputDecoration(
                labelText: '期初结余',
                prefixText: '¥ ',
                errorText: _amountError,
                border: const OutlineInputBorder(),
              ),
              onChanged: (_) {
                if (_amountError != null) {
                  setState(() => _amountError = null);
                }
              },
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _pickStartDate,
              icon: const Icon(Icons.calendar_today_outlined),
              label: Text('起算日期：${dateKey(_startDate)}'),
            ),
            if (_dateError != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(_dateError!, style: TextStyle(color: colors.error)),
              ),
            const SizedBox(height: 8),
            Text(
              '只保存在当前设备；账单云同步不会同步这项设置。',
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: colors.onSurfaceVariant),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () =>
                    Navigator.of(context)
                        .pop(const _FinanceOpeningBalanceDraft.clear()),
                child: const Text('恢复为全部历史流水累计'),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(onPressed: _save, child: const Text('保存')),
      ],
    );
  }
}
