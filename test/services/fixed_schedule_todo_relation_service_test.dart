import 'package:countdown_todo/models.dart';
import 'package:countdown_todo/services/fixed_schedule_todo_relation_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026, 10, 24, 12);
  final todo = TodoItem(id: 'todo-a', title: '准备考试');

  FixedScheduleItem schedule(
    String id,
    String date, {
    String title = '期末考试',
    String? teamUuid,
    String? seriesId,
    List<String> relatedTodoIds = const ['todo-a'],
    FixedScheduleStatus status = FixedScheduleStatus.scheduled,
    int? startHour,
    bool isDeleted = false,
  }) => FixedScheduleItem(
    id: id,
    title: title,
    date: date,
    startTime: startHour == null
        ? null
        : DateTime.parse('$date ${startHour.toString().padLeft(2, '0')}:00')
              .millisecondsSinceEpoch,
    endTime: startHour == null
        ? null
        : DateTime.parse('$date ${startHour.toString().padLeft(2, '0')}:30')
              .millisecondsSinceEpoch,
    recurrenceSeriesId: seriesId,
    relatedTodoIds: relatedTodoIds,
    teamUuid: teamUuid,
    status: status,
    isDeleted: isDeleted,
  );

  test('filters exact links, deleted rows, and mismatched visibility', () {
    final related = FixedScheduleTodoRelationService.groupForTodo(
      todo: todo,
      now: now,
      schedules: [
        schedule('personal', '2026-10-28', startHour: 9),
        schedule('wrong-team', '2026-10-27', teamUuid: 'team-a'),
        schedule('deleted', '2026-10-26', isDeleted: true),
        schedule('different-todo', '2026-10-25', relatedTodoIds: ['todo-ab']),
      ],
    );

    expect(related.map((group) => group.items.single.id), ['personal']);
  });

  test('team todo only sees its own normalized team scope', () {
    final teamTodo = TodoItem(
      id: 'team-todo',
      title: '准备答辩',
      teamUuid: 'team-a',
    );
    final groups = FixedScheduleTodoRelationService.groupForTodo(
      todo: teamTodo,
      now: now,
      schedules: [
        schedule(
          'same-team',
          '2026-10-28',
          teamUuid: ' team-a ',
          relatedTodoIds: ['team-todo'],
        ),
        schedule(
          'other-team',
          '2026-10-27',
          teamUuid: 'team-b',
          relatedTodoIds: ['team-todo'],
        ),
        schedule('personal', '2026-10-26', relatedTodoIds: ['team-todo']),
      ],
    );

    expect(groups.map((group) => group.items.single.id), ['same-team']);
  });

  test('groups series by stable title and prefers nearest live occurrence', () {
    final groups = FixedScheduleTodoRelationService.groupForTodo(
      todo: todo,
      now: now,
      schedules: [
        schedule('past', '2026-10-20', seriesId: 'exam-series', startHour: 9),
        schedule('next', '2026-10-30', seriesId: 'exam-series', startHour: 9),
        schedule(
          'cancelled',
          '2026-10-27',
          seriesId: 'exam-series',
          status: FixedScheduleStatus.cancelled,
          startHour: 9,
        ),
        schedule(
          'renamed',
          '2026-11-06',
          title: '期末考试（改期）',
          seriesId: 'exam-series',
          startHour: 9,
        ),
      ],
    );

    expect(groups, hasLength(2));
    expect(groups.first.isSeries, isTrue);
    expect(groups.first.title, '期末考试');
    expect(groups.first.items.map((item) => item.id), [
      'next',
      'past',
      'cancelled',
    ]);
    expect(groups.first.summaryItem.id, 'next');
    expect(groups.last.title, '期末考试（改期）');
    expect(groups.last.summaryItem.id, 'renamed');
  });

  test(
    'when a series has no live occurrence, summary uses most recent history',
    () {
      final groups = FixedScheduleTodoRelationService.groupForTodo(
        todo: todo,
        now: now,
        schedules: [
          schedule(
            'older',
            '2026-10-20',
            seriesId: 'past-series',
            startHour: 9,
          ),
          schedule(
            'newer',
            '2026-10-23',
            seriesId: 'past-series',
            startHour: 9,
          ),
        ],
      );

      expect(groups.single.summaryItem.id, 'newer');
    },
  );
}
