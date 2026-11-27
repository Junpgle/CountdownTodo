import 'package:countdown_todo/features/finance/models/finance_models.dart';
import 'package:countdown_todo/features/finance/widgets/finance_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget buildLedger({
    required List<FinanceTransaction> transactions,
    required String keyword,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: FinanceLedgerPanel(
          month: DateTime(2026, 11),
          clock: () => DateTime(2026, 11, 25, 12),
          transactions: transactions,
          categories: const {},
          paymentMethods: const {},
          keyword: keyword,
          filterType: null,
          onOpenDetail: (_, _) {},
          onKeywordChanged: (_) {},
          onFilterChanged: (_) {},
          onEdit: (_) {},
          onDelete: (_) {},
          onRefund: (_) {},
        ),
      ),
    );
  }

  testWidgets('记账明细搜索支持按订单金额过滤', (tester) async {
    final transactions = [
      FinanceTransaction(
        uuid: 'tx-1',
        type: FinanceTransactionType.expense,
        amountMinor: 123450,
        transactionDate: '2026-11-20',
        occurredAt: DateTime(2026, 11, 20, 10).millisecondsSinceEpoch,
        merchant: '咖啡店',
      ),
      FinanceTransaction(
        uuid: 'tx-2',
        type: FinanceTransactionType.expense,
        amountMinor: 2500,
        transactionDate: '2026-11-20',
        occurredAt: DateTime(2026, 11, 20, 11).millisecondsSinceEpoch,
        merchant: '便利店',
      ),
    ];

    for (final query in ['1234.50', '¥1,234.50', '¥1234.50', '1234']) {
      await tester.pumpWidget(
        buildLedger(transactions: transactions, keyword: query),
      );
      await tester.pumpAndSettle();

      expect(find.text('咖啡店'), findsOneWidget, reason: 'Failed for: $query');
      expect(find.text('便利店'), findsNothing, reason: 'Failed for: $query');
    }
  });
}
