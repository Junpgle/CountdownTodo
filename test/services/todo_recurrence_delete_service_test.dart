import 'package:countdown_todo/models.dart';
import 'package:countdown_todo/services/todo_recurrence_delete_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  String todoId(String id) => '$id-0000-4000-8000-000000000000';

  TodoItem occurrence(
    String id,
    int day, {
    RecurrenceType recurrence = RecurrenceType.none,
    bool done = false,
    bool skipped = false,
    String seriesId = 'series-a',
  }) => TodoItem(
    id: todoId(id),
    title: id,
    recurrence: recurrence,
    recurrenceSeriesId: seriesId,
    isDone: done,
    isSkipped: skipped,
    createdDate: DateTime(2026, 10, day).toUtc().millisecondsSinceEpoch,
  );

  Map<String, TodoItem> byId(Iterable<TodoItem> todos) => {
    for (final todo in todos) todo.id: todo,
  };

  test('仅本期删除规则承载项时把规则移交后续期并保护日期墓碑', () {
    final staleRuleOwner = occurrence(
      'stale-rule-owner',
      19,
      recurrence: RecurrenceType.weekly,
    );
    final root = occurrence('root', 20, recurrence: RecurrenceType.daily);
    final current = occurrence('current', 20, done: true);
    final next = occurrence('next', 21, skipped: true);
    final deletedDuplicate = occurrence('deleted-duplicate', 20)
      ..isDeleted = true;

    final plan = TodoRecurrenceDeleteService.plan(
      todos: [staleRuleOwner, root, current, next, deletedDuplicate],
      todoId: todoId('root'),
      scope: TodoRecurrenceDeleteScope.occurrence,
    );
    final changed = byId(plan.changedItems);

    expect(plan.preview.occurrenceCount, 1);
    expect(plan.preview.recordCount, 2);
    expect(plan.preview.completedCount, 1);
    expect(plan.affectedIds, {todoId('root'), todoId('current')});
    expect(plan.revivalBarrierIds, {
      todoId('root'),
      todoId('current'),
      todoId('deleted-duplicate'),
    });
    expect(changed[todoId('root')]!.isDeleted, isTrue);
    expect(changed[todoId('root')]!.recurrence, RecurrenceType.none);
    expect(
      changed[todoId('stale-rule-owner')]!.recurrence,
      RecurrenceType.none,
    );
    expect(changed[todoId('current')]!.isDone, isTrue);
    expect(changed[todoId('current')]!.isDeleted, isTrue);
    expect(changed[todoId('next')]!.recurrence, RecurrenceType.daily);
    expect(changed[todoId('next')]!.isSkipped, isTrue);
  });

  test('本期及以后保留此前期次并把截止收口到最后保留期', () {
    final past = occurrence('past', 18);
    final current = occurrence('current', 19);
    final selected = occurrence('selected', 20, skipped: true);
    final future = occurrence('future', 21);
    final activeRoot = past..recurrence = RecurrenceType.daily;

    final plan = TodoRecurrenceDeleteService.plan(
      todos: [activeRoot, current, selected, future],
      todoId: todoId('selected'),
      scope: TodoRecurrenceDeleteScope.future,
    );
    final changed = byId(plan.changedItems);

    expect(plan.preview.occurrenceCount, 2);
    expect(plan.preview.skippedCount, 1);
    expect(plan.affectedIds, {todoId('selected'), todoId('future')});
    expect(changed[todoId('past')]!.recurrence, RecurrenceType.none);
    expect(changed[todoId('current')]!.recurrence, RecurrenceType.daily);
    expect(
      changed[todoId('current')]!.recurrenceEndDate,
      DateTime(2026, 10, 19),
    );
    expect(changed[todoId('selected')]!.isDeleted, isTrue);
    expect(changed[todoId('future')]!.isDeleted, isTrue);
  });

  test('本期之前没有保留记录时按整个系列移入回收站', () {
    final current = occurrence(
      'current',
      20,
      recurrence: RecurrenceType.daily,
      done: true,
    );
    final future = occurrence('future', 21, skipped: true);

    final plan = TodoRecurrenceDeleteService.plan(
      todos: [current, future],
      todoId: todoId('current'),
      scope: TodoRecurrenceDeleteScope.future,
    );
    final changed = byId(plan.changedItems);

    expect(plan.affectedIds, {todoId('current'), todoId('future')});
    expect(changed.values.every((todo) => todo.isDeleted), isTrue);
    expect(changed[todoId('current')]!.recurrence, RecurrenceType.daily);
    expect(plan.preview.completedCount, 1);
    expect(plan.preview.skippedCount, 1);
  });

  test('整系列删除保留原期次数据和恢复所需的规则', () {
    final past = occurrence(
      'past',
      19,
      recurrence: RecurrenceType.weekly,
      done: true,
    );
    final future = occurrence('future', 20, skipped: true);

    final plan = TodoRecurrenceDeleteService.plan(
      todos: [past, future],
      todoId: todoId('past'),
      scope: TodoRecurrenceDeleteScope.series,
    );
    final changed = byId(plan.changedItems);

    expect(changed.values.every((todo) => todo.isDeleted), isTrue);
    expect(changed[todoId('past')]!.isDone, isTrue);
    expect(changed[todoId('past')]!.recurrence, RecurrenceType.weekly);
    expect(changed[todoId('future')]!.isSkipped, isTrue);
    expect(plan.preview.occurrenceCount, 2);
    expect(plan.preview.completedCount, 1);
    expect(plan.preview.skippedCount, 1);
  });
}
