import 'package:countdown_todo/models.dart';
import 'package:countdown_todo/services/ai_action_parser.dart';
import 'package:countdown_todo/services/ai_todo_action_executor.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final start = DateTime(2026, 10, 2, 10);
  final existing = FixedScheduleItem(
    id: 'schedule-1',
    title: '导师例会',
    date: '2026-10-02',
    startTime: start.millisecondsSinceEpoch,
    endTime: start.add(const Duration(hours: 1)).millisecondsSinceEpoch,
  );

  test('moving only the start keeps the existing fixed schedule duration', () {
    const response = '''
[ACTION_START]
{"action":"update_schedule","updates":[{"scheduleId":"schedule-1","startTime":"2026-10-02 12:00"}]}
[ACTION_END]
''';
    final actions = AiActionParser.extractTodoActions(
      response,
      originalText: '把导师例会开始时间改到12点',
    );
    final result = AiTodoActionExecutor.execute(
      actions: actions,
      existingTodos: const [],
      existingFixedSchedules: [existing],
    );

    expect(result.updatedFixedSchedules, hasLength(1));
    expect(
      result.updatedFixedSchedules.single.endTime! -
          result.updatedFixedSchedules.single.startTime!,
      const Duration(hours: 1).inMilliseconds,
    );
    expect(
      DateTime.fromMillisecondsSinceEpoch(
        result.updatedFixedSchedules.single.endTime!,
      ),
      start.add(const Duration(hours: 3)),
    );
  });

  test('omitted start and end keep the existing fixed schedule interval', () {
    const response = '''
[ACTION_START]
{"action":"update_schedule","updates":[{"scheduleId":"schedule-1","title":"新例会标题"}]}
[ACTION_END]
''';
    final actions = AiActionParser.extractTodoActions(
      response,
      originalText: '修改例会标题',
    );
    final result = AiTodoActionExecutor.execute(
      actions: actions,
      existingTodos: const [],
      existingFixedSchedules: [existing],
    );

    expect(result.updatedFixedSchedules.single.startTime, existing.startTime);
    expect(result.updatedFixedSchedules.single.endTime, existing.endTime);
  });
}
