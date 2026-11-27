import 'package:countdown_todo/models.dart';
import 'package:countdown_todo/utils/todo_recurrence_picker.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final today = DateTime(2026, 7, 15, 12);

  TodoItem occurrence(
    int day, {
    RecurrenceType recurrence = RecurrenceType.none,
    bool isDone = false,
  }) {
    return TodoItem(
      title: '每日循环',
      recurrence: recurrence,
      recurrenceSeriesId: 'picker-series',
      isDone: isDone,
      createdDate: DateTime(2026, 7, day, 19).millisecondsSinceEpoch,
    );
  }

  test('todo picker keeps only the current recurrence occurrence', () {
    final previous = occurrence(14);
    final current = occurrence(15, recurrence: RecurrenceType.daily);
    final future = occurrence(16);
    final normal = TodoItem(title: '普通任务');

    final collapsed = collapseRecurrenceSeriesForTodoPicker([
      future,
      previous,
      normal,
      current,
    ], now: today);

    expect(collapsed.map((todo) => todo.id), [normal.id, current.id]);
  });

  test(
    'todo picker uses the latest overdue occurrence when anchor is absent',
    () {
      final oldOverdue = occurrence(13);
      final latestOverdue = occurrence(14);
      final future = occurrence(16);

      final collapsed = collapseRecurrenceSeriesForTodoPicker([
        oldOverdue,
        future,
        latestOverdue,
      ], now: today);

      expect(collapsed.single.id, latestOverdue.id);
    },
  );

  test('bound occurrence selects the aggregate row from the same series', () {
    final previous = occurrence(14);
    final current = occurrence(15, recurrence: RecurrenceType.daily);
    final unrelated = TodoItem(
      title: '其他循环',
      recurrenceSeriesId: 'other-series',
    );

    expect(areSameTodoOrRecurrenceSeries(previous, current), isTrue);
    expect(areSameTodoOrRecurrenceSeries(previous, unrelated), isFalse);
  });

  test('planning date selects the real occurrence on that date', () {
    final current = occurrence(15, recurrence: RecurrenceType.daily);
    final future = occurrence(16);

    final collapsed = collapseRecurrenceSeriesForTodoPicker([
      current,
      future,
    ], now: DateTime(2026, 7, 16, 9));

    expect(collapsed.single.id, future.id);
  });

  test('editing an existing plan preserves its bound occurrence', () {
    final previous = occurrence(14);
    final current = occurrence(15, recurrence: RecurrenceType.daily);

    final collapsed = collapseRecurrenceSeriesForTodoPicker(
      [previous, current],
      now: today,
      preferredTodoId: previous.id,
    );

    expect(collapsed.single.id, previous.id);
  });

  test('desktop widget keeps one actionable item for a recurrence series', () {
    final previous = occurrence(14);
    final current = occurrence(15, recurrence: RecurrenceType.daily);
    final future = occurrence(16);

    final collapsed = collapseRecurrenceSeriesForTodoPicker([
      previous,
      current,
      future,
    ], now: today);

    expect(collapsed, hasLength(1));
    expect(collapsed.single.id, current.id);
  });

  test('sortTodosForPicker orders by done, group, urgency, and title', () {
    final groups = [
      TodoGroup(id: 'g1', name: '第一组'),
      TodoGroup(id: 'g2', name: '第二组'),
    ];
    final tDone = TodoItem(
      id: 'done',
      title: 'A已完成',
      groupId: 'g1',
      isDone: true,
    );
    final tG2 = TodoItem(id: 'g2_item', title: '第二组任务', groupId: 'g2');
    final tUnknownGroup = TodoItem(
      id: 'unknown_g',
      title: '未知组任务',
      groupId: 'missing',
    );
    final tUnassigned = TodoItem(id: 'unassigned', title: '未分组任务');
    final tG1DueEarly = TodoItem(
      id: 'g1_due_early',
      title: 'Z早截止',
      groupId: 'g1',
      dueDate: DateTime(2026, 7, 15, 9),
    );
    final tG1CreatedMid = TodoItem(
      id: 'g1_created_mid',
      title: 'A中创建',
      groupId: 'g1',
      createdDate: DateTime(2026, 7, 15, 11).millisecondsSinceEpoch,
    );
    final tG1NoDateA = TodoItem(
      id: 'g1_nodate_a',
      title: 'A无时间',
      groupId: 'g1',
    );
    final tG1NoDateB = TodoItem(
      id: 'g1_nodate_b',
      title: 'B无时间',
      groupId: 'g1',
    );

    final sorted = sortTodosForPicker([
      tDone,
      tUnassigned,
      tG1NoDateB,
      tUnknownGroup,
      tG2,
      tG1CreatedMid,
      tG1NoDateA,
      tG1DueEarly,
    ], groups);

    expect(sorted.map((t) => t.id), [
      'g1_due_early',
      'g1_created_mid',
      'g1_nodate_a',
      'g1_nodate_b',
      'g2_item',
      'unknown_g',
      'unassigned',
      'done',
    ]);
  });
}
