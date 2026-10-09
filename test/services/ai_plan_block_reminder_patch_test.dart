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
    reminderMinutes: 15,
  );

  test('explicit null reminder disables an existing plan block reminder', () {
    const response = '''
[ACTION_START]
{"action":"update_plan_block","updates":[{"planBlockId":"block-1","reminderMinutes":null}]}
[ACTION_END]
''';
    final actions = AiActionParser.extractTodoActions(
      response,
      originalText: '取消这个计划块的提醒',
    );
    final result = AiTodoActionExecutor.execute(
      actions: actions,
      existingTodos: const [],
      existingPlanBlocks: [existing],
    );

    expect(result.updatedPlanBlocks.single.reminderMinutes, 0);
  });

  test('omitted reminder keeps an existing plan block reminder', () {
    const response = '''
[ACTION_START]
{"action":"update_plan_block","updates":[{"planBlockId":"block-1","title":"新标题"}]}
[ACTION_END]
''';
    final actions = AiActionParser.extractTodoActions(
      response,
      originalText: '修改计划块标题',
    );
    final result = AiTodoActionExecutor.execute(
      actions: actions,
      existingTodos: const [],
      existingPlanBlocks: [existing],
    );

    expect(result.updatedPlanBlocks.single.reminderMinutes, 15);
  });
}
