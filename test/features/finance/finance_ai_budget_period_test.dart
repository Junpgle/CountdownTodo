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

  test('过去七天查询按滚动自然日跨月取账单', () async {
    final range = FinanceAiContextService.resolveDateRange(
      '过去7天支出',
      now: DateTime(2026, 9, 2, 23, 59),
    );
    final context = await FinanceAiContextService.buildContext(
      userMessage: '过去7天支出多少',
      now: DateTime(2026, 9, 2, 23, 59),
    );

    expect(dateKey(range.from), '2026-08-27');
    expect(dateKey(range.to), '2026-09-03');
    expect(context, contains('[transactionId: august]'));
    expect(context, contains('[transactionId: earlier-september]'));
    expect(context, contains('[transactionId: today]'));
    expect(context, contains('净支出 ¥60.00'));

    final alternate = FinanceAiContextService.resolveDateRange(
      '近一周支出',
      now: DateTime(2026, 9, 2, 23, 59),
    );
    expect(dateKey(alternate.from), '2026-08-27');
    expect(dateKey(alternate.to), '2026-09-03');

    final followUp = FinanceAiContextService.buildContextInjectionSummary(
      userMessage: '过去七天呢',
      conversationContext: '查看记账支出情况',
      previousUserMessage: '本月支出多少',
      now: DateTime(2026, 9, 2),
    );
    expect(followUp, '记账明细 2026-08-27 至 2026-09-02');
  });

  test('本季度和上季度查询分别使用完整自然季度', () async {
    await FinanceStorage.saveTransaction(
      FinanceTransaction(
        uuid: 'last-quarter',
        amountMinor: 4500,
        transactionDate: '2026-06-30',
        occurredAt: DateTime(2026, 6, 30, 12).millisecondsSinceEpoch,
      ),
    );
    final now = DateTime(2026, 9, 2, 23, 59);
    final previousRange = FinanceAiContextService.resolveDateRange(
      '上季度支出',
      now: now,
    );
    final previousContext = await FinanceAiContextService.buildContext(
      userMessage: '上季度支出多少',
      now: now,
    );
    final currentRange = FinanceAiContextService.resolveDateRange(
      '本季度支出',
      now: now,
    );
    final currentContext = await FinanceAiContextService.buildContext(
      userMessage: '本季度支出多少',
      now: now,
    );

    expect(dateKey(previousRange.from), '2026-04-01');
    expect(dateKey(previousRange.to), '2026-07-01');
    expect(previousContext, contains('[transactionId: last-quarter]'));
    expect(previousContext, isNot(contains('[transactionId: today]')));
    expect(previousContext, contains('净支出 ¥45.00'));
    expect(dateKey(currentRange.from), '2026-07-01');
    expect(dateKey(currentRange.to), '2026-10-01');
    expect(currentContext, contains('[transactionId: today]'));
    expect(currentContext, isNot(contains('[transactionId: last-quarter]')));
    expect(currentContext, contains('净支出 ¥60.00'));

    final followUp = FinanceAiContextService.buildContextInjectionSummary(
      userMessage: '上季度呢',
      conversationContext: '查看记账支出情况',
      previousUserMessage: '本月支出多少',
      now: now,
    );
    expect(followUp, '记账明细 2026-04-01 至 2026-06-30');
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

  test('去年账单查询使用上一完整自然年，不默认本月', () async {
    await FinanceStorage.saveTransaction(
      FinanceTransaction(
        uuid: 'last-year',
        amountMinor: 7700,
        transactionDate: '2025-05-12',
        occurredAt: DateTime(2025, 5, 12, 12).millisecondsSinceEpoch,
      ),
    );

    final range = FinanceAiContextService.resolveDateRange(
      '去年支出',
      now: DateTime(2026, 9, 2, 23, 59),
    );
    final context = await FinanceAiContextService.buildContext(
      userMessage: '去年支出多少',
      now: DateTime(2026, 9, 2, 23, 59),
    );

    expect(dateKey(range.from), '2025-01-01');
    expect(dateKey(range.to), '2026-01-01');
    expect(context, contains('[transactionId: last-year]'));
    expect(context, isNot(contains('[transactionId: today]')));
    expect(context, contains('净支出 ¥77.00'));
  });

  test('前年及上一年也按完整自然年解析', () {
    for (final query in ['去年支出', '上一年支出', '前一年支出']) {
      final range = FinanceAiContextService.resolveDateRange(
        query,
        now: DateTime(2026, 9, 2),
      );
      expect(dateKey(range.from), '2025-01-01', reason: query);
      expect(dateKey(range.to), '2026-01-01', reason: query);
    }
    final twoYearsAgo = FinanceAiContextService.resolveDateRange(
      '前年支出',
      now: DateTime(2026, 9, 2),
    );
    expect(dateKey(twoYearsAgo.from), '2024-01-01');
    expect(dateKey(twoYearsAgo.to), '2025-01-01');

    final lastAugust = FinanceAiContextService.resolveDateRange(
      '去年八月支出',
      now: DateTime(2026, 9, 2),
    );
    expect(dateKey(lastAugust.from), '2025-08-01');
    expect(dateKey(lastAugust.to), '2025-09-01');

    final followUp = FinanceAiContextService.buildContextInjectionSummary(
      userMessage: '去年呢',
      conversationContext: '查看记账支出情况',
      previousUserMessage: '本月支出多少',
      now: DateTime(2026, 9, 2),
    );
    expect(followUp, '记账明细 2025-01-01 至 2025-12-31');
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
          categoryUuid: 'context-category-${index % 13}',
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

    expect(context, contains('支出分类汇总（共13类）'));
    expect(context, contains('支出分类仅列出金额最高的12类，另有1类未列出'));
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
