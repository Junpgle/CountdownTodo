import 'dart:convert';

import 'package:countdown_todo/models.dart';
import 'package:countdown_todo/models/plan_availability.dart';
import 'package:countdown_todo/services/missed_plan_recovery_service.dart';
import 'package:countdown_todo/services/plan_availability_repository.dart';
import 'package:countdown_todo/services/plan_availability_service.dart';
import 'package:countdown_todo/services/pomodoro_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:flutter/services.dart';
import 'package:countdown_todo/services/device_calendar_read_service.dart';

import '../support/plan_availability_fixture.dart';

class MutatingAvailability extends PlanAvailabilityRepository {
  MutatingAvailability(Database db, this.mutation)
    : super(databaseOverride: db, clock: () => PlanAvailabilityFixture.now);
  final Future<void> Function() mutation;
  int reads = 0;
  @override
  Future<PlanAvailabilitySnapshot> read(
    PlanAvailabilityQuery query, {
    bool forceRefresh = false,
    bool requireCalendar = false,
  }) async {
    final result = await super.read(
      query,
      forceRefresh: forceRefresh,
      requireCalendar: requireCalendar,
    );
    if (++reads == 2) await mutation();
    return result;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final day = PlanAvailabilityFixture.day;
  DateTime at(int hour) => day.add(Duration(hours: hour));
  late PlanAvailabilityFixture fixture;
  late MissedPlanRecoveryService service;
  late TodoPlanBlock source;
  late MissedPlanRecoveryContext context;
  setUp(() async {
    fixture = PlanAvailabilityFixture();
    await fixture.initialize();
    source = TodoPlanBlock(
      id: 'missed-source',
      todoId: 'todo-target',
      titleSnapshot: '旧标题',
      startTime: day.subtract(const Duration(days: 2)).millisecondsSinceEpoch,
      endTime: day
          .subtract(const Duration(days: 2))
          .add(const Duration(minutes: 45))
          .millisecondsSinceEpoch,
      plannedMinutes: 45,
      actualFocusSeconds: 600,
      status: TodoPlanStatus.missed,
      source: TodoPlanSource.ai,
      remark: '先复习错题',
      reminderMinutes: 15,
      pomodoroMinutes: 30,
      pomodoroRounds: 2,
      calendarEventId: 'old-event',
      pomodoroRecordIds: ['old-focus'],
      version: 8,
      deviceId: 'old-device',
    );
    await fixture.block(source);
    service = MissedPlanRecoveryService(
      databaseOverride: fixture.db,
      clock: () => PlanAvailabilityFixture.now,
    );
    context = await service.read(PlanAvailabilityFixture.username, source.id);
  });
  tearDown(() => fixture.dispose());

  Future<int> count(String table) async =>
      (await fixture.db.query(table)).length;
  Future<TodoPlanBlock> save({
    TodoPlanBlock? draft,
    PlanAvailabilitySelection? selected,
    PlanAvailabilityQuery? query,
    MissedPlanRecoveryService? via,
  }) => (via ?? service).save(
    context,
    draft ?? context.draft(at(10)),
    selected,
    manualQuery: query,
    sync: false,
  );
  Future<void> zeroWrites(Future<dynamic> action) async {
    final failure = expectLater(action, throwsA(anything));
    final blocks = await fixture.db.query('todo_plan_blocks');
    final logs = await fixture.db.query('op_logs');
    await failure;
    expect(await fixture.db.query('todo_plan_blocks'), blocks);
    expect(await fixture.db.query('op_logs'), logs);
  }

  test('45分钟重新安排白名单继承，新身份，历史和待办逐字段不变', () async {
    final old = await fixture.db.query('todo_plan_blocks');
    final todos = await fixture.db.query('todos');
    final query = PlanAvailabilityQuery(
      username: context.username,
      todoId: context.todo.id,
      date: day,
      minutes: 45,
    );
    final snapshot = await service.availability.read(query);
    final slot = PlanAvailabilityService.find(
      query,
      snapshot,
      now: service.now,
    ).slots.first;
    final draft = context.draft(slot.start);
    draft.actualFocusSeconds = 900;
    draft.calendarEventId = 'injected';
    draft.pomodoroRecordIds = ['injected'];
    draft.version = 40;
    final saved = await save(
      draft: draft,
      selected: PlanAvailabilitySelection(query, slot, snapshot),
    );
    expect(saved.id, isNot(source.id));
    expect(saved.todoId, 'todo-target');
    expect(saved.plannedMinutes, 45);
    expect(saved.titleSnapshot, '复习高数');
    expect(saved.remark, source.remark);
    expect(saved.reminderMinutes, 15);
    expect(saved.pomodoroMinutes, 30);
    expect(saved.pomodoroRounds, 2);
    expect(saved.status, TodoPlanStatus.planned);
    expect(saved.source, TodoPlanSource.manual);
    expect(saved.actualFocusSeconds, 0);
    expect(saved.calendarEventId, isNull);
    expect(saved.pomodoroRecordIds, isEmpty);
    expect(saved.version, 1);
    expect(saved.deviceId, isNull);
    expect(
      await fixture.db.query(
        'todo_plan_blocks',
        where: 'uuid = ?',
        whereArgs: [source.id],
      ),
      old,
    );
    expect(await fixture.db.query('todos'), todos);
    expect(await count('op_logs'), 1);
    final payload = jsonDecode(
      (await fixture.db.query('op_logs')).single['data_json'] as String,
    );
    expect(payload['actual_focus_seconds'], 0);
    expect(payload['calendar_event_id'], '');
  });

  test('打开查找和选用不写入；重复保存同UUID拒绝', () async {
    final draft = context.draft(at(10));
    expect(await count('op_logs'), 0);
    expect(await count('todo_plan_blocks'), 1);
    await save(draft: draft);
    context.acknowledgeFollowups();
    await zeroWrites(save(draft: draft));
  });

  test('已有安排显式确认，未看过的新安排及改动再次阻止', () async {
    final later = TodoPlanBlock(
      id: 'later',
      todoId: source.todoId,
      startTime: at(16).millisecondsSinceEpoch,
      endTime: at(17).millisecondsSinceEpoch,
    );
    await fixture.block(later);
    context = await service.read(context.username, source.id);
    expect(context.followups.single.id, 'later');
    await zeroWrites(save());
    context.acknowledgeFollowups();
    await service.validate(context);
    await fixture.db.update(
      'todo_plan_blocks',
      {'remark': '修改'},
      where: 'uuid = ?',
      whereArgs: ['later'],
    );
    await zeroWrites(save());
    final latest = await service.read(context.username, source.id);
    latest.acknowledgeFollowups();
    context.acknowledgedFollowups.addAll(latest.acknowledgedFollowups);
    await save();
  });

  for (final change in ['remark', 'status', 'todo_uuid', 'is_deleted']) {
    test('来源$change变化停止写入', () async {
      await fixture.db.update(
        'todo_plan_blocks',
        {
          change: switch (change) {
            'status' => TodoPlanStatus.finished.index,
            'is_deleted' => 1,
            'todo_uuid' => 'another',
            _ => 'changed',
          },
        },
        where: 'uuid = ?',
        whereArgs: [source.id],
      );
      await zeroWrites(save());
    });
  }
  for (final change in ['is_completed', 'is_deleted', 'has_conflict']) {
    test('目标待办$change变化停止写入', () async {
      await fixture.db.update(
        'todos',
        {change: 1},
        where: 'uuid = ?',
        whereArgs: [source.todoId],
      );
      await zeroWrites(save());
    });
  }
  test('账号切换和虚拟来源拒绝', () async {
    await expectLater(
      service.read(context.username, 'virtual-course'),
      throwsA(isA<MissedPlanRecoveryException>()),
    );
    await (await SharedPreferences.getInstance()).setString(
      'current_login_user',
      'another',
    );
    await zeroWrites(save());
  });
  test('当前规划专注以及未更新规划状态的运行会话都阻止', () async {
    await fixture.block(
      TodoPlanBlock(
        id: 'focusing',
        todoId: source.todoId,
        startTime: at(16).millisecondsSinceEpoch,
        endTime: at(17).millisecondsSinceEpoch,
        status: TodoPlanStatus.focusing,
      ),
    );
    expect(
      (await service.read(context.username, source.id)).hasCurrentFocus,
      isTrue,
    );
    await zeroWrites(save());
    await fixture.db.delete(
      'todo_plan_blocks',
      where: 'uuid = ?',
      whereArgs: ['focusing'],
    );
    await PomodoroService.saveRunState(
      PomodoroRunState(
        phase: PomodoroPhase.focusing,
        todoUuid: source.todoId,
        planBlockId: 'unmarked',
        targetEndMs: at(16).millisecondsSinceEpoch,
        currentCycle: 1,
        totalCycles: 1,
        focusSeconds: 1500,
        breakSeconds: 300,
      ),
    );
    await zeroWrites(save());
  });
  test('重复待办保留原实例，更新标题使用最新值', () async {
    await fixture.db.update(
      'todos',
      {'recurrence': 1, 'recurrence_series_id': 'series'},
      where: 'uuid = ?',
      whereArgs: [source.todoId],
    );
    await fixture.todo('next-instance', '下一期');
    await fixture.db.update(
      'todos',
      {'content': '新的标题'},
      where: 'uuid = ?',
      whereArgs: [source.todoId],
    );
    final saved = await save();
    expect(saved.todoId, source.todoId);
    expect(saved.titleSnapshot, '新的标题');
    final invalid = context.draft(at(12))..todoId = 'next-instance';
    await zeroWrites(save(draft: invalid));
  });
  test('过期截止阻止，日期截止允许至当天结束', () async {
    await fixture.db.update(
      'todos',
      {'due_date': service.now.millisecondsSinceEpoch},
      where: 'uuid = ?',
      whereArgs: [source.todoId],
    );
    await zeroWrites(save());
    await fixture.db.update(
      'todos',
      {'due_date': day.millisecondsSinceEpoch, 'is_all_day': 1},
      where: 'uuid = ?',
      whereArgs: [source.todoId],
    );
    final draft = context.draft(at(23))
      ..endTime = at(24).millisecondsSinceEpoch;
    await save(draft: draft);
  });
  test('手动安排也检查占用、避让、跨日、截止和时间流逝', () async {
    await fixture.course('busy', day, 1000, 1100);
    await zeroWrites(save());
    await fixture.db.delete('courses');
    final avoid = PlanAvailabilityQuery(
      username: context.username,
      todoId: source.todoId,
      date: day,
      minutes: 45,
      avoidWindows: [const PlanDailyTimeWindow('午休', 720, 840)],
    );
    await zeroWrites(save(draft: context.draft(at(12)), query: avoid));
    await zeroWrites(
      save(
        draft: context.draft(at(23))..endTime = at(25).millisecondsSinceEpoch,
      ),
    );
    await fixture.db.update(
      'todos',
      {'due_date': at(10).millisecondsSinceEpoch},
      where: 'uuid = ?',
      whereArgs: [source.todoId],
    );
    await zeroWrites(save());
    await fixture.db.update(
      'todos',
      {'due_date': null},
      where: 'uuid = ?',
      whereArgs: [source.todoId],
    );
    final later = MissedPlanRecoveryService(
      databaseOverride: fixture.db,
      clock: () => at(10).add(const Duration(seconds: 1)),
    );
    await zeroWrites(save(via: later));
  });
  test('事务内重新检查来源，写入异常完整回滚', () async {
    final mutating = MissedPlanRecoveryService(
      databaseOverride: fixture.db,
      clock: () => PlanAvailabilityFixture.now,
      availabilityOverride: MutatingAvailability(fixture.db, () async {
        await fixture.db.update(
          'todo_plan_blocks',
          {'remark': '同步变化'},
          where: 'uuid = ?',
          whereArgs: [source.id],
        );
      }),
    );
    await expectLater(
      save(via: mutating),
      throwsA(isA<MissedPlanRecoveryException>()),
    );
    expect(await count('todo_plan_blocks'), 1);
    expect(await count('op_logs'), 0);
    context = await service.read(context.username, source.id);
    await fixture.db.execute(
      "CREATE TRIGGER fail_recovery_op BEFORE INSERT ON op_logs BEGIN SELECT RAISE(ABORT, 'test rollback'); END",
    );
    await zeroWrites(save());
  });
  test('旧配置使用支持的默认值且提示，原记录不修写', () async {
    await fixture.db.update(
      'todo_plan_blocks',
      {
        'planned_minutes': 2000,
        'reminder_minutes': 7,
        'pomodoro_minutes': 17,
        'pomodoro_rounds': 20,
      },
      where: 'uuid = ?',
      whereArgs: [source.id],
    );
    context = await service.read(context.username, source.id);
    expect(context.minutes, 45);
    expect(context.notices, hasLength(2));
    final saved = await save();
    expect(saved.reminderMinutes, 5);
    expect(saved.pomodoroMinutes, 25);
    expect(saved.pomodoroRounds, 0);
  });
  test('手机日历读取失败阻止推荐和手动保存，显式应用内模式才放行', () async {
    DeviceCalendarReadService.debugIsSupportedOverride = true;
    await DeviceCalendarReadService.setEnabled(true);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('countdown_todo/device_calendar_read'),
          (call) async {
            if (call.method == 'checkPermission') return true;
            throw PlatformException(code: 'synthetic-provider-failure');
          },
        );
    await zeroWrites(save());
    final query = PlanAvailabilityQuery(
      username: context.username,
      todoId: source.todoId,
      date: day,
      minutes: 45,
      appOnly: true,
    );
    final saved = await save(query: query);
    expect(saved.titleSnapshot, '复习高数');
    expect(await count('op_logs'), 1);
  });
  test('事务前出现未展示的后续安排，即使时段不冲突也拒绝', () async {
    final via = MissedPlanRecoveryService(
      databaseOverride: fixture.db,
      clock: () => PlanAvailabilityFixture.now,
      availabilityOverride: MutatingAvailability(fixture.db, () async {
        await fixture.block(
          TodoPlanBlock(
            id: 'unseen',
            todoId: source.todoId,
            startTime: at(18).millisecondsSinceEpoch,
            endTime: at(19).millisecondsSinceEpoch,
          ),
        );
      }),
    );
    await expectLater(
      save(via: via),
      throwsA(isA<MissedPlanRecoveryException>()),
    );
    expect(await count('op_logs'), 0);
    expect(await count('todo_plan_blocks'), 2);
  });
  test('午夜切换拒绝旧日期，来源或待办硬删除均拒绝', () async {
    final midnight = MissedPlanRecoveryService(
      databaseOverride: fixture.db,
      clock: () => at(24),
    );
    await zeroWrites(save(via: midnight));
    await fixture.db.delete(
      'todos',
      where: 'uuid = ?',
      whereArgs: [source.todoId],
    );
    await zeroWrites(save());
    await fixture.todo(source.todoId, '复习高数');
    await fixture.db.delete(
      'todo_plan_blocks',
      where: 'uuid = ?',
      whereArgs: [source.id],
    );
    await zeroWrites(save());
  });
}
