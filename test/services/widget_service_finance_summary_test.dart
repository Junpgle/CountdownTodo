import 'package:countdown_todo/features/finance/models/finance_models.dart';
import 'package:countdown_todo/services/widget_service_io.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('记账小组件汇总不计入未来账单，最近一笔取已发生记录', () {
    final now = DateTime(2026, 10, 2, 12);
    final transactions = [
      FinanceTransaction(
        uuid: 'widget-recent-past',
        amountMinor: 4000,
        transactionDate: '2026-10-02',
        occurredAt: DateTime(2026, 10, 2, 10).millisecondsSinceEpoch,
        createdAt: DateTime(2026, 10, 2, 10).millisecondsSinceEpoch,
        merchant: '已发生午餐',
      ),
      FinanceTransaction(
        uuid: 'widget-future-expense',
        amountMinor: 9000,
        transactionDate: '2026-10-02',
        occurredAt: DateTime(2026, 10, 2, 13).millisecondsSinceEpoch,
        createdAt: now.millisecondsSinceEpoch,
        merchant: '未来晚餐',
      ),
    ];

    final summary = WidgetService.financeWidgetSummaryForTransactions(
      now: now,
      transactions: transactions,
    );

    expect(summary.incomeMinor, 0);
    expect(summary.netExpenseMinor, 4000);
    expect(summary.balanceMinor, -4000);
    expect(summary.transactionCount, 1);
    expect(summary.latestTitle, '已发生午餐');
    expect(summary.latestAmountMinor, 4000);
    expect(summary.latestDate, '2026-10-02');
  });
}
