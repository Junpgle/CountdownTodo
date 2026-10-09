import 'dart:convert';

import 'package:countdown_todo/models.dart';
import 'package:countdown_todo/services/plan_execution_repository.dart';
import 'package:countdown_todo/services/pomodoro_service.dart';
import 'package:countdown_todo/storage_service.dart';
import 'package:countdown_todo/widgets/plan_execution_view.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/plan_availability_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late PlanAvailabilityFixture fixture;
  final day = PlanAvailabilityFixture.day;
  int at(int hour, [int minute = 0]) => DateTime(
    day.year,
    day.month,
    day.day,
    hour,
    minute,
  ).millisecondsSinceEpoch;
  setUp(() async {
    fixture = PlanAvailabilityFixture();
    await fixture.initialize();
  });
  tearDown(() => fixture.dispose());

  test('按当天重叠读取专注与日志，跨午夜不遗漏，不含删除或边界外记录', () async {
    for (final record in [
      PomodoroRecord(
        uuid: 'overnight',
        startTime: at(-1),
        endTime: at(1),
        plannedDuration: 7200,
        actualDuration: 3600,
      ),
      PomodoroRecord(
        uuid: 'short-focus',
        startTime: at(3),
        endTime: at(3, 10),
        plannedDuration: 1800,
        actualDuration: 600,
      ),
      PomodoroRecord(
        uuid: 'ends-at-midnight',
        startTime: at(-2),
        endTime: at(0),
        plannedDuration: 7200,
      ),
      PomodoroRecord(
        uuid: 'next-day',
        startTime: at(24),
        endTime: at(25),
        plannedDuration: 3600,
      ),
      PomodoroRecord(
        uuid: 'deleted',
        startTime: at(5),
        endTime: at(6),
        plannedDuration: 3600,
        isDeleted: true,
      ),
    ]) {
      await fixture.db.insert('pomodoro_records', {
        ...record.toJson(),
        'tag_uuids': jsonEncode(record.tagUuids),
        'actual_duration': record.effectiveDuration,
      });
    }
    await StorageService.saveTimeLogs(PlanAvailabilityFixture.username, [
      TimeLogItem(
        id: 'overnight-log',
        title: '跨午夜阅读',
        startTime: at(-1, 30),
        endTime: at(0, 30),
        tagUuids: ['tag-one'],
      ),
      TimeLogItem(id: 'day-log', title: '运动', startTime: at(7), endTime: at(8)),
      TimeLogItem(
        id: 'edge-log',
        title: '边界',
        startTime: at(-1),
        endTime: at(0),
      ),
      TimeLogItem(
        id: 'deleted-log',
        title: '已删除',
        startTime: at(9),
        endTime: at(10),
        isDeleted: true,
      ),
      TimeLogItem(
        id: 'invalid-log',
        title: '无效',
        startTime: at(10),
        endTime: at(9),
      ),
    ], sync: false);
    final before = await fixture.db.query('time_logs');
    final data = await PlanExecutionRepository(databaseOverride: fixture.db)
        .read(PlanAvailabilityFixture.username, day);
    expect(data.records.map((r) => r.uuid), ['overnight', 'short-focus']);
    expect(data.logs.map((l) => l.id), ['overnight-log', 'day-log']);
    expect(data.logs.first.tagUuids, ['tag-one']);
    final entries = PlanExecutionEntry.forDay(day, data.records, data.logs);
    expect(entries, hasLength(4));
    expect(entries.first.start, at(-1));
    expect(entries.first.end, at(1));
    expect(data.records.first.effectiveDuration, 3600);
    expect(await fixture.db.query('time_logs'), before);
    expect(await fixture.db.query('todo_plan_blocks'), isEmpty);
    expect(await fixture.db.query('op_logs'), isEmpty);
  });

  test('历史空标签不隐藏日志，旧专注缓存按原迁移路径恢复', () async {
    final prefs = await SharedPreferences.getInstance();
    final record = PomodoroRecord(
      uuid: 'legacy-focus',
      todoTitle: '旧专注',
      startTime: at(8),
      endTime: at(9),
      plannedDuration: 3600,
      actualDuration: 1800,
    );
    await prefs.setString(
      'pomodoro_records_${PlanAvailabilityFixture.username}',
      jsonEncode([record.toJson()]),
    );
    await StorageService.saveTimeLogs(PlanAvailabilityFixture.username, [
      TimeLogItem(
        id: 'old-tags',
        title: '旧空标签日志',
        startTime: at(10),
        endTime: at(11),
      ),
    ], sync: false);
    await fixture.db.update(
      'time_logs',
      {'tag_uuids': ''},
      where: 'uuid = ?',
      whereArgs: ['old-tags'],
    );
    final data = await PlanExecutionRepository(databaseOverride: fixture.db)
        .read(PlanAvailabilityFixture.username, day);
    expect(data.records.single.uuid, 'legacy-focus');
    expect(data.logs.single.tagUuids, isEmpty);
    expect(data.logs.single.title, '旧空标签日志');
    expect(await fixture.db.query('todo_plan_blocks'), isEmpty);
    expect(await fixture.db.query('op_logs'), isEmpty);
  });

  test('账号切换和读取失败明确报错，不伪装成空记录', () async {
    final repo = PlanExecutionRepository(databaseOverride: fixture.db);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('current_login_user', 'other-account');
    await expectLater(
      repo.read(PlanAvailabilityFixture.username, day),
      throwsStateError,
    );
    await prefs.setString(
      'current_login_user',
      PlanAvailabilityFixture.username,
    );
    await fixture.db.execute('DROP TABLE time_logs');
    await expectLater(
      repo.read(PlanAvailabilityFixture.username, day),
      throwsA(isA<Exception>()),
    );
  });

  test('旧日志迁移继续生效，保存发出时间日志刷新信号', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      'user_time_logs_${PlanAvailabilityFixture.username}',
      ['{"id":"legacy-log","title":"旧日志","start_time":${at(8)},"end_time":${at(9)}}'],
    );
    final data = await PlanExecutionRepository(databaseOverride: fixture.db)
        .read(PlanAvailabilityFixture.username, day);
    expect(data.logs.single.id, 'legacy-log');
    expect(
      prefs.getStringList('user_time_logs_${PlanAvailabilityFixture.username}'),
      isNull,
    );
    expect(
      StorageService.scopedDataRefreshNotifier.value.affects(
        DataRefreshDomain.timeLogs,
      ),
      isTrue,
    );
  });
}
