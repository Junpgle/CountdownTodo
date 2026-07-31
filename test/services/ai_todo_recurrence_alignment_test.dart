import 'package:countdown_todo/models.dart';
import 'package:countdown_todo/models/ai_todo_action.dart';
import 'package:countdown_todo/services/ai_action_parser.dart';
import 'package:countdown_todo/services/ai_todo_action_executor.dart';
import 'package:countdown_todo/services/ai_todo_chat_launcher.dart';
import 'package:countdown_todo/services/ai_todo_context_builder.dart';
import 'package:countdown_todo/services/llm_service.dart';
import 'package:countdown_todo/services/todo_classification_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TodoItem occurrence({
    required String id,
    required int day,
    required RecurrenceType recurrence,
    bool isDone = false,
    String? teamUuid,
  }) {
    final start = DateTime(2026, 7, day);
    return TodoItem(
      id: id,
      title: '喝水',
      isDone: isDone,
      createdDate: start.millisecondsSinceEpoch,
      dueDate: DateTime(2026, 7, day, 23, 59),
      isAllDay: true,
      recurrence: recurrence,
      recurrenceSeriesId: 'series-water',
      recurrenceEndDate: DateTime(2026, 8, 31),
      reminderMinutes: 10,
      teamUuid: teamUuid,
    );
  }

  group('AI recurring todo alignment', () {
    test('chat context exposes occurrence and series identities separately',
        () {
      final current = occurrence(
        id: 'occurrence-current',
        day: 20,
        recurrence: RecurrenceType.daily,
      );
      final future = occurrence(
        id: 'occurrence-future',
        day: 21,
        recurrence: RecurrenceType.none,
      );

      final maps = AiTodoChatLauncher.toChatTodoMaps([current, future]);
      final futureMap = maps.singleWhere(
        (todo) => todo['id'] == 'occurrence-future',
      );

      expect(futureMap['recurrence'], 'none');
      expect(futureMap['recurrenceRule'], 'daily');
      expect(futureMap['recurrenceSeriesId'], 'series-water');
      expect(futureMap['recurrenceRole'], 'occurrence');
      expect(futureMap['timeMode'], 'dateOnly');

      final prompt = AiTodoContextBuilder.buildSystemPrompt(
        customPrompt: '{todos}',
        promptEnabled: true,
        todos: maps,
        todoGroups: const [],
        now: DateTime(2026, 7, 20, 12),
      );
      expect(prompt, contains('期次todoId: occurrence-future'));
      expect(prompt, contains('系列ID: series-water'));
      expect(prompt, contains('系列规则: daily'));
    });

    test('parser preserves explicit null and recurrence scope patch intent',
        () {
      const response = '''
[ACTION_START]
[{"action":"update_todo","updates":[{"todoId":"occurrence-current","timeMode":"unscheduled","dueDate":null,"recurrence":"none","recurrenceSeriesId":"series-water","recurrenceScope":"future"}]}]
[ACTION_END]
''';

      final action = AiActionParser.extractTodoActions(
        response,
        originalText: '从本期开始结束循环并清空日期',
      ).single;

      expect(action.hasDueDate, isTrue);
      expect(action.dueDate, isNull);
      expect(action.hasTimeMode, isTrue);
      expect(action.hasRecurrence, isTrue);
      expect(action.recurrence, 'none');
      expect(action.recurrenceSeriesId, 'series-water');
      expect(action.appliesToFutureOccurrences, isTrue);

      final restored = AiTodoAction.fromJson(action.toJson());
      expect(restored.hasDueDate, isTrue);
      expect(restored.hasRecurrence, isTrue);
      expect(restored.appliesToFutureOccurrences, isTrue);
    });

    test('omitted recurrence keeps active rule and full todo metadata', () {
      final current = occurrence(
        id: 'occurrence-current',
        day: 20,
        recurrence: RecurrenceType.daily,
        teamUuid: 'team-1',
      );
      final action = AiTodoAction(
        type: AiTodoActionType.updateTodo,
        todoId: current.id,
        title: '按时喝水',
      );

      final result = AiTodoActionExecutor.execute(
        actions: [action],
        existingTodos: AiTodoChatLauncher.toChatTodoMaps([current]),
      );
      final updated = result.updatedTodos.single;

      expect(updated.title, '按时喝水');
      expect(updated.recurrence, RecurrenceType.daily);
      expect(updated.recurrenceSeriesId, 'series-water');
      expect(updated.teamUuid, 'team-1');
      expect(updated.createdAt, current.createdAt);
    });

    test('future scope updates current and later real occurrences only', () {
      final past = occurrence(
        id: 'occurrence-past',
        day: 19,
        recurrence: RecurrenceType.none,
      );
      final current = occurrence(
        id: 'occurrence-current',
        day: 20,
        recurrence: RecurrenceType.daily,
      );
      final future = occurrence(
        id: 'occurrence-future',
        day: 21,
        recurrence: RecurrenceType.none,
      );
      final action = AiTodoAction(
        type: AiTodoActionType.updateTodo,
        todoId: current.id,
        title: '补充水分',
        recurrenceSeriesId: 'series-water',
        recurrenceScope: 'future',
      );

      final result = AiTodoActionExecutor.execute(
        actions: [action],
        existingTodos:
            AiTodoChatLauncher.toChatTodoMaps([past, current, future]),
      );

      expect(
        result.updatedTodos.map((todo) => todo.id).toSet(),
        {'occurrence-current', 'occurrence-future'},
      );
      expect(
          result.updatedTodos,
          everyElement(predicate<TodoItem>(
            (todo) => todo.title == '补充水分',
          )));
      expect(
        result.updatedTodos
            .singleWhere((todo) => todo.id == 'occurrence-current')
            .recurrence,
        RecurrenceType.daily,
      );
      expect(
        result.updatedTodos
            .singleWhere((todo) => todo.id == 'occurrence-future')
            .recurrence,
        RecurrenceType.none,
      );
    });

    test('complete remains occurrence-only even if model emits future scope',
        () {
      final current = occurrence(
        id: 'occurrence-current',
        day: 20,
        recurrence: RecurrenceType.daily,
      );
      final future = occurrence(
        id: 'occurrence-future',
        day: 21,
        recurrence: RecurrenceType.none,
      );
      final action = AiTodoAction(
        type: AiTodoActionType.completeTodo,
        todoId: current.id,
        recurrenceScope: 'future',
      );

      final result = AiTodoActionExecutor.execute(
        actions: [action],
        existingTodos: AiTodoChatLauncher.toChatTodoMaps([current, future]),
      );

      expect(result.updatedTodos, hasLength(1));
      expect(result.updatedTodos.single.id, 'occurrence-current');
      expect(result.updatedTodos.single.isDone, isTrue);
    });

    test('ending recurrence keeps target and tombstones generated future', () {
      final current = occurrence(
        id: 'occurrence-current',
        day: 20,
        recurrence: RecurrenceType.daily,
      );
      final future = occurrence(
        id: 'occurrence-future',
        day: 21,
        recurrence: RecurrenceType.none,
      );
      final action = AiTodoAction(
        type: AiTodoActionType.updateTodo,
        todoId: current.id,
        recurrence: 'none',
        recurrenceSeriesId: 'series-water',
        recurrenceScope: 'future',
        hasRecurrence: true,
      );

      final result = AiTodoActionExecutor.execute(
        actions: [action],
        existingTodos: AiTodoChatLauncher.toChatTodoMaps([current, future]),
      );
      final target = result.updatedTodos.singleWhere(
        (todo) => todo.id == 'occurrence-current',
      );
      final generated = result.updatedTodos.singleWhere(
        (todo) => todo.id == 'occurrence-future',
      );

      expect(target.isDeleted, isFalse);
      expect(target.recurrence, RecurrenceType.none);
      expect(target.recurrenceEndDate, isNotNull);
      expect(generated.isDeleted, isTrue);
    });

    test('explicit unscheduled clears both todo time fields through merge', () {
      final current = occurrence(
        id: 'occurrence-current',
        day: 20,
        recurrence: RecurrenceType.daily,
      );
      final action = AiTodoAction(
        type: AiTodoActionType.updateTodo,
        todoId: current.id,
        timeMode: 'unscheduled',
        hasDueDate: true,
      );

      final result = AiTodoActionExecutor.execute(
        actions: [action],
        existingTodos: AiTodoChatLauncher.toChatTodoMaps([current]),
      );
      final merged = AiTodoActionExecutor.mergeTodoUpdates(
        [current],
        const [],
        result.updatedTodos,
      ).single;

      expect(merged.createdDate, isNull);
      expect(merged.dueDate, isNull);
      expect(merged.timeMode, TodoTimeMode.unscheduled);
      expect(merged.recurrence, RecurrenceType.daily);
    });

    test('new recurrence requires an anchor and gets a stable series id', () {
      final missingAnchor = AiTodoAction(
        type: AiTodoActionType.createTodo,
        title: '喝水',
        recurrence: 'daily',
      );
      final valid = AiTodoAction(
        type: AiTodoActionType.createTodo,
        title: '喝水',
        timeMode: 'dateOnly',
        dueDate: '2026-07-20 00:00',
        recurrence: 'daily',
      );

      final rejected = AiTodoActionExecutor.execute(
        actions: [missingAnchor],
        existingTodos: const [],
      );
      final accepted = AiTodoActionExecutor.execute(
        actions: [valid],
        existingTodos: const [],
      );

      expect(rejected.newTodos, isEmpty);
      expect(missingAnchor.isAdded, isFalse);
      expect(accepted.newTodos, hasLength(1));
      expect(accepted.newTodos.single.recurrenceSeriesId,
          accepted.newTodos.single.id);
      expect(accepted.newTodos.single.isDateOnly, isTrue);
    });

    test('action protocol documents recurrence occurrence safety', () {
      final prompt = AiTodoContextBuilder.buildActionProtocolPrompt('修改循环待办');

      expect(prompt, contains('recurrenceScope="occurrence"'));
      expect(prompt, contains('recurrenceScope="future"'));
      expect(prompt, contains('绝不能把seriesId当期次ID'));
      expect(prompt, contains('新建循环待办必须提供首次发生日期'));
    });

    test('automatic classification selects one active series representative',
        () {
      final current = occurrence(
        id: 'occurrence-current',
        day: 20,
        recurrence: RecurrenceType.daily,
      );
      final future = occurrence(
        id: 'occurrence-future',
        day: 21,
        recurrence: RecurrenceType.none,
      );

      final representatives =
          TodoClassificationService.seriesRepresentativesForTest(
        [future, current],
      );

      expect(representatives, hasLength(1));
      expect(representatives.single.id, 'occurrence-current');
    });
  });

  group('AI fixed schedule alignment', () {
    FixedScheduleItem schedule({
      required String id,
      required int day,
      RecurrenceType recurrence = RecurrenceType.daily,
    }) {
      return FixedScheduleItem(
        id: id,
        title: '项目例会',
        date: '2026-07-${day.toString().padLeft(2, '0')}',
        startTime: DateTime(2026, 7, day, 10).millisecondsSinceEpoch,
        endTime: DateTime(2026, 7, day, 11).millisecondsSinceEpoch,
        source: FixedScheduleSource.ai,
        recurrence: recurrence,
        recurrenceSeriesId: 'series-meeting',
      );
    }

    test('parser keeps schedule identity, null clears, and reminder list', () {
      const response = '''
[ACTION_START]
[{"action":"update_schedule","updates":[{"scheduleId":"schedule-1","location":null,"endTime":null,"reminderMinutes":[0,15],"recurrenceScope":"future"}]}]
[ACTION_END]
''';

      final action = AiActionParser.extractTodoActions(
        response,
        originalText: '后续例会地点待定，结束时间待定',
      ).single;

      expect(action.type, AiTodoActionType.updateFixedSchedule);
      expect(action.scheduleId, 'schedule-1');
      expect(action.hasLocation, isTrue);
      expect(action.location, isNull);
      expect(action.hasDueDate, isTrue);
      expect(action.dueDate, isNull);
      expect(action.reminderMinutesList, [0, 15]);
      expect(action.hasReminderMinutesList, isTrue);
      expect(action.appliesToFutureOccurrences, isTrue);
    });

    test('creates start-only schedule without inventing an end time', () {
      final action = AiTodoAction.fromJson({
        'action': 'create_schedule',
        'title': '项目例会',
        'date': '2026-07-20',
        'startTime': '2026-07-20 10:00',
        'endTime': null,
        'location': '第一会议室',
        'reminderMinutes': [15, 60],
      });

      final result = AiTodoActionExecutor.execute(
        actions: [action],
        existingTodos: const [],
        now: DateTime(2026, 7, 1),
      );
      final created = result.newFixedSchedules.single;

      expect(created.date, '2026-07-20');
      expect(
          created.startTime, DateTime(2026, 7, 20, 10).millisecondsSinceEpoch);
      expect(created.endTime, isNull);
      expect(created.source, FixedScheduleSource.ai);
      expect(created.location, '第一会议室');
      expect(created.reminderMinutes, [15, 60]);
    });

    test('materializes recurring schedules into independently addressed dates',
        () {
      final action = AiTodoAction.fromJson({
        'action': 'create_schedule',
        'title': '晨会',
        'date': '2026-07-20',
        'startTime': '2026-07-20 09:00',
        'endTime': '2026-07-20 09:30',
        'recurrence': 'daily',
        'recurrenceEndDate': '2026-07-22',
      });

      final result = AiTodoActionExecutor.execute(
        actions: [action],
        existingTodos: const [],
      );

      expect(result.newFixedSchedules, hasLength(3));
      expect(
        result.newFixedSchedules.map((item) => item.date),
        ['2026-07-20', '2026-07-21', '2026-07-22'],
      );
      expect(
        result.newFixedSchedules.map((item) => item.id).toSet(),
        hasLength(3),
      );
      expect(
        result.newFixedSchedules.map((item) => item.recurrenceSeriesId).toSet(),
        hasLength(1),
      );
    });

    test('future cancellation does not touch past schedule occurrences', () {
      final past =
          schedule(id: 'past', day: 19, recurrence: RecurrenceType.none);
      final current = schedule(id: 'current', day: 20);
      final future =
          schedule(id: 'future', day: 21, recurrence: RecurrenceType.none);
      final action = AiTodoAction(
        type: AiTodoActionType.cancelFixedSchedule,
        scheduleId: current.id,
        recurrenceSeriesId: 'series-meeting',
        recurrenceScope: 'future',
      );

      final result = AiTodoActionExecutor.execute(
        actions: [action],
        existingTodos: const [],
        existingFixedSchedules: [past, current, future],
      );

      expect(
        result.updatedFixedSchedules.map((item) => item.id).toSet(),
        {'current', 'future'},
      );
      expect(
        result.updatedFixedSchedules,
        everyElement(predicate<FixedScheduleItem>(
          (item) => item.status == FixedScheduleStatus.cancelled,
        )),
      );
      expect(past.status, FixedScheduleStatus.scheduled);
    });

    test('occurrence scope cannot silently rewrite a recurring rule', () {
      final current = schedule(id: 'current', day: 20);
      final action = AiTodoAction(
        type: AiTodoActionType.updateFixedSchedule,
        scheduleId: current.id,
        recurrence: 'weekly',
        hasRecurrence: true,
      );

      final result = AiTodoActionExecutor.execute(
        actions: [action],
        existingTodos: const [],
        existingFixedSchedules: [current],
      );

      expect(result.updatedFixedSchedules, isEmpty);
      expect(action.isAdded, isFalse);
    });

    test('planning context injects fixed schedules as hard constraints', () {
      final item = schedule(id: 'current', day: 20);
      final injection = AiTodoContextBuilder.buildContextInjection(
        userMessage: '帮我规划今天的时间',
        courses: const [],
        timeLogs: const [],
        fixedSchedules: [item],
        conflicts: const [],
        teams: const [],
        now: DateTime(2026, 7, 20, 8),
      );

      expect(injection, contains('日程ID: current'));
      expect(injection, contains('外部时间硬约束'));
      expect(injection, contains('系列ID: series-meeting'));
      expect(
        AiTodoContextBuilder.buildActionProtocolPrompt('明天10点开项目会议'),
        contains('create_schedule'),
      );
    });

    test('recognition prompts enforce current item and recurrence semantics',
        () {
      expect(LLMConfig.defaultTextPrompt, contains('location'));
      expect(LLMConfig.defaultTextPrompt, contains('不得默认今天'));
      expect(LLMConfig.defaultTextPrompt, contains('fixedSchedule默认15'));
      expect(LLMConfig.defaultVisionPrompt, contains('保留recurrence'));
      expect(
        LLMConfig.itemSemanticGuardrailPrompt,
        allOf(
          contains('优先于前文'),
          contains('禁止默认今天'),
          contains('fixedSchedule地点使用location字段'),
        ),
      );
    });
  });
}
