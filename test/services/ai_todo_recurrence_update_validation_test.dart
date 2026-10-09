import 'package:countdown_todo/models/ai_todo_action.dart';
import 'package:countdown_todo/services/ai_todo_action_executor.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AI recurrence update validation', () {
    test('rejects enabling recurrence without a date anchor', () {
      final action = AiTodoAction(
        type: AiTodoActionType.updateTodo,
        todoId: 'todo-1',
        recurrence: 'weekly',
      );
      final result = AiTodoActionExecutor.execute(
        actions: [action],
        existingTodos: const [
          {'id': 'todo-1', 'title': '喝水', 'recurrence': 'none'},
        ],
      );

      expect(result.updatedTodos, isEmpty);
      expect(action.isAdded, isFalse);
    });

    test('rejects recurrence end date before the first occurrence', () {
      final anchor = DateTime(2026, 10, 2, 19);
      final action = AiTodoAction(
        type: AiTodoActionType.updateTodo,
        todoId: 'todo-1',
        recurrenceEndDate: '2026-10-01',
      );
      final result = AiTodoActionExecutor.execute(
        actions: [action],
        existingTodos: [
          {
            'id': 'todo-1',
            'title': '喝水',
            'recurrence': 'weekly',
            'recurrenceSeriesId': 'series-1',
            'timeMode': 'deadline',
            'createdDate': anchor.millisecondsSinceEpoch,
            'dueDate': anchor,
          },
        ],
      );

      expect(result.updatedTodos, isEmpty);
      expect(action.isAdded, isFalse);
    });

    test('accepts a recurrence end date on or after the anchor', () {
      final anchor = DateTime(2026, 10, 2, 19);
      final action = AiTodoAction(
        type: AiTodoActionType.updateTodo,
        todoId: 'todo-1',
        recurrenceEndDate: '2026-10-10',
      );
      final result = AiTodoActionExecutor.execute(
        actions: [action],
        existingTodos: [
          {
            'id': 'todo-1',
            'title': '喝水',
            'recurrence': 'weekly',
            'recurrenceSeriesId': 'series-1',
            'timeMode': 'deadline',
            'createdDate': anchor.millisecondsSinceEpoch,
            'dueDate': anchor,
          },
        ],
      );

      expect(result.updatedTodos, hasLength(1));
      expect(result.updatedTodos.single.recurrenceEndDate, isNotNull);
    });
  });
}
