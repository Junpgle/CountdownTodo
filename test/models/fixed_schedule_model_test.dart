import 'package:countdown_todo/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('FixedScheduleItem', () {
    test('round trips independent schedule fields', () {
      final source = FixedScheduleItem(
        id: 'exam-1',
        title: '高等数学考试',
        date: '2026-07-22',
        startTime: DateTime(2026, 7, 22, 14).millisecondsSinceEpoch,
        endTime: DateTime(2026, 7, 22, 16).millisecondsSinceEpoch,
        location: 'A101',
        reminderMinutes: const [1440, 30],
        recurrence: RecurrenceType.customDays,
        customIntervalDays: 3,
        recurrenceSeriesId: 'exam-series',
        relatedTodoIds: const ['review-todo'],
      );

      final restored = FixedScheduleItem.fromJson(source.toJson());

      expect(restored.id, source.id);
      expect(restored.title, source.title);
      expect(restored.location, 'A101');
      expect(restored.reminderMinutes, [1440, 30]);
      expect(restored.relatedTodoIds, ['review-todo']);
      expect(restored.recurrence, RecurrenceType.customDays);
      expect(restored.customIntervalDays, 3);
      expect(restored.recurrenceSeriesId, 'exam-series');
    });

    test('supports a fixed date whose clock time is still unknown', () {
      final item = FixedScheduleItem(
        title: '下周一会议',
        date: '2026-07-27',
      );

      expect(item.isTimeTbd, isTrue);
      expect(
        item.phaseAt(DateTime(2026, 7, 20)),
        FixedSchedulePhase.timeTbd,
      );
    });

    test('accepts the server payload shape without inventing a time range', () {
      final item = FixedScheduleItem.fromJson({
        'uuid': 'pickup-window-1',
        'title': '预约取证',
        'date': '2026-07-27',
        'start_time': null,
        'end_time': null,
        'reminder_minutes': [1440, 30],
        'related_todo_ids': ['prepare-documents'],
        'is_deleted': false,
        'version': 3,
        'created_at': 1000,
        'updated_at': 2000,
      });

      expect(item.isTimeTbd, isTrue);
      expect(item.reminderMinutes, [1440, 30]);
      expect(item.relatedTodoIds, ['prepare-documents']);
      expect(item.isDeleted, isFalse);
      expect(item.version, 3);
    });

    test('derives upcoming ongoing and ended phases', () {
      final item = FixedScheduleItem(
        title: '面试',
        date: '2026-07-22',
        startTime: DateTime(2026, 7, 22, 10).millisecondsSinceEpoch,
        endTime: DateTime(2026, 7, 22, 11).millisecondsSinceEpoch,
      );

      expect(
        item.phaseAt(DateTime(2026, 7, 22, 9)),
        FixedSchedulePhase.upcoming,
      );
      expect(
        item.phaseAt(DateTime(2026, 7, 22, 10, 30)),
        FixedSchedulePhase.ongoing,
      );
      expect(
        item.phaseAt(DateTime(2026, 7, 22, 12)),
        FixedSchedulePhase.ended,
      );
    });
  });
}
