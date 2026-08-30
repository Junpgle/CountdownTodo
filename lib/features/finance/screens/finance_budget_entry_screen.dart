import '../../../widgets/floating_glass_control.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/finance_models.dart';
import '../services/finance_repository.dart';

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
      setState(() => _isLoading = false);
      _showError('加载支出分类失败：$error');
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
          child: Text('${category.icon}  ${category.name}'),
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
    if (!_formKey.currentState!.validate()) return;
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
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: FloatingGlassAppBar(
        flexibleSpace: const FloatingGlassTopBarBackground(),
        title: Text(_isEditing ? '编辑预算' : '新增预算'),
        actions: [
          TextButton(
            onPressed: _isSaving || _isLoading ? null : _save,
            child: const Text('保存'),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                children: [
                  Card(
                    color: colorScheme.secondaryContainer,
                    child: ListTile(
                      leading: Icon(
                        Icons.calendar_month_outlined,
                        color: colorScheme.onSecondaryContainer,
                      ),
                      title: Text(
                        '${widget.month.year} 年 ${widget.month.month} 月',
                        style: TextStyle(
                          color: colorScheme.onSecondaryContainer,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      subtitle: Text(
                        '预算只对这个月份的本地账单生效',
                        style: TextStyle(
                          color: colorScheme.onSecondaryContainer
                              .withValues(alpha: 0.75),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    key: ValueKey('finance-budget-scope-$_scopeValue'),
                    initialValue: _scopeValue,
                    decoration: const InputDecoration(
                      labelText: '预算范围',
                      prefixIcon: Icon(Icons.track_changes_outlined),
                    ),
                    items: _scopeItems,
                    onChanged: (value) {
                      if (value != null) {
                        setState(() => _scopeValue = value);
                      }
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _amountController,
                    autofocus: !_isEditing,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                    ],
                    decoration: InputDecoration(
                      labelText: '预算金额',
                      prefixText: '¥ ',
                      hintText: '0.00',
                      prefixStyle: TextStyle(
                        color: colorScheme.primary,
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                      ),
                      labelStyle: TextStyle(color: colorScheme.primary),
                    ),
                    style: const TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.w700,
                    ),
                    validator: (value) =>
                        parseFinanceAmount(value ?? '') == null
                            ? '请输入预算金额'
                            : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _noteController,
                    decoration: const InputDecoration(
                      labelText: '备注（可选）',
                      prefixIcon: Icon(Icons.notes_outlined),
                    ),
                    maxLength: 120,
                    maxLines: 2,
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: _isSaving ? null : _save,
                    icon: _isSaving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.check),
                    label: Text(_isSaving ? '保存中...' : '保存预算'),
                  ),
                ],
              ),
            ),
    );
  }
}
