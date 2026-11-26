part of '../ai_tool_chat_runner.dart';

const _writeProposalToolNames = {
  'propose_cdt_actions',
  'propose_finance_drafts',
  'propose_finance_actions',
};

const _cdtActionQueryDomains = {
  'update_todo': {'todos'},
  'complete_todo': {'todos'},
  'skip_todo': {'todos'},
  'delete_todo': {'todos'},
  'reschedule_todo': {'todos'},
  'bulk_reschedule': {'todos'},
  'bulk_reschedule_todo': {'todos'},
  'categorize_todo': {'todos', 'todo_groups'},
  'split_todo': {'todos'},
  'merge_todos': {'todos'},
  'update_schedule': {'fixed_schedules'},
  'cancel_schedule': {'fixed_schedules'},
  'delete_schedule': {'fixed_schedules'},
  'update_plan_block': {'plan_blocks'},
  'reschedule_plan_blocks': {'plan_blocks'},
  'delete_plan_block': {'plan_blocks'},
  'skip_plan_block': {'plan_blocks'},
  'start_plan_block_pomodoro': {'plan_blocks'},
  'update_time_log': {'time_logs'},
  'delete_time_log': {'time_logs'},
  'update_countdown': {'countdowns'},
  'complete_countdown': {'countdowns'},
  'delete_countdown': {'countdowns'},
  'update_todo_group': {'todo_groups'},
  'delete_todo_group': {'todo_groups'},
  'update_pomodoro_tag': {'pomodoro_tags'},
  'delete_pomodoro_tag': {'pomodoro_tags'},
  'update_habit': {'habits'},
  'delete_habit': {'habits'},
};

Set<String> _proposalReferenceDomains(AiChatFunctionCall call) {
  Map<String, dynamic>? arguments;
  try {
    final decoded = jsonDecode(call.arguments);
    if (decoded is Map) arguments = Map<String, dynamic>.from(decoded);
  } catch (_) {
    return const {};
  }
  if (arguments == null) return const {};
  bool hasReference(Map record, Iterable<String> fields) => fields.any(
    (field) => record[field]?.toString().trim().isNotEmpty == true,
  );
  bool hasListReference(Map record, Iterable<String> fields) => fields.any(
    (field) =>
        record[field] is List &&
        (record[field] as List).any(
          (value) => value?.toString().trim().isNotEmpty == true,
        ),
  );
  List<Map> records(Object? value) => value is List
      ? value.whereType<Map>().toList(growable: false)
      : const <Map>[];
  List<Map> recordsFor(Map action, String field) =>
      action[field] is List ? records(action[field]) : [action];

  if (call.name == 'propose_finance_actions') {
    if (arguments['actions'] is! List ||
        (arguments['actions'] as List).isEmpty) {
      return const {};
    }
    final domains = <String>{'finance_transactions'};
    if ((arguments['actions'] as List).whereType<Map>().any(
      (action) =>
          hasReference(action, const ['categoryUuid']) ||
          hasReference(action, const ['paymentMethodUuid']),
    )) {
      domains.add('finance_catalog');
    }
    return domains;
  }
  if (call.name == 'propose_finance_drafts') {
    return records(arguments['drafts']).any(
          (draft) => hasReference(draft, const [
            'categoryUuid',
            'category_uuid',
            'paymentMethodUuid',
            'payment_method_uuid',
          ]),
        )
        ? const {'finance_catalog'}
        : const {};
  }
  if (call.name != 'propose_cdt_actions' || arguments['actions'] is! List) {
    return const {};
  }

  final domains = <String>{};
  for (final action in (arguments['actions'] as List).whereType<Map>()) {
    final actionName = action['action']?.toString();
    domains.addAll(_cdtActionQueryDomains[actionName] ?? const {});
    switch (actionName) {
      case 'create_todo':
        if (hasReference(action, const ['groupId', 'group_id']) ||
            recordsFor(action, 'todos').any(
              (todo) => hasReference(todo, const ['groupId', 'group_id']),
            )) {
          domains.add('todo_groups');
        }
      case 'update_todo' || 'categorize_todo':
        if (recordsFor(action, 'updates').any(
          (update) => hasReference(update, const ['groupId', 'group_id']),
        )) {
          domains.add('todo_groups');
        }
      case 'create_plan_block':
        if (hasReference(action, const ['todoId', 'todo_id', 'todoUuid']) ||
            recordsFor(action, 'blocks').any(
              (block) =>
                  hasReference(block, const ['todoId', 'todo_id', 'todoUuid']),
            )) {
          domains.add('todos');
        }
      case 'create_habit':
        for (final habit in recordsFor(action, 'habits')) {
          final sourceType =
              (habit['sourceType'] ??
                      habit['habitSourceType'] ??
                      habit['source_type'] ??
                      action['sourceType'] ??
                      action['habitSourceType'])
                  ?.toString();
          final hasSourceIds = hasListReference(habit, const [
            'sourceIds',
            'source_ids',
            'habitSourceIds',
            'habit_source_ids',
            'tagUuids',
            'tagIds',
          ]);
          if (!hasSourceIds) continue;
          if (sourceType == 'pomodoroTag') {
            domains.add('pomodoro_tags');
          } else if (sourceType == 'recurringTodo') {
            domains.add('todos');
          }
        }
      case 'create_time_log':
        if (hasListReference(action, const ['tagUuids', 'tagIds']) ||
            recordsFor(action, 'logs').any(
              (log) => hasListReference(log, const ['tagUuids', 'tagIds']),
            )) {
          domains.add('pomodoro_tags');
        }
      case 'start_pomodoro':
        if (hasReference(action, const ['todoId', 'todo_id'])) {
          domains.add('todos');
        }
        if (hasListReference(action, const ['tagUuids', 'tagIds'])) {
          domains.add('pomodoro_tags');
        }
    }
  }
  return domains;
}

Set<String> _matchingQueryCallIdsForProposal(
  AiChatFunctionCall proposal,
  Iterable<AiChatFunctionCall> queryCalls,
) {
  final requiredDomains = _proposalReferenceDomains(proposal);
  if (requiredDomains.isEmpty) return const {};
  final matchingIds = <String>{};
  for (final call in queryCalls) {
    if (call.name == 'query_habits' && requiredDomains.contains('habits')) {
      matchingIds.add(call.id);
      continue;
    }
    Map<String, dynamic> arguments;
    try {
      final decoded = jsonDecode(call.arguments);
      if (decoded is! Map) continue;
      arguments = Map<String, dynamic>.from(decoded);
    } catch (_) {
      continue;
    }
    if (call.name == 'query_app_data' &&
        requiredDomains.contains(arguments['domain']?.toString())) {
      matchingIds.add(call.id);
    } else if (call.name == 'query_finance' &&
        (((arguments['view'] == 'summary' ||
                    arguments['view'] == 'transactions') &&
                requiredDomains.contains('finance_transactions')) ||
            (arguments['view'] == 'catalog' &&
                requiredDomains.contains('finance_catalog')))) {
      matchingIds.add(call.id);
    }
  }
  return matchingIds;
}

Set<String> _queryReferenceDomains(AiChatFunctionCall call) {
  if (call.name == 'query_habits') return const {'habits'};
  Map<String, dynamic> arguments;
  try {
    final decoded = jsonDecode(call.arguments);
    if (decoded is! Map) return const {};
    arguments = Map<String, dynamic>.from(decoded);
  } catch (_) {
    return const {};
  }
  if (call.name == 'query_app_data') {
    final domain = arguments['domain']?.toString();
    return domain == null || domain.isEmpty ? const {} : {domain};
  }
  if (call.name == 'query_finance') {
    return switch (arguments['view']) {
      'summary' || 'transactions' => const {'finance_transactions'},
      'catalog' => const {'finance_catalog'},
      _ => const {},
    };
  }
  return const {};
}

bool _queryReturnsReferenceIds(
  AiChatFunctionCall call,
  Map<String, dynamic> result,
) {
  if (result['ok'] != true) return false;
  Map<String, dynamic> arguments;
  try {
    final decoded = jsonDecode(call.arguments);
    if (decoded is! Map) return false;
    arguments = Map<String, dynamic>.from(decoded);
  } catch (_) {
    return false;
  }
  final view = arguments['view'];
  if ((call.name == 'query_app_data' || call.name == 'query_habits') &&
      view == 'summary') {
    return false;
  }
  if (call.name == 'query_finance' &&
      view != 'transactions' &&
      view != 'catalog') {
    return false;
  }
  final items = result['items'];
  if (items is! List) return false;
  return items.any((item) {
    if (item is! Map) return false;
    return const [
      'id',
      'uuid',
      'todoId',
      'todo_id',
      'transactionId',
      'transaction_id',
      'habitId',
      'habit_id',
    ].any((field) => item[field]?.toString().trim().isNotEmpty == true);
  });
}

String? _writeProposalValidationIssue(
  AiChatFunctionCall call,
  List<Map<String, dynamic>> tools, {
  required String requestText,
  Set<String>? knownTodoIds,
  Set<String>? knownHabitIds,
  Set<String>? knownFinanceTransactionIds,
  Map<String, Set<String>>? knownFinanceCatalogIdsByKind,
  Map<String, Set<String>>? knownReferenceIdsByDomain,
}) {
  Map? parameters;
  for (final tool in tools) {
    final function = tool['function'];
    if (function is Map && function['name'] == call.name) {
      final candidate = function['parameters'];
      if (candidate is Map) parameters = candidate;
      break;
    }
  }
  if (parameters == null) return '本轮没有找到该函数的参数定义';

  Object? decoded;
  try {
    decoded = jsonDecode(call.arguments);
  } catch (_) {
    return '参数不是有效JSON';
  }
  final countdownRoutingIssue = _countdownMutationRoutingIssue(
    decoded,
    requestText: requestText,
  );
  if (countdownRoutingIssue != null) return countdownRoutingIssue;
  if (!_matchesJsonSchema(decoded, parameters)) {
    return '参数不符合本轮工具 schema 或缺少必填字段';
  }
  return _writeProposalSemanticIssue(
    call.name,
    decoded,
    requestText: requestText,
    knownTodoIds: knownTodoIds,
    knownHabitIds: knownHabitIds,
    knownFinanceTransactionIds: knownFinanceTransactionIds,
    knownFinanceCatalogIdsByKind: knownFinanceCatalogIdsByKind,
    knownReferenceIdsByDomain: knownReferenceIdsByDomain,
  );
}

String? _countdownMutationRoutingIssue(
  Object? decoded, {
  required String requestText,
}) {
  if (!AiTodoContextBuilder.isExplicitCountdownMutationRequest(requestText) ||
      AiTodoContextBuilder.isExplicitlyTargetingTodo(requestText) ||
      decoded is! Map ||
      decoded['actions'] is! List) {
    return null;
  }
  final hasTodoUpdate = (decoded['actions'] as List).any(
    (action) => action is Map && action['action'] == 'update_todo',
  );
  if (!hasTodoUpdate) return null;
  return '本轮修改对象是倒计时，但参数使用了待办动作update_todo/todoId。请改用update_countdown，在一个动作对象中提供updates数组，每项使用真实countdownId和title；不要使用titleSnapshot或todoId。';
}

String? _writeProposalSemanticIssue(
  String toolName,
  Object? arguments, {
  required String requestText,
  Set<String>? knownTodoIds,
  Set<String>? knownHabitIds,
  Set<String>? knownFinanceTransactionIds,
  Map<String, Set<String>>? knownFinanceCatalogIdsByKind,
  Map<String, Set<String>>? knownReferenceIdsByDomain,
}) {
  if (toolName == 'propose_finance_drafts') {
    return _validateFinanceDraftProposal(
      arguments,
      knownCatalogIdsByKind: knownFinanceCatalogIdsByKind,
    );
  }
  if (toolName == 'propose_finance_actions') {
    return _validateFinanceActionProposal(
      arguments,
      knownTransactionIds: knownFinanceTransactionIds,
      knownCatalogIdsByKind: knownFinanceCatalogIdsByKind,
    );
  }
  if (toolName != 'propose_cdt_actions') return null;
  if (arguments is! Map || arguments['actions'] is! List) {
    return 'CDT 操作缺少 actions 数组';
  }

  var createdTodoCount = 0;
  var hasCreateTodoAction = false;
  for (final action in (arguments['actions'] as List).whereType<Map>()) {
    final referenceIssue = _validateCdtActionReference(
      action,
      knownTodoIds: knownTodoIds,
      knownHabitIds: knownHabitIds,
      knownReferenceIdsByDomain: knownReferenceIdsByDomain,
    );
    if (referenceIssue != null) return referenceIssue;
    final mutationIssue = _validateCdtMutationAction(
      action,
      requestText: requestText,
      knownReferenceIdsByDomain: knownReferenceIdsByDomain,
    );
    if (mutationIssue != null) return mutationIssue;
    final creationIssue = _validateCdtCreationAction(
      action,
      knownTodoIds: knownTodoIds,
      knownReferenceIdsByDomain: knownReferenceIdsByDomain,
    );
    if (creationIssue != null) return creationIssue;
    if (action['action'] != 'create_todo') continue;
    hasCreateTodoAction = true;
    final rawTodos = action['todos'];
    final todos = rawTodos is List ? rawTodos : [action];
    for (final todo in todos) {
      if (todo is! Map) return 'create_todo 中的每一项都必须是对象';
      final title = todo['title']?.toString().trim() ?? '';
      if (title.isEmpty) return 'create_todo 中的每一项都必须包含非空标题';
      if (const ['date', 'startTime', 'endTime'].any((field) {
        return todo[field]?.toString().trim().isNotEmpty == true;
      })) {
        return '普通待办不能使用旧版 date/startTime/endTime 字段，请仅使用 timeMode 和 dueDate；备注日期应写入remark';
      }
      final rawDueDate = todo['dueDate'];
      final dueDate = rawDueDate == null
          ? null
          : _parseStrictLocalDateTime(rawDueDate);
      if (rawDueDate != null && dueDate == null) {
        return 'create_todo 的dueDate必须是有效的本地日期或yyyy-MM-dd HH:mm时间';
      }
      final timeMode = todo['timeMode']?.toString();
      if ((timeMode == 'deadline' || timeMode == 'dateOnly') &&
          dueDate == null) {
        return '$timeMode待办必须包含有效dueDate';
      }
      if (timeMode == 'unscheduled' && dueDate != null) {
        return '未安排待办不能同时提供dueDate';
      }
      final recurrence = todo['recurrence']?.toString() ?? 'none';
      if (recurrence != 'none' && dueDate == null) {
        return '周期待办必须包含有效dueDate作为周期锚点';
      }
      if (recurrence == 'customDays' &&
          _toPositiveInt(todo['customIntervalDays']) == null) {
        return 'customDays周期待办必须包含正数customIntervalDays';
      }
      final rawRecurrenceEnd = todo['recurrenceEndDate'];
      if (rawRecurrenceEnd != null && !_isStrictDateOnly(rawRecurrenceEnd)) {
        return 'recurrenceEndDate必须是有效的yyyy-MM-dd日期';
      }
      if (rawRecurrenceEnd != null &&
          dueDate != null &&
          _parseStrictLocalDateTime(rawRecurrenceEnd)!
              .isBefore(CalendarDateMath.dateOnly(dueDate))) {
        return 'recurrenceEndDate不能早于待办周期锚点';
      }
      final hasRemarkedMonth = RegExp(
        r'备注.{0,3}(?:正月|腊月|冬月|十[一二]?月|[一二三四五六七八九]月|\d{1,2}月)',
      ).hasMatch(requestText);
      final hasExplicitDeadline = RegExp(
        r'截止|截至|最晚|期限|到期|前完成|之前完成|完成前|deadline',
        caseSensitive: false,
      ).hasMatch(requestText);
      if (hasRemarkedMonth &&
          !hasExplicitDeadline &&
          todo['dueDate']?.toString().trim().isNotEmpty == true) {
        return '用户将月份明确标为备注且未提出截止要求；请把月份保留在remark并清除dueDate/timeMode';
      }
      createdTodoCount++;
    }
  }

  if (hasCreateTodoAction && createdTodoCount < 1) {
    return 'create_todo 至少需要一条待办';
  }
  return null;
}

String? _validateFinanceDraftProposal(
  Object? arguments, {
  Map<String, Set<String>>? knownCatalogIdsByKind,
}) {
  if (arguments is! Map || arguments['drafts'] is! List) {
    return '记账提案缺少drafts数组';
  }
  final drafts = (arguments['drafts'] as List).whereType<Map>().toList();
  if (drafts.isEmpty) return '记账提案至少需要一条账单';
  for (final draft in drafts) {
    final amountIssue = _validateFinanceAmount(draft);
    if (amountIssue != null) return amountIssue;
    final categoryIssue = _validateFinanceCatalogReference(
      draft,
      'categoryUuid',
      'category',
      knownCatalogIdsByKind,
    );
    if (categoryIssue != null) return categoryIssue;
    final paymentMethodIssue = _validateFinanceCatalogReference(
      draft,
      'paymentMethodUuid',
      'payment_method',
      knownCatalogIdsByKind,
    );
    if (paymentMethodIssue != null) return paymentMethodIssue;
    final date = draft['date']?.toString() ?? '';
    if (!isFinanceDateKey(date)) {
      return '每条记账草案都必须包含有效的yyyy-MM-dd日期';
    }
  }
  return null;
}

String? _validateFinanceActionProposal(
  Object? arguments, {
  Set<String>? knownTransactionIds,
  Map<String, Set<String>>? knownCatalogIdsByKind,
}) {
  if (arguments is! Map || arguments['actions'] is! List) {
    return '账单操作提案缺少actions数组';
  }
  final actions = (arguments['actions'] as List).whereType<Map>().toList();
  if (actions.isEmpty) return '账单操作提案至少需要一条操作';
  for (final action in actions) {
    final transactionId = action['transactionId']?.toString().trim();
    if (transactionId?.isNotEmpty != true) {
      return '每条账单操作都必须引用本轮上下文中的transactionId';
    }
    if (knownTransactionIds != null &&
        !knownTransactionIds.contains(transactionId)) {
      return '账单操作引用的transactionId不在当前账单上下文或只读查询结果中，请先查询真实账单';
    }
    final type = action['action']?.toString();
    if (type == 'update_finance') {
      final categoryIssue = _validateFinanceCatalogReference(
        action,
        'categoryUuid',
        'category',
        knownCatalogIdsByKind,
      );
      if (categoryIssue != null) return categoryIssue;
      final paymentMethodIssue = _validateFinanceCatalogReference(
        action,
        'paymentMethodUuid',
        'payment_method',
        knownCatalogIdsByKind,
      );
      if (paymentMethodIssue != null) return paymentMethodIssue;
      const mutableFields = {
        'type',
        'amount',
        'amount_minor',
        'category',
        'categoryUuid',
        'merchant',
        'date',
        'paymentMethod',
        'paymentMethodUuid',
        'note',
      };
      if (!mutableFields.any(action.containsKey)) {
        return 'update_finance必须至少包含一个要修改的字段';
      }
      if (action.containsKey('amount') || action.containsKey('amount_minor')) {
        final amountIssue = _validateFinanceAmount(action);
        if (amountIssue != null) return amountIssue;
      }
      final rawDate = action['date'];
      if (rawDate != null && !isFinanceDateKey(rawDate.toString())) {
        return 'update_finance的date必须是有效的yyyy-MM-dd日期';
      }
    }
  }
  return null;
}

String? _validateFinanceCatalogReference(
  Map record,
  String field,
  String kind,
  Map<String, Set<String>>? knownCatalogIdsByKind,
) {
  final rawId = record[field];
  if (rawId == null) return null;
  final id = rawId.toString().trim();
  if (id.isEmpty) return '$field不能是空字符串；清除选择时请使用null';
  final knownIds = knownCatalogIdsByKind?[kind];
  if (knownIds != null && !knownIds.contains(id)) {
    final label = kind == 'category' ? '分类' : '付款方式';
    return '$field引用的$label不在本地目录或本轮只读查询结果中，请选择真实目录项';
  }
  return null;
}

Set<String> _financeTransactionIdsFromQuery(Map<String, dynamic> result) {
  final items = result['items'];
  if (items is! List) return const {};
  return items
      .whereType<Map>()
      .map((item) {
        return (item['transactionId'] ?? item['transaction_id'] ?? item['id'])
            ?.toString()
            .trim();
      })
      .whereType<String>()
      .where((id) => id.isNotEmpty)
      .toSet();
}

Map<String, Set<String>> _financeCatalogIdsFromQuery(
  Map<String, dynamic> result,
) {
  final items = result['items'];
  if (items is! List) return const {};
  final idsByKind = <String, Set<String>>{};
  for (final item in items.whereType<Map>()) {
    final kind = switch (item['kind']) {
      'category' => 'category',
      'payment_method' => 'payment_method',
      _ => null,
    };
    final id = item['id']?.toString().trim();
    if (kind == null || id == null || id.isEmpty) continue;
    idsByKind.putIfAbsent(kind, () => <String>{}).add(id);
  }
  return idsByKind;
}

String? _validateFinanceAmount(Map record) {
  final rawMinor = record['amount_minor'] ?? record['amountMinor'];
  if (rawMinor != null) {
    final minor = rawMinor is String && RegExp(r'^\d+$').hasMatch(rawMinor)
        ? BigInt.tryParse(rawMinor)
        : rawMinor is int
        ? BigInt.from(rawMinor)
        : null;
    if (minor == null ||
        minor <= BigInt.zero ||
        minor > BigInt.from(maxFinanceAmountMinor)) {
      return 'amount_minor必须是范围内的正数人民币分';
    }
    return null;
  }

  final rawAmount = record['amount'];
  final amount = rawAmount is num
      ? rawAmount.toDouble()
      : double.tryParse(rawAmount?.toString() ?? '');
  if (amount == null ||
      !amount.isFinite ||
      amount <= 0 ||
      amount > maxFinanceAmountMinor / 100) {
    return 'amount必须是范围内的正数金额';
  }
  return null;
}

DateTime? _parseStrictLocalDateTime(Object? value) {
  if (value is! String) return null;
  final match = RegExp(
    r'^(\d{4})-(\d{2})-(\d{2})(?:[ T](\d{2}):(\d{2})(?::(\d{2})(?:\.(\d{1,6}))?)?)?$',
  ).firstMatch(value.trim());
  if (match == null) return null;
  final year = int.parse(match.group(1)!);
  final month = int.parse(match.group(2)!);
  final day = int.parse(match.group(3)!);
  final hour = int.tryParse(match.group(4) ?? '') ?? 0;
  final minute = int.tryParse(match.group(5) ?? '') ?? 0;
  final second = int.tryParse(match.group(6) ?? '') ?? 0;
  final fraction = match.group(7) ?? '';
  if (year == 0 ||
      month < 1 ||
      month > 12 ||
      day < 1 ||
      day > DateTime(year, month + 1, 0).day ||
      hour > 23 ||
      minute > 59 ||
      second > 59) {
    return null;
  }
  final microseconds = fraction.isEmpty
      ? 0
      : int.parse(fraction.padRight(6, '0'));
  return DateTime(
    year,
    month,
    day,
    hour,
    minute,
    second,
    microseconds ~/ 1000,
    microseconds % 1000,
  );
}

bool _isStrictDateOnly(Object? value) =>
    value is String &&
    RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value.trim()) &&
    _parseStrictLocalDateTime(value) != null;
