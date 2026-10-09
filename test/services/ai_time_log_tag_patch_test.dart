import 'package:countdown_todo/models.dart';
import 'package:countdown_todo/models/ai_todo_action.dart';
import 'package:countdown_todo/services/ai_action_parser.dart';
import 'package:countdown_todo/services/ai_todo_action_executor.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final start = DateTime(2026, 10, 2, 19);
  final existing = TimeLogItem(
    id: 'log-1',
    title: '复习高数',
    tagUuids: const ['tag-1', 'tag-2'],
    startTime: start.millisecondsSinceEpoch,
    endTime: start.add(const Duration(hours: 1)).millisecondsSinceEpoch,
  );

  test('explicit empty tag list clears existing time log tags', () {
    const response = '''
[ACTION_START]
{"action":"update_time_log","updates":[{"logId":"log-1","tagUuids":[]}]}
[ACTION_END]
''';
    final actions = AiActionParser.extractTodoActions(
      response,
      originalText: '清除这条专注记录的标签',
    );
    final restoredAction = AiTodoAction.fromJson(actions.single.toJson());
    final result = AiTodoActionExecutor.execute(
      actions: [restoredAction],
      existingTodos: const [],
      existingTimeLogs: [existing],
    );

    expect(result.updatedTimeLogs.single.tagUuids, isEmpty);
  });

  test('omitted tag list keeps existing time log tags', () {
    const response = '''
[ACTION_START]
{"action":"update_time_log","updates":[{"logId":"log-1","title":"新标题"}]}
[ACTION_END]
''';
    final actions = AiActionParser.extractTodoActions(
      response,
      originalText: '修改专注记录标题',
    );
    final result = AiTodoActionExecutor.execute(
      actions: actions,
      existingTodos: const [],
      existingTimeLogs: [existing],
    );

    expect(result.updatedTimeLogs.single.tagUuids, ['tag-1', 'tag-2']);
  });
}
