import 'package:countdown_todo/models.dart';
import 'package:countdown_todo/models/ai_todo_action.dart';
import 'package:countdown_todo/services/ai_todo_action_executor.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('moving only the start preserves duration and valid interval', () {
    final originalStart = DateTime(2026, 10, 2, 19);
    final originalEnd = DateTime(2026, 10, 2, 20);
    final result = AiTodoActionExecutor.execute(
      actions: [
        AiTodoAction(
          type: AiTodoActionType.updatePlanBlock,
          planBlockId: 'block-1',
          startTime: '2026-10-02T21:00:00',
        ),
      ],
      existingTodos: const [],
      existingPlanBlocks: [
        TodoPlanBlock(
          id: 'block-1',
          todoId: 'todo-1',
          startTime: originalStart.millisecondsSinceEpoch,
          endTime: originalEnd.millisecondsSinceEpoch,
          plannedMinutes: 60,
        ),
      ],
    );

    final updated = result.updatedPlanBlocks.single;
    final start = DateTime.fromMillisecondsSinceEpoch(updated.startTime);
    final end = DateTime.fromMillisecondsSinceEpoch(updated.endTime);
    expect(end.isAfter(start), isTrue);
    expect(end.difference(start).inMinutes, 60);
    expect(updated.plannedMinutes, 60);
  });
}
