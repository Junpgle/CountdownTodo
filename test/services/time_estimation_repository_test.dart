import 'dart:async';
import 'dart:convert';

import 'package:countdown_todo/models.dart';
import 'package:countdown_todo/services/time_estimation_repository.dart';
import 'package:countdown_todo/services/time_estimation_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import '../support/plan_availability_fixture.dart';

class GatedDatabase implements Database {
  GatedDatabase(this.inner);
  final Database inner;
  final started = Completer<void>(), release = Completer<void>();
  @override
  Future<T> transaction<T>(
    Future<T> Function(Transaction txn) action, {
    bool? exclusive,
  }) => inner.transaction((txn) async {
    started.complete();
    await release.future;
    return action(txn);
  }, exclusive: exclusive);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late PlanAvailabilityFixture fixture;
  late TimeEstimationRepository repository;
  bool nullableRecordSchema = false;
  final now = DateTime(2026, 10, 10, 12);
  final end = now.subtract(const Duration(days: 1)).millisecondsSinceEpoch;
  const user = PlanAvailabilityFixture.username;
  Future<void> record(
    String id, [
    Map<String, Object?> change = const {},
  ]) async {
    // Older schemas permitted nulls; retain real production constraints for
    // other tests and exercise a nullable compatibility shape only as needed.
    if (!nullableRecordSchema &&
        change.entries.any(
          (e) =>
              e.value == null || e.value is double && (e.value as double).isNaN,
        )) {
      await fixture.db.execute(
        'CREATE TABLE legacy_records AS SELECT * FROM pomodoro_records',
      );
      await fixture.db.execute('DROP TABLE pomodoro_records');
      await fixture.db.execute(
        'ALTER TABLE legacy_records RENAME TO pomodoro_records',
      );
      await fixture.db.execute(
        'CREATE UNIQUE INDEX legacy_record_uuid ON pomodoro_records(uuid)',
      );
      nullableRecordSchema = true;
    }
    await fixture.db.insert('pomodoro_records', {
      'uuid': id,
      'todo_uuid': 'todo-target',
      'todo_title': '旧标题',
      'start_time': end - 600000,
      'end_time': end,
      'actual_duration': 600,
      'planned_duration': 1500,
      'status': 'completed',
      'tag_uuids': '[]',
      'created_at': end,
      'updated_at': end,
      ...change,
    });
  }

  Future<void> plan(
    String id, {
    String todo = 'todo-target',
    bool deleted = false,
  }) => fixture.block(
    TodoPlanBlock(
      id: id,
      todoId: todo,
      titleSnapshot: '无关快照',
      startTime: end - 600000,
      endTime: end,
      actualFocusSeconds: 600,
      plannedMinutes: 180,
      isDeleted: deleted,
    ),
  );
  Future<TimeEstimationHistory> read() => repository.read(user, now);
  Future<String> snapshot() async {
    final rows = <String, Object?>{};
    for (final table in [
      'todos',
      'todo_plan_blocks',
      'pomodoro_records',
      'op_logs',
      'fixed_schedules',
      'time_logs',
    ]) {
      rows[table] = await fixture.db.query(table, orderBy: 'id');
    }
    return jsonEncode(rows);
  }

  setUp(() async {
    nullableRecordSchema = false;
    fixture = PlanAvailabilityFixture();
    await fixture.initialize();
    await fixture.db.update(
      'todos',
      {'is_completed': 1},
      where: 'uuid = ?',
      whereArgs: ['todo-target'],
    );
    repository = TimeEstimationRepository(databaseOverride: fixture.db);
  });
  tearDown(() => fixture.dispose());

  test('多轮按秒累计，规范标题优先，计划汇总不重复，读取逐表零写入', () async {
    await plan('plan-linked');
    await record('a', {'actual_duration': 61, 'plan_block_id': 'plan-linked'});
    await record('b', {'actual_duration': 61, 'status': 'abandoned'});
    final before = await snapshot();
    final history = await read();
    expect(history.samples.single.actualSeconds, 122);
    expect(history.samples.single.title, '复习高数');
    await TimeEstimationService.estimate(
      '复习高数',
      username: user,
      repository: repository,
      clock: () => now,
    );
    expect(await snapshot(), before);
    expect(() => history.samples.clear(), throwsUnsupportedError);
  });
  test('已知零实际不回退计划；与有效轮次合并时只加真实秒数', () async {
    await record('zero', {'actual_duration': 0});
    final zero = await read();
    expect(zero.samples, isEmpty);
    expect(zero.noActualCount, 1);
    expect(zero.incompleteCount, 0);
    await record('actual');
    expect((await read()).samples.single.actualSeconds, 600);
  });
  final invalids = <String, Map<String, Object?>>{
    '缺实际值': {'actual_duration': null},
    '负实际值': {'actual_duration': -1},
    '小数秒': {'actual_duration': 1.5},
    '非数值': {'actual_duration': 'unknown'},
    '无限值': {'actual_duration': double.infinity},
    '非有限值': {'actual_duration': double.nan},
    '超过墙钟': {'actual_duration': 10000},
    '未结束': {'end_time': null},
    '未来': {'end_time': end + 2 * Duration.millisecondsPerDay},
    '无效开始': {'start_time': 0},
    '倒置时间': {'start_time': end + 1},
    '未知状态': {'status': 'focusing'},
    '记录冲突': {'has_conflict': 1},
    '缺身份': {'uuid': null},
  };
  for (final entry in invalids.entries) {
    test('${entry.key}污染整项完成任务，不能仅累计剩余轮次', () async {
      await record('good');
      await record('bad', entry.value);
      final history = await read();
      expect(history.samples, isEmpty);
      expect(history.incompleteCount, 1);
    });
  }
  test('删除的坏记录不污染任务；明确暂停时长不再扣除实际值', () async {
    await record('deleted', {'is_deleted': 1, 'actual_duration': null});
    await record('valid', {'actual_duration': 300, 'total_pause_seconds': 300});
    expect((await read()).samples.single.actualSeconds, 300);
  });
  for (final value in [
    {'is_completed': 0},
    {'is_deleted': 1},
    {'has_conflict': 1},
    {'content': '  '},
  ]) {
    test('无资格待办不成为完成样本：$value', () async {
      await record('valid');
      await fixture.db.update(
        'todos',
        value,
        where: 'uuid = ?',
        whereArgs: ['todo-target'],
      );
      expect((await read()).samples, isEmpty);
    });
  }
  test('只在直接绑定缺失时通过有效规划关联，不靠标题猜任务', () async {
    await plan('plan-linked');
    await record('fallback', {
      'todo_uuid': null,
      'plan_block_id': 'plan-linked',
    });
    await record('free', {'todo_uuid': null, 'todo_title': '复习高数'});
    expect((await read()).samples.single.actualSeconds, 600);
  });
  test('无直接绑定的已删除、映射和不存在规划不能冒充归属', () async {
    await plan('plan-deleted', deleted: true);
    await plan('mapped_course_demo');
    for (final id in ['plan-deleted', 'mapped_course_demo', 'missing-plan']) {
      await record(id, {'todo_uuid': null, 'plan_block_id': id});
    }
    expect((await read()).samples, isEmpty);
    await record('direct', {'plan_block_id': 'missing-plan'});
    expect((await read()).samples.single.actualSeconds, 600);
  });
  test('相互矛盾的两种关联让两边待办都不完整', () async {
    await fixture.todo('todo-other', '其他任务', done: true);
    await plan('plan-other', todo: 'todo-other');
    await record('first-good');
    await record('second-good', {'todo_uuid': 'todo-other'});
    await record('conflict', {'plan_block_id': 'plan-other'});
    final history = await read();
    expect(history.samples, isEmpty);
    expect(history.incompleteCount, 2);
  });
  test('跨午夜按完整实际值累计，同名与重复系列每期独立', () async {
    await fixture.todo('todo-period-2', '复习高数', done: true);
    await fixture.db.update(
      'todos',
      {'recurrence_series_id': 'series-demo'},
      where: 'uuid IN (?, ?)',
      whereArgs: ['todo-target', 'todo-period-2'],
    );
    final midnight = DateTime(2026, 10, 9).millisecondsSinceEpoch;
    await record('cross-midnight', {
      'start_time': midnight - 1800000,
      'end_time': midnight + 1800000,
      'actual_duration': 3600,
    });
    await record('other-period', {
      'todo_uuid': 'todo-period-2',
      'actual_duration': 300,
    });
    expect((await read()).samples.map((s) => s.actualSeconds).toSet(), {
      3600,
      300,
    });
  });
  test('标签以解析后UUID集合保存，坏JSON不创建假匹配', () async {
    await record('a', {'tag_uuids': '["tag-1","tag-10"]'});
    await record('b', {'tag_uuids': '["tag-2",7,null]'});
    await record('c', {'tag_uuids': 'tag-3'});
    final sample = (await read()).samples.single;
    expect(sample.tagIds, {'tag-1', 'tag-10', 'tag-2'});
    expect(() => sample.tagIds.add('bad'), throwsUnsupportedError);
  });
  test('先完成聚合再限制500任务，700轮任务不被截成部分时长', () async {
    await fixture.db.transaction((txn) async {
      final batch = txn.batch();
      for (var i = 0; i < 501; i++) {
        final id = 'task-$i';
        batch.insert('todos', {
          'uuid': id,
          'content': '复习高数',
          'created_date': 0,
          'is_completed': 1,
          'created_at': end,
          'updated_at': end,
        });
        batch.insert('pomodoro_records', {
          'uuid': 'round-$i',
          'todo_uuid': id,
          'start_time': end - 600000,
          'end_time': end - 1000,
          'actual_duration': 60,
          'status': 'completed',
          'tag_uuids': '[]',
          'todo_title': '复习高数',
          'planned_duration': 1500,
          'created_at': end,
          'updated_at': end,
        });
      }
      for (var i = 0; i < 700; i++) {
        batch.insert('pomodoro_records', {
          'uuid': 'many-$i',
          'todo_uuid': 'todo-target',
          'start_time': end - 600000,
          'end_time': end,
          'actual_duration': 60,
          'status': 'completed',
          'tag_uuids': '["exact-tag"]',
          'todo_title': '复习高数',
          'planned_duration': 1500,
          'created_at': end,
          'updated_at': end,
        });
      }
      await batch.commit(noResult: true);
    });
    final history = await read();
    expect(history.samples.length, 500);
    final target = history.samples.singleWhere(
      (s) => s.todoId == 'todo-target',
    );
    expect(target.actualSeconds, 700 * 60);
    expect(target.tagIds, {'exact-tag'});
  });
  test('有坏历史和真正空历史区分；数据库故障明确返回读取失败', () async {
    final empty = await TimeEstimationService.estimate(
      '复习高数',
      username: user,
      repository: repository,
      clock: () => now,
    );
    expect(empty.source, TimeEstimationSource.heuristic);
    expect(empty.incompleteCount, 0);
    await record('bad', {'actual_duration': null});
    final incomplete = await TimeEstimationService.estimate(
      '复习高数',
      username: user,
      repository: repository,
      clock: () => now,
    );
    expect(incomplete.incompleteCount, 1);
    expect(incomplete.reason, contains('记录不完整'));
    await fixture.db.execute(
      'ALTER TABLE pomodoro_records RENAME TO unavailable_records',
    );
    final failure = await TimeEstimationService.estimate(
      '复习高数',
      username: user,
      repository: repository,
      clock: () => now,
    );
    expect(failure.source, TimeEstimationSource.readFailure);
    expect(failure.reason, contains('读取失败'));
    expect(failure.samples, isEmpty);
    await fixture.db.execute(
      'ALTER TABLE unavailable_records RENAME TO pomodoro_records',
    );
  });
  test('切账号前拒绝读取；读取中切账号拒绝返回旧结果', () async {
    await record('valid');
    final gated = GatedDatabase(fixture.db);
    final future = TimeEstimationRepository(databaseOverride: gated)
        .read(user, now);
    final rejected = expectLater(
      future,
      throwsA(isA<TimeEstimationAccountChanged>()),
    );
    await gated.started.future;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('current_login_user', 'another-user');
    gated.release.complete();
    await rejected;
    await expectLater(
      repository.read(user, now),
      throwsA(isA<TimeEstimationAccountChanged>()),
    );
    await expectLater(
      TimeEstimationService.estimate(
        '复习高数',
        username: user,
        repository: repository,
        clock: () => now,
      ),
      throwsA(isA<TimeEstimationAccountChanged>()),
    );
  });
}
