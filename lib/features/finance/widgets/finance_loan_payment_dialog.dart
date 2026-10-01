import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../utils/app_dialogs.dart';
import '../models/finance_models.dart';
import '../services/finance_repository.dart';

class FinanceLoanPaymentSelection {
  final String? paymentMethodUuid;
  final DateTime paidAt;

  const FinanceLoanPaymentSelection({
    this.paymentMethodUuid,
    required this.paidAt,
  });
}

class FinanceLoanPaymentDialog extends StatefulWidget {
  final FinanceLoanInstallment installment;
  final List<FinancePaymentMethod> paymentMethods;

  const FinanceLoanPaymentDialog({
    super.key,
    required this.installment,
    required this.paymentMethods,
  });

  @override
  State<FinanceLoanPaymentDialog> createState() =>
      _FinanceLoanPaymentDialogState();
}

class _FinanceLoanPaymentDialogState extends State<FinanceLoanPaymentDialog> {
  static const _unlinked = '__unlinked__';
  final _formKey = GlobalKey<FormState>();
  String? _methodUuid;
  late DateTime _paidAt;

  @override
  void initState() {
    super.initState();
    _methodUuid = widget.installment.paymentMethodUuid ??
        (widget.installment.isPaid ? _unlinked : null);
    final paidAt = widget.installment.paidAt;
    _paidAt = paidAt == null || paidAt <= 0
        ? DateTime.now()
        : DateTime.fromMillisecondsSinceEpoch(paidAt);
  }

  Future<void> _pickTime() async {
    final now = DateTime.now();
    final earliest = DateTime(2000);
    final date = await showAppDatePicker(
      context: context,
      initialDate: _paidAt.isAfter(now)
          ? now
          : (_paidAt.isBefore(earliest) ? earliest : _paidAt),
      firstDate: earliest,
      lastDate: now,
      helpText: '选择实际还款日期',
    );
    if (date == null || !mounted) return;
    final time = await showAppTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_paidAt),
      helpText: '选择实际还款时刻',
    );
    if (time == null || !mounted) return;
    final selected = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );
    if (selected.isAfter(DateTime.now())) {
      AppSnackBars.showSnackBar(
        context,
        const SnackBar(content: Text('还款时间不能晚于现在')),
      );
      return;
    }
    setState(() => _paidAt = selected);
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.pop(
      context,
      FinanceLoanPaymentSelection(
        paymentMethodUuid: _methodUuid == _unlinked ? null : _methodUuid,
        paidAt: _paidAt,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final methods = widget.paymentMethods
        .where(
          (item) =>
              !item.isDeleted &&
              (!item.isArchived ||
                  item.uuid == widget.installment.paymentMethodUuid),
        )
        .toList();
    return AlertDialog(
      title: Text(widget.installment.isPaid ? '修改还款记录' : '记录还款'),
      content: SingleChildScrollView(
        child: SizedBox(
          width: 420,
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '本期还款 ${formatFinanceAmount(widget.installment.paymentMinor)}',
                ),
                const SizedBox(height: 8),
                const Text('所选账户余额会扣减本金和利息，支出统计只计入利息。'),
                const SizedBox(height: 20),
                DropdownButtonFormField<String>(
                  key: const ValueKey('finance-loan-payment-method'),
                  initialValue: _methodUuid,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: '还款账户'),
                  items: [
                    for (final method in methods)
                      DropdownMenuItem(
                        value: method.uuid,
                        child: Text(
                          '${method.icon} ${method.name}',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    if (_methodUuid != null &&
                        _methodUuid != _unlinked &&
                        methods.every((item) => item.uuid != _methodUuid))
                      DropdownMenuItem(
                        value: _methodUuid,
                        child: const Text('已删除或未知账户'),
                      ),
                    const DropdownMenuItem(
                      value: _unlinked,
                      child: Text('不关联账户（仅记录已还）'),
                    ),
                  ],
                  onChanged: (value) => setState(() => _methodUuid = value),
                  validator: (value) => value == null ? '请选择还款账户或不关联账户' : null,
                ),
                const SizedBox(height: 12),
                ListTile(
                  key: const ValueKey('finance-loan-payment-time'),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('实际还款时间'),
                  subtitle: Text(DateFormat('yyyy年M月d日 HH:mm').format(_paidAt)),
                  trailing: const Icon(Icons.schedule_outlined),
                  onTap: _pickTime,
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          key: const ValueKey('finance-loan-payment-save'),
          onPressed: _save,
          child: const Text('保存还款'),
        ),
      ],
    );
  }
}
