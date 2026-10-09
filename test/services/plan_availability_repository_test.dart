import 'dart:convert';

import 'package:countdown_todo/models.dart';
import 'package:countdown_todo/models/plan_availability.dart';
import 'package:countdown_todo/services/course_calendar_adjustment_service.dart';
import 'package:countdown_todo/services/database_helper.dart';
import 'package:countdown_todo/services/device_calendar_read_service.dart';
import 'package:countdown_todo/services/plan_availability_repository.dart';
import 'package:countdown_todo/services/plan_availability_service.dart';
import 'package:countdown_todo/storage_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/plan_availability_fixture.dart';

DateTime at(int hour, [int minute = 0]) => DateTime(2026, 10, 8, hour, minute);
PlanAvailabilityQuery query({
  String todo = 'todo-target',
  String? editing,
  bool appOnly = false,
}) => PlanAvailabilityQuery(
  username: PlanAvailabilityFixture.username,
  todoId: todo,
  date: PlanAvailabilityFixture.day,
  minutes: 45,
  excludeBlockId: editing,
  appOnly: appOnly,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late PlanAvailabilityFixture fixture;
  late PlanAvailabilityRepository repository;
  setUp(() async {
    fixture = PlanAvailabilityFixture();
    await fixture.initialize();
    repository = PlanAvailabilityRepository(
      databaseOverride: fixture.db,
      clock: () => PlanAvailabilityFixture.now,
    );
  });
  tearDown(() => fixture.dispose());
  Future<PlanAvailabilitySelection> choose(PlanAvailabilityQuery q) async {
    final snapshot = await repository.read(q);
    final slot = PlanAvailabilityService.find(
      q,
      snapshot,
      now: PlanAvailabilityFixture.now,
    ).slots.first;
    return PlanAvailabilitySelection(q, slot, snapshot);
  }

  TodoPlanBlock draft(PlanAvailabilitySelection s, {String id = 'new-block'}) =>
      TodoPlanBlock(
        id: id,
        todoId: s.query.todoId,
        startTime: s.slot.start.millisecondsSinceEpoch,
        endTime: s.slot.end.millisecondsSinceEpoch,
        plannedMinutes: s.slot.minutes,
      );

  test('真实隔离表同时适配课程、固定日程及规划，返回精确示例', () async {
    await fixture.course('course-one', at(0), 900, 1000);
    await fixture.fixed('fixed-one', at(11), at(12));
    await fixture.block(
      TodoPlanBlock(
        id: 'plan-one',
        todoId: 'todo-target',
        startTime: at(14).millisecondsSinceEpoch,
        endTime: at(15).millisecondsSinceEpoch,
      ),
    );
    final snapshot = await repository.read(query());
    expect(snapshot.busy.map((i) => i.source).toSet(), {
      PlanBusySource.course,
      PlanBusySource.fixedSchedule,
      PlanBusySource.planBlock,
    });
    expect(
      PlanAvailabilityService.find(
        query(),
        snapshot,
        now: PlanAvailabilityFixture.now,
      ).slots.map((i) => i.start),
      [at(8), at(10), at(12), at(12, 45), at(15)],
    );
    expect(await fixture.db.query('op_logs'), isEmpty);
  });
  test('跨日固定日程及规划不漏，当前UUID排除，其他同待办规划保留', () async {
    await fixture.fixed('overnight-fixed', DateTime(2026, 10, 7, 23), at(9));
    await fixture.block(
      TodoPlanBlock(
        id: 'overnight-plan',
        todoId: 'todo-target',
        startTime: DateTime(2026, 10, 7, 22).millisecondsSinceEpoch,
        endTime: at(10).millisecondsSinceEpoch,
      ),
    );
    await fixture.block(
      TodoPlanBlock(
        id: 'editing-plan',
        todoId: 'todo-target',
        startTime: at(10).millisecondsSinceEpoch,
        endTime: at(11).millisecondsSinceEpoch,
      ),
    );
    final q = query(editing: 'editing-plan');
    final snapshot = await repository.read(q);
    expect(snapshot.busy.any((i) => i.id == 'editing-plan'), isFalse);
    expect(snapshot.busy.any((i) => i.id == 'overnight-plan'), isTrue);
    expect(
      PlanAvailabilityService.find(
        q,
        snapshot,
        now: PlanAvailabilityFixture.now,
      ).slots.first.start,
      at(10),
    );
  });
  test('完成、取消、漏做和跳过不占用，时间待定记录可见', () async {
    for (final status in [
      TodoPlanStatus.finished,
      TodoPlanStatus.cancelled,
      TodoPlanStatus.missed,
      TodoPlanStatus.skipped,
    ]) {
      await fixture.block(
        TodoPlanBlock(
          id: 'plan-${status.name}',
          todoId: 'todo-target',
          startTime: at(8).millisecondsSinceEpoch,
          endTime: at(20).millisecondsSinceEpoch,
          status: status,
        ),
      );
    }
    await fixture.db.insert(
      'fixed_schedules',
      FixedScheduleItem(
        id: 'fixed-tbd',
        title: '时间待定会议',
        date: '2026-10-08',
      ).toJson(),
    );
    await fixture.course('course-tbd', at(0), 0, 0);
    final snapshot = await repository.read(query());
    expect(snapshot.busy, isEmpty);
    expect(snapshot.unknownTimes, hasLength(2));
  });
  test('截止、日期待办本身不占用，真实旧区间去重', () async {
    await fixture.todo('todo-date', '当天提交', due: at(0), allDay: true);
    await fixture.todo('todo-deadline', '定时提交', due: at(18));
    await fixture.todo('todo-legacy', '旧区间', due: at(10), legacyStart: at(9));
    var snapshot = await repository.read(query());
    expect(snapshot.busy.single.source, PlanBusySource.legacyTodo);
    await fixture.block(
      TodoPlanBlock(
        id: 'legacy-plan',
        todoId: 'todo-legacy',
        startTime: at(12).millisecondsSinceEpoch,
        endTime: at(13).millisecondsSinceEpoch,
      ),
    );
    snapshot = await repository.read(query());
    expect(snapshot.busy.map((i) => i.source), [PlanBusySource.planBlock]);
  });
  test('跨日截止待办与零开始占位不能把空闲日整天占满', () async {
    // The calendar only projects same-day legacy execution ranges. A deadline
    // spanning days is not an all-day execution reservation.
    await fixture.todo(
      'long-deadline',
      '下周交论文',
      legacyStart: DateTime(2026, 10, 1, 9),
      due: DateTime(2026, 10, 15, 18),
    );
    await fixture.todo('zero-start', '只设截止', due: at(20));
    await fixture.db.update(
      'todos',
      {'created_date': 0},
      where: 'uuid = ?',
      whereArgs: ['zero-start'],
    );
    final snapshot = await repository.read(query());
    expect(snapshot.busy, isEmpty);
    expect(
      PlanAvailabilityService.find(
        query(),
        snapshot,
        now: PlanAvailabilityFixture.now,
      ).slots.first.start,
      at(8),
    );
    final choice = PlanAvailabilitySelection(
      query(),
      PlanAvailabilityService.find(
        query(),
        snapshot,
        now: PlanAvailabilityFixture.now,
      ).slots.first,
      snapshot,
    );
    await repository.save(choice, draft(choice), sync: false);
    expect(await fixture.db.query('op_logs'), hasLength(1));
  });
  test('物理创建时间兜底不是旧执行时间，真实同日区间仍占用', () async {
    await fixture.todo(
      'creation-anchor',
      '晚点提交',
      due: at(20),
      legacyStart: at(7),
    );
    await fixture.db.update(
      'todos',
      {'created_at': at(7).millisecondsSinceEpoch},
      where: 'uuid = ?',
      whereArgs: ['creation-anchor'],
    );
    await fixture.todo('real-legacy', '旧执行安排', due: at(10), legacyStart: at(9));
    final snapshot = await repository.read(query());
    expect(snapshot.busy.map((item) => item.id), ['real-legacy']);
    expect(
      PlanAvailabilityService.find(
        query(),
        snapshot,
        now: PlanAvailabilityFixture.now,
      ).slots.map((slot) => slot.start),
      [at(8), at(10), at(10, 45), at(11, 30), at(12, 15)],
    );
  });
  test('课程假期、调休与多学期实际日期遵循原服务', () async {
    await fixture.course(
      'course-holiday',
      at(0),
      900,
      1000,
      semester: 'semester-one',
    );
    await fixture.course(
      'course-transfer',
      DateTime(2026, 10, 9),
      1100,
      1200,
      semester: 'semester-two',
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'semester_start_date_${PlanAvailabilityFixture.username}',
      '2026-10-05',
    );
    await CourseCalendarAdjustmentService.save(
      CourseCalendarAdjustment(
        holidayDates: {'2026-10-08'},
        transfers: [
          const CourseDayTransfer(fromDate: '2026-10-09', toDate: '2026-10-08'),
        ],
      ),
    );
    final snapshot = await repository.read(query());
    expect(
      snapshot.busy.where((i) => i.source == PlanBusySource.course),
      hasLength(1),
    );
    expect(snapshot.busy.single.start, at(11));
  });
  test('账号切换不读取另一个账号或写入原账号', () async {
    final q = query();
    final choice = await choose(q);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('current_login_user', 'other-fixture');
    final other = await DatabaseHelper.instance.databaseForUser(
      'other-fixture',
    );
    await fixture.todo('todo-other', '其他账号', targetDatabase: other);
    await expectLater(
      repository.read(q),
      throwsA(isA<PlanAvailabilityException>()),
    );
    await expectLater(
      repository.save(choice, draft(choice), sync: false),
      throwsA(isA<PlanAvailabilityException>()),
    );
    expect(await other.query('todos'), hasLength(1));
    await prefs.setString(
      'current_login_user',
      PlanAvailabilityFixture.username,
    );
    fixture.db = await DatabaseHelper.instance.databaseForUser(
      PlanAvailabilityFixture.username,
    );
    expect(await fixture.db.query('todo_plan_blocks'), isEmpty);
  });
  test('读取失败及损坏日期设置绝不变成成功空列表', () async {
    await fixture.db.execute('DROP TABLE fixed_schedules');
    await expectLater(
      repository.read(query()),
      throwsA(
        isA<PlanAvailabilityException>().having(
          (e) => e.message,
          'message',
          contains('固定日程'),
        ),
      ),
    );
  });
  test('损坏课表设置显示明确失败', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'course_calendar_adjustments_v1_${PlanAvailabilityFixture.username}',
      'invalid-json',
    );
    await expectLater(
      repository.read(query()),
      throwsA(isA<PlanAvailabilityException>()),
    );
  });
  test('损坏规则字段不能被旧服务降级为空；其他账号设置不干扰当前账号', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'course_calendar_adjustments_v1_other-fixture',
      'invalid',
    );
    expect((await repository.read(query())).busy, isEmpty);
    await prefs.setString(
      'course_calendar_adjustments_v1_${PlanAvailabilityFixture.username}',
      '{"holiday_dates":42}',
    );
    await expectLater(
      repository.read(query()),
      throwsA(isA<PlanAvailabilityException>()),
    );
    expect(await fixture.db.query('op_logs'), isEmpty);
  });
  test('损坏调休条目不能被忽略后当作空闲时段', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'course_calendar_adjustments_v1_${PlanAvailabilityFixture.username}',
      jsonEncode({
        'transfers': [42],
      }),
    );
    await expectLater(
      repository.read(query()),
      throwsA(isA<PlanAvailabilityException>()),
    );
  });
  test('保存再次遵守午休避让，拒绝冲突草稿且不产生规划或oplog', () async {
    final q = PlanAvailabilityQuery(
      username: PlanAvailabilityFixture.username,
      todoId: 'todo-target',
      date: PlanAvailabilityFixture.day,
      minutes: 45,
      avoidWindows: const [PlanDailyTimeWindow('午休', 720, 840)],
    );
    final snapshot = await repository.read(q);
    final blocked = PlanAvailabilitySelection(
      q,
      PlanTimeSlot(at(12), at(12, 45)),
      snapshot,
    );
    await expectLater(
      repository.save(blocked, draft(blocked), sync: false),
      throwsA(isA<PlanAvailabilityException>()),
    );
    expect(await fixture.db.query('todo_plan_blocks'), isEmpty);
    expect(await fixture.db.query('op_logs'), isEmpty);
    final allowed = PlanAvailabilitySelection(
      q,
      PlanTimeSlot(at(14), at(14, 45)),
      snapshot,
    );
    await repository.save(allowed, draft(allowed), sync: false);
    expect(await fixture.db.query('todo_plan_blocks'), hasLength(1));
    expect(await fixture.db.query('op_logs'), hasLength(1));
  });

  test('采用不写入；保存才写一条规划和一条oplog，不改待办截止', () async {
    final original = await fixture.db.query('todos');
    final choice = await choose(query());
    expect(await fixture.db.query('todo_plan_blocks'), isEmpty);
    final saved = await repository.save(choice, draft(choice), sync: false);
    expect(saved.startTime, at(8).millisecondsSinceEpoch);
    expect(await fixture.db.query('todo_plan_blocks'), hasLength(1));
    final ops = await fixture.db.query('op_logs');
    expect(ops, hasLength(1));
    expect(ops.single['target_table'], 'todo_plan_blocks');
    expect(await fixture.db.query('todos'), original);
  });
  test('新占用、目标完成均让保存失败且零写入', () async {
    final choice = await choose(query());
    await fixture.fixed('new-meeting', at(8), at(9));
    await expectLater(
      repository.save(choice, draft(choice), sync: false),
      throwsA(isA<PlanAvailabilityException>()),
    );
    expect(await fixture.db.query('todo_plan_blocks'), isEmpty);
    expect(await fixture.db.query('op_logs'), isEmpty);
    await fixture.db.delete('fixed_schedules');
    await fixture.db.update('todos', {'is_completed': 1});
    await expectLater(
      repository.save(choice, draft(choice), sync: false),
      throwsA(isA<PlanAvailabilityException>()),
    );
  });
  test('事务回滚，版本冲突和重复UUID都不留下oplog', () async {
    final choice = await choose(query());
    final value = draft(choice);
    await expectLater(
      StorageService.savePlanBlockEdited(
        PlanAvailabilityFixture.username,
        value,
        sync: false,
        beforeWrite: (_) async {
          throw StateError('abort');
        },
      ),
      throwsStateError,
    );
    expect(await fixture.db.query('todo_plan_blocks'), isEmpty);
    expect(await fixture.db.query('op_logs'), isEmpty);
    await repository.save(choice, value, sync: false);
    await expectLater(
      StorageService.savePlanBlockEdited(
        PlanAvailabilityFixture.username,
        value,
        sync: false,
      ),
      throwsStateError,
    );
    expect(await fixture.db.query('todo_plan_blocks'), hasLength(1));
    expect(await fixture.db.query('op_logs'), hasLength(1));
  });
  test('编辑保留实际执行和日历关联，版本变化拒绝覆盖', () async {
    final old = TodoPlanBlock(
      id: 'editing-plan',
      todoId: 'todo-target',
      startTime: at(8).millisecondsSinceEpoch,
      endTime: at(9).millisecondsSinceEpoch,
      actualFocusSeconds: 321,
      pomodoroRecordIds: ['record-one'],
      calendarEventId: 'event-one',
      deviceId: 'device-one',
      version: 7,
      updatedAt: 100,
    );
    await fixture.block(old);
    final choice = await choose(query(editing: old.id));
    final saved = await repository.save(
      choice,
      draft(choice, id: old.id),
      expectedVersion: 7,
      expectedUpdatedAt: 100,
      sync: false,
    );
    expect(saved.actualFocusSeconds, 321);
    expect(saved.calendarEventId, 'event-one');
    expect(saved.pomodoroRecordIds, ['record-one']);
    expect(saved.deviceId, 'device-one');
    expect(saved.version, 8);
    await expectLater(
      repository.save(
        choice,
        draft(choice, id: old.id),
        expectedVersion: 7,
        expectedUpdatedAt: 100,
        sync: false,
      ),
      throwsStateError,
    );
    expect(await fixture.db.query('op_logs'), hasLength(1));
  });
  test('编辑记录变成正在专注时拒绝推荐保存', () async {
    final old = TodoPlanBlock(
      id: 'editing-plan',
      todoId: 'todo-target',
      startTime: at(8).millisecondsSinceEpoch,
      endTime: at(9).millisecondsSinceEpoch,
      status: TodoPlanStatus.focusing,
      version: 7,
      updatedAt: 100,
    );
    await fixture.block(old);
    final choice = await choose(query(editing: old.id));
    await expectLater(
      repository.save(
        choice,
        draft(choice, id: old.id),
        expectedVersion: 7,
        expectedUpdatedAt: 100,
        sync: false,
      ),
      throwsA(isA<PlanAvailabilityException>()),
    );
    expect(await fixture.db.query('op_logs'), isEmpty);
  });
  test('日历已开启读取失败须显式选择应用内模式', () async {
    DeviceCalendarReadService.debugIsSupportedOverride = true;
    await DeviceCalendarReadService.setEnabled(true);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('countdown_todo/device_calendar_read'),
          (call) async {
            if (call.method == 'checkPermission') return true;
            throw PlatformException(code: 'provider-unavailable');
          },
        );
    await expectLater(
      repository.read(query()),
      throwsA(
        isA<PlanAvailabilityException>().having(
          (e) => e.canUseAppOnly,
          'appOnly',
          true,
        ),
      ),
    );
    final snapshot = await repository.read(query(appOnly: true));
    expect(snapshot.deviceCalendarIncluded, isFalse);
    expect(snapshot.coverage, contains('未计入手机日历'));
  });
  test('手机日历全天和跨天事项不占用，同日事项仍阻挡查找和保存', () async {
    DeviceCalendarReadService.debugIsSupportedOverride = true;
    await DeviceCalendarReadService.setEnabled(true);
    var sameDayMeeting = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('countdown_todo/device_calendar_read'),
          (call) async {
            if (call.method == 'checkPermission') return true;
            return [
              {
                'id': 'overnight-phone',
                'startMs': at(8).millisecondsSinceEpoch,
                'endMs': DateTime(2026, 10, 9, 8).millisecondsSinceEpoch,
                'allDay': false,
              },
              {
                'id': 'all-day-phone',
                'startMs': at(0).millisecondsSinceEpoch,
                'endMs': DateTime(2026, 10, 9).millisecondsSinceEpoch,
                'allDay': true,
              },
              if (sameDayMeeting)
                {
                  'id': 'real-phone-meeting',
                  'startMs': at(8).millisecondsSinceEpoch,
                  'endMs': at(9).millisecondsSinceEpoch,
                  'allDay': false,
                },
            ];
          },
        );
    final choice = await choose(query());
    expect(choice.slot.start, at(8));
    expect(choice.snapshot.busy, isEmpty);
    expect(choice.snapshot.coverage, contains('全天及跨天'));
    await repository.save(choice, draft(choice), sync: false);
    expect(await fixture.db.query('op_logs'), hasLength(1));
    await fixture.db.delete('todo_plan_blocks');
    await fixture.db.delete('op_logs');
    final tomorrowQuery = PlanAvailabilityQuery(
      username: PlanAvailabilityFixture.username,
      todoId: 'todo-target',
      date: DateTime(2026, 10, 9),
      minutes: 45,
    );
    expect(
      (await repository.read(tomorrowQuery, forceRefresh: true)).busy,
      isEmpty,
    );
    final nextChoice = await choose(query());
    sameDayMeeting = true;
    await expectLater(
      repository.save(nextChoice, draft(nextChoice), sync: false),
      throwsA(isA<PlanAvailabilityException>()),
    );
    expect(await fixture.db.query('op_logs'), isEmpty);
    final fresh = await repository.read(query(), forceRefresh: true);
    expect(fresh.busy.single.id, 'real-phone-meeting');
    expect(
      PlanAvailabilityService.find(
        query(),
        fresh,
        now: PlanAvailabilityFixture.now,
      ).slots.first.start,
      at(9),
    );
  });

  test('手机日历保存前强制读取，外部详情不持久化', () async {
    DeviceCalendarReadService.debugIsSupportedOverride = true;
    await DeviceCalendarReadService.setEnabled(true);
    var reads = 0;
    var occupied = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('countdown_todo/device_calendar_read'),
          (call) async {
            if (call.method == 'checkPermission') return true;
            reads++;
            return occupied
                ? [
                    {
                      'id': 'private-event',
                      'calendarId': 'calendar',
                      'title': '不得写入日志的合成标题',
                      'startMs': at(8).millisecondsSinceEpoch,
                      'endMs': at(9).millisecondsSinceEpoch,
                      'allDay': false,
                    },
                  ]
                : [];
          },
        );
    final choice = await choose(query());
    expect(choice.snapshot.deviceCalendarIncluded, isTrue);
    occupied = true;
    await expectLater(
      repository.save(choice, draft(choice), sync: false),
      throwsA(isA<PlanAvailabilityException>()),
    );
    expect(reads, 2);
    expect(await fixture.db.query('op_logs'), isEmpty);
    occupied = false;
    final freshChoice = await choose(query());
    await repository.save(freshChoice, draft(freshChoice), sync: false);
    final data = jsonEncode(await fixture.db.query('op_logs'));
    expect(data, isNot(contains('private-event')));
    expect(data, isNot(contains('合成标题')));
  });
  test('合成1000条占用测量完整读取与计算', () async {
    final batch = fixture.db.batch();
    for (var i = 0; i < 1000; i++) {
      batch.insert(
        'todo_plan_blocks',
        TodoPlanBlock(
          id: 'sample-$i',
          titleSnapshot: '合成规划',
          todoId: 'other-todo',
          startTime: at(9).millisecondsSinceEpoch,
          endTime: at(10).millisecondsSinceEpoch,
        ).toDbJson(),
      );
    }
    await batch.commit(noResult: true);
    final watch = Stopwatch()..start();
    final snapshot = await repository.read(query());
    final read = watch.elapsedMicroseconds;
    watch.reset();
    final result = PlanAvailabilityService.find(
      query(),
      snapshot,
      now: PlanAvailabilityFixture.now,
    );
    final compute = watch.elapsedMicroseconds;
    expect(snapshot.busy, hasLength(1000));
    expect(result.slots.first.start, at(8));
    // Actual observations only; deliberately no fragile speed threshold.
    if (kDebugMode) {
      print(
        'PLAN_AVAILABILITY_BENCHMARK ${jsonEncode({'rows': 1000, 'readMicroseconds': read, 'computeMicroseconds': compute, 'localTables': 4})}',
      );
    }
  });
}
