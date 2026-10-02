import 'package:countdown_todo/models.dart';
import 'package:countdown_todo/models/ai_todo_action.dart';
import 'package:countdown_todo/services/ai_action_parser.dart';
import 'package:countdown_todo/services/ai_todo_action_executor.dart';
import 'package:countdown_todo/services/ai_todo_chat_launcher.dart';
import 'package:countdown_todo/services/ai_todo_context_builder.dart';
import 'package:countdown_todo/services/chat_storage_service.dart';
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
      expect(futureMap['dueDate'], endsWith('23:59'));

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
      expect(prompt, contains('目标日期: 2026-07-20'));
      expect(prompt, isNot(contains('日期锚点:')));
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

    test(
        'legacy plan_todos schedules an existing todo instead of duplicating it',
        () {
      const response = '''
[ACTION_START]
[{"action":"plan_todos","todos":[{"title":"复习高数","startTime":"2026-07-20 19:00","dueDate":"2026-07-20 20:00"}]}]
[ACTION_END]
''';

      final actions = AiActionParser.extractTodoActions(
        response,
        originalText: '帮我规划今天的待办',
        existingTodoTitles: const {'todo-math': '复习高数'},
      );
      final result = AiTodoActionExecutor.execute(
        actions: actions,
        existingTodos: const [
          {'id': 'todo-math', 'title': '复习高数'},
        ],
      );

      expect(actions.single.type, AiTodoActionType.createPlanBlock);
      expect(actions.single.todoId, 'todo-math');
      expect(result.newTodos, isEmpty);
      expect(result.newPlanBlocks, hasLength(1));
      expect(result.newPlanBlocks.single.todoId, 'todo-math');
    });

    test('unmatched legacy plan_todos cannot create a duplicate todo', () {
      const response = '''
[ACTION_START]
[{"action":"plan_todos","todos":[{"title":"复习高数（今晚）","startTime":"2026-07-20 19:00","dueDate":"2026-07-20 20:00"}]}]
[ACTION_END]
''';

      final actions = AiActionParser.extractTodoActions(
        response,
        originalText: '帮我规划今天的待办',
        existingTodoTitles: const {'todo-math': '复习高数'},
      );

      expect(actions, isEmpty);
    });

    test('actionless planning payload resolves an exact existing todo only',
        () {
      const response = '''
[ACTION_START]
[{"todos":[{"title":"复习高数","startTime":"2026-07-20 19:00","endTime":"2026-07-20 20:00"}]}]
[ACTION_END]
''';

      final actions = AiActionParser.extractTodoActions(
        response,
        originalText: '帮我规划今天的待办',
        existingTodoTitles: const {'todo-math': '复习高数'},
      );
      final result = AiTodoActionExecutor.execute(
        actions: actions,
        existingTodos: const [
          {'id': 'todo-math', 'title': '复习高数'},
        ],
      );

      expect(actions.single.type, AiTodoActionType.createPlanBlock);
      expect(actions.single.todoId, 'todo-math');
      expect(result.newTodos, isEmpty);
      expect(result.newPlanBlocks, hasLength(1));
    });

    test('actionless todo payload is rejected instead of creating a todo', () {
      const response = '''
[ACTION_START]
[{"todos":[{"title":"买牛奶","timeMode":"unscheduled","dueDate":null}]}]
[ACTION_END]
''';

      final actions = AiActionParser.extractTodoActions(
        response,
        originalText: '帮我新增买牛奶',
      );
      final result = AiTodoActionExecutor.execute(
        actions: actions,
        existingTodos: const [],
      );

      expect(actions, isEmpty);
      expect(result.newTodos, isEmpty);
    });

    test(
        'executor rejects a legacy plan_todos action without a resolved target',
        () {
      final action = AiTodoAction(
        type: AiTodoActionType.planTodos,
        title: '复习高数',
        startTime: '2026-07-20 19:00',
        dueDate: '2026-07-20 20:00',
      );

      final result = AiTodoActionExecutor.execute(
        actions: [action],
        existingTodos: const [],
      );

      expect(result.newTodos, isEmpty);
      expect(action.isAdded, isFalse);
    });

    test('action protocol documents recurrence occurrence safety', () {
      final prompt = AiTodoContextBuilder.buildActionProtocolPrompt('修改循环待办');

      expect(prompt, contains('recurrenceScope="occurrence"'));
      expect(prompt, contains('recurrenceScope="future"'));
      expect(prompt, contains('绝不能把seriesId当期次ID'));
      expect(prompt, contains('新建循环待办必须提供首次发生日期'));
    });

    test('planning protocol prioritizes plan blocks over todo creation', () {
      final prompt =
          AiTodoContextBuilder.buildActionProtocolPrompt('帮我规划今天的待办');

      expect(prompt, contains('- create_plan_block:'));
      expect(prompt, contains('禁止用create_todo复制已有待办'));
      expect(prompt, isNot(contains('plan_todos')));
      expect(prompt, isNot(contains('- create_todo:')));
      expect(prompt, isNot(contains('- create_schedule:')));
    });

    test('parses create_habit payload and preserves habit fields', () {
      const response = '''
[ACTION_START]
[{"action":"create_habit","habits":[{"name":"每天喝水","icon":"💧","sourceType":"quantityCheckIn","periodType":"daily","targetValue":1600,"unit":"ml","quickValues":[200,500],"reminderPolicy":{"fixedTimes":[480],"progressReminder":true}}]}]
[ACTION_END]
''';

      final actions = AiActionParser.extractTodoActions(
        response,
        originalText: '创建每天喝水习惯',
      );

      expect(actions, hasLength(1));
      final action = actions.single;
      expect(action.type, AiTodoActionType.createHabit);
      expect(action.title, '每天喝水');
      expect(action.habitSourceType, 'quantityCheckIn');
      expect(action.targetValue, 1600);
      expect(action.unit, 'ml');
      expect(action.quickValues, [200, 500]);
      expect(action.habitReminderPolicy?['fixedTimes'], [480]);

      final restored = AiTodoAction.fromJson(action.toJson());
      expect(restored.type, AiTodoActionType.createHabit);
      expect(restored.habitSourceType, 'quantityCheckIn');
      expect(restored.targetValue, 1600);
    });

    test('routes habit creation away from new todo creation', () {
      final action = AiTodoAction(
        type: AiTodoActionType.createHabit,
        title: '每天阅读',
        icon: '📖',
        habitSourceType: 'durationCheckIn',
        habitPeriodType: 'daily',
        durationMinutes: 30,
      );

      final result = AiTodoActionExecutor.execute(
        actions: [action],
        existingTodos: const [],
      );

      expect(result.newHabitActions, [action]);
      expect(result.newTodos, isEmpty);
      expect(result.hasChanges, isTrue);
      expect(action.isAdded, isFalse);
    });

    test('habit request protocol tells the model to use create_habit', () {
      final prompt = AiTodoContextBuilder.buildActionProtocolPrompt(
        '创建一个每天喝水的习惯',
      );

      expect(prompt, contains('- create_habit:'));
      expect(prompt, contains('必须使用create_habit'));
      expect(prompt, isNot(contains('- create_todo:')));
    });

    test('ambiguous recurring activity asks habit or todo before creating', () {
      final prompt = AiTodoContextBuilder.buildActionProtocolPrompt('创建每天喝水');

      expect(prompt, contains('要创建成习惯，还是循环待办'));
      expect(prompt, contains('不要输出任何创建动作'));
      expect(prompt, isNot(contains('plan_todos')));
      expect(prompt, isNot(contains('- create_habit:')));
      expect(prompt, isNot(contains('- create_todo:')));
    });

    test('explicit recurring todo still exposes todo actions', () {
      final prompt = AiTodoContextBuilder.buildActionProtocolPrompt(
        '创建一个每天喝水的待办',
      );

      expect(prompt, contains('- create_todo:'));
      expect(prompt, isNot(contains('要创建成习惯，还是循环待办')));
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
      expect(
          LLMConfig.defaultTextPrompt, contains('普通todo只输出timeMode和dueDate'));
      expect(
          LLMConfig.defaultTextPrompt, isNot(contains('普通todo禁止输出startTime')));
      expect(LLMConfig.defaultVisionPrompt, contains('保留recurrence'));
      expect(
        LLMConfig.itemSemanticGuardrailPrompt,
        allOf(
          contains('CDT_RECOGNITION_PROTOCOL_V2'),
          contains('优先于前文'),
          contains('禁止默认今天'),
          contains('fixedSchedule地点使用location字段'),
        ),
      );
      expect(ChatStorageService.defaultPrompt, isNot(contains('plan_todos')));
      final migratedPrompt = ChatStorageService.ensureCurrentPromptProtocol(
        '自定义提示词：请帮助用户安排事项\n旧协议：plan_todos',
      );
      expect(migratedPrompt, contains('CDT_CHAT_PROTOCOL_V2'));
      expect(migratedPrompt, contains('create_plan_block'));
      expect(migratedPrompt, isNot(contains('plan_todos')));
    });

    test('image prompt adds compact island content to saved prompts', () {
      final config = LLMConfig(
        apiKey: 'test-key',
        model: 'test-model',
        visionPrompt: '自定义图片识别：按{now}判断日期。\nCDT_RECOGNITION_PROTOCOL_V2',
      );

      final prompt = LLMService.buildTodoVisionPrompt(
        config,
        now: '2026-09-30 13:01',
      );

      expect(prompt, startsWith('自定义图片识别：按2026-09-30 13:01判断日期。'));
      expect(prompt, endsWith(LLMConfig.visionTodoConcisenessPrompt));
      expect(prompt, contains('remark会作为灵动岛内容展示'));
      expect(prompt, contains('有码时只写'));
      expect(prompt, contains('没有明确待办或日程时返回[]'));
      expect(prompt, isNot(contains('{now}')));
    });

    test('注入更多不覆盖明确的上个月效率范围', () {
      final now = DateTime(2026, 10, 1, 12);
      final timeLogs = [
        for (var day in [7, 14, 21])
          TimeLogItem(
            id: 'last-month-log-$day',
            title: '上月专注 $day 日',
            startTime: DateTime(2026, 9, day, 9).millisecondsSinceEpoch,
            endTime: DateTime(2026, 9, day, 10).millisecondsSinceEpoch,
          ),
        TimeLogItem(
          id: 'future-log',
          title: '未来专注记录',
          startTime: DateTime(2026, 10, 5, 9).millisecondsSinceEpoch,
          endTime: DateTime(2026, 10, 5, 10).millisecondsSinceEpoch,
        ),
      ];
      final planBlocks = [
        for (var day in [7, 14, 21])
          TodoPlanBlock(
            id: 'last-month-plan-$day',
            todoId: 'todo-$day',
            titleSnapshot: '上月计划任务 $day 日',
            startTime: DateTime(2026, 9, day, 9).millisecondsSinceEpoch,
            endTime: DateTime(2026, 9, day, 10).millisecondsSinceEpoch,
            plannedMinutes: 60,
          ),
        TodoPlanBlock(
          id: 'future-plan',
          todoId: 'todo-future',
          titleSnapshot: '未来计划任务',
          startTime: DateTime(2026, 10, 5, 9).millisecondsSinceEpoch,
          endTime: DateTime(2026, 10, 5, 10).millisecondsSinceEpoch,
          plannedMinutes: 60,
        ),
      ];

      String buildContext(String userMessage) =>
          AiTodoContextBuilder.buildContextInjection(
            userMessage: userMessage,
            courses: const [],
            timeLogs: timeLogs,
            planBlocks: planBlocks,
            conflicts: const [],
            teams: const [],
            now: now,
          )!;

      final regular = buildContext('分析我上个月的效率');
      final expanded = buildContext('分析我上个月的效率，并扩大到未来30天范围');

      expect(regular, contains('last-month-log-7'));
      expect(regular, contains('last-month-plan-7'));
      expect(regular, isNot(contains('future-log')));
      expect(regular, isNot(contains('future-plan')));
      expect(expanded, equals(regular));
    });

    test('上周效率只汇总上一自然周，不混入本周记录', () {
      final now = DateTime(2026, 10, 2, 12);
      final timeLogs = [
        TimeLogItem(
          id: 'last-week-monday',
          title: '上周周一专注',
          startTime: DateTime(2026, 9, 21, 9).millisecondsSinceEpoch,
          endTime: DateTime(2026, 9, 21, 10).millisecondsSinceEpoch,
        ),
        TimeLogItem(
          id: 'last-week-sunday',
          title: '上周周日专注',
          startTime: DateTime(2026, 9, 27, 10).millisecondsSinceEpoch,
          endTime: DateTime(2026, 9, 27, 11).millisecondsSinceEpoch,
        ),
        TimeLogItem(
          id: 'this-week',
          title: '本周专注',
          startTime: DateTime(2026, 10, 1, 11).millisecondsSinceEpoch,
          endTime: DateTime(2026, 10, 1, 12).millisecondsSinceEpoch,
        ),
      ];

      final context = AiTodoContextBuilder.buildContextInjection(
        userMessage: '分析上周的效率',
        courses: const [],
        timeLogs: timeLogs,
        conflicts: const [],
        teams: const [],
        now: now,
      )!;
      final preview = AiTodoContextBuilder.buildContextInjectionSummary(
        userMessage: '分析上周的效率',
        courses: const [],
        timeLogs: timeLogs,
        conflicts: const [],
        teams: const [],
        now: now,
      )!;

      expect(context, contains('上周合计'));
      expect(context, contains('last-week-monday'));
      expect(context, contains('last-week-sunday'));
      expect(context, isNot(contains('this-week')));
      expect(preview, contains('专注记录20260921-20260927'));
      expect(preview, isNot(contains('最近30条')));
    });

    test('最近七天效率按含今天的滚动自然日范围汇总', () {
      final now = DateTime(2026, 10, 2, 12);
      final timeLogs = [
        TimeLogItem(
          id: 'outside-seven-days',
          title: '七天前专注',
          startTime: DateTime(2026, 9, 25, 9).millisecondsSinceEpoch,
          endTime: DateTime(2026, 9, 25, 10).millisecondsSinceEpoch,
        ),
        TimeLogItem(
          id: 'first-day-in-range',
          title: '范围首日专注',
          startTime: DateTime(2026, 9, 26, 9).millisecondsSinceEpoch,
          endTime: DateTime(2026, 9, 26, 10).millisecondsSinceEpoch,
        ),
        TimeLogItem(
          id: 'inside-seven-days',
          title: '本周专注',
          startTime: DateTime(2026, 10, 1, 11).millisecondsSinceEpoch,
          endTime: DateTime(2026, 10, 1, 12).millisecondsSinceEpoch,
        ),
        TimeLogItem(
          id: 'future-log',
          title: '未来专注',
          startTime: DateTime(2026, 10, 3, 9).millisecondsSinceEpoch,
          endTime: DateTime(2026, 10, 3, 10).millisecondsSinceEpoch,
        ),
      ];

      final context = AiTodoContextBuilder.buildContextInjection(
        userMessage: '分析最近七天的效率',
        courses: const [],
        timeLogs: timeLogs,
        conflicts: const [],
        teams: const [],
        now: now,
      )!;
      final preview = AiTodoContextBuilder.buildContextInjectionSummary(
        userMessage: '分析最近七天的效率',
        courses: const [],
        timeLogs: timeLogs,
        conflicts: const [],
        teams: const [],
        now: now,
      )!;

      expect(context, contains('最近7天合计'));
      expect(context, isNot(contains('outside-seven-days')));
      expect(context, contains('first-day-in-range'));
      expect(context, contains('inside-seven-days'));
      expect(context, isNot(contains('future-log')));
      expect(preview, contains('专注记录20260926-20261002'));

      final thirtyDayContext = AiTodoContextBuilder.buildContextInjection(
        userMessage: '分析最近30天的效率',
        courses: const [],
        timeLogs: timeLogs,
        conflicts: const [],
        teams: const [],
        now: now,
      )!;
      final thirtyDayPreview =
          AiTodoContextBuilder.buildContextInjectionSummary(
            userMessage: '分析最近30天的效率',
            courses: const [],
            timeLogs: timeLogs,
            conflicts: const [],
            teams: const [],
            now: now,
          )!;

      expect(thirtyDayContext, contains('最近30天合计'));
      expect(thirtyDayContext, contains('outside-seven-days'));
      expect(thirtyDayContext, isNot(contains('future-log')));
      expect(thirtyDayPreview, contains('专注记录20260903-20261002'));
    });
    test('效率分析按去年、今年和上一自然季度筛选记录', () {
      final now = DateTime(2026, 10, 2, 12);
      final timeLogs = [
        ('last-year', DateTime(2025, 12, 31, 9)),
        ('this-year-start', DateTime(2026, 1, 1, 9)),
        ('previous-quarter', DateTime(2026, 6, 30, 9)),
        ('last-quarter-start', DateTime(2026, 7, 1, 9)),
        ('last-quarter-end', DateTime(2026, 9, 30, 9)),
        ('this-quarter', DateTime(2026, 10, 1, 9)),
        ('future', DateTime(2026, 10, 3, 9)),
      ].map((entry) => TimeLogItem(
        id: entry.$1,
        title: entry.$1,
        startTime: entry.$2.millisecondsSinceEpoch,
        endTime: entry.$2.add(const Duration(hours: 1)).millisecondsSinceEpoch,
      )).toList();

      String contextFor(String prompt) =>
          AiTodoContextBuilder.buildContextInjection(
            userMessage: prompt,
            courses: const [],
            timeLogs: timeLogs,
            conflicts: const [],
            teams: const [],
            now: now,
          )!;
      String previewFor(String prompt) =>
          AiTodoContextBuilder.buildContextInjectionSummary(
            userMessage: prompt,
            courses: const [],
            timeLogs: timeLogs,
            conflicts: const [],
            teams: const [],
            now: now,
          )!;

      final lastQuarter = contextFor('分析上季度的效率');
      expect(lastQuarter, contains('上季度合计'));
      expect(lastQuarter, contains('last-quarter-start'));
      expect(lastQuarter, contains('last-quarter-end'));
      expect(lastQuarter, isNot(contains('previous-quarter')));
      expect(lastQuarter, isNot(contains('this-quarter')));
      expect(lastQuarter, isNot(contains('future')));
      expect(previewFor('分析上季度的效率'), contains('专注记录20260701-20260930'));

      final thisYear = contextFor('分析今年的效率');
      expect(thisYear, contains('今年合计'));
      expect(thisYear, contains('this-year-start'));
      expect(thisYear, contains('this-quarter'));
      expect(thisYear, isNot(contains('last-year')));
      expect(thisYear, isNot(contains('future')));
      expect(previewFor('分析今年的效率'), contains('专注记录20260101-20261002'));

      final lastYear = contextFor('分析去年效率');
      expect(lastYear, contains('去年合计'));
      expect(lastYear, contains('last-year'));
      expect(lastYear, isNot(contains('this-year-start')));
      expect(previewFor('分析去年效率'), contains('专注记录20250101-20251231'));
    });

    test('本周和本月效率范围截止今天，不包含未来日志', () {
      final now = DateTime(2026, 10, 2, 12);
      final timeLogs = [
        ('last-week', DateTime(2026, 9, 27, 9)),
        ('current-week', DateTime(2026, 10, 1, 9)),
        ('future', DateTime(2026, 10, 3, 9)),
      ].map((entry) => TimeLogItem(
        id: entry.$1,
        title: entry.$1,
        startTime: entry.$2.millisecondsSinceEpoch,
        endTime: entry.$2.add(const Duration(hours: 1)).millisecondsSinceEpoch,
      )).toList();

      String contextFor(String prompt) =>
          AiTodoContextBuilder.buildContextInjection(
            userMessage: prompt,
            courses: const [],
            timeLogs: timeLogs,
            conflicts: const [],
            teams: const [],
            now: now,
          )!;
      String previewFor(String prompt) =>
          AiTodoContextBuilder.buildContextInjectionSummary(
            userMessage: prompt,
            courses: const [],
            timeLogs: timeLogs,
            conflicts: const [],
            teams: const [],
            now: now,
          )!;

      final thisWeek = contextFor('分析本周的效率');
      expect(thisWeek, contains('本周合计'));
      expect(thisWeek, contains('current-week'));
      expect(thisWeek, isNot(contains('last-week')));
      expect(thisWeek, isNot(contains('future')));
      expect(previewFor('分析本周的效率'), contains('专注记录20260928-20261002'));

      final thisMonth = contextFor('分析本月的效率');
      expect(thisMonth, contains('本月合计'));
      expect(thisMonth, contains('current-week'));
      expect(thisMonth, isNot(contains('future')));
      expect(previewFor('分析本月的效率'), contains('专注记录20261001-20261002'));
    });

    test('指定年份和最近一年效率查询使用完整对应日期范围', () {
      final now = DateTime(2026, 10, 2, 12);
      final timeLogs = [
        ('year-2024', DateTime(2024, 12, 31, 9)),
        ('year-2025-start', DateTime(2025, 1, 1, 9)),
        ('rolling-outside', DateTime(2025, 10, 1, 9)),
        ('rolling-start', DateTime(2025, 10, 2, 9)),
        ('year-2025-end', DateTime(2025, 12, 31, 9)),
        ('year-2026', DateTime(2026, 1, 1, 9)),
        ('future', DateTime(2026, 10, 3, 9)),
      ].map((entry) => TimeLogItem(
        id: entry.$1,
        title: entry.$1,
        startTime: entry.$2.millisecondsSinceEpoch,
        endTime: entry.$2.add(const Duration(hours: 1)).millisecondsSinceEpoch,
      )).toList();

      String contextFor(String prompt) =>
          AiTodoContextBuilder.buildContextInjection(
            userMessage: prompt,
            courses: const [],
            timeLogs: timeLogs,
            conflicts: const [],
            teams: const [],
            now: now,
          )!;
      String previewFor(String prompt) =>
          AiTodoContextBuilder.buildContextInjectionSummary(
            userMessage: prompt,
            courses: const [],
            timeLogs: timeLogs,
            conflicts: const [],
            teams: const [],
            now: now,
          )!;

      final year2025 = contextFor('分析2025年效率');
      expect(year2025, contains('2025年合计'));
      expect(year2025, contains('year-2025-start'));
      expect(year2025, contains('year-2025-end'));
      expect(year2025, isNot(contains('year-2024')));
      expect(year2025, isNot(contains('year-2026')));
      expect(previewFor('分析2025年效率'), contains('专注记录20250101-20251231'));

      final recentYear = contextFor('分析最近一年的效率');
      expect(recentYear, contains('最近一年合计'));
      expect(recentYear, contains('rolling-start'));
      expect(recentYear, contains('year-2025-end'));
      expect(recentYear, isNot(contains('rolling-outside')));
      expect(recentYear, isNot(contains('year-2024')));
      expect(recentYear, isNot(contains('future')));
      expect(previewFor('分析最近一年的效率'), contains('专注记录20251002-20261002'));
    });

    test('明确年月和去年某月效率查询不会回退到最近30条', () {
      final now = DateTime(2026, 10, 2, 12);
      final timeLogs = [
        ('before-month', DateTime(2025, 8, 31, 9)),
        ('month-start', DateTime(2025, 9, 1, 9)),
        ('month-end', DateTime(2025, 9, 30, 9)),
        ('after-month', DateTime(2025, 10, 1, 9)),
      ].map((entry) => TimeLogItem(
        id: entry.$1,
        title: entry.$1,
        startTime: entry.$2.millisecondsSinceEpoch,
        endTime: entry.$2.add(const Duration(hours: 1)).millisecondsSinceEpoch,
      )).toList();

      String contextFor(String prompt) =>
          AiTodoContextBuilder.buildContextInjection(
            userMessage: prompt,
            courses: const [],
            timeLogs: timeLogs,
            conflicts: const [],
            teams: const [],
            now: now,
          )!;
      String previewFor(String prompt) =>
          AiTodoContextBuilder.buildContextInjectionSummary(
            userMessage: prompt,
            courses: const [],
            timeLogs: timeLogs,
            conflicts: const [],
            teams: const [],
            now: now,
          )!;

      final explicitMonth = contextFor('分析2025年9月效率');
      expect(explicitMonth, contains('2025年9月合计'));
      expect(explicitMonth, contains('month-start'));
      expect(explicitMonth, contains('month-end'));
      expect(explicitMonth, isNot(contains('before-month')));
      expect(explicitMonth, isNot(contains('after-month')));
      expect(previewFor('分析2025年9月效率'), contains('专注记录20250901-20250930'));

      final relativeMonth = contextFor('分析去年9月效率');
      expect(relativeMonth, contains('2025年9月合计'));
      expect(relativeMonth, contains('month-start'));
      expect(relativeMonth, isNot(contains('before-month')));
      expect(relativeMonth, isNot(contains('after-month')));
    });

    test('自然语言具体季度效率查询筛选正确的季度和年份', () {
      final now = DateTime(2026, 10, 2, 12);
      final timeLogs = [
        ('2025-q2', DateTime(2025, 6, 30, 9)),
        ('2025-q3-start', DateTime(2025, 7, 1, 9)),
        ('2025-q3-end', DateTime(2025, 9, 30, 9)),
        ('2025-q4', DateTime(2025, 10, 1, 9)),
        ('2026-q3-start', DateTime(2026, 7, 1, 9)),
        ('2026-q3-end', DateTime(2026, 9, 30, 9)),
        ('2026-q4', DateTime(2026, 10, 1, 9)),
      ].map((entry) => TimeLogItem(
        id: entry.$1,
        title: entry.$1,
        startTime: entry.$2.millisecondsSinceEpoch,
        endTime: entry.$2.add(const Duration(hours: 1)).millisecondsSinceEpoch,
      )).toList();

      String contextFor(String prompt) =>
          AiTodoContextBuilder.buildContextInjection(
            userMessage: prompt,
            courses: const [],
            timeLogs: timeLogs,
            conflicts: const [],
            teams: const [],
            now: now,
          )!;
      String previewFor(String prompt) =>
          AiTodoContextBuilder.buildContextInjectionSummary(
            userMessage: prompt,
            courses: const [],
            timeLogs: timeLogs,
            conflicts: const [],
            teams: const [],
            now: now,
          )!;

      final explicitQuarter = contextFor('分析2025年第三季度效率');
      expect(explicitQuarter, contains('2025年第3季度合计'));
      expect(explicitQuarter, contains('2025-q3-start'));
      expect(explicitQuarter, contains('2025-q3-end'));
      expect(explicitQuarter, isNot(contains('2025-q2')));
      expect(explicitQuarter, isNot(contains('2025-q4')));
      expect(previewFor('分析2025年第三季度效率'), contains('专注记录20250701-20250930'));

      final relativeQuarter = contextFor('分析今年第三季度效率');
      expect(relativeQuarter, contains('2026年第3季度合计'));
      expect(relativeQuarter, contains('2026-q3-start'));
      expect(relativeQuarter, contains('2026-q3-end'));
      expect(relativeQuarter, isNot(contains('2026-q4')));
      expect(previewFor('分析第三季度效率'), contains('专注记录20260701-20260930'));
    });

    test('显式单日效率查询只汇总指定日期', () {
      final now = DateTime(2026, 10, 2, 12);
      final timeLogs = [
        ('previous-day', DateTime(2026, 9, 30, 9)),
        ('selected-day', DateTime(2026, 10, 1, 9)),
        ('today', DateTime(2026, 10, 2, 9)),
        ('future-day', DateTime(2026, 10, 3, 9)),
      ].map((entry) => TimeLogItem(
        id: entry.$1,
        title: entry.$1,
        startTime: entry.$2.millisecondsSinceEpoch,
        endTime: entry.$2.add(const Duration(hours: 1)).millisecondsSinceEpoch,
      )).toList();

      final context = AiTodoContextBuilder.buildContextInjection(
        userMessage: '分析2026-10-01的效率',
        courses: const [],
        timeLogs: timeLogs,
        conflicts: const [],
        teams: const [],
        now: now,
      )!;
      final preview = AiTodoContextBuilder.buildContextInjectionSummary(
        userMessage: '分析2026-10-01的效率',
        courses: const [],
        timeLogs: timeLogs,
        conflicts: const [],
        teams: const [],
        now: now,
      )!;

      expect(context, contains('2026-10-01合计'));
      expect(context, contains('selected-day'));
      expect(context, isNot(contains('previous-day')));
      expect(context, isNot(contains('today')));
      expect(context, isNot(contains('future-day')));
      expect(preview, contains('专注记录20261001'));
    });

    test('具体年月日和月日效率范围优先于整月匹配', () {
      final now = DateTime(2026, 10, 2, 12);
      final timeLogs = [
        ('last-year-september-first', DateTime(2025, 9, 1, 9)),
        ('last-year-september-last', DateTime(2025, 9, 30, 9)),
        ('current-october-first', DateTime(2026, 10, 1, 9)),
        ('today', DateTime(2026, 10, 2, 9)),
        ('future', DateTime(2026, 10, 3, 9)),
      ].map((entry) => TimeLogItem(
        id: entry.$1,
        title: entry.$1,
        startTime: entry.$2.millisecondsSinceEpoch,
        endTime: entry.$2.add(const Duration(hours: 1)).millisecondsSinceEpoch,
      )).toList();

      String contextFor(String prompt) =>
          AiTodoContextBuilder.buildContextInjection(
            userMessage: prompt,
            courses: const [],
            timeLogs: timeLogs,
            conflicts: const [],
            teams: const [],
            now: now,
          )!;
      String previewFor(String prompt) =>
          AiTodoContextBuilder.buildContextInjectionSummary(
            userMessage: prompt,
            courses: const [],
            timeLogs: timeLogs,
            conflicts: const [],
            teams: const [],
            now: now,
          )!;

      final explicitDay = contextFor('分析2025年9月1日效率');
      expect(explicitDay, contains('2025-09-01合计'));
      expect(explicitDay, contains('last-year-september-first'));
      expect(explicitDay, isNot(contains('last-year-september-last')));
      expect(previewFor('分析2025年9月1日效率'), contains('专注记录20250901'));

      final relativeDay = contextFor('分析去年9月1日效率');
      expect(relativeDay, contains('last-year-september-first'));
      expect(relativeDay, isNot(contains('last-year-september-last')));

      final monthDay = contextFor('分析10月1日效率');
      expect(monthDay, contains('2026-10-01合计'));
      expect(monthDay, contains('current-october-first'));
      expect(monthDay, isNot(contains('today')));
      expect(monthDay, isNot(contains('future')));
      expect(previewFor('分析10月1日效率'), contains('专注记录20261001'));
    });
    test('前后相对日效率范围只筛选对应自然日', () {
      final now = DateTime(2026, 10, 2, 12);
      final cases = [
        ('大前天', DateTime(2026, 9, 29), '大前天'),
        ('前天', DateTime(2026, 9, 30), '前天'),
        ('昨天', DateTime(2026, 10, 1), '昨日'),
        ('今天', DateTime(2026, 10, 2), '今日'),
        ('明天', DateTime(2026, 10, 3), '明天'),
        ('后天', DateTime(2026, 10, 4), '后天'),
        ('大后天', DateTime(2026, 10, 5), '大后天'),
      ];
      final timeLogs = [
        for (final (phrase, date, _) in cases)
          TimeLogItem(
            id: 'log-$phrase',
            title: phrase,
            startTime: DateTime(date.year, date.month, date.day, 9)
                .millisecondsSinceEpoch,
            endTime: DateTime(date.year, date.month, date.day, 10)
                .millisecondsSinceEpoch,
          ),
      ];

      for (final (phrase, date, label) in cases) {
        final prompt = '分析$phrase的效率';
        final context = AiTodoContextBuilder.buildContextInjection(
          userMessage: prompt,
          courses: const [],
          timeLogs: timeLogs,
          conflicts: const [],
          teams: const [],
          now: now,
        )!;
        final preview = AiTodoContextBuilder.buildContextInjectionSummary(
          userMessage: prompt,
          courses: const [],
          timeLogs: timeLogs,
          conflicts: const [],
          teams: const [],
          now: now,
        )!;

        expect(context, contains('$label合计'), reason: prompt);
        expect(context, contains('log-$phrase'), reason: prompt);
        for (final (otherPhrase, _, _) in cases.where(
          (item) => item.$1 != phrase,
        )) {
          expect(context, isNot(contains('log-$otherPhrase')), reason: prompt);
        }
        final month = date.month.toString().padLeft(2, '0');
        final day = date.day.toString().padLeft(2, '0');
        final dateKey = '${date.year}$month$day';
        expect(preview, contains('专注记录$dateKey'), reason: prompt);
      }
    });
    test('上上周和上上个月效率范围不会匹配上一期', () {
      final now = DateTime(2026, 10, 2, 12);
      final timeLogs = [
        ('two-months-prior', DateTime(2026, 8, 31, 9)),
        ('last-month', DateTime(2026, 9, 30, 9)),
        ('two-weeks-prior', DateTime(2026, 9, 18, 9)),
        ('last-week', DateTime(2026, 9, 25, 9)),
        ('this-week', DateTime(2026, 9, 29, 9)),
      ].map((entry) => TimeLogItem(
        id: entry.$1,
        title: entry.$1,
        startTime: entry.$2.millisecondsSinceEpoch,
        endTime: entry.$2.add(const Duration(hours: 1)).millisecondsSinceEpoch,
      )).toList();

      String contextFor(String prompt) =>
          AiTodoContextBuilder.buildContextInjection(
            userMessage: prompt,
            courses: const [],
            timeLogs: timeLogs,
            conflicts: const [],
            teams: const [],
            now: now,
          )!;
      String previewFor(String prompt) =>
          AiTodoContextBuilder.buildContextInjectionSummary(
            userMessage: prompt,
            courses: const [],
            timeLogs: timeLogs,
            conflicts: const [],
            teams: const [],
            now: now,
          )!;

      final twoMonths = contextFor('分析上上个月效率');
      expect(twoMonths, contains('上上个月合计'));
      expect(twoMonths, contains('two-months-prior'));
      expect(twoMonths, isNot(contains('last-month')));
      expect(
        previewFor('分析上上个月效率'),
        contains('专注记录20260801-20260831'),
      );

      final twoWeeks = contextFor('分析上上周效率');
      expect(twoWeeks, contains('上上周合计'));
      expect(twoWeeks, contains('two-weeks-prior'));
      expect(twoWeeks, isNot(contains('last-week')));
      expect(twoWeeks, isNot(contains('this-week')));
      expect(
        previewFor('分析上上周效率'),
        contains('专注记录20260914-20260920'),
      );
    });

  });
}
