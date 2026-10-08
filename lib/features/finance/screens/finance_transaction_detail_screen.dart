import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../utils/page_transitions.dart';
import '../../../widgets/app_detail_widgets.dart';
import '../../../widgets/floating_glass_control.dart';
import '../models/finance_models.dart';
import '../services/finance_repository.dart';
import '../services/finance_storage.dart';
import 'finance_entry_screen.dart';

/// Read-only presentation of a saved finance transaction.
///
/// Editing is deliberately one action away from this screen, so tapping a
/// ledger row is safe for people who only want to inspect a bill.
class FinanceTransactionDetailScreen extends StatefulWidget {
  final FinanceTransaction transaction;
  final FinanceCategory? category;
  final String? categoryDisplayName;
  final FinancePaymentMethod? paymentMethod;

  const FinanceTransactionDetailScreen({
    super.key,
    required this.transaction,
    this.category,
    this.categoryDisplayName,
    this.paymentMethod,
  });

  @override
  State<FinanceTransactionDetailScreen> createState() =>
      _FinanceTransactionDetailScreenState();
}

class _FinanceTransactionDetailScreenState
    extends State<FinanceTransactionDetailScreen> {
  late FinanceTransaction transaction;
  FinanceCategory? category;
  String? categoryDisplayName;
  FinancePaymentMethod? paymentMethod;
  Timer? _financeChangeRefreshTimer;
  bool _refreshInProgress = false;
  bool _refreshPending = false;
  bool _isUnavailable = false;

  @override
  void initState() {
    super.initState();
    transaction = widget.transaction;
    category = widget.category;
    categoryDisplayName = widget.categoryDisplayName;
    paymentMethod = widget.paymentMethod;
    FinanceStorage.revision.addListener(_onFinanceChanged);
  }

  @override
  void didUpdateWidget(covariant FinanceTransactionDetailScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.transaction, widget.transaction)) {
      transaction = widget.transaction;
      _isUnavailable = false;
    }
    if (!identical(oldWidget.category, widget.category)) {
      category = widget.category;
    }
    if (oldWidget.categoryDisplayName != widget.categoryDisplayName) {
      categoryDisplayName = widget.categoryDisplayName;
    }
    if (!identical(oldWidget.paymentMethod, widget.paymentMethod)) {
      paymentMethod = widget.paymentMethod;
    }
  }

  @override
  void dispose() {
    _financeChangeRefreshTimer?.cancel();
    FinanceStorage.revision.removeListener(_onFinanceChanged);
    super.dispose();
  }

  void _onFinanceChanged() {
    _financeChangeRefreshTimer?.cancel();
    _financeChangeRefreshTimer = Timer(const Duration(milliseconds: 100), () {
      _financeChangeRefreshTimer = null;
      if (mounted) unawaited(_reloadLatestTransaction());
    });
  }

  Future<void> _reloadLatestTransaction() async {
    if (_refreshInProgress) {
      _refreshPending = true;
      return;
    }
    _refreshInProgress = true;
    try {
      do {
        _refreshPending = false;
        final latestTransaction = await FinanceRepository.getTransaction(
          transaction.uuid,
        );
        if (latestTransaction == null || latestTransaction.isDeleted) {
          if (!mounted) return;
          setState(() => _isUnavailable = true);
          return;
        }
        final categories = await FinanceRepository.getCategories(
          includeArchived: true,
        );
        final paymentMethods = await FinanceRepository.getPaymentMethods(
          includeArchived: true,
        );
        if (!mounted) return;

        final latestCategory = categories
            .where((item) => item.uuid == latestTransaction.categoryUuid)
            .firstOrNull;
        final latestPaymentMethod = paymentMethods
            .where((item) => item.uuid == latestTransaction.paymentMethodUuid)
            .firstOrNull;
        setState(() {
          transaction = latestTransaction;
          _isUnavailable = false;
          category = latestCategory;
          categoryDisplayName = latestCategory == null
              ? null
              : financeCategoryDisplayName(latestCategory, categories);
          paymentMethod = latestPaymentMethod;
        });
      } while (_refreshPending);
    } catch (error) {
      debugPrint('刷新账单详情失败：$error');
    } finally {
      _refreshInProgress = false;
      if (mounted && _refreshPending) {
        _refreshPending = false;
        unawaited(_reloadLatestTransaction());
      }
    }
  }

  String get _title {
    final merchant = transaction.merchant?.trim();
    if (merchant != null && merchant.isNotEmpty) return merchant;
    if (category != null) return categoryDisplayName ?? category!.name;
    return transaction.type.label;
  }

  Color _amountColor(ColorScheme colorScheme) {
    return transaction.type == FinanceTransactionType.expense
        ? colorScheme.error
        : colorScheme.primary;
  }

  String _categoryLabel() {
    final value = category;
    return value == null
        ? '未分类'
        : '${value.icon} ${categoryDisplayName ?? value.name}';
  }

  String _paymentMethodLabel() {
    final value = paymentMethod;
    if (value != null) return '${value.icon} ${value.name}';
    return transaction.paymentMethodUuid?.trim().isNotEmpty == true
        ? switch (transaction.type) {
            FinanceTransactionType.expense => '已删除或未知付款方式',
            FinanceTransactionType.income => '已删除或未知到账账户',
            FinanceTransactionType.refund => '已删除或未知退款到账账户',
          }
        : transaction.type == FinanceTransactionType.expense
        ? '未指定'
        : '未指定（不更新账户余额）';
  }

  String _paymentMethodTitle() {
    return switch (transaction.type) {
      FinanceTransactionType.expense => '付款方式',
      FinanceTransactionType.income => '到账账户',
      FinanceTransactionType.refund => '退款到账账户',
    };
  }

  String _occurredAtLabel() {
    final occurred = transaction.occurrenceLocalTime;
    if (occurred == null) return '未记录';
    final time = DateFormat('yyyy年M月d日 HH:mm').format(occurred);
    final deviceOffsetAtOccurrence = DateTime.fromMillisecondsSinceEpoch(
      transaction.occurredAt!,
    ).timeZoneOffset.inMinutes;
    return transaction.timezoneOffsetMinutes == deviceOffsetAtOccurrence
        ? time
        : '$time（${financeTimezoneLabel(transaction.timezoneOffsetMinutes)}）';
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

  Widget _buildUnavailableScreen(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return AppDetailScreen(
      appBarTitle: '账单详情',
      icon: Icons.delete_outline_rounded,
      title: '账单已删除',
      headerSubtitle: '这笔记录已从账本中移除。',
      color: colors.onSurfaceVariant,
      iconSize: 64,
      titleSize: 22,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      scrollPhysics: const BouncingScrollPhysics(),
      appBarActions: const [],
      sections: [
        AppDetailSection(
          title: '记录状态',
          children: [
            AppDetailWideCard(
              icon: Icons.delete_outline_rounded,
              title: '账单已删除',
              value: '这笔记录已从账本中移除，无法继续编辑。',
            ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isUnavailable) return _buildUnavailableScreen(context);

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
              title: _paymentMethodTitle(),
              value: _paymentMethodLabel(),
            ),
            if (transaction.isInstallment)
              AppDetailWideCard(
                icon: Icons.event_repeat_outlined,
                title: '分期信息',
                value:
                    '第 ${transaction.installmentLabel!}'
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
              title: '发生时刻',
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
