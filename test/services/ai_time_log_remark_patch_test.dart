import 'package:countdown_todo/models.dart';
import 'package:countdown_todo/models/ai_todo_action.dart';
import 'package:countdown_todo/services/ai_todo_action_executor.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final start = DateTime(2026, 10, 2, 19);
  final end = DateTime(2026, 10, 2, 20);
  final existing = TimeLogItem(
    id: 'log-1',
    title: '复习高数',
    startTime: start.millisecondsSinceEpoch,
    endTime: end.millisecondsSinceEpoch,
    remark: '旧备注',
  );

  test('explicit null remark clears an existing time log remark', () {
    final result = AiTodoActionExecutor.execute(
      actions: [
        AiTodoAction(
          type: AiTodoActionType.updateTimeLog,
          todoId: 'log-1',
          hasRemark: true,
        ),
      ],
      existingTodos: const [],
      existingTimeLogs: [existing],
    );

    expect(result.updatedTimeLogs, hasLength(1));
    expect(result.updatedTimeLogs.single.remark, isNull);
  });

  test('omitted remark leaves an existing time log remark unchanged', () {
    final result = AiTodoActionExecutor.execute(
      actions: [
        AiTodoAction(type: AiTodoActionType.updateTimeLog, todoId: 'log-1'),
      ],
      existingTodos: const [],
      existingTimeLogs: [existing],
    );

    expect(result.updatedTimeLogs.single.remark, '旧备注');
  });
}
