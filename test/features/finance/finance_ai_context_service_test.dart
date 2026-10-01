import 'package:countdown_todo/features/finance/services/finance_ai_context_service.dart';
import 'package:countdown_todo/features/finance/models/finance_models.dart';
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
    expect(
      FinanceAiContextService.shouldInjectCatalogFor('今天午餐花了 28 元'),
      isTrue,
    );
    expect(
      FinanceAiContextService.shouldInjectCatalogFor('请统计本月支出'),
      isFalse,
    );
    expect(
      FinanceAiContextService.shouldInjectCatalogFor('查看本月账单'),
      isFalse,
    );
    expect(
      FinanceAiContextService.shouldInjectCatalogFor('记录一下今天的学习时长'),
      isFalse,
    );
    expect(
      FinanceAiContextService.shouldInjectCatalogFor('把这个待办分类到工作'),
      isFalse,
    );
  });

  test('本地记账目录包含真实UUID并排除归档和删除项目', () {
    final context = FinanceAiContextService.formatCatalogContext(
      categories: [
        FinanceCategory(
          uuid: 'category-coffee',
          name: '咖啡',
          sortOrder: 10,
        ),
        FinanceCategory(
          uuid: 'category-old',
          name: '旧分类',
          isArchived: true,
        ),
      ],
      paymentMethods: [
        FinancePaymentMethod(uuid: 'payment-wechat', name: '微信'),
        FinancePaymentMethod(
          uuid: 'payment-deleted',
          name: '已删除',
          isDeleted: true,
        ),
      ],
    );

    expect(context, contains('categoryUuid=category-coffee'));
    expect(context, contains('categoryName=咖啡'));
    expect(context, contains('paymentMethodUuid=payment-wechat'));
    expect(context, isNot(contains('category-old')));
    expect(context, isNot(contains('payment-deleted')));
    expect(context, contains('UUID只能原样复制'));
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

  test('AI记账上下文将未来账单从实际汇总中排除并标为待发生', () {
    final pastAt = now.subtract(const Duration(hours: 1));
    final futureAt = now.add(const Duration(hours: 1));
    final transactions = [
      FinanceTransaction(
        uuid: 'context-past-expense',
        amountMinor: 4000,
        transactionDate: dateKey(now),
        occurredAt: pastAt.millisecondsSinceEpoch,
        createdAt: pastAt.millisecondsSinceEpoch,
        merchant: '已发生午餐',
      ),
      FinanceTransaction(
        uuid: 'context-future-expense',
        amountMinor: 9000,
        transactionDate: dateKey(now),
        occurredAt: futureAt.millisecondsSinceEpoch,
        createdAt: now.millisecondsSinceEpoch,
        merchant: '计划晚餐',
      ),
    ];
    final asOfAt = now.millisecondsSinceEpoch;
    final context = FinanceAiContextService.formatContext(
      range: FinanceDateRange(
        DateTime(now.year, now.month),
        DateTime(now.year, now.month + 1),
      ),
      summary: FinanceSummary.fromTransactions(
        transactions,
        asOfAt: asOfAt,
      ),
      transactions: transactions,
      categories: const [],
      paymentMethods: const [],
      budgets: const [],
      budgetSummaries: const {},
      asOfAt: asOfAt,
    );

    expect(context, contains('支出 ¥40.00'));
    expect(context, isNot(contains('支出 ¥130.00')));
    expect(
      context,
      contains('待发生 | [transactionId: context-future-expense]'),
    );
    expect(context, contains('已发生午餐'));
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

    final creationPrompt =
        AiTodoContextBuilder.buildActionProtocolPrompt('今天午餐 28 元');
    expect(creationPrompt, contains('categoryUuid'));
  });

  test('finance context resolves an explicit calendar date', () {
    final range = FinanceAiContextService.resolveDateRange(
      '查询2026-09-20账单明细',
      now: DateTime(2026, 10, 1, 12),
    );

    expect(range.from, DateTime(2026, 9, 20));
    expect(range.to, DateTime(2026, 9, 21));
  });

  test('does not inject finance data for an invalid explicit date', () {
    expect(
      FinanceAiContextService.shouldInjectFor('查询2026-02-30账单明细'),
      isFalse,
    );
  });
}
