import '../../../widgets/floating_glass_control.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/finance_models.dart';
import '../services/finance_repository.dart';
import '../services/finance_storage.dart';
import '../services/finance_text_parser.dart';
import '../widgets/finance_catalog_editor.dart';

class _FinanceOptionSelection<T> {
  const _FinanceOptionSelection(this.value);

  final T? value;
}

class FinanceEntryScreen extends StatefulWidget {
  final FinanceTransaction? transaction;
  final FinanceTransaction? originalTransaction;
  final FinanceEntryTemplate? initialTemplate;
  final FinanceEntryDraft? initialDraft;

  const FinanceEntryScreen({
    super.key,
    this.transaction,
    this.originalTransaction,
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
  late final TextEditingController _quickEntryController;
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
  FinanceTransaction? _originalTransaction;
  int _remainingRefundableMinor = 0;
  bool _installmentEnabled = false;
  int _installmentCount = FinanceInstallmentCalculator.minCount;
  bool _isLoading = true;
  bool _isSaving = false;

  bool get _isEditing => widget.transaction != null;
  bool get _isEditingInstallment => widget.transaction?.isInstallment == true;
  bool get _hasRefundBinding =>
      widget.originalTransaction != null ||
      widget.transaction?.relatedTransactionUuid?.isNotEmpty == true;
  bool get _isBoundRefund =>
      _type == FinanceTransactionType.refund && _hasRefundBinding;

  @override
  void initState() {
    super.initState();
    final transaction = widget.transaction;
    final template = transaction == null ? widget.initialTemplate : null;
    final draft = transaction == null ? widget.initialDraft : null;
    _originalTransaction = widget.originalTransaction;
    _type = widget.originalTransaction != null
        ? FinanceTransactionType.refund
        : transaction?.type ??
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
      text: transaction?.merchant ??
          widget.originalTransaction?.merchant ??
          draft?.merchant ??
          template?.merchant ??
          '',
    );
    _noteController = TextEditingController(
      text: transaction?.note ?? draft?.note ?? template?.note ?? '',
    );
    _quickEntryController = TextEditingController();
    _installmentCountController = TextEditingController(
      text: _installmentCount.toString(),
    );
    _categoryUuid = transaction?.categoryUuid ??
        widget.originalTransaction?.categoryUuid ??
        draft?.categoryUuid ??
        template?.categoryUuid;
    _paymentMethodUuid = transaction?.paymentMethodUuid ??
        widget.originalTransaction?.paymentMethodUuid ??
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
    _quickEntryController.dispose();
    _installmentCountController.dispose();
    super.dispose();
  }

  Future<void> _loadOptions() async {
    try {
      final boundOriginalUuid = widget.originalTransaction?.uuid ??
          widget.transaction?.relatedTransactionUuid;
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
        widget.originalTransaction != null
            ? Future.value(widget.originalTransaction)
            : boundOriginalUuid == null
                ? Future.value(null)
                : FinanceRepository.getTransaction(boundOriginalUuid),
        boundOriginalUuid == null
            ? Future.value(0)
            : FinanceRepository.getRemainingRefundableMinor(
                boundOriginalUuid,
                excludingRefundUuid: widget.transaction?.uuid,
              ),
      ]);
      if (!mounted) return;
      final installmentGroup = options[3] as List<FinanceTransaction>;
      final originalTransaction = options[4] as FinanceTransaction?;
      final remainingRefundableMinor = options[5] as int;
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
        _originalTransaction = originalTransaction;
        _remainingRefundableMinor = remainingRefundableMinor;
        if (!_isEditing &&
            originalTransaction != null &&
            _amountController.text.trim().isEmpty &&
            remainingRefundableMinor > 0) {
          _amountController.text = formatFinanceAmount(
            remainingRefundableMinor,
            withSymbol: false,
          );
        }
        _isLoading = false;
      });
      _resolveDraftSelections();
      _normalizeSelections(
        allowDefaultCategory: !_shouldKeepUnresolvedDraftCategory(),
      );
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
    final categoryType = financeCategoryTypeForTransaction(_type);
    final hasValidCategoryUuid = _categories.any(
      (item) =>
          item.uuid == _categoryUuid &&
          item.type == categoryType &&
          !item.isDeleted,
    );
    if (!hasValidCategoryUuid && draft.categoryName != null) {
      final wanted = _normalizeOptionName(draft.categoryName!);
      final semanticWanted = FinanceTextParser.inferCategoryName(
        draft.categoryName!,
        _type,
      );
      final candidates = _categories
          .where((item) => item.type == categoryType && !item.isDeleted)
          .toList();
      final exact = candidates
          .where((item) =>
              _normalizeOptionName(item.name) == wanted ||
              _normalizeOptionName(
                    financeCategoryDisplayName(item, _categories),
                  ) ==
                  wanted)
          .firstOrNull;
      _categoryUuid = exact?.uuid ??
          candidates
              .where((item) {
                if (semanticWanted == null) return false;
                return FinanceTextParser.inferCategoryName(item.name, _type) ==
                    semanticWanted;
              })
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

  bool _shouldKeepUnresolvedDraftCategory() {
    final draft = widget.initialDraft;
    if (draft == null || widget.transaction != null) return false;
    final isRecognitionDraft = draft.source == FinanceEntrySource.ai ||
        draft.source == FinanceEntrySource.import;
    final requestedUuid = draft.categoryUuid?.trim();
    final requestedName = draft.categoryName?.trim();
    if ((requestedUuid == null || requestedUuid.isEmpty) &&
        (requestedName == null || requestedName.isEmpty)) {
      // Recognition/import drafts must never silently become the first local
      // category (usually 餐饮) just because the model omitted a category.
      return isRecognitionDraft;
    }
    final categoryType = financeCategoryTypeForTransaction(_type);
    final resolved = _categoryUuid != null &&
        _categories.any(
          (item) =>
              item.uuid == _categoryUuid &&
              item.type == categoryType &&
              !item.isDeleted,
        );
    return !resolved;
  }

  String _normalizeOptionName(String value) {
    return value
        .replaceAll(RegExp(r'^[^\u4e00-\u9fffA-Za-z0-9]+'), '')
        .replaceAll(RegExp(r'\s+'), '')
        .trim()
        .toLowerCase();
  }

  String _categoryName(FinanceCategory category) =>
      financeCategoryDisplayName(category, _categories);

  FinanceCategory? _categoryByUuid(String? uuid) {
    final normalized = uuid?.trim();
    if (normalized == null || normalized.isEmpty) return null;
    for (final category in _categories) {
      if (category.uuid == normalized) return category;
    }
    return null;
  }

  FinanceCategory _topLevelCategory(FinanceCategory category) {
    var current = category;
    final visited = <String>{category.uuid};
    while (true) {
      final parentUuid = current.parentUuid?.trim();
      if (parentUuid == null ||
          parentUuid.isEmpty ||
          !visited.add(parentUuid)) {
        return current;
      }
      final parent = _categoryByUuid(parentUuid);
      if (parent == null || parent.type != current.type) return current;
      current = parent;
    }
  }

  List<FinanceCategory> get _visibleCategories {
    final type = financeCategoryTypeForTransaction(_type);
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

  List<FinanceCategory> get _visibleCategoryParents {
    final type = financeCategoryTypeForTransaction(_type);
    final roots = _categories
        .where(
          (item) =>
              item.type == type &&
              !item.isArchived &&
              !item.isDeleted &&
              (item.parentUuid == null || item.parentUuid!.trim().isEmpty),
        )
        .toList();
    final selected = _categoryByUuid(_categoryUuid);
    final selectedRoot = selected == null ? null : _topLevelCategory(selected);
    if (selectedRoot != null &&
        !selectedRoot.isDeleted &&
        roots.every((item) => item.uuid != selectedRoot.uuid)) {
      roots.insert(0, selectedRoot);
    }
    return roots;
  }

  List<FinanceCategory> _childrenOf(FinanceCategory parent) {
    return _visibleCategories
        .where((item) => item.parentUuid?.trim() == parent.uuid)
        .toList();
  }

  int _nextSubcategorySortOrder(FinanceCategory parent) {
    var maxSortOrder = parent.sortOrder;
    for (final category in _categories) {
      if (category.parentUuid?.trim() == parent.uuid &&
          category.sortOrder > maxSortOrder) {
        maxSortOrder = category.sortOrder;
      }
    }
    return maxSortOrder + 1;
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

  void _normalizeSelections({
    bool notify = true,
    bool allowDefaultCategory = true,
  }) {
    final categories = _visibleCategories;
    if (_categoryUuid == null ||
        categories.every((item) => item.uuid != _categoryUuid)) {
      _categoryUuid = allowDefaultCategory && categories.isNotEmpty
          ? categories.first.uuid
          : null;
    }
    if (_paymentMethodUuid != null &&
        _visiblePaymentMethods
            .every((item) => item.uuid != _paymentMethodUuid)) {
      _paymentMethodUuid = null;
    }
    if (notify && mounted) setState(() {});
  }

  void _dismissKeyboard() {
    FocusManager.instance.primaryFocus?.unfocus(
      disposition: UnfocusDisposition.scope,
    );
  }

  Future<void> _pickDate() async {
    _dismissKeyboard();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 3650)),
      helpText: '选择账单日期',
    );
    _dismissKeyboard();
    if (picked != null && mounted) setState(() => _date = picked);
  }

  Future<void> _applyQuickEntry() async {
    if (_isSaving) return;
    final input = _quickEntryController.text.trim();
    if (input.isEmpty) {
      _showError('请先描述账单，例如：今天午餐 28 元，微信支付，分类餐饮');
      return;
    }
    final drafts = FinanceTextParser.parseQuickEntries(input);
    if (drafts.isEmpty) {
      _showError('没有识别到金额；多笔账单可以用换行或分号分开');
      return;
    }

    _dismissKeyboard();
    if (drafts.length > 1) {
      await _reviewQuickEntries(drafts);
      return;
    }
    _applyQuickDraft(drafts.single);
  }

  void _applyQuickDraft(FinanceEntryDraft draft) {
    _dismissKeyboard();
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
      _normalizeSelections(
        notify: false,
        allowDefaultCategory: !_shouldKeepUnresolvedDraftCategory(),
      );
    });
    _showMessage('已识别并填入表单，请核对后保存');
  }

  Future<void> _reviewQuickEntries(List<FinanceEntryDraft> drafts) async {
    final shouldReview = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      requestFocus: false,
      backgroundColor: Theme.of(context).colorScheme.surface,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.76,
      ),
      builder: (sheetContext) {
        final colorScheme = Theme.of(sheetContext).colorScheme;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 2, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Row(
                    children: [
                      Icon(Icons.receipt_long_rounded,
                          color: colorScheme.primary),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '识别到 ${drafts.length} 笔账单',
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              '请逐笔核对后保存，缺少分类或付款方式可在编辑页补充',
                              style: TextStyle(
                                color: colorScheme.onSurfaceVariant,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.42,
                  ),
                  child: ListView.separated(
                    shrinkWrap: true,
                    padding: EdgeInsets.zero,
                    itemCount: drafts.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 6),
                    itemBuilder: (context, index) {
                      final draft = drafts[index];
                      final isIncome =
                          draft.type == FinanceTransactionType.income;
                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        leading: CircleAvatar(
                          backgroundColor: isIncome
                              ? colorScheme.tertiaryContainer
                              : colorScheme.primaryContainer,
                          child: Icon(
                            isIncome
                                ? Icons.south_west_rounded
                                : Icons.north_east_rounded,
                            color: isIncome
                                ? colorScheme.onTertiaryContainer
                                : colorScheme.onPrimaryContainer,
                          ),
                        ),
                        title: Text(
                          '${draft.type.label} · '
                          '${formatFinanceAmount(draft.amountMinor)}',
                        ),
                        subtitle: Text(
                          _quickDraftSummary(draft),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(sheetContext).pop(false),
                        child: const Text('返回修改'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () => Navigator.of(sheetContext).pop(true),
                        icon: const Icon(Icons.edit_note_rounded),
                        label: const Text('逐笔确认'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
    _dismissKeyboard();
    if (shouldReview != true || !mounted) return;

    var savedCount = 0;
    for (final draft in drafts) {
      if (!mounted) return;
      final saved = await Navigator.of(context).push<FinanceTransaction>(
        MaterialPageRoute(
          builder: (_) => FinanceEntryScreen(initialDraft: draft),
        ),
      );
      if (saved != null) savedCount++;
    }
    _dismissKeyboard();
    if (!mounted) return;
    if (savedCount > 0) {
      _quickEntryController.clear();
      _showMessage('已保存 $savedCount/${drafts.length} 笔账单');
    }
  }

  String _quickDraftSummary(FinanceEntryDraft draft) {
    final parts = <String>[draft.transactionDate];
    final category = draft.categoryName?.trim();
    final merchant = draft.merchant?.trim();
    final payment = draft.paymentMethodName?.trim();
    parts.add(category == null || category.isEmpty ? '待选择分类' : category);
    if (merchant != null && merchant.isNotEmpty) parts.add(merchant);
    if (payment != null && payment.isNotEmpty) parts.add(payment);
    return parts.join(' · ');
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final amount = parseFinanceAmount(_amountController.text);
    if (amount == null) {
      _showError('请输入大于 0 且不超过两位小数的金额');
      return;
    }
    if (_isBoundRefund && _originalTransaction == null) {
      _showError('原账单不存在或已删除，无法保存这笔退款');
      return;
    }
    if (_isBoundRefund && amount > _remainingRefundableMinor) {
      _showError(
        '退款金额不能超过剩余可退金额 '
        '${formatFinanceAmount(_remainingRefundableMinor)}',
      );
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
      relatedTransactionUuid:
          _originalTransaction?.uuid ?? old?.relatedTransactionUuid,
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
    final selectedCategory = _visibleCategories
        .where((item) => item.uuid == _categoryUuid)
        .firstOrNull;
    final selectedPaymentMethod = _visiblePaymentMethods
        .where((item) => item.uuid == _paymentMethodUuid)
        .firstOrNull;

    final category = _buildFinancePickerField(
      key: ValueKey('finance-category-$_type-$_categoryUuid'),
      colorScheme: colorScheme,
      label: '分类',
      placeholder: '请选择分类',
      selectedName:
          selectedCategory == null ? null : _categoryName(selectedCategory),
      selectedIcon: selectedCategory?.icon,
      fieldIcon: Icons.category_outlined,
      onTap: _isSaving || _isBoundRefund ? null : _pickCategory,
    );

    final payment = _buildFinancePickerField(
      key: ValueKey('finance-payment-$_paymentMethodUuid'),
      colorScheme: colorScheme,
      label: '付款方式（可选）',
      placeholder: '未指定',
      selectedName: selectedPaymentMethod?.name,
      selectedIcon: selectedPaymentMethod?.icon,
      fieldIcon: Icons.account_balance_wallet_outlined,
      onTap: _isSaving ? null : _pickPaymentMethod,
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

  Widget _buildFinancePickerField({
    required Key key,
    required ColorScheme colorScheme,
    required String label,
    required String placeholder,
    required String? selectedName,
    required String? selectedIcon,
    required IconData fieldIcon,
    required VoidCallback? onTap,
  }) {
    final hasSelection = selectedName != null && selectedName.isNotEmpty;
    final displayName = hasSelection ? selectedName : placeholder;
    final valueColor = hasSelection
        ? colorScheme.onSurface
        : colorScheme.onSurfaceVariant.withValues(alpha: 0.82);

    return Material(
      key: key,
      color: colorScheme.surface.withValues(alpha: 0),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: colorScheme.outlineVariant.withValues(alpha: 0.82),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
          child: Row(
            children: [
              Icon(
                fieldIcon,
                size: 20,
                color: hasSelection
                    ? colorScheme.primary
                    : colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        color: colorScheme.onSurfaceVariant,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        if (hasSelection && selectedIcon != null) ...[
                          Text(selectedIcon,
                              style: const TextStyle(fontSize: 18)),
                          const SizedBox(width: 7),
                        ],
                        Flexible(
                          child: Text(
                            displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: valueColor,
                              fontSize: 15,
                              fontWeight: hasSelection
                                  ? FontWeight.w600
                                  : FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.keyboard_arrow_down_rounded,
                color: colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickCategory() async {
    _dismissKeyboard();
    final parents = _visibleCategoryParents;
    if (parents.isEmpty) return;
    final currentCategory = _categoryByUuid(_categoryUuid);
    final selectedParentUuid = currentCategory == null
        ? parents.first.uuid
        : _topLevelCategory(currentCategory).uuid;
    final parent = await _showFinanceOptionPicker<FinanceCategory>(
      title: '选择大类',
      subtitle: '先选择这笔账单所属的大类',
      headerIcon: Icons.category_outlined,
      options: parents,
      selectedUuid: selectedParentUuid,
      optionUuid: (item) => item.uuid,
      optionBuilder: (context, item, isSelected, onTap) =>
          _buildFinanceOptionTile(
        context,
        title: item.name,
        subtitle: '一级分类',
        iconText: item.icon,
        accent: _optionAccent(item.colorValue, Theme.of(context).colorScheme),
        isSelected: isSelected,
        onTap: onTap,
      ),
    );
    if (!mounted || parent?.value == null) return;

    final selectedParent = parent!.value!;
    final children = _childrenOf(selectedParent);
    if (children.isEmpty) {
      _dismissKeyboard();
      setState(() => _categoryUuid = selectedParent.uuid);
      return;
    }

    final current = _categoryByUuid(_categoryUuid);
    final currentBelongsToParent = current != null &&
        (current.uuid == selectedParent.uuid ||
            current.parentUuid?.trim() == selectedParent.uuid);
    final selected = await _showFinanceOptionPicker<FinanceCategory>(
      title: '${selectedParent.name} · 选择小类',
      subtitle: '可以只记为大类，也可以选择更具体的细分',
      headerIcon: Icons.account_tree_outlined,
      options: [selectedParent, ...children],
      selectedUuid: currentBelongsToParent ? current.uuid : selectedParent.uuid,
      optionUuid: (item) => item.uuid,
      addTooltip: '新增小类',
      onAdd: () => _addSubcategory(selectedParent),
      optionBuilder: (context, item, isSelected, onTap) {
        final isParent = item.uuid == selectedParent.uuid;
        return _buildFinanceOptionTile(
          context,
          title: isParent ? '仅记为${selectedParent.name}' : item.name,
          subtitle: isParent ? '不选择小类' : '${selectedParent.name}下的细分类',
          iconText: item.icon,
          accent: _optionAccent(item.colorValue, Theme.of(context).colorScheme),
          isSelected: isSelected,
          onTap: onTap,
        );
      },
    );
    if (!mounted || selected?.value == null) return;
    _dismissKeyboard();
    setState(() => _categoryUuid = selected!.value!.uuid);
  }

  Future<FinanceCategory?> _addSubcategory(FinanceCategory parent) async {
    _dismissKeyboard();
    FinanceCategory? created;
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => FinanceCatalogEditor(
        initialIcon: parent.icon,
        categoryType: parent.type,
        availableParents: _categories,
        initialParentUuid: parent.uuid,
        lockParent: true,
        isSubcategory: true,
        onSave: (draft) async {
          final category = FinanceCategory(
            name: draft.name,
            type: draft.type!,
            icon: draft.icon,
            parentUuid: draft.parentUuid,
            sortOrder: _nextSubcategorySortOrder(parent),
          );
          await FinanceRepository.saveCategory(category);
          created = category;
        },
      ),
    );
    _dismissKeyboard();
    if (saved != true || !mounted || created == null) return null;
    setState(() => _categories = [..._categories, created!]);
    return created;
  }

  Future<void> _pickPaymentMethod() async {
    _dismissKeyboard();
    final selected = await _showFinanceOptionPicker<FinancePaymentMethod>(
      title: '选择付款方式',
      subtitle: '记录这笔账单使用的支付渠道',
      headerIcon: Icons.account_balance_wallet_outlined,
      options: _visiblePaymentMethods,
      selectedUuid: _paymentMethodUuid,
      optionUuid: (item) => item.uuid,
      includeUnset: true,
      optionBuilder: (context, item, isSelected, onTap) =>
          _buildFinanceOptionTile(
        context,
        title: item.name,
        iconText: item.icon,
        accent: _optionAccent(item.colorValue, Theme.of(context).colorScheme),
        isSelected: isSelected,
        onTap: onTap,
      ),
    );
    if (!mounted || selected == null) return;
    _dismissKeyboard();
    setState(() => _paymentMethodUuid = selected.value?.uuid);
  }

  Future<_FinanceOptionSelection<T>?> _showFinanceOptionPicker<T>({
    required String title,
    required String subtitle,
    required IconData headerIcon,
    required List<T> options,
    required String? selectedUuid,
    required String Function(T option) optionUuid,
    required Widget Function(
      BuildContext context,
      T option,
      bool isSelected,
      VoidCallback onTap,
    ) optionBuilder,
    bool includeUnset = false,
    String? addTooltip,
    Future<T?> Function()? onAdd,
  }) async {
    _dismissKeyboard();
    final selected = await showModalBottomSheet<_FinanceOptionSelection<T>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      requestFocus: false,
      backgroundColor: Theme.of(context).colorScheme.surface,
      clipBehavior: Clip.antiAlias,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.76,
      ),
      builder: (sheetContext) {
        final colorScheme = Theme.of(sheetContext).colorScheme;
        final totalCount = options.length + (includeUnset ? 1 : 0);
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 2, 20, 14),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      headerIcon,
                      color: colorScheme.onPrimaryContainer,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          subtitle,
                          style: TextStyle(
                            color: colorScheme.onSurfaceVariant,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (onAdd != null)
                    IconButton(
                      key: ValueKey(addTooltip ?? 'finance-option-add'),
                      tooltip: addTooltip ?? '新增',
                      onPressed: () async {
                        final added = await onAdd();
                        if (!sheetContext.mounted || added == null) return;
                        Navigator.of(sheetContext).pop(
                          _FinanceOptionSelection<T>(added),
                        );
                      },
                      icon: const Icon(Icons.add_rounded),
                    ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '$totalCount 项',
                      style: TextStyle(
                        color: colorScheme.onSurfaceVariant,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                itemCount: totalCount,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  if (includeUnset && index == 0) {
                    return _buildFinanceOptionTile(
                      context,
                      title: '未指定',
                      subtitle: '暂不记录付款方式',
                      icon: Icons.remove_rounded,
                      accent: colorScheme.outline,
                      isSelected: selectedUuid == null,
                      onTap: () => Navigator.of(sheetContext).pop(
                        _FinanceOptionSelection<T>(null),
                      ),
                    );
                  }
                  final option = options[index - (includeUnset ? 1 : 0)];
                  return optionBuilder(
                    context,
                    option,
                    optionUuid(option) == selectedUuid,
                    () => Navigator.of(sheetContext).pop(
                      _FinanceOptionSelection<T>(option),
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
    _dismissKeyboard();
    return selected;
  }

  Widget _buildFinanceOptionTile(
    BuildContext context, {
    required String title,
    String? subtitle,
    String? iconText,
    IconData? icon,
    required Color accent,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final iconBackground =
        isSelected ? colorScheme.primary : accent.withValues(alpha: 0.16);
    final iconColor = isSelected ? colorScheme.onPrimary : accent;

    return Material(
      color: isSelected
          ? colorScheme.primaryContainer.withValues(alpha: 0.58)
          : colorScheme.surfaceContainerLow.withValues(alpha: 0.72),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
          color: isSelected
              ? colorScheme.primary.withValues(alpha: 0.55)
              : colorScheme.outlineVariant.withValues(alpha: 0.48),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: iconBackground,
                  borderRadius: BorderRadius.circular(13),
                ),
                child: iconText == null
                    ? Icon(icon, color: iconColor, size: 20)
                    : Text(iconText, style: const TextStyle(fontSize: 20)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: colorScheme.onSurface,
                        fontSize: 15,
                        fontWeight:
                            isSelected ? FontWeight.w700 : FontWeight.w600,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: colorScheme.onSurfaceVariant,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 160),
                child: isSelected
                    ? Icon(
                        Icons.check_circle_rounded,
                        key: const ValueKey('selected'),
                        color: colorScheme.primary,
                      )
                    : Icon(
                        Icons.chevron_right_rounded,
                        key: const ValueKey('unselected'),
                        color: colorScheme.onSurfaceVariant,
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color _optionAccent(int? colorValue, ColorScheme colorScheme) {
    return colorValue == null ? colorScheme.primary : Color(colorValue);
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
          Material(
            type: MaterialType.transparency,
            child: SwitchListTile.adaptive(
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
    final topBarHeight = floatingGlassTopBarHeight(context);
    return Scaffold(
      resizeToAvoidBottomInset: false,
      extendBodyBehindAppBar: true,
      appBar: FloatingGlassAppBar(
        flexibleSpace: const FloatingGlassTopBarBackground(),
        title: Text(
          _isBoundRefund
              ? (_isEditing ? '编辑退款' : '原单退款')
              : _isEditingInstallment
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
      body: FloatingGlassTopBarContentFade(
        topBarHeight: topBarHeight,
        child: _isLoading
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
                        topBarHeight + 8,
                        16,
                        96 + MediaQuery.viewPaddingOf(context).bottom,
                      ),
                      children: [
                        _buildTypeSelector(colorScheme),
                        if (_isBoundRefund) ...[
                          const SizedBox(height: 12),
                          _buildRefundContextCard(colorScheme),
                        ],
                        if (!_isEditing &&
                            !_isBoundRefund &&
                            widget.initialDraft == null) ...[
                          const SizedBox(height: 16),
                          _buildOneSentenceEntry(colorScheme),
                        ],
                        const SizedBox(height: 20),
                        TextFormField(
                          controller: _amountController,
                          autofocus: false,
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(
                                RegExp(r'[0-9.,]')),
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
                    _dismissKeyboard();
                    if (type == _type ||
                        _isEditingInstallment ||
                        _hasRefundBinding) {
                      return;
                    }
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

  Widget _buildRefundContextCard(ColorScheme colorScheme) {
    final original = _originalTransaction;
    if (original == null) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: colorScheme.errorContainer,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(
          '原账单不存在或已删除，这笔退款暂时无法编辑。',
          style: TextStyle(color: colorScheme.onErrorContainer),
        ),
      );
    }
    final refundedMinor = (original.amountMinor - _remainingRefundableMinor)
        .clamp(0, original.amountMinor)
        .toInt();
    final title = original.merchant?.trim().isNotEmpty == true
        ? original.merchant!.trim()
        : original.categoryUuid;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colorScheme.secondaryContainer.withValues(alpha: 0.62),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '关联原账单',
            style: TextStyle(
              color: colorScheme.onSecondaryContainer,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '$title  ·  ${formatFinanceAmount(original.amountMinor)}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: colorScheme.onSecondaryContainer),
          ),
          const SizedBox(height: 4),
          Text(
            '已退 ${formatFinanceAmount(refundedMinor)}  ·  '
            '剩余可退 ${formatFinanceAmount(_remainingRefundableMinor)}',
            style: TextStyle(
              color: colorScheme.onSecondaryContainer.withValues(alpha: 0.78),
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
                    '自然语言记账',
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
              FinanceTextParser.quickEntryHelp,
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
                    text: FinanceTextParser.quickEntryExample,
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
                  key: const ValueKey('finance-quick-entry-input'),
                  controller: _quickEntryController,
                  autofocus: false,
                  minLines: 2,
                  maxLines: 5,
                  maxLength: 500,
                  keyboardType: TextInputType.multiline,
                  textInputAction: TextInputAction.newline,
                  onSubmitted: (_) => _applyQuickEntry(),
                  decoration: _fieldDecoration(
                    colorScheme,
                    labelText: '账单描述',
                    hintText: '如：今天早餐 8 元，微信；中午午餐 25 元，支付宝',
                    prefixIcon: Icons.edit_note_rounded,
                    counterText: '',
                  ),
                );
                final action = TextButton.icon(
                  style: _compactTextButtonStyle(colorScheme),
                  onPressed: _isSaving ? null : _applyQuickEntry,
                  icon: const Icon(Icons.arrow_forward_rounded, size: 18),
                  label: const Text('识别账单'),
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
    _dismissKeyboard();
    final selected = await showModalBottomSheet<FinanceEntryTemplate>(
      context: context,
      showDragHandle: true,
      requestFocus: false,
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
    _dismissKeyboard();
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
    _dismissKeyboard();
  }
}
