import 'package:countdown_todo/models.dart';
import 'package:countdown_todo/services/todo_trash_multi_restore_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TodoItem todo(
    String id,
    int day, {
    String? seriesId,
    RecurrenceType recurrence = RecurrenceType.none,
    bool done = false,
    bool skipped = false,
    String? groupId,
    bool deleted = true,
  }) => TodoItem(
    id: id,
    title: id,
    recurrenceSeriesId: seriesId,
    recurrence: recurrence,
    isDone: done,
    isSkipped: skipped,
    isDeleted: deleted,
    groupId: groupId,
    createdDate: DateTime.utc(2026, 10, day, 9).millisecondsSinceEpoch,
  );

  test('跨普通待办和多个系列建立精确恢复范围并保留状态', () {
    final ordinary = todo(
      '00000000-0000-4000-8000-000000000001',
      18,
      done: true,
    );
    final seriesA = todo(
      '00000000-0000-4000-8000-000000000002',
      19,
      seriesId: '00000000-0000-4000-8000-000000000010',
      recurrence: RecurrenceType.daily,
      skipped: true,
    );
    final seriesB = todo(
      '00000000-0000-4000-8000-000000000003',
      20,
      seriesId: '00000000-0000-4000-8000-000000000011',
    );
    final unselected = todo(
      '00000000-0000-4000-8000-000000000004',
      21,
      seriesId: '00000000-0000-4000-8000-000000000010',
    );
    final todos = [ordinary, seriesA, seriesB, unselected];

    final plan = TodoTrashMultiRestoreService.tryPlan(
      todos: todos,
      selectedTodoIds: [ordinary.id, seriesA.id, seriesB.id, ordinary.id],
      activeGroupIds: const {},
    );

    expect(plan, isNotNull);
    expect(plan!.selectedTodoIds, {ordinary.id, seriesA.id, seriesB.id});
    expect(plan.preview.recordCount, 3);
    expect(plan.preview.seriesCount, 2);
    expect(plan.preview.completedCount, 1);
    expect(plan.preview.skippedCount, 1);
    expect(plan.preview.firstDate, DateTime(2026, 10, 18));
    expect(plan.preview.lastDate, DateTime(2026, 10, 20));
    expect(plan.restoredItems.every((item) => !item.isDeleted), isTrue);
    expect(
      plan.restoredItems.firstWhere((item) => item.id == ordinary.id).isDone,
      isTrue,
    );
    expect(
      plan.restoredItems.firstWhere((item) => item.id == seriesA.id).isSkipped,
      isTrue,
    );
    expect(plan.revivalBarrierIds, {seriesA.id, seriesB.id});
    expect(todos.every((item) => item.isDeleted), isTrue);
    expect(
      plan.restoredItems.firstWhere((item) => item.id == seriesA.id).recurrence,
      RecurrenceType.daily,
    );
    expect(plan.restoredItems.any((item) => item.id == unselected.id), isFalse);
  });

  test('失效文件夹解绑且其余字段保持原样', () {
    final deleted = todo(
      '00000000-0000-4000-8000-000000000005',
      18,
      groupId: 'missing-group',
      seriesId: '00000000-0000-4000-8000-000000000010',
    )..remark = '保留备注';

    final plan = TodoTrashMultiRestoreService.tryPlan(
      todos: [deleted],
      selectedTodoIds: [deleted.id],
      activeGroupIds: {'active-group'},
    );

    expect(plan, isNotNull);
    expect(plan!.restoredItems.single.groupId, isNull);
    expect(plan.restoredItems.single.remark, '保留备注');
    expect(deleted.isDeleted, isTrue);
    expect(deleted.groupId, 'missing-group');
  });

  test('空范围、缺失项目、活动项目和互斥状态都拒绝生成计划', () {
    final deleted = todo('00000000-0000-4000-8000-000000000006', 18);
    final active = todo(
      '00000000-0000-4000-8000-000000000007',
      19,
      deleted: false,
    );
    final invalid = todo(
      '00000000-0000-4000-8000-000000000008',
      20,
      skipped: true,
    )..isDone = true;

    expect(
      TodoTrashMultiRestoreService.tryPlan(
        todos: [deleted],
        selectedTodoIds: const [],
      ),
      isNull,
    );
    expect(
      TodoTrashMultiRestoreService.tryPlan(
        todos: [deleted],
        selectedTodoIds: ['missing'],
      ),
      isNull,
    );
    expect(
      TodoTrashMultiRestoreService.tryPlan(
        todos: [active],
        selectedTodoIds: [active.id],
      ),
      isNull,
    );
    expect(
      TodoTrashMultiRestoreService.tryPlan(
        todos: [invalid],
        selectedTodoIds: [invalid.id],
      ),
      isNull,
    );
  });
}
