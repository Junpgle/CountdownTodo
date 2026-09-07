import 'package:countdown_todo/features/finance/models/finance_models.dart';
import 'package:countdown_todo/features/finance/screens/finance_transaction_detail_screen.dart';
import 'package:countdown_todo/features/finance/widgets/finance_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

FinanceTransaction _transaction() => FinanceTransaction(
      uuid: 'transaction-detail-test',
      type: FinanceTransactionType.expense,
      amountMinor: 2850,
      transactionDate: '2026-09-07',
      occurredAt: DateTime(2026, 9, 7, 12, 30).millisecondsSinceEpoch,
      merchant: '午餐',
      note: '和同事一起吃饭',
      categoryUuid: 'food',
      paymentMethodUuid: 'wechat',
      installmentGroupUuid: 'lunch-installment',
      installmentIndex: 1,
      installmentCount: 3,
      installmentTotalMinor: 8550,
    );

Future<void> _pump(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
      ),
      home: child,
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('账单列表点击打开详情而不是直接编辑', (tester) async {
    var opened = false;
    var edited = false;
    final transaction = _transaction();

    await _pump(
      tester,
      Scaffold(
        body: SizedBox(
          height: 720,
          child: FinanceLedgerPanel(
            transactions: [transaction],
            categories: {
              'food': FinanceCategory(uuid: 'food', name: '餐饮', icon: '🍜'),
            },
            paymentMethods: {
              'wechat': FinancePaymentMethod(
                uuid: 'wechat',
                name: '微信',
                icon: '💬',
              ),
            },
            keyword: '',
            filterType: null,
            onOpenDetail: (_) => opened = true,
            onKeywordChanged: (_) {},
            onFilterChanged: (_) {},
            onEdit: (_) => edited = true,
            onDelete: (_) {},
            onRefund: (_) {},
          ),
        ),
      ),
    );

    await tester.tap(find.text('午餐'));
    expect(opened, isTrue);
    expect(edited, isFalse);
  });

  testWidgets('账单详情展示完整信息并提供编辑入口', (tester) async {
    await _pump(
      tester,
      FinanceTransactionDetailScreen(
        transaction: _transaction(),
        category: FinanceCategory(uuid: 'food', name: '餐饮', icon: '🍜'),
        paymentMethod: FinancePaymentMethod(
          uuid: 'wechat',
          name: '微信',
          icon: '💬',
        ),
      ),
    );

    expect(find.text('账单详情'), findsOneWidget);
    expect(find.text('午餐'), findsOneWidget);
    expect(find.text('-¥28.50'), findsOneWidget);
    expect(find.textContaining('餐饮'), findsOneWidget);
    expect(find.textContaining('微信'), findsOneWidget);
    expect(find.text('和同事一起吃饭'), findsOneWidget);
    expect(find.text('第 1/3 期 · 总额 ¥85.50'), findsOneWidget);
    expect(find.byKey(const ValueKey('finance-transaction-detail-edit')),
        findsOneWidget);
    expect(find.byTooltip('编辑账单'), findsOneWidget);
  });
}
