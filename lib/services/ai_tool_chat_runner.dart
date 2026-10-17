import 'dart:async';
import 'dart:convert';

import 'ai_chat_service.dart';
import 'ai_query_tool_service.dart';
import 'ai_planning_draft_validator.dart';
import 'ai_tool_result_context.dart';
import 'ai_settings_navigation_service.dart';
import 'ai_todo_context_builder.dart';

typedef AiToolRoundStream = Stream<AiChatStreamChunk> Function(
  List<Map<String, dynamic>> messages,
  List<Map<String, dynamic>> tools,
);
typedef AiReadToolExecutor = Future<Map<String, dynamic>> Function(
  AiChatFunctionCall call,
);

/// Continues the same user turn after the app returns read-only tool results.
/// Mutation tools stay proposals handled by the existing confirmation UI.
abstract final class AiToolChatRunner {
  static Stream<AiChatStreamChunk> run({
    required List<Map<String, dynamic>> messages,
    required List<Map<String, dynamic>> tools,
    required AiToolRoundStream streamRound,
    AiToolRoundStream? streamProposalRound,
    required AiReadToolExecutor executeRead,
    Completer<void>? cancelToken,
    bool includeReasoningContent = false,
    bool requirePlanningProposal = false,
    String planningRequestText = '',
    DateTime? planningNow,
    int maxQueryRounds = 4,
    int maxCalls = 8,
  }) async* {
    final history = _initialHistory(
      messages,
      compactForPlanning:
          requirePlanningProposal &&
          _isSelfContainedPlanningRequest(planningRequestText),
    );
    final allowed = {
      for (final tool in tools) (tool['function'] as Map)['name'] as String,
    };
    var callCount = 0;
    var proposalsProduced = false;
    var planningRepairAttempted = false;
    var planningScheduleRepairAttempted = false;
    var actionProposalRepairAttempted = false;
    var actionRepairQueriesUsed = false;
    final planningRequestTime = planningNow ?? DateTime.now();
    final hasWriteProposalTool = tools.any((tool) {
      final name = (tool['function'] as Map)['name'];
      return const {
        'propose_cdt_actions',
        'propose_finance_drafts',
        'propose_finance_actions',
      }.contains(name);
    });
    final hasPlanningTool = tools.any((tool) {
      final function = tool['function'] as Map;
      return function['name'] == 'propose_cdt_actions' &&
          jsonEncode(function['parameters']).contains('create_plan_block');
    });
    final usedIds = <String>{};
    final completedQueries = <String, (String, Map<String, dynamic>)>{};
    var resultChars = 0;
    bool cancelled() => cancelToken?.isCompleted == true;

    for (var round = 0; round <= maxQueryRounds + 1; round++) {
      if (cancelled()) return;
      final finalRound =
          round >= maxQueryRounds ||
          callCount >= maxCalls ||
          resultChars > AiToolResultContext.maxTurnChars - 400;
      final roundTools = tools.where((tool) {
        final name = (tool['function'] as Map)['name'] as String;
        final isQuery = AiQueryToolService.toolNames.contains(name);
        return (!finalRound || !isQuery) &&
            (!proposalsProduced || isQuery) &&
            (!planningRepairAttempted || name == 'propose_cdt_actions') &&
            (!planningScheduleRepairAttempted ||
                name == 'propose_cdt_actions') &&
            // Action recovery may query once to resolve a real local ID; after
            // that, keep only proposals unless a mixed call still has reads
            // left to finish.
            (!actionProposalRepairAttempted ||
                name.startsWith('propose_') ||
                (isQuery && (!actionRepairQueriesUsed || proposalsProduced)));
      }).toList();
      if (finalRound &&
          !planningRepairAttempted &&
          !planningScheduleRepairAttempted) {
        history.add({
          'role': 'system',
          'content':
              '本轮查询次数或数据预算已达上限。不要继续查询或编造数据。'
              '依据已有结果回答；若用户要求生成操作且信息齐全，仍可调用本轮保留的propose_*工具生成待确认草案。'
              '信息不足时说明缺少什么；未调用提案工具时不要声称已生成草案。',
        });
      }
      var content = '';
      var reasoning = '';
      final calls = <AiChatFunctionCall>[];
      final runRound =
          planningRepairAttempted ||
              planningScheduleRepairAttempted ||
              actionProposalRepairAttempted
          ? streamProposalRound ?? streamRound
          : streamRound;
      await for (final chunk in runRound(history, roundTools)) {
        if (cancelled()) return;
        content += chunk.content;
        reasoning += chunk.reasoningContent;
        calls.addAll(chunk.toolCalls);
        yield AiChatStreamChunk(
          // Proposal prose stays buffered until we know whether an actual
          // call arrived. Never flash a false "created/saved" claim.
          content: hasPlanningTool || hasWriteProposalTool ? '' : chunk.content,
          reasoningContent: chunk.reasoningContent,
          // Emit calls only after the complete proposal passes app-side
          // validation. Malformed writes must not reach the action parser.
          finishReason: chunk.finishReason,
          usage: chunk.usage,
          usageSummary: chunk.usageSummary,
        );
      }
      if (cancelled()) return;
      final proposalValidationIssues = <String, String>{};
      var createdTodoCount = 0;
      var createdTodoRemarkCount = 0;
      for (final call in calls) {
        if (!_writeProposalToolNames.contains(call.name)) continue;
        final issue = _writeProposalValidationIssue(call, tools);
        if (issue != null) {
          proposalValidationIssues.putIfAbsent(call.id, () => issue);
        } else if (call.name == 'propose_cdt_actions') {
          createdTodoCount += _createdTodoCount(call.arguments);
          createdTodoRemarkCount += _createdTodoRemarkCount(call.arguments);
        }
      }
      final cdtProposalCalls = calls
          .where((call) => call.name == 'propose_cdt_actions')
          .toList(growable: false);
      final requestedTodoCount = _explicitTodoCount(planningRequestText);
      if (requestedTodoCount != null &&
          cdtProposalCalls.isNotEmpty &&
          createdTodoCount < requestedTodoCount) {
        final issue =
            '用户明确要求 $requestedTodoCount 条待办，当前提案只有 $createdTodoCount 条';
        for (final call in cdtProposalCalls) {
          proposalValidationIssues.putIfAbsent(call.id, () => issue);
        }
      }
      final requestedTodoRemarkCount = _explicitTodoRemarkCount(
        planningRequestText,
      );
      if (requestedTodoRemarkCount != null &&
          cdtProposalCalls.isNotEmpty &&
          createdTodoRemarkCount < requestedTodoRemarkCount) {
        final issue =
            '用户分别提供了 $requestedTodoRemarkCount 份待办备注，当前提案只有 $createdTodoRemarkCount 条带备注的待办';
        for (final call in cdtProposalCalls) {
          proposalValidationIssues.update(
            call.id,
            (existing) => '$existing；$issue',
            ifAbsent: () => issue,
          );
        }
      }
      final invalidWriteProposals = calls
          .where((call) => proposalValidationIssues.containsKey(call.id))
          .toList(growable: false);
      final cdtProposalOnly =
          calls.isNotEmpty &&
          calls.every((call) => call.name == 'propose_cdt_actions');
      if (hasPlanningTool && cdtProposalOnly && invalidWriteProposals.isEmpty) {
        final validationIssue = AiPlanningDraftValidator.validateFromNow(
          requestText: planningRequestText,
          actions: _decodeCdtProposalActions(calls),
          now: planningRequestTime,
        );
        if (validationIssue != null) {
          if (planningScheduleRepairAttempted) {
            yield AiChatStreamChunk(
              content: '这次规划草案未通过时间校验，没有生成确认卡。$validationIssue',
            );
            return;
          }
          planningScheduleRepairAttempted = true;
          history.add({
            'role': 'assistant',
            'content': content,
            if (includeReasoningContent) 'reasoning_content': reasoning,
            'tool_calls': [
              for (final call in calls)
                {
                  'id': call.id,
                  'type': 'function',
                  'function': {'name': call.name, 'arguments': call.arguments},
                },
            ],
          });
          for (final call in calls) {
            history.add({
              'role': 'tool',
              'tool_call_id': call.id,
              'content': jsonEncode({
                'ok': false,
                'status': 'invalid_planning_draft',
                'message': validationIssue,
              }),
            });
          }
          history.add({
            'role': 'system',
            'content':
                '刚才的规划草案未交给App，也没有生成确认卡。$validationIssue'
                '本轮请求时的本地时间是${_formatPlanningTime(planningRequestTime)}。'
                '请重新安排所有可在用户要求时段内完成的任务：从该当前时间开始，'
                '每个规划块必须在截止时间前结束，时间不能互相重叠；确实排不下的任务不要塞入过去或重叠时段，'
                '改为只安排能完成的部分，并在说明中列出未安排的任务。现在直接调用propose_cdt_actions生成新的待确认草案。',
          });
          continue;
        }
      }
      if (calls.isEmpty && hasPlanningTool && !proposalsProduced) {
        final claimsDraft = RegExp(
          r'草案.{0,12}已生成|已(?:生成|创建|新建|保存)|我已为|回复.{0,12}确认.{0,20}保存',
        ).hasMatch(content);
        if (_isLikelyClarification(content)) {
          if (content.isNotEmpty) yield AiChatStreamChunk(content: content);
          return;
        }
        if ((requirePlanningProposal || claimsDraft || hasWriteProposalTool) &&
            !planningRepairAttempted &&
            !planningScheduleRepairAttempted) {
          planningRepairAttempted = true;
          history.add({
            'role': 'assistant',
            'content': content,
            if (includeReasoningContent) 'reasoning_content': reasoning,
          });
          history.add({
            'role': 'system',
            'content':
                '上一条只有文字，没有返回规划工具调用，App没有创建任何待办或规划卡。'
                '用户已要求生成方案，请现在调用propose_cdt_actions提交create_plan_block。'
                '已有待办用真实todoId；不存在的事项用newTodoTitle，不编造ID。'
                '只生成待确认卡，不保存，不再要求回复确认。确实缺少日期或时段时明确说明缺少什么。',
          });
          continue;
        }
        yield AiChatStreamChunk(
          content:
              planningRepairAttempted ||
                  planningScheduleRepairAttempted ||
                  claimsDraft
              ? '模型没有返回可执行的规划草案，本次未创建或保存待办、规划块。请重试生成。'
              : content,
        );
        return;
      }
      if (calls.isEmpty &&
          hasWriteProposalTool &&
          !hasPlanningTool &&
          !proposalsProduced) {
        if (_isLikelyClarification(content)) {
          if (content.isNotEmpty) yield AiChatStreamChunk(content: content);
          return;
        }
        if (!actionProposalRepairAttempted) {
          actionProposalRepairAttempted = true;
          history.add({
            'role': 'assistant',
            'content': content,
            if (includeReasoningContent) 'reasoning_content': reasoning,
          });
          history.add({
            'role': 'system',
            'content':
                '用户明确要求执行数据变更，但上一轮只返回了文字，没有返回函数调用。'
                'App没有生成确认卡，也没有写入任何数据。若目标和必填信息齐全，'
                '现在调用相应的propose_*工具生成待确认操作卡；若缺少目标或信息有歧义，'
                '直接向用户提出必要问题。不得只用文字声称已经操作。',
          });
          continue;
        }
        yield AiChatStreamChunk(
          content: '模型未返回可执行的操作调用；应用没有生成确认卡，也没有写入数据。请重试或补充缺少的信息。',
        );
        return;
      }
      if ((hasPlanningTool || hasWriteProposalTool) &&
          calls.isEmpty &&
          content.isNotEmpty) {
        yield AiChatStreamChunk(content: content);
      }
      if (calls.isEmpty) return;
      final visibleCalls = calls
          .where(
            (call) =>
                allowed.contains(call.name) &&
                !proposalValidationIssues.containsKey(call.id),
          )
          .toList(growable: false);
      if (visibleCalls.isNotEmpty) {
        yield AiChatStreamChunk(toolCalls: visibleCalls);
      }
      // A proposals-only response can be presented immediately as confirmation
      // cards. Mixed read/proposal responses still complete the read cycle.
      final proposalsOnly = calls.every(
        (call) =>
            allowed.contains(call.name) && call.name.startsWith('propose_'),
      );
      if (proposalsOnly && invalidWriteProposals.isEmpty) {
        return;
      }
      if (finalRound &&
          calls.any(
            (call) => AiQueryToolService.toolNames.contains(call.name),
          )) {
        throw StateError('模型在查询次数达到上限后仍返回查询调用');
      }
      history.add({
        'role': 'assistant',
        'content': content,
        if (includeReasoningContent) 'reasoning_content': reasoning,
        'tool_calls': [
          for (final call in calls)
            {
              'id': call.id,
              'type': 'function',
              'function': {'name': call.name, 'arguments': call.arguments},
            },
        ],
      });
      var invalidWriteProposalSeen = false;
      final invalidWriteProposalNames = <String>{};
      final invalidWriteProposalIssues = <String>{};
      final validWriteProposalNames = <String>{};
      for (final call in calls) {
        if (cancelled()) return;
        callCount++;
        Map<String, dynamic> result;
        if (!allowed.contains(call.name)) {
          result = {'ok': false, 'error': '本轮未开放此工具'};
        } else if (!usedIds.add(call.id)) {
          result = {'ok': false, 'error': '重复的工具调用ID，未再次执行'};
        } else if (callCount > maxCalls) {
          result = {'ok': false, 'error': '本轮工具调用次数达到上限'};
        } else if (resultChars > AiToolResultContext.maxTurnChars - 400) {
          result = {'ok': false, 'error': '本轮数据预算达到上限，请根据已有结果回答'};
        } else if (AiQueryToolService.toolNames.contains(call.name)) {
          if (actionProposalRepairAttempted) {
            actionRepairQueriesUsed = true;
          }
          final key = AiToolResultContext.queryKey(call.name, call.arguments);
          final cached = completedQueries[key];
          if (cached != null) {
            result = {...cached.$2, 'reused_tool_call_id': cached.$1};
          } else {
            try {
              result = await executeRead(call)
                  .timeout(const Duration(seconds: 20));
              if (result['ok'] == true) {
                completedQueries[key] = (call.id, result);
              }
            } catch (_) {
              result = {'ok': false, 'error': '本地查询失败或超时，请稍后重试'};
            }
          }
        } else if (_writeProposalToolNames.contains(call.name)) {
          final validationIssue = proposalValidationIssues[call.id];
          if (validationIssue != null) {
            invalidWriteProposalSeen = true;
            invalidWriteProposalNames.add(call.name);
            invalidWriteProposalIssues.add('${call.name}：$validationIssue');
            result = {
              'ok': false,
              'status': 'invalid_arguments',
              'saved': false,
              'message': '写入提案参数未通过本轮工具 schema 校验，App没有生成确认卡，也没有写入数据。',
            };
          } else {
            proposalsProduced = true;
            validWriteProposalNames.add(call.name);
            result = {
              'status': 'awaiting_confirmation',
              'saved': false,
              'message': '操作草案交给App解析并展示确认卡，尚未执行。请用户核对确认。',
            };
          }
        } else if (call.name == AiSettingsNavigationService.toolName) {
          proposalsProduced = true;
          final targets = AiSettingsNavigationService.targetsFromArguments(
            call.arguments,
          );
          result = {
            'ok': targets.isNotEmpty,
            'status': targets.isNotEmpty
                ? 'awaiting_navigation'
                : 'invalid_target',
            'targets': targets,
            'settings_changed': false,
            'message': targets.isNotEmpty
                ? '已生成设置入口卡片，用户点击后进入设置自行调整。'
                : '未找到有效设置入口，不要编造路径。',
          };
        } else {
          proposalsProduced = true;
          result = {
            'status': 'awaiting_confirmation',
            'saved': false,
            'message': '操作草案交给App解析并展示确认卡，尚未执行。请用户核对确认。',
          };
        }
        if (cancelled()) return;
        final modelSource = result.containsKey('reused_tool_call_id')
            ? <String, dynamic>{
                'ok': true,
                'reused_tool_call_id': result['reused_tool_call_id'],
                'message': '相同条件已查询，直接使用该调用的结果；未重复读取或回传明细。',
              }
            : result;
        final remaining = AiToolResultContext.maxTurnChars - resultChars;
        final modelResult = AiToolResultContext.forModel(
          modelSource,
          maxChars: remaining.clamp(400, AiToolResultContext.maxResultChars),
        );
        final encoded = jsonEncode(modelResult);
        resultChars += encoded.length;
        history.add({
          'role': 'tool',
          'tool_call_id': call.id,
          'content': encoded,
        });
        yield AiChatStreamChunk(toolResults: {call.id: result});
      }
      if (invalidWriteProposalSeen) {
        if (actionProposalRepairAttempted || round >= maxQueryRounds + 1) {
          yield AiChatStreamChunk(
            content: validWriteProposalNames.isEmpty
                ? '模型返回的写入参数仍不符合本轮工具格式；应用没有生成有效确认卡，也没有写入数据。请重试或补充信息。'
                : '部分写入函数参数仍不符合本轮工具格式；无效调用没有执行。请检查已生成的操作卡，并补充或重试缺失的操作。',
          );
          return;
        }
        actionProposalRepairAttempted = true;
        proposalsProduced = false;
        history.add({
          'role': 'system',
          'content':
              '上一轮这些写入函数调用未通过参数校验：${invalidWriteProposalIssues.join('；')}。'
              'App没有执行无效调用，也没有写入任何数据。'
              '${validWriteProposalNames.isEmpty ? '现在请修正参数并重新调用对应提案工具。' : '其他有效提案已保留；不要重复它们，只补齐无效调用对应的提案。'}'
              '如果信息不足或意图有歧义，先向用户追问；不要声称已经完成或保存。',
        });
        continue;
      }
    }
  }

  static List<Map<String, dynamic>> _initialHistory(
    List<Map<String, dynamic>> messages, {
    required bool compactForPlanning,
  }) {
    final copied = [
      for (final message in messages) Map<String, dynamic>.from(message),
    ];
    if (!compactForPlanning) return copied;

    final currentUserIndex = copied.lastIndexWhere(
      (message) => message['role'] == 'user',
    );
    if (currentUserIndex < 0) return copied;

    // A complete, explicit schedule is a new planning request even when it is
    // sent in a long-running chat that contains an older pending proposal.
    // Keep the current system instructions and request, while excluding stale
    // proposal summaries and read-only results from the prior turn.
    return [
      for (final message in copied)
        if (message['role'] == 'system') message,
      {
        'role': 'system',
        'content':
            '当前用户消息已明确给出本轮任务和时间要求。请只根据当前请求与本轮查询结果重新生成规划草案；'
            '历史对话中的旧草案和旧答复不属于本轮计划。',
      },
      copied[currentUserIndex],
    ];
  }

  static List<Map<String, dynamic>> _decodeCdtProposalActions(
    List<AiChatFunctionCall> calls,
  ) {
    final actions = <Map<String, dynamic>>[];
    for (final call in calls) {
      if (call.name != 'propose_cdt_actions') continue;
      try {
        final decoded = jsonDecode(call.arguments);
        if (decoded is! Map || decoded['actions'] is! List) continue;
        actions.addAll(
          (decoded['actions'] as List).whereType<Map>().map(
            (item) => Map<String, dynamic>.from(item),
          ),
        );
      } catch (_) {
        // The regular action parser reports malformed arguments as no draft.
      }
    }
    return actions;
  }

  static const _writeProposalToolNames = {
    'propose_cdt_actions',
    'propose_finance_drafts',
    'propose_finance_actions',
  };

  static String? _writeProposalValidationIssue(
    AiChatFunctionCall call,
    List<Map<String, dynamic>> tools,
  ) {
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
    if (!_matchesJsonSchema(decoded, parameters)) {
      return '参数不符合本轮工具 schema 或缺少必填字段';
    }
    return _writeProposalSemanticIssue(call.name, decoded);
  }

  static String? _writeProposalSemanticIssue(
    String toolName,
    Object? arguments,
  ) {
    if (toolName != 'propose_cdt_actions') return null;
    if (arguments is! Map || arguments['actions'] is! List) {
      return 'CDT 操作缺少 actions 数组';
    }

    var createdTodoCount = 0;
    var hasCreateTodoAction = false;
    for (final action in (arguments['actions'] as List).whereType<Map>()) {
      if (action['action'] != 'create_todo') continue;
      hasCreateTodoAction = true;
      final rawTodos = action['todos'];
      final todos = rawTodos is List ? rawTodos : [action];
      for (final todo in todos) {
        if (todo is! Map) return 'create_todo 中的每一项都必须是对象';
        final title = todo['title']?.toString().trim() ?? '';
        if (title.isEmpty) return 'create_todo 中的每一项都必须包含非空标题';
        createdTodoCount++;
      }
    }

    if (hasCreateTodoAction && createdTodoCount < 1) {
      return 'create_todo 至少需要一条待办';
    }
    return null;
  }

  static int _createdTodoCount(String rawArguments) {
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
          return todo['title']?.toString().trim().isNotEmpty == true;
        }).length;
      }
      return count;
    } catch (_) {
      return 0;
    }
  }

  static int _createdTodoRemarkCount(String rawArguments) {
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

  static int? _explicitTodoCount(String text) {
    final isPlanningRequest = RegExp(r'规划|计划块|时间块|安排|排进|排入').hasMatch(text);
    final explicitlyCreatesTodo =
        AiTodoContextBuilder.isExplicitTodoCreationRequest(text) ||
        (!isPlanningRequest &&
            const ['提醒我', '新建', '新增', '创建', '添加'].any(
              (verb) => AiTodoContextBuilder.isExplicitlyRequested(text, verb),
            ));
    if (!explicitlyCreatesTodo) return null;
    final match = RegExp(r'(\d+|[一二两三四五六七八九十]+)\s*(?:个|条|份|项|件)?\s*(?:待办|任务)')
        .firstMatch(text);
    final rawCount = match?.group(1);
    if (rawCount == null) return null;
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

  static int? _explicitTodoRemarkCount(String text) {
    if (_explicitTodoCount(text) == null) return null;
    final count = RegExp('备注').allMatches(text).length;
    return count > 1 ? count : null;
  }

  static bool _matchesJsonSchema(Object? value, Map schema) {
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

  static bool _matchesJsonType(Object? value, String type) => switch (type) {
    'object' => value is Map,
    'array' => value is List,
    'string' => value is String,
    'number' => value is num,
    'integer' => value is int || (value is num && value % 1 == 0),
    'boolean' => value is bool,
    'null' => value == null,
    _ => true,
  };

  static String _formatPlanningTime(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')} '
      '${value.hour.toString().padLeft(2, '0')}:'
      '${value.minute.toString().padLeft(2, '0')}';

  static bool _isLikelyClarification(String content) {
    final claimsCompletedMutation = RegExp(
      r'(?:(?:已(?:经)?|成功(?:地)?|刚刚)(?:为你|帮你|把|将)?|(?:我)?帮你|(?:已)?为你)[^。！？\n]{0,20}(?:创建|新建|新增|添加|保存|删除|移除|完成|更新|修改|改期|调整|移动|移至|挪到|挪至|移到|改到|延期|推迟|提前|记录|取消|补记|安排|归类|分到|合并|拆分|开始|启动|开启|停止|结束|执行|搞定|搞好|做好|办好|处理好|弄好)',
    ).hasMatch(content);
    if (claimsCompletedMutation) return false;
    return RegExp(
      r'(?:请提供|请补充|请告诉我|请确认.{0,12}(?:具体)?(?:金额|日期|时间|时段|对象|待办|任务|日程|账单|分类|标签|内容)|还需要(?:提供|补充)|需要你(?:提供|补充|选择)|缺少|缺乏|信息不足|需要明确|尚不清楚|不清楚|不确定|有歧义|无法确定|无法匹配|找不到|没有找到|哪一笔|哪一个|哪个(?:待办|账单|任务|日程)|哪种|哪天|哪一天|什么时间|什么时段|多少(?:元|钱|分钟|小时)?|习惯.{0,8}还是.{0,8}(?:待办|任务)|(?:待办|任务).{0,8}还是.{0,8}习惯|什么(?:待办|任务|日程|习惯|账单|内容|日期|时间|金额|分类|标签))',
    ).hasMatch(content);
  }

  static bool _isSelfContainedPlanningRequest(String text) {
    final request = text.trim();
    if (request.isEmpty || request.length < 18) return false;
    final hasPlanningIntent = RegExp(r'安排|规划|排程|联排').hasMatch(request);
    final hasTimeBoundary = RegExp(
      r'(?:\d{1,2}\s*(?::|：|点)|(?:截止|截至|到|之前).{0,10}(?:晚上|今晚|下午|夜里|早上|上午|中午|\d)|从现在|剩下的时间|今天|明天)',
    ).hasMatch(request);
    final listSeparators = RegExp(r'[、，,；;]|以及|还有|然后|再').allMatches(request);
    return hasPlanningIntent && hasTimeBoundary && listSeparators.length >= 2;
  }
}
