import 'package:countdown_todo/models.dart';
import 'package:countdown_todo/services/schedule_conflict_service.dart';
import 'package:flutter_test/flutter_test.dart';

FixedScheduleItem fixed(
  String id,
  String title,
  DateTime start,
  DateTime end,
) =>
    FixedScheduleItem(
      id: id,
      title: title,
      date:
          '${start.year}-${start.month.toString().padLeft(2, '0')}-${start.day.toString().padLeft(2, '0')}',
      startTime: start.millisecondsSinceEpoch,
      endTime: end.millisecondsSinceEpoch,
    );

void main() {
  group('ScheduleConflictService', () {
    test('reports fixed schedule overlap as a hard conflict', () {
      final conflicts = ScheduleConflictService.detect(
        fixedSchedules: [
          fixed(
            'exam',
            '考试',
            DateTime(2026, 7, 22, 14),
            DateTime(2026, 7, 22, 16),
          ),
          fixed(
            'interview',
            '面试',
            DateTime(2026, 7, 22, 15),
            DateTime(2026, 7, 22, 17),
          ),
        ],
      );

      expect(conflicts, hasLength(1));
      expect(conflicts.single.severity, ScheduleConflictSeverity.hard);
    });

    test('reports a plan overlap as soft and recommends moving the plan', () {
      final schedule = fixed(
        'exam',
        '考试',
        DateTime(2026, 7, 22, 14),
        DateTime(2026, 7, 22, 16),
      );
      final plan = TodoPlanBlock(
        id: 'review-plan',
        todoId: 'review',
        titleSnapshot: '复习',
        startTime: DateTime(2026, 7, 22, 15).millisecondsSinceEpoch,
        endTime: DateTime(2026, 7, 22, 17).millisecondsSinceEpoch,
      );

      final conflicts = ScheduleConflictService.detect(
        fixedSchedules: [schedule],
        planBlocks: [plan],
      );

      expect(conflicts, hasLength(1));
      expect(conflicts.single.severity, ScheduleConflictSeverity.soft);
      expect(conflicts.single.message, contains('建议移动规划块'));
    });

    test('includes courses as hard constraints', () {
      final schedule = fixed(
        'exam',
        '考试',
        DateTime(2026, 7, 22, 14),
        DateTime(2026, 7, 22, 16),
      );
      final course = CourseItem(
        uuid: 'course',
        courseName: '高数课',
        teacherName: '',
        date: '2026-07-22',
        weekday: 3,
        startTime: 1500,
        endTime: 1630,
        weekIndex: 1,
        roomName: '',
      );

      final conflicts = ScheduleConflictService.detect(
        fixedSchedules: [schedule],
        courses: [course],
      );

      expect(conflicts.single.severity, ScheduleConflictSeverity.hard);
      expect(conflicts.single.rightKind, ScheduleEntityKind.course);
    });

    test('ignores time-TBD schedules and adjacent ranges', () {
      final timeTbd = FixedScheduleItem(
        id: 'tbd',
        title: '时间待定会议',
        date: '2026-07-22',
      );
      final first = fixed(
        'first',
        '第一场',
        DateTime(2026, 7, 22, 14),
        DateTime(2026, 7, 22, 15),
      );
      final second = fixed(
        'second',
        '第二场',
        DateTime(2026, 7, 22, 15),
        DateTime(2026, 7, 22, 16),
      );

      final conflicts = ScheduleConflictService.detect(
        fixedSchedules: [timeTbd, first, second],
      );

      expect(conflicts, isEmpty);
    });
  });
}
