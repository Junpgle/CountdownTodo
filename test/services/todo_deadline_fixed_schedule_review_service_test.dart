import 'package:countdown_todo/models.dart';
import 'package:countdown_todo/services/todo_deadline_fixed_schedule_review_service.dart';
import 'package:flutter_test/flutter_test.dart';

DateTime _at(int day, int hour, [int minute = 0]) =>
    DateTime(2026, 10, day, hour, minute);

TodoItem _todo(
  String id, {
  required DateTime? due,
  bool dateOnly = false,
  bool done = false,
  bool skipped = false,
  String? teamUuid,
}) => TodoItem(
  id: id,
  title: '准备材料 $id',
  dueDate: due,
  isAllDay: dateOnly,
  isDone: done,
  isSkipped: skipped,
  teamUuid: teamUuid,
);

FixedScheduleItem _schedule(
  String id,
  DateTime? start, {
  List<String> todoIds = const [],
  String? seriesId,
  String title = '考试',
  String? teamUuid,
  FixedScheduleStatus status = FixedScheduleStatus.scheduled,
  bool deleted = false,
}) => FixedScheduleItem(
  id: id,
  title: title,
  date: '2026-10-08',
  startTime: start?.millisecondsSinceEpoch,
  endTime: start?.add(const Duration(hours: 2)).millisecondsSinceEpoch,
  relatedTodoIds: todoIds,
  recurrenceSeriesId: seriesId,
  teamUuid: teamUuid,
  status: status,
  isDeleted: deleted,
);

void main() {
  final now = _at(1, 8);

  test('定时期限移到未来日程开始之后时生成改前改后复核项', () {
    final before = _todo('todo-1', due: _at(8, 8));
    final after = TodoItem.fromJson(before.toJson())..dueDate = _at(8, 11);
    final schedule = _schedule('schedule-1', _at(8, 10), todoIds: ['todo-1']);

    final review = TodoDeadlineFixedScheduleReviewService.build(
      changedTodos: [after],
      baselines: {'todo-1': before},
      schedules: [schedule],
      now: now,
    );

    expect(review.needsReview, isTrue);
    expect(review.entryCount, 1);
    expect(review.groups.single.entries.single.beforeTodo.dueDate, _at(8, 8));
    expect(review.groups.single.entries.single.afterTodo.dueDate, _at(8, 11));
  });

  test('未改期限或改到日程开始前不产生复核', () {
    final before = _todo('todo-1', due: _at(8, 8));
    final unchanged = TodoItem.fromJson(before.toJson())..title = '标题变化';
    final earlier = TodoItem.fromJson(before.toJson())..dueDate = _at(8, 9);
    final schedule = _schedule('schedule-1', _at(8, 10), todoIds: ['todo-1']);

    expect(
      TodoDeadlineFixedScheduleReviewService.build(
        changedTodos: [unchanged],
        baselines: {'todo-1': before},
        schedules: [schedule],
        now: now,
      ).needsReview,
      isFalse,
    );
    expect(
      TodoDeadlineFixedScheduleReviewService.build(
        changedTodos: [earlier],
        baselines: {'todo-1': before},
        schedules: [schedule],
        now: now,
      ).needsReview,
      isFalse,
    );
  });

  test('日期待办按自然日比较，同一天不按23:59制造误报', () {
    final before = _todo('todo-1', due: _at(8, 23, 59), dateOnly: true);
    final sameDay = TodoItem.fromJson(before.toJson());
    final nextDay = TodoItem.fromJson(before.toJson())
      ..dueDate = _at(9, 23, 59);
    final schedule = _schedule('schedule-1', _at(8, 10), todoIds: ['todo-1']);

    expect(
      TodoDeadlineFixedScheduleReviewService.build(
        changedTodos: [sameDay],
        baselines: {
          'todo-1': _todo('todo-1', due: _at(7, 23, 59), dateOnly: true),
        },
        schedules: [schedule],
        now: now,
      ).needsReview,
      isFalse,
    );
    final review = TodoDeadlineFixedScheduleReviewService.build(
      changedTodos: [nextDay],
      baselines: {'todo-1': before},
      schedules: [schedule],
      now: now,
    );
    expect(review.needsReview, isTrue);
    expect(review.groups.single.entries.single.afterTodo.isDateOnly, isTrue);
  });

  test('只展示未开始的日程且排除完成跳过及跨团队关系', () {
    final base = _todo('todo-1', due: _at(8, 12));
    final changed = TodoItem.fromJson(base.toJson())..dueDate = _at(8, 13);
    final schedules = [
      _schedule('upcoming', _at(8, 10), todoIds: ['todo-1']),
      _schedule('ongoing', _at(1, 7), todoIds: ['todo-1']),
      _schedule(
        'cancelled',
        _at(8, 10),
        todoIds: ['todo-1'],
        status: FixedScheduleStatus.cancelled,
      ),
      _schedule('tbd', null, todoIds: ['todo-1']),
      _schedule(
        'wrong-team',
        _at(8, 10),
        todoIds: ['todo-1'],
        teamUuid: 'team-a',
      ),
    ];
    final review = TodoDeadlineFixedScheduleReviewService.build(
      changedTodos: [changed],
      baselines: {'todo-1': base},
      schedules: schedules,
      now: now,
    );
    expect(review.groups.single.entries.map((entry) => entry.schedule.id), [
      'upcoming',
    ]);

    final done = TodoItem.fromJson(changed.toJson())..isDone = true;
    final skipped = TodoItem.fromJson(changed.toJson())..isSkipped = true;
    expect(
      TodoDeadlineFixedScheduleReviewService.build(
        changedTodos: [done, skipped],
        baselines: {'todo-1': base},
        schedules: schedules,
        now: now,
      ).needsReview,
      isFalse,
    );
  });

  test('待办同时转移团队时按保存前的关联范围复核', () {
    final before = _todo('todo-1', due: _at(8, 8), teamUuid: 'team-a');
    final after = TodoItem.fromJson(before.toJson())
      ..dueDate = _at(8, 12)
      ..teamUuid = 'team-b';
    final schedule = _schedule(
      'schedule-1',
      _at(8, 10),
      todoIds: ['todo-1'],
      teamUuid: 'team-a',
    );

    final review = TodoDeadlineFixedScheduleReviewService.build(
      changedTodos: [after],
      baselines: {'todo-1': before},
      schedules: [schedule],
      now: now,
    );

    expect(review.entryCount, 1);
  });

  test('重复固定日程按系列和标题合并并保留每期明细', () {
    final beforeA = _todo('todo-a', due: _at(7, 8));
    final afterA = TodoItem.fromJson(beforeA.toJson())..dueDate = _at(8, 11);
    final beforeB = _todo('todo-b', due: _at(14, 8));
    final afterB = TodoItem.fromJson(beforeB.toJson())..dueDate = _at(15, 11);
    final schedules = [
      _schedule(
        'schedule-a',
        _at(8, 10),
        todoIds: ['todo-a'],
        seriesId: 'series-1',
      ),
      _schedule(
        'schedule-b',
        _at(15, 10),
        todoIds: ['todo-b'],
        seriesId: 'series-1',
      ),
    ];

    final review = TodoDeadlineFixedScheduleReviewService.build(
      changedTodos: [afterA, afterB],
      baselines: {'todo-a': beforeA, 'todo-b': beforeB},
      schedules: schedules,
      now: now,
    );

    expect(review.groups, hasLength(1));
    expect(review.groups.single.isSeries, isTrue);
    expect(review.groups.single.entries, hasLength(2));
    expect(review.groups.single.firstStart, _at(8, 10));
    expect(review.groups.single.lastStart, _at(15, 10));
  });
}
