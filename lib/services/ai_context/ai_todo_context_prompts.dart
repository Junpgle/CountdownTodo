part of '../ai_todo_context_builder.dart';

const int _actionProtocolVersion = 2;

const String _dynamicSuggestionRules = '''
【AI动态下一步建议】
建议只由模型结合本轮用户请求、助手最终回复和实际查询结果即时生成；应用没有固定建议清单，不得把功能目录或通用开场问题当作建议栏内容。
建议数量为0-4条，默认输出0条；只有本轮确有自然、具体且有帮助的后续时才输出。每条必须明确承接本轮提到的事项、对象、数据或结果，并包含可从本轮内容核对的具体依据；每条不超过15字。
不要输出功能菜单、通用引导、欢迎语、泛化问句或与本轮无关的查询；不要按照固定主题轮流填充建议栏，也不要复用常见问题清单。只从本轮结果中挑选可继续处理的具体事项，或提出与当前操作卡直接相关的字段调整。
已有待确认操作卡时，只能建议调整卡片中与本轮有关的具体字段；不要建议用户在聊天里回复“确认”来保存，也不要用通用问题填充建议栏。
没有合适后续时完全省略建议块（相当于0条），不要为了填充建议栏而提问。建议只在用户点击后发起下一轮请求，不能据此直接执行写操作；写操作仍须生成待确认操作卡并等待用户确认。
格式：[SUGGEST_START]["建议1","建议2"][SUGGEST_END]
''';

String _buildLeanSystemPrompt({
  required String customPrompt,
  required bool promptEnabled,
  bool nativeToolCalls = false,
  bool queryTools = false,
  bool settingsNavigation = true,
  bool memoryEnabled = false,
  String memoryPromptBlock = '',
  DateTime? now,
}) {
  final nowValue = now ?? DateTime.now();
  final nowText =
      '${AppTimeFormats.fullDateTime(nowValue)} (${_formatTimeZone(nowValue)})';
  final basePrompt = promptEnabled && customPrompt.trim().isNotEmpty
      ? customPrompt
      : ChatStorageService.defaultPrompt;
  var resolvedBasePrompt = ChatStorageService.ensureCurrentPromptProtocol(
    basePrompt,
  );
  if (nativeToolCalls) {
    resolvedBasePrompt = ChatStorageService.removeCurrentTextProtocol(
      resolvedBasePrompt,
    );
  }
  final hasInjectedNow = resolvedBasePrompt.contains('{now}');
  resolvedBasePrompt = resolvedBasePrompt
      .replaceAll('{now}', nowText)
      .replaceAll('{todos}', queryTools ? '待办需按需调用查询工具读取' : '待办将按需通过智能上下文注入');
  resolvedBasePrompt = _compactCapabilitySection(resolvedBasePrompt);
  final fallbackNowLine = hasInjectedNow ? '' : '当前基准时间：$nowText。\n';
  final sharedRules = nativeToolCalls
      ? '''【全局规则】
$fallbackNowLine所有时间按本地时间理解，并以当前基准时间和括号中的时区判断相对日期；未指定年份的月份或日期默认按当前基准时间所在年份理解。
待办表示待完成的结果；规划块是可调整的执行时段；课程、会议、预约等外部约束是固定日程。没有日期和具体时间时不要默认今天全天。
重复是周期机制，不等于习惯；周期事项未明确选择习惯或循环待办时先询问。循环修改默认只作用于本期，只有用户明确要求才作用于本期及以后。
当本轮提供了与用户明确写入请求匹配的propose_*工具且信息完整时，必须调用对应工具生成待确认草案；不得只用自然语言声称已完成。工具调用只生成待确认草案，不直接保存或删除。query_*工具用于只读查询，可按需调用。不确定对象或缺少关键信息时先查询或追问，不得伪造参数。
原生函数调用模式下，正文不得输出[ACTION_START]、[FINANCE_START]、[FINANCE_ACTION_START]或[SETTINGS_START]协议块；所有操作只能通过本轮开放的函数工具提交。
用户已要求生成规划或已同意方案时，必须调用propose_cdt_actions生成实际确认卡，Markdown表格不等于草案。只要时间范围和任务已明确，时长、顺序等偏好可给出可编辑建议，不必反复要求用户确认后才生成草案。保存只能由用户点击App确认卡完成，聊天回复“确认/要的/可以”只表达方案意图，绝不保存，也不要要求用户继续回复确认以保存。
'''
      : '''【时间规则】
$fallbackNowLine所有上下文时间均为本地时间，格式为yyyy-MM-dd HH:mm。判断今天、昨天、明天时必须以当前基准时间和括号中的时区为准，不要按UTC重新换算；未指定年份的月份或日期默认按当前基准时间所在年份理解。

【动作输出规则】
当用户明确要求管理数据时，按本轮动作协议输出对应操作块；只按用户明确意图生成，信息不足时先追问。具体动作、字段和确认要求按本轮协议执行。''';
  final memoryBlock = memoryEnabled
      ? '\n\n${AiMemoryService.buildInstructionPrompt(nativeToolCalls: nativeToolCalls)}'
            '${memoryPromptBlock.trim().isNotEmpty ? '\n\n${memoryPromptBlock.trim()}' : ''}'
      : '';
  return '$resolvedBasePrompt\n\n$sharedRules\n\n$_dynamicSuggestionRules\n\n'
      '历史消息中的READ_ONLY_TOOL_HISTORY等上下文块只供参考，不要在回复中复述其标记或JSON。'
      '只有实际输出操作调用或操作块后才能说已生成待确认草案。'
      '$memoryBlock'
      '${settingsNavigation ? '\n\n${AiSettingsNavigationService.buildPrompt(nativeToolCalls: nativeToolCalls)}' : ''}';
}

String _compactCapabilitySection(String text) {
  final pattern = RegExp(r'【你的能力】[\s\S]*?(?=\n【|$)');
  if (!pattern.hasMatch(text)) return text;
  return text.replaceFirst(pattern, '【你的能力】\n按本轮动作协议执行，仅保留当前问题相关能力。');
}

String _buildActionProtocolPrompt(
  String userMessage, {
  String previousUserMessage = '',
  String previousAssistantMessage = '',
  List<Team> availableTeams = const [],
}) {
  final resolvedCreationRequest = _inheritExplicitCreationClarification(
    userMessage,
    previousUserMessage: previousUserMessage,
    previousAssistantMessage: previousAssistantMessage,
  );
  final isCreationClarificationFollowUp =
      resolvedCreationRequest != userMessage.trim();
  userMessage = resolvedCreationRequest;
  final pendingCountdownTitleSuffix = _pendingCountdownTitleSuffixForRequest(
    userMessage,
    previousUserMessage: previousUserMessage,
    previousAssistantMessage: previousAssistantMessage,
  );
  final hasRequestedCountdownTeam =
      AiTeamBindingResolver.hasExplicitBindingIntent(userMessage);
  final requestedCountdownTeam = AiTeamBindingResolver.requestedTeam(
    userMessage,
    teams: availableTeams,
  );
  final actions = <String>[];
  void add(String line) {
    if (!actions.contains(line)) actions.add(line);
  }

  if (isCreationClarificationFollowUp) {
    add(
      '- 创建澄清续答：本轮是在补充上一轮明确创建请求的参数；继续使用同一创建类型解释字段并生成草案，不要把日期、时长、频率等答复误分类成其他操作。',
    );
  }

  final isPlanningRequest =
      _matchesAny(userMessage, _planKeywords) ||
      _matchesAny(userMessage, _planningKeywords) ||
      (_matchesAny(userMessage, const ['安排']) &&
          (_matchesAny(userMessage, const ['待办', '任务']) ||
              _matchesAny(userMessage, _planningTimeKeywords)) &&
          !_matchesAny(userMessage, _fixedScheduleEventKeywords));
  final hasExplicitCreateIntent =
      _isExplicitTodoCreationRequest(userMessage) ||
      _createTodoKeywords.any(
        (verb) =>
            _isExplicitlyRequested(userMessage, verb) &&
            _hasExplicitActionPrefix(userMessage, verb),
      );
  final habitCreationFollowUp = _isHabitCreationFollowUp(
    userMessage,
    previousAssistantMessage,
  );
  final habitUpdateFollowUp = _isHabitMutationFollowUp(
    userMessage,
    previousAssistantMessage,
    verbs: _habitUpdateKeywords,
  );
  final habitDeleteFollowUp = _isHabitMutationFollowUp(
    userMessage,
    previousAssistantMessage,
    verbs: _habitDeleteKeywords,
  );
  final mentionsHabit =
      _matchesAny(userMessage, _habitKeywords) ||
      userMessage.toLowerCase().contains('habit') ||
      habitCreationFollowUp ||
      habitUpdateFollowUp ||
      habitDeleteFollowUp;
  final explicitlyTargetsHabit =
      _matchesAny(userMessage, _habitTypeKeywords) ||
      userMessage.toLowerCase().contains('habit') ||
      habitCreationFollowUp ||
      habitUpdateFollowUp ||
      habitDeleteFollowUp;
  final explicitlyTargetsTodo = _isExplicitlyTargetingTodo(userMessage);
  final habitUpdateRequested =
      habitUpdateFollowUp ||
      (mentionsHabit &&
          _habitUpdateKeywords.any(
            (word) => _isExplicitlyRequested(userMessage, word),
          ));
  final habitDeleteRequested =
      habitDeleteFollowUp ||
      (mentionsHabit &&
          _habitDeleteKeywords.any(
            (word) => _isExplicitlyRequested(userMessage, word),
          ));
  final requestsHabitAction =
      habitCreationFollowUp ||
      habitUpdateRequested ||
      habitDeleteRequested ||
      _isExplicitHabitCreationRequest(userMessage) ||
      (mentionsHabit &&
          (hasExplicitCreateIntent ||
              _matchesAny(userMessage, _habitCreationKeywords)));
  final unresolvedHabitTodoChoice =
      !isPlanningRequest &&
      _matchesAny(userMessage, _recurrenceKeywords) &&
      !explicitlyTargetsHabit &&
      !explicitlyTargetsTodo &&
      !_matchesAny(userMessage, _fixedScheduleKeywords) &&
      !_matchesAny(userMessage, _existingTodoKeywords);
  final ambiguousHabitTodoChoice =
      unresolvedHabitTodoChoice && !_looksLikeInformationQuestion(userMessage);
  final contextualTodoMutation =
      _shouldInheritContext(
        userMessage,
        previousUserMessage,
        _shouldInjectTodoContext,
      ) &&
      _matchesAny(userMessage, _existingTodoKeywords);
  final declinedOperation = _isExplicitOperationDecline(userMessage);
  final readOnlyRequest = declinedOperation || _isReadOnlyRequest(userMessage);
  final planningActions = declinedOperation || !isPlanningRequest
      ? <String>{}
      : _explicitPlanningActionNames(userMessage);
  final countdownOnlyMutationRequest =
      _isExplicitCountdownMutationRequest(userMessage) &&
      !explicitlyTargetsTodo;
  final requestsTodoAction =
      !countdownOnlyMutationRequest &&
      !readOnlyRequest &&
      (!requestsHabitAction ||
          (habitCreationFollowUp
              ? _matchesAny(userMessage, const ['待办', '任务', 'todo'])
              : explicitlyTargetsTodo)) &&
      !unresolvedHabitTodoChoice &&
      (contextualTodoMutation ||
          _shouldInjectTodoContext(userMessage) ||
          _matchesAny(userMessage, const ['提醒我', '记得']) ||
          _isExplicitTodoCreationRequest(userMessage) ||
          _matchesAny(userMessage, _recurrenceKeywords) ||
          userMessage.contains('待办') ||
          userMessage.contains('任务'));
  final scheduleActions = declinedOperation
      ? <String>{}
      : _explicitScheduleActionNames(userMessage);
  final requestsFinanceAction =
      !declinedOperation &&
      (_matchesAny(userMessage, _financeKeywords) ||
          userMessage.contains('#记账') ||
          userMessage.contains('账单') ||
          RegExp(r'\d+(?:\.\d+)?\s*(?:元|块(?:钱)?|人民币|¥|￥)')
              .hasMatch(userMessage));
  final financeDraftIntent = _shouldOfferFinanceDraftProposal(userMessage);
  final financeMutationIntent =
      _hasExplicitFinanceUpdateIntent(userMessage) ||
      _hasExplicitFinanceDeleteIntent(userMessage);
  if (requestsTodoAction && _hasExplicitTodoCreationIntent(userMessage)) {
    add(
      '- create_todo: {"action":"create_todo","todos":[{"title":"标题","remark":"备注","timeMode":"unscheduled|dateOnly|deadline","dueDate":null,"groupId":null,"reminderMinutes":5,"recurrence":"none|daily|weekly|monthly|yearly|weekdays|customDays","customIntervalDays":null,"recurrenceEndDate":null}]}；多个事项分别作为数组条目，每条独立填写标题和备注。用户明确说“备注是六月”等内容时，remark原样写“六月”，不得改写成“截止时间：六月”或把它当dueDate；只有明确要求截止日期/时间时才设置dueDate，否则timeMode="unscheduled"且dueDate=null',
    );
  }
  if (requestsTodoAction && !isPlanningRequest) {
    add(
      '- update_todo / complete_todo / skip_todo / delete_todo / reschedule_todo / bulk_reschedule / categorize_todo: 必须带真实期次todoId；循环期次可带recurrenceSeriesId校验系列',
    );
    add(
      '- 循环作用域: recurrenceScope="occurrence"只操作该期（默认）；recurrenceScope="future"操作该期及以后。只有用户明确说“整个系列/所有期次/所有周期”时，update_todo 才可用 recurrenceScope="series" 修改所有已生成期次的内容；series 保留各期完成/跳过状态且不得修改频率、间隔或结束规则。修改循环规则或结束循环必须用future；完成、跳过、删除始终不能用series',
    );
  }
  if (requestsTodoAction && !isPlanningRequest) {
    add('- split_todo / merge_todos: 拆分合并需 sourceTodoId/sourceTodoIds');
  }
  if (requestsHabitAction && !readOnlyRequest) {
    if (!habitUpdateRequested && !habitDeleteRequested) {
      add(
        '- create_habit: {"action":"create_habit","habits":[{"name":"习惯名称","icon":"🎯","sourceType":"quantityCheckIn|timeCheckIn|durationCheckIn|pomodoroTag|recurringTodo","periodType":"daily|weekly|weekdays|monthly|custom","targetValue":1600,"unit":"ml","durationMinutes":30,"targetTimeMinute":420,"timeComparison":"before|after","timeToleranceMinutes":0,"weekdaysMask":127,"customIntervalDays":null,"dayBoundaryMinute":0,"quickValues":[200,500],"sourceIds":[],"displayMode":"habitOnly|todoOnly|both","defaultFocusMinutes":25,"reminderPolicy":{"fixedTimes":[480],"progressReminder":false,"nearEndReminder":false,"dailySummaryReminder":false}}]}',
      );
      add(
        '- 习惯创建规则：明确创建习惯时必须使用create_habit，不能用普通待办动作代替。数量目标使用quantityCheckIn并填写targetValue/unit；时间点目标使用timeCheckIn并填写targetTimeMinute（分钟数）和timeComparison；时长目标使用durationCheckIn并填写durationMinutes；只有上下文提供真实番茄标签UUID时才使用pomodoroTag并填写sourceIds，否则使用durationCheckIn；完成一次型目标使用recurringTodo，独立打卡不再创建循环待办。periodType为weekdays时用weekdaysMask（周一bit0至周日bit6），custom时必须填写customIntervalDays。',
      );
      if (habitCreationFollowUp) {
        add('- 习惯草案续答：上一条助手正在收集创建习惯的参数，本轮是该习惯的补充信息；不要转成一次性的专注记录或普通待办。');
      }
    }
    if (habitUpdateRequested) {
      add(
        '- update_habit: {"action":"update_habit","updates":[{"habitUuid":"必须复制query_habits返回的真实ID","title":"现有习惯名称，仅用于确认卡标识","name":"新名称","icon":"🎯","displayMode":"habitOnly|todoOnly|both","defaultFocusMinutes":25,"targetValue":2000,"unit":"ml","durationMinutes":30,"targetTimeMinute":420,"timeComparison":"before|after","timeToleranceMinutes":0,"periodType":"daily|weekly|weekdays|monthly|custom","weekdaysMask":127,"customIntervalDays":3,"dayBoundaryMinute":0,"quickValues":[200,500],"reminderPolicy":{"fixedTimes":[480],"progressReminder":false,"nearEndReminder":false,"dailySummaryReminder":false},"effectiveFromOption":"today|nextPeriod|all"}]}。title用于确认卡标识，若不改名请填写query_habits返回的现有名称；name才是要修改的新名称。只传用户明确要改的字段；规则默认today生效，只有用户明确要求下周期或覆盖全部历史目标时才用nextPeriod或all。修改已有习惯前先用query_habits读取真实ID和规则，不要更换习惯来源类型。',
      );
    }
    if (habitDeleteRequested) {
      add(
        '- delete_habit: {"action":"delete_habit","updates":[{"habitUuid":"必须复制query_habits返回的真实ID","title":"query_habits返回的习惯名称，仅用于确认卡标识"}]}。只删除用户明确指定的习惯；这是软删除习惯目标和规则，不会删除其来源待办或专注记录。',
      );
    }
  }
  if (ambiguousHabitTodoChoice) {
    add('- 创建类型不明确：用户只描述了周期性事项但没有说明要创建为习惯还是待办。先询问“要创建成习惯，还是循环待办？”，不要输出任何创建动作。');
  }
  if (!readOnlyRequest) {
    if (scheduleActions.contains('create_schedule')) {
      add(
        '- create_schedule: {"action":"create_schedule","schedules":[{"title":"日程名","date":"YYYY-MM-DD","startTime":"YYYY-MM-DD HH:mm或null","endTime":"YYYY-MM-DD HH:mm或null","location":null,"remark":null,"reminderMinutes":[15],"recurrence":"none|daily|weekly|monthly|yearly|weekdays|customDays","customIntervalDays":null,"recurrenceEndDate":null}]}',
      );
    }
    if (scheduleActions.contains('update_schedule')) {
      add(
        '- update_schedule: {"action":"update_schedule","updates":[{"scheduleId":"真实期次ID","recurrenceSeriesId":"可选系列ID","recurrenceScope":"occurrence|future","title":"新标题","date":"YYYY-MM-DD","startTime":null,"endTime":null,"location":null,"remark":null,"reminderMinutes":[],"recurrence":"none|daily|weekly|monthly|yearly|weekdays|customDays","customIntervalDays":null,"recurrenceEndDate":null}]}。字段缺省=保持，null=清空；startTime=null同时清空结束时间，表示时间待定；修改重复规则必须使用future',
      );
    }
    if (scheduleActions.contains('cancel_schedule')) {
      add(
        '- cancel_schedule: 必须带真实scheduleId；默认只取消本期，只有用户明确说本期及以后时才用recurrenceScope="future"',
      );
    }
    if (scheduleActions.contains('delete_schedule')) {
      add(
        '- delete_schedule: 必须带真实scheduleId；默认只删除本期，只有用户明确说本期及以后时才用recurrenceScope="future"',
      );
    }
  }
  if (requestsFinanceAction) {
    if (!readOnlyRequest && financeDraftIntent) {
      add(
        '- 记账草案：回复正文末尾追加 [FINANCE_START]...[FINANCE_END]，其中必须是JSON数组；每笔使用 {"type":"expense|income|refund","amount":28.50,"amount_minor":"2850","category":"餐饮","categoryUuid":null,"merchant":"午餐","date":"YYYY-MM-DD","paymentMethod":"微信","paymentMethodUuid":null,"note":"备注"}；amount单位为元，amount_minor是人民币分的十进制整数文本且优先于amount，金额需要精确到分时填写amount_minor；缺失的可选字段用null；若提供本地记账目录，UUID只能复制目录中的真实值；只生成草案并告知用户在应用显示的“待确认记账”卡片中核对后点击“编辑并保存”；聊天中的“确认/确定”不会保存账单，不得承诺收到文字确认后代为保存，也不得声称已保存',
      );
      add(
        '- 记账与取餐码双识别：同一条消息同时包含账单和取餐/取件信息时，两者都保留，记账放FINANCE块，取餐放ACTION块，禁止二选一',
      );
      add('- 只记账时不要为了凑协议生成空的ACTION块；FINANCE块独立于ACTION块，账单只作为待确认草案，不要声称已保存');
    }
    add(
      '- finance_summary / finance_list：查询已有账单时使用 [FINANCE_ACTION_START]...[FINANCE_ACTION_END]，分别输出 {"action":"finance_summary","from":"YYYY-MM-DD","to":"YYYY-MM-DD"} 或 {"action":"finance_list","from":"YYYY-MM-DD","to":"YYYY-MM-DD","keyword":null,"type":null,"limit":20}；上下文已有汇总和明细时，正文要直接回答用户，不要假装执行了写入',
    );
    if (!readOnlyRequest && financeMutationIntent) {
      add(
        '- update_finance：只允许引用记账上下文里的真实transactionId，使用 {"action":"update_finance","transactionId":"真实ID","type":"expense|income|refund","amount":28.50,"amount_minor":"2850","category":"餐饮","merchant":"商家","date":"YYYY-MM-DD","paymentMethod":"微信","note":"备注"}；amount单位为元，amount_minor是人民币分的十进制整数文本且优先于amount，金额需要精确到分时填写amount_minor；只填写用户要改的字段，先生成待确认修改，不得直接保存',
      );
      add(
        '- delete_finance：只允许引用记账上下文里的真实transactionId，使用 {"action":"delete_finance","transactionId":"真实ID","reason":"用户要求删除"}；先生成待确认删除，不得直接删除；找不到唯一账单时先追问日期、商家或金额',
      );
      add(
        '- 记账操作安全：绝不编造transactionId；查询只读，修改/删除必须等用户在确认卡中操作；同一消息既有新增账单又有已有账单操作时，分别放FINANCE块和FINANCE_ACTION块',
      );
    }
  }
  if (!readOnlyRequest && planningActions.contains('create_plan_block')) {
    add(
      '- 规划优先规则：把上下文中已有待办安排到可调整执行时段时，必须使用create_plan_block；禁止用create_todo复制已有待办。每个已有待办都要使用真实todoId',
    );
    add(
      '- create_plan_block前提：先查询待办取得真实ID；查询后确实没有对应待办时，blocks条目使用newTodoTitle填写待建标题并省略todoId。App会在同一张规划确认卡中显示“新建待办并安排”，用户点击后才创建待办并关联规划。不得编造ID，不得声称已创建；已有待办必须用真实todoId，不能用newTodoTitle复制已有待办。',
    );
    add(
      '- create_plan_block: {"action":"create_plan_block","blocks":[{"todoId":"已有待办ID（新事项省略此字段并填写newTodoTitle）","newTodoTitle":"仅无对应待办时的待建标题","title":"规划标题","startTime":"YYYY-MM-DD HH:mm","dueDate":"YYYY-MM-DD HH:mm","durationMinutes":60,"reminderMinutes":5}]}',
    );
  }
  if (!readOnlyRequest && planningActions.contains('update_plan_block')) {
    add('- update_plan_block: 必须带真实planBlockId，只修改用户明确指定的字段');
  }
  if (!readOnlyRequest && planningActions.contains('reschedule_plan_blocks')) {
    add('- reschedule_plan_blocks: 必须带真实planBlockId；仅按用户明确指定的时间改期');
  }
  if (!readOnlyRequest && planningActions.contains('delete_plan_block')) {
    add('- delete_plan_block: 必须带真实planBlockId，只删除用户明确指定的规划块');
  }
  if (!readOnlyRequest && planningActions.contains('skip_plan_block')) {
    add('- skip_plan_block: 必须带真实planBlockId，只跳过用户明确指定的规划块');
  }
  if (!readOnlyRequest &&
      planningActions.contains('start_plan_block_pomodoro')) {
    add(
      '- start_plan_block_pomodoro: 必须带真实planBlockId，只能为用户明确指定的规划块打开番茄钟工作台并预绑定待办；等待用户在工作台手动开始计时',
    );
  }
  final focusActions = _explicitFocusActionNames(userMessage);
  if (!readOnlyRequest &&
      (!habitCreationFollowUp ||
          focusActions.isNotEmpty ||
          _isExplicitFocusMutationRequest(userMessage))) {
    if (focusActions.contains('create_time_log')) {
      add(
        '- create_time_log: {"action":"create_time_log","logs":[{"title":"专注内容","startTime":"YYYY-MM-DD HH:mm","dueDate":"YYYY-MM-DD HH:mm","durationMinutes":60,"remark":"备注","tagUuids":[]}]}',
      );
    }
    if (focusActions.contains('update_time_log')) {
      add(
        '- update_time_log: {"action":"update_time_log","updates":[{"logId":"日志ID","title":"新标题","startTime":"YYYY-MM-DD HH:mm","dueDate":"YYYY-MM-DD HH:mm","durationMinutes":60,"remark":"备注","tagUuids":[]}]}',
      );
    }
    if (focusActions.contains('delete_time_log')) {
      add(
        '- delete_time_log: {"action":"delete_time_log","updates":[{"logId":"日志ID"}]}',
      );
    }
    if (focusActions.contains('start_pomodoro')) {
      add(
        '- start_pomodoro: {"action":"start_pomodoro","title":"专注内容","todoId":"可选待办ID","durationMinutes":25,"tagUuids":[]}',
      );
    }
    if (focusActions.contains('stop_pomodoro')) {
      add('- stop_pomodoro: {"action":"stop_pomodoro","status":"completed"}');
    }
  }
  if (!readOnlyRequest) {
    final countdownActions = _explicitCountdownActionNames(userMessage);
    if (pendingCountdownTitleSuffix != null) {
      countdownActions.add('create_countdown');
    }
    if (countdownActions.contains('create_countdown')) {
      add(
        '- create_countdown: {"action":"create_countdown","countdowns":[{"title":"事件","dueDate":"YYYY-MM-DD HH:mm"}]}',
      );
      add(
        '- create_countdown 团队归属：用户明确指定团队时，先按本地团队上下文匹配唯一现有团队，并将其规范名称写入每条对应倒计时的teamName；重发已有待确认草案时保留原teamName，除非用户本轮明确更改团队。团队名只放teamName字段，不得拼入title；不得新造或使用未匹配团队。',
      );
      if (pendingCountdownTitleSuffix != null) {
        final teamReplacementRule = requestedCountdownTeam != null
            ? '本轮用户还明确指定了本地团队「${requestedCountdownTeam.name}」，所有替换草案都必须设置为该团队的teamName，覆盖旧teamName。'
            : hasRequestedCountdownTeam
            ? '本轮用户指定的团队无法在本地团队列表中唯一匹配，不得伪造或保留该团队绑定；应说明无法匹配并请用户从本地团队中选择。'
            : '逐条保留原teamName和原团队绑定。';
        add(
          '- create_countdown 待确认草案标题修订：用户要求批量给未保存草案的标题追加“$pendingCountdownTitleSuffix”。读取$_pendingCountdownDraftsContextMarker中的全部草案，以propose_cdt_actions调用create_countdown重发完整替换集合；每条保留原dueDate，只在原标题末尾追加该文字（已包含时不要重复追加）；$teamReplacementRule 这是替换待确认草案，不是创建额外事项；不得使用需要真实countdownId的update_countdown。只有工具成功返回并由应用生成了完整新草案卡后，才能说标题已经更新。',
        );
      }
    }
    if (countdownActions.contains('update_countdown')) {
      add(
        '- update_countdown: {"action":"update_countdown","updates":[{"countdownId":"倒计时ID","title":"新标题","dueDate":"YYYY-MM-DD HH:mm"}]}',
      );
      add(
        '- update_countdown字段规则：只修改用户明确指定的字段；只改标题时仅填写title，不使用titleSnapshot，不填写dueDate或startTime，也不改teamName。',
      );
      if (userMessage.contains('未定') &&
          _matchesAny(userMessage, const ['标题前面', '标题开头'])) {
        add(
          '- update_countdown标题规则：用户要求将标题末尾的“未定”移到开头并加连字符时，每条title设为“未定-”加原标题删除末尾“未定”后的文本；已经以“未定-”开头时不要重复添加。',
        );
      }
    }
    if (countdownActions.contains('complete_countdown')) {
      add(
        '- complete_countdown: {"action":"complete_countdown","updates":[{"countdownId":"倒计时ID"}]}',
      );
    }
    if (countdownActions.contains('delete_countdown')) {
      add(
        '- delete_countdown: {"action":"delete_countdown","updates":[{"countdownId":"倒计时ID"}]}',
      );
    }
  }
  if (!readOnlyRequest &&
      (_matchesAny(userMessage, _groupManagementKeywords) ||
          _isExplicitManagementRequest(userMessage, _groupKeywords))) {
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
  final targetsTodoTag =
      _matchesAny(userMessage, const ['待办', '任务', 'todo']) &&
      !_matchesAny(userMessage, const ['番茄', '专注']);
  if (!readOnlyRequest &&
      !targetsTodoTag &&
      (_matchesAny(userMessage, _tagManagementKeywords) ||
          _isExplicitManagementRequest(userMessage, const [
            '番茄标签',
            '专注标签',
            '番茄 tag',
            'pomodoro tag',
          ]))) {
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
    add(
      unresolvedHabitTodoChoice
          ? '- 本轮不生成结构化创建操作：如果用户是在咨询周期性安排，直接回答；如果用户想创建但未选择类型，先询问习惯或循环待办'
          : mentionsHabit
          ? '- 本轮是习惯信息咨询，不要生成结构化操作'
          : '- 本轮不生成结构化操作：直接回答用户问题；只有用户明确提出增删改操作时才输出操作块，意图不明确先追问',
    );
  }

  final financeActionProtocol = readOnlyRequest
      ? '''记账查询格式（只读）：
[FINANCE_ACTION_START]
[{"action":"finance_summary|finance_list"}]
[FINANCE_ACTION_END]
'''
      : '''记账动作块格式（查询/修改/删除已有账单时使用）：
[FINANCE_ACTION_START]
[{"action":"finance_summary|finance_list|update_finance|delete_finance"}]
[FINANCE_ACTION_END]
''';

  return '''【本轮可用动作（按需精简）】
${actions.join('\n')}

动作块格式（CDT Actions v$_actionProtocolVersion，必须）：
[ACTION_START]
{"protocol":"cdt.actions","version":$_actionProtocolVersion,"actions":[{"action":"..."}]}
[ACTION_END]

输出约束：只允许输出上述 v$_actionProtocolVersion 信封，不输出裸 JSON 数组。

$financeActionProtocol

字段约束（必须）：
- 仅操作已有对象时必须携带对应ID（todoId / scheduleId / groupId / countdownId / tagId / planBlockId / logId）
- 时间字段统一使用 yyyy-MM-dd HH:mm（如 startTime / dueDate）
- 待办时间必须带timeMode：unscheduled无日期、dateOnly某天内完成、deadline具体截止时刻；null表示清空，字段缺省表示不修改
- 没有日期和时间的待办保持未安排，不得默认今天全天
- 只有日期没有具体时刻时才使用dateOnly；普通待办不要使用日期区间字段表达时间
- 单一时刻默认表示截止点，不得自动扩展为一小时执行区间
- 取件、取餐、取药默认是可完成的待办，不得仅为触发提醒而伪装成全天事件
- 考试、课程、会议、面试、预约、航班等外部决定时间的事项必须使用固定日程动作，不能静默创建为待办或规划块
- 固定日程date必填；时间待定时startTime/endTime均为null，只有开始时刻时endTime为null，明确区间才同时填写开始和结束
- 把已有待办安排到用户可调整的执行时段时使用create_plan_block
- 重复只表示周期机制，不得自动称为习惯
- 新建循环待办必须提供首次发生日期/截止点；recurrenceEndDate是最后一期日期，不是普通待办截止时间
- 上下文中同一recurrenceSeriesId下的每一条都是可独立寻址的真实期次；待办用todoId，日程用scheduleId，绝不能把seriesId当期次ID
- 用户没有明确“本期及以后/后续所有周期”时，循环待办和循环日程动作必须使用recurrenceScope="occurrence"；只有明确“整个系列/所有期次/所有周期”才能为 update_todo 使用series
- 危险操作（删除/取消日程、完成待办、停止）仅在用户明确要求时输出
- 账单查询可以直接回答上下文中的只读数据；修改和删除必须输出FINANCE_ACTION块并等待确认，不得直接保存或删除
- FINANCE_ACTION中的transactionId只能复制上下文中已有的真实ID，不能使用商家名、系列名或临时编号代替''';
}

String _buildSystemPrompt({
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
      '${AppTimeFormats.fullDateTime(nowValue)} (${_formatTimeZone(nowValue)})';
  final todoList = _formatTodos(todos, todoGroups);
  final scheduleList = _formatFixedSchedules(fixedSchedules, '', nowValue);
  final basePrompt = promptEnabled && customPrompt.trim().isNotEmpty
      ? customPrompt
      : ChatStorageService.defaultPrompt;

  final resolvedBasePrompt = ChatStorageService.ensureCurrentPromptProtocol(
    basePrompt,
  ).replaceAll('{now}', nowText).replaceAll('{todos}', todoList);

  return '''$resolvedBasePrompt

$_dynamicSuggestionRules

【用户当前固定日程】
$scheduleList

【时间规则】
所有上下文时间均为本地时间，格式为yyyy-MM-dd HH:mm。判断今天、昨天、明天时必须以当前基准时间和括号中的时区为准，不要按UTC重新换算。

【事项语义】
- 待办表示需要完成的结果；没有日期和时间时保持未安排，不能默认今天全天。
- 习惯表示需要按周期追踪的目标；用户明确创建习惯时必须使用create_habit，不能用循环待办代替。
- 如果用户只描述周期性事项（如“每天跑步”“每周整理房间”）但没有明确选择习惯或待办，必须先询问“要创建成习惯，还是循环待办？”，不要擅自生成任何创建动作。
- 只有日期没有具体时刻时表示“某天内完成”；单一时刻表示截止点，不能自动补一小时。
- 规划块表示用户自行安排、可以调整的执行时段。
- 考试、课程、会议、面试、预约、航班等外部固定时间属于固定日程，不是待办或规划块；创建或修改时必须使用日程动作。
- 取件、取餐、取药默认属于待办；可领取窗口不占用整个日历时段。只有必须按预约时刻到场时才属于固定日程。
- 重复是一种周期机制，不等于习惯；不得把每周周报、每月交租等称为习惯。
- 循环系列由多个可独立寻址的真实期次组成。recurrenceSeriesId只标识系列，不能代替todoId或scheduleId；每个期次必须使用自己的真实ID。
- 修改默认只作用于当前期次。只有用户明确说“本期及以后/后续所有周期”时才能使用future；修改循环规则或结束循环必须明确future。

【事项管理功能 - 重要规则】
当用户明确要求管理待办、习惯、固定日程、规划块、专注记录、番茄钟、倒计时、分类或标签时，必须在回复末尾附加JSON操作块。
操作已有对象必须使用上下文中的真实期次ID；固定日程使用scheduleId，循环系列ID不能代替期次ID。不确定时先追问。
JSON操作块必须且只能使用以下协议：
1. 必须用 [ACTION_START] 和 [ACTION_END] 包裹。
2. [ACTION_START] 内必须是 CDT Actions v$_actionProtocolVersion 信封：protocol="cdt.actions"、version=$_actionProtocolVersion、actions 为 JSON 数组。
3. 每个操作对象必须包含 "action" 字段。
4. 禁止使用 Markdown 代码块，例如 ```json。
5. 禁止使用任何旧版动作标记。
6. 禁止只输出 {"todos":[...]}、{"updates":[...]} 等缺少 "action" 字段的对象。
7. 如果同时输出操作块和建议块，顺序必须是：正文 -> [ACTION_START]...[ACTION_END] -> [SUGGEST_START]...[SUGGEST_END]。

唯一合法示例：
[ACTION_START]
{"protocol":"cdt.actions","version":2,"actions":[
{"action":"create_plan_block","blocks":[{"todoId":"已有待办ID","title":"标题快照","startTime":"YYYY-MM-DD HH:mm","dueDate":"YYYY-MM-DD HH:mm","durationMinutes":60,"remark":"备注","reminderMinutes":5}]}
]}
[ACTION_END]

支持的动作：

- create_todo: {"action":"create_todo","todos":[{"title":"标题","remark":"备注","timeMode":"unscheduled|dateOnly|deadline","dueDate":null,"recurrence":"none|daily|weekly|monthly|yearly|weekdays|customDays","customIntervalDays":null,"recurrenceEndDate":null,"groupId":null,"reminderMinutes":5}]}。循环待办必须给首次dueDate；创建后每一期有独立todoId
- create_habit: {"action":"create_habit","habits":[{"name":"习惯名称","icon":"🎯","sourceType":"quantityCheckIn|timeCheckIn|durationCheckIn|pomodoroTag|recurringTodo","periodType":"daily|weekly|weekdays|monthly|custom","targetValue":1600,"unit":"ml","durationMinutes":30,"targetTimeMinute":420,"timeComparison":"before|after","timeToleranceMinutes":0,"weekdaysMask":127,"customIntervalDays":null,"dayBoundaryMinute":0,"quickValues":[200,500],"sourceIds":[],"displayMode":"habitOnly|todoOnly|both","defaultFocusMinutes":25,"reminderPolicy":{"fixedTimes":[480],"progressReminder":false,"nearEndReminder":false,"dailySummaryReminder":false}}]}。数量、时间点、时长和完成一次型分别使用对应sourceType；pomodoroTag必须引用真实标签UUID
- create_schedule: {"action":"create_schedule","schedules":[{"title":"日程名","date":"YYYY-MM-DD","startTime":"YYYY-MM-DD HH:mm或null","endTime":"YYYY-MM-DD HH:mm或null","location":null,"remark":null,"reminderMinutes":[15],"recurrence":"none|daily|weekly|monthly|yearly|weekdays|customDays","customIntervalDays":null,"recurrenceEndDate":null}]}。date必填；时间待定时起止均为null；只有开始时刻时endTime为null
- update_schedule: {"action":"update_schedule","updates":[{"scheduleId":"真实期次ID","recurrenceSeriesId":"可选系列ID","recurrenceScope":"occurrence|future","title":"新标题","date":"YYYY-MM-DD","startTime":"YYYY-MM-DD HH:mm或null","endTime":"YYYY-MM-DD HH:mm或null","location":null,"remark":null,"reminderMinutes":[],"recurrence":"none|daily|weekly|monthly|yearly|weekdays|customDays","customIntervalDays":null,"recurrenceEndDate":null}]}。字段缺省=保持，null=清空；修改重复规则必须使用future
- cancel_schedule / delete_schedule: 使用scheduleId；默认occurrence，只有明确“本期及以后”才用future；日程没有待办式“完成勾选”
- create_plan_block: {"action":"create_plan_block","blocks":[{"todoId":"已有待办ID","title":"标题快照","startTime":"YYYY-MM-DD HH:mm","dueDate":"YYYY-MM-DD HH:mm","durationMinutes":60,"remark":"备注","reminderMinutes":5}]}，用于把已有待办安排到具体时间块；用户说"规划今天/明天/本周时间""安排到几点到几点"时优先使用这个动作。重要：规划中提到的每一个已有待办都必须生成对应的plan block，不要只生成一个
- update_plan_block / reschedule_plan_blocks / delete_plan_block / skip_plan_block / start_plan_block_pomodoro: 必须使用已有规划块ID(planBlockId/blockId/id)，用于修改、重排、删除、跳过或打开并预绑定某个规划块的番茄钟工作台；start_plan_block_pomodoro 不会自动开始计时
- update_todo: {"action":"update_todo","updates":[{"todoId":"真实期次ID","recurrenceSeriesId":"可选系列ID","recurrenceScope":"occurrence|future|series","title":"新标题","timeMode":"unscheduled|dateOnly|deadline","dueDate":"...","groupId":"...","reminderMinutes":5}]}。字段缺省=保持，字段为null=清空；series仅在用户明确要求修改整个系列时使用，且不能改重复规则或每期状态
- complete_todo: {"action":"complete_todo","updates":[{"todoId":"真实期次ID","recurrenceScope":"occurrence"}]}，循环完成状态永远属于单期
- skip_todo: {"action":"skip_todo","updates":[{"todoId":"真实重复期次ID"}]}，只跳过该UUID对应的一期；不得用标题猜测、不得跳过整个系列；只有用户明确说“跳过本期”或“略过本期”时提出，仍交给操作确认卡
- delete_todo: {"action":"delete_todo","updates":[{"todoId":"真实期次ID","recurrenceSeriesId":"可选系列ID","recurrenceScope":"occurrence|future"}]}
- reschedule_todo: {"action":"reschedule_todo","updates":[{"todoId":"真实期次ID","recurrenceScope":"occurrence|future","timeMode":"dateOnly|deadline|unscheduled","dueDate":"..."}]}
- bulk_reschedule: 同reschedule_todo，批量改期
- categorize_todo: {"action":"categorize_todo","updates":[{"todoId":"ID","groupId":"新分类ID或null（移出分类时）"}]}
- split_todo: {"action":"split_todo","sourceTodoId":"原ID","deleteSource":false,"todos":[...]}
- merge_todos: {"action":"merge_todos","sourceTodoIds":["ID1","ID2"],"deleteSources":false,"todo":{...}}
- create_time_log: {"action":"create_time_log","logs":[{"title":"专注内容","startTime":"YYYY-MM-DD HH:mm","dueDate":"YYYY-MM-DD HH:mm","durationMinutes":60,"remark":"备注","tagUuids":[]}]}
- update_time_log: {"action":"update_time_log","updates":[{"logId":"ID","title":"新标题","startTime":"...","dueDate":"...","durationMinutes":60,"remark":"备注","tagUuids":[]}]}
- delete_time_log: {"action":"delete_time_log","updates":[{"logId":"ID"}]}
- start_pomodoro: {"action":"start_pomodoro","title":"专注内容","todoId":"可选待办ID","durationMinutes":25,"tagUuids":[]}
- stop_pomodoro: {"action":"stop_pomodoro","status":"completed"}
- create_countdown: {"action":"create_countdown","countdowns":[{"title":"事件","dueDate":"YYYY-MM-DD HH:mm"}]}
- 倒计时团队归属：用户明确说“这些都是X的/属于X/绑定到X团队”等时，将X原名写入每条对应倒计时的teamName；团队名只放teamName字段，不得拼入title。只有上下文中的现有团队可绑定；未明确指定时省略teamName。
- update_countdown: {"action":"update_countdown","updates":[{"countdownId":"ID","title":"新标题","dueDate":"YYYY-MM-DD HH:mm"}]}
- complete_countdown: {"action":"complete_countdown","updates":[{"countdownId":"ID"}]}
- delete_countdown: {"action":"delete_countdown","updates":[{"countdownId":"ID"}]}
- create_todo_group: {"action":"create_todo_group","groups":[{"name":"分类名"}]}
- update_todo_group: {"action":"update_todo_group","updates":[{"groupId":"ID","name":"新分类名"}]}
- delete_todo_group: {"action":"delete_todo_group","updates":[{"groupId":"ID"}]}
- create_pomodoro_tag: {"action":"create_pomodoro_tag","tags":[{"name":"标签名","color":"#607D8B"}]}
- update_pomodoro_tag: {"action":"update_pomodoro_tag","updates":[{"tagId":"ID","name":"新名称","color":"#3B82F6"}]}
- delete_pomodoro_tag: {"action":"delete_pomodoro_tag","updates":[{"tagId":"ID"}]}

可组合多种操作：[ACTION_START]{"protocol":"cdt.actions","version":2,"actions":[{"action":"create_plan_block","blocks":[...]},{"action":"start_pomodoro","title":"专注内容","durationMinutes":25}]}[ACTION_END]

$_dynamicSuggestionRules

【核心规则】
1. 意图判定：先区分习惯目标、待办结果、外部固定日程和可调整规划块，再选择创建/修改/取消/完成/删除/改期/分类/拆分/合并等动作；习惯创建只用create_habit。周期性事项没有明确类型时先追问，不生成创建动作
2. 文件夹归类：只在语义明显关联时分配groupId，不确定时留空，严禁乱分类
3. 危险操作(删除或取消日程、删除或完成待办、合并删源、拆分删源、停止番茄钟、删除专注记录、完成或删除倒计时、删除番茄标签)只在用户明确要求时输出
4. 禁止对已有分类任务重复categorize_todo
5. [ACTION_START]/[ACTION_END]标记和[SUGGEST_START]/[SUGGEST_END]标记必须完整
6. 规划完整性：当用户要求规划时间（今天/明天/本周等），文本中提到的每一个时间段如果对应已有待办，都必须在[ACTION_START]中生成create_plan_block，不能只生成部分。如果文本中规划了5个时间段对应5个已有待办，action中必须有5个blocks
7. 规划避让：如果上下文提供固定日程、课程表、已有规划或专注记录，生成create_plan_block时必须避开硬约束和已占用时间
8. 循环期次：complete/skip永远只操作指定todoId；删除沿用occurrence或明确的future，不得series。普通修改默认occurrence；只有用户明确要求本期及以后时使用future，只有明确要求整个系列时 update_todo 才使用series，并保留各期状态及重复规则；结束循环用update_todo设置recurrence="none"、recurrenceScope="future"''';
}

String _buildPromptPreview({
  required String customPrompt,
  required bool promptEnabled,
  required List<Map<String, dynamic>> todos,
  required List<TodoGroup> todoGroups,
  DateTime? now,
}) {
  final nowValue = now ?? DateTime.now();
  final nowText =
      '${AppTimeFormats.fullDateTime(nowValue)} (${_formatTimeZone(nowValue)})';
  final basePrompt = promptEnabled && customPrompt.trim().isNotEmpty
      ? customPrompt
      : ChatStorageService.defaultPrompt;
  return ChatStorageService.ensureCurrentPromptProtocol(basePrompt)
      .replaceAll('{now}', nowText)
      .replaceAll('{todos}', _formatTodos(todos, todoGroups));
}

String _buildManualCopyPrompt(List<Map<String, dynamic>> messages) {
  final buffer = StringBuffer()
    ..writeln('请按下面的对话内容扮演效率助手，只回复 assistant 的最终内容。')
    ..writeln(
      '必须遵守 system 中的所有规则；如果需要创建、修改、规划或删除待办等数据，必须输出 [ACTION_START] JSON 操作块；如果需要新增记账，输出 [FINANCE_START]；如果需要查询、修改或删除已有账单，输出 [FINANCE_ACTION_START]。',
    )
    ..writeln('不要解释这些包装文本，不要使用 Markdown 代码块包裹操作 JSON。')
    ..writeln(_dynamicSuggestionRules);

  for (final message in messages) {
    final role = (message['role'] ?? 'user').toUpperCase();
    final content = message['content']?.toString() ?? '';
    buffer
      ..writeln()
      ..writeln('===== $role =====')
      ..writeln(content);
  }
  return buffer.toString().trim();
}
