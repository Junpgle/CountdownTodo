import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../widgets/floating_glass_control.dart';
import '../models/finance_models.dart';
import '../services/finance_repository.dart';
import '../widgets/finance_management_widgets.dart';

class FinanceLoanEntryScreen extends StatefulWidget {
  final FinanceLoan? loan;

  const FinanceLoanEntryScreen({super.key, this.loan});

  @override
  State<FinanceLoanEntryScreen> createState() => _FinanceLoanEntryScreenState();
}

class _FinanceLoanEntryScreenState extends State<FinanceLoanEntryScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _lenderController;
  late final TextEditingController _principalController;
  late final TextEditingController _rateController;
  late final TextEditingController _termController;
  late final TextEditingController _noteController;

  late DateTime _startDate;
  late int _repaymentDay;
  late FinanceLoanRepaymentMethod _repaymentMethod;
  bool _isSaving = false;

  bool get _isEditing => widget.loan != null;

  @override
  void initState() {
    super.initState();
    final loan = widget.loan;
    _startDate = loan == null ? DateTime.now() : dateFromKey(loan.startDate);
    _repaymentDay = loan?.repaymentDay ?? _startDate.day;
    _repaymentMethod = loan?.repaymentMethod ??
        FinanceLoanRepaymentMethod.equalPrincipalInterest;
    _nameController = TextEditingController(text: loan?.name ?? '');
    _lenderController = TextEditingController(text: loan?.lender ?? '');
    _principalController = TextEditingController(
      text: loan == null
          ? ''
          : formatFinanceAmount(loan.principalMinor, withSymbol: false),
    );
    _rateController = TextEditingController(
      text: loan == null ? '0' : _formatRateInput(loan.annualInterestRateBps),
    );
    _termController = TextEditingController(
      text: '${loan?.termMonths ?? 12}',
    );
    _noteController = TextEditingController(text: loan?.note ?? '');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _lenderController.dispose();
    _principalController.dispose();
    _rateController.dispose();
    _termController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  String _formatRateInput(int basisPoints) {
    return (basisPoints / 100).toStringAsFixed(2).replaceFirst(
          RegExp(r'\.?0+$'),
          '',
        );
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _startDate,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 3650)),
      helpText: '选择借款日期',
    );
    if (picked == null || !mounted) return;
    setState(() {
      _startDate = picked;
      if (!_isEditing) _repaymentDay = picked.day;
    });
  }

  Future<void> _save() async {
    if (_isSaving || !_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    final principal = parseFinanceAmount(_principalController.text);
    final rate = parseFinanceInterestRate(_rateController.text);
    final term = int.tryParse(_termController.text.trim());
    if (principal == null) {
      _showError('请输入有效的借款本金');
      return;
    }
    if (rate == null) {
      _showError('年利率请输入 0-100 之间、最多两位小数的百分比');
      return;
    }
    if (term == null ||
        term < FinanceLoanCalculator.minTermMonths ||
        term > FinanceLoanCalculator.maxTermMonths) {
      _showError(
        '贷款期限必须在 ${FinanceLoanCalculator.minTermMonths}-'
        '${FinanceLoanCalculator.maxTermMonths} 个月之间',
      );
      return;
    }
    if (term > principal) {
      _showError('贷款期限不能超过本金的分（人民币分）');
      return;
    }

    setState(() => _isSaving = true);
    final old = widget.loan;
    final now = DateTime.now().millisecondsSinceEpoch;
    final loan = FinanceLoan(
      uuid: old?.uuid,
      name: _nameController.text.trim(),
      lender: _emptyToNull(_lenderController.text),
      principalMinor: principal,
      currencyCode: old?.currencyCode ?? FinanceDefaults.defaultCurrencyCode,
      annualInterestRateBps: rate,
      termMonths: term,
      startDate: dateKey(_startDate),
      repaymentDay: _repaymentDay,
      repaymentMethod: _repaymentMethod,
      note: _emptyToNull(_noteController.text),
      version: old?.version ?? 1,
      createdAt: old?.createdAt ?? now,
      updatedAt: old?.updatedAt ?? now,
      deviceId: old?.deviceId,
    );

    try {
      await FinanceRepository.saveLoan(loan);
      if (!mounted) return;
      Navigator.of(context).pop(loan);
    } catch (error) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      _showError('保存贷款失败：$error');
    }
  }

  String? _emptyToNull(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Widget _buildPreview() {
    final principal = parseFinanceAmount(_principalController.text);
    final rate = parseFinanceInterestRate(_rateController.text);
    final term = int.tryParse(_termController.text.trim());
    List<FinanceLoanScheduleAllocation>? schedule;
    if (principal != null && rate != null && term != null) {
      try {
        schedule = FinanceLoanCalculator.generate(
          principalMinor: principal,
          annualInterestRateBps: rate,
          termMonths: term,
          startDate: _startDate,
          repaymentDay: _repaymentDay,
          repaymentMethod: _repaymentMethod,
        );
      } catch (_) {
        // Incomplete form values do not have a repayment preview yet.
      }
    }
    if (schedule == null || schedule.isEmpty) {
      return const FinanceSectionCard(
        title: '还款预览',
        icon: Icons.insights_outlined,
        child: Text('填写本金、利率和期限后，这里会显示首期还款与总利息。'),
      );
    }
    final colors = Theme.of(context).colorScheme;
    final first = schedule.first;
    final totalInterest =
        schedule.fold<int>(0, (sum, item) => sum + item.interestMinor);
    final totalPayment =
        schedule.fold<int>(0, (sum, item) => sum + item.paymentMinor);
    return FinanceSectionCard(
      key: const ValueKey('finance-loan-preview'),
      title: '还款预览',
      icon: Icons.insights_outlined,
      color: colors.secondaryContainer.withValues(alpha: 0.45),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('首期应还',
            style: Theme.of(context)
                .textTheme
                .labelLarge
                ?.copyWith(color: colors.onSurfaceVariant)),
        const SizedBox(height: 6),
        Text(formatFinanceAmount(first.paymentMinor),
            style: Theme.of(context)
                .textTheme
                .headlineSmall
                ?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 10),
        FinanceStatusBadge(
            label: first.dueDate, icon: Icons.calendar_today_outlined),
        const SizedBox(height: 18),
        FinanceAdaptiveFields(minChildWidth: 180, children: [
          _previewMetric('预计总利息', totalInterest),
          _previewMetric('预计总还款', totalPayment),
        ]),
      ]),
    );
  }

  Widget _previewMetric(String label, int amount) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant)),
      const SizedBox(height: 4),
      Text(formatFinanceAmount(amount),
          style: Theme.of(context)
              .textTheme
              .titleMedium
              ?.copyWith(fontWeight: FontWeight.w700)),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return PopScope(
      canPop: !_isSaving,
      child: Scaffold(
        appBar: FloatingGlassAppBar(
          flexibleSpace: const FloatingGlassTopBarBackground(),
          title: Text(_isEditing ? '编辑贷款' : '新增贷款'),
        ),
        body: Column(children: [
          Expanded(
            child: AbsorbPointer(
              absorbing: _isSaving,
              child: Form(
                key: _formKey,
                child: FinancePageList(maxWidth: 720, children: [
                  FinanceSectionCard(
                    title: '借款信息',
                    icon: Icons.account_balance_outlined,
                    child: Column(children: [
                      TextFormField(
                        key: const ValueKey('finance-loan-name'),
                        controller: _nameController,
                        maxLength: 60,
                        textInputAction: TextInputAction.next,
                        decoration: financeFieldDecoration(context,
                                label: '贷款名称', hint: '例如：房贷、消费贷')
                            .copyWith(counterText: ''),
                        validator: (value) =>
                            value == null || value.trim().isEmpty
                                ? '请输入贷款名称'
                                : null,
                      ),
                      const SizedBox(height: 16),
                      FinanceAmountField(
                        key: const ValueKey('finance-loan-principal'),
                        controller: _principalController,
                        label: '借款本金',
                        onChanged: (_) => setState(() {}),
                      ),
                    ]),
                  ),
                  const SizedBox(height: 16),
                  FinanceSectionCard(
                    title: '还款设置',
                    icon: Icons.event_repeat_outlined,
                    child: Column(children: [
                      FinanceAdaptiveFields(minChildWidth: 150, children: [
                        TextFormField(
                          key: const ValueKey('finance-loan-rate'),
                          controller: _rateController,
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(
                                RegExp(r'[0-9.,%]'))
                          ],
                          decoration: financeFieldDecoration(context,
                              label: '年利率', suffix: '%', hint: '0.00'),
                          validator: (value) =>
                              parseFinanceInterestRate(value ?? '') == null
                                  ? '请输入 0–100%'
                                  : null,
                          onChanged: (_) => setState(() {}),
                        ),
                        TextFormField(
                          key: const ValueKey('finance-loan-term'),
                          controller: _termController,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly
                          ],
                          decoration: financeFieldDecoration(context,
                              label: '贷款期限', suffix: '个月'),
                          validator: (value) {
                            final term = int.tryParse(value?.trim() ?? '');
                            return term == null ||
                                    term <
                                        FinanceLoanCalculator.minTermMonths ||
                                    term > FinanceLoanCalculator.maxTermMonths
                                ? '请输入 1–360 个月'
                                : null;
                          },
                          onChanged: (_) => setState(() {}),
                        ),
                      ]),
                      const SizedBox(height: 16),
                      DropdownButtonFormField<FinanceLoanRepaymentMethod>(
                        key: const ValueKey('finance-loan-method'),
                        initialValue: _repaymentMethod,
                        isExpanded: true,
                        decoration:
                            financeFieldDecoration(context, label: '还款方式'),
                        items: [
                          for (final method
                              in FinanceLoanRepaymentMethod.values)
                            DropdownMenuItem(
                                value: method, child: Text(method.label))
                        ],
                        onChanged: (value) {
                          if (value != null) {
                            setState(() => _repaymentMethod = value);
                          }
                        },
                      ),
                      const SizedBox(height: 16),
                      FinanceAdaptiveFields(children: [
                        InkWell(
                          key: const ValueKey('finance-loan-start'),
                          borderRadius: BorderRadius.circular(14),
                          onTap: _pickDate,
                          child: InputDecorator(
                            decoration: financeFieldDecoration(context,
                                label: '借款日期',
                                icon: Icons.calendar_today_outlined),
                            child: Text(dateKey(_startDate)),
                          ),
                        ),
                        DropdownButtonFormField<int>(
                          key: ValueKey(
                              'finance-loan-repayment-day-$_repaymentDay'),
                          initialValue: _repaymentDay,
                          isExpanded: true,
                          decoration: financeFieldDecoration(context,
                              label: '每月还款日', helper: '当月没有该日期时，按月末还款。'),
                          items: [
                            for (var day = 1; day <= 31; day++)
                              DropdownMenuItem(
                                  value: day, child: Text('$day 日'))
                          ],
                          onChanged: (value) {
                            if (value != null) {
                              setState(() => _repaymentDay = value);
                            }
                          },
                        ),
                      ]),
                    ]),
                  ),
                  const SizedBox(height: 16),
                  _buildPreview(),
                  const SizedBox(height: 16),
                  FinanceSectionCard(
                    child: ExpansionTile(
                      tilePadding: EdgeInsets.zero,
                      childrenPadding: const EdgeInsets.only(top: 14),
                      shape: const Border(),
                      collapsedShape: const Border(),
                      initiallyExpanded: _lenderController.text.isNotEmpty ||
                          _noteController.text.isNotEmpty,
                      title: const Text('补充信息'),
                      subtitle: const Text('出借方、备注 · 可选'),
                      children: [
                        TextFormField(
                          controller: _lenderController,
                          maxLength: 60,
                          decoration: financeFieldDecoration(context,
                              label: '出借方',
                              icon: Icons.business_outlined,
                              hint: '例如：某银行'),
                        ),
                        const SizedBox(height: 14),
                        TextFormField(
                          controller: _noteController,
                          maxLength: 300,
                          minLines: 2,
                          maxLines: 4,
                          decoration: financeFieldDecoration(context,
                              label: '备注', icon: Icons.notes_outlined),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '借款本金不会计入收入。标记某期已还后，利息会作为支出记录，本金只用于减少剩余负债。',
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: colors.onSurfaceVariant, height: 1.5),
                  ),
                ]),
              ),
            ),
          ),
          FinanceFormActions(isSaving: _isSaving, onSave: _save, label: '保存贷款'),
        ]),
      ),
    );
  }
}
