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
    GlobalKey? sourceKey;
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
            onOpenDetail: (_, key) {
              opened = true;
              sourceKey = key;
            },
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
    expect(sourceKey?.currentContext, isNotNull);
  });

  testWidgets('账单列表按日期归类并显示每天的净支出', (tester) async {
    final sameDay = FinanceTransaction(
      uuid: 'transaction-same-day',
      amountMinor: 1200,
      transactionDate: '2026-09-07',
      occurredAt: DateTime(2026, 9, 7, 8).millisecondsSinceEpoch,
      merchant: '咖啡',
      categoryUuid: 'food',
    );
    final previousDay = FinanceTransaction(
      uuid: 'transaction-previous-day',
      amountMinor: 1800,
      transactionDate: '2026-09-06',
      occurredAt: DateTime(2026, 9, 6, 8).millisecondsSinceEpoch,
      merchant: '早餐',
      categoryUuid: 'food',
    );

    await _pump(
      tester,
      Scaffold(
        body: SizedBox(
          height: 720,
          child: FinanceLedgerPanel(
            // 故意打乱输入顺序，确保分组组件自身负责日期和组内排序。
            transactions: [previousDay, _transaction(), sameDay],
            categories: {
              'food': FinanceCategory(uuid: 'food', name: '餐饮', icon: '🍜'),
            },
            paymentMethods: const {},
            keyword: '',
            filterType: null,
            onOpenDetail: (_, __) {},
            onKeywordChanged: (_) {},
            onFilterChanged: (_) {},
            onEdit: (_) {},
            onDelete: (_) {},
            onRefund: (_) {},
          ),
        ),
      ),
    );

    expect(find.text('9月7日 周一'), findsOneWidget);
    expect(find.text('净支出 ¥40.50'), findsOneWidget);
    expect(find.text('9月6日 周日'), findsOneWidget);
    expect(find.text('净支出 ¥18.00'), findsOneWidget);
    expect(find.text('3 笔账单'), findsNothing);
    expect(find.text('2 笔账单'), findsOneWidget);
    expect(find.text('1 笔账单'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('记账概览支持月、周、日三种时间视图', (tester) async {
    final transaction = FinanceTransaction(
      uuid: 'overview-transaction',
      amountMinor: 1200,
      transactionDate: '2026-09-01',
      occurredAt: DateTime(2026, 9, 1, 9).millisecondsSinceEpoch,
      merchant: '早餐',
      categoryUuid: 'food',
    );
    const summary = FinanceSummary(
      expenseMinor: 1200,
      transactionCount: 1,
      expenseByCategory: {'food': 1200},
      expenseByDate: {'2026-09-01': 1200},
    );
    DateTime? changedMonth;

    await _pump(
      tester,
      Scaffold(
        body: FinanceOverviewPanel(
          month: DateTime(2026, 9),
          summary: summary,
          transactions: [transaction],
          categories: {
            'food': FinanceCategory(uuid: 'food', name: '餐饮', icon: '🍜'),
          },
          onAdd: () {},
          addActionKey: GlobalKey(),
          onRefresh: () async {},
          onMonthChanged: (value) => changedMonth = value,
        ),
      ),
    );

    expect(find.text('月视图'), findsOneWidget);
    expect(find.text('每日支出'), findsOneWidget);
    expect(find.text('2026 年 9 月'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('finance-overview-period-previous')),
    );
    await tester.pump();
    expect(changedMonth, DateTime(2026, 8));

    await tester.tap(find.text('周视图'));
    await tester.pumpAndSettle();
    expect(find.text('周一至周日'), findsOneWidget);
    expect(find.text('本周每日支出'), findsOneWidget);

    await tester.tap(find.text('日视图'));
    await tester.pumpAndSettle();
    expect(find.text('选择具体日期'), findsOneWidget);
    expect(find.text('当天时段支出'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('概览按一级分类汇总，点击后展示小类并可选择账单筛选', (tester) async {
    String? selectedCategoryUuid;
    final transactions = [
      FinanceTransaction(
        uuid: 'overview-milk-tea',
        amountMinor: 1200,
        transactionDate: '2026-09-01',
        merchant: '奶茶店',
        categoryUuid: 'milk-tea',
      ),
      FinanceTransaction(
        uuid: 'overview-coffee',
        amountMinor: 800,
        transactionDate: '2026-09-02',
        merchant: '咖啡店',
        categoryUuid: 'coffee',
      ),
      FinanceTransaction(
        uuid: 'overview-direct',
        amountMinor: 500,
        transactionDate: '2026-09-03',
        merchant: '餐饮未细分',
        categoryUuid: 'food',
      ),
      FinanceTransaction(
        uuid: 'overview-transport',
        amountMinor: 1000,
        transactionDate: '2026-09-04',
        merchant: '打车',
        categoryUuid: 'transport',
      ),
    ];
    const summary = FinanceSummary(
      expenseMinor: 3500,
      transactionCount: 4,
      expenseByDate: {
        '2026-09-01': 1200,
        '2026-09-02': 800,
        '2026-09-03': 500,
        '2026-09-04': 1000,
      },
    );

    await _pump(
      tester,
      Scaffold(
        body: FinanceOverviewPanel(
          month: DateTime(2026, 9),
          summary: summary,
          transactions: transactions,
          categories: {
            'food': FinanceCategory(uuid: 'food', name: '餐饮', icon: '🍜'),
            'milk-tea': FinanceCategory(
              uuid: 'milk-tea',
              name: '奶茶',
              icon: '🧋',
              parentUuid: 'food',
            ),
            'coffee': FinanceCategory(
              uuid: 'coffee',
              name: '咖啡',
              icon: '☕',
              parentUuid: 'food',
            ),
            'transport':
                FinanceCategory(uuid: 'transport', name: '交通', icon: '🚕'),
          },
          onAdd: () {},
          addActionKey: GlobalKey(),
          onRefresh: () async {},
          onCategorySelected: (value) => selectedCategoryUuid = value,
        ),
      ),
    );

    await tester.ensureVisible(
      find.byKey(const ValueKey('finance-overview-category-food')),
    );
    await tester.pumpAndSettle();
    expect(find.text('餐饮 - 奶茶'), findsNothing);
    expect(find.textContaining('餐饮'), findsOneWidget);
    expect(find.text('¥25.00'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('finance-overview-category-food')),
    );
    await tester.pumpAndSettle();
    expect(find.text('支出分类详情'), findsOneWidget);
    expect(find.text('奶茶'), findsOneWidget);
    expect(find.text('咖啡'), findsOneWidget);
    expect(find.text('未细分'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('finance-category-detail-milk-tea')),
    );
    await tester.pumpAndSettle();
    expect(selectedCategoryUuid, 'milk-tea');
  });

  testWidgets('账单页按小类精确筛选并支持清除筛选', (tester) async {
    String? categoryFilter = 'milk-tea';
    final transactions = [
      FinanceTransaction(
        uuid: 'ledger-milk-tea',
        amountMinor: 1200,
        transactionDate: '2026-09-01',
        merchant: '奶茶店',
        categoryUuid: 'milk-tea',
      ),
      FinanceTransaction(
        uuid: 'ledger-coffee',
        amountMinor: 800,
        transactionDate: '2026-09-02',
        merchant: '咖啡店',
        categoryUuid: 'coffee',
      ),
    ];

    await _pump(
      tester,
      Scaffold(
        body: StatefulBuilder(
          builder: (context, setState) => FinanceLedgerPanel(
            transactions: transactions,
            categories: {
              'food': FinanceCategory(uuid: 'food', name: '餐饮', icon: '🍜'),
              'milk-tea': FinanceCategory(
                uuid: 'milk-tea',
                name: '奶茶',
                icon: '🧋',
                parentUuid: 'food',
              ),
              'coffee': FinanceCategory(
                uuid: 'coffee',
                name: '咖啡',
                icon: '☕',
                parentUuid: 'food',
              ),
            },
            paymentMethods: const {},
            keyword: '',
            filterType: null,
            categoryUuid: categoryFilter,
            onOpenDetail: (_, __) {},
            onKeywordChanged: (_) {},
            onFilterChanged: (_) {},
            onCategoryChanged: (value) =>
                setState(() => categoryFilter = value),
            onEdit: (_) {},
            onDelete: (_) {},
            onRefund: (_) {},
          ),
        ),
      ),
    );

    expect(find.text('奶茶店'), findsOneWidget);
    expect(find.text('咖啡店'), findsNothing);
    await tester.tap(
      find.byKey(const ValueKey('finance-ledger-category-filter')),
    );
    await tester.pumpAndSettle();
    expect(categoryFilter, isNull);
    expect(find.text('咖啡店'), findsOneWidget);
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
