import 'package:countdown_todo/features/finance/models/finance_models.dart';
import 'package:countdown_todo/features/finance/services/finance_repository.dart';
import 'package:countdown_todo/services/storage/app_settings_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
      installmentGroupUuid: 'installment-1',
      installmentIndex: 2,
      installmentCount: 6,
      installmentTotalMinor: 15594,
    );

    final restored = FinanceTransaction.fromMap(original.toJson());

    expect(restored.uuid, original.uuid);
    expect(restored.type, FinanceTransactionType.refund);
    expect(restored.amountMinor, 2599);
    expect(restored.transactionDate, '2026-08-27');
    expect(restored.relatedTransactionUuid, 'transaction-0');
    expect(restored.installmentGroupUuid, 'installment-1');
    expect(restored.installmentLabel, '2/6 期');
    expect(restored.installmentTotalMinor, 15594);
    expect(restored.pendingSync, isTrue);
  });

  test('分期金额按分精确分摊，余数只造成 1 分差异', () {
    final allocations = FinanceInstallmentCalculator.split(
      totalMinor: 10000,
      count: 3,
      startDate: DateTime(2026, 1, 31),
    );

    expect(
      allocations.map((item) => item.amountMinor).toList(),
      [3334, 3333, 3333],
    );
    expect(
      allocations.map((item) => dateKey(item.date)).toList(),
      ['2026-01-31', '2026-02-28', '2026-03-31'],
    );
    expect(
      allocations.fold<int>(0, (sum, item) => sum + item.amountMinor),
      10000,
    );
  });

  test('分期月数和金额范围无效时拒绝生成', () {
    expect(
      () => FinanceInstallmentCalculator.split(
        totalMinor: 100,
        count: 1,
        startDate: DateTime(2026, 1, 1),
      ),
      throwsArgumentError,
    );
    expect(
      () => FinanceInstallmentCalculator.split(
        totalMinor: 2,
        count: 3,
        startDate: DateTime(2026, 1, 1),
      ),
      throwsArgumentError,
    );
  });

  test('贷款利率可在百分比和基点之间往返', () {
    expect(parseFinanceInterestRate('12.5%'), 1250);
    expect(parseFinanceInterestRate('12.50'), 1250);
    expect(parseFinanceInterestRate('100.01'), isNull);
    expect(formatFinanceInterestRate(1250), '12.5%');
    expect(formatFinanceInterestRate(0), '0%');
  });

  test('贷款计算器精确分配本金并处理短月还款日', () {
    final equalPrincipalInterest = FinanceLoanCalculator.generate(
      principalMinor: 1000000,
      annualInterestRateBps: 1200,
      termMonths: 12,
      startDate: DateTime(2026, 1, 31),
      repaymentDay: 31,
    );

    expect(equalPrincipalInterest, hasLength(12));
    expect(equalPrincipalInterest.first.dueDate, '2026-02-28');
    expect(equalPrincipalInterest.last.dueDate, '2027-01-31');
    expect(
      equalPrincipalInterest.fold<int>(
        0,
        (sum, item) => sum + item.principalMinor,
      ),
      1000000,
    );
    expect(equalPrincipalInterest.last.remainingPrincipalMinor, 0);
    expect(
      equalPrincipalInterest.every((item) => item.paymentMinor > 0),
      isTrue,
    );
    expect(
      equalPrincipalInterest.fold<int>(
        0,
        (sum, item) => sum + item.interestMinor,
      ),
      greaterThan(0),
    );

    final equalPrincipal = FinanceLoanCalculator.generate(
      principalMinor: 1000000,
      annualInterestRateBps: 0,
      termMonths: 3,
      startDate: DateTime(2026, 1, 1),
      repaymentDay: 1,
      repaymentMethod: FinanceLoanRepaymentMethod.equalPrincipal,
    );
    expect(
      equalPrincipal.map((item) => item.principalMinor).toList(),
      [333334, 333333, 333333],
    );
    expect(equalPrincipal.first.paymentMinor, greaterThanOrEqualTo(333334));
    expect(equalPrincipal.last.remainingPrincipalMinor, 0);
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
    expect(
      financeCategoryTypeForTransaction(FinanceTransactionType.refund),
      FinanceCategoryType.expense,
    );
    expect(
      financeCategoryTypeForTransaction(FinanceTransactionType.income),
      FinanceCategoryType.income,
    );
  });

  test('预算范围和 CSV 文本使用稳定、安全的表示', () {
    expect(
      FinanceBudget.stableUuid('2026-09', 'category-food'),
      FinanceBudget.stableUuid('2026-09', 'category-food'),
    );
    expect(
      FinanceBudget.stableUuid('2026-09', 'category-food'),
      isNot(FinanceBudget.stableUuid('2026-09', null)),
    );
    expect(sanitizeFinanceCsvText('=HYPERLINK("x")'), '\'=HYPERLINK("x")');
    expect(sanitizeFinanceCsvText(' 午餐'), ' 午餐');
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

  test('记账云同步按账号默认关闭并相互隔离', () async {
    SharedPreferences.setMockInitialValues({});

    expect(
      await AppSettingsStorage.isFinanceCloudSyncEnabled('alice'),
      isFalse,
    );
    await AppSettingsStorage.setFinanceCloudSyncEnabled('alice', true);
    expect(
      await AppSettingsStorage.isFinanceCloudSyncEnabled('alice'),
      isTrue,
    );
    expect(
      await AppSettingsStorage.isFinanceCloudSyncEnabled('bob'),
      isFalse,
    );
  });

}
