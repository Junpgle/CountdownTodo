import 'package:countdown_todo/features/finance/models/finance_models.dart';
import 'package:countdown_todo/services/timeline_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('时间轴按账单记录时区显示跨日发生时间', () {
    final ledgerDate = DateTime(2026, 10, 2);
    final transaction = FinanceTransaction(
      uuid: 'timeline-cross-timezone',
      amountMinor: 2000,
      transactionDate: dateKey(ledgerDate),
      occurredAt: DateTime.utc(2026, 10, 1, 10, 30).millisecondsSinceEpoch,
      timezoneOffsetMinutes: 14 * 60,
    );

    expect(
      TimelineService.financeTransactionTimestampForDay(
        transaction,
        ledgerDate,
      ),
      DateTime(2026, 10, 2, 0, 30),
    );
  });

  test('时间轴将尚未发生的账单标记为待发生', () {
    final now = DateTime(2026, 10, 2, 12);
    final upcoming = FinanceTransaction(
      uuid: 'timeline-upcoming-bill',
      amountMinor: 3000,
      transactionDate: dateKey(now),
      occurredAt: now.add(const Duration(hours: 2)).millisecondsSinceEpoch,
      createdAt: now.millisecondsSinceEpoch,
    );
    final completed = FinanceTransaction(
      uuid: 'timeline-completed-bill',
      amountMinor: 2000,
      transactionDate: dateKey(now),
      occurredAt: now.subtract(const Duration(hours: 1)).millisecondsSinceEpoch,
      createdAt: now.subtract(const Duration(hours: 1)).millisecondsSinceEpoch,
    );

    expect(
      TimelineService.financeTransactionTitle(upcoming, now: now),
      '待发生 · 支出',
    );
    expect(
      TimelineService.financeTransactionTitle(completed, now: now),
      '记账 · 支出',
    );
  });

  test('时间轴对缺失或与账单日期不匹配的发生时间使用中午占位', () {
    final ledgerDate = DateTime(2026, 10, 2);
    final missingTime = FinanceTransaction.fromMap({
      'uuid': 'timeline-missing-time',
      'amount_minor': 1000,
      'transaction_date': dateKey(ledgerDate),
      'created_at': DateTime(2026, 10, 2, 8).millisecondsSinceEpoch,
    });
    final mismatchedTime = FinanceTransaction(
      uuid: 'timeline-mismatched-time',
      amountMinor: 1000,
      transactionDate: dateKey(ledgerDate),
      occurredAt: DateTime.utc(2026, 10, 1, 10).millisecondsSinceEpoch,
      timezoneOffsetMinutes: 0,
    );

    expect(
      TimelineService.financeTransactionTimestampForDay(
        missingTime,
        ledgerDate,
      ),
      DateTime(2026, 10, 2, 12),
    );
    expect(
      TimelineService.financeTransactionTimestampForDay(
        mismatchedTime,
        ledgerDate,
      ),
      DateTime(2026, 10, 2, 12),
    );
  });

  test('时间轴当前期间的账单汇总排除未来记录，未来期间保留计划记录', () {
    final now = DateTime(2026, 10, 2, 12);
    final pastAt = now.subtract(const Duration(hours: 1));
    final futureAt = now.add(const Duration(hours: 1));
    final currentTransactions = [
      FinanceTransaction(
        uuid: 'timeline-summary-past',
        amountMinor: 4000,
        transactionDate: dateKey(now),
        occurredAt: pastAt.millisecondsSinceEpoch,
        createdAt: pastAt.millisecondsSinceEpoch,
      ),
      FinanceTransaction(
        uuid: 'timeline-summary-future',
        amountMinor: 9000,
        transactionDate: dateKey(now),
        occurredAt: futureAt.millisecondsSinceEpoch,
        createdAt: now.millisecondsSinceEpoch,
      ),
    ];
    final futureTransaction = FinanceTransaction(
      uuid: 'timeline-summary-planned-next-month',
      amountMinor: 12000,
      transactionDate: '2026-11-02',
      occurredAt: DateTime(2026, 11, 2, 10).millisecondsSinceEpoch,
      createdAt: now.millisecondsSinceEpoch,
    );

    final currentPeriod = TimelineService.financeTransactionsThroughNow(
      transactions: currentTransactions,
      periodStart: DateTime(2026, 10),
      now: now,
    );
    final futurePeriod = TimelineService.financeTransactionsThroughNow(
      transactions: [futureTransaction],
      periodStart: DateTime(2026, 11),
      now: now,
    );

    expect(currentPeriod.map((item) => item.uuid), ['timeline-summary-past']);
    expect(futurePeriod.map((item) => item.uuid), [
      'timeline-summary-planned-next-month',
    ]);
  });
}
