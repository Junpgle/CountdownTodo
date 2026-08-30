import 'package:countdown_todo/features/finance/services/finance_ai_context_service.dart';
import 'package:countdown_todo/services/ai_todo_context_builder.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026, 8, 30, 15, 20);

  test('普通的一句话记账不会注入已有账单隐私', () {
    expect(
      FinanceAiContextService.shouldInjectFor('今天午餐花了 28 元'),
      isFalse,
    );
    expect(
      FinanceAiContextService.shouldInjectFor('请统计本月支出'),
      isTrue,
    );
    expect(
      FinanceAiContextService.shouldInjectFor('把昨天那笔改成 30 元'),
      isTrue,
    );
  });

  test('按用户表达解析日、周、月和年度范围', () {
    final today = FinanceAiContextService.resolveDateRange('今天的账单', now: now);
    expect(today.from, DateTime(2026, 8, 30));
    expect(today.to, DateTime(2026, 8, 31));

    final week = FinanceAiContextService.resolveDateRange('查看本周支出', now: now);
    expect(week.from, DateTime(2026, 8, 24));
    expect(week.to, DateTime(2026, 8, 31));

    final month = FinanceAiContextService.resolveDateRange('统计上月账单', now: now);
    expect(month.from, DateTime(2026, 7));
    expect(month.to, DateTime(2026, 8));

    final year = FinanceAiContextService.resolveDateRange('查看今年收入', now: now);
    expect(year.from, DateTime(2026));
    expect(year.to, DateTime(2027));
  });

  test('动作协议覆盖查询、修改、删除和真实ID安全规则', () {
    final prompt =
        AiTodoContextBuilder.buildActionProtocolPrompt('查询本月账单并统计餐饮支出');

    expect(prompt, contains('finance_summary'));
    expect(prompt, contains('finance_list'));
    expect(prompt, contains('update_finance'));
    expect(prompt, contains('delete_finance'));
    expect(prompt, contains('[FINANCE_ACTION_START]'));
    expect(prompt, contains('绝不编造transactionId'));
  });
}
