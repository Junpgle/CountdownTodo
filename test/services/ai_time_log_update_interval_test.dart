import 'package:countdown_todo/models.dart';
import 'package:countdown_todo/services/ai_action_parser.dart';
import 'package:countdown_todo/services/ai_todo_action_executor.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final start = DateTime(2026, 10, 2, 19);
  final existing = TimeLogItem(
    id: 'log-1',
    title: '复习高数',
    startTime: start.millisecondsSinceEpoch,
    endTime: start.add(const Duration(hours: 1)).millisecondsSinceEpoch,
  );

  test('moving only the start keeps the existing time log duration', () {
    const response = '''
[ACTION_START]
{"action":"update_time_log","updates":[{"logId":"log-1","startTime":"2026-10-02 20:00"}]}
[ACTION_END]
''';
    final actions = AiActionParser.extractTodoActions(
      response,
      originalText: '把这条专注记录的开始时间改到20点',
    );
    final result = AiTodoActionExecutor.execute(
      actions: actions,
      existingTodos: const [],
      existingTimeLogs: [existing],
    );

    expect(result.updatedTimeLogs, hasLength(1));
    expect(
      result.updatedTimeLogs.single.endTime -
          result.updatedTimeLogs.single.startTime,
      const Duration(hours: 1).inMilliseconds,
    );
    expect(
      DateTime.fromMillisecondsSinceEpoch(result.updatedTimeLogs.single.endTime),
      start.add(const Duration(hours: 2)),
    );
  });

  test('omitted start and end keep the existing time log interval', () {
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

    expect(result.updatedTimeLogs.single.startTime, existing.startTime);
    expect(result.updatedTimeLogs.single.endTime, existing.endTime);
  });
}
