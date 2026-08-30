import 'package:countdown_todo/features/finance/models/finance_models.dart';
import 'package:countdown_todo/features/finance/services/finance_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('记账金额解析', () {
    test('支持整数和两位小数，并转换为分', () {
      expect(parseFinanceAmount('12'), 1200);
      expect(parseFinanceAmount('12.3'), 1230);
      expect(parseFinanceAmount('12.30'), 1230);
      expect(parseFinanceAmount('1,234.56'), 123456);
    });

    test('拒绝零、负数、字母和超过两位小数', () {
      expect(parseFinanceAmount('0'), isNull);
      expect(parseFinanceAmount('-1'), isNull);
      expect(parseFinanceAmount('12.345'), isNull);
      expect(parseFinanceAmount('1,23'), isNull);
      expect(parseFinanceAmount('abc'), isNull);
    });
  });

  test('交易模型可以在 SQLite/JSON 字段之间往返', () {
    final original = FinanceTransaction(
      uuid: 'transaction-1',
      type: FinanceTransactionType.refund,
      amountMinor: 2599,
      categoryUuid: 'category-1',
      paymentMethodUuid: 'payment-1',
      transactionDate: '2026-08-27',
      merchant: '书店',
      note: '退回一本书',
      relatedTransactionUuid: 'transaction-0',
      pendingSync: true,
    );

    final restored = FinanceTransaction.fromMap(original.toJson());

    expect(restored.uuid, original.uuid);
    expect(restored.type, FinanceTransactionType.refund);
    expect(restored.amountMinor, 2599);
    expect(restored.transactionDate, '2026-08-27');
    expect(restored.relatedTransactionUuid, 'transaction-0');
    expect(restored.pendingSync, isTrue);
  });

  test('预算模型可以在 SQLite/JSON 字段之间往返', () {
    final original = FinanceBudget(
      uuid: 'budget-1',
      monthKey: '2026-08',
      categoryUuid: 'category-food',
      amountMinor: 30000,
      note: '工作日午餐',
    );

    final restored = FinanceBudget.fromMap(original.toJson());

    expect(restored.uuid, 'budget-1');
    expect(restored.monthKey, '2026-08');
    expect(restored.categoryUuid, 'category-food');
    expect(restored.amountMinor, 30000);
    expect(restored.isOverall, isFalse);
    expect(financeMonthKey(DateTime(2026, 8, 27)), '2026-08');
  });

  test('退款会以正向现金流显示，但保留退款类型', () {
    expect(
      formatSignedFinanceAmount(800, FinanceTransactionType.expense),
      '-¥8.00',
    );
    expect(
      formatSignedFinanceAmount(800, FinanceTransactionType.refund),
      '+¥8.00',
    );
  });

  test('汇总会将退款从实际支出中扣除', () {
    const summary = FinanceSummary(
      incomeMinor: 10000,
      expenseMinor: 5000,
      refundMinor: 1200,
    );

    expect(summary.netExpenseMinor, 3800);
    expect(summary.balanceMinor, 6200);
  });

  test('默认分类和付款方式使用稳定 ID', () {
    expect(
      FinanceDefaults.categories.map((item) => item['uuid']).toSet().length,
      FinanceDefaults.categories.length,
    );
    expect(
      FinanceDefaults.paymentMethods.map((item) => item['uuid']).toSet().length,
      FinanceDefaults.paymentMethods.length,
    );
  });
}
