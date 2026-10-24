@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:countdown_todo/models.dart';
import 'package:countdown_todo/models/plan_availability.dart';
import 'package:countdown_todo/services/database_helper.dart';
import 'package:countdown_todo/services/database_schema_history.dart';
import 'package:countdown_todo/services/plan_editor_draft_repository.dart';
import 'package:countdown_todo/services/plan_todo_guard.dart';
import 'package:countdown_todo/services/api_service.dart';
import 'package:countdown_todo/services/data_export_service.dart';
import 'package:countdown_todo/models/data_export_models.dart';
import 'package:countdown_todo/services/minor_mode_service.dart';
import 'package:countdown_todo/storage_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import '../support/plan_availability_fixture.dart';

class _LocalHttpOverrides extends HttpOverrides {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late PlanAvailabilityFixture f;
  late PlanEditorDraftRepository repo;
  const identity = PlanTodoIdentity(PlanAvailabilityFixture.username, 0);
  PlanDraftFields fields({
    String origin = 'timeline',
    String remark = '完整保留',
    String todoId = 'todo-target',
    FixedSchedulePreparationContext? preparationContext,
  }) => PlanDraftFields(
    todoId: todoId,
    title: '复习高数',
    start: PlanAvailabilityFixture.day
        .add(const Duration(hours: 9))
        .millisecondsSinceEpoch,
    end: PlanAvailabilityFixture.day
        .add(const Duration(hours: 10))
        .millisecondsSinceEpoch,
    remark: remark,
    reminder: 15,
    pomodoro: 45,
    rounds: 3,
    origin: origin,
    offsetMinutes: 480,
    preparationContext: preparationContext,
  );
  Future<PlanEditorDraft> keep({
    String id = 'reserved',
    String origin = 'timeline',
  }) => repo.keep(identity, fields(origin: origin), targetId: id);
  TodoPlanBlock block(PlanEditorDraft draft) => TodoPlanBlock(
    id: draft.targetId,
    todoId: draft.fields.todoId,
    startTime: draft.fields.start,
    endTime: draft.fields.end,
    plannedMinutes: 60,
    remark: draft.fields.remark,
    reminderMinutes: 15,
    pomodoroMinutes: 45,
    pomodoroRounds: 3,
  );
  Future<Map<String, int>> businessCounts() async => {
    for (final table in [
      'todos',
      'todo_plan_blocks',
      'op_logs',
      'local_audit_logs',
    ])
      table:
          (await f.db.rawQuery('SELECT COUNT(*) AS n FROM $table')).single['n']
              as int,
  };

  setUp(() async {
    f = PlanAvailabilityFixture();
    await f.initialize();
    repo = PlanEditorDraftRepository(
      database: f.db,
      clock: () => PlanAvailabilityFixture.now,
    );
  });
  tearDown(() async {
    ApiService.clearBaseUrlOverride();
    await MinorModeService.instance.dispose();
    await f.dispose();
  });

  test('fresh database creates local draft schema and member index', () async {
    expect(await f.db.getVersion(), DatabaseSchemaHistory.currentVersion);
    expect(
      await f.db.rawQuery("PRAGMA index_list(local_plan_editor_drafts)"),
      contains(containsPair('name', 'idx_local_plan_drafts_member')),
    );
  });
  test('actual business export excludes retained draft content', () async {
    await repo.keep(
      identity,
      fields(remark: 'LOCAL_DRAFT_PRIVATE_SENTINEL'),
      targetId: 'reserved',
    );
    final result = await DataExportService.exportData(
      username: identity.username,
      selectedTypes: ['todo_plan_blocks'],
      saveToFile: true,
      options: const ExportOptions(),
    );
    expect(result.success, isTrue, reason: result.errorMessage);
    final raw = await File(result.filePath!).readAsString();
    final json = jsonDecode(raw) as Map;
    expect(json['data'], {'todo_plan_blocks': []});
    expect(raw, isNot(contains('LOCAL_DRAFT_PRIVATE_SENTINEL')));
    expect(raw, isNot(contains(PlanEditorDraftRepository.table)));
  });
  test(
    'actual cloud request excludes local draft table and contents',
    () async {
      await repo.keep(
        identity,
        fields(remark: 'LOCAL_DRAFT_PRIVATE_SENTINEL'),
        targetId: 'reserved',
      );
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      Map? sent;
      server.listen((request) async {
        sent = jsonDecode(await utf8.decoder.bind(request).join()) as Map;
        request.response.headers.contentType = ContentType.json;
        request.response.write('{"success":true}');
        await request.response.close();
      });
      try {
        ApiService.setBaseUrlOverride('http://127.0.0.1:${server.port}');
        final blocks = await StorageService.getPlanBlocks(identity.username);
        final result = await HttpOverrides.runWithHttpOverrides(
          () => ApiService.postDeltaSync(
            userId: 0,
            lastSyncTime: 0,
            deviceId: 'synthetic-device',
            todosChanges: const [],
            countdownsChanges: const [],
            planBlocksChanges: blocks.map((b) => b.toJson()).toList(),
          ),
          _LocalHttpOverrides(),
        );
        expect(result['success'], isTrue);
        expect(sent!['todo_plan_blocks_changes'], isEmpty);
        expect(
          jsonEncode(sent),
          isNot(contains('LOCAL_DRAFT_PRIVATE_SENTINEL')),
        );
        expect(
          jsonEncode(sent),
          isNot(contains(PlanEditorDraftRepository.table)),
        );
      } finally {
        await server.close(force: true);
      }
    },
  );
  test(
    'upgrade from preceding schema keeps real todos and creates drafts',
    () async {
      await f.db.execute('DROP TABLE local_plan_editor_drafts');
      await f.db.setVersion(57);
      await DatabaseHelper.instance.closeDatabase();
      f.db = await DatabaseHelper.instance.databaseForUser(
        PlanAvailabilityFixture.username,
      );
      repo = PlanEditorDraftRepository(database: f.db);
      expect(await repo.list(identity), isEmpty);
      expect(
        await f.db.query('todos', where: 'uuid=?', whereArgs: ['todo-target']),
        hasLength(1),
      );
      expect(await f.db.getVersion(), DatabaseSchemaHistory.currentVersion);
    },
  );
  test(
    'all fields survive a repository reopen without business writes',
    () async {
      final before = await businessCounts();
      final d = await keep();
      repo = PlanEditorDraftRepository(database: f.db);
      final read = await repo.read(identity, d.id);
      expect(read.fields.fingerprint, fields().fingerprint);
      expect(read.targetId, 'reserved');
      expect(
        (await repo.prepare(identity, d.id, d.revision)).todo!.id,
        'todo-target',
      );
      await repo.delete(identity, d.id, d.revision);
      expect(await businessCounts(), before);
    },
  );
  test('固定日程准备上下文可随本机草稿恢复且不写入业务表', () async {
    final before = await businessCounts();
    final context = FixedSchedulePreparationContext(
      scheduleId: 'schedule-occurrence',
      startTime: PlanAvailabilityFixture.day
          .add(const Duration(days: 1, hours: 12))
          .millisecondsSinceEpoch,
      appOnly: true,
    );
    final draft = await repo.keep(
      identity,
      fields(preparationContext: context),
      targetId: 'prep-plan',
    );
    repo = PlanEditorDraftRepository(database: f.db);
    final restored = await repo.read(identity, draft.id);
    expect(restored.fields.preparationContext?.toJson(), context.toJson());
    expect(await businessCounts(), before);
  });
  test(
    'six concurrent inserts admit exactly five and never overwrite',
    () async {
      final outcomes = await Future.wait(
        List.generate(6, (i) async {
          try {
            return await keep(id: 'reserved-$i');
          } catch (e) {
            return e;
          }
        }),
      );
      expect(outcomes.whereType<PlanEditorDraft>(), hasLength(5));
      expect(outcomes.whereType<StateError>(), hasLength(1));
      expect(
        (await repo.list(identity)).map((d) => d.id).toSet(),
        hasLength(5),
      );
    },
  );
  test('concurrent updates allow one revision winner', () async {
    final d = await keep();
    final outcomes = await Future.wait(
      List.generate(2, (i) async {
        try {
          return await repo.keep(
            identity,
            fields(remark: '$i'),
            previous: d,
            targetId: d.targetId,
          );
        } catch (e) {
          return e;
        }
      }),
    );
    expect(outcomes.whereType<PlanEditorDraft>(), hasLength(1));
    expect(outcomes.whereType<StateError>(), hasLength(1));
    await expectLater(
      repo.validateRevision(f.db, identity, d),
      throwsStateError,
    );
  });
  test('stale revision cannot prepare or delete a newer draft', () async {
    final d = await keep();
    final newer = await repo.keep(
      identity,
      fields(remark: '新备注'),
      previous: d,
      targetId: d.targetId,
    );
    await expectLater(
      repo.prepare(identity, d.id, d.revision),
      throwsStateError,
    );
    await expectLater(
      repo.delete(identity, d.id, d.revision),
      throwsStateError,
    );
    expect((await repo.read(identity, d.id)).revision, newer.revision);
  });
  test('member cannot read update or delete another member draft', () async {
    final d = await keep();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('current_user_id', 2);
    const member = PlanTodoIdentity(PlanAvailabilityFixture.username, 2);
    expect(await repo.list(member), isEmpty);
    await expectLater(repo.read(member, d.id), throwsStateError);
    await expectLater(
      repo.keep(member, fields(), previous: d, targetId: d.targetId),
      throwsStateError,
    );
    await expectLater(repo.delete(member, d.id, d.revision), throwsStateError);
  });
  test('account switch rejects every stale draft operation', () async {
    final d = await keep();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('current_login_user', 'other');
    for (final action in [
      () => repo.list(identity),
      () => repo.read(identity, d.id),
      () => repo.keep(identity, fields(), targetId: 'new'),
      () => repo.delete(identity, d.id, d.revision),
      () => repo.target(identity, d),
    ]) {
      await expectLater(action(), throwsA(isA<Exception>()));
    }
  });
  for (final mutation in ['done', 'deleted', 'conflict']) {
    test('restore refuses $mutation todo and keeps draft untouched', () async {
      final d = await keep();
      await f.db.update(
        'todos',
        {
          switch (mutation) {
            'done' => 'is_completed',
            'deleted' => 'is_deleted',
            _ => 'has_conflict',
          }: 1,
        },
        where: 'uuid=?',
        whereArgs: ['todo-target'],
      );
      await expectLater(
        repo.prepare(identity, d.id, d.revision),
        throwsA(isA<Exception>()),
      );
      expect((await repo.read(identity, d.id)).fields.remark, '完整保留');
    });
  }
  test('missing UUID never substitutes a same-title todo', () async {
    final d = await repo.keep(
      identity,
      fields(todoId: 'missing'),
      targetId: 'reserved',
    );
    await expectLater(
      repo.prepare(identity, d.id, d.revision),
      throwsA(isA<Exception>()),
    );
  });
  test(
    'backlog rebuilds live arrangements without persisted approval',
    () async {
      final d = await keep(origin: 'backlog');
      await f.block(block(d)..id = 'another-plan');
      final prepared = await repo.prepare(identity, d.id, d.revision);
      expect(prepared.backlog!.arrangements, contains('another-plan'));
      expect(prepared.backlog!.todoId, 'todo-target');
    },
  );
  test('saved target is recognized even after todo completion', () async {
    final d = await keep();
    await f.block(block(d));
    await f.db.update('todos', {'is_completed': 1});
    final prepared = await repo.prepare(identity, d.id, d.revision);
    expect(prepared.saved!.id, d.targetId);
    expect(prepared.todo, isNull);
    expect(await f.db.query('todo_plan_blocks'), hasLength(1));
  });
  for (final mutation in ['deleted', 'time', 'todo', 'remark']) {
    test('changed saved target $mutation cannot be recreated', () async {
      final d = await keep();
      final b = block(d);
      switch (mutation) {
        case 'deleted':
          b.isDeleted = true;
        case 'time':
          b.startTime += 60000;
        case 'todo':
          b.todoId = 'other-todo';
        case 'remark':
          b.remark = '新备注';
      }
      await f.block(b);
      await expectLater(repo.target(identity, d), throwsStateError);
      expect(await f.db.query('todo_plan_blocks'), hasLength(1));
    });
  }
  for (final raw in ['{', '{"todo":12}', '{"start":null}']) {
    test('damaged JSON is explicit and independently deletable $raw', () async {
      final d = await keep();
      final good = await keep(id: 'second');
      await f.db.update(
        PlanEditorDraftRepository.table,
        {'form_json': raw},
        where: 'uuid=?',
        whereArgs: [d.id],
      );
      await expectLater(repo.read(identity, d.id), throwsStateError);
      await repo.delete(identity, d.id, d.revision);
      expect((await repo.read(identity, good.id)).targetId, 'second');
    });
  }
  test('future format is shown unsupported without clearing data', () async {
    final d = await keep();
    await f.db.update(
      PlanEditorDraftRepository.table,
      {'format_version': 99},
      where: 'uuid=?',
      whereArgs: [d.id],
    );
    expect((await repo.list(identity)).single.readable, isFalse);
    await expectLater(repo.read(identity, d.id), throwsStateError);
    expect(await f.db.query(PlanEditorDraftRepository.table), hasLength(1));
  });
  test('large remarks fail without truncation or creating draft', () async {
    await expectLater(
      repo.keep(identity, fields(remark: '字' * 100000), targetId: 'reserved'),
      throwsStateError,
    );
    expect(await repo.list(identity), isEmpty);
  });
  test(
    'summary order is stable and optional exact todo filter is scoped',
    () async {
      final a = await keep(id: 'a');
      final b = await keep(id: 'b');
      await repo.keep(identity, fields(todoId: 'other'), targetId: 'c');
      final rows = await repo.list(identity, todoId: 'todo-target');
      expect(rows.map((r) => r.id), orderedEquals([a.id, b.id]..sort()));
    },
  );
}
