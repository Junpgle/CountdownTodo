import 'package:flutter_test/flutter_test.dart';
import 'package:countdown_todo/models.dart';
import 'package:countdown_todo/models/ai_todo_action.dart';
import 'package:countdown_todo/services/ai_action_parser.dart';
import 'package:countdown_todo/services/ai_todo_action_executor.dart';
import 'package:countdown_todo/services/ai_todo_chat_launcher.dart';

void main() {
  TodoItem occurrence({
    required String id,
    required DateTime start,
    RecurrenceType recurrence = RecurrenceType.none,
    bool isDone = false,
    bool isSkipped = false,
  }) => TodoItem(
    id: id,
    title: '每周整理资料',
    recurrence: recurrence,
    recurrenceSeriesId: 'series-cleanup',
    createdDate: start.millisecondsSinceEpoch,
    dueDate: start.add(const Duration(hours: 8)),
    isDone: isDone,
    isSkipped: isSkipped,
  );

  test(
    'AI skip proposal binds one real UUID and changes only that occurrence',
    () {
      final current = occurrence(
        id: 'cleanup-current',
        start: DateTime(2026, 10, 20, 9),
        recurrence: RecurrenceType.weekly,
      );
      final future = occurrence(
        id: 'cleanup-future',
        start: DateTime(2026, 10, 27, 9),
      );
      final parsed = AiActionParser.extractTodoActions(
        '[ACTION_START]{"action":"skip_todo","updates":[{"todoId":"cleanup-current"}]}[ACTION_END]',
        originalText: '请跳过这期',
        existingTodoTitles: {
          current.id: current.title,
          future.id: future.title,
        },
      );

      expect(parsed, hasLength(1));
      expect(parsed.single.type, AiTodoActionType.skipTodo);
      expect(parsed.single.todoId, current.id);
      expect(parsed.single.appliesToFutureOccurrences, isFalse);

      final result = AiTodoActionExecutor.execute(
        actions: parsed,
        existingTodos: AiTodoChatLauncher.toChatTodoMaps([current, future]),
      );
      expect(result.updatedTodos, hasLength(1));
      expect(result.updatedTodos.single.id, current.id);
      expect(result.updatedTodos.single.isSkipped, isTrue);
      expect(result.updatedTodos.single.isDone, isFalse);
      expect(result.updatedTodos.single.isSkippedSyncPending, isTrue);
    },
  );

  test('AI skip proposal rejects ambiguous, future-scope, and non-recurring targets', () {
    List<AiTodoAction> parse(
      String update,
    ) => AiActionParser.extractTodoActions(
      '[ACTION_START]{"action":"skip_todo","updates":[$update]}[ACTION_END]',
      originalText: '跳过本期',
      existingTodoTitles: const {'cleanup-current': '每周整理资料'},
    );

    expect(parse('{"title":"每周整理资料"}'), isEmpty);
    expect(
      parse('{"todoId":"cleanup-current","recurrenceScope":"future"}'),
      isEmpty,
    );

    final start = DateTime(2026, 10, 20, 9);
    final invalidTargets = [
      occurrence(id: 'cleanup-current', start: start)
        ..recurrenceSeriesId = null,
      occurrence(
        id: 'cleanup-current',
        start: start,
        recurrence: RecurrenceType.weekly,
        isDone: true,
      ),
      occurrence(
        id: 'cleanup-current',
        start: start,
        recurrence: RecurrenceType.weekly,
        isSkipped: true,
      ),
    ];
    for (final target in invalidTargets) {
      final action = AiTodoAction(
        type: AiTodoActionType.skipTodo,
        todoId: target.id,
      );
      final result = AiTodoActionExecutor.execute(
        actions: [action],
        existingTodos: AiTodoChatLauncher.toChatTodoMaps([target]),
      );
      expect(result.updatedTodos, isEmpty);
    }
  });

  test('completing a skipped occurrence clears skip state', () {
    final skipped = occurrence(
      id: 'cleanup-current',
      start: DateTime(2026, 10, 20, 9),
      recurrence: RecurrenceType.weekly,
      isSkipped: true,
    );
    final result = AiTodoActionExecutor.execute(
      actions: [
        AiTodoAction(type: AiTodoActionType.completeTodo, todoId: skipped.id),
      ],
      existingTodos: AiTodoChatLauncher.toChatTodoMaps([skipped]),
    );
    expect(result.updatedTodos, hasLength(1));
    expect(result.updatedTodos.single.isDone, isTrue);
    expect(result.updatedTodos.single.isSkipped, isFalse);
    expect(result.updatedTodos.single.isSkippedSyncPending, isTrue);
  });
}
