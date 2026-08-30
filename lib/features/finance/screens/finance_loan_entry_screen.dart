import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../widgets/floating_glass_control.dart';
import '../models/finance_models.dart';
import '../services/finance_repository.dart';

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
    if (!_formKey.currentState!.validate()) return;
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

  FinanceLoanScheduleAllocation? _previewSchedule() {
    final principal = parseFinanceAmount(_principalController.text);
    final rate = parseFinanceInterestRate(_rateController.text);
    final term = int.tryParse(_termController.text.trim());
    if (principal == null || rate == null || term == null) return null;
    try {
      final schedule = FinanceLoanCalculator.generate(
        principalMinor: principal,
        annualInterestRateBps: rate,
        termMonths: term,
        startDate: _startDate,
        repaymentDay: _repaymentDay,
        repaymentMethod: _repaymentMethod,
      );
      return schedule.isEmpty ? null : schedule.first;
    } catch (_) {
      return null;
    }
  }

  Widget _buildPreview(ColorScheme colorScheme) {
    final first = _previewSchedule();
    final principal = parseFinanceAmount(_principalController.text);
    final rate = parseFinanceInterestRate(_rateController.text);
    final term = int.tryParse(_termController.text.trim());
    if (first == null || principal == null || rate == null || term == null) {
      return const SizedBox.shrink();
    }
    final schedule = FinanceLoanCalculator.generate(
      principalMinor: principal,
      annualInterestRateBps: rate,
      termMonths: term,
      startDate: _startDate,
      repaymentDay: _repaymentDay,
      repaymentMethod: _repaymentMethod,
    );
    final totalInterest = schedule.fold<int>(
      0,
      (sum, item) => sum + item.interestMinor,
    );
    final totalPayment = schedule.fold<int>(
      0,
      (sum, item) => sum + item.paymentMinor,
    );
    return Card(
      color: colorScheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '还款预览',
              style: TextStyle(
                color: colorScheme.onSecondaryContainer,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              '首期 ${first.dueDate} · ${formatFinanceAmount(first.paymentMinor)}',
              style: TextStyle(color: colorScheme.onSecondaryContainer),
            ),
            const SizedBox(height: 4),
            Text(
              '预计总利息 ${formatFinanceAmount(totalInterest)} · 总还款 ${formatFinanceAmount(totalPayment)}',
              style: TextStyle(
                color: colorScheme.onSecondaryContainer.withValues(alpha: 0.82),
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  InputDecoration _decoration({
    required String labelText,
    IconData? icon,
    String? suffixText,
    String? hintText,
  }) {
    return InputDecoration(
      labelText: labelText,
      prefixIcon: icon == null ? null : Icon(icon),
      suffixText: suffixText,
      hintText: hintText,
      border: const OutlineInputBorder(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: FloatingGlassAppBar(
        flexibleSpace: const FloatingGlassTopBarBackground(),
        title: Text(_isEditing ? '编辑贷款' : '新增贷款'),
        actions: [
          TextButton(
            onPressed: _isSaving ? null : _save,
            child: const Text('保存'),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            TextFormField(
              controller: _nameController,
              autofocus: !_isEditing,
              maxLength: 60,
              decoration: _decoration(
                labelText: '贷款名称',
                icon: Icons.account_balance_outlined,
                hintText: '例如：房贷、消费贷',
              ),
              validator: (value) =>
                  value?.trim().isEmpty == true ? '请输入贷款名称' : null,
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _lenderController,
              maxLength: 60,
              decoration: _decoration(
                labelText: '出借方（可选）',
                icon: Icons.business_outlined,
                hintText: '例如：某银行',
              ),
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _principalController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
              ],
              decoration: _decoration(
                labelText: '借款本金',
                icon: Icons.payments_outlined,
                hintText: '0.00',
              ).copyWith(prefixText: '¥ '),
              validator: (value) =>
                  parseFinanceAmount(value ?? '') == null ? '请输入借款本金' : null,
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 14),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _rateController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.,%]')),
                    ],
                    decoration: _decoration(
                      labelText: '年利率',
                      icon: Icons.percent,
                      suffixText: '%',
                      hintText: '12.00',
                    ),
                    validator: (value) =>
                        parseFinanceInterestRate(value ?? '') == null
                            ? '请输入 0-100%'
                            : null,
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _termController,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: _decoration(
                      labelText: '贷款期限',
                      icon: Icons.timelapse_outlined,
                      suffixText: '个月',
                      hintText: '12',
                    ),
                    validator: (value) {
                      final term = int.tryParse(value?.trim() ?? '');
                      if (term == null ||
                          term < FinanceLoanCalculator.minTermMonths ||
                          term > FinanceLoanCalculator.maxTermMonths) {
                        return '1-360 个月';
                      }
                      return null;
                    },
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Card(
              child: Column(
                children: [
                  ListTile(
                    leading: Icon(
                      Icons.calendar_today_outlined,
                      color: colorScheme.primary,
                    ),
                    title: const Text('借款日期'),
                    subtitle: Text(dateKey(_startDate)),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: _isSaving ? null : _pickDate,
                  ),
                  const Divider(height: 1),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                    child: DropdownButtonFormField<int>(
                      initialValue: _repaymentDay,
                      decoration: _decoration(
                        labelText: '每月还款日',
                        icon: Icons.event_repeat_outlined,
                        suffixText: '日',
                      ),
                      items: [
                        for (var day = 1; day <= 31; day++)
                          DropdownMenuItem(value: day, child: Text('$day 日')),
                      ],
                      onChanged: _isSaving
                          ? null
                          : (value) {
                              if (value != null) {
                                setState(() => _repaymentDay = value);
                              }
                            },
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<FinanceLoanRepaymentMethod>(
              initialValue: _repaymentMethod,
              decoration: _decoration(
                labelText: '还款方式',
                icon: Icons.swap_vert_circle_outlined,
              ),
              items: [
                for (final method in FinanceLoanRepaymentMethod.values)
                  DropdownMenuItem(value: method, child: Text(method.label)),
              ],
              onChanged: _isSaving
                  ? null
                  : (value) {
                      if (value != null) {
                        setState(() => _repaymentMethod = value);
                      }
                    },
            ),
            const SizedBox(height: 14),
            _buildPreview(colorScheme),
            const SizedBox(height: 14),
            TextFormField(
              controller: _noteController,
              maxLength: 300,
              maxLines: 2,
              decoration: _decoration(
                labelText: '备注（可选）',
                icon: Icons.notes_outlined,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '借款本金不会计入收入。标记某期已还后，利息会作为支出记录，本金只用于减少剩余负债。',
              style: TextStyle(
                color: colorScheme.onSurfaceVariant,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _isSaving ? null : _save,
              icon: _isSaving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check),
              label: Text(_isSaving ? '保存中...' : '保存贷款'),
            ),
          ],
        ),
      ),
    );
  }
}
