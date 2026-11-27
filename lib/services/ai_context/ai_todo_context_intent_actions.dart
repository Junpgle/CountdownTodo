part of '../ai_todo_context_builder.dart';

const _pendingWriteProposalContextMarker = '[APP_PENDING_WRITE_PROPOSAL]';

const _pendingCountdownDraftsContextMarker = '[APP_PENDING_COUNTDOWN_DRAFTS]';

bool _matchesAny(String text, List<String> keywords) {
  return keywords.any((k) => text.contains(k));
}

bool _mentionsAvailableTeam(String text, List<Team> teams) => teams.any(
  (team) => team.name.trim().isNotEmpty && text.contains(team.name.trim()),
);

bool _isReadOnlyRequest(String text) {
  if (_isExplicitTodoCreationRequest(text)) return false;
  if (_isExplicitHabitCreationRequest(text)) return false;
  if (_isExplicitHabitMutationRequest(text)) return false;
  if (_isExplicitScheduleMutationRequest(text)) return false;
  if (_isExplicitCountdownMutationRequest(text)) return false;
  if (_hasExplicitFinanceUpdateIntent(text)) return false;
  if (_isExplicitFinanceDraftRequest(text)) return false;
  if (_isExplicitFocusMutationRequest(text)) return false;
  final asksInformation =
      _matchesAny(text, _readOnlyRequestKeywords) ||
      _looksLikeInformationQuestion(text) ||
      _matchesAny(text, _todoListQueryKeywords) ||
      _looksLikeTodoListQuery(text) ||
      _looksLikeFocusQuery(text) ||
      _looksLikeCountdownQuery(text);
  if (!asksInformation) return false;
  return !_writeIntentKeywords.any(
    (trigger) => _isExplicitlyRequested(text, trigger),
  );
}

/// Prevents short cancellations and declines from inheriting an earlier
/// write request or exposing unrelated proposal tools.
bool _isExplicitOperationDecline(String text) {
  final message = text.trim().toLowerCase().replaceAll(
    _rxAiCtxIntentActions1,
    '',
  );
  if (message.isEmpty) return false;

  const exactDeclines = {
    '算了',
    '那算了',
    '那就算了',
    '不用了',
    '不需要了',
    '暂时不用',
    '暂时不用了',
    '先不用',
    '先不用了',
    '取消',
    '取消吧',
    '撤销',
    '撤销吧',
    '放弃',
    '放弃吧',
    '不要了',
    '不做了',
    '先不做',
    '先不做了',
    '先不弄',
    '先不弄了',
    '不继续了',
    '不要继续了',
  };
  if (exactDeclines.contains(message)) return true;

  final cancelsCurrentOperation = _rxAiCtxIntentActions2;
  if (cancelsCurrentOperation.hasMatch(message)) return true;

  final cancelsProposedWrite = _rxAiCtxIntentActions3;
  if (cancelsProposedWrite.hasMatch(message)) return true;

  return _rxAiCtxIntentActions4.hasMatch(message);
}

bool _isExplicitScheduleMutationRequest(String text) {
  return _explicitScheduleActionNames(text).isNotEmpty;
}

Set<String> _explicitScheduleActionNames(String text) {
  const createVerbs = [
    '创建',
    '新建',
    '新增',
    '添加',
    '加个',
    '加一个',
    '记下',
    '记一下',
    '记录',
    '写进',
    '记入',
    '加入',
    '加到',
    '安排',
    '加一场',
    '排一场',
    '预约',
    '预订',
    '预定',
    '订一场',
    '订个',
    '订一个',
    '订一下',
    '订下',
    '定一场',
    '定个',
    '定一个',
    '定一下',
    '定下',
    '约一场',
    '约个',
    '约一个',
    '约一下',
    '约',
  ];
  const updateVerbs = ['修改', '更新', '更改', '调整', '改到', '改为', '改成', '调到', '改期'];
  const cancelVerbs = ['取消', '撤销'];
  const deleteVerbs = ['删除', '删掉', '删', '移除', '清掉'];
  final actions = <String>{};
  final targets = [..._fixedScheduleEventKeywords, '日程', '日历'];
  final clauses = text.split(_rxAiCtxIntentActions5);
  for (final clause in clauses) {
    if (!_matchesAny(clause, targets)) continue;
    void addWhenExplicit(List<String> verbs, String action) {
      for (final verb in verbs) {
        if (_isExplicitlyRequested(clause, verb) &&
            _hasExplicitActionPrefix(clause, verb)) {
          actions.add(action);
          return;
        }
      }
    }

    addWhenExplicit(createVerbs, 'create_schedule');
    addWhenExplicit(updateVerbs, 'update_schedule');
    addWhenExplicit(cancelVerbs, 'cancel_schedule');
    addWhenExplicit(deleteVerbs, 'delete_schedule');
  }
  return actions;
}

Set<String> _explicitPlanningActionNames(String text) {
  const planningTargets = [
    '规划',
    '计划',
    '待办',
    '任务',
    '规划块',
    '计划块',
    '时间块',
    '排时间',
    'plan block',
  ];
  const blockTargets = ['规划块', '计划块', '时间块', 'plan block'];
  const createVerbs = [
    '规划',
    '计划',
    '新建',
    '新增',
    '添加',
    '安排',
    '排一下',
    '排个',
    '排一个',
    '排时间',
    '排进',
    '排入',
    '加个',
    '加一个',
    '制定',
    '生成',
    '创建',
    '建立',
  ];
  const updateVerbs = ['修改', '更新', '更改', '调整'];
  const rescheduleVerbs = ['改期', '重排', '重新安排', '改到', '改成', '调整时间', '改时间'];
  const deleteVerbs = ['删除', '删掉', '删', '移除', '清掉', '取消'];
  const skipVerbs = ['跳过', '略过'];
  const startVerbs = ['开始', '启动'];
  final actions = <String>{};
  final clauses = text.split(_rxAiCtxIntentActions5);
  for (final clause in clauses) {
    void addWhenExplicit(List<String> verbs, String action) {
      for (final verb in verbs) {
        if (_isExplicitlyRequested(clause, verb) &&
            _hasExplicitActionPrefix(clause, verb)) {
          actions.add(action);
          return;
        }
      }
    }

    final hasPlanningTarget =
        _matchesAny(clause.toLowerCase(), planningTargets) ||
        (_matchesAny(clause, _planningTimeKeywords) &&
            !_matchesAny(clause, _fixedScheduleEventKeywords));
    if (hasPlanningTarget) {
      addWhenExplicit(createVerbs, 'create_plan_block');
    }
    if (!_matchesAny(clause.toLowerCase(), blockTargets)) continue;
    addWhenExplicit(updateVerbs, 'update_plan_block');
    addWhenExplicit(rescheduleVerbs, 'reschedule_plan_blocks');
    addWhenExplicit(deleteVerbs, 'delete_plan_block');
    addWhenExplicit(skipVerbs, 'skip_plan_block');
    addWhenExplicit(startVerbs, 'start_plan_block_pomodoro');
  }
  return actions;
}

bool _isHabitCreationFollowUp(
  String userMessage,
  String previousAssistantMessage,
) {
  final message = userMessage.trim();
  final previous = previousAssistantMessage.trim();
  if (message.isEmpty ||
      previous.isEmpty ||
      previous.contains(_pendingWriteProposalContextMarker) ||
      _isExplicitOperationDecline(message)) {
    return false;
  }

  final answersHabitTypeChoice = _rxAiCtxIntentActions6.hasMatch(message);
  final assistantOfferedHabitOrTodo =
      previous.contains('习惯') &&
      _matchesAny(previous, const ['待办', '任务']) &&
      _rxAiCtxIntentActions7.hasMatch(previous);
  if (answersHabitTypeChoice && assistantOfferedHabitOrTodo) return true;

  final offeredHabitDraft =
      previous.contains('习惯') && _rxAiCtxIntentActions8.hasMatch(previous);
  final requestedHabitDetails =
      _rxAiCtxIntentActions9.hasMatch(previous) ||
      (_rxAiCtxIntentActions10.hasMatch(previous) &&
          _rxAiCtxIntentActions11.hasMatch(previous));
  if (!offeredHabitDraft || !requestedHabitDetails) return false;

  final explicitlyTargetsOtherWrite =
      _isExplicitTodoCreationRequest(message) ||
      (_matchesAny(message, const ['待办', '任务', 'todo']) &&
          (_matchesAny(message, _createTodoKeywords) ||
              _matchesAny(message, _recurrenceKeywords) ||
              _matchesAny(message, _existingTodoKeywords))) ||
      (_matchesAny(message, _fixedScheduleKeywords) &&
          _matchesAny(message, _createTodoKeywords)) ||
      _isExplicitFocusMutationRequest(message) ||
      _isExplicitFinanceDraftRequest(message) ||
      _hasExplicitFinanceUpdateIntent(message);
  return !explicitlyTargetsOtherWrite && !_isReadOnlyRequest(message);
}

bool _isHabitMutationFollowUp(
  String userMessage,
  String previousAssistantMessage, {
  required List<String> verbs,
}) {
  final message = userMessage.trim();
  final previous = previousAssistantMessage.trim();
  if (message.isEmpty ||
      previous.isEmpty ||
      previous.contains(_pendingWriteProposalContextMarker) ||
      _isExplicitOperationDecline(message) ||
      _isExplicitTodoCreationRequest(message) ||
      _matchesAny(message, const ['待办', '任务', '日程', '账单', '专注记录'])) {
    return false;
  }
  final askedAboutHabitMutation =
      _matchesAny(previous, _habitKeywords) &&
      verbs.any((verb) => _matchesAny(previous, [verb])) &&
      (_rxAiCtxIntentActions10.hasMatch(previous) ||
          _rxAiCtxIntentActions12.hasMatch(previous));
  if (!askedAboutHabitMutation) return false;
  return !_looksLikeInformationQuestion(message);
}

/// Carries only an explicit creation request across an assistant's parameter
/// clarification. Short answers such as a title, date, or duration otherwise
/// lose the action type and can be routed to an unrelated tool.
String _inheritExplicitCreationClarification(
  String userMessage, {
  required String previousUserMessage,
  required String previousAssistantMessage,
}) {
  final message = userMessage.trim();
  final previousRequest = previousUserMessage.trim();
  final assistantReply = previousAssistantMessage.trim();
  final isIndependentQuestionOrLookup = _rxAiCtxIntentActions13.hasMatch(
    message,
  );
  if (message.isEmpty ||
      previousRequest.isEmpty ||
      assistantReply.isEmpty ||
      assistantReply.contains(_pendingWriteProposalContextMarker) ||
      message.contains(previousRequest) ||
      _isExplicitOperationDecline(message) ||
      isIndependentQuestionOrLookup ||
      _isHabitCreationFollowUp(message, assistantReply) ||
      _hasExplicitCreationIntent(message)) {
    return message;
  }

  final assistantAlreadyGeneratedProposal = _rxAiCtxIntentActions14.hasMatch(
    assistantReply,
  );
  if (assistantAlreadyGeneratedProposal ||
      !_hasExplicitCreationIntent(previousRequest)) {
    return message;
  }

  final assistantRequestsDetails =
      _rxAiCtxIntentActions15.hasMatch(assistantReply) ||
      (_rxAiCtxIntentActions10.hasMatch(assistantReply) &&
          _rxAiCtxIntentActions16.hasMatch(assistantReply));
  if (!assistantRequestsDetails) return message;

  return '$previousRequest\n$message';
}

bool _hasExplicitCreationIntent(String text) {
  if (_hasExplicitTodoCreationIntent(text) ||
      _explicitScheduleActionNames(text).contains('create_schedule') ||
      _explicitPlanningActionNames(text).contains('create_plan_block') ||
      _explicitFocusActionNames(text).any(
        (action) => action == 'create_time_log' || action == 'start_pomodoro',
      ) ||
      _explicitCountdownActionNames(text).contains('create_countdown') ||
      _isExplicitManagementRequest(text, _groupKeywords) ||
      _isExplicitManagementRequest(text, const [
        '番茄标签',
        '专注标签',
        '番茄 tag',
        'pomodoro tag',
      ])) {
    return true;
  }
  return false;
}

bool _hasExplicitTodoCreationIntent(String text) {
  const todoTargets = ['待办', '任务', 'todo'];
  const implicitTodoVerbs = ['提醒我', '记得'];
  const explicitCreateVerbs = [
    '新建',
    '新增',
    '创建',
    '添加',
    '加个',
    '加一个',
    '加条',
    '加一条',
    '加几条',
    '设个',
    '设一个',
    '记个',
    '记一个',
    '记一条',
    '写个',
    '写一个',
    '写一条',
    '登记',
    '录入',
    '加入',
  ];
  const otherTargets = [
    '分类',
    '文件夹',
    '分组',
    '标签',
    '习惯',
    '日程',
    '会议',
    '课程',
    '倒计时',
    '专注',
    '提醒',
  ];
  final clauses = text.split(_rxAiCtxIntentActions17);
  for (final clause in clauses) {
    if (_isExplicitTodoCreationRequest(clause)) return true;
    for (final verb in implicitTodoVerbs) {
      if (_isExplicitlyRequested(clause, verb) &&
          _hasExplicitActionPrefix(clause, verb)) {
        return true;
      }
    }
    if (!_matchesAny(clause.toLowerCase(), todoTargets)) continue;
    for (final verb in explicitCreateVerbs) {
      if (!_isExplicitlyRequested(clause, verb) ||
          !_hasExplicitActionPrefix(clause, verb)) {
        continue;
      }
      final verbIndex = clause.indexOf(verb);
      final before = clause.substring(0, verbIndex);
      final after = clause.substring(verbIndex + verb.length);
      var todoAfterIndex = -1;
      for (final target in todoTargets) {
        final index = after.toLowerCase().indexOf(target);
        if (index >= 0 && (todoAfterIndex < 0 || index < todoAfterIndex)) {
          todoAfterIndex = index;
        }
      }
      if (todoAfterIndex >= 0) {
        if (_rxAiCtxIntentActions18.hasMatch(after.substring(todoAfterIndex))) {
          continue;
        }
        var otherBeforeTodoIndex = -1;
        String? otherBeforeTodo;
        for (final target in otherTargets) {
          final index = after.indexOf(target);
          if (index >= 0 &&
              index < todoAfterIndex &&
              (otherBeforeTodoIndex < 0 || index < otherBeforeTodoIndex)) {
            otherBeforeTodoIndex = index;
            otherBeforeTodo = target;
          }
        }
        if (otherBeforeTodoIndex < 0) return true;
        final coordination = after.substring(
          otherBeforeTodoIndex + otherBeforeTodo!.length,
          todoAfterIndex,
        );
        if (_rxAiCtxIntentActions19.hasMatch(coordination)) {
          return true;
        }
        continue;
      }
      if (!_matchesAny(before.toLowerCase(), todoTargets) ||
          after.trim().isEmpty ||
          _matchesAny(after, otherTargets)) {
        continue;
      }
      return true;
    }
  }
  return false;
}

bool _isExplicitManagementRequest(String text, List<String> targets) {
  if (!_matchesAny(text.toLowerCase(), targets)) return false;
  const verbs = [
    '创建',
    '新建',
    '新增',
    '添加',
    '建立',
    '建',
    '建个',
    '建一个',
    '加个',
    '加一个',
    '设个',
    '设一个',
    '修改',
    '更新',
    '更名',
    '改名',
    '重命名',
    '删除',
    '删掉',
    '删一下',
    '删个',
    '删一个',
    '删',
    '移除',
    '清掉',
  ];
  return verbs.any(
    (verb) =>
        _isExplicitlyRequested(text, verb) &&
        _hasExplicitActionPrefix(text, verb),
  );
}

bool _isExplicitTodoGroupManagementRequest(String text) {
  return _isExplicitManagementRequest(text, _groupKeywords);
}

/// Recognizes common spoken commands such as "帮我记两个待办" and
/// "我要写两条任务" without treating how-to questions as write requests.
bool _isExplicitTodoCreationRequest(String text) {
  if (!_matchesAny(text, const ['待办', '任务'])) return false;
  if (_rxAiCtxIntentActions20.hasMatch(text)) {
    return false;
  }
  final startsTodoRecord = _rxAiCtxIntentActions21.hasMatch(text.trim());
  if (!startsTodoRecord) return false;

  // Phrases such as "帮我写一个待办分类" create a category, not a todo.
  final todoTarget = _rxAiCtxIntentActions22.firstMatch(text);
  if (todoTarget == null) return false;
  final afterTarget = text.substring(todoTarget.end);
  if (_rxAiCtxIntentActions23.hasMatch(afterTarget)) {
    return false;
  }
  return true;
}

int? _explicitTodoCreationCount(String text) {
  if (!_matchesAny(text, const ['待办', '任务', 'todo'])) return null;
  final explicitlyCreatesTodo =
      _isExplicitTodoCreationRequest(text) ||
      const [
        '提醒我',
        '新建',
        '新增',
        '创建',
        '添加',
      ].any((verb) => _isExplicitlyRequested(text, verb));
  if (!explicitlyCreatesTodo) return null;

  final match = _rxAiCtxIntentActions24.firstMatch(text);
  final rawCount = match?.group(1);
  if (rawCount == null) return null;
  return _parseExplicitCount(rawCount);
}

/// Recognizes a requested number of new ledger entries, such as "记两笔
/// 支出" or "新增3笔账单". Count validation only runs for explicit write
/// requests so a read-only statement about existing entries is unaffected.
int? _explicitFinanceDraftCount(String text) {
  if (!_shouldOfferFinanceDraftProposal(text)) return null;
  const count = r'(\d+|[一二两三四五六七八九十]+)';
  final beforeTarget = RegExp('$count\\s*(?:笔|份|条)?\\s*(?:账单|账|支出|收入|退款|交易|消费)')
      .firstMatch(text);
  final afterVerb = RegExp(
    '(?:记|记录|新增|添加|录入)\\s*(?:账单|账|支出|收入|退款|交易|消费)?\\s*'
    '$count\\s*笔',
  ).firstMatch(text);
  final rawCount = beforeTarget?.group(1) ?? afterVerb?.group(1);
  if (rawCount == null) return null;
  return _parseExplicitCount(rawCount);
}

int? _parseExplicitCount(String rawCount) {
  final numeric = int.tryParse(rawCount);
  if (numeric != null) return numeric > 0 ? numeric : null;

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
    '十': 10,
  };
  final tenIndex = rawCount.indexOf('十');
  if (tenIndex == -1) return digits[rawCount];
  final tensText = rawCount.substring(0, tenIndex);
  final onesText = rawCount.substring(tenIndex + 1);
  final tens = tensText.isEmpty ? 1 : digits[tensText];
  final ones = onesText.isEmpty ? 0 : digits[onesText];
  if (tens == null || ones == null) return null;
  return tens * 10 + ones;
}

bool _isExplicitHabitCreationRequest(String text) {
  if (!_matchesAny(text, _habitKeywords)) return false;
  const createVerbs = [
    '创建',
    '新建',
    '新增',
    '添加',
    '建立',
    '建',
    '加个',
    '加一个',
    '做个',
    '做一个',
    '设个',
    '设一个',
    '设置',
    '设定',
    '养成',
    '坚持',
    '记录',
    '记录一下',
    '记下',
    '记个',
    '记一个',
    '记一条',
  ];
  return createVerbs.any(
        (verb) =>
            _isExplicitlyRequested(text, verb) &&
            _hasExplicitActionPrefix(text, verb),
      ) ||
      _habitCreationKeywords.any(
        (verb) =>
            _isExplicitlyRequested(text, verb) &&
            _hasExplicitActionPrefix(text, verb),
      );
}

bool _isExplicitHabitMutationRequest(String text) {
  if (!_matchesAny(text, _habitKeywords)) return false;
  final mutationVerbs = [..._habitUpdateKeywords, ..._habitDeleteKeywords];
  return mutationVerbs.any(
    (verb) =>
        _isExplicitlyRequested(text, verb) &&
        _hasExplicitActionPrefix(text, verb),
  );
}

Set<String> _explicitHabitActionNames(
  String text, {
  String previousAssistantMessage = '',
}) {
  final actions = <String>{};
  if (_isExplicitHabitCreationRequest(text) ||
      _isHabitCreationFollowUp(text, previousAssistantMessage)) {
    actions.add('create_habit');
  }
  if (_isHabitMutationFollowUp(
    text,
    previousAssistantMessage,
    verbs: _habitUpdateKeywords,
  )) {
    actions.add('update_habit');
  }
  if (_isHabitMutationFollowUp(
    text,
    previousAssistantMessage,
    verbs: _habitDeleteKeywords,
  )) {
    actions.add('delete_habit');
  }
  for (final clause in text.split(_rxAiCtxIntentActions5)) {
    if (!_matchesAny(clause, _habitTypeKeywords)) continue;
    if (_habitUpdateKeywords.any(
      (verb) =>
          _isExplicitlyRequested(clause, verb) &&
          _hasExplicitActionPrefix(clause, verb),
    )) {
      actions.add('update_habit');
    }
    if (_habitDeleteKeywords.any(
      (verb) =>
          _isExplicitlyRequested(clause, verb) &&
          _hasExplicitActionPrefix(clause, verb),
    )) {
      actions.add('delete_habit');
    }
  }
  return actions;
}

/// Identifies concrete CDT action types explicitly requested in the current
/// turn so a mixed request cannot be marked complete after only one action.
Set<String> _requiredExplicitCdtActionNames(
  String text, {
  String previousUserMessage = '',
  String previousAssistantMessage = '',
}) {
  final actions = <String>{};
  if (_isExplicitTodoCreationRequest(text) ||
      _hasExplicitTodoCreationIntent(text)) {
    actions.add('create_todo');
  }
  actions.addAll(
    _explicitHabitActionNames(
      text,
      previousAssistantMessage: previousAssistantMessage,
    ),
  );
  actions.addAll(_explicitScheduleActionNames(text));
  actions.addAll(_explicitPlanningActionNames(text));
  actions.addAll(_explicitFocusActionNames(text));
  actions.addAll(_explicitCountdownActionNames(text));
  if (_pendingCountdownTitleSuffixForRequest(
        text,
        previousUserMessage: previousUserMessage,
        previousAssistantMessage: previousAssistantMessage,
      ) !=
      null) {
    actions.add('create_countdown');
  }
  actions.addAll(
    _explicitManagementActionNames(
      text,
      _groupKeywords,
    ).map((action) => '${action}_todo_group'),
  );
  final targetsTodoTag =
      _matchesAny(text, const ['待办', '任务', 'todo']) &&
      !_matchesAny(text, const ['番茄', '专注']);
  final requestsPomodoroTagManagement =
      !targetsTodoTag &&
      (_matchesAny(text, _tagManagementKeywords) ||
          _isExplicitManagementRequest(text, const [
            '番茄标签',
            '专注标签',
            '番茄 tag',
            'pomodoro tag',
          ]));
  if (requestsPomodoroTagManagement) {
    actions.addAll(
      _explicitManagementActionNames(text, const [
        '标签',
        '番茄标签',
        '专注标签',
        '番茄 tag',
        'pomodoro tag',
      ]).map((action) => '${action}_pomodoro_tag'),
    );
  }

  const todoTargets = ['待办', '任务', 'todo'];
  const todoUpdateVerbs = ['修改', '更新', '编辑', '更改', '改成', '改为', '调成', '调为'];
  const todoDeleteVerbs = ['删除', '删掉', '删了', '删', '清空', '清掉', '清除', '去掉', '取消'];
  const todoScheduleVerbs = [
    '延期',
    '改期',
    '改到',
    '移到',
    '挪到',
    '调到',
    '调整到',
    '提前到',
    '推迟到',
    '延到',
    '顺延',
    '往后推',
    '往前调',
  ];
  const todoCategorizeVerbs = ['分类', '归类', '分个类', '移出文件夹'];
  for (final clause in text.split(_rxAiCtxIntentActions5)) {
    if (!_matchesAny(clause.toLowerCase(), todoTargets)) continue;
    bool requested(List<String> verbs) => verbs.any(
      (verb) =>
          _isExplicitlyRequested(clause, verb) &&
          _hasExplicitActionPrefix(clause, verb),
    );

    if (requested(_todoCompletionMutationKeywords)) {
      actions.add('complete_todo');
    }
    if (requested(_todoSkipMutationKeywords)) actions.add('skip_todo');
    if (requested(todoDeleteVerbs)) actions.add('delete_todo');
    if (requested(todoUpdateVerbs)) actions.add('update_todo');
    if (requested(todoScheduleVerbs)) actions.add('reschedule_todo');
    if (requested(todoCategorizeVerbs)) actions.add('categorize_todo');
    if (requested(const ['拆分'])) actions.add('split_todo');
    if (requested(const ['合并'])) actions.add('merge_todos');
  }
  return actions;
}

Set<String> _explicitManagementActionNames(String text, List<String> targets) {
  if (!_isExplicitManagementRequest(text, targets)) return const {};
  const createVerbs = [
    '创建',
    '新建',
    '新增',
    '添加',
    '建立',
    '建',
    '建个',
    '建一个',
    '加个',
    '加一个',
    '设个',
    '设一个',
  ];
  const updateVerbs = ['修改', '更新', '更名', '改名', '重命名'];
  const deleteVerbs = ['删除', '删掉', '删一下', '删个', '删一个', '删', '移除', '清掉'];
  bool requested(List<String> verbs) => verbs.any(
    (verb) =>
        _isExplicitlyRequested(text, verb) &&
        _hasExplicitActionPrefix(text, verb),
  );

  return {
    if (requested(createVerbs)) 'create',
    if (requested(updateVerbs)) 'update',
    if (requested(deleteVerbs)) 'delete',
  };
}

/// Keeps explicit focus writes out of the generic read-only route for
/// "记录", while leaving questions on the query path.
bool _isExplicitFocusMutationRequest(String text) {
  if (_explicitFocusActionNames(text).isNotEmpty) return true;

  const mutationVerbs = ['记录', '补记', '补录', '新增', '创建', '添加'];
  const readOnlyWords = [
    '查看',
    '看看',
    '查询',
    '查',
    '检索',
    '统计',
    '分析',
    '汇总',
    '明细',
    '列表',
    '情况',
    '趋势',
    '结果',
    '效率',
    '为什么',
    '怎么',
    '如何',
    '怎样',
    '能不能',
    '可不可以',
    '方法',
    '步骤',
    '指南',
    '多少',
    '多久',
    '什么',
    '哪些',
    '最近',
    '是否',
    '没有',
    '知道',
    '是不是',
    '哪个',
    '吗',
    '呢',
    '？',
    '?',
  ];
  final durationPattern = _rxAiCtxIntentActions25;
  for (final clause in text.split(_rxAiCtxIntentActions26)) {
    final hasExplicitVerb = mutationVerbs.any(
      (verb) => _isExplicitlyRequested(clause, verb),
    );
    if (hasExplicitVerb &&
        _matchesAny(clause, const ['专注', '番茄']) &&
        durationPattern.hasMatch(clause) &&
        !_matchesAny(clause, readOnlyWords)) {
      return true;
    }
  }
  return false;
}

Set<String> _explicitFocusActionNames(String text) {
  const logCreateVerbs = [
    '记录',
    '记下',
    '记一下',
    '记个',
    '记一个',
    '记一条',
    '记一段',
    '补记',
    '补录',
    '补个',
    '补一条',
    '新增',
    '创建',
    '添加',
    '加个',
    '加一个',
  ];
  const logUpdateVerbs = ['修改', '更新', '更正', '调整', '改成', '改为', '改到'];
  const logDeleteVerbs = ['删除', '删掉', '删', '移除', '清掉'];
  const pomodoroStartVerbs = ['开始', '启动', '开启'];
  const pomodoroStopVerbs = ['停止', '结束'];
  final actions = <String>{};
  final clauses = text.split(_rxAiCtxIntentActions5);
  for (final clause in clauses) {
    if (!_matchesAny(clause, _timeLogActionKeywords)) continue;
    void addWhenExplicit(List<String> verbs, String action) {
      for (final verb in verbs) {
        if (_isExplicitlyRequested(clause, verb) &&
            _hasExplicitActionPrefix(clause, verb)) {
          actions.add(action);
          return;
        }
      }
    }

    addWhenExplicit(logCreateVerbs, 'create_time_log');
    addWhenExplicit(logUpdateVerbs, 'update_time_log');
    addWhenExplicit(logDeleteVerbs, 'delete_time_log');
    addWhenExplicit(pomodoroStartVerbs, 'start_pomodoro');
    addWhenExplicit(pomodoroStopVerbs, 'stop_pomodoro');
  }
  return actions;
}

Set<String> _explicitCountdownActionNames(String text) {
  const createVerbs = [
    '创建',
    '新建',
    '新增',
    '添加',
    '加个',
    '加一个',
    '设置',
    '设定',
    '设个',
    '设一个',
    '弄个',
    '弄一个',
    '记录',
    '记下',
    '记一下',
    '记个',
    '记一个',
    '建立',
    '建',
  ];
  const updateVerbs = [
    '修改',
    '更新',
    '更改',
    '调整',
    '改到',
    '改成',
    '改为',
    '挪到',
    '移到',
    '移动到',
  ];
  const completeVerbs = ['完成', '办完', '标记完成', '做完'];
  const deleteVerbs = ['删除', '删掉', '删', '移除', '清掉', '取消'];
  final actions = <String>{};
  final targets = [..._countdownKeywords, 'countdown'];
  final clauses = text.split(_rxAiCtxIntentActions5);
  for (final clause in clauses) {
    if (!_matchesAny(clause.toLowerCase(), targets)) continue;
    void addWhenExplicit(List<String> verbs, String action) {
      for (final verb in verbs) {
        if (_isExplicitlyRequested(clause, verb) &&
            _hasExplicitActionPrefix(clause, verb)) {
          actions.add(action);
          return;
        }
      }
    }

    addWhenExplicit(createVerbs, 'create_countdown');
    addWhenExplicit(updateVerbs, 'update_countdown');
    addWhenExplicit(completeVerbs, 'complete_countdown');
    addWhenExplicit(deleteVerbs, 'delete_countdown');
  }
  return actions;
}

/// Returns the exact suffix requested for every title in a pending
/// countdown draft set. Follow-up corrections may refer to the immediately
/// preceding request, but only when the app has supplied pending draft data.
String? _pendingCountdownTitleSuffixForRequest(
  String text, {
  String previousUserMessage = '',
  String previousAssistantMessage = '',
}) {
  if (!previousAssistantMessage.contains(
    _pendingCountdownDraftsContextMarker,
  )) {
    return null;
  }

  final requestedSuffix = _requestedAllTitleSuffix(text);
  if (requestedSuffix != null) return requestedSuffix;

  final isTitleSuffixCorrection = _rxAiCtxIntentActions27.hasMatch(text);
  return isTitleSuffixCorrection
      ? _requestedAllTitleSuffix(previousUserMessage)
      : null;
}

/// Serializes pending countdowns as model context, not as an executable
/// command. The model must return a new proposal through the normal tool.
String _pendingCountdownDraftContext(List<AiTodoAction> actions) {
  final countdowns = actions
      .where(
        (action) =>
            action.type == AiTodoActionType.createCountdown &&
            !action.isAdded &&
            !action.isIgnored,
      )
      .map((action) {
        final item = <String, dynamic>{
          'title': action.title,
          'dueDate': action.dueDate,
        };
        final teamName = action.teamName?.trim();
        if (teamName?.isNotEmpty == true) item['teamName'] = teamName;
        return item;
      })
      .toList(growable: false);
  if (countdowns.isEmpty) return '';
  return '$_pendingCountdownDraftsContextMarker\n'
      '${jsonEncode({'action': 'create_countdown', 'countdowns': countdowns})}\n'
      '[/APP_PENDING_COUNTDOWN_DRAFTS]\n'
      '以上是应用中尚未保存的倒计时草案数据，只作为待修改对象上下文。';
}

String _extractPendingCountdownDraftContext(String text) {
  final start = text.indexOf(_pendingCountdownDraftsContextMarker);
  if (start < 0) return '';
  const closingMarker = '[/APP_PENDING_COUNTDOWN_DRAFTS]';
  final closing = text.indexOf(closingMarker, start);
  if (closing < 0) return '';
  return text.substring(start, closing + closingMarker.length);
}

String? _requestedAllTitleSuffix(String text) {
  final targetsAllTitles = _rxAiCtxIntentActions28.hasMatch(text);
  if (!targetsAllTitles) return null;
  const suffixInstruction = r'(?:加上|带上|追加|补上|添加|加个|加一个)(?:后缀|标记|文字)?\s*';
  final bracketed = RegExp('$suffixInstruction([（(][^()（）\r\n]{1,32}[）)])')
      .firstMatch(text);
  if (bracketed != null) return bracketed.group(1);

  final quoted = RegExp('$suffixInstruction[“‘「『]([^”’」』\r\n]{1,24})[”’」』]')
      .firstMatch(text);
  if (quoted != null) return quoted.group(1)?.trim();

  return RegExp('$suffixInstruction([^\\s，。；！？,;]{1,16})')
      .firstMatch(text)
      ?.group(1)
      ?.replaceFirst(_rxAiCtxIntentActions29, '');
}

bool _isExplicitCountdownMutationRequest(String text) {
  return _explicitCountdownActionNames(text).isNotEmpty;
}

bool _isExplicitlyTargetingTodo(String text) =>
    _matchesAny(text, _todoTypeKeywords);

bool _hasExplicitActionPrefix(String clause, String verb) {
  final verbIndex = clause.indexOf(verb);
  if (verbIndex < 0) return false;
  final prefix = clause.substring(0, verbIndex);
  if (prefix.trim().isEmpty) return true;
  if (_rxAiCtxIntentActions30.hasMatch(prefix.trim())) {
    return true;
  }
  return _rxAiCtxIntentActions31.hasMatch(prefix);
}

// Cached RegExp patterns
final RegExp _rxAiCtxIntentActions1 = RegExp(r'[\s，。！？,.!?；;]');
final RegExp _rxAiCtxIntentActions2 = RegExp(
  r'^(?:我)?(?:先|暂时)?(?:算了|取消|撤销|放弃)'
  r'(?:(?:这次|本次|这个|它|这件事|这项操作|刚才那个))*'
  r'(?:吧|了|好了)?$',
);
final RegExp _rxAiCtxIntentActions3 = RegExp(
  r'^(?:我)?(?:先|暂时)?(?:取消|撤销|放弃)'
  r'(?:再|继续)?(?:我|给我|帮我|替我)?'
  r'(?:创建|新建|新增|添加|记录|记账|生成|执行|建)'
  r'(?:(?:这次|本次|这个|它|习惯|待办|任务|专注|番茄|倒计时|分类|标签|账单|日程|时间块|了|吧|一下))*$',
);
final RegExp _rxAiCtxIntentActions4 = RegExp(
  r'^(?:我)?(?:先|暂时)?(?:不需要|不用|不要|不想|不打算|不准备|不|别)'
  r'(?:再|继续)?(?:我|给我|帮我|替我)?(?:现在|以后)?'
  r'(?:创建|新建|新增|添加|记录|记账|安排|规划|计划|做|弄|执行|生成|建)?'
  r'(?:(?:这次|本次|这个|它|习惯|待办|任务|专注|番茄|倒计时|分类|标签|账单|日程|时间块|了|吧|一下))*$',
);
final RegExp _rxAiCtxIntentActions5 = RegExp(r'[，。；！？,;]|然后|并且|同时');
final RegExp _rxAiCtxIntentActions6 = RegExp(
  r'^(?:那就|就|选择|选|创建成|按|我要|我选)?\s*习惯(?:打卡)?(?:吧|就行|也行|即可)?[。！!\s]*$',
);
final RegExp _rxAiCtxIntentActions7 = RegExp(r'还是|或者|或');
final RegExp _rxAiCtxIntentActions8 = RegExp(
  r'(?:习惯.{0,24}(?:草案|生成|创建|追踪)|(?:生成|创建|新增|建立).{0,24}习惯)',
);
final RegExp _rxAiCtxIntentActions9 = RegExp(r'告诉我|回答|补充|这些细节|还差|请提供|请告诉|请问');
final RegExp _rxAiCtxIntentActions10 = RegExp(r'[？?]');
final RegExp _rxAiCtxIntentActions11 = RegExp(r'频率|每周|每天|每次|类型|时长|提醒|哪天|星期');
final RegExp _rxAiCtxIntentActions12 = RegExp(r'请告诉|请提供|还差|补充|选择|哪个|哪一个');
final RegExp _rxAiCtxIntentActions13 = RegExp(
  r'[？?]|^(?:为什么|怎么|如何|怎样|有没有|有哪些|有什么|查看|查询|查一下|列出|统计|汇总|分析一下|帮我查|帮我分析)',
);
final RegExp _rxAiCtxIntentActions14 = RegExp(
  r'(?:已生成|已经生成|已创建|已经创建|已保存|已经保存).{0,16}(?:草案|确认卡|操作卡|待办|习惯|日程|账单)?',
);
final RegExp _rxAiCtxIntentActions15 = RegExp(
  r'请提供|请补充|请告诉|告诉我|还需要|还差|缺少|需要你提供|需要补充|请问',
);
final RegExp _rxAiCtxIntentActions16 = RegExp(
  r'标题|名称|备注|时间|日期|时长|频率|提醒|颜色|分类|地点|截止|星期|哪天|几次|多久',
);
final RegExp _rxAiCtxIntentActions17 = RegExp(r'[，。；！？,;]|然后|并且|同时|并|再');
final RegExp _rxAiCtxIntentActions18 = RegExp(
  r'^(?:待办|任务)(?:事项)?(?:分类|文件夹|分组)',
);
final RegExp _rxAiCtxIntentActions19 = RegExp(
  r'^(?:和|与|及)(?:(?:一个|一条|一项|几个|几条|两条|三条))?$',
);
final RegExp _rxAiCtxIntentActions20 = RegExp(
  r'(?:怎么|如何|怎样).{0,12}(?:记|写|记录|登记|录入).{0,12}(?:待办|任务)',
);
final RegExp _rxAiCtxIntentActions21 = RegExp(
  r'^(?:(?:请|帮我|帮忙|麻烦(?:你)?|给我|替我|我想|我要|直接)\s*)*'
  r'(?:分开|分别|单独|各自)?\s*'
  r'(?:记(?:下|一下|上)?|记录|登记|录入|写(?:一下|一份|一个)?|'
  r'加(?:个|一个|条|一条|几条))',
);
final RegExp _rxAiCtxIntentActions22 = RegExp(r'待办|任务');
final RegExp _rxAiCtxIntentActions23 = RegExp(r'^(?:事项)?(?:分类|文件夹|分组|标签)');
final RegExp _rxAiCtxIntentActions24 = RegExp(
  r'(\d+|[一二两三四五六七八九十]+)\s*(?:个|条|份|项|件)?\s*(?:待办|任务)',
);
final RegExp _rxAiCtxIntentActions25 = RegExp(
  r'(?:\d+|[一二两三四五六七八九十]+)\s*(?:分钟|小时)',
);
final RegExp _rxAiCtxIntentActions26 = RegExp(r'[，。；,;]|然后|并且|并|同时|再');
final RegExp _rxAiCtxIntentActions27 = RegExp(
  r'(?:实际.{0,8})?(?:标题|名称).{0,16}(?:没|没有|未|并没有).{0,12}(?:加上|带上|追加|补上|添加)|'
  r'(?:没|没有|未|并没有).{0,12}(?:加上|带上|追加|补上|添加).{0,12}(?:标题|名称)',
);
final RegExp _rxAiCtxIntentActions28 = RegExp(
  r'(?:所有|全部|每个|每条|这些)(?:的)?[^，。；！？\n]{0,10}(?:标题|名称)|(?:标题|名称)[^，。；！？\n]{0,10}(?:都|全部)',
);
final RegExp _rxAiCtxIntentActions29 = RegExp(r'(?:吧|一下|即可|就行|了)$');
final RegExp _rxAiCtxIntentActions30 = RegExp(
  r'^(?:(?:今天|明天|后天|本周[一二三四五六日天]?|这周|下周[一二三四五六日天]?|周[一二三四五六日天]|周末|上午|下午|晚上|早上|中午|今晚|明晚|\d{1,2}月\d{1,2}日)\s*)+$',
);
final RegExp _rxAiCtxIntentActions31 = RegExp(
  r'(?:请|麻烦|帮我|帮忙|给我|替我|我要|我想|我来|把|将|直接|先)[^，。；！？,;]*$',
);
