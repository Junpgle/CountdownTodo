part of '../ai_todo_context_builder.dart';

/// Disambiguates an amount-bearing transaction record from finance queries
/// that also contain broad words such as "记录" or "支出".
bool _isExplicitFinanceDraftRequest(String text) {
  const mutationVerbs = [
    '记一笔',
    '记录一笔',
    '新增一笔',
    '添加一笔',
    '消费了',
    '花了',
    '记',
    '买了',
    '购买了',
    '进账',
    '收款',
    '记录',
  ];
  const readOnlyWords = [
    '查看',
    '看看',
    '查询',
    '查',
    '检索',
    '统计',
    '汇总',
    '分析',
    '明细',
    '列表',
    '情况',
    '趋势',
    '结果',
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
    '是否',
    '没有',
    '知道',
    '是不是',
    '哪个',
    '有没有',
    '吗',
    '呢',
    '？',
    '?',
  ];
  final amountPattern = _rxAiCtxIntentRouting1;
  for (final clause in text.split(_rxAiCtxIntentRouting2)) {
    if (amountPattern.hasMatch(clause) &&
        mutationVerbs.any((verb) => _isExplicitlyRequested(clause, verb)) &&
        !_matchesAny(clause, readOnlyWords)) {
      return true;
    }
  }
  return false;
}

/// Only expose the ledger-write proposal for an explicit transaction request
/// or a concise amount-bearing entry. Financial planning amounts such as a
/// budget, loan, balance, or investment are not transactions by themselves.
bool _shouldOfferFinanceDraftProposal(String text) {
  final withoutReminderNegation = text.replaceAll(_rxAiCtxIntentRouting3, '');
  if (_rxAiCtxIntentRouting4.hasMatch(withoutReminderNegation)) {
    return false;
  }
  const clearDraftVerbs = [
    '记一笔',
    '记录一笔',
    '新增一笔',
    '添加一笔',
    '消费了',
    '花了',
    '买了',
    '购买了',
    '进账',
    '收款',
    '消费',
    '记',
  ];
  if (clearDraftVerbs.any((verb) => _isExplicitlyRequested(text, verb))) {
    return true;
  }

  const nonTransactionFinanceContexts = [
    '预算',
    '额度',
    '贷款',
    '借款',
    '还款计划',
    '欠款',
    '储蓄',
    '存款',
    '存钱',
    '余额',
    '投资',
    '理财',
    '本金',
    '利息',
    '成本',
    '报价',
    '估价',
    '预计花费',
    '预计支出',
    '计划金额',
    '目标金额',
    '钱包',
    '账户',
    '银行卡',
    '卡里',
    '支付宝里',
    '微信里',
    '现金余额',
  ];
  if (_matchesAny(text, nonTransactionFinanceContexts)) return false;
  if (_isExplicitFinanceDraftRequest(text)) return true;

  const ambiguousDraftVerbs = ['花费', '购买', '记账草案'];
  final mentionsAmbiguousDraftVerb = ambiguousDraftVerbs.any(text.contains);
  if (mentionsAmbiguousDraftVerb) {
    return ambiguousDraftVerbs.any(
      (verb) => _isExplicitlyRequested(text, verb),
    );
  }

  final hasAmount = _rxAiCtxIntentRouting1.hasMatch(text);
  if (!hasAmount) return false;

  final amountMatch = _rxAiCtxIntentRouting1.firstMatch(text);
  if (amountMatch == null) return false;
  var descriptor =
      '${text.substring(0, amountMatch.start)} '
      '${text.substring(amountMatch.end)}';
  const genericEntryWords = [
    '帮忙',
    '帮我',
    '给我',
    '替我',
    '麻烦',
    '请问',
    '请',
    '我',
    '有',
    '还有',
    '还剩',
    '剩下',
    '今天',
    '昨天',
    '明天',
    '刚才',
    '大约',
    '大概',
    '预计',
    '金额',
    '记一笔',
    '记录一笔',
    '记账',
    '记录',
    '新增',
    '添加',
    '消费了',
    '消费',
    '花了',
    '花费',
    '买了',
    '购买',
    '进账',
    '收款',
    '记',
    '一笔',
    '人民币',
    '元',
    '块钱',
    '块',
    '¥',
    '￥',
  ];
  for (final word in genericEntryWords) {
    descriptor = descriptor.replaceAll(word, ' ');
  }
  return descriptor.trim().runes.length >= 2;
}

bool _hasExplicitFinanceDeleteIntent(String text) {
  if (!_matchesAny(text, _financeKeywords)) return false;
  const deleteVerbs = [
    '删除',
    '删除掉',
    '删掉',
    '删了',
    '清掉',
    '移除',
    '去掉',
    '清除',
    '撤销',
    '取消',
  ];
  return deleteVerbs.any(
    (verb) =>
        _isExplicitlyRequested(text, verb) &&
        _hasExplicitActionPrefix(text, verb),
  );
}

bool _hasExplicitFinanceUpdateIntent(String text) {
  if (!_matchesAny(text, _financeKeywords)) return false;
  final commandPrefix = _rxAiCtxIntentRouting5;
  final updateVerbPrefix = _rxAiCtxIntentRouting6;
  const updateVerbs = [
    '更正',
    '调整',
    '修改',
    '更新',
    '更改',
    '编辑',
    '改成',
    '改为',
    '调成',
    '调为',
  ];
  const assignmentVerbs = {'改成', '改为', '调成', '调为'};
  const readOnlyFinanceQueryKeywords = [
    '查询',
    '查看',
    '分析',
    '统计',
    '汇总',
    '列出',
    '明细',
    '情况',
    '记录',
    '影响',
    '效果',
    '结果',
    '趋势',
    '建议',
    '是否',
    '有没有',
  ];
  final hasReadOnlyQuestion =
      _looksLikeInformationQuestion(text) ||
      _matchesAny(text, readOnlyFinanceQueryKeywords);
  for (final clause in text.split(_rxAiCtxIntentRouting7)) {
    final normalizedClause = clause.trim();
    final startsWithCommand =
        commandPrefix.hasMatch(normalizedClause) ||
        updateVerbPrefix.hasMatch(normalizedClause);
    for (final verb in updateVerbs) {
      if (!_isExplicitlyRequested(normalizedClause, verb)) continue;
      final suffix = normalizedClause.substring(
        normalizedClause.indexOf(verb) + verb.length,
      );
      final directAssignment = _rxAiCtxIntentRouting8.hasMatch(suffix);
      final propertyAssignment = _rxAiCtxIntentRouting9.hasMatch(suffix);
      final readOnlyTail = _matchesAny(suffix, const [
        '影响',
        '效果',
        '结果',
        '情况',
        '记录',
        '明细',
        '建议',
        '趋势',
        '变化',
        '分析',
        '查询',
        '统计',
        '什么',
        '多少',
        '怎么',
        '为什么',
        '吗',
      ]);
      final embeddedAssignment =
          assignmentVerbs.contains(verb) &&
          suffix.trim().isNotEmpty &&
          suffix.trim() != '一下' &&
          suffix.trim() != '下';
      final assignsNewValue =
          (directAssignment || propertyAssignment || embeddedAssignment) &&
          !readOnlyTail;
      final shortCommand =
          suffix.trim().isEmpty ||
          suffix.trim() == '一下' ||
          suffix.trim() == '下';
      if ((startsWithCommand || !hasReadOnlyQuestion) &&
          (assignsNewValue || shortCommand)) {
        return true;
      }
    }
  }
  return false;
}

bool _isExplicitlyRequested(String text, String trigger) {
  var searchFrom = 0;
  while (searchFrom < text.length) {
    final index = text.indexOf(trigger, searchFrom);
    if (index == -1) return false;
    final clauseBoundary = text.lastIndexOf(_rxAiCtxIntentRouting7, index);
    final clauseStart = clauseBoundary == -1 ? 0 : clauseBoundary + 1;
    final prefix = text
        .substring(clauseStart, index)
        .replaceAll(_rxAiCtxIntentRouting3, '');
    final suffixBoundary = text.indexOf(
      _rxAiCtxIntentRouting7,
      index + trigger.length,
    );
    final suffix = text.substring(
      index + trigger.length,
      suffixBoundary == -1 ? text.length : suffixBoundary,
    );
    final politeWriteRequest = _rxAiCtxIntentRouting10.hasMatch(prefix.trim());
    final hasExplicitCommandPrefix =
        _rxAiCtxIntentRouting11.hasMatch(prefix) &&
        !_rxAiCtxIntentRouting12.hasMatch(prefix);
    final mutationStatus = _rxAiCtxIntentRouting13.hasMatch(prefix);
    final mutationQuestion =
        !hasExplicitCommandPrefix &&
        ((!politeWriteRequest && _rxAiCtxIntentRouting14.hasMatch(prefix)) ||
            _rxAiCtxIntentRouting15.hasMatch(suffix) ||
            _rxAiCtxIntentRouting16.hasMatch(suffix) ||
            _rxAiCtxIntentRouting17.hasMatch(suffix) ||
            _rxAiCtxIntentRouting18.hasMatch(suffix));
    final firstPersonReport = _rxAiCtxIntentRouting19.hasMatch(prefix);
    final reportedMutation =
        _rxAiCtxIntentRouting20.hasMatch(suffix) ||
        (_rxAiCtxIntentRouting21.hasMatch(suffix) &&
            (!hasExplicitCommandPrefix || firstPersonReport));
    final completionMetric =
        trigger == '完成' &&
        _rxAiCtxIntentRouting22.hasMatch(
          text.substring(index + trigger.length),
        );
    final descriptiveStatus = _rxAiCtxIntentRouting23.hasMatch(prefix);
    final howToQuestion =
        !politeWriteRequest && _rxAiCtxIntentRouting24.hasMatch(prefix);
    if (mutationStatus ||
        mutationQuestion ||
        reportedMutation ||
        completionMetric ||
        descriptiveStatus ||
        howToQuestion) {
      searchFrom = index + trigger.length;
      continue;
    }
    final negations = _rxAiCtxIntentRouting25.allMatches(prefix).toList();
    final contrasts = _rxAiCtxIntentRouting26.allMatches(prefix).toList();
    final isNegated =
        negations.isNotEmpty &&
        (contrasts.isEmpty || negations.last.start > contrasts.last.start);
    if (!isNegated) return true;
    searchFrom = index + trigger.length;
  }
  return false;
}

bool _shouldInjectCourseContext(String text) {
  if (_matchesAny(text, _courseKeywords)) return true;
  return _matchesAny(text, _planningKeywords) &&
      _matchesAny(text, _planningTimeKeywords);
}

bool _shouldInjectFixedScheduleContext(String text) {
  if (_matchesAny(text, _fixedScheduleKeywords)) return true;
  return _matchesAny(text, _planningKeywords) &&
      _matchesAny(text, _planningTimeKeywords);
}

bool _shouldInjectTodoContext(String text) {
  final asksList =
      _matchesAny(text, _todoListQueryKeywords) ||
      _looksLikeTodoListQuery(text);
  final touchesExisting = _matchesAny(text, _existingTodoKeywords);
  final createOnly =
      _matchesAny(text, _createTodoKeywords) &&
      !_matchesAny(text, _existingTodoKeywords) &&
      !asksList;
  if (createOnly) return false;
  return touchesExisting || asksList;
}

bool _isContextFollowUp(String text, String previousUserMessage) {
  if (previousUserMessage.trim().isEmpty) return false;
  return _matchesAny(text, _contextReferenceKeywords) ||
      _rxAiCtxIntentRouting27.hasMatch(text);
}

bool _shouldInheritContext(
  String userMessage,
  String previousUserMessage,
  bool Function(String) classifier,
) {
  return _isContextFollowUp(userMessage, previousUserMessage) &&
      classifier(previousUserMessage);
}

bool _shouldInjectFocusContext(String text) =>
    _matchesAny(text, _timeLogKeywords) || _looksLikeFocusQuery(text);

bool _shouldInjectPlanContext(String text) {
  return _matchesAny(text, _planKeywords) ||
      (_matchesAny(text, _planningKeywords) &&
          _matchesAny(text, _planningTimeKeywords));
}

bool _looksLikeTodoListQuery(String text) {
  final hasTodoNoun =
      text.contains('待办') ||
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

bool _looksLikeCountdownQuery(String text) {
  final asksRemainingDays = _rxAiCtxIntentRouting28.hasMatch(text);
  if (asksRemainingDays) return true;
  final hasNoun =
      text.contains('倒计时') ||
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

bool _looksLikeFocusQuery(String text) {
  final hasNoun =
      text.contains('专注') ||
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

bool _looksLikeInformationQuestion(String text) {
  return text.contains('为什么') ||
      text.contains('怎么') ||
      text.contains('如何') ||
      text.contains('什么') ||
      text.contains('好处') ||
      text.contains('建议') ||
      text.contains('是否') ||
      text.contains('吗') ||
      text.contains('呢') ||
      text.contains('？') ||
      text.contains('?');
}

// Cached RegExp patterns
final RegExp _rxAiCtxIntentRouting1 = RegExp(
  r'\d+(?:\.\d+)?\s*(?:元|块(?:钱)?|人民币|¥|￥)',
);
final RegExp _rxAiCtxIntentRouting2 = RegExp(r'[，。；！？,;]|然后|并且|并|同时|再');
final RegExp _rxAiCtxIntentRouting3 = RegExp(r'(?:别|不要)忘(?:了|记)?');
final RegExp _rxAiCtxIntentRouting4 = RegExp(
  r'(?:不要|别|不必|无需|不用)(?:再|帮我|帮忙|替我|给我)?'
  r'(?:记|记录|新增|添加|消费|花|买|进账|收款)',
);
final RegExp _rxAiCtxIntentRouting5 = RegExp(r'^(?:(?:请|帮我|替我|给我)\s*)*(?:把|将)');
final RegExp _rxAiCtxIntentRouting6 = RegExp(
  r'^(?:(?:请|帮我|替我|给我)\s*)*'
  r'(?:更正|调整|修改|更新|更改|编辑|改成|改为|调成|调为)',
);
final RegExp _rxAiCtxIntentRouting7 = RegExp(r'[，。；！？,;]');
final RegExp _rxAiCtxIntentRouting8 = RegExp(r'^\s*(?:为|成|到|至)\s*\S+\s*$');
final RegExp _rxAiCtxIntentRouting9 = RegExp(
  r'(?:金额|数额|价格|日期|时间|类别|分类|备注|账户|支付方式)\s*'
  r'(?:更正|调整)?\s*(?:为|成|到|至)\s*\S+\s*$',
);
final RegExp _rxAiCtxIntentRouting10 = RegExp(
  r'^(?:(?:请问|麻烦|请|直接)\s*)?(?:能不能|可不可以|能否|可否|可以)'
  r'(?:(?:请|直接)?(?:帮我|帮忙|替我|给我)(?:把[^，。；！？,;]{0,16})?|'
  r'把[^，。；！？,;]{0,16})?$',
);
final RegExp _rxAiCtxIntentRouting11 = RegExp(
  r'(?:请|麻烦|帮我|帮忙|把|将|给我|替我)[^，。；！？,;]*$',
);
final RegExp _rxAiCtxIntentRouting12 = RegExp(
  r'(?:查询|查看|看看|看下|查下|查一下|查找|检索|统计|汇总|分析|列出|了解|问问)',
);
final RegExp _rxAiCtxIntentRouting13 = RegExp(
  r'(?:已|已经|已被|已经被|需要|应该|尚未|未|待|没|没有|被)\s*$',
);
final RegExp _rxAiCtxIntentRouting14 = RegExp(
  r'(?:哪些|什么|多少|多久|多长时间|几天|几周|几个月|哪几|几个|几项|几条|几件|'
  r'几点|几时|何时|哪天|几号|几日|何日|是否|有没有|有无|要不要|需不需要|'
  r'该不该|应不应|应不应该|是否应该|是否需要|有没有必要|是不是要|是不是该|'
  r'是不是应该|想不想|会不会|能否|可否)[^，。；！？,;]*$',
);
final RegExp _rxAiCtxIntentRouting15 = RegExp(
  r'^(?:(?:了|过|的|得)?)(?:哪些|什么|多少|哪几|几个|几项|几条|几件|吗|呢|情况|状态|明细|详情|得怎么样|得如何|是否|有没有|有无)',
);
final RegExp _rxAiCtxIntentRouting16 = RegExp(
  r'^(?:什么|哪些|多少|多久|多长时间|怎么|如何|怎样|为什么|是什么|是什么意思|'
  r'有哪些|有什么|有多少|几点|几时|何时|哪天|几号|几日|什么时候|什么时间|'
  r'什么情况|情况如何|状态如何|进度如何|是否|有没有|有无|要不要|需不需要|'
  r'会不会|能不能|可不可以|能否|可否)[^，。；！？,;]{0,24}$',
);
final RegExp _rxAiCtxIntentRouting17 = RegExp(
  r'^[^，。；！？,;]{1,24}(?:需要什么|需要哪些|需要多少|要什么|要哪些|'
  r'怎么|如何|怎样|为什么|是否|有没有|有无|几点|几时|何时|哪天|几号|几日|'
  r'什么时候|什么时间|多久|多长时间)[^，。；！？,;]{0,16}$',
);
final RegExp _rxAiCtxIntentRouting18 = RegExp(
  r'^[^，。；！？,;]{1,16}(?:有哪些(?:好处|意义|作用|用途|区别|要求|条件|方法|原因|注意事项)|'
  r'有什么(?:好处|意义|作用|用途|功能|区别|要求|条件|方法|原因|注意事项|需要注意)|'
  r'是什么(?:原因|情况|状态|含义|意思|定义|功能)|是什么意思|'
  r'(?:意义|作用|用途|含义|意思|定义|目的)是什么|'
  r'有哪些|有什么|有多少|是什么|为什么|怎么|如何|怎样|'
  r'多久|多长时间|几天|几周|几个月|几点|几时|何时|哪天|几号|几日|何日|'
  r'什么时候|什么时间|什么情况|什么状态|情况如何|状态如何|进度如何|'
  r'有什么影响|会有什么影响|会不会影响|是否会|有何影响|有无影响|'
  r'造成什么影响|影响吗|有影响|会不会|会怎样|会如何|能不能|可不可以|'
  r'能否|可否|是否|有没有|有无|要不要|需不需要|该不该|吗|呢)$',
);
final RegExp _rxAiCtxIntentRouting19 = RegExp(
  r'^(?:我|本人)(?!想|要|希望|需要|请|麻烦|让你|帮我)',
);
final RegExp _rxAiCtxIntentRouting20 = RegExp(r'^的');
final RegExp _rxAiCtxIntentRouting21 = RegExp(r'^(?:了|过)');
final RegExp _rxAiCtxIntentRouting22 = RegExp(r'^(?:率|情况|数量|进度|状态)');
final RegExp _rxAiCtxIntentRouting23 = RegExp(r'(?:哪些|什么|需要|应该|尚未|未|待)\s*$');
final RegExp _rxAiCtxIntentRouting24 = RegExp(
  r'(?:为什么|怎么|如何|怎样|是否|能不能|可不可以)[^，。；！？,;]*$',
);
final RegExp _rxAiCtxIntentRouting25 = RegExp(r'不|别|没|无需|禁止|避免');
final RegExp _rxAiCtxIntentRouting26 = RegExp(r'但是|不过|但|而是');
final RegExp _rxAiCtxIntentRouting27 = RegExp(r'第(?:[一二三四五六七八九十]|\d+)个');
final RegExp _rxAiCtxIntentRouting28 = RegExp(
  r'(?:还有|还剩|剩下?|距离).{0,12}(?:几|多少|[一二三四五六七八九十\d]+).{0,3}(?:天|日)',
);
