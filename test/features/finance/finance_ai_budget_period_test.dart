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

  test('最近一笔支出跨月查询仍能找到最近的实际账单', () async {
    final now = DateTime(2026, 10, 1, 12);
    await FinanceStorage.saveTransaction(
      FinanceTransaction(
        uuid: 'recent-income',
        type: FinanceTransactionType.income,
        amountMinor: 7000,
        transactionDate: '2026-09-20',
        occurredAt: DateTime(2026, 9, 20, 12).millisecondsSinceEpoch,
      ),
    );
    await FinanceStorage.saveTransaction(
      FinanceTransaction(
        uuid: 'future-expense',
        amountMinor: 9000,
        categoryUuid: 'test-food',
        transactionDate: '2026-10-01',
        occurredAt: DateTime.utc(2026, 10, 1, 13).millisecondsSinceEpoch,
        timezoneOffsetMinutes: 0,
        createdAt: now.millisecondsSinceEpoch,
      ),
    );

    final expenseContext = await FinanceAiContextService.buildContext(
      userMessage: '最近一笔支出是哪笔',
      now: now,
    );
    final incomeContext = await FinanceAiContextService.buildContext(
      userMessage: '最近一笔收入是哪笔',
      now: now,
    );
    final recentExpensesContext = await FinanceAiContextService.buildContext(
      userMessage: '最近两笔支出是哪两笔',
      now: now,
    );

    expect(expenseContext, contains('[transactionId: today]'));
    expect(expenseContext, isNot(contains('[transactionId: future-expense]')));
    expect(expenseContext, contains('查询范围: 全部历史中最近1笔已发生账单'));
    expect(incomeContext, contains('[transactionId: recent-income]'));
    expect(recentExpensesContext, contains('[transactionId: today]'));
    expect(recentExpensesContext, contains('[transactionId: earlier-september]'));
    expect(recentExpensesContext, isNot(contains('[transactionId: august]')));
    expect(
      FinanceAiContextService.buildContextInjectionSummary(
        userMessage: '最近一笔支出是哪笔',
        now: now,
      ),
      '记账最近1笔账单',
    );
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

  test('本星期和上个星期查询使用完整自然周', () async {
    final now = DateTime(2026, 9, 2, 23, 59);
    await FinanceStorage.saveTransaction(
      FinanceTransaction(
        uuid: 'previous-calendar-week',
        amountMinor: 400,
        transactionDate: '2026-08-27',
        occurredAt: DateTime(2026, 8, 27, 12).millisecondsSinceEpoch,
      ),
    );

    final currentWeekContext = await FinanceAiContextService.buildContext(
      userMessage: '本星期支出多少',
      now: now,
    );
    final previousWeekContext = await FinanceAiContextService.buildContext(
      userMessage: '上个星期支出了多少',
      now: now,
    );

    for (final phrase in [
      '本周',
      '本星期',
      '本礼拜',
      '这周',
      '这星期',
      '这个星期',
      '这礼拜',
      '这个礼拜',
    ]) {
      final range = FinanceAiContextService.resolveDateRange(
        '$phrase支出',
        now: now,
      );
      expect(dateKey(range.from), '2026-08-31', reason: phrase);
      expect(dateKey(range.to), '2026-09-07', reason: phrase);
    }
    expect(currentWeekContext, contains('[transactionId: august]'));
    expect(currentWeekContext, contains('净支出 ¥60.00'));

    for (final phrase in [
      '上周',
      '上一周',
      '上星期',
      '上一星期',
      '上个星期',
      '上一个星期',
      '上礼拜',
      '上个礼拜',
      '上一个礼拜',
    ]) {
      final range = FinanceAiContextService.resolveDateRange(
        '$phrase支出',
        now: now,
      );
      expect(dateKey(range.from), '2026-08-24', reason: phrase);
      expect(dateKey(range.to), '2026-08-31', reason: phrase);
    }
    expect(
      previousWeekContext,
      contains('[transactionId: previous-calendar-week]'),
    );
    expect(previousWeekContext, isNot(contains('[transactionId: august]')));
    expect(previousWeekContext, contains('净支出 ¥4.00'));
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

  test('最近半个月查询按滚动十五个自然日跨月取账单', () async {
    final now = DateTime(2026, 9, 2, 23, 59);
    final range = FinanceAiContextService.resolveDateRange(
      '最近半个月支出',
      now: now,
    );
    final context = await FinanceAiContextService.buildContext(
      userMessage: '最近半个月支出多少',
      now: now,
    );

    expect(dateKey(range.from), '2026-08-19');
    expect(dateKey(range.to), '2026-09-03');
    expect(context, contains('[transactionId: august]'));
    expect(context, contains('净支出 ¥60.00'));
    for (final phrase in ['近半个月', '过去半个月', '最近半月']) {
      final alias = FinanceAiContextService.resolveDateRange(
        '$phrase支出',
        now: now,
      );
      expect(dateKey(alias.from), '2026-08-19', reason: phrase);
      expect(dateKey(alias.to), '2026-09-03', reason: phrase);
    }
  });

  test('过去两周和最近三星期查询按完整滚动范围跨月取账单', () async {
    final now = DateTime(2026, 9, 2, 23, 59);
    final twoWeekRange = FinanceAiContextService.resolveDateRange(
      '过去两周支出',
      now: now,
    );
    final twoWeekContext = await FinanceAiContextService.buildContext(
      userMessage: '过去两周支出多少',
      now: now,
    );
    final threeWeekRange = FinanceAiContextService.resolveDateRange(
      '最近3星期支出',
      now: now,
    );
    final oneWeekRange = FinanceAiContextService.resolveDateRange(
      '过去一个星期支出',
      now: now,
    );
    final oneWeekContext = await FinanceAiContextService.buildContext(
      userMessage: '过去一个星期支出多少',
      now: now,
    );

    expect(dateKey(twoWeekRange.from), '2026-08-20');
    expect(dateKey(twoWeekRange.to), '2026-09-03');
    expect(twoWeekContext, contains('[transactionId: august]'));
    expect(twoWeekContext, contains('[transactionId: earlier-september]'));
    expect(twoWeekContext, contains('[transactionId: today]'));
    expect(twoWeekContext, contains('净支出 ¥60.00'));
    expect(dateKey(threeWeekRange.from), '2026-08-13');
    expect(dateKey(threeWeekRange.to), '2026-09-03');
    expect(dateKey(oneWeekRange.from), '2026-08-27');
    expect(dateKey(oneWeekRange.to), '2026-09-03');
    expect(oneWeekContext, contains('[transactionId: august]'));
    expect(oneWeekContext, contains('[transactionId: earlier-september]'));
    expect(oneWeekContext, contains('[transactionId: today]'));
    expect(oneWeekContext, contains('净支出 ¥60.00'));
  });

  test('最近几天未指定天数时要求澄清且不注入本月账单', () async {
    final now = DateTime(2026, 9, 2, 23, 59);
    final context = await FinanceAiContextService.buildContext(
      userMessage: '最近几天支出多少',
      now: now,
    );
    final preview = FinanceAiContextService.buildContextInjectionSummary(
      userMessage: '最近几天支出多少',
      now: now,
    );

    expect(context, contains('日期范围不明确'));
    expect(context, contains('请先询问用户具体天数'));
    expect(context, isNot(contains('[transactionId: earlier-september]')));
    expect(context, isNot(contains('[transactionId: today]')));
    expect(preview, '记账查询范围待确认');

    for (final phrase in [
      '过去几天',
      '近几个星期',
      '这几周',
      '最近几个月',
    ]) {
      expect(
        FinanceAiContextService.shouldInjectFor('$phrase支出多少'),
        isFalse,
        reason: phrase,
      );
    }

    final explicitRange = FinanceDateRange(
      DateTime(2026, 8, 31),
      DateTime(2026, 9, 3),
    );
    final overriddenContext = await FinanceAiContextService.buildContext(
      userMessage: '最近几天支出多少',
      dateRangeOverride: explicitRange,
      now: now,
    );
    expect(overriddenContext, isNot(contains('日期范围不明确')));
    expect(overriddenContext, contains('[transactionId: august]'));
    expect(overriddenContext, contains('[transactionId: earlier-september]'));
    expect(overriddenContext, contains('净支出 ¥60.00'));
  });

  test('比较多个相对账期时不静默选择其中一段', () async {
    final now = DateTime(2026, 9, 2, 23, 59);

    for (final query in [
      '比较最近7天和上周的账单支出明细',
      '比较上个月和上周的账单支出明细',
      '比较本季度和上季度的账单支出明细',
      '比较去年和今年的账单支出明细',
      '比较2026-08-01至2026-08-31和上周的账单支出明细',
    ]) {
      expect(FinanceAiContextService.shouldInjectFor(query), isFalse);
      expect(
        await FinanceAiContextService.buildContext(
          userMessage: query,
          now: now,
        ),
        isEmpty,
        reason: query,
      );
      expect(
        FinanceAiContextService.buildContextInjectionSummary(
          userMessage: query,
          now: now,
        ),
        isNull,
        reason: query,
      );
    }
  });

  test('自选账期覆盖提示中的多个相对账期', () async {
    const query = '比较最近7天和上周的账单支出明细';
    final selectedRange = FinanceDateRange(
      DateTime(2026, 8, 1),
      DateTime(2026, 9, 1),
    );
    final now = DateTime(2026, 9, 2, 23, 59);

    final context = await FinanceAiContextService.buildContext(
      userMessage: query,
      dateRangeOverride: selectedRange,
      now: now,
    );
    final preview = FinanceAiContextService.buildContextInjectionSummary(
      userMessage: query,
      dateRangeOverride: selectedRange,
      now: now,
    );

    expect(context, contains('查询范围: 2026-08-01 至 2026-08-31'));
    expect(context, contains('[transactionId: august]'));
    expect(context, isNot(contains('[transactionId: today]')));
    expect(preview, contains('记账明细 2026-08-01 至 2026-08-31'));
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

  test('中文年月日查询按单日过滤并拒绝无效日期', () async {
    final now = DateTime(2026, 9, 2, 23, 59);
    final range = FinanceAiContextService.resolveDateRange(
      '2026年9月2日支出',
      now: now,
    );
    final context = await FinanceAiContextService.buildContext(
      userMessage: '2026年9月2日支出多少',
      now: now,
    );

    expect(dateKey(range.from), '2026-09-02');
    expect(dateKey(range.to), '2026-09-03');
    expect(context, contains('[transactionId: today]'));
    expect(context, isNot(contains('[transactionId: earlier-september]')));

    final previousYearRange = FinanceAiContextService.resolveDateRange(
      '去年9月2日支出',
      now: now,
    );
    expect(dateKey(previousYearRange.from), '2025-09-02');
    expect(dateKey(previousYearRange.to), '2025-09-03');

    final chineseNumeralRange = FinanceAiContextService.resolveDateRange(
      '九月二十一日支出',
      now: now,
    );
    expect(dateKey(chineseNumeralRange.from), '2026-09-21');
    expect(dateKey(chineseNumeralRange.to), '2026-09-22');

    expect(
      FinanceAiContextService.shouldInjectFor('2026年9月31日支出多少'),
      isFalse,
    );
    expect(
      FinanceAiContextService.shouldInjectFor('九月三十一日支出多少'),
      isFalse,
    );
    expect(
      await FinanceAiContextService.buildContext(
        userMessage: '2026年9月31日支出多少',
        now: now,
      ),
      isEmpty,
    );
    for (final query in [
      '19月2日支出多少',
      '119月2日支出多少',
      '9月230日支出多少',
      '十三月二日支出多少',
      '九月二百日支出多少',
      '13月账单多少',
      '十三月账单多少',
    ]) {
      expect(
        FinanceAiContextService.shouldInjectFor(query),
        isFalse,
        reason: query,
      );
      expect(
        await FinanceAiContextService.buildContext(
          userMessage: query,
          now: now,
        ),
        isEmpty,
        reason: query,
      );
    }
  });

  test('显式日期范围包含首尾日期', () async {
    for (final (query, expectedFrom, expectedTo) in [
      ('2026-09-01至2026-09-30支出多少', '2026-09-01', '2026-10-01'),
      ('9月1日到9月30日支出多少', '2026-09-01', '2026-10-01'),
      ('9月1日至10日支出多少', '2026-09-01', '2026-09-11'),
      ('9月1日至十日支出多少', '2026-09-01', '2026-09-11'),
      ('9月28日至3日支出多少', '2026-09-28', '2026-10-04'),
      ('2026-09-01至2日支出多少', '2026-09-01', '2026-09-03'),
      ('去年9月1日至9月30日支出多少', '2025-09-01', '2025-10-01'),
      ('12月20日到1月5日支出多少', '2026-12-20', '2027-01-06'),
    ]) {
      final range = FinanceAiContextService.resolveDateRange(
        query,
        now: DateTime(2026, 10, 2),
      );
      expect(dateKey(range.from), expectedFrom, reason: query);
      expect(dateKey(range.to), expectedTo, reason: query);
      expect(
        FinanceAiContextService.shouldInjectFor(query),
        isTrue,
        reason: query,
      );
    }

    for (final query in [
      '2026-09-01和2026-09-30支出多少',
      '2026-09-01至2026-09-31支出多少',
      '2026年2月1日至31日支出多少',
    ]) {
      expect(
        FinanceAiContextService.shouldInjectFor(query),
        isFalse,
        reason: query,
      );
    }

    final context = await FinanceAiContextService.buildContext(
      userMessage: '2026-09-01至2日支出多少',
      now: DateTime(2026, 9, 2, 23, 59),
    );
    expect(context, contains('[transactionId: earlier-september]'));
    expect(context, contains('[transactionId: today]'));
    expect(context, isNot(contains('[transactionId: august]')));
  });

  test('显式月份范围包含起止月并正确跨年', () async {
    for (final (query, expectedFrom, expectedTo) in [
      ('2026年8月到9月支出多少', '2026-08-01', '2026-10-01'),
      ('2026-08到2026-09支出多少', '2026-08-01', '2026-10-01'),
      ('去年12月到1月支出多少', '2025-12-01', '2026-02-01'),
    ]) {
      final range = FinanceAiContextService.resolveDateRange(
        query,
        now: DateTime(2026, 10, 2),
      );
      expect(dateKey(range.from), expectedFrom, reason: query);
      expect(dateKey(range.to), expectedTo, reason: query);
      expect(
        FinanceAiContextService.shouldInjectFor(query),
        isTrue,
        reason: query,
      );
    }

    expect(
      FinanceAiContextService.shouldInjectFor('2026年8月和2026年9月支出多少'),
      isFalse,
    );
    final context = await FinanceAiContextService.buildContext(
      userMessage: '2026年8月到9月支出多少',
      now: DateTime(2026, 9, 2, 23, 59),
    );
    expect(context, contains('[transactionId: august]'));
    expect(context, contains('[transactionId: earlier-september]'));
    expect(context, contains('[transactionId: today]'));
  });

  test('明确日期和月份的年份由各自的日期前缀决定', () {
    final now = DateTime(2026, 9, 2);
    final dateRange = FinanceAiContextService.resolveDateRange(
      '去年9月2日支出，前年同期是多少',
      now: now,
    );
    final monthRange = FinanceAiContextService.resolveDateRange(
      '去年9月支出，前年同期是多少',
      now: now,
    );

    expect(dateKey(dateRange.from), '2025-09-02');
    expect(dateKey(dateRange.to), '2025-09-03');
    expect(dateKey(monthRange.from), '2025-09-01');
    expect(dateKey(monthRange.to), '2025-10-01');
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

  test('数字年份账单查询按完整自然年过滤', () async {
    final now = DateTime(2026, 10, 2, 12);
    for (final transaction in [
      FinanceTransaction(
        uuid: 'numeric-year-2025',
        amountMinor: 1200,
        transactionDate: '2025-05-15',
        occurredAt: DateTime(2025, 5, 15, 12).millisecondsSinceEpoch,
      ),
      FinanceTransaction(
        uuid: 'numeric-year-2025-h2',
        amountMinor: 800,
        transactionDate: '2025-08-15',
        occurredAt: DateTime(2025, 8, 15, 12).millisecondsSinceEpoch,
      ),
    ]) {
      await FinanceStorage.saveTransaction(transaction);
    }

    final range = FinanceAiContextService.resolveDateRange(
      '2025年支出',
      now: now,
    );
    final context = await FinanceAiContextService.buildContext(
      userMessage: '2025年支出多少',
      now: now,
    );
    final secondHalfRange = FinanceAiContextService.resolveDateRange(
      '2025年下半年支出',
      now: now,
    );
    final secondHalfContext = await FinanceAiContextService.buildContext(
      userMessage: '2025年下半年支出多少',
      now: now,
    );
    final followUp = FinanceAiContextService.buildContextInjectionSummary(
      userMessage: '2025年呢',
      conversationContext: '查看记账支出情况',
      previousUserMessage: '2026年9月支出多少',
      now: now,
    );

    expect(dateKey(range.from), '2025-01-01');
    expect(dateKey(range.to), '2026-01-01');
    expect(context, contains('[transactionId: numeric-year-2025]'));
    expect(context, contains('[transactionId: numeric-year-2025-h2]'));
    expect(context, isNot(contains('[transactionId: today]')));
    expect(dateKey(secondHalfRange.from), '2025-07-01');
    expect(dateKey(secondHalfRange.to), '2026-01-01');
    expect(
      secondHalfContext,
      contains('[transactionId: numeric-year-2025-h2]'),
    );
    expect(
      secondHalfContext,
      isNot(contains('[transactionId: numeric-year-2025]')),
    );
    expect(
      FinanceAiContextService.shouldInjectFor('2025年支出多少'),
      isTrue,
    );
    expect(followUp, '记账明细 2025-01-01 至 2025-12-31');
    for (final query in [
      '0000年支出多少',
      '0000年第二季度支出多少',
      '0000年下半年支出多少',
    ]) {
      expect(FinanceAiContextService.shouldInjectFor(query), isFalse);
    }
  });

  test('去年同期查询沿用上一条账单的月份范围', () async {
    final now = DateTime(2026, 10, 2, 12);
    for (final transaction in [
      FinanceTransaction(
        uuid: 'same-period-2025-september',
        amountMinor: 900,
        transactionDate: '2025-09-15',
        occurredAt: DateTime(2025, 9, 15, 12).millisecondsSinceEpoch,
      ),
      FinanceTransaction(
        uuid: 'same-period-2025-may',
        amountMinor: 500,
        transactionDate: '2025-05-15',
        occurredAt: DateTime(2025, 5, 15, 12).millisecondsSinceEpoch,
      ),
    ]) {
      await FinanceStorage.saveTransaction(transaction);
    }

    final context = await FinanceAiContextService.buildContext(
      userMessage: '去年同期支出多少',
      conversationContext: '查看记账支出情况',
      previousUserMessage: '今年9月支出多少',
      now: now,
    );
    final preview = FinanceAiContextService.buildContextInjectionSummary(
      userMessage: '去年同期呢',
      conversationContext: '查看记账支出情况',
      previousUserMessage: '今年9月支出多少',
      now: now,
    );
    final missingPeriodContext = await FinanceAiContextService.buildContext(
      userMessage: '去年同期支出多少',
      conversationContext: '查看记账支出情况',
      now: now,
    );
    final missingPeriodPreview =
        FinanceAiContextService.buildContextInjectionSummary(
          userMessage: '去年同期呢',
          conversationContext: '查看记账支出情况',
          now: now,
        );

    expect(context, contains('查询范围: 2025-09-01 至 2025-09-30'));
    expect(context, contains('[transactionId: same-period-2025-september]'));
    expect(context, isNot(contains('[transactionId: same-period-2025-may]')));
    expect(preview, '记账明细 2025-09-01 至 2025-09-30');
    expect(missingPeriodContext, contains('“同期”需要参考上一条具体账期'));
    expect(missingPeriodPreview, '记账查询范围待确认');
  });

  test('近半年和近几个月查询使用滚动自然月范围', () async {
    final now = DateTime(2026, 10, 2, 12);
    for (final (query, expectedFrom) in [
      ('近半年支出', '2026-04-02'),
      ('过去6个月支出', '2026-04-02'),
      ('近两个月支出', '2026-08-02'),
      ('最近三个月支出', '2026-07-02'),
      ('近3个月支出', '2026-07-02'),
      ('近13月支出', '2025-09-02'),
      ('近13个月支出', '2025-09-02'),
      ('近十三个月支出', '2025-09-02'),
      ('近三十六个月支出', '2023-10-02'),
      ('近一年支出', '2025-10-02'),
      ('过去两年支出', '2024-10-02'),
    ]) {
      final range = FinanceAiContextService.resolveDateRange(
        query,
        now: now,
      );
      expect(dateKey(range.from), expectedFrom, reason: query);
      expect(dateKey(range.to), '2026-10-03', reason: query);
      expect(
        FinanceAiContextService.shouldInjectFor(query),
        isTrue,
        reason: query,
      );
    }

    for (final query in [
      '近37个月支出多少',
      '近100个月支出多少',
      '近三十七个月支出多少',
      '近一百个月支出多少',
      '近11年支出多少',
      '近100年支出多少',
      '近十一年支出多少',
      '近一百年支出多少',
    ]) {
      expect(
        FinanceAiContextService.shouldInjectFor(query),
        isFalse,
        reason: query,
      );
      expect(
        await FinanceAiContextService.buildContext(
          userMessage: query,
          now: now,
        ),
        isEmpty,
        reason: query,
      );
    }

    expect(
      FinanceAiContextService.buildContextInjectionSummary(
        userMessage: '近半年支出',
        now: now,
      ),
      '记账明细 2026-04-02 至 2026-10-02',
    );
    expect(
      FinanceAiContextService.buildContextInjectionSummary(
        userMessage: '近一年支出',
        now: now,
      ),
      '记账明细 2025-10-02 至 2026-10-02',
    );
    final context = await FinanceAiContextService.buildContext(
      userMessage: '近半年支出',
      now: now,
    );
    expect(context, contains('查询范围: 2026-04-02 至 2026-10-02（含首尾日期）'));
    expect(context, contains('[transactionId: today]'));

    final monthEndRange = FinanceAiContextService.resolveDateRange(
      '近6个月支出',
      now: DateTime(2026, 8, 31),
    );
    expect(dateKey(monthEndRange.from), '2026-02-28');
  });

  test('效率分析不会注入无关月份的账单数据', () async {
    for (final query in [
      '分析我上个月的效率',
      '分析我9月的效率',
      '分析我2026年9月的效率',
    ]) {
      expect(
        FinanceAiContextService.shouldInjectFor(query),
        isFalse,
        reason: query,
      );
      expect(
        FinanceAiContextService.buildContextInjectionSummary(
          userMessage: query,
          now: DateTime(2026, 10, 2),
        ),
        isNull,
        reason: query,
      );
      expect(
        await FinanceAiContextService.buildContext(
          userMessage: query,
          now: DateTime(2026, 10, 2),
        ),
        isEmpty,
        reason: query,
      );
    }
  });

  test('跟进问题不会把上一条无效账单范围回退为当前月', () async {
    const userMessage = '明细呢？';
    const previousUserMessage = '查询2026-08-31至2026-08-01支出';
    final context = await FinanceAiContextService.buildContext(
      userMessage: userMessage,
      conversationContext: '查询记账支出情况',
      previousUserMessage: previousUserMessage,
      now: DateTime(2026, 9, 2, 12),
    );
    final summary = FinanceAiContextService.buildContextInjectionSummary(
      userMessage: userMessage,
      conversationContext: '查询记账支出情况',
      previousUserMessage: previousUserMessage,
      now: DateTime(2026, 9, 2, 12),
    );

    expect(context, isEmpty);
    expect(summary, isNull);

    final selectedRange = FinanceDateRange(
      DateTime(2026, 8, 1),
      DateTime(2026, 9, 1),
    );
    final selectedContext = await FinanceAiContextService.buildContext(
      userMessage: userMessage,
      conversationContext: '查询记账支出情况',
      previousUserMessage: previousUserMessage,
      dateRangeOverride: selectedRange,
      now: DateTime(2026, 9, 2, 12),
    );
    final selectedSummary =
        FinanceAiContextService.buildContextInjectionSummary(
          userMessage: userMessage,
          conversationContext: '查询记账支出情况',
          previousUserMessage: previousUserMessage,
          dateRangeOverride: selectedRange,
          now: DateTime(2026, 9, 2, 12),
        );

    expect(selectedContext, contains('查询范围: 2026-08-01 至 2026-08-31'));
    expect(selectedContext, contains('[transactionId: august]'));
    expect(selectedSummary, '记账明细 2026-08-01 至 2026-08-31');
  });

  test('AI 查询付款方式余额时提供快照及之后的账户流水', () async {
    final snapshotAt = DateTime(2026, 9, 1, 10);
    await db.insert(
      'finance_payment_methods',
      FinancePaymentMethod(uuid: 'ai-card', name: 'AI银行卡').toMap(),
    );
    await db.insert(
      'finance_payment_methods',
      FinancePaymentMethod(uuid: 'ai-card-no-snapshot', name: '备用银行卡')
          .toMap(),
    );
    await FinanceStorage.saveBudget(
      FinanceBudget(
        uuid: 'ai-card-snapshot',
        monthKey: '2026-09',
        paymentMethodUuid: 'ai-card',
        amountMinor: 10000,
        balanceSnapshotAt: snapshotAt.millisecondsSinceEpoch,
        createdAt: snapshotAt.millisecondsSinceEpoch,
        updatedAt: snapshotAt.millisecondsSinceEpoch,
      ),
      balanceSnapshotAt: snapshotAt.millisecondsSinceEpoch,
    );
    final expense = FinanceTransaction(
      uuid: 'ai-card-expense',
      amountMinor: 2000,
      paymentMethodUuid: 'ai-card',
      transactionDate: '2026-09-02',
      occurredAt: DateTime(2026, 9, 2, 12).millisecondsSinceEpoch,
    );
    for (final transaction in [
      expense,
      FinanceTransaction(
        uuid: 'ai-card-income',
        type: FinanceTransactionType.income,
        amountMinor: 5000,
        paymentMethodUuid: 'ai-card',
        transactionDate: '2026-09-02',
        occurredAt: DateTime(2026, 9, 2, 11).millisecondsSinceEpoch,
      ),
      FinanceTransaction(
        uuid: 'ai-card-refund',
        type: FinanceTransactionType.refund,
        amountMinor: 500,
        paymentMethodUuid: 'ai-card',
        transactionDate: '2026-09-02',
        occurredAt: DateTime(2026, 9, 2, 13).millisecondsSinceEpoch,
        relatedTransactionUuid: expense.uuid,
      ),
    ]) {
      await FinanceStorage.saveTransaction(transaction);
    }

    final context = await FinanceAiContextService.buildContext(
      userMessage: '银行卡余额多少',
      now: DateTime(2026, 9, 2, 23, 59),
    );

    expect(context, contains('- AI银行卡: ¥135.00'));
    expect(context, contains('- 备用银行卡: 未录入余额快照，无法确定实际余额'));
    expect(context, contains('本期结余不代表付款方式实际余额'));

    final colloquialContext = await FinanceAiContextService.buildContext(
      userMessage: '银行卡还有多少钱',
      now: DateTime(2026, 9, 2, 23, 59),
    );
    expect(colloquialContext, contains('- AI银行卡: ¥135.00'));
    expect(
      FinanceAiContextService.buildContextInjectionSummary(
        userMessage: '银行卡还有多少钱',
        now: DateTime(2026, 9, 2),
      ),
      contains('付款方式实际余额'),
    );

    final budgetBalanceContext = await FinanceAiContextService.buildContext(
      userMessage: '本月预算余额多少',
      now: DateTime(2026, 9, 2, 23, 59),
    );
    expect(budgetBalanceContext, contains('预算（2026-09，整月）'));
    expect(
      budgetBalanceContext,
      isNot(contains('付款方式实际余额（截至')),
    );
    expect(
      FinanceAiContextService.buildContextInjectionSummary(
        userMessage: '本月预算余额多少',
        now: DateTime(2026, 9, 2),
      ),
      isNot(contains('付款方式实际余额')),
    );
  });

  test('历史月份的银行卡余额按账期结束时刻计算', () async {
    final augustSnapshotAt = DateTime(2026, 8, 1);
    final septemberSnapshotAt = DateTime(2026, 9, 1);
    await db.insert(
      'finance_payment_methods',
      FinancePaymentMethod(uuid: 'historical-card', name: '历史银行卡').toMap(),
    );
    for (final (uuid, monthKey, amountMinor, snapshotAt) in [
      (
        'historical-card-august-snapshot',
        '2026-08',
        10000,
        augustSnapshotAt,
      ),
      (
        'historical-card-september-snapshot',
        '2026-09',
        6000,
        septemberSnapshotAt,
      ),
    ]) {
      await FinanceStorage.saveBudget(
        FinanceBudget(
          uuid: uuid,
          monthKey: monthKey,
          paymentMethodUuid: 'historical-card',
          amountMinor: amountMinor,
          balanceSnapshotAt: snapshotAt.millisecondsSinceEpoch,
          createdAt: snapshotAt.millisecondsSinceEpoch,
          updatedAt: snapshotAt.millisecondsSinceEpoch,
        ),
        balanceSnapshotAt: snapshotAt.millisecondsSinceEpoch,
      );
    }
    final augustExpenseAt = DateTime(2026, 8, 10, 12);
    await FinanceStorage.saveTransaction(
      FinanceTransaction(
        uuid: 'historical-card-august-expense',
        amountMinor: 2000,
        paymentMethodUuid: 'historical-card',
        transactionDate: '2026-08-10',
        occurredAt: augustExpenseAt.millisecondsSinceEpoch,
        createdAt: augustExpenseAt.millisecondsSinceEpoch,
      ),
    );

    final now = DateTime(2026, 9, 2, 23, 59);
    final currentContext = await FinanceAiContextService.buildContext(
      userMessage: '银行卡余额多少',
      now: now,
    );
    final historicalContext = await FinanceAiContextService.buildContext(
      userMessage: '上个月银行卡余额多少',
      now: now,
    );

    expect(currentContext, contains('- 历史银行卡: ¥60.00'));
    expect(historicalContext, contains('- 历史银行卡: ¥80.00'));
    expect(
      historicalContext,
      contains('付款方式实际余额（截至 2026-08-31 23:59:59.999'),
    );
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

  test('财务 AI 前后相对日查询使用单日范围', () {
    final now = DateTime(2026, 10, 2, 12);
    final cases = [
      ('大前天', '2026-09-29'),
      ('前天', '2026-09-30'),
      ('昨天', '2026-10-01'),
      ('今天', '2026-10-02'),
      ('明天', '2026-10-03'),
      ('后天', '2026-10-04'),
      ('大后天', '2026-10-05'),
    ];

    for (final (phrase, expectedDay) in cases) {
      final range = FinanceAiContextService.resolveDateRange(
        '$phrase支出',
        now: now,
      );
      final expectedEnd = financeCalendarDayOffset(
        DateTime.parse(expectedDay),
        1,
      );
      expect(dateKey(range.from), expectedDay, reason: phrase);
      expect(dateKey(range.to), dateKey(expectedEnd), reason: phrase);
    }

    final followUp = FinanceAiContextService.buildContextInjectionSummary(
      userMessage: '明天呢',
      conversationContext: '查看记账支出情况',
      previousUserMessage: '上个月支出多少',
      now: now,
    );
    expect(followUp, '记账明细 2026-10-03 至 2026-10-03');
  });

  test('财务 AI 上上期查询不会匹配上一期', () {
    final now = DateTime(2026, 10, 2, 12);
    final cases = [
      ('上上周', '2026-09-14', '2026-09-21'),
      ('上上星期', '2026-09-14', '2026-09-21'),
      ('上上个星期', '2026-09-14', '2026-09-21'),
      ('上上礼拜', '2026-09-14', '2026-09-21'),
      ('上上个礼拜', '2026-09-14', '2026-09-21'),
      ('上上个月', '2026-08-01', '2026-09-01'),
      ('上上月', '2026-08-01', '2026-09-01'),
      ('上上季度', '2026-04-01', '2026-07-01'),
      ('上上个季度', '2026-04-01', '2026-07-01'),
    ];

    for (final (phrase, expectedFrom, expectedTo) in cases) {
      final range = FinanceAiContextService.resolveDateRange(
        '$phrase支出',
        now: now,
      );
      expect(dateKey(range.from), expectedFrom, reason: phrase);
      expect(dateKey(range.to), expectedTo, reason: phrase);
    }
  });

  test('上一个月查询使用上个自然月并排除本月账单', () async {
    final now = DateTime(2026, 9, 2, 23, 59);
    final range = FinanceAiContextService.resolveDateRange(
      '上一个月支出',
      now: now,
    );
    final context = await FinanceAiContextService.buildContext(
      userMessage: '上一个月支出多少',
      now: now,
    );

    expect(dateKey(range.from), '2026-08-01');
    expect(dateKey(range.to), '2026-09-01');
    expect(context, contains('查询范围: 2026-08-01 至 2026-08-31'));
    expect(context, contains('[transactionId: august]'));
    expect(context, isNot(contains('[transactionId: earlier-september]')));
    expect(context, isNot(contains('[transactionId: today]')));
    expect(context, contains('净支出 ¥10.00'));
  });

  test('前一个月查询使用上个自然月并排除本月账单', () async {
    final now = DateTime(2026, 9, 2, 23, 59);
    final range = FinanceAiContextService.resolveDateRange(
      '前一个月支出',
      now: now,
    );
    final context = await FinanceAiContextService.buildContext(
      userMessage: '前一个月支出多少',
      now: now,
    );

    expect(dateKey(range.from), '2026-08-01');
    expect(dateKey(range.to), '2026-09-01');
    expect(context, contains('[transactionId: august]'));
    expect(context, isNot(contains('[transactionId: earlier-september]')));
    expect(context, isNot(contains('[transactionId: today]')));
    expect(context, contains('净支出 ¥10.00'));
  });

  test('前一个星期和前一个礼拜查询上一完整自然周', () async {
    final now = DateTime(2026, 9, 2, 23, 59);
    await FinanceStorage.saveTransaction(
      FinanceTransaction(
        uuid: 'previous-calendar-week-prefix-alias',
        amountMinor: 400,
        transactionDate: '2026-08-27',
        occurredAt: DateTime(2026, 8, 27, 12).millisecondsSinceEpoch,
      ),
    );

    for (final phrase in ['前一个星期', '前一个礼拜']) {
      final range = FinanceAiContextService.resolveDateRange(
        '$phrase支出',
        now: now,
      );
      final context = await FinanceAiContextService.buildContext(
        userMessage: '$phrase支出了多少',
        now: now,
      );

      expect(dateKey(range.from), '2026-08-24', reason: phrase);
      expect(dateKey(range.to), '2026-08-31', reason: phrase);
      expect(
        context,
        contains('[transactionId: previous-calendar-week-prefix-alias]'),
      );
      expect(context, isNot(contains('[transactionId: august]')));
      expect(context, isNot(contains('[transactionId: earlier-september]')));
      expect(context, contains('净支出 ¥4.00'));
    }
  });

  test('前一个季度和前一季度查询上一完整自然季度', () async {
    final now = DateTime(2026, 10, 2, 12);
    for (final phrase in ['前一个季度', '前一季度']) {
      final range = FinanceAiContextService.resolveDateRange(
        '$phrase支出',
        now: now,
      );
      final context = await FinanceAiContextService.buildContext(
        userMessage: '$phrase支出多少',
        now: now,
      );

      expect(dateKey(range.from), '2026-07-01', reason: phrase);
      expect(dateKey(range.to), '2026-10-01', reason: phrase);
      expect(context, contains('查询范围: 2026-07-01 至 2026-09-30'));
      expect(context, contains('[transactionId: august]'));
      expect(context, contains('[transactionId: earlier-september]'));
      expect(context, contains('[transactionId: today]'));
      expect(context, contains('净支出 ¥60.00'));
    }
  });

  test('明确季度账单查询按指定年份和季度过滤', () async {
    final now = DateTime(2026, 10, 2, 12);
    for (final item in [
      FinanceTransaction(
        uuid: 'explicit-2026-q2',
        amountMinor: 500,
        transactionDate: '2026-05-15',
        occurredAt: DateTime(2026, 5, 15, 12).millisecondsSinceEpoch,
      ),
      FinanceTransaction(
        uuid: 'explicit-2025-q3',
        amountMinor: 700,
        transactionDate: '2025-08-15',
        occurredAt: DateTime(2025, 8, 15, 12).millisecondsSinceEpoch,
      ),
    ]) {
      await FinanceStorage.saveTransaction(item);
    }

    final secondQuarterRange = FinanceAiContextService.resolveDateRange(
      '2026年第2季度支出',
      now: now,
    );
    final secondQuarterContext = await FinanceAiContextService.buildContext(
      userMessage: '2026年第2季度支出多少',
      now: now,
    );
    final previousYearRange = FinanceAiContextService.resolveDateRange(
      '去年第三季度支出',
      now: now,
    );
    final previousYearContext = await FinanceAiContextService.buildContext(
      userMessage: '去年第三季度支出多少',
      now: now,
    );

    expect(dateKey(secondQuarterRange.from), '2026-04-01');
    expect(dateKey(secondQuarterRange.to), '2026-07-01');
    expect(secondQuarterContext, contains('[transactionId: explicit-2026-q2]'));
    expect(secondQuarterContext, isNot(contains('[transactionId: today]')));
    expect(dateKey(previousYearRange.from), '2025-07-01');
    expect(dateKey(previousYearRange.to), '2025-10-01');
    expect(previousYearContext, contains('[transactionId: explicit-2025-q3]'));
    expect(
      previousYearContext,
      isNot(contains('[transactionId: explicit-2026-q2]')),
    );

    for (final (phrase, expectedFrom, expectedTo) in [
      ('2026年第二季度', '2026-04-01', '2026-07-01'),
      ('今年第一季度', '2026-01-01', '2026-04-01'),
      ('前年第四季度', '2024-10-01', '2025-01-01'),
      ('明年第四季度', '2027-10-01', '2028-01-01'),
    ]) {
      final range = FinanceAiContextService.resolveDateRange(
        '$phrase支出',
        now: now,
      );
      expect(dateKey(range.from), expectedFrom, reason: phrase);
      expect(dateKey(range.to), expectedTo, reason: phrase);
      expect(
        FinanceAiContextService.shouldInjectFor('$phrase支出多少'),
        isTrue,
        reason: phrase,
      );
    }

    expect(FinanceAiContextService.shouldInjectFor('2026年第5季度支出多少'), isFalse);
    expect(
      FinanceAiContextService.shouldInjectFor('今年第二季度和去年第三季度支出对比'),
      isFalse,
    );
    expect(
      await FinanceAiContextService.buildContext(
        userMessage: '2026年第5季度支出多少',
        now: now,
      ),
      isEmpty,
    );
  });

  test('下个月账单查询返回计划账单而不是本月记录', () async {
    final now = DateTime(2026, 9, 2, 23, 59);
    final futureAt = DateTime(2026, 10, 5, 12);
    await FinanceStorage.saveTransaction(
      FinanceTransaction(
        uuid: 'next-month-plan',
        amountMinor: 2500,
        transactionDate: '2026-10-05',
        occurredAt: futureAt.millisecondsSinceEpoch,
        createdAt: now.millisecondsSinceEpoch,
        merchant: '下月计划账单',
      ),
    );

    final context = await FinanceAiContextService.buildContext(
      userMessage: '下个月支出有哪些',
      now: now,
    );

    for (final phrase in ['下月', '下个月', '下一个月']) {
      final range = FinanceAiContextService.resolveDateRange(
        '$phrase支出',
        now: now,
      );
      expect(dateKey(range.from), '2026-10-01', reason: phrase);
      expect(dateKey(range.to), '2026-11-01', reason: phrase);
    }
    expect(context, contains('查询范围: 2026-10-01 至 2026-10-31'));
    expect(context, contains('- 待发生 | [transactionId: next-month-plan]'));
    expect(context, isNot(contains('[transactionId: earlier-september]')));
    expect(context, isNot(contains('[transactionId: today]')));
  });

  test('下周计划账单查询使用下一完整自然周', () async {
    final now = DateTime(2026, 9, 2, 23, 59);
    final futureAt = DateTime(2026, 9, 8, 12);
    await FinanceStorage.saveTransaction(
      FinanceTransaction(
        uuid: 'next-week-plan',
        amountMinor: 1800,
        transactionDate: '2026-09-08',
        occurredAt: futureAt.millisecondsSinceEpoch,
        createdAt: now.millisecondsSinceEpoch,
        merchant: '下周计划账单',
      ),
    );

    for (final phrase in [
      '下周',
      '下星期',
      '下个星期',
      '下一个星期',
      '下礼拜',
      '下个礼拜',
      '下一个礼拜',
    ]) {
      final range = FinanceAiContextService.resolveDateRange(
        '$phrase支出',
        now: now,
      );
      expect(dateKey(range.from), '2026-09-07', reason: phrase);
      expect(dateKey(range.to), '2026-09-14', reason: phrase);
    }

    final context = await FinanceAiContextService.buildContext(
      userMessage: '下周支出有哪些',
      now: now,
    );
    expect(context, contains('查询范围: 2026-09-07 至 2026-09-13'));
    expect(context, contains('- 待发生 | [transactionId: next-week-plan]'));
    expect(context, isNot(contains('[transactionId: today]')));
  });

  test('下季度计划账单查询使用下一个完整自然季度', () async {
    final now = DateTime(2026, 10, 2, 12);
    final futureAt = DateTime(2027, 1, 5, 12);
    await FinanceStorage.saveTransaction(
      FinanceTransaction(
        uuid: 'next-quarter-plan',
        amountMinor: 3200,
        transactionDate: '2027-01-05',
        occurredAt: futureAt.millisecondsSinceEpoch,
        createdAt: now.millisecondsSinceEpoch,
        merchant: '下季度计划账单',
      ),
    );

    for (final phrase in ['下季度', '下个季度', '下一个季度']) {
      final range = FinanceAiContextService.resolveDateRange(
        '$phrase支出',
        now: now,
      );
      expect(dateKey(range.from), '2027-01-01', reason: phrase);
      expect(dateKey(range.to), '2027-04-01', reason: phrase);
    }

    final context = await FinanceAiContextService.buildContext(
      userMessage: '下季度支出有哪些',
      now: now,
    );
    expect(context, contains('查询范围: 2027-01-01 至 2027-03-31'));
    expect(context, contains('- 待发生 | [transactionId: next-quarter-plan]'));
    expect(context, isNot(contains('[transactionId: today]')));
  });

  test('明年下一年和来年查询返回下一自然年的计划账单', () async {
    final now = DateTime(2026, 10, 2, 12);
    final futureAt = DateTime(2027, 5, 12, 12);
    await FinanceStorage.saveTransaction(
      FinanceTransaction(
        uuid: 'next-year-plan',
        amountMinor: 4100,
        transactionDate: '2027-05-12',
        occurredAt: futureAt.millisecondsSinceEpoch,
        createdAt: now.millisecondsSinceEpoch,
        merchant: '明年计划账单',
      ),
    );

    for (final phrase in ['明年', '下年', '下一年', '来年']) {
      final range = FinanceAiContextService.resolveDateRange(
        '$phrase支出',
        now: now,
      );
      expect(dateKey(range.from), '2027-01-01', reason: phrase);
      expect(dateKey(range.to), '2028-01-01', reason: phrase);
    }

    final context = await FinanceAiContextService.buildContext(
      userMessage: '明年支出有哪些',
      now: now,
    );
    expect(context, contains('查询范围: 2027-01-01 至 2027-12-31'));
    expect(context, contains('- 待发生 | [transactionId: next-year-plan]'));
    expect(context, isNot(contains('[transactionId: today]')));
  });

  test('今年下半年查询只包含下半年而不混入上半年账单', () async {
    final now = DateTime(2026, 10, 2, 12);
    await FinanceStorage.saveTransaction(
      FinanceTransaction(
        uuid: 'first-half-transaction',
        amountMinor: 5000,
        transactionDate: '2026-03-12',
        occurredAt: DateTime(2026, 3, 12, 12).millisecondsSinceEpoch,
        createdAt: DateTime(2026, 3, 12, 12).millisecondsSinceEpoch,
      ),
    );

    final range = FinanceAiContextService.resolveDateRange(
      '今年下半年支出',
      now: now,
    );
    final context = await FinanceAiContextService.buildContext(
      userMessage: '今年下半年支出多少',
      now: now,
    );

    expect(dateKey(range.from), '2026-07-01');
    expect(dateKey(range.to), '2027-01-01');
    expect(context, contains('查询范围: 2026-07-01 至 2026-12-31'));
    expect(context, contains('[transactionId: august]'));
    expect(context, isNot(contains('[transactionId: first-half-transaction]')));

    for (final (phrase, expectedFrom, expectedTo) in [
      ('下半年', '2026-07-01', '2027-01-01'),
      ('今年上半年', '2026-01-01', '2026-07-01'),
      ('明年上半年', '2027-01-01', '2027-07-01'),
      ('去年下半年', '2025-07-01', '2026-01-01'),
    ]) {
      final alias = FinanceAiContextService.resolveDateRange(
        '$phrase支出',
        now: now,
      );
      expect(dateKey(alias.from), expectedFrom, reason: phrase);
      expect(dateKey(alias.to), expectedTo, reason: phrase);
    }
  });
}
