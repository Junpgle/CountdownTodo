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
  late final TextEditingController _installmentCountController;

  FinanceTransactionType _type = FinanceTransactionType.expense;
  DateTime _date = DateTime.now();
  List<FinanceCategory> _categories = const [];
  List<FinancePaymentMethod> _paymentMethods = const [];
  List<FinanceEntryTemplate> _templates = const [];
  String? _categoryUuid;
  String? _paymentMethodUuid;
  String? _selectedTemplateUuid;
  List<FinanceTransaction> _existingInstallments = const [];
  bool _installmentEnabled = false;
  int _installmentCount = FinanceInstallmentCalculator.minCount;
  bool _isLoading = true;
  bool _isSaving = false;

  bool get _isEditing => widget.transaction != null;
  bool get _isEditingInstallment => widget.transaction?.isInstallment == true;

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
    if (_isEditingInstallment) {
      _installmentEnabled = true;
      _installmentCount = transaction!.installmentCount ??
          FinanceInstallmentCalculator.minCount;
    }
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
    _installmentCountController = TextEditingController(
      text: _installmentCount.toString(),
    );
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
    _installmentCountController.dispose();
    super.dispose();
  }

  Future<void> _loadOptions() async {
    try {
      final options = await Future.wait<dynamic>([
        FinanceStorage.getCategories(includeArchived: true),
        FinanceStorage.getPaymentMethods(includeArchived: true),
        FinanceStorage.getTemplates(),
        _isEditingInstallment
            ? FinanceStorage.getInstallmentGroup(
                widget.transaction!.installmentGroupUuid!,
                includeDeleted: true,
              )
            : Future.value(const <FinanceTransaction>[]),
      ]);
      if (!mounted) return;
      final installmentGroup = options[3] as List<FinanceTransaction>;
      if (installmentGroup.isNotEmpty) {
        final first = installmentGroup.firstWhere(
          (item) => item.installmentIndex == 1,
          orElse: () => installmentGroup.first,
        );
        final total = first.installmentTotalMinor ??
            installmentGroup.fold<int>(
              0,
              (sum, item) => sum + item.amountMinor,
            );
        _existingInstallments = installmentGroup;
        _type = first.type;
        _date = dateFromKey(first.transactionDate);
        _amountController.text = formatFinanceAmount(total, withSymbol: false);
        _merchantController.text = first.merchant ?? '';
        _noteController.text = first.note ?? '';
        _categoryUuid = first.categoryUuid;
        _paymentMethodUuid = first.paymentMethodUuid;
        _installmentEnabled = true;
        _installmentCount = first.installmentCount ?? installmentGroup.length;
        _installmentCountController.text = _installmentCount.toString();
      }
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

    final installmentCount = _installmentEnabled
        ? int.tryParse(_installmentCountController.text.trim())
        : 1;
    if (installmentCount == null ||
        (_installmentEnabled &&
            (installmentCount < FinanceInstallmentCalculator.minCount ||
                installmentCount > FinanceInstallmentCalculator.maxCount))) {
      _showError(
        '分期月数必须在 ${FinanceInstallmentCalculator.minCount}-'
        '${FinanceInstallmentCalculator.maxCount} 之间',
      );
      return;
    }
    if (_installmentEnabled && installmentCount > amount) {
      _showError('分期月数不能超过金额的分（人民币分）');
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
      final List<FinanceTransaction> saved;
      if (installmentCount > 1) {
        saved = await FinanceRepository.saveInstallmentPlan(
          transaction: transaction,
          totalAmountMinor: amount,
          installmentCount: installmentCount,
          startDate: _date,
          existingInstallments: _existingInstallments.isNotEmpty
              ? _existingInstallments
              : old == null
                  ? const []
                  : [old],
        );
      } else {
        await FinanceRepository.saveTransaction(transaction);
        saved = [transaction];
      }
      if (_selectedTemplateUuid != null) {
        try {
          await FinanceRepository.markTemplateUsed(_selectedTemplateUuid!);
        } catch (_) {
          // 模板使用次数是辅助信息，不应影响账单保存结果。
        }
      }
      if (!mounted) return;
      Navigator.of(context).pop(saved.first);
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

  ButtonStyle _plainTextButtonStyle(ColorScheme colorScheme) {
    return ButtonStyle(
      backgroundColor: WidgetStatePropertyAll(
        colorScheme.surface.withValues(alpha: 0),
      ),
      backgroundBuilder: (context, states, child) =>
          child ?? const SizedBox.shrink(),
      foregroundColor: WidgetStatePropertyAll(colorScheme.primary),
      overlayColor: WidgetStatePropertyAll(
        colorScheme.primary.withValues(alpha: 0.08),
      ),
      minimumSize: const WidgetStatePropertyAll(Size.zero),
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      shape: WidgetStatePropertyAll(
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  ButtonStyle _compactTextButtonStyle(ColorScheme colorScheme) {
    return _plainTextButtonStyle(colorScheme).copyWith(
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      ),
      textStyle: const WidgetStatePropertyAll(
        TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      ),
    );
  }

  InputDecoration _fieldDecoration(
    ColorScheme colorScheme, {
    String? labelText,
    String? hintText,
    String? prefixText,
    IconData? prefixIcon,
    String? counterText,
    String? suffixText,
    bool alignLabelWithHint = false,
    FloatingLabelBehavior? floatingLabelBehavior,
    EdgeInsetsGeometry? contentPadding,
    TextStyle? prefixStyle,
  }) {
    final outline = OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide(
        color: colorScheme.outlineVariant.withValues(alpha: 0.82),
      ),
    );
    return InputDecoration(
      labelText: labelText,
      hintText: hintText,
      prefixText: prefixText,
      prefixIcon: prefixIcon == null
          ? null
          : Icon(prefixIcon, size: 21, color: colorScheme.onSurfaceVariant),
      counterText: counterText,
      suffixText: suffixText,
      alignLabelWithHint: alignLabelWithHint,
      floatingLabelBehavior: floatingLabelBehavior,
      isDense: true,
      filled: false,
      contentPadding: contentPadding ??
          const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
      prefixStyle: prefixStyle,
      labelStyle: TextStyle(color: colorScheme.onSurfaceVariant),
      floatingLabelStyle: TextStyle(
        color: colorScheme.primary,
        fontWeight: FontWeight.w600,
      ),
      hintStyle: TextStyle(
        color: colorScheme.onSurfaceVariant.withValues(alpha: 0.72),
      ),
      border: outline,
      enabledBorder: outline,
      focusedBorder: outline.copyWith(
        borderSide: BorderSide(color: colorScheme.primary, width: 1.5),
      ),
      errorBorder: outline.copyWith(
        borderSide: BorderSide(color: colorScheme.error),
      ),
      focusedErrorBorder: outline.copyWith(
        borderSide: BorderSide(color: colorScheme.error, width: 1.5),
      ),
    );
  }

  Widget _buildSelectionFields(
    ColorScheme colorScheme, {
    required bool isWide,
  }) {
    final category = DropdownButtonFormField<String>(
      key: ValueKey('finance-category-$_type-$_categoryUuid'),
      initialValue: _categoryUuid,
      isExpanded: true,
      decoration: _fieldDecoration(colorScheme, labelText: '分类'),
      items: [
        for (final item in _visibleCategories)
          DropdownMenuItem<String>(
            value: item.uuid,
            child: Text(
              '${item.icon}  ${item.name}',
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
      onChanged:
          _isSaving ? null : (value) => setState(() => _categoryUuid = value),
    );
    final payment = DropdownButtonFormField<String>(
      key: ValueKey('finance-payment-$_paymentMethodUuid'),
      initialValue: _paymentMethodUuid,
      isExpanded: true,
      decoration: _fieldDecoration(
        colorScheme,
        labelText: '付款方式（可选）',
      ),
      items: [
        const DropdownMenuItem<String>(
          value: null,
          child: Text('未指定'),
        ),
        for (final method in _visiblePaymentMethods)
          DropdownMenuItem<String>(
            value: method.uuid,
            child: Text(
              '${method.icon}  ${method.name}',
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
      onChanged: _isSaving
          ? null
          : (value) => setState(() => _paymentMethodUuid = value),
    );
    if (!isWide) {
      return Column(
        children: [
          category,
          const SizedBox(height: 14),
          payment,
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: category),
        const SizedBox(width: 12),
        Expanded(child: payment),
      ],
    );
  }

  Widget _buildDateField(ColorScheme colorScheme) {
    return Material(
      color: colorScheme.surface.withValues(alpha: 0),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: colorScheme.outlineVariant.withValues(alpha: 0.82),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: _isSaving ? null : _pickDate,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
          child: Row(
            children: [
              Icon(
                Icons.calendar_today_outlined,
                size: 21,
                color: colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  '账单日期',
                  style: TextStyle(
                    color: colorScheme.onSurface,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              Text(
                dateKey(_date),
                style: TextStyle(
                  color: colorScheme.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInstallmentField(ColorScheme colorScheme) {
    if (_type != FinanceTransactionType.expense) {
      return const SizedBox.shrink();
    }
    final hasPlan = _installmentEnabled;
    final subtitle = _isEditingInstallment
        ? '修改表单内容时，会同步更新全部分期'
        : hasPlan
            ? '从 ${dateKey(_date)} 开始，每月记入一期账单'
            : '将整笔金额一次性计入当前月份';
    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow.withValues(alpha: 0.52),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.82),
        ),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          SwitchListTile.adaptive(
            contentPadding: const EdgeInsets.symmetric(horizontal: 14),
            secondary: Icon(
              Icons.calendar_month_outlined,
              color: colorScheme.primary,
            ),
            title: Text(
              _isEditingInstallment ? '分期账单' : '分期付款',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle: Text(subtitle),
            value: hasPlan,
            onChanged: _isSaving || _isEditingInstallment
                ? null
                : (value) {
                    setState(() {
                      _installmentEnabled = value;
                      if (value) {
                        _installmentCount =
                            FinanceInstallmentCalculator.minCount;
                        _installmentCountController.text =
                            _installmentCount.toString();
                      }
                    });
                  },
          ),
          if (hasPlan) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
              child: TextFormField(
                controller: _installmentCountController,
                enabled: !_isSaving,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: _fieldDecoration(
                  colorScheme,
                  labelText: '分期月数',
                  prefixIcon: Icons.repeat_rounded,
                  hintText: '${FinanceInstallmentCalculator.minCount}',
                  suffixText: '个月',
                ),
                onChanged: (value) {
                  final parsed = int.tryParse(value);
                  if (parsed != null) {
                    setState(() => _installmentCount = parsed);
                  }
                },
                validator: (value) {
                  final count = int.tryParse(value?.trim() ?? '');
                  if (count == null ||
                      count < FinanceInstallmentCalculator.minCount ||
                      count > FinanceInstallmentCalculator.maxCount) {
                    return '请输入 ${FinanceInstallmentCalculator.minCount}-'
                        '${FinanceInstallmentCalculator.maxCount} 个月';
                  }
                  final amount = parseFinanceAmount(_amountController.text);
                  if (amount != null && count > amount) {
                    return '期数不能超过金额的分（人民币分）';
                  }
                  return null;
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '金额按分精确分摊，无法整除时前几期会多 1 分。',
                  style: TextStyle(
                    color: colorScheme.onSurfaceVariant,
                    fontSize: 12,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildOptionalFields(
    ColorScheme colorScheme, {
    required bool isWide,
  }) {
    final merchant = TextFormField(
      controller: _merchantController,
      textInputAction: TextInputAction.next,
      maxLength: 80,
      decoration: _fieldDecoration(
        colorScheme,
        labelText: '商家（可选）',
        counterText: '',
      ),
    );
    final note = TextFormField(
      controller: _noteController,
      maxLines: 2,
      maxLength: 300,
      decoration: _fieldDecoration(
        colorScheme,
        labelText: '备注（可选）',
        counterText: '',
        alignLabelWithHint: true,
      ),
    );
    if (!isWide) {
      return Column(
        children: [
          merchant,
          const SizedBox(height: 14),
          note,
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: merchant),
        const SizedBox(width: 12),
        Expanded(child: note),
      ],
    );
  }

  ButtonStyle _primaryButtonStyle(ColorScheme colorScheme) {
    return ButtonStyle(
      backgroundColor: WidgetStatePropertyAll(colorScheme.primary),
      backgroundBuilder: (context, states, child) =>
          child ?? const SizedBox.shrink(),
      foregroundColor: WidgetStatePropertyAll(colorScheme.onPrimary),
      overlayColor: WidgetStatePropertyAll(
        colorScheme.onPrimary.withValues(alpha: 0.12),
      ),
      minimumSize: const WidgetStatePropertyAll(Size.fromHeight(48)),
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      ),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      shape: WidgetStatePropertyAll(
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      resizeToAvoidBottomInset: false,
      appBar: FloatingGlassAppBar(
        flexibleSpace: const FloatingGlassTopBarBackground(),
        title: Text(
          _isEditingInstallment
              ? '编辑分期账单'
              : _isEditing
                  ? '编辑账单'
                  : '记一笔',
        ),
        actions: [
          TextButton(
            style: _plainTextButtonStyle(colorScheme),
            onPressed: _isSaving || _isLoading ? null : _save,
            child: const Text('保存'),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final isWide = constraints.maxWidth >= 620;
                  return ListView(
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    padding: EdgeInsets.fromLTRB(
                      16,
                      8,
                      16,
                      96 + MediaQuery.viewPaddingOf(context).bottom,
                    ),
                    children: [
                      _buildTypeSelector(colorScheme),
                      if (!_isEditing) ...[
                        const SizedBox(height: 16),
                        _buildOneSentenceEntry(colorScheme),
                      ],
                      const SizedBox(height: 20),
                      TextFormField(
                        controller: _amountController,
                        autofocus: !_isEditing,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                        ],
                        decoration: _fieldDecoration(
                          colorScheme,
                          labelText: _installmentEnabled ? '分期总额' : '金额',
                          prefixText: '¥ ',
                          hintText: '0.00',
                          floatingLabelBehavior: FloatingLabelBehavior.always,
                          contentPadding: const EdgeInsets.fromLTRB(
                            16,
                            20,
                            16,
                            12,
                          ),
                          prefixStyle: TextStyle(
                            color: colorScheme.primary,
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        style: TextStyle(
                          color: colorScheme.onSurface,
                          fontSize: 28,
                          fontWeight: FontWeight.w700,
                        ),
                        validator: (value) =>
                            parseFinanceAmount(value ?? '') == null
                                ? '请输入金额'
                                : null,
                      ),
                      const SizedBox(height: 14),
                      _buildSelectionFields(colorScheme, isWide: isWide),
                      const SizedBox(height: 14),
                      _buildDateField(colorScheme),
                      if (_type == FinanceTransactionType.expense) ...[
                        const SizedBox(height: 14),
                        _buildInstallmentField(colorScheme),
                      ],
                      const SizedBox(height: 14),
                      _buildOptionalFields(colorScheme, isWide: isWide),
                      const SizedBox(height: 20),
                      FilledButton.icon(
                        style: _primaryButtonStyle(colorScheme),
                        onPressed: _isSaving ? null : _save,
                        icon: _isSaving
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.check_rounded),
                        label: Text(_isSaving ? '保存中...' : '保存账单'),
                      ),
                    ],
                  );
                },
              ),
            ),
    );
  }

  Widget _buildTypeSelector(ColorScheme colorScheme) {
    final types = [
      FinanceTransactionType.expense,
      FinanceTransactionType.income,
      FinanceTransactionType.refund,
    ];
    return Container(
      height: 44,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: colorScheme.surface.withValues(alpha: 0.72),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.8),
        ),
        borderRadius: BorderRadius.circular(13),
      ),
      child: Row(
        children: [
          for (final type in types)
            Expanded(
              child: Semantics(
                button: true,
                selected: type == _type,
                label: type.label,
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () {
                    if (type == _type || _isEditingInstallment) return;
                    setState(() {
                      _type = type;
                      if (type != FinanceTransactionType.expense) {
                        _installmentEnabled = false;
                      }
                      _normalizeSelections(notify: false);
                    });
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    curve: Curves.easeOut,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: type == _type
                          ? colorScheme.primaryContainer
                          : colorScheme.surface.withValues(alpha: 0),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      type.label,
                      style: TextStyle(
                        color: type == _type
                            ? colorScheme.onPrimaryContainer
                            : colorScheme.onSurfaceVariant,
                        fontWeight:
                            type == _type ? FontWeight.w700 : FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildOneSentenceEntry(ColorScheme colorScheme) {
    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow.withValues(alpha: 0.52),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.72),
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 13, 14, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.auto_awesome_rounded,
                  size: 19,
                  color: colorScheme.primary,
                ),
                const SizedBox(width: 7),
                const Expanded(
                  child: Text(
                    '快速记账',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (_templates.isNotEmpty)
                  TextButton.icon(
                    style: _compactTextButtonStyle(colorScheme),
                    onPressed: _showTemplatePicker,
                    icon: const Icon(Icons.flash_on_outlined, size: 17),
                    label: Text(
                      _selectedTemplateUuid == null ? '快捷模板' : '更换模板',
                    ),
                  ),
              ],
            ),
            Text(
              '输入一句话，自动填入金额、分类、商家和付款方式',
              style: TextStyle(
                color: colorScheme.onSurfaceVariant,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 8),
            Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: '示例：',
                    style: TextStyle(
                      color: colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  TextSpan(
                    text: FinanceTextParser.oneSentenceExample,
                    style: TextStyle(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            LayoutBuilder(
              builder: (context, constraints) {
                final input = TextField(
                  controller: _oneSentenceController,
                  textInputAction: TextInputAction.done,
                  maxLength: 200,
                  onSubmitted: (_) => _applyOneSentence(),
                  decoration: _fieldDecoration(
                    colorScheme,
                    hintText: '输入账单描述',
                    prefixIcon: Icons.edit_note_rounded,
                    counterText: '',
                  ),
                );
                final action = TextButton.icon(
                  style: _compactTextButtonStyle(colorScheme),
                  onPressed: _isSaving ? null : _applyOneSentence,
                  icon: const Icon(Icons.arrow_forward_rounded, size: 18),
                  label: const Text('解析并填入'),
                );
                if (constraints.maxWidth >= 520) {
                  return Row(
                    children: [
                      Expanded(child: input),
                      const SizedBox(width: 10),
                      action,
                    ],
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    input,
                    Align(alignment: Alignment.centerRight, child: action),
                  ],
                );
              },
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
