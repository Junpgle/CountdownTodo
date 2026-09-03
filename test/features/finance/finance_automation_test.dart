import 'package:countdown_todo/features/finance/models/finance_models.dart';
import 'package:countdown_todo/features/finance/services/finance_automation_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  FinanceRecurringRule monthlyRule({
    int day = 31,
    String startDate = '2026-01-01',
  }) {
    return FinanceRecurringRule(
      uuid: 'rule-monthly',
      name: '房租',
      amountMinor: 250000,
      dayOfMonth: day,
      startDate: startDate,
    );
  }

  test('月末不存在指定日期时会落在当月最后一天', () {
    final due = FinanceAutomationService.dueDateFor(
      monthlyRule(),
      2026,
      2,
    );

    expect(due, DateTime(2026, 2, 28, 9));
  });

  test('年度规则只在目标月份发生', () {
    final rule = FinanceRecurringRule(
      uuid: 'rule-yearly',
      name: '保险',
      amountMinor: 120000,
      frequency: FinanceRecurringFrequency.yearly,
      monthOfYear: 6,
      dayOfMonth: 31,
      startDate: '2026-01-01',
    );

    expect(FinanceAutomationService.dueDateFor(rule, 2026, 5), isNull);
    expect(
      FinanceAutomationService.dueDateFor(rule, 2026, 6),
      DateTime(2026, 6, 30, 9),
    );
  });

  test('开始日期会过滤掉之前的周期', () {
    final rule = monthlyRule(day: 1, startDate: '2026-08-15');
    final due = FinanceAutomationService.dueDateFor(rule, 2026, 8);

    expect(due, isNull);
  });

  test('未来窗口按到期时间排序，并为同一规则生成稳定周期键', () {
    final first = FinanceRecurringRule(
      uuid: 'rule-first',
      name: '月费',
      amountMinor: 1000,
      dayOfMonth: 28,
      startDate: '2026-01-01',
    );
    final second = FinanceRecurringRule(
      uuid: 'rule-second',
      name: '月薪',
      type: FinanceTransactionType.income,
      amountMinor: 100000,
      dayOfMonth: 30,
      startDate: '2026-01-01',
    );
    final dues = FinanceAutomationService.upcoming(
      rules: [second, first],
      now: DateTime(2026, 8, 20),
      limit: DateTime(2026, 9, 5),
    );

    expect(dues.map((item) => item.rule.uuid), ['rule-first', 'rule-second']);
    expect(dues.first.periodKey, '2026-08');
    expect(
      FinanceAutomationService.notificationIdFor('rule-first', '2026-08'),
      FinanceAutomationService.notificationIdFor('rule-first', '2026-08'),
    );
  });

  test('自动化来源和频率标签可读', () {
    expect(FinanceEntrySource.automation.label, '自动');
    expect(FinanceRecurringFrequency.yearly.label, '每年');
  });

  test('恢复运行时按顺序补齐遗漏周期', () {
    final rule = monthlyRule(day: 15, startDate: '2026-01-01')
      ..lastGeneratedPeriod = '2026-05';
    final dues = FinanceAutomationService.missedDuesFor(
      rule,
      now: DateTime(2026, 8, 20),
    );

    expect(
      dues.map((item) => item.periodKey),
      ['2026-06', '2026-07', '2026-08'],
    );
  });

  test('无生成标记的历史规则只生成当前周期', () {
    final rule = monthlyRule(day: 15, startDate: '2000-01-01');
    final dues = FinanceAutomationService.missedDuesFor(
      rule,
      now: DateTime(2026, 8, 20),
    );

    expect(dues.map((item) => item.periodKey), ['2026-08']);
  });

  test('长期未运行的规则最多补齐最近十二个周期', () {
    final rule = monthlyRule(day: 15, startDate: '2000-01-01')
      ..lastGeneratedPeriod = '2000-01';
    final dues = FinanceAutomationService.missedDuesFor(
      rule,
      now: DateTime(2026, 8, 20),
    );

    expect(dues, hasLength(12));
    expect(dues.first.periodKey, '2025-09');
    expect(dues.last.periodKey, '2026-08');
  });
}
