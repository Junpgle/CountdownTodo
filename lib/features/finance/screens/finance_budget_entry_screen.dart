import '../../../widgets/floating_glass_control.dart';
import 'package:flutter/material.dart';

import '../models/finance_models.dart';
import '../services/finance_repository.dart';
import '../widgets/finance_management_widgets.dart';

class FinanceBudgetEntryScreen extends StatefulWidget {
  final DateTime month;
  final FinanceBudget? budget;

  const FinanceBudgetEntryScreen({
    super.key,
    required this.month,
    this.budget,
  });

  @override
  State<FinanceBudgetEntryScreen> createState() =>
      _FinanceBudgetEntryScreenState();
}

class _FinanceBudgetEntryScreenState extends State<FinanceBudgetEntryScreen> {
  static const String _overallValue = '__finance_overall_budget__';

  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _amountController;
  late final TextEditingController _noteController;

  List<FinanceCategory> _categories = const [];
  String _scopeValue = _overallValue;
  bool _isLoading = true;
  String? _loadError;
  bool _isSaving = false;

  bool get _isEditing => widget.budget != null;

  @override
  void initState() {
    super.initState();
    final budget = widget.budget;
    _scopeValue = budget?.categoryUuid ?? _overallValue;
    _amountController = TextEditingController(
      text: budget == null
          ? ''
          : (budget.amountMinor / 100)
              .toStringAsFixed(2)
              .replaceFirst(RegExp(r'\.00$'), ''),
    );
    _noteController = TextEditingController(text: budget?.note ?? '');
    _loadCategories();
  }

  @override
  void dispose() {
    _amountController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _loadCategories() async {
    setState(() {
      _isLoading = true;
      _loadError = null;
    });
    try {
      final categories = await FinanceRepository.getCategories(
        type: FinanceCategoryType.expense,
        includeArchived: true,
      );
      if (!mounted) return;
      setState(() {
        _categories = categories;
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
    if (_scopeValue != _overallValue &&
        result.every((item) => item.uuid != _scopeValue)) {
      final selected = _categories.where(
        (item) => item.uuid == _scopeValue && !item.isDeleted,
      );
      result.insertAll(0, selected);
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
          value: category.uuid,
          child: Text('${category.icon}  ${category.name}',
              overflow: TextOverflow.ellipsis),
        ),
    ];
    if (_scopeValue != _overallValue &&
        items.every((item) => item.value != _scopeValue)) {
      items.add(
        DropdownMenuItem(
          value: _scopeValue,
          child: const Text('🗃️ 已归档或未知分类'),
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
      _showError('请输入大于 0 且不超过两位小数的预算');
      return;
    }

    setState(() => _isSaving = true);
    final old = widget.budget;
    final now = DateTime.now().millisecondsSinceEpoch;
    final budget = FinanceBudget(
      uuid: old?.uuid,
      monthKey: financeMonthKey(widget.month),
      categoryUuid: _scopeValue == _overallValue ? null : _scopeValue,
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
      _showError('保存预算失败：$error');
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
    return PopScope(
      canPop: !_isSaving,
      child: Scaffold(
        appBar: FloatingGlassAppBar(
          flexibleSpace: const FloatingGlassTopBarBackground(),
          title: Text(_isEditing ? '编辑预算' : '新增预算'),
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _loadError != null
                ? FinancePageList(children: [
                    FinanceEmptyState(
                      icon: Icons.error_outline_rounded,
                      title: '预算分类加载失败',
                      description: '请重新加载后再设置预算。',
                      actionLabel: '重试',
                      onAction: _loadCategories,
                    ),
                  ])
                : Column(children: [
                    Expanded(
                      child: AbsorbPointer(
                        absorbing: _isSaving,
                        child: Form(
                          key: _formKey,
                          child: FinancePageList(
                            maxWidth: 720,
                            children: [
                              FinanceSectionCard(
                                title:
                                    '${widget.month.year} 年 ${widget.month.month} 月',
                                description: '预算按这个月份的账单统计。',
                                icon: Icons.calendar_month_outlined,
                                child: FinanceAmountField(
                                  key: const ValueKey('finance-budget-amount'),
                                  controller: _amountController,
                                  label: '预算金额',
                                ),
                              ),
                              const SizedBox(height: 16),
                              FinanceSectionCard(
                                title: '预算范围',
                                icon: Icons.track_changes_outlined,
                                description: '总预算覆盖全部支出；分类预算独立统计。',
                                child: DropdownButtonFormField<String>(
                                  key: ValueKey(
                                      'finance-budget-scope-$_scopeValue'),
                                  initialValue: _scopeValue,
                                  isExpanded: true,
                                  decoration: financeFieldDecoration(context,
                                      label: '选择支出范围'),
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
                        isSaving: _isSaving, onSave: _save, label: '保存预算'),
                  ]),
      ),
    );
  }
}
