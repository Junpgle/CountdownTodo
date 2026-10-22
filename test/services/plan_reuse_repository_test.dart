@TestOn('vm')
library;

import 'package:countdown_todo/models.dart';
import 'package:countdown_todo/models/plan_availability.dart';
import 'package:countdown_todo/services/plan_reuse_repository.dart';
import 'package:countdown_todo/services/plan_todo_guard.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/plan_availability_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late PlanAvailabilityFixture f;
  late PlanReuseRepository repo;
  late TodoPlanBlock source;
  final day = PlanAvailabilityFixture.day;
  const identity = PlanTodoIdentity(PlanAvailabilityFixture.username, 0);
  setUp(() async {
    f = PlanAvailabilityFixture();
    await f.initialize();
    // Exercise both the current conflict-aware schema and the optional-column
    // fallback used when reading older local databases.
    await f.db.execute(
      'ALTER TABLE todo_plan_blocks ADD COLUMN has_conflict INTEGER NOT NULL DEFAULT 0',
    );
    repo = PlanReuseRepository(
      database: f.db,
      clock: () => day.add(const Duration(hours: 8)),
    );
    source = TodoPlanBlock(
      id: 'source',
      todoId: 'todo-target',
      startTime: day
          .subtract(const Duration(days: 1))
          .add(const Duration(hours: 9))
          .millisecondsSinceEpoch,
      endTime: day
          .subtract(const Duration(days: 1))
          .add(const Duration(hours: 10))
          .millisecondsSinceEpoch,
      plannedMinutes: 777,
      actualFocusSeconds: 9999,
      status: TodoPlanStatus.finished,
      source: TodoPlanSource.ai,
      remark: '沿用备注',
      reminderMinutes: 10,
      pomodoroMinutes: 45,
      pomodoroRounds: 2,
      calendarEventId: 'source-calendar',
      pomodoroRecordIds: ['source-focus'],
    );
    await f.block(source);
  });
  tearDown(() => f.dispose());

  test(
    'reads only settings, actual interval and precise todo, with zero writes',
    () async {
      final before = await f.db.query('todo_plan_blocks');
      final operations = await f.db.query('op_logs');
      final seed = await repo.read(identity.username, source.id);
      expect(seed.settings.minutes, 60);
      expect(seed.settings.remark, '沿用备注');
      expect(
        [seed.settings.reminder, seed.settings.pomodoro, seed.settings.rounds],
        [10, 45, 2],
      );
      expect(seed.todo!.id, source.todoId);
      expect(seed.start, day.add(const Duration(hours: 9)));
      expect(await f.db.query('todo_plan_blocks'), before);
      expect(await f.db.query('op_logs'), operations);
      await f.db.update('todo_plan_blocks', {
        'remark': '源已变化',
        'is_deleted': 1,
      });
      expect(seed.settings.remark, '沿用备注');
    },
  );

  test(
    'future date retained, including local boundary and full-day interval',
    () async {
      final start = DateTime(day.year, day.month, day.day + 4);
      await f.db.update('todo_plan_blocks', {
        'start_time': start.millisecondsSinceEpoch,
        'end_time': start
            .add(const Duration(minutes: 1440))
            .millisecondsSinceEpoch,
      });
      final seed = await repo.read(identity.username, source.id);
      expect(seed.start, start);
      expect(seed.settings.minutes, 1440);
    },
  );

  for (final change in [
    {'is_deleted': 1},
    {'has_conflict': 1},
    {'status': 99},
    {'source': TodoPlanSource.calendar.index},
    {'start_time': 0},
    {'end_time': 0},
    {'todo_uuid': ''},
  ]) {
    test(
      'rejects raw invalid source $change without default coercion',
      () async {
        await f.db.update('todo_plan_blocks', change);
        await expectLater(
          repo.read(identity.username, source.id),
          throwsA(isA<PlanAvailabilityException>()),
        );
      },
    );
  }

  test(
    'repairs unsupported settings individually without writing the source',
    () async {
      await f.db.update('todo_plan_blocks', {
        'reminder_minutes': 7,
        'pomodoro_minutes': 45,
        'pomodoro_rounds': 7,
      });
      final blocksBefore = await f.db.query('todo_plan_blocks');
      final logsBefore = await f.db.query('op_logs');

      final seed = await repo.read(identity.username, source.id);

      expect(
        [seed.settings.reminder, seed.settings.pomodoro, seed.settings.rounds],
        [5, 45, 0],
      );
      expect(seed.settings.corrections.map((item) => item.summary).toList(), [
        '提前提醒：7 分钟前 → 5 分钟前',
        '番茄轮数：7 轮 → 按规划时长',
      ]);
      expect(await f.db.query('todo_plan_blocks'), blocksBefore);
      expect(await f.db.query('op_logs'), logsBefore);
    },
  );

  test(
    'unreadable settings use defaults and identify only the affected fields',
    () async {
      await f.db.update('todo_plan_blocks', {
        'reminder_minutes': 'legacy-value',
        'pomodoro_minutes': 30,
        'pomodoro_rounds': 2,
      });

      final seed = await repo.read(identity.username, source.id);

      expect(seed.settings.reminder, 5);
      expect(seed.settings.pomodoro, 30);
      expect(seed.settings.rounds, 2);
      expect(seed.settings.corrections.map((item) => item.summary).toList(), [
        '提前提醒：无法识别 → 5 分钟前',
      ]);
    },
  );

  test('rejects non-minute and oversized duration', () async {
    for (final delta in [60001, 1441 * 60000]) {
      await f.db.update('todo_plan_blocks', {
        'end_time': source.startTime + delta,
      });
      await expectLater(
        repo.read(identity.username, source.id),
        throwsA(isA<PlanAvailabilityException>()),
      );
    }
  });
  test('all legitimate statuses are usable settings sources', () async {
    for (final status in TodoPlanStatus.values) {
      await f.db.update('todo_plan_blocks', {'status': status.index});
      expect(
        (await repo.read(identity.username, source.id)).settings.minutes,
        60,
      );
    }
  });
  for (final change in [
    {'is_completed': 1},
    {'is_deleted': 1},
    {'has_conflict': 1},
  ]) {
    test('ineligible source todo leaves selection empty $change', () async {
      await f.db.update('todos', change);
      expect((await repo.read(identity.username, source.id)).todo, isNull);
    });
  }
  test('member completion overrides global state without selecting another recurrence', () async {
    await f.db.update('todos', {'collab_type': 1});
    await f.db.insert('todo_completions', {
      'todo_uuid': source.todoId,
      'user_id': 0,
      'is_completed': 1,
      'updated_at': source.updatedAt,
    });
    await f.todo('same-title-next-occurrence', '复习高数');
    expect((await repo.read(identity.username, source.id)).todo, isNull);
  });
  test('missing source todo allowed; source query failure is not an empty selection', () async {
    await f.db.delete('todos');
    expect((await repo.read(identity.username, source.id)).todo, isNull);
    await f.db.execute('DROP TABLE todo_plan_blocks');
    await expectLater(
      repo.read(identity.username, source.id),
      throwsA(anything),
    );
  });
  test('missing, mapped and changed identity rejected', () async {
    for (final id in ['missing', 'mapped_course_1', '']) {
      await expectLater(
        repo.read(identity.username, id),
        throwsA(isA<PlanAvailabilityException>()),
      );
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('current_user_id', 5);
    await expectLater(
      repo.savedTarget(identity, source),
      throwsA(isA<PlanAvailabilityException>()),
    );
  });
  test('older schema without optional conflict column works, missing required settings fails', () async {
    await f.db.execute('ALTER TABLE todo_plan_blocks DROP COLUMN has_conflict');
    expect(
      (await repo.read(identity.username, source.id)).settings.minutes,
      60,
    );
    await f.db.execute(
      'ALTER TABLE todo_plan_blocks DROP COLUMN reminder_minutes',
    );
    await expectLater(
      repo.read(identity.username, source.id),
      throwsA(anything),
    );
  });
  test('uncertain commit resolves only matching target, never overwrites or allocates an ID', () async {
    final draft = TodoPlanBlock(
      id: 'new-target',
      todoId: source.todoId,
      titleSnapshot: '复习高数',
      startTime: day.add(const Duration(hours: 12)).millisecondsSinceEpoch,
      endTime: day.add(const Duration(hours: 13)).millisecondsSinceEpoch,
      plannedMinutes: 60,
    );
    expect(await repo.savedTarget(identity, draft), isNull);
    await f.block(draft);
    expect((await repo.savedTarget(identity, draft))!.id, draft.id);
    await f.db.update(
      'todo_plan_blocks',
      {'remark': '新内容'},
      where: 'uuid=?',
      whereArgs: [draft.id],
    );
    await expectLater(
      repo.savedTarget(identity, draft),
      throwsA(isA<PlanAvailabilityException>()),
    );
    expect((await f.db.query('todo_plan_blocks')).length, 2);
  });
}
