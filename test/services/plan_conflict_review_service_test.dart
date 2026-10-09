import 'dart:convert';

import 'package:countdown_todo/models.dart';
import 'package:countdown_todo/models/plan_availability.dart';
import 'package:countdown_todo/services/device_calendar_read_service.dart';
import 'package:countdown_todo/services/plan_availability_preferences.dart';
import 'package:countdown_todo/services/plan_availability_repository.dart';
import 'package:countdown_todo/services/plan_availability_service.dart';
import 'package:countdown_todo/services/plan_conflict_review_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import '../support/plan_availability_fixture.dart';

class MutatingConflictAvailability extends PlanAvailabilityRepository {
  MutatingConflictAvailability(Database db, this.mutation)
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
  const username = PlanAvailabilityFixture.username;
  final day = PlanAvailabilityFixture.day;
  final now = PlanAvailabilityFixture.now;
  DateTime at(int hour, [int minute = 0]) =>
      DateTime(day.year, day.month, day.day, hour, minute);
  late PlanAvailabilityFixture fixture;
  late PlanConflictReviewService service;
  late PlanConflictEditContext context;
  late TodoPlanBlock original;
  setUp(() async {
    fixture = PlanAvailabilityFixture();
    await fixture.initialize();
    original = TodoPlanBlock(
      id: 'conflicting-plan',
      todoId: 'todo-target',
      titleSnapshot: '复习高数',
      startTime: at(10).millisecondsSinceEpoch,
      endTime: at(11).millisecondsSinceEpoch,
      plannedMinutes: 60,
      actualFocusSeconds: 300,
      calendarEventId: 'keep-calendar',
      pomodoroRecordIds: ['keep-record'],
      deviceId: 'keep-device',
      source: TodoPlanSource.ai,
      version: 4,
      remark: '原备注',
    );
    await fixture.block(original);
    service = PlanConflictReviewService(
      databaseOverride: fixture.db,
      clock: () => now,
    );
    context = await service.prepareEdit(username, original.id);
  });
  tearDown(() => fixture.dispose());

  TodoPlanBlock draft({int hour = 12, int minute = 0}) =>
      TodoPlanBlock.fromJson(context.block.toJson())
        ..startTime = at(hour, minute).millisecondsSinceEpoch
        ..endTime = at(hour + 1, minute).millisecondsSinceEpoch
        ..remark = '调整后';
  Future<TodoPlanBlock> save({
    TodoPlanBlock? input,
    PlanAvailabilitySelection? selected,
    PlanConflictReviewService? via,
    PlanAvailabilityQuery? manualQuery,
  }) => (via ?? service).save(
    context,
    input ?? draft(),
    selected,
    expectedBlock: context.block,
    sync: false,
    manualQuery: manualQuery,
  );
  Future<void> zeroWrites(Future<void> Function() action) async {
    final plans = await fixture.db.query('todo_plan_blocks');
    final todos = await fixture.db.query('todos');
    final logs = await fixture.db.query('op_logs');
    await expectLater(action(), throwsA(anything));
    expect(await fixture.db.query('todo_plan_blocks'), plans);
    expect(await fixture.db.query('todos'), todos);
    expect(await fixture.db.query('op_logs'), logs);
  }

  test('多来源按真实UUID计数，规划对规划双向显示且只排除自身', () async {
    await fixture.course('course', day, 1000, 1045);
    await fixture.fixed('meeting', at(10, 50), at(12));
    await fixture.block(
      TodoPlanBlock(
        id: 'other-plan',
        todoId: 'todo-target',
        startTime: at(10, 30).millisecondsSinceEpoch,
        endTime: at(11, 30).millisecondsSinceEpoch,
      ),
    );
    final result = await service.read(username, day);
    expect(result.entries, hasLength(2));
    final first = result.entries.first;
    expect(first.block.id, original.id);
    expect(first.overlaps.map((item) => item.source.source).toSet(), {
      PlanBusySource.course,
      PlanBusySource.fixedSchedule,
      PlanBusySource.planBlock,
    });
    expect(
      first.overlaps.any((item) => item.source.id == original.id),
      isFalse,
    );
    expect(first.overlaps.first.start, at(10));
    expect(first.overlaps.first.end, at(10, 45));
    expect(first.overlaps.first.source.record, isA<CourseItem>());
    expect(await fixture.db.query('op_logs'), isEmpty);
  });
  test('半开边界、取消会议、过去和虚拟映射不误报', () async {
    await fixture.fixed('ends-at-start', at(9), at(10));
    await fixture.fixed('starts-at-end', at(11), at(12));
    await fixture.fixed(
      'cancelled',
      at(10),
      at(11),
      status: FixedScheduleStatus.cancelled,
    );
    await fixture.block(
      TodoPlanBlock(
        id: 'ended',
        todoId: 'todo-target',
        startTime: now
            .subtract(const Duration(hours: 3))
            .millisecondsSinceEpoch,
        endTime: now.subtract(const Duration(hours: 2)).millisecondsSinceEpoch,
      ),
    );
    expect((await service.read(username, day)).entries, isEmpty);
  });
  test('每个有效状态参加检查，专注中仅查看，历史状态排除', () async {
    await fixture.fixed('meeting', at(10), at(11));
    for (final status in TodoPlanStatus.values) {
      await fixture.db.update(
        'todo_plan_blocks',
        {'status': status.index},
        where: 'uuid = ?',
        whereArgs: [original.id],
      );
      final entries = (await service.read(username, day)).entries;
      if (PlanAvailabilityService.occupies(
        TodoPlanBlock.fromJson({
          ...context.block.toJson(),
          'status': status.index,
        }),
      )) {
        expect(entries, hasLength(1), reason: status.name);
        expect(entries.single.canAdjust, status != TodoPlanStatus.focusing);
      } else {
        expect(entries, isEmpty, reason: status.name);
      }
    }
  });
  test('时间待定明确不完整，查找偏好不作为已保存规划的冲突来源', () async {
    await PlanAvailabilityPreferences.save(
      username,
      PlanAvailabilityPreferences.defaultWindows,
      {PlanAvailabilityPreferences.defaultWindows.first},
    );
    await fixture.db.insert(
      'fixed_schedules',
      FixedScheduleItem(id: 'tbd', title: '时间待定', date: '2026-10-08').toJson(),
    );
    final result = await service.read(username, day);
    expect(result.entries, isEmpty);
    expect(result.complete, isFalse);
    expect(result.unknownTimes.single, contains('时间待定'));
  });
  test('跨日应用内安排每天裁剪，七天范围同一规划只计一次', () async {
    final next = DateTime(day.year, day.month, day.day + 1);
    await fixture.db.update(
      'todo_plan_blocks',
      {
        'start_time': at(23).millisecondsSinceEpoch,
        'end_time': next.add(const Duration(hours: 2)).millisecondsSinceEpoch,
      },
      where: 'uuid = ?',
      whereArgs: [original.id],
    );
    await fixture.fixed(
      'night',
      at(23, 30),
      next.add(const Duration(hours: 1)),
    );
    final one = await service.read(username, day);
    expect(one.entries.single.overlaps.single.start, at(23, 30));
    expect(one.entries.single.overlaps.single.end, next);
    final week = await service.read(username, day, days: 7);
    expect(week.entries, hasLength(1));
    expect(week.entries.single.overlaps, hasLength(2));
    expect(week.end, DateTime(day.year, day.month, day.day + 7));
    expect(week.entries.single.overlaps.last.start, next);
  });
  test('七天只读一次手机日历，全天和跨日期事件不占用，同日事件正确命名', () async {
    DeviceCalendarReadService.debugIsSupportedOverride = true;
    await (await SharedPreferences.getInstance()).setBool(
      'device_calendar_read_enabled',
      true,
    );
    var reads = 0;
    Map<dynamic, dynamic>? args;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('countdown_todo/device_calendar_read'),
          (call) async {
            if (call.method == 'checkPermission') return true;
            if (call.method == 'readEvents') {
              reads++;
              args = call.arguments as Map;
              return [
                {
                  'id': 'all',
                  'calendarId': 'c',
                  'title': '全天',
                  'startMs': at(0).millisecondsSinceEpoch,
                  'endMs': at(23).millisecondsSinceEpoch,
                  'allDay': true,
                },
                {
                  'id': 'cross',
                  'calendarId': 'c',
                  'title': '跨天',
                  'startMs': at(8).millisecondsSinceEpoch,
                  'endMs': at(8)
                      .add(const Duration(days: 1))
                      .millisecondsSinceEpoch,
                  'allDay': false,
                },
                {
                  'id': 'timed',
                  'calendarId': 'c',
                  'title': '手机会议',
                  'startMs': at(10, 30).millisecondsSinceEpoch,
                  'endMs': at(11, 30).millisecondsSinceEpoch,
                  'allDay': false,
                },
              ];
            }
            return null;
          },
        );
    final result = await service.read(username, day, days: 7);
    expect(reads, 1);
    expect(args!['startMs'], day.millisecondsSinceEpoch);
    expect(
      args!['endMs'],
      DateTime(day.year, day.month, day.day + 7).millisecondsSinceEpoch,
    );
    expect(result.entries.single.overlaps, hasLength(1));
    expect(result.entries.single.overlaps.single.source.title, '手机会议');
    expect(
      result.entries.single.overlaps.single.source.record,
      isA<DeviceCalendarEvent>(),
    );
  });
  test('日历读取失败不视为空闲，明确应用内降级才返回带范围结果', () async {
    DeviceCalendarReadService.debugIsSupportedOverride = true;
    await (await SharedPreferences.getInstance()).setBool(
      'device_calendar_read_enabled',
      true,
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('countdown_todo/device_calendar_read'),
          (call) async {
            if (call.method == 'checkPermission') return true;
            throw PlatformException(code: 'calendar-failed');
          },
        );
    await expectLater(
      service.read(username, day),
      throwsA(isA<PlanAvailabilityException>()),
    );
    final result = await service.read(username, day, appOnly: true);
    expect(result.appOnly, isTrue);
    expect(result.coverage, contains('未计入手机日历'));
  });
  test('来源表损坏时明确失败，范围不能大于七天', () async {
    await expectLater(
      service.read(username, day, days: 8),
      throwsA(isA<PlanAvailabilityException>()),
    );
    await fixture.db.execute('DROP TABLE fixed_schedules');
    await expectLater(
      service.read(username, day),
      throwsA(isA<PlanAvailabilityException>()),
    );
  });
  test('手动改期只更新原UUID，保存实际记录日历来源设备并且其他表不变', () async {
    await fixture.fixed('meeting', at(10), at(11));
    await fixture.block(
      TodoPlanBlock(
        id: 'untouched',
        todoId: 'todo-target',
        startTime: at(15).millisecondsSinceEpoch,
        endTime: at(16).millisecondsSinceEpoch,
      ),
    );
    final other = await fixture.db.query(
      'todo_plan_blocks',
      where: 'uuid = ?',
      whereArgs: ['untouched'],
    );
    final todos = await fixture.db.query('todos');
    final fixed = await fixture.db.query('fixed_schedules');
    final malicious = draft()
      ..actualFocusSeconds = 0
      ..calendarEventId = null
      ..pomodoroRecordIds = []
      ..deviceId = null
      ..source = TodoPlanSource.manual;
    final saved = await save(input: malicious);
    expect(saved.id, original.id);
    expect(saved.version, context.block.version + 1);
    expect(saved.actualFocusSeconds, 300);
    expect(saved.calendarEventId, 'keep-calendar');
    expect(saved.pomodoroRecordIds, ['keep-record']);
    expect(saved.deviceId, 'keep-device');
    expect(saved.source, TodoPlanSource.ai);
    expect(saved.startTime, at(12).millisecondsSinceEpoch);
    expect(await fixture.db.query('todos'), todos);
    expect(await fixture.db.query('fixed_schedules'), fixed);
    expect(
      await fixture.db.query(
        'todo_plan_blocks',
        where: 'uuid = ?',
        whereArgs: ['untouched'],
      ),
      other,
    );
    final logs = await fixture.db.query('op_logs');
    expect(logs, hasLength(1));
    expect(logs.single['target_uuid'], original.id);
  });
  test('推荐改期排除原UUID，采用前零写入，保存后冲突消失', () async {
    await fixture.fixed('meeting', at(10), at(11));
    final q = PlanAvailabilityQuery(
      username: username,
      todoId: 'todo-target',
      date: day,
      minutes: 60,
      excludeBlockId: original.id,
    );
    final snap = await service.availability.read(q);
    final slot = PlanAvailabilityService.find(q, snap, now: now).slots.first;
    final selected = PlanAvailabilitySelection(q, slot, snap);
    final input = draft()
      ..startTime = slot.start.millisecondsSinceEpoch
      ..endTime = slot.end.millisecondsSinceEpoch;
    expect(await fixture.db.query('op_logs'), isEmpty);
    await save(input: input, selected: selected);
    expect((await service.read(username, day)).entries, isEmpty);
    expect(await fixture.db.query('todo_plan_blocks'), hasLength(1));
  });
  test('手动区间仍校验其他同待办规划，截止与已记住避让', () async {
    await fixture.block(
      TodoPlanBlock(
        id: 'same-todo',
        todoId: 'todo-target',
        startTime: at(12).millisecondsSinceEpoch,
        endTime: at(13).millisecondsSinceEpoch,
      ),
    );
    await zeroWrites(() async => save());
    await fixture.db.delete(
      'todo_plan_blocks',
      where: 'uuid = ?',
      whereArgs: ['same-todo'],
    );
    await PlanAvailabilityPreferences.save(
      username,
      PlanAvailabilityPreferences.defaultWindows,
      {PlanAvailabilityPreferences.defaultWindows.first},
    );
    await zeroWrites(() async => save());
    await PlanAvailabilityPreferences.save(
      username,
      PlanAvailabilityPreferences.defaultWindows,
      {},
    );
    await fixture.db.update(
      'todos',
      {'due_date': at(12, 30).millisecondsSinceEpoch},
      where: 'uuid = ?',
      whereArgs: ['todo-target'],
    );
    await zeroWrites(() async => save());
  });
  test('推荐采用后避让偏好变化必须重新查找，即使旧时段碰巧没有重叠', () async {
    final q = PlanAvailabilityQuery(
      username: username,
      todoId: 'todo-target',
      date: day,
      minutes: 60,
      excludeBlockId: original.id,
    );
    final snap = await service.availability.read(q);
    final slot = PlanAvailabilityService.find(q, snap, now: now).slots.first;
    await PlanAvailabilityPreferences.save(
      username,
      PlanAvailabilityPreferences.defaultWindows,
      {PlanAvailabilityPreferences.defaultWindows.first},
    );
    final input = draft()
      ..startTime = slot.start.millisecondsSinceEpoch
      ..endTime = slot.end.millisecondsSinceEpoch;
    await zeroWrites(
      () async => save(
        input: input,
        selected: PlanAvailabilitySelection(q, slot, snap),
      ),
    );
  });
  test('最终读取后避让变化也在写事务内拒绝', () async {
    final via = PlanConflictReviewService(
      databaseOverride: fixture.db,
      clock: () => now,
      availabilityOverride: MutatingConflictAvailability(
        fixture.db,
        () => PlanAvailabilityPreferences.save(
          username,
          PlanAvailabilityPreferences.defaultWindows,
          {PlanAvailabilityPreferences.defaultWindows.first},
        ),
      ),
    );
    await zeroWrites(() async => save(via: via));
  });
  test('改期后专注状态重试复用原UUID和已保存时间，不重复创建', () async {
    final saved = await save();
    final status = await service.save(
      context,
      saved,
      null,
      expectedBlock: saved,
      newStatus: TodoPlanStatus.focusing,
      sync: false,
    );
    expect(status.id, original.id);
    expect(status.status, TodoPlanStatus.focusing);
    expect(status.startTime, saved.startTime);
    expect(status.pomodoroRecordIds, ['keep-record']);
    expect(await fixture.db.query('todo_plan_blocks'), hasLength(1));
    expect(await fixture.db.query('op_logs'), hasLength(2));
  });
  test('仍在进行的跨日规划在过去日期不产生待改期提示', () async {
    final data = PlanAvailabilityRangeSnapshot(
      username: username,
      start: day,
      end: day.add(const Duration(days: 1)),
      blocks: [
        TodoPlanBlock.fromJson(context.block.toJson())
          ..endTime = day.add(const Duration(days: 3)).millisecondsSinceEpoch,
      ],
      todos: [context.todo],
      days: [
        PlanAvailabilityDaySources(
          date: day,
          busy: [
            PlanBusyInterval(
              at(10),
              at(11),
              source: PlanBusySource.fixedSchedule,
              id: 'old',
            ),
          ],
          unknownTimes: ['旧日期待定事项'],
        ),
      ],
      coverage: '合成',
      deviceCalendarIncluded: false,
    );
    final result = PlanConflictReviewService.detect(
      data,
      now: day.add(const Duration(days: 2)),
    );
    expect(result.entries, isEmpty);
    expect(result.unknownTimes, isEmpty);
  });

  test('不能替换原UUID或切换待办关联', () async {
    await zeroWrites(() async => save(input: draft()..id = 'new-id'));
    await fixture.todo('other', '另一待办');
    await zeroWrites(() async => save(input: draft()..todoId = 'other'));
  });
  for (final column in ['is_completed', 'is_deleted', 'has_conflict']) {
    test('待办$column变更后拒绝保存并零写入', () async {
      await fixture.db.update(
        'todos',
        {column: 1},
        where: 'uuid = ?',
        whereArgs: ['todo-target'],
      );
      await zeroWrites(() async => save());
    });
  }
  for (final status in [
    TodoPlanStatus.focusing,
    TodoPlanStatus.finished,
    TodoPlanStatus.missed,
    TodoPlanStatus.cancelled,
    TodoPlanStatus.skipped,
  ]) {
    test('原规划变为${status.name}后拒绝改期并零写入', () async {
      await fixture.db.update(
        'todo_plan_blocks',
        {'status': status.index},
        where: 'uuid = ?',
        whereArgs: [original.id],
      );
      await zeroWrites(() async => save());
    });
  }
  test('版本、更新时间相同但内容被改也拒绝保存', () async {
    await fixture.db.update(
      'todo_plan_blocks',
      {'remark': '其他设备修改'},
      where: 'uuid = ?',
      whereArgs: [original.id],
    );
    await zeroWrites(() async => save());
  });
  test('账号切换后检查和保存均停止，不改任一账号', () async {
    await (await SharedPreferences.getInstance()).setString(
      'current_login_user',
      'other',
    );
    await expectLater(
      service.read(username, day),
      throwsA(isA<PlanAvailabilityException>()),
    );
    await zeroWrites(() async => save());
  });
  test('最终读取后新占用在事务内再次检查，失败零写入', () async {
    final availability = MutatingConflictAvailability(
      fixture.db,
      () => fixture.fixed('late-meeting', at(12), at(13)),
    );
    final via = PlanConflictReviewService(
      databaseOverride: fixture.db,
      clock: () => now,
      availabilityOverride: availability,
    );
    await zeroWrites(() async => save(via: via));
    expect(availability.reads, 2);
    expect(await fixture.db.query('fixed_schedules'), hasLength(1));
  });
  test('oplog写入失败时规划事务完整回滚', () async {
    await fixture.db.execute(
      "CREATE TRIGGER reject_conflict_log BEFORE INSERT ON op_logs BEGIN SELECT RAISE(ABORT, 'reject test log'); END",
    );
    await zeroWrites(() async => save());
  });
  test('同一来源重复读取去重，跨日按日期分段仍只计一个规划', () async {
    final source = PlanBusyInterval(
      at(10),
      at(11),
      source: PlanBusySource.fixedSchedule,
      id: 'same',
      title: '同一会议',
    );
    final data = PlanAvailabilityRangeSnapshot(
      username: username,
      start: day,
      end: day.add(const Duration(days: 1)),
      blocks: [context.block, context.block],
      todos: [context.todo],
      days: [
        PlanAvailabilityDaySources(
          date: day,
          busy: [source, source],
          unknownTimes: [],
        ),
      ],
      coverage: '合成',
      deviceCalendarIncluded: false,
    );
    final result = PlanConflictReviewService.detect(data, now: now);
    expect(result.entries, hasLength(1));
    expect(result.entries.single.overlaps, hasLength(1));
    expect(jsonEncode(context.block.toJson()), jsonEncode(original.toJson()));
  });
}
