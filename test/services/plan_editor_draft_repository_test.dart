@TestOn('vm')
library;

import 'package:countdown_todo/services/database_helper.dart';
import 'package:countdown_todo/services/plan_editor_draft_repository.dart';
import 'package:countdown_todo/services/plan_todo_guard.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  late Database db;
  late PlanEditorDraftRepository repository;
  late PlanTodoIdentity identity;

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'current_login_user': 'draft-test',
      'current_user_id': 7,
    });
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await DatabaseHelper.ensurePlanEditorDraftSchema(db);
    identity = const PlanTodoIdentity('draft-test', 7);
    repository = PlanEditorDraftRepository(
      database: db,
      clock: () => DateTime.utc(2026, 10, 11, 12),
    );
  });

  tearDown(() async => db.close());

  PlanDraftFields fields({String todoId = 'todo-1', String remark = '复习'}) =>
      PlanDraftFields(
        todoId: todoId,
        title: '准备考试',
        start: DateTime.utc(2026, 10, 12, 9).millisecondsSinceEpoch,
        end: DateTime.utc(2026, 10, 12, 10).millisecondsSinceEpoch,
        remark: remark,
        reminder: 5,
        pomodoro: 25,
        rounds: 0,
        origin: 'timeline',
        offsetMinutes: 480,
      );

  test('keeps and reads only the selected member draft', () async {
    final kept = await repository.keep(
      identity,
      fields(),
      targetId: 'reserved-block-1',
    );

    final summaries = await repository.list(identity);
    expect(summaries, hasLength(1));
    expect(summaries.single.readable, isTrue);
    expect(summaries.single.title, '准备考试');
    expect(
      (await repository.read(identity, kept.id)).fields.fingerprint,
      fields().fingerprint,
    );

    final preferences = await SharedPreferences.getInstance();
    await preferences.setInt('current_user_id', 8);
    await expectLater(repository.list(identity), throwsA(isA<Exception>()));
    expect(
      await repository.list(const PlanTodoIdentity('draft-test', 8)),
      isEmpty,
    );
  });

  test(
    'round-trips validated settings adjustment notes with local drafts',
    () async {
      final adjusted = PlanDraftFields(
        todoId: 'todo-1',
        title: '准备考试',
        start: DateTime.utc(2026, 10, 12, 9).millisecondsSinceEpoch,
        end: DateTime.utc(2026, 10, 12, 10).millisecondsSinceEpoch,
        remark: '复习',
        reminder: 5,
        pomodoro: 25,
        rounds: 0,
        origin: 'reuse',
        offsetMinutes: 480,
        settingsAdjustments: const ['提前提醒：7 分钟前 → 5 分钟前', '番茄轮数：7 轮 → 按规划时长'],
      );
      final kept = await repository.keep(
        identity,
        adjusted,
        targetId: 'reserved-block-1',
      );

      expect(
        (await repository.read(identity, kept.id)).fields.settingsAdjustments,
        adjusted.settingsAdjustments,
      );
      expect(
        () => PlanDraftFields.fromJson({
          ...adjusted.toJson(),
          'settingsAdjustments': ['有效', 7],
        }),
        throwsFormatException,
      );
    },
  );

  test('uses revision checks when updating and deleting a draft', () async {
    final first = await repository.keep(
      identity,
      fields(),
      targetId: 'reserved-block-1',
    );
    final updated = await repository.keep(
      identity,
      fields(remark: '修改后的备注'),
      previous: first,
      targetId: first.targetId,
    );

    expect(updated.revision, 2);
    expect(
      (await repository.read(identity, updated.id)).fields.remark,
      '修改后的备注',
    );
    await expectLater(
      repository.keep(
        identity,
        fields(remark: '旧页面写入'),
        previous: first,
        targetId: first.targetId,
      ),
      throwsStateError,
    );
    await expectLater(
      repository.delete(identity, first.id, first.revision),
      throwsStateError,
    );
    expect(await repository.list(identity), hasLength(1));

    await repository.delete(identity, updated.id, updated.revision);
    expect(await repository.list(identity), isEmpty);
  });

  test(
    'enforces the five-draft limit without replacing existing drafts',
    () async {
      for (var index = 0; index < PlanEditorDraftRepository.capacity; index++) {
        await repository.keep(
          identity,
          fields(todoId: 'todo-$index'),
          targetId: 'reserved-block-$index',
        );
      }

      await expectLater(
        repository.keep(
          identity,
          fields(todoId: 'todo-overflow'),
          targetId: 'reserved-block-overflow',
        ),
        throwsStateError,
      );
      expect(await repository.list(identity), hasLength(5));
    },
  );

  test(
    'marks malformed draft content unreadable and preserves its row',
    () async {
      final kept = await repository.keep(
        identity,
        fields(),
        targetId: 'reserved-block-1',
      );
      await db.update(
        PlanEditorDraftRepository.table,
        {'form_json': '{invalid'},
        where: 'uuid=?',
        whereArgs: [kept.id],
      );

      final summaries = await repository.list(identity);
      expect(summaries, hasLength(1));
      expect(summaries.single.readable, isFalse);
      await expectLater(repository.read(identity, kept.id), throwsStateError);
      expect(await db.query(PlanEditorDraftRepository.table), hasLength(1));
    },
  );
}
