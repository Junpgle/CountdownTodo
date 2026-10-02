import 'package:countdown_todo/features/finance/models/finance_models.dart';
import 'package:countdown_todo/features/finance/services/finance_repository.dart';
import 'package:countdown_todo/features/finance/services/finance_text_parser.dart';
import 'package:countdown_todo/services/storage/app_settings_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('新交易默认保存创建时的本机时区', () {
    final createdAt = DateTime.now().millisecondsSinceEpoch;
    final localDate = dateKey(DateTime.fromMillisecondsSinceEpoch(createdAt));
    final transaction = FinanceTransaction(
      amountMinor: 100,
      transactionDate: localDate,
      occurredAt: createdAt,
    );

    expect(
      transaction.timezoneOffsetMinutes,
      DateTime.fromMillisecondsSinceEpoch(createdAt).timeZoneOffset.inMinutes,
    );
    expect(dateKey(transaction.occurrenceLocalTime!), localDate);
  });

  test('分期发生时刻使用记录时区，跨日期后仍按实际时刻扣减', () {
    final eventAt = DateTime.utc(2026, 10, 1, 10, 30).millisecondsSinceEpoch;
    final transaction = FinanceTransaction(
      amountMinor: 2000,
      transactionDate: '2026-10-02',
      occurredAt: eventAt,
      timezoneOffsetMinutes: 840,
      createdAt: DateTime.utc(2026, 9, 15).millisecondsSinceEpoch,
    );
    expect(dateKey(transaction.occurrenceLocalTime!), '2026-10-02');
    expect(transaction.occurrenceLocalTime!.hour, 0);
    expect(
      transaction.balanceEventAt(
        snapshotAt: DateTime.utc(2026, 9, 30).millisecondsSinceEpoch,
      ),
      eventAt,
    );
    expect(
      FinanceTransaction.fromMap(transaction.toMap()).balanceEventAt(),
      eventAt,
    );
  });

  test('历史账单缺少发生时间时未来日期不会提前扣减', () {
    final future = DateTime(2027, 1, 2);
    final transaction = FinanceTransaction.fromMap({
      'amount_minor': 100,
      'transaction_date': dateKey(future),
      'created_at': DateTime(2026, 10, 1).millisecondsSinceEpoch,
    });
    expect(transaction.balanceEventAt(), future.millisecondsSinceEpoch);
  });

  test('预算截止汇总排除尚未发生的同日和未来日期账单', () {
    final asOf = DateTime(2026, 10, 2, 12);
    final summary = FinanceSummary.fromTransactions(
      [
        FinanceTransaction(
          uuid: 'budget-before-cutoff',
          amountMinor: 40000,
          transactionDate: '2026-10-02',
          occurredAt: DateTime(2026, 10, 2, 11).millisecondsSinceEpoch,
        ),
        FinanceTransaction(
          uuid: 'budget-after-cutoff',
          amountMinor: 20000,
          transactionDate: '2026-10-02',
          occurredAt: DateTime(2026, 10, 2, 13).millisecondsSinceEpoch,
        ),
        FinanceTransaction(
          uuid: 'budget-next-day',
          amountMinor: 150000,
          transactionDate: '2026-10-03',
          occurredAt: DateTime(2026, 10, 3, 12).millisecondsSinceEpoch,
        ),
      ],
      asOfAt: asOf.millisecondsSinceEpoch,
    );

    expect(summary.expenseMinor, 40000);
    expect(summary.transactionCount, 1);
  });

  test('未来发生时刻不因记录日期与保存时区不一致而提前计入余额', () {
    final createdAt = DateTime.utc(2026, 10, 1, 16, 30);
    final occurredAt = createdAt.add(const Duration(minutes: 1));
    final transaction = FinanceTransaction(
      amountMinor: 100,
      transactionDate: '2026-10-02',
      occurredAt: occurredAt.millisecondsSinceEpoch,
      timezoneOffsetMinutes: 0,
      createdAt: createdAt.millisecondsSinceEpoch,
    );

    expect(
      transaction.balanceEventAt(snapshotAt: createdAt.millisecondsSinceEpoch),
      occurredAt.millisecondsSinceEpoch,
    );
  });

  test('已录入的历史日期账单不回溯修改付款余额', () {
    final createdAt = DateTime.utc(2026, 10, 2);
    final transaction = FinanceTransaction(
      amountMinor: 100,
      transactionDate: '2026-10-01',
      occurredAt: createdAt.millisecondsSinceEpoch,
      timezoneOffsetMinutes: 0,
      createdAt: createdAt.millisecondsSinceEpoch,
    );

    expect(transaction.balanceEventAt(), createdAt.millisecondsSinceEpoch);
  });

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

    test('付款余额可录入零，普通账单仍拒绝零', () {
      expect(parseFinanceAmount('0', allowZero: true), 0);
      expect(parseFinanceAmount('0.00', allowZero: true), 0);
      expect(parseFinanceAmount('0'), isNull);
    });

    test('金额上限在整数边界内精确解析和显示', () {
      expect(parseFinanceAmount('90071992547409.91'), maxFinanceAmountMinor);
      expect(parseFinanceAmount('90071992547409.92'), isNull);
      expect(parseFinanceAmount('100000000000000000'), isNull);
      expect(
        formatFinanceAmount(maxFinanceAmountMinor),
        '¥90,071,992,547,409.91',
      );
    });

    test('AI 识别草稿金额也保持精确并拒绝越界值', () {
      expect(
        FinanceEntryDraft.fromJson({'amount': '90071992547409.91'}).amountMinor,
        maxFinanceAmountMinor,
      );
      expect(
        FinanceEntryDraft.fromJson({'amount': '100000000000000000'})
            .amountMinor,
        0,
      );
      expect(
        FinanceEntryDraft.fromJson({'amount_minor': maxFinanceAmountMinor + 1})
            .amountMinor,
        0,
      );
    });
  });

  test('自然语言快速记账不会把商品数量拆成金额', () {
    final drafts = FinanceTextParser.parseQuickEntries(
      '买了2个苹果，共20元；买了3个橙子，共30元',
      now: DateTime(2026, 10, 2),
    );

    expect(drafts.map((draft) => draft.amountMinor).toList(), [2000, 3000]);
  });

  test('自然语言快速记账拒绝不存在的明确日期', () {
    final now = DateTime(2026, 10, 2);

    expect(
      FinanceTextParser.parseQuickEntries('2026-02-30 午餐20元', now: now),
      isEmpty,
    );
    expect(
      FinanceTextParser.parseQuickEntries('2月30日 午餐20元', now: now),
      isEmpty,
    );
    expect(
      FinanceTextParser.parseQuickEntries('2026-02-28 午餐20元', now: now)
          .single
          .transactionDate,
      '2026-02-28',
    );
    expect(
      FinanceTextParser.parseQuickEntries('午餐20元', now: now)
          .single
          .transactionDate,
      '2026-10-02',
    );
  });

  test('流式AI回复隐藏完整和未完成的记账协议块', () {
    expect(
      FinanceTextParser.cleanStreamingAssistantContent(
        '已识别账单\n[FINANCE_START]\n{"type":"income"}',
      ),
      '已识别账单',
    );
    expect(
      FinanceTextParser.cleanStreamingAssistantContent(
        '已识别账单\n[FINANCE_START]\n[]\n[FINANCE_END]\n请核对后保存',
      ),
      '已识别账单\n\n请核对后保存',
    );
    expect(
      FinanceTextParser.cleanStreamingAssistantContent(
        '[FINANCE_ACTION_START]',
      ),
      isEmpty,
    );
  });

  test('AI 简写 FN 协议会生成待确认收入草案并从回复正文隐藏', () {
    const response = '''
[FN_START] {"type":"income","amount":90,"date":"2026-09-30","note":"兼职收入，已到账"} [FN_END]
已识别为兼职收入，请核对后保存。
''';

    final drafts = FinanceTextParser.extractAssistantDrafts(response);

    expect(drafts, hasLength(1));
    expect(drafts.single.type, FinanceTransactionType.income);
    expect(drafts.single.amountMinor, 9000);
    expect(drafts.single.transactionDate, '2026-09-30');
    expect(
      FinanceTextParser.cleanAssistantContent(response),
      '已识别为兼职收入，请核对后保存。',
    );
    expect(
      FinanceTextParser.cleanStreamingAssistantContent(
        '[FN_START] {"type":"income","amount":90',
      ),
      isEmpty,
    );
  });

  test('快速记账区分金额千位逗号与多笔账单分隔符', () {
    final now = DateTime(2026, 10, 2);
    final groupedAmount = FinanceTextParser.parseQuickEntries(
      '午餐1,234.56元',
      now: now,
    );

    expect(groupedAmount, hasLength(1));
    expect(groupedAmount.single.amountMinor, 123456);
    expect(
      FinanceTextParser.parseOneSentence('午餐12,34元', now: now),
      isNull,
    );
  });

  test('分期和贷款本金拒绝超出跨平台安全范围的金额', () {
    expect(
      () => FinanceInstallmentCalculator.split(
        totalMinor: maxFinanceAmountMinor + 1,
        count: 2,
        startDate: DateTime(2026, 9),
      ),
      throwsArgumentError,
    );
    expect(
      () => FinanceLoanCalculator.generate(
        principalMinor: maxFinanceAmountMinor + 1,
        annualInterestRateBps: 0,
        termMonths: 1,
        startDate: DateTime(2026, 9),
        repaymentDay: 1,
      ),
      throwsArgumentError,
    );
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

  test('旧交易缺少发生时刻时保留未记录状态', () {
    final legacy = FinanceTransaction(
      amountMinor: 100,
      transactionDate: '2026-08-27',
      createdAt: 1787832000000,
    ).toMap()
      ..remove('occurred_at');

    final restored = FinanceTransaction.fromMap(legacy);

    expect(restored.occurredAt, isNull);
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

  test('付款方式月额度使用独立范围并可在 SQLite/JSON 字段间往返', () {
    final original = FinanceBudget(
      uuid: 'payment-budget-1',
      monthKey: '2026-08',
      paymentMethodUuid: 'payment-card',
      amountMinor: 30000,
    );

    final restored = FinanceBudget.fromMap(original.toJson());

    expect(restored.paymentMethodUuid, 'payment-card');
    expect(restored.isPaymentMethod, isTrue);
    expect(restored.isOverall, isFalse);
    expect(
      FinanceBudget.stableUuid(
        '2026-08',
        null,
        paymentMethodUuid: 'payment-card',
      ),
      isNot(FinanceBudget.stableUuid('2026-08', null)),
    );
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

  test('已加载的交易列表可以直接生成概览汇总', () {
    final summary = FinanceRepository.summarizeTransactions([
      FinanceTransaction(
        uuid: 'summary-income',
        type: FinanceTransactionType.income,
        amountMinor: 10000,
        transactionDate: '2026-09-01',
        categoryUuid: 'salary',
      ),
      FinanceTransaction(
        uuid: 'summary-expense',
        amountMinor: 5000,
        transactionDate: '2026-09-02',
        categoryUuid: 'food',
      ),
      FinanceTransaction(
        uuid: 'summary-refund',
        type: FinanceTransactionType.refund,
        amountMinor: 1200,
        transactionDate: '2026-09-03',
        categoryUuid: 'food',
      ),
    ]);

    expect(summary.incomeMinor, 10000);
    expect(summary.expenseMinor, 5000);
    expect(summary.refundMinor, 1200);
    expect(summary.netExpenseMinor, 3800);
    expect(summary.expenseByCategory['food'], 3800);
    expect(summary.expenseByDate['2026-09-02'], 5000);
    expect(summary.expenseByDate['2026-09-03'], -1200);
  });

  test('付款方式净扣减按支出扣除退款并忽略收入', () {
    final spending = FinanceRepository.summarizePaymentMethodSpending([
      FinanceTransaction(
        uuid: 'card-expense',
        amountMinor: 10000,
        paymentMethodUuid: 'payment-card',
        transactionDate: '2026-09-01',
      ),
      FinanceTransaction(
        uuid: 'card-refund',
        type: FinanceTransactionType.refund,
        amountMinor: 2500,
        paymentMethodUuid: 'payment-card',
        transactionDate: '2026-09-02',
      ),
      FinanceTransaction(
        uuid: 'wallet-refund',
        type: FinanceTransactionType.refund,
        amountMinor: 4000,
        paymentMethodUuid: 'payment-wallet',
        transactionDate: '2026-09-03',
      ),
      FinanceTransaction(
        uuid: 'card-income',
        type: FinanceTransactionType.income,
        amountMinor: 9000,
        paymentMethodUuid: 'payment-card',
        transactionDate: '2026-09-04',
      ),
    ]);

    expect(spending, {'payment-card': 7500, 'payment-wallet': -4000});
  });

  test('付款方式余额按收入和退款增加、支出减少', () {
    final changes = FinanceRepository.summarizePaymentMethodBalanceChanges([
      FinanceTransaction(
        uuid: 'card-expense',
        amountMinor: 10000,
        paymentMethodUuid: 'payment-card',
        transactionDate: '2026-09-01',
      ),
      FinanceTransaction(
        uuid: 'card-refund',
        type: FinanceTransactionType.refund,
        amountMinor: 2500,
        paymentMethodUuid: 'payment-card',
        transactionDate: '2026-09-02',
      ),
      FinanceTransaction(
        uuid: 'card-income',
        type: FinanceTransactionType.income,
        amountMinor: 9000,
        paymentMethodUuid: 'payment-card',
        transactionDate: '2026-09-03',
      ),
      FinanceTransaction(
        uuid: 'unassigned-income',
        type: FinanceTransactionType.income,
        amountMinor: 5000,
        transactionDate: '2026-09-03',
      ),
    ]);

    expect(changes, {'payment-card': 1500});
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

  test('默认细分类使用父分类 UUID，并能生成可读路径', () {
    final parent = FinanceCategory.fromMap(
      FinanceDefaults.categories.firstWhere(
        (item) => item['uuid'] == 'finance-system-category-food',
      ),
    );
    final child = FinanceCategory.fromMap(
      FinanceDefaults.categories.firstWhere(
        (item) => item['uuid'] == 'finance-system-category-food-milk-tea',
      ),
    );

    expect(child.parentUuid, parent.uuid);
    expect(
      financeCategoryDisplayName(child, [parent, child]),
      '餐饮 - 奶茶',
    );
    expect(
      FinanceDefaults.categories
          .where((item) => item['parent_uuid'] != null)
          .every((item) => FinanceDefaults.categories.any(
                (parent) => parent['uuid'] == item['parent_uuid'],
              )),
      isTrue,
    );
  });

  test('餐饮默认分类包含网购小类', () {
    final onlineShopping = FinanceDefaults.categories.firstWhere(
      (item) => item['uuid'] == 'finance-system-category-food-online-shopping',
    );

    expect(onlineShopping['name'], '网购');
    expect(
      onlineShopping['parent_uuid'],
      'finance-system-category-food',
    );
    expect(onlineShopping['type'], 'expense');
  });

  test('分类图标自定义标记会进入本地映射与云同步载荷', () {
    final category = FinanceCategory(
      uuid: 'finance-system-category-food',
      name: '餐饮',
      icon: '🥗',
      isSystem: true,
      iconCustomized: true,
      nameCustomized: true,
    );

    final map = category.toMap();
    expect(map['icon'], '🥗');
    expect(map['icon_customized'], 1);
    expect(map['name_customized'], 1);
    expect(FinanceCategory.fromMap(map).iconCustomized, isTrue);
    expect(FinanceCategory.fromMap(map).nameCustomized, isTrue);
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
