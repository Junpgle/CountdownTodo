import 'dart:async';
import 'dart:convert';

import 'package:countdown_todo/services/pomodoro_service.dart';
import 'package:countdown_todo/utils/todo_recurrence_picker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:countdown_todo/models.dart';
import 'package:countdown_todo/services/plan_backlog_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/plan_availability_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late PlanAvailabilityFixture f;
  late PlanBacklogRepository repo;
  setUp(() async {
    f = PlanAvailabilityFixture();
    await f.initialize();
    repo = PlanBacklogRepository(clock: () => PlanAvailabilityFixture.now);
  });
  tearDown(() async => f.dispose());
  Future<PlanBacklogPage> read({
    bool scheduled = false,
    String search = '',
    String? folder,
    PlanBacklogCursor? cursor,
  }) => repo.read(
    PlanAvailabilityFixture.username,
    PlanAvailabilityFixture.day,
    scheduled: scheduled,
    search: search,
    folder: folder,
    cursor: cursor,
  );
  test(
    'future and cross-midnight plans are aggregated across every date',
    () async {
      await f.block(
        TodoPlanBlock(
          id: 'future',
          todoId: 'todo-target',
          startTime: DateTime(2026, 10, 9, 23).millisecondsSinceEpoch,
          endTime: DateTime(2026, 10, 10, 1).millisecondsSinceEpoch,
        ),
      );
      expect((await read()).total, 0);
      final page = await read(scheduled: true);
      expect(page.rows.single.planCount, 1);
      expect(page.rows.single.id, 'todo-target');
    },
  );
  test('past and inactive statuses do not hide unfinished tasks', () async {
    for (final status in TodoPlanStatus.values) {
      await f.block(
        TodoPlanBlock(
          id: status.name,
          todoId: 'todo-target',
          status: status,
          startTime: DateTime(2026, 10, 6, 10).millisecondsSinceEpoch,
          endTime: DateTime(2026, 10, 6, 11).millisecondsSinceEpoch,
        ),
      );
    }
    expect((await read()).total, 1);
  });
  test(
    'member completion overrides global only for independent collaboration',
    () async {
      await f.db.update(
        'todos',
        {'collab_type': 1, 'is_completed': 1},
        where: 'uuid=?',
        whereArgs: ['todo-target'],
      );
      await f.db.insert('todo_completions', {
        'todo_uuid': 'todo-target',
        'user_id': 0,
        'is_completed': 0,
      });
      expect((await read()).total, 1);
      await f.db.update('todo_completions', {'is_completed': 1});
      expect((await read()).total, 0);
    },
  );
  test('literal wildcards and 1000 rows use stable bounded pages; changes reset cursor', () async {
    await f.db.transaction((t) async {
      for (var i = 0; i < 1000; i++) {
        await t.insert('todos', {
          'uuid': 'bulk-${i.toString().padLeft(4, '0')}',
          'content': i == 0 ? '100%_完成' : '任务$i',
          'created_date': 0,
          'created_at': 1,
          'updated_at': 1,
        });
      }
    });
    expect((await read(search: '%_')).rows.single.id, 'bulk-0000');
    var page = await read();
    final ids = <String>{};
    while (true) {
      expect(page.rows.length, lessThanOrEqualTo(50));
      for (final row in page.rows) {
        expect(ids.add(row.id), true);
      }
      if (page.next == null) break;
      page = await read(cursor: page.next);
    }
    expect(ids.length, 1001);
    final first = await read();
    await f.todo('new', '新任务');
    expect((await read(cursor: first.next)).restarted, true);
  });
  test(
    'pending migration and identity changes are errors, not empty success',
    () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(
        'user_todos_${PlanAvailabilityFixture.username}',
        ['legacy'],
      );
      await expectLater(read(), throwsA(anything));
      await prefs.remove('user_todos_${PlanAvailabilityFixture.username}');
      await prefs.setString('current_login_user', 'other');
      await expectLater(read(), throwsA(anything));
    },
  );
  test('active statuses, legacy interval, date-only and deadlines keep distinct meaning', () async {
    await f.db.delete('todos');
    for (final status in TodoPlanStatus.values) {
      await f.todo('status-${status.index}', '任务${status.name}');
      await f.block(
        TodoPlanBlock(
          id: 'plan-${status.index}',
          todoId: 'status-${status.index}',
          status: status,
          startTime: DateTime(2026, 10, 9, 10).millisecondsSinceEpoch,
          endTime: DateTime(2026, 10, 9, 11).millisecondsSinceEpoch,
        ),
      );
    }
    await f.todo(
      'legacy-range',
      '旧式区间',
      legacyStart: DateTime(2026, 10, 9, 10),
      due: DateTime(2026, 10, 9, 11),
    );
    await f.todo(
      'date-only',
      '日期',
      legacyStart: DateTime(2026, 10, 9),
      due: DateTime(2026, 10, 9, 23, 59),
    );
    await f.todo('deadline-only', '截止', due: DateTime(2026, 10, 9, 20));
    await f.todo(
      'cross-day',
      '跨日截止',
      legacyStart: DateTime(2026, 10, 9, 10),
      due: DateTime(2026, 10, 10, 11),
    );
    final arranged = await read(scheduled: true);
    expect(arranged.rows.map((r) => r.id).toSet(), {
      'status-0',
      'status-2',
      'status-4',
      'status-5',
      'legacy-range',
    });
    expect(
      arranged.rows.singleWhere((r) => r.id == 'legacy-range').legacy,
      true,
    );
    final open = await read();
    expect(open.total, 7);
  });
  test('series representative is selected before scheduled filtering and matches picker', () async {
    await f.db.delete('todos');
    final input = <TodoItem>[];
    for (var i = 0; i < 10; i++) {
      final todo = TodoItem(
        id: 'series-item-$i',
        title: '第$i期',
        recurrenceSeriesId: 'series',
        createdDate: DateTime(2026, 10, 3 + i).millisecondsSinceEpoch,
        recurrence: i == 8 ? RecurrenceType.daily : RecurrenceType.none,
      );
      input.add(todo);
      await f.todo(todo.id, todo.title);
      await f.db.update(
        'todos',
        {
          'recurrence_series_id': 'series',
          'created_date': todo.createdDate,
          'recurrence': todo.recurrence.index,
        },
        where: 'uuid=?',
        whereArgs: [todo.id],
      );
    }
    for (final date in [
      DateTime(2026, 10, 8),
      DateTime(2026, 10, 1),
      DateTime(2026, 10, 20),
    ]) {
      final expected = collapseRecurrenceSeriesForTodoPicker(
        input,
        now: date,
      ).single.id;
      expect(
        (await repo.read(
          PlanAvailabilityFixture.username,
          date,
        )).rows.single.id,
        expected,
      );
    }
    await f.block(
      TodoPlanBlock(
        id: 'chosen-plan',
        todoId: 'series-item-5',
        startTime: DateTime(2026, 10, 9, 10).millisecondsSinceEpoch,
        endTime: DateTime(2026, 10, 9, 11).millisecondsSinceEpoch,
      ),
    );
    expect((await read()).total, 0);
    expect((await read(scheduled: true)).rows.single.id, 'series-item-5');
    await f.db.update(
      'todos',
      {'is_completed': 1},
      where: 'uuid=?',
      whereArgs: ['series-item-5'],
    );
    expect((await read()).rows.single.id, 'series-item-8');
  });
  test(
    'paused focus and invalid plans/conflicts cannot look unarranged',
    () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'pomodoro_run_state_${PlanAvailabilityFixture.username}',
        jsonEncode(
          PomodoroRunState(
            phase: PomodoroPhase.focusing,
            todoUuid: 'todo-target',
            isPaused: true,
          ).toJson(),
        ),
      );
      expect((await read()).total, 0);
      final focused = (await read(scheduled: true)).rows.single;
      expect(focused.focusing, true);
      expect(focused.paused, true);
      await prefs.remove(
        'pomodoro_run_state_${PlanAvailabilityFixture.username}',
      );
      await f.block(
        TodoPlanBlock(
          id: 'invalid-time',
          todoId: 'todo-target',
          startTime: 3,
          endTime: 2,
        ),
      );
      expect((await read(scheduled: true)).rows.single.needsReview, true);
      await expectLater(
        repo.prepare((await read(scheduled: true)).identity, 'todo-target'),
        throwsA(anything),
      );
    },
  );
  test(
    'read-only queries leave every business table and preferences unchanged',
    () async {
      final tables = [
        'todos',
        'todo_plan_blocks',
        'op_logs',
        'todo_completions',
        'pomodoro_records',
        'time_logs',
      ];
      final before = {
        for (final table in tables) table: await f.db.query(table),
      };
      final prefs = await SharedPreferences.getInstance();
      final keys = {for (final key in prefs.getKeys()) key: prefs.get(key)};
      await read();
      await read(scheduled: true);
      await read(search: '复习', folder: '');
      for (final table in tables) {
        expect(await f.db.query(table), before[table]);
      }
      expect({for (final key in prefs.getKeys()) key: prefs.get(key)}, keys);
    },
  );
  test('two focus bindings are review rows, never free tasks', () async {
    await f.todo('other-task', '另一项');
    await f.block(
      TodoPlanBlock(
        id: 'bound-plan',
        todoId: 'other-task',
        startTime: 1,
        endTime: 2,
        status: TodoPlanStatus.finished,
      ),
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'pomodoro_run_state_${PlanAvailabilityFixture.username}',
      jsonEncode(
        PomodoroRunState(
          phase: PomodoroPhase.focusing,
          todoUuid: 'todo-target',
          planBlockId: 'bound-plan',
        ).toJson(),
      ),
    );
    expect((await read()).total, 0);
    final page = await read(scheduled: true);
    expect(page.rows, hasLength(2));
    expect(page.rows.every((r) => r.needsReview), true);
    await expectLater(
      repo.prepare(page.identity, 'todo-target'),
      throwsA(anything),
    );
  });
  test(
    'folder normalization, counts, empty title and deleted tasks use one scope',
    () async {
      await f.db.insert('todo_groups', {
        'uuid': 'study-group',
        'name': '学习',
        'created_at': 1,
        'updated_at': 1,
      });
      await f.todo('study-task', '学习项目');
      await f.db.update(
        'todos',
        {'group_id': 'study-group'},
        where: 'uuid=?',
        whereArgs: ['study-task'],
      );
      await f.db.update(
        'todos',
        {'group_id': 'missing-folder'},
        where: 'uuid=?',
        whereArgs: ['todo-target'],
      );
      expect((await read(folder: 'study-group')).rows.single.id, 'study-task');
      expect((await read(folder: '')).rows.single.id, 'todo-target');
      await f.todo('empty-title', '   ');
      await f.todo('completed-task', '已完成', done: true);
      await f.todo('deleted-task', '已删除');
      await f.db.update(
        'todos',
        {'is_deleted': 1},
        where: 'uuid=?',
        whereArgs: ['deleted-task'],
      );
      expect((await read()).total, 2);
    },
  );
  test(
    'bounded metadata batches and page projection avoid per-todo reads',
    () async {
      await f.db.transaction((txn) async {
        for (var i = 0; i < 1000; i++) {
          await txn.insert('todos', {
            'uuid': 'projection-$i',
            'content': '任务$i',
            'remark': 'large ignored remark',
            'original_text': 'ignored',
            'created_at': 1,
            'updated_at': 1,
            'created_date': 0,
          });
        }
      });
      final queries = <String>[];
      final measured = PlanBacklogRepository(
        clock: () => PlanAvailabilityFixture.now,
        onQuery: queries.add,
      );
      final page = await measured.read(
        PlanAvailabilityFixture.username,
        PlanAvailabilityFixture.day,
      );
      expect(page.rows, hasLength(50));
      expect(page.total, 1001);
      expect(queries.length, lessThanOrEqualTo(14));
      expect(
        queries.any(
          (q) =>
              q.contains('remark') ||
              q.contains('original_text') ||
              q.contains('SELECT t.*'),
        ),
        false,
      );
      expect(queries.where((q) => q.contains('LIMIT 200')).length, 9);
    },
  );
  test('end boundary resets cursor even without a data write', () async {
    var instant = PlanAvailabilityFixture.now;
    final moving = PlanBacklogRepository(clock: () => instant);
    for (var i = 0; i < 51; i++) {
      await f.todo('boundary-task-$i', '边界$i');
    }
    await f.block(
      TodoPlanBlock(
        id: 'ending-plan',
        todoId: 'todo-target',
        startTime: instant
            .subtract(const Duration(hours: 1))
            .millisecondsSinceEpoch,
        endTime: instant.add(const Duration(minutes: 1)).millisecondsSinceEpoch,
      ),
    );
    final first = await moving.read(
      PlanAvailabilityFixture.username,
      PlanAvailabilityFixture.day,
    );
    expect(first.nextBoundary, instant.add(const Duration(minutes: 1)));
    instant = instant.add(const Duration(minutes: 2));
    final second = await moving.read(
      PlanAvailabilityFixture.username,
      PlanAvailabilityFixture.day,
      cursor: first.next,
    );
    expect(second.restarted, true);
    expect(second.total, 52);
  });
  for (final size in [50, 51, 500]) {
    test(
      '$size tasks have exact totals and no missing or duplicate pages',
      () async {
        await f.db.delete('todos');
        await f.db.transaction((txn) async {
          for (var i = 0; i < size; i++) {
            await txn.insert('todos', {
              'uuid': 'sized-${i.toString().padLeft(4, '0')}',
              'content': '任务$i',
              'created_at': 1,
              'updated_at': 1,
              'created_date': 0,
            });
          }
        });
        final ids = <String>{};
        var page = await read();
        while (true) {
          expect(page.total, size);
          expect(page.rows.length, lessThanOrEqualTo(50));
          for (final row in page.rows) {
            expect(ids.add(row.id), true);
          }
          if (page.next == null) break;
          page = await read(cursor: page.next);
        }
        expect(ids.length, size);
      },
    );
  }
  test(
    'member identity changing during SQL read rejects the old snapshot',
    () async {
      final prefs = await SharedPreferences.getInstance();
      var changed = false;
      final racing = PlanBacklogRepository(
        clock: () => PlanAvailabilityFixture.now,
        onQuery: (_) {
          if (!changed) {
            changed = true;
            unawaited(prefs.setInt('current_user_id', 99));
          }
        },
      );
      await expectLater(
        racing.read(
          PlanAvailabilityFixture.username,
          PlanAvailabilityFixture.day,
        ),
        throwsA(anything),
      );
    },
  );
}
