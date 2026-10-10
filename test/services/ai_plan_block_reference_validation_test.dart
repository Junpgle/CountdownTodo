import 'package:countdown_todo/models/ai_todo_action.dart';
import 'package:countdown_todo/services/ai_action_parser.dart';
import 'package:countdown_todo/services/ai_todo_action_executor.dart';
import 'package:countdown_todo/services/ai_plan_draft_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/plan_availability_fixture.dart';

List<AiTodoAction> _newPlans({String title = '行测', String end = '17:45'}) =>
    AiActionParser.extractTodoActions('''
[ACTION_START]{"action":"create_plan_block","blocks":[{"newTodoTitle":"$title","startTime":"2026-10-10 16:20","dueDate":"2026-10-10 $end"}]}[ACTION_END]
''', originalText: '生成规划块');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('新事项规划确认', () {
    test('模型返回已执行或忽略标记不能隐藏新草案，存储恢复保留真实状态', () {
      final actions = AiActionParser.extractTodoActions('''
[ACTION_START]{"action":"create_plan_block","blocks":[
{"newTodoTitle":"行测","isAdded":true,"isIgnored":true,"isSelected":false},
{"newTodoTitle":"申论","isAdded":true},
{"newTodoTitle":"习概","isIgnored":true}
]}[ACTION_END]
''', originalText: '生成规划块');
      expect(actions, hasLength(3));
      for (final action in actions) {
        expect(action.isAdded, false);
        expect(action.isIgnored, false);
        expect(action.isSelected, true);
      }
      actions.first.isAdded = true;
      actions.last.isIgnored = true;
      expect(AiTodoAction.fromJson(actions.first.toJson()).isAdded, true);
      expect(AiTodoAction.fromJson(actions.last.toJson()).isIgnored, true);
    });

    test('生成卡片不创建待办；取消选择不创建任何对象', () {
      final actions = _newPlans();
      expect(actions.single.todoId, isNull);
      expect(actions.single.newTodoTitle, '行测');
      expect(actions.single.isAdded, false);
      final restored = AiTodoAction.fromJson(actions.single.toJson());
      expect(restored.newTodoTitle, '行测');
      restored.isSelected = false;
      final result = AiTodoActionExecutor.execute(
        actions: [restored],
        existingTodos: const [],
      );
      expect(result.hasChanges, false);
    });

    test('选中确认后生成本地UUID并把新规划挂载到待办', () {
      final actions = _newPlans();
      final result = AiTodoActionExecutor.execute(
        actions: actions,
        existingTodos: const [],
      );
      expect(result.newTodos, hasLength(1));
      expect(result.newPlanBlocks, hasLength(1));
      expect(result.newTodos.single.title, '行测');
      expect(result.newTodos.single.dueDate, isNull);
      expect(result.newPlanBlocks.single.todoId, result.newTodos.single.id);
      expect(actions.single.todoId, result.newTodos.single.id);
      final again = AiTodoActionExecutor.execute(
        actions: actions,
        existingTodos: const [],
      );
      expect(again.hasChanges, false);
    });

    test('重复时间块复用本批待办，确认时已有同名待办也复用', () {
      final result = AiTodoActionExecutor.execute(
        actions: [..._newPlans(), ..._newPlans()],
        existingTodos: const [],
      );
      expect(result.newTodos, hasLength(1));
      expect(result.newPlanBlocks, hasLength(2));
      expect(
        result.newPlanBlocks.map((block) => block.todoId).toSet(),
        hasLength(1),
      );
      final existing = AiTodoActionExecutor.execute(
        actions: _newPlans(),
        existingTodos: const [
          {'id': 'existing-xingce', 'title': '行测'},
        ],
      );
      expect(existing.newTodos, isEmpty);
      expect(existing.newPlanBlocks.single.todoId, 'existing-xingce');
    });

    test('无效时段或同名歧义不会遗留新待办', () {
      final invalid = AiTodoActionExecutor.execute(
        actions: _newPlans(end: '16:00'),
        existingTodos: const [],
      );
      expect(invalid.hasChanges, false);
      final ambiguous = AiTodoActionExecutor.execute(
        actions: _newPlans(),
        existingTodos: const [
          {'id': 'one', 'title': '行测'},
          {'id': 'two', 'title': '行测'},
        ],
      );
      expect(ambiguous.hasChanges, false);
    });
  });

  group('新待办与规划原子保存', () {
    late PlanAvailabilityFixture fixture;
    setUp(() async {
      fixture = PlanAvailabilityFixture();
      await fixture.initialize();
    });
    tearDown(() async => fixture.dispose());

    test('确认写入待办、规划及两类同步日志，重试不重复', () async {
      final result = AiTodoActionExecutor.execute(
        actions: _newPlans(),
        existingTodos: const [],
      );
      Future<void> save() => AiPlanDraftRepository.save(
        username: PlanAvailabilityFixture.username,
        newTodos: result.newTodos,
        blocks: result.newPlanBlocks,
        sync: false,
      );
      await save();
      await save();
      final rows = await fixture.db.query(
        'todos',
        where: 'content = ?',
        whereArgs: ['行测'],
      );
      expect(rows, hasLength(1));
      final blocks = await fixture.db.query('todo_plan_blocks');
      expect(blocks, hasLength(1));
      expect(blocks.single['todo_uuid'], rows.single['uuid']);
      expect(await fixture.db.query('op_logs'), hasLength(2));
      expect(await fixture.db.query('local_audit_logs'), hasLength(1));
    });

    test('规划写入失败时待办和所有同步日志一起回滚', () async {
      await fixture.db.execute(
        "CREATE TRIGGER fail_ai_plan BEFORE INSERT ON todo_plan_blocks BEGIN SELECT RAISE(ABORT, 'fixture failure'); END",
      );
      final result = AiTodoActionExecutor.execute(
        actions: _newPlans(),
        existingTodos: const [],
      );
      await expectLater(
        AiPlanDraftRepository.save(
          username: PlanAvailabilityFixture.username,
          newTodos: result.newTodos,
          blocks: result.newPlanBlocks,
          sync: false,
        ),
        throwsA(isA<Exception>()),
      );
      expect(
        await fixture.db.query(
          'todos',
          where: 'content = ?',
          whereArgs: ['行测'],
        ),
        isEmpty,
      );
      expect(await fixture.db.query('todo_plan_blocks'), isEmpty);
      expect(await fixture.db.query('op_logs'), isEmpty);
      expect(await fixture.db.query('local_audit_logs'), isEmpty);
    });

    test('生成后出现同名待办时阻止重复创建', () async {
      final result = AiTodoActionExecutor.execute(
        actions: _newPlans(),
        existingTodos: const [],
      );
      await fixture.todo('new-existing-xingce', '行测');
      await expectLater(
        AiPlanDraftRepository.save(
          username: PlanAvailabilityFixture.username,
          newTodos: result.newTodos,
          blocks: result.newPlanBlocks,
          sync: false,
        ),
        throwsStateError,
      );
      expect(
        await fixture.db.query(
          'todos',
          where: 'content = ?',
          whereArgs: ['行测'],
        ),
        hasLength(1),
      );
      expect(await fixture.db.query('todo_plan_blocks'), isEmpty);
    });
  });

  group('AI plan block todo references', () {
    const response = '''
[ACTION_START]
{"action":"create_plan_block","blocks":[{"todoId":"todo-1","title":"整理桌面","startTime":"2026-10-02T19:00:00","dueDate":"2026-10-02T19:30:00"}]}
[ACTION_END]
''';

    test('parser rejects a plan block for an unknown todo ID', () {
      final actions = AiActionParser.extractTodoActions(
        response.replaceAll('todo-1', 'missing-todo'),
        originalText: '安排整理桌面',
        existingTodoTitles: const {},
      );

      expect(actions, isEmpty);
    });

    test('executor rejects a plan block whose todo is absent locally', () {
      final action = AiTodoAction(
        type: AiTodoActionType.createPlanBlock,
        todoId: 'missing-todo',
        title: '整理桌面',
        startTime: '2026-10-02T19:00:00',
        dueDate: '2026-10-02T19:30:00',
      );

      final result = AiTodoActionExecutor.execute(
        actions: [action],
        existingTodos: const [],
      );

      expect(result.newPlanBlocks, isEmpty);
      expect(action.isAdded, isFalse);
    });

    test('accepts a plan block linked to an existing todo', () {
      final actions = AiActionParser.extractTodoActions(
        response,
        originalText: '安排整理桌面',
        existingTodoTitles: const {'todo-1': '整理桌面'},
      );
      final result = AiTodoActionExecutor.execute(
        actions: actions,
        existingTodos: const [
          {'id': 'todo-1', 'title': '整理桌面'},
        ],
      );

      expect(actions, hasLength(1));
      expect(result.newPlanBlocks, hasLength(1));
      expect(result.newPlanBlocks.single.todoId, 'todo-1');
    });
  });
}
