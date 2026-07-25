import 'package:countdown_todo/models.dart';
import 'package:countdown_todo/services/calendar_sync_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CalendarSyncService todo semantics', () {
    test('does not export an unscheduled todo as a fake event', () {
      final todo = TodoItem(title: '买牛奶');

      expect(CalendarSyncService.todoToEntryForTest(todo), isNull);
    });

    test('exports a date-only todo to the all-day area', () {
      final todo = TodoItem(
        title: '取快递',
        createdDate: DateTime(2026, 7, 21).millisecondsSinceEpoch,
        dueDate: DateTime(2026, 7, 21, 23, 59),
        isAllDay: true,
      );

      final entry = CalendarSyncService.todoToEntryForTest(todo)!;

      expect(entry.allDay, isTrue);
      expect(entry.start, DateTime(2026, 7, 21));
      expect(entry.end, DateTime(2026, 7, 22));
    });

    test('exports a new deadline as a one-minute deadline marker', () {
      final due = DateTime(2026, 7, 21, 18);
      final todo = TodoItem(
        title: '交作业',
        createdDate: due.millisecondsSinceEpoch,
        dueDate: due,
      );

      final entry = CalendarSyncService.todoToEntryForTest(todo)!;

      expect(entry.allDay, isFalse);
      expect(entry.start, DateTime(2026, 7, 21, 17, 59));
      expect(entry.end, due);
    });

    test('keeps a legacy timed todo range unchanged', () {
      final start = DateTime(2026, 7, 21, 14);
      final due = DateTime(2026, 7, 21, 16);
      final todo = TodoItem(
        title: '旧时间段待办',
        createdDate: start.millisecondsSinceEpoch,
        dueDate: due,
      );

      final entry = CalendarSyncService.todoToEntryForTest(todo)!;

      expect(entry.start, start);
      expect(entry.end, due);
    });

    test('exports an exact fixed schedule as a busy event', () {
      final start = DateTime(2026, 7, 22, 14);
      final end = DateTime(2026, 7, 22, 16);
      final item = FixedScheduleItem(
        title: '高数考试',
        date: '2026-07-22',
        startTime: start.millisecondsSinceEpoch,
        endTime: end.millisecondsSinceEpoch,
        location: 'A101',
      );

      final entry = CalendarSyncService.fixedScheduleToEntryForTest(item)!;

      expect(entry.type, CalendarSyncEntryType.fixedSchedule);
      expect(entry.start, start);
      expect(entry.end, end);
      expect(entry.location, 'A101');
    });

    test('does not fabricate an event for a time-TBD fixed schedule', () {
      final item = FixedScheduleItem(
        title: '时间待定会议',
        date: '2026-07-22',
      );

      expect(
        CalendarSyncService.fixedScheduleToEntryForTest(item),
        isNull,
      );
    });
  });
}
