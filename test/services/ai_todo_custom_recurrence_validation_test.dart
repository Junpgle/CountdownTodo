import 'package:countdown_todo/models/ai_todo_action.dart';
import 'package:countdown_todo/services/ai_todo_action_executor.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AI custom recurrence validation', () {
    test('rejects switching to customDays without a positive interval', () {
      final action = AiTodoAction(
        type: AiTodoActionType.updateTodo,
        todoId: 'todo-1',
        recurrence: 'customDays',
      );
      final result = AiTodoActionExecutor.execute(
        actions: [action],
        existingTodos: const [
          {
            'id': 'todo-1',
            'title': '喝水',
            'recurrence': 'weekly',
            'recurrenceSeriesId': 'series-1',
          },
        ],
      );

      expect(result.updatedTodos, isEmpty);
      expect(action.isAdded, isFalse);
    });

    test(
      'rejects clearing an interval while keeping customDays recurrence',
      () {
        final action = AiTodoAction(
          type: AiTodoActionType.updateTodo,
          todoId: 'todo-1',
          hasCustomIntervalDays: true,
        );
        final result = AiTodoActionExecutor.execute(
          actions: [action],
          existingTodos: const [
            {
              'id': 'todo-1',
              'title': '喝水',
              'recurrence': 'customDays',
              'recurrenceSeriesId': 'series-1',
              'customIntervalDays': 5,
            },
          ],
        );

        expect(result.updatedTodos, isEmpty);
        expect(action.isAdded, isFalse);
      },
    );

    test('accepts a custom recurrence update with a positive interval', () {
      final result = AiTodoActionExecutor.execute(
        actions: [
          AiTodoAction(
            type: AiTodoActionType.updateTodo,
            todoId: 'todo-1',
            recurrence: 'customDays',
            customIntervalDays: 5,
          ),
        ],
        existingTodos: const [
          {
            'id': 'todo-1',
            'title': '喝水',
            'recurrence': 'weekly',
            'recurrenceSeriesId': 'series-1',
          },
        ],
      );

      expect(result.updatedTodos, hasLength(1));
      expect(result.updatedTodos.single.recurrence.name, 'customDays');
      expect(result.updatedTodos.single.customIntervalDays, 5);
    });
  });
}
