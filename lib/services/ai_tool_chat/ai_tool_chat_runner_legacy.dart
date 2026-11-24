part of '../ai_tool_chat_runner.dart';

final RegExp _legacyTextToolBlock = RegExp(
  r'<tool_call\b[^>]*>([\s\S]*?)</tool_call\s*>',
  caseSensitive: false,
);
final RegExp _legacyTextToolOpen = RegExp(
  r'<tool_call\b[^>]*>',
  caseSensitive: false,
);
final RegExp _legacyTextToolClose = RegExp(
  r'</tool_call\s*>',
  caseSensitive: false,
);

String _visibleTextBeforeLegacyToolCalls(String content) {
  final lowerContent = content.toLowerCase();
  var cursor = 0;
  final visible = StringBuffer();
  while (cursor < content.length) {
    final openMatches = _legacyTextToolOpen.allMatches(content, cursor);
    final openMatch = openMatches.isEmpty ? null : openMatches.first;
    final closeMatches = _legacyTextToolClose.allMatches(content, cursor);
    final closeBeforeOpen = closeMatches.isEmpty ? null : closeMatches.first;
    if (closeBeforeOpen != null &&
        (openMatch == null || closeBeforeOpen.start < openMatch.start)) {
      visible.write(content.substring(cursor, closeBeforeOpen.start));
      cursor = closeBeforeOpen.end;
      continue;
    }
    if (openMatch != null) {
      visible.write(content.substring(cursor, openMatch.start));
      final toolCloseMatches = _legacyTextToolClose.allMatches(
        content,
        openMatch.end,
      );
      final closeMatch = toolCloseMatches.isEmpty
          ? null
          : toolCloseMatches.first;
      if (closeMatch == null) return visible.toString();
      cursor = closeMatch.end;
      continue;
    }

    final partialOpenIndex = lowerContent.lastIndexOf('<tool_call');
    if (partialOpenIndex >= cursor &&
        !lowerContent.substring(partialOpenIndex).contains('>')) {
      visible.write(content.substring(cursor, partialOpenIndex));
      return visible.toString();
    }
    visible.write(content.substring(cursor));
    return visible.toString();
  }
  return visible.toString();
}

({
  String content,
  List<AiChatFunctionCall> calls,
  bool hadToolMarkup,
  bool hadDisallowedWriteMarkup,
})
_parseLegacyTextToolCalls(
  String content,
  List<Map<String, dynamic>> tools,
  int round,
) {
  // Some OpenAI-compatible providers return tool calls as XML-like assistant
  // text instead of populating `tool_calls`. Only accept functions advertised
  // in this round; writes still pass through proposal validation and the
  // existing confirmation-card path.
  final allowedTools = <String, Map>{};
  for (final tool in tools) {
    final function = tool['function'];
    if (function is! Map) continue;
    final name = function['name']?.toString() ?? '';
    if (name.isNotEmpty) allowedTools[name] = function;
  }

  final calls = <AiChatFunctionCall>[];
  var callIndex = 0;
  var hadDisallowedWriteMarkup = false;
  for (final blockMatch in _legacyTextToolBlock.allMatches(content)) {
    final block = blockMatch.group(1) ?? '';
    final functionMatch = RegExp(
      r'<function\s*=\s*([A-Za-z_][A-Za-z0-9_]*)\s*>',
      caseSensitive: false,
    ).firstMatch(block);
    if (functionMatch == null) continue;

    final requestedName = functionMatch.group(1)!.toLowerCase();
    var canonicalName = requestedName;
    String? aliasedDomain;
    if (!allowedTools.containsKey(canonicalName) &&
        requestedName.startsWith('query_')) {
      final domain = requestedName.substring('query_'.length);
      if (AiQueryToolService.domains.contains(domain) &&
          allowedTools.containsKey('query_app_data')) {
        canonicalName = 'query_app_data';
        aliasedDomain = domain;
      }
    }
    final function = allowedTools[canonicalName];
    if (function == null) {
      if (_writeProposalToolNames.contains(canonicalName)) {
        hadDisallowedWriteMarkup = true;
      }
      continue;
    }

    final parameters = function['parameters'];
    final properties = parameters is Map ? parameters['properties'] : null;
    if (parameters is! Map || properties is! Map) continue;
    final arguments = <String, dynamic>{};
    var valid = true;
    final functionBodyStart = functionMatch.end;
    final functionBodyEnd = block.toLowerCase().lastIndexOf('</function>');
    final functionBody = functionBodyEnd >= functionBodyStart
        ? block.substring(functionBodyStart, functionBodyEnd)
        : block.substring(functionBodyStart);
    for (final parameterMatch in RegExp(
      r'<parameter\s*=\s*([A-Za-z_][A-Za-z0-9_]*)\s*>([\s\S]*?)</parameter\s*>',
      caseSensitive: false,
    ).allMatches(functionBody)) {
      final name = parameterMatch.group(1)!;
      final specification = properties[name];
      if (specification is! Map || arguments.containsKey(name)) {
        valid = false;
        break;
      }
      var rawValue = parameterMatch.group(2)!.trim();
      rawValue = rawValue
          .replaceAll('&lt;', '<')
          .replaceAll('&gt;', '>')
          .replaceAll('&quot;', '"')
          .replaceAll('&#39;', "'")
          .replaceAll('&apos;', "'")
          .replaceAll('&amp;', '&');
      final parsedValue = _parseLegacyTextParameterValue(
        rawValue,
        specification,
      );
      if (!parsedValue.valid ||
          (specification['enum'] is List &&
              !(specification['enum'] as List).contains(parsedValue.value))) {
        valid = false;
        break;
      }
      arguments[name] = parsedValue.value;
    }

    if (aliasedDomain != null) {
      if (arguments['domain'] != null && arguments['domain'] != aliasedDomain) {
        valid = false;
      }
      arguments['domain'] = aliasedDomain;
    }
    final requiredParameters = parameters['required'];
    if (requiredParameters is List &&
        requiredParameters.any((name) => !arguments.containsKey(name))) {
      valid = false;
    }
    if (parameters['additionalProperties'] == false &&
        arguments.keys.any((name) => !properties.containsKey(name))) {
      valid = false;
    }
    if (!valid) continue;

    calls.add(
      AiChatFunctionCall(
        id: 'legacy-text-$round-${callIndex++}',
        name: canonicalName,
        arguments: jsonEncode(arguments),
      ),
    );
  }

  final hadToolMarkup = RegExp(
    r'</?tool_call\b',
    caseSensitive: false,
  ).hasMatch(content);
  var cleaned = content.replaceAll(_legacyTextToolBlock, '');
  final malformedStart = RegExp(
    r'<tool_call\b',
    caseSensitive: false,
  ).allMatches(cleaned);
  final malformedToolCall = malformedStart.isEmpty
      ? null
      : malformedStart.first;
  if (malformedToolCall != null) {
    cleaned = cleaned.substring(0, malformedToolCall.start);
  }
  cleaned = cleaned.replaceAll(_legacyTextToolClose, '');
  return (
    content: cleaned,
    calls: calls,
    hadToolMarkup: hadToolMarkup,
    hadDisallowedWriteMarkup: hadDisallowedWriteMarkup,
  );
}

dynamic _decodeLegacyJsonValue(String value) {
  try {
    return jsonDecode(value);
  } catch (_) {
    return null;
  }
}

({bool valid, dynamic value}) _parseLegacyTextParameterValue(
  String rawValue,
  Map specification,
) {
  final rawType = specification['type'];
  final types = rawType is List
      ? rawType.map((type) => type.toString()).toList(growable: false)
      : rawType == null
      ? const <String>[]
      : <String>[rawType.toString()];
  if (rawValue == 'null' && types.contains('null')) {
    return (valid: true, value: null);
  }

  for (final type in types.isEmpty ? const ['json'] : types) {
    final decodedJson = type == 'object' || type == 'array' || type == 'json'
        ? _decodeLegacyJsonValue(rawValue)
        : null;
    final value = switch (type) {
      'string' => rawValue,
      'integer' => int.tryParse(rawValue),
      'number' => num.tryParse(rawValue),
      'boolean' =>
        rawValue.toLowerCase() == 'true'
            ? true
            : rawValue.toLowerCase() == 'false'
            ? false
            : null,
      'object' => decodedJson is Map ? decodedJson : null,
      'array' => decodedJson is List ? decodedJson : null,
      'json' => decodedJson,
      _ => null,
    };
    if (value != null) return (valid: true, value: value);
  }
  return (valid: false, value: null);
}

int? _toInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '');
}

bool _sameStringSet(Set<String> first, Set<String> second) =>
    first.length == second.length && first.containsAll(second);

int? _toPositiveInt(Object? value) {
  final parsed = _toInt(value);
  return parsed != null && parsed > 0 ? parsed : null;
}

double? _toPositiveDouble(Object? value) {
  final parsed = value is num
      ? value.toDouble()
      : double.tryParse(value?.toString() ?? '');
  return parsed != null && parsed.isFinite && parsed > 0 ? parsed : null;
}

int _createdTodoCount(String rawArguments) {
  try {
    final arguments = jsonDecode(rawArguments);
    if (arguments is! Map || arguments['actions'] is! List) return 0;
    var count = 0;
    for (final action in (arguments['actions'] as List).whereType<Map>()) {
      if (action['action'] == 'create_todo') {
        final rawTodos = action['todos'];
        final todos = rawTodos is List ? rawTodos : [action];
        count += todos.where((todo) {
          if (todo is! Map) return false;
          return todo['title']?.toString().trim().isNotEmpty == true;
        }).length;
      } else if (action['action'] == 'create_plan_block' &&
          action['blocks'] is List) {
        count += (action['blocks'] as List)
            .whereType<Map>()
            .where(
              (block) =>
                  block['newTodoTitle']?.toString().trim().isNotEmpty == true,
            )
            .length;
      }
    }
    return count;
  } catch (_) {
    return 0;
  }
}

int _createdFinanceDraftCount(String rawArguments) {
  try {
    final arguments = jsonDecode(rawArguments);
    if (arguments is! Map || arguments['drafts'] is! List) return 0;
    return (arguments['drafts'] as List).whereType<Map>().length;
  } catch (_) {
    return 0;
  }
}

Set<String> _cdtActionNames(String rawArguments) {
  try {
    final decoded = jsonDecode(rawArguments);
    if (decoded is! Map || decoded['actions'] is! List) {
      return const {};
    }
    return (decoded['actions'] as List)
        .whereType<Map>()
        .map((action) {
          final name = action['action']?.toString() ?? '';
          return name == 'bulk_reschedule' ? 'reschedule_todo' : name;
        })
        .where((action) => action.isNotEmpty)
        .toSet();
  } catch (_) {
    return const {};
  }
}

Set<String> _financeActionNames(String rawArguments) {
  try {
    final decoded = jsonDecode(rawArguments);
    if (decoded is! Map || decoded['actions'] is! List) {
      return const {};
    }
    return (decoded['actions'] as List)
        .whereType<Map>()
        .map((action) => action['action']?.toString() ?? '')
        .where((action) => action.isNotEmpty)
        .toSet();
  } catch (_) {
    return const {};
  }
}

String _financeActionLabel(String action) => switch (action) {
  'update_finance' => '修改账单',
  'delete_finance' => '删除账单',
  _ => action,
};

bool _hasNewTodoInPlan(String rawArguments) {
  try {
    final decoded = jsonDecode(rawArguments);
    if (decoded is! Map || decoded['actions'] is! List) return false;
    for (final action in decoded['actions'] as List) {
      if (action is! Map ||
          action['action'] != 'create_plan_block' ||
          action['blocks'] is! List) {
        continue;
      }
      if ((action['blocks'] as List).whereType<Map>().any(
        (block) => block['newTodoTitle']?.toString().trim().isNotEmpty == true,
      )) {
        return true;
      }
    }
    return false;
  } catch (_) {
    return false;
  }
}

String _cdtActionLabel(String action) => switch (action) {
  'create_todo' => '新建待办',
  'create_habit' => '创建习惯',
  'update_habit' => '修改习惯',
  'delete_habit' => '删除习惯',
  'create_schedule' => '新建固定日程',
  'update_schedule' => '修改固定日程',
  'cancel_schedule' => '取消固定日程',
  'delete_schedule' => '删除固定日程',
  'create_plan_block' => '创建规划块',
  'update_plan_block' => '修改规划块',
  'reschedule_plan_blocks' => '重排规划块',
  'delete_plan_block' => '删除规划块',
  'skip_plan_block' => '跳过规划块',
  'start_plan_block_pomodoro' => '打开规划番茄钟',
  'create_time_log' => '创建专注记录',
  'update_time_log' => '修改专注记录',
  'delete_time_log' => '删除专注记录',
  'start_pomodoro' => '启动番茄钟',
  'stop_pomodoro' => '停止番茄钟',
  'create_countdown' => '创建倒计时',
  'update_countdown' => '修改倒计时',
  'complete_countdown' => '完成倒计时',
  'delete_countdown' => '删除倒计时',
  'complete_todo' => '完成待办',
  'skip_todo' => '跳过本期待办',
  'delete_todo' => '删除待办',
  'update_todo' => '修改待办',
  'reschedule_todo' => '改期待办',
  'categorize_todo' => '分类待办',
  'split_todo' => '拆分待办',
  'merge_todos' => '合并待办',
  _ => action,
};

int _createdTodoRemarkCount(String rawArguments) {
  try {
    final arguments = jsonDecode(rawArguments);
    if (arguments is! Map || arguments['actions'] is! List) return 0;
    var count = 0;
    for (final action in (arguments['actions'] as List).whereType<Map>()) {
      if (action['action'] != 'create_todo') continue;
      final rawTodos = action['todos'];
      final todos = rawTodos is List ? rawTodos : [action];
      count += todos.where((todo) {
        if (todo is! Map) return false;
        final title = todo['title']?.toString().trim() ?? '';
        if (title.isEmpty) return false;
        return todo['remark']?.toString().trim().isNotEmpty == true;
      }).length;
    }
    return count;
  } catch (_) {
    return 0;
  }
}

int? _explicitTodoCount(String text) =>
    AiTodoContextBuilder.explicitTodoCreationCount(text);

int? _explicitTodoRemarkCount(String text) {
  if (_explicitTodoCount(text) == null) return null;
  final count = RegExp('备注').allMatches(text).length;
  return count > 1 ? count : null;
}

bool _matchesJsonSchema(Object? value, Map schema) {
  final type = schema['type'];
  if (type is String && !_matchesJsonType(value, type)) return false;
  if (type is List && !type.any((item) => _matchesJsonType(value, '$item'))) {
    return false;
  }

  final enumValues = schema['enum'];
  if (enumValues is List && !enumValues.contains(value)) return false;

  if (value is Map) {
    final required = schema['required'];
    if (required is List &&
        required.whereType<String>().any((key) => !value.containsKey(key))) {
      return false;
    }

    final properties = schema['properties'];
    final knownProperties = <String>{};
    if (properties is Map) {
      for (final entry in properties.entries) {
        final key = entry.key.toString();
        knownProperties.add(key);
        if (value.containsKey(key) &&
            entry.value is Map &&
            !_matchesJsonSchema(value[key], entry.value as Map)) {
          return false;
        }
      }
    }
    if (schema['additionalProperties'] == false &&
        value.keys.any((key) => !knownProperties.contains(key.toString()))) {
      return false;
    }
  }

  if (value is List) {
    final minItems = schema['minItems'];
    final maxItems = schema['maxItems'];
    if (minItems is int && value.length < minItems) return false;
    if (maxItems is int && value.length > maxItems) return false;
    final itemSchema = schema['items'];
    if (itemSchema is Map &&
        value.any((item) => !_matchesJsonSchema(item, itemSchema))) {
      return false;
    }
  }

  return true;
}

bool _matchesJsonType(Object? value, String type) => switch (type) {
  'object' => value is Map,
  'array' => value is List,
  'string' => value is String,
  'number' => value is num,
  'integer' => value is int || (value is num && value % 1 == 0),
  'boolean' => value is bool,
  'null' => value == null,
  _ => true,
};

String _formatPlanningTime(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-'
    '${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')} '
    '${value.hour.toString().padLeft(2, '0')}:'
    '${value.minute.toString().padLeft(2, '0')}';

/// Detects replies that are legitimately asking for missing write details.
/// Shared by native and text-protocol write recovery so neither path turns a
/// clarification into an inferred mutation.
bool _isLikelyClarification(String content) {
  final claimsCompletedMutation = RegExp(
    r'(?:(?:已(?:经)?|成功(?:地)?|刚刚)(?:为你|帮你|把|将)?|(?:我)?帮你|(?:已)?为你)[^。！？\n]{0,20}(?:创建|新建|新增|添加|保存|删除|移除|完成|更新|修改|改期|调整|移动|移至|挪到|挪至|移到|改到|延期|推迟|提前|记录|取消|补记|安排|归类|分到|合并|拆分|开始|启动|开启|停止|结束|执行|搞定|搞好|做好|办好|处理好|弄好)',
  ).hasMatch(content);
  if (claimsCompletedMutation) return false;
  return RegExp(
    r'(?:请提供|请补充|请告诉我|请确认.{0,12}(?:具体)?(?:金额|日期|时间|时段|对象|待办|任务|日程|账单|分类|标签|内容)|还需要(?:提供|补充)|需要你(?:提供|补充|选择)|缺少|缺乏|信息不足|需要明确|尚不清楚|不清楚|不确定|有歧义|无法确定|无法匹配|找不到|没有找到|哪一笔|哪一个|哪个(?:待办|账单|任务|日程)|哪种|哪天|哪一天|什么时间|什么时段|多少(?:元|钱|分钟|小时)?|习惯.{0,8}还是.{0,8}(?:待办|任务)|(?:待办|任务).{0,8}还是.{0,8}习惯|什么(?:待办|任务|日程|习惯|账单|内容|日期|时间|金额|分类|标签))',
  ).hasMatch(content);
}

bool _isSelfContainedPlanningRequest(String text) {
  final request = text.trim();
  if (request.isEmpty || request.length < 18) return false;
  final hasPlanningIntent = RegExp(r'安排|规划|排程|联排').hasMatch(request);
  final hasTimeBoundary = RegExp(
    r'(?:\d{1,2}\s*(?::|：|点)|(?:截止|截至|到|之前).{0,10}(?:晚上|今晚|下午|夜里|早上|上午|中午|\d)|从现在|剩下的时间|今天|明天)',
  ).hasMatch(request);
  final listSeparators = RegExp(r'[、，,；;]|以及|还有|然后|再').allMatches(request);
  return hasPlanningIntent && hasTimeBoundary && listSeparators.length >= 2;
}
