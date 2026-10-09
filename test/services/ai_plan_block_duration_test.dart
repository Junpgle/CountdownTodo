import 'package:countdown_todo/models/ai_todo_action.dart';
import 'package:countdown_todo/services/ai_todo_action_executor.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AI plan block duration', () {
    test('planned minutes match the explicit plan block interval', () {
      final result = AiTodoActionExecutor.execute(
        actions: [
          AiTodoAction(
            type: AiTodoActionType.createPlanBlock,
            todoId: 'todo-1',
            title: '整理桌面',
            startTime: '2026-10-02T19:00:00',
            dueDate: '2026-10-02T20:00:00',
            durationMinutes: 30,
          ),
        ],
        existingTodos: const [
          {'id': 'todo-1', 'title': '整理桌面'},
        ],
      );

      final block = result.newPlanBlocks.single;
      expect(block.plannedMinutes, 60);
      expect(
        DateTime.fromMillisecondsSinceEpoch(block.endTime)
            .difference(DateTime.fromMillisecondsSinceEpoch(block.startTime))
            .inMinutes,
        block.plannedMinutes,
      );
    });

    test('duration supplies the end when no explicit end is provided', () {
      final result = AiTodoActionExecutor.execute(
        actions: [
          AiTodoAction(
            type: AiTodoActionType.createPlanBlock,
            todoId: 'todo-1',
            title: '整理桌面',
            startTime: '2026-10-02T19:00:00',
            durationMinutes: 35,
          ),
        ],
        existingTodos: const [
          {'id': 'todo-1', 'title': '整理桌面'},
        ],
      );

      final block = result.newPlanBlocks.single;
      expect(block.plannedMinutes, 35);
      expect(
        DateTime.fromMillisecondsSinceEpoch(block.endTime)
            .difference(DateTime.fromMillisecondsSinceEpoch(block.startTime))
            .inMinutes,
        35,
      );
    });
  });
}
