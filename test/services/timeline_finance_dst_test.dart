import 'package:countdown_todo/features/finance/models/finance_models.dart';
import 'package:countdown_todo/services/timeline_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Timeline finance date boundaries', () {
    test('fall-back day reaches the next local midnight', () {
      final bounds = TimelineService.dayBoundsForDate(DateTime(2026, 11, 1));

      expect(bounds.start, DateTime(2026, 11, 1));
      expect(bounds.end, DateTime(2026, 11, 2));
      expect(bounds.end.difference(bounds.start), const Duration(hours: 25));
    });

    test('spring-forward two-day range is not treated as one day', () {
      final start = DateTime(2026, 3, 8);
      final end = DateTime(2026, 3, 10);

      expect(end.difference(start), const Duration(hours: 47));
      expect(
        TimelineService.isSingleCalendarDayRange(start, end),
        isFalse,
      );
    });

    test('keeps a transaction at the last hour of the fall-back day', () {
      final transaction = FinanceTransaction(
        amountMinor: 1250,
        transactionDate: '2026-11-01',
        occurredAt: DateTime.utc(2026, 11, 2, 4, 30).millisecondsSinceEpoch,
        timezoneOffsetMinutes: -300,
      );

      final timestamp = TimelineService.financeTransactionTimestampForDay(
        transaction,
        DateTime(2026, 11, 1),
      );

      expect(timestamp, DateTime(2026, 11, 1, 23, 30));
    });
  });
}
