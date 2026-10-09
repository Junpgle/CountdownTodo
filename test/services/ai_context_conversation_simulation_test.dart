import 'package:countdown_todo/features/finance/services/finance_ai_context_service.dart';
import 'package:countdown_todo/features/habits/services/habit_ai_context_service.dart';
import 'package:countdown_todo/models/chat_message.dart';
import 'package:countdown_todo/models.dart';
import 'package:countdown_todo/services/ai_chat_history_window.dart';
import 'package:countdown_todo/services/ai_native_tool_definition_builder.dart';
import 'package:countdown_todo/services/ai_todo_context_builder.dart';
import 'package:flutter_test/flutter_test.dart';

typedef SimulatedTurn = ({
  String domain,
  String previousUserMessage,
  String userMessage,
});

void main() {
  final now = DateTime(2026, 10, 1, 12);
  final todos = [
    {
      'id': 'todo-thursday',
      'title': '提交报告',
      'dueDate': DateTime(2026, 10, 1, 18).toIso8601String(),
      'timeMode': 'deadline',
    },
    {
      'id': 'todo-friday',
      'title': '复习数据结构',
      'dueDate': DateTime(2026, 10, 2, 18).toIso8601String(),
      'timeMode': 'deadline',
    },
  ];
  final courses = [
    CourseItem(
      uuid: 'course-friday',
      courseName: '数据结构',
      teacherName: '王老师',
      date: '2026-10-02',
      weekday: DateTime.friday,
      startTime: 900,
      endTime: 950,
      weekIndex: 1,
      roomName: 'A101',
    ),
    CourseItem(
      uuid: 'course-monday',
      courseName: '英语',
      teacherName: '李老师',
      date: '2026-10-05',
      weekday: DateTime.monday,
      startTime: 1000,
      endTime: 1050,
      weekIndex: 2,
      roomName: 'B202',
    ),
  ];
  final schedules = [
    FixedScheduleItem(
      id: 'schedule-friday',
      title: '项目例会',
      date: '2026-10-02',
      startTime: DateTime(2026, 10, 2, 14).millisecondsSinceEpoch,
      endTime: DateTime(2026, 10, 2, 15).millisecondsSinceEpoch,
    ),
    FixedScheduleItem(
      id: 'schedule-monday',
      title: '复诊预约',
      date: '2026-10-05',
      startTime: DateTime(2026, 10, 5, 10).millisecondsSinceEpoch,
      endTime: DateTime(2026, 10, 5, 11).millisecondsSinceEpoch,
    ),
  ];
  final plans = [
    TodoPlanBlock(
      id: 'plan-friday',
      todoId: 'todo-friday',
      titleSnapshot: '复习数据结构',
      startTime: DateTime(2026, 10, 2, 9).millisecondsSinceEpoch,
      endTime: DateTime(2026, 10, 2, 10).millisecondsSinceEpoch,
      plannedMinutes: 60,
    ),
    TodoPlanBlock(
      id: 'plan-monday',
      todoId: 'todo-thursday',
      titleSnapshot: '提交报告',
      startTime: DateTime(2026, 10, 5, 9).millisecondsSinceEpoch,
      endTime: DateTime(2026, 10, 5, 10).millisecondsSinceEpoch,
      plannedMinutes: 60,
    ),
  ];
  final timeLogs = [
    TimeLogItem(
      id: 'focus-yesterday',
      title: '阅读论文',
      startTime: DateTime(2026, 9, 30, 19).millisecondsSinceEpoch,
      endTime: DateTime(2026, 9, 30, 20).millisecondsSinceEpoch,
    ),
    TimeLogItem(
      id: 'focus-today',
      title: '写报告',
      startTime: DateTime(2026, 10, 1, 9).millisecondsSinceEpoch,
      endTime: DateTime(2026, 10, 1, 10).millisecondsSinceEpoch,
    ),
  ];
  final countdowns = [
    CountdownItem(
      id: 'countdown-tomorrow',
      title: '项目提交',
      targetDate: DateTime(2026, 10, 2, 12),
    ),
    CountdownItem(
      id: 'countdown-monday',
      title: '旅行出发',
      targetDate: DateTime(2026, 10, 5, 8),
    ),
  ];

  String? inject(String userMessage, String previousUserMessage) {
    return AiTodoContextBuilder.buildContextInjection(
      userMessage: userMessage,
      previousUserMessage: previousUserMessage,
      courses: courses,
      timeLogs: timeLogs,
      planBlocks: plans,
      todos: todos,
      countdowns: countdowns,
      fixedSchedules: schedules,
      conflicts: const [],
      teams: const [],
      now: now,
    );
  }

  List<SimulatedTurn> turns(String domain, List<(String, String)> pairs) => [
    for (final pair in pairs)
      (domain: domain, previousUserMessage: pair.$1, userMessage: pair.$2),
  ];

  test('100组离线对话模拟覆盖五类上下文和多轮续问', () {
    final scenarios = <SimulatedTurn>[
      ...turns('finance', [
        ('', '本月账单明细有多少？'),
        ('', '查看今天消费情况'),
        ('', '统计本周收入'),
        ('', '分析昨天支出'),
        ('', '看看去年收入趋势'),
        ('', '预算余额多少？'),
        ('', '列出退款明细'),
        ('', '看看最近30天账单'),
        ('', '查看2026年9月账单'),
        ('', '消费占比怎么样？'),
        ('查看上月账单明细', '餐饮明细呢？'),
        ('查看上月账单明细', '商家排行呢？'),
        ('查看上月账单明细', '微信支付呢？'),
        ('查看上月账单明细', '按类别拆开呢？'),
        ('查看上月账单明细', '只看退款情况呢？'),
        ('查看上月账单明细', '那本周呢？'),
        ('查看上月账单明细', '那最近30天呢？'),
        ('查看上月账单明细', '这个月呢？'),
        ('查看上月账单明细', '再看看收入呢？'),
        ('查看上月账单明细', '还有哪些消费？'),
      ]),
      ...turns('habit', [
        ('', '查看今日习惯打卡进度'),
        ('', '本周习惯养成情况'),
        ('', '看看喝水习惯的完成率'),
        ('', '昨天的运动打卡如何？'),
        ('', '习惯目标完成得怎么样？'),
        ('', '统计本月坚持情况'),
        ('', '查看2026-09-20习惯进度'),
        ('', '习惯最近表现如何？'),
        ('', '跑步习惯完成率多少？'),
        ('', '总结今年的习惯打卡'),
        ('查看2026-09-20习惯进度', '那进度呢？'),
        ('查看2026-09-20习惯进度', '完成率怎么样？'),
        ('查看2026-09-20习惯进度', '喝水打卡如何？'),
        ('查看2026-09-20习惯进度', '那目标情况呢？'),
        ('查看2026-09-20习惯进度', '上个月呢？'),
        ('查看2026-09-20习惯进度', '那昨天的进度呢？'),
        ('查看2026-09-20习惯进度', '那2026-09-20呢？'),
        ('查看2026-09-20习惯进度', '还剩几天呢？'),
        ('查看2026-09-20习惯进度', '最近的习惯表现呢？'),
        ('查看2026-09-20习惯进度', '那打卡情况怎么样？'),
      ]),
      ...turns('todo', [
        ('', '今天有哪些待办？'),
        ('', '列出待办清单'),
        ('', '明天有没有任务？'),
        ('', '把待办延期到周五'),
        ('', '删除这个待办'),
        ('', '完成任务'),
        ('', '帮我把任务改到明天'),
        ('', '规划今天的待办'),
        ('', '把这个待办分到工作'),
        ('', '合并这两个待办'),
        ('今天有哪些待办？', '把第二个改到明天'),
        ('今天有哪些待办？', '把它延到周五'),
        ('今天有哪些待办？', '删掉刚才那项'),
        ('今天有哪些待办？', '第二个的截止时间是什么？'),
        ('今天有哪些待办？', '它呢？'),
        ('今天有哪些待办？', '那一项'),
        ('今天有哪些待办？', '刚才那个的标题呢？'),
        ('今天有哪些待办？', '这个任务的日期呢？'),
        ('今天有哪些待办？', '还有哪些没做？'),
        ('今天有哪些待办？', '把它往后推'),
      ]),
      ...turns('planning', [
        ('', '帮我规划今天的学习时间'),
        ('', '帮我规划周五的学习时间'),
        ('', '帮我安排明天的待办时间'),
        ('', '接下来一周怎么排时间？'),
        ('', '给我做本周计划'),
        ('', '把今天的待办排进时间块'),
        ('', '帮我规划明天上午的任务'),
        ('', '未来7天安排学习计划'),
        ('', '周五下午帮我规划一下时间'),
        ('', '本周课程怎么避开会议安排时间？'),
        ('帮我规划今天的学习时间', '那周五呢？'),
        ('帮我规划今天的学习时间', '那个周五的课程呢？'),
        ('帮我规划今天的学习时间', '那下周五也这样排呢？'),
        ('帮我规划今天的学习时间', '那星期五可以吗？'),
        ('帮我规划今天的学习时间', '那下周五避开会议呢？'),
        ('帮我规划今天的学习时间', '本周五呢？'),
        ('帮我规划今天的学习时间', '礼拜五也一样呢？'),
        ('帮我规划今天的学习时间', '下礼拜五的安排呢？'),
        ('帮我规划今天的学习时间', '那明天上午呢？'),
        ('帮我规划今天的学习时间', '还有周五呢？'),
      ]),
      ...turns('activity', [
        ('', '查看今天的专注记录'),
        ('', '查看番茄记录'),
        ('', '统计本周专注时长'),
        ('', '昨天专注了多久？'),
        ('', '展示我的时间日志'),
        ('', '查看明天的倒计时'),
        ('', '下周有哪些倒数日？'),
        ('', '还有几天到项目截止？'),
        ('', '看看最近的倒计时'),
        ('', '列出今天的倒计时'),
        ('查看今天的专注记录', '那昨天呢？'),
        ('查看今天的专注记录', '那本周呢？'),
        ('查看今天的专注记录', '这个专注时长呢？'),
        ('查看今天的专注记录', '前天的呢？'),
        ('查看今天的专注记录', '还有呢？'),
        ('查看倒计时', '那明天呢？'),
        ('查看倒计时', '那个呢？'),
        ('查看倒计时', '那后天呢？'),
        ('查看倒计时', '还有哪一个？'),
        ('查看倒计时', '那今天呢？'),
      ]),
    ];

    expect(scenarios, hasLength(100));
    for (final scenario in scenarios) {
      final contextText = [
        scenario.previousUserMessage,
        scenario.userMessage,
      ].join('\n');
      switch (scenario.domain) {
        case 'finance':
          expect(
            FinanceAiContextService.shouldInjectFor(
              scenario.userMessage,
              conversationContext: scenario.previousUserMessage,
            ),
            isTrue,
            reason: scenario.userMessage,
          );
          expect(
            FinanceAiContextService.buildContextInjectionSummary(
              userMessage: scenario.userMessage,
              conversationContext: contextText,
              previousUserMessage: scenario.previousUserMessage,
              now: now,
            ),
            contains('记账明细'),
            reason: scenario.userMessage,
          );
        case 'habit':
          expect(
            HabitAiContextService.buildContextInjectionSummary(
              userMessage: scenario.userMessage,
              conversationContext: contextText,
              previousUserMessage: scenario.previousUserMessage,
              goals: const [],
              now: now,
            ),
            contains('习惯数据'),
            reason: scenario.userMessage,
          );
        case 'todo':
          expect(
            inject(scenario.userMessage, scenario.previousUserMessage),
            contains('[期次todoId:'),
            reason: scenario.userMessage,
          );
        case 'planning':
          final injection = inject(
            scenario.userMessage,
            scenario.previousUserMessage,
          );
          expect(injection, contains('课程表'), reason: scenario.userMessage);
          expect(injection, contains('固定日程'), reason: scenario.userMessage);
          expect(injection, contains('待办规划'), reason: scenario.userMessage);
        case 'activity':
          final injection = inject(
            scenario.userMessage,
            scenario.previousUserMessage,
          );
          if (scenario.previousUserMessage.contains('专注') ||
              scenario.userMessage.contains('专注') ||
              scenario.userMessage.contains('番茄') ||
              scenario.userMessage.contains('时间日志')) {
            expect(injection, contains('专注记录'), reason: scenario.userMessage);
          } else {
            expect(injection, contains('倒计时'), reason: scenario.userMessage);
          }
        default:
          fail('Unknown simulation domain: ${scenario.domain}');
      }
    }
  });

  test('待办续问保留真实ID，并提供原生待办操作工具', () {
    const previousUserMessage = '今天有哪些待办？';
    const userMessage = '把第二个改到明天';

    final injection = inject(userMessage, previousUserMessage);
    expect(injection, contains('todo-friday'));
    final prompt = AiTodoContextBuilder.buildActionProtocolPrompt(
      userMessage,
      previousUserMessage: previousUserMessage,
    );
    expect(prompt, contains('reschedule_todo'));
    final tools = AiNativeToolDefinitionBuilder.buildNativeToolDefinitions(
      userMessage,
      previousUserMessage: previousUserMessage,
    );
    expect(tools, isNotEmpty);
    expect(
      AiNativeToolDefinitionBuilder.allowedCdtActionNames(tools),
      contains('reschedule_todo'),
    );
  });

  test('纯文本新增账单提示使用确认卡且聊天确认不会入账', () {
    final prompt = AiTodoContextBuilder.buildActionProtocolPrompt(
      '帮我记一笔兼职收入90元',
    );

    expect(prompt, contains('[FINANCE_START]...[FINANCE_END]'));
    expect(prompt, contains('“待确认记账”卡片'));
    expect(prompt, contains('点击“编辑并保存”'));
    expect(prompt, contains('聊天中的“确认/确定”不会保存账单'));
  });

  test('周五续问将课程、固定日程和待办都限制到该日', () {
    final injection = inject('那周五呢？', '帮我规划今天的学习时间');

    expect(injection, contains('数据结构'));
    expect(injection, isNot(contains('英语')));
    expect(injection, contains('schedule-friday'));
    expect(injection, isNot(contains('schedule-monday')));
    expect(injection, contains('todo-friday'));
    expect(injection, isNot(contains('todo-thursday')));
  });

  test('显式未来课程范围超过30天时不截断', () {
    String dateText(DateTime date) => date.toIso8601String().substring(0, 10);

    CourseItem course(String id, DateTime date) => CourseItem(
      uuid: id,
      courseName: id,
      teacherName: '王老师',
      date: dateText(date),
      weekday: date.weekday,
      startTime: 900,
      endTime: 950,
      weekIndex: 1,
      roomName: 'A101',
    );

    for (final (rangeDays, query) in [
      (60, '未来60天课程安排'),
      (100, '未来100天课程安排'),
      (100, '未来一百天课程安排'),
      (105, '未来一百零五天课程安排'),
      (365, '未来三百六十五天课程安排'),
    ]) {
      final inRangeDate = now.add(Duration(days: rangeDays - 15));
      final rangeEnd = now.add(Duration(days: rangeDays));
      final injection = AiTodoContextBuilder.buildContextInjection(
        userMessage: query,
        courses: [
          course('course-in-range', inRangeDate),
          course('course-at-range-end', rangeEnd),
        ],
        timeLogs: const [],
        conflicts: const [],
        teams: const [],
        now: now,
      );

      expect(injection, contains('未来$rangeDays天范围'));
      expect(injection, contains('course-in-range'));
      expect(injection, isNot(contains('course-at-range-end')));
    }
  });

  test('滚动课程日期范围按用户指定天数筛选历史课程', () {
    String dateText(DateTime date) => date.toIso8601String().substring(0, 10);

    CourseItem course(String id, DateTime date) => CourseItem(
      uuid: id,
      courseName: id,
      teacherName: '王老师',
      date: dateText(date),
      weekday: date.weekday,
      startTime: 900,
      endTime: 950,
      weekIndex: 1,
      roomName: 'A101',
    );

    for (final (rangeDays, query) in [
      (14, '过去两周课程安排'),
      (21, '最近3星期课程安排'),
      (60, '最近60天课程安排'),
      (100, '过去100天课程安排'),
      (100, '最近一百天课程安排'),
      (105, '最近一百零五天课程安排'),
      (365, '过去三百六十五天课程安排'),
    ]) {
      final inRangeAgeDays = rangeDays > 15 ? rangeDays - 15 : rangeDays ~/ 2;
      final inRangeDate = now.subtract(Duration(days: inRangeAgeDays));
      final rangeStart = now.subtract(Duration(days: rangeDays));
      final injection = AiTodoContextBuilder.buildContextInjection(
        userMessage: query,
        courses: [
          course('course-in-range', inRangeDate),
          course('course-at-range-start', rangeStart),
        ],
        timeLogs: const [],
        conflicts: const [],
        teams: const [],
        now: now,
      );

      expect(injection, contains('最近$rangeDays天范围'));
      expect(injection, contains('course-in-range'));
      expect(injection, isNot(contains('course-at-range-start')));
    }
  });

  test('与习惯或账单相关的省略日期续问继承上一轮范围', () {
    final habit = HabitAiContextService.buildContextInjectionSummary(
      userMessage: '那完成率呢？',
      conversationContext: '查看2026-09-20习惯进度',
      previousUserMessage: '查看2026-09-20习惯进度',
      goals: const [],
      now: now,
    );
    final finance = FinanceAiContextService.buildContextInjectionSummary(
      userMessage: '餐饮明细呢？',
      conversationContext: '查看上月账单明细',
      previousUserMessage: '查看上月账单明细',
      now: now,
    );

    expect(habit, contains('2026-09-20'));
    expect(finance, contains('2026-09-01 至 2026-09-30'));
  });

  test('习惯上下文接受自定义日期范围而不是只取起始日', () {
    final habit = HabitAiContextService.buildContextInjectionSummary(
      userMessage: '分析习惯在自定义范围的完成率，2026-08-01 至 2026-10-31',
      goals: const [],
      now: now,
    );

    expect(habit, contains('2026-08-01 至 2026-10-31'));
  });

  test('长对话窗口保留重复首问', () {
    final messages = List.generate(16, (index) {
      return ChatMessage(
        id: 'message-$index',
        role: index.isEven ? ChatRole.user : ChatRole.assistant,
        content: index == 0 || index == 14
            ? '分析我上个月的效率'
            : '对话消息 $index',
      );
    });

    final window = AiChatHistoryWindow.selectRecentMessages(
      messages,
      maxContextMessages: 15,
    );

    expect(window.firstUserMessage.id, 'message-0');
    expect(window.recentMessages, hasLength(13));
    expect(
      window.recentMessages.any((message) => message.id == 'message-14'),
      isTrue,
    );
  });

  test('只读分析和待办列表查询不注入写操作协议', () {
    for (final query in [
      '分析我上个月的效率',
      '今天有哪些待办？',
      '有哪些已完成待办？',
      '哪些任务需要删除？',
      '有哪些待办？不要删除其中一条',
      '分析最近效率，不要补记专注记录',
      '明天有哪些固定日程？',
      '查看我的倒计时',
      '有哪些番茄标签？',
    ]) {
      final prompt = AiTodoContextBuilder.buildActionProtocolPrompt(query);

      expect(prompt, contains('本轮不生成结构化操作'), reason: query);
      expect(prompt, isNot(contains('create_todo')), reason: query);
      expect(prompt, isNot(contains('delete_todo')), reason: query);
      expect(prompt, isNot(contains('create_time_log')), reason: query);
      expect(prompt, isNot(contains('delete_time_log')), reason: query);
      expect(prompt, isNot(contains('start_pomodoro')), reason: query);
      expect(prompt, isNot(contains('create_schedule')), reason: query);
      expect(prompt, isNot(contains('delete_schedule')), reason: query);
      expect(prompt, isNot(contains('create_countdown')), reason: query);
      expect(prompt, isNot(contains('create_pomodoro_tag')), reason: query);
      expect(prompt, isNot(contains('update_finance')), reason: query);
      expect(prompt, isNot(contains('delete_finance')), reason: query);
    }

    final financeQuery = AiTodoContextBuilder.buildActionProtocolPrompt(
      '查询上月账单明细',
    );
    expect(financeQuery, contains('finance_summary / finance_list'));
    expect(financeQuery, isNot(contains('update_finance')));
    expect(financeQuery, isNot(contains('delete_finance')));

    final mixedRequest = AiTodoContextBuilder.buildActionProtocolPrompt(
      '查看待办并删除第一个',
    );
    expect(mixedRequest, contains('delete_todo'));
    final explicitFocusRequest = AiTodoContextBuilder.buildActionProtocolPrompt(
      '帮我补记一条专注记录',
    );
    expect(explicitFocusRequest, contains('create_time_log'));
    final explicitFocusLog = AiTodoContextBuilder.buildActionProtocolPrompt(
      '帮我记录这次专注25分钟',
    );
    expect(explicitFocusLog, contains('create_time_log'));
  });
}
