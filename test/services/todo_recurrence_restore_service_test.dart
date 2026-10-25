import 'package:countdown_todo/models.dart';
import 'package:countdown_todo/services/todo_recurrence_restore_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const seriesId = '00000000-0000-4000-8000-000000000027';

  TodoItem occurrence(
    String id,
    int day, {
    RecurrenceType recurrence = RecurrenceType.none,
    bool done = false,
    bool skipped = false,
    String? groupId,
    bool deleted = true,
    String title = '每日复习',
  }) => TodoItem(
    id: id,
    title: title,
    recurrence: recurrence,
    recurrenceSeriesId: seriesId,
    isDeleted: deleted,
    isDone: done,
    isSkipped: skipped,
    groupId: groupId,
    createdDate: DateTime.utc(2026, 10, day, 9).millisecondsSinceEpoch,
  );

  test('完整回收站系列可整组恢复并保留状态及规则', () {
    final rows = [
      occurrence(seriesId, 18, recurrence: RecurrenceType.daily, done: true),
      occurrence('00000000-0000-4000-8000-000000000028', 19, skipped: true),
      occurrence('00000000-0000-4000-8000-000000000029', 20),
    ];

    final plan = TodoRecurrenceRestoreService.tryPlan(
      todos: rows,
      seriesId: seriesId,
    );

    expect(plan, isNotNull);
    expect(plan!.expectedMemberIds, rows.map((todo) => todo.id).toSet());
    expect(plan.preview.recordCount, 3);
    expect(plan.preview.occurrenceCount, 3);
    expect(plan.preview.completedCount, 1);
    expect(plan.preview.skippedCount, 1);
    expect(plan.preview.firstDate, DateTime(2026, 10, 18));
    expect(plan.preview.lastDate, DateTime(2026, 10, 20));
    expect(plan.restoredItems.every((todo) => !todo.isDeleted), isTrue);
    expect(plan.restoredItems.first.isDone, isTrue);
    expect(plan.restoredItems[1].isSkipped, isTrue);
    expect(plan.restoredItems.first.recurrence, RecurrenceType.daily);
    expect(
      plan.restoredItems.where(
        (todo) => todo.recurrence != RecurrenceType.none,
      ),
      hasLength(1),
    );
    expect(rows.every((todo) => todo.isDeleted), isTrue);
  });

  test('失效文件夹解绑，活动文件夹和其它数据保持原样', () {
    final rows = [
      occurrence(seriesId, 18, recurrence: RecurrenceType.weekly),
      occurrence(
        '00000000-0000-4000-8000-000000000028',
        25,
        groupId: 'missing-group',
        title: '每周复习',
      ),
    ];

    final plan = TodoRecurrenceRestoreService.tryPlan(
      todos: rows,
      seriesId: seriesId,
      activeGroupIds: {'active-group'},
    );

    expect(plan, isNotNull);
    expect(plan!.restoredItems.first.groupId, isNull);
    expect(plan.restoredItems.last.title, '每周复习');
  });

  test('活动成员存在时只允许逐期恢复', () {
    final rows = [
      occurrence(seriesId, 18, recurrence: RecurrenceType.daily),
      occurrence('00000000-0000-4000-8000-000000000028', 19, deleted: false),
    ];

    expect(
      TodoRecurrenceRestoreService.tryPlan(todos: rows, seriesId: seriesId),
      isNull,
    );
  });

  test('规则缺失或重复时不猜测恢复规则', () {
    final root = occurrence(seriesId, 18);
    final next = occurrence('00000000-0000-4000-8000-000000000028', 19);

    expect(
      TodoRecurrenceRestoreService.tryPlan(
        todos: [root, next],
        seriesId: seriesId,
      ),
      isNull,
    );
    root.recurrence = RecurrenceType.daily;
    next.recurrence = RecurrenceType.weekly;
    expect(
      TodoRecurrenceRestoreService.tryPlan(
        todos: [root, next],
        seriesId: seriesId,
      ),
      isNull,
    );
  });

  test('单条、同日重复和无效双状态不显示整组恢复', () {
    final rule = occurrence(seriesId, 18, recurrence: RecurrenceType.daily);
    expect(
      TodoRecurrenceRestoreService.tryPlan(todos: [rule], seriesId: seriesId),
      isNull,
    );
    final duplicate = occurrence('00000000-0000-4000-8000-000000000028', 18);
    expect(
      TodoRecurrenceRestoreService.tryPlan(
        todos: [rule, duplicate],
        seriesId: seriesId,
      ),
      isNull,
    );
    final invalid = occurrence(
      '00000000-0000-4000-8000-000000000029',
      19,
      skipped: true,
    )..isDone = true;
    expect(
      TodoRecurrenceRestoreService.tryPlan(
        todos: [rule, invalid],
        seriesId: seriesId,
      ),
      isNull,
    );
  });
}
