import 'package:countdown_todo/services/ai_action_parser.dart';
import 'package:countdown_todo/services/ai_todo_action_executor.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const response = '''
[ACTION_START]
{"action":"update_todo","updates":[{"todoId":"todo-1","dueDate":null}]}
[ACTION_END]
''';

  for (final mode in ['deadline', 'dateOnly']) {
    test('explicit dueDate null clears an existing $mode todo', () {
      final scheduledDate = DateTime(2026, 10, 2, mode == 'deadline' ? 19 : 0);
      final existingDue = mode == 'dateOnly'
          ? DateTime(2026, 10, 2, 23, 59)
          : DateTime(2026, 10, 3, 19);
      final actions = AiActionParser.extractTodoActions(
        response,
        originalText: '清除这个待办的日期',
      );
      final result = AiTodoActionExecutor.execute(
        actions: actions,
        existingTodos: [
          {
            'id': 'todo-1',
            'title': '提交报告',
            'timeMode': mode,
            'isAllDay': mode == 'dateOnly',
            'createdDate': scheduledDate.millisecondsSinceEpoch,
            'dueDate': existingDue,
          },
        ],
      );

      expect(result.updatedTodos, hasLength(1));
      expect(result.updatedTodos.single.createdDate, isNull);
      expect(result.updatedTodos.single.dueDate, isNull);
    });
  }

  test('omitting dueDate leaves an existing scheduled todo unchanged', () {
    const updateResponse = '''
[ACTION_START]
{"action":"update_todo","updates":[{"todoId":"todo-1","title":"改好报告名称"}]}
[ACTION_END]
''';
    final dueDate = DateTime(2026, 10, 3, 19);
    final actions = AiActionParser.extractTodoActions(
      updateResponse,
      originalText: '修改待办标题',
    );
    final result = AiTodoActionExecutor.execute(
      actions: actions,
      existingTodos: [
        {
          'id': 'todo-1',
          'title': '提交报告',
          'timeMode': 'deadline',
          'createdDate': dueDate.millisecondsSinceEpoch,
          'dueDate': dueDate,
        },
      ],
    );

    expect(result.updatedTodos.single.dueDate, dueDate);
    expect(
      result.updatedTodos.single.createdDate,
      dueDate.millisecondsSinceEpoch,
    );
  });
}
