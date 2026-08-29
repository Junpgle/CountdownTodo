import 'package:intl/intl.dart';

import '../models.dart';
import 'chat_storage_service.dart';
import 'pomodoro_service.dart';

class AiTodoContextBuilder {
  static String buildLeanSystemPrompt({
    required String customPrompt,
    required bool promptEnabled,
    DateTime? now,
  }) {
    final nowValue = now ?? DateTime.now();
    final nowText =
        '${DateFormat('yyyy-MM-dd HH:mm').format(nowValue)} (${_formatTimeZone(nowValue)})';
    final basePrompt = promptEnabled && customPrompt.trim().isNotEmpty
        ? customPrompt
        : ChatStorageService.defaultPrompt;
    var resolvedBasePrompt = basePrompt
        .replaceAll('{now}', nowText)
        .replaceAll('{todos}', '待办将按需通过智能上下文注入');
    resolvedBasePrompt = _compactCapabilitySection(resolvedBasePrompt);
    return '''$resolvedBasePrompt

【时间规则】
所有上下文时间均为本地时间，格式为yyyy-MM-dd HH:mm。判断今天、昨天、明天时必须以当前基准时间和括号中的时区为准，不要按UTC重新换算。

【动作输出规则】
当用户明确要求管理待办、固定日程、规划块、专注记录、番茄钟、倒计时、标签或记账时，回复末尾必须附对应的结构化结果。待办等使用 [ACTION_START]...[ACTION_END] JSON 数组；记账使用 [FINANCE_START]...[FINANCE_END] JSON 数组。
每个操作对象必须包含 action 字段；禁止旧标记与 Markdown 代码块。
具体可用动作与字段约束会按当前问题动态提供。''';
  }

  static String _compactCapabilitySection(String text) {
    final pattern = RegExp(r'【你的能力】[\s\S]*?(?=\n【|$)');
    if (!pattern.hasMatch(text)) return text;
    return text.replaceFirst(
      pattern,
      '【你的能力】\n按本轮动作协议执行，仅保留当前问题相关能力。',
    );
  }

  static String buildActionProtocolPrompt(String userMessage) {
    final actions = <String>[];
    void add(String line) {
      if (!actions.contains(line)) actions.add(line);
    }

    final requestsTodoAction = _shouldInjectTodoContext(userMessage) ||
        _matchesAny(userMessage, _createTodoKeywords) ||
        _matchesAny(userMessage, _recurrenceKeywords) ||
        userMessage.contains('待办') ||
        userMessage.contains('任务');
    final requestsScheduleAction =
        _shouldInjectFixedScheduleContext(userMessage) ||
            _matchesAny(userMessage, _fixedScheduleKeywords);
    final requestsFinanceAction = _matchesAny(userMessage, _financeKeywords) ||
        userMessage.contains('#记账') ||
        userMessage.contains('账单');
    if (requestsTodoAction) {
      add(
        '- create_todo: {"action":"create_todo","todos":[{"title":"标题","remark":"备注","timeMode":"unscheduled|dateOnly|deadline","dueDate":null,"groupId":null,"reminderMinutes":5,"recurrence":"none|daily|weekly|monthly|yearly|weekdays|customDays","customIntervalDays":null,"recurrenceEndDate":null}]}',
      );
      add(
        '- update_todo / complete_todo / delete_todo / reschedule_todo / bulk_reschedule / categorize_todo: 必须带真实期次todoId；循环期次可带recurrenceSeriesId校验系列',
      );
      add(
        '- 循环作用域: recurrenceScope="occurrence"只操作该期（默认）；recurrenceScope="future"操作该期及以后。修改循环规则或结束循环必须用future；完成操作始终只针对一期',
      );
      add(
        '- split_todo / merge_todos / plan_todos: 拆分合并需 sourceTodoId/sourceTodoIds，规划需 todos[]。注意：plan_todos仅用于创建全新待办，把已有待办安排到时间必须用create_plan_block',
      );
    }
    if (requestsScheduleAction) {
      add(
        '- create_schedule: {"action":"create_schedule","schedules":[{"title":"日程名","date":"YYYY-MM-DD","startTime":"YYYY-MM-DD HH:mm或null","endTime":"YYYY-MM-DD HH:mm或null","location":null,"remark":null,"reminderMinutes":[15],"recurrence":"none|daily|weekly|monthly|yearly|weekdays|customDays","customIntervalDays":null,"recurrenceEndDate":null}]}',
      );
      add(
        '- update_schedule: {"action":"update_schedule","updates":[{"scheduleId":"真实期次ID","recurrenceSeriesId":"可选系列ID","recurrenceScope":"occurrence|future","title":"新标题","date":"YYYY-MM-DD","startTime":null,"endTime":null,"location":null,"remark":null,"reminderMinutes":[],"recurrence":"none|daily|weekly|monthly|yearly|weekdays|customDays","customIntervalDays":null,"recurrenceEndDate":null}]}。字段缺省=保持，null=清空；startTime=null同时清空结束时间，表示时间待定；修改重复规则必须使用future',
      );
      add(
        '- cancel_schedule / delete_schedule: 必须带scheduleId；默认只操作本期，只有用户明确说本期及以后时才用recurrenceScope="future"',
      );
    }
    if (requestsFinanceAction) {
      add(
        '- 记账草案：回复正文末尾追加 [FINANCE_START]...[FINANCE_END]，其中必须是JSON数组；每笔使用 {"type":"expense|income|refund","amount":28.50,"category":"餐饮","merchant":"午餐","date":"YYYY-MM-DD","paymentMethod":"微信","note":"备注"}，金额单位为元，缺失的可选字段用null；只生成草案，不要声称已保存',
      );
      add(
        '- 记账与取餐码双识别：同一条消息同时包含账单和取餐/取件信息时，两者都保留，记账放FINANCE块，取餐放ACTION块，禁止二选一',
      );
      add(
        '- 只记账时不要为了凑协议生成空的ACTION块；FINANCE块独立于ACTION块，账单只作为待确认草案，不要声称已保存',
      );
    }
    if (_matchesAny(userMessage, _planKeywords) ||
        _matchesAny(userMessage, _planningKeywords)) {
      add(
        '- create_plan_block: {"action":"create_plan_block","blocks":[{"todoId":"已有待办ID","startTime":"YYYY-MM-DD HH:mm","dueDate":"YYYY-MM-DD HH:mm","durationMinutes":60,"reminderMinutes":5}]}',
      );
      add('- update/delete/reschedule/skip/start_plan_block_*: 必须带 planBlockId');
    }
    if (_matchesAny(userMessage, _timeLogKeywords) ||
        _looksLikeFocusQuery(userMessage)) {
      add(
        '- create_time_log: {"action":"create_time_log","logs":[{"title":"专注内容","startTime":"YYYY-MM-DD HH:mm","dueDate":"YYYY-MM-DD HH:mm","durationMinutes":60,"remark":"备注","tagUuids":[]}]}',
      );
      add(
        '- update_time_log: {"action":"update_time_log","updates":[{"logId":"日志ID","title":"新标题","startTime":"YYYY-MM-DD HH:mm","dueDate":"YYYY-MM-DD HH:mm","durationMinutes":60,"remark":"备注","tagUuids":[]}]}',
      );
      add(
        '- delete_time_log: {"action":"delete_time_log","updates":[{"logId":"日志ID"}]}',
      );
      add(
        '- start_pomodoro: {"action":"start_pomodoro","title":"专注内容","todoId":"可选待办ID","durationMinutes":25,"tagUuids":[]}',
      );
      add('- stop_pomodoro: {"action":"stop_pomodoro","status":"completed"}');
    }
    if (_matchesAny(userMessage, _countdownKeywords) ||
        _looksLikeCountdownQuery(userMessage)) {
      add(
        '- create_countdown: {"action":"create_countdown","countdowns":[{"title":"事件","dueDate":"YYYY-MM-DD HH:mm"}]}',
      );
      add(
        '- update_countdown: {"action":"update_countdown","updates":[{"countdownId":"倒计时ID","title":"新标题","dueDate":"YYYY-MM-DD HH:mm"}]}',
      );
      add(
        '- complete_countdown: {"action":"complete_countdown","updates":[{"countdownId":"倒计时ID"}]}',
      );
      add(
        '- delete_countdown: {"action":"delete_countdown","updates":[{"countdownId":"倒计时ID"}]}',
      );
    }
    if (_matchesAny(userMessage, _groupKeywords)) {
      add(
        '- create_todo_group: {"action":"create_todo_group","groups":[{"name":"分类名"}]}',
      );
      add(
        '- update_todo_group: {"action":"update_todo_group","updates":[{"groupId":"分类ID","name":"新分类名"}]}',
      );
      add(
        '- delete_todo_group: {"action":"delete_todo_group","updates":[{"groupId":"分类ID"}]}',
      );
    }
    if (_matchesAny(userMessage, _tagKeywords)) {
      add(
        '- create_pomodoro_tag: {"action":"create_pomodoro_tag","tags":[{"name":"标签名","color":"#607D8B"}]}',
      );
      add(
        '- update_pomodoro_tag: {"action":"update_pomodoro_tag","updates":[{"tagId":"标签ID","name":"新名称","color":"#3B82F6"}]}',
      );
      add(
        '- delete_pomodoro_tag: {"action":"delete_pomodoro_tag","updates":[{"tagId":"标签ID"}]}',
      );
    }
    if (actions.isEmpty) {
      add('- create_todo / update_todo / complete_todo / delete_todo');
    }

    return '''【本轮可用动作（按需精简）】
${actions.join('\n')}

动作块格式（必须）：
[ACTION_START]
[{"action":"..."}]
[ACTION_END]

字段约束（必须）：
- 仅操作已有对象时必须携带对应ID（todoId / scheduleId / groupId / countdownId / tagId / planBlockId / logId）
- 时间字段统一使用 yyyy-MM-dd HH:mm（如 startTime / dueDate）
- 待办时间必须带timeMode：unscheduled无日期、dateOnly某天内完成、deadline具体截止时刻；null表示清空，字段缺省表示不修改
- 没有日期和时间的待办保持未安排，不得默认今天全天
- 只有日期没有具体时刻时才使用dateOnly；isAllDay仅作旧协议兼容
- 单一时刻默认表示截止点，不得自动扩展为一小时执行区间
- 取件、取餐、取药默认是可完成的待办，不得仅为触发提醒而伪装成全天事件
- 考试、课程、会议、面试、预约、航班等外部决定时间的事项必须使用固定日程动作，不能静默创建为待办或规划块
- 固定日程date必填；时间待定时startTime/endTime均为null，只有开始时刻时endTime为null，明确区间才同时填写开始和结束
- 把已有待办安排到用户可调整的执行时段时使用create_plan_block
- 重复只表示周期机制，不得自动称为习惯
- 新建循环待办必须提供首次发生日期/截止点；recurrenceEndDate是最后一期日期，不是普通待办截止时间
- 上下文中同一recurrenceSeriesId下的每一条都是可独立寻址的真实期次；待办用todoId，日程用scheduleId，绝不能把seriesId当期次ID
- 用户没有明确“本期及以后/后续所有周期”时，循环待办和循环日程动作必须使用recurrenceScope="occurrence"
- 危险操作（删除/取消日程、完成待办、停止）仅在用户明确要求时输出''';
  }

  static String buildSystemPrompt({
    required String customPrompt,
    required bool promptEnabled,
    required List<Map<String, dynamic>> todos,
    required List<TodoGroup> todoGroups,
    List<CountdownItem> countdowns = const [],
    List<PomodoroTag> pomodoroTags = const [],
    List<TodoPlanBlock> planBlocks = const [],
    List<FixedScheduleItem> fixedSchedules = const [],
    DateTime? now,
  }) {
    final nowValue = now ?? DateTime.now();
    final nowText =
        '${DateFormat('yyyy-MM-dd HH:mm').format(nowValue)} (${_formatTimeZone(nowValue)})';
    final todoList = _formatTodos(todos, todoGroups);
    final scheduleList = _formatFixedSchedules(fixedSchedules, '', nowValue);
    final basePrompt = promptEnabled && customPrompt.trim().isNotEmpty
        ? customPrompt
        : ChatStorageService.defaultPrompt;

    final resolvedBasePrompt =
        basePrompt.replaceAll('{now}', nowText).replaceAll('{todos}', todoList);

    return '''$resolvedBasePrompt

【用户当前固定日程】
$scheduleList

【时间规则】
所有上下文时间均为本地时间，格式为yyyy-MM-dd HH:mm。判断今天、昨天、明天时必须以当前基准时间和括号中的时区为准，不要按UTC重新换算。

【事项语义】
- 待办表示需要完成的结果；没有日期和时间时保持未安排，不能默认今天全天。
- 只有日期没有具体时刻时表示“某天内完成”；单一时刻表示截止点，不能自动补一小时。
- 规划块表示用户自行安排、可以调整的执行时段。
- 考试、课程、会议、面试、预约、航班等外部固定时间属于固定日程，不是待办或规划块；创建或修改时必须使用日程动作。
- 取件、取餐、取药默认属于待办；可领取窗口不占用整个日历时段。只有必须按预约时刻到场时才属于固定日程。
- 重复是一种周期机制，不等于习惯；不得把每周周报、每月交租等称为习惯。
- 循环系列由多个可独立寻址的真实期次组成。recurrenceSeriesId只标识系列，不能代替todoId或scheduleId；每个期次必须使用自己的真实ID。
- 修改默认只作用于当前期次。只有用户明确说“本期及以后/后续所有周期”时才能使用future；修改循环规则或结束循环必须明确future。

【事项管理功能 - 重要规则】
当用户明确要求管理待办、固定日程、规划块、专注记录、番茄钟、倒计时、分类或标签时，必须在回复末尾附加JSON操作块。
操作已有对象必须使用上下文中的真实期次ID；固定日程使用scheduleId，循环系列ID不能代替期次ID。不确定时先追问。
JSON操作块必须且只能使用以下协议：
1. 必须用 [ACTION_START] 和 [ACTION_END] 包裹。
2. [ACTION_START] 内必须是合法 JSON 数组；即使只有一个操作，也必须放进数组。
3. 每个操作对象必须包含 "action" 字段。
4. 禁止使用 Markdown 代码块，例如 ```json。
5. 禁止使用 [PLAN_TODOS]、[CREATE_TODO]、[UPDATE_TODO] 等任何旧标记。
6. 禁止只输出 {"todos":[...]}、{"updates":[...]} 等缺少 "action" 字段的对象。
7. 如果同时输出操作块和建议块，顺序必须是：正文 -> [ACTION_START]...[ACTION_END] -> [SUGGEST_START]...[SUGGEST_END]。

唯一合法示例：
[ACTION_START]
[
  {"action":"create_plan_block","blocks":[{"todoId":"已有待办ID","title":"标题快照","startTime":"YYYY-MM-DD HH:mm","dueDate":"YYYY-MM-DD HH:mm","durationMinutes":60,"remark":"备注","reminderMinutes":5}]}
]
[ACTION_END]

支持的动作：

- create_todo: {"action":"create_todo","todos":[{"title":"标题","remark":"备注","timeMode":"unscheduled|dateOnly|deadline","dueDate":null,"recurrence":"none|daily|weekly|monthly|yearly|weekdays|customDays","customIntervalDays":null,"recurrenceEndDate":null,"groupId":null,"reminderMinutes":5}]}。循环待办必须给首次dueDate；创建后每一期有独立todoId
- create_schedule: {"action":"create_schedule","schedules":[{"title":"日程名","date":"YYYY-MM-DD","startTime":"YYYY-MM-DD HH:mm或null","endTime":"YYYY-MM-DD HH:mm或null","location":null,"remark":null,"reminderMinutes":[15],"recurrence":"none|daily|weekly|monthly|yearly|weekdays|customDays","customIntervalDays":null,"recurrenceEndDate":null}]}。date必填；时间待定时起止均为null；只有开始时刻时endTime为null
- update_schedule: {"action":"update_schedule","updates":[{"scheduleId":"真实期次ID","recurrenceSeriesId":"可选系列ID","recurrenceScope":"occurrence|future","title":"新标题","date":"YYYY-MM-DD","startTime":"YYYY-MM-DD HH:mm或null","endTime":"YYYY-MM-DD HH:mm或null","location":null,"remark":null,"reminderMinutes":[],"recurrence":"none|daily|weekly|monthly|yearly|weekdays|customDays","customIntervalDays":null,"recurrenceEndDate":null}]}。字段缺省=保持，null=清空；修改重复规则必须使用future
- cancel_schedule / delete_schedule: 使用scheduleId；默认occurrence，只有明确“本期及以后”才用future；日程没有待办式“完成勾选”
- plan_todos: 同create_todo字段，仅用于创建全新的待办事项；如果用户要求把已有待办安排到具体执行时间，必须使用create_plan_block
- create_plan_block: {"action":"create_plan_block","blocks":[{"todoId":"已有待办ID","title":"标题快照","startTime":"YYYY-MM-DD HH:mm","dueDate":"YYYY-MM-DD HH:mm","durationMinutes":60,"remark":"备注","reminderMinutes":5}]}，用于把已有待办安排到具体时间块；用户说"规划今天/明天/本周时间""安排到几点到几点"时优先使用这个动作。重要：规划中提到的每一个已有待办都必须生成对应的plan block，不要只生成一个
- update_plan_block / reschedule_plan_blocks / delete_plan_block / skip_plan_block / start_plan_block_pomodoro: 必须使用已有规划块ID(planBlockId/blockId/id)，用于修改、重排、删除、跳过或直接开始某个规划块的番茄钟
- update_todo: {"action":"update_todo","updates":[{"todoId":"真实期次ID","recurrenceSeriesId":"可选系列ID","recurrenceScope":"occurrence|future","title":"新标题","timeMode":"unscheduled|dateOnly|deadline","dueDate":"...","groupId":"...","reminderMinutes":5}]}。字段缺省=保持，字段为null=清空
- complete_todo: {"action":"complete_todo","updates":[{"todoId":"真实期次ID","recurrenceScope":"occurrence"}]}，循环完成状态永远属于单期
- delete_todo: {"action":"delete_todo","updates":[{"todoId":"真实期次ID","recurrenceSeriesId":"可选系列ID","recurrenceScope":"occurrence|future"}]}
- reschedule_todo: {"action":"reschedule_todo","updates":[{"todoId":"真实期次ID","recurrenceScope":"occurrence|future","timeMode":"dateOnly|deadline|unscheduled","dueDate":"..."}]}
- bulk_reschedule: 同reschedule_todo，批量改期
- categorize_todo: {"action":"categorize_todo","updates":[{"todoId":"ID","groupId":"新分类ID"}]}
- split_todo: {"action":"split_todo","sourceTodoId":"原ID","deleteSource":false,"todos":[...]}
- merge_todos: {"action":"merge_todos","sourceTodoIds":["ID1","ID2"],"deleteSources":false,"todo":{...}}
- create_time_log: {"action":"create_time_log","logs":[{"title":"专注内容","startTime":"YYYY-MM-DD HH:mm","dueDate":"YYYY-MM-DD HH:mm","durationMinutes":60,"remark":"备注","tagUuids":[]}]}
- update_time_log: {"action":"update_time_log","updates":[{"logId":"ID","title":"新标题","startTime":"...","dueDate":"...","durationMinutes":60,"remark":"备注","tagUuids":[]}]}
- delete_time_log: {"action":"delete_time_log","updates":[{"logId":"ID"}]}
- start_pomodoro: {"action":"start_pomodoro","title":"专注内容","todoId":"可选待办ID","durationMinutes":25,"tagUuids":[]}
- stop_pomodoro: {"action":"stop_pomodoro","status":"completed"}
- create_countdown: {"action":"create_countdown","countdowns":[{"title":"事件","dueDate":"YYYY-MM-DD HH:mm"}]}
- update_countdown: {"action":"update_countdown","updates":[{"countdownId":"ID","title":"新标题","dueDate":"YYYY-MM-DD HH:mm"}]}
- complete_countdown: {"action":"complete_countdown","updates":[{"countdownId":"ID"}]}
- delete_countdown: {"action":"delete_countdown","updates":[{"countdownId":"ID"}]}
- create_todo_group: {"action":"create_todo_group","groups":[{"name":"分类名"}]}
- update_todo_group: {"action":"update_todo_group","updates":[{"groupId":"ID","name":"新分类名"}]}
- delete_todo_group: {"action":"delete_todo_group","updates":[{"groupId":"ID"}]}
- create_pomodoro_tag: {"action":"create_pomodoro_tag","tags":[{"name":"标签名","color":"#607D8B"}]}
- update_pomodoro_tag: {"action":"update_pomodoro_tag","updates":[{"tagId":"ID","name":"新名称","color":"#3B82F6"}]}
- delete_pomodoro_tag: {"action":"delete_pomodoro_tag","updates":[{"tagId":"ID"}]}

可组合多种操作：[ACTION_START][{"action":"create_plan_block","blocks":[...]},{"action":"start_pomodoro","title":"专注内容","durationMinutes":25}][ACTION_END]

【后续建议】
每次回复末尾附3-4个简短建议后续问题（≤15字），格式：[SUGGEST_START]["追问1","追问2","追问3"][SUGGEST_END]

【核心规则】
1. 意图判定：先区分待办结果、外部固定日程和可调整规划块，再选择创建/修改/取消/完成/删除/改期/分类/拆分/合并等动作
2. 文件夹归类：只在语义明显关联时分配groupId，不确定时留空，严禁乱分类
3. 危险操作(删除或取消日程、删除或完成待办、合并删源、拆分删源、停止番茄钟、删除专注记录、完成或删除倒计时、删除番茄标签)只在用户明确要求时输出
4. 禁止对已有分类任务重复categorize_todo
5. [ACTION_START]/[ACTION_END]标记和[SUGGEST_START]/[SUGGEST_END]标记必须完整
6. 规划完整性：当用户要求规划时间（今天/明天/本周等），文本中提到的每一个时间段如果对应已有待办，都必须在[ACTION_START]中生成create_plan_block，不能只生成部分。如果文本中规划了5个时间段对应5个已有待办，action中必须有5个blocks
7. 规划避让：如果上下文提供固定日程、课程表、已有规划或专注记录，生成create_plan_block时必须避开硬约束和已占用时间
8. 循环期次：complete永远只完成指定todoId；修改/删除默认occurrence。只有用户明确要求后续所有周期时使用future；结束循环用update_todo设置recurrence="none"、recurrenceScope="future"''';
  }

  /// 根据用户消息关键词，返回需要注入的上下文片段。无匹配返回 null。
  static String? buildContextInjection({
    required String userMessage,
    required List<CourseItem> courses,
    required List<TimeLogItem> timeLogs,
    List<TodoGroup> todoGroups = const [],
    List<PomodoroRecord> pomodoroRecords = const [],
    List<TodoPlanBlock> planBlocks = const [],
    List<Map<String, dynamic>> todos = const [],
    List<CountdownItem> countdowns = const [],
    List<PomodoroTag> pomodoroTags = const [],
    List<FixedScheduleItem> fixedSchedules = const [],
    required List<ConflictInfo> conflicts,
    required List<Team> teams,
    DateTime? now,
  }) {
    final nowValue = now ?? DateTime.now();
    final sections = <String>[];

    if (_shouldInjectCourseContext(userMessage) && courses.isNotEmpty) {
      sections.add(_formatCourses(courses, userMessage, nowValue));
    }
    if (_shouldInjectFixedScheduleContext(userMessage) &&
        fixedSchedules.isNotEmpty) {
      sections.add(
        _formatFixedSchedules(fixedSchedules, userMessage, nowValue),
      );
    }
    if (_shouldInjectTodoContext(userMessage) && todos.isNotEmpty) {
      sections.add(
        _formatTodos(
          todos,
          todoGroups,
          userMessage: userMessage,
          now: nowValue,
        ),
      );
      if (todoGroups.isNotEmpty) {
        sections.add('分类/文件夹（随待办注入）:\n${_formatGroups(todoGroups)}');
      }
    }
    if (!_shouldInjectTodoContext(userMessage) &&
        _matchesAny(userMessage, _groupKeywords) &&
        todoGroups.isNotEmpty) {
      sections.add('分类/文件夹:\n${_formatGroups(todoGroups)}');
    }
    if ((_matchesAny(userMessage, _countdownKeywords) ||
            _looksLikeCountdownQuery(userMessage)) &&
        countdowns.isNotEmpty) {
      sections.add(
        _formatCountdowns(
          countdowns,
          userMessage: userMessage,
          now: nowValue,
        ),
      );
    }
    if (_matchesAny(userMessage, _tagKeywords) && pomodoroTags.isNotEmpty) {
      sections.add('番茄标签:\n${_formatPomodoroTags(pomodoroTags)}');
    }
    if (_matchesAny(userMessage, _planKeywords) && planBlocks.isNotEmpty) {
      sections.add(
        _formatPlanBlocks(
          planBlocks,
          todos,
          userMessage: userMessage,
          now: nowValue,
        ),
      );
    }
    if ((_matchesAny(userMessage, _timeLogKeywords) ||
            _looksLikeFocusQuery(userMessage)) &&
        (timeLogs.isNotEmpty ||
            pomodoroRecords.isNotEmpty ||
            planBlocks.isNotEmpty)) {
      sections.add(
        _formatFocusRecords(
          timeLogs,
          pomodoroRecords,
          userMessage,
          nowValue,
        ),
      );
      if (planBlocks.isNotEmpty) {
        sections.add(
          _formatPlanBlocks(
            planBlocks,
            todos,
            userMessage: userMessage,
            now: nowValue,
          ),
        );
      }
    }
    if (_matchesAny(userMessage, _conflictKeywords) && conflicts.isNotEmpty) {
      sections.add(_formatConflicts(conflicts));
    }
    if (_matchesAny(userMessage, _teamKeywords) && teams.isNotEmpty) {
      sections.add(_formatTeams(teams));
    }

    if (sections.isEmpty) return null;
    return '【相关上下文】\n${sections.join('\n')}';
  }

  /// 返回用于输入区提示的注入摘要，不包含完整上下文正文。
  static String? buildContextInjectionSummary({
    required String userMessage,
    required List<CourseItem> courses,
    required List<TimeLogItem> timeLogs,
    List<TodoGroup> todoGroups = const [],
    List<PomodoroRecord> pomodoroRecords = const [],
    List<TodoPlanBlock> planBlocks = const [],
    List<Map<String, dynamic>> todos = const [],
    List<CountdownItem> countdowns = const [],
    List<PomodoroTag> pomodoroTags = const [],
    List<FixedScheduleItem> fixedSchedules = const [],
    required List<ConflictInfo> conflicts,
    required List<Team> teams,
    DateTime? now,
  }) {
    final nowValue = now ?? DateTime.now();
    final parts = <String>[];

    if (_shouldInjectCourseContext(userMessage) && courses.isNotEmpty) {
      final period = _resolveCoursePeriod(userMessage, nowValue);
      if (period != null) {
        parts.add(
          '课程${_formatCompactDate(period.start)}-${_formatCompactDate(period.end.subtract(const Duration(days: 1)))}',
        );
      } else {
        parts.add('课程今日起');
      }
    }
    if (_shouldInjectFixedScheduleContext(userMessage) &&
        fixedSchedules.isNotEmpty) {
      final scoped = _scopeFixedSchedulesByTime(
        fixedSchedules,
        userMessage: userMessage,
        now: nowValue,
      );
      parts.add('日程${scoped.length}条');
    }
    if (_shouldInjectTodoContext(userMessage) && todos.isNotEmpty) {
      final scoped = _scopeTodosByTime(
        todos,
        userMessage: userMessage,
        now: nowValue,
      );
      parts.add('待办${scoped.length}条');
      if (todoGroups.isNotEmpty) {
        parts.add('分类${todoGroups.length}个');
      }
    }
    if (!_shouldInjectTodoContext(userMessage) &&
        _matchesAny(userMessage, _groupKeywords) &&
        todoGroups.isNotEmpty) {
      parts.add('分类${todoGroups.length}个');
    }
    if ((_matchesAny(userMessage, _countdownKeywords) ||
            _looksLikeCountdownQuery(userMessage)) &&
        countdowns.isNotEmpty) {
      final scoped = _scopeCountdownsByTime(
        countdowns,
        userMessage: userMessage,
        now: nowValue,
      );
      parts.add('倒计时${scoped.length}个');
    }
    if (_matchesAny(userMessage, _tagKeywords) && pomodoroTags.isNotEmpty) {
      parts.add('番茄标签${pomodoroTags.where((t) => !t.isDeleted).length}个');
    }
    if (_matchesAny(userMessage, _planKeywords) && planBlocks.isNotEmpty) {
      final scoped = _scopePlanBlocksByTime(
        planBlocks,
        userMessage: userMessage,
        now: nowValue,
      );
      parts.add('规划块${scoped.length}个');
    }

    if ((_matchesAny(userMessage, _timeLogKeywords) ||
            _looksLikeFocusQuery(userMessage)) &&
        (timeLogs.isNotEmpty ||
            pomodoroRecords.isNotEmpty ||
            planBlocks.isNotEmpty)) {
      final period = _resolveTimeLogPeriod(userMessage, nowValue);
      if (period != null) {
        final start = _formatCompactDate(period.start);
        final end =
            _formatCompactDate(period.end.subtract(const Duration(days: 1)));
        parts.add(start == end ? '专注记录$start' : '专注记录$start-$end');
      } else {
        parts.add('专注记录最近30条');
      }
      if (planBlocks.isNotEmpty) {
        parts.add('规划块');
      }
    }

    if (_matchesAny(userMessage, _conflictKeywords) && conflicts.isNotEmpty) {
      parts.add('冲突信息');
    }
    if (_matchesAny(userMessage, _teamKeywords) && teams.isNotEmpty) {
      parts.add('团队信息');
    }

    if (parts.isEmpty) return null;
    return '将注入：${parts.join('、')}';
  }

  static bool _matchesAny(String text, List<String> keywords) {
    return keywords.any((k) => text.contains(k));
  }

  static bool _shouldInjectCourseContext(String text) {
    if (_matchesAny(text, _courseKeywords)) return true;
    return _matchesAny(text, _planningKeywords) &&
        _matchesAny(text, _planningTimeKeywords);
  }

  static bool _shouldInjectFixedScheduleContext(String text) {
    if (_matchesAny(text, _fixedScheduleKeywords)) return true;
    return _matchesAny(text, _planningKeywords) &&
        _matchesAny(text, _planningTimeKeywords);
  }

  static bool _shouldInjectTodoContext(String text) {
    final asksList = _matchesAny(text, _todoListQueryKeywords) ||
        _looksLikeTodoListQuery(text);
    final touchesExisting = _matchesAny(text, _existingTodoKeywords);
    final createOnly = _matchesAny(text, _createTodoKeywords) &&
        !_matchesAny(text, _existingTodoKeywords) &&
        !asksList;
    if (createOnly) return false;
    return touchesExisting || asksList;
  }

  static bool _looksLikeTodoListQuery(String text) {
    final hasTodoNoun = text.contains('待办') ||
        text.contains('任务') ||
        text.toLowerCase().contains('todo');
    if (!hasTodoNoun) return false;
    return text.contains('什么') ||
        text.contains('哪些') ||
        text.contains('查看') ||
        text.contains('列出') ||
        text.contains('有没有') ||
        text.contains('有啥') ||
        text.contains('有吗');
  }

  static bool _looksLikeCountdownQuery(String text) {
    final hasNoun = text.contains('倒计时') ||
        text.contains('倒数日') ||
        text.contains('倒數日') ||
        text.toLowerCase().contains('countdown');
    if (!hasNoun) return false;
    return text.contains('什么') ||
        text.contains('哪些') ||
        text.contains('查看') ||
        text.contains('列出') ||
        text.contains('有没有') ||
        text.contains('有啥') ||
        text.contains('有吗');
  }

  static bool _looksLikeFocusQuery(String text) {
    final hasNoun = text.contains('专注') ||
        text.contains('番茄') ||
        text.contains('时间记录') ||
        text.contains('时长');
    if (!hasNoun) return false;
    return text.contains('什么') ||
        text.contains('哪些') ||
        text.contains('查看') ||
        text.contains('列出') ||
        text.contains('有没有') ||
        text.contains('有啥') ||
        text.contains('有吗') ||
        text.contains('多久');
  }

  static const _courseKeywords = [
    '课',
    '课程',
    '上课',
    '教室',
    '老师',
    '学期',
    '周几',
    '星期',
    '课表',
    '排课',
    '选课',
    '调课',
  ];
  static const _fixedScheduleKeywords = [
    '日程',
    '日历',
    '固定日程',
    '会议',
    '例会',
    '考试',
    '上课',
    '课程',
    '面试',
    '预约',
    '门诊',
    '体检',
    '手术',
    '答辩',
    '讲座',
    '驾考',
    '航班',
    '飞机',
    '火车',
    '高铁',
    '演出',
    '电影',
    '比赛',
    '行程',
  ];
  static const _planningKeywords = [
    '规划',
    '安排',
    '计划',
    '排一下',
    '排时间',
    '待办规划',
    '今日计划',
  ];
  static const _createTodoKeywords = [
    '提醒我',
    '记得',
    '新建',
    '新增',
    '创建',
    '添加',
  ];
  static const _recurrenceKeywords = [
    '循环',
    '重复',
    '每天',
    '每周',
    '每月',
    '每年',
    '工作日',
    '每隔',
    '后续周期',
    '以后所有周期',
    '结束循环',
  ];
  static const _existingTodoKeywords = [
    '修改',
    '更新',
    '完成',
    '删除',
    '延期',
    '改期',
    '分类',
    '归类',
    '拆分',
    '合并',
    '重排',
    '重计划',
    '规划',
    '这个待办',
    '该待办',
    '把待办',
  ];
  static const _todoListQueryKeywords = [
    '待办清单',
    '有哪些待办',
    '有什么待办',
    '今天有什么待办',
    '今天待办',
    '我的待办',
    '全部待办',
    '列出待办',
    '查看待办',
  ];
  static const _groupKeywords = [
    '分类',
    '文件夹',
    '归类',
    '分组',
  ];
  static const _countdownKeywords = [
    '倒计时',
    '倒数日',
    '倒數日',
    '截止',
    'ddl',
  ];
  static const _tagKeywords = [
    '标签',
    '番茄标签',
    'tag',
  ];
  static const _financeKeywords = [
    '记账',
    '账单',
    '支出',
    '收入',
    '退款',
    '消费',
    '记一笔',
    '花钱',
    '买了',
    '付款',
    '支付',
    '花了',
    '花费',
    '进账',
    '收款',
    '余额',
    '预算',
  ];
  static const _planKeywords = [
    '规划',
    '时间块',
    'plan block',
    '计划块',
  ];
  static const _planningTimeKeywords = [
    '未来',
    '接下来',
    '一周',
    '七天',
    '7天',
    '今天',
    '今日',
    '明天',
    '明日',
    '后天',
    '本周',
    '这周',
    '下周',
    '本月',
    '这个月',
    '时间',
    '上午',
    '下午',
    '晚上',
    '早上',
    '中午',
    '点',
    '分钟',
    '小时',
  ];
  static const _timeLogKeywords = [
    '专注',
    '番茄',
    '时间',
    '记录',
    '统计',
    '日志',
    '时长',
    '钟',
    '分钟',
    '效率',
    '集中',
  ];
  static const _conflictKeywords = [
    '冲突',
    '同步',
    '版本',
    '覆盖',
    '合并冲突',
    '冲突解决',
  ];
  static const _teamKeywords = [
    '团队',
    '协作',
    '成员',
    '管理员',
    '邀请',
    '队友',
    '小组',
  ];

  static String buildPromptPreview({
    required String customPrompt,
    required bool promptEnabled,
    required List<Map<String, dynamic>> todos,
    required List<TodoGroup> todoGroups,
    DateTime? now,
  }) {
    final nowValue = now ?? DateTime.now();
    final nowText =
        '${DateFormat('yyyy-MM-dd HH:mm').format(nowValue)} (${_formatTimeZone(nowValue)})';
    final basePrompt = promptEnabled && customPrompt.trim().isNotEmpty
        ? customPrompt
        : ChatStorageService.defaultPrompt;
    return basePrompt
        .replaceAll('{now}', nowText)
        .replaceAll('{todos}', _formatTodos(todos, todoGroups));
  }

  static String buildManualCopyPrompt(List<Map<String, String>> messages) {
    final buffer = StringBuffer()
      ..writeln('请按下面的对话内容扮演效率助手，只回复 assistant 的最终内容。')
      ..writeln(
          '必须遵守 system 中的所有规则；如果需要创建、修改、规划或删除数据，必须输出可被应用识别的 [ACTION_START] JSON 操作块。')
      ..writeln('不要解释这些包装文本，不要使用 Markdown 代码块包裹操作 JSON。');

    for (final message in messages) {
      final role = (message['role'] ?? 'user').toUpperCase();
      final content = message['content'] ?? '';
      buffer
        ..writeln()
        ..writeln('===== $role =====')
        ..writeln(content);
    }
    return buffer.toString().trim();
  }

  static String _formatTodos(
      List<Map<String, dynamic>> todos, List<TodoGroup> todoGroups,
      {String? userMessage, DateTime? now}) {
    if (todos.isEmpty) return '暂无待办';
    final scoped = _scopeTodosByTime(
      todos,
      userMessage: userMessage,
      now: now,
    );
    if (scoped.isEmpty) return '待办列表: 暂无匹配时间范围的待办';
    return '待办列表（按时间范围筛选，最多80条）:\n${scoped.take(80).map((t) {
      final id = t['id'] ?? 'unknown';
      final title = t['title'] ?? '';
      final remark = t['remark'] ?? '';
      final startTime = t['startTime'] ?? '';
      final endTime = t['endTime'] ?? '';
      final timeMode = switch (t['timeMode']?.toString()) {
        'dateOnly' => '日期内完成',
        'deadline' => '定时截止',
        _ => '未安排',
      };
      final recurrence = t['recurrence'] ?? 'none';
      final recurrenceRule = t['recurrenceRule'] ?? recurrence;
      final recurrenceSeriesId =
          t['recurrenceSeriesId']?.toString().trim() ?? '';
      final recurrenceRole = t['recurrenceRole']?.toString() ?? 'standalone';
      final customIntervalDays = t['customIntervalDays'];
      final recurrenceEndDate = t['recurrenceEndDate']?.toString().trim() ?? '';
      final status = t['isDone'] == true ? '已完成' : '未完成';
      final reminderMinutes = t['reminderMinutes'] ?? 5;
      final gid = t['groupId'] ?? '';
      var folderName = '';
      if (gid.toString().isNotEmpty) {
        folderName = todoGroups
            .firstWhere((g) => g.id == gid, orElse: () => TodoGroup(name: ''))
            .name;
      }

      final recurrenceText = recurrenceSeriesId.isEmpty
          ? ' | 循环: none'
          : ' | 系列ID: $recurrenceSeriesId | 期次角色: $recurrenceRole | 系列规则: $recurrenceRule${recurrenceRule == 'customDays' ? '(${customIntervalDays ?? 1}天)' : ''}${recurrenceEndDate.isNotEmpty ? ' | 系列结束: $recurrenceEndDate' : ''}${recurrence != recurrenceRule ? ' | 本期存储规则: $recurrence' : ''}';
      return '- [期次todoId: $id] 标题: $title | 状态: $status${remark.toString().isNotEmpty ? ' | 备注: $remark' : ''}${folderName.isNotEmpty ? ' | 分类: $folderName' : ''}${startTime.toString().isNotEmpty ? ' | 日期锚点: $startTime' : ''}${endTime.toString().isNotEmpty ? ' | 截止: $endTime' : ''} | 时间语义: $timeMode$recurrenceText | 提醒: 提前$reminderMinutes分钟';
    }).join('\n')}';
  }

  static String _formatGroups(List<TodoGroup> todoGroups) {
    if (todoGroups.isEmpty) return '暂无分类';
    return todoGroups.map((g) => '- 名称: ${g.name} | ID: ${g.id}').join('\n');
  }

  static String _formatCountdowns(
    List<CountdownItem> countdowns, {
    String? userMessage,
    DateTime? now,
  }) {
    final active = _scopeCountdownsByTime(
      countdowns,
      userMessage: userMessage,
      now: now,
    );
    if (active.isEmpty) return '倒计时: 暂无匹配时间范围的记录';
    return '倒计时（按时间范围筛选）:\n${active.take(40).map((c) {
      final target = DateFormat('yyyy-MM-dd HH:mm').format(c.targetDate);
      final status = c.isCompleted ? '已达成' : '进行中';
      return '- [ID: ${c.id}] 标题: ${c.title} | 目标: $target | 状态: $status';
    }).join('\n')}';
  }

  static String _formatPomodoroTags(List<PomodoroTag> tags) {
    final active = tags.where((t) => !t.isDeleted).take(40).toList();
    if (active.isEmpty) return '暂无番茄标签';
    return active
        .map((t) => '- [ID: ${t.uuid}] 名称: ${t.name} | 颜色: ${t.color}')
        .join('\n');
  }

  static String _formatPlanBlocks(
      List<TodoPlanBlock> blocks, List<Map<String, dynamic>> todos,
      {String? userMessage, DateTime? now}) {
    final active = _scopePlanBlocksByTime(
      blocks,
      userMessage: userMessage,
      now: now,
    )..sort((a, b) => a.startTime.compareTo(b.startTime));
    if (active.isEmpty) return '待办规划: 暂无匹配时间范围的规划块';

    String todoTitle(String id) {
      final match = todos.where((t) => t['id']?.toString() == id).toList();
      if (match.isEmpty) return id;
      final title = match.first['title']?.toString();
      return title == null || title.isEmpty ? id : title;
    }

    return '待办规划（按时间范围筛选）:\n${active.take(60).map((b) {
      final start = DateFormat('yyyy-MM-dd HH:mm')
          .format(DateTime.fromMillisecondsSinceEpoch(b.startTime));
      final end = DateFormat('yyyy-MM-dd HH:mm')
          .format(DateTime.fromMillisecondsSinceEpoch(b.endTime));
      final actualMinutes = b.actualFocusSeconds ~/ 60;
      return '- [ID: ${b.id}] 待办ID: ${b.todoId} | 标题: ${b.titleSnapshot ?? todoTitle(b.todoId)} | 时间: $start-$end | 计划: ${b.plannedMinutes}分钟 | 实际专注: $actualMinutes分钟 | 状态: ${b.status.name} | 提醒: 提前${b.reminderMinutes}分钟';
    }).join('\n')}';
  }

  static String _formatFixedSchedules(
    List<FixedScheduleItem> schedules,
    String userMessage,
    DateTime now,
  ) {
    final scoped = _scopeFixedSchedulesByTime(
      schedules,
      userMessage: userMessage,
      now: now,
    );
    if (scoped.isEmpty) return '固定日程: 暂无';
    final lines = scoped.take(50).map((item) {
      final time = item.startTime == null
          ? '时间待定'
          : item.endTime == null
              ? '${DateFormat('HH:mm').format(DateTime.fromMillisecondsSinceEpoch(item.startTime!).toLocal())}（结束待定）'
              : '${DateFormat('HH:mm').format(DateTime.fromMillisecondsSinceEpoch(item.startTime!).toLocal())}-${DateFormat('HH:mm').format(DateTime.fromMillisecondsSinceEpoch(item.endTime!).toLocal())}';
      final series = item.recurrenceSeriesId?.trim().isNotEmpty == true
          ? ' | 系列ID: ${item.recurrenceSeriesId} | 重复: ${item.recurrence.name}'
          : '';
      final location = item.location?.trim().isNotEmpty == true
          ? ' | 地点: ${item.location}'
          : '';
      final remark =
          item.remark?.trim().isNotEmpty == true ? ' | 备注: ${item.remark}' : '';
      return '- [日程ID: ${item.id}] ${item.date} $time ${item.title} | 状态: ${item.status.name}$location$remark$series';
    }).join('\n');
    return '固定日程（外部时间硬约束；每条使用自己的日程ID）:\n$lines';
  }

  static List<FixedScheduleItem> _scopeFixedSchedulesByTime(
    List<FixedScheduleItem> schedules, {
    required String userMessage,
    required DateTime now,
  }) {
    final active = schedules.where((item) => !item.isDeleted).toList()
      ..sort((left, right) {
        final dateCompare = left.date.compareTo(right.date);
        if (dateCompare != 0) return dateCompare;
        return (left.startTime ?? 0).compareTo(right.startTime ?? 0);
      });
    final period = _resolveCoursePeriod(userMessage, now);
    if (period != null) {
      return active.where((item) {
        final date = DateTime.tryParse(item.date);
        return date != null &&
            !date.isBefore(period.start) &&
            date.isBefore(period.end);
      }).toList();
    }
    if (userMessage.trim().isEmpty) return active.take(50).toList();
    final today = DateTime(now.year, now.month, now.day);
    return active
        .where((item) {
          final date = DateTime.tryParse(item.date);
          return date != null && !date.isBefore(today);
        })
        .take(50)
        .toList();
  }

  static String _formatCourses(
    List<CourseItem> courses,
    String userMessage,
    DateTime now,
  ) {
    if (courses.isEmpty) return '课程表: 暂无';
    final activeCourses = courses.where((c) => !c.isDeleted).toList()
      ..sort((a, b) {
        final dateCompare = a.date.compareTo(b.date);
        if (dateCompare != 0) return dateCompare;
        return a.startTime.compareTo(b.startTime);
      });
    if (activeCourses.isEmpty) return '课程表: 暂无';

    final allDates = activeCourses
        .map((c) => DateTime.tryParse(c.date))
        .whereType<DateTime>()
        .toList();
    final availableRange = allDates.isEmpty
        ? null
        : _DateRange(
            label: '全部可用课程日期',
            start: allDates.first,
            end: allDates.last.add(const Duration(days: 1)),
          );
    final period = _resolveCoursePeriod(userMessage, now);
    final scopedCourses = _selectCoursesForPeriod(activeCourses, period, now);
    final lines = scopedCourses
        .take(30)
        .map((c) =>
            '- ${c.date} ${c.formattedStartTime}-${c.formattedEndTime} ${c.courseName} | ${c.roomName} | ${c.teacherName}')
        .join('\n');
    final header = period == null
        ? '课程表（当前时间: ${_formatDateTime(now)}，今日起最近30节）'
        : '课程表（当前时间: ${_formatDateTime(now)}，${period.label}范围: ${_formatDate(period.start)} 至 ${_formatDate(period.end.subtract(const Duration(days: 1)))})';
    final rangeLine = availableRange == null
        ? ''
        : '\n${availableRange.label}: ${_formatDate(availableRange.start)} 至 ${_formatDate(availableRange.end.subtract(const Duration(days: 1)))}';
    return '$header$rangeLine\n${lines.isEmpty ? '暂无匹配课程' : lines}';
  }

  static List<CourseItem> _selectCoursesForPeriod(
    List<CourseItem> courses,
    _DateRange? period,
    DateTime now,
  ) {
    if (period != null) {
      return courses.where((c) {
        final date = DateTime.tryParse(c.date);
        if (date == null) return false;
        final day = DateTime(date.year, date.month, date.day);
        return !day.isBefore(period.start) && day.isBefore(period.end);
      }).toList();
    }

    final today = DateTime(now.year, now.month, now.day);
    return courses.where((c) {
      final date = DateTime.tryParse(c.date);
      if (date == null) return false;
      final day = DateTime(date.year, date.month, date.day);
      return !day.isBefore(today);
    }).toList();
  }

  static _DateRange? _resolveCoursePeriod(String text, DateTime now) {
    final explicit = _resolveExplicitDateRange(text);
    if (explicit != null) return explicit;
    final todayStart = DateTime(now.year, now.month, now.day);
    final futureDays = _parseFutureDays(text);
    if (futureDays != null) {
      return _DateRange(
        label: '未来$futureDays天',
        start: todayStart,
        end: todayStart.add(Duration(days: futureDays)),
      );
    }
    if (text.contains('未来一周') ||
        text.contains('接下来一周') ||
        text.contains('未来7天') ||
        text.contains('未来七天') ||
        text.contains('接下来7天') ||
        text.contains('接下来七天')) {
      return _DateRange(
        label: '未来一周',
        start: todayStart,
        end: todayStart.add(const Duration(days: 7)),
      );
    }
    if (text.contains('今天') || text.contains('今日')) {
      return _DateRange(
        label: '今日',
        start: todayStart,
        end: todayStart.add(const Duration(days: 1)),
      );
    }
    if (text.contains('明天') || text.contains('明日')) {
      final start = todayStart.add(const Duration(days: 1));
      return _DateRange(
        label: '明日',
        start: start,
        end: start.add(const Duration(days: 1)),
      );
    }
    if (text.contains('后天') || text.contains('后日')) {
      final start = todayStart.add(const Duration(days: 2));
      return _DateRange(
        label: '后日',
        start: start,
        end: start.add(const Duration(days: 1)),
      );
    }
    if (text.contains('下周')) {
      final thisWeekStart =
          todayStart.subtract(Duration(days: now.weekday - 1));
      final start = thisWeekStart.add(const Duration(days: 7));
      return _DateRange(
        label: '下周',
        start: start,
        end: start.add(const Duration(days: 7)),
      );
    }
    if (text.contains('本周') || text.contains('这周')) {
      final start = todayStart.subtract(Duration(days: now.weekday - 1));
      return _DateRange(
        label: '本周',
        start: start,
        end: start.add(const Duration(days: 7)),
      );
    }
    if (text.contains('本月') || text.contains('这个月')) {
      return _DateRange(
        label: '本月',
        start: DateTime(now.year, now.month),
        end: DateTime(now.year, now.month + 1),
      );
    }
    return null;
  }

  static int? _parseFutureDays(String text) {
    final digitMatch =
        RegExp(r'(?:未来|接下来)\s*(\d{1,2})\s*(?:天|日)').firstMatch(text);
    if (digitMatch != null) {
      final parsed = int.tryParse(digitMatch.group(1)!);
      if (parsed != null && parsed > 0) {
        return parsed.clamp(1, 30);
      }
    }

    final hanMatch =
        RegExp(r'(?:未来|接下来)\s*([一二两三四五六七八九十]{1,3})\s*(?:天|日)').firstMatch(text);
    if (hanMatch != null) {
      final parsed = _parseSimpleChineseNumber(hanMatch.group(1)!);
      if (parsed != null && parsed > 0) {
        return parsed.clamp(1, 30);
      }
    }
    return null;
  }

  static int? _parseSimpleChineseNumber(String text) {
    const digits = {
      '一': 1,
      '二': 2,
      '两': 2,
      '三': 3,
      '四': 4,
      '五': 5,
      '六': 6,
      '七': 7,
      '八': 8,
      '九': 9,
    };
    if (text == '十') return 10;
    if (text.startsWith('十')) {
      final unit = digits[text.substring(1)];
      return unit == null ? null : 10 + unit;
    }
    if (text.endsWith('十')) {
      final tens = digits[text.substring(0, text.length - 1)];
      return tens == null ? null : tens * 10;
    }
    final tenIdx = text.indexOf('十');
    if (tenIdx > 0 && tenIdx < text.length - 1) {
      final tens = digits[text.substring(0, tenIdx)];
      final units = digits[text.substring(tenIdx + 1)];
      if (tens != null && units != null) return tens * 10 + units;
    }
    return digits[text];
  }

  static String _formatFocusRecords(
    List<TimeLogItem> timeLogs,
    List<PomodoroRecord> pomodoroRecords,
    String userMessage,
    DateTime now,
  ) {
    final activeLogs = timeLogs.where((t) => !t.isDeleted).toList();
    final activePomodoros = pomodoroRecords.where((p) => !p.isDeleted).toList();
    if (activeLogs.isEmpty && activePomodoros.isEmpty) return '专注记录: 暂无';
    final period = _resolveTimeLogPeriod(userMessage, now);
    final records = <_FocusRecord>[
      ...activeLogs.map(_FocusRecord.fromTimeLog),
      ...activePomodoros.map(_FocusRecord.fromPomodoro),
    ]..sort((a, b) => b.startMs.compareTo(a.startMs));
    final scopedRecords = period == null
        ? records.take(30).toList()
        : records.where((r) => _focusOverlapsPeriod(r, period)).toList();

    if (period != null) {
      final totalMinutes = scopedRecords
          .map((r) => _focusOverlapMinutes(r, period))
          .fold<int>(0, (sum, minutes) => sum + minutes);
      final timeLogMinutes = scopedRecords
          .where((r) => r.source == '补录')
          .map((r) => _focusOverlapMinutes(r, period))
          .fold<int>(0, (sum, minutes) => sum + minutes);
      final pomodoroMinutes = scopedRecords
          .where((r) => r.source == '番茄钟')
          .map((r) => _focusOverlapMinutes(r, period))
          .fold<int>(0, (sum, minutes) => sum + minutes);
      final lines = scopedRecords.take(30).map((r) {
        final start = _formatEpochMillis(r.startMs);
        final end = _formatEpochMillis(r.endMs);
        final minutes = _focusOverlapMinutes(r, period);
        return '- [${r.source} ID: ${r.id}] $start-$end ${r.title} | 本时段计入${formatMinutesChinese(minutes)}${r.status != null ? ' | 状态: ${r.status}' : ''}';
      }).join('\n');
      return '''专注记录:
${period.label}范围: ${_formatDateTime(period.start)} 至 ${_formatDateTime(period.end)}
${period.label}合计: ${formatMinutesChinese(totalMinutes)}
其中补录: ${formatMinutesChinese(timeLogMinutes)}，番茄钟: ${formatMinutesChinese(pomodoroMinutes)}
${period.label}记录:
${lines.isEmpty ? '暂无' : lines}''';
    }

    final lines = scopedRecords.map((r) {
      final start = _formatEpochMillis(r.startMs);
      final end = _formatEpochMillis(r.endMs);
      return '- [${r.source} ID: ${r.id}] $start-$end ${r.title} | ${formatMinutesChinese(r.minutes)}${r.status != null ? ' | 状态: ${r.status}' : ''}';
    }).join('\n');
    return '专注记录（最近30条，按开始时间倒序）:\n$lines';
  }

  static String _formatConflicts(List<ConflictInfo> conflicts) {
    if (conflicts.isEmpty) return '冲突信息: 暂无';
    final lines = conflicts.take(20).map((c) {
      final title = c.item['title'] ?? c.item['content'] ?? c.item['id'] ?? '';
      final other = c.conflictWith['title'] ??
          c.conflictWith['content'] ??
          c.conflictWith['id'] ??
          '';
      return '- ${c.type}: $title <-> $other';
    }).join('\n');
    return '冲突信息:\n$lines';
  }

  static String _formatTeams(List<Team> teams) {
    if (teams.isEmpty) return '团队协作: 暂无';
    final lines = teams
        .take(20)
        .map((t) => '- ${t.name} | ID: ${t.uuid} | 成员: ${t.memberCount}')
        .join('\n');
    return '团队协作:\n$lines';
  }

  static String _formatTimeZone(DateTime value) {
    final offset = value.timeZoneOffset;
    final sign = offset.isNegative ? '-' : '+';
    final absOffset = offset.abs();
    final hours = absOffset.inHours.toString().padLeft(2, '0');
    final minutes = (absOffset.inMinutes % 60).toString().padLeft(2, '0');
    return 'UTC$sign$hours:$minutes ${value.timeZoneName}';
  }

  static _TimeLogPeriod? _resolveTimeLogPeriod(String text, DateTime now) {
    final explicit = _resolveExplicitDateRange(text);
    if (explicit != null) {
      return _TimeLogPeriod(
        label: explicit.label,
        start: explicit.start,
        end: explicit.end,
      );
    }
    final todayStart = DateTime(now.year, now.month, now.day);
    if (text.contains('今天') || text.contains('今日')) {
      return _TimeLogPeriod(
        label: '今日',
        start: todayStart,
        end: todayStart.add(const Duration(days: 1)),
      );
    }
    if (text.contains('昨天') || text.contains('昨日')) {
      final start = todayStart.subtract(const Duration(days: 1));
      return _TimeLogPeriod(
        label: '昨日',
        start: start,
        end: todayStart,
      );
    }
    if (text.contains('本周') || text.contains('这周')) {
      final start = todayStart.subtract(Duration(days: now.weekday - 1));
      return _TimeLogPeriod(
        label: '本周',
        start: start,
        end: start.add(const Duration(days: 7)),
      );
    }
    if (text.contains('本月') || text.contains('这个月')) {
      final start = DateTime(now.year, now.month);
      return _TimeLogPeriod(
        label: '本月',
        start: start,
        end: DateTime(now.year, now.month + 1),
      );
    }
    return null;
  }

  static bool _focusOverlapsPeriod(_FocusRecord record, _TimeLogPeriod period) {
    return record.endMs > period.start.millisecondsSinceEpoch &&
        record.startMs < period.end.millisecondsSinceEpoch;
  }

  static int _focusOverlapMinutes(_FocusRecord record, _TimeLogPeriod period) {
    final start = record.startMs > period.start.millisecondsSinceEpoch
        ? record.startMs
        : period.start.millisecondsSinceEpoch;
    final end = record.endMs < period.end.millisecondsSinceEpoch
        ? record.endMs
        : period.end.millisecondsSinceEpoch;
    if (end <= start) return 0;
    return ((end - start) / 60000).round();
  }

  static String _formatEpochMillis(int value) {
    return _formatDateTime(DateTime.fromMillisecondsSinceEpoch(value));
  }

  static String _formatDateTime(DateTime value) {
    return DateFormat('yyyy-MM-dd HH:mm').format(value.toLocal());
  }

  static String _formatDate(DateTime value) {
    return DateFormat('yyyy-MM-dd').format(value.toLocal());
  }

  static String _formatCompactDate(DateTime value) {
    return DateFormat('yyyyMMdd').format(value.toLocal());
  }

  static _DateRange? _resolveExplicitDateRange(String text) {
    final match = RegExp(
      r'(\d{4}-\d{2}-\d{2})\s*(?:至|到|-|~)\s*(\d{4}-\d{2}-\d{2})',
    ).firstMatch(text);
    if (match == null) return null;
    final start = DateTime.tryParse(match.group(1)!);
    final end = DateTime.tryParse(match.group(2)!);
    if (start == null || end == null) return null;
    final s = DateTime(start.year, start.month, start.day);
    final e = DateTime(end.year, end.month, end.day);
    if (e.isBefore(s)) return null;
    return _DateRange(
      label: '自定义',
      start: s,
      end: e.add(const Duration(days: 1)),
    );
  }

  static List<Map<String, dynamic>> _scopeTodosByTime(
    List<Map<String, dynamic>> todos, {
    String? userMessage,
    DateTime? now,
  }) {
    final base = todos.toList();
    final message = userMessage ?? '';
    final nowValue = now ?? DateTime.now();
    final period = _resolveCoursePeriod(message, nowValue);
    if (period == null) return base;
    return base.where((t) {
      final start = _parseFlexibleDateTime(
        t['startTime'] ??
            t['start_time'] ??
            t['createdDate'] ??
            t['created_date'],
      );
      final end = _parseFlexibleDateTime(
        t['endTime'] ?? t['end_time'] ?? t['dueDate'] ?? t['due_date'],
      );
      final fallback = start ?? end;
      if (start == null && end == null) return false;
      final s = start ?? fallback!;
      final e = end ?? s.add(const Duration(minutes: 1));
      return _dateRangeOverlaps(period.start, period.end, s, e);
    }).toList();
  }

  static List<CountdownItem> _scopeCountdownsByTime(
    List<CountdownItem> countdowns, {
    String? userMessage,
    DateTime? now,
  }) {
    final active = countdowns.where((c) => !c.isDeleted).toList();
    final message = userMessage ?? '';
    final nowValue = now ?? DateTime.now();
    final period = _resolveCountdownPeriod(message, nowValue);
    if (period == null) return active;
    return active.where((c) {
      final target = DateTime(
        c.targetDate.year,
        c.targetDate.month,
        c.targetDate.day,
      );
      return !target.isBefore(period.start) && target.isBefore(period.end);
    }).toList();
  }

  static _DateRange? _resolveCountdownPeriod(String text, DateTime now) {
    final explicit = _resolveExplicitDateRange(text);
    if (explicit != null) return explicit;

    final todayStart = DateTime(now.year, now.month, now.day);
    if (text.contains('今天') || text.contains('今日')) {
      return _DateRange(
        label: '今日',
        start: todayStart,
        end: todayStart.add(const Duration(days: 1)),
      );
    }
    if (text.contains('明天') || text.contains('明日')) {
      final start = todayStart.add(const Duration(days: 1));
      return _DateRange(
        label: '明日',
        start: start,
        end: start.add(const Duration(days: 1)),
      );
    }
    if (text.contains('本周') || text.contains('这周')) {
      final start = todayStart.subtract(Duration(days: now.weekday - 1));
      return _DateRange(
        label: '本周',
        start: start,
        end: start.add(const Duration(days: 7)),
      );
    }
    if (text.contains('最近') || text.contains('近期')) {
      return _DateRange(
        label: '最近14天',
        start: todayStart,
        end: todayStart.add(const Duration(days: 14)),
      );
    }
    final futureDays = _parseFutureDays(text);
    if (futureDays != null) {
      return _DateRange(
        label: '未来$futureDays天',
        start: todayStart,
        end: todayStart.add(Duration(days: futureDays)),
      );
    }
    return null;
  }

  static List<TodoPlanBlock> _scopePlanBlocksByTime(
    List<TodoPlanBlock> blocks, {
    String? userMessage,
    DateTime? now,
  }) {
    final active = blocks.where((b) => !b.isDeleted).toList();
    final message = userMessage ?? '';
    final nowValue = now ?? DateTime.now();
    final period = _resolveCoursePeriod(message, nowValue);
    if (period == null) return active;
    return active.where((b) {
      final start = DateTime.fromMillisecondsSinceEpoch(b.startTime);
      final end = DateTime.fromMillisecondsSinceEpoch(b.endTime);
      return _dateRangeOverlaps(period.start, period.end, start, end);
    }).toList();
  }

  static bool _dateRangeOverlaps(
    DateTime pStart,
    DateTime pEnd,
    DateTime itemStart,
    DateTime itemEnd,
  ) {
    return itemEnd.isAfter(pStart) && itemStart.isBefore(pEnd);
  }

  static DateTime? _parseFlexibleDateTime(dynamic raw) {
    if (raw == null) return null;
    final text = raw.toString().trim();
    if (text.isEmpty) return null;
    final numeric = int.tryParse(text);
    if (numeric != null) {
      if (numeric > 1000000000000) {
        return DateTime.fromMillisecondsSinceEpoch(numeric);
      }
      if (numeric > 1000000000) {
        return DateTime.fromMillisecondsSinceEpoch(numeric * 1000);
      }
    }
    return DateTime.tryParse(text);
  }
}

class _TimeLogPeriod {
  const _TimeLogPeriod({
    required this.label,
    required this.start,
    required this.end,
  });

  final String label;
  final DateTime start;
  final DateTime end;
}

class _FocusRecord {
  const _FocusRecord({
    required this.id,
    required this.title,
    required this.source,
    required this.startMs,
    required this.endMs,
    this.status,
  });

  factory _FocusRecord.fromTimeLog(TimeLogItem log) {
    return _FocusRecord(
      id: log.id,
      title: log.title,
      source: '补录',
      startMs: log.startTime,
      endMs: log.endTime,
    );
  }

  factory _FocusRecord.fromPomodoro(PomodoroRecord record) {
    final endMs =
        record.endTime ?? record.startTime + record.effectiveDuration * 1000;
    return _FocusRecord(
      id: record.uuid,
      title: record.todoTitle?.isNotEmpty == true ? record.todoTitle! : '番茄钟',
      source: '番茄钟',
      startMs: record.startTime,
      endMs: endMs,
      status: record.isCompleted ? '已完成' : '已中断',
    );
  }

  final String id;
  final String title;
  final String source;
  final int startMs;
  final int endMs;
  final String? status;

  int get minutes => ((endMs - startMs) / 60000).round();
}

class _DateRange {
  const _DateRange({
    required this.label,
    required this.start,
    required this.end,
  });

  final String label;
  final DateTime start;
  final DateTime end;
}
