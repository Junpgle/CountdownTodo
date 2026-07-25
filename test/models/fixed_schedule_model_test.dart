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
        ownerUserId: 42,
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
      expect(restored.ownerUserId, 42);
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

    test('only a known owner can change a shared schedule team', () {
      final owned = FixedScheduleItem(
        title: '团队会议',
        date: '2026-07-27',
        teamUuid: 'team-1',
        ownerUserId: 42,
      );
      final legacyUnknownOwner = FixedScheduleItem(
        title: '旧团队会议',
        date: '2026-07-27',
        teamUuid: 'team-1',
      );

      expect(owned.canChangeTeamFor(42), isTrue);
      expect(owned.canChangeTeamFor(7), isFalse);
      expect(legacyUnknownOwner.canChangeTeamFor(42), isFalse);
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

    test('end-time-TBD is ongoing only until the schedule day ends', () {
      final item = FixedScheduleItem(
        title: '公开课',
        date: '2026-07-22',
        startTime: DateTime(2026, 7, 22, 20).millisecondsSinceEpoch,
      );

      expect(
        item.phaseAt(DateTime(2026, 7, 22, 21)),
        FixedSchedulePhase.ongoing,
      );
      expect(
        item.phaseAt(DateTime(2026, 7, 23)),
        FixedSchedulePhase.ended,
      );
      expect(
        DateTime.fromMillisecondsSinceEpoch(item.effectiveActivityEndTime!),
        DateTime(2026, 7, 23),
      );
    });

    test('local changes stay newer than a future pulled timestamp', () {
      final future = DateTime.now().add(const Duration(days: 1));
      final item = FixedScheduleItem(
        title: '时钟偏移日程',
        date: '2026-07-22',
        updatedAt: future.millisecondsSinceEpoch,
        version: 3,
      );

      item.markAsChanged();

      expect(item.updatedAt, future.millisecondsSinceEpoch + 1);
      expect(item.version, 4);
    });
  });
}
