import 'package:countdown_todo/models.dart';
import 'package:countdown_todo/services/ai_action_parser.dart';
import 'package:countdown_todo/services/ai_todo_action_executor.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final start = DateTime(2026, 10, 2, 19);
  final existing = TodoPlanBlock(
    id: 'block-1',
    todoId: 'todo-1',
    startTime: start.millisecondsSinceEpoch,
    endTime: start.add(const Duration(hours: 1)).millisecondsSinceEpoch,
    plannedMinutes: 60,
    remark: '旧备注',
  );

  test('explicit null remark clears an existing plan block remark', () {
    const response = '''
[ACTION_START]
{"action":"update_plan_block","updates":[{"planBlockId":"block-1","remark":null}]}
[ACTION_END]
''';
    final actions = AiActionParser.extractTodoActions(
      response,
      originalText: '清除规划块备注',
    );
    final result = AiTodoActionExecutor.execute(
      actions: actions,
      existingTodos: const [],
      existingPlanBlocks: [existing],
    );

    expect(result.updatedPlanBlocks.single.remark, isNull);
  });

  test('omitted remark keeps an existing plan block remark', () {
    const response = '''
[ACTION_START]
{"action":"update_plan_block","updates":[{"planBlockId":"block-1","title":"新标题"}]}
[ACTION_END]
''';
    final actions = AiActionParser.extractTodoActions(
      response,
      originalText: '修改规划块标题',
    );
    final result = AiTodoActionExecutor.execute(
      actions: actions,
      existingTodos: const [],
      existingPlanBlocks: [existing],
    );

    expect(result.updatedPlanBlocks.single.remark, '旧备注');
  });
}
