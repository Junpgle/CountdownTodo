import 'package:countdown_todo/models/ai_todo_action.dart';
import 'package:countdown_todo/services/ai_action_parser.dart';
import 'package:countdown_todo/services/ai_todo_action_executor.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
