import 'package:countdown_todo/models.dart';
import 'package:countdown_todo/services/todo_editor_save_service.dart';
import 'package:countdown_todo/storage_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/plan_availability_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late PlanAvailabilityFixture fixture;

  setUp(() async {
    fixture = PlanAvailabilityFixture();
    await fixture.initialize();
  });

  tearDown(() async => fixture.dispose());

  test('显式编辑保留旧待办 ID 并提交待办与 oplog', () async {
    final baseline = (await StorageService.getTodos(
      PlanAvailabilityFixture.username,
      includeDeleted: true,
    )).single;
    expect(baseline.id, 'todo-target');

    final edited = TodoItem.fromJson(baseline.toJson())
      ..title = '更新后的标题'
      ..markAsChanged();
    await StorageService.saveTodos(
      PlanAvailabilityFixture.username,
      [edited],
      expectedTodoBaselines: {baseline.id: baseline},
    );

    final stored = (await StorageService.getTodos(
      PlanAvailabilityFixture.username,
      includeDeleted: true,
    )).single;
    expect(stored.id, baseline.id);
    expect(stored.title, '更新后的标题');
    final ops = await fixture.db.query(
      'op_logs',
      where: 'target_table = ? AND target_uuid = ?',
      whereArgs: ['todos', baseline.id],
    );
    expect(ops, hasLength(1));
  });

  test('事务检测到基线已过期时拒绝旧编辑覆盖', () async {
    final baseline = (await StorageService.getTodos(
      PlanAvailabilityFixture.username,
      includeDeleted: true,
    )).single;
    final edited = TodoItem.fromJson(baseline.toJson())
      ..title = '编辑器里的旧标题'
      ..markAsChanged();

    await fixture.db.update(
      'todos',
      {
        'content': '其他位置的新标题',
        'version': baseline.version + 1,
        'updated_at': baseline.updatedAt + 100,
      },
      where: 'uuid = ?',
      whereArgs: [baseline.id],
    );

    await expectLater(
      StorageService.saveTodos(
        PlanAvailabilityFixture.username,
        [edited],
        expectedTodoBaselines: {baseline.id: baseline},
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('重新打开后再编辑'),
        ),
      ),
    );
    final stored = (await StorageService.getTodos(
      PlanAvailabilityFixture.username,
      includeDeleted: true,
    )).single;
    expect(stored.title, '其他位置的新标题');
    expect(
      await fixture.db.query(
        'op_logs',
        where: 'target_table = ? AND target_uuid = ?',
        whereArgs: ['todos', baseline.id],
      ),
      isEmpty,
    );
  });

  test('事务发现系列新增成员时拒绝局部保存', () async {
    const username = PlanAvailabilityFixture.username;
    final anchor = TodoItem(
      id: 'guarded-series',
      title: '每周复盘',
      recurrence: RecurrenceType.weekly,
      recurrenceSeriesId: 'guarded-series',
      createdDate: DateTime(2026, 10, 19).millisecondsSinceEpoch,
    );
    final existing = TodoItem(
      id: 'guarded-series-old',
      title: '每周复盘',
      recurrenceSeriesId: 'guarded-series',
      createdDate: DateTime(2026, 10, 12).millisecondsSinceEpoch,
    );
    await StorageService.saveTodos(username, [anchor, existing]);
    final baselines = {
      for (final todo in [anchor, existing]) todo.id: todo,
    };
    final edited = TodoItem.fromJson(anchor.toJson())
      ..title = '复盘周报'
      ..markAsChanged();
    final newlyMaterialized = TodoItem(
      id: 'guarded-series-new',
      title: '每周复盘',
      recurrenceSeriesId: 'guarded-series',
      createdDate: DateTime(2026, 10, 26).millisecondsSinceEpoch,
    );
    await StorageService.saveTodos(username, [newlyMaterialized]);

    await expectLater(
      StorageService.saveTodos(
        username,
        [edited],
        expectedTodoBaselines: baselines,
        expectedSeriesMembership: {
          'guarded-series': {'guarded-series', 'guarded-series-old'},
        },
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('循环系列已有变化'),
        ),
      ),
    );
    final storedAnchor = await StorageService.getTodoByUuid(
      username,
      anchor.id,
    );
    expect(storedAnchor?.title, '每周复盘');
  });

  test('oplog 写入失败时回滚待办，读回不会误判成已保存', () async {
    const username = PlanAvailabilityFixture.username;
    final baseline = (await StorageService.getTodos(
      username,
      includeDeleted: true,
    )).single;
    final edited = TodoItem.fromJson(baseline.toJson())
      ..title = '不能落库的标题'
      ..markAsChanged();
    await fixture.db.execute('''
      CREATE TRIGGER fail_todo_editor_oplog
      BEFORE INSERT ON op_logs
      WHEN NEW.target_table = 'todos' AND NEW.target_uuid = '${baseline.id}'
      BEGIN
        SELECT RAISE(ABORT, 'synthetic oplog failure');
      END
    ''');

    await expectLater(
      TodoEditorSaveService.save(
        username: username,
        changedTodos: [edited],
        baselines: {baseline.id: baseline},
      ),
      throwsA(isA<Exception>()),
    );

    final stored = (await StorageService.getTodos(
      username,
      includeDeleted: true,
    )).single;
    expect(stored.title, baseline.title);
    expect(await TodoEditorSaveService.isCommitted(username, [edited]), false);
    expect(
      await fixture.db.query(
        'op_logs',
        where: 'target_table = ? AND target_uuid = ?',
        whereArgs: ['todos', baseline.id],
      ),
      isEmpty,
    );
  });

  test('并发删除或冲突更新会阻止旧编辑覆盖', () async {
    const username = PlanAvailabilityFixture.username;
    final cases = [
      (
        id: 'deleted-editor-target',
        title: '已删除的待办',
        change: <String, Object?>{
          'is_deleted': 1,
          'version': 2,
          'updated_at': 300,
        },
      ),
      (
        id: 'conflicted-editor-target',
        title: '发生冲突的待办',
        change: <String, Object?>{
          'has_conflict': 1,
          'conflict_data': '{"title":"remote"}',
          'version': 2,
          'updated_at': 300,
        },
      ),
      (
        id: 'team-changed-editor-target',
        title: '团队归属已经更新',
        change: <String, Object?>{
          'team_uuid': 'team-updated-elsewhere',
          'collab_type': 1,
          'version': 2,
          'updated_at': 300,
        },
      ),
    ];

    for (final item in cases) {
      await fixture.todo(item.id, item.title);
      final baseline = (await StorageService.getTodos(
        username,
        includeDeleted: true,
      )).singleWhere((todo) => todo.id == item.id);
      final staleEdit = TodoItem.fromJson(baseline.toJson())
        ..title = '编辑器里的旧内容'
        ..markAsChanged();
      await fixture.db.update(
        'todos',
        item.change,
        where: 'uuid = ?',
        whereArgs: [item.id],
      );

      await expectLater(
        StorageService.saveTodos(
          username,
          [staleEdit],
          expectedTodoBaselines: {item.id: baseline},
        ),
        throwsA(isA<StateError>()),
      );
      final current = (await fixture.db.query(
        'todos',
        where: 'uuid = ?',
        whereArgs: [item.id],
      )).single;
      expect(current['content'], item.title);
      expect(current['is_deleted'], item.change['is_deleted'] ?? 0);
      expect(current['has_conflict'], item.change['has_conflict'] ?? 0);
      expect(current['team_uuid'], item.change['team_uuid']);
      expect(current['collab_type'], item.change['collab_type'] ?? 0);
    }
  });

  test('账户切换后旧账户编辑不会提交到原账户库', () async {
    const username = PlanAvailabilityFixture.username;
    final baseline = (await StorageService.getTodos(
      username,
      includeDeleted: true,
    )).single;
    final edited = TodoItem.fromJson(baseline.toJson())
      ..title = '旧账户迟到的修改'
      ..markAsChanged();
    await (await SharedPreferences.getInstance()).setString(
      'current_login_user',
      'switched-account',
    );

    await expectLater(
      TodoEditorSaveService.save(
        username: username,
        changedTodos: [edited],
        baselines: {baseline.id: baseline},
      ),
      throwsA(isA<StateError>()),
    );
    final raw = (await fixture.db.query(
      'todos',
      where: 'uuid = ?',
      whereArgs: [baseline.id],
    )).single;
    expect(raw['content'], baseline.title);
    expect(
      await fixture.db.query(
        'op_logs',
        where: 'target_table = ? AND target_uuid = ?',
        whereArgs: ['todos', baseline.id],
      ),
      isEmpty,
    );
  });

  test('文件夹同步只在事务基线未变化时提交', () async {
    const username = PlanAvailabilityFixture.username;
    final group = TodoGroup(
      id: 'editor-group',
      name: '工作',
      updatedAt: PlanAvailabilityFixture.now.millisecondsSinceEpoch,
      createdAt: PlanAvailabilityFixture.now.millisecondsSinceEpoch,
    );
    await StorageService.saveTodoGroups(username, [group]);
    final baseline = (await StorageService.getTodoGroups(
      username,
      includeDeleted: true,
    )).single;
    final changed = TodoGroup.fromJson(baseline.toJson())
      ..teamUuid = 'team-new'
      ..teamName = '新团队'
      ..markAsChanged();

    await StorageService.saveTodoGroups(
      username,
      [changed],
      expectedGroupBaselines: {baseline.id: baseline},
    );
    final stored = (await StorageService.getTodoGroups(
      username,
      includeDeleted: true,
    )).single;
    expect(stored.teamUuid, 'team-new');
    expect(stored.teamName, '新团队');

    final nextBaseline = TodoGroup.fromJson(stored.toJson());
    final stale = TodoGroup.fromJson(stored.toJson())
      ..teamUuid = 'stale-team'
      ..markAsChanged();
    await fixture.db.update(
      'todo_groups',
      {
        'team_uuid': 'remote-team',
        'version': nextBaseline.version + 1,
        'updated_at': nextBaseline.updatedAt + 100,
      },
      where: 'uuid = ?',
      whereArgs: [nextBaseline.id],
    );

    await expectLater(
      StorageService.saveTodoGroups(
        username,
        [stale],
        expectedGroupBaselines: {nextBaseline.id: nextBaseline},
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('请重新打开后再修改'),
        ),
      ),
    );
    final finalValue = (await StorageService.getTodoGroups(
      username,
      includeDeleted: true,
    )).single;
    expect(finalValue.teamUuid, 'remote-team');
  });
}
