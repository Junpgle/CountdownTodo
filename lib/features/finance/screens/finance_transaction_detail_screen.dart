import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../utils/page_transitions.dart';
import '../../../widgets/app_detail_widgets.dart';
import '../../../widgets/floating_glass_control.dart';
import '../models/finance_models.dart';
import '../services/finance_repository.dart';
import 'finance_entry_screen.dart';

/// Read-only presentation of a saved finance transaction.
///
/// Editing is deliberately one action away from this screen, so tapping a
/// ledger row is safe for people who only want to inspect a bill.
class FinanceTransactionDetailScreen extends StatelessWidget {
  final FinanceTransaction transaction;
  final FinanceCategory? category;
  final FinancePaymentMethod? paymentMethod;

  const FinanceTransactionDetailScreen({
    super.key,
    required this.transaction,
    this.category,
    this.paymentMethod,
  });

  String get _title {
    final merchant = transaction.merchant?.trim();
    if (merchant != null && merchant.isNotEmpty) return merchant;
    if (category != null) return category!.name;
    return transaction.type.label;
  }

  Color _amountColor(ColorScheme colorScheme) {
    return transaction.type == FinanceTransactionType.expense
        ? colorScheme.error
        : colorScheme.primary;
  }

  String _categoryLabel() {
    final value = category;
    return value == null ? '未分类' : '${value.icon} ${value.name}';
  }

  String _paymentMethodLabel() {
    final value = paymentMethod;
    return value == null ? '未指定' : '${value.icon} ${value.name}';
  }

  String _occurredAtLabel() {
    final occurredAt = transaction.occurredAt;
    if (occurredAt == null || occurredAt <= 0) return '未记录';
    return DateFormat('yyyy年M月d日 HH:mm').format(
      DateTime.fromMillisecondsSinceEpoch(occurredAt),
    );
  }

  Future<void> _openEditor(BuildContext context) async {
    final result = await Navigator.of(context).push<FinanceTransaction>(
      PageTransitions.material(
        builder: (_) => FinanceEntryScreen(transaction: transaction),
      ),
    );
    if (result != null && context.mounted) {
      Navigator.of(context).pop(result);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final amountColor = _amountColor(colorScheme);
    final subtitle = [
      transaction.type.label,
      transaction.transactionDate,
      if (transaction.installmentLabel != null) transaction.installmentLabel!,
    ].join(' · ');

    return AppDetailScreen(
      appBarTitle: '账单详情',
      icon: Icons.receipt_long_rounded,
      title: _title,
      headerSubtitle: subtitle,
      color: amountColor,
      iconSize: 64,
      titleSize: 22,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      scrollPhysics: const BouncingScrollPhysics(),
      appBarActions: [
        IconButton(
          key: const ValueKey('finance-transaction-detail-edit'),
          style: floatingGlassPlainIconButtonStyle(),
          tooltip: '编辑账单',
          onPressed: () => _openEditor(context),
          icon: const Icon(Icons.edit_outlined),
        ),
      ],
      sections: [
        AppDetailSection(
          title: '账单信息',
          children: [
            AppDetailWideCard(
              icon: Icons.payments_outlined,
              title: '金额',
              value: formatSignedFinanceAmount(
                transaction.amountMinor,
                transaction.type,
              ),
              valueColor: amountColor,
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                children: [
                  Expanded(
                    child: AppDetailInfoCard(
                      icon: Icons.swap_vert_rounded,
                      title: '类型',
                      value: transaction.type.label,
                      valueColor: amountColor,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: AppDetailInfoCard(
                      icon: Icons.calendar_today_rounded,
                      title: '账单日期',
                      value: transaction.transactionDate,
                    ),
                  ),
                ],
              ),
            ),
            AppDetailWideCard(
              icon: Icons.category_outlined,
              title: '分类',
              value: _categoryLabel(),
            ),
            AppDetailWideCard(
              icon: Icons.account_balance_wallet_outlined,
              title: '付款方式',
              value: _paymentMethodLabel(),
            ),
            if (transaction.isInstallment)
              AppDetailWideCard(
                icon: Icons.event_repeat_outlined,
                title: '分期信息',
                value: '第 ${transaction.installmentLabel!}'
                    '${transaction.installmentTotalMinor == null ? '' : ' · 总额 ${formatFinanceAmount(transaction.installmentTotalMinor!)}'}',
              ),
          ],
        ),
        if (transaction.note?.trim().isNotEmpty == true)
          AppDetailSection(
            title: '备注',
            children: [
              AppDetailWideCard(
                icon: Icons.notes_rounded,
                title: '备注内容',
                value: transaction.note!.trim(),
                maxLines: 10,
              ),
            ],
          ),
        AppDetailSection(
          title: '记录信息',
          children: [
            AppDetailWideCard(
              icon: Icons.source_outlined,
              title: '记录来源',
              value: transaction.source.label,
            ),
            AppDetailWideCard(
              icon: Icons.schedule_rounded,
              title: '记录时间',
              value: _occurredAtLabel(),
            ),
            AppDetailWideCard(
              icon: Icons.currency_exchange_rounded,
              title: '币种',
              value: transaction.currencyCode,
            ),
          ],
        ),
      ],
    );
  }
}
