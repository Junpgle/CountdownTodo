@TestOn('vm')
library;

import 'package:countdown_todo/features/finance/models/finance_models.dart';
import 'package:countdown_todo/features/finance/services/finance_ai_context_service.dart';
import 'package:countdown_todo/features/finance/services/finance_storage.dart';
import 'package:countdown_todo/services/database_helper.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  late Database db;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(singleInstance: false),
    );
    await DatabaseHelper.ensureFinanceSchema(db);
    FinanceStorage.databaseOverride = db;
    await FinanceStorage.ensureReady();
    for (final month in ['2026-08', '2026-09']) {
      await FinanceStorage.saveBudget(
        FinanceBudget(monthKey: month, amountMinor: 10000),
      );
    }
    for (final item in [
      FinanceTransaction(
        uuid: 'august',
        amountMinor: 1000,
        transactionDate: '2026-08-31',
        occurredAt: DateTime(2026, 8, 31, 12).millisecondsSinceEpoch,
      ),
      FinanceTransaction(
        uuid: 'earlier-september',
        amountMinor: 3000,
        transactionDate: '2026-09-01',
        occurredAt: DateTime(2026, 9, 1, 12).millisecondsSinceEpoch,
      ),
      FinanceTransaction(
        uuid: 'today',
        amountMinor: 2000,
        transactionDate: '2026-09-02',
        occurredAt: DateTime(2026, 9, 2, 12).millisecondsSinceEpoch,
      ),
    ]) {
      await FinanceStorage.saveTransaction(item);
    }
  });
  tearDown(() async {
    FinanceStorage.databaseOverride = null;
    await db.close();
  });

  test('今天明细只包含当天，月预算包含整月支出', () async {
    final context = await FinanceAiContextService.buildContext(
      userMessage: '今天支出和预算还有多少',
      now: DateTime(2026, 9, 2, 23, 59),
    );
    expect(context, contains('整体: 额度 ¥100.00 | 已用 ¥50.00 | 剩余 ¥50.00'));
    expect(context, contains('[transactionId: today]'));
    expect(context, isNot(contains('[transactionId: earlier-september]')));
    expect(context, isNot(contains('[transactionId: august]')));
    expect(context, contains('净支出 ¥20.00'));
  });

  test('跨月周查询分别给出两个自然月预算，不能混用整周支出', () async {
    final context = await FinanceAiContextService.buildContext(
      userMessage: '本周支出和预算还有多少',
      now: DateTime(2026, 9, 2, 23, 59),
    );
    expect(context, contains('整体: 额度 ¥100.00 | 已用 ¥10.00 | 剩余 ¥90.00'));
    expect(context, contains('整体: 额度 ¥100.00 | 已用 ¥50.00 | 剩余 ¥50.00'));
    expect(context, contains('净支出 ¥60.00'));
  });

  test('夏令时回拨日按自然日计算 AI 账单范围和标签', () {
    final today = FinanceAiContextService.resolveDateRange(
      '今天支出',
      now: DateTime(2026, 11, 1, 12),
    );
    expect(dateKey(today.from), '2026-11-01');
    expect(dateKey(today.to), '2026-11-02');
    expect(today.label, '2026-11-01 至 2026-11-01');

    final week = FinanceAiContextService.resolveDateRange(
      '本周支出',
      now: DateTime(2026, 11, 1, 12),
    );
    expect(dateKey(week.from), '2026-10-26');
    expect(dateKey(week.to), '2026-11-02');
    expect(week.label, '2026-10-26 至 2026-11-01');
  });

  test('AI 财务上下文会说明账单和预算明细被截断', () {
    final categories = [
      for (var index = 0; index < 21; index++)
        FinanceCategory(
          uuid: 'context-category-$index',
          name: '上下文分类$index',
        ),
    ];
    final budgets = [
      for (var index = 0; index < 21; index++)
        FinanceBudget(
          uuid: 'context-budget-$index',
          monthKey: '2026-09',
          categoryUuid: 'context-category-$index',
          amountMinor: 10000,
        ),
    ];
    final transactions = [
      for (var index = 0; index < 61; index++)
        FinanceTransaction(
          uuid: 'context-transaction-$index',
          amountMinor: 100,
          transactionDate: dateKey(DateTime(2026, 9, index % 30 + 1)),
          occurredAt: DateTime(
            2026,
            9,
            index % 30 + 1,
            12,
          ).millisecondsSinceEpoch,
        ),
    ];
    final context = FinanceAiContextService.formatContext(
      range: FinanceDateRange(DateTime(2026, 9), DateTime(2026, 10)),
      summary: FinanceSummary.fromTransactions(transactions),
      transactions: transactions,
      categories: categories,
      paymentMethods: const [],
      budgets: budgets,
      budgetSummaries: const {'2026-09': FinanceSummary()},
      asOfAt: DateTime(2026, 10).millisecondsSinceEpoch,
    );

    expect(context, contains('预算条目共21项，当前仅列出前20项，另有1项未展开'));
    expect(context, contains('账单明细共61笔，当前仅列出前60笔'));
    expect(context, contains('其余1笔没有逐笔列出'));
  });

  test('今年查询按实际月份给出预算，账单汇总仍按全年', () async {
    final context = await FinanceAiContextService.buildContext(
      userMessage: '今年支出和预算还有多少',
      now: DateTime(2026, 9, 2, 23, 59),
    );
    expect(context, contains('整体: 额度 ¥100.00 | 已用 ¥10.00 | 剩余 ¥90.00'));
    expect(context, contains('整体: 额度 ¥100.00 | 已用 ¥50.00 | 剩余 ¥50.00'));
    expect(context, contains('净支出 ¥60.00'));
  });
}
