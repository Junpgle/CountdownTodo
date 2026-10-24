import 'package:countdown_todo/models.dart';
import 'package:countdown_todo/storage_service.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/plan_availability_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late PlanAvailabilityFixture fixture;

  setUp(() async {
    fixture = PlanAvailabilityFixture();
    await fixture.initialize();
  });

  tearDown(() async => fixture.dispose());

  Future<FixedScheduleItem> insertSchedule({
    required String id,
    required List<String> todoIds,
    required DateTime start,
    bool deleted = false,
  }) async {
    final item = FixedScheduleItem(
      id: id,
      title: '关联考试',
      date: '2026-10-08',
      startTime: start.millisecondsSinceEpoch,
      endTime: start.add(const Duration(hours: 2)).millisecondsSinceEpoch,
      relatedTodoIds: todoIds,
      isDeleted: deleted,
    );
    await fixture.db.insert('fixed_schedules', item.toJson());
    return item;
  }

  test('批量读取只返回精确关联且未删除的日程', () async {
    await insertSchedule(
      id: 'linked',
      todoIds: ['todo-1'],
      start: DateTime(2026, 10, 8, 10),
    );
    await insertSchedule(
      id: 'prefix-only',
      todoIds: ['todo-10'],
      start: DateTime(2026, 10, 8, 11),
    );
    await insertSchedule(
      id: 'deleted',
      todoIds: ['todo-1'],
      start: DateTime(2026, 10, 8, 12),
      deleted: true,
    );

    final result = await StorageService.getFixedSchedulesByRelatedTodos(
      PlanAvailabilityFixture.username,
      {'todo-1'},
    );

    expect(result.map((item) => item.id), ['linked']);
  });

  test('保存事务拒绝已变化的关联固定日程并保持待办未写入', () async {
    await fixture.todo('todo-review', '准备考试材料', due: DateTime(2026, 10, 8, 8));
    final before = (await StorageService.getTodos(
      PlanAvailabilityFixture.username,
    )).singleWhere((item) => item.id == 'todo-review');
    final schedule = await insertSchedule(
      id: 'schedule-review',
      todoIds: [before.id],
      start: DateTime(2026, 10, 8, 10),
    );
    final snapshots = await StorageService.getFixedSchedulesByRelatedTodos(
      PlanAvailabilityFixture.username,
      {before.id},
    );
    expect(snapshots.map((item) => item.id), [schedule.id]);

    final changedSchedule = FixedScheduleItem.fromJson(schedule.toJson())
      ..startTime = DateTime(2026, 10, 8, 11).millisecondsSinceEpoch;
    changedSchedule.markAsChanged();
    await fixture.db.update(
      'fixed_schedules',
      changedSchedule.toJson(),
      where: 'uuid = ?',
      whereArgs: [schedule.id],
    );
    final changedTodo = TodoItem.fromJson(before.toJson())
      ..dueDate = DateTime(2026, 10, 8, 12)
      ..markAsChanged();

    await expectLater(
      StorageService.saveTodos(
        PlanAvailabilityFixture.username,
        [changedTodo],
        expectedTodoBaselines: {before.id: before},
        expectedFixedScheduleTodoIds: {before.id},
        expectedFixedScheduleBaselines: snapshots,
      ),
      throwsA(isA<StateError>()),
    );

    final stored = (await StorageService.getTodos(
      PlanAvailabilityFixture.username,
    )).singleWhere((item) => item.id == before.id);
    expect(stored.dueDate, before.dueDate);
  });

  test('空的关联快照也会阻止并发新增关联日程后使用旧复核保存', () async {
    await fixture.todo(
      'todo-empty-review',
      '准备材料',
      due: DateTime(2026, 10, 8, 8),
    );
    final before = (await StorageService.getTodos(
      PlanAvailabilityFixture.username,
    )).singleWhere((item) => item.id == 'todo-empty-review');
    final emptySnapshot = await StorageService.getFixedSchedulesByRelatedTodos(
      PlanAvailabilityFixture.username,
      {before.id},
    );
    expect(emptySnapshot, isEmpty);
    await insertSchedule(
      id: 'late-linked-schedule',
      todoIds: [before.id],
      start: DateTime(2026, 10, 8, 10),
    );
    final changedTodo = TodoItem.fromJson(before.toJson())
      ..dueDate = DateTime(2026, 10, 8, 12)
      ..markAsChanged();

    await expectLater(
      StorageService.saveTodos(
        PlanAvailabilityFixture.username,
        [changedTodo],
        expectedTodoBaselines: {before.id: before},
        expectedFixedScheduleTodoIds: {before.id},
        expectedFixedScheduleBaselines: emptySnapshot,
      ),
      throwsA(isA<StateError>()),
    );
  });
}
