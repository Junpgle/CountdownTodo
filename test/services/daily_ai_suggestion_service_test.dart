import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:countdown_todo/models.dart';
import 'package:countdown_todo/services/daily_ai_suggestion_service.dart';
import 'package:countdown_todo/services/pomodoro_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('isEnabled defaults to false and persists per user', () async {
    expect(await DailyAiSuggestionService.isEnabled('alice'), isFalse);

    await DailyAiSuggestionService.setEnabled('alice', true);
    expect(await DailyAiSuggestionService.isEnabled('alice'), isTrue);
    expect(await DailyAiSuggestionService.isEnabled('bob'), isFalse);
  });

  test('buildPromptMessages includes today context and avoids completed todos', () {
    final now = DateTime(2026, 11, 15, 9, 30);
    final todos = [
      TodoItem(
        id: 'todo-overdue',
        title: '提交实验报告',
        dueDate: DateTime(2026, 11, 14, 23, 59),
      ),
      TodoItem(
        id: 'todo-today',
        title: '复习高数第三章',
        dueDate: DateTime(2026, 11, 15, 20, 0),
      ),
      TodoItem(
        id: 'todo-done',
        title: '已完成事项',
        isDone: true,
        dueDate: DateTime(2026, 11, 15, 10, 0),
      ),
    ];
    final countdowns = [
      CountdownItem(
        id: 'cd-1',
        title: '期末考试',
        targetDate: DateTime(2026, 11, 20),
      ),
    ];
    final schedules = [
      FixedScheduleItem(
        id: 'fs-1',
        title: '项目周会',
        date: '2026-11-15',
        startTime: DateTime(2026, 11, 15, 14, 0).millisecondsSinceEpoch,
        endTime: DateTime(2026, 11, 15, 15, 0).millisecondsSinceEpoch,
      ),
    ];

    final messages = DailyAiSuggestionService.buildPromptMessages(
      now: now,
      todos: todos,
      countdowns: countdowns,
      planBlocks: const [],
      fixedSchedules: schedules,
      courses: const [],
    );

    expect(messages.length, 2);
    final userContent = messages[1]['content'] as String;
    expect(userContent, contains('提交实验报告'));
    expect(userContent, contains('复习高数第三章'));
    expect(userContent, isNot(contains('已完成事项')));
    expect(userContent, contains('项目周会'));
    expect(userContent, contains('期末考试'));
  });

  test('parseAiResponse handles fenced JSON and plain text fallback', () {
    const fenced = '''```json
{
  "summary": "今天优先清理逾期报告并推进高数复习。",
  "items": [
    {
      "title": "提交实验报告",
      "reason": "已逾期，建议上午优先完成",
      "priority": "high",
      "todoId": "todo-overdue"
    }
  ]
}
```''';

    final parsed = DailyAiSuggestionService.parseAiResponse(
      fenced,
      dateKey: '2026-11-15',
      generatedAtMs: 123456,
    );
    expect(parsed.summary, '今天优先清理逾期报告并推进高数复习。');
    expect(parsed.items.length, 1);
    expect(parsed.items.first.priority, DailyAiSuggestionPriority.high);
    expect(parsed.items.first.todoId, 'todo-overdue');

    final fallback = DailyAiSuggestionService.parseAiResponse(
      '今天先专心完成手头最重要的任务。',
      dateKey: '2026-11-15',
      generatedAtMs: 123456,
    );
    expect(fallback.summary, '今天先专心完成手头最重要的任务。');
    expect(fallback.items, isEmpty);
  });

  test('ensureTodaySuggestion runs once per day and regenerates on next day', () async {
    await DailyAiSuggestionService.setEnabled('alice', true);

    Future<({String model, String apiKey, String apiUrl, String provider})?>
    fakeConfigResolver() async => (
      model: 'glm-4-flash',
      apiKey: 'test-key',
      apiUrl: 'https://example.com/v1/chat/completions',
      provider: 'zhipu',
    );

    var callCount = 0;
    Future<String> fakeCompleter({
      required String apiUrl,
      required String apiKey,
      required String model,
      required List<Map<String, dynamic>> messages,
      String provider = 'zhipu',
      double temperature = 0.5,
      int maxTokens = 30,
      Duration timeout = const Duration(seconds: 10),
      String usageOperation = 'title',
    }) async {
      callCount++;
      return '{"summary":"第$callCount次建议","items":[{"title":"完成核心任务","reason":"上午效率最高","priority":"high"}]}';
    }

    final day1Morning = DateTime(2026, 11, 15, 8, 0);
    final first = await DailyAiSuggestionService.ensureTodaySuggestion(
      username: 'alice',
      todos: const [],
      countdowns: const [],
      planBlocks: const [],
      fixedSchedules: const [],
      courses: const [],
      now: day1Morning,
      completer: fakeCompleter,
      configResolver: fakeConfigResolver,
    );
    expect(callCount, 1);
    expect(first.suggestion?.summary, '第1次建议');
    expect(first.shouldShowOnDashboard, isTrue);

    // Same day later: should hit cache, not call AI again.
    final day1Evening = DateTime(2026, 11, 15, 20, 0);
    final second = await DailyAiSuggestionService.ensureTodaySuggestion(
      username: 'alice',
      todos: const [],
      countdowns: const [],
      planBlocks: const [],
      fixedSchedules: const [],
      courses: const [],
      now: day1Evening,
      completer: fakeCompleter,
      configResolver: fakeConfigResolver,
    );
    expect(callCount, 1);
    expect(second.suggestion?.summary, '第1次建议');

    // Dismiss for today: should hide on dashboard without re-calling AI.
    await DailyAiSuggestionService.dismissForToday('alice', now: day1Evening);
    final afterDismiss = await DailyAiSuggestionService.ensureTodaySuggestion(
      username: 'alice',
      todos: const [],
      countdowns: const [],
      planBlocks: const [],
      fixedSchedules: const [],
      courses: const [],
      now: day1Evening,
      completer: fakeCompleter,
      configResolver: fakeConfigResolver,
    );
    expect(callCount, 1);
    expect(afterDismiss.shouldShowOnDashboard, isFalse);

    // Force refresh on the same day: should re-call AI and re-show on dashboard.
    final refreshed = await DailyAiSuggestionService.ensureTodaySuggestion(
      username: 'alice',
      todos: const [],
      countdowns: const [],
      planBlocks: const [],
      fixedSchedules: const [],
      courses: const [],
      forceRefresh: true,
      now: day1Evening,
      completer: fakeCompleter,
      configResolver: fakeConfigResolver,
    );
    expect(callCount, 2);
    expect(refreshed.suggestion?.summary, '第2次建议');
    expect(refreshed.shouldShowOnDashboard, isTrue);

    // requestRegenerate clears cache so next sync also regenerates.
    await DailyAiSuggestionService.requestRegenerate('alice');
    final afterReset = await DailyAiSuggestionService.ensureTodaySuggestion(
      username: 'alice',
      todos: const [],
      countdowns: const [],
      planBlocks: const [],
      fixedSchedules: const [],
      courses: const [],
      now: day1Evening,
      completer: fakeCompleter,
      configResolver: fakeConfigResolver,
    );
    expect(callCount, 3);
    expect(afterReset.suggestion?.summary, '第3次建议');

    // Next day: should call AI again.
    final day2 = DateTime(2026, 11, 16, 8, 30);
    final third = await DailyAiSuggestionService.ensureTodaySuggestion(
      username: 'alice',
      todos: const [],
      countdowns: const [],
      planBlocks: const [],
      fixedSchedules: const [],
      courses: const [],
      now: day2,
      completer: fakeCompleter,
      configResolver: fakeConfigResolver,
    );
    expect(callCount, 4);
    expect(third.suggestion?.summary, '第4次建议');
    expect(third.shouldShowOnDashboard, isTrue);
  });

  test('shows first-open prompt when configured but disabled, until declined', () async {
    Future<({String model, String apiKey, String apiUrl, String provider})?>
    fakeConfigResolver() async => (
      model: 'glm-4-flash',
      apiKey: 'test-key',
      apiUrl: 'https://example.com/v1/chat/completions',
      provider: 'zhipu',
    );

    final initial = await DailyAiSuggestionService.ensureTodaySuggestion(
      username: 'alice',
      todos: const [],
      countdowns: const [],
      planBlocks: const [],
      fixedSchedules: const [],
      courses: const [],
      configResolver: fakeConfigResolver,
    );
    expect(initial.enabled, isFalse);
    expect(initial.showFirstOpenPrompt, isTrue);
    expect(initial.shouldShowOnDashboard, isTrue);

    await DailyAiSuggestionService.dismissFirstOpenPrompt('alice');
    final afterDecline = await DailyAiSuggestionService.ensureTodaySuggestion(
      username: 'alice',
      todos: const [],
      countdowns: const [],
      planBlocks: const [],
      fixedSchedules: const [],
      courses: const [],
      configResolver: fakeConfigResolver,
    );
    expect(afterDecline.showFirstOpenPrompt, isFalse);
    expect(afterDecline.shouldShowOnDashboard, isFalse);

    await DailyAiSuggestionService.setManualSectionKept('alice', true);
    final manual = await DailyAiSuggestionService.ensureTodaySuggestion(
      username: 'alice',
      todos: const [],
      countdowns: const [],
      planBlocks: const [],
      fixedSchedules: const [],
      courses: const [],
      configResolver: fakeConfigResolver,
    );
    expect(manual.enabled, isFalse);
    expect(manual.showManualGenerateCard, isTrue);
    expect(manual.shouldShowOnDashboard, isTrue);
  });

  test(
    'buildPromptMessages includes today pomodoros and time logs while filtering out other days',
    () {
      final now = DateTime(2026, 11, 15, 16, 0);
      final pomodoros = [
        PomodoroRecord(
          todoTitle: '高数刷题',
          startTime: DateTime(2026, 11, 15, 9, 0).millisecondsSinceEpoch,
          endTime: DateTime(2026, 11, 15, 9, 25).millisecondsSinceEpoch,
          plannedDuration: 25 * 60,
          actualDuration: 25 * 60,
          status: PomodoroRecordStatus.completed,
          note: '完成微积分',
        ),
        PomodoroRecord(
          todoTitle: '昨日专注',
          startTime: DateTime(2026, 11, 14, 21, 0).millisecondsSinceEpoch,
          endTime: DateTime(2026, 11, 14, 21, 25).millisecondsSinceEpoch,
          plannedDuration: 25 * 60,
          actualDuration: 25 * 60,
        ),
        PomodoroRecord(
          todoTitle: '已删除专注',
          startTime: DateTime(2026, 11, 15, 10, 0).millisecondsSinceEpoch,
          endTime: DateTime(2026, 11, 15, 10, 25).millisecondsSinceEpoch,
          plannedDuration: 25 * 60,
          isDeleted: true,
        ),
      ];
      final timeLogs = [
        TimeLogItem(
          title: '文献阅读',
          startTime: DateTime(2026, 11, 15, 14, 0).millisecondsSinceEpoch,
          endTime: DateTime(2026, 11, 15, 15, 0).millisecondsSinceEpoch,
          remark: '读完两篇论文',
        ),
        TimeLogItem(
          title: '昨日日志',
          startTime: DateTime(2026, 11, 14, 14, 0).millisecondsSinceEpoch,
          endTime: DateTime(2026, 11, 14, 15, 0).millisecondsSinceEpoch,
        ),
        TimeLogItem(
          title: '已删除日志',
          startTime: DateTime(2026, 11, 15, 11, 0).millisecondsSinceEpoch,
          endTime: DateTime(2026, 11, 15, 11, 30).millisecondsSinceEpoch,
          isDeleted: true,
        ),
      ];

      final messages = DailyAiSuggestionService.buildPromptMessages(
        now: now,
        todos: const [],
        countdowns: const [],
        planBlocks: const [],
        fixedSchedules: const [],
        courses: const [],
        todayPomodoroRecords: pomodoros,
        todayTimeLogs: timeLogs,
      );

      final userContent = messages[1]['content'] as String;
      expect(userContent, contains('【今日番茄钟专注记录（共1次，完成1次，累计25分钟）】'));
      expect(userContent, contains('高数刷题 (25分钟, 已完成 | 备注:完成微积分)'));
      expect(userContent, isNot(contains('昨日专注')));
      expect(userContent, isNot(contains('已删除专注')));

      expect(userContent, contains('【今日时间日志（共1条，累计60分钟）】'));
      expect(userContent, contains('文献阅读 (60分钟 | 备注:读完两篇论文)'));
      expect(userContent, isNot(contains('昨日日志')));
      expect(userContent, isNot(contains('已删除日志')));
    },
  );

  test(
    'buildPromptMessages includes counts, done todos, plan status, free slots, rhythm, and extra blocks',
    () {
      final now = DateTime(2026, 11, 15, 16, 0);
      final todos = [
        for (var i = 1; i <= 10; i++)
          TodoItem(
            id: 'overdue-$i',
            title: '逾期任务$i',
            dueDate: DateTime(2026, 11, 14, 10, 0),
          ),
        TodoItem(
          id: 'done-today',
          title: '今天已完成的报告',
          isDone: true,
          completedAt: DateTime(2026, 11, 15, 11, 0).millisecondsSinceEpoch,
        ),
        TodoItem(
          id: 'done-yesterday',
          title: '昨天完成的任务',
          isDone: true,
          completedAt: DateTime(2026, 11, 14, 15, 0).millisecondsSinceEpoch,
        ),
      ];
      final planBlocks = [
        TodoPlanBlock(
          id: 'pb-1',
          todoId: 'overdue-1',
          titleSnapshot: '处理逾期任务1',
          startTime: DateTime(2026, 11, 15, 17, 0).millisecondsSinceEpoch,
          endTime: DateTime(2026, 11, 15, 18, 0).millisecondsSinceEpoch,
          status: TodoPlanStatus.planned,
        ),
      ];
      final courses = [
        CourseItem(
          courseName: '机器学习',
          roomName: 'A101',
          teacherName: '张老师',
          weekIndex: 10,
          weekday: 1,
          date: '2026-11-16',
          startTime: DateTime(2026, 11, 16, 8, 30).millisecondsSinceEpoch,
          endTime: DateTime(2026, 11, 16, 10, 0).millisecondsSinceEpoch,
        ),
      ];
      final yesterdayPomodoros = [
        PomodoroRecord(
          todoTitle: '昨日深度专注',
          startTime: DateTime(2026, 11, 14, 20, 0).millisecondsSinceEpoch,
          endTime: DateTime(2026, 11, 14, 20, 45).millisecondsSinceEpoch,
          plannedDuration: 45 * 60,
          actualDuration: 45 * 60,
        ),
      ];

      final messages = DailyAiSuggestionService.buildPromptMessages(
        now: now,
        todos: todos,
        countdowns: const [],
        planBlocks: planBlocks,
        fixedSchedules: const [],
        courses: courses,
        yesterdayPomodoroRecords: yesterdayPomodoros,
        habitSummaryBlock: '【今日习惯打卡（共1项）】\n- 💧 喝水：进行中(50%)',
        challengeSummaryBlock: '【30天挑战】《早睡挑战》已完成 3/30，今日尚未打卡。',
        recentFeedbackBlock: '【近期建议反馈】\n- 2026-11-14：已采纳加入待办：整理笔记',
        isManualRefresh: true,
      );

      final userContent = messages[1]['content'] as String;
      expect(userContent, contains('用户手动刷新/重新评估'));
      expect(userContent, contains('【已逾期未完成待办（共10条，仅展示前8条）】'));
      expect(userContent, contains('【今日已完成待办（共1条）】'));
      expect(userContent, contains('今天已完成的报告'));
      expect(userContent, contains('规划 17:00-18:00 处理逾期任务1 (待执行 | todoId:overdue-1)'));
      expect(userContent, contains('【今日剩余可用空档（至23:00）】'));
      expect(userContent, contains('16:00-17:00 (60分钟)'));
      expect(userContent, contains('18:00-23:00 (300分钟)'));
      expect(userContent, contains('昨日完成待办：1 项'));
      expect(userContent, contains('昨日番茄专注：1 次，累计 45 分钟'));
      expect(userContent, contains('明早08:30 课程:机器学习'));
      expect(userContent, contains('【今日习惯打卡（共1项）】'));
      expect(userContent, contains('【30天挑战】'));
      expect(userContent, contains('【近期建议反馈】'));
    },
  );

  test(
    'archives previous day suggestion feedback into recentFeedbackBlock on next day',
    () async {
      await DailyAiSuggestionService.setEnabled('alice', true);
      Future<({String model, String apiKey, String apiUrl, String provider})?>
      fakeConfigResolver() async => (
        model: 'glm-4-flash',
        apiKey: 'test-key',
        apiUrl: 'https://example.com/v1/chat/completions',
        provider: 'zhipu',
      );
      Future<String> fakeCompleter({
        required String apiUrl,
        required String apiKey,
        required String model,
        required List<Map<String, dynamic>> messages,
        String provider = 'zhipu',
        double temperature = 0.5,
        int maxTokens = 30,
        Duration timeout = const Duration(seconds: 10),
        String usageOperation = 'title',
      }) async =>
          '{"summary":"今日重点","items":[{"title":"写周报","reason":"截止","priority":"high"},{"title":"整理桌面","reason":"顺手","priority":"low"}]}';

      final day1 = DateTime(2026, 11, 15, 9, 0);
      await DailyAiSuggestionService.ensureTodaySuggestion(
        username: 'alice',
        todos: const [],
        countdowns: const [],
        planBlocks: const [],
        fixedSchedules: const [],
        courses: const [],
        now: day1,
        completer: fakeCompleter,
        configResolver: fakeConfigResolver,
      );
      await DailyAiSuggestionService.markItemAddedToTodo('alice', 0, now: day1);

      final day2 = DateTime(2026, 11, 16, 9, 0);
      await DailyAiSuggestionService.ensureTodaySuggestion(
        username: 'alice',
        todos: const [],
        countdowns: const [],
        planBlocks: const [],
        fixedSchedules: const [],
        courses: const [],
        now: day2,
        completer: fakeCompleter,
        configResolver: fakeConfigResolver,
      );

      final feedback = await DailyAiSuggestionService.loadRecentFeedbackBlock(
        'alice',
      );
      expect(feedback, contains('2026-11-15'));
      expect(feedback, contains('已采纳加入待办：写周报'));
      expect(feedback, contains('未采纳：整理桌面'));
    },
  );

  test(
    'context options default to all enabled, persist per user, and gate sections/loaders',
    () async {
      final defaultConfig = await DailyAiSuggestionService.loadContextConfig(
        'alice',
      );
      expect(
        defaultConfig.enabledCount,
        DailyAiContextOption.values.length,
      );

      await DailyAiSuggestionService.setContextOption(
        'alice',
        DailyAiContextOption.pomodoro,
        false,
      );
      await DailyAiSuggestionService.setContextOption(
        'alice',
        DailyAiContextOption.habits,
        false,
      );
      await DailyAiSuggestionService.setContextOption(
        'alice',
        DailyAiContextOption.freeSlots,
        false,
      );

      final aliceConfig = await DailyAiSuggestionService.loadContextConfig(
        'alice',
      );
      expect(aliceConfig.isEnabled(DailyAiContextOption.pomodoro), isFalse);
      expect(aliceConfig.isEnabled(DailyAiContextOption.habits), isFalse);
      expect(aliceConfig.isEnabled(DailyAiContextOption.freeSlots), isFalse);
      expect(aliceConfig.isEnabled(DailyAiContextOption.timeLogs), isTrue);

      final bobConfig = await DailyAiSuggestionService.loadContextConfig('bob');
      expect(bobConfig.enabledCount, DailyAiContextOption.values.length);

      await DailyAiSuggestionService.setEnabled('alice', true);
      var pomodoroLoaderCalled = false;
      var habitLoaderCalled = false;
      var timeLogLoaderCalled = false;
      String? capturedPrompt;

      await DailyAiSuggestionService.ensureTodaySuggestion(
        username: 'alice',
        todos: const [],
        countdowns: const [],
        planBlocks: const [],
        fixedSchedules: const [],
        courses: const [],
        now: DateTime(2026, 11, 15, 10, 0),
        loadTodayPomodoroRecords: () async {
          pomodoroLoaderCalled = true;
          return const [];
        },
        loadHabitSummary: (_) async {
          habitLoaderCalled = true;
          return '【今日习惯打卡】\n- 喝水';
        },
        loadTodayTimeLogs: () async {
          timeLogLoaderCalled = true;
          return [
            TimeLogItem(
              title: '阅读',
              startTime: DateTime(2026, 11, 15, 9, 0).millisecondsSinceEpoch,
              endTime: DateTime(2026, 11, 15, 9, 30).millisecondsSinceEpoch,
            ),
          ];
        },
        configResolver: () async => (
          model: 'glm-4-flash',
          apiKey: 'test-key',
          apiUrl: 'https://example.com/v1/chat/completions',
          provider: 'zhipu',
        ),
        completer: ({
          required String apiUrl,
          required String apiKey,
          required String model,
          required List<Map<String, dynamic>> messages,
          String provider = 'zhipu',
          double temperature = 0.5,
          int maxTokens = 30,
          Duration timeout = const Duration(seconds: 10),
          String usageOperation = 'title',
        }) async {
          capturedPrompt = messages[1]['content'] as String;
          return '{"summary":"ok","items":[{"title":"t","reason":"r","priority":"medium"}]}';
        },
      );

      expect(pomodoroLoaderCalled, isFalse);
      expect(habitLoaderCalled, isFalse);
      expect(timeLogLoaderCalled, isTrue);
      expect(capturedPrompt, contains('【今日时间日志'));
      expect(capturedPrompt, isNot(contains('【今日剩余可用空档')));
      expect(capturedPrompt, isNot(contains('【今日习惯打卡')));
    },
  );
}
