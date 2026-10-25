import 'package:countdown_todo/models.dart';
import 'package:countdown_todo/storage_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/plan_availability_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late PlanAvailabilityFixture fixture;

  setUp(() async {
    fixture = PlanAvailabilityFixture();
    await fixture.initialize();
    await (await SharedPreferences.getInstance()).setInt('current_user_id', 42);
  });

  tearDown(() async => fixture.dispose());

  FixedScheduleItem schedule({
    String id = 'schedule-current',
    String teamUuid = 'team-a',
    String? seriesId,
  }) => FixedScheduleItem(
    id: id,
    title: '周会',
    date: '2026-10-08',
    startTime: DateTime(2026, 10, 8, 10).millisecondsSinceEpoch,
    endTime: DateTime(2026, 10, 8, 11).millisecondsSinceEpoch,
    teamUuid: teamUuid,
    recurrence: seriesId == null ? RecurrenceType.none : RecurrenceType.weekly,
    recurrenceSeriesId: seriesId,
  );

  Future<void> insertSchedule(FixedScheduleItem item) =>
      fixture.db.insert('fixed_schedules', item.toJson());

  TodoItem todo({
    String id = 'prep-todo',
    String teamUuid = 'team-a',
    RecurrenceType recurrence = RecurrenceType.none,
  }) => TodoItem(
    id: id,
    title: '准备议程',
    teamUuid: teamUuid,
    recurrence: recurrence,
  );

  test('原子保存待办、当前场次关系和两类 op log', () async {
    final baseline = schedule(seriesId: 'weekly-series');
    final nextOccurrence = schedule(
      id: 'schedule-next',
      seriesId: 'weekly-series',
    )..relatedTodoIds.add('unrelated-todo');
    await insertSchedule(baseline);
    await insertSchedule(nextOccurrence);

    final savedSchedule = await StorageService.saveTodoLinkedToFixedSchedule(
      PlanAvailabilityFixture.username,
      todo(),
      baseline,
      sync: false,
    );

    final storedTodo = await fixture.db.query(
      'todos',
      where: 'uuid = ?',
      whereArgs: ['prep-todo'],
    );
    final storedSchedule = await fixture.db.query(
      'fixed_schedules',
      where: 'uuid = ?',
      whereArgs: [baseline.id],
    );
    final untouchedOccurrence = await fixture.db.query(
      'fixed_schedules',
      where: 'uuid = ?',
      whereArgs: [nextOccurrence.id],
    );

    expect(storedTodo, hasLength(1));
    expect(storedTodo.single['content'], '准备议程');
    expect(FixedScheduleItem.fromJson(storedSchedule.single).relatedTodoIds, [
      'prep-todo',
    ]);
    expect(savedSchedule.version, baseline.version + 1);
    expect(
      FixedScheduleItem.fromJson(untouchedOccurrence.single).relatedTodoIds,
      ['unrelated-todo'],
    );
    expect(
      await fixture.db.query(
        'op_logs',
        where: 'target_uuid IN (?, ?)',
        whereArgs: ['prep-todo', baseline.id],
        orderBy: 'target_table ASC',
      ),
      hasLength(2),
    );
    expect(
      await fixture.db.query(
        'op_logs',
        where: 'target_table = ? AND target_uuid = ?',
        whereArgs: ['fixed_schedules', baseline.id],
      ),
      hasLength(1),
    );
  });

  test('日程快照过期时拒绝保存且不留下待办或 op log', () async {
    final baseline = schedule();
    await insertSchedule(baseline);
    await fixture.db.update(
      'fixed_schedules',
      {'title': '已改期的周会', 'version': baseline.version + 1},
      where: 'uuid = ?',
      whereArgs: [baseline.id],
    );

    await expectLater(
      StorageService.saveTodoLinkedToFixedSchedule(
        PlanAvailabilityFixture.username,
        todo(),
        baseline,
        sync: false,
      ),
      throwsA(isA<StateError>()),
    );

    expect(
      await fixture.db.query(
        'todos',
        where: 'uuid = ?',
        whereArgs: ['prep-todo'],
      ),
      isEmpty,
    );
    expect(await fixture.db.query('op_logs'), isEmpty);
  });

  test('团队范围不匹配或单次限制不满足时在写入前拒绝', () async {
    final baseline = schedule();
    await insertSchedule(baseline);

    await expectLater(
      StorageService.saveTodoLinkedToFixedSchedule(
        PlanAvailabilityFixture.username,
        todo(teamUuid: 'team-b'),
        baseline,
        sync: false,
      ),
      throwsA(isA<StateError>()),
    );
    await expectLater(
      StorageService.saveTodoLinkedToFixedSchedule(
        PlanAvailabilityFixture.username,
        todo(id: 'repeat-todo', recurrence: RecurrenceType.weekly),
        baseline,
        sync: false,
      ),
      throwsA(isA<ArgumentError>()),
    );

    expect(
      await fixture.db.query(
        'todos',
        where: "uuid IN ('prep-todo', 'repeat-todo')",
      ),
      isEmpty,
    );
    expect(await fixture.db.query('op_logs'), isEmpty);
  });

  test('固定日程写入失败会回滚待办、关系和双方 op log', () async {
    final baseline = schedule();
    await insertSchedule(baseline);
    await fixture.db.execute('''
      CREATE TRIGGER reject_linked_schedule_update
      BEFORE INSERT ON fixed_schedules
      WHEN NEW.uuid = 'schedule-current'
      BEGIN
        SELECT RAISE(ABORT, 'forced fixed schedule write failure');
      END
    ''');

    await expectLater(
      StorageService.saveTodoLinkedToFixedSchedule(
        PlanAvailabilityFixture.username,
        todo(),
        baseline,
        sync: false,
      ),
      throwsA(anything),
    );

    expect(
      await fixture.db.query(
        'todos',
        where: 'uuid = ?',
        whereArgs: ['prep-todo'],
      ),
      isEmpty,
    );
    expect(
      FixedScheduleItem.fromJson(
        (await fixture.db.query(
          'fixed_schedules',
          where: 'uuid = ?',
          whereArgs: [baseline.id],
        )).single,
      ).relatedTodoIds,
      isEmpty,
    );
    expect(await fixture.db.query('op_logs'), isEmpty);
  });

  test('账号切换后拒绝关联保存', () async {
    final baseline = schedule();
    await insertSchedule(baseline);
    await (await SharedPreferences.getInstance()).setString(
      'current_login_user',
      'another-account',
    );

    await expectLater(
      StorageService.saveTodoLinkedToFixedSchedule(
        PlanAvailabilityFixture.username,
        todo(),
        baseline,
        sync: false,
      ),
      throwsA(isA<StateError>()),
    );
    expect(
      await fixture.db.query(
        'todos',
        where: 'uuid = ?',
        whereArgs: ['prep-todo'],
      ),
      isEmpty,
    );
    expect(await fixture.db.query('op_logs'), isEmpty);
  });

  test('已取消的固定日程拒绝新建关联待办', () async {
    final baseline = schedule()..status = FixedScheduleStatus.cancelled;
    await insertSchedule(baseline);

    await expectLater(
      StorageService.saveTodoLinkedToFixedSchedule(
        PlanAvailabilityFixture.username,
        todo(),
        baseline,
        sync: false,
      ),
      throwsA(isA<StateError>()),
    );
    expect(
      await fixture.db.query(
        'todos',
        where: 'uuid = ?',
        whereArgs: ['prep-todo'],
      ),
      isEmpty,
    );
    expect(await fixture.db.query('op_logs'), isEmpty);
  });
}
