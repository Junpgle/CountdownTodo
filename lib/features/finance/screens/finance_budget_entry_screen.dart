import '../../../widgets/floating_glass_control.dart';
import 'package:flutter/material.dart';

import '../models/finance_models.dart';
import '../services/finance_repository.dart';
import '../widgets/finance_management_widgets.dart';

class FinanceBudgetEntryScreen extends StatefulWidget {
  final DateTime month;
  final FinanceBudget? budget;
  final String? initialPaymentMethodUuid;

  const FinanceBudgetEntryScreen({
    super.key,
    required this.month,
    this.budget,
    this.initialPaymentMethodUuid,
  });

  @override
  State<FinanceBudgetEntryScreen> createState() =>
      _FinanceBudgetEntryScreenState();
}

class _FinanceBudgetEntryScreenState extends State<FinanceBudgetEntryScreen> {
  static const String _overallValue = '__finance_overall_budget__';
  static const String _categoryPrefix = 'category:';
  static const String _paymentPrefix = 'payment:';

  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _amountController;
  late final TextEditingController _noteController;

  List<FinanceCategory> _categories = const [];
  List<FinancePaymentMethod> _paymentMethods = const [];
  String _scopeValue = _overallValue;
  bool _isLoading = true;
  String? _loadError;
  bool _isSaving = false;

  bool get _isEditing => widget.budget != null;

  bool get _isPaymentScope => _scopeValue.startsWith(_paymentPrefix);

  String get _screenTitle => _isPaymentScope
      ? (_isEditing ? '更新付款方式余额' : '记录付款方式余额')
      : (_isEditing ? '编辑预算' : '新增预算');

  @override
  void initState() {
    super.initState();
    final budget = widget.budget;
    _scopeValue = budget?.paymentMethodUuid != null
        ? '$_paymentPrefix${budget!.paymentMethodUuid}'
        : budget?.categoryUuid != null
            ? '$_categoryPrefix${budget!.categoryUuid}'
            : widget.initialPaymentMethodUuid != null
                ? '$_paymentPrefix${widget.initialPaymentMethodUuid}'
                : _overallValue;
    _amountController = TextEditingController(
      text: budget == null
          ? ''
          : (budget.amountMinor / 100)
              .toStringAsFixed(2)
              .replaceFirst(RegExp(r'\.00$'), ''),
    );
    _noteController = TextEditingController(text: budget?.note ?? '');
    _loadScopeOptions();
  }

  @override
  void dispose() {
    _amountController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _loadScopeOptions() async {
    setState(() {
      _isLoading = true;
      _loadError = null;
    });
    try {
      final values = await Future.wait<dynamic>([
        FinanceRepository.getCategories(
          type: FinanceCategoryType.expense,
          includeArchived: true,
        ),
        FinanceRepository.getPaymentMethods(includeArchived: true),
      ]);
      if (!mounted) return;
      setState(() {
        _categories = values[0] as List<FinanceCategory>;
        _paymentMethods = values[1] as List<FinancePaymentMethod>;
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

  List<FinanceCategory> get _visibleCategories {
    final result = _categories
        .where((item) => !item.isArchived && !item.isDeleted)
        .toList();
    final selectedUuid = _scopeValue.startsWith(_categoryPrefix)
        ? _scopeValue.substring(_categoryPrefix.length)
        : null;
    if (selectedUuid != null &&
        result.every((item) => item.uuid != selectedUuid)) {
      final selected = _categories.where(
        (item) => item.uuid == selectedUuid && !item.isDeleted,
      );
      result.insertAll(0, selected);
    }
    return result;
  }

  List<FinancePaymentMethod> get _visiblePaymentMethods {
    final result = _paymentMethods
        .where((item) => !item.isArchived && !item.isDeleted)
        .toList();
    final selectedUuid = _scopeValue.startsWith(_paymentPrefix)
        ? _scopeValue.substring(_paymentPrefix.length)
        : null;
    if (selectedUuid != null &&
        result.every((item) => item.uuid != selectedUuid)) {
      result.insertAll(
        0,
        _paymentMethods.where(
          (item) => item.uuid == selectedUuid && !item.isDeleted,
        ),
      );
    }
    return result;
  }

  List<DropdownMenuItem<String>> get _scopeItems {
    final items = <DropdownMenuItem<String>>[
      const DropdownMenuItem(
        value: _overallValue,
        child: Text('全部支出（总预算）'),
      ),
      for (final category in _visibleCategories)
        DropdownMenuItem(
          value: '$_categoryPrefix${category.uuid}',
          child: Text(
              '${category.icon}  分类 · ${financeCategoryDisplayName(category, _categories)}',
              overflow: TextOverflow.ellipsis),
        ),
      for (final method in _visiblePaymentMethods)
        DropdownMenuItem(
          value: '$_paymentPrefix${method.uuid}',
          child: Text('${method.icon}  付款方式 · ${method.name}',
              overflow: TextOverflow.ellipsis),
        ),
    ];
    if (_scopeValue != _overallValue &&
        items.every((item) => item.value != _scopeValue)) {
      items.add(
        DropdownMenuItem(
          value: _scopeValue,
          child: Text(_scopeValue.startsWith(_paymentPrefix)
              ? '💼 已归档或未知付款方式'
              : '🗃️ 已归档或未知分类'),
        ),
      );
    }
    return items;
  }

  Future<void> _save() async {
    if (_isSaving || _isLoading || !_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    final amount = parseFinanceAmount(_amountController.text);
    if (amount == null) {
      _showError('请输入大于 0 且不超过两位小数的金额');
      return;
    }

    setState(() => _isSaving = true);
    final old = widget.budget;
    final now = DateTime.now().millisecondsSinceEpoch;
    final budget = FinanceBudget(
      uuid: old?.uuid,
      monthKey: financeMonthKey(widget.month),
      categoryUuid: _scopeValue.startsWith(_categoryPrefix)
          ? _scopeValue.substring(_categoryPrefix.length)
          : null,
      paymentMethodUuid: _scopeValue.startsWith(_paymentPrefix)
          ? _scopeValue.substring(_paymentPrefix.length)
          : null,
      amountMinor: amount,
      currencyCode: old?.currencyCode ?? FinanceDefaults.defaultCurrencyCode,
      note: _emptyToNull(_noteController.text),
      version: old?.version ?? 1,
      createdAt: old?.createdAt ?? now,
      updatedAt: old?.updatedAt ?? now,
      deviceId: old?.deviceId,
    );
    if (old != null) budget.markAsChanged();

    try {
      await FinanceRepository.saveBudget(budget);
      if (!mounted) return;
      Navigator.of(context).pop(budget);
    } catch (error) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      _showError('${_isPaymentScope ? '保存付款方式余额失败' : '保存预算失败'}：$error');
    }
  }

  String? _emptyToNull(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final topBarHeight = floatingGlassTopBarHeight(context);
    return PopScope(
      canPop: !_isSaving,
      child: Scaffold(
        extendBodyBehindAppBar: true,
        appBar: FloatingGlassAppBar(
          flexibleSpace: const FloatingGlassTopBarBackground(),
          title: Text(_screenTitle),
        ),
        body: FloatingGlassTopBarContentFade(
          topBarHeight: topBarHeight,
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _loadError != null
                  ? FinancePageList(topPadding: topBarHeight, children: [
                      FinanceEmptyState(
                        icon: Icons.error_outline_rounded,
                        title: '分类或付款方式加载失败',
                        description: '请重新加载后再设置预算。',
                        actionLabel: '重试',
                        onAction: _loadScopeOptions,
                      ),
                    ])
                  : Column(children: [
                      Expanded(
                        child: AbsorbPointer(
                          absorbing: _isSaving,
                          child: Form(
                            key: _formKey,
                            child: FinancePageList(
                              topPadding: topBarHeight,
                              maxWidth: 720,
                              children: [
                                FinanceSectionCard(
                                  title:
                                      '${widget.month.year} 年 ${widget.month.month} 月',
                                  description: _isPaymentScope
                                      ? '保存时会将金额记为当天的余额快照；之后的支出会扣减，退款会加回。'
                                      : '预算按这个月份的账单统计。',
                                  icon: _isPaymentScope
                                      ? Icons.account_balance_wallet_outlined
                                      : Icons.calendar_month_outlined,
                                  child: FinanceAmountField(
                                    key:
                                        const ValueKey('finance-budget-amount'),
                                    controller: _amountController,
                                    label: _isPaymentScope ? '录入时剩余金额' : '预算金额',
                                  ),
                                ),
                                const SizedBox(height: 16),
                                FinanceSectionCard(
                                  title: _isPaymentScope ? '付款方式' : '预算范围',
                                  icon: Icons.track_changes_outlined,
                                  description: _isPaymentScope
                                      ? '支出按账单记录的付款方式扣减，退款会加回。'
                                      : '总预算覆盖全部支出；分类预算和付款方式余额独立统计。',
                                  child: DropdownButtonFormField<String>(
                                    key: ValueKey(
                                        'finance-budget-scope-$_scopeValue'),
                                    initialValue: _scopeValue,
                                    isExpanded: true,
                                    decoration: financeFieldDecoration(context,
                                        label: _isPaymentScope
                                            ? '选择付款方式'
                                            : '选择支出范围'),
                                    items: _scopeItems,
                                    onChanged: (value) {
                                      if (value != null) {
                                        setState(() => _scopeValue = value);
                                      }
                                    },
                                  ),
                                ),
                                const SizedBox(height: 16),
                                FinanceSectionCard(
                                  title: '留个备注',
                                  icon: Icons.notes_outlined,
                                  child: TextFormField(
                                    controller: _noteController,
                                    decoration: financeFieldDecoration(context,
                                        label: '备注（可选）', hint: '例如：本月减少外卖，多做饭'),
                                    maxLength: 120,
                                    minLines: 2,
                                    maxLines: 4,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      FinanceFormActions(
                          isSaving: _isSaving,
                          onSave: _save,
                          label: _isPaymentScope ? '保存余额' : '保存预算'),
                    ]),
        ),
      ),
    );
  }
}
