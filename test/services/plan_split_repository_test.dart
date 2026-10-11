@TestOn('vm')
library;

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import 'package:countdown_todo/models.dart';
import 'package:countdown_todo/models/plan_availability.dart';
import 'package:countdown_todo/models/plan_split.dart';
import 'package:countdown_todo/services/plan_availability_repository.dart';
import 'package:countdown_todo/services/plan_editor_draft_repository.dart';
import 'package:countdown_todo/services/plan_split_service.dart';
import 'package:countdown_todo/services/plan_todo_guard.dart';
import 'package:countdown_todo/storage_service.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/plan_availability_fixture.dart';

class _AfterRead extends PlanAvailabilityRepository {
  _AfterRead(Database db, this.after)
    : super(databaseOverride: db, clock: () => PlanAvailabilityFixture.now);
  final Future<void> Function() after;
  @override
  Future<PlanSplitSnapshot> readSplit(
    PlanSplitQuery query, {
    bool forceRefresh = false,
    bool requireCalendar = false,
  }) async {
    final s = await super.readSplit(
      query,
      forceRefresh: forceRefresh,
      requireCalendar: requireCalendar,
    );
    await after();
    return s;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late PlanAvailabilityFixture f;
  late PlanAvailabilityRepository repo;
  final day = PlanAvailabilityFixture.day, now = PlanAvailabilityFixture.now;
  const identity = PlanTodoIdentity(PlanAvailabilityFixture.username, 0);
  PlanSplitQuery q() => PlanSplitQuery(
    PlanAvailabilityQuery(
      username: identity.username,
      todoId: 'todo-target',
      date: day,
      minutes: 90,
    ),
  );
  Future<PlanSplitSelection> selection() async {
    final query = q(), s = await repo.readSplit(q());
    return PlanSplitSelection(
      query,
      PlanSplitService.find(query, s, now: now).groups.first,
      s,
    );
  }

  List<TodoPlanBlock> blocks(PlanSplitSelection s) => [
    for (var i = 0; i < s.slots.length; i++)
      TodoPlanBlock(
        id: 'split-$i',
        todoId: 'todo-target',
        startTime: s.slots[i].start.millisecondsSinceEpoch,
        endTime: s.slots[i].end.millisecondsSinceEpoch,
        plannedMinutes: s.slots[i].minutes,
        reminderMinutes: 5,
        pomodoroMinutes: 25,
        pomodoroRounds: 0,
      ),
  ];
  Future<int> count(String table) async =>
      (await f.db.rawQuery('SELECT COUNT(*) n FROM $table')).single['n'] as int;
  PlanDraftFields fields(PlanSplitSelection s) => PlanDraftFields(
    todoId: 'todo-target',
    title: '复习高数',
    start: s.slots.first.start.millisecondsSinceEpoch,
    end: s.slots.first.end.millisecondsSinceEpoch,
    remark: '',
    reminder: 5,
    pomodoro: 25,
    rounds: 0,
    origin: 'timeline',
    offsetMinutes: 0,
    split: PlanSplitDraft(
      s.query,
      s.slots,
      blocks(s).map((b) => b.id).toList(),
    ),
  );
  setUp(() async {
    f = PlanAvailabilityFixture();
    await f.initialize();
    repo = PlanAvailabilityRepository(databaseOverride: f.db, clock: () => now);
  });
  tearDown(() async {
    await f.dispose();
  });
  test('whole group and oplogs commit together; retry has no duplicate refresh or writes', () async {
    final s = await selection(), drafts = blocks(await selection());
    var refresh = 0;
    void listener() {
      refresh++;
    }

    StorageService.scopedDataRefreshNotifier.addListener(listener);
    try {
      final saved = await repo.saveSplit(s, drafts, sync: false);
      expect(saved.length, 2);
      await Future<void>.delayed(const Duration(milliseconds: 250));
      expect(await count('todo_plan_blocks'), 2);
      expect(await count('op_logs'), 2);
      expect(refresh, 1);
      await repo.saveSplit(s, drafts, sync: false);
      await Future<void>.delayed(const Duration(milliseconds: 250));
      expect(await count('todo_plan_blocks'), 2);
      expect(await count('op_logs'), 2);
      expect(refresh, 1);
    } finally {
      StorageService.scopedDataRefreshNotifier.removeListener(listener);
    }
  });
  test('second insert failure rolls back first block and all oplogs', () async {
    final s = await selection();
    await f.db.execute(
      "CREATE TRIGGER fail_second BEFORE INSERT ON todo_plan_blocks WHEN NEW.uuid='split-1' BEGIN SELECT RAISE(ABORT,'fault'); END",
    );
    await expectLater(
      repo.saveSplit(s, blocks(s), sync: false),
      throwsA(anything),
    );
    expect(await count('todo_plan_blocks'), 0);
    expect(await count('op_logs'), 0);
  });
  test('late busy source aborts group and preserves sources', () async {
    final s = await selection();
    await f.fixed('new', s.slots.last.start, s.slots.last.end);
    await expectLater(
      repo.saveSplit(s, blocks(s), sync: false),
      throwsA(isA<PlanAvailabilityException>()),
    );
    expect(await count('todo_plan_blocks'), 0);
    expect(await count('op_logs'), 0);
    expect(await count('fixed_schedules'), 1);
  });
  test('guard failure inside transaction rolls back all mutations', () async {
    final s = await selection();
    await expectLater(
      repo.saveSplit(
        s,
        blocks(s),
        sync: false,
        beforeWrite: (db) async {
          await db.update(
            'todos',
            {'is_completed': 1},
            where: 'uuid=?',
            whereArgs: ['todo-target'],
          );
          throw StateError('race');
        },
      ),
      throwsStateError,
    );
    expect((await f.db.query('todos')).single['is_completed'], 0);
    expect(await count('todo_plan_blocks'), 0);
  });
  test(
    'partial target, changed target and completed todo are never overwritten',
    () async {
      final s = await selection(), b = blocks(await selection());
      await f.block(b.first);
      await expectLater(repo.saveSplit(s, b, sync: false), throwsStateError);
      expect(await count('todo_plan_blocks'), 1);
      await f.block(b.last);
      await f.db.update(
        'todo_plan_blocks',
        {'remark': 'new'},
        where: 'uuid=?',
        whereArgs: [b.first.id],
      );
      await expectLater(repo.saveSplit(s, b, sync: false), throwsStateError);
      expect(await count('todo_plan_blocks'), 2);
    },
  );
  test('v2 draft is one capacity slot, revision guarded, no occupancy or override persisted', () async {
    final s = await selection(),
        draftRepo = PlanEditorDraftRepository(database: f.db, clock: () => now);
    final d = await draftRepo.keep(identity, fields(s), targetId: 'split-0');
    final row = (await f.db.query(PlanEditorDraftRepository.table)).single;
    expect(row['format_version'], 2);
    expect(
      jsonDecode(row['form_json'] as String)['split'].keys,
      isNot(contains('appOnly')),
    );
    final list = await draftRepo.list(identity);
    expect(list.single.parts, 2);
    expect(list.single.total, 90);
    expect(list.single.lastEnd, s.slots.last.end.millisecondsSinceEpoch);
    final read = await draftRepo.read(identity, d.id);
    expect(read.fields.fingerprint, d.fields.fingerprint);
    expect(await count('todo_plan_blocks'), 0);
    expect(await count('op_logs'), 0);
    await draftRepo.keep(identity, fields(s), targetId: 'split-0', previous: d);
    await expectLater(
      draftRepo.validateRevision(f.db, identity, d),
      throwsStateError,
    );
  });
  test(
    'all saved draft targets recognized; partial or deleted target refused',
    () async {
      final s = await selection(),
          r = PlanEditorDraftRepository(database: f.db);
      final d = await r.keep(identity, fields(s), targetId: 'split-0');
      await f.block(blocks(s).first);
      await expectLater(r.target(identity, d), throwsStateError);
      await f.block(blocks(s).last);
      expect((await r.target(identity, d))!.id, 'split-0');
      await f.db.update(
        'todo_plan_blocks',
        {'is_deleted': 1},
        where: 'uuid=?',
        whereArgs: ['split-1'],
      );
      await expectLater(r.target(identity, d), throwsStateError);
    },
  );
  test(
    'v2 malformed group refuses restore without harming other drafts',
    () async {
      final s = await selection(),
          r = PlanEditorDraftRepository(database: f.db);
      final d = await r.keep(identity, fields(s), targetId: 'split-0');
      final raw = fields(s).toJson();
      (raw['split'] as Map)['total'] = 91;
      await f.db.update(
        PlanEditorDraftRepository.table,
        {'form_json': jsonEncode(raw)},
        where: 'uuid=?',
        whereArgs: [d.id],
      );
      await expectLater(r.read(identity, d.id), throwsStateError);
      expect((await r.list(identity)).single.readable, isFalse);
      (raw['split'] as Map)['total'] = 90;
      for (final timestamp in [0, 8640000000000001]) {
        (raw['split'] as Map)['date'] = timestamp;
        await f.db.update(
          PlanEditorDraftRepository.table,
          {'form_json': jsonEncode(raw)},
          where: 'uuid=?',
          whereArgs: [d.id],
        );
        await expectLater(r.read(identity, d.id), throwsStateError);
        expect((await r.list(identity)).single.readable, isFalse);
      }
    },
  );
  test(
    'oplog failure on second segment rolls back every segment and log',
    () async {
      final s = await selection();
      await f.db.execute(
        "CREATE TRIGGER fail_log BEFORE INSERT ON op_logs WHEN NEW.target_uuid='split-1' BEGIN SELECT RAISE(ABORT,'log-fault'); END",
      );
      await expectLater(
        repo.saveSplit(s, blocks(s), sync: false),
        throwsA(anything),
      );
      expect(await count('todo_plan_blocks'), 0);
      expect(await count('op_logs'), 0);
    },
  );
  test('neighbor inserted after fresh source read is caught by transaction re-read', () async {
    final s = await selection();
    final race = _AfterRead(
      f.db,
      () async => f.fixed('race', s.slots.last.start, s.slots.last.end),
    );
    await expectLater(
      race.saveSplit(s, blocks(s), sync: false),
      throwsA(isA<PlanAvailabilityException>()),
    );
    expect(await count('todo_plan_blocks'), 0);
    expect(await count('op_logs'), 0);
  });
  for (final change in [
    {'is_completed': 1},
    {'is_deleted': 1},
    {'has_conflict': 1},
  ]) {
    test('latest todo $change refuses the complete group', () async {
      final s = await selection();
      await f.db.update(
        'todos',
        change,
        where: 'uuid=?',
        whereArgs: ['todo-target'],
      );
      await expectLater(
        repo.saveSplit(s, blocks(s), sync: false),
        throwsA(isA<PlanAvailabilityException>()),
      );
      expect(await count('todo_plan_blocks'), 0);
    });
  }
  test('member switch before transaction prevents all writes', () async {
    final s = await selection();
    final race = _AfterRead(f.db, () async {
      await (await SharedPreferences.getInstance()).setInt(
        'current_user_id',
        7,
      );
    });
    await expectLater(
      race.saveSplit(s, blocks(s), sync: false),
      throwsA(isA<PlanAvailabilityException>()),
    );
    expect(await count('todo_plan_blocks'), 0);
    expect(await count('op_logs'), 0);
  });
  test(
    'v1 converts to v2 with original first target and uses one of five slots',
    () async {
      final s = await selection(),
          r = PlanEditorDraftRepository(database: f.db);
      final split = fields(s),
          single = PlanDraftFields(
            todoId: split.todoId,
            title: split.title,
            start: split.start,
            end: split.end,
            remark: '',
            reminder: 5,
            pomodoro: 25,
            rounds: 0,
            origin: 'timeline',
            offsetMinutes: 0,
          );
      final v1 = await r.keep(identity, single, targetId: 'split-0');
      final v2 = await r.keep(
        identity,
        split,
        previous: v1,
        targetId: 'split-0',
      );
      expect(v2.targetId, v1.targetId);
      expect(await count(PlanEditorDraftRepository.table), 1);
      for (var i = 0; i < 4; i++) {
        await r.keep(identity, single, targetId: 'extra-$i');
      }
      await expectLater(
        r.keep(identity, split, targetId: 'split-0'),
        throwsStateError,
      );
      expect(await count(PlanEditorDraftRepository.table), 5);
    },
  );
  test(
    'payload limit and duplicate ids refuse a v2 draft without writes',
    () async {
      final s = await selection(),
          r = PlanEditorDraftRepository(database: f.db),
          raw = fields(await selection()).toJson();
      raw['remark'] = 'x' * (256 * 1024);
      await expectLater(
        r.keep(identity, PlanDraftFields.fromJson(raw), targetId: 'split-0'),
        throwsStateError,
      );
      final payload = raw['split'] as Map,
          segments = payload['segments'] as List;
      segments[1]['id'] = segments[0]['id'];
      expect(() => PlanDraftFields.fromJson(raw), throwsFormatException);
      expect(await count(PlanEditorDraftRepository.table), 0);
      expect(s.slots, hasLength(2));
    },
  );
}
