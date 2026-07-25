import 'package:countdown_todo/models.dart';
import 'package:countdown_todo/services/fixed_schedule_recurrence_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('FixedScheduleRecurrenceService', () {
    test('weekly summer classes are expanded through the inclusive end date',
        () {
      final dates = FixedScheduleRecurrenceService.occurrenceDates(
        startDate: DateTime(2026, 7, 7),
        endDate: DateTime(2026, 7, 28),
        recurrence: RecurrenceType.weekly,
      );

      expect(
        dates,
        [
          DateTime(2026, 7, 7),
          DateTime(2026, 7, 14),
          DateTime(2026, 7, 21),
          DateTime(2026, 7, 28),
        ],
      );
    });

    test('custom day intervals from AI capture are materialized exactly', () {
      final dates = FixedScheduleRecurrenceService.occurrenceDates(
        startDate: DateTime(2026, 7, 1),
        endDate: DateTime(2026, 7, 10),
        recurrence: RecurrenceType.customDays,
        customIntervalDays: 3,
      );

      expect(
        dates,
        [
          DateTime(2026, 7, 1),
          DateTime(2026, 7, 4),
          DateTime(2026, 7, 7),
          DateTime(2026, 7, 10),
        ],
      );
    });

    test('workday recurrence stays a workday rule', () {
      final template = FixedScheduleItem(
        id: 'weekday-class',
        title: '工作日辅导班',
        date: '2026-07-24',
      );

      final result = FixedScheduleRecurrenceService.rebuildSeries(
        template: template,
        existingSeries: const [],
        recurrence: RecurrenceType.weekdays,
        recurrenceEndDate: DateTime(2026, 7, 28),
      );

      expect(result.active.map((item) => item.date), [
        '2026-07-24',
        '2026-07-27',
        '2026-07-28',
      ]);
      expect(
        result.active.map((item) => item.recurrence).toSet(),
        {RecurrenceType.weekdays},
      );
    });

    test('custom interval metadata is copied to every occurrence', () {
      final template = FixedScheduleItem(
        id: 'custom-class',
        title: '隔三天辅导班',
        date: '2026-07-01',
      );

      final result = FixedScheduleRecurrenceService.rebuildSeries(
        template: template,
        existingSeries: const [],
        recurrence: RecurrenceType.customDays,
        recurrenceEndDate: DateTime(2026, 7, 10),
        customIntervalDays: 3,
      );

      expect(
        result.active.map((item) => item.customIntervalDays).toSet(),
        {3},
      );
    });

    test('oversized recurrence reports an error instead of truncating', () {
      expect(
        () => FixedScheduleRecurrenceService.occurrenceDates(
          startDate: DateTime(2026, 1, 1),
          endDate: DateTime(2026, 1, 1).add(
            const Duration(
              days: FixedScheduleRecurrenceService.maxOccurrences,
            ),
          ),
          recurrence: RecurrenceType.daily,
        ),
        throwsA(isA<FixedScheduleRecurrenceLimitException>()),
      );
    });

    test('materialized occurrences keep time, team and series identity', () {
      final template = FixedScheduleItem(
        id: 'summer-class',
        title: '暑假数学辅导班',
        date: '2026-07-07',
        startTime: DateTime(2026, 7, 7, 9).millisecondsSinceEpoch,
        endTime: DateTime(2026, 7, 7, 11).millisecondsSinceEpoch,
        teamUuid: 'family-team',
      );

      final result = FixedScheduleRecurrenceService.rebuildSeries(
        template: template,
        existingSeries: const [],
        recurrence: RecurrenceType.weekly,
        recurrenceEndDate: DateTime(2026, 7, 21),
      );

      expect(result.active, hasLength(3));
      expect(
          result.active.map((item) => item.teamUuid).toSet(), {'family-team'});
      expect(result.active.map((item) => item.recurrenceSeriesId).toSet(),
          {'summer-class'});
      expect(result.active.map((item) => item.recurrence).toSet(),
          {RecurrenceType.weekly});
      expect(
        result.active
            .map((item) =>
                DateTime.fromMillisecondsSinceEpoch(item.startTime!).hour)
            .toSet(),
        {9},
      );
    });

    test('shortening a series emits tombstones for removed occurrences', () {
      final template = FixedScheduleItem(
        id: 'series-start',
        title: '暑假英语辅导班',
        date: '2026-07-01',
        startTime: DateTime(2026, 7, 1, 14).millisecondsSinceEpoch,
        endTime: DateTime(2026, 7, 1, 16).millisecondsSinceEpoch,
        recurrence: RecurrenceType.weekly,
        recurrenceSeriesId: 'series-start',
      );
      final existing = FixedScheduleRecurrenceService.rebuildSeries(
        template: template,
        existingSeries: const [],
        recurrence: RecurrenceType.weekly,
        recurrenceEndDate: DateTime(2026, 7, 29),
      ).active;

      final shortened = FixedScheduleRecurrenceService.rebuildSeries(
        template: template,
        existingSeries: existing,
        recurrence: RecurrenceType.weekly,
        recurrenceEndDate: DateTime(2026, 7, 15),
      );

      expect(shortened.active, hasLength(3));
      expect(shortened.changes.where((item) => item.isDeleted), hasLength(2));
    });
  });
}
