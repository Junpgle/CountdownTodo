import '../../../widgets/floating_glass_control.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/finance_models.dart';
import '../services/finance_repository.dart';
import '../services/finance_storage.dart';
import '../services/finance_text_parser.dart';

class FinanceEntryScreen extends StatefulWidget {
  final FinanceTransaction? transaction;
  final FinanceEntryTemplate? initialTemplate;
  final FinanceEntryDraft? initialDraft;

  const FinanceEntryScreen({
    super.key,
    this.transaction,
    this.initialTemplate,
    this.initialDraft,
  });

  @override
  State<FinanceEntryScreen> createState() => _FinanceEntryScreenState();
}

class _FinanceEntryScreenState extends State<FinanceEntryScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _amountController;
  late final TextEditingController _merchantController;
  late final TextEditingController _noteController;
  late final TextEditingController _oneSentenceController;

  FinanceTransactionType _type = FinanceTransactionType.expense;
  DateTime _date = DateTime.now();
  List<FinanceCategory> _categories = const [];
  List<FinancePaymentMethod> _paymentMethods = const [];
  List<FinanceEntryTemplate> _templates = const [];
  String? _categoryUuid;
  String? _paymentMethodUuid;
  String? _selectedTemplateUuid;
  bool _isLoading = true;
  bool _isSaving = false;

  bool get _isEditing => widget.transaction != null;

  @override
  void initState() {
    super.initState();
    final transaction = widget.transaction;
    final template = transaction == null ? widget.initialTemplate : null;
    final draft = transaction == null ? widget.initialDraft : null;
    _type = transaction?.type ??
        draft?.type ??
        template?.type ??
        FinanceTransactionType.expense;
    _date = transaction == null
        ? draft == null
            ? DateTime.now()
            : dateFromKey(draft.transactionDate)
        : dateFromKey(transaction.transactionDate);
    _amountController = TextEditingController(
      text: transaction == null
          ? draft != null
              ? formatFinanceAmount(draft.amountMinor, withSymbol: false)
              : template == null
                  ? ''
                  : formatFinanceAmount(template.amountMinor, withSymbol: false)
          : (transaction.amountMinor / 100)
              .toStringAsFixed(2)
              .replaceFirst(RegExp(r'\.00$'), ''),
    );
    _merchantController = TextEditingController(
      text:
          transaction?.merchant ?? draft?.merchant ?? template?.merchant ?? '',
    );
    _noteController = TextEditingController(
      text: transaction?.note ?? draft?.note ?? template?.note ?? '',
    );
    _oneSentenceController = TextEditingController();
    _categoryUuid = transaction?.categoryUuid ??
        draft?.categoryUuid ??
        template?.categoryUuid;
    _paymentMethodUuid = transaction?.paymentMethodUuid ??
        draft?.paymentMethodUuid ??
        template?.paymentMethodUuid;
    _selectedTemplateUuid = template?.uuid;
    _loadOptions();
  }

  @override
  void dispose() {
    _amountController.dispose();
    _merchantController.dispose();
    _noteController.dispose();
    _oneSentenceController.dispose();
    super.dispose();
  }

  Future<void> _loadOptions() async {
    try {
      final options = await Future.wait<dynamic>([
        FinanceStorage.getCategories(includeArchived: true),
        FinanceStorage.getPaymentMethods(includeArchived: true),
        FinanceStorage.getTemplates(),
      ]);
      if (!mounted) return;
      setState(() {
        _categories = options[0] as List<FinanceCategory>;
        _paymentMethods = options[1] as List<FinancePaymentMethod>;
        _templates = options[2] as List<FinanceEntryTemplate>;
        _isLoading = false;
      });
      _resolveDraftSelections();
      _normalizeSelections();
    } catch (error) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      _showError('加载分类失败：$error');
    }
  }

  void _resolveDraftSelections() {
    final draft = widget.initialDraft;
    if (draft == null || widget.transaction != null) return;
    _resolveSelectionsFromDraft(draft);
  }

  void _resolveSelectionsFromDraft(FinanceEntryDraft draft) {
    if (_categoryUuid == null && draft.categoryName != null) {
      final wanted = _normalizeOptionName(draft.categoryName!);
      _categoryUuid = _categories
          .where((item) =>
              item.type ==
                  (_type == FinanceTransactionType.expense
                      ? FinanceCategoryType.expense
                      : FinanceCategoryType.income) &&
              !item.isDeleted)
          .where((item) => _normalizeOptionName(item.name) == wanted)
          .map((item) => item.uuid)
          .firstOrNull;
    }
    if (_paymentMethodUuid == null && draft.paymentMethodName != null) {
      final wanted = _normalizeOptionName(draft.paymentMethodName!);
      _paymentMethodUuid = _paymentMethods
          .where((item) => !item.isDeleted)
          .where((item) => _normalizeOptionName(item.name) == wanted)
          .map((item) => item.uuid)
          .firstOrNull;
    }
  }

  String _normalizeOptionName(String value) {
    return value
        .replaceAll(RegExp(r'^[^\u4e00-\u9fffA-Za-z0-9]+'), '')
        .trim()
        .toLowerCase();
  }

  List<FinanceCategory> get _visibleCategories {
    final type = _type == FinanceTransactionType.expense
        ? FinanceCategoryType.expense
        : FinanceCategoryType.income;
    final result = _categories
        .where(
          (item) => item.type == type && !item.isArchived && !item.isDeleted,
        )
        .toList();
    if (_categoryUuid != null &&
        result.every((item) => item.uuid != _categoryUuid)) {
      final selected = _categories.where(
        (item) =>
            item.uuid == _categoryUuid && item.type == type && !item.isDeleted,
      );
      result.insertAll(0, selected);
    }
    return result;
  }

  List<FinancePaymentMethod> get _visiblePaymentMethods {
    final result = _paymentMethods
        .where((item) => !item.isArchived && !item.isDeleted)
        .toList();
    if (_paymentMethodUuid != null &&
        result.every((item) => item.uuid != _paymentMethodUuid)) {
      final selected = _paymentMethods.where(
        (item) => item.uuid == _paymentMethodUuid && !item.isDeleted,
      );
      result.insertAll(0, selected);
    }
    return result;
  }

  void _normalizeSelections({bool notify = true}) {
    final categories = _visibleCategories;
    if (_categoryUuid == null ||
        categories.every((item) => item.uuid != _categoryUuid)) {
      _categoryUuid = categories.isEmpty ? null : categories.first.uuid;
    }
    if (_paymentMethodUuid != null &&
        _visiblePaymentMethods
            .every((item) => item.uuid != _paymentMethodUuid)) {
      _paymentMethodUuid = null;
    }
    if (notify && mounted) setState(() {});
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 3650)),
      helpText: '选择账单日期',
    );
    if (picked != null && mounted) setState(() => _date = picked);
  }

  void _applyOneSentence() {
    if (_isSaving) return;
    final input = _oneSentenceController.text.trim();
    if (input.isEmpty) {
      _showError('请先输入一句话，例如：今天午餐花了 28.5 元，微信支付，分类餐饮');
      return;
    }
    final draft = FinanceTextParser.parseOneSentence(input);
    if (draft == null) {
      _showError('没有识别到金额，请说清楚金额，例如：今天午餐花了 28.5 元');
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() {
      _type = draft.type;
      _date = dateFromKey(draft.transactionDate);
      _amountController.text =
          formatFinanceAmount(draft.amountMinor, withSymbol: false);
      _merchantController.text = draft.merchant ?? '';
      _noteController.text = draft.note ?? '';
      _categoryUuid = draft.categoryUuid;
      _paymentMethodUuid = draft.paymentMethodUuid;
      _selectedTemplateUuid = null;
      _resolveSelectionsFromDraft(draft);
      _normalizeSelections(notify: false);
    });
    _showMessage('已填入表单，请核对后保存');
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final amount = parseFinanceAmount(_amountController.text);
    if (amount == null) {
      _showError('请输入大于 0 且不超过两位小数的金额');
      return;
    }

    setState(() => _isSaving = true);
    final old = widget.transaction;
    final now = DateTime.now().millisecondsSinceEpoch;
    final transaction = FinanceTransaction(
      uuid: old?.uuid,
      type: _type,
      amountMinor: amount,
      currencyCode: old?.currencyCode ?? FinanceDefaults.defaultCurrencyCode,
      categoryUuid: _categoryUuid,
      paymentMethodUuid: _paymentMethodUuid,
      transactionDate: dateKey(_date),
      occurredAt: old?.occurredAt ?? now,
      timezoneOffsetMinutes:
          old?.timezoneOffsetMinutes ?? DateTime.now().timeZoneOffset.inMinutes,
      merchant: _emptyToNull(_merchantController.text),
      note: _emptyToNull(_noteController.text),
      source: old?.source ??
          widget.initialDraft?.source ??
          FinanceEntrySource.manual,
      relatedTodoUuid: old?.relatedTodoUuid,
      relatedPlanBlockUuid: old?.relatedPlanBlockUuid,
      relatedTransactionUuid: old?.relatedTransactionUuid,
      isDeleted: false,
      version: old?.version ?? 1,
      createdAt: old?.createdAt ?? now,
      updatedAt: old?.updatedAt ?? now,
      deviceId: old?.deviceId,
    );
    if (old != null) transaction.markAsChanged();

    try {
      await FinanceRepository.saveTransaction(transaction);
      if (_selectedTemplateUuid != null) {
        try {
          await FinanceRepository.markTemplateUsed(_selectedTemplateUuid!);
        } catch (_) {
          // 模板使用次数是辅助信息，不应影响账单保存结果。
        }
      }
      if (!mounted) return;
      Navigator.of(context).pop(transaction);
    } catch (error) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      _showError('保存失败：$error');
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

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: FloatingGlassAppBar(
        flexibleSpace: const FloatingGlassTopBarBackground(),
        title: Text(_isEditing ? '编辑账单' : '记一笔'),
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
                  _buildTypeSelector(colorScheme),
                  if (!_isEditing) ...[
                    const SizedBox(height: 12),
                    _buildOneSentenceEntry(colorScheme),
                  ],
                  if (!_isEditing && _templates.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: _showTemplatePicker,
                        icon: const Icon(Icons.flash_on_outlined),
                        label: Text(
                          _selectedTemplateUuid == null ? '使用快捷模板' : '更换快捷模板',
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  TextFormField(
                    controller: _amountController,
                    autofocus: !_isEditing,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                    ],
                    decoration: InputDecoration(
                      labelText: '金额',
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
                            ? '请输入金额'
                            : null,
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    key: ValueKey('finance-category-$_type-$_categoryUuid'),
                    initialValue: _categoryUuid,
                    decoration: const InputDecoration(
                      labelText: '分类',
                      prefixIcon: Icon(Icons.category_outlined),
                    ),
                    items: [
                      for (final category in _visibleCategories)
                        DropdownMenuItem<String>(
                          value: category.uuid,
                          child: Text('${category.icon}  ${category.name}'),
                        ),
                    ],
                    onChanged: (value) => setState(() => _categoryUuid = value),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    key: ValueKey('finance-payment-$_paymentMethodUuid'),
                    initialValue: _paymentMethodUuid,
                    decoration: const InputDecoration(
                      labelText: '付款方式（可选）',
                      prefixIcon: Icon(Icons.account_balance_wallet_outlined),
                    ),
                    items: [
                      const DropdownMenuItem<String>(
                        value: null,
                        child: Text('未指定'),
                      ),
                      for (final method in _visiblePaymentMethods)
                        DropdownMenuItem<String>(
                          value: method.uuid,
                          child: Text('${method.icon}  ${method.name}'),
                        ),
                    ],
                    onChanged: (value) =>
                        setState(() => _paymentMethodUuid = value),
                  ),
                  const SizedBox(height: 12),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.calendar_today_outlined),
                    title: const Text('账单日期'),
                    trailing: Text(
                      dateKey(_date),
                      style: TextStyle(
                        color: colorScheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    onTap: _pickDate,
                  ),
                  const Divider(),
                  TextFormField(
                    controller: _merchantController,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: '商家（可选）',
                      prefixIcon: Icon(Icons.storefront_outlined),
                    ),
                    maxLength: 80,
                  ),
                  TextFormField(
                    controller: _noteController,
                    decoration: const InputDecoration(
                      labelText: '备注（可选）',
                      prefixIcon: Icon(Icons.notes_outlined),
                    ),
                    maxLines: 2,
                    maxLength: 300,
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
                    label: Text(_isSaving ? '保存中...' : '保存账单'),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildTypeSelector(ColorScheme colorScheme) {
    return SegmentedButton<FinanceTransactionType>(
      segments: [
        for (final type in [
          FinanceTransactionType.expense,
          FinanceTransactionType.income,
          FinanceTransactionType.refund,
        ])
          ButtonSegment<FinanceTransactionType>(
            value: type,
            label: Text(type.label),
            icon: Icon(
              type == FinanceTransactionType.expense
                  ? Icons.arrow_upward_rounded
                  : type == FinanceTransactionType.refund
                      ? Icons.undo_rounded
                      : Icons.arrow_downward_rounded,
            ),
          ),
      ],
      selected: {_type},
      onSelectionChanged: (selection) {
        if (selection.isEmpty) return;
        setState(() {
          _type = selection.first;
          _normalizeSelections(notify: false);
        });
      },
      style: ButtonStyle(
        visualDensity: VisualDensity.compact,
        foregroundColor: WidgetStatePropertyAll(colorScheme.onSurface),
      ),
    );
  }

  Widget _buildOneSentenceEntry(ColorScheme colorScheme) {
    return Card(
      margin: EdgeInsets.zero,
      color: colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.auto_awesome_rounded, color: colorScheme.primary),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    '一句话记账',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                Text(
                  '自动填入',
                  style: TextStyle(
                    color: colorScheme.onSurfaceVariant,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              FinanceTextParser.oneSentenceHelp,
              style: TextStyle(
                color: colorScheme.onSurfaceVariant,
                fontSize: 12,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _oneSentenceController,
              textInputAction: TextInputAction.done,
              maxLength: 200,
              onSubmitted: (_) => _applyOneSentence(),
              decoration: InputDecoration(
                labelText: '输入一句话',
                hintText: FinanceTextParser.oneSentenceExample,
                prefixIcon: const Icon(Icons.edit_note_rounded),
                counterText: '',
                filled: true,
                fillColor: colorScheme.surface,
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: _isSaving ? null : _applyOneSentence,
                icon: const Icon(Icons.arrow_downward_rounded),
                label: const Text('解析并填入'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showTemplatePicker() async {
    final selected = await showModalBottomSheet<FinanceEntryTemplate>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          children: [
            const ListTile(
              title: Text('选择快捷模板'),
              subtitle: Text('模板只填充默认内容，保存前仍可修改'),
            ),
            for (final template in _templates)
              ListTile(
                leading: Icon(
                  template.type == FinanceTransactionType.income
                      ? Icons.arrow_downward_rounded
                      : Icons.arrow_upward_rounded,
                ),
                title: Text(template.name),
                subtitle: Text(
                  '${template.type.label} · ${formatFinanceAmount(template.amountMinor)}',
                ),
                trailing: template.uuid == _selectedTemplateUuid
                    ? const Icon(Icons.check)
                    : null,
                onTap: () => Navigator.pop(context, template),
              ),
          ],
        ),
      ),
    );
    if (selected == null || !mounted) return;
    setState(() {
      _selectedTemplateUuid = selected.uuid;
      _type = selected.type;
      _amountController.text =
          formatFinanceAmount(selected.amountMinor, withSymbol: false);
      _merchantController.text = selected.merchant ?? '';
      _noteController.text = selected.note ?? '';
      _categoryUuid = selected.categoryUuid;
      _paymentMethodUuid = selected.paymentMethodUuid;
      _normalizeSelections(notify: false);
    });
  }
}
