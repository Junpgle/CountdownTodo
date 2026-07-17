import 'package:CountDownTodo/models.dart';
import 'package:CountDownTodo/services/pomodoro_service.dart';
import 'package:CountDownTodo/widgets/todo_recurrence_progress.dart';
import 'package:CountDownTodo/widgets/todo_section_widget.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('recurrence series only keeps its aggregate card in todo sections', () {
    TodoItem occurrence(int day,
        {RecurrenceType recurrence = RecurrenceType.none}) {
      return TodoItem(
        title: '每日循环',
        recurrence: recurrence,
        recurrenceSeriesId: 'series-only-one-card',
        createdDate: DateTime(2026, 7, day, 19).millisecondsSinceEpoch,
        dueDate: DateTime(2026, 7, day, 22),
      );
    }

    final past = occurrence(13);
    final repairedPast = occurrence(14);
    final current = occurrence(15, recurrence: RecurrenceType.daily);
    final future = occurrence(16);
    final normal = TodoItem(title: '普通待办');

    final visible =
        TodoSectionWidgetState.collapseRecurrenceInstancesForDisplayForTest([
      past,
      repairedPast,
      current,
      future,
      normal,
    ]);

    expect(
        visible.map((todo) => todo.id), containsAll([current.id, normal.id]));
    expect(visible, hasLength(2));
    expect(
      visible.map((todo) => todo.id),
      isNot(contains(anyOf(past.id, repairedPast.id, future.id))),
    );
  });

  test('ended recurrence series uses its latest occurrence as aggregate card',
      () {
    final previous = TodoItem(
      title: '已结束循环',
      recurrenceSeriesId: 'series-ended',
      createdDate: DateTime(2026, 7, 14).millisecondsSinceEpoch,
    );
    final latest = TodoItem(
      title: '已结束循环',
      recurrenceSeriesId: 'series-ended',
      createdDate: DateTime(2026, 7, 15).millisecondsSinceEpoch,
    );

    final visible =
        TodoSectionWidgetState.collapseRecurrenceInstancesForDisplayForTest([
      previous,
      latest,
    ]);

    expect(visible.single.id, latest.id);
  });

  test('finite recurrence summary counts the whole series', () {
    final nodes = List.generate(
      7,
      (index) => TodoRecurrenceProgressNode(
        date: DateTime(2026, 7, 13 + index),
        state: index < 2
            ? TodoRecurrenceNodeState.completed
            : index == 2
                ? TodoRecurrenceNodeState.current
                : TodoRecurrenceNodeState.future,
      ),
    );

    final finiteSummary = TodoSectionWidgetState.recurrenceSummaryForTest(
      allNodes: nodes,
      historyNodes: nodes.take(3).toList(),
      hasFixedEnd: true,
    );
    final openEndedSummary = TodoSectionWidgetState.recurrenceSummaryForTest(
      allNodes: nodes,
      historyNodes: nodes.take(3).toList(),
      hasFixedEnd: false,
    );

    expect(finiteSummary.completedCount, 2);
    expect(finiteSummary.totalCount, 7);
    expect(openEndedSummary.totalCount, 3);
  });

  test('todo editor exposes every persisted occurrence in its series', () {
    TodoItem occurrence(int day, {bool isDeleted = false}) => TodoItem(
          title: '每日循环',
          recurrenceSeriesId: 'series-editor-navigation',
          isDeleted: isDeleted,
          createdDate: DateTime(2026, 7, day).millisecondsSinceEpoch,
        );

    final first = occurrence(13);
    final current = occurrence(15);
    final future = occurrence(16);
    final deleted = occurrence(14, isDeleted: true);
    final unrelated = TodoItem(
      title: '其他循环',
      recurrenceSeriesId: 'other-series',
    );

    final related =
        TodoEditScreenState.relatedRecurrenceOccurrencesForTest(current, [
      future,
      unrelated,
      deleted,
      current,
      first,
    ]);

    expect(related.map((todo) => todo.id), [first.id, current.id, future.id]);
  });

  test('todo editor aggregates focus records from every series occurrence', () {
    TodoItem occurrence(int day, {bool isDeleted = false}) => TodoItem(
          title: '每日循环',
          recurrenceSeriesId: 'series-focus-summary',
          isDeleted: isDeleted,
          createdDate: DateTime(2026, 7, day).millisecondsSinceEpoch,
        );

    final previous = occurrence(14, isDeleted: true);
    final current = occurrence(15);
    final future = occurrence(16);
    final unrelated = TodoItem(
      title: '其他循环',
      recurrenceSeriesId: 'other-series',
    );

    final focusTodoIds = TodoEditScreenState.focusRecordTodoIdsForTest(
      current,
      [previous, current, future, unrelated],
    );

    expect(focusTodoIds, {previous.id, current.id, future.id});
  });

  test('daily focus records on two dates count as two recurrence periods', () {
    TodoItem occurrence(int day,
            {RecurrenceType recurrence = RecurrenceType.none}) =>
        TodoItem(
          title: '每日循环',
          recurrence: recurrence,
          recurrenceSeriesId: 'series-focus-periods',
          createdDate: DateTime(2026, 7, day, 19).millisecondsSinceEpoch,
          dueDate: DateTime(2026, 7, day, 22),
        );

    final july13 = occurrence(13);
    final july14 = occurrence(14);
    final current = occurrence(15, recurrence: RecurrenceType.daily);
    PomodoroRecord record(DateTime start) => PomodoroRecord(
          todoUuid: current.id,
          startTime: start.millisecondsSinceEpoch,
          plannedDuration: 25 * 60,
        );

    final count = TodoEditScreenState.focusedRecurrencePeriodCountForTest(
      current,
      [july13, july14, current],
      [
        record(DateTime(2026, 7, 13, 18, 55)),
        record(DateTime(2026, 7, 14, 19, 1)),
      ],
    );

    expect(count, 2);
  });

  test('cross-day focus stays in its bound recurrence period', () {
    final previous = TodoItem(
      title: '跨天每日循环',
      recurrenceSeriesId: 'series-cross-day-focus',
      createdDate: DateTime(2026, 7, 13, 19).millisecondsSinceEpoch,
      dueDate: DateTime(2026, 7, 14, 22),
    );
    final current = TodoItem(
      title: '跨天每日循环',
      recurrence: RecurrenceType.daily,
      recurrenceSeriesId: 'series-cross-day-focus',
      createdDate: DateTime(2026, 7, 14, 19).millisecondsSinceEpoch,
      dueDate: DateTime(2026, 7, 15, 22),
    );
    final record = PomodoroRecord(
      todoUuid: previous.id,
      startTime: DateTime(2026, 7, 14, 10).millisecondsSinceEpoch,
      plannedDuration: 25 * 60,
    );

    final count = TodoEditScreenState.focusedRecurrencePeriodCountForTest(
      current,
      [previous, current],
      [record],
    );

    expect(count, 1);
  });
}
