import 'dart:convert';
import 'dart:io';

import 'package:countdown_todo/models.dart';
import 'package:countdown_todo/services/plan_availability_preferences.dart';
import 'package:countdown_todo/services/plan_conflict_review_service.dart';
import 'package:countdown_todo/services/plan_drag_service.dart';
import 'package:countdown_todo/services/pomodoro_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/plan_availability_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const username = PlanAvailabilityFixture.username;
  final day = PlanAvailabilityFixture.day;
  DateTime at(int h, [int m = 0]) =>
      DateTime(day.year, day.month, day.day, h, m);
  PlanDragTimes times(int a, int b) => PlanDragTimes(at(a), at(b));
  for (final step in [5, 10, 15, 30]) {
    test('移动保时长与两端边界，粒度$step', () {
      final original = PlanDragTimes(at(22, 30), at(23, 30));
      final end = PlanDragGeometry.adjust(
        date: day,
        original: original,
        deltaMinutes: 2000,
        step: step,
        kind: PlanDragKind.move,
      );
      expect(end.start, at(23));
      expect(end.end, at(24));
      expect(end.minutes, 60);
      final first = PlanDragGeometry.adjust(
        date: day,
        original: original,
        deltaMinutes: -2000,
        step: step,
        kind: PlanDragKind.move,
      );
      expect(first.start, at(0));
      expect(first.end, at(1));
    });
    test('累计慢拖与缩放最小长度，粒度$step', () {
      final resized = PlanDragGeometry.adjust(
        date: day,
        original: times(10, 11),
        deltaMinutes: step * .6,
        step: step,
        kind: PlanDragKind.resizeEnd,
      );
      expect(resized.end, at(11).add(Duration(minutes: step)));
      final start = PlanDragGeometry.adjust(
        date: day,
        original: times(10, 11),
        deltaMinutes: 1000,
        step: step,
        kind: PlanDragKind.resizeStart,
      );
      expect(start.end, at(11));
      expect(start.minutes, step);
      final end = PlanDragGeometry.adjust(
        date: day,
        original: times(10, 11),
        deltaMinutes: -1000,
        step: step,
        kind: PlanDragKind.resizeEnd,
      );
      expect(end.start, at(10));
      expect(end.minutes, step);
    });
  }
  test('无变化保持旧时段，完整一天和月底使用本地日期边界', () {
    final original = times(0, 24);
    final moved = PlanDragGeometry.adjust(
      date: day,
      original: original,
      deltaMinutes: 1500,
      step: 15,
      kind: PlanDragKind.move,
    );
    expect(moved.start, day);
    expect(moved.end, at(24));
    final feb = DateTime(2028, 2, 29);
    final result = PlanDragGeometry.adjust(
      date: feb,
      original: PlanDragTimes(DateTime(2028, 2, 29, 23), DateTime(2028, 3, 1)),
      deltaMinutes: 30,
      step: 15,
      kind: PlanDragKind.move,
    );
    expect(result.end, DateTime(2028, 3, 1));
    expect(result.minutes, 60);
    expect(
      PlanDragGeometry.adjust(
        date: day,
        original: times(10, 11),
        deltaMinutes: 4,
        step: 15,
        kind: PlanDragKind.resizeEnd,
      ).end,
      at(11),
    );
  });
  test('跨日和非法原区间不悄悄裁剪，非有限位移被拒绝', () {
    for (final original in [times(-1, 1), times(23, 25), times(11, 10)]) {
      expect(
        () => PlanDragGeometry.adjust(
          date: day,
          original: original,
          deltaMinutes: 1,
          step: 15,
          kind: PlanDragKind.move,
        ),
        throwsA(isA<PlanDragException>()),
      );
    }
    expect(
      () => PlanDragGeometry.adjust(
        date: day,
        original: times(10, 11),
        deltaMinutes: double.nan,
        step: 15,
        kind: PlanDragKind.move,
      ),
      throwsA(isA<PlanDragException>()),
    );
  });

  group('隔离SQLite受校验保存与撤销', () {
    late PlanAvailabilityFixture fixture;
    late PlanDragService service;
    late TodoPlanBlock original;
    late PlanDragSnapshot snapshot;
    late DateTime clock;
    setUp(() async {
      fixture = PlanAvailabilityFixture();
      await fixture.initialize();
      clock = PlanAvailabilityFixture.now;
      original = TodoPlanBlock(
        id: 'drag',
        todoId: 'todo-target',
        titleSnapshot: '复习高数',
        startTime: at(10).millisecondsSinceEpoch,
        endTime: at(11).millisecondsSinceEpoch,
        plannedMinutes: 60,
        version: 4,
        actualFocusSeconds: 321,
        calendarEventId: 'calendar',
        pomodoroRecordIds: ['record'],
        deviceId: 'device',
        source: TodoPlanSource.ai,
        remark: '原备注',
        reminderMinutes: 10,
        pomodoroMinutes: 30,
        pomodoroRounds: 2,
      );
      await fixture.block(original);
      service = PlanDragService(
        databaseOverride: fixture.db,
        clock: () => clock,
      );
      snapshot = service.capture(username, day, original);
    });
    tearDown(() => fixture.dispose());
    Future<PlanDragChange> save([PlanDragTimes? target]) async =>
        (await service.save(snapshot, target ?? times(14, 15), sync: false))!;
    Future<TodoPlanBlock> persisted() async => TodoPlanBlock.fromJson(
      (await fixture.db.query(
        'todo_plan_blocks',
        where: 'uuid = ?',
        whereArgs: ['drag'],
      )).single,
    );
    Future<void> zeroWrites(
      Future<void> Function() action, {
      bool stale = true,
    }) async {
      final before = await fixture.db.query('todo_plan_blocks');
      final logs = await fixture.db.query('op_logs');
      await expectLater(
        action(),
        throwsA(
          isA<PlanDragException>().having((e) => e.stale, 'stale', stale),
        ),
      );
      expect(await fixture.db.query('todo_plan_blocks'), before);
      expect(await fixture.db.query('op_logs'), logs);
    }

    test('移动和撤销同UUID，保留实际配置身份；两条新版本oplog', () async {
      await fixture.todo('other-todo', '别的待办');
      await fixture.block(
        TodoPlanBlock(
          id: 'other',
          todoId: 'other-todo',
          startTime: at(16).millisecondsSinceEpoch,
          endTime: at(17).millisecondsSinceEpoch,
        ),
      );
      final todos = await fixture.db.query('todos');
      final other = await fixture.db.query(
        'todo_plan_blocks',
        where: 'uuid = ?',
        whereArgs: ['other'],
      );
      final change = await save();
      final saved = await persisted();
      expect(saved.startTime, at(14).millisecondsSinceEpoch);
      expect(saved.version, original.version + 1);
      final undone = await service.undo(change, sync: false);
      final expected = original.toJson()
        ..['version'] = original.version + 2
        ..['updated_at'] = undone.updatedAt;
      expect(undone.toJson(), expected);
      expect(await fixture.db.query('todos'), todos);
      expect(
        await fixture.db.query(
          'todo_plan_blocks',
          where: 'uuid = ?',
          whereArgs: ['other'],
        ),
        other,
      );
      final logs = await fixture.db.query('op_logs');
      expect(logs, hasLength(2));
      expect(
        jsonDecode(logs.last['data_json']! as String)['start_time'],
        original.startTime,
      );
      expect(
        logs.every(
          (r) => r['op_type'] == 'UPSERT' && r['target_uuid'] == original.id,
        ),
        isTrue,
      );
    });
    test('快照与返回副本不能被预览修改，无变化零写入', () async {
      snapshot.block
        ..startTime = at(18).millisecondsSinceEpoch
        ..remark = '污染';
      original.remark = '污染调用方';
      expect(snapshot.block.remark, '原备注');
      expect(await service.save(snapshot, times(10, 11), sync: false), isNull);
      expect(await fixture.db.query('op_logs'), isEmpty);
      expect((await persisted()).version, 4);
    });
    test('缩放后撤销精确恢复旧计划分钟数', () async {
      final change = await save(times(10, 12));
      expect((await persisted()).plannedMinutes, 120);
      expect((await service.undo(change, sync: false)).plannedMinutes, 60);
    });
    for (final status in [TodoPlanStatus.reminded, TodoPlanStatus.delayed]) {
      test('${status.name}可调整且撤销保留状态', () async {
        await fixture.db.update(
          'todo_plan_blocks',
          {'status': status.index},
          where: 'uuid = ?',
          whereArgs: ['drag'],
        );
        snapshot = service.capture(username, day, await persisted());
        final change = await save();
        expect((await service.undo(change, sync: false)).status, status);
      });
    }
    test('硬删除关联待办和撤销前账号切换均拒绝', () async {
      final change = await save();
      await fixture.db.delete(
        'todos',
        where: 'uuid = ?',
        whereArgs: ['todo-target'],
      );
      await zeroWrites(() async {
        await service.undo(change, sync: false);
      });
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('current_login_user', 'another-user');
      await expectLater(
        PlanDragService(clock: () => clock).validateUndo(change),
        throwsA(isA<PlanDragException>().having((e) => e.stale, 'stale', true)),
      );
      await zeroWrites(() async {
        await service.undo(change, sync: false);
      });
    });
    test('已有重叠与避让不是直接拖动或恢复的硬限制', () async {
      await fixture.fixed('meeting', at(14), at(15));
      await PlanAvailabilityPreferences.save(
        username,
        PlanAvailabilityPreferences.defaultWindows,
        {PlanAvailabilityPreferences.defaultWindows.first},
      );
      final change = await save(times(12, 14));
      await fixture.fixed('new-meeting', at(10), at(11));
      await service.undo(change, sync: false);
      final conflicts = await PlanConflictReviewService(
        databaseOverride: fixture.db,
        clock: () => clock,
      ).read(username, day);
      expect(conflicts.entries.single.block.id, 'drag');
    });
    for (final status in [
      TodoPlanStatus.focusing,
      TodoPlanStatus.finished,
      TodoPlanStatus.missed,
      TodoPlanStatus.skipped,
      TodoPlanStatus.cancelled,
    ]) {
      test('原规划变为${status.name}停止保存与撤销', () async {
        await fixture.db.update(
          'todo_plan_blocks',
          {'status': status.index},
          where: 'uuid = ?',
          whereArgs: ['drag'],
        );
        await zeroWrites(() async {
          await save();
        });
        final lateChange = PlanDragChange(snapshot, snapshot.block);
        await zeroWrites(() async {
          await service.undo(lateChange, sync: false);
        });
      });
    }
    for (final column in ['is_completed', 'is_deleted', 'has_conflict']) {
      test('待办$column变更停止写入', () async {
        await fixture.db.update(
          'todos',
          {column: 1},
          where: 'uuid = ?',
          whereArgs: ['todo-target'],
        );
        await zeroWrites(() async {
          await save();
        });
      });
    }
    test('内容同版本变更也拒绝保存与撤销', () async {
      final change = await save();
      await fixture.db.update(
        'todo_plan_blocks',
        {'remark': '其他设备备注'},
        where: 'uuid = ?',
        whereArgs: ['drag'],
      );
      await zeroWrites(() async {
        await service.undo(change, sync: false);
      });
      await expectLater(
        service.validateUndo(change),
        throwsA(isA<PlanDragException>().having((e) => e.stale, 'stale', true)),
      );
    });
    test('版本变化、软删除、硬删除不会恢复旧记录', () async {
      final change = await save();
      await fixture.db.update(
        'todo_plan_blocks',
        {'version': 99},
        where: 'uuid = ?',
        whereArgs: ['drag'],
      );
      await zeroWrites(() async {
        await service.undo(change, sync: false);
      });
      await fixture.db.update(
        'todo_plan_blocks',
        {'is_deleted': 1},
        where: 'uuid = ?',
        whereArgs: ['drag'],
      );
      await zeroWrites(() async {
        await save();
      });
      await fixture.db.delete(
        'todo_plan_blocks',
        where: 'uuid = ?',
        whereArgs: ['drag'],
      );
      await zeroWrites(() async {
        await service.undo(change, sync: false);
      });
    });
    test('当前专注运行标记和账号切换阻止过期操作', () async {
      final change = await save();
      await PomodoroService.saveRunState(
        PomodoroRunState(phase: PomodoroPhase.focusing, planBlockId: 'drag'),
      );
      await zeroWrites(() async {
        await service.undo(change, sync: false);
      });
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('current_login_user', 'other');
      await zeroWrites(() async {
        await save();
      });
    });
    test('原时段过期禁止撤销，目标过去或跨日禁止保存', () async {
      final change = await save();
      clock = at(12);
      await zeroWrites(() async {
        await service.undo(change, sync: false);
      });
      final latest = service.capture(username, day, await persisted());
      await zeroWrites(() async {
        await service.save(latest, times(8, 9), sync: false);
      });
      await zeroWrites(() async {
        await service.save(latest, times(23, 25), sync: false);
      });
    });
    test('oplog失败整笔回滚，失败后可重试撤销', () async {
      final change = await save();
      await fixture.db.execute(
        "CREATE TRIGGER fail_drag BEFORE INSERT ON op_logs BEGIN SELECT RAISE(ABORT, 'test'); END",
      );
      await zeroWrites(() async {
        await service.undo(change, sync: false);
      }, stale: false);
      await fixture.db.execute('DROP TRIGGER fail_drag');
      await service.undo(change, sync: false);
      expect((await persisted()).startTime, original.startTime);
    });
    test('读取失败保留重试资格，不误判已删除', () async {
      final change = await save();
      await fixture.db.execute('ALTER TABLE todos RENAME TO unavailable_todos');
      await expectLater(
        service.validateUndo(change),
        throwsA(
          isA<PlanDragException>().having((e) => e.stale, 'stale', false),
        ),
      );
      await zeroWrites(() async {
        await service.undo(change, sync: false);
      }, stale: false);
      await fixture.db.execute('ALTER TABLE unavailable_todos RENAME TO todos');
      await service.undo(change, sync: false);
    });
    test('并发连击只有一次写入，撤销连击也只执行一次', () async {
      final first = service.save(snapshot, times(14, 15), sync: false);
      await expectLater(
        service.save(snapshot, times(16, 17), sync: false),
        throwsA(isA<PlanDragException>()),
      );
      final change = (await first)!;
      final undo = service.undo(change, sync: false);
      await expectLater(
        service.undo(change, sync: false),
        throwsA(isA<PlanDragException>()),
      );
      await undo;
      expect(await fixture.db.query('op_logs'), hasLength(2));
      await zeroWrites(() async {
        await service.undo(change, sync: false);
      });
    });
  });
  test('夏令时日期使用本地午夜边界，23或25小时日仍保时长', () {
    for (final pair in [
      (DateTime(2026, 3, 8), 23),
      (DateTime(2026, 11, 1), 25),
    ]) {
      final date = pair.$1;
      final last = DateTime(date.year, date.month, date.day + 1);
      if (Platform.environment['TZ'] == 'America/New_York') {
        expect(last.difference(date).inHours, pair.$2);
      }
      final original = PlanDragTimes(
        DateTime(date.year, date.month, date.day, 22, 30),
        DateTime(date.year, date.month, date.day, 23, 30),
      );
      final result = PlanDragGeometry.adjust(
        date: date,
        original: original,
        deltaMinutes: 9999,
        step: 15,
        kind: PlanDragKind.move,
      );
      expect(result.end, last);
      expect(result.minutes, 60);
      expect(result.start, DateTime(date.year, date.month, date.day, 23));
    }
  });
}
