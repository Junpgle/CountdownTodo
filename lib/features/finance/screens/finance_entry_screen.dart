import 'dart:async';

import '../../../widgets/app_skeleton.dart';
import '../../../widgets/floating_glass_control.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/finance_models.dart';
import '../services/finance_repository.dart';
import '../services/finance_storage.dart';
import '../services/finance_text_parser.dart';
import '../widgets/finance_amount_calculator.dart';
import '../widgets/finance_catalog_editor.dart';
import '../widgets/finance_revision_refresh_mixin.dart';
import 'finance_loan_screen.dart';
import '../../../utils/app_dialogs.dart';
import '../../../utils/time_utils.dart';
import '../../../utils/text_utils.dart';
import '../../../utils/calendar_date_math.dart';

part 'parts/finance_entry_options.dart';
part 'parts/finance_entry_actions.dart';
part 'parts/finance_entry_pickers.dart';
part 'parts/finance_entry_fields.dart';

final RegExp _optionNameLeadingDecorationPattern = RegExp(
  r'^[^\u4e00-\u9fffA-Za-z0-9]+',
);
final RegExp _optionNameWhitespacePattern = RegExp(r'\s+');
final RegExp _expressionOperatorPattern = RegExp(r'[+\-*/()]');
final RegExp _expressionLineBreakPattern = RegExp(r'\r?\n');
final List<TextInputFormatter> _installmentCountInputFormatters =
    List<TextInputFormatter>.unmodifiable([
      FilteringTextInputFormatter.digitsOnly,
    ]);

class _FinanceOptionSelection<T> {
  const _FinanceOptionSelection(this.value);

  final T? value;
}

class FinanceEntryScreen extends StatefulWidget {
  final FinanceTransaction? transaction;
  final FinanceTransaction? originalTransaction;
  final FinanceEntryTemplate? initialTemplate;
  final FinanceEntryDraft? initialDraft;
  final DateTime? initialDate;

  const FinanceEntryScreen({
    super.key,
    this.transaction,
    this.originalTransaction,
    this.initialTemplate,
    this.initialDraft,
    this.initialDate,
  });

  @override
  State<FinanceEntryScreen> createState() => _FinanceEntryScreenState();
}

class _FinanceEntryScreenState extends State<FinanceEntryScreen>
    with FinanceRevisionRefreshMixin<FinanceEntryScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _amountController;
  late final TextEditingController _merchantController;
  late final TextEditingController _noteController;
  late final TextEditingController _quickEntryController;
  late final TextEditingController _installmentCountController;

  FinanceTransactionType _type = FinanceTransactionType.expense;
  DateTime _date = DateTime.now();
  DateTime? _occurredAt;
  bool _occurrenceTimeExplicit = false;
  late int _timezoneOffsetMinutes;
  List<FinanceCategory> _categories = const [];
  List<FinancePaymentMethod> _paymentMethods = const [];
  final _categoriesByUuid = <String, FinanceCategory>{};
  final _paymentMethodsByUuid = <String, FinancePaymentMethod>{};
  final _categoryDisplayNameCache = <String, String>{};
  final _paymentMethodDisplayNameCache = <String, String>{};
  List<FinanceEntryTemplate> _templates = const [];
  String? _categoryUuid;
  String? _paymentMethodUuid;
  String? _targetPaymentMethodUuid;
  String? _unmatchedDraftPaymentMethodName;
  bool _paymentMethodSelectionEdited = false;
  bool _archivedCategoryRequiresSelection = false;
  String? _selectedTemplateUuid;
  String? _amountExpression;
  List<FinanceTransaction> _existingInstallments = const [];
  FinanceTransaction? _originalTransaction;
  FinanceTransaction? _editingTransaction;
  FinanceLoanInstallment? _linkedRepayment;
  int _remainingRefundableMinor = 0;
  bool _installmentEnabled = false;
  int _installmentCount = FinanceInstallmentCalculator.minCount;
  bool _isLoading = true;
  bool _isSaving = false;
  bool _saveCompleted = false;
  bool _catalogRefreshPending = false;
  bool _catalogRefreshInProgress = false;

  bool get _isEditing => widget.transaction != null;
  bool get _isLoanInterest => _linkedRepayment != null;
  bool get _isEditingInstallment => widget.transaction?.isInstallment == true;
  bool get _hasRefundBinding =>
      widget.originalTransaction != null ||
      widget.transaction?.relatedTransactionUuid?.isNotEmpty == true;
  bool get _isBoundRefund =>
      _type == FinanceTransactionType.refund && _hasRefundBinding;

  void _mutateState(VoidCallback fn) => setState(fn);

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    final transaction = widget.transaction;
    _editingTransaction = transaction;
    _timezoneOffsetMinutes =
        transaction?.timezoneOffsetMinutes ?? now.timeZoneOffset.inMinutes;
    final template = transaction == null ? widget.initialTemplate : null;
    final draft = transaction == null ? widget.initialDraft : null;
    _originalTransaction = widget.originalTransaction;
    _type = widget.originalTransaction != null
        ? FinanceTransactionType.refund
        : transaction?.type ??
              draft?.type ??
              template?.type ??
              FinanceTransactionType.expense;
    _targetPaymentMethodUuid = transaction?.targetPaymentMethodUuid;
    if (_isEditingInstallment) {
      _installmentEnabled = true;
      _installmentCount =
          transaction!.installmentCount ??
          FinanceInstallmentCalculator.minCount;
    }
    _date = transaction == null
        ? draft == null
              ? widget.initialDate == null
                    ? now
                    : DateTime(
                        widget.initialDate!.year,
                        widget.initialDate!.month,
                        widget.initialDate!.day,
                      )
              : dateFromKey(draft.transactionDate)
        : dateFromKey(transaction.transactionDate);
    if (transaction == null) {
      _occurredAt = _defaultOccurrenceTimeFor(_date, now);
    } else {
      final occurred = transaction.occurrenceLocalTime;
      _occurredAt =
          occurred != null && dateKey(occurred) == transaction.transactionDate
          ? occurred
          : null;
      _occurrenceTimeExplicit = _occurredAt != null;
    }
    if (transaction == null && _occurredAt != null) {
      _timezoneOffsetMinutes = financeDefaultOccurrenceTimezoneOffsetMinutes(
        occurrence: _occurredAt,
        now: now,
      );
    }
    _amountController = TextEditingController(
      text: transaction == null
          ? draft != null
                ? formatFinanceAmount(draft.amountMinor, withSymbol: false)
                : template == null
                ? ''
                : formatFinanceAmount(template.amountMinor, withSymbol: false)
          : formatFinanceAmountInput(transaction.amountMinor),
    );
    _merchantController = TextEditingController(
      text:
          transaction?.merchant ??
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
    _categoryUuid =
        transaction?.categoryUuid ??
        widget.originalTransaction?.categoryUuid ??
        draft?.categoryUuid ??
        template?.categoryUuid;
    _paymentMethodUuid =
        transaction?.paymentMethodUuid ??
        widget.originalTransaction?.paymentMethodUuid ??
        draft?.paymentMethodUuid ??
        template?.paymentMethodUuid;
    _selectedTemplateUuid = template?.uuid;
    startListeningToFinanceRevision();
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

  @override
  void onFinanceRevisionRefresh() {
    if (_isSaving || _saveCompleted) return;
    if (_isLoading || _catalogRefreshInProgress) {
      _catalogRefreshPending = true;
      return;
    }
    unawaited(_refreshCatalogOptions());
  }

  Future<void> _refreshCatalogOptions() async {
    if (!mounted) return;
    if (_isLoading || _catalogRefreshInProgress) {
      _catalogRefreshPending = true;
      return;
    }

    _catalogRefreshInProgress = true;
    try {
      do {
        _catalogRefreshPending = false;
        final categories = await FinanceStorage.getCategories(
          includeArchived: true,
        );
        final paymentMethods = await FinanceStorage.getPaymentMethods(
          includeArchived: true,
        );
        final templates = await FinanceStorage.getTemplates();
        if (!mounted) return;
        setState(() {
          _replaceCategories(categories);
          _replacePaymentMethods(paymentMethods);
          _templates = templates;
          if (widget.transaction == null &&
              widget.originalTransaction == null) {
            _clearArchivedNewEntryAssociations();
            _normalizeSelections(
              notify: false,
              allowDefaultCategory:
                  !_archivedCategoryRequiresSelection &&
                  !_shouldKeepUnresolvedDraftCategory(),
            );
          }
        });
      } while (_catalogRefreshPending);
    } catch (error) {
      debugPrint('刷新记账选项失败：$error');
    } finally {
      _catalogRefreshInProgress = false;
      _drainPendingCatalogRefresh();
    }
  }

  void _drainPendingCatalogRefresh() {
    if (!mounted ||
        !_catalogRefreshPending ||
        _isLoading ||
        _catalogRefreshInProgress) {
      return;
    }
    _catalogRefreshPending = false;
    unawaited(_refreshCatalogOptions());
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final topBarHeight = floatingGlassTopBarHeight(context);
    return Scaffold(
      resizeToAvoidBottomInset: true,
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
            ? AppSkeletonFormPage(
                topPadding: topBarHeight + 8,
                showAmountHeader: true,
                fieldCount: 5,
              )
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
                        if (_isLoanInterest) ...[
                          const SizedBox(height: 12),
                          Text(
                            '贷款利息金额由还款计划确定，账户和时间请在还款记录中修改。商家和备注仍可编辑。',
                            style: TextStyle(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: TextButton.icon(
                              key: const ValueKey('finance-linked-repayment'),
                              onPressed: _isSaving ? null : _openRepayment,
                              icon: const Icon(Icons.account_balance_outlined),
                              label: const Text('查看还款记录'),
                            ),
                          ),
                        ],
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
                          key: const ValueKey('finance-amount-field'),
                          controller: _amountController,
                          autofocus: false,
                          readOnly: true,
                          showCursor: false,
                          keyboardType: TextInputType.none,
                          onTap: _isSaving || _isLoanInterest
                              ? null
                              : _showAmountCalculator,
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
                            suffixIcon: Icon(
                              Icons.calculate_outlined,
                              color: colorScheme.primary,
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
                        const SizedBox(height: 8),
                        _buildOccurrenceTimeField(colorScheme),
                        if (_type == FinanceTransactionType.expense &&
                            !_isLoanInterest) ...[
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
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
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
}
