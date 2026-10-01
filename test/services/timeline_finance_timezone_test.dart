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
}
