import 'package:countdown_todo/features/finance/models/finance_models.dart';
import 'package:countdown_todo/features/finance/widgets/finance_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  FinanceCategory buildCategory({
    required String uuid,
    required String name,
    String icon = '🍜',
    FinanceCategoryType type = FinanceCategoryType.expense,
    String? parentUuid,
  }) {
    return FinanceCategory(
      uuid: uuid,
      name: name,
      icon: icon,
      type: type,
      parentUuid: parentUuid,
    );
  }

  FinancePaymentMethod buildPaymentMethod({
    required String uuid,
    required String name,
    String icon = '💳',
  }) {
    return FinancePaymentMethod(uuid: uuid, name: name, icon: icon);
  }

  FinanceTransaction buildTransaction({
    required String uuid,
    FinanceTransactionType type = FinanceTransactionType.expense,
    int amountMinor = 2500,
    String? categoryUuid,
    String? paymentMethodUuid,
    String transactionDate = '2026-11-15',
    String? merchant,
    String? note,
  }) {
    return FinanceTransaction(
      uuid: uuid,
      type: type,
      amountMinor: amountMinor,
      categoryUuid: categoryUuid,
      paymentMethodUuid: paymentMethodUuid,
      transactionDate: transactionDate,
      occurredAt: DateTime(2026, 11, 15, 12).millisecondsSinceEpoch,
      merchant: merchant,
      note: note,
    );
  }

  Widget wrapLedger({
    required List<FinanceTransaction> transactions,
    required Map<String, FinanceCategory> categories,
    required Map<String, FinancePaymentMethod> paymentMethods,
    Future<void> Function(List<FinanceTransaction>)? onBatchSave,
    Future<void> Function(List<FinanceTransaction>)? onBatchDelete,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: FinanceLedgerPanel(
          month: DateTime(2026, 11),
          clock: () => DateTime(2026, 11, 15, 12),
          transactions: transactions,
          categories: categories,
          paymentMethods: paymentMethods,
          keyword: '',
          filterType: null,
          onOpenDetail: (_, _) {},
          onKeywordChanged: (_) {},
          onFilterChanged: (_) {},
          onEdit: (_) {},
          onDelete: (_) {},
          onRefund: (_) {},
          onBatchSave: onBatchSave,
          onBatchDelete: onBatchDelete,
        ),
      ),
    );
  }

  testWidgets('long press enters selection mode and batch updates category', (
    tester,
  ) async {
    final food = buildCategory(uuid: 'cat-food', name: '餐饮', icon: '🍜');
    final transport = buildCategory(
      uuid: 'cat-transport',
      name: '交通',
      icon: '🚇',
    );
    final tx1 = buildTransaction(
      uuid: 'tx-1',
      categoryUuid: food.uuid,
      merchant: '早餐店',
    );
    final tx2 = buildTransaction(
      uuid: 'tx-2',
      categoryUuid: food.uuid,
      merchant: '咖啡店',
    );

    List<FinanceTransaction>? saved;
    await tester.pumpWidget(
      wrapLedger(
        transactions: [tx1, tx2],
        categories: {food.uuid: food, transport.uuid: transport},
        paymentMethods: const {},
        onBatchSave: (updated) async {
          saved = updated;
        },
      ),
    );

    await tester.longPress(find.text('早餐店'));
    await tester.pumpAndSettle();

    expect(find.text('已选 1 笔 / 2 笔'), findsOneWidget);

    await tester.tap(find.text('咖啡店'));
    await tester.pumpAndSettle();
    expect(find.text('已选 2 笔 / 2 笔'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('finance-ledger-batch-category')),
    );
    await tester.pumpAndSettle();

    expect(find.text('批量修改分类（2 笔）'), findsOneWidget);
    await tester.tap(find.text('交通'));
    await tester.pumpAndSettle();

    expect(saved, isNotNull);
    expect(saved!.length, 2);
    expect(saved!.every((t) => t.categoryUuid == transport.uuid), isTrue);
    expect(saved!.every((t) => t.version == 2 && t.pendingSync), isTrue);
    expect(find.text('已将 2 笔账单分类改为「交通」'), findsOneWidget);
  });

  testWidgets('mixed expense and income selection blocks batch category edit', (
    tester,
  ) async {
    final food = buildCategory(uuid: 'cat-food', name: '餐饮', icon: '🍜');
    final salary = buildCategory(
      uuid: 'cat-salary',
      name: '工资',
      icon: '💼',
      type: FinanceCategoryType.income,
    );
    final tx1 = buildTransaction(
      uuid: 'tx-1',
      type: FinanceTransactionType.expense,
      categoryUuid: food.uuid,
      merchant: '午餐',
    );
    final tx2 = buildTransaction(
      uuid: 'tx-2',
      type: FinanceTransactionType.income,
      categoryUuid: salary.uuid,
      merchant: '奖金',
    );

    await tester.pumpWidget(
      wrapLedger(
        transactions: [tx1, tx2],
        categories: {food.uuid: food, salary.uuid: salary},
        paymentMethods: const {},
        onBatchSave: (_) async {},
      ),
    );

    await tester.tap(find.text('选择账单'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('全选'));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('finance-ledger-batch-category')),
    );
    await tester.pumpAndSettle();

    expect(find.text('所选账单同时包含支出和收入，请分开选择后再修改分类'), findsOneWidget);
  });

  testWidgets('batch payment method, multi-field edit, and delete work', (
    tester,
  ) async {
    final food = buildCategory(uuid: 'cat-food', name: '餐饮', icon: '🍜');
    final alipay = buildPaymentMethod(uuid: 'pm-alipay', name: '支付宝');
    final wechat = buildPaymentMethod(uuid: 'pm-wechat', name: '微信');
    final tx1 = buildTransaction(
      uuid: 'tx-1',
      categoryUuid: food.uuid,
      paymentMethodUuid: alipay.uuid,
      merchant: '便利店',
    );

    List<FinanceTransaction>? saved;
    List<FinanceTransaction>? deleted;
    await tester.pumpWidget(
      wrapLedger(
        transactions: [tx1],
        categories: {food.uuid: food},
        paymentMethods: {alipay.uuid: alipay, wechat.uuid: wechat},
        onBatchSave: (updated) async {
          saved = updated;
        },
        onBatchDelete: (items) async {
          deleted = items;
        },
      ),
    );

    await tester.longPress(find.text('便利店'));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('finance-ledger-batch-payment-method')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('微信'));
    await tester.pumpAndSettle();

    expect(saved, isNotNull);
    expect(saved!.single.paymentMethodUuid, wechat.uuid);

    await tester.longPress(find.text('便利店'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('finance-ledger-batch-edit')));
    await tester.pumpAndSettle();

    await tester.tap(find.text('修改备注'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, '备注内容（留空则清空）'),
      '导入修正',
    );
    await tester.tap(find.text('应用修改'));
    await tester.pumpAndSettle();

    expect(saved!.single.note, '导入修正');

    await tester.longPress(find.text('便利店'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('finance-ledger-batch-delete')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '删除'));
    await tester.pumpAndSettle();

    expect(deleted, isNotNull);
    expect(deleted!.single.uuid, tx1.uuid);
  });
}
