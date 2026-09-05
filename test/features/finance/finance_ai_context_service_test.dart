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
}
