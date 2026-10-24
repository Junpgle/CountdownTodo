import 'package:countdown_todo/models.dart';
import 'package:countdown_todo/services/fixed_schedule_reschedule_impact_service.dart';
import 'package:flutter_test/flutter_test.dart';

DateTime _at(String date, String time) => DateTime.parse('${date}T$time:00');

FixedScheduleItem _schedule({
  required String id,
  required String date,
  required DateTime start,
  DateTime? end,
  List<String> relatedTodoIds = const [],
  String? teamUuid,
  List<int> reminderMinutes = const [],
  FixedScheduleStatus status = FixedScheduleStatus.scheduled,
}) => FixedScheduleItem(
  id: id,
  title: '考试',
  date: date,
  startTime: start.millisecondsSinceEpoch,
  endTime: end?.millisecondsSinceEpoch,
  relatedTodoIds: relatedTodoIds,
  teamUuid: teamUuid,
  reminderMinutes: reminderMinutes,
  status: status,
);

FixedScheduleRescheduleImpact _build({
  required List<FixedScheduleItem> baseline,
  required List<FixedScheduleItem> active,
  required List<FixedScheduleItem> changes,
  required FixedScheduleEditScope scope,
  required FixedScheduleItem selected,
  required FixedScheduleItem refresh,
  List<TodoItem> todos = const [],
  List<TodoPlanBlock> plans = const [],
  DateTime? now,
}) => FixedScheduleRescheduleImpactService.build(
  baseline: baseline,
  active: active,
  changes: changes,
  scope: scope,
  selectedOccurrence: selected,
  refreshItem: refresh,
  todos: todos,
  planBlocks: plans,
  now: now ?? _at('2026-10-01', '08:00'),
);

void main() {
  test('ignores title and reminder-only edits', () {
    final original = _schedule(
      id: 'schedule-1',
      date: '2026-10-20',
      start: _at('2026-10-20', '09:00'),
      end: _at('2026-10-20', '10:00'),
    );
    final edited = FixedScheduleItem.fromJson(original.toJson())
      ..title = '新标题'
      ..reminderMinutes = [15];

    final impact = _build(
      baseline: [original],
      active: [edited],
      changes: [edited],
      scope: FixedScheduleEditScope.occurrence,
      selected: original,
      refresh: edited,
    );

    expect(impact.shouldReview, isFalse);
    expect(impact.deltas, isEmpty);
  });

  test('keeps an explicitly cleared start or end time cleared', () {
    final original = _schedule(
      id: 'schedule-1',
      date: '2026-10-20',
      start: _at('2026-10-20', '09:00'),
      end: _at('2026-10-20', '10:00'),
    );
    final edited = FixedScheduleItem.fromJson(original.toJson())
      ..date = '2026-10-21'
      ..startTime = null
      ..endTime = null;

    final impact = _build(
      baseline: [original],
      active: [edited],
      changes: [edited],
      scope: FixedScheduleEditScope.occurrence,
      selected: original,
      refresh: edited,
    );

    expect(impact.deltas, hasLength(1));
    expect(impact.deltas.single.start, isNull);
    expect(impact.deltas.single.end, isNull);
  });

  test('counts only dates changed in the chosen future scope', () {
    final earlier = _schedule(
      id: 'earlier',
      date: '2026-11-03',
      start: _at('2026-11-03', '09:00'),
      end: _at('2026-11-03', '10:00'),
    );
    final selected = _schedule(
      id: 'selected',
      date: '2026-11-10',
      start: _at('2026-11-10', '09:00'),
      end: _at('2026-11-10', '10:00'),
    );
    final later = _schedule(
      id: 'later',
      date: '2026-11-17',
      start: _at('2026-11-17', '09:00'),
      end: _at('2026-11-17', '10:00'),
    );
    final editedSelected = FixedScheduleItem.fromJson(selected.toJson())
      ..startTime = _at('2026-11-10', '11:00').millisecondsSinceEpoch
      ..endTime = _at('2026-11-10', '12:00').millisecondsSinceEpoch;
    final editedLater = FixedScheduleItem.fromJson(later.toJson())
      ..startTime = _at('2026-11-17', '11:00').millisecondsSinceEpoch
      ..endTime = _at('2026-11-17', '12:00').millisecondsSinceEpoch;

    final impact = _build(
      baseline: [earlier, selected, later],
      active: [earlier, editedSelected, editedLater],
      changes: [editedSelected, editedLater],
      scope: FixedScheduleEditScope.future,
      selected: selected,
      refresh: editedSelected,
    );

    expect(impact.deltas.map((delta) => delta.id), ['selected', 'later']);
    expect(impact.deltas.map((delta) => delta.before?.id), [
      'selected',
      'later',
    ]);
  });

  test(
    'hides a linked todo when only an unrelated schedule has its team scope',
    () {
      final oldTeamSchedule = _schedule(
        id: 'team-event',
        date: '2026-10-20',
        start: _at('2026-10-20', '09:00'),
        end: _at('2026-10-20', '10:00'),
        relatedTodoIds: ['private-todo'],
        teamUuid: 'team-a',
      );
      final movedTeamSchedule = FixedScheduleItem.fromJson(
        oldTeamSchedule.toJson(),
      )..startTime = _at('2026-10-20', '11:00').millisecondsSinceEpoch;
      final unrelatedPersonalSchedule = _schedule(
        id: 'personal-event',
        date: '2026-10-21',
        start: _at('2026-10-21', '09:00'),
        end: _at('2026-10-21', '10:00'),
      );
      final movedPersonalSchedule = FixedScheduleItem.fromJson(
        unrelatedPersonalSchedule.toJson(),
      )..startTime = _at('2026-10-21', '11:00').millisecondsSinceEpoch;

      final impact = _build(
        baseline: [oldTeamSchedule, unrelatedPersonalSchedule],
        active: [movedTeamSchedule, movedPersonalSchedule],
        changes: [movedTeamSchedule, movedPersonalSchedule],
        scope: FixedScheduleEditScope.series,
        selected: oldTeamSchedule,
        refresh: movedTeamSchedule,
        todos: [TodoItem(id: 'private-todo', title: '团队事项', teamUuid: null)],
      );

      expect(impact.relatedTodoIds, {'private-todo'});
      expect(impact.visibleTodos, isEmpty);
    },
  );

  test(
    'warns on late deadlines without treating date due as a time conflict',
    () {
      final original = _schedule(
        id: 'schedule-1',
        date: '2026-10-20',
        start: _at('2026-10-20', '09:00'),
        end: _at('2026-10-20', '10:00'),
        relatedTodoIds: ['exact', 'date-only'],
      );
      final edited = FixedScheduleItem.fromJson(original.toJson())
        ..startTime = _at('2026-10-20', '10:00').millisecondsSinceEpoch
        ..endTime = _at('2026-10-20', '11:00').millisecondsSinceEpoch;
      final exactDeadline = TodoItem(
        id: 'exact',
        title: '具体时刻待办',
        dueDate: _at('2026-10-20', '10:30'),
      );
      final dateOnlyDeadline = TodoItem(
        id: 'date-only',
        title: '日期待办',
        dueDate: _at('2026-10-20', '00:00'),
        isAllDay: true,
      );
      final impact = _build(
        baseline: [original],
        active: [edited],
        changes: [edited],
        scope: FixedScheduleEditScope.occurrence,
        selected: original,
        refresh: edited,
        todos: [exactDeadline, dateOnlyDeadline],
      );

      expect(
        FixedScheduleRescheduleImpactService.todoDeadlineNeedsReview(
          exactDeadline,
          impact.deltas,
        ),
        isTrue,
      );
      expect(
        FixedScheduleRescheduleImpactService.todoDeadlineNeedsReview(
          dateOnlyDeadline,
          impact.deltas,
        ),
        isFalse,
      );
    },
  );

  test('lists each active plan overlap and excludes terminal plans', () {
    final original = _schedule(
      id: 'schedule-1',
      date: '2026-10-20',
      start: _at('2026-10-20', '09:00'),
      end: _at('2026-10-20', '10:00'),
    );
    final edited = FixedScheduleItem.fromJson(original.toJson())
      ..startTime = _at('2026-10-20', '10:00').millisecondsSinceEpoch
      ..endTime = _at('2026-10-20', '11:00').millisecondsSinceEpoch;
    TodoPlanBlock plan(String id, TodoPlanStatus status) => TodoPlanBlock(
      id: id,
      todoId: 'todo-$id',
      titleSnapshot: id,
      startTime: _at('2026-10-20', '10:30').millisecondsSinceEpoch,
      endTime: _at('2026-10-20', '11:30').millisecondsSinceEpoch,
      status: status,
    );

    final impact = _build(
      baseline: [original],
      active: [edited],
      changes: [edited],
      scope: FixedScheduleEditScope.occurrence,
      selected: original,
      refresh: edited,
      plans: [
        plan('planned', TodoPlanStatus.planned),
        plan('done', TodoPlanStatus.finished),
      ],
    );

    expect(impact.planBlocks.map((item) => item.id), ['planned']);
    expect(impact.planConflicts, hasLength(1));
    expect(
      DateTime.fromMillisecondsSinceEpoch(
        impact.planConflicts.single.startTime,
      ),
      _at('2026-10-20', '10:30'),
    );
  });

  test(
    'reminders use post-change instant and omit past or finished events',
    () {
      final now = _at('2026-10-21', '12:00');
      final original = _schedule(
        id: 'schedule-1',
        date: '2026-10-20',
        start: _at('2026-10-20', '09:00'),
        end: _at('2026-10-20', '10:00'),
        reminderMinutes: [15, 60, 1440],
      );
      final edited = FixedScheduleItem.fromJson(original.toJson())
        ..startTime = _at('2026-10-22', '11:00').millisecondsSinceEpoch
        ..endTime = _at('2026-10-22', '12:00').millisecondsSinceEpoch
        ..date = '2026-10-22';
      final finished = _schedule(
        id: 'finished',
        date: '2026-10-22',
        start: _at('2026-10-22', '11:00'),
        end: _at('2026-10-22', '12:00'),
        reminderMinutes: [15],
        status: FixedScheduleStatus.finished,
      );

      final impact = _build(
        baseline: [original, finished],
        active: [edited, finished],
        changes: [edited, finished],
        scope: FixedScheduleEditScope.series,
        selected: original,
        refresh: edited,
        now: now,
      );

      expect(impact.reminders, hasLength(3));
      expect(
        impact.reminders.map((reminder) => reminder.triggerAt),
        contains(_at('2026-10-21', '11:00')),
      );
      expect(
        impact.reminders.any((reminder) => reminder.isPastAt(now)),
        isTrue,
      );
      expect(
        impact.reminders.every(
          (reminder) => reminder.scheduleId == 'schedule-1',
        ),
        isTrue,
      );
    },
  );
}
